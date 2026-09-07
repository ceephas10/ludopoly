// L'identité de LudoPoly : le logo, et l'écran de chargement.
//
// Réunis ici parce qu'ils doivent rester d'accord — l'écran de chargement
// n'est que le logo posé sur le décor, avec une barre de progression. Deux
// écrans qui montrent le même titre ne doivent pas le dessiner deux fois.

import 'package:flutter/material.dart';

import 'app_background.dart';
import 'background_config.dart';

/// Le titre, sa devise et son jeton. [scale] fait varier l'ensemble sans
/// rien décaler : 1 pour l'accueil, plus petit pour le chargement.
class LudoPolyLogo extends StatelessWidget {
  const LudoPolyLogo({super.key, this.scale = 1.0, this.tagline = true});

  final double scale;
  final bool tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Le jeton : un dé stylisé, dans l'ambre du décor.
        Container(
          width: 62 * scale,
          height: 62 * scale,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFD166), BgPalette.amber],
            ),
            borderRadius: BorderRadius.circular(16 * scale),
            boxShadow: [
              BoxShadow(
                color: BgPalette.amber.withValues(alpha: 0.45),
                blurRadius: 26 * scale,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(Icons.casino_rounded,
              size: 36 * scale, color: const Color(0xFF3A2B00)),
        ),
        SizedBox(height: 16 * scale),
        // « LUDO » clair, « POLY » ambre : le nom se lit en deux temps.
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 44 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 3 * scale,
              height: 1.0,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 16 * scale,
                  offset: Offset(0, 3 * scale),
                ),
              ],
            ),
            children: const [
              TextSpan(text: 'LUDO', style: TextStyle(color: Colors.white)),
              TextSpan(text: 'POLY', style: TextStyle(color: BgPalette.amber)),
            ],
          ),
        ),
        if (tagline) ...[
          SizedBox(height: 10 * scale),
          // Un filet doré de part et d'autre de la devise.
          // FittedBox : la devise est longue et très espacée. Sur une
          // colonne étroite elle débordait de la ligne ; elle se réduit
          // désormais au lieu de la casser.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Rule(width: 26 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                  child: Text(
                    'TOUT SE JOUE JUSQU\'AU DERNIER PION',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 10.5 * scale,
                      letterSpacing: 2.2 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _Rule(width: 26 * scale),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 1,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, BgPalette.amber],
          ),
        ),
      );
}

/// L'écran d'attente pendant le sondage des animations. Il porte le décor
/// et le logo : on ne regarde plus un fond vide en anglais.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    required this.status,
    this.background = const BackgroundConfig(),
  });

  /// Ce que l'application est en train de charger, dit simplement.
  final String status;

  final BackgroundConfig background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground.menu.wrap(
        config: background,
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LudoPolyLogo(scale: 0.9),
                const SizedBox(height: 40),
                // Une barre plutôt qu'une roue : elle occupe la largeur du
                // titre et donne au chargement l'air d'appartenir à l'écran.
                SizedBox(
                  width: 210,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: const LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Color(0x33FFFFFF),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(BgPalette.amber),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Préparation du plateau…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
