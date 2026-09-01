// Les AMÉLIORATIONS LudoPoly : cases Vortex et cases Chance.
//
// Tout ce module est ADDITIF : il ne modifie aucune règle du Ludo de base.
// Éteint (par défaut), il est invisible ; allumé, il n'agit qu'aux points
// de branchement explicites du moteur (`GameController._applyVortexOnLanding`
// / `_applyChanceOnLanding` / gardes figé & invulnérable / `pickDiceValueFor`).
//
// GÉOMÉTRIE (verrouillée par test/upgrades_test.dart) :
//
//   * Vortex BON — la case de départ de chaque couleur (« première case
//     après la boîte départ »). Un pion qui s'y pose est aspiré vers la
//     case de départ de l'adversaire EN DIAGONALE (+26 pas). Réservé à la
//     couleur propriétaire : un pion adverse posé dessus ne bouge pas.
//
//   * Vortex MAUVAIS — la première case du couloir final de chaque couleur
//     (« première case de votre dernière ligne droite »). Le pion est
//     renvoyé sur l'anneau, à l'entrée de la dernière ligne droite de
//     l'adversaire en diagonale : il doit refaire la moitié du plateau.
//
//   * Cases CHANCE — 4 cases neutres (elles n'appartiennent à personne),
//     placées 2 cases AVANT chaque étoile de protection, soit 6 pas après
//     chaque départ : anneaux 6, 19, 32 et 45. Tout pion qui s'y pose tire
//     une carte du talon.
//
// TALON des cartes immédiates : mélangé au début, une carte par
// instruction ; une fois épuisé il est RETOURNÉ (pas remélangé) et l'on
// recommence — exactement comme un talon physique.
//
// DURÉES (« pendant 2 tours ») : un « tour » d'une couleur va de sa prise
// de main à son passage de main. Les états de pion (invulnérable, figé)
// prennent effet immédiatement et expirent après 2 tours COMPLETS du
// propriétaire ; les modificateurs de dé s'appliquent « à partir du tour
// suivant », donc pendant les 2 prochains tours de la couleur. Une carte
// retirée remplace l'existante — les effets ne se cumulent JAMAIS
// (règle « REPLACE_EXISTING » de la spec).

import 'dart:math' as math;

import 'pawn.dart';
import 'player_color.dart';

/// Quand une carte peut s'activer.
enum ChanceTiming { onChance, beforeRoll, afterRoll }

/// Immédiate (appliquée sur le pion tombé sur la case) ou différée
/// (conservée en main — phase 2, pas encore jouable).
enum CardKind { immediate, deferred }

/// Les actions du script (ANNEXE A de la spec).
enum CardAction {
  move,          // avancer / reculer de N cases
  teleport,      // se placer sur une case précise (juste devant la sortie)
  captureAhead,  // avancer sur le 1er adverse devant et le capturer
  captureBehind, // reculer sur le 1er adverse derrière et le capturer
  releaseAll,    // tous les pions de la base sortent d'un coup
  returnToBase,  // le pion retourne dans sa boîte départ
  setState,      // invulnérable / figé
  modifyDice,    // demi-dé / double-dé / deux dés
}

/// États temporaires d'un pion.
enum CardPawnState { invulnerable, frozen }

/// Modes de dé temporaires.
enum CardDiceMode {
  limit,   // demi-dé : 1..3
  double,  // double-dé : 2, 4, 6, 8, 10, 12
  twoDice, // deux dés sommés : 2..12
}

/// Une carte chance, portée telle quelle depuis le script JSON de la spec
/// (id, noms FR/EN/ES, type, timing, action). Les champs d'animation du
/// script (Start/Transition/EndAnimation) ne sont pas embarqués : les
/// émotions sont des assets à produire côté Studio Animations.
class ChanceCard {
  final String id;
  final String nameFr;
  final String nameEn;
  final String nameEs;
  final CardKind kind;
  final ChanceTiming timing;
  final CardAction action;

  /// STATUS de la spec : une carte INACTIVE est sautée, comme si elle
  /// n'existait pas dans le talon.
  final bool active;

  /// Nombre de cases pour [CardAction.move] (négatif = recul), pas visés
  /// pour [CardAction.teleport], durée en tours pour setState/modifyDice.
  final int value;
  final CardPawnState? pawnState;
  final CardDiceMode? diceMode;

  const ChanceCard({
    required this.id,
    required this.nameFr,
    required this.nameEn,
    required this.nameEs,
    required this.kind,
    required this.timing,
    required this.action,
    this.active = true,
    this.value = 0,
    this.pawnState,
    this.diceMode,
  });

  @override
  String toString() => id;
}

