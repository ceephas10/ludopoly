// Le décor des écrans, monté couche par couche.
//
// Il suit le kit « Ludo King Background » : un dégradé radial, l'image du
// style choisi, un rayon diagonal, des gouttelettes, des halos colorés, un
// halo central et un vignettage. Chaque couche est commandée par le
// [BackgroundConfig] que le joueur règle dans Options › Arrière-plan.
//
// Rien n'est obligatoire : une image absente laisse simplement voir le
// dégradé, et chaque effet s'éteint sans casser les autres.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'background_config.dart';

/// Les couleurs d'interface reprises du décor, pour que le menu et les
/// panneaux s'accordent avec lui.
abstract final class BgPalette {
  static const Color amber = Color(0xFFFFB703);
  static const Color cyan = Color(0xFF00B4D8);
  static const Color tile = Color(0xFF123A6B);
}

/// Les deux écrans qui portent un décor. Ils partagent la configuration ;
/// seul le calme de fond change — le plateau en demande plus que le menu.
enum AppBackground {
  menu(1.0),
  board(0.82);

  const AppBackground(this.strength);

  /// Atténuation appliquée à l'image ET aux effets. Le plateau doit rester
  /// lisible : un décor plein derrière lui rendrait les pions confus.
  final double strength;

  Widget wrap(Widget child, {BackgroundConfig config = const BackgroundConfig()}) {
    final t = config.theme;
    final imageOpacity =
        (config.patternOpacity / 100 * strength).clamp(0.0, 1.0);
    final rays = config.raysIntensity / 100 * strength;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Le dégradé de la palette : il tient debout même sans image.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.04),
              radius: 0.95,
              colors: [t.light, t.mid, t.dark],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),

        // 2. L'image du style choisi. Absente ? On n'affiche rien plutôt
        //    qu'une icône d'erreur.
        if (imageOpacity > 0)
          Opacity(
            opacity: imageOpacity,
            child: Image.asset(
              config.style.asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),

        // 3. Le rayon diagonal, depuis le haut-gauche.
        if (rays > 0)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.16 * rays),
                    t.ray.withValues(alpha: t.ray.a * rays),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.25, 0.6],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),

        // 4. Gouttelettes et halos : posés au-dessus du fond, jamais sur le
        //    chemin d'un clic.
        if (config.waterDroplets || config.floatingAccents)
          IgnorePointer(
            child: CustomPaint(
              painter: _Ambiance(
                droplets: config.waterDroplets,
                accents: config.floatingAccents,
                accent: t.light,
                strength: strength,
              ),
              child: const SizedBox.expand(),
            ),
          ),

        // 5. Le halo central : le plateau semble éclairé plutôt que posé.
        if (config.centerGlow)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.55,
                  colors: [t.glow, Colors.transparent],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),

        // 6. Le vignettage : les bords s'éteignent, le regard va au centre.
        if (config.vignette)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [Colors.transparent, Color(0xBF000000)],
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
}

/// Gouttelettes d'eau et halos colorés. Leur position vient d'un tirage
/// à graine FIXE : le décor est donc le même d'un lancement à l'autre, et
/// ne scintille pas à chaque redessin.
class _Ambiance extends CustomPainter {
  const _Ambiance({
    required this.droplets,
    required this.accents,
    required this.accent,
    required this.strength,
  });

  final bool droplets;
  final bool accents;
  final Color accent;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(20260907);
    final d = math.min(size.width, size.height);

    if (accents) {
      for (var i = 0; i < 5; i++) {
        final c = Offset(rng.nextDouble() * size.width,
            rng.nextDouble() * size.height);
        final r = d * (0.10 + rng.nextDouble() * 0.14);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                accent.withValues(alpha: 0.16 * strength),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
      }
    }

    if (droplets) {
      for (var i = 0; i < 26; i++) {
        final c = Offset(rng.nextDouble() * size.width,
            rng.nextDouble() * size.height);
        final r = d * (0.006 + rng.nextDouble() * 0.014);
        // Le corps de la goutte, puis son reflet en haut à gauche : sans ce
        // point clair elle ressemble à une tache, pas à de l'eau.
        canvas.drawCircle(
            c,
            r,
            Paint()..color = Colors.white.withValues(alpha: 0.10 * strength));
        canvas.drawCircle(
            c.translate(-r * 0.3, -r * 0.3),
            r * 0.32,
            Paint()..color = Colors.white.withValues(alpha: 0.28 * strength));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.5, r * 0.14)
              ..color = Colors.white.withValues(alpha: 0.18 * strength));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Ambiance old) =>
      old.droplets != droplets ||
      old.accents != accents ||
      old.accent != accent ||
      old.strength != strength;
}
