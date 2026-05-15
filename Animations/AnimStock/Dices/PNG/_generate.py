import numpy as np
from PIL import Image
import cv2, os, glob

BASE = r'C:/Users/jmpir/Dev/LudoPoly/Animations/AnimStock/Dices'
SRC = os.path.join(BASE, 'Dice_White_3D.png')

# === FACE QUADS (image coords, order TL TR BR BL face-local CW) ===
def solve_face_corners(pip_TL, pip_TR, pip_BR, pip_BL):
    A = np.array([
        [0.5625, 0.1875, 0.0625, 0.1875],
        [0.1875, 0.5625, 0.1875, 0.0625],
        [0.0625, 0.1875, 0.5625, 0.1875],
        [0.1875, 0.0625, 0.1875, 0.5625],
    ])
    bx = [pip_TL[0], pip_TR[0], pip_BR[0], pip_BL[0]]
    by = [pip_TL[1], pip_TR[1], pip_BR[1], pip_BL[1]]
    xs = np.linalg.solve(A, bx)
    ys = np.linalg.solve(A, by)
    return [(float(xs[i]), float(ys[i])) for i in range(4)]

# Top face pip positions (face 5 in reference)
TOP_PIPS_REF = {
    'TL': (78, 86), 'TR': (142, 49), 'BR': (197, 96), 'BL': (132, 136), 'C': (137, 91),
}
TOP_QUAD = solve_face_corners(TOP_PIPS_REF['TL'], TOP_PIPS_REF['TR'], TOP_PIPS_REF['BR'], TOP_PIPS_REF['BL'])

# Right face: 3 pips on diagonal TL-C-BR (face 3 in reference)
# Top edge of right face = top face S-E edge (TOP_QUAD[3]-TOP_QUAD[2])
RIGHT_TL_corner = TOP_QUAD[3]
RIGHT_TR_corner = TOP_QUAD[2]
RIGHT_PIPS_REF = {
    'TL': (161, 185), 'C': (189, 188), 'BR': (214, 192),
}
# Solve right BR, BL from pip constraints (homography)
# Use the 2 corner pips of face 3 (TL and BR positions face-local) plus the 2 known corners
def solve_2_unknown_corners(known_TL, known_TR, pip_TL_pos, pip_BR_pos):
    """Knowing TL, TR of face quad, and pip positions at face-local (0.25,0.25) and (0.75,0.75),
    solve for BL and BR."""
    A = np.array([[0.1875, 0.0625], [0.1875, 0.5625]])
    bx = [
        pip_TL_pos[0] - 0.5625*known_TL[0] - 0.1875*known_TR[0],
        pip_BR_pos[0] - 0.0625*known_TL[0] - 0.1875*known_TR[0],
    ]
    by = [
        pip_TL_pos[1] - 0.5625*known_TL[1] - 0.1875*known_TR[1],
        pip_BR_pos[1] - 0.0625*known_TL[1] - 0.1875*known_TR[1],
    ]
    sx = np.linalg.solve(A, bx)
    sy = np.linalg.solve(A, by)
    BL = (float(sx[0]), float(sy[0]))
    BR = (float(sx[1]), float(sy[1]))
    return BL, BR

RIGHT_BL_corner, RIGHT_BR_corner = solve_2_unknown_corners(
    RIGHT_TL_corner, RIGHT_TR_corner, RIGHT_PIPS_REF['TL'], RIGHT_PIPS_REF['BR']
)
RIGHT_QUAD = [RIGHT_TL_corner, RIGHT_TR_corner, RIGHT_BR_corner, RIGHT_BL_corner]

# Left face: only 1 reference pip (face 1, center).
# Top edge = top face W-S edge (TOP_QUAD[0]-TOP_QUAD[3]).
LEFT_TL_corner = TOP_QUAD[0]
LEFT_TR_corner = TOP_QUAD[3]
# 1 pip detection — actually we had 2 small detections that we'll average
LEFT_PIPS_REF = {'C': (71, 179)}
# To estimate BL, BR with 1 pip: assume the face is the mirror of the right face about the dice's vertical mid-axis
# Right face's depth offset (from top edge to bottom edge):
right_TR_to_BR = (RIGHT_BR_corner[0]-RIGHT_TR_corner[0], RIGHT_BR_corner[1]-RIGHT_TR_corner[1])
right_TL_to_BL = (RIGHT_BL_corner[0]-RIGHT_TL_corner[0], RIGHT_BL_corner[1]-RIGHT_TL_corner[1])
# Mirror (negate x):
left_TR_to_BR = (-right_TL_to_BL[0], right_TL_to_BL[1])
left_TL_to_BL = (-right_TR_to_BR[0], right_TR_to_BR[1])
LEFT_BR_corner = (LEFT_TR_corner[0] + left_TR_to_BR[0], LEFT_TR_corner[1] + left_TR_to_BR[1])
LEFT_BL_corner = (LEFT_TL_corner[0] + left_TL_to_BL[0], LEFT_TL_corner[1] + left_TL_to_BL[1])
LEFT_QUAD = [LEFT_TL_corner, LEFT_TR_corner, LEFT_BR_corner, LEFT_BL_corner]

