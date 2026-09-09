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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/game/game_controller.dart';
import 'package:ludopoly/game/pawn.dart';
import 'package:ludopoly/game/player_color.dart';
import 'package:ludopoly/main.dart';

import 'app_boot.dart';

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

  // ── QUAND chaque son part ──────────────────────────────────────────
  //
  // La plainte : « les sons ne coïncident pas, on attend que le dé ait
  // fini de rouler pour l'entendre ». Le harnais n'a pas de greffon
  // audio, on ne peut donc rien écouter — mais on peut mesurer l'INSTANT
  // de chaque déclenchement, et c'est exactement ce qui n'allait pas.
  group('⏱ Les sons tombent avec le geste', () {
    late List<({String son, Duration t})> journal;
    late Duration horloge;

    setUp(() {
      useLargeSurface();
      horloge = Duration.zero;
      journal = [];
      BoardScreenState.onSoundForTest =
          (son) => journal.add((son: son, t: horloge));
    });
    tearDown(() {
      BoardScreenState.onSoundForTest = null;
      resetSurface();
    });

    /// Avance l'horloge simulée ET celle du journal, du même pas.
    Future<void> avancer(WidgetTester t, Duration d) async {
      horloge += d;
      await t.pump(d);
    }

    testWidgets('le dé sonne au LANCER, pas à la fin de son animation',
        (t) async {
      await bootApp(t);
      final s = t.state<BoardScreenState>(find.byType(BoardScreen));
      s.rollManualForTest(6);
      await t.pump();

      expect(journal.map((e) => e.son), contains('de'));
      expect(journal.first.son, 'de');
      expect(journal.first.t, Duration.zero,
          reason: 'le son part dans la frame du lancer, pas après');

      await t.pump(const Duration(seconds: 2));
      await shutdownApp(t);
    });

    testWidgets('la SORTIE DE BASE sonne la chaîne, et pas le pas',
        (t) async {
      await bootApp(t);
      final s = t.state<BoardScreenState>(find.byType(BoardScreen));
      final me = s.controller.currentColor;
      s.rollManualForTest(6);
      await t.pump();
      journal.clear(); // on ne juge que ce qui suit le lancer

      await t.tap(find.byKey(ValueKey('hit_${me.name}_0')));
      await avancer(t, const Duration(milliseconds: 16));

      expect(journal.map((e) => e.son), ['sortie'],
          reason: 'une entrée en scène, pas un pas de plus');

      await t.pump(const Duration(seconds: 2));
      await shutdownApp(t);
    });

    testWidgets('le CRI attend que la victime s\'efface', (t) async {
      await bootApp(t);
      final s = t.state<BoardScreenState>(find.byType(BoardScreen));
      final c = s.controller;
      final me = c.currentColor;

      // Un pion à moi sur l'anneau, une victime isolée trois pas devant.
      final mien = c.state.pawnsByColor[me]![0];
      mien.location = PawnLocation.ring;
      mien.position = (GameController.startIdx(me) + 20) %
          GameController.ringSize;
      final proie = c.state.pawnsByColor[
          PlayerColor.values.firstWhere((x) => x != me)]![0];
      proie.location = PawnLocation.ring;
      proie.position = (mien.position + 3) % GameController.ringSize;

      s.rollManualForTest(3);
      await t.pump();
      journal.clear();

      await t.tap(find.byKey(ValueKey('hit_${me.name}_0')));
      for (var i = 0; i < 60; i++) {
        await avancer(t, const Duration(milliseconds: 40));
      }

      final pas = journal.where((e) => e.son == 'pas').toList();
      final cri = journal.where((e) => e.son == 'capture').toList();
      expect(pas, isNotEmpty, reason: 'trois pas, donc des sons de pas');
      expect(cri, hasLength(1), reason: 'une victime, un cri');
      expect(cri.first.t, greaterThan(pas.last.t),
          reason: 'le cri partait à la DÉTECTION, une seconde avant qu\'on '
              'voie quoi que ce soit : il doit tomber APRÈS le dernier pas, '
              'quand la victime s\'efface');

      await t.pump(const Duration(seconds: 2));
      await shutdownApp(t);
    });
  });
}
