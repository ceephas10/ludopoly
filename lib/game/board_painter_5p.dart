// Vector painter for the 5-player Ludo board.
//
// Geometry comes from `board5p_geometry.dart` (generated from
// BoardCraft/boardcraft.json). All Offsets in that file live in a fixed
// 1332 × 1265 coord space; we scale and center them to the widget at paint
// time so the board stays crisp at any resolution.
//
// Drawing style mirrors the 4-player [BoardPainter]: filled colored
// regions, dark outlines, subdivided home corridors, white safe stars
// with dark outline, central pentagons + dice.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'board5p_geometry.dart';

class BoardPainter5P extends CustomPainter {
  const BoardPainter5P();

  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color cBleu   = Color(0xFF3DA4EC);
  static const Color cOrange = Color(0xFFF08C2A);
  static const Color cVert   = Color(0xFF1FA84E);
  static const Color cRouge  = Color(0xFFD33232);
  static const Color cJaune  = Color(0xFFF2C61F);
  static const Color cDice   = Color(0xFF1F9CE6);
  static const Color cDark   = Color(0xFF1F1F1F);
  static const Color cGrey   = Color(0xFF9A9A9A);
  static const Color cRing   = Color(0xFFEFEFEF);
  static const Color cBoard  = Color(0xFFFBFBFB);

  // ── Transform helper ─────────────────────────────────────────────────────
  ({double scale, Offset translate}) _fit(Size size) {
    final scale = math.min(
      size.width  / kBoard5pSrcWidth,
      size.height / kBoard5pSrcHeight,
    );
    final dx = (size.width  - kBoard5pSrcWidth  * scale) / 2;
    final dy = (size.height - kBoard5pSrcHeight * scale) / 2;
    return (scale: scale, translate: Offset(dx, dy));
  }

  Offset _tx(Offset p, double s, Offset t) =>
      Offset(p.dx * s + t.dx, p.dy * s + t.dy);

  Path _poly(List<Offset> pts, double s, Offset t) {
    final p = Path();
    if (pts.isEmpty) return p;
    final first = _tx(pts.first, s, t);
    p.moveTo(first.dx, first.dy);
    for (var i = 1; i < pts.length; i++) {
      final q = _tx(pts[i], s, t);
      p.lineTo(q.dx, q.dy);
    }
    p.close();
    return p;
  }

