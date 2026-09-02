// Les AMÉLIORATIONS LudoPoly : cases Vortex et cases Chance.
//
// Tout ce module est ADDITIF : il ne modifie aucune règle du Ludo de base.
// Éteint (par défaut), il est invisible ; allumé, il n'agit qu'aux points
// de branchement explicites du moteur.
//
// GÉOMÉTRIE (verrouillée par test/upgrades_test.dart) :
//
//   * Cases VORTEX / TROU NOIR — DEUX cases par couleur, chacune à SA
//     couleur, et son propriétaire seul peut les utiliser : un pion
//     adverse qui s'y pose ne bouge pas. Chacune a sa propre règle.
//
//     LA BONNE — juste devant sa case de départ (départ + 1 pas), donc la
//     première case après la boîte départ. Le pion file sur la première
//     case de l'adversaire en diagonale, celle qui suit SA case de
//     départ : 26 pas gagnés.
//
//     LA MAUVAISE — la première case de sa dernière ligne droite, son 44e
//     pas. C'est là que le parcours prend son dernier segment rectiligne
//     (6 cases, pas 44 à 49), avant le virage du pas 50 qui ouvre sur le
//     couloir final. Sur la grille 15×15 du plateau :
//         vert 81 · jaune 99 · bleu 143 · rouge 125
//     — vérifiées par test/upgrades_test.dart. Le pion REVIENT à la
//     première case de la dernière ligne droite de l'adversaire en
//     diagonale : 26 pas perdus alors qu'il touchait au but.
//
//     Chaque case mène à son homologue d'en face. Aucun rebond possible :
//     cette case-là appartient à l'autre couleur.
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

  /// Indifféremment avant ou après le lancer.
  beforeOrAfterRoll,
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
  noExit,        // le pion désigné ne peut pas sortir de sa boîte
  captureToBox,  // règle spéciale appliquée à la prochaine capture
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

  /// Ce que la carte fait, en clair — §10 de la spec : « chaque carte doit
  /// avoir un identifiant unique, un nom, une description… ». C'est ce
  /// texte qui s'affiche en infobulle dans le bloc de cartes.
  final String descriptionFr;
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

  /// Nombre d'exemplaires de cette carte dans le paquet — §8 : « si
  /// plusieurs exemplaires d'une même carte sont souhaités, le système
  /// doit permettre de définir une quantité pour chaque carte ».
  final int quantity;

  const ChanceCard({
    required this.id,
    required this.nameFr,
    required this.nameEn,
    required this.nameEs,
    required this.descriptionFr,
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
    this.quantity = 1,
  });

  /// Vrai si le joueur doit DÉSIGNER une cible avant de jouer la carte.
  bool get needsTarget => selection == CardSelection.chosen;

  /// La carte peut-elle se jouer avant le lancer ?
  bool get playableBeforeRoll =>
      timing == ChanceTiming.beforeRoll ||
      timing == ChanceTiming.beforeOrAfterRoll;

  /// Et après ?
  bool get playableAfterRoll =>
      timing == ChanceTiming.afterRoll ||
      timing == ChanceTiming.beforeOrAfterRoll;

  /// Le moment, dit comme la spec l'écrit.
  String get timingLabelFr => switch (timing) {
        ChanceTiming.onChance => 'Immédiate',
        ChanceTiming.beforeRoll => 'AVANT',
        ChanceTiming.afterRoll => 'APRÈS',
        ChanceTiming.beforeOrAfterRoll => 'AVANT/APRÈS',
      };

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
    descriptionFr:
        'Le pion recule exactement de 3 cases, sans jamais franchir une zone qu\'il ne peut normalement pas franchir.',
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
    descriptionFr:
        'Le pion avance exactement de 3 cases, selon les règles normales du jeu.',
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
    descriptionFr:
        'Tous les pions du joueur encore dans sa boîte de départ sortent immédiatement. Les autres joueurs ne sont pas concernés.',
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
    descriptionFr:
        'Le pion est placé sur la case située immédiatement avant la sortie vers son couloir maison — jamais dans le couloir lui-même.',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.teleport,
  ),
  ChanceCard(
    id: 'IMM_PAWN_HOME',
    nameFr: 'Votre pion retourne dans sa boîte départ',
    nameEn: 'Your pawn goes back to its start box',
    nameEs: 'Tu ficha vuelve a su caja de salida',
    descriptionFr:
        'Le pion retourne dans sa boîte de départ. Il devra ensuite suivre les règles normales pour ressortir.',
    kind: CardKind.immediate,
    timing: ChanceTiming.onChance,
    action: CardAction.returnToBase,
  ),
  ChanceCard(
    id: 'IMM_PAWN_INVULNERABLE',
    nameFr: 'Pion invulnérable pendant 2 tours',
    nameEn: 'Invulnerable pawn for 2 turns',
    nameEs: 'Ficha invulnerable por 2 turnos',
    descriptionFr:
        'Pendant 2 tours, ce pion ne peut pas être capturé. L\'invulnérabilité disparaît ensuite d\'elle-même.',
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
    descriptionFr:
        'Ce pion ne peut pas être déplacé pendant 2 tours. Il redevient normal ensuite.',
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
    descriptionFr:
        'Le programme cherche le premier pion adverse devant, dans le sens du parcours ; le pion y avance et le capture.',
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
    descriptionFr:
        'Le programme cherche le premier pion adverse derrière ; le pion y recule et le capture.',
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
    descriptionFr:
        'À partir du tour suivant et pendant 2 tours, le dé ne peut produire que 1, 2 ou 3.',
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
    descriptionFr:
        'À partir du tour suivant et pendant 2 tours, le dé ne produit que des valeurs paires : 2, 4, 6, 8, 10 ou 12.',
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
    descriptionFr:
        'À partir du tour suivant et pendant 2 tours, le joueur lance 2 dés ; le résultat est leur somme, de 2 à 12.',
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
    nameFr: 'Votre pion invulnérable pendant 2 tours',
    nameEn: 'Your pawn invulnerable for 2 turns',
    nameEs: 'Tu ficha invulnerable por 2 turnos',
    descriptionFr:
        'Avant de lancer le dé, désignez un de vos pions : aucun adversaire ne peut le capturer pendant 2 tours.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setState,
    selection: CardSelection.chosen,
    pawnState: CardPawnState.invulnerable,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_OPPONENT_FROZEN',
    nameFr: 'Pion d\'un adversaire figé pendant 2 tours',
    nameEn: 'An opponent\'s pawn frozen for 2 turns',
    nameEs: 'Ficha de un rival congelada por 2 turnos',
    descriptionFr:
        'Avant de lancer le dé, désignez un pion adverse : il est immobilisé pendant 2 tours.',
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
    nameFr: 'Empêcher un pion adverse de sortir',
    nameEn: 'Stop an opponent\'s pawn from leaving its box',
    nameEs: 'Impide que una ficha rival salga de su caja',
    descriptionFr:
        'Désignez un pion adverse encore en boîte : à son tour, s\'il pouvait sortir, il ne sort pas et attend une prochaine occasion.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.noExit,
    scope: CardScope.opponent,
    selection: CardSelection.chosen,
  ),
  // ---- Concernant les dés : 6 cartes, de 1 à 6 ----
  ChanceCard(
    id: 'DEF_DICE_1',
    nameFr: 'Carte dé 1',
    nameEn: 'Dice card: 1',
    nameEs: 'Carta de dado: 1',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 1.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 1,
  ),
  ChanceCard(
    id: 'DEF_DICE_2',
    nameFr: 'Carte dé 2',
    nameEn: 'Dice card: 2',
    nameEs: 'Carta de dado: 2',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 2.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 2,
  ),
  ChanceCard(
    id: 'DEF_DICE_3',
    nameFr: 'Carte dé 3',
    nameEn: 'Dice card: 3',
    nameEs: 'Carta de dado: 3',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 3.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 3,
  ),
  ChanceCard(
    id: 'DEF_DICE_4',
    nameFr: 'Carte dé 4',
    nameEn: 'Dice card: 4',
    nameEs: 'Carta de dado: 4',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 4.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 4,
  ),
  ChanceCard(
    id: 'DEF_DICE_5',
    nameFr: 'Carte dé 5',
    nameEn: 'Dice card: 5',
    nameEs: 'Carta de dado: 5',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 5.',
    kind: CardKind.deferred,
    timing: ChanceTiming.beforeRoll,
    action: CardAction.setDice,
    entity: CardEntity.player,
    selection: CardSelection.none,
    value: 5,
  ),
  ChanceCard(
    id: 'DEF_DICE_6',
    nameFr: 'Carte dé 6',
    nameEn: 'Dice card: 6',
    nameEs: 'Carta de dado: 6',
    descriptionFr:
        'Jouée à la place du lancer : le résultat du dé est 6.',
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
    nameFr: 'Règle spéciale après capture',
    nameEn: 'Special rule after a capture',
    nameEs: 'Regla especial tras una captura',
    descriptionFr:
        'Après une capture : le pion capturé retourne dans la boîte de son propriétaire et devra obtenir un 6 pour ressortir.',
    kind: CardKind.deferred,
    timing: ChanceTiming.afterRoll,
    action: CardAction.captureToBox,
    entity: CardEntity.player,
    selection: CardSelection.none,
  ),
  // ---- Concernant les joueurs ----
  ChanceCard(
    id: 'DEF_SKIP_RIGHT',
    nameFr: 'Le joueur à votre droite ne joue pas pendant 2 tours',
    nameEn: 'The player on your right misses 2 turns',
    nameEs: 'El jugador a tu derecha pierde 2 turnos',
    descriptionFr:
        'Avant de lancer le dé : le joueur situé à votre droite ne joue pas pendant 2 tours, son tour est passé automatiquement.',
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
    nameFr: 'Le joueur de votre choix ne joue pas pendant 2 tours',
    nameEn: 'A player of your choice misses 2 turns',
    nameEs: 'El jugador que elijas pierde 2 turnos',
    descriptionFr:
        'Avant de lancer le dé : l\'adversaire de votre choix ne joue pas pendant 2 tours, son tour est passé automatiquement.',
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

  /// Pas auquel commence la dernière ligne droite d'une couleur. Le
  /// parcours file alors tout droit sur 6 cases (pas 44 à 49), tourne au
  /// pas 50, puis entre dans le couloir final. Ce n'est pas un réglage :
  /// c'est le dessin du plateau.
  static const int lastStraightStep = 44;

  /// La BONNE case d'une couleur : juste devant sa case de départ, donc
  /// la première case après sa boîte départ.
  static int goodVortexCell(PlayerColor c) => (startOf[c]! + 1) % ringSize;

  /// Cible de la bonne : la première case de l'adversaire en diagonale,
  /// celle qui suit SA case de départ — donc sa propre bonne case.
  static int goodVortexTarget(PlayerColor c) =>
      goodVortexCell(diagonalOf[c]!);

  /// La MAUVAISE case d'une couleur : la première case de sa dernière
  /// ligne droite (44e pas).
  static int badVortexCell(PlayerColor c) =>
      (startOf[c]! + lastStraightStep) % ringSize;

  /// Cible de la mauvaise : la première case de la dernière ligne droite
  /// de l'adversaire en diagonale — donc son propre trou noir.
  static int badVortexTarget(PlayerColor c) =>
      badVortexCell(diagonalOf[c]!);

  /// Les deux cases spéciales d'une couleur, dans l'ordre du parcours.
  static List<int> vortexCellsOf(PlayerColor c) =>
      [goodVortexCell(c), badVortexCell(c)];

  /// Les 4 cases Chance : 2 cases avant chaque étoile (départ + 6).
  static const Set<int> chanceCells = {6, 19, 32, 45};

  /// La case Chance du bras de [c] : celle qui se trouve 6 pas après son
  /// départ. Il y en a une par couleur, et c'est elle qui porte sa teinte.
  static int chanceCellOf(PlayerColor c) => (startOf[c]! + 6) % ringSize;
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

  /// Tours à laisser passer avant que l'effet ne morde. Zéro pour un
  /// effet qui prend tout de suite ; un quand le pion vient justement de
  /// jouer et que ce tour-ci est déjà consommé.
  final int startsIn;
  const _PawnMod(this.state, this.sinceDone, this.startsIn);
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
      // STATUS : une carte INACTIVE est sautée, comme si elle n'existait
      // pas. Et chaque carte entre dans le paquet en autant d'exemplaires
      // que le dit sa `quantity` (§8).
      for (final c in _source) {
        if (!c.active) continue;
        for (int i = 0; i < c.quantity; i++) {
          _cards.add(c);
        }
      }
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

  /// Nombre maximum de cartes différées tenues en main — §3 : « il peut
  /// avoir au maximum 4 cartes différées disponibles », et §9 interdit
  /// « plus de 4 cartes différées dans la main d'un joueur ». Une carte
  /// tirée alors que la main est pleine est perdue — voir [addToHand].
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
  /// pleine : il n'y a de la place que pour [handLimit] cartes différées,
  /// la carte tirée en trop est perdue.
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
    // Une carte « règle après capture » non utilisée pendant le tour où
    // elle a été jouée est perdue.
    _captureRule.remove(c);
  }

  int doneTurns(PlayerColor c) => _done[c]!;

  // --- États de pion (invulnérable / figé) --------------------------------

  final Map<Pawn, _PawnMod> _pawnMods = {};

  /// Pose [state] sur [p]. REMPLACE l'état précédent : retirer une seconde
  /// carte « invulnérable » repart pour 2 tours, sans cumul.
  ///
  /// [startsIn] décale le début de la fenêtre. Il vaut 1 dans un seul
  /// cas : le GEL posé par une carte immédiate. Le pion vient alors de
  /// jouer pour atterrir sur la case Chance ; le figer séance tenante ne
  /// lui coûterait qu'UN tour jouable au lieu des deux annoncés.
  void setPawnState(Pawn p, CardPawnState state, {int startsIn = 0}) =>
      _pawnMods[p] = _PawnMod(state, _done[p.color]!, startsIn);

  bool _hasState(Pawn p, CardPawnState s) {
    final mod = _pawnMods[p];
    if (mod == null || mod.state != s) return false;
    // Deux tours du propriétaire, à compter du début de la fenêtre.
    final d = _done[p.color]! - mod.sinceDone;
    return d >= mod.startsIn && d < mod.startsIn + 2;
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

  // --- Carte 15 : « empêcher un pion adverse de SORTIR de sa boîte » ------

  final Set<Pawn> _noExit = {};

  void markNoExit(Pawn p) => _noExit.add(p);

  /// Vrai tant que [p] n'a pas laissé passer son occasion de sortir.
  bool cannotExit(Pawn p) => _noExit.contains(p);

  /// L'occasion s'est présentée et le pion l'a laissée passer : la marque
  /// est consommée. « Il doit rester dans sa boîte et attendre une
  /// prochaine possibilité de sortie » — celle-là, il l'aura.
  void clearNoExit(Pawn p) => _noExit.remove(p);

  /// Consomme la marque de tous les pions de [c] : leur occasion de sortir
  /// vient de passer. Renvoie ceux qui étaient marqués, pour l'annonce.
  List<Pawn> consumeNoExitFor(PlayerColor c) {
    final missed = _noExit.where((p) => p.color == c).toList();
    _noExit.removeAll(missed);
    return missed;
  }

  // --- Carte 22 : la règle spéciale après capture -------------------------
  //
  // Telle que la spec la décrit désormais, la carte ne déplace PAS la
  // victime chez le captureur : « le pion capturé retourne dans la boîte
  // de départ de son propriétaire » et « doit obtenir un 6 » pour
  // ressortir. C'est déjà le sort d'un pion capturé au Ludo ; la carte se
  // contente donc de l'appliquer explicitement à la capture qui suit.
  //
  // Le mécanisme de PRISONNIER retenu dans la boîte de l'adversaire, qui
  // vivait ici, a été RETIRÉ : il ne figure plus dans la spec.

  final Set<PlayerColor> _captureRule = {};

  /// Arme la carte pour [c] : sa prochaine capture de ce tour appliquera
  /// explicitement la règle.
  void armCaptureRule(PlayerColor c) => _captureRule.add(c);

  bool captureRuleArmed(PlayerColor c) => _captureRule.contains(c);

  /// Consomme l'armement s'il existe. Renvoie `true` s'il a servi.
  bool consumeCaptureRule(PlayerColor c) => _captureRule.remove(c);

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

  // --- La dernière carte TIRÉE, pour que l'interface l'ouvre --------------

  ChanceCard? _lastDrawn;
  PlayerColor? _lastDrawnBy;

  /// Retenue au tirage : l'interface la retire pour la montrer face
  /// visible, puis elle est oubliée.
  void noteDrawn(ChanceCard card, PlayerColor by) {
    _lastDrawn = card;
    _lastDrawnBy = by;
  }

  /// Rend la carte tirée depuis le dernier appel, et l'oublie. `null` si
  /// aucune carte n'a été tirée entre-temps.
  ({ChanceCard card, PlayerColor by})? takeLastDrawn() {
    final c = _lastDrawn;
    final by = _lastDrawnBy;
    _lastDrawn = null;
    _lastDrawnBy = null;
    return (c == null || by == null) ? null : (card: c, by: by);
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
    _noExit.clear();
    _captureRule.clear();
    _lastDrawn = null;
    _lastDrawnBy = null;
    _skips.clear();
    _notices.clear();
    for (final c in PlayerColor.values) {
      _done[c] = 0;
    }
  }
}