print('TOP_QUAD :', [tuple(round(c,1) for c in p) for p in TOP_QUAD])
print('RIGHT_QUAD:', [tuple(round(c,1) for c in p) for p in RIGHT_QUAD])
print('LEFT_QUAD:', [tuple(round(c,1) for c in p) for p in LEFT_QUAD])

# === PIP PATTERNS (face-local u, v in [0,1]) ===
PATTERNS = {
    1: [(0.5, 0.5)],
    2: [(0.25, 0.25), (0.75, 0.75)],
    3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75), (0.5, 0.5)],
    6: [(0.25, 0.25), (0.25, 0.5), (0.25, 0.75), (0.75, 0.25), (0.75, 0.5), (0.75, 0.75)],
}

SIDES = {
    1: (2, 3), 2: (1, 4), 3: (1, 2), 4: (1, 5), 5: (1, 3), 6: (5, 3),
}

COLORS = {
    'blue':   (59, 130, 246), 'red': (239, 68, 68), 'green': (34, 197, 94),
    'yellow': (234, 179, 8), 'orange': (249, 115, 22), 'purple': (168, 85, 247),
}

# === HOMOGRAPHY: unit-square (TL=0,0 ; TR=1,0 ; BR=1,1 ; BL=0,1) → face quad ===
def compute_homography(quad):
    src = np.array([[0,0],[1,0],[1,1],[0,1]], dtype=np.float32)
    dst = np.array(quad, dtype=np.float32)
    return cv2.getPerspectiveTransform(src, dst)

H_TOP = compute_homography(TOP_QUAD)
H_RIGHT = compute_homography(RIGHT_QUAD)
H_LEFT = compute_homography(LEFT_QUAD)

def apply_homography(H, u, v):
    pt = np.array([u, v, 1.0])
    out = H @ pt
    return (out[0]/out[2], out[1]/out[2])

# === LOAD SOURCE, INPAINT ALL PIPS ===
src_img = np.array(Image.open(SRC).convert('RGBA'))
h, w = src_img.shape[:2]
rgb = src_img[:,:,:3]
alpha = src_img[:,:,3]
gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
dark = ((gray < 90) & (alpha > 200)).astype(np.uint8)
n_comp, labels, stats, centroids = cv2.connectedComponentsWithStats(dark)
mask = np.zeros((h, w), dtype=np.uint8)
for i in range(1, n_comp):
    area = stats[i, cv2.CC_STAT_AREA]
    if area > 60:
        cx, cy = centroids[i]
        r = max(13, int(np.sqrt(area / np.pi)) + 6)
        cv2.circle(mask, (int(cx), int(cy)), r, 255, -1)
bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
inpainted_bgr = cv2.inpaint(bgr, mask, 8, cv2.INPAINT_TELEA)
inpainted_rgb = cv2.cvtColor(inpainted_bgr, cv2.COLOR_BGR2RGB)
clean = src_img.copy()
clean[:,:,:3] = inpainted_rgb
Image.fromarray(clean, 'RGBA').save(os.path.join(BASE, '_clean_all.png'))

