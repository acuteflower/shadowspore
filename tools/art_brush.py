#!/usr/bin/env python3
"""Draws Flüstergras (7 variants) and Glutdorn / bramble (5 variants) + ember_berry icon (stdlib only),
frames 40x34 (feet at (20, 31)):
  assets/props/grass.png, grass_glow.png, grass_stripped.png
  assets/props/bramble.png, bramble_glow.png, bramble_stripped.png
  assets/items/ember_berry.png
Also exports shared pixel helpers (GRASS, INK, RIM, SEED, TIP, Glow, blade, outline, put, sheet) used by
art_flora.py, art_shrooms.py, art_shore_plants.py, and art_hexenwald.py — including adaptive material-tinted
1px outlines so pale blossoms, golden petals, and cool foliage all sit harmoniously in the world."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, FH, FW, GROUND, SHADOW, bezier, blank, check_icon, clamp, put_shadow, render_body  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

GRASS = [hexc(c) for c in ("12183a", "163e3c", "22604c", "38885a", "5eb66c", "9ee28c")]
RIM = [hexc("22707e"), hexc("4cc0c4")]
TIP = [hexc(c) for c in ("4a2c8a", "7048d0", "b89cff")]
PLUME = [hexc(c) for c in ("4c447e", "7e74b2", "b2a8de", "e8e2fa")]
OAT = [hexc(c) for c in ("5c3e20", "986e2e", "cca048", "f2d47e", "fff4ba")]
SEED = [hexc("2a9aa0"), hexc("78f4e6")]
SPEC = hexc("fff6c0")

CANE = [hexc(c) for c in ("26163a", "4a2a5c", "764e86", "a67eb0")]
LEAF = [hexc(c) for c in ("131a3e", "1a3c48", "245e58", "368464", "5cb27e", "9ae4aa")]
ROSE = hexc("dc9ac2")
EMBER = [hexc(c) for c in ("5c181a", "a8341c", "e6722c", "ffbe5c")]
EMBER_CORE = hexc("fff0b2")
EMBER_GLOW = hexc("ffb25a")

# Exported INK + adaptive outline colours (never flat pure black #000000!)
INK = hexc("16182e")
INK_LEAF = hexc("122327")
INK_LOW = hexc("181530")
INK_WARM = hexc("281a34")
INK_PALE = hexc("211d3a")

# 7 Flüstergras silhouettes
GRASSES = [
    {"blades": 18, "spread": 6, "lo": 8, "hi": 16, "arch": 0.48, "lean_bias": 0.0},
    {"blades": 28, "spread": 9, "lo": 11, "hi": 22, "arch": 0.72, "lean_bias": 0.0},
    {"blades": 24, "spread": 9, "lo": 8, "hi": 16, "arch": 0.50, "lean_bias": 0.0, "plumes": 5, "plume_lo": 20, "plume_hi": 28},
    {"blades": 44, "spread": 15, "lo": 5, "hi": 12, "arch": 0.58, "lean_bias": 0.0},
    {"blades": 20, "spread": 8, "lo": 7, "hi": 14, "arch": 0.38, "lean_bias": 0.0, "pods": 6, "pod_lo": 19, "pod_hi": 28},
    {"blades": 26, "spread": 10, "lo": 9, "hi": 18, "arch": 0.68, "lean_bias": 0.24, "oats": 5, "oat_lo": 18, "oat_hi": 27},
    {"blades": 32, "spread": 12, "lo": 8, "hi": 19, "arch": 0.55, "lean_bias": -0.14, "foxtails": 4, "fox_lo": 17, "fox_hi": 25},
]

# 5 Glutdorn / bramble silhouettes
BRAMBLES = [
    {"canes": 7, "spread": 9, "height": 15, "droop": 0.50, "berries": 6, "lean": 0.0, "lobes": [(20, 24, 8, 6, 0), (14, 25, 5, 5, -1), (26, 25, 5, 5, -1)]},
    {"canes": 9, "spread": 13, "height": 20, "droop": 0.55, "berries": 10, "lean": 0.0, "lobes": [(20, 21, 10, 8, 0), (12, 24, 6, 6, -1), (28, 24, 6, 6, -1)]},
    {"canes": 11, "spread": 15, "height": 17, "droop": 0.68, "berries": 9, "lean": 0.0, "lobes": [(20, 24, 12, 6, 0), (10, 25, 6, 5, -1), (30, 25, 6, 5, -1)]},
    {"canes": 9, "spread": 13, "height": 18, "droop": 0.62, "berries": 8, "lean": 2.5, "lobes": [(17, 22, 8, 7, 0), (26, 24, 8, 6, 1), (11, 25, 5, 4, -1)]},
    {"canes": 12, "spread": 15, "height": 21, "droop": 0.58, "berries": 12, "lean": -1.5, "lobes": [(14, 20, 8, 8, 0), (26, 21, 8, 8, 0), (20, 25, 10, 5, 1)]},
]


class Glow:
    def __init__(self, w=FW, h=FH):
        self.w, self.h = w, h
        self.px = blank(w, h)
        self.items = []

    def emit(self, px, x, y, dim, bright, halo=1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim is not None:
                px[y][x] = dim
            self.px[y][x] = (*bright[:3], 255)
            self.items.append((x, y, bright, halo))

    def done(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    xx, yy = x + dx, y + dy
                    if 0 < d <= radius + 0.5 and 0 <= xx < self.w and 0 <= yy < self.h and self.px[yy][xx][3] == 0:
                        self.px[yy][xx] = (*color[:3], 104 if d < 1.6 else 46)
        return self.px


def put(px, x, y, c):
    if 0 <= x < FW and 0 <= y < FH:
        px[y][x] = c


def _pick_outline(neighbors, y):
    if y >= GROUND:
        return INK_LOW
    # Check brightest/most characteristic neighbour pixel so pale petals & warm blooms get soft tinted ink
    best = max(neighbors, key=lambda c: c[0] + c[1] + c[2])
    r, g, b, _a = best
    if r > 175 and g > 165 and b > 175:
        return INK_PALE
    if r > g + 22 and r > 105:
        return INK_WARM
    if g > r + 8:
        return INK_LEAF
    return INK


def outline(px):
    """Material-tinted 1-px silhouette outline (never harsh pure black around delicate petals or leaves)."""
    src = [row[:] for row in px]
    for y in range(FH):
        for x in range(FW):
            if src[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < FW and 0 <= b < FH and src[b][a][3] == 255]
            if hit:
                if y >= GROUND or any(b > y + 0 and y >= GROUND - 2 for _a, b in hit):
                    px[y][x] = INK_LOW
                else:
                    px[y][x] = _pick_outline([src[b][a] for a, b in hit], y)


# ------------------------------------------------------------------ grass
def blade(px, x0, y0, length, lean, arch, tone, seed, violet=False):
    """One curved grass blade: 2 px wide at the lower half (shaded right side) tapering to 1 px sunlit tip."""
    tip = (int(round(x0)), int(round(y0)))
    for i in range(int(length) + 1):
        t = i / max(length, 1)
        x = x0 + lean * length * t + arch * lean * length * t * t * 0.85
        y = y0 - length * (t - 0.26 * arch * t * t)
        xi, yi = int(clamp(round(x), 2, FW - 3)), int(clamp(round(y), 2, FH - 2))
        shade = clamp(tone + (2 if t > 0.72 else (1 if t > 0.42 else 0)) - (1 if t < 0.18 else 0) + (1 if lean < 0 else 0), 0, 5)
        col = GRASS[int(shade)]
        if violet and t > 0.78:
            col = TIP[int(t * 3) % 2]
        put(px, xi, yi, col)
        if t < 0.62 and xi + 1 < FW - 2:
            put(px, xi + 1, yi, GRASS[int(clamp(shade - 1, 0, 5))])
        tip = (xi, yi)
    return tip


def head(px, glow, x, y, kind, seed):
    x = int(clamp(x, 4, FW - 5))
    y = int(clamp(y, 4, GROUND - 4))
    if kind == "plume":
        for k in range(7):
            a = -math.pi / 2 + (k - 3) * 0.25
            for j in range(1, 4 + (1 if k % 2 == 0 else 0)):
                xx = int(clamp(round(x + math.cos(a) * j * 0.9), 2, FW - 3))
                yy = int(clamp(round(y + math.sin(a) * j * 1.05) + 1, 2, GROUND - 2))
                put(px, xx, yy, PLUME[min(3, j // 2 + (1 if k <= 3 else 0))])
        put(px, x, y - 2, PLUME[3])
        glow.emit(px, x, y - 2, None, PLUME[2], 2)
    elif kind == "oat":
        # Nodding golden-amber oat panicle with tiny dangling spikelets
        for j in range(5):
            ox = int(clamp(x + (1 if j > 1 else 0) + (1 if j > 3 else 0), 3, FW - 4))
            oy = int(clamp(y - 2 + j, 2, GROUND - 3))
            put(px, ox, oy, OAT[3 if j < 2 else 2])
            if j % 2 == 0:
                put(px, ox - 1, oy + 1, OAT[4 if j == 0 else 3])
                put(px, ox + 1, oy + 1, OAT[1])
        glow.emit(px, x, y - 2, OAT[4], OAT[4], 1)
    elif kind == "foxtail":
        # Cylindrical bristly violet-tipped meadow foxtail spike
        for dy in range(-3, 2):
            yy = int(clamp(y + dy, 2, GROUND - 3))
            put(px, x - 1, yy, TIP[2] if dy < -1 else GRASS[4])
            put(px, x, yy, TIP[1] if dy < 0 else GRASS[3])
            put(px, x + 1, yy, TIP[0] if dy < 0 else GRASS[1])
        glow.emit(px, x - 1, max(2, y - 3), TIP[2], TIP[2], 1)
    else:
        for dy in range(-1, 3):
            for dx in range(-1, 2):
                if abs(dx) + abs(dy - 0.5) <= 1.6:
                    put(px, x + dx, y + dy - 1, SEED[0] if dx >= 0 else GRASS[4])
        glow.emit(px, x, y - 1, SEED[0], SEED[1], 2)
        glow.emit(px, x, y, None, SEED[1], 1)


def make_grass(spec, seed):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n, spread = spec["blades"], spec["spread"]
    lb = spec.get("lean_bias", 0.0)

    # Subtle shaded root-tussock cushion at the base so grass clumps feel grounded & solid for critters
    tussock_w = max(5, int(spread * 0.72))
    for y in range(GROUND - 5, GROUND + 1):
        u = (GROUND - y) / 6.0
        hw = int(round(tussock_w * (1.0 - 0.38 * u)))
        for dx in range(-hw, hw + 1):
            xx = int(clamp(20 + dx, 3, FW - 4))
            lit = 2 if (dx < 0 and u > 0.35) else (1 if dx < hw // 2 else 0)
            px[y][xx] = GRASS[lit]

    blades = []
    for _i in range(n):
        x0 = 20 + rng.uniform(-spread, spread)
        height = rng.uniform(spec["lo"], spec["hi"]) * (1.0 - 0.32 * abs(x0 - 20) / (spread + 1))
        lean = (x0 - 20) / (spread + 1) * 0.44 + lb + rng.uniform(-0.18, 0.18)
        blades.append((abs(x0 - 20) * -1 + rng.random() * 3, x0, height, lean))
    blades.sort()
    for _d, x0, height, lean in blades:
        tone = int(clamp(2 + (1 if lean < 0 else 0) + rng.choice((0, 0, 1)) - (1 if abs(x0 - 20) < 2 else 0), 0, 4))
        tip = blade(px, x0, GROUND, height, lean, spec["arch"], tone, seed, violet=rng.random() < 0.12)
        if rng.random() < 0.24:
            glow.emit(px, tip[0], max(2, tip[1] - 1), None, SEED[1], 1)
    for key, lo_k, hi_k, kind in (("plumes", "plume_lo", "plume_hi", "plume"), ("pods", "pod_lo", "pod_hi", "pod"), ("oats", "oat_lo", "oat_hi", "oat"), ("foxtails", "fox_lo", "fox_hi", "foxtail")):
        cnt = spec.get(key, 0)
        for i in range(cnt):
            x0 = 20 + (i - (cnt - 1) / 2.0) * 2.5 + rng.uniform(-0.8, 0.8)
            height = rng.uniform(spec[lo_k], spec[hi_k])
            lean = (x0 - 20) / 20.0 + lb * 0.7
            tip = blade(px, x0, GROUND, height, lean, 0.38, 2, seed + i)
            head(px, glow, tip[0], tip[1], kind, seed + i)
    for y in range(2, FH - 1):
        for x in range(2, FW - 2):
            c = px[y][x]
            if c[3] == 255 and c in GRASS and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 88 and c in GRASS[1:4]:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 150)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, spec["spread"] + 3, 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base, glow.done()


def make_grass_stripped(spec, seed):
    rng = random.Random(seed)
    px = blank(FW, FH)
    put_shadow(px, [(20, GROUND - 2, spec["spread"] + 2, 2.5, 0)])
    for _ in range(int(spec["blades"] * 0.6)):
        x0 = 20 + rng.uniform(-spec["spread"], spec["spread"])
        blade(px, x0, GROUND, rng.uniform(1.5, 4.2), rng.uniform(-0.3, 0.3), 0.3, rng.choice((1, 2, 3)), seed)
    outline(px)
    return px


# ------------------------------------------------------------------ bramble
def cane(px, x0, spread_x, height, droop, thorns):
    p0 = (x0, GROUND + 0.5)
    p1 = (x0 + spread_x * 0.25, GROUND - height * 1.08)
    p2 = (x0 + spread_x * 0.78, GROUND - height * 1.20)
    p3 = (clamp(x0 + spread_x * 1.05, 3.0, FW - 4.0), clamp(GROUND - height * (1.20 - droop * 1.05), 4.0, GROUND - 2.0))
    pts = bezier(p0, p1, p2, p3, n=34)
    last = None
    for i, (x, y) in enumerate(pts):
        xi, yi = int(clamp(round(x), 2, FW - 3)), int(clamp(round(y), 2, GROUND))
        if (xi, yi) == last:
            continue
        last = (xi, yi)
        t = i / len(pts)
        tone = 2 if (spread_x < 0 or t < 0.3) else 1
        put(px, xi, yi, CANE[tone if x < 20 else max(tone - 1, 0)])
        if t < 0.16 and xi + 1 < FW - 2:
            put(px, xi + 1, yi, CANE[0])
        if thorns and i % 6 == 3 and 2 < xi < FW - 3 and yi > 3:
            put(px, xi + (1 if spread_x > 0 else -1), yi - 1, CANE[3])
    return pts


def leaves(px, pts, rng):
    for i in range(2, len(pts) - 1, 2):
        x, y = pts[i]
        side = rng.choice((-1, 1))
        for k in range(rng.choice((2, 3))):
            xx = int(clamp(round(x + side * (1 + k * 0.9)), 2, FW - 3))
            yy = int(clamp(round(y - 1 + rng.choice((-1, 0, 0, 1))), 2, GROUND - 1))
            lit = 4 if (side < 0 and k > 0) else (3 if k > 0 else 2)
            put(px, xx, yy, LEAF[lit])
            if yy + 1 <= GROUND:
                put(px, xx, yy + 1, LEAF[max(lit - 2, 0)])
        if rng.random() < 0.16:
            rx, ry = int(clamp(round(x + side * 2), 2, FW - 3)), int(clamp(round(y - 2), 2, GROUND - 2))
            put(px, rx, ry, ROSE)


def berry(px, glow, x, y, ripe_glow=True):
    x = int(clamp(x, 3, FW - 4))
    y = int(clamp(y, 3, GROUND - 3))
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (1, 1), (-1, 1), (0, 2), (0, -1)):
        if (dx, dy) == (-1, -1):
            continue
        lit = -dx - dy
        c = EMBER[3] if (dx, dy) in ((-1, 0), (0, -1)) else (EMBER[2] if lit >= 0 and dy <= 1 else (EMBER[1] if dy <= 1 else EMBER[0]))
        put(px, x + dx, y + dy, c)
    put(px, x, y, EMBER[2])
    if ripe_glow:
        glow.emit(px, x, y, EMBER[3], EMBER_CORE, 2)
        glow.emit(px, x - 1, y, None, EMBER_GLOW, 1)


def make_bramble(spec, seed, berries=True):
    rng = random.Random(seed)
    # Shaded interior thicket cushion behind the thorny canes for rich volume & LeafCritter support
    px, _band = render_body(spec["lobes"], LEAF, seed + 5, noise_amp=0.25, dither=0.72, leaf_marks=True, bias=-0.18)
    glow = Glow()
    n = spec["canes"]
    lean = spec.get("lean", 0.0)
    all_pts = []
    for i in range(n):
        side = -1 if i % 2 == 0 else 1
        x0 = 20 + lean * 0.4 + side * rng.uniform(1.0, 4.8) * (1 if i > 1 else 0.5)
        spread = side * (spec["spread"] * rng.uniform(0.55, 1.08)) + lean * 1.1
        height = spec["height"] * rng.uniform(0.62, 1.18)
        pts = cane(px, x0, spread, height, min(spec["droop"] * rng.uniform(0.75, 1.55), 1.06), thorns=True)
        all_pts.append(pts)
    for pts in all_pts:
        leaves(px, pts, rng)
    for _ in range(6 + spec["canes"]):
        blade(px, 20 + rng.uniform(-spec["spread"] * 0.75, spec["spread"] * 0.75), GROUND, rng.uniform(2, 5), rng.uniform(-0.4, 0.4), 0.4, rng.choice((1, 2, 3)), seed)
    if berries:
        tips = [p[-1] for p in all_pts] + [p[len(p) * 2 // 3] for p in all_pts] + [p[len(p) // 2] for p in all_pts]
        rng.shuffle(tips)
        placed = []
        for x, y in tips:
            xi, yi = int(clamp(round(x), 4, FW - 5)), int(clamp(round(y), 4, GROUND - 5))
            if len(placed) >= spec["berries"] or any(abs(xi - a) + abs(yi - b) < 4 for a, b in placed):
                continue
            for k in range(1, 3):
                put(px, xi, yi + k - 1, CANE[2])
            berry(px, glow, xi, yi + 2)
            placed.append((xi, yi))
    for _ in range(3):
        pts = all_pts[rng.randrange(len(all_pts))]
        x, y = pts[rng.randrange(len(pts) // 3, len(pts))]
        glow.emit(px, int(clamp(round(x), 3, FW - 4)), int(clamp(round(y) - 1, 3, GROUND - 3)), None, hexc("ffd8a0") if berries else hexc("78f4e6"), 1)
    for y in range(2, FH - 1):
        for x in range(2, FW - 2):
            c = px[y][x]
            if c[3] == 255 and c in LEAF[1:4] and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 96:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 150)]
            elif c[3] == 255 and c in LEAF[:5] and px[y - 1][x][3] == 0:
                px[y][x] = LEAF[min(LEAF.index(c) + 1, 5)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, min(17, spec["spread"] + 3), 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base, glow.done()


def make_bramble_stripped(spec, seed):
    rng = random.Random(seed)
    px = blank(FW, FH)
    put_shadow(px, [(20, GROUND - 2, min(16, spec["spread"] + 2), 2.5, 0)])
    for i in range(spec["canes"]):
        side = -1 if i % 2 == 0 else 1
        cane(px, 20 + side * rng.uniform(0.5, 3.0), side * spec["spread"] * rng.uniform(0.5, 0.95), spec["height"] * rng.uniform(0.48, 0.85), spec["droop"], thorns=True)
    outline(px)
    return px


# ------------------------------------------------------------------ icon
def icon_ember_berry():
    px = blank(16, 16)
    for x, y in ((8, 1), (8, 2), (8, 3), (8, 4)):
        px[y][x] = CANE[2]
    px[2][9], px[2][10], px[1][9] = LEAF[4], LEAF[3], LEAF[5]
    for cx, cy in ((5, 9), (9, 9), (7, 6)):
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (1, 1), (-1, 1), (0, 2), (0, -1), (1, -1)):
            lit = -dx - dy
            px[cy + dy][cx + dx] = EMBER[3] if lit > 1 else (EMBER[2] if lit >= 0 else (EMBER[1] if dy < 2 else EMBER[0]))
        px[cy][cx] = EMBER_CORE if (cx, cy) == (7, 6) else EMBER[3]
    px[8][4] = EMBER_CORE
    check_icon("ember_berry", px)
    return outline_pass(px, hexc("1b1a2e"))


def sheet(frames, cols, rows):
    out = [[CLEAR] * (FW * cols) for _ in range(FH * rows)]
    for i, f in enumerate(frames):
        cx, cy = (i % cols) * FW, (i // cols) * FH
        for y in range(FH):
            out[cy + y][cx:cx + FW] = f[y]
    return out


def main():
    props, items = ROOT / "props", ROOT / "items"
    ng = len(GRASSES)
    grass = [make_grass(s, 200 + i * 19) for i, s in enumerate(GRASSES)]
    write_png(props / "grass.png", FW * ng, FH, sheet([g[0] for g in grass], ng, 1))
    write_png(props / "grass_glow.png", FW * ng, FH, sheet([g[1] for g in grass], ng, 1))
    write_png(props / "grass_stripped.png", FW * ng, FH, sheet([make_grass_stripped(s, 300 + i) for i, s in enumerate(GRASSES)], ng, 1))

    nb = len(BRAMBLES)
    ripe = [make_bramble(s, 400 + i * 23) for i, s in enumerate(BRAMBLES)]
    bare = [make_bramble(s, 400 + i * 23, berries=False) for i, s in enumerate(BRAMBLES)]
    write_png(props / "bramble.png", FW * nb, FH * 2, sheet([f[0] for f in ripe + bare], nb, 2))
    write_png(props / "bramble_glow.png", FW * nb, FH * 2, sheet([f[1] for f in ripe + bare], nb, 2))
    write_png(props / "bramble_stripped.png", FW * nb, FH, sheet([make_bramble_stripped(s, 500 + i) for i, s in enumerate(BRAMBLES)], nb, 1))
    write_png(items / "ember_berry.png", 16, 16, icon_ember_berry())
    print(f"grass ({ng} variants), bramble ({nb} variants) and ember berry written")


if __name__ == "__main__":
    main()
