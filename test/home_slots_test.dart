// Placement des pions ARRIVÉS dans le triangle de la maison.
//
// Les 4 pions d'une couleur se rangent sur 4 parts égales de l'hypoténuse
// de leur triangle, au lieu de se superposer sur un point unique.
//
// Tout est vérifiable ici : `homeSlotCenter` est une fonction pure, en
// unités de case, sans le moindre widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

/// Sommet des quatre triangles : le centre du plateau.
const _apex = Offset(7.5, 7.5);

/// Direction « vers l'extérieur » de chaque couleur, depuis le sommet.
const _outward = {
  PlayerColor.blue: Offset(0, 1), // sud
  PlayerColor.green: Offset(0, -1), // nord
  PlayerColor.red: Offset(-1, 0), // ouest
  PlayerColor.yellow: Offset(1, 0), // est
};

void main() {
  group('🏠 Les 4 pions se rangent sur l\'hypoténuse de leur triangle', () {
    test('aucun pion ne se superpose à un autre', () {
      for (final color in PlayerColor.values) {
        final places = {
          for (int slot = 0; slot < 4; slot++)
            BoardView.homeSlotCenter(color, slot),
        };
        expect(places.length, 4,
            reason: '${color.name} : ${places.length} places distinctes '
                'au lieu de 4');
      }
    });

    test('les 4 places sont ALIGNÉES, parallèlement à l\'hypoténuse', () {
      for (final color in PlayerColor.values) {
        final out = _outward[color]!;
        // Toutes à la même distance du sommet dans la direction sortante :
        // elles forment donc une ligne parallèle à la base.
        final depths = {
          for (int slot = 0; slot < 4; slot++)
            () {
              final p = BoardView.homeSlotCenter(color, slot) - _apex;
              return (p.dx * out.dx + p.dy * out.dy).toStringAsFixed(6);
            }(),
        };
        expect(depths.length, 1,
            reason: '${color.name} : profondeurs différentes $depths');
      }
    });

    test('elles sont SYMÉTRIQUES par rapport à l\'axe du triangle', () {
      for (final color in PlayerColor.values) {
        final out = _outward[color]!;
        // Axe perpendiculaire à la direction sortante.
        final side = Offset(-out.dy, out.dx);
        final along = [
          for (int slot = 0; slot < 4; slot++)
            () {
              final p = BoardView.homeSlotCenter(color, slot) - _apex;
              return p.dx * side.dx + p.dy * side.dy;
            }(),
        ];
        // Somme nulle = centrées sur l'axe ; et les extrêmes s'opposent.
        expect(along.reduce((a, b) => a + b), closeTo(0, 1e-9),
            reason: '${color.name} : $along');
        expect(along.first, closeTo(-along.last, 1e-9));
        expect(along[1], closeTo(-along[2], 1e-9));
      }
    });

    test('ce sont les MILIEUX de 4 parts égales : 1/8, 3/8, 5/8, 7/8', () {
      for (final color in PlayerColor.values) {
        final out = _outward[color]!;
        final side = Offset(-out.dy, out.dx);
        final along = [
          for (int slot = 0; slot < 4; slot++)
            () {
              final p = BoardView.homeSlotCenter(color, slot) - _apex;
              return p.dx * side.dx + p.dy * side.dy;
            }(),
        ];
        // L'hypoténuse mesure 3 cases. Les milieux des quarts sont donc à
        // -1,125 / -0,375 / +0,375 / +1,125 de l'axe.
        for (final v in along) {
          expect(v.abs(), anyOf(closeTo(0.375, 1e-9), closeTo(1.125, 1e-9)),
              reason: '${color.name} : $along');
        }
        // Pas constant entre voisins.
        final sorted = [...along]..sort();
        for (int i = 1; i < sorted.length; i++) {
          expect(sorted[i] - sorted[i - 1], closeTo(0.75, 1e-9),
              reason: '${color.name} : parts inégales $sorted');
        }
      }
    });

    test('toutes les places sont SUR la ligne de l\'hypoténuse', () {
      // Le triangle a son sommet au centre et sa base à 1,5 case. Être
      // « sur l'hypoténuse » veut donc dire : profondeur exactement 1,5,
      // et latéral strictement dans la largeur de la base.
      for (final color in PlayerColor.values) {
        final out = _outward[color]!;
        final side = Offset(-out.dy, out.dx);
        for (int slot = 0; slot < 4; slot++) {
          final p = BoardView.homeSlotCenter(color, slot) - _apex;
          final depth = p.dx * out.dx + p.dy * out.dy;
          final lateral = (p.dx * side.dx + p.dy * side.dy).abs();
          expect(depth, closeTo(1.5, 1e-9),
              reason: '${color.name}#$slot n\'est pas SUR la base '
                  '(profondeur $depth au lieu de 1,5)');
          expect(lateral, lessThan(1.5),
              reason: '${color.name}#$slot sort par le flanc de la base');
        }
      }
    });

    test('chaque couleur va vers SON côté du plateau', () {
      for (final entry in _outward.entries) {
        for (int slot = 0; slot < 4; slot++) {
          final p = BoardView.homeSlotCenter(entry.key, slot) - _apex;
          final depth = p.dx * entry.value.dx + p.dy * entry.value.dy;
          expect(depth, greaterThan(0),
              reason: '${entry.key.name} doit pointer vers son propre bord');
        }
      }
    });

    test('un slot hors bornes retombe sur une place valide', () {
      // Robustesse : jamais de position aberrante si un id sortait de 0..3.
      for (final color in PlayerColor.values) {
        expect(BoardView.homeSlotCenter(color, -5),
            BoardView.homeSlotCenter(color, 0));
        expect(BoardView.homeSlotCenter(color, 99),
            BoardView.homeSlotCenter(color, 3));
      }
    });

    test('les 4 places tiennent sur la base, sans la déborder', () {
      // L'écart entre les deux extrêmes doit valoir 3 parts de 0,75, soit
      // 2,25 case — donc bien à l'intérieur des 3 cases de la base.
      for (final color in PlayerColor.values) {
        final first = BoardView.homeSlotCenter(color, 0);
        final last = BoardView.homeSlotCenter(color, 3);
        expect((last - first).distance, closeTo(2.25, 1e-9),
            reason: '${color.name} : étalement inattendu');
      }
    });
  });
}
