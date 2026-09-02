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
import 'upgrades.dart';

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

/// Le choix d'une IA : quelle carte différée jouer, et sur quelle cible.
class AiCardPlay {
  final ChanceCard card;
  final Pawn? targetPawn;
  final PlayerColor? targetPlayer;
  const AiCardPlay(this.card, {this.targetPawn, this.targetPlayer});
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

  /// Tire une valeur 1..6. STRICTEMENT UNIFORME, sans la moindre exception.
  ///
  /// Deux biais ont existé ici, tous deux retirés après avoir causé des
  /// bugs bien pires que le problème qu'ils prétendaient résoudre :
  ///
  ///   * préférer les valeurs « jouables » — quand tous les pions étaient
  ///     en base, seul le 6 était jouable, et le premier lancer de CHAQUE
  ///     couleur donnait donc 6 à coup sûr ;
  ///   * éviter les valeurs qui feraient tomber un pion sur son camarade —
  ///     avec un pion sur sa flèche d'entrée et un autre 6 cases devant,
  ///     le dé ne pouvait alors PLUS JAMAIS sortir de 6, et le joueur
  ///     perdait toute possibilité de sortir un pion de sa base.
  ///
  /// Un lancer sans coup jouable est un lancer normal du Ludo : le tour
  /// passe, c'est tout. N'ajoutez aucun filtre ici — l'équité du dé est
  /// verrouillée par `test/gameplay_test.dart`.
  int pickDiceValue([math.Random? rng]) => (rng ?? _rng).nextInt(6) + 1;



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
    // Branchement Améliorations : un pion FIGÉ par une carte chance ne
    // bouge pas (inerte quand les Améliorations sont éteintes).
    if (upgrades.isFrozen(p)) return false;
    if (!_sameTeam(p.color, playingFor)) return false;
    // Helping the partner: only allowed once [playingFor]'s own pions
    // are all at home.
    if (p.color != playingFor && !_allPawnsHome(playingFor)) return false;
    switch (p.location) {
      case PawnLocation.base:
        if (v != 6) return false;
        // Branchement Améliorations, carte 15 : ce pion est désigné, il ne
        // sort pas. Il reste en boîte et attendra une prochaine occasion.
        if (upgrades.cannotExit(p)) return false;
        // La case départ ne doit pas déjà porter un pion de la couleur.
        return !wouldSelfStack(p, v);
      case PawnLocation.ring:
        final taken = _stepsTaken(p);
        // SEULE exclusion d'un pion déjà en jeu : dépasser la maison. Le
        // compte doit être exact pour rentrer, c'est une règle du Ludo.
        //
        // Il y en avait une seconde — l'interdiction de se poser sur son
        // propre pion — et elle a été RETIRÉE. Elle rendait injouable un
        // pion parfaitement légitime dès que son camarade se trouvait
        // exactement à distance du dé, et le joueur voyait un pion sans
        // sélecteur sans comprendre pourquoi. Dans un Ludo classique ce
        // coup est légal : deux pions d'une couleur peuvent partager une
        // case. Voir `wouldSelfStack`, conservée mais plus consultée par
        // les règles.
        return taken + v <= totalStepsToHome;
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

    // Branchement Améliorations : le pion vient d'atterrir — un Vortex de
    // SA couleur peut l'aspirer ailleurs AVANT la résolution de capture,
    // qui s'applique alors à la case d'arrivée réelle. Inerte quand les
    // Améliorations sont éteintes.
    _applyVortexOnLanding(p);

    // Capture: opposing-team pawn(s) on the same non-safe ring cell go
    // back to base. In team mode, partner pawns on the cell are NEVER
    // captured.
    if (p.location == PawnLocation.ring && !_safeCells.contains(p.position)) {
      for (final color in state.pawnsByColor.keys) {
        if (_sameTeam(color, p.color)) continue;
        for (final other in state.pawnsByColor[color]!) {
          // Branchement Améliorations : un pion INVULNÉRABLE ne se fait
          // pas capturer — les deux pions cohabitent sur la case.
          if (upgrades.isInvulnerable(other)) continue;
          if (other.location == PawnLocation.ring &&
              other.position == p.position) {
            _returnPawnToBase(other);
            // Branchement Améliorations, carte 22 : la règle après capture
            // était armée. La victime rentre dans SA propre boîte et devra
            // faire 6 pour ressortir — on le dit explicitement.
            if (upgrades.consumeCaptureRule(p.color)) {
              upgrades.addNotice(
                  'Le pion ${other.id + 1} de ${_fr[other.color]} regagne '
                  'sa boîte de départ : il lui faudra un 6 pour ressortir.');
            }
            captured = true;
          }
        }
      }
    }

    // Branchement Améliorations : atterrir sur une case Chance tire une
    // carte immédiate et l'applique. Inerte quand éteint.
    _applyChanceOnLanding(p);

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
    // Branchement Améliorations : nouvelle partie, talon et effets à zéro.
    upgrades.resetForNewGame();
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
    // Branchement Améliorations : la couleur courante REND la main — son
    // compteur de tours terminés avance (durées des cartes « 2 tours »).
    //
    // Carte 15 : si elle a sorti un 6 pendant ce tour, l'occasion de
    // sortir s'est présentée et le pion désigné l'a laissée passer. La
    // marque tombe ici — « il attendra une prochaine possibilité ».
    if (consecutiveSixes > 0) {
      for (final missed in upgrades.consumeNoExitFor(currentColor)) {
        upgrades.addNotice(
            'Le pion ${missed.id + 1} de ${_fr[missed.color]} n\'a pas pu '
            'sortir : il attendra la prochaine occasion.');
      }
    }
    upgrades.onTurnCompleted(currentColor);
    diceValue = 0;
    consecutiveSixes = 0;
    lastMovedThisTurn = null;
    phase = TurnPhase.rolling;
    // Mode Rapide : il n'y a pas de « joueur suivant ». La couleur qui
    // vient de jouer reprend simplement la main sur SON tour, et les autres
    // mènent le leur de leur côté. C'est tout l'objet du mode.
    if (fastMode) return;
    // Branchement Améliorations : une couleur qui « ne joue pas pendant 2
    // tours » consomme un tour sauté et l'on cherche la suivante. Sans
    // aucune carte de ce type en jeu, `consumeSkip` rend toujours `false`
    // et la boucle interne se comporte EXACTEMENT comme avant.
    for (int attempt = 0; attempt < turnOrder.length * 3; attempt++) {
      bool skipped = false;
      for (int i = 0; i < turnOrder.length; i++) {
        currentPlayerIdx = (currentPlayerIdx + 1) % turnOrder.length;
        final c = currentColor;
        if (!hasFinished(c)) {
          if (!upgrades.consumeSkip(c)) return;
          upgrades.addNotice('${_fr[c]} passe son tour.');
          skipped = true;
          break;
        }
        final partner = _partners[c];
        if (teamMode && partner != null && !_allPawnsHome(partner)) {
          if (!upgrades.consumeSkip(c)) return;
          upgrades.addNotice('${_fr[c]} passe son tour.');
          skipped = true;
          break;
        }
      }
      if (!skipped) return; // tout le monde a terminé : rien à chercher
    }
  }

