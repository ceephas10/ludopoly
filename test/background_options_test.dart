// Options › Arrière-plan : ce qu'on y choisit doit s'appliquer, et suivre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/background_config.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('les cinq styles et les cinq palettes sont proposés',
      (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-options')));
    await t.pump();

    await t.scrollUntilVisible(
      find.byKey(const Key('bg-style-royalGold')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    for (final s in BgStyle.values) {
      expect(find.byKey(Key('bg-style-${s.name}')), findsOneWidget,
          reason: s.label);
    }
    for (final th in BgTheme.values) {
      expect(find.byKey(Key('bg-theme-${th.name}')), findsOneWidget,
          reason: th.label);
    }
    // Les réglages d'ambiance du kit.
    for (final k in [
      'bg-droplets',
      'bg-accents',
      'bg-pattern-opacity',
      'bg-rays',
      'bg-center-glow',
      'bg-vignette',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }

    await shutdownApp(t);
  });

  testWidgets('le style choisi suit jusqu\'au plateau', (t) async {
    resetPawnAnimationCache();
    await t.pumpWidget(const LudoPolyApp());
    await t.pump();
    await t.tap(find.byKey(const Key('menu-options')));
    await t.pump();

    // On prend « Diamant Royal Gold » et la palette pourpre.
    await t.scrollUntilVisible(
      find.byKey(const Key('bg-style-royalGold')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('bg-style-royalGold')));
    await t.pump();
    await t.tap(find.byKey(const Key('bg-theme-royalPurple')));
    await t.pump();

    // On valide, puis on entre dans une partie.
    await t.scrollUntilVisible(
      find.byKey(const Key('setup-play')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('setup-play')));
    await t.pump();
    await t.tap(find.byKey(const Key('menu-play')));
    await waitForBoard(t);

    final board = t.widget<BoardScreen>(find.byType(BoardScreen));
    expect(board.setup.background.style, BgStyle.royalGold,
        reason: 'le décor réglé dans Options doit valoir pour la partie');
    expect(board.setup.background.theme, BgTheme.royalPurple);

    await shutdownApp(t);
  });
}
