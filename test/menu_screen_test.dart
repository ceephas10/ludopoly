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

  testWidgets('« Système » ramène le panneau ET son chevron', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-system')));
    await waitForBoard(t);

    expect(find.text('Centre de commandes'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget,
        reason: 'le panneau est ouvert sur le centre de commandes');
    expect(find.byKey(const Key('panel-handle')), findsOneWidget,
        reason: 'ici le chevron existe : on peut replier puis rouvrir');

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
