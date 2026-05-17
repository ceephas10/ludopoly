"""Generate `board5_clean.png` from the original LudoKing 5-player JPEG by
replacing the blue decorative background with white. Run once; the result is
checked in alongside `index.html`.
"""
import os
import math
from PIL import Image, ImageDraw
import numpy as np

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "Documentation", "Ludo King Board 5 players.jpeg")
OUT = os.path.join(HERE, "board5_clean.png")

img = Image.open(SRC).convert("RGB")
W, H = img.size
print(f"Source: {W} x {H}")

# Decagon geometry estimated from the LudoKing photo:
#   - vertical span of the board: y in [80, 1100], so vertical center ~590
#   - the bottom of the decagon sits a bit above the "Player 1" tab
#   - one vertex points UP at the top
# Combined mask: anything outside a generous CIRCLE around the board → white.
# Center / radius measured from the JPEG: extremes at y=186 top, y=1110 bottom,
# x=109 left, x=1232 right → center ≈ (670, 648), max radius ≈ 565.
arr = np.array(img)
yy, xx = np.indices((H, W))
CENTER = (670, 648)
R_CLIP = 580  # a bit > 565 to keep all bases + a small white halo
dist = np.sqrt((xx - CENTER[0]) ** 2 + (yy - CENTER[1]) ** 2)
outside_circle = dist > R_CLIP
arr[outside_circle] = [255, 255, 255]

# Final cleanup inside the circle: any remaining dark-navy or saturated-blue
# background pattern → white. We restrict this to the "donut" between
# R_CLIP_INNER and R_CLIP where the decorative blue still bleeds through
# (the actual board interior is past R_CLIP_INNER).
R_CLIP_INNER = 460
ring_zone = (dist <= R_CLIP) & (dist > R_CLIP_INNER)
r_ch = arr[:, :, 0].astype(int)
g_ch = arr[:, :, 1].astype(int)
b_ch = arr[:, :, 2].astype(int)
dark_navy = (r_ch < 80) & (g_ch < 130) & (b_ch < 180) & (b_ch > r_ch + 15)
bright_deco = (r_ch < 90) & (b_ch > 200) & (b_ch > g_ch + 30)
arr[ring_zone & (dark_navy | bright_deco)] = [255, 255, 255]

# Hard-clear small decoration zones that survive the filters:
#  - top center "dice" decorations between P3 base and P4 base (above the
#    P3/P4 ribbon outer edges).
arr[0:160, 540:780] = [255, 255, 255]
#  - bottom "Player 1" tab + its outline.
arr[1100:H, :] = [255, 255, 255]

Image.fromarray(arr).save(OUT)
print(f"Saved: {OUT}")
