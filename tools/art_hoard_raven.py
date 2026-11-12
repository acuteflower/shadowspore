"""The raven's perches (Rabenhandel, docs/raetsel_konzept.md section 4, rare): taller, paler and older than the crow's stumps (tools/art_hoard.py,
whose renderer setup, ramps and helpers this script shares). Three variants:
  0 bleached tree: a twisted bone-pale trunk with a snapped crown, a long bare branch the raven sits on, a hollow full of glints, its finds hung on
    chains (a ring, a key), old-man's-beard lichen, stones in its roots, black feathers fallen at its foot,
  1 rock spire: four leaning blocks of the world's stone with a nest on top, a crack with a glint, lichen, a dead root climbing it, a ring on a chain,
  2 twin trunk: two bleached trunks leaning apart, the nest wedged in the fork, broken side branches, beard lichen, a hollow between the roots.
    py -3 tools/art_hoard_raven.py [preview.png]
Writes assets/props/puzzles/hoard_raven.png (+ _glow), frames of 64 x 84, feet at (32, 78), and the key "hoard_raven" of data/puzzle_art.json
(`perches`, `solid` per variant). Other keys are kept."""
import json
import math
import pathlib
import sys

import numpy as np

import art_hoard as a
from art_hoard import c, h, V, OUT, DATA, write_png, hexc

BASE = len(h.RAMPS)
_R = [
    ("BLEACH", ["332d3c", "615a6c", "9a92a4", "d6d0d8"]),  # the raven's bleached wood, a breath of violet in the shade
    ("GREYBEARD", ["4c5258", "707a7e", "9aa4a2", "c6ccc4"]),  # old-man's-beard lichen hanging off it
]
for i, (name, ramp) in enumerate(_R):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(x) for x in ramp] for _, ramp in _R]
STONE, SILVER, DARK, CHAIN, COPPER, LICHEN, MOSS = a.STONE, a.SILVER, a.DARK, a.CHAIN, a.COPPER, a.LICHEN, a.MOSS
FW, FH, GR = 64, 84, 78


def bend_trunk(s, pts, r0, r1, mat):
    total = len(pts) - 1
    for i, (p, q) in enumerate(zip(pts, pts[1:])):
        s.limb(tuple(p), tuple(q), r0 + (r1 - r0) * i / total, r0 + (r1 - r0) * (i + 1) / total, mat)


def beard(s, rng, at, n, ln):
    for _ in range(n):  # thin grey-green strands
        x = at[0] + rng.uniform(-1.4, 1.4)
        z = at[2] + rng.uniform(0.2, 1.4)
        l = ln * rng.uniform(0.6, 1.0)
        s.limb((x, at[1], z), (x + rng.uniform(-0.3, 0.3), at[1] - l, z + 0.2), 0.32, 0.18, GREYBEARD)


def trinket_chain(s, at, ln):
    x, y, z = at
    s.limb((x, y, z), (x + 0.2, y - ln, z + 0.3), 0.14, 0.14, CHAIN)
    s.ell((x + 0.2, y - ln - 0.5, z + 0.3), (0.7, 0.7, 0.3), SILVER, kind="emit")  # a ring on a chain


def fallen_feathers(s, rng, r):
    for _ in range(3):
        t = rng.uniform(0.3, 2.8)
        s.limb((math.cos(t) * r, 0.4, math.sin(t) * r * 0.75), (math.cos(t) * r + 1.8, 0.4, math.sin(t) * r * 0.75 + 0.6), 0.32, 0.18, CHAIN)


