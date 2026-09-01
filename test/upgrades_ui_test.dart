// Les Améliorations à travers la VRAIE interface : les deux interrupteurs
// de l'onglet « Règles du jeu », et l'annonce d'une carte chance tirée en
// partie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  Future<void> openRules(WidgetTester t) async {
    await t.tap(find.text('Règles du jeu'));
    await t.pump(const Duration(milliseconds: 300));
  }

  /// L'interrupteur qui vit dans la même ligne que [label].
  Finder switchOf(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );

  group('🎛️ Les interrupteurs des Améliorations', () {
    testWidgets('éteints par défaut, allumables et re-éteignables', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      await openRules(t);

      // La carte existe, avec ses deux lignes.
      expect(find.text('Améliorations LudoPoly'), findsOneWidget);
      expect(find.text('Cases Vortex / Trou noir'), findsOneWidget);
      expect(find.text('Cases Chance'), findsOneWidget);
      expect(state.controller.upgrades.vortexEnabled, isFalse);
      expect(state.controller.upgrades.chanceEnabled, isFalse);

      await t.ensureVisible(switchOf('Cases Vortex / Trou noir'));
      await t.tap(switchOf('Cases Vortex / Trou noir'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.controller.upgrades.vortexEnabled, isTrue);
      expect(state.controller.upgrades.chanceEnabled, isFalse,
          reason: 'les deux interrupteurs sont indépendants');

      await t.ensureVisible(switchOf('Cases Chance'));
      await t.tap(switchOf('Cases Chance'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.controller.upgrades.chanceEnabled, isTrue);

      await t.tap(switchOf('Cases Vortex / Trou noir'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.controller.upgrades.vortexEnabled, isFalse,
          reason: 'l\'interrupteur doit aussi ÉTEINDRE');

      await shutdownApp(t);
    });

    testWidgets('le plateau dessine les cases quand on allume', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      BoardView board() => t.widget<BoardView>(find.byType(BoardView));
      expect(board().showVortexCells, isFalse);
      expect(board().showChanceCells, isFalse);

      state.setVortexEnabled(true);
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 300));
      expect(board().showVortexCells, isTrue,
          reason: 'les spirales Vortex doivent se dessiner');
      expect(board().showChanceCells, isTrue,
          reason: 'les cases « ? » doivent se dessiner');

      await shutdownApp(t);
    });
  });

  group('🎰 Une carte chance tirée en partie est ANNONCÉE', () {
    testWidgets('atterrir sur la case Chance affiche la carte au panneau',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);

      // Le pion 0 du joueur courant à 3 pas de sa case Chance ; dé 3 → il
      // s'y pose (seul coup possible : il part tout seul après la pause).
      final p = c.state.pawnsByColor[c.currentColor]![0];
      p.location = PawnLocation.ring;
      p.position = GameController.startIdx(c.currentColor) + 3;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700)); // pause du dé
      await t.pump(const Duration(seconds: 2));        // trajet + arrivée

      expect(c.upgrades.doneTurns, isNotNull);
      expect(find.textContaining('Carte chance'), findsOneWidget,
          reason: 'le joueur doit VOIR quelle carte est tombée');

      await shutdownApp(t);
    });
  });
}
