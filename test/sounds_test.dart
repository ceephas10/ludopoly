// LES SONS DU JEU doivent être EMBARQUÉS.
//
// C'est le piège maison, déjà rencontré avec `AnimStock/` : Flutter ne
// s'arrête pas quand un asset manque. Il écrit une ligne dans le journal
// du build, puis termine par un `✓ Built`. Le jeu part en production
// muet, et rien ne le signale.
//
// Ce test lit chaque fichier PAR LE BUNDLE, comme le fera `audioplayers`,
// et vérifie qu'il est lisible partout : un WAV en PCM 16 bits (le
// 24 bits ne se décode pas partout sur le web), ou un MP3 en bonne et due
// forme.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Un son du jeu, et la durée au-delà de laquelle il gênerait.
class _Son {
  const _Son(this.asset, this.maxMs, this.pourquoi);
  final String asset;
  final int maxMs;
  final String pourquoi;
}

const _sons = [
  _Son('assets/audio/dice_roll.mp3', 3000,
      'un lancer dure 500 ms : la traîne peut le déborder, pas l\'enterrer'),
  _Son('assets/audio/pawn_step.wav', 1000,
      'une case toutes les 190 ms : au-delà d\'une seconde, il en resterait '
      'cinq en vol à tout instant et quatre voix ne suffiraient plus'),
  _Son('assets/audio/capture.wav', 2000,
      'le cri doit être fini avant que le pion capturé n\'ait regagné sa boîte'),
  _Son('assets/audio/base_exit.wav', 2000,
      'la sortie de base dure 480 ms : la chaîne peut la déborder un peu, '
      'pas la doubler deux fois'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final son in _sons) {
    test('${son.asset} est dans le bundle, en PCM 16 bits', () async {
      final data = await rootBundle.load(son.asset);
      final b = data.buffer.asUint8List();
      expect(b.length, greaterThan(1000), reason: 'un fichier, pas un reste');

      String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));

      if (son.asset.endsWith('.mp3')) {
        // Un MP3 commence soit par une étiquette ID3, soit directement par
        // la synchro d'une trame : 11 bits à 1.
        final id3 = tag(0).startsWith('ID3');
        final sync = b[0] == 0xFF && (b[1] & 0xE0) == 0xE0;
        expect(id3 || sync, isTrue,
            reason: 'ni étiquette ID3 ni synchro de trame : ce n\'est pas '
                'un MP3, quelle que soit son extension');
        // La durée d'un MP3 ne se lit pas dans un en-tête fixe. Le poids
        // suffit à repérer le fichier vide ou tronqué, qui est le vrai
        // risque ici.
        expect(b.length, greaterThan(5000));
        return;
      }

      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');

      // Le bloc `fmt ` : format (2 octets), canaux (2), fréquence (4),
      // débit (4), alignement (2), bits par échantillon (2).
      final head = ByteData.sublistView(b);
      expect(tag(12), 'fmt ', reason: 'le bloc de format vient en premier');
      expect(head.getUint16(20, Endian.little), 1,
          reason: 'PCM non compressé');
      expect(head.getUint16(34, Endian.little), 16,
          reason: '16 bits : le 24 bits ne se décode pas partout sur le web');

      final canaux = head.getUint16(22, Endian.little);
      final hz = head.getUint32(24, Endian.little);
      final ms = (b.length - 44) / (canaux * 2 * hz) * 1000;
      expect(ms, lessThan(son.maxMs),
          reason: '${ms.round()} ms — ${son.pourquoi}');
    });
  }

  test('les quatre sons sont bien QUATRE fichiers distincts', () async {
    final tailles = <int>{};
    for (final son in _sons) {
      tailles.add((await rootBundle.load(son.asset)).lengthInBytes);
    }
    expect(tailles.length, _sons.length,
        reason: 'un même fichier recopié sous plusieurs noms passerait '
            'tous les contrôles ci-dessus sans qu\'on l\'entende');
  });
}
