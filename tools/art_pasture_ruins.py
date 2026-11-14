#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 2 Habitat 3 — Alte Kulturspuren / Verlassenes Weideland (stdlib only):
  assets/props/orchard_apple.png         3 cols x 6 rows of 112x200 (336x1200), FEET_ROW=196, center x=56
  assets/props/orchard_pear.png          3 cols x 6 rows of 112x200 (336x1200), FEET_ROW=196, center x=56
  assets/props/orchard_apple_growth.png  4 cols x 1 row of 112x200 (448x200), feet at (56, 196)
  assets/props/orchard_pear_growth.png   4 cols x 1 row of 112x200 (448x200), feet at (56, 196)
  assets/props/fallen_fruit.png          6 cols x 1 row of 48x24 (288x24), anchor at (24, 18)
  assets/props/dry_stone_wall.png        6 cols x 4 rows of 64x56 (384x224), feet at (32, 52) [rock.tscn]
  assets/props/dry_stone_wall_glow.png   6 cols x 4 rows of 64x56 (384x224), unlit emissive pixels
  assets/props/broken_fence.png          5 cols x 1 row of 40x34 (200x34), feet at (20, 31) [bush.tscn]
  assets/props/broken_fence_stripped.png 5 cols x 1 row of 40x34 (200x34), low splintered stubs
  assets/props/pasture_paving.png        4 cols x 1 row of 96x64 (384x64), dithered edges (z_index = -9)
  assets/items/meadow_apple.png          16x16 item icon (#1b1a2e outline)
  assets/items/moon_pear.png             16x16 item icon (#1b1a2e outline)
  docs/img/pasture_ruins_sheet.png       Visual QA contact sheet (daylight + night)

Zero #000000 pixels anywhere; stdlib + gen_art.py / art_*.py helpers only.
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
import art_tree  # noqa: E402
from art_bush import bezier, check_icon  # noqa: E402
from art_spruce import CH, CW, FEET_X, FEET_Y, RIM, SHELF, TEAL, TEAL_L, VIO, VIO_L, Emitters, grid, put as sp_put  # noqa: E402
from art_tree import check_bounds, to_pixels  # noqa: E402
from art_willow import lobes_shade  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "pasture_ruins_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

OUT_STONE = hexc("1b1a2e")
OUT_LEAF = hexc("122228")
SHADOW_RGB = (14, 16, 34)

# ---- Palettes (ZERO #000000) ----
# Orchard Apple: warm mossy twisted plum-brown bark + sunlit meadow-green foliage + crimson-gold Wiesenäpfel
APPLE_BARK = [hexc(c) for c in ("1d1324", "362234", "583848", "825966", "b0868e")]
APPLE_LEAF = [hexc(c) for c in ("142436", "1e443c", "2d684a", "448c58", "68b468", "9cdc86", "cef0a4")]
APPLE_FRUIT = [hexc(c) for c in ("6a1830", "9c223c", "c23244", "e85d4a", "f49454", "f6b85c", "fff0a8")]
APPLE_UNRIPE = [hexc(c) for c in ("2d684a", "56985c", "8cc874")]

# Orchard Pear: silver-plum bark + sage-teal foliage + luminous pale-gold/turquoise Mondbirnen
PEAR_BARK = [hexc(c) for c in ("1b182c", "332f48", "544e6a", "7e7894", "aea8be")]
PEAR_LEAF = [hexc(c) for c in ("122038", "183e48", "24625e", "388874", "5cb28e", "90dcb2", "c8f4d4")]
PEAR_FRUIT = [hexc(c) for c in ("246874", "3a9898", "78d8b8", "b6eea8", "d8f6b0", "fff8d0")]
PEAR_UNRIPE = [hexc(c) for c in ("24625e", "489684", "7cc6a8")]

# Dry stone wall & pasture paving (8-step Shadowspore fieldstone ramp + warm weathered sandstone-slate accents)
WALL_STONE = [hexc(c) for c in ("1c1a34", "282548", "3a365f", "4e4978", "665f94", "827ab0", "a69fd0", "d4cfee")]
WARM_STONE = [hexc(c) for c in ("221c34", "342b48", "4c4060", "685a7c", "88789a", "aa9ab8", "ccc0d8", "ece4f2")]
MORTAR = hexc("161328")
MOSS = [hexc(c) for c in ("1a3a34", "265844", "3a7c54", "5ca266", "88ca7c")]
IVY = [hexc(c) for c in ("142c34", "1e4c44", "2e7254", "4c9a66")]
LICHEN = [hexc("628478"), hexc("98bea8")]
FLOWER_GOLD = [hexc("d89e3c"), hexc("f6cc64"), hexc("fff4b8")]
FLOWER_LILAC = [hexc("744acc"), hexc("aa86f6"), hexc("eee2ff")]
FLOWER_ROSE = [hexc("a83c68"), hexc("df7498"), hexc("ffd6e4")]

# Weathered wooden fence & rusty iron hardware
FENCE_WOOD = [hexc(c) for c in ("221828", "38293a", "564254", "7a6372", "a28c96", "cab8be")]
SPLINTER = [hexc(c) for c in ("583e38", "8c6858", "bc987c", "e2c6a6")]
RUST_IRON = [hexc("261c2e"), hexc("4e343e"), hexc("7c5254"), hexc("a47874")]

# Glow accents
GOLD_DIM = hexc("b48a38")
GOLD = hexc("e6c468")
GOLD_HOT = hexc("fff0b0")
TEAL_HOT = hexc("d0fff8")


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        px[y][x] = col


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def hsh(x: int, y: int, s: int) -> float:
    n = (int(x) * 374761393 + int(y) * 668265263 + int(s) * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x: float, y: float, s: int) -> float:
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def fbm(x: float, y: float, s: int) -> float:
    return 0.56 * vnoise(x, y, s) + 0.30 * vnoise(x * 2.1, y * 2.1, s + 11) + 0.14 * vnoise(x * 4.3, y * 4.3, s + 23)


class GlowMap:
    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.px = blank(w, h)
        self.pts = []

    def emit(self, base, x: int, y: int, dim_col, bright_col, halo: int = 1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim_col is not None and base is not None:
                base[y][x] = dim_col
            self.px[y][x] = bright_col
            if halo > 0:
                self.pts.append((x, y, bright_col, halo))

    def finish(self):
        out = [row[:] for row in self.px]
        for cx, cy, col, rad in self.pts:
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    if dx == 0 and dy == 0:
                        continue
                    xx, yy = cx + dx, cy + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h):
                        continue
                    d = math.hypot(dx, dy)
                    if d <= rad + 0.45 and out[yy][xx][3] < 255:
                        a = 98 if d <= 1.2 else (46 if d <= 1.95 else 22)
                        if a > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], a)
        return out


# ==============================================================================
# 1. Heritage Orchard Trees (`orchard_apple.png` & `orchard_pear.png`, 3x6 of 112x200)
#    + Growth sheets (`orchard_apple_growth.png` & `orchard_pear_growth.png`, 4x1 of 112x200)
# ==============================================================================
ORCHARD_VARIANTS = [
    # Variant 0: Gnarled leaning old-pasture tree (height=96, clear=22, crown_hw=32, trunk_hw=5)
    dict(
        height=96, w=64, h=64, clear=22, trunk_hw=5.0, lean=3.0, twist=2.2, twin=False,
        fungi=1, veins=1, hollow=True, fruits=16, tassels=8,
        boughs=[
            (0.44, -0.34, 0.72, 0.56, 0.44),
            (0.58, 0.34, 0.58, 0.58, 0.44),
            (0.76, -0.20, 0.36, 0.62, 0.46),
            (0.92, 0.16, 0.22, 0.56, 0.42),
            (0.98, -0.02, 0.14, 0.48, 0.38),
        ],
    ),
    # Variant 1: Wide pruned goblet-crown heritage orchard tree (height=108, clear=25, crown_hw=36, trunk_hw=6)
    dict(
        height=108, w=72, h=72, clear=25, trunk_hw=6.0, lean=-2.6, twist=2.6, twin=True,
        fungi=2, veins=1, hollow=True, fruits=21, tassels=10,
        boughs=[
            (0.42, -0.36, 0.74, 0.54, 0.42),
            (0.50, 0.36, 0.64, 0.56, 0.42),
            (0.68, -0.24, 0.44, 0.58, 0.44),
            (0.78, 0.24, 0.34, 0.58, 0.44),
            (0.94, -0.08, 0.18, 0.54, 0.40),
            (0.62, 0.02, 0.52, 0.50, 0.40),
        ],
    ),
    # Variant 2: Tall gnarled matriarch fruit tree (height=118, clear=28, crown_hw=40, trunk_hw=7)
    dict(
        height=118, w=80, h=80, clear=28, trunk_hw=7.0, lean=2.4, twist=3.0, twin=False,
        fungi=3, veins=2, hollow=True, fruits=25, tassels=12,
        boughs=[
            (0.40, -0.38, 0.76, 0.52, 0.40),
            (0.52, 0.38, 0.66, 0.54, 0.42),
            (0.66, -0.26, 0.48, 0.56, 0.42),
            (0.76, 0.26, 0.36, 0.56, 0.42),
            (0.88, -0.12, 0.22, 0.56, 0.42),
            (0.97, 0.10, 0.14, 0.50, 0.38),
            (0.60, 0.00, 0.54, 0.50, 0.40),
        ],
    ),
]

ORCHARD_SAPLING = dict(
    height=40, w=26, h=22, clear=9, trunk_hw=1.8, lean=1.4, twist=0.7, twin=False,
    fungi=0, veins=0, hollow=False, fruits=0, tassels=2,
    boughs=[(0.54, -0.24, 0.62, 0.64, 0.52), (0.92, 0.22, 0.26, 0.68, 0.54)],
)

ORCHARD_YOUNG = dict(
    height=68, w=44, h=40, clear=14, trunk_hw=3.2, lean=-1.8, twist=1.3, twin=False,
    fungi=0, veins=0, hollow=False, fruits=4, tassels=4,
    boughs=[(0.46, -0.28, 0.66, 0.60, 0.48), (0.74, 0.26, 0.36, 0.64, 0.50), (0.95, -0.04, 0.18, 0.54, 0.44)],
)


