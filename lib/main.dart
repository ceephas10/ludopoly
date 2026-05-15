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
  bool _showDetails = false;
  int _playerCount = 4;
  bool _assetsReady = false;

  /// Optional override of the board's logical width. When null the board
  /// fills the available room. Buttons in the command center set this to
  /// device preset sizes for testing different aspect ratios.
  double? _boardWidthOverride;

  /// Manual-mode selection: which color to play next and which dice value
  /// to force. Independent of the controller's natural turn rotation.
  PlayerColor _manualPlayer = PlayerColor.blue;
  int _manualValue = 1;

  /// Last hover info text (token or dice), shown next to the Détails toggle.
  String? _hoverInfo;

  /// Dice value displayed in each player's corner slot. Initialised to a
  /// random 1..6 so each corner shows a different face at game start. Sticks
  /// to the last rolled value so non-active players still see a face.
  late final Map<PlayerColor, int> _diceValues = {
    for (final c in PlayerColor.values) c: math.Random().nextInt(6) + 1,
  };

  /// One idle-animation index (1..5) per pawn, drawn once at startup.
  late final Map<Pawn, int> _pawnAnimIdx;

  /// Returns the GIF asset path for [pawn]'s currently assigned idle anim.
  String _pawnAsset(Pawn pawn) =>
      'AnimStock/Tokens/GIF/'
      'Pawn_standard_${pawn.color.name}_idle_${_pawnAnimIdx[pawn]}.gif';

  /// Active player colors derived from [_playerCount].
  ///   1 → blue alone
  ///   2 → blue + green (diagonal — opposite bases on the 4-player board)
  ///   3 → blue + red + green
  ///   4+ → all four
  List<PlayerColor> get _activeColors {
    switch (_playerCount.clamp(1, 4)) {
      case 1:  return const [PlayerColor.blue];
      case 2:  return const [PlayerColor.blue, PlayerColor.green];
      case 3:  return const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
      ];
      default: return const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ];
    }
  }

  /// Filter [BoardScreen.players] to the currently-active colors.
  List<Player> get _activePlayers => BoardScreen.players
      .where((p) => _activeColors.contains(p.color))
      .toList();

  void _onChangePlayerCount(int n) {
    setState(() {
      _playerCount = n;
      final order = _activeColors;
      _controller.turnOrder = order;
      if (_controller.currentPlayerIdx >= order.length) {
        _controller.currentPlayerIdx = 0;
      }
      // If the manually-selected color is no longer active, fall back to the
      // first active one.
      if (!order.contains(_manualPlayer)) {
        _manualPlayer = order.first;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Pick a random idle animation per pawn (#1..#5), then preload all 20
  /// token GIFs so the board renders smoothly the first time pawns appear.
  Future<void> _bootstrap() async {
    final rng = math.Random();
    _pawnAnimIdx = {
      for (final p in _game.allPawns) p: rng.nextInt(5) + 1,
    };

    final assets = <String>[
      for (final c in PlayerColor.values)
        for (int i = 1; i <= 5; i++)
          'AnimStock/Tokens/GIF/'
              'Pawn_standard_${c.name}_idle_$i.gif',
    ];
    await Future.wait(assets.map(_GifFrames.load));
    if (!mounted) return;
    setState(() => _assetsReady = true);
  }

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

  /// Manual-mode action: set the controller's current player to
  /// [_manualPlayer] and force its dice to [_manualValue].
  void _applyManual() {
    if (_controller.phase == TurnPhase.gameOver) return;
    final idx = _controller.turnOrder.indexOf(_manualPlayer);
    if (idx < 0) return;
    setState(() {
      _controller.currentPlayerIdx = idx;
      _controller.phase = TurnPhase.rolling;
      _controller.consecutiveSixes = 0;
      _controller.diceValue = 0;
      _controller.roll(_manualValue);
      _diceValues[_manualPlayer] = _manualValue;
    });
  }

  void _confirmRestart(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redémarrer le jeu ?'),
        content: const Text('Tous les pions retourneront dans leur base.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Redémarrer'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          _controller.reset();
          _diceValues.updateAll((_, __) => math.Random().nextInt(6) + 1);
        });
      }
    });
  }

  /// Hover callbacks — only active when [_showDetails] is on.
  void _onPawnHover(Pawn? p) {
    if (!_showDetails) return;
    if (p == null) {
      setState(() => _hoverInfo = null);
      return;
    }
    final animIdx = _pawnAnimIdx[p];
    String pos;
    switch (p.location) {
      case PawnLocation.base:        pos = 'base #${p.position}';        break;
      case PawnLocation.ring:        pos = 'ring #${p.position}';        break;
      case PawnLocation.homeColumn:  pos = 'home column #${p.position}'; break;
      case PawnLocation.home:        pos = 'home';                       break;
    }
    setState(() {
      _hoverInfo =
          'Pion ${p.color.name} #${p.id} · idle anim #$animIdx · $pos';
    });
  }

  void _onDiceHover(bool hovering) {
    if (!_showDetails) return;
    if (!hovering) {
      setState(() => _hoverInfo = null);
      return;
    }
    final color = _controller.currentColor;
    final v = _diceValues[color] ?? 1;
    setState(() {
      _hoverInfo = 'Dé ${color.name} · valeur $v';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A2541),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 16),
              Text(
                'Loading tokens…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1A2541),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 800.0;
            final w = c.maxWidth.isFinite ? c.maxWidth : 1200.0;
            // Command center capped at 30 % of the page width (with a sane
            // floor for tiny windows). The board is centered in the rest.
            final panelWidth = (w * 0.30).clamp(280.0, w * 0.5);
            final boardArea = (w - panelWidth).clamp(120.0, w);
            final maxBoard = h.clamp(0.0, boardArea);
            final boardSide =
                _boardWidthOverride?.clamp(120.0, maxBoard) ?? maxBoard;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: boardArea,
                  height: h,
                  child: Center(
                    child: SizedBox(
                      width: boardSide,
                      height: boardSide,
                      child: BoardView(
                    players: _activePlayers,
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
                    pawnAsset: _pawnAsset,
                    onPawnHover: _onPawnHover,
                    onDiceHover: _onDiceHover,
                    showDetails: _showDetails,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: panelWidth,
                  height: h,
                  child: _ControlPanel(
                    showRing: _showRing,
                    onToggleRing: (v) => setState(() => _showRing = v),
                    showGrid: _showGrid,
                    onToggleGrid: (v) => setState(() => _showGrid = v),
                    showDetails: _showDetails,
                    onToggleDetails: (v) {
                      setState(() {
                        _showDetails = v;
                        if (!v) _hoverInfo = null;
                      });
                    },
                    hoverInfo: _hoverInfo,
                    boardWidthOverride: _boardWidthOverride,
                    onDeviceSize: (w) =>
                        setState(() => _boardWidthOverride = w),
                    manualPlayer: _manualPlayer,
                    onChangeManualPlayer: (c) {
                      setState(() {
                        _manualPlayer = c;
                        // Immediately switch the controller's current player
                        // so the central dice picks up the new color.
                        final idx = _controller.turnOrder.indexOf(c);
                        if (idx >= 0) {
                          _controller.currentPlayerIdx = idx;
                          if (_controller.phase != TurnPhase.gameOver) {
                            _controller.phase = TurnPhase.rolling;
                            _controller.diceValue = 0;
                            _controller.consecutiveSixes = 0;
                          }
                        }
                      });
                    },
                    manualValue: _manualValue,
                    onChangeManualValue: (v) {
                      setState(() {
                        _manualValue = v;
                        // Removing the "Continue" button means the click on a
                        // value IS the action: force-roll for the current
                        // (manual-selected) player.
                        if (_controller.phase != TurnPhase.gameOver) {
                          _controller.phase = TurnPhase.rolling;
                          _controller.consecutiveSixes = 0;
                          _controller.roll(v);
                          _diceValues[_controller.currentColor] = v;
                        }
                      });
                    },
                    playerCount: _playerCount,
                    onChangePlayerCount: _onChangePlayerCount,
                    activePlayers: _activePlayers,
                    currentPlayer: _activePlayers[
                        _controller.currentPlayerIdx
                            .clamp(0, _activePlayers.length - 1)],
                    phase: _controller.phase,
                    diceValue: _controller.diceValue,
                    consecutiveSixes: _controller.consecutiveSixes,
                    winner: _controller.winner,
                    onRollDice: _rollDice,
                    onEndTurn: _endTurn,
                    onRestart: () => _confirmRestart(context),
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

/// Right-side panel: command center. Two cards (Normal / Manual) on top of an
/// overlay-toggles card. The number of players (1-6) and board-width preset
/// (smartphone / foldable / tablet / web FHD) live on the header row.
class _ControlPanel extends StatelessWidget {
  // Overlays
  final bool showRing;
  final ValueChanged<bool> onToggleRing;
  final bool showGrid;
  final ValueChanged<bool> onToggleGrid;
  final bool showDetails;
  final ValueChanged<bool> onToggleDetails;
  final String? hoverInfo;

  // Layout
  final int playerCount;
  final ValueChanged<int> onChangePlayerCount;
  final List<Player> activePlayers;
  final double? boardWidthOverride;
  final ValueChanged<double?> onDeviceSize;

  // Turn state (normal mode)
  final Player currentPlayer;
  final TurnPhase phase;
  final int diceValue;
  final int consecutiveSixes;
  final PlayerColor? winner;
  final VoidCallback onRollDice;
  final VoidCallback onEndTurn;

  // Restart
  final VoidCallback onRestart;

  // Manual mode
  final PlayerColor manualPlayer;
  final ValueChanged<PlayerColor> onChangeManualPlayer;
  final int manualValue;
  final ValueChanged<int> onChangeManualValue;

  const _ControlPanel({
    required this.showRing,
    required this.onToggleRing,
    required this.showGrid,
    required this.onToggleGrid,
    required this.showDetails,
    required this.onToggleDetails,
    required this.hoverInfo,
    required this.playerCount,
    required this.onChangePlayerCount,
    required this.activePlayers,
    required this.boardWidthOverride,
    required this.onDeviceSize,
    required this.currentPlayer,
    required this.phase,
    required this.diceValue,
    required this.consecutiveSixes,
    required this.winner,
    required this.onRollDice,
    required this.onEndTurn,
    required this.onRestart,
    required this.manualPlayer,
    required this.onChangeManualPlayer,
    required this.manualValue,
    required this.onChangeManualValue,
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
        return 'En attente du lancer';
      case TurnPhase.moving:
        return 'Dé $diceValue — choisis un pion';
      case TurnPhase.gameOver:
        return 'Partie terminée';
    }
  }

  /// Device-size presets for the board width override.
  static const Map<String, ({IconData icon, double? width})> _devicePresets = {
    'Smartphone':   (icon: Icons.smartphone,    width: 360),
    'Foldable':     (icon: Icons.devices_fold,  width: 720),
    'Tablette':     (icon: Icons.tablet_mac,    width: 1024),
    'Web FHD':      (icon: Icons.desktop_windows, width: 1920),
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Material(
          color: cs.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Title ----
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    'Centre de commandes',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // ---- Row: Nb joueurs (left) + device presets (right) ----
                _SectionCard(
                  title: 'Setup',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Nb joueurs',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 3, label: Text('3')),
                          ButtonSegment(value: 4, label: Text('4')),
                          ButtonSegment(value: 5, label: Text('5')),
                          ButtonSegment(value: 6, label: Text('6')),
                        ],
                        selected: {playerCount},
                        onSelectionChanged: (s) =>
                            onChangePlayerCount(s.first),
                        showSelectedIcon: false,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Taille board',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: onRestart,
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('Redémarrer jeu'),
                            style: TextButton.styleFrom(
                              foregroundColor: cs.error,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in _devicePresets.entries)
                            Tooltip(
                              message:
                                  '${entry.key} (${entry.value.width!.toInt()}px)',
                              child: IconButton.filledTonal(
                                isSelected: boardWidthOverride ==
                                    entry.value.width,
                                onPressed: () =>
                                    onDeviceSize(entry.value.width),
                                icon: Icon(entry.value.icon),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ---- Two side-by-side cards: Jeu normal / Jeu manuel ----
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _normalCard(theme, cs)),
                      const SizedBox(width: 8),
                      Expanded(child: _manualCard(theme, cs)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ---- Overlays card ----
                _SectionCard(
                  title: 'Overlays',
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Show ring'),
                        subtitle:
                            const Text('Indices des cases du ring'),
                        value: showRing,
                        onChanged: onToggleRing,
                      ),
                      SwitchListTile(
                        title: const Text('Show grid 15×15'),
                        subtitle:
                            const Text('Indices 0..224 sur chaque case'),
                        value: showGrid,
                        onChanged: onToggleGrid,
                      ),
                      SwitchListTile(
                        title: const Text('Détails'),
                        subtitle: Text(
                          hoverInfo ?? 'Survole un pion ou le dé',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: showDetails,
                        onChanged: onToggleDetails,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _normalCard(ThemeData theme, ColorScheme cs) {
    return _SectionCard(
      title: 'Jeu normal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Tour :', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 6),
              Flexible(
                child: Chip(
                  label: Text(currentPlayer.name,
                      overflow: TextOverflow.ellipsis),
                  backgroundColor: _playerColor(currentPlayer.color),
                  labelStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _phaseText(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (consecutiveSixes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Série de 6 : $consecutiveSixes',
                  style: TextStyle(color: cs.tertiary, fontSize: 12)),
            ),
          if (winner != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, size: 18, color: cs.tertiary),
                  const SizedBox(width: 4),
                  Text('${winner!.name} gagne',
                      style: TextStyle(
                          color: cs.tertiary,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.casino),
            label: const Text('Lancer le dé'),
            onPressed: phase == TurnPhase.rolling ? onRollDice : null,
          ),
        ],
      ),
    );
  }

  Widget _manualCard(ThemeData theme, ColorScheme cs) {
    return _SectionCard(
      title: 'Jeu manuel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Couleur',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in activePlayers)
                _ColorDot(
                  color: _playerColor(p.color),
                  selected: p.color == manualPlayer,
                  onTap: () => onChangeManualPlayer(p.color),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Valeur dé',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int v = 1; v <= 6; v++)
                _MiniDiceButton(
                  value: v,
                  selected: v == manualValue,
                  onTap: () => onChangeManualValue(v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small color dot for the manual-mode color selector.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 3)
              : null,
        ),
      ),
    );
  }
}

/// Reusable section card with a small title above the body. Uses the ambient
/// Material 3 theme for surface/elevation/typography.
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SectionCard({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(padding: padding, child: child),
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
  /// Resolver for a pawn's currently-assigned idle GIF asset path.
  final String Function(Pawn) pawnAsset;
  /// Hover callback for token details. Null pawn = mouse exited.
  final ValueChanged<Pawn?>? onPawnHover;
  /// Hover callback for the dice. Bool = entered (true) / exited (false).
  final ValueChanged<bool>? onDiceHover;
  /// When true, the cursor over pawns/dice becomes a help-pointer (`?`).
  final bool showDetails;
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
    required this.pawnAsset,
    this.onPawnHover,
    this.onDiceHover,
    this.showDetails = false,
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

  /// 3px gap between the colored base's top edge and the visible token top.
  static const double _pawnTopMarginPx = 3.0;

  // ---- Pawn-image visible bounds inside its bbox -------------------------
  // Measured on the production GIF (`PIL.getbbox()` on the 200×440 native):
  // visible content spans y 214..299 → 48.6 %..68.0 % of the bbox height.
  // Center at ≈ 58.3 %.
  static const double _pawnVisibleTopFrac    = 0.486;
  static const double _pawnVisibleCenterFrac = 0.583;

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

  // Center (in cell units) of each player's name label, placed in the
  // bottom row of its base. Targets: red 77/78, green 86/87, blue 212/213,
  // yellow 221/222 — center sits on the shared edge of those two cells.
  static const Map<PlayerColor, Offset> _labelCenter = {
    PlayerColor.red:    Offset(3.0,  5.5),
    PlayerColor.green:  Offset(12.0, 5.5),
    PlayerColor.blue:   Offset(3.0,  14.5),
    PlayerColor.yellow: Offset(12.0, 14.5),
  };

  /// Returns the pixel that the bbox-anchor (its `_pawnVisibleCenterFrac`
  /// line) must hit so the *visible* pawn top sits at [baseTopPx] +
  /// [_pawnTopMarginPx].
  ///
  ///   visible_top = bbox_top + visibleTopFrac × H
  ///   bbox_top    = anchor   − visibleCenterFrac × H
  /// ⇒ anchor = base_top + margin + (visibleCenterFrac − visibleTopFrac) × H
  Offset _baseSlotCenter(
      PlayerColor color, int slot, double cell, double pawnHeight) {
    final corner = _baseCorner[color]!;
    final cx = (corner.dx + _spotsX[slot]) * cell;
    final baseTopPx = corner.dy * cell;
    final cy = baseTopPx +
        _pawnTopMarginPx +
        pawnHeight * (_pawnVisibleCenterFrac - _pawnVisibleTopFrac);
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
    // Polygonal layout only for 5 and 6. Counts 1-4 all use the 4-player
    // board (inactive colors are filtered out of the pawn/label rendering
    // by the parent that builds the `players` list).
    if (playerCount >= 5) {
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
                child: const _DiceFace(value: 1, playerColor: null),
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
                      name: p.name,
                      color: _colorOf(p.color),
                      // Scale the label font with the cell size — 14 at a
                      // ~50 px cell (~750 px board), down to ~7 on a 360 px
                      // smartphone preset.
                      fontSize: (cell * 0.30).clamp(8.0, 16.0),
                    ),
                  ),
                );
              }(),

            // Single central dice in the current player's color. Clickable
            // during the rolling phase.
            () {
              final size = cell * 1.6;
              final clickable = canRollDice;
              return Positioned(
                left: 7.5 * cell - size / 2,
                top:  7.5 * cell - size / 2,
                width: size,
                height: size,
                child: MouseRegion(
                  cursor: showDetails
                      ? SystemMouseCursors.help
                      : (clickable
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic),
                  onEnter: (_) => onDiceHover?.call(true),
                  onExit: (_) => onDiceHover?.call(false),
                  child: GestureDetector(
                    onTap: clickable ? onRollDice : null,
                    child: _DiceFace(
                      value: diceValues[currentPlayerColor] ?? 1,
                      playerColor: currentPlayerColor,
                    ),
                  ),
                ),
              );
            }(),

            // Every pawn, rendered at its current model position. Pawns the
            // current player can move with the rolled dice are highlighted
            // and tappable.
            ...() sync* {
              final activeColors = players.map((p) => p.color).toSet();
              final list = game.allPawns
                  .where((p) => activeColors.contains(p.color))
                  .toList();
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
                // Halo selector behind the pawn when it is a legal move
                // target. Sized 2.4 × cell, centered on the visible pawn
                // anchor (so it hugs the helmet on base and the body on
                // ring/home).
                if (isMovable) {
                  final haloSize = cell * 2.4;
                  yield Positioned(
                    left: center.dx - haloSize / 2,
                    top:  center.dy - haloSize / 2,
                    width: haloSize,
                    height: haloSize,
                    child: IgnorePointer(
                      child: Image.asset(
                        'AnimStock/Selectors/GIF/Selector_A_Halo.gif',
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                }
                // `_pawnVisibleCenterFrac` is the vertical position of the
                // visible token center inside the bbox. Anchoring the bbox
                // so that line lands on `center.dy` makes the *visible*
                // pawn centered on the cell (ring / home).
                yield Positioned(
                  left: center.dx - pawnWidth / 2,
                  top:  center.dy - pawnHeight * _pawnVisibleCenterFrac,
                  width: pawnWidth,
                  height: pawnHeight,
                  child: MouseRegion(
                    cursor: showDetails
                        ? SystemMouseCursors.help
                        : (isMovable
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic),
                    onEnter: (_) => onPawnHover?.call(pawn),
                    onExit: (_) => onPawnHover?.call(null),
                    child: GestureDetector(
                      onTap: isMovable ? () => onPawnTap(pawn) : null,
                      child: _PawnAnimatedGif(
                        key: ValueKey('${pawn.color.name}_${pawn.id}'),
                        asset: pawnAsset(pawn),
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
  final bool selected;
  const _MiniDiceButton({
    required this.value,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                color: selected ? cs.onPrimary : cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dice at rest, rendered from a colored face PNG keyed by [playerColor] and
/// [value]. When [playerColor] is null we use the generic white dice (used by
/// the 5/6-player center slot).
class _DiceFace extends StatelessWidget {
  final int value;
  final PlayerColor? playerColor;
  const _DiceFace({required this.value, required this.playerColor});

  String get _assetPath {
    final colorName = playerColor?.name ?? 'white';
    final v = value.clamp(1, 6);
    return 'AnimStock/Dices/PNG/Dice_${v}_$colorName.png';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _PlayerLabel extends StatelessWidget {
  final String name;
  final Color color;
  final double fontSize;
  const _PlayerLabel({
    required this.name,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    // Padding scales with fontSize so the pill stays proportional on small
    // boards (Smartphone preset). FittedBox prevents long names from
    // overflowing — they shrink instead of clipping.
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.55,
        vertical: fontSize * 0.25,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(fontSize * 0.45),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2)),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}