def bleach_tree():
    s = c.Scene()
    rng = np.random.default_rng(61)
    a.roots(s, rng, 2.6, 6, BLEACH)
    for (x, z) in ((-6.0, 3.0), (5.4, 4.0)):  # stones in its roots
        s.box((x, 1.0, z), (1.6, 1.1, 1.4), STONE, R=h.rot_y(x), kind="stone", seed=x)
    pts = [V(0, 0.6, 0), V(0.8, 8.0, 0.2), V(-0.6, 16.0, -0.2), V(0.6, 23.0, 0), V(-0.2, 28.0, -0.4)]
    bend_trunk(s, pts, 2.6, 1.2, BLEACH)
    for (y, sd) in ((5.0, 1), (12.0, -1), (19.0, 1)):  # knots
        s.ell((sd * 1.6, y, 1.0), (1.0, 1.2, 0.9), BLEACH)
    for p, q in ((V(-0.2, 28.0, -0.4), V(-1.0, 31.0, -0.6)), (V(0.2, 27.6, 0), V(1.0, 30.2, 0.4))):  # the snapped crown: splinters
        s.limb(tuple(p), tuple(q), 0.8, 0.15, BLEACH)
    b0, b1, b2 = V(0.4, 21.0, 0.2), V(8.0, 26.6, 1.0), V(13.0, 28.0, 1.2)  # the long bare branch the raven sits on
    s.limb(tuple(b0), tuple(b1), 0.9, 0.55, BLEACH)
    s.limb(tuple(b1), tuple(b2), 0.55, 0.3, BLEACH)
    s.limb(tuple(b1), tuple(b1 + V(0.6, 3.2, -0.4)), 0.4, 0.15, BLEACH)
    s.limb((-0.6, 14.0, 0), (-6.4, 18.0, 0.6), 0.8, 0.45, BLEACH)  # a lower branch, broken off short
    s.limb((-6.4, 18.0, 0.6), (-8.6, 17.2, 0.8), 0.45, 0.2, BLEACH)
    s.limb((0.8, 9.0, 0.4), (3.8, 10.6, 2.0), 0.7, 0.4, BLEACH)  # a stub
    s.ell((0.2, 11.6, 2.2), (1.0, 1.8, 0.6), DARK)  # the hollow, full of glints
    for k in range(3):
        s.ell((-0.2 + k * 0.4, 10.6 + k * 0.7, 2.7), (0.36, 0.3, 0.3), SILVER, kind="emit")
    trinket_chain(s, (-5.0, 17.4, 1.0), 3.4)  # its finds hung up
    s.limb((3.4, 10.2, 2.2), (3.6, 8.2, 2.4), 0.12, 0.12, CHAIN)
    s.ell((3.6, 7.8, 2.4), (0.45, 0.8, 0.3), COPPER)  # a key
    beard(s, rng, (-6.6, 17.8, 0.8), 4, 3.2)
    beard(s, rng, (7.6, 26.2, 1.2), 3, 2.6)
    beard(s, rng, (-1.0, 21.0, 2.0), 2, 3.0)
    fallen_feathers(s, rng, 6.5)
    a.moss(s, rng, 3, 5.4)
    a.glints_in_grass(s, rng, 3, 9.0)
    return s, tuple(b2 + V(-1.4, 0.8, 0)), (10, 6)


def spire():
    s = c.Scene()
    rng = np.random.default_rng(63)
    blocks = [((0, 4.0, 0), (5.6, 4.0, 4.6), 0.05, 0.1), ((0.6, 11.5, -0.2), (4.2, 3.6, 3.6), -0.08, 0.5),
              ((-0.2, 18.4, 0.2), (3.2, 3.4, 2.8), 0.1, 0.9), ((0.4, 24.4, 0), (2.4, 2.8, 2.2), -0.12, 1.4)]
    for k, (cc, e, lean, yaw) in enumerate(blocks):
        s.box(cc, e, STONE, R=c.rz(lean) @ h.rot_y(yaw), kind="stone", seed=float(k))
    s.box((5.0, 1.6, 3.6), (2.0, 1.6, 1.8), STONE, R=h.rot_y(0.7), kind="stone", seed=7.0)
    s.box((-5.4, 1.2, 2.8), (1.4, 1.2, 1.2), STONE, R=h.rot_y(-0.4), kind="stone", seed=8.0)
    s.ell((1.4, 12.0, 3.7), (0.45, 3.0, 0.4), DARK)  # a crack running up
    s.ell((1.4, 10.6, 3.9), (0.35, 0.3, 0.3), SILVER, kind="emit")
    pts = [V(-5.0, 0.4, 2.4), V(-4.2, 6.0, 3.6), V(-3.2, 12.0, 3.0), V(-2.4, 18.0, 2.6), V(-1.2, 23.0, 2.0)]  # a dead root climbing it
    bend_trunk(s, pts, 0.8, 0.45, BLEACH)
    a.nest(s, rng, (0.4, 27.2, 0), 2.8, 16, 2)
    for (x, y, z, r) in ((-3.6, 6.0, 4.2, 1.5), (3.4, 14.0, 3.2, 1.1), (-2.2, 20.0, 2.6, 0.9), (2.4, 4.0, 4.4, 1.2)):
        s.ell((x, y, z), (r, r * 0.8, 0.4), LICHEN)
    beard(s, rng, (-1.6, 22.6, 2.2), 3, 3.0)
    trinket_chain(s, (2.6, 27.4, 1.6), 3.0)
    for _ in range(5):
        t = rng.uniform(0, 2 * math.pi)
        s.ell((math.cos(t) * 8.5, 0.6, math.sin(t) * 6.0), (rng.uniform(0.7, 1.3), 0.6, rng.uniform(0.6, 1.1)), STONE, kind="stone")
    fallen_feathers(s, rng, 7.0)
    a.moss(s, rng, 3, 6.4)
    a.glints_in_grass(s, rng, 3, 9.0)
    return s, (0.4, 29.0, 0), (14, 8)


