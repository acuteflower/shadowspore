#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 3 — Spuren des Roten Ordens (stdlib + gen_art.py only):
  1. assets/props/order_watchtower.png & _glow.png
     - 2 cols x 1 row of 128x144 (256x144 total), ground/feet anchor at (64, 130):
       * Col 0: Half-collapsed ancient cliffside stone watchtower (~110 px tall, 88 px wide at base),
                heavy weathered grey-violet ashlar masonry, aged wine-red mortar/banner courses,
                crumbled right battlement arch, mossy ledges, carved Red Order sun-shield crest,
                and sheltered wrought-iron wall lantern niche.
       * Col 1: Octagonal/round bastion ruin with collapsed spiral stair wall, mossy fallen voussoir
                blocks at the base, and an iron brazier sconce.
  2. assets/props/order_patrol_camp.png & _glow.png
     - 2 cols x 1 row of 96x64 (192x64 total), ground/feet anchor at (48, 52):
       * Col 0: Cold moss-rimmed stone fire-ring with grey ash, rotted leather pack & weathered
                Crimson-Order heater shield in clover/fern, prominent rusted knight's greatsword
                driven blade-down into the earth at center-left, leaving ~18 px clear space on right
                (x ~ 68..82) for the separate swaying banner pole!
       * Col 1: Mossy stone cairn & collapsed canvas bedroll frame, rusted Order halberd/sword planted
                in turf, dented iron kettle, scattered parchment scroll tube with crimson wax seal.
  3. assets/props/order_banner.png (no glow)
     - Single frame 32x64, ground/pole-foot anchor at (16, 58):
       Iron-shod wooden lance/banner pole (x=9..11, y=6..58) with spearhead/crossbar at y=6..10 and
       torn wine-red Red Order cloth banner (y=8..48, x=11..26) with faded gold sun-sword emblem and
       ragged tails, keeping x=0..4 and x=27..31 strictly transparent for sway_rows.gdshader!
  4. assets/props/order_boundary_stone.png & _glow.png
     - 3 cols x 1 row of 48x56 (144x56 total), ground/feet anchor at (24, 48):
       * Col 0: Upright chamfered obelisk stele with chiselled script lines, Red Order sword-sun crest & moss cap.
       * Col 1: Tilted cracked tablet stele with crimson-red ribbon tied around its neck & creeping ivy.
       * Col 2: Twin-notched pass marker stone with recessed rune medallion & lichen clusters.
  5. docs/img/red_order_sheet.png — Visual QA contact sheet (daylight + night + composited camp banner).

STRICTLY ZERO #000000 pure black pixels anywhere!
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "red_order_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# Core Outlines & Cool-Violet Ground Shadows (NEVER #000000)
OUT = hexc("1b1a2e")
OUT_LEAF = hexc("132228")
MORTAR = hexc("19172b")
SHADOW_RGB = (15, 16, 34)

# Heavy weathered grey-violet ashlar masonry (8 steps matching arena_pillars.png + prompt ramp)
STONE = [
    hexc("1f1d32"),  # 0 deep crevice
    hexc("2a283e"),  # 1 shadow ashlar
    hexc("383650"),  # 2 cool slate-violet
    hexc("464462"),  # 3 mid-shadow stone
    hexc("595776"),  # 4 mid stone
    hexc("6c6a8a"),  # 5 lit stone
    hexc("8482a2"),  # 6 bright facet
    hexc("9c9ab8"),  # 7 sunlit bevel
    hexc("c4c2de"),  # 8 crisp top-left catch-edge
]

# Aged wine-red Red Order masonry courses & cloth banner ramp
CRIMSON_STONE = [hexc(c) for c in ("2d1220", "4a1c2d", "622438", "782c42", "90374e", "a44258", "c46276")]
BANNER_RED = [hexc(c) for c in ("28101c", "3d1726", "521e31", "68253b", "802f46", "963850", "bc5268")]
ORDER_GOLD = [hexc(c) for c in ("463116", "6f5020", "926d2c", "b48a38", "d4ab50", "e6c468", "fff0b0")]

# Rusted steel, wrought iron, weathered wood, leather, parchment & ash
STEEL = [hexc(c) for c in ("242136", "38344c", "4a4562", "5d5876", "746f8e", "8b86a4", "b4b0cc")]
RUST = [hexc(c) for c in ("3d1d1e", "522726", "68322c", "7e3e34", "944b3b", "b4684e")]
IRON = [hexc(c) for c in ("1d1b2d", "2c2940", "413e58", "5c5876", "7e7a98")]
WOOD = [hexc(c) for c in ("231826", "382634", "523946", "72525c", "967278", "baa09e")]
LEATHER = [hexc(c) for c in ("261722", "3e252c", "5c3838", "7e5248", "a4725e")]
CANVAS = [hexc(c) for c in ("343044", "4c475e", "6a647c", "8c869e", "b2acc2")]
PARCHMENT = [hexc(c) for c in ("5c4842", "8a6e5c", "b89c7e", "dfc6a2", "f6e6c8")]
ASH = [hexc(c) for c in ("242234", "363448", "4c4a60", "68667c")]

# Meadow moss, ivy, fern & lichen
MOSS = [hexc(c) for c in ("193632", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a6dc8c")]
LICHEN = [hexc("5e8076"), hexc("92b8a8")]
CLOVER_FL = [hexc("9e4268"), hexc("de7ca0"), hexc("ffdce8")]

# Unlit Glow Palettes
EMBER_D = hexc("8c2438")
EMBER_R = hexc("c23b4b")
EMBER_O = hexc("ff8e47")
EMBER_H = hexc("ffd89a")

RUNE_D = hexc("a8324a")
RUNE_M = hexc("ff6a7a")
RUNE_G = hexc("ff8c68")
RUNE_H = hexc("ffe0a8")


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
                        a = 104 if d <= 1.25 else (48 if d <= 2.05 else 22)
                        if a > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], a)
        return out


def shade_stone_px(x: int, y: int, lit_base: float, seed: int, crimson: bool = False, catch_top: bool = False, catch_left: bool = False):
    """Shades an individual ashlar masonry pixel with fbm micro-grain, Bayer 4x4 dither, pitting & sunlit catch-edges."""
    grain = (fbm(x * 0.52, y * 0.52, seed) - 0.5) * 0.95
    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.58
    bevel = (0.75 if catch_top else 0.0) + (0.45 if catch_left else 0.0)
    pit = -1.25 if hsh(x, y, seed + 31) < 0.032 else 0.0
    if crimson:
        v = (lit_base + 0.12) * 5.2 + grain * 0.8 + dith + bevel * 0.8 + pit * 0.6
        return CRIMSON_STONE[int(clamp(v, 0, len(CRIMSON_STONE) - 1))]
    v = lit_base * 6.8 + grain + dith + bevel + pit
    return STONE[int(clamp(v, 0, len(STONE) - 1))]


def draw_ashlar_block(px, x0: int, y0: int, x1: int, y1: int, lit_bias: float, seed: int, crimson: bool = False, chip_tr: bool = False):
    """Draws one cut stone block with 1px dark mortar border on bottom/right and sunlit bevel on top/left."""
    block_tone = (hsh(x0, y0, seed + 3) - 0.5) * 0.14
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if chip_tr and (x - x1) + (y0 - y) >= -1 and x >= x1 - 1 and y <= y0 + 1:
                put(px, x, y, MORTAR)
                continue
            if y == y1 or x == x1:
                put(px, x, y, MORTAR)
            else:
                ct = (y == y0)
                cl = (x == x0)
                col = shade_stone_px(x, y, lit_bias + block_tone, seed, crimson=crimson, catch_top=ct, catch_left=cl)
                put(px, x, y, col)


