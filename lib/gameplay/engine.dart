// Le moteur du gameplay — premier jet : le Ludo standard, piloté par le JSON.
//
// Ce qu'il fait : la sortie de base sur un 6, le déplacement sur l'anneau
// (la valeur vient du dernier dé, les virages des cases à `vector`), la
// capture, et les tours (un 6 ou une capture redonnent la main, trois 6
// d'affilée font perdre le tour).
//
// Ce qu'il ne fait PAS encore, parce que le JSON ne le dit pas : l'effet des
// cases `vortex`, `death`, `luck` et `moveExit` (elles sont reconnues et
// signalées, rien de plus), le couloir final, la victoire, et l'effet des
// statuts `doubleDice` / `halfDice`. Seul `invincible` agit : un pion
// invincible ne se fait pas capturer.

import 'dart:math' as math;

import 'spec.dart';
import 'token.dart';

enum Phase { rolling, moving }

enum EventType {
  exited,
  moved,
  captured,
  specialCell,
  extraTurn,
  turnPassed,
  threeSixes,
  noMove,
}

/// Ce qui vient de se passer. Le journal du moteur, et ce que l'interface
/// devra animer.
class GameEvent {
  const GameEvent(
    this.type, {
    this.token,
    this.victim,
    this.cell,
    this.action,
    this.reason,
  });

  final EventType type;
  final Token? token;
  final Token? victim;
  final int? cell;
  final CellAction? action;
  final String? reason;

  @override
  String toString() => [
        type.name,
        if (token != null) token!.name,
        if (victim != null) '→ ${victim!.name}',
        if (cell != null) 'case $cell',
        if (action != null) action!.name,
        if (reason != null) '($reason)',
      ].join(' ');
}

/// Le `move` du JSON : la valeur vient du dernier dé (`source: lastDice`),
/// et `vectorAngle` cumule les virages pris (`vector: 90`) sur le chemin.
class Move {
  const Move({
    required this.token,
    required this.moveValue,
    required this.path,
    required this.vectorAngle,
  });

  final Token token;
  final int moveValue;

  /// Les cases traversées, arrivée comprise. Une sortie de base = `[start]`.
  final List<int> path;

  /// Rotation cumulée pendant ce déplacement, en degrés (mod 360).
  final int vectorAngle;

  int get destination => path.last;
}

class GameplayEngine {
  GameplayEngine(
    this.spec, {
    List<TokenColor>? players,
    math.Random? rng,
    this.tokensPerColor = 4,
  })  : players = players ?? spec.colors,
        _rng = rng ?? math.Random() {
    if (this.players.length < 2) {
      throw ArgumentError('il faut au moins 2 joueurs');
    }
    for (final p in this.players) {
      if (!spec.startOf.containsKey(p)) {
        throw ArgumentError('${p.name} n\'a pas de case de départ dans le JSON');
      }
      tokens[p] = [
        for (var i = 0; i < tokensPerColor; i++)
          Token(color: p, colorIndex: i),
      ];
    }
  }

  final BoardSpec spec;

  /// Les joueurs, dans l'ordre des tours.
  final List<TokenColor> players;
  final int tokensPerColor;
  final math.Random _rng;
  final Map<TokenColor, List<Token>> tokens = {};

  /// Tout ce qui s'est passé depuis le début de la partie.
  final List<GameEvent> log = [];

  int _current = 0;
  TokenColor get currentPlayer => players[_current];
  Phase phase = Phase.rolling;
  int lastDice = 0;
  int consecutiveSixes = 0;

  Iterable<Token> get allTokens => tokens.values.expand((l) => l);

  /// Les pions posés sur la case [cell].
  List<Token> tokensAt(int cell) =>
      [for (final t in allTokens) if (t.onRing && t.ringIndex == cell) t];

  // --- le tour -------------------------------------------------------------

