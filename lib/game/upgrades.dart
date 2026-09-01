// Les AMÉLIORATIONS LudoPoly : cases Vortex et cases Chance.
//
// Tout ce module est ADDITIF : il ne modifie aucune règle du Ludo de base.
// Éteint (par défaut), il est invisible ; allumé, il n'agit qu'aux points
// de branchement explicites du moteur.
//
// GÉOMÉTRIE (verrouillée par test/upgrades_test.dart) :
//
//   * Vortex BON — la case de départ de chaque couleur (« première case
//     après la boîte départ »). Elle est déjà peinte à votre couleur sur
//     le plateau, ce qui colle au « elle est à votre couleur » de la spec.
//     Un pion qui s'y pose est aspiré vers la case de départ de
//     l'adversaire EN DIAGONALE (+26 pas). Réservé à la couleur
//     propriétaire : un pion adverse posé dessus ne bouge pas.
//
//   * Vortex MAUVAIS — la première case du couloir final de chaque couleur
//     (« première case de votre dernière ligne droite »), elle aussi à
//     votre couleur. Le pion est renvoyé sur l'anneau, à l'entrée de la
//     dernière ligne droite de l'adversaire en diagonale.
//
//   * Cases CHANCE — 4 cases NEUTRES (elles ne portent la couleur d'aucun
//     joueur, cf. Annexe B), placées 2 cases AVANT chaque étoile de
//     protection, soit 6 pas après chaque départ : anneaux 6, 19, 32, 45.
//
// TIRAGE (Annexe B) : à l'arrivée sur une case Chance, une chance sur deux
// de tirer une carte IMMÉDIATE (appliquée sur-le-champ au pion tombé
// dessus) ou une carte DIFFÉRÉE (conservée en main, jouée plus tard).
//
// TALONS : une carte par instruction. Mélangé au début ; une fois épuisé
// il est RETOURNÉ (pas remélangé) et l'on recommence — comme un talon
// physique. Le talon immédiat est commun ; chaque joueur a en plus SON
// talon de toutes les cartes différées.
//
// DURÉES (« pendant 2 tours »). Un « tour » d'une couleur va de sa prise
// de main à son passage de main.
//   * États de pion (invulnérable, figé) : la spec ne dit rien de
//     particulier, ils prennent donc effet IMMÉDIATEMENT et couvrent 2
//     tours du propriétaire — celui du tirage et le suivant. C'est ce qui
//     donne son sens à « invulnérable » : le pion est protégé pendant que
//     les adversaires jouent, juste après le tirage.
//   * Modificateurs de dé : la spec dit explicitement « à partir du tour
//     suivant », donc les 2 tours QUI SUIVENT celui du tirage.
// Une carte re-tirée REMPLACE l'effet en cours, la durée repart de zéro :
// aucun cumul (règle « REPLACE_EXISTING » de l'Annexe A).

import 'dart:math' as math;

import 'pawn.dart';
import 'player_color.dart';

/// Quand une carte peut s'activer (Annexe A, table « Timing »).
enum ChanceTiming {
  /// Arrivée sur une case Chance.
  onChance,

  /// Avant le lancer de dé.
  beforeRoll,

  /// Après le lancer de dé.
  afterRoll,
}

/// Immédiate (appliquée sur-le-champ au pion tombé sur la case) ou
/// différée (conservée en main et jouée à son tour).
enum CardKind { immediate, deferred }

/// Les actions du script (Annexe A, « Actions supportées »).
enum CardAction {
  move,          // avancer / reculer de N cases
  teleport,      // se placer sur une case précise
  captureAhead,  // avancer sur le 1er adverse devant et le capturer
  captureBehind, // reculer sur le 1er adverse derrière et le capturer
  releaseAll,    // tous les pions de la base sortent d'un coup
  returnToBase,  // le pion retourne dans sa boîte départ
  setState,      // invulnérable / figé
  modifyDice,    // demi-dé / double-dé / deux dés
  setDice,       // carte-dé : remplace le lancer par une valeur fixe
  noExit,        // le pion désigné passe sa sortie et refait le tour
  captureToBox,  // le prochain pion capturé va dans VOTRE boîte
  skipTurn,      // un joueur ne joue pas pendant N tours
}

