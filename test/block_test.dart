// LE BLOC : deux pions d'une même couleur sur une même case de l'anneau.
//
// La règle demandée, mot pour mot : « lorsqu'il y a deux pions de même
// couleur sur la même case ring et qu'un pion adverse vient sur ces deux
// pions, alors ces deux pions restent sur le même ring. C'est lorsque
// l'adversaire vient encore, c'est-à-dire deux pions de la même couleur
// adverse, que les deux pions dégagent. »
//
// Donc : un attaquant SEUL partage la case sans rien manger ; il faut
// qu'il y amène un DEUXIÈME pion de sa couleur pour faire tomber le bloc.
// Un pion isolé, lui, se mange comme avant.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/ai_difficulty.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';

GameController game() => GameController(
      turnOrder: const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ],
      state: GameState.initial(),
    )..aiDifficulty = AiDifficulty.expert;

/// Le pion [id] de [color], posé sur la case d'anneau [cell].
Pawn put(GameController c, PlayerColor color, int id, int cell) {
  final p = c.state.pawnsByColor[color]![id];
  p.location = PawnLocation.ring;
  p.position = cell;
  return p;
}

/// Fait jouer [color] : trois pas, avec le pion [id].
void step3(GameController c, PlayerColor color, int id) {
  c.currentPlayerIdx = c.turnOrder.indexOf(color);
  c.phase = TurnPhase.rolling;
  c.diceValue = 0;
  c.roll(3);
  c.movePawn(c.state.pawnsByColor[color]![id]);
}

/// La case visée : 44 pas après le départ de [color]. Aucune des quatre
/// n'est une case sûre — la case sûre a ses propres règles, qui ne sont
/// pas ce qu'on teste ici.
int target(PlayerColor color) =>
    (GameController.startIdx(color) + 44) % GameController.ringSize;

/// La case de départ de l'attaquant : trois pas avant la case visée.
int launchpad(PlayerColor color) =>
    (GameController.startIdx(color) + 41) % GameController.ringSize;

void main() {
  group('🧱 Deux pions de même couleur font un bloc', () {
    test('un attaquant SEUL ne casse pas le bloc : il partage la case', () {
      final c = game();
      final cell = target(PlayerColor.red);
      final d0 = put(c, PlayerColor.blue, 0, cell);
      final d1 = put(c, PlayerColor.blue, 1, cell);
      put(c, PlayerColor.red, 0, launchpad(PlayerColor.red));

      step3(c, PlayerColor.red, 0);

      expect(d0.location, PawnLocation.ring, reason: 'le bloc tient');
      expect(d1.location, PawnLocation.ring, reason: 'le bloc tient');
      expect(d0.position, cell);
      expect(d1.position, cell);
      expect(c.state.pawnsByColor[PlayerColor.red]![0].position, cell,
          reason: 'l\'attaquant se pose quand même sur la case');
    });

    test('le DEUXIÈME pion adverse fait dégager le bloc', () {
      final c = game();
      final cell = target(PlayerColor.red);
      final d0 = put(c, PlayerColor.blue, 0, cell);
      final d1 = put(c, PlayerColor.blue, 1, cell);
      put(c, PlayerColor.red, 0, launchpad(PlayerColor.red));
      put(c, PlayerColor.red, 1, launchpad(PlayerColor.red));

      step3(c, PlayerColor.red, 0); // le bloc tient
      expect(d0.location, PawnLocation.ring);

      step3(c, PlayerColor.red, 1); // deux contre deux
      expect(d0.location, PawnLocation.base, reason: 'le bloc dégage');
      expect(d1.location, PawnLocation.base, reason: 'les DEUX dégagent');
      for (final id in [0, 1]) {
        expect(c.state.pawnsByColor[PlayerColor.red]![id].position, cell,
            reason: 'les deux attaquants restent sur la case conquise');
      }
    });

    test('un pion ISOLÉ se mange toujours du premier coup', () {
      final c = game();
      final cell = target(PlayerColor.red);
      final seul = put(c, PlayerColor.blue, 0, cell);
      put(c, PlayerColor.red, 0, launchpad(PlayerColor.red));

      step3(c, PlayerColor.red, 0);

      expect(seul.location, PawnLocation.base,
          reason: 'la règle du bloc ne protège QUE les blocs');
    });

    // « Il faudrait que cela se répète pour toutes les couleurs. »
    test('la règle vaut pour les QUATRE couleurs, dans les deux rôles', () {
      for (final attaquant in PlayerColor.values) {
        for (final defenseur in PlayerColor.values) {
          if (defenseur == attaquant) continue;
          final c = game();
          final cell = target(attaquant);
          final d0 = put(c, defenseur, 0, cell);
          final d1 = put(c, defenseur, 1, cell);
          put(c, attaquant, 0, launchpad(attaquant));
          put(c, attaquant, 1, launchpad(attaquant));

          step3(c, attaquant, 0);
          expect(d0.location, PawnLocation.ring,
              reason: '$attaquant seul contre le bloc de $defenseur');
          expect(d1.location, PawnLocation.ring,
              reason: '$attaquant seul contre le bloc de $defenseur');

          step3(c, attaquant, 1);
          expect(d0.location, PawnLocation.base,
              reason: '$attaquant à deux contre le bloc de $defenseur');
          expect(d1.location, PawnLocation.base,
              reason: '$attaquant à deux contre le bloc de $defenseur');
        }
      }
    });

    // L'IA note une capture 900 points, au-dessus de presque tout. Si
    // elle croyait manger un bloc avec un seul pion, elle irait sur le
    // bloc et laisserait filer la vraie prise, juste à côté.
    test('l\'IA préfère la VRAIE prise au bloc qu\'elle ne peut pas manger',
        () {
      final c = game();
      // Deux cases atteignables en 3 pas par deux pions rouges différents.
      final bloc = target(PlayerColor.red);
      final proie = (bloc + 4) % GameController.ringSize;

      put(c, PlayerColor.blue, 0, bloc); // un BLOC : intouchable seul
      put(c, PlayerColor.blue, 1, bloc);
      put(c, PlayerColor.green, 0, proie); // un pion ISOLÉ : mangeable

      final versLeBloc = put(c, PlayerColor.red, 0, launchpad(PlayerColor.red));
      final versLaProie =
          put(c, PlayerColor.red, 1, (proie - 3 + GameController.ringSize) % GameController.ringSize);

      c.currentPlayerIdx = c.turnOrder.indexOf(PlayerColor.red);
      c.phase = TurnPhase.rolling;
      c.diceValue = 0;
      c.roll(3);

      expect(c.pickAiPawn(), same(versLaProie),
          reason: 'le bloc ne se mange pas à un pion : ce n\'est pas une prise');
      expect(versLeBloc.location, PawnLocation.ring);
    });

    test('trois défenseurs tombent aussi devant deux attaquants', () {
      final c = game();
      final cell = target(PlayerColor.red);
      final blues = [for (int i = 0; i < 3; i++) put(c, PlayerColor.blue, i, cell)];
      put(c, PlayerColor.red, 0, launchpad(PlayerColor.red));
      put(c, PlayerColor.red, 1, launchpad(PlayerColor.red));

      step3(c, PlayerColor.red, 0);
      expect(blues.every((p) => p.location == PawnLocation.ring), isTrue);

      step3(c, PlayerColor.red, 1);
      expect(blues.every((p) => p.location == PawnLocation.base), isTrue,
          reason: 'un bloc est un bloc, quelle que soit sa taille');
    });
  });

}
