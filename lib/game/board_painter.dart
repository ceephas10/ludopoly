// Vector renderer for the Ludo board.
//
// Draws everything with Canvas primitives so the board stays crisp at any
// resolution (no raster scaling artifacts). Coordinates are expressed in the
// 15x15 grid; the painter converts to pixels using the widget size.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'board_path.dart' show ring;
import 'upgrades.dart' show SpecialCells;

class BoardPainter extends CustomPainter {
  /// Améliorations LudoPoly : quand un interrupteur est allumé, les cases
  /// correspondantes se dessinent par-dessus le plateau de base. Éteints
  /// (défaut), le plateau est EXACTEMENT celui d'avant.
  final bool showVortex;
  final bool showChance;
  const BoardPainter({this.showVortex = false, this.showChance = false});

  // Palette tuned to feel like the original Ludo King board.
  static const Color _red    = Color(0xFFE94B4B);
  static const Color _green  = Color(0xFF4FAE5D);
  static const Color _blue   = Color(0xFF3DA4EC);
  static const Color _yellow = Color(0xFFFFCE2E);
  static const Color _gridLine = Color(0xFFAAAAAA);
  static const Color _bg     = Color(0xFF1A2541);

  /// Couleur NEUTRE des cases Chance — la spec demande une couleur qui
  /// n'appartient à aucun joueur : un violet absent de la palette.
  static const Color _chance = Color(0xFF8E44AD);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 15.0;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _gridLine
      ..strokeWidth = math.max(1.0, cell * 0.03);

    Rect cr(int col, int row) =>
        Rect.fromLTWH(col * cell, row * cell, cell, cell);
    Rect rect(double c0, double r0, double c1, double r1) =>
        Rect.fromLTRB(c0 * cell, r0 * cell, c1 * cell, r1 * cell);

