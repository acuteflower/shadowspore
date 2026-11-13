#!/usr/bin/env python3
"""Procedural desert pixel art & item icons for Sonnenquarz-Öde (stdlib only), matching Shadowspore's
3/4 top-left lighting, cel + Bayer dithering, indigo/plum deep shadows and adaptive 1px ink outlines:

  assets/props/crown_cactus.png         5 cols x 6 rows of 112x200 (feet 56, 196):
                                        0 trunk, 1 crown (with figs), 2 crown glow, 3 trunk glow,
                                        4 crown picked, 5 crown picked glow
  assets/props/crown_cactus_growth.png  5 cols x 1 row of 112x200 (small stump, large stump, sprout, young, pad)
  assets/props/prickly_pear.png         5 cols x 2 rows of 40x34 (feet 20, 31) + _glow + _stripped
  assets/props/barrel_cactus.png        4 cols x 1 row  of 40x34 + _glow + _stripped
  assets/props/desert_scrub.png         6 cols x 1 row  of 40x34 + _glow + _stripped
  assets/props/tumble_scrub.png         4 cols x 1 row  of 40x34 + _glow + _stripped
  assets/props/dune_grass.png           5 cols x 1 row  of 40x34 + _glow + _stripped
  assets/props/glass_aloe.png           4 cols x 2 rows of 40x34 + _glow
  assets/props/night_cactus.png         4 cols x 3 rows of 40x34 (0 night open, 1 day closed, 2 picked) + _glow
  assets/props/sand_tuber.png           4 cols x 2 rows of 40x34 (0 in sand, 1 pulled sand crater) + _glow
  assets/props/sun_palm.png             6 cols x 6 rows of 112x200 (feet 56, 196)
  assets/props/sun_palm_growth.png      6 cols x 1 row  of 112x200
  assets/props/oasis_reed.png           5 cols x 1 row  of 40x34 + _glow + _stripped
  assets/props/oasis_lily.png           4 cols x 2 rows of 40x34 + _glow
  assets/props/sun_quartz_rock.png      6 cols x 4 rows of 64x56 + _glow

  assets/items/{sun_fig,crown_fig,cactus_wood,cactus_pulp,quartz_aloe,night_cactus_bloom,sand_tuber,palm_wood,sun_date,oasis_blossom,sun_quartz}.png

Run:
  python3 tools/art_desert.py
  python3 tools/art_desert.py preview   -> also writes docs/img/desert_flora.png & previews_oasis/oasis_sprites.png
"""
import math
import pathlib
import random
import shutil
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_flora as F  # noqa: E402
import art_stone as S  # noqa: E402
import art_tree  # noqa: E402
from art_brush import Glow, outline, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, check_icon, clamp, put_shadow, stroke  # noqa: E402
from art_spruce import CH, CW, FEET_X, FEET_Y, grid  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402


def ramp(*c):
    return [hexc(x) for x in c]


# Palettes harmonized with warm desert ochre sand & cool white-turquoise sun-quartz
CACTUS = ramp("17222c", "233c3b", "345a4f", "4e7e67", "74a685", "a4cca8")
CACTUS_RIM = hexc("8cc8b8")
SPINE = ramp("a89c88", "e8dec0", "faf4e2")
FIG = ramp("6e182c", "b82c42", "f26444", "ffb852", "fff0a8")
FIG_GLOW, FIG_HOT = hexc("ff9a42"), hexc("ffe898")
PULP = ramp("3e5c4c", "6c9874", "a6cc98", "dcf0c4")

CINNAMON = ramp("241824", "4a3034", "785042", "a87c5c")
PALM_BARK = ramp("241620", "4a2e32", "72483c", "9e6b48", "c8945e", "eab87c")
PALM_LEAF = ramp("163434", "245242", "347850", "4fa05e", "7cc66e", "b2e48c")
PALM_DEW = hexc("88f2e4")
DATE_RAMP = ramp("5a2614", "9e481e", "dc7e2a", "ffb84a", "ffea96")
DATE_GLOW, DATE_HOT = hexc("ffbe48"), hexc("fff0aa")

REED_CULM = ramp("183834", "2a5e50", "428a6c", "6ab688", "9ae0a4")
REED_TIP = ramp("4eb8b4", "8af2ec", "e8ffff")
LILY_LEAF = ramp("14322e", "225848", "368060", "56ac76", "84d48e")
LILY_PETAL = ramp("2c8084", "4eb8b8", "84e6e2", "c8fcf8", "ffffff")
LILY_GOLD = ramp("d8902c", "ffd86b", "fff6ba")

SANDSTONE = ramp("261824", "462b30", "6e4438", "9a6644", "c69258", "ebd6a0")
DESERT_ROCK = ramp("2c1d28", "4c3134", "754b3c", "a46f4a", "cea06a", "f0d49c")
DESERT_RIM = ramp("7e5a4c", "d8ae78")
QUARTZ_CRYSTAL = ramp("344868", "527494", "7eb4cc", "b8ecf4", "e8ffff", "ffffff")
QUARTZ_GOLD = hexc("ffe69c")

SCRUB_SAGE = ramp("2c3228", "4a5236", "747848", "a29c5e", "cbc07e")
SCRUB_TEAL = ramp("263434", "3e584e", "5e7e68", "88a888", "b4ceb0")

TUMBLE = ramp("302028", "5c4438", "967450", "c8a46e", "ead09a")
DUNE = ramp("3a382c", "686240", "a29054", "d2b86e", "f0deb0")
PLUME_D = ramp("968256", "c8b47c", "f2e4ba")

ALOE = ramp("1c3244", "2e5c68", "56989c", "94d6d2", "d6f6f4", "ffffff")
ALOE_GLOW, ALOE_HOT = hexc("7ee6e0"), hexc("eeffff")

CEREUS = ramp("141828", "24303e", "385058", "587874", "84a498")
NIGHT_PETAL = ramp("5a4c8e", "8e80c8", "c4b8f4", "f0ecff", "ffffff")
NIGHT_BUD = ramp("2c263c", "4a445e", "746e8a", "a8a2bc")
NIGHT_GLOW, NIGHT_HOT = hexc("b8a8ff"), hexc("fff4c8")
GOLD_STAMEN = hexc("ffd870")

TUBER_SKIN = ramp("4a2824", "844c32", "bf7c44", "ecb266", "fae09a")
SAND_MOUND = ramp("5c3c2e", "8f603e", "be8c50", "e4ba6e")
SAND_GLINT = hexc("ffc466")

DRY_OUT = hexc("221826")
SAGE_OUT = hexc("182226")
QUARTZ_OUT = hexc("1c2838")
ICON_OUT = hexc("1b1a2e")


def desert_outline(px, tint=None):
    """Adaptive 1px warm-indigo/slate dark outline preserving crisp contrast on sand."""
    outline(px)
    if tint is None:
        return
    # Replace pure top-edge cool ink with softly matched desert ink where appropriate
    for y in range(FH):
        for x in range(FW):
            if px[y][x] == hexc("16182e"):
                px[y][x] = tint


def finish_desert(px, spread, seed, rim_colors=(), outline_tint=None):
    """Adds right-side rim accent (if applicable), contact shadow, and 1px outline."""
    if rim_colors:
        for y in range(FH):
            for x in range(1, FW - 1):
                c = px[y][x]
                if c[3] == 255 and c in rim_colors and px[y][x + 1][3] == 0 and noise(x, y, seed + 5) > 108:
                    px[y][x] = CACTUS_RIM
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, min(16, spread + 2), 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    desert_outline(base, outline_tint)
    return base


def gput(g, x, y, c, over=True):
    if 2 <= x < CW - 2 and 2 <= y < CH and (over or g[y][x] is None):
        g[y][x] = c


# ================================================================== 1. Kronen-Säulenkaktus (112x200 x 5 cols x 6 rows)
SAGUAROS = [
    {"h": 54, "clear": 20, "trunk_hw": 4.0, "arms": [(1, 0.56, 7, 13)], "figs": 2},
    {"h": 68, "clear": 24, "trunk_hw": 4.8, "arms": [(-1, 0.52, 10, 17)], "figs": 3},
    {"h": 82, "clear": 28, "trunk_hw": 5.3, "arms": [(-1, 0.48, 11, 20), (1, 0.62, 10, 17)], "figs": 4},
    {"h": 96, "clear": 32, "trunk_hw": 6.0, "arms": [(1, 0.44, 13, 24), (-1, 0.58, 12, 22), (1, 0.72, 8, 13)], "figs": 5},
    {"h": 112, "clear": 36, "trunk_hw": 6.6, "arms": [(-1, 0.42, 14, 28), (1, 0.54, 13, 25), (-1, 0.68, 9, 17)], "figs": 6},
]


