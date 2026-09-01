// L'onglet Settings — même mécanique que les Règles du jeu, contenu
// encore vide : les paramètres viendront s'y ranger un à un.

import 'package:flutter_test/flutter_test.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'onglet existe, s\'ouvre, et masque les deux autres',
      (t) async {
    await bootApp(t);

    // Les trois onglets sont proposés côte à côte.
    expect(find.text('Centre de commandes'), findsOneWidget);
    expect(find.text('Règles du jeu'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Au départ : Centre de commandes affiché, pas les Paramètres.
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Paramètres'), findsNothing);

    await t.tap(find.text('Settings'));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('Paramètres'), findsOneWidget,
        reason: 'la page Settings doit s\'ouvrir');
    expect(find.text('Aucun paramètre pour l\'instant.'), findsOneWidget);
    expect(find.text('Setup'), findsNothing,
        reason: 'le Centre de commandes doit disparaître');
    expect(find.text('Règles persistantes'), findsNothing,
        reason: 'les Règles du jeu aussi');

    // Et retour au Centre de commandes, comme avec les Règles.
    await t.tap(find.text('Centre de commandes'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Paramètres'), findsNothing);

    await shutdownApp(t);
  });
}
