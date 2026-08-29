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

/// Une case traversée par un pion pendant son déplacement.
///
/// Sert UNIQUEMENT à l'affichage : l'interface fait glisser le pion d'une
/// [PawnStep] à la suivante pour qu'on voie chaque case. Le moteur, lui,
/// applique le coup d'un bloc — l'animation ne décide jamais d'une règle.
class PawnStep {
  final PawnLocation location;
  final int position;
  const PawnStep(this.location, this.position);

  @override
  String toString() => '${location.name}:$position';
}

/// Position figée d'un pion dans un [GameSnapshot].
class PawnSnapshot {
  final PawnLocation location;
  final int position;
  const PawnSnapshot(this.location, this.position);
}

/// Instantané complet d'une partie : la position des 16 pions PLUS tout
/// l'état de tour (joueur courant, dé, série de 6, phase, classement).
///
/// Sert au bouton « Retour » : on empile un instantané AVANT chaque action,
/// et [GameController.stepBack] le réapplique tel quel. Un instantané ne
/// contient que des valeurs, jamais de références aux pions vivants — le
/// restaurer ne peut donc pas ré-introduire un état partiellement modifié.
class GameSnapshot {
  final Map<PlayerColor, List<PawnSnapshot>> pawns;
  final int currentPlayerIdx;
  final int diceValue;
  final int lastRoll;
  final int consecutiveSixes;
  final TurnPhase phase;
  final PlayerColor? winner;
  final List<PlayerColor> ranking;

  /// Libellé lisible de l'action qui a suivi cet instantané, p. ex.
  /// « red · dé 4 ». Affiché dans l'infobulle du bouton Retour.
  final String label;

  const GameSnapshot({
    required this.pawns,
    required this.currentPlayerIdx,
    required this.diceValue,
    required this.lastRoll,
    required this.consecutiveSixes,
    required this.phase,
    required this.winner,
    required this.ranking,
    required this.label,
  });
}

class GameController {
  /// Turn order. Mutable so the host can swap players in/out at runtime
  /// (e.g. when the user picks 1/2/3 players in the command center).
  List<PlayerColor> turnOrder;
  final GameState state;

  int currentPlayerIdx = 0;
  int diceValue = 0;

  /// Dernière valeur SORTIE du dé, tous joueurs confondus. Contrairement à
  /// [diceValue] — qui retombe à 0 dès que le tour passe — celle-ci persiste :
  /// c'est ce que le plateau affiche pendant que le joueur suivant réfléchit.
  /// 0 = aucun lancer depuis le début de la partie.
  int lastRoll = 0;
  int consecutiveSixes = 0;
  Pawn? lastMovedThisTurn;
  TurnPhase phase = TurnPhase.rolling;
  PlayerColor? winner;

  /// Ordre d'arrivée : `ranking[0]` = 1er, `ranking[1]` = 2e, etc. Une
  /// couleur y entre dès que ses 4 pions sont au centre. La partie NE
  /// s'arrête PAS au premier arrivé : les autres continuent à jouer pour
  /// les places suivantes, jusqu'à ce qu'il ne reste qu'un joueur.
  final List<PlayerColor> ranking = [];

  /// Règle des blocs (barrière). Quand elle est ON, 2 pions ou plus de la
  /// même couleur sur une case du ring forment un BLOC : un pion adverse
  /// ne peut ni s'y poser, ni le traverser. Configurable parce que les
  /// variantes de Ludo ne traitent pas l'empilement de la même manière.
  bool blockRule = false;

  /// 2v2 team mode toggle. When ON :
  ///   - blue + green form one team, yellow + red form the other ([_partners])
  ///   - capture is suppressed BETWEEN partners (a pion landing on a same-
  ///     team pion's cell does NOT send it back)
  ///   - a player whose 4 pawns are all home keeps playing on their turn,
  ///     but moves their partner's remaining pawns instead
  ///   - victory = a team has its 8 pawns home (4 + 4)
  bool teamMode = false;

  /// Static team mapping. Each color points to its teammate.
  static const Map<PlayerColor, PlayerColor> _partners = {
    PlayerColor.blue:   PlayerColor.green,
    PlayerColor.green:  PlayerColor.blue,
    PlayerColor.yellow: PlayerColor.red,
    PlayerColor.red:    PlayerColor.yellow,
  };

  /// Public lookup for teammate (used by UI to label the current
  /// "playing-for-partner" state). Returns `null` outside team mode or
  /// for a color with no defined partner.
  PlayerColor? partnerOf(PlayerColor c) =>
      teamMode ? _partners[c] : null;