/// Le talon des cartes IMMÉDIATES : une carte par instruction de la spec.
const List<ChanceCard> kImmediateCards = [
  ChanceCard(
    id: 'IMM_PAWN_BACK_3',
    nameFr: 'Reculez de 3 cases',
    nameEn: 'Move back 3 spaces',
    nameEs: 'Retrocede 3 casillas',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.move,
    value: -3,
  ),
  ChanceCard(
    id: 'IMM_PAWN_FORWARD_3',
    nameFr: 'Avancez de 3 cases',
    nameEn: 'Move forward 3 spaces',
    nameEs: 'Avanza 3 casillas',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.move,
    value: 3,
  ),
  ChanceCard(
    id: 'IMM_ALL_PAWNS_OUT',
    nameFr: 'Tous vos pions sortent',
    nameEn: 'All your pawns come out',
    nameEs: 'Todas tus fichas salen',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.releaseAll,
  ),
  ChanceCard(
    id: 'IMM_PAWN_BEFORE_EXIT',
    nameFr: 'Votre pion se place juste devant la sortie',
    nameEn: 'Your pawn moves just before the exit',
    nameEs: 'Tu ficha se coloca justo antes de la salida',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.teleport,
  ),
  ChanceCard(
    id: 'IMM_PAWN_HOME',
    nameFr: 'Votre pion retourne dans sa boîte départ',
    nameEn: 'Your pawn goes back to its start box',
    nameEs: 'Tu ficha vuelve a su caja de salida',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.returnToBase,
  ),
  ChanceCard(
    id: 'IMM_PAWN_INVULNERABLE',
    nameFr: 'Pion invulnérable pendant 2 tours',
    nameEn: 'Invulnerable pawn for 2 turns',
    nameEs: 'Ficha invulnerable por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.setState,
    pawnState: CardPawnState.invulnerable,
    value: 2,
  ),
  ChanceCard(
    id: 'IMM_PAWN_FROZEN',
    nameFr: 'Pion figé pendant 2 tours',
    nameEn: 'Frozen pawn for 2 turns',
    nameEs: 'Ficha congelada por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.setState,
    pawnState: CardPawnState.frozen,
    value: 2,
  ),
  ChanceCard(
    id: 'IMM_CAPTURE_AHEAD',
    nameFr: 'Avancez sur le premier adversaire devant et capturez-le',
    nameEn: 'Advance to the first opponent ahead and capture it',
    nameEs: 'Avanza hasta el primer rival delante y captúralo',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.captureAhead,
  ),
  ChanceCard(
    id: 'IMM_CAPTURE_BEHIND',
    nameFr: 'Reculez sur le premier adversaire derrière et capturez-le',
    nameEn: 'Move back to the first opponent behind and capture it',
    nameEs: 'Retrocede hasta el primer rival detrás y captúralo',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.captureBehind,
  ),
  ChanceCard(
    id: 'IMM_DICE_HALF',
    nameFr: 'Demi-dé pendant 2 tours (1, 2 ou 3)',
    nameEn: 'Half dice for 2 turns',
    nameEs: 'Medio dado por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.modifyDice,
    diceMode: CardDiceMode.limit,
    value: 2,
  ),
  ChanceCard(
    id: 'IMM_DICE_DOUBLE',
    nameFr: 'Double-dé pendant 2 tours (2, 4, 6, 8, 10, 12)',
    nameEn: 'Double dice for 2 turns',
    nameEs: 'Dado doble por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.modifyDice,
    diceMode: CardDiceMode.double,
    value: 2,
  ),
  ChanceCard(
    id: 'IMM_TWO_DICE',
    nameFr: 'Deux dés pendant 2 tours (2 à 12)',
    nameEn: 'Two dice for 2 turns',
    nameEs: 'Dos dados por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.modifyDice,
    diceMode: CardDiceMode.twoDice,
    value: 2,
  ),
];

/// Géométrie des cases spéciales. Les 4 index de départ sont ceux de
/// [GameController] (bleu 0, rouge 13, vert 26, jaune 39) — verrouillés
/// des deux côtés par les tests.
class SpecialCells {
  static const int ringSize = 52;

  static const Map<PlayerColor, int> startOf = {
    PlayerColor.blue: 0,
    PlayerColor.red: 13,
    PlayerColor.green: 26,
    PlayerColor.yellow: 39,
  };

  /// L'adversaire EN DIAGONALE de chaque couleur, à +26 pas sur l'anneau
  /// (rouge en haut-gauche ↔ jaune en bas-droite, vert ↔ bleu).
  static const Map<PlayerColor, PlayerColor> diagonalOf = {
    PlayerColor.blue: PlayerColor.green,
    PlayerColor.green: PlayerColor.blue,
    PlayerColor.red: PlayerColor.yellow,
    PlayerColor.yellow: PlayerColor.red,
  };

  /// Vortex BON d'une couleur : sa case de départ.
  static int goodVortexCell(PlayerColor c) => startOf[c]!;

  /// Cible du vortex bon : la case de départ de la diagonale.
  static int goodVortexTarget(PlayerColor c) => startOf[diagonalOf[c]!]!;

  /// Cible du vortex MAUVAIS : la case d'anneau qui précède l'entrée du
  /// couloir de la diagonale (son 50e pas) — l'« entrée de la dernière
  /// ligne droite de l'adversaire en diagonale ».
  static int badVortexTarget(PlayerColor c) =>
      (startOf[diagonalOf[c]!]! + 50) % ringSize;