def _cactus_rib_shade(dx, hw, y, seed, pal=CACTUS):
    """Vertical cylindrical cactus ribs + top-left sunlight + Bayer dither."""
    u = dx / max(hw, 1.0)
    z = math.sqrt(max(0.0, 1.0 - u * u))
    rib = math.cos(u * math.pi * 2.5) * 0.22
    lit = 0.48 - 0.52 * u + 0.20 * z + rib + (noise(int(dx + 20), y // 3, seed) / 255.0 - 0.5) * 0.16
    idx = int(clamp(lit * (len(pal) - 0.25) + (BAYER[y % 4][int(dx + 50) % 4] / 16.0 - 0.5) * 0.48, 0, len(pal) - 1))
    return pal[idx]


def _draw_saguaro_column(grid_t, grid_c, clear_y, x_center, y_top, y_bot, hw_top, hw_bot, seed, draw_crown_cap=True):
    for y in range(int(round(y_top)), int(round(y_bot)) + 1):
        t = (y - y_top) / max(y_bot - y_top, 1.0)
        hw = hw_top + (hw_bot - hw_top) * t
        if draw_crown_cap and y < y_top + hw_top * 0.9:
            cap_t = max(0.0, 1.0 - (y - y_top) / max(hw_top * 0.9, 1.0))
            hw *= math.sqrt(max(0.0, 1.0 - cap_t * cap_t * 0.85))
        ihw = int(math.floor(hw + 0.25))
        target = grid_t if y >= clear_y else grid_c
        for dx in range(-ihw, ihw + 1):
            c = _cactus_rib_shade(dx, max(hw, 1.2), y, seed)
            if y > FEET_Y - 5:  # woody weathered desert collar at base
                if abs(dx) < hw * 0.85 and (y > FEET_Y - 2 or noise(int(x_center + dx), y, seed + 19) > 135):
                    c = CINNAMON[1 if dx > 0 else 2]
            gput(target, int(round(x_center)) + dx, y, c)
        # tiny spine clusters along vertical ribs every 5 pixels
        if y > y_top + 3 and y < y_bot - 4 and y % 5 == 0 and hw >= 2.6:
            for rx in (-0.65, 0.0, 0.65):
                sx = int(round(x_center + rx * hw))
                gput(target, sx, y, SPINE[2 if rx <= 0 else 1])


def _draw_saguaro_arm(grid_t, grid_c, clear_y, x0, y0, side, reach, rise, arm_hw, seed):
    """Curved elbow arm bending outward and upward."""
    pts = bezier(
        (x0, y0),
        (x0 + side * reach * 0.88, y0 + 1.5),
        (x0 + side * reach, y0 - rise * 0.22),
        (x0 + side * reach, y0 - rise),
        n=max(16, int((reach + rise) * 2)),
    )
    for i, (px, py) in enumerate(pts):
        t = i / max(len(pts) - 1, 1)
        r = arm_hw * (0.85 + 0.15 * math.sin(t * math.pi * 0.6))
        if t > 0.86:
            r *= math.sqrt(max(0.08, 1.0 - ((t - 0.86) / 0.14) ** 2))
        for dy in range(-int(r) - 1, int(r) + 2):
            for dx in range(-int(r) - 1, int(r) + 2):
                d = math.hypot(dx, dy)
                if d <= r:
                    xx, yy = int(round(px + dx)), int(round(py + dy))
                    target = grid_t if yy >= clear_y else grid_c
                    lit = (-dx * 0.55 - dy * 0.75) / max(r, 0.8) + 0.45
                    rib = 0.16 * math.cos((dx / max(r, 0.8)) * math.pi * 2.0)
                    c = CACTUS[int(clamp((lit + rib) * 5.2, 0, 5))]
                    gput(target, xx, yy, c)
    # Spine accents up the vertical section of the arm
    for i in range(4, len(pts) - 2, 7):
        px, py = int(round(pts[i][0])), int(round(pts[i][1]))
        target = grid_t if py >= clear_y else grid_c
        gput(target, px + side, py, SPINE[1])
    return (int(round(pts[-1][0])), int(round(pts[-1][1])))


def _draw_crown_fig(grid_c, glow_c, cx, cy, small=False):
    rx, ry = (2.0, 2.2) if small else (2.6, 2.8)
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            d = (dx / rx) ** 2 + (dy / ry) ** 2
            if d <= 1.0:
                lit = 0.55 - 0.38 * dx / rx - 0.42 * dy / ry
                c = FIG[int(clamp(lit * 4.5, 0, 4))]
                gput(grid_c, cx + dx, cy + dy, c)
    gput(grid_c, cx - 1, cy - 1, FIG[4])
    gput(glow_c, cx, cy, FIG_HOT)
    gput(glow_c, cx - 1, cy - 1, FIG_HOT)
    gput(glow_c, cx + 1, cy, FIG_GLOW)


def build_crown_cactus(idx, spec, picked=False):
    trunk, crown = grid(), grid()
    glow_c, glow_t = grid(), grid()
    clear_y = FEET_Y - spec["clear"]
    top_y = FEET_Y - spec["h"]
    seed = 4100 + idx * 37
    # Main trunk + upper column
    _draw_saguaro_column(trunk, crown, clear_y, FEET_X, top_y, FEET_Y, spec["trunk_hw"] * 0.86, spec["trunk_hw"], seed)
    tips = [(FEET_X, top_y)]
    for side, frac, reach, rise in spec["arms"]:
        ay = int(round(FEET_Y - spec["h"] * frac))
        if ay >= clear_y - 4:
            ay = clear_y - 6
        x0 = FEET_X + side * (spec["trunk_hw"] * 0.72)
        tip = _draw_saguaro_arm(trunk, crown, clear_y, x0, ay, side, reach, rise, max(2.2, spec["trunk_hw"] * 0.56), seed + int(frac * 100))
        tips.append(tip)
    if not picked:
        # Place coral-gold crown figs around main apex & arm tops
        placements = [
            (tips[0][0] - 2, tips[0][1] - 1, False),
            (tips[0][0] + 2, tips[0][1], True),
        ]
        for tip_idx in range(1, len(tips)):
            tx, ty = tips[tip_idx]
            placements.append((tx, ty - 1, tip_idx > 1))
        if len(tips) >= 3:
            placements.append((tips[0][0], tips[0][1] - 3, True))
        for px, py, small in placements[: spec["figs"]]:
            _draw_crown_fig(crown, glow_c, px, py, small=small)
    # Soft glow halo around emitted fig pixels
    glow_src = [[glow_c[y][x] for x in range(CW)] for y in range(CH)]
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            if glow_src[y][x] is not None:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if (dx or dy) and glow_c[y + dy][x + dx] is None:
                            glow_c[y + dy][x + dx] = (*FIG_GLOW[:3], 92)
    t_out, c_out = art_tree.finish(trunk, crown, spec["trunk_hw"] + 6.5)
    return t_out, c_out, art_tree.to_pixels(glow_c), art_tree.to_pixels(glow_t)


def build_cactus_growth():
    frames = []
    # 0: small cut cactus stump, 1: large cut cactus stump
    for r in (4.5, 7.0):
        t = grid()
        top_y = FEET_Y - int(r * 1.45)
        for y in range(top_y, FEET_Y + 2):
            for dx in range(-int(r) - 1, int(r) + 2):
                hw = r + max(0.0, (y - (FEET_Y - 3)) * 0.4)
                if abs(dx) <= hw:
                    if y < top_y + 3 and ((dx / (r + 0.2)) ** 2 + ((y - top_y) / (r * 0.42)) ** 2) <= 1.0:
                        d = math.sqrt((dx / (r + 0.2)) ** 2 + ((y - top_y) / (r * 0.42)) ** 2)
                        c = PULP[3] if d < 0.28 else (PULP[2] if d < 0.72 else CACTUS[3])
                    else:
                        c = _cactus_rib_shade(dx, hw, y, 4200 + int(r))
                    gput(t, FEET_X + dx, y, c)
        t_out, _ = art_tree.finish(t, grid(), r + 5.0)
        frames.append(t_out)
    # 2: baby globose sprout, 3: young unbranched ribbed column
    for h, hw, sd in ((16, 3.6, 4210), (36, 4.2, 4220)):
        t = grid()
        _draw_saguaro_column(t, t, FEET_Y - h - 5, FEET_X, FEET_Y - h, FEET_Y, hw * 0.85, hw, sd)
        t_out, _ = art_tree.finish(t, grid(), hw + 5.0)
        frames.append(t_out)
    frames.append(frames[-1])  # pad to 5 columns (like birch_growth)
    out = [[CLEAR] * (CW * 5) for _ in range(CH)]
    for i, f in enumerate(frames):
        for y in range(CH):
            out[y][i * CW : (i + 1) * CW] = f[y]
    return out


# ================================================================== 1b. Sonnenpalme (112x200 x 6 cols x 6 rows + growth)
SUN_PALMS = [
    {"stems": [(0, 54, 7.0, -3.0, 2.5)], "fronds": 9, "flen": 27, "dates": 2, "clear": 24},
    {"stems": [(0, 84, 14.0, -5.0, 2.8)], "fronds": 9, "flen": 31, "dates": 2, "clear": 42},
    {"stems": [(-3, 94, -14.5, -3.0, 2.6), (3, 66, 15.0, 2.5, 2.2)], "fronds": 9, "flen": 29, "dates": 3, "clear": 36},
    {"stems": [(0, 112, -14.0, 8.5, 3.0)], "fronds": 10, "flen": 34, "dates": 3, "clear": 58},
    {"stems": [(0, 122, 8.5, -4.0, 3.4)], "fronds": 12, "flen": 37, "dates": 4, "clear": 64},
    {"stems": [(0, 134, 10.5, -5.5, 3.3), (-4, 82, -14.5, -2.5, 2.4), (4, 44, 11.0, 1.5, 1.9)], "fronds": 11, "flen": 35, "dates": 4, "clear": 34},
]


def _draw_palm_stem(grid_t, grid_c, clear_y, bx, height, curve_end, s_mid, base_r, seed, top_frac=1.0):
    """Curved ringed desert palm trunk with criss-cross diamond leaf-scar bark."""
    top_y = FEET_Y - height * top_frac
    p0 = (FEET_X + bx, FEET_Y + 0.5)
    p1 = (FEET_X + bx + curve_end * 0.25 + s_mid, FEET_Y - height * 0.42 * top_frac)
    p2 = (FEET_X + bx + curve_end * top_frac, top_y)
    pts = bezier(p0, p1, p2, n=max(24, int(height * 1.8)))
    for i, (px, py) in enumerate(pts):
        t = i / max(len(pts) - 1, 1)
        flare = max(0.0, (0.14 - t) / 0.14) * 1.3
        r = base_r * (1.0 - 0.44 * t) + flare
        ring_band = abs(math.sin((FEET_Y - py) * 0.95)) < 0.34
        target = grid_t if py >= clear_y else grid_c
        for dy in range(-int(r) - 1, int(r) + 2):
            for dx in range(-int(r) - 1, int(r) + 2):
                if dx * dx + dy * dy <= r * r:
                    u = dx / max(r, 0.8)
                    lit = 0.52 - 0.46 * u + (0.12 if ring_band else -0.05) + (noise(int(px + dx), int(py + dy), seed) / 255.0 - 0.5) * 0.14
                    if y_ring := (abs(dx) < r * 0.72 and int(FEET_Y - py) % 4 == 0):
                        lit -= 0.08
                    c = PALM_BARK[int(clamp(lit * 5.2, 0, 5))]
                    gput(target, int(round(px + dx)), int(round(py + dy)), c)
    return pts[-1]


def _draw_feather_frond(grid_c, glow_c, ox, oy, angle, length, droop, seed, dry=False):
    """Graceful arching pinnate frond with individual leaflets."""
    steps = max(18, int(length * 1.25))
    ca, sa = math.cos(angle), math.sin(angle)
    p0 = (ox, oy)
    p1 = (ox + ca * length * 0.55, oy + sa * length * 0.44 - (2.0 if dry else 6.5))
    p2 = (ox + ca * length, oy + sa * length * 0.80 + droop)
    spine = bezier(p0, p1, p2, n=steps)
    ramp_c = DATE_RAMP if dry else PALM_LEAF
    for i, (sx, sy) in enumerate(spine):
        t = i / max(steps - 1, 1)
        rib_col = ramp_c[1 if dry else (2 if t < 0.5 else 3)]
        gput(grid_c, int(round(sx)), int(round(sy)), rib_col)
        if i % 2 == 0 and t > 0.10 and t < 0.96:
            llen = math.sin(t * math.pi) * (3.6 if dry else 7.6) + 1.4
            nx, ny = -sa * 0.55, abs(ca) * 0.65 + 0.55
            for side in (-1, 1):
                for d in range(1, int(round(llen)) + 1):
                    lt = d / max(llen, 1.0)
                    lx = int(round(sx + ca * (d * 0.25) + side * nx * d * 0.72))
                    ly = int(round(sy + lt * llen * 0.76 + d * 0.28 * side * (0.3 if ny > 0.5 else 0.15)))
                    if dry:
                        shade = 2 if (side < 0 or t < 0.5) else 1
                    else:
                        shade = 3 if (side < 0 or t < 0.6) else 2
                        if lt > 0.65 and t > 0.3:
                            shade = 4
                        if noise(lx, ly, seed + i) > 192 and shade < 5:
                            shade += 1
                    gput(grid_c, lx, ly, ramp_c[shade])
            if not dry and i == steps - 4 and noise(int(sx), int(sy), seed + 9) > 130:
                gput(glow_c, int(round(sx)), int(round(sy + 1)), (*PALM_DEW[:3], 170))


def _draw_date_bunch(grid_c, glow_c, cx, cy):
    """Hanging golden cluster of sun-dates beneath crown heart."""
    for dx, dy, sh in ((0, 0, 2), (-1, 2, 3), (1, 2, 2), (-2, 4, 3), (0, 4, 4), (2, 4, 1), (-1, 6, 3), (1, 6, 2), (0, 7, 4), (0, 8, 3)):
        gput(grid_c, int(round(cx + dx)), int(round(cy + dy)), DATE_RAMP[sh])
        if sh >= 3:
            gput(glow_c, int(round(cx + dx)), int(round(cy + dy)), DATE_HOT if sh == 4 else DATE_GLOW)


def _draw_palm_canopy(grid_c, glow_c, cx, cy, fronds, flen, dates, picked, seed):
    # Crownshaft / petiole sheath + lower sun-bleached dry frond skirt
    for dy in range(-3, 5):
        for dx in range(-4, 5):
            if dx * dx * 0.55 + (dy - 0.5) * (dy - 0.5) <= 9.5:
                gput(grid_c, int(round(cx + dx)), int(round(cy + dy)), PALM_BARK[2 if dy > 1 else 3] if dy > 0 else PALM_LEAF[3])
    for d_ang in (0.45, 1.15, 2.0, 2.75):
        _draw_feather_frond(grid_c, glow_c, cx, cy + 2, d_ang, flen * 0.42, 6.0, seed + 701, dry=True)
    if dates > 0 and not picked:
        offsets = [(-4.0, 4.5), (4.0, 5.0), (-0.5, 6.0), (5.5, 3.0)]
        for ox, oy in offsets[:dates]:
            _draw_date_bunch(grid_c, glow_c, cx + ox, cy + oy)
    for f in range(fronds):
        base_ang = (f / fronds) * math.pi * 2.0 + ((seed % 7) - 3) * 0.08
        f_len = flen * (0.86 + 0.22 * (((f * 3 + seed) % 5) / 4.0))
        droop = 5.0 + 4.5 * abs(math.sin(base_ang))
        _draw_feather_frond(grid_c, glow_c, cx, cy - 1, base_ang, f_len, droop, seed + f * 31)


def build_sun_palm(idx, spec, picked=False):
    trunk, crown = grid(), grid()
    glow_t, glow_c = grid(), grid()
    clear_y = FEET_Y - spec["clear"]
    seed = 5100 + idx * 97
    tips = []
    for si, (bx, h, curve, smid, br) in enumerate(spec["stems"]):
        tx, ty = _draw_palm_stem(trunk, crown, clear_y, bx, h, curve, smid, br, seed + si * 23)
        tips.append((si, tx, ty))
    for si, tx, ty in tips:
        scale = 1.0 if si == 0 else 0.78
        _draw_palm_canopy(
            crown, glow_c, tx, ty,
            max(5, int(round(spec["fronds"] * scale))),
            spec["flen"] * scale,
            spec["dates"] if si == 0 else max(0, spec["dates"] - 2),
            picked,
            seed + si * 53,
        )
    glow_src = [[glow_c[y][x] for x in range(CW)] for y in range(CH)]
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            if glow_src[y][x] is not None and glow_src[y][x][3] > 200:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if (dx or dy) and glow_c[y + dy][x + dx] is None:
                            glow_c[y + dy][x + dx] = (*DATE_GLOW[:3], 88)
    t_out, c_out = art_tree.finish(trunk, crown, spec["fronds"] + spec["flen"] * 0.65)
    return t_out, c_out, art_tree.to_pixels(glow_c), art_tree.to_pixels(glow_t)


def build_palm_growth():
    frames = []
    # 0..1: cut palm stumps with exposed warm golden pith ring
    for r in (3.0, 4.4):
        t = grid()
        top_y = FEET_Y - int(r * 2.1)
        for y in range(top_y, FEET_Y + 2):
            flare = max(0.0, (y - (FEET_Y - 3)) * 0.35)
            hw = r + flare
            for dx in range(-int(hw) - 1, int(hw) + 2):
                if abs(dx) <= hw:
                    if y < top_y + 2 and ((dx / (r + 0.1)) ** 2 + ((y - top_y) / (r * 0.45)) ** 2) <= 1.0:
                        d = math.sqrt((dx / (r + 0.1)) ** 2 + ((y - top_y) / (r * 0.45)) ** 2)
                        c = PALM_BARK[5 if d < 0.45 else 4]
                    else:
                        c = PALM_BARK[2 if dx > 0 else (3 if y % 3 else 1)]
                    gput(t, FEET_X + dx, y, c)
        t_out, _ = art_tree.finish(t, grid(), r + 5.0)
        frames.append(t_out)
    # 2: baby sprout rosette, 3: young palm sapling
    for h, nfr, fl in ((6, 4, 9), (22, 6, 15)):
        t = grid()
        c = grid()
        tx, ty = _draw_palm_stem(t, c, FEET_Y - 4, 0, h, 2.0, -1.0, 1.6, 5400 + h)
        _draw_palm_canopy(c, grid(), tx, ty, nfr, fl, 0, True, 5500 + h)
        t_out, _ = art_tree.finish(t, c, fl * 0.7)
        frames.append(t_out)
    while len(frames) < 6:
        frames.append(frames[-1])
    out = [[CLEAR] * (CW * 6) for _ in range(CH)]
    for i, f in enumerate(frames):
        for y in range(CH):
            out[y][i * CW : (i + 1) * CW] = f[y]
    return out


# ================================================================== 2. Sonnenfeigen-Kaktus (Prickly Pear - 5x2 + stripped)
PEARS = [
    {"pads": [(20, 27, 4.5, 4.2, 0), (15, 21, 3.8, 4.6, -1), (25, 22, 3.6, 4.3, 1)], "spread": 10},
    {"pads": [(20, 27, 5.2, 4.4, 0), (14, 22, 4.0, 4.8, 0), (26, 22, 4.0, 4.8, 0), (20, 15, 3.6, 4.4, 1)], "spread": 12},
    {"pads": [(20, 27, 5.8, 4.4, 0), (12, 23, 4.2, 4.6, 0), (28, 23, 4.2, 4.6, 0), (15, 15, 3.6, 4.3, 1), (25, 16, 3.5, 4.2, 1)], "spread": 14},
    {"pads": [(20, 27, 5.2, 4.3, 0), (13, 21, 4.0, 4.7, 0), (26, 23, 4.2, 4.5, 0), (18, 14, 3.6, 4.2, 1)], "spread": 13},
    {"pads": [(20, 27, 6.0, 4.6, 0), (11, 23, 4.2, 4.8, -1), (29, 23, 4.2, 4.8, 0), (14, 15, 3.8, 4.4, 1), (25, 14, 3.8, 4.5, 1), (20, 19, 4.2, 4.2, 2)], "spread": 15},
]


def _draw_pad(px, cx, cy, rx, ry, seed, clipped=False):
    for y in range(max(2, int(cy - ry) - 1), min(GROUND + 1, int(cy + ry) + 2)):
        for x in range(max(2, int(cx - rx) - 1), min(FW - 2, int(cx + rx) + 2)):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                if clipped and y < cy - 1:
                    continue
                if clipped and y == int(cy - 1):
                    put(px, x, y, PULP[2 if abs(dx) < 0.6 else 1])
                    continue
                z = math.sqrt(max(0.0, 1.0 - dx * dx - dy * dy))
                lit = 0.48 - 0.44 * dx - 0.48 * dy + 0.22 * z + (noise(x, y, seed) / 255.0 - 0.5) * 0.16
                put(px, x, y, CACTUS[int(clamp(lit * 5.2 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.45, 0, 5))])


def make_prickly_pear(spec, seed, picked=False, stripped=False):
    px, glow = blank(FW, FH), Glow()
    pads = sorted(spec["pads"], key=lambda p: p[4])
    if stripped:
        pads = [pads[0]]
    for idx, (cx, cy, rx, ry, _z) in enumerate(pads):
        _draw_pad(px, cx, cy, rx, ry, seed + idx * 11, clipped=stripped)
        if not stripped:
            # Tiny pale spine dots on pad faces
            for sx, sy in ((cx - 1, cy - 1), (cx + 1, cy + 1), (cx, cy - 2)):
                if noise(int(sx), int(sy), seed + idx) > 105:
                    put(px, int(round(sx)), int(round(sy)), SPINE[2])
    if not stripped and not picked:
        # Crown top-edge pads with plump coral-gold Sonnenfeigen
        fig_pads = [p for p in pads if p[1] <= 24]
        for idx, (cx, cy, rx, ry, _z) in enumerate(fig_pads[:4]):
            fx = int(round(cx + (-1 if idx % 2 else 1)))
            fy = int(round(cy - ry - 0.5))
            if fy < 3:
                fy = 3
            F.blob(px, fx, fy, 1.8, 2.1, FIG, dither=False)
            glow.emit(px, fx, fy - 1, FIG[4], FIG_HOT, 1)
            glow.emit(px, fx, fy, FIG[3], FIG_GLOW, 0)
    return finish_desert(px, spec["spread"], seed, rim_colors=CACTUS[2:4], outline_tint=SAGE_OUT), glow.done()


# ================================================================== 3. Sandigel (Barrel Cactus - 4x1 + stripped)
BARRELS = [
    {"globes": [(20, 25, 6.5, 5.8)], "flower": False, "spread": 8},
    {"globes": [(18, 25, 6.0, 5.6), (27, 27, 4.0, 3.8)], "flower": False, "spread": 10},
    {"globes": [(20, 23, 5.8, 7.2)], "flower": True, "spread": 9},
    {"globes": [(20, 25, 5.8, 5.5), (12, 27, 4.0, 3.8), (28, 27, 3.8, 3.6)], "flower": True, "spread": 11},
]


def make_barrel_cactus(spec, seed, stripped=False):
    px, glow = blank(FW, FH), Glow()
    for gi, (cx, cy, rx, ry) in enumerate(sorted(spec["globes"], key=lambda g: g[2], reverse=True)):
        for y in range(max(2, int(cy - ry) - 1), min(GROUND + 1, int(cy + ry) + 2)):
            for x in range(max(2, int(cx - rx) - 1), min(FW - 2, int(cx + rx) + 2)):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy > 1.0 or y > GROUND:
                    continue
                if stripped and y < GROUND - 4:
                    continue
                if stripped and y == GROUND - 4:
                    put(px, x, y, PULP[3 if abs(dx) < 0.4 else 2])
                    continue
                rib = 0.22 * math.cos(dx * math.pi * 4.0)
                lit = 0.48 - 0.42 * dx - 0.45 * dy + rib
                c = CACTUS[int(clamp(lit * 5.2 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42, 0, 5))]
                put(px, x, y, c)
        if not stripped:
            # Golden spine stars along ribs
            for rx_u in (-0.55, 0.0, 0.55):
                sx = int(round(cx + rx_u * rx))
                for sy in (int(cy - ry * 0.45), int(cy + ry * 0.1)):
                    put(px, sx, sy, SPINE[2 if rx_u <= 0 else 1])
            if spec["flower"] and gi == 0:
                fy = int(round(cy - ry))
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 0)):
                    put(px, int(cx) + dx, fy + dy, FIG[3 if (dx or dy) else 4])
                glow.emit(px, int(cx), fy - 1, FIG[4], FIG_HOT, 0)
    return finish_desert(px, spec["spread"], seed, outline_tint=SAGE_OUT), glow.done()


