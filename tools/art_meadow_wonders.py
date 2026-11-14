#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 5 — Die 3 Einmaligen Weltwunder (stdlib + gen_art.py only):
  1. assets/props/bell_spire.png & _glow.png (Der Glockenteich)
     - 2 cols x 1 row of 96x160 (192x160 total), waterline/base anchor at (48, 136):
       * Col 0 (Dormant / Day-Dusk): Sunken ancient stone & verdigris-copper belfry spire rising ~120 px above
                waterline (48, 136), submerged mossy stone arch columns disappearing into turquoise water ripples
                at y=128..146, open arched belfry chamber (y=50..98) housing a heavy verdigris-bronze bell with
                aged gold rim, steep weathered slate-and-copper spire roof (y=12..50) topped by a crescent finial!
       * Col 1 (Awakened / Midnight Toll): Warm turquoise-gold resonance runes awakened on archivolts & bell rim,
                and luminous concentric water rings expanding at the waterline.
  2. assets/props/bell_stepping_stone.png & _glow.png
     - 3 cols x 1 row of 32x32 (96x32 total), center (16, 18):
       * Col 0: Faint dark-teal underwater stone silhouette beneath the surface.
       * Col 1: Raised ancient carved octagonal flagstone (~22x14 px) with wet turquoise water rim & spiral rune.
       * Col 2: Raised mossy step slab with concentric bell-wave glyph.
  3. assets/props/sleeping_guardian.png & _glow.png (Der Kreis der Schlafenden Wächter)
     - 3 cols x 1 row of 80x128 (240x128 total), ground/feet anchor at (40, 116):
       * Col 0: Towering robed monolithic guardian (~98 px tall, 52 px wide) on stepped ashlar plinth, resting both
                stone hands on a grounded runic stone shield/staff, serene bowed crowned head draped in moss.
       * Col 1: Seated/kneeling monolithic sentinel with folded stone wings/cloak, serene closed eyes, ivy & heather.
       * Col 2: 7th Broken/Headless Guardian (~72 px tall), fractured cleanly across the neck/collar with mossy rubble.
  4. assets/props/guardian_brazier.png & _glow.png (plus Fallen Headstone!)
     - 3 cols x 1 row of 40x48 (120x48 total), ground/feet anchor at (20, 40):
       * Col 0: Unlit squat mossy stone offering bowl on pedestal (~24 px tall) with cold ash.
       * Col 1: Lit stone bowl burning with crisp turquoise-gold spirit flame.
       * Col 2: Fallen Guardian Headstone (~26x22 px) resting half-buried in meadow grass & clover.
  5. assets/props/amphitheater_podium.png & _glow.png (Das Blumen-Amphitheater)
     - Single frame 128x96, center/ground anchor at (64, 52):
       Ancient 3/4 circular/octagonal carved stone stage podium (~108 px wide, 66 px deep, 10 px raised rim with
       4 mossy steps N/S/E/W), inlaid with a grand concentric moonflower-and-chord mosaic + glowing harmonic inlays!
  6. docs/img/meadow_wonders_sheet.png — Visual QA contact sheet (daylight + night).

STRICTLY ZERO #000000 pure black pixels anywhere!
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "meadow_wonders_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

OUT = hexc("1b1a2e")
MORTAR = hexc("18162a")
SHADOW_RGB = (14, 16, 34)

# ---- Palettes (ZERO #000000) ----
# Ancient slate-violet monolithic & belfry stone (`#26243a -> #444260 -> #6c6a8c -> #9e9cba` + catch-edge)
STONE = [
    hexc("1c1a2e"),  # 0 deep crevice
    hexc("26243a"),  # 1 slate-violet shadow
    hexc("35334d"),  # 2 dark ashlar
    hexc("444260"),  # 3 mid-shadow stone
    hexc("585676"),  # 4 mid stone
    hexc("6c6a8c"),  # 5 lit stone
    hexc("8583a4"),  # 6 bright facet
    hexc("9e9cba"),  # 7 sunlit bevel
    hexc("c8c6e2"),  # 8 crisp catch-edge
]

# Verdigris-bronze bell & copper spire roofing (`#24423e -> #38685e -> #5a9484` + aged gold `#8c6b32 -> #c9a252`)
VERDIGRIS = [hexc(c) for c in ("182e2e", "24423e", "2e554e", "38685e", "487e71", "5a9484", "7eb8a6", "aee0ce")]
GOLD_RIM = [hexc(c) for c in ("58411e", "8c6b32", "ad8640", "c9a252", "e6c46e", "fff0b0")]
SLATE_ROOF = [hexc(c) for c in ("1a2034", "26304a", "364462", "4a5c7c", "647898", "8aa0be")]

# Submerged stone & water ripples
SUB_STONE = [hexc(c) for c in ("132a36", "1a3c48", "24525e", "326c78")]
WATER_RING = [hexc("247284"), hexc("3cc0c6"), hexc("78f4e6"), hexc("e8fffb")]

