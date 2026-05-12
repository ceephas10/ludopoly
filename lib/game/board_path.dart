// 1D ribbon of the 52 cells that make the Ludo ring.
//
// The visual board is a 15x15 grid; the game logic only needs this linear
// ring of 52 cells (indices 0..51). Each cell stores:
//   - its (col, row) on the 15x15 visual grid (top-left = (0,0))
//   - the displacement (dCol, dRow) leading to the NEXT cell on the ring
//     (cell 51's next is cell 0; the ring is cyclic)
//   - its [type] (normal / start / safeStar)
//   - which player (if any) starts here
//   - the [pawns] currently sitting on it (mutable runtime state)
//
// Numbering convention: cell 0 is the BLUE starting square (bottom arm,
// left col, just outside the bottom-left blue base). Indices grow clockwise:
//   cell 13 = RED start, 26 = GREEN start, 39 = YELLOW start.
//
// Home columns (5 cells of the player's color leading to the center) are
// NOT part of this ribbon — a pawn leaves the ring after one lap and enters
// its own home column. Those are modeled separately, per player.

import 'player_color.dart';
import 'pawn.dart';

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
  final int index;     // 0..51
  final int col;       // 0..14 on the visual grid
  final int row;       // 0..14
  final int dCol;      // displacement to next cell (col axis)
  final int dRow;      // displacement to next cell (row axis)
  final CellType type;
  final PlayerColor? startsHere; // non-null iff type == start

  /// Pawns currently sitting on this cell.
  final List<Pawn> pawns = [];

  RingCell({
    required this.index,
    required this.col,
    required this.row,
    required this.dCol,
    required this.dRow,
    required this.type,
    this.startsHere,
  });

  bool get isSafe => type != CellType.normal;
}

/// Path positions in (col, row) screen coords, clockwise from blue entry.
const List<List<int>> _pathColRow = [
  // 0..4 — bottom arm left edge (going up)
  [6, 13], [6, 12], [6, 11], [6, 10], [6, 9],
  // 5..9 — left arm lower edge (going left)
  [5, 8], [4, 8], [3, 8], [2, 8], [1, 8],
  // 10..12 — left edge (going up)
  [0, 8], [0, 7], [0, 6],
  // 13..17 — left arm upper edge (going right)
  [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
  // 18..23 — top arm left edge (going up)
  [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0],
  // 24..25 — top of top arm (going right)
  [7, 0], [8, 0],
  // 26..30 — top arm right edge (going down)
  [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
  // 31..36 — right arm upper edge (going right)
  [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6],
  // 37..38 — right edge (going down)
  [14, 7], [14, 8],
  // 39..43 — right arm lower edge (going left)
  [13, 8], [12, 8], [11, 8], [10, 8], [9, 8],
  // 44..49 — bottom arm right edge (going down)
  [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14],
  // 50..51 — bottom of bottom arm (going left)
  [7, 14], [6, 14],
];

const Map<int, PlayerColor> _startsByIndex = {
  0:  PlayerColor.blue,
  13: PlayerColor.red,
  26: PlayerColor.green,
  39: PlayerColor.yellow,
};

// Stars: the 4 safe cells, 8 steps after each color's start.
const Set<int> _safeStars = {8, 21, 34, 47};

/// Pre-built ring: 52 cells with their displacement vectors and metadata.
final List<RingCell> ring = List.generate(52, (i) {
  final cur = _pathColRow[i];
  final next = _pathColRow[(i + 1) % 52];
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
    col: cur[0],
    row: cur[1],
    dCol: next[0] - cur[0],
    dRow: next[1] - cur[1],
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
