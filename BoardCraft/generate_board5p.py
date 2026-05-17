"""Generate `Board5p.png` from scratch — a vectorial 5-player Ludo board,
similar in spirit to the 4-player `BoardPainter` in the Flutter game.

The geometry comes from `boardcraft.json` (each region annotated by hand
in the BoardCraft tool). We DON'T overlay the photo — we PAINT a clean
new board using the polygons/surfaces in the JSON as the source of truth.

Input:  BoardCraft/boardcraft.json   (and optionally the JPEG as ref)
Output: BoardCraft/Board5p.png       (1332 x 1265, RGB)
"""
import os
import json
import math
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
JSON = os.path.join(HERE, "boardcraft.json")
OUT  = os.path.join(HERE, "Board5p.png")

# ----------------------------------------------------------------------
# Palette — matches the LudoKing 5-player visual identity.
# ----------------------------------------------------------------------
COLORS = {
    "Bleu":    "#3DA4EC",
    "Orange":  "#F08C2A",
    "Vert":    "#1FA84E",
    "Rouge":   "#D33232",
    "Jaune":   "#F2C61F",
}
DICE_BLUE = "#1F9CE6"
WHITE     = "#FFFFFF"
GREY_LINE = "#9A9A9A"
DARK      = "#1F1F1F"

CANVAS_W, CANVAS_H = 1332, 1265

# ----------------------------------------------------------------------
# Load annotations and index by label.
# ----------------------------------------------------------------------
with open(JSON, "r", encoding="utf-8") as f:
    data = json.load(f)
annots = data["annotations"]

# Map label -> annotation (labels are unique in this JSON).
by_label = {a["label"]: a for a in annots}

def pts(label):
    """Return list of (x, y) tuples for annotation with given label."""
    a = by_label.get(label)
    if a is None:
        raise KeyError(f"missing annotation: {label!r}")
    return [(p["x"], p["y"]) for p in a["points"]]


def pt(label):
    """Return first (x, y) point for annotation with given label."""
    return pts(label)[0]


# ----------------------------------------------------------------------
# Canvas
# ----------------------------------------------------------------------
img = Image.new("RGBA", (CANVAS_W, CANVAS_H), WHITE)
d = ImageDraw.Draw(img)


def poly(points, fill=None, outline=None, width=1):
    if fill is not None:
        d.polygon(points, fill=fill)
    if outline is not None:
        d.line(list(points) + [points[0]], fill=outline, width=width)


def stroke(points, color, width=2, closed=False):
    if closed:
        d.line(list(points) + [points[0]], fill=color, width=width)
    else:
        d.line(list(points), fill=color, width=width)


def filled_circle(c, r, fill, outline=None, width=1):
    x, y = c
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill,
              outline=outline, width=width)


