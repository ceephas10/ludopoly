// Game engine for 4-player Ludo King rules.
//
// Owns the dice value, turn order, and the win condition check. Rule details
// (exit on 6, lap = 50 ring cells then 5-cell home column then center, exact
// roll to home, capture, safe cells, bonus turn on 6 / capture / home arrival,
// 3-six streak cancels the turn) live here.

import 'dart:math' as math;

import 'ai_difficulty.dart';
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

/// État de tour d'UNE couleur : son dé, sa série de 6, sa phase.
///
/// En mode ordinaire ces valeurs vivent directement sur le contrôleur, et
/// une seule couleur les utilise à la fois. En mode Rapide chaque couleur
/// a les siennes — c'est ce qui lui permet de jouer sans attendre les
/// autres. Voir [GameController.fastMode] et [GameController.runAsSeat].
class SeatTurn {
  int diceValue = 0;
  int consecutiveSixes = 0;
  Pawn? lastMoved;
  TurnPhase phase = TurnPhase.rolling;

  SeatTurn();

  SeatTurn.from(SeatTurn other)
      : diceValue = other.diceValue,
        consecutiveSixes = other.consecutiveSixes,
        lastMoved = other.lastMoved,
        phase = other.phase;
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

  /// État de tour de chaque couleur. Vide en mode ordinaire — la seule
  /// couleur qui joue a son état dans les champs ci-dessus. En mode Rapide
  /// il FAUT le mémoriser, sinon un retour arrière rendrait le plateau
  /// sans rendre les tours en cours des autres couleurs.
  final Map<PlayerColor, SeatTurn> seats;

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
    required this.seats,
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

  // La règle des blocs (barrière formée par 2 pions d'une même couleur sur
  // une case du ring) a été RETIRÉE : l'empilement de deux pions d'une même
  // couleur sur le ring est désormais interdit tout court, donc plus aucune
  // barrière ne peut se former. Voir [wouldSelfStack].

  /// 2v2 team mode toggle. When ON :
  ///   - blue + green form one team, yellow + red form the other ([_partners])
  ///   - capture is suppressed BETWEEN partners (a pion landing on a same-
  ///     team pion's cell does NOT send it back)
  ///   - a player whose 4 pawns are all home keeps playing on their turn,
  ///     but moves their partner's remaining pawns instead
  ///   - victory = a team has its 8 pawns home (4 + 4)
  bool teamMode = false;

  /// Mode Rapide — sans attente de tour.
  ///
  /// OFF (défaut) : les couleurs jouent chacune à leur tour, dans l'ordre
  /// fixe de [turnOrder]. C'est le Ludo classique.
  ///
  /// ON : chaque couleur mène SON tour indépendamment, avec son propre dé,
  /// sa propre série de 6 et sa propre phase — voir [SeatTurn]. Personne
  /// n'attend personne : un ordinateur joue pendant que l'humain réfléchit.
  /// [currentPlayerIdx] n'ordonne plus rien, il reflète simplement la
  /// dernière couleur à avoir agi.
  ///
  /// Le CLASSEMENT ne change pas : la partie continue après le premier
  /// arrivé, jusqu'à ce que tout le monde ait sa place.
  bool fastMode = false;

  /// État de tour de chaque couleur, utilisé par le mode Rapide.
  final Map<PlayerColor, SeatTurn> _seats = {};

  SeatTurn seatOf(PlayerColor c) => _seats.putIfAbsent(c, SeatTurn.new);