  // --- Améliorations LudoPoly : cases Vortex + cases Chance -----------------
  //
  // Tout ce qui suit est ADDITIF. Éteint (défaut), rien ne change au Ludo
  // de base — c'est verrouillé par test/upgrades_test.dart. La géométrie et
  // l'état vivent dans lib/game/upgrades.dart ; ici il n'y a que
  // l'application des effets sur la partie.

  /// État des Améliorations (interrupteurs, talon, effets en cours).
  final LudoUpgrades upgrades = LudoUpgrades();

  static const Map<PlayerColor, String> _fr = {
    PlayerColor.blue: 'bleu',
    PlayerColor.red: 'rouge',
    PlayerColor.green: 'vert',
    PlayerColor.yellow: 'jaune',
  };

  /// Tire la valeur du dé pour [c], en respectant un éventuel modificateur
  /// de carte chance (demi-dé, double-dé, deux dés). Sans modificateur,
  /// c'est EXACTEMENT [pickDiceValue] — le dé de base reste strictement
  /// uniforme.
  int pickDiceValueFor(PlayerColor c, [math.Random? rng]) {
    final r = rng ?? _rng;
    switch (upgrades.activeDiceMode(c)) {
      case null:
        return pickDiceValue(r);
      case CardDiceMode.limit:
        return r.nextInt(3) + 1;
      case CardDiceMode.double:
        return (r.nextInt(6) + 1) * 2;
      case CardDiceMode.twoDice:
        // Deux dés bien réels : on garde leurs deux faces pour les
        // MONTRER, et le moteur ne travaille que sur leur somme.
        final a = r.nextInt(6) + 1;
        final b = r.nextInt(6) + 1;
        upgrades.lastTwoDice = (a: a, b: b);
        return a + b;
    }
  }

