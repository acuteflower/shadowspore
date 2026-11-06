#!/usr/bin/env python3
"""Draws the eight new meadow plants and their items (stdlib only), frames 40x34 like the bushes (feet at (20, 31)):
  assets/props/moonbell.png         Mondglöckchen: 3 stands of nodding bells x 2 rows (in bloom, picked)
  assets/props/wound_leaf.png       Wundblatt: 3 plantain rosettes x 2 rows (with violet spikes, trimmed)
  assets/props/puffseed.png         Wispersaat: 3 seed-head stands x 2 rows (fluffy globes, bare)
  assets/props/glowfern.png         Leuchtfern: 3 ferns x 2 rows (with glowing fiddleheads, without) + glowfern_stripped.png
  assets/props/cattail.png          Rohrkolben: 3 reed stands (+ cattail_stripped.png, the cut stubs)
  assets/props/sunbloom.png         Sonnenwende: 3 plants x 5 rows (turned east, up, west, closed for the night, picked)
  assets/props/voidbloom.png        Leerenblüte: 3 drooping blooms x 2 rows (open, wilted)
  assets/props/earth_tuber.png      Erdknolle: 3 leafy patches x 2 rows (tuber showing, dug up)
  every sheet has a `_glow` twin with only the emissive pixels (drawn unshaded, bright at night)
  assets/items/{moonbell,wound_leaf,seed_fluff,fiddlehead,fern_frond,reed,sun_seed,void_bloom,earth_tuber}.png  icons 16x16
Same light as the rest of the meadow: from the top left, a cool rim on the right, violet-ink outline, void-touched tips.
`python3 tools/art_flora.py [preview.png]` writes the files, the optional argument also a 4x contact sheet."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, INK, RIM, SEED, TIP, Glow, blade, outline, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, check_icon, clamp, put_shadow  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402


def ramp(*c):
    return [hexc(x) for x in c]


BELL = ramp("2a2a6a", "4a5aa8", "8ab8e0", "d6f2f4", "f4fff8")
TEAL_B = hexc("78f4e6")
LEAFW = ramp("12283a", "1c4a46", "2c6e54", "449a62", "6cc47a", "a4eca0")
SPIKE = ramp("4a2c6a", "8a5ab0", "c890d8", "f0c8f0")
PUFF = ramp("6a6aa0", "a0a0d0", "d0d0f0", "f6f4ff")
FERN = ramp("10223a", "1a4a48", "2a7254", "42a05e", "70cc78", "aef09a")
FID = ramp("4a7a24", "9ccc44", "e4f88e")
SPORE = hexc("66f0d8")
CAT = ramp("2a1a30", "4a2a3e", "7a4a52", "a87a6a")
SUNP = ramp("7a2a10", "c05a10", "f0a020", "ffd860", "fff0a0")
DISC = ramp("1a0e22", "3a1e3a", "5a3248", "7a5058")
VPET = ramp("0c0620", "220a44", "40146e", "6a2aa0", "a050e0")
VMAG, VMAG_L = hexc("ff4ad0"), hexc("ffa0ee")
TUB = ramp("3a2450", "6a4a80", "a082a8", "d8c0d0", "f4e8ec")
SOIL = ramp("1e1428", "3a2838", "5a4048", "7a6068")
CARG = ramp("10283a", "1c4a50", "2e7a64", "4aa87a", "7ad89a", "b8f4c0")
CARR = ramp("4a1410", "9a2e18", "e0701c", "ffa83a", "ffe08a")
EMBER_G, EMBER_GL = hexc("ffb25a"), hexc("fff0b0")
BEETR = ramp("0e0820", "2a1248", "4a2478", "7a3ca0", "a870d0")
BEETL = ramp("1a0a2a", "3a1450", "5a2a70", "7a4a98", "a070c0", "d0a0e8")
BEET_ST = ramp("4a0e3a", "8a1e64", "c8408c")
SHEEN = hexc("4cc8c8")
LILY = ramp("2e2262", "5a4a9c", "9a8cd4", "d4cdf2", "f8f4ff")
LILY_GLOW = hexc("c8b8ff")
STAMEN = hexc("ffe28a")
POP = ramp("4a0a1c", "a01428", "e03a22", "ff7a2a", "ffc060")
POP_GLOW, POP_HOT = hexc("ff8a3a"), hexc("ffe8a0")
LIGHT = (-0.55, -0.8)


# ------------------------------------------------------------------ helpers
def blob(px, cx, cy, rx, ry, colors, dither=True):
    """A shaded ellipse (lit from the top left, ordered dither between the bands)."""
    n = len(colors)
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            d = dx * dx + dy * dy
            if d > 1.0:
                continue
            lit = 0.5 + 0.4 * (dx * LIGHT[0] + dy * LIGHT[1]) + 0.25 * (math.sqrt(1.0 - d) - 0.5)
            if dither:
                lit += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.22
            put(px, x, y, colors[int(clamp(lit * n, 0, n - 1))])


def stem(px, pts, tone=2, thick=False):
    last = None
    for x, y in pts:
        xi, yi = int(round(x)), int(round(y))
        if (xi, yi) == last:
            continue
        last = (xi, yi)
        put(px, xi, yi, GRASS[tone])
        if thick:
            put(px, xi + 1, yi, GRASS[max(tone - 1, 0)])


def leaf(px, x0, y0, ang, length, wmax, colors, curve=0.0, tone=3):
    """A lanceolate leaf from (x0, y0) in direction `ang` (radians, 0 = right, -pi/2 = up), bending by `curve`."""
    x, y, a = float(x0), float(y0), ang
    steps = int(length * 3)
    for i in range(steps + 1):
        t = i / max(steps, 1)
        dx, dy = math.cos(a), math.sin(a)
        w = wmax * math.sin(math.pi * min(1.0, t ** 0.75))
        nx, ny = dy, -dx  # the upper side
        sign = 1 if nx * LIGHT[0] + ny * LIGHT[1] > 0 else -1
        s = -w
        while s <= w + 0.01:
            side = s * sign
            idx = tone + (1 if side > w * 0.2 else 0) - (1 if side < -w * 0.45 else 0) - (1 if t < 0.15 else 0)
            if abs(s) < 0.4 and w > 1.2:
                idx += 1  # the midrib
            put(px, int(round(x + nx * s)), int(round(y + ny * s)), colors[int(clamp(idx, 0, len(colors) - 1))])
            s += 0.5
        x += dx / 3.0
        y += dy / 3.0
        a += curve / steps


def finish(px, spread, seed):
    for y in range(FH):  # cool light on the right edge of the greens
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and (c in GRASS[1:4] or c in LEAFW[1:4] or c in FERN[1:4]) and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 100:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 150)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, spread + 3, 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base


def grass_foot(px, rng, seed, spread, n=6, hi=5):
    for _ in range(n):
        blade(px, 20 + rng.uniform(-spread, spread), GROUND, rng.uniform(2, hi), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2, 3)), seed)


def stalks_at(rng, n, spread):
    return [20 + (i - (n - 1) / 2.0) * (2.0 * spread / max(n, 1)) + rng.uniform(-1.2, 1.2) for i in range(n)]


# ------------------------------------------------------------------ Mondglöckchen
MOONBELLS = [
    {"stalks": 1, "spread": 3, "lo": 15, "hi": 18, "leaves": 4, "bells": 3},
    {"stalks": 3, "spread": 8, "lo": 14, "hi": 23, "leaves": 7, "bells": 3},
    {"stalks": 6, "spread": 11, "lo": 12, "hi": 24, "leaves": 11, "bells": 2},
]


def bell(px, glow, x, y, big):
    widths = [2, 4, 5, 6, 6, 7] if big else [2, 3, 4, 5, 5]
    for r, w in enumerate(widths):
        for c in range(w):
            xx = x - w // 2 + c
            idx = 3 if c < w // 2 else (2 if c == w // 2 else 1)
            if r == 0:
                idx = 2
            if r == len(widths) - 1:
                idx = 1 if 0 < c < w - 1 else 2  # the lilac, shadowed lip
            put(px, xx, y + r, BELL[idx])
    ly = y + len(widths) - 1
    glow.emit(px, x, ly, BELL[1], TEAL_B, 1)  # the light sits in the mouth
    if big:
        glow.emit(px, x + 1, ly, None, TEAL_B, 1)
    put(px, x - len(widths[:1]) , y + 1, BELL[4])


def make_moonbell(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["leaves"]):
        blade(px, 20 + rng.uniform(-spec["spread"], spec["spread"]), GROUND, rng.uniform(5, 11), rng.uniform(-0.7, 0.7), 0.6, rng.choice((1, 2, 3)), seed)
    for i, x0 in enumerate(stalks_at(rng, spec["stalks"], spec["spread"])):
        side = 1 if x0 >= 20 else -1
        h = rng.uniform(3, 5) if picked else rng.uniform(spec["lo"], spec["hi"])
        end = (x0 + side * rng.uniform(3, 6), GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 1.5, GROUND - h * 0.8), (x0 + side * 1.0, GROUND - h * 1.15), end, n=30)
        stem(px, pts, 2)
        if picked:
            continue
        for j in range(spec["bells"]):
            p = pts[int(len(pts) * (0.55 + 0.4 * j / max(spec["bells"] - 1, 1)))] if spec["bells"] > 1 else pts[-1]
            bx, by = int(round(p[0])) + side * 2, int(round(p[1])) + 2
            put(px, int(round(p[0])) + side, int(round(p[1])) + 1, GRASS[2])  # the little neck
            bell(px, glow, bx, by, big=(j == 0 and spec["stalks"] < 6) or j == spec["bells"] - 1)
        glow.emit(px, int(round(end[0])), int(round(end[1])) - 1, None, TEAL_B, 1)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Wundblatt
WOUNDS = [
    {"leaves": 7, "len": (8, 12), "spikes": 0, "spread": 6},
    {"leaves": 9, "len": (9, 15), "spikes": 2, "spread": 9},
    {"leaves": 11, "len": (8, 14), "spikes": 3, "spread": 12},
]


def make_wound(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["leaves"]
    angles = sorted(-math.pi / 2 + (i / max(n - 1, 1) - 0.5) * 2.5 + rng.uniform(-0.12, 0.12) for i in range(n))
    for a in sorted(angles, key=lambda v: -abs(v + math.pi / 2)):  # outer leaves first, the middle ones in front
        length = rng.uniform(*spec["len"]) * (0.45 if picked else 1.0)
        x0 = 20 + math.cos(a) * 1.5
        leaf(px, x0, GROUND - 1, a, length, 2.2 if not picked else 1.2, LEAFW, curve=-(a + math.pi / 2) * 0.55, tone=3)
        if not picked and rng.random() < 0.3:
            ex = x0 + math.cos(a) * length * 0.8
            ey = GROUND - 1 + math.sin(a) * length * 0.8
            glow.emit(px, int(round(ex)), int(round(ey)) - 1, None, hexc("c8fff0"), 1)  # a drop of dew on a tip
    if not picked:
        for i in range(spec["spikes"]):
            x0 = 20 + (i - (spec["spikes"] - 1) / 2.0) * 5 + rng.uniform(-1, 1)
            h = rng.uniform(15, 20)
            lean = (x0 - 20) / 30.0
            pts = bezier((x0, GROUND), (x0 + lean * 4, GROUND - h * 0.6), (x0 + lean * 12, GROUND - h), n=24)
            stem(px, pts, 2)
            tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
            for k in range(7):  # the flower spike: a violet cylinder of tiny blooms
                for dx in (-1, 0, 1):
                    put(px, tx + dx, ty + k - 3, SPIKE[2 if dx < 0 else (1 if dx == 0 and k % 2 else 3 if dx == 0 else 0)])
            put(px, tx, ty - 4, SPIKE[3])
            glow.emit(px, tx, ty - 4, SPIKE[3], hexc("f0b8ff"), 1)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Wispersaat
PUFFS = [
    {"stalks": 1, "spread": 3, "lo": 14, "hi": 17, "leaves": 6, "r": 5},
    {"stalks": 3, "spread": 8, "lo": 12, "hi": 20, "leaves": 8, "r": 4},
    {"stalks": 6, "spread": 9, "lo": 10, "hi": 21, "leaves": 11, "r": 4},
]


def puff_head(px, glow, cx, cy, r, rng):
    for k in range(18):  # filaments, each a fine line ending in a speck
        a = k / 18.0 * math.tau + rng.uniform(-0.1, 0.1)
        ln = r * rng.uniform(0.85, 1.1)
        for j in range(1, int(ln) + 1):
            col = PUFF[3] if (math.cos(a) < 0.2 and math.sin(a) < 0.2) else PUFF[2 if j < ln else 1]
            put(px, int(round(cx + math.cos(a) * j)), int(round(cy + math.sin(a) * j)), col)
        ex, ey = int(round(cx + math.cos(a) * (ln + 0.5))), int(round(cy + math.sin(a) * (ln + 0.5)))
        put(px, ex, ey, PUFF[3])
        if k % 3 == 0:
            glow.emit(px, ex, ey, PUFF[3], hexc("e0f4ff"), 1)
    put(px, int(cx), int(cy), PUFF[1])
    put(px, int(cx) - 1, int(cy), PUFF[0])


def make_puff(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["leaves"]):  # a ragged rosette
        a = -math.pi / 2 + rng.uniform(-1.35, 1.35)
        leaf(px, 20 + math.cos(a) * 2, GROUND - 1, a, rng.uniform(6, 10), 1.5, LEAFW, curve=rng.uniform(-0.5, 0.5), tone=3)
    for x0 in stalks_at(rng, spec["stalks"], spec["spread"]):
        h = rng.uniform(4, 7) if picked else rng.uniform(spec["lo"], spec["hi"])
        lean = (x0 - 20) / 40.0 + rng.uniform(-0.05, 0.05)
        pts = bezier((x0, GROUND + 0.5), (x0 + lean * h * 0.3, GROUND - h * 0.6), (x0 + lean * h * 1.2, GROUND - h), n=26)
        stem(px, pts, 2)
        tx, ty = pts[-1]
        if picked:
            put(px, int(tx), int(ty) - 1, DISC[2])
            put(px, int(tx), int(ty), DISC[1])
        else:
            puff_head(px, glow, tx, ty - spec["r"] + 1, spec["r"], rng)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Leuchtfern
FERNS = [
    {"fronds": 5, "len": 11, "spread": 8, "fiddles": 1},
    {"fronds": 7, "len": 13, "spread": 12, "fiddles": 2},
    {"fronds": 9, "len": 15, "spread": 14, "fiddles": 3},
]


def frond(px, glow, x0, side, length, rise, rng, seed):
    p0 = (x0, GROUND)
    pts = bezier(p0, (x0 + side * length * 0.2, GROUND - rise), (x0 + side * length * 0.8, GROUND - rise * 1.15), (x0 + side * length, GROUND - rise * 0.35), n=40)
    for i in range(0, len(pts) - 2, 2):
        x, y = pts[i]
        nx, ny = pts[i + 1][0] - x, pts[i + 1][1] - y
        ln = math.hypot(nx, ny) or 1.0
        t = i / len(pts)
        pl = max(1.0, (1.0 - t) ** 0.8 * (length * 0.2 + 1.0))  # pinnae shrink toward the tip
        for sgn in (-1, 1):
            ox, oy = (-ny / ln) * sgn, (nx / ln) * sgn
            for k in range(1, int(pl) + 1):
                tone = 3 + (1 if (oy * sgn > 0 or ox < 0) and k < pl else 0) - (1 if k == int(pl) and sgn > 0 else 0)
                put(px, int(round(x + ox * k + nx / ln * k * 0.6)), int(round(y + oy * k * 0.9 + ny / ln * k * 0.6 + 0.4 * k)), FERN[int(clamp(tone, 1, 5))])
        put(px, int(round(x)), int(round(y)), FERN[2])
        if i % 8 == 4 and rng.random() < 0.7:
            glow.emit(px, int(round(x)), int(round(y)) + 1, None, SPORE, 1)  # spores on the underside shine through


def fiddlehead(px, glow, x, y, size):
    """A curled young frond on a short stalk, standing out above the fronds."""
    top = y - 7
    for k in range(7):
        put(px, int(x), y - k, FID[0])
    pts = []
    for i in range(30):
        t = i / 29.0
        ang = math.pi / 2 + t * 4.6
        rr = (size + 1) * (1.0 - t * 0.8)
        pts.append((x + math.cos(ang) * rr, top - size + math.sin(ang) * rr))
    for i, (cx, cy) in enumerate(pts):
        put(px, int(round(cx)), int(round(cy)), FID[1 if i > 12 else 0])
    glow.emit(px, int(round(pts[-1][0])), int(round(pts[-1][1])), FID[2], hexc("d8ff80"), 2)


def make_fern(spec, seed, picked=False, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["fronds"]
    order = sorted(range(n), key=lambda i: -abs(i - (n - 1) / 2.0))
    for i in order:
        side = -1 if i % 2 == 0 else 1
        frac = abs(i - (n - 1) / 2.0) / max((n - 1) / 2.0, 1)
        length = spec["len"] * (0.55 + 0.45 * rng.random()) * (0.45 if stripped else 1.0)
        rise = (6 + length * 0.55) * (1.0 - 0.25 * frac) * (0.4 if stripped else 1.0)
        frond(px, glow, 20 + side * rng.uniform(0.5, 2.5), side, length, rise, rng, seed + i)
    if not picked and not stripped:
        for i in range(spec["fiddles"]):
            fiddlehead(px, glow, 20 + (i - (spec["fiddles"] - 1) / 2.0) * 5 + rng.uniform(-1, 1), GROUND - 1, 2 + (i % 2))
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Rohrkolben
CATTAILS = [
    {"stems": 4, "spread": 6, "lo": 15, "hi": 20},
    {"stems": 7, "spread": 9, "lo": 13, "hi": 21},
    {"stems": 10, "spread": 12, "lo": 11, "hi": 21},
]


def make_cattail(spec, seed, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["stems"] + 3):  # long ribbon leaves
        a = -math.pi / 2 + rng.uniform(-0.9, 0.9)
        leaf(px, 20 + rng.uniform(-spec["spread"], spec["spread"]) * 0.8, GROUND, a, rng.uniform(7, 14) * (0.35 if stripped else 1), 1.0, LEAFW, curve=rng.uniform(-0.8, 0.8), tone=3)
    for x0 in stalks_at(rng, spec["stems"], spec["spread"]):
        h = rng.uniform(2, 4) if stripped else rng.uniform(spec["lo"], spec["hi"])
        lean = (x0 - 20) / 34.0 + rng.uniform(-0.06, 0.06)
        pts = bezier((x0, GROUND + 0.5), (x0 + lean * h * 0.4, GROUND - h * 0.6), (x0 + lean * h * 1.1, GROUND - h), n=24)
        stem(px, pts, 2)
        if stripped:
            continue
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        top = ty + 1
        for k in range(7):  # the brown club
            for dx in (-1, 0, 1):
                put(px, tx + dx, top + k - 7, CAT[2 if dx < 0 else (1 if dx == 0 else 0)] if k not in (0, 6) or dx == 0 else CAT[0])
        put(px, tx - 1, top - 6, CAT[3])
        put(px, tx, top - 8, GRASS[3])
        put(px, tx, top - 9, GRASS[4])
        if rng.random() < 0.5:
            glow.emit(px, tx + 2, top - 3, None, TEAL_B, 0)  # a tuft of fluff in the air
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Sonnenwende
SUNS = [
    {"stalks": [(20, 17, 4)], "spread": 6},
    {"stalks": [(20, 18, 5)], "spread": 7},
    {"stalks": [(15, 18, 5), (26, 13, 4)], "spread": 9},
]


def petals(px, glow, cx, cy, rx, ry, count, length, rng, dim=False):
    for k in range(count):
        a = k / count * math.tau
        for j in range(int(length)):
            r = 1.0 + j / max(length - 1, 1)
            x = int(round(cx + math.cos(a) * rx * r))
            y = int(round(cy + math.sin(a) * ry * r))
            idx = (2 + (1 if math.cos(a) < 0 and math.sin(a) < 0.4 else 0) + (1 if j < length - 1 else 0)) - (2 if dim else 0)
            idx = int(clamp(idx - (1 if math.sin(a) > 0.5 else 0), 0, 4))
            put(px, x, y, SUNP[idx])
            if j == int(length) - 1 and k % 2 == 0:
                glow.emit(px, x, y, None, SUNP[3], 1)


def make_sun(spec, seed, pose):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for x0, h, r in spec["stalks"]:
        h = h * (0.3 if pose == 4 else 1.0)
        side = {0: 1, 1: 0, 2: -1, 3: 1, 4: 1}[pose]
        droop = pose in (3, 4)
        end = (x0 + (side * 2 if pose < 3 else 4), GROUND - h + (3 if droop else 0))
        pts = bezier((x0, GROUND + 0.5), (x0 - 1.5, GROUND - h * 0.6), end, n=30) if not droop else bezier((x0, GROUND + 0.5), (x0, GROUND - h), (x0 + 5, GROUND - h * 0.75), end, n=30)
        stem(px, pts, 2, thick=True)
        for i, t in enumerate((0.25, 0.5)):  # two broad leaves on the stem
            p = pts[int(len(pts) * t)]
            for sgn in (-1, 1):
                if (i + (sgn > 0)) % 2 == 0 or h > 22:
                    leaf(px, p[0], p[1], -math.pi / 2 + sgn * 1.1, 6 - i, 2.0, LEAFW, curve=sgn * 0.5, tone=3)
        cx, cy = end
        if pose == 4:
            blob(px, cx, cy + 1, 2.2, 2.0, DISC)
            continue
        if pose == 3:  # closed for the night: a green-sheathed bud hanging down with an amber tip
            blob(px, cx + 1, cy + 3, r * 0.4 + 1.2, r * 0.6 + 2.2, LEAFW[2:5])
            blob(px, cx + 1, cy + r * 0.6 + 4.5, 1.6, 1.8, SUNP[1:4], dither=False)
            glow.emit(px, int(cx + 1), int(cy + r * 0.6 + 5), SUNP[2], SUNP[4], 1)
            continue
        rx, ry = {0: (r * 0.45, r), 1: (r, r * 0.95), 2: (r * 0.45, r)}[pose]
        shift = {0: 1.5, 1: 0.0, 2: -1.5}[pose]
        petals(px, glow, cx + shift, cy - r * 0.6, rx * 0.6, ry * 0.6, 12, 3, rng)
        blob(px, cx + shift, cy - r * 0.6, max(rx * 0.75, 1.5), ry * 0.75, DISC)
        glow.emit(px, int(cx + shift), int(cy - r * 0.6), DISC[3], hexc("ffcf70"), 0)
    return finish(px, spec["spread"], seed + pose), glow.done()


# ------------------------------------------------------------------ Leerenblüte
VOIDS = [
    {"stalks": 1, "spread": 4, "h": (16, 18), "tendrils": 3},
    {"stalks": 2, "spread": 8, "h": (14, 22), "tendrils": 5},
    {"stalks": 3, "spread": 12, "h": (13, 24), "tendrils": 6},
]


def void_flower(px, glow, x, y, rng):
    """A drooping orchid: three long petals hanging from a throat that glows magenta."""
    for sgn, ln in ((-1, 6), (0, 8), (1, 6)):
        for k in range(ln):
            w = 2 if k < ln - 2 else 1
            for dx in range(w):
                xx = x + sgn * (1 + k // 3) - (w // 2) + dx
                col = VPET[int(clamp(3 - k // 3 - (1 if sgn > 0 else 0) + (1 if dx == 0 and sgn <= 0 else 0), 0, 4))]
                put(px, xx, y + 1 + k, col)
        glow.emit(px, x + sgn * (1 + (ln - 1) // 3), y + ln, VPET[3], VMAG, 1)  # the tip of every petal glows
    for k in range(3):
        put(px, x, y + 1 + k * 2, VMAG if k == 0 else VPET[2])
    glow.emit(px, x, y, VMAG, VMAG_L, 2)


def make_void(spec, seed, wilted=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["tendrils"]):  # thin leaves like wavering ribbons
        a = -math.pi / 2 + rng.uniform(-1.2, 1.2)
        leaf(px, 20 + rng.uniform(-3, 3), GROUND, a, rng.uniform(6, 11) * (0.5 if wilted else 1.0), 1.1, VPET, curve=rng.uniform(-1.0, 1.0), tone=2)
    for x0 in stalks_at(rng, spec["stalks"], spec["spread"]):
        h = rng.uniform(*spec["h"]) * (0.45 if wilted else 1.0)
        side = 1 if x0 >= 20 else -1
        end = (x0 + side * 3, GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 2, GROUND - h * 0.9), end, n=26)
        for x, y in pts:
            put(px, int(round(x)), int(round(y)), VPET[2])
        ex, ey = int(round(end[0])), int(round(end[1]))
        if wilted:
            put(px, ex, ey + 1, VPET[1])
            put(px, ex, ey + 2, VPET[0])
        else:
            void_flower(px, glow, ex, ey, rng)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Erdknolle
TUBERS = [
    {"tubers": [(20, 27)], "leaves": 5, "spread": 7},
    {"tubers": [(15, 27), (25, 28)], "leaves": 8, "spread": 11},
    {"tubers": [(13, 28), (21, 27), (28, 28)], "leaves": 11, "spread": 14},
]


def make_tuber(spec, seed, dug=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for tx, ty in spec["tubers"]:  # the earth round them
        blob(px, tx, ty + 1, 5.5, 3.0, SOIL)
    if dug:
        for tx, ty in spec["tubers"]:
            blob(px, tx, ty + 1, 3.2, 1.6, [SOIL[0], SOIL[0], SOIL[1]], dither=False)
            put(px, tx - 3, ty - 1, SOIL[3])
            put(px, tx + 3, ty, SOIL[3])
    else:
        for tx, ty in spec["tubers"]:
            blob(px, tx, ty - 0.5, 4.0, 3.2, TUB)  # the pale shoulder pushing out of the soil
            put(px, tx - 1, ty - 2, TUB[4])
    n = spec["leaves"] if not dug else 3
    for i in range(n):
        tx, ty = spec["tubers"][i % len(spec["tubers"])]
        a = -math.pi / 2 + rng.uniform(-1.1, 1.1)
        leaf(px, tx, ty - 2, a, rng.uniform(7, 13) * (0.55 if dug else 1.0), 2.4 if not dug else 1.6, LEAFW, curve=rng.uniform(-0.5, 0.5), tone=3 if not dug else 2)
    if not dug and rng.random() < 2:
        glow.emit(px, spec["tubers"][0][0] + 1, spec["tubers"][0][1] - 2, TUB[3], hexc("e8d8ff"), 1)  # a faint violet shimmer on the skin
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Glutmöhre and Nachtrübe: the two roots you pull out of the ground
CARROTS = [
    {"crowns": [(20, 3.0)], "stalks": 6, "len": (9, 14), "spread": 8},
    {"crowns": [(20, 3.8)], "stalks": 9, "len": (11, 16), "spread": 10},
    {"crowns": [(15, 3.2), (25, 3.0)], "stalks": 10, "len": (8, 12), "spread": 11},
]
BEETS = [
    {"crowns": [(20, 5.0)], "leaves": 4, "len": (8, 11), "spread": 8},
    {"crowns": [(20, 6.0)], "leaves": 6, "len": (9, 13), "spread": 10},
    {"crowns": [(15, 5.0), (26, 4.2)], "leaves": 7, "len": (8, 12), "spread": 12},
]


def crater(px, rng, crowns, big):
    """What is left when a root has been pulled: a dark hole, heaped crumbs of earth, torn rootlets."""
    for cx, r in crowns:
        blob(px, cx, GROUND - 0.5, r + 3.5, 3.0, SOIL)
        blob(px, cx, GROUND - 0.2, r * 0.75 + 1, 1.7, [SOIL[0], SOIL[0], SOIL[1]], dither=False)
        for _ in range(5 + int(r)):
            a = rng.uniform(0, math.tau)
            x, y = cx + math.cos(a) * (r + 3.5) * rng.uniform(0.7, 1.35), GROUND - 0.5 + math.sin(a) * 3.2 * rng.uniform(0.6, 1.2)
            blob(px, x, y - 0.5, 1.3, 1.0, SOIL[1:], dither=False)
        for k in (-1, 1):  # torn rootlets stick out of the hole
            put(px, int(cx + k * 1.5), GROUND - 1, TUB[3])
            put(px, int(cx + k * 2.5), GROUND - 2, TUB[2])
    for _ in range(3):
        blade(px, 20 + rng.uniform(-big, big), GROUND, rng.uniform(1, 3), rng.uniform(-0.5, 0.5), 0.3, rng.choice((1, 2)), 5)


def carrot_leaf(px, glow, x0, y0, length, side, rng):
    """A feathery carrot frond: a thin stalk that arches over, fine paired leaflets all along it."""
    end = (x0 + side * length * 0.7, y0 - length)
    pts = bezier((x0, y0), (x0 + side * 1.0, y0 - length * 0.7), (x0 + side * length * 0.25, y0 - length * 1.05), end, n=30)
    stem(px, pts, 2)
    for i in range(6, len(pts), 3):
        x, y = pts[i]
        t = i / len(pts)
        ln = 2.4 - 1.2 * abs(t - 0.6)
        for sgn in (-1, 1):
            for k in range(1, int(ln + 1)):
                put(px, int(round(x + sgn * k)), int(round(y - k * 0.5 + 0.3 * k * k * 0.2)), CARG[int(clamp(3 + (1 if sgn < 0 else 0) + (1 if k == int(ln) else 0), 1, 5))])
    put(px, int(round(end[0])), int(round(end[1])) - 1, CARG[5])
    if rng.random() < 0.35:
        glow.emit(px, int(round(end[0])), int(round(end[1])) - 2, None, EMBER_G, 0)


def make_carrot(spec, seed, pulled=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        crater(px, rng, spec["crowns"], spec["spread"])
        return finish(px, spec["spread"], seed), glow.done()
    for cx, r in spec["crowns"]:
        blob(px, cx, GROUND - 0.5, r + 3.0, 2.8, SOIL)  # the earth heaps round the crown
    for i in range(spec["stalks"]):
        cx, r = spec["crowns"][i % len(spec["crowns"])]
        side = -1 if i % 2 == 0 else 1
        carrot_leaf(px, glow, cx + side * rng.uniform(0, 2), GROUND - 2, rng.uniform(*spec["len"]), side, rng)
    for cx, r in spec["crowns"]:  # the orange shoulder of the carrot, rings on it, glowing where the greens leave it
        blob(px, cx, GROUND - 1.5, r, 2.6, CARR)
        for k in (-1, 1):
            put(px, int(cx + k * (r - 1.2)), GROUND - 1, CARR[1])
        put(px, int(cx) - 1, GROUND - 3, CARR[4])
        glow.emit(px, int(cx), GROUND - 2, CARR[3], EMBER_GL, 2)
    for _ in range(3):
        blade(px, 20 + rng.uniform(-spec["spread"], spec["spread"]), GROUND, rng.uniform(2, 4), rng.uniform(-0.6, 0.6), 0.4, rng.choice((1, 2, 3)), seed)
    return finish(px, spec["spread"], seed), glow.done()


def make_beet(spec, seed, pulled=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        crater(px, rng, [(cx, r * 0.8) for cx, r in spec["crowns"]], spec["spread"])
        return finish(px, spec["spread"], seed), glow.done()
    for cx, r in spec["crowns"]:
        blob(px, cx, GROUND - 0.5, r + 3.0, 3.0, SOIL)
    for i in range(spec["leaves"]):
        cx, r = spec["crowns"][i % len(spec["crowns"])]
        side = -1 if i % 2 == 0 else 1
        h = rng.uniform(*spec["len"])
        end = (cx + side * rng.uniform(1.5, 5.0), GROUND - 3 - h)
        pts = bezier((cx + side * rng.uniform(0, 2), GROUND - 3), (cx, GROUND - 3 - h * 0.7), end, n=22)
        for x, y in pts:  # the thick wine-red leaf stalk
            put(px, int(round(x)), int(round(y)), BEET_ST[1])
            put(px, int(round(x)) + 1, int(round(y)), BEET_ST[0])
        leaf(px, end[0], end[1] + 1, -math.pi / 2 + side * 0.55, 8 + rng.random() * 2, 2.9, BEETL, curve=side * 0.45, tone=3)
        if rng.random() < 0.6:
            glow.emit(px, int(round(end[0] + side * 2)), int(round(end[1])) - 3, None, SHEEN, 0)
    for cx, r in spec["crowns"]:  # the round dark shoulder with pale growth rings and a sheen
        blob(px, cx, GROUND - r * 0.45, r, r * 0.8, BEETR)
        for k in range(1, 3):
            for a in range(190, 350, 10):
                x = int(round(cx + math.cos(math.radians(a)) * r * (0.35 * k + 0.15)))
                y = int(round(GROUND - r * 0.45 + math.sin(math.radians(a)) * r * 0.8 * (0.35 * k + 0.1)))
                put(px, x, y, BEETR[1])
        put(px, int(cx) - 2, int(GROUND - r * 0.9), BEETR[4])
        glow.emit(px, int(cx) + 1, int(GROUND - r * 0.7), BEETR[3], SHEEN, 1)
        glow.emit(px, int(cx) - 2, int(GROUND - r * 0.35), None, VMAG, 0)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Nebellilie and Funkenmohn: two flowers with a habit of their own
LILIES = [
    {"stalks": [(20, 16)], "leaves": 5, "spread": 7},
    {"stalks": [(15, 14), (25, 18)], "leaves": 8, "spread": 10},
    {"stalks": [(12, 12), (20, 18), (28, 14)], "leaves": 11, "spread": 13},
]
POPPIES = [
    {"stalks": 3, "spread": 5, "lo": 13, "hi": 19, "leaves": 5},
    {"stalks": 5, "spread": 9, "lo": 12, "hi": 21, "leaves": 8},
    {"stalks": 8, "spread": 12, "lo": 11, "hi": 21, "leaves": 11},
]


def lily_flower(px, glow, cx, cy, rng):
    """A six-pointed star seen from the front and above: back petals first, then the two in front; gold stamens glow."""
    for deg in (-155, -115, -65, -25, 165, 15, 90):
        a = math.radians(deg)
        front = deg in (165, 15, 90)
        leaf(px, cx + math.cos(a) * 0.8, cy + math.sin(a) * 0.6, a, 6.5 if not front else 5.5, 1.9, LILY, curve=(0.4 if math.cos(a) > 0 else -0.4) * (0.6 if front else 1.0), tone=2)
        mx, my = cx + math.cos(a) * 3.4, cy + math.sin(a) * 3.0
        if rng.random() < 0.8:
            put(px, int(round(mx)), int(round(my)), LILY[0] if not front else LILY[1])  # violet freckles
    put(px, int(cx), int(cy), VPET[2])
    for k, dx in enumerate((-2, 0, 2)):  # three long stamens
        for j in range(1, 4):
            put(px, int(cx + dx * j / 3.0), int(cy - j - 1), LILY[3])
        glow.emit(px, int(cx + dx), int(cy) - 5, STAMEN, STAMEN, 1)
    glow.emit(px, int(cx), int(cy), None, LILY_GLOW, 1)


def lily_bud(px, glow, cx, cy):
    """Closed for the day: a long pointed bud wrapped in a green sheath."""
    blob(px, cx, cy - 3, 2.3, 4.8, LILY[:4])
    blob(px, cx, cy + 0.5, 2.0, 2.2, LEAFW[2:5], dither=False)
    put(px, int(cx), int(cy) - 8, LILY[4])
    glow.emit(px, int(cx), int(cy) - 7, None, LILY_GLOW, 0)


def make_lily(spec, seed, row):
    """row 0 open (night), 1 closed (day), 2 picked."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["leaves"]):
        blade(px, 20 + rng.uniform(-spec["spread"], spec["spread"]), GROUND, rng.uniform(5, 10), rng.uniform(-0.7, 0.7), 0.5, rng.choice((1, 2, 3)), seed)
    for x0, h in spec["stalks"]:
        h = 3 if row == 2 else h
        end = (x0 + (x0 - 20) * 0.08, GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - 1, GROUND - h * 0.6), end, n=24)
        stem(px, pts, 2, thick=True)
        if row == 2:
            continue
        p = pts[len(pts) // 2]
        leaf(px, p[0], p[1], -math.pi / 2 - 0.9 * (1 if x0 >= 20 else -1), 6, 1.4, LEAFW, curve=0.3, tone=3)
        (lily_flower if row == 0 else lambda a, b, c, d, e: lily_bud(a, b, c, d))(px, glow, end[0], end[1] - (3 if row == 0 else 0), rng)
    return finish(px, spec["spread"], seed + row), glow.done()


def poppy_flower(px, glow, cx, cy, r, rng):
    """A cup of four crumpled petals, crimson with a hot orange lit edge, black blotches and a dark heart."""
    blob(px, cx, cy - r * 0.35, r * 0.85, r * 0.7, POP)
    blob(px, cx - r * 0.55, cy + r * 0.15, r * 0.7, r * 0.8, POP)
    blob(px, cx + r * 0.55, cy + r * 0.15, r * 0.7, r * 0.8, POP)
    blob(px, cx, cy, r * 0.38, r * 0.3, DISC, dither=False)
    put(px, int(cx - r * 0.5), int(cy + r * 0.3), POP[0])
    put(px, int(cx + r * 0.6), int(cy), POP[0])
    for k in (-1, 0, 1):  # the sparks: stamens tipped with glowing pollen
        put(px, int(cx + k * 1.2), int(cy) - 1, DISC[3])
    glow.emit(px, int(cx), int(cy) - 1, POP[4], POP_HOT, 1)
    for dx, dy in ((-r * 0.9, -r * 0.5), (r * 0.9, r * 0.1), (-r * 0.2, -r * 1.0)):
        glow.emit(px, int(round(cx + dx)), int(round(cy + dy)), None, POP_GLOW, 0)  # the lit rims shine like embers


def make_poppy(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["leaves"]):  # deeply cut grey-green leaves low on the ground
        a = -math.pi / 2 + rng.uniform(-1.3, 1.3)
        leaf(px, 20 + math.cos(a) * 2, GROUND - 1, a, rng.uniform(5, 9), 1.5, LEAFW, curve=rng.uniform(-0.6, 0.6), tone=2)
    for i, x0 in enumerate(stalks_at(rng, spec["stalks"], spec["spread"])):
        h = rng.uniform(3, 5) if picked else rng.uniform(spec["lo"], spec["hi"])
        side = 1 if x0 >= 20 else -1
        bud = (i % 3 == 1) and not picked  # some are still drooping, hairy buds
        end = (x0 + side * rng.uniform(0.5, 2.5), GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 1.5, GROUND - h * 0.7), end, n=24) if not bud else bezier((x0, GROUND + 0.5), (x0, GROUND - h), (x0 + side * 3, GROUND - h * 0.9), (x0 + side * 3.5, GROUND - h * 0.55), n=24)
        stem(px, pts, 2)
        for k in range(2, len(pts) - 2, 4):  # hairs on the stem
            put(px, int(round(pts[k][0])) + side, int(round(pts[k][1])), GRASS[4])
        if picked:
            continue
        ex, ey = pts[-1]
        if bud:
            blob(px, ex, ey + 2, 1.9, 2.7, POP[1:4])
            put(px, int(ex), int(ey), LEAFW[3])
            glow.emit(px, int(ex), int(ey) + 4, None, POP_GLOW, 0)
        else:
            poppy_flower(px, glow, ex, ey - 2, 3.6 if spec["stalks"] < 8 else 3.2, rng)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ icons (16x16, one connected piece, 1 px margin)
