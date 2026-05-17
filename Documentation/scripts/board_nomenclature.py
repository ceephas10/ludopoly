"""Generate a labelled diagram of the 4-player Ludo board for shared
vocabulary. Renders a simplified 15×15 board via PIL and overlays arrows
pointing to each named part.
Output: ``Documentation/Board4_Nomenclature.png``.
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Documentation" / "Board4_Nomenclature.png"

# Canvas + board geometry.
CANVAS_W, CANVAS_H = 2400, 1600
BOARD_SIZE = 1200            # 15 cells × 80 px = 1200
CELL = BOARD_SIZE // 15      # 80 px per cell
BOARD_X = (CANVAS_W - BOARD_SIZE) // 2
BOARD_Y = (CANVAS_H - BOARD_SIZE) // 2 + 80  # offset down to leave room for title

# Colors.
BG      = (250, 250, 252, 255)
RED     = (233, 75, 75, 255)
GREEN   = (79, 174, 93, 255)
BLUE    = (61, 164, 236, 255)
YELLOW  = (255, 206, 46, 255)
WHITE   = (255, 255, 255, 255)
GRID    = (170, 170, 170, 255)
DARK    = (26, 37, 65, 255)


def cell_rect(c, r):
    """Pixel rect of grid cell (c, r) on the board."""
    return (
        BOARD_X + c * CELL,
        BOARD_Y + r * CELL,
        BOARD_X + (c + 1) * CELL,
        BOARD_Y + (r + 1) * CELL,
    )


def fill_rect(draw, c0, r0, c1, r1, color):
    """Fill grid rectangle from cell (c0,r0) to (c1-1, r1-1)."""
    draw.rectangle(
        (
            BOARD_X + c0 * CELL,
            BOARD_Y + r0 * CELL,
            BOARD_X + c1 * CELL,
            BOARD_Y + r1 * CELL,
        ),
        fill=color,
    )


def draw_grid_lines(draw):
    """Thin grid lines on every cell of the white cross."""
    # Vertical band (cols 6..9), full height
    for c in range(6, 10):
        x = BOARD_X + c * CELL
        draw.line([(x, BOARD_Y), (x, BOARD_Y + BOARD_SIZE)], fill=GRID, width=2)
    # Horizontal band (rows 6..9), full width
    for r in range(6, 10):
        y = BOARD_Y + r * CELL
        draw.line([(BOARD_X, y), (BOARD_X + BOARD_SIZE, y)], fill=GRID, width=2)
    # The two arms' grid lines
    for c in range(0, 16):
        x = BOARD_X + c * CELL
        for r0, r1 in [(6, 9)]:
            draw.line([(x, BOARD_Y + r0 * CELL), (x, BOARD_Y + r1 * CELL)],
                       fill=GRID, width=2)
    for r in range(0, 16):
        y = BOARD_Y + r * CELL
        for c0, c1 in [(6, 9)]:
            draw.line([(BOARD_X + c0 * CELL, y), (BOARD_X + c1 * CELL, y)],
                       fill=GRID, width=2)


def draw_star(draw, c, r, color=(0, 0, 0, 255)):
    """5-pointed star centered on cell (c, r)."""
    import math
    cx = BOARD_X + (c + 0.5) * CELL
    cy = BOARD_Y + (r + 0.5) * CELL
    outer = CELL * 0.32
    inner = CELL * 0.14
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = outer if i % 2 == 0 else inner
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    draw.polygon(pts, fill=WHITE, outline=(40, 40, 40, 255))


def draw_arrow_marker(draw, c, r, direction, color):
    """White arrow inside a start-square cell."""
    pad = CELL * 0.20
    x0 = BOARD_X + c * CELL + pad
    y0 = BOARD_Y + r * CELL + pad
    x1 = BOARD_X + (c + 1) * CELL - pad
    y1 = BOARD_Y + (r + 1) * CELL - pad
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    s = (x1 - x0) / 2
    if direction == "right":
        head = [(x1, cy), (x1 - s, cy - s * 0.6), (x1 - s, cy + s * 0.6)]
        stem = (x0, cy - s * 0.22, x1 - s, cy + s * 0.22)
    elif direction == "left":
        head = [(x0, cy), (x0 + s, cy - s * 0.6), (x0 + s, cy + s * 0.6)]
        stem = (x0 + s, cy - s * 0.22, x1, cy + s * 0.22)
    elif direction == "down":
        head = [(cx, y1), (cx - s * 0.6, y1 - s), (cx + s * 0.6, y1 - s)]
        stem = (cx - s * 0.22, y0, cx + s * 0.22, y1 - s)
    else:  # up
        head = [(cx, y0), (cx - s * 0.6, y0 + s), (cx + s * 0.6, y0 + s)]
        stem = (cx - s * 0.22, y0 + s, cx + s * 0.22, y1)
    draw.rectangle(stem, fill=WHITE)
    draw.polygon(head, fill=WHITE)


def draw_board(draw):
    """Vector copy of the in-app 4-player BoardPainter (simplified)."""
    # Dark backdrop outside the cross.
    draw.rectangle(
        (BOARD_X, BOARD_Y, BOARD_X + BOARD_SIZE, BOARD_Y + BOARD_SIZE),
        fill=DARK,
    )
    # White cross.
    fill_rect(draw, 6, 0, 9, 15, WHITE)
    fill_rect(draw, 0, 6, 15, 9, WHITE)
    # 4 colored bases (6×6 corner with inner 5×5 white).
    bases = [
        (0, 0, RED),
        (9, 0, GREEN),
        (0, 9, BLUE),
        (9, 9, YELLOW),
    ]
    for c0, r0, color in bases:
        fill_rect(draw, c0, r0, c0 + 6, r0 + 6, color)
        # inner 5×5 white
        draw.rectangle(
            (
                BOARD_X + (c0 + 0.5) * CELL,
                BOARD_Y + (r0 + 0.5) * CELL,
                BOARD_X + (c0 + 5.5) * CELL,
                BOARD_Y + (r0 + 5.5) * CELL,
            ),
            fill=WHITE,
        )
    # Home stretches (5 colored cells per color).
    fill_rect(draw, 1, 7, 6, 8, RED)     # red row
    fill_rect(draw, 7, 1, 8, 6, GREEN)   # green column
    fill_rect(draw, 9, 7, 14, 8, YELLOW) # yellow row
    fill_rect(draw, 7, 9, 8, 14, BLUE)   # blue column
    # Start squares.
    starts = [(1, 6, RED), (8, 1, GREEN), (13, 8, YELLOW), (6, 13, BLUE)]
    for c, r, color in starts:
        fill_rect(draw, c, r, c + 1, r + 1, color)
    # Center triangles meeting at (7.5, 7.5).
    cx = BOARD_X + 7.5 * CELL
    cy = BOARD_Y + 7.5 * CELL
    lt = (BOARD_X + 6 * CELL, BOARD_Y + 6 * CELL)
    rt = (BOARD_X + 9 * CELL, BOARD_Y + 6 * CELL)
    rb = (BOARD_X + 9 * CELL, BOARD_Y + 9 * CELL)
    lb = (BOARD_X + 6 * CELL, BOARD_Y + 9 * CELL)
    draw.polygon([lt, lb, (cx, cy)], fill=RED)
    draw.polygon([lt, rt, (cx, cy)], fill=GREEN)
    draw.polygon([rt, rb, (cx, cy)], fill=YELLOW)
    draw.polygon([lb, rb, (cx, cy)], fill=BLUE)
    # Grid lines on the cross.
    draw_grid_lines(draw)
    # Stars (safe cells).
    for c, r in [(2, 8), (6, 2), (12, 6), (8, 12)]:
        draw_star(draw, c, r)
    # Start arrows.
    for c, r, color, d in [
        (1, 6, RED, "right"),
        (8, 1, GREEN, "down"),
        (13, 8, YELLOW, "left"),
        (6, 13, BLUE, "up"),
    ]:
        draw_arrow_marker(draw, c, r, d, color)


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), BG)
    draw = ImageDraw.Draw(canvas)

    try:
        title_font = ImageFont.truetype("arial.ttf", 64)
        label_font = ImageFont.truetype("arial.ttf", 36)
    except OSError:
        title_font = ImageFont.load_default()
        label_font = ImageFont.load_default()

    # Title.
    draw.text(
        (60, 40),
        "Nomenclature du Board 4 joueurs",
        fill=(20, 20, 30, 255),
        font=title_font,
    )
    draw.text(
        (60, 120),
        "Vocabulaire partagé pour parler des parties du plateau.",
        fill=(80, 80, 90, 255),
        font=label_font,
    )

    draw_board(draw)

    # Labels: name, (cellX, cellY) target on the grid, (lx, ly) anchor canvas,
    # side ('L' or 'R').
    LABELS = [
        # name, target (cell coords float), anchor, side
        ("Base",              (2, 2),      (BOARD_X - 250, BOARD_Y + 2 * CELL), 'L'),
        ("Yard (token area)", (3, 11),     (BOARD_X - 250, BOARD_Y + 11.5 * CELL), 'L'),
        ("Case départ",       (1.5, 6.5),  (BOARD_X - 250, BOARD_Y + 6.5 * CELL), 'L'),
        ("Couloir maison",    (7.5, 11),   (BOARD_X + BOARD_SIZE + 80, BOARD_Y + 13 * CELL), 'R'),
        ("Home (centre)",     (7.5, 7.5),  (BOARD_X + BOARD_SIZE + 80, BOARD_Y + 7.5 * CELL), 'R'),
        ("Triangle home",     (7.0, 8.0),  (BOARD_X + BOARD_SIZE + 80, BOARD_Y + 9 * CELL), 'R'),
        ("Ring (52 cases)",   (10.5, 8.5), (BOARD_X + BOARD_SIZE + 80, BOARD_Y + 10.5 * CELL), 'R'),
        ("Étoile (safe)",     (2.5, 8.5),  (BOARD_X - 250, BOARD_Y + 8.5 * CELL), 'L'),
        ("Flèche d'entrée",   (6.5, 13.5), (BOARD_X - 250, BOARD_Y + 13.5 * CELL), 'L'),
        ("Croix blanche",     (7.5, 4),    (BOARD_X + BOARD_SIZE + 80, BOARD_Y + 4 * CELL), 'R'),
        ("Bandeau joueur",    (2.5, 14.5), (BOARD_X - 250, BOARD_Y + 14.5 * CELL), 'L'),
    ]

    for name, target, anchor, side in LABELS:
        tx = BOARD_X + target[0] * CELL
        ty = BOARD_Y + target[1] * CELL
        lx, ly = anchor
        # Arrow line.
        draw.line([(lx, ly), (tx, ty)], fill=(50, 50, 60, 255), width=4)
        # Arrowhead.
        head_size = 22
        dx, dy = tx - lx, ty - ly
        length = (dx ** 2 + dy ** 2) ** 0.5 or 1
        ux, uy = dx / length, dy / length
        px, py = -uy, ux
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
