// Les réglages choisis AVANT la partie.
//
// L'écran d'accueil les rassemble, le plateau les applique une fois pour
// toutes. Rien ici n'est une règle du jeu : ce sont les choix que le
// joueur fait avant de commencer — combien ils sont, qui est tenu par
// l'ordinateur, et quelles options sont de la partie.

import 'ai_difficulty.dart';
import 'background_config.dart';
import 'player_color.dart';

class GameSetup {
  const GameSetup({
    this.playerCount = 4,
    this.aiSeats = const {},
    this.difficulty = AiDifficulty.defaultLevel,
    this.teamMode = false,
    this.vortex = false,
    this.chance = false,
    this.aiTurbo = false,
    this.background = const BackgroundConfig(),
  });

  /// De 1 à 4. L'ordre des couleurs en découle : bleu, puis rouge, vert et
  /// jaune selon le nombre.
  final int playerCount;

  /// Les couleurs tenues par l'ordinateur. Les autres sont humaines.
  final Set<PlayerColor> aiSeats;

  /// Le niveau de l'ordinateur, commun à tous ses sièges.
  final AiDifficulty difficulty;

  /// Mode 2 contre 2. N'a de sens qu'à quatre.
  final bool teamMode;

  /// Cases spéciales : vortex et trous noirs.
  final bool vortex;

  /// Cases Chance et leurs cartes.
  final bool chance;

  /// Accélérateur : raccourcit les temps d'attente de l'ordinateur.
  final bool aiTurbo;

  /// Le décor : style, palette et effets d'ambiance.
  final BackgroundConfig background;

  GameSetup copyWith({
    int? playerCount,
    Set<PlayerColor>? aiSeats,
    AiDifficulty? difficulty,
    bool? teamMode,
    bool? vortex,
    bool? chance,
    bool? aiTurbo,
    BackgroundConfig? background,
  }) =>
      GameSetup(
        playerCount: playerCount ?? this.playerCount,
        aiSeats: aiSeats ?? this.aiSeats,
        difficulty: difficulty ?? this.difficulty,
        teamMode: teamMode ?? this.teamMode,
        vortex: vortex ?? this.vortex,
        chance: chance ?? this.chance,
        aiTurbo: aiTurbo ?? this.aiTurbo,
        background: background ?? this.background,
      );

  /// Les couleurs de la partie, dans l'ordre des tours. Même découpage que
  /// celui du plateau : à deux, ce sont les couleurs OPPOSÉES qui jouent.
  List<PlayerColor> get colors {
    switch (playerCount.clamp(1, 4)) {
      case 1:
        return const [PlayerColor.blue];
      case 2:
        return const [PlayerColor.blue, PlayerColor.green];
      case 3:
        return const [PlayerColor.blue, PlayerColor.red, PlayerColor.green];
      default:
        return const [
          PlayerColor.blue,
          PlayerColor.red,
          PlayerColor.green,
          PlayerColor.yellow,
        ];
    }
  }

  /// Y a-t-il au moins un joueur humain ? Une partie sans personne se
  /// regarde, elle ne se joue pas — l'écran d'accueil le signale.
  bool get hasHuman => colors.any((c) => !aiSeats.contains(c));
}
