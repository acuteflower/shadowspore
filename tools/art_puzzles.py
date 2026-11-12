"""The objects of the trials of the Wächterin (docs/raetsel_konzept.md): rune steles, the sundial, the trial stone, lantern posts, the pilgrim
shrines, (the hoard perches of crow and raven are tools/art_hoard.py and art_hoard_raven.py), the dirt mound and the snapping twigs. Same renderer as the loot chests (tools/art_loot_chests.py: oriented boxes +
art_hero3d ellipsoids, light from the top left, ink outline), the pale violet stone of the waystone statues with teal inlay.
    py -3 tools/art_puzzles.py [preview.png]
Writes assets/props/puzzles/<name>.png (+ <name>_glow.png where something glows) and data/puzzle_art.json (frame, ground row, frames, anchors in px
from the feet) and data/puzzle_runes.json (the six 5x5 trial runes, drawn by the game on steles and on the ground ring)."""
import json
import math
import pathlib
import sys

import numpy as np

import art_loot_chests as c
import art_hero3d as h
from gen_art import ROOT, hexc, write_png

OUT = ROOT / "props" / "puzzles"
DATA = ROOT.parent / "data" / "puzzle_art.json"
RUNES_OUT = ROOT.parent / "data" / "puzzle_runes.json"
V = c.V
Scene, rx, rz = c.Scene, c.rx, c.rz
BASE = len(h.RAMPS)
_R = [
    ("PALE", ["2c2844", "565078", "8880a8", "c0b8da"]),  # the waystones' pale violet stone
    ("BRONZE", ["3a2a1a", "6a4a28", "a0763c", "dab276"]),
    ("EARTH", ["1c1410", "38281e", "584030", "7c6048"]),
    ("DEADWOOD", ["3c3436", "625856", "8e8480", "bcb2aa"]),
    ("BONE", ["4e4a50", "7e7a7e", "b2aeaa", "e2ded4"]),
]
for i, (name, ramp) in enumerate(_R):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(x) for x in ramp] for _, ramp in _R]
c.EMISSIVE.update({h.TEAL: 1, c.AMBER: 1, c.SILVER: 2, h.VIOLET: 1, c.MOON: 1})

RUNES = {  # the six trial runes, 5 x 5
    "mond": [".XXX.", "XX...", "X....", "XX...", ".XXX."],
    "wurzel": ["..X..", "..X..", ".XXX.", "X.X.X", "X.X.X"],
    "auge": ["..X..", ".X.X.", "X.X.X", ".X.X.", "..X.."],
    "flamme": ["..X..", ".XX..", ".XXX.", "XX.XX", ".XXX."],
    "welle": ["X..X.", ".XX.X", ".....", "X..X.", ".XX.X"],
    "feder": ["....X", "...XX", "..XX.", ".XX..", "X...."],
}
RUNE_ORDER = ["mond", "wurzel", "auge", "flamme", "welle", "feder"]


def moss(s, rng, cx, cz, rxx, rzz, n=4, y=0.6):
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        s.ell((cx + math.cos(a) * rxx * rng.uniform(0.6, 1.0), y, cz + math.sin(a) * rzz * rng.uniform(0.6, 1.0)), (rng.uniform(1.6, 2.6), 0.8, rng.uniform(1.0, 1.8)), c.MOSS)


# ------------------------------------------------------------------ objects (each returns a Scene)
def stele(rune):
    s = Scene()
    rng = np.random.default_rng(11)
    s.box((0, 1.4, 0), (5.6, 1.4, 4.2), PALE, kind="stone", seed=0.3)
    lean = rz(0.05)
    s.box((0, 13.5, 0), (4.4, 10.8, 2.3), PALE, R=lean, kind="stone", seed=1.1)
    s.ell((0.5, 24.6, 0), (4.3, 2.0, 2.3), PALE, R=lean)
    s.box((-1.5, 18.0, 2.25), (0.25, 3.0, 0.1), c.DARK, kind="")  # a crack
    s.box((-1.2, 15.6, 2.25), (1.0, 0.22, 0.1), c.DARK, kind="")
    for k in range(3):  # the teal inlay band under the rune
        s.box((-2.6 + k * 2.6, 6.4, 2.35), (0.9, 0.35, 0.1), h.TEAL, kind="emit")
    moss(s, rng, 0, 0, 6.0, 4.6, 5)
    s.ell((-3.4, 21.0, 1.0), (1.6, 0.8, 1.8), c.MOSS)
    return s


