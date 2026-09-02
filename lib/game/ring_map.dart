// La CARTE DES CASES de l'anneau, en JSON.
//
// Les 52 cases du ring — celles que l'interrupteur « Show ring » numérote
// à l'écran — décrites une à une, et regroupées par FONCTION. Rien n'est
// écrit en dur : tout se recalcule depuis la géométrie du plateau
// (`board_path.dart`) et depuis les cases spéciales (`upgrades.dart`), de
// sorte que ce JSON ne peut pas dériver du jeu réel.
//
// Les cinq fonctions se déduisent toutes du même principe : une case
// spéciale appartient à UNE couleur, et se trouve à un nombre de pas fixe
// de SA case de départ.
//
//   pas  0  → DÉPART        cases 0, 13, 26, 39   (sûre)
//   pas  1  → VORTEX BON    cases 1, 14, 27, 40
//   pas  6  → CHANCE        cases 6, 19, 32, 45
//   pas  8  → ÉTOILE SÛRE   cases 8, 21, 34, 47   (sûre)
//   pas 44  → TROU NOIR     cases 44, 5, 18, 31
//
// Tout le reste est une case ordinaire.

import 'dart:convert';

import 'board_path.dart';
import 'player_color.dart';
import 'upgrades.dart';

/// Les fonctions qu'une case d'anneau peut porter.
enum RingFunction {
  start,
  vortexGood,
  vortexBad,
  chance,
  safeStar,
  normal,
}

/// Le pas, depuis le départ de sa couleur, auquel chaque fonction se
/// trouve. `null` pour une case ordinaire, qui n'appartient à personne.
const Map<RingFunction, int> _stepOf = {
  RingFunction.start: 0,
  RingFunction.vortexGood: 1,
  RingFunction.chance: 6,
  RingFunction.safeStar: 8,
  RingFunction.vortexBad: SpecialCells.lastStraightStep,
};

const Map<RingFunction, String> _idJson = {
  RingFunction.start: 'START',
  RingFunction.vortexGood: 'VORTEX_GOOD',
  RingFunction.vortexBad: 'VORTEX_BAD',
  RingFunction.chance: 'CHANCE',
  RingFunction.safeStar: 'SAFE_STAR',
  RingFunction.normal: 'NORMAL',
};

const Map<RingFunction, String> _nameFr = {
  RingFunction.start: 'Case de départ',
  RingFunction.vortexGood: 'Vortex — la bonne',
  RingFunction.vortexBad: 'Vortex — le trou noir',
  RingFunction.chance: 'Case Chance',
  RingFunction.safeStar: 'Étoile de protection',
  RingFunction.normal: 'Case ordinaire',
};

const Map<RingFunction, String> _descFr = {
  RingFunction.start:
      'Le pion y sort de sa boîte sur un 6. Case sûre : on n\'y capture '
          'personne.',
  RingFunction.vortexGood:
      'Première case après la boîte départ. Son propriétaire seul l\'utilise : '
          'il file sur la première case de l\'adversaire en diagonale, 26 pas '
          'gagnés.',
  RingFunction.vortexBad:
      'Première case de la dernière ligne droite. Son propriétaire seul '
          'l\'utilise : il revient sur celle de l\'adversaire en diagonale, '
          '26 pas perdus.',
  RingFunction.chance:
      'Deux cases avant l\'étoile. Le pion qui s\'y arrête tire une carte : '
          'une chance sur deux qu\'elle soit immédiate ou différée. Elle '
          'n\'appartient à aucun joueur.',
  RingFunction.safeStar:
      'Case sûre : on n\'y capture personne.',
  RingFunction.normal:
      'Case de parcours ordinaire. La capture y est possible.',
};