# ================================================================== 4. Wüstendorn (Desert Scrub - 6x1 + stripped)
SCRUBS = [
    {"lobes": [(20, 24, 7, 5, 0), (14, 25, 4.5, 4, -1), (26, 25, 4.5, 4, -1)], "pal": SCRUB_SAGE, "spread": 9},
    {"lobes": [(20, 22, 8.5, 6, 0), (13, 25, 5, 4.5, -1), (27, 25, 5, 4.5, -1)], "pal": SCRUB_SAGE, "spread": 11},
    {"lobes": [(20, 25, 11, 5, 0), (10, 26, 5.5, 4, -1), (30, 26, 5.5, 4, -1)], "pal": SCRUB_TEAL, "spread": 13},
    {"lobes": [(17, 24, 7.5, 5.5, 0), (26, 25, 6, 4.5, 1), (11, 26, 4, 3.5, -1)], "pal": SCRUB_SAGE, "spread": 12},
    {"lobes": [(20, 20, 6.5, 7.5, 0), (15, 25, 5, 4.5, -1), (25, 25, 5, 4.5, -1)], "pal": SCRUB_TEAL, "spread": 11},
    {"lobes": [(15, 22, 7.5, 6.5, 0), (26, 21, 7.5, 6.5, 0), (21, 26, 8.5, 4.5, 1)], "pal": SCRUB_SAGE, "spread": 14},
]


