"""The root weave (Wurzelgeflecht, docs/raetsel_konzept.md section 6a): the half-buried cubes of the Wächterin's pale violet stone.
Same renderer as the crow's hoard (art_loot_chests.pixels_detail: oriented boxes + ellipsoids, light from the top left, ink outline).
    py -3 tools/art_root_weave.py [preview.png]
Writes
  assets/props/puzzles/weave_cubes.png (+ _glow): frames of 40 x 44, feet at (20, 36); rows = ROWS (cube variants, seed closed/open, thorn
    variants), columns = dark (asleep), lit (teal inlay), gold (solved),
  assets/props/puzzles/weave_heart.png (+ _glow): frames of 60 x 66, feet at (30, 54); columns = HEART (heart lit, heart dark, heart gold and
    upright, crown closed, crown in bloom),
and the key "weave" of data/puzzle_art.json (frames, ground rows, the rune's place on each row's front face, the heart's eye) - other keys kept.
The runes themselves are not baked: the game draws the trial runes (data/puzzle_runes.json) on the front face, so one sheet serves six runes."""
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
    ("PALE", ["2c2844", "565078", "8880a8", "c0b8da"]),  # the waystones' pale violet stone
    ("EARTH", ["1c1410", "38281e", "584030", "7c6048"]),
    ("GROOVE", ["07050c", "0f0a1a", "181129", "261c3e"]),  # carved, asleep inlay
    ("THORN", ["040208", "0c0814", "1c1430", "3a2c5c"]),  # the void's black thorns, a cold violet rim
    ("PETAL", ["2a1d56", "4a3796", "7a64c8", "b4a2f0"]),  # a closed bud of crystal petals
]
for i, (name, ramp) in enumerate(_R):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(x) for x in ramp] for _, ramp in _R]
TEAL, AMBER, VIOLET, MOSS, BARK, STONE = h.TEAL, c.AMBER, h.VIOLET, c.MOSS, c.BARK, c.STONE
c.EMISSIVE.update({TEAL: 1, AMBER: 1, VIOLET: 1})

FW, FH, GR = 40, 44, 36
HW, HH, HG = 60, 66, 54
h.SCALE *= 2.0  # the cubes must read at a glance: a cube is about one tile wide
STATES = ["dark", "lit", "gold"]
ROWS = ["cube0", "cube1", "cube2", "seed", "seed_open", "thorn0", "thorn1"]
HEART = ["heart_lit", "heart_dark", "heart_gold", "crown", "crown_open"]


def inlay_mat(state):
    return {"dark": GROOVE, "lit": TEAL, "gold": AMBER}[state]


def inlay_kind(state):
    return "" if state == "dark" else "emit"


def mound(s, rng, r, n_roots=5, earth=True):
    """The heap of torn earth and root stubs the cube broke out of."""
    if earth:
        for k in range(7):
            a = k * 2 * math.pi / 7 + rng.uniform(-0.25, 0.25)
            d = r * rng.uniform(0.75, 1.05)
            s.ell((math.cos(a) * d, 0.5, math.sin(a) * d * 0.85), (rng.uniform(1.5, 2.4), rng.uniform(0.7, 1.2), rng.uniform(1.2, 1.9)), EARTH)
    for k in range(n_roots):
        a = k * 2 * math.pi / n_roots + rng.uniform(-0.4, 0.4)
        s.limb((math.cos(a) * r * 0.55, 1.6, math.sin(a) * r * 0.5), (math.cos(a) * (r + 2.6), 0.2, math.sin(a) * (r + 2.0)), 0.9, 0.35, BARK)
    for k in range(3):  # crumbs of earth thrown up
        a = rng.uniform(0.3, math.pi - 0.3)
        s.ell((math.cos(a) * (r + 3.0), 0.35, math.sin(a) * (r + 1.6)), (0.6, 0.4, 0.5), EARTH)


def cube_frame(e, cy, R):
    """A transform helper: a point in the cube's own frame (unit = model) -> scene point."""
    return lambda p: tuple(V(0, cy, 0) + R @ V(*p))


