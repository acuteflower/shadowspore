"""The star mirror (Sternenspiegel, docs/raetsel_konzept.md 6b): the rim of the still pond, the moonstones and the four corner stones of the star field.
Same renderer as the root weave and the crow's hoard (art_loot_chests.pixels_detail), the Wächterin's pale violet stone, but seen without the chests'
yaw (the pond is round on the ground). The water itself, the reflection and the light lines are drawn by the game.
    py -3 tools/art_star_mirror.py [preview.png]
Writes
  assets/props/puzzles/star_pond.png (+ _glow): the rim (stones, reeds, moss, glow caps) round an empty oval, feet = the pond's centre,
  assets/props/puzzles/moonstones.png (+ _glow): frames of 28 x 24, feet (14, 19), columns = 4 shapes, rows = dim, lit (on its star),
  assets/props/puzzles/star_corner.png (+ _glow): frames of 22 x 34, feet (11, 28), columns = dim, lit,
and the key "star_mirror" of data/puzzle_art.json (frames, ground rows, the water oval in px, the corner stone's rune place) - other keys kept."""
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
V = c.V
c.YAW = 0.0
BASE = len(h.RAMPS)
_R = [
    ("PALE", ["2c2844", "565078", "8880a8", "c0b8da"]),
    ("MOONST", ["3a3858", "6a6890", "a6a4c8", "e2e0f4"]),  # the moonstones (the same ramp as player_carry_stone.png)
    ("REED", ["1e2a22", "35503a", "5a7a4a", "93a86a"]),
    ("EARTH", ["1c1410", "38281e", "584030", "7c6048"]),
]
for i, (name, ramp) in enumerate(_R):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(x) for x in ramp] for _, ramp in _R]
TEAL, MOSS, STONE = h.TEAL, c.MOSS, c.STONE
c.EMISSIVE.update({TEAL: 1})
S = h.SCALE
# the water oval on the screen, px
WRX, WRY = 62, 30
PW, PH, PG = 160, 92, 50  # the pond picture: its feet (the water's centre) at (80, 50)


def to_model_ground(sx, sy):
    """Screen px on the ground (from the feet) -> model (x, z)."""
    return sx / S, sy / (S * h.SINP)


def pond():
    s = c.Scene()
    rng = np.random.default_rng(83)
    n = 52
    for k in range(n):  # a ring of rounded stones round the water, bigger at the back, smaller in front
        a = k * 2 * math.pi / n + rng.uniform(-0.05, 0.05)
        ex, ey = math.cos(a) * (WRX + 3), math.sin(a) * (WRY + 2)
        mx, mz = to_model_ground(ex, ey)
        r = rng.uniform(3.4, 4.8) * (1.15 if math.sin(a) < 0 else 0.8)
        s.ell((mx, r * 0.45, mz), (r * 1.2, r * 0.75, r), PALE if k % 3 else STONE)
        mx2, mz2 = to_model_ground(math.cos(a) * (WRX + 8), math.sin(a) * (WRY + 6))
        s.ell((mx2, 0.4, mz2), (r * 1.4, 0.8, r * 1.1), EARTH if k % 4 else MOSS)  # a bank of earth and moss behind the stones
        if rng.random() < 0.45:
            s.ell((mx + rng.uniform(-1, 1), r * 0.85, mz), (r * 0.8, 0.4, r * 0.6), MOSS)
    for k in range(14):  # reeds in tufts at the back and the sides
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95) if k < 9 else rng.uniform(-0.3, 0.3) + (0 if k % 2 else math.pi)
        ex, ey = math.cos(a) * (WRX + 7), math.sin(a) * (WRY + 5)
        mx, mz = to_model_ground(ex, ey)
        for j in range(5):
            dx = rng.uniform(-1.6, 1.6)
            hgt = rng.uniform(9, 16)
            lean = rng.uniform(-0.25, 0.25)
            s.limb((mx + dx, 0.3, mz), (mx + dx + lean * hgt, hgt, mz - 0.5), 0.45, 0.2, REED)
        if k % 3 == 0:
            s.ell((mx + 0.8, 14.0, mz - 0.4), (0.6, 1.8, 0.6), EARTH)  # a cattail head
    for k in range(4):  # glow caps between the stones
        a = [3.6, 4.4, 5.6, 0.6][k]
        ex, ey = math.cos(a) * (WRX + 9), math.sin(a) * (WRY + 7)
        mx, mz = to_model_ground(ex, ey)
        s.limb((mx, 0.2, mz), (mx, 1.8, mz), 0.35, 0.3, c.WAX)
        s.ell((mx, 2.4, mz), (1.6, 0.7, 1.4), PALE)
        s.ell((mx, 2.9, mz + 0.6), (0.8, 0.4, 0.6), TEAL, kind="emit")
    return s


