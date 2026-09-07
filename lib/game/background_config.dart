// La configuration du décor, et les palettes qui vont avec.
//
// Reprise du kit « Ludo King Background » : cinq styles, cinq palettes,
// et les réglages d'ambiance. Rien n'est calculé au hasard — les valeurs
// sont celles du kit, converties en Dart.

import 'package:flutter/material.dart';

/// Les fonds proposés. `defaut` est l'image actuelle du projet ; les
/// quatre autres viennent du kit.
enum BgStyle {
  defaut('Par défaut', 'Motif', 'AnimStock/Backgrounds/Background.png'),
  chicDeluxe('Chic Deluxe', 'Nouveau', 'AnimStock/Backgrounds/Bg_ChicDeluxe.png'),
  splashMosaic('Splash & Mosaïque', 'Chic',
      'AnimStock/Backgrounds/Bg_SplashMosaic.png'),
  ludoKing3D('Ludo King 3D', '3D', 'AnimStock/Backgrounds/Bg_LudoKing3D.png'),
  royalGold('Diamant Royal Gold', 'Royal',
      'AnimStock/Backgrounds/Bg_RoyalGold.png');

  const BgStyle(this.label, this.badge, this.asset);

  final String label;

  /// L'étiquette affichée sous le nom, comme dans le kit.
  final String badge;
  final String asset;
}

/// Les cinq palettes du kit, telles quelles.
enum BgTheme {
  classicBlue('Bleu Royal Ludo King', Color(0xFF071B3B), Color(0xFF0E3D7A),
      Color(0xFF1F6DB5), Color(0x73268EEB), Color(0x294AAFFF)),
  deepCyan('Océan Cyan & Azur', Color(0xFF041D28), Color(0xFF094155),
      Color(0xFF0D738A), Color(0x661EC8DC), Color(0x2638E1F5)),
  royalPurple('Pourpre Royal', Color(0xFF1A0B2E), Color(0xFF39135C),
      Color(0xFF652199), Color(0x66B450FF), Color(0x24D778FF)),
  emerald('Émeraude Casino', Color(0xFF052216), Color(0xFF0B4A2F),
      Color(0xFF148052), Color(0x6122C55E), Color(0x244ADE80)),
  amberGold('Or Impérial & Ambre', Color(0xFF281704), Color(0xFF5C350A),
      Color(0xFF9E6216), Color(0x66F59E0B), Color(0x26FBBF24));

  const BgTheme(this.label, this.dark, this.mid, this.light, this.glow,
      this.ray);

  final String label;

  /// Les trois arrêts du dégradé, du bord vers le centre.
  final Color dark;
  final Color mid;
  final Color light;

  /// Halo central, et rayon diagonal.
  final Color glow;
  final Color ray;
}

/// Ce que le joueur règle dans Options › Arrière-plan.
class BackgroundConfig {
  const BackgroundConfig({
    this.style = BgStyle.defaut,
    this.theme = BgTheme.classicBlue,
    this.patternOpacity = 35,
    this.raysIntensity = 45,
    this.centerGlow = true,
    this.vignette = true,
    this.waterDroplets = true,
    this.floatingAccents = true,
  });

  final BgStyle style;
  final BgTheme theme;

  /// Part de l'image qui transparaît, de 0 à 100.
  final int patternOpacity;

  /// Force du rayon diagonal, de 0 à 100.
  final int raysIntensity;

  final bool centerGlow;
  final bool vignette;

  /// Gouttelettes d'eau posées sur le décor.
  final bool waterDroplets;

  /// Halos colorés qui flottent au-dessus du fond.
  final bool floatingAccents;

  BackgroundConfig copyWith({
    BgStyle? style,
    BgTheme? theme,
    int? patternOpacity,
    int? raysIntensity,
    bool? centerGlow,
    bool? vignette,
    bool? waterDroplets,
    bool? floatingAccents,
  }) =>
      BackgroundConfig(
        style: style ?? this.style,
        theme: theme ?? this.theme,
        patternOpacity: patternOpacity ?? this.patternOpacity,
        raysIntensity: raysIntensity ?? this.raysIntensity,
        centerGlow: centerGlow ?? this.centerGlow,
        vignette: vignette ?? this.vignette,
        waterDroplets: waterDroplets ?? this.waterDroplets,
        floatingAccents: floatingAccents ?? this.floatingAccents,
      );
}