# Meadow moss, ivy, heather & clover
MOSS = [hexc(c) for c in ("183430", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
HEATHER = [hexc("5e3884"), hexc("8e5cc2"), hexc("caa4f2")]
ASH = [hexc(c) for c in ("242234", "38364c", "504e66")]

# Mosaic inlays & unlit glow colors
MOSAIC_SILVER = [hexc("5a6884"), hexc("8898b6"), hexc("bccae2"), hexc("eef4ff")]
MOSAIC_VIO = [hexc("3e2b68"), hexc("64469c"), hexc("9468ee"), hexc("cbaaff")]
TEAL_DIM = hexc("2a8c94")
TEAL = hexc("3cc0c6")
TEAL_L = hexc("78f4e6")
TEAL_HOT = hexc("e8fffb")
GOLD_GLOW = hexc("ffd88a")
GOLD_HOT = hexc("fff8dc")
VIO_GLOW = hexc("9468ee")
VIO_HOT = hexc("cbaaff")


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


def shade_stone(x: int, y: int, lit: float, seed: int, catch_top: bool = False, catch_left: bool = False):
    grain = (fbm(x * 0.52, y * 0.52, seed) - 0.5) * 0.95
    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.58
    bevel = (0.75 if catch_top else 0.0) + (0.45 if catch_left else 0.0)
    pit = -1.2 if hsh(x, y, seed + 29) < 0.03 else 0.0
    return STONE[int(clamp(lit * 6.8 + grain + dith + bevel + pit, 0, len(STONE) - 1))]


def draw_ashlar_block(px, x0: int, y0: int, x1: int, y1: int, lit: float, seed: int):
    bias = (hsh(x0, y0, seed + 3) - 0.5) * 0.14
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if y == y1 or x == x1:
                put(px, x, y, MORTAR)
            else:
                put(px, x, y, shade_stone(x, y, lit + bias, seed, catch_top=(y == y0), catch_left=(x == x0)))


def drape_moss(px, x0: int, x1: int, y_top: int, thick: int, hang: int, seed: int):
    w, h = len(px[0]), len(px)
    for x in range(max(2, x0), min(w - 2, x1 + 1)):
        drop = int(hang * max(0.0, 0.62 * math.sin(x * 0.44 + seed) + 0.38 * hsh(x, y_top, seed + 5)))
        tj = -1 if hsh(x, 0, seed + 7) > 0.58 else 0
        for y in range(y_top + tj, y_top + thick + drop + 1):
            if not (2 <= y < h - 2):
                continue
            if y > y_top + 1 and px[y][x][3] == 0:
                continue
            u = (y - (y_top + tj)) / max(1.0, float(thick + drop))
            lit = (1.0 - u) * 0.72 + (0.20 if x < w // 2 else 0.04) + (fbm(x * 0.5, y * 0.5, seed + 11) - 0.5) * 0.4
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5
            put(px, x, y, MOSS[int(clamp(lit * 6.0 + dith, 0, len(MOSS) - 1))])
        fy = y_top + thick + drop + 1
        if 2 <= fy < h - 2 and px[fy][x] in STONE[2:]:
            px[fy][x] = STONE[max(0, STONE.index(px[fy][x]) - 2)]


def add_shadow_and_outline(body, cx: int, fy: int, rx: float, ry: float):
    w, h = len(body[0]), len(body)
    sh = blank(w, h)
    for y in range(max(0, int(fy - ry - 2)), min(h, int(fy + ry + 4))):
        for x in range(w):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - (fy + 1.0)) / ry) ** 2
            if d < 1.0:
                sh[y][x] = (*SHADOW_RGB, 114 if d < 0.48 else 58)
    framed = outline_pass(body, OUT)
    return [[framed[y][x] if framed[y][x][3] > 0 else sh[y][x] for x in range(w)] for y in range(h)]


# ==============================================================================
# 1. Bell Spire (`bell_spire.png` & `_glow.png`, 2x1 of 96x160, waterline anchor (48, 136))
# ==============================================================================
def build_bell_spire_variant(awakened: bool):
    W, H = 96, 160
    CX, WY = 48, 136  # Waterline anchor
    seed = 3401
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Submerged stone arch base & watery reflection (`y = 135..152`) disappearing into still turquoise lake water!
    for y in range(WY - 1, 152):
        depth_u = (y - (WY - 1)) / 16.0
        hw_sub = int(round((26.0 - depth_u * 8.0) * (1.0 + 0.08 * math.sin(y * 1.4))))
        for x in range(CX - hw_sub, CX + hw_sub + 1):
            # Central flooded archway gap even underwater (`abs(x - CX) < 9` fades quicker)
            if abs(x - CX) < 9 and y < WY + 7:
                continue
            if (y - WY) % 2 == 1 and depth_u > 0.45:
                continue  # Dithered watery dissolution
            col_s = SUB_STONE[int(clamp((1.0 - depth_u) * 3.4, 0, 3))]
            put(body, x, y, col_s)

    # 2) Lower Sunken Belfry Arcade Story (`y = 98..135`, `x = 22..74`): Flooded Stone Arch Columns emerging from lake!
    for y in range(98, WY):
        u = (y - 98) / float(WY - 98)
        hw = 23 + int(u * 3.5)
        course_r = (y - 98) % 6
        for x in range(CX - hw, CX + hw + 1):
            # Pointed Gothic water-arch opening (`cx = 48, apex at y = 105, half-width = 10` at waterline)
            dx_a = abs(x - CX) / 10.5
            dy_a = max(0.0, (124.0 - y) / 19.0)
            in_arch = (y >= 105 and dx_a + 0.55 * (dy_a ** 1.4) < 1.0)
            in_voussoir = (y >= 102 and not in_arch and dx_a + 0.55 * (max(0.0, (126.0 - y) / 21.0) ** 1.4) < 1.24)
            if in_arch:
                # Dark recessed inner flooded belfry piers visible behind front arch!
                if abs(x - CX) > 6.5:
                    put(body, x, y, WET_COL := SUB_STONE[2 if y < 126 else 1])
                continue
            if in_voussoir:
                put(body, x, y, MORTAR if (x + y) % 5 == 0 else STONE[6 if x < CX else 4])
                continue
            rel = (x - CX) / float(hw)
            is_j = (course_r == 5) or ((x + (4 if ((y - 98) // 6) % 2 else 0)) % 9 == 0)
            if is_j:
                put(body, x, y, MORTAR)
            else:
                # Wet mossy waterline band on lowest 6 px above water (`y >= 130`)
                if y >= 130 and fbm(x * 0.5, y * 0.5, seed + 5) > 0.42:
                    put(body, x, y, MOSS[2 if x < CX else 1])
                else:
                    lit = 0.62 - 0.28 * rel - 0.08 * u
                    put(body, x, y, shade_stone(x, y, lit, seed + 7, catch_top=(course_r == 0)))

    # Carved cornice ledge with gargoyle/waterspout shoulders between lower arcade & open bell chamber (`y = 94..98, x = 20..76`)
    draw_ashlar_block(body, 20, 94, 76, 98, 0.66, seed + 13)
    drape_moss(body, 21, 38, 94, 2, 4, seed + 15)
    drape_moss(body, 60, 75, 94, 2, 3, seed + 17)

    # 3) Open Arched Stone Belfry Chamber (`y = 48..93, x = 24..72`) housing the Heavy Verdigris-Bronze Bell!
    # First fill deep dark back arch-interior + oak bell yoke so the bronze bell silhouettes crisply!
    for y in range(52, 94):
        for x in range(32, 65):
            dx_b = abs(x - CX) / 15.5
            dy_b = max(0.0, (70.0 - y) / 18.0)
            if dx_b + 0.65 * (dy_b ** 1.5) < 1.0:
                put(body, x, y, STONE[0 if x >= CX - 4 else 1])

    # Heavy oak bell-yoke beam (`y = 56..59, x = 37..59`) + iron suspension straps
    for x in range(37, 60):
        put(body, x, 57, GOLD_RIM[1 if x > CX else 2])
        put(body, x, 58, OUT)
    put(body, CX, 59, GOLD_RIM[3])
    put(body, CX - 1, 59, GOLD_RIM[4])

    # Sculpted Verdigris-Bronze Ancient Bell (`y = 60..84`, flaring mouth `x = 36..60` at `y = 81..83`, clapper at `(48, 85)`)!
    for y in range(60, 84):
        u_b = (y - 60) / 23.0
        # Classic flared church/temple bell profile: rounded crown -> waist -> sweeping sound-bow flare!
        hw_bell = 5.2 + 3.2 * (u_b ** 0.7) + 4.8 * max(0.0, (u_b - 0.58) / 0.42) ** 1.85
        for x in range(int(round(CX - hw_bell)), int(round(CX + hw_bell)) + 1):
            rel_b = (x - CX) / max(1.0, hw_bell)
            nz = math.sqrt(max(0.05, 1.0 - min(0.98, rel_b * rel_b)))
            lit_b = -0.55 * rel_b - 0.25 * (u_b - 0.4) + 0.48 * nz
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.48
            # Aged gold sound-bow rim (`y = 80..83`) & upper inscription band (`y = 65..66`)!
            if y >= 80 or y == 65:
                col_bell = GOLD_RIM[int(clamp((lit_b + 0.35) * 4.8 + dith, 0, 5))]
            else:
                col_bell = VERDIGRIS[int(clamp((lit_b + 0.38) * 6.5 + dith, 0, 7))]
            put(body, x, y, col_bell)

    # Bronze bell clapper sphere peeking below the sound-bow at `(48, 84..86)`
    for dy in (0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if abs(dx) + dy <= 2:
                put(body, CX + dx, 84 + dy, GOLD_RIM[5 if dx <= 0 and dy <= 1 else 2])

    # Outer Carved Stone Belfry Piers, Side Buttresses & Pointed Gothic Archivolts (`y = 48..93, x = 23..73`)!
    for y in range(48, 94):
        hw_ch = 22 + (2 if y >= 84 else (1 if y <= 52 else 0))
        course_r = (y - 48) % 6
        for x in range(CX - hw_ch, CX + hw_ch + 1):
            dx_o = abs(x - CX) / 14.2
            dy_o = max(0.0, (70.0 - y) / 18.0)
            arch_val = dx_o + 0.65 * (dy_o ** 1.5)
            if y >= 53 and arch_val < 0.98:
                continue  # Open bell window!
            elif y >= 50 and arch_val < 1.24:
                # Pointed Gothic stone archivolt moulding framing the bell!
                put(body, x, y, MORTAR if (x + y) % 5 == 0 else STONE[7 if x < CX else 5])
            else:
                rel = (x - CX) / float(hw_ch)
                is_j = (course_r == 5) or ((x + 3) % 8 == 0)
                put(body, x, y, MORTAR if is_j else shade_stone(x, y, 0.64 - 0.30 * rel, seed + 23, catch_top=(course_r == 0)))

    # 4) Steep Weathered Slate-and-Verdigris-Copper Spire Roof (`y = 14..48`, `CX = 48`) + Crescent Finial (`y = 5..14`)!
    # Eaves cornice + triangular gablets at base of spire (`y = 44..48, x = 21..75`)
    for x in range(21, 76):
        put(body, x, 47, VERDIGRIS[6 if x < CX else 4])
        put(body, x, 48, STONE[2])
    for y in range(14, 47):
        t_s = (y - 14) / 33.0
        # Slight concave witch-hat / belfry spire flare near eaves!
        hw_sp = 1.2 + 21.5 * (t_s ** 1.12) + 3.5 * max(0.0, (t_s - 0.72) / 0.28) ** 1.7
        sh_row = (y - 14) % 4
        copper_band = (sh_row == 0) or (t_s < 0.25) or (0.52 <= t_s <= 0.60)
        for x in range(int(round(CX - hw_sp)), int(round(CX + hw_sp)) + 1):
            rel_s = (x - CX) / max(1.0, hw_sp)
            # 3 octagonal spire facets: bright sunlit left, mid center, cool dark right
            facet_l = 0.78 if rel_s < -0.35 else (0.52 if rel_s < 0.35 else 0.26)
            if sh_row == 3:
                facet_l -= 0.16
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.45
            if copper_band or (hsh(x // 2, y // 3, seed + 31) > 0.62):
                col_r = VERDIGRIS[int(clamp(facet_l * 7.4 + dith, 0, 7))]
            else:
                col_r = SLATE_ROOF[int(clamp(facet_l * 5.8 + dith, 0, 5))]
            put(body, x, y, col_r)

    drape_moss(body, 25, 39, 45, 2, 3, seed + 35)
    drape_moss(body, 57, 70, 45, 2, 2, seed + 37)

    # Crescent Moon Finial atop the spire (`y = 4..14, cx = 48`)
    for y in range(9, 15):
        put(body, CX, y, GOLD_RIM[4 if y < 12 else 2])
    # Crescent horns curving upward (`y = 4..10, x = 44..52`)
    for dy in range(-4, 3):
        for dx in range(-4, 5):
            ro = math.hypot(dx, dy)
            ri = math.hypot(dx - 1.1, dy + 1.2)
            if ro <= 3.8 and ri >= 2.3:
                put(body, CX + dx, 8 + dy, GOLD_RIM[5 if dx <= 0 else 3])

    # 5) Waterline Ripples (`y = 132..149`) + Dormant vs Awakened Midnight Toll Glow!
    if not awakened:
        # Col 0 (Dormant): calm turquoise-blue water ripples around submerged piers + soft moonlight glint on bronze bell & finial
        for rx_w, ry_w, w_len in [(18, 136, 12), (66, 136, 12), (24, 141, 16), (56, 141, 16), (34, 146, 28)]:
            for dx in range(w_len):
                if (dx + ry_w) % 3 != 0:
                    put(body, rx_w + dx, ry_w, WATER_RING[1 if dx in (0, w_len - 1) else 2])
        glow.emit(body, CX - 3, 71, VERDIGRIS[6], TEAL_L, halo=1)
        glow.emit(body, CX - 2, 81, GOLD_RIM[5], GOLD_RIM[5], halo=1)
        glow.emit(body, CX - 2, 7, GOLD_RIM[5], GOLD_RIM[5], halo=1)
    else:
        # Col 1 (Awakened Midnight Toll): Radiant turquoise-gold resonance runes on archivolts & bell rim,
        # glowing bronze bell heart, awakened finial, and luminous concentric water rings!
        for ring_rx, ring_ry in [(31.0, 5.5), (41.0, 8.8)]:
            for deg in range(0, 360, 3):
                th = math.radians(deg)
                # Front & side arcs (`sin(th) >= -0.25` so rings wrap naturally around the sunken tower!)
                if math.sin(th) < -0.22:
                    continue
                wx = int(round(CX + math.cos(th) * ring_rx))
                wy = int(round(WY + 1.5 + math.sin(th) * ring_ry))
                if 3 <= wx < W - 3 and 3 <= wy < H - 3:
                    if deg % 12 != 0:
                        glow.emit(body, wx, wy, WATER_RING[2], TEAL_HOT if deg % 24 == 0 else TEAL_L, halo=1)

        # Glowing archivolt runes framing the belfry chamber
        rune_arch_pts = [
            (33, 82), (33, 74), (34, 66), (37, 58), (42, 52), (48, 50),
            (54, 52), (59, 58), (62, 66), (63, 74), (63, 82),
            (35, 118), (37, 110), (59, 110), (61, 118),
        ]
        for i_r, (rx_p, ry_p) in enumerate(rune_arch_pts):
            is_g = (i_r % 3 == 0)
            glow.emit(body, rx_p, ry_p, GOLD_GLOW if is_g else TEAL_L, GOLD_HOT if is_g else TEAL_HOT, halo=2 if i_r == 5 else 1)

        # Radiant awakened bell rim, inscription band, clapper heart & crescent finial!
        for bx_r in range(38, 59, 3):
            glow.emit(body, bx_r, 81, GOLD_GLOW, GOLD_HOT if abs(bx_r - CX) <= 4 else TEAL_L, halo=1)
        for bx_r in range(43, 54, 3):
            glow.emit(body, bx_r, 65, TEAL_L, TEAL_HOT, halo=1)
        glow.emit(body, CX, 85, GOLD_HOT, GOLD_HOT, halo=2)
        glow.emit(body, CX, 84, GOLD_GLOW, GOLD_HOT, halo=2)
        glow.emit(body, CX - 1, 73, TEAL_L, TEAL_HOT, halo=2)
        glow.emit(body, CX - 2, 7, GOLD_HOT, GOLD_HOT, halo=2)

    framed = outline_pass(body, OUT)
    return framed, glow.finish()


# ==============================================================================
# 2. Bell Stepping Stones (`bell_stepping_stone.png` & `_glow.png`, 3x1 of 32x32, center (16, 18))
# ==============================================================================
def build_bell_stepping_stones():
    FW, FH = 32, 32
    CX, CY = 16, 18
    frames = []
    glows = []

    # Col 0: Submerged faint dark-teal underwater stone silhouette (`y = 11..25`, no hard dark outline so it looks underwater!)
    sub = blank(FW, FH)
    sub_gl = GlowMap(FW, FH)
    for y in range(11, 26):
        for x in range(5, 27):
            d = ((x + 0.5 - CX) / 10.5) ** 2 + ((y + 0.5 - CY) / 6.8) ** 2
            if d <= 1.0:
                if d > 0.78 and (x + y) % 2 == 0:
                    continue
                col_u = SUB_STONE[2 if d < 0.42 else (1 if d < 0.75 else 0)]
                put(sub, x, y, (*col_u[:3], 185 if d < 0.65 else 115))
    # Tiny faint surface water ripple above submerged stone
    for dx in (-4, -3, 2, 3, 4):
        put(sub, CX + dx, CY - 3, (*WATER_RING[0][:3], 140))
    frames.append(sub)
    glows.append(sub_gl.finish())

    # Cols 1 & 2: Risen Mossy Carved Stepping Slabs (~22x14 px 3/4 octagonal slab) breaking the water surface!
    for var_idx in (1, 2):
        seed = 3600 + var_idx * 29
        body = blank(FW, FH)
        gl = GlowMap(FW, FH)

        # Slab top plateau (`cy = 16.5, rx = 10.8, ry = 5.8`) + wet 3/4 vertical stone thickness (`4 px` drop to `y = 25`)
        for y in range(10, 26):
            for x in range(4, 28):
                dx_top = (x + 0.5 - CX) / 10.8
                dy_top = (y + 0.5 - 16.5) / 5.8
                d_top = (abs(dx_top) ** 2.3 + abs(dy_top) ** 2.3) ** (1.0 / 2.3)

                dx_bot = (x + 0.5 - CX) / 10.8
                dy_bot = (y + 0.5 - 20.2) / 5.8
                d_bot = (abs(dx_bot) ** 2.3 + abs(dy_bot) ** 2.3) ** (1.0 / 2.3)

                if d_top <= 1.0:
                    lit = 0.66 - 0.24 * dx_top - 0.28 * dy_top
                    if d_top > 0.82 and (dx_top < 0.2 or dy_top < 0.1):
                        lit += 0.18
                    put(body, x, y, shade_stone(x, y, lit, seed))
                elif y > 16 and d_bot <= 1.0:
                    put(body, x, y, SUB_STONE[2 if x < CX else 1] if y >= 22 else STONE[2 if x < CX else 1])

        # Moss tuft on upper-left rim of slab
        drape_moss(body, 7, 13, 11, 2, 1, seed + 5)
        if var_idx == 2:
            drape_moss(body, 19, 24, 12, 2, 1, seed + 9)

        # Carved glowing rune in slab center: Variant 1 = Spiral Rune; Variant 2 = Concentric Bell-Wave Glyph!
        if var_idx == 1:
            spiral_pts = [(0, 0), (1, 0), (1, -1), (0, -2), (-1, -2), (-2, -1), (-3, 0), (-2, 1), (0, 2), (2, 2), (3, 1)]
            for i_p, (dx, dy) in enumerate(spiral_pts):
                gl.emit(body, CX + dx, 16 + dy, TEAL_L if i_p < 4 else TEAL, TEAL_HOT if i_p == 0 else TEAL_L, halo=1)
        else:
            # Bell-wave glyph
            gl.emit(body, CX, 16, GOLD_HOT, GOLD_HOT, halo=1)
            for dx, dy in [(-2, 0), (2, 0), (-1, -1), (0, -1), (1, -1), (-3, 1), (0, 2), (3, 1), (-4, 0), (4, 0)]:
                gl.emit(body, CX + dx, 16 + dy, TEAL_L, TEAL_HOT if dy == -1 else TEAL_L, halo=1)

        framed = outline_pass(body, OUT)
        # Wet turquoise water-foam rim hugging the emerged stone base (`y = 21..27`) + subtle glow glint!
        for deg in range(15, 165, 10):
            th = math.radians(deg)
            wx = int(round(CX + math.cos(th) * 11.8))
            wy = int(round(20.5 + math.sin(th) * 6.2))
            if 1 <= wx < FW - 1 and 1 <= wy < FH - 1:
                framed[wy][wx] = WATER_RING[3 if deg in (45, 95, 135) else 2]
                if deg in (45, 95, 135):
                    gl.emit(None, wx, wy, None, TEAL_L, halo=0)

        frames.append(framed)
        glows.append(gl.finish())

    return frames, glows


# ==============================================================================
# 3. Sleeping Guardians (`sleeping_guardian.png` & `_glow.png`, 3x1 of 80x128, feet (40, 116))
# ==============================================================================
def build_sleeping_guardian(variant: int):
    W, H = 80, 128
    FX, FY = 40, 116
    seed = 3801 + variant * 43
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Heavy Two-Tier Stepped Ashlar Monolith Plinth (`y = 98..116, x = 14..66`, 52 px wide!)
    draw_ashlar_block(body, 14, 107, 66, 116, 0.56, seed + 1)
    draw_ashlar_block(body, 18, 99, 62, 106, 0.62, seed + 2)
    # Staggered vertical block joints on plinth
    for jx in (27, 42, 55):
        for y in range(108, 116):
            put(body, jx, y, MORTAR)
    for jx in (31, 48):
        for y in range(100, 106):
            put(body, jx, y, MORTAR)

    if variant == 0:
        # ---- Col 0: Towering Robed Sleeping Guardian (~98 px tall: y = 18..116) leaning peacefully on grounded stone shield/staff!
        # Robed monolithic body (`y = 42..98`): broad ancient mantle shoulders (`y ~ 45..58, hw = 21`) tapering slightly to `hw = 18` at plinth
        for y in range(42, 99):
            u = (y - 42) / 56.0
            shoulder_bulge = 4.2 * math.sin(min(1.0, u * 2.2) * math.pi) if u < 0.45 else 0.0
            hw = 16.5 + shoulder_bulge + 1.8 * u
            for x in range(int(round(FX - hw)), int(round(FX + hw)) + 1):
                rel = (x - FX) / max(1.0, hw)
                # Vertical fluted stone robe folds + 3D cylindrical volume!
                fold = math.sin((x - FX) * 0.55) * (0.14 if u > 0.28 else 0.05)
                lit = 0.58 - 0.32 * rel + fold - 0.06 * u
                if abs(y - 68) == 0 and abs(rel) > 0.35:
                    put(body, x, y, MORTAR)  # Monolith drum joint
                else:
                    put(body, x, y, shade_stone(x, y, lit, seed + 5, catch_top=(y == 42 and abs(rel) < 0.6)))

        # Grounded Stone Tower-Shield / Staff held before the guardian (`x = 31..49, y = 60..98`) + Clasped Stone Hands (`y = 56..63`)!
        for y in range(60, 99):
            u_s = (y - 60) / 38.0
            hw_sh = 8.5 * (1.0 - 0.35 * (u_s ** 1.8))
            for x in range(int(round(FX - hw_sh)), int(round(FX + hw_sh)) + 1):
                rel_s = (x - FX) / max(1.0, hw_sh)
                edge = abs(abs(x - FX) - hw_sh) < 1.3 or y == 60
                lit_s = (0.76 if rel_s < 0 else 0.42) if edge else (0.50 - 0.25 * rel_s)
                put(body, x, y, shade_stone(x, y, lit_s, seed + 9, catch_top=(y == 60)))
        # Sculpted clasped stone gauntlets/hands resting peacefully atop the shield (`y = 55..61, x = 33..47`)
        for y in range(55, 62):
            for x in range(34, 47):
                if (x - FX) ** 2 / 42.0 + (y - 58.0) ** 2 / 12.0 <= 1.0:
                    put(body, x, y, STONE[7 if y <= 56 and x < FX + 2 else (5 if x < FX else 3)])

        # Serene Bowed Crowned Stone Head (`y = 18..45, x = 29..51`)!
        # Crown peaks (`y = 18..25`) + peaceful brow & closed eyes (`y = 31..32`) + long stone beard (`y = 36..49`)
        for y in range(18, 48):
            if y < 25:
                # 5-point ancient stone crown!
                t_c = (y - 18) / 7.0
                hw_h = 9.5 + 1.0 * (1.0 - t_c)
                spire_gap = (y < 22 and int(abs(x_test := 0)) >= 0)  # handled per x
            else:
                hw_h = 9.5 * (1.0 - 0.38 * max(0.0, (y - 35) / 13.0) ** 1.4)
            for x in range(int(round(FX - hw_h)), int(round(FX + hw_h)) + 1):
                if y < 22 and (abs(x - FX) in (3, 4, 8)):
                    continue  # Crown crenellation notches!
                rel_h = (x - FX) / max(1.0, hw_h)
                lit_h = 0.66 - 0.32 * rel_h + (0.12 if y in (24, 25) else 0.0)
                put(body, x, y, shade_stone(x, y, lit_h, seed + 13, catch_top=(y <= 22)))

        # Serene closed stone eyelids (`y = 31`), nose bridge (`x = 40, y = 30..35`), & fluted beard
        for ex in (35, 36, 37, 43, 44, 45):
            put(body, ex, 31, MORTAR)
            put(body, ex, 32, STONE[6 if ex < FX else 4])
        for ny in range(29, 36):
            put(body, FX - 1, ny, STONE[7])
            put(body, FX + 1, ny, STONE[2])

        # Lush moss cape across head crown, shoulders & plinth!
        drape_moss(body, 31, 44, 19, 2, 4, seed + 17)
        drape_moss(body, 20, 34, 43, 3, 6, seed + 19)
        drape_moss(body, 47, 60, 44, 2, 5, seed + 21)
        drape_moss(body, 15, 32, 107, 2, 3, seed + 23)

        # Serene Turquoise-Violet Rune Seams on crown, chest, shield spine & plinth (`sleeping_guardian_glow.png`)
        glow.emit(body, FX, 23, TEAL_L, TEAL_HOT, halo=2)
        for ry_s in range(65, 92, 4):
            glow.emit(body, FX, ry_s, TEAL if ry_s % 8 != 1 else MOSAIC_VIO[2], TEAL_L if ry_s % 8 != 1 else VIO_HOT, halo=1)
        for rx_c, ry_c in [(31, 51), (34, 52), (49, 51), (46, 52), (28, 103), (52, 103)]:
            glow.emit(body, rx_c, ry_c, MOSAIC_VIO[2], VIO_GLOW, halo=1)

    elif variant == 1:
        # ---- Col 1: Seated/Kneeling Monolithic Sentinel (~94 px tall: y = 22..116) with Folded Stone Wings/Cloak & Closed Eyes!
        # Sweeping arched Gothic-tipped stone wings framing the back & sides (`y = 21..98, x = 14..66`)
        for y in range(21, 99):
            u = (y - 21) / 77.0
            hw_w = 24.5 * math.sin(min(1.0, (u + 0.08) * 1.02) * math.pi * 0.86) + 3.0
            for x in range(int(round(FX - hw_w)), int(round(FX + hw_w)) + 1):
                dx_c = abs(x - FX)
                # Twin high-peaked angel/sentinel wing arches at `dx_c = 15..16` (`y_peak = 21`), dipping behind head (`dx_c < 9`)!
                wing_top_y = 21.0 + 0.24 * ((dx_c - 15.5) ** 2)
                if dx_c < 9.5 and y < 34:
                    continue
                if y < wing_top_y:
                    continue
                rel = (x - FX) / max(1.0, hw_w)
                # Tiered carved stone primary/secondary wing feathers!
                feather_col = int((dx_c - 6.0) / 3.8)
                in_groove = (dx_c > 8.5) and ((int(dx_c * 1.2 + y * 0.22) % 5 == 0) or (y - int(wing_top_y)) in (14, 28, 43))
                if in_groove:
                    lit = 0.20 - 0.08 * rel
                else:
                    lit = 0.68 - 0.34 * rel - 0.05 * u + (0.10 if (feather_col % 2 == 0 and x < FX) else 0.0)
                put(body, x, y, shade_stone(x, y, lit, seed + 31, catch_top=(y <= wing_top_y + 1.4)))

        # Robed sentinel torso & kneeling skirt nested between the wings (`y = 44..98, x = 28..52`)
        for y in range(44, 99):
            u_t = (y - 44) / 54.0
            hw_t = 10.5 + 3.2 * u_t
            for x in range(int(round(FX - hw_t)), int(round(FX + hw_t)) + 1):
                rel_t = (x - FX) / max(1.0, hw_t)
                fold = math.sin((x - FX) * 0.65) * 0.10
                if abs(x - FX) >= hw_t - 1.1:
                    put(body, x, y, MORTAR)  # Deep shadow seam separating inner robe from folded wings!
                else:
                    put(body, x, y, shade_stone(x, y, 0.58 - 0.28 * rel_t + fold, seed + 32))

        # Serene Bowed Sentinel Head nestled between the high wing arches (`y = 24..46, x = 31..49`)
        for y in range(24, 47):
            u_h = (y - 24) / 22.0
            hw_h = 8.8 * math.sin(min(1.0, (u_h + 0.16) * 0.92) * math.pi)
            for x in range(int(round(FX - hw_h)), int(round(FX + hw_h)) + 1):
                rel_h = (x - FX) / max(1.0, hw_h)
                if abs(x - FX) >= hw_h - 0.9 and y > 28:
                    put(body, x, y, STONE[1])
                else:
                    put(body, x, y, shade_stone(x, y, 0.70 - 0.30 * rel_h, seed + 33, catch_top=(y <= 26)))
        # Sculpted circlet brow band, nose bridge & serene closed eyelids
        for x in range(33, 48):
            put(body, x, 30, STONE[7 if x < FX else 5])
        for ex in (35, 36, 37, 43, 44, 45):
            put(body, ex, 35, MORTAR)
            put(body, ex, 36, STONE[6 if ex < FX else 4])
        for ny in range(32, 39):
            put(body, FX - 1, ny, STONE[7])
            put(body, FX + 1, ny, STONE[2])

        # Distinct Sculpted Crossed Stone Forearms & Hands over the chest (`y = 51..66, x = 28..52`)!
        for y in range(50, 67):
            for x in range(28, 53):
                d1 = (y - 58.0) - (x - FX) * 0.42
                d2 = (y - 58.0) + (x - FX) * 0.42
                if abs(d1) <= 3.3:
                    # Right-over-left stone forearm
                    edge_top = d1 < -1.9
                    edge_bot = d1 > 2.2
                    put(body, x, y, MORTAR if edge_bot else (STONE[7] if edge_top and x < FX + 4 else shade_stone(x, y, 0.68 - 0.22 * ((x - FX) / 12.0), seed + 35)))
                elif abs(d2) <= 3.3:
                    edge_top = d2 < -1.9
                    edge_bot = d2 > 2.2
                    put(body, x, y, MORTAR if edge_bot else (STONE[6] if edge_top else shade_stone(x, y, 0.56 - 0.22 * ((x - FX) / 12.0), seed + 36)))

        # Creeping ivy, purple heather blossoms & moss cushions on wing shoulder and plinth!
        drape_moss(body, 22, 30, 31, 3, 5, seed + 37)
        drape_moss(body, 35, 44, 24, 2, 3, seed + 39)
        drape_moss(body, 48, 61, 99, 2, 4, seed + 41)
        for k in range(24):
            ix = 52 + int(round(2.5 * math.sin(k * 0.45)))
            iy = 114 - k
            put(body, ix, iy, MOSS[4 if k % 2 == 0 else 2])
            if k % 5 == 0:
                put(body, ix + 1, iy, HEATHER[2])
                put(body, ix + 2, iy, HEATHER[1])

        # Glowing brow circlet, crossed-arm runes & wing-seam glyphs!
        glow.emit(body, FX, 30, TEAL_L, TEAL_HOT, halo=2)
        for gx, gy, is_v in [(FX - 6, 55, False), (FX, 58, True), (FX + 6, 55, False), (FX, 72, False), (FX, 80, True), (FX, 88, False), (25, 36, True), (55, 36, True), (32, 103, True), (48, 103, True)]:
            glow.emit(body, gx, gy, MOSAIC_VIO[2] if is_v else TEAL, VIO_HOT if is_v else TEAL_L, halo=1)

    else:
        # ---- Col 2: 7th Broken/Headless Guardian (~72 px tall: y = 44..116), fractured cleanly across neck/collar + mossy rubble at feet!
        for y in range(44, 99):
            u = (y - 44) / 54.0
            shoulder_bulge = 4.2 * math.sin(min(1.0, u * 2.2) * math.pi) if u < 0.45 else 0.0
            hw = 16.5 + shoulder_bulge + 1.8 * u
            for x in range(int(round(FX - hw)), int(round(FX + hw)) + 1):
                # Jagged fractured neck/collar break profile along top (`y = 44..50`)!
                frac_top = 44 + int(3.5 * abs(math.sin((x - FX) * 0.32 + 0.6))) + (2 if abs(x - FX) > 11 else 0)
                if y < frac_top:
                    continue
                rel = (x - FX) / max(1.0, hw)
                fold = math.sin((x - FX) * 0.55) * 0.13
                lit = 0.56 - 0.32 * rel + fold - 0.06 * u
                if y <= frac_top + 1:
                    # Exposed pale fractured stone plane across broken neck socket!
                    put(body, x, y, STONE[7 if abs(x - FX) > 4 and x < FX else (1 if abs(x - FX) <= 4 else 5)])
                elif y == 70 and abs(rel) > 0.32:
                    put(body, x, y, MORTAR)
                else:
                    put(body, x, y, shade_stone(x, y, lit, seed + 51))

        # Grounded stone shield/staff (top chipped slightly below broken collar)
        for y in range(60, 99):
            u_s = (y - 60) / 38.0
            hw_sh = 8.2 * (1.0 - 0.35 * (u_s ** 1.8))
            for x in range(int(round(FX - hw_sh)), int(round(FX + hw_sh)) + 1):
                rel_s = (x - FX) / max(1.0, hw_sh)
                edge = abs(abs(x - FX) - hw_sh) < 1.3 or y == 60
                put(body, x, y, shade_stone(x, y, (0.74 if rel_s < 0 else 0.40) if edge else (0.48 - 0.24 * rel_s), seed + 55))
        for y in range(56, 62):
            for x in range(34, 47):
                if (x - FX) ** 2 / 42.0 + (y - 58.5) ** 2 / 11.0 <= 1.0:
                    put(body, x, y, STONE[6 if x < FX else 3])

        # Crumbled mossy stone rubble chunks scattered around the plinth base (`y = 111..118`)!
        for rx_c, ry_c, rrx, rry in [(15, 114, 4.8, 2.7), (24, 116, 4.0, 2.3), (57, 115, 5.2, 2.8), (66, 114, 4.2, 2.4)]:
            for yy in range(int(ry_c - rry - 1), int(ry_c + rry + 2)):
                for xx in range(int(rx_c - rrx - 1), int(rx_c + rrx + 2)):
                    if ((xx - rx_c) / rrx) ** 2 + ((yy - ry_c) / rry) ** 2 <= 1.0:
                        put(body, xx, yy, shade_stone(xx, yy, 0.62 if xx < rx_c else 0.34, seed + rx_c))

        drape_moss(body, 21, 34, 46, 3, 5, seed + 57)
        drape_moss(body, 46, 58, 47, 2, 4, seed + 59)
        drape_moss(body, 14, 30, 107, 2, 3, seed + 61)

        # Interrupted rune circuit on broken neck socket & chest!
        glow.emit(body, FX, 48, MOSAIC_VIO[2], VIO_HOT, halo=1)
        for ry_s in range(66, 91, 5):
            glow.emit(body, FX, ry_s, TEAL, TEAL_L, halo=1)

    # Base grass & heather tufts around all 3 guardian plinths
    for gx in range(13, 68, 9):
        for bdx, bdy, mi in [(-2, -2, 4), (-1, -3, 6), (0, -1, 2), (1, -3, 5), (2, -1, 3)]:
            put(body, gx + bdx, FY + bdy, MOSS[mi])
        if gx in (22, 58):
            put(body, gx, FY - 4, HEATHER[2])
            put(body, gx + 1, FY - 3, HEATHER[1])

    out = add_shadow_and_outline(body, FX, FY, rx=31.0, ry=5.5)
    return out, glow.finish()


# ==============================================================================
# 4. Guardian Brazier & Fallen Headstone (`guardian_brazier.png` & `_glow.png`, 3x1 of 40x48, feet (20, 40))
# ==============================================================================
def build_guardian_brazier_col(col: int):
    W, H = 40, 48
    FX, FY = 20, 40
    seed = 4101 + col * 31
    body = blank(W, H)
    glow = GlowMap(W, H)

    if col in (0, 1):
        # ---- Col 0 (Unlit Stone Brazier Bowl) & Col 1 (Lit Turquoise-Gold Spirit-Flame Brazier)
        # Squat carved mossy stone pedestal + fluted offering bowl (`y = 17..40`, `24 px` tall, `24 px` wide bowl!)
        # Base plinth (`y = 35..40, x = 10..30`)
        draw_ashlar_block(body, 10, 35, 30, 40, 0.56, seed + 1)
        # Short carved waist stem (`y = 28..34, x = 14..26`)
        for y in range(28, 35):
            for x in range(14, 27):
                rel = (x - FX) / 6.5
                put(body, x, y, shade_stone(x, y, 0.58 - 0.34 * rel, seed + 3))
        # Wide carved stone offering bowl (`y = 18..28, x = 8..32`)
        for y in range(18, 29):
            u_b = (y - 18) / 10.0
            hw_b = 12.2 * math.sqrt(max(0.15, 1.0 - 0.55 * (u_b ** 1.6)))
            for x in range(int(round(FX - hw_b)), int(round(FX + hw_b)) + 1):
                rel = (x - FX) / max(1.0, hw_b)
                if y <= 20 and abs(rel) < 0.76:
                    # Bowl interior: cold grey ash (Col 0) vs glowing spirit-embers (Col 1)
                    put(body, x, y, ASH[2 if x < FX else 0] if col == 0 else TEAL_DIM)
                else:
                    flute = ((x - FX) % 4 == 0 and 22 <= y <= 26)
                    lit = 0.24 if flute else (0.66 - 0.34 * rel + (0.16 if y == 18 else 0.0))
                    put(body, x, y, shade_stone(x, y, lit, seed + 5, catch_top=(y == 18)))

        drape_moss(body, 9, 16, 19, 2, 2, seed + 9)
        drape_moss(body, 11, 20, 35, 2, 2, seed + 11)

        if col == 0:
            # Col 0: Faint dormant rune dot on pedestal front
            glow.emit(body, FX, 31, TEAL_DIM, TEAL, halo=1)
        else:
            # Col 1: Crisp multi-tongued Turquoise-Gold Spirit Flame (`y = 5..20`) + awakened pedestal rune!
            glow.emit(body, FX, 31, TEAL_L, TEAL_HOT, halo=1)
            for y in range(5, 21):
                u_f = (20 - y) / 15.0  # 0 at bowl base -> 1 at flame tip
                sway = 1.1 * math.sin(u_f * 4.5)
                hw_f = 7.2 * ((1.0 - u_f) ** 0.72) * (0.85 + 0.25 * math.sin(u_f * 6.0))
                # Twin secondary side tongues near mid-height
                for x in range(int(round(FX + sway - hw_f - 1)), int(round(FX + sway + hw_f + 2))):
                    dist = abs(x - (FX + sway)) / max(0.7, hw_f)
                    if dist > 1.0:
                        continue
                    # Core = white-gold `#fff8dc -> #ffd88a`; mid = radiant `#78f4e6`; outer = `#2a8c94`!
                    if dist < 0.36 and u_f < 0.68:
                        c_b = GOLD_HOT
                    elif dist < 0.62 and u_f < 0.82:
                        c_b = GOLD_GLOW
                    elif dist < 0.86:
                        c_b = TEAL_L
                    else:
                        c_b = TEAL_DIM
                    glow.emit(body, x, y, c_b, GOLD_HOT if c_b == GOLD_HOT else (GOLD_GLOW if c_b == GOLD_GLOW else TEAL_L), halo=1 if (x == FX and y in (10, 15, 18)) else 0)

    else:
        # ---- Col 2: Fallen Guardian Headstone (~26x22 px: x = 7..33, y = 19..40) resting tilted in meadow grass & clover!
        # Matches the broken 7th Guardian's crowned stone head, tilted ~22 degrees on its side in lush sod!
        ca, sa = math.cos(-0.36), math.sin(-0.36)
        cx_h, cy_h = 20.5, 29.5
        for y in range(17, 41):
            for x in range(6, 35):
                dx0, dy0 = x - cx_h, y - cy_h
                lx = dx0 * ca - dy0 * sa
                ly = dx0 * sa + dy0 * ca
                # Headstone local bounds: `lx in [-10.5..10.5]`, `ly in [-11.0 (crown) .. +10.0 (fractured neck)]`
                if not (-10.5 <= lx <= 10.5 and -11.0 <= ly <= 10.0):
                    continue
                # Crown crenellation notches at top (`ly < -7.5`)
                if ly < -7.8 and int(abs(lx)) in (3, 4, 8):
                    continue
                # Tapered cheeks/beard toward neck (`ly > 3`)
                max_lx = 10.2 if ly < 2.0 else 10.2 * (1.0 - 0.25 * ((ly - 2.0) / 8.0))
                if abs(lx) > max_lx:
                    continue
                lit = 0.66 - 0.28 * (dx0 / 11.0) - 0.26 * (dy0 / 11.0)
                # Serene closed stone eyes & nose relief in tilted local coordinates!
                if abs(ly + 1.5) < 0.7 and (2.2 <= abs(lx) <= 5.8):
                    col_s = MORTAR
                elif abs(lx) < 1.1 and -3.0 <= ly <= 3.0:
                    col_s = STONE[7]
                else:
                    col_s = shade_stone(x, y, lit, seed + 17, catch_top=(dy0 < -7.0))
                put(body, x, y, col_s)

        # Moss blanket over the upper brow/crown + pulsing turquoise rune on the fallen headstone's brow!
        drape_moss(body, 11, 24, 19, 2, 3, seed + 21)
        glow.emit(body, 18, 25, TEAL_L, TEAL_HOT, halo=2)
        glow.emit(body, 19, 25, TEAL, TEAL_L, halo=1)

    # Lush meadow grass & clover around base of all 3 frames (`y = 37..41`)
    for gx in (9, 15, 24, 30):
        for bdx, bdy, mi in [(-1, -2, 5), (0, -3, 6), (0, -1, 2), (1, -2, 4), (2, -1, 3)]:
            put(body, gx + bdx, FY + bdy, MOSS[mi])
    if col == 2:
        # Extra tall grass & pink/lilac clover half-burying the fallen headstone!
        for gx, gy in [(12, 39), (18, 40), (26, 39)]:
            put(body, gx, gy - 3, MOSS[5])
            put(body, gx + 1, gy - 4, HEATHER[2])

    out = add_shadow_and_outline(body, FX, FY, rx=15.5, ry=3.8)
    return out, glow.finish()


# ==============================================================================
# 5. Amphitheater Podium (`amphitheater_podium.png` & `_glow.png`, 128x96, anchor (64, 52))
# ==============================================================================
def build_amphitheater_podium():
    W, H = 128, 96
    CX, CY = 64, 46     # Center of top mosaic stage ellipse (so with 10px front rim, ground anchor (64, 52) sits right in the heart of the stage!)
    RX, RY = 52.0, 30.0 # ~104 px wide + steps = ~112 px total width, ~60 px top ellipse + 10 px rim = ~70 px total height (`y = 13..85`)
    RIM_DROP = 9
    seed = 4401
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) 4 Small Carved Mossy Stone Steps at N (`(64, 14)`), S (`(64, 82)`), W (`(9, 48)`), E (`(119, 48)`)!
    # Draw N, W, E steps before main drum; draw S front steps integrated/after!
    # West step (`x = 5..15, y = 40..56`) & East step (`x = 113..123, y = 40..56`)
    for sx0, sx1, is_left in [(5, 16, True), (112, 123, False)]:
        for y in range(40, 58):
            for x in range(sx0, sx1 + 1):
                if y >= 53:
                    put(body, x, y, STONE[2 if is_left else 1])
                elif y == 40 or (is_left and x == sx0):
                    put(body, x, y, STONE[7])
                else:
                    put(body, x, y, shade_stone(x, y, 0.58 if is_left else 0.42, seed + sx0))
    # North step (`x = 52..76, y = 12..19`)
    draw_ashlar_block(body, 52, 12, 76, 18, 0.66, seed + 11)

    # 2) Raised 10 px 3/4 Carved Octagonal/Circular Stone Stage Drum (`y` from top ellipse down `+RIM_DROP`)
    for y in range(int(CY - RY), int(CY + RY + RIM_DROP + 2)):
        for x in range(int(CX - RX - 1), int(CX + RX + 2)):
            dx = (x + 0.5 - CX) / RX
            dy_top = (y + 0.5 - CY) / RY
            dy_bot = (y + 0.5 - (CY + RIM_DROP)) / RY
            # Subtle 12-sided polygonal/circular temple-stage facets
            ang_b = math.atan2(dy_bot, dx)
            poly_b = 1.0 - 0.025 * math.cos(ang_b * 12.0)
            if y > CY and (dx * dx + dy_top * dy_top) > (poly_b ** 2) and (dx * dx + dy_bot * dy_bot) <= (poly_b ** 2):
                # Vertical front/side ashlar kerb wall (`RIM_DROP` = 9 px tall)!
                joint = (int((ang_b + math.pi) * 9.5) % 2 == 0 and abs(((ang_b + math.pi) * 9.5) % 1.0) < 0.14) or (y == int(CY + RY + RIM_DROP - 4))
                if joint:
                    put(body, x, y, MORTAR)
                else:
                    lit_w = 0.54 - 0.34 * dx - 0.10 * ((y - CY) / float(RIM_DROP))
                    put(body, x, y, shade_stone(x, y, lit_w, seed + 21))

    # 3) Grand Concentric Moonflower-and-Chord Mosaic Floor (`dx^2 + dy^2 <= 1.0` around `(CX, CY)`)!
    for y in range(int(CY - RY - 1), int(CY + RY + 2)):
        for x in range(int(CX - RX - 1), int(CX + RX + 2)):
            dx = (x + 0.5 - CX) / RX
            dy = (y + 0.5 - CY) / RY
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            poly = 1.0 - 0.022 * math.cos(ang * 12.0)
            if r > poly:
                continue

            # Outer carved stone kerb border (`0.88 <= r <= poly`) with radial block joints & sunlit bevel
            if r >= 0.87 * poly:
                spoke_j = abs(((ang + math.pi) * 12.0 / math.pi) % 1.0) < 0.08
                if spoke_j or abs(r - 0.87 * poly) < 0.025:
                    put(body, x, y, MORTAR)
                else:
                    lit_k = 0.68 - 0.20 * dx - 0.22 * dy
                    put(body, x, y, shade_stone(x, y, lit_k, seed + 31, catch_top=(r > 0.94 * poly and dy < 0)))
                continue

            # Inside Mosaic Stage (`r < 0.87`):
            # - Outer Harmonic Ring (`0.72 <= r <= 0.77`): glowing turquoise-silver inlay!
            # - 8-Petal Moonflower Rosette (`r = 0.22 + 0.36 * |cos(4 * ang)|`) + secondary 8-petal violet interlace (`|sin(4 * ang)|`)!
            # - 8 Musical / Harmonic Chord Lines connecting cardinal & diagonal points (`cos(4*ang)` / star octagram)!
            # - Central Moon-Pearl Medallion (`r <= 0.16`)!
            petal_main = 0.20 + 0.38 * abs(math.cos(4.0 * ang))
            petal_sec = 0.18 + 0.30 * abs(math.sin(4.0 * ang))
            on_outer_ring = 0.73 <= r <= 0.77
            on_inner_ring = 0.40 <= r <= 0.435
            on_center_ring = 0.13 <= r <= 0.165
            on_main_petal = abs(r - petal_main) < 0.042 and r > 0.16
            on_sec_petal = abs(r - petal_sec) < 0.038 and r > 0.16
            # Harmonic chord lines (inscribed square/octagram chords at `|dx/0.74| + |dy/0.74| == 0.74`)
            chord_a = abs((abs(dx) + abs(dy)) - 0.74) < 0.028 and r < 0.75
            chord_b = (abs(dx) < 0.022 or abs(dy) < 0.035) and 0.16 < r < 0.74

            if r < 0.13:
                # Radiant central moonflower heart
                col_m = MOSAIC_SILVER[3 if (dx < 0 and dy < 0) else 2]
                put(body, x, y, col_m)
                if r < 0.07:
                    glow.emit(body, x, y, MOSAIC_SILVER[3], TEAL_HOT, halo=2)
            elif on_outer_ring or on_center_ring:
                put(body, x, y, MOSAIC_SILVER[2 if dx < 0.2 else 1])
                if (x + y) % 2 == 0:
                    glow.emit(body, x, y, TEAL, TEAL_L, halo=1)
            elif on_main_petal:
                put(body, x, y, MOSAIC_SILVER[3 if dy < 0 else 2])
                if (x + y) % 2 == 0:
                    glow.emit(body, x, y, TEAL_L, TEAL_HOT if r > 0.50 else TEAL_L, halo=1)
            elif on_sec_petal or on_inner_ring:
                put(body, x, y, MOSAIC_VIO[2 if dy < 0 else 1])
                if (x + y) % 2 == 0:
                    glow.emit(body, x, y, MOSAIC_VIO[2], VIO_HOT if on_sec_petal else VIO_GLOW, halo=1)
            elif chord_a or chord_b:
                put(body, x, y, MOSAIC_SILVER[1])
                if (x + y) % 3 == 0:
                    glow.emit(body, x, y, TEAL_DIM, TEAL, halo=0)
            else:
                # Concentric fitted radial mosaic tesserae / flagstones in slate-violet!
                ring_j = abs((r * 9.0) % 1.0) < 0.09
                rad_j = abs(((ang + math.pi) * 16.0 / math.pi) % 1.0) < 0.07 and r > 0.22
                if ring_j or rad_j:
                    # Occasional tiny moss speck invading mosaic mortar joints near rim!
                    if r > 0.58 and fbm(x * 0.35, y * 0.35, seed + 41) > 0.56:
                        put(body, x, y, MOSS[4 if dy < 0 else 2])
                    else:
                        put(body, x, y, MORTAR)
                else:
                    lit_f = 0.54 - 0.16 * dx - 0.18 * dy + (0.06 if int(r * 9.0) % 2 == 0 else -0.04)
                    put(body, x, y, shade_stone(x, y, lit_f, seed + 47))

    # 4) South (Front) Mossy Two-Tread Stone Steps (`x = 50..78, y = 73..86`)!
    draw_ashlar_block(body, 51, 74, 77, 80, 0.64, seed + 51)
    draw_ashlar_block(body, 49, 80, 79, 86, 0.58, seed + 53)

    # Velvety meadow moss cushions & tiny moon-violet petals along kerb & steps
    drape_moss(body, 22, 38, 22, 2, 2, seed + 61)
    drape_moss(body, 88, 102, 65, 2, 3, seed + 63)
    drape_moss(body, 49, 58, 80, 2, 2, seed + 65)
    for gx, gy in [(16, 62), (32, 74), (47, 85), (81, 85), (98, 72), (112, 59)]:
        for bdx, bdy, mi in [(-1, -1, 5), (0, -2, 6), (1, -1, 3)]:
            put(body, gx + bdx, gy + bdy, MOSS[mi])
        put(body, gx, gy - 3, HEATHER[2])

    out = add_shadow_and_outline(body, CX, CY + 6, rx=58.0, ry=35.0)
    return out, glow.finish()


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/meadow_wonders_sheet.png`)
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
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def pack_row(frames, fw: int, fh: int):
    out = blank(fw * len(frames), fh)
    for col, f in enumerate(frames):
        for y in range(fh):
            out[y][col * fw:(col + 1) * fw] = f[y]
    return out


def render_qa_sheet(spires, step_frames, step_glows, guardians, braziers, podium_px, podium_gl):
    cw, ch = 620, 440
    canvas = blank(cw, ch)
    half = 220

    for y in range(ch):
        night = y >= half
        ly = y % half
        for x in range(cw):
            # Lake Glockenteich water basin on left (`x < 212`) + lush meadow on right (`x >= 212`)
            in_lake = x < 210
            n = noise(x // 4, y // 3, 173)
            if in_lake:
                if not night:
                    canvas[y][x] = (34, 96, 120, 255) if n < 120 else ((44, 116, 138, 255) if n < 210 else (76, 162, 176, 255))
                else:
                    canvas[y][x] = (16, 38, 62, 255) if n < 120 else ((22, 48, 74, 255) if n < 210 else (36, 78, 102, 255))
            else:
                if not night:
                    canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
                else:
                    canvas[y][x] = (20, 28, 48, 255) if n < 115 else ((25, 36, 58, 255) if n < 205 else (31, 44, 68, 255))

    for p_i in range(2):
        night = p_i == 1
        yo = 0 if not night else half

        # 1) 2 Bell Spires in Lake Glockenteich (`x = 6` Dormant, `x = 106` Awakened) + 3 Stepping Stones below!
        for i in range(2):
            sp_px, sp_gl = spires[i]
            ox, oy = 6 + i * 100, yo + 8
            alpha_over(canvas, tint_night_px(sp_px) if night else sp_px, ox, oy)
            if night or i == 1:
                add_glow_over(canvas, sp_gl, ox, oy)
        for i in range(3):
            ox, oy = 22 + i * 58, yo + 178
            alpha_over(canvas, tint_night_px(step_frames[i]) if night else step_frames[i], ox, oy)
            if night:
                add_glow_over(canvas, step_glows[i], ox, oy)

        # 2) 3 Sleeping Guardians (`x = 216, 298, 380`) + 3 Guardian Braziers/Headstone below them!
        for i in range(3):
            g_px, g_gl = guardians[i]
            ox, oy = 216 + i * 82, yo + 6
            alpha_over(canvas, tint_night_px(g_px) if night else g_px, ox, oy)
            if night:
                add_glow_over(canvas, g_gl, ox, oy)
        for i in range(3):
            b_px, b_gl = braziers[i]
            ox, oy = 234 + i * 74, yo + 152
            alpha_over(canvas, tint_night_px(b_px) if night else b_px, ox, oy)
            if night or i == 1:
                add_glow_over(canvas, b_gl, ox, oy)

        # 3) Amphitheater Podium on far right (`x = 472, yo + 64`)
        px_pos, py_pos = 474, yo + 62
        alpha_over(canvas, tint_night_px(podium_px) if night else podium_px, px_pos, py_pos)
        if night:
            add_glow_over(canvas, podium_gl, px_pos, py_pos)

    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"

    spires = [build_bell_spire_variant(False), build_bell_spire_variant(True)]
    sp_sheet = pack_row([s for s, _ in spires], 96, 160)
    sp_glow = pack_row([g for _, g in spires], 96, 160)

    step_frames, step_glows = build_bell_stepping_stones()
    st_sheet = pack_row(step_frames, 32, 32)
    st_glow = pack_row(step_glows, 32, 32)

    guardians = [build_sleeping_guardian(i) for i in range(3)]
    gd_sheet = pack_row([g for g, _ in guardians], 80, 128)
    gd_glow = pack_row([gl for _, gl in guardians], 80, 128)

    braziers = [build_guardian_brazier_col(i) for i in range(3)]
    br_sheet = pack_row([b for b, _ in braziers], 40, 48)
    br_glow = pack_row([gl for _, gl in braziers], 40, 48)

    podium_px, podium_gl = build_amphitheater_podium()

    outputs = [
        ("bell_spire.png", sp_sheet, 192, 160),
        ("bell_spire_glow.png", sp_glow, 192, 160),
        ("bell_stepping_stone.png", st_sheet, 96, 32),
        ("bell_stepping_stone_glow.png", st_glow, 96, 32),
        ("sleeping_guardian.png", gd_sheet, 240, 128),
        ("sleeping_guardian_glow.png", gd_glow, 240, 128),
        ("guardian_brazier.png", br_sheet, 120, 48),
        ("guardian_brazier_glow.png", br_glow, 120, 48),
        ("amphitheater_podium.png", podium_px, 128, 96),
        ("amphitheater_podium_glow.png", podium_gl, 128, 96),
    ]
    for name, px, ew, eh in outputs:
        assert (len(px[0]), len(px)) == (ew, eh), f"{name}: got {(len(px[0]), len(px))} != {(ew, eh)}"
        verify_no_black(name, px)
        write_png(props / name, ew, eh, px)

    render_qa_sheet(spires, step_frames, step_glows, guardians, braziers, podium_px, podium_gl)
    print("Wrote 10 Meadow Wonders PNGs and docs/img/meadow_wonders_sheet.png")


if __name__ == "__main__":
    main()
