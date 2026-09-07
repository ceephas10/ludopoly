// L'écran d'accueil : on règle la partie AVANT de voir le plateau, et ce
// qu'on y choisit est réellement appliqué.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/ai_difficulty.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'application ouvre sur les réglages, pas sur le plateau',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(find.text('LudoPoly'), findsOneWidget);
    expect(find.text('Nombre de joueurs'), findsOneWidget);
    expect(find.text('Qui joue ?'), findsOneWidget);
    expect(find.byKey(const Key('setup-play')), findsOneWidget);
    expect(find.byType(BoardScreen), findsNothing,
        reason: 'le plateau ne doit apparaître qu\'après « Jouer »');

    await t.tap(find.byKey(const Key('setup-play')));
    await t.pump();
    expect(find.byType(BoardScreen), findsOneWidget);

    await waitForBoard(t);
    await shutdownApp(t);
  });

  testWidgets('ce qu\'on règle est ce qu\'on joue', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    // Deux joueurs.
    await t.tap(find.text('2'));
    await t.pump();
    // Le vert passe à l'ordinateur.
    await t.tap(find.byKey(const Key('setup-seat-Vert')));
    await t.pump();
    // Les cartes chance entrent dans la partie.
    await t.tap(find.byKey(const Key('setup-option-Cartes chance')));
    await t.pump();

    await t.tap(find.byKey(const Key('setup-play')));
    await waitForBoard(t);

    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(state.controller.turnOrder,
        [PlayerColor.blue, PlayerColor.green],
        reason: 'deux joueurs : les couleurs opposées');
    expect(state.aiSeats, {PlayerColor.green});
    expect(state.controller.upgrades.chanceEnabled, isTrue);
    expect(state.controller.upgrades.vortexEnabled, isFalse,
        reason: 'une option non cochée reste éteinte');

    await shutdownApp(t);
  });

  testWidgets('le niveau n\'apparaît que s\'il y a un ordinateur', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(find.byKey(const Key('setup-difficulty')), findsNothing,
        reason: 'aucun ordinateur : le réglage n\'a rien à régler');

    await t.tap(find.byKey(const Key('setup-seat-Rouge')));
    await t.pump();
    expect(find.byKey(const Key('setup-difficulty')), findsOneWidget);

    await t.tap(find.byKey(const Key('setup-play')));
    await waitForBoard(t);

    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(state.aiSeats, {PlayerColor.red});
    expect(state.aiDifficulty, AiDifficulty.defaultLevel);

    await shutdownApp(t);
  });
}
