// CHAQUE CARTE FAIT VRAIMENT CE QU'ELLE DIT.
//
// Une carte n'est pas un texte : c'est une instruction. « Touchez le pion
// de votre adversaire, il ne peut plus bouger » doit se traduire par un
// pion qui, à l'écran comme dans le moteur, ne bouge plus. Ce fichier
// vérifie les 24 cartes une par une — les 12 immédiates (A à L) et les 12
// différées (1 à 12) — et refuse celles qui ne changeraient rien.
//
// Chaque test est nommé par le CODE de la carte : quand il casse, on sait
// immédiatement laquelle est en cause.
//
// Deux surfaces à couvrir, et le test dit laquelle :
//   * LE PION  — position, boîte, gel, protection, interdiction de sortir.
//   * LE DÉ    — valeur imposée, bridée, doublée, ou tirée en deux dés.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/game/upgrades.dart';

GameController newGame() => GameController(
      turnOrder: const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ],
      state: GameState.initial(),
    );

/// Pose [p] sur l'anneau, [steps] pas après SA case de départ.
void put(Pawn p, int steps) {
  p.location = PawnLocation.ring;
  p.position = (GameController.startIdx(p.color) + steps) %
      GameController.ringSize;
}

int stepsOf(Pawn p) =>
    (p.position - GameController.startIdx(p.color) + GameController.ringSize) %
        GameController.ringSize;

ChanceCard imm(String code) =>
    kImmediateCards.singleWhere((c) => cardCode(c) == code);

ChanceCard def(String code) =>
    kDeferredCards.singleWhere((c) => cardCode(c) == code);

