// Les cartes différées portent un NUMÉRO — leur rang dans la main. Sans
// lui, on ne peut ni les distinguer dans sa base, ni désigner laquelle on
// veut jouer dans le panneau.
//
// Le rang tient sa place que la carte soit montrée de dos (celles des
// autres joueurs) ou reconnaissable (les siennes, cf. [CardMini]) : c'est
// la MÊME pastille, au même endroit.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/card_art.dart';
import 'package:ludopoly/game/upgrades.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('chaque dos de la base porte son rang, de 1 à 4', (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    state.setChanceEnabled(true);
    final me = c.currentColor;

    // Trois cartes en main : trois dos numérotés 1, 2, 3.
    for (final id in ['DEF_DICE_1', 'DEF_DICE_2', 'DEF_DICE_3']) {
      c.upgrades
          .addToHand(me, kDeferredCards.singleWhere((x) => x.id == id));
    }
    state.setChanceEnabled(true); // force un redessin
    await t.pump(const Duration(milliseconds: 100));

    final numbers = [
      for (final b in t.widgetList<CardBack>(find.byType(CardBack)))
        if (b.number != null) b.number!,
      for (final m in t.widgetList<CardMini>(find.byType(CardMini))) m.number,
    ]..sort();
    expect(numbers, [1, 2, 3],
        reason: 'un dos par carte tenue, numéroté à partir de 1');

    await shutdownApp(t);
  });

  testWidgets('le panneau montre les MÊMES numéros que la base', (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    state.setChanceEnabled(true);
    final me = c.currentColor;

    final second =
        kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_5');
    c.upgrades
        .addToHand(me, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_4'));
    c.upgrades.addToHand(me, second);
    state.setChanceEnabled(true);
    await t.pump(const Duration(milliseconds: 100));

    // Le panneau liste les deux cartes, avec leur rang.
    expect(find.text(second.nameFr), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);

    await shutdownApp(t);
  });

  testWidgets('la carte ouverte annonce son numéro', (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    state.setChanceEnabled(true);
    final me = c.currentColor;

    c.upgrades
        .addToHand(me, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_1'));
    c.upgrades
        .addToHand(me, kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_6'));
    state.setChanceEnabled(true);
    await t.pump(const Duration(milliseconds: 100));

    state.openHandCardForTest(1); // la DEUXIÈME carte
    await t.pump(const Duration(milliseconds: 100));

    expect(state.openedHandCard?.id, 'DEF_DICE_6');
    expect(find.textContaining('carte 2'), findsOneWidget,
        reason: 'l\'ouverture doit rappeler le dos qu\'on vient de toucher');

    state.closeHandCard();
    await t.pump();
    await shutdownApp(t);
  });
}