  /// Vortex — appliqué à l'atterrissage d'un coup de dé, jamais à un
  /// déplacement de carte.
  ///
  /// DEUX cases par couleur, chacune avec sa règle, et elles n'agissent
  /// QUE pour leur couleur :
  ///   * la BONNE, juste devant la case de départ → le pion file sur la
  ///     première case de l'adversaire en diagonale (26 pas gagnés) ;
  ///   * la MAUVAISE, première case de la dernière ligne droite → le pion
  ///     revient sur celle de l'adversaire en diagonale (26 pas perdus).
  /// Chacune mène à son homologue d'en face, qui appartient à l'autre
  /// couleur : aucun enchaînement possible.
  /// L'INVULNÉRABILITÉ ne protège pas d'un vortex : elle empêche d'être
  /// CAPTURÉ par un adversaire, pas d'être aspiré par sa propre case. La
  /// règle vaut pour les 4 couleurs et pour tous les pions, sans exception.
  void _applyVortexOnLanding(Pawn p) {
    if (!upgrades.vortexEnabled) return;
    if (p.location != PawnLocation.ring) return;
    final diag = _fr[SpecialCells.diagonalOf[p.color]!];
    if (p.position == SpecialCells.goodVortexCell(p.color)) {
      p.position = SpecialCells.goodVortexTarget(p.color);
      upgrades.addNotice(
          'Vortex ${_fr[p.color]} : le pion ${p.id + 1} file sur la '
          'première case de $diag !');
      return;
    }
    if (p.position == SpecialCells.badVortexCell(p.color)) {
      p.position = SpecialCells.badVortexTarget(p.color);
      upgrades.addNotice(
          'Trou noir ${_fr[p.color]} : le pion ${p.id + 1} est renvoyé sur '
          'la dernière ligne droite de $diag…');
    }
  }

  /// Case Chance — appliquée à l'atterrissage d'un coup de dé sur l'une
  /// des 4 cases neutres : tire la carte du dessus du talon immédiat et
  /// l'applique au pion tombé sur la case.
  void _applyChanceOnLanding(Pawn p) {
    if (!upgrades.chanceEnabled) return;
    if (p.location != PawnLocation.ring) return;
    if (!SpecialCells.chanceCells.contains(p.position)) return;
    // Une chance sur deux : carte immédiate ou carte différée (Annexe B).
    final card = upgrades.drawOnChance(p.color);
    // La carte est retenue pour que l'interface l'OUVRE : le joueur doit
    // voir sa vraie face et l'instruction à suivre.
    upgrades.noteDrawn(card, p.color);
    if (card.kind == CardKind.deferred) {
      if (upgrades.addToHand(p.color, card)) {
        upgrades.addNotice('Carte différée pour ${_fr[p.color]} : '
            '« ${card.nameFr} » — à jouer à votre tour.');
      } else {
        // La main est pleine : il n'y a que 3 emplacements.
        upgrades.addNotice('Carte différée pour ${_fr[p.color]} : '
            '« ${card.nameFr} » — main pleine, la carte est perdue.');
      }
      return;
    }
    upgrades.addNotice(
        'Carte chance pour ${_fr[p.color]} : « ${card.nameFr} »');
    // Une immédiate qui réclame une cible ne part pas toute seule : le
    // joueur — ou l'ordinateur — désigne d'abord SON pion. Elle reste en
    // attente jusque-là.
    if (card.needsTarget && card.entity == CardEntity.pawn) {
      upgrades.notePendingChoice(card, p);
      return;
    }
    applyImmediateCard(card, p);
  }

