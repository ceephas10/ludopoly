// 1D ribbon of cells that make the Ludo ring (52 cells for 4 players, more
// for 5/6).
//
// Each cell stores its position and displacement to the NEXT cell as 2D
// vectors in CELL UNITS (1.0 = the side of one grid cell). The geometry is
// not constrained to an integer grid: 4-player rings happen to fall on a
// 15x15 grid but 5/6-player rings will be on a polygon with diagonal
// displacements at arbitrary angles. Consumers multiply by the pixel-per-
// cell scale at paint time.
//
// Numbering convention (4p): cell 0 is the BLUE starting square. Indices
// grow clockwise: cell 13 = RED start, 26 = GREEN start, 39 = YELLOW start.

import 'package:flutter/painting.dart' show Offset;

import 'pawn.dart';
import 'player_color.dart';

/// What kind of cell this is on the ring.
enum CellType {
  /// Plain cell — pawns can be captured here.
  normal,
  /// One of the 4 starting squares. Safe zone; multiple colors can stack.
  start,
  /// One of the 4 "star" safe zones spread around the ring.
  safeStar,
}

class RingCell {
  /// 0..N-1 along the ring.
  final int index;

  /// Cell center in cell-units. For 4p this is `(col + 0.5, row + 0.5)` on
  /// the 15×15 grid; for 5/6p it falls anywhere on a polygon.
  final Offset pos;

  /// Vector to the next ring cell, in cell-units (`ring[i+1].pos - ring[i].pos`).
  /// Magnitude can exceed 1.0 on diagonal corners (e.g. ~√2 for a 45° turn).
  final Offset dir;

  final CellType type;
  final PlayerColor? startsHere; // non-null iff type == start

  /// Pawns currently sitting on this cell (mutable runtime state).
  final List<Pawn> pawns = [];

  RingCell({
    required this.index,
    required this.pos,
    required this.dir,
    required this.type,
    this.startsHere,
  });

  bool get isSafe => type != CellType.normal;
}

/// Cell-center positions of every ring cell, in cell-units, clockwise from
/// the BLUE entry. Stored as [Offset] so 5/6-player rings (which fall off
/// integer grids) can use the same representation.
const List<Offset> _path = [
  // 0..4 — bottom arm left edge (going up)
  Offset(6.5, 13.5), Offset(6.5, 12.5), Offset(6.5, 11.5),
  Offset(6.5, 10.5), Offset(6.5,  9.5),
  // 5..9 — left arm lower edge (going left)
  Offset(5.5,  8.5), Offset(4.5,  8.5), Offset(3.5,  8.5),
  Offset(2.5,  8.5), Offset(1.5,  8.5),
  // 10..12 — left edge (going up)
  Offset(0.5,  8.5), Offset(0.5,  7.5), Offset(0.5,  6.5),
  // 13..17 — left arm upper edge (going right)
  Offset(1.5,  6.5), Offset(2.5,  6.5), Offset(3.5,  6.5),
  Offset(4.5,  6.5), Offset(5.5,  6.5),
  // 18..23 — top arm left edge (going up)
  Offset(6.5,  5.5), Offset(6.5,  4.5), Offset(6.5,  3.5),
  Offset(6.5,  2.5), Offset(6.5,  1.5), Offset(6.5,  0.5),
  // 24..25 — top of top arm (going right)
  Offset(7.5,  0.5), Offset(8.5,  0.5),
  // 26..30 — top arm right edge (going down)
  Offset(8.5,  1.5), Offset(8.5,  2.5), Offset(8.5,  3.5),
  Offset(8.5,  4.5), Offset(8.5,  5.5),
  // 31..36 — right arm upper edge (going right)
  Offset(9.5,  6.5), Offset(10.5, 6.5), Offset(11.5, 6.5),
  Offset(12.5, 6.5), Offset(13.5, 6.5), Offset(14.5, 6.5),
  // 37..38 — right edge (going down)
  Offset(14.5, 7.5), Offset(14.5, 8.5),
  // 39..43 — right arm lower edge (going left)
  Offset(13.5, 8.5), Offset(12.5, 8.5), Offset(11.5, 8.5),
  Offset(10.5, 8.5), Offset(9.5,  8.5),
  // 44..49 — bottom arm right edge (going down)
  Offset(8.5,  9.5), Offset(8.5, 10.5), Offset(8.5, 11.5),
  Offset(8.5, 12.5), Offset(8.5, 13.5), Offset(8.5, 14.5),
  // 50..51 — bottom of bottom arm (going left)
  Offset(7.5, 14.5), Offset(6.5, 14.5),
];

const Map<int, PlayerColor> _startsByIndex = {
  0:  PlayerColor.blue,
  13: PlayerColor.red,
  26: PlayerColor.green,
  39: PlayerColor.yellow,
};

// Stars: the 4 safe cells, 8 steps after each color's start.
const Set<int> _safeStars = {8, 21, 34, 47};

/// Pre-built 4-player ring: 52 cells, positions on the 15×15 grid expressed
/// as cell-center vectors (col + 0.5, row + 0.5).
final List<RingCell> ring = List.generate(_path.length, (i) {
  final pos = _path[i];
  final nextPos = _path[(i + 1) % _path.length];
  final start = _startsByIndex[i];
  CellType type;
  if (start != null) {
    type = CellType.start;
  } else if (_safeStars.contains(i)) {
    type = CellType.safeStar;
  } else {
    type = CellType.normal;
  }
  return RingCell(
    index: i,
    pos: pos,
    dir: nextPos - pos,
    type: type,
    startsHere: start,
  );
});

/// The starting ring index for each player color.
const Map<PlayerColor, int> startIndexOf = {
  PlayerColor.blue:   0,
  PlayerColor.red:    13,
  PlayerColor.green:  26,
  PlayerColor.yellow: 39,
};