def stele_rune_anchor():
    return c.screen((0.0, 16.5, 2.4), 28, 42)


def sundial():
    s = Scene()
    rng = np.random.default_rng(13)
    for a in (0.0, math.pi / 4):  # an octagonal plinth of two turned boxes
        s.box((0, 2.0, 0), (6.6, 2.0, 6.6), PALE, R=h.rot_y(a), kind="stone", seed=a)
    s.box((0, 4.5, 0), (4.6, 0.6, 4.6), PALE, R=h.rot_y(0.39), kind="stone")
    s.ell((0, 5.4, 0), (9.5, 0.8, 9.5), BRONZE)  # the dial plate's bronze rim
    s.ell((0, 5.9, 0), (8.7, 0.6, 8.7), PALE)
    for k in range(12):  # hour ticks
        a = k * math.pi / 6
        s.ell((7.4 * math.cos(a), 6.35, 7.4 * math.sin(a)), (0.45, 0.2, 0.45), BRONZE)
    s.limb((0, 6.2, 1.5), (0, 15.5, -4.5), 0.75, 0.5, BRONZE)  # the gnomon leaning north
    s.limb((0, 6.2, 1.5), (0, 6.6, -4.5), 0.5, 0.5, BRONZE)
    s.ell((0, 16.4, -5.2), (1.3, 1.6, 1.0), c.GOLD)  # a feather knob
    s.ell((0.4, 17.6, -5.6), (0.5, 1.1, 0.3), c.GOLD, R=rz(-0.4))
    moss(s, rng, 0, 0, 7.5, 7.5, 6)
    return s


def trial_stone(rift):
    s = Scene()
    rng = np.random.default_rng(17)
    s.box((0, 1.2, 0), (5.2, 1.2, 4.2), PALE, kind="stone", seed=0.7)
    s.ell((0, 8.0, 0), (4.4, 7.0, 3.4), PALE)
    s.ell((0, 14.4, 0), (2.8, 1.6, 2.4), PALE)
    s.ell((0, 9.0, 3.1), (1.6, 1.6, 0.6), PALE if not rift else c.DARK)  # the eye's socket
    s.ell((0, 9.0, 3.45), (1.0, 1.0, 0.4), h.TEAL if not rift else h.VIOLET, kind="emit")
    for k in range(5):  # crystals growing from its flank
        a = 2.2 + k * 0.35
        base = V(math.cos(a) * 4.0, 3.0 + k * 0.8, math.sin(a) * 3.0)
        tip = base + V(math.cos(a) * 2.6, 3.2 + k * 0.4, math.sin(a) * 1.4)
        s.ell(tuple((base + tip) / 2), (0.7, float(np.linalg.norm(tip - base)) / 2, 0.7), c.STONE if not rift else h.VIOLET, R=h.frame_from(tip - base, V(0, 0, 1)), kind="" if not rift else "emit")
    if rift:  # violet veins from the eye
        for pts in (((0.6, 8.0, 3.3), (2.2, 5.0, 3.0), (3.0, 2.4, 2.6)), ((-0.8, 10.0, 3.2), (-2.4, 12.2, 2.6))):
            for a, b in zip(pts, pts[1:]):
                s.limb(a, b, 0.3, 0.25, h.VIOLET, kind="emit")
    moss(s, rng, 0, 0, 5.5, 4.4, 4)
    return s