  /// Lance le dé — ou impose [value], pour les tests et le jeu manuel.
  /// Termine le tour de lui-même si aucun coup n'est possible, ou au
  /// troisième 6 d'affilée.
  List<GameEvent> roll([int? value]) {
    if (phase != Phase.rolling) {
      throw StateError('ce n\'est pas le moment de lancer le dé');
    }
    final v = value ?? _rng.nextInt(6) + 1;
    if (v < 1 || v > 6) throw ArgumentError('dé hors de 1..6 : $v');
    lastDice = v;

    final out = <GameEvent>[];
    if (v == 6) {
      consecutiveSixes++;
      if (consecutiveSixes >= 3) {
        out.add(const GameEvent(EventType.threeSixes,
            reason: 'troisième 6 d\'affilée : le tour est perdu'));
        out.addAll(_endTurn());
        return _emit(out);
      }
    } else {
      consecutiveSixes = 0;
    }

    if (movableTokens().isEmpty) {
      out.add(GameEvent(EventType.noMove, reason: 'aucun pion ne peut jouer $v'));
      out.addAll(_endTurn());
      return _emit(out);
    }
    phase = Phase.moving;
    return _emit(out);
  }

  /// [t] peut-il jouer le dernier dé ? En base, il faut un 6. Sur l'anneau,
  /// on avance toujours : il n'y a pas encore de couloir final.
  bool canMove(Token t) {
    if (t.color != currentPlayer) return false;
    if (t.inBase) return lastDice == 6;
    return true;
  }

  List<Token> movableTokens() =>
      [for (final t in tokens[currentPlayer]!) if (canMove(t)) t];

  /// Le déplacement que jouerait [t], sans l'appliquer.
  Move preview(Token t) {
    if (t.inBase) {
      final start = spec.startOf[t.color]!;
      return Move(
        token: t,
        moveValue: lastDice,
        path: [start],
        vectorAngle: spec.cell(start).vector % 360,
      );
    }
    final path = <int>[];
    var angle = 0;
    var cell = t.ringIndex;
    for (var i = 0; i < lastDice; i++) {
      cell = spec.next(cell);
      path.add(cell);
      angle = (angle + spec.cell(cell).vector) % 360;
    }
    return Move(token: t, moveValue: lastDice, path: path, vectorAngle: angle);
  }

  /// Joue [t] avec le dernier dé, puis applique la capture et la règle du
  /// tour.
  List<GameEvent> play(Token t) {
    if (phase != Phase.moving) throw StateError('il faut lancer le dé d\'abord');
    if (!canMove(t)) throw StateError('${t.name} ne peut pas jouer');

    final mv = preview(t);
    final out = <GameEvent>[];
    final wasInBase = t.inBase;
    t.enterRing(mv.destination);
    out.add(GameEvent(
      wasInBase ? EventType.exited : EventType.moved,
      token: t,
      cell: mv.destination,
    ));

    final captured = _capture(t, out);

    final cell = spec.cell(t.ringIndex);
    if (cell.action != CellAction.move) {
      // Reconnue, pas appliquée : le JSON ne dit pas ce qu'elle fait.
      out.add(GameEvent(EventType.specialCell,
          token: t, cell: cell.id, action: cell.action));
    }

    if (lastDice == 6 || captured) {
      out.add(GameEvent(EventType.extraTurn,
          token: t, reason: lastDice == 6 ? 'un 6' : 'une capture'));
      phase = Phase.rolling;
    } else {
      out.addAll(_endTurn());
    }
    return _emit(out);
  }

  // --- capture --------------------------------------------------------------

  /// Sur une case non sûre, tout pion adverse présent retourne dans sa base —
  /// sauf s'il est invincible. Renvoie `true` si au moins un est parti.
  bool _capture(Token mover, List<GameEvent> out) {
    final cell = spec.cell(mover.ringIndex);
    if (cell.safe) return false;
    var any = false;
    for (final v in tokensAt(mover.ringIndex)) {
      if (v.color == mover.color) continue;
      if (v.status == TokenStatus.invincible) continue;
      v.returnToBase();
      out.add(GameEvent(EventType.captured, token: mover, victim: v, cell: cell.id));
      any = true;
    }
    return any;
  }

  // --- fin de tour ----------------------------------------------------------

  List<GameEvent> _endTurn() {
    for (final t in tokens[currentPlayer]!) {
      t.tickStatus();
    }
    final from = currentPlayer;
    consecutiveSixes = 0;
    _current = (_current + 1) % players.length;
    phase = Phase.rolling;
    return [
      GameEvent(EventType.turnPassed, reason: '${from.name} → ${currentPlayer.name}'),
    ];
  }

  List<GameEvent> _emit(List<GameEvent> events) {
    log.addAll(events);
    return events;
  }
}