/// Portée d'une carte (Annexe A, « Ciblage »).
enum CardScope { self, opponent, any }

/// Ce que la carte vise.
enum CardEntity { pawn, player }

/// Qui choisit la cible, et comment (Annexe A, « SELECTION »).
enum CardSelection {
  /// Pion ayant déclenché la case Chance — choisi par le système.
  pawnOnChance,

  /// Cible choisie par le joueur.
  chosen,

  /// Premier pion adverse devant — choisi par le système.
  firstOnPath,

  /// Premier pion adverse derrière — choisi par le système.
  firstBehind,

  /// Aucune cible à désigner (la carte se suffit à elle-même).
  none,
}

/// États temporaires d'un pion.
enum CardPawnState { invulnerable, frozen }

/// Modes de dé temporaires.
enum CardDiceMode {
  limit,   // demi-dé : 1..3
  double,  // double-dé : 2, 4, 6, 8, 10, 12
  twoDice, // deux dés sommés : 2..12
}

/// Une carte chance, portée telle quelle depuis le script JSON de l'Annexe
/// A. Les champs d'animation du script (Start/Transition/EndAnimation) ne
/// sont pas embarqués : les émotions sont des assets à produire côté
/// Studio Animations.
class ChanceCard {
  final String id;
  final String nameFr;
  final String nameEn;
  final String nameEs;
  final CardKind kind;
  final ChanceTiming timing;
  final CardAction action;

  final CardScope scope;
  final CardEntity entity;
  final CardSelection selection;

  /// STATUS de l'Annexe A : une carte INACTIVE est sautée, comme si elle
  /// n'existait pas dans le talon.
  final bool active;

  /// Nombre de cases pour [CardAction.move] (négatif = recul), valeur du
  /// dé pour [CardAction.setDice], durée en tours pour setState /
  /// modifyDice / skipTurn.
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
    this.scope = CardScope.self,
    this.entity = CardEntity.pawn,
    this.selection = CardSelection.pawnOnChance,
    this.active = true,
    this.value = 0,
    this.pawnState,
    this.diceMode,
  });

  /// Vrai si le joueur doit DÉSIGNER une cible avant de jouer la carte.
  bool get needsTarget => selection == CardSelection.chosen;

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
    entity: CardEntity.player,
    selection: CardSelection.none,
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
    selection: CardSelection.firstOnPath,
  ),
  ChanceCard(
    id: 'IMM_CAPTURE_BEHIND',
    nameFr: 'Reculez sur le premier adversaire derrière et capturez-le',
    nameEn: 'Move back to the first opponent behind and capture it',
    nameEs: 'Retrocede hasta el primer rival detrás y captúralo',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.captureBehind,
    selection: CardSelection.firstBehind,
  ),
  ChanceCard(
    id: 'IMM_DICE_HALF',
    nameFr: 'Demi-dé pendant 2 tours (1, 2 ou 3)',
    nameEn: 'Half dice for 2 turns',
    nameEs: 'Medio dado por 2 turnos',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.modifyDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
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
    entity: CardEntity.player,
    selection: CardSelection.none,
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
    entity: CardEntity.player,
    selection: CardSelection.none,
    diceMode: CardDiceMode.twoDice,
    value: 2,
  ),
];

