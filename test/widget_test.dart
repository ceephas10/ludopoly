// Fumigation : l'application démarre, sort de son écran de chargement et
// affiche le plateau des 4 joueurs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'app démarre et affiche les 4 joueurs', (tester) async {
    await bootApp(tester);
    // Chaque nom apparaît deux fois : sur le plateau et dans le panneau.
    for (final name in ['Player 1', 'Player 2', 'Player 3', 'Player 4']) {
      expect(find.text(name), findsWidgets, reason: '$name est absent');
    }

    // Chaque pion décale le départ de son animation d'au plus 800 ms via
    // un `Future.delayed`. On laisse ces délais s'écouler, puis on démonte
    // l'arbre : sans ça le harnais signale « A Timer is still pending ».
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
