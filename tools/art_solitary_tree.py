#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 2 Habitat 2 — Solitärbaum auf den Offenen Windwiesen (stdlib only):
  assets/props/solitary_oak.png       2 cols x 1 row of 224x208 (448x208), feet at (112, 192):
                                      Col 0: Grand wind-sculpted gnarled Wind-Eiche / Windlinde with multi-tiered
                                             leaf-clump shelves, exposed crooked dark bark elbows, hanging leaf tassels,
                                             mossy roots, wildflowers, and a detailed weathered wooden bench nestled
                                             beside the right-front roots (`x ~ +22..+50` from center, `y ~ +2` around
                                             feet) where Ellie (`42 px` tall) can sit facing south!
                                      Col 1: Grand wind-sculpted Wind-Eiche with a sturdy crooked left bough offering
                                             braided rope attachment at `(-42, -58)` from feet `(112, 192)`, i.e. `(70, 134)`.
  assets/props/solitary_oak_glow.png  2 cols x 1 row of 224x208 (448x208), unlit firefly/lichen glints at night.
  assets/props/oak_swing.png          32x64 single sprite, top rope pivot at `(16, 2)`, twin braided hemp ropes
                                      hanging down ~48 px to a weathered wooden plank seat at `y = 50..56`.
  docs/img/solitary_oak_sheet.png     Visual QA contact sheet (daylight + night + attached swing preview).

Zero #000000 pixels anywhere; stdlib + gen_art.py only.
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "solitary_oak_sheet.png"

FW, FH = 224, 208
FX, FY = 112, 192
SW_W, SW_H = 32, 64

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# Palettes (NEVER #000000)
OUT_BARK = hexc("1b1a2e")
OUT_LEAF = hexc("132226")
SHADOW_RGB = (16, 18, 36)

# Sunlit olive-meadow & golden-sage leaf canopy (7 rich cel steps matching prompt + deep cool-indigo pocket)
OAK_LEAF = [
    hexc("162736"),  # 0 deep slate-indigo canopy interior crevice
    hexc("22483c"),  # 1 cool forest shadow
    hexc("3e7d56"),  # 2 meadow mid-dark
    hexc("55985f"),  # 3 sunlit meadow mid
    hexc("7cb96d"),  # 4 warm olive-meadow
    hexc("a8dc8c"),  # 5 golden-sage highlight
    hexc("d4ee9e"),  # 6 sun-drenched crown crest
]
LEAF_RIM = [hexc("2b7882"), hexc("4ec0bc")]

# Warm-grey / dusty plum gnarled oak bark (6 steps) & weathered bench planks
OAK_BARK = [hexc(c) for c in ("1d1526", "322438", "4e3b50", "70586a", "987f8c", "c4aeb4")]
LICHEN_CRUST = [hexc("628478"), hexc("96bca8")]
PLANK = [hexc(c) for c in ("281b26", "463036", "6e4e4c", "9c786e", "c6a494", "e2c6b2")]
IRON = [hexc("242238"), hexc("464460"), hexc("7c7a98")]
ROPE = [hexc(c) for c in ("382b24", "5e4a36", "8e724e", "bc9e72", "dfd0a4")]
ROOT_MOSS = [hexc(c) for c in ("1c3c34", "2a5c46", "3e7d56", "5e9e64", "86c478")]
FLOWER_GOLD = [hexc("d89e3c"), hexc("f4d068"), hexc("fff4b8")]
FLOWER_LILAC = [hexc("7248cc"), hexc("a682f4"), hexc("ebe0ff")]
FLOWER_WHITE = [hexc("96b0c8"), hexc("dce8f2"), hexc("ffffff")]

# Emissive glow colors
TEAL_DIM = hexc("2a8c94")
TEAL = hexc("3cc0c6")
TEAL_L = hexc("78f4e6")
GOLD_MID = hexc("b48a38")
GOLD = hexc("e6c468")
GOLD_HOT = hexc("fff0b0")


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


def sample_cubic(p0, p1, p2, p3, steps: int = 56):
    pts = []
    for i in range(steps + 1):
        t = i / float(steps)
        u = 1.0 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def draw_gnarled_limb(px, pts, r0: float, r1: float, seed: int = 7, moss_top: bool = False):
    """Draws a crooked, bark-furrowed oak limb with fbm bark grain, Bayer dither, knots & optional moss ridge."""
    n = max(1, len(pts) - 1)
    for i, (cx_f, cy_f) in enumerate(pts):
        t = i / float(n)
        rad = r0 + (r1 - r0) * t + 0.45 * math.sin(t * 9.5 + seed)
        ir = int(math.ceil(rad + 0.5))
        cx, cy = int(round(cx_f)), int(round(cy_f))
        tx = pts[min(n, i + 1)][0] - pts[max(0, i - 1)][0]
        ty = pts[min(n, i + 1)][1] - pts[max(0, i - 1)][1]
        tlen = max(0.001, math.hypot(tx, ty))
        tx, ty = tx / tlen, ty / tlen

        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy > (rad + 0.25) ** 2:
                    continue
                xx, yy = cx + dx, cy + dy
                lit = (-0.54 * dx - 0.76 * dy) / max(1.0, rad) + 0.46
                across = -dx * ty + dy * tx
                along = dx * tx + dy * ty
                furrow = math.sin(across * 1.35 + 0.55 * math.sin(along * 0.32 + seed))
                grain = (fbm(xx * 0.65, yy * 0.42, seed + 3) - 0.5) * 0.42
                dith = (BAYER[yy % 4][xx % 4] / 16.0 - 0.5) * 0.45
                v = (lit + 0.16 * furrow + grain) * 5.2 + dith
                if furrow < -0.76 and rad >= 2.2:
                    v -= 1.15
                if dy > rad * 0.56:
                    v = min(v, 0.75)
                col = OAK_BARK[int(clamp(v, 0, 5))]
                if moss_top and dy < -rad * 0.42 and rad >= 2.4 and t < 0.72 and hsh(xx, yy, seed + 17) > 0.38:
                    col = ROOT_MOSS[3 if dx <= 0 else 2]
                put(px, xx, yy, col)


