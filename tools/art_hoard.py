"""The crow's hoard perches (Krähenschatz, docs/raetsel_konzept.md section 4): where the ringed hoard crow sits and keeps its finds. Four variants,
rendered with the chests' renderer in its detail mode (art_loot_chests.pixels_detail):
  0 lightning stump: a tall stump split by lightning, two jagged splinters, bark peeled off one side, a dark hollow full of glints, shelf fungi,
    a nest in the crook and a silver thread hanging down,
  1 ring stump: a low wide cut stump, a messy nest heaped with trinkets (a bent spoon, a key, buttons), pale caps at its foot,
  2 crooked stump: a leaning hollow stump with one bare branch the crow sits on, ivy, a glint in the root hollow,
  3 rock: a small boulder of the world's blue-violet stone with a crevice, a nest in the dip on top, lichen and pebbles.
    py -3 tools/art_hoard.py [preview.png]
Writes assets/props/puzzles/hoard_crow.png (+ _glow), frames of 52 x 64, feet at (26, 58), and the key "hoard_crow" of data/puzzle_art.json
(`perches` = where the crow sits per variant, px from the feet; `solid` = footprint per variant). Other keys of that file are kept."""
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
BASE = len(h.RAMPS)
_R = [
    ("DEADWOOD", ["3c3436", "625856", "8e8480", "bcb2aa"]),  # bleached wood under the bark
    ("NEST", ["3a2a22", "6a4e3a", "9c7a56", "d0aa7a"]),  # twigs and straw
    ("FUNGUS", ["2a3a4a", "3a6a72", "5ea8a2", "9ee8d6"]),  # shelf fungi (teal edges glow)
    ("LICHEN", ["3a4a3a", "5e7452", "8ea070", "c4cc96"]),
]
for i, (name, ramp) in enumerate(_R):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(x) for x in ramp] for _, ramp in _R]
BARK, STONE, MOSS, SILVER, DARK, WAX, CHAIN, COPPER, TEAL = c.BARK, c.STONE, c.MOSS, c.SILVER, c.DARK, c.WAX, c.CHAIN, c.COPPER, h.TEAL
FW, FH, GR = 52, 64, 58
h.SCALE *= 1.6  # bigger than the other puzzle props: the crow's home must read at a glance


def roots(s, rng, r, n, mat=None):
    mat = mat or BARK
    for k in range(n):
        a = k * 2 * math.pi / n + rng.uniform(-0.3, 0.3)
        s.limb((math.cos(a) * r * 0.7, 1.4, math.sin(a) * r * 0.6), (math.cos(a) * (r + 4.2), 0.3, math.sin(a) * (r + 3.0)), 1.3, 0.45, mat)


def trunk(s, base, top, r0, r1, mat, rough=0.0, seed=0):
    """A cut trunk with a flat top: a stack of flat discs from `base` to `top` (a limb of spheres would end in a dome)."""
    base, top = V(*base), V(*top)
    axis = top - base
    ln = float(np.linalg.norm(axis))
    up = axis / ln
    side = np.cross(up, V(0, 0, 1))
    side = side / max(np.linalg.norm(side), 1e-6)
    fwd = np.cross(side, up)
    R = np.stack([side, up, fwd], axis=1)
    rng = np.random.default_rng(seed)
    n = max(2, int(ln / 0.45))
    for i in range(n + 1):
        t = i / n
        r = r0 + (r1 - r0) * t + (rng.uniform(-rough, rough) if rough else 0.0)
        s.ell(tuple(base + axis * t), (r, 0.55, r * 0.92), mat, R=R)
    return R


def moss(s, rng, n, r):
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        s.ell((math.cos(a) * r * rng.uniform(0.7, 1.1), 0.5, math.sin(a) * r * 0.8), (rng.uniform(1.4, 2.4), 0.7, rng.uniform(1.0, 1.6)), MOSS)