  /// Joue [body] au nom de [c], avec l'état de tour de SA couleur.
  ///
  /// Le principe est un simple échange : on charge le siège de [c] dans les
  /// champs partagés, on laisse le code de règles travailler exactement
  /// comme en mode ordinaire — il n'a aucune idée du mode Rapide — puis on
  /// remet le résultat dans le siège. Aucune règle n'est dupliquée.
  ///
  /// Dart n'a qu'un fil d'exécution : chaque appel est donc ATOMIQUE, et
  /// deux couleurs ne peuvent pas se marcher dessus au milieu d'un coup.
  /// « En même temps » veut dire entrelacé au fil des minuteries, ce qui
  /// suffit à ce qu'aucune couleur n'attende son tour.
  ///
  /// Hors mode Rapide, [body] s'exécute tel quel sur l'état partagé.
  void runAsSeat(PlayerColor c, void Function() body) {
    if (!fastMode) {
      body();
      return;
    }
    if (phase == TurnPhase.gameOver) return;
    final seat = seatOf(c);
    final idx = turnOrder.indexOf(c);
    if (idx < 0) return;

    currentPlayerIdx = idx;
    diceValue = seat.diceValue;
    consecutiveSixes = seat.consecutiveSixes;
    lastMovedThisTurn = seat.lastMoved;
    phase = seat.phase;

    body();

    seat.diceValue = diceValue;
    seat.consecutiveSixes = consecutiveSixes;
    seat.lastMoved = lastMovedThisTurn;
    // La fin de partie est GLOBALE : elle reste sur la phase partagée et
    // n'est pas rangée dans le siège, sinon les autres couleurs
    // continueraient de jouer sur un plateau terminé.
    seat.phase = phase == TurnPhase.gameOver ? TurnPhase.rolling : phase;
  }

  /// Remet tous les sièges à zéro. Appelé au reset et au changement de mode.
  void resetSeats() {
    _seats.clear();
    for (final c in turnOrder) {
      seatOf(c);
    }
  }

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

  /// Dernier pas encore SUR l'anneau, compté depuis la case de départ.
  ///
  /// Un pion ne fait PAS le tour complet des 52 cases : il quitte l'anneau
  /// par la bouche de son couloir, qui se trouve 50 pas après son départ.
  /// Les cases situées entre cette bouche et sa propre case de départ ne
  /// sont parcourues que par les AUTRES couleurs.
  ///
  /// Ce 50 n'est pas arbitraire, il est imposé par le dessin du plateau :
  /// la bouche du couloir de chaque couleur est orthogonalement adjacente
  /// à la case d'anneau qui se trouve à 50 pas de son départ.
  ///
  ///   bleu   couloir (7.5, 13.5) ← anneau 50 (7.5, 14.5)
  ///   rouge  couloir (1.5,  7.5) ← anneau 11 (0.5,  7.5)
  ///   vert   couloir (7.5,  1.5) ← anneau 24 (7.5,  0.5)
  ///   jaune  couloir (13.5, 7.5) ← anneau 37 (14.5, 7.5)
  ///
  /// Avec 51 le pion allait une case TROP LOIN — sur la case d'angle, juste
  /// avant son propre départ — puis rejoignait son couloir en diagonale : il
  /// dépassait visiblement la ligne de son couloir avant d'y entrer.
  /// `test/gameplay_test.dart` verrouille cette adjacence pour les 4 couleurs.
  static const int lastRingStep = 50;

  /// 50 pas d'anneau + 5 cases de couloir + 1 pas final vers la maison.
  static const int totalStepsToHome = lastRingStep + 6;

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

  /// Tire une valeur 1..6, uniforme SAUF sur un point : les valeurs qui
  /// feraient tomber un pion sur une case du ring déjà tenue par SA couleur
  /// sont écartées tant qu'il reste au moins une autre valeur.
  ///
  /// C'est le SEUL biais autorisé. Une version précédente préférait aussi
  /// les valeurs « jouables » — conséquence désastreuse : quand tous les
  /// pions étaient en base, la seule valeur jouable était 6, et le premier
  /// lancer de CHAQUE couleur donnait donc 6 à coup sûr. Un lancer sans
  /// coup jouable est un lancer normal du Ludo : le tour passe, c'est tout.
  /// Ne réintroduisez jamais de filtre de jouabilité ici —
  /// `test/gameplay_test.dart` le verrouille.
  int pickDiceValue([math.Random? rng]) {
    final r = rng ?? _rng;
    final pool = [
      for (int v = 1; v <= 6; v++)
        if (!_wastedByStackBan(v)) v,
    ];
    if (pool.isEmpty) return r.nextInt(6) + 1;
    return pool[r.nextInt(pool.length)];
  }

