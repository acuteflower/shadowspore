#!/usr/bin/env python3
"""Three plants of the water's edge (stdlib only), frames 40x34 like the other plants (feet at (20, 31)):
  assets/props/moon_iris.png        Mondiris: 3 stands of tall blue-green sword leaves with violet iris blooms (beard of light) x 2 rows (bloom, picked)
  assets/props/brook_mint.png       Bachminze: 3 mounds of serrated leaves with lilac whorled flower heads x 2 rows (whole, cut)
  assets/props/marsh_gold.png       Sumpfdotter: 3 clumps of big glossy kidney leaves with golden cup flowers x 2 rows (bloom, picked)
  every sheet has a `_glow` twin with only the emissive pixels
  assets/items/{iris_bloom,brook_mint,marsh_gold}.png   icons 16x16
`python3 tools/art_shore_plants.py [preview.png]`"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, Glow, blade, put, sheet  # noqa: E402
from art_bush import FH, FW, GROUND, bezier, blank, check_icon, clamp  # noqa: E402
from art_flora import LEAFW, LILY, STAMEN, blob, finish, leaf, ramp, stalks_at, stem  # noqa: E402
from gen_art import ROOT, hexc, outline_pass, write_png  # noqa: E402

IRISL = ramp("12283a", "1c4a52", "2c6e66", "429a82", "6cc4a0")
IRIS = ramp("241a64", "4632a4", "7260d4", "a494f0", "d8d0ff")
IRIS_F = ramp("1a1248", "36248a", "5a48c0", "8878e8", "ece8ff")
MINT = ramp("14343a", "1c5a4c", "2e7e5c", "4ea072", "7cc890", "b4ecb4")
MINT_B = ramp("46387a", "7a64b4", "a898dc", "d0c4f4")
GOLD = ramp("8a5a14", "d08a1c", "f0b830", "ffd860", "fff4b0")
KIDNEY = ramp("102a2c", "1a4a3c", "2a6a46", "3e8a54", "62ae66", "98d484")
DEW = hexc("c8fff4")

IRISES = [{"stalks": [(20, 15)], "blades": 6, "spread": 7}, {"stalks": [(15, 13), (25, 17)], "blades": 8, "spread": 10}, {"stalks": [(12, 12), (20, 16), (28, 13)], "blades": 10, "spread": 12}]
MINTS = [{"stems": 4, "spread": 7, "lo": 8, "hi": 14}, {"stems": 6, "spread": 10, "lo": 9, "hi": 16}, {"stems": 8, "spread": 13, "lo": 8, "hi": 17}]
MARSH = [{"leaves": 3, "flowers": 2, "spread": 7}, {"leaves": 5, "flowers": 3, "spread": 10}, {"leaves": 7, "flowers": 4, "spread": 13}]
CUT = []


def fit(name, i, px):
    pts = [(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]]
    if pts and not (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2):
        CUT.append("%s frame %d: top %d, x %d..%d" % (name, i, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))


# ------------------------------------------------------------------ Mondiris
def iris_bloom(px, glow, cx, cy, rng):
    for deg in (-120, -90, -60):  # three upright standards
        a = math.radians(deg)
        leaf(px, cx + math.cos(a), cy + math.sin(a), a, 5.5, 1.8, IRIS, curve=(0.3 if deg > -90 else -0.3), tone=2)
    for deg in (160, 90, 20):  # three falls hanging out and down, darker, white-veined
        a = math.radians(deg)
        leaf(px, cx + math.cos(a) * 0.6, cy + 0.5 + math.sin(a) * 0.4, a, 5.5 if deg == 90 else 6.5, 2.0, IRIS_F, curve=(0.4 if deg < 90 else -0.4), tone=2)
    for k in (-1, 0, 1):
        put(px, cx + k, cy + 2, IRIS_F[4])  # the pale vein down every fall
    put(px, cx, cy, STAMEN)
    glow.emit(px, cx, cy + 1, STAMEN, hexc("ffe8a0"), 1)  # the beard of light
    glow.emit(px, cx - 5, cy - 4, None, hexc("c8b8ff"), 0)
    glow.emit(px, cx + 5, cy - 4, None, hexc("c8b8ff"), 0)


def make_iris(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["blades"]
    for i in range(n):  # a fan of sword leaves, the outer ones leaning out
        u = (i + 0.5) / n * 2.0 - 1.0
        a = -math.pi / 2 + u * 0.55 + rng.uniform(-0.06, 0.06)
        ln = rng.uniform(16, 24) * (1.0 - 0.25 * abs(u)) * (0.5 if picked else 1.0)
        leaf(px, 20 + u * spec["spread"] * 0.5, GROUND - 1, a, ln, 1.3, IRISL, curve=u * 0.35, tone=2)
    for x0, h in spec["stalks"]:
        if picked:
            continue
        pts = bezier((x0, GROUND), (x0 - 1, GROUND - h * 0.6), (x0 + (x0 - 20) * 0.1, GROUND - h), n=24)
        stem(px, pts, 2)
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        iris_bloom(px, glow, tx, ty - 3, rng)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Bachminze
def make_mint(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["stems"] * 2):  # leaves low on the ground in opposite pairs
        a = -math.pi / 2 + rng.uniform(-1.45, 1.45)
        leaf(px, 20 + rng.uniform(-3, 3), GROUND - 1, a, rng.uniform(5, 9), 2.2, MINT, curve=rng.uniform(-0.5, 0.5), tone=3)
    for x0 in stalks_at(rng, spec["stems"], spec["spread"]):
        h = rng.uniform(4, 6) if picked else rng.uniform(spec["lo"], spec["hi"])
        end = (x0 + (x0 - 20) * 0.12, GROUND - h)
        pts = bezier((x0, GROUND), (x0 - 1, GROUND - h * 0.6), end, n=20)
        stem(px, pts, 3)
        for k in range(3, len(pts) - 2, 4):  # pairs of leaves up the stalk
            x, y = pts[k]
            for side in (-1, 1):
                leaf(px, x, y, -math.pi / 2 + side * 1.0, 4, 1.7, MINT, curve=side * 0.3, tone=3)
        if picked:
            continue
        ex, ey = int(round(end[0])), int(round(end[1]))
        for dy in (0, 3):  # two whorls of tiny lilac flowers
            blob(px, ex, ey + dy, 2.5, 2.1, MINT_B)
            for sx, sy in ((-3, 0), (3, 1), (0, -2)):
                put(px, ex + sx, ey + dy + sy, MINT_B[2])
        glow.emit(px, ex - 1, ey - 1, None, DEW, 0)
        if rng.random() < 0.5:
            glow.emit(px, ex + 3, ey + 2, None, hexc("bfe8ff"), 0)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Sumpfdotter
def buttercup(px, glow, cx, cy):
    for dx, dy in ((0, -2), (2, -1), (2, 1), (0, 2), (-2, 1), (-2, -1)):  # six rounded petals round a heart
        blob(px, cx + dx * 0.8, cy + dy * 0.8, 1.7, 1.5, GOLD[1:])
    blob(px, cx, cy, 1.4, 1.2, [GOLD[3], GOLD[4], GOLD[4]], dither=False)
    put(px, cx - 1, cy - 1, GOLD[4])
    glow.emit(px, cx, cy, GOLD[3], hexc("ffd070"), 1)


def make_marsh(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    n = spec["leaves"]
    for i in range(n):  # big glossy kidney leaves, a notch where the stalk goes in, back ones first
        cx = 20 + (i - (n - 1) / 2.0) * (2.0 * spec["spread"] / max(n, 1)) + rng.uniform(-1, 1)
        cy = GROUND - 4 - rng.uniform(0, 3) - (2 if i % 2 else 0)
        rx, ry = rng.uniform(5.0, 6.5), rng.uniform(3.6, 4.6)
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy > 1.0 or (dy > 0.35 and abs(dx) < 0.22):
                    continue
                lit = 0.5 - 0.45 * dx - 0.6 * dy
                put(px, x, y, KIDNEY[int(clamp(lit * 5.0 + (hash((x, y, i)) % 100 / 100.0 - 0.5) * 0.5, 1, 5))])
        for k in range(-int(rx) + 2, int(rx) - 1, 2):  # veins
            put(px, int(cx + k), int(cy - abs(k) * 0.3), KIDNEY[1])
        put(px, int(cx - rx * 0.4), int(cy - ry * 0.5), KIDNEY[5])  # a glossy highlight
    if not picked:
        for i in range(spec["flowers"]):
            x0 = 20 + (i - (spec["flowers"] - 1) / 2.0) * 7 + rng.uniform(-1, 1)
            h = rng.uniform(11, 17)
            pts = bezier((x0, GROUND - 3), (x0, GROUND - h * 0.7), (x0 + rng.uniform(-2, 2), GROUND - h), n=18)
            stem(px, pts, 3, thick=True)
            buttercup(px, glow, int(round(pts[-1][0])), int(round(pts[-1][1])) - 1)
    return finish(px, spec["spread"], seed), glow.done()


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
    sheets = {"moon_iris": [make_iris(s, 2100 + i * 13, picked=r) for r in (False, True) for i, s in enumerate(IRISES)],
              "brook_mint": [make_mint(s, 2200 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(MINTS)],
              "marsh_gold": [make_marsh(s, 2300 + i * 19, picked=r) for r in (False, True) for i, s in enumerate(MARSH)]}
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            fit(name, i, base)
            fit(name, i, glow)
        write_png(props / (name + ".png"), FW * 3, FH * 2, sheet([f[0] for f in frames], 3, 2))
        write_png(props / (name + "_glow.png"), FW * 3, FH * 2, sheet([f[1] for f in frames], 3, 2))
    assert not CUT, "cut off at the frame edge:\n" + "\n".join(CUT)
    for name, draw in (("iris_bloom", i_iris), ("brook_mint", i_mint), ("marsh_gold", i_marsh)):
        write_png(items / (name + ".png"), 16, 16, icon(name, draw))
    print("shore plants written")
    if len(sys.argv) > 1:
        from PIL import Image
        img = Image.new("RGBA", (FW * 3, FH * 6), (40, 70, 50, 255))
        for r, (name, frames) in enumerate(sheets.items()):
            for i, (b, g) in enumerate(frames):
                for layer in (b, g):
                    tile = Image.new("RGBA", (FW, FH))
                    tile.putdata([c for row in layer for c in row])
                    img.alpha_composite(tile, ((i % 3) * FW, (r * 2 + i // 3) * FH))
        img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(sys.argv[1])


if __name__ == "__main__":
    main()
