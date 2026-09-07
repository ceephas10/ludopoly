// Le fond des écrans : une image si le Studio en a fourni une, sinon un
// dégradé.
//
// L'image n'est pas obligatoire. Tant qu'elle manque, `errorBuilder` fait
// retomber sur le dégradé — l'écran reste correct, il est seulement uni.

import 'package:flutter/material.dart';

/// Les deux fonds du jeu.
enum AppBackground {
  /// Derrière le tableau de bord.
  menu('AnimStock/Backgrounds/Background_Menu.png',
      [Color(0xFF16452C), Color(0xFF0E2A1C)]),

  /// Derrière le plateau, pendant la partie.
  board('AnimStock/Backgrounds/Background_Board.png',
      [Color(0xFF2A3A63), Color(0xFF141C33)]);

  const AppBackground(this.asset, this.fallback);

  final String asset;

  /// Les deux couleurs du dégradé de repli, du centre vers les bords.
  final List<Color> fallback;

  /// Le dégradé seul, sans image.
  Widget get _gradient => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.95,
            colors: fallback,
          ),
        ),
        child: const SizedBox.expand(),
      );

  /// Le fond, image comprise si elle existe. [child] est posé PAR-DESSUS —
  /// c'est ce qui donne l'impression que le plateau flotte sur le décor.
  Widget wrap(Widget child) => Stack(
        fit: StackFit.expand,
        children: [
          _gradient,
          Image.asset(
            asset,
            fit: BoxFit.cover,
            // Absente ? On garde le dégradé, sans rien casser ni afficher
            // d'icône d'erreur.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          // Un voile sombre : sans lui, un décor chargé mange la lisibilité
          // du plateau et des boutons posés dessus.
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0x59000000)),
            child: SizedBox.expand(),
          ),
          child,
        ],
      );
}