def inlays(s, at, R, e, state, top=True, side=True, ring=True):
    """Teal (or carved, or gold) lines let into the stone: a square ring round the rune on the front, a cross of veins on the top and a forked
    vein down the left side."""
    m, k = inlay_mat(state), inlay_kind(state)
    t = 0.32
    if ring:
        q = e * 0.66
        for (cx, cy, ex, ey) in ((0, q, q, t), (0, -q, q, t), (q, 0, t, q), (-q, 0, t, q)):
            s.box(at((cx, cy, e + 0.05)), (ex, ey, 0.2), m, R=R, kind=k)
    if top:
        for a in (0.0, math.pi / 2):
            d = V(math.cos(a), 0, math.sin(a))
            s.box(at(tuple(V(0, e + 0.05, 0))), (e * 0.62 if a == 0 else t, 0.2, t if a == 0 else e * 0.62), m, R=R, kind=k)
        s.box(at((0, e + 0.08, 0)), (0.7, 0.24, 0.7), m, R=R, kind=k)
    if side:
        s.box(at((-e - 0.05, e * 0.2, e * 0.1)), (0.2, e * 0.55, t), m, R=R, kind=k)
        s.box(at((-e - 0.05, -e * 0.35, e * 0.45)), (0.2, t, e * 0.42), m, R=R, kind=k)
        s.box(at((-e - 0.05, -e * 0.62, -e * 0.2)), (0.2, e * 0.25, t), m, R=R, kind=k)


def moss_cap(s, rng, at, R, e, n):
    for _ in range(n):
        x, z = rng.uniform(-e * 0.9, e * 0.9), rng.uniform(-e * 0.9, -e * 0.1)
        s.ell(at((x, e + 0.25, z)), (rng.uniform(0.9, 1.6), 0.45, rng.uniform(0.7, 1.2)), MOSS)
    for _ in range(2):  # a beard hanging down the left side
        y = rng.uniform(-e * 0.5, e * 0.6)
        s.ell(at((-e - 0.1, y, rng.uniform(-e * 0.6, e * 0.2))), (0.4, rng.uniform(0.9, 1.6), 0.7), MOSS)


def cube(variant, state, kind="cube", open_=False):
    s = c.Scene()
    rng = np.random.default_rng(31 + variant * 7)
    e = 4.0
    tilt = [(0.06, 0.22, 0.04), (-0.08, -0.18, 0.07), (0.11, 0.05, -0.05)][variant % 3]
    R = c.rz(tilt[0]) @ h.rot_y(tilt[1]) @ c.rx(tilt[2])
    cy = e * 0.78  # sunk: about a fifth of it under the ground
    at = cube_frame(e, cy, R)
    mound(s, np.random.default_rng(41 + variant), 5.6)
    s.box((0, cy, 0), (e, e, e), PALE, R=R, kind="stone", seed=0.4 + variant)
    # weathering: a few pale chips and a darker scar
    s.box(at((e * 0.55, e * 0.98, e * 0.6)), (1.1, 0.35, 0.9), PALE, R=R @ h.rot_y(0.5), kind="stone", seed=2.0)
    s.ell(at((e * 0.4, -e * 0.4, e + 0.02)), (0.9, 0.5, 0.15), STONE)
    inlays(s, at, R, e, state, top=kind != "thorn")
    if kind != "thorn":
        moss_cap(s, rng, at, R, e, 3 if variant != 1 else 5)
    if kind == "seed":
        bud(s, at, e, state, open_)
    if kind == "thorn":
        thorns(s, rng, at, e, variant)
    return s


def bud(s, at, e, state, open_):
    """The seed's bud on the top face: a closed knot of crystal petals, or a bloom whose heart glows when the cube is lit."""
    base = V(*at((0, e + 0.4, 0)))
    s.ell(tuple(base), (2.0, 0.7, 1.8), BARK)
    n = 7
    for k in range(n):
        a = k * 2 * math.pi / n + 0.3
        if open_:
            d = V(math.cos(a) * 1.0, 0.55, math.sin(a) * 0.9)
            ln = 3.6
        else:
            d = V(math.cos(a) * 0.3, 1.0, math.sin(a) * 0.27)
            ln = 3.4
        d = d / np.linalg.norm(d)
        mid = base + d * ln * 0.55 + V(0, 0.3, 0)
        s.ell(tuple(mid), (1.0, ln * 0.55, 0.6), PETAL, R=h.frame_from(d, V(0, 0, 1)))
    heart = {"dark": GROOVE, "lit": TEAL, "gold": AMBER}[state]
    if open_:
        s.ell(tuple(base + V(0, 1.1, 0)), (1.3, 0.9, 1.2), heart, kind=inlay_kind(state))
    else:
        s.ell(tuple(base + V(0, 4.3, 0)), (0.7, 0.8, 0.6), heart if state != "dark" else PETAL, kind=inlay_kind(state))