def drape_moss_ledge(px, x0: int, x1: int, y_top: int, thick: int, hang: int, seed: int):
    """Drapes multi-tone velvety meadow moss over a stone ledge with damp darkened stone fringe underneath."""
    w, h = len(px[0]), len(px)
    for x in range(max(2, x0), min(w - 2, x1 + 1)):
        drop = int(hang * max(0.0, 0.62 * math.sin(x * 0.42 + seed) + 0.38 * hsh(x, y_top, seed + 5)))
        t_jit = -1 if hsh(x, 1, seed + 7) > 0.58 else 0
        for y in range(y_top + t_jit, y_top + thick + drop + 1):
            if not (2 <= y < h - 2):
                continue
            if y > y_top + 1 and px[y][x][3] == 0:
                continue
            u = (y - (y_top + t_jit)) / max(1.0, float(thick + drop))
            lit = (1.0 - u) * 0.72 + (0.20 if x < w // 2 else 0.04) + (fbm(x * 0.5, y * 0.5, seed + 11) - 0.5) * 0.42
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
            put(px, x, y, MOSS[int(clamp(lit * 5.8 + dith, 0, len(MOSS) - 1))])
        fy = y_top + thick + drop + 1
        if 2 <= fy < h - 2 and px[fy][x] in STONE[2:]:
            idx = STONE.index(px[fy][x])
            px[fy][x] = STONE[max(0, idx - 2)]


def draw_fallen_block(px, cx: float, cy: float, rx: float, ry: float, tilt: float, seed: int, crimson: bool = False):
    ca, sa = math.cos(tilt), math.sin(tilt)
    for y in range(int(cy - ry - 3), int(cy + ry + 4)):
        for x in range(int(cx - rx - 3), int(cx + rx + 4)):
            dx0, dy0 = x + 0.5 - cx, y + 0.5 - cy
            u = (dx0 * ca + dy0 * sa) / max(1.0, rx)
            v = (-dx0 * sa + dy0 * ca) / max(1.0, ry)
            d = (abs(u) ** 2.6 + abs(v) ** 2.6) ** (1.0 / 2.6)
            if d <= 1.02:
                if d > 0.86:
                    put(px, x, y, MORTAR)
                else:
                    lit = 0.52 - 0.28 * u - 0.34 * v
                    col = shade_stone_px(x, y, lit, seed, crimson=crimson, catch_top=(v < -0.52), catch_left=(u < -0.52))
                    put(px, x, y, col)


def add_shadow_and_outline(body, cx: int, fy: int, rx: float, ry: float, out_col=OUT):
    w, h = len(body[0]), len(body)
    sh = blank(w, h)
    for y in range(max(0, int(fy - ry - 2)), min(h, int(fy + ry + 4))):
        for x in range(w):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - (fy + 1.0)) / ry) ** 2
            if d < 1.0:
                sh[y][x] = (*SHADOW_RGB, 114 if d < 0.48 else 60)
    framed = outline_pass(body, out_col)
    return [[framed[y][x] if framed[y][x][3] > 0 else sh[y][x] for x in range(w)] for y in range(h)]