  /// Les pions que [card] peut viser, la carte ayant été déclenchée par
  /// [onPawn]. Vide si elle ne demande aucun choix.
  List<Pawn> immediateTargets(ChanceCard card, Pawn onPawn) {
    if (!card.needsTarget || card.entity != CardEntity.pawn) return const [];
    final wantsOwn = card.scope == CardScope.self;
    return [
      for (final entry in state.pawnsByColor.entries)
        if (wantsOwn
            ? entry.key == onPawn.color
            : !_sameTeam(entry.key, onPawn.color))
          for (final p in entry.value)
            // Un pion arrivé au centre ne subit plus rien.
            if (p.location != PawnLocation.home)
              // Un pion INVULNÉRABLE ne se laisse pas viser par un
              // adversaire — ni capturer, ni contrôler.
              if (wantsOwn || !upgrades.isInvulnerable(p)) p,
    ];
  }

  /// Applique la carte en attente au pion [chosen]. Sans choix valable,
  /// elle retombe sur le pion qui l'a déclenchée : l'effet a toujours lieu.
  void resolvePendingImmediate({Pawn? chosen}) {
    final pending = upgrades.takePendingChoice();
    if (pending == null) return;
    final targets = immediateTargets(pending.card, pending.onPawn);
    final target =
        (chosen != null && targets.contains(chosen)) ? chosen : pending.onPawn;
    applyImmediateCard(pending.card, target);
    upgrades.addNotice(
        '${_fr[target.color]} : le pion ${target.id + 1} est désigné.');
  }

  /// Le pion qu'un ORDINATEUR désignerait pour la carte en attente : le
  /// plus avancé, donc le plus précieux à protéger.
  Pawn? pickAiImmediateTarget() {
    final pending = upgrades.pendingChoice;
    if (pending == null) return null;
    final targets = immediateTargets(pending.card, pending.onPawn);
    if (targets.isEmpty) return null;
    Pawn best = targets.first;
    int bestSteps = -1;
    for (final p in targets) {
      final st = p.location == PawnLocation.ring ? _stepsTaken(p) : -1;
      if (st > bestSteps) {
        bestSteps = st;
        best = p;
      }
    }
    return best;
  }

  /// Le joueur « à votre droite ». Le tour passe à votre gauche, donc le
  /// voisin de droite est celui qui vient de jouer — le PRÉCÉDENT dans
  /// l'ordre du tour.
  PlayerColor rightNeighbourOf(PlayerColor c) {
    final i = turnOrder.indexOf(c);
    if (i < 0) return c;
    return turnOrder[(i - 1 + turnOrder.length) % turnOrder.length];
  }

  /// [c] peut-il jouer [card] maintenant ? Une carte « Avant » se joue
  /// avant le lancer, une carte « Après » après ; et l'on ne joue qu'UNE
  /// carte différée par tour.
  bool canPlayDeferred(PlayerColor c, ChanceCard card) {
    if (phase == TurnPhase.gameOver) return false;
    if (currentColor != c) return false;
    if (upgrades.hasPlayedThisTurn(c)) return false;
    if (!upgrades.handOf(c).contains(card)) return false;
    // Le moteur EMPÊCHE de jouer une carte au mauvais moment : « une carte
    // AVANT ne peut pas être utilisée APRÈS », et réciproquement.
    return switch (phase) {
      TurnPhase.rolling => card.playableBeforeRoll,
      TurnPhase.moving => card.playableAfterRoll,
      TurnPhase.gameOver => false,
    };
  }