def nest(s, rng, at, rad, n=16, trinkets=2):
    x, y, z = at
    s.ell((x, y + 0.3, z), (rad * 0.9, 0.7, rad * 0.8), NEST)
    for k in range(n):
        a = k * 2 * math.pi / n + rng.uniform(-0.2, 0.2)
        r = rad * rng.uniform(0.75, 1.1)
        s.limb((x + math.cos(a) * r, y + 0.9 + rng.uniform(-0.3, 0.5), z + math.sin(a) * r * 0.8),
               (x + math.cos(a + 1.0) * r * 1.15, y + 1.5 + rng.uniform(-0.2, 0.6), z + math.sin(a + 1.0) * r * 0.9), 0.32, 0.22, NEST)
    for k in range(trinkets):  # glints of its finds in the nest
        a = rng.uniform(0, 2 * math.pi)
        s.ell((x + math.cos(a) * rad * 0.4, y + 1.5, z + math.sin(a) * rad * 0.35 + 0.6), (0.55, 0.4, 0.5), SILVER, kind="emit")


def glints_in_grass(s, rng, n, r):
    for _ in range(n):
        a = rng.uniform(0.2, math.pi - 0.2)  # in front, where they are seen
        s.ell((math.cos(a) * r * rng.uniform(0.9, 1.3), 0.4, math.sin(a) * r * 0.7), (0.45, 0.3, 0.45), SILVER, kind="emit")


def lightning():
    s = c.Scene()
    rng = np.random.default_rng(51)
    H = 17.0
    roots(s, rng, 3.6, 5)
    s.ell((0, 1.6, 0), (5.0, 2.2, 4.4), BARK)
    trunk(s, (0, 0.6, 0), (0.4, H, -0.3), 4.2, 3.3, BARK, 0.25, 1)
    # the split: two jagged splinters behind, bleached wood where it tore
    s.limb((-1.8, H - 1.0, -0.8), (-3.0, H + 9.0, -1.6), 2.0, 0.25, DEADWOOD)
    s.limb((0.8, H - 1.0, -1.8), (1.8, H + 6.0, -2.6), 1.6, 0.2, DEADWOOD)
    s.limb((-0.4, H - 0.6, -1.4), (0.0, H + 4.0, -1.6), 1.0, 0.2, DEADWOOD)
    s.limb((2.6, H - 1.0, -0.6), (3.8, H + 2.6, -0.4), 0.9, 0.2, DEADWOOD)
    s.ell((0.6, H - 0.2, 0.4), (3.0, 0.8, 2.6), DEADWOOD)  # the torn top, the crook the nest sits in
    # bark peeled off the front-left: a pale stripe with grain
    s.ell((-1.9, H * 0.55, 3.0), (1.6, H * 0.36, 0.7), DEADWOOD, R=c.rz(0.08))
    # the hollow with its hoard
    s.ell((1.6, H * 0.42, 2.9), (1.3, 1.9, 0.7), DARK)
    for k in range(3):
        s.ell((1.2 + k * 0.5, H * 0.42 - 1.0 + k * 0.6, 3.3), (0.4, 0.35, 0.3), SILVER, kind="emit")
    # shelf fungi up the right side
    for (y, z, r) in ((H * 0.3, 1.0, 1.7), (H * 0.52, 0.4, 1.3), (H * 0.7, 1.2, 1.0)):
        s.ell((3.6, y, z), (r, 0.45, r * 0.9), FUNGUS)
        s.ell((3.6 + r * 0.7, y - 0.2, z + 0.3), (0.35, 0.3, 0.35), TEAL, kind="emit")
    nest(s, rng, (0.9, H + 0.1, 0.6), 2.6, 14, 2)
    # a silver thread hangs from the nest, a bead at its end
    s.limb((2.8, H + 0.6, 2.0), (3.4, H - 4.6, 2.4), 0.15, 0.15, CHAIN)
    s.ell((3.4, H - 5.0, 2.4), (0.45, 0.45, 0.45), SILVER, kind="emit")
    moss(s, rng, 4, 5.2)
    s.ell((-3.4, 6.0, 2.0), (1.2, 2.4, 0.6), MOSS)  # a beard of moss down the bark
    glints_in_grass(s, rng, 3, 8.0)
    return s, (0.9, H + 1.6, 0.6), (12, 6)


