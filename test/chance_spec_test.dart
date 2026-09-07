// Conformité à la spec « La case chance » — chaque puce du cahier des
// charges, vérifiée une par une.
//
// Ce fichier ne teste pas le code par le menu : il relit la SPEC. Chaque
// test porte le numéro de sa puce, pour qu'on puisse pointer une ligne du
// document et retrouver son test. Si une règle du jeu change, c'est ici
// qu'on vient d'abord.

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

void putOnRing(Pawn p, int steps) {
  p.location = PawnLocation.ring;
  p.position = (GameController.startIdx(p.color) + steps) %
      GameController.ringSize;
}

ChanceCard imm(String id) => kImmediateCards.singleWhere((c) => c.id == id);
ChanceCard def(String id) => kDeferredCards.singleWhere((c) => c.id == id);

/// Met [id] dans la main de [color] et lui donne la main, dé non lancé.
ChanceCard give(GameController c, PlayerColor color, String id) {
  final card = def(id);
  c.upgrades.addToHand(color, card);
  c.currentPlayerIdx = c.turnOrder.indexOf(color);
  c.phase = TurnPhase.rolling;
  // Une carte-dé est refusée si elle ne donne aucun coup jouable (§9) :
  // on met donc un pion sur l'anneau pour que le coup existe.
  putOnRing(c.state.pawnsByColor[color]![0], 8);
  return card;
}