/// Fait passer [c] tours complets à la couleur courante, pour ouvrir les
/// fenêtres « pendant 2 tours » qui ne s'ouvrent qu'au tour suivant.
void endTurns(GameController g, PlayerColor color, int n) {
  for (var i = 0; i < n; i++) {
    g.upgrades.onTurnCompleted(color);
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  //  LES 12 IMMÉDIATES — A à L
  // ══════════════════════════════════════════════════════════════════════
  group('Cartes IMMÉDIATES : l\'effet tombe sur le pion, tout de suite', () {
    test('A — « Reculez de 3 cases » : le pion RECULE de 3', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('A'), p);
      expect(stepsOf(p), 7, reason: 'le pion doit avoir reculé de 3 pas');
    });

    test('B — « Avancez de 3 cases » : le pion AVANCE de 3', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('B'), p);
      expect(stepsOf(p), 13);
    });

    test('C — « Tous vos pions sortent » : la boîte se VIDE', () {
      final g = newGame();
      final mine = g.state.pawnsByColor[PlayerColor.blue]!;
      expect(mine.every((x) => x.location == PawnLocation.base), isTrue);
      g.applyImmediateCard(imm('C'), mine[0]);
      expect(mine.every((x) => x.location == PawnLocation.ring), isTrue,
          reason: 'les quatre pions doivent être sortis');
      expect(mine.every((x) => stepsOf(x) == 0), isTrue,
          reason: 'et posés sur leur case de départ');
    });

    test('D — « Juste devant la sortie » : le pion saute au 50e pas', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 4);
      g.applyImmediateCard(imm('D'), p);
      expect(stepsOf(p), GameController.lastRingStep);
    });

    test('E — « Retour dans la boîte » : le pion QUITTE l\'anneau', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 20);
      g.applyImmediateCard(imm('E'), p);
      expect(p.location, PawnLocation.base);
    });

    test('F — « Invulnérable » : le pion ne peut plus être MANGÉ', () {
      final g = newGame();
      final me = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(me, 20);
      g.applyImmediateCard(imm('F'), me);
      expect(g.upgrades.isInvulnerable(me), isTrue);

      // Et l'effet mord vraiment : un adversaire qui tombe dessus ne le
      // renvoie pas dans sa boîte.
      final foe = g.state.pawnsByColor[PlayerColor.red]![0];
      put(foe, (me.position - GameController.startIdx(PlayerColor.red) +
              GameController.ringSize - 2) %
          GameController.ringSize);
      g.currentPlayerIdx = g.turnOrder.indexOf(PlayerColor.red);
      g.phase = TurnPhase.rolling;
      g.roll(2);
      g.movePawn(foe);
      expect(me.location, PawnLocation.ring,
          reason: 'un pion invulnérable ne rentre pas à la boîte');
    });

    test('G — « Figé » : au tour suivant le pion NE BOUGE PLUS', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('G'), p);

      // Le gel ne mord qu'au tour SUIVANT : celui-ci est déjà dépensé.
      endTurns(g, PlayerColor.blue, 1);
      expect(g.upgrades.isFrozen(p), isTrue);

      g.currentPlayerIdx = g.turnOrder.indexOf(PlayerColor.blue);
      g.phase = TurnPhase.rolling;
      g.roll(3);
      expect(g.movablePawns().contains(p), isFalse,
          reason: 'un pion figé ne figure pas parmi les coups possibles');
    });

    test('H — « Capturez devant » : l\'adversaire devant RENTRE', () {
      final g = newGame();
      final me = g.state.pawnsByColor[PlayerColor.blue]![0];
      final foe = g.state.pawnsByColor[PlayerColor.red]![0];
      put(me, 10);
      foe.location = PawnLocation.ring;
      foe.position = (me.position + 4) % GameController.ringSize;
      g.applyImmediateCard(imm('H'), me);
      expect(foe.location, PawnLocation.base,
          reason: 'le pion rattrapé retourne dans sa boîte');
      expect(me.position, (GameController.startIdx(PlayerColor.blue) + 14) %
          GameController.ringSize,
          reason: 'et le mien prend sa place');
    });

    test('I — « Capturez derrière » : l\'adversaire derrière RENTRE', () {
      final g = newGame();
      final me = g.state.pawnsByColor[PlayerColor.blue]![0];
      final foe = g.state.pawnsByColor[PlayerColor.red]![0];
      put(me, 10);
      foe.location = PawnLocation.ring;
      foe.position = (me.position - 3 + GameController.ringSize) %
          GameController.ringSize;
      g.applyImmediateCard(imm('I'), me);
      expect(foe.location, PawnLocation.base);
      expect(stepsOf(me), 7, reason: 'mon pion recule sur la case prise');
    });

    // ── LE DÉ ────────────────────────────────────────────────────────────
    test('J — « Demi-dé » : le dé ne sort plus que 1, 2 ou 3', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('J'), p);
      endTurns(g, PlayerColor.blue, 1); // « à partir du tour suivant »
      expect(g.upgrades.activeDiceMode(PlayerColor.blue),
          CardDiceMode.limit);

      for (var i = 0; i < 40; i++) {
        expect(g.pickDiceValueFor(PlayerColor.blue, math.Random(i)), inInclusiveRange(1, 3));
      }
    });

    test('K — « Double-dé » : le dé rend le double, 2 à 12 pairs', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('K'), p);
      endTurns(g, PlayerColor.blue, 1);
      expect(g.upgrades.activeDiceMode(PlayerColor.blue),
          CardDiceMode.double);

      for (var i = 0; i < 40; i++) {
        final v = g.pickDiceValueFor(PlayerColor.blue, math.Random(i));
        expect(v.isEven, isTrue, reason: 'un double est toujours pair');
        expect(v, inInclusiveRange(2, 12));
      }
    });

    test('L — « Deux dés » : deux tirages, et leur SOMME est jouée', () {
      final g = newGame();
      final p = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(p, 10);
      g.applyImmediateCard(imm('L'), p);
      endTurns(g, PlayerColor.blue, 1);
      expect(g.upgrades.activeDiceMode(PlayerColor.blue),
          CardDiceMode.twoDice);

      for (var i = 0; i < 40; i++) {
        final v = g.pickDiceValueFor(PlayerColor.blue, math.Random(i));
        final two = g.upgrades.lastTwoDice;
        expect(two, isNotNull, reason: 'les deux dés doivent être montrés');
        expect(two!.a + two.b, v, reason: 'la somme est ce qui se joue');
        expect(v, inInclusiveRange(2, 12));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  LES 12 DIFFÉRÉES — 1 à 12
  // ══════════════════════════════════════════════════════════════════════
  group('Cartes DIFFÉRÉES : jouées à la main, l\'effet tombe pareil', () {
    /// Met [card] dans la main de bleu et ouvre son tour dans la phase
    /// où la carte est jouable.
    GameController armed(ChanceCard card, {bool afterRoll = false}) {
      final g = newGame();
      g.upgrades.addToHand(PlayerColor.blue, card);
      g.currentPlayerIdx = g.turnOrder.indexOf(PlayerColor.blue);
      g.phase = afterRoll ? TurnPhase.moving : TurnPhase.rolling;
      return g;
    }

    test('1 — « Mon pion invulnérable » : la protection est POSÉE', () {
      final c = def('1');
      final g = armed(c);
      final mine = g.state.pawnsByColor[PlayerColor.blue]![0];
      put(mine, 8);
      expect(g.deferredPawnTargets(PlayerColor.blue, c), contains(mine));
      g.playDeferredCard(PlayerColor.blue, c, targetPawn: mine);
      expect(g.upgrades.isInvulnerable(mine), isTrue);
      expect(g.upgrades.handOf(PlayerColor.blue), isEmpty,
          reason: 'la carte jouée quitte la main');
    });

    test('2 — « Le pion adverse est FIGÉ » : il ne peut plus bouger', () {
      final c = def('2');
      final g = armed(c);
      final foe = g.state.pawnsByColor[PlayerColor.red]![0];
      put(foe, 6);

      expect(g.deferredPawnTargets(PlayerColor.blue, c), contains(foe),
          reason: 'un pion adverse sorti doit être désignable');
      g.playDeferredCard(PlayerColor.blue, c, targetPawn: foe);
      expect(g.upgrades.isFrozen(foe), isTrue);

      // Et rouge, à son tour, ne peut effectivement pas le jouer.
      g.currentPlayerIdx = g.turnOrder.indexOf(PlayerColor.red);
      g.phase = TurnPhase.rolling;
      g.roll(4);
      expect(g.movablePawns().contains(foe), isFalse,
          reason: 'c\'est TOUT l\'objet de la carte : il ne bouge plus');
    });

    test('3 — « Pas de sortie » : le 6 ne fait plus sortir ce pion', () {
      final c = def('3');
      final g = armed(c);
      final foe = g.state.pawnsByColor[PlayerColor.red]![0];
      expect(foe.location, PawnLocation.base);
      expect(g.deferredPawnTargets(PlayerColor.blue, c), contains(foe),
          reason: 'seul un pion encore en boîte est visable');
      g.playDeferredCard(PlayerColor.blue, c, targetPawn: foe);
      expect(g.upgrades.cannotExit(foe), isTrue);

      g.currentPlayerIdx = g.turnOrder.indexOf(PlayerColor.red);
      g.phase = TurnPhase.rolling;
      g.roll(6);
      expect(g.movablePawns().contains(foe), isFalse,
          reason: 'même avec un 6, ce pion reste dans sa boîte');
    });

    for (var face = 1; face <= 6; face++) {
      final code = '${face + 3}'; // 4→1, 5→2 … 9→6
      test('$code — « Carte dé $face » : le lancer VAUT $face', () {
        final c = def(code);
        final g = armed(c);
        // Un pion sorti, assez loin du couloir pour que tout dé passe.
        put(g.state.pawnsByColor[PlayerColor.blue]![0], 5);
        expect(g.canPlayDeferred(PlayerColor.blue, c), isTrue,
            reason: 'une carte-dé se joue AVANT le lancer');
        final forced = g.playDeferredCard(PlayerColor.blue, c);
        expect(forced, face,
            reason: 'la carte impose la valeur, elle ne la tire pas');
        g.roll(forced!);
        expect(g.diceValue, face, reason: 'et c\'est elle qui est jouée');
      });
    }

    test('10 — « Règle après capture » : la règle est ARMÉE pour le tour',
        () {
      final c = def('10');
      // Elle se joue APRÈS le lancer : c'est une règle sur la capture qui
      // va suivre, pas sur le dé.
      final g = armed(c, afterRoll: true);
      g.playDeferredCard(PlayerColor.blue, c);
      expect(g.upgrades.captureRuleArmed(PlayerColor.blue), isTrue);
      // Elle ne survit pas au tour : non utilisée, elle est perdue.
      g.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(g.upgrades.captureRuleArmed(PlayerColor.blue), isFalse);
    });

    test('11 — « Le voisin de droite saute 2 tours »', () {
      final c = def('11');
      final g = armed(c);
      final victim = g.rightNeighbourOf(PlayerColor.blue);
      g.playDeferredCard(PlayerColor.blue, c);
      expect(g.upgrades.skipsLeft(victim), 2);
      expect(g.upgrades.consumeSkip(victim), isTrue,
          reason: 'son tour lui est effectivement retiré');
      expect(g.upgrades.skipsLeft(victim), 1);
    });

    test('12 — « Le joueur de mon choix saute 2 tours »', () {
      final c = def('12');
      final g = armed(c);
      final targets = g.deferredPlayerTargets(PlayerColor.blue, c);
      expect(targets, isNotEmpty);
      final victim = targets.first;
      g.playDeferredCard(PlayerColor.blue, c, targetPlayer: victim);
      expect(g.upgrades.skipsLeft(victim), 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  LE FILET : aucune carte ne doit rester lettre morte
  // ══════════════════════════════════════════════════════════════════════
  test('les 24 cartes sont couvertes, et aucune n\'est inerte', () {
    final all = [...kImmediateCards, ...kDeferredCards];
    expect(all.length, 24);
    for (final c in all) {
      expect(c.active, isTrue, reason: '${cardCode(c)} est désactivée');
      expect(c.descriptionFr.trim(), isNotEmpty,
          reason: '${cardCode(c)} n\'explique rien');
    }
  });
}
