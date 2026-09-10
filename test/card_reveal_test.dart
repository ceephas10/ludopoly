// LA CARTE TIRÉE SE MONTRE — QUATRE SECONDES, DIFFÉRÉE COMPRISE.
//
// « Lorsqu'un token joue et il tombe sur une case chance, il faudrait que
// la carte différée se présente à moi quelques secondes avant qu'elle
// parte dans la base […] pour la carte immédiate il faut que la durée
// pour qu'elle s'applique prenne au moins 4 secondes, et aussi pour la
// carte différée 4 secondes aussi. »
//
// Deux choses à tenir, donc :
//   * la durée — quatre secondes pleines, pas trois ;
//   * l'ordre — la différée se voit AVANT d'atterrir dans la base, et
//     pas en même temps.
//
// La seconde se lit sur `mainAffichee` : la main du moteur reçoit la
// carte tout de suite (c'est la règle), l'affichage la retient le temps
// de la présentation.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/upgrades.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// La plus petite graine dont le tirage sur une case Chance donne [kind].
///
/// Le tirage est une pièce jetée (Annexe B : une chance sur deux), et
/// c'est le PREMIER appel au hasard des améliorations. La graine décide
/// donc du genre à elle seule — ce que les deux tests vérifient d'ailleurs
/// aussitôt, en relisant le genre de la carte présentée.
int graineQuiDonne(CardKind kind) {
  for (var graine = 0; graine < 200; graine++) {
    final tire = math.Random(graine).nextBool()
        ? CardKind.immediate
        : CardKind.deferred;
    if (tire == kind) return graine;
  }
  throw StateError('aucune graine ne donne $kind');
}

/// Pose blue#0 juste avant sa case Chance et joue le pas qui l'y mène.
/// Renvoie l'état du plateau.
Future<BoardScreenState> tomberSurUneCaseChance(
    WidgetTester t, int graine) async {
  await bootApp(t);
  final state = t.state<BoardScreenState>(find.byType(BoardScreen));
  final c = state.controller;
  state.setChanceEnabled(true);
  c.upgrades.rng = math.Random(graine);

  final chance = SpecialCells.chanceCellOf(PlayerColor.blue);
  final p = c.state.pawnsByColor[PlayerColor.blue]![0];
  p.location = PawnLocation.ring;
  p.position = chance - 1;
  c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
  c.phase = TurnPhase.rolling;

  // Un seul coup possible : le jeu le joue tout seul, comme pour un
  // joueur qui n'a pas le choix.
  state.rollManualForTest(1);
  for (int i = 0; i < 40 && state.revealedCard == null; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(p.position, chance, reason: 'le pion doit être sur la case Chance');
  return state;
}

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('une carte DIFFÉRÉE se montre, PUIS rejoint la base',
      (t) async {
    final state =
        await tomberSurUneCaseChance(t, graineQuiDonne(CardKind.deferred));
    final c = state.controller;

    final montree = state.revealedCard;
    expect(montree, isNotNull,
        reason: 'la différée doit se présenter, pas filer en douce');
    expect(montree!.kind, CardKind.deferred);

    // Le moteur l'a déjà rangée…
    expect(c.upgrades.handOf(PlayerColor.blue), contains(montree));
    // … mais la base ne la montre pas encore : elle est en l'air.
    expect(state.mainAffichee(PlayerColor.blue), isNot(contains(montree)),
        reason: 'tant qu\'on la présente, elle n\'est pas dans la base');

    // Elle tient les quatre secondes.
    await t.pump(const Duration(milliseconds: 3800));
    expect(state.revealedCard, isNotNull,
        reason: 'à 3,8 s la carte doit être encore ouverte');

    await t.pump(const Duration(milliseconds: 400));
    expect(state.revealedCard, isNull, reason: 'à 4,2 s elle est refermée');
    expect(state.mainAffichee(PlayerColor.blue), contains(montree),
        reason: 'et c\'est MAINTENANT qu\'elle apparaît dans la base');

    await shutdownApp(t);
  });

  testWidgets('une carte IMMÉDIATE reste ouverte quatre secondes',
      (t) async {
    final state =
        await tomberSurUneCaseChance(t, graineQuiDonne(CardKind.immediate));
    expect(state.revealedCard?.kind, CardKind.immediate);

    await t.pump(const Duration(milliseconds: 3800));
    expect(state.revealedCard, isNotNull,
        reason: 'quatre secondes pour lire, pas trois');

    await t.pump(const Duration(milliseconds: 400));
    expect(state.revealedCard, isNull);

    await shutdownApp(t);
  });
}