  void _fillStroke(Canvas c, Path path, Color fill, Color stroke, double w) {
    c.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    c.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ── Paint ────────────────────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    final f = _fit(size);
    final s = f.scale;
    final t = f.translate;
    final lineW = math.max(1.0, 3 * s);

    // 0) White full background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // 1) Board outline (decagonal).
    _fillStroke(canvas, _poly(kBoard, s, t), cBoard, cDark, lineW * 1.3);

    // 2) Ring corridor (light grey fill behind everything else).
    _fillStroke(canvas, _poly(kRingDepuisLeDepartBleu, s, t),
        cRing, cGrey, math.max(1.0, 1.5 * s));

    // 3) Bandeaux (colored outer triangles).
    final bandeaux = <(Color, List<Offset>)>[
      (cBleu,   kBandeauBaseBleu),
      (cOrange, kBandeauBaseOrange),
      (cVert,   kBandeauBaseVert),
      (cRouge,  kBandeauBaseRouge),
      (cJaune,  kBandeauBaseJaune),
    ];
    for (final b in bandeaux) {
      _fillStroke(canvas, _poly(b.$2, s, t), b.$1, cDark, lineW);
    }

    // 4) Yards (white interior triangles).
    final yards = <List<Offset>>[
      kYardBleu, kYardOrange, kYardVert, kYardRouge, kYardJaune,
    ];
    for (final y in yards) {
      _fillStroke(canvas, _poly(y, s, t), Colors.white, cGrey, math.max(1.0, 2 * s));
    }

    // 5) Home corridors (5 cells each, subdivided).
    final couloirs = <(Color, List<Offset>)>[
      (cBleu,   kCouloirMaisonBleu),
      (cOrange, kCouloirMaisonOrange),
      (cVert,   kCouloirMaisonVert),
      (cRouge,  kCouloirMaisonRouge),
      (cJaune,  kCouloirMaisonJaune),
    ];
    for (final c in couloirs) {
      _drawCouloir(canvas, c.$2, c.$1, s, t, lineW);
    }

    // 6) Central pentagon home (white) + 5 colored arrival triangles.
    _fillStroke(canvas, _poly(kPentagoneHome, s, t),
        Colors.white, cDark, lineW);
    final homes = <(Color, List<Offset>)>[
      (cBleu,   kHomeBleu),
      (cOrange, kHomeOrange),
      (cVert,   kHomeVert),
      (cRouge,  kHomeRouge),
      (cJaune,  kHomeJaune),
    ];
    for (final h in homes) {
      _fillStroke(canvas, _poly(h.$2, s, t), h.$1, cDark, lineW);
    }

    // 7) Central pentagon dice (white frame + colored dice cell).
    _fillStroke(canvas, _poly(kPentagoneDe, s, t),
        Colors.white, cDark, lineW * 1.2);
    final dicePt = _tx(kDe, s, t);
    final dr = 42 * s;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: dicePt, width: dr * 2, height: dr * 2),
        Radius.circular(10 * s),
      ),
      Paint()..color = cDice,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: dicePt, width: dr * 2, height: dr * 2),
        Radius.circular(10 * s),
      ),
      Paint()
        ..color = cDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW * 1.2,
    );
    canvas.drawCircle(dicePt, 9 * s, Paint()..color = Colors.white);

    // 8) Cases départ (colored squares with inward white arrow).
    final starts = <(Color, Offset)>[
      (cBleu,   kCaseDepartBleu),
      (cOrange, kCaseDepartOrange),
      (cVert,   kCaseDepartVert),
      (cRouge,  kCaseDepartRouge),
      (cJaune,  kCaseDepartJaune),
    ];
    for (final st in starts) {
      _drawStart(canvas, st.$2, st.$1, s, t, lineW);
    }

    // 9) Étoiles safe (5 white stars with dark outline).
    for (final star in kCasesEtoile) {
      _drawStar(canvas, _tx(star, s, t), 22 * s, 10 * s, lineW * 0.7);
    }

    // 10) Entrées couloir maison (small colored arrows pointing to home center).
    final entries = <(Color, Offset, Offset)>[
      (cBleu,   kEntreeCouloirMaisonBleu,   kMaisonBleu),
      (cOrange, kEntreeCouloirMaisonOrange, kMaisonOrange),
      (cVert,   kEntreeCouloirMaisonVert,   kMaisonVert),
      (cRouge,  kEntreeCouloirMaisonRouge,  kMaisonRouge),
      (cJaune,  kEntreeCouloirMaisonJaune,  kMaisonJaune),
    ];
    for (final e in entries) {
      _drawArrow(canvas, _tx(e.$2, s, t), _tx(e.$3, s, t), e.$1, s, lineW * 0.6);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  void _drawCouloir(Canvas canvas, List<Offset> pts, Color color,
                    double s, Offset t, double lineW) {
    final path = _poly(pts, s, t);
    _fillStroke(canvas, path, color, cDark, lineW);

    if (pts.length == 4) {
      // The corridor is a 4-vertex quad. The longest pair of opposite edges
      // are the "rails"; we split the corridor into 5 cells with 4 dividers
      // perpendicular to those rails.
      final p0 = _tx(pts[0], s, t);
      final p1 = _tx(pts[1], s, t);
      final p2 = _tx(pts[2], s, t);
      final p3 = _tx(pts[3], s, t);

      // Identify the long-axis pairs by edge length: (p0-p3) ↔ (p1-p2) OR
      // (p0-p1) ↔ (p2-p3). Pick the pairing with the larger average length.
      double avg(Offset a, Offset b, Offset c, Offset d) =>
          ((a - b).distance + (c - d).distance) / 2;
      final pairA = avg(p0, p3, p1, p2);   // sides 0-3 and 1-2
      final pairB = avg(p0, p1, p2, p3);   // sides 0-1 and 2-3
      Offset r0a, r0b, r1a, r1b;
      if (pairA >= pairB) {
        r0a = p0; r0b = p3;
        r1a = p1; r1b = p2;
      } else {
        r0a = p0; r0b = p1;
        r1a = p3; r1b = p2;
      }
      final paint = Paint()
        ..color = cDark
        ..strokeWidth = lineW * 0.7
        ..style = PaintingStyle.stroke;
      for (var k = 1; k < 5; k++) {
        final u = k / 5.0;
        final a = Offset.lerp(r0a, r0b, u)!;
        final b = Offset.lerp(r1a, r1b, u)!;
        canvas.drawLine(a, b, paint);
      }
    }
  }

  void _drawStart(Canvas canvas, Offset c, Color color,
                  double s, Offset t, double lineW) {
    final p = _tx(c, s, t);
    final half = 32 * s;
    final rect = Rect.fromCenter(center: p, width: half * 2, height: half * 2);
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(
      rect,
      Paint()
        ..color = cDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW,
    );
    // Arrow pointing toward the dice center.
    final dice = _tx(kDe, s, t);
    final dir = (dice - p);
    final len = dir.distance;
    if (len < 1e-3) return;
    final ux = dir.dx / len, uy = dir.dy / len;
    final nx = -uy, ny = ux;
    final tip   = Offset(p.dx + ux * 16 * s, p.dy + uy * 16 * s);
    final baseL = Offset(p.dx - ux * 12 * s + nx * 10 * s,
                         p.dy - uy * 12 * s + ny * 10 * s);
    final baseR = Offset(p.dx - ux * 12 * s - nx * 10 * s,
                         p.dy - uy * 12 * s - ny * 10 * s);
    final pathArrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..close();
    canvas.drawPath(pathArrow, Paint()..color = Colors.white);
    canvas.drawPath(
      pathArrow,
      Paint()
        ..color = cDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW * 0.7,
    );
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color,
                  double s, double w) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1e-3) return;
    final ux = dir.dx / len, uy = dir.dy / len;
    final nx = -uy, ny = ux;
    final tip   = Offset(from.dx + ux * 18 * s, from.dy + uy * 18 * s);
    final baseL = Offset(from.dx - ux * 8 * s + nx * 11 * s,
                         from.dy - uy * 8 * s + ny * 11 * s);
    final baseR = Offset(from.dx - ux * 8 * s - nx * 11 * s,
                         from.dy - uy * 8 * s - ny * 11 * s);
    final p = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
      p,
      Paint()
        ..color = cDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  void _drawStar(Canvas canvas, Offset c, double outerR, double innerR,
                 double w) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final ang = -math.pi / 2 + i * math.pi / 5;
      final r = (i % 2 == 0) ? outerR : innerR;
      final x = c.dx + r * math.cos(ang);
      final y = c.dy + r * math.sin(ang);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    canvas.drawPath(p, Paint()..color = Colors.white);
    canvas.drawPath(
      p,
      Paint()
        ..color = cDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter5P old) => false;
}
