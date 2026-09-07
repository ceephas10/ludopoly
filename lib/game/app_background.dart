// Le décor des écrans, peint — pas une image.
//
// Il suit la spécification « Ludo King Classic Blue » : un dégradé radial
// saphir, des rayons diagonaux, un halo central cyan et un vignettage
// sombre. Empilés dans cet ordre, ces quatre calques donnent la profondeur
// qu'un aplat n'a pas.
//
// L'image d'`AnimStock/Backgrounds/` reste posée entre le dégradé et les
// rayons, en filigrane : elle apporte sa texture sans manger la
// lisibilité. Absente, tout le reste tient debout sans elle.

import 'package:flutter/material.dart';

/// La palette de fond de la spec, telle quelle.
abstract final class BgPalette {
  static const Color lightCenter = Color(0xFF1F6DB5);
  static const Color midStop = Color(0xFF0E3D7A);
  static const Color darkEdges = Color(0xFF071B3B);

  /// Halo central, sous le plateau.
  static const Color centerGlow = Color(0x73268EEB);

  /// Rayon diagonal venant du haut-gauche.
  static const Color lightRay = Color(0x294AAFFF);

  /// Assombrissement des bords.
  static const Color vignette = Color(0xBF000000);

  // Accents repris par le menu.
  static const Color amber = Color(0xFFFFB703);
  static const Color cyan = Color(0xFF00B4D8);
  static const Color tile = Color(0xFF123A6B);
}

/// Les deux fonds du jeu. Même décor, seule l'opacité du filigrane change :
/// le plateau a besoin de plus de calme derrière lui que le menu.
enum AppBackground {
  menu(1.0),
  board(0.92);

  const AppBackground(this.textureOpacity);

  /// Force de l'image. Elle est le décor, pas un filigrane : le dégradé
  /// n'est là que pour combler ce qu'elle ne couvre pas, et pour tenir
  /// debout si elle disparaît. À peine adoucie derrière le plateau, qui a
  /// besoin d'un peu plus de calme que le menu.
  final double textureOpacity;

  static const String _texture = 'AnimStock/Backgrounds/Background.png';

  /// Le décor, avec [child] posé PAR-DESSUS.
  Widget wrap(Widget child) => Stack(
        fit: StackFit.expand,
        children: [
          // 1. Le dégradé saphir. L'ellipse est légèrement au-dessus du
          //    centre — c'est là que le plateau se pose.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.04),
                radius: 0.95,
                colors: [
                  BgPalette.lightCenter,
                  BgPalette.midStop,
                  BgPalette.darkEdges,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // 2. La texture, en filigrane. Absente ? On n'affiche rien plutôt
          //    qu'une icône d'erreur — le décor tient sans elle.
          Opacity(
            opacity: textureOpacity,
            child: Image.asset(
              _texture,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),

          // 3. Le rayon diagonal, très adouci : l'image porte déjà son
          //    propre éclairage, un voile appuyé la délaverait.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x0FFFFFFF),
                    Color(0x0A4AAFFF),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.25, 0.6],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),

          // 4. Le vignettage : les bords s'éteignent, le regard va au centre.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [Colors.transparent, BgPalette.vignette],
                  stops: [0.4, 1.0],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),

          child,
        ],
      );
}
