"""Generate selector animated GIFs (transparent background, looping).

- Selector_A_Halo.gif    : rotating dashed yellow ring on the static halo glow.
- Selector_B_Spotlight.gif: brightness pulse on the spotlight beam + floor disc.
- Selector_C_Chevron.gif : static cyan pedestal + downward chevron arrow bobbing.

Reads Selector_*.png from ../PNG/ when needed and writes GIFs next to this file.
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


# ---------------------------------------------------------------------------
# Palette + transparency helper (sentinel index 255 = transparent).
# ---------------------------------------------------------------------------
def to_palette_with_transparency(im: Image.Image) -> Image.Image:
    alpha = im.split()[3]
    rgb = im.convert('RGB')
    pal = rgb.quantize(colors=255, dither=Image.Dither.FLOYDSTEINBERG)
    mask = alpha.point(lambda a: 255 if a < 128 else 0)
    pal.paste(255, mask=mask)
    return pal


def save_gif(frames: list[Image.Image], out_path: str) -> None:
    pframes = [to_palette_with_transparency(f) for f in frames]
    pframes[0].save(
        out_path,
        save_all=True,
        append_images=pframes[1:],
        duration=FRAME_MS,
        loop=0,
        disposal=2,
        transparency=255,
        optimize=False,
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

_N = 6000
_pts = []
_arc = [0.0]
for _i in range(_N + 1):
    _t = 2 * math.pi * _i / _N
    _pts.append((CX_H + RX_H * math.cos(_t), CY_H + RY_H * math.sin(_t)))
    if _i > 0:
        _dx = _pts[_i][0] - _pts[_i - 1][0]
        _dy = _pts[_i][1] - _pts[_i - 1][1]
        _arc.append(_arc[-1] + math.hypot(_dx, _dy))
_TOTAL = _arc[-1]


def _point_at(s: float):
    s = s % _TOTAL
    lo, hi = 0, _N
    while lo < hi:
        mid = (lo + hi) // 2
        if _arc[mid] < s:
            lo = mid + 1
        else:
            hi = mid
    return _pts[lo]


def draw_ring(img: Image.Image, offset: float) -> None:
    d = ImageDraw.Draw(img, 'RGBA')
    step = 0.4
    s = 0.0
    prev_pt = None
    prev_active = False
    half = STROKE / 2
    while s < _TOTAL + step:
        phase = ((s + offset) % PERIOD + PERIOD) % PERIOD
        active = phase < DASH
        pt = _point_at(s)
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
    save_gif(frames, os.path.join(OUT_DIR, 'Selector_A_Halo.gif'))


# ---------------------------------------------------------------------------
# B — Spotlight: brightness pulse on the whole image (alpha modulation).
# ---------------------------------------------------------------------------
def gen_spotlight() -> None:
    base = Image.open(os.path.join(PNG_DIR, 'Selector_B_Spotlight.png')).convert('RGBA')
    base_alpha = base.split()[3]
    frames = []
    for f in range(N_FRAMES):
        # Smooth sine pulse: 0.55 .. 1.0 .. 0.55
        t = f / N_FRAMES
        k = 0.775 + 0.225 * math.cos(2 * math.pi * t)  # ranges ~0.55..1.0
        scaled_alpha = base_alpha.point(lambda a, k=k: int(a * k))
        frame = base.copy()
        frame.putalpha(scaled_alpha)
        frames.append(frame)
    save_gif(frames, os.path.join(OUT_DIR, 'Selector_B_Spotlight.gif'))


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
    bob_amp = 7  # pixels
    for f in range(N_FRAMES):
        t = f / N_FRAMES
        # Smooth bob: down on first half, up on second
        dy = int(round(bob_amp * math.sin(2 * math.pi * t)))
        frame = pedestal.copy()
        draw_arrow(frame, ARROW_Y0 + dy)
        frames.append(frame)
    save_gif(frames, os.path.join(OUT_DIR, 'Selector_C_Chevron.gif'))


def main() -> None:
    print(f'Rendering {N_FRAMES} frames each (4.3s loops)...')
    gen_halo()
    gen_spotlight()
    gen_chevron()
    print('Done.')


if __name__ == '__main__':
    main()
