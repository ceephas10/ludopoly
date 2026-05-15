// LudoPoly — Step 1: static board with 4 players at starting positions
// rendered from the GameState model, with a debug overlay for the 52-cell ring.

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'game/board_painter.dart';
import 'game/board_path.dart';
import 'game/game_controller.dart';
import 'game/game_state.dart';
import 'game/pawn.dart';
import 'game/player_color.dart';
export 'game/player_color.dart';

void main() => runApp(const LudoPolyApp());

class LudoPolyApp extends StatelessWidget {
  const LudoPolyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPoly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const BoardScreen(),
    );
  }
}

class Player {
  final String name;
  final PlayerColor color;
  const Player(this.name, this.color);
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  static const players = <Player>[
    Player('Player 1', PlayerColor.blue),
    Player('Player 2', PlayerColor.red),
    Player('Player 3', PlayerColor.green),
    Player('Player 4', PlayerColor.yellow),
  ];

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final GameState _game = GameState.initial();
  late final GameController _controller = GameController(
    turnOrder: BoardScreen.players.map((p) => p.color).toList(),
    state: _game,
  );
  bool _showRing = false;
  bool _showGrid = false;
  int _playerCount = 4;

  /// Dice value displayed in each player's corner slot. Sticks to the last
  /// rolled value so non-active players still see a face. Driven by the
  /// controller for the current player.
  final Map<PlayerColor, int> _diceValues = {
    PlayerColor.blue:   1,
    PlayerColor.red:    1,
    PlayerColor.green:  1,
    PlayerColor.yellow: 1,
  };

  void _rollDice() {
    if (_controller.phase != TurnPhase.rolling) return;
    setState(() {
      _controller.rollRandom();
      _diceValues[_controller.currentColor] = _controller.diceValue;
    });
  }

  void _setDice(int value) {
    if (_controller.phase != TurnPhase.rolling) return;
    setState(() {
      _controller.roll(value);
      _diceValues[_controller.currentColor] = _controller.diceValue;
    });
  }

  void _movePawn(Pawn p) {
    if (_controller.phase != TurnPhase.moving) return;
    setState(() {
      _controller.movePawn(p);
    });
  }

  void _endTurn() {
    setState(() {
      _controller.skipTurn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2541),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            // Defensive: clamp to finite values; reserve a minimum width for
            // the control panel.
            const minPanel = 260.0;
            final h = c.maxHeight.isFinite ? c.maxHeight : 800.0;
            final w = c.maxWidth.isFinite ? c.maxWidth : 1200.0;
            final boardSide = h.clamp(0.0, w - minPanel);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: boardSide,
                  height: boardSide,
                  child: BoardView(
                    players: BoardScreen.players,
                    game: _game,
                    showRing: _showRing,
                    showGrid: _showGrid,
                    playerCount: _playerCount,
                    diceValues: _diceValues,
                    currentPlayerColor: _controller.currentColor,
                    canRollDice: _controller.phase == TurnPhase.rolling,
                    movablePawns: _controller.movablePawns().toSet(),
                    onRollDice: _rollDice,
                    onPawnTap: _movePawn,
                  ),
                ),
                SizedBox(
                  width: w - boardSide,
                  height: h,
                  child: _ControlPanel(
                    showRing: _showRing,
                    onToggleRing: (v) => setState(() => _showRing = v),
                    showGrid: _showGrid,
                    onToggleGrid: (v) => setState(() => _showGrid = v),
                    playerCount: _playerCount,
                    onChangePlayerCount: (n) =>
                        setState(() => _playerCount = n),
                    currentPlayer: BoardScreen.players[
                        _controller.currentPlayerIdx],
                    phase: _controller.phase,
                    diceValue: _controller.diceValue,
                    consecutiveSixes: _controller.consecutiveSixes,
                    winner: _controller.winner,
                    onForceDice: _setDice,
                    onEndTurn: _endTurn,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Right-side panel: debug switches and developer actions.
class _ControlPanel extends StatelessWidget {
  final bool showRing;
  final ValueChanged<bool> onToggleRing;
  final bool showGrid;
  final ValueChanged<bool> onToggleGrid;
  final int playerCount;
  final ValueChanged<int> onChangePlayerCount;
  final Player currentPlayer;
  final TurnPhase phase;
  final int diceValue;
  final int consecutiveSixes;
  final PlayerColor? winner;
  final ValueChanged<int> onForceDice;
  final VoidCallback onEndTurn;

  const _ControlPanel({
    required this.showRing,
    required this.onToggleRing,
    required this.showGrid,
    required this.onToggleGrid,
    required this.playerCount,
    required this.onChangePlayerCount,
    required this.currentPlayer,
    required this.phase,
    required this.diceValue,
    required this.consecutiveSixes,
    required this.winner,
    required this.onForceDice,
    required this.onEndTurn,
  });

  Color _playerColor(PlayerColor c) {
    switch (c) {
      case PlayerColor.yellow: return const Color(0xFFE6B800);
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
    }
  }

  String _phaseText() {
    switch (phase) {
      case TurnPhase.rolling:
        return 'roll dice…';
      case TurnPhase.moving:
        return 'rolled $diceValue — pick a pawn';
      case TurnPhase.gameOver:
        return 'game over';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF22305A),
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Debug controls',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Current player + state info.
          Row(
            children: [
              const Text('Turn: ',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _playerColor(currentPlayer.color),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  currentPlayer.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _phaseText(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          if (consecutiveSixes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$consecutiveSixes × 6',
                style: const TextStyle(color: Colors.amber, fontSize: 11),
              ),
            ),
          if (winner != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '🏆 ${winner!.name.toUpperCase()} WINS',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Force dice',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int v = 1; v <= 6; v++)
                _MiniDiceButton(value: v, onTap: () => onForceDice(v)),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.skip_next),
            label: const Text('End turn (skip)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: onEndTurn,
          ),
          const Divider(color: Colors.white24, height: 24),
          const Text('Nb players',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 6, label: Text('6')),
            ],
            selected: {playerCount},
            onSelectionChanged: (s) => onChangePlayerCount(s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? Colors.black
                      : Colors.white),
              backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? Colors.amber
                      : Colors.transparent),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Show ring',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Numbered overlay of the 52 ring cells',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: showRing,
            onChanged: onToggleRing,
            activeThumbColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Show grid 15x15',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Numbered overlay of every cell (0..224)',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: showGrid,
            onChanged: onToggleGrid,
            activeThumbColor: Colors.amber,
            contentPadding: EdgeInsets.zero,
          ),
        ],
        ),
      ),
    );
  }
}

