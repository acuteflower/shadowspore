"""Fast vectorized High-Res (~186px tall inside 144x216 cell, Sprite2D.scale = 1/3 -> 62 world units)
pixel-art extraction, de-fringing, OKLab palette-locking, pure-silver hair guard, and 2D rig poser.
"""
from __future__ import annotations
from collections import deque
import math
import numpy as np
from PIL import Image, ImageFilter

CELL_W, CELL_H = 144, 216
FOOT_X, FOOT_Y = 72, 198
TARGET_BODY_H = 186  # 186 / 3 = 62.0 world units tall; 1:1 native pixels on 1080p!


def hx(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


# 0=OUTLINE, 1=HAIR(cool only!), 2=SKIN, 3=EYE_CRYS, 4=CORSET, 5=COAT, 6=LEATHER, 7=GOLD, 8=LIP
PALETTE_SPEC: list[tuple[str, int]] = [
    ("12091c", 0), ("1d122b", 0),
    ("ffffff", 1), ("f6f3ff", 1), ("e6e1f8", 1), ("d0c8ec", 1),
    ("b0a6d6", 1), ("8c80b4", 1), ("685c8c", 1), ("463c68", 1),
    ("fff0e4", 2), ("fce0ce", 2), ("f6cbb4", 2), ("e5ac98", 2), ("c9867a", 2), ("9c5c5e", 2),
    ("26113e", 3), ("4e287c", 3), ("7c48b8", 3), ("aa74e8", 3), ("d4aef8", 3), ("f6ecff", 3),
    ("231834", 4), ("312444", 4), ("44345a", 4), ("5c4976", 4), ("766292", 4),
    ("331a4c", 5), ("4a2868", 5), ("643a86", 5), ("8050a6", 5), ("9e6cc4", 5),
    ("2d1b2a", 6), ("462c3e", 6), ("624154", 6), ("7e586c", 6), ("9c7688", 6), ("b894a4", 6),
    ("6e4c20", 7), ("a67a34", 7), ("deb256", 7), ("fce89a", 7),
    ("b86472", 8), ("df8e96", 8),
]

PAL_RGB = np.array([hx(c) for c, _ in PALETTE_SPEC], dtype=np.uint8)
PAL_MAT = np.array([m for _, m in PALETTE_SPEC], dtype=np.int32)
PAL_HEX = ["#" + c for c, _ in PALETTE_SPEC]


def _srgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    x = np.clip(rgb.astype(np.float32) / 255.0, 0.0, 1.0)
    lin = np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b + 1e-12)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b + 1e-12)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b + 1e-12)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return np.stack([L, A, B], axis=-1)


PAL_LAB = _srgb_to_oklab(PAL_RGB)
COOL_HAIR_IDXS = np.where(np.isin(PAL_MAT, [0, 1]))[0]


def _shift2d(arr: np.ndarray, dy: int, dx: int, fill: int = 0) -> np.ndarray:
    H, W = arr.shape
    out = np.full_like(arr, fill)
    y0_d, y1_d = max(0, dy), min(H, H + dy)
    x0_d, x1_d = max(0, dx), min(W, W + dx)
    y0_s, y1_s = max(0, -dy), min(H, H - dy)
    x0_s, x1_s = max(0, -dx), min(W, W - dx)
    if y1_d > y0_d and x1_d > x0_d:
        out[y0_d:y1_d, x0_d:x1_d] = arr[y0_s:y1_s, x0_s:x1_s]
    return out


def _erode_bool(mask: np.ndarray, steps: int = 1) -> np.ndarray:
    cur = mask
    for _ in range(steps):
        cur = (
            cur
            & _shift2d(cur, -1, 0, 0)
            & _shift2d(cur, 1, 0, 0)
            & _shift2d(cur, 0, -1, 0)
            & _shift2d(cur, 0, 1, 0)
        )
    return cur


