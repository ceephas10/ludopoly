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

    test('vortex, trous noirs, chance et sorties', () {
      expect(ids(spec.cellsOf(CellKind.vortex)), [1, 14, 27, 40]);
      expect(ids(spec.cellsOf(CellKind.death)), [5, 18, 31, 44]);
      expect(ids(spec.cellsOf(CellKind.luck)), [6, 19, 32, 45]);
      expect(ids(spec.cellsWithAction(CellAction.moveExit)), [11, 24, 37, 50]);
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

    test('le drapeau move: true, tel qu\'écrit dans le JSON', () {
      expect(ids(spec.ring.where((c) => c.move)), [1, 5, 6]);
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

    test('l\'anneau boucle : pas de couloir final pour l\'instant', () {
      final g = game();
      final t = tok(g, TokenColor.blue)..enterRing(50);
      g.roll(3);
      expect(g.preview(t).path, [51, 0, 1]);
      g.play(t);
      expect(t.ringIndex, 1);
    });

    test('sur l\'anneau, un pion peut toujours jouer, quel que soit le dé', () {
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

    test('death, luck et moveExit sont signalés de même', () {
      const cases = [
        (from: 4, action: CellAction.death),
        (from: 5, action: CellAction.luck),
        (from: 10, action: CellAction.moveExit),
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
}