def render_terraced_oak_canopy(shelves, seed: int, clear_swing_box: bool = False):
    """`art_blossom.py` / `art_willow.py`-grade multi-tiered broadleaf cloud-clump renderer:
    - Places ~140 overlapping small 3D leaf sub-clumps (`rx = 3.6..8.2 px`) across staggered wind-swept bough shelves
      rather than giant smooth spheres, creating rich dappled micro-clusters and dark indigo-green bough crevices.
    - Adds Bayer 4x4 ordered dithering, fbm 2px leaf-spray grain, top-left sunlit contour highlights, cool teal
      right-rim bounce, and wind-swept trailing leaf tassels!
    """
    rng = random.Random(seed)
    sub_lobes = []

    for si, (bx, by, pw, ph, z_tier, bias) in enumerate(shelves):
        # Moderate core pad tucked slightly back in Z so each shelf reads as a coherent wind-swept foliage terrace
        sub_lobes.append((bx, by + ph * 0.06, pw * 0.66, ph * 0.56, z_tier - 2.6, bias - 0.05, si))
        # Dense cluster of small crisp leaf puffs (`3.6..7.6 px`) sculpting the entire terrace
        n_clumps = max(14, int((pw * ph) / 15.0))
        for k in range(n_clumps):
            a = rng.uniform(0.0, math.tau)
            r = (rng.random() ** 0.58)
            # Slight wind-sweep elongation to the right (+x) like a hillside Wind-Eiche!
            wind_shift = 2.2 * (1.0 - math.sin(a)) if math.cos(a) > 0 else 0.0
            lx = bx + math.cos(a) * pw * r + wind_shift
            ly = by + math.sin(a) * ph * r * (0.94 if math.sin(a) < 0 else 0.78)
            if clear_swing_box and 46 <= lx <= 98 and ly >= 115:
                continue
            sz = rng.uniform(3.6, 7.6)
            cz = z_tier + (2.2 if math.sin(a) < -0.10 else -0.6) + (k % 4) * 0.35
            sub_lobes.append((lx, ly, sz * 1.24, sz * 0.86, cz, bias, si))

        # Wind-blown feathering puffs extending off the right & left tips of each bough shelf
        for side in (-1, 1):
            for e_i in range(2 + (1 if side > 0 else 0)):
                ox = bx + side * (pw * (0.86 + 0.12 * e_i) + rng.uniform(0.5, 3.0))
                oy = by + rng.uniform(-2.5, 3.5) + (1.5 * e_i if side > 0 else 0.0)
                if clear_swing_box and 46 <= ox <= 98 and oy >= 115:
                    continue
                sub_lobes.append((ox, oy, rng.uniform(3.2, 5.2), rng.uniform(2.3, 3.8), z_tier + 1.8, bias, si))

    depth = [[-1e9] * FW for _ in range(FH)]
    nrm = [[None] * FW for _ in range(FH)]
    shelf_id = [[-1] * FW for _ in range(FH)]

    for cx, cy, rx, ry, cz, bias, si in sub_lobes:
        x0 = max(3, int(cx - rx - 2))
        x1 = min(FW - 4, int(cx + rx + 3))
        y0 = max(3, int(cy - ry - 2))
        y1 = min(FY - 18, int(cy + ry + 3))
        for y in range(y0, y1):
            for x in range(x0, x1):
                if clear_swing_box and 50 <= x <= 94 and y >= 122:
                    continue
                dx = (x + 0.5 - cx) / max(0.8, rx)
                dy = (y + 0.5 - cy) / max(0.8, ry)
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                nz = math.sqrt(1.0 - d)
                zw = cz * 2.6 + nz * max(rx, ry) * 0.82
                if zw > depth[y][x]:
                    depth[y][x] = zw
                    nrm[y][x] = (dx, dy, nz, bias)
                    shelf_id[y][x] = si

    canopy = blank(FW, FH)
    for y in range(3, FH - 4):
        for x in range(3, FW - 3):
            n = nrm[y][x]
            if n is None:
                continue
            dx, dy, nz, bias = n
            # Local sub-clump 3D shading + subtle global crown dome + crisp 2px leaf-cluster grain
            global_dome = -0.20 * ((x - FX) / 94.0) - 0.24 * ((y - 74.0) / 60.0)
            local_lit = (-0.55 * dx - 0.76 * dy + 0.56 * nz + 1.0) / 2.0
            grain = (noise(x // 2, y // 2, seed + 5) / 255.0 - 0.5) * 0.26
            grain += (fbm(x * 0.52, y * 0.52, seed + 13) - 0.5) * 0.22

            # Deep shelf-crevice shadow where an upper bough terrace overhangs a lower terrace!
            si_here = shelf_id[y][x]
            ao = 0.0
            for c_dy in (1, 2, 3, 4):
                if y - c_dy >= 3 and shelf_id[y - c_dy][x] != -1 and shelf_id[y - c_dy][x] != si_here:
                    if depth[y - c_dy][x] > depth[y][x] + 1.8:
                        ao = 0.34 if c_dy <= 2 else 0.18
                        break
            if y + 2 < FH and nrm[y + 2][x] is not None and depth[y][x] < depth[y + 2][x] - 3.0:
                ao = max(ao, 0.24)

            light = local_lit + global_dome * 0.45 + bias + grain - ao
            v = light * 6.55 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.72
            canopy[y][x] = OAK_LEAF[int(clamp(v, 0, 6))]

    # Post-pass (`art_blossom.py` style): crisp sunlit upper-left leaf contours & cool teal twilight right-rim bounce!
    snap = [row[:] for row in canopy]
    for y in range(4, FY - 18):
        for x in range(4, FW - 4):
            c = snap[y][x]
            if c[3] == 0 or c not in OAK_LEAF:
                continue
            k = OAK_LEAF.index(c)
            if snap[y - 1][x][3] == 0 and k < 6:
                canopy[y][x] = OAK_LEAF[min(6, k + 2)]
            elif snap[y][x - 1][3] == 0 and k < 5:
                canopy[y][x] = OAK_LEAF[k + 1]
            elif snap[y][x + 1][3] == 0 and 1 <= k <= 3 and noise(x, y, seed + 29) > 95:
                canopy[y][x] = LEAF_RIM[1 if noise(x, y, seed + 31) > 165 else 0]

    # Wind-swept trailing leaf shoots / catkins along lower bough hems so the silhouette breathes organically
    hems = [
        (x, y)
        for y in range(28, FY - 26)
        for x in range(10, FW - 10)
        if canopy[y][x] in OAK_LEAF[:5] and canopy[y + 1][x][3] == 0
        and not (clear_swing_box and 48 <= x <= 96 and y >= 114)
    ]
    rng.shuffle(hems)
    used_h = []
    for hx, hy in hems:
        if len(used_h) >= 34:
            break
        if any(abs(hx - ux) < 6 and abs(hy - uy) < 8 for ux, uy in used_h):
            continue
        used_h.append((hx, hy))
        t_len = rng.randint(2, 5)
        for k in range(1, t_len + 1):
            yy = hy + k
            xx = hx + (1 if k >= 3 else 0)  # Gentle breeze drift to the right
            if clear_swing_box and 48 <= xx <= 96 and yy >= 120:
                break
            if canopy[yy][xx][3] == 0:
                tone = OAK_LEAF[4 if (hx < FX and k == t_len) else (3 if k % 2 == 0 else 2)]
                put(canopy, xx, yy, tone)
                if k == 2 and t_len >= 4 and canopy[yy][xx - 1][3] == 0:
                    put(canopy, xx - 1, yy, OAK_LEAF[1])

    return canopy


def draw_cozy_root_bench(px):
    """Draws a richly detailed weathered wooden bench nestled beside/under the right-front roots of Variant 0:
    Centered at x = FX + 36 = 148 (`x = 134..162`, i.e. `+22..+50` from center), feet at `y = FY + 2 = 194`,
    seat top at `y = 183..186` so Ellie (`42 px` tall) can sit facing south!
    """
    bx0, bx1 = FX + 22, FX + 50  # 134 .. 162 (29px wide)
    seat_y = FY - 9              # 183..186
    foot_y = FY + 2              # 194

    # Two sturdy carved oak-stump legs (`x = 137..141` and `x = 155..159`, `y = 186..194`) with bark grain & moss
    for lx0, lx1 in [(bx0 + 3, bx0 + 7), (bx1 - 7, bx1 - 3)]:
        for y in range(seat_y + 3, foot_y + 1):
            for x in range(lx0, lx1 + 1):
                if y in (seat_y + 3, foot_y):
                    col = OAK_BARK[0]
                else:
                    rel = (x - lx0) / 4.0
                    grain = (hsh(x, y, 61) - 0.5) * 0.7
                    idx = int(clamp((0.78 - 0.65 * rel) * 4.5 + grain, 1, 4))
                    col = OAK_BARK[idx]
                    if y >= foot_y - 2 and rel < 0.5:
                        col = ROOT_MOSS[2 if y == foot_y - 1 else 3]
                put(px, x, y, col)

    # Mortised dark stretcher beam + wooden peg joints under seat
    for x in range(bx0 + 6, bx1 - 5):
        put(px, x, seat_y + 4, PLANK[2 if x < bx0 + 16 else 1])
        put(px, x, seat_y + 5, PLANK[0])
    put(px, bx0 + 5, seat_y + 5, IRON[2])
    put(px, bx1 - 5, seat_y + 5, IRON[1])

    # Rustic twin-post split backrest (`y = seat_y - 8 .. seat_y - 3`) with wood grain, knot & dark gap
    for px_post in (bx0 + 4, bx1 - 5):
        for y in range(seat_y - 8, seat_y + 1):
            put(px, px_post, y, PLANK[3 if y < seat_y - 2 else 1])
            put(px, px_post + 1, y, PLANK[1 if y < seat_y - 2 else 0])

    # Backrest rail (`y = seat_y - 7 .. seat_y - 4`) with slightly wavy hand-hewn top edge
    for y in range(seat_y - 7, seat_y - 3):
        for x in range(bx0 + 1, bx1):
            if y == seat_y - 7 and x in (bx0 + 1, bx1 - 1, bx0 + 14):
                continue  # Hand-hewn weathered notch!
            if y == seat_y - 7:
                col = PLANK[5 if x < bx0 + 14 else 4]
            elif y == seat_y - 4:
                col = PLANK[0 if x > bx0 + 12 else 1]
            else:
                g = fbm(x * 0.45, y * 1.2, 71)
                col = PLANK[int(clamp((4.2 if x < bx0 + 18 else 3.3) + (g - 0.5) * 1.6, 1, 5))]
            put(px, x, y, col)
    # Iron nail studs where backrest meets posts
    put(px, bx0 + 4, seat_y - 5, IRON[2])
    put(px, bx1 - 5, seat_y - 5, IRON[1])

    # Seat made of TWO distinct weathered planks (`y = seat_y..seat_y+1` back plank, dark seam at `seat_y+1`, front plank `seat_y+2..seat_y+3`)
    for y in range(seat_y, seat_y + 4):
        for x in range(bx0, bx1 + 1):
            if (x in (bx0, bx1)) and y in (seat_y, seat_y + 3):
                continue
            if y == seat_y:
                col = PLANK[5 if x < bx0 + 16 else 4]
            elif y == seat_y + 1:
                # Subtle dark seam line between back & front seat boards broken by sunlit bevels
                if (x + 2) % 5 != 0:
                    col = PLANK[1]
                else:
                    col = PLANK[3 if x < bx0 + 16 else 2]
            elif y == seat_y + 2:
                grain = fbm(x * 0.5, y * 0.9, 79)
                col = PLANK[4 if (x < bx0 + 18 and grain > 0.45) else (3 if x < bx0 + 22 else 2)]
            else:
                col = PLANK[1 if x < bx0 + 14 else 0]
            put(px, x, y, col)

    # Iron rivet dots on seat ends & velvety moss cushion creeping onto the left corner from the oak roots
    for nx in (bx0 + 5, bx1 - 5):
        put(px, nx, seat_y + 2, IRON[0])
    for dx, dy, mi in [(0, 0, 4), (1, 0, 3), (2, 0, 4), (3, 0, 2), (1, 1, 2), (2, 1, 1), (2, -6, 4), (3, -6, 3)]:
        put(px, bx0 + dx, seat_y + dy, ROOT_MOSS[mi])


def draw_wildflowers_and_grass(px, variant: int, seed: int):
    rng = random.Random(seed)
    tuft_xs = [-48, -38, -28, -18, -8, 4, 14, 20, 54] if variant == 0 else [-44, -32, -20, -8, 6, 18, 30, 42, 52]
    for i, dx in enumerate(tuft_xs):
        bx = FX + dx
        by = FY + (2 if abs(dx) < 22 else (1 if abs(dx) < 38 else 0))
        blades = [(-3, -2, 2), (-2, -4, 4), (-1, -2, 3), (0, -5, 4), (0, -2, 2), (1, -3, 3), (2, -4, 4), (2, -1, 1), (3, -2, 2)]
        for bdx, bdy, mi in blades:
            if (bdx + i) % 5 != 0:
                put(px, bx + bdx, by + bdy, ROOT_MOSS[mi])
        # Meadow wildflowers (buttercup gold, wind-lilac & white clover)
        fpal = FLOWER_GOLD if i % 3 == 0 else (FLOWER_LILAC if i % 3 == 1 else FLOWER_WHITE)
        fx_p = bx + (-1 if i % 2 == 0 else 1)
        fy_p = by - 5
        put(px, fx_p, fy_p, fpal[2])
        put(px, fx_p + 1, fy_p, fpal[1])
        put(px, fx_p, fy_p + 1, fpal[0])
        if rng.random() < 0.65:
            put(px, bx + (2 if i % 2 == 0 else -2), by - 3, fpal[1])


def build_solitary_oak(variant: int):
    """Builds Variant 0 (with cozy bench at right roots) or Variant 1 (with left swing bough at (-42, -58))."""
    seed = 401 + variant * 37
    rng = random.Random(seed)
    body = blank(FW, FH)
    glow = GlowMap(FW, FH)

    # 1. Wide gnarled windswept trunk & root buttresses anchored at (112, 192)
    lean_dir = 1.0 if variant == 0 else 0.65
    trunk_centers = {}
    for y in range(96, FY + 2):
        t_up = max(0.0, (FY - y) / float(FY - 96))
        cx = FX - 3.0 * (1.0 - t_up) + lean_dir * 9.5 * (t_up ** 1.32) + 2.6 * math.sin(t_up * 3.4 + variant)
        flare = max(0.0, (y - (FY - 24)) / 24.0) ** 1.72 * 20.0
        waist = 1.0 - 0.28 * math.sin(min(1.0, t_up * 1.15) * math.pi)
        hw = (16.5 * waist * (1.0 - 0.34 * t_up)) + flare
        trunk_centers[y] = (cx, hw)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = int(round(cx + dx))
            rel = dx / max(1.0, hw)
            # Deep spiral gnarled bark plates + fbm micro-grain + Bayer 4x4 ordered dither
            plate = math.sin(dx * 0.64 + (FY - y) * 0.15 + 0.9 * math.sin(y * 0.09 + variant))
            grain = (fbm(x * 0.58, y * 0.30, seed + 3) - 0.5) * 0.95
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.58
            v = (0.52 - 0.48 * rel) * 5.2 + 0.65 * plate + grain + dith
            if plate < -0.74 and (x + y) % 3 != 0:
                v -= 1.35  # Deep winding bark fissure
            if rel > 0.84:
                v = min(v, 0.85)
            col = OAK_BARK[int(clamp(v, 0, 5))]

            # Cozy dark root hollow at base center-left (`y = FY-16..FY-5`) with warm bark rim bevel
            if FY - 16 <= y <= FY - 5 and -6 <= dx <= 2:
                hd = ((dx + 2.0) / 3.8) ** 2 + ((y - (FY - 10.5)) / 5.5) ** 2
                if hd <= 0.68:
                    col = OAK_BARK[0]
                elif hd <= 1.05:
                    col = OAK_BARK[4 if dx < -2 else 2]

            # Rich multi-tone moss cushions along upper-left root shoulders & base flutes
            if y > FY - 22 and rel < 0.36:
                ms = ((y - (FY - 22)) / 22.0) * 1.1 - max(0.0, rel) * 0.8 + (fbm(x * 0.38, y * 0.38, seed + 9) - 0.45)
                if ms > 0.40 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.32 and not (FY - 15 <= y <= FY - 6 and -5 <= dx <= 1):
                    col = ROOT_MOSS[int(clamp((0.62 - 0.5 * rel) * 4.2, 0, 4))]
            put(body, x, y, col)

    # Pale crust lichen patches on sunlit left bark
    for _ in range(12):
        ly = rng.randrange(122, FY - 10)
        if ly in trunk_centers:
            cx_t, hw_t = trunk_centers[ly]
            lx = int(round(cx_t + rng.uniform(-hw_t * 0.75, hw_t * 0.10)))
            put(body, lx, ly, LICHEN_CRUST[1])
            put(body, lx + 1, ly, LICHEN_CRUST[0])

    # Spreading gnarled surface roots gripping the sunlit hill crest
    roots = [
        (sample_cubic((FX - 15, FY - 9), (FX - 28, FY - 5), (FX - 38, FY - 1), (FX - 49, FY + 1), 30), 4.5, True),
        (sample_cubic((FX - 7, FY - 6), (FX - 15, FY - 1), (FX - 22, FY + 2), (FX - 29, FY + 3), 22), 3.6, True),
        (sample_cubic((FX + 12, FY - 9), (FX + 23, FY - 4), (FX + 32, FY - 1), (FX + 40, FY + 1), 26), 4.2, False),
        (sample_cubic((FX + 4, FY - 5), (FX + 10, FY - 1), (FX + 15, FY + 2), (FX + 20, FY + 3), 18), 3.3, False),
    ]
    for ri, (r_pts, r0, m_top) in enumerate(roots):
        draw_gnarled_limb(body, r_pts, r0, 1.2, seed=seed + 9 + ri, moss_top=m_top)

    # 2. Sweeping crooked primary & secondary boughs (drawn into `body` AND selectively exposed in `canopy` crevices!)
    exposed_elbows = []
    if variant == 0:
        boughs = [
            (sample_cubic((FX + 1, 128), (FX - 26, 118), (FX - 54, 108), (FX - 82, 95), 50), 7.8, 2.6, True),
            (sample_cubic((FX - 34, 113), (FX - 48, 98), (FX - 62, 84), (FX - 74, 72), 32), 4.4, 1.8, False),
            (sample_cubic((FX + 4, 116), (FX - 12, 94), (FX - 28, 74), (FX - 44, 54), 44), 7.0, 2.4, False),
            (sample_cubic((FX + 8, 124), (FX + 36, 111), (FX + 64, 103), (FX + 90, 96), 52), 8.2, 2.8, True),
            (sample_cubic((FX + 44, 107), (FX + 58, 92), (FX + 70, 80), (FX + 80, 68), 32), 4.5, 1.8, False),
            (sample_cubic((FX + 6, 112), (FX + 20, 88), (FX + 34, 66), (FX + 48, 46), 44), 7.2, 2.4, False),
            (sample_cubic((FX + 5, 104), (FX + 2, 82), (FX - 2, 62), (FX + 4, 42), 36), 5.6, 2.0, False),
        ]
    else:
        # Variant 1: Sturdy horizontal-arch swing bough extending left so rope attachment at (-42, -58) = (70, 134)
        # sits right on the underside of the bough with completely open air below y=135..192!
        swing_bough = sample_cubic((FX - 2, 136), (FX - 20, 129), (FX - 38, 129), (FX - 68, 123), 52)
        boughs = [
            (swing_bough, 8.2, 3.5, True),
            (sample_cubic((FX - 42, 128), (FX - 58, 110), (FX - 74, 94), (FX - 86, 78), 38), 4.8, 2.0, False),
            (sample_cubic((FX + 2, 118), (FX - 14, 94), (FX - 28, 72), (FX - 42, 52), 44), 7.2, 2.4, False),
            (sample_cubic((FX + 7, 124), (FX + 36, 109), (FX + 66, 99), (FX + 92, 90), 52), 8.2, 2.8, True),
            (sample_cubic((FX + 44, 105), (FX + 58, 90), (FX + 72, 78), (FX + 82, 66), 32), 4.5, 1.8, False),
            (sample_cubic((FX + 5, 112), (FX + 18, 86), (FX + 34, 64), (FX + 50, 44), 44), 7.0, 2.4, False),
            (sample_cubic((FX + 4, 104), (FX + 1, 80), (FX - 3, 60), (FX + 3, 40), 36), 5.5, 2.0, False),
        ]

    for b_idx, (pts, r0, r1, m_top) in enumerate(boughs):
        draw_gnarled_limb(body, pts, r0, r1, seed=seed + 20 + b_idx, moss_top=m_top)
        exposed_elbows.append(pts[12:30])

    if variant == 1:
        # Twin braided hemp rope wraps + iron bark-protector collar around swing bough centered at x = FX - 42 = 70
        # (`oak_swing.png` ropes sit at pivot-relative dx = -7 and +6 -> world x = 63 and 76!)
        for rx_wrap in (FX - 49, FX - 36):
            for wy in range(125, 136):
                if body[wy][rx_wrap][3] == 255 or wy >= 131:
                    put(body, rx_wrap - 1, wy, ROPE[1])
                    put(body, rx_wrap, wy, ROPE[4 if wy < 129 else (3 if wy % 2 == 0 else 2)])
                    put(body, rx_wrap + 1, wy, ROPE[2 if wy < 130 else 0])

    # 3. Terraced, multi-clump wind-sculpted broadleaf canopy (`shelves`: bx, by, pw, ph, z_tier, bias)
    if variant == 0:
        shelves = [
            # Deep back crown shadow shelves
            (FX - 46, 86, 38, 22, -3.0, -0.10),
            (FX + 46, 84, 42, 24, -3.0, -0.13),
            (FX + 2, 52, 44, 24, -2.5, -0.05),
            # Staggered mid-crown billowing bough terraces
            (FX - 74, 95, 26, 16, 0.5, 0.03),
            (FX - 38, 72, 34, 20, 1.4, 0.06),
            (FX + 74, 93, 28, 17, 0.5, -0.07),
            (FX + 40, 72, 36, 21, 1.4, -0.03),
            # Sun-drenched upper crest & forward billowing shelves
            (FX - 14, 40, 36, 20, 2.4, 0.11),
            (FX + 24, 45, 34, 19, 2.1, 0.05),
            (FX + 2, 78, 32, 18, 3.0, 0.03),
            (FX - 48, 92, 24, 14, 2.6, 0.04),
            (FX + 52, 90, 26, 15, 2.5, -0.04),
        ]
    else:
        shelves = [
            (FX - 48, 76, 36, 20, -3.0, -0.08),
            (FX + 46, 82, 42, 24, -3.0, -0.13),
            (FX + 4, 50, 44, 24, -2.5, -0.04),
            # Left wing arches high above the swing bough (`y <= 112`) so the gnarled swing bough is 100% clear!
            (FX - 78, 84, 25, 16, 0.8, 0.04),
            (FX - 44, 64, 33, 19, 1.6, 0.08),
            # Sweeping right wind-crest
            (FX + 76, 89, 28, 17, 0.8, -0.07),
            (FX + 40, 69, 38, 21, 1.6, -0.03),
            # Sunlit upper crown crest & central-right front terrace
            (FX - 14, 38, 36, 20, 2.5, 0.11),
            (FX + 24, 43, 34, 19, 2.2, 0.06),
            (FX + 10, 76, 31, 18, 3.0, 0.03),
            (FX + 52, 90, 26, 15, 2.5, -0.04),
        ]

    canopy = render_terraced_oak_canopy(shelves, seed=seed + 55, clear_swing_box=(variant == 1))

    # Composite canopy over upper branches while letting crooked dark bark elbows peek through deep shadow pockets!
    merged = [row[:] for row in body]
    for y in range(FH):
        for x in range(FW):
            if canopy[y][x][3] == 255:
                if variant == 1 and 50 <= x <= 98 and y >= 123 and body[y][x][3] == 255:
                    continue
                merged[y][x] = canopy[y][x]

    for seg in exposed_elbows:
        for k, (fx, fy) in enumerate(seg[::2]):
            ix, iy = int(round(fx)), int(round(fy))
            if 8 <= ix < FW - 8 and 18 <= iy < FY - 32:
                if merged[iy][ix] in (OAK_LEAF[0], OAK_LEAF[1]):
                    put(merged, ix, iy, OAK_BARK[3 if ix < FX else 2])
                    put(merged, ix, iy + 1, OAK_BARK[0])

    # Variant 0: Cozy weathered wooden bench nestled beside right-front roots
    if variant == 0:
        draw_cozy_root_bench(merged)

    # Wildflowers & meadow grass tufts around roots
    draw_wildflowers_and_grass(merged, variant, seed + 77)

    # 4. Subtle warm golden-turquoise firefly & lichen glints for `solitary_oak_glow.png`
    firefly_spots = [
        (FX - 56, 84, True),
        (FX - 24, 58, False),
        (FX + 14, 50, True),
        (FX + 48, 78, False),
        (FX + 70, 90, True),
        (FX - 2, FY - 10, True),   # Warm golden spirit-moss glow inside the cozy root hollow
        (FX - 3, FY - 9, False),
        (FX - 28, FY - 3, False),  # Turquoise root-moss spore glint
        (FX + 26, FY - 5, False),
    ]
    if variant == 0:
        firefly_spots.append((FX + 23, FY - 9, True))  # Tiny warm glint by bench moss
    else:
        firefly_spots.append((FX - 42, 129, True))     # Warm firefly perched on swing bough between ropes

    for gx, gy, is_gold in firefly_spots:
        if is_gold:
            glow.emit(merged, gx, gy, GOLD, GOLD_HOT, halo=2)
        else:
            glow.emit(merged, gx, gy, TEAL_DIM, TEAL_L, halo=2)

    # 5. Ground shadow ellipse + 1px material-tinted dark outline
    out = blank(FW, FH)
    for y in range(FY - 6, FH):
        for x in range(FW):
            d_main = ((x + 0.5 - (FX + 4)) / 64.0) ** 2 + ((y + 0.5 - (FY + 1.5)) / 5.5) ** 2
            d_bench = ((x + 0.5 - (FX + 36)) / 18.5) ** 2 + ((y + 0.5 - (FY + 3.0)) / 3.2) ** 2 if variant == 0 else 9.0
            d = min(d_main, d_bench)
            if d < 1.0:
                out[y][x] = (*SHADOW_RGB, 116 if d < 0.48 else 62)

    oak_leaf_set = set(OAK_LEAF + LEAF_RIM)
    for y in range(1, FH - 1):
        for x in range(1, FW - 1):
            if merged[y][x][3] == 255:
                continue
            nb = [merged[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if merged[y + dy][x + dx][3] == 255]
            if nb:
                out[y][x] = OUT_LEAF if nb[0] in oak_leaf_set else OUT_BARK

    for y in range(FH):
        for x in range(FW):
            if merged[y][x][3] == 255:
                out[y][x] = merged[y][x]

    return out, glow.finish()


# ==============================================================================
# Oak Swing (`assets/props/oak_swing.png`: 32x64, top rope pivot at (16, 2))
# ==============================================================================
def build_oak_swing():
    """Single sprite 32x64, top rope pivot at (16, 2):
    Twin braided hemp ropes hanging down ~48 px (`x = 9` and `x = 22`, `y = 2..51`)
    to a weathered, wood-grained twin-plank seat with iron end-straps & knots at `y = 50..56`.
    """
    body = blank(SW_W, SW_H)

    for rx in (9, 22):
        # Forged iron ring / heavy whipped rope collar at y = 1..5
        put(body, rx, 1, IRON[2])
        put(body, rx + 1, 1, IRON[1])
        for ky in range(2, 6):
            put(body, rx - 1, ky, ROPE[2 if ky < 4 else 1])
            put(body, rx, ky, ROPE[4 if ky == 2 else 3])
            put(body, rx + 1, ky, ROPE[1 if ky > 3 else 2])
        # Diagonal-twist braided hemp rope (`y = 6..50`, 2px wide with alternating sunlit/shadow strands)
        for y in range(6, 51):
            ph = (y + (0 if rx == 9 else 1)) % 4
            if ph == 0:
                c_l, c_r = ROPE[4], ROPE[2]
            elif ph == 1:
                c_l, c_r = ROPE[3], ROPE[1]
            elif ph == 2:
                c_l, c_r = ROPE[2], ROPE[3]
            else:
                c_l, c_r = ROPE[1], ROPE[2]
            put(body, rx, y, c_l)
            put(body, rx + 1, y, c_r)

    # Weathered wooden plank seat at y = 50..55, x = 4..27 (24 px wide) with board seam, wood grain & iron straps
    for y in range(50, 56):
        x0 = 5 if y in (50, 55) else 4
        x1 = 26 if y in (50, 55) else 27
        for x in range(x0, x1 + 1):
            # Forged iron cleat straps hugging the plank at x = 8..10 and x = 21..23
            if x in (9, 22) and y in (51, 52, 53):
                col = IRON[2 if y == 51 else (1 if y == 52 else 0)]
            elif y == 50:
                col = PLANK[5 if x < 17 else 4]
            elif y == 51:
                col = PLANK[1 if (x + 1) % 5 != 0 else 3]  # Plank board seam
            elif y in (52, 53):
                g = hsh(x, y, 91)
                col = PLANK[4 if (x < 16 and g > 0.45) else (3 if x < 21 else 2)]
            elif y == 54:
                col = PLANK[2 if x < 15 else 1]
            else:
                col = PLANK[0]
            put(body, x, y, col)

    # Tiny moss tuft on left edge of swing plank + knotted rope tassels hanging underneath (`y = 56..59`)
    put(body, 5, 50, ROOT_MOSS[3])
    put(body, 6, 50, ROOT_MOSS[2])
    for rx in (9, 22):
        put(body, rx - 1, 56, ROPE[2])
        put(body, rx, 56, ROPE[3])
        put(body, rx + 1, 56, ROPE[1])
        put(body, rx, 57, ROPE[2])
        put(body, rx + 1, 57, ROPE[0])
        put(body, rx, 58, ROPE[1])

    # 1px dark plum outline (#1b1a2e)
    out = blank(SW_W, SW_H)
    for y in range(SW_H):
        for x in range(SW_W):
            if body[y][x][3] == 255:
                out[y][x] = body[y][x]
            else:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < SW_W and 0 <= ny < SW_H and body[ny][nx][3] == 255:
                        out[y][x] = OUT_BARK
                        break
    return out


# ==============================================================================
# Verification & Contact Preview (`docs/img/solitary_oak_sheet.png`)
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
                min(255, int(dc[0] * (1.0 - 0.55 * f) + gc[0] * f * 1.3)),
                min(255, int(dc[1] * (1.0 - 0.55 * f) + gc[1] * f * 1.3)),
                min(255, int(dc[2] * (1.0 - 0.55 * f) + gc[2] * f * 1.3)),
                255,
            )


def tint_night_px(src):
    out = blank(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(5, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def render_qa_sheet(oaks, swing_px):
    cw = FW * 2 + 64
    ch = FH * 2 + 24
    canvas = blank(cw, ch)
    for y in range(ch):
        night = y >= FH + 12
        for x in range(cw):
            hill_y = (58 if not night else (FH + 70)) + int(8 * math.sin(x * 0.02))
            if y < hill_y:
                canvas[y][x] = (158, 188, 228, 255) if not night else (16, 15, 36, 255)
            else:
                n = noise(x // 4, y // 3, 83)
                if not night:
                    canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (124, 185, 109, 255))
                else:
                    canvas[y][x] = (22, 32, 54, 255) if n < 115 else ((28, 42, 66, 255) if n < 205 else (34, 50, 76, 255))

    # Top row: Daylight Variant 0 (with bench), Variant 1 (with oak_swing attached at (-42, -58) from feet!), plus standalone swing
    for col in range(2):
        ox, oy = 8 + col * FW, 6
        o_px, _ = oaks[col]
        if col == 1:
            sw_x = ox + FX - 42 - 16
            sw_y = oy + FY - 58 - 2
            alpha_over(canvas, swing_px, sw_x, sw_y)
        alpha_over(canvas, o_px, ox, oy)

    alpha_over(canvas, swing_px, FW * 2 + 20, 76)

    # Bottom row: Night Variant 0 & Variant 1 with glow + night swing
    for col in range(2):
        ox, oy = 8 + col * FW, FH + 16
        o_px, o_gl = oaks[col]
        if col == 1:
            sw_x = ox + FX - 42 - 16
            sw_y = oy + FY - 58 - 2
            alpha_over(canvas, tint_night_px(swing_px), sw_x, sw_y)
        alpha_over(canvas, tint_night_px(o_px), ox, oy)
        add_glow_over(canvas, o_gl, ox, oy)

    alpha_over(canvas, tint_night_px(swing_px), FW * 2 + 20, FH + 86)

    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"
    oaks = [build_solitary_oak(0), build_solitary_oak(1)]
    oak_sheet = blank(FW * 2, FH)
    oak_glow_sheet = blank(FW * 2, FH)
    for col, (o_px, o_gl) in enumerate(oaks):
        verify_no_black(f"solitary_oak_{col}", o_px)
        verify_no_black(f"solitary_oak_glow_{col}", o_gl)
        for y in range(FH):
            oak_sheet[y][col * FW:(col + 1) * FW] = o_px[y]
            oak_glow_sheet[y][col * FW:(col + 1) * FW] = o_gl[y]

    write_png(props / "solitary_oak.png", FW * 2, FH, oak_sheet)
    write_png(props / "solitary_oak_glow.png", FW * 2, FH, oak_glow_sheet)

    swing_px = build_oak_swing()
    verify_no_black("oak_swing", swing_px)
    write_png(props / "oak_swing.png", SW_W, SW_H, swing_px)

    render_qa_sheet(oaks, swing_px)
    print("Wrote high-detail solitary_oak.png, solitary_oak_glow.png, oak_swing.png, and docs/img/solitary_oak_sheet.png")


if __name__ == "__main__":
    main()