def lantern_post(lit):
    s = Scene()
    rng = np.random.default_rng(19)
    s.box((0, 1.4, 0), (4.0, 1.4, 4.0), PALE, kind="stone", seed=0.2)
    s.box((0, 14.0, 0), (2.2, 11.5, 2.2), PALE, kind="stone", seed=0.9)
    s.box((0, 26.2, 0), (3.0, 0.8, 3.0), PALE, kind="stone")
    s.limb((1.6, 25.0, 0), (6.6, 28.0, 0), 0.5, 0.45, c.CHAIN)  # the iron arm
    s.limb((6.6, 28.0, 0), (7.6, 26.2, 0), 0.4, 0.4, c.CHAIN)
    cx, cy = 7.6, 21.8
    s.box((cx, cy + 3.8, 0), (2.4, 0.4, 2.4), c.CHAIN, kind="metal")
    s.box((cx, cy - 3.2, 0), (2.4, 0.4, 2.4), c.CHAIN, kind="metal")
    for dx in (-2.0, 2.0):
        for dz in (-2.0, 2.0):
            s.box((cx + dx, cy + 0.3, dz), (0.3, 3.4, 0.3), c.CHAIN, kind="metal")
    if lit:
        s.ell((cx, cy, 0), (1.9, 3.0, 1.9), c.AMBER, kind="emit")
        s.ell((cx, cy - 0.6, 0.2), (0.8, 1.5, 0.8), c.WAX, kind="emit")
    else:
        s.ell((cx, cy, 0), (1.9, 3.0, 1.9), c.DARK)
        s.ell((cx, cy - 2.4, 0.4), (0.7, 0.6, 0.7), c.WAX)  # a dead stub of wick
    s.ell((-2.0, 18.0, 1.6), (1.4, 2.8, 1.0), c.MOSS)
    moss(s, rng, 0, 0, 4.6, 4.6, 4)
    return s


def shrine(big, lit):
    s = Scene()
    rng = np.random.default_rng(23 if big else 29)
    W = 12.0 if big else 7.0
    s.box((0, 1.0, 0), (W + 3.0, 1.0, 6.0), PALE, kind="stone", seed=0.1)
    s.box((0, 2.6, -0.5), (W + 1.6, 0.6, 5.0), PALE, kind="stone", seed=0.5)
    H = 20.0 if big else 13.0
    for x in (-W, W):  # pillars
        s.box((x, 3.2 + H / 2, -1.0), (1.8, H / 2, 1.8), PALE, kind="stone", seed=x)
    s.box((0, 3.2 + H / 2, -3.4), (W - 1.0, H / 2, 0.8), PALE, kind="stone", seed=1.9)  # back wall
    roof_y = 3.2 + H
    for side in (-1, 1):  # a gabled stone roof
        s.box((side * (W + 2.6) / 2, roof_y + 2.0, -1.0), ((W + 2.6) / 2 + 0.6, 0.8, 4.4), PALE, R=rz(-side * 0.42), kind="stone", seed=side)
    s.ell((0, roof_y + 4.2, -1.0), (1.4, 1.2, 4.2), PALE)
    bowl_y = 3.8
    s.ell((0, bowl_y + 1.0, 0.6), (3.2, 1.2, 2.6), BRONZE)
    s.ell((0, bowl_y + 1.6, 0.6), (2.6, 0.5, 2.0), c.DARK)
    if lit:
        s.limb((0, bowl_y + 1.8, 0.6), (0.2, bowl_y + 7.4, 0.6), 1.9, 0.35, c.AMBER, kind="emit")
        s.ell((0, bowl_y + 3.0, 0.8), (1.0, 1.4, 1.0), c.WAX, kind="emit")
        s.ell((0, bowl_y + 8.0, -3.0), (5.0, 4.0, 0.3), c.AMBER, kind="emit")  # light on the back wall
    if big:  # the bell under the roof
        s.limb((0, roof_y + 0.6, -1.0), (0, roof_y - 2.6, -1.0), 0.3, 0.3, c.CHAIN)
        s.ell((0, roof_y - 5.2, -1.0), (2.8, 3.0, 2.8), BRONZE)
        s.ell((0, roof_y - 7.6, -1.0), (3.2, 0.7, 3.2), BRONZE)
        s.ell((0, roof_y - 8.4, -1.0), (0.6, 0.6, 0.6), c.CHAIN)
    s.ell((-W, 3.2 + H * 0.6, 0.9), (1.4, 3.0, 0.8), c.MOSS)
    s.ell((W * 0.5, roof_y + 3.2, 1.6), (2.6, 0.7, 1.6), c.MOSS)
    moss(s, rng, 0, 0, W + 3.5, 6.5, 6)
    return s