def make_desert_scrub(spec, seed, stripped=False):
    rng = random.Random(seed)
    px = blank(FW, FH)
    pal = spec["pal"]
    if stripped:
        for i in range(6):
            x = 20 + (i - 2.5) * 3.2 + rng.uniform(-0.8, 0.8)
            h = rng.uniform(4, 7)
            for s in range(int(h)):
                put(px, int(round(x + s * 0.25 * (-1 if i % 2 else 1))), GROUND - s, CINNAMON[2 if s % 2 else 1])
        return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)
    # Visible gnarled cinnamon branches underneath foliage mounds
    for i in range(5):
        x0 = 20 + (i - 2) * 2.2
        lean = (i - 2) * 0.35 + rng.uniform(-0.15, 0.15)
        h = rng.uniform(7, 13)
        pts = bezier((x0, GROUND), (x0 + lean * 3, GROUND - h * 0.55), (x0 + lean * 7, GROUND - h), n=16)
        for bx, by in pts:
            put(px, int(round(bx)), int(round(by)), CINNAMON[2 if bx < 20 else 1])
    # Leaf tufts across the lobes
    for cx, cy, rx, ry, _z in spec["lobes"]:
        for _ in range(int(rx * ry * 0.7)):
            a = rng.uniform(0, math.tau)
            r = math.sqrt(rng.random())
            lx = clamp(cx + math.cos(a) * rx * r, 3, FW - 4)
            ly = clamp(cy + math.sin(a) * ry * r, 4, GROUND - 1)
            lit = 0.52 - 0.35 * ((lx - 20) / 14.0) - 0.42 * ((ly - 22) / 10.0)
            tone = int(clamp(lit * len(pal) + rng.uniform(-0.6, 0.7), 0, len(pal) - 1))
            put(px, int(round(lx)), int(round(ly)), pal[tone])
            if rng.random() < 0.35:
                put(px, int(round(lx)) + 1, int(round(ly)), pal[max(0, tone - 1)])
    # A few protruding dry twigs + thorns at rim
    for _ in range(5):
        cx, cy, rx, ry, _ = rng.choice(spec["lobes"])
        ang = rng.uniform(-math.pi * 0.9, -math.pi * 0.1)
        x1 = int(clamp(cx + math.cos(ang) * (rx + 1.5), 2, FW - 3))
        y1 = int(clamp(cy + math.sin(ang) * (ry + 1.5), 3, GROUND - 2))
        put(px, x1, y1, CINNAMON[3])
    return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)


# ================================================================== 5. Steppenroller (Tumble Scrub - 4x1 + stripped)
TUMBLES = [
    {"r": 6.8, "cy": 24, "arcs": 10, "spread": 9},
    {"r": 7.8, "cy": 23, "arcs": 12, "spread": 10},
    {"r": 8.6, "cy": 22, "arcs": 14, "spread": 11},
    {"r": 9.4, "cy": 21, "arcs": 16, "spread": 12},
]


def make_tumble_scrub(spec, seed, stripped=False):
    rng = random.Random(seed)
    px = blank(FW, FH)
    if stripped:
        for i in range(4):
            pts = bezier((17 + i * 2, GROUND), (16 + i * 2.5, GROUND - 4), (15 + i * 3, GROUND - 6), n=10)
            for bx, by in pts:
                put(px, int(round(bx)), int(round(by)), TUMBLE[2])
        return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)
    r = spec["r"]
    cy = spec["cy"]
    # Dark wispy core twigs for depth while leaving air pockets visible
    for i in range(spec["arcs"] // 2):
        a0 = rng.uniform(0, math.tau)
        a1 = a0 + rng.uniform(1.6, 2.8)
        rr = r * rng.uniform(0.45, 0.78)
        p0 = (20 + math.cos(a0) * rr, cy + math.sin(a0) * rr * 0.8)
        p2 = (20 + math.cos(a1) * rr, cy + math.sin(a1) * rr * 0.8)
        pm = (20 + rng.uniform(-rr * 0.4, rr * 0.4), cy + rng.uniform(-rr * 0.35, rr * 0.35))
        for bx, by in bezier(p0, pm, p2, n=16):
            if 2 <= bx < FW - 2 and 2 <= by <= GROUND:
                put(px, int(round(bx)), int(round(by)), TUMBLE[1 if by > cy else 2])
    # Sun-bleached outer basket-weave wire twigs (sampled sparsely for open lacy silhouette)
    for i in range(spec["arcs"]):
        a0 = (i / spec["arcs"]) * math.tau + rng.uniform(-0.2, 0.2)
        a1 = a0 + rng.uniform(1.1, 2.2)
        rr = r * rng.uniform(0.72, 1.0)
        p0 = (20 + math.cos(a0) * rr, cy + math.sin(a0) * rr * 0.82)
        p2 = (20 + math.cos(a1) * rr, cy + math.sin(a1) * rr * 0.82)
        pm = (20 + math.cos((a0 + a1) * 0.5) * rr * 1.15, cy + math.sin((a0 + a1) * 0.5) * rr * 0.92)
        for j, (bx, by) in enumerate(bezier(p0, pm, p2, n=14)):
            if not (2 <= bx < FW - 2 and 2 <= by <= GROUND):
                continue
            lit = 0.55 - 0.35 * ((bx - 20) / r) - 0.38 * ((by - cy) / r)
            tone = int(clamp(1.2 + lit * 3.4, 1, len(TUMBLE) - 1))
            put(px, int(round(bx)), int(round(by)), TUMBLE[tone])
    # Stem anchoring to sand
    for k in range(3):
        put(px, 19 + (k % 2), GROUND - k, TUMBLE[1])
    return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)


# ================================================================== 6. Dünengras (Dune Grass - 5x1 + stripped)
DUNES = [
    {"blades": 10, "spread": 7, "lo": 8, "hi": 16, "plumes": 2, "wind": 0.45},
    {"blades": 13, "spread": 8, "lo": 9, "hi": 19, "plumes": 3, "wind": 0.65},
    {"blades": 16, "spread": 10, "lo": 10, "hi": 21, "plumes": 3, "wind": 0.55},
    {"blades": 14, "spread": 9, "lo": 9, "hi": 18, "plumes": 2, "wind": -0.35},
    {"blades": 18, "spread": 11, "lo": 11, "hi": 23, "plumes": 4, "wind": 0.72},
]