def ring():
    s = c.Scene()
    rng = np.random.default_rng(53)
    H = 8.0
    roots(s, rng, 5.4, 6)
    trunk(s, (0, 0.6, 0), (0, H, 0), 6.2, 5.6, BARK, 0.2, 2)
    s.ell((0, H + 0.2, 0), (5.4, 0.6, 5.0), DEADWOOD)  # the cut face
    s.ell((-1.6, H + 0.5, -1.2), (1.6, 0.3, 1.4), BARK)  # a dark heart crack in the rings
    nest(s, rng, (1.0, H + 0.4, 0.8), 3.4, 18, 3)
    # trinkets: a bent spoon, a key, a button
    s.limb((2.6, H + 1.6, 2.6), (5.0, H + 3.0, 3.4), 0.35, 0.3, CHAIN)
    s.ell((5.4, H + 3.2, 3.6), (0.8, 0.35, 0.6), SILVER, kind="emit")
    s.limb((-1.4, H + 1.6, 3.0), (-3.4, H + 2.0, 3.6), 0.3, 0.3, COPPER)
    s.ell((-3.8, H + 2.1, 3.7), (0.7, 0.6, 0.5), COPPER)
    s.ell((-0.6, H + 1.9, 2.2), (0.55, 0.4, 0.5), SILVER, kind="emit")
    # pale caps at its foot
    for (x, z, hh) in ((5.6, 4.2, 2.6), (6.6, 3.0, 1.8), (-6.0, 3.6, 2.0)):
        s.limb((x, 0.2, z), (x, hh, z), 0.35, 0.3, WAX)
        s.ell((x, hh + 0.2, z), (1.0, 0.55, 0.9), WAX)
    moss(s, rng, 4, 6.4)
    s.ell((-5.2, H * 0.6, 2.6), (1.0, 1.8, 0.6), MOSS)
    glints_in_grass(s, rng, 3, 9.5)
    return s, (1.0, H + 2.0, 0.8), (16, 7)


def crooked():
    s = c.Scene()
    rng = np.random.default_rng(57)
    H = 13.0
    lean = c.rz(-0.22)
    roots(s, rng, 3.4, 5)
    s.ell((0, 1.5, 0), (4.6, 2.0, 4.2), BARK)
    top = lean @ V(0, H, 0)
    trunk(s, (0, 0.6, 0), tuple(top), 3.8, 2.8, BARK, 0.25, 3)
    s.ell(tuple(top + V(0, 0.2, 0)), (2.4, 0.7, 2.2), DEADWOOD)
    for k in range(4):  # a ragged rim
        a = k * 1.7
        s.limb(tuple(top + V(math.cos(a) * 1.8, 0, math.sin(a) * 1.6)), tuple(top + V(math.cos(a) * 2.0, 1.4 + k * 0.4, math.sin(a) * 1.8)), 0.6, 0.2, DEADWOOD)
    # the bare branch the crow sits on, with a twig of a nest at its fork
    b0 = lean @ V(0, H * 0.72, 0)
    b1 = b0 + V(-6.6, 3.4, 1.2)
    b2 = b1 + V(-2.0, 2.4, 0.2)
    s.limb(tuple(b0), tuple(b1), 1.2, 0.7, BARK)
    s.limb(tuple(b1), tuple(b2), 0.7, 0.3, BARK)
    s.limb(tuple(b1 + V(0.4, 0, 0)), tuple(b1 + V(1.2, 2.6, 0.8)), 0.35, 0.2, BARK)
    nest(s, rng, tuple(b1 + V(0.6, -0.2, 0.2)), 1.5, 10, 1)
    # the root hollow with a glint
    s.ell((0.8, 2.6, 3.6), (1.6, 1.6, 0.6), DARK)
    s.ell((0.6, 2.0, 4.0), (0.45, 0.35, 0.3), SILVER, kind="emit")
    # ivy wound round it
    for k in range(9):
        a = k * 0.9
        p = lean @ V(math.cos(a) * 3.3, 2.0 + k * 1.2, math.sin(a) * 3.0 + 0.4)
        if math.sin(a) > -0.2:
            s.ell(tuple(p), (0.9, 0.5, 0.6), MOSS)
    s.ell((3.0, 4.0, 2.4), (1.1, 0.4, 1.0), FUNGUS)
    s.ell((3.7, 3.8, 2.8), (0.3, 0.3, 0.3), TEAL, kind="emit")
    moss(s, rng, 4, 5.0)
    glints_in_grass(s, rng, 3, 8.0)
    return s, tuple(b1 + V(0.6, 1.4, 0.2)), (12, 6)


