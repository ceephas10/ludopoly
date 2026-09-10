// L'ACCUEIL DU PANNEAU « SYSTÈME » : trois cadres SUR UNE MÊME LIGNE —
// Jeu normal, Jeu manuel, Pions à la maison.
//
// Une mise en page se casse sans bruit : un cadre déplacé, un cadre
// renvoyé dans un onglet, et rien ne le signale à la compilation. D'où
// ce test, qui lit les positions à l'écran plutôt que le code.
//
// Il vérifie aussi les deux conséquences du choix : les cadres sont
// AU-DESSUS des onglets, donc ils survivent au changement de page ; et
// ils s'empilent sur un téléphone, où trois colonnes ne tiennent pas.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/menu_music.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

const _titres = ['Jeu normal', 'Jeu manuel', 'Pions à la maison'];

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  Offset coin(WidgetTester t, String titre) => t.getTopLeft(find.text(titre));

  testWidgets('les trois cadres sont sur la même ligne, dans l\'ordre',
      (t) async {
    await bootApp(t);

    for (final titre in _titres) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }

    final coins = [for (final titre in _titres) coin(t, titre)];

    // MÊME LIGNE : les trois titres sont à la même hauteur.
    expect(coins[1].dy, coins[0].dy,
        reason: '« Jeu manuel » doit être à la hauteur de « Jeu normal »');
    expect(coins[2].dy, coins[0].dy,
        reason: '« Pions à la maison » aussi');

    // ET DANS L'ORDRE, de gauche à droite.
    expect(coins[0].dx, lessThan(coins[1].dx));
    expect(coins[1].dx, lessThan(coins[2].dx));

    // Les trois précèdent les onglets : c'est ce qui les rend visibles
    // quelle que soit la page ouverte.
    expect(coins[2].dy, lessThan(coin(t, 'Commandes').dy),
        reason: 'les trois cadres sont au-dessus des onglets');

    await shutdownApp(t);
  });

  testWidgets('changer d\'onglet ne les fait pas disparaître', (t) async {
    await bootApp(t);

    await t.tap(find.text('Règles'));
    await t.pump(const Duration(milliseconds: 300));

    // La page a bien changé…
    expect(find.text('Setup'), findsNothing);
    // … et les trois cadres sont toujours là.
    for (final titre in _titres) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }

    await shutdownApp(t);
  });

  testWidgets('« Pions à la maison » fixe le compte, dans les deux sens',
      (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    final moi = state.manualPlayerForTest;

    int rentres() => c.state.pawnsByColor[moi]!
        .where((p) => p.location == PawnLocation.home)
        .length;

    // Le cadre, et lui seul : « Valeur dé » propose les mêmes chiffres
    // dans le cadre d'à côté.
    final cadre = find.ancestor(
        of: find.text('Pions à la maison'), matching: find.byType(Card));
    Finder bouton(String n) =>
        find.descendant(of: cadre, matching: find.text(n));

    expect(rentres(), 0, reason: 'personne n\'est rentré au départ');

    await t.tap(bouton('3'));
    await t.pump(const Duration(milliseconds: 200));
    expect(rentres(), 3, reason: 'le bouton FIXE le compte à 3');

    // Et il le fait redescendre — c'est ce que dit le cadre.
    await t.tap(bouton('1'));
    await t.pump(const Duration(milliseconds: 200));
    expect(rentres(), 1, reason: 'de 3 à 1, deux pions ressortent');

    await shutdownApp(t);
  });

  testWidgets('sur un téléphone, les trois cadres s\'empilent', (t) async {
    // Trois colonnes de 120 points ne tiennent pas : la ligne des six
    // valeurs de dé en réclame 188 à elle seule. En dessous du seuil, les
    // cadres se rangent donc l'un sous l'autre — sans quoi la page
    // déborderait, ce que ce test vérifie AUSSI : un débordement de mise
    // en page fait échouer le test de lui-même.
    BoardScreenState.muteStepSounds = true;
    MenuMusic.muted = true;
    final vue = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    vue.physicalSize = const Size(390, 844);
    vue.devicePixelRatio = 1.0;

    resetPawnAnimationCache();
    await t.pumpWidget(
        const MaterialApp(home: BoardScreen(showBoard: false)));
    await waitForBoard(t);

    final coins = [for (final titre in _titres) coin(t, titre)];
    expect(coins[0].dx, coins[1].dx, reason: 'même colonne');
    expect(coins[0].dy, lessThan(coins[1].dy), reason: 'Jeu normal en tête');
    expect(coins[1].dy, lessThan(coins[2].dy),
        reason: 'puis Jeu manuel, puis Pions à la maison');

    await shutdownApp(t);
  });
}
