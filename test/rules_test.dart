// Cahier de tests des règles — reprend une à une les situations du tableau
// « 16. Pour éviter les bugs » de la spec. Tout se joue sur le MOTEUR, sans
// interface : c'est exactement ce que la spec demande (les animations ne
// décident jamais des règles).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/ai_difficulty.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';

/// Contrôleur neuf avec les 4 couleurs dans l'ordre bleu → rouge → vert → jaune.
GameController newGame({
  bool team = false,
  AiDifficulty ai = AiDifficulty.expert,
}) {
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
  // EXPERT par défaut dans les tests, pas le niveau par défaut du jeu :
  // ces cas décrivent la stratégie complète, et seul un niveau sans erreur
  // volontaire ([AiDifficulty.blunderRate] nul) la joue de façon
  // déterministe. L'échelle elle-même est testée dans son propre groupe.
  c.aiDifficulty = ai;
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

    test('à coups égaux, l\'IA évite la case où elle serait capturable', () {
      final c = newGame();
      final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
      final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      // Deux avances ordinaires équivalentes… sauf qu'un rouge rôde à
      // 3 pas derrière la case visée par b1.
      putOnRing(b0, 30);
      putOnRing(b1, 20);
      red.location = PawnLocation.ring;
      red.position = (GameController.startIdx(PlayerColor.blue) + 18) % 52;
      c.roll(2); // b0 → pas 32 (tranquille), b1 → pas 22 (rouge à 4 pas)
      expect(c.pickAiPawn(), b0,
          reason: 'b1 irait s\'exposer sous le pion rouge');
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

  // Échelle de difficulté. Trois leviers seulement — erreur volontaire,
  // conscience du risque, anticipation — et AUCUN d'eux ne touche au dé.
  group('🎚️ Niveaux de difficulté de l\'IA', () {
    test('le niveau par défaut du jeu est Moyen', () {
      final c = GameController(
        turnOrder: const [PlayerColor.blue, PlayerColor.red],
        state: GameState.initial(),
      );
      expect(c.aiDifficulty, AiDifficulty.moyen);
      expect(AiDifficulty.defaultLevel, AiDifficulty.moyen);
    });

    test('un seul niveau actif : l\'enum ne permet pas d\'en cumuler', () {
      final c = newGame(ai: AiDifficulty.debutant);
      c.aiDifficulty = AiDifficulty.imbattable;
      expect(c.aiDifficulty, AiDifficulty.imbattable);
    });

    test('Expert et au-dessus ne se trompent JAMAIS', () {
      for (final level in [
        AiDifficulty.expert,
        AiDifficulty.grandMaitre,
        AiDifficulty.imbattable,
      ]) {
        expect(level.blunderRate, 0.0, reason: level.label);
      }
    });

    test('Débutant se trompe bien plus souvent que Moyen', () {
      expect(AiDifficulty.debutant.blunderRate,
          greaterThan(AiDifficulty.moyen.blunderRate));
      expect(AiDifficulty.moyen.blunderRate, greaterThan(0.0));
    });

    test('Débutant rate souvent une capture que l\'Expert prend toujours',
        () {
      // Même position pour les deux : capture évidente contre déplacement
      // banal. On compte sur 400 tirages, avec un RNG graine — le Débutant
      // doit visiblement passer à côté, l\'Expert jamais.
      int capturesFor(AiDifficulty level, int seed) {
        int taken = 0;
        for (int i = 0; i < 400; i++) {
          final c = GameController(
            turnOrder: const [PlayerColor.blue, PlayerColor.red],
            state: GameState.initial(),
            rng: math.Random(seed + i),
          );
          c.aiDifficulty = level;
          final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
          final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
          final red = c.state.pawnsByColor[PlayerColor.red]![0];
          red.location = PawnLocation.ring;
          red.position = 5;
          b0.location = PawnLocation.ring;
          b0.position = 2; // +3 → capture
          b1.location = PawnLocation.ring;
          b1.position = 20; // +3 → rien
          c.roll(3);
          if (identical(c.pickAiPawn(), b0)) taken++;
        }
        return taken;
      }

      expect(capturesFor(AiDifficulty.expert, 1000), 400,
          reason: 'l\'Expert ne laisse jamais passer la capture');
      final debutant = capturesFor(AiDifficulty.debutant, 1000);
      expect(debutant, lessThan(350),
          reason: 'le Débutant doit rater des captures, il en a pris '
              '\$debutant/400');
    });

    test('seul Expert et au-dessus fuit une case exposée', () {
      // b0 avance vers une case juste devant un pion rouge : la case est à
      // portée de capture. b1 a un déplacement équivalent, sans danger.
      Pawn choiceAt(AiDifficulty level) {
        final c = newGame(ai: level);
        final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
        final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
        final red = c.state.pawnsByColor[PlayerColor.red]![0];
        red.location = PawnLocation.ring;
        red.position = 1; // menace les cases 2..7
        b0.location = PawnLocation.ring;
        b0.position = 2; // +3 → case 5, à portée du rouge
        b1.location = PawnLocation.ring;
        b1.position = 30; // +3 → case 33, tranquille
        c.roll(3);
        return c.pickAiPawn()!;
      }

      // Moyen ne voit pas le danger : il prend le pion le plus avancé.
      expect(choiceAt(AiDifficulty.expert).id, 1,
          reason: 'l\'Expert évite la case exposée');
      expect(choiceAt(AiDifficulty.grandMaitre).id, 1,
          reason: 'le Grand Maître aussi');
      expect(choiceAt(AiDifficulty.imbattable).id, 1,
          reason: 'l\'Imbattable aussi');
    });

    test('l\'anticipation ne renverse jamais une arrivée à la maison', () {
      for (final level in [
        AiDifficulty.grandMaitre,
        AiDifficulty.imbattable,
      ]) {
        final c = newGame(ai: level);
        final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
        final b1 = c.state.pawnsByColor[PlayerColor.blue]![1];
        b0.location = PawnLocation.homeColumn;
        b0.position = 2; // +3 → maison
        b1.location = PawnLocation.ring;
        b1.position = 20;
        c.roll(3);
        expect(c.pickAiPawn(), b0, reason: level.label);
      }
    });

    test('AUCUN niveau ne touche au dé', () {
      // Le tirage doit rester identique pour tous les niveaux à graine
      // égale : la difficulté ne joue que sur le choix du pion.
      List<int> rolls(AiDifficulty level) {
        final c = newGame(ai: level);
        final rng = math.Random(4242);
        return [for (int i = 0; i < 200; i++) c.pickDiceValue(rng)];
      }

      final reference = rolls(AiDifficulty.debutant);
      for (final level in AiDifficulty.values) {
        expect(rolls(level), reference, reason: level.label);
      }
    });

    test('tout niveau joue un coup dès qu\'il en existe un', () {
      // Filet anti-blocage : quel que soit le niveau, phase moving implique
      // un pion choisi. C'est la garantie qui manquait quand l'IA se figeait.
      for (final level in AiDifficulty.values) {
        final c = newGame(ai: level);
        final rng = math.Random(level.index + 1);
        for (int turn = 0; turn < 300; turn++) {
          if (c.phase == TurnPhase.gameOver) break;
          c.roll(c.pickDiceValue(rng));
          if (c.phase == TurnPhase.moving) {
            final choice = c.pickAiPawn();
            expect(choice, isNotNull,
                reason: '\${level.label} : bloqué au tour \$turn');
            c.movePawn(choice!);
          }
        }
      }
    });
  });

  // Mode Rapide — sans attente de tour. Chaque couleur mène SON tour avec
  // son propre dé, sa propre série de 6 et sa propre phase.
  group('⚡ Mode Rapide — sans attente de tour', () {
    GameController fast() {
      final c = newGame();
      c.fastMode = true;
      c.resetSeats();
      return c;
    }

    test('OFF par défaut : le Ludo classique ne change pas', () {
      expect(newGame().fastMode, isFalse);
    });

    test('jouer une couleur ne passe PAS la main à la suivante', () {
      final c = fast();
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 20;
      c.runAsSeat(PlayerColor.red, () {
        c.roll(3);
        c.movePawn(red);
      });
      // Rouge a joué un 3 sans capture : en mode ordinaire la main
      // passerait. Ici, son propre siège revient simplement en attente.
      expect(c.seatOf(PlayerColor.red).phase, TurnPhase.rolling);
      expect(red.position, 23);
    });

    test('chaque couleur garde SON dé, indépendamment des autres', () {
      final c = fast();
      // Chacune a besoin d'un coup JOUABLE, sinon son tour se termine
      // aussitôt et son dé retombe à 0 — ce qui est la règle normale.
      for (final color in [PlayerColor.red, PlayerColor.green]) {
        final p = c.state.pawnsByColor[color]![0];
        p.location = PawnLocation.ring;
        p.position = GameController.startIdx(color) + 2;
      }
      c.runAsSeat(PlayerColor.blue, () => c.roll(6));
      c.runAsSeat(PlayerColor.red, () => c.roll(2));
      c.runAsSeat(PlayerColor.green, () => c.roll(4));

      expect(c.seatOf(PlayerColor.blue).diceValue, 6);
      expect(c.seatOf(PlayerColor.red).diceValue, 2);
      expect(c.seatOf(PlayerColor.green).diceValue, 4);
    });

    test('la série de 6 est propre à chaque couleur', () {
      final c = fast();
      // Bleu enchaîne deux 6 ; rouge lance entre les deux et ne doit rien
      // casser de la série de bleu.
      final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
      c.runAsSeat(PlayerColor.blue, () {
        c.roll(6);
        c.movePawn(b0);
      });
      c.runAsSeat(PlayerColor.red, () => c.roll(1));
      c.runAsSeat(PlayerColor.blue, () => c.roll(6));

      expect(c.seatOf(PlayerColor.blue).consecutiveSixes, 2);
      expect(c.seatOf(PlayerColor.red).consecutiveSixes, 0);
    });

    test('la règle des trois 6 s\'applique par couleur', () {
      final c = fast();
      final b0 = c.state.pawnsByColor[PlayerColor.blue]![0];
      c.runAsSeat(PlayerColor.blue, () {
        c.roll(6);
        c.movePawn(b0); // sortie
      });
      c.runAsSeat(PlayerColor.blue, () {
        c.roll(6);
        c.movePawn(b0);
      });
      expect(b0.location, PawnLocation.ring);
      c.runAsSeat(PlayerColor.blue, () => c.roll(6)); // 3e six
      expect(b0.location, PawnLocation.base,
          reason: 'le 3e six renvoie le dernier pion joué en base');
    });

    test('une capture entre deux couleurs qui jouent chacune de leur côté',
        () {
      final c = fast();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 1;
      c.runAsSeat(PlayerColor.blue, () {
        c.roll(4);
        c.movePawn(blue);
      });
      expect(red.location, PawnLocation.base, reason: 'rouge est mangé');
      expect(blue.position, 5);
    });

    test('le classement reste COMPLET : la partie continue après le 1er',
        () {
      final c = fast();
      for (final p in c.state.pawnsByColor[PlayerColor.blue]!) {
        p.location = PawnLocation.home;
      }
      final b = c.state.pawnsByColor[PlayerColor.blue]![3];
      b.location = PawnLocation.homeColumn;
      b.position = 4;
      c.runAsSeat(PlayerColor.blue, () {
        c.roll(1);
        c.movePawn(b);
      });
      expect(c.ranking, [PlayerColor.blue]);
      expect(c.phase, isNot(TurnPhase.gameOver),
          reason: 'trois couleurs doivent encore jouer pour leur place');
    });

    test('la fin de partie est GLOBALE, pas rangée dans un siège', () {
      final c = fast();
      // Trois couleurs rentrent : la 4e prend la dernière place et la
      // partie s'arrête pour tout le monde.
      for (final color in [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
      ]) {
        for (final p in c.state.pawnsByColor[color]!) {
          p.location = PawnLocation.home;
        }
        final last = c.state.pawnsByColor[color]![3];
        last.location = PawnLocation.homeColumn;
        last.position = 4;
        c.runAsSeat(color, () {
          c.roll(1);
          c.movePawn(last);
        });
      }
      expect(c.phase, TurnPhase.gameOver);
      expect(c.ranking.length, 4);
      // Une couleur ne peut plus agir sur un plateau terminé.
      final yellow = c.state.pawnsByColor[PlayerColor.yellow]![0];
      c.runAsSeat(PlayerColor.yellow, () => c.roll(6));
      expect(yellow.location, PawnLocation.base);
    });

    test('un retour arrière rend AUSSI les tours en cours des autres', () {
      final c = fast();
      for (final color in [PlayerColor.red, PlayerColor.green]) {
        final p = c.state.pawnsByColor[color]![0];
        p.location = PawnLocation.ring;
        p.position = GameController.startIdx(color) + 2;
      }
      c.runAsSeat(PlayerColor.red, () => c.roll(4));
      c.runAsSeat(PlayerColor.green, () => c.roll(2));
      c.pushHistory('avant bleu');
      c.runAsSeat(PlayerColor.blue, () => c.roll(6));

      c.stepBack();
      expect(c.seatOf(PlayerColor.red).diceValue, 4,
          reason: 'le tour de rouge doit survivre au retour arrière');
      expect(c.seatOf(PlayerColor.green).diceValue, 2);
    });

    test('repasser en mode ordinaire rétablit la rotation', () {
      final c = fast();
      c.fastMode = false;
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 20;
      c.currentPlayerIdx = 1; // rouge
      c.roll(3);
      c.movePawn(red);
      expect(c.currentColor, PlayerColor.green,
          reason: 'la main repasse au joueur suivant');
    });
  });

  // Un 6 doit TOUJOURS laisser le choix : sortir un pion, ou en avancer un.
  // C'est la règle la plus fondamentale du Ludo, et l'interdit d'empilement
  // l'avait cassée — voir wouldSelfStack.
  group('🎲 Sur un 6, le joueur garde toujours le choix', () {
    test('2e six consécutif : les 4 pions restent jouables', () {
      for (final color in PlayerColor.values) {
        final c = newGame();
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        c.roll(6);
        expect(c.movablePawns().length, 4,
            reason: '${color.name} : 1er six');
        c.movePawn(c.state.pawnsByColor[color]![0]);
        // Le pion est sur la case de départ ; le six suivant doit encore
        // proposer les trois pions de base EN PLUS de celui qui est sorti.
        c.roll(6);
        expect(c.movablePawns().length, 4,
            reason: '${color.name} : le 2e six ne laisse plus le choix '
                '— ${c.movablePawns()}');
      }
    });

    test('sortir reste possible même avec un pion sur sa case de départ', () {
      for (final color in PlayerColor.values) {
        final c = newGame();
        c.currentPlayerIdx = c.turnOrder.indexOf(color);
        final onStart = c.state.pawnsByColor[color]![0];
        onStart.location = PawnLocation.ring;
        onStart.position = GameController.startIdx(color);
        for (final p in c.state.pawnsByColor[color]!.skip(1)) {
          expect(c.wouldSelfStack(p, 6), isFalse,
              reason: '${color.name} : une sortie de base ne doit JAMAIS '
                  'être bloquée');
        }
      }
    });

    test('trois six d\'affilée laissent le choix à chaque fois', () {
      final c = newGame();
      c.roll(6);
      expect(c.movablePawns().length, 4, reason: '1er six');
      c.movePawn(c.state.pawnsByColor[PlayerColor.blue]![0]);
      c.roll(6);
      expect(c.movablePawns().length, 4, reason: '2e six');
      c.movePawn(c.state.pawnsByColor[PlayerColor.blue]![1]);
      // Le 3e six annule le tour (§9) : c'est une autre règle, préservée.
      c.roll(6);
      expect(c.consecutiveSixes, 0,
          reason: 'la règle des trois 6 doit rester intacte');
    });

    test('l\'interdit d\'empilement ANNEAU → ANNEAU reste entier', () {
      final c = newGame();
      final a = c.state.pawnsByColor[PlayerColor.blue]![0];
      final b = c.state.pawnsByColor[PlayerColor.blue]![1];
      a.location = PawnLocation.ring;
      a.position = 10;
      b.location = PawnLocation.ring;
      b.position = 7; // +3 tomberait sur a
      expect(c.wouldSelfStack(b, 3), isTrue,
          reason: 'deux pions d\'une couleur ne peuvent pas partager une '
              'case du ring');
      c.roll(3);
      expect(c.movablePawns(), isNot(contains(b)));
    });

    test('un seul coup possible reste joué tout seul', () {
      // L'automatisme ne doit PAS disparaître : il n'y a simplement rien
      // à choisir quand un seul pion peut bouger.
      final c = newGame();
      final only = c.state.pawnsByColor[PlayerColor.blue]![0];
      only.location = PawnLocation.ring;
      only.position = 10;
      c.roll(3); // pas de 6 : aucune sortie possible
      expect(c.movablePawns(), [only]);
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