def twin():
    s = c.Scene()
    rng = np.random.default_rng(67)
    a.roots(s, rng, 3.0, 7, BLEACH)
    s.ell((0, 1.4, 0), (4.0, 1.8, 3.4), BLEACH)
    left = [V(-0.8, 1.0, 0), V(-2.6, 9.0, 0.2), V(-5.0, 17.0, -0.2), V(-6.4, 23.0, -0.4)]
    right = [V(0.8, 1.0, 0), V(2.4, 8.0, -0.2), V(4.0, 15.0, 0.2), V(4.8, 20.0, 0)]
    bend_trunk(s, left, 1.9, 0.9, BLEACH)
    bend_trunk(s, right, 1.8, 0.85, BLEACH)
    s.limb(tuple(left[-1]), tuple(left[-1] + V(-0.6, 2.4, 0)), 0.8, 0.15, BLEACH)  # snapped tops
    s.limb(tuple(right[-1]), tuple(right[-1] + V(0.8, 2.0, 0.2)), 0.7, 0.15, BLEACH)
    s.limb((-5.0, 17.0, -0.2), (-9.4, 19.6, 0.6), 0.55, 0.25, BLEACH)
    s.limb((4.0, 15.0, 0.2), (8.8, 17.0, 0.6), 0.5, 0.25, BLEACH)
    a.nest(s, rng, (0.0, 7.8, 0.6), 2.6, 18, 3)  # wedged in the fork
    s.ell((0.0, 3.2, 3.6), (1.4, 1.6, 0.6), DARK)  # a hollow between the roots
    s.ell((0.2, 2.8, 4.0), (0.4, 0.3, 0.3), SILVER, kind="emit")
    trinket_chain(s, (-8.0, 19.2, 0.6), 3.6)
    beard(s, rng, (7.0, 16.6, 0.6), 3, 3.0)
    beard(s, rng, (-3.4, 13.0, 1.0), 3, 3.4)
    fallen_feathers(s, rng, 7.0)
    a.moss(s, rng, 4, 6.0)
    a.glints_in_grass(s, rng, 3, 9.5)
    return s, (0.0, 9.6, 0.6), (14, 7)


VARIANTS = [bleach_tree, spire, twin]


if __name__ == "__main__":
    frames, perches, solids = [], [], []
    for build in VARIANTS:
        scene, perch, solid = build()
        frames.append(c.pixels_detail(scene, FW, FH, GR, (0, -1, 15, 5), stones=[STONE], woods=[a.BARK, a.DEADWOOD, BLEACH], metals=[CHAIN, COPPER], lichen=MOSS, seed=5))
        perches.append(c.screen(perch, FW, GR))
        solids.append(list(solid))
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / "hoard_raven.png", FW * len(frames), FH, sheet)
    write_png(OUT / "hoard_raven_glow.png", FW * len(frames), FH, c.glow(sheet))
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    data["hoard_raven"] = {"frame": [FW, FH], "ground": GR, "frames": len(frames), "perches": perches, "solid": solids}
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    for i, f in enumerate(frames):
        if any(px[3] > 100 for px in f[0]) or any(f[y][0][3] > 100 or f[y][FW - 1][3] > 100 for y in range(FH)):
            print("  WARNING: variant", i, "touches the border")
    print("hoard_raven written, perches", perches)
    if len(sys.argv) > 1:
        sc = 5
        bg = (58, 92, 66, 255)
        big = []
        for row in sheet:
            line = []
            for px in row:
                al = px[3] / 255.0
                line += [tuple(int(px[i] * al + bg[i] * (1 - al)) for i in range(3)) + (255,)] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), FW * len(frames) * sc, FH * sc, big)
