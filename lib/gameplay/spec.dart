// Le SQUELETTE du gameplay.
//
// Le JSON `assets/gameplay/board.json` est la source de vérité. Ce fichier
// le lit, le VÉRIFIE, et le rend exploitable par le moteur (`engine.dart`),
// qui lui obéit. Il n'invente aucune règle : ce qui n'est pas écrit dans le
// JSON n'existe pas ici.

import 'dart:convert';

/// Les couleurs que le JSON déclare dans `enums.cellType`
/// (`startRed` … `startOrange`). Seules celles qui possèdent une case de
/// départ dans l'anneau sont jouables — voir [BoardSpec.colors].
enum TokenColor { red, blue, green, yellow, purple, orange }

/// `enums.tokenStatus` du JSON, dans le même ordre.
enum TokenStatus { normal, doubleDice, halfDice, invincible }

/// La famille d'une case, déduite de son `cellType`
/// (`vortexBlue` → [vortex], appartenant à [TokenColor.blue]).
enum CellKind { normal, exit, start, star, luck, vortex, death }

/// L'`action` d'une case.
enum CellAction { move, moveExit, vortex, death, luck }

/// Le JSON est invalide : le moteur ne doit pas démarrer.
class BoardSpecError implements Exception {
  BoardSpecError(this.message);
  final String message;
  @override
  String toString() => 'BoardSpecError: $message';
}

/// Une case de l'anneau, telle que le JSON la décrit.
class CellSpec {
  const CellSpec({
    required this.id,
    required this.cellType,
    required this.kind,
    required this.color,
    required this.safe,
    required this.move,
    required this.vector,
    required this.action,
  });

  final int id;

  /// Le `cellType` brut, tel qu'écrit dans le JSON.
  final String cellType;
  final CellKind kind;

  /// La couleur propriétaire (`vortexBlue` → blue), ou `null`.
  final TokenColor? color;
  final bool safe;

  /// Le drapeau `move: true` du JSON, tel quel.
  final bool move;

  /// `vector` du JSON, en degrés ; 0 quand absent. 90 = un virage est pris.
  final int vector;
  final CellAction action;

  @override
  String toString() => 'Cell $id $cellType/${action.name}';
}

/// Le plateau, lu depuis le JSON.
class BoardSpec {
  BoardSpec._({
    required this.ring,
    required this.cellTypes,
    required this.tokenStatuses,
    required this.moveSource,
  }) : startOf = {
          for (final c in ring)
            if (c.kind == CellKind.start) c.color!: c.id,
        };

  final List<CellSpec> ring;

  /// `enums.cellType`, tel quel.
  final List<String> cellTypes;

  /// `enums.tokenStatus`, converti.
  final List<TokenStatus> tokenStatuses;

  /// `move.source` : d'où vient la valeur du déplacement (`lastDice`).
  final String moveSource;

  /// La case de départ de chaque couleur jouable.
  final Map<TokenColor, int> startOf;

  int get size => ring.length;
  CellSpec cell(int id) => ring[id];
  int next(int id) => (id + 1) % size;

  /// Les couleurs jouables, dans l'ordre de l'anneau (par case de départ).
  List<TokenColor> get colors {
    final list = startOf.keys.toList()
      ..sort((a, b) => startOf[a]!.compareTo(startOf[b]!));
    return list;
  }

  /// Les cases de la famille [kind] (et de la couleur [color], si donnée).
  List<CellSpec> cellsOf(CellKind kind, [TokenColor? color]) => [
        for (final c in ring)
          if (c.kind == kind && (color == null || c.color == color)) c,
      ];

  /// Les cases portant l'action [action].
  List<CellSpec> cellsWithAction(CellAction action) =>
      [for (final c in ring) if (c.action == action) c];

  /// Les cases où un virage est pris (`vector` non nul).
  List<CellSpec> get turns => [for (final c in ring) if (c.vector != 0) c];

  // --- lecture ------------------------------------------------------------

  static final _typeRe = RegExp(r'^(normal|star|luck|exit|start|vortex|death)'
      r'(Red|Blue|Green|Yellow|Purple|Orange)?$');

