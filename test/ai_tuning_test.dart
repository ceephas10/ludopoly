// Les deux réglages de l'ordinateur, testés À TRAVERS L'INTERFACE :
// le Mode Accélérateur (centre de commandes) et l'échelle de difficulté
// (règles du jeu).
//
// Le comportement de l'échelle elle-même est couvert dans `rules_test.dart`,
// côté moteur. Ici on vérifie le CÂBLAGE : que les boutons existent, qu'ils
// sont exclusifs, qu'ils changent bien l'état du jeu, et surtout que
// l'accélérateur ne touche QUE les tours de l'ordinateur.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/ai_difficulty.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  /// Ouvre l'onglet « Règles du jeu » du panneau.
  Future<void> openRules(WidgetTester t) async {
    await t.tap(find.text('Règles'));
    await t.pump(const Duration(milliseconds: 300));
  }

  group('⚡ Mode Accélérateur IA', () {
    testWidgets('absent au démarrage, activable, et désactivable', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      expect(find.text('Mode Accélérateur IA'), findsOneWidget,
          reason: 'le bouton vit dans le centre de commandes');
      expect(state.aiTurbo, isFalse, reason: 'éteint au lancement');
      expect(find.text('⚡ ACTIF'), findsNothing);

      await t.tap(find.text('Mode Accélérateur IA'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.aiTurbo, isTrue);
      expect(find.text('⚡ ACTIF'), findsOneWidget,
          reason: "l'état actif doit se voir");

      await t.tap(find.text('Mode Accélérateur IA'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.aiTurbo, isFalse);
      expect(find.text('⚡ ACTIF'), findsNothing);
      await shutdownApp(t);
    });

    testWidgets('divise par deux les délais — mais SEULEMENT pour une IA',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      const ref = Duration(milliseconds: 900);

      // Aucun siège ordinateur : rien n'est jamais accéléré.
      state.setAiSeats(const {});
      state.aiTurbo = true;
      expect(state.paceForTest(ref), ref,
          reason: 'sans IA en jeu, aucun délai ne change');

      // Le tour courant est bleu. Bleu confié à l'ordinateur → accéléré.
      state.setAiSeats({state.currentColor});
      expect(state.paceForTest(ref), const Duration(milliseconds: 450));

      // Accélérateur éteint : on retrouve le rythme normal.
      state.aiTurbo = false;
      expect(state.paceForTest(ref), ref);
      await shutdownApp(t);
    });

    testWidgets('un tour HUMAIN garde son rythme même accélérateur allumé',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      const ref = Duration(milliseconds: 900);

      // Tous les sièges SAUF le joueur courant sont des ordinateurs.
      final human = state.currentColor;
      state.setAiSeats(
          PlayerColor.values.where((c) => c != human).toSet());
      state.aiTurbo = true;

      expect(state.paceForTest(ref), ref,
          reason: "c'est au tour d'un humain : pas d'accélération");
      expect(state.paceForTest(ref, ai: true),
          const Duration(milliseconds: 450),
          reason: 'un coup explicitement marqué IA est bien accéléré');
      await shutdownApp(t);
    });
  });

  group('⚡ Mode Rapide — sans attente de tour', () {
    testWidgets('le bouton existe, bascule, et pilote le moteur', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      await openRules(t);

      expect(find.text('Rapide — sans attente de tour'), findsOneWidget);
      expect(state.controller.fastMode, isFalse, reason: 'éteint au départ');

      // L'interrupteur de SA ligne — `Switch.last` visait le dernier de
      // l'onglet, et la carte Améliorations en a ajouté deux après lui.
      final fastSwitch = find.descendant(
        of: find
            .ancestor(
                of: find.text('Rapide — sans attente de tour'),
                matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );

      await t.ensureVisible(fastSwitch);
      await t.tap(fastSwitch);
      await t.pump(const Duration(milliseconds: 400));
      expect(state.controller.fastMode, isTrue);

      await t.tap(fastSwitch);
      await t.pump(const Duration(milliseconds: 400));
      expect(state.controller.fastMode, isFalse,
          reason: 'le bouton doit aussi DÉSACTIVER le mode');

      await shutdownApp(t);
    });

    testWidgets('les ordinateurs jouent en parallèle, sans attendre un tour',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      // Les quatre couleurs à l'ordinateur : la partie doit avancer toute
      // seule, et surtout PLUSIEURS couleurs doivent progresser sans que
      // l'une attende l'autre.
      state.setAiSeats(PlayerColor.values.toSet());
      state.setFastMode(true);

      // On observe quelles couleurs ont sorti au moins un pion.
      final progressed = <PlayerColor>{};
      for (int i = 0; i < 400; i++) {
        await t.pump(const Duration(milliseconds: 100));
        for (final c in PlayerColor.values) {
          final out = state.controller.state.pawnsByColor[c]!
              .any((p) => p.location != PawnLocation.base);
          if (out) progressed.add(c);
        }
        if (progressed.length == 4) break;
      }

      expect(progressed.length, 4,
          reason: 'les 4 couleurs doivent avoir progressé sans intervention, '
              'or seules $progressed ont bougé');

      await shutdownApp(t);
    });

    testWidgets('chaque couleur garde SON dé pendant que les autres jouent',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats({PlayerColor.red, PlayerColor.green});
      state.setFastMode(true);

      await t.pump(const Duration(seconds: 4));

      // Les sièges existent et sont indépendants : aucun n'écrase l'autre.
      final seats = {
        for (final c in PlayerColor.values) c: state.controller.seatOf(c),
      };
      expect(seats.length, 4);
      // Le siège humain n'a jamais été joué par personne : il attend.
      expect(state.controller.seatOf(PlayerColor.blue).phase,
          anyOf(TurnPhase.rolling, TurnPhase.moving),
          reason: 'le siège humain ne doit pas être piloté par le mode');

      await shutdownApp(t);
    });

    testWidgets('revenir en mode ordinaire rétablit le tour par tour',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats({PlayerColor.red});
      state.setFastMode(true);
      await t.pump(const Duration(seconds: 2));

      state.setFastMode(false);
      await t.pump(const Duration(milliseconds: 500));

      expect(state.controller.fastMode, isFalse);
      expect(find.byType(BoardScreen), findsOneWidget,
          reason: 'la bascule ne doit pas casser la partie en cours');

      await shutdownApp(t);
    });
  });

  group('🎲 Le choix sur un 6, à travers l\'interface', () {
    testWidgets('un 6 après une sortie propose encore les 4 pions',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;

      c.roll(6);
      await t.pump(const Duration(milliseconds: 700));
      c.movePawn(c.state.pawnsByColor[c.currentColor]![0]);
      await t.pump(const Duration(seconds: 2));

      c.roll(6);
      await t.pump(const Duration(milliseconds: 100));
      expect(c.movablePawns().length, 4,
          reason: 'le 2e six doit laisser le choix, pas partir tout seul');

      await shutdownApp(t);
    });

    testWidgets('un coup joué tout seul est ANNONCÉ au joueur', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = state.controller;

      // Un seul pion jouable : sorti sur l'anneau, dé de 3 (pas de sortie
      // possible pour les autres).
      final only = c.state.pawnsByColor[c.currentColor]![0];
      only.location = PawnLocation.ring;
      only.position = GameController.startIdx(c.currentColor) + 4;
      expect(state.autoNotice, isNull, reason: 'rien à annoncer au départ');

      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 100));

      expect(state.autoNotice, isNotNull,
          reason: 'un coup automatique doit être expliqué');
      expect(state.autoNotice, contains('Un seul coup possible'));
      expect(find.textContaining('Un seul coup possible'), findsOneWidget,
          reason: 'le message doit être VISIBLE dans le panneau');

      await shutdownApp(t);
    });
  });

  group('🎚️ Niveaux de difficulté', () {
    testWidgets('les 5 niveaux sont proposés, Moyen actif par défaut',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      await openRules(t);

      for (final level in AiDifficulty.values) {
        expect(find.text(level.label), findsOneWidget,
            reason: '${level.label} doit avoir son bouton');
      }
      expect(state.aiDifficulty, AiDifficulty.moyen,
          reason: 'niveau par défaut demandé');
      expect(find.text(AiDifficulty.moyen.summary), findsOneWidget,
          reason: 'le résumé du niveau actif est affiché');
      await shutdownApp(t);
    });

    testWidgets('les boutons sont EXCLUSIFS : un seul niveau à la fois',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      await openRules(t);

      for (final level in AiDifficulty.values) {
        await t.tap(find.text(level.label));
        await t.pump(const Duration(milliseconds: 300));

        expect(state.aiDifficulty, level);
        // Un seul niveau coché à la fois. On ne compte QUE les chips de
        // difficulté : d'autres cartes du panneau en utilisent aussi, et
        // les compter toutes ferait passer ce test pour cassé sans raison.
        final labels = {for (final l in AiDifficulty.values) l.label};
        final selected = t
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((c) =>
                c.label is Text && labels.contains((c.label as Text).data))
            .where((c) => c.selected)
            .map((c) => (c.label as Text).data)
            .toList();
        expect(selected, [level.label],
            reason: '${level.label} : niveaux cochés = $selected');
        expect(find.text(level.summary), findsOneWidget);
      }
      await shutdownApp(t);
    });

    testWidgets('le niveau choisi survit à un changement d\'onglet',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      await openRules(t);

      await t.tap(find.text(AiDifficulty.imbattable.label));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.aiDifficulty, AiDifficulty.imbattable);

      await t.tap(find.text('Commandes'));
      await t.pump(const Duration(milliseconds: 300));
      await openRules(t);

      expect(state.aiDifficulty, AiDifficulty.imbattable,
          reason: 'le niveau ne doit pas retomber sur le défaut');
      await shutdownApp(t);
    });
  });
}
