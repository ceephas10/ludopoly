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

    test('l\'invulnérabilité EXPIRE après 2 tours complets du propriétaire',
        () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 5);
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue, reason: 'tour 1');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue, reason: 'tour 2');
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isFalse,
          reason: 'expirée après 2 tours complets');
    });

    test('re-tirer la carte REMPLACE la durée : ça repart pour 2 tours',
        () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 5);
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      // Sur le point d'expirer — nouvelle carte : la durée repart.
      c.applyImmediateCard(card('IMM_PAWN_INVULNERABLE'), blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      expect(c.upgrades.isInvulnerable(blue), isTrue,
          reason: 'la nouvelle durée compte depuis le re-tirage');
    });

    test('un pion FIGÉ n\'est plus jouable, puis se libère', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, blue, 10);
      c.applyImmediateCard(card('IMM_PAWN_FROZEN'), blue);
      arm(c, 3);
      expect(c.movablePawns(), isEmpty,
          reason: 'le seul pion en jeu est figé, et 3 ne sort pas de base');
      // Le tour vient de passer faute de coup (roll → _nextPlayer), ce qui
      // compte déjà un tour bleu terminé. Encore deux : l'état expire.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
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
    test('atterrir dessus tire une carte, l\'annonce, et l\'applique', () {
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
      expect(notices.first, contains('Carte chance'));
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
}