  /// Vrai quand la valeur [v] ne donnerait AUCUN coup jouable, et que le
  /// seul obstacle est l'interdit d'empilement.
  ///
  /// C'est le seul cas où il vaut la peine d'éviter une valeur. L'ancien
  /// filtre écartait [v] dès qu'UN pion s'y serait empilé, même quand la
  /// valeur offrait par ailleurs d'excellents coups — avec un pion sur sa
  /// flèche d'entrée et un autre 6 cases devant, le dé ne pouvait alors
  /// PLUS JAMAIS sortir de 6, et le joueur perdait du même coup toute
  /// possibilité de sortir un pion de sa base. L'interdit d'empilement,
  /// lui, suffit déjà à garantir que deux pions d'une couleur ne se posent
  /// jamais sur la même case : le dé n'a pas à s'en mêler davantage.
  bool _wastedByStackBan(int v) {
    final mine = state.pawnsByColor[currentColor]!;
    if (mine.any((p) => _canMoveAs(p, v, currentColor))) return false;
    return mine.any((p) => wouldSelfStack(p, v));
  }

  /// Roll a random 1..6, en évitant les valeurs qui viseraient un
  /// empilement — voir [pickDiceValue].
  void rollRandom() => roll(pickDiceValue());

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
        // La case départ ne doit pas déjà porter un pion de la couleur.
        return !wouldSelfStack(p, v);
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        if (taken + v > totalStepsToHome) return false;
        // Interdiction d'empilement : deux pions d'une même couleur ne
        // partagent jamais une case du ring.
        return !wouldSelfStack(p, v);
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
            if (s <= lastRingStep)
              PawnStep(PawnLocation.ring, (start + s) % ringSize)
            else if (s == totalStepsToHome)
              const PawnStep(PawnLocation.home, 0)
            else
              PawnStep(PawnLocation.homeColumn, s - lastRingStep - 1),
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
        if (newSteps <= lastRingStep) {
          p.position = (_startIdx[p.color]! + newSteps) % ringSize;
        } else if (newSteps == totalStepsToHome) {
          p.location = PawnLocation.home;
          homeArrival = true;
        } else {
          // newSteps in 51..55 → home column step 0..4.
          p.location = PawnLocation.homeColumn;
          p.position = newSteps - lastRingStep - 1;
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
  /// Score plancher de l'IA, en LITTÉRAL et surtout PAS `-1 << 30`.
  ///
  /// Sur le web, les opérations bit à bit de Dart travaillent en 32 bits
  /// NON SIGNÉS : `-1 << 30` y vaut +3 221 225 472 et non −1 073 741 824.
  /// La sentinelle « moins l'infini » devenait donc un plafond
  /// infranchissable : aucun score ne la dépassait, [pickAiPawn] rendait
  /// null avec des coups plein les mains, et l'IA ne jouait JAMAIS dans le
  /// navigateur — alors que tous les tests, exécutés sur la VM où le
  /// décalage est signé, passaient. Aucun décalage de bits sur des
  /// négatifs nulle part dans ce moteur.
  static const int _aiScoreFloor = -0x40000000;

  /// Niveau de jeu de l'ordinateur. Ne touche QUE le choix du pion — le dé
  /// l'ignore complètement, voir [AiDifficulty].
  AiDifficulty aiDifficulty = AiDifficulty.defaultLevel;

  Pawn? pickAiPawn() {
    final options = movablePawns();
    if (options.isEmpty) return null;
    if (options.length == 1) return options.single;

    // Erreur VOLONTAIRE des niveaux bas : on joue un coup légal au hasard
    // au lieu du meilleur. C'est le seul endroit où le hasard entre dans
    // la décision, et il ne touche jamais le dé.
    final blunder = aiDifficulty.blunderRate;
    if (blunder > 0 && _rng.nextDouble() < blunder) {
      return options[_rng.nextInt(options.length)];
    }

    Pawn? best;
    int bestScore = _aiScoreFloor;
    for (final p in options) {
      final s = _aiScore(p);
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return best;
  }

  /// Ce que vaut la position APRÈS le coup, du point de vue de [mover].
  ///
  /// Deux termes, tous deux pondérés par l'AVANCEMENT des pions concernés —
  /// perdre un pion à 40 pas coûte bien plus que d'en perdre un à 3 :
  ///
  ///   * le DANGER : mes pions, celui qui vient de bouger compris, qui se
  ///     retrouvent à portée d'un adversaire ;
  ///   * la MENACE : les pions adverses que je pourrai capturer au tour
  ///     suivant depuis ma nouvelle case.
  ///
  /// Portée honnête : c'est UN demi-coup d'avance, pas une recherche
  /// profonde. « À portée » veut dire à 1..6 pas, soit une chance sur six
  /// par poursuivant — l'espérance sur le dé est dans la pondération, pas
  /// dans un arbre de variantes.
  ///
  /// [destCell] est la case du ring où le pion atterrit, ou `null` s'il
  /// quitte le ring (couloir ou maison) : il devient alors intouchable et
  /// ne compte plus dans le danger.
  int _positionAfterMove(PlayerColor mover, Pawn moved, int? destCell,
      int destSteps) {
    int danger = 0;
    for (final p in state.pawnsByColor[mover]!) {
      final int cell;
      final int steps;
      if (identical(p, moved)) {
        if (destCell == null) continue; // sorti du ring : hors d'atteinte
        cell = destCell;
        steps = destSteps;
      } else {
        if (p.location != PawnLocation.ring) continue;
        cell = p.position;
        steps = _stepsTaken(p);
      }
      if (_isCapturableAt(cell, mover)) danger += 10 + steps;
    }

    int threat = 0;
    if (destCell != null) {
      for (final entry in state.pawnsByColor.entries) {
        if (_sameTeam(entry.key, mover)) continue;
        for (final foe in entry.value) {
          if (foe.location != PawnLocation.ring) continue;
          if (_safeCells.contains(foe.position)) continue;
          final gap = (foe.position - destCell + ringSize) % ringSize;
          // Il faut aussi que je puisse ENCORE l'atteindre : au-delà de ma
          // bouche de couloir je quitte le ring avant lui.
          if (gap >= 1 && gap <= 6 && destSteps + gap <= lastRingStep) {
            threat += 10 + _stepsTaken(foe);
          }
        }
      }
    }
    return threat - danger;
  }

  /// Vrai si un pion ADVERSE, encore sur l'anneau, se trouve de 1 à 6 pas
  /// derrière [cell] : il pourrait donc y capturer au prochain tour. Les
  /// cases sûres ne sont jamais dangereuses.
  bool _isCapturableAt(int cell, PlayerColor mover) {
    if (_safeCells.contains(cell)) return false;
    for (final entry in state.pawnsByColor.entries) {
      if (_sameTeam(entry.key, mover)) continue;
      for (final foe in entry.value) {
        if (foe.location != PawnLocation.ring) continue;
        final gap = (cell - foe.position + ringSize) % ringSize;
        // Le poursuivant doit aussi pouvoir ATTEINDRE la case : au-delà de
        // sa bouche de couloir il quitterait l'anneau avant.
        if (gap >= 1 &&
            gap <= 6 &&
            _stepsTaken(foe) + gap <= lastRingStep) {
          return true;
        }
      }
    }
    return false;
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
        } else if (newSteps > lastRingStep) {
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
          // Éviter de S'EXPOSER : un adversaire à 6 pas ou moins derrière
          // la case d'arrivée pourrait capturer au tour suivant. Le malus
          // reste sous les gros bonus (maison, capture, couloir) : on ne
          // renonce pas à un coup fort par peur, on départage les coups
          // ordinaires. Débutant et Moyen ne voient pas ce danger.
          if (aiDifficulty.riskAware &&
              score < 600 &&
              _isCapturableAt(target, p.color)) {
            score -= 150;
          }
        }
        break;
      case PawnLocation.homeColumn:
        score = (p.position + diceValue == 5) ? 1000 : 600 + p.position;
        break;
      case PawnLocation.home:
        // Littéral, pas `-1 << 29` : voir [_aiScoreFloor] — sur le web ce
        // décalage devenait un score COLOSSAL et positif, faisant du pion
        // déjà arrivé le meilleur choix possible.
        score = _aiScoreFloor;
        break;
    }

    // Anticipation (Grand Maître, Imbattable) : peser la position qui
    // SUIVRA le coup. Le terme est borné par le niveau pour qu'il départage
    // les coups ordinaires sans jamais renverser une arrivée à la maison ou
    // une capture — un pion rentré vaut mieux qu'un pion bien placé.
    final horizon = aiDifficulty.lookahead;
    if (horizon > 0 &&
        score != _aiScoreFloor &&
        p.location != PawnLocation.home) {
      final int? destCell;
      final int destSteps;
      if (p.location == PawnLocation.ring) {
        final newSteps = taken + diceValue;
        destSteps = newSteps;
        destCell = newSteps <= lastRingStep
            ? (_startIdx[p.color]! + newSteps) % ringSize
            : null; // couloir ou maison : plus sur le ring
      } else if (p.location == PawnLocation.base) {
        destSteps = 0;
        destCell = _startIdx[p.color]!;
      } else {
        destSteps = totalStepsToHome; // couloir : hors d'atteinte
        destCell = null;
      }
      final delta = _positionAfterMove(p.color, p, destCell, destSteps);
      score += delta.clamp(-horizon, horizon);
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

  /// Cases du ring déjà occupées par un pion de la couleur [color], en
  /// ignorant [except] (le pion qu'on s'apprête à bouger : il libère la
  /// sienne en partant).
  ///
  /// Deux pions d'une même couleur ne peuvent JAMAIS partager une case du
  /// ring — voir [wouldSelfStack]. Le couloir final, lui, reste privé et
  /// admet plusieurs pions de la couleur.
  Set<int> _selfOccupiedRing(PlayerColor color, {Pawn? except}) => {
        for (final p in state.pawnsByColor[color]!)
          if (p != except && p.location == PawnLocation.ring) p.position,
      };

  /// True si déplacer [p] de [v] le ferait atterrir sur une case du ring
  /// déjà occupée par un pion de SA couleur.
  ///
  /// Seule la case d'ARRIVÉE compte : un pion traverse librement les cases
  /// de ses camarades, il n'a juste pas le droit de s'y arrêter. Une arrivée
  /// dans le couloir ou à la maison n'est jamais concernée.
  bool wouldSelfStack(Pawn p, int v) {
    if (v <= 0) return false;
    final occupied = _selfOccupiedRing(p.color, except: p);
    if (occupied.isEmpty) return false;
    switch (p.location) {
      case PawnLocation.base:
        // Une SORTIE DE BASE n'est jamais bloquée, même si la case de
        // départ porte déjà un pion de la couleur.
        //
        // C'est la règle la plus fondamentale du Ludo : un 6 doit TOUJOURS
        // offrir le choix entre sortir un pion et en avancer un. L'interdit
        // d'empilement s'y appliquait, et il suffisait qu'un pion occupe sa
        // propre case de départ pour que les trois pions de base deviennent
        // injouables — le second 6 consécutif n'avait alors plus qu'un seul
        // coup possible et partait tout seul, sans laisser choisir.
        //
        // L'interdit reste entier pour tout déplacement ANNEAU → ANNEAU.
        return false;
      case PawnLocation.ring:
        final steps = _stepsTaken(p) + v;
        if (steps > lastRingStep) return false; // couloir ou maison
        return occupied.contains((_startIdx[p.color]! + steps) % ringSize);
      case PawnLocation.homeColumn:
      case PawnLocation.home:
        return false;
    }
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
        seats: {
          for (final e in _seats.entries) e.key: SeatTurn.from(e.value),
        },
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
    _seats
      ..clear()
      ..addEntries(
          snap.seats.entries.map((e) => MapEntry(e.key, SeatTurn.from(e.value))));
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
    // Mode Rapide : il n'y a pas de « joueur suivant ». La couleur qui
    // vient de jouer reprend simplement la main sur SON tour, et les autres
    // mènent le leur de leur côté. C'est tout l'objet du mode.
    if (fastMode) return;
    for (int i = 0; i < turnOrder.length; i++) {
      currentPlayerIdx = (currentPlayerIdx + 1) % turnOrder.length;
      final c = currentColor;
      if (!hasFinished(c)) return;
      final partner = _partners[c];
      if (teamMode && partner != null && !_allPawnsHome(partner)) return;
    }
  }
}
