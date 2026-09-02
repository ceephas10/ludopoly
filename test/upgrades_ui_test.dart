// Les Améliorations à travers la VRAIE interface : les deux interrupteurs
// de l'onglet « Règles du jeu », et l'annonce d'une carte chance tirée en
// partie.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/card_art.dart';
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
      // Un pion sur l'anneau : sans cible possible, la carte n'offrirait
      // aucun menu.
      final mine = c.state.pawnsByColor[c.currentColor]![0];
      mine.location = PawnLocation.ring;
      mine.position = GameController.startIdx(c.currentColor) + 12;
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Choisir un pion'), findsOneWidget,
          reason: 'la carte réclame une cible');
      // Le bouton « Jouer » reste inerte tant qu'aucune cible n'est choisie.
      final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Jouer'));
      expect(button.onPressed, isNull);

      // Cible choisie par le code : la carte part et fait son effet.
      state.playDeferredCard(card, targetPawn: mine);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.upgrades.isInvulnerable(mine), isTrue);

      await shutdownApp(t);
    });
  });

  group('⏱️ Une carte « Après » reste jouable', () {
    testWidgets('le coup automatique ne devance plus la carte', (t) async {
      // Une carte « Après » se joue le dé en main. Quand un seul pion
      // pouvait bouger, le coup partait tout seul en 550 ms et la carte
      // devenait injouable — la spec dit pourtant « et parfois après le
      // lancer ».
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      final card = kDeferredCards
          .singleWhere((x) => x.id == 'DEF_CAPTURE_TO_MY_BOX');
      c.upgrades.addToHand(me, card);

      // UN SEUL coup possible : un pion sur l'anneau, dé de 3.
      final only = c.state.pawnsByColor[me]![0];
      only.location = PawnLocation.ring;
      only.position = GameController.startIdx(me) + 4;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 100));
      expect(c.movablePawns().length, 1);
      expect(c.canPlayDeferred(me, card), isTrue,
          reason: 'le moteur autorise la carte');

      state.playDeferredCard(card);
      await t.pump(const Duration(milliseconds: 100));
      expect(c.upgrades.handOf(me), isNot(contains(card)),
          reason: 'l\'interface doit la laisser partir, elle aussi');
      expect(c.upgrades.captureRuleArmed(me), isTrue);

      await shutdownApp(t);
    });

    testWidgets('sans carte en main, le coup unique part toujours tout seul',
        (t) async {
      // Le comportement demandé plus tôt ne bouge pas d'un pouce.
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      final me = c.currentColor;
      final only = c.state.pawnsByColor[me]![0];
      only.location = PawnLocation.ring;
      only.position = GameController.startIdx(me) + 4;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 100));
      expect(state.autoNotice, contains('part tout seul'));
      await t.pump(const Duration(seconds: 2));
      expect(only.position, GameController.startIdx(me) + 7,
          reason: 'le pion a bien joué seul');

      await shutdownApp(t);
    });
  });

  group('🃏 Les cartes vivent dans UN SEUL bloc', () {
    testWidgets('plus rien n\'est dessiné dans les bases', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);

      final dice6 = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_6');
      c.upgrades.addToHand(c.currentColor, dice6);
      await t.pump(const Duration(milliseconds: 300));

      // La carte est visible UNE fois, et une seule : dans son bloc.
      expect(find.text('Vos cartes chance'), findsOneWidget);
      expect(find.text(dice6.nameFr), findsOneWidget,
          reason: 'un seul endroit, pas un doublon sur le plateau');
      expect(find.byTooltip(dice6.descriptionFr), findsOneWidget,
          reason: 'l\'effet se lit au survol');
      expect(find.text(dice6.timingLabelFr), findsOneWidget,
          reason: 'le moment d\'utilisation est affiché');

      await shutdownApp(t);
    });

    testWidgets('la main tient 4 cartes et le bloc les montre toutes',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      for (int v = 1; v <= 4; v++) {
        c.upgrades.addToHand(
            me, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_$v'));
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(c.upgrades.handOf(me).length, 4);
      for (int v = 1; v <= 4; v++) {
        expect(
            find.text(kDeferredCards
                .singleWhere((x) => x.id == 'DEF_DICE_$v')
                .nameFr),
            findsOneWidget);
      }
      // La 5e est refusée.
      expect(
          c.upgrades.addToHand(
              me, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_5')),
          isFalse);

      await shutdownApp(t);
    });
  });

  group('🎴 Les cartes sont posées FACE CACHÉE dans les bases', () {
    test('le bloc tient dans la base, sous les pions et au-dessus du nom',
        () {
      for (final color in PlayerColor.values) {
        final places = {
          for (int slot = 0; slot < LudoUpgrades.handLimit; slot++)
            BoardView.cardSlotCenter(color, slot),
        };
        expect(places.length, LudoUpgrades.handLimit,
            reason: '${color.name} : autant de places que la main');

        final cx = color == PlayerColor.green || color == PlayerColor.yellow
            ? 9.0
            : 0.0;
        final cy = color == PlayerColor.blue || color == PlayerColor.yellow
            ? 9.0
            : 0.0;
        for (final p in places) {
          final dx = p.dx - cx;
          final dy = p.dy - cy;
          expect(dx, inInclusiveRange(0.5, 5.5),
              reason: '${color.name} : le bloc déborde de la base');
          expect(dy, greaterThan(2.0), reason: 'sous les pions');
          expect(dy, lessThan(4.8), reason: 'au-dessus de l\'étiquette');
        }
      }
    });

    test('c\'est un BLOC : cartes alignées et jointives', () {
      for (final color in PlayerColor.values) {
        final ys = {
          for (int slot = 0; slot < LudoUpgrades.handLimit; slot++)
            BoardView.cardSlotCenter(color, slot).dy,
        };
        expect(ys.length, 1, reason: '${color.name} : une seule rangée');
        final xs = [
          for (int slot = 0; slot < LudoUpgrades.handLimit; slot++)
            BoardView.cardSlotCenter(color, slot).dx,
        ]..sort();
        for (int i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], closeTo(0.90, 1e-9),
              reason: '${color.name} : espacement irrégulier $xs');
        }
      }
    });

    testWidgets('une carte en main montre son DOS, jamais son instruction',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      expect(find.byType(CardBack), findsNothing,
          reason: 'aucune carte, aucun dos');

      final card = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_6');
      c.upgrades.addToHand(me, card);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byType(CardBack), findsOneWidget,
          reason: 'la carte est posée face cachée dans la base');
      expect(find.byType(CardFace), findsNothing,
          reason: 'sa face ne doit PAS être visible');

      await shutdownApp(t);
    });
  });

  group('🔓 La carte tirée S\'OUVRE', () {
    testWidgets('elle se retourne, montre son instruction, puis se referme',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      // Graine 1 : le tirage donne une IMMÉDIATE sans cible à désigner —
      // seules celles-là s'ouvrent d'elles-mêmes.
      c.upgrades.rng = math.Random(1);
      final me = c.currentColor;

      final p = c.state.pawnsByColor[me]![0];
      p.location = PawnLocation.ring;
      p.position = GameController.startIdx(me) + 3;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700)); // pause du dé
      await t.pump(const Duration(seconds: 2));        // trajet + arrivée

      final opened = state.revealedCard;
      expect(opened, isNotNull, reason: 'la carte doit s\'ouvrir');
      // Le retournement passe du dos à la face.
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(CardFace), findsOneWidget,
          reason: 'sa vraie face est montrée');
      expect(find.text(opened!.nameFr), findsWidgets);
      expect(find.text(opened.descriptionFr), findsOneWidget,
          reason: 'avec l\'instruction à suivre');

      // Elle se referme d'elle-même.
      await t.pump(const Duration(seconds: 4));
      expect(state.revealedCard, isNull);
      expect(find.byType(CardFace), findsNothing);

      await shutdownApp(t);
    });

    testWidgets('un clic la referme plus tôt', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      c.upgrades.rng = math.Random(1); // une immédiate sans cible
      final me = c.currentColor;

      final p = c.state.pawnsByColor[me]![0];
      p.location = PawnLocation.ring;
      p.position = GameController.startIdx(me) + 3;
      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 2));
      expect(state.revealedCard, isNotNull);

      state.closeCard();
      await t.pump(const Duration(milliseconds: 200));
      expect(state.revealedCard, isNull);

      await shutdownApp(t);
    });
  });

  group('👆 Toucher une carte de sa base pour la lire et l\'appliquer', () {
    testWidgets('tant qu\'on n\'y touche pas, la face reste cachée',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      final card = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4');
      c.upgrades.addToHand(me, card);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byType(CardBack), findsOneWidget, reason: 'le dos');
      expect(find.byType(CardFace), findsNothing,
          reason: 'rien à voir tant qu\'on n\'a pas touché');
      expect(state.openedHandCard, isNull);

      await shutdownApp(t);
    });

    testWidgets('la toucher la retourne et montre son instruction',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      final card = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4');
      c.upgrades.addToHand(me, card);
      await t.pump(const Duration(milliseconds: 300));

      state.openHandCard(0);
      await t.pump(const Duration(milliseconds: 300));

      expect(state.openedHandCard, card);
      expect(find.byType(CardFace), findsOneWidget);
      expect(find.text(card.descriptionFr), findsOneWidget,
          reason: 'l\'instruction se lit sur la carte');
      expect(find.text('Jouer la carte'), findsOneWidget);

      await shutdownApp(t);
    });

    testWidgets('« Appliquer » joue vraiment la carte', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      final card = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4');
      c.upgrades.addToHand(me, card);
      await t.pump(const Duration(milliseconds: 300));
      state.openHandCard(0);
      await t.pump(const Duration(milliseconds: 300));

      await t.tap(find.widgetWithText(FilledButton, 'Jouer la carte'));
      await t.pump(const Duration(milliseconds: 400));

      expect(c.lastRoll, 4, reason: 'la carte-dé a remplacé le lancer');
      expect(c.upgrades.handOf(me), isEmpty, reason: 'carte consommée');
      expect(state.openedHandCard, isNull, reason: 'la carte se referme');

      await shutdownApp(t);
    });

    testWidgets('on ne peut PAS retourner la carte d\'un autre joueur',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;
      final other =
          PlayerColor.values.firstWhere((x) => x != me);

      c.upgrades.addToHand(
          other, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4'));
      await t.pump(const Duration(milliseconds: 300));

      final board = t.widget<BoardView>(find.byType(BoardView));
      expect(board.tappableCardSeat, me,
          reason: 'seules MES cartes sont cliquables');
      // Même en forçant le clic, rien ne s'ouvre : ce n'est pas ma carte.
      state.openHandCard(0);
      await t.pump(const Duration(milliseconds: 200));
      expect(state.openedHandCard, isNull);
      expect(find.byType(CardFace), findsNothing);

      await shutdownApp(t);
    });

    testWidgets('les cartes d\'un siège ORDINATEUR ne sont pas cliquables',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setChanceEnabled(true);
      state.setAiSeats(PlayerColor.values.toSet());
      await t.pump(const Duration(milliseconds: 300));

      expect(
          t.widget<BoardView>(find.byType(BoardView)).tappableCardSeat,
          isNull,
          reason: 'aucune carte d\'ordinateur ne s\'ouvre au clic');

      await shutdownApp(t);
    });
  });

  group('🤖 L\'ordinateur joue ses cartes différées', () {
    testWidgets('il pose sa carte au lieu de la garder', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      state.setAiSeats(PlayerColor.values.toSet());

      // On garnit les quatre mains : aucune ne doit rester pleine.
      for (final color in PlayerColor.values) {
        for (final id in ['DEF_DICE_6', 'DEF_DICE_5', 'DEF_SKIP_CHOSEN']) {
          c.upgrades.addToHand(
              color, kDeferredCards.singleWhere((x) => x.id == id));
        }
      }
      final before = {
        for (final color in PlayerColor.values)
          color: c.upgrades.handOf(color).length,
      };
      expect(before.values.every((n) => n == 3), isTrue);

      // On laisse la partie tourner.
      for (int i = 0; i < 120; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }

      final after = {
        for (final color in PlayerColor.values)
          color: c.upgrades.handOf(color).length,
      };
      expect(after.values.any((n) => n < 3), isTrue,
          reason: 'au moins un ordinateur doit avoir joué une carte : '
              'avant $before, après $after');

      await shutdownApp(t);
    });
  });

  group('🗂️ Les cartes à la main, dans le centre de commandes', () {
    testWidgets('le panneau propose les deux familles et applique la carte',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);

      expect(find.text('Cartes chance'), findsOneWidget,
          reason: 'le panneau vit à côté de « Jeu manuel »');
      expect(find.text('Immédiates'), findsOneWidget);
      expect(find.text('Différées'), findsOneWidget);

      // Une IMMÉDIATE s'exécute séance tenante.
      final home = kImmediateCards.singleWhere((x) => x.id == 'IMM_PAWN_HOME');
      final me = state.manualPlayerForTest;
      final p = c.state.pawnsByColor[me]![1];
      p.location = PawnLocation.ring;
      p.position = GameController.startIdx(me) + 10;
      state.applyManualCard(home, me, 1);
      await t.pump(const Duration(milliseconds: 300));
      expect(p.location, PawnLocation.base,
          reason: 'la carte a renvoyé le pion 2 dans sa boîte');

      // Une DIFFÉRÉE entre dans la main du joueur visé.
      final dice3 = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_3');
      state.applyManualCard(dice3, PlayerColor.green, 0);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.upgrades.handOf(PlayerColor.green), [dice3]);

      await shutdownApp(t);
    });

    test('chaque carte rend son JSON au format de l\'Annexe A', () {
      for (final card in [...kImmediateCards, ...kDeferredCards]) {
        final j = card.toJson();
        expect(j['id'], card.id);
        expect(j['STATUS'], 'ACTIVE');
        expect(j['NAME_FR'], card.nameFr);
        expect(j['type'],
            card.kind == CardKind.immediate ? 'IMMEDIATE' : 'DEFERRED');
        expect(['PAWN', 'DICE', 'PLAYER', 'CAPTURE'], contains(j['category']));
        expect(
            ['ON_CHANCE', 'BEFORE_ROLL', 'AFTER_ROLL', 'BEFORE_OR_AFTER_ROLL'],
            contains(j['timing']));
        final target = j['target'] as Map;
        expect(['SELF', 'OPPONENT', 'ANY'], contains(target['scope']));
        expect(['PAWN', 'PLAYER'], contains(target['entity']));
        // Et il se sérialise vraiment.
        expect(card.toJsonString(), contains(card.id));
      }
    });
  });

  group('🤫 Une carte DIFFÉRÉE ne se montre pas', () {
    testWidgets('elle file dans la base sans rien révéler', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      // Graine 0 : le tirage donne une DIFFÉRÉE.
      c.upgrades.rng = math.Random(0);
      final me = c.currentColor;

      final p = c.state.pawnsByColor[me]![0];
      p.location = PawnLocation.ring;
      p.position = GameController.startIdx(me) + 3;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 2));

      expect(c.upgrades.handOf(me), hasLength(1),
          reason: 'elle est bien allée dans la base');
      expect(state.revealedCard, isNull,
          reason: 'aucune carte ne s\'ouvre toute seule');
      expect(find.byType(CardFace), findsNothing,
          reason: 'sa face reste cachée : il faudra la toucher');
      expect(find.byType(CardBack), findsOneWidget,
          reason: 'on ne voit que son dos, dans la base');

      await shutdownApp(t);
    });
  });

  group('🛡️ « Pion invulnérable » : le joueur DÉSIGNE son pion', () {
    testWidgets('la carte attend le choix, puis protège celui qu\'on nomme',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      // Graine 41 : le tirage donne « Pion invulnérable ».
      c.upgrades.rng = math.Random(41);
      final me = c.currentColor;

      final lander = c.state.pawnsByColor[me]![0];
      lander.location = PawnLocation.ring;
      lander.position = GameController.startIdx(me) + 3;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 2));

      expect(state.pendingChoiceCard?.id, 'IMM_PAWN_INVULNERABLE',
          reason: 'elle attend qu\'on lui désigne un pion');
      expect(c.upgrades.isInvulnerable(lander), isFalse,
          reason: 'rien n\'est appliqué tant que le choix n\'est pas fait');
      expect(find.text('Choisir un pion'), findsNothing,
          reason: 'le pion qui a déclenché est proposé d\'office');

      // On désigne un AUTRE pion que celui qui a déclenché la carte — mais
      // lui aussi sur l'anneau : on ne protège que ce qui peut être mangé.
      final chosen = c.state.pawnsByColor[me]![2];
      chosen.location = PawnLocation.ring;
      chosen.position = GameController.startIdx(me) + 20;
      state.resolvePendingChoice(chosen);
      await t.pump(const Duration(milliseconds: 300));

      expect(c.upgrades.isInvulnerable(chosen), isTrue,
          reason: 'c\'est le pion DÉSIGNÉ qui est protégé');
      expect(c.upgrades.isInvulnerable(lander), isFalse,
          reason: 'et pas celui qui a déclenché la carte');
      expect(state.pendingChoiceCard, isNull);

      await shutdownApp(t);
    });

    testWidgets('refermer sans choisir protège le pion qui a déclenché',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      c.upgrades.rng = math.Random(41);
      final me = c.currentColor;

      final lander = c.state.pawnsByColor[me]![0];
      lander.location = PawnLocation.ring;
      lander.position = GameController.startIdx(me) + 3;
      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 2));

      state.resolvePendingChoice(null);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.upgrades.isInvulnerable(lander), isTrue,
          reason: 'l\'effet a toujours lieu, on ne peut pas l\'esquiver');

      await shutdownApp(t);
    });

    testWidgets('aucune fenêtre ne s\'ouvre pour un ORDINATEUR', (t) async {
      // Il désigne son pion lui-même : le choix ne doit jamais interrompre
      // sa boucle. Le pion RETENU est vérifié au moteur, sans minuterie.
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      c.upgrades.rng = math.Random(41);
      final me = c.currentColor;
      state.setAiSeats({me});

      final lander = c.state.pawnsByColor[me]![0];
      lander.location = PawnLocation.ring;
      lander.position = GameController.startIdx(me) + 3;

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(seconds: 2));

      expect(state.pendingChoiceCard, isNull,
          reason: 'aucune fenêtre ne s\'ouvre pour un ordinateur');
      expect(c.upgrades.pendingChoice, isNull,
          reason: 'et la carte a bien été résolue, pas laissée en plan');

      await shutdownApp(t);
    });
  });

  group('🎲 « Deux dés » : le centre en montre DEUX', () {
    testWidgets('un seul dé d\'ordinaire, deux sous la carte', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      BoardView board() => t.widget<BoardView>(find.byType(BoardView));
      expect(board().twoDice, isNull, reason: 'un seul dé au départ');

      // La carte « Deux dés » : elle mord au tour SUIVANT.
      c.applyImmediateCard(
          kImmediateCards.singleWhere((x) => x.id == 'IMM_TWO_DICE'),
          c.state.pawnsByColor[me]![0]);
      await t.pump(const Duration(milliseconds: 200));
      expect(board().twoDice, isNull,
          reason: 'le tour du tirage garde un dé unique');

      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true); // redemande un rendu
      await t.pump(const Duration(milliseconds: 200));
      expect(board().twoDice, isNotNull,
          reason: 'à partir du tour suivant, deux dés');

      // Et un vrai lancer donne bien deux faces dont la somme est jouée.
      final total = c.pickDiceValueFor(me);
      final pair = c.upgrades.lastTwoDice!;
      expect(pair.a + pair.b, total,
          reason: 'la somme des deux dés est ce que le pion parcourt');
      expect(pair.a, inInclusiveRange(1, 6));
      expect(pair.b, inInclusiveRange(1, 6));

      // Deux tours plus tard, le dé redevient unique.
      c.upgrades.onTurnCompleted(me);
      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 200));
      expect(board().twoDice, isNull, reason: 'après 2 tours, un seul dé');

      await shutdownApp(t);
    });

    testWidgets('le DOUBLE-dé montre aussi deux dés, la même face deux fois',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      BoardView board() => t.widget<BoardView>(find.byType(BoardView));
      expect(board().twoDice, isNull);

      c.applyImmediateCard(
          kImmediateCards.singleWhere((x) => x.id == 'IMM_DICE_DOUBLE'),
          c.state.pawnsByColor[me]![0]);
      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true); // redemande un rendu
      await t.pump(const Duration(milliseconds: 200));

      expect(board().twoDice, isNotNull,
          reason: 'un 8, un 10 ou un 12 ne tient pas sur une seule face');

      // Chaque lancer : deux fois LA MÊME face, et leur somme est jouée.
      for (int i = 0; i < 50; i++) {
        final total = c.pickDiceValueFor(me);
        final pair = c.upgrades.lastTwoDice!;
        expect(pair.a, pair.b, reason: 'le double, c\'est deux fois pareil');
        expect(pair.a, inInclusiveRange(1, 6));
        expect(pair.a + pair.b, total);
        expect(total.isEven, isTrue);
      }

      // Deux tours plus tard, le dé redevient unique.
      c.upgrades.onTurnCompleted(me);
      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 200));
      expect(board().twoDice, isNull);

      await shutdownApp(t);
    });

    testWidgets('le DEMI-dé reste un seul dé, de 1 à 3', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      c.applyImmediateCard(
          kImmediateCards.singleWhere((x) => x.id == 'IMM_DICE_HALF'),
          c.state.pawnsByColor[me]![0]);
      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 200));

      expect(t.widget<BoardView>(find.byType(BoardView)).twoDice, isNull,
          reason: 'le demi-dé n\'en ajoute pas un second');
      final seen = <int>{for (int i = 0; i < 200; i++) c.pickDiceValueFor(me)};
      expect(seen, {1, 2, 3});

      await shutdownApp(t);
    });
  });

  group('🛡️ Le pion protégé se DISTINGUE des autres', () {
    testWidgets('un repère apparaît sur lui, et sur lui seul', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;
      state.setChanceEnabled(true);
      final me = c.currentColor;

      BoardView board() => t.widget<BoardView>(find.byType(BoardView));
      expect(board().invulnerablePawns, isEmpty,
          reason: 'aucun pion protégé au départ');

      final mine = c.state.pawnsByColor[me]![1];
      mine.location = PawnLocation.ring;
      mine.position = GameController.startIdx(me) + 12;
      c.upgrades.setPawnState(mine, CardPawnState.invulnerable);
      state.setChanceEnabled(true); // redemande un rendu
      await t.pump(const Duration(milliseconds: 300));

      expect(board().invulnerablePawns, {mine},
          reason: 'le repère ne marque que le pion désigné');

      // Deux tours plus tard, l'invulnérabilité tombe et le repère aussi.
      c.upgrades.onTurnCompleted(me);
      c.upgrades.onTurnCompleted(me);
      state.setChanceEnabled(true);
      await t.pump(const Duration(milliseconds: 300));
      expect(board().invulnerablePawns, isEmpty,
          reason: 'plus protégé, plus de repère');

      await shutdownApp(t);
    });
  });
}
