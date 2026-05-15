import numpy as np
from PIL import Image, ImageDraw
import os, glob

BASE = r'C:/Users/jmpir/Dev/LudoPoly/Animations/AnimStock/Dices'

COLORS = {
    'blue':   (59, 130, 246),
    'red':    (239, 68, 68),
    'green':  (34, 197, 94),
    'yellow': (234, 179, 8),
    'orange': (249, 115, 22),
    'purple': (168, 85, 247),
}

def make_background_transparent(img_rgba: Image.Image, thresh: int = 30) -> Image.Image:
    """Flood-fill the background color (whatever it is) from all 4 corners → transparent.
    Each corner's flood uses its own seed color, so different bg colors are handled."""
    img = img_rgba.copy()
    w, h = img.size
    for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
        px = img.getpixel(corner)
        if px[3] == 0:
            continue
        ImageDraw.floodfill(img, corner, (0, 0, 0, 0), thresh=thresh)
    return img

# Clear old colored variants (keep white originals)
for old in glob.glob(os.path.join(BASE, 'Dice_[1-6]_*.png')):
    name = os.path.basename(old)
    if '_white' not in name.lower():
        os.remove(old)

count = 0
for value in range(1, 7):
    src_path = os.path.join(BASE, f'Dice_{value}_white.png')
    if not os.path.exists(src_path):
        print('Missing', src_path)
        continue
    src_pil = Image.open(src_path).convert('RGBA')
    # Make white background transparent first
    transparent_pil = make_background_transparent(src_pil)
    src = np.array(transparent_pil)
    rgb_f = src[:, :, :3].astype(np.float32) / 255.0
    alpha = src[:, :, 3]

    # Lighten the tint so multiply doesn't darken shading too much.
    # Mix color with white: adjusted = color*(1-w) + 255*w
    LIGHTEN = 0.25
    for color_name, (cr, cg, cb) in COLORS.items():
        adj = np.array([cr, cg, cb], dtype=np.float32) * (1 - LIGHTEN) + 255.0 * LIGHTEN
        target = adj / 255.0
        rec = (rgb_f * target * 255.0).clip(0, 255).astype(np.uint8)
        out_img = np.dstack([rec, alpha])
        out_path = os.path.join(BASE, f'Dice_{value}_{color_name}.png')
        Image.fromarray(out_img, 'RGBA').save(out_path, 'PNG')
        count += 1

print(f'Generated {count} colored dice variants with transparent backgrounds.')
