// LES CARTES DU PARTENAIRE, en mode équipe.
//
// La règle demandée : « si c'est au tour de vert de jouer et qu'il n'a
// pas de carte, si bleu a une ou plusieurs cartes dans sa base, vert peut
// y avoir accès. » Et cela vaut pour toutes les couleurs.
//
// C'est la même condition que la règle « aide ton partenaire » déjà en
// place sur les pions : on ne pioche pas chez l'autre tant qu'on a de
// quoi jouer soi-même.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/game_state.dart';
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/game/upgrades.dart';

GameController jeu({bool equipe = true}) => GameController(
      turnOrder: const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ],
      state: GameState.initial(),
    )..teamMode = equipe;

ChanceCard carte(String id) =>
    kDeferredCards.singleWhere((x) => x.id == id);

/// Le tour passe à [c], dé pas encore lancé.
void auTourDe(GameController c, PlayerColor couleur) {
  c.currentPlayerIdx = c.turnOrder.indexOf(couleur);
  c.phase = TurnPhase.rolling;
  c.diceValue = 0;
}

void main() {
  group('🤝 Les cartes du partenaire', () {
    test('la main ATTEIGNABLE bascule sur le partenaire quand la sienne '
        'est vide', () {
      final c = jeu();
      c.upgrades.chanceEnabled = true;
      c.upgrades.addToHand(PlayerColor.blue, carte('DEF_DICE_6'));
      auTourDe(c, PlayerColor.green);

      expect(c.upgrades.handOf(PlayerColor.green), isEmpty);
      expect(c.reachableHand(PlayerColor.green).map((x) => x.id),
          ['DEF_DICE_6'],
          reason: 'vert n\'a rien : il atteint la main de bleu');
      expect(c.deferredHolder(PlayerColor.green, carte('DEF_DICE_6')),
          PlayerColor.blue,
          reason: 'la carte reste celle de BLEU, c\'est lui qui la perdra');
    });

    test('tant qu\'on a une carte à soi, on ne touche PAS à celle de '
        'l\'autre', () {
      final c = jeu();
      c.upgrades.chanceEnabled = true;
      c.upgrades.addToHand(PlayerColor.blue, carte('DEF_DICE_6'));
      c.upgrades.addToHand(PlayerColor.green, carte('DEF_DICE_2'));
      auTourDe(c, PlayerColor.green);

      expect(c.reachableHand(PlayerColor.green).map((x) => x.id),
          ['DEF_DICE_2'], reason: 'la sienne, et elle seule');
      expect(c.deferredHolder(PlayerColor.green, carte('DEF_DICE_6')), isNull);
      expect(c.canPlayDeferred(PlayerColor.green, carte('DEF_DICE_6')),
          isFalse);
    });

    test('HORS mode équipe, chacun ses cartes', () {
      final c = jeu(equipe: false);
      c.upgrades.chanceEnabled = true;
      c.upgrades.addToHand(PlayerColor.blue, carte('DEF_DICE_6'));
      auTourDe(c, PlayerColor.green);

      expect(c.reachableHand(PlayerColor.green), isEmpty);
      expect(c.canPlayDeferred(PlayerColor.green, carte('DEF_DICE_6')),
          isFalse, reason: 'sans équipe, il n\'y a pas de partenaire');
    });

    test('jouer la carte du partenaire la retire de SA main à LUI', () {
      final c = jeu();
      c.upgrades.chanceEnabled = true;
      c.upgrades.addToHand(PlayerColor.blue, carte('DEF_DICE_6'));
      auTourDe(c, PlayerColor.green);

      final forced =
          c.playDeferredCard(PlayerColor.green, carte('DEF_DICE_6'));
      expect(forced, 6, reason: 'la carte dé 6 force le lancer');
      expect(c.upgrades.handOf(PlayerColor.blue), isEmpty,
          reason: 'c\'est BLEU qui perd la carte, pas vert');
      expect(c.upgrades.handOf(PlayerColor.green), isEmpty);
    });

    // « Que cela s'applique à toutes les couleurs. »
    test('les QUATRE couleurs atteignent la main de leur partenaire', () {
      const paires = {
        PlayerColor.blue: PlayerColor.green,
        PlayerColor.green: PlayerColor.blue,
        PlayerColor.red: PlayerColor.yellow,
        PlayerColor.yellow: PlayerColor.red,
      };
      for (final entry in paires.entries) {
        final c = jeu();
        c.upgrades.chanceEnabled = true;
        c.upgrades.addToHand(entry.value, carte('DEF_DICE_6'));
        auTourDe(c, entry.key);

        expect(c.reachableHand(entry.key).map((x) => x.id), ['DEF_DICE_6'],
            reason: '${entry.key.name} doit atteindre '
                '${entry.value.name}');
        expect(c.canPlayDeferred(entry.key, carte('DEF_DICE_6')), isTrue,
            reason: '${entry.key.name} doit pouvoir la jouer');
      }
    });

    test('on ne pioche pas chez un ADVERSAIRE', () {
      final c = jeu();
      c.upgrades.chanceEnabled = true;
      // Rouge et jaune sont l'autre équipe.
      c.upgrades.addToHand(PlayerColor.red, carte('DEF_DICE_6'));
      auTourDe(c, PlayerColor.green);

      expect(c.reachableHand(PlayerColor.green), isEmpty);
      expect(c.canPlayDeferred(PlayerColor.green, carte('DEF_DICE_6')),
          isFalse);
    });
  });
}
