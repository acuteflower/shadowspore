#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 4 — Alte Wassermühlen, Steinbogenbrücken & Fischerstege (stdlib + gen_art.py only):
  1. assets/props/old_watermill.png & _glow.png
     - Single frame 160x144, ground/foundation anchor at (80, 128):
       Charming weathered 3/4 RPG riverside watermill house: lower storey of mossy river-cobble stone masonry,
       upper storey of aged half-timbering with warm cream-slate plaster, steep mossy wooden shingle gable roof,
       arched oak mill door at bottom-center (x=70..90, y=96..126), mullioned attic window + side lantern,
       grain sacks & millstone leaning against the left wall, and sturdy timber axle housing on the right
       (x ~ 124, y ~ 98) where watermill_wheel.png mounts!
  2. assets/props/watermill_wheel.png
     - 6 cols x 1 row of 64x72 (384x72 total), wheel hub centered at (32, 36):
       6 seamless rotation frames (advancing 1/6 of a 6-spoke / 12-paddle spacing = 5 deg or 10 deg per frame ->
       here 8 spokes = 45 deg spacing -> 7.5 deg per frame across 6 frames = 45 deg = 100% seamless loop!) of a
       weathered dark-oak 3/4 perspective waterwheel (~52 px diameter, ~12 px 3/4 depth rim) with iron hub bands,
       mossy wooden paddles, and gleaming turquoise-white water droplets clinging to rising paddles.
  3. assets/props/watermill_jam.png
     - 2 cols x 1 row of 48x48 (96x48 total), center (24, 24):
       Col 0 (Jammed): Tangled bleached driftwood branch, river-weed & rusted iron chain wedged into spokes.
       Col 1 (Cleared): Tiny harmless mossy river stone beside the race.
  4. assets/props/broken_stone_bridge.png & _glow.png
     - 4 cols x 1 row of 96x96 (384x96 total), abutment center at (48, 56):
       Col 0 (West -> East): x=4..86, flagstone deck y=38..64 (26px wide), low mossy parapets, stone arch vault below,
                             jagged crumbled stones on right (x=76..88).
       Col 1 (East <- West): x=10..92, jagged crumbled edge on left (x=8..20), intact mossy parapet & wayfarer lantern on right.
       Col 2 (North -> South): x=28..68 walkable deck, y=6..86, broken stone arch at bottom (y=74..86).
       Col 3 (South -> North): x=28..68 walkable deck, y=10..90, broken arch edge at top (y=10..22).
  5. assets/props/fisher_pier.png & _glow.png
     - 4 cols x 1 row of 96x96 (384x96 total), center (48, 52):
       Weathered wooden fishing pier on mossy pilings with coiled rope, creel/bucket, and iron hook-lantern at tip:
       Col 0 East (x=8..86, deck y=40..62), Col 1 West (x=10..88, deck y=40..62),
       Col 2 South (x=34..62, deck y=8..86), Col 3 North (x=34..62, deck y=10..88).
  6. assets/props/reed_rowboat.png (no glow)
     - 2 cols x 1 row of 64x48 (128x48 total), center (32, 28):
       Col 0 (Unsearched): Weathered wooden rowboat nestled in green-gold lake reeds, mossy planks, oar, canvas satchel in bow.
       Col 1 (Searched): Same mossy rowboat in reeds with satchel taken (oar & planks remain).
  7. docs/img/water_pois_sheet.png — Visual QA contact sheet (daylight + night + mounted wheel preview).

STRICTLY ZERO #000000 pure black pixels anywhere!
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "water_pois_sheet.png"

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
# River-cobble & bridge stone masonry (`#2a283e -> #4a4866 -> #727090` extended to 8 crisp steps)
STONE = [
    hexc("1e1c30"),  # 0 deep crevice
    hexc("2a283e"),  # 1 cool river shadow
    hexc("393752"),  # 2 dark slate
    hexc("4a4866"),  # 3 mid-dark cobble
    hexc("5d5b7a"),  # 4 mid stone
    hexc("727090"),  # 5 lit cobble
    hexc("908eac"),  # 6 bright facet
    hexc("b8b5d2"),  # 7 sunlit catch-edge
]
WET_STONE = [hexc(c) for c in ("182034", "223048", "304560", "46607c")]

# Aged oak half-timbering, weathered planks, pilings & rowboat wood
TIMBER = [hexc(c) for c in ("23181b", "3b2820", "4c3328", "5c3f30", "704d3a", "825b44", "a67b5e", "caa080")]
PLANK = [hexc(c) for c in ("221926", "362836", "4e3b48", "6c535e", "8e7178", "b29496", "d2b8b4")]
DRIFTWOOD = [hexc(c) for c in ("302c3c", "4c4758", "6e6878", "96909e", "c0bac6")]

# Warm cream-slate half-timber plaster (`#6e6a82 -> #9894ab -> #c2bed4`)
PLASTER = [hexc(c) for c in ("4e4a62", "6e6a82", "848098", "9894ab", "aea9bf", "c2bed4", "dedbe9")]

# Steep wooden shingle gable roof (`#24283b -> #38405a -> #525e7a`)
ROOF = [hexc(c) for c in ("1a1d2e", "24283b", "2e344b", "38405a", "454f6b", "525e7a", "6e7c9a", "92a0be")]