  /// True when [a] and [b] are on the same team (themselves included).
  /// In non-team mode this collapses to identity.
  bool _sameTeam(PlayerColor a, PlayerColor b) =>
      a == b || (teamMode && _partners[a] == b);

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

  /// Public lookup for [_startIdx] — used by rules like
  /// "start with 1 token out" that need to place a pawn directly on
  /// its color's ring start cell.
  static int startIdx(PlayerColor color) => _startIdx[color]!;

  /// Cells where capture is forbidden (4 starts + 4 stars).
  static const Set<int> _safeCells = {0, 13, 26, 39, 8, 21, 34, 47};

  // --- public API -----------------------------------------------------------

  PlayerColor get currentColor => turnOrder[currentPlayerIdx];

  /// Roll a random 1..6.
  void rollRandom() => roll(_rng.nextInt(6) + 1);

  /// Set the dice value (random or forced) and update [phase]. If no pawn can
  /// move (or the streak-of-3 sixes triggers), advances to the next player.
  void roll(int value) {
    if (phase != TurnPhase.rolling) return;
    diceValue = value;
    lastRoll = value;

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

  /// All pawns the current player can legally move with [diceValue]. In
  /// team mode, when the current player's 4 pawns are all home, this
  /// switches to their partner's still-in-play pawns (the "help partner"
  /// rule).
  List<Pawn> movablePawns() {
    if (phase == TurnPhase.gameOver) return [];
    final own = state.pawnsByColor[currentColor]!;
    final result = own.where((p) => _canMoveAs(p, diceValue, currentColor))
        .toList();
    if (result.isNotEmpty) return result;
    if (teamMode && _allPawnsHome(currentColor)) {
      final partner = _partners[currentColor];
      if (partner != null) {
        final partnerPawns = state.pawnsByColor[partner]!;
        return partnerPawns
            .where((p) => _canMoveAs(p, diceValue, currentColor))
            .toList();
      }
    }
    return const [];
  }

  bool _canMove(Pawn p, int v) => _canMoveAs(p, v, currentColor);

  /// Legality check for moving [p] on behalf of [playingFor]. In team mode
  /// a partner can be playing the pawn (so [p.color] is the teammate's,
  /// not [playingFor]) — but ONLY if [playingFor]'s own 4 pawns are all
  /// home (the "help partner" rule kicks in only after you've finished).
  bool _canMoveAs(Pawn p, int v, PlayerColor playingFor) {
    if (v <= 0) return false;
    if (!_sameTeam(p.color, playingFor)) return false;
    // Helping the partner: only allowed once [playingFor]'s own pions
    // are all at home.
    if (p.color != playingFor && !_allPawnsHome(playingFor)) return false;
    switch (p.location) {
      case PawnLocation.base:
        if (v != 6) return false;
        // Sortie de base : la case départ doit être libre de tout bloc adverse.
        return !_barriersFor(playingFor).contains(_startIdx[p.color]!);
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        if (taken + v > totalStepsToHome) return false;
        return _pathIsClear(p, taken, v, playingFor);
      case PawnLocation.homeColumn:
        // Home column has 5 cells (indices 0..4); the 6th step reaches home.
        return p.position + v <= 5;
      case PawnLocation.home:
        return false;
    }
  }

  /// Les cases successivement traversées par [p] avec un dé de [v], case
  /// d'ARRIVÉE comprise et case de départ exclue. Une sortie de base ne
  /// compte qu'une étape (le pion est téléporté sur sa case départ, il ne
  /// parcourt pas 6 cases). Liste vide si le coup est illégal.
  ///
  /// Purement géométrique : ne modifie rien, sert à animer le trajet.
  List<PawnStep> pathFor(Pawn p, int v) {
    if (!_canMoveAs(p, v, currentColor)) return const [];
    switch (p.location) {
      case PawnLocation.base:
        return [PawnStep(PawnLocation.ring, _startIdx[p.color]!)];
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        final start = _startIdx[p.color]!;
        return [
          for (int s = taken + 1; s <= taken + v; s++)
            if (s <= 51)
              PawnStep(PawnLocation.ring, (start + s) % ringSize)
            else if (s == totalStepsToHome)
              const PawnStep(PawnLocation.home, 0)
            else
              PawnStep(PawnLocation.homeColumn, s - 52),
        ];
      case PawnLocation.homeColumn:
        return [
          for (int s = p.position + 1; s <= p.position + v; s++)
            if (s == 5)
              const PawnStep(PawnLocation.home, 0)
            else
              PawnStep(PawnLocation.homeColumn, s),
        ];
      case PawnLocation.home:
        return const [];
    }
  }

  /// Chemin de RETOUR d'un pion capturé, case par case et case de capture
  /// EXCLUE : depuis [from], la case de l'anneau où il vient de se faire
  /// manger, il remonte l'anneau À CONTRE-SENS jusqu'à sa flèche d'entrée
  /// (la case de départ de sa couleur), puis rentre dans sa base sur le
  /// créneau [baseSlot]. La dernière étape est donc toujours la base.
  ///
  /// Un pion capturé est forcément sur l'anneau, et jamais sur une case
  /// sûre — les 4 cases de départ en font partie — donc le chemin compte
  /// au moins une case d'anneau. Tout autre cas retombe sur le saut direct.
  ///
  /// Purement géométrique : ne modifie rien, sert à animer le retour.
  List<PawnStep> returnPathFor(PlayerColor color, PawnStep from, int baseSlot) {
    if (from.location != PawnLocation.ring) {
      return [PawnStep(PawnLocation.base, baseSlot)];
    }
    final start = _startIdx[color]!;
    final taken = (from.position - start + ringSize) % ringSize;
    return [
      for (int s = taken - 1; s >= 0; s--)
        PawnStep(PawnLocation.ring, (start + s) % ringSize),
      PawnStep(PawnLocation.base, baseSlot),
    ];
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

    // Capture: opposing-team pawn(s) on the same non-safe ring cell go
    // back to base. In team mode, partner pawns on the cell are NEVER
    // captured.
    if (p.location == PawnLocation.ring && !_safeCells.contains(p.position)) {
      for (final color in state.pawnsByColor.keys) {
        if (_sameTeam(color, p.color)) continue;
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

    // Classement : dès qu'une couleur a ses 4 pions au centre elle prend le
    // rang suivant. Le 1er arrivé est le gagnant, mais la partie CONTINUE
    // pour les places 2e / 3e / 4e.
    final colorToCheck = p.color;
    if (_allPawnsHome(colorToCheck) && !ranking.contains(colorToCheck)) {
      ranking.add(colorToCheck);
      winner ??= colorToCheck;
    }

    // Fin de partie. En mode équipe : une équipe a ses 8 pions au centre.
    // En mode classique : il ne reste plus qu'un joueur non classé, il
    // prend automatiquement la dernière place.
    if (teamMode) {
      final partner = _partners[colorToCheck];
      if (partner != null &&
          _allPawnsHome(colorToCheck) &&
          _allPawnsHome(partner)) {
        winner = colorToCheck;
        phase = TurnPhase.gameOver;
        return;
      }
    } else if (ranking.isNotEmpty &&
        ranking.length >= turnOrder.length - 1) {
      for (final c in turnOrder) {
        if (!ranking.contains(c)) ranking.add(c);
      }
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

  /// Reset all pawns to base, clear dice/turn state, restart from first player.
  void reset() {
    for (final pawns in state.pawnsByColor.values) {
      for (final p in pawns) {
        p.location = PawnLocation.base;
        p.position = p.id;
      }
    }
    currentPlayerIdx = 0;
    diceValue = 0;
    lastRoll = 0;
    consecutiveSixes = 0;
    lastMovedThisTurn = null;
    phase = TurnPhase.rolling;
    winner = null;
    ranking.clear();
    clearHistory();
  }

  // --- IA locale (mode "contre ordinateur") ---------------------------------

  /// Choisit le meilleur pion à jouer pour le joueur courant, par ordre de
  /// priorité décroissante :
  ///   1. un coup qui CAPTURE un pion adverse ;
  ///   2. un coup qui rentre un pion à la MAISON ;
  ///   3. un coup qui entre dans le COULOIR final ;
  ///   4. une SORTIE de base (occuper le plateau) ;
  ///   5. un coup qui termine sur une case SÛRE ;
  ///   6. à défaut, le pion le plus AVANCÉ.
  /// Retourne `null` si aucun coup n'est jouable.
  Pawn? pickAiPawn() {
    final options = movablePawns();
    if (options.isEmpty) return null;
    Pawn? best;
    int bestScore = -1 << 30;
    for (final p in options) {
      final s = _aiScore(p);
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return best;
  }

  int _aiScore(Pawn p) {
    final taken = p.location == PawnLocation.ring ? _stepsTaken(p) : 0;
    int score = 0;
    switch (p.location) {
      case PawnLocation.base:
        score = 400; // sortir occupe le plateau
        break;
      case PawnLocation.ring:
        final newSteps = taken + diceValue;
        if (newSteps == totalStepsToHome) {
          score = 1000; // arrivée exacte à la maison
        } else if (newSteps > 51) {
          score = 600; // entrée dans le couloir final
        } else {
          final target = (_startIdx[p.color]! + newSteps) % ringSize;
          if (_wouldCaptureAt(target, p.color)) {
            score = 900; // capture = tour supplémentaire
          } else if (_safeCells.contains(target)) {
            score = 500;
          } else {
            score = 100 + newSteps; // sinon, faire avancer le plus avancé
          }
        }
        break;
      case PawnLocation.homeColumn:
        score = (p.position + diceValue == 5) ? 1000 : 600 + p.position;
        break;
      case PawnLocation.home:
        score = -1 << 29;
        break;
    }
    return score;
  }

  /// True si un pion adverse capturable se trouve sur la case [cell].
  bool _wouldCaptureAt(int cell, PlayerColor mover) {
    if (_safeCells.contains(cell)) return false;
    for (final entry in state.pawnsByColor.entries) {
      if (_sameTeam(entry.key, mover)) continue;
      for (final other in entry.value) {
        if (other.location == PawnLocation.ring && other.position == cell) {
          return true;
        }
      }
    }
    return false;
  }

  // --- internal helpers -----------------------------------------------------

  int _stepsTaken(Pawn p) =>
      (p.position - _startIdx[p.color]! + ringSize) % ringSize;

  /// Cases du ring qui font BARRIÈRE pour [mover] : une case portant 2 pions
  /// ou plus d'une même couleur qui n'est pas dans l'équipe de [mover].
  /// Vide quand [blockRule] est OFF (comportement historique : on traverse
  /// et on s'empile librement).
  Set<int> _barriersFor(PlayerColor mover) {
    if (!blockRule) return const {};
    final byCellAndColor = <int, Map<PlayerColor, int>>{};
    for (final entry in state.pawnsByColor.entries) {
      if (_sameTeam(entry.key, mover)) continue;
      for (final p in entry.value) {
        if (p.location != PawnLocation.ring) continue;
        final byColor = byCellAndColor.putIfAbsent(p.position, () => {});
        byColor[entry.key] = (byColor[entry.key] ?? 0) + 1;
      }
    }
    final result = <int>{};
    byCellAndColor.forEach((cell, byColor) {
      if (byColor.values.any((n) => n >= 2)) result.add(cell);
    });
    return result;
  }

  /// True si aucune barrière adverse ne se trouve sur les [v] cases que [p]
  /// s'apprête à parcourir (cases intermédiaires ET case d'arrivée). Le
  /// couloir final est privé : on ne teste que la portion sur le ring.
  bool _pathIsClear(Pawn p, int taken, int v, PlayerColor playingFor) {
    final barriers = _barriersFor(playingFor);
    if (barriers.isEmpty) return true;
    final start = _startIdx[p.color]!;
    for (int s = taken + 1; s <= taken + v && s <= 51; s++) {
      if (barriers.contains((start + s) % ringSize)) return false;
    }
    return true;
  }

  // --- Historique / bouton Retour -------------------------------------------

  /// Pile d'annulation : un instantané de l'état AVANT chaque action, le
  /// plus récent en dernier. Bornée à [_maxHistory].
  final List<GameSnapshot> _history = [];

  /// Pile de rétablissement : les états APRÈS les actions annulées. Vidée dès
  /// qu'une nouvelle action est jouée — on ne peut pas rétablir une branche
  /// qu'on vient d'abandonner.
  final List<GameSnapshot> _redo = [];

  static const int _maxHistory = 100;

  /// Nombre de coups annulables / rétablissables.
  int get undoDepth => _history.length;
  int get redoDepth => _redo.length;

  /// Libellé du prochain coup annulable / rétablissable, ou `null`.
  String? get lastUndoLabel =>
      _history.isEmpty ? null : _history.last.label;
  String? get nextRedoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Photographie l'état courant sous [label].
  GameSnapshot _capture(String label) => GameSnapshot(
        pawns: {
          for (final entry in state.pawnsByColor.entries)
            entry.key: [
              for (final p in entry.value)
                PawnSnapshot(p.location, p.position),
            ],
        },
        currentPlayerIdx: currentPlayerIdx,
        diceValue: diceValue,
        lastRoll: lastRoll,
        consecutiveSixes: consecutiveSixes,
        phase: phase,
        winner: winner,
        ranking: List<PlayerColor>.from(ranking),
        label: label,
      );

  /// Réapplique [snap] tel quel.
  void _restore(GameSnapshot snap) {
    for (final entry in state.pawnsByColor.entries) {
      final saved = snap.pawns[entry.key];
      if (saved == null) continue;
      for (int i = 0; i < entry.value.length && i < saved.length; i++) {
        entry.value[i].location = saved[i].location;
        entry.value[i].position = saved[i].position;
      }
    }
    currentPlayerIdx = snap.currentPlayerIdx;
    diceValue = snap.diceValue;
    lastRoll = snap.lastRoll;
    consecutiveSixes = snap.consecutiveSixes;
    phase = snap.phase;
    winner = snap.winner;
    ranking
      ..clear()
      ..addAll(snap.ranking);
    lastMovedThisTurn = null;
  }

  /// Fige l'état courant AVANT une action. À appeler juste avant tout ce qui
  /// modifie la partie (lancer de dé, édition manuelle).
  void pushHistory(String label) {
    _history.add(_capture(label));
    if (_history.length > _maxHistory) _history.removeAt(0);
    _redo.clear();
  }

  /// Annule la dernière action : replace les 16 pions et rembobine l'état de
  /// tour tel qu'il était AVANT elle. Retourne `false` si rien à annuler.
  bool stepBack() {
    if (_history.isEmpty) return false;
    final snap = _history.removeLast();
    // L'état actuel (= APRÈS l'action annulée) devient rétablissable, sous le
    // même libellé que l'action.
    _redo.add(_capture(snap.label));
    _restore(snap);
    return true;
  }

  /// Rétablit l'action précédemment annulée. Retourne `false` si rien à
  /// rétablir.
  bool stepForward() {
    if (_redo.isEmpty) return false;
    final snap = _redo.removeLast();
    _history.add(_capture(snap.label));
    _restore(snap);
    return true;
  }

  /// Vide les deux piles (nouvelle partie).
  void clearHistory() {
    _history.clear();
    _redo.clear();
  }

  /// True quand [c] a déjà terminé (ses 4 pions au centre, rang attribué).
  bool hasFinished(PlayerColor c) => ranking.contains(c);

  /// Rang 1-based de [c] dans l'ordre d'arrivée, ou `null` s'il n'a pas
  /// encore fini.
  int? rankOf(PlayerColor c) {
    final i = ranking.indexOf(c);
    return i < 0 ? null : i + 1;
  }

  /// Recalcule [ranking]/[winner]/[phase] à partir de l'état réel des pions.
  /// Utilisé par l'éditeur manuel, qui pousse des pions vers/hors du centre
  /// sans passer par [movePawn].
  void recomputeStandings() {
    // On repart des seules couleurs réellement rentrées, dans l'ordre
    // d'arrivée déjà connu ; les nouvelles s'ajoutent à la suite.
    ranking.removeWhere((c) => !_allPawnsHome(c));
    for (final c in turnOrder) {
      if (_allPawnsHome(c) && !ranking.contains(c)) ranking.add(c);
    }
    winner = ranking.isEmpty ? null : ranking.first;
    final over = teamMode
        ? (winner != null &&
            _partners[winner!] != null &&
            _allPawnsHome(_partners[winner!]!))
        : ranking.isNotEmpty && ranking.length >= turnOrder.length - 1;
    if (over) {
      // Le ou les joueurs restants prennent d'office les dernières places.
      for (final c in turnOrder) {
        if (!ranking.contains(c)) ranking.add(c);
      }
      phase = TurnPhase.gameOver;
    } else if (phase == TurnPhase.gameOver) {
      phase = TurnPhase.rolling;
    }
  }

  void _returnPawnToBase(Pawn p) {
    p.location = PawnLocation.base;
    p.position = p.id;
  }

  bool _allPawnsHome(PlayerColor color) {
    return state.pawnsByColor[color]!
        .every((p) => p.location == PawnLocation.home);
  }

  /// Passe au joueur suivant en SAUTANT ceux qui ont déjà terminé (leurs 4
  /// pions sont au centre et leur rang est acquis). En mode équipe, un
  /// joueur classé garde la main tant que son partenaire n'a pas fini —
  /// c'est la règle "aide ton partenaire".
  void _nextPlayer() {
    diceValue = 0;
    consecutiveSixes = 0;
    lastMovedThisTurn = null;
    phase = TurnPhase.rolling;
    for (int i = 0; i < turnOrder.length; i++) {
      currentPlayerIdx = (currentPlayerIdx + 1) % turnOrder.length;
      final c = currentColor;
      if (!hasFinished(c)) return;
      final partner = _partners[c];
      if (teamMode && partner != null && !_allPawnsHome(partner)) return;
    }
  }
}