def thorns(s, rng, at, e, variant):
    """Black thorn tendrils of the void wound round the cube (glossy, a cold violet rim), long spikes outwards."""
    for w in range(2):
        prev = None
        for k in range(14):
            a = k * 0.62 + w * math.pi + variant * 0.7
            y = -e * 0.95 + k * (e * 2.05 / 13.0)
            r = e * 1.3
            p = V(*at((math.cos(a) * r, y, math.sin(a) * r)))
            if prev is not None:
                s.limb(tuple(prev), tuple(p), 0.6, 0.55, THORN)
            if k % 2 == 1:
                out = V(math.cos(a), 0.25, math.sin(a))
                s.limb(tuple(p), tuple(p + out * 2.4), 0.5, 0.1, THORN)
            prev = p
    for k in range(4):  # tendrils gripping the ground
        a = k * 1.6 + variant
        s.limb(at((math.cos(a) * e * 1.4, -e * 0.7, math.sin(a) * e * 1.4)), (math.cos(a) * (e + 5.0), 0.2, math.sin(a) * (e + 3.6)), 0.8, 0.25, THORN)


def heart(state):
    s = c.Scene()
    rng = np.random.default_rng(73)
    e = 5.2
    upright = state == "gold"
    R = np.eye(3) if upright else c.rz(0.3) @ h.rot_y(0.2) @ c.rx(0.16)
    cy = e * (0.95 if upright else 0.55)  # half swallowed by the earth until the weave is solved
    at = cube_frame(e, cy, R)
    mound(s, rng, 8.2, 8, earth=True)
    for k in range(4):  # thick roots clutch it
        a = k * 1.6 + 0.4
        s.limb((math.cos(a) * 7.0, 0.4, math.sin(a) * 6.0), at((math.cos(a) * e * 0.9, -e * 0.2, math.sin(a) * e * 0.9)), 1.3, 0.8, BARK)
    s.box((0, cy, 0), (e, e, e), PALE, R=R, kind="stone", seed=1.7)
    st = {"heart_lit": "lit", "heart_dark": "dark", "heart_gold": "gold"}[{"lit": "heart_lit", "dark": "heart_dark", "gold": "heart_gold"}[state]]
    inlays(s, at, R, e, st, top=False)
    # the eye on its top face: an almond socket with a glowing iris (closed: a dark slit)
    s.ell(at((0, e + 0.15, 0.6)), (3.2, 0.5, 1.9), GROOVE)
    if state == "dark":
        s.ell(at((0, e + 0.45, 0.6)), (2.9, 0.3, 0.45), PALE)
    else:
        s.ell(at((0, e + 0.5, 0.6)), (1.6, 0.4, 1.3), TEAL if state == "lit" else AMBER, kind="emit")
        s.ell(at((0, e + 0.75, 0.6)), (0.55, 0.3, 0.9), GROOVE)
    for k in range(4):  # veins running out of the eye over the top
        a = k * math.pi / 2 + 0.6
        s.box(at((math.cos(a) * e * 0.55, e + 0.05, math.sin(a) * e * 0.55)), (e * 0.32, 0.18, 0.3), inlay_mat(st), R=R @ h.rot_y(-a), kind=inlay_kind(st))
    if not upright:
        for _ in range(3):  # moss on the back half only: the eye stays clear
            s.ell(at((rng.uniform(-e * 0.8, e * 0.8), e + 0.3, rng.uniform(-e * 0.95, -e * 0.55))), (1.4, 0.45, 0.9), MOSS)
        s.ell(at((-e - 0.1, 0.0, 0.0)), (0.45, 2.0, 1.0), MOSS)
    else:
        for k in range(5):  # the moss it shook off lies round its foot
            a = rng.uniform(0.2, math.pi - 0.2)
            s.ell((math.cos(a) * (e + 2.2), 0.4, math.sin(a) * (e + 1.4)), (1.2, 0.4, 0.9), MOSS)
    return s, at((0, e + 0.4, 0.4)), at((0, 0, e))


