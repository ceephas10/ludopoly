// LE RACCOURCI DE LA CASE CHANCE, dans le panneau Système.
//
// « Au niveau de la carte chance, faire un bouton uniquement pour la
// case de chance : lorsque je clique sur le bouton, elle met mon token
// sur la case chance et elle me donne une carte chance. »
//
// Ce que le bouton doit faire, donc, en un clic : poser le pion choisi
// sur la case Chance de sa couleur, et déclencher le VRAI tirage — même
// talon, même présentation. Et rien du tout si les cases Chance sont
// éteintes : il n'y aurait pas de carte à tirer.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/upgrades.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// La plus petite graine dont le tirage donne une carte DIFFÉRÉE.
///
/// On la choisit pour que le pion RESTE sur sa case : une immédiate peut
/// le renvoyer en boîte ou l'avancer, et on ne saurait plus si le bouton
/// l'y a posé.
int graineDifferee() {
  for (var graine = 0; graine < 200; graine++) {
    if (!math.Random(graine).nextBool()) return graine;
  }
  throw StateError('aucune graine ne donne une différée');
}

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('un clic : le pion est sur la case Chance, et la carte tombe',
      (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    state.setChanceEnabled(true);
    c.upgrades.rng = math.Random(graineDifferee());
    await t.pump();

    final couleur = state.manualPlayerForTest;
    final pion = c.state.pawnsByColor[couleur]![0];
    expect(pion.location, PawnLocation.base, reason: 'il part de sa boîte');
    expect(c.upgrades.handOf(couleur), isEmpty);

    final bouton = find.byKey(const Key('cards-land-on-chance'));
    expect(bouton, findsOneWidget);
    await t.ensureVisible(bouton);
    await t.tap(bouton);
    await t.pump(const Duration(milliseconds: 300));

    expect(pion.location, PawnLocation.ring);
    expect(pion.position, SpecialCells.chanceCellOf(couleur),
        reason: 'sur SA case Chance, pas celle d\'un autre');
    expect(c.upgrades.handOf(couleur), hasLength(1),
        reason: 'et la carte est bien tirée');
    expect(state.revealedCard, isNotNull,
        reason: 'elle se présente, comme après un coup de dé');

    await shutdownApp(t);
  });

  testWidgets('« Retour » défait le raccourci comme n\'importe quel coup',
      (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;
    state.setChanceEnabled(true);
    c.upgrades.rng = math.Random(graineDifferee());
    await t.pump();

    final couleur = state.manualPlayerForTest;
    final pion = c.state.pawnsByColor[couleur]![0];

    final bouton = find.byKey(const Key('cards-land-on-chance'));
    await t.ensureVisible(bouton);
    await t.tap(bouton);
    await t.pump(const Duration(milliseconds: 300));
    expect(pion.location, PawnLocation.ring);

    // La carte ouverte couvre le plateau : on la referme avant de viser
    // un bouton, comme le ferait un joueur pressé.
    state.closeCard();
    await t.pump(const Duration(milliseconds: 300));

    final retour = find.widgetWithText(OutlinedButton, 'Retour');
    await t.ensureVisible(retour);
    await t.tap(retour);
    await t.pump(const Duration(milliseconds: 600));

    expect(pion.location, PawnLocation.base,
        reason: 'le pion doit revenir dans sa boîte');

    await shutdownApp(t);
  });

  testWidgets('cases Chance éteintes : le bouton est mort', (t) async {
    await bootApp(t);
    final state = t.state<BoardScreenState>(find.byType(BoardScreen));
    state.setChanceEnabled(false);
    await t.pump(const Duration(milliseconds: 300));

    final bouton = t.widget<ButtonStyleButton>(
        find.byKey(const Key('cards-land-on-chance')));
    expect(bouton.onPressed, isNull,
        reason: 'sans cases Chance, il n\'y a pas de carte à tirer');

    await shutdownApp(t);
  });
}