  /// Lit et vérifie le JSON. Toute anomalie lève une [BoardSpecError] qui
  /// dit quelle case, et pourquoi.
  static BoardSpec parse(String json) {
    Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw BoardSpecError('JSON illisible : ${e.message}');
    }
    if (root is! Map<String, Object?>) {
      throw BoardSpecError('la racine doit être un objet');
    }

    final enums = _map(root['enums'], 'enums');
    final cellTypes = _strings(enums['cellType'], 'enums.cellType');
    final tokenStatuses = <TokenStatus>[];
    for (final s in _strings(enums['tokenStatus'], 'enums.tokenStatus')) {
      final v = _byName(TokenStatus.values, s);
      if (v == null) throw BoardSpecError('tokenStatus inconnu : « $s »');
      tokenStatuses.add(v);
    }

    final rawRing = root['ring'];
    if (rawRing is! List || rawRing.isEmpty) {
      throw BoardSpecError('ring doit être une liste non vide');
    }
    final ring = <CellSpec>[];
    for (var i = 0; i < rawRing.length; i++) {
      final c = _map(rawRing[i], 'ring[$i]');
      final id = c['id'];
      if (id != i) throw BoardSpecError('ring[$i] : id attendu $i, trouvé $id');

      final type = c['cellType'];
      if (type is! String || !cellTypes.contains(type)) {
        throw BoardSpecError(
            'case $i : cellType « $type » absent de enums.cellType');
      }
      final m = _typeRe.firstMatch(type);
      if (m == null) {
        throw BoardSpecError('case $i : cellType « $type » incompréhensible');
      }
      final kind = CellKind.values.byName(m.group(1)!);
      final colorName = m.group(2);
      final color = colorName == null
          ? null
          : TokenColor.values.byName(colorName.toLowerCase());
      const owned = {
        CellKind.start,
        CellKind.exit,
        CellKind.vortex,
        CellKind.death,
      };
      if (owned.contains(kind) && color == null) {
        throw BoardSpecError('case $i : « $type » doit porter une couleur');
      }

      final safe = c['safe'];
      if (safe is! bool) throw BoardSpecError('case $i : safe doit être true/false');
      final move = c['move'] ?? false;
      if (move is! bool) throw BoardSpecError('case $i : move doit être true/false');
      final vector = c['vector'] ?? 0;
      if (vector is! int) throw BoardSpecError('case $i : vector doit être un entier');
      final actionName = c['action'];
      final action =
          actionName is String ? _byName(CellAction.values, actionName) : null;
      if (action == null) {
        throw BoardSpecError('case $i : action « $actionName » inconnue');
      }

      ring.add(CellSpec(
        id: i,
        cellType: type,
        kind: kind,
        color: color,
        safe: safe,
        move: move,
        vector: vector,
        action: action,
      ));
    }

    // Une couleur n'a qu'UNE case de départ, et il en faut au moins une.
    final seen = <TokenColor>{};
    for (final c in ring) {
      if (c.kind == CellKind.start && !seen.add(c.color!)) {
        throw BoardSpecError('deux cases de départ pour ${c.color!.name}');
      }
    }
    if (seen.isEmpty) {
      throw BoardSpecError('aucune case de départ : personne ne peut jouer');
    }

    final move = _map(root['move'], 'move');
    final source = move['source'];
    if (source != 'lastDice') {
      throw BoardSpecError(
          'move.source : seul « lastDice » est pris en charge, trouvé « $source »');
    }

    return BoardSpec._(
      ring: ring,
      cellTypes: cellTypes,
      tokenStatuses: tokenStatuses,
      moveSource: source as String,
    );
  }

  static T? _byName<T extends Enum>(List<T> values, String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static Map<String, Object?> _map(Object? v, String what) {
    if (v is Map<String, Object?>) return v;
    throw BoardSpecError('$what doit être un objet');
  }

  static List<String> _strings(Object? v, String what) {
    if (v is List && v.every((e) => e is String)) return v.cast<String>();
    throw BoardSpecError('$what doit être une liste de textes');
  }
}