def mound():
    s = Scene()
    rng = np.random.default_rng(31)
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0, 5.0)
        s.ell((math.cos(a) * r, 1.4 + rng.uniform(0, 1.2), math.sin(a) * r * 0.7), (rng.uniform(2.4, 3.6), rng.uniform(1.4, 2.4), rng.uniform(2.0, 3.0)), EARTH)
    for k in range(7):  # crumbs round it
        a = rng.uniform(0, 2 * math.pi)
        s.ell((math.cos(a) * 9.0, 0.5, math.sin(a) * 6.0), (0.9, 0.6, 0.8), EARTH)
    s.limb((2.4, 3.8, 1.0), (5.4, 5.6, 2.0), 0.4, 0.35, c.CHAIN)  # a bent spoon sticking out
    s.ell((5.8, 5.9, 2.2), (0.9, 0.4, 0.7), c.SILVER, kind="emit")
    s.ell((-3.0, 3.6, 2.4), (0.5, 0.5, 0.4), c.SILVER, kind="emit")  # a glint
    s.limb((-1.0, 3.4, 2.6), (-3.6, 5.0, 3.4), 0.25, 0.15, c.CHAIN)  # a black feather
    return s


def twig(variant, broken):
    s = Scene()
    rng = np.random.default_rng(37 + variant)
    ln = 5.5 + variant * 1.2
    ang = (0.3, -0.6, 1.1)[variant]
    d = V(math.cos(ang), 0, math.sin(ang) * 0.6)
    if broken:
        s.limb(tuple(V(0, 0.5, 0) - d * ln), tuple(V(0, 0.6, 0) - d * 0.8), 0.55, 0.45, DEADWOOD)
        s.limb(tuple(V(0.6, 0.5, 0.8) + d * 0.6), tuple(V(0.6, 0.5, 0.8) + d * ln), 0.5, 0.4, DEADWOOD)
        s.ell((0, 0.4, 0.4), (0.5, 0.3, 0.5), BONE)  # bright splinters
        s.ell((0.6, 0.4, 0.9), (0.4, 0.3, 0.4), BONE)
    else:
        s.limb(tuple(V(0, 0.55, 0) - d * ln), tuple(V(0, 0.55, 0) + d * ln), 0.55, 0.45, DEADWOOD)
        side = V(-d[2], 0, d[0])
        s.limb(tuple(d * 1.5 + V(0, 0.5, 0)), tuple(d * 3.4 + side * 2.6 + V(0, 0.9, 0)), 0.35, 0.2, DEADWOOD)
        s.limb(tuple(-d * 2.0 + V(0, 0.5, 0)), tuple(-d * 3.6 - side * 2.0 + V(0, 0.8, 0)), 0.3, 0.2, DEADWOOD)
    return s


def hoard(raven):
    s = Scene()
    rng = np.random.default_rng(41 if raven else 43)
    mat = BONE if raven else c.BARK
    H = 24.0 if raven else 11.0
    s.ell((0, 1.4, 0), (5.4, 2.0, 4.8), mat)  # root flare
    for a in (0.4, 2.2, 4.0):
        s.limb((math.cos(a) * 3.4, 1.0, math.sin(a) * 3.0), (math.cos(a) * 7.4, 0.3, math.sin(a) * 5.4), 1.1, 0.5, mat)
    s.limb((0, 1.0, 0), (0.6, H, -0.4), 3.4, 2.4, mat)
    if raven:  # a broken snag with one bare branch and a hollow
        s.limb((0.6, H * 0.72, -0.2), (7.6, H * 0.92, 1.0), 1.1, 0.5, mat)
        s.limb((7.6, H * 0.92, 1.0), (9.6, H * 1.02, 0.6), 0.5, 0.3, mat)
        s.ell((0.4, H * 0.5, 2.4), (1.2, 1.8, 0.6), c.DARK)
        for k in range(5):
            s.ell((rng.uniform(-1.6, 1.6), H + rng.uniform(-0.6, 0.6), rng.uniform(-1.4, 1.4)), (1.1, 1.4, 1.0), mat)
    else:  # a cut stump with a nest of twigs on top
        s.ell((0.6, H + 0.2, -0.4), (2.6, 0.6, 2.4), DEADWOOD)
        for k in range(14):
            a = k * 2 * math.pi / 14
            s.limb((0.6 + math.cos(a) * 2.6, H + 1.0, -0.4 + math.sin(a) * 2.2), (0.6 + math.cos(a + 0.9) * 3.2, H + 1.6, -0.4 + math.sin(a + 0.9) * 2.6), 0.4, 0.3, DEADWOOD)
    top = H + (1.6 if not raven else 0.6)
    for k in range(4):  # glitter in the nest / hollow and in the grass
        s.ell((rng.uniform(-1.6, 2.4), top + 0.4 if k < 2 else 0.4, rng.uniform(-1.2, 1.2) if k < 2 else rng.uniform(5.0, 7.0)), (0.5, 0.35, 0.5), c.SILVER, kind="emit")
    moss(s, rng, 0, 0, 5.0, 4.4, 4)
    return s


