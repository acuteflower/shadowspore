#!/usr/bin/env python3
"""Draws the twelve meadow/forest/marsh flora species and their items (stdlib only), frames 40x34 (feet at (20, 31)):
  assets/props/moonbell.png         Mondglöckchen: 5 stands of nodding bells x 2 rows (in bloom, picked)
  assets/props/wound_leaf.png       Wundblatt: 5 plantain rosettes x 2 rows (with violet spikes, trimmed)
  assets/props/puffseed.png         Wispersaat: 5 seed-head stands x 2 rows (fluffy globes, bare)
  assets/props/glowfern.png         Leuchtfern: 5 ferns x 2 rows (with glowing fiddleheads, without) + glowfern_stripped.png
  assets/props/cattail.png          Rohrkolben: 5 reed stands (+ cattail_stripped.png, the cut stubs)
  assets/props/sunbloom.png         Sonnenwende: 5 plants x 5 rows (turned east, up, west, closed for the night, picked)
  assets/props/voidbloom.png        Leerenblüte: 5 drooping blooms x 2 rows (open, wilted)
  assets/props/earth_tuber.png      Erdknolle: 5 leafy patches x 2 rows (tuber showing, dug up)
  assets/props/ember_carrot.png     Glutmöhre: 5 feathery patches x 2 rows (shoulder showing, pulled)
  assets/props/night_beet.png       Nachtrübe: 5 wine-leaved patches x 2 rows (shoulder showing, pulled)
  assets/props/mist_lily.png        Nebellilie: 5 star-lily stands x 3 rows (open night, closed day bud, picked)
  assets/props/spark_poppy.png      Funkenmohn: 5 silky poppy stands x 2 rows (in bloom, picked)
  every sheet has a `_glow` twin with only the emissive pixels (drawn unshaded, bright at night)
  assets/items/{moonbell,wound_leaf,seed_fluff,fiddlehead,fern_frond,reed,sun_seed,void_bloom,earth_tuber,ember_carrot,night_beet,mist_lily,spark_poppy}.png
Unified Shadowspore art style: top-left light, structured 4-6 tone cel + Bayer ramps, cool indigo-violet deep shadows,
blue-teal-meadow foliage, subtle cool teal right rim, adaptive material-tinted 1px outlines, grounded contact shadows.
`python3 tools/art_flora.py [preview.png]` writes the files, the optional argument also a 3x contact sheet."""
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


COLS = 5
BELL = ramp("24245e", "3e4e98", "72a4d4", "bce8ee", "f0fcfa")
TEAL_B = hexc("78f4e6")
LEAFW = ramp("12223a", "1b4648", "2b6c54", "449864", "6cc27c", "a0e69e")
SPIKE = ramp("3e245e", "74489e", "b07cc8", "e6bef0")
PUFF = ramp("46467a", "787aae", "b2b4de", "e8eaf8", "fbfaff")
FERN = ramp("10223a", "1a4848", "2a7054", "429e60", "6ec878", "aae89a")
FID = ramp("3c6c28", "84bc42", "daf488")
SPORE = hexc("66f0d8")
CAT = ramp("24162c", "46283c", "744650", "a47266", "cfa28e")
CAT_FLUFF = ramp("8a7c8c", "c4b8c4", "f0eaf0")
SUNP = ramp("6e2814", "b45416", "e49622", "f8ce58", "fff09e")
SUNP_WARM = ramp("642018", "a83e1c", "dc7822", "f6ba4c", "ffea96")
DISC = ramp("181024", "341c38", "563048", "7c4e58")
VPET = ramp("100826", "26104c", "48207a", "763ab2", "ac6ae2")
VLEAF = ramp("101c36", "1c324c", "2e4c66", "486e82")
VMAG, VMAG_L = hexc("ee48c8"), hexc("ffa4ec")
TUB = ramp("382450", "64487c", "9a7ca6", "d0bacb", "f0e4ea")
SOIL = ramp("18142a", "2e243a", "4a3a4c", "6c5868", "8c7684")
CARG = ramp("10263a", "1c4a50", "2c7662", "48a478", "76d296", "b2efc0")
CARR = ramp("461614", "902e1a", "d66a20", "f6a23c", "ffdc88")
EMBER_G, EMBER_GL = hexc("ffb25a"), hexc("fff0b0")
BEETR = ramp("120a24", "2c144a", "4e2478", "7c3ca2", "ac72d0")
BEETL = ramp("18102e", "321a4e", "522c72", "764c98", "9e72c0", "cca2e6")
BEET_ST = ramp("461038", "842060", "c24288")
SHEEN = hexc("4cc8c8")
LILY = ramp("28205c", "4e4294", "887cc8", "c6c0f0", "f4f2ff")
LILY_ROSE = ramp("321e58", "5e3e90", "9a78c4", "d6c2ee", "faf2ff")
LILY_GLOW = hexc("c8b8ff")
STAMEN = hexc("ffe28a")
POP = ramp("460c20", "94182a", "d43a26", "f4742e", "fcbd62")
POP_DEEP = ramp("3e0a24", "821432", "c02e32", "e86238", "f8ae5c")
POP_GLOW, POP_HOT = hexc("ff8a3a"), hexc("ffe8a0")
LIGHT = (-0.55, -0.8)


# ------------------------------------------------------------------ helpers
def blob(px, cx, cy, rx, ry, colors, dither=True):
    """A shaded ellipse (lit from the top left, ordered Bayer dither between bands)."""
    n = len(colors)
    if rx <= 0.1 or ry <= 0.1:
        return
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            d = dx * dx + dy * dy
            if d > 1.0:
                continue
            lit = 0.5 + 0.42 * (dx * LIGHT[0] + dy * LIGHT[1]) + 0.25 * (math.sqrt(1.0 - d) - 0.5)
            if dither:
                lit += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.20
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
    steps = max(1, int(length * 3))
    for i in range(steps + 1):
        t = i / steps
        dx, dy = math.cos(a), math.sin(a)
        w = wmax * math.sin(math.pi * min(1.0, t ** 0.72))
        nx, ny = dy, -dx
        sign = 1 if nx * LIGHT[0] + ny * LIGHT[1] > 0 else -1
        s = -w
        while s <= w + 0.01:
            side = s * sign
            idx = tone + (1 if side > w * 0.2 else 0) - (1 if side < -w * 0.45 else 0) - (1 if t < 0.16 else 0)
            if abs(s) < 0.4 and w > 1.25:
                idx += 1
            put(px, int(round(x + nx * s)), int(round(y + ny * s)), colors[int(clamp(idx, 0, len(colors) - 1))])
            s += 0.5
        x += dx / 3.0
        y += dy / 3.0
        a += curve / steps


def finish(px, spread, seed):
    for y in range(FH):  # cool teal rim light on the right edge of foliage
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and (c in GRASS[1:4] or c in LEAFW[1:4] or c in FERN[1:4] or c in CARG[1:4]) and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 102:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 155)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, min(16, spread + 3), 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base


def stalks_at(rng, n, spread):
    if n == 1:
        return [20 + rng.uniform(-1.0, 1.0)]
    return [20 + (i - (n - 1) / 2.0) * (2.0 * spread / max(n, 1)) + rng.uniform(-1.0, 1.0) for i in range(n)]


