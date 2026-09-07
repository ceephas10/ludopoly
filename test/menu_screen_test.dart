// Le tableau de bord : la première et la seule chose qu'on voit en ouvrant
// LudoPoly. « Jouer » mène au plateau nu, « Système » au plateau et à son
// panneau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'application ouvre sur le menu, et rien d\'autre', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(find.text('LUDOPOLY'), findsOneWidget);
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
    expect(find.text('Centre de commandes'), findsNothing);
    expect(find.text('Règles du jeu'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byKey(const Key('panel-handle')), findsNothing,
        reason: 'aucun moyen d\'ouvrir les paramètres depuis « Jouer »');

    await shutdownApp(t);
  });

  testWidgets('« Système » ne montre QUE les options, sans plateau',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-system')));
    await waitForBoard(t);

    // Les trois pages d'options, et elles seules.
    expect(find.text('Centre de commandes'), findsOneWidget);
    expect(find.text('Règles du jeu'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget,
        reason: 'ouvert sur le centre de commandes');

    // Pas de plateau : pas de pion à l'écran, donc pas de chevron non plus
    // — il n'y a rien à replier.
    expect(find.byType(BoardView), findsNothing,
        reason: 'Système ne montre pas le jeu');
    expect(find.byKey(const Key('panel-handle')), findsNothing);

    await shutdownApp(t);
  });

  testWidgets('« Comment jouer » ouvre le panneau sur les règles', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-how')));
    await waitForBoard(t);

    expect(find.text('Règles persistantes'), findsOneWidget,
        reason: 'le panneau doit s\'ouvrir directement sur les règles');

    await shutdownApp(t);
  });

  testWidgets('une option activée dans Système suit jusqu\'à Comment jouer',
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

    // Retour au menu, puis on entre par Comment jouer.
    await t.tap(find.byKey(const Key('board-home')));
    await t.pump();
    await t.tap(find.byKey(const Key('menu-how')));
    await waitForBoard(t);

    final how = t.state<BoardScreenState>(find.byType(BoardScreen));
    expect(how.controller.upgrades.chanceEnabled, isTrue,
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

    expect(find.text('LUDOPOLY'), findsOneWidget);
    expect(find.byType(BoardScreen), findsNothing,
        reason: 'sans ce retour, « Jouer » enferme dans la partie');

    await shutdownApp(t);
  });
}
