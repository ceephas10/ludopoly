"""Generate 3 selector overlay PNGs for the active/selectable token."""
import os
from PIL import Image, ImageDraw, ImageFilter
import math

OUT = r'C:/Users/jmpir/Dev/LudoPoly/Animations/AnimStock/Selectors'
os.makedirs(OUT, exist_ok=True)

W, H = 400, 400


def save(img: Image.Image, name: str) -> None:
    img.save(os.path.join(OUT, name), 'PNG')
    print(f'  saved {name}')


def concept_a_halo() -> Image.Image:
    """A — Gold radial halo (the dashed ring is rendered separately in SVG so it can rotate)."""
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = W // 2, int(H * 0.45)
    for r, alpha in [(180, 30), (140, 55), (100, 90), (70, 130), (45, 160)]:
        gd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 210, 80, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(glow)

    core = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    cd.ellipse((cx - 35, cy - 35, cx + 35, cy + 35), fill=(255, 245, 200, 110))
    core = core.filter(ImageFilter.GaussianBlur(8))
    img.alpha_composite(core)
    return img


def concept_b_spotlight() -> Image.Image:
    """B — Vertical white-yellow light beam from above + bright floor disc."""
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Cone beam: a triangle filled with vertical gradient
    apex = (W // 2, 0)
    base_left = (int(W * 0.18), int(H * 0.92))
    base_right = (int(W * 0.82), int(H * 0.92))

    # Build cone by drawing thin horizontal strips with varying alpha
    cone = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cone)
    for y in range(0, int(H * 0.92), 2):
        t = y / (H * 0.92)
        # Half width at y
        hw = int(W * 0.04 + (W * 0.32 - W * 0.04) * t)
        alpha = int(20 + 110 * t)  # stronger near base
        cd.rectangle((W // 2 - hw, y, W // 2 + hw, y + 2),
                     fill=(255, 250, 210, alpha))
    cone = cone.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(cone)

    # Bright floor disc (where beam hits)
    floor = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(floor)
    ground_cx, ground_cy = W // 2, int(H * 0.84)
    for rx, ry, a in [(160, 42, 80), (120, 32, 140), (80, 22, 200), (45, 13, 240)]:
        fd.ellipse((ground_cx - rx, ground_cy - ry, ground_cx + rx, ground_cy + ry),
                   fill=(255, 250, 230, a))
    floor = floor.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(floor)

    # Crisp inner core on the floor (very bright)
    core = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    cd2 = ImageDraw.Draw(core)
    cd2.ellipse((ground_cx - 30, ground_cy - 8, ground_cx + 30, ground_cy + 8),
                fill=(255, 255, 255, 220))
    core = core.filter(ImageFilter.GaussianBlur(3))
    img.alpha_composite(core)
    return img


def concept_c_chevron_pedestal() -> Image.Image:
    """C — Cyan glowing pedestal under the token + downward chevron arrow above."""
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))

    # Glowing pedestal disc
    pedestal = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pedestal)
    ground_cx, ground_cy = W // 2, int(H * 0.84)

    # Outer glow
    for rx, ry, a in [(170, 50, 60), (130, 38, 110), (100, 28, 170)]:
        pd.ellipse((ground_cx - rx, ground_cy - ry, ground_cx + rx, ground_cy + ry),
                   fill=(80, 220, 255, a))
    pedestal = pedestal.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(pedestal)

    # Bright cyan disc + ring
    disc = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    rx, ry = 95, 24
    # Filled disc
    dd.ellipse((ground_cx - rx, ground_cy - ry, ground_cx + rx, ground_cy + ry),
               fill=(160, 240, 255, 200))
    # Thick ring on top
    dd.ellipse((ground_cx - rx, ground_cy - ry, ground_cx + rx, ground_cy + ry),
               outline=(20, 180, 230, 255), width=6)
    img.alpha_composite(disc)

    # Downward chevron arrow above the head
    arrow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)
    ax, ay = W // 2, int(H * 0.08)
    chev_w, chev_h = 70, 50
    # Outer arrow body (white outline)
    pts_outer = [
        (ax - chev_w, ay),
        (ax, ay + chev_h),
        (ax + chev_w, ay),
        (ax + chev_w - 18, ay - 6),
        (ax, ay + chev_h - 24),
        (ax - chev_w + 18, ay - 6),
    ]
    ad.polygon(pts_outer, fill=(255, 255, 255, 255), outline=(20, 180, 230, 255))
    # Inner cyan fill
    pts_inner = [
        (ax - chev_w + 12, ay - 2),
        (ax, ay + chev_h - 18),
        (ax + chev_w - 12, ay - 2),
        (ax + chev_w - 24, ay - 6),
        (ax, ay + chev_h - 30),
        (ax - chev_w + 24, ay - 6),
    ]
    ad.polygon(pts_inner, fill=(80, 220, 255, 255))
    img.alpha_composite(arrow)

    # Subtle glow around arrow
    halo = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse((ax - 80, ay - 30, ax + 80, ay + 70), fill=(80, 220, 255, 80))
    halo = halo.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(halo)
    img.alpha_composite(arrow)  # re-draw arrow above its halo

    return img


print('Generating 3 selector overlays...')
save(concept_a_halo(), 'Selector_A_Halo.png')
save(concept_b_spotlight(), 'Selector_B_Spotlight.png')
save(concept_c_chevron_pedestal(), 'Selector_C_Chevron.png')
print('Done.')