/// Renders the board image, the pawn name labels, and every pawn at its
/// current location (base / ring / home column / home).
class BoardView extends StatelessWidget {
  final List<Player> players;
  final GameState game;
  final bool showRing;
  final bool showGrid;
  final int playerCount;
  final Map<PlayerColor, int> diceValues;
  final PlayerColor currentPlayerColor;
  final bool canRollDice;
  final Set<Pawn> movablePawns;
  final VoidCallback onRollDice;
  final ValueChanged<Pawn> onPawnTap;
  const BoardView({
    super.key,
    required this.players,
    required this.game,
    required this.diceValues,
    required this.currentPlayerColor,
    required this.canRollDice,
    required this.movablePawns,
    required this.onRollDice,
    required this.onPawnTap,
    this.showRing = false,
    this.showGrid = false,
    this.playerCount = 4,
  });

  // Top-left grid cell of each colored base (the board is a 15x15 grid).
  // New layout: red TL, green TR, blue BL, yellow BR.
  static const Map<PlayerColor, Offset> _baseCorner = {
    PlayerColor.red:    Offset(0, 0),
    PlayerColor.green:  Offset(9, 0),
    PlayerColor.blue:   Offset(0, 9),
    PlayerColor.yellow: Offset(9, 9),
  };

  // Horizontal X positions (in cell units relative to base top-left) of the
  // 4 pawn slots inside a base. Y is computed dynamically so the pawn bbox
  // is stuck to the top of the (enlarged) white inner area with a 3px margin.
  static const List<double> _spotsX = [1.5, 2.5, 3.5, 4.5];

  /// 3px gap between the inner-white top edge and the pawn bbox top.
  static const double _pawnTopMarginPx = 3.0;

  // Center of each player's dice, in global cell coordinates. Each dice
  // occupies the 2x2 cell square diagonally inward from the base's outer
  // corner: red 32/33/47/48, green 41/42/56/57, blue 167/168/182/183,
  // yellow 176/177/191/192.
  static const Map<PlayerColor, Offset> _diceCenter = {
    PlayerColor.red:    Offset(3.0,  3.0),
    PlayerColor.green:  Offset(12.0, 3.0),
    PlayerColor.blue:   Offset(3.0,  12.0),
    PlayerColor.yellow: Offset(12.0, 12.0),
  };

