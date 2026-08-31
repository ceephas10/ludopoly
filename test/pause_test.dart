// Le bouton Pause, testé à travers la vraie interface.
//
// Ce qui compte n'est pas que le bouton existe, mais les quatre garanties
// qu'il promet : plus rien ne bouge, aucune minuterie ne court, aucun tour
// n'est sauté, et la reprise repart avec le TEMPS RESTANT plutôt que de
// relancer chaque délai depuis zéro.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// Empreinte du plateau : deux empreintes égales = rien n'a bougé.
String board(GameController c) => [
      c.currentColor.name,
      c.phase.name,
      c.diceValue,
      c.lastRoll,
      for (final p in c.state.allPawns) '${p.location.name}:${p.position}',
    ].join('|');

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  group('⏸️ Pause du plateau', () {
    testWidgets('le bouton existe et bascule dans les deux sens', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      expect(state.paused, isFalse, reason: 'le jeu démarre en marche');
      expect(find.text('PAUSE'), findsNothing);

      await t.tap(find.widgetWithText(OutlinedButton, 'Pause'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.paused, isTrue);
      expect(find.text('PAUSE'), findsOneWidget,
          reason: 'le voile doit annoncer la pause sans ambiguïté');

      await t.tap(find.widgetWithText(FilledButton, 'Reprendre'));
      await t.pump(const Duration(milliseconds: 300));
      expect(state.paused, isFalse);
      expect(find.text('PAUSE'), findsNothing);

      await shutdownApp(t);
    });

    testWidgets('en pause, une partie d\'ordinateurs se fige TOTALEMENT',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats(PlayerColor.values.toSet());

      // On laisse la partie démarrer pour de bon.
      await t.pump(const Duration(seconds: 4));
      state.setPaused(true);
      // Laisser retomber ce qui aurait pu être armé à l'instant du gel.
      await t.pump(const Duration(milliseconds: 400));

      final frozen = board(state.controller);
      // Dix secondes simulées : largement de quoi voir bouger un plateau
      // vivant (lancer 900 ms, coup 700 ms, trajets 190 ms par case).
      await t.pump(const Duration(seconds: 10));
      expect(board(state.controller), frozen,
          reason: 'le plateau a bougé pendant la pause');

      await shutdownApp(t);
    });

    testWidgets('la reprise redémarre la partie, sans sauter de tour',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats(PlayerColor.values.toSet());
      await t.pump(const Duration(seconds: 4));

      state.setPaused(true);
      await t.pump(const Duration(milliseconds: 400));
      final frozen = board(state.controller);
      await t.pump(const Duration(seconds: 5));

      // À la reprise, l'état de départ est EXACTEMENT celui du gel : rien
      // n'a été rejoué pendant l'arrêt.
      expect(board(state.controller), frozen);
      state.setPaused(false);

      bool moved = false;
      for (int i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 200));
        if (board(state.controller) != frozen) {
          moved = true;
          break;
        }
      }
      expect(moved, isTrue, reason: 'la partie doit repartir après la pause');

      await shutdownApp(t);
    });

    testWidgets('le dé et les pions n\'acceptent plus rien en pause',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setPaused(true);
      await t.pump(const Duration(milliseconds: 300));

      final frozen = board(state.controller);
      // On force les commandes du joueur : elles doivent toutes être inertes.
      state.rollDiceForTest();
      await t.pump(const Duration(milliseconds: 500));
      expect(board(state.controller), frozen,
          reason: 'le dé a répondu alors que le plateau est gelé');

      await shutdownApp(t);
    });
  });

  group('⏱️ La reprise repart avec le TEMPS RESTANT', () {
    test('une minuterie reprend son reliquat, pas son délai entier', () async {
      var fired = 0;
      final t = PausableTimer(const Duration(milliseconds: 200), () => fired++);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      t.pause();
      expect(fired, 0);
      expect(t.isPaused, isTrue);

      // Bien plus long que le délai d'origine : gelée, elle ne part pas.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fired, 0, reason: 'une minuterie en pause ne doit pas partir');
      expect(t.isActive, isTrue, reason: 'en pause = en attente, pas morte');

      t.resume();
      // Il ne lui restait que ~50 ms : 120 suffisent largement, alors que
      // 120 ne suffiraient PAS si elle avait repris son délai entier.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(fired, 1, reason: 'la reprise a relancé le délai depuis zéro');

      t.cancel();
    });

    test('une minuterie répétée garde sa cadence après reprise', () async {
      var ticks = 0;
      final t = PausableTimer(const Duration(milliseconds: 100), () => ticks++,
          periodic: true);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      final before = ticks;
      expect(before, greaterThanOrEqualTo(2));

      t.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(ticks, before, reason: 'elle a continué de battre en pause');

      t.resume();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ticks, greaterThan(before), reason: 'elle n\'a pas repris');

      t.cancel();
    });

    test('annuler pendant la pause tue bien la minuterie', () async {
      var fired = 0;
      final t = PausableTimer(const Duration(milliseconds: 100), () => fired++);
      t.pause();
      t.cancel();
      expect(t.isActive, isFalse);
      t.resume(); // ne doit rien réarmer
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fired, 0);
    });
  });
}
