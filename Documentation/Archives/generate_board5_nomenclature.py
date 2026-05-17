"""Generate Board5_Nomenclature.png — the 5-player Ludo board diagram with
labeled parts, matching the visual style of Board4_Nomenclature.png.

Geometry (matches LudoKing 5-player layout):
  - Board inscribed in a regular decagon (10 vertices, R_outer).
  - 5 sectors of 72 degrees each, one per player.
  - Each sector contains:
      * Triangular base on the outer side (3 pawn slots).
      * 5-cell radial home column (colored) leading toward the center.
      * Ring cells running along the sector boundary (3-cell wide strips
        forming a path that wraps around the board through all 5 sectors).
      * One safe star on the ring.
      * One start cell (colored, with entry arrow) at the sector edge.
  - Central pentagon (white) with a blue dice.
  - 5-pointed star (home) overlays the inner pentagon edges (each colored
    triangle is one player's "home arrival" zone).

Output:
  Documentation/Board5_Nomenclature.png

Note: This is a SCHEMATIC, not a pixel-perfect reproduction of LudoKing's
asset. It exists to share vocabulary between human + AI when discussing
the 5-player board parts.
"""

import math
import os
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Polygon, Circle, FancyArrow, FancyBboxPatch
from matplotlib.path import Path
import matplotlib.lines as mlines

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OUT = os.path.join(os.path.dirname(__file__), "..", "Board5_Nomenclature.png")

# Player order: P1 (bottom) clockwise -- matches LudoKing 5p layout.
# Angles in degrees, measured from +X axis (math convention), CCW positive.
# In screen coords matplotlib uses (math y up), so 270° = bottom of screen.
PLAYER_ANGLES = [270, 198, 126, 54, 342]  # P1..P5 (degrees CCW)
PLAYER_COLORS = ["#3DA4EC", "#F08C2A", "#2E8B47", "#D33232", "#E6B800"]
PLAYER_NAMES = ["P1 Bleu", "P2 Orange", "P3 Vert", "P4 Rouge", "P5 Jaune"]
PLAYER_LETTERS = ["B", "O", "V", "R", "J"]

# Board radii (arbitrary units; scale set via figsize)
R_OUTER = 100.0          # outer decagon vertex radius
R_BASE_TIP = 36.0        # inner tip of each triangular base (toward center)
R_HOME_OUTER = 36.0      # outer edge of home column (= R_BASE_TIP)
R_HOME_INNER = 8.0       # inner edge of home column (touches center pentagon)
R_CENTER = 8.0           # center pentagon outer radius

# ---------------------------------------------------------------------------
# Figure setup
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(16, 11), dpi=150)
ax.set_aspect("equal")
ax.axis("off")
# Title + subtitle
fig.text(0.04, 0.96, "Nomenclature du Board 5 joueurs",
         fontsize=22, fontweight="normal", ha="left", va="top")
fig.text(0.04, 0.925,
         "Vocabulaire partagé pour parler des parties du plateau pentagonal.",
         fontsize=12, color="#666666", ha="left", va="top")

# Plot bounds — leave room for labels on left and right
ax.set_xlim(-260, 240)
ax.set_ylim(-130, 130)


def deg2rad(d):
    return math.radians(d)


def polar(r, deg):
    a = deg2rad(deg)
    return (r * math.cos(a), r * math.sin(a))


# ---------------------------------------------------------------------------
# 1) Draw outer decagon (white fill, thin border)
# ---------------------------------------------------------------------------
# Decagon vertices at angles offset by 18° from sector centers so that each
# sector spans from one decagon vertex to the next.
decagon = [polar(R_OUTER, 18 + 36 * i) for i in range(10)]
ax.add_patch(Polygon(decagon, closed=True,
                     facecolor="#FAFAFA", edgecolor="#222", linewidth=1.5))


