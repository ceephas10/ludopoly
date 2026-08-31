// Fumigation : l'application démarre, sort de son écran de chargement et
// affiche le plateau des 4 joueurs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludopoly/main.dart';

import 'app_boot.dart';

void main() {
  setUp(useLargeSurface);
  tearDown(resetSurface);

  testWidgets('l\'app démarre et affiche les 4 joueurs', (tester) async {
    await bootApp(tester);
    // Chaque nom apparaît deux fois : sur le plateau et dans le panneau.
    for (final name in ['Player 1', 'Player 2', 'Player 3', 'Player 4']) {
      expect(find.text(name), findsWidgets, reason: '$name est absent');
    }

    // Chaque pion décale le départ de son animation d'au plus 800 ms via
    // un `Future.delayed`. On laisse ces délais s'écouler, puis on démonte
    // l'arbre : sans ça le harnais signale « A Timer is still pending ».
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('l\'onglet Règles du jeu montre les boutons Joueurs et Modes',
      (tester) async {
    await bootApp(tester);

    // Ouvre l'onglet « Règles du jeu ».
    await tester.tap(find.text('Règles du jeu'));
    // Pas de pumpAndSettle : les animations idle des pions ne se posent
    // jamais, il expirerait à coup sûr. Deux pompes suffisent pour l'onglet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // ── Les 5 combinaisons Humain / IA, un bouton chacune ──
    for (final label in ['4 H', '3 H + 1 IA', '2 H + 2 IA', '1 H + 3 IA', '4 IA']) {
      expect(find.text(label), findsOneWidget,
          reason: 'le bouton de combinaison « $label » manque');
    }

    // ── Un interrupteur H / IA par siège ──
    for (final name in ['Player 1', 'Player 2', 'Player 3', 'Player 4']) {
      expect(find.text(name), findsWidgets, reason: '$name absent du panneau');
    }

    // ── Les modes de partie : l'ordinaire actif, les deux autres à venir ──
    expect(find.text('Ordinaire — tour par tour (local)'), findsOneWidget);
    expect(find.text('Rapide — sans attente de tour'), findsOneWidget);
    expect(find.text('Multijoueur — plusieurs appareils'), findsOneWidget);
    expect(find.text('À venir'), findsNWidgets(2),
        reason: 'rapide et multijoueur doivent être verrouillés « À venir »');

    // ── L'ancien interrupteur unique a bien disparu ──
    expect(find.text('Adversaires ordinateur'), findsNothing,
        reason: 'remplacé par la configuration siège par siège');

    // Le bouton « 4 IA » agit vraiment : tous les sièges passent à l'IA.
    final state = tester.state<BoardScreenState>(find.byType(BoardScreen));
    await tester.tap(find.text('4 IA'));
    await tester.pump();
    expect(state.aiSeats.length, 4,
        reason: 'le bouton 4 IA doit mettre les 4 sièges à l\'IA');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
