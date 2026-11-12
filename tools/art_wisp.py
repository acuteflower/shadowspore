"""The wisp's bowl (Irrlichtspur, docs/raetsel_konzept.md section 1): an old leaning pillar of the world's blue-violet rock with a shallow stone
bowl on top, a bed of luminous moss in it where the wisp sleeps, a spiral groove up the shaft, a carved flame sigil on the plinth, ivy and
dripping glow-moss off the rim, glow caps, ferns and pebbles at its foot. Rendered with the chests' renderer in its detail mode
(art_loot_chests.pixels_detail: dithered light, occlusion, weathered stone, lichen, catch-light).
    py -3 tools/art_wisp.py [preview.png]
Writes assets/props/puzzles/wisp_bowl.png (+ _glow): frame 0 = the wisp at home (the moss bed and the groove alight), frame 1 = it has gone
(cold groove, the bed grey and dry); data/puzzle_art.json key "wisp_bowl" (frame, ground, `nest` = where the wisp sits, px from the feet)."""
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
ASH, FERN = BASE, BASE + 1
h.RAMPS += [[hexc(x) for x in r] for r in (
    ["2a2632", "4a4554", "6e6878", "99929e"],  # cold ash in the empty bowl
    ["1c3d36", "2b5646", "4a7d58", "86b878"],  # fern fronds
)]
STONE, MOSS, TEAL, DARK = c.STONE, c.MOSS, h.TEAL, c.DARK
FW, FH, GR = 44, 52, 46
H_BOWL = 27.0  # height of the bowl's rim


def octagon(s, y, r, half_h, rot=0.0, seed=0.0, lean=None):
    for a in (rot, rot + math.pi / 4):
        R = h.rot_y(a) if lean is None else lean @ h.rot_y(a)
        s.box((0, y, 0), (r, half_h, r), STONE, R=R, kind="stone", seed=seed + a)


