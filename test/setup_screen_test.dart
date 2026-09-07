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

  testWidgets('Options ouvre les réglages, et y revient une fois validés',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    // Les réglages ne sont plus la première page : on y entre par Options.
    await t.tap(find.byKey(const Key('menu-options')));
    await t.pump();

    expect(find.text('Nombre de joueurs'), findsOneWidget);
    expect(find.text('Qui joue ?'), findsOneWidget);
    expect(find.byKey(const Key('setup-play')), findsOneWidget);
    expect(find.byType(BoardScreen), findsNothing,
        reason: 'le plateau ne doit apparaître qu\'après « Jouer »');

    // « Jouer » depuis les réglages ramène au MENU : on a réglé, on
    // choisit ensuite comment entrer.
    await t.tap(find.byKey(const Key('setup-play')));
    await t.pump();
    expect(find.byKey(const Key('menu-play')), findsOneWidget);

    await shutdownApp(t);
  });

  testWidgets('ce qu\'on règle est ce qu\'on joue', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    // Les réglages ne sont plus la première page : on y entre par Options.
    await t.tap(find.byKey(const Key('menu-options')));
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

    // On valide les réglages, puis on entre par « Système ».
    await t.tap(find.byKey(const Key('setup-play')));
    await t.pump();
    await t.tap(find.byKey(const Key('menu-system')));
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
    // Les réglages ne sont plus la première page : on y entre par Options.
    await t.tap(find.byKey(const Key('menu-options')));
    await t.pump();

    expect(find.byKey(const Key('setup-difficulty')), findsNothing,
        reason: 'aucun ordinateur : le réglage n\'a rien à régler');

    await t.tap(find.byKey(const Key('setup-seat-Rouge')));
    await t.pump();
    expect(find.byKey(const Key('setup-difficulty')), findsOneWidget);

    // On valide les réglages, puis on entre par « Système ».
    await t.tap(find.byKey(const Key('setup-play')));
    await t.pump();
    await t.tap(find.byKey(const Key('menu-system')));
    await waitForBoard(t);

    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(state.aiSeats, {PlayerColor.red});
    expect(state.aiDifficulty, AiDifficulty.defaultLevel);

    await shutdownApp(t);
  });
}
