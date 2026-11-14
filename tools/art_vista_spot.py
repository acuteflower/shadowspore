#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 1 Panorama-Aussichtspunkte (`VistaPoint`, stdlib only):
  assets/props/vista_spot.png       192x48 (3 cols x 1 row of 64x48), feet/ground anchor at (32, 40)
  assets/props/vista_spot_glow.png  192x48 unlit emissive pixels (teal/gold runes, lichen buds, dew-spores)
  docs/img/vista_spot_sheet.png     3x upscaled QA contact sheet (daylight + night + seated Ellie alignment)

Crafted to match `art_arena_pillars.py`, `art_stone.py`, and `art_tree.py` pixel density:
  - Multi-octave value noise + Bayer 4x4 ordered dithering across rock strata, dressed stone joints, and bark grain
  - Chipped stone silhouettes, dark hairline cracks with sunlit catch-edges, damp moss fringe stains, pale crust lichen
  - Creeping ivy strands, shelf fungi with glowing gills, wildflower tufts, and carved runes/spirals
  - Zero #000000 pixels anywhere; material-tinted 1px dark outlines (#1b1a2e / #122422) & cool-violet ground shadow.
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "vista_spot_sheet.png"
FW, FH = 64, 48
FOOT_X, FOOT_Y = 32, 40

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# Palettes (NEVER #000000)
OUT_STONE = hexc("1b1a2e")
OUT_LEAF = hexc("122422")
SHADOW_RGB = (16, 16, 34)

# 8-step weathered blue-violet stone ramp (matching art_stone.py + art_arena_pillars.py richness)
STONE = [hexc(c) for c in ("1c1a34", "282548", "3a365f", "4e4978", "665f94", "827ab0", "a69fd0", "d4cfee")]
MORTAR = hexc("19162e")
LICHEN = [hexc("6a8a7c"), hexc("9cc0ae")]
RIM_COOL = [hexc("2c6e8a"), hexc("58b6ce")]

# 6-step warm plum-brown ancient bark & 5-step cut heartwood
BARK = [hexc(c) for c in ("1d1220", "2f1e2e", "48303f", "674655", "8c6472", "b48b94")]
HEARTWOOD = [hexc(c) for c in ("382230", "5c3c4a", "8a626c", "b89092", "e2c4bc")]

# Meadow moss, teal moss & shelf fungi
MEADOW = [hexc(c) for c in ("1d3b34", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
TEAL_MOSS = [hexc(c) for c in ("16363c", "225254", "327870", "52a892", "86dcb8")]
SHELF = [hexc(c) for c in ("19444c", "2b7c80", "5ec6bc", "a6f2e4")]
BLOSSOM_LILAC = [hexc("8e6ea8"), hexc("be9ece"), hexc("f0e2f8")]
BLOSSOM_GOLD = [hexc("b48a38"), hexc("e6c468"), hexc("fff0b0")]

# Emissive glow & dim base colors
TEAL_DIM = hexc("2a8c94")
TEAL = hexc("3cc0c6")
TEAL_L = hexc("78f4e6")
TEAL_HOT = hexc("d0fff8")

GOLD_DIM = hexc("6f5020")
GOLD_MID = hexc("b48a38")
GOLD = hexc("e6c468")
GOLD_HOT = hexc("fff0b0")


def blank(w: int = FW, h: int = FH):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        px[y][x] = col


def get_a(px, x: int, y: int) -> int:
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        return px[y][x][3]
    return 0


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
    return 0.58 * vnoise(x, y, s) + 0.28 * vnoise(x * 2.1, y * 2.1, s + 11) + 0.14 * vnoise(x * 4.2, y * 4.2, s + 23)


class GlowLayer:
    def __init__(self, w: int = FW, h: int = FH):
        self.w = w
        self.h = h
        self.px = blank(w, h)
        self.halos = []

    def emit(self, base_px, x: int, y: int, base_col, glow_col, halo: int = 1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if base_col is not None:
                base_px[y][x] = base_col
            self.px[y][x] = glow_col
            if halo > 0:
                self.halos.append((x, y, glow_col, halo))

    def finish(self):
        out = [row[:] for row in self.px]
        for cx, cy, col, rad in self.halos:
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    if dx == 0 and dy == 0:
                        continue
                    xx, yy = cx + dx, cy + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h):
                        continue
                    d = math.hypot(dx, dy)
                    if d <= rad + 0.45 and out[yy][xx][3] < 255:
                        alpha = 102 if d <= 1.2 else (50 if d <= 1.9 else 24)
                        if alpha > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], alpha)
        return out


