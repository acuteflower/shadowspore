#!/usr/bin/env python3
"""Draws the two newer bushes and the ember berry (stdlib only), frames 40x34 like the other bushes (feet at (20, 31)):
  assets/props/grass.png               Flüstergras: 5 grassy clumps (tuft, clump, pampas with plumes, wide carpet, glowing reeds)
  assets/props/grass_glow.png          the same layout, only the emissive parts (blade tips, plumes, seed pods)
  assets/props/grass_stripped.png      the stubble the sickle leaves
  assets/props/bramble.png             Glutbeerenranke: 3 arching brambles x 2 rows (ripe with glowing ember berries, picked)
  assets/props/bramble_glow.png        the same layout, only the emissive parts (berry cores and halos, a few thorn-tip sparks)
  assets/props/bramble_stripped.png    the bare canes the sickle leaves
  assets/items/ember_berry.png         icon 16x16
Light comes from the top left with a cool rim on the right (like the other bushes). The grass is made of single curved
blades; the bramble of thorny canes that arch up and droop, small leaves along them, berries hanging at the tips."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, FH, FW, GROUND, SHADOW, bezier, blank, check_icon, clamp, put_shadow  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

GRASS = [hexc(c) for c in ("12183a", "16403a", "22624a", "3a8a58", "62b868", "a4e890")]  # shade .. sunlit blade tips
RIM = [hexc("22707e"), hexc("4cc0c4")]
TIP = [hexc(c) for c in ("4a2c8a", "7048d0", "b89cff")]  # void-touched tips
PLUME = [hexc(c) for c in ("5a4e90", "8c80c0", "b8aee4", "e6e0fa")]
SEED = [hexc("2a9aa0"), hexc("78f4e6")]  # a glowing seed pod: dim, bright
SPEC = hexc("fff6c0")

CANE = [hexc(c) for c in ("2a1840", "4e2c60", "7a5088", "a880b0")]  # violet canes, lit on the left
LEAF = [hexc(c) for c in ("161a40", "1f3f4c", "2c6460", "3e8a6c", "6cb890", "a8ecb8")]
ROSE = hexc("e0a0c8")  # a few leaf tips blush
EMBER = [hexc(c) for c in ("6a1a14", "b83a18", "ee7a2a", "ffc05a")]  # shade .. lit
EMBER_CORE = hexc("fff0b0")
EMBER_GLOW = hexc("ffb25a")
INK = hexc("0c1020")

# (blades, spread, min height, max height, lean) per grass; pampas and reeds also carry heads
GRASSES = [
    {"blades": 15, "spread": 6, "lo": 8, "hi": 15, "arch": 0.5},
    {"blades": 24, "spread": 9, "lo": 10, "hi": 21, "arch": 0.8},
    {"blades": 20, "spread": 8, "lo": 7, "hi": 15, "arch": 0.5, "plumes": 5, "plume_lo": 21, "plume_hi": 29},
    {"blades": 42, "spread": 16, "lo": 4, "hi": 11, "arch": 0.6},
    {"blades": 14, "spread": 7, "lo": 6, "hi": 13, "arch": 0.4, "pods": 6, "pod_lo": 20, "pod_hi": 30},
]
# (canes, spread, height, droop) per bramble
BRAMBLES = [
    {"canes": 7, "spread": 9, "height": 15, "droop": 0.5, "berries": 6},
    {"canes": 9, "spread": 13, "height": 20, "droop": 0.55, "berries": 9},
    {"canes": 11, "spread": 16, "height": 17, "droop": 0.7, "berries": 8},
]


class Glow:
    """Emissive pixels: a dim colour goes into the lit art, the bright one (with a soft halo) into the glow layer."""

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
                        self.px[yy][xx] = (*color[:3], 110 if d < 1.6 else 52)
        return self.px


def put(px, x, y, c):
    if 0 <= x < FW and 0 <= y < FH:
        px[y][x] = c


def outline(px):
    src = [row[:] for row in px]
    for y in range(FH):
        for x in range(FW):
            if src[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < FW and 0 <= b < FH and src[b][a][3] == 255]
            if hit:
                px[y][x] = INK


# ------------------------------------------------------------------ grass
def blade(px, x0, y0, length, lean, arch, tone, seed, violet=False):
    """One blade from the ground: rises, then bends over, 2 px wide at the foot and 1 px at the tip; returns the tip."""
    tip = (x0, y0)
    for i in range(int(length) + 1):
        t = i / max(length, 1)
        x = x0 + lean * length * t + arch * lean * length * t * t * 0.9
        y = y0 - length * (t - 0.28 * arch * t * t)
        xi, yi = int(round(x)), int(round(y))
        shade = clamp(tone + (2 if t > 0.75 else 0) - (1 if t < 0.2 else 0) + (1 if lean < 0 else 0), 0, 5)
        col = GRASS[int(shade)]
        if violet and t > 0.8:
            col = TIP[int(t * 3) % 2]
        put(px, xi, yi, col)
        if t < 0.55:
            put(px, xi + 1, yi, GRASS[int(clamp(shade - 1, 0, 5))])  # the broad foot
        tip = (xi, yi)
    return tip


def head(px, glow, x, y, kind, seed):
    """A seed head at the top of a stalk: a feathery plume (pampas) or a glowing pod (reeds)."""
    if kind == "plume":
        for k in range(7):
            a = -math.pi / 2 + (k - 3) * 0.26
            for j in range(1, 4 + (1 if k % 2 == 0 else 0)):
                xx, yy = x + int(round(math.cos(a) * j * 0.9)), y + int(round(math.sin(a) * j * 1.05)) + 1
                put(px, xx, yy, PLUME[min(2, j // 2 + (1 if k < 3 else 0))])
        put(px, x, y - 2, PLUME[3])
        glow.emit(px, x, y - 2, None, PLUME[2], 2)
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
    blades = []
    for i in range(n):
        x0 = 20 + rng.uniform(-spread, spread)
        height = rng.uniform(spec["lo"], spec["hi"]) * (1.0 - 0.35 * abs(x0 - 20) / (spread + 1))
        lean = (x0 - 20) / (spread + 1) * 0.45 + rng.uniform(-0.2, 0.2)
        blades.append((abs(x0 - 20) * -1 + rng.random() * 3, x0, height, lean))  # the middle is drawn last (in front)... outer first
    blades.sort()
    for _d, x0, height, lean in blades:
        tone = int(clamp(2 + (1 if lean < 0 else 0) + rng.choice((0, 0, 1)) - (1 if abs(x0 - 20) < 2 else 0), 0, 4))
        tip = blade(px, x0, GROUND, height, lean, spec["arch"], tone, seed, violet=rng.random() < 0.12)
        if rng.random() < 0.28:
            glow.emit(px, tip[0], tip[1] - 1, None, SEED[1], 1)  # a speck of light on some tips
    for i in range(spec.get("plumes", 0)):  # tall stalks with feathery heads
        x0 = 20 + (i - spec["plumes"] / 2.0) * 2.4 + rng.uniform(-1, 1)
        height = rng.uniform(spec["plume_lo"], spec["plume_hi"])
        lean = (x0 - 20) / 18.0
        tip = blade(px, x0, GROUND, height, lean, 0.45, 2, seed + i)
        head(px, glow, tip[0], tip[1], "plume", seed + i)
    for i in range(spec.get("pods", 0)):  # reeds with glowing pods
        x0 = 20 + (i - spec["pods"] / 2.0) * 2.8 + rng.uniform(-1, 1)
        height = rng.uniform(spec["pod_lo"], spec["pod_hi"])
        lean = (x0 - 20) / 22.0
        tip = blade(px, x0, GROUND, height, lean, 0.3, 2, seed + i)
        head(px, glow, tip[0], tip[1], "pod", seed + i)
    for y in range(FH):  # cool light on the right, lit contour on the top
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and c in GRASS and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 90 and c in GRASS[1:4]:
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
    """The stubble after the sickle: short cut blades, a few bent ones."""
    rng = random.Random(seed)
    px = blank(FW, FH)
    put_shadow(px, [(20, GROUND - 2, spec["spread"] + 2, 2.5, 0)])
    for _ in range(int(spec["blades"] * 0.6)):
        x0 = 20 + rng.uniform(-spec["spread"], spec["spread"])
        blade(px, x0, GROUND, rng.uniform(1, 4), rng.uniform(-0.3, 0.3), 0.3, rng.choice((1, 2, 3)), seed)
    outline(px)
    return px


# ------------------------------------------------------------------ bramble
def cane(px, x0, spread_x, height, droop, rng, thorns):
    """A cane: up and out, then drooping; returns its points and its tip."""
    p0 = (x0, GROUND + 0.5)
    p1 = (x0 + spread_x * 0.25, GROUND - height * 1.1)
    p2 = (x0 + spread_x * 0.8, GROUND - height * 1.25)
    p3 = (x0 + spread_x * 1.1, GROUND - height * (1.25 - droop * 1.1))
    pts = bezier(p0, p1, p2, p3, n=34)
    last = None
    for i, (x, y) in enumerate(pts):
        xi, yi = int(round(x)), int(round(y))
        if (xi, yi) == last:
            continue
        last = (xi, yi)
        t = i / len(pts)
        tone = 2 if (spread_x < 0 or t < 0.3) else 1
        put(px, xi, yi, CANE[tone if x < 20 else max(tone - 1, 1)])
        if t < 0.12:
            put(px, xi + 1, yi, CANE[1])
        if thorns and i % 6 == 3:
            put(px, xi + (1 if spread_x > 0 else -1), yi - 1, CANE[3])
    return pts


def leaves(px, pts, rng, seed):
    for i in range(2, len(pts) - 1, 2):
        x, y = pts[i]
        side = rng.choice((-1, 1))
        for k in range(rng.choice((2, 3))):
            xx, yy = int(round(x + side * (1 + k * 0.9))), int(round(y - 1 + rng.choice((-1, 0, 0, 1))))
            lit = 4 if (side < 0 and k > 0) else (3 if k > 0 else 2)
            put(px, xx, yy, LEAF[lit])
            put(px, xx, yy + 1, LEAF[max(lit - 2, 0)])
        if rng.random() < 0.18:
            put(px, int(round(x + side * 2)), int(round(y - 2)), ROSE)


def berry(px, glow, x, y, ripe_glow=True):
    """A hanging ember berry: a drop with a lit top left and a hot core."""
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (1, 1), (-1, 1), (0, 2), (0, -1)):
        if (dx, dy) == (-1, -1):
            continue
        lit = -dx - dy
        put(px, x + dx, y + dy, EMBER[3] if (dx, dy) == (-1, 0) or (dx, dy) == (0, -1) else (EMBER[2] if lit >= 0 and dy <= 1 else (EMBER[1] if dy <= 1 else EMBER[0])))
    put(px, x, y, EMBER[2])
    if ripe_glow:
        glow.emit(px, x, y, EMBER[3], EMBER_CORE, 2)
        glow.emit(px, x - 1, y, None, EMBER_GLOW, 1)


def make_bramble(spec, seed, berries=True):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["canes"]
    all_pts = []
    for i in range(n):
        side = -1 if i % 2 == 0 else 1
        x0 = 20 + side * rng.uniform(1.0, 5.0) * (1 if i > 1 else 0.5)
        spread = side * (spec["spread"] * rng.uniform(0.55, 1.15))
        height = spec["height"] * rng.uniform(0.6, 1.25)
        pts = cane(px, x0, spread, height, min(spec["droop"] * rng.uniform(0.7, 1.7), 1.08), rng, thorns=True)
        all_pts.append(pts)
    for pts in all_pts:
        leaves(px, pts, rng, seed)
    for _ in range(6 + spec["canes"]):  # blades of grass at the foot ground the bramble
        blade(px, 20 + rng.uniform(-spec["spread"] * 0.8, spec["spread"] * 0.8), GROUND, rng.uniform(2, 5), rng.uniform(-0.4, 0.4), 0.4, rng.choice((1, 2, 3)), seed)
    if berries:
        tips = [p[-1] for p in all_pts] + [p[len(p) * 2 // 3] for p in all_pts]
        rng.shuffle(tips)
        placed = []
        for x, y in tips:
            xi, yi = int(round(x)), int(round(y))
            if len(placed) >= spec["berries"] or yi > GROUND - 4 or any(abs(xi - a) + abs(yi - b) < 5 for a, b in placed):
                continue
            for k in range(1, 3):  # a short stalk
                put(px, xi, yi + k - 1, CANE[2])
            berry(px, glow, xi, yi + 2)
            placed.append((xi, yi))
    for _ in range(3):  # a spark on a thorn tip
        pts = all_pts[rng.randrange(len(all_pts))]
        x, y = pts[rng.randrange(len(pts) // 3, len(pts))]
        glow.emit(px, int(round(x)), int(round(y)) - 1, None, hexc("ffd8a0") if berries else hexc("78f4e6"), 1)
    for y in range(FH):  # cool rim on the right
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and c in LEAF[1:4] and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 100:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 150)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, spec["spread"] + 4, 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base, glow.done()


def make_bramble_stripped(spec, seed):
    rng = random.Random(seed)
    px = blank(FW, FH)
    put_shadow(px, [(20, GROUND - 2, spec["spread"] + 3, 2.5, 0)])
    for i in range(spec["canes"]):
        side = -1 if i % 2 == 0 else 1
        pts = cane(px, 20 + side * rng.uniform(0.5, 3.0), side * spec["spread"] * rng.uniform(0.5, 1.0), spec["height"] * rng.uniform(0.5, 0.9), spec["droop"], rng, thorns=True)
    outline(px)
    return px


# ------------------------------------------------------------------ icon
def icon_ember_berry():
    px = blank(16, 16)
    g = Glow(16, 16)
    for x, y in ((8, 1), (8, 2), (8, 3), (8, 4)):  # stem
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
    grass = [make_grass(s, 200 + i * 19) for i, s in enumerate(GRASSES)]
    write_png(props / "grass.png", FW * len(grass), FH, sheet([g[0] for g in grass], len(grass), 1))
    write_png(props / "grass_glow.png", FW * len(grass), FH, sheet([g[1] for g in grass], len(grass), 1))
    write_png(props / "grass_stripped.png", FW * len(grass), FH, sheet([make_grass_stripped(s, 300 + i) for i, s in enumerate(GRASSES)], len(grass), 1))
    ripe = [make_bramble(s, 400 + i * 23) for i, s in enumerate(BRAMBLES)]
    bare = [make_bramble(s, 400 + i * 23, berries=False) for i, s in enumerate(BRAMBLES)]
    write_png(props / "bramble.png", FW * 3, FH * 2, sheet([f[0] for f in ripe + bare], 3, 2))
    write_png(props / "bramble_glow.png", FW * 3, FH * 2, sheet([f[1] for f in ripe + bare], 3, 2))
    write_png(props / "bramble_stripped.png", FW * 3, FH, sheet([make_bramble_stripped(s, 500 + i) for i, s in enumerate(BRAMBLES)], 3, 1))
    write_png(items / "ember_berry.png", 16, 16, icon_ember_berry())
    print("grass, bramble and ember berry written")


if __name__ == "__main__":
    main()