def moonstone(shape, lit):
    s = c.Scene()
    rng = np.random.default_rng(91 + shape)
    r = 4.2
    squash = [(1.0, 0.78, 0.9), (1.15, 0.7, 0.85), (0.9, 0.85, 0.95), (1.05, 0.66, 1.0)][shape]
    s.ell((0, r * squash[1] * 0.9, 0), (r * squash[0], r * squash[1], r * squash[2]), MOONST)
    s.ell((r * 0.5, r * 1.2, r * 0.3), (r * 0.45, r * 0.3, r * 0.4), MOONST)  # a bump
    fleck = TEAL if lit else STONE
    s.ell((0.6, r * squash[1] * 1.45, r * 0.55), (r * 0.32, r * 0.2, r * 0.3), fleck, kind="emit" if lit else "")
    for k in range(2 + int(lit) * 2):  # veins across its face
        a = rng.uniform(-0.6, 0.6)
        s.limb((-r * 0.7, r * 0.7 + k * 0.6, r * 0.75), (r * 0.6, r * 0.9 + k * 0.4 + a, r * 0.8), 0.26 if lit else 0.18, 0.22 if lit else 0.15, TEAL if lit else c.DARK, kind="emit" if lit else "")
    return s


def corner(lit):
    s = c.Scene()
    s.box((0, 1.0, 0), (3.6, 1.0, 3.0), PALE, kind="stone", seed=0.2)
    s.box((0, 7.5, 0), (2.6, 5.6, 1.6), PALE, R=c.rz(0.04), kind="stone", seed=1.3)
    s.ell((0.2, 13.4, 0), (2.5, 1.3, 1.6), PALE)
    s.ell((0, 7.5, 1.7), (1.6, 1.8, 0.2), c.DARK if not lit else TEAL, kind="emit" if lit else "")  # the rune plate (the rune itself is drawn by the game)
    s.ell((-2.4, 0.6, 1.6), (1.4, 0.5, 1.0), MOSS)
    return s


def big_preview(sheets, path):
    sc = 5
    bg = (38, 62, 52, 255)
    W = max(len(r[0]) for r in sheets)
    canvas = []
    for sheet in sheets:
        canvas += [row + [(0, 0, 0, 0)] * (W - len(row)) for row in sheet] + [[(0, 0, 0, 0)] * W] * 3
    out = []
    for row in canvas:
        line = []
        for px in row:
            a = px[3] / 255.0
            line += [tuple(int(px[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
        out += [line] * sc
    write_png(pathlib.Path(path), W * sc, len(canvas) * sc, out)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    pond_px = c.pixels_detail(pond(), PW, PH, PG, (0, 0, 1, 1), stones=[PALE, STONE], woods=[REED], lichen=MOSS, seed=21)
    pond_px = [[px if px[3] > 100 else (0, 0, 0, 0) for px in row] for row in pond_px]  # no ground shadow: the water lies there
    write_png(OUT / "star_pond.png", PW, PH, pond_px)
    write_png(OUT / "star_pond_glow.png", PW, PH, c.glow(pond_px))
    MW, MH, MG = 28, 24, 19
    stones = [[c.pixels_detail(moonstone(k, lit), MW, MH, MG, (0, -1, 6, 2), stones=[MOONST], seed=5) for k in range(4)] for lit in (False, True)]
    msheet = []
    for row in stones:
        for y in range(MH):
            msheet.append(sum((f[y] for f in row), []))
    write_png(OUT / "moonstones.png", MW * 4, MH * 2, msheet)
    write_png(OUT / "moonstones_glow.png", MW * 4, MH * 2, c.glow(msheet))
    CW, CH, CG = 22, 34, 28
    cf = [c.pixels_detail(corner(lit), CW, CH, CG, (0, -1, 6, 2), stones=[PALE], lichen=MOSS, seed=7) for lit in (False, True)]
    csheet = [sum((f[y] for f in cf), []) for y in range(CH)]
    write_png(OUT / "star_corner.png", CW * 2, CH, csheet)
    write_png(OUT / "star_corner_glow.png", CW * 2, CH, c.glow(csheet))
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    data["star_mirror"] = {"pond_frame": [PW, PH], "pond_ground": PG, "water": [WRX, WRY],
                           "stone_frame": [MW, MH], "stone_ground": MG, "stone_shapes": 4,
                           "corner_frame": [CW, CH], "corner_ground": CG, "corner_rune": c.screen((0, 7.5, 1.9), CW, CG)}
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    print("star mirror art written; corner rune", data["star_mirror"]["corner_rune"])
    if len(sys.argv) > 1:
        big_preview([pond_px, msheet, csheet], sys.argv[1])