  static const Map<PlayerColor, String> _pawnAsset = {
    PlayerColor.yellow: 'Animations/AnimStock/Tokens/GIF/Pawn_standard_yellow_idle_20260514_13h45.gif',
    PlayerColor.blue:   'Animations/AnimStock/Tokens/GIF/Pawn_standard_blue_idle_20260514_13h45.gif',
    PlayerColor.red:    'Animations/AnimStock/Tokens/GIF/Pawn_standard_red_idle_20260514_13h45.gif',
    PlayerColor.green:  'Animations/AnimStock/Tokens/GIF/Pawn_standard_green_idle_20260514_13h45.gif',
  };

  // Center (in cell units) of each player's name label, placed in the
  // bottom row of its base. Targets: red 77/78, green 86/87, blue 212/213,
  // yellow 221/222 — center sits on the shared edge of those two cells.
  static const Map<PlayerColor, Offset> _labelCenter = {
    PlayerColor.red:    Offset(3.0,  5.5),
    PlayerColor.green:  Offset(12.0, 5.5),
    PlayerColor.blue:   Offset(3.0,  14.5),
    PlayerColor.yellow: Offset(12.0, 14.5),
  };

  /// Visual center of a pawn given its color and base slot (0..3).
  /// The pawn image has ~1 cell of transparent padding at the top of its
  /// bbox; we shift the bbox up by 1 cell so the visible helmet sits 3px
  /// below the top of the colored base.
  Offset _baseSlotCenter(
      PlayerColor color, int slot, double cell, double pawnHeight) {
    final corner = _baseCorner[color]!;
    final cx = (corner.dx + _spotsX[slot]) * cell;
    final baseTopPx = corner.dy * cell;
    final bboxTopPx = baseTopPx + _pawnTopMarginPx - cell;
    final cy = bboxTopPx + pawnHeight * 0.55;
    return Offset(cx, cy);
  }

  /// Visual center of a pawn sitting on ring cell [index]. The cell stores
  /// its center in cell-units; we just scale to pixels.
  Offset _ringCellCenter(int index, double cell) => ring[index].pos * cell;

  /// Resolve a pawn's visual center in board coordinates.
  Offset _pawnCenter(Pawn p, double cell, double pawnHeight) {
    switch (p.location) {
      case PawnLocation.base:
        return _baseSlotCenter(p.color, p.position, cell, pawnHeight);
      case PawnLocation.ring:
        return _ringCellCenter(p.position, cell);
      case PawnLocation.homeColumn:
        return _homeColumnCenter(p.color, p.position, cell);
      case PawnLocation.home:
        return Offset(7.5 * cell, 7.5 * cell);
    }
  }

  /// Center of home-column cell [position] (0..4) for the given [color].
  /// Position 0 = entry from ring, position 4 = cell just before center.
  Offset _homeColumnCenter(PlayerColor color, int position, double cell) {
    final p = position.toDouble();
    late double col, row;
    switch (color) {
      case PlayerColor.blue:
        col = 7;      row = 13 - p; break;
      case PlayerColor.red:
        col = 1 + p;  row = 7;      break;
      case PlayerColor.green:
        col = 7;      row = 1 + p;  break;
      case PlayerColor.yellow:
        col = 13 - p; row = 7;      break;
    }
    return Offset((col + 0.5) * cell, (row + 0.5) * cell);
  }