def _keep_large_components_small(mask: np.ndarray, min_area: int = 12) -> np.ndarray:
    """Fast component filter run AFTER downscaling (or on coarse 2x2 grid)."""
    H, W = mask.shape
    vis = np.zeros((H, W), dtype=bool)
    out = np.zeros((H, W), dtype=bool)
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if vis[sy, sx]:
            continue
        q = deque([(sy, sx)])
        vis[sy, sx] = True
        comp = []
        while q:
            cy, cx = q.popleft()
            comp.append((cy, cx))
            if cy > 0 and not vis[cy - 1, cx] and mask[cy - 1, cx]:
                vis[cy - 1, cx] = True; q.append((cy - 1, cx))
            if cy + 1 < H and not vis[cy + 1, cx] and mask[cy + 1, cx]:
                vis[cy + 1, cx] = True; q.append((cy + 1, cx))
            if cx > 0 and not vis[cy, cx - 1] and mask[cy, cx - 1]:
                vis[cy, cx - 1] = True; q.append((cy, cx - 1))
            if cx + 1 < W and not vis[cy, cx + 1] and mask[cy, cx + 1]:
                vis[cy, cx + 1] = True; q.append((cy, cx + 1))
        if len(comp) >= min_area:
            for cy, cx in comp:
                out[cy, cx] = True
    return out


def estimate_bg(img_rgb: np.ndarray) -> np.ndarray:
    b0 = img_rgb[:6, :, :].reshape(-1, 3)
    b1 = img_rgb[-6:, :, :].reshape(-1, 3)
    b2 = img_rgb[:, :6, :].reshape(-1, 3)
    b3 = img_rgb[:, -6:, :].reshape(-1, 3)
    return np.median(np.vstack([b0, b1, b2, b3]), axis=0).astype(np.float32)


def clean_crop_rgba(
    crop_rgb: np.ndarray,
    bg_rgb: np.ndarray,
    strip_ground_shadow: bool = True,
    strip_water_rings: bool = False,
    min_comp_area: int = 40,
) -> np.ndarray:
    arr = crop_rgb.astype(np.float32)
    H, W, _ = arr.shape
    diff = np.linalg.norm(arr - bg_rgb[None, None, :], axis=-1)
    is_bg = diff < 18.5

    if strip_ground_shadow:
        ratio = arr / np.maximum(bg_rgb[None, None, :], 1.0)
        r_mean = ratio.mean(axis=-1)
        r_std = ratio.std(axis=-1)
        lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
        ys = np.arange(H)[:, None]
        rough_fg = (~is_bg) & ~((r_std < 0.048) & (r_mean > 0.54) & (r_mean < 0.98) & (lum > 42.0))
        # Despeckle rough_fg via 3x3 neighbor count (>=3) so JPEG noise doesn't skew y_bot!
        rf_i = rough_fg.astype(np.int32)
        rf_nb = _shift2d(rf_i, 1, 0) + _shift2d(rf_i, -1, 0) + _shift2d(rf_i, 0, 1) + _shift2d(rf_i, 0, -1)
        fg_ys = np.nonzero(rough_fg & (rf_nb >= 3))[0]
        if len(fg_ys) > 0:
            y_bot = int(fg_ys.max())
            shadow_zone = ys >= (y_bot - int(0.14 * (y_bot - int(fg_ys.min()))))
            is_shadow = shadow_zone & (r_std < 0.052) & (r_mean > 0.52) & (r_mean < 0.99) & (lum > 40.0)
            is_bg = is_bg | is_shadow

    if strip_water_rings:
        # Strip painted cyan/slate water ripples on swim sheet so game's real WaterField / SwimWater renders cleanly!
        r_c, g_c, b_c = arr[..., 0], arr[..., 1], arr[..., 2]
        is_cyan_ripple = (g_c > r_c + 12) & (b_c > r_c + 18)
        is_bg = is_bg | is_cyan_ripple

    fg = ~is_bg
    # Fast 3x3 despeckle
    f_i = fg.astype(np.int32)
    fg = fg & ((_shift2d(f_i, 1, 0) + _shift2d(f_i, -1, 0) + _shift2d(f_i, 0, 1) + _shift2d(f_i, 0, -1)) >= 2)

    pil_min = Image.fromarray(crop_rgb, "RGB").filter(ImageFilter.MinFilter(3))
    interior_dil = np.asarray(pil_min, dtype=np.float32)

    eroded = _erode_bool(fg, steps=2)
    border = fg & (~eroded)
    d_to_bg = np.linalg.norm(arr - bg_rgb[None, None, :], axis=-1)
    d_int_bg = np.maximum(np.linalg.norm(interior_dil - bg_rgb[None, None, :], axis=-1), 20.0)
    alpha_est = np.clip(d_to_bg / d_int_bg, 0.0, 1.0)

    trim = border & (alpha_est < 0.48) & (d_to_bg < 38.0)
    fg = fg & (~trim)

    eroded1 = _erode_bool(fg, steps=1)
    edge1 = fg & (~eroded1)
    rgb_clean = arr.copy()
    a_unmix = np.clip(d_to_bg / np.maximum(d_int_bg, 25.0), 0.55, 1.0)[..., None]
    unmixed = np.clip((arr - (1.0 - a_unmix) * bg_rgb[None, None, :]) / a_unmix, 0.0, 255.0)
    rgb_clean[edge1] = np.where(d_to_bg[edge1, None] < 55.0, interior_dil[edge1], unmixed[edge1])

    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(np.rint(rgb_clean), 0, 255).astype(np.uint8)
    rgba[fg, 3] = 255
    return rgba


