// Le chevron posé entre le plateau et le centre de commandes : il replie
// le panneau sur le côté, et le rouvre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('le chevron replie le panneau, puis le rouvre', (t) async {
    await bootApp(t);

    final handle = find.byKey(const Key('panel-handle'));
    expect(handle, findsOneWidget, reason: 'la poignée est entre les deux');

    // Au départ : le panneau est ouvert, et le chevron montre la droite —
    // c'est là que le clic va l'emmener.
    expect(find.text('Centre de commandes'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await t.tap(handle);
    await t.pump(const Duration(milliseconds: 300));

    // Replié : le panneau a disparu, le chevron s'est retourné.
    expect(find.text('Centre de commandes'), findsNothing,
        reason: 'le panneau doit être replié');
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(handle, findsOneWidget, reason: 'la poignée, elle, reste');

    await t.tap(handle);
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('Centre de commandes'), findsOneWidget,
        reason: 'un second clic le rouvre');
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await shutdownApp(t);
  });
}