def _draw_branch_curve(target_grid, pts, r0: float, r1: float, bark):
    n = max(len(pts) - 1, 1)
    for i, (fx, fy) in enumerate(pts):
        t = i / float(n)
        rad = r0 + (r1 - r0) * t
        cx, cy = int(round(fx)), int(round(fy))
        ir = int(math.ceil(rad))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= (rad + 0.25) ** 2:
                    lit = -0.55 * dx - 0.75 * dy
                    tone = 3 if lit > 0.45 else (2 if lit > -0.25 else 1)
                    if dy >= ir and rad >= 1.1:
                        tone = 0
                    sp_put(target_grid, cx + dx, cy + dy, bark[tone])


def draw_apple_cluster(crown, lights_c, cx: int, cy: int, ripe: bool, extras: bool):
    """Draws a crisp, round 4x4 shaded Wiesenapfel nestled in leaves with stem & warm golden cheek."""
    if not ripe:
        for dx, dy, ci in [(0, 0, 2), (1, 0, 1), (0, 1, 1), (1, 1, 0)]:
            sp_put(crown, cx + dx, cy + dy, APPLE_UNRIPE[ci])
        return
    # Tiny dark stem & sunlit leaf glint above
    sp_put(crown, cx, cy - 2, APPLE_BARK[1])
    sp_put(crown, cx + 1, cy - 2, APPLE_LEAF[5])
    # Plump 4x4 crimson-gold meadow apple (top-left golden-blush highlight -> rich crimson -> deep ruby shade)
    apple_px = [
        (-1, -1, 5), (0, -1, 6), (1, -1, 3),
        (-2, 0, 4), (-1, 0, 5), (0, 0, 3), (1, 0, 2),
        (-2, 1, 3), (-1, 1, 3), (0, 1, 2), (1, 1, 1),
        (-1, 2, 2), (0, 2, 1), (1, 2, 0),
    ]
    for dx, dy, ci in apple_px:
        sp_put(crown, cx + dx, cy + dy, APPLE_FRUIT[ci])
    if extras:
        # Subtle warm golden sun-stored night glint on the upper-left cheek of select apples
        lights_c.pixel(crown, cx - 1, cy, APPLE_FRUIT[5], GOLD, halo=1)


def draw_pear_cluster(crown, lights_c, cx: int, cy: int, ripe: bool, extras: bool):
    """Draws a teardrop-shaped 4x5 bioluminescent Mondbirne hanging from the bough."""
    if not ripe:
        for dx, dy, ci in [(0, 0, 2), (0, 1, 1), (-1, 1, 2), (0, 2, 0)]:
            sp_put(crown, cx + dx, cy + dy, PEAR_UNRIPE[ci])
        return
    # Stem & narrow pear neck widening into a plump glowing turquoise-gold belly
    sp_put(crown, cx, cy - 2, PEAR_BARK[1])
    pear_px = [
        (0, -1, 4), (1, -1, 2),
        (-1, 0, 5), (0, 0, 4), (1, 0, 2),
        (-1, 1, 4), (0, 1, 3), (1, 1, 1), (2, 1, 0),
        (-1, 2, 3), (0, 2, 2), (1, 2, 1),
        (0, 3, 1),
    ]
    for dx, dy, ci in pear_px:
        sp_put(crown, cx + dx, cy + dy, PEAR_FRUIT[ci])
    if extras:
        lights_c.pixel(crown, cx - 1, cy, PEAR_FRUIT[5], PEAR_FRUIT[5], halo=2)
        lights_c.pixel(crown, cx, cy + 1, PEAR_FRUIT[3], TEAL_L, halo=1)