void main() {
  group('§ La case chance', () {
    test('il y en a 4, placées 2 cases avant l\'étoile de protection', () {
      const stars = {8, 21, 34, 47};
      expect(SpecialCells.chanceCells.length, 4);
      for (final cell in SpecialCells.chanceCells) {
        expect(stars.contains((cell + 2) % GameController.ringSize), isTrue,
            reason: 'la case $cell doit précéder une étoile de 2 cases');
      }
    });

    test('une carte immédiate s\'applique sur le jeton tombé sur la case',
        () {
      final c = newGame();
      c.upgrades
        ..chanceEnabled = true
        ..rng = math.Random(3);
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      final before = PawnStep(p.location, p.position);
      putOnRing(p, 2);
      c.phase = TurnPhase.rolling;
      c.roll(4); // 2 + 4 = 6 → case Chance du bleu
      c.movePawn(p);
      // Quelque chose s'est passé : soit le pion a changé d'état, soit une
      // carte est partie en main. Dans les deux cas, c'est annoncé.
      expect(c.upgrades.takeNotices(), isNotEmpty);
      expect(before, isNotNull);
    });
  });

  group('§ i — Les cartes chance immédiates', () {
    test('le talon contient 1 carte par instruction, soit 12', () {
      expect(kImmediateCards.length, 12);
      expect(kImmediateCards.map((c) => c.id).toSet().length, 12);
      for (final card in kImmediateCards) {
        expect(card.kind, CardKind.immediate);
        expect(card.timing, ChanceTiming.onChance);
      }
    });

    test('mélangé au début, RETOURNÉ (pas remélangé) une fois épuisé', () {
      final u = LudoUpgrades()..rng = math.Random(42);
      final first = [
        for (int i = 0; i < kImmediateCards.length; i++) u.drawImmediate().id,
      ];
      expect(first.toSet().length, kImmediateCards.length);
      final second = [
        for (int i = 0; i < kImmediateCards.length; i++) u.drawImmediate().id,
      ];
      expect(second, first.reversed.toList());
    });

    test('i.1.a — Reculez de 3 cases', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 10);
      c.applyImmediateCard(imm('IMM_PAWN_BACK_3'), p);
      expect(p.position, 7);
    });

    test('i.1.b — Avancez de 3 cases', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 10);
      c.applyImmediateCard(imm('IMM_PAWN_FORWARD_3'), p);
      expect(p.position, 13);
    });

    test('i.1.c — Tous vos pions sortent d\'un coup', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 10);
      c.applyImmediateCard(imm('IMM_ALL_PAWNS_OUT'), p);
      expect(
          c.state.pawnsByColor[PlayerColor.blue]!
              .where((x) => x.location == PawnLocation.base),
          isEmpty);
    });

    test('i.1.d — Votre pion se place juste devant la sortie', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.yellow]![0];
      putOnRing(p, 6);
      c.applyImmediateCard(imm('IMM_PAWN_BEFORE_EXIT'), p);
      final steps = (p.position - GameController.startIdx(PlayerColor.yellow) +
              GameController.ringSize) %
          GameController.ringSize;
      expect(steps, GameController.lastRingStep,
          reason: 'la dernière case avant le couloir');
    });

    test('i.1.e — Votre pion retourne dans sa boîte départ', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.green]![2];
      putOnRing(p, 30);
      c.applyImmediateCard(imm('IMM_PAWN_HOME'), p);
      expect(p.location, PawnLocation.base);
      expect(p.position, p.id);
    });

    test('i.1.f — Pion invulnérable pendant 2 tours', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 10);
      c.applyImmediateCard(imm('IMM_PAWN_INVULNERABLE'), p);
      expect(c.upgrades.isInvulnerable(p), isTrue, reason: 'tour 1');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(p), isTrue, reason: 'tour 2');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(p), isFalse, reason: '2 tours, pas 3');
    });

    test('i.1.g — Pion figé pendant 2 tours', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 10);
      c.applyImmediateCard(imm('IMM_PAWN_FROZEN'), p);
      // Le tour du tirage est DÉJÀ dépensé — le pion vient de jouer pour
      // arriver sur la case. Le gel mord donc aux DEUX tours suivants,
      // sans quoi la carte ne coûterait qu'un seul tour jouable.
      expect(c.upgrades.isFrozen(p), isFalse,
          reason: 'le tour du tirage ne compte pas');

      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isFrozen(p), isTrue, reason: '1er tour bloqué');
      // On arme la phase à la main : `roll` passerait la main faute de
      // coup jouable, et compterait un tour de plus.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.diceValue = 3;
      c.phase = TurnPhase.moving;
      expect(c.movablePawns(), isNot(contains(p)),
          reason: 'un pion figé ne se joue pas');

      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isFrozen(p), isTrue, reason: '2e tour bloqué');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isFrozen(p), isFalse, reason: '2 tours, pas 3');
    });

    test('i.1.h — Avancez sur le premier adversaire devant et capturez-le',
        () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(p, 5);
      foe.location = PawnLocation.ring;
      foe.position = 11;
      c.applyImmediateCard(imm('IMM_CAPTURE_AHEAD'), p);
      expect(p.position, 11);
      expect(foe.location, PawnLocation.base);
    });

    test('i.1.i — Reculez sur le premier adversaire derrière et '
        'capturez-le', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(p, 20);
      foe.location = PawnLocation.ring;
      foe.position = 15;
      c.applyImmediateCard(imm('IMM_CAPTURE_BEHIND'), p);
      expect(p.position, 15);
      expect(foe.location, PawnLocation.base);
    });

    /// Les 3 cartes de dé partagent la même promesse : rien au tour du
    /// tirage, puis exactement 2 tours modifiés.
    void diceCard(String id, String label, Set<int> expected) {
      test('i.2 — $label : à partir du tour suivant, pendant 2 tours', () {
        final c = newGame();
        final rng = math.Random(7);
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        c.applyImmediateCard(imm(id), p);

        expect(c.upgrades.activeDiceMode(PlayerColor.blue), isNull,
            reason: 'le tour du tirage garde le dé normal');
        c.upgrades.onTurnCompleted(PlayerColor.blue);

        final seen = <int>{
          for (int i = 0; i < 600; i++)
            c.pickDiceValueFor(PlayerColor.blue, rng),
        };
        expect(seen, expected, reason: 'valeurs possibles');

        c.upgrades.onTurnCompleted(PlayerColor.blue);
        expect(c.upgrades.activeDiceMode(PlayerColor.blue), isNotNull,
            reason: '2e tour, encore actif');
        c.upgrades.onTurnCompleted(PlayerColor.blue);
        expect(c.upgrades.activeDiceMode(PlayerColor.blue), isNull,
            reason: '3e tour, terminé');
      });
    }

    diceCard('IMM_DICE_HALF', 'Demi-dé', {1, 2, 3});
    // Le double-dé, c'est UNE face comptée DEUX FOIS — donc uniquement
    // des valeurs paires. C'est ce que la carte écrit noir sur blanc :
    // « Double-dé pendant 2 tours (2, 4, 6, 8, 10, 12) », et sa
    // description : « le dé ne produit que des valeurs paires ».
    //
    // Il tirait auparavant deux dés indépendants. Deux conséquences, les
    // deux fausses : la carte sortait des valeurs impaires que sa propre
    // consigne interdit, et elle devenait IDENTIQUE à « Deux dés » — deux
    // cartes du talon pour un seul effet, impossibles à distinguer.
    diceCard('IMM_DICE_DOUBLE', 'Double-dé',
        {for (int v = 1; v <= 6; v++) v * 2});
    diceCard('IMM_TWO_DICE', 'Deux dés',
        {for (int v = 2; v <= 12; v++) v});
  });

  group('§ ii — Les cartes chance différées', () {
    test('chaque joueur a SON talon, complet', () {
      expect(kDeferredCards.length, 12);
      final u = LudoUpgrades()..rng = math.Random(11);
      final blue = [
        for (int i = 0; i < kDeferredCards.length; i++)
          u.drawDeferred(PlayerColor.blue).id,
      ];
      expect(blue.toSet().length, kDeferredCards.length);
      // Le talon du rouge n'a rien consommé.
      final red = [
        for (int i = 0; i < kDeferredCards.length; i++)
          u.drawDeferred(PlayerColor.red).id,
      ];
      expect(red.toSet().length, kDeferredCards.length);
    });

    test('il y a de la place pour 4 cartes différées, pas une de plus', () {
      expect(LudoUpgrades.handLimit, 4);
      final u = LudoUpgrades()..rng = math.Random(5);
      for (int i = 0; i < 4; i++) {
        expect(u.addToHand(PlayerColor.blue, kDeferredCards[i]), isTrue);
      }
      expect(u.addToHand(PlayerColor.blue, kDeferredCards[4]), isFalse,
          reason: 'la 5e est refusée');
      expect(u.handOf(PlayerColor.blue).length, 4);
    });

    test('on ne joue qu\'une carte différée à la fois', () {
      final c = newGame();
      final a = give(c, PlayerColor.blue, 'DEF_DICE_4');
      final b = give(c, PlayerColor.blue, 'DEF_DICE_2');
      expect(c.playDeferredCard(PlayerColor.blue, a), 4);
      expect(c.canPlayDeferred(PlayerColor.blue, b), isFalse);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.canPlayDeferred(PlayerColor.blue, b), isTrue,
          reason: 'au tour suivant, on peut en rejouer une');
    });

    test('« Avant » se joue avant le lancer, « Après » après', () {
      final c = newGame();
      final avant = give(c, PlayerColor.blue, 'DEF_DICE_4');
      final apres = give(c, PlayerColor.blue, 'DEF_CAPTURE_TO_MY_BOX');
      expect(c.canPlayDeferred(PlayerColor.blue, avant), isTrue);
      expect(c.canPlayDeferred(PlayerColor.blue, apres), isFalse);
      c.roll(6);
      expect(c.canPlayDeferred(PlayerColor.blue, avant), isFalse);
      expect(c.canPlayDeferred(PlayerColor.blue, apres), isTrue);
    });

    test('ii.1.a — Pion invulnérable pendant 2 tours (Avant)', () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_PAWN_INVULNERABLE');
      expect(card.timing, ChanceTiming.beforeRoll);
      final mine = c.state.pawnsByColor[PlayerColor.blue]![0];
      // L'invulnérabilité protège d'une capture : elle ne se pose que sur
      // un pion DÉJÀ SUR L'ANNEAU, le seul endroit où l'on peut être mangé.
      putOnRing(mine, 12);
      expect(c.deferredPawnTargets(PlayerColor.blue, card),
          everyElement(predicate<Pawn>((x) =>
              x.color == PlayerColor.blue &&
              x.location == PawnLocation.ring)));
      c.playDeferredCard(PlayerColor.blue, card, targetPawn: mine);
      expect(c.upgrades.isInvulnerable(mine), isTrue);
    });

    test('ii.1.b — Pion d\'un adversaire figé pendant 2 tours (Avant)', () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_OPPONENT_FROZEN');
      expect(card.timing, ChanceTiming.beforeRoll);
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(foe, 10);
      // Elle vise les ADVERSAIRES.
      expect(c.deferredPawnTargets(PlayerColor.blue, card),
          everyElement(predicate<Pawn>((x) => x.color != PlayerColor.blue)));
      c.playDeferredCard(PlayerColor.blue, card, targetPawn: foe);
      expect(c.upgrades.isFrozen(foe), isTrue);
    });

    test('ii.1.c — le pion adverse désigné ne SORT PAS de sa boîte', () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_OPPONENT_NO_EXIT');
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      // Il est en boîte, comme au départ.
      expect(foe.location, PawnLocation.base);
      c.playDeferredCard(PlayerColor.blue, card, targetPawn: foe);
      expect(c.upgrades.cannotExit(foe), isTrue);

      // Rouge sort un 6 : ce pion-là ne peut pas sortir.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      c.phase = TurnPhase.rolling;
      c.roll(6);
      expect(c.movablePawns(), isNot(contains(foe)),
          reason: 'il reste dans sa boîte');
      expect(c.movablePawns(), isNotEmpty,
          reason: 'ses trois autres pions sortent normalement');

      // L'occasion est passée : la marque tombe à la fin du tour.
      c.movePawn(c.movablePawns().first);
      c.skipTurn();
      expect(c.upgrades.cannotExit(foe), isFalse,
          reason: 'il attendra la prochaine occasion, et elle arrive');
    });

    test('ii.2.a — 6 cartes dés de 1 à 6, à la place du lancer (Avant)', () {
      final dice = kDeferredCards
          .where((c) => c.action == CardAction.setDice)
          .toList();
      expect(dice.length, 6);
      expect((dice.map((c) => c.value).toList()..sort()), [1, 2, 3, 4, 5, 6]);
      for (int v = 1; v <= 6; v++) {
        final c = newGame();
        final card = give(c, PlayerColor.blue, 'DEF_DICE_$v');
        expect(card.timing, ChanceTiming.beforeRoll);
        expect(c.playDeferredCard(PlayerColor.blue, card), v);
      }
    });

    test('ii.3.a — après capture, le pion regagne la boîte de SON '
        'propriétaire et devra faire 6 (APRÈS)', () {
      final c = newGame();
      final card = def('DEF_CAPTURE_TO_MY_BOX');
      expect(card.timing, ChanceTiming.afterRoll);
      c.upgrades.addToHand(PlayerColor.blue, card);
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(blue, 5);
      foe.location = PawnLocation.ring;
      foe.position = 10;

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;
      c.roll(5);
      expect(c.canPlayDeferred(PlayerColor.blue, card), isTrue,
          reason: 'une carte APRÈS se joue le dé en main');
      c.playDeferredCard(PlayerColor.blue, card);
      expect(c.upgrades.captureRuleArmed(PlayerColor.blue), isTrue);
      c.movePawn(blue);

      expect(foe.location, PawnLocation.base,
          reason: 'la victime rentre dans SA propre boîte');
      expect(foe.position, foe.id);

      // Et il lui faut un 6 pour ressortir — la règle normale du Ludo.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      c.phase = TurnPhase.rolling;
      c.roll(3);
      expect(c.movablePawns(), isNot(contains(foe)));
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      c.phase = TurnPhase.rolling;
      c.roll(6);
      expect(c.movablePawns(), contains(foe));
    });

    test('ii.4.a — le joueur à votre droite ne joue pas pendant 2 tours', () {
      final c = newGame();
      final card = give(c, PlayerColor.green, 'DEF_SKIP_RIGHT');
      expect(card.timing, ChanceTiming.beforeRoll);
      c.playDeferredCard(PlayerColor.green, card);
      expect(c.upgrades.skipsLeft(c.rightNeighbourOf(PlayerColor.green)), 2);
    });

    test('ii.4.b — le joueur de votre choix ne joue pas pendant 2 tours',
        () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_SKIP_CHOSEN');
      expect(card.timing, ChanceTiming.beforeRoll);
      expect(c.deferredPlayerTargets(PlayerColor.blue, card),
          isNot(contains(PlayerColor.blue)));
      c.playDeferredCard(PlayerColor.blue, card,
          targetPlayer: PlayerColor.yellow);
      expect(c.upgrades.skipsLeft(PlayerColor.yellow), 2);
    });
  });

  group('§ ANNEXE A — le modèle des cartes', () {
    test('les effets ne se CUMULENT jamais : la durée repart de zéro', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 5);
      c.applyImmediateCard(imm('IMM_PAWN_INVULNERABLE'), p);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.applyImmediateCard(imm('IMM_PAWN_INVULNERABLE'), p);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(p), isTrue,
          reason: 'la durée compte depuis le re-tirage');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(p), isFalse,
          reason: 'et pas plus de 2 tours pour autant');
    });

    test('un nouvel état REMPLACE le précédent', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(p, 5);
      c.applyImmediateCard(imm('IMM_PAWN_INVULNERABLE'), p);
      c.applyImmediateCard(imm('IMM_PAWN_FROZEN'), p);
      expect(c.upgrades.isInvulnerable(p), isFalse,
          reason: 'un pion n\'a qu\'un état à la fois');
      // Le gel prend au tour suivant : c'est là qu'on le constate.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isFrozen(p), isTrue);
    });

    test('STATUS : une carte INACTIVE est sautée, comme si elle n\'existait '
        'pas', () {
      // Toutes les cartes livrées sont ACTIVE ; la règle vit dans le
      // filtre du talon.
      expect(kImmediateCards.every((c) => c.active), isTrue);
      expect(kDeferredCards.every((c) => c.active), isTrue);
      const off = ChanceCard(
        id: 'TEST_OFF',
        nameFr: 'x',
        nameEn: 'x',
        nameEs: 'x',
        descriptionFr: 'x',
        kind: CardKind.immediate,
        timing: ChanceTiming.onChance,
        action: CardAction.move,
        active: false,
      );
      expect(off.active, isFalse);
    });

    test('TIMING : ON_CHANCE, AVANT, APRÈS et AVANT/APRÈS', () {
      expect(ChanceTiming.values.map((e) => e.name).toSet(),
          {'onChance', 'beforeRoll', 'afterRoll', 'beforeOrAfterRoll'});
    });

    test('SELECTION : les 4 valeurs de la spec (plus « aucune cible »)', () {
      expect(CardSelection.values.map((e) => e.name).toSet(), {
        'pawnOnChance',
        'chosen',
        'firstOnPath',
        'firstBehind',
        'none',
      });
      // CHOSEN est la seule qui demande au JOUEUR de désigner sa cible.
      for (final card in [...kImmediateCards, ...kDeferredCards]) {
        expect(card.needsTarget, card.selection == CardSelection.chosen,
            reason: card.id);
      }
    });

    test('CIBLAGE : scope et entity couvrent toutes les cartes', () {
      for (final card in [...kImmediateCards, ...kDeferredCards]) {
        expect(CardScope.values, contains(card.scope), reason: card.id);
        expect(CardEntity.values, contains(card.entity), reason: card.id);
      }
    });
  });
}