# ==============================================================================
# 1. Order Watchtower (`order_watchtower.png` & `_glow.png`, 2x1 of 128x144, feet (64, 130))
# ==============================================================================
def build_watchtower_variant(variant: int):
    W, H = 128, 144
    FX, FY = 64, 130
    seed = 1301 + variant * 59
    rng = random.Random(seed)
    body = blank(W, H)
    glow = GlowMap(W, H)

    if variant == 0:
        # ---- Col 0: Half-collapsed cliffside rectangular/battered stone watchtower (~112px tall, 88px wide at base)
        # Courses from top (`y = 18`) down to battered plinth (`y = 130`), with crumbled upper-right wall/battlement!
        y = 18
        course_idx = 0
        while y < FY:
            ch = 6 if y < 32 else (7 if y < 108 else 8)
            yb = min(FY, y + ch - 1)
            u_down = (y - 18) / float(FY - 18)
            # Battered fortress walls: ~68px wide near top, flaring to ~88px wide at base plinth!
            hw = int(round(33.0 + 7.5 * (u_down ** 1.35) + (3.5 if y >= 114 else 0.0)))
            if y < 28:
                hw += 2  # Corbelled machicolation parapet overhang on intact left half!

            # Right-side collapse profile: upper-right battlement & wall tumbled away in a jagged step curve
            collapse_x = FX + hw
            if y < 26:
                collapse_x = FX - 2 + int(4 * hsh(0, y, seed))  # Only left 2 merlons survive at very top
            elif y < 38:
                collapse_x = FX + 10 + int((y - 26) * 0.9)
            elif y < 56:
                collapse_x = FX + 21 + int((y - 38) * 0.55)
            elif y < 74:
                collapse_x = FX + 30 + int((y - 56) * 0.35)

            # Aged wine-red Order frieze courses at breastwork (`y ~ 45..52`) and lower plinth band (`y ~ 106..113`)
            is_crimson = (44 <= y <= 51) or (106 <= y <= 112)

            # Draw dark ruined interior core behind the collapsed upper-right breach so the tower reads 3D hollow!
            if 26 <= y <= 68 and collapse_x < FX + hw - 2:
                rx_back = min(FX + hw - 3, collapse_x + 14)
                for bx in range(max(FX - 6, collapse_x - 4), rx_back + 1):
                    for by in range(y, yb + 1):
                        in_lit = 0.14 + 0.08 * hsh(bx, by, seed + 9)
                        put(body, bx, by, shade_stone_px(bx, by, in_lit, seed + 9, crimson=False))

            # Merlon gaps along the very top parapet (`y = 18..23`)
            x_cur = FX - hw + ((course_idx % 2) * 5 - 2)
            x_left_edge = FX - hw
            while x_cur <= collapse_x:
                bw = rng.randint(10, 15)
                bx0 = max(x_left_edge, x_cur)
                bx1 = min(collapse_x, x_cur + bw - 1)
                if bx1 - bx0 >= 3:
                    # Merlon embrasure notch at top course
                    in_embrasure = (y < 24 and (-22 <= (bx0 + bx1) // 2 - FX <= -13))
                    if not in_embrasure:
                        mid_x = (bx0 + bx1) * 0.5
                        rel = (mid_x - FX) / max(1.0, float(hw))
                        # 3/4 fortress lighting: bright sunlit left flank, mid front face, cool violet-slate right flank
                        lit = 0.68 - 0.34 * rel - 0.06 * u_down
                        if rel < -0.52:
                            lit += 0.10
                        elif rel > 0.45:
                            lit -= 0.14
                        draw_ashlar_block(
                            body, bx0, y, bx1, yb, lit, seed + course_idx * 19 + bx0,
                            crimson=is_crimson, chip_tr=(bx1 >= collapse_x - 1 and y < 70),
                        )
                x_cur += bw
            y = yb + 1
            course_idx += 1

        # Crumbled stone arch window / ruined gallery opening on upper-right (`x = 68..84, y = 52..72`)
        acx, acy = 75, 62
        for ay in range(52, 74):
            for ax in range(68, 83):
                dx_a = (ax - acx) / 6.5
                dy_a = (ay - acy) / 9.5
                if (ay <= acy and dx_a * dx_a + dy_a * dy_a <= 1.0) or (ay > acy and abs(dx_a) <= 0.92):
                    # Deep shadowed interior wall visible through the arch + sunlit right inner reveal
                    put(body, ax, ay, STONE[3 if ax >= acx + 3 else (0 if ax < acx else 1)])
                elif 1.0 < dx_a * dx_a + dy_a * dy_a <= 1.48 and ay <= acy + 1:
                    # Radial stone voussoir ring framing the arch!
                    ang = math.atan2(dy_a, dx_a)
                    spoke = int((ang + math.pi) * 3.8)
                    put(body, ax, ay, MORTAR if abs((ang + math.pi) * 3.8 - spoke) < 0.14 else STONE[6 if dx_a < 0 else 4])

        # Heavy arched sally-port / watchtower doorway at lower front-left (`x = 45..63, y = 98..129`)
        dcx, dcy = 54, 108
        for ay in range(97, FY):
            for ax in range(44, 65):
                dx_d = (ax - dcx) / 8.5
                dy_d = (ay - dcy) / 10.0
                if (ay <= dcy and dx_d * dx_d + dy_d * dy_d <= 0.82) or (ay > dcy and abs(dx_d) <= 0.78):
                    # Dark barred oak/iron portal recess
                    if (ax - dcx) % 3 == 0 or ay in (110, 120):
                        put(body, ax, ay, IRON[2 if ax < dcx else 1])
                    else:
                        put(body, ax, ay, STONE[0])
                elif ((ay <= dcy and dx_d * dx_d + dy_d * dy_d <= 1.22) or (ay > dcy and abs(dx_d) <= 1.05)):
                    # Dressed crimson-and-slate voussoir door surround
                    is_j = (ay > dcy and (ay - dcy) % 5 == 0)
                    put(body, ax, ay, MORTAR if is_j else (CRIMSON_STONE[4 if ax < dcx else 2] if (ay // 5) % 2 == 0 else STONE[6 if ax < dcx else 4]))

        # Carved Red Order Sun-Shield Crest on the breastwork (`cx = 54, cy = 48`)
        scx, scy = 54, 48
        for dy in range(-7, 8):
            hw_s = 6.0 if dy < 0 else max(0.5, 6.0 * (1.0 - (dy / 8.0) ** 1.3))
            for dx in range(-7, 8):
                if abs(dx) <= hw_s:
                    rim = (abs(dx) >= hw_s - 1.1) or (dy == -7)
                    if rim:
                        put(body, scx + dx, scy + dy, ORDER_GOLD[4 if dx <= 0 and dy <= 0 else 2])
                    else:
                        put(body, scx + dx, scy + dy, CRIMSON_STONE[4 if dx < 0 else 2])
        # Sunburst + vertical sword relief inside crest + faint ruby glint in `_glow.png`
        for dy in range(-4, 5):
            put(body, scx, scy + dy, ORDER_GOLD[5 if dy <= 0 else 3])
        for dx in (-3, -2, 2, 3):
            put(body, scx + dx, scy - 1, ORDER_GOLD[4 if dx < 0 else 2])
        glow.emit(body, scx, scy - 1, CRIMSON_STONE[6], EMBER_R, halo=1)
        glow.emit(body, scx, scy, ORDER_GOLD[5], EMBER_O, halo=1)

        # Sheltered wrought-iron wall lantern niche beside the doorway (`cx = 71, cy = 98`)
        lcx, lcy = 72, 98
        for dy in range(-6, 6):
            for dx in range(-4, 5):
                if abs(dx) <= 3 and -4 <= dy <= 4:
                    put(body, lcx + dx, lcy + dy, STONE[0])
                elif abs(dx) == 4 or dy in (-5, 5):
                    put(body, lcx + dx, lcy + dy, STONE[5 if dx < 0 or dy < 0 else 2])
        # Wrought-iron lantern frame + warm amber-crimson ember core
        put(body, lcx, lcy - 4, IRON[3])
        put(body, lcx, lcy - 3, IRON[4])
        for dx in (-2, -1, 0, 1, 2):
            put(body, lcx + dx, lcy - 2, IRON[3 if dx <= 0 else 1])
            put(body, lcx + dx, lcy + 3, IRON[2])
        glow.emit(body, lcx, lcy, ORDER_GOLD[5], EMBER_H, halo=2)
        glow.emit(body, lcx - 1, lcy, EMBER_R, EMBER_O, halo=2)
        glow.emit(body, lcx + 1, lcy, EMBER_D, EMBER_R, halo=1)
        glow.emit(body, lcx, lcy + 1, EMBER_R, EMBER_O, halo=2)

        # Structural hairline cracks + tumbled ashlar blocks at right base + lush moss ledges!
        for k in range(24):
            cy_c = 58 + k
            cx_c = 62 + int(round(2.2 * math.sin(k * 0.35)))
            put(body, cx_c, cy_c, MORTAR)
            put(body, cx_c + 1, cy_c, STONE[7])

        for fx_b, fy_b, rx_b, ry_b, tilt, cr in [
            (94, 125, 7.5, 4.2, 0.24, False),
            (104, 127, 6.2, 3.6, -0.18, True),
            (85, 127, 5.8, 3.4, 0.12, False),
            (24, 127, 5.5, 3.2, -0.15, False),
        ]:
            draw_fallen_block(body, fx_b, fy_b, rx_b, ry_b, tilt, seed + fx_b, crimson=cr)

        drape_moss_ledge(body, 29, 49, 18, 2, 4, seed + 1)
        drape_moss_ledge(body, 58, 72, 30, 2, 3, seed + 3)
        drape_moss_ledge(body, 26, 44, 76, 2, 4, seed + 5)
        drape_moss_ledge(body, 21, 41, 114, 2, 3, seed + 7)
        drape_moss_ledge(body, 82, 102, 121, 2, 2, seed + 9)

    else:
        # ---- Col 1: Octagonal/Round Bastion Ruin with collapsed spiral stair wall, fallen voussoirs & iron brazier sconce!
        # Cylindrical/octagonal drum (`x ~ 22..106`, `y = 24..130`), breached open on upper-left/center revealing
        # ascending stone spiral stair steps curving around a central newel pillar!
        for y in range(24, FY + 1):
            u_down = (y - 24) / float(FY - 24)
            hw = 36.0 + 7.0 * (u_down ** 1.4) + (3.0 if y >= 115 else 0.0)
            is_crimson = (52 <= y <= 58) or (108 <= y <= 114)
            course_row = (y - 24) % 7

            for x in range(int(FX - hw - 1), int(FX + hw + 2)):
                rel = (x - FX) / hw
                if abs(rel) > 1.0:
                    continue
                # Breached upper-central/right curtain wall (`y < 76`) exposing the spiral staircase inside!
                breach = False
                if y < 29 and x > FX - 14 + int(3 * hsh(x // 4, 0, seed)):
                    breach = True
                elif 29 <= y < 56 and (FX - 4 + (y - 29) * 0.42) < x < FX + hw - 5 - (10 if y < 38 else (4 if y < 48 else 0)):
                    breach = True
                elif 56 <= y < 74 and (FX + 8 + (y - 56) * 0.55) < x < FX + hw - 9:
                    breach = True

                if breach:
                    # Ruined inner back-wall drops in jagged stair-steps (`top_back_y`) instead of a flat line!
                    top_back_y = 28 + max(0, (x - (FX - 8)) // 4) * 3 + (2 if (x // 5) % 2 else 0)
                    if y >= top_back_y and abs(rel) < 0.94:
                        if FX - 1 <= x <= FX + 5 and y >= 33:
                            n_lit = 0.55 - 0.12 * (x - FX)
                            put(body, x, y, shade_stone_px(x, y, n_lit, seed + 21, catch_left=(x == FX - 1)))
                        else:
                            in_lit = 0.16 + 0.14 * rel
                            if course_row == 0:
                                put(body, x, y, MORTAR)
                            else:
                                put(body, x, y, shade_stone_px(x, y, in_lit, seed + 23, crimson=(y in range(52, 57))))
                    continue

                # Cylindrical/octagonal facet normal (`3 octagonal faces` visible across -1..+1)
                facet = -0.58 if rel < -0.36 else (0.0 if rel < 0.36 else 0.58)
                lit = 0.54 - 0.38 * facet - 0.14 * rel - 0.05 * u_down
                # Mortar courses & staggered vertical joints
                c_id = (y - 24) // 7
                ang_slot = (rel + 1.0) * 3.6 + (0.5 if c_id % 2 else 0.0)
                is_joint = (course_row == 6) or (abs(ang_slot - round(ang_slot)) < 0.075) or abs(abs(rel) - 0.36) < 0.025
                if is_joint:
                    put(body, x, y, MORTAR)
                else:
                    ct = (course_row == 0)
                    cl = abs(ang_slot - math.floor(ang_slot) - 0.09) < 0.05
                    put(body, x, y, shade_stone_px(x, y, lit, seed + c_id * 7, crimson=is_crimson, catch_top=ct, catch_left=cl))

        # Ascending stone spiral staircase steps inside the breached bastion (`y = 40..72`)
        for st_i in range(7):
            sy = 68 - st_i * 4
            sx0 = FX + 3 + (st_i % 4) * 3 - (6 if st_i >= 4 else 0)
            sx1 = sx0 + 13
            for yy in range(sy, sy + 3):
                for xx in range(sx0, sx1 + 1):
                    put(body, xx, yy, STONE[7 if yy == sy else (4 if yy == sy + 1 else 1)])

        # Narrow lancet arrow-slit on the sunlit left octagonal face (`x = 40..44, y = 66..88`)
        for yy in range(66, 89):
            put(body, 41, yy, STONE[0])
            put(body, 42, yy, STONE[0])
            put(body, 43, yy, STONE[6])  # Sunlit inner splay bevel
            if yy in (65, 89):
                for xx in range(39, 45):
                    put(body, xx, yy, CRIMSON_STONE[4])

        # Small weathered Order shield plaque below arrow-slit (`cx = 42, cy = 98`)
        for dy in range(-4, 5):
            hw_p = 3 if dy < 1 else max(0, 4 - dy)
            for dx in range(-hw_p, hw_p + 1):
                put(body, 42 + dx, 98 + dy, ORDER_GOLD[4] if abs(dx) == hw_p or dy == -4 else CRIMSON_STONE[4 if dx <= 0 else 2])
        glow.emit(body, 42, 98, ORDER_GOLD[5], EMBER_R, halo=1)

        # Wrought-iron brazier sconce mounted on the front bastion pier (`cx = 72, cy = 88`)
        bcx, bcy = 72, 88
        # Iron wall bracket arm
        for dy in range(0, 7):
            put(body, bcx - 4, bcy + dy, IRON[3])
            put(body, bcx - 3, bcy + dy, IRON[1])
        for dx in range(-4, 1):
            put(body, bcx + dx, bcy + 4, IRON[2])
        # Fluted iron fire-basket (`x = bcx-5..bcx+5, y = bcy-3..bcy+3`)
        for dy in range(-2, 4):
            hw_b = 5 - max(0, dy - 1)
            for dx in range(-hw_b, hw_b + 1):
                if dy == -2 or dx % 2 == 0:
                    put(body, bcx + dx, bcy + dy, IRON[4 if dx < 0 else 2])
                else:
                    put(body, bcx + dx, bcy + dy, EMBER_D if dy <= 0 else IRON[0])
        # Warm glowing brazier embers in `order_watchtower_glow.png`
        for gx, gy, d_c, b_c, hl in [
            (bcx, bcy - 3, ORDER_GOLD[5], EMBER_H, 2),
            (bcx - 1, bcy - 2, EMBER_O, EMBER_H, 2),
            (bcx + 1, bcy - 2, EMBER_R, EMBER_O, 2),
            (bcx - 2, bcy - 3, EMBER_R, EMBER_O, 1),
            (bcx + 2, bcy - 1, EMBER_D, EMBER_R, 1),
        ]:
            glow.emit(body, gx, gy, d_c, b_c, halo=hl)

        # Mossy fallen curved voussoir arch blocks at the base (`x = 76..110, y = 122..130`)
        for fx_b, fy_b, rx_b, ry_b, tilt, cr in [
            (86, 126, 7.8, 4.0, 0.32, True),
            (98, 127, 7.0, 3.8, -0.25, False),
            (107, 128, 5.4, 3.0, 0.18, False),
            (23, 127, 6.2, 3.5, -0.20, False),
        ]:
            draw_fallen_block(body, fx_b, fy_b, rx_b, ry_b, tilt, seed + fx_b, crimson=cr)

        drape_moss_ledge(body, 28, 52, 24, 3, 5, seed + 31)
        drape_moss_ledge(body, 84, 100, 73, 2, 4, seed + 33)
        drape_moss_ledge(body, 22, 48, 114, 2, 3, seed + 35)
        drape_moss_ledge(body, 80, 104, 122, 2, 2, seed + 37)

    # Creeping ivy vines, pale crust lichen & base clover/fern tufts on both watchtowers
    for vx0 in (33, 82) if variant == 0 else (35, 88):
        for k in range(22):
            vx = vx0 + int(round(2.4 * math.sin(k * 0.45 + variant)))
            vy = FY - 3 - k
            if body[vy][vx][3] == 255:
                put(body, vx, vy, MOSS[4 if k % 2 == 0 else 3])
                put(body, vx + 1, vy, MOSS[1])
    for _ in range(16):
        lx, ly = rng.randrange(26, 100), rng.randrange(36, 124)
        if body[ly][lx] in STONE[2:7]:
            put(body, lx, ly, LICHEN[1])
            put(body, lx + 1, ly, LICHEN[0])

    for tx in range(20, 108, 9):
        if hsh(tx, variant, 99) > 0.35:
            by = FY + (1 if 34 <= tx <= 94 else 0)
            for bdx, bdy, mi in [(-2, -2, 4), (-1, -3, 5), (0, -1, 2), (1, -3, 4), (2, -1, 3)]:
                put(body, tx + bdx, by + bdy, MOSS[mi])

    out = add_shadow_and_outline(body, FX + 2, FY, rx=52.0, ry=6.5, out_col=OUT)
    return out, glow.finish()


# ==============================================================================
# 2. Order Patrol Camp (`order_patrol_camp.png` & `_glow.png`, 2x1 of 96x64, feet (48, 52))
# ==============================================================================
def draw_line_thick(px, x0: float, y0: float, x1: float, y1: float, r: float, col_fn):
    steps = max(1, int(math.hypot(x1 - x0, y1 - y0) * 2.5))
    ir = int(math.ceil(r + 0.5))
    for i in range(steps + 1):
        t = i / float(steps)
        cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        ix, iy = int(round(cx)), int(round(cy))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= (r + 0.15) ** 2:
                    c = col_fn(ix + dx, iy + dy, dx, dy, t)
                    if c is not None:
                        put(px, ix + dx, iy + dy, c)


def build_patrol_camp_variant(variant: int):
    W, H = 96, 64
    FX, FY = 48, 52
    seed = 1511 + variant * 43
    rng = random.Random(seed)
    body = blank(W, H)
    glow = GlowMap(W, H)

    # Subtle mossy trodden earth / fern patch under the left/center camp (`x = 10..67`, leaving `x = 68..86` clear on Col 0!)
    max_x_clutter = 66 if variant == 0 else 80
    for gx in range(12, max_x_clutter, 5):
        gy = FY - 2 + int(3.0 * math.sin(gx * 0.23 + variant))
        for bdx, bdy, mi in [(-2, -1, 3), (-1, -2, 5), (0, -1, 2), (1, -2, 4), (2, 0, 2)]:
            put(body, gx + bdx, gy + bdy, MOSS[mi])
        if gx % 10 == 2:
            put(body, gx, gy - 3, CLOVER_FL[2])
            put(body, gx + 1, gy - 2, CLOVER_FL[1])

    if variant == 0:
        # ---- Col 0: Overgrown Red Order Patrol Campsite (leaving x ~ 68..84 open for separate banner pole!)
        # 1) Rotted leather pack & weathered Crimson-Order heater shield half-buried in fern/clover (`x = 13..31, y = 35..49`)
        for y in range(36, 48):
            for x in range(13, 25):
                dx, dy = (x - 18.5) / 5.8, (y - 42.0) / 5.5
                if dx * dx + dy * dy <= 1.0:
                    lit = 0.55 - 0.35 * dx - 0.35 * dy
                    col = LEATHER[int(clamp(lit * 4.5, 0, 4))]
                    if x in (16, 21):
                        col = ORDER_GOLD[3] if y == 41 else LEATHER[1]  # Buckled pack straps
                    put(body, x, y, col)

        # Tilted Crimson-Order heater shield leaning against the pack (`cx = 26, cy = 43`)
        for dy in range(-6, 7):
            hw_sh = 5.5 if dy < 0 else max(0.6, 5.5 * (1.0 - (dy / 7.5) ** 1.3))
            for dx in range(-6, 7):
                sx, sy = int(round(26 + dx - dy * 0.25)), 43 + dy
                if abs(dx) <= hw_sh:
                    if abs(dx) >= hw_sh - 1.1 or dy == -6:
                        put(body, sx, sy, ORDER_GOLD[4 if dx < 0 else 2])
                    else:
                        put(body, sx, sy, CRIMSON_STONE[5 if dx < 0 and dy < 0 else (3 if dx <= 1 else 1)])
        put(body, 26, 42, ORDER_GOLD[5])
        put(body, 26, 43, ORDER_GOLD[4])
        # Fern fronds creeping over the shield's lower edge
        for dx, dy, mi in [(-3, 5, 5), (-2, 4, 4), (-1, 5, 3), (0, 6, 4), (2, 5, 5), (3, 6, 3)]:
            put(body, 26 + dx, 43 + dy, MOSS[mi])

        # 2) Cold moss-rimmed stone fire-ring with grey ash & charred billets (`cx = 51, cy = 46`, well left of x=68!)
        fcx, fcy = 51, 46
        for y in range(fcy - 5, fcy + 6):
            for x in range(fcx - 10, fcx + 11):
                d = ((x - fcx) / 9.2) ** 2 + ((y - fcy) / 4.6) ** 2
                if d <= 0.62:
                    n = hsh(x, y, seed + 11)
                    put(body, x, y, ASH[3 if n > 0.72 else (2 if n > 0.35 else 1)])
        # Charred cold wood sticks crossed in the ash
        for k in range(-5, 6):
            put(body, fcx + k, fcy + k // 3, WOOD[0 if k > 0 else 1])
            put(body, fcx + k, fcy - k // 3, WOOD[1 if k < 0 else 0])
        # Ring of 9 mossy cobbles around the cold hearth
        for i_s in range(9):
            ang = (i_s / 9.0) * math.tau
            rx_c = fcx + math.cos(ang) * 9.5
            ry_c = fcy + math.sin(ang) * 4.8
            draw_fallen_block(body, rx_c, ry_c, 3.1, 2.0, ang * 0.2, seed + i_s * 7)
            if i_s in (2, 3, 4, 5):
                put(body, int(round(rx_c)), int(round(ry_c - 1.5)), MOSS[4])

        # 3) Prominent Rusted Knight's Greatsword driven blade-down into the turf at center-left (`x ~ 35..39, y = 11..49`)!
        # Slight heroic lean: pommel at `(34, 11)`, crossguard at `(36, 22)`, blade entering turf at `(39, 48)`
        # Earth/moss sod mound around embedded blade point
        for dx in range(-5, 6):
            put(body, 39 + dx, 48, MOSS[4 if dx < 0 else 2])
            put(body, 39 + dx, 49, MOSS[2 if dx < 0 else 1])

        # Broad two-handed steel blade (`t = 0` at crossguard `(36, 23)` -> `t = 1` at earth `(39, 48)`)
        steps_b = 26
        for i in range(steps_b):
            t = i / float(steps_b - 1)
            bx = 36.0 + 3.0 * t
            by = 23 + i
            ix = int(round(bx))
            # 5px wide rusted greatsword blade: sunlit left bevel, fuller groove with faint rune, rust-pitted right bevel
            put(body, ix - 2, by, STEEL[6 if i % 4 != 2 else 4])
            put(body, ix - 1, by, RUST[4] if (i in (5, 6, 13, 14, 20)) else STEEL[5])
            # Central fuller groove + crimson memory rune glimmer!
            if i in (4, 7, 10, 13, 16, 19):
                glow.emit(body, ix, by, RUNE_D, RUNE_M if i % 2 == 0 else RUNE_G, halo=1)
            else:
                put(body, ix, by, STEEL[1])
            put(body, ix + 1, by, RUST[3] if (i in (3, 8, 9, 15, 16, 22)) else STEEL[3])
            put(body, ix + 2, by, RUST[1] if i % 5 == 0 else STEEL[1])

        # Winged Cruciform Red Order Crossguard (`y = 21..23`, `x = 29..43`) with gold central sun-boss
        for dx in range(-7, 8):
            gy = 22 + (1 if dx > 3 else (-1 if dx < -4 else 0))
            col_g = RUST[4] if dx in (-3, 4) else STEEL[5 if dx < 0 else 2]
            put(body, 36 + dx, gy, col_g)
            put(body, 36 + dx, gy + 1, STEEL[1])
        put(body, 36, 22, ORDER_GOLD[5])
        put(body, 35, 22, ORDER_GOLD[3])

        # Leather-wrapped two-handed grip (`y = 13..21`) + heavy faceted wheel pommel (`y = 10..12`)
        for k in range(9):
            gy = 21 - k
            gx = int(round(36.0 - k * 0.22))
            put(body, gx - 1, gy, LEATHER[4 if k % 2 == 0 else 2])
            put(body, gx, gy, CRIMSON_STONE[4] if k % 2 == 0 else LEATHER[1])
            put(body, gx + 1, gy, LEATHER[0])
        for dy in (-1, 0, 1):
            for dx in (-2, -1, 0, 1, 2):
                if abs(dx) + abs(dy) <= 2:
                    put(body, 34 + dx, 11 + dy, ORDER_GOLD[5 if (dx <= 0 and dy <= 0) else 2])
        put(body, 34, 11, CRIMSON_STONE[5])
        # Tattered crimson sword-knot ribbon fluttering from crossguard
        for rx_k, ry_k, ci in [(34, 24, 5), (33, 25, 4), (32, 26, 5), (32, 27, 3), (31, 28, 2)]:
            put(body, rx_k, ry_k, BANNER_RED[ci])

    else:
        # ---- Col 1: Mossy Stone Cairn, Collapsed Canvas Bedroll, Planted Rusted Order Halberd/Sword, Kettle & Scroll Tube!
        # 1) Collapsed weathered canvas bedroll/shelter tarp on wooden A-poles (`x = 14..42, y = 34..48`)
        for y in range(36, 48):
            u_y = (y - 36) / 11.0
            x0_t = int(16 - 2 * u_y)
            x1_t = int(39 + 3 * u_y)
            for x in range(x0_t, x1_t + 1):
                sag = 1.8 * math.sin((x - x0_t) * 0.26)
                lit = 0.62 - 0.30 * u_y - 0.20 * ((x - 27) / 14.0) + 0.08 * sag
                col = CANVAS[int(clamp(lit * 4.6 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5, 0, 4))]
                # Faded crimson Order stripe along the canvas edge
                if x0_t + 3 <= x <= x0_t + 5:
                    col = CRIMSON_STONE[4 if u_y < 0.5 else 2]
                put(body, x, y, col)
        # Broken wooden ridge-pole sticking out of the collapsed bedroll
        draw_line_thick(body, 14, 46, 43, 35, 1.1, lambda x, y, dx, dy, t: WOOD[4 if dy <= 0 else 1])
        drape_moss_ledge(body, 18, 34, 44, 2, 1, seed + 5)

        # 2) Mossy patrol stone cairn (`x = 58..75, y = 31..49`)
        cairn_stones = [
            (62, 47, 5.2, 2.8, -0.1), (70, 47, 5.0, 2.7, 0.12),
            (66, 42, 5.6, 2.9, 0.05),
            (65, 37, 4.6, 2.5, -0.08),
            (66, 33, 3.5, 2.1, 0.04),
        ]
        for ci, (cx_s, cy_s, rx_s, ry_s, tl) in enumerate(cairn_stones):
            draw_fallen_block(body, cx_s, cy_s, rx_s, ry_s, tl, seed + ci * 13, crimson=(ci == 1))
        drape_moss_ledge(body, 61, 71, 32, 2, 3, seed + 17)

        # 3) Rusted Order Halberd / Pole-Blade planted upright in the turf (`x ~ 48..52, y = 8..49`)
        # Ash-wood & iron-shod shaft (`y = 14..49`)
        for y in range(14, 50):
            sx = int(round(49.0 + (y - 14) * 0.06))
            put(body, sx - 1, y, WOOD[4 if y % 5 != 0 else 2])
            put(body, sx, y, WOOD[2])
            put(body, sx + 1, y, WOOD[0])
        # Crescent halberd axe-blade on left (`x = 41..48, y = 13..25`), back-spike on right (`x = 50..54`), spear tip (`y = 7..14`)
        for y in range(7, 15):
            hw_tip = max(0, (y - 7) // 2)
            for dx in range(-hw_tip, hw_tip + 1):
                put(body, 49 + dx, y, STEEL[6 if dx < 0 else (3 if dx == 0 else 1)])
        for y in range(14, 26):
            dy_h = (y - 19.5) / 5.5
            x_edge = int(round(42.0 + 2.2 * (dy_h * dy_h)))
            for x in range(x_edge, 49):
                if x == x_edge:
                    col = STEEL[6]
                elif (x + y) % 5 == 0:
                    col = RUST[4 if x < 46 else 2]
                else:
                    col = STEEL[4 if x < 46 else 2]
                put(body, x, y, col)
        for dx in range(1, 5):
            put(body, 49 + dx, 18 + dx // 2, RUST[3] if dx == 2 else STEEL[3])
        # Glowing crimson Order rune etched on the halberd collar (`(48, 18..21)`)
        glow.emit(body, 47, 19, RUNE_D, RUNE_M, halo=1)
        glow.emit(body, 47, 20, RUNE_D, RUNE_G, halo=1)
        # Small tattered wine-red pennant below halberd head
        for px_t, py_t, ci in [(50, 22, 5), (51, 23, 4), (52, 24, 5), (51, 25, 3), (52, 26, 2)]:
            put(body, px_t, py_t, BANNER_RED[ci])

        # 4) Dented iron patrol kettle (`x = 39..46, y = 44..50`) & scattered parchment scroll tube with glowing wax seal (`x = 53..63, y = 48..51`)
        for y in range(44, 50):
            for x in range(39, 46):
                dx, dy = (x - 42.0) / 3.4, (y - 47.0) / 2.9
                if dx * dx + dy * dy <= 1.0:
                    col = RUST[3] if (x == 43 and y == 47) else IRON[4 if dx < -0.2 else (2 if dx < 0.4 else 0)]
                    put(body, x, y, col)
        put(body, 41, 43, IRON[3])
        put(body, 43, 43, IRON[2])

        # Parchment scroll tube + glowing crimson Order wax seal at `(57, 49)`
        for i_p in range(8):
            px_s = 54 + i_p
            py_s = 49 + (1 if i_p >= 4 else 0)
            put(body, px_s, py_s - 1, PARCHMENT[4 if i_p < 5 else 3])
            put(body, px_s, py_s, PARCHMENT[2 if i_p < 5 else 1])
        glow.emit(body, 57, 49, CRIMSON_STONE[6], RUNE_M, halo=2)
        glow.emit(body, 58, 49, ORDER_GOLD[4], RUNE_H, halo=1)

    rx_s = 30.0 if variant == 0 else 36.0
    cx_s = 39 if variant == 0 else 46
    out = add_shadow_and_outline(body, cx_s, FY - 2, rx=rx_s, ry=5.5, out_col=OUT)
    return out, glow.finish()


# ==============================================================================
# 3. Swaying Red Order Banner (`order_banner.png`, 32x64, ground/pole-foot anchor (16, 58))
#    NOTE: Keep x = 0..4 and x = 27..31 STRICTLY TRANSPARENT for sway_rows.gdshader!
# ==============================================================================
def build_order_banner():
    W, H = 32, 64
    body = blank(W, H)

    # Iron-shod wooden lance/banner pole at x = 9..11, y = 5..58 (with 1px outline -> x >= 8, safely >= 5!)
    # Spearhead finial at y = 3..7
    for y, xs in [(3, [10]), (4, [9, 10, 11]), (5, [9, 10, 11]), (6, [10])]:
        for x in xs:
            put(body, x, y, STEEL[6 if x <= 10 else 3])

    # Horizontal iron crossbar at y = 7..8, x = 7..25 (with 1px outline -> x = 6..26, leaving x=0..5 and x=27..31 100% clear!)
    for x in range(7, 26):
        put(body, x, 7, IRON[4 if x < 18 else 3])
        put(body, x, 8, IRON[1])
    put(body, 7, 7, ORDER_GOLD[4])
    put(body, 25, 7, ORDER_GOLD[3])

    # Wooden lance shaft from y = 7 down to iron ground spike at y = 58
    for y in range(7, 58):
        if y >= 53:
            # Iron ground shoe
            put(body, 9, y, STEEL[4])
            put(body, 10, y, STEEL[2])
            if y < 56:
                put(body, 11, y, STEEL[1])
        else:
            put(body, 9, y, WOOD[4 if y % 6 != 0 else 3])
            put(body, 10, y, WOOD[2])
            put(body, 11, y, WOOD[1])
        # Brass/leather pole rings tying banner luff to pole
        if y in (12, 20, 28, 36):
            put(body, 9, y, ORDER_GOLD[4])
            put(body, 10, y, ORDER_GOLD[2])
            put(body, 11, y, ORDER_GOLD[1])

    # Small mossy sod tuft at base of pole (`y = 56..58, x = 8..13` — note y > 8 sways slightly or sits at base)
    for dx, dy, mi in [(-2, 0, 4), (-1, -1, 5), (0, 0, 3), (1, -1, 4), (2, 0, 2)]:
        put(body, 10 + dx, 57 + dy, MOSS[mi])

    # Torn, weathered wine-red Red Order cloth banner (`y = 9..48`, `x = 12..25`, so with 1px outline max x is 26 <= 26!)
    for y in range(9, 49):
        u_y = (y - 9) / 39.0
        for x in range(12, 26):
            # Battle-torn notches on right fly edge & tattered 3-tail bottom (`y >= 38`)
            if x == 25 and (16 <= y <= 19 or 29 <= y <= 33 or y >= 41):
                continue
            if x == 24 and (17 <= y <= 18 or 30 <= y <= 31 or y >= 44):
                continue
            # Ragged 3-tail swallowtail cuts at bottom (`y = 38..48`)
            if y >= 38:
                tail_depth = y - 37
                # Gap 1 around x = 15..16, Gap 2 around x = 20..21
                if x in (15, 16) and tail_depth >= 3:
                    continue
                if x in (20, 21) and tail_depth >= 2:
                    continue
                if x in (12, 13, 14) and y >= 47 - (14 - x):
                    continue
                if x in (17, 18, 19) and y >= 48 - abs(x - 18):
                    continue
                if x >= 22 and y >= 45 - (x - 22):
                    continue

            # Vertical cloth drape folds + top-left sunlight + Bayer weave texture
            fold = math.sin((x - 12) * 0.62 + y * 0.08)
            lit = 0.56 - 0.24 * u_y - 0.16 * ((x - 12) / 13.0) + 0.22 * fold
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.48
            col = BANNER_RED[int(clamp(lit * 6.2 + dith, 0, len(BANNER_RED) - 1))]

            # Faded gold border trim along top & side hems (broken by weathering)
            if y == 10 or (x == 13 and y < 38 and y % 5 != 0) or (x == 23 and y < 36 and y % 4 != 0):
                col = ORDER_GOLD[3 if fold > 0 else 1]
            put(body, x, y, col)

    # Faded Gold Red Order Sun-Sword Emblem centered on cloth (`cx = 18, cy = 22`)
    ecx, ecy = 18, 22
    # Radiant sun-ring + cardinal rays
    for dy in range(-5, 6):
        for dx in range(-4, 5):
            r = math.hypot(dx, dy * 0.9)
            if 2.6 <= r <= 3.7 and (dx + dy) % 5 != 0:
                put(body, ecx + dx, ecy + dy, ORDER_GOLD[4 if dx <= 0 and dy <= 0 else 2])
    # Vertical Order blade + crossguard through sun center
    for dy in range(-7, 9):
        if dy != 5:  # Slight weathered flake in gold leaf
            put(body, ecx, ecy + dy, ORDER_GOLD[5 if dy <= 0 else 3])
    for dx in (-3, -2, -1, 1, 2, 3):
        put(body, ecx + dx, ecy - 3, ORDER_GOLD[4 if dx < 0 else 2])
    put(body, ecx, ecy, ORDER_GOLD[6])

    framed = outline_pass(body, OUT)
    # Enforce hard safety guarantee: x = 0..4 and x = 27..31 strictly transparent!
    for y in range(H):
        for x in (0, 1, 2, 3, 4, 27, 28, 29, 30, 31):
            framed[y][x] = CLEAR

    # Subtle ground shadow right under the pole foot `(10, 58)` within safe non-clipped rows (actually rows > 8 sway slightly, so keep shadow tight `x = 6..15`)
    for y in range(57, 61):
        for x in range(6, 16):
            if framed[y][x][3] == 0:
                d = ((x - 10.0) / 4.8) ** 2 + ((y - 58.5) / 2.0) ** 2
                if d < 1.0:
                    framed[y][x] = (*SHADOW_RGB, 96 if d < 0.5 else 48)
    return framed


# ==============================================================================
# 4. Order Boundary Stones (`order_boundary_stone.png` & `_glow.png`, 3x1 of 48x56, feet (24, 48))
# ==============================================================================
def build_boundary_stone(variant: int):
    W, H = 48, 56
    FX, FY = 24, 48
    seed = 1723 + variant * 37
    body = blank(W, H)
    glow = GlowMap(W, H)

    if variant == 0:
        # ---- Col 0: Upright chamfered obelisk stele (~40px tall, 22px wide at plinth) with chiselled script, sword-sun crest & moss cap
        # Stepped stone plinth (`y = 42..48, x = 12..36`)
        draw_ashlar_block(body, 13, 43, 35, 48, 0.56, seed + 1)
        draw_ashlar_block(body, 15, 39, 33, 42, 0.62, seed + 2, crimson=True)
        # Tapered chamfered obelisk shaft (`y = 8..38`) with pyramidal peak (`y = 8..14`)
        for y in range(8, 39):
            if y < 14:
                hw = 2.0 + (y - 8) * 1.15
            else:
                hw = 9.0 + (y - 14) * 0.06
            for x in range(int(FX - hw), int(FX + hw) + 1):
                rel = (x - FX) / max(1.0, hw)
                # 3 chamfered vertical planes: bright left bevel, broad front tablet face, cool dark right bevel
                if rel < -0.62:
                    lit = 0.86
                elif rel > 0.62:
                    lit = 0.22
                else:
                    lit = 0.56 - 0.14 * rel
                put(body, x, y, shade_stone_px(x, y, lit, seed + 5, catch_top=(y < 14 and abs(abs(rel) - 1.0) < 0.25)))

        # Chiselled Red Order Sword-Sun Crest (`cy = 21`) + horizontal script lines (`y = 29, 32, 35`)
        for dy in range(-5, 6):
            put(body, FX, 21 + dy, STONE[0])
        for dx in (-3, -2, -1, 1, 2, 3):
            put(body, FX + dx, 19, STONE[0])
        # Sun ring around sword
        for dx, dy in [(-2, -1), (2, -1), (-2, 1), (2, 1), (-3, 0), (3, 0)]:
            put(body, FX + dx, 21 + dy, ORDER_GOLD[3])
        glow.emit(body, FX, 19, ORDER_GOLD[5], RUNE_H, halo=2)
        glow.emit(body, FX, 21, CRIMSON_STONE[5], RUNE_G, halo=2)
        glow.emit(body, FX, 23, CRIMSON_STONE[4], RUNE_M, halo=1)

        for sy in (29, 32, 35):
            for sx in range(FX - 5, FX + 6):
                if (sx + sy) % 4 != 0:
                    put(body, sx, sy, STONE[1])
                    put(body, sx, sy + 1, STONE[7])  # Crisp sunlit lower lip of chiselled letter groove!
                    if (sx + sy) % 3 == 0:
                        glow.emit(body, sx, sy, CRIMSON_STONE[4], RUNE_G, halo=1)

        drape_moss_ledge(body, 17, 29, 9, 2, 4, seed + 11)
        drape_moss_ledge(body, 13, 21, 42, 2, 2, seed + 13)

    elif variant == 1:
        # ---- Col 1: Tilted cracked tablet stele (~38px tall) with crimson-red ribbon tied around its neck & creeping ivy!
        for y in range(10, 49):
            u = (y - 10) / 38.0
            cx = FX - 2.2 * (1.0 - u)  # Leans slightly to the left
            # Rounded head with slight neck waist at `y = 20..23` where ribbon is tied!
            if y < 15:
                hw = math.sqrt(max(0.0, 1.0 - ((15 - y) / 5.5) ** 2)) * 9.5
            elif 19 <= y <= 23:
                hw = 8.4  # Carved neck notch for ribbon
            else:
                hw = 9.5 + u * 1.4
            for x in range(int(round(cx - hw)), int(round(cx + hw)) + 1):
                rel = (x - cx) / max(1.0, hw)
                lit = 0.78 if rel < -0.68 else (0.20 if rel > 0.66 else (0.54 - 0.16 * rel))
                put(body, x, y, shade_stone_px(x, y, lit, seed + 7, catch_top=(y <= 12)))

        # Diagonal fracture crack across middle of tablet
        for dx in range(-8, 9):
            cy_c = 28 + dx // 3
            cx_c = int(round(FX - 1 + dx))
            if body[cy_c][cx_c][3] == 255:
                put(body, cx_c, cy_c, MORTAR)
                put(body, cx_c, cy_c + 1, STONE[8])

        # Crimson-red memorial ribbon tied snugly around the stele's neck (`y = 20..22`) with fluttering tails on right!
        for x in range(14, 32):
            if body[21][x][3] == 255:
                put(body, x, 20, BANNER_RED[6 if x < 23 else 4])
                put(body, x, 21, BANNER_RED[5 if x < 23 else 3])
                put(body, x, 22, BANNER_RED[2])
        # Knot & two trailing crimson ribbon tails (`x = 30..36, y = 21..29`)
        for rx_t, ry_t, ci in [
            (30, 21, 6), (31, 22, 5), (32, 23, 6), (33, 24, 5), (34, 25, 4), (35, 26, 3),
            (30, 23, 4), (31, 24, 3), (31, 25, 4), (32, 27, 3), (32, 28, 2),
        ]:
            put(body, rx_t, ry_t, BANNER_RED[ci])

        # Recessed rune crest above ribbon (`cy = 15`) + glowing lines below crack
        for dx, dy in [(0, -2), (0, -1), (0, 0), (-2, -1), (2, -1), (-1, 1), (1, 1)]:
            glow.emit(body, FX - 2 + dx, 16 + dy, CRIMSON_STONE[5], RUNE_H if dx == 0 and dy == -1 else RUNE_G, halo=1)
        for sx in range(18, 29, 2):
            glow.emit(body, sx, 33, CRIMSON_STONE[4], RUNE_M, halo=1)

        # Creeping ivy vine climbing up the right flank
        for k in range(20):
            iy = 47 - k
            ix = 29 + int(round(2.0 * math.sin(k * 0.5)))
            put(body, ix, iy, MOSS[4 if k % 2 == 0 else 3])
            put(body, ix - 1, iy, MOSS[5 if k % 3 == 0 else 2])

    else:
        # ---- Col 2: Twin-notched pass marker stone (~39px tall, 24px wide) with recessed rune medallion & lichen clusters
        draw_ashlar_block(body, 11, 43, 37, 48, 0.54, seed + 17)
        for y in range(9, 43):
            u = (y - 9) / 34.0
            # Twin-horned / notched summit (`y = 9..14` dips in center `FX`, rises on shoulders `FX-6` and `FX+6`)
            notch_y = 9 + int(3.2 * math.exp(-((0) ** 2)))  # handled per x below
            hw = 10.2 + u * 1.6
            if 18 <= y <= 21:
                hw -= 1.5  # Side shoulder notches!
            for x in range(int(FX - hw), int(FX + hw) + 1):
                top_curve = 9.0 + 3.6 * math.exp(-(((x - FX) / 3.2) ** 2)) + 0.35 * max(0.0, abs(x - FX) - 5.5)
                if y < top_curve:
                    continue
                rel = (x - FX) / max(1.0, hw)
                lit = 0.82 if rel < -0.66 else (0.20 if rel > 0.66 else (0.55 - 0.14 * rel))
                is_cr = (37 <= y <= 40)
                put(body, x, y, shade_stone_px(x, y, lit, seed + 19, crimson=is_cr, catch_top=(y - top_curve < 1.2)))

        # Circular recessed rune medallion (`cx = 24, cy = 26, r = 5.5`)
        mcx, mcy = FX, 26
        for dy in range(-6, 7):
            for dx in range(-6, 7):
                r = math.hypot(dx, dy)
                if r <= 4.3:
                    put(body, mcx + dx, mcy + dy, CRIMSON_STONE[2 if dx > 0 else 1])
                elif r <= 5.6:
                    put(body, mcx + dx, mcy + dy, ORDER_GOLD[4 if (dx < 0 and dy < 0) else 2])
        # Glowing crimson-gold Order cross-sun rune inside medallion!
        glow.emit(body, mcx, mcy, ORDER_GOLD[6], RUNE_H, halo=2)
        for dx, dy in [(-2, 0), (-1, 0), (1, 0), (2, 0), (0, -2), (0, -1), (0, 1), (0, 2)]:
            glow.emit(body, mcx + dx, mcy + dy, ORDER_GOLD[4], RUNE_G, halo=1)

        # Pale crust lichen & moss tufts
        for lx, ly in [(16, 16), (17, 17), (30, 31), (31, 32), (17, 34), (29, 17)]:
            put(body, lx, ly, LICHEN[1])
            put(body, lx + 1, ly, LICHEN[0])
        drape_moss_ledge(body, 14, 20, 10, 2, 3, seed + 23)
        drape_moss_ledge(body, 28, 34, 10, 2, 2, seed + 25)

    # Base grass & clover around stele foot
    for tx in (13, 19, 28, 34):
        for bdx, bdy, mi in [(-1, -2, 5), (0, -3, 4), (0, -1, 2), (1, -2, 3)]:
            put(body, tx + bdx, FY + bdy, MOSS[mi])

    out = add_shadow_and_outline(body, FX, FY, rx=16.5, ry=4.2, out_col=OUT)
    return out, glow.finish()


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/red_order_sheet.png`)
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
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.46)), max(14, int(c[2] * 0.66)), c[3])
    return out


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


def render_qa_sheet(towers, camps, banner, steles):
    cw, ch = 500, 340
    canvas = blank(cw, ch)
    half = 170
    for y in range(ch):
        night = y >= half
        for x in range(cw):
            n = noise(x // 4, y // 3, 131)
            if not night:
                canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
            else:
                canvas[y][x] = (20, 28, 48, 255) if n < 115 else ((25, 36, 58, 255) if n < 205 else (31, 44, 68, 255))

    for p_i in range(2):
        night = p_i == 1
        yo = 0 if not night else half

        # 2 Watchtowers on left (`x = 8` and `x = 140`)
        for i in range(2):
            t_px, t_gl = towers[i]
            ox, oy = 8 + i * 132, yo + 12
            alpha_over(canvas, tint_night_px(t_px) if night else t_px, ox, oy)
            if night:
                add_glow_over(canvas, t_gl, ox, oy)

        # 2 Patrol Camps on upper right (`x = 278` and `x = 384`), with `order_banner.png` composited in Col 0's right slot (`x ~ 74`) + standalone banner!
        for i in range(2):
            c_px, c_gl = camps[i]
            ox, oy = 278 + i * 106, yo + 26
            alpha_over(canvas, tint_night_px(c_px) if night else c_px, ox, oy)
            if night:
                add_glow_over(canvas, c_gl, ox, oy)
            if i == 0:
                # Composite banner right into the reserved slot (`x = 74, y = 50` in camp frame, minus banner anchor `(16, 58)` -> `(ox+58, oy-8)`)
                alpha_over(canvas, tint_night_px(banner) if night else banner, ox + 58, oy - 8)

        # Standalone `order_banner.png` + 3 `order_boundary_stone.png` steles on lower right
        alpha_over(canvas, tint_night_px(banner) if night else banner, 282, yo + 98)
        for i in range(3):
            s_px, s_gl = steles[i]
            ox, oy = 326 + i * 54, yo + 104
            alpha_over(canvas, tint_night_px(s_px) if night else s_px, ox, oy)
            if night:
                add_glow_over(canvas, s_gl, ox, oy)

    # Upscale 2x for crisp inspection
    big = scale_nn(canvas, 2)
    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, len(big[0]), len(big), big)


def pack_row(frames, fw: int, fh: int):
    out = blank(fw * len(frames), fh)
    for col, f in enumerate(frames):
        for y in range(fh):
            out[y][col * fw:(col + 1) * fw] = f[y]
    return out


def main():
    props = ROOT / "props"

    towers = [build_watchtower_variant(0), build_watchtower_variant(1)]
    wt_sheet = pack_row([t for t, _ in towers], 128, 144)
    wt_glow = pack_row([g for _, g in towers], 128, 144)

    camps = [build_patrol_camp_variant(0), build_patrol_camp_variant(1)]
    cp_sheet = pack_row([c for c, _ in camps], 96, 64)
    cp_glow = pack_row([g for _, g in camps], 96, 64)

    banner = build_order_banner()

    steles = [build_boundary_stone(0), build_boundary_stone(1), build_boundary_stone(2)]
    bs_sheet = pack_row([s for s, _ in steles], 48, 56)
    bs_glow = pack_row([g for _, g in steles], 48, 56)

    outputs = [
        ("order_watchtower.png", wt_sheet, 256, 144),
        ("order_watchtower_glow.png", wt_glow, 256, 144),
        ("order_patrol_camp.png", cp_sheet, 192, 64),
        ("order_patrol_camp_glow.png", cp_glow, 192, 64),
        ("order_banner.png", banner, 32, 64),
        ("order_boundary_stone.png", bs_sheet, 144, 56),
        ("order_boundary_stone_glow.png", bs_glow, 144, 56),
    ]
    for name, px, ew, eh in outputs:
        assert (len(px[0]), len(px)) == (ew, eh), f"{name} size mismatch"
        verify_no_black(name, px)
        write_png(props / name, ew, eh, px)

    render_qa_sheet(towers, camps, banner, steles)
    print("Wrote 7 Red Order PNGs and docs/img/red_order_sheet.png")


if __name__ == "__main__":
    main()