def build_orchard_tree(spec: dict, seed: int, kind: str, picked: bool = False, extras: bool = True):
    """100% compatible with `art_blossom.py` & `tree.tscn` (`112x200`, `FEET_Y=196`, `FEET_X=56`)."""
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)

    is_apple = (kind == "apple")
    bark = APPLE_BARK if is_apple else PEAR_BARK
    leaf_ramp = APPLE_LEAF if is_apple else PEAR_LEAF

    height, w, h = spec["height"], min(spec["w"], 100), spec["h"]
    clear = spec["clear"]
    hw = spec["trunk_hw"]
    lean = spec["lean"]
    top_y = max(5, FEET_Y - height)
    leader_top = int(top_y + h * 0.25)

    # 1. Gnarled pruned-long-ago orchard trunk(s) with twisted bark, pruning knots & moss
    stems = [(-1, -2.0), (1, 2.0)] if spec.get("twin") else [(0, 0.0)]
    stem_spines = []
    centers = {}
    for si, (sd, x_base_off) in enumerate(stems):
        phase = rng.uniform(0.0, 5.0)
        stem_hw = hw * (0.76 if spec.get("twin") else 1.0)
        spine = {}
        for y in range(leader_top, FEET_Y + 1):
            t_up = (FEET_Y - y) / max(1.0, float(FEET_Y - leader_top))
            curve = lean * (t_up ** 1.15) * (0.65 if spec.get("twin") else 1.0)
            curve += spec["twist"] * math.sin(t_up * 3.3 + phase) * 0.80
            if spec.get("twin"):
                curve += sd * (1.2 + 8.5 * (t_up ** 0.85))
            cx_f = FEET_X + x_base_off + curve
            flare = max(0.0, (y - (FEET_Y - 10)) * 0.72)
            # Subtle old pruning-collar bulge just below crown fork!
            collar = 1.25 if abs(y - (FEET_Y - clear + 3)) <= 2 else 0.0
            cur_hw = stem_hw * (1.0 - 0.70 * (t_up ** 1.08)) + flare + collar * 0.45
            spine[y] = (cx_f, cur_hw)
            if si == 0 or y not in centers:
                centers[y] = (int(round(cx_f)), cur_hw)
            dest = trunk if y > FEET_Y - clear - int(h * 0.34) else crown
            for dx in range(-int(cur_hw) - 1, int(cur_hw) + 2):
                if abs(dx) > cur_hw:
                    continue
                x = int(round(cx_f)) + dx
                if not (3 <= x < CW - 3):
                    continue
                lit = 0.56 - 0.52 * dx / max(1.0, cur_hw)
                ridge = (dx + int(noise(y // 4, si, seed + 2) % 3)) % 3 == 0
                v = lit * 4.15 + (noise(x, y, seed + 3) / 255.0 - 0.5) * 0.82 - (0.85 if ridge else 0.0)
                col = bark[int(clamp(v, 0, 4))]
                if y > FEET_Y - 15 and dx < 2 and noise(x, y, seed + 8) > 138:
                    col = sp.MOSS[2 if lit > 0.55 else (1 if lit > 0.35 else 0)]
                sp_put(dest, x, y, col)
        stem_spines.append(spine)

    sp._roots(trunk, bark, hw, lights_t, dict(violet=0.08), extras)

    if extras:
        # Trunk moss glints & shelf fungi (Row 0 + Row 3 trunk glow)
        for v_i in range(spec["veins"]):
            y0 = FEET_Y - int(clear * rng.uniform(0.18, 0.48))
            for k in range(int(clear * 0.52)):
                yy = y0 - k
                if yy not in centers or yy <= FEET_Y - clear - 4:
                    break
                cx_t, chw = centers[yy]
                xx = cx_t + int(round(math.sin(k * 0.45 + v_i * 1.9) * 1.2))
                if abs(xx - cx_t) < chw - 0.6 and trunk[yy][xx] is not None:
                    if is_apple:
                        lights_t.pixel(trunk, xx, yy, sp.MOSS[2], GOLD if k % 3 == 0 else TEAL_L, 1)
                    else:
                        lights_t.pixel(trunk, xx, yy, TEAL, TEAL_L, 1)

        for f_i in range(spec["fungi"]):
            yy = FEET_Y - int(clear * rng.uniform(0.24, 0.82))
            if yy in centers:
                cx_t, chw = centers[yy]
                side = -1 if f_i % 2 else 1
                for i in range(4):
                    x = cx_t + side * (int(chw) + i)
                    sp_put(trunk, x, yy + (1 if i > 2 else 0), SHELF[1])
                    sp_put(trunk, x, yy + 1 + (1 if i > 2 else 0), SHELF[0])
                    lights_t.pixel(trunk, x, yy - (1 if 0 < i < 3 else 0), SHELF[2], TEAL_L, 1)

        if spec["hollow"] and (FEET_Y - int(clear * 0.50)) in centers:
            hy = FEET_Y - int(clear * 0.50)
            cx_t, _ = centers[hy]
            for dy in range(-3, 4):
                for dx in range(-2, 3):
                    d = (dx / 2.1) ** 2 + (dy / 3.2) ** 2
                    if d <= 1.0:
                        sp_put(trunk, cx_t + dx, hy + dy, bark[0] if d < 0.58 else bark[3 if dx < 0 else 2])
            lights_t.pixel(trunk, cx_t, hy, GOLD if is_apple else TEAL_L, GOLD_HOT if is_apple else TEAL_HOT, 2)

    # 2. Crooked pruned orchard boughs
    crown_cx = max(int(w * 0.5) + 5, min(CW - int(w * 0.5) - 5, FEET_X + int(round(lean * 0.65))))
    bough_pads = []
    exposed_elbows = []
    for bi, (att_t, dx_f, y_f, wf, hf) in enumerate(spec["boughs"]):
        bx = max(10.0, min(CW - 11.0, crown_cx + dx_f * w * 0.90))
        by = max(9.0, top_y + y_f * h)
        pw = max(10.5, w * wf * 0.5)
        ph = max(7.5, h * hf * 0.5)
        bough_pads.append((bx, by, pw, ph, bi))

        spine = stem_spines[(0 if dx_f < 0 else 1) if spec.get("twin") else 0]
        ay = int(round(FEET_Y - att_t * (FEET_Y - leader_top)))
        ay = max(leader_top + 2, min(FEET_Y - max(9, int(clear * 0.70)), ay))
        ax, ahw = spine.get(ay, (float(FEET_X), hw * 0.5))
        ctrl_x = ax + (bx - ax) * 0.58 + rng.uniform(-2.2, 2.2)
        ctrl_y = min(ay, by) - rng.uniform(1.5, 4.5) if by < ay else (ay + by) * 0.5 - 2.5
        pts = bezier((ax, ay), (ctrl_x, ctrl_y), (bx, by + ph * 0.12), n=26)
        r_start = max(1.1, min(ahw * 0.72, hw * 0.46))
        _draw_branch_curve(trunk, pts[:7], r_start, max(0.9, r_start * 0.72), bark)
        _draw_branch_curve(crown, pts[5:], max(1.0, r_start * 0.75), 0.65, bark)
        exposed_elbows.append(pts[6:16])

    # 3. Terraced, multi-clump leafy orchard dome (`lobes_shade` with Bayer 4x4 dither + 2px cluster grain)
    leaf_lobes = []
    for bx, by, pw, ph, bi in bough_pads:
        leaf_lobes.append((bx, by, pw * 0.68, ph * 0.56, -7.5 - bi * 1.1))
        n_clumps = max(10, int(pw * ph / 11.5))
        for k in range(n_clumps):
            a = rng.uniform(0.0, math.tau)
            r = rng.random() ** 0.60
            lx = max(6.0, min(CW - 7.0, bx + math.cos(a) * pw * r))
            ly = max(6.0, by + math.sin(a) * ph * r * (0.90 if math.sin(a) < 0 else 0.74))
            sz = rng.uniform(2.8, 5.4) * (0.80 + 0.22 * w / 85.0)
            depth_bias = -bi * 1.1 + (2.5 if math.sin(a) < -0.12 else -0.8) + (k % 3) * 0.35
            leaf_lobes.append((lx, ly, sz * 1.22, sz * 0.86, depth_bias))
        for side in (-1, 1):
            ox = max(6.0, min(CW - 7.0, bx + side * (pw * 0.92 + rng.uniform(0.5, 2.0))))
            oy = max(6.0, by + rng.uniform(-1.0, 2.5))
            leaf_lobes.append((ox, oy, rng.uniform(2.4, 3.6), rng.uniform(1.9, 2.8), 2.4))

    leaf_grid = grid()
    lobes_shade(leaf_grid, leaf_lobes, leaf_ramp, seed + 5, -0.15)
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            if leaf_grid[y][x] is not None:
                crown[y][x] = leaf_grid[y][x]

    # Glimpses of dark crooked orchard bough elbows peeking through deep shadow crevices
    for seg in exposed_elbows:
        for k, (fx, fy) in enumerate(seg[:6]):
            ix, iy = int(round(fx)), int(round(fy))
            if 5 <= ix < CW - 5 and 5 <= iy < CH - 5 and crown[iy][ix] in (None, leaf_ramp[0], leaf_ramp[1]):
                sp_put(crown, ix, iy, bark[2 if k % 2 else 1])
                sp_put(crown, ix, iy + 1, bark[0])

    # Top-left sunlit leaf contours & cool twilight teal right-rim bounce
    snap = [row[:] for row in crown]
    top_idx = len(leaf_ramp) - 1
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            c = snap[y][x]
            if c is None or c not in leaf_ramp:
                continue
            k = leaf_ramp.index(c)
            if snap[y - 1][x] is None and k < top_idx:
                crown[y][x] = leaf_ramp[min(k + 2, top_idx)]
            elif snap[y][x - 1] is None and k < top_idx - 1:
                crown[y][x] = leaf_ramp[k + 1]
            elif snap[y][x + 1] is None and noise(x, y, seed + 9) > 95 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 155)]

    # Hanging leafy orchard shoots along lower hems
    leaf_hems = [
        (x, y)
        for y in range(8, FEET_Y - 10)
        for x in range(6, CW - 6)
        if crown[y][x] in leaf_ramp[:5] and crown[y + 1][x] is None and trunk[y + 1][x] is None
    ]
    rng.shuffle(leaf_hems)
    for hx, hy in leaf_hems[:spec["tassels"]]:
        ln = rng.randint(2, 4)
        for k in range(1, ln + 1):
            if hy + k < FEET_Y - 6:
                sp_put(crown, hx + (1 if k == ln and hx % 2 == 0 else 0), hy + k, leaf_ramp[4 if k == ln else 2], over=False)

    # 4. Ripe Crimson-Gold Wiesenäpfel / Luminous Mondbirnen (Row 1 + Row 2) OR Picked State (Row 4 + Row 5)
    candidates = [
        (x, y)
        for y in range(int(top_y + 6), int(FEET_Y - clear + 4))
        for x in range(10, CW - 10)
        if crown[y][x] in leaf_ramp[1:6]
        and crown[y - 2][x] is not None
        and crown[y + 2][x] is not None
        and crown[y][x - 2] is not None
        and crown[y][x + 2] is not None
    ]
    rng.shuffle(candidates)
    placed_fruits = []

    if not picked:
        target_n = spec["fruits"]
        for fx_p, fy_p in candidates:
            if len(placed_fruits) >= target_n:
                break
            if any(abs(fx_p - ux) < 7 and abs(fy_p - uy) < 7 for ux, uy in placed_fruits):
                continue
            placed_fruits.append((fx_p, fy_p))
            if is_apple:
                draw_apple_cluster(crown, lights_c, fx_p, fy_p, ripe=True, extras=extras and (len(placed_fruits) % 3 == 1))
            else:
                draw_pear_cluster(crown, lights_c, fx_p, fy_p, ripe=True, extras=extras)
        # Extra soft firefly/dew glints in unpicked crown glow
        if extras and candidates:
            for i_g in range(4):
                gx, gy = candidates[(i_g * 17 + 5) % len(candidates)]
                if all(abs(gx - ux) > 4 or abs(gy - uy) > 4 for ux, uy in placed_fruits):
                    lights_c.pixel(crown, gx, gy, GOLD_DIM if is_apple else TEAL, GOLD_HOT if is_apple else TEAL_L, 1)
    else:
        # Picked crown (`Row 4`): only 1–2 tiny unripe fruits left + dim night glints (`Row 5`)
        n_shy = 2 if spec["fruits"] > 0 else 0
        for fx_p, fy_p in candidates:
            if len(placed_fruits) >= n_shy:
                break
            if any(abs(fx_p - ux) < 12 for ux, _ in placed_fruits):
                continue
            placed_fruits.append((fx_p, fy_p))
            if is_apple:
                draw_apple_cluster(crown, lights_c, fx_p, fy_p, ripe=False, extras=False)
            else:
                draw_pear_cluster(crown, lights_c, fx_p, fy_p, ripe=False, extras=False)
        if extras and candidates:
            for i_g in range(2):
                gx, gy = candidates[(i_g * 23 + 3) % len(candidates)]
                lights_c.pixel(crown, gx, gy, TEAL, TEAL_L if not is_apple else GOLD, 1)

    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}


def build_orchard_sheets(kind: str, seed_base: int):
    bark = APPLE_BARK if kind == "apple" else PEAR_BARK
    unpicked = [build_orchard_tree(s, seed_base + i * 13, kind, picked=False) for i, s in enumerate(ORCHARD_VARIANTS)]
    picked = [build_orchard_tree(s, seed_base + i * 13, kind, picked=True) for i, s in enumerate(ORCHARD_VARIANTS)]
    lit_u = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(unpicked, ORCHARD_VARIANTS)]
    lit_p = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(picked, ORCHARD_VARIANTS)]
    check_bounds(f"orchard_{kind}", lit_u)
    check_bounds(f"orchard_{kind}_picked", lit_p)

    rows = [
        [t for t, _ in lit_u],
        [c for _, c in lit_u],
        [to_pixels(p["glow_crown"]) for p in unpicked],
        [to_pixels(p["glow_trunk"]) for p in unpicked],
        [c for _, c in lit_p],
        [to_pixels(p["glow_crown"]) for p in picked],
    ]
    sheet = blank(CW * 3, CH * 6)
    for r, frames in enumerate(rows):
        for col, f in enumerate(frames):
            for y in range(CH):
                sheet[r * CH + y][col * CW:(col + 1) * CW] = f[y]

    # Growth sheet: 4 cols x 1 row of 112x200 (0 small stump, 1 gnarled stump, 2 sapling, 3 young fruit tree)
    g_frames = []
    old_bark = art_tree.BARK
    art_tree.BARK = bark
    try:
        g_frames.append(art_tree.stump(4.8, 3)[0])
        g_frames.append(art_tree.stump(8.4, 3)[0])
    finally:
        art_tree.BARK = old_bark

    for g_spec, g_seed in ((ORCHARD_SAPLING, seed_base + 71), (ORCHARD_YOUNG, seed_base + 79)):
        parts = build_orchard_tree(g_spec, g_seed, kind, picked=False, extras=False)
        t_fin, c_fin = art_tree.finish(parts["trunk"], parts["crown"], g_spec["w"] / 2.0 + 2.0)
        merged = [[c_fin[y][x] if c_fin[y][x][3] else t_fin[y][x] for x in range(CW)] for y in range(CH)]
        g_frames.append(merged)

    growth_sheet = blank(CW * 4, CH)
    for col, f in enumerate(g_frames):
        for y in range(CH):
            growth_sheet[y][col * CW:(col + 1) * CW] = f[y]

    return sheet, growth_sheet, lit_u, unpicked


