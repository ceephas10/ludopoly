// Game engine for 4-player Ludo King rules.
//
// Owns the dice value, turn order, and the win condition check. Rule details
// (exit on 6, lap = 51 ring cells then 5-cell home column then center, exact
// roll to home, capture, safe cells, bonus turn on 6 / capture / home arrival,
// 3-six streak cancels the turn) live here.

import 'dart:math' as math;

import 'game_state.dart';
import 'pawn.dart';
import 'player_color.dart';

enum TurnPhase {
  /// The current player needs to roll the dice (or have it set).
  rolling,
  /// Dice has a value; the current player must pick a movable pawn.
  moving,
  /// A player has brought all four pawns home.
  gameOver,
}

class GameController {
  /// Turn order, fixed at construction time. Index `currentPlayerIdx` cycles
  /// through this list.
  final List<PlayerColor> turnOrder;
  final GameState state;

  int currentPlayerIdx = 0;
  int diceValue = 0;
  int consecutiveSixes = 0;
  Pawn? lastMovedThisTurn;
  TurnPhase phase = TurnPhase.rolling;
  PlayerColor? winner;

  final math.Random _rng;

  GameController({
    required this.turnOrder,
    required this.state,
    math.Random? rng,
  }) : _rng = rng ?? math.Random();

  // --- ring/home geometry constants -----------------------------------------

  /// Number of cells on the shared ring.
  static const int ringSize = 52;

  /// 51 ring steps + 5 home-column cells + 1 final home step.
  static const int totalStepsToHome = 57;

  /// Index of each color's starting ring cell.
  static const Map<PlayerColor, int> _startIdx = {
    PlayerColor.blue:   0,
    PlayerColor.red:    13,
    PlayerColor.green:  26,
    PlayerColor.yellow: 39,
  };

  /// Cells where capture is forbidden (4 starts + 4 stars).
  static const Set<int> _safeCells = {0, 13, 26, 39, 8, 21, 34, 47};

  // --- public API -----------------------------------------------------------

  PlayerColor get currentColor => turnOrder[currentPlayerIdx];

  /// Roll a random 1..6.
  void rollRandom() => roll(_rng.nextInt(6) + 1);

  /// Set the dice value (random or forced) and update [phase]. If no pawn can
  /// move (or the streak-of-3 sixes triggers), advances to the next player.
  void roll(int value) {
    if (phase != TurnPhase.rolling || winner != null) return;
    diceValue = value;

    if (value == 6) {
      consecutiveSixes++;
      if (consecutiveSixes >= 3) {
        // 3 sixes in a row: cancel the turn and send the pawn most recently
        // moved during this streak back to base.
        if (lastMovedThisTurn != null &&
            lastMovedThisTurn!.color == currentColor) {
          _returnPawnToBase(lastMovedThisTurn!);
        }
        _nextPlayer();
        return;
      }
    } else {
      consecutiveSixes = 0;
    }

    if (movablePawns().isEmpty) {
      _nextPlayer();
      return;
    }

    phase = TurnPhase.moving;
  }

  /// All pawns of the current player that can legally move with [diceValue].
  List<Pawn> movablePawns() {
    if (winner != null) return [];
    final pawns = state.pawnsByColor[currentColor]!;
    return pawns.where((p) => _canMove(p, diceValue)).toList();
  }

  bool _canMove(Pawn p, int v) {
    if (p.color != currentColor || v <= 0) return false;
    switch (p.location) {
      case PawnLocation.base:
        return v == 6;
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        return taken + v <= totalStepsToHome;
      case PawnLocation.homeColumn:
        // Home column has 5 cells (indices 0..4); the 6th step reaches home.
        return p.position + v <= 5;
      case PawnLocation.home:
        return false;
    }
  }

  /// Move [p] by [diceValue]. No-op if illegal. Resolves capture, home
  /// arrival, win, and bonus turns.
  void movePawn(Pawn p) {
    if (phase != TurnPhase.moving) return;
    if (!_canMove(p, diceValue)) return;

    bool captured = false;
    bool homeArrival = false;

    switch (p.location) {
      case PawnLocation.base:
        // Exit on 6 → start cell.
        p.location = PawnLocation.ring;
        p.position = _startIdx[p.color]!;
        break;
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        final newSteps = taken + diceValue;
        if (newSteps <= 51) {
          p.position = (_startIdx[p.color]! + newSteps) % ringSize;
        } else if (newSteps == totalStepsToHome) {
          p.location = PawnLocation.home;
          homeArrival = true;
        } else {
          // newSteps in 52..56 → home column step 0..4.
          p.location = PawnLocation.homeColumn;
          p.position = newSteps - 52;
        }
        break;
      case PawnLocation.homeColumn:
        final newPos = p.position + diceValue;
        if (newPos == 5) {
          p.location = PawnLocation.home;
          homeArrival = true;
        } else {
          p.position = newPos;
        }
        break;
      case PawnLocation.home:
        return; // never happens (filtered by _canMove)
    }

    // Capture: opponent pawn(s) on the same non-safe ring cell go back to
    // base. (Blocks of 2+ same-color opponents are NOT handled yet — they
    // simply get all captured for now; see Phase 3 for block rules.)
    if (p.location == PawnLocation.ring && !_safeCells.contains(p.position)) {
      for (final color in state.pawnsByColor.keys) {
        if (color == p.color) continue;
        for (final other in state.pawnsByColor[color]!) {
          if (other.location == PawnLocation.ring &&
              other.position == p.position) {
            _returnPawnToBase(other);
            captured = true;
          }
        }
      }
    }

    lastMovedThisTurn = p;

    if (_allPawnsHome(currentColor)) {
      winner = currentColor;
      phase = TurnPhase.gameOver;
      return;
    }

    // Bonus turn on 6, on capture, or on home arrival.
    if (diceValue == 6 || captured || homeArrival) {
      diceValue = 0;
      phase = TurnPhase.rolling;
    } else {
      _nextPlayer();
    }
  }

  /// Force the next player (debug). Resets streak + dice.
  void skipTurn() => _nextPlayer();

  // --- internal helpers -----------------------------------------------------

  int _stepsTaken(Pawn p) =>
      (p.position - _startIdx[p.color]! + ringSize) % ringSize;

  void _returnPawnToBase(Pawn p) {
    p.location = PawnLocation.base;
    p.position = p.id;
  }

  bool _allPawnsHome(PlayerColor color) {
    return state.pawnsByColor[color]!
        .every((p) => p.location == PawnLocation.home);
  }

  void _nextPlayer() {
    diceValue = 0;
    consecutiveSixes = 0;
    lastMovedThisTurn = null;
    phase = TurnPhase.rolling;
    currentPlayerIdx = (currentPlayerIdx + 1) % turnOrder.length;
  }
}