/// Le talon des cartes DIFFÉRÉES. Chaque joueur possède le sien, complet.
/// « Avant » = jouable avant le lancer, « Après » = après le lancer.
const List<ChanceCard> kDeferredCards = [
  // ---- Concernant les pions ----
  ChanceCard(
    id: 'DEF_PAWN_INVULNERABLE',
    nameFr: 'Votre pion invulnérable pendant 2 tours (Avant)',
    nameEn: 'Your pawn invulnerable for 2 turns',
    nameEs: 'Tu ficha invulnerable por 2 turnos',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setState,
    selection: CardSelection.chosen,
    pawnState: CardPawnState.invulnerable,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_OPPONENT_FROZEN',
    nameFr: 'Pion d\'un adversaire figé pendant 2 tours (Avant)',
    nameEn: 'An opponent\'s pawn frozen for 2 turns',
    nameEs: 'Ficha de un rival congelada por 2 turnos',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setState,
    scope: CardScope.opponent,
    selection: CardSelection.chosen,
    pawnState: CardPawnState.frozen,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_OPPONENT_NO_EXIT',
    nameFr: 'Un pion adverse passe sa sortie et refait le tour (Avant)',
    nameEn: 'An opponent\'s pawn misses its exit and laps again',
    nameEs: 'Una ficha rival pasa su salida y da otra vuelta',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.noExit,
    scope: CardScope.opponent,
    selection: CardSelection.chosen,
  ),
  // ---- Concernant les dés : 6 cartes, de 1 à 6 ----
  ChanceCard(
    id: 'DEF_DICE_1',
    nameFr: 'Carte dé : 1 (Avant)',
    nameEn: 'Dice card: 1',
    nameEs: 'Carta de dado: 1',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 1,
  ),
  ChanceCard(
    id: 'DEF_DICE_2',
    nameFr: 'Carte dé : 2 (Avant)',
    nameEn: 'Dice card: 2',
    nameEs: 'Carta de dado: 2',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_DICE_3',
    nameFr: 'Carte dé : 3 (Avant)',
    nameEn: 'Dice card: 3',
    nameEs: 'Carta de dado: 3',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 3,
  ),
  ChanceCard(
    id: 'DEF_DICE_4',
    nameFr: 'Carte dé : 4 (Avant)',
    nameEn: 'Dice card: 4',
    nameEs: 'Carta de dado: 4',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 4,
  ),
  ChanceCard(
    id: 'DEF_DICE_5',
    nameFr: 'Carte dé : 5 (Avant)',
    nameEn: 'Dice card: 5',
    nameEs: 'Carta de dado: 5',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 5,
  ),
  ChanceCard(
    id: 'DEF_DICE_6',
    nameFr: 'Carte dé : 6 (Avant)',
    nameEn: 'Dice card: 6',
    nameEs: 'Carta de dado: 6',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 6,
  ),
  // ---- Concernant les captures ----
  ChanceCard(
    id: 'DEF_CAPTURE_TO_MY_BOX',
    nameFr: 'Le pion capturé va dans VOTRE boîte départ (Après)',
    nameEn: 'The captured pawn goes into YOUR start box',
    nameEs: 'La ficha capturada va a TU caja de salida',
    kind: CardKind.deferred,
    timing: ChanceTiming.afterRoll,
    action: CardAction.captureToBox,
    entity: CardEntity.player,
    selection: CardSelection.none,
  ),
  // ---- Concernant les joueurs ----
  ChanceCard(
    id: 'DEF_SKIP_RIGHT',
    nameFr: 'Le joueur à votre droite ne joue pas pendant 2 tours (Avant)',
    nameEn: 'The player on your right misses 2 turns',
    nameEs: 'El jugador a tu derecha pierde 2 turnos',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.skipTurn,
    scope: CardScope.opponent,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_SKIP_CHOSEN',
    nameFr: 'Le joueur de votre choix ne joue pas pendant 2 tours (Avant)',
    nameEn: 'A player of your choice misses 2 turns',
    nameEs: 'El jugador que elijas pierde 2 turnos',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.skipTurn,
    scope: CardScope.opponent,
    entity: CardEntity.player,
    selection: CardSelection.chosen,
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

/// Un talon de cartes à jouer : mélangé une fois, puis RETOURNÉ (et non
/// remélangé) chaque fois qu'il est épuisé.
class _Deck {
  final List<ChanceCard> _cards = [];
  final List<ChanceCard> _source;
  int _next = 0;

  _Deck(this._source);

  ChanceCard draw(math.Random rng) {
    if (_cards.isEmpty) {
      // STATUS : une carte INACTIVE est sautée, comme si elle n'existait pas.
      _cards.addAll(_source.where((c) => c.active));
      _cards.shuffle(rng);
    }
    if (_next >= _cards.length) {
      final flipped = _cards.reversed.toList();
      _cards
        ..clear()
        ..addAll(flipped);
      _next = 0;
    }
    return _cards[_next++];
  }

  void reset() {
    _cards.clear();
    _next = 0;
  }
}

/// Tout l'état des Améliorations. Possédé par [GameController] et remis à
/// zéro avec lui — les instantanés du bouton Retour ne le couvrent PAS
/// (limite connue : annuler un coup n'annule pas la carte tirée).
class LudoUpgrades {
  /// Interrupteurs, pilotés par l'onglet « Règles du jeu ». Éteints par
  /// défaut : le jeu de base reste un Ludo King intact.
  bool vortexEnabled = false;
  bool chanceEnabled = false;

  /// Hasard des talons, du tirage immédiate/différée et des dés modifiés.
  /// Remplaçable par les tests pour un tirage reproductible.
  math.Random rng = math.Random();

  /// Nombre maximum de cartes différées tenues en main (spec : 4).
  static const int handLimit = 4;

  // --- Talons -------------------------------------------------------------

  final _Deck _immediate = _Deck(kImmediateCards);
  final Map<PlayerColor, _Deck> _deferred = {
    for (final c in PlayerColor.values) c: _Deck(kDeferredCards),
  };

  /// Tire la carte du dessus du talon immédiat.
  ChanceCard drawImmediate() => _immediate.draw(rng);

  /// Tire la carte du dessus du talon différé de [c] — chaque joueur a le
  /// sien, complet.
  ChanceCard drawDeferred(PlayerColor c) => _deferred[c]!.draw(rng);

  /// Tirage sur une case Chance : UNE CHANCE SUR DEUX de tomber sur une
  /// carte immédiate ou sur une différée (Annexe B).
  ChanceCard drawOnChance(PlayerColor c) =>
      rng.nextBool() ? drawImmediate() : drawDeferred(c);

  // --- Main de cartes différées, par joueur -------------------------------

  final Map<PlayerColor, List<ChanceCard>> _hands = {
    for (final c in PlayerColor.values) c: <ChanceCard>[],
  };

  /// Les cartes différées que [c] tient en main (au plus [handLimit]).
  List<ChanceCard> handOf(PlayerColor c) => List.unmodifiable(_hands[c]!);

  bool handIsFull(PlayerColor c) => _hands[c]!.length >= handLimit;

  /// Range [card] dans la main de [c]. Renvoie `false` si la main est
  /// pleine : il n'y a de la place que pour 4 cartes différées, la carte
  /// tirée en trop est perdue.
  bool addToHand(PlayerColor c, ChanceCard card) {
    if (handIsFull(c)) return false;
    _hands[c]!.add(card);
    return true;
  }

  void removeFromHand(PlayerColor c, ChanceCard card) =>
      _hands[c]!.remove(card);

  // --- « On ne joue qu'une carte différée à la fois » ----------------------

  final Set<PlayerColor> _playedThisTurn = {};

  bool hasPlayedThisTurn(PlayerColor c) => _playedThisTurn.contains(c);

  void markPlayed(PlayerColor c) => _playedThisTurn.add(c);

  // --- Compteur de tours terminés, par couleur ---------------------------

  final Map<PlayerColor, int> _done = {
    for (final c in PlayerColor.values) c: 0,
  };

  /// Appelé par le moteur chaque fois qu'une couleur REND la main.
  void onTurnCompleted(PlayerColor c) {
    _done[c] = _done[c]! + 1;
    // Le tour est fini : la couleur pourra rejouer une carte différée.
    _playedThisTurn.remove(c);
    // Une carte « le prochain capturé va dans ma boîte » non utilisée
    // pendant le tour où elle a été jouée est perdue.
    _captureToBox.remove(c);
  }

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
    // Effet IMMÉDIAT, sur 2 tours du propriétaire : celui du tirage
    // (d = 0) et le suivant (d = 1). Voir l'en-tête du fichier.
    return _done[p.color]! - mod.sinceDone < 2;
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

  // --- « Refaire le tour » : le pion désigné passe sa sortie --------------

  final Set<Pawn> _mustLap = {};

  void markMustLap(Pawn p) => _mustLap.add(p);

  /// Vrai tant que [p] n'a pas encore raté sa sortie.
  bool mustLap(Pawn p) => _mustLap.contains(p);

  /// Le pion vient de passer devant sa sortie : la marque est consommée,
  /// il pourra rentrer au tour suivant.
  void clearLap(Pawn p) => _mustLap.remove(p);

  // --- « Le pion capturé va dans VOTRE boîte départ » ---------------------

  final Set<PlayerColor> _captureToBox = {};

  /// Arme la carte pour [c] : sa prochaine capture de ce tour enverra la
  /// victime dans SA boîte départ.
  void armCaptureToBox(PlayerColor c) => _captureToBox.add(c);

  bool captureToBoxArmed(PlayerColor c) => _captureToBox.contains(c);

  /// Consomme l'armement s'il existe. Renvoie `true` s'il a servi.
  bool consumeCaptureToBox(PlayerColor c) => _captureToBox.remove(c);

  /// Pions prisonniers : rangés dans la boîte d'une AUTRE couleur, en
  /// attente d'un 6 pour rentrer chez eux.
  final Map<Pawn, PlayerColor> _prisoners = {};

  void imprison(Pawn p, PlayerColor captor) => _prisoners[p] = captor;

  /// La couleur dont la boîte retient [p], ou `null` s'il est libre.
  PlayerColor? captorOf(Pawn p) => _prisoners[p];

  bool isPrisoner(Pawn p) => _prisoners.containsKey(p);

  /// Le 6 est tombé : le pion regagne SA propre boîte départ.
  void freePrisoner(Pawn p) => _prisoners.remove(p);

  // --- « Ne joue pas pendant 2 tours » ------------------------------------

  final Map<PlayerColor, int> _skips = {};

  /// [c] saute ses [turns] prochains tours. Remplace un décompte en cours
  /// plutôt que de s'y ajouter : aucun cumul, comme pour les autres effets.
  void setSkipTurns(PlayerColor c, int turns) => _skips[c] = turns;

  int skipsLeft(PlayerColor c) => _skips[c] ?? 0;

  /// Si [c] doit sauter son tour, en consomme un et renvoie `true`.
  bool consumeSkip(PlayerColor c) {
    final left = _skips[c] ?? 0;
    if (left <= 0) return false;
    if (left == 1) {
      _skips.remove(c);
    } else {
      _skips[c] = left - 1;
    }
    return true;
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

  /// Nouvelle partie : talons, mains, compteurs, états et annonces
  /// repartent de zéro. Les interrupteurs, eux, restent tels que
  /// l'utilisateur les a réglés.
  void resetForNewGame() {
    _immediate.reset();
    for (final d in _deferred.values) {
      d.reset();
    }
    for (final h in _hands.values) {
      h.clear();
    }
    _playedThisTurn.clear();
    _pawnMods.clear();
    _diceMods.clear();
    _mustLap.clear();
    _captureToBox.clear();
    _prisoners.clear();
    _skips.clear();
    _notices.clear();
    for (final c in PlayerColor.values) {
      _done[c] = 0;
    }
  }
}