# ==============================================================================
# 2. Fallen Fruit (`assets/props/fallen_fruit.png`: 6 cols x 1 row of 48x24, anchor (24, 18))
# ==============================================================================
def build_fallen_fruit():
    fw, fh = 48, 24
    ax, ay = 24, 18
    sheet = blank(fw * 6, fh)

    apple_layouts = [
        [(-9, -1), (2, 1), (10, -2)],
        [(-11, 0), (-3, -2), (5, 1), (12, -1)],
        [(-6, 1), (4, -1), (9, 1)],
    ]
    pear_layouts = [
        [(-9, 0), (1, -2), (10, 0)],
        [(-11, -1), (-2, 1), (6, -2), (12, 0)],
        [(-7, 0), (3, 1), (10, -1)],
    ]

    for col in range(6):
        body = blank(fw, fh)
        sh_layer = blank(fw, fh)
        is_apple = col < 3
        positions = apple_layouts[col] if is_apple else pear_layouts[col - 3]
        leaf_pal = APPLE_LEAF if is_apple else PEAR_LEAF

        # Soft ground shadow + fallen orchard leaves & meadow grass blades nestled around the fruits
        for fx_off, fy_off in positions:
            cx, cy = ax + fx_off, ay + fy_off
            for y in range(max(0, cy - 2), min(fh, cy + 5)):
                for x in range(max(0, cx - 6), min(fw, cx + 7)):
                    d = ((x - cx) / 5.5) ** 2 + ((y - (cy + 1.6)) / 2.2) ** 2
                    if d < 1.0:
                        a = 104 if d < 0.5 else 54
                        if a > sh_layer[y][x][3]:
                            sh_layer[y][x] = (*SHADOW_RGB, a)

            # Fallen leaf & grass tuft framing each fruit
            for bdx, bdy, li in [(-4, 0, 3), (-3, -1, 5), (-2, 0, 2), (3, 0, 4), (4, -1, 5), (2, 1, 2)]:
                put(body, cx + bdx, cy + bdy, leaf_pal[li])

        # Draw each plump 4x4 / 5x4 fruit on top
        for idx_f, (fx_off, fy_off) in enumerate(positions):
            cx, cy = ax + fx_off, ay + fy_off
            if is_apple:
                for dx, dy, ci in [
                    (-1, -3, 5), (0, -3, 6), (1, -3, 3),
                    (-2, -2, 4), (-1, -2, 5), (0, -2, 3), (1, -2, 2),
                    (-2, -1, 3), (-1, -1, 2), (0, -1, 1), (1, -1, 0),
                    (-1, 0, 1), (0, 0, 0),
                ]:
                    put(body, cx + dx, cy + dy, APPLE_FRUIT[ci])
                put(body, cx, cy - 4, APPLE_BARK[1])
                if idx_f % 2 == 0:
                    put(body, cx + 1, cy - 4, APPLE_LEAF[5])
            else:
                # Fallen Mondbirne lying slightly tilted on its side with luminous pale-gold/turquoise belly
                for dx, dy, ci in [
                    (-1, -3, 5), (0, -3, 4),
                    (-2, -2, 5), (-1, -2, 4), (0, -2, 3), (1, -2, 2),
                    (-2, -1, 4), (-1, -1, 3), (0, -1, 2), (1, -1, 1), (2, -1, 1),
                    (-1, 0, 2), (0, 0, 1), (1, 0, 0),
                ]:
                    put(body, cx + dx, cy + dy, PEAR_FRUIT[ci])
                put(body, cx + 2, cy - 2, PEAR_BARK[1])

        framed = outline_pass(body, OUT_STONE)
        for y in range(fh):
            for x in range(fw):
                c = framed[y][x] if framed[y][x][3] > 0 else sh_layer[y][x]
                sheet[y][col * fw + x] = c

    return sheet


# ==============================================================================
# 3. Dry Stone Wall (`dry_stone_wall.png` & `_glow.png`: 6 cols x 4 rows of 64x56, feet (32, 52))
#    100% compatible with `rock.tscn` (`stage` 0=intact, 1=chipped, 2=half-tumbled, 3=walkable rubble)!
# ==============================================================================
WW, WH = 64, 56
WFX, WFY = 32, 52


def draw_fieldstone(px, stone_mask, cx: float, cy: float, rx: float, ry: float, seed: int, warm: bool = False, tilt: float = 0.0):
    """Draws a single fitted irregular dry-laid fieldstone with dark mortar/crevice rim, sunlit top-left bevel,
    multi-octave fbm + Bayer 4x4 stone grain, and occasional pitting/lichen!
    """
    pal = WARM_STONE if warm else WALL_STONE
    tone_shift = (hsh(int(cx * 3), int(cy * 3), seed) - 0.5) * 0.95
    x0 = max(2, int(cx - rx - 2))
    x1 = min(WW - 3, int(cx + rx + 3))
    y0 = max(2, int(cy - ry - 2))
    y1 = min(WH - 2, int(cy + ry + 3))
    ca, sa = math.cos(tilt), math.sin(tilt)

    # First pass: dark dry-laid crevice rim so adjacent stones have unmistakable hand-fitted separation!
    interior = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx0, dy0 = x + 0.5 - cx, y + 0.5 - cy
            rx_p = (dx0 * ca + dy0 * sa) / max(1.0, rx)
            ry_p = (-dx0 * sa + dy0 * ca) / max(1.0, ry)
            ang = math.atan2(ry_p, rx_p)
            warp = 1.0 + 0.10 * math.sin(ang * 3.0 + seed) + 0.06 * math.cos(ang * 5.0 - seed * 2)
            # Squared-off ashlar/fieldstone super-ellipse (`|x|^2.4 + |y|^2.4`) so stones pack tightly like a real wall!
            d = ((abs(rx_p) ** 2.35 + abs(ry_p) ** 2.35) ** (1.0 / 2.35)) / warp
            if d <= 1.04:
                if d > 0.85:
                    put(px, x, y, MORTAR)
                    stone_mask[y][x] = 1
                else:
                    interior.append((x, y, rx_p, ry_p, d))

    for x, y, rx_p, ry_p, d in interior:
        nz = math.sqrt(max(0.02, 1.0 - min(0.98, d * d)))
        lit = -0.52 * rx_p - 0.78 * ry_p + 0.48 * nz
        # Crisp sunlit bevel along upper-left facet of each individual fieldstone!
        if ry_p < -0.42 and rx_p < 0.35:
            lit += 0.38
        elif rx_p < -0.45 and ry_p < 0.30:
            lit += 0.24
        if ry_p > 0.48:
            lit -= 0.34
        grain = (fbm(x * 0.62, y * 0.62, seed + 7) - 0.5) * 0.85
        dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
        idx = int(clamp((lit + 0.58) * 4.4 + tone_shift + grain + dith, 0, 7))
        col = pal[idx]
        if hsh(x, y, seed + 19) < 0.035 and idx >= 2:
            col = pal[max(0, idx - 2)]
        put(px, x, y, col)
        stone_mask[y][x] = 2


def drape_wall_moss(px, stone_mask, x0: int, x1: int, y_cap: int, thickness: int, seed: int, hang: int = 3):
    """Drapes velvety multi-tone moss cushion along a wall crest with damp darkened stone fringe underneath."""
    for x in range(max(3, x0), min(WW - 3, x1 + 1)):
        drop = int(hang * max(0.0, math.sin(x * 0.38 + seed) * 0.65 + 0.35 * hsh(x, y_cap, seed + 3)))
        top_j = -1 if hsh(x, 0, seed + 5) > 0.55 else 0
        for y in range(y_cap + top_j, y_cap + thickness + drop + 1):
            if not (2 <= y < WH - 2):
                continue
            if y > y_cap + 1 and stone_mask[y][x] == 0:
                continue
            u_y = (y - (y_cap + top_j)) / max(1.0, float(thickness + drop))
            lit = (1.0 - u_y) * 0.72 + (0.22 if x < WFX + 4 else 0.04) + (fbm(x * 0.5, y * 0.5, seed + 9) - 0.5) * 0.45
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
            mi = int(clamp(lit * 4.6 + dith, 0, 4))
            put(px, x, y, MOSS[mi])
            stone_mask[y][x] = 3
        # Damp darkened stone fringe 1px below the moss hem
        fy = y_cap + thickness + drop + 1
        if 2 <= fy < WH - 2 and stone_mask[fy][x] == 2 and px[fy][x] in WALL_STONE[2:]:
            k = WALL_STONE.index(px[fy][x])
            px[fy][x] = WALL_STONE[max(0, k - 2)]