def make_dune_grass(spec, seed, stripped=False):
    rng = random.Random(seed)
    px = blank(FW, FH)
    if stripped:
        for i in range(8):
            x = 20 + (i - 3.5) * 1.8 + rng.uniform(-0.4, 0.4)
            for s in range(rng.randrange(2, 5)):
                put(px, int(round(x + s * 0.3)), GROUND - s, DUNE[2 if s < 2 else 3])
        return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)
    for i in range(spec["blades"]):
        u = i / max(spec["blades"] - 1, 1) - 0.5
        x0 = 20 + u * spec["spread"] * 0.85 + rng.uniform(-0.6, 0.6)
        h = rng.uniform(spec["lo"], spec["hi"]) * (1.0 - 0.32 * abs(u))
        splay = u * 11.0 + spec["wind"] * 7.0 + rng.uniform(-1.5, 1.5)
        end_x = clamp(x0 + splay, 3, FW - 4)
        end_y = clamp(GROUND - h, 4, GROUND - 3)
        pts = bezier((x0, GROUND), (x0 + splay * 0.25, GROUND - h * 0.72), (end_x, end_y), n=20)
        for j, (bx, by) in enumerate(pts):
            t = j / max(len(pts) - 1, 1)
            tone = int(clamp(1 + t * 3.1 - (0.5 if bx > 20 else 0.0), 0, len(DUNE) - 1))
            put(px, int(round(bx)), int(round(by)), DUNE[tone])
    # Airy arching feathery seed plumes on outer stalks
    for i in range(spec["plumes"]):
        u = (i / max(spec["plumes"] - 1, 1) - 0.5) * 0.85 if spec["plumes"] > 1 else 0.0
        x0 = 20 + u * spec["spread"] * 0.7
        h = rng.uniform(spec["hi"] - 3, spec["hi"])
        splay = u * 9.0 + spec["wind"] * 8.5
        end = (clamp(x0 + splay, 4, FW - 5), clamp(GROUND - h, 4, GROUND - 7))
        for bx, by in bezier((x0, GROUND), (x0 + splay * 0.3, GROUND - h * 0.75), end, n=18):
            put(px, int(round(bx)), int(round(by)), DUNE[2])
        tx, ty = int(round(end[0])), int(round(end[1]))
        wdir = 1 if splay >= 0 else -1
        for k in range(3):
            put(px, tx + wdir * k, ty + (k // 2), PLUME_D[2 if k == 0 else 1])
    return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)


# ================================================================== 7. Glasaloe (Glass Aloe - 4x2 + glow)
ALOES = [
    {"spears": 6, "len": (10, 14), "spread": 8},
    {"spears": 8, "len": (11, 16), "spread": 9},
    {"spears": 10, "len": (12, 19), "spread": 11},
    {"spears": 9, "len": (11, 17), "spread": 10},
]


def _aloe_spear(px, glow, x0, y0, ang, length, wmax, seed, picked=False):
    x, y = float(x0), float(y0)
    steps = max(4, int(length * 3))
    for i in range(steps + 1):
        t = i / steps
        dx, dy = math.cos(ang), math.sin(ang)
        nx, ny = dy, -dx
        w = wmax * (1.0 - t) ** 0.72 * (0.45 + 0.55 * min(1.0, t * 4.5))
        s = -w
        while s <= w + 0.01:
            lit = 0.5 + 0.35 * (nx * -0.55 + ny * -0.8) * (1 if s >= 0 else -1) + 0.38 * t
            tone = int(clamp(lit * (len(ALOE) - 0.5), 0, len(ALOE) - 1))
            xx, yy = int(round(x + nx * s)), int(round(y + ny * s))
            put(px, xx, yy, ALOE[tone])
            s += 0.5
        if not picked and t > 0.76:
            glow.emit(px, int(round(x)), int(round(y)), ALOE[5] if t > 0.9 else ALOE[4], ALOE_HOT if t > 0.9 else ALOE_GLOW, 1 if t > 0.92 else 0)
        x += dx / 3.0
        y += dy / 3.0


def make_glass_aloe(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["spears"] if not picked else max(4, spec["spears"] // 2)
    angles = [-math.pi / 2 + (i / max(n - 1, 1) - 0.5) * 2.15 + rng.uniform(-0.08, 0.08) for i in range(n)]
    for a in sorted(angles, key=lambda v: -abs(v + math.pi / 2)):
        length = rng.uniform(*spec["len"]) * (0.50 if picked else 1.0)
        wmax = 2.6 if not picked else 1.8
        _aloe_spear(px, glow, 20 + math.cos(a) * 1.5, GROUND - 1, a, length, wmax, seed, picked=picked)
    return finish_desert(px, spec["spread"], seed, outline_tint=QUARTZ_OUT), glow.done()


# ================================================================== 8. Königin der Nacht (Night Cactus - 4x3 + glow)
# CRITICAL Flora row contract (`flora.gd:149`):
#   row 0 = NIGHT OPEN
#   row 1 = DAY CLOSED bud
#   row 2 = PICKED bare stems
NIGHTS = [
    {"stems": [(20, 17, -1), (22, 13, 1)], "bloom_at": (17, 13), "spread": 8},
    {"stems": [(19, 19, -2), (22, 14, 2)], "bloom_at": (16, 11), "spread": 9},
    {"stems": [(20, 21, 1), (17, 15, -3), (24, 14, 2)], "bloom_at": (22, 10), "spread": 10},
    {"stems": [(21, 20, -2), (17, 16, -3), (25, 13, 3)], "bloom_at": (14, 13), "spread": 10},
]


def _night_star(px, glow, cx, cy):
    # Radiant star blossom + warm golden stamens
    for dy in range(-5, 6):
        for dx in range(-5, 6):
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            star = 3.2 + 1.8 * max(0.0, math.cos(ang * 5.0))
            if r <= star:
                tone = 4 if r < 2.2 else (3 if r < 3.4 else (2 if dx + dy <= 0 else 1))
                put(px, cx + dx, cy + dy, NIGHT_PETAL[tone])
                if r < 2.6:
                    glow.emit(px, cx + dx, cy + dy, None, NIGHT_GLOW, 1 if r < 1.2 else 0)
    glow.emit(px, cx, cy, GOLD_STAMEN, NIGHT_HOT, 1)
    put(px, cx + 1, cy, GOLD_STAMEN)


def make_night_cactus(spec, seed, row_mode=0):
    """row_mode: 0 = night open bloom, 1 = day closed bud, 2 = picked bare stem."""
    px, glow = blank(FW, FH), Glow()
    for sx, h, lean in spec["stems"]:
        pts = bezier((sx, GROUND), (sx + lean * 0.4, GROUND - h * 0.5), (sx + lean, GROUND - h), n=24)
        for j, (bx, by) in enumerate(pts):
            t = j / max(len(pts) - 1, 1)
            for k in (-1, 0, 1):
                c = CEREUS[3 if k < 0 else (2 if k == 0 else 1)]
                put(px, int(round(bx)) + k, int(round(by)), c)
            if j % 5 == 2:
                put(px, int(round(bx)) - 1, int(round(by)) - 1, SPINE[1])
    bx, by = spec["bloom_at"]
    if row_mode == 0:  # Night open
        _night_star(px, glow, bx, by)
    elif row_mode == 1:  # Day closed spindle bud
        pts = bezier((bx, by + 2), (bx - 1, by - 1), (bx - 2, by - 4), n=12)
        for i, (pxx, pyy) in enumerate(pts):
            r = 1.6 * (1.0 - 0.55 * (i / 12.0))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx * dx + dy * dy <= r * r:
                        put(px, int(round(pxx)) + dx, int(round(pyy)) + dy, NIGHT_BUD[2 if dx <= 0 else 1])
        put(px, bx - 2, by - 4, NIGHT_BUD[3])
    return finish_desert(px, spec["spread"], seed, outline_tint=QUARTZ_OUT), glow.done()


# ================================================================== 9. Sandknolle (Sand Tuber - 4x2 + glow, pull: true)
TUBERS = [
    {"twigs": 5, "h": 12, "spread": 8},
    {"twigs": 6, "h": 14, "spread": 9},
    {"twigs": 7, "h": 15, "spread": 9},
    {"twigs": 6, "h": 13, "spread": 8},
]


def make_sand_tuber(spec, seed, pulled=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        # Crater/divot in golden sand after Ellie yanks it out
        for dy in range(-2, 3):
            for dx in range(-6, 7):
                d = (dx / 6.2) ** 2 + (dy / 2.4) ** 2
                if d <= 1.0:
                    c = SAND_MOUND[0] if d < 0.35 else (SAND_MOUND[1] if dy < 0 else SAND_MOUND[2])
                    put(px, 20 + dx, GROUND - 1 + dy, c)
        for dx in range(-5, 6):
            if abs(dx) > 2:
                put(px, 20 + dx, GROUND - 3, SAND_MOUND[3])
        return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), blank(FW, FH)
    # Little heaped sand mound around base
    F.blob(px, 20, GROUND - 1.5, 6.5, 2.5, SAND_MOUND, dither=False)
    # Peeking amber-honey water-tuber shoulder
    F.blob(px, 19.5, GROUND - 3.5, 3.6, 2.8, TUBER_SKIN, dither=False)
    glow.emit(px, 18, GROUND - 4, TUBER_SKIN[4], SAND_GLINT, 0)
    # Twisted dry ochre/olive leaf crown above tuber
    for i in range(spec["twigs"]):
        a = -math.pi / 2 + (i / max(spec["twigs"] - 1, 1) - 0.5) * 1.9 + rng.uniform(-0.15, 0.15)
        h = rng.uniform(spec["h"] * 0.55, spec["h"])
        pts = bezier((20, GROUND - 4), (20 + math.cos(a) * h * 0.45, GROUND - 4 + math.sin(a) * h * 0.7), (20 + math.cos(a) * h + rng.uniform(-1.5, 2.0), GROUND - 4 + math.sin(a) * h * 0.85), n=16)
        for j, (bx, by) in enumerate(pts):
            put(px, int(round(bx)), int(round(by)), DUNE[1 + min(3, j // 5)])
    return finish_desert(px, spec["spread"], seed, outline_tint=DRY_OUT), glow.done()


# ================================================================== Item Icons (16x16)
def i_sun_fig(px, g):
    F.blob(px, 8, 8.5, 4.2, 4.5, FIG, dither=False)
    for dx in (-2, -1, 0, 1, 2):
        px[4][8 + dx] = CACTUS[3 if dx <= 0 else 2]
    px[3][7], px[3][8], px[3][9] = CACTUS[4], CACTUS[5], CACTUS[3]
    px[6][6] = FIG[4]


def i_crown_fig(px, g):
    F.blob(px, 8, 9.0, 4.0, 3.8, FIG, dither=False)
    # Golden star-bract petals at top
    for dx, dy, c in ((0, -4, 4), (-2, -3, 3), (2, -3, 2), (-1, -2, 4), (1, -2, 3), (0, -2, 4)):
        px[8 + dy][8 + dx] = FIG[c]
    for dx in (-1, 0, 1):
        px[13][8 + dx] = CACTUS[2]
    px[7][6] = FIG[4]


def i_cactus_wood(px, g):
    # Hollow pale honey-ivory saguaro skeleton cylinder with characteristic oval pores
    rib = ramp("5a4434", "967454", "cbb088", "efe0bc", "fbf4de")
    pts = bezier((4.5, 11.5), (8.0, 8.0), (11.5, 4.5), n=24)
    stroke(px, pts, 3.0, 2.8, rib)
    stroke(px, [(11.5, 4.5)], 2.8, 2.8, [rib[1], rib[3], rib[4]])
    px[4][11], px[5][11] = rib[0], rib[0]
    for x, y in ((6, 9), (8, 7), (7, 10), (9, 8)):
        px[y][x] = rib[0]


def i_cactus_pulp(px, g):
    # Freshly cut wedge of cool jade/pale cream cactus pulp
    for y in range(4, 13):
        w = int((y - 3) * 0.9)
        for dx in range(-w // 2, w // 2 + 1):
            x = 8 + dx - (12 - y) // 4
            if y >= 11:
                px[y][x] = CACTUS[2 if dx <= 0 else 1]
            else:
                px[y][x] = PULP[3 if dx < 0 and y < 8 else (2 if dx <= 1 else 1)]
    for x, y in ((7, 7), (8, 9), (6, 9), (9, 10)):
        px[y][x] = CINNAMON[0]


def i_quartz_aloe(px, g):
    # Thick curved translucent aqua-white succulent spear
    pts = bezier((4.5, 11.2), (6.5, 6.8), (11.5, 3.0), n=24)
    stroke(px, pts, 2.3, 0.7, ALOE[1:])
    for tx, ty in ((4, 8), (6, 6), (8, 9), (10, 6)):
        px[ty][tx] = ALOE[5]
    px[3][11] = ALOE[5]


def i_night_bloom(px, g):
    # Radiant 5-point star flower + warm golden center
    for dy in range(-5, 6):
        for dx in range(-5, 6):
            r = math.hypot(dx, dy)
            star = 3.2 + 2.2 * max(0.0, math.cos(math.atan2(dy, dx) * 5.0 - 0.3))
            if r <= star and 2 <= 8 + dx < 14 and 2 <= 8 + dy < 14:
                px[8 + dy][8 + dx] = NIGHT_PETAL[4 if r < 2.2 else (3 if dx + dy <= 1 else 2)]
    px[8][8] = GOLD_STAMEN
    px[7][8], px[8][7] = NIGHT_HOT, GOLD_STAMEN
    px[13][8], px[14][8] = CEREUS[2], CEREUS[1]


def i_sand_tuber(px, g):
    F.blob(px, 8, 9.0, 4.0, 3.4, TUBER_SKIN, dither=False)
    px[12][7], px[13][6], px[12][9], px[13][10] = TUBER_SKIN[1], TUBER_SKIN[0], TUBER_SKIN[1], TUBER_SKIN[0]
    for dx, dy, c in ((0, -4, 1), (-1, -4, 2), (1, -4, 1), (0, -5, 3), (-2, -5, 2)):
        px[9 + dy][8 + dx] = DUNE[c]
    px[7][6] = TUBER_SKIN[4]


# ================================================================== 9. Quarzschilf (Oasis Reed - 5x1 + stripped, 40x34)
REEDS = [
    {"style": "papyrus", "stalks": [(-4, 21, -4.5), (0, 25, 1.0), (4, 20, 4.8)], "spread": 11},
    {"style": "iris", "stalks": [(-4, 18, -3.2), (0, 23, 0.4), (4, 19, 3.4)], "spread": 12},
    {"style": "double_plume", "stalks": [(-5, 22, -4.8), (-1, 25, -1.2), (3, 24, 3.0), (6, 18, 5.2)], "spread": 12},
    {"style": "fountain_sedge", "stalks": [(-5, 16, -6.5), (-2, 20, -3.5), (1, 22, 1.5), (4, 19, 4.5), (6, 15, 7.0)], "spread": 13},
    {"style": "crystal_horsetail", "stalks": [(-4, 21, -2.0), (-1, 26, -0.5), (2, 23, 1.2), (5, 19, 2.6)], "spread": 11},
]


def make_oasis_reed(spec, seed, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    style = spec["style"]
    if stripped:
        for ox, _h, lean in spec["stalks"]:
            pts = bezier((20 + ox, GROUND), (20 + ox + lean * 0.15, GROUND - 3), (20 + ox + lean * 0.25, GROUND - 6), n=10)
            for j, (sx, sy) in enumerate(pts):
                put(px, int(round(sx)), int(round(sy)), REED_CULM[1 if j < 6 else 2])
        return finish_desert(px, spec["spread"], seed, outline_tint=SAGE_OUT), blank(FW, FH)

    # Dense basal tuft of arching ribbon/sword leaves hugging the shore
    basal_angles = (-8.5, -5.5, -2.5, 2.5, 5.5, 8.5)
    for bi, bx_off in enumerate(basal_angles):
        bx0 = 20 + bx_off * 0.45
        bh = rng.randint(6, 10)
        pts = bezier((bx0, GROUND), (bx0 + bx_off * 0.55, GROUND - bh * 0.6), (bx0 + bx_off, max(12, GROUND - bh)), n=12)
        for j, (lx, ly) in enumerate(pts):
            put(px, int(round(lx)), int(round(ly)), REED_CULM[min(4, 1 + j // 3)])

    for si, (ox, h, lean) in enumerate(spec["stalks"]):
        bx = 20 + ox
        pts = bezier((bx, GROUND), (bx + lean * 0.45, GROUND - h * 0.52), (bx + lean, max(4, GROUND - h)), n=22)
        for j, (sx, sy) in enumerate(pts):
            t = j / max(len(pts) - 1, 1)
            c_idx = min(4, 1 + int(t * 3.4))
            ix, iy = int(round(sx)), int(round(sy))
            # Segmented node rings on crystal horsetail
            if style == "crystal_horsetail" and j % 5 == 0 and 0.15 < t < 0.9:
                put(px, ix, iy, REED_CULM[0])
                put(px, ix + 1, iy, REED_CULM[2])
                continue
            put(px, ix, iy, REED_CULM[c_idx])
            if (style in ("iris", "papyrus") or t < 0.72) and j % 2 == 0:
                put(px, ix - 1 if lean >= 0 else ix + 1, iy, REED_CULM[max(0, c_idx - 1)])

        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        if style == "papyrus":
            # Broad radiating papyrus fan umbel with bright turquoise-gold dew drops
            for ray in range(-3, 4):
                rx = tx + ray * 2
                ry = max(3, ty + abs(ray) - 2)
                for m in range(1, 4):
                    mx = int(round(tx + (rx - tx) * (m / 3.0)))
                    my = int(round(ty + (ry - ty) * (m / 3.0)))
                    put(px, mx, my, REED_CULM[4] if m < 3 else REED_TIP[1])
                if abs(ray) <= 2 and (ray + si) % 2 == 0:
                    glow.emit(px, rx, ry, REED_TIP[2], REED_TIP[1], 1 if ray == 0 else 0)
        elif style == "iris":
            # Twin flag-iris chalices with warm gold beards
            if si == 1:
                for fx_o, fy_o in ((0, 0), (-3, 3)):
                    bx2, by2 = tx + fx_o, max(5, ty + fy_o)
                    for dx, dy, sh in ((0, -2, 3), (-2, 0, 2), (2, 0, 1), (-1, -1, 4), (1, -1, 2), (0, 1, 1)):
                        put(px, bx2 + dx, by2 + dy, LILY_PETAL[sh])
                    glow.emit(px, bx2, by2 - 1, LILY_GOLD[1], LILY_GOLD[2], 1 if fx_o == 0 else 0)
                    glow.emit(px, bx2, by2, LILY_GOLD[0], LILY_GOLD[1], 0)
            else:
                put(px, tx, max(4, ty - 1), REED_CULM[4])
        elif style == "double_plume":
            # Fluffy warm-buff / aqua twin seed plumes along top third
            for pk in range(6):
                py = max(3, ty + pk)
                px_off = int(round(math.sin(pk * 0.9 + si) * 1.4))
                put(px, tx + px_off, py, PLUME_D[min(2, pk // 2)] if si % 2 == 0 else REED_TIP[min(2, 2 - pk // 3)])
                put(px, tx + px_off + 1, py, PLUME_D[1] if si % 2 == 0 else REED_TIP[0])
            if si in (1, 2):
                glow.emit(px, tx, max(3, ty + 1), REED_TIP[2], REED_TIP[1], 0)
        elif style == "fountain_sedge":
            # Arching cascading tips with dew droplets
            for droop in range(1, 4):
                dx = tx + (droop if lean >= 0 else -droop)
                dy = ty + droop
                put(px, dx, dy, REED_CULM[4] if droop < 3 else REED_TIP[1])
            if si in (1, 2, 3):
                glow.emit(px, tx + (3 if lean >= 0 else -3), ty + 3, REED_TIP[2], REED_TIP[1], 0)
        elif style == "crystal_horsetail":
            # Faceted cyan-quartz bud tip atop segmented stalk
            for dx, dy, sh in ((0, -2, 4), (0, -1, 3), (-1, 0, 2), (1, 0, 1)):
                put(px, tx + dx, max(3, ty + dy), QUARTZ_CRYSTAL[sh])
            glow.emit(px, tx, max(3, ty - 1), REED_TIP[2], REED_TIP[1], 1 if si == 1 else 0)

    return finish_desert(px, spec["spread"], seed, outline_tint=SAGE_OUT), glow.done()


# ================================================================== 10. Quellblume (Oasis Lily - 4x2, 40x34)
LILIES = [
    {"blooms": [(16, 20), (24, 22)], "pads": [(14, 28, 6.2, 2.8), (25, 28, 6.0, 2.7), (20, 26, 7.0, 3.2)], "spread": 12},
    {"blooms": [(14, 21), (20, 18), (26, 21)], "pads": [(13, 28, 6.4, 2.9), (26, 28, 6.2, 2.8), (20, 27, 7.6, 3.3), (20, 30, 5.8, 2.2)], "spread": 13},
    {"blooms": [(15, 22), (21, 18), (26, 23)], "pads": [(14, 28, 6.6, 3.0), (26, 28, 6.4, 2.9), (20, 26, 7.4, 3.4)], "spread": 13},
    {"blooms": [(13, 21), (19, 17), (25, 20), (20, 24)], "pads": [(12, 28, 6.5, 2.9), (27, 28, 6.5, 2.9), (20, 26, 8.0, 3.5), (20, 30, 6.5, 2.3)], "spread": 14},
]


def make_oasis_lily(spec, seed, picked=False):
    px, glow = blank(FW, FH), Glow()
    # Multi-layered notched emerald lotus & succulent pads hugging shore
    for pi, (bx, by, rx, ry) in enumerate(spec["pads"]):
        notch_side = -1 if pi % 2 == 0 else 1
        for dy in range(-5, 6):
            for dx in range(-9, 10):
                d = (dx / rx) ** 2 + (dy / ry) ** 2
                if d <= 1.0:
                    if notch_side * dx > rx * 0.45 and abs(dy) <= 1 and d > 0.35:
                        continue
                    sh = 4 if (dy < -1 and dx < 1) else (3 if d < 0.58 else (2 if dx + dy <= 2 else 1))
                    put(px, int(round(bx + dx)), int(round(by + dy)), LILY_LEAF[sh])
    # Arching glossy side leaves behind blooms
    for sx_off in (-5, 5):
        pts = bezier((20, GROUND - 2), (20 + sx_off * 0.8, GROUND - 7), (20 + sx_off * 1.4, GROUND - 9), n=10)
        for j, (lx, ly) in enumerate(pts):
            put(px, int(round(lx)), int(round(ly)), LILY_LEAF[min(4, 2 + j // 4)])

    for idx, (fx, fy) in enumerate(spec["blooms"]):
        # Curved jade flower stem
        stem_pts = bezier((20 + (fx - 20) * 0.4, GROUND - 2), ((20 + fx) * 0.5, (GROUND + fy) * 0.5), (fx, fy + 2), n=10)
        for sx, sy in stem_pts:
            put(px, int(round(sx)), int(round(sy)), LILY_LEAF[2])
        if picked:
            put(px, fx, fy + 1, LILY_LEAF[3])
            put(px, fx, fy, LILY_PETAL[0])
            put(px, fx - 1, fy + 1, LILY_LEAF[2])
        else:
            # Rich 6-7px multi-petalled star lotus blossom with crisp sunlit lip & warm amber heart
            petals = (
                (0, -3, 3), (-3, -1, 2), (3, -1, 1), (-3, 1, 1), (3, 1, 0), (0, 2, 1),
                (-2, -2, 4), (2, -2, 3), (-2, 1, 2), (2, 1, 1),
                (-1, -2, 4), (1, -2, 3), (-2, 0, 3), (2, 0, 2), (-1, 1, 2), (1, 1, 1),
                (-1, -1, 4), (1, -1, 3), (0, -1, 4),
            )
            for dx, dy, sh in petals:
                put(px, fx + dx, fy + dy, LILY_PETAL[sh])
            put(px, fx, fy, LILY_GOLD[1])
            put(px, fx - 1, fy, LILY_GOLD[2])
            glow.emit(px, fx, fy - 1, LILY_GOLD[2], LILY_PETAL[3], 1 if idx <= 1 else 0)
            glow.emit(px, fx, fy, LILY_GOLD[1], LILY_GOLD[2], 0)
            glow.emit(px, fx - 1, fy - 1, LILY_PETAL[4], LILY_PETAL[2], 0)
    return finish_desert(px, spec["spread"], seed, outline_tint=SAGE_OUT), glow.done()


# ================================================================== 11. Sonnenquarz-Fels (6 cols x 4 rows, 64x56, feet (32, 52))
QUARTZ_ROCKS = [
    # 0: Pure Starburst Crystal Druse (cluster of 7 radiating faceted prisms on crystalline quartz matrix)
    {
        "prims": [("block", 32, 26, 18, 9, 0, 0), ("block", 24, 14, 9, 7, -1, -1), ("block", 40, 14, 9, 7, 1, -1)],
        "crystal_base": True,
        "spires": [
            (32, 46, 26, 4.6, -4), (27, 47, 22, 4.0, -22), (37, 47, 21, 4.0, 18),
            (22, 49, 16, 3.3, -38), (42, 49, 16, 3.3, 36), (30, 50, 15, 3.1, 8), (35, 50, 13, 2.9, -14),
        ],
    },
    # 1: Asymmetric Desert Sandstone Crag + Shoulder Quartz Burst
    {
        "prims": [("block", 27, 30, 21, 22, -2, 0), ("block", 44, 18, 12, 13, 2, -1)],
        "strata": 5, "veins": 1, "crack": 2,
        "spires": [
            (36, 38, 23, 4.2, 22), (42, 42, 18, 3.5, 35), (30, 32, 19, 3.8, -12), (46, 46, 13, 2.9, 44),
        ],
    },
    # 2: Grand Cathedral Quartz Monolith (towering snow-white central obelisk + flanking spires)
    {
        "prims": [("block", 32, 38, 28, 12, 0, 0), ("block", 18, 15, 10, 10, -1, -1), ("block", 46, 15, 10, 10, 1, -1)],
        "strata": 6, "crack": 2,
        "spires": [
            (32, 44, 36, 5.4, -3), (24, 46, 26, 4.3, -18), (40, 46, 25, 4.2, 16),
            (18, 49, 17, 3.4, -32), (46, 49, 16, 3.3, 30), (35, 49, 18, 3.2, 6),
        ],
    },
    # 3: Tall Leaning Desert Quartz Stele (wind-carved sandstone tower with quartz vein & jutting points)
    {
        "prims": [("block", 30, 22, 14, 42, 3, 0), ("block", 43, 12, 7, 17, -2, -1)],
        "strata": 6, "veins": 2, "crack": 2,
        "spires": [
            (32, 15, 14, 3.4, 8), (22, 29, 15, 3.2, -36), (40, 36, 16, 3.3, 32), (44, 44, 13, 2.8, 24),
        ],
    },
    # 4: Wide Wind-Eroded Mesa Slab with Twin Crystal Clusters
    {
        "prims": [("block", 32, 48, 42, 14, 1, 0), ("block", 24, 28, 22, 19, -1, 1)],
        "strata": 4, "veins": 1, "crack": 2,
        "spires": [
            (18, 37, 21, 3.8, -18), (24, 35, 17, 3.3, 6),
            (41, 41, 22, 4.0, 22), (46, 44, 16, 3.2, 38), (36, 42, 14, 3.0, -8),
        ],
    },
    # 5: Cracked Geode Boulder (twin sandstone jaws cradling a radiant crystal hollow)
    {
        "prims": [("block", 21, 20, 13, 24, -3, 0), ("block", 43, 20, 13, 22, 3, 0)],
        "strata": 5, "veins": 1, "crack": 2,
        "spires": [
            (32, 45, 27, 4.5, 2), (28, 46, 22, 3.9, -18), (36, 46, 21, 3.8, 20),
            (25, 48, 16, 3.2, -30), (39, 48, 15, 3.1, 30),
        ],
    },
]


def _draw_faceted_prism(px, glow, bx, by, length, width, angle_deg, stage, seed):
    scale = (1.0, 0.78, 0.52, 0.25)[stage]
    ph = max(6.0, length * scale)
    pw = max(1.8, width * (1.0 if stage == 0 else (0.86 if stage == 1 else 0.72)))
    rad = math.radians(angle_deg)
    ax, ay = math.sin(rad), -math.cos(rad)
    nx, ny = math.cos(rad), math.sin(rad)
    min_x = max(2, int(math.floor(min(bx, bx + ax * ph) - pw - 2)))
    max_x = min(S.RW - 3, int(math.ceil(max(bx, bx + ax * ph) + pw + 2)))
    min_y = max(2, int(math.floor(min(by, by + ay * ph) - pw - 2)))
    max_y = min(S.GR, int(math.ceil(max(by, by + ay * ph) + 2)))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            dx = x + 0.5 - bx
            dy = y + 0.5 - by
            u = dx * ax + dy * ay
            v = dx * nx + dy * ny
            if u < -0.6 or u > ph:
                continue
            t = clamp(u / ph, 0.0, 1.0)
            half = pw * ((1.0 - t) / 0.28 if t > 0.72 else 0.88 + 0.12 * (t / 0.72))
            if abs(v) > half:
                continue
            rel = v / max(half, 0.5)
            if t > 0.72:
                sh = 5 if rel <= 0.1 else (4 if rel <= 0.6 else 3)
            elif rel < -0.58:
                sh = 5 if t > 0.2 else 4
            elif rel < -0.14:
                sh = 4 if t > 0.25 else 3
            elif rel < 0.30:
                sh = 3 if t > 0.18 else 2
            else:
                sh = 2 if rel < 0.72 else 1
            if u < 1.8 and sh > 1:
                sh -= 1
            if t > 0.45 and t < 0.74 and abs(rel + 0.14) < 0.18 and seed % 3 == 0:
                px[y][x] = QUARTZ_GOLD if stage == 0 else QUARTZ_CRYSTAL[5]
            else:
                px[y][x] = QUARTZ_CRYSTAL[sh]
            if stage < 3 and sh >= 4 and (t > 0.76 or (rel < -0.55 and (x + y) % 3 == 0)):
                c_g = QUARTZ_GOLD if (t > 0.86 and seed % 2 == 0) else QUARTZ_CRYSTAL[4]
                glow.emit(px, x, y, c_g, QUARTZ_CRYSTAL[3], 1 if t > 0.84 else 0)


def render_sun_quartz_rock(idx, spec, stage):
    px = blank(S.RW, S.RH)
    glow = Glow(S.RW, S.RH)
    rng = random.Random(6100 + idx * 131 + stage * 17)
    seed = 6100 + idx * 131 + stage * 17
    if stage == 3:
        # Shattered sandstone & crystalline quartz rubble pile
        width = max(abs(p[1] - 32) + p[2] / 2 for p in spec["prims"])
        ramp_r = QUARTZ_CRYSTAL[1:5] if spec.get("crystal_base") else DESERT_ROCK[1:5]
        for _ in range(7 + int(width / 4)):
            cx = 32 + rng.uniform(-width * 0.72, width * 0.72)
            cy = S.GR - 1 - rng.uniform(0.0, 2.6)
            r = rng.uniform(1.5, 2.8)
            stroke(px, [(cx, cy)], r, r, ramp_r)
        for sx, sy, sh in ((27, S.GR - 5, 4), (33, S.GR - 6, 5), (37, S.GR - 4, 3)):
            if 4 <= sx < S.RW - 4:
                px[sy][sx] = QUARTZ_CRYSTAL[sh]
                px[sy + 1][sx] = QUARTZ_CRYSTAL[2]
                glow.emit(px, sx, sy, QUARTZ_CRYSTAL[4], QUARTZ_CRYSTAL[3], 1)
        return S.finish_rock(px), glow.done()

    f = (1.0, 0.80, 0.58)[stage]
    normal = S.rock_scene(spec, f)
    ramp_b = QUARTZ_CRYSTAL if spec.get("crystal_base") else DESERT_ROCK
    for y in range(S.RH):
        for x in range(S.RW):
            n = normal[y][x]
            if n is None:
                continue
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
            lit = (n[0] * S.LIGHT[0] + n[1] * S.LIGHT[1] + n[2] * S.LIGHT[2]) / ln
            lit += (noise(x // 2, y // 2, seed) / 255.0 - 0.5) * 0.20 + (noise(x, y, seed + 1) / 255.0 - 0.5) * 0.10
            lit -= 0.20 * max(0.0, (y - (S.GR - 9)) / 9.0)
            if "strata" in spec:
                band = int((y + 3 * math.sin(x * 0.22 + seed)) // spec["strata"])
                lit += 0.14 if band % 2 else -0.10
            v = (lit + 0.5) / 1.5 * 5.99
            px[y][x] = ramp_b[int(max(0, min(5, v + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5)))]
    body = [row[:] for row in px]
    for y in range(S.RH):
        for x in range(S.RW):
            if not body[y][x][3]:
                continue
            if (y == 0 or not body[y - 1][x][3]) or (x == 0 or not body[y][x - 1][3]):
                px[y][x] = ramp_b[5] if (x + y) % 3 else ramp_b[4]
            elif x + 1 < S.RW and not body[y][x + 1][3] and noise(x, y, seed + 12) > 95:
                px[y][x] = QUARTZ_CRYSTAL[3] if spec.get("crystal_base") else DESERT_RIM[int(noise(x, y, seed + 13) > 150)]
    # Rock cracks & glowing quartz veins
    for i in range(spec.get("crack", 0) + spec.get("veins", 0)):
        cx = rng.randrange(22, 42)
        cy = rng.randrange(max(12, S.GR - 34), S.GR - 8)
        glowing = i >= spec.get("crack", 0) and stage < 2
        for k in range(rng.randrange(5, 10)):
            xx = cx + int(math.sin(k * 0.9 + seed + i) * 1.4)
            yy = cy + k
            if 0 <= xx < S.RW and 0 <= yy < S.RH and px[yy][xx][3]:
                if glowing:
                    glow.emit(px, xx, yy, QUARTZ_CRYSTAL[3], QUARTZ_CRYSTAL[4], 1)
                else:
                    px[yy][xx] = ramp_b[0]

    spires = spec["spires"] if stage == 0 else (spec["spires"][:max(2, len(spec["spires"]) - 1)] if stage == 1 else spec["spires"][:2])
    # Draw back-most spires first, center last
    for si, (ox, by, length, width, ang) in sorted(enumerate(spires), key=lambda it: abs(it[1][4]), reverse=True):
        bx = 32.0 + (ox - 32.0) * f
        base_y = S.GR - (S.GR - by) * f
        _draw_faceted_prism(px, glow, bx, base_y, length, width, ang, stage, seed + si * 29)
    return S.finish_rock(px), glow.done()


def i_palm_wood(px, g):
    pts = bezier((4.0, 11.5), (7.8, 8.2), (11.5, 4.5), n=22)
    stroke(px, pts, 3.0, 2.8, PALM_BARK[1:5])
    stroke(px, [(11.5, 4.5)], 2.6, 2.6, [PALM_BARK[2], PALM_BARK[4], PALM_BARK[5]])
    for k in range(3):
        px[10 - k * 2][5 + k * 2] = PALM_BARK[0]


def i_sun_date(px, g):
    for cx, cy in ((6.2, 9.2), (9.8, 9.4), (8.0, 6.8)):
        F.blob(px, cx, cy, 2.5, 2.8, DATE_RAMP, dither=False)
        px[int(cy) - 1][int(cx) - 1] = DATE_RAMP[4]
    for dx in (-1, 0, 1):
        px[4][8 + dx] = PALM_LEAF[3]
    px[3][8] = PALM_LEAF[4]


def i_oasis_blossom(px, g):
    for dx in range(-4, 5):
        px[12][8 + dx] = LILY_LEAF[2 if abs(dx) < 3 else 1]
    for dy in (10, 11):
        px[dy][8] = LILY_LEAF[3]
    for dx, dy, sh in (
        (0, -4, 4), (-1, -4, 3), (1, -4, 3),
        (-2, -3, 3), (-1, -3, 4), (0, -3, 4), (1, -3, 3), (2, -3, 2),
        (-3, -2, 2), (-2, -2, 3), (-1, -2, 4), (0, -2, 4), (1, -2, 3), (2, -2, 2), (3, -2, 1),
        (-2, -1, 2), (-1, -1, 3), (1, -1, 2), (2, -1, 1),
        (-1, 0, 2), (0, 0, 2), (1, 0, 1),
        (0, 1, 2),
    ):
        px[8 + dy][8 + dx] = LILY_PETAL[sh]
    px[7][8], px[8][8] = LILY_GOLD[2], LILY_GOLD[1]


def i_sun_quartz(px, g):
    # Twin faceted crystal quartz shard cluster
    for dx, h, x0, sh_l, sh_r in ((-2, 8, 6, 4, 2), (1, 11, 9, 5, 3)):
        for y in range(13 - h, 13):
            t = (y - (13 - h)) / max(h, 1.0)
            w = 1 if t < 0.28 else 2
            for ox in range(-w + 1, w + 1):
                px[y][x0 + ox] = QUARTZ_CRYSTAL[sh_l if ox <= 0 else sh_r]
        px[13 - h][x0] = QUARTZ_GOLD
    for x in range(4, 12):
        px[13][x] = SANDSTONE[3 if x < 8 else 2]


# ================================================================== build & preview
def main():
    props, items = ROOT / "props", ROOT / "items"

    # 1. Crown Cactus (5 cols x 6 rows of 112x200 + growth 5 cols x 1 row)
    full_t, full_c, full_gc, full_gt = [], [], [], []
    pick_c, pick_gc = [], []
    for i, s in enumerate(SAGUAROS):
        t, c, gc, gt = build_crown_cactus(i, s, picked=False)
        _, cp, gcp, _ = build_crown_cactus(i, s, picked=True)
        full_t.append(t)
        full_c.append(c)
        full_gc.append(gc)
        full_gt.append(gt)
        pick_c.append(cp)
        pick_gc.append(gcp)
    rows_cactus = [full_t, full_c, full_gc, full_gt, pick_c, pick_gc]
    cactus_sheet = [[CLEAR] * (CW * 5) for _ in range(CH * 6)]
    for r, frames in enumerate(rows_cactus):
        for i, f in enumerate(frames):
            for y in range(CH):
                cactus_sheet[r * CH + y][i * CW : (i + 1) * CW] = f[y]
    write_png(props / "crown_cactus.png", CW * 5, CH * 6, cactus_sheet)
    write_png(props / "crown_cactus_growth.png", CW * 5, CH, build_cactus_growth())

    # 1b. Sun Palm (6 cols x 6 rows of 112x200 + growth 6 cols x 1 row)
    p_full_t, p_full_c, p_full_gc, p_full_gt = [], [], [], []
    p_pick_c, p_pick_gc = [], []
    for i, s in enumerate(SUN_PALMS):
        t, c, gc, gt = build_sun_palm(i, s, picked=False)
        _, cp, gcp, _ = build_sun_palm(i, s, picked=True)
        p_full_t.append(t)
        p_full_c.append(c)
        p_full_gc.append(gc)
        p_full_gt.append(gt)
        p_pick_c.append(cp)
        p_pick_gc.append(gcp)
    rows_palm = [p_full_t, p_full_c, p_full_gc, p_full_gt, p_pick_c, p_pick_gc]
    palm_sheet = [[CLEAR] * (CW * 6) for _ in range(CH * 6)]
    for r, frames in enumerate(rows_palm):
        for i, f in enumerate(frames):
            for y in range(CH):
                palm_sheet[r * CH + y][i * CW : (i + 1) * CW] = f[y]
    write_png(props / "sun_palm.png", CW * 6, CH * 6, palm_sheet)
    write_png(props / "sun_palm_growth.png", CW * 6, CH, build_palm_growth())

    # 2..9 Small & Medium Plants (40x34)
    def save_sheet(name, frames, cols):
        rows = len(frames) // cols
        for idx, (b, g) in enumerate(frames):
            F.fit(name, idx, b)
            F.fit(name + "_glow", idx, g)
        lit = sheet([f[0] for f in frames], cols, rows)
        glow = sheet([f[1] for f in frames], cols, rows)
        write_png(props / f"{name}.png", FW * cols, FH * rows, lit)
        write_png(props / f"{name}_glow.png", FW * cols, FH * rows, glow)
        return frames, cols, rows

    def save_stripped(name, frames, cols):
        for idx, b in enumerate(frames):
            F.fit(name + "_stripped", idx, b)
        write_png(props / f"{name}_stripped.png", FW * cols, FH, sheet(frames, cols, 1))

    all_sheets = {}
    all_sheets["prickly_pear"] = save_sheet(
        "prickly_pear",
        [make_prickly_pear(s, 3100 + i * 19, picked=p) for p in (False, True) for i, s in enumerate(PEARS)],
        5,
    )
    save_stripped("prickly_pear", [make_prickly_pear(s, 3100 + i * 19, stripped=True)[0] for i, s in enumerate(PEARS)], 5)

    all_sheets["barrel_cactus"] = save_sheet(
        "barrel_cactus",
        [make_barrel_cactus(s, 3200 + i * 17) for i, s in enumerate(BARRELS)],
        4,
    )
    save_stripped("barrel_cactus", [make_barrel_cactus(s, 3200 + i * 17, stripped=True)[0] for i, s in enumerate(BARRELS)], 4)

    all_sheets["desert_scrub"] = save_sheet(
        "desert_scrub",
        [make_desert_scrub(s, 3300 + i * 23) for i, s in enumerate(SCRUBS)],
        6,
    )
    save_stripped("desert_scrub", [make_desert_scrub(s, 3300 + i * 23, stripped=True)[0] for i, s in enumerate(SCRUBS)], 6)

    all_sheets["tumble_scrub"] = save_sheet(
        "tumble_scrub",
        [make_tumble_scrub(s, 3400 + i * 29) for i, s in enumerate(TUMBLES)],
        4,
    )
    save_stripped("tumble_scrub", [make_tumble_scrub(s, 3400 + i * 29, stripped=True)[0] for i, s in enumerate(TUMBLES)], 4)

    all_sheets["dune_grass"] = save_sheet(
        "dune_grass",
        [make_dune_grass(s, 3500 + i * 13) for i, s in enumerate(DUNES)],
        5,
    )
    save_stripped("dune_grass", [make_dune_grass(s, 3500 + i * 13, stripped=True)[0] for i, s in enumerate(DUNES)], 5)

    all_sheets["glass_aloe"] = save_sheet(
        "glass_aloe",
        [make_glass_aloe(s, 3600 + i * 31, picked=p) for p in (False, True) for i, s in enumerate(ALOES)],
        4,
    )
    all_sheets["night_cactus"] = save_sheet(
        "night_cactus",
        [make_night_cactus(s, 3700 + i * 37, row_mode=r) for r in (0, 1, 2) for i, s in enumerate(NIGHTS)],
        4,
    )
    all_sheets["sand_tuber"] = save_sheet(
        "sand_tuber",
        [make_sand_tuber(s, 3800 + i * 41, pulled=p) for p in (False, True) for i, s in enumerate(TUBERS)],
        4,
    )
    all_sheets["oasis_reed"] = save_sheet(
        "oasis_reed",
        [make_oasis_reed(s, 3900 + i * 29) for i, s in enumerate(REEDS)],
        5,
    )
    save_stripped("oasis_reed", [make_oasis_reed(s, 3900 + i * 29, stripped=True)[0] for i, s in enumerate(REEDS)], 5)
    all_sheets["oasis_lily"] = save_sheet(
        "oasis_lily",
        [make_oasis_lily(s, 4000 + i * 31, picked=p) for p in (False, True) for i, s in enumerate(LILIES)],
        4,
    )

    # 11. Sun Quartz Rock (6 cols x 4 rows of 64x56 + glow)
    rock_frames = [render_sun_quartz_rock(i, s, st) for st in range(4) for i, s in enumerate(QUARTZ_ROCKS)]
    rock_lit = [[CLEAR] * (S.RW * 6) for _ in range(S.RH * 4)]
    rock_glow = [[CLEAR] * (S.RW * 6) for _ in range(S.RH * 4)]
    for fi, (rl, rg) in enumerate(rock_frames):
        ox, oy = (fi % 6) * S.RW, (fi // 6) * S.RH
        for y in range(S.RH):
            rock_lit[oy + y][ox : ox + S.RW] = rl[y]
            rock_glow[oy + y][ox : ox + S.RW] = rg[y]
    write_png(props / "sun_quartz_rock.png", S.RW * 6, S.RH * 4, rock_lit)
    write_png(props / "sun_quartz_rock_glow.png", S.RW * 6, S.RH * 4, rock_glow)

    assert not F.CUT, "cut off at frame border:\n" + "\n".join(F.CUT)

    # 11 Item Icons (16x16)
    icons = {}
    for name, draw in (
        ("sun_fig", i_sun_fig),
        ("crown_fig", i_crown_fig),
        ("cactus_wood", i_cactus_wood),
        ("cactus_pulp", i_cactus_pulp),
        ("quartz_aloe", i_quartz_aloe),
        ("night_cactus_bloom", i_night_bloom),
        ("sand_tuber", i_sand_tuber),
        ("palm_wood", i_palm_wood),
        ("sun_date", i_sun_date),
        ("oasis_blossom", i_oasis_blossom),
        ("sun_quartz", i_sun_quartz),
    ):
        px = blank(16, 16)
        draw(px, Glow(16, 16))
        check_icon(name, px)
        px = outline_pass(px, ICON_OUT)
        icons[name] = px
        write_png(items / f"{name}.png", 16, 16, px)

    print(f"Desert art: crown_cactus + sun_palm + 10 desert flora + sun_quartz_rock + {len(icons)} icons written cleanly.")
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        write_preview((full_t, full_c, full_gc), all_sheets, icons)
        write_oasis_preview((p_full_t, p_full_c, p_full_gc), all_sheets, rock_frames, icons)


def write_preview(sag_parts, all_sheets, icons):
    """docs/img/desert_flora.png: day on warm desert sand (top) & desert indigo night with glow (bottom)."""
    z = 2
    full_t, full_c, full_gc = sag_parts
    max_small_w = max(FW * cols for (_frames, cols, _rows) in all_sheets.values())
    w = max(CW * 5, FW * 6 + FW * 5 + 32, max_small_w * 2)
    w = max(w, 600)
    h1 = CH + FH * 10 + 48
    day_bg = (212, 168, 102, 255)
    night_bg = (22, 22, 46, 255)
    img = [[day_bg if (y // z) < h1 else night_bg for _ in range(w * z)] for y in range(h1 * 2 * z)]

    def paste(layer, ox, oy, dim=1.0, k=z, additive=False):
        for y, row in enumerate(layer):
            for x, c in enumerate(row):
                if c is None or not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(k):
                    for dx in range(k):
                        X, Y = ox * z + x * k + dx, oy * z + y * k + dy
                        if 0 <= X < w * z and 0 <= Y < len(img):
                            b = img[Y][X]
                            if additive:
                                img[Y][X] = tuple(min(255, int(b[i] + c[i] * a)) for i in range(3)) + (255,)
                            else:
                                img[Y][X] = tuple(int(b[i] * (1 - a) + c[i] * dim * a) for i in range(3)) + (255,)

    for night in (0, 1):
        oy = night * h1
        dim = 0.44 if night else 1.0
        for i in range(5):
            paste(full_t[i], i * CW, oy, dim)
            paste(full_c[i], i * CW, oy, dim)
            if night:
                paste(full_gc[i], i * CW, oy, 1.0, additive=True)
        # Arrange small plant sheets neatly in two columns below the saguaros
        col_x = [8, 280]
        col_y = [CH + 8, CH + 8]
        for idx, (name, (frames, cols, rows)) in enumerate(all_sheets.items()):
            side = idx % 2
            x0, y0 = col_x[side], oy + col_y[side]
            for fi, (base, glow) in enumerate(frames):
                fx = x0 + (fi % cols) * FW
                fy = y0 + (fi // cols) * FH
                paste(base, fx, fy, dim)
                if night:
                    paste(glow, fx, fy, 1.0, additive=True)
            col_y[side] += rows * FH + 8
    for i, px in enumerate(icons.values()):
        paste(px, w - 24 * (len(icons) - i) - 8, h1 - 24, 1.0, k=2)
    out_path = ROOT.parent / "docs" / "img" / "desert_flora.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(out_path, w * z, len(img), img)
    print(f"preview written: {out_path}")


def write_oasis_preview(palm_parts, all_sheets, rock_frames, icons):
    """Focused day + night preview sheet for oasis palms, reeds, lilies, quartz rocks, and 4 icons."""
    z = 2
    p_t, p_c, p_gc = palm_parts
    w = max(CW * 6, S.RW * 6 + 16)
    h1 = CH + FH * 3 + S.RH * 4 + 32
    day_bg = (146, 178, 128, 255)
    night_bg = (20, 26, 46, 255)
    img = [[day_bg if (y // z) < h1 else night_bg for _ in range(w * z)] for y in range(h1 * 2 * z)]

    def paste(layer, ox, oy, dim=1.0, k=z, additive=False):
        for y, row in enumerate(layer):
            for x, c in enumerate(row):
                if c is None or not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(k):
                    for dx in range(k):
                        X, Y = ox * z + x * k + dx, oy * z + y * k + dy
                        if 0 <= X < w * z and 0 <= Y < len(img):
                            b = img[Y][X]
                            if additive:
                                img[Y][X] = tuple(min(255, int(b[i] + c[i] * a)) for i in range(3)) + (255,)
                            else:
                                img[Y][X] = tuple(int(b[i] * (1 - a) + c[i] * dim * a) for i in range(3)) + (255,)

    for night in (0, 1):
        oy = night * h1
        dim = 0.45 if night else 1.0
        for i in range(6):
            paste(p_t[i], i * CW, oy, dim)
            paste(p_c[i], i * CW, oy, dim)
            if night:
                paste(p_gc[i], i * CW, oy, 1.0, additive=True)
        for idx, key in enumerate(("oasis_reed", "oasis_lily")):
            frames, cols, _rows = all_sheets[key]
            x0, y0 = 12 + idx * 240, oy + CH + 6
            for fi, (base, glow) in enumerate(frames):
                fx, fy = x0 + (fi % cols) * FW, y0 + (fi // cols) * FH
                paste(base, fx, fy, dim)
                if night:
                    paste(glow, fx, fy, 1.0, additive=True)
        ry0 = oy + CH + FH * 2 + 16
        for fi, (rl, rg) in enumerate(rock_frames):
            rx, ry = 8 + (fi % 6) * S.RW, ry0 + (fi // 6) * S.RH
            paste(rl, rx, ry, dim)
            if night:
                paste(rg, rx, ry, 1.0, additive=True)
    new_icons = ("palm_wood", "sun_date", "oasis_blossom", "sun_quartz")
    for i, kname in enumerate(new_icons):
        paste(icons[kname], w - 36 * (len(new_icons) - i) - 12, h1 - 36, 1.0, k=z * 2)
    out = type(ROOT)("/Users/nxye/.gemini/antigravity/brain/a4c535af-cedd-4de8-aa92-4c9315390c23/previews_oasis/oasis_sprites.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    write_png(out, w * z, len(img), img)
    print(f"oasis preview written: {out}")


if __name__ == "__main__":
    main()
