// Le halo suit son pion À LA FRAME PRÈS, et il passe SOUS tous les pions.
//
// Deux plaintes, deux vérifications :
//
//   * « on a l'impression qu'il saute plus vite que le halo le suit » —
//     le halo a sa propre `AnimatedPositioned`, à côté de celle du pion.
//     Même durée, même courbe, construite dans la même passe : les deux
//     tweens démarrent sur la même frame. Ce test le mesure EN COURS de
//     déplacement, pas seulement à l'arrivée — c'est en chemin que le
//     décalage se voyait.
//
//   * « il ne faudrait pas que les halos passent à travers les tokens » —
//     sur l'anneau les pions se chevauchent (un pion fait plus d'une
//     case de haut). Tant que chaque halo était peint avec SON pion, il
//     recouvrait la tête du voisin de derrière. Ils sont donc tous peints
//     AVANT tous les pions : le test vérifie cet ordre dans l'arbre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// Position du coin haut-gauche d'un widget repéré par sa clé.
Offset _at(WidgetTester t, String key) {
  final box = t.renderObject<RenderBox>(find.byKey(ValueKey(key)));
  return box.localToGlobal(Offset.zero);
}

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('le halo ne décroche pas du pion pendant le déplacement',
      (t) async {
    await bootApp(t);
    final s = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = s.controller;

    final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
    blue.location = PawnLocation.ring;
    blue.position = 10;
    s.rollManualForTest(3);
    await t.pump(const Duration(milliseconds: 50));

    // L'écart halo ↔ pion AU REPOS. C'est la référence.
    final rest = _at(t, 'halo_blue_0') - _at(t, 'pawn_blue_0');

    await t.tap(find.byKey(const ValueKey('hit_blue_0')));
    // EN PLEIN déplacement : trois relevés répartis sur le trajet.
    for (final ms in [40, 90, 140]) {
      await t.pump(Duration(milliseconds: ms));
      final d = _at(t, 'halo_blue_0') - _at(t, 'pawn_blue_0');
      expect((d - rest).distance, lessThan(0.5),
          reason: 'à +$ms ms le halo a pris $d au lieu de $rest');
    }

    await t.pump(const Duration(seconds: 2));
    await shutdownApp(t);
  });

  testWidgets('tous les halos sont peints AVANT tous les pions', (t) async {
    await bootApp(t);
    final s = t.state<BoardScreenState>(find.byType(BoardScreen));
    final c = s.controller;

    // Deux pions bleus sur des cases VOISINES : ils se chevauchent, et
    // c'est là que le halo de l'un mordait sur la tête de l'autre.
    final blues = c.state.pawnsByColor[PlayerColor.blue]!;
    for (int i = 0; i < 2; i++) {
      blues[i].location = PawnLocation.ring;
      blues[i].position = 10 + i;
    }
    s.rollManualForTest(3);
    await t.pump(const Duration(milliseconds: 50));

    // L'ordre des enfants du Stack EST l'ordre de peinture.
    final keys = <String>[];
    for (final e in find.byType(AnimatedPositioned).evaluate()) {
      final k = e.widget.key;
      if (k is ValueKey<String>) keys.add(k.value);
    }
    final halos = [for (int i = 0; i < keys.length; i++) if (keys[i].startsWith('halo_')) i];
    final pions = [for (int i = 0; i < keys.length; i++) if (keys[i].startsWith('pawn_')) i];
    expect(halos, isNotEmpty, reason: 'deux pions jouables, donc deux halos');
    expect(pions, isNotEmpty);
    expect(halos.reduce((a, b) => a > b ? a : b),
        lessThan(pions.reduce((a, b) => a < b ? a : b)),
        reason: 'le DERNIER halo doit passer avant le PREMIER pion');

    await shutdownApp(t);
  });
}
