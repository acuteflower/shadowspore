#!/usr/bin/env python3
"""Three plants of the water's edge (stdlib only), frames 40x34 (feet at (20, 31)):
  assets/props/moon_iris.png        Mondiris: 5 stands of tall glaucous sword leaves with royal-violet iris blooms x 2 rows
  assets/props/brook_mint.png       Bachminze: 5 mounds of opposite mint leaves with lilac whorled flower heads x 2 rows
  assets/props/marsh_gold.png       Sumpfdotter: 5 clumps of glossy cel-shaded kidney leaves with golden cup blooms x 2 rows
  every sheet has a `_glow` twin with only the emissive pixels
  assets/items/{iris_bloom,brook_mint,marsh_gold}.png   icons 16x16
Harmonized with Shadowspore's structured cel + Bayer shading (zero hash pixel noise!), cool indigo-violet deep shadows,
cool teal waterside rim highlights, and adaptive material-tinted 1px outlines."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, RIM, Glow, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, check_icon, clamp  # noqa: E402
from art_flora import LIGHT, STAMEN, blob, finish, leaf, ramp, stalks_at, stem  # noqa: E402
from gen_art import ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

COLS = 5
IRISL = ramp("12263a", "1b4852", "2b6e68", "429a84", "6cc4a2")
IRIS = ramp("221860", "4430a0", "705ed2", "a494f0", "dcd4ff")
IRIS_F = ramp("181046", "322284", "5846be", "8878e6", "ece8ff")
MINT = ramp("122c38", "1b544a", "2c7a5c", "4ca074", "78c890", "b0eab2")
MINT_B = ramp("3e3274", "6e5cae", "a090da", "d4c8f6")
GOLD = ramp("7c4e14", "c27e1c", "eaa82c", "ffd65c", "fff2a8")
KIDNEY = ramp("102634", "184640", "266a4c", "3e925c", "64bc74", "9ce092")
DEW = hexc("c8fff4")

IRISES = [
    {"stalks": [(20, 15, False)], "blades": 6, "spread": 7},
    {"stalks": [(16, 13, False), (25, 17, False)], "blades": 8, "spread": 9},
    {"stalks": [(13, 12, False), (20, 17, False), (28, 13, False)], "blades": 10, "spread": 11},
    {"stalks": [(17, 17, False), (25, 13, True)], "blades": 9, "spread": 10},  # tall bloom + furled violet spire bud
    {"stalks": [(11, 11, False), (17, 16, False), (24, 17, False), (30, 12, True)], "blades": 11, "spread": 12.5},
]
MINTS = [
    {"stems": 3, "spread": 6, "lo": 9, "hi": 14, "lean": 0.0},
    {"stems": 4, "spread": 8, "lo": 9, "hi": 15, "lean": 0.0},
    {"stems": 6, "spread": 10, "lo": 8, "hi": 16, "lean": 0.0},
    {"stems": 5, "spread": 10, "lo": 9, "hi": 15, "lean": 0.12},  # trailing waterside drift
    {"stems": 7, "spread": 12, "lo": 8, "hi": 16, "lean": 0.0},
]
MARSH = [
    {"leaves": 3, "flowers": 1, "spread": 7, "bud": True},
    {"leaves": 4, "flowers": 2, "spread": 8.5, "bud": False},
    {"leaves": 5, "flowers": 3, "spread": 10, "bud": False},
    {"leaves": 6, "flowers": 3, "spread": 11, "bud": True},
    {"leaves": 7, "flowers": 4, "spread": 12, "bud": False},
]
CUT = []


def fit(name, i, px):
    pts = [(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]]
    if pts and not (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2):
        CUT.append("%s frame %d: top %d, x %d..%d" % (name, i, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))


def finish_shore(px, spread, seed):
    # Extra cool aqua-teal waterside rim on glaucous shore leaves before standard finish()
    for y in range(FH):
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and (c in IRISL[1:4] or c in MINT[1:4] or c in KIDNEY[1:4]) and px[y][x + 1][3] == 0 and noise(x, y, seed + 5) > 95:
                px[y][x] = RIM[int(noise(x, y, seed + 6) > 150)]
    return finish(px, spread, seed)


# ------------------------------------------------------------------ Mondiris
def iris_bloom(px, glow, cx, cy):
    cx = int(clamp(cx, 7, FW - 8))
    cy = int(clamp(cy, 7, GROUND - 6))
    for deg in (-118, -90, -62):  # three arched standards
        a = math.radians(deg)
        leaf(px, cx + math.cos(a) * 0.8, cy + math.sin(a) * 0.8, a, 5.2, 1.8, IRIS, curve=(0.35 if deg > -90 else (-0.35 if deg < -90 else 0.0)), tone=3)
    for deg in (158, 90, 22):  # three drooping velvet falls
        a = math.radians(deg)
        leaf(px, cx + math.cos(a) * 0.6, cy + 0.5 + math.sin(a) * 0.4, a, 5.2 if deg == 90 else 6.0, 2.0, IRIS_F, curve=(0.38 if deg < 90 else (-0.38 if deg > 90 else 0.0)), tone=2)
    for k in (-1, 0, 1):
        put(px, cx + k, cy + 2, IRIS_F[4])
    put(px, cx, cy, STAMEN)
    glow.emit(px, cx, cy + 1, STAMEN, hexc("ffe8a0"), 1)
    glow.emit(px, max(3, cx - 4), max(3, cy - 3), None, hexc("c8b8ff"), 0)
    glow.emit(px, min(FW - 4, cx + 4), max(3, cy - 3), None, hexc("c8b8ff"), 0)


def iris_bud(px, glow, cx, cy):
    cx = int(clamp(cx, 6, FW - 7))
    cy = int(clamp(cy, 7, GROUND - 5))
    blob(px, cx, cy - 2.2, 1.9, 3.8, IRIS[:4])
    blob(px, cx, cy + 0.4, 1.7, 1.8, IRISL[1:4], dither=False)
    put(px, cx, max(2, cy - 5), IRIS[4])
    glow.emit(px, cx, max(2, cy - 4), None, hexc("c8b8ff"), 0)


def make_iris(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["blades"]
    for i in range(n):
        u = (i + 0.5) / n * 2.0 - 1.0
        a = -math.pi / 2 + u * 0.52 + rng.uniform(-0.05, 0.05)
        ln = rng.uniform(15, 22) * (1.0 - 0.25 * abs(u)) * (0.48 if picked else 1.0)
        leaf(px, 20 + u * spec["spread"] * 0.48, GROUND - 1, a, ln, 1.35, IRISL, curve=u * 0.32, tone=2)
    for x0, h, is_bud in spec["stalks"]:
        if picked:
            pts = bezier((x0, GROUND), (x0, GROUND - 3), (x0, GROUND - 5), n=8)
            stem(px, pts, 2)
            continue
        pts = bezier((x0, GROUND), (x0 - 1, GROUND - h * 0.6), (clamp(x0 + (x0 - 20) * 0.08, 7, FW - 8), GROUND - h), n=24)
        stem(px, pts, 2)
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        if is_bud:
            iris_bud(px, glow, tx, ty - 1)
        else:
            iris_bloom(px, glow, tx, ty - 3)
    return finish_shore(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Bachminze
def make_mint(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    blob(px, 20, GROUND - 3.5, spec["spread"] * 0.55, 3.2, [MINT[0], MINT[1], MINT[2], MINT[3]])
    for i in range(spec["stems"] * 2 + 2):
        a = -math.pi / 2 + (i / max(spec["stems"] * 2 + 1, 1) - 0.5) * 2.5 + rng.uniform(-0.15, 0.15)
        leaf(px, 20 + math.cos(a) * 2.5, GROUND - 1, a, rng.uniform(5, 8.5), 2.1, MINT, curve=rng.uniform(-0.45, 0.45), tone=3)
    for x0 in stalks_at(rng, spec["stems"], spec["spread"] * 0.78):
        h = rng.uniform(4, 6) if picked else rng.uniform(spec["lo"], spec["hi"])
        end = (clamp(x0 + (x0 - 20) * 0.12 + spec["lean"] * 18, 6, FW - 7), max(6, GROUND - h))
        pts = bezier((x0, GROUND), (x0 - 0.8, GROUND - h * 0.6), end, n=20)
        stem(px, pts, 3)
        for k in range(4, len(pts) - 2, 5):
            x, y = pts[k]
            for side in (-1, 1):
                leaf(px, x, y, -math.pi / 2 + side * 1.05, 3.8, 1.7, MINT, curve=side * 0.28, tone=3)
        if picked:
            continue
        ex, ey = int(round(end[0])), int(round(end[1]))
        # Tiered lilac flower whorls (verticillasters)
        for w_idx, (dy, rx) in enumerate(((0, 2.2), (3, 2.7))):
            yy = min(GROUND - 4, ey + dy)
            blob(px, ex, yy, rx, 1.9, MINT_B)
            put(px, max(3, ex - int(rx)), yy, MINT_B[3])
            if w_idx == 0:
                put(px, ex, max(2, yy - 2), MINT_B[3])
        glow.emit(px, max(3, ex - 1), max(3, ey - 1), None, DEW, 0)
        if rng.random() < 0.55:
            glow.emit(px, min(FW - 4, ex + 2), min(GROUND - 4, ey + 2), None, hexc("bfe8ff"), 0)
    return finish_shore(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Sumpfdotter
def buttercup(px, glow, cx, cy, bud=False):
    cx = int(clamp(cx, 6, FW - 7))
    cy = int(clamp(cy, 6, GROUND - 5))
    if bud:
        blob(px, cx, cy, 1.9, 1.9, GOLD[1:4])
        put(px, cx - 1, cy - 1, GOLD[4])
        glow.emit(px, cx, cy, GOLD[3], hexc("ffd070"), 0)
        return
    # Five cupped overlapping golden marsh-marigold petals + glowing stamen cluster
    for k in range(5):
        a = -math.pi / 2 + k / 5.0 * math.tau
        px_c = cx + math.cos(a) * 1.65
        py_c = cy + math.sin(a) * 1.45
        blob(px, px_c, py_c, 1.65, 1.45, GOLD[1:] if math.cos(a) <= 0.2 else GOLD[:4])
    blob(px, cx, cy, 1.35, 1.15, [GOLD[2], GOLD[3], GOLD[4]], dither=False)
    put(px, cx - 1, cy - 1, GOLD[4])
    glow.emit(px, cx, cy, GOLD[4], hexc("ffd478"), 1)


def kidney_leaf(px, cx, cy, rx, ry):
    """Smooth glossy cel + Bayer shaded cordate/kidney marsh leaf (zero random hash noise!)."""
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if not (2 <= x < FW - 2 and 2 <= y < GROUND + 1):
                continue
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            # Cordate basal sinus notch on lower side
            if dx * dx + dy * dy > 1.0 or (dy > 0.30 and abs(dx) < 0.24 * (dy + 0.4)):
                continue
            lit = 0.52 + 0.40 * (dx * LIGHT[0] + dy * LIGHT[1]) + 0.14 * (1.0 - (dx * dx + dy * dy))
            lit += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.20
            put(px, x, y, KIDNEY[int(clamp(lit * len(KIDNEY), 0, len(KIDNEY) - 1))])
    # Crisp palmate mid-veins & wet marsh sheen on top-left lobe
    put(px, int(round(cx)), int(round(cy)), KIDNEY[1])
    put(px, int(round(cx - rx * 0.35)), int(round(cy - ry * 0.45)), KIDNEY[5])
    put(px, int(round(cx - rx * 0.50)), int(round(cy - ry * 0.35)), KIDNEY[5])


def make_marsh(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["leaves"]
    # Back kidney leaves higher, front leaves lower for natural overlapping marsh mound
    order = sorted(range(n), key=lambda i: -(i % 2))
    for i in order:
        cx = clamp(20 + (i - (n - 1) / 2.0) * (1.85 * spec["spread"] / max(n, 1)) + rng.uniform(-0.8, 0.8), 7.5, FW - 8.5)
        cy = GROUND - 3.5 - (2.4 if i % 2 == 1 else 0.4) - rng.uniform(0, 1.8)
        rx, ry = rng.uniform(4.8, 6.0), rng.uniform(3.4, 4.3)
        kidney_leaf(px, cx, cy, rx, ry)
    if not picked:
        nf = spec["flowers"] + (1 if spec.get("bud") else 0)
        for i in range(nf):
            x0 = clamp(20 + (i - (nf - 1) / 2.0) * 5.6 + rng.uniform(-0.8, 0.8), 7, FW - 8)
            is_bud = bool(spec.get("bud") and i == nf - 1)
            h = rng.uniform(10, 13) if is_bud else rng.uniform(12, 17)
            pts = bezier((x0, GROUND - 3), (x0, GROUND - h * 0.7), (clamp(x0 + rng.uniform(-1.8, 1.8), 7, FW - 8), GROUND - h), n=18)
            stem(px, pts, 3, thick=not is_bud)
            buttercup(px, glow, pts[-1][0], pts[-1][1] - 1, bud=is_bud)
    return finish_shore(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ icons
def icon(name, draw):
    px = blank(16, 16)
    draw(px)
    check_icon(name, px)
    return outline_pass(px, hexc("1b1a2e"))


def i_iris(px):
    for y in range(8, 14):
        px[y][8] = GRASS[2]
    px[12][7], px[11][7], px[11][9], px[10][9] = IRISL[3], IRISL[3], IRISL[3], IRISL[3]
    px[13][7], px[13][9] = IRISL[2], IRISL[2]
    for deg in (-120, -90, -60):
        a = math.radians(deg)
        for j in range(1, 5):
            px[int(round(6 + math.sin(a) * j))][int(round(8 + math.cos(a) * j))] = IRIS[3 if j > 1 else 2]
    for deg in (160, 90, 20):
        a = math.radians(deg)
        for j in range(1, 5 if deg != 90 else 4):
            px[int(round(6 + math.sin(a) * j))][int(round(8 + math.cos(a) * j))] = IRIS_F[2 + (j == 4)]
    px[6][8] = STAMEN
    px[7][8] = STAMEN


def i_mint(px):
    for y in range(5, 14):
        px[y][8] = MINT[2]
    for dy, side in ((9, -1), (9, 1), (11, -1), (11, 1), (13, -1), (13, 1)):
        for k in range(1, 4):
            px[dy][8 + side * k] = MINT[4 if k < 3 else 3]
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)):
        px[4 + dy][8 + dx] = MINT_B[3 if dx <= 0 else 2]
    px[3][8] = MINT_B[3]


def i_marsh(px):
    for y in range(5, 13):
        px[y][8] = GRASS[2]
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
        px[4 + dy][8 + dx] = GOLD[3 if dx <= 0 else 2]
    px[4][8] = GOLD[4]
    for dx in range(-4, 5):
        for dy in (0, 1):
            if abs(dx) + dy * 2 <= 5:
                px[12 + dy][8 + dx] = KIDNEY[4 if dx < 0 else 3]


def main():
    props, items = ROOT / "props", ROOT / "items"
    sheets = {
        "moon_iris": [make_iris(s, 2100 + i * 13, picked=r) for r in (False, True) for i, s in enumerate(IRISES)],
        "brook_mint": [make_mint(s, 2200 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(MINTS)],
        "marsh_gold": [make_marsh(s, 2300 + i * 19, picked=r) for r in (False, True) for i, s in enumerate(MARSH)],
    }
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            fit(name, i, base)
            fit(name, i, glow)
        write_png(props / (name + ".png"), FW * COLS, FH * 2, sheet([f[0] for f in frames], COLS, 2))
        write_png(props / (name + "_glow.png"), FW * COLS, FH * 2, sheet([f[1] for f in frames], COLS, 2))
    assert not CUT, "cut off at the frame edge:\n" + "\n".join(CUT)
    for name, draw in (("iris_bloom", i_iris), ("brook_mint", i_mint), ("marsh_gold", i_marsh)):
        write_png(items / (name + ".png"), 16, 16, icon(name, draw))
    print("shore plants (5 variants each) written")


if __name__ == "__main__":
    main()