    // 1) Dark backdrop (outside the cross).
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        fill..color = _bg);

    // 2) White cross.
    fill.color = Colors.white;
    canvas.drawRect(rect(6, 0, 9, 15), fill);   // vertical band
    canvas.drawRect(rect(0, 6, 15, 9), fill);   // horizontal band

    // 3) 4 colored bases (6x6 corners with inner 5x5 white — enlarged by
    //    half a cell on each side compared to the standard Ludo layout, to
    //    leave room for the LudoPoly extension content).
    void drawBase(double c0, double r0, Color color) {
      canvas.drawRect(rect(c0, r0, c0 + 6, r0 + 6), fill..color = color);
      canvas.drawRect(
          rect(c0 + 0.5, r0 + 0.5, c0 + 5.5, r0 + 5.5),
          fill..color = Colors.white);
    }
    drawBase(0, 0, _red);     // top-left
    drawBase(9, 0, _green);   // top-right
    drawBase(0, 9, _blue);    // bottom-left
    drawBase(9, 9, _yellow);  // bottom-right

    // 4) Home stretches (5 colored cells per color leading to the center).
    fill.color = _red;
    canvas.drawRect(rect(1, 7, 6, 8), fill);
    fill.color = _green;
    canvas.drawRect(rect(7, 1, 8, 6), fill);
    fill.color = _yellow;
    canvas.drawRect(rect(9, 7, 14, 8), fill);
    fill.color = _blue;
    canvas.drawRect(rect(7, 9, 8, 14), fill);

    // 5) Start squares (cell just outside each base, colored).
    final starts = <_Start>[
      _Start(1, 6, _red),
      _Start(8, 1, _green),
      _Start(13, 8, _yellow),
      _Start(6, 13, _blue),
    ];
    for (final s in starts) {
      canvas.drawRect(cr(s.col, s.row), fill..color = s.color);
    }

    // 6) Center triangles converging at the middle.
    final cx = 7.5 * cell;
    final cy = 7.5 * cell;
    final lt = Offset(6 * cell, 6 * cell);
    final rt = Offset(9 * cell, 6 * cell);
    final rb = Offset(9 * cell, 9 * cell);
    final lb = Offset(6 * cell, 9 * cell);
    final center = Offset(cx, cy);
    _drawTri(canvas, fill, lt, lb, center, _red);
    _drawTri(canvas, fill, lt, rt, center, _green);
    _drawTri(canvas, fill, rt, rb, center, _yellow);
    _drawTri(canvas, fill, lb, rb, center, _blue);

    // 7) Grid lines on every cell of the cross.
    void hline(double x0, double x1, double y) {
      canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke);
    }
    void vline(double x, double y0, double y1) {
      canvas.drawLine(Offset(x, y0), Offset(x, y1), stroke);
    }
    // Top arm
    for (int c = 6; c <= 9; c++) { vline(c * cell, 0, 6 * cell); }
    for (int r = 0; r <= 6; r++) { hline(6 * cell, 9 * cell, r * cell); }
    // Bottom arm
    for (int c = 6; c <= 9; c++) { vline(c * cell, 9 * cell, 15 * cell); }
    for (int r = 9; r <= 15; r++) { hline(6 * cell, 9 * cell, r * cell); }
    // Horizontal band
    for (int c = 0; c <= 15; c++) { vline(c * cell, 6 * cell, 9 * cell); }
    for (int r = 6; r <= 9; r++) { hline(0, 15 * cell, r * cell); }

    // 8) Safe stars (4 cells on the ring).
    const stars = [[2, 8], [6, 2], [12, 6], [8, 12]];
    for (final s in stars) {
      _drawStar(canvas, s[0], s[1], cell);
    }

    // 9) Améliorations LudoPoly (uniquement quand activées).
    if (showChance) {
      // Les 4 cases Chance, neutres : fond violet + « ? » blanc.
      for (final idx in SpecialCells.chanceCells) {
        final c = ring[idx].pos;
        final r = Rect.fromCenter(
            center: Offset(c.dx * cell, c.dy * cell),
            width: cell * 0.92,
            height: cell * 0.92);
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cell * 0.14)),
            Paint()..color = _chance);
        _drawGlyph(canvas, '?', c.dx * cell, c.dy * cell, cell * 0.62,
            Colors.white);
      }
    }
    if (showVortex) {
      // Vortex BONS : une spirale blanche sur chaque case de départ.
      for (final color in SpecialCells.startOf.keys) {
        final c = ring[SpecialCells.goodVortexCell(color)].pos;
        _drawSpiral(canvas, c.dx * cell, c.dy * cell, cell, Colors.white);
      }
      // Vortex MAUVAIS : une spirale sombre sur la 1re case du couloir de
      // chaque couleur (l'entrée de la dernière ligne droite).
      const badCells = [
        [1.5, 7.5],   // rouge
        [7.5, 1.5],   // vert
        [13.5, 7.5],  // jaune
        [7.5, 13.5],  // bleu
      ];
      for (final b in badCells) {
        _drawSpiral(canvas, b[0] * cell, b[1] * cell, cell,
            const Color(0xE6202020));
      }
    }
  }

  /// Petite spirale d'Archimède (statique — le rendu animé, s'il arrive un
  /// jour, sera un asset du Studio Animations).
  void _drawSpiral(Canvas canvas, double cx, double cy, double cell,
      Color color) {
    final p = Path();
    const turns = 2.2;
    final maxR = cell * 0.34;
    for (double t = 0; t <= 1.0; t += 0.02) {
      final angle = t * turns * 2 * math.pi;
      final r = maxR * t;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (t == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.5, cell * 0.10));
  }

  /// Un caractère centré sur une case (statique).
  void _drawGlyph(Canvas canvas, String glyph, double cx, double cy,
      double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _drawTri(Canvas c, Paint fill, Offset a, Offset b, Offset center, Color color) {
    fill.color = color;
    final p = Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(center.dx, center.dy)..close();
    c.drawPath(p, fill);
  }

  void _drawStar(Canvas canvas, int col, int row, double cell) {
    final cx = (col + 0.5) * cell;
    final cy = (row + 0.5) * cell;
    final outerR = cell * 0.36;
    final innerR = cell * 0.16;
    final p = Path();
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = (i % 2 == 0) ? outerR : innerR;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    canvas.drawPath(p, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF2A2A2A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, cell * 0.05)
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.showVortex != showVortex || old.showChance != showChance;
}

class _Start {
  final int col;
  final int row;
  final Color color;
  const _Start(this.col, this.row, this.color);
}
