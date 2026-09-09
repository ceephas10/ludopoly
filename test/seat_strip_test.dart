// LES PAVÉS DES JOUEURS doivent se trouver AU-DESSUS DE LEUR BASE.
//
// Les deux pavés du haut se retournent : les joueurs d'en face lisent le
// plateau à l'envers. Le retournement portait sur la RANGÉE entière, ce
// qui la lisait de droite à gauche — le pavé rouge atterrissait au-dessus
// de la base VERTE, et le vert au-dessus de la ROUGE.
//
// Sur le plateau : rouge en haut à GAUCHE, vert en haut à DROITE, bleu en
// bas à gauche, jaune en bas à droite.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// Le libellé du BANDEAU, pas celui du plateau.
///
/// Le nom du joueur est écrit à deux endroits : en 12 points dans le pavé
/// du bandeau, et en 8 points sur le plateau lui-même. On vise le grand.
Finder pave(String label) => find.byWidgetPredicate(
    (w) => w is Text && w.data == label && (w.style?.fontSize ?? 0) >= 10,
    description: 'le pavé « $label »');

double _x(WidgetTester t, String label) => t.getCenter(pave(label)).dx;

/// Le plateau SANS le centre de commandes, sur un TÉLÉPHONE.
///
/// C'est la seule disposition qui pose les bandeaux au-dessus et au-dessous
/// du plateau — celle du jeu réel, et celle dont on parle ici. C'est aussi
/// la seule où chaque libellé n'apparaît qu'une fois : le panneau nomme lui
/// aussi les joueurs.
Future<void> bootSansPanneau(WidgetTester t) async {
  final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = const Size(750, 1624);
  view.devicePixelRatio = 2.0;
  BoardScreenState.muteStepSounds = true;
  resetPawnAnimationCache();
  await t.pumpWidget(const MaterialApp(home: BoardScreen(showPanel: false)));
  await waitForBoard(t);
}

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('chaque pavé est du côté de sa base', (t) async {
    await bootSansPanneau(t);

    // Les libellés, tels que `BoardScreen.players` les nomme.
    final rouge = BoardScreen.players[1];
    final vert = BoardScreen.players[2];
    final bleu = BoardScreen.players[0];
    final jaune = BoardScreen.players[3];

    expect(_x(t, rouge.name), lessThan(_x(t, vert.name)),
        reason: 'rouge est la base du HAUT-GAUCHE, vert celle du haut-droite');
    expect(_x(t, bleu.name), lessThan(_x(t, jaune.name)),
        reason: 'bleu est la base du BAS-GAUCHE, jaune celle du bas-droite');

    await shutdownApp(t);
  });

  testWidgets('les pavés du haut restent RETOURNÉS, chacun pour soi',
      (t) async {
    await bootSansPanneau(t);

    // Le retournement est passé de la rangée à CHAQUE pavé : il doit
    // toujours être là, sinon les joueurs d'en haut lisent à l'envers.
    for (final joueur in [BoardScreen.players[1], BoardScreen.players[2]]) {
      final tourne = find.ancestor(
        of: pave(joueur.name),
        matching: find.byWidgetPredicate(
            (w) => w is RotatedBox && w.quarterTurns == 2),
      );
      expect(tourne, findsOneWidget,
          reason: '${joueur.name} est en haut : son pavé se retourne');
    }
    await shutdownApp(t);
  });
}
