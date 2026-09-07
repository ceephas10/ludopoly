// Vector renderer for the Ludo board.
//
// Draws everything with Canvas primitives so the board stays crisp at any
// resolution (no raster scaling artifacts). Coordinates are expressed in the
// 15x15 grid; the painter converts to pixels using the widget size.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'board_path.dart' show ring;
import 'player_color.dart';
import 'upgrades.dart' show SpecialCells;

/// Les 4 emplacements de pion d'une base, en unités de case depuis son coin
/// haut-gauche. Partagés entre le socle peint ici et le pion posé dessus
/// par `main.dart` : une seule source, donc aucun risque de décalage.
const List<double> kBaseSlotsX = [1.5, 2.5, 3.5, 4.5];

/// Hauteur du centre de la CASE d'un emplacement, depuis le coin de la base.
const double kBaseSlotY = 1.4;

/// Côté du socle, en cases. C'est aussi la hauteur visible du pion.
const double kBaseSlotSize = 1.15;

class BoardPainter extends CustomPainter {
  /// Améliorations LudoPoly : quand un interrupteur est allumé, les cases
  /// correspondantes se dessinent par-dessus le plateau de base. Éteints
  /// (défaut), le plateau est EXACTEMENT celui d'avant.
  final bool showVortex;
  final bool showChance;
  const BoardPainter({this.showVortex = false, this.showChance = false});

  // Palette tuned to feel like the original Ludo King board.
  // Couleurs relevées sur le plateau de référence : franches et saturées,
  // là où les précédentes étaient délavées.
  static const Color _red    = Color(0xFFED1C24);
  static const Color _green  = Color(0xFF00A651);
  static const Color _blue   = Color(0xFF29ABE2);
  static const Color _yellow = Color(0xFFFFCB05);
  static const Color _gridLine = Color(0xFFAAAAAA);
  static const Color _bg     = Color(0xFF1A2541);

