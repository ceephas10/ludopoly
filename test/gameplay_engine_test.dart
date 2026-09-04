// Le squelette JSON, joué pour de vrai. Chaque règle de ce premier jet —
// sortie de base sur 6, déplacement et virages, capture, tours — est
// vérifiée en faisant tourner le moteur sur `assets/gameplay/board.json`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/gameplay/engine.dart';
import 'package:ludopoly/gameplay/spec.dart';
import 'package:ludopoly/gameplay/token.dart';

const _asset = 'assets/gameplay/board.json';
late final BoardSpec spec;

GameplayEngine game({List<TokenColor>? players}) =>
    GameplayEngine(spec, players: players);

Token tok(GameplayEngine g, TokenColor c, [int i = 0]) => g.tokens[c]![i];

/// Le JSON valide, modifié par [f], ré-encodé.
String mutated(void Function(Map<String, dynamic> root) f) {
  final root =
      jsonDecode(File(_asset).readAsStringSync()) as Map<String, dynamic>;
  f(root);
  return jsonEncode(root);
}

List<int> ids(Iterable<CellSpec> cells) => [for (final c in cells) c.id];
List<EventType> types(List<GameEvent> ev) => [for (final e in ev) e.type];

void main() {
  setUpAll(() {
    spec = BoardSpec.parse(File(_asset).readAsStringSync());
  });

  group('📄 Le JSON, lu et vérifié', () {
    test('52 cases, numérotées 0 à 51 dans l\'ordre', () {
      expect(spec.size, 52);
      expect([for (final c in spec.ring) c.id], List.generate(52, (i) => i));
    });

    test('4 couleurs jouables, dans l\'ordre de l\'anneau', () {
      expect(spec.colors, [
        TokenColor.blue,
        TokenColor.red,
        TokenColor.green,
        TokenColor.yellow,
      ]);
      expect(spec.startOf, {
        TokenColor.blue: 0,
        TokenColor.red: 13,
        TokenColor.green: 26,
        TokenColor.yellow: 39,
      });
    });

    test('violet et orange : déclarés dans l\'enum, sans case de départ', () {
      expect(spec.cellTypes, contains('startPurple'));
      expect(spec.colors, isNot(contains(TokenColor.purple)));
      expect(spec.colors, isNot(contains(TokenColor.orange)));
    });

    test('les 8 cases sûres', () {
      expect(ids(spec.ring.where((c) => c.safe)), [0, 8, 13, 21, 26, 34, 39, 47]);
    });

    test('vortex, trous noirs et chance', () {
      expect(ids(spec.cellsOf(CellKind.vortex)), [1, 14, 27, 40]);
      expect(ids(spec.cellsOf(CellKind.death)), [5, 18, 31, 44]);
      expect(ids(spec.cellsOf(CellKind.luck)), [6, 19, 32, 45]);
      // Il n'y a plus d'action moveExit : on entre dans le couloir par le
      // calcul, pas en foulant une case précise. 52 − 12 spéciales = 40.
      expect(spec.cellsWithAction(CellAction.move).length, 40);
      expect(spec.cell(5).color, TokenColor.red);
      expect(spec.cell(44).color, TokenColor.blue);
      expect(ids(spec.cellsOf(CellKind.vortex, TokenColor.green)), [27]);
    });

    test('les virages : vector 90, tel qu\'écrit dans le JSON', () {
      expect(ids(spec.turns), [4, 11, 24, 37, 50]);
      expect(spec.cell(4).vector, 90);
      expect(spec.cell(17).vector, 0,
          reason: 'absent du JSON : le code n\'invente pas');
    });

    test('plus aucune case ne porte le drapeau move', () {
      // Le champ a ete retire du JSON ; le parseur le laisse a false.
      expect(ids(spec.ring.where((c) => c.move)), isEmpty);
    });

    test('tokenStatus et move.source', () {
      expect(spec.tokenStatuses, TokenStatus.values);
      expect(spec.moveSource, 'lastDice');
    });

    group('un JSON invalide est refusé', () {
      test('cellType hors de l\'enum', () {
        final j = mutated((r) => (r['ring'] as List)[3]['cellType'] = 'teleport');
        expect(() => BoardSpec.parse(j), throwsA(isA<BoardSpecError>()));
      });
      test('ids dans le désordre', () {
        final j = mutated((r) => (r['ring'] as List)[3]['id'] = 9);
        expect(() => BoardSpec.parse(j), throwsA(isA<BoardSpecError>()));
      });
      test('action inconnue', () {
        final j = mutated((r) => (r['ring'] as List)[3]['action'] = 'fly');
        expect(() => BoardSpec.parse(j), throwsA(isA<BoardSpecError>()));
      });
      test('deux départs pour une même couleur', () {
        final j = mutated((r) => (r['ring'] as List)[3]['cellType'] = 'startBlue');
        expect(() => BoardSpec.parse(j), throwsA(isA<BoardSpecError>()));
      });
      test('texte qui n\'est pas du JSON', () {
        expect(() => BoardSpec.parse('pas du json'),
            throwsA(isA<BoardSpecError>()));
      });
    });
  });

  group('🏁 Mise en place', () {
    test('16 pions, tous en base, bleu commence', () {
      final g = game();
      expect(g.allTokens.length, 16);
      expect(g.allTokens.every((t) => t.inBase), isTrue);
      expect(g.currentPlayer, TokenColor.blue);
      expect(g.phase, Phase.rolling);
    });

    test('2 joueurs seulement : bleu et vert alternent', () {
      final g = game(players: [TokenColor.blue, TokenColor.green]);
      expect(g.allTokens.length, 8);
      g.roll(2); // rien ne peut bouger → le tour passe
      expect(g.currentPlayer, TokenColor.green);
      g.roll(2);
      expect(g.currentPlayer, TokenColor.blue);
    });

    test('une couleur sans case de départ est refusée', () {
      expect(() => game(players: [TokenColor.blue, TokenColor.purple]),
          throwsArgumentError);
    });
  });

  group('🚪 Sortir de la base', () {
    test('1 à 5 : aucun pion ne peut sortir, le tour passe', () {
      for (var v = 1; v <= 5; v++) {
        final g = game();
        expect(types(g.roll(v)), contains(EventType.noMove), reason: 'dé $v');
        expect(g.currentPlayer, TokenColor.red, reason: 'dé $v');
      }
    });

    test('6 : les 4 pions peuvent sortir', () {
      final g = game();
      g.roll(6);
      expect(g.movableTokens().length, 4);
      expect(g.phase, Phase.moving);
    });

    test('le pion sort sur sa case de départ, et rejoue (c\'était un 6)', () {
      final g = game();
      g.roll(6);
      final t = tok(g, TokenColor.blue);
      final ev = g.play(t);
      expect(t.onRing, isTrue);
      expect(t.ringIndex, 0);
      expect(ev.first.type, EventType.exited);
      expect(types(ev), contains(EventType.extraTurn));
      expect(g.currentPlayer, TokenColor.blue);
    });

    test('chaque couleur sort sur SA case', () {
      for (final c in spec.colors) {
        final other = c == TokenColor.blue ? TokenColor.red : TokenColor.blue;
        final g = game(players: [c, other]);
        g.roll(6);
        final t = tok(g, c);
        g.play(t);
        expect(t.ringIndex, spec.startOf[c], reason: c.name);
      }
    });
  });

  group('➡️ Déplacement et virages', () {
    test('le pion avance de la valeur du dé', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(10);
      g.roll(4);
      final mv = g.preview(t);
      expect(mv.moveValue, 4);
      expect(mv.path, [11, 12, 13, 14]);
      g.play(t);
      expect(t.ringIndex, 14);
    });

    test('passer la case 4 (vector 90) : un virage est pris', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(2);
      g.roll(3);
      final mv = g.preview(t);
      expect(mv.path, [3, 4, 5]);
      expect(mv.vectorAngle, 90);
    });

    test('sans case à vector : aucun virage', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(14);
      g.roll(3);
      expect(g.preview(t).vectorAngle, 0);
    });

    test('l\'anneau ne boucle plus : le bleu ne foule jamais la 51', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(50);
      g.roll(3);
      final mv = g.preview(t);
      expect(mv.path, isEmpty, reason: 'aucune case d\'anneau ne restait');
      expect(mv.exitRank, 3);
      g.play(t);
      expect(t.inExit, isTrue);
      expect(t.ringIndex, 3);
    });

    test('loin de sa sortie, un pion joue n\'importe quel dé', () {
      for (var v = 1; v <= 5; v++) {
        final g = game();
        final t = tok(g, TokenColor.blue)..enterRing(20);
        g.roll(v);
        expect(g.movableTokens(), [t], reason: 'dé $v');
      }
    });
  });

  group('⚔️ Capture', () {
    test('arriver sur un adversaire, case ordinaire : il retourne en base, on rejoue', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(10);
      final r = tok(g, TokenColor.red)..enterRing(14);
      g.roll(4);
      final ev = g.play(b);
      expect(r.inBase, isTrue);
      expect(types(ev), containsAll([EventType.captured, EventType.extraTurn]));
      expect(g.currentPlayer, TokenColor.blue);
    });

    test('case sûre (étoile 8) : pas de capture, le tour passe', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(4);
      final r = tok(g, TokenColor.red)..enterRing(8);
      g.roll(4);
      final ev = g.play(b);
      expect(r.onRing, isTrue);
      expect(r.ringIndex, 8);
      expect(types(ev), isNot(contains(EventType.captured)));
      expect(g.currentPlayer, TokenColor.red);
    });

    test('case de départ adverse : sûre aussi', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(10);
      final r = tok(g, TokenColor.red)..enterRing(13);
      g.roll(3);
      g.play(b);
      expect(r.onRing, isTrue);
    });

    test('deux adversaires sur la case : les deux repartent', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(10);
      final r = tok(g, TokenColor.red)..enterRing(14);
      final y = tok(g, TokenColor.yellow)..enterRing(14);
      g.roll(4);
      final ev = g.play(b);
      expect(r.inBase && y.inBase, isTrue);
      expect(ev.where((e) => e.type == EventType.captured).length, 2);
    });

    test('mes propres pions : on s\'empile, pas de capture', () {
      final g = game();
      final b0 = tok(g, TokenColor.blue, 0)..enterRing(10);
      final b1 = tok(g, TokenColor.blue, 1)..enterRing(14);
      g.roll(4);
      g.play(b0);
      expect(b1.onRing && b1.ringIndex == 14, isTrue);
      expect(g.tokensAt(14).length, 2);
    });
  });

  group('🔁 Les tours', () {
    test('ordre bleu → rouge → vert → jaune → bleu', () {
      final g = game();
      final seen = <TokenColor>[];
      for (var i = 0; i < 5; i++) {
        seen.add(g.currentPlayer);
        g.roll(1);
      }
      expect(seen, [
        TokenColor.blue,
        TokenColor.red,
        TokenColor.green,
        TokenColor.yellow,
        TokenColor.blue,
      ]);
    });

    test('un 6 redonne la main, même sans capture', () {
      final g = game();
      tok(g, TokenColor.blue).enterRing(20);
      g.roll(6);
      g.play(tok(g, TokenColor.blue));
      expect(g.currentPlayer, TokenColor.blue);
      expect(g.phase, Phase.rolling);
    });

    test('trois 6 d\'affilée : le troisième est perdu, le tour passe', () {
      final g = game();
      g.roll(6);
      g.play(tok(g, TokenColor.blue, 0));
      g.roll(6);
      g.play(tok(g, TokenColor.blue, 1));
      expect(g.currentPlayer, TokenColor.blue);
      final ev = g.roll(6);
      expect(types(ev), contains(EventType.threeSixes));
      expect(g.currentPlayer, TokenColor.red);
      expect(g.phase, Phase.rolling);
    });

    test('après un tour passé, le compte des 6 repart de zéro', () {
      final g = game();
      g.roll(6);
      g.play(tok(g, TokenColor.blue));
      g.roll(6);
      g.play(tok(g, TokenColor.blue));
      g.roll(2);
      g.play(tok(g, TokenColor.blue)); // 2 : le tour passe
      expect(g.currentPlayer, TokenColor.red);
      expect(g.consecutiveSixes, 0);
    });

    test('on ne joue pas sans avoir lancé', () {
      final g = game();
      expect(() => g.play(tok(g, TokenColor.blue)), throwsStateError);
    });

    test('on ne lance pas deux fois', () {
      final g = game();
      tok(g, TokenColor.blue).enterRing(10);
      g.roll(3);
      expect(() => g.roll(3), throwsStateError);
    });

    test('on ne joue pas le pion d\'un autre', () {
      final g = game();
      tok(g, TokenColor.blue).enterRing(10);
      final r = tok(g, TokenColor.red)..enterRing(20);
      g.roll(3);
      expect(g.canMove(r), isFalse);
      expect(() => g.play(r), throwsStateError);
    });

    test('un dé hors de 1..6 est refusé', () {
      final g = game();
      expect(() => g.roll(7), throwsArgumentError);
      expect(() => g.roll(0), throwsArgumentError);
    });
  });

  group('✨ Statuts', () {
    test('un pion invincible ne se fait pas capturer', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(10);
      final r = tok(g, TokenColor.red)
        ..enterRing(14)
        ..setStatus(TokenStatus.invincible, turns: 2);
      g.roll(4);
      final ev = g.play(b);
      expect(r.onRing, isTrue);
      expect(types(ev), isNot(contains(EventType.captured)));
      expect(g.currentPlayer, TokenColor.red,
          reason: 'pas de capture → pas de tour bonus');
    });

    test('statusCount descend à chaque fin de tour du propriétaire, puis expire', () {
      final g = game();
      final r = tok(g, TokenColor.red)
        ..enterRing(20)
        ..setStatus(TokenStatus.invincible, turns: 2);
      g.roll(1); // bleu : rien à jouer → rouge
      expect(r.statusCount, 2, reason: 'le tour de bleu ne compte pas');
      g.roll(1);
      g.play(r); // rouge joue, son tour finit
      expect(r.statusCount, 1);
      expect(r.status, TokenStatus.invincible);
      g.roll(1); // vert
      g.roll(1); // jaune
      g.roll(1); // bleu
      g.roll(1);
      g.play(r); // rouge à nouveau
      expect(r.statusCount, 0);
      expect(r.status, TokenStatus.normal);
    });

    test('doubleDice et halfDice : portés, pas encore appliqués', () {
      final g = game();
      final b = tok(g, TokenColor.blue)
        ..enterRing(10)
        ..setStatus(TokenStatus.doubleDice, turns: 2);
      g.roll(3);
      expect(g.preview(b).path.length, 3,
          reason: 'le JSON ne dit pas comment ce statut agit');
    });
  });

  group('🌀 Cases spéciales : reconnues, pas encore appliquées', () {
    test('arriver sur vortexBlue (case 1) est signalé ; le pion y reste', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(0);
      g.roll(1);
      final ev = g.play(b);
      final sp = ev.firstWhere((e) => e.type == EventType.specialCell);
      expect(sp.action, CellAction.vortex);
      expect(sp.cell, 1);
      expect(b.ringIndex, 1);
    });

    test('death et luck sont signalés de même', () {
      const cases = [
        (from: 4, action: CellAction.death),
        (from: 5, action: CellAction.luck),
      ];
      for (final c in cases) {
        final g = game();
        final b = tok(g, TokenColor.blue)..enterRing(c.from);
        g.roll(1);
        final ev = g.play(b);
        expect(
          ev.any((e) => e.type == EventType.specialCell && e.action == c.action),
          isTrue,
          reason: c.action.name,
        );
      }
    });

    test('une case ordinaire ne signale rien', () {
      final g = game();
      final b = tok(g, TokenColor.blue)..enterRing(1);
      g.roll(1); // → case 2
      final ev = g.play(b);
      expect(ev.any((e) => e.type == EventType.specialCell), isFalse);
    });
  });

  group('🚩 La sortie du ring', () {
    test('exitIndex : 50 bleu, 11 rouge, 24 vert, 37 jaune', () {
      expect(spec.exitIndexOf(TokenColor.blue), 50);
      expect(spec.exitIndexOf(TokenColor.red), 11);
      expect(spec.exitIndexOf(TokenColor.green), 24);
      expect(spec.exitIndexOf(TokenColor.yellow), 37);
    });

    test('la case jamais foulée : 51 bleu, 12 rouge, 25 vert, 38 jaune', () {
      expect(spec.neverVisitedBy(TokenColor.blue), 51);
      expect(spec.neverVisitedBy(TokenColor.red), 12);
      expect(spec.neverVisitedBy(TokenColor.green), 25);
      expect(spec.neverVisitedBy(TokenColor.yellow), 38);
    });

    test('l\'exemple du document : bleu sur 48, dé 4 → couloir rang 2', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(48);
      g.roll(4);
      final mv = g.preview(t);
      expect(mv.entersExit, isTrue);
      expect(mv.exitRank, 2);
      expect(mv.path, [49, 50], reason: 'les 2 cases d\'anneau qui restaient');
      g.play(t);
      expect(t.inExit, isTrue);
      expect(t.ringIndex, 2);
    });

    test('la bascule vaut pour les quatre couleurs', () {
      for (final c in spec.colors) {
        final other = c == TokenColor.blue ? TokenColor.red : TokenColor.blue;
        final g = game(players: [c, other]);
        final before = (spec.exitIndexOf(c) - 2 + spec.size) % spec.size;
        final t = tok(g, c)..enterRing(before);
        g.roll(4);
        g.play(t);
        expect(t.inExit, isTrue, reason: c.name);
        expect(t.ringIndex, 2, reason: c.name);
      }
    });

    test('le piège : un rouge fraîchement sorti ne part pas au couloir', () {
      // 13 + 4 = 17 dépasse son exitIndex 11 : la comparaison directe
      // l'enverrait au couloir sans un seul tour. Le modulo dit qu'il lui
      // reste 50 cases.
      final g = game(players: [TokenColor.red, TokenColor.blue]);
      final t = tok(g, TokenColor.red)..enterRing(13);
      g.roll(4);
      expect(g.preview(t).entersExit, isFalse);
      g.play(t);
      expect(t.inExit, isFalse);
      expect(t.ringIndex, 17);
    });

    test('le jet exact : dépasser le centre est illégal', () {
      final g = game();
      // Un cran avant le centre : un 3 le depasserait forcement.
      final t = tok(g, TokenColor.blue)..enterExit(BoardSpec.exitGoal - 1);
      tok(g, TokenColor.blue, 1).enterRing(20); // pour que le tour ne passe pas
      g.roll(3);
      expect(g.currentPlayer, TokenColor.blue);
      expect(g.canMove(t), isFalse);
    });

    test('le jet exact : la bonne valeur sort le pion', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterExit(BoardSpec.exitGoal - 2);
      g.roll(2); // pile le centre
      final ev = g.play(t);
      expect(t.isHome, isTrue);
      expect(types(ev), contains(EventType.home));
    });

    test('un pion sorti ne rejoue plus', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterExit(BoardSpec.exitGoal);
      tok(g, TokenColor.blue, 1).enterRing(20);
      g.roll(1);
      expect(g.currentPlayer, TokenColor.blue);
      expect(g.canMove(t), isFalse);
    });

    test('un pion du couloir ne se fait pas capturer', () {
      // Le rang 2 du couloir n'est PAS la case 2 de l'anneau.
      final g = game();
      final safe = tok(g, TokenColor.blue)..enterExit(2);
      final victim = tok(g, TokenColor.red)..enterRing(2);
      final mover = tok(g, TokenColor.blue, 1)..enterRing(1);
      g.roll(1);
      g.play(mover);
      expect(victim.inBase, isTrue, reason: 'le rouge de l\'anneau part');
      expect(safe.inExit, isTrue, reason: 'le bleu du couloir reste');
      expect(safe.ringIndex, 2);
    });

    test('un tour complet : 56 pas, et la case interdite jamais foulée', () {
      // Le parcours entier, dé de 1, pour chacune des quatre couleurs :
      // 50 cases d'anneau puis 6 rangs de couloir.
      for (final c in spec.colors) {
        final other = c == TokenColor.blue ? TokenColor.red : TokenColor.blue;
        final g = game(players: [c, other]);
        final t = tok(g, c)..enterRing(spec.startOf[c]!);
        final visited = <int>[];
        var steps = 0;
        while (!t.isHome && steps < 200) {
          if (g.currentPlayer != c) {
            g.roll(1); // l'adversaire a tout en base : son tour repasse
            continue;
          }
          g.roll(1);
          if (g.phase != Phase.moving) continue;
          g.play(t);
          steps++;
          if (!t.inExit) visited.add(t.ringIndex);
        }
        expect(steps, BoardSpec.lapLength + BoardSpec.exitGoal, reason: c.name);
        expect(visited, isNot(contains(spec.neverVisitedBy(c))),
            reason: '${c.name} ne foule jamais sa case interdite');
        expect(visited.last, spec.exitIndexOf(c),
            reason: '${c.name} quitte l\'anneau depuis sa dernière case');
      }
    });

    test('victoire : les quatre pions sortis', () {
      final g = game();
      final mine = g.tokens[TokenColor.blue]!;
      for (var i = 0; i < 3; i++) {
        mine[i].enterExit(BoardSpec.exitGoal);
      }
      final last = mine[3]..enterExit(BoardSpec.exitGoal - 1);
      g.roll(1);
      final ev = g.play(last);
      expect(types(ev), contains(EventType.won));
      expect(g.winners, [TokenColor.blue]);
    });
  });
}
