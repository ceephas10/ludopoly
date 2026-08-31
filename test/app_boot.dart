// Démarrage de l'application dans un test de widget.
//
// `_bootstrap` sonde les 20 fichiers d'animation des pions par de VRAIES
// entrées-sorties. `tester.pump` n'avance que l'horloge simulée : il ne
// laisse jamais ces futures aboutir, et l'application reste indéfiniment
// sur son écran « Loading tokens… ». Il faut rendre la main à
// l'ordonnanceur réel entre deux pompages, ce que fait `runAsync`.
//
// C'est aussi la raison pour laquelle `widget_test.dart` échouait depuis
// le début : il ne pompait qu'une fois.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

/// Surface de rendu des tests. La surface par défaut (800×600) est trop
/// étroite pour le plateau ET le panneau de commandes : la mise en page
/// déborde et le test échoue sur une erreur sans rapport avec ce qu'il
/// teste.
void useLargeSurface() {
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.physicalSize = const Size(2400, 1500);
  view.devicePixelRatio = 1.0;
}

void resetSurface() {
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
  view.resetPhysicalSize();
  view.resetDevicePixelRatio();
}

/// Monte l'application et attend la fin du sondage des assets.
///
/// La limite est volontairement large : `flutter test` exécute les
/// fichiers de test en parallèle, et le sondage peut prendre nettement
/// plus longtemps quand plusieurs s'exécutent en même temps.
Future<void> bootApp(WidgetTester t) async {
  // Chaque test a sa propre zone asynchrone : une future mise en cache par
  // le test précédent ne s'y résout jamais. On repart d'un cache vide.
  resetPawnAnimationCache();
  await t.pumpWidget(const LudoPolyApp());
  for (int i = 0; i < 3000; i++) {
    if (find.text('Loading tokens…').evaluate().isEmpty) return;
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  fail(
    'le sondage des assets n\'a pas abouti — l\'application est restée '
    'sur son écran de chargement',
  );
}

/// Démonte l'arbre en fin de test.
///
/// Deux choses à purger, sans quoi le test échoue sur « A Timer is still
/// pending even after the widget tree was disposed » :
///
///   * les minuteries de la boucle IA — `dispose` les coupe, watchdog
///     périodique compris ;
///   * le démarrage DÉCALÉ de l'animation de chaque pion, un
///     `Future.delayed` de 0 à 799 ms (`_PawnAnimatedGifState._init`).
///     Celui-là n'est pas annulable : il est simplement gardé par un
///     `!mounted`, donc inoffensif en production. On lui laisse le temps
///     de retomber plutôt que d'alourdir le code de rendu pour un
///     détail de harnais.
Future<void> shutdownApp(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(milliseconds: 900));
}