# === EXTRACT PIP STAMPS ===
# A stamp = RGBA patch centered on a reference pip, with only "pip pixels" opaque (rest transparent).
def extract_stamp(pip_center, half_w=22, half_h=16):
    """Extract a small RGBA stamp from the source image at the pip center.
    Pip pixels (dark) are opaque; surrounding face pixels are transparent."""
    cx, cy = int(pip_center[0]), int(pip_center[1])
    x0, x1 = max(0, cx-half_w), min(w, cx+half_w+1)
    y0, y1 = max(0, cy-half_h), min(h, cy+half_h+1)
    patch = src_img[y0:y1, x0:x1].copy()
    ph, pw = patch.shape[:2]
    # Identify pip pixels: low brightness
    patch_gray = cv2.cvtColor(patch[:,:,:3], cv2.COLOR_RGB2GRAY)
    # Use a smooth alpha based on darkness — pip pixels (gray<90) fully opaque,
    # bright pixels transparent, intermediate softly blended.
    a = np.clip((140 - patch_gray.astype(np.float32)) / 50.0 * 255.0, 0, 255).astype(np.uint8)
    # Mask out anything outside ~20px of pip center to avoid grabbing nearby pips
    yy, xx = np.ogrid[:ph, :pw]
    dist = np.sqrt((yy - (cy-y0))**2 + (xx - (cx-x0))**2)
    a[dist > min(half_w, half_h)] = 0
    patch[:,:,3] = a
    return patch, (cx-x0, cy-y0)  # patch + anchor point inside patch

# Reference stamps per face. Use central pip for each face (most "balanced" perspective).
STAMP_TOP, ANCHOR_TOP = extract_stamp(TOP_PIPS_REF['C'], half_w=18, half_h=13)
STAMP_RIGHT, ANCHOR_RIGHT = extract_stamp(RIGHT_PIPS_REF['C'], half_w=18, half_h=13)
STAMP_LEFT, ANCHOR_LEFT = extract_stamp(LEFT_PIPS_REF['C'], half_w=18, half_h=13)

def paste_stamp(target_rgba, stamp, anchor, image_pos):
    """Composite stamp onto target_rgba (RGBA np array) at image_pos, anchored at anchor."""
    th, tw = target_rgba.shape[:2]
    sh, sw = stamp.shape[:2]
    cx, cy = int(round(image_pos[0])), int(round(image_pos[1]))
    ax, ay = anchor
    x0 = cx - ax; y0 = cy - ay
    x1 = x0 + sw; y1 = y0 + sh
    # Clip
    sx0 = max(0, -x0); sy0 = max(0, -y0)
    sx1 = sw - max(0, x1 - tw); sy1 = sh - max(0, y1 - th)
    tx0 = max(0, x0); ty0 = max(0, y0)
    tx1 = min(tw, x1); ty1 = min(th, y1)
    if sx1 <= sx0 or sy1 <= sy0:
        return target_rgba
    stamp_clip = stamp[sy0:sy1, sx0:sx1]
    target_clip = target_rgba[ty0:ty1, tx0:tx1]
    # Alpha blend
    a = stamp_clip[:,:,3:4].astype(np.float32) / 255.0
    target_clip[:,:,:3] = (stamp_clip[:,:,:3].astype(np.float32) * a + target_clip[:,:,:3].astype(np.float32) * (1-a)).astype(np.uint8)
    target_clip[:,:,3] = np.maximum(target_clip[:,:,3], stamp_clip[:,:,3])
    target_rgba[ty0:ty1, tx0:tx1] = target_clip
    return target_rgba

# === GENERATE 36 VARIANTS ===
for old in glob.glob(os.path.join(BASE, 'Dice_[1-6]_*.png')):
    os.remove(old)

count = 0
for color_name, (cr, cg, cb) in COLORS.items():
    rec = clean.copy().astype(np.float32)
    rec[:,:,0] *= cr / 255.0
    rec[:,:,1] *= cg / 255.0
    rec[:,:,2] *= cb / 255.0
    rec = np.clip(rec, 0, 255).astype(np.uint8)
    rec[:,:,3] = clean[:,:,3]
    for top_value in range(1, 7):
        fl_value, fr_value = SIDES[top_value]
        img = rec.copy()
        # Top face pips
        for (u, v) in PATTERNS[top_value]:
            pos = apply_homography(H_TOP, u, v)
            img = paste_stamp(img, STAMP_TOP, ANCHOR_TOP, pos)
        # Left face pips
        for (u, v) in PATTERNS[fl_value]:
            pos = apply_homography(H_LEFT, u, v)
            img = paste_stamp(img, STAMP_LEFT, ANCHOR_LEFT, pos)
        # Right face pips
        for (u, v) in PATTERNS[fr_value]:
            pos = apply_homography(H_RIGHT, u, v)
            img = paste_stamp(img, STAMP_RIGHT, ANCHOR_RIGHT, pos)
        out = os.path.join(BASE, f'Dice_{top_value}_{color_name}.png')
        Image.fromarray(img, 'RGBA').save(out, 'PNG')
        count += 1
print('Generated', count, 'dice variants using reference pip stamps + perspective.')
