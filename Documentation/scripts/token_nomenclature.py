"""Generate a labelled diagram of the standard token (pion) for shared
vocabulary between human and AI.

Loads the production blue idle WebP (frame 0), scales it up on a wide
canvas, then draws labelled arrows pointing to each named part.

Output: ``Documentation/Token_Nomenclature.png``.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
TOKEN_SRC = ROOT / "AnimStock" / "Tokens" / "WEBP" / \
    "Token_standard_blue_idle_#1.webp"
OUTPUT = ROOT / "Documentation" / "Token_Nomenclature.png"

# Output canvas (large enough to fit big labels on both sides).
CANVAS_W, CANVAS_H = 2400, 1600

# Source token is 64×93 px. Scale uniformly so it stays in shape.
SCALE = 12  # → rendered token 768×1116 px

# Eye / face / body coords measured on the 64×93 native WebP (frame 0):
#   left eye  : (22.5, 27)
#   right eye : (40.5, 27)
#   centre between eyes  → (31.5, 27)  ← the NEW canonical center
#   sommet (top of helmet halo): around (32, 8)
#   visage centre  : (32, 26)
#   smile / bouche : (32, 36)
#   anneau visage  : (15, 30)  (left edge of the face ring)
#   corps          : (32, 60)
#   pointe (tip)   : (32, 88)
#   halo (contour vert), outer edge: (54, 50)
LABELS = [
    # (text, native_target_xy, on_left, badge_y_in_canvas)
    ("Sommet (casque)",                 (32,  8),  True,  340),
    ("Visage",                          (32, 23), False,  330),
    ("Œil",                             (22, 27),  True,  440),
    ("Centre du pion (entre les yeux)", (31, 27), False,  450),
    ("Bouche",                          (32, 36), False,  570),
    ("Anneau visage",                   (15, 30),  True,  570),
    ("Corps",                           (32, 60), False,  720),
    ("Halo (contour vert)",             (54, 50),  True,  720),
    ("Pointe",                          (32, 90), False,  880),
]


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (250, 250, 252, 255))
    token = Image.open(TOKEN_SRC).convert("RGBA")
    native_w, native_h = token.size
    token_w = native_w * SCALE
    token_h = native_h * SCALE
    token = token.resize((token_w, token_h), Image.LANCZOS)

    token_x = (CANVAS_W - token_w) // 2
    token_y = (CANVAS_H - token_h) // 2 + 80  # leave room for the title
    canvas.paste(token, (token_x, token_y), token)

    draw = ImageDraw.Draw(canvas)

    try:
        title_font = ImageFont.truetype("arial.ttf", 64)
        sub_font   = ImageFont.truetype("arial.ttf", 30)
        label_font = ImageFont.truetype("arial.ttf", 36)
    except OSError:
        title_font = sub_font = label_font = ImageFont.load_default()

    draw.text((60, 40), "Nomenclature du Token",
              fill=(20, 20, 30, 255), font=title_font)
    draw.text((60, 120),
              "Vocabulaire partagé pour parler des parties d'un pion. "
              "Le centre du pion = le point entre les 2 yeux (idle).",
              fill=(80, 80, 90, 255), font=sub_font)

    # Draw a small red crosshair on the canonical center (between the eyes).
    cx_native_x, cx_native_y = 31, 27
    cx_canvas_x = token_x + cx_native_x * SCALE
    cx_canvas_y = token_y + cx_native_y * SCALE
    cross = 18
    draw.line([(cx_canvas_x - cross, cx_canvas_y),
               (cx_canvas_x + cross, cx_canvas_y)],
              fill=(220, 30, 30, 255), width=3)
    draw.line([(cx_canvas_x, cx_canvas_y - cross),
               (cx_canvas_x, cx_canvas_y + cross)],
              fill=(220, 30, 30, 255), width=3)

    margin = 80
    for name, (nx, ny), on_left, by in LABELS:
        tx = token_x + nx * SCALE
        ty = token_y + ny * SCALE
        if on_left:
            badge_x_anchor = margin               # left padding
        else:
            badge_x_anchor = CANVAS_W - margin    # right padding

        # Draw label badge first to know its width.
        text_bbox = draw.textbbox((0, 0), name, font=label_font)
        text_w = text_bbox[2] - text_bbox[0]
        text_h = text_bbox[3] - text_bbox[1]
        pad = 14
        if on_left:
            bx0 = badge_x_anchor
        else:
            bx0 = badge_x_anchor - text_w - pad * 2
        by0 = by - text_h // 2 - pad
        bx1 = bx0 + text_w + pad * 2
        by1 = by0 + text_h + pad * 2
        draw.rounded_rectangle((bx0, by0, bx1, by1), radius=18,
                               fill=(255, 235, 130, 255),
                               outline=(180, 150, 30, 255), width=3)
        draw.text((bx0 + pad, by0 + pad - 6), name,
                  fill=(40, 30, 0, 255), font=label_font)

        # Arrow from badge edge to target.
        if on_left:
            lx, ly = bx1, by
        else:
            lx, ly = bx0, by
        draw.line([(lx, ly), (tx, ty)], fill=(50, 50, 60, 255), width=4)
        # Arrowhead.
        head_size = 24
        dx, dy = tx - lx, ty - ly
        length = (dx ** 2 + dy ** 2) ** 0.5 or 1
        ux, uy = dx / length, dy / length
        px, py = -uy, ux
        p1 = (tx - ux * head_size + px * head_size * 0.5,
              ty - uy * head_size + py * head_size * 0.5)
        p2 = (tx - ux * head_size - px * head_size * 0.5,
              ty - uy * head_size - py * head_size * 0.5)
        draw.polygon([(tx, ty), p1, p2], fill=(50, 50, 60, 255))

    canvas.save(OUTPUT, "PNG")
    print(f"Wrote {OUTPUT}  ({CANVAS_W}×{CANVAS_H})")


if __name__ == "__main__":
    main()