def crown(open_):
    s = c.Scene()
    rng = np.random.default_rng(79)
    e = 4.6
    R = c.rz(-0.05) @ h.rot_y(-0.15)
    cy = e * 0.8
    at = cube_frame(e, cy, R)
    mound(s, rng, 6.6, 6)
    s.box((0, cy, 0), (e, e, e), PALE, R=R, kind="stone", seed=2.9)
    inlays(s, at, R, e, "gold" if open_ else "dark", top=False)
    base = V(*at((0, e + 0.2, 0)))
    n = 8
    for k in range(n):  # a crown of crystal petals: shut and dull, or opened golden
        a = k * 2 * math.pi / n
        d = V(math.cos(a) * (0.9 if open_ else 0.25), 1.0 if not open_ else 0.7, math.sin(a) * (0.8 if open_ else 0.22))
        d = d / np.linalg.norm(d)
        ln = 3.4 if k % 2 == 0 else 2.6
        s.ell(tuple(base + d * ln * 0.55), (0.8, ln * 0.55, 0.5), PETAL if not open_ else VIOLET, R=h.frame_from(d, V(0, 0, 1)), kind="" if not open_ else "emit")
    s.ell(tuple(base + V(0, 1.2 if open_ else 3.4, 0)), (1.2, 0.9, 1.1) if open_ else (0.6, 0.6, 0.5), AMBER if open_ else GROOVE, kind="emit" if open_ else "")
    moss_cap(s, rng, at, R, e, 3)
    return s, at((0, e + 1.4, 0))


def render_small(scene):
    return c.pixels_detail(scene, FW, FH, GR, (0, -1, 15, 5), stones=[PALE, STONE], woods=[BARK], metals=[], lichen=MOSS, seed=9)


def render_big(scene):
    return c.pixels_detail(scene, HW, HH, HG, (0, -1, 22, 7), stones=[PALE, STONE], woods=[BARK], metals=[], lichen=MOSS, seed=13)


def rune_anchor(variant):
    e = 4.0
    tilt = [(0.06, 0.22, 0.04), (-0.08, -0.18, 0.07), (0.11, 0.05, -0.05)][variant % 3]
    R = c.rz(tilt[0]) @ h.rot_y(tilt[1]) @ c.rx(tilt[2])
    p = V(0, e * 0.78, 0) + R @ V(0, 0, e + 0.2)
    return c.screen(tuple(p), FW, GR)


def check_border(frames, w, hh, name):
    for i, f in enumerate(frames):
        if any(px[3] > 100 for px in f[0]) or any(f[y][0][3] > 100 or f[y][w - 1][3] > 100 for y in range(hh)):
            print("  WARNING:", name, "frame", i, "touches the border")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    anchors = []
    for name in ROWS:
        kind = "seed" if name.startswith("seed") else "thorn" if name.startswith("thorn") else "cube"
        variant = int(name[-1]) if name[-1].isdigit() else 0
        frames = [render_small(cube(variant, st, kind, name == "seed_open")) for st in STATES]
        check_border(frames, FW, FH, name)
        rows.append(frames)
        anchors.append(rune_anchor(variant))
    sheet = []
    for frames in rows:
        for y in range(FH):
            sheet.append(sum((f[y] for f in frames), []))
    write_png(OUT / "weave_cubes.png", FW * len(STATES), FH * len(ROWS), sheet)
    write_png(OUT / "weave_cubes_glow.png", FW * len(STATES), FH * len(ROWS), c.glow(sheet))
    big = []
    eye = rune = top = None
    for name in HEART:
        if name.startswith("heart"):
            sc, eye_p, front = heart(name.split("_")[1])
            if name == "heart_lit":
                eye, rune = c.screen(eye_p, HW, HG), c.screen(front, HW, HG)
        else:
            sc, top_p = crown(name == "crown_open")
            top = c.screen(top_p, HW, HG)
        big.append(render_big(sc))
    check_border(big, HW, HH, "heart")
    hsheet = [sum((f[y] for f in big), []) for y in range(HH)]
    write_png(OUT / "weave_heart.png", HW * len(HEART), HH, hsheet)
    write_png(OUT / "weave_heart_glow.png", HW * len(HEART), HH, c.glow(hsheet))
    data = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    data["weave"] = {"frame": [FW, FH], "ground": GR, "rows": ROWS, "states": STATES, "rune": anchors,
                     "heart_frame": [HW, HH], "heart_ground": HG, "heart": HEART, "eye": eye, "crown_top": top}
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    print("weave written: rune anchors", anchors, "eye", eye, "crown", top)
    if len(sys.argv) > 1:
        sc = 5
        bg = (58, 92, 66, 255)
        W = max(FW * len(STATES), HW * len(HEART))
        canvas = [row + [(0, 0, 0, 0)] * (W - len(row)) for row in sheet] + [[(0, 0, 0, 0)] * W] * 4 + [row + [(0, 0, 0, 0)] * (W - len(row)) for row in hsheet]
        out = []
        for row in canvas:
            line = []
            for px in row:
                a = px[3] / 255.0
                line += [tuple(int(px[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
            out += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), W * sc, len(canvas) * sc, out)
