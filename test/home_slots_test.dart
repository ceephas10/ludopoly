// LES PIONS ARRIVÉS : superposés sur la 6ᵉ case, et plus petits.
//
// « Lorsqu'un pion entre à maison il faut qu'il diminue de forme et
// qu'on le voie superposé dans leur 6ᵉ case. »
//
// Les quatre pions d'une couleur se rangeaient auparavant sur quatre
// parts égales de l'hypoténuse de leur triangle. Ils tiennent désormais
// tous sur la même case — la sixième de leur couloir, celle qui touche le
// centre — et c'est leur TAILLE réduite, plus l'écart de l'empilement,
// qui permet de les compter.
//
// `homeSlotCenter` est une fonction pure, en unités de case : le premier
// groupe se vérifie sans le moindre widget. Le second monte le plateau,
// parce que la réduction, elle, est une affaire de rendu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

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
  group('🏠 Les 4 pions rentrés tiennent sur la 6ᵉ case', () {
    test('les quatre places n\'en font qu\'une', () {
      for (final color in PlayerColor.values) {
        final places = {
          for (int slot = 0; slot < 4; slot++)
            BoardView.homeSlotCenter(color, slot),
        };
        expect(places.length, 1,
            reason: '${color.name} : ${places.length} places au lieu '
                'd\'une seule — les pions rentrés se superposent');
      }
    });

    test('cette case est la 6ᵉ du couloir : une case après la 5ᵉ, '
        'vers le centre', () {
      for (final color in PlayerColor.values) {
        // Les cinq cases du couloir vont de la 0 à la 4 ; la sixième est
        // la suivante, à une case du centre du côté de sa couleur.
        final attendu = _apex + _outward[color]! * 1.0;
        expect(BoardView.homeSlotCenter(color, 0), attendu,
            reason: '${color.name} : la case des pions rentrés');
      }
    });

    test('un rang hors bornes ne casse rien', () {
      for (final color in PlayerColor.values) {
        expect(BoardView.homeSlotCenter(color, -5),
            BoardView.homeSlotCenter(color, 0));
        expect(BoardView.homeSlotCenter(color, 99),
            BoardView.homeSlotCenter(color, 0));
      }
    });

    test('le pion rentré est RÉDUIT, sans devenir un point', () {
      expect(BoardView.retraitMaison, lessThan(1.0),
          reason: 'il doit diminuer');
      expect(BoardView.retraitMaison, greaterThan(0.4),
          reason: 'mais rester un pion qu\'on reconnaît');
    });
  });

  group('🏠 Sur le plateau, le pion rentré rapetisse', () {
    setUp(useLargeSurface);
    tearDown(resetSurface);

    testWidgets('il perd exactement le retrait annoncé, sans se déformer',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      final couleur = state.manualPlayerForTest;

      // On rentre un pion PAR LE PANNEAU, comme on le ferait à la main :
      // « Pions maison », rangée « Combien », bouton 1.
      await t.tap(find.byKey(const ValueKey('home-count-1')));
      await t.pump(const Duration(milliseconds: 400));

      final pions = c.state.pawnsByColor[couleur]!;
      final rentre = pions.firstWhere((p) => p.location == PawnLocation.home);
      final dehors = pions.firstWhere((p) => p.location != PawnLocation.home);

      // Deux pions de la MÊME couleur au même instant : le seul écart
      // entre eux est d'être rentré ou non.
      final petit = t.getSize(
          find.byKey(ValueKey('pawn_${couleur.name}_${rentre.id}')));
      final grand = t.getSize(
          find.byKey(ValueKey('pawn_${couleur.name}_${dehors.id}')));

      expect(petit.height, lessThan(grand.height),
          reason: 'le pion rentré doit diminuer');
      expect(petit.height / grand.height,
          closeTo(BoardView.retraitMaison, 0.001),
          reason: 'exactement du retrait annoncé');
      expect(petit.width / grand.width,
          closeTo(BoardView.retraitMaison, 0.001),
          reason: 'et sans se déformer : la largeur suit la hauteur');

      await shutdownApp(t);
    });
  });
}
