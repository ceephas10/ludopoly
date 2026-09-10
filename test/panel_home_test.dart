// L'ACCUEIL DU PANNEAU « SYSTÈME ».
//
// Deux cadres l'un sous l'autre, alignés : « Pions maison » — la
// couleur, le dé, le nombre de pions rentrés — puis « Jeu normal ». Ils
// sont AU-DESSUS des onglets : ils ne commandent pas une page, ils
// commandent la partie, et survivent donc au changement de page.
//
// Et tout en bas, collée, la barre « Retour / Rejouer » : elle ne défile
// pas avec le reste. C'est un ORDRE et une STRUCTURE, donc des choses
// qui se cassent sans bruit — d'où ce test, qui lit les positions à
// l'écran plutôt que le code.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/menu_music.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  Offset coin(WidgetTester t, String titre) => t.getTopLeft(find.text(titre));

  testWidgets('« Pions maison » est au-dessus de « Jeu normal », aligné',
      (t) async {
    await bootApp(t);

    expect(find.text('Pions maison'), findsOneWidget);
    expect(find.text('Jeu normal'), findsOneWidget);
    // Les deux anciens cadres n'existent plus sous leurs anciens noms.
    expect(find.text('Jeu manuel'), findsNothing);
    expect(find.text('Pions à la maison'), findsNothing);

    final maison = coin(t, 'Pions maison');
    final normal = coin(t, 'Jeu normal');

    expect(maison.dy, lessThan(normal.dy),
        reason: '« Pions maison » vient au-dessus');
    expect(maison.dx, normal.dx,
        reason: 'et les deux cadres commencent au même bord');

    // Les deux précèdent les onglets.
    expect(normal.dy, lessThan(coin(t, 'Commandes').dy),
        reason: 'les cadres sont au-dessus des onglets');

    await shutdownApp(t);
  });

  testWidgets('la phrase d\'attente du lancer a disparu', (t) async {
    await bootApp(t);
    expect(find.text('En attente du lancer'), findsNothing);
    expect(find.textContaining('attente du lancer'), findsNothing);
    await shutdownApp(t);
  });

  testWidgets('« Retour / Rejouer » : plus de titre, et collé en bas',
      (t) async {
    await bootApp(t);

    expect(find.text('Retour / Rejouer'), findsNothing,
        reason: 'le titre du cadre est retiré');

    final retour = find.widgetWithText(OutlinedButton, 'Retour');
    final rejouer = find.widgetWithText(OutlinedButton, 'Rejouer');
    expect(retour, findsOneWidget);
    expect(rejouer, findsOneWidget);

    final avant = t.getTopLeft(retour);
    // Il est en BAS : sous les onglets, et sous les cadres d'accueil.
    expect(avant.dy, greaterThan(coin(t, 'Jeu normal').dy),
        reason: 'la barre est en bas du panneau, pas dans le contenu');

    // ET IL NE DÉFILE PAS. On fait défiler le panneau ; le contenu monte,
    // la barre ne bouge pas d'un pixel.
    final contenuAvant = coin(t, 'Jeu normal');
    await t.drag(find.byType(SingleChildScrollView).first,
        const Offset(0, -600));
    await t.pump(const Duration(milliseconds: 300));

    expect(coin(t, 'Jeu normal').dy, lessThan(contenuAvant.dy),
        reason: 'le contenu doit vraiment avoir défilé, sinon ce test '
            'ne prouve rien');
    expect(t.getTopLeft(retour), avant,
        reason: 'la barre est collée : le contenu défile au-dessus d\'elle');

    await shutdownApp(t);
  });

  testWidgets('changer d\'onglet ne fait pas disparaître les cadres',
      (t) async {
    await bootApp(t);

    await t.tap(find.text('Règles'));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('Setup'), findsNothing, reason: 'la page a changé');
    expect(find.text('Pions maison'), findsOneWidget);
    expect(find.text('Jeu normal'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retour'), findsOneWidget,
        reason: 'et la barre du bas reste, quelle que soit la page');

    await shutdownApp(t);
  });

  testWidgets('« Combien de pions rentrés » fixe le compte, dans les deux sens',
      (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    final moi = state.manualPlayerForTest;

    int rentres() => c.state.pawnsByColor[moi]!
        .where((p) => p.location == PawnLocation.home)
        .length;

    expect(rentres(), 0, reason: 'personne n\'est rentré au départ');

    // Par la CLÉ : le cadre porte deux rangées de chiffres, la valeur du
    // dé et le nombre de pions rentrés.
    await t.tap(find.byKey(const ValueKey('home-count-3')));
    await t.pump(const Duration(milliseconds: 200));
    expect(rentres(), 3, reason: 'le bouton FIXE le compte à 3');

    await t.tap(find.byKey(const ValueKey('home-count-1')));
    await t.pump(const Duration(milliseconds: 200));
    expect(rentres(), 1, reason: 'de 3 à 1, deux pions ressortent');

    await shutdownApp(t);
  });

  testWidgets('sur un téléphone, la structure tient', (t) async {
    // Un débordement de mise en page fait échouer le test de lui-même :
    // c'est aussi ce que ce test vérifie.
    BoardScreenState.muteStepSounds = true;
    MenuMusic.muted = true;
    final vue =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    vue.physicalSize = const Size(390, 844);
    vue.devicePixelRatio = 1.0;

    resetPawnAnimationCache();
    await t.pumpWidget(
        const MaterialApp(home: BoardScreen(showBoard: false)));
    await waitForBoard(t);

    final maison = coin(t, 'Pions maison');
    final normal = coin(t, 'Jeu normal');
    expect(maison.dy, lessThan(normal.dy));
    expect(maison.dx, normal.dx, reason: 'alignés, même sur un téléphone');

    final retour = t.getBottomLeft(find.widgetWithText(OutlinedButton, 'Retour'));
    expect(retour.dy, greaterThan(700),
        reason: 'la barre est bien posée au bas de l\'écran');

    await shutdownApp(t);
  });
}
