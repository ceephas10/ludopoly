// Le moteur du gameplay — premier jet : le Ludo standard, piloté par le JSON.
//
// Ce qu'il fait : la sortie de base sur un 6, le déplacement sur l'anneau
// (la valeur vient du dernier dé, les virages des cases à `vector`), la
// capture, et les tours (un 6 ou une capture redonnent la main, trois 6
// d'affilée font perdre le tour).
//
// La SORTIE DU RING : un pion n'entre pas dans son couloir en foulant une
// case précise, mais en DÉPASSANT la dernière case d'anneau de sa couleur.
// Ce qui compte est donc la distance qu'il lui reste à couvrir, calculée au
// modulo — c'est elle qui rend la formule juste pour les quatre couleurs,
// y compris le rouge dont le parcours enjambe le zéro. Dans le couloir, le
// déplacement devient une addition sans modulo, et il faut le JET EXACT
// pour atteindre le centre.
//
// Ce qu'il ne fait PAS encore, parce que le JSON ne le dit pas : l'effet des
// cases `vortex`, `death` et `luck` (elles sont reconnues et signalées, rien
// de plus), et l'effet des statuts `doubleDice` / `halfDice`. Seul
// `invincible` agit : un pion invincible ne se fait pas capturer.

import 'dart:math' as math;

import 'spec.dart';
import 'token.dart';

enum Phase { rolling, moving }

