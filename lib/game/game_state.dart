// Holds every pawn and exposes queries. At start, all 16 pawns are in their
// base (location = base, position = 0..3 for the 4 base slots).

import 'player_color.dart';
import 'pawn.dart';

class GameState {
  /// All 16 pawns, grouped by color (4 per color).
  final Map<PlayerColor, List<Pawn>> pawnsByColor;

  GameState._(this.pawnsByColor);

  factory GameState.initial() {
    final map = <PlayerColor, List<Pawn>>{};
    for (final color in PlayerColor.values) {
      map[color] = List.generate(
        4,
        (i) => Pawn(color: color, id: i, location: PawnLocation.base, position: i),
      );
    }
    return GameState._(map);
  }

  /// Flat iterable over all 16 pawns.
  Iterable<Pawn> get allPawns =>
      pawnsByColor.values.expand((list) => list);
}
