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
import 'package:ludopoly/game/board_path.dart';
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
    test('DEUX cases par couleur : la bonne devant le départ, la mauvaise '
        'au 44e pas', () {
      final all = <int>{};
      for (final c in PlayerColor.values) {
        final good = SpecialCells.goodVortexCell(c);
        final bad = SpecialCells.badVortexCell(c);
        expect(good, (GameController.startIdx(c) + 1) % GameController.ringSize,
            reason: '${c.name} : la bonne suit immédiatement le départ');
        expect(
            bad,
            (GameController.startIdx(c) + SpecialCells.lastStraightStep) %
                GameController.ringSize,
            reason: '${c.name} : la mauvaise est au 44e pas');
        expect(good, isNot(bad));
        expect(good, isNot(GameController.startIdx(c)),
            reason: 'ni l\'une ni l\'autre n\'est la case de départ');
        expect(bad, isNot(GameController.startIdx(c)));
        all..add(good)..add(bad);
      }
      expect(all.length, 8, reason: '8 cases distinctes en tout');
      // Jamais sur une case sûre, jamais sur une case Chance.
      for (final v in all) {
        expect(const {0, 13, 26, 39, 8, 21, 34, 47}.contains(v), isFalse);
        expect(SpecialCells.chanceCells.contains(v), isFalse);
      }
    });

    test('les mauvaises tombent sur les cases 81 vert · 99 jaune · '
        '143 bleu · 125 rouge de la grille 15×15', () {
      // Les quatre repères donnés à la main. On les recalcule depuis la
      // géométrie du plateau : c'est le verrou le plus dur de ce fichier.
      int gridIndex(int ringIdx) {
        final pos = ring[ringIdx].pos;
        return (pos.dy - 0.5).round() * 15 + (pos.dx - 0.5).round();
      }
      expect(gridIndex(SpecialCells.badVortexCell(PlayerColor.green)), 81);
      expect(gridIndex(SpecialCells.badVortexCell(PlayerColor.yellow)), 99);
      expect(gridIndex(SpecialCells.badVortexCell(PlayerColor.blue)), 143);
      expect(gridIndex(SpecialCells.badVortexCell(PlayerColor.red)), 125);
    });

    test('la dernière ligne droite est bien DROITE, et le virage vient '
        'après', () {
      // Le 44e pas ouvre 6 cases alignées ; le 50e tourne pour entrer dans
      // le couloir. C'est ce qui fait du 44e « la première case de la
      // dernière ligne droite ».
      for (final c in PlayerColor.values) {
        final start = GameController.startIdx(c);
        final run = [
          for (int s = SpecialCells.lastStraightStep;
              s <= GameController.lastRingStep - 1;
              s++)
            ring[(start + s) % GameController.ringSize].pos,
        ];
        expect(run.length, 6, reason: '${c.name} : 6 cases droites');
        final sameX = run.every((o) => o.dx == run.first.dx);
        final sameY = run.every((o) => o.dy == run.first.dy);
        expect(sameX || sameY, isTrue,
            reason: '${c.name} : le segment doit être rectiligne, $run');
        final before =
            ring[(start + SpecialCells.lastStraightStep - 1) % 52].pos;
        expect(sameX ? before.dx == run.first.dx : before.dy == run.first.dy,
            isFalse,
            reason: '${c.name} : la ligne droite commencerait plus tôt');
      }
    });

    test('chaque case mène à SON homologue d\'en face : 26 pas gagnés ou '
        'perdus', () {
      for (final c in PlayerColor.values) {
        final diag = SpecialCells.diagonalOf[c]!;
        expect(SpecialCells.goodVortexTarget(c),
            SpecialCells.goodVortexCell(diag));
        expect(SpecialCells.badVortexTarget(c),
            SpecialCells.badVortexCell(diag));

        int stepsOf(int cell) =>
            (cell - GameController.startIdx(c) + GameController.ringSize) %
            GameController.ringSize;
        // La bonne : de 1 pas à 27 → 26 gagnés.
        expect(stepsOf(SpecialCells.goodVortexTarget(c)) - 1, 26,
            reason: '${c.name} : la bonne fait gagner 26 pas');
        // La mauvaise : de 44 pas à 18 → 26 perdus.
        expect(
            SpecialCells.lastStraightStep -
                stepsOf(SpecialCells.badVortexTarget(c)),
            26,
            reason: '${c.name} : la mauvaise fait perdre 26 pas');
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

    test('se poser sur l\'une ou l\'autre case ne téléporte PAS', () {
      for (final step in [1, SpecialCells.lastStraightStep]) {
        final c = newGame();
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        putOnRing(c, p, step - 1);
        arm(c, 1);
        c.movePawn(p);
        expect((p.position - GameController.startIdx(PlayerColor.blue) + 52) %
            52, step);
        expect(c.upgrades.takeNotices(), isEmpty);
      }
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

  group('🌀 Les deux cases Vortex', () {
    GameController vortexGame() {
      final c = newGame();
      c.upgrades.vortexEnabled = true;
      return c;
    }

    /// Amène le pion 0 de [color] sur son [step]e pas par un vrai coup.
    Pawn landOn(GameController c, PlayerColor color, int step) {
      c.currentPlayerIdx = c.turnOrder.indexOf(color);
      final p = c.state.pawnsByColor[color]![0];
      putOnRing(c, p, step - 1);
      arm(c, 1);
      c.movePawn(p);
      return p;
    }

    test('LA BONNE : le pion file sur la première case de la diagonale, '
        'pour les 4 couleurs', () {
      for (final color in PlayerColor.values) {
        final c = vortexGame();
        final p = landOn(c, color, 1);
        final diag = SpecialCells.diagonalOf[color]!;
        expect(p.location, PawnLocation.ring);
        expect(p.position, SpecialCells.goodVortexCell(diag),
            reason: '${color.name} doit filer sur la 1re case de '
                '${diag.name}');
        expect(c.upgrades.takeNotices().single, contains('Vortex'));
      }
    });

    test('LA MAUVAISE : le pion revient sur la dernière ligne droite de la '
        'diagonale, pour les 4 couleurs', () {
      for (final color in PlayerColor.values) {
        final c = vortexGame();
        final p = landOn(c, color, SpecialCells.lastStraightStep);
        final diag = SpecialCells.diagonalOf[color]!;
        expect(p.location, PawnLocation.ring);
        expect(p.position, SpecialCells.badVortexCell(diag),
            reason: '${color.name} doit revenir sur le trou noir de '
                '${diag.name}');
        expect(c.upgrades.takeNotices().single, contains('Trou noir'));
      }
    });

    test('26 pas gagnés par la bonne, 26 perdus par la mauvaise', () {
      int stepsOf(Pawn p) =>
          (p.position - GameController.startIdx(p.color) +
              GameController.ringSize) %
          GameController.ringSize;

      final good = vortexGame();
      expect(stepsOf(landOn(good, PlayerColor.blue, 1)) - 1, 26);

      final bad = vortexGame();
      expect(
          SpecialCells.lastStraightStep -
              stepsOf(landOn(bad, PlayerColor.blue,
                  SpecialCells.lastStraightStep)),
          26);
    });

    test('chaque case a SA règle : aucune ne fait le travail de l\'autre',
        () {
      final c = vortexGame();
      // La bonne ne renvoie jamais en arrière.
      final p1 = landOn(c, PlayerColor.blue, 1);
      expect(p1.position, isNot(SpecialCells.badVortexCell(PlayerColor.green)));
      c.upgrades.takeNotices();
      // La mauvaise ne fait jamais gagner de terrain.
      final c2 = vortexGame();
      final p2 = landOn(c2, PlayerColor.blue, SpecialCells.lastStraightStep);
      expect(p2.position,
          isNot(SpecialCells.goodVortexCell(PlayerColor.green)));
    });

    test('arriver sur une case D\'EN FACE ne relance rien', () {
      for (final step in [1, SpecialCells.lastStraightStep]) {
        final c = vortexGame();
        final p = landOn(c, PlayerColor.blue, step);
        expect(c.upgrades.takeNotices().length, 1,
            reason: 'un seul saut, pas de rebond');
        // Le pion est posé sur une case du VERT : elle ne lui répond pas.
        final steps = (p.position - GameController.startIdx(PlayerColor.green) +
                52) %
            52;
        expect(steps, step, reason: 'c\'est bien la case homologue du vert');
      }
    });

    test('L\'INVULNÉRABILITÉ ne protège PAS du vortex — 4 couleurs et '
        'les deux cases', () {
      // L'invulnérabilité empêche d'être CAPTURÉ par un adversaire ; elle
      // n'empêche pas sa propre case de vous emporter.
      for (final color in PlayerColor.values) {
        for (final invulnerable in [false, true]) {
          for (final step in [1, SpecialCells.lastStraightStep]) {
            final c = vortexGame();
            c.currentPlayerIdx = c.turnOrder.indexOf(color);
            final p = c.state.pawnsByColor[color]![0];
            putOnRing(c, p, step - 1);
            if (invulnerable) {
              c.upgrades.setPawnState(p, CardPawnState.invulnerable);
              expect(c.upgrades.isInvulnerable(p), isTrue);
            }
            arm(c, 1);
            c.movePawn(p);
            final diag = SpecialCells.diagonalOf[color]!;
            final want = step == 1
                ? SpecialCells.goodVortexCell(diag)
                : SpecialCells.badVortexCell(diag);
            expect(p.location, PawnLocation.ring);
            expect(p.position, want,
                reason: '${color.name} '
                    '${invulnerable ? "invulnérable" : "ordinaire"}, '
                    'case ${step == 1 ? "bonne" : "trou noir"} : '
                    'elle doit agir dans tous les cas');
            c.upgrades.takeNotices();
          }
        }
      }
    });

    test('une carte qui DÉPOSE le pion sur son trou noir le déclenche', () {
      // « Tomber sur » la case ne veut pas dire « y arriver au dé » : une
      // carte qui vous y dépose vous y dépose quand même.
      final c = vortexGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(c, p, SpecialCells.lastStraightStep - 3);
      c.applyImmediateCard(card('IMM_PAWN_FORWARD_3'), p);
      expect(
          p.position,
          SpecialCells.badVortexCell(
              SpecialCells.diagonalOf[PlayerColor.blue]!),
          reason: 'la carte l\'a posé dessus : le trou noir répond');
    });


    test('les cases d\'une AUTRE couleur ne font rien', () {
      // Rouge traverse les deux cases du bleu sans être touché.
      for (final blueCell in [
        SpecialCells.goodVortexCell(PlayerColor.blue),
        SpecialCells.badVortexCell(PlayerColor.blue),
      ]) {
        final c = vortexGame();
        c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
        final p = c.state.pawnsByColor[PlayerColor.red]![0];
        final steps =
            (blueCell - GameController.startIdx(PlayerColor.red) + 52) % 52;
        putOnRing(c, p, steps - 1);
        arm(c, 1);
        c.movePawn(p);
        expect(p.position, blueCell, reason: 'rouge s\'y pose sans bouger');
        expect(c.upgrades.takeNotices(), isEmpty);
      }
    });

    test('la case de DÉPART ne déclenche rien : sortir de base reste une '
        'sortie ordinaire', () {
      for (final color in PlayerColor.values) {
        final c = vortexGame();
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        final p = c.state.pawnsByColor[color]![0];
        arm(c, 6);
        c.movePawn(p);
        expect(p.position, GameController.startIdx(color),
            reason: '${color.name} sort sur sa case de départ, point');
        expect(c.upgrades.takeNotices(), isEmpty);
      }
    });

    test('entrer dans son couloir final ne déclenche rien', () {
      for (final color in PlayerColor.values) {
        final c = vortexGame();
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        final p = c.state.pawnsByColor[color]![0];
        putOnRing(c, p, 48);
        arm(c, 3); // 51 → couloir case 0
        c.movePawn(p);
        expect(p.location, PawnLocation.homeColumn,
            reason: '${color.name} entre bien dans son couloir');
        expect(p.position, 0);
        expect(c.upgrades.takeNotices(), isEmpty);
      }
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
      // Le tour du tirage est déjà dépensé : le gel prend au suivant.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 3);
      expect(c.movablePawns(), isEmpty,
          reason: 'le seul pion en jeu est figé, et 3 ne sort pas de base');
      // Ce lancer sans coup jouable a passé la main : un 2e tour bleu est
      // compté. Encore un, et l'état expire.
      c.upgrades.onTurnCompleted(PlayerColor.blue);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 3);
      expect(c.movablePawns(), [blue], reason: 'libéré après 2 tours');
    });
  });

  group('🛡️ « Pion invulnérable » : la cible se DÉSIGNE', () {
    /// Amène le pion 0 de [color] sur sa case Chance avec la graine 41,
    /// qui donne « Pion invulnérable ».
    GameController landOnInvulnerable(PlayerColor color) {
      final c = newGame();
      c.upgrades
        ..chanceEnabled = true
        ..rng = math.Random(41);
      c.currentPlayerIdx = c.turnOrder.indexOf(color);
      final p = c.state.pawnsByColor[color]![0];
      putOnRing(c, p, 3);
      arm(c, 3); // 3 + 3 = 6 pas → la case Chance
      c.movePawn(p);
      return c;
    }

    test('la carte ATTEND sa cible au lieu de s\'appliquer d\'office', () {
      final c = landOnInvulnerable(PlayerColor.blue);
      final lander = c.state.pawnsByColor[PlayerColor.blue]![0];
      expect(c.upgrades.pendingChoice?.card.id, 'IMM_PAWN_INVULNERABLE');
      expect(c.upgrades.isInvulnerable(lander), isFalse,
          reason: 'rien n\'est posé tant que le pion n\'est pas désigné');
    });

    test('elle protège le pion DÉSIGNÉ, pas celui qui l\'a déclenchée', () {
      final c = landOnInvulnerable(PlayerColor.blue);
      final lander = c.state.pawnsByColor[PlayerColor.blue]![0];
      final chosen = c.state.pawnsByColor[PlayerColor.blue]![2];
      putOnRing(c, chosen, 25); // lui aussi sur l'anneau
      c.resolvePendingImmediate(chosen: chosen);
      expect(c.upgrades.isInvulnerable(chosen), isTrue);
      expect(c.upgrades.isInvulnerable(lander), isFalse);
    });

    test('sans choix, elle retombe sur le pion qui l\'a déclenchée', () {
      final c = landOnInvulnerable(PlayerColor.blue);
      final lander = c.state.pawnsByColor[PlayerColor.blue]![0];
      c.resolvePendingImmediate();
      expect(c.upgrades.isInvulnerable(lander), isTrue,
          reason: 'l\'effet a toujours lieu');
    });

    test('un ORDINATEUR désigne son pion le plus avancé', () {
      final c = landOnInvulnerable(PlayerColor.blue);
      final best = c.state.pawnsByColor[PlayerColor.blue]![1];
      putOnRing(c, best, 40); // bien plus avancé que celui qui a déclenché
      final target = c.pickAiImmediateTarget();
      expect(target, best, reason: 'c\'est le pion le plus précieux');
      c.resolvePendingImmediate(chosen: target);
      expect(c.upgrades.isInvulnerable(best), isTrue);
    });

    test('le choix se limite aux pions DÉJÀ SUR L\'ANNEAU', () {
      // L'invulnérabilité protège d'une capture, et l'on ne peut être
      // mangé que sur l'anneau : protéger un pion en boîte ou déjà dans
      // son couloir ne servirait à rien.
      final c = landOnInvulnerable(PlayerColor.blue);
      final pawns = c.state.pawnsByColor[PlayerColor.blue]!;
      final lander = pawns[0];                    // sur l'anneau
      final onRing = pawns[1];
      putOnRing(c, onRing, 20);
      pawns[2].location = PawnLocation.homeColumn;
      pawns[2].position = 2;
      // pawns[3] reste en boîte

      final targets =
          c.immediateTargets(c.upgrades.pendingChoice!.card, lander);
      expect(targets, containsAll([lander, onRing]));
      expect(targets, isNot(contains(pawns[2])),
          reason: 'un pion dans son couloir ne risque plus rien');
      expect(targets, isNot(contains(pawns[3])),
          reason: 'un pion en boîte non plus');
      expect(targets.every((p) => p.location == PawnLocation.ring), isTrue);
    });

    test('la carte DIFFÉRÉE suit la même règle', () {
      final c = newGame();
      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_PAWN_INVULNERABLE');
      c.upgrades.addToHand(PlayerColor.blue, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;
      final pawns = c.state.pawnsByColor[PlayerColor.blue]!;
      putOnRing(c, pawns[0], 12);

      final targets = c.deferredPawnTargets(PlayerColor.blue, card);
      expect(targets, [pawns[0]],
          reason: 'seul le pion sur l\'anneau peut être protégé');
    });

    test('un pion INVULNÉRABLE ne peut plus être visé par un adversaire',
        () {
      final c = newGame();
      final mine = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, mine, 10);
      c.upgrades.setPawnState(mine, CardPawnState.invulnerable);

      final freeze =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_OPPONENT_FROZEN');
      c.upgrades.addToHand(PlayerColor.blue, freeze);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;

      expect(c.deferredPawnTargets(PlayerColor.blue, freeze),
          isNot(contains(mine)),
          reason: 'ni capturé, ni contrôlé : il ne figure pas dans les '
              'cibles adverses');
      // Et le forcer ne marche pas non plus.
      expect(
          c.playDeferredCard(PlayerColor.blue, freeze, targetPawn: mine),
          isNull);
      expect(c.upgrades.isFrozen(mine), isFalse);
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
      // Le modificateur pèse sur CELUI QUI LANCE. On donne donc la main au
      // rouge avant de lui appliquer la carte.
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
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

    test('le vortex précède la capture : c\'est à la case d\'ARRIVÉE que '
        'l\'on mange, par l\'une comme par l\'autre', () {
      for (final good in [true, false]) {
        final c = newGame();
        c.upgrades.vortexEnabled = true;
        final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
        final red = c.state.pawnsByColor[PlayerColor.red]![0];
        final step = good ? 1 : SpecialCells.lastStraightStep;
        final target = good
            ? SpecialCells.goodVortexTarget(PlayerColor.blue)
            : SpecialCells.badVortexTarget(PlayerColor.blue);
        red.location = PawnLocation.ring;
        red.position = target;
        putOnRing(c, blue, step - 1);
        arm(c, 1);
        c.movePawn(blue);
        expect(blue.position, target);
        expect(red.location, PawnLocation.base,
            reason: 'capturé là où le vortex a déposé le pion');
      }
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
      expect(LudoUpgrades.handLimit, 4, reason: '4 places, comme la spec');
      final u = LudoUpgrades()..rng = math.Random(5);
      for (int i = 0; i < LudoUpgrades.handLimit; i++) {
        expect(u.addToHand(PlayerColor.blue, kDeferredCards[i]), isTrue);
      }
      expect(u.handOf(PlayerColor.blue).length, 4);
      expect(u.handIsFull(PlayerColor.blue), isTrue);
      expect(u.addToHand(PlayerColor.blue, kDeferredCards[4]), isFalse,
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
      // Elle ne se pose que sur un pion DÉJÀ SUR L'ANNEAU.
      putOnRing(c, mine, 12);
      putOnRing(c, theirs, 12);

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

  group('🚫 « Empêcher un pion adverse de sortir »', () {
    test('le pion désigné ne sort pas, ses camarades si', () {
      final c = newGame();
      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_OPPONENT_NO_EXIT');
      c.upgrades.addToHand(PlayerColor.blue, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;

      final foes = c.state.pawnsByColor[PlayerColor.red]!;
      c.playDeferredCard(PlayerColor.blue, card, targetPawn: foes[0]);
      expect(c.upgrades.cannotExit(foes[0]), isTrue);

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 6);
      final movable = c.movablePawns();
      expect(movable, isNot(contains(foes[0])),
          reason: 'celui-là reste dans sa boîte');
      expect(movable, containsAll([foes[1], foes[2], foes[3]]),
          reason: 'la carte ne vise QUE le pion désigné');
    });

    test('l\'occasion passée, la marque tombe : il sortira la fois d\'après',
        () {
      final c = newGame();
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      c.upgrades.markNoExit(foe);

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 6);
      expect(c.movablePawns(), isNot(contains(foe)));
      c.movePawn(c.movablePawns().first);
      c.skipTurn(); // le tour rouge se termine
      expect(c.upgrades.cannotExit(foe), isFalse,
          reason: 'l\'occasion s\'est présentée, elle est consommée');

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 6);
      expect(c.movablePawns(), contains(foe), reason: 'il peut sortir');
    });

    test('sans 6, l\'occasion ne s\'est pas présentée : la marque TIENT',
        () {
      final c = newGame();
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      c.upgrades.markNoExit(foe);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3); // aucun coup : la main passe
      expect(c.upgrades.cannotExit(foe), isTrue,
          reason: 'il n\'a jamais pu sortir, la carte n\'est pas dépensée');
    });

    test('un pion déjà sur l\'anneau n\'est pas une cible', () {
      final c = newGame();
      final card =
          kDeferredCards.singleWhere((x) => x.id == 'DEF_OPPONENT_NO_EXIT');
      c.upgrades.addToHand(PlayerColor.blue, card);
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      c.phase = TurnPhase.rolling;
      final foe = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, foe, 10);
      expect(c.deferredPawnTargets(PlayerColor.blue, card),
          isNot(contains(foe)),
          reason: 'la carte empêche de SORTIR : viser un pion déjà sorti '
              'n\'aurait aucun sens');
    });
  });

  group('📦 La règle spéciale après capture', () {
    test('la victime regagne la boîte de SON propriétaire, et lui faut un 6',
        () {
      final c = newGame();
      final card = kDeferredCards
          .singleWhere((x) => x.id == 'DEF_CAPTURE_TO_MY_BOX');
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(c, blue, 5);
      red.location = PawnLocation.ring;
      red.position = 10;

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.blue);
      arm(c, 5);
      c.upgrades.addToHand(PlayerColor.blue, card);
      expect(c.playDeferredCard(PlayerColor.blue, card), isNull);
      expect(c.upgrades.captureRuleArmed(PlayerColor.blue), isTrue);

      c.movePawn(blue);
      expect(red.location, PawnLocation.base, reason: 'capturé');
      expect(red.position, red.id, reason: 'dans SA propre boîte');

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 3);
      expect(c.movablePawns(), isNot(contains(red)),
          reason: 'sans 6, il reste en boîte');
      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      arm(c, 6);
      expect(c.movablePawns(), contains(red), reason: 'le 6 le fait sortir');
    });

    test('sans la carte, une capture ordinaire fait déjà cela', () {
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
      expect(c.upgrades.captureRuleArmed(PlayerColor.blue), isFalse);
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

    test('reset() vide aussi les mains et les marques', () {
      final c = newGame();
      c.upgrades.addToHand(PlayerColor.blue, kDeferredCards.first);
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      c.upgrades.markNoExit(red);
      c.upgrades.setSkipTurns(PlayerColor.green, 2);
      c.reset();
      expect(c.upgrades.handOf(PlayerColor.blue), isEmpty);
      expect(c.upgrades.cannotExit(red), isFalse);
      expect(c.upgrades.skipsLeft(PlayerColor.green), 0);
    });
  });
}
