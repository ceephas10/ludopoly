// LES DESSINS DES CASES VORTEX REGARDENT LEUR COULEUR.
//
// Les ailes de bleu pointent vers la base bleue : elles sont dessinées
// pour. Les trois autres couleurs recevaient le MÊME dessin, sans le
// tourner — elles pointaient donc vers la base de quelqu'un d'autre.
//
// La correction applique à chaque couleur le quart de tour de son bras.
// Ce test vérifie que ces quarts de tour sont les BONS, non pas en
// relisant la table, mais en la confrontant aux cases elles-mêmes : un
// quart de tour autour du centre du plateau doit emmener la case de
// bleu exactement sur celle de la couleur concernée.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/board_painter.dart' show kQuartsDeTour;
import 'package:ludopoly/game/board_path.dart' show ring;
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/game/upgrades.dart' show SpecialCells;

/// Le centre du plateau, en cases.
const Offset centre = Offset(7.5, 7.5);

/// [p] tourné de [quarts] quarts de tour AUTOUR DU CENTRE, dans le sens
/// des aiguilles — le même sens que `canvas.rotate` avec un axe des y
/// vers le bas.
Offset tourne(Offset p, int quarts) {
  var q = p;
  for (var i = 0; i < quarts % 4; i++) {
    q = Offset(centre.dx - (q.dy - centre.dy), centre.dy + (q.dx - centre.dx));
  }
  return q;
}

void main() {
  test('le quart de tour de chaque couleur est celui de son bras', () {
    final ailesBleu = ring[SpecialCells.goodVortexCell(PlayerColor.blue)].pos;
    final craneBleu = ring[SpecialCells.badVortexCell(PlayerColor.blue)].pos;

    for (final c in PlayerColor.values) {
      final quarts = kQuartsDeTour[c]!;
      expect(
        tourne(ailesBleu, quarts),
        ring[SpecialCells.goodVortexCell(c)].pos,
        reason: '${c.name} : la case des ailes de bleu, tournée de $quarts '
            'quart(s) de tour, doit tomber sur celle de ${c.name} — sinon '
            'le dessin tourne d\'un quart de tour qui n\'est pas le sien',
      );
      expect(
        tourne(craneBleu, quarts),
        ring[SpecialCells.badVortexCell(c)].pos,
        reason: '${c.name} : même chose pour le crâne',
      );
    }
  });

  test('les quatre couleurs ont chacune leur quart de tour', () {
    expect(kQuartsDeTour[PlayerColor.blue], 0,
        reason: 'bleu est la référence : son dessin ne tourne pas');
    expect(kQuartsDeTour.values.toSet(), {0, 1, 2, 3},
        reason: 'quatre bras, quatre quarts de tour distincts');
  });
}
