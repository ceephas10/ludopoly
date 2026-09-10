// Le tableau de bord : la première et la seule chose qu'on voit en ouvrant
// LudoPoly. « Jouer » mène au plateau nu, « Système » au plateau et à son
// panneau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/brand.dart';
import 'package:ludopoly/game/menu_music.dart';
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

  // LA MUSIQUE DE L'ACCUEIL et son bouton. Le son lui-même est coupé dans
  // les tests — le harnais n'a pas de greffon audio — mais l'intention,
  // elle, se vérifie : c'est elle que le bouton pilote.
  testWidgets('l\'accueil porte un bouton qui coupe la musique', (t) async {
    addTearDown(() => MenuMusic.instance.setWanted(true));
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(MenuMusic.instance.wanted.value, isTrue,
        reason: 'la musique tourne par défaut en arrivant');
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    await t.tap(find.byKey(const Key('menu-music')));
    await t.pump();
    expect(MenuMusic.instance.wanted.value, isFalse, reason: 'stop');
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget,
        reason: 'l\'icône dit l\'état : haut-parleur barré');

    // Et l'on peut la remettre : couper sans pouvoir revenir serait une
    // impasse.
    await t.tap(find.byKey(const Key('menu-music')));
    await t.pump();
    expect(MenuMusic.instance.wanted.value, isTrue);

    await shutdownApp(t);
  });

  // LA MUSIQUE NE SUIT PAS SUR LE PLATEAU.
  //
  // Elle y repartait au premier contact : le réveil au premier geste —
  // celui qui la fait démarrer sur l'accueil, puisque les navigateurs
  // interdisent tout son avant qu'on ait touché la page — ne faisait
  // aucune différence entre l'accueil et la partie. Or sur le plateau on
  // touche sans arrêt : le dé, les pions, les cartes.
  testWidgets('la musique se tait sur le plateau, et rien ne la réveille',
      (t) async {
    addTearDown(() => MenuMusic.instance.surLePlateau(false));
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();

    expect(MenuMusic.instance.devraitJouer, isTrue,
        reason: 'sur l\'accueil, elle joue');

    await t.tap(find.byKey(const Key('menu-play')));
    await waitForBoard(t);
    expect(MenuMusic.instance.devraitJouer, isFalse,
        reason: 'sur le plateau, elle se tait');

    // On touche le plateau, comme on le fait sans arrêt en jouant.
    await t.tapAt(t.getCenter(find.byType(BoardScreen)));
    await t.pump(const Duration(milliseconds: 200));
    expect(MenuMusic.instance.devraitJouer, isFalse,
        reason: 'toucher le plateau ne la rallume pas');

    // Retour au menu : elle revient.
    await t.tap(find.byKey(const Key('board-home')));
    await t.pump(const Duration(milliseconds: 200));
    expect(MenuMusic.instance.devraitJouer, isTrue,
        reason: 'de retour sur l\'accueil, elle reprend');

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
