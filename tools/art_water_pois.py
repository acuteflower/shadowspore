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


# Warm weathered plaster, roof shingle variation & brass hardware accents
WARM_PLASTER = [hexc(c) for c in ("4b4358", "695f78", "827790", "9b90a8", "b5aac2", "cfc6da", "e6e0ee")]
WARM_ROOF = [hexc(c) for c in ("1e1d2e", "2b2a3e", "383850", "464762", "565876", "686b8a", "8488a6", "a6aac6")]
BRASS = [hexc(c) for c in ("4e3618", "7c5824", "b48636", "e6bc5c", "fff0a8")]


def _draw_grained_beam(px, x0: float, y0: float, x1: float, y1: float, half_w: float, seed: int, peg_ends: bool = False):
    """Draws a hand-hewn oak half-timber beam with longitudinal wood grain, top-left chamfer & optional wooden pegs."""
    dx_t, dy_t = x1 - x0, y1 - y0
    length = max(1.0, math.hypot(dx_t, dy_t))
    ux, uy = dx_t / length, dy_t / length
    nx, ny = -uy, ux  # Cross-beam normal
    steps = max(1, int(length * 2.4))
    ir = int(math.ceil(half_w + 0.6))
    for i in range(steps + 1):
        t = i / float(steps)
        cx, cy = x0 + dx_t * t, y0 + dy_t * t
        ix, iy = int(round(cx)), int(round(cy))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                px_x, py_y = ix + dx, iy + dy
                cross = (px_x - cx) * nx + (py_y - cy) * ny
                if abs(cross) > half_w + 0.18:
                    continue
                along = (px_x - x0) * ux + (py_y - y0) * uy
                # Top-left lighting across beam cross-section + elongated longitudinal oak grain
                lit_dir = -0.62 * (px_x - cx) / max(0.8, half_w) - 0.72 * (py_y - cy) / max(0.8, half_w)
                grain = (vnoise(along * 0.24, cross * 1.35, seed + 13) - 0.5) * 1.25
                idx = int(clamp(round(3.8 + lit_dir * 1.65 + grain), 1, 6))
                if abs(cross) >= half_w - 0.38:
                    idx = 6 if (px_x - cx + py_y - cy) < -0.15 else 1
                put(px, px_x, py_y, TIMBER[idx])
    if peg_ends:
        for t_p in (0.10, 0.90):
            px_p = int(round(x0 + dx_t * t_p))
            py_p = int(round(y0 + dy_t * t_p))
            put(px, px_p, py_p, TIMBER[7])
            put(px, px_p + 1, py_p + 1, TIMBER[1])


