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
    expect(find.text('Commandes'), findsOneWidget);
    expect(find.text('Règles'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);

    // Au départ : Commandes affiché, pas la page des paramètres. On la
    // reconnaît à sa phrase, pas au mot « Paramètres » — c'est aussi le
    // libellé de son onglet, qui lui est toujours là.
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Aucun paramètre pour l\'instant.'), findsNothing);

    await t.tap(find.text('Paramètres'));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('Aucun paramètre pour l\'instant.'), findsOneWidget,
        reason: 'la page des paramètres doit s\'ouvrir');
    expect(find.text('Setup'), findsNothing,
        reason: 'le Centre de commandes doit disparaître');
    expect(find.text('Règles persistantes'), findsNothing,
        reason: 'les Règles du jeu aussi');

    // Et retour au Centre de commandes, comme avec les Règles.
    await t.tap(find.text('Commandes'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Aucun paramètre pour l\'instant.'), findsNothing);

    await shutdownApp(t);
  });
}