def icon(name, draw):
    px = blank(16, 16)
    g = Glow(16, 16)
    draw(px, g)
    check_icon(name, px)
    return outline_pass(px, hexc("1b1a2e"))


def i_moonbell(px, g):
    for y in range(2, 14):
        px[y][8] = GRASS[2]
    px[13][6], px[12][6], px[13][10], px[12][10] = GRASS[3], GRASS[3], GRASS[3], GRASS[3]
    px[12][7], px[12][9] = GRASS[2], GRASS[2]
    for (nx, ny), cx, y in (((7, 3), 5, 4), ((9, 7), 11, 8)):
        px[ny][nx] = GRASS[2]
        px[ny + 1][nx + (-1 if nx < 8 else 1)] = GRASS[2]
        for r, w in enumerate((3, 5, 5, 6)):
            for c in range(w):
                px[y + r][cx - w // 2 + c] = BELL[3 if c < w // 2 else 2] if r < 3 else BELL[1]
    px[11][11] = TEAL_B
    px[7][5] = TEAL_B


def i_wound(px, g):
    for i, (a, ln) in enumerate(((-2.2, 7), (-1.57, 8), (-0.95, 7))):
        for t in range(ln):
            x, y = 8 + math.cos(a) * t, 13 + math.sin(a) * t * 1.05
            for s in (-1, 0, 1):
                xx = int(round(x + s * (0 if abs(math.cos(a)) > 0.7 else 1)))
                yy = int(round(y + (s if abs(math.cos(a)) > 0.7 else 0)))
                if 0 < xx < 15 and 0 < yy < 15 and (abs(s) < 1 or t in (2, 3, 4)):
                    px[yy][xx] = LEAFW[3 + (1 if s < 0 else 0)] if s else LEAFW[5]


def i_fluff(px, g):
    for k in range(14):
        a = k / 14.0 * math.tau
        for j in range(1, 5):
            px[int(round(7 + math.sin(a) * j))][int(round(8 + math.cos(a) * j))] = PUFF[3 if j < 4 else 2]
    px[7][8] = PUFF[1]
    for y in range(11, 14):
        px[y][8] = GRASS[2]
    px[13][8] = GRASS[1]


def i_fiddle(px, g):
    pts = []
    for i in range(34):
        t = i / 33.0
        ang = -math.pi / 2 + t * 4.4
        rr = 4.4 * (1.0 - t * 0.8)
        pts.append((8 + math.cos(ang) * rr - 1, 6 + math.sin(ang) * rr))
    for i, (x, y) in enumerate(pts):
        px[int(round(y))][int(round(x))] = FID[1 if i > 14 else 0]
        if i > 14:
            px[int(round(y)) + 1][int(round(x))] = FID[0]
    px[8][8] = FID[2]
    for y in range(10, 14):
        px[y][7] = FID[0]


def i_frond(px, g):
    for i in range(12):
        x, y = 3 + i, 13 - int(math.sin(i / 11.0 * 2.2) * 8)
        px[y][x] = FERN[2]
        if i % 2 == 1 and i < 11:
            px[y - 1][x] = FERN[4]
            px[y - 2][x] = FERN[3] if i < 9 else FERN[4]
            px[y + 1][x] = FERN[1]
            px[y + 2][x] = FERN[3]
    px[12][4] = SPORE


def i_reed(px, g):
    for y in range(3, 14):
        px[y][5] = GRASS[3]
        px[y][6] = GRASS[2]
        px[y][10] = GRASS[3] if y > 5 else CLEAR
    for y in range(4, 10):
        px[y][9], px[y][10], px[y][11] = CAT[2], CAT[1], CAT[0]
    for x in range(5, 11):
        px[13][x] = GRASS[1]
    px[4][9] = CAT[3]
    px[3][10] = GRASS[4]
    px[2][10] = GRASS[4]


def i_sun(px, g):
    blob(px, 8, 8, 4.2, 5.0, SUNP[1:])
    for y in range(4, 12):
        px[y][5:9] = [px[y][5], px[y][6], px[y][7], px[y][8]]
    for k in range(12):
        a = k / 12.0 * math.tau
        px[int(round(8 + math.sin(a) * 3.2))][int(round(8 + math.cos(a) * 3.2))] = DISC[1 + (k % 2)] if k % 3 else DISC[3]
    px[7][7] = SUNP[4]
    px[10][9] = SUNP[0]


def i_void(px, g):
    for y in range(2, 8):
        px[y][8] = VPET[2]
    for sgn, ln in ((-1, 6), (0, 8), (1, 6)):
        for k in range(ln):
            px[7 + k][8 + sgn * (1 + k // 3)] = VPET[3 - k // 3]
        px[6 + ln][8 + sgn * (1 + (ln - 1) // 3)] = VMAG
    px[7][8] = VMAG_L
    px[8][8] = VMAG


def i_tuber(px, g):
    blob(px, 8, 10, 5.0, 4.0, TUB)
    px[8][6] = TUB[4]
    for i, a in enumerate((-2.2, -1.57, -0.9)):
        for t in range(5):
            x, y = 8 + math.cos(a) * t * 1.1, 6 + math.sin(a) * t * 1.0
            px[int(round(y))][int(round(x))] = LEAFW[4 if t > 1 else 3]
    for x in range(4, 13):
        if px[13][x][3] == 0:
            px[13][x] = SOIL[2]


def i_carrot(px, g):
    for i in range(10):  # a carrot lying diagonally: the shoulder at the top left, the tip at the bottom right
        x, y = 4 + i, 4 + i
        w = 3 if i < 3 else (2 if i < 7 else 1)
        for k in range(w):
            px[y][x - k] = CARR[3 if k == 0 else (2 if k == 1 else 1)]
            if k == 0 and w > 1:
                px[y + 1][x - k] = CARR[1] if w == 3 else CARR[2]
        if i in (4, 6):
            px[y][x] = CARR[1]
    px[5][4], px[4][4] = CARR[4], CARR[4]
    for x, y, t in ((3, 3, 3), (2, 2, 4), (4, 2, 4), (3, 1, 5), (2, 3, 3), (5, 1, 3)):
        px[y][x] = CARG[t]


def i_lily(px, g):
    for y in range(8, 14):
        px[y][8] = GRASS[2]
    px[11][9], px[10][10], px[11][6], px[10][7] = GRASS[3], GRASS[3], GRASS[3], GRASS[3]
    for deg in (-150, -110, -70, -30, 160, 20, 90):
        a = math.radians(deg)
        for j in range(1, 5 if deg != 90 else 4):
            px[int(round(7 + math.sin(a) * j * 0.8))][int(round(8 + math.cos(a) * j))] = LILY[3 if j < 4 else 2] if j > 1 else LILY[2]
    px[7][8] = VPET[2]
    px[4][8], px[3][7], px[3][9] = STAMEN, STAMEN, STAMEN
    px[5][8] = LILY[4]


def i_poppy(px, g):
    for y in range(9, 14):
        px[y][8] = GRASS[2]
    px[12][9], px[11][10] = GRASS[3], GRASS[3]
    blob(px, 8, 6, 5.0, 4.2, POP)
    blob(px, 8, 6, 1.8, 1.4, DISC, dither=False)
    px[5][8] = POP_HOT
    px[4][5], px[3][6] = POP[4], POP[4]


def i_beet(px, g):
    blob(px, 8, 9, 5.0, 4.4, BEETR)
    for y in range(12, 15):
        px[y][8] = BEETR[1]
    px[13][9] = BEETR[0]
    px[7][6], px[8][5] = BEETR[4], BEETR[4]
    px[9][10] = SHEEN
    for y in range(3, 6):
        px[y][8] = BEET_ST[2]
    for dx, dy in ((-1, 2), (-2, 1), (1, 2), (2, 1), (0, 1)):
        px[3 + dy - 2][8 + dx] = BEETL[3 + (dx < 0)]
    px[2][8] = BEETL[5]


# ------------------------------------------------------------------ main
CUT = []


def fit(name, i, px):
    """No frame may touch the top row or the side columns: the sprite would be cut off there."""
    pts = [(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]]
    if pts and not (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2):
        CUT.append("%s frame %d: top %d, x %d..%d" % (name, i, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))



def main():
    props, items = ROOT / "props", ROOT / "items"

    def write(name, frames, cols, rows):
        write_png(props / (name + ".png"), FW * cols, FH * rows, sheet([f[0] for f in frames], cols, rows))
        write_png(props / (name + "_glow.png"), FW * cols, FH * rows, sheet([f[1] for f in frames], cols, rows))

    def write_plain(name, frames, cols):
        write_png(props / (name + ".png"), FW * cols, FH, sheet(frames, cols, 1))

    sheets = {}
    sheets["moonbell"] = [make_moonbell(s, 600 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(MOONBELLS)]
    sheets["wound_leaf"] = [make_wound(s, 700 + i * 13, picked=r) for r in (False, True) for i, s in enumerate(WOUNDS)]
    sheets["puffseed"] = [make_puff(s, 800 + i * 11, picked=r) for r in (False, True) for i, s in enumerate(PUFFS)]
    sheets["glowfern"] = [make_fern(s, 900 + i * 7, picked=r) for r in (False, True) for i, s in enumerate(FERNS)]
    sheets["cattail"] = [make_cattail(s, 1000 + i * 19) for i, s in enumerate(CATTAILS)]
    sheets["sunbloom"] = [make_sun(s, 1100 + i * 5, pose) for pose in range(5) for i, s in enumerate(SUNS)]
    sheets["voidbloom"] = [make_void(s, 1200 + i * 9, wilted=r) for r in (False, True) for i, s in enumerate(VOIDS)]
    sheets["earth_tuber"] = [make_tuber(s, 1300 + i * 23, dug=r) for r in (False, True) for i, s in enumerate(TUBERS)]
    sheets["ember_carrot"] = [make_carrot(s, 1400 + i * 29, pulled=r) for r in (False, True) for i, s in enumerate(CARROTS)]
    sheets["mist_lily"] = [make_lily(s, 1600 + i * 37 + r, r) for r in (0, 1, 2) for i, s in enumerate(LILIES)]
    sheets["spark_poppy"] = [make_poppy(s, 1700 + i * 41, picked=r) for r in (False, True) for i, s in enumerate(POPPIES)]
    sheets["night_beet"] = [make_beet(s, 1500 + i * 31, pulled=r) for r in (False, True) for i, s in enumerate(BEETS)]
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            fit(name, i, base)
            fit(name, i, glow)
        write(name, frames, 3, len(frames) // 3)
    write_plain("glowfern_stripped", [make_fern(s, 900 + i * 7, stripped=True)[0] for i, s in enumerate(FERNS)], 3)
    write_plain("cattail_stripped", [make_cattail(s, 1000 + i * 19, stripped=True)[0] for i, s in enumerate(CATTAILS)], 3)
    for name, draw in (("moonbell", i_moonbell), ("wound_leaf", i_wound), ("seed_fluff", i_fluff), ("fiddlehead", i_fiddle), ("fern_frond", i_frond),
                       ("reed", i_reed), ("sun_seed", i_sun), ("void_bloom", i_void), ("earth_tuber", i_tuber), ("ember_carrot", i_carrot), ("night_beet", i_beet), ("mist_lily", i_lily), ("spark_poppy", i_poppy)):
        write_png(items / (name + ".png"), 16, 16, icon(name, draw))
    assert not CUT, "cut off at the frame edge:\n" + "\n".join(CUT)
    print("flora written")
    if len(sys.argv) > 1:
        preview(pathlib.Path(sys.argv[1]), sheets)


def preview(path, sheets):
    """Every sheet 3x on a dark meadow green, rows under each other; icons at the bottom."""
    z = 3
    rows = sum(len(f) // 3 for f in sheets.values())
    w, h = FW * 3 * z, FH * rows * z
    out = [[(24, 40, 34, 255)] * w for _ in range(h)]
    r = 0
    for frames in sheets.values():
        for i, (base, glow) in enumerate(frames):
            ox, oy = (i % 3) * FW * z, (r + i // 3) * FH * z
            for y in range(FH):
                for x in range(FW):
                    for layer in (base, glow):
                        c = layer[y][x]
                        if c[3]:
                            a = c[3] / 255.0
                            for dy in range(z):
                                for dx in range(z):
                                    o = out[oy + y * z + dy][ox + x * z + dx]
                                    out[oy + y * z + dy][ox + x * z + dx] = tuple(int(o[k] * (1 - a) + c[k] * a) for k in range(3)) + (255,)
        r += len(frames) // 3
    write_png(path, w, h, out)


if __name__ == "__main__":
    main()