enum EventType {
  exited,
  moved,
  enteredExit,
  home,
  won,
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
    this.exitRank,
  });

  final Token token;
  final int moveValue;

  /// Les cases d'ANNEAU traversées, arrivée comprise. Une sortie de base =
  /// `[start]`. Vide si le pion était déjà dans son couloir.
  final List<int> path;

  /// Rotation cumulée pendant ce déplacement, en degrés (mod 360).
  final int vectorAngle;

  /// Rang atteint dans le couloir (à partir de 1), ou `null` si le pion
  /// reste sur l'anneau.
  final int? exitRank;

  /// Ce coup fait basculer le pion hors de l'anneau.
  bool get entersExit => exitRank != null;

  /// Ce coup amène le pion au centre : il est sorti.
  bool get reachesHome => exitRank == BoardSpec.exitGoal;

  /// La dernière case d'ANNEAU foulée. N'a de sens que si [entersExit] est
  /// faux — sinon l'arrivée est [exitRank].
  int get destination => path.isEmpty ? token.ringIndex : path.last;
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
      final exit = spec.exitIndexOf(p);
      tokens[p] = [
        for (var i = 0; i < tokensPerColor; i++)
          Token(color: p, colorIndex: i, exitIndex: exit),
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

  /// Les couleurs qui ont rentré tous leurs pions, dans l'ordre d'arrivée.
  final List<TokenColor> winners = [];

  /// Les pions posés sur la case [cell]. Un pion du couloir n'y figure
  /// PAS : son `ringIndex` désigne un rang, pas une case — sans ce filtre,
  /// un pion au rang 2 se ferait capturer par un adversaire arrivant sur
  /// la case 2 de l'anneau.
  List<Token> tokensAt(int cell) =>
      [for (final t in allTokens) if (t.onRingPath && t.ringIndex == cell) t];

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

  /// Le coup que [t] jouerait avec [dice], ou `null` s'il est illégal — le
  /// pion ne bougerait alors pas. C'est l'UNIQUE endroit où le déplacement
  /// est décidé : [canMove] et [preview] s'y ramènent tous les deux.
  Move? _plan(Token t, int dice) {
    if (t.isHome) return null;

    // En base : il faut un 6, et on sort sur sa case de départ.
    if (t.inBase) {
      if (dice != 6) return null;
      final start = spec.startOf[t.color]!;
      return Move(
        token: t,
        moveValue: dice,
        path: [start],
        vectorAngle: spec.cell(start).vector % 360,
      );
    }

    // Déjà dans le couloir : simple addition, sans modulo. Dépasser le
    // centre est illégal — c'est le jet exact.
    if (t.inExit) {
      final target = t.ringIndex + dice;
      if (target > BoardSpec.exitGoal) return null;
      return Move(
        token: t,
        moveValue: dice,
        path: const [],
        vectorAngle: 0,
        exitRank: target,
      );
    }

    // Sur l'anneau : ce qui compte est la distance restante jusqu'à sa
    // dernière case, PAS la comparaison directe des index. Sans ce modulo,
    // un pion rouge fraîchement sorti sur sa case 13 avec un dé de 4
    // donnerait 17 > 11 et filerait au couloir sans avoir fait un tour.
    final remaining = (t.exitIndex - t.ringIndex + spec.size) % spec.size;
    final steps = dice <= remaining ? dice : remaining;
    final path = <int>[];
    var angle = 0;
    var cell = t.ringIndex;
    for (var i = 0; i < steps; i++) {
      cell = spec.next(cell);
      path.add(cell);
      angle = (angle + spec.cell(cell).vector) % 360;
    }
    if (dice <= remaining) {
      return Move(token: t, moveValue: dice, path: path, vectorAngle: angle);
    }
    final rank = dice - remaining;
    if (rank > BoardSpec.exitGoal) return null; // dépassement du but
    return Move(
      token: t,
      moveValue: dice,
      path: path,
      vectorAngle: angle,
      exitRank: rank,
    );
  }

  /// [t] peut-il jouer le dernier dé ?
  bool canMove(Token t) {
    if (t.color != currentPlayer) return false;
    return _plan(t, lastDice) != null;
  }

  List<Token> movableTokens() =>
      [for (final t in tokens[currentPlayer]!) if (canMove(t)) t];

  /// Le déplacement que jouerait [t], sans l'appliquer.
  Move preview(Token t) {
    final m = _plan(t, lastDice);
    if (m == null) throw StateError('${t.name} ne peut pas jouer $lastDice');
    return m;
  }

  /// Joue [t] avec le dernier dé, puis applique la capture et la règle du
  /// tour.
  List<GameEvent> play(Token t) {
    if (phase != Phase.moving) throw StateError('il faut lancer le dé d\'abord');
    if (!canMove(t)) throw StateError('${t.name} ne peut pas jouer');

    final mv = preview(t);
    final out = <GameEvent>[];
    final wasInBase = t.inBase;
    var captured = false;

    if (mv.entersExit) {
      t.enterExit(mv.exitRank!);
      out.add(GameEvent(EventType.enteredExit,
          token: t, reason: 'couloir, rang ${mv.exitRank}'));
      if (t.isHome) out.add(GameEvent(EventType.home, token: t));
    } else {
      t.enterRing(mv.destination);
      out.add(GameEvent(
        wasInBase ? EventType.exited : EventType.moved,
        token: t,
        cell: mv.destination,
      ));
      captured = _capture(t, out);

      final cell = spec.cell(t.ringIndex);
      if (cell.action != CellAction.move) {
        // Reconnue, pas appliquée : le JSON ne dit pas ce qu'elle fait.
        out.add(GameEvent(EventType.specialCell,
            token: t, cell: cell.id, action: cell.action));
      }
    }

    // Victoire : les quatre pions d'une couleur sont sortis.
    if (!winners.contains(t.color) &&
        tokens[t.color]!.every((x) => x.isHome)) {
      winners.add(t.color);
      out.add(GameEvent(EventType.won,
          token: t,
          reason: '${t.color.name} a sorti ses $tokensPerColor pions'));
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
  /// sauf s'il est invincible, et sauf s'il tient un BLOC.
  ///
  /// Le bloc : deux pions d'une même couleur sur une même case. Un
  /// adversaire seul qui s'y pose ne les mange pas, il partage la case ;
  /// il faut qu'il y amène un deuxième pion de sa couleur. Un pion isolé,
  /// lui, se mange comme avant. Même règle que `game_controller.dart`.
  ///
  /// Renvoie `true` si au moins un pion est parti.
  bool _capture(Token mover, List<GameEvent> out) {
    final cell = spec.cell(mover.ringIndex);
    if (cell.safe) return false;
    final here = tokensAt(mover.ringIndex).toList();
    final mine = here.where((t) => t.color == mover.color).length;
    var any = false;
    for (final v in here) {
      if (v.color == mover.color) continue;
      if (v.status == TokenStatus.invincible) continue;
      final theirs = here.where((t) => t.color == v.color).length;
      if (theirs >= 2 && mine < 2) continue;
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