  @override
  Widget build(BuildContext context) {
    // 5- and 6-player boards use a polygonal layout (no 15x15 grid, no
    // pawns/labels yet — first pass focuses on the board geometry). A single
    // shared dice sits in the central dark hexagon.
    if (playerCount != 4) {
      return LayoutBuilder(
        builder: (context, c) {
          final side = c.biggest.shortestSide;
          final diceSize =
              side * _PolygonBoardPainter.diceSizeFraction(playerCount);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                    painter: _PolygonBoardPainter(n: playerCount)),
              ),
              if (showRing && playerCount == 5)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PolygonRingDebugPainter(n: playerCount),
                    ),
                  ),
                ),
              Positioned(
                left: (c.biggest.width - diceSize) / 2,
                top: (c.biggest.height - diceSize) / 2,
                width: diceSize,
                height: diceSize,
                child: const _DiceFace(value: 1, color: Colors.white),
              ),
            ],
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final side = c.biggest.shortestSide;
        final cell = side / 15.0;

        // Pawn ~ 4 cells tall (user requested "2x bigger" vs previous 2-cell).
        final pawnHeight = cell * 4.0;
        // Pawn aspect ratio derived from the source image bbox (236x338).
        final pawnWidth = pawnHeight * (236.0 / 338.0);

        return Stack(
          children: [
            // Vector-drawn board: stays crisp at any size (no raster scaling).
            const Positioned.fill(
              child: CustomPaint(painter: BoardPainter()),
            ),

            // Player name labels — sitting in the bottom row of each base.
            for (final p in players)
              () {
                final lc = _labelCenter[p.color]!;
                final w = cell * 2.4;
                final h = cell * 0.8;
                return Positioned(
                  left: lc.dx * cell - w / 2,
                  top:  lc.dy * cell - h / 2,
                  width: w,
                  height: h,
                  child: Center(
                    child: _PlayerLabel(
                        name: p.name, color: _colorOf(p.color)),
                  ),
                );
              }(),

            // One dice per player. The current player's dice is fully opaque
            // and clickable while we're in the rolling phase; the others are
            // dimmed.
            for (final p in players)
              () {
                final dc = _diceCenter[p.color]!;
                final size = cell * 2.0;
                final isCurrent = p.color == currentPlayerColor;
                final clickable = isCurrent && canRollDice;
                return Positioned(
                  left: dc.dx * cell - size / 2,
                  top:  dc.dy * cell - size / 2,
                  width: size,
                  height: size,
                  child: MouseRegion(
                    cursor: clickable
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      onTap: clickable ? onRollDice : null,
                      child: Opacity(
                        opacity: isCurrent ? 1.0 : 0.4,
                        child: _DiceFace(
                          value: diceValues[p.color] ?? 1,
                          color: _colorOf(p.color),
                        ),
                      ),
                    ),
                  ),
                );
              }(),

            // Every pawn, rendered at its current model position. Pawns the
            // current player can move with the rolled dice are highlighted
            // and tappable.
            ...() sync* {
              final list = game.allPawns.toList();
              // Per-pawn delays = the multiples of 100 ms in random order.
              // ValueKey'd state preservation means only the first build's
              // shuffle counts — subsequent rebuilds re-compute it but never
              // re-trigger _init() inside the pawn widget.
              final delays =
                  List.generate(list.length, (i) => i * 100)
                    ..shuffle(math.Random());
              for (int i = 0; i < list.length; i++) {
                final pawn = list[i];
                final center = _pawnCenter(pawn, cell, pawnHeight);
                final isMovable = movablePawns.contains(pawn);
                yield Positioned(
                  left: center.dx - pawnWidth / 2,
                  top:  center.dy - pawnHeight * 0.55,
                  width: pawnWidth,
                  height: pawnHeight,
                  child: MouseRegion(
                    cursor: isMovable
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      onTap: isMovable ? () => onPawnTap(pawn) : null,
                      child: _PawnAnimatedGif(
                        key: ValueKey('${pawn.color.name}_${pawn.id}'),
                        asset: _pawnAsset[pawn.color]!,
                        sequentialStartDelayMs: delays[i],
                      ),
                    ),
                  ),
                );
              }
            }(),

            // Debug overlay: numbered dots on every ring cell.
            if (showRing)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RingDebugPainter(cell: cell)),
                ),
              ),

            // Debug overlay: 15x15 grid with cell numbers (0..224, row-major).
            if (showGrid)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GridDebugPainter(cell: cell)),
                ),
              ),
          ],
        );
      },
    );
  }

  static Color _colorOf(PlayerColor c) {
    switch (c) {
      case PlayerColor.yellow: return const Color(0xFFE6B800);
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
    }
  }
}