def finish_prop(body_px, cx: float, cy: float, rx: float, ry: float):
    """Composites soft ground shadow ellipse, material-tinted 1px dark outline, and detailed body."""
    out = blank(FW, FH)
    for y in range(FH):
        for x in range(FW):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1.0:
                out[y][x] = (*SHADOW_RGB, 118 if d < 0.48 else 64)

    green_set = set(MEADOW + TEAL_MOSS)
    for y in range(FH):
        for x in range(FW):
            if body_px[y][x][3] == 255:
                continue
            nbs = [body_px[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < FW and 0 <= y + dy < FH and body_px[y + dy][x + dx][3] == 255]
            if nbs:
                # Material-tinted outline: deep forest slate around moss/grass, dark plum-violet around stone/bark
                has_below = y + 1 < FH and body_px[y + 1][x][3] == 255
                out[y][x] = OUT_LEAF if (nbs[0] in green_set and has_below) else OUT_STONE

    for y in range(FH):
        for x in range(FW):
            if body_px[y][x][3] == 255:
                out[y][x] = body_px[y][x]
    return out


def draw_detailed_pebble(px, cx: float, cy: float, rx: float, ry: float, seed: int):
    """Draws a finely shaded, pitted, top-left-lit stone pebble with Bayer grain and rim highlight."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            warp = 1.0 + 0.08 * math.sin(math.atan2(dy, dx) * 3.0 + seed)
            d = (dx * dx + dy * dy) / (warp * warp)
            if d > 1.0:
                continue
            nz = math.sqrt(max(0.0, 1.0 - d))
            grain = (vnoise(x * 0.9, y * 0.9, seed) - 0.5) * 0.65
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.6
            val = 3.6 + (-0.58 * dx - 0.72 * dy + 0.55 * nz) * 2.8 + grain + dith
            if dy < -0.45 and dx < 0.25 and d > 0.35:
                val += 1.1
            elif dy > 0.58:
                val -= 1.4
            put(px, x, y, STONE[int(clamp(val, 0, 7))])


def draw_cairn(px, glow: GlowLayer, base_x: float, base_y: float, stones, seed: int, glow_kind="teal"):
    """Stacked Steinmännchen with dark contact crevices, lichen flecks, and a glowing rune/spore speck."""
    for i, (dx, dy, rx, ry) in enumerate(stones):
        cx, cy = base_x + dx, base_y + dy
        if i > 0:
            for sx in range(int(cx - rx + 0.4), int(cx + rx + 0.6)):
                sy = int(cy + ry)
                if get_a(px, sx, sy) == 255:
                    put(px, sx, sy, MORTAR)
        draw_detailed_pebble(px, cx, cy, rx, ry, seed + i * 7)
        if i in (0, 2) and hsh(i, seed, 3) > 0.3:
            put(px, int(cx - rx * 0.3), int(cy - ry * 0.2), MEADOW[4])
            put(px, int(cx - rx * 0.3) + 1, int(cy - ry * 0.2), MEADOW[3])

    if glow_kind == "teal":
        glow.emit(px, int(round(base_x - 1)), int(round(base_y - 3)), TEAL_DIM, TEAL_L, halo=1)
    elif glow_kind == "gold":
        glow.emit(px, int(round(base_x)), int(round(base_y - 4)), GOLD_MID, GOLD_HOT, halo=1)


def apply_organic_moss(px, mask_fn, seed: int, pal=MEADOW):
    """Applies textured, multi-tone moss cushions with Bayer edges, sunlit leaf flecks & damp dark fringe."""
    snap = [row[:] for row in px]
    for y in range(1, FH - 1):
        for x in range(1, FW - 1):
            w_prob = mask_fn(x, y)
            if w_prob <= 0.0:
                continue
            n = fbm(x * 0.35, y * 0.45, seed) * 0.8 + hsh(x, y, seed + 5) * 0.2
            thr = 0.56 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42
            score = w_prob * (0.55 + n)
            if score > thr:
                # Shaded by local slope + micro leaf clusters
                lit = 0.55 - 0.012 * (x - 24) - 0.04 * (y - 28) + (hsh(x, y, seed + 9) - 0.5) * 0.55
                idx = int(clamp(lit * (len(pal) - 1.2) + (BAYER[(y + 1) % 4][x % 4] / 16.0 - 0.5) * 0.7, 1, len(pal) - 1))
                # Trailing dark moss edge at bottom of cushion
                if mask_fn(x, y + 1) < w_prob * 0.45 and hsh(x, y, seed + 13) > 0.4:
                    idx = max(0, idx - 2)
                put(px, x, y, pal[idx])
            elif score > thr - 0.16 and snap[y][x][3] == 255 and snap[y][x] in STONE[2:]:
                # Damp weathering stain around moss fringe (like art_arena_pillars.py!)
                k = STONE.index(snap[y][x])
                put(px, x, y, STONE[max(1, k - 1)])


def draw_ivy_vine(px, pts, seed: int):
    """Delicate creeping ivy vine with tiny alternating sunlit 2px leaves."""
    for i, (ix, iy) in enumerate(pts):
        put(px, ix, iy, MEADOW[1 if i % 2 else 2])
        if i % 2 == 1:
            side = -1 if (i // 2) % 2 == 0 else 1
            put(px, ix + side, iy, MEADOW[5 if side < 0 else 4])
            if i % 4 == 1:
                put(px, ix + side, iy + 1, MEADOW[2])


def draw_grass_and_flowers(px, bx: int, by: int, flip: int = 1, blossom=None):
    """Crisp meadow grass tuft with shaded root and sunlit tips, plus optional wildflower."""
    blades = [
        [(0, 0, MEADOW[1]), (-1 * flip, -1, MEADOW[3]), (-2 * flip, -2, MEADOW[4]), (-3 * flip, -3, MEADOW[5])],
        [(1 * flip, 0, MEADOW[1]), (1 * flip, -1, MEADOW[3]), (2 * flip, -2, MEADOW[5]), (2 * flip, -3, MEADOW[6])],
        [(0, -1, MEADOW[2]), (0, -2, MEADOW[4]), (-1 * flip, -3, MEADOW[5])],
    ]
    for b in blades:
        for dx, dy, c in b:
            put(px, bx + dx, by + dy, c)
    if blossom is not None:
        put(px, bx + 2 * flip, by - 2, blossom[0])
        put(px, bx + 2 * flip, by - 3, blossom[2])
        put(px, bx + 1 * flip, by - 3, blossom[1])


def read_png_rgba(path: pathlib.Path):
    """Pure-stdlib PNG reader returning (w, h, rows_of_rgba_tuples) for QA compositing."""
    import struct
    import zlib
    data = path.read_bytes()
    pos = 8
    w = h = ct = 0
    idat = bytearray()
    while pos < len(data):
        ln, tag = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, _bd, ct, _, _, _ = struct.unpack(">IIBBBBB", chunk)
        elif tag == b"IDAT":
            idat.extend(chunk)
    raw = zlib.decompress(bytes(idat))
    bpp = 4 if ct == 6 else 3
    stride = w * bpp
    rows = []
    p = 0
    prev = bytearray(stride)
    for _y in range(h):
        flt = raw[p]
        p += 1
        row = bytearray(raw[p:p + stride])
        p += stride
        if flt == 1:
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 0xFF
        elif flt == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif flt == 3:
            for i in range(stride):
                a = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif flt == 4:
            for i in range(stride):
                a = row[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pr_v = a + b - c
                pa, pb, pc = abs(pr_v - a), abs(pr_v - b), abs(pr_v - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 0xFF
        prev = row
        if bpp == 4:
            rows.append([tuple(row[x * 4:x * 4 + 4]) for x in range(w)])
        else:
            rows.append([(*row[x * 3:x * 3 + 3], 255) for x in range(w)])
    return w, h, rows


# ==============================================================================
# Variant 0: Windgeschliffener Aussichtsfels (`stone_ledge`)
# ==============================================================================
def build_stone_ledge():
    px = blank()
    glow = GlowLayer()
    seed = 107

    # 1. Sculpted, weathered cliff-ledge boulder (`x ≈ 11..51`, top plateau `y = 29..32` across `x = 23..43`)
    for y in range(27, 41):
        t = (y - 27) / 13.0
        left_x = 12.6 - 1.6 * math.sin(t * math.pi * 0.85) + (1.0 if y < 29 else 0.0)
        right_x = 49.8 + 1.6 * math.sin(t * math.pi * 0.8) - (1.8 if y < 29 else 0.0)
        if y == 40:
            left_x += 2.2
            right_x -= 2.2
        elif y == 39:
            left_x += 0.9
            right_x -= 0.9

        for x in range(int(round(left_x)), int(round(right_x)) + 1):
            top_y = 27 if 14 <= x <= 21 else (28 if (21 < x <= 23 or 44 <= x <= 47) else 29)
            if x <= 13 or x >= 49:
                top_y = max(top_y, 30)
            # Small natural rock chip at upper-right rim (x=42..43, y=29)
            if y == 29 and x in (43, 48):
                continue
            if y < top_y:
                continue

            front_lip = 32 if 22 <= x <= 43 else 31
            grain = (fbm(x * 0.55, y * 0.85, seed) - 0.5) * 1.15
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.65

            if y <= front_lip:
                # Wind-polished horizontal rock plateau with directional wind-scour streaks
                scour = math.sin(x * 0.28 + y * 1.1) * 0.35
                u_x = (x - 14.0) / 35.0
                val = 6.1 - u_x * 1.45 + grain * 0.75 + scour + dith
                if y == top_y:
                    val += 0.95  # Crisp sunlit back-top bevel
                elif y == front_lip:
                    val += 0.45  # Front seat rim catching skylight
                put(px, x, y, STONE[int(clamp(val, 2, 7))])
            else:
                # Vertical faceted cliff face (`y = 33..40`) with geological sedimentary strata & angular facets
                # Facet planes: bright-left (x < 21), mid-left (21..30), recessed rune face (30..36), shaded right (36+)
                if x < 21:
                    f_lit = 4.5
                elif x < 29:
                    f_lit = 3.8
                elif x < 38:
                    f_lit = 3.0
                else:
                    f_lit = 1.9

                # Sedimentary bedding seams at y=35 and y=38 (waving slightly)
                bed_y = y + 0.45 * math.sin(x * 0.24 + 1.1)
                if abs(bed_y - 35.2) < 0.42 or abs(bed_y - 38.1) < 0.38:
                    f_lit -= 1.35
                elif abs(bed_y - 36.0) < 0.45:
                    f_lit += 0.55  # Catch-edge below bedding seam

                # Overhang shadow right below the seat lip (`y = 33`) and ground AO (`y >= 39`)
                if y == front_lip + 1:
                    f_lit -= 1.15
                if y >= 39:
                    f_lit -= 0.9 * (y - 38)

                # Pitting flecks
                if hsh(x // 2, y, seed + 19) > 0.93:
                    f_lit -= 1.1

                col = STONE[int(clamp(f_lit + grain + dith, 0, 6))]
                # Cool twilight sky bounce on far-right vertical edge
                if x >= int(round(right_x)) - 1 and 33 <= y <= 37 and hsh(x, y, seed + 31) > 0.35:
                    col = RIM_COOL[1 if y <= 35 else 0]
                put(px, x, y, col)

    # 2. Branching geological cracks with sunlit right catch-edge
    cracks = [
        [(21, 32), (21, 33), (22, 34), (22, 35), (23, 36), (23, 37), (22, 38)],
        [(39, 33), (40, 34), (40, 35), (41, 36), (42, 37), (42, 38)],
        [(16, 33), (17, 34), (17, 35)],
    ]
    for ck in cracks:
        for cx_k, cy_k in ck:
            if get_a(px, cx_k, cy_k) == 255:
                put(px, cx_k, cy_k, MORTAR)
                if get_a(px, cx_k + 1, cy_k) == 255 and px[cy_k][cx_k + 1] in STONE[:5]:
                    idx = STONE.index(px[cy_k][cx_k + 1])
                    put(px, cx_k + 1, cy_k, STONE[min(6, idx + 1)])

    # Pale crust lichen colonies on rock face
    for lx, ly in [(18, 36), (19, 36), (25, 34), (26, 34), (44, 35), (45, 36)]:
        if get_a(px, lx, ly) == 255:
            put(px, lx, ly, LICHEN[1 if (lx + ly) % 2 == 0 else 0])

    # 3. Rich multi-tone moss mantle on left shoulder & right corner (leaving seat x=24..42 clear!)
    def ledge_moss_mask(x: int, y: int) -> float:
        if get_a(px, x, y) != 255:
            return 0.0
        # Left shoulder cushion (x=13..23, y=27..32) + right corner tuft (x=44..48, y=28..32)
        d_left = ((x - 18.0) / 5.8) ** 2 + ((y - 28.8) / 3.2) ** 2
        d_right = ((x - 46.0) / 3.2) ** 2 + ((y - 30.0) / 2.4) ** 2
        if d_left < 1.0:
            return 1.25 - d_left * 0.75
        if d_right < 1.0:
            return 1.15 - d_right * 0.75
        return 0.0

    apply_organic_moss(px, ledge_moss_mask, seed=211, pal=MEADOW)
    # Creeping ivy tendril draping down left rock shoulder
    draw_ivy_vine(px, [(15, 30), (15, 31), (16, 32), (16, 33), (15, 34), (15, 35)], seed=213)

    # 4. Detailed 5-stone Steinmännchen (cairn) on left shoulder (`x ≈ 13..19`, `y ≈ 18..28`)
    cairn_stones = [
        (0.0, 0.0, 3.6, 2.0),
        (0.2, -2.5, 2.8, 1.6),
        (-0.2, -4.7, 2.2, 1.4),
        (0.1, -6.6, 1.7, 1.2),
        (0.0, -8.2, 1.2, 1.0),
    ]
    draw_cairn(px, glow, 16.2, 27.4, cairn_stones, seed=221, glow_kind="teal")

    # 5. Incised ancient wind-compass spiral on front rock face (`x = 29..34, y = 34..38`)
    carved_pts = [(30, 34), (31, 34), (32, 34), (33, 35), (33, 36), (32, 37), (31, 37), (30, 37), (29, 36), (29, 35)]
    for gx, gy in carved_pts:
        put(px, gx, gy, MORTAR)
    # Sunlit lower-inside chisel bevel of the carving
    for bx, by in [(30, 38), (31, 38), (32, 38), (34, 36), (30, 35)]:
        if get_a(px, bx, by) == 255:
            put(px, bx, by, STONE[5])

    glow.emit(px, 31, 35, GOLD, GOLD_HOT, halo=2)
    glow.emit(px, 31, 36, GOLD_MID, GOLD, halo=1)
    glow.emit(px, 30, 36, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 32, 35, TEAL_DIM, TEAL_L, halo=1)
    # Luminous moss buds
    glow.emit(px, 14, 28, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 20, 27, GOLD_MID, GOLD_HOT, halo=1)
    glow.emit(px, 46, 29, TEAL_DIM, TEAL_L, halo=1)

    # Fallen chips & meadow wildflowers at the foot
    draw_detailed_pebble(px, 12.2, 39.2, 2.3, 1.4, seed=231)
    draw_detailed_pebble(px, 49.0, 39.5, 1.8, 1.2, seed=233)
    draw_grass_and_flowers(px, 9, 39, flip=1, blossom=BLOSSOM_GOLD)
    draw_grass_and_flowers(px, 51, 39, flip=-1, blossom=BLOSSOM_LILAC)

    return finish_prop(px, cx=31.5, cy=40.4, rx=23.5, ry=3.3), glow.finish()


# ==============================================================================
# Variant 1: Bemooster Klippen-Sitzstamm (`moss_log`)
# ==============================================================================
def build_moss_log():
    px = blank()
    glow = GlowLayer()
    seed = 307

    # 1. Gnarled fallen ancient trunk (`x = 10..52`, `y = 28..40`) with deep twisted bark plates, knots & splits
    x_start, x_end = 11, 51
    for x in range(x_start, x_end + 1):
        u = (x - x_start) / float(x_end - x_start)
        # Subtle organic settle in the middle seat saddle + root swell at right
        cy = 34.4 + 0.55 * math.sin(u * math.pi) - (0.45 if x < 17 else 0.0)
        ry = 5.5 - 0.3 * u + (0.45 if 15 <= x <= 20 or x >= 46 else 0.0)
        y_top = int(round(cy - ry))
        y_bot = min(40, int(round(cy + ry)))

        for y in range(y_top, y_bot + 1):
            dy = (y + 0.5 - cy) / ry
            nz = math.sqrt(max(0.0, 1.0 - min(1.0, dy * dy)))
            # Stretched bark fiber noise + winding furrow channels
            fiber = (fbm(x * 0.22, y * 1.35, seed) - 0.5) * 1.25
            furrow_wave = math.sin(y * 1.55 + 0.55 * math.sin(x * 0.24 + 0.8))
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.62
            val = 2.6 + (-0.68 * dy + 0.42 * nz - 0.16 * (u - 0.35)) * 2.7 + fiber + 0.48 * furrow_wave + dith
            # Crisp dark bark crevices running along the trunk
            if furrow_wave < -0.72 and (x + y * 2) % 5 != 0:
                val -= 1.35
            if dy > 0.72:
                val = min(val, 0.9)
            put(px, x, y, BARK[int(clamp(val, 0, 5))])

    # Gnarled bark knot / whorl at (x=29..33, y=35..38) on the front of the log
    for ky in range(34, 39):
        for kx in range(28, 34):
            d = ((kx - 30.8) / 2.6) ** 2 + ((ky - 36.2) / 1.9) ** 2
            if d <= 1.05 and get_a(px, kx, ky) == 255:
                col = BARK[0] if d < 0.28 else (BARK[4] if (d > 0.55 and ky <= 36) else BARK[1])
                put(px, kx, ky, col)

    # 2. Angled broken/hollow heartwood end on the left (`x = 10..17, y = 28..40`)
    ecx, ecy, erx, ery = 13.4, 34.3, 3.4, 5.3
    for y in range(28, 41):
        for x in range(9, 18):
            dx = (x + 0.5 - ecx) / erx
            dy = (y + 0.5 - ecy) / ery
            d = math.hypot(dx, dy)
            # Jagged splintered wood top-right of cut
            splinter = 0.12 * math.sin(math.atan2(dy, dx) * 5.0 + 1.4)
            if d <= 1.06 + splinter:
                if d > 0.84:
                    col = BARK[5 if (dy < -0.25 and dx < 0.25) else (3 if dy < 0.35 else 0)]
                elif d < 0.36:
                    # Deep hollow heart cavity (dark plum-indigo, zero #000000)
                    col = BARK[0] if dy < 0.1 else MORTAR
                else:
                    # Concentric growth rings + radial checks
                    ring = math.sin(d * 14.0) > 0.25
                    lit_cut = -0.45 * dx - 0.55 * dy + (0.35 if ring else -0.25)
                    col = HEARTWOOD[int(clamp(2.4 + lit_cut * 2.2, 0, 4))]
                put(px, x, y, col)

    # Root spurs gripping the soil on the right (`x = 47..55, y = 35..40`)
    for ax, ay, bx, by in [(47, 35, 54, 39), (45, 37, 51, 40), (49, 34, 55, 37)]:
        for s in range(12):
            t = s / 11.0
            xx = int(round(ax + (bx - ax) * t))
            yy = int(round(ay + (by - ay) * t + 0.6 * math.sin(t * math.pi)))
            put(px, xx, yy, BARK[4 if t < 0.45 else 3])
            if yy + 1 <= 40:
                put(px, xx, yy + 1, BARK[2 if t < 0.5 else 1])
            if yy + 2 <= 40 and t < 0.6:
                put(px, xx, yy + 2, BARK[0])

    # 3. Velvety emerald & teal moss saddle blanket along upper trunk ridge (`x = 16..46, y = 28..34`)
    def log_moss_mask(x: int, y: int) -> float:
        if x < 16 or x > 46 or y < 28 or y > 35:
            return 0.0
        drape_lim = 32.3 + 1.3 * math.sin(x * 0.52 + 0.8) + (1.4 if x in (18, 19, 20, 41, 42, 43) else 0.0)
        if 25 <= x <= 38:
            drape_lim = min(drape_lim, 32.4)
        if y > drape_lim:
            return 0.0
        top_lim = 28 if (17 <= x <= 24 or 39 <= x <= 44) else 29
        if y < top_lim:
            return 0.0
        return 1.35 - max(0.0, (y - top_lim) / max(1.5, drape_lim - top_lim)) * 0.55

    # Ensure solid base pixels exist at y=28..31 along the moss ridge before shading moss
    for x in range(16, 47):
        top_lim = 28 if (17 <= x <= 24 or 39 <= x <= 44) else 29
        for y in range(top_lim, 32):
            if get_a(px, x, y) == 0:
                put(px, x, y, BARK[3])

    apply_organic_moss(px, log_moss_mask, seed=317, pal=MEADOW)
    # Interleave rich teal-moss tufts into the meadow moss blanket
    for tx, ty in [(18, 29), (19, 30), (22, 29), (36, 30), (40, 29), (41, 30), (42, 31)]:
        if get_a(px, tx, ty) == 255:
            put(px, tx, ty, TEAL_MOSS[4 if ty == 29 else 3])
            if get_a(px, tx + 1, ty) == 255:
                put(px, tx + 1, ty, TEAL_MOSS[2])

    # Crust lichen & tiered bracket shelf fungi along the front bark
    for lx, ly in [(24, 36), (25, 36), (35, 37), (36, 37)]:
        put(px, lx, ly, LICHEN[1 if lx % 2 == 0 else 0])

    for fx, fy, fw in [(40, 35, 5), (43, 37, 4), (19, 35, 4), (21, 37, 3)]:
        for dx in range(fw):
            put(px, fx + dx, fy, SHELF[3 if dx < fw - 2 else 2])
            put(px, fx + dx, fy + 1, SHELF[1 if dx == 0 else 0])

    # 4. Stacked 4-stone Steinmännchen + glowing dew-spores at the right root end (`x ≈ 51..56`)
    log_cairn = [
        (0.0, 0.0, 3.0, 1.7),
        (-0.2, -2.2, 2.2, 1.3),
        (0.1, -4.0, 1.6, 1.1),
        (0.0, -5.5, 1.1, 0.9),
    ]
    draw_cairn(px, glow, 53.2, 38.6, log_cairn, seed=331, glow_kind="gold")

    # Bioluminescent spores & fungi gills
    glow.emit(px, 13, 35, GOLD, GOLD_HOT, halo=2)
    glow.emit(px, 14, 35, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 19, 28, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 41, 35, SHELF[2], TEAL_L, halo=1)
    glow.emit(px, 44, 37, SHELF[2], TEAL, halo=1)
    glow.emit(px, 20, 35, SHELF[2], TEAL_L, halo=1)
    glow.emit(px, 48, 33, GOLD_MID, GOLD_HOT, halo=1)

    draw_grass_and_flowers(px, 9, 39, flip=1, blossom=BLOSSOM_LILAC)
    draw_grass_and_flowers(px, 57, 39, flip=-1, blossom=BLOSSOM_GOLD)

    return finish_prop(px, cx=32.5, cy=40.4, rx=25.0, ry=3.2), glow.finish()


# ==============================================================================
# Variant 2: Alter Steinsetzer-Raststein (`carved_bench`)
# ==============================================================================
def build_carved_bench():
    px = blank()
    glow = GlowLayer()
    seed = 409

    # 1. Deep recessed shadow apron under the bench slab (`x = 23..41, y = 33..37`)
    for y in range(33, 38):
        for x in range(23, 41):
            if y <= 36:
                put(px, x, y, MORTAR if y <= 34 else STONE[0])

    # 2. Two squat dressed-ashlar stone piers (`x = 19..25` and `x = 39..45`, `y = 33..40`)
    for pier_i, (px0, px1) in enumerate([(19, 25), (39, 45)]):
        for y in range(33, 41):
            x0 = px0 - (1 if y >= 38 else 0)
            x1 = px1 + (1 if y >= 38 else 0)
            for x in range(x0, x1 + 1):
                u = (x - x0) / max(1.0, float(x1 - x0))
                grain = (fbm(x * 0.7, y * 0.8, seed + pier_i * 13) - 0.5) * 0.9
                dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
                if y == 33:
                    col = MORTAR  # Cast shadow right under overhanging seat slab
                elif y == 37 or (y in (35, 36) and x == px0 + 3):
                    col = MORTAR  # Ashlar horizontal & vertical mortar joints!
                elif y == 40:
                    col = STONE[0]
                else:
                    base_v = (4.3 if pier_i == 0 else 3.4) - u * 2.1 + grain + dith
                    if y == 38 and u < 0.65:
                        base_v += 1.0  # Sunlit plinth step lip
                    col = STONE[int(clamp(base_v, 1, 6))]
                put(px, x, y, col)

    # 3. Hewn Hallgrat stone-setter bench slab (`x = 17..47, y = 29..33`)
    # Dressed from 3 fitted megalithic blocks (`x=17..27`, `28..37`, `38..47`) with chipped corners & carved fascia
    slab_joints = (27, 37)
    for y in range(29, 34):
        x0 = 18 if y == 29 else 17
        x1 = 45 if y == 29 else (46 if y == 30 else 47)
        for x in range(x0, x1 + 1):
            # Chipped notch at x=37, y=29 along the joint
            if y == 29 and x == 37:
                continue
            u = (x - 17.0) / 30.0
            grain = (fbm(x * 0.65, y * 0.9, seed + 29) - 0.5) * 0.95
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55

            if x in slab_joints and y in (29, 30, 31, 33):
                col = MORTAR if y >= 31 else STONE[2]
            elif y == 29:
                col = STONE[7 if x < 30 else (6 if x < 40 else 5)]
            elif y in (30, 31):
                val = 5.9 - u * 1.55 + grain + dith
                if x - 1 in slab_joints:
                    val += 0.85  # Sunlit catch-edge right of slab joint!
                if y == 31 and x > 38:
                    val -= 0.4
                col = STONE[int(clamp(val, 2, 7))]
            elif y == 32:
                # Carved Hallgrat chevron/dentil fascia frieze along front edge (`x = 19..45`)
                notch = 20 <= x <= 44 and ((x - 20) % 3 == 0)
                if notch:
                    col = MORTAR if x > 32 else STONE[1]
                else:
                    val = 4.6 - u * 1.6 + (0.6 if (x - 20) % 3 == 1 else 0.0) + grain * 0.5
                    col = STONE[int(clamp(val, 1, 6))]
            else:  # y == 33 lower chamfer
                col = STONE[2 if x < 28 else (1 if x < 40 else 0)]
            put(px, x, y, col)

    # Hairline crack across right slab block
    for cx_k, cy_k in [(41, 30), (41, 31), (42, 32), (42, 33)]:
        put(px, cx_k, cy_k, MORTAR)

    # 4. Weathered Hallgrat boundary lantern-pillar beside left end (`x = 8..16, y = 21..40`)
    # Stepped ashlar base (y=36..40)
    for y in range(36, 41):
        for x in range(8 + (1 if y == 36 else 0), 17 - (1 if y == 36 else 0)):
            u = (x - 8.0) / 8.0
            if y == 38 or (y >= 38 and x == 12):
                col = MORTAR
            elif y == 40:
                col = STONE[0]
            else:
                val = (5.2 if y == 36 else 4.0) - u * 2.2 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.6
                col = STONE[int(clamp(val, 1, 6))]
            put(px, x, y, col)

    # Lantern shaft with arched rune niche (`x = 9..15, y = 26..35`)
    for y in range(26, 36):
        for x in range(9, 16):
            u = (x - 9.0) / 6.0
            if 28 <= y <= 33 and 11 <= x <= 13 and not (y == 28 and x in (11, 13)):
                put(px, x, y, MORTAR)  # Deep lantern niche
            elif y in (27, 34):
                # Carved molding rings above & below lantern window
                put(px, x, y, STONE[5 if u < 0.45 else (3 if u < 0.8 else 1)])
            elif y == 35:
                put(px, x, y, MORTAR)
            else:
                val = 5.0 - u * 2.5 + (fbm(x * 0.8, y * 0.8, seed + 51) - 0.5) * 0.8
                put(px, x, y, STONE[int(clamp(val, 1, 6))])

    # Stepped pyramidal cap + finial pebble (`y = 21..25`)
    for y in range(23, 26):
        hw = 4 if y == 25 else (3 if y == 24 else 2)
        for x in range(12 - hw, 12 + hw + 1):
            u = (x - (12 - hw)) / max(1.0, float(2 * hw))
            put(px, x, y, STONE[int(clamp(6.2 - u * 2.6 - (y - 23) * 0.4, 2, 7))])
    draw_detailed_pebble(px, 12.2, 22.0, 1.7, 1.2, seed=461)

    # 5. Moss cushions & creeping ivy on lantern cap, bench ends, and pier bases (keeping center x=23..41 clear!)
    def bench_moss_mask(x: int, y: int) -> float:
        if get_a(px, x, y) != 255:
            return 0.0
        for mx, my, mrx, mry in [(19.5, 29.8, 2.8, 1.8), (45.0, 30.2, 2.6, 1.8), (21.2, 38.8, 2.8, 1.6), (10.8, 24.2, 2.5, 1.6)]:
            d = ((x - mx) / mrx) ** 2 + ((y - my) / mry) ** 2
            if d < 1.0:
                return 1.25 - d * 0.7
        return 0.0

    apply_organic_moss(px, bench_moss_mask, seed=479, pal=MEADOW)
    draw_ivy_vine(px, [(19, 31), (20, 32), (20, 33), (21, 34), (21, 35), (20, 36)], seed=483)
    draw_ivy_vine(px, [(44, 32), (44, 33), (43, 34), (43, 35)], seed=487)

    # 6. Warm-gold lantern rune flame + carved teal stone-setter rune glints on bench fascia
    glow.emit(px, 12, 30, GOLD_HOT, GOLD_HOT, halo=2)
    glow.emit(px, 12, 31, GOLD, GOLD_HOT, halo=2)
    glow.emit(px, 12, 32, GOLD_MID, GOLD, halo=1)
    glow.emit(px, 11, 31, GOLD_DIM, GOLD, halo=1)
    glow.emit(px, 32, 32, TEAL, TEAL_HOT, halo=2)    # Center keystone rune on bench front
    glow.emit(px, 26, 32, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 38, 32, TEAL_DIM, TEAL_L, halo=1)
    glow.emit(px, 45, 29, TEAL_DIM, TEAL_L, halo=1)

    # Fallen stone chip & meadow clover tufts
    draw_detailed_pebble(px, 50.2, 39.4, 2.0, 1.3, seed=491)
    draw_grass_and_flowers(px, 6, 39, flip=1, blossom=BLOSSOM_GOLD)
    draw_grass_and_flowers(px, 31, 39, flip=1, blossom=BLOSSOM_LILAC)
    draw_grass_and_flowers(px, 52, 39, flip=-1, blossom=BLOSSOM_LILAC)

    return finish_prop(px, cx=30.0, cy=40.4, rx=24.5, ry=3.3), glow.finish()


# ==============================================================================
# Verification & 3x QA Contact Sheet (stdlib only)
# ==============================================================================
def verify_no_pure_black(name: str, px):
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} contains forbidden pure #000000 pixel at ({x}, {y}): {c}")


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
                min(255, int(dc[0] * (1.0 - 0.6 * f) + gc[0] * f * 1.3)),
                min(255, int(dc[1] * (1.0 - 0.6 * f) + gc[1] * f * 1.3)),
                min(255, int(dc[2] * (1.0 - 0.6 * f) + gc[2] * f * 1.3)),
                255,
            )


def make_meadow_swatch(w: int, h: int, night: bool):
    day_cols = [hexc(c) for c in ("2f624e", "3e7d56", "55985f")]
    night_cols = [(20, 28, 50, 255), (25, 36, 60, 255), (31, 46, 70, 255)]
    pal = night_cols if night else day_cols
    sky = (15, 14, 34, 255) if night else (154, 184, 226, 255)
    rim = (42, 54, 82, 255) if night else (85, 152, 95, 255)
    out = blank(w, h)
    for y in range(h):
        for x in range(w):
            if y < 9:
                out[y][x] = sky
            elif y == 9:
                out[y][x] = rim
            else:
                n = noise(x // 3, y // 2, 91)
                out[y][x] = pal[0 if n < 68 else (1 if n <= 202 else 2)]
    return out


def render_qa_sheet(sheet_px, glow_px):
    pad_top = 18
    row_h = FH + pad_top
    total_w = FW * 3
    canvas = blank(total_w, row_h * 3)

    # Row 0: Daylight
    day = make_meadow_swatch(total_w, row_h, night=False)
    alpha_over(day, sheet_px, 0, pad_top)
    alpha_over(canvas, day, 0, 0)

    # Row 1: Night + additive glow
    night = make_meadow_swatch(total_w, row_h, night=True)
    tinted = [[(max(4, int(c[0] * 0.45)), max(6, int(c[1] * 0.48)), max(12, int(c[2] * 0.68)), c[3]) if c[3] else CLEAR for c in r] for r in sheet_px]
    alpha_over(night, tinted, 0, pad_top)
    add_glow_over(night, glow_px, 0, pad_top)
    alpha_over(canvas, night, 0, row_h)

    # Row 2: Seated Ellie (`player_rest.png`) SE / S / SW alignment at (32, 40)
    sit = make_meadow_swatch(total_w, row_h, night=False)
    alpha_over(sit, sheet_px, 0, pad_top)
    rest_path = ROOT / "characters" / "player_rest.png"
    if rest_path.exists():
        rw, rh, rpx = read_png_rgba(rest_path)
        fw, fh = 72, 76
        col_idle = 18
        if rw >= (col_idle + 1) * fw and rh >= 4 * fh:
            for c_i, sector in enumerate((1, 2, 3)):
                crop = [rpx[sector * fh + yy][col_idle * fw:(col_idle + 1) * fw] for yy in range(fh)]
                alpha_over(sit, crop, c_i * FW + FOOT_X - 36, pad_top + FOOT_Y - 54)
    alpha_over(canvas, sit, 0, row_h * 2)

    # 3x nearest upscale
    up_w, up_h = total_w * 3, row_h * 3 * 3
    up = [[canvas[y // 3][x // 3] for x in range(up_w)] for y in range(up_h)]
    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, up_w, up_h, up)


def main():
    variants = [build_stone_ledge(), build_moss_log(), build_carved_bench()]
    sheet_w, sheet_h = FW * 3, FH
    sheet_px = blank(sheet_w, sheet_h)
    glow_px = blank(sheet_w, sheet_h)
    for col, (v_px, v_gl) in enumerate(variants):
        verify_no_pure_black(f"vista_col_{col}", v_px)
        verify_no_pure_black(f"vista_glow_col_{col}", v_gl)
        for y in range(FH):
            sheet_px[y][col * FW:(col + 1) * FW] = v_px[y]
            glow_px[y][col * FW:(col + 1) * FW] = v_gl[y]

    write_png(ROOT / "props" / "vista_spot.png", sheet_w, sheet_h, sheet_px)
    write_png(ROOT / "props" / "vista_spot_glow.png", sheet_w, sheet_h, glow_px)
    render_qa_sheet(sheet_px, glow_px)
    print("Regenerated high-detail vista_spot.png, vista_spot_glow.png, and docs/img/vista_spot_sheet.png")


if __name__ == "__main__":
    main()