# ------------------------------------------------------------------ sheets
SHEETS = {
    # name: (frames builders, FW, FH, GR, shadow (sx, sy, rx, ry))
    "stele": ([lambda: stele(r) for r in RUNE_ORDER], 28, 48, 42, (0, -1, 8, 3)),
    "sundial": ([sundial], 40, 40, 32, (0, -1, 12, 5)),
    "trial_stone": ([lambda: trial_stone(False), lambda: trial_stone(True)], 28, 34, 29, (0, -1, 8, 3)),
    "lantern_post": ([lambda: lantern_post(False), lambda: lantern_post(True)], 32, 52, 46, (0, -1, 7, 3)),
    "shrine_small": ([lambda: shrine(False, False), lambda: shrine(False, True)], 40, 44, 38, (0, -1, 14, 5)),
    "shrine_big": ([lambda: shrine(True, False), lambda: shrine(True, True)], 52, 60, 52, (0, -1, 19, 6)),
    "mound": ([mound], 32, 22, 16, (0, -1, 10, 3)),
    "twig": ([lambda v=v: twig(v, False) for v in range(3)] + [lambda v=v: twig(v, True) for v in range(3)], 18, 12, 8, (0, 0, 1, 1)),
}


def build_all():
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}  # keeps the keys of art_wisp.py and art_hoard.py
    previews = []
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (builders, FW, FH, GR, shadow) in SHEETS.items():
        frames = [c.pixels(b(), FW, FH, GR, shadow) for b in builders]
        if name == "twig":  # twigs carry no shadow of their own
            frames = [[[px if px[3] > 100 else (0, 0, 0, 0) for px in row] for row in f] for f in frames]
        sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
        write_png(OUT / f"{name}.png", FW * len(frames), FH, sheet)
        g = c.glow(sheet)
        if any(px[3] for row in g for px in row):
            write_png(OUT / f"{name}_glow.png", FW * len(frames), FH, g)
        data[name] = {"frame": [FW, FH], "ground": GR, "frames": len(frames)}
        previews.append((sheet, FW * len(frames), FH))
        for f in frames:
            for y in range(FH):
                if f[y][0][3] > 100 or f[y][FW - 1][3] > 100:
                    print(f"  WARNING {name}: pixel at a side border, row {y}")
                    break
            if any(px[3] > 100 for px in f[0]):
                print(f"  WARNING {name}: pixel at the top border")
    data["stele"]["rune"] = stele_rune_anchor()
    data["sundial"]["tip"] = c.screen((0, 16.4, -5.2), 40, 32)
    data["sundial"]["foot"] = c.screen((0, 6.2, 0), 40, 32)
    data["trial_stone"]["eye"] = c.screen((0, 9.0, 3.5), 28, 29)
    data["lantern_post"]["flame"] = c.screen((7.6, 21.8, 0), 32, 46)
    data["shrine_small"]["flame"] = c.screen((0, 6.6, 0.6), 40, 38)
    data["shrine_big"]["flame"] = c.screen((0, 6.6, 0.6), 52, 52)
    data["shrine_big"]["bell"] = c.screen((0, 18.0, -1.0), 52, 52)
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    RUNES_OUT.write_text(json.dumps({"order": RUNE_ORDER, "runes": RUNES}, indent="\t") + "\n", encoding="utf-8")
    return previews


if __name__ == "__main__":
    previews = build_all()
    print("puzzle props written:", ", ".join(SHEETS))
    if len(sys.argv) > 1:
        sc = 4
        bg = (58, 92, 66, 255)
        width = max(w for _, w, _ in previews) * sc
        big = []
        for sheet, w, hgt in previews:
            for row in sheet:
                line = []
                for px in row:
                    a = px[3] / 255.0
                    line += [tuple(int(px[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
                line += [bg] * (width - len(line))
                big += [line] * sc
            big += [[(30, 40, 34, 255)] * width] * 4
        write_png(pathlib.Path(sys.argv[1]), width, len(big), big)
