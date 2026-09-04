"""Generate selector animated WEBPs (transparent background, looping).

- Selector_A_Halo.webp    : rotating dashed yellow ring on the static halo glow.
- Selector_B_Spotlight.webp: brightness pulse on the spotlight beam + floor disc.
- Selector_C_Chevron.webp : static cyan pedestal + downward chevron arrow bobbing.
- Selector_D_Arrow.webp   : rotating dashed yellow ring + golden arrow bobbing above head.

Reads Selector_*.png from ../PNG/ when needed and writes WEBPs next to this file.
WEBP keeps full 8-bit alpha (no palette quantization) and produces smaller files than GIF.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PNG_DIR = os.path.join(HERE, '..', 'PNG')
OUT_DIR = HERE

W, H = 400, 400
N_FRAMES = 43
FRAME_MS = 100  # 4.3s loop


def tight_crop(frames: list[Image.Image], margin: int = 5) -> list[Image.Image]:
    """Crop all frames to the union bbox of opaque pixels (alpha>=8) + margin."""
    bbox = None
    for f in frames:
        alpha_solid = f.split()[3].point(lambda a: 255 if a >= 128 else 0)
        b = alpha_solid.getbbox()
        if b is None:
            continue
        if bbox is None:
            bbox = list(b)
        else:
            bbox[0] = min(bbox[0], b[0])
            bbox[1] = min(bbox[1], b[1])
            bbox[2] = max(bbox[2], b[2])
            bbox[3] = max(bbox[3], b[3])
    if bbox is None:
        return frames
    fw, fh = frames[0].size
    x0 = max(0, bbox[0] - margin)
    y0 = max(0, bbox[1] - margin)
    x1 = min(fw, bbox[2] + margin)
    y1 = min(fh, bbox[3] + margin)
    return [f.crop((x0, y0, x1, y1)) for f in frames]


def save_webp(frames: list[Image.Image], out_path: str) -> None:
    # Pas de tight_crop : on garde le canvas 400×400 carré pour que toutes les anims
    # se positionnent de la même manière dans le <img> carré côté studio (le canvas
    # est le repère partagé). Sinon le centre visuel se décale selon le selector
    # et le ratio non-carré se fait déformer par width/height fixes.
    frames[0].save(
        out_path,
        format='WEBP',
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_MS,
        loop=0,
        lossless=True,
        quality=80,
        method=4,
        minimize_size=False,
        allow_mixed=False,
    )
    print(f'Saved {out_path}')


# ---------------------------------------------------------------------------
# A — Halo: rotating dashed ring overlay.
# ---------------------------------------------------------------------------
CX_H, CY_H = 200, 299
RX_H, RY_H = 65, 17.5
STROKE = 9
DASH, GAP = 14, 18
PERIOD = DASH + GAP
DASHOFFSET_CYCLE = 160
HALO_COLOR = (250, 204, 21, 255)  # #facc15

def _build_ring(cx: float, cy: float, rx: float, ry: float):
    n = 6000
    pts = []
    arc = [0.0]
    for i in range(n + 1):
        t = 2 * math.pi * i / n
        pts.append((cx + rx * math.cos(t), cy + ry * math.sin(t)))
        if i > 0:
            dx = pts[i][0] - pts[i - 1][0]
            dy = pts[i][1] - pts[i - 1][1]
            arc.append(arc[-1] + math.hypot(dx, dy))
    return pts, arc, arc[-1]


def draw_ring(img: Image.Image, offset: float,
              cx: float = CX_H, cy: float = CY_H,
              rx: float = RX_H, ry: float = RY_H) -> None:
    pts, arc, total = _build_ring(cx, cy, rx, ry)
    n = len(pts) - 1

    def point_at(s: float):
        s = s % total
        lo, hi = 0, n
        while lo < hi:
            mid = (lo + hi) // 2
            if arc[mid] < s:
                lo = mid + 1
            else:
                hi = mid
        return pts[lo]

    d = ImageDraw.Draw(img, 'RGBA')
    step = 0.4
    s = 0.0
    prev_pt = None
    prev_active = False
    half = STROKE / 2
    while s < total + step:
        phase = ((s + offset) % PERIOD + PERIOD) % PERIOD
        active = phase < DASH
        pt = point_at(s)
        if active and prev_active and prev_pt is not None:
            d.line([prev_pt, pt], fill=HALO_COLOR, width=STROKE)
        if active and not prev_active:
            d.ellipse((pt[0] - half, pt[1] - half, pt[0] + half, pt[1] + half), fill=HALO_COLOR)
        if (not active) and prev_active and prev_pt is not None:
            d.ellipse((prev_pt[0] - half, prev_pt[1] - half,
                       prev_pt[0] + half, prev_pt[1] + half), fill=HALO_COLOR)
        prev_pt = pt
        prev_active = active
        s += step


def gen_halo() -> None:
    base = Image.open(os.path.join(PNG_DIR, 'Selector_A_Halo.png')).convert('RGBA')
    frames = []
    for f in range(N_FRAMES):
        offset = -DASHOFFSET_CYCLE * (f / N_FRAMES)
        frame = base.copy()
        draw_ring(frame, offset)
        frames.append(frame)
    save_webp(frames, os.path.join(OUT_DIR, 'Selector_A_Halo.webp'))


# ---------------------------------------------------------------------------
# B — Spotlight: brightness pulse on the whole image (alpha modulation).
# ---------------------------------------------------------------------------
def gen_spotlight() -> None:
    base = Image.open(os.path.join(PNG_DIR, 'Selector_B_Spotlight.png')).convert('RGBA')
    base_alpha = base.split()[3]
    frames = []
    for f in range(N_FRAMES):
        t = f / N_FRAMES
        k = 0.775 + 0.225 * math.cos(2 * math.pi * t)
        scaled_alpha = base_alpha.point(lambda a, k=k: int(a * k))
        frame = base.copy()
        frame.putalpha(scaled_alpha)
        frames.append(frame)
    save_webp(frames, os.path.join(OUT_DIR, 'Selector_B_Spotlight.webp'))


# ---------------------------------------------------------------------------
# C — Chevron: redraw pedestal (static) + chevron arrow bobbing vertically.
# ---------------------------------------------------------------------------
PED_CX, PED_CY = W // 2, int(H * 0.84)
ARROW_X, ARROW_Y0 = W // 2, int(H * 0.08)
CHEV_W, CHEV_H = 70, 50
CYAN_FILL = (80, 220, 255, 255)
CYAN_OUTLINE = (20, 180, 230, 255)
WHITE_OUTLINE = (255, 255, 255, 255)


def build_pedestal() -> Image.Image:
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pedestal = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pedestal)
    for rx, ry, a in [(170, 50, 60), (130, 38, 110), (100, 28, 170)]:
        pd.ellipse((PED_CX - rx, PED_CY - ry, PED_CX + rx, PED_CY + ry),
                   fill=(80, 220, 255, a))
    pedestal = pedestal.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(pedestal)
    disc = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    rx, ry = 95, 24
    dd.ellipse((PED_CX - rx, PED_CY - ry, PED_CX + rx, PED_CY + ry),
               fill=(160, 240, 255, 200))
    dd.ellipse((PED_CX - rx, PED_CY - ry, PED_CX + rx, PED_CY + ry),
               outline=CYAN_OUTLINE, width=6)
    img.alpha_composite(disc)
    return img


def draw_arrow(target: Image.Image, ay: int) -> None:
    arrow_layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    halo = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse((ARROW_X - 80, ay - 30, ARROW_X + 80, ay + 70), fill=(80, 220, 255, 80))
    halo = halo.filter(ImageFilter.GaussianBlur(14))
    arrow_layer.alpha_composite(halo)

    ad = ImageDraw.Draw(arrow_layer)
    pts_outer = [
        (ARROW_X - CHEV_W, ay),
        (ARROW_X, ay + CHEV_H),
        (ARROW_X + CHEV_W, ay),
        (ARROW_X + CHEV_W - 18, ay - 6),
        (ARROW_X, ay + CHEV_H - 24),
        (ARROW_X - CHEV_W + 18, ay - 6),
    ]
    ad.polygon(pts_outer, fill=WHITE_OUTLINE, outline=CYAN_OUTLINE)
    pts_inner = [
        (ARROW_X - CHEV_W + 12, ay - 2),
        (ARROW_X, ay + CHEV_H - 18),
        (ARROW_X + CHEV_W - 12, ay - 2),
        (ARROW_X + CHEV_W - 24, ay - 6),
        (ARROW_X, ay + CHEV_H - 30),
        (ARROW_X - CHEV_W + 24, ay - 6),
    ]
    ad.polygon(pts_inner, fill=CYAN_FILL)
    target.alpha_composite(arrow_layer)


def gen_chevron() -> None:
    pedestal = build_pedestal()
    frames = []
    bob_amp = 7
    for f in range(N_FRAMES):
        t = f / N_FRAMES
        dy = int(round(bob_amp * math.sin(2 * math.pi * t)))
        frame = pedestal.copy()
        draw_arrow(frame, ARROW_Y0 + dy)
        frames.append(frame)
    save_webp(frames, os.path.join(OUT_DIR, 'Selector_C_Chevron.webp'))


# ---------------------------------------------------------------------------
# D — Arrow: rotating dashed ring (feet) + golden arrow above head bobbing.
# ---------------------------------------------------------------------------
ARROW_D_X = 200
# Descendue de 1.2/10 de case (1 case ≈ 130 px en canvas) → +15.6 px
ARROW_D_Y0 = 95 + 16
ARROW_D_W = 44
ARROW_D_H = 36
ARROW_D_BOB = 7
ARROW_D_BOB_CYCLES = 10
ARROW_D_RING_SPEED = 2.5
GOLD_FILL = (255, 200, 40, 255)
GOLD_LIGHT = (255, 235, 130, 255)
GOLD_DARK = (190, 130, 10, 255)


def draw_gold_arrow(target: Image.Image, ay: int) -> None:
    """Clean downward gold arrow. 4× oversample + LANCZOS downsample for smooth AA edges.
    Pas de halo lumineux — flèche nette seule.
    """
    S = 4
    big = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(big)

    cx = ARROW_D_X * S
    top = ay * S

    shaft_w = 14 * S
    head_w = 44 * S
    shaft_h = 14 * S
    head_h = 24 * S
    outline_t = 3 * S

    shaft_bot = top + shaft_h
    tip = shaft_bot + head_h

    arrow_pts = [
        (cx - shaft_w // 2, top),
        (cx + shaft_w // 2, top),
        (cx + shaft_w // 2, shaft_bot),
        (cx + head_w // 2, shaft_bot),
        (cx,                 tip),
        (cx - head_w // 2, shaft_bot),
        (cx - shaft_w // 2, shaft_bot),
    ]

    pts_outline = [
        (cx - shaft_w // 2 - outline_t, top - outline_t),
        (cx + shaft_w // 2 + outline_t, top - outline_t),
        (cx + shaft_w // 2 + outline_t, shaft_bot),
        (cx + head_w // 2 + outline_t * 2, shaft_bot),
        (cx, tip + outline_t),
        (cx - head_w // 2 - outline_t * 2, shaft_bot),
        (cx - shaft_w // 2 - outline_t, shaft_bot),
    ]
    bd.polygon(pts_outline, fill=GOLD_DARK)
    bd.polygon(arrow_pts, fill=GOLD_FILL)
    bd.polygon([
        (cx - shaft_w // 2 + 2 * S, top + 2 * S),
        (cx - 1 * S,                top + 2 * S),
        (cx - 1 * S,                shaft_bot - 2 * S),
        (cx - shaft_w // 2 + 2 * S, shaft_bot - 2 * S),
    ], fill=GOLD_LIGHT)

    small = big.resize((W, H), Image.LANCZOS)
    target.alpha_composite(small)


# Cercle (ring) du Selector D : 80% de la largeur de la case, remonté de 2/10 de case par rapport
# au cercle générique. Hypothèse : le cercle générique (RX_H=65 → 130 px wide) couvre 1 case.
ARROW_D_RING_RX = RX_H * 0.8           # 52
ARROW_D_RING_RY = RY_H * 0.8           # 14
# Ring descendu de 3/10 de case (cell ≈ 130 px) par rapport à la position « -2/10 cell »
# précédente → solde net = +1/10 cell vs CY_H. 299 + 13 = 312.
ARROW_D_RING_CY = CY_H + 13


def gen_arrow() -> None:
    frames = []
    ring_mult = max(1, int(round(ARROW_D_RING_SPEED)))
    for f in range(N_FRAMES):
        offset = -DASHOFFSET_CYCLE * ring_mult * (f / N_FRAMES)
        t = f / N_FRAMES
        dy = int(round(ARROW_D_BOB * math.sin(2 * math.pi * ARROW_D_BOB_CYCLES * t)))
        frame = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        draw_ring(frame, offset, cx=CX_H, cy=ARROW_D_RING_CY,
                  rx=ARROW_D_RING_RX, ry=ARROW_D_RING_RY)
        draw_gold_arrow(frame, ARROW_D_Y0 + dy)
        frames.append(frame)
    save_webp(frames, os.path.join(OUT_DIR, 'Selector_D_Arrow.webp'))


def main() -> None:
    print(f'Rendering {N_FRAMES} frames each (4.3s loops)...')
    gen_halo()
    gen_spotlight()
    gen_chevron()
    gen_arrow()
    print('Done.')


if __name__ == '__main__':
    main()