  /// Les pions que [c] peut désigner pour [card] (cartes « CHOSEN »).
  /// Vide pour les cartes qui ne visent pas un pion.
  List<Pawn> deferredPawnTargets(PlayerColor c, ChanceCard card) {
    if (card.entity != CardEntity.pawn ||
        card.selection != CardSelection.chosen) {
      return const [];
    }
    final wantsOwn = card.scope == CardScope.self;
    return [
      for (final entry in state.pawnsByColor.entries)
        if (wantsOwn ? entry.key == c : !_sameTeam(entry.key, c))
          for (final p in entry.value)
            // Un pion arrivé au centre ne subit plus rien.
            if (p.location != PawnLocation.home)
              // Un pion INVULNÉRABLE ne peut être ni capturé ni CONTRÔLÉ
              // par un adversaire : il ne figure pas dans ses cibles.
              if (wantsOwn || !upgrades.isInvulnerable(p))
                // Carte 15 : « empêcher de SORTIR » ne vise qu'un pion
                // encore dans sa boîte de départ — viser un pion déjà
                // sorti n'aurait aucun sens.
                if (card.action != CardAction.noExit ||
                    p.location == PawnLocation.base)
                  p,
    ];
  }

  /// Les joueurs que [c] peut désigner pour [card] (cartes « CHOSEN »).
  List<PlayerColor> deferredPlayerTargets(PlayerColor c, ChanceCard card) {
    if (card.entity != CardEntity.player ||
        card.selection != CardSelection.chosen) {
      return const [];
    }
    return [
      for (final other in turnOrder)
        if (!_sameTeam(other, c) && !hasFinished(other)) other,
    ];
  }

