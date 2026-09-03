// Charge le squelette JSON depuis les assets de l'application. Seul fichier
// du module qui dépende de Flutter : le reste est du Dart pur, testable
// sans interface.

import 'package:flutter/services.dart' show rootBundle;

import 'spec.dart';

/// Le chemin du squelette, déclaré dans `pubspec.yaml`.
const String boardAsset = 'assets/gameplay/board.json';

/// Lit et vérifie `assets/gameplay/board.json`.
Future<BoardSpec> loadBoardSpec() async =>
    BoardSpec.parse(await rootBundle.loadString(boardAsset));