/// La couleur à qui appartient la case [id], pour la fonction [f], ou
/// `null` si cette fonction n'appartient à personne.
PlayerColor? _ownerOf(int id, RingFunction f) {
  final step = _stepOf[f];
  if (step == null || f == RingFunction.chance) return null;
  for (final c in PlayerColor.values) {
    if ((startIndexOf[c]! + step) % ring.length == id) return c;
  }
  return null;
}

/// La fonction portée par la case [id].
RingFunction ringFunctionOf(int id) {
  for (final f in _stepOf.keys) {
    for (final c in PlayerColor.values) {
      if ((startIndexOf[c]! + _stepOf[f]!) % ring.length == id) return f;
    }
  }
  return RingFunction.normal;
}

/// L'index de la case [id] sur la grille 15×15 du plateau — la même
/// numérotation que celle de l'interrupteur « Show grid » : `ligne × 15 +
/// colonne`.
int gridIndexOf(int id) {
  final pos = ring[id].pos;
  return (pos.dy - 0.5).round() * 15 + (pos.dx - 0.5).round();
}

/// Les cases portant la fonction [f], dans l'ordre de l'anneau.
List<int> cellsWithFunction(RingFunction f) => [
      for (int id = 0; id < ring.length; id++)
        if (ringFunctionOf(id) == f) id,
    ];

Map<String, Object?> _cellJson(int id) {
  final f = ringFunctionOf(id);
  final owner = _ownerOf(id, f);
  final pos = ring[id].pos;
  return {
    'id': id,
    'grid': gridIndexOf(id),
    'col': (pos.dx - 0.5).round(),
    'row': (pos.dy - 0.5).round(),
    'function': _idJson[f],
    if (owner != null) 'owner': owner.name,
    'safe': ring[id].isSafe,
    // À combien de pas cette case se trouve du départ de CHAQUE couleur.
    // C'est ce qui explique qu'une même case soit le trou noir de l'un et
    // une case ordinaire pour les trois autres.
    'steps': {
      for (final c in PlayerColor.values)
        c.name: (id - startIndexOf[c]! + ring.length) % ring.length,
    },
  };
}

/// La carte complète de l'anneau : les couleurs, les groupes de cases par
/// fonction, puis les 52 cases une à une.
Map<String, Object?> ringMapJson() => {
      'version': '1.0',
      'board': '4 joueurs',
      'ringSize': ring.length,
      'note':
          'Les identifiants sont ceux affichés par l\'interrupteur « Show '
              'ring ». Une case spéciale appartient à UNE couleur et se '
              'trouve à un nombre de pas fixe de SA case de départ.',
      'colors': {
        for (final c in PlayerColor.values)
          c.name: {
            'start': startIndexOf[c],
            'vortexGood': SpecialCells.goodVortexCell(c),
            'vortexBad': SpecialCells.badVortexCell(c),
            'chance': SpecialCells.chanceCellOf(c),
            'safeStar': (startIndexOf[c]! + 8) % ring.length,
            // Dernière case d'anneau avant d'entrer dans son couloir.
            'lastRingCell': (startIndexOf[c]! + 50) % ring.length,
            'diagonal': SpecialCells.diagonalOf[c]!.name,
          },
      },
      'groups': [
        for (final f in RingFunction.values)
          {
            'function': _idJson[f],
            'nameFr': _nameFr[f],
            'descriptionFr': _descFr[f],
            if (_stepOf[f] != null) 'stepFromOwnStart': _stepOf[f],
            'safe': f == RingFunction.start || f == RingFunction.safeStar,
            'cells': cellsWithFunction(f),
            if (f != RingFunction.normal && f != RingFunction.chance)
              'byColor': {
                for (final c in PlayerColor.values)
                  c.name: (startIndexOf[c]! + _stepOf[f]!) % ring.length,
              },
          },
      ],
      'cells': [for (int id = 0; id < ring.length; id++) _cellJson(id)],
    };

/// La même carte, mise en forme sur plusieurs lignes.
String ringMapJsonString() =>
    const JsonEncoder.withIndent('  ').convert(ringMapJson());