def build_wall_cell(variant: int, stage: int):
    """Builds one `64x56` cell of `dry_stone_wall.png` + `_glow.png` for `variant` 0..5 and damage `stage` 0..3."""
    seed = 700 + variant * 41 + stage * 13
    rng = random.Random(seed)
    body = blank(WW, WH)
    mask = [[0] * WW for _ in range(WH)]
    glow = GlowMap(WW, WH)

    # Stage 3 (`rock.gd` walkable rubble): low scattered mossy cobbles & pebbles across the ground (`y = 43..53`)
    if stage == 3:
        rubble_specs = [
            (-19, -2, 4.4, 2.4), (-11, 0, 5.0, 2.6), (-3, -3, 4.2, 2.3),
            (5, 0, 5.2, 2.7), (14, -2, 4.5, 2.4), (20, 0, 3.6, 2.0),
            (-7, 2, 3.4, 1.9), (9, 2, 3.6, 1.9), (0, -1, 3.8, 2.1),
        ]
        if variant == 3:  # N-S foreshortened rubble line
            rubble_specs = [(-4, -10, 4.5, 2.4), (3, -8, 4.2, 2.3), (-3, -4, 5.0, 2.6), (4, -2, 4.4, 2.4), (-2, 1, 4.8, 2.5), (3, 2, 3.8, 2.0)]
        elif variant == 2:  # Pillar rubble cluster
            rubble_specs = [(-9, -2, 5.0, 2.6), (0, -4, 5.4, 2.8), (8, -1, 4.8, 2.5), (-4, 1, 4.4, 2.3), (5, 2, 4.0, 2.1)]

        for i_r, (dx, dy, rx, ry) in enumerate(rubble_specs):
            draw_fieldstone(body, mask, WFX + dx + rng.uniform(-0.8, 0.8), WFY - 3 + dy, rx, ry, seed + i_r * 7, warm=(i_r % 3 == 0))
            if i_r % 2 == 0:
                put(body, int(WFX + dx - 1), int(WFY - 4 + dy), MOSS[3])
                put(body, int(WFX + dx), int(WFY - 4 + dy), MOSS[2])
        # Grass blades poking between walkable rubble stones
        for gx_off in (-15, -5, 4, 13):
            if variant == 3 and abs(gx_off) > 7:
                continue
            put(body, WFX + gx_off, WFY - 2, MOSS[2])
            put(body, WFX + gx_off - 1, WFY - 3, MOSS[4])
            put(body, WFX + gx_off + 1, WFY - 3, MOSS[3])

        sh = blank(WW, WH)
        rx_sh = 13.0 if variant == 3 else (17.0 if variant == 2 else 25.0)
        for y in range(WFY - 8, WH):
            for x in range(WW):
                d = ((x - WFX) / rx_sh) ** 2 + ((y - (WFY - 1.5)) / 4.2) ** 2
                if d < 1.0:
                    sh[y][x] = (*SHADOW_RGB, 88 if d < 0.5 else 46)
        framed = outline_pass(body, OUT_STONE)
        out = [[framed[y][x] if framed[y][x][3] > 0 else sh[y][x] for x in range(WW)] for y in range(WH)]
        return out, glow.finish()

    # Stages 0 (intact), 1 (chipped), 2 (half-tumbled):
    max_courses = 4 if stage == 0 else (3 if stage == 1 else 2)

    if variant in (0, 1, 4):
        # E-W fieldstone wall (~54 px wide: x = 5..59, base at y = 51, courses rising up to y ~ 30)
        courses = [
            # Course 0 (heavy foundation boulders at y = 48..52)
            [(10, 48.5, 5.8, 3.3), (20, 48.8, 6.2, 3.4), (31, 48.6, 6.4, 3.4), (42, 48.8, 6.0, 3.3), (53, 48.5, 5.8, 3.3)],
            # Course 1 (staggered mid-lower course at y = 43.2)
            [(13, 43.4, 6.0, 3.1), (24, 43.6, 6.2, 3.1), (36, 43.5, 6.4, 3.2), (48, 43.4, 6.0, 3.1), (56, 44.0, 4.2, 2.8), (7, 44.0, 4.2, 2.8)],
            # Course 2 (upper-mid course at y = 38.4)
            [(10, 38.6, 5.6, 3.0), (20, 38.5, 5.8, 3.0), (31, 38.7, 6.0, 3.0), (42, 38.5, 5.8, 3.0), (52, 38.7, 5.6, 3.0)],
            # Course 3 (heavy flat coping stones / capstones along top at y = 34.0)
            [(11, 34.2, 5.8, 2.7), (22, 34.0, 6.2, 2.7), (33, 34.1, 6.0, 2.7), (44, 34.0, 6.0, 2.7), (53, 34.3, 5.0, 2.6)],
        ]
        for ci in range(max_courses):
            for si_s, (sx, sy, srx, sry) in enumerate(courses[ci]):
                # Variant 1 has a picturesque sunken central breach (`x = 26..40` missing upper courses)!
                if variant == 1 and ci >= 2 and 25 <= sx <= 39:
                    continue
                if variant == 1 and ci == 1 and 29 <= sx <= 37:
                    sy += 1.6
                # Stage 1 chips off 1–2 top-right capstones; Stage 2 tumbles irregular stones
                if stage == 1 and ci == max_courses - 1 and si_s in (2, 4):
                    continue
                if stage == 2 and ci == max_courses - 1 and si_s == 3:
                    continue
                draw_fieldstone(body, mask, sx + rng.uniform(-0.4, 0.4), sy, srx, sry, seed + ci * 17 + si_s * 5, warm=((ci + si_s) % 3 == 1))

        # Tumbled stones at base for Variant 1 breach or Stage 1/2 damage
        if variant == 1 or stage >= 1:
            for ti, (tx, ty, trx, try_) in enumerate([(28, 50.5, 4.2, 2.3), (36, 51.0, 4.6, 2.4), (45, 50.8, 3.8, 2.1)][: (2 if stage == 0 else 3)]):
                draw_fieldstone(body, mask, tx, ty, trx, try_, seed + 99 + ti, warm=(ti == 1))

        # Lush moss cushions & creeping pasture flora
        top_y = 32 if stage == 0 else (37 if stage == 1 else 42)
        if variant == 0:
            drape_wall_moss(body, mask, 7, 26, top_y, 2, seed + 3, hang=3)
            drape_wall_moss(body, mask, 40, 56, top_y, 2, seed + 7, hang=2)
        elif variant == 1:
            drape_wall_moss(body, mask, 7, 22, top_y, 2, seed + 3, hang=3)
            drape_wall_moss(body, mask, 24, 40, 41 if stage <= 1 else 43, 3, seed + 5, hang=3)
            drape_wall_moss(body, mask, 43, 56, top_y, 2, seed + 9, hang=2)
        elif variant == 4:
            # Heavily overgrown wall with trailing ivy vines & blooming pasture wildflowers!
            drape_wall_moss(body, mask, 6, 57, top_y, 3, seed + 4, hang=4)
            for vx0 in (15, 29, 44):
                vy0 = top_y + 2
                for k in range(11 - stage * 2):
                    vx = vx0 + int(round(1.6 * math.sin(k * 0.6 + vx0)))
                    vy = vy0 + k
                    if vy < WFY - 1:
                        put(body, vx, vy, IVY[3 if k % 2 == 0 else 2])
                        put(body, vx + 1, vy, IVY[1])
            for fx_p, fpal in [(14, FLOWER_GOLD), (22, FLOWER_LILAC), (35, FLOWER_ROSE), (47, FLOWER_GOLD)]:
                fy_p = top_y - 1
                put(body, fx_p, fy_p, fpal[2])
                put(body, fx_p + 1, fy_p, fpal[1])
                put(body, fx_p, fy_p + 1, fpal[0])

    elif variant == 2:
        # Variant 2: Sturdy mossy corner / end-pillar gatepost cairn (`x ~ 18..46`, taller at `y ~ 22..52` with lantern rune!)
        p_courses = [
            [(25, 48.8, 6.8, 3.5), (38, 48.8, 6.8, 3.5)],
            [(24, 43.5, 5.8, 3.2), (32, 43.6, 5.8, 3.2), (40, 43.5, 5.8, 3.2)],
            [(26, 38.4, 6.4, 3.1), (38, 38.4, 6.4, 3.1)],
            [(25, 33.4, 5.6, 2.9), (32, 33.5, 5.8, 2.9), (39, 33.4, 5.6, 2.9)],
            [(27, 28.6, 6.2, 2.8), (37, 28.6, 6.2, 2.8)],
            [(32, 24.2, 9.8, 3.0)],  # Wide weathered capstone slab
        ]
        n_c = 6 if stage == 0 else (4 if stage == 1 else 3)
        for ci in range(n_c):
            for si_s, (sx, sy, srx, sry) in enumerate(p_courses[ci]):
                draw_fieldstone(body, mask, sx, sy, srx, sry, seed + ci * 13 + si_s * 5, warm=((ci + si_s) % 2 == 0))
        cap_y = 22 if stage == 0 else (31 if stage == 1 else 36)
        drape_wall_moss(body, mask, 22, 42, cap_y, 2, seed + 11, hang=3)
        if stage <= 1:
            # Small carved boundary-mark rune in the pillar face with warm turquoise-gold glow!
            ry_m = 38 if stage == 0 else 42
            for dy_r in (-2, -1, 0, 1, 2):
                put(body, WFX, ry_m + dy_r, WALL_STONE[0])
            glow.emit(body, WFX, ry_m, TEAL, TEAL_L, halo=2)
            glow.emit(body, WFX, ry_m - 1, GOLD_DIM, GOLD_HOT, halo=1)

    elif variant == 3:
        # Variant 3: N-S foreshortened dry-stone wall segment (`x ~ 21..43`, marching back in 3/4 perspective `y = 20..52`)
        ns_rows = [
            (24.0, 8.2, 2.8),
            (28.2, 8.5, 2.9),
            (32.6, 8.8, 3.0),
            (37.2, 9.2, 3.1),
            (42.0, 9.5, 3.2),
            (47.2, 9.8, 3.4),
        ]
        start_idx = 0 if stage == 0 else (2 if stage == 1 else 3)
        for ri_n in range(start_idx, len(ns_rows)):
            ry_c, half_w, ry_s = ns_rows[ri_n]
            # Left cheek stone, right cheek stone & top hearting stone
            draw_fieldstone(body, mask, WFX - half_w * 0.46, ry_c + 1.2, half_w * 0.56, ry_s, seed + ri_n * 9, warm=(ri_n % 2 == 0))
            draw_fieldstone(body, mask, WFX + half_w * 0.46, ry_c + 1.2, half_w * 0.56, ry_s, seed + ri_n * 9 + 3)
            if stage == 0 or ri_n > start_idx:
                draw_fieldstone(body, mask, WFX + rng.uniform(-0.8, 0.8), ry_c - 1.2, half_w * 0.76, ry_s * 0.82, seed + ri_n * 9 + 6, warm=(ri_n % 3 == 0))
        drape_wall_moss(body, mask, WFX - 7, WFX + 6, int(ns_rows[start_idx][0] - 3), 2, seed + 15, hang=2)

    else:
        # Variant 5: Collapsed mossy stone heap / tumbled pasture cairn (`x ~ 9..55`, `y ~ 33..52`)
        heap = [
            (16, 48.8, 6.2, 3.3, -0.15), (27, 49.0, 6.6, 3.4, 0.10), (39, 48.8, 6.4, 3.3, -0.12), (49, 49.0, 5.6, 3.1, 0.18),
            (21, 44.0, 6.0, 3.2, 0.22), (32, 43.6, 6.8, 3.4, -0.18), (43, 44.2, 5.8, 3.1, 0.15),
            (26, 39.0, 5.8, 3.0, -0.20), (36, 39.2, 5.6, 3.0, 0.24),
            (31, 35.2, 5.4, 2.8, 0.08),
        ]
        keep_n = 10 if stage == 0 else (7 if stage == 1 else 5)
        for hi_s, (sx, sy, srx, sry, tilt) in enumerate(heap[:keep_n]):
            draw_fieldstone(body, mask, sx, sy, srx, sry, seed + hi_s * 11, warm=(hi_s % 2 == 1), tilt=tilt)
        drape_wall_moss(body, mask, 19, 43, 34 if stage == 0 else (38 if stage == 1 else 43), 3, seed + 21, hang=3)

    # Pale crust lichen flecks, base grass tufts & subtle night spore-lichen glints
    for _ in range(8):
        lx = rng.randrange(10, WW - 10)
        ly = rng.randrange(26, WFY - 2)
        if mask[ly][lx] == 2:
            put(body, lx, ly, LICHEN[1])
            if mask[ly][lx + 1] == 2:
                put(body, lx + 1, ly, LICHEN[0])

    tuft_xs = [-10, 8] if variant == 3 else ([-13, 0, 13] if variant == 2 else [-23, -10, 4, 17, 25])
    for tx_off in tuft_xs:
        bx = WFX + tx_off
        for bdx, bdy, mi in [(-1, -2, 4), (0, -3, 3), (0, -1, 1), (1, -2, 3), (2, -1, 2)]:
            put(body, bx + bdx, WFY + bdy, MOSS[mi])

    # Tiny glowing turquoise/gold lichen-spore glints tucked into damp wall crevices (`dry_stone_wall_glow.png`)
    spore_spots = [
        (WFX - 14, 41, False), (WFX + 9, 44, True),
    ] if variant != 3 else [(WFX - 4, 38, False), (WFX + 3, 45, True)]
    for gx, gy, is_gold in spore_spots[: (2 if stage == 0 else 1)]:
        if 4 <= gx < WW - 4 and 4 <= gy < WH - 4 and body[gy][gx][3] == 255:
            if is_gold:
                glow.emit(body, gx, gy, GOLD_DIM, GOLD, halo=1)
            else:
                glow.emit(body, gx, gy, TEAL, TEAL_L, halo=1)

    # Ground shadow ellipse + 1px `#1b1a2e` outline
    sh = blank(WW, WH)
    rx_sh = 13.5 if variant == 3 else (17.5 if variant == 2 else 28.5)
    for y in range(WFY - 6, WH):
        for x in range(WW):
            d = ((x + 0.5 - WFX) / rx_sh) ** 2 + ((y + 0.5 - (WFY + 0.5)) / 4.2) ** 2
            if d < 1.0:
                sh[y][x] = (*SHADOW_RGB, 112 if d < 0.48 else 58)

    framed = outline_pass(body, OUT_STONE)
    out = [[framed[y][x] if framed[y][x][3] > 0 else sh[y][x] for x in range(WW)] for y in range(WH)]
    return out, glow.finish()


