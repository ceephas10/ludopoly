// Les CODES des cartes Chance — A…L pour les immédiates, 1…12 pour les
// différées — sont un contrat avec le joueur : « la 5 me fait jouer 2 »,
// « la 11 saute mon voisin de droite ». Il les apprend. S'ils bougent, ce
// qu'il a appris devient faux sans qu'il en soit prévenu.
//
// Ce fichier les fige. Toute renumérotation le fait échouer, et c'est
// exactement ce qu'on lui demande.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/upgrades.dart';

void main() {
  test('les 12 immédiates portent A à L, dans cet ordre', () {
    expect(kImmediateCards.length, 12);
    expect([for (final c in kImmediateCards) cardCode(c)],
        ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']);
  });

  test('les 12 différées portent 1 à 12, dans cet ordre', () {
    expect(kDeferredCards.length, 12);
    expect([for (final c in kDeferredCards) cardCode(c)],
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']);
  });

  test('chaque code est écrit en dur, et il en existe un par carte', () {
    final all = [...kImmediateCards, ...kDeferredCards];
    for (final c in all) {
      expect(kCardCodes.containsKey(c.id), isTrue,
          reason: '${c.id} n\'a pas de code : ajoutez-le à kCardCodes');
    }
    expect(kCardCodes.length, all.length,
        reason: 'kCardCodes contient un code orphelin');
  });

  test('aucun code n\'est porté par deux cartes', () {
    final codes = kCardCodes.values.toList();
    expect(codes.toSet().length, codes.length,
        reason: 'deux cartes partagent un code : $codes');
  });

  // Les codes que le joueur retient le plus vite : les cartes-dé. La 4 fait
  // jouer 1, la 5 fait jouer 2… jusqu'à la 9 qui fait jouer 6.
  test('les cartes-dé vont de 4 à 9, dans l\'ordre des faces', () {
    for (var face = 1; face <= 6; face++) {
      final c = kDeferredCards.singleWhere((x) => x.id == 'DEF_DICE_$face');
      expect(cardCode(c), '${face + 3}',
          reason: 'la carte qui fait jouer $face doit être la ${face + 3}');
      expect(c.value, face);
    }
  });

  // Un code ne dépend PAS de la position dans le talon : c'est tout
  // l'intérêt de la table. On le vérifie en réordonnant une copie.
  test('le code suit la carte, pas son rang dans le talon', () {
    final shuffled = [...kDeferredCards].reversed.toList();
    for (final c in shuffled) {
      expect(cardCode(c), kCardCodes[c.id],
          reason: '${c.id} change de code quand le talon change d\'ordre');
    }
  });
}
