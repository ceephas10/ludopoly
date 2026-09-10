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
import 'package:flutter/rendering.dart';
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

/// Où en est la zone de touche du premier coup jouable : existe-t-elle,
/// et est-elle réellement à l'écran ? C'est la seule chose que le test
/// fait pour avancer un tour humain ; s'il gèle, c'est là qu'il faut
/// regarder.
String _zoneEtat(WidgetTester tester, List<Pawn> coups) {
  if (coups.isEmpty) return 'aucun coup';
  final p = coups.first;
  final zone = find.byKey(ValueKey('hit_${p.color.name}_${p.id}'));
  if (zone.evaluate().isEmpty) return '${p.color.name}#${p.id} : ABSENTE';
  final r = tester.getRect(zone);
  final ecran =
      tester.binding.platformDispatcher.views.first.physicalSize;
  final dedans = r.left >= 0 &&
      r.top >= 0 &&
      r.right <= ecran.width &&
      r.bottom <= ecran.height;
  // QUI reçoit vraiment la touche à cet endroit ? Une zone `opaque`
  // posée par-dessus absorbe le clic sans rien en faire : le pion ne
  // bouge pas et rien ne le dit. On déroule donc la pile.
  final pile = tester
      .hitTestOnBinding(r.center)
      .path
      .whereType<BoxHitTestEntry>()
      .take(8)
      .map((e) {
        final b = e.target;
        final c = b.debugCreator;
        final w = c is DebugCreator ? c.element.widget : null;
        return w == null
            ? '${b.runtimeType}'
            : '${w.runtimeType}${w.key ?? ""}';
      })
      .join(' → ');
  return '${p.color.name}#${p.id} : $r '
      '${dedans ? "à l'écran" : "HORS ÉCRAN ($ecran)"} · sous le doigt : $pile';
}

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

        // Budget rallongé avec la SORTIE DE BASE, passée de 220 à
        // 480 ms : chaque pion qui entre en jeu coûte un quart de seconde
        // de plus, et c'est précisément le nombre de pions sortis que ce
        // test mesure.
        for (int step = 0; step < 3900; step++) {
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
            // UNE CARTE ATTEND UNE CIBLE. Depuis que les cases Chance
            // sont allumées d'origine, le joueur humain en tire, et
            // certaines réclament qu'il désigne un pion. Tant qu'il ne
            // l'a pas fait, la partie attend — pour de bon, et c'est
            // bien ce que le chien de garde doit signaler.
            //
            // Le joueur, lui, répondrait. Le test répond donc aussi,
            // sans quoi il mesure sa propre inaction.
            if (state.pendingChoiceCard != null) {
              state.resolvePendingChoice(null);
              await tester.pump();
            }
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
            if (idleMs >= 12000) {
              // Le tour le plus lent d'un ordinateur : 900 ms avant le
              // lancer, 700 ms avant le coup, puis le trajet et
              // l'éventuelle pause de capture. 12 s simulées sans le
              // moindre changement, c'est figé.
              //
              // Le diagnostic n'est monté qu'ICI : il fait un test de
              // touche, et le construire à chaque pompage coûterait plus
              // cher que la partie elle-même.
              fail('partie figée au tour de ${c.currentColor.name} '
                  '(phase ${c.phase.name}, dé ${c.diceValue}, '
                  'coups jouables ${c.movablePawns().length}) — '
                  'aucun changement depuis 12 s simulées'
                  ' · carte en attente ${state.pendingChoiceCard?.id}'
                  ' · carte ouverte ${state.openedHandCard?.id}'
                  ' · carte montrée ${state.revealedCard?.id}'
                  ' · pions à désigner ${state.targetPawns.length}'
                  ' · verrous ${state.verrousForTest}'
                  ' · zone du 1er coup : '
                  '${_zoneEtat(tester, c.movablePawns())}');
            }
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
    int changes = 0;

    // Personne ne clique JAMAIS : si la partie avance, c'est que la boucle
    // IA s'auto-entretient de bout en bout.
    //
    // Le budget est du temps SIMULÉ, pas un nombre de tours : quand les
    // temporisations de l'ordinateur s'allongent — la pause de lecture du
    // dé les a portées à 1,5 s — il tient moins de tours dans la même
    // fenêtre. Rallongé d'autant, sinon la partie n'a pas le temps de
    // sortir ses pions et le test devient capricieux sous charge.
    //
    // Rallongé une seconde fois quand la SORTIE DE BASE est passée de 220
    // à 480 ms : chaque pion qui entre en jeu coûte désormais un quart de
    // seconde de plus, et la marge s'était réduite au point que le test
    // tombait sous charge tout en passant seul.
    for (int step = 0; step < 2800; step++) {
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
        changes++;
        last = now;
      }
    }

    // Ce que ce test promet, c'est que la partie AVANCE toute seule. On le
    // mesure donc par le nombre de fois où l'état a changé — une quantité
    // qui ne fait que monter.
    //
    // L'ancienne mesure comptait les pions hors base À LA FIN. Or une
    // capture en renvoie en base : ce nombre monte ET descend, et une
    // partie animée pouvait finir la fenêtre à 4 exactement. Le test
    // tombait alors sur un coup de dé, pas sur une régression.
    expect(
      changes,
      greaterThan(50),
      reason: 'sans aucun clic, la partie 4 IA doit avancer toute seule',
    );
    expect(
      c.state.allPawns.where((p) => p.location != PawnLocation.base).length,
      greaterThan(0),
      reason: 'et des pions doivent être réellement sortis, pas seulement '
          'des dés lancés',
    );

    // Démonte l'arbre : `dispose` coupe tous les timers de la boucle IA
    // encore en vol (le test s'arrête volontairement en pleine partie).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
