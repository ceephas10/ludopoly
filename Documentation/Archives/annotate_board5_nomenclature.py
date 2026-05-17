"""Annotate the LudoKing 5-player board photo with labels for shared
vocabulary (matches the style of Board4_Nomenclature.png).

The ORIGINAL JPEG is used as-is for the board itself. We only paste it onto
a wider white canvas and draw yellow label boxes + thin arrows pointing to
each feature.

Output: Documentation/Board5_Nomenclature.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "Ludo King Board 5 players.jpeg")
OUT = os.path.join(HERE, "..", "Board5_Nomenclature.png")

# ---- Canvas / image placement ---------------------------------------------
board = Image.open(SRC).convert("RGB")
BW, BH = board.size  # 1332 x 1600

# Margins: left & right for labels, top for title.
LEFT_MARGIN = 440
RIGHT_MARGIN = 440
TOP_MARGIN = 180
BOTTOM_MARGIN = 60
CW = BW + LEFT_MARGIN + RIGHT_MARGIN
CH = BH + TOP_MARGIN + BOTTOM_MARGIN

canvas = Image.new("RGB", (CW, CH), "white")
canvas.paste(board, (LEFT_MARGIN, TOP_MARGIN))

draw = ImageDraw.Draw(canvas)

# ---- Fonts -----------------------------------------------------------------
def load_font(size, bold=False):
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()

font_title = load_font(56, bold=False)
font_subtitle = load_font(26)
font_label = load_font(26)

# ---- Title + subtitle ------------------------------------------------------
draw.text((40, 30), "Nomenclature du Board 5 joueurs", fill="#222",
          font=font_title)
draw.text((40, 110),
          "Vocabulaire partagé pour parler des parties du plateau pentagonal.",
          fill="#777", font=font_subtitle)

# ---- Coordinate helpers ----------------------------------------------------
# Board features are addressed in ORIGINAL image coords. We convert to canvas
# coords by adding (LEFT_MARGIN, TOP_MARGIN).
def b(x, y):
    return (x + LEFT_MARGIN, y + TOP_MARGIN)


# Approximate feature positions in the ORIGINAL JPEG (1332 x 1600).
# Visually estimated from the LudoKing photo:
#   center of decagon  ≈ (665, 660)
#   P1 (bleu)   bottom     ≈ base centroid (530, 1010)
#   P2 (orange) bot-left   ≈ (260, 720)
#   P3 (vert)   top-left   ≈ (235, 210)
#   P4 (rouge)  top-right  ≈ (835, 195)
#   P5 (jaune)  right      ≈ (1075, 510)
features = {
    "P3_base":       (260, 200),    # vert base centroid
    "P3_yard":       (335, 250),    # inside vert yard (3 tokens)
    "P3_bandeau":    (190, 145),    # outer colored ribbon edge of P3
    "ring":          (640, 250),    # vertical ring strip between P3 and P4 (top)
    "P3_start":      (415, 415),    # green start cell with entry arrow
    "P3_corridor":   (455, 460),    # green home corridor (5 colored cells)
    "P3_star":       (475, 305),    # safe star on green ring
    "center_home":   (665, 660),    # central pentagon with dice
    "triangle_home": (700, 580),    # one colored center triangle (yellow side)
    "decagon_edge":  (1100, 380),   # outer decagon edge (top-right)
    "P5_base":       (1100, 575),   # yellow base
    "P1_base":       (470, 1140),   # blue base centroid (bottom)
    "P1_yard":       (530, 1080),   # 3 tokens inside blue yard
    "P2_base":       (175, 800),    # orange base
    "P2_start":      (305, 715),    # orange start cell with arrow
    "tokens":        (470, 1120),   # 3 tokens row (instead of 4 like 4P)
}

# ---- Label rendering -------------------------------------------------------
def label_box(text, x, y, anchor="lm"):
    """Draw a yellow rounded box at (x,y). `anchor` controls alignment of the
    box relative to (x,y): 'lm'=left-middle, 'rm'=right-middle, etc.
    Returns the connection point used to anchor the arrow on the box side."""
    pad_x, pad_y = 14, 10
    # Measure text
    lines = text.split("\n")
    line_h = font_label.size + 4
    widths = [draw.textlength(ln, font=font_label) for ln in lines]
    tw = max(widths)
    th = line_h * len(lines)
    bw = tw + 2 * pad_x
    bh = th + 2 * pad_y
    # Compute top-left from anchor
    if anchor == "lm":
        tl = (x, y - bh / 2)
        arrow_pt = (x, y)            # left middle
    elif anchor == "rm":
        tl = (x - bw, y - bh / 2)
        arrow_pt = (x, y)            # right middle
    else:
        tl = (x - bw / 2, y - bh / 2)
        arrow_pt = (x, y)
    br = (tl[0] + bw, tl[1] + bh)
    # Yellow rounded rectangle
    draw.rounded_rectangle([tl, br], radius=10,
                           fill="#FFE680", outline="#B8860B", width=2)
    # Text
    ty = tl[1] + pad_y
    for ln, w in zip(lines, widths):
        tx = tl[0] + (bw - w) / 2
        draw.text((tx, ty), ln, fill="#222", font=font_label)
        ty += line_h
    return arrow_pt


def arrow(p_from, p_to, color="#FFEB00", width=4):
    """Draw a thin line with an arrowhead at p_to."""
    draw.line([p_from, p_to], fill=color, width=width)
    # Arrowhead
    import math
    dx = p_to[0] - p_from[0]
    dy = p_to[1] - p_from[1]
    L = max(1.0, math.hypot(dx, dy))
    ux, uy = dx / L, dy / L
    head = 16
    spread = 6
    base = (p_to[0] - ux * head, p_to[1] - uy * head)
    left = (base[0] - uy * spread, base[1] + ux * spread)
    right = (base[0] + uy * spread, base[1] - ux * spread)
    draw.polygon([p_to, left, right], fill=color)


def annotate(target_x, target_y, label_text, side, label_y_offset=0):
    """`side` = 'left' or 'right'. Places label box on the chosen side of the
    canvas at the same vertical level as target (+ optional offset)."""
    tx, ty = b(target_x, target_y)
    if side == "left":
        anchor = "lm"
        box_x = 40
        # Label box anchored to its LEFT side at box_x
        # We need to compute the right side of the box for the arrow
        # Use label_box with anchor='lm' meaning left of box at box_x
        end_pt = label_box(label_text, box_x, ty + label_y_offset, anchor="lm")
        # arrow goes from RIGHT side of box to target
        # Recompute: with anchor='lm' the connection point returned is the LEFT
        # side. We want the RIGHT side as arrow start.
        # Simpler: re-measure
        lines = label_text.split("\n")
        line_h = font_label.size + 4
        widths = [draw.textlength(ln, font=font_label) for ln in lines]
        bw = max(widths) + 28
        right_side = (box_x + bw, ty + label_y_offset)
        arrow(right_side, (tx, ty))
    else:
        # right side label
        box_right_x = CW - 40
        end_pt = label_box(label_text, box_right_x, ty + label_y_offset, anchor="rm")
        lines = label_text.split("\n")
        widths = [draw.textlength(ln, font=font_label) for ln in lines]
        bw = max(widths) + 28
        left_side = (box_right_x - bw, ty + label_y_offset)
        arrow(left_side, (tx, ty))


# ---- Left-side labels ------------------------------------------------------
# Vertically distribute labels along the canvas height. Use distinct y offsets.
left_labels = [
    ("Base (triangle)",           features["P3_base"],     0),
    ("Yard (token area)\n3 pions seulement", features["P3_yard"], 80),
    ("Bandeau joueur",            features["P3_bandeau"], -120),
    ("Couloir maison\n(5 cases colorées)", features["P3_corridor"], 100),
    ("Case départ +\nflèche d'entrée", features["P3_start"], -40),
    ("Étoile (safe)",             features["P3_star"],     180),
    ("Base P2 (orange)",          features["P2_base"],     100),
    ("Pions (0, 1, 2)\n3 par couleur",  features["tokens"], 0),
]
# Manually-set absolute y for left labels to space them nicely.
# We override `target` vertical via label_y_offset implicitly above; easier to
# place labels at FIXED canvas y positions and draw arrows to feature points.

def left_label_fixed(label_text, label_y, target_xy):
    box_x = 40
    end_pt = label_box(label_text, box_x, label_y, anchor="lm")
    # Compute box right side
    lines = label_text.split("\n")
    line_h = font_label.size + 4
    widths = [draw.textlength(ln, font=font_label) for ln in lines]
    bw = max(widths) + 28
    box_right_x = box_x + bw
    tx, ty = b(*target_xy)
    arrow((box_right_x, label_y), (tx, ty))

def right_label_fixed(label_text, label_y, target_xy):
    box_right_x = CW - 40
    end_pt = label_box(label_text, box_right_x, label_y, anchor="rm")
    lines = label_text.split("\n")
    widths = [draw.textlength(ln, font=font_label) for ln in lines]
    bw = max(widths) + 28
    box_left_x = box_right_x - bw
    tx, ty = b(*target_xy)
    arrow((box_left_x, label_y), (tx, ty))


# Y axis on canvas: starts at 0 top, going down. Title takes ~180 px.
# Image starts at TOP_MARGIN (180), ends at TOP_MARGIN + BH (1780).
# Distribute labels between y=250 and y=1700.

left_items = [
    (340,  "Base (triangle)",        features["P3_base"]),
    (450,  "Yard (token area)\n3 pions seulement", features["P3_yard"]),
    (570,  "Bandeau joueur",         features["P3_bandeau"]),
    (700,  "Case départ +\nflèche d'entrée", features["P3_start"]),
    (830,  "Couloir maison\n(5 cases colorées)", features["P3_corridor"]),
    (960,  "Étoile (safe)",          features["P3_star"]),
    (1140, "Base P2 (orange)",       features["P2_base"]),
    (1320, "Base P1 (bleu)\n3 pions",  features["P1_yard"]),
    (1500, "Pions 0, 1, 2",           features["tokens"]),
]
right_items = [
    (340,  "Ring\n(continue sur 360°)",       features["ring"]),
    (500,  "Plateau décagonal\n(10 côtés)",   features["decagon_edge"]),
    (650,  "Base P5 (jaune)",                 features["P5_base"]),
    (800,  "Triangle home\n(par couleur)",    features["triangle_home"]),
    (950,  "Home (centre)\n+ dé",             features["center_home"]),
    (1200, "5 secteurs\nde 72°",              (665, 660)),
    (1400, "P1 Bleu en bas\nordre horaire",   features["P1_base"]),
]

# Number labels sequentially: left column first (1..N), then right column.
n = 1
for y, txt, tgt in left_items:
    left_label_fixed(f"{n}. {txt}", y, tgt)
    n += 1
for y, txt, tgt in right_items:
    right_label_fixed(f"{n}. {txt}", y, tgt)
    n += 1

# ---- Footer ----------------------------------------------------------------
footer = ("Différences vs board 4 joueurs : "
          "carré 15×15 → décagone | 4 pions → 3 pions | "
          "ring 52 cases → ring 5p (à confirmer en comptant) | "
          "croix centrale 4 home → pentagon central 5 home")
draw.text((40, CH - 50), footer, fill="#444", font=load_font(22))

canvas.save(OUT)
print("Saved:", OUT, canvas.size)