def basal_tussock(px, rng, spread, n_blades, seed, hi=6):
    blob(px, 20, GROUND - 1.0, min(spread * 0.65 + 1.5, 10.0), 2.0, [GRASS[0], GRASS[1], GRASS[2]])
    for _ in range(n_blades):
        blade(px, 20 + rng.uniform(-spread * 0.85, spread * 0.85), GROUND, rng.uniform(3, hi), rng.uniform(-0.65, 0.65), 0.45, rng.choice((1, 2, 3)), seed)


# ------------------------------------------------------------------ Mondglöckchen (5 variants)
MOONBELLS = [
    {"stalks": 1, "spread": 4, "lo": 15, "hi": 18, "leaves": 5, "bells": 3, "drift": 0.0},
    {"stalks": 2, "spread": 6, "lo": 14, "hi": 21, "leaves": 6, "bells": 3, "drift": 0.0},
    {"stalks": 3, "spread": 8, "lo": 13, "hi": 22, "leaves": 8, "bells": 3, "drift": 0.0},
    {"stalks": 4, "spread": 9, "lo": 12, "hi": 21, "leaves": 8, "bells": 2, "drift": 1.0},   # wind-swept right drift
    {"stalks": 5, "spread": 11, "lo": 11, "hi": 23, "leaves": 10, "bells": 2, "drift": 0.0},
]


