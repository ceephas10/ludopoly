// LudoPoly — Step 1: static board with 4 players at starting positions
// rendered from the GameState model, with a debug overlay for the 52-cell ring.

import 'package:flutter/material.dart';
import 'game/board_painter.dart';
import 'game/board_path.dart';
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
  GameState _game = GameState.initial();
  bool _showRing = false;

  void _resetState() {
    setState(() => _game = GameState.initial());
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
                  ),
                ),
                SizedBox(
                  width: w - boardSide,
                  height: h,
                  child: _ControlPanel(
                    showRing: _showRing,
                    onToggleRing: (v) => setState(() => _showRing = v),
                    onReset: _resetState,
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
  final VoidCallback onReset;

  const _ControlPanel({
    required this.showRing,
    required this.onToggleRing,
    required this.onReset,
  });

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
          const SizedBox(height: 16),
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
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Reset state'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: onReset,
          ),
          const SizedBox(height: 8),
          const Text(
            'Real hot reload: type "r" in the flutter run terminal.\n'
            'Hot restart: type "R".',
            style: TextStyle(color: Colors.white54, fontSize: 11),
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
  const BoardView({
    super.key,
    required this.players,
    required this.game,
    this.showRing = false,
  });

  // Top-left grid cell of each colored base (the board is a 15x15 grid).
  // New layout: red TL, green TR, blue BL, yellow BR.
  static const Map<PlayerColor, Offset> _baseCorner = {
    PlayerColor.red:    Offset(0, 0),
    PlayerColor.green:  Offset(9, 0),
    PlayerColor.blue:   Offset(0, 9),
    PlayerColor.yellow: Offset(9, 9),
  };

  // 2x2 layout of pawn spots inside a base, expressed in cell coordinates
  // relative to the base's top-left corner. Index = pawn.position when in base.
  static const List<Offset> _spots = [
    Offset(2.0, 2.0),
    Offset(4.0, 2.0),
    Offset(2.0, 4.0),
    Offset(4.0, 4.0),
  ];

  static const Map<PlayerColor, String> _pawnAsset = {
    PlayerColor.yellow: 'assets/pawns/20260512_pawn_normal_yellow_idle.png',
    PlayerColor.blue:   'assets/pawns/20260512_pawn_normal_blue_idle.png',
    PlayerColor.red:    'assets/pawns/20260512_pawn_normal_red_idle.png',
    PlayerColor.green:  'assets/pawns/20260512_pawn_normal_green_idle.png',
  };

  static const Map<PlayerColor, Alignment> _labelAlignment = {
    PlayerColor.red:    Alignment.topLeft,
    PlayerColor.green:  Alignment.topRight,
    PlayerColor.blue:   Alignment.bottomLeft,
    PlayerColor.yellow: Alignment.bottomRight,
  };

  /// Visual center of a pawn given its color and base slot (0..3).
  Offset _baseSlotCenter(PlayerColor color, int slot, double cell) {
    final corner = _baseCorner[color]!;
    final spot = _spots[slot];
    return Offset((corner.dx + spot.dx) * cell, (corner.dy + spot.dy) * cell);
  }

  /// Visual center of a pawn sitting on ring cell [index]. Cell origin is at
  /// (col, row) and pawn sits centered on the cell.
  Offset _ringCellCenter(int index, double cell) {
    final c = ring[index];
    return Offset((c.col + 0.5) * cell, (c.row + 0.5) * cell);
  }

  /// Resolve a pawn's visual center in board coordinates.
  Offset _pawnCenter(Pawn p, double cell) {
    switch (p.location) {
      case PawnLocation.base:
        return _baseSlotCenter(p.color, p.position, cell);
      case PawnLocation.ring:
        return _ringCellCenter(p.position, cell);
      case PawnLocation.homeColumn:
      case PawnLocation.home:
        // TODO: implement when home columns are added.
        return _baseSlotCenter(p.color, p.id, cell);
    }
  }

  @override
  Widget build(BuildContext context) {
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

            // Player name labels at each corner.
            for (final p in players)
              Align(
                alignment: _labelAlignment[p.color]!,
                child: Padding(
                  padding: EdgeInsets.all(cell * 0.15),
                  child: _PlayerLabel(name: p.name, color: _colorOf(p.color)),
                ),
              ),

            // Every pawn, rendered at its current model position.
            for (final pawn in game.allPawns)
              () {
                final center = _pawnCenter(pawn, cell);
                return Positioned(
                  // Anchor: pawn head ~at center; tail extends below.
                  left: center.dx - pawnWidth / 2,
                  top: center.dy - pawnHeight * 0.55,
                  width: pawnWidth,
                  height: pawnHeight,
                  child: Image.asset(_pawnAsset[pawn.color]!),
                );
              }(),

            // Debug overlay: numbered dots on every ring cell.
            if (showRing)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RingDebugPainter(cell: cell)),
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
      final cx = (c.col + 0.5) * cell;
      final cy = (c.row + 0.5) * cell;
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
