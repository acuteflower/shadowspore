#!/usr/bin/env python3
"""Handcrafted Botanical Pixel-Art Generator for Shadowspore (`LivingFlora 2.0` — 28 Species).

Strictly adheres to `docs/design_guide.md`:
  - Top-left lighting, 3-4 tonal steps per material, cool-violet/deep-teal tinted 1px dark outlines (NEVER #000000!)
  - Foliage ramps derived directly from Shadowspore Meadow (#22483c..#a8dc8c), Woodland Moss, and Silver-Sage
  - Muted, harmonious blossom palettes (Cream-Ivory, Lavender-Violet, Antique Gold, Cornflower-Smoke,
    Turquoise-Dew, Rosehip-Carmine) — zero neon or cartoon primaries!
  - Separate unshaded `*_glow.png` sheets for nocturnal bioluminescence & morning Star-Dew pearls.

Outputs:
  assets/props/flora_sanctuary_small.png       192x720 px (6 cols x 20 rows of 32x36 px, foot at (16, 31))
  assets/props/flora_sanctuary_small_glow.png  Matching night/dew unlit glow sheet
  assets/props/flora_sanctuary_large.png       280x416 px (5 cols x 8 rows of 56x52 px, foot at (28, 45))
  assets/props/flora_sanctuary_large_glow.png  Matching night/dew unlit glow sheet
  docs/img/flora_sanctuary_small_3x.png        3x nearest visual QA sheet (all 20 small/medium species & states)
  docs/img/flora_sanctuary_large_3x.png        3x nearest visual QA sheet (all 8 tall herbs & shrubs & states)
"""
from __future__ import annotations

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, hexc, write_png  # noqa: E402

PROJ_ROOT = pathlib.Path(__file__).resolve().parent.parent

SW, SH = 32, 36
S_PIVOT_X, S_PIVOT_Y = 16, 31
S_COLS, S_ROWS = 6, 20

LW, LH = 56, 52
L_PIVOT_X, L_PIVOT_Y = 28, 45
L_COLS, L_ROWS = 5, 8

# ==============================================================================
# Harmonized Shadowspore Botanical Palettes (Design Guide Section 1)
# ==============================================================================

# Foliage Ramps: [0=tinted 1px outline, 1=deep shadow, 2=mid leaf, 3=lit leaf, 4=NW rim highlight]
LEAF_MEADOW = [hexc("162c28"), hexc("22483c"), hexc("3e7d56"), hexc("62a665"), hexc("9ad484")]
LEAF_DEEP = [hexc("122426"), hexc("1c3d38"), hexc("2e614e"), hexc("4a8862"), hexc("78b878")]
LEAF_SAGE = [hexc("1d3034"), hexc("314c4c"), hexc("52756e"), hexc("7ba092"), hexc("b2cfc0")]
LEAF_SUCCULENT = [hexc("23342c"), hexc("3a5842"), hexc("5e8656"), hexc("8ab46c"), hexc("bce08c")]
LEAF_WOOD = [hexc("1e1726"), hexc("362838"), hexc("56404a"), hexc("7a5f62"), hexc("9e827e")]

# Blossom & Berry Ramps: [0=dark calyx/outline, 1=shadow petal, 2=mid petal, 3=sunlit petal]
BL_CREAM = [hexc("45485c"), hexc("8d92ab"), hexc("cbcde0"), hexc("f4f2fa")]
BL_LILAC = [hexc("2d1c4c"), hexc("634496"), hexc("9a7ee0"), hexc("d8c8ff")]
BL_VIOLET = [hexc("241342"), hexc("4c2982"), hexc("7b4ec2"), hexc("b58ef7")]
BL_CHICORY = [hexc("213258"), hexc("3e629c"), hexc("6aa0dc"), hexc("aed4ff")]
BL_GOLD = [hexc("4a3518"), hexc("8c6628"), hexc("cfa44e"), hexc("f7de88")]
BL_BLUSH = [hexc("4a243c"), hexc("8c4e6e"), hexc("cc8ca8"), hexc("f7d2e0")]
BL_PLUM = [hexc("1b0e2e"), hexc("381d5c"), hexc("643896"), hexc("9e72cc")]
BL_TEAL_DEW = [hexc("18424c"), hexc("2a7a84"), hexc("5cd4ce"), hexc("d6fff8")]
FR_ROSEHIP = [hexc("381222"), hexc("7a1e34"), hexc("bf364e"), hexc("f27988")]
FR_ELDER = [hexc("140c24"), hexc("2b1947"), hexc("4e2e78"), hexc("8c6ec2")]
FR_SLOE = [hexc("182038"), hexc("2c3e63"), hexc("4e6c99"), hexc("8cb0d9")]
FR_BRAMBLE = [hexc("160d24"), hexc("33184a"), hexc("5c2c78"), hexc("9c6eb8")]

FOOT_SHADOW = (14, 24, 30, 68)

GLOW_TEAL_LO = (96, 224, 214, 110)
GLOW_TEAL_HI = (196, 255, 246, 195)
GLOW_GOLD_LO = (232, 186, 92, 115)
GLOW_GOLD_HI = (255, 238, 172, 198)
GLOW_VIOLET_LO = (154, 108, 242, 110)
GLOW_VIOLET_HI = (222, 194, 255, 185)


def make_grid(w: int, h: int) -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR] * w for _ in range(h)]


def save_grid(path: pathlib.Path, grid: list[list[tuple[int, int, int, int]]]) -> None:
    write_png(path, len(grid[0]), len(grid), grid)


