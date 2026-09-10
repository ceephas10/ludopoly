// LE PION DE LA RANGÉE DU HAUT RÉPOND AU CLIC.
//
// Sa zone de touche est faite plus haute que lui, exprès : un doigt vise
// la tête, la partie qu'on voit, et la zone doit donc la couvrir. Sur les
// cases 23, 24 et 25 — la rangée du haut du plateau — cette hauteur
// dépassait du plateau. Or le Stack laisse bien DÉBORDER ce qu'il peint
// (`Clip.none`), mais Flutter n'envoie jamais une touche à un enfant
// situé hors du cadre de son parent : la part qui dépassait était visible
// et morte. Le MILIEU de la zone tombait dedans, et le pion ne répondait
// plus du tout.
//
// C'est ainsi que la partie se figeait : un joueur qui tape sur son pion
// et à qui il ne se passe rien.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('les pions de la rangée du haut se laissent jouer',
      (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;

    final p0 = c.state.pawnsByColor[PlayerColor.blue]![0];
    final p1 = c.state.pawnsByColor[PlayerColor.blue]![1];

    // 22 et 26 encadrent la rangée du haut : ils marchaient déjà, ils
    // servent de témoins. 23, 24, 25 sont les trois cases du dessus.
    for (final cellule in [22, 23, 24, 25, 26]) {
      p0.location = PawnLocation.ring;
      p0.position = cellule;
      // Un DEUXIÈME coup possible. Sans lui le jeu joue le coup unique
      // tout seul, et le test mesurerait cet automatisme au lieu du clic.
      p1.location = PawnLocation.ring;
      p1.position = 5;
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;
      state.rollManualForTest(3);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.movablePawns().length, greaterThan(1),
          reason: 'case $cellule : il faut un vrai choix, sinon le coup '
              'part tout seul et le clic ne prouve rien');

      final zone = find.byKey(const ValueKey('hit_blue_0'));
      expect(zone, findsOneWidget, reason: 'case $cellule');
      await t.tap(zone, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 1500));

      expect(p0.position, cellule + 3,
          reason: 'case $cellule : le clic au MILIEU de la zone de touche '
              'doit jouer le pion — il tombait hors du plateau, là où '
              'aucune touche n\'arrive');
    }

    await shutdownApp(t);
  });
}