  /// Choisit la carte différée que [c] devrait jouer maintenant, cible
  /// comprise, ou `null` s'il n'y a rien de bon à jouer.
  ///
  /// L'ordinateur joue ses cartes comme un joueur : il ne les accumule pas
  /// jusqu'à saturer sa main. L'ordre de préférence est simple et se lit
  /// d'un trait — d'abord ce qui rapporte gros, ensuite ce qui gêne
  /// l'adversaire, enfin ce qui se protège.
  AiCardPlay? pickAiDeferred(PlayerColor c) {
    final playable = [
      for (final card in upgrades.handOf(c))
        if (canPlayDeferred(c, card)) card,
    ];
    if (playable.isEmpty) return null;

    ChanceCard? byId(bool Function(ChanceCard) test) {
      for (final card in playable) {
        if (test(card)) return card;
      }
      return null;
    }

    /// Mon pion le plus AVANCÉ encore sur l'anneau — le plus précieux.
    Pawn? myBest() {
      Pawn? best;
      int bestSteps = -1;
      for (final p in state.pawnsByColor[c]!) {
        if (p.location != PawnLocation.ring) continue;
        final st = _stepsTaken(p);
        if (st > bestSteps) {
          bestSteps = st;
          best = p;
        }
      }
      return best;
    }

    /// Le pion adverse le plus avancé, celui qui menace le plus.
    Pawn? foeBest({bool inBase = false}) {
      Pawn? best;
      int bestSteps = -1;
      for (final e in state.pawnsByColor.entries) {
        if (_sameTeam(e.key, c) || hasFinished(e.key)) continue;
        for (final p in e.value) {
          if (inBase) {
            if (p.location != PawnLocation.base) continue;
            return p;
          }
          if (p.location != PawnLocation.ring) continue;
          final st = _stepsTaken(p);
          if (st > bestSteps) {
            bestSteps = st;
            best = p;
          }
        }
      }
      return best;
    }

    // 1. Une carte-dé : c'est un coup CHOISI, le plus fort de tous. On
    //    prend 6 s'il reste un pion en boîte (sortir vaut tout), sinon la
    //    plus grande valeur disponible.
    final needsSix = state.pawnsByColor[c]!
        .any((p) => p.location == PawnLocation.base);
    final diceCards = [
      for (final card in playable)
        if (card.action == CardAction.setDice) card,
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (diceCards.isNotEmpty) {
      final six = diceCards.where((x) => x.value == 6);
      if (needsSix && six.isNotEmpty) return AiCardPlay(six.first);
      if (!needsSix) return AiCardPlay(diceCards.first);
    }

    // 2. Faire sauter le tour d'un adversaire encore en course.
    final skip = byId((x) => x.action == CardAction.skipTurn);
    if (skip != null) {
      if (skip.needsTarget) {
        final targets = deferredPlayerTargets(c, skip);
        if (targets.isNotEmpty) {
          return AiCardPlay(skip, targetPlayer: targets.first);
        }
      } else if (!hasFinished(rightNeighbourOf(c))) {
        return AiCardPlay(skip);
      }
    }

    // 3. Figer le pion adverse le plus avancé.
    final freeze = byId((x) =>
        x.action == CardAction.setState &&
        x.pawnState == CardPawnState.frozen);
    if (freeze != null) {
      final target = foeBest();
      if (target != null && deferredPawnTargets(c, freeze).contains(target)) {
        return AiCardPlay(freeze, targetPawn: target);
      }
    }

    // 4. Empêcher un adversaire de sortir.
    final noExit = byId((x) => x.action == CardAction.noExit);
    if (noExit != null) {
      final targets = deferredPawnTargets(c, noExit);
      if (targets.isNotEmpty) {
        return AiCardPlay(noExit, targetPawn: targets.first);
      }
    }

    // 5. Protéger son propre pion le plus avancé.
    final shield = byId((x) =>
        x.action == CardAction.setState &&
        x.pawnState == CardPawnState.invulnerable);
    if (shield != null) {
      final mine = myBest();
      if (mine != null && deferredPawnTargets(c, shield).contains(mine)) {
        return AiCardPlay(shield, targetPawn: mine);
      }
    }

    // 6. À défaut, la règle après capture — elle ne coûte rien.
    final rule = byId((x) => x.action == CardAction.captureToBox);
    if (rule != null) return AiCardPlay(rule);

    // Une carte-dé de faible valeur reste préférable à laisser la main
    // pleine : la main sature à 4 et tout tirage suivant serait perdu.
    if (diceCards.isNotEmpty && upgrades.handIsFull(c)) {
      return AiCardPlay(diceCards.first);
    }
    return null;
  }

  /// Joue la carte différée [card] au nom de [c].
  ///
  /// Renvoie la valeur de dé imposée par une carte-dé, ou `null` pour
  /// toute autre carte. L'appelant (l'interface) se charge alors de
  /// lancer le tour avec cette valeur. Ne fait rien — et renvoie `null` —
  /// si la carte n'est pas jouable maintenant.
  int? playDeferredCard(
    PlayerColor c,
    ChanceCard card, {
    Pawn? targetPawn,
    PlayerColor? targetPlayer,
  }) {
    if (!canPlayDeferred(c, card)) return null;
    if (card.needsTarget &&
        card.entity == CardEntity.pawn &&
        (targetPawn == null ||
            !deferredPawnTargets(c, card).contains(targetPawn))) {
      return null;
    }
    if (card.needsTarget &&
        card.entity == CardEntity.player &&
        (targetPlayer == null ||
            !deferredPlayerTargets(c, card).contains(targetPlayer))) {
      return null;
    }

    int? forcedDice;
    switch (card.action) {
      case CardAction.setState:
        upgrades.setPawnState(targetPawn!, card.pawnState!);
        break;
      case CardAction.noExit:
        upgrades.markNoExit(targetPawn!);
        break;
      case CardAction.setDice:
        forcedDice = card.value;
        break;
      case CardAction.captureToBox:
        upgrades.armCaptureRule(c);
        break;
      case CardAction.skipTurn:
        final victim = targetPlayer ?? rightNeighbourOf(c);
        // Un joueur ayant déjà rentré ses 4 pions ne joue plus : le tour
        // ne lui revient jamais, et la carte serait perdue pour rien.
        if (hasFinished(victim)) return null;
        upgrades.setSkipTurns(victim, card.value);
        break;
      // Les autres actions n'existent que sur les cartes immédiates.
      case CardAction.move:
      case CardAction.teleport:
      case CardAction.captureAhead:
      case CardAction.captureBehind:
      case CardAction.releaseAll:
      case CardAction.returnToBase:
      case CardAction.modifyDice:
        return null;
    }

    upgrades.removeFromHand(c, card);
    upgrades.markPlayed(c);
    upgrades.addNotice('${_fr[c]} joue « ${card.nameFr} »');
    return forcedDice;
  }

  /// Applique une carte immédiate sur [p]. Public : les tests s'en servent
  /// carte par carte, et la phase 2 (cartes différées) le réutilisera.
  ///
  /// Les effets de carte ne donnent JAMAIS de tour bonus — seuls le 6, la
  /// capture au dé et l'arrivée au dé en donnent, comme avant.
  void applyImmediateCard(ChanceCard card, Pawn p) {
    switch (card.action) {
      case CardAction.move:
        _cardMove(p, card.value);
        break;
      case CardAction.teleport:
        // « Juste devant la sortie » : le 50e pas, la bouche du couloir.
        if (p.location == PawnLocation.ring) {
          p.position = (_startIdx[p.color]! + lastRingStep) % ringSize;
          _settleAfterCardMove(p);
        }
        break;
      case CardAction.returnToBase:
        _returnPawnToBase(p);
        break;
      case CardAction.releaseAll:
        // Sortie groupée : les pions restés en base rejoignent la case de
        // départ (l'empilement de sa propre couleur est légal). Le vortex
        // ne se déclenche pas sur une sortie de carte.
        for (final mate in state.pawnsByColor[p.color]!) {
          // Carte 15 : un pion à qui l'on a interdit de sortir ne part pas
          // avec les autres.
          if (upgrades.cannotExit(mate)) continue;
          if (mate.location == PawnLocation.base) {
            mate.location = PawnLocation.ring;
            mate.position = _startIdx[p.color]!;
          }
        }
        break;
      case CardAction.captureAhead:
        _cardChase(p, forward: true);
        break;
      case CardAction.captureBehind:
        _cardChase(p, forward: false);
        break;
      case CardAction.setState:
        // Le GEL immédiat ne mord qu'au tour SUIVANT : le pion vient de
        // jouer pour arriver ici, ce tour-ci est déjà dépensé. Sans ce
        // décalage la carte ne coûtait qu'un seul tour jouable.
        // L'INVULNÉRABILITÉ, elle, protège tout de suite — c'est pendant
        // les tours adverses qui suivent que le pion risque d'être mangé.
        upgrades.setPawnState(p, card.pawnState!,
            startsIn: card.pawnState == CardPawnState.frozen ? 1 : 0);
        break;
      case CardAction.modifyDice:
        // Le modificateur suit CELUI QUI LANCE, pas la couleur du pion :
        // en mode Équipe un joueur ayant fini joue les pions de son
        // partenaire, et la carte doit peser sur son propre dé.
        upgrades.setDiceMode(currentColor, card.diceMode!);
        break;
      // Actions réservées aux cartes DIFFÉRÉES : elles passent par
      // [playDeferredCard], jamais par une case Chance.
      case CardAction.setDice:
      case CardAction.noExit:
      case CardAction.captureToBox:
      case CardAction.skipTurn:
        break;
    }
  }

  /// Avance ([delta] > 0) ou recule ([delta] < 0) un pion d'anneau, avec
  /// capture à l'arrivée. Le recul s'arrête à la case de départ (pas 0) —
  /// un pion ne recule jamais « avant » son entrée, sinon le compte de
  /// pas repartirait de l'autre bout de l'anneau et le recul deviendrait
  /// un bond en avant. L'avance qui dépasserait la maison ne bouge pas
  /// (le compte doit être exact, comme au dé).
  void _cardMove(Pawn p, int delta) {
    if (p.location != PawnLocation.ring) return;
    final taken = _stepsTaken(p);
    final target = taken + delta;
    if (delta < 0) {
      final clamped = math.max(0, target);
      p.position = (_startIdx[p.color]! + clamped) % ringSize;
      _settleAfterCardMove(p);
      return;
    }
    if (target > totalStepsToHome) return;
    if (target == totalStepsToHome) {
      p.location = PawnLocation.home;
      p.position = 0;
    } else if (target > lastRingStep) {
      p.location = PawnLocation.homeColumn;
      p.position = target - lastRingStep - 1;
    } else {
      p.position = (_startIdx[p.color]! + target) % ringSize;
      _settleAfterCardMove(p);
    }
  }

  /// « Avancez/Reculez sur le premier pion adverse et capturez-le » : le
  /// pion saute sur la case du premier adverse CAPTURABLE (hors cases
  /// sûres, hors invulnérables, hors coéquipiers) trouvé sur son chemin —
  /// à venir (jusqu'à sa bouche de couloir) ou parcouru (jusqu'à son
  /// départ). Aucune cible : la carte ne fait rien.
  void _cardChase(Pawn p, {required bool forward}) {
    if (p.location != PawnLocation.ring) return;
    final taken = _stepsTaken(p);
    final steps = forward
        ? [for (int s = taken + 1; s <= lastRingStep; s++) s]
        : [for (int s = taken - 1; s >= 0; s--) s];
    for (final s in steps) {
      final cell = (_startIdx[p.color]! + s) % ringSize;
      if (_safeCells.contains(cell)) continue;
      final hasVictim = state.pawnsByColor.entries.any((e) =>
          !_sameTeam(e.key, p.color) &&
          e.value.any((foe) =>
              foe.location == PawnLocation.ring &&
              foe.position == cell &&
              !upgrades.isInvulnerable(foe)));
      if (hasVictim) {
        p.position = cell;
        _settleAfterCardMove(p);
        return;
      }
    }
  }

  /// Le pion vient d'être POSÉ par une carte : il atterrit, donc les cases
  /// spéciales lui répondent comme après un coup de dé.
  ///
  /// « Tomber sur » une case ne veut pas dire « y arriver au dé » : une
  /// carte qui vous y dépose vous y dépose quand même. Le vortex agit
  /// d'abord, puis la capture se résout à la case d'ARRIVÉE réelle.
  ///
  /// Aucun enchaînement sans fin : le vortex mène toujours à la case de
  /// l'adversaire en diagonale, qui n'appartient pas à ce pion.
  void _settleAfterCardMove(Pawn p) {
    _applyVortexOnLanding(p);
    _cardCaptureEnemiesAt(p);
  }

  /// Capture par CARTE à la case du pion [p] : mêmes règles que la capture
  /// au dé (cases sûres intouchables, coéquipiers épargnés, invulnérables
  /// épargnés) — mais sans tour bonus.
  void _cardCaptureEnemiesAt(Pawn p) {
    if (p.location != PawnLocation.ring) return;
    if (_safeCells.contains(p.position)) return;
    for (final entry in state.pawnsByColor.entries) {
      if (_sameTeam(entry.key, p.color)) continue;
      for (final other in entry.value) {
        if (upgrades.isInvulnerable(other)) continue;
        if (other.location == PawnLocation.ring &&
            other.position == p.position) {
          _returnPawnToBase(other);
          // Même règle qu'au dé : la carte 22 vaut pour TOUTE capture du
          // tour, sinon elle serait gaspillée quand c'est une carte qui
          // mange.
          if (upgrades.consumeCaptureRule(p.color)) {
            upgrades.addNotice(
                'Le pion ${other.id + 1} de ${_fr[other.color]} regagne sa '
                'boîte de départ : il lui faudra un 6 pour ressortir.');
          }
        }
      }
    }
  }
}
