// Tests de GAMEPLAY : des parties jouées coup par coup, par opposition à
// `rules_test.dart` qui teste chaque règle isolément.
//
// Chaque groupe suit une section du cahier des charges
// (`Documentation/LudoPoly_Regles.md`). Le scénario du bug signalé
// (« rouge 6 → pion sorti, puis rouge 3 → pion vert sorti ») est en bas,
// dans le groupe 🐞.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/board_path.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';

const _fourPlayers = [
  PlayerColor.blue,
  PlayerColor.red,
  PlayerColor.green,
  PlayerColor.yellow,
];

GameController newGame({
  List<PlayerColor> order = _fourPlayers,
  bool blocks = false,
  bool team = false,
}) {
  final c = GameController(
    turnOrder: List<PlayerColor>.from(order),
    state: GameState.initial(),
  );
  c.blockRule = blocks;
  c.teamMode = team;
  return c;
}

/// Joue un tour complet : lancer [value], puis déplacer le pion choisi par
/// [pick] parmi les pions jouables (par défaut le premier). Ne fait rien de
/// plus que ce que fait l'interface — le moteur décide de tout le reste.
void playTurn(GameController c, int value, {Pawn Function(List<Pawn>)? pick}) {
  c.roll(value);
  if (c.phase != TurnPhase.moving) return; // aucun coup jouable
  final options = c.movablePawns();
  if (options.isEmpty) return;
  c.movePawn(pick == null ? options.first : pick(options));
}

/// Tous les pions hors de leur base, tous joueurs confondus.
List<Pawn> outOfBase(GameController c) => c.state.allPawns
    .where((p) => p.location != PawnLocation.base)
    .toList();

/// Empreinte comparable de l'état des 16 pions.
List<String> boardFingerprint(GameController c) => [
      for (final p in c.state.allPawns)
        '${p.color.name}#${p.id}=${p.location.name}:${p.position}',
    ];

