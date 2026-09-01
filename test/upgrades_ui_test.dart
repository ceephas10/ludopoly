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

  group('🗃️ Les 4 emplacements de cartes dans les bases', () {
    test('ils sont rangés dans la base, sans toucher pions ni étiquette',
        () {
      for (final color in PlayerColor.values) {
        final places = {
          for (int slot = 0; slot < 4; slot++)
            BoardView.cardSlotCenter(color, slot),
        };
        expect(places.length, 4,
            reason: '${color.name} : 4 emplacements distincts');

        for (int slot = 0; slot < 4; slot++) {
          final p = BoardView.cardSlotCenter(color, slot);
          // Coin de la base : (0,0) (9,0) (0,9) (9,9) selon la couleur.
          final cx = color == PlayerColor.green || color == PlayerColor.yellow
              ? 9.0
              : 0.0;
          final cy = color == PlayerColor.blue || color == PlayerColor.yellow
              ? 9.0
              : 0.0;
          final dx = p.dx - cx;
          final dy = p.dy - cy;
          // Dans l'aire blanche intérieure (0,5 → 5,5 depuis le coin).
          expect(dx, inInclusiveRange(0.5, 5.5),
              reason: '${color.name}#$slot déborde de la base');
          expect(dy, inInclusiveRange(0.5, 5.5));
          // Sous les pions (rangés vers 1,1) et au-dessus de l'étiquette
          // du joueur (posée vers 5,5).
          expect(dy, greaterThan(2.0),
              reason: '${color.name}#$slot chevaucherait les pions');
          expect(dy, lessThan(4.8),
              reason: '${color.name}#$slot chevaucherait l\'étiquette');
        }
      }
    });

    test('les 4 sont alignés et régulièrement espacés', () {
      for (final color in PlayerColor.values) {
        final ys = {
          for (int slot = 0; slot < 4; slot++)
            BoardView.cardSlotCenter(color, slot).dy,
        };
        expect(ys.length, 1, reason: '${color.name} : une seule rangée');
        final xs = [
          for (int slot = 0; slot < 4; slot++)
            BoardView.cardSlotCenter(color, slot).dx,
        ]..sort();
        for (int i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], closeTo(1.0, 1e-9),
              reason: '${color.name} : espacement irrégulier $xs');
        }
      }
    });

    testWidgets('4 emplacements par couleur, vides puis remplis', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;

      // Une carte en main, mais les cases Chance encore éteintes : aucun
      // emplacement ne se dessine sur le plateau.
      final dice6 = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_6');
      c.upgrades.addToHand(PlayerColor.red, dice6);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip(dice6.nameFr), findsNothing,
          reason: 'pas de cases Chance, pas de cartes sur le plateau');

      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 300));

      final board = t.widget<BoardView>(find.byType(BoardView));
      expect(board.deferredHands.keys.length, 4,
          reason: 'les 4 couleurs ont leur rangée');
      expect(board.deferredHands[PlayerColor.red], [dice6]);
      for (final color in PlayerColor.values.where((x) => x != PlayerColor.red)) {
        expect(board.deferredHands[color], isEmpty,
            reason: '${color.name} n\'a rien tiré');
      }
      expect(find.byTooltip(dice6.nameFr), findsOneWidget,
          reason: 'la carte posée dans la base porte son nom');

      await shutdownApp(t);
    });

    testWidgets('une carte tirée EN PARTIE apparaît dans la base du joueur',
        (t) async {
      // Le vrai chemin, de bout en bout : le pion tombe sur une case
      // Chance, le tirage donne une différée, elle se range en main — et
      // elle doit se voir dans la base, sans autre intervention.
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      ChanceCard? drawn;
      for (int attempt = 0; attempt < 40 && drawn == null; attempt++) {
        // On replace le pion à 3 pas de la case Chance et on relance.
        final p = c.state.pawnsByColor[me]![0];
        p.location = PawnLocation.ring;
        p.position = GameController.startIdx(me) + 3;
        c.currentPlayerIdx = c.turnOrder.indexOf(me);
        c.phase = TurnPhase.rolling;
        state.rollManualForTest(3);
        await t.pump(const Duration(milliseconds: 700));
        await t.pump(const Duration(seconds: 2));
        final hand = c.upgrades.handOf(me);
        if (hand.isNotEmpty) drawn = hand.first;
      }

      expect(drawn, isNotNull,
          reason: 'une chance sur deux : une différée doit finir par tomber');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip(drawn!.nameFr), findsOneWidget,
          reason: 'la carte tirée en partie doit se voir dans la base');

      await shutdownApp(t);
    });
  });
}
