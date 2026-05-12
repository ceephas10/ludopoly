// Pawn model and its possible locations on the board.

import 'player_color.dart';

/// Where a pawn currently sits.
enum PawnLocation {
  base,        // still parked in the colored corner base
  ring,        // on the 52-cell outer ring
  homeColumn,  // on the 5-cell colored stretch leading to the center
  home,        // arrived at the center
}

class Pawn {
  /// Color of this pawn (and of the player who owns it).
  final PlayerColor color;

  /// 0..3 — which of the 4 pawns of this color this is.
  final int id;

  /// Current location category.
  PawnLocation location;

  /// Slot index in the base (0..3) when [location] == base.
  /// Ring index (0..51) when [location] == ring.
  /// Home column index (0..4) when [location] == homeColumn.
  /// Unused when [location] == home.
  int position;

  Pawn({
    required this.color,
    required this.id,
    this.location = PawnLocation.base,
    this.position = 0,
  });

  @override
  String toString() => 'Pawn(${color.name}#$id @ ${location.name}:$position)';
}
