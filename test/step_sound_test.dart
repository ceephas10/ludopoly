// LE SON DU PAS doit être EMBARQUÉ.
//
// C'est le piège maison, déjà rencontré avec `AnimStock/` : Flutter ne
// s'arrête pas quand un asset manque. Il écrit une ligne dans le journal
// du build, puis termine par un `✓ Built`. Le jeu part en production
// muet, et rien ne le signale.
//
// Ce test lit le fichier PAR LE BUNDLE, comme le fera `audioplayers`, et
// vérifie que c'est bien un WAV PCM 16 bits — le 24 bits d'origine ne se
// décode pas partout sur le web.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le son du pas est dans le bundle, en PCM 16 bits', () async {
    final data = await rootBundle.load('assets/audio/pawn_step.wav');
    final b = data.buffer.asUint8List();
    expect(b.length, greaterThan(1000), reason: 'un fichier, pas un reste');

    String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));
    expect(tag(0), 'RIFF');
    expect(tag(8), 'WAVE');

    // Le bloc `fmt ` : format (2 octets), canaux (2), fréquence (4),
    // débit (4), alignement (2), bits par échantillon (2).
    final head = ByteData.sublistView(b);
    expect(tag(12), 'fmt ', reason: 'le bloc de format vient en premier');
    expect(head.getUint16(20, Endian.little), 1, reason: 'PCM non compressé');
    expect(head.getUint16(34, Endian.little), 16,
        reason: '16 bits : le 24 bits ne se décode pas partout sur le web');

    // 190 ms entre deux cases : si le son dépassait la seconde, il en
    // resterait cinq en vol à tout instant. Quatre voix ne suffiraient
    // plus, et ce test dirait pourquoi.
    final canaux = head.getUint16(22, Endian.little);
    final hz = head.getUint32(24, Endian.little);
    final octets = b.length - 44;
    final ms = octets / (canaux * 2 * hz) * 1000;
    expect(ms, lessThan(1000),
        reason: 'son de ${ms.round()} ms : trop long pour un pas de 190 ms');
  });
}
