// La carte des cases de l'anneau, verrouillée sur les groupes annoncés.
//
// Le JSON se recalcule depuis la géométrie du plateau : ces tests sont là
// pour qu'il ne puisse jamais dire autre chose que ce que le jeu fait.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/board_path.dart';
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/game/ring_map.dart';
import 'package:ludopoly/game/upgrades.dart';

void main() {
  group('🗺️ Les groupes de cases, un par fonction', () {
    test('les cinq familles portent exactement les cases annoncées', () {
      expect(cellsWithFunction(RingFunction.start), [0, 13, 26, 39]);
      expect(cellsWithFunction(RingFunction.vortexGood), [1, 14, 27, 40]);
      expect(cellsWithFunction(RingFunction.vortexBad), [5, 18, 31, 44]);
      expect(cellsWithFunction(RingFunction.chance), [6, 19, 32, 45]);
      expect(cellsWithFunction(RingFunction.safeStar), [8, 21, 34, 47]);
    });

    test('les 52 cases sont classées, une fois chacune', () {
      final seen = <int>[];
      for (final f in RingFunction.values) {
        seen.addAll(cellsWithFunction(f));
      }
      expect(seen.length, ring.length, reason: 'aucune case en double');
      expect(seen.toSet().length, ring.length);
      expect(seen.toSet(), {for (int i = 0; i < ring.length; i++) i});
    });

    test('les 20 cases spéciales ne se chevauchent jamais', () {
      final special = <int>{};
      for (final f in const [
        RingFunction.start,
        RingFunction.vortexGood,
        RingFunction.vortexBad,
        RingFunction.chance,
        RingFunction.safeStar,
      ]) {
        for (final id in cellsWithFunction(f)) {
          expect(special.add(id), isTrue,
              reason: 'la case $id porterait deux fonctions');
        }
      }
      expect(special.length, 20);
      expect(cellsWithFunction(RingFunction.normal).length, 32);
    });

    test('chaque case spéciale est à son pas fixe du départ de SA couleur',
        () {
      const expected = {
        RingFunction.start: 0,
        RingFunction.vortexGood: 1,
        RingFunction.chance: 6,
        RingFunction.safeStar: 8,
        RingFunction.vortexBad: SpecialCells.lastStraightStep,
      };
      for (final entry in expected.entries) {
        for (final c in PlayerColor.values) {
          final id = (startIndexOf[c]! + entry.value) % ring.length;
          expect(ringFunctionOf(id), entry.key,
              reason: '${c.name} + ${entry.value} pas → case $id');
        }
      }
    });

    test('les cases sûres du moteur sont bien les départs et les étoiles',
        () {
      for (int id = 0; id < ring.length; id++) {
        final f = ringFunctionOf(id);
        final shouldBeSafe =
            f == RingFunction.start || f == RingFunction.safeStar;
        expect(ring[id].isSafe, shouldBeSafe,
            reason: 'case $id : le plateau et la carte doivent s\'accorder');
      }
    });

    test('la case Chance n\'appartient à personne, les autres si', () {
      final map = ringMapJson();
      final groups = map['groups']! as List;
      for (final g in groups.cast<Map<String, Object?>>()) {
        final f = g['function'] as String;
        if (f == 'CHANCE' || f == 'NORMAL') {
          expect(g.containsKey('byColor'), isFalse,
              reason: '$f n\'appartient à aucune couleur');
        } else {
          expect(g['byColor'], isNotNull, reason: '$f a un propriétaire');
        }
      }
    });
  });

  group('🗺️ Le JSON lui-même', () {
    test('il décrit les 52 cases, avec leur place sur la grille 15×15', () {
      final map = ringMapJson();
      final cells = (map['cells']! as List).cast<Map<String, Object?>>();
      expect(cells.length, 52);
      for (final cell in cells) {
        final id = cell['id']! as int;
        expect(cell['grid'], gridIndexOf(id));
        expect(cell['col'], inInclusiveRange(0, 14));
        expect(cell['row'], inInclusiveRange(0, 14));
        // Les pas depuis chaque couleur, et la case du propriétaire à 0.
        final steps = (cell['steps']! as Map).cast<String, int>();
        expect(steps.length, 4);
        for (final c in PlayerColor.values) {
          expect(steps[c.name],
              (id - startIndexOf[c]! + ring.length) % ring.length);
        }
      }
    });

    test('les repères de grille des trous noirs : 81, 99, 143, 125', () {
      // Les quatre nombres donnés à la main, retrouvés par la carte.
      expect(gridIndexOf(SpecialCells.badVortexCell(PlayerColor.green)), 81);
      expect(gridIndexOf(SpecialCells.badVortexCell(PlayerColor.yellow)), 99);
      expect(gridIndexOf(SpecialCells.badVortexCell(PlayerColor.blue)), 143);
      expect(gridIndexOf(SpecialCells.badVortexCell(PlayerColor.red)), 125);
    });

    test('il se sérialise et se relit sans perte', () {
      final text = ringMapJsonString();
      final back = jsonDecode(text) as Map<String, Object?>;
      expect(back['ringSize'], 52);
      expect((back['cells']! as List).length, 52);
      expect((back['groups']! as List).length, RingFunction.values.length);
      final colors = (back['colors']! as Map).cast<String, Object?>();
      expect(colors.keys.toSet(),
          {for (final c in PlayerColor.values) c.name});
    });

    test('chaque couleur y trouve ses cinq cases et sa diagonale', () {
      final colors =
          (ringMapJson()['colors']! as Map).cast<String, Map<String, Object?>>();
      for (final c in PlayerColor.values) {
        final e = colors[c.name]!;
        expect(e['start'], startIndexOf[c]);
        expect(e['vortexGood'], SpecialCells.goodVortexCell(c));
        expect(e['vortexBad'], SpecialCells.badVortexCell(c));
        expect(e['chance'], SpecialCells.chanceCellOf(c));
        expect(e['diagonal'], SpecialCells.diagonalOf[c]!.name);
        // La dernière case d'anneau avant son couloir.
        expect(e['lastRingCell'], (startIndexOf[c]! + 50) % 52);
      }
    });
  });
}