def build(lit):
    s = c.Scene()
    rng = np.random.default_rng(71)
    # --- the foot: moss mats, pebbles, ferns, a cluster of glow caps
    for (x, z, rx, rz) in ((-6.5, 4.0, 3.6, 2.0), (5.0, 5.5, 3.0, 1.8), (7.0, -3.0, 2.4, 2.0)):
        s.ell((x, 0.45, z), (rx, 0.6, rz), MOSS)
    for k in range(6):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(8.5, 11.0)
        s.ell((math.cos(a) * rr, 0.7, math.sin(a) * rr * 0.8), (rng.uniform(0.8, 1.5), rng.uniform(0.6, 1.0), rng.uniform(0.7, 1.3)), STONE, kind="stone")
    for (x, z, n) in ((-9.0, 2.0, 5), (8.5, 1.5, 4)):  # ferns: arching fronds with leaflets
        for k in range(n):
            a = -math.pi / 2 + (k - n / 2) * 0.55 + rng.uniform(-0.2, 0.2)
            tip = V(x + math.cos(a + math.pi / 2) * 4.2, 3.4 + rng.uniform(0, 1.6), z + math.sin(a + math.pi / 2) * 1.6)
            mid = (V(x, 0.3, z) + tip) / 2 + V(0, 1.6, 0)
            s.limb((x, 0.3, z), tuple(mid), 0.35, 0.3, FERN)
            s.limb(tuple(mid), tuple(tip), 0.3, 0.18, FERN)
            for j in range(3):
                p = V(x, 0.3, z) + (tip - V(x, 0.3, z)) * (0.35 + j * 0.2) + V(0, 1.0, 0)
                s.ell(tuple(p), (0.9, 0.3, 0.5), FERN, R=c.rz(a))
    for k, (x, z, hgt, r) in enumerate(((6.2, 4.6, 2.6, 1.5), (7.8, 3.4, 1.8, 1.1), (5.0, 6.0, 1.4, 0.9))):  # glow caps
        s.limb((x, 0.2, z), (x, hgt, z), 0.4, 0.35, c.WAX)
        s.ell((x, hgt + 0.3, z), (r, r * 0.55, r), TEAL, kind="emit" if lit or k == 0 else "")
    # --- the plinth: two octagonal steps, worn
    octagon(s, 1.5, 7.0, 1.5, 0.12, 1.0)
    octagon(s, 3.9, 5.4, 0.9, 0.5, 2.0)
    # a carved flame sigil on the plinth's front step
    for (x, y, w, hh) in ((0.0, 3.8, 0.35, 0.75), (-0.45, 3.6, 0.3, 0.4), (0.45, 3.5, 0.3, 0.35), (0.0, 4.65, 0.2, 0.3)):
        s.box((x, y, 5.15), (w, hh, 0.12), TEAL if lit else DARK, kind="emit" if lit else "")
    # --- the shaft: octagonal, leaning a little, a spiral groove up it
    lean = c.rz(0.05) @ c.rx(-0.03)
    octagon(s, 13.0, 2.6, 8.4, 0.0, 3.0, lean)
    for k in range(34):
        t = k / 33
        a = t * 2.4 * 2 * math.pi + 0.6
        p = lean @ V(math.cos(a) * 2.85, 5.6 + t * 15.0, math.sin(a) * 2.85)
        if math.sin(a) > -0.2:  # only the side we see
            s.ell(tuple(p), (0.42, 0.42, 0.42), TEAL if lit and k % 3 != 0 else DARK, kind="emit" if lit and k % 3 != 0 else "")
    # cracks and a chipped edge
    s.box((-1.6, 10.0, 2.55), (0.12, 2.4, 0.1), DARK, R=c.rz(0.3), kind="")
    s.box((1.1, 16.5, 2.6), (0.12, 1.4, 0.1), DARK, R=c.rz(-0.4), kind="")
    # --- the capital and the bowl
    top = lean @ V(0, 21.8, 0)
    octagon(s, top[1], 3.5, 0.9, 0.39, 4.0)
    s.ell((top[0], 23.6, 0), (3.0, 1.4, 3.0), STONE)
    s.ell((top[0], 25.2, 0), (6.6, 2.0, 6.6), STONE)
    for k in range(18):  # a heavy rolled rim
        a = k * 2 * math.pi / 18
        s.ell((top[0] + math.cos(a) * 6.0, H_BOWL - 0.2, math.sin(a) * 6.0), (1.35, 0.95, 1.35), STONE)
    s.ell((top[0], H_BOWL - 0.1, 0), (5.1, 0.45, 5.1), DARK)  # the hollow
    if lit:  # a bed of luminous moss, buds glowing in it
        s.ell((top[0], H_BOWL + 0.15, 0), (4.6, 0.55, 4.6), MOSS)
        for k in range(9):
            a = rng.uniform(0, 2 * math.pi)
            rr = rng.uniform(0.6, 3.8)
            s.ell((top[0] + math.cos(a) * rr, H_BOWL + 0.6, math.sin(a) * rr), (0.55, 0.4, 0.55), TEAL, kind="emit")
        s.ell((top[0], H_BOWL + 0.5, 0), (2.2, 0.35, 2.0), TEAL, kind="emit")  # the hollow it sleeps in
    else:  # cold ash and dry moss
        s.ell((top[0], H_BOWL + 0.05, 0), (4.4, 0.45, 4.4), ASH)
        for k in range(5):
            a = rng.uniform(0, 2 * math.pi)
            s.ell((top[0] + math.cos(a) * 3.0, H_BOWL + 0.4, math.sin(a) * 3.0), (0.9, 0.3, 0.7), FERN)
    # --- ivy down the shaft, glow-moss dripping off the rim
    pts = [V(top[0] - 4.8, H_BOWL - 0.6, 3.8)]
    for i in range(8):
        pts.append(pts[-1] + V(0.4 + math.sin(i * 1.3) * 0.7, -2.2, 0.15 - i * 0.05))
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        s.limb(tuple(a), tuple(b), 0.35, 0.3, MOSS)
        side = 1 if i % 2 else -1
        s.ell(tuple(b + V(side * 0.9, 0.3, 0.8)), (1.15, 0.4, 0.85), FERN, R=c.rx(0.6))
    for k, (a, ln) in enumerate(((0.9, 4.2), (1.9, 6.0), (2.6, 3.2), (-0.4, 5.0))):
        base = V(top[0] + math.cos(a) * 6.2, H_BOWL - 0.8, math.sin(a) * 6.2)
        tip = base + V(0.2, -ln, 0.3)
        s.limb(tuple(base), tuple(tip), 0.35, 0.22, MOSS)
        s.ell(tuple(tip + V(0, -0.4, 0)), (0.45, 0.6, 0.45), TEAL if lit else MOSS, kind="emit" if lit else "")
    # a few drifts of moss on the steps
    s.ell((-4.0, 3.2, 3.6), (2.4, 0.5, 1.4), MOSS)
    s.ell((3.6, 5.0, 2.2), (1.6, 0.4, 1.0), MOSS)
    return s


def nest():
    top = (c.rz(0.05) @ c.rx(-0.03)) @ V(0, 21.8, 0)
    return c.screen((top[0], H_BOWL + 1.2, 0), FW, GR)


if __name__ == "__main__":
    frames = [c.pixels_detail(build(lit), FW, FH, GR, (0, -1, 13, 4), stones=[STONE, ASH], woods=[], metals=[], lichen=MOSS, seed=4) for lit in (True, False)]
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / "wisp_bowl.png", FW * 2, FH, sheet)
    write_png(OUT / "wisp_bowl_glow.png", FW * 2, FH, c.glow(sheet))
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    data["wisp_bowl"] = {"frame": [FW, FH], "ground": GR, "frames": 2, "nest": nest()}
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    for f in frames:
        if any(px[3] > 100 for px in f[0]) or any(f[y][0][3] > 100 or f[y][FW - 1][3] > 100 for y in range(FH)):
            print("  WARNING: pixel at the border")
    print("wisp_bowl written, nest", nest())
    if len(sys.argv) > 1:
        sc = 7
        bg = (58, 92, 66, 255)
        big = []
        for row in sheet:
            line = []
            for px in row:
                a = px[3] / 255.0
                line += [tuple(int(px[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), FW * 2 * sc, FH * sc, big)
