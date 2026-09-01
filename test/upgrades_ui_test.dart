// Les Améliorations à travers la VRAIE interface : les deux interrupteurs
// de l'onglet « Règles du jeu », et l'annonce d'une carte chance tirée en
// partie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/upgrades.dart';
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

      expect(
          find.textContaining(
              RegExp('Carte chance|Carte différée|Vortex|Trou noir')),
          findsWidgets,
          reason: 'le joueur doit VOIR ce qui est tombé');

      await shutdownApp(t);
    });
  });

  group('🎴 La main de cartes différées', () {
    testWidgets('absente tant que le joueur n\'a aucune carte', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Vos cartes chance'), findsNothing,
          reason: 'pas de carte, pas de panneau');

      await shutdownApp(t);
    });

    testWidgets('une carte-dé s\'affiche et REMPLACE le lancer', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);

      final dice4 =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4');
      c.upgrades.addToHand(c.currentColor, dice4);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Vos cartes chance'), findsOneWidget);
      expect(find.text(dice4.nameFr), findsOneWidget);

      state.playDeferredCard(dice4);
      await t.pump(const Duration(milliseconds: 300));

      expect(c.lastRoll, 4,
          reason: 'la carte-dé doit valoir un lancer de 4');
      expect(c.upgrades.handOf(c.currentColor), isEmpty,
          reason: 'la carte est consommée');

      await shutdownApp(t);
    });

    testWidgets('une carte à cible attend qu\'on désigne un pion',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);

      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_PAWN_INVULNERABLE');
      c.upgrades.addToHand(c.currentColor, card);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Choisir un pion'), findsOneWidget,
          reason: 'la carte réclame une cible');
      // Le bouton « Jouer » reste inerte tant qu'aucune cible n'est choisie.
      final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Jouer'));
      expect(button.onPressed, isNull);

      // Cible choisie par le code : la carte part et fait son effet.
      final mine = c.state.pawnsByColor[c.currentColor]![0];
      state.playDeferredCard(card, targetPawn: mine);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.upgrades.isInvulnerable(mine), isTrue);

      await shutdownApp(t);
    });
  });
}