# ---------------------------------------------------------------------------
# 2) Draw 5 sectors -- triangular base + ring strip + home column + start
# ---------------------------------------------------------------------------
def draw_sector(angle_deg, color, name, letter, idx):
    """Draw all elements of one sector centered on `angle_deg`."""
    # Sector spans angle ± 36° (= 72/2)
    a_center = angle_deg
    a_left = angle_deg + 36
    a_right = angle_deg - 36

    # ---- Base triangle (filled colored, outer side) ----
    # 3 vertices: 2 outer decagon vertices, 1 inner tip toward center
    v1 = polar(R_OUTER, a_left)
    v2 = polar(R_OUTER, a_right)
    tip = polar(R_BASE_TIP + 25, a_center)  # base extends ~25 toward center
    ax.add_patch(Polygon([v1, v2, tip], closed=True,
                         facecolor=color, edgecolor="#222", linewidth=1.2))

    # ---- Yard (white inner triangle inside the base) ----
    shrink = 0.85
    v1y = polar(R_OUTER * shrink, a_left)
    v2y = polar(R_OUTER * shrink, a_right)
    tipy = polar((R_BASE_TIP + 25) * shrink + 6, a_center)
    ax.add_patch(Polygon([v1y, v2y, tipy], closed=True,
                         facecolor="white", edgecolor="#888", linewidth=0.7))

    # ---- 3 pawn slots inside the yard ----
    # Arrange 3 circles roughly inside the triangle.
    slot_r = 5
    cx, cy = polar((R_OUTER * shrink + (R_BASE_TIP + 25) * shrink) / 2, a_center)
    # Spread perpendicular to the radial axis
    perp = (math.cos(deg2rad(a_center + 90)),
            math.sin(deg2rad(a_center + 90)))
    offsets = [-1, 0, 1]
    for j, off in enumerate(offsets):
        px = cx + perp[0] * off * 11
        py = cy + perp[1] * off * 11
        ax.add_patch(Circle((px, py), slot_r,
                            facecolor=color, edgecolor="#222", linewidth=0.8))
        ax.text(px, py, str(j), ha="center", va="center",
                fontsize=7, color="white", fontweight="bold")

    # ---- Home column (radial colored strip from R_HOME_OUTER inward) ----
    # 5 cells stacked along the radial direction.
    home_width = 14  # cell perpendicular width
    n_cells = 5
    cell_len = (R_HOME_OUTER - R_HOME_INNER) / n_cells
    for k in range(n_cells):
        r0 = R_HOME_OUTER - k * cell_len
        r1 = R_HOME_OUTER - (k + 1) * cell_len
        # Cell rectangle: 4 corners in polar -> cartesian
        c1 = polar(r0, a_center - math.degrees(math.atan2(home_width/2, r0)))
        c2 = polar(r0, a_center + math.degrees(math.atan2(home_width/2, r0)))
        c3 = polar(r1, a_center + math.degrees(math.atan2(home_width/2, r1)))
        c4 = polar(r1, a_center - math.degrees(math.atan2(home_width/2, r1)))
        ax.add_patch(Polygon([c1, c2, c3, c4], closed=True,
                             facecolor=color, edgecolor="#222", linewidth=0.5))

    # ---- Ring strip on each sector edge (3 cells wide) ----
    # Run from R_BASE_TIP + 25 outward to R_OUTER, along the angle a_left and
    # a_right boundaries. Simplified: draw a single white-bg strip with
    # 3 cell divisions, on the LEFT edge of this sector.
    edge_angle = a_left
    strip_width = 10
    strip_r0 = R_BASE_TIP + 25
    strip_r1 = R_OUTER * shrink
    # Construct a thin radial corridor (just visualize as 3 small white cells)
    for k in range(3):
        rA = strip_r0 + k * (strip_r1 - strip_r0) / 3
        rB = strip_r0 + (k + 1) * (strip_r1 - strip_r0) / 3
        a_lo = edge_angle - math.degrees(math.atan2(strip_width/2, rA))
        a_hi = edge_angle + math.degrees(math.atan2(strip_width/2, rA))
        a_lo2 = edge_angle - math.degrees(math.atan2(strip_width/2, rB))
        a_hi2 = edge_angle + math.degrees(math.atan2(strip_width/2, rB))
        c1 = polar(rA, a_lo)
        c2 = polar(rA, a_hi)
        c3 = polar(rB, a_hi2)
        c4 = polar(rB, a_lo2)
        ax.add_patch(Polygon([c1, c2, c3, c4], closed=True,
                             facecolor="white", edgecolor="#666", linewidth=0.5))

    # ---- Start cell (colored, on the ring, at the sector's far-left edge) ----
    # Position: the OUTER end of the left-edge corridor, painted in player color.
    rA = strip_r1 - (strip_r1 - strip_r0) / 3
    rB = strip_r1
    a_lo = edge_angle - math.degrees(math.atan2(strip_width/2, rA))
    a_hi = edge_angle + math.degrees(math.atan2(strip_width/2, rA))
    a_lo2 = edge_angle - math.degrees(math.atan2(strip_width/2, rB))
    a_hi2 = edge_angle + math.degrees(math.atan2(strip_width/2, rB))
    c1 = polar(rA, a_lo)
    c2 = polar(rA, a_hi)
    c3 = polar(rB, a_hi2)
    c4 = polar(rB, a_lo2)
    ax.add_patch(Polygon([c1, c2, c3, c4], closed=True,
                         facecolor=color, edgecolor="#222", linewidth=0.8))
    # Entry arrow pointing inward
    midA = polar((rA + rB) / 2, edge_angle)
    inward = polar((rA + rB) / 2 - 6, edge_angle)
    ax.annotate("", xy=inward, xytext=midA,
                arrowprops=dict(arrowstyle="->", color="white", lw=1.5))

    # ---- Safe star on the ring (mid-edge of the sector) ----
    star_r = (strip_r0 + strip_r1) / 2
    sx, sy = polar(star_r, edge_angle - 12)
    star_pts = []
    for s in range(10):
        rr = 3.5 if s % 2 == 0 else 1.5
        aa = deg2rad(90 + s * 36)
        star_pts.append((sx + rr * math.cos(aa), sy + rr * math.sin(aa)))
    ax.add_patch(Polygon(star_pts, closed=True,
                         facecolor="white", edgecolor="#333", linewidth=0.8))