  /// Les 4 cases Chance : 2 cases avant chaque étoile (départ + 6).
  static const Set<int> chanceCells = {6, 19, 32, 45};
}

/// Un modificateur de dé actif pour une couleur.
class _DiceMod {
  final CardDiceMode mode;
  final int sinceDone; // tours terminés de la couleur au moment du tirage
  const _DiceMod(this.mode, this.sinceDone);
}

/// Un état temporaire posé sur un pion.
class _PawnMod {
  final CardPawnState state;
  final int sinceDone;
  const _PawnMod(this.state, this.sinceDone);
}

/// Tout l'état des Améliorations. Possédé par [GameController] et remis à
/// zéro avec lui — les instantanés du bouton Retour ne le couvrent PAS
/// (limite connue : annuler un coup n'annule pas la carte tirée).
class LudoUpgrades {
  /// Interrupteurs, pilotés par l'onglet « Règles du jeu ». Éteints par
  /// défaut : le jeu de base reste un Ludo King intact.
  bool vortexEnabled = false;
  bool chanceEnabled = false;

  /// Hasard du talon et des dés modifiés. Remplaçable par les tests pour
  /// un tirage reproductible.
  math.Random rng = math.Random();

  // --- Talon des cartes immédiates ---------------------------------------

  final List<ChanceCard> _deck = [];
  int _next = 0;

  /// Tire la carte du dessus. Premier tirage : le talon est mélangé.
  /// Talon épuisé : il est RETOURNÉ (ordre inversé, pas remélangé).
  ChanceCard drawImmediate() {
    if (_deck.isEmpty) {
      _deck.addAll(kImmediateCards.where((c) => c.active));
      _deck.shuffle(rng);
    }
    if (_next >= _deck.length) {
      final flipped = _deck.reversed.toList();
      _deck
        ..clear()
        ..addAll(flipped);
      _next = 0;
    }
    return _deck[_next++];
  }

  // --- Compteur de tours terminés, par couleur ---------------------------

  final Map<PlayerColor, int> _done = {
    for (final c in PlayerColor.values) c: 0,
  };

  /// Appelé par le moteur chaque fois qu'une couleur REND la main.
  void onTurnCompleted(PlayerColor c) => _done[c] = _done[c]! + 1;

  int doneTurns(PlayerColor c) => _done[c]!;

  // --- États de pion (invulnérable / figé) --------------------------------

  final Map<Pawn, _PawnMod> _pawnMods = {};

  /// Pose [state] sur [p]. REMPLACE l'état précédent : retirer une seconde
  /// carte « invulnérable » repart pour 2 tours, sans cumul.
  void setPawnState(Pawn p, CardPawnState state) =>
      _pawnMods[p] = _PawnMod(state, _done[p.color]!);

  bool _hasState(Pawn p, CardPawnState s) {
    final mod = _pawnMods[p];
    if (mod == null || mod.state != s) return false;
    // Actif dès maintenant, expiré après 2 tours COMPLETS du propriétaire.
    return _done[p.color]! - mod.sinceDone <= 2;
  }

  bool isInvulnerable(Pawn p) => _hasState(p, CardPawnState.invulnerable);
  bool isFrozen(Pawn p) => _hasState(p, CardPawnState.frozen);

  // --- Modificateurs de dé, par couleur -----------------------------------

  final Map<PlayerColor, _DiceMod> _diceMods = {};

  /// Pose [mode] sur la couleur [c] — remplace le précédent, sans cumul.
  void setDiceMode(PlayerColor c, CardDiceMode mode) =>
      _diceMods[c] = _DiceMod(mode, _done[c]!);

  /// Mode actif pour [c], ou `null` si le dé est normal. « Pendant 2 tours
  /// à partir du tour SUIVANT » : actif pendant les 2 tours qui suivent
  /// celui du tirage.
  CardDiceMode? activeDiceMode(PlayerColor c) {
    final mod = _diceMods[c];
    if (mod == null) return null;
    final d = _done[c]! - mod.sinceDone;
    return (d >= 1 && d <= 2) ? mod.mode : null;
  }

  // --- Annonces pour l'interface ------------------------------------------

  final List<String> _notices = [];

  void addNotice(String n) => _notices.add(n);

  /// Rend les annonces accumulées depuis le dernier appel, et les efface.
  List<String> takeNotices() {
    final out = List<String>.from(_notices);
    _notices.clear();
    return out;
  }

  // --- Cycle de vie -------------------------------------------------------

  /// Nouvelle partie : talon, compteurs, états et annonces repartent de
  /// zéro. Les interrupteurs, eux, restent tels que l'utilisateur les a
  /// réglés.
  void resetForNewGame() {
    _deck.clear();
    _next = 0;
    _pawnMods.clear();
    _diceMods.clear();
    _notices.clear();
    for (final c in PlayerColor.values) {
      _done[c] = 0;
    }
  }
}
