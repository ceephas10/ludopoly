// Le `token` du JSON : color, colorIndex, ringIndex, status, statusCount.

import 'spec.dart';

/// Où se trouve un pion. Le JSON ne connaît que `ringIndex` ; mais la base
/// et la sortie sur 6 sont conservées, donc un pion doit pouvoir être « pas
/// encore sur l'anneau ». Le couloir final n'existe pas encore : quand il
/// viendra, il s'ajoutera ici.
enum TokenPlace { base, ring }

class Token {
  Token({required this.color, required this.colorIndex});

  final TokenColor color;

  /// Rang du pion dans sa couleur (0..3).
  final int colorIndex;

  TokenPlace place = TokenPlace.base;

  /// Position sur l'anneau ; n'a de sens que si [place] est [TokenPlace.ring].
  int ringIndex = 0;

  TokenStatus status = TokenStatus.normal;

  /// Tours du propriétaire pendant lesquels [status] tient encore.
  int statusCount = 0;

  bool get inBase => place == TokenPlace.base;
  bool get onRing => place == TokenPlace.ring;

  void enterRing(int cell) {
    place = TokenPlace.ring;
    ringIndex = cell;
  }

  void returnToBase() {
    place = TokenPlace.base;
    ringIndex = 0;
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
  String toString() =>
      inBase ? '$name(base)' : '$name@$ringIndex${status == TokenStatus.normal ? '' : ' ${status.name}×$statusCount'}';
}