/// Paints small numbered markers on every ring cell + emphasizes safe cells.
class _RingDebugPainter extends CustomPainter {
  final double cell;
  _RingDebugPainter({required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final normal = Paint()..color = const Color(0xCCFF00FF);
    final start = Paint()..color = const Color(0xCCFFC107);
    final star = Paint()..color = const Color(0xCC00E5FF);
    for (final c in ring) {
      final cx = c.pos.dx * cell;
      final cy = c.pos.dy * cell;
      Paint p;
      switch (c.type) {
        case CellType.start:     p = start; break;
        case CellType.safeStar:  p = star; break;
        case CellType.normal:    p = normal; break;
      }
      canvas.drawCircle(Offset(cx, cy), cell * 0.18, p);

      final tp = TextPainter(
        text: TextSpan(
          text: '${c.index}',
          style: TextStyle(
            color: Colors.white,
            fontSize: cell * 0.28,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RingDebugPainter old) => old.cell != cell;
}

/// Debug overlay for the 5-player ring: numbered magenta dots on every ring
/// cell, mirroring the 4-player [_RingDebugPainter] but for the polygonal
/// layout produced by [_PolygonBoardPainter].
class _PolygonRingDebugPainter extends CustomPainter {
  final int n;
  _PolygonRingDebugPainter({required this.n});

  @override
  void paint(Canvas canvas, Size size) {
    if (n != 5) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final c = _PolygonBoardPainter.cellSize5(
        math.min(size.width, size.height));
    final positions = _PolygonBoardPainter.ringPositions5(cx, cy, c);

    final dotPaint = Paint()..color = const Color(0xCCFF00FF);
    final dotR = c * 0.22;
    final fontSize = c * 0.32;
    for (int i = 0; i < positions.length; i++) {
      final p = positions[i];
      canvas.drawCircle(p, dotR, dotPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonRingDebugPainter old) => old.n != n;
}

/// Paints a 15x15 grid above the board with each cell's index (row-major,
/// 0..224). Used as a coordinate ruler when designing the board geometry.
class _GridDebugPainter extends CustomPainter {
  final double cell;
  _GridDebugPainter({required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xAAFF00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final side = cell * 15.0;
    for (int i = 0; i <= 15; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, side), line);
      canvas.drawLine(Offset(0, p), Offset(side, p), line);
    }
    final fontSize = cell * 0.28;
    for (int r = 0; r < 15; r++) {
      for (int c = 0; c < 15; c++) {
        final idx = r * 15 + c;
        final tp = TextPainter(
          text: TextSpan(
            text: '$idx',
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            c * cell + (cell - tp.width) / 2,
            r * cell + (cell - tp.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridDebugPainter old) => old.cell != cell;
}

/// Painter for 5- and 6-player Ludo boards (5p detailed, 6p still a rough
/// placeholder).
///
/// 5p geometry (matches the LudoKing 5p reference):
///   - 5 radial arms at 72° intervals starting from the bottom (player 1).
///   - Each arm is 3 cells wide × 6 cells long. The middle column holds the
///     5 colored home-stretch cells; the side columns hold ring cells.
///   - A triangular colored BASE sits at the outer end of each arm, with a
///     smaller white token triangle inside for the 4 tokens.
///   - A central PENTAGON home is split into 5 colored triangles converging
///     to a small DARK pentagon at the very center (where the dice sits).
class _PolygonBoardPainter extends CustomPainter {
  final int n;
  const _PolygonBoardPainter({required this.n});

  // Standard Ludo King wedge colors going CCW visual (= CCW math because +y
  // is down) from the bottom (player 1).
  static const Map<int, List<Color>> _wedgeColors = {
    5: [Color(0xFF3DA4EC), Color(0xFFFF8A2C), Color(0xFF4FAE5D),
        Color(0xFFE94B4B), Color(0xFFFFCE2E)],
    6: [Color(0xFF3DA4EC), Color(0xFFFF8A2C), Color(0xFF4FAE5D),
        Color(0xFFE94B4B), Color(0xFFFFCE2E), Color(0xFF9B59B6)],
  };

  /// Cell-grid parameters for the 5p board.
  static const int _innerCells5 = 3;  // central pentagon "radius" in cells
  static const int _armLen5     = 6;  // arm length in cells
  static const int _armWidth5   = 3;  // arm width in cells
  static const int _baseExtra5  = 3;  // base extension beyond arm, in cells

  /// Total span of the 5p board in cells (diameter / 2 + margin).
  static double _totalCells5() =>
      (_innerCells5 + _armLen5 + _baseExtra5).toDouble();

  /// Returns the fraction of board side where the dice should be positioned
  /// (i.e. inscribed circle radius of the central black pentagon, divided by
  /// the board's smaller side). Used by [BoardView] to size the central dice.
  static double diceSizeFraction(int n) {
    if (n == 5) {
      return 0.07;
    }
    return 0.06; // 6p placeholder
  }

  /// Cell size for the 5p layout given a square viewport of [shortSide].
  static double cellSize5(double shortSide) =>
      shortSide / (2 * (_totalCells5() + 1));

  /// The 65 ring cell centers for the 5-player board, going CW visually
  /// starting at the outer end of arm 0 (player 1, bottom) LEFT column.
  /// Section k (cells 13k..13k+12) covers arm k's left column going inward
  /// (6 cells), one transition cell at the central pentagon vertex between
  /// arm k and arm k+1, and arm (k+1)'s right column going outward (6 cells).
  static List<Offset> ringPositions5(double cx, double cy, double c) {
    final cells = <Offset>[];
    final rInner = _innerCells5 * c;
    for (int k = 0; k < 5; k++) {
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final rHat = Offset(math.cos(theta), math.sin(theta));
      final tHat = Offset(-math.sin(theta), math.cos(theta));

      // 6 cells along arm k's LEFT col (+tHat), going INWARD (row 5 → 0).
      for (int row = 5; row >= 0; row--) {
        final r = rInner + (row + 0.5) * c;
        cells.add(Offset(
          cx + r * rHat.dx + c * tHat.dx,
          cy + r * rHat.dy + c * tHat.dy,
        ));
      }

      // 1 transition cell at the central pentagon vertex between arm k and
      // arm k+1 (at angle theta + 36°).
      final transAngle = theta + math.pi / 5;
      cells.add(Offset(
        cx + rInner * math.cos(transAngle),
        cy + rInner * math.sin(transAngle),
      ));

      // 6 cells along arm (k+1)'s RIGHT col (-tHat), going OUTWARD (row 0 → 5).
      final kNext = (k + 1) % 5;
      final thetaN = math.pi / 2 + (2 * math.pi / 5) * kNext;
      final rHatN = Offset(math.cos(thetaN), math.sin(thetaN));
      final tHatN = Offset(-math.sin(thetaN), math.cos(thetaN));
      for (int row = 0; row < 6; row++) {
        final r = rInner + (row + 0.5) * c;
        cells.add(Offset(
          cx + r * rHatN.dx - c * tHatN.dx,
          cy + r * rHatN.dy - c * tHatN.dy,
        ));
      }
    }
    return cells;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Backdrop.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A2541),
    );
    if (n == 5) {
      _paint5(canvas, size);
    } else {
      _paint6Rough(canvas, size);
    }
  }

  /// Detailed 5-player board: 5 radial arms (3×6 cells), 5 triangular bases,
  /// central colored pentagon with 5 sections + small dark inner pentagon.
  void _paint5(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final c = cellSize5(math.min(size.width, size.height));
    final rInner    = _innerCells5 * c;
    final rArmOuter = rInner + _armLen5 * c;
    final rBaseOuter = rArmOuter + _baseExtra5 * c;
    final halfArm = (_armWidth5 / 2) * c;
    final halfBase = halfArm + c; // base widens by 1 cell on each side
    final colors = _wedgeColors[5]!;

    final gridPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, c * 0.04);

    for (int k = 0; k < 5; k++) {
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final rHat = Offset(math.cos(theta), math.sin(theta));
      final tHat = Offset(-math.sin(theta), math.cos(theta));
      final color = colors[k];

      Offset p(double r, double t) =>
          Offset(cx + r * rHat.dx + t * tHat.dx,
                 cy + r * rHat.dy + t * tHat.dy);

      // 1) ARM background (white rectangle from rInner to rArmOuter).
      final armPath = Path()
        ..moveTo(p(rInner, -halfArm).dx, p(rInner, -halfArm).dy)
        ..lineTo(p(rArmOuter, -halfArm).dx, p(rArmOuter, -halfArm).dy)
        ..lineTo(p(rArmOuter, halfArm).dx, p(rArmOuter, halfArm).dy)
        ..lineTo(p(rInner, halfArm).dx, p(rInner, halfArm).dy)
        ..close();
      canvas.drawPath(armPath, Paint()..color = Colors.white);

      // 2) HOME STRETCH: 5 colored cells in the middle column.
      // Inner cell (closest to center) = row 0, outer cell = row 4.
      // The 6th cell (row 5) at the outer end of middle column is the ring
      // entry cell into the home stretch (white, but reserved for the entry).
      for (int row = 0; row < 5; row++) {
        final r0 = rInner + row * c;
        final r1 = r0 + c;
        final cellPath = Path()
          ..moveTo(p(r0, -0.5 * c).dx, p(r0, -0.5 * c).dy)
          ..lineTo(p(r1, -0.5 * c).dx, p(r1, -0.5 * c).dy)
          ..lineTo(p(r1, 0.5 * c).dx, p(r1, 0.5 * c).dy)
          ..lineTo(p(r0, 0.5 * c).dx, p(r0, 0.5 * c).dy)
          ..close();
        canvas.drawPath(cellPath, Paint()..color = color);
      }

      // 3) GRID lines on the arm (3 cols × 6 rows).
      for (int i = 0; i <= _armWidth5; i++) {
        final t = (i - _armWidth5 / 2) * c;
        canvas.drawLine(p(rInner, t), p(rArmOuter, t), gridPaint);
      }
      for (int i = 0; i <= _armLen5; i++) {
        final r = rInner + i * c;
        canvas.drawLine(p(r, -halfArm), p(r, halfArm), gridPaint);
      }

      // 4) BASE trapezoid (colored, widening outward) at the outer end of
      // the arm.
      final basePath = Path()
        ..moveTo(p(rArmOuter, -halfArm).dx,  p(rArmOuter, -halfArm).dy)
        ..lineTo(p(rBaseOuter, -halfBase).dx, p(rBaseOuter, -halfBase).dy)
        ..lineTo(p(rBaseOuter,  halfBase).dx, p(rBaseOuter,  halfBase).dy)
        ..lineTo(p(rArmOuter,   halfArm).dx,  p(rArmOuter,   halfArm).dy)
        ..close();
      canvas.drawPath(basePath, Paint()..color = color);

      // 5) Inner WHITE token triangle inside the base: an isoceles triangle
      // pointing toward the center (apex inward).
      final innerInset = 0.30; // fraction of base width/height to inset
      final apexInner = p(rArmOuter + (rBaseOuter - rArmOuter) * 0.25, 0);
      final outerLeft  = p(rBaseOuter - (rBaseOuter - rArmOuter) * 0.15,
                           -halfBase + (halfBase * 2) * innerInset);
      final outerRight = p(rBaseOuter - (rBaseOuter - rArmOuter) * 0.15,
                            halfBase - (halfBase * 2) * innerInset);
      final tokenTri = Path()
        ..moveTo(apexInner.dx, apexInner.dy)
        ..lineTo(outerLeft.dx, outerLeft.dy)
        ..lineTo(outerRight.dx, outerRight.dy)
        ..close();
      canvas.drawPath(tokenTri, Paint()..color = Colors.white);
    }

    // 6) Central HOME pentagon: 5 colored triangles converging at center.
    for (int k = 0; k < 5; k++) {
      final color = colors[k];
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final aLeft  = theta - math.pi / 5;
      final aRight = theta + math.pi / 5;
      final left = Offset(
          cx + rInner * math.cos(aLeft), cy + rInner * math.sin(aLeft));
      final right = Offset(
          cx + rInner * math.cos(aRight), cy + rInner * math.sin(aRight));
      final tri = Path()
        ..moveTo(cx, cy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = color);
    }

    // 7) Inner small DARK pentagon (the dice slot).
    final rBlack = rInner * 0.55;
    final blackPath = Path();
    for (int i = 0; i < 5; i++) {
      final a = math.pi / 2 + (2 * math.pi / 5) * i;
      final px = cx + rBlack * math.cos(a);
      final py = cy + rBlack * math.sin(a);
      if (i == 0) {
        blackPath.moveTo(px, py);
      } else {
        blackPath.lineTo(px, py);
      }
    }
    blackPath.close();
    canvas.drawPath(blackPath, Paint()..color = const Color(0xFF1A2541));
  }

  /// 6-player placeholder: same rough wedge sketch as before (to be detailed
  /// after the 5p layout is locked in).
  void _paint6Rough(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(cx, cy) * 0.92;
    Offset vert(int i) {
      final a = math.pi / 2 - math.pi / 6 + (math.pi / 3) * i;
      return Offset(cx + R * math.cos(a), cy + R * math.sin(a));
    }
    final outer = Path()..moveTo(vert(0).dx, vert(0).dy);
    for (int i = 1; i < 6; i++) {
      outer.lineTo(vert(i).dx, vert(i).dy);
    }
    outer.close();
    canvas.drawPath(outer, Paint()..color = Colors.white);
    final colors = _wedgeColors[6]!;
    const insetFactor = 0.82;
    for (int i = 0; i < 6; i++) {
      final v0 = vert(i);
      final v1 = vert((i + 1) % 6);
      final p0 = Offset(cx + (v0.dx - cx) * insetFactor,
                        cy + (v0.dy - cy) * insetFactor);
      final p1 = Offset(cx + (v1.dx - cx) * insetFactor,
                        cy + (v1.dy - cy) * insetFactor);
      final wedge = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(cx, cy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = colors[i]);
    }
    final innerR = R * 0.14;
    final inner = Path();
    for (int i = 0; i < 6; i++) {
      final a = math.pi / 2 - math.pi / 6 + (math.pi / 3) * i;
      final x = cx + innerR * math.cos(a);
      final y = cy + innerR * math.sin(a);
      if (i == 0) {
        inner.moveTo(x, y);
      } else {
        inner.lineTo(x, y);
      }
    }
    inner.close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFF1A2541));
  }

  @override
  bool shouldRepaint(covariant _PolygonBoardPainter old) => old.n != n;
}

/// Decoded frames of a GIF, shared across all pawns of the same color so we
/// pay the decode cost only once per asset.
class _GifFrames {
  final List<ui.Image> images;
  final List<Duration> durations;
  _GifFrames(this.images, this.durations);

  static final Map<String, Future<_GifFrames>> _cache = {};

  static Future<_GifFrames> load(String asset) {
    return _cache.putIfAbsent(asset, () async {
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final images = <ui.Image>[];
      final durations = <Duration>[];
      for (int i = 0; i < codec.frameCount; i++) {
        final f = await codec.getNextFrame();
        images.add(f.image);
        durations.add(f.duration);
      }
      codec.dispose();
      return _GifFrames(images, durations);
    });
  }
}

/// Renders an idle pawn GIF, with the first frame appearing as soon as the
/// asset is decoded. After [sequentialStartDelayMs] elapses, the widget
/// starts cycling through frames at the pace described by the GIF metadata.
/// Each instance keeps its OWN `_frameIdx` so the 16 pawns visibly desync.
class _PawnAnimatedGif extends StatefulWidget {
  final String asset;
  final int sequentialStartDelayMs;
  const _PawnAnimatedGif({
    super.key,
    required this.asset,
    required this.sequentialStartDelayMs,
  });

  @override
  State<_PawnAnimatedGif> createState() => _PawnAnimatedGifState();
}

class _PawnAnimatedGifState extends State<_PawnAnimatedGif>
    with SingleTickerProviderStateMixin {
  _GifFrames? _frames;
  int _frameIdx = 0;
  Ticker? _ticker;
  Duration _accum = Duration.zero;
  Duration? _lastTickTime;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final frames = await _GifFrames.load(widget.asset);
      if (!mounted) return;
      setState(() => _frames = frames);

      await Future<void>.delayed(
        Duration(milliseconds: widget.sequentialStartDelayMs),
      );
      if (!mounted) return;
      _ticker = createTicker(_onTick)..start();
    } catch (e, st) {
      debugPrint('Animated GIF load failed for ${widget.asset}: $e\n$st');
    }
  }

  void _onTick(Duration elapsed) {
    final frames = _frames;
    if (frames == null || frames.images.isEmpty) return;

    _lastTickTime ??= elapsed;
    final dt = elapsed - _lastTickTime!;
    _lastTickTime = elapsed;
    _accum += dt;

    bool changed = false;
    // Loop over frames until the accumulated time fits in the current one.
    while (_accum >= frames.durations[_frameIdx] &&
        frames.durations[_frameIdx] > Duration.zero) {
      _accum -= frames.durations[_frameIdx];
      _frameIdx = (_frameIdx + 1) % frames.images.length;
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    if (frames == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: RawImage(image: frames.images[_frameIdx]),
      ),
    );
  }
}

/// Small clickable dice button used in the debug panel to force a specific
/// dice value (1..6) for deterministic testing.
class _MiniDiceButton extends StatelessWidget {
  final int value;
  final VoidCallback onTap;
  const _MiniDiceButton({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black54),
          ),
          child: Center(
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dice at rest, rendered from a photographic PNG asset. The colored player
/// frame around it is dropped in favor of the realistic look.
class _DiceFace extends StatelessWidget {
  final int value;
  final Color color;
  const _DiceFace({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Image.asset(
        'Animations/AnimStock/Dices/Dice_White_3D.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _PlayerLabel extends StatelessWidget {
  final String name;
  final Color color;
  const _PlayerLabel({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