for i in range(5):
    draw_sector(PLAYER_ANGLES[i], PLAYER_COLORS[i],
                PLAYER_NAMES[i], PLAYER_LETTERS[i], i)


# ---------------------------------------------------------------------------
# 3) Central pentagon (white, holds dice) + colored home triangles
# ---------------------------------------------------------------------------
# 5 colored triangles meeting at center (the "home" arrival zone, one per player)
for i, (ang, color) in enumerate(zip(PLAYER_ANGLES, PLAYER_COLORS)):
    a_left = ang + 36
    a_right = ang - 36
    # Triangle from center to two inner pentagon vertices
    v0 = (0, 0)
    v1 = polar(R_HOME_INNER, a_left)
    v2 = polar(R_HOME_INNER, a_right)
    ax.add_patch(Polygon([v0, v1, v2], closed=True,
                         facecolor=color, edgecolor="#222", linewidth=0.5,
                         alpha=0.85))

# Central pentagon (white) with dice
pentagon_verts = [polar(R_CENTER * 0.6, 90 + 72 * k) for k in range(5)]
ax.add_patch(Polygon(pentagon_verts, closed=True,
                     facecolor="white", edgecolor="#222", linewidth=1))
# Dice
ax.add_patch(Circle((0, 0), 3.5, facecolor="#3DA4EC",
                    edgecolor="#222", linewidth=0.8))


# ---------------------------------------------------------------------------
# 4) Labels with arrows
# ---------------------------------------------------------------------------
def label(x_target, y_target, x_text, y_text, text, ha="left"):
    """Draw a yellow-box label connected by a line to a target point."""
    # Yellow rounded box
    bbox = dict(boxstyle="round,pad=0.4", facecolor="#FFE680",
                edgecolor="#B8860B", linewidth=0.8)
    ax.annotate(text, xy=(x_target, y_target),
                xytext=(x_text, y_text), fontsize=10,
                ha=ha, va="center", bbox=bbox,
                arrowprops=dict(arrowstyle="-", color="#222", lw=0.8))