# ==============================================================================
# 1. Old Watermill (`old_watermill.png` & `_glow.png`, 160x144, anchor (80, 128))
# ==============================================================================
def build_old_watermill():
    W, H = 160, 144
    FX, FY = 80, 128
    seed = 2101
    rng = random.Random(seed)
    body = blank(W, H)
    under_skirt = blank(W, H)
    over_flora = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Weathered Coursed-Stone Chimney on left roof slope (`x = 42..54, y = 8..43`)
    chim_courses = [(12, 15), (16, 19), (20, 23), (24, 28), (29, 33), (34, 38), (39, 43)]
    for ci, (cy0, cy1) in enumerate(chim_courses):
        split_x = 48 + (1 if ci % 2 else -1)
        _draw_stone_block(body, 43, cy0, split_x, cy1, 5.2 - ci * 0.08, seed + ci * 11, warm=(ci % 3 == 1))
        _draw_stone_block(body, split_x + 1, cy0, 53, cy1, 3.6 - ci * 0.08, seed + ci * 11 + 5, warm=(ci % 3 == 2))
    # Terracotta/dark-stone flue pot (`y = 7..9`) + overhanging corbelled chimney cap (`y = 9..11`) with soot & moss
    for x in range(46, 51):
        put(body, x, 7, RUST[2 if x < 48 else 0])
        put(body, x, 8, STONE[0] if 47 <= x <= 49 else RUST[1])
    _draw_stone_block(body, 41, 9, 55, 11, 5.6, seed + 91, warm=True, mortar_r=False, mortar_b=False)
    drape_moss(body, 42, 51, 9, 2, 2, seed + 2)

    # 2) Lower Masonry Storey (`y = 91..128, x = 35..124`): Fitted Irregular Polygonal Fieldstones + Corner Quoins!
    # Generate Voronoi fieldstone sites across `x = 34..126, y = 90..130`
    m_sites = []
    ms_id = 0
    for ry_b in (93.0, 98.2, 103.6, 109.2, 114.8, 120.4, 125.8):
        xc = 36.0 + (rng.uniform(2.2, 4.8) if int(ry_b) % 2 else 0.0)
        while xc < 125.0:
            step = rng.uniform(5.8, 9.6)
            sx = xc + step * 0.5 + rng.uniform(-0.7, 0.7)
            sy = ry_b + rng.uniform(-1.1, 1.1)
            m_sites.append((sx, sy, ms_id, hsh(ms_id, 1, seed + 15) < 0.33, (hsh(ms_id, 2, seed + 17) - 0.5) * 1.15))
            ms_id += 1
            xc += step

    for y in range(91, FY + 1):
        for x in range(35, 125):
            wx = x + 0.5 + (vnoise(x * 0.30, y * 0.30, seed + 21) - 0.5) * 1.0
            wy = y + 0.5 + (vnoise(x * 0.30, y * 0.30, seed + 23) - 0.5) * 1.0
            d1, d2 = 1e9, 1e9
            s1, s2 = m_sites[0], m_sites[0]
            for st in m_sites:
                dd = math.hypot((wx - st[0]) * 0.88, (wy - st[1]) * 1.14)
                if dd < d1:
                    d2, d1 = d1, dd
                    s2, s1 = s1, st
                elif dd < d2:
                    d2 = dd
            gap = d2 - d1
            side_recede = (x >= 114)
            wet_zone = (x >= 105 and y >= 106) or (y >= 125 and x >= 98)
            if gap < 0.58:
                # Mossy mortar pockets near damp base & wheel raceway!
                if (wet_zone or y >= 121) and vnoise(x * 0.42, y * 0.42, seed + 27) > 0.48:
                    put(body, x, y, MOSS[2 if side_recede else 3])
                else:
                    put(body, x, y, MORTAR)
            else:
                vx, vy = s1[0] - s2[0], s1[1] - s2[1]
                vl = max(0.001, math.hypot(vx, vy))
                b_dot = (vx / vl) * 0.65 + (vy / vl) * 0.76
                bevel = (0.95 if b_dot > 0.28 else (-0.65 if b_dot < -0.28 else 0.0)) if gap < 1.45 else 0.0
                cl = (vnoise(x * 0.36, y * 0.48, seed + 31) - 0.5) * 0.9
                # Dark jetty overhang shadow at top of masonry (`y = 93..94`)
                j_sh = -1.35 if y <= 94 else (-0.55 if y == 95 else 0.0)
                if wet_zone:
                    idx_w = int(clamp(round((2.1 + s1[4] * 0.6 + bevel * 0.7 + cl + j_sh * 0.5) - (0.6 if side_recede else 0.0)), 0, 3))
                    col_m = MOSS[1] if (y >= 118 and x >= 111 and hsh(s1[2], y // 2, seed + 35) < 0.28) else WET_STONE[idx_w]
                else:
                    pal_m = BRIDGE_WARM_STONE if s1[3] else STONE
                    lit_m = (2.8 if side_recede else (4.4 - 0.55 * ((x - 35) / 80.0))) + s1[4] + bevel + cl + j_sh
                    # Occasional hairline stone crack
                    if s1[2] % 6 == 0 and abs((x - s1[0]) * 0.7 + (y - s1[1])) < 0.45:
                        lit_m -= 1.6
                    col_m = pal_m[int(clamp(round(lit_m), 1, 7))]
                put(body, x, y, col_m)

    # Dressed alternating stone corner quoins on left (`x = 35..41`) & front-right corner (`x = 111..116`)
    for qi, qy0 in enumerate(range(93, FY - 2, 5)):
        qy1 = min(FY - 1, qy0 + 4)
        lw_q = 6 if qi % 2 == 0 else 4
        rw_q = 4 if qi % 2 == 0 else 6
        _draw_stone_block(body, 35, qy0, 35 + lw_q, qy1, 5.2 if qy0 > 94 else 3.8, seed + 200 + qi, warm=(qi % 2 == 1))
        _draw_stone_block(body, 114 - rw_q, qy0, 114, qy1, 3.8 if qy0 > 94 else 2.8, seed + 220 + qi, warm=(qi % 3 == 0))

    # 3) Upper Storey & Gable Peak (`y = 16..92`): Mottled Wattle-and-Daub Plaster + Grained Oak Half-Timbering!
    for y in range(16, 89):
        if y < 58:
            span = (y - 15) / 43.0 * 38.0
            x0, x1 = int(round(68.0 - span)), int(round(68.0 + span))
        else:
            x0, x1 = 34, 122
        for x in range(x0, x1 + 1):
            side_wall = (x > 113 and y >= 58)
            rel_x = (x - 68.0) / 44.0
            # Mottled warm/cool plaster clusters + damp eave shadow staining under roof verges & jetty!
            mottle = vnoise(x * 0.22, y * 0.22, seed + 41)
            fine = (vnoise(x * 0.55, y * 0.45, seed + 43) - 0.5) * 0.75
            eave_stain = 0.0
            if y < 58:
                dist_verge = min(abs(x - x0), abs(x - x1))
                if dist_verge < 4:
                    eave_stain = -0.22 * (1.0 - dist_verge / 4.0)
            elif 58 <= y <= 62:
                eave_stain = -0.18 * (1.0 - (y - 58) / 4.0)
            lit = (0.32 if side_wall else (0.64 - 0.18 * rel_x - 0.06 * ((y - 50) / 40.0))) + eave_stain
            pal_pl = WARM_PLASTER if mottle > 0.48 else PLASTER
            idx_pl = int(clamp(round(lit * 6.2 + (mottle - 0.5) * 0.9 + fine), 0, len(pal_pl) - 1))
            col_pl = pal_pl[idx_pl]

            # Fine weathered plaster hairline cracks (`(81..86, 66..73)` & `(60..64, 29..35)`)
            if (66 <= y <= 72 and x == 82 + (y - 66) // 2) or (29 <= y <= 35 and x == 61 + (y - 29) // 3):
                col_pl = PLASTER[1]
            put(body, x, y, col_pl)

    # Small weathered plaster-peel patch at `(99..106, 78..83)` exposing horizontal wooden wattle laths!
    for py_l in range(78, 84):
        for px_l in range(99, 107):
            if ((px_l - 102.5) / 4.2) ** 2 + ((py_l - 80.5) / 3.0) ** 2 <= 1.0:
                if py_l % 2 == 0:
                    put(body, px_l, py_l, TIMBER[4 if px_l < 103 else 3])  # Exposed horizontal wooden lath
                else:
                    put(body, px_l, py_l, TIMBER[0])  # Dark daub gap between laths
            elif ((px_l - 102.5) / 5.0) ** 2 + ((py_l - 80.5) / 3.6) ** 2 <= 1.0:
                put(body, px_l, py_l, WARM_PLASTER[6 if (px_l + py_l) < 183 else 1])  # Broken plaster rim bevel

    # Grained Oak Half-Timbering Frame + Wooden Corner Pegs (Treenails) + Carved Jetty Bressummer & Corbels!
    # Diagonal wind-braces first, then main posts & rails so mortise joints overlap cleanly
    _draw_grained_beam(body, 36, 88, 56, 59, 1.15, seed + 74, peg_ends=True)
    _draw_grained_beam(body, 96, 59, 112, 88, 1.15, seed + 75, peg_ends=True)
    _draw_grained_beam(body, 52, 57, 67, 39, 1.05, seed + 170, peg_ends=True)
    _draw_grained_beam(body, 84, 57, 69, 39, 1.05, seed + 171, peg_ends=True)

    for vx, yt_p in [(35, 58), (57, 42), (68, 18), (80, 42), (96, 58), (113, 58), (121, 58)]:
        _draw_grained_beam(body, vx, yt_p, vx, 88, 1.35, seed + vx, peg_ends=True)
    _draw_grained_beam(body, 34, 58, 121, 58, 1.45, seed + 71, peg_ends=True)
    _draw_grained_beam(body, 51, 38, 85, 38, 1.2, seed + 169, peg_ends=True)
    _draw_grained_beam(body, 35, 75, 113, 75, 1.15, seed + 73, peg_ends=True)

    # Heavy overhanging jetty bressummer beam (`y = 89..92, x = 33..124`) + sculpted curved oak corbel brackets!
    for y in range(89, 93):
        for x in range(33, 125):
            g_b = (vnoise(x * 0.25, y * 1.2, seed + 81) - 0.5) * 1.1
            base_t = 6.2 if y == 89 else (1.2 if y == 92 else (4.4 if x < 113 else 2.6))
            put(body, x, y, TIMBER[int(clamp(round(base_t + g_b), 0, 7))])
    for bx_c in (36, 57, 68, 96, 113):
        put(body, bx_c, 90, TIMBER[7])  # Treenail pegs along bressummer
        for dy in range(1, 6):
            w_cb = 3 if dy <= 2 else (2 if dy <= 4 else 1)
            for dx in range(w_cb):
                put(body, bx_c - 1 + dx, 92 + dy, TIMBER[5 if dx == 0 else (3 if dx == 1 else 1)])

    # 4) Steep Staggered Wood/Slate Shingle Gable Roof (`y = 12..61`) + Decorative Carved Bargeboards!
    for y in range(12, 62):
        t_r = max(0.0, (y - 13) / 48.0)
        flare = 3.8 * max(0.0, (t_r - 0.65) / 0.35) ** 1.6
        lx_out = int(round(68.0 - t_r * 40.0 - flare))
        rx_front = int(round(68.0 + t_r * 40.0 + flare))
        rx_back = int(round(101.0 + t_r * 28.0 + flare * 0.7))

        sh_course = max(0, (y - 14) // 4)
        sh_row = (y - 14) % 4
        # Individual staggered shingle widths (`4..7 px` per shingle via deterministic cell hash)
        for x in range(rx_front - 1, min(W - 4, rx_back + 1)):
            if y <= 14:
                # Carved weathered oak ridge-beam with peg cresting!
                put(body, x, y, TIMBER[6 if y == 12 else (5 if x % 5 != 0 else 2)])
                continue
            # Variable-width staggered shingle index
            x_shift = x + (3 if sh_course % 2 else 0) + int(hsh(0, sh_course, seed + 173) * 4.0)
            sh_id = x_shift // 5
            seam_x = (x_shift % 5 == 0)
            slipped = (hsh(sh_id, sh_course, seed + 175) < 0.14)
            warm_sh = (hsh(sh_id, sh_course, seed + 176) < 0.32)
            pal_r = WARM_ROOF if warm_sh else ROOF
            sh_bias = (hsh(sh_id, sh_course, seed + 177) - 0.5) * 1.1

            if (sh_row == 3 and not slipped) or (slipped and sh_row == 0):
                lit_i = 1.3  # Crisp dark shingle overlap step shadow
            elif seam_x and sh_row < 3:
                lit_i = 1.6  # Vertical gap between individual shingles
            elif sh_row == 0 or (x_shift % 5 == 1):
                lit_i = 5.4 + sh_bias - 1.1 * ((x - rx_front) / 34.0)  # Sunlit top-left shingle bevel
            else:
                cl_r = (vnoise(x * 0.45, y * 0.65, seed + 178) - 0.5) * 0.8
                lit_i = 3.9 + sh_bias + cl_r - 1.1 * ((x - rx_front) / 34.0)
            # Occasional pale sage roof lichen fleck
            if sh_row == 1 and not seam_x and hsh(sh_id * 7 + x, sh_course, seed + 179) < 0.035:
                put(body, x, y, BRIDGE_LICHEN[1 if x < 105 else 0])
            else:
                put(body, x, y, pal_r[int(clamp(round(lit_i), 0, 7))])

        # Exposed wooden rafter tails along right eaves (`y = 57..61`)
        if 57 <= y <= 61:
            for rt_x in range(rx_front + 4, rx_back - 1, 6):
                put(body, rt_x, y + 1, TIMBER[4])
                put(body, rt_x + 1, y + 1, TIMBER[1])

        # Thick sculpted front gable roof verges + carved wooden bargeboards with scalloped under-trim!
        if y >= 13:
            band_w = 6
            for x in range(lx_out, lx_out + band_w + 1):
                put(body, x, y, ROOF[7 if x <= lx_out + 1 else (5 if (y + x) % 4 != 0 else 3)])
            for x in range(lx_out + band_w + 1, lx_out + band_w + 3):
                put(body, x, y, TIMBER[5 if x == lx_out + band_w + 1 else 2])
            if y % 4 == 0:
                put(body, lx_out + band_w + 3, y, TIMBER[1])  # Scalloped bargeboard tooth + eave shadow

            for x in range(rx_front - band_w, rx_front + 1):
                put(body, x, y, ROOF[6 if x == rx_front - band_w else (4 if (y + x) % 4 != 0 else 2)])
            for x in range(rx_front - band_w - 2, rx_front - band_w):
                put(body, x, y, TIMBER[4 if x == rx_front - band_w - 2 else 1])

    # Re-stamp upper part of stone chimney (`x = 41..55, y = 7..34`) rising cleanly through left roof slope!
    for ci, (cy0, cy1) in enumerate(chim_courses[:5]):
        split_x = 48 + (1 if ci % 2 else -1)
        _draw_stone_block(body, 43, cy0, split_x, cy1, 5.2 - ci * 0.08, seed + ci * 11, warm=(ci % 3 == 1))
        _draw_stone_block(body, split_x + 1, cy0, 53, cy1, 3.6 - ci * 0.08, seed + ci * 11 + 5, warm=(ci % 3 == 2))
    for x in range(46, 51):
        put(body, x, 7, RUST[2 if x < 48 else 0])
        put(body, x, 8, STONE[0] if 47 <= x <= 49 else RUST[1])
    _draw_stone_block(body, 41, 9, 55, 11, 5.6, seed + 91, warm=True, mortar_r=False, mortar_b=False)
    drape_moss(body, 42, 51, 9, 2, 2, seed + 2)
    # Lead/mortar roof flashing collar at chimney base
    for x in range(42, 54):
        fy_fl = int(round(13 + (68 - x) * (48.0 / 40.0))) - 6
        if 26 <= fy_fl <= 36:
            put(body, x, fy_fl, IRON[2])

    # Carved wooden finial post at gable apex `(68, 7..16)` + lush roof moss cushions!
    for y in range(7, 17):
        put(body, 68, y, TIMBER[7 if y < 10 else (5 if y < 14 else 3)])
        if y in (9, 13):
            put(body, 67, y, TIMBER[6])
            put(body, 69, y, TIMBER[2])
    for mx0, mx1, my0 in [(71, 86, 15), (84, 99, 25), (95, 112, 38), (103, 124, 52), (32, 42, 48), (54, 63, 24)]:
        drape_moss(body, mx0, mx1, my0, 2, 3, seed + mx0 + my0)

    # 5) Arched Grained-Oak Mill Door (`x = 70..90, y = 96..126`) with Radiating Stone Voussoirs & Keystone!
    dcx, dcy = 80, 106
    for y in range(94, FY):
        for x in range(66, 95):
            dx_d = (x - dcx) / 10.5
            dy_d = (y - dcy) / 9.8
            r_d = math.hypot(dx_d, dy_d)
            in_door = (y <= dcy and r_d <= 0.76) or (y > dcy and abs(dx_d) <= 0.76)
            in_recess = (y <= dcy and r_d <= 0.86) or (y > dcy and abs(dx_d) <= 0.84)
            in_arch = (y <= dcy and r_d <= 1.24) or (y > dcy and abs(dx_d) <= 1.12)
            if in_door:
                plank_seam = ((x - 72) % 4 == 0)
                if plank_seam:
                    col_d = TIMBER[0]
                elif y in (108, 120) and 72 <= x <= 84:
                    # Forged iron strap hinges with rivets & scrolled fleur tip!
                    col_d = IRON[4 if (x - 73) % 3 == 0 else (3 if y == 108 else 2)]
                elif x == 84 and y in (107, 109, 119, 121):
                    col_d = IRON[2]  # Scroll hinge tips
                else:
                    gr = (vnoise(x * 1.1, y * 0.22, seed + 185) - 0.5) * 1.15
                    col_d = TIMBER[int(clamp(round((4.8 if x < dcx else 3.4) + gr - (0.8 if y < 101 else 0.0)), 1, 6))]
                put(body, x, y, col_d)
            elif in_recess:
                put(body, x, y, STONE[0 if x <= dcx else 1])  # Deep 3D doorway reveal shadow
            elif in_arch:
                if y <= dcy + 1:
                    # True radial wedge-shaped arch voussoirs + carved warm keystone at top!
                    ang_a = math.atan2(max(0.01, dcy - y), x - dcx)
                    wf = (ang_a / math.pi) * 9.0
                    wid = int(wf)
                    fr_a = wf - wid
                    is_key = (wid == 4)
                    if abs(fr_a) < 0.12 or abs(1.0 - fr_a) < 0.12 or r_d > 1.17:
                        put(body, x, y, MORTAR)
                    else:
                        pal_v = BRIDGE_WARM_STONE if (is_key or wid % 3 == 1) else STONE
                        put(body, x, y, pal_v[6 if (is_key or x < dcx) else 4])
                else:
                    # Vertical jamb quoin blocks flanking door
                    j_course = (y - dcy) // 5
                    if (y - dcy) % 5 == 0:
                        put(body, x, y, MORTAR)
                    else:
                        pal_j = BRIDGE_WARM_STONE if j_course % 2 == 1 else STONE
                        put(body, x, y, pal_j[6 if x < dcx else 4])

    # Forged iron ring-pull & escutcheon plate at `(86, 113..115)` + worn flagstone threshold step (`x = 66..94, y = 125..128`)
    put(body, 86, 112, IRON[3])
    put(body, 85, 113, IRON[4])
    put(body, 87, 113, IRON[2])
    put(body, 86, 114, IRON[3])
    put(body, 86, 115, TIMBER[0])
    for x in range(66, 95):
        joint_t = x in (73, 81, 88)
        put(body, x, 125, MORTAR if joint_t else BRIDGE_WARM_STONE[7 if 74 <= x <= 86 else 6])
        put(body, x, 126, MORTAR if joint_t else STONE[5 if x < 84 else 4])
        put(body, x, 127, STONE[3 if x < 84 else 2])
        put(body, x, 128, STONE[1])

    # 6) Diamond-Mullioned Windows with Carved Sills & Open Wooden Shutters + Hanging Door Lantern!
    def draw_detailed_window(wx0: int, wy0: int, wx1: int, wy1: int, with_shutters: bool):
        # Carved wooden head-lintel & projecting corbelled sill
        for x in range(wx0 - 2, wx1 + 3):
            put(body, x, wy0 - 2, TIMBER[6])
            put(body, x, wy0 - 1, TIMBER[3])
            put(body, x, wy1 + 1, TIMBER[6])
            put(body, x, wy1 + 2, TIMBER[2])
        for x in (wx0 - 1, wx1 + 1):
            for y in range(wy0, wy1 + 1):
                put(body, x, y, TIMBER[4 if x == wx0 - 1 else 2])
        if with_shutters:
            # Weathered open plank shutters with iron hinge straps flanking the window!
            for side_s, sx0 in ((-1, wx0 - 6), (1, wx1 + 2)):
                for sy in range(wy0, wy1 + 1):
                    for sdx in range(4):
                        xx_s = sx0 + sdx
                        if sy in (wy0 + 2, wy1 - 2):
                            put(body, xx_s, sy, IRON[3 if side_s < 0 else 2])
                        elif sdx == 2:
                            put(body, xx_s, sy, TIMBER[1])
                        else:
                            put(body, xx_s, sy, TIMBER[5 if side_s < 0 else 3])
        # Warm glowing amber glass with central cross-mullion & delicate diamond lattice leadwork!
        mx_w, my_w = (wx0 + wx1) // 2, (wy0 + wy1) // 2
        for y in range(wy0, wy1 + 1):
            for x in range(wx0, wx1 + 1):
                if x == mx_w or y == my_w:
                    put(body, x, y, TIMBER[1])
                elif (x - wx0 + y - wy0) % 4 == 0 and (x + y) % 2 == 0:
                    glow.emit(body, x, y, AMBER_D, AMBER_M, halo=1)  # Subtle diamond lead glint
                else:
                    is_hot = (x <= mx_w and y <= my_w)
                    glow.emit(body, x, y, AMBER_H if is_hot else AMBER_M, AMBER_H if is_hot else AMBER_M, halo=2 if is_hot else 1)

    draw_detailed_window(63, 41, 73, 51, with_shutters=False)
    draw_detailed_window(45, 62, 55, 72, with_shutters=True)

    # Branching climbing ivy vines creeping up the left stone quoin & lower plaster (`x = 35..44, y = 78..126`)!
    for k in range(46):
        vy = 125 - k
        vx = 37 + int(round(2.4 * math.sin(k * 0.24) + (k * 0.08)))
        put(body, vx, vy, BRIDGE_IVY[3 if k % 3 != 0 else 4])
        put(body, vx + 1, vy, BRIDGE_IVY[1])
        if k % 3 == 1:
            leaf_dx = -2 if (k // 3) % 2 == 0 else 2
            put(body, vx + leaf_dx, vy, BRIDGE_IVY[4 if leaf_dx < 0 else 2])
            put(body, vx + (leaf_dx // 2), vy - 1, BRIDGE_IVY[3])

    # Cozy wrought-iron door lantern on scrolled iron wall-bracket at `(96, 100)`
    for bx_l in range(92, 98):
        put(body, bx_l, 96, IRON[4 if bx_l < 96 else 3])
    put(body, 93, 97, IRON[2])
    put(body, 94, 98, IRON[1])
    put(body, 96, 97, IRON[3])
    for dx in (-2, -1, 0, 1, 2):
        put(body, 96 + dx, 98, IRON[4 if dx <= 0 else 2])
        put(body, 96 + dx, 103, IRON[1])
    put(body, 96, 97, IRON[4])
    for dy in (99, 100, 101, 102):
        put(body, 94, dy, IRON[3])
        put(body, 98, dy, IRON[1])
        glow.emit(body, 95, dy, AMBER_M, AMBER_H, halo=2)
        glow.emit(body, 96, dy, AMBER_H, AMBER_H, halo=2)
        glow.emit(body, 97, dy, AMBER_D, AMBER_M, halo=1)

    # 7) Radially-Furrowed Millstone & Burlap-Woven Tied Grain Sacks (`x = 18..50, y = 108..129`)
    mcx, mcy = 43, 119
    for dy in range(-9, 10):
        for dx in range(-9, 10):
            # 3/4 beveled stone thickness on right rim (`dx + 1.5`)
            r_back = math.hypot((dx - 1.4) * 1.08, dy)
            r = math.hypot(dx * 1.08, dy)
            if r <= 2.1:
                put(body, mcx + dx, mcy + dy, IRON[2] if abs(dx) >= 1.5 or abs(dy) >= 1.5 else STONE[0])  # Iron-bushed eye
            elif r <= 9.2:
                ang_m = math.atan2(dy, dx)
                # Tangential/radial millstone grinding harps (8 sectors)
                spoke_f = ((ang_m + math.pi) / math.tau) * 12.0 + r * 0.08
                is_furrow = (abs(spoke_f - round(spoke_f)) < 0.14 and 2.8 < r < 8.2)
                is_rim = (r > 8.1)
                lit = 5.4 - 1.8 * (dx / 9.0) - 1.8 * (dy / 9.0) + (0.8 if is_rim and (dx + dy < 0) else 0.0)
                pal_ms = BRIDGE_WARM_STONE
                put(body, mcx + dx, mcy + dy, pal_ms[2 if is_furrow else int(clamp(round(lit), 1, 7))])
            elif r_back <= 9.2 and dx > 0:
                put(body, mcx + dx, mcy + dy, STONE[1])  # 3D stone edge thickness

    # Two plump burlap flour/grain sacks with woven cross-hatch texture, side stitch & braided rope neck!
    for s_i, (scx, scy, srx, sry) in enumerate([(25, 121, 6.4, 7.2), (34, 123, 5.8, 6.2)]):
        for dy in range(-int(sry) - 3, int(sry) + 1):
            for dx in range(-int(srx), int(srx) + 1):
                if dy < -int(sry) + 1:
                    # Ruffled flared sack ears above rope tie!
                    ear_w = 1.6 + (-dy - int(sry) + 1) * 0.85
                    if abs(dx) <= ear_w:
                        put(body, scx + dx, scy + dy, SACK[5 if dx <= 0 else (3 if dx == 1 else 2)])
                    continue
                if dy == -int(sry) + 1 and abs(dx) <= 3.2:
                    # Cinched braided hemp rope neck tie
                    put(body, scx + dx, scy + dy, ROPE[4 if dx < 0 else (3 if dx == 0 else 1)])
                    continue
                # Plump bottom-heavy pear-shaped sack profile
                w_bulge = srx * (1.0 + 0.14 * math.sin((dy / sry) * 1.8))
                d = (dx / w_bulge) ** 2 + (dy / sry) ** 2
                if d <= 1.0:
                    lit = 3.4 - 1.55 * (dx / w_bulge) - 1.15 * (dy / sry)
                    # Crisp woven burlap cross-hatch weave + stitched side seam
                    weave = 0.42 if ((dx + dy) % 2 == 0 and dx % 3 != 0) else -0.28
                    if abs(dx - w_bulge * 0.45) < 0.55 and dy % 2 == 0:
                        col_s = ROPE[1]  # Stitched burlap side seam
                    else:
                        col_s = SACK[int(clamp(round(lit + weave), 0, 5))]
                    put(body, scx + dx, scy + dy, col_s)

    # 8) Sturdy Timber Axle Housing (`axle journal at (124, 98)`) & Iron-Banded Wooden Headrace Flume (`y = 65..73`)!
    for y in range(65, 73):
        for x in range(116, 145):
            if y == 65:
                put(body, x, y, WATER_DROP[3 if (x % 4 == 0) else 2])  # Churning bright headrace crest
            elif y == 66:
                put(body, x, y, WATER_DROP[1 if (x % 3 == 0) else 2])
            elif y == 67:
                put(body, x, y, TIMBER[6])
            elif y == 72:
                put(body, x, y, TIMBER[0])
            elif x in (122, 132, 141):
                put(body, x, y, IRON[3 if y < 70 else 1])  # Iron flume tie-straps
            else:
                gr_f = (vnoise(x * 0.28, y * 1.2, seed + 190) - 0.5) * 0.9
                put(body, x, y, TIMBER[int(clamp(round((4.2 if x < 133 else 3.4) + gr_f), 1, 6))])
    # Cascading water stream pouring from flume spout (`x = 138..144, y = 72..78`) onto the wheel!
    for wy_s in range(72, 79):
        put(body, 142 + (wy_s - 72) // 3, wy_s, WATER_DROP[3 if wy_s < 76 else 2])
        put(body, 143 + (wy_s - 72) // 3, wy_s, WATER_DROP[2 if wy_s % 2 == 0 else 1])
    _draw_grained_beam(body, 118, 86, 136, 72, 1.35, seed + 88, peg_ends=True)
    _draw_grained_beam(body, 125, 92, 125, 73, 1.15, seed + 89, peg_ends=False)

    # Heavy mortised timber pillow-block & bolted cast-iron axle collar centered at `(124, 98)`!
    for y in range(92, 106):
        for x in range(116, 131):
            if y in (92, 105) or x == 130:
                put(body, x, y, TIMBER[1 if y == 105 else 6])
            elif x in (117, 129) and y in (94, 103):
                put(body, x, y, IRON[4])  # Corner mounting bolts
            else:
                put(body, x, y, TIMBER[4 if y < 98 else 2])
    for dy in range(-5, 6):
        for dx in range(-5, 6):
            r = math.hypot(dx, dy)
            if r <= 2.2:
                put(body, 124 + dx, 98 + dy, TIMBER[6 if dx <= 0 and dy <= 0 else 2])
            elif r <= 4.4:
                is_bolt = (abs(dx) == 3 and abs(dy) == 2) or (abs(dx) == 2 and abs(dy) == 3)
                put(body, 124 + dx, 98 + dy, IRON[4 if (is_bolt or (dx < 0 and dy < 0)) else (2 if dx + dy <= 1 else 0)])

    # 9) Feathered Packed-Earth, Threshold Pebble & Meadow Grass-Tuft Foundation Skirt (`y = 124..134`, outside `outline_pass`!)
    for y in range(124, 136):
        for x in range(15, 127):
            # Elliptical/warped foundation apron under sacks, mill wall, doorway & right raceway
            dx_ap = (x - 71.0) / 55.0
            dy_ap = (y - 128.0) / 6.0
            n_ap = vnoise(x * 0.38, y * 0.42, seed + 241)
            d_ap = math.hypot(dx_ap, dy_ap) - (n_ap - 0.5) * 0.18
            if d_ap >= 1.0:
                continue
            alpha = 255 if d_ap < 0.58 else (180 if d_ap < 0.80 else 98)
            if x >= 112:
                # Wet raceway splash & cool water reflection under right wheel wall!
                _blend_under(under_skirt, x, y, (*BRIDGE_WATER_SH_RGB, min(140, alpha)))
                if 128 <= y <= 130 and (x + y) % 3 == 0:
                    _blend_under(over_flora, x, y, (*BRIDGE_AQUA_HI_RGB, 115))
            else:
                is_door_path = (64 <= x <= 96)
                if is_door_path and d_ap < 0.82:
                    # Sunken doorway gravel & path cobbles
                    peb = ((x // 4 + y // 3) % 3 == 0 and x % 4 != 0 and y % 3 != 0)
                    col_a = STONE[4 if n_ap > 0.5 else 3] if peb else BRIDGE_EARTH[int(clamp(1.8 + n_ap * 2.8, 1, 4))]
                else:
                    col_a = BRIDGE_TURF[int(clamp(1.0 + n_ap * 3.2, 0, 4))] if d_ap > 0.62 else BRIDGE_EARTH[int(clamp(1.2 + n_ap * 2.6, 0, 3))]
                under_skirt[y][x] = (*col_a[:3], alpha)

    # Outline structural building body ONLY (suppress flat bottom `OUT` line along grounded foundation `y >= 129`)
    framed = outline_pass(body, OUT)
    for y in range(129, H):
        for x in range(18, 128):
            if body[y][x][3] == 0 and framed[y][x] == OUT:
                framed[y][x] = CLEAR

    # Lush meadow grass tufts, clover & raceway reeds overlapping foundation toes!
    for gx, gy, big in [
        (19, 127, False), (28, 129, True), (39, 129, True), (50, 128, False), (60, 128, True),
        (98, 128, True), (107, 128, False), (115, 128, True),
    ]:
        _draw_grass_tuft(over_flora, gx, gy, seed + gx * 5, big=big)
    # Tiny meadow buttercup dots beside sacks & doorway
    put(over_flora, 58, 126, AMBER_H)
    put(over_flora, 59, 127, AMBER_M)
    put(over_flora, 100, 126, AMBER_H)

    out = [row[:] for row in under_skirt]
    alpha_over(out, framed, 0, 0)
    alpha_over(out, over_flora, 0, 0)
    return out, glow.finish()


# ==============================================================================
# 2. Watermill Wheel (`watermill_wheel.png`, 6 cols x 1 row of 64x72, hub at (32, 36))
# ==============================================================================
def build_watermill_wheel():
    FW, FH = 64, 72
    CX, CY = 32, 36
    # 8 radial spokes (`45 deg` spacing) & 16 angled wooden bucket paddles (`22.5 deg` spacing):
    # Advancing `7.5 deg` per frame across 6 frames = `45.0 deg` = exact 1-spoke & 2-paddle period (100% seamless loop!)
    N_SPOKES = 8
    N_PADDLES = 16
    STEP_DEG = 7.5

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

        # 1) Back 3/4 oak shroud rim, inner tie-ring & 8 back spokes in cool river shadow
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            bx, by = rim_pt(th, 0.93, back=True)
            for s in range(26):
                t = s / 25.0
                px_x = int(round((CX + DEPTH_DX) * (1 - t) + bx * t))
                py_y = int(round((CY + DEPTH_DY) * (1 - t) + by * t))
                put(body, px_x, py_y, TIMBER[2 if t < 0.5 else 1])
                put(body, px_x + 1, py_y, TIMBER[0])

        for deg in range(360):
            th = math.radians(deg)
            for rs in (0.84, 0.89, 0.95, 1.0):
                bx, by = rim_pt(th, rs, back=True)
                put(body, int(round(bx)), int(round(by)), TIMBER[2 if (math.sin(th) < -0.2 and rs < 0.96) else 1])

        # 2) 16 Angled Wooden Bucket Paddles with oak grain, iron corner brackets & wet river-moss sheen!
        paddle_order = sorted(range(N_PADDLES), key=lambda k: math.sin(ang0 + k * (math.tau / N_PADDLES)))
        for k_p in paddle_order:
            th = ang0 + k_p * (math.tau / N_PADDLES)
            # Bucket canted slightly forward (`th - 0.08` inner -> `th + 0.05` outer) like real millwheel floats!
            fx0, fy0 = rim_pt(th - 0.06, 0.85, back=False)
            fx1, fy1 = rim_pt(th + 0.04, 1.07, back=False)
            bx1, by1 = rim_pt(th + 0.04, 1.07, back=True)
            bx0, by0 = rim_pt(th - 0.06, 0.85, back=True)
            lit_p = 0.56 - 0.30 * math.sin(th) - 0.18 * math.cos(th)
            # Period-2 moss variation (`k_p % 2`) repeats every 2 paddles = 45 deg -> 100% seamless across Frame 5 -> Frame 0!
            moss_slot = (k_p % 2 == 0)
            for u_i in range(9):
                u = u_i / 8.0
                ax = fx0 + (fx1 - fx0) * u
                ay = fy0 + (fy1 - fy0) * u
                zx = bx0 + (bx1 - bx0) * u
                zy = by0 + (by1 - by0) * u
                for v_i in range(12):
                    v = v_i / 11.0
                    xx = int(round(ax + (zx - ax) * v))
                    yy = int(round(ay + (zy - ay) * v))
                    if u_i == 8:
                        # Sunlit outer wooden bucket lip + wet sheen on rising/bottom paddles
                        col = WATER_DROP[1] if (0.3 < math.sin(th) and 0.25 < v < 0.75 and v_i % 3 == 0) else TIMBER[6 if math.sin(th) < 0 else 4]
                    elif v_i in (0, 11):
                        col = IRON[2] if u_i in (6, 7) else TIMBER[1]
                    else:
                        grain_v = 0.35 if (v_i % 3 == 1) else (-0.25 if v_i % 4 == 0 else 0.0)
                        if moss_slot and (0.22 <= v <= 0.68) and u_i in (4, 5, 6):
                            col = MOSS[3 if math.sin(th) < -0.2 else 2]
                        else:
                            col = TIMBER[int(clamp(round(lit_p * 6.4 + grain_v), 1, 5))]
                    put(body, xx, yy, col)

        # 3) Front Grained Dark-Oak Shroud Rim, 8 Radial Spokes & Wrought-Iron Strap Plates + Rivets!
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            fx, fy = rim_pt(th, 0.94, back=False)
            _draw_grained_beam(body, CX, CY, fx, fy, 1.25, 310, peg_ends=False)

        for deg in range(720):
            th = math.radians(deg * 0.5)
            lit_r = 0.64 - 0.28 * math.cos(th) - 0.34 * math.sin(th)
            # Check angular proximity to nearest spoke for wrought-iron rim strapping plates!
            rel_sp = ((th - ang0) % (math.tau / N_SPOKES)) / (math.tau / N_SPOKES)
            on_iron_strap = (rel_sp < 0.11 or rel_sp > 0.89)
            for rs_i, rs in enumerate((0.82, 0.87, 0.92, 0.98)):
                fx, fy = rim_pt(th, rs, back=False)
                ix, iy = int(round(fx)), int(round(fy))
                if rs_i in (0, 3):
                    col = TIMBER[1 if (rs_i == 3 and math.sin(th) > 0.15) else 5]
                elif on_iron_strap and rs_i == 2:
                    col = IRON[3 if math.sin(th) < 0 else 2]
                else:
                    grain_r = 0.4 if (deg // 6) % 3 == 0 else -0.2
                    col = TIMBER[int(clamp(round(lit_r * 6.8 + grain_r), 1, 6))]
                put(body, ix, iy, col)

        # Bright forged iron rivet heads & spoke tenon wedges at every spoke joint
        for i_s in range(N_SPOKES):
            th = ang0 + i_s * (math.tau / N_SPOKES)
            fx, fy = rim_pt(th, 0.90, back=False)
            put(body, int(round(fx)), int(round(fy)), IRON[4])
            fx2, fy2 = rim_pt(th + 0.06, 0.90, back=False)
            put(body, int(round(fx2)), int(round(fy2)), IRON[1])

        # 4) Heavy Bolted Cast-Iron & Oak Wheel Hub centered at `(32, 36)`
        for dy in range(-6, 7):
            for dx in range(-6, 8):
                d = ((dx - 0.8) / 5.5) ** 2 + (dy / 6.2) ** 2
                if d <= 0.18:
                    put(body, CX + dx, CY + dy, IRON[0])
                elif d <= 0.62:
                    bolt = (abs(dx - 1) == 2 and abs(dy) == 2)
                    put(body, CX + dx, CY + dy, IRON[4 if (bolt or (dx <= 0 and dy <= 0)) else (2 if dx + dy <= 1 else 1)])
                elif d <= 1.0:
                    put(body, CX + dx, CY + dy, TIMBER[6 if (dx < 0 and dy < 0) else (4 if dx <= 1 else 2)])

        # 5) Gleaming Turquoise-White Water Droplets, Falling Streams & Tailrace Froth (`100%` seamless 6-frame phase!)
        for k_p in range(N_PADDLES):
            th = (ang0 + k_p * (math.tau / N_PADDLES)) % math.tau
            # Falling right-side water (`0.15 .. 1.35`), bottom splash (`1.25 .. 2.05`), and rising wet left paddles (`2.05 .. 4.10`)
            if 0.25 <= th <= 4.10:
                bx, by = rim_pt(th, 1.08, back=False)
                ix, iy = int(round(bx)), int(round(by))
                put(body, ix, iy + 1, WATER_DROP[3])
                put(body, ix, iy + 2, WATER_DROP[2])
                if 1.15 <= th <= 3.45:
                    # Seamless phase using `th` (advances by `1/2` paddle spacing per 3 frames -> exact period at frame 6!)
                    phase_u = ((th / (math.tau / (N_PADDLES / 2))) * 1.0) % 1.0
                    drop_fall = int(phase_u * 4.0)
                    put(body, ix - 1, iy + 2 + drop_fall, WATER_DROP[3])
                    put(body, ix - 1, iy + 3 + drop_fall, WATER_DROP[2 if drop_fall < 2 else 1])
                if 1.30 <= th <= 1.95:
                    # Frothy tailrace splash arc at bottom of wheel!
                    put(body, ix + 2, min(FH - 3, iy + 2), WATER_DROP[3])
                    put(body, ix - 2, min(FH - 3, iy + 2), WATER_DROP[2])

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

    # Col 0 (Jammed): Gnarled bark-ridged driftwood limb with knot-holes, splintered forks, river-weed & 3D rusted chain!
    jam = blank(FW, FH)
    for i in range(52):
        t = i / 51.0
        cx = 5.5 + 36.5 * t
        cy = 33.0 - 17.5 * t + 2.5 * math.sin(t * 5.4)
        rad = 3.5 * (1.0 - 0.34 * t) + (0.65 if abs(t - 0.44) < 0.07 else 0.0)
        ix, iy = int(round(cx)), int(round(cy))
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                if dx * dx + dy * dy <= rad * rad:
                    # Splintered pale heartwood at broken ends (`t < 0.08` or `t > 0.92`)
                    if (t < 0.07 or t > 0.93) and (dx + dy) % 2 == 0:
                        put(jam, ix + dx, iy + dy, SACK[4 if dy <= 0 else 2])
                        continue
                    lit = 0.64 - 0.24 * dx - 0.30 * dy
                    # Longitudinal gnarled bark ridges
                    bark_ridge = -0.35 if ((ix + dx) + (iy + dy) * 2) % 4 == 0 else 0.15
                    put(jam, ix + dx, iy + dy, DRIFTWOOD[int(clamp(round((lit + bark_ridge) * 4.3), 0, 4))])

    # Dark hollow knot-hole on main trunk around `(21, 24)`
    put(jam, 21, 24, TIMBER[0])
    put(jam, 22, 24, DRIFTWOOD[0])
    put(jam, 20, 23, DRIFTWOOD[4])

    # Snagged secondary upper & lower gnarled forks (`(23, 24)->(37, 34)` & `(14, 29)->(9, 20)`)
    for x0_f, y0_f, x1_f, y1_f in [(23.0, 24.0, 37.0, 34.5), (15.0, 28.0, 9.5, 19.5)]:
        for i in range(24):
            t = i / 23.0
            ix = int(round(x0_f + (x1_f - x0_f) * t))
            iy = int(round(y0_f + (y1_f - y0_f) * t + 1.1 * math.sin(t * 4.2)))
            r_f = 1.6 * (1.0 - 0.4 * t)
            for dy in (-2, -1, 0, 1, 2):
                for dx in (-2, -1, 0, 1, 2):
                    if dx * dx + dy * dy <= r_f * r_f + 0.2:
                        put(jam, ix + dx, iy + dy, DRIFTWOOD[4 if (dx + dy < 0) else (2 if dy <= 0 else 1)])

    # Dripping layered river-weed & wet moss strands draped across the snagged log (`x = 12..35, y = 18..40`)
    for wx in range(12, 36, 2):
        wy0 = int(round(30 - (wx - 11) * 0.44))
        w_len = 5 + (wx * 5) % 7
        for k in range(w_len):
            sw = int(round(0.8 * math.sin(k * 0.7 + wx)))
            put(jam, wx + sw, wy0 + k, MOSS[5 if k == 0 else (3 if k < 3 else (2 if k < w_len - 2 else 0))])
            if k == w_len - 1 and wx % 4 == 0:
                put(jam, wx + sw, wy0 + k + 1, WATER_DROP[2])  # Dripping water bead!

    # Individually resolved 3D interlocking rusted iron chain links (`x = 18..31, y = 15..35`)
    chain_pts = [(18, 16), (19, 18), (21, 21), (22, 23), (24, 26), (25, 28), (27, 31), (29, 34)]
    for li, (cx_l, cy_l) in enumerate(chain_pts):
        if li % 2 == 0:
            # Open oval link seen flat (hollow dark center + rusted/iron rim)
            for dx, dy in [(-2, 0), (-1, -1), (0, -1), (1, -1), (2, 0), (1, 1), (0, 1), (-1, 1)]:
                put(jam, cx_l + dx, cy_l + dy, RUST[3 if (dx + dy < 0) else 1])
            put(jam, cx_l, cy_l, TIMBER[0])
            put(jam, cx_l - 1, cy_l - 1, IRON[4])  # Metallic edge glint
        else:
            # Edge-on connecting link bar
            for k_b in (-1, 0, 1):
                put(jam, cx_l + k_b, cy_l + k_b, IRON[3 if k_b <= 0 else 1])
                put(jam, cx_l + k_b + 1, cy_l + k_b, RUST[0])

    jam_out = outline_pass(jam, OUT)

    # Col 1 (Cleared remnant): Chiseled faceted wet mossy river stones + tiny water-lap ripple beside race (`cx = 24, cy = 34`)
    clr = blank(FW, FH)
    _draw_stone_block(clr, 19, 32, 27, 36, 4.8, 405, wet=True, mortar_r=False, mortar_b=False)
    _draw_stone_block(clr, 26, 34, 30, 37, 3.8, 407, wet=True, mortar_r=False, mortar_b=False)
    drape_moss(clr, 20, 27, 31, 2, 2, 409)
    clr_out = outline_pass(clr, OUT)
    for rx_w, a_w in [(19, 85), (20, 125), (21, 140), (22, 95), (25, 110), (26, 145), (27, 115), (28, 80)]:
        _blend_under(clr_out, rx_w, 38, (*BRIDGE_AQUA_HI_RGB, a_w))

    for y in range(FH):
        sheet[y][0:FW] = jam_out[y]
        sheet[y][FW:FW * 2] = clr_out[y]
    return sheet


# ==============================================================================
# 4. Broken Stone Bridge (`broken_stone_bridge.png` & `_glow.png`, 4x1 of 96x96, center (48, 56))
# ==============================================================================
BRIDGE_WARM_STONE = [
    hexc("211b32"),  # 0 deep warm crevice
    hexc("312844"),  # 1 warm plum-slate shadow
    hexc("453a58"),  # 2 dark weathered sandstone
    hexc("5b4d70"),  # 3 mid-dark warm stone
    hexc("736488"),  # 4 mid warm fieldstone
    hexc("8e7ea2"),  # 5 lit warm slab
    hexc("aba0be"),  # 6 bright warm facet
    hexc("cfc5de"),  # 7 sunlit warm catch-edge
]
BRIDGE_EARTH = [
    hexc("262030"),  # 0 damp soil crevice
    hexc("372f3e"),  # 1 shaded path earth
    hexc("4b3f4e"),  # 2 packed road grit
    hexc("63535f"),  # 3 mid path loam
    hexc("7d6a70"),  # 4 sunlit dry earth
    hexc("988482"),  # 5 pale worn grit
]
BRIDGE_TURF = [
    hexc("22483c"),  # 0 canonical meadow ramp
    hexc("2f624e"),  # 1
    hexc("3e7d56"),  # 2
    hexc("55985f"),  # 3
    hexc("7cb96d"),  # 4
    hexc("a8dc8c"),  # 5
]
BRIDGE_TURF_ROOT = hexc("183430")
BRIDGE_IVY = [hexc(c) for c in ("142c34", "1e4c44", "2e7254", "4c9a66", "74be7c")]
BRIDGE_LICHEN = [hexc("5e8278"), hexc("90b8a8")]
BRIDGE_RUNE_DIM = hexc("1f6874")
BRIDGE_RUNE_HOT = hexc("d0fff8")
BRIDGE_WATER_SH_RGB = (16, 38, 58)
BRIDGE_AQUA_MID_RGB = (64, 162, 178)
BRIDGE_AQUA_HI_RGB = (144, 232, 228)
BRIDGE_AQUA_FOAM_RGB = (210, 252, 246)

_DECK_FIELD_CACHE = {}


def _blend_under(px, x: int, y: int, rgba):
    if not (0 <= x < len(px[0]) and 0 <= y < len(px)):
        return
    sa = rgba[3]
    if sa <= 0:
        return
    dst = px[y][x]
    da = dst[3]
    if da == 0 or sa >= 255:
        px[y][x] = rgba
        return
    out_a = sa + (da * (255 - sa)) // 255
    if out_a <= 0:
        return
    inv = 255 - sa
    r = (rgba[0] * sa + (dst[0] * da * inv) // 255) // out_a
    g = (rgba[1] * sa + (dst[1] * da * inv) // 255) // out_a
    b = (rgba[2] * sa + (dst[2] * da * inv) // 255) // out_a
    px[y][x] = (int(clamp(r, 1, 255)), int(clamp(g, 1, 255)), int(clamp(b, 1, 255)), int(clamp(out_a, 1, 255)))


def _darken_stone_col(col, delta: int):
    if col in STONE:
        return STONE[max(0, STONE.index(col) - delta)]
    if col in BRIDGE_WARM_STONE:
        return BRIDGE_WARM_STONE[max(0, BRIDGE_WARM_STONE.index(col) - delta)]
    if col in BRIDGE_EARTH:
        return BRIDGE_EARTH[max(0, BRIDGE_EARTH.index(col) - max(1, delta - 1))]
    if col in MOSS:
        return MOSS[max(0, MOSS.index(col) - max(1, delta - 1))]
    return col


def _lighten_stone_col(col, delta: int):
    if col in STONE:
        return STONE[min(len(STONE) - 1, STONE.index(col) + delta)]
    if col in BRIDGE_WARM_STONE:
        return BRIDGE_WARM_STONE[min(len(BRIDGE_WARM_STONE) - 1, BRIDGE_WARM_STONE.index(col) + delta)]
    return col


def _get_deck_field(seed: int, horizontal: bool):
    key = (seed, horizontal)
    if key in _DECK_FIELD_CACHE:
        return _DECK_FIELD_CACHE[key]

    rng = random.Random(seed + 701)
    sites = []
    s_id = 0

    if horizontal:
        # Dressed kerb courses bordering the deck (y ~ 43.2 & 66.0) + irregular staggered interior flagstone courses
        row_ys = [39.5, 43.4, 48.0, 52.8, 57.6, 62.1, 66.0, 69.8]
        for r_idx, ry_base in enumerate(row_ys):
            is_curb = r_idx in (1, 6)
            x_cur = -4.0 + (rng.uniform(2.5, 5.5) if r_idx % 2 else 0.0)
            while x_cur < 100.0:
                step_x = rng.uniform(7.5, 11.2) if is_curb else rng.uniform(6.2, 11.8)
                jit_y = rng.uniform(-0.35, 0.35) if is_curb else rng.uniform(-1.25, 1.25)
                sx = x_cur + step_x * 0.5 + rng.uniform(-0.8, 0.8)
                sy = ry_base + jit_y
                warm = (hsh(s_id, r_idx, seed + 11) < 0.31)
                bias = (hsh(s_id, r_idx, seed + 23) - 0.5) * 1.15
                crack = (hsh(s_id, r_idx, seed + 37) < 0.20)
                c_ang = 0.45 + hsh(s_id, 3, seed + 41) * 1.6
                sites.append((sx, sy, s_id, warm, bias, crack, c_ang, is_curb))
                s_id += 1
                x_cur += step_x
        ax, ay = 0.84, 1.18
    else:
        # Dressed kerb columns bordering the deck (x ~ 31.2 & 65.0) + irregular staggered interior flagstone columns
        col_xs = [27.0, 31.3, 36.2, 41.8, 48.0, 54.1, 59.8, 65.0, 69.2]
        for c_idx, cx_base in enumerate(col_xs):
            is_curb = c_idx in (1, 7)
            y_cur = -4.0 + (rng.uniform(2.5, 5.5) if c_idx % 2 else 0.0)
            while y_cur < 100.0:
                step_y = rng.uniform(7.2, 10.8) if is_curb else rng.uniform(5.8, 10.6)
                jit_x = rng.uniform(-0.35, 0.35) if is_curb else rng.uniform(-1.25, 1.25)
                sx = cx_base + jit_x
                sy = y_cur + step_y * 0.5 + rng.uniform(-0.8, 0.8)
                warm = (hsh(s_id, c_idx, seed + 13) < 0.31)
                bias = (hsh(s_id, c_idx, seed + 29) - 0.5) * 1.15
                crack = (hsh(s_id, c_idx, seed + 43) < 0.20)
                c_ang = 0.45 + hsh(s_id, 5, seed + 47) * 1.6
                sites.append((sx, sy, s_id, warm, bias, crack, c_ang, is_curb))
                s_id += 1
                y_cur += step_y
        ax, ay = 1.12, 0.88

    # Spatial acceleration buckets (12x12 px)
    buckets = {}
    for idx, st in enumerate(sites):
        bx, by = int(st[0] // 12), int(st[1] // 12)
        buckets.setdefault((bx, by), []).append(idx)

    grid_cells = [[None] * 96 for _ in range(96)]
    for y in range(96):
        for x in range(96):
            wx = x + 0.5 + (vnoise(x * 0.26, y * 0.26, seed + 53) - 0.5) * 1.15
            wy = y + 0.5 + (vnoise(x * 0.26, y * 0.26, seed + 67) - 0.5) * 1.15
            bx, by = int(wx // 12), int(wy // 12)
            d1, d2, d3 = 1e9, 1e9, 1e9
            i1, i2 = 0, 0
            for dby in (-1, 0, 1):
                for dbx in (-1, 0, 1):
                    for cand in buckets.get((bx + dbx, by + dby), ()):
                        sx, sy = sites[cand][0], sites[cand][1]
                        dd = math.hypot((wx - sx) * ax, (wy - sy) * ay)
                        if dd < d1:
                            d3, d2, d1 = d2, d1, dd
                            i2, i1 = i1, cand
                        elif dd < d2:
                            d3, d2 = d2, dd
                            i2 = cand
                        elif dd < d3:
                            d3 = dd
            sx1, sy1 = sites[i1][0], sites[i1][1]
            sx2, sy2 = sites[i2][0], sites[i2][1]
            vx, vy = sx1 - sx2, sy1 - sy2
            vlen = max(0.001, math.hypot(vx, vy))
            # Positive bevel when neighbor s2 is up/left of s1 -> pixel sits on sunlit top-left rim of s1
            bevel_dot = (vx / vlen) * 0.64 + (vy / vlen) * 0.77
            grid_cells[y][x] = (i1, d2 - d1, d3 - d1, bevel_dot)

    res = (sites, grid_cells)
    _DECK_FIELD_CACHE[key] = res
    return res


def shade_flagstone_deck(px, x: int, y: int, seed: int):
    """Shades organic polygonal road flagstones (cool river slate + warm sandstone-violet, bevels, cracks & worn grit)."""
    horizontal = (seed % 2 == 1)  # col 0 (2501), col 1 (2548) -> check explicit flag via helper below if needed
    return _shade_flagstone_px(x, y, seed, horizontal=True, wear_center=54.5, wear_half=12.5, extra_crack=False)


def _shade_flagstone_px(
    x: int,
    y: int,
    seed: int,
    horizontal: bool,
    wear_center: float,
    wear_half: float,
    extra_crack: bool = False,
):
    sites, grid_cells = _get_deck_field(seed, horizontal)
    i1, gap12, gap13, bevel_dot = grid_cells[y][x]
    sx, sy, s_id, warm, bias, has_crack, c_ang, is_curb = sites[i1]

    coord_across = float(y) if horizontal else float(x)
    edge_u = abs(coord_across - wear_center) / max(1.0, wear_half)  # 0 at road center, ~1 near parapets

    # Mortar crevices & chamfered 3-stone corners
    if gap12 < 0.56 or gap13 < 0.92:
        # Worn central footpath has occasional packed earth grit in joints; edges gather damp moss!
        if edge_u > 0.66 and vnoise(x * 0.34, y * 0.34, seed + 89) > 0.54:
            return MOSS[3 if bevel_dot > 0.1 else 2]
        if edge_u < 0.42 and hsh(x, y, seed + 97) < 0.34:
            return BRIDGE_EARTH[2]
        return MORTAR

    pal = BRIDGE_WARM_STONE if warm else STONE
    # Clean directional cluster shading (top-left light + smooth center road polish, zero noisy static)
    base_lit = 4.25 + bias + (0.32 if is_curb else 0.0)
    if edge_u < 0.45:
        base_lit += 0.25 * (1.0 - edge_u / 0.45)  # Subtle worn footpath sheen along road center
    else:
        base_lit -= 0.28 * ((edge_u - 0.45) / 0.55)

    bevel = 0.0
    if gap12 < 1.46:
        if bevel_dot > 0.22:
            bevel = 1.05 if bevel_dot > 0.55 else 0.68
        elif bevel_dot < -0.24:
            bevel = -0.68

    # Directional mineral stroke cluster (elongated along stone course)
    stroke = (vnoise(x * (0.28 if horizontal else 0.48), y * (0.48 if horizontal else 0.28), seed + 109) - 0.5) * 1.05

    # Hairline fracture crack across weathered slabs (more frequent near broken chasm brink)
    crack_delta = 0.0
    if has_crack or (extra_crack and s_id % 3 == 0):
        rx_c = (x + 0.5 - sx) * math.cos(c_ang) + (y + 0.5 - sy) * math.sin(c_ang)
        ry_c = -(x + 0.5 - sx) * math.sin(c_ang) + (y + 0.5 - sy) * math.cos(c_ang)
        wiggle = 0.55 * math.sin(ry_c * 0.65 + s_id)
        cd = rx_c - wiggle
        if abs(cd) < 0.46 and abs(ry_c) < 3.6:
            return pal[1]
        if 0.46 <= cd < 1.02 and abs(ry_c) < 3.2:
            crack_delta = 0.72  # Sunlit catch-lip right beside hairline crack

    # Occasional pale crust lichen fleck near quiet parapet edges
    if edge_u > 0.72 and gap12 > 1.5 and hsh(s_id, x // 2 + y // 2, seed + 131) < 0.045:
        return BRIDGE_LICHEN[1 if bevel_dot >= 0 else 0]

    idx = int(clamp(round(base_lit + bevel + stroke + crack_delta), 1, 7))
    return pal[idx]


def _draw_stone_block(
    px,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    lit_idx: float,
    seed: int,
    warm: bool = False,
    wet: bool = False,
    top_bevel: bool = True,
    left_bevel: bool = True,
    mortar_r: bool = True,
    mortar_b: bool = True,
):
    if x1 < x0 or y1 < y0:
        return
    pal = WET_STONE if wet else (BRIDGE_WARM_STONE if warm else STONE)
    max_i = len(pal) - 1
    scale = (max_i / 7.0) if wet else 1.0
    chip_tr = (x1 - x0 >= 4 and y1 - y0 >= 3 and hsh(x0, y0, seed + 7) < 0.28)
    chip_bl = (x1 - x0 >= 5 and y1 - y0 >= 3 and hsh(x0, y0, seed + 13) < 0.22)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (mortar_r and x == x1) or (mortar_b and y == y1):
                put(px, x, y, MORTAR)
                continue
            if chip_tr and x == x1 - 1 and y == y0:
                put(px, x, y, MORTAR)
                continue
            if chip_bl and x == x0 and y == y1 - 1:
                put(px, x, y, MORTAR)
                continue
            bv = 0.0
            if top_bevel and y == y0:
                bv += 1.05
            if left_bevel and x == x0:
                bv += 0.65
            if mortar_b and y == y1 - 1 and y > y0:
                bv -= 0.45
            if mortar_r and x == x1 - 1 and x > x0:
                bv -= 0.35
            cl = (vnoise(x * 0.36, y * 0.46, seed + 19) - 0.5) * 0.85
            idx = int(clamp(round((lit_idx + bv + cl) * scale), 0 if wet else 1, max_i))
            put(px, x, y, pal[idx])


def _draw_grass_tuft(px, cx: int, cy: int, seed: int, big: bool = False):
    """Paints a crisp Shadowspore meadow grass tuft (canonical 6-tone meadow greens, zero #1b1a2e box)."""
    blades = (
        [(-3, 0, 1), (-2, -1, 2), (-2, -2, 4), (-1, 0, 0), (-1, -1, 2), (-1, -3, 5), (0, 0, 1), (0, -2, 3), (0, -4, 5),
         (1, 0, 0), (1, -1, 2), (1, -3, 4), (2, 0, 1), (2, -1, 3), (3, 0, 2)]
        if big else
        [(-2, 0, 1), (-1, 0, 0), (-1, -1, 3), (-1, -2, 4), (0, 0, 1), (0, -1, 2), (0, -3, 5), (1, 0, 0), (1, -1, 3), (2, 0, 2)]
    )
    flip = -1 if hsh(cx, cy, seed) > 0.5 else 1
    put(px, cx, cy + 1, (*BRIDGE_TURF_ROOT[:3], 170))
    for dx, dy, ti in blades:
        put(px, cx + dx * flip, cy + dy, BRIDGE_TURF[ti])


def _draw_ivy_tendril(px, x0: int, y0: int, length: int, sway_dir: float, seed: int):
    for k in range(length):
        xx = x0 + int(round(sway_dir * (k * 0.25) + 1.15 * math.sin(k * 0.68 + seed)))
        yy = y0 + k
        tone = 4 if k == 0 else (3 if k < length * 0.45 else (2 if k < length - 2 else 1))
        put(px, xx, yy, BRIDGE_IVY[tone])
        if k % 2 == 1 and k < length - 1:
            side = -1 if (k // 2 + seed) % 2 == 0 else 1
            put(px, xx + side, yy, BRIDGE_IVY[min(4, tone + 1) if side < 0 else max(0, tone - 1)])


def _paint_water_lap(under_px, over_px, x0: int, x1: int, y_water: int, seed: int, foam_x0: int = -1, foam_x1: int = -1):
    """Paints a 2-3px feathered translucent pale-aqua river foam/ripple water-lap & cool reflection (outside outline_pass)."""
    if foam_x0 < 0:
        foam_x0 = x0
    if foam_x1 < 0:
        foam_x1 = x1
    for x in range(x0, x1 + 1):
        edge_fade = min(1.0, min(x - x0 + 1, x1 - x + 1) / 3.5)
        # Subtle dark cool water/bank reflection band extending 2-3px below submerged masonry
        for dy, base_a in ((0, 118), (1, 78), (2, 38)):
            a = int(base_a * edge_fade)
            if a > 8:
                _blend_under(under_px, x, y_water + dy, (*BRIDGE_WATER_SH_RGB, a))
        # Translucent pale-aqua water-lap foam & broken river ripple wisps over riverward zone
        if foam_x0 <= x <= foam_x1:
            f_fade = min(1.0, min(x - foam_x0 + 1, foam_x1 - x + 1) / 3.0)
            wave = math.sin(x * 0.48 + seed * 0.7) * 0.5 + 0.5
            if wave > 0.30:
                a_hi = int((138 if wave > 0.68 else 88) * f_fade)
                rgb_hi = BRIDGE_AQUA_FOAM_RGB if wave > 0.76 else BRIDGE_AQUA_HI_RGB
                _blend_under(over_px, x, y_water, (*rgb_hi, a_hi))
            else:
                _blend_under(over_px, x, y_water, (*BRIDGE_AQUA_MID_RGB, int(74 * f_fade)))
            if math.sin(x * 0.39 - seed * 1.1) > 0.38:
                _blend_under(over_px, x, y_water + 1, (*BRIDGE_AQUA_HI_RGB, int(82 * f_fade)))
            if (x + seed) % 5 in (0, 1) and f_fade > 0.55:
                _blend_under(over_px, x, y_water + 2, (*BRIDGE_AQUA_MID_RGB, int(48 * f_fade)))


def draw_wayfarer_lantern_post(px, glow: GlowMap, cx: int, cy: int):
    """Carved stepped stone lantern pillar with wrought-iron cage/cap & warm-amber + turquoise wayfarer flame!"""
    # 1) Stepped carved stone plinth resting on parapet (`cy - 1 .. cy + 2`)
    _draw_stone_block(px, cx - 4, cy + 1, cx + 4, cy + 2, 5.2, cx * 13 + cy, warm=True, mortar_r=False, mortar_b=False)
    _draw_stone_block(px, cx - 3, cy - 2, cx + 3, cy, 5.0, cx * 17 + cy, warm=False, mortar_r=False, mortar_b=False)
    # Chamfered stone shaft (`cy - 5 .. cy - 3`) + carved stone collar (`cy - 6`)
    for dy in (-5, -4, -3):
        put(px, cx - 2, cy + dy, STONE[6])
        put(px, cx - 1, cy + dy, STONE[5])
        put(px, cx, cy + dy, STONE[4])
        put(px, cx + 1, cy + dy, STONE[3])
        put(px, cx + 2, cy + dy, STONE[2])
    for dx in range(-3, 4):
        put(px, cx + dx, cy - 6, BRIDGE_WARM_STONE[7 if dx < 0 else (5 if dx <= 1 else 3)])

    # 2) Wrought-iron lantern cage (`cy - 10 .. cy - 7`) + flared iron pagoda cap & finial (`cy - 13 .. cy - 11`)
    for dx in range(-3, 4):
        put(px, cx + dx, cy - 7, IRON[3 if dx <= 0 else 1])
    for dy in (-10, -9, -8):
        put(px, cx - 2, cy + dy, IRON[3])
        put(px, cx + 2, cy + dy, IRON[1])
        for dx in (-1, 0, 1):
            put(px, cx + dx, cy + dy, STONE[0])
    for dx in range(-3, 4):
        put(px, cx + dx, cy - 11, IRON[4 if dx < 0 else (3 if dx <= 1 else 1)])
    for dx in range(-2, 3):
        put(px, cx + dx, cy - 12, IRON[4 if dx <= 0 else 2])
    put(px, cx, cy - 13, IRON[4])

    # 3) Luminous warm-amber + turquoise wayfarer flame (`_glow.png`) + inlaid turquoise plinth rune
    glow.emit(px, cx, cy - 8, AMBER_H, AMBER_H, halo=2)
    glow.emit(px, cx, cy - 9, BRIDGE_GOLD, BRIDGE_GOLD, halo=2)
    glow.emit(px, cx + 1, cy - 8, AMBER_M, AMBER_M, halo=1)
    glow.emit(px, cx - 1, cy - 9, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)
    glow.emit(px, cx - 1, cy - 10, BRIDGE_RUNE_DIM, BRIDGE_RUNE_HOT, halo=1)
    put(px, cx, cy - 1, STONE[0])
    glow.emit(px, cx, cy, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=1)


def _draw_wayfarer_rune_plaque(px, glow: GlowMap, cx: int, cy: int):
    """Carved recessed stone rune tablet with glowing turquoise Shadow-Step glyph on opposite parapet."""
    _draw_stone_block(px, cx - 3, cy - 2, cx + 3, cy + 2, 5.2, cx * 29 + cy, warm=True, mortar_r=False, mortar_b=False)
    for dy in (-1, 0, 1):
        for dx in (-2, -1, 0, 1, 2):
            put(px, cx + dx, cy + dy, STONE[0])
    glow.emit(px, cx, cy, BRIDGE_TEAL_L, BRIDGE_RUNE_HOT, halo=2)
    glow.emit(px, cx - 1, cy, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)
    glow.emit(px, cx + 1, cy, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=1)
    glow.emit(px, cx, cy - 1, BRIDGE_RUNE_DIM, BRIDGE_TEAL_L, halo=1)
    glow.emit(px, cx, cy + 1, BRIDGE_RUNE_DIM, BRIDGE_TEAL, halo=1)


def _draw_stone_bollard(px, x0: int, y0: int, x1: int, y1: int, seed: int):
    """Sculpted square corner bollard / wing-wall terminal pier with pyramidal capstone & molding."""
    # Lower shaft
    _draw_stone_block(px, x0, y0 + 4, x1, y1, 4.6, seed + 3, warm=False, mortar_r=False, mortar_b=False)
    # Mid necking groove
    for x in range(x0, x1 + 1):
        put(px, x, y0 + 3, MORTAR if x == x1 else STONE[2 if x > (x0 + x1) // 2 else 3])
    # Overhanging dressed warm capstone
    _draw_stone_block(px, x0 - 1, y0 + 1, x1 + 1, y0 + 2, 5.8, seed + 9, warm=True, mortar_r=False, mortar_b=False)
    for x in range(x0, x1 + 1):
        put(px, x, y0, BRIDGE_WARM_STONE[7 if x <= (x0 + x1) // 2 else 5])


def build_bridge_variant(col: int):
    W, H = 96, 96
    glow = GlowMap(W, H)
    stone_body = blank(W, H)
    under_layer = blank(W, H)
    over_flora = blank(W, H)
    no_outline = [[False] * W for _ in range(H)]
    seed = 2501 + col * 47
    rng = random.Random(seed)

    if col in (0, 1):
        # ======================================================================
        # Horizontal Bridge Abutments (96x96, anchor (48, 56)):
        #   Walkable deck surface: y = 42..67 (x = 0..84 West, x = 12..96 East)
        #   North parapet: y = 33..41 (soft deck shadow y = 42..43)
        #   South parapet: y = 67..74 (clear 3/4 front face below coping)
        #   Shore half (x < 40 West / x > 56 East): flared wing-walls, bollards,
        #     feathered earth/cobble apron & sloped mossy embankment (NO 18px cliff!)
        #   River half (x = 40..86 West / x = 10..56 East): splayed wet pier +
        #     cutwater buttress, radial voussoirs + keystone, recessed dark barrel
        #     vault ceiling (zero bank grass poking through!) & aqua water-lap!
        # ======================================================================
        is_west = (col == 0)
        sites, grid_cells = _get_deck_field(seed, horizontal=True)

        def shore_d(x: int) -> int:
            return x if is_west else (W - 1 - x)

        # 1) Feathered Shore Approach Apron (`d = 0..19`, `y = 39..70`, crisp pixel-art clusters + sunken cobbles, outside `outline_pass`!)
        for y in range(38, 72):
            for x in range(W):
                d = shore_d(x)
                if d > 19:
                    continue
                rel_y = abs(y - 54.5) / 15.2
                n_val = vnoise(x * 0.40, y * 0.40, seed + 17)
                wob = 0.16 * math.sin(y * 0.34 + col * 1.9) + 0.18 * (n_val - 0.5)
                if rel_y > 0.98 + wob * 0.42:
                    continue
                # Crisp clustered pixel-art alpha bands (`255 / 175 / 95`) instead of blurry linear smear!
                u_in = (d + wob * 6.0) / 11.0 - rel_y * 0.32
                if u_in <= 0.14:
                    continue
                alpha = 255 if (d >= 11 and rel_y < 0.84) else (255 if u_in > 0.74 else (176 if u_in > 0.44 else 96))
                turf_mix = rel_y > 0.64 - 0.24 * (1.0 - min(1.0, d / 14.0)) + wob * 0.35
                if turf_mix:
                    tc = BRIDGE_TURF[int(clamp(1.1 + n_val * 3.5, 0, 4))]
                else:
                    tc = BRIDGE_EARTH[int(clamp(1.4 + n_val * 3.1 + (0.45 if abs(y - 54.5) < 5.5 else 0.0), 1, 4))]
                under_layer[y][x] = (tc[0], tc[1], tc[2], alpha)

                # Scattered sunken mossy threshold flagstones emerging across `d = 3..15`
                if 3 <= d <= 15 and 42 <= y <= 67:
                    i1, gap12, _, _ = grid_cells[y][x]
                    sx_c, sy_c, s_id_c = sites[i1][0], sites[i1][1], sites[i1][2]
                    d_site = shore_d(int(round(sx_c)))
                    keep_prob = (d_site - 2.2) / 10.5
                    if 42.5 <= sy_c <= 66.5 and hsh(s_id_c, 7, seed + 21) < keep_prob:
                        if gap12 >= 0.78:
                            sc = _shade_flagstone_px(x, y, seed, True, 54.5, 12.5, False)
                            under_layer[y][x] = (sc[0], sc[1], sc[2], 255 if d >= 6 else 215)
                        else:
                            mc = BRIDGE_TURF[2 if n_val > 0.5 else 1]
                            under_layer[y][x] = (mc[0], mc[1], mc[2], max(alpha, 210))

        # 2) Walkable Irregular Polygonal Flagstone Deck (`y = 42..67`) with organic polygon-guided chasm fracture!
        for y in range(42, 68):
            # Per-row fracture envelope around x = 78..85 (West) / x = 11..18 (East)
            row_wave = 3.2 * math.sin(y * 0.29 + col * 2.3) + 2.2 * (hsh(y // 3, col, seed + 31) - 0.5)
            for x in range(W):
                d = shore_d(x)
                if d < 12:
                    continue
                i1, gap12, _, _ = grid_cells[y][x]
                sx_c, sy_c, s_id_c = sites[i1][0], sites[i1][1], sites[i1][2]
                # Shore transition: cells at `d = 12..16` step organically onto `stone_body`
                if d < 16 and hsh(s_id_c, 11, seed + 33) > (d - 10.5) / 5.5:
                    continue

                # Chasm break: decide per stone polygon so slabs jut as crisp angular cantilevers (no sine mush or cobble eggs!)
                cell_jut = (hsh(s_id_c, 19, seed + 39) - 0.45) * 5.2
                if is_west:
                    limit_x = 80.5 + row_wave + cell_jut
                    if sx_c > limit_x or x > int(round(limit_x + 2.2)):
                        continue
                    near_brink = (x >= 72)
                else:
                    limit_x = 15.5 - row_wave - cell_jut
                    if sx_c < limit_x or x < int(round(limit_x - 2.2)):
                        continue
                    near_brink = (x <= 23)

                col_px = _shade_flagstone_px(x, y, seed, True, 54.5, 12.5, extra_crack=near_brink)
                put(stone_body, x, y, col_px)

        # Extrude 3D broken slab thickness (`3px` rock edge + chasm drop shadow) under cantilevered brink flagstones!
        deck_snap = [row[:] for row in stone_body]
        for y in range(42, 68):
            for x in (range(73, 89) if is_west else range(7, 23)):
                if deck_snap[y][x][3] == 0:
                    continue
                # Exposed right/left broken slab edge + exposed bottom overhang
                open_riverward = (x + (1 if is_west else -1) < W) and deck_snap[y][x + (1 if is_west else -1)][3] == 0
                if open_riverward:
                    # Crisp fracture rim on top-left-lit East break vs shaded West break
                    stone_body[y][x] = _lighten_stone_col(stone_body[y][x], 1) if not is_west else _darken_stone_col(stone_body[y][x], 1)
                if y + 1 <= 68 and deck_snap[y + 1][x][3] == 0:
                    for th in (1, 2, 3):
                        yy = y + th
                        if yy <= 70 and stone_body[yy][x][3] == 0:
                            put(stone_body, x, yy, STONE[2 if th == 1 else (1 if th == 2 else 0)])
                    _blend_under(under_layer, x + (1 if is_west else -1), y + 4, (*SHADOW_RGB, 105))
                if open_riverward:
                    for sh_dx in (1, 2):
                        xx_s = x + sh_dx * (1 if is_west else -1)
                        _blend_under(under_layer, xx_s, y + 1, (*SHADOW_RGB, 112 if sh_dx == 1 else 58))

        # 3) North Parapet (`y = 33..41`) + Flared Wing-Wall & Corner Bollard (`d = 6..21`) + Broken Step-Down
        # Staggered inner cheek courses (`y = 37..41`) + overhang shadow (`y = 36`) + coping slabs (`y = 33..35`)
        x_p0, x_p1 = (14, 80) if is_west else (15, 81)
        for c_i, (cy0, cy1) in enumerate(((37, 39), (40, 41))):
            xc = x_p0 - (3 if c_i else 0)
            while xc <= x_p1:
                bw = rng.randint(6, 11)
                bx0, bx1 = max(x_p0, xc), min(x_p1, xc + bw - 1)
                # Step down toward river break
                dist_brink = (80 - bx1) if is_west else (bx0 - 15)
                if dist_brink >= (0 if c_i == 1 else 3):
                    warm = hsh(bx0, cy0, seed + 51) < 0.30
                    _draw_stone_block(stone_body, bx0, cy0, bx1, cy1, 3.8 - 0.3 * c_i, seed + bx0 + cy0, warm=warm)
                xc += bw
        # Coping course (`y = 33..35`, overhang lip `y = 36` stops slightly before ragged rubble tip)
        cp0, cp1 = (15, 74) if is_west else (21, 80)
        for x in range(cp0, cp1 + 1):
            put(stone_body, x, 36, MORTAR if x % 7 == 0 else STONE[1])
        xc = cp0
        while xc <= cp1:
            bw = rng.randint(7, 12)
            bx0, bx1 = xc, min(cp1, xc + bw - 1)
            # Slight upward flare near shore (`d < 22`)
            flare_up = 1 if shore_d((bx0 + bx1) // 2) < 20 else 0
            warm = hsh(bx0, 33, seed + 61) < 0.34
            _draw_stone_block(stone_body, bx0, 33 - flare_up, bx1, 35, 5.7, seed + bx0 * 3, warm=warm, mortar_b=False)
            xc += bw

        # Soft North Parapet Cast Shadow onto walkable deck (`y = 42..43`)
        for x in range(W):
            if stone_body[41][x][3] > 0:
                if stone_body[42][x][3] > 0:
                    stone_body[42][x] = _darken_stone_col(stone_body[42][x], 2)
                if stone_body[43][x][3] > 0:
                    stone_body[43][x] = _darken_stone_col(stone_body[43][x], 1)

        # 4) South Parapet (`y = 68..74`, clear 3/4 front face below coping so player feet at `y <= 67` never clip!)
        sp0, sp1 = (14, 80) if is_west else (15, 81)
        for c_i, (cy0, cy1) in enumerate(((71, 72), (73, 74))):
            xc = sp0 - (4 if c_i else 0)
            while xc <= sp1:
                bw = rng.randint(6, 11)
                bx0, bx1 = max(sp0, xc), min(sp1, xc + bw - 1)
                dist_brink = (80 - bx1) if is_west else (bx0 - 15)
                if dist_brink >= (0 if c_i == 1 else 2):
                    warm = hsh(bx0, cy0, seed + 71) < 0.30
                    _draw_stone_block(stone_body, bx0, cy0, bx1, cy1, 4.1 - 0.45 * c_i, seed + bx0 + cy0 * 2, warm=warm)
                xc += bw
        scp0, scp1 = (15, 75) if is_west else (20, 80)
        for x in range(scp0, scp1 + 1):
            put(stone_body, x, 70, STONE[1])
        xc = scp0
        while xc <= scp1:
            bw = rng.randint(7, 12)
            bx0, bx1 = xc, min(scp1, xc + bw - 1)
            flare_dn = 1 if shore_d((bx0 + bx1) // 2) < 20 else 0
            warm = hsh(bx0, 68, seed + 79) < 0.34
            _draw_stone_block(stone_body, bx0, 68, bx1, 69 + flare_dn, 5.6, seed + bx0 * 5, warm=warm, mortar_b=False)
            xc += bw

        # Sculpted Shore Corner Bollards & Stepped Terminal Kerb Stones (`d = 6..15`)
        if is_west:
            _draw_stone_bollard(stone_body, 9, 30, 14, 41, seed + 101)
            _draw_stone_block(stone_body, 6, 36, 8, 41, 4.8, seed + 102, warm=True, mortar_b=False)
            _draw_stone_bollard(stone_body, 9, 65, 14, 76, seed + 103)
            _draw_stone_block(stone_body, 6, 70, 8, 75, 4.6, seed + 104, warm=False, mortar_b=False)
        else:
            _draw_stone_bollard(stone_body, 81, 30, 86, 41, seed + 105)
            _draw_stone_block(stone_body, 87, 36, 89, 41, 4.4, seed + 106, warm=True, mortar_b=False)
            _draw_stone_bollard(stone_body, 81, 65, 86, 76, seed + 107)
            _draw_stone_block(stone_body, 87, 70, 89, 75, 4.3, seed + 108, warm=False, mortar_b=False)

        # 5) Below South Parapet (`y >= 75`):
        #    - Shore Half (`d < 40`, i.e. `x < 40` West / `x > 55` East): NO 18px cliff! Low sloped mossy bank plinth & grass tufts!
        #    - River Half (`x = 40..85` West / `x = 11..55` East): Splayed Wet River Pier + Cutwater + Voussoir Half-Arch + Barrel Vault!
        for x in range(W):
            d = shore_d(x)
            if 22 <= d <= 39:
                # Gentle sloped kerb plinth (`1..5 px` tall) dipping toward the river bank at `d = 40`
                kerb_h = 1 + int(((d - 22) / 17.0) ** 1.45 * 4.5)
                for ky in range(75, 75 + kerb_h):
                    put(stone_body, x, ky, MOSS[2] if ky >= 75 + kerb_h - 1 else STONE[2 if (x + ky) % 6 == 0 else 3])

        # Riverward Half Spandrel, Splayed Pier & Recessed Barrel Vault (`x = 40..85` West / `x = 11..55` East)
        arch_cx = 79.0 if is_west else 16.0
        arch_cy = 90.5
        rx_in, ry_in = 20.5, 13.0
        rx_out, ry_out = 25.5, 17.2

        # First fill spandrel & pier irregular stone courses (`y = 75..90`)
        course_bands = [(75, 78), (79, 82), (83, 86), (87, 90)]
        rx0, rx1 = (40, 84) if is_west else (11, 55)
        for c_idx, (cy0, cy1) in enumerate(course_bands):
            xc = rx0 - (3 if c_idx % 2 else 0)
            while xc <= rx1:
                bw = rng.randint(7, 12)
                bx0, bx1 = max(rx0, xc), min(rx1, xc + bw - 1)
                wet_course = (cy0 >= 84)
                warm_b = (not wet_course) and (hsh(bx0, cy0, seed + 140 + c_idx) < 0.28)
                _draw_stone_block(
                    stone_body, bx0, cy0, bx1, cy1,
                    3.7 - 0.25 * c_idx, seed + bx0 * 7 + cy0,
                    warm=warm_b, wet=wet_course, mortar_b=(cy1 < 90),
                )
                xc += bw

        # Trim bank-step diagonal at `d = 40..45`, trim broken river crown, carve radial voussoirs & recessed barrel vault!
        for y in range(75, 91):
            for x in range(rx0, rx1 + 1):
                d = shore_d(x)
                # Smooth stepped diagonal bank abutment at `d = 40..45` (`y_bot` stepping 82 -> 90)
                if d < 46:
                    max_y_bank = 81 + int((d - 39) * 1.55)
                    if y > min(90, max_y_bank):
                        stone_body[y][x] = CLEAR
                        continue

                # Broken riverward crown beyond arch fracture (`x > 79..83` West / `x < 12..16` East)
                crown_jag = int(2.2 * math.sin(y * 0.55 + col))
                if (is_west and x > 81 + crown_jag - max(0, (y - 77) * 2)) or (not is_west and x < 14 - crown_jag + max(0, (y - 77) * 2)):
                    stone_body[y][x] = CLEAR
                    continue

                dx_i = (x + 0.5 - arch_cx) / rx_in
                dy_i = (arch_cy - (y + 0.5)) / ry_in
                r_in = math.hypot(dx_i, dy_i)

                dx_o = (x + 0.5 - arch_cx) / rx_out
                dy_o = (arch_cy - (y + 0.5)) / ry_out
                r_out = math.hypot(dx_o, dy_o)

                if r_in < 1.0:
                    # Inside the arch opening: fill recessed dark wet barrel-vault ceiling (soffit) so ZERO bank grass pokes through!
                    # Near the pier (`x = 58..69` West / `x = 26..37` East) vault extends down to `y = 89`;
                    # toward the open river chasm (`x >= 70` West / `x <= 25` East) the broken vault tapers up in 3/4 perspective!
                    dist_from_crown = abs(x - arch_cx)
                    if dist_from_crown >= 10.5:
                        y_vault_floor = 89
                    else:
                        y_vault_floor = 79 + int(dist_from_crown * 0.95)
                    if y <= y_vault_floor:
                        # Curved dark wet barrel-vault masonry courses in deep shadow + faint turquoise water bounce-light
                        vault_seam = ((y + int(abs(x - arch_cx) * 0.35)) % 4 == 0)
                        if r_in > 0.86 or vault_seam:
                            put(stone_body, x, y, STONE[0])
                        elif y >= 85 and (x + y) % 5 == 0:
                            put(stone_body, x, y, WET_STONE[2])
                        else:
                            put(stone_body, x, y, WET_STONE[0 if r_in > 0.58 else 1])
                    else:
                        stone_body[y][x] = CLEAR
                        # Soft cool shadow on river water beneath open broken vault crown
                        if y <= y_vault_floor + 3:
                            _blend_under(under_layer, x, y, (*BRIDGE_WATER_SH_RGB, 108 - (y - y_vault_floor) * 28))

                elif r_out <= 1.04:
                    # Radial wedge-shaped arch voussoir stones + carved keystone near crown (`ang ~ pi/2`)!
                    ang = math.atan2(max(0.01, dy_i), dx_i)  # 0..pi
                    wedge_f = (ang / math.pi) * 9.0
                    w_idx = int(wedge_f)
                    frac = wedge_f - w_idx
                    is_keystone = abs(ang - math.pi * 0.5) < 0.20
                    if abs(frac) < 0.11 or abs(1.0 - frac) < 0.11:
                        put(stone_body, x, y, MORTAR)
                    else:
                        pal_v = BRIDGE_WARM_STONE if (is_keystone or w_idx % 3 == 1) else STONE
                        lit_v = 5.6 if is_keystone else (5.0 if y < 81 else 3.8)
                        if r_in < 1.14 and ((is_west and dx_i < 0.15) or (not is_west and dx_i > -0.15)):
                            lit_v += 1.0  # Crisp sunlit inner/upper bevel on each voussoir!
                        if r_out > 0.96:
                            put(stone_body, x, y, MORTAR)
                        else:
                            put(stone_body, x, y, pal_v[int(clamp(round(lit_v), 2, 7))])

        # Sculpted 3/4 Triangular Cutwater Buttress on the River Pier (`cx_cut = 51` West / `44` East, `y = 75..90`)
        cx_cut = 51 if is_west else 44
        for y in range(75, 91):
            hw_c = 3 if y <= 77 else (4 if y <= 84 else 5)
            for dx in range(-hw_c, hw_c + 1):
                xx = cx_cut + dx
                if y <= 76:
                    # Sloped drip-cap hoodstone
                    put(stone_body, xx, y, BRIDGE_WARM_STONE[7 if dx <= 0 else 4])
                elif y == 77:
                    put(stone_body, xx, y, MORTAR if abs(dx) == hw_c else STONE[2])
                else:
                    wet_c = (y >= 84)
                    pal_c = WET_STONE if wet_c else STONE
                    if abs(dx) == hw_c or (y in (81, 86) and dx != 0):
                        put(stone_body, xx, y, MORTAR)
                    elif dx < 0:
                        put(stone_body, xx, y, pal_c[3 if wet_c else 6])
                    elif dx == 0:
                        put(stone_body, xx, y, pal_c[3 if wet_c else 7])  # Crisp sunlit 3/4 cutwater arris!
                    else:
                        put(stone_body, xx, y, pal_c[1 if wet_c else 2])

        # Olive-emerald waterline moss along wet pier (`y = 83..88`) + lush moss & trailing ivy on parapets & brink!
        pier_m0, pier_m1 = (44, 58) if is_west else (37, 51)
        drape_moss(stone_body, pier_m0, pier_m1, 84, 2, 2, seed + 171)

        if is_west:
            drape_moss(stone_body, 9, 34, 32, 2, 3, seed + 31)
            drape_moss(stone_body, 50, 75, 68, 2, 4, seed + 33)
            drape_moss(stone_body, 73, 80, 36, 2, 3, seed + 34)
            _draw_ivy_tendril(stone_body, 76, 69, 9, 0.5, seed + 181)
            _draw_ivy_tendril(stone_body, 66, 70, 7, -0.3, seed + 182)
            _draw_ivy_tendril(stone_body, 22, 69, 6, 0.2, seed + 183)
            draw_wayfarer_lantern_post(stone_body, glow, 56, 34)
            _draw_wayfarer_rune_plaque(stone_body, glow, 67, 71)
            # Feathered dark reflection + riverward pale-aqua foam/ripple water-lap (`foam_x = 55..74`)!
            _paint_water_lap(under_layer, over_flora, 45, 74, 90, seed + 191, foam_x0=55, foam_x1=74)
            # Lush meadow grass tufts tucking shore wing-walls, bollards & sloped embankment into terrain!
            for gx, gy, big in [(5, 42, False), (7, 35, False), (12, 41, False), (5, 67, False), (6, 75, True), (12, 76, True), (19, 76, False), (26, 77, True), (33, 79, False), (39, 81, True), (45, 89, False)]:
                _draw_grass_tuft(over_flora, gx, gy, seed + gx * 3, big=big)
        else:
            drape_moss(stone_body, 61, 86, 32, 2, 3, seed + 35)
            drape_moss(stone_body, 20, 45, 68, 2, 4, seed + 37)
            drape_moss(stone_body, 15, 22, 36, 2, 3, seed + 38)
            _draw_ivy_tendril(stone_body, 19, 69, 9, -0.5, seed + 184)
            _draw_ivy_tendril(stone_body, 29, 70, 7, 0.3, seed + 185)
            _draw_ivy_tendril(stone_body, 73, 69, 6, -0.2, seed + 186)
            draw_wayfarer_lantern_post(stone_body, glow, 40, 34)
            _draw_wayfarer_rune_plaque(stone_body, glow, 29, 71)
            _paint_water_lap(under_layer, over_flora, 21, 50, 90, seed + 193, foam_x0=21, foam_x1=40)
            for gx, gy, big in [(90, 42, False), (88, 35, False), (83, 41, False), (90, 67, False), (89, 75, True), (83, 76, True), (76, 76, False), (69, 77, True), (62, 79, False), (56, 81, True), (50, 89, False)]:
                _draw_grass_tuft(over_flora, gx, gy, seed + gx * 3, big=big)

        # Suppress `OUT` outline ONLY along shore road mouth, grass-buried shore skirt, and submerged bottom waterline!
        for y in range(H):
            for x in range(W):
                d = shore_d(x)
                if d <= 17 and 41 <= y <= 68:
                    no_outline[y][x] = True
                if d <= 39 and y >= 75:
                    no_outline[y][x] = True
                if y >= 89:
                    no_outline[y][x] = True

    else:
        # ======================================================================
        # Vertical Bridge Abutments (96x96, anchor (48, 56)):
        #   Walkable deck surface: x = 30..66 (y = 6..86 North, y = 10..94 South)
        #   Left parapet: x = 23..29 (soft cast shadow x = 30..31)
        #   Right parapet: x = 67..73
        #   Col 2 (North->South): shore wing-walls/bollards/apron at y = 0..24;
        #     3/4 fractured stone arch lip & shadowed wet pier depth at y = 75..89 + aqua water-lap!
        #   Col 3 (South->North): cantilevered broken flagstones, snapped coping & hanging moss at y = 10..20;
        #     shore wing-walls/bollards/apron at y = 70..95!
        # ======================================================================
        is_north = (col == 2)
        sites, grid_cells = _get_deck_field(seed, horizontal=False)

        def shore_dy(y: int) -> int:
            return y if is_north else (H - 1 - y)

        # 1) Feathered Shore Approach Apron (`d = 0..18`, `x = 26..70`, crisp pixel-art clusters + sunken cobbles, outside `outline_pass`!)
        for y in range(H):
            d = shore_dy(y)
            if d > 18:
                continue
            for x in range(25, 72):
                rel_x = abs(x - 48.0) / 21.2
                n_val = vnoise(x * 0.40, y * 0.40, seed + 19)
                wob = 0.16 * math.sin(x * 0.33 + col * 1.5) + 0.18 * (n_val - 0.5)
                if rel_x > 0.98 + wob * 0.42:
                    continue
                u_in = (d + wob * 5.8) / 10.6 - rel_x * 0.32
                if u_in <= 0.14:
                    continue
                alpha = 255 if (d >= 10 and rel_x < 0.84) else (255 if u_in > 0.74 else (176 if u_in > 0.44 else 96))
                turf_mix = rel_x > 0.66 - 0.24 * (1.0 - min(1.0, d / 13.0)) + wob * 0.35
                if turf_mix:
                    tc = BRIDGE_TURF[int(clamp(1.1 + n_val * 3.5, 0, 4))]
                else:
                    tc = BRIDGE_EARTH[int(clamp(1.4 + n_val * 3.1 + (0.45 if abs(x - 48.0) < 7.0 else 0.0), 1, 4))]
                under_layer[y][x] = (tc[0], tc[1], tc[2], alpha)

                if 3 <= d <= 15 and 30 <= x <= 66:
                    i1, gap12, _, _ = grid_cells[y][x]
                    sx_c, sy_c, s_id_c = sites[i1][0], sites[i1][1], sites[i1][2]
                    d_site = shore_dy(int(round(sy_c)))
                    if 30.5 <= sx_c <= 65.5 and hsh(s_id_c, 9, seed + 23) < (d_site - 2.0) / 10.5:
                        if gap12 >= 0.78:
                            sc = _shade_flagstone_px(x, y, seed, False, 48.0, 18.0, False)
                            under_layer[y][x] = (sc[0], sc[1], sc[2], 255 if d >= 6 else 215)
                        else:
                            mc = BRIDGE_TURF[2 if n_val > 0.5 else 1]
                            under_layer[y][x] = (mc[0], mc[1], mc[2], max(alpha, 210))

        # 2) Walkable Irregular Polygonal Flagstone Deck (`x = 30..66`) with polygon-guided chasm fracture!
        for y in range(H):
            d = shore_dy(y)
            if d < 11:
                continue
            for x in range(30, 67):
                col_wave = 2.8 * math.sin(x * 0.31 + col * 1.8) + 2.0 * (hsh(x // 3, col, seed + 41) - 0.5)
                i1, _, _, _ = grid_cells[y][x]
                sx_c, sy_c, s_id_c = sites[i1][0], sites[i1][1], sites[i1][2]
                if d < 15 and hsh(s_id_c, 13, seed + 43) > (d - 9.5) / 5.5:
                    continue
                cell_jut = (hsh(s_id_c, 23, seed + 47) - 0.45) * 4.8
                if is_north:
                    limit_y = 78.5 + col_wave + cell_jut
                    if sy_c > limit_y or y > int(round(limit_y + 2.0)):
                        continue
                    near_brink = (y >= 69)
                else:
                    limit_y = 15.5 - col_wave - cell_jut
                    if sy_c < limit_y or y < int(round(limit_y - 2.0)):
                        continue
                    near_brink = (y <= 25)
                col_px = _shade_flagstone_px(x, y, seed, False, 48.0, 18.0, extra_crack=near_brink)
                put(stone_body, x, y, col_px)

        # 3) Left Parapet (`x = 23..29`) & Right Parapet (`x = 67..73`) with irregular coping slabs & riverward buttress ribs!
        py0, py1 = (13, 81) if is_north else (14, 83)
        for side_i, (px0, px1) in enumerate(((23, 29), (67, 73))):
            yc = py0
            while yc <= py1:
                bh = rng.randint(7, 12)
                by0, by1 = yc, min(py1, yc + bh - 1)
                dist_brink = (81 - by1) if is_north else (by0 - 14)
                # Flare outward by 1-2px near shore (`d < 20`)
                mid_d = shore_dy((by0 + by1) // 2)
                fl = 2 if mid_d < 16 else (1 if mid_d < 21 else 0)
                bx0_f = px0 - fl if side_i == 0 else px0
                bx1_f = px1 if side_i == 0 else px1 + fl
                if dist_brink >= 2:
                    warm = hsh(px0, by0, seed + 83 + side_i) < 0.32
                    lit_p = 5.4 if side_i == 0 else 4.7
                    _draw_stone_block(stone_body, bx0_f, by0, bx1_f, by1, lit_p, seed + by0 * 5 + side_i, warm=warm)
                    # Inner/outer 3/4 vertical cheek shading (`x = 28..29` on left, `x = 72..73` on right)
                    for yy in range(by0, by1):
                        if side_i == 0:
                            put(stone_body, 28, yy, STONE[2])
                            put(stone_body, 29, yy, STONE[1])
                        else:
                            put(stone_body, bx1_f - 1, yy, STONE[2])
                            put(stone_body, bx1_f, yy, STONE[1])
                elif dist_brink >= -1:
                    # Broken parapet step-down exposing rough stone core near chasm brink!
                    _draw_stone_block(stone_body, px0 + 1, by0, px1 - 1, by1, 3.6, seed + by0 * 9 + side_i, warm=False)
                yc += bh

        # Subtle riverward exterior pilaster buttresses (`x = 21..22` & `x = 74..75`) for grounded bridge weight
        rib_range = range(48, 83) if is_north else range(16, 48)
        for yy in rib_range:
            if stone_body[yy][23][3] > 0:
                put(stone_body, 22, yy, MORTAR if yy % 6 == 0 else STONE[5])
                if abs(yy - (64 if is_north else 32)) <= 5:
                    put(stone_body, 21, yy, STONE[6 if yy % 6 != 0 else 2])
            if stone_body[yy][73][3] > 0:
                put(stone_body, 74, yy, MORTAR if yy % 6 == 0 else STONE[1])
                if abs(yy - (64 if is_north else 32)) <= 5:
                    put(stone_body, 75, yy, STONE[0])

        # Soft Left Parapet Cast Shadow onto walkable deck (`x = 30..31`)
        for y in range(H):
            if stone_body[y][29][3] > 0:
                if stone_body[y][30][3] > 0:
                    stone_body[y][30] = _darken_stone_col(stone_body[y][30], 2)
                if stone_body[y][31][3] > 0:
                    stone_body[y][31] = _darken_stone_col(stone_body[y][31], 1)

        # Sculpted Shore Corner Bollards (`x = 18..24` & `x = 72..78`) tucked into grass tufts!
        if is_north:
            _draw_stone_bollard(stone_body, 19, 8, 25, 16, seed + 121)
            _draw_stone_bollard(stone_body, 71, 8, 77, 16, seed + 123)
            _draw_stone_block(stone_body, 20, 5, 24, 8, 4.8, seed + 122, warm=True, mortar_b=False)
            _draw_stone_block(stone_body, 72, 5, 76, 8, 4.4, seed + 124, warm=True, mortar_b=False)
        else:
            _draw_stone_bollard(stone_body, 19, 77, 25, 87, seed + 125)
            _draw_stone_bollard(stone_body, 71, 77, 77, 87, seed + 127)
            _draw_stone_block(stone_body, 20, 86, 24, 89, 4.3, seed + 126, warm=False, mortar_b=False)
            _draw_stone_block(stone_body, 72, 86, 76, 89, 4.0, seed + 128, warm=False, mortar_b=False)

        # 4) Broken Chasm Architecture:
        if is_north:
            # Col 2 (North->South): Cohesive 3/4 fractured stone arch lip, wet side-piers & shadowed barrel-vault depth (`y = 76..88`)!
            deck_snap = [row[:] for row in stone_body]
            for x in range(21, 76):
                dx_a = (x - 48.0) / 17.5
                in_pier = (x <= 31) or (x >= 65)
                # Arch intrados rises smoothly from `y = 87` at side piers up to `y = 81` at center crown
                intrados_y = 81 + int(round(6.0 * min(1.15, dx_a * dx_a)))
                extrados_y = intrados_y - 4

                bot_deck = 75
                for yy in range(84, 70, -1):
                    if deck_snap[yy][x][3] > 0:
                        bot_deck = yy
                        break

                for y in range(min(bot_deck + 1, extrados_y), 89):
                    if deck_snap[y][x][3] > 0 and y < extrados_y:
                        continue
                    if in_pier:
                        if x in (21, 75) and y < 80:
                            continue
                        wet_p = (y >= 83)
                        pal_p = WET_STONE if wet_p else STONE
                        seam = (y in (80, 84)) or (x in (27, 69) and y % 4 < 2)
                        if seam:
                            put(stone_body, x, y, MORTAR)
                        else:
                            tone_p = (3 if x < 30 else 2) if wet_p else (5 if x < 28 else (3 if x < 48 else 2))
                            put(stone_body, x, y, pal_p[tone_p])
                    elif y <= intrados_y:
                        # True radial wedge voussoirs fanning from arch center `(48, 92)` + overhang shadow under deck!
                        ang_v = math.atan2(92.5 - y, x - 48.0)
                        w_f = (ang_v / math.pi) * 9.0
                        w_id = int(w_f)
                        frac_v = w_f - w_id
                        is_key = (w_id == 4)
                        if y == bot_deck + 1 and y <= extrados_y:
                            put(stone_body, x, y, STONE[1])  # Cantilevered deck slab shadow crease
                        elif abs(frac_v) < 0.11 or abs(1.0 - frac_v) < 0.11:
                            put(stone_body, x, y, MORTAR)
                        else:
                            pal_v = BRIDGE_WARM_STONE if (is_key or w_id % 3 == 1) else STONE
                            lit_v = 5 if (y <= extrados_y + 1 and x <= 52) else (4 if x <= 50 else 3)
                            put(stone_body, x, y, pal_v[lit_v + (1 if is_key and y == extrados_y + 1 else 0)])
                    else:
                        # Deep shadowed wet barrel-vault recess under the south arch lip (`y = intrados_y + 1 .. 88`)
                        vault_row = (y + abs(x - 48) // 5) % 3 == 0
                        put(stone_body, x, y, STONE[0] if (y == intrados_y + 1 or vault_row) else WET_STONE[0 if y < 86 else 1])

            drape_moss(stone_body, 22, 32, 83, 2, 2, seed + 151)
            drape_moss(stone_body, 64, 74, 83, 2, 2, seed + 152)
            drape_moss(stone_body, 23, 29, 22, 3, 4, seed + 41)
            drape_moss(stone_body, 67, 73, 42, 3, 4, seed + 43)
            drape_moss(stone_body, 34, 43, 77, 2, 3, seed + 153)
            _draw_ivy_tendril(stone_body, 37, 78, 8, -0.3, seed + 154)
            _draw_ivy_tendril(stone_body, 58, 78, 7, 0.3, seed + 155)
            draw_wayfarer_lantern_post(stone_body, glow, 26, 62)
            _draw_wayfarer_rune_plaque(stone_body, glow, 70, 62)
            # Feathered pale-aqua river foam/ripple water-lap along submerged south pier & arch base (`y = 88..91`)
            _paint_water_lap(under_layer, over_flora, 22, 74, 88, seed + 195, foam_x0=24, foam_x1=72)
            for gx, gy, big in [(18, 12, False), (22, 16, True), (77, 12, False), (73, 16, True), (25, 6, False), (70, 6, False)]:
                _draw_grass_tuft(over_flora, gx, gy, seed + gx * 5, big=big)
        else:
            # Col 3 (South->North): Cantilevered broken flagstones, sunlit north fracture rim, chasm shadow & hanging moss!
            deck_snap = [row[:] for row in stone_body]
            for x in range(23, 74):
                for y in range(10, 26):
                    if deck_snap[y][x][3] > 0 and deck_snap[y - 1][x][3] == 0:
                        # Crisp sunlit northern fracture rim + cool chasm drop-shadow right above/underneath in water!
                        stone_body[y][x] = _lighten_stone_col(stone_body[y][x], 1)
                        _blend_under(under_layer, x, y - 1, (*BRIDGE_WATER_SH_RGB, 125))
                        _blend_under(under_layer, x, y - 2, (*BRIDGE_WATER_SH_RGB, 68))
                        break

            drape_moss(stone_body, 23, 29, 56, 3, 4, seed + 45)
            drape_moss(stone_body, 67, 73, 24, 2, 3, seed + 47)
            # Hanging moss cushions & trailing tendrils dipping over the fractured northern brink!
            for mx0, mx1, my0 in [(24, 32, 14), (37, 46, 12), (53, 62, 13), (65, 72, 15)]:
                for mx in range(mx0, mx1 + 1):
                    for my in range(my0, my0 + 5):
                        if stone_body[my][mx][3] > 0:
                            put(stone_body, mx, my, MOSS[4 if my == my0 else 3])
                            if stone_body[my - 1][mx][3] == 0 and hsh(mx, my, seed + 161) < 0.65:
                                put(stone_body, mx, my - 1, MOSS[2])
                            break
            _draw_ivy_tendril(stone_body, 24, 16, 7, -0.3, seed + 162)
            _draw_ivy_tendril(stone_body, 72, 17, 7, 0.3, seed + 163)
            draw_wayfarer_lantern_post(stone_body, glow, 26, 40)
            _draw_wayfarer_rune_plaque(stone_body, glow, 70, 40)
            for gx, gy, big in [(17, 86, True), (22, 89, True), (78, 86, True), (73, 89, True), (25, 82, False), (71, 82, False)]:
                _draw_grass_tuft(over_flora, gx, gy, seed + gx * 7, big=big)

        # Suppress `OUT` outline ONLY along shore road mouth, bollard grass toes, and Col 2 submerged waterline!
        for y in range(H):
            d = shore_dy(y)
            for x in range(W):
                if d <= 16 and 28 <= x <= 68:
                    no_outline[y][x] = True
                if d <= 11 and (17 <= x <= 79):
                    no_outline[y][x] = True
                if is_north and y >= 88:
                    no_outline[y][x] = True

    # Run `outline_pass` cleanly on structural masonry ONLY, then composite feathered terrain/water layers!
    framed_stone = outline_pass(stone_body, OUT)
    for y in range(H):
        for x in range(W):
            if stone_body[y][x][3] == 0 and framed_stone[y][x] == OUT and no_outline[y][x]:
                framed_stone[y][x] = CLEAR

    out = [row[:] for row in under_layer]
    alpha_over(out, framed_stone, 0, 0)
    alpha_over(out, over_flora, 0, 0)
    return out, glow.finish()


# ==============================================================================
# 5. Fisher Pier (`fisher_pier.png` & `_glow.png`, 4x1 of 96x96, center (48, 52))
# ==============================================================================
def _paint_piling_water_lap(under_px, over_px, cx: int, wy: int, rx: int, seed: int):
    """Paints cool submerged piling reflection & crisp translucent pale-aqua/foam water-lap ring."""
    for dy in range(0, 5):
        yy = wy + dy
        if not (0 <= yy < len(under_px)):
            continue
        span = rx + 2 + (1 if dy in (1, 2) else 0)
        for dx in range(-span, span + 1):
            xx = cx + dx
            if not (0 <= xx < len(under_px[0])):
                continue
            nd = abs(dx) / max(1.0, float(span))
            if nd > 1.0:
                continue
            # Submerged dark timber/water shadow reflection beneath piling
            sh_a = int((135 if dy <= 1 else (92 if dy == 2 else 48)) * (1.0 - 0.55 * nd))
            _blend_under(under_px, xx, yy, (*BRIDGE_WATER_SH_RGB, sh_a))

            rip = math.sin(dx * 0.85 + seed * 0.7 + dy * 1.6)
            if dy == 0 and nd <= 0.88:
                fa = 188 if rip > -0.15 else 132
                _blend_under(over_px, xx, yy, (*BRIDGE_AQUA_FOAM_RGB, fa))
            elif dy == 1 and nd <= 0.96 and rip > -0.25:
                _blend_under(over_px, xx, yy, (*BRIDGE_AQUA_HI_RGB, 142 if rip > 0.25 else 96))
            elif dy == 2 and 0.25 <= nd <= 1.0 and rip > 0.05:
                _blend_under(over_px, xx, yy, (*BRIDGE_AQUA_MID_RGB, 92))
            elif dy == 3 and 0.35 <= nd <= 0.95 and rip > 0.38:
                _blend_under(over_px, xx, yy, (*BRIDGE_AQUA_HI_RGB, 68))


def _paint_pier_shore_ramp(under_px, over_px, no_outline, col: int, seed: int):
    """Paints a feathered packed-earth, shore-pebble & meadow grass-tuft bank ramp at the shoreward end of each pier."""
    W, H = 96, 96
    if col in (0, 1):
        # Col 0 shore is LEFT (`x = 0..14`), Col 1 shore is RIGHT (`x = 81..95`), deck `y = 40..62`
        is_left = (col == 0)
        for y in range(34, 69):
            dy_c = abs(y - 51.0)
            half_h = 13.5 + 1.8 * math.sin(y * 0.45 + seed)
            if dy_c > half_h + 2.5:
                continue
            for d_sh in range(0, 15):
                x = d_sh if is_left else (W - 1 - d_sh)
                edge_j = (vnoise(x * 0.35, y * 0.32, seed + 17) - 0.5) * 3.2
                reach = d_sh + edge_j - (dy_c / max(1.0, half_h)) * 4.2
                if reach < 1.2:
                    continue
                # Quantized pixel-art alpha bands (no blurry linear smear!)
                a = 255 if reach >= 5.2 else (176 if reach >= 3.0 else 96)
                lit_e = 3.3 - 0.14 * max(0.0, dy_c - 6.0) + (0.45 if y < 51 else -0.25)
                cl = (vnoise(x * 0.42, y * 0.42, seed + 29) - 0.5) * 1.1
                ec = BRIDGE_EARTH[int(clamp(round(lit_e + cl), 0, len(BRIDGE_EARTH) - 1))]
                _blend_under(under_px, x, y, (ec[0], ec[1], ec[2], a))

        # Sunken shore flagstones/pebbles embedded in the earth ramp (`2x2`..`4x3`)
        pebbles = (
            [(4, 44, 3, 2, True), (6, 52, 4, 3, False), (3, 57, 3, 2, False), (7, 41, 3, 2, True), (7, 60, 3, 2, False)]
            if is_left else
            [(89, 44, 3, 2, True), (86, 52, 4, 3, False), (90, 57, 3, 2, False), (86, 41, 3, 2, True), (86, 60, 3, 2, False)]
        )
        for px0, py0, pw, ph, warm in pebbles:
            _draw_stone_block(under_px, px0, py0, px0 + pw - 1, py0 + ph - 1, 4.4, seed + px0 * 3 + py0, warm=warm, mortar_r=False, mortar_b=False)

        # Meadow grass tufts framing the pier-to-bank transition (`over_px`, outside `outline_pass`)
        tufts = (
            [(7, 39, True), (4, 42, False), (9, 64, True), (5, 62, False), (2, 49, False), (11, 38, False), (11, 65, False)]
            if is_left else
            [(88, 39, True), (91, 42, False), (86, 64, True), (90, 62, False), (93, 49, False), (84, 38, False), (84, 65, False)]
        )
        for gx, gy, big in tufts:
            _draw_grass_tuft(over_px, gx, gy, seed + gx * 7 + gy, big=big)

        # Suppress harsh `OUT` outline across shore mouth (`x <= 12` or `x >= 83`)
        for y in range(36, 67):
            for x in (range(0, 13) if is_left else range(83, W)):
                no_outline[y][x] = True
    else:
        # Col 2 shore is TOP (`y = 0..14`), Col 3 shore is BOTTOM (`y = 81..95`), deck `x = 34..62`
        is_top = (col == 2)
        for x in range(28, 69):
            dx_c = abs(x - 48.0)
            half_w = 16.0 + 1.8 * math.sin(x * 0.42 + seed)
            if dx_c > half_w + 2.5:
                continue
            for d_sh in range(0, 15):
                y = d_sh if is_top else (H - 1 - d_sh)
                edge_j = (vnoise(x * 0.32, y * 0.35, seed + 23) - 0.5) * 3.2
                reach = d_sh + edge_j - (dx_c / max(1.0, half_w)) * 4.2
                if reach < 1.2:
                    continue
                a = 255 if reach >= 5.2 else (176 if reach >= 3.0 else 96)
                lit_e = 3.3 - 0.12 * max(0.0, dx_c - 8.0) + (0.45 if x < 48 else -0.25)
                cl = (vnoise(x * 0.42, y * 0.42, seed + 31) - 0.5) * 1.1
                ec = BRIDGE_EARTH[int(clamp(round(lit_e + cl), 0, len(BRIDGE_EARTH) - 1))]
                _blend_under(under_px, x, y, (ec[0], ec[1], ec[2], a))

        pebbles = (
            [(37, 4, 3, 2, True), (46, 5, 4, 3, False), (55, 4, 3, 2, True), (34, 7, 3, 2, False), (59, 7, 3, 2, False)]
            if is_top else
            [(37, 89, 3, 2, True), (46, 87, 4, 3, False), (55, 89, 3, 2, True), (34, 86, 3, 2, False), (59, 86, 3, 2, False)]
        )
        for px0, py0, pw, ph, warm in pebbles:
            _draw_stone_block(under_px, px0, py0, px0 + pw - 1, py0 + ph - 1, 4.4, seed + px0 + py0 * 3, warm=warm, mortar_r=False, mortar_b=False)

        tufts = (
            [(32, 8, True), (35, 5, False), (64, 8, True), (61, 5, False), (48, 2, False), (30, 12, False), (66, 12, False)]
            if is_top else
            [(32, 88, True), (35, 91, False), (64, 88, True), (61, 91, False), (48, 93, False), (30, 84, False), (66, 84, False)]
        )
        for gx, gy, big in tufts:
            _draw_grass_tuft(over_px, gx, gy, seed + gx * 5 + gy, big=big)

        for y in (range(0, 13) if is_top else range(83, H)):
            for x in range(30, 67):
                no_outline[y][x] = True


def draw_pier_props(
    px,
    glow: GlowMap,
    lx: int,
    ly: int,
    rx_rope: int,
    ry_rope: int,
    cx_creel: int,
    cy_creel: int,
    hook_dir: int = 1,
):
    """Adds braided hemp mooring rope coil + tail, diagonal-weave wicker fisher creel, and chamfered hook-lantern!"""
    # 1) Soft contact shadow under rope coil & creel so props sit firmly on planks
    for dy in (-2, -1, 0, 1, 2, 3):
        for dx in (-4, -3, -2, -1, 0, 1, 2, 3, 4):
            if dx * dx + dy * dy <= 18 and px[ry_rope + dy + 1][rx_rope + dx][3] > 0:
                put(px, rx_rope + dx, ry_rope + dy + 1, PLANK[1])

    # Braided concentric hemp mooring rope coil (`4.2 x 3.4 px`) + trailing rope tail!
    for dy in range(-3, 4):
        for dx in range(-4, 5):
            r = math.hypot(dx * 0.88, dy * 1.12)
            if r <= 3.85:
                if r < 0.95:
                    col_r = ROPE[0]  # Hollow dark center of coil
                else:
                    ring = int(r * 1.55) % 2
                    twist = ((dx + dy * 2) % 3 == 0)
                    if ring == 0:
                        col_r = ROPE[4 if (dy <= 0 and twist) else (3 if dy <= 1 else 2)]
                    else:
                        col_r = ROPE[2 if (dy < 0 and twist) else (1 if dy <= 1 else 0)]
                put(px, rx_rope + dx, ry_rope + dy, col_r)
    # Loose trailing hemp tail curving out from the coil across adjacent planks
    for k, (tdx, tdy) in enumerate([(4, 2), (5, 3), (6, 3), (7, 2)]):
        put(px, rx_rope + tdx * (-1 if hook_dir < 0 else 1), ry_rope + tdy, ROPE[3 if k < 2 else 2])

    # 2) Woven Wicker Fisher Creel (`cx_creel, cy_creel`) with diagonal basket weave, hinged lid, leather strap & brass buckle!
    for dy in range(-3, 5):
        for dx in range(-4, 5):
            if dy == 4:
                if abs(dx) <= 3:
                    put(px, cx_creel + dx, cy_creel + dy, TIMBER[0])  # Base grounding shadow
                continue
            if abs(dx) == 4 and dy in (-3, 3):
                continue  # Rounded basket corners
            if dy == -3:
                # Rolled willow lid rim
                col_c = SACK[5 if dx <= 0 else (3 if dx <= 2 else 2)]
            elif dy == -2:
                # Lid underside lip crease
                col_c = TIMBER[1 if dx > 0 else 2]
            elif dx == 0 and dy >= -2:
                # Vertical dark-leather closure strap + gleaming brass buckle at `dy == 0`!
                col_c = BRASS[3] if dy == 0 else TIMBER[1 if dy > 0 else 2]
            else:
                # Crisp diagonal cross-hatch wicker basket weave!
                weave_up = ((dx + dy) % 2 == 0)
                lit_c = (4 if dx < 0 else (3 if dx <= 2 else 2)) + (1 if (weave_up and dx <= 1 and dy < 2) else (-1 if not weave_up else 0))
                col_c = SACK[int(clamp(lit_c, 0, 5))]
            put(px, cx_creel + dx, cy_creel + dy, col_c)
    # Curved willow carry handle arch on top of creel lid
    for dx in (-1, 0, 1):
        put(px, cx_creel + dx, cy_creel - 4, ROPE[4 if dx <= 0 else 2])

    # 3) Chamfered Oak Lantern Post (`(lx, ly)` up to `(lx, ly - 13)`), iron brace, curved hook & warm amber lantern!
    put(px, lx - 2, ly, TIMBER[2])
    put(px, lx + 2, ly, TIMBER[0])  # Post base collar
    for dy in range(0, 14):
        yy = ly - dy
        if dy == 13:
            # Carved pyramidal post finial cap
            put(px, lx - 1, yy, TIMBER[7])
            put(px, lx, yy, TIMBER[6])
            put(px, lx + 1, yy, TIMBER[3])
        else:
            grain_p = -1 if (dy % 5 == 2) else 0
            put(px, lx - 1, yy, TIMBER[max(3, 6 + grain_p)])
            put(px, lx, yy, TIMBER[max(2, 4 + grain_p)])
            put(px, lx + 1, yy, TIMBER[1])
            if dy in (2, 10):
                # Wrought-iron post collars
                put(px, lx - 1, yy, IRON[3])
                put(px, lx, yy, IRON[2])
                put(px, lx + 1, yy, IRON[1])

    # Forged iron hook arm + diagonal scroll brace (`hook_dir = +1` right or `-1` left)
    for step in range(1, 5):
        put(px, lx + step * hook_dir, ly - 12, IRON[4 if step <= 2 else 3])
    put(px, lx + 2 * hook_dir, ly - 11, IRON[2])
    put(px, lx + 1 * hook_dir, ly - 10, IRON[2])  # Diagonal scroll strut

    hx, hy = lx + 4 * hook_dir, ly - 9
    put(px, hx, hy - 3, IRON[3])  # Suspension ring
    put(px, hx, hy - 2, IRON[4])  # Lantern chimney cap peak
    for dx in (-2, -1, 0, 1, 2):
        if abs(dx) <= 2:
            put(px, hx + dx, hy - 1, IRON[4 if dx * hook_dir <= 0 else 2])  # Wide rain hood
        if abs(dx) <= 1:
            put(px, hx + dx, hy + 2, IRON[2 if dx <= 0 else 1])  # Weighted iron base pan
    # Cage side bars
    for dy_g in (0, 1):
        put(px, hx - 2, hy + dy_g, IRON[2])
        put(px, hx + 2, hy + dy_g, IRON[1])
    # Warm-amber glowing lantern glass (`3x2` core + soft night halo)
    glow.emit(px, hx - 1, hy, PIER_G2, PIER_G2, halo=1)
    glow.emit(px, hx, hy, PIER_G3, PIER_G3, halo=2)
    glow.emit(px, hx + 1, hy, PIER_G1, PIER_G2, halo=1)
    glow.emit(px, hx - 1, hy + 1, PIER_G1, PIER_G2, halo=1)
    glow.emit(px, hx, hy + 1, PIER_G2, PIER_G3, halo=2)
    glow.emit(px, hx + 1, hy + 1, AMBER_D, PIER_G1, halo=1)


def _draw_pier_piling(px, cx: int, y_top: int, y_bot: int, waterline_y: int, seed: int, rope_y: int = -1):
    """Draws a weathered round oak piling with concentric end-grain cap, bark fissures, rope lashing & wet algae base."""
    for py in range(y_top, y_bot + 1):
        for dx in (-2, -1, 0, 1, 2):
            if py == y_top and abs(dx) == 2:
                continue  # Rounded bevel top corners
            if py == y_top:
                col_p = PLANK[6] if dx <= 0 else PLANK[4]
            elif py == y_top + 1:
                col_p = TIMBER[6 if dx < 0 else (3 if dx == 0 else 2)]  # End-grain ring
            elif rope_y > 0 and rope_y <= py <= rope_y + 1:
                twist = ((dx + py) % 2 == 0)
                col_p = ROPE[4 if (dx < 0 and twist) else (3 if dx <= 0 else (2 if dx == 1 else 1))]
            elif py >= waterline_y:
                # Wet river-moss & dark waterlogged algae band!
                wet_band = py - waterline_y
                if wet_band == 0 and (dx + seed) % 2 == 0:
                    col_p = MOSS[3 if dx < 0 else 1]
                else:
                    col_p = MOSS[2 if dx < 0 else (1 if dx == 0 else 0)]
            else:
                fissure = -1 if (dx == 0 and (py + seed) % 5 == 0) else 0
                base_t = 5 if dx == -2 else (4 if dx == -1 else (3 if dx == 0 else (2 if dx == 1 else 0)))
                col_p = TIMBER[max(0, base_t + fissure)]
            put(px, cx + dx, py, col_p)


def build_fisher_pier_variant(col: int):
    W, H = 96, 96
    under_layer = blank(W, H)
    body = blank(W, H)
    over_layer = blank(W, H)
    no_outline = [[False] * W for _ in range(H)]
    glow = GlowMap(W, H)
    seed = 2801 + col * 37

    # 1) Feathered shoreward packed-earth, pebble & grass-tuft approach ramp
    _paint_pier_shore_ramp(under_layer, over_layer, no_outline, col, seed)

    # Irregular plank width pattern (`3, 4, 5 px`) to break up mechanical uniform grid!
    plank_widths = [4, 5, 3, 4, 5, 4, 3, 5, 4, 4, 5, 3, 4, 5, 4, 3, 5, 4, 4, 5, 4]

    if col in (0, 1):
        # Col 0: Extends East (`x = 8..86`, deck `y = 40..62`), shore LEFT (`x = 0..14`), tip RIGHT
        # Col 1: Extends West (`x = 10..88`, deck `y = 40..62`), shore RIGHT (`x = 81..95`), tip LEFT
        x0, x1 = (8, 86) if col == 0 else (10, 88)
        y0, y1 = 40, 62
        piling_xs = [x0 + 6, x0 + 26, x0 + 49, x1 - 5]
        water_pilings = piling_xs[1:] if col == 0 else piling_xs[:-1]

        # Diagonal timber sway/cross-bracing & heavy oak ledger beam beneath deck (`y = 62..72`)
        for i_b in range(len(piling_xs) - 1):
            pa, pb = piling_xs[i_b], piling_xs[i_b + 1]
            mid_x = (pa + pb) // 2
            _draw_grained_beam(body, pa + 2, 64, mid_x - 3, 70, 0.95, seed + i_b * 7)
            _draw_grained_beam(body, pb - 2, 64, mid_x + 3, 70, 0.95, seed + i_b * 7 + 3)

        for x in range(x0 + 1, x1):
            put(body, x, 63, TIMBER[3 if (x % 9 != 0) else 1])
            put(body, x, 64, TIMBER[1])
            put(body, x, 65, TIMBER[0])

        # Back piling caps (`y = 35..41`) & front pilings descending into river (`y = 59..75`)
        for idx_p, px_p in enumerate(piling_xs):
            in_water = (px_p in water_pilings)
            _draw_pier_piling(body, px_p, 35, 41, waterline_y=99, seed=seed + idx_p * 11)
            bot_y = 75 if in_water else 70
            rope_y = 61 if idx_p in (1, 2, 3 if col == 0 else 0) else -1
            _draw_pier_piling(body, px_p, 59, bot_y, waterline_y=(70 if in_water else 68), seed=seed + idx_p * 13, rope_y=rope_y)
            if in_water:
                _paint_piling_water_lap(under_layer, over_layer, px_p, bot_y - 1, rx=3, seed=seed + idx_p * 19)
                for yy in range(bot_y - 1, bot_y + 3):
                    for xx in range(px_p - 4, px_p + 5):
                        if 0 <= xx < W and 0 <= yy < H:
                            no_outline[yy][xx] = True

        # Heavy shoreward oak bank sill-beam anchoring the pier mouth into the earth ramp
        sill_x = x0 - 1 if col == 0 else x1
        for py in range(y0 - 1, y1 + 3):
            put(body, sill_x, py, TIMBER[5 if py < 51 else 3])
            put(body, sill_x + (-1 if col == 0 else 1), py, TIMBER[3 if py < 51 else 1])

        # Transverse weathered wooden deck planks (`3..5 px` wide, grain streaks, knots, sun-bleached walkway & iron nails)
        p_cur = x0
        p_idx = 0
        while p_cur <= x1 - 2:
            pw = plank_widths[p_idx % len(plank_widths)]
            if p_cur + pw > x1 + 1:
                pw = x1 + 1 - p_cur
            if pw < 2:
                break
            jit_t = int(round((hsh(p_idx, 0, seed) - 0.5) * 2.4))
            jit_b = int(round((hsh(p_idx, 1, seed) - 0.5) * 2.4))
            tone_b = (hsh(p_idx, 2, seed) - 0.5) * 1.05
            silvered = (hsh(p_idx, 6, seed) < 0.34)
            knot_y = (45 + int(hsh(p_idx, 7, seed) * 12)) if (pw >= 4 and hsh(p_idx, 8, seed) < 0.28) else -1
            py_top, py_bot = y0 + jit_t, y1 + jit_b

            for py in range(py_top, py_bot + 1):
                center_wear = max(0.0, 1.0 - abs(py - 51.0) / 6.5) * 0.65
                for dx in range(pw):
                    px_x = p_cur + dx
                    if px_x > x1:
                        continue
                    if dx == pw - 1 and px_x < x1:
                        # Inter-plank gap (deep shadow over water / stringers)
                        col_w = TIMBER[0] if py not in (43, 59) else IRON[0]
                    elif py == py_bot:
                        # 1px 3/4 front plank thickness end-grain lip!
                        col_w = TIMBER[2 if dx > 0 else 3]
                    elif dx == 0 or py == py_top:
                        # Top-left sunlit plank bevel edge
                        col_w = DRIFTWOOD[4] if (silvered and py < 54) else PLANK[6 if py < 52 else 5]
                    elif knot_y > 0 and abs(py - knot_y) <= 1 and dx in (1, 2):
                        col_w = TIMBER[0] if (py == knot_y and dx == 1) else PLANK[2]
                    else:
                        # Longitudinal vertical wood-grain streaks (`fbm` stretched along `y`)
                        g = (fbm(px_x * 1.35, py * 0.22, seed + 5) - 0.5) * 1.35
                        idx = int(clamp(round(3.45 + tone_b + center_wear + g), 1, 6))
                        if silvered and center_wear > 0.25:
                            col_w = DRIFTWOOD[min(4, max(1, idx - 1))]
                        else:
                            col_w = PLANK[idx]
                    put(body, px_x, py, col_w)

                # Twin rows of oxidized iron nail heads (`y = 43` and `y = 58`)
                if py in (43, 58) and pw >= 3:
                    nail_x = p_cur + (1 if pw <= 4 else 2)
                    if nail_x <= x1:
                        put(body, nail_x, py, IRON[1])
                        if py + 1 < py_bot:
                            put(body, nail_x, py + 1, RUST[1] if (p_idx % 3 == 0) else PLANK[2])

            p_cur += pw
            p_idx += 1

        # Damp moss cushions clinging to outer plank corners
        drape_moss(body, x0 + 16, x0 + 25, y0, 2, 2, seed + 11)
        drape_moss(body, x0 + 44, x0 + 52, y1 - 1, 2, 1, seed + 13)
        if col == 0:
            draw_pier_props(body, glow, lx=x1 - 6, ly=y0 + 3, rx_rope=x1 - 15, ry_rope=y1 - 5, cx_creel=x0 + 15, cy_creel=y0 + 4, hook_dir=1)
        else:
            draw_pier_props(body, glow, lx=x0 + 6, ly=y0 + 3, rx_rope=x0 + 15, ry_rope=y1 - 5, cx_creel=x1 - 15, cy_creel=y0 + 4, hook_dir=-1)

    else:
        # Col 2: Extends South (`x = 34..62`, deck `y = 8..86`), shore TOP (`y = 0..14`), tip BOTTOM
        # Col 3: Extends North (`x = 34..62`, deck `y = 10..88`), shore BOTTOM (`y = 81..95`), tip TOP
        x0, x1 = 34, 62
        y0, y1 = (8, 86) if col == 2 else (10, 88)
        piling_ys = [y0 + 8, y0 + 28, y0 + 50, y1 - 6]
        water_pilings_y = piling_ys[1:] if col == 2 else piling_ys[:-1]

        # Side pilings along left (`x = 32`) and right (`x = 64`) + water-lap rings on riverward stations!
        for idx_p, py_p in enumerate(piling_ys):
            in_water = (py_p in water_pilings_y)
            bot_dy = 9 if in_water else 6
            for side_i, side_x in enumerate((x0 - 2, x1 + 2)):
                rope_y = (py_p + 2) if (in_water and idx_p in (1, 2)) else -1
                _draw_pier_piling(
                    body,
                    side_x,
                    py_p - 3,
                    py_p + bot_dy,
                    waterline_y=(py_p + 5 if in_water else py_p + 6),
                    seed=seed + idx_p * 11 + side_i * 5,
                    rope_y=rope_y,
                )
                if in_water:
                    _paint_piling_water_lap(under_layer, over_layer, side_x, py_p + bot_dy - 1, rx=3, seed=seed + idx_p * 17 + side_i * 3)
                    for yy in range(py_p + bot_dy - 1, py_p + bot_dy + 3):
                        for xx in range(side_x - 4, side_x + 5):
                            if 0 <= xx < W and 0 <= yy < H:
                                no_outline[yy][xx] = True

        # On Col 2 (South tip at `y1 = 86`), show 3/4 front cross-brace & twin end-pilings descending into river (`y = 85..91`)!
        if col == 2:
            _draw_grained_beam(body, x0 + 1, 87, x1 - 1, 87, 0.95, seed + 91)
            _draw_grained_beam(body, x0 + 4, 86, 46, 88, 0.75, seed + 92)
            _draw_grained_beam(body, x1 - 4, 86, 50, 88, 0.75, seed + 93)
            for end_x in (x0 + 4, x1 - 4):
                _draw_pier_piling(body, end_x, 85, 91, waterline_y=89, seed=seed + end_x)
                _paint_piling_water_lap(under_layer, over_layer, end_x, 90, rx=3, seed=seed + end_x + 7)
            for yy in range(89, 95):
                for xx in range(x0 - 2, x1 + 3):
                    if 0 <= xx < W and 0 <= yy < H:
                        no_outline[yy][xx] = True

        # Heavy shoreward oak bank sill-beam anchoring the pier mouth into the earth ramp
        sill_y = y0 - 1 if col == 2 else y1
        for px_x in range(x0 - 1, x1 + 2):
            put(body, px_x, sill_y, TIMBER[5 if px_x < 48 else 3])
            put(body, px_x, sill_y + (-1 if col == 2 else 1), TIMBER[3 if px_x < 48 else 1])

        # Horizontal cross-planks (`3..5 px` tall, horizontal wood grain, knots, silvered center walkway & twin nail rows)
        p_cur = y0
        p_idx = 0
        while p_cur <= y1 - 2:
            ph = plank_widths[p_idx % len(plank_widths)]
            if p_cur + ph > y1 + 1:
                ph = y1 + 1 - p_cur
            if ph < 2:
                break
            jit_l = int(round((hsh(p_idx, 3, seed) - 0.5) * 2.4))
            jit_r = int(round((hsh(p_idx, 4, seed) - 0.5) * 2.4))
            tone_b = (hsh(p_idx, 5, seed) - 0.5) * 1.05
            silvered = (hsh(p_idx, 6, seed + 3) < 0.34)
            knot_x = (39 + int(hsh(p_idx, 7, seed + 3) * 18)) if (ph >= 4 and hsh(p_idx, 8, seed + 3) < 0.28) else -1
            px_left, px_right = x0 + jit_l, x1 + jit_r

            for dy in range(ph):
                py = p_cur + dy
                if py > y1:
                    continue
                for px_x in range(px_left, px_right + 1):
                    center_wear = max(0.0, 1.0 - abs(px_x - 48.0) / 8.0) * 0.65
                    if dy == ph - 1 and py < y1:
                        col_w = TIMBER[0] if px_x not in (x0 + 3, x1 - 3) else IRON[0]
                    elif px_x == px_right:
                        col_w = TIMBER[2]
                    elif dy == 0 or px_x == px_left:
                        col_w = DRIFTWOOD[4] if (silvered and px_x < 52) else PLANK[6 if px_x < 50 else 5]
                    elif knot_x > 0 and abs(px_x - knot_x) <= 1 and dy in (1, 2):
                        col_w = TIMBER[0] if (px_x == knot_x and dy == 1) else PLANK[2]
                    else:
                        # Longitudinal horizontal wood-grain streaks (`fbm` stretched along `x`)
                        g = (fbm(px_x * 0.22, py * 1.35, seed + 9) - 0.5) * 1.35
                        idx = int(clamp(round(3.45 + tone_b + center_wear + g), 1, 6))
                        if silvered and center_wear > 0.25:
                            col_w = DRIFTWOOD[min(4, max(1, idx - 1))]
                        else:
                            col_w = PLANK[idx]
                    put(body, px_x, py, col_w)

                # Twin rows of oxidized iron nail heads along side stringers (`x0 + 3` & `x1 - 3`)
                if dy == 1 and ph >= 3:
                    for nx in (x0 + 3, x1 - 3):
                        put(body, nx, py, IRON[1])
                        if nx + 1 < px_right:
                            put(body, nx + 1, py, RUST[1] if (p_idx % 3 == 0) else PLANK[2])

            p_cur += ph
            p_idx += 1

        drape_moss(body, x0, x0 + 6, y0 + 20, 2, 2, seed + 19)
        drape_moss(body, x1 - 6, x1, y0 + 46, 2, 2, seed + 23)
        if col == 2:
            # Tip at South (`y1 = 86`)
            draw_pier_props(body, glow, lx=x1 - 3, ly=y1 - 3, rx_rope=x0 + 6, ry_rope=y1 - 7, cx_creel=x1 - 5, cy_creel=y0 + 16, hook_dir=1)
        else:
            # Tip at North (`y0 = 10`, keep lantern post starting at `y = 20` so `ly - 13 = 7 >= 2` stays well inside frame!)
            draw_pier_props(body, glow, lx=x1 - 4, ly=y0 + 10, rx_rope=x0 + 6, ry_rope=y0 + 8, cx_creel=x1 - 5, cy_creel=y1 - 16, hook_dir=1)

    framed = outline_pass(body, OUT)
    for y in range(H):
        for x in range(W):
            if body[y][x][3] == 0 and framed[y][x] == OUT and no_outline[y][x]:
                framed[y][x] = CLEAR

    out = [row[:] for row in under_layer]
    alpha_over(out, framed, 0, 0)
    alpha_over(out, over_layer, 0, 0)
    return out, glow.finish()


# ==============================================================================
# 6. Reed Rowboat (`reed_rowboat.png`, 2 cols x 1 row of 64x48, center (32, 28))
# ==============================================================================
def _draw_reed_stalk(px, base_x: int, base_y: int, height: int, lean: float, bend: float, tone_shift: int, cattail: bool, fluff: bool):
    """Draws a gracefully curved lake reed stalk with tapering leaf blade and optional velvety cattail seed head."""
    for k in range(height):
        tk = k / max(1.0, float(height - 1))
        xx = int(round(base_x + lean * k + bend * (tk * tk) * height * 0.35))
        yy = base_y - k
        idx = int(clamp(tone_shift + int(tk * 4.2), 0, 5))
        put(px, xx, yy, REED[idx])
        # Side leaf offshoot mid-stalk
        if k == height // 2 and height >= 11:
            ldir = 1 if lean >= 0 else -1
            put(px, xx + ldir, yy - 1, REED[min(5, idx + 1)])
            put(px, xx + ldir * 2, yy - 2, REED[min(5, idx + 2)])
        if cattail and height - 5 <= k <= height - 2:
            # Cylindrical dark-brown cattail head (`2px` wide with sunlit left highlight & spike tip!)
            put(px, xx, yy, TIMBER[3 if k >= height - 3 else 2])
            put(px, xx + 1, yy, TIMBER[1])
            if fluff and k == height - 2:
                put(px, xx - 1, yy, SACK[5])
                put(px, xx, yy - 1, REED[5])
        elif cattail and k == height - 1:
            put(px, xx, yy, REED[4])


def build_reed_rowboat():
    FW, FH = 64, 48
    sheet = blank(FW * 2, FH)

    for col in range(2):
        unsearched = (col == 0)
        under_layer = blank(FW, FH)
        body = blank(FW, FH)
        over_layer = blank(FW, FH)
        no_outline = [[False] * FW for _ in range(FH)]
        seed = 3101 + col

        # 1) Back-layer green-gold swaying lake reeds & cattails behind the rowboat (`y = 4..28, x = 7..57`)
        back_specs = [
            (9, 27, 15, -0.14, -0.10, 0, False, False),
            (12, 27, 19, 0.12, 0.14, 1, True, False),
            (15, 26, 14, 0.18, 0.08, 0, False, False),
            (19, 26, 16, -0.08, -0.12, 1, False, False),
            (23, 25, 12, 0.14, 0.10, 0, False, False),
            (42, 24, 13, -0.12, -0.08, 0, False, False),
            (46, 25, 19, 0.10, 0.15, 1, True, True),
            (50, 26, 15, 0.18, 0.12, 1, False, False),
            (53, 27, 17, -0.10, -0.14, 0, True, False),
            (56, 28, 12, 0.20, 0.10, 1, False, False),
        ]
        for bx_r, by_r, rh, ln, bd, ts, cat, flf in back_specs:
            _draw_reed_stalk(body, bx_r, by_r, rh, ln, bd, ts, cat, flf)

        # 2) Weathered Clinker-Built (Lapstrake) Oak Rowboat Hull (`cx = 32, cy = 28`, tilted ~ -10 deg:
        #    pointed oak stem-post bow at upper-right `(53, 22)`, square transom stern at lower-left `(12, 30)`)
        ca, sa = math.cos(-0.18), math.sin(-0.18)
        waterline_pts = []
        for y in range(15, 41):
            for x in range(9, 57):
                dx0, dy0 = x - 32.0, y - 27.5
                u = dx0 * ca - dy0 * sa
                v = dx0 * sa + dy0 * ca
                if u < -19.5 or u > 20.8:
                    continue
                if u > 4.0:
                    hb = 8.5 * max(0.0, 1.0 - ((u - 4.0) / 17.0) ** 1.42)
                elif u < -10.0:
                    hb = 8.5 * (1.0 - 0.24 * ((-10.0 - u) / 9.5))
                else:
                    hb = 8.5

                side_drop = 5.6 * (1.0 - 0.34 * abs(u / 21.5))
                if -hb <= v <= hb:
                    # Raised curved oak gunwale rail & solid bow stem / stern transom cap!
                    if u >= 18.6:
                        put(body, x, y, TIMBER[6 if v <= 0 else 4])  # Carved oak stem-post
                    elif u <= -18.0:
                        put(body, x, y, TIMBER[4 if v < 0 else 2])  # Stern transom board
                    elif v <= -hb + 1.35:
                        # Sunlit far/north gunwale rail + inner shadow lip
                        put(body, x, y, PLANK[6] if v <= -hb + 0.65 else TIMBER[2])
                    elif v >= hb - 1.35:
                        # Near/south gunwale cap catching top-left light
                        put(body, x, y, PLANK[5 if u < 6 else 6] if v <= hb - 0.65 else TIMBER[4])
                    else:
                        # Cockpit interior: two wooden thwarts (`u ~ -6.4` & `u ~ +5.0`) + iron knees, curved oak ribs & slatted floorboards!
                        on_stern_thwart = abs(u + 6.4) <= 1.65
                        on_bow_thwart = abs(u - 5.0) <= 1.65
                        if on_stern_thwart or on_bow_thwart:
                            if abs(v) >= hb - 2.3:
                                col_i = IRON[3 if v < 0 else 1]  # Forged iron thwart knee bracket!
                            elif (u < -7.3 and on_stern_thwart) or (u < 4.1 and on_bow_thwart):
                                col_i = PLANK[6 if v < 1.5 else 5]  # Sunlit thwart front/left bevel
                            else:
                                grain_t = 0.45 if int(v + 9) % 3 == 0 else -0.2
                                col_i = PLANK[int(clamp(round(4.3 - 0.12 * v + grain_t), 2, 5))]
                            put(body, x, y, col_i)
                        else:
                            # Cast shadow immediately behind thwarts (`u` right of bench)
                            in_thwart_sh = (-4.7 < u <= -3.5) or (6.7 < u <= 7.9)
                            rib_phase = (u + 18.0) % 4.6
                            if rib_phase < 0.88:
                                # Curved interior oak hull ribs (`TIMBER`)
                                col_i = TIMBER[1 if in_thwart_sh else (4 if (rib_phase < 0.42 and v < 2.5) else 2)]
                            else:
                                # Longitudinal slatted bilge floorboards (`v`-aligned) + tiny bilge puddle in belly!
                                slat = int(round((v + 9.0) * 1.15)) % 3
                                if slat == 0:
                                    col_i = WET_STONE[2] if (abs(u + 0.8) < 2.8 and abs(v - 1.0) < 2.2) else TIMBER[0]
                                else:
                                    base_fl = (2 if in_thwart_sh else 3) + (1 if (slat == 1 and v > -1.0 and not in_thwart_sh) else 0)
                                    col_i = PLANK[int(clamp(base_fl, 1, 4))]
                            put(body, x, y, col_i)
                elif hb < v <= hb + side_drop:
                    # Exterior 3/4 clinker (lapstrake) oak hull planks (3 overlapping strakes + mossy wet waterline!)
                    depth_s = v - hb
                    strake_f = (depth_s / max(1.0, side_drop)) * 3.2
                    strake_i = int(strake_f)
                    frac_s = strake_f - strake_i
                    lit_u = 1 if (-4.0 <= u <= 12.0) else 0
                    if depth_s >= side_drop - 1.25:
                        # Submerged mossy waterline along hull bottom
                        put(body, x, y, MOSS[3 if (u > -2 and (x + y) % 2 == 0) else (2 if (x + y) % 3 else 1)])
                        waterline_pts.append((x, y))
                    elif frac_s < 0.24:
                        # Crisp clinker lap shadow crease beneath overlapping upper strake!
                        put(body, x, y, TIMBER[0 if strake_i >= 1 else 1])
                    elif frac_s < 0.52:
                        # Sunlit top bevel of each lapstrake oak board
                        put(body, x, y, TIMBER[min(6, 4 + lit_u - (1 if strake_i == 2 else 0))])
                    else:
                        grain_h = 1 if int(u + 22) % 6 == 0 else 0
                        put(body, x, y, TIMBER[int(clamp(3 + lit_u - strake_i + grain_h, 1, 5))])

        # Gleaming brass U-oarlocks mounted on both gunwales (`u ~ -1.2`) + iron bow ring & trailing painter rope!
        for ox_l, oy_l, hi_l in [(29, 20, True), (32, 34, False)]:
            put(body, ox_l, oy_l - 1, BRASS[4 if hi_l else 3])
            put(body, ox_l + 1, oy_l - 1, BRASS[3 if hi_l else 2])
            put(body, ox_l, oy_l, IRON[2])
        # Forged iron bow mooring ring at `(53, 23)` + trailing hemp painter rope dipping into reeds
        put(body, 53, 23, IRON[4])
        put(body, 54, 24, IRON[2])
        for rx_p, ry_p, ri in [(54, 25, 3), (55, 26, 2), (56, 28, 2), (56, 29, 1)]:
            put(body, rx_p, ry_p, ROPE[ri])

        # Damp moss cushions clinging to weathered stern transom & mid-hull
        drape_moss(body, 13, 20, 25, 2, 2, seed + 7)
        drape_moss(body, 35, 42, 32, 2, 1, seed + 9)

        # 3) Detailed Wooden Oar resting diagonally across thwarts (`(16, 30)` -> `(41, 24)`)
        #    with rounded handle grip, dark leather oarlock collar sleeve, turned shaft & ribbed paddle blade!
        for i in range(27):
            t = i / 26.0
            ox = int(round(16.0 + 25.0 * t))
            oy = int(round(30.0 - 6.0 * t))
            if t < 0.10:
                # Carved oar grip handle
                put(body, ox, oy, SACK[5])
                put(body, ox, oy + 1, TIMBER[2])
            elif 0.34 <= t <= 0.46:
                # Stitched dark-leather oarlock wear sleeve + tiny brass tack
                put(body, ox, oy, BRASS[3] if abs(t - 0.40) < 0.025 else TIMBER[2])
                put(body, ox, oy + 1, TIMBER[0])
            elif t < 0.66:
                # Turned warm ash/oak shaft
                put(body, ox, oy, SACK[4 if t < 0.52 else 5])
                put(body, ox, oy + 1, SACK[2])
            else:
                # Tapered flat paddle blade with central spine ridge & wet tip sheen
                put(body, ox, oy - 1, SACK[5 if t < 0.90 else 4])
                put(body, ox, oy, SACK[4] if t < 0.88 else MOSS[3])  # Spine + slight wet algae tip
                put(body, ox, oy + 1, SACK[2 if t < 0.90 else 1])
                if 0.74 <= t <= 0.92:
                    put(body, ox, oy + 2, TIMBER[2])

        # 4) Col 0 (Unsearched): Stitched Canvas Fisher Satchel (`cx = 43, cy = 24`) with angled 3/4 flap,
        #    central buckled leather strap & gleaming sunlit brass clasp!
        #    Col 1 (Searched): Satchel taken — exposed bow ribs/slats + unbuckled loose twine remnant!
        if unsearched:
            for dy in range(-3, 4):
                for dx in range(-4, 5):
                    if abs(dx) == 4 and abs(dy) == 3:
                        continue
                    sx, sy = 43 + dx, 24 + dy
                    if dy == 3:
                        put(body, sx, sy, TIMBER[0])  # Grounding shadow in bow
                        continue
                    flap_y = 0 if dx <= 0 else 1  # Angled 3/4 canvas flap overhang
                    if dx == 0 and dy >= -2:
                        # Central vertical dark-leather closure strap
                        col_s = TIMBER[2 if dy <= 0 else 1]
                    elif dy == flap_y and abs(dx) <= 3:
                        # Angled folded flap shadow lip
                        col_s = SACK[1 if dx > 0 else 2]
                    elif dy == -3 or (dx == -4 and dy <= 1):
                        # Sunlit top-left fold of canvas pack
                        col_s = SACK[5 if dx <= 1 else 4]
                    else:
                        weave_s = 0.35 if ((dx + dy) % 2 == 0) else -0.2
                        lit_s = 4.2 - 0.24 * dx - 0.30 * dy + weave_s
                        col_s = SACK[int(clamp(round(lit_s), 1, 5))]
                    put(body, sx, sy, col_s)
            # Gleaming sunlit brass clasp & side D-ring so players spot the interactive loot immediately!
            put(body, 43, 24, AMBER_H)
            put(body, 42, 24, BRASS[3])
            put(body, 43, 25, BRASS[2])
            put(body, 39, 23, BRASS[3])
        else:
            # Loose unbuckled coil of hemp twine & tiny brass ring left behind in empty bow
            for rdx, rdy, ri in [(-1, 1, 3), (0, 1, 2), (1, 1, 1), (0, 2, 2), (2, 0, 3)]:
                put(body, 43 + rdx, 24 + rdy, ROPE[ri])
            put(body, 42, 24, BRASS[2])

        # 5) Foreground green-gold lake reeds & cattail framing the hull (`y = 24..42`)
        front_specs = [
            (11, 37, 13, 0.14, 0.10, 1, False, False),
            (15, 38, 15, -0.10, -0.12, 2, True, False),
            (24, 40, 11, 0.16, 0.08, 2, False, False),
            (28, 41, 13, -0.12, -0.10, 1, False, False),
            (46, 39, 12, -0.15, -0.10, 2, False, False),
            (50, 38, 15, 0.12, 0.14, 1, True, False),
            (54, 36, 11, -0.14, -0.08, 2, False, False),
        ]
        for fx_r, fy_r, rh, ln, bd, ts, cat, flf in front_specs:
            _draw_reed_stalk(body, fx_r, fy_r, rh, ln, bd, ts, cat, flf)
            for yy in range(fy_r - 1, min(FH, fy_r + 3)):
                for xx in range(fx_r - 2, fx_r + 3):
                    if 0 <= xx < FW and 0 <= yy < FH:
                        no_outline[yy][xx] = True

        # Suppress harsh bottom `OUT` outline along submerged hull waterline so boat sits naturally IN the water!
        for wx, wy in waterline_pts:
            for dy_w in (0, 1, 2):
                if 0 <= wy + dy_w < FH:
                    no_outline[wy + dy_w][wx] = True

        # Cool submerged hull/reed water reflection (`under_layer`, `y = 28..45`) + translucent aqua water-lap ripples (`over_layer`)!
        for y in range(28, 45):
            for x in range(7, 59):
                dx0, dy0 = x - 32.5, y - 34.5
                d_ell = (dx0 / 24.5) ** 2 + (dy0 / 8.8) ** 2
                if d_ell <= 1.0:
                    sh_a = 128 if d_ell < 0.42 else (84 if d_ell < 0.72 else 42)
                    _blend_under(under_layer, x, y, (*BRIDGE_WATER_SH_RGB, sh_a))

        seen_wl_x = {}
        for wx, wy in waterline_pts:
            if wx not in seen_wl_x or wy > seen_wl_x[wx]:
                seen_wl_x[wx] = wy
        for wx, wy in sorted(seen_wl_x.items()):
            rip = math.sin(wx * 0.65 + seed)
            if wy + 1 < FH:
                _blend_under(over_layer, wx, wy + 1, (*BRIDGE_AQUA_FOAM_RGB, 172 if rip > -0.2 else 118))
            if wy + 2 < FH and rip > -0.3:
                _blend_under(over_layer, wx, wy + 2, (*BRIDGE_AQUA_HI_RGB, 118 if rip > 0.2 else 78))
            if wy + 3 < FH and rip > 0.22:
                _blend_under(over_layer, wx, wy + 3, (*BRIDGE_AQUA_MID_RGB, 76))
        # Subtle aqua ripple glints around foreground reed stems entering the water
        for fx_r, fy_r, *_ in front_specs:
            for dx_r in (-2, -1, 0, 1, 2):
                if 0 <= fx_r + dx_r < FW and 0 <= fy_r + 1 < FH:
                    _blend_under(over_layer, fx_r + dx_r, fy_r + 1, (*BRIDGE_AQUA_HI_RGB, 128 if abs(dx_r) <= 1 else 74))

        framed = outline_pass(body, OUT)
        for y in range(FH):
            for x in range(FW):
                if body[y][x][3] == 0 and framed[y][x] == OUT and no_outline[y][x]:
                    framed[y][x] = CLEAR

        out = [row[:] for row in under_layer]
        alpha_over(out, framed, 0, 0)
        alpha_over(out, over_layer, 0, 0)

        for y in range(FH):
            sheet[y][col * FW:(col + 1) * FW] = out[y]

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
