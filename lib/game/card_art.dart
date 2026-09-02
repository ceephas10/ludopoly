// Le DOS et la FACE des cartes Chance.
//
// Le dos est dessiné au vecteur, comme le plateau (`BoardPainter`) : il
// reste net à toutes les tailles, du timbre-poste posé dans une base
// jusqu'à la carte plein écran qui s'ouvre. Toutes les cartes partagent
// EXACTEMENT ce même dos — c'est ce qui permet de les poser face cachée
// sans rien révéler.
//
// Si un jour le Studio Animations livre le dos en image, il suffira de
// remplacer [CardBack] par un `Image.asset` : rien d'autre ne bouge.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'upgrades.dart';

/// Les deux ors et le noir profond du dos.
const Color _gold = Color(0xFFD4AF37);
const Color _goldPale = Color(0xFFF3E3A3);
const Color _ink = Color(0xFF0A0A0A);

/// Le dos d'une carte : noir et or, bordure double, médaillon central et
/// lotus. Identique pour toutes les cartes.
class CardBack extends StatelessWidget {
  final double radius;
  const CardBack({super.key, this.radius = 6});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: const _CardBackPainter(),
          size: Size.infinite,
        ),
      );
}

class _CardBackPainter extends CustomPainter {
  const _CardBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Toute la gravure est proportionnelle au plus petit côté : le dos
    // garde ses proportions qu'il fasse 20 px ou 400.
    final u = math.min(w, h);

    canvas.drawRect(Offset.zero & size, Paint()..color = _ink);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = _gold
      ..strokeCap = StrokeCap.round;

    // --- bordure double ---------------------------------------------------
    line
      ..strokeWidth = math.max(0.8, u * 0.030)
      ..color = _gold;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.035, u * 0.035, w - u * 0.07, h - u * 0.07),
            Radius.circular(u * 0.05)),
        line);
    line
      ..strokeWidth = math.max(0.5, u * 0.014)
      ..color = _goldPale;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(u * 0.085, u * 0.085, w - u * 0.17, h - u * 0.17),
            Radius.circular(u * 0.035)),
        line);

    final cx = w / 2;
    final cy = h / 2;

    // --- volutes des quatre coins ----------------------------------------
    line
      ..strokeWidth = math.max(0.5, u * 0.016)
      ..color = _gold;
    for (final sx in [1.0, -1.0]) {
      for (final sy in [1.0, -1.0]) {
        canvas.save();
        canvas.translate(sx > 0 ? u * 0.14 : w - u * 0.14,
            sy > 0 ? u * 0.14 : h - u * 0.14);
        canvas.scale(sx, sy);
        final p = Path()
          ..moveTo(0, u * 0.20)
          ..cubicTo(0, u * 0.05, u * 0.05, 0, u * 0.20, 0);
        canvas.drawPath(p, line);
        final curl = Path()
          ..moveTo(u * 0.045, u * 0.11)
          ..cubicTo(u * 0.045, u * 0.045, u * 0.11, u * 0.045, u * 0.11,
              u * 0.095)
          ..cubicTo(u * 0.11, u * 0.13, u * 0.07, u * 0.13, u * 0.07, u * 0.10);
        canvas.drawPath(curl, line);
        canvas.restore();
      }
    }

    // --- médaillon : deux cercles concentriques ---------------------------
    final r = u * 0.30;
    line
      ..strokeWidth = math.max(0.6, u * 0.020)
      ..color = _gold;
    canvas.drawCircle(Offset(cx, cy), r, line);
    line
      ..strokeWidth = math.max(0.4, u * 0.010)
      ..color = _goldPale;
    canvas.drawCircle(Offset(cx, cy), r * 0.86, line);

    // Petits pétales en couronne, entre les deux cercles.
    line
      ..strokeWidth = math.max(0.4, u * 0.009)
      ..color = _gold;
    for (int i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final x1 = cx + math.cos(a) * r * 0.88;
      final y1 = cy + math.sin(a) * r * 0.88;
      final x2 = cx + math.cos(a) * r * 0.98;
      final y2 = cy + math.sin(a) * r * 0.98;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);
    }

    // --- le lotus ---------------------------------------------------------
    _drawLotus(canvas, Offset(cx, cy), r * 0.78, u);

    // --- rinceaux au-dessus et au-dessous du médaillon --------------------
    line
      ..strokeWidth = math.max(0.5, u * 0.013)
      ..color = _gold;
    for (final dir in [-1.0, 1.0]) {
      for (final side in [-1.0, 1.0]) {
        final p = Path()
          ..moveTo(cx, cy + dir * r * 1.08)
          ..cubicTo(
              cx + side * u * 0.16,
              cy + dir * r * 1.22,
              cx + side * u * 0.26,
              cy + dir * r * 1.10,
              cx + side * u * 0.30,
              cy + dir * r * 1.34);
        canvas.drawPath(p, line);
      }
    }
  }

  /// Un lotus vu de face : une couronne de pétales, puis un cœur.
  void _drawLotus(Canvas canvas, Offset c, double r, double u) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _goldPale
      ..strokeWidth = math.max(0.5, u * 0.012)
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = _gold.withValues(alpha: 0.22);

    Path petal(double angle, double len, double width) {
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      final px = -dy;
      final py = dx;
      final tipX = c.dx + dx * len;
      final tipY = c.dy + dy * len;
      return Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(c.dx + dx * len * 0.5 + px * width,
            c.dy + dy * len * 0.5 + py * width, tipX, tipY)
        ..quadraticBezierTo(c.dx + dx * len * 0.5 - px * width,
            c.dy + dy * len * 0.5 - py * width, c.dx, c.dy)
        ..close();
    }

    // Couronne extérieure : 8 pétales larges, pointe vers l'extérieur.
    for (int i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final p = petal(a, r, r * 0.34);
      canvas.drawPath(p, fill);
      canvas.drawPath(p, stroke);
    }
    // Couronne intérieure, décalée d'un demi-pas.
    for (int i = 0; i < 8; i++) {
      final a = -math.pi / 2 + (i + 0.5) * math.pi / 4;
      final p = petal(a, r * 0.62, r * 0.22);
      canvas.drawPath(p, stroke);
    }
    // Cœur.
    canvas.drawCircle(c, r * 0.16, fill);
    canvas.drawCircle(c, r * 0.16, stroke);
  }

  @override
  bool shouldRepaint(covariant _CardBackPainter old) => false;
}

/// La FACE d'une carte : le même cadre doré, mais ouverte — on y lit le
/// moment d'utilisation, le nom et l'instruction à suivre.
class CardFace extends StatelessWidget {
  final ChanceCard card;
  final double radius;
  const CardFace({super.key, required this.card, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final immediate = card.kind == CardKind.immediate;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _ink,
          border: Border.all(color: _gold, width: 3),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bandeau : immédiate ou différée, et son moment.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  border: Border.all(color: _gold, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  immediate
                      ? 'CARTE IMMÉDIATE'
                      : 'CARTE DIFFÉRÉE · ${card.timingLabelFr}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _goldPale,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                card.nameFr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _goldPale,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: _gold.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    card.descriptionFr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _goldPale.withValues(alpha: 0.85),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                immediate
                    ? "L'effet s'applique immédiatement."
                    : 'Rangée dans votre main, à jouer à votre tour.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _gold.withValues(alpha: 0.75),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
