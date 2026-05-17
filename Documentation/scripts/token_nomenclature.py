"""Generate a labelled diagram of the standard pawn (token) for shared
vocabulary between the user and Claude.

Loads the production blue idle GIF, scales it up, places it on a wider
canvas and draws labelled arrows pointing to each named part. Output:
``Documentation/Token_Nomenclature.png``.
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN_GIF = ROOT / "Animations" / "AnimStock" / "Tokens" / "GIF" / \
            "Token_standard_blue_idle_1.gif"
OUTPUT = ROOT / "Documentation" / "Token_Nomenclature.png"

# Output canvas size (BIG).
CANVAS_W, CANVAS_H = 2400, 1600
# Where to draw the (scaled) token inside the canvas.
TOKEN_W, TOKEN_H = 800, 1760  # token native is 200×440 → 4× scale
TOKEN_X = (CANVAS_W - TOKEN_W) // 2
TOKEN_Y = (CANVAS_H - TOKEN_H) // 2

# Measured visible bbox in the 200×440 native: x 71..129, y 214..299.
# Scaled ×4 → x 284..516, y 856..1196 inside the 800×1760 token rectangle.
# Targets below are (x, y) in token-relative coords (0..TOKEN_W × 0..TOKEN_H).
LABELS = [
    ("Sommet (casque)",      (400,  855), (TOKEN_X - 120,  TOKEN_Y + 830),  'L'),
    ("Visage",               (400,  920), (TOKEN_X + TOKEN_W + 120, TOKEN_Y + 860), 'R'),
    ("Œil",                  (370,  960), (TOKEN_X - 120,  TOKEN_Y + 930),  'L'),
    ("Bouche",               (420, 1000), (TOKEN_X + TOKEN_W + 120, TOKEN_Y + 1000), 'R'),
    ("Anneau visage",        (316,  980), (TOKEN_X - 120,  TOKEN_Y + 1060), 'L'),
    ("Corps",                (420, 1090), (TOKEN_X + TOKEN_W + 120, TOKEN_Y + 1130), 'R'),
    ("Pointe",               (400, 1190), (TOKEN_X + TOKEN_W + 120, TOKEN_Y + 1260), 'R'),
    ("Halo (contour vert)",  (296, 1110), (TOKEN_X - 120,  TOKEN_Y + 1200), 'L'),
]


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (250, 250, 252, 255))
    token = Image.open(TOKEN_GIF).convert("RGBA")
    token = token.resize((TOKEN_W, TOKEN_H), Image.LANCZOS)
    canvas.paste(token, (TOKEN_X, TOKEN_Y), token)

    draw = ImageDraw.Draw(canvas)

    # Title.
    try:
        title_font = ImageFont.truetype("arial.ttf", 64)
        label_font = ImageFont.truetype("arial.ttf", 40)
    except OSError:
        title_font = ImageFont.load_default()
        label_font = ImageFont.load_default()
    draw.text(
        (60, 40),
        "Nomenclature du Token",
        fill=(20, 20, 30, 255),
        font=title_font,
    )
    draw.text(
        (60, 120),
        "Vocabulaire partagé pour parler des parties d'un pion.",
        fill=(80, 80, 90, 255),
        font=label_font,
    )

    for name, target, anchor, side in LABELS:
        tx = TOKEN_X + target[0]
        ty = TOKEN_Y + target[1]
        lx, ly = anchor
        # Arrow line.
        draw.line([(lx, ly), (tx, ty)], fill=(50, 50, 60, 255), width=4)
        # Arrowhead near the target.
        head_size = 20
        dx, dy = tx - lx, ty - ly
        length = (dx ** 2 + dy ** 2) ** 0.5 or 1
        ux, uy = dx / length, dy / length
        px, py = -uy, ux  # perpendicular
        p1 = (tx - ux * head_size + px * head_size * 0.5,
              ty - uy * head_size + py * head_size * 0.5)
        p2 = (tx - ux * head_size - px * head_size * 0.5,
              ty - uy * head_size - py * head_size * 0.5)
        draw.polygon([(tx, ty), p1, p2], fill=(50, 50, 60, 255))
        # Label badge.
        text_bbox = draw.textbbox((0, 0), name, font=label_font)
        text_w = text_bbox[2] - text_bbox[0]
        text_h = text_bbox[3] - text_bbox[1]
        pad = 14
        if side == 'L':
            bx0 = lx - text_w - pad * 2
        else:
            bx0 = lx
        by0 = ly - text_h // 2 - pad
        bx1 = bx0 + text_w + pad * 2
        by1 = by0 + text_h + pad * 2
        draw.rounded_rectangle(
            (bx0, by0, bx1, by1),
            radius=18,
            fill=(255, 235, 130, 255),
            outline=(180, 150, 30, 255),
            width=3,
        )
        draw.text(
            (bx0 + pad, by0 + pad - 4),
            name,
            fill=(40, 30, 0, 255),
            font=label_font,
        )

    canvas.save(OUTPUT, "PNG")
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