# P3 Vert (haut-gauche) base
v3a = deg2rad(126)
label(R_OUTER * 0.7 * math.cos(v3a),
      R_OUTER * 0.7 * math.sin(v3a),
      -240, 105, "Base (triangle)", ha="left")

# P3 Yard
label(R_OUTER * 0.78 * math.cos(v3a) + 8,
      R_OUTER * 0.78 * math.sin(v3a) + 6,
      -240, 80, "Yard (token area)\n3 pions seulement", ha="left")

# P3 Bandeau joueur (outer edge of base)
v3_outer = polar(R_OUTER, 126)
label(v3_outer[0], v3_outer[1] + 5,
      -240, 50, "Bandeau joueur", ha="left")

# Ring (between P3 and P4, top center)
v_ring_top = polar(R_OUTER * 0.85, 90)
label(v_ring_top[0], v_ring_top[1],
      -240, 25, "Ring (50 cases)", ha="left")

# Couloir maison (home column) -- P3 corridor
v_corr = polar(R_HOME_OUTER * 0.6, 126)
label(v_corr[0] - 8, v_corr[1],
      -240, 0, "Couloir maison\n(5 cases)", ha="left")

# Start cell with arrow (P3, on left edge of sector)
v_start = polar(R_OUTER * 0.93, 126 + 30)
label(v_start[0], v_start[1],
      -240, -30, "Case départ +\nFlèche d'entrée", ha="left")

# Safe star (P3 area)
v_star = polar((R_OUTER + R_BASE_TIP + 25) / 2 * 0.95, 126 + 24)
label(v_star[0] - 6, v_star[1] - 5,
      -240, -60, "Étoile (safe)", ha="left")

# ---- Right-side labels ----
# Home / center
label(0, 0, 220, 100, "Home (centre)\n+ dé", ha="left")

# Triangle home (one of the 5 colored triangles at center)
v_th = polar(R_HOME_INNER * 0.7, 54)
label(v_th[0], v_th[1], 220, 70, "Triangle home\n(par couleur)", ha="left")

# Décagone
v_dec = polar(R_OUTER, 0)
label(v_dec[0], v_dec[1], 220, 40, "Plateau décagonal\n(10 côtés)", ha="left")

# P5 Jaune base
v5 = deg2rad(342)
label(R_OUTER * 0.7 * math.cos(v5),
      R_OUTER * 0.7 * math.sin(v5),
      220, 10, "Base P5 (jaune)", ha="left")

# P1 Bleu (bottom)
v1 = polar(R_OUTER * 0.7, 270)
label(v1[0], v1[1], 220, -25, "Base P1 (bleu)\n3 pions: 0, 1, 2", ha="left")

# P2 Orange (bottom-left)
v2 = polar(R_OUTER * 0.7, 198)
label(v2[0] + 5, v2[1] - 5, 220, -55, "Base P2 (orange)", ha="left")

# Sectors / 72°
ax.annotate("5 secteurs de 72°", xy=(0, -R_OUTER * 0.5),
            xytext=(220, -85),
            fontsize=10, ha="left", va="center",
            bbox=dict(boxstyle="round,pad=0.4",
                      facecolor="#FFE680", edgecolor="#B8860B", linewidth=0.8),
            arrowprops=dict(arrowstyle="-", color="#222", lw=0.8))

# ---------------------------------------------------------------------------
# 5) Footer note
# ---------------------------------------------------------------------------
fig.text(0.5, 0.02,
         "Comparaison avec le board 4 joueurs : "
         "carré 15×15 → décagone | 4 pions/couleur → 3 pions/couleur | "
         "ring 52 cases → ring ~50 cases | croix centrale 4 home → pentagon centrale 5 home",
         fontsize=9, color="#444", ha="center", va="bottom",
         style="italic")

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
plt.savefig(OUT, dpi=150, bbox_inches="tight",
            facecolor="white", edgecolor="none")
print(f"Saved: {OUT}")