# Meadow moss, river-weed & green-gold lake reeds
MOSS = [hexc(c) for c in ("183430", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
REED = [hexc(c) for c in ("244234", "3a6642", "5c8c4c", "8cb258", "bfd26c", "e6ea96")]
SACK = [hexc(c) for c in ("3a2a26", "5c4438", "84664e", "ad8c68", "d2b48a", "ecd4aa")]
ROPE = [hexc(c) for c in ("382b24", "5e4a36", "8e724e", "bc9e72", "dfd0a4")]
IRON = [hexc(c) for c in ("1d1b2d", "2e2b42", "46435e", "64607e", "8a86a6")]
RUST = [hexc(c) for c in ("3d1f22", "64322e", "8e4a3c", "b46a50")]

# Water droplets & unlit glow palettes
WATER_DROP = [hexc("247888"), hexc("3cc0c6"), hexc("78f4e6"), hexc("e8ffff")]
AMBER_D = hexc("c87828")
AMBER_M = hexc("ffb84d")
AMBER_H = hexc("fff0b0")
PIER_G1 = hexc("d47a2a")
PIER_G2 = hexc("ffc45c")
PIER_G3 = hexc("fff3c4")
BRIDGE_TEAL = hexc("3cc0c6")
BRIDGE_TEAL_L = hexc("78f4e6")
BRIDGE_GOLD = hexc("ffcb6b")


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


def draw_cobble(px, cx: float, cy: float, rx: float, ry: float, seed: int, wet: bool = False):
    pal = WET_STONE if wet else STONE
    tone = (hsh(int(cx * 3), int(cy * 3), seed) - 0.5) * 0.85
    for y in range(int(cy - ry - 2), int(cy + ry + 3)):
        for x in range(int(cx - rx - 2), int(cx + rx + 3)):
            dx = (x + 0.5 - cx) / max(1.0, rx)
            dy = (y + 0.5 - cy) / max(1.0, ry)
            d = (abs(dx) ** 2.3 + abs(dy) ** 2.3) ** (1.0 / 2.3)
            if d <= 1.04:
                if d > 0.85:
                    put(px, x, y, MORTAR)
                else:
                    lit = 0.54 - 0.34 * dx - 0.42 * dy + (0.25 if dy < -0.45 and dx < 0.3 else 0.0)
                    g = (fbm(x * 0.6, y * 0.6, seed + 5) - 0.5) * 0.75
                    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.52
                    idx = int(clamp(lit * (len(pal) - 0.6) + tone + g + dith, 0, len(pal) - 1))
                    put(px, x, y, pal[idx])


def drape_moss(px, x0: int, x1: int, y_top: int, thick: int, hang: int, seed: int):
    w, h = len(px[0]), len(px)
    for x in range(max(2, x0), min(w - 2, x1 + 1)):
        drop = int(hang * max(0.0, 0.6 * math.sin(x * 0.42 + seed) + 0.4 * hsh(x, y_top, seed + 3)))
        tj = -1 if hsh(x, 0, seed + 7) > 0.6 else 0
        for y in range(y_top + tj, y_top + thick + drop + 1):
            if not (2 <= y < h - 2):
                continue
            if y > y_top + 1 and px[y][x][3] == 0:
                continue
            u = (y - (y_top + tj)) / max(1.0, float(thick + drop))
            lit = (1.0 - u) * 0.74 + (0.18 if x < w // 2 else 0.04) + (fbm(x * 0.5, y * 0.5, seed + 9) - 0.5) * 0.4
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5
            put(px, x, y, MOSS[int(clamp(lit * 6.0 + dith, 0, len(MOSS) - 1))])


def draw_beam(px, x0: float, y0: float, x1: float, y1: float, half_w: float, seed: int):
    steps = max(1, int(math.hypot(x1 - x0, y1 - y0) * 2.2))
    ir = int(math.ceil(half_w + 0.5))
    for i in range(steps + 1):
        t = i / float(steps)
        cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        ix, iy = int(round(cx)), int(round(cy))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= (half_w + 0.2) ** 2:
                    lit = 0.55 - 0.35 * (dx / max(1.0, half_w)) - 0.38 * (dy / max(1.0, half_w))
                    g = (hsh(ix + dx, iy + dy, seed) - 0.5) * 0.5
                    put(px, ix + dx, iy + dy, TIMBER[int(clamp(lit * 6.5 + g, 0, 7))])


# ==============================================================================
# 1. Old Watermill (`old_watermill.png` & `_glow.png`, 160x144, anchor (80, 128))
# ==============================================================================
def build_old_watermill():
    W, H = 160, 144
    FX, FY = 80, 128
    seed = 2101
    rng = random.Random(seed)
    body = blank(W, H)
    glow = GlowMap(W, H)

    # ---- Architecture layout (3/4 RPG house with front gable on x = 36..118, plus right wheel-wall wing x = 118..126):
    # - Stone chimney at back-left (`x = 42..53, y = 10..42`)
    # - Lower storey (`y = 92..128, x = 36..124`): mossy river-cobble stone masonry, wet raceway plinth on right!
    # - Upper storey (`y = 58..92, x = 34..122`, slight jetty overhang!): cream-slate plaster + oak half-timbering
    # - Steep gable front & side shingle roof (`peak at x = 77, y = 14`, eaves at `y = 60, x = 28..128`)
    # - Arched oak mill door at bottom-center (`x = 70..90, y = 96..127`)
    # - Mullioned attic/gable window (`x = 69..85, y = 40..53`) + warm upper-left window (`x = 45..57, y = 68..80`) + door lantern (`x = 95, y = 99`)
    # - Grain sacks & carved round millstone leaning against left wall (`x = 18..46, y = 104..129`)
    # - Sturdy timber axle housing on right (`x ~ 118..131, y ~ 91..106`, axle journal centered at `(124, 98)`!)

    # 1) Stone Chimney on left roof slope (`x = 43..53, y = 10..44`)
    for cy_c in range(11, 44, 4):
        for cx_c in (45.5, 50.5):
            draw_cobble(body, cx_c + (1.0 if (cy_c // 4) % 2 else 0.0), cy_c, 3.2, 2.2, seed + cy_c)
    for x in range(42, 55):
        put(body, x, 10, STONE[7 if x < 49 else 5])
        put(body, x, 11, STONE[4 if x < 49 else 2])
    drape_moss(body, 43, 52, 10, 2, 2, seed + 2)

    # 2) Lower Storey (`y = 91..128, x = 36..124`): Fitted River-Cobble Masonry
    for y in range(91, FY + 1):
        for x in range(36, 125):
            put(body, x, y, MORTAR)
    for row_i, cy_c in enumerate(range(94, FY + 1, 6)):
        x_cur = 39.0 + (3.5 if row_i % 2 else 0.0)
        while x_cur < 123.0:
            cw_r = rng.uniform(4.6, 6.2)
            wet = (x_cur > 108 and cy_c > 112)
            draw_cobble(body, min(121.0, x_cur), cy_c, cw_r * 0.55, 3.1, seed + row_i * 19 + int(x_cur), wet=wet)
            x_cur += cw_r + 1.2
    # Right side wall shadow (`x = 115..124` recedes slightly in 3/4 depth)
    for y in range(91, FY + 1):
        for x in range(115, 125):
            c = body[y][x]
            if c in STONE[2:]:
                body[y][x] = STONE[max(1, STONE.index(c) - 2)]
    drape_moss(body, 36, 56, 122, 3, 2, seed + 5)
    drape_moss(body, 96, 123, 121, 3, 2, seed + 6)

    # 3) Upper Storey & Gable Peak (`y = 20..91`): Cream-Slate Plaster + Aged Oak Half-Timbering
    # Jetty floor beam (`y = 89..92, x = 33..124`) with carved corbel brackets
    for y in range(89, 93):
        for x in range(33, 125):
            lit = 0.72 if y == 89 else (0.18 if y == 92 else (0.55 if x < 112 else 0.30))
            put(body, x, y, TIMBER[int(clamp(lit * 7.0, 0, 7))])
    for bx_c in (38, 62, 96, 114):
        for dy in range(1, 5):
            put(body, bx_c, 92 + dy, TIMBER[4])
            put(body, bx_c + 1, 92 + dy, TIMBER[1])

    # Plaster fill for upper rectangle (`y = 58..88, x = 34..122`) + triangular front gable (`peak (77, 18)` down to `(34, 58)` and `(120, 58)`)
    for y in range(18, 89):
        if y < 58:
            span = (y - 18) / 40.0 * 43.0
            x0, x1 = int(round(77 - span)), int(round(77 + span))
        else:
            x0, x1 = 34, 122
        for x in range(x0, x1 + 1):
            side_wall = (x > 113 and y >= 58)
            rel_x = (x - 77.0) / 45.0
            lit = (0.34 if side_wall else (0.64 - 0.22 * rel_x - 0.08 * ((y - 50) / 40.0)))
            g = (fbm(x * 0.45, y * 0.45, seed + 13) - 0.5) * 0.65
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.52
            put(body, x, y, PLASTER[int(clamp(lit * 6.2 + g + dith, 0, len(PLASTER) - 1))])

    # Half-timbering oak posts, horizontal rails & diagonal wind-braces!
    for vx in (35, 59, 77, 95, 113, 121):
        y_top_p = 58 if vx not in (59, 77, 95) else (35 if vx in (59, 95) else 20)
        draw_beam(body, vx, y_top_p, vx, 88, 1.35, seed + vx)
    draw_beam(body, 35, 58, 121, 58, 1.4, seed + 71)
    draw_beam(body, 58, 37, 96, 37, 1.2, seed + 72)
    draw_beam(body, 35, 74, 113, 74, 1.1, seed + 73)
    # Diagonal St. Andrew / wind braces
    draw_beam(body, 36, 88, 58, 59, 1.1, seed + 74)
    draw_beam(body, 96, 59, 112, 88, 1.1, seed + 75)
    draw_beam(body, 60, 57, 76, 38, 1.0, seed + 76)
    draw_beam(body, 94, 57, 78, 38, 1.0, seed + 77)

    # 4) Steep Mossy Wooden Shingle Gable Roof (`front ridge peak at (68, 13)`, receding 3/4 ridge to `(108, 13)`,
    #    front eaves at `x = 26..110, y = 60`, wide visible 3/4 right shingle roof slope extending out to `x = 128`!)
    # First re-trim plaster/gable above roof slopes (`x = 28..118`) so front gable sits cleanly under `(68, 15)`!
    for y in range(15, 58):
        span_g = (y - 15) / 43.0 * 38.0
        gx0, gx1 = int(round(68 - span_g)), int(round(68 + span_g))
        for x in range(28, 130):
            if not (gx0 <= x <= gx1) and not (42 <= x <= 54 and y < 44):
                body[y][x] = CLEAR
    # Redraw front gable center timber post & mullioned attic window centered at `x = 68`!
    for y in range(17, 58):
        for x in range(int(round(68 - (y - 15) / 43.0 * 38.0)), int(round(68 + (y - 15) / 43.0 * 38.0)) + 1):
            rel_x = (x - 68.0) / 40.0
            lit = 0.64 - 0.22 * rel_x - 0.08 * ((y - 46) / 40.0)
            g = (fbm(x * 0.45, y * 0.45, seed + 13) - 0.5) * 0.65
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.52
            put(body, x, y, PLASTER[int(clamp(lit * 6.2 + g + dith, 0, len(PLASTER) - 1))])
    draw_beam(body, 68, 18, 68, 57, 1.3, seed + 168)
    draw_beam(body, 51, 38, 85, 38, 1.15, seed + 169)
    draw_beam(body, 52, 57, 67, 39, 1.0, seed + 170)
    draw_beam(body, 84, 57, 69, 39, 1.0, seed + 171)

    # Draw wide 3/4 Right Shingle Roof Slope (`ridge from (68, 13) to (102, 15)`, descending to eaves `(108, 60)..(132, 56)`)!
    for y in range(13, 62):
        t_r = (y - 13) / 48.0
        flare = 3.8 * max(0.0, (t_r - 0.65) / 0.35) ** 1.6
        lx_out = int(round(68.0 - t_r * 40.0 - flare))
        rx_front = int(round(68.0 + t_r * 40.0 + flare))
        rx_back = int(round(101.0 + t_r * 28.0 + flare * 0.7))

        # Expansive Shingled Right Roof Slope (`rx_front .. rx_back`) with crisp overlapping wooden shingle courses!
        for x in range(rx_front - 1, min(W - 4, rx_back + 1)):
            sh_course = (y - 13) // 4
            sh_row = (y - 13) % 4
            sh_col = (x + (3 if sh_course % 2 else 0)) % 6
            # Shingle overlap shadow on bottom row of each 4px course + sunlit upper lip + vertical shingle gaps
            lit = 0.24 if sh_row == 3 else (0.64 if sh_row == 0 else 0.48)
            lit -= 0.10 * ((x - rx_front) / 30.0)
            if sh_col == 0 and sh_row < 3:
                lit -= 0.22  # Vertical gap between individual wooden shingles!
            elif sh_col == 1:
                lit += 0.08
            if y <= 15:
                lit = 0.76  # Timber ridge-cap crest!
            g = (hsh(x // 2, sh_course, seed + 177) - 0.5) * 0.16
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42
            put(body, x, y, ROOF[int(clamp(lit * 7.2 + g + dith, 0, 7))])

        # Thick sculpted front gable verge / bargeboard (`6px` wide on both sunlit left & right front slopes)
        band_w = 6
        for x in range(lx_out, lx_out + band_w + 1):
            sh_r = (y + x) % 4
            put(body, x, y, ROOF[7 if x <= lx_out + 1 else (6 if sh_r != 0 else 4)])
        for x in range(lx_out + band_w + 1, lx_out + band_w + 3):
            put(body, x, y, TIMBER[2])

        for x in range(rx_front - band_w, rx_front + 1):
            sh_r = (y + x) % 4
            put(body, x, y, ROOF[6 if x == rx_front - band_w else (4 if sh_r != 0 else 2)])
        for x in range(rx_front - band_w - 2, rx_front - band_w):
            put(body, x, y, TIMBER[1])

    # Re-stamp upper part of stone chimney (`x = 43..53, y = 10..35`) so it rises cleanly through the left roof slope!
    for cy_c in range(11, 34, 4):
        for cx_c in (45.5, 50.5):
            draw_cobble(body, cx_c + (1.0 if (cy_c // 4) % 2 else 0.0), cy_c, 3.2, 2.2, seed + cy_c)
    for x in range(42, 55):
        put(body, x, 10, STONE[7 if x < 49 else 5])
        put(body, x, 11, STONE[4 if x < 49 else 2])
    drape_moss(body, 43, 52, 10, 2, 2, seed + 2)

    # Carved wooden finial post at gable apex `(68, 8..16)` + organic meadow moss blankets on roof shingles!
    for y in range(8, 17):
        put(body, 68, y, TIMBER[6 if y < 12 else 4])
        if y in (10, 14):
            put(body, 67, y, TIMBER[5])
            put(body, 69, y, TIMBER[2])
    for mx0, mx1, my0 in [(72, 86, 15), (84, 99, 25), (95, 112, 38), (104, 124, 51), (32, 42, 48), (54, 64, 24)]:
        drape_moss(body, mx0, mx1, my0, 2, 3, seed + mx0 + my0)

    # 5) Arched Oak Mill Door at bottom-center (`x = 70..90, y = 96..127`) + stone threshold step
    dcx, dcy = 80, 105
    for y in range(95, FY):
        for x in range(68, 93):
            dx_d = (x - dcx) / 10.2
            dy_d = (y - dcy) / 9.5
            in_door = (y <= dcy and dx_d * dx_d + dy_d * dy_d <= 0.78) or (y > dcy and abs(dx_d) <= 0.78)
            in_arch = (y <= dcy and dx_d * dx_d + dy_d * dy_d <= 1.15) or (y > dcy and abs(dx_d) <= 1.04)
            if in_door:
                # Vertical oak planks + wrought-iron strap hinges & ring handle
                plank_seam = ((x - 72) % 4 == 0)
                if plank_seam:
                    col = TIMBER[0]
                elif y in (108, 120) and x < 85:
                    col = IRON[3 if y == 108 else 2]  # Iron hinge straps
                else:
                    col = TIMBER[5 if x < dcx else 3]
                put(body, x, y, col)
            elif in_arch:
                # Dressed stone voussoir surround
                put(body, x, y, MORTAR if (y % 5 == 0 and y > dcy) else STONE[6 if x < dcx else 4])
    # Iron ring knocker/latch at `(86, 113)` + wide mossy stone threshold step (`x = 67..93, y = 126..128`)
    put(body, 86, 113, IRON[4])
    put(body, 86, 114, IRON[1])
    for x in range(67, 94):
        put(body, x, 126, STONE[7 if x < 82 else 5])
        put(body, x, 127, STONE[4 if x < 82 else 2])
        put(body, x, 128, STONE[1])

    # 6) Mullioned Attic Window (`x = 71..83, y = 41..53`), Left Casement Window (`x = 43..53, y = 63..73`) & Door Lantern (`x = 96, y = 100`)
    def draw_warm_window(wx0: int, wy0: int, wx1: int, wy1: int):
        for y in range(wy0 - 1, wy1 + 2):
            for x in range(wx0 - 1, wx1 + 2):
                if x in (wx0 - 1, wx1 + 1) or y in (wy0 - 1, wy1 + 1):
                    put(body, x, y, TIMBER[6 if y == wy1 + 1 else (4 if x == wx0 - 1 else 1)])
                elif x == (wx0 + wx1) // 2 or y == (wy0 + wy1) // 2:
                    put(body, x, y, TIMBER[1])  # Mullion crossbars
                else:
                    is_hot = (x < (wx0 + wx1) // 2 and y < (wy0 + wy1) // 2)
                    glow.emit(body, x, y, AMBER_M if is_hot else AMBER_D, AMBER_H if is_hot else AMBER_M, halo=2 if is_hot else 1)

    draw_warm_window(63, 41, 73, 51)
    draw_warm_window(43, 62, 53, 72)

    # Cozy wrought-iron door lantern hanging at `(96, 100)`
    put(body, 95, 97, IRON[3])
    put(body, 96, 97, IRON[4])
    put(body, 96, 98, IRON[2])
    for dx in (-2, -1, 0, 1, 2):
        put(body, 96 + dx, 99, IRON[3 if dx <= 0 else 1])
        put(body, 96 + dx, 103, IRON[1])
    for dy in (100, 101, 102):
        put(body, 94, dy, IRON[2])
        put(body, 98, dy, IRON[1])
        glow.emit(body, 95, dy, AMBER_M, AMBER_H, halo=2)
        glow.emit(body, 96, dy, AMBER_H, AMBER_H, halo=2)
        glow.emit(body, 97, dy, AMBER_D, AMBER_M, halo=1)

    # 7) Carved Round Millstone & Plump Grain Sacks leaning against the left wall (`x = 18..48, y = 105..129`)
    # Grooved circular millstone leaning at `(42, 119, r = 9.5)`
    mcx, mcy = 42, 119
    for dy in range(-9, 10):
        for dx in range(-9, 10):
            r = math.hypot(dx * 1.08, dy)
            if r <= 2.2:
                put(body, mcx + dx, mcy + dy, STONE[0])  # Square millstone eye
            elif r <= 9.2:
                furrow = ((dx + dy) % 4 == 0 and r < 8.0)
                lit = 0.68 - 0.35 * (dx / 9.0) - 0.35 * (dy / 9.0)
                put(body, mcx + dx, mcy + dy, STONE[2 if furrow else int(clamp(lit * 7.2, 1, 7))])

    # Two tied burlap flour/grain sacks (`(26, 121)` and `(34, 123)`)
    for scx, scy, srx, sry in [(25, 121, 6.2, 7.2), (33, 123, 5.8, 6.2)]:
        for dy in range(-int(sry) - 2, int(sry) + 1):
            for dx in range(-int(srx), int(srx) + 1):
                if dy < -int(sry) + 1:
                    # Tied sack ears at top!
                    if abs(dx) <= 2.4:
                        put(body, scx + dx, scy + dy, SACK[4 if dx <= 0 else 2])
                    continue
                d = (dx / srx) ** 2 + (dy / sry) ** 2
                if d <= 1.0:
                    lit = 0.64 - 0.36 * (dx / srx) - 0.32 * (dy / sry)
                    dith = (BAYER[(scy + dy) % 4][(scx + dx) % 4] / 16.0 - 0.5) * 0.5
                    col = ROPE[1] if dy == -int(sry) + 2 else SACK[int(clamp(lit * 5.2 + dith, 0, 5))]
                    put(body, scx + dx, scy + dy, col)

    # 8) Sturdy Timber Axle Housing & Wooden Mill-Flume on Right (`x ~ 116..134, y ~ 88..112`, wheel mounts at `(124, 98)`!)
    # Heavy stone & timber bearing block jutting from right wall around `(124, 98)` + overhead wooden flume trough (`y = 66..74, x = 118..146`)
    for y in range(66, 73):
        for x in range(116, 144):
            if y == 66:
                put(body, x, y, WATER_DROP[2 if x % 3 != 0 else 3])  # Gleaming headrace water in trough!
            elif y == 67:
                put(body, x, y, TIMBER[6])
            elif y == 72:
                put(body, x, y, TIMBER[0])
            else:
                put(body, x, y, TIMBER[4 if x < 132 else 3])
    # Angled timber strut supporting the flume (`(118, 86)` -> `(136, 72)`)
    draw_beam(body, 118, 86, 136, 72, 1.3, seed + 88)

    # Heavy timber axle housing / pillow-block centered at `(124, 98)`
    for y in range(92, 106):
        for x in range(116, 131):
            if y in (92, 105) or x == 130:
                put(body, x, y, TIMBER[1 if y == 105 else 5])
            else:
                put(body, x, y, TIMBER[4 if y < 98 else 2])
    # Forged iron axle collar at `(124, 98)` ready to receive `watermill_wheel.png`!
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            r = math.hypot(dx, dy)
            if r <= 2.2:
                put(body, 124 + dx, 98 + dy, TIMBER[6 if dx <= 0 and dy <= 0 else 2])
            elif r <= 4.0:
                put(body, 124 + dx, 98 + dy, IRON[4 if dx < 0 and dy < 0 else 1])

    # Lush riverside grass & reeds along foundation base
    for gx in range(20, 126, 8):
        for bdx, bdy, mi in [(-2, -2, 4), (-1, -4, 6), (0, -2, 2), (1, -3, 5), (2, -1, 3)]:
            put(body, gx + bdx, FY + bdy, MOSS[mi])

    # Soft ground shadow + 1px `#1b1a2e` outline
    sh = blank(W, H)
    for y in range(FY - 7, H):
        for x in range(W):
            d = ((x + 0.5 - 76.0) / 62.0) ** 2 + ((y + 0.5 - (FY + 1.0)) / 6.5) ** 2
            if d < 1.0:
                sh[y][x] = (*SHADOW_RGB, 114 if d < 0.48 else 60)
    framed = outline_pass(body, OUT)
    out = [[framed[y][x] if framed[y][x][3] > 0 else sh[y][x] for x in range(W)] for y in range(H)]
    return out, glow.finish()


# ==============================================================================
# 2. Watermill Wheel (`watermill_wheel.png`, 6 cols x 1 row of 64x72, hub at (32, 36))
# ==============================================================================
def build_watermill_wheel():
    FW, FH = 64, 72
    CX, CY = 32, 36
    # 6 spokes (`60 deg` symmetry) & 12 paddles (`30 deg` symmetry)!
    #Wait: if paddles have 30-deg spacing (`12 paddles`) and spokes have 60-deg spacing (`6 spokes`):
    # Actually if BOTH spokes and paddles share 12-fold or 8-fold symmetry:
    # With 6 spokes (`60 deg` spacing) and 12 paddles (`30 deg` spacing), advancing `10 deg` per frame across 6 frames advances `60 deg` — BOTH the 6-spoke wheel AND the 12-paddle rim return 100% identically to Frame 0 on Frame 6!
    N_SPOKES = 6
    N_PADDLES = 12
    STEP_DEG = 10.0  # 6 frames * 10 deg = 60 deg = exact spoke & 2x-paddle period!

    # 3/4 perspective wheel geometry (~52 px tall, ~44 px foreshortened horizontal width, +9 px 3/4 depth rim to the right/back!)
    RX, RY = 21.0, 26.0
    DEPTH_DX, DEPTH_DY = 8.0, -1.5

    frames = []
    for f_idx in range(6):
        ang0 = math.radians(f_idx * STEP_DEG)
        body = blank(FW, FH)

        def rim_pt(theta: float, r_scale: float = 1.0, back: bool = False):
            ox = DEPTH_DX if back else 0.0
            oy = DEPTH_DY if back else 0.0
            return (
                CX + ox + math.cos(theta) * RX * r_scale,
                CY + oy + math.sin(theta) * RY * r_scale,
            )

        # 1) Back 3/4 oak rim & back spokes (darker cool-shaded timber so depth reads unmistakably!)
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            bx, by = rim_pt(th, 0.92, back=True)
            steps = 24
            for s in range(steps + 1):
                t = s / float(steps)
                px_x = int(round((CX + DEPTH_DX) * (1 - t) + bx * t))
                py_y = int(round((CY + DEPTH_DY) * (1 - t) + by * t))
                put(body, px_x, py_y, TIMBER[1])
                put(body, px_x + 1, py_y, TIMBER[0])

        for deg in range(360):
            th = math.radians(deg)
            for rs in (0.86, 0.91, 0.96, 1.0):
                bx, by = rim_pt(th, rs, back=True)
                put(body, int(round(bx)), int(round(by)), TIMBER[2 if math.sin(th) < 0 else 1])

        # 2) 12 Wooden Bucket Paddles spanning between front rim and back rim (`th_p`)!
        # Draw back-half paddles first (`cos(th) < 0.2`), front-half paddles after, sorted by depth!
        paddle_order = sorted(range(N_PADDLES), key=lambda k: math.sin(ang0 + k * (math.tau / N_PADDLES)))
        for k_p in paddle_order:
            th = ang0 + k_p * (math.tau / N_PADDLES)
            fx0, fy0 = rim_pt(th, 0.88, back=False)
            fx1, fy1 = rim_pt(th, 1.07, back=False)
            bx1, by1 = rim_pt(th, 1.07, back=True)
            bx0, by0 = rim_pt(th, 0.88, back=True)
            # Fill wooden paddle plank quad `(fx0,fy0)-(fx1,fy1)-(bx1,by1)-(bx0,by0)`
            lit_p = 0.56 - 0.32 * math.sin(th) - 0.18 * math.cos(th)
            mossy = ((k_p + f_idx // 6) % 3 == 0)  # Wait: keep moss deterministic per angle slot or subtle wet tint so loop is seamless!
            for u_i in range(9):
                u = u_i / 8.0
                ax = fx0 + (fx1 - fx0) * u
                ay = fy0 + (fy1 - fy0) * u
                zx = bx0 + (bx1 - bx0) * u
                zy = by0 + (by1 - by0) * u
                for v_i in range(11):
                    v = v_i / 10.0
                    xx = int(round(ax + (zx - ax) * v))
                    yy = int(round(ay + (zy - ay) * v))
                    if u_i == 8:
                        col = TIMBER[6 if math.sin(th) < 0 else 4]
                    elif v_i in (0, 10):
                        col = TIMBER[1]
                    else:
                        col = MOSS[2] if (0.3 < v < 0.7 and math.sin(th * 2.0) > 0.55) else TIMBER[int(clamp(lit_p * 6.2, 1, 5))]
                    put(body, xx, yy, col)

        # 3) Front weathered dark-oak rim & 6 radial front spokes + iron tie-bolts!
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            fx, fy = rim_pt(th, 0.94, back=False)
            draw_beam(body, CX, CY, fx, fy, 1.25, 300 + i_s)

        for deg in range(720):
            th = math.radians(deg * 0.5)
            lit_r = 0.62 - 0.28 * math.cos(th) - 0.34 * math.sin(th)
            for rs_i, rs in enumerate((0.83, 0.88, 0.93, 0.98)):
                fx, fy = rim_pt(th, rs, back=False)
                ix, iy = int(round(fx)), int(round(fy))
                if rs_i in (0, 3):
                    col = TIMBER[1 if rs_i == 3 and math.sin(th) > 0.2 else 5]
                else:
                    col = TIMBER[int(clamp(lit_r * 6.8, 1, 6))]
                put(body, ix, iy, col)

        # Iron rivet bolts on front rim at each spoke tip
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            fx, fy = rim_pt(th, 0.91, back=False)
            put(body, int(round(fx)), int(round(fy)), IRON[4])

        # 4) Heavy Iron-Banded Oak Wheel Hub centered at `(32, 36)`
        for dy in range(-6, 7):
            for dx in range(-5, 8):
                d = ((dx - 1.0) / 5.2) ** 2 + (dy / 6.0) ** 2
                if d <= 0.22:
                    put(body, CX + dx, CY + dy, IRON[0])
                elif d <= 0.58:
                    put(body, CX + dx, CY + dy, IRON[4 if (dx <= 0 and dy <= 0) else 2])
                elif d <= 1.0:
                    put(body, CX + dx, CY + dy, TIMBER[5 if dx < 0 else 2])

        # 5) Gleaming Turquoise-White Water Droplets & Splash Arcs clinging to rising/falling paddles (`0..5` seamless phase!)
        for k_p in range(N_PADDLES):
            th = (ang0 + k_p * (math.tau / N_PADDLES)) % math.tau
            # Rising left paddles (`pi*0.55 .. pi*1.35`) & bottom splash (`pi*0.25 .. pi*0.75`) shed sparkling droplets!
            if 0.85 <= th <= 4.15:
                bx, by = rim_pt(th, 1.08, back=False)
                ix, iy = int(round(bx)), int(round(by))
                put(body, ix, iy + 1, WATER_DROP[3])
                put(body, ix, iy + 2, WATER_DROP[2])
                if 1.2 <= th <= 3.3:
                    drop_fall = int(((th * 3.0 + f_idx * 0.5) % 1.0) * 4.0)
                    put(body, ix - 1, iy + 3 + drop_fall, WATER_DROP[2 if drop_fall < 2 else 1])
                    put(body, ix - 1, iy + 2 + drop_fall, WATER_DROP[3])

        frames.append(outline_pass(body, OUT))

    sheet = blank(FW * 6, FH)
    for col, fr in enumerate(frames):
        for y in range(FH):
            sheet[y][col * FW:(col + 1) * FW] = fr[y]
    return sheet


# ==============================================================================
# 3. Watermill Jam (`watermill_jam.png`, 2 cols x 1 row of 48x48, center (24, 24))
# ==============================================================================
def build_watermill_jam():
    FW, FH = 48, 48
    sheet = blank(FW * 2, FH)

    # Col 0 (Jammed): Tangled bleached driftwood branch, river-weed & rusted iron chain wedged into lower spokes!
    jam = blank(FW, FH)
    # Crooked forked bleached driftwood log (`(6, 31)` -> `(41, 16)` + snag fork `(24, 23)` -> `(36, 34)`)
    for i in range(44):
        t = i / 43.0
        cx = 6.0 + 35.0 * t
        cy = 32.0 - 16.0 * t + 2.4 * math.sin(t * 5.2)
        rad = 3.2 * (1.0 - 0.35 * t)
        ix, iy = int(round(cx)), int(round(cy))
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                if dx * dx + dy * dy <= rad * rad:
                    lit = 0.62 - 0.25 * dx - 0.32 * dy
                    put(jam, ix + dx, iy + dy, DRIFTWOOD[int(clamp(lit * 4.5, 0, 4))])
    # Snagged secondary branch fork
    for i in range(22):
        t = i / 21.0
        ix = int(round(22.0 + 14.0 * t))
        iy = int(round(24.0 + 10.0 * t + 1.2 * math.sin(t * 4.0)))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                put(jam, ix + dx, iy + dy, DRIFTWOOD[3 if dy <= 0 else 1])

    # Dripping dark emerald river-weed & algae tangled over the driftwood (`x = 14..34, y = 18..39`)
    for wx in range(13, 35, 2):
        wy0 = int(round(29 - (wx - 12) * 0.42))
        w_len = 5 + (wx * 3) % 6
        for k in range(w_len):
            put(jam, wx + (k // 3), wy0 + k, MOSS[4 if k < 2 else (2 if k < w_len - 2 else 1)])

    # Rusted iron chain links wrapped tightly around the snagged log (`x = 18..30, y = 16..34`)
    chain_pts = [(19, 17), (20, 19), (21, 21), (22, 23), (23, 25), (24, 27), (25, 29), (26, 31), (28, 33)]
    for li, (cx_l, cy_l) in enumerate(chain_pts):
        for dx, dy in [(-1, 0), (0, -1), (1, 0), (0, 1)]:
            put(jam, cx_l + dx, cy_l + dy, RUST[3 if (dx + dy < 0) else 1] if li % 2 == 0 else IRON[3 if dy < 0 else 1])

    jam_out = outline_pass(jam, OUT)

    # Col 1 (Cleared remnant): Tiny harmless mossy river stone beside the race (`cx = 24, cy = 34`)
    clr = blank(FW, FH)
    draw_cobble(clr, 24.0, 34.0, 4.5, 2.8, 405, wet=True)
    drape_moss(clr, 21, 27, 32, 2, 1, 409)
    clr_out = outline_pass(clr, OUT)

    for y in range(FH):
        sheet[y][0:FW] = jam_out[y]
        sheet[y][FW:FW * 2] = clr_out[y]
    return sheet


# ==============================================================================
# 4. Broken Stone Bridge (`broken_stone_bridge.png` & `_glow.png`, 4x1 of 96x96, center (48, 56))
# ==============================================================================
def draw_wayfarer_lantern_post(px, glow: GlowMap, cx: int, cy: int):
    """Carved stone parapet lantern pillar with turquoise-amber wayfarer rune/flame so players spot Shadow-Step crossings at night!"""
    for dy in range(-9, 3):
        for dx in range(-3, 4):
            if dy in (-9, -5, 2) and abs(dx) <= 3:
                put(px, cx + dx, cy + dy, STONE[7 if dx <= 0 else 4])
            elif abs(dx) <= 2:
                if -4 <= dy <= -1 and abs(dx) <= 1:
                    put(px, cx + dx, cy + dy, STONE[0])
                else:
                    put(px, cx + dx, cy + dy, STONE[6 if dx < 0 else 3])
    # Glowing turquoise-amber wayfarer core inside lantern + rune below!
    glow.emit(px, cx, cy - 3, AMBER_H, AMBER_H, halo=2)
    glow.emit(px, cx, cy - 2, BRIDGE_GOLD, BRIDGE_GOLD, halo=2)
    glow.emit(px, cx - 1, cy - 2, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=1)
    glow.emit(px, cx, cy + 1, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)


def shade_flagstone_deck(px, x: int, y: int, seed: int):
    """Draws irregular fitted road flagstones with dark mortar joints & sunlit bevels."""
    gx = (x + (4 if (y // 7) % 2 else 0)) % 9
    gy = y % 7
    if gx == 0 or gy == 0:
        return MORTAR
    tile_id = (x // 9) * 31 + (y // 7) * 17
    bias = (hsh(tile_id, y // 7, seed) - 0.5) * 0.22
    lit = 0.58 + bias + (0.16 if gx == 1 or gy == 1 else 0.0) - (0.12 if gx == 8 or gy == 6 else 0.0)
    g = (fbm(x * 0.55, y * 0.55, seed + 3) - 0.5) * 0.65
    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5
    return STONE[int(clamp(lit * 6.8 + g + dith, 1, 7))]


def build_bridge_variant(col: int):
    W, H = 96, 96
    glow = GlowMap(W, H)
    body = blank(W, H)
    seed = 2501 + col * 47
    rng = random.Random(seed)

    if col in (0, 1):
        # ---- Horizontal Bridge Abutments:
        # Col 0 (West bank pointing East ->): `x = 4..86`, walkable flagstone deck `y = 38..64` (26px wide),
        #       low parapet walls (`y = 31..37` & `y = 65..72`), mossy stone arch vault underneath (`y = 72..90`),
        #       jagged crumbled stones on right (`x = 75..88`)!
        # Col 1 (East bank pointing <- West): `x = 10..92`, jagged crumbled edge on left (`x = 8..21`), intact approach on right!
        is_west = (col == 0)

        for y in range(30, 91):
            for x in range(4, 92):
                # Jagged fracture profile on broken waterward end + flared shoreward approach!
                jag = int(5.5 * math.sin(y * 0.34 + col * 2.1) + 3.5 * hsh(0, y // 3, seed))
                if is_west:
                    x_min = 4 + (2 if 38 <= y <= 64 else 0)
                    x_max = 81 + jag if y <= 73 else (74 - max(0, (y - 73) // 2))
                else:
                    x_min = 15 + jag if y <= 73 else (22 + max(0, (y - 73) // 2))
                    x_max = 91 - (2 if 38 <= y <= 64 else 0)

                if not (x_min <= x <= x_max):
                    continue

                # 1) North (back) low parapet wall (`y = 31..37`)
                if 31 <= y <= 37:
                    if y in (31, 32):
                        col_px = STONE[7 if y == 31 else 6] if (x % 10 != 0) else MORTAR
                    elif y == 37:
                        col_px = MORTAR
                    else:
                        col_px = STONE[4 if (x + y) % 9 != 0 else 2]
                    put(body, x, y, col_px)

                # 2) Walkable paved flagstone road deck (`y = 38..64`, 27px wide!)
                elif 38 <= y <= 64:
                    col_px = shade_flagstone_deck(body, x, y, seed)
                    if y in (38, 39):
                        # Soft parapet cast shadow along north edge of road
                        idx = STONE.index(col_px) if col_px in STONE else 3
                        col_px = STONE[max(1, idx - 2)]
                    # Moss invading cracks near shore & broken brink
                    if (x % 9 == 0 or y % 7 == 0) and fbm(x * 0.25, y * 0.25, seed + 19) > 0.58:
                        col_px = MOSS[3 if y < 52 else 2]
                    put(body, x, y, col_px)

                # 3) South (front) parapet wall (`y = 65..72`, seen in 3/4 elevation!)
                elif 65 <= y <= 72:
                    if y in (65, 66):
                        col_px = STONE[7 if y == 65 else 5] if (x % 11 != 0) else MORTAR
                    elif y == 72 or x % 11 == 0:
                        col_px = MORTAR
                    else:
                        col_px = STONE[5 if y < 69 else 3]
                    put(body, x, y, col_px)

                # 4) Underneath 3/4 Stone Spandrel & Broken Arch Vault (`y = 73..90`)!
                else:
                    # Arch cutout opening toward the river gap (`x > 42` for West, `x < 54` for East)
                    arch_cx = 76.0 if is_west else 20.0
                    dx_a = (x - arch_cx) / 30.0
                    dy_a = (91.0 - y) / 16.5
                    r_a = dx_a * dx_a + dy_a * dy_a
                    if r_a < 0.84:
                        # Dark recessed stone vault soffit visible under the broken arch (only near pier side)
                        if r_a > 0.56 and ((is_west and x < 64) or (not is_west and x > 32)):
                            put(body, x, y, WET_STONE[0 if dy_a < 0.5 else 1])
                        continue
                    elif r_a < 1.12:
                        # Radial stone arch voussoirs!
                        ang = math.atan2(dy_a, dx_a)
                        put(body, x, y, MORTAR if int(abs(ang) * 9) % 3 == 0 else STONE[5 if y < 80 else 3])
                    else:
                        # Wet river-pier masonry courses
                        is_j = ((y - 73) % 5 == 4) or ((x + (5 if ((y - 73) // 5) % 2 else 0)) % 10 == 0)
                        if is_j:
                            put(body, x, y, MORTAR)
                        else:
                            put(body, x, y, WET_STONE[3 if y < 82 else 2] if y > 83 else STONE[3 if x < 48 else 2])

        # Scattered jutting rubble stones at the broken chasm brink + lush moss drapes + wayfarer lantern!
        brink_x = 82 if is_west else 14
        for dy_r, dx_r, rx_r in [(41, 3, 3.6), (52, 5, 4.2), (61, 2, 3.8), (69, 4, 3.5)]:
            sgn = 1 if is_west else -1
            draw_cobble(body, brink_x + sgn * dx_r, dy_r, rx_r, 2.5, seed + dy_r)

        if is_west:
            drape_moss(body, 6, 36, 31, 2, 3, seed + 31)
            drape_moss(body, 48, 74, 65, 2, 4, seed + 33)
            draw_wayfarer_lantern_post(body, glow, 58, 33)
            # Glowing turquoise rune on south parapet near jump brink (`(68, 69)`)
            glow.emit(body, 68, 69, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)
        else:
            drape_moss(body, 58, 90, 31, 2, 3, seed + 35)
            drape_moss(body, 22, 52, 65, 2, 4, seed + 37)
            draw_wayfarer_lantern_post(body, glow, 38, 33)
            glow.emit(body, 28, 69, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)

    else:
        # ---- Vertical Bridge Abutments:
        # Col 2 (North bank pointing South v): `x = 28..68` walkable deck (`x = 22..74` with side parapets), `y = 6..85`, broken arch at bottom (`y = 74..86`)!
        # Col 3 (South bank pointing ^ North): `x = 28..68` walkable deck (`x = 22..74` with side parapets), `y = 11..90`, broken arch at top (`y = 10..22`)!
        is_north = (col == 2)
        for y in range(6, 91):
            for x in range(21, 76):
                jag = int(5.0 * math.sin(x * 0.36 + col * 1.7) + 3.5 * hsh(x // 3, 0, seed))
                if is_north:
                    y_min = 6
                    y_max = 79 + jag
                else:
                    y_min = 16 + jag
                    y_max = 90
                if not (y_min <= y <= y_max):
                    continue

                # Left parapet (`x = 22..27`), walkable flagstone deck (`x = 28..68`), right parapet (`x = 69..74`)
                if 22 <= x <= 27:
                    if y % 9 == 0:
                        col_px = MORTAR
                    elif x in (22, 23):
                        col_px = STONE[7]
                    elif x == 27:
                        col_px = STONE[2]
                    else:
                        col_px = STONE[5]
                    put(body, x, y, col_px)
                elif 69 <= x <= 74:
                    if y % 9 == 0:
                        col_px = MORTAR
                    elif x in (69, 70):
                        col_px = STONE[6]
                    elif x == 74:
                        col_px = STONE[1]
                    else:
                        col_px = STONE[4]
                    put(body, x, y, col_px)
                elif 28 <= x <= 68:
                    # At the broken south edge of Col 2 (`y >= 75`), show the broken stone arch vault thickness underneath!
                    if is_north and y >= 75:
                        dx_v = (x - 48.0) / 18.0
                        arch_lip = 76 + int(5.5 * (1.0 - dx_v * dx_v))
                        if y >= arch_lip:
                            put(body, x, y, WET_STONE[1 if y > arch_lip + 2 else 3])
                            continue
                    col_px = shade_flagstone_deck(body, x, y, seed)
                    if x in (28, 29):
                        idx = STONE.index(col_px) if col_px in STONE else 3
                        col_px = STONE[max(1, idx - 2)]
                    if (x % 9 == 0 or y % 7 == 0) and fbm(x * 0.25, y * 0.25, seed + 29) > 0.58:
                        col_px = MOSS[3]
                    put(body, x, y, col_px)

        # Jutting broken flagstones at the river brink + moss cushions + wayfarer lanterns!
        brink_y = 80 if is_north else 15
        sgn = 1 if is_north else -1
        for bx_r, dy_r in [(33, 3), (44, 5), (55, 4), (63, 2)]:
            draw_cobble(body, bx_r, brink_y + sgn * dy_r, 3.6, 2.5, seed + bx_r)

        if is_north:
            drape_moss(body, 22, 28, 18, 3, 4, seed + 41)
            drape_moss(body, 68, 74, 42, 3, 4, seed + 43)
            draw_wayfarer_lantern_post(body, glow, 25, 62)
            glow.emit(body, 71, 62, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)
        else:
            drape_moss(body, 22, 28, 52, 3, 4, seed + 45)
            drape_moss(body, 68, 74, 34, 3, 4, seed + 47)
            draw_wayfarer_lantern_post(body, glow, 25, 34)
            glow.emit(body, 71, 34, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)

    out = outline_pass(body, OUT)
    return out, glow.finish()


# ==============================================================================
# 5. Fisher Pier (`fisher_pier.png` & `_glow.png`, 4x1 of 96x96, center (48, 52))
# ==============================================================================
def draw_pier_props(px, glow: GlowMap, lx: int, ly: int, rx_rope: int, ry_rope: int, cx_creel: int, cy_creel: int):
    """Adds coiled hemp mooring rope, woven wicker fisher creel/bucket, and warm iron hook-lantern at pier tip!"""
    # Coiled mooring rope (`3.5 px` radius)
    for dy in range(-3, 4):
        for dx in range(-4, 5):
            r = math.hypot(dx * 0.9, dy * 1.15)
            if r <= 3.6:
                ring = int(r * 1.6) % 2
                put(px, rx_rope + dx, ry_rope + dy, ROPE[4 if (ring == 0 and dy <= 0) else (2 if ring == 0 else 1)])

    # Wicker fisher creel / wooden bucket (`cx_creel, cy_creel`)
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if abs(dx) <= 3 and abs(dy) <= 3:
                if dy == -3:
                    put(px, cx_creel + dx, cy_creel + dy, SACK[4 if dx <= 0 else 2])
                elif dy == 0:
                    put(px, cx_creel + dx, cy_creel + dy, IRON[2])  # Hoop band
                else:
                    put(px, cx_creel + dx, cy_creel + dy, SACK[3 if dx < 0 else 1])

    # Sturdy wooden lantern post (`(lx, ly)` down to `(lx, ly - 13)`) + iron hook + warm amber lantern!
    for dy in range(0, 14):
        put(px, lx - 1, ly - dy, TIMBER[5])
        put(px, lx, ly - dy, TIMBER[3])
        put(px, lx + 1, ly - dy, TIMBER[1])
    # Iron hook arm & hanging lantern cage (`cx = lx + 3, cy = ly - 10`)
    for dx in range(0, 5):
        put(px, lx + dx, ly - 13, IRON[4 if dx < 3 else 2])
    hx, hy = lx + 4, ly - 10
    put(px, hx, hy - 2, IRON[3])
    for dx in (-1, 0, 1):
        put(px, hx + dx, hy - 1, IRON[3])
        put(px, hx + dx, hy + 2, IRON[1])
    glow.emit(px, hx, hy, PIER_G3, PIER_G3, halo=2)
    glow.emit(px, hx, hy + 1, PIER_G2, PIER_G2, halo=2)
    glow.emit(px, hx - 1, hy, PIER_G1, PIER_G2, halo=1)


def build_fisher_pier_variant(col: int):
    W, H = 96, 96
    body = blank(W, H)
    glow = GlowMap(W, H)
    seed = 2801 + col * 37
    rng = random.Random(seed)

    if col in (0, 1):
        # Col 0: Extends East (`x = 8..86`, deck `y = 40..62`)
        # Col 1: Extends West (`x = 10..88`, deck `y = 40..62`)
        x0, x1 = (8, 86) if col == 0 else (10, 88)
        y0, y1 = 40, 62

        # Mossy submerged/wet wooden pilings along front (`y = 61..74`) and back (`y = 35..41`)
        piling_xs = [x0 + 6, x0 + 26, x0 + 48, x1 - 5]
        for px_p in piling_xs:
            # Back piling cap sticking just above deck
            for py in range(36, 42):
                for dx in (-2, -1, 0, 1, 2):
                    put(body, px_p + dx, py, TIMBER[6 if py == 36 else (4 if dx < 0 else 1)])
            # Front piling leg descending into water with wet green algae waterline!
            for py in range(59, 75):
                for dx in (-2, -1, 0, 1, 2):
                    if py == 59:
                        col_p = TIMBER[6 if dx <= 0 else 4]
                    elif py >= 70:
                        col_p = MOSS[2 if dx < 0 else 0]  # Wet waterline algae!
                    else:
                        col_p = TIMBER[4 if dx < 0 else (2 if dx == 0 else 0)]
                    put(body, px_p + dx, py, col_p)
            # Horizontal stringer beam under front edge of deck (`y = 63..65`)
        for x in range(x0 + 1, x1):
            put(body, x, 63, TIMBER[2])
            put(body, x, 64, TIMBER[0])
        # Mooring rope lashed around two pilings
        for px_p in (piling_xs[1], piling_xs[3]):
            for dx in (-2, -1, 0, 1, 2):
                put(body, px_p + dx, 62, ROPE[3 if dx <= 0 else 1])

        # Transverse weathered wooden deck planks (`4px` wide each with 1px dark water gap & slightly uneven ends!)
        p_cur = x0
        p_idx = 0
        while p_cur <= x1 - 3:
            pw = 4
            jit_t = int(round((hsh(p_idx, 0, seed) - 0.5) * 2.2))
            jit_b = int(round((hsh(p_idx, 1, seed) - 0.5) * 2.2))
            tone_b = (hsh(p_idx, 2, seed) - 0.5) * 0.9
            for py in range(y0 + jit_t, y1 + jit_b + 1):
                for dx in range(pw):
                    px_x = p_cur + dx
                    if px_x > x1:
                        continue
                    if dx == pw - 1:
                        col_w = TIMBER[0]  # Gap between planks
                    elif dx == 0 or py == y0 + jit_t:
                        col_w = PLANK[6 if py < 50 else 5]
                    else:
                        g = (fbm(px_x * 0.6, py * 0.35, seed + 5) - 0.5) * 1.1
                        col_w = PLANK[int(clamp(3.6 + tone_b + g, 1, 5))]
                    put(body, px_x, py, col_w)
                # Tiny iron nail dots along stringers (`y = 43` and `y = 59`)
                if py in (43, 59):
                    put(body, p_cur + 1, py, IRON[1])
            p_cur += pw
            p_idx += 1

        # Moss patches on damp plank ends
        drape_moss(body, x0 + 14, x0 + 23, y0, 2, 1, seed + 11)
        if col == 0:
            draw_pier_props(body, glow, lx=x1 - 6, ly=y0 + 3, rx_rope=x1 - 14, ry_rope=y1 - 4, cx_creel=x0 + 14, cy_creel=y0 + 4)
        else:
            draw_pier_props(body, glow, lx=x0 + 5, ly=y0 + 3, rx_rope=x0 + 14, ry_rope=y1 - 4, cx_creel=x1 - 14, cy_creel=y0 + 4)

    else:
        # Col 2: Extends South (`x = 34..62`, deck `y = 8..86`)
        # Col 3: Extends North (`x = 34..62`, deck `y = 10..88`)
        x0, x1 = 34, 62
        y0, y1 = (8, 86) if col == 2 else (10, 88)

        # Side pilings along left (`x = 31..35`) and right (`x = 61..65`)
        piling_ys = [y0 + 8, y0 + 28, y0 + 50, y1 - 6]
        for py_p in piling_ys:
            for side_x in (x0 - 2, x1 + 2):
                for dy in range(-2, 9):
                    for dx in (-2, -1, 0, 1, 2):
                        if dy == -2:
                            col_p = TIMBER[6 if dx <= 0 else 4]
                        elif dy >= 5:
                            col_p = MOSS[2 if dx < 0 else 0]
                        else:
                            col_p = TIMBER[4 if dx < 0 else 1]
                        put(body, side_x + dx, py_p + dy, col_p)

        # Horizontal cross-planks (`4px` tall each) running from `y0` to `y1`
        p_cur = y0
        p_idx = 0
        while p_cur <= y1 - 3:
            ph = 4
            jit_l = int(round((hsh(p_idx, 3, seed) - 0.5) * 2.2))
            jit_r = int(round((hsh(p_idx, 4, seed) - 0.5) * 2.2))
            tone_b = (hsh(p_idx, 5, seed) - 0.5) * 0.9
            for dy in range(ph):
                py = p_cur + dy
                if py > y1:
                    continue
                for px_x in range(x0 + jit_l, x1 + jit_r + 1):
                    if dy == ph - 1:
                        col_w = TIMBER[0]
                    elif dy == 0 or px_x == x0 + jit_l:
                        col_w = PLANK[6 if px_x < 48 else 5]
                    else:
                        g = (fbm(px_x * 0.35, py * 0.6, seed + 9) - 0.5) * 1.1
                        col_w = PLANK[int(clamp(3.6 + tone_b + g, 1, 5))]
                    put(body, px_x, py, col_w)
                if dy == 1:
                    put(body, x0 + 3, py, IRON[1])
                    put(body, x1 - 3, py, IRON[1])
            p_cur += ph
            p_idx += 1

        drape_moss(body, x0, x0 + 6, y0 + 18, 2, 2, seed + 19)
        if col == 2:
            # Tip at South (`y1 = 86`)
            draw_pier_props(body, glow, lx=x1 - 3, ly=y1 - 3, rx_rope=x0 + 6, ry_rope=y1 - 6, cx_creel=x1 - 5, cy_creel=y0 + 12)
        else:
            # Tip at North (`y0 = 10`, keep lantern post starting at `y = 20` so `ly - 13 = 7 >= 2` stays well inside frame!)
            draw_pier_props(body, glow, lx=x1 - 4, ly=y0 + 10, rx_rope=x0 + 6, ry_rope=y0 + 7, cx_creel=x1 - 5, cy_creel=y1 - 12)

    out = outline_pass(body, OUT)
    return out, glow.finish()


# ==============================================================================
# 6. Reed Rowboat (`reed_rowboat.png`, 2 cols x 1 row of 64x48, center (32, 28))
# ==============================================================================
def build_reed_rowboat():
    FW, FH = 64, 48
    sheet = blank(FW * 2, FH)

    for col in range(2):
        unsearched = (col == 0)
        body = blank(FW, FH)
        seed = 3101 + col

        # 1) Back-layer green-gold lake reeds swaying behind the boat (`y = 6..28, x = 8..56`)
        back_reeds = [10, 14, 17, 22, 43, 47, 51, 55]
        for rx_r in back_reeds:
            r_h = 12 + (rx_r * 5) % 9
            lean = 0.16 if (rx_r % 2 == 0) else -0.10
            for k in range(r_h):
                yy = 27 - k
                xx = int(round(rx_r + k * lean))
                put(body, xx, yy, REED[min(5, 1 + k // 3)])
                if k == r_h - 2 and rx_r in (14, 47):
                    # Cattail / reed seed plume!
                    put(body, xx, yy - 1, TIMBER[2])
                    put(body, xx, yy - 2, TIMBER[3])
                    put(body, xx, yy - 3, REED[5])

        # 2) Weathered Wooden Rowboat Hull (`cx = 32, cy = 28`, tilted slightly at ~ -10 deg in 3/4 view:
        #    pointed bow on upper-right `(53, 22)`, square transom stern on lower-left `(12, 30)`)
        ca, sa = math.cos(-0.18), math.sin(-0.18)
        for y in range(15, 41):
            for x in range(9, 57):
                dx0, dy0 = x - 32.0, y - 27.5
                # Boat local coords: u along keel (-20 stern .. +21 bow), v across beam
                u = dx0 * ca - dy0 * sa
                v = dx0 * sa + dy0 * ca
                if u < -19.5 or u > 20.5:
                    continue
                # Hull half-beam: tapers sharply to pointed bow (`u > 4`), slightly narrower at transom stern (`u < -12`)
                if u > 4.0:
                    hb = 8.4 * max(0.0, 1.0 - ((u - 4.0) / 16.8) ** 1.45)
                elif u < -10.0:
                    hb = 8.4 * (1.0 - 0.25 * ((-10.0 - u) / 9.5))
                else:
                    hb = 8.4

                # 3/4 hull exterior drop below gunwale (`v > hb` up to `hb + 5.5` on visible front/south side!)
                if -hb <= v <= hb:
                    # Inside boat cockpit vs gunwale rail!
                    if abs(v) >= hb - 1.35 or u <= -18.0 or u >= 18.8:
                        # Raised weathered oak gunwale rail
                        put(body, x, y, PLANK[6 if v < 0 else 4])
                    else:
                        # Interior bilge planks, ribs & two wooden thwarts (bench seats at `u ~ -6` and `u ~ +5`)
                        if abs(u + 6.0) <= 1.6 or abs(u - 5.2) <= 1.6:
                            put(body, x, y, PLANK[5 if v < 2 else 3])
                        elif int(round(u)) % 5 == 0:
                            put(body, x, y, TIMBER[1])  # Curved oak hull ribs
                        else:
                            plank_row = int(v + 10) % 3
                            put(body, x, y, PLANK[1 if plank_row == 0 else (3 if v > 1 else 2)])
                elif hb < v <= hb + 5.2 * (1.0 - 0.35 * abs(u / 21.0)):
                    # Exterior clinker-built side planks + mossy waterline!
                    depth_s = v - hb
                    if depth_s > 3.6:
                        put(body, x, y, MOSS[2 if (x + y) % 3 else 3])  # Mossy wet waterline
                    elif int(depth_s * 1.4) % 2 == 0:
                        put(body, x, y, TIMBER[4 if u > 0 else 3])
                    else:
                        put(body, x, y, TIMBER[2 if u > 0 else 1])

        # Mossy patches clinging to stern & gunwale
        drape_moss(body, 13, 21, 24, 2, 2, seed + 7)
        drape_moss(body, 36, 43, 31, 2, 1, seed + 9)

        # 3) Wooden Oar resting diagonally inside the hull (`(18, 29)` -> `(41, 24)`)
        for i in range(25):
            t = i / 24.0
            ox = int(round(18.0 + 23.0 * t))
            oy = int(round(29.0 - 5.0 * t))
            put(body, ox, oy, SACK[4 if t < 0.7 else 3])
            if t > 0.68:
                # Wider flat oar paddle blade
                put(body, ox, oy + 1, SACK[2])
                put(body, ox, oy - 1, SACK[4])

        # 4) Col 0 (Unsearched): Tucked Canvas Bundle / Fisher Satchel with brass buckle gleaming in the bow (`cx = 44, cy = 24`)!
        #    Col 1 (Searched): Bundle taken — only a loose bit of twine/plank remains!
        if unsearched:
            for dy in range(-3, 4):
                for dx in range(-4, 5):
                    if (dx / 4.2) ** 2 + (dy / 3.2) ** 2 <= 1.0:
                        lit = 0.68 - 0.30 * (dx / 4.0) - 0.32 * (dy / 3.0)
                        col_b = SACK[int(clamp(lit * 5.4, 1, 5))]
                        if dx == 0:
                            col_b = TIMBER[2]  # Leather satchel strap
                        put(body, 43 + dx, 24 + dy, col_b)
            # Gleaming sunlit brass clasp/highlight on the unsearched bundle so players spot the loot!
            put(body, 43, 23, AMBER_H)
            put(body, 42, 23, AMBER_M)
        else:
            # Small loose coil of rope left behind in bow
            put(body, 43, 25, ROPE[2])
            put(body, 44, 25, ROPE[1])

        # 5) Foreground green-gold lake reeds & water-ripple highlights framing the hull (`y = 26..42`)
        front_reeds = [12, 16, 25, 29, 46, 50, 54]
        for rx_r in front_reeds:
            r_h = 10 + (rx_r * 3) % 7
            lean = 0.14 if rx_r < 32 else -0.15
            base_y = 39 if 22 <= rx_r <= 48 else 36
            for k in range(r_h):
                yy = base_y - k
                xx = int(round(rx_r + k * lean))
                put(body, xx, yy, REED[min(5, 2 + k // 3)])

        framed = outline_pass(body, OUT)
        # Subtle cool water-reflection / reed shadow ring around hull base (`y = 32..43`)
        for y in range(30, 44):
            for x in range(8, 58):
                if framed[y][x][3] == 0:
                    d = ((x - 32.0) / 24.0) ** 2 + ((y - 34.0) / 8.0) ** 2
                    if d < 1.0:
                        framed[y][x] = (*SHADOW_RGB, 88 if d < 0.55 else 44)

        for y in range(FH):
            sheet[y][col * FW:(col + 1) * FW] = framed[y]

    return sheet


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/water_pois_sheet.png`)
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


def crop(sheet, x0: int, y0: int, w: int, h: int):
    return [row[x0:x0 + w] for row in sheet[y0:y0 + h]]


def pack_row(frames, fw: int, fh: int):
    out = blank(fw * len(frames), fh)
    for col, f in enumerate(frames):
        for y in range(fh):
            out[y][col * fw:(col + 1) * fw] = f[y]
    return out


def render_qa_sheet(mill_px, mill_gl, wheel_sheet, jam_sheet, bridges, piers, boat_sheet):
    cw, ch = 660, 560
    canvas = blank(cw, ch)
    half = 280

    # Scenic meadow bank + winding blue-teal river/lake channel backdrop (daylight top half, night bottom half)
    for y in range(ch):
        night = y >= half
        ly = y % half
        for x in range(cw):
            # River channel runs through the bridge & pier showcase zones (`x > 210` & `ly > 82`, plus mill race at `x = 130..205`)
            in_water = (x >= 210 and ly >= 86) or (126 <= x <= 206 and ly >= 112)
            n = noise(x // 4, y // 3, 149)
            if in_water:
                ripple = ((x + ly * 2) % 17 == 0 and n > 150)
                if not night:
                    canvas[y][x] = (92, 186, 194, 255) if ripple else ((38, 108, 132, 255) if n < 120 else (48, 128, 150, 255))
                else:
                    canvas[y][x] = (46, 98, 122, 255) if ripple else ((18, 42, 68, 255) if n < 120 else (24, 52, 80, 255))
            else:
                if not night:
                    canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
                else:
                    canvas[y][x] = (20, 28, 48, 255) if n < 115 else ((25, 36, 58, 255) if n < 205 else (31, 44, 68, 255))

    w0 = crop(wheel_sheet, 0, 0, 64, 72)
    j0 = crop(jam_sheet, 0, 0, 48, 48)
    j1 = crop(jam_sheet, 48, 0, 48, 48)
    b0 = crop(boat_sheet, 0, 0, 64, 48)
    b1 = crop(boat_sheet, 64, 0, 64, 48)

    for p_i in range(2):
        night = p_i == 1
        yo = 0 if not night else half

        # 1) Old Watermill (`(8, yo + 10)`) with `watermill_wheel.png` frame 0 mounted right on axle `(124, 98)`!
        mx, my = 8, yo + 10
        alpha_over(canvas, tint_night_px(mill_px) if night else mill_px, mx, my)
        # Mount wheel hub `(32, 36)` onto mill axle `(mx + 124, my + 98)` -> `(mx + 92, my + 62)`
        alpha_over(canvas, tint_night_px(w0) if night else w0, mx + 92, my + 62)
        if night:
            add_glow_over(canvas, mill_gl, mx, my)

        # Wheel frames strip (3 sample frames) + Jammed/Cleared sprites below the watermill (`ly = 166..268`)
        for fi in range(3):
            wf = crop(wheel_sheet, fi * 2 * 64, 0, 64, 72)
            alpha_over(canvas, tint_night_px(wf) if night else wf, 6 + fi * 64, yo + 178)
        alpha_over(canvas, tint_night_px(j0) if night else j0, 12, yo + 230)
        alpha_over(canvas, tint_night_px(j1) if night else j1, 68, yo + 230)

        # 2) Top-right strip (`x = 212..648, ly = 4..82`): 2 Reed Rowboats + standalone wheel frames
        alpha_over(canvas, tint_night_px(b0) if night else b0, 218, yo + 18)
        alpha_over(canvas, tint_night_px(b1) if night else b1, 294, yo + 18)

        # Show West->East and East<-West broken stone bridge abutments facing each other across a gap!
        br_w, br_w_gl = bridges[0]
        br_e, br_e_gl = bridges[1]
        alpha_over(canvas, tint_night_px(br_w) if night else br_w, 376, yo + 2)
        alpha_over(canvas, tint_night_px(br_e) if night else br_e, 504, yo + 2)
        if night:
            add_glow_over(canvas, br_w_gl, 376, yo + 2)
            add_glow_over(canvas, br_e_gl, 504, yo + 2)

        # Show North->South and South->North broken stone bridge abutments on mid-right (`ly = 96..192`)
        br_n, br_n_gl = bridges[2]
        br_s, br_s_gl = bridges[3]
        alpha_over(canvas, tint_night_px(br_n) if night else br_n, 214, yo + 90)
        alpha_over(canvas, tint_night_px(br_s) if night else br_s, 314, yo + 90)
        if night:
            add_glow_over(canvas, br_n_gl, 214, yo + 90)
            add_glow_over(canvas, br_s_gl, 314, yo + 90)

        # 4 Fisher Piers (East, West, South, North) across right water basin!
        pier_coords = [(422, yo + 90), (532, yo + 90), (422, yo + 182), (532, yo + 182)]
        for pi_idx, (px_pos, py_pos) in enumerate(pier_coords):
            p_px, p_gl = piers[pi_idx]
            alpha_over(canvas, tint_night_px(p_px) if night else p_px, px_pos, py_pos)
            if night:
                add_glow_over(canvas, p_gl, px_pos, py_pos)

    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"

    mill_px, mill_gl = build_old_watermill()
    wheel_sheet = build_watermill_wheel()
    jam_sheet = build_watermill_jam()

    bridges = [build_bridge_variant(i) for i in range(4)]
    bridge_sheet = pack_row([b for b, _ in bridges], 96, 96)
    bridge_glow = pack_row([g for _, g in bridges], 96, 96)

    piers = [build_fisher_pier_variant(i) for i in range(4)]
    pier_sheet = pack_row([p for p, _ in piers], 96, 96)
    pier_glow = pack_row([g for _, g in piers], 96, 96)

    boat_sheet = build_reed_rowboat()

    outputs = [
        ("old_watermill.png", mill_px, 160, 144),
        ("old_watermill_glow.png", mill_gl, 160, 144),
        ("watermill_wheel.png", wheel_sheet, 384, 72),
        ("watermill_jam.png", jam_sheet, 96, 48),
        ("broken_stone_bridge.png", bridge_sheet, 384, 96),
        ("broken_stone_bridge_glow.png", bridge_glow, 384, 96),
        ("fisher_pier.png", pier_sheet, 384, 96),
        ("fisher_pier_glow.png", pier_glow, 384, 96),
        ("reed_rowboat.png", boat_sheet, 128, 48),
    ]
    for name, px, ew, eh in outputs:
        assert (len(px[0]), len(px)) == (ew, eh), f"{name}: got {(len(px[0]), len(px))} != {(ew, eh)}"
        verify_no_black(name, px)
        write_png(props / name, ew, eh, px)

    render_qa_sheet(mill_px, mill_gl, wheel_sheet, jam_sheet, bridges, piers, boat_sheet)
    print("Wrote 9 Water POI PNGs and docs/img/water_pois_sheet.png")


if __name__ == "__main__":
    main()