def bell(px, glow, x, y, big):
    # Sculpted flared bell corolla with scalloped 3-lobe mouth & top-left porcelain highlight
    widths = [2, 4, 5, 6, 7] if big else [2, 3, 4, 5]
    put(px, x, y - 1, LEAFW[2])  # green calyx cap
    put(px, x - 1, y, LEAFW[3])
    for r, w in enumerate(widths):
        for c in range(w):
            xx = x - w // 2 + c
            if r == len(widths) - 1:
                # Ruffled mouth lobes: alternate tips slightly brighter, interior dark
                lobe = (c in (0, w // 2, w - 1))
                idx = 2 if lobe else 0
                if c == 0:
                    idx = 3
                put(px, xx, y + r, BELL[idx])
            else:
                frac = c / max(w - 1, 1)
                idx = 3 if frac < 0.4 else (2 if frac < 0.72 else 1)
                if r == 0:
                    idx = max(1, idx - 1)
                put(px, xx, y + r, BELL[idx])
    put(px, x - widths[1] // 2, y + 1, BELL[4])
    if big:
        put(px, x - widths[2] // 2, y + 2, BELL[4])
    ly = y + len(widths) - 1
    glow.emit(px, x, ly, BELL[2], TEAL_B, 1)
    if big:
        glow.emit(px, x + 1, ly, None, TEAL_B, 0)


def make_moonbell(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for i in range(spec["leaves"]):
        a = -math.pi / 2 + (i / max(spec["leaves"] - 1, 1) - 0.5) * 1.9 + rng.uniform(-0.15, 0.15)
        leaf(px, 20 + math.cos(a) * 2.0, GROUND - 1, a, rng.uniform(6, 11) * (0.65 if picked else 1.0), 1.5, LEAFW, curve=(a + math.pi / 2) * 0.45, tone=2)
    xs = stalks_at(rng, spec["stalks"], spec["spread"] * 0.75)
    for i, x0 in enumerate(xs):
        side = 1 if spec["drift"] > 0 else ((1 if x0 >= 20 else -1) if spec["stalks"] > 1 else 1)
        h = rng.uniform(3.5, 5.5) if picked else rng.uniform(spec["lo"], spec["hi"])
        reach = rng.uniform(3.2, 5.4) if not picked else 1.0
        end = (clamp(x0 + side * reach, 6, FW - 7), GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 1.2, GROUND - h * 0.75), (x0 + side * 1.5, GROUND - h * 1.12), end, n=30)
        stem(px, pts, 2, thick=(i == 0 and spec["stalks"] <= 3 and not picked))
        if picked:
            continue
        nb = spec["bells"] + (1 if i == len(xs) // 2 and spec["stalks"] >= 4 else 0)
        for j in range(nb):
            t_pos = 0.54 + 0.42 * j / max(nb - 1, 1) if nb > 1 else 0.92
            p = pts[int(len(pts) * t_pos)]
            bx = int(clamp(round(p[0]) + side * 2, 5, FW - 6))
            by = int(clamp(round(p[1]) + 2, 4, GROUND - 6))
            put(px, int(round(p[0])) + side, int(round(p[1])) + 1, GRASS[2])
            bell(px, glow, bx, by, big=(j == 0 and spec["stalks"] <= 3))
        glow.emit(px, int(round(end[0])), max(2, int(round(end[1])) - 1), None, TEAL_B, 0)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Wundblatt (5 variants)
WOUNDS = [
    {"leaves": 6, "len": (8, 11), "spikes": 0, "spread": 7, "w": 2.4},
    {"leaves": 8, "len": (9, 13), "spikes": 1, "spread": 9, "w": 2.6},
    {"leaves": 9, "len": (9, 14), "spikes": 2, "spread": 10, "w": 2.6},
    {"leaves": 10, "len": (8, 14), "spikes": 3, "spread": 11, "w": 2.5},
    {"leaves": 12, "len": (9, 15), "spikes": 4, "spread": 13, "w": 2.7},
]


def make_wound(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["leaves"]
    angles = sorted(-math.pi / 2 + (i / max(n - 1, 1) - 0.5) * 2.45 + rng.uniform(-0.10, 0.10) for i in range(n))
    for a in sorted(angles, key=lambda v: -abs(v + math.pi / 2)):
        length = rng.uniform(*spec["len"]) * (0.45 if picked else 1.0)
        x0 = 20 + math.cos(a) * 1.8
        leaf(px, x0, GROUND - 1, a, length, spec["w"] if not picked else 1.4, LEAFW, curve=-(a + math.pi / 2) * 0.50, tone=3)
        if not picked and rng.random() < 0.28:
            ex = clamp(x0 + math.cos(a) * length * 0.78, 3, FW - 4)
            ey = clamp(GROUND - 1 + math.sin(a) * length * 0.78, 3, GROUND - 2)
            glow.emit(px, int(round(ex)), int(round(ey)) - 1, None, hexc("c8fff0"), 0)
    if not picked and spec["spikes"] > 0:
        for i in range(spec["spikes"]):
            x0 = 20 + (i - (spec["spikes"] - 1) / 2.0) * 4.4 + rng.uniform(-0.8, 0.8)
            h = rng.uniform(14, 19) - abs(x0 - 20) * 0.25
            lean = (x0 - 20) / 28.0
            pts = bezier((x0, GROUND - 1), (x0 + lean * 3.5, GROUND - h * 0.6), (x0 + lean * 9.0, GROUND - h), n=24)
            stem(px, pts, 2)
            tx, ty = int(clamp(round(pts[-1][0]), 4, FW - 5)), int(clamp(round(pts[-1][1]), 5, GROUND - 8))
            spk_h = 6 + (i % 2)
            for k in range(spk_h):
                w_row = (-1, 0, 1) if 0 < k < spk_h - 1 else (0,)
                for dx in w_row:
                    tone = 2 if dx < 0 else (3 if dx == 0 and k % 2 == 0 else (1 if dx == 0 else 0))
                    put(px, tx + dx, ty + k - spk_h // 2, SPIKE[tone])
                if k == spk_h // 2:
                    put(px, tx - 1, ty + k - spk_h // 2, STAMEN)  # tiny anther ring on plantain spike
            glow.emit(px, tx, ty - spk_h // 2, SPIKE[3], hexc("f0b8ff"), 1)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Wispersaat (5 variants)
PUFFS = [
    {"stalks": 1, "spread": 4, "lo": 15, "hi": 17, "leaves": 6, "r": 5.2, "shed": False},
    {"stalks": 2, "spread": 6, "lo": 12, "hi": 19, "leaves": 7, "r": 4.6, "shed": False},
    {"stalks": 3, "spread": 8, "lo": 11, "hi": 20, "leaves": 8, "r": 4.3, "shed": False},
    {"stalks": 3, "spread": 9, "lo": 12, "hi": 20, "leaves": 9, "r": 4.2, "shed": True},   # windswept with drifting pappus
    {"stalks": 5, "spread": 11, "lo": 10, "hi": 21, "leaves": 11, "r": 3.9, "shed": False},
]


def puff_head(px, glow, cx, cy, r, rng, half_shed=False):
    # Volumetric shaded pearlescent dandelion globe (instead of bare 1px spokes!)
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            dx, dy = (x + 0.5 - cx) / r, (y + 0.5 - cy) / r
            d = dx * dx + dy * dy
            if d > 1.05:
                continue
            if half_shed and dx > 0.25 and dy < 0.15:
                continue
            # Fluffy scalloped silhouette edge
            ang = math.atan2(dy, dx)
            scallop = 0.88 + 0.14 * math.cos(ang * 10.0)
            if d > scallop:
                continue
            if d > 0.62 and (BAYER[y % 4][x % 4] > 12) and d > 0.78:
                continue
            lit = 0.55 + 0.38 * (dx * LIGHT[0] + dy * LIGHT[1]) + 0.18 * math.sqrt(max(0.0, 1.0 - d))
            lit += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.22
            put(px, x, y, PUFF[int(clamp(lit * len(PUFF), 0, len(PUFF) - 1))])
    # Subtle dark seed receptacle heart peeking from center-bottom
    put(px, int(round(cx)), int(round(cy + 1)), DISC[2])
    put(px, int(round(cx)), int(round(cy)), PUFF[1])
    put(px, int(round(cx - r * 0.42)), int(round(cy - r * 0.42)), PUFF[4])
    glow.emit(px, int(round(cx - r * 0.35)), int(round(cy - r * 0.45)), PUFF[4], hexc("e6f6ff"), 1)
    if half_shed:
        # Floating parachute seed drifting right
        fx, fy = min(FW - 4, int(round(cx + r + 3))), max(3, int(round(cy - 2)))
        put(px, fx, fy, PUFF[3])
        put(px, fx - 1, fy + 1, PUFF[2])
        glow.emit(px, fx, fy, PUFF[4], hexc("e6f6ff"), 1)


def make_puff(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for i in range(spec["leaves"]):
        a = -math.pi / 2 + (i / max(spec["leaves"] - 1, 1) - 0.5) * 2.5 + rng.uniform(-0.15, 0.15)
        leaf(px, 20 + math.cos(a) * 2.0, GROUND - 1, a, rng.uniform(6, 10), 1.6, LEAFW, curve=-(a + math.pi / 2) * 0.45, tone=3)
    xs = stalks_at(rng, spec["stalks"], spec["spread"] * 0.8)
    for idx, x0 in enumerate(xs):
        h = rng.uniform(4, 7) if picked else rng.uniform(spec["lo"], spec["hi"])
        lean = (x0 - 20) / 36.0 + (0.08 if spec["shed"] else rng.uniform(-0.04, 0.04))
        pts = bezier((x0, GROUND + 0.5), (x0 + lean * h * 0.35, GROUND - h * 0.6), (x0 + lean * h * 1.1, GROUND - h), n=26)
        stem(px, pts, 2)
        tx, ty = pts[-1]
        tx = clamp(tx, 6, FW - 7)
        ty = clamp(ty, 7, GROUND - 4)
        if picked:
            blob(px, tx, ty, 1.8, 1.3, DISC[1:4], dither=False)
            put(px, int(round(tx)), int(round(ty)) - 1, PUFF[2])
        else:
            puff_head(px, glow, tx, ty - spec["r"] * 0.55, spec["r"], rng, half_shed=(spec["shed"] and idx == len(xs) - 1))
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Leuchtfern (3 legacy FERNS for hexenwald + 5 GLOWFERNS)
FERNS = [
    {"fronds": 5, "len": 11, "spread": 8, "fiddles": 1},
    {"fronds": 7, "len": 13, "spread": 12, "fiddles": 2},
    {"fronds": 9, "len": 15, "spread": 14, "fiddles": 3},
]
GLOWFERNS = [
    {"fronds": 6, "len": 11, "spread": 8, "fiddles": 1, "lean": 0.0},
    {"fronds": 7, "len": 12.5, "spread": 10, "fiddles": 2, "lean": 0.0},
    {"fronds": 9, "len": 14, "spread": 12, "fiddles": 3, "lean": 0.0},
    {"fronds": 8, "len": 13.5, "spread": 11, "fiddles": 2, "lean": 1.8},
    {"fronds": 11, "len": 15, "spread": 14, "fiddles": 4, "lean": -0.8},
]


def frond(px, glow, x0, side, length, rise, rng, seed):
    p0 = (x0, GROUND - 1)
    end_x = clamp(x0 + side * length, 3, FW - 4)
    end_y = clamp(GROUND - rise * 0.35, 4, GROUND - 1)
    pts = bezier(p0, (x0 + side * length * 0.22, GROUND - rise), (x0 + side * length * 0.78, GROUND - rise * 1.15), (end_x, end_y), n=42)
    for i in range(0, len(pts) - 2, 2):
        x, y = pts[i]
        nx, ny = pts[i + 1][0] - x, pts[i + 1][1] - y
        ln = math.hypot(nx, ny) or 1.0
        t = i / len(pts)
        pl = max(1.2, (1.0 - t) ** 0.75 * (length * 0.22 + 1.3))
        for sgn in (-1, 1):
            ox, oy = (-ny / ln) * sgn, (nx / ln) * sgn
            for k in range(1, int(pl) + 2):
                if k > pl + 0.2:
                    continue
                tone = 3 + (1 if (oy * sgn > 0 or ox < 0) and k < pl else 0) - (1 if k >= int(pl) and sgn > 0 else 0)
                px_x = int(round(x + ox * k + nx / ln * k * 0.5))
                px_y = int(round(y + oy * k * 0.85 + ny / ln * k * 0.5 + 0.35 * k))
                put(px, px_x, px_y, FERN[int(clamp(tone, 1, 5))])
                if k < pl - 0.4:
                    put(px, px_x, min(GROUND - 1, px_y + 1), FERN[int(clamp(tone - 1, 0, 4))])
        put(px, int(round(x)), int(round(y)), FERN[2])
        if i % 8 == 4 and rng.random() < 0.65:
            glow.emit(px, int(round(x)), int(round(y)) + 1, None, SPORE, 1)


def fiddlehead(px, glow, x, y, size):
    top = y - (6 + size)
    for k in range(6 + size):
        put(px, int(round(x)), y - k, FID[0])
        if k < 4:
            put(px, int(round(x)) + 1, y - k, FERN[1])
    pts = []
    for i in range(30):
        t = i / 29.0
        ang = math.pi / 2 + t * 4.6
        rr = (size + 0.9) * (1.0 - t * 0.78)
        pts.append((x + math.cos(ang) * rr, top - size * 0.7 + math.sin(ang) * rr))
    for i, (cx, cy) in enumerate(pts):
        put(px, int(clamp(round(cx), 2, FW - 3)), int(clamp(round(cy), 2, GROUND - 2)), FID[1 if i > 11 else 0])
    gx, gy = int(clamp(round(pts[-1][0]), 3, FW - 4)), int(clamp(round(pts[-1][1]), 3, GROUND - 3))
    glow.emit(px, gx, gy, FID[2], hexc("d8ff80"), 2)


def make_fern(spec, seed, picked=False, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    lean = spec.get("lean", 0.0)
    # Dense shaded interior fern cushion so the rosette looks lush & supports LeafCritter 9x5 habitat patches
    if not stripped:
        blob(px, 20 + lean * 0.5, GROUND - 7.5, max(5.6, spec["spread"] * 0.58), 5.6, [FERN[0], FERN[1], FERN[2], FERN[3]])
        blob(px, 20 + lean * 0.3, GROUND - 10.5, max(5.0, spec["spread"] * 0.48), 4.2, [FERN[1], FERN[2], FERN[3], FERN[4]])
    else:
        blob(px, 20, GROUND - 2.5, max(4.0, spec["spread"] * 0.4), 2.4, [FERN[0], FERN[1], FERN[2]])
    n = spec["fronds"]
    order = sorted(range(n), key=lambda i: -abs(i - (n - 1) / 2.0))
    for i in order:
        side = -1 if i % 2 == 0 else 1
        frac = abs(i - (n - 1) / 2.0) / max((n - 1) / 2.0, 1)
        length = spec["len"] * (0.68 + 0.32 * rng.random()) * (0.42 if stripped else 1.0)
        rise = (7 + length * 0.58) * (1.0 - 0.22 * frac) * (0.38 if stripped else 1.0)
        frond(px, glow, 20 + lean * 0.4 + side * rng.uniform(0.4, 2.2), side, length + (lean * side * 0.6), rise, rng, seed + i)
    if not picked and not stripped:
        nf = spec["fiddles"]
        for i in range(nf):
            fx = 20 + lean * 0.5 + (i - (nf - 1) / 2.0) * 4.2 + rng.uniform(-0.7, 0.7)
            fiddlehead(px, glow, clamp(fx, 7, FW - 8), GROUND - 2, 2 + (i % 2))
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Rohrkolben (5 variants)
CATTAILS = [
    {"stems": 2, "spread": 5, "lo": 15, "hi": 18, "fluff": False, "lean": 0.0},
    {"stems": 3, "spread": 7, "lo": 14, "hi": 19, "fluff": False, "lean": 0.0},
    {"stems": 4, "spread": 8.5, "lo": 13, "hi": 19, "fluff": True, "lean": 0.0},
    {"stems": 4, "spread": 8.5, "lo": 13, "hi": 18, "fluff": True, "lean": 0.07},
    {"stems": 6, "spread": 10.5, "lo": 12, "hi": 19, "fluff": True, "lean": -0.03},
]


def make_cattail(spec, seed, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    # Dense reed base cushion (also ensures solid habitat & grounded wetland silhouette)
    if not stripped:
        blob(px, 20, GROUND - 5.5, max(4.8, spec["spread"] * 0.55), 5.0, [LEAFW[0], LEAFW[1], LEAFW[2], LEAFW[3]])
    for i in range(spec["stems"] * 2 + 4):
        u = (i / max(spec["stems"] * 2 + 3, 1) - 0.5) * 2.0
        a = -math.pi / 2 + u * 0.62 + spec["lean"] + rng.uniform(-0.10, 0.10)
        ln = rng.uniform(9, 15) * (1.0 - 0.25 * abs(u)) * (0.32 if stripped else 1.0)
        leaf(px, 20 + u * spec["spread"] * 0.60, GROUND, a, ln, 1.25, LEAFW, curve=u * 0.40 + spec["lean"] * 1.4, tone=3)
    xs = stalks_at(rng, spec["stems"], spec["spread"] * 0.75)
    for idx, x0 in enumerate(xs):
        h = rng.uniform(2.5, 4.5) if stripped else rng.uniform(spec["lo"], spec["hi"])
        lean = (x0 - 20) / 38.0 + spec["lean"] + rng.uniform(-0.04, 0.04)
        pts = bezier((x0, GROUND + 0.5), (x0 + lean * h * 0.35, GROUND - h * 0.6), (x0 + lean * h * 0.95, GROUND - h), n=26)
        stem(px, pts, 2)
        if stripped:
            continue
        tx, ty = int(clamp(round(pts[-1][0]), 5, FW - 6)), int(clamp(round(pts[-1][1]), 9, GROUND - 8))
        club_h = 7 if h > 16.5 else 6
        # Cylindrical 3D-shaded velvety umber-plum cattail club with rounded caps
        for k in range(club_h):
            t_end = k in (0, club_h - 1)
            for dx in ((-1, 0, 1) if not t_end else (0,)):
                tone = 3 if (dx < 0 and 1 <= k <= club_h - 2) else (2 if dx <= 0 else (1 if k < club_h - 2 else 0))
                put(px, tx + dx, ty + k - club_h + 1, CAT[tone])
        put(px, tx - 1, ty - club_h + 3, CAT[4])  # warm velvety highlight
        # Slender golden-olive staminate spike above club
        put(px, tx, ty - club_h, GRASS[3])
        put(px, tx, max(3, ty - club_h - 1), SEED[1])
        # Creamy bursting seed-down fluff wisp on mature club
        if spec["fluff"] and idx == len(xs) // 2:
            put(px, tx + 1, ty - club_h + 2, CAT_FLUFF[2])
            put(px, tx + 2, ty - club_h + 1, CAT_FLUFF[1])
            glow.emit(px, tx + 2, ty - club_h + 1, CAT_FLUFF[2], TEAL_B, 0)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Sonnenwende (5 variants x 5 rows)
SUNS = [
    {"stalks": [(20, 15, 4.4, False)], "spread": 6},
    {"stalks": [(20, 18, 5.2, True)], "spread": 7},
    {"stalks": [(15, 17, 4.8, False), (26, 13, 4.0, True)], "spread": 9},
    {"stalks": [(18, 18, 5.0, False), (27, 11, 3.2, False)], "spread": 9, "bud": True},
    {"stalks": [(13, 14, 4.2, True), (20, 19, 5.2, False), (28, 13, 4.0, False)], "spread": 11},
]


def sun_crown(px, glow, cx, cy, rx, ry, pal, pose):
    """Lush two-ring overlapping cupped golden ray petals around a textured dark seed disc."""
    n_petals = 12 if max(rx, ry) >= 4.6 else 10
    # Outer/back ring first, then sunlit front ring
    for ring, (ang_off, len_mul, tone_boost) in enumerate(((math.pi / n_petals, 1.05, -1), (0.0, 0.95, 0))):
        for k in range(n_petals):
            a = k / n_petals * math.tau + ang_off
            ca, sa = math.cos(a), math.sin(a)
            # Perspective foreshortening for East (pose 0) and West (pose 2)
            px_len = math.hypot(ca * rx, sa * ry) * len_mul
            bx = cx + ca * rx * 0.35
            by = cy + sa * ry * 0.35
            lit_tone = 2 + tone_boost + (1 if (ca * LIGHT[0] + sa * LIGHT[1]) > 0.05 else 0)
            leaf(px, bx, by, a, max(2.2, px_len * 0.78), 1.35 if pose == 1 else 1.15, pal, curve=0.12 * (-1 if ca < 0 else 1), tone=int(clamp(lit_tone, 1, 3)))
            if ring == 1 and k % 3 == 0:
                tx = int(clamp(round(cx + ca * rx * 1.05), 3, FW - 4))
                ty = int(clamp(round(cy + sa * ry * 1.05), 3, GROUND - 4))
                glow.emit(px, tx, ty, None, pal[3], 0)
    # Rich dark plum-bronze seed disc with golden pollen rim
    drx, dry = max(1.6, rx * 0.48), max(1.6, ry * 0.48)
    blob(px, cx, cy, drx + 0.5, dry + 0.5, [pal[1], pal[2], pal[3]], dither=False)
    blob(px, cx, cy, drx, dry, DISC)
    put(px, int(round(cx - drx * 0.35)), int(round(cy - dry * 0.35)), pal[3])
    glow.emit(px, int(round(cx)), int(round(cy)), DISC[3], hexc("ffcf70"), 1)


def make_sun(spec, seed, pose):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    basal_tussock(px, rng, spec["spread"] * 0.65, 4, seed, hi=5)
    for idx, (x0, h, r, warm) in enumerate(spec["stalks"]):
        pal = SUNP_WARM if warm else SUNP
        is_side_bud = spec.get("bud") and idx == 1
        h_eff = h * (0.34 if pose == 4 else 1.0)
        side = {0: 1, 1: 0, 2: -1, 3: 1, 4: 1}[pose]
        droop = pose in (3, 4)
        end_x = clamp(x0 + (side * 2.0 if pose < 3 else 3.2), 7, FW - 8)
        end_y = clamp(GROUND - h_eff + (2.5 if droop else 0), 6, GROUND - 4)
        pts = (bezier((x0, GROUND + 0.5), (x0 - 1.2, GROUND - h_eff * 0.58), (end_x, end_y), n=28)
               if not droop else
               bezier((x0, GROUND + 0.5), (x0, GROUND - h_eff), (x0 + 3.8, GROUND - h_eff * 0.78), (end_x, end_y), n=28))
        stem(px, pts, 2, thick=(r >= 4.5))
        if pose != 4:
            for li, t in enumerate((0.28, 0.54)):
                p = pts[int(len(pts) * t)]
                for sgn in (-1, 1):
                    if (li + (sgn > 0)) % 2 == 0 or r >= 5.0:
                        leaf(px, p[0], p[1], -math.pi / 2 + sgn * 1.05, 5.5 - li * 0.8, 2.0, LEAFW, curve=sgn * 0.48, tone=3)
        cx, cy = end_x, end_y
        if pose == 4:
            blob(px, cx, cy + 0.5, 2.3, 1.8, [LEAFW[1], LEAFW[2], DISC[1], DISC[2]], dither=False)
            continue
        if pose == 3 or is_side_bud:
            # Closed leafy sepal lantern hugging warm glowing amber tips
            blob(px, cx + 0.8, cy + 2.2, r * 0.42 + 1.2, r * 0.55 + 1.8, LEAFW[1:5])
            blob(px, cx + 0.8, cy + r * 0.5 + 3.4, 1.6, 1.7, pal[1:4], dither=False)
            glow.emit(px, int(round(cx + 0.8)), min(GROUND - 3, int(round(cy + r * 0.5 + 4.0))), pal[3], pal[4], 1)
            continue
        rx, ry = {0: (r * 0.62, r * 0.96), 1: (r, r * 0.94), 2: (r * 0.62, r * 0.96)}[pose]
        shift = {0: 1.2, 1: 0.0, 2: -1.2}[pose]
        sun_crown(px, glow, clamp(cx + shift, 7, FW - 8), max(6.5, cy - r * 0.35), rx, ry, pal, pose)
    return finish(px, spec["spread"], seed + pose), glow.done()


# ------------------------------------------------------------------ Leerenblüte (5 variants)
VOIDS = [
    {"stalks": 1, "spread": 5, "h": (16, 18), "tendrils": 4},
    {"stalks": 2, "spread": 7, "h": (14, 20), "tendrils": 5},
    {"stalks": 3, "spread": 9, "h": (13, 21), "tendrils": 6},
    {"stalks": 2, "spread": 9, "h": (16, 22), "tendrils": 6, "arch": True},
    {"stalks": 4, "spread": 12, "h": (12, 22), "tendrils": 8},
]


def void_flower(px, glow, x, y, side, big):
    """Sculpted drooping twilight-velvet orchid: hooded upper sepal + 3 curling magenta-veined petals."""
    blob(px, x, y, 2.2 if big else 1.8, 1.8, VPET[1:5], dither=False)
    specs = ((-1, 6 if big else 5), (0, 8 if big else 6), (1, 6 if big else 5))
    for sgn, ln in specs:
        pts = bezier((x + sgn * 0.8, y + 1), (x + sgn * 2.2, y + ln * 0.55), (x + sgn * (2.6 + (0.6 if big else 0)), y + ln), n=14)
        for k, (px_x, px_y) in enumerate(pts):
            t = k / max(len(pts) - 1, 1)
            ix, iy = int(clamp(round(px_x), 3, FW - 4)), int(clamp(round(px_y), 3, GROUND - 3))
            tone = int(clamp(3 - t * 2.2 + (1 if sgn <= 0 else 0), 0, 4))
            put(px, ix, iy, VPET[tone])
            if t < 0.65:
                put(px, ix + (1 if sgn <= 0 else -1), iy, VPET[max(0, tone - 1)])
        tx, ty = int(clamp(round(pts[-1][0]), 3, FW - 4)), int(clamp(round(pts[-1][1]), 3, GROUND - 3))
        glow.emit(px, tx, ty, VPET[4], VMAG, 1)
    put(px, x, y + 2, VMAG)
    glow.emit(px, x, y + 1, VMAG_L, VMAG_L, 2 if big else 1)


def make_void(spec, seed, wilted=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    # Cool blue-slate-violet ribbon foliage so Leerenblüte harmonizes with the meadow's cool shadow world
    for i in range(spec["tendrils"]):
        a = -math.pi / 2 + (i / max(spec["tendrils"] - 1, 1) - 0.5) * 2.3 + rng.uniform(-0.15, 0.15)
        leaf(px, 20 + math.cos(a) * 2.0, GROUND - 1, a, rng.uniform(6, 11) * (0.52 if wilted else 1.0), 1.35, VLEAF, curve=rng.uniform(-0.8, 0.8), tone=2)
    xs = stalks_at(rng, spec["stalks"], spec["spread"] * 0.72)
    for idx, x0 in enumerate(xs):
        h = rng.uniform(*spec["h"]) * (0.45 if wilted else 1.0)
        side = 1 if spec.get("arch") else (1 if x0 >= 20 else -1)
        end = (clamp(x0 + side * (4.0 if spec.get("arch") else 2.8), 6, FW - 7), clamp(GROUND - h, 5, GROUND - 4))
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 1.8, GROUND - h * 0.88), end, n=26)
        for x, y in pts:
            put(px, int(round(x)), int(round(y)), VLEAF[2])
            if not wilted and h > 16:
                put(px, int(round(x)) + 1, int(round(y)), VPET[1])
        ex, ey = int(round(end[0])), int(round(end[1]))
        if wilted:
            put(px, ex, ey + 1, VPET[2])
            put(px, ex, ey + 2, VPET[1])
        else:
            void_flower(px, glow, ex, ey, side, big=(idx == 0 and spec["stalks"] <= 2))
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Erdknolle, Glutmöhre, Nachtrübe (5 variants each)
TUBERS = [
    {"tubers": [(20, 27, 3.6)], "leaves": 5, "spread": 7},
    {"tubers": [(20, 27, 4.3)], "leaves": 7, "spread": 9},
    {"tubers": [(15, 27, 3.8), (25, 28, 3.2)], "leaves": 8, "spread": 11},
    {"tubers": [(16, 28, 3.3), (24, 27, 4.1)], "leaves": 9, "spread": 11},
    {"tubers": [(13, 28, 3.2), (20, 27, 4.2), (28, 28, 3.0)], "leaves": 11, "spread": 13},
]
CARROTS = [
    {"crowns": [(20, 2.8)], "stalks": 5, "len": (8, 12), "spread": 7},
    {"crowns": [(20, 3.6)], "stalks": 8, "len": (10, 15), "spread": 9},
    {"crowns": [(15, 3.2), (25, 2.8)], "stalks": 9, "len": (8, 13), "spread": 11},
    {"crowns": [(17, 3.7), (26, 2.4)], "stalks": 10, "len": (9, 14), "spread": 11},
    {"crowns": [(13, 2.8), (20, 3.6), (27, 2.7)], "stalks": 12, "len": (8, 14), "spread": 13},
]
BEETS = [
    {"crowns": [(20, 4.2)], "leaves": 4, "len": (7, 10), "spread": 8},
    {"crowns": [(20, 5.4)], "leaves": 6, "len": (9, 12), "spread": 10},
    {"crowns": [(15, 4.6), (25, 3.8)], "leaves": 7, "len": (8, 11), "spread": 11},
    {"crowns": [(16, 3.6), (24, 5.0)], "leaves": 8, "len": (8, 12), "spread": 12},
    {"crowns": [(13, 3.8), (20, 5.0), (28, 3.6)], "leaves": 9, "len": (8, 12), "spread": 13},
]


def soil_mound(px, cx, cy, rx, ry):
    blob(px, cx, cy, rx, ry, SOIL[:4])
    put(px, int(round(cx - rx * 0.45)), int(round(cy - ry * 0.35)), SOIL[4])
    put(px, int(round(cx + rx * 0.5)), int(round(cy + 0.5)), LEAFW[1])  # tiny moss fleck


def crater(px, rng, crowns, big):
    """Pulled-root crater: shadowed hollow, crumbly twilight soil clods, torn rootlets & short grass."""
    for cx, r in crowns:
        soil_mound(px, cx, GROUND - 0.5, r + 3.2, 2.8)
        blob(px, cx, GROUND - 0.2, r * 0.72 + 1.0, 1.6, [SOIL[0], SOIL[0], SOIL[1]], dither=False)
        for _ in range(4 + int(r)):
            a = rng.uniform(0, math.tau)
            x = cx + math.cos(a) * (r + 3.0) * rng.uniform(0.7, 1.2)
            y = GROUND - 0.5 + math.sin(a) * 2.6 * rng.uniform(0.6, 1.1)
            blob(px, clamp(x, 4, FW - 5), clamp(y - 0.4, GROUND - 4, GROUND), 1.2, 0.9, SOIL[1:4], dither=False)
        for k in (-1, 1):
            put(px, int(clamp(cx + k * 1.5, 3, FW - 4)), GROUND - 1, TUB[3])
            put(px, int(clamp(cx + k * 2.4, 3, FW - 4)), GROUND - 2, TUB[2])
    for _ in range(3):
        blade(px, 20 + rng.uniform(-big * 0.8, big * 0.8), GROUND, rng.uniform(1.5, 3.5), rng.uniform(-0.5, 0.5), 0.3, rng.choice((1, 2)), 5)


def make_tuber(spec, seed, dug=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if dug:
        crater(px, rng, [(tx, r * 0.85) for tx, _ty, r in spec["tubers"]], spec["spread"])
        for tx, ty, _r in spec["tubers"][:2]:
            leaf(px, tx, ty - 1, -math.pi / 2 + rng.uniform(-0.9, 0.9), 4.5, 1.4, LEAFW, curve=0.3, tone=2)
        return finish(px, spec["spread"], seed), glow.done()
    for tx, ty, r in spec["tubers"]:
        soil_mound(px, tx, ty + 1.2, r + 2.2, 2.6)
    n = spec["leaves"]
    for i in range(n):
        tx, ty, r = spec["tubers"][i % len(spec["tubers"])]
        a = -math.pi / 2 + (i / max(n - 1, 1) - 0.5) * 2.1 + rng.uniform(-0.18, 0.18)
        leaf(px, tx, ty - 2, a, rng.uniform(7, 12), 2.3, LEAFW, curve=-(a + math.pi / 2) * 0.45, tone=3)
    for idx, (tx, ty, r) in enumerate(spec["tubers"]):
        blob(px, tx, ty - 0.6, r, r * 0.78, TUB)
        put(px, int(tx - r * 0.35), int(ty - r * 0.45), TUB[4])
        put(px, int(tx + r * 0.3), int(ty), TUB[1])  # growth dimple
        if idx == 0:
            glow.emit(px, int(tx + 1), int(ty - 2), TUB[3], hexc("e8d8ff"), 1)
    return finish(px, spec["spread"], seed), glow.done()


def carrot_leaf(px, glow, x0, y0, length, side, rng):
    end = (clamp(x0 + side * length * 0.65, 4, FW - 5), max(4, y0 - length))
    pts = bezier((x0, y0), (x0 + side * 1.0, y0 - length * 0.7), (x0 + side * length * 0.25, y0 - length * 1.05), end, n=28)
    stem(px, pts, 2)
    for i in range(5, len(pts), 3):
        x, y = pts[i]
        t = i / len(pts)
        ln = 2.4 - 1.1 * abs(t - 0.58)
        for sgn in (-1, 1):
            for k in range(1, int(ln + 1)):
                px_x = int(clamp(round(x + sgn * k), 2, FW - 3))
                px_y = int(clamp(round(y - k * 0.45 + 0.06 * k * k), 2, GROUND - 2))
                put(px, px_x, px_y, CARG[int(clamp(3 + (1 if sgn < 0 else 0) + (1 if k == int(ln) else 0), 1, 5))])
    put(px, int(round(end[0])), max(2, int(round(end[1])) - 1), CARG[5])
    if rng.random() < 0.32:
        glow.emit(px, int(round(end[0])), max(2, int(round(end[1])) - 2), None, EMBER_G, 0)


def make_carrot(spec, seed, pulled=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        crater(px, rng, spec["crowns"], spec["spread"])
        return finish(px, spec["spread"], seed), glow.done()
    for cx, r in spec["crowns"]:
        soil_mound(px, cx, GROUND - 0.5, r + 2.8, 2.6)
    for i in range(spec["stalks"]):
        cx, r = spec["crowns"][i % len(spec["crowns"])]
        side = -1 if i % 2 == 0 else 1
        carrot_leaf(px, glow, cx + side * rng.uniform(0, 1.6), GROUND - 2, rng.uniform(*spec["len"]), side, rng)
    for cx, r in spec["crowns"]:
        blob(px, cx, GROUND - 1.6, r, 2.5, CARR)
        for k in (-1, 1):
            put(px, int(cx + k * max(1, r - 1.2)), GROUND - 1, CARR[1])
        put(px, int(cx) - 1, GROUND - 3, CARR[4])
        glow.emit(px, int(cx), GROUND - 2, CARR[3], EMBER_GL, 2)
    for _ in range(3):
        blade(px, 20 + rng.uniform(-spec["spread"] * 0.8, spec["spread"] * 0.8), GROUND, rng.uniform(2, 4), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2, 3)), seed)
    return finish(px, spec["spread"], seed), glow.done()


def make_beet(spec, seed, pulled=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        crater(px, rng, [(cx, r * 0.78) for cx, r in spec["crowns"]], spec["spread"])
        return finish(px, spec["spread"], seed), glow.done()
    for cx, r in spec["crowns"]:
        soil_mound(px, cx, GROUND - 0.5, r + 2.6, 2.8)
    for i in range(spec["leaves"]):
        cx, r = spec["crowns"][i % len(spec["crowns"])]
        side = -1 if i % 2 == 0 else 1
        h = rng.uniform(*spec["len"])
        end = (clamp(cx + side * rng.uniform(1.5, 4.5), 5, FW - 6), max(6, GROUND - 3 - h))
        pts = bezier((cx + side * rng.uniform(0, 1.5), GROUND - 3), (cx, GROUND - 3 - h * 0.68), end, n=20)
        for x, y in pts:
            put(px, int(round(x)), int(round(y)), BEET_ST[1])
            put(px, int(round(x)) + 1, int(round(y)), BEET_ST[0])
        leaf(px, end[0], end[1] + 1, -math.pi / 2 + side * 0.52, 7.2 + rng.random() * 1.8, 2.7, BEETL, curve=side * 0.42, tone=3)
        if rng.random() < 0.5:
            glow.emit(px, int(clamp(round(end[0] + side * 1.5), 3, FW - 4)), max(3, int(round(end[1])) - 2), None, SHEEN, 0)
    for cx, r in spec["crowns"]:
        blob(px, cx, GROUND - r * 0.45, r, r * 0.78, BEETR)
        for k in range(1, 3):
            for a in range(195, 345, 12):
                x = int(round(cx + math.cos(math.radians(a)) * r * (0.34 * k + 0.15)))
                y = int(round(GROUND - r * 0.45 + math.sin(math.radians(a)) * r * 0.78 * (0.34 * k + 0.1)))
                put(px, x, y, BEETR[1])
        put(px, int(cx - r * 0.35), int(GROUND - r * 0.85), BEETR[4])
        glow.emit(px, int(cx) + 1, int(GROUND - r * 0.68), BEETR[3], SHEEN, 1)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Nebellilie & Funkenmohn (5 variants each)
LILIES = [
    {"stalks": [(20, 15, False)], "leaves": 5, "spread": 7},
    {"stalks": [(16, 13, False), (25, 17, True)], "leaves": 7, "spread": 9},
    {"stalks": [(13, 12, True), (21, 17, False), (28, 13, False)], "leaves": 9, "spread": 11},
    {"stalks": [(17, 17, False), (25, 12, True)], "leaves": 8, "spread": 10, "bud": True},
    {"stalks": [(11, 11, False), (17, 16, True), (24, 18, False), (30, 12, False)], "leaves": 11, "spread": 13},
]
POPPIES = [
    {"stalks": 2, "spread": 5, "lo": 13, "hi": 18, "leaves": 5, "lean": 0.0},
    {"stalks": 3, "spread": 7, "lo": 12, "hi": 19, "leaves": 7, "lean": 0.0},
    {"stalks": 5, "spread": 9, "lo": 11, "hi": 20, "leaves": 8, "lean": 0.0},
    {"stalks": 4, "spread": 10, "lo": 12, "hi": 19, "leaves": 8, "lean": 0.12},
    {"stalks": 7, "spread": 12, "lo": 10, "hi": 20, "leaves": 11, "lean": 0.0},
]


def lily_flower(px, glow, cx, cy, pal, rng, small=False):
    scale = 0.82 if small else 1.0
    for deg in (-152, -112, -68, -28, 162, 18, 90):
        a = math.radians(deg)
        front = deg in (162, 18, 90)
        ln = (6.2 if not front else 5.2) * scale
        leaf(px, cx + math.cos(a) * 0.7, cy + math.sin(a) * 0.5, a, ln, 1.85 * scale, pal, curve=(0.38 if math.cos(a) > 0 else -0.38) * (0.6 if front else 1.0), tone=2 if not front else 3)
        mx, my = cx + math.cos(a) * 2.8 * scale, cy + math.sin(a) * 2.5 * scale
        if rng.random() < 0.75:
            put(px, int(round(mx)), int(round(my)), pal[0] if not front else pal[1])
    put(px, int(round(cx)), int(round(cy)), VPET[2])
    for dx in ((-2, 0, 2) if not small else (-1, 1)):
        for j in range(1, 4):
            put(px, int(clamp(round(cx + dx * j / 3.0), 3, FW - 4)), max(2, int(round(cy - j))), pal[3])
        glow.emit(px, int(clamp(round(cx + dx), 3, FW - 4)), max(2, int(round(cy - 4))), STAMEN, STAMEN, 1)
    glow.emit(px, int(round(cx)), int(round(cy)), None, LILY_GLOW, 1)


def lily_bud(px, glow, cx, cy, pal):
    blob(px, cx, max(5, cy - 2.6), 2.2, 4.2, pal[:4])
    blob(px, cx, cy + 0.5, 1.9, 2.0, LEAFW[2:5], dither=False)
    put(px, int(round(cx)), max(2, int(round(cy - 6.5))), pal[4])
    glow.emit(px, int(round(cx)), max(2, int(round(cy - 5.5))), None, LILY_GLOW, 0)


def make_lily(spec, seed, row):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for i in range(spec["leaves"]):
        u = (i / max(spec["leaves"] - 1, 1) - 0.5) * 2.0
        blade(px, 20 + u * spec["spread"] * 0.7, GROUND, rng.uniform(6, 11) * (0.7 if row == 2 else 1.0), u * 0.65, 0.5, rng.choice((1, 2, 3)), seed + i)
    for idx, (x0, h, rose_tint) in enumerate(spec["stalks"]):
        pal = LILY_ROSE if rose_tint else LILY
        h_eff = 3.5 if row == 2 else h
        end = (clamp(x0 + (x0 - 20) * 0.08, 7, FW - 8), max(8, GROUND - h_eff))
        pts = bezier((x0, GROUND + 0.5), (x0 - 1, GROUND - h_eff * 0.6), end, n=24)
        stem(px, pts, 2, thick=(len(spec["stalks"]) <= 2))
        if row == 2:
            continue
        p = pts[len(pts) // 2]
        leaf(px, p[0], p[1], -math.pi / 2 - 0.85 * (1 if x0 >= 20 else -1), 5.5, 1.4, LEAFW, curve=0.3, tone=3)
        if row == 1 or (spec.get("bud") and idx == 1):
            lily_bud(px, glow, end[0], end[1], pal)
        else:
            lily_flower(px, glow, end[0], end[1] - 2.5, pal, rng, small=(len(spec["stalks"]) >= 4 and idx in (0, 3)))
    return finish(px, spec["spread"], seed + row), glow.done()


def poppy_flower(px, glow, cx, cy, r, pal, rng):
    """Silky cupped overlapping poppy petals, deep plum basal blotches & glowing ember crown."""
    cx = clamp(cx, 6, FW - 7)
    cy = clamp(cy, 6, GROUND - 5)
    # Back cupped petals
    blob(px, cx, cy - r * 0.42, r * 0.92, r * 0.68, pal[:4])
    # Side ruffled petals overlapping forward
    blob(px, cx - r * 0.55, cy + r * 0.12, r * 0.74, r * 0.78, pal)
    blob(px, cx + r * 0.55, cy + r * 0.12, r * 0.74, r * 0.78, pal[:4])
    # Front lip petal
    blob(px, cx, cy + r * 0.35, r * 0.68, r * 0.48, pal[1:])
    # Deep plum-velvet poppy heart + golden-ember stamen sparks
    blob(px, cx, cy, r * 0.36, r * 0.28, DISC, dither=False)
    put(px, int(round(cx - r * 0.42)), int(round(cy + r * 0.2)), pal[0])
    put(px, int(round(cx + r * 0.45)), int(round(cy + r * 0.15)), pal[0])
    put(px, int(round(cx - r * 0.5)), int(round(cy - r * 0.45)), pal[4])
    for k in (-1, 0, 1):
        put(px, int(round(cx + k * 1.1)), int(round(cy)) - 1, STAMEN if k == 0 else DISC[3])
    glow.emit(px, int(round(cx)), int(round(cy)) - 1, pal[4], POP_HOT, 1)
    glow.emit(px, int(clamp(round(cx - r * 0.75), 3, FW - 4)), max(3, int(round(cy - r * 0.45))), None, POP_GLOW, 0)


def make_poppy(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for i in range(spec["leaves"]):
        a = -math.pi / 2 + (i / max(spec["leaves"] - 1, 1) - 0.5) * 2.4 + rng.uniform(-0.15, 0.15)
        leaf(px, 20 + math.cos(a) * 2.0, GROUND - 1, a, rng.uniform(5, 9), 1.55, LEAFW, curve=rng.uniform(-0.55, 0.55), tone=2)
    xs = stalks_at(rng, spec["stalks"], spec["spread"] * 0.78)
    for i, x0 in enumerate(xs):
        h = rng.uniform(3.5, 5.5) if picked else rng.uniform(spec["lo"], spec["hi"])
        side = 1 if spec["lean"] > 0 else (1 if x0 >= 20 else -1)
        bud = (i == len(xs) - 1 and spec["stalks"] >= 2) and not picked and (i % 2 == 1)
        end = (clamp(x0 + side * rng.uniform(0.8, 2.6) + spec["lean"] * 18, 6, FW - 7), max(6, GROUND - h))
        pts = (bezier((x0, GROUND + 0.5), (x0 - side * 1.2, GROUND - h * 0.7), end, n=24)
               if not bud else
               bezier((x0, GROUND + 0.5), (x0, GROUND - h), (clamp(x0 + side * 2.8, 5, FW - 6), GROUND - h * 0.88), (clamp(x0 + side * 3.2, 5, FW - 6), GROUND - h * 0.55), n=24))
        stem(px, pts, 2)
        if picked:
            continue
        ex, ey = pts[-1]
        pal = POP_DEEP if (i % 2 == 1) else POP
        if bud:
            blob(px, ex, ey + 1.8, 1.8, 2.5, pal[1:4])
            blob(px, ex, ey + 0.5, 1.8, 1.4, LEAFW[2:5], dither=False)
            glow.emit(px, int(round(ex)), min(GROUND - 3, int(round(ey + 3.5))), None, POP_GLOW, 0)
        else:
            poppy_flower(px, glow, ex, ey - 1.8, 3.6 if spec["stalks"] <= 4 else 3.1, pal, rng)
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
    for a, ln in ((-2.2, 7), (-1.57, 8), (-0.95, 7)):
        for t in range(ln):
            x, y = 8 + math.cos(a) * t, 13 + math.sin(a) * t * 1.05
            for s in (-1, 0, 1):
                xx = int(round(x + s * (0 if abs(math.cos(a)) > 0.7 else 1)))
                yy = int(round(y + (s if abs(math.cos(a)) > 0.7 else 0)))
                if 0 < xx < 15 and 0 < yy < 15 and (abs(s) < 1 or t in (2, 3, 4)):
                    px[yy][xx] = LEAFW[3 + (1 if s < 0 else 0)] if s else LEAFW[5]


def i_fluff(px, g):
    blob(px, 8, 7, 4.4, 4.4, PUFF)
    px[7][8] = DISC[2]
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
    for a in (-2.2, -1.57, -0.9):
        for t in range(5):
            x, y = 8 + math.cos(a) * t * 1.1, 6 + math.sin(a) * t * 1.0
            px[int(round(y))][int(round(x))] = LEAFW[4 if t > 1 else 3]
    for x in range(4, 13):
        if px[13][x][3] == 0:
            px[13][x] = SOIL[2]


def i_carrot(px, g):
    for i in range(10):
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
    sheets["glowfern"] = [make_fern(s, 900 + i * 7, picked=r) for r in (False, True) for i, s in enumerate(GLOWFERNS)]
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
        write(name, frames, COLS, len(frames) // COLS)
    stripped_fern = [make_fern(s, 900 + i * 7, stripped=True)[0] for i, s in enumerate(GLOWFERNS)]
    stripped_cat = [make_cattail(s, 1000 + i * 19, stripped=True)[0] for i, s in enumerate(CATTAILS)]
    for i, px in enumerate(stripped_fern):
        fit("glowfern_stripped", i, px)
    for i, px in enumerate(stripped_cat):
        fit("cattail_stripped", i, px)
    write_plain("glowfern_stripped", stripped_fern, COLS)
    write_plain("cattail_stripped", stripped_cat, COLS)
    for name, draw in (("moonbell", i_moonbell), ("wound_leaf", i_wound), ("seed_fluff", i_fluff), ("fiddlehead", i_fiddle), ("fern_frond", i_frond),
                       ("reed", i_reed), ("sun_seed", i_sun), ("void_bloom", i_void), ("earth_tuber", i_tuber), ("ember_carrot", i_carrot), ("night_beet", i_beet), ("mist_lily", i_lily), ("spark_poppy", i_poppy)):
        write_png(items / (name + ".png"), 16, 16, icon(name, draw))
    assert not CUT, "cut off at the frame edge:\n" + "\n".join(CUT)
    print("flora written (12 species x 5 variants)")
    if len(sys.argv) > 1:
        preview(pathlib.Path(sys.argv[1]), sheets)


def preview(path, sheets):
    z = 2
    rows = sum(len(f) // COLS for f in sheets.values())
    w, h = FW * COLS * z, FH * rows * z
    out = [[(26, 40, 52, 255)] * w for _ in range(h)]
    r = 0
    for frames in sheets.values():
        for i, (base, glow) in enumerate(frames):
            ox, oy = (i % COLS) * FW * z, (r + i // COLS) * FH * z
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
        r += len(frames) // COLS
    write_png(path, w, h, out)


if __name__ == "__main__":
    main()
