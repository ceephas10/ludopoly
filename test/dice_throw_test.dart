// L'animation de lancer vient du Studio, pas d'un code d'animation : le
// plateau se contente de jouer `Dice_<couleur>_throw_<valeur>.webp`. Deux
// choses doivent donc rester vraies — les 42 fichiers existent, et la durée
// codée côté Flutter suit celle des fichiers.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

void main() {
  test('les 4 couleurs jouables ont leurs 6 faces de lancer', () {
    for (final c in [
      PlayerColor.blue,
      PlayerColor.red,
      PlayerColor.green,
      PlayerColor.yellow,
    ]) {
      for (var v = 1; v <= 6; v++) {
        final f = File('AnimStock/Dices/WEBP/Dice_${c.name}_throw_$v.webp');
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    }
  });

  test('la durée codée suit celle des fichiers du Studio', () async {
    final bytes =
        File('AnimStock/Dices/WEBP/Dice_blue_throw_6.webp').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    var total = Duration.zero;
    for (var i = 0; i < codec.frameCount; i++) {
      total += (await codec.getNextFrame()).duration;
    }
    codec.dispose();

    expect(
      BoardScreenState.diceThrowDurationForTest.inMilliseconds,
      total.inMilliseconds,
      reason: 'si le Studio refait l\'animation, la constante Flutter doit '
          'suivre : trop courte, on coupe le lancer ; trop longue, le dé '
          'reste figé sur sa dernière image',
    );
  });
}
