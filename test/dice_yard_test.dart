// Les DEUX indicateurs de tour : le dé central, qui prend la couleur du
// joueur dont c'est le tour, et le Yard (la base) de ce joueur, qui
// clignote — humain comme ordinateur. Deux promesses de plus : les deux
// SUIVENT le tour quand la main passe, et le clignotement se FIGE pendant
// la pause comme tout le reste du plateau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// Chemins d'asset de toutes les faces de dé actuellement à l'écran.
List<String> diceAssets(WidgetTester t) => [
      for (final img in t.widgetList<Image>(find.byType(Image)))
        if (img.image is AssetImage &&
            (img.image as AssetImage).assetName.contains('Dices/PNG/'))
          (img.image as AssetImage).assetName,
    ];

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  group('🎲 Le dé central porte la COULEUR du joueur au tour', () {
    testWidgets('au démarrage : un seul dé, à la couleur du premier joueur',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      final dice = diceAssets(t);
      expect(dice.length, 1, reason: 'un seul dé sur le plateau : $dice');
      expect(dice.single, endsWith('_${state.currentColor.name}.png'),
          reason: 'le dé doit porter la couleur du joueur dont c\'est '
              'le tour');

      await shutdownApp(t);
    });

    testWidgets('quand la main passe, le dé change de couleur AVEC elle',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      // Un 3 au premier tour : aucun coup jouable, la main passe DANS le
      // lancer lui-même — la couleur « avant » se lit donc avant de lancer.
      final before = state.currentColor;
      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 200));

      expect(state.currentColor, isNot(before),
          reason: 'un 3 sans coup jouable doit passer la main');
      expect(diceAssets(t).single,
          'AnimStock/Dices/PNG/Dice_3_${state.currentColor.name}.png',
          reason: 'le dé garde la valeur sortie mais prend la couleur du '
              'joueur suivant');

      await shutdownApp(t);
    });
  });

  group('✨ Le Yard du joueur actif clignote', () {
    testWidgets('un seul halo, sur le Yard du joueur courant, et il pulse',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      expect(find.byType(YardBlink), findsOneWidget,
          reason: 'exactement un Yard clignote à la fois');
      final blink = t.widget<YardBlink>(find.byType(YardBlink));
      expect(blink.playerColor, state.currentColor,
          reason: 'le halo doit désigner le joueur dont c\'est le tour');

      final blinkState = t.state<YardBlinkState>(find.byType(YardBlink));
      expect(blinkState.animating, isTrue,
          reason: 'un halo immobile n\'indique rien : il doit pulser');

      await shutdownApp(t);
    });

    testWidgets('le halo SUIT le tour quand la main passe', (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      final before = state.currentColor;

      // Un 2 au premier tour : aucun coup jouable, la main passe dans le
      // lancer même. On pompe ensuite pour que le plateau se redessine.
      state.rollManualForTest(2);
      await t.pump(const Duration(milliseconds: 300));
      expect(state.currentColor, isNot(before));

      final blink = t.widget<YardBlink>(find.byType(YardBlink));
      expect(blink.playerColor, state.currentColor,
          reason: 'le halo est resté sur ${blink.playerColor.name} alors '
              'que c\'est au tour de ${state.currentColor.name}');

      await shutdownApp(t);
    });

    testWidgets('il clignote aussi pour un siège tenu par l\'ordinateur',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats(PlayerColor.values.toSet());
      await t.pump(const Duration(seconds: 3));

      expect(find.byType(YardBlink), findsOneWidget,
          reason: 'le tour d\'une IA se signale comme celui d\'un humain');

      await shutdownApp(t);
    });

    testWidgets('la pause FIGE la pulsation, la reprise la relance',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));

      state.setPaused(true);
      await t.pump(const Duration(milliseconds: 300));
      final frozen = t.state<YardBlinkState>(find.byType(YardBlink));
      expect(frozen.animating, isFalse,
          reason: 'un plateau en pause ne doit plus respirer du tout');

      state.setPaused(false);
      await t.pump(const Duration(milliseconds: 300));
      expect(t.state<YardBlinkState>(find.byType(YardBlink)).animating,
          isTrue,
          reason: 'la reprise doit relancer le clignotement');

      await shutdownApp(t);
    });
  });

  group('🎲 Le dé reste lisible APRÈS le coup', () {
    testWidgets('le chiffre et la couleur du joueur tiennent, puis passent',
        (t) async {
      await bootApp(t);
      final state = t.state<BoardScreenState>(find.byType(BoardScreen));
      state.setAiSeats(const {}); // personne ne joue tout seul
      await t.pump();

      final me = state.currentColor;
      // Un seul pion sur l'anneau : avec un 3, le coup est forcé et part
      // tout seul.
      final p = state.controller.state.pawnsByColor[me]![0];
      p.location = PawnLocation.ring;
      p.position =
          (GameController.startIdx(me) + 10) % GameController.ringSize;

      state.rollManualForTest(3);
      // Pause d'affichage du dé (550 ms) puis le trajet (2 × 190 ms).
      await t.pump(const Duration(milliseconds: 1400));

      // Le moteur a passé la main…
      expect(state.currentColor, isNot(me),
          reason: 'un 3 sans capture doit passer la main');
      // … mais le dé montre encore le 3 de CELUI QUI VIENT DE JOUER.
      expect(diceAssets(t).single,
          'AnimStock/Dices/PNG/Dice_3_${me.name}.png',
          reason: 'sans cette retenue, le joueur ne lit jamais son propre '
              'résultat : le dé basculerait à la couleur suivante dès que '
              'le pion se pose');

      // La pause écoulée, la main passe visuellement au suivant.
      await t.pump(const Duration(milliseconds: 900));
      expect(diceAssets(t).single,
          'AnimStock/Dices/PNG/Dice_3_${state.currentColor.name}.png');

      await shutdownApp(t);
    });
  });
}