  /// Les deux ors de la case Chance : l'un pour les aplats, l'autre — plus
  /// sombre — pour les traits et le point d'interrogation, afin qu'ils
  /// tiennent sur la case blanche.
  static const Color _goldBright = Color(0xFFE8B923);
  static const Color _goldDeep   = Color(0xFF7A5B00);

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
      // Bande de couleur élargie : le blanc intérieur se resserre de 0,5 à
      // 0,85 case sur chaque bord.
      canvas.drawRect(
          rect(c0 + 0.85, r0 + 0.85, c0 + 5.15, r0 + 5.15),
          fill..color = Colors.white);
      // Un socle par pion : sur le blanc de la base, les quatre pions
      // flottaient sans rien pour les poser. Chaque socle occupe
      // exactement la place du pion — mêmes constantes, partagées avec la
      // couche qui les dessine.
      for (final sx in kBaseSlotsX) {
        final cx = (c0 + sx) * cell;
        // Le socle se pose SOUS la pointe des pieds, pas derrière le pion :
        // la pointe touche la case à `kBaseSlotY + 0.1`, le disque est
        // centré juste là. Il est aussi plus petit que le pion — c'est un
        // socle, pas un fond.
        final cy = (r0 + kBaseSlotY + 0.1) * cell;
        final r = kBaseSlotSize * cell * 0.30;
        canvas.drawCircle(Offset(cx, cy), r, fill..color = color);
        canvas.drawCircle(
            Offset(cx, cy),
            r * 0.82,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8, r * 0.10)
              ..color = Colors.white.withValues(alpha: 0.55));
      }
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

    // 4 bis) La flèche d'ENTRÉE : sur la dernière case d'anneau de chaque
    // couleur, elle montre par où le pion quitte l'anneau pour son couloir.
    // Bleu sur la 50, rouge sur la 11, vert sur la 24, jaune sur la 37 —
    // toutes à `départ + 50`.
    void drawEntryArrow(int cellIndex, double dx, double dy, Color color) {
      final c = ring[cellIndex].pos * cell;
      final a = cell * 0.26; // demi-longueur de la flèche
      final w = cell * 0.17; // demi-largeur de la base du triangle
      final tip = Offset(c.dx + dx * a, c.dy + dy * a);
      // Perpendiculaire au sens de la flèche.
      final px = -dy, py = dx;
      final b1 = Offset(c.dx - dx * a * 0.35 + px * w,
                        c.dy - dy * a * 0.35 + py * w);
      final b2 = Offset(c.dx - dx * a * 0.35 - px * w,
                        c.dy - dy * a * 0.35 - py * w);
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(b1.dx, b1.dy)
            ..lineTo(b2.dx, b2.dy)
            ..close(),
          Paint()..color = color);
    }

    // Le sens suit le couloir de la couleur : le bleu monte, le rouge va à
    // droite, le vert descend, le jaune va à gauche.
    drawEntryArrow(50, 0, -1, _blue);
    drawEntryArrow(11, 1, 0, _red);
    drawEntryArrow(24, 0, 1, _green);
    drawEntryArrow(37, -1, 0, _yellow);

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
    //
    // Aucune de ces cases n'a de fond : la case du plateau reste telle
    // qu'elle est, et c'est le DESSIN qui porte la couleur. Les ailes et
    // la tête de mort prennent celle de leur joueur ; la boîte cadeau
    // garde une teinte unique — l'or — parce que la case Chance
    // n'appartient à personne.
    if (showChance) {
      for (final idx in SpecialCells.chanceCells) {
        final c = ring[idx].pos;
        _drawGiftBox(canvas, c.dx * cell, c.dy * cell, cell);
      }
    }
    if (showVortex) {
      for (final color in SpecialCells.startOf.keys) {
        final tint = _playerColors[color]!;
        final g = ring[SpecialCells.goodVortexCell(color)].pos;
        _drawWings(canvas, g.dx * cell, g.dy * cell, cell, tint);
        final b = ring[SpecialCells.badVortexCell(color)].pos;
        _drawTopHatSkull(canvas, b.dx * cell, b.dy * cell, cell, tint);
      }
    }
  }

  /// Une paire d'ailes déployées, gravée sur une case.
  ///
  /// Deux ailes en miroir, pointes vers le bas, épaules jointes en haut —
  /// et quelques nervures pour suggérer les plumes. À la taille d'une case
  /// (30 à 50 px) c'est la SILHOUETTE qui doit se lire : inutile d'y
  /// graver chaque plume, elle deviendrait une tache. Elles portent la
  /// COULEUR de leur joueur, cernées de sombre pour rester lisibles sur la
  /// case nue.
  void _drawWings(
      Canvas canvas, double cx, double cy, double cell, Color color) {
    final s = cell * 0.40;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xE6101010)
      ..strokeWidth = math.max(0.7, cell * 0.022)
      ..strokeJoin = StrokeJoin.round;
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x99101010)
      ..strokeWidth = math.max(0.5, cell * 0.014)
      ..strokeCap = StrokeCap.round;

    // Le contour d'UNE aile, celle de droite, dans un repère centré :
    // l'épaule s'ouvre en haut près du centre, le bord extérieur descend
    // en trois festons — les pointes de plumes — jusqu'à la longue rémige
    // du bas, puis le bord intérieur remonte vers l'épaule.
    Path wing() => Path()
      ..moveTo(0.09 * s, -0.86 * s)
      ..cubicTo(
          0.58 * s, -1.02 * s, 1.06 * s, -0.60 * s, 0.97 * s, -0.20 * s)
      ..quadraticBezierTo(0.84 * s, -0.08 * s, 0.88 * s, 0.08 * s)
      ..quadraticBezierTo(0.72 * s, 0.14 * s, 0.72 * s, 0.32 * s)
      ..quadraticBezierTo(0.56 * s, 0.36 * s, 0.52 * s, 0.56 * s)
      ..quadraticBezierTo(0.41 * s, 0.62 * s, 0.29 * s, 1.04 * s)
      ..cubicTo(
          0.24 * s, 0.52 * s, 0.17 * s, 0.10 * s, 0.12 * s, -0.28 * s)
      ..close();

    void veins() {
      for (int i = 0; i < 4; i++) {
        final t = (i + 1) / 5.0;
        canvas.drawLine(
            Offset((0.14 + 0.04 * t) * s, (-0.55 + 1.30 * t) * s),
            Offset((0.80 - 0.48 * t) * s, (-0.32 + 1.20 * t) * s),
            vein);
      }
    }

    for (final mirror in [1.0, -1.0]) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(mirror, 1.0);
      final w = wing();
      canvas.drawPath(w, fill);
      canvas.drawPath(w, edge);
      veins();
      canvas.restore();
    }
  }

  /// La TÊTE DE MORT AU HAUT-DE-FORME du trou noir.
  ///
  /// Elle porte la COULEUR de son joueur : le crâne dans sa teinte, le
  /// chapeau dans la même assombrie. À l'échelle d'une case, ce qui la
  /// fait reconnaître tient à quatre choses : la silhouette du chapeau,
  /// les deux orbites creuses, le nez triangulaire et la rangée de dents.
  /// Le reste serait du bruit.
  void _drawTopHatSkull(
      Canvas canvas, double cx, double cy, double cell, Color color) {
    final ink = Paint()
      ..style = PaintingStyle.fill
      ..color = Color.lerp(color, const Color(0xFF000000), 0.62)!;
    final bone = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Color.lerp(color, const Color(0xFF000000), 0.62)!
      ..strokeWidth = math.max(0.5, cell * 0.016)
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(cx, cy);
    final u = cell;

    // --- le haut-de-forme -------------------------------------------------
    // La coiffe, puis le ruban, puis le bord large.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-0.20 * u, -0.44 * u, 0.40 * u, 0.26 * u),
            Radius.circular(u * 0.03)),
        ink);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-0.21 * u, -0.24 * u, 0.42 * u, 0.06 * u),
            Radius.circular(u * 0.02)),
        bone);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-0.34 * u, -0.20 * u, 0.68 * u, 0.07 * u),
            Radius.circular(u * 0.035)),
        ink);

    // --- le crâne ---------------------------------------------------------
    final skull = Path()
      ..moveTo(-0.21 * u, -0.02 * u)
      ..cubicTo(-0.23 * u, -0.16 * u, 0.23 * u, -0.16 * u, 0.21 * u,
          -0.02 * u)
      ..cubicTo(0.20 * u, 0.10 * u, 0.13 * u, 0.14 * u, 0.11 * u, 0.19 * u)
      ..lineTo(-0.11 * u, 0.19 * u)
      ..cubicTo(-0.13 * u, 0.14 * u, -0.20 * u, 0.10 * u, -0.21 * u,
          -0.02 * u)
      ..close();
    canvas.drawPath(skull, bone);
    canvas.drawPath(skull, line);

    // --- orbites, nez, dents ---------------------------------------------
    for (final sx in [-1.0, 1.0]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(sx * 0.095 * u, -0.035 * u),
              width: 0.115 * u,
              height: 0.105 * u),
          ink);
    }
    final nose = Path()
      ..moveTo(0, 0.015 * u)
      ..lineTo(0.035 * u, 0.085 * u)
      ..lineTo(-0.035 * u, 0.085 * u)
      ..close();
    canvas.drawPath(nose, ink);

    // La mâchoire : un bandeau clair barré de traits verticaux.
    final jaw = Rect.fromLTWH(-0.105 * u, 0.115 * u, 0.21 * u, 0.075 * u);
    canvas.drawRect(jaw, bone);
    canvas.drawRect(jaw, line);
    for (int i = 1; i < 5; i++) {
      final x = jaw.left + jaw.width * i / 5;
      canvas.drawLine(
          Offset(x, jaw.top), Offset(x, jaw.bottom), line);
    }
    canvas.restore();
  }

  /// La BOÎTE CADEAU MAGIQUE de la case Chance : le couvercle s'ouvre, une
  /// lueur en sort, et le point d'interrogation flotte au-dessus.
  ///
  /// Elle garde une teinte UNIQUE — l'or — quelle que soit la couleur du
  /// bras où elle se trouve : la case Chance n'appartient à personne.
  void _drawGiftBox(Canvas canvas, double cx, double cy, double cell) {
    final u = cell;
    final ink = Paint()
      ..style = PaintingStyle.fill
      ..color = _goldDeep;
    final gold = Paint()
      ..style = PaintingStyle.fill
      ..color = _goldBright;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = _goldDeep
      ..strokeWidth = math.max(0.5, cell * 0.018)
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(cx, cy);

    // La lueur qui s'échappe : trois halos de plus en plus larges.
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
          Offset(0, -0.04 * u),
          u * 0.10 * i,
          Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.11));
    }

    // Le corps de la boîte.
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(-0.26 * u, 0.02 * u, 0.52 * u, 0.32 * u),
        Radius.circular(u * 0.03));
    canvas.drawRRect(body, gold);
    canvas.drawRRect(body, line);
    // Le ruban vertical.
    canvas.drawRect(
        Rect.fromLTWH(-0.045 * u, 0.02 * u, 0.09 * u, 0.32 * u), ink);

    // Les deux battants du couvercle, ouverts vers l'extérieur.
    for (final sx in [-1.0, 1.0]) {
      final flap = Path()
        ..moveTo(sx * 0.04 * u, 0.02 * u)
        ..lineTo(sx * 0.30 * u, -0.10 * u)
        ..lineTo(sx * 0.40 * u, -0.02 * u)
        ..lineTo(sx * 0.10 * u, 0.10 * u)
        ..close();
      canvas.drawPath(flap, gold);
      canvas.drawPath(flap, line);
    }

    canvas.restore();

    // Le point d'interrogation, au-dessus de l'ouverture.
    _drawGlyph(canvas, '?', cx, cy - u * 0.20, u * 0.40, _goldDeep);
  }

  /// Couleur de plateau de chaque joueur, pour peindre sa case Vortex.
  static const Map<PlayerColor, Color> _playerColors = {
    PlayerColor.red: _red,
    PlayerColor.green: _green,
    PlayerColor.blue: _blue,
    PlayerColor.yellow: _yellow,
  };

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