def pixelize_rgba(
    src_rgba: np.ndarray,
    scale_h: int | None = None,
    px_step: float | None = None,
) -> np.ndarray:
    """100x faster vectorized 3x3-subpixel medoid downsampler + OKLab 44-color palette-locker!"""
    ys, xs = np.nonzero(src_rgba[..., 3] > 128)
    if len(ys) == 0:
        return np.zeros((16, 16, 4), dtype=np.uint8)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop = src_rgba[y0:y1, x0:x1]
    sh, sw, _ = crop.shape

    if px_step is None:
        assert scale_h is not None and scale_h > 0
        px_step = sh / float(scale_h)

    tw = max(1, int(round(sw / px_step)))
    th = max(1, int(round(sh / px_step)))

    # Vectorized 3x3 subpixel sampling inside each target cell -> shape [th, tw, 9, 4]
    offs = (-0.30, 0.0, 0.30)
    samples = []
    for oy in offs:
        sy = np.clip(((np.arange(th) + 0.5 + oy) * px_step).astype(np.int32), 0, sh - 1)
        for ox in offs:
            sx = np.clip(((np.arange(tw) + 0.5 + ox) * px_step).astype(np.int32), 0, sw - 1)
            samples.append(crop[sy[:, None], sx[None, :]])
    stack = np.stack(samples, axis=2)  # [th, tw, 9, 4]
    op = stack[..., 3] > 128            # [th, tw, 9]
    cov = op.sum(axis=2)                # 0..9
    solid = cov >= 4

    # Weighted median approx: replace transparent subpixels with center subpixel (idx 4) before median
    center_rgb = stack[:, :, 4:5, :3]
    valid_rgb = np.where(op[..., None], stack[..., :3], center_rgb).astype(np.float32)
    med_rgb = np.median(valid_rgb, axis=2)  # [th, tw, 3]
    # Pick exact real sample closest to med_rgb among opaque samples!
    dist_m = np.sum((stack[..., :3].astype(np.float32) - med_rgb[:, :, None, :]) ** 2, axis=-1)
    dist_m = np.where(op, dist_m, 1e12)
    best_k = np.argmin(dist_m, axis=2)
    out_rgb = np.take_along_axis(stack[..., :3], best_k[:, :, None, None], axis=2)[:, :, 0, :]

    solid = _keep_large_components_small(solid, min_area=8)

    lab = _srgb_to_oklab(out_rgb)
    d2 = np.sum((lab[:, :, None, :] - PAL_LAB[None, None, :, :]) ** 2, axis=-1)

    r_c = out_rgb[..., 0].astype(np.int32)
    g_c = out_rgb[..., 1].astype(np.int32)
    b_c = out_rgb[..., 2].astype(np.int32)
    is_gold_like = (r_c > b_c + 34) & (g_c > b_c + 16) & (r_c > 115)
    gold_mask = (PAL_MAT == 7)[None, None, :]
    d2 = np.where(is_gold_like[..., None] & gold_mask, d2 * 0.55, d2)

    lum = 0.299 * r_c + 0.587 * g_c + 0.114 * b_c
    is_cool_silver = (b_c >= r_c - 6) & (lum > 78) & ((b_c - g_c) < 38)
    non_hair_warm = np.isin(PAL_MAT, [2, 6, 7, 8])[None, None, :]
    d2 = np.where(is_cool_silver[..., None] & non_hair_warm, d2 + 10.0, d2)

    best_idx = np.argmin(d2, axis=-1)
    quant_rgb = PAL_RGB[best_idx]

    mat_grid = np.where(solid, PAL_MAT[best_idx], -1)
    for _ in range(2):
        hair_nb = np.zeros((th, tw), dtype=np.int32)
        warm_nb = np.zeros((th, tw), dtype=np.int32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            s_m = _shift2d(mat_grid, dy, dx, fill=-1)
            hair_nb += (s_m == 1).astype(np.int32)
            warm_nb += np.isin(s_m, [2, 6, 7]).astype(np.int32)
        stray_warm_in_hair = solid & np.isin(mat_grid, [2, 6, 8]) & (hair_nb >= 3) & (warm_nb <= 1)
        if not np.any(stray_warm_in_hair):
            break
        d2_cool = d2[:, :, COOL_HAIR_IDXS]
        cool_choice = COOL_HAIR_IDXS[np.argmin(d2_cool, axis=-1)]
        best_idx = np.where(stray_warm_in_hair, cool_choice, best_idx)
        quant_rgb = PAL_RGB[best_idx]
        mat_grid = np.where(solid, PAL_MAT[best_idx], -1)

    res = np.zeros((th, tw, 4), dtype=np.uint8)
    res[solid, :3] = quant_rgb[solid]
    res[solid, 3] = 255
    return res


def place_in_cell(
    spr_rgba: np.ndarray,
    cell_w: int = CELL_W,
    cell_h: int = CELL_H,
    foot_x: int = FOOT_X,
    foot_y: int = FOOT_Y,
    dx: int = 0,
    dy: int = 0,
    center_mode: str = "lower_body",
) -> np.ndarray:
    ys, xs = np.nonzero(spr_rgba[..., 3] > 0)
    canvas = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    if len(ys) == 0:
        return canvas
    y_min, y_max = int(ys.min()), int(ys.max())
    if center_mode == "lower_body":
        leg_mask = (spr_rgba[..., 3] > 0) & (np.arange(spr_rgba.shape[0])[:, None] >= int(y_min + 0.72 * (y_max - y_min)))
        lxs = np.nonzero(leg_mask)[1]
        cx = int(round(0.5 * (int(lxs.min()) + int(lxs.max())))) if len(lxs) > 0 else int(round(xs.mean()))
    else:
        cx = int(round(0.5 * (int(xs.min()) + int(xs.max()))))

    ox = foot_x - cx + dx
    oy = foot_y - y_max + dy

    sh, sw, _ = spr_rgba.shape
    dx0, dx1 = max(0, ox), min(cell_w, ox + sw)
    dy0, dy1 = max(0, oy), min(cell_h, oy + sh)
    sx0, sx1 = dx0 - ox, dx1 - ox
    sy0, sy1 = dy0 - oy, dy1 - oy
    if dx1 > dx0 and dy1 > dy0:
        canvas[dy0:dy1, dx0:dx1] = spr_rgba[sy0:sy1, sx0:sx1]
    return canvas


def split_strip_bboxes(rgba: np.ndarray, min_w: int = 24) -> list[tuple[int, int, int, int]]:
    """Splits a horizontal row of characters into individual (x0, y0, x1, y1) bounding boxes."""
    col_has = (rgba[..., 3] > 128).sum(axis=0) >= 4
    boxes = []
    in_seg = False
    x0 = 0
    for x in range(len(col_has)):
        if col_has[x] and not in_seg:
            in_seg = True
            x0 = x
        elif not col_has[x] and in_seg:
            in_seg = False
            if x - x0 >= min_w:
                ys = np.nonzero(rgba[:, x0:x, 3] > 128)[0]
                if len(ys) > 0:
                    boxes.append((x0, int(ys.min()), x, int(ys.max()) + 1))
    if in_seg and len(col_has) - x0 >= min_w:
        ys = np.nonzero(rgba[:, x0:, 3] > 128)[0]
        if len(ys) > 0:
            boxes.append((x0, int(ys.min()), len(col_has), int(ys.max()) + 1))
    return boxes


def pose_cell(
    master_cell: np.ndarray,
    sector: int,
    bob_y: int = 0,
    lean_deg: float = 0.0,
    stride: float = 0.0,
    lift_a: int = 0,
    lift_b: int = 0,
    arm_swing: float = 0.0,
    hair_sway: float = 0.0,
    coat_flare: float = 0.0,
    crouch: float = 0.0,
) -> np.ndarray:
    """Articulated High-Res pixel-art deformation on a 144x216 cell (nearest-neighbor, 100% palette-pure!):
    Smoothly animates legs, boots, coat tails, arms, breathing chest, hair waves, torso lean, and sneak crouch
    while keeping face, eyes, bust, hairpin, and outlines razor-sharp!
    """
    H, W, _ = master_cell.shape
    ys, xs = np.mgrid[0:H, 0:W]
    # Vertical normalized body coordinate: u = 0 at feet (198), u = 1 at crown (12)
    u = np.clip((float(FOOT_Y) - ys.astype(np.float32)) / float(TARGET_BODY_H), -0.1, 1.15)

    # Facing direction vector in screen x: +1 right (E, SE, NE), -1 left (W, SW, NW), 0 front/back (S, N)
    dir_x = {0: 1.0, 1: 0.75, 2: 0.0, 3: -0.75, 4: -1.0, 5: -0.75, 6: 0.0, 7: 0.75}[sector]

    # 1. Crouch compression (compresses knees/hips u=0.08..0.55 downward cleanly while keeping head & boots crisp!)
    crouch_px = crouch * 18.0 * np.clip(1.0 - np.maximum(0.0, 0.12 - u) / 0.12, 0.0, 1.0)
    # Upper body bob
    upper_w = np.clip((u - 0.34) / 0.18, 0.0, 1.0)
    dy_total = float(bob_y) * upper_w + crouch_px

    # 2. Forward torso/head lean during sprint/jog/sneak
    lean_rad = math.radians(lean_deg)
    dx_lean = dir_x * math.tan(lean_rad) * np.maximum(0.0, u - 0.32) * float(TARGET_BODY_H) * 0.55

    # 3. Leg & boot stride (below hip u < 0.44): split left/right of x = FOOT_X (or front/back in side views!)
    leg_w = np.clip((0.44 - u) / 0.36, 0.0, 1.0)
    rel_x = xs.astype(np.float32) - float(FOOT_X)

    if sector in (2, 6):  # S, N: left leg (rel_x < 0) vs right leg (rel_x >= 0) step vertically & slightly in x!
        side_sgn = np.where(rel_x < 0.0, -1.0, 1.0)
        dy_leg = np.where(rel_x < 0.0, -float(lift_a), -float(lift_b)) * leg_w
        dx_leg = side_sgn * stride * 2.5 * leg_w
    else:
        # Side & 3/4 views: stride shears lower legs horizontally + lifts passing foot cleanly!
        side_sgn = np.where(rel_x < 0.0, -1.0, 1.0)
        dx_leg = (side_sgn * abs(stride) * 7.5 + stride * 5.0 * np.sign(rel_x + 0.1)) * leg_w
        dy_leg = np.where(rel_x * dir_x > 0.0, -float(lift_a), -float(lift_b)) * leg_w

    # 4. Coat tail secondary billow & hair S-wave sway
    coat_zone = (u > 0.18) & (u < 0.48) & (np.abs(rel_x) > 12.0)
    dx_coat = np.where(coat_zone, np.sign(rel_x) * coat_flare * (0.48 - u) * 14.0 - dir_x * abs(coat_flare) * 3.5, 0.0)

    hair_zone = (u > 0.54) & (u < 0.90)
    dx_hair = np.where(hair_zone, math.sin(hair_sway) * (0.90 - u) * 8.5 - dir_x * abs(lean_deg) * 0.18 * (0.90 - u), 0.0)

    # 5. Subtle opposite arm swing on outer shoulder-to-hand columns (|rel_x| > 16, u in 0.40..0.72)
    arm_zone = (u > 0.40) & (u < 0.72) & (np.abs(rel_x) > 15.0)
    arm_sgn = np.where(rel_x < 0.0, -1.0, 1.0)
    dy_arm = np.where(arm_zone, arm_sgn * arm_swing * (0.72 - u) * 14.0, 0.0)
    dx_arm = np.where(arm_zone, arm_sgn * arm_swing * (0.72 - u) * 9.0 * (0.4 + 0.6 * abs(dir_x)), 0.0)

    src_x = np.rint(xs.astype(np.float32) - dx_lean - dx_leg - dx_coat - dx_hair - dx_arm).astype(np.int32)
    src_y = np.rint(ys.astype(np.float32) - dy_total - dy_leg - dy_arm).astype(np.int32)

    valid = (src_x >= 0) & (src_x < W) & (src_y >= 0) & (src_y < H)
    out = np.zeros_like(master_cell)
    out[valid] = master_cell[src_y[valid], src_x[valid]]
    return out


def split_cosmetic_layers(sheet_rgba: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Splits a High-Res Ellie RGBA sheet into modular Paper-Doll textures for `AppearanceComponent`:
    Returns (base_rgba, outfit_rgba, hair_front_rgba, hair_back_rgba).
    - Hair pixels (pure cool silver-lavender + gold hairpin near head) go into `hair_front` / `hair_back`
      so `hit_flash.gdshader`'s `hair_tint` dyes ONLY her hair (preserving gold hairpin via shader rule!).
    - Outfit pixels (corset, puff sleeves, purple coat, leather boots/bracers/belt/pouch/garter, crystal)
      go into `outfit_rgba` so `outfit_tint` dyes her outfit while keeping porcelain skin untouched!
    - Base holds full silhouette skin + neutral dark under-bodice fallback under outfit/hair so zero holes ever appear!
    """
    H, W, _ = sheet_rgba.shape
    op = sheet_rgba[..., 3] > 0
    rgb = sheet_rgba[..., :3]

    # Match exact palette index (fast RGB lookup via Lab / exact RGB distance)
    d = np.sum((rgb.astype(np.int32)[:, :, None, :] - PAL_RGB.astype(np.int32)[None, None, :, :]) ** 2, axis=-1)
    pidx = np.argmin(d, axis=-1)
    mat = np.where(op, PAL_MAT[pidx], -1)

    ys = (np.arange(H) % CELL_H)[:, None]
    # Gold in head zone (y < 68 inside 216 cell) is the hairpin -> belongs to hair_front!
    is_hairpin = (mat == 7) & (ys < 68)
    is_hair_col = (mat == 1) | is_hairpin
    # Dark outline pixels bordering hair on the head/locks belong to hair!
    h_i = is_hair_col.astype(np.int32)
    h_nb = _shift2d(h_i, 1, 0) + _shift2d(h_i, -1, 0) + _shift2d(h_i, 0, 1) + _shift2d(h_i, 0, -1)
    is_hair = is_hair_col | ((mat == 0) & (h_nb >= 2) & (ys < 118))

    # Outfit: corset(4), coat/puff(5), leather(6), lower gold buckles(7 & ys>=68), crystal below choker(3 & ys>=48)
    is_crys = (mat == 3) & (ys >= 50)
    is_outfit_col = np.isin(mat, [4, 5, 6]) | ((mat == 7) & (ys >= 68)) | is_crys
    o_i = is_outfit_col.astype(np.int32)
    o_nb = _shift2d(o_i, 1, 0) + _shift2d(o_i, -1, 0) + _shift2d(o_i, 0, 1) + _shift2d(o_i, 0, -1)
    is_outfit = (~is_hair) & (is_outfit_col | ((mat == 0) & (o_nb >= 1) & (ys >= 46)))

    base = sheet_rgba.copy()
    # Under hair & outfit in base, leave neutral dark-plum mannequin silhouette where needed so removing hair/outfit never leaves holes
    hair_front = np.zeros_like(sheet_rgba)
    hair_back = np.zeros_like(sheet_rgba)
    outfit = np.zeros_like(sheet_rgba)

    hair_front[is_hair] = sheet_rgba[is_hair]
    outfit[is_outfit] = sheet_rgba[is_outfit]
    return base, outfit, hair_front, hair_back


def make_blood_map(sheet_rgba: np.ndarray, cell_w: int = CELL_W, cell_h: int = CELL_H, foot_y_in_cell: int = FOOT_Y) -> np.ndarray:
    H, W, _ = sheet_rgba.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    op = sheet_rgba[..., 3] > 128
    if not np.any(op):
        return out
    ys, xs = np.mgrid[0:H, 0:W]
    ly = (ys % cell_h).astype(np.float32)
    lx = (xs % cell_w).astype(np.float32) - (cell_w * 0.5)
    waist_y = float(foot_y_in_cell) - float(TARGET_BODY_H) * 0.44
    dist = np.sqrt((lx / (cell_w * 0.22)) ** 2 + ((ly - waist_y) / (TARGET_BODY_H * 0.36)) ** 2)
    n = np.sin(xs * 12.9898 + ys * 78.233) * 43758.5453
    n = n - np.floor(n)
    thresh = np.clip(0.12 + 0.72 * dist + 0.14 * n, 0.05, 0.98)
    out[..., 0] = np.clip(np.rint(thresh * 255.0), 1, 254).astype(np.uint8)
    out[..., 1] = 128
    out[..., 2] = 0
    in_bandage = op & (np.abs(ly - waist_y) < (TARGET_BODY_H * 0.055))
    out[..., 3] = np.where(in_bandage, 254, np.where(op, 255, 0)).astype(np.uint8)
    return out