def put(g: list[list[tuple[int, int, int, int]]], x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= y < len(g) and 0 <= x < len(g[0]):
        g[y][x] = c


def blend_over(dst: tuple[int, int, int, int], src: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    sa = src[3] / 255.0
    if sa <= 0.0:
        return dst
    if sa >= 0.999 or dst[3] == 0:
        return src
    da = dst[3] / 255.0
    oa = sa + da * (1.0 - sa)
    if oa <= 0.001:
        return CLEAR
    return (
        int((src[0] * sa + dst[0] * da * (1.0 - sa)) / oa),
        int((src[1] * sa + dst[1] * da * (1.0 - sa)) / oa),
        int((src[2] * sa + dst[2] * da * (1.0 - sa)) / oa),
        int(oa * 255.0),
    )


def h2(x: int, y: int, seed: int) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / 16777216.0


def shadow_ellipse(px: list[list[tuple[int, int, int, int]]], cx: float, cy: float, rx: float, ry: float) -> None:
    h, w = len(px), len(px[0])
    for y in range(max(0, int(cy - ry - 1)), min(h, int(cy + ry + 2))):
        for x in range(max(0, int(cx - rx - 1)), min(w, int(cx + rx + 2))):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                px[y][x] = blend_over(px[y][x], FOOT_SHADOW)


def apply_tinted_outline(px: list[list[tuple[int, int, int, int]]], outline_col: tuple[int, int, int, int], max_y: int) -> None:
    """Adds a clean 1px dark tinted silhouette rim around opaque plant pixels without muddying airy tips."""
    h, w = len(px), len(px[0])
    orig = [[px[y][x] for x in range(w)] for y in range(h)]
    for y in range(1, min(h - 1, max_y + 2)):
        for x in range(1, w - 1):
            if orig[y][x][3] > 180:
                continue
            # Only outline bottom/right or enclosed pockets so top/left stays crisp & airy!
            up_s = orig[y - 1][x][3] > 200
            lf_s = orig[y][x - 1][3] > 200
            nb = int(up_s) + int(lf_s) + int(orig[y + 1][x][3] > 200) + int(orig[y][x + 1][3] > 200)
            if (up_s and lf_s) or nb >= 3:
                px[y][x] = blend_over(px[y][x], outline_col)


def draw_stem(
    px: list[list[tuple[int, int, int, int]]],
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    bend_x: float,
    ramp: list[tuple[int, int, int, int]],
    thick: int = 1,
) -> list[tuple[int, int]]:
    """Draws a smooth quadratic Bezier stem and returns integer spine points."""
    steps = max(4, int(max(abs(x1 - x0), abs(y1 - y0)) * 1.6))
    mx = (x0 + x1) * 0.5 + bend_x
    my = (y0 + y1) * 0.5
    pts: list[tuple[int, int]] = []
    for i in range(steps + 1):
        t = i / steps
        bx = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * mx + t ** 2 * x1
        by = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * my + t ** 2 * y1
        ix, iy = int(round(bx)), int(round(by))
        c = ramp[3] if t > 0.72 else (ramp[1] if 0.25 < t <= 0.62 else ramp[1])
        if ramp is LEAF_MEADOW:
            c = LEAF_DEEP[1] if t < 0.58 else LEAF_MEADOW[3]
        put(px, ix, iy, c)
        if thick >= 2:
            put(px, ix + 1, iy, ramp[0] if t < 0.5 else ramp[1])
        if not pts or pts[-1] != (ix, iy):
            pts.append((ix, iy))
    return pts


def draw_leaf_pair(
    px: list[list[tuple[int, int, int, int]]],
    cx: int,
    cy: int,
    dx: int,
    dy: int,
    ramp: list[tuple[int, int, int, int]],
    broad: bool = False,
) -> None:
    """Draws a crisp directional pixel leaf stroke from (cx, cy) toward (cx+dx, cy+dy)."""
    steps = max(2, max(abs(dx), abs(dy)))
    for s in range(1, steps + 1):
        t = s / steps
        lx = int(round(cx + dx * t))
        ly = int(round(cy + dy * t))
        lit = (dx <= 0 and dy <= 0) or t > 0.65
        put(px, lx, ly, ramp[4] if (lit and t > 0.72) else (ramp[3] if lit else ramp[2]))
        if broad and 0.25 <= t <= 0.80:
            put(px, lx, ly + 1, ramp[1] if dy >= 0 else ramp[2])


def draw_rosette(
    px: list[list[tuple[int, int, int, int]]],
    cx: int,
    cy: int,
    rx: int,
    ry: int,
    leaves: int,
    ramp: list[tuple[int, int, int, int]],
    seed: int,
    broad: bool = True,
) -> None:
    for i in range(leaves):
        ang = (i / leaves) * math.tau + h2(i, seed, 17) * 0.45
        dx = int(round(math.cos(ang) * rx))
        dy = int(round(math.sin(ang) * ry))
        draw_leaf_pair(px, cx, cy, dx, dy, ramp, broad=broad)
    put(px, cx, cy, ramp[1])


def draw_star_bloom(
    px: list[list[tuple[int, int, int, int]]],
    cx: int,
    cy: int,
    bl_ramp: list[tuple[int, int, int, int]],
    size: int = 2,
    center_col: tuple[int, int, int, int] | None = None,
) -> None:
    """Draws a crisp 3x3 or 5x5 pixel-art wildflower head with NW lighting."""
    if size == 1:
        put(px, cx, cy, bl_ramp[3])
        put(px, cx + 1, cy, bl_ramp[2])
        put(px, cx, cy + 1, bl_ramp[1])
        return
    if size == 2:
        for ox, oy, tone in ((-1, 0, 3), (0, -1, 3), (1, 0, 2), (0, 1, 1)):
            put(px, cx + ox, cy + oy, bl_ramp[tone])
        put(px, cx, cy, center_col if center_col is not None else bl_ramp[2])
    else:
        for ox, oy, tone in (
            (-1, -1, 3), (0, -2, 3), (-2, 0, 3), (1, -1, 3),
            (2, 0, 2), (1, 1, 2), (0, 2, 1), (-1, 1, 2),
            (-1, 0, 3), (0, -1, 3), (1, 0, 2), (0, 1, 2),
        ):
            put(px, cx + ox, cy + oy, bl_ramp[tone])
        put(px, cx, cy, center_col if center_col is not None else BL_GOLD[3])


def draw_umbel(
    px: list[list[tuple[int, int, int, int]]],
    cx: int,
    cy: int,
    rx: int,
    bl_ramp: list[tuple[int, int, int, int]],
    leaf_ramp: list[tuple[int, int, int, int]],
) -> None:
    """Draws a flat-topped compound umbel (Schafgarbe, Engelwurz, Holunderblüte, Mädesüß)."""
    for ox in range(-rx, rx + 1, 2):
        lift = int(round((1.0 - (ox / max(1, rx)) ** 2) * 1.6))
        ux, uy = cx + ox, cy - lift
        put(px, ux, uy + 2, leaf_ramp[2])
        put(px, ux, uy, bl_ramp[3] if ox <= 0 else bl_ramp[2])
        put(px, ux + 1, uy, bl_ramp[2] if ox <= 0 else bl_ramp[1])
        if abs(ox) < rx - 1:
            put(px, ux, uy - 1, bl_ramp[3])


# ==============================================================================
# Small & Medium Flora Generator (20 rows x 6 cols, 32x36 px, foot at (16, 31))
# Cols: 0..2 = Growth Variants, 3 = Night/Rain/Puff State, 4 = Picked, 5 = Cut
# ==============================================================================

def draw_small_species(
    sp_idx: int, col: int
) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(SW, SH)
    glow = make_grid(SW, SH)
    fx, fy = S_PIVOT_X, S_PIVOT_Y
    seed = sp_idx * 97 + col * 13
    is_alt = (col == 3)
    is_picked = (col == 4)
    is_cut = (col == 5)
    var_i = col if col < 3 else 1
    shift = -1 if var_i == 0 else (1 if var_i == 2 else 0)

    # Common cut-stubble state (Col 5) so harvested plants leave realistic green stubs!
    if is_cut:
        shadow_ellipse(px, fx, fy + 0.5, 5.0, 1.8)
        rmp = LEAF_SAGE if sp_idx in (4, 11) else (LEAF_DEEP if sp_idx in (3, 14, 16, 19) else LEAF_MEADOW)
        for ox, h_st in ((-3, 3), (0, 4), (3, 3)):
            for dy in range(h_st):
                put(px, fx + ox, fy - dy, rmp[3] if dy == h_st - 1 else rmp[1 + min(1, dy)])
        apply_tinted_outline(px, rmp[0], fy)
        return px, glow

    # 0: waybread — Pflaster-Wegerich (flat ribbed rosette + tough brownish-green spikes)
    if sp_idx == 0:
        shadow_ellipse(px, fx, fy + 0.5, 6.5, 2.2)
        draw_rosette(px, fx + shift, fy - 1, 6 + (var_i % 2), 3, 7 + var_i, LEAF_MEADOW, seed, broad=True)
        if not is_picked:
            for sx, sh in ((-2 + shift, 8 + var_i), (2 + shift, 7)):
                draw_stem(px, fx + sx * 0.4, fy - 1, fx + sx, fy - sh, 0.4, LEAF_MEADOW)
                for ky in range(fy - sh, fy - sh + 3):
                    put(px, fx + sx, ky, BL_GOLD[2] if ky == fy - sh else LEAF_SAGE[3])
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 1: gold_stonecrop — Gold-Mauerpfeffer (succulent cushion + matte-gold star blooms)
    elif sp_idx == 1:
        shadow_ellipse(px, fx, fy + 0.5, 6.5, 2.2)
        for i in range(14 + var_i * 2):
            ang = i * 2.399 + seed * 0.2
            r = math.sqrt(i / 16.0)
            bx = fx + shift + int(round(math.cos(ang) * (5.5 + var_i * 0.5) * r))
            by = fy - 1 + int(round(math.sin(ang) * 2.8 * r)) - int((1.0 - r) * 2.5)
            put(px, bx, by, LEAF_SUCCULENT[4] if by < fy - 2 else LEAF_SUCCULENT[2])
            put(px, bx, by + 1, LEAF_SUCCULENT[1])
        if not is_picked:
            for gx, gy in ((-3, -4), (1, -5), (4, -3), (-1, -2))[: 3 + (var_i % 2)]:
                draw_star_bloom(px, fx + shift + gx, fy + gy, BL_GOLD, size=1)
        apply_tinted_outline(px, LEAF_SUCCULENT[0], fy)

    # 2: cymbal_weed — Fugen-Zimbelkraut (creeping joint trailer + tiny lilac blooms)
    elif sp_idx == 2:
        for i in range(-7 - var_i, 8 + var_i, 2):
            wy = fy - 1 + int(round(math.sin(i * 0.5 + seed) * 1.6))
            put(px, fx + i, wy, LEAF_MEADOW[3] if i % 4 == 0 else LEAF_MEADOW[2])
            put(px, fx + i, wy + 1, LEAF_MEADOW[1])
            if not is_picked and i in (-5, 1, 5):
                put(px, fx + i, wy - 1, BL_LILAC[3])
                put(px, fx + i + 1, wy - 1, BL_LILAC[2])
        apply_tinted_outline(px, LEAF_MEADOW[0], fy + 1)

    # 3: wall_rue — Steinfugen-Streifenfarn (delicate dark-stemmed rock spleenwort)
    elif sp_idx == 3:
        shadow_ellipse(px, fx, fy + 0.5, 5.5, 2.0)
        fronds = [(-5, -9), (-2, -11 - var_i), (2, -10), (5, -8)]
        for dx, dy in fronds:
            pts = draw_stem(px, fx, fy, fx + dx + shift, fy + dy, dx * 0.25, LEAF_WOOD)
            for idx_p, (px_i, py_i) in enumerate(pts[2:]):
                put(px, px_i - 1, py_i, LEAF_DEEP[3] if idx_p % 2 == 0 else LEAF_DEEP[2])
                put(px, px_i + 1, py_i, LEAF_DEEP[2] if idx_p % 2 == 0 else LEAF_DEEP[1])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 4: silverweed — Kriech-Silberkraut (feathery silver-backed leaves + small gold cinquefoil)
    elif sp_idx == 4:
        shadow_ellipse(px, fx, fy + 0.5, 6.8, 2.2)
        rmp = LEAF_SAGE if is_alt else LEAF_MEADOW
        draw_rosette(px, fx + shift, fy - 1, 7, 3, 8, rmp, seed, broad=False)
        for ox in (-4, 0, 4):
            put(px, fx + shift + ox, fy - 2, LEAF_SAGE[4])
        if not is_picked:
            draw_star_bloom(px, fx + shift - 2, fy - 4, BL_GOLD, size=1)
            if var_i >= 1:
                draw_star_bloom(px, fx + shift + 3, fy - 3, BL_GOLD, size=1)
        apply_tinted_outline(px, LEAF_SAGE[0], fy)

    # 5: silver_yarrow — Silber-Schafgarbe (ferny dark leaves + flat cream-lavender umbels)
    elif sp_idx == 5:
        shadow_ellipse(px, fx, fy + 0.5, 6.5, 2.3)
        draw_rosette(px, fx, fy, 6, 2, 6, LEAF_DEEP, seed, broad=False)
        stems = [(-4 + shift, 16 + var_i), (1, 19 + (var_i % 2)), (4, 14)]
        for sx, sh in stems[: 2 + (1 if var_i > 0 else 0)]:
            pts = draw_stem(px, fx + sx * 0.2, fy, fx + sx, fy - sh, sx * 0.2, LEAF_DEEP)
            for px_i, py_i in pts[3::3]:
                put(px, px_i - 1, py_i, LEAF_DEEP[3])
                put(px, px_i + 1, py_i, LEAF_DEEP[2])
            if not is_picked:
                draw_umbel(px, fx + sx, fy - sh - 1, 3 if sh >= 18 else 2, BL_CREAM, LEAF_DEEP)
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 6: way_chicory — Weg-Sternwarte (branching roadside stem + sky-cornflower ray blooms; Col 3 = afternoon closed!)
    elif sp_idx == 6:
        shadow_ellipse(px, fx, fy + 0.5, 5.8, 2.0)
        draw_rosette(px, fx, fy, 5, 2, 5, LEAF_MEADOW, seed, broad=False)
        pts = draw_stem(px, fx, fy, fx + shift, fy - 21 - var_i, -1.2 * shift, LEAF_SAGE)
        draw_stem(px, fx, fy - 8, fx + 4, fy - 16, 1.0, LEAF_SAGE)
        draw_stem(px, fx, fy - 12, fx - 4, fy - 19, -1.0, LEAF_SAGE)
        if not is_picked:
            bloom_pts = [(fx + shift, fy - 21 - var_i), (fx + 4, fy - 16), (fx - 4, fy - 19)]
            for bx, by in bloom_pts[: 2 + (1 if var_i != 0 else 0)]:
                if is_alt:  # Closed afternoon/night chicory buds!
                    put(px, bx, by, BL_CHICORY[1])
                    put(px, bx, by - 1, BL_CHICORY[2])
                else:
                    draw_star_bloom(px, bx, by, BL_CHICORY, size=2, center_col=BL_CHICORY[1])
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 7: wild_thyme — Steinthymian-Polster (aromatic woody cushion + rich violet flower candles)
    elif sp_idx == 7:
        shadow_ellipse(px, fx, fy + 0.5, 8.0, 2.6)
        for i in range(18):
            ang = i * 2.1 + seed
            r = math.sqrt(i / 18.0)
            put(px, fx + int(math.cos(ang) * 7.5 * r), fy - 1 + int(math.sin(ang) * 2.5 * r) - int((1 - r) * 3), LEAF_DEEP[3 if i % 2 == 0 else 2])
        spikes = [-5, -2, 1, 4, 6] if var_i == 2 else [-4, -1, 2, 5]
        for sx in spikes:
            h_sp = 9 + (( abs(sx) + var_i) % 4)
            draw_stem(px, fx + sx * 0.7, fy - 2, fx + sx, fy - h_sp, 0.0, LEAF_DEEP)
            if not is_picked:
                for ky in range(fy - h_sp - 2, fy - h_sp + 2):
                    put(px, fx + sx, ky, BL_VIOLET[3] if ky < fy - h_sp else BL_VIOLET[2])
                    if ky % 2 == 0:
                        put(px, fx + sx + 1, ky, BL_VIOLET[1])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 8: dew_campion — Taukehlchen (graceful arching stems + nodding lilac-blush bell calyces)
    elif sp_idx == 8:
        shadow_ellipse(px, fx, fy + 0.5, 5.5, 2.0)
        draw_rosette(px, fx, fy, 5, 2, 5, LEAF_MEADOW, seed, broad=False)
        bells = [(-5 + shift, 16), (3 + shift, 18 + var_i)]
        for bx_off, bh in bells:
            draw_stem(px, fx, fy, fx + bx_off, fy - bh + 2, bx_off * 0.45, LEAF_MEADOW)
            if not is_picked:
                cx_b, cy_b = fx + bx_off + (1 if bx_off > 0 else -1), fy - bh + 3
                put(px, cx_b, cy_b - 1, LEAF_DEEP[2])
                for ox in (-1, 0, 1):
                    put(px, cx_b + ox, cy_b, BL_LILAC[3] if ox <= 0 else BL_LILAC[2])
                    put(px, cx_b + ox, cy_b + 1, BL_BLUSH[3] if ox == 0 else BL_LILAC[1])
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 9: meadow_clock — Wisperstern (Col 0..1 = amber salsify flower, Col 2..3 = filigree silver dandelion puff-globe, Col 4 = bare head!)
    elif sp_idx == 9:
        shadow_ellipse(px, fx, fy + 0.5, 5.5, 2.0)
        draw_rosette(px, fx, fy, 6, 2, 6, LEAF_MEADOW, seed, broad=True)
        hx, hy = fx + shift, fy - 16 - (var_i % 2)
        draw_stem(px, fx, fy, hx, hy + 2, shift * 0.8, LEAF_MEADOW)
        if is_picked:
            # Bare silvery receptacle button after puff dispersal!
            put(px, hx, hy + 1, BL_CREAM[2])
            put(px, hx - 1, hy + 2, LEAF_MEADOW[2])
            put(px, hx + 1, hy + 2, LEAF_MEADOW[2])
        elif col in (2, 3):
            # Filigree radial silver-white dandelion clock (spoke & halo structure, zero checkerboard!)
            put(px, hx, hy, LEAF_WOOD[2])
            for ox, oy in (
                (-2, -2), (0, -3), (2, -2), (-3, 0), (3, 0), (-2, 2), (0, 3), (2, 2),
                (-1, -2), (1, -2), (-2, -1), (2, -1), (-1, 2), (1, 2),
                (-1, -1), (1, -1), (0, -1), (-1, 0), (1, 0), (0, 1),
            ):
                put(px, hx + ox, hy + oy, BL_CREAM[3] if ox + oy <= 0 else BL_CREAM[2])
        else:
            draw_star_bloom(px, hx, hy, BL_GOLD, size=3, center_col=BL_GOLD[1])
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 10: rune_saxifrage — Runen-Steinbrech (basal stone-rosette + nocturnal glowing turquoise-star panicle!)
    elif sp_idx == 10:
        shadow_ellipse(px, fx, fy + 0.5, 6.0, 2.2)
        draw_rosette(px, fx, fy - 1, 6, 3, 8, LEAF_SUCCULENT, seed, broad=True)
        if not is_picked:
            draw_stem(px, fx, fy - 2, fx + shift, fy - 18, 0.6, LEAF_WOOD)
            stars = [(fx + shift, fy - 19), (fx - 3 + shift, fy - 15), (fx + 3 + shift, fy - 14), (fx - 2, fy - 11)]
            for sx_p, sy_p in stars[: 3 + (var_i % 2)]:
                draw_star_bloom(px, sx_p, sy_p, BL_TEAL_DEW, size=1)
                put(glow, sx_p, sy_p, GLOW_TEAL_HI)
                put(glow, sx_p + 1, sy_p, GLOW_TEAL_LO)
        apply_tinted_outline(px, LEAF_SUCCULENT[0], fy)

    # 11: sentinel_mullein — Wächterkerze (tall 30px silver-woolly rosette + glowing amber flower torch!)
    elif sp_idx == 11:
        shadow_ellipse(px, fx, fy + 0.5, 8.5, 2.8)
        draw_rosette(px, fx, fy, 8, 3, 9, LEAF_SAGE, seed, broad=True)
        top_y = fy - 27 - var_i
        draw_stem(px, fx, fy - 1, fx + shift, top_y, shift * 0.5, LEAF_SAGE, thick=2)
        # Alternating woolly stem leaves
        draw_leaf_pair(px, fx, fy - 7, -5, -2, LEAF_SAGE, broad=True)
        draw_leaf_pair(px, fx + 1, fy - 10, 5, -2, LEAF_SAGE, broad=True)
        if not is_picked:
            for my in range(top_y, fy - 12):
                w_candle = 2 if my > top_y + 3 else 1
                for ox in range(-w_candle + 1, w_candle + 1):
                    bx = fx + shift + ox // 2
                    is_fl = (my + ox + seed) % 3 != 0
                    if is_fl:
                        put(px, bx, my, BL_GOLD[3] if ox <= 0 else BL_GOLD[2])
                        if (my + ox) % 2 == 0:
                            put(glow, bx, my, GLOW_GOLD_HI if my < top_y + 6 else GLOW_GOLD_LO)
                    else:
                        put(px, bx, my, LEAF_SAGE[2])
        apply_tinted_outline(px, LEAF_SAGE[0], fy)

    # 12: star_mantle — Sternen-Frauenmantel (pleated fan leaves holding a gleaming central Star-Dew pearl!)
    elif sp_idx == 12:
        shadow_ellipse(px, fx, fy + 0.5, 7.5, 2.5)
        cups = [(-4 + shift, fy - 5, 4), (3 + shift, fy - 4, 3), (0, fy - 8 - (var_i % 2), 4)]
        for cx_m, cy_m, r_m in cups:
            draw_stem(px, fx, fy, fx + cx_m, cy_m + 1, 0.0, LEAF_MEADOW)
            for oy in range(-r_m + 1, r_m):
                for ox in range(-r_m, r_m + 1):
                    if (ox / r_m) ** 2 + (oy / (r_m * 0.75)) ** 2 <= 1.0:
                        rib = (ox + oy) % 2 == 0
                        put(px, fx + cx_m + ox, cy_m + oy, LEAF_MEADOW[4 if (oy < 0 and rib) else (3 if rib else 2)])
            # Central Star-Dew pearl on Col 0..2 (absent when dry Col 3 or picked Col 4!)
            if not is_picked and not is_alt:
                put(px, fx + cx_m, cy_m, BL_TEAL_DEW[3])
                put(px, fx + cx_m + 1, cy_m, BL_TEAL_DEW[2])
                put(glow, fx + cx_m, cy_m, GLOW_TEAL_HI)
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 13: dusk_columbine — Nachtsporn (dark plum-violet spurred bells + nocturnal violet spore glow!)
    elif sp_idx == 13:
        shadow_ellipse(px, fx, fy + 0.5, 6.0, 2.2)
        draw_rosette(px, fx, fy, 6, 2, 6, LEAF_DEEP, seed, broad=True)
        spurs = [(-4 + shift, 18), (3 + shift, 20 + var_i)]
        for sx_c, sh_c in spurs:
            draw_stem(px, fx, fy, fx + sx_c, fy - sh_c, sx_c * 0.3, LEAF_WOOD)
            if not is_picked:
                bx, by = fx + sx_c, fy - sh_c + 2
                # Hooked upward nectar spurs + hanging plum bell + glowing stamen core!
                put(px, bx - 1, by - 2, BL_PLUM[2])
                put(px, bx + 1, by - 2, BL_PLUM[2])
                for ox in (-1, 0, 1):
                    put(px, bx + ox, by - 1, BL_PLUM[3] if ox <= 0 else BL_PLUM[2])
                    put(px, bx + ox, by, BL_PLUM[2] if ox == 0 else BL_PLUM[1])
                put(px, bx, by + 1, BL_LILAC[3])
                put(glow, bx, by + 1, GLOW_VIOLET_HI)
                put(glow, bx, by, GLOW_VIOLET_LO)
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 14: sanctuary_ivy — Heiligtums-Efeu (sprawling dark-emerald 5-lobed ivy runner across stone seams)
    elif sp_idx == 14:
        for t_i in range(16):
            tx = fx - 11 + t_i * 1.45
            ty = fy - 4 + math.sin(t_i * 0.55 + var_i) * 3.2
            ix, iy = int(round(tx)), int(round(ty))
            put(px, ix, iy, LEAF_WOOD[2])
            if t_i % 3 == 1:
                for ox, oy, tn in ((0, -1, 4), (-1, 0, 3), (0, 0, 3), (1, 0, 2), (0, 1, 1)):
                    put(px, ix + ox, iy + oy, LEAF_DEEP[tn])
        apply_tinted_outline(px, LEAF_DEEP[0], fy + 2)

    # 15: silver_clematis — Silber-Waldrebe (twining vine + connected creamy star blooms)
    elif sp_idx == 15:
        shadow_ellipse(px, fx, fy + 0.5, 7.5, 2.4)
        for arm in (-1, 1):
            pts = draw_stem(px, fx, fy, fx + arm * (7 + var_i), fy - 16, -arm * 2.5, LEAF_WOOD)
            for px_i, py_i in pts[2::3]:
                draw_leaf_pair(px, px_i, py_i, arm * 2, -1, LEAF_DEEP, broad=False)
        draw_stem(px, fx, fy - 4, fx + shift, fy - 17, 0.5, LEAF_DEEP)
        if not is_picked:
            for bx, by in ((fx - 5 + shift, fy - 13), (fx + 5, fy - 12), (fx + shift, fy - 17)):
                draw_stem(px, fx, by + 3, bx, by, 0.0, LEAF_DEEP)
                draw_star_bloom(px, bx, by, BL_CREAM, size=2, center_col=LEAF_SAGE[4])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 16: periwinkle_mat — Ruinen-Immergrün (glossy evergreen groundcover + violet-blue 5-star blooms)
    elif sp_idx == 16:
        shadow_ellipse(px, fx, fy + 0.5, 10.0, 2.8)
        for i in range(22):
            ang = i * 2.399 + seed * 0.3
            r = math.sqrt(i / 22.0)
            lx = fx + int(round(math.cos(ang) * 10.5 * r))
            ly = fy - 2 + int(round(math.sin(ang) * 3.6 * r)) - int((1.0 - r) * 2.5)
            draw_leaf_pair(px, lx, ly, 2 if i % 2 == 0 else -2, -1, LEAF_DEEP, broad=False)
        if not is_picked:
            for bx, by in ((-6 + shift, fy - 4), (1, fy - 7), (6, fy - 3)):
                draw_star_bloom(px, fx + bx, by, BL_VIOLET, size=2, center_col=BL_CREAM[3])
        apply_tinted_outline(px, LEAF_DEEP[0], fy + 1)

    # 17: wood_sorrel — Mond-Sauerklee (heart-clover + white bells; Col 3 = folded sleeping umbrella leaves!)
    elif sp_idx == 17:
        shadow_ellipse(px, fx, fy + 0.5, 7.0, 2.2)
        clovers = [(-5 + shift, fy - 5), (0, fy - 7), (5 + shift, fy - 4)]
        for cx_s, cy_s in clovers:
            draw_stem(px, fx + cx_s * 0.4, fy, fx + cx_s, cy_s, 0.0, LEAF_MEADOW)
            if is_alt:  # Nyctinastic sleeping folded umbrella leaves at night / heavy rain!
                for oy in range(0, 3):
                    put(px, fx + cx_s - 1, cy_s + oy, LEAF_MEADOW[2])
                    put(px, fx + cx_s + 1, cy_s + oy, LEAF_MEADOW[1])
            else:
                for ox, oy, tn in ((-2, 0, 4), (-1, -1, 4), (1, -1, 3), (2, 0, 2), (0, 1, 3)):
                    put(px, fx + cx_s + ox, cy_s + oy, LEAF_MEADOW[tn])
        if not is_picked and not is_alt:
            draw_stem(px, fx, fy - 2, fx + 2, fy - 11, 0.5, LEAF_WOOD)
            draw_star_bloom(px, fx + 2, fy - 11, BL_CREAM, size=1)
        apply_tinted_outline(px, LEAF_MEADOW[0], fy)

    # 18: shadow_arum — Schattenkelch (arrow leaves + pale spathe hood + glowing spadix!)
    elif sp_idx == 18:
        shadow_ellipse(px, fx, fy + 0.5, 7.0, 2.4)
        for lx_off, ly_h in ((-5, 11), (5, 10), (-2, 8)):
            draw_stem(px, fx, fy, fx + lx_off, fy - ly_h, lx_off * 0.2, LEAF_DEEP)
            draw_leaf_pair(px, fx + lx_off, fy - ly_h, -2, 3, LEAF_DEEP, broad=True)
            draw_leaf_pair(px, fx + lx_off, fy - ly_h, 2, 3, LEAF_DEEP, broad=True)
        if not is_picked:
            hx, hy = fx + shift, fy - 16 - var_i
            draw_stem(px, fx, fy, hx, hy + 4, 0.0, LEAF_DEEP)
            # Pale green-lilac hood spathe cupping a luminous violet-teal spadix!
            for oy in range(-4, 4):
                w_h = 2 if abs(oy) <= 2 else 1
                for ox in range(-w_h, w_h + 1):
                    put(px, hx + ox, hy + oy, LEAF_SAGE[4] if ox < 0 else LEAF_SAGE[3])
            for sy in range(hy - 2, hy + 2):
                put(px, hx, sy, BL_LILAC[3] if sy < hy else BL_PLUM[2])
                put(glow, hx, sy, GLOW_VIOLET_HI if sy == hy - 1 else GLOW_TEAL_LO)
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 19: ostrich_fern — Großer Trichterfarn (arching shuttlecock crown + central curled fiddleheads!)
    else:
        shadow_ellipse(px, fx, fy + 0.5, 9.0, 2.8)
        fronds_o = [(-10, -14), (-7, -20 - var_i), (-3, -22), (3, -22), (7, -19 - var_i), (10, -13)]
        for dx, dy in fronds_o:
            pts = draw_stem(px, fx + (1 if dx > 0 else -1), fy, fx + dx + shift, fy + dy, -dx * 0.35, LEAF_DEEP)
            for idx_p, (px_i, py_i) in enumerate(pts[2:-1]):
                rmp = LEAF_MEADOW if py_i < fy - 12 else LEAF_DEEP
                put(px, px_i - 1, py_i, rmp[4 if dx < 0 and idx_p > 3 else 3])
                put(px, px_i + 1, py_i, rmp[2])
        if not is_picked:
            # Young curled fiddleheads (`Bischofsstäbe`) nestled in the funnel heart!
            for f_off in (-1, 1):
                draw_stem(px, fx, fy - 1, fx + f_off, fy - 10, 0.0, LEAF_MEADOW)
                put(px, fx + f_off * 2, fy - 10, LEAF_MEADOW[4])
                put(px, fx + f_off * 2, fy - 9, LEAF_MEADOW[3])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    return px, glow


# ==============================================================================
# Tall Herbs & Shrubs Generator (8 rows x 5 cols, 56x52 px, foot at (28, 45))
# Cols: 0..1 = Bloom/Summer Variants, 2 = Fruit/Seed Variant, 3 = Picked, 4 = Pruned/Cut
# ==============================================================================

def populate_foliage_mass(
    px: list[list[tuple[int, int, int, int]]],
    blobs: list[tuple[float, float, float, float]],
    ramp: list[tuple[int, int, int, int]],
    seed: int,
) -> list[tuple[int, int]]:
    """Builds a crisp clustered pixel-art shrub canopy (NEVER noisy static!) and returns interior leaf coords."""
    mask = [[False] * LW for _ in range(LH)]
    for cx, cy, rx, ry in blobs:
        for y in range(max(2, int(cy - ry - 2)), min(LH - 2, int(cy + ry + 2))):
            for x in range(max(2, int(cx - rx - 2)), min(LW - 2, int(cx + rx + 2))):
                nx = (x - cx) / rx
                ny = (y - cy) / ry
                ang = math.atan2(ny, nx)
                scallop = 0.14 * math.sin(ang * 5.0 + seed) + 0.09 * math.cos(ang * 7.0 - seed * 0.7)
                if nx * nx + ny * ny <= (1.0 + scallop) ** 2:
                    mask[y][x] = True

    pts: list[tuple[int, int]] = []
    min_y = min((y for y in range(LH) for x in range(LW) if mask[y][x]), default=20)
    max_y = max((y for y in range(LH) for x in range(LW) if mask[y][x]), default=44)
    span_y = max(1.0, float(max_y - min_y))

    for y in range(1, LH - 1):
        for x in range(1, LW - 1):
            if not mask[y][x]:
                continue
            pts.append((x, y))
            up_o = not mask[y - 1][x]
            lf_o = not mask[y][x - 1]
            dn_o = not mask[y + 1][x]
            rt_o = not mask[y][x + 1]
            v = (y - min_y) / span_y
            cl = h2(x // 3, y // 2, seed + 41)
            if dn_o or rt_o:
                tone = 0 if dn_o and v > 0.72 else 1
            elif (up_o or lf_o) and v < 0.55:
                tone = 4 if cl > 0.35 else 3
            else:
                tone = 3 if (v < 0.42 and cl > 0.38) else (2 if v < 0.76 or cl > 0.45 else 1)
            px[y][x] = ramp[tone]
    return pts


def draw_large_species(
    sp_idx: int, col: int
) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(LW, LH)
    glow = make_grid(LW, LH)
    fx, fy = L_PIVOT_X, L_PIVOT_Y
    seed = 700 + sp_idx * 83 + col * 19
    is_fruit = (col == 2)
    is_picked = (col == 3)
    is_cut = (col == 4)
    shift = -1 if col == 0 else (1 if col == 1 else 0)

    if is_cut:
        shadow_ellipse(px, fx, fy + 0.5, 9.0, 2.8)
        is_shrub = sp_idx >= 4
        rmp = LEAF_WOOD if is_shrub else LEAF_DEEP
        for sx, sh in ((-6, 7), (-2, 9), (2, 8), (6, 6)):
            draw_stem(px, fx + sx * 0.4, fy, fx + sx, fy - sh, sx * 0.2, rmp, thick=2 if is_shrub else 1)
            put(px, fx + sx, fy - sh, LEAF_MEADOW[3])
        apply_tinted_outline(px, rmp[0], fy)
        return px, glow

    # 0: shadow_angelica — Schatten-Engelwurz (28x33 px airy tall compound umbel)
    if sp_idx == 0:
        shadow_ellipse(px, fx, fy + 0.5, 9.5, 2.8)
        draw_rosette(px, fx, fy - 1, 9, 3, 8, LEAF_DEEP, seed, broad=True)
        umbels = [(-7 + shift, 24), (0 + shift, 30), (7 + shift, 22)]
        for ux, uh in umbels:
            pts = draw_stem(px, fx + ux * 0.2, fy, fx + ux, fy - uh, ux * 0.18, LEAF_MEADOW, thick=1 if abs(ux) > 0 else 2)
            for px_i, py_i in pts[4::5]:
                draw_leaf_pair(px, px_i, py_i, -3 if ux <= 0 else 3, -2, LEAF_DEEP, broad=True)
            if not is_picked:
                bl = BL_GOLD if is_fruit else BL_CREAM
                draw_umbel(px, fx + ux, fy - uh - 1, 5 if uh >= 28 else 4, bl, LEAF_MEADOW)
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 1: wild_teasel — Silber-Weberkarde (22x31 px architectural spiny teasel heads + violet ring)
    elif sp_idx == 1:
        shadow_ellipse(px, fx, fy + 0.5, 8.0, 2.5)
        rmp = LEAF_SAGE if is_fruit else LEAF_MEADOW
        draw_rosette(px, fx, fy, 8, 3, 7, rmp, seed, broad=True)
        heads = [(0 + shift, 29), (-6 + shift, 21), (6 + shift, 20)]
        for hx_o, hh in heads[: 2 + (1 if col != 1 else 0)]:
            tx, ty = fx + hx_o, fy - hh
            draw_stem(px, fx + hx_o * 0.2, fy, tx, ty + 3, hx_o * 0.1, rmp)
            # Upcurved spiny calyx bracts beneath head!
            draw_leaf_pair(px, tx, ty + 3, -3, -4, rmp, broad=False)
            draw_leaf_pair(px, tx, ty + 3, 3, -4, rmp, broad=False)
            for oy in range(-3, 3):
                for ox in (-1, 0, 1):
                    if not is_picked and not is_fruit and oy in (-1, 0):
                        put(px, tx + ox, ty + oy, BL_LILAC[3 if ox <= 0 else 2])
                    else:
                        put(px, tx + ox, ty + oy, LEAF_WOOD[3 if ox <= 0 else 2])
        apply_tinted_outline(px, rmp[0], fy)

    # 2: nettle_clump — Ruinen-Nesselhorst (24x25 px dense serrated foliage + dead-nettle whorls)
    elif sp_idx == 2:
        shadow_ellipse(px, fx, fy + 0.5, 10.0, 3.0)
        stalks = [-7, -3, 1, 5, 8] if col != 1 else [-6, -2, 2, 6]
        for sx in stalks:
            sh = 18 + ((abs(sx) + col * 3) % 6)
            pts = draw_stem(px, fx + sx * 0.65, fy, fx + sx + shift, fy - sh, 0.0, LEAF_DEEP)
            for idx_p, (px_i, py_i) in enumerate(pts[3::4]):
                draw_leaf_pair(px, px_i, py_i, -3, 1, LEAF_DEEP, broad=True)
                draw_leaf_pair(px, px_i, py_i, 3, 1, LEAF_MEADOW, broad=True)
                if not is_picked and idx_p >= 1:
                    bl = BL_PLUM if is_fruit else BL_CREAM
                    put(px, px_i - 1, py_i - 1, bl[3])
                    put(px, px_i + 1, py_i - 1, bl[2])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 3: meadowsweet — Wiesenkönigin (24x29 px reddish stems + foamy cream blossom plumes)
    elif sp_idx == 3:
        shadow_ellipse(px, fx, fy + 0.5, 8.5, 2.6)
        draw_rosette(px, fx, fy, 8, 3, 7, LEAF_DEEP, seed, broad=True)
        plumes = [(-5 + shift, 22), (1 + shift, 26), (6, 20)]
        for px_o, ph in plumes:
            pts = draw_stem(px, fx + px_o * 0.25, fy, fx + px_o, fy - ph, px_o * 0.2, LEAF_WOOD)
            for px_i, py_i in pts[3::4]:
                draw_leaf_pair(px, px_i, py_i, -3, 0, LEAF_MEADOW, broad=False)
                draw_leaf_pair(px, px_i, py_i, 3, 0, LEAF_DEEP, broad=False)
            if not is_picked:
                cx_p, cy_p = fx + px_o, fy - ph - 2
                # Clustered foamy blossom cloud (zero diagonal stripes!)
                for bx_c, by_c, rad_c in ((cx_p, cy_p, 2.6), (cx_p - 2, cy_p + 1, 1.9), (cx_p + 2, cy_p + 1, 1.9)):
                    for oy in range(-3, 4):
                        for ox in range(-3, 4):
                            if ox * ox + oy * oy <= rad_c * rad_c:
                                tone_c = 3 if (ox + oy <= 0) else (2 if oy <= 1 else 1)
                                put(px, bx_c + ox, by_c + oy, BL_CREAM[tone_c])
        apply_tinted_outline(px, LEAF_DEEP[0], fy)

    # 4: wild_rose_briar — Dämmer-Heckenrose (38x34 px arching wild rose shrub / ruby rosehips!)
    elif sp_idx == 4:
        shadow_ellipse(px, fx, fy + 1.0, 15.0, 4.0)
        for cane_x, cane_y in ((-14, -20), (-6, -28), (6, -29), (15, -19)):
            draw_stem(px, fx + cane_x * 0.2, fy, fx + cane_x, fy + cane_y, cane_x * 0.35, LEAF_WOOD, thick=2)
        blobs = [
            (fx - 9 + shift, fy - 15, 9.5, 7.5),
            (fx + shift, fy - 21, 10.5, 8.5),
            (fx + 9 + shift, fy - 14, 9.5, 7.5),
            (fx, fy - 9, 13.0, 6.5),
        ]
        populate_foliage_mass(px, blobs, LEAF_MEADOW, seed)
        if not is_picked:
            spots = [(-11, -17), (-5, -24), (3, -25), (10, -18), (-3, -12), (6, -11)]
            for bx, by in spots:
                if is_fruit:
                    # Bright carmine-ruby rosehips!
                    put(px, fx + shift + bx, fy + by, FR_ROSEHIP[3])
                    put(px, fx + shift + bx + 1, fy + by + 1, FR_ROSEHIP[2])
                    put(px, fx + shift + bx, fy + by + 1, FR_ROSEHIP[1])
                else:
                    draw_star_bloom(px, fx + shift + bx, fy + by, BL_BLUSH, size=2, center_col=BL_GOLD[3])

    # 5: elderberry_shrub — Glimm-Holunder (44x42 px gnarled woody elder shrub: cream plates / dark berry clusters!)
    elif sp_idx == 5:
        shadow_ellipse(px, fx, fy + 1.0, 17.5, 4.5)
        # Gnarled visible multi-stem woody trunk base!
        for tx_o in (-5, 0, 5):
            draw_stem(px, fx + tx_o * 0.5, fy, fx + tx_o * 1.6, fy - 18, tx_o * 0.4, LEAF_WOOD, thick=2)
        blobs = [
            (fx - 12 + shift, fy - 20, 10.5, 8.5),
            (fx + shift, fy - 28, 12.5, 9.5),
            (fx + 12 + shift, fy - 19, 10.5, 8.5),
            (fx - 5, fy - 14, 11.0, 7.0),
            (fx + 6, fy - 14, 11.0, 7.0),
        ]
        populate_foliage_mass(px, blobs, LEAF_DEEP, seed)
        if not is_picked:
            umbel_pts = [(-13, -23), (-4, -32), (6, -30), (14, -22), (-6, -16), (7, -15)]
            for ux, uy in umbel_pts:
                cx_u, cy_u = fx + shift + ux, fy + uy
                if is_fruit:
                    # Heavy drooping plum-violet elderberry clusters on reddish stalks!
                    put(px, cx_u, cy_u - 1, FR_ROSEHIP[2])
                    for ox, oy, tn in ((-1, 0, 3), (1, 0, 2), (0, 1, 3), (-1, 2, 2), (1, 2, 1), (0, 3, 2)):
                        put(px, cx_u + ox, cy_u + oy, FR_ELDER[tn])
                else:
                    draw_umbel(px, cx_u, cy_u, 3, BL_CREAM, LEAF_MEADOW)
                    put(glow, cx_u, cy_u, GLOW_GOLD_LO)

    # 6: hawthorn_bush — Altdorn-Heckenbusch (36x31 px dense twisted hedgerow bush: May blossoms / blue sloes)
    elif sp_idx == 6:
        shadow_ellipse(px, fx, fy + 1.0, 15.0, 4.0)
        draw_stem(px, fx - 2, fy, fx - 4, fy - 14, -1.5, LEAF_WOOD, thick=2)
        draw_stem(px, fx + 2, fy, fx + 5, fy - 14, 1.5, LEAF_WOOD, thick=2)
        blobs = [
            (fx - 9 + shift, fy - 13, 9.5, 7.5),
            (fx + 1 + shift, fy - 19, 11.0, 8.5),
            (fx + 10 + shift, fy - 12, 9.0, 7.0),
        ]
        populate_foliage_mass(px, blobs, LEAF_DEEP, seed)
        if not is_picked:
            pts_h = [(-10, -15), (-3, -22), (4, -20), (10, -14), (0, -11), (-6, -9)]
            for bx, by in pts_h:
                if is_fruit:
                    put(px, fx + shift + bx, fy + by, FR_SLOE[3])
                    put(px, fx + shift + bx + 1, fy + by, FR_SLOE[2])
                    put(px, fx + shift + bx, fy + by + 1, FR_SLOE[1])
                else:
                    draw_star_bloom(px, fx + shift + bx, fy + by, BL_CREAM, size=1)
                    draw_star_bloom(px, fx + shift + bx + 2, fy + by + 1, BL_CREAM, size=1)

    # 7: bramble_thicket — Dornenbrombeer-Geflecht (40x27 px sprawling arched blackberry bramble)
    else:
        shadow_ellipse(px, fx, fy + 1.0, 17.5, 4.0)
        blobs = [
            (fx - 11 + shift, fy - 9, 10.0, 6.5),
            (fx + shift, fy - 13, 11.5, 8.0),
            (fx + 11 + shift, fy - 8, 10.0, 6.5),
        ]
        populate_foliage_mass(px, blobs, LEAF_DEEP, seed)
        # Arching reddish thorny canes looping over the thicket!
        draw_stem(px, fx - 15, fy - 2, fx + 4, fy - 18, -4.0, LEAF_WOOD)
        draw_stem(px, fx + 15, fy - 2, fx - 4, fy - 17, 4.0, LEAF_WOOD)
        if not is_picked:
            b_spots = [(-12, -10), (-5, -16), (3, -17), (11, -10), (-2, -8), (6, -7)]
            for bx, by in b_spots:
                cx_b, cy_b = fx + shift + bx, fy + by
                if is_fruit:
                    for ox, oy, tn in ((0, 0, 3), (1, 0, 2), (0, 1, 2), (1, 1, 1), (-1, 1, 3)):
                        put(px, cx_b + ox, cy_b + oy, FR_BRAMBLE[tn])
                else:
                    draw_star_bloom(px, cx_b, cy_b, BL_LILAC, size=2, center_col=BL_CREAM[3])

    return px, glow


def scale_nearest(grid: list[list[tuple[int, int, int, int]]], factor: int) -> list[list[tuple[int, int, int, int]]]:
    out: list[list[tuple[int, int, int, int]]] = []
    for row in grid:
        scaled_row: list[tuple[int, int, int, int]] = []
        for p in row:
            scaled_row.extend([p] * factor)
        for _ in range(factor):
            out.append(list(scaled_row))
    return out


def build_qa_sheet(
    sheet: list[list[tuple[int, int, int, int]]],
    glow_sheet: list[list[tuple[int, int, int, int]]],
    cw: int,
    ch: int,
    cols: int,
    rows: int,
) -> list[list[tuple[int, int, int, int]]]:
    pad = 2
    total_cols = cols + 1  # Extra right-hand column showing twilight/night render with glow!
    w = total_cols * (cw + pad) + pad
    h = rows * (ch + pad) + pad
    bg_day = hexc("3e7d56")
    bg_night = hexc("141d29")
    out = [[bg_day] * w for _ in range(h)]
    nx0 = cols * (cw + pad) + pad
    for y in range(h):
        for x in range(nx0 - 1, w):
            out[y][x] = bg_night

    for r in range(rows):
        gy = pad + r * (ch + pad)
        for c in range(cols):
            gx = pad + c * (cw + pad)
            for y in range(ch):
                for x in range(cw):
                    out[gy + y][gx + x] = blend_over(out[gy + y][gx + x], sheet[r * ch + y][c * cw + x])
        # Night column uses Col 1!
        gx_n = pad + cols * (cw + pad)
        for y in range(ch):
            for x in range(cw):
                p = sheet[r * ch + y][1 * cw + x]
                if p[3]:
                    dim = (int(p[0] * 0.42), int(p[1] * 0.48), int(p[2] * 0.66), p[3])
                    out[gy + y][gx_n + x] = blend_over(out[gy + y][gx_n + x], dim)
                g = glow_sheet[r * ch + y][1 * cw + x]
                if g[3]:
                    out[gy + y][gx_n + x] = blend_over(out[gy + y][gx_n + x], g)
    return out


def main() -> None:
    small_sheet = make_grid(SW * S_COLS, SH * S_ROWS)
    small_glow = make_grid(SW * S_COLS, SH * S_ROWS)
    for r in range(S_ROWS):
        for c in range(S_COLS):
            sp, sg = draw_small_species(r, c)
            ox, oy = c * SW, r * SH
            for y in range(SH):
                for x in range(SW):
                    small_sheet[oy + y][ox + x] = sp[y][x]
                    small_glow[oy + y][ox + x] = sg[y][x]

    large_sheet = make_grid(LW * L_COLS, LH * L_ROWS)
    large_glow = make_grid(LW * L_COLS, LH * L_ROWS)
    for r in range(L_ROWS):
        for c in range(L_COLS):
            lp, lg = draw_large_species(r, c)
            ox, oy = c * LW, r * LH
            for y in range(LH):
                for x in range(LW):
                    large_sheet[oy + y][ox + x] = lp[y][x]
                    large_glow[oy + y][ox + x] = lg[y][x]

    props_dir = PROJ_ROOT / "assets" / "props"
    save_grid(props_dir / "flora_sanctuary_small.png", small_sheet)
    save_grid(props_dir / "flora_sanctuary_small_glow.png", small_glow)
    save_grid(props_dir / "flora_sanctuary_large.png", large_sheet)
    save_grid(props_dir / "flora_sanctuary_large_glow.png", large_glow)

    img_dir = PROJ_ROOT / "docs" / "img"
    qa_s = scale_nearest(build_qa_sheet(small_sheet, small_glow, SW, SH, S_COLS, S_ROWS), 3)
    qa_l = scale_nearest(build_qa_sheet(large_sheet, large_glow, LW, LH, L_COLS, L_ROWS), 3)
    save_grid(img_dir / "flora_sanctuary_small_3x.png", qa_s)
    save_grid(img_dir / "flora_sanctuary_large_3x.png", qa_l)
    print("Generated all 28 LivingFlora 2.0 species (small 20x6 + large 8x5) & 3x QA sheets!")


if __name__ == "__main__":
    main()
