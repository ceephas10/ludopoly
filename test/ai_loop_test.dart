// Test de la BOUCLE DE L'INTERFACE, par opposition à `rules_test.dart` et
// `gameplay_test.dart` qui ne testent que le moteur.
//
// Le moteur était déjà prouvé bon : une partie 100 % ordinateur y va
// jusqu'au classement complet. Pourtant la partie se figeait à l'écran.
// C'est donc l'enchaînement des minuteries de `main.dart` qu'il faut
// exercer — _scheduleAiTurn, _playAiTurn, _playAiMove, _scheduleAutoMove,
// _movePawn — avec l'horloge simulée du harnais de test.
//
// Le test joue une partie ENTIÈRE : il clique le dé et les pions pour la
// couleur humaine, et n'intervient jamais pour les couleurs ordinateur.
// Si l'IA se fige, le test échoue en disant précisément où.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

/// Empreinte de la partie. Deux empreintes identiques après plusieurs
/// secondes simulées = plus rien ne bouge.
String fingerprint(GameController c) => [
  c.currentColor.name,
  c.phase.name,
  c.diceValue,
  c.lastRoll,
  for (final p in c.state.allPawns) '${p.location.name}:${p.position}',
].join('|');

void main() {
  // Le panneau de commandes déborde sur la surface 800×600 par défaut, ce
  // qui fait échouer le test sur une erreur de mise en page sans rapport.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(2400, 1500);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'une partie contre l\'ordinateur va jusqu\'au bout sans se figer',
    (tester) async {
      // Le filet de sécurité de l'interface relance l'IA quand un chemin a
      // oublié de le faire. Ici on veut le SAVOIR : s'il se déclenche, c'est
      // qu'il manque un appel explicite, et le test doit le dire au lieu de
      // laisser le filet masquer le trou.
      final rescues = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.contains('relance de secours')) {
          rescues.add(message);
        }
      };
      // Restauré AVANT la fin du corps du test : Flutter vérifie qu'aucune
      // variable de debug n'a été laissée modifiée, et cette vérification
      // passe avant les `addTearDown`.
      try {
        await bootApp(tester);

        final state = tester.state<BoardScreenState>(find.byType(BoardScreen));
        final c = state.controller;
        final human = c.turnOrder.first;

        state.aiOpponents = true;
        await tester.pump();

        String last = fingerprint(c);
        int idleMs = 0;
        bool rewound = false;

        for (int step = 0; step < 3000; step++) {
          if (c.phase == TurnPhase.gameOver) break;

          // Une fois la partie lancée, on appuie sur « Retour » pendant le tour
          // d'un ordinateur. C'est LE chemin qui figeait tout : le rembobinage
          // annulait la minuterie de l'IA sans la replanifier, et comme le
          // plateau est en lecture seule pendant son tour, plus rien ne pouvait
          // relancer la partie. L'IA doit repartir toute seule ensuite.
          if (!rewound && step > 300 && c.currentColor != human) {
            final undo = find.widgetWithText(OutlinedButton, 'Retour');
            if (undo.evaluate().isNotEmpty) {
              await tester.ensureVisible(undo);
              await tester.tap(undo, warnIfMissed: false);
              await tester.pump();
              rewound = true;
            }
          }

          if (c.currentColor == human) {
            // Tour humain : on clique, exactement comme le ferait un joueur.
            if (c.phase == TurnPhase.rolling) {
              final dice = find.byKey(const Key('roll-normal'));
              if (dice.evaluate().isNotEmpty) {
                await tester.ensureVisible(dice);
                await tester.tap(dice, warnIfMissed: false);
              }
            } else if (c.phase == TurnPhase.moving) {
              final options = c.movablePawns();
              if (options.isNotEmpty) {
                final Pawn p = options.first;
                final zone = find.byKey(
                  ValueKey('hit_${p.color.name}_${p.id}'),
                );
                if (zone.evaluate().isNotEmpty) {
                  await tester.tap(zone, warnIfMissed: false);
                }
              }
            }
          }

          await tester.pump(const Duration(milliseconds: 100));

          final now = fingerprint(c);
          if (now == last) {
            idleMs += 100;
            // Le tour le plus lent d'un ordinateur : 900 ms avant le lancer,
            // 700 ms avant le coup, puis le trajet et l'éventuelle pause de
            // capture. 12 s simulées sans le moindre changement, c'est figé.
            expect(
              idleMs,
              lessThan(12000),
              reason:
                  'partie figée au tour de ${c.currentColor.name} '
                  '(phase ${c.phase.name}, dé ${c.diceValue}, '
                  'coups jouables ${c.movablePawns().length}) — '
                  'aucun changement depuis 12 s simulées',
            );
          } else {
            idleMs = 0;
            last = now;
          }
        }

        // 300 s simulées ne suffisent pas toujours à terminer une partie
        // entière — ce n'est pas le sujet. Le sujet est qu'elle AVANCE sans
        // jamais se figer, ce que vérifie le contrôle d'inactivité ci-dessus.
        // On exige quand même une progression franche.
        final home = c.state.allPawns
            .where((p) => p.location == PawnLocation.home)
            .length;
        final out = c.state.allPawns
            .where((p) => p.location != PawnLocation.base)
            .length;
        expect(
          rewound,
          isTrue,
          reason: 'le bouton Retour n\'a jamais pu être actionné',
        );
        expect(
          out,
          greaterThan(4),
          reason:
              'trop peu de pions sortis : la partie n\'avance pas '
              '(rentrés : $home)',
        );
        expect(
          home + out,
          greaterThan(6),
          reason: 'progression insuffisante — rentrés $home, sortis $out',
        );
        expect(
          rescues,
          isEmpty,
          reason:
              'le filet de sécurité a dû relancer l\'IA : il manque un '
              'appel à _scheduleAiTurn sur un chemin. Traces : $rescues',
        );
      } finally {
        debugPrint = previousPrint;
      }
    },
  );

  testWidgets('0 humain + 4 IA : la partie se joue entièrement seule', (
    tester,
  ) async {
    await bootApp(tester);

    final state = tester.state<BoardScreenState>(find.byType(BoardScreen));
    final c = state.controller;

    // Les QUATRE sièges à l'IA — la combinaison « 4 IA » du panneau.
    state.setAiSeats(c.turnOrder.toSet());
    await tester.pump();

    String last = fingerprint(c);
    int idleMs = 0;

    // Personne ne clique JAMAIS : si la partie avance, c'est que la boucle
    // IA s'auto-entretient de bout en bout.
    for (int step = 0; step < 1500; step++) {
      if (c.phase == TurnPhase.gameOver) break;
      await tester.pump(const Duration(milliseconds: 100));
      final now = fingerprint(c);
      if (now == last) {
        idleMs += 100;
        expect(
          idleMs,
          lessThan(12000),
          reason:
              'partie 4 IA figée au tour de ${c.currentColor.name} '
              '(phase ${c.phase.name}, dé ${c.diceValue})',
        );
      } else {
        idleMs = 0;
        last = now;
      }
    }

    final out = c.state.allPawns
        .where((p) => p.location != PawnLocation.base)
        .length;
    expect(
      out,
      greaterThan(4),
      reason: 'sans aucun clic, la partie 4 IA doit avancer toute seule',
    );

    // Démonte l'arbre : `dispose` coupe tous les timers de la boucle IA
    // encore en vol (le test s'arrête volontairement en pleine partie).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
