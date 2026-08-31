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
        // Largeur du triangle à cette profondeur : 2 cases. Les milieux des
        // quarts sont donc à -0,75 / -0,25 / +0,25 / +0,75 de l'axe.
        for (final v in along) {
          expect(v.abs(), anyOf(closeTo(0.25, 1e-9), closeTo(0.75, 1e-9)),
              reason: '${color.name} : $along');
        }
        // Pas constant entre voisins.
        final sorted = [...along]..sort();
        for (int i = 1; i < sorted.length; i++) {
          expect(sorted[i] - sorted[i - 1], closeTo(0.5, 1e-9),
              reason: '${color.name} : parts inégales $sorted');
        }
      }
    });

    test('toutes les places restent DANS le triangle', () {
      // Le triangle a son sommet au centre et sa base à 1,5 case. À une
      // profondeur d, sa demi-largeur vaut exactement d.
      for (final color in PlayerColor.values) {
        final out = _outward[color]!;
        final side = Offset(-out.dy, out.dx);
        for (int slot = 0; slot < 4; slot++) {
          final p = BoardView.homeSlotCenter(color, slot) - _apex;
          final depth = p.dx * out.dx + p.dy * out.dy;
          final lateral = (p.dx * side.dx + p.dy * side.dy).abs();
          expect(depth, greaterThan(0),
              reason: '${color.name}#$slot est du mauvais côté du sommet');
          expect(depth, lessThanOrEqualTo(1.5),
              reason: '${color.name}#$slot déborde la base');
          expect(lateral, lessThan(depth),
              reason: '${color.name}#$slot sort par le flanc du triangle '
                  '(latéral $lateral ≥ profondeur $depth)');
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

    test('la profondeur reste celle du placement d\'avant', () {
      // Le point unique historique de chaque couleur, qu'on ne veut pas
      // avoir déplacé : seule la RÉPARTITION latérale est nouvelle.
      const before = {
        PlayerColor.blue: Offset(7.5, 8.5),
        PlayerColor.red: Offset(6.5, 7.5),
        PlayerColor.green: Offset(7.5, 6.5),
        PlayerColor.yellow: Offset(8.5, 7.5),
      };
      for (final entry in before.entries) {
        final out = _outward[entry.key]!;
        final oldDepth = (entry.value - _apex);
        final expected = oldDepth.dx * out.dx + oldDepth.dy * out.dy;
        for (int slot = 0; slot < 4; slot++) {
          final p = BoardView.homeSlotCenter(entry.key, slot) - _apex;
          final depth = p.dx * out.dx + p.dy * out.dy;
          expect(depth, closeTo(expected, 1e-9),
              reason: '${entry.key.name} a changé de profondeur');
        }
      }
    });
  });
}
