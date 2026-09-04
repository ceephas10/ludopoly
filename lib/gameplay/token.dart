// Le `token` du JSON : color, colorIndex, ringIndex, inExit, exitIndex,
// status, statusCount.

import 'spec.dart';

/// Où se trouve un pion. Le JSON ne connaît que `ringIndex` ; mais la base
/// et la sortie sur 6 sont conservées, donc un pion doit pouvoir être « pas
/// encore sur l'anneau ». Le couloir final, lui, ne se lit pas ici mais dans
/// [Token.inExit] : c'est le drapeau qui change le SENS de `ringIndex`.
enum TokenPlace { base, ring }

class Token {
  Token({
    required this.color,
    required this.colorIndex,
    required this.exitIndex,
  });

  final TokenColor color;

  /// Rang du pion dans sa couleur (0..3).
  final int colorIndex;

  /// La dernière case d'anneau de sa couleur : bleu 50, rouge 11, vert 24,
  /// jaune 37. Pivot du calcul de sortie — le pion n'entre pas dans son
  /// couloir en s'y posant, mais en la DÉPASSANT.
  final int exitIndex;

  TokenPlace place = TokenPlace.base;

  /// Case de l'anneau tant que [inExit] est faux ; rang dans le couloir
  /// (à partir de 1) une fois [inExit] vrai.
  int ringIndex = 0;

  /// Le pion a quitté l'anneau et progresse dans son couloir.
  bool inExit = false;

  TokenStatus status = TokenStatus.normal;

  /// Tours du propriétaire pendant lesquels [status] tient encore.
  int statusCount = 0;

  bool get inBase => place == TokenPlace.base;
  bool get onRing => place == TokenPlace.ring;

  /// Le pion occupe une case de l'anneau — donc capturable, et comptant
  /// dans [GameplayEngine.tokensAt]. Un pion du couloir n'y est plus :
  /// son `ringIndex` désigne un rang, pas une case.
  bool get onRingPath => onRing && !inExit;

  /// Sorti : arrivé au centre. Il ne joue plus.
  bool get isHome => inExit && ringIndex >= BoardSpec.exitGoal;

  void enterRing(int cell) {
    place = TokenPlace.ring;
    ringIndex = cell;
    inExit = false;
  }

  /// Bascule dans le couloir, au rang [rank] (1 = première case).
  void enterExit(int rank) {
    place = TokenPlace.ring;
    inExit = true;
    ringIndex = rank;
  }

  void returnToBase() {
    place = TokenPlace.base;
    ringIndex = 0;
    inExit = false;
  }

  /// Donne [s] pour [turns] tours du propriétaire.
  void setStatus(TokenStatus s, {required int turns}) {
    status = s;
    statusCount = s == TokenStatus.normal ? 0 : turns;
  }

  /// Fin d'un tour du propriétaire : le compteur descend, et le statut
  /// expire quand il touche zéro.
  void tickStatus() {
    if (status == TokenStatus.normal) return;
    if (statusCount > 0) statusCount--;
    if (statusCount == 0) status = TokenStatus.normal;
  }

  /// `blue1` … `blue4`.
  String get name => '${color.name}${colorIndex + 1}';

  @override
  String toString() {
    final where = inBase
        ? '(base)'
        : inExit
            ? (isHome ? '(maison)' : '(couloir $ringIndex)')
            : '@$ringIndex';
    final st = status == TokenStatus.normal
        ? ''
        : ' ${status.name}×$statusCount';
    return '$name$where$st';
  }
}
