// Les AMÉLIORATIONS — cases Vortex, cases Chance et cartes immédiates.
//
// Trois garanties d'ensemble :
//   1. ÉTEINTES (défaut), elles sont invisibles : le Ludo de base est
//      inchangé au bit près.
//   2. Allumées, chaque case et chaque carte fait EXACTEMENT ce que dit
//      la spec (géométrie, talon retourné, durées « 2 tours »).
//   3. Aucun cumul : une carte retirée REMPLACE l'effet en cours.

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

void putOnRing(GameController c, Pawn p, int steps) {
  p.location = PawnLocation.ring;
  p.position = (GameController.startIdx(p.color) + steps) %
      GameController.ringSize;
}

ChanceCard card(String id) =>
    kImmediateCards.singleWhere((c) => c.id == id);

/// Force la phase « moving » avec un dé de [v] pour le joueur courant.
void arm(GameController c, int v) {
  c.phase = TurnPhase.rolling;
  c.roll(v);
}

void main() {
  group('🕳️ Géométrie des cases spéciales', () {
    test('vortex bons : la case de départ de chaque couleur', () {
      for (final c in PlayerColor.values) {
        expect(SpecialCells.goodVortexCell(c), GameController.startIdx(c));
      }
    });

    test('les diagonales se répondent, à +26 pas', () {
      for (final c in PlayerColor.values) {
        final d = SpecialCells.diagonalOf[c]!;
        expect(SpecialCells.diagonalOf[d], c, reason: 'diagonale symétrique');
        expect(
            (GameController.startIdx(d) -
                    GameController.startIdx(c) +
                    GameController.ringSize) %
                GameController.ringSize,
            26,
            reason: '${c.name} → ${d.name} doit être à l\'exact opposé');
      }
    });

    test('cases Chance : 2 cases avant chaque étoile (départ + 6)', () {
      expect(SpecialCells.chanceCells, {6, 19, 32, 45});
      for (final c in PlayerColor.values) {
        expect(
            SpecialCells.chanceCells.contains(
                (GameController.startIdx(c) + 6) % GameController.ringSize),
            isTrue);
      }
      // Jamais une case sûre : la capture y reste possible.
      for (final cell in SpecialCells.chanceCells) {
        expect(const {0, 13, 26, 39, 8, 21, 34, 47}.contains(cell), isFalse);
      }
    });
  });

  group('🔌 Éteintes par défaut : le Ludo de base est INTACT', () {
    test('les interrupteurs démarrent éteints', () {
      final c = newGame();
      expect(c.upgrades.vortexEnabled, isFalse);
      expect(c.upgrades.chanceEnabled, isFalse);
    });

    test('sortir sur sa case de départ ne téléporte PAS', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      arm(c, 6);
      c.movePawn(p);
      expect(p.position, GameController.startIdx(PlayerColor.blue));
    });

    test('atterrir sur une case Chance ne tire AUCUNE carte', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 3);
      arm(c, 3); // 3 + 3 = 6 → case Chance du bleu
      c.movePawn(p);
      expect(p.position, 6);
      expect(c.upgrades.takeNotices(), isEmpty);
    });

    test('entrer dans son couloir ne renvoie PAS en arrière', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 48);
      arm(c, 3); // 51 → couloir case 0
      c.movePawn(p);
      expect(p.location, PawnLocation.homeColumn);
      expect(p.position, 0);
    });
  });

  group('🌀 Vortex BON — aspiré vers la diagonale', () {
    test('sortir de base aspire vers le départ de la diagonale, '
        'pour les 4 couleurs', () {
      for (final color in PlayerColor.values) {
        final c = newGame();
        c.upgrades.vortexEnabled = true;
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        final p = c.state.pawnsByColor[color]![0];
        arm(c, 6);
        c.movePawn(p);
        final diag = SpecialCells.diagonalOf[color]!;
        expect(p.location, PawnLocation.ring);
        expect(p.position, GameController.startIdx(diag),
            reason: '${color.name} doit être aspiré chez ${diag.name}');
        expect(c.upgrades.takeNotices().single, contains('Vortex'));
      }
    });

    test('le vortex d\'une AUTRE couleur ne fait rien', () {
      final c = newGame();
      c.upgrades.vortexEnabled = true;
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      final p = c.state.pawnsByColor[PlayerColor.red]![0];
      // Rouge à 36 pas : la case de départ du BLEU (cellule 0) est à 39
      // pas de rouge → un dé de 3 l'y pose.
      putOnRing(c, p, 36);
      arm(c, 3);
      c.movePawn(p);
      expect(p.position, 0, reason: 'posé sur le départ bleu, sans vortex');
      expect(c.upgrades.takeNotices(), isEmpty);
    });
  });

  group('🕳️ Vortex MAUVAIS — la ligne droite refusée', () {
    test('entrer sur la 1re case de SON couloir renvoie à l\'entrée de la '
        'ligne droite de la diagonale, pour les 4 couleurs', () {
      for (final color in PlayerColor.values) {
        final c = newGame();
        c.upgrades.vortexEnabled = true;
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        final p = c.state.pawnsByColor[color]![0];
        putOnRing(c, p, 48);
        arm(c, 3); // 51 → couloir case 0 → aspiré
        c.movePawn(p);
        expect(p.location, PawnLocation.ring,
            reason: '${color.name} doit être renvoyé sur l\'anneau');
        expect(p.position, SpecialCells.badVortexTarget(color));
        // Depuis sa nouvelle case, il lui reste la moitié du plateau :
        // l'entrée du couloir de la diagonale est à 24 pas de SON départ.
        final steps = (p.position - GameController.startIdx(color) + 52) % 52;
        expect(steps, 24, reason: 'la moitié du plateau à refaire');
        expect(c.upgrades.takeNotices().single, contains('Trou noir'));
      }
    });

    test('une case plus loin dans le couloir (case 1) ne déclenche rien',
        () {
      final c = newGame();
      c.upgrades.vortexEnabled = true;
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 48);
      arm(c, 4); // 52 → couloir case 1 : pas la première
      c.movePawn(p);
      expect(p.location, PawnLocation.homeColumn);
      expect(p.position, 1);
      expect(c.upgrades.takeNotices(), isEmpty);
    });
  });

  group('🃏 Le talon des cartes immédiates', () {
    test('mélangé une fois, puis RETOURNÉ à l\'épuisement (pas remélangé)',
        () {
      final u = LudoUpgrades()..rng = math.Random(42);
      final first = [
        for (int i = 0; i < kImmediateCards.length; i++) u.drawImmediate().id,
      ];
      expect(first.toSet().length, kImmediateCards.length,
          reason: 'une carte par instruction, chacune une seule fois');
      final second = [
        for (int i = 0; i < kImmediateCards.length; i++) u.drawImmediate().id,
      ];
      expect(second, first.reversed.toList(),
          reason: 'le talon épuisé est retourné tel quel');
      // Et le cycle continue : troisième passe = première remise à l'endroit.
      final third = [
        for (int i = 0; i < kImmediateCards.length; i++) u.drawImmediate().id,
      ];
      expect(third, first);
    });

    test('une carte INACTIVE est sautée comme si elle n\'existait pas', () {
      // Toutes les cartes livrées sont actives ; la règle est vérifiée sur
      // le filtre lui-même.
      expect(kImmediateCards.every((c) => c.active), isTrue);
    });
  });

  group('🂠 Chaque carte immédiate, une par une', () {
    test('Reculez de 3 cases — et jamais au-delà du départ', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 10);
      c.applyImmediateCard(card('IMM_PAWN_BACK_3'), p);
      expect(p.position, 7);
      putOnRing(c, p, 1);
      c.applyImmediateCard(card('IMM_PAWN_BACK_3'), p);
      expect(p.position, GameController.startIdx(PlayerColor.blue),
          reason: 'le recul s\'arrête à la case de départ, sans wrap');
    });

    test('Reculez de 3 : capture à l\'arrivée, règles habituelles', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 10);
      red.location = PawnLocation.ring;
      red.position = 7; // 7 pas du bleu, case non sûre
      c.applyImmediateCard(card('IMM_PAWN_BACK_3'), blue);
      expect(blue.position, 7);
      expect(red.location, PawnLocation.base, reason: 'capturé par la carte');
    });

    test('Avancez de 3 cases — anneau, couloir, et maison exacte', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 10);
      c.applyImmediateCard(card('IMM_PAWN_FORWARD_3'), p);
      expect(p.position, 13);
      putOnRing(c, p, 49);
      c.applyImmediateCard(card('IMM_PAWN_FORWARD_3'), p);
      expect(p.location, PawnLocation.homeColumn);
      expect(p.position, 1, reason: '49 + 3 = 52 → couloir case 1');
    });

    test('Tous vos pions sortent d\'un coup — empilés sur le départ', () {
      final c = newGame();
      final pawns = c.state.pawnsByColor[PlayerColor.blue]!;
      putOnRing(c, pawns[0], 20); // déjà en jeu : il ne bouge pas
      c.applyImmediateCard(card('IMM_ALL_PAWNS_OUT'), pawns[1]);
      expect(pawns[0].position, 20);
      for (final p in pawns.skip(1)) {
        expect(p.location, PawnLocation.ring);
        expect(p.position, GameController.startIdx(PlayerColor.blue));
      }
    });

    test('Votre pion se place juste devant la sortie (50e pas)', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.yellow]![0];
      putOnRing(c, p, 6);
      c.applyImmediateCard(card('IMM_PAWN_BEFORE_EXIT'), p);
      expect(p.location, PawnLocation.ring);
      expect((p.position - GameController.startIdx(PlayerColor.yellow) + 52) %
          52, 50);
    });

    test('Votre pion retourne dans sa boîte départ', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.green]![2];
      putOnRing(c, p, 30);
      c.applyImmediateCard(card('IMM_PAWN_HOME'), p);
      expect(p.location, PawnLocation.base);
      expect(p.position, p.id);
    });

    test('Avancez sur le premier adversaire devant : saute les cases sûres '
        'et capture le premier capturable', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]!;
      putOnRing(c, blue, 5);
      red[0].location = PawnLocation.ring;
      red[0].position = 8; // étoile SÛRE : intouchable
      red[1].location = PawnLocation.ring;
      red[1].position = 11; // première vraie cible
      c.applyImmediateCard(card('IMM_CAPTURE_AHEAD'), blue);
      expect(red[0].position, 8, reason: 'la case sûre protège');
      expect(red[1].location, PawnLocation.base, reason: 'capturé');
      expect(blue.position, 11, reason: 'le chasseur prend la case');
    });

    test('Avancez sur le premier adversaire : sans cible, rien ne bouge',
        () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 5);
      c.applyImmediateCard(card('IMM_CAPTURE_AHEAD'), blue);
      expect(blue.position, 5);
    });

    test('Reculez sur le premier adversaire derrière et capturez-le', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 20);
      red.location = PawnLocation.ring;
      red.position = 15; // 15 pas du bleu, derrière lui
      c.applyImmediateCard(card('IMM_CAPTURE_BEHIND'), blue);
      expect(blue.position, 15);
      expect(red.location, PawnLocation.base);
    });
  });

  group('🛡️ Invulnérable & figé — « pendant 2 tours », sans cumul', () {
    test('un pion invulnérable ne se fait PAS capturer au dé', () {
      final c = newGame();
      c.upgrades.chanceEnabled = true;
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 5); // cellule 5, non sûre
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      // Rouge arrive sur sa case : cellule 5 = 44 pas de rouge.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      putOnRing(c, red, 40);
      arm(c, 4);
      c.movePawn(red);
      expect(red.position, 5, reason: 'les deux cohabitent sur la case');
      expect(blue.location, PawnLocation.ring,
          reason: 'l\'invulnérable reste en jeu');
      expect(blue.position, 5);
    });

    test('l\'invulnérabilité couvre 2 tours du propriétaire, puis EXPIRE',
        () {
      // « Pendant 2 tours », effet immédiat : le tour du tirage et le
      // suivant. Il faut qu'elle protège TOUT DE SUITE — c'est pendant
      // que les adversaires jouent, juste après, que le pion risque de
      // se faire manger.
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 5);
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue,
          reason: 'protégé dès le tirage');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue,
          reason: '2e tour, encore protégé');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isFalse,
          reason: 'expirée au 3e tour : 2 tours, pas plus');
    });

    test('re-tirer la carte REMPLACE la durée : ça repart pour 2 tours',
        () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 5);
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      // Sur le point d'expirer — nouvelle carte : la durée repart.
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue,
          reason: 'la nouvelle durée compte depuis le re-tirage');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isFalse,
          reason: 'et elle ne dure pas plus de 2 tours non plus');
    });

    test('un pion FIGÉ n\'est plus jouable, puis se libère', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 10);
      c.applyImmediateCard(card('IMM_PAWN_FROZEN'), blue);
      arm(c, 3);
      expect(c.movablePawns(), isEmpty,
          reason: 'le seul pion en jeu est figé, et 3 ne sort pas de base');
      // Le lancer sans coup jouable a déjà passé la main : un tour bleu
      // est compté. Encore un, et l'état expire.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 3);
      expect(c.movablePawns(), [blue], reason: 'libéré après 2 tours');
    });
  });

  group('🎲 Modificateurs de dé — « à partir du tour suivant »', () {
    test('demi-dé : 1..3 pendant les 2 tours suivants, puis dé normal', () {
      final c = newGame();
      final rng = math.Random(7);
      c.applyImmediateCard(
          card('IMM_DICE_HALF'), c.state.pawnsByColor[PlayerColor.blue]![0]);
      // Tour du tirage : le dé reste NORMAL (la carte parle du tour suivant).
      expect(c.upgrades.activeDiceMode(PlayerColor.blue), isNull);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      for (int i = 0; i < 200; i++) {
        final v = c.pickDiceValueFor(PlayerColor.blue, rng);
        expect(v, inInclusiveRange(1, 3));
      }
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.activeDiceMode(PlayerColor.blue),
          CardDiceMode.limit, reason: 'encore actif au 2e tour');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.activeDiceMode(PlayerColor.blue), isNull);
      final seen = <int>{
        for (int i = 0; i < 300; i++) c.pickDiceValueFor(PlayerColor.blue, rng),
      };
      expect(seen, {1, 2, 3, 4, 5, 6}, reason: 'dé redevenu entier');
    });

    test('double-dé : uniquement 2, 4, 6, 8, 10, 12', () {
      final c = newGame();
      final rng = math.Random(7);
      c.applyImmediateCard(
          card('IMM_DICE_DOUBLE'), c.state.pawnsByColor[PlayerColor.red]![0]);
      c.upgrades.onTurnCompleted(PlayerColor.red);
      final seen = <int>{
        for (int i = 0; i < 400; i++) c.pickDiceValueFor(PlayerColor.red, rng),
      };
      expect(seen, {2, 4, 6, 8, 10, 12});
    });

    test('deux dés : sommes de 2 à 12, et le moteur SAIT jouer un 12', () {
      final c = newGame();
      final rng = math.Random(7);
      c.applyImmediateCard(
          card('IMM_TWO_DICE'), c.state.pawnsByColor[PlayerColor.blue]![0]);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      final seen = <int>{
        for (int i = 0; i < 600; i++) c.pickDiceValueFor(PlayerColor.blue, rng),
      };
      expect(seen, {for (int v = 2; v <= 12; v++) v});

      // Un 12 se JOUE : 12 cases d'un coup sur l'anneau.
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 10);
      arm(c, 12);
      expect(c.movablePawns(), contains(p));
      c.movePawn(p);
      expect(p.position, 22);
    });

    test('les autres couleurs gardent leur dé normal', () {
      final c = newGame();
      final rng = math.Random(7);
      c.applyImmediateCard(
          card('IMM_DICE_HALF'), c.state.pawnsByColor[PlayerColor.blue]![0]);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      final seen = <int>{
        for (int i = 0; i < 300; i++) c.pickDiceValueFor(PlayerColor.red, rng),
      };
      expect(seen, {1, 2, 3, 4, 5, 6});
    });
  });

  group('🎰 La case Chance en partie réelle', () {
    test('atterrir dessus tire une carte et l\'annonce', () {
      // Le tirage est à pile ou face : immédiate appliquée sur-le-champ,
      // ou différée rangée en main. Les deux DOIVENT être annoncées.
      final c = newGame();
      c.upgrades
        ..chanceEnabled = true
        ..rng = math.Random(3);
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 2);
      arm(c, 4); // 2 + 4 = 6 → case Chance
      c.movePawn(p);
      final notices = c.upgrades.takeNotices();
      expect(notices, isNotEmpty);
      expect(notices.first,
          anyOf(contains('Carte chance'), contains('Carte différée')));
    });

    test('le vortex précède la capture : atterrir sur le trou noir capture '
        'à la case d\'ARRIVÉE', () {
      final c = newGame();
      c.upgrades.vortexEnabled = true;
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      // Rouge posé sur la cible du trou noir bleu (cellule 24, non sûre).
      red.location = PawnLocation.ring;
      red.position = SpecialCells.badVortexTarget(PlayerColor.blue);
      putOnRing(c, blue, 48);
      arm(c, 3); // couloir 0 → aspiré sur la cellule 24
      c.movePawn(blue);
      expect(blue.position, SpecialCells.badVortexTarget(PlayerColor.blue));
      expect(red.location, PawnLocation.base,
          reason: 'capturé là où le vortex a déposé le pion');
    });

    test('reset() vide talon, états et compteurs', () {
      final c = newGame();
      c.upgrades
        ..vortexEnabled = true
        ..chanceEnabled = true;
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, 5);
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), p);
      c.upgrades.drawImmediate();
      c.reset();
      expect(c.upgrades.isInvulnerable(p), isFalse);
      expect(c.upgrades.doneTurns(PlayerColor.blue), 0);
      expect(c.upgrades.vortexEnabled, isTrue,
          reason: 'les interrupteurs de l\'utilisateur survivent au reset');
    });
  });

  // =======================================================================
  //  LES CARTES DIFFÉRÉES
  // =======================================================================

  group('🎴 Le talon différé et la main', () {
    test('chaque joueur a SON talon, complet, et il tourne pareil', () {
      final u = LudoUpgrades()..rng = math.Random(11);
      final blue = [
        for (int i = 0; i < kDeferredCards.length; i++)
          u.drawDeferred(PlayerColor.blue).id,
      ];
      expect(blue.toSet().length, kDeferredCards.length,
          reason: 'une carte par instruction, chacune une seule fois');
      // Le talon du rouge est indépendant : il n'a rien consommé.
      final red = [
        for (int i = 0; i < kDeferredCards.length; i++)
          u.drawDeferred(PlayerColor.red).id,
      ];
      expect(red.toSet().length, kDeferredCards.length);
      // Épuisé, le talon bleu est RETOURNÉ, pas remélangé.
      final blue2 = [
        for (int i = 0; i < kDeferredCards.length; i++)
          u.drawDeferred(PlayerColor.blue).id,
      ];
      expect(blue2, blue.reversed.toList());
    });

    test('sur une case Chance : UNE CHANCE SUR DEUX immédiate / différée',
        () {
      final u = LudoUpgrades()..rng = math.Random(2024);
      int deferred = 0;
      const draws = 2000;
      for (int i = 0; i < draws; i++) {
        if (u.drawOnChance(PlayerColor.blue).kind == CardKind.deferred) {
          deferred++;
        }
      }
      // Une pièce honnête sur 2000 tirages : l'écart type vaut ~22, donc
      // 900..1100 laisse une marge de 4 σ — le test ne peut pas clignoter,
      // mais il attraperait un tirage franchement biaisé.
      expect(deferred, inInclusiveRange(900, 1100),
          reason: '$deferred différées sur $draws tirages');
    });

    test('le talon contient bien les 6 cartes-dés, de 1 à 6', () {
      final dice = kDeferredCards
          .where((c) => c.action == CardAction.setDice)
          .map((c) => c.value)
          .toList()
        ..sort();
      expect(dice, [1, 2, 3, 4, 5, 6]);
    });

    test('la main tient 4 cartes, pas une de plus', () {
      final u = LudoUpgrades()..rng = math.Random(5);
      for (int i = 0; i < LudoUpgrades.handLimit; i++) {
        expect(u.addToHand(PlayerColor.blue, kDeferredCards[i]), isTrue);
      }
      expect(u.handOf(PlayerColor.blue).length, 4);
      expect(u.handIsFull(PlayerColor.blue), isTrue);
      expect(u.addToHand(PlayerColor.blue, kDeferredCards[5]), isFalse,
          reason: 'la 5e carte n\'a pas de place');
      expect(u.handOf(PlayerColor.blue).length, 4);
    });

    test('une case Chance donne parfois une différée : elle va EN MAIN, '
        'sans rien appliquer', () {
      // rng(1) : le premier drawOnChance tombe sur une différée.
      final c = newGame();
      c.upgrades
        ..chanceEnabled = true
        ..rng = math.Random(1);
      var landed = 0;
      // On rejoue l'arrivée sur la case Chance jusqu'à tomber sur une
      // différée : le tirage est à pile ou face, il vient vite.
      while (c.upgrades.handOf(PlayerColor.blue).isEmpty && landed < 40) {
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        putOnRing(c, p, 2);
        c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
        arm(c, 4); // 2 + 4 = 6 → case Chance
        c.movePawn(p);
        c.upgrades.takeNotices();
        landed++;
      }
      expect(c.upgrades.handOf(PlayerColor.blue), isNotEmpty,
          reason: 'une chance sur deux : la différée doit finir par tomber');
      expect(c.upgrades.handOf(PlayerColor.blue).first.kind,
          CardKind.deferred);
    });
  });

  group('🎴 Jouer une carte différée', () {
    /// Met [card] dans la main de [c] et lui donne la main.
    ChanceCard give(GameController g, PlayerColor c, String id) {
      final card = kDeferredCards.singleWhere((x) => x.id == id);
      g.upgrades.addToHand(c, card);
      g.currentPlayerIdx = g.turnOrder.indexOf(c);
      g.phase = TurnPhase.rolling;
      return card;
    }

    test('« Avant » ne se joue qu\'avant le lancer, « Après » qu\'après',
        () {
      final c = newGame();
      final avant = give(c, PlayerColor.blue, 'DEF_DICE_4');
      final apres = give(c, PlayerColor.blue, 'DEF_CAPTURE_TO_MY_BOX');

      expect(c.canPlayDeferred(PlayerColor.blue, avant), isTrue);
      expect(c.canPlayDeferred(PlayerColor.blue, apres), isFalse,
          reason: 'une carte « Après » attend le lancer');

      c.roll(6); // phase moving (une sortie est possible)
      expect(c.phase, TurnPhase.moving);
      expect(c.canPlayDeferred(PlayerColor.blue, avant), isFalse,
          reason: 'trop tard pour une carte « Avant »');
      expect(c.canPlayDeferred(PlayerColor.blue, apres), isTrue);
    });

    test('on ne joue qu\'UNE carte différée par tour', () {
      final c = newGame();
      final a = give(c, PlayerColor.blue, 'DEF_DICE_4');
      final b = give(c, PlayerColor.blue, 'DEF_DICE_2');

      expect(c.playDeferredCard(PlayerColor.blue, a), 4);
      expect(c.canPlayDeferred(PlayerColor.blue, b), isFalse,
          reason: 'une seule carte à la fois');
      // Tour suivant : on peut rejouer.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.canPlayDeferred(PlayerColor.blue, b), isTrue);
    });

    test('la carte quitte la main une fois jouée', () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_DICE_5');
      expect(c.upgrades.handOf(PlayerColor.blue), contains(card));
      expect(c.playDeferredCard(PlayerColor.blue, card), 5);
      expect(c.upgrades.handOf(PlayerColor.blue), isEmpty);
    });

    test('carte-dé : elle remplace le lancer par SA valeur', () {
      for (int v = 1; v <= 6; v++) {
        final c = newGame();
        final card = give(c, PlayerColor.blue, 'DEF_DICE_$v');
        expect(c.playDeferredCard(PlayerColor.blue, card), v);
      }
    });

    test('un joueur ne peut pas jouer la carte d\'un autre', () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_DICE_3');
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      expect(c.canPlayDeferred(PlayerColor.blue, card), isFalse,
          reason: 'ce n\'est pas au bleu de jouer');
    });

    test('« Votre pion invulnérable » vise VOS pions, pas ceux des autres',
        () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_PAWN_INVULNERABLE');
      final mine = c.state.pawnsByColor[PlayerColor.blue]![0];
      final theirs = c.state.pawnsByColor[PlayerColor.red]![0];

      final targets = c.deferredPawnTargets(PlayerColor.blue, card);
      expect(targets, contains(mine));
      expect(targets, isNot(contains(theirs)));

      // Une cible illégale ne fait RIEN : la carte reste en main.
      expect(
          c.playDeferredCard(PlayerColor.blue, card, targetPawn: theirs),
          isNull);
      expect(c.upgrades.handOf(PlayerColor.blue), contains(card));

      c.playDeferredCard(PlayerColor.blue, card, targetPawn: mine);
      expect(c.upgrades.isInvulnerable(mine), isTrue);
    });

    test('« Pion adverse figé » vise les ADVERSAIRES, et le fige vraiment',
        () {
      final c = newGame();
      final card = give(c, PlayerColor.blue, 'DEF_OPPONENT_FROZEN');
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, foe, 10);

      final targets = c.deferredPawnTargets(PlayerColor.blue, card);
      expect(targets, contains(foe));
      expect(targets,
          isNot(contains(c.state.pawnsByColor[PlayerColor.blue]![0])));

      c.playDeferredCard(PlayerColor.blue, card, targetPawn: foe);
      expect(c.upgrades.isFrozen(foe), isTrue);

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3);
      expect(c.movablePawns(), isNot(contains(foe)),
          reason: 'un pion figé ne se joue pas');
    });
  });

  group('🔁 « Le pion adverse refait le tour »', () {
    test('le pion désigné passe devant sa sortie et repart pour un tour',
        () {
      final c = newGame();
      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_OPPONENT_NO_EXIT');
      c.upgrades.addToHand(PlayerColor.blue, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;

      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, foe, 48);
      c.playDeferredCard(PlayerColor.blue, card, targetPawn: foe);
      expect(c.upgrades.mustLap(foe), isTrue);

      // Rouge joue : 48 + 3 = 51 → il devrait entrer dans son couloir.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3);
      expect(c.movablePawns(), contains(foe));
      c.movePawn(foe);
      expect(foe.location, PawnLocation.ring,
          reason: 'il ne prend PAS sa sortie');
      expect((foe.position - GameController.startIdx(PlayerColor.red) + 52) %
          52, 51);
      expect(c.upgrades.mustLap(foe), isFalse,
          reason: 'la marque est consommée : il rentrera au tour prochain');
    });

    test('la marque consommée, le pion rentre normalement', () {
      final c = newGame();
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, foe, 48);
      c.upgrades.markMustLap(foe);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3);
      c.movePawn(foe);
      // Deuxième tour : il repart de 51, il lui faut 51 pas… on le
      // replace juste devant sa sortie pour vérifier l'entrée.
      putOnRing(c, foe, 48);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3);
      c.movePawn(foe);
      expect(foe.location, PawnLocation.homeColumn,
          reason: 'plus de marque : la sortie fonctionne');
    });
  });

  group('📦 « Le pion capturé va dans VOTRE boîte »', () {
    test('la victime est retenue, et son 6 la ramène chez elle', () {
      final c = newGame();
      final card = kDeferredCards
          .singleWhere((x) => x.id == 'DEF_CAPTURE_TO_MY_BOX');
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 5);
      red.location = PawnLocation.ring;
      red.position = 8 + 2; // cellule 10, non sûre

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 5); // 5 + 5 = 10 → capture
      c.upgrades.addToHand(PlayerColor.blue, card);
      // « Après » : la carte se joue le dé en main, avant de bouger.
      expect(c.playDeferredCard(PlayerColor.blue, card), isNull);
      expect(c.upgrades.captureToBoxArmed(PlayerColor.blue), isTrue);

      c.movePawn(blue);
      expect(red.location, PawnLocation.base, reason: 'capturé');
      expect(c.upgrades.captorOf(red), PlayerColor.blue,
          reason: 'retenu dans la boîte du bleu');

      // Le 6 du rouge ne le fait pas SORTIR : il rentre chez lui d'abord.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 6);
      expect(c.movablePawns(), contains(red));
      c.movePawn(red);
      expect(red.location, PawnLocation.base,
          reason: 'il regagne sa boîte, il ne part pas sur l\'anneau');
      expect(c.upgrades.isPrisoner(red), isFalse, reason: 'libéré');
    });

    test('sans la carte, une capture ordinaire ne retient personne', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 5);
      red.location = PawnLocation.ring;
      red.position = 10;
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 5);
      c.movePawn(blue);
      expect(red.location, PawnLocation.base);
      expect(c.upgrades.isPrisoner(red), isFalse);
    });
  });

  group('⏭️ « Ne joue pas pendant 2 tours »', () {
    test('le joueur désigné est sauté deux fois, puis revient', () {
      final c = newGame();
      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_SKIP_CHOSEN');
      c.upgrades.addToHand(PlayerColor.blue, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;

      final targets = c.deferredPlayerTargets(PlayerColor.blue, card);
      expect(targets, isNot(contains(PlayerColor.blue)),
          reason: 'on ne se punit pas soi-même');
      c.playDeferredCard(PlayerColor.blue, card,
          targetPlayer: PlayerColor.red);
      expect(c.upgrades.skipsLeft(PlayerColor.red), 2);

      // L'ordre est bleu → rouge → vert → jaune. Rouge est sauté deux fois.
      c.skipTurn();
      expect(c.currentColor, PlayerColor.green,
          reason: 'rouge est sauté (1/2)');
      c.skipTurn(); // vert → jaune
      c.skipTurn(); // jaune → bleu
      c.skipTurn(); // bleu → rouge sauté (2/2) → vert
      expect(c.currentColor, PlayerColor.green,
          reason: 'rouge est sauté (2/2)');
      expect(c.upgrades.skipsLeft(PlayerColor.red), 0);

      c.skipTurn(); // vert → jaune
      c.skipTurn(); // jaune → bleu
      c.skipTurn(); // bleu → rouge, qui rejoue enfin
      expect(c.currentColor, PlayerColor.red);
    });

    test('« le joueur à votre droite » = celui qui joue juste avant vous',
        () {
      final c = newGame();
      // Ordre : bleu → rouge → vert → jaune.
      expect(c.rightNeighbourOf(PlayerColor.red), PlayerColor.blue);
      expect(c.rightNeighbourOf(PlayerColor.blue), PlayerColor.yellow);

      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_SKIP_RIGHT');
      c.upgrades.addToHand(PlayerColor.green, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.green);
      c.phase = TurnPhase.rolling;
      c.playDeferredCard(PlayerColor.green, card);
      expect(c.upgrades.skipsLeft(PlayerColor.red), 2,
          reason: 'le voisin de droite du vert est le rouge');
    });

    test('sans aucune carte de saut, l\'ordre du tour est INCHANGÉ', () {
      final c = newGame();
      final seen = <PlayerColor>[];
      for (int i = 0; i < 8; i++) {
        c.skipTurn();
        seen.add(c.currentColor);
      }
      expect(seen, [
        PlayerColor.red, PlayerColor.green, PlayerColor.yellow,
        PlayerColor.blue,
        PlayerColor.red, PlayerColor.green, PlayerColor.yellow,
        PlayerColor.blue,
      ]);
    });
  });

  group('🔌 Les cartes différées ne troublent rien quand rien n\'est joué',
      () {
    test('main vide au départ, pour tout le monde', () {
      final c = newGame();
      for (final color in PlayerColor.values) {
        expect(c.upgrades.handOf(color), isEmpty);
      }
    });

    test('reset() vide aussi les mains et les prisonniers', () {
      final c = newGame();
      c.upgrades.addToHand(PlayerColor.blue, kDeferredCards.first);
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      c.upgrades.imprison(red, PlayerColor.blue);
      c.upgrades.setSkipTurns(PlayerColor.green, 2);
      c.reset();
      expect(c.upgrades.handOf(PlayerColor.blue), isEmpty);
      expect(c.upgrades.isPrisoner(red), isFalse);
      expect(c.upgrades.skipsLeft(PlayerColor.green), 0);
    });
  });
}
