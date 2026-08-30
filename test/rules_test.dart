// Cahier de tests des règles — reprend une à une les situations du tableau
// « 16. Pour éviter les bugs » de la spec. Tout se joue sur le MOTEUR, sans
// interface : c'est exactement ce que la spec demande (les animations ne
// décident jamais des règles).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';

/// Contrôleur neuf avec les 4 couleurs dans l'ordre bleu → rouge → vert → jaune.
GameController newGame({bool team = false}) {
  final c = GameController(
    turnOrder: const [
      PlayerColor.blue,
      PlayerColor.red,
      PlayerColor.green,
      PlayerColor.yellow,
    ],
    state: GameState.initial(),
  );
  c.teamMode = team;
  return c;
}

/// Place [p] sur le ring à [steps] pas de sa case départ.
void putOnRing(Pawn p, int steps) {
  p.location = PawnLocation.ring;
  p.position =
      (GameController.startIdx(p.color) + steps) % GameController.ringSize;
}

void main() {
  group('🎲 Dé et sortie de base', () {
    test('1-5 avec tous les pions en base → aucun mouvement possible', () {
      for (final v in [1, 2, 3, 4, 5]) {
        final c = newGame();
        c.roll(v);
        // Aucun coup → le moteur a déjà passé la main.
        expect(c.currentColor, PlayerColor.red,
            reason: 'dé=$v aurait dû passer le tour');
      }
    });

    test('6 avec pion en base → sortie possible', () {
      final c = newGame();
      c.roll(6);
      expect(c.phase, TurnPhase.moving);
      expect(c.movablePawns().length, 4);
    });

    test('6 → le pion sort sur SA case départ', () {
      final c = newGame();
      c.roll(6);
      final p = c.movablePawns().first;
      c.movePawn(p);
      expect(p.location, PawnLocation.ring);
      expect(p.position, GameController.startIdx(PlayerColor.blue));
    });

    test('6 → tour supplémentaire', () {
      final c = newGame();
      c.roll(6);
      c.movePawn(c.movablePawns().first);
      expect(c.currentColor, PlayerColor.blue);
      expect(c.phase, TurnPhase.rolling);
    });
  });

  group('🔄 Trois 6 consécutifs', () {
    test('3 × 6 → tour perdu et pion renvoyé à la base', () {
      final c = newGame();
      c.roll(6);
      final p = c.movablePawns().first;
      c.movePawn(p); // 1er six, tour bonus
      c.roll(6);
      c.movePawn(c.movablePawns().firstWhere((x) => x == p)); // 2e six
      expect(c.currentColor, PlayerColor.blue);
      c.roll(6); // 3e six → annulation
      expect(c.currentColor, PlayerColor.red);
      expect(p.location, PawnLocation.base);
    });

    test('la série se remet à zéro sur un non-6', () {
      final c = newGame();
      c.roll(6);
      c.movePawn(c.movablePawns().first);
      expect(c.consecutiveSixes, 1);
      c.roll(3);
      expect(c.consecutiveSixes, 0);
    });
  });

  group('⚔️ Captures', () {
    test('arrivée sur un adversaire (case normale) → capture + rejeu', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      // Case 5 : ni départ, ni étoile → capture autorisée.
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 2;
      c.roll(3);
      c.movePawn(blue);
      expect(red.location, PawnLocation.base, reason: 'le rouge est capturé');
      expect(c.currentColor, PlayerColor.blue, reason: 'capture → rejoue');
    });

    test('arrivée sur une case étoilée occupée → AUCUNE capture', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 8; // étoile
      blue.location = PawnLocation.ring;
      blue.position = 5;
      c.roll(3);
      c.movePawn(blue);
      expect(blue.position, 8);
      expect(red.location, PawnLocation.ring, reason: 'protégé par l\'étoile');
      expect(c.currentColor, PlayerColor.red, reason: 'pas de capture → tour suivant');
    });

    test('en équipe, pas de capture entre partenaires', () {
      final c = newGame(team: true);
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final green = c.state.pawnsByColor[PlayerColor.green]![0];
      green.location = PawnLocation.ring;
      green.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 2;
      c.roll(3);
      c.movePawn(blue);
      expect(green.location, PawnLocation.ring);
    });
  });

  group('🏠 Couloir final et arrivée', () {
    test('déplacement dépassant HOME → mouvement interdit', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      blue.location = PawnLocation.homeColumn;
      blue.position = 3; // 2 pas de la maison
      c.roll(5);
      expect(c.movablePawns(), isEmpty);
    });

    test('arrivée EXACTE → le pion rentre à la maison + rejeu', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      blue.location = PawnLocation.homeColumn;
      blue.position = 2; // 3 pas de la maison
      c.roll(3);
      c.movePawn(blue);
      expect(blue.location, PawnLocation.home);
      expect(c.currentColor, PlayerColor.blue, reason: 'arrivée → rejoue');
    });

    test('pion déjà HOME → impossible à déplacer', () {
      final c = newGame();
      for (final p in c.state.pawnsByColor[PlayerColor.blue]!) {
        p.location = PawnLocation.home;
      }
      c.roll(6);
      expect(c.movablePawns(), isEmpty);
    });

    test('le couloir final est privé : 50 pas puis 5 cases de couloir', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(blue, 49);
      c.roll(3); // 52 → couloir index 1
      c.movePawn(blue);
      expect(blue.location, PawnLocation.homeColumn);
      expect(blue.position, 1);
    });
  });

  group('🏆 Victoire et classement 1er–4e', () {
    test('4 pions au centre → 1er au classement, la partie continue', () {
      final c = newGame();
      final blues = c.state.pawnsByColor[PlayerColor.blue]!;
      for (int i = 0; i < 3; i++) {
        blues[i].location = PawnLocation.home;
      }
      blues[3].location = PawnLocation.homeColumn;
      blues[3].position = 2;
      c.roll(3);
      c.movePawn(blues[3]);
      expect(c.ranking, [PlayerColor.blue]);
      expect(c.winner, PlayerColor.blue);
      expect(c.phase, isNot(TurnPhase.gameOver),
          reason: 'les autres jouent encore pour la 2e place');
    });

    test('un joueur classé est sauté dans l\'ordre des tours', () {
      final c = newGame();
      final blues = c.state.pawnsByColor[PlayerColor.blue]!;
      for (int i = 0; i < 3; i++) {
        blues[i].location = PawnLocation.home;
      }
      blues[3].location = PawnLocation.homeColumn;
      blues[3].position = 2;
      c.roll(3);
      c.movePawn(blues[3]); // bleu termine, rejoue... mais n'a plus de coup
      c.roll(6);
      expect(c.currentColor, isNot(PlayerColor.blue));
    });

    test('il ne reste qu\'un joueur → fin de partie, il est dernier', () {
      final c = newGame();
      // Bleu, rouge, vert déjà rentrés ; on fait rentrer le dernier pion vert.
      for (final col in [PlayerColor.blue, PlayerColor.red]) {
        for (final p in c.state.pawnsByColor[col]!) {
          p.location = PawnLocation.home;
        }
        c.ranking.add(col);
      }
      final greens = c.state.pawnsByColor[PlayerColor.green]!;
      for (int i = 0; i < 3; i++) {
        greens[i].location = PawnLocation.home;
      }
      greens[3].location = PawnLocation.homeColumn;
      greens[3].position = 4;
      c.currentPlayerIdx = 2; // vert
      c.roll(1);
      c.movePawn(greens[3]);
      expect(c.phase, TurnPhase.gameOver);
      expect(c.ranking, [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ]);
    });

    test('recomputeStandings attribue aussi la dernière place', () {
      final c = newGame();
      for (final col in [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
      ]) {
        for (final p in c.state.pawnsByColor[col]!) {
          p.location = PawnLocation.home;
        }
      }
      c.recomputeStandings();
      expect(c.phase, TurnPhase.gameOver);
      expect(c.ranking.last, PlayerColor.yellow,
          reason: 'le joueur restant est classé dernier d\'office');
      expect(c.ranking.length, 4);
    });

    test('recomputeStandings rattrape les pions posés à la main', () {
      final c = newGame();
      for (final p in c.state.pawnsByColor[PlayerColor.red]!) {
        p.location = PawnLocation.home;
      }
      c.recomputeStandings();
      expect(c.ranking, [PlayerColor.red]);
      expect(c.winner, PlayerColor.red);
      // On ressort un pion : le rang doit être retiré.
      c.state.pawnsByColor[PlayerColor.red]![0].location = PawnLocation.base;
      c.recomputeStandings();
      expect(c.ranking, isEmpty);
      expect(c.winner, isNull);
    });
  });

  group('🤖 IA locale', () {
    test('préfère la capture au simple déplacement', () {
      final c = newGame();
      final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
      final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5; // case normale
      b0.location = PawnLocation.ring;
      b0.position = 2; // +3 → capture
      b1.location = PawnLocation.ring;
      b1.position = 20; // +3 → rien
      c.roll(3);
      expect(c.pickAiPawn(), b0);
    });

    test('préfère rentrer à la maison', () {
      final c = newGame();
      final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
      final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
      b0.location = PawnLocation.homeColumn;
      b0.position = 2; // +3 → maison
      b1.location = PawnLocation.ring;
      b1.position = 20;
      c.roll(3);
      expect(c.pickAiPawn(), b0);
    });

    test('ne renvoie rien quand aucun coup n\'est jouable', () {
      final c = newGame();
      c.roll(2); // tous en base → tour déjà passé
      expect(c.pickAiPawn(), isNull);
    });

    test('jamais de blocage : phase moving implique toujours un coup', () {
      // C'est l'invariant qui permet à l'interface de faire jouer une IA
      // sans jamais rendre la main. S'il tombait, la partie resterait
      // figée en attendant un clic qui ne viendrait pas.
      final c = newGame();
      final rng = math.Random(4242);
      for (int turn = 0; turn < 3000; turn++) {
        if (c.phase == TurnPhase.gameOver) break;
        c.roll(c.pickDiceValue(rng));
        if (c.phase == TurnPhase.moving) {
          final choice = c.pickAiPawn();
          expect(choice, isNotNull,
              reason: 'tour $turn : phase moving mais aucun pion à jouer');
          c.movePawn(choice!);
        }
      }
    });

    test('une partie 100 % ordinateur va jusqu\'au bout toute seule', () {
      final c = newGame();
      final rng = math.Random(20260830);
      int turns = 0;
      while (c.phase != TurnPhase.gameOver && turns < 20000) {
        turns++;
        c.roll(c.pickDiceValue(rng));
        if (c.phase == TurnPhase.moving) {
          c.movePawn(c.pickAiPawn()!);
        }
      }
      expect(c.phase, TurnPhase.gameOver,
          reason: 'la partie doit se terminer sans aucune intervention '
              '(bloquée après $turns tours)');
      expect(c.ranking.length, 4, reason: 'les 4 places doivent être prises');
    });

    test('après un Retour, la partie repart et va quand même au bout', () {
      // L'interface figeait ici : elle ne replanifiait pas l'IA après un
      // rembobinage. Côté moteur, l'état rendu par stepBack doit être
      // jouable comme n'importe quel autre.
      final c = newGame();
      final rng = math.Random(99);
      for (int i = 0; i < 40 && c.phase != TurnPhase.gameOver; i++) {
        // L'interface empile un instantané AVANT chaque lancer ; c'est ce
        // qui alimente le bouton Retour. On fait pareil.
        c.pushHistory('tour $i');
        c.roll(c.pickDiceValue(rng));
        if (c.phase == TurnPhase.moving) c.movePawn(c.pickAiPawn()!);
      }
      expect(c.undoDepth, greaterThan(1));
      c.stepBack();
      c.stepBack();
      expect(c.phase, isNot(TurnPhase.gameOver));

      int turns = 0;
      while (c.phase != TurnPhase.gameOver && turns < 20000) {
        turns++;
        c.roll(c.pickDiceValue(rng));
        if (c.phase == TurnPhase.moving) {
          final choice = c.pickAiPawn();
          expect(choice, isNotNull, reason: 'bloqué au tour $turns');
          c.movePawn(choice!);
        }
      }
      expect(c.phase, TurnPhase.gameOver,
          reason: 'la partie doit se terminer après un rembobinage');
    });
  });

  group('↩️ Retour arrière (stepBack)', () {
    test('annule le lancer ET le déplacement joué avec', () {
      final c = newGame();
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      putOnRing(red, 0);
      c.currentPlayerIdx = 1; // rouge
      final before = red.position;

      c.pushHistory('red · dé 4');
      c.roll(4);
      c.movePawn(red);
      expect(red.position, isNot(before));
      expect(c.currentColor, PlayerColor.green, reason: 'le tour a avancé');

      expect(c.stepBack(), isTrue);
      expect(red.position, before, reason: 'le pion est revenu');
      expect(c.currentColor, PlayerColor.red, reason: 'le tour est revenu');
      expect(c.diceValue, 0, reason: 'le dé n\'a pas encore été lancé');
      expect(c.phase, TurnPhase.rolling);
    });

    test('restaure un pion capturé dans sa base', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 2;

      c.pushHistory('blue · dé 3');
      c.roll(3);
      c.movePawn(blue);
      expect(red.location, PawnLocation.base);

      c.stepBack();
      expect(red.location, PawnLocation.ring);
      expect(red.position, 5, reason: 'le capturé retrouve sa case');
      expect(blue.position, 2);
    });

    test('annule aussi un classement acquis', () {
      final c = newGame();
      final blues = c.state.pawnsByColor[PlayerColor.blue]!;
      for (int i = 0; i < 3; i++) {
        blues[i].location = PawnLocation.home;
      }
      blues[3].location = PawnLocation.homeColumn;
      blues[3].position = 2;

      c.pushHistory('blue · dé 3');
      c.roll(3);
      c.movePawn(blues[3]);
      expect(c.ranking, [PlayerColor.blue]);
      expect(c.winner, PlayerColor.blue);

      c.stepBack();
      expect(c.ranking, isEmpty);
      expect(c.winner, isNull);
      expect(blues[3].location, PawnLocation.homeColumn);
    });

    test('plusieurs pressions remontent coup par coup', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(blue, 0);
      final p0 = blue.position;

      c.pushHistory('blue · dé 6');
      c.roll(6);
      c.movePawn(blue); // 6 → rejoue
      final p1 = blue.position;
      c.pushHistory('blue · dé 6');
      c.roll(6);
      c.movePawn(blue);
      expect(blue.position, isNot(p1));

      c.stepBack();
      expect(blue.position, p1);
      c.stepBack();
      expect(blue.position, p0);
      expect(c.undoDepth, 0);
      expect(c.stepBack(), isFalse, reason: 'pile vide');
    });

    test('reset vide la pile d\'annulation', () {
      final c = newGame();
      c.pushHistory('test');
      expect(c.undoDepth, 1);
      c.reset();
      expect(c.undoDepth, 0);
    });
  });

  group('🔄 Ordre des tours', () {
    test('rotation simple sur un 1-5 joué', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      putOnRing(blue, 0);
      c.roll(3);
      c.movePawn(blue);
      expect(c.currentColor, PlayerColor.red);
    });

    test('reset remet le classement et l\'ordre à zéro', () {
      final c = newGame();
      for (final p in c.state.pawnsByColor[PlayerColor.blue]!) {
        p.location = PawnLocation.home;
      }
      c.recomputeStandings();
      expect(c.ranking, isNotEmpty);
      c.reset();
      expect(c.ranking, isEmpty);
      expect(c.winner, isNull);
      expect(c.currentColor, PlayerColor.blue);
      expect(c.state.allPawns.every((p) => p.location == PawnLocation.base),
          isTrue);
    });
  });
}