def load_font(size, bold=False):
    paths = ([r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf"]
             if bold else
             [r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\arial.ttf"])
    for p in paths:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# ----------------------------------------------------------------------
# 0) Board outline (decagonal) — fill light cream, dark outline.
# ----------------------------------------------------------------------
board_pts = pts("Board")
poly(board_pts, fill="#FBFBFB", outline=DARK, width=4)

# ----------------------------------------------------------------------
# 1) Ring corridor — fill the ring polygon with light gray, then carve
#    out the inner regions (couloirs, pentagone home/dé) which we will
#    over-paint in step 2+. The ring polygon is the "outline" of the
#    ring track.
# ----------------------------------------------------------------------
ring_pts = pts("Ring depuis le départ Bleu")
poly(ring_pts, fill="#EFEFEF", outline=GREY_LINE, width=2)

# ----------------------------------------------------------------------
# 2) Player BANDEAU triangles (the colored outer ribbon of each base).
# ----------------------------------------------------------------------
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    poly(pts(f"Bandeau base {color_name}"),
         fill=COLORS[color_name], outline=DARK, width=3)

# ----------------------------------------------------------------------
# 3) Player YARDS (the white interior triangle inside each bandeau).
# ----------------------------------------------------------------------
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    poly(pts(f"Yard {color_name}"),
         fill=WHITE, outline=GREY_LINE, width=2)

# ----------------------------------------------------------------------
# 4) Couloirs maison (the colored 5-cell strips toward the center).
# ----------------------------------------------------------------------
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    couloir = pts(f"Couloir maison {color_name}")
    poly(couloir, fill=COLORS[color_name], outline=DARK, width=2)

    # Subdivide into 5 cells along the corridor's main axis. The corridor
    # is a 4-vertex quad ordered roughly as (outer-near, outer-far,
    # inner-far, inner-near). We linearly interpolate along the long
    # edges to draw 4 dividing lines.
    if len(couloir) == 4:
        outer = (couloir[0], couloir[3])  # along outer edge
        inner = (couloir[1], couloir[2])  # along inner edge
        for k in range(1, 5):
            t = k / 5.0
            a = (outer[0][0] + (outer[1][0] - outer[0][0]) * t,
                 outer[0][1] + (outer[1][1] - outer[0][1]) * t)
            b = (inner[0][0] + (inner[1][0] - inner[0][0]) * t,
                 inner[0][1] + (inner[1][1] - inner[0][1]) * t)
            d.line([a, b], fill=DARK, width=2)

# ----------------------------------------------------------------------
# 5) Pentagone Home + 5 colored Home triangles inside.
# ----------------------------------------------------------------------
poly(pts("Pentagone Home"), fill=WHITE, outline=DARK, width=2)
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    poly(pts(f"Home {color_name}"),
         fill=COLORS[color_name], outline=DARK, width=2)

# ----------------------------------------------------------------------
# 6) Pentagone Dé (white) + dice cell.
# ----------------------------------------------------------------------
poly(pts("Pentagone Dé"), fill=WHITE, outline=DARK, width=3)

# Dice: small colored rounded square at the dice point.
dx, dy = pt("Dé")
dr = 42
d.rounded_rectangle([dx - dr, dy - dr, dx + dr, dy + dr],
                    radius=10, fill=DICE_BLUE, outline=DARK, width=3)
# A single white pip in the middle to suggest a die.
filled_circle((dx, dy), 9, fill=WHITE)

# ----------------------------------------------------------------------
# 7) Cases départ — colored squares (1 cell ≈ 70 px) at each start point.
# ----------------------------------------------------------------------
START_HALF = 32
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    sx, sy = pt(f"Case départ {color_name}")
    d.rectangle([sx - START_HALF, sy - START_HALF,
                 sx + START_HALF, sy + START_HALF],
                fill=COLORS[color_name], outline=DARK, width=3)
    # White entry arrow inside (pointing inward toward the board center).
    cx_board, cy_board = pt("Dé")
    dx_, dy_ = cx_board - sx, cy_board - sy
    L = math.hypot(dx_, dy_) or 1
    ux, uy = dx_ / L, dy_ / L
    nx, ny = -uy, ux  # perpendicular
    tip = (sx + ux * 16, sy + uy * 16)
    base_l = (sx - ux * 12 + nx * 10, sy - uy * 12 + ny * 10)
    base_r = (sx - ux * 12 - nx * 10, sy - uy * 12 - ny * 10)
    d.polygon([tip, base_l, base_r], fill=WHITE, outline=DARK)

# ----------------------------------------------------------------------
# 8) Étoiles safe — 5-pointed stars at each safe cell.
# ----------------------------------------------------------------------
def draw_star(cx, cy, outer_r=22, inner_r=10, fill=WHITE, outline=DARK):
    p = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        r = outer_r if i % 2 == 0 else inner_r
        p.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d.polygon(p, fill=fill, outline=outline)

for (sx, sy) in pts("Cases Etoile"):
    draw_star(sx, sy)

# ----------------------------------------------------------------------
# 9) Entrée couloir maison — small colored arrowhead at each entry,
#    pointing along the corridor toward the center.
# ----------------------------------------------------------------------
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    ex, ey = pt(f"Entrée couloir maison {color_name}")
    # Direction = from entry point toward Home center of that color.
    hx, hy = pt(f"Maison {color_name}")
    dx_, dy_ = hx - ex, hy - ey
    L = math.hypot(dx_, dy_) or 1
    ux, uy = dx_ / L, dy_ / L
    nx, ny = -uy, ux
    tip   = (ex + ux * 18, ey + uy * 18)
    base_l = (ex - ux * 8 + nx * 11, ey - uy * 8 + ny * 11)
    base_r = (ex - ux * 8 - nx * 11, ey - uy * 8 - ny * 11)
    d.polygon([tip, base_l, base_r], fill=COLORS[color_name],
              outline=DARK)

# ----------------------------------------------------------------------
# 10) Player token slots — small colored circles in each yard (3 or 4
#     positions as defined in the JSON).
# ----------------------------------------------------------------------
TOK_R = 22
# Labels in the JSON are inconsistent ("verts" vs "Vert", double-spaces…).
TOKEN_LABEL = {
    "Bleu":   "4 tokens Bleu",
    "Orange": "4 tokens Orange",
    "Vert":   "4 tokens verts",
    "Rouge":  "4 tokens  rouge",
    "Jaune":  "4 tokens Jaune",
}
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    for (tx, ty) in pts(TOKEN_LABEL[color_name]):
        filled_circle((tx, ty), TOK_R + 4, fill="#FFFFFF",
                      outline=DARK, width=2)
        filled_circle((tx, ty), TOK_R, fill=COLORS[color_name],
                      outline=DARK, width=2)

# ----------------------------------------------------------------------
# 11) Player banner (e.g. "Player 1" tab below P1, etc.) — small colored
#     plates centered on each base's outer apex.
# ----------------------------------------------------------------------
PLAYER_LABEL = {
    "Bleu": "Player 1", "Orange": "Player 2", "Vert": "Player 3",
    "Rouge": "Player 4", "Jaune": "Player 5",
}
f_label = load_font(22, bold=True)
for color_name in ("Bleu", "Orange", "Vert", "Rouge", "Jaune"):
    bandeau = pts(f"Bandeau base {color_name}")
    # outer apex = vertex farthest from the dice center
    cx_die, cy_die = pt("Dé")
    apex = max(bandeau, key=lambda p: math.hypot(p[0] - cx_die, p[1] - cy_die))
    # Place a small label rectangle near the apex, offset slightly outward.
    dx_, dy_ = apex[0] - cx_die, apex[1] - cy_die
    L = math.hypot(dx_, dy_) or 1
    ux, uy = dx_ / L, dy_ / L
    cx_lbl = apex[0] + ux * 12
    cy_lbl = apex[1] + uy * 12
    txt = PLAYER_LABEL[color_name]
    # Background plate (color)
    bbox = d.textbbox((cx_lbl, cy_lbl), txt, font=f_label, anchor="mm")
    pad = 10
    d.rounded_rectangle(
        [bbox[0] - pad, bbox[1] - pad // 2, bbox[2] + pad, bbox[3] + pad // 2],
        radius=8, fill=COLORS[color_name], outline=DARK, width=2)
    d.text((cx_lbl, cy_lbl), txt, fill=WHITE, font=f_label, anchor="mm")

# ----------------------------------------------------------------------
# Save (flatten to RGB for compactness).
# ----------------------------------------------------------------------
final = Image.new("RGB", (CANVAS_W, CANVAS_H), WHITE)
final.paste(img, (0, 0), img)
final.save(OUT, "PNG", optimize=True)
print(f"Saved: {OUT}  ({CANVAS_W} x {CANVAS_H})")
