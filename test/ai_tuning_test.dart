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
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  /// Ouvre l'onglet « Règles du jeu » du panneau.
  Future<void> openRules(WidgetTester t) async {
    await t.tap(find.text('Règles du jeu'));
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

      await t.tap(find.text('Centre de commandes'));
      await t.pump(const Duration(milliseconds: 300));
      await openRules(t);

      expect(state.aiDifficulty, AiDifficulty.imbattable,
          reason: 'le niveau ne doit pas retomber sur le défaut');
      await shutdownApp(t);
    });
  });
}