def rock():
    s = c.Scene()
    rng = np.random.default_rng(59)
    s.box((0, 4.0, 0), (6.4, 4.0, 5.0), STONE, R=c.rz(0.05), kind="stone", seed=1.0)
    s.box((-2.0, 9.0, -0.6), (4.0, 2.6, 3.6), STONE, R=c.rz(-0.18) @ h.rot_y(0.3), kind="stone", seed=2.0)
    s.box((3.8, 8.0, -0.4), (2.6, 2.4, 3.0), STONE, R=c.rz(0.22) @ h.rot_y(-0.2), kind="stone", seed=3.0)
    s.box((5.8, 1.6, 3.6), (1.8, 1.6, 1.6), STONE, R=h.rot_y(0.6), kind="stone", seed=4.0)  # a chip at its foot
    s.ell((1.0, 6.0, 5.0), (0.5, 3.0, 0.4), DARK)  # the crevice
    s.ell((1.0, 4.0, 5.2), (0.4, 0.35, 0.3), SILVER, kind="emit")
    nest(s, rng, (1.0, 10.6, 0.2), 2.6, 14, 2)
    for (x, y, z, r) in ((-4.6, 7.0, 3.6, 1.4), (4.4, 5.0, 4.2, 1.0), (-1.2, 11.6, 2.4, 0.9)):  # lichen
        s.ell((x, y, z), (r, r * 0.8, 0.4), LICHEN)
    for k in range(5):  # pebbles round it
        a = rng.uniform(0, 2 * math.pi)
        s.ell((math.cos(a) * 9.0, 0.6, math.sin(a) * 6.5), (rng.uniform(0.7, 1.3), 0.6, rng.uniform(0.6, 1.1)), STONE, kind="stone")
    moss(s, rng, 3, 7.0)
    glints_in_grass(s, rng, 3, 9.0)
    return s, (1.0, 12.2, 0.2), (16, 7)


VARIANTS = [lightning, ring, crooked, rock]


if __name__ == "__main__":
    frames, perches, solids = [], [], []
    for build in VARIANTS:
        scene, perch, solid = build()
        frames.append(c.pixels_detail(scene, FW, FH, GR, (0, -1, 13, 4), stones=[STONE], woods=[BARK, DEADWOOD], metals=[CHAIN, COPPER], lichen=MOSS, seed=5))
        perches.append(c.screen(perch, FW, GR))
        solids.append(list(solid))
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / "hoard_crow.png", FW * len(frames), FH, sheet)
    write_png(OUT / "hoard_crow_glow.png", FW * len(frames), FH, c.glow(sheet))
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    data["hoard_crow"] = {"frame": [FW, FH], "ground": GR, "frames": len(frames), "perches": perches, "solid": solids}
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    for i, f in enumerate(frames):
        if any(px[3] > 100 for px in f[0]) or any(f[y][0][3] > 100 or f[y][FW - 1][3] > 100 for y in range(FH)):
            print("  WARNING: variant", i, "touches the border")
    print("hoard_crow written, perches", perches)
    if len(sys.argv) > 1:
        sc = 6
        bg = (58, 92, 66, 255)
        big = []
        for row in sheet:
            line = []
            for px in row:
                a = px[3] / 255.0
                line += [tuple(int(px[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), FW * len(frames) * sc, FH * sc, big)