# ==============================================================================
# 4. Broken Pasture Fence (`broken_fence.png` & `_stripped.png`: 5 cols x 1 row of 40x34, feet (20, 31))
#    100% compatible with `bush.tscn`!
# ==============================================================================
BFW, BFH = 40, 34
BFX, BFY = 20, 31


def draw_wood_post(px, x_base: float, y_base: int, h_post: int, w_post: int, lean_dx: float, seed: int, splintered: bool = False):
    for dy in range(h_post):
        y = y_base - dy
        if not (2 <= y < BFH - 1):
            continue
        t = dy / max(1.0, float(h_post - 1))
        cx = x_base + lean_dx * t
        x0 = int(round(cx - w_post * 0.5))
        for k in range(w_post):
            x = x0 + k
            if not (2 <= x < BFW - 2):
                continue
            if splintered and dy >= h_post - 3:
                # Jagged pale heartwood splinters at broken stub top!
                jag = (k * 2 + int(x_base)) % 3
                if dy >= h_post - jag:
                    continue
                put(px, x, y, SPLINTER[3 if k == 0 else (2 if k == 1 else 1)])
                continue
            rel = k / max(1.0, float(w_post - 1))
            grain = (hsh(x, y // 2, seed) - 0.5) * 0.9
            idx = int(clamp((0.82 - 0.68 * rel) * 4.8 + grain, 0, 5))
            if dy == h_post - 1 and not splintered:
                idx = min(5, idx + 1)  # Sunlit weathered post cap
            if dy <= 2:
                idx = max(0, idx - 1)  # Damp soil base
            put(px, x, y, FENCE_WOOD[idx])


def draw_wood_rail(px, x0: int, y0: float, x1: int, y1: float, thick: int, seed: int, broken_right: bool = False, broken_left: bool = False):
    steps = max(1, abs(x1 - x0))
    for i in range(steps + 1):
        t = i / float(steps)
        x = int(round(x0 + (x1 - x0) * t))
        yc = y0 + (y1 - y0) * t + 0.45 * math.sin(t * 4.0 + seed)
        if not (2 <= x < BFW - 2):
            continue
        for k in range(thick):
            y = int(round(yc)) + k
            if not (2 <= y < BFH - 1):
                continue
            if broken_right and i >= steps - 3 and (i + k) % 2 == 0:
                if i == steps - 2:
                    put(px, x, y, SPLINTER[2])
                continue
            if broken_left and i <= 2 and (i + k) % 2 == 0:
                if i == 2:
                    put(px, x, y, SPLINTER[3])
                continue
            if k == 0:
                col = FENCE_WOOD[5 if x < BFX + 2 else 4]
            elif k == thick - 1:
                col = FENCE_WOOD[1 if x < BFX else 0]
            else:
                g = hsh(x // 2, y, seed + 5)
                col = FENCE_WOOD[4 if g > 0.62 else (3 if g > 0.25 else 2)]
            put(px, x, y, col)


def build_fence_pair(variant: int):
    """Returns `(intact_frame, stripped_frame)` of size `40x34` anchored at `(20, 31)`."""
    seed = 910 + variant * 29
    body = blank(BFW, BFH)
    stub = blank(BFW, BFH)

    if variant == 0:
        # 0: Two sturdy mossy posts + two weathered split horizontal rails
        draw_wood_rail(body, 4, 15.0, 35, 15.8, 3, seed + 1)
        draw_wood_rail(body, 4, 22.5, 35, 22.0, 3, seed + 2)
        draw_wood_post(body, 9.5, BFY - 1, 21, 5, -0.6, seed + 3)
        draw_wood_post(body, 30.5, BFY - 1, 20, 5, 0.8, seed + 4)
        # Rusty iron nails & moss caps on posts
        for nx, ny in [(9, 16), (30, 16), (9, 23), (30, 23)]:
            put(body, nx, ny, RUST_IRON[1])
            put(body, nx + 1, ny, RUST_IRON[3])
        for mx in range(7, 12):
            put(body, mx, 9, MOSS[4 if mx < 10 else 2])
        # Stripped stubs
        draw_wood_post(stub, 9.5, BFY - 1, 8, 5, -0.3, seed + 3, splintered=True)
        draw_wood_post(stub, 30.5, BFY - 1, 7, 5, 0.4, seed + 4, splintered=True)

    elif variant == 1:
        # 1: Leaning left post + broken upper rail dipping diagonally into the meadow grass on the right
        draw_wood_rail(body, 6, 15.5, 33, 28.5, 3, seed + 5, broken_right=True)
        draw_wood_rail(body, 6, 22.5, 22, 25.5, 3, seed + 6, broken_right=True)
        draw_wood_post(body, 10.0, BFY - 1, 20, 5, -2.2, seed + 7)
        put(body, 9, 16, RUST_IRON[2])
        put(body, 9, 23, RUST_IRON[1])
        for mx in range(7, 11):
            put(body, mx, 10, MOSS[3])
        draw_wood_post(stub, 10.0, BFY - 1, 8, 5, -0.8, seed + 7, splintered=True)
        draw_wood_rail(stub, 18, 28.5, 30, 29.5, 2, seed + 8, broken_left=True, broken_right=True)

    elif variant == 2:
        # 2: Crooked half-open pasture gate remnant (thick hinge post with forged iron hinge straps + sagging braced gate frame)
        # Sagging gate frame (`x = 11..34`)
        draw_wood_rail(body, 11, 14.0, 34, 18.5, 3, seed + 9)
        draw_wood_rail(body, 11, 23.0, 34, 27.0, 3, seed + 10)
        # Diagonal gate cross-brace & end stile
        for i in range(20):
            gx = 13 + i
            gy = int(round(23.0 - i * 0.24))
            put(body, gx, gy, FENCE_WOOD[4 if i < 10 else 3])
            put(body, gx, gy + 1, FENCE_WOOD[2])
        draw_wood_post(body, 32.5, BFY - 2, 13, 3, 1.2, seed + 11)
        # Heavy left hinge post (`x = 7..12`) + forged iron hinge straps
        draw_wood_post(body, 9.5, BFY - 1, 23, 5, -0.4, seed + 12)
        for hy in (15, 24):
            for hx in range(9, 15):
                put(body, hx, hy, RUST_IRON[3 if hx < 12 else 1])
        draw_wood_post(stub, 9.5, BFY - 1, 9, 5, -0.2, seed + 12, splintered=True)
        put(stub, 10, 25, RUST_IRON[2])
        put(stub, 11, 25, RUST_IRON[1])

    elif variant == 3:
        # 3: Twin corner posts meeting at an angle with short rails, creeping ivy & wildflowers
        draw_wood_rail(body, 4, 17.5, 19, 16.0, 3, seed + 13, broken_left=True)
        draw_wood_rail(body, 21, 16.0, 35, 20.5, 3, seed + 14, broken_right=True)
        draw_wood_post(body, 17.5, BFY - 1, 21, 5, -0.5, seed + 15)
        draw_wood_post(body, 23.5, BFY, 19, 5, 0.7, seed + 16)
        # Creeping ivy & lilac blossom wrapping the corner posts
        for k in range(14):
            ix = 16 + int(round(2.5 * math.sin(k * 0.55)))
            iy = BFY - 2 - k
            put(body, ix, iy, IVY[3 if k % 2 == 0 else 2])
            put(body, ix + 1, iy, IVY[1])
        put(body, 15, 19, FLOWER_LILAC[2])
        put(body, 16, 20, FLOWER_LILAC[1])
        draw_wood_post(stub, 17.5, BFY - 1, 8, 5, -0.2, seed + 15, splintered=True)
        draw_wood_post(stub, 23.5, BFY, 7, 5, 0.3, seed + 16, splintered=True)

    else:
        # 4: Mossy lone post with splintered mortise slot + weathered fallen rail lying in the grass
        draw_wood_rail(body, 15, 27.5, 36, 29.2, 3, seed + 17, broken_left=True, broken_right=True)
        draw_wood_post(body, 13.0, BFY - 1, 21, 6, 1.2, seed + 18)
        # Dark mortise slot in the lone post where the rail once sat
        for my in range(16, 19):
            put(body, 13, my, FENCE_WOOD[0])
            put(body, 14, my, FENCE_WOOD[0])
        for mx in range(11, 17):
            put(body, mx, 10, MOSS[4 if mx < 14 else 2])
            put(body, mx, 11, MOSS[2 if mx < 14 else 1])
        draw_wood_post(stub, 13.0, BFY - 1, 8, 6, 0.5, seed + 18, splintered=True)

    # Lush grass tufts & tiny pasture buttercups around the feet of both intact & stripped frames
    for target in (body, stub):
        for gx in (8, 15, 22, 30):
            for bdx, bdy, mi in [(-1, -2, 4), (0, -3, 3), (0, -1, 1), (1, -2, 4), (2, -1, 2)]:
                put(target, gx + bdx, BFY + bdy, MOSS[mi])
        put(body, 23, BFY - 3, FLOWER_GOLD[2])
        put(body, 23, BFY - 2, FLOWER_GOLD[0])

    def finish_fence(raw_px, rx_sh: float):
        sh = blank(BFW, BFH)
        for y in range(BFY - 4, BFH):
            for x in range(BFW):
                d = ((x + 0.5 - BFX) / rx_sh) ** 2 + ((y + 0.5 - BFY) / 2.8) ** 2
                if d < 1.0:
                    sh[y][x] = (*SHADOW_RGB, 104 if d < 0.5 else 54)
        fr = outline_pass(raw_px, OUT_STONE)
        return [[fr[y][x] if fr[y][x][3] > 0 else sh[y][x] for x in range(BFW)] for y in range(BFH)]

    return finish_fence(body, 16.5), finish_fence(stub, 12.5)


# ==============================================================================
# 5. Pasture Paving (`assets/props/pasture_paving.png`: 4 cols x 1 row of 96x64, z_index = -9)
# ==============================================================================
def build_pasture_paving():
    pw, ph = 96, 64
    sheet = blank(pw * 4, ph)

    for col in range(4):
        seed = 1100 + col * 53
        rng = random.Random(seed)
        frame = blank(pw, ph)

        # Generate Voronoi-like irregular flagstone / cobble cell centers tailored to each patch archetype!
        sites = []
        if col == 0:
            # 0: Sunken old courtyard flagstone patch (larger rectangular/polygonal slabs)
            for gy in range(8, ph - 6, 13):
                row_shift = 7 if (gy // 13) % 2 else 0
                for gx in range(10 + row_shift, pw - 8, 16):
                    sites.append((gx + rng.uniform(-2.5, 2.5), gy + rng.uniform(-2.0, 2.0), rng.randrange(1000)))
        elif col == 1:
            # 1: Winding cart-track / pasture cobble path segment running diagonally E-W
            for gx in range(8, pw - 6, 11):
                cy_path = 32.0 + 7.5 * math.sin(gx * 0.065 + 0.4)
                for dy_off in (-13, -4, 5, 14):
                    sites.append((gx + rng.uniform(-2.0, 2.0), cy_path + dy_off + rng.uniform(-1.5, 1.5), rng.randrange(1000)))
        elif col == 2:
            # 2: Circular old wellhead / threshing ring remnants of radial cobbles
            sites.append((48.0, 32.0, 77))
            for ring_r, n_pts in [(13.0, 8), (25.0, 14), (36.0, 18)]:
                for k in range(n_pts):
                    ang = (k / float(n_pts)) * math.tau + ring_r * 0.05
                    sites.append((48.0 + math.cos(ang) * ring_r * 1.22, 32.0 + math.sin(ang) * ring_r * 0.82, rng.randrange(1000)))
        else:
            # 3: Scattered mossy threshold flagstones fading into meadow sod
            for _ in range(28):
                sites.append((rng.uniform(12, pw - 12), rng.uniform(10, ph - 10), rng.randrange(1000)))

        for y in range(ph):
            for x in range(pw):
                # Warped patch envelope for organic Bayer-dithered alpha falloff (`forestbed.png` convention)
                nx = (x + 0.5 - pw * 0.5) / (pw * 0.46)
                ny = (y + 0.5 - ph * 0.5) / (ph * 0.45)
                if col == 1:
                    cy_p = 32.0 + 7.5 * math.sin(x * 0.065 + 0.4)
                    ny = (y + 0.5 - cy_p) / 21.5
                ang = math.atan2(ny, nx)
                warp = 1.0 + 0.14 * math.sin(ang * 3.0 + col * 1.7) + 0.09 * math.cos(ang * 5.0 - col)
                d_env = math.hypot(nx, ny) / warp
                if d_env >= 1.0:
                    continue
                if d_env > 0.62:
                    edge_u = (d_env - 0.62) / 0.38
                    keep = BAYER[y % 4][x % 4] / 16.0 * 0.68 + hsh(x, y, seed + 3) * 0.32
                    if edge_u > keep:
                        continue

                # Nearest & second-nearest stone site -> flagstone interior vs grass-invaded joint!
                d1, d2, s1 = 1e9, 1e9, None
                for sx, sy, s_id in sites:
                    # Slight horizontal stretch for natural 3/4 perspective flagstones
                    dd = math.hypot((x - sx) * 0.86, (y - sy) * 1.12)
                    if dd < d1:
                        d2 = d1
                        d1 = dd
                        s1 = (sx, sy, s_id)
                    elif dd < d2:
                        d2 = dd

                joint_gap = d2 - d1
                # Grass & moss invading wider joints and outer patch margins!
                grass_invade = 1.55 + (1.45 if d_env > 0.52 else 0.0) + (fbm(x * 0.18, y * 0.18, seed + 11) - 0.45) * 1.6
                if joint_gap < grass_invade or d1 > 10.5:
                    # Moss / meadow turf growing between sunken stones
                    g_val = fbm(x * 0.45, y * 0.45, seed + 19) * 3.8 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.6
                    if joint_gap < 0.65 and hsh(x, y, seed + 23) < 0.45:
                        col_px = MORTAR  # Deep dark soil shadow right at stone edge
                    else:
                        col_px = MOSS[int(clamp(g_val, 0, 4))]
                else:
                    sx, sy, s_id = s1
                    # Missing sunken stone pockets invaded by clover/turf
                    if (s_id % 7 == 0 and d_env > 0.35) or (col == 3 and s_id % 4 == 0):
                        g_val = fbm(x * 0.4, y * 0.4, seed + 29) * 3.6
                        col_px = MOSS[int(clamp(g_val, 0, 3))]
                    else:
                        pal = WARM_STONE if (s_id % 3 == 0) else WALL_STONE
                        stone_bias = ((s_id % 11) / 11.0 - 0.5) * 1.1
                        # Sunlit bevel on top-left edge of each sunken flagstone (`joint_gap < grass_invade + 1.3`)
                        rel_dx = x - sx
                        rel_dy = y - sy
                        bevel = 0.0
                        if joint_gap < grass_invade + 1.35:
                            bevel = 0.85 if (rel_dx < 0 and rel_dy < 0) else (-0.75 if (rel_dx > 1 or rel_dy > 1) else 0.25)
                        grain = (fbm(x * 0.55, y * 0.55, seed + 37) - 0.5) * 1.1
                        dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.62
                        # Hairline crack across occasional old flagstones
                        crack = -1.2 if (s_id % 5 == 0 and abs((x - sx) * 0.7 + (y - sy) * 1.1) < 0.65) else 0.0
                        idx = int(clamp(2.9 + stone_bias + bevel + grain + dith + crack, 0, 6))
                        col_px = pal[idx]

                frame[y][x] = col_px

        # Tiny clover & buttercup specks in the mossy joints
        for _ in range(7):
            fx_p = rng.randrange(14, pw - 14)
            fy_p = rng.randrange(10, ph - 10)
            if frame[fy_p][fx_p] in MOSS[1:]:
                frame[fy_p][fx_p] = FLOWER_GOLD[1] if rng.random() < 0.6 else FLOWER_LILAC[1]

        for y in range(ph):
            sheet[y][col * pw:(col + 1) * pw] = frame[y]

    return sheet


# ==============================================================================
# 6. 16x16 Item Icons (`assets/items/meadow_apple.png` & `assets/items/moon_pear.png`)
# ==============================================================================
def build_icon_meadow_apple():
    px = blank(16, 16)
    # Plump round crimson-gold Wiesenapfel (`x = 3..12`, `y = 4..13`) with stem & crisp green leaf
    for y in range(4, 14):
        for x in range(3, 13):
            dx = (x - 7.5) / 4.8
            dy = (y - 8.8) / 4.7
            # Classic apple dimple at top center (`x ~ 7.5, y ~ 4..5`)
            dimple = 0.22 * math.exp(-((x - 7.5) ** 2) / 1.8) if y < 7 else 0.0
            d = dx * dx + (dy - dimple) ** 2
            if d > 1.0:
                continue
            nz = math.sqrt(max(0.0, 1.0 - d))
            lit = -0.55 * dx - 0.72 * dy + 0.52 * nz
            idx = int(clamp((lit + 0.68) * 4.4, 0, 6))
            px[y][x] = APPLE_FRUIT[idx]
    # Specular glint, woody stem & fresh green leaf on upper right
    px[6][5] = APPLE_FRUIT[6]
    px[7][5] = APPLE_FRUIT[5]
    px[3][7] = APPLE_BARK[2]
    px[4][7] = APPLE_BARK[1]
    px[2][8] = APPLE_BARK[3]
    for lx, ly, li in [(9, 3, 5), (10, 2, 6), (11, 2, 5), (10, 3, 4), (11, 3, 3), (12, 3, 4)]:
        px[ly][lx] = APPLE_LEAF[li]
    check_icon("meadow_apple", px)
    return outline_pass(px, OUT_STONE)


def build_icon_moon_pear():
    px = blank(16, 16)
    # Graceful teardrop luminous Mondbirne (`y = 3..13`) with stem, sage-teal leaf & glowing core sheen
    for y in range(3, 14):
        u = (y - 3.0) / 10.0  # 0 at narrow neck, 1 at rounded base
        rx = 1.6 + 3.3 * (math.sin(min(1.0, u * 0.92) * math.pi * 0.78) ** 1.15)
        if u > 0.82:
            rx *= math.sqrt(max(0.0, 1.0 - ((u - 0.82) / 0.20) ** 2))
        cx = 7.6 - 0.4 * (1.0 - u)
        for x in range(2, 14):
            dx = (x - cx) / max(0.8, rx)
            if abs(dx) > 1.0:
                continue
            dy = (u - 0.58) * 1.7
            nz = math.sqrt(max(0.0, 1.0 - dx * dx))
            lit = -0.54 * dx - 0.58 * dy + 0.55 * nz
            idx = int(clamp((lit + 0.62) * 3.9, 0, 5))
            px[y][x] = PEAR_FRUIT[idx]
    # Luminous pearl-gold highlight, stem & sage-teal leaf
    px[7][6] = PEAR_FRUIT[5]
    px[8][6] = PEAR_FRUIT[5]
    px[2][7] = PEAR_BARK[3]
    px[3][7] = PEAR_BARK[2]
    for lx, ly, li in [(8, 2, 5), (9, 2, 6), (10, 2, 4), (9, 3, 4), (10, 3, 3)]:
        px[ly][lx] = PEAR_LEAF[li]
    check_icon("moon_pear", px)
    return outline_pass(px, OUT_STONE)


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/pasture_ruins_sheet.png`)
# ==============================================================================
def verify_no_black(name: str, px):
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} has forbidden pure #000000 pixel at ({x}, {y})")


def alpha_over(dst, src, ox: int, oy: int):
    sh, sw = len(src), len(src[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(sh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(sw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            sc = src[y][x]
            sa = sc[3]
            if sa == 0:
                continue
            if sa == 255:
                dst[dy][dx] = sc
            else:
                dc = dst[dy][dx]
                inv = 255 - sa
                dst[dy][dx] = (
                    (sc[0] * sa + dc[0] * inv) // 255,
                    (sc[1] * sa + dc[1] * inv) // 255,
                    (sc[2] * sa + dc[2] * inv) // 255,
                    255,
                )


def add_glow_over(dst, glow, ox: int, oy: int):
    gh, gw = len(glow), len(glow[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(gh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(gw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            gc = glow[y][x]
            ga = gc[3]
            if ga == 0:
                continue
            dc = dst[dy][dx]
            f = ga / 255.0
            dst[dy][dx] = (
                min(255, int(dc[0] * (1.0 - 0.55 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.55 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.55 * f) + gc[2] * f * 1.35)),
                255,
            )


def tint_night_px(src):
    out = blank(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(5, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def crop(sheet, x0: int, y0: int, w: int, h: int):
    return [row[x0:x0 + w] for row in sheet[y0:y0 + h]]


def scale_nn(src, factor: int):
    h, w = len(src), len(src[0])
    out = blank(w * factor, h * factor)
    for y in range(h):
        for x in range(w):
            c = src[y][x]
            for dy in range(factor):
                for dx in range(factor):
                    out[y * factor + dy][x * factor + dx] = c
    return out


def render_qa_sheet(apple_lit, apple_raw, pear_lit, pear_raw, fallen_sheet, wall_cells, fence_pairs, paving_sheet, icon_a, icon_p):
    cw, ch = 720, 620
    canvas = blank(cw, ch)
    half_h = 310
    for y in range(ch):
        night = y >= half_h
        for x in range(cw):
            n = noise(x // 4, y // 3, 97)
            if not night:
                canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
            else:
                canvas[y][x] = (20, 29, 50, 255) if n < 115 else ((26, 38, 62, 255) if n < 205 else (32, 46, 72, 255))

    for pass_i in range(2):
        night = pass_i == 1
        y_off = 0 if not night else half_h

        # Ground layer: 4 `pasture_paving.png` patches across lower band
        for col in range(4):
            pv = crop(paving_sheet, col * 96, 0, 96, 64)
            alpha_over(canvas, tint_night_px(pv) if night else pv, 16 + col * 106, y_off + 234)

        # Top row: 3 orchard_apple + 3 orchard_pear trees with fallen_fruit at their feet!
        for i in range(3):
            ox = 6 + i * 108
            oy = y_off + 4
            t_px, c_px = apple_lit[i]
            ff = crop(fallen_sheet, i * 48, 0, 48, 24)
            if not night:
                alpha_over(canvas, ff, ox + 56 - 24, oy + 196 - 16)
                alpha_over(canvas, t_px, ox, oy)
                alpha_over(canvas, c_px, ox, oy)
            else:
                alpha_over(canvas, tint_night_px(ff), ox + 56 - 24, oy + 196 - 16)
                alpha_over(canvas, tint_night_px(t_px), ox, oy)
                alpha_over(canvas, tint_night_px(c_px), ox, oy)
                add_glow_over(canvas, to_pixels(apple_raw[i]["glow_trunk"]), ox, oy)
                add_glow_over(canvas, to_pixels(apple_raw[i]["glow_crown"]), ox, oy)

        for i in range(3):
            ox = 334 + i * 108
            oy = y_off + 4
            t_px, c_px = pear_lit[i]
            ff = crop(fallen_sheet, (i + 3) * 48, 0, 48, 24)
            if not night:
                alpha_over(canvas, ff, ox + 56 - 24, oy + 196 - 16)
                alpha_over(canvas, t_px, ox, oy)
                alpha_over(canvas, c_px, ox, oy)
            else:
                alpha_over(canvas, tint_night_px(ff), ox + 56 - 24, oy + 196 - 16)
                alpha_over(canvas, tint_night_px(t_px), ox, oy)
                alpha_over(canvas, tint_night_px(c_px), ox, oy)
                add_glow_over(canvas, to_pixels(pear_raw[i]["glow_trunk"]), ox, oy)
                add_glow_over(canvas, to_pixels(pear_raw[i]["glow_crown"]), ox, oy)

        # Dry stone wall (all 6 variants intact + stage 3 rubble sample) & 5 broken fences
        for v in range(6):
            w_px, w_gl = wall_cells[(v, 0)]
            wx, wy = 438 + (v % 3) * 74, y_off + 206 + (v // 3) * 48
            alpha_over(canvas, tint_night_px(w_px) if night else w_px, wx, wy)
            if night:
                add_glow_over(canvas, w_gl, wx, wy)

        for v in range(5):
            f_px, _ = fence_pairs[v]
            fx_pos, fy_pos = 18 + v * 82, y_off + 204
            alpha_over(canvas, tint_night_px(f_px) if night else f_px, fx_pos, fy_pos)

        # 2x upscaled 16x16 item icons in top-right corner
        ia = scale_nn(tint_night_px(icon_a) if night else icon_a, 2)
        ip = scale_nn(tint_night_px(icon_p) if night else icon_p, 2)
        alpha_over(canvas, ia, 668, y_off + 22)
        alpha_over(canvas, ip, 668, y_off + 62)

    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"
    items = ROOT / "items"

    # 1. Orchard Apple & Pear sheets (`336x1200`) + Growth sheets (`448x200`)
    apple_sheet, apple_growth, apple_lit, apple_raw = build_orchard_sheets("apple", 310)
    pear_sheet, pear_growth, pear_lit, pear_raw = build_orchard_sheets("pear", 510)
    for nm, sh in [
        ("orchard_apple.png", apple_sheet),
        ("orchard_apple_growth.png", apple_growth),
        ("orchard_pear.png", pear_sheet),
        ("orchard_pear_growth.png", pear_growth),
    ]:
        verify_no_black(nm, sh)
        write_png(props / nm, len(sh[0]), len(sh), sh)

    # 2. Fallen Fruit (`288x24`)
    fallen_sheet = build_fallen_fruit()
    verify_no_black("fallen_fruit.png", fallen_sheet)
    write_png(props / "fallen_fruit.png", 288, 24, fallen_sheet)

    # 3. Dry Stone Wall (`384x224` + glow)
    wall_sheet = blank(WW * 6, WH * 4)
    wall_glow_sheet = blank(WW * 6, WH * 4)
    wall_cells = {}
    for stage in range(4):
        for v in range(6):
            w_px, w_gl = build_wall_cell(v, stage)
            wall_cells[(v, stage)] = (w_px, w_gl)
            for y in range(WH):
                wall_sheet[stage * WH + y][v * WW:(v + 1) * WW] = w_px[y]
                wall_glow_sheet[stage * WH + y][v * WW:(v + 1) * WW] = w_gl[y]
    verify_no_black("dry_stone_wall.png", wall_sheet)
    verify_no_black("dry_stone_wall_glow.png", wall_glow_sheet)
    write_png(props / "dry_stone_wall.png", WW * 6, WH * 4, wall_sheet)
    write_png(props / "dry_stone_wall_glow.png", WW * 6, WH * 4, wall_glow_sheet)

    # 4. Broken Fence (`200x34` + stripped)
    fence_sheet = blank(BFW * 5, BFH)
    fence_stripped_sheet = blank(BFW * 5, BFH)
    fence_pairs = []
    for v in range(5):
        f_intact, f_stub = build_fence_pair(v)
        fence_pairs.append((f_intact, f_stub))
        for y in range(BFH):
            fence_sheet[y][v * BFW:(v + 1) * BFW] = f_intact[y]
            fence_stripped_sheet[y][v * BFW:(v + 1) * BFW] = f_stub[y]
    verify_no_black("broken_fence.png", fence_sheet)
    verify_no_black("broken_fence_stripped.png", fence_stripped_sheet)
    write_png(props / "broken_fence.png", BFW * 5, BFH, fence_sheet)
    write_png(props / "broken_fence_stripped.png", BFW * 5, BFH, fence_stripped_sheet)

    # 5. Pasture Paving (`384x64`)
    paving_sheet = build_pasture_paving()
    verify_no_black("pasture_paving.png", paving_sheet)
    write_png(props / "pasture_paving.png", 384, 64, paving_sheet)

    # 6. Item Icons (`16x16`)
    icon_apple = build_icon_meadow_apple()
    icon_pear = build_icon_moon_pear()
    verify_no_black("meadow_apple.png", icon_apple)
    verify_no_black("moon_pear.png", icon_pear)
    write_png(items / "meadow_apple.png", 16, 16, icon_apple)
    write_png(items / "moon_pear.png", 16, 16, icon_pear)

    render_qa_sheet(apple_lit, apple_raw, pear_lit, pear_raw, fallen_sheet, wall_cells, fence_pairs, paving_sheet, icon_apple, icon_pear)
    print("Wrote high-detail pasture_ruins assets and docs/img/pasture_ruins_sheet.png")


if __name__ == "__main__":
    main()
