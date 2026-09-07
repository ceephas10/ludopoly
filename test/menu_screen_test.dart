// Le tableau de bord : la première et la seule chose qu'on voit en ouvrant
// LudoPoly. « Jouer » mène au plateau nu, « Système » au plateau et à son
// panneau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/brand.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'application ouvre sur le menu, et rien d\'autre', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(find.byType(LudoPolyLogo), findsOneWidget);
    for (final k in ['menu-play', 'menu-system', 'menu-how', 'menu-options']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    // Aucun réglage, aucun plateau : le menu seul.
    expect(find.byType(BoardScreen), findsNothing);
    expect(find.text('Nombre de joueurs'), findsNothing,
        reason: 'les réglages ne doivent PAS être sur le chemin du joueur');

    await shutdownApp(t);
  });

  testWidgets('« Jouer » donne le plateau SANS le panneau', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-play')));
    await waitForBoard(t);

    expect(find.byType(BoardScreen), findsOneWidget);
    // Ni le panneau, ni le chevron qui l'ouvrirait : cet écran s'adresse au
    // joueur, qui ne doit même pas apercevoir la page des paramètres.
    expect(find.text('Commandes'), findsNothing);
    expect(find.text('Règles'), findsNothing);
    expect(find.text('Paramètres'), findsNothing);
    expect(find.byKey(const Key('panel-handle')), findsNothing,
        reason: 'aucun moyen d\'ouvrir les paramètres depuis « Jouer »');

    await shutdownApp(t);
  });

  testWidgets('« Système » montre les options ET le plateau, repliable',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-system')));
    await waitForBoard(t);

    // Les trois pages d'options.
    expect(find.text('Commandes'), findsOneWidget);
    expect(find.text('Règles'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget,
        reason: 'ouvert sur le centre de commandes');

    // Et le plateau à côté : on règle en voyant l'effet. Le chevron est
    // là pour replier le panneau quand on veut le plateau en grand.
    expect(find.byType(BoardView), findsOneWidget,
        reason: 'Système montre aussi le jeu');
    expect(find.byKey(const Key('panel-handle')), findsOneWidget);

    await shutdownApp(t);
  });

  testWidgets('« Comment jouer » ouvre la règle du jeu, sans plateau',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-how')));
    await t.pump();

    expect(find.text('🎲 COMMENT JOUER À LUDOPOLY'), findsOneWidget);
    expect(find.text('1. 🎯 Le but du jeu'), findsOneWidget);
    // Une page de lecture : aucun plateau, aucun panneau de réglages.
    expect(find.byType(BoardScreen), findsNothing,
        reason: 'on vient y comprendre, pas y jouer');
    expect(find.text('Commandes'), findsNothing);

    // Et l'on en revient.
    await t.tap(find.byKey(const Key('how-home')));
    await t.pump();
    expect(find.byType(LudoPolyLogo), findsOneWidget);

    await shutdownApp(t);
  });

  testWidgets('une option activée dans Système suit jusqu\'à la partie',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    // Dans Système, on allume les cartes chance.
    await t.tap(find.byKey(const Key('menu-system')));
    await waitForBoard(t);
    final sys = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(sys.controller.upgrades.chanceEnabled, isFalse);
    sys.setChanceEnabled(true);
    await t.pump();

    // Retour au menu, puis on entre par « Jouer ».
    await t.tap(find.byKey(const Key('board-home')));
    await t.pump();
    await t.tap(find.byKey(const Key('menu-play')));
    await waitForBoard(t);

    final game = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(game.controller.upgrades.chanceEnabled, isTrue,
        reason: 'ce qu\'on règle dans Système doit valoir pour les autres '
            'écrans, sinon le réglage ne sert à rien');

    await shutdownApp(t);
  });

  testWidgets('la maison ramène au menu', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-play')));
    await waitForBoard(t);

    await t.tap(find.byKey(const Key('board-home')));
    await t.pump();

    expect(find.byType(LudoPolyLogo), findsOneWidget);
    expect(find.byType(BoardScreen), findsNothing,
        reason: 'sans ce retour, « Jouer » enferme dans la partie');

    await shutdownApp(t);
  });
}