void main() {
  // ─────────────────────────────────────────────────────────────────
  group('§1 Structure fondamentale', () {
    test('4 joueurs × 4 pions, tous en base au départ', () {
      final c = newGame();
      expect(c.state.allPawns.length, 16);
      for (final color in PlayerColor.values) {
        expect(c.state.pawnsByColor[color]!.length, 4);
      }
      expect(outOfBase(c), isEmpty);
    });

    test('chaque pion démarre sur son propre emplacement de base', () {
      final c = newGame();
      for (final color in PlayerColor.values) {
        final slots =
            c.state.pawnsByColor[color]!.map((p) => p.position).toList();
        expect(slots, [0, 1, 2, 3]);
      }
    });

    test('une partie à 2 joueurs n\'alterne qu\'entre ces 2 couleurs', () {
      final c = newGame(order: [PlayerColor.blue, PlayerColor.red]);
      final seen = <PlayerColor>{};
      for (int i = 0; i < 8; i++) {
        seen.add(c.currentColor);
        c.skipTurn();
      }
      expect(seen, {PlayerColor.blue, PlayerColor.red});
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§2–§3 Cycle du dé et sortie de base', () {
    test('le cycle complet : lancer → choix → déplacement → tour suivant', () {
      final c = newGame();
      expect(c.phase, TurnPhase.rolling);
      c.roll(6);
      expect(c.phase, TurnPhase.moving, reason: 'il faut choisir un pion');
      final p = c.movablePawns().first;
      c.movePawn(p);
      expect(p.location, PawnLocation.ring);
      expect(c.phase, TurnPhase.rolling, reason: 'tour bonus après un 6');
    });

    test('1 à 5 depuis la base : rien ne sort, la main passe', () {
      for (final v in [1, 2, 3, 4, 5]) {
        final c = newGame();
        c.roll(v);
        expect(outOfBase(c), isEmpty, reason: 'dé=$v ne doit rien sortir');
        expect(c.currentColor, PlayerColor.red);
      }
    });

    test('un 6 ne sort qu\'UN pion, pas toute la base', () {
      final c = newGame();
      c.roll(6);
      c.movePawn(c.movablePawns().first);
      expect(outOfBase(c).length, 1);
    });

    test('le pion sorti arrive exactement sur la case départ de sa couleur',
        () {
      for (final color in PlayerColor.values) {
        final c = newGame();
        c.currentPlayerIdx = _fourPlayers.indexOf(color);
        c.roll(6);
        final p = c.movablePawns().first;
        c.movePawn(p);
        expect(p.position, GameController.startIdx(color),
            reason: '${color.name} doit sortir sur SA case');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§4 Déplacement : le compte doit être exact', () {
    test('un pion avance d\'exactement N cases', () {
      for (int v = 1; v <= 5; v++) {
        final c = newGame();
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        p.location = PawnLocation.ring;
        p.position = 10;
        c.roll(v);
        c.movePawn(p);
        expect(p.position, 10 + v, reason: 'dé=$v');
      }
    });

    test('le parcours boucle après la case 51', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.green]![0];
      p.location = PawnLocation.ring;
      p.position = 50;
      c.currentPlayerIdx = 2; // vert, départ 26
      c.roll(4);
      c.movePawn(p);
      expect(p.position, 2, reason: '50 → 51 → 0 → 1 → 2');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§5–§8 Collisions, étoiles et tours bonus', () {
    test('capture : l\'adversaire rentre en base, le captureur rejoue', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5; // case normale
      blue.location = PawnLocation.ring;
      blue.position = 1;
      playTurn(c, 4);
      expect(blue.position, 5);
      expect(red.location, PawnLocation.base);
      expect(red.position, red.id, reason: 'retour sur SON emplacement');
      expect(c.currentColor, PlayerColor.blue);
    });

    test('la capture ne laisse jamais 2 couleurs sur la même case', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 1;
      playTurn(c, 4);
      final onCell5 = c.state.allPawns
          .where((p) => p.location == PawnLocation.ring && p.position == 5)
          .map((p) => p.color)
          .toSet();
      expect(onCell5, {PlayerColor.blue});
    });

    test('les 4 étoiles et les 4 départs protègent de la capture', () {
      for (final safe in [8, 21, 34, 47, 0, 13, 26, 39]) {
        final c = newGame();
        final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
        final red = c.state.pawnsByColor[PlayerColor.red]![0];
        red.location = PawnLocation.ring;
        red.position = safe;
        blue.location = PawnLocation.ring;
        blue.position = (safe - 2 + 52) % 52;
        c.roll(2);
        if (c.phase == TurnPhase.moving) c.movePawn(blue);
        expect(red.location, PawnLocation.ring,
            reason: 'case $safe : le rouge doit être protégé');
      }
    });

    test('deux sources de tour bonus : le 6 ET la capture', () {
      // 6 sans capture
      final a = newGame();
      final ap = a.state.pawnsByColor[PlayerColor.blue]![0];
      ap.location = PawnLocation.ring;
      ap.position = 2;
      playTurn(a, 6);
      expect(a.currentColor, PlayerColor.blue, reason: 'bonus du 6');

      // capture sans 6
      final b = newGame();
      final bp = b.state.pawnsByColor[PlayerColor.blue]![0];
      final br = b.state.pawnsByColor[PlayerColor.red]![0];
      br.location = PawnLocation.ring;
      br.position = 5;
      bp.location = PawnLocation.ring;
      bp.position = 3;
      playTurn(b, 2);
      expect(b.currentColor, PlayerColor.blue, reason: 'bonus de la capture');
    });

    test('un déplacement banal ne donne PAS de tour bonus', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.ring;
      p.position = 2;
      playTurn(c, 3);
      expect(c.currentColor, PlayerColor.red);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§9 Série de trois 6', () {
    test('6, 6, 6 → tour annulé et dernier pion renvoyé en base', () {
      final c = newGame();
      playTurn(c, 6); // sortie
      final p = outOfBase(c).single;
      expect(c.consecutiveSixes, 1);
      playTurn(c, 6); // avance
      expect(c.consecutiveSixes, 2);
      expect(c.currentColor, PlayerColor.blue);
      c.roll(6); // 3e → sanction
      expect(c.currentColor, PlayerColor.red, reason: 'le tour est perdu');
      expect(p.location, PawnLocation.base);
      expect(c.consecutiveSixes, 0, reason: 'compteur remis à zéro');
    });

    test('6, 6, 2 → pas de sanction, la série retombe', () {
      final c = newGame();
      playTurn(c, 6);
      playTurn(c, 6);
      expect(c.consecutiveSixes, 2);
      playTurn(c, 2);
      expect(c.consecutiveSixes, 0);
      expect(outOfBase(c).length, 1, reason: 'aucun pion sanctionné');
    });

    test('la série est propre à un tour, pas cumulée entre joueurs', () {
      final c = newGame();
      playTurn(c, 6); // bleu
      playTurn(c, 3); // bleu avance, main au rouge
      expect(c.currentColor, PlayerColor.red);
      expect(c.consecutiveSixes, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§10–§12 Couloir final, dépassement et arrivée', () {
    test('après 50 pas, le pion entre dans SON couloir', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.ring;
      p.position = 50; // 50 pas depuis le départ 0
      playTurn(c, 1);
      expect(p.location, PawnLocation.homeColumn);
      expect(p.position, 0, reason: '51e pas = 1re case du couloir');
    });

    test('un pion ne peut pas entrer dans le couloir d\'une autre couleur',
        () {
      final c = newGame();
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 12; // 51 pas depuis le départ rouge (13)
      c.currentPlayerIdx = 1;
      playTurn(c, 3);
      expect(red.location, PawnLocation.homeColumn);
      // Le couloir est indexé par la couleur du pion : c'est bien celui du
      // rouge, jamais celui du bleu qu'il vient de longer.
      expect(red.color, PlayerColor.red);
    });

    test('tout dépassement de la maison est illégal', () {
      for (int pos = 0; pos <= 4; pos++) {
        final besoin = 5 - pos;
        for (int v = besoin + 1; v <= 6; v++) {
          final c = newGame();
          final blues = c.state.pawnsByColor[PlayerColor.blue]!;
          // Les 3 autres pions sont déjà rentrés : seul celui du couloir
          // pourrait jouer, donc la liste vide prouve bien le refus.
          for (int i = 1; i < 4; i++) {
            blues[i].location = PawnLocation.home;
          }
          final p = blues[0];
          p.location = PawnLocation.homeColumn;
          p.position = pos;
          c.roll(v);
          expect(c.movablePawns(), isEmpty,
              reason: 'couloir $pos avec dé $v doit être refusé');
        }
      }
    });

    test('seul le compte EXACT fait rentrer le pion', () {
      for (int pos = 0; pos <= 4; pos++) {
        final c = newGame();
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        p.location = PawnLocation.homeColumn;
        p.position = pos;
        playTurn(c, 5 - pos);
        expect(p.location, PawnLocation.home, reason: 'depuis couloir $pos');
      }
    });

    test('un pion arrivé ne bouge plus jamais', () {
      for (int v = 1; v <= 6; v++) {
        final c = newGame();
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        p.location = PawnLocation.home;
        c.roll(v);
        expect(c.movablePawns().contains(p), isFalse, reason: 'dé=$v');
      }
    });

    test('l\'arrivée à la maison donne un tour bonus', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.homeColumn;
      p.position = 1;
      playTurn(c, 4);
      expect(p.location, PawnLocation.home);
      expect(c.currentColor, PlayerColor.blue);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§13 Ordre des joueurs', () {
    test('rotation bleu → rouge → vert → jaune → bleu', () {
      final c = newGame();
      final order = <PlayerColor>[];
      for (int i = 0; i < 5; i++) {
        order.add(c.currentColor);
        c.skipTurn();
      }
      expect(order, [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
        PlayerColor.blue,
      ]);
    });

    test('une chaîne de 6 garde la main au même joueur', () {
      final c = newGame();
      playTurn(c, 6);
      expect(c.currentColor, PlayerColor.blue);
      playTurn(c, 6);
      expect(c.currentColor, PlayerColor.blue);
    });

    test('un lancer sans coup jouable passe la main immédiatement', () {
      final c = newGame();
      c.roll(4); // tout en base
      expect(c.currentColor, PlayerColor.red);
      expect(c.phase, TurnPhase.rolling);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('§18 Classement au fil de la partie', () {
    test('une partie à 2 joueurs se termine dès le 1er arrivé', () {
      final c = newGame(order: [PlayerColor.blue, PlayerColor.red]);
      final blues = c.state.pawnsByColor[PlayerColor.blue]!;
      for (int i = 0; i < 3; i++) {
        blues[i].location = PawnLocation.home;
      }
      blues[3].location = PawnLocation.homeColumn;
      blues[3].position = 4;
      playTurn(c, 1);
      expect(c.phase, TurnPhase.gameOver);
      expect(c.ranking, [PlayerColor.blue, PlayerColor.red]);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('↩️ Undo / Redo sur une séquence jouée', () {
    test('undo puis redo rendent exactement le même plateau', () {
      final c = newGame();
      c.pushHistory('bleu · dé 6');
      playTurn(c, 6);
      final apres = boardFingerprint(c);
      final tourApres = c.currentColor;

      expect(c.stepBack(), isTrue);
      expect(outOfBase(c), isEmpty, reason: 'retour avant la sortie');

      expect(c.stepForward(), isTrue);
      expect(boardFingerprint(c), apres);
      expect(c.currentColor, tourApres);
    });

    test('redo restaure aussi le dé et la série de 6', () {
      final c = newGame();
      c.pushHistory('bleu · dé 6');
      playTurn(c, 6);
      final sixes = c.consecutiveSixes;
      c.stepBack();
      expect(c.consecutiveSixes, 0);
      c.stepForward();
      expect(c.consecutiveSixes, sixes);
    });

    test('jouer un nouveau coup annule la possibilité de rejouer', () {
      final c = newGame();
      c.pushHistory('bleu · dé 6');
      playTurn(c, 6);
      c.stepBack();
      expect(c.redoDepth, 1);
      c.pushHistory('bleu · dé 3'); // nouvelle branche
      expect(c.redoDepth, 0, reason: 'la branche annulée est abandonnée');
      expect(c.stepForward(), isFalse);
    });

    test('undo/redo en escalier sur 3 coups', () {
      final c = newGame();
      final marques = <List<String>>[boardFingerprint(c)];
      for (final v in [6, 6, 6]) {
        c.pushHistory('bleu · dé $v');
        c.roll(v);
        if (c.phase == TurnPhase.moving) c.movePawn(c.movablePawns().first);
        marques.add(boardFingerprint(c));
      }
      // On remonte tout
      for (int i = 3; i >= 1; i--) {
        expect(boardFingerprint(c), marques[i]);
        c.stepBack();
      }
      expect(boardFingerprint(c), marques[0]);
      // On redescend tout
      for (int i = 1; i <= 3; i++) {
        c.stepForward();
        expect(boardFingerprint(c), marques[i]);
      }
      expect(c.redoDepth, 0);
    });

    test('undo d\'une capture rend le pion capturé ET annule le bonus', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 3;
      c.pushHistory('bleu · dé 2');
      playTurn(c, 2);
      expect(red.location, PawnLocation.base);
      expect(c.currentColor, PlayerColor.blue);

      c.stepBack();
      expect(red.location, PawnLocation.ring);
      expect(red.position, 5);
      expect(blue.position, 3);
      expect(c.diceValue, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('🎲 Le dé affiché reste sur la dernière valeur sortie', () {
    test('bleu fait 5 → la valeur reste 5 quand la main passe au rouge', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      blue.location = PawnLocation.ring;
      blue.position = 2;
      playTurn(c, 5);
      expect(c.currentColor, PlayerColor.red, reason: 'la main a passé');
      expect(c.diceValue, 0, reason: 'rouge n\'a pas encore lancé');
      expect(c.lastRoll, 5,
          reason: 'le dé affiché garde 5 en attendant que rouge joue');
    });

    test('la valeur ne change qu\'au lancer suivant', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      blue.location = PawnLocation.ring;
      blue.position = 2;
      playTurn(c, 5);
      expect(c.lastRoll, 5);
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 15;
      playTurn(c, 3);
      expect(c.lastRoll, 3);
      expect(c.currentColor, PlayerColor.green);
    });

    test('un lancer sans coup jouable met quand même à jour l\'affichage', () {
      final c = newGame();
      c.roll(4); // tout en base → la main passe immédiatement
      expect(c.lastRoll, 4);
      expect(c.diceValue, 0);
    });

    test('avant le tout premier lancer, aucune valeur n\'est sortie', () {
      expect(newGame().lastRoll, 0);
    });

    test('reset remet le dé à zéro', () {
      final c = newGame();
      c.roll(6);
      expect(c.lastRoll, 6);
      c.reset();
      expect(c.lastRoll, 0);
    });

    test('undo / redo restaurent la valeur affichée', () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      blue.location = PawnLocation.ring;
      blue.position = 2;
      c.pushHistory('bleu · dé 5');
      playTurn(c, 5);
      expect(c.lastRoll, 5);
      c.stepBack();
      expect(c.lastRoll, 0, reason: 'retour avant le lancer');
      c.stepForward();
      expect(c.lastRoll, 5);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('🎞️ Trajet case par case (pathFor)', () {
    test('un dé de N donne N cases traversées', () {
      for (int v = 1; v <= 6; v++) {
        final c = newGame();
        final p = c.state.pawnsByColor[PlayerColor.blue]![0];
        p.location = PawnLocation.ring;
        p.position = 10;
        c.roll(v);
        expect(c.pathFor(p, v).length, v, reason: 'dé=$v');
      }
    });

    test('les cases sont consécutives et finissent à l\'arrivée', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.ring;
      p.position = 10;
      c.roll(4);
      final path = c.pathFor(p, 4);
      expect(path.map((s) => s.position).toList(), [11, 12, 13, 14]);
      c.movePawn(p);
      expect(p.position, path.last.position,
          reason: 'la dernière étape est la position réelle');
    });

    test('le trajet suit la boucle du plateau', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.green]![0];
      p.location = PawnLocation.ring;
      p.position = 50;
      c.currentPlayerIdx = 2;
      c.roll(3);
      expect(c.pathFor(p, 3).map((s) => s.position).toList(), [51, 0, 1]);
    });

    test('le trajet passe du ring au couloir puis à la maison', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.ring;
      p.position = 49; // 49 pas faits
      c.roll(6);       // 50, puis couloir 0..4
      final path = c.pathFor(p, 6);
      expect(path.map((s) => '${s.location.name}:${s.position}').toList(), [
        'ring:50',
        'homeColumn:0',
        'homeColumn:1',
        'homeColumn:2',
        'homeColumn:3',
        'homeColumn:4',
      ]);
    });

    test('la dernière étape est la maison quand le compte est exact', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.homeColumn;
      p.position = 2;
      c.roll(3);
      final path = c.pathFor(p, 3);
      expect(path.last.location, PawnLocation.home);
      expect(path.length, 3);
    });

    test('une sortie de base ne compte qu\'UNE étape', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      c.roll(6);
      final path = c.pathFor(p, 6);
      expect(path.length, 1, reason: 'téléportation, pas un parcours');
      expect(path.single.position, GameController.startIdx(PlayerColor.blue));
    });

    test('un coup illégal ne produit aucun trajet', () {
      final c = newGame();
      final p = c.state.pawnsByColor[PlayerColor.blue]![0];
      p.location = PawnLocation.homeColumn;
      p.position = 4; // 1 case de la maison
      c.roll(5);
      expect(c.pathFor(p, 5), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('🐞 Bug signalé — « rouge 6 sort un pion, puis rouge 3 »', () {
    test('après le 3, SEUL le pion rouge a bougé', () {
      final c = newGame();
      c.currentPlayerIdx = _fourPlayers.indexOf(PlayerColor.red);

      // rouge fait 6 → un pion rouge sort
      playTurn(c, 6);
      final sorti = outOfBase(c).single;
      expect(sorti.color, PlayerColor.red);
      expect(c.currentColor, PlayerColor.red, reason: 'bonus du 6');

      final avant = boardFingerprint(c);

      // rouge fait 3 → son pion avance de 3, personne d'autre ne bouge
      playTurn(c, 3);
      expect(sorti.position, GameController.startIdx(PlayerColor.red) + 3);
      for (final p in c.state.allPawns) {
        if (p == sorti) continue;
        expect(p.location, PawnLocation.base,
            reason: '$p ne devait pas bouger');
      }
      expect(avant.length, boardFingerprint(c).length);
    });

    test('aucun pion vert ne peut sortir sur un 3', () {
      final c = newGame();
      c.currentPlayerIdx = _fourPlayers.indexOf(PlayerColor.green);
      c.roll(3);
      final verts = c.state.pawnsByColor[PlayerColor.green]!;
      expect(verts.every((p) => p.location == PawnLocation.base), isTrue);
      expect(c.movablePawns(), isEmpty);
    });

    test('le 3 de rouge passe la main au VERT (et non l\'inverse)', () {
      final c = newGame();
      c.currentPlayerIdx = _fourPlayers.indexOf(PlayerColor.red);
      playTurn(c, 6); // sortie, bonus
      playTurn(c, 3); // avance, fin de tour
      expect(c.currentColor, PlayerColor.green,
          reason: 'c\'est au vert de JOUER, pas au rouge de bouger un vert');
      expect(c.phase, TurnPhase.rolling,
          reason: 'le vert doit encore lancer son dé');
    });

    test('un lancer ne déplace jamais un pion d\'une autre couleur', () {
      // Toutes les couleurs ont un pion sur le ring ; on lance pour chacune
      // et on vérifie que seul SON pion bouge.
      for (final color in _fourPlayers) {
        final c = newGame();
        for (final col in _fourPlayers) {
          final p = c.state.pawnsByColor[col]![0];
          p.location = PawnLocation.ring;
          p.position = (GameController.startIdx(col) + 1) % 52;
        }
        c.currentPlayerIdx = _fourPlayers.indexOf(color);
        final avant = {
          for (final p in c.state.allPawns) p: p.position,
        };
        playTurn(c, 3);
        for (final p in c.state.allPawns) {
          if (p.color == color) continue;
          expect(p.position, avant[p],
              reason: 'lancer de ${color.name} : $p a bougé');
        }
      }
    });
  });

  // §32 — Le pion quitte l'anneau PILE en face de son couloir.
  //
  // Ces tests relient le moteur au DESSIN du plateau. `lastRingStep` n'est
  // pas un réglage libre : la bouche du couloir de chaque couleur est
  // orthogonalement adjacente à une case d'anneau précise, et c'est elle
  // qui fixe le nombre de pas. Un pas de plus et le pion se retrouve sur la
  // case d'angle, en diagonale de sa bouche — il dépasse visiblement la
  // ligne de son couloir avant d'y entrer.
  group('🏠 Le pion quitte l\'anneau en face de sa bouche de couloir', () {
    // 1re case du couloir de chaque couleur, en unités de case, telle que
    // `_homeColumnCenter` la dessine dans main.dart.
    const mouth = {
      PlayerColor.blue:   Offset(7.5, 13.5),
      PlayerColor.red:    Offset(1.5, 7.5),
      PlayerColor.green:  Offset(7.5, 1.5),
      PlayerColor.yellow: Offset(13.5, 7.5),
    };

    Offset ringPos(PlayerColor color, int steps) =>
        ring[(GameController.startIdx(color) + steps) %
                GameController.ringSize]
            .pos;

    test('la dernière case d\'anneau touche la bouche du couloir', () {
      for (final color in _fourPlayers) {
        final d = ringPos(color, GameController.lastRingStep) - mouth[color]!;
        expect(d.dx.abs() + d.dy.abs(), closeTo(1.0, 1e-9),
            reason: '${color.name} : la case à '
                '${GameController.lastRingStep} pas doit être collée à '
                'sa bouche ${mouth[color]}');
      }
    });

    test('un pas de plus dépasserait la ligne du couloir', () {
      for (final color in _fourPlayers) {
        final d =
            ringPos(color, GameController.lastRingStep + 1) - mouth[color]!;
        expect(d.dx.abs() + d.dy.abs(), greaterThan(1.0),
            reason: '${color.name} : ${GameController.lastRingStep + 1} pas '
                'tombe en diagonale de la bouche — c\'est le dépassement');
      }
    });

    test('le total pour rentrer = 50 anneau + 5 couloir + 1 maison', () {
      expect(GameController.lastRingStep, 50);
      expect(GameController.totalStepsToHome, 56);
    });

    test('aucun pion ne repasse sur sa propre case de départ', () {
      // Le pion quitte l'anneau AVANT d'avoir bouclé : les cases entre sa
      // bouche et son départ ne sont parcourues que par les autres couleurs.
      for (final color in _fourPlayers) {
        final c = newGame();
        final p = c.state.pawnsByColor[color]![0];
        c.currentPlayerIdx = _fourPlayers.indexOf(color);
        final start = GameController.startIdx(color);
        p.location = PawnLocation.ring;
        p.position = (start + GameController.lastRingStep - 1) %
            GameController.ringSize;
        final path = c.pathFor(p, 6);
        final ringCells = path
            .where((s) => s.location == PawnLocation.ring)
            .map((s) => s.position);
        expect(ringCells, isNot(contains(start)),
            reason: '${color.name} ne doit jamais revenir sur son départ');
      }
    });
  });

  // §31 — Retour à contre-sens du pion capturé. Le pion mangé rembobine son
  // parcours depuis la case de capture jusqu'à sa flèche d'entrée, puis
  // rentre dans sa base. Purement géométrique : `returnPathFor` ne modifie
  // rien, elle décrit le trajet que l'animation doit suivre.
  group('↩︎ Retour à contre-sens du pion capturé (returnPathFor)', () {
    test('le trajet remonte l\'anneau case par case jusqu\'à la flèche', () {
      final c = newGame();
      // Bleu démarre en 0 ; capturé en 5, il a donc fait 5 pas.
      final path = c.returnPathFor(
          PlayerColor.blue, const PawnStep(PawnLocation.ring, 5), 2);
      expect(path.length, 6,
          reason: '5 cases d\'anneau (4→0, flèche incluse) + la base');
      expect(path.map((s) => s.position).toList().sublist(0, 5),
          [4, 3, 2, 1, 0],
          reason: 'à contre-sens, case de capture exclue, flèche incluse');
      expect(path.last.location, PawnLocation.base);
      expect(path.last.position, 2, reason: 'le créneau de base demandé');
    });

    test('la dernière case d\'anneau est la flèche d\'entrée de la couleur',
        () {
      for (final color in _fourPlayers) {
        final start = GameController.startIdx(color);
        final captured = (start + 9) % 52;
        final path = c0().returnPathFor(
            color, PawnStep(PawnLocation.ring, captured), 0);
        final lastRing = path[path.length - 2];
        expect(lastRing.location, PawnLocation.ring);
        expect(lastRing.position, start,
            reason: '${color.name} doit finir sur sa flèche $start');
      }
    });

    test('le trajet franchit le raccord 51 → 0 sans trou', () {
      // Jaune démarre en 39 ; capturé en 3, il a franchi le raccord.
      final path = c0().returnPathFor(
          PlayerColor.yellow, const PawnStep(PawnLocation.ring, 3), 0);
      final ring = path.sublist(0, path.length - 1);
      expect(ring.first.position, 2);
      expect(ring.last.position, 39);
      for (int i = 1; i < ring.length; i++) {
        final prev = ring[i - 1].position;
        final cur = ring[i].position;
        expect((prev - cur + 52) % 52, 1,
            reason: 'saut entre $prev et $cur');
      }
    });

    test('un pion capturé juste après sa flèche ne fait qu\'un pas', () {
      final c = newGame();
      final start = GameController.startIdx(PlayerColor.red);
      final path = c.returnPathFor(
          PlayerColor.red, PawnStep(PawnLocation.ring, start + 1), 3);
      expect(path.length, 2);
      expect(path.first, isA<PawnStep>()
          .having((s) => s.position, 'position', start));
      expect(path.last.location, PawnLocation.base);
    });

    test('hors anneau, le retour est un saut direct vers la base', () {
      final path = c0().returnPathFor(
          PlayerColor.green, const PawnStep(PawnLocation.homeColumn, 2), 1);
      expect(path.length, 1);
      expect(path.single.location, PawnLocation.base);
      expect(path.single.position, 1);
    });

    test('une sortie de base sur un 6 va EN AVANT, jamais à contre-sens', () {
      // Invariant demandé : le rembobinage n'appartient qu'à la capture.
      // Une sortie de base est un saut unique vers la flèche d'entrée.
      for (final color in _fourPlayers) {
        final c = newGame(order: [color]);
        final pawn = c.state.pawnsByColor[color]![0];
        c.roll(6);
        final path = c.pathFor(pawn, 6);
        expect(path.length, 1, reason: '${color.name} : sortie = 1 étape');
        expect(path.single.location, PawnLocation.ring);
        expect(path.single.position, GameController.startIdx(color),
            reason: '${color.name} sort SUR sa flèche, pas avant');
      }
    });

    test('le trajet de retour ne déplace aucun pion', () {
      final c = newGame();
      final avant = {for (final p in c.state.allPawns) p: p.toString()};
      c.returnPathFor(
          PlayerColor.blue, const PawnStep(PawnLocation.ring, 20), 0);
      for (final p in c.state.allPawns) {
        expect(p.toString(), avant[p], reason: '$p a été modifié');
      }
    });

    test('une capture réelle produit un retour cohérent avec la case mangée',
        () {
      final c = newGame();
      final blue = c.state.pawnsByColor[PlayerColor.blue]![0];
      final red = c.state.pawnsByColor[PlayerColor.red]![0];
      red.location = PawnLocation.ring;
      red.position = 5;
      blue.location = PawnLocation.ring;
      blue.position = 1;
      playTurn(c, 4); // bleu 1 → 5, mange rouge
      expect(red.location, PawnLocation.base);
      // Le retour part de la case où rouge a été mangé, pas de sa base.
      final path = c.returnPathFor(
          PlayerColor.red, const PawnStep(PawnLocation.ring, 5), red.position);
      expect(path.last.location, PawnLocation.base);
      expect(path[path.length - 2].position,
          GameController.startIdx(PlayerColor.red));
    });
  });
}

/// Contrôleur jetable pour les tests purement géométriques de
/// [GameController.returnPathFor], qui ne lisent aucun état de partie.
GameController c0() => newGame();
