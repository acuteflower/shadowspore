#!/usr/bin/env python3
"""The quarry where the knight is found mining (needs numpy; made like the hut's yard: ellipsoids through hut_lib / art_hero3d): a worked outcrop of the
world's blue-violet stone cut into three terraces (rough above, flat cut faces with drill holes and wedge slots below, veins of void-violet crystal that
glow, a fresh bright gouge where the pick bites), stacks of cut blocks, a handcart loaded with rough stone, tools, heaps of rubble.
    python3 tools/art_quarry.py [preview.png]     writes assets/props/quarry/*.png (+ _glow sheets with only the emissive pixels)
Placed from data/ground.json quarries[].props (class Quarry); the gravel and dust on the ground are baked by tools/bake_ground.py (yard `palette` gravel)."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, load_png_arr, save  # noqa: E402
from hut_yard import cap, shadowed  # noqa: E402

OUT = ROOT / "props" / "quarry"
OUT.mkdir(parents=True, exist_ok=True)
# the world's rocks (tools/art_stone.py: deep blue-violet, a pale lit cap, a mid left face, a dark right face): the quarry is built from the same stone
QS, QS_L = len(h.RAMPS), len(h.RAMPS) + 1
h.RAMPS += [[hexc(c) for c in row] for row in [["1c1a34", "2e2a52", "47436f", "665f94"], ["2e2a52", "47436f", "665f94", "8a83b8"]]]
STONE, STONE_L = QS, QS_L  # (this module only: the hut's greyer stones stay what they are in hut_lib)
ROCK = (STONE, STONE_L)


class big:
    """Renders the models inside it larger (the renderer's unit scale times `k`): the pixel grain stays the same, the rock gets bigger."""

    def __init__(self, k):
        self.k = k

    def __enter__(self):
        self.saved = h.SCALE
        h.SCALE = self.saved * self.k

    def __exit__(self, *_):
        h.SCALE = self.saved


def lumpy(m, rng, x0, x1, z0, z1, y0, y1, rough, front_cut=False, tag=0):
    """A mass of stone filling the box in courses of rounded lumps. `front_cut`: the south face is cut flat (wide, shallow lumps, tight joints)."""
    y = y0
    row = 0
    while y < y1 - 1.0:
        hh = rng.uniform(9.0, 15.0) if not front_cut else rng.uniform(9.0, 12.0)
        hh = min(hh, y1 - y)
        x = x0 - rng.uniform(0, 4)
        while x < x1:
            w = rng.uniform(17, 30) if not front_cut else rng.uniform(22, 36)
            cx = min(x + w / 2, x1)
            for zc, dep in ((z1 - 5.0, 6.5), (z0 + 6.0, 6.5), ((z0 + z1) / 2, 7.0)):
                shade = ROCK[int(rng.integers(0, 2))] if not (front_cut and zc == z1 - 5.0) else (STONE, STONE_L, STONE)[int(rng.integers(0, 3))]
                rr = rough * (1.0 if not front_cut else 0.35)
                m.ell((cx + rng.uniform(-rr, rr), y + hh / 2, zc + rng.uniform(-rr, rr)), (w / 2 * 0.97, hh / 2 * (0.95 + 0.08 * rng.random()), dep), shade)
            if rng.random() < 0.2 and not front_cut:
                m.ell((cx, y + hh + 0.2, z1 - 3), (rng.uniform(2.5, 5), 0.8, rng.uniform(1.8, 3.2)), MOSS_L if rng.random() < 0.5 else MOSS)
            x += w * 0.94
        y += hh * 0.94
        row += 1


def crystal(m, rng, at, n=4, tall=9.0):
    for k in range(n):
        a = rng.uniform(-0.5, 0.5)
        ln = tall * rng.uniform(0.5, 1.0)
        base = at + V(rng.uniform(-2.5, 2.5), 0, rng.uniform(-1.5, 1.5))
        m.limb(base, base + V(math.sin(a) * ln * 0.5, ln, rng.uniform(-0.5, 1.0)), 1.1, 0.25, h.VIOLET if k % 3 else h.TEAL, kind="emit")


def chunk(m, c, w, hh, d, ang=0.0, mat=STONE, tilt=0.0):
    """A big smooth faceted boulder-block like the world's rocks (tools/art_stone.py): one broad rounded mass and a pale lit cap on top of it."""
    R = h.rot_y(ang) @ h.rot_x(tilt)
    c = np.asarray(c, float)
    m.ell(c + R @ V(0, hh * 0.5, 0), (w / 2, hh * 0.5, d), mat, R=R)
    m.ell(c + R @ V(-w * 0.02, hh * 0.9, -d * 0.05), (w * 0.4, hh * 0.18, d * 0.85), STONE_L, R=R)
    m.ell(c + R @ V(w * 0.3, hh * 0.5, d * 0.1), (w * 0.22, hh * 0.46, d * 0.95), mat, R=R)  # a second mass beside it, so the outline is not an egg
    for k in range(2):  # cracks, like the world's rocks
        x = w * (-0.25 + 0.4 * k)
        m.ell(c + R @ V(x, hh * (0.45 + 0.1 * k), d * 0.97), (0.35, hh * 0.22, 0.3), GAP, R=R)
        m.ell(c + R @ V(x + 1.0, hh * (0.28 + 0.1 * k), d * 0.97), (1.4, 0.3, 0.3), GAP, R=R)
    m.ell(c + R @ V(-w * 0.18, hh * 0.78, d * 0.9), (w * 0.12, hh * 0.1, d * 0.5), MOSS if hh > 6 else STONE_L, R=R)


def face_arr():
    """The worked outcrop, made of a few big faceted blocks like the world's rocks: three terraces stepping down to the east (the cut faces flat with drill holes and
    wedge slots, the top one rough and mossy with crystal), a fresh pale gouge where the pick bites, loose boulders on top. 190 x 120, feet row 104."""
    rng = rng_for(200)
    m = h.Model()
    z = -4.0
    chunk(m, V(-34, 0, z - 3), 40, 38, 14, 0.03, STONE)  # the highest terrace, rough
    chunk(m, V(-10, 0, z), 26, 25, 15, -0.02, STONE_L)  # the middle terrace, cut
    chunk(m, V(24, 0, z + 2), 44, 12, 14, 0.0, STONE)  # the lowest bench he works at
    chunk(m, V(-22, 38, z - 5), 24, 8, 11, 0.12, STONE_L)  # a loose slab on top
    m.ell(V(-40, 44, z - 6), (11, 7, 9), STONE_L)  # boulders sitting on it
    m.ell(V(-24, 46, z - 7), (8, 6, 8), STONE)
    for (x0, x1, top, zf, dep) in ((-54, -14, 38.0, z + 11, 14), (-23, 3, 25.0, z + 14, 15), (2, 46, 12.0, z + 16, 14)):  # the cut faces
        for yy in np.arange(8.0, top, 8.0):
            m.ell((rng.uniform(x0 + 8, x1 - 8), yy, zf), ((x1 - x0) * 0.4, 0.3, 0.45), GAP)
        for xx in np.arange(x0 + 6, x1 - 3, 9.0):  # drill holes in rows
            for k in range(int(top // 8) + (1 if top < 20 else 0)):
                m.ell((xx, 4.0 + k * 8.0, zf + 0.2), (0.7, 0.7, 0.4), GAP)
        m.ell((x0 + (x1 - x0) * 0.4, top * 0.55, zf), (0.45, 4.2, 0.4), GAP)  # a wedge slot
    for (x0, x1, top, zc) in ((-54, -14, 38.0, z - 3), (-23, 3, 25.0, z), (2, 46, 12.0, z + 2)):  # moss on the tops
        for _ in range(5):
            m.ell((rng.uniform(x0 + 3, x1 - 3), top + 0.4, zc + rng.uniform(-3, 4)), (rng.uniform(3, 7), 0.8, rng.uniform(2, 4)), MOSS_L if rng.random() < 0.5 else MOSS)
    for _ in range(14):  # the fresh gouge where the pick bites: pale stone, chips
        m.ell((47 + rng.uniform(-1.5, 2.5), rng.uniform(1.5, 10), z + 14 + rng.uniform(1, 3)), (rng.uniform(1.4, 3.0), rng.uniform(1.2, 2.4), 1.0), STONE_L)
    m.ell((48, 6.0, z + 15.5), (2.6, 4.0, 1.4), GAP)
    p = V(-52, 6, z + 14.5)  # a vein of crystal across the cut faces
    for st in range(22):
        p = p + V(rng.uniform(1.8, 2.8), rng.uniform(0.5, 1.6), 0)
        if p[1] < (38 if p[0] < -14 else 25 if p[0] < 3 else 12) - 1.5 and st % 6 != 5:
            m.ell(p, (0.7, 0.7, 0.5), h.VIOLET, kind="emit")
    crystal(m, rng, V(-48, 46, z - 6), 6, 12.0)
    crystal(m, rng, V(-6, 25, z - 4), 3, 7.0)
    for k in range(4):  # lichen fungi at the foot, like the rocks
        m.ell((-50 + k * 22, 2.4, z + 16), (2.2, 1.0, 1.6), h.TEAL, kind="emit")
    for k in range(3):
        ivy(m, V(-56 + k * 3, 36, z + 12.5), rng.uniform(14, 26), rng, glow_every=4, sway=0.7)
    for _ in range(3):  # fallen chunks at the foot
        c = V(rng.uniform(-50, 50), 0, z + rng.uniform(19, 24))
        chunk(m, c, rng.uniform(7, 12), rng.uniform(4, 6), 5, rng.uniform(-0.6, 0.6), ROCK[int(rng.integers(0, 2))])
    with big(1.15):
        arr = to_array(render(m, 190, 120, 104))
    return shadowed(arr, 104, 80, 7), 104


CRANE = dict(w=88, h=104, ground=92)


def crane_arrs():
    """A wooden tripod with a pulley at its top, and (a sheet of its own: it sways in the wind) the rope with a sling and a cut block hanging from it. Returns
    (the tripod, the hanging load, feet row, the row of the pulley)."""
    rng = rng_for(250)
    m = h.Model()
    c = h.Model()
    top = V(0, 66, 0)
    for k, (x, z) in enumerate(((-17, 10), (17, 10), (0, -15))):
        log(m, V(x, 0, z), top + V(x * 0.05, 0, z * 0.05), 2.4, BARK if k != 2 else BARK_D, step=1.2, taper=0.8)
        for q in range(4):
            m.ell(V(x * (1 - q * 0.1), 3 + q * 0.5, z * (1 - q * 0.1)) + V(rng.uniform(-1, 1), 0, rng.uniform(-1, 1)), (rng.uniform(1.2, 2.4), 1.0, 1.2), MOSS_L if rng.random() < 0.5 else MOSS)
    log(m, V(-14, 24, 8.5), V(14, 24, 8.5), 1.4, BARK_D, step=1.1)  # a brace
    log(m, V(-6, 40, -4), V(6, 40, -4), 1.3, BARK_D, step=1.1)
    for k in range(10):  # the pulley wheel
        a = k / 10 * math.tau
        m.ell(V(math.cos(a) * 3.6, 63 + math.sin(a) * 3.6, 0.5), (1.0, 1.0, 1.4), IRON)
    m.ell(top + V(0, 2, 0), (3.0, 2.0, 3.0), BARK_D)
    m.ell(V(0, 69, 1.5), (1.0, 1.0, 1.0), h.TEAL, kind="emit")
    m.limb(V(2.5, 65, 0.8), V(22, 4, 14), 0.5, 0.5, STRAW)  # the free end of the rope, tied off at a peg
    log(m, V(22, 0, 14), V(22, 7, 14), 1.4, BARK_D, step=1.0)
    c.limb(V(-3.0, 63, 0.9), V(-3.0, 36, 0.9), 0.55, 0.55, STRAW)
    for sx in (-1, 1):  # the sling round a block
        c.limb(V(-3.0, 36, 0.9), V(-3.0 + sx * 8.5, 24, 1.5), 0.4, 0.4, STRAW)
    c.ell(V(-3.0, 37, 0.9), (1.6, 1.6, 1.6), IRON)
    for ix in range(-6, 7):
        c.ell(V(-3.0 + ix * 1.4, 18.0, 1.0), (2.0, 5.5, 6.5), STONE if (ix // 4) % 2 == 0 else STONE_L)
    for k in range(5):
        c.ell(V(-11.0 + k * 4.6, 18.0, 7.6), (0.45, 4.2, 0.4), GAP)
    fw, fh, g = CRANE["w"], CRANE["h"], CRANE["ground"]
    tri = grain(to_array(render(m, fw, fh, g)), 251, amount=0.5, mats=WOODS)
    load = grain(to_array(render(c, fw, fh, g)), 252, amount=0.4, mats=(STONE, STONE_L))
    return shadowed(tri, g, 30, 6), load, g


def blocks_arr():
    """Cut blocks, two stacks and one tilted, chisel marks on their faces. 96 x 64, feet row 52."""
    rng = rng_for(210)
    m = h.Model()

    def block(c, w, hh, d, ang=0.0, mat=STONE):
        chunk(m, c, w, hh, d, ang, mat)
        R = h.rot_y(ang)
        for k in range(3):  # chisel marks
            m.ell(V(c[0], c[1], c[2]) + R @ V(-w * 0.3 + k * w * 0.3, hh * 0.45, d * 0.97), (0.45, hh * 0.25, 0.4), GAP)

    block(V(-24, 0, 0), 22, 11, 9)
    block(V(-2, 0, 2), 22, 11, 9, 0.05, STONE_L)
    block(V(-14, 11, 1), 24, 10, 9, -0.04)
    block(V(26, 0, 4), 20, 9, 8, 0.5)
    block(V(18, 0, -10), 18, 8, 7, -0.2, STONE_L)
    for _ in range(14):
        m.ell(V(rng.uniform(-40, 40), 0.8, rng.uniform(3, 12)), (rng.uniform(1.0, 2.4), 0.7, 1.0), STONE_L)
    for _ in range(10):
        m.ell(V(rng.uniform(-36, 18), rng.uniform(0.5, 21), 13 + rng.uniform(0, 1)), (rng.uniform(1.6, 3.4), 0.9, 1.0), MOSS_L if rng.random() < 0.5 else MOSS)
    m.ell(V(34, 3.0, 12), (1.3, 1.3, 1.3), h.TEAL, kind="emit")
    arr = to_array(render(m, 96, 64, 52))
    return shadowed(arr, 52, 44, 7), 52


def cart_arr():
    """A handcart with two big wheels, loaded with rough stone; the shafts rest on the ground. 104 x 70, feet row 56."""
    rng = rng_for(220)
    m = h.Model()
    for sz in (-1, 1):  # the wheels, rim and spokes
        for k in range(26):
            a = k / 26 * math.tau
            m.ell(V(math.cos(a) * 11.5, 11.8 + math.sin(a) * 11.5, sz * 13.5), (1.6, 1.6, 1.4), BARK_D if k % 2 else BARK)
        for k in range(8):
            a = k / 8 * math.tau
            m.limb(V(0, 11.8, sz * 13.5), V(math.cos(a) * 10.5, 11.8 + math.sin(a) * 10.5, sz * 13.5), 0.8, 0.6, BARK)
        m.ell(V(0, 11.8, sz * 14.5), (2.2, 2.2, 1.8), IRON)
    log(m, V(0, 11.8, -16), V(0, 11.8, 16), 1.1, IRON, step=1.0)  # the axle
    for k in range(6):  # the bed: planks
        z = -10.5 + k * 4.2
        slab(m, V(-17, 14.4, z), V(17, 14.4, z), 2.0, 0.8, PLANK_W if k % 2 else BARK, (0, 1, 0))
    for sz in (-1, 1):
        slab(m, V(-17, 19.0, sz * 12.2), V(17, 19.0, sz * 12.2), 3.4, 0.9, BARK_D, (0, 0, sz))
    slab(m, V(17.5, 19.0, -11), V(17.5, 19.0, 11), 3.4, 0.9, BARK, (1, 0, 0))
    for sz in (-1, 1):  # the shafts
        log(m, V(14, 15.5, sz * 8.0), V(-44, 3.0, sz * 7.0), 1.5, BARK, step=1.2)
    log(m, V(-40, 4.2, -7), V(-40, 4.2, 7), 1.4, BARK_D, step=1.0)  # the cross bar
    for _ in range(11):  # the load: rough chunks, some bright where they were split
        m.ell(V(rng.uniform(-14, 14), rng.uniform(17, 25), rng.uniform(-9, 9)), (rng.uniform(4.5, 8.0), rng.uniform(3.0, 5.5), rng.uniform(3.5, 6.0)), ROCK[int(rng.integers(0, 2))],
              R=h.rot_y(rng.uniform(0, 3)) @ h.rot_x(rng.uniform(-0.4, 0.4)))
    for _ in range(4):
        m.ell(V(rng.uniform(-10, 10), rng.uniform(24, 28), rng.uniform(-6, 6)), (1.0, 2.2, 0.9), h.VIOLET, kind="emit")
    for _ in range(10):
        m.ell(V(rng.uniform(-16, 16), rng.uniform(12, 17), 12.6), (rng.uniform(1.5, 3), 1.0, 0.8), MOSS if rng.random() < 0.5 else MOSS_L)
    m.limb(V(-44, 3.5, 0), V(-30, 14, 3), 0.5, 0.5, STRAW)  # a rope coiled over a shaft
    arr = to_array(render(m, 104, 70, 56))
    arr = grain(arr, 221, amount=0.5, mats=(BARK, BARK_D, PLANK_W))
    return shadowed(arr, 56, 50, 8, dx=-5), 56


def tools_arr():
    """A sledgehammer on the ground, iron wedges, a crate with chisels, a water bucket. 72 x 40, feet row 30."""
    rng = rng_for(230)
    m = h.Model()
    log(m, V(-26, 1.8, 6), V(-4, 1.8, 3), 1.1, h.LEATHER, step=1.0)
    m.ell(V(-30, 3.4, 6.3), (4.4, 3.0, 3.0), IRON)
    m.ell(V(-30, 3.4, 6.3), (4.6, 0.7, 3.2), STEEL_L if False else IRON)
    for k in range(4):
        m.ell(V(-2 + k * 5.0, 1.6, 12 - k * 1.2), (1.2, 2.0, 3.2), IRON, R=h.rot_y(0.5 * k))
    cx, cz = 18.0, -2.0
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(cx + sx * 7.5, 0, cz + sz * 5.5), V(cx + sx * 7.5, 9, cz + sz * 5.5), 1.2, BARK_D, step=1.0)
    for k in range(3):
        for sz in (-1, 1):
            slab(m, V(cx - 8.2, 2.2 + k * 3.2, cz + sz * 6.2), V(cx + 8.2, 2.2 + k * 3.2, cz + sz * 6.2), 1.7, 0.7, PLANK_W if k % 2 else BARK, (0, 0, sz))
    m.ell(V(cx, 6.5, cz), (7.2, 0.6, 5.2), GAP)
    for k in range(5):  # chisels standing in it
        log(m, V(cx - 5 + k * 2.6, 6.5, cz + rng.uniform(-2, 2)), V(cx - 5 + k * 2.6 + rng.uniform(-0.6, 0.6), 13 + rng.uniform(0, 3), cz), 0.6, IRON if k % 2 else h.LEATHER, step=0.8)
    bx, bz = 46.0, 4.0
    log(m, V(bx, 0, bz), V(bx, 8.5, bz), 4.6, PLANK_W, step=1.0, taper=1.1)
    for y in (2.2, 7.0):
        for k in range(14):
            a = k / 14 * math.tau
            m.ell(V(bx + math.cos(a) * 5.3, y, bz + math.sin(a) * 5.3), (0.8, 0.7, 0.8), IRON)
    m.ell(V(bx, 8.8, bz), (4.6, 0.4, 4.6), WATER if False else GAP)
    arc = [V(bx - 5.2 * math.cos(i / 8 * math.pi), 9.0 + math.sin(i / 8 * math.pi) * 5.5, bz) for i in range(9)]
    for a_, b_ in zip(arc[:-1], arc[1:]):
        m.limb(a_, b_, 0.45, 0.45, STRAW)
    arr = to_array(render(m, 72, 40, 30))
    arr = grain(arr, 231, amount=0.5, mats=(BARK, BARK_D, PLANK_W))
    return shadowed(arr, 30, 32, 5, dx=2), 30


def rubble_arr():
    """Three heaps of broken stone with chips, moss and a crystal splinter. 3 frames of 56 x 32, feet row 26."""
    out = np.zeros((32, 56 * 3, 4), np.uint8)
    for v in range(3):
        rng = rng_for(240 + v)
        m = h.Model()
        n = 7 + v * 2
        for _ in range(n):
            a = rng.uniform(0, math.tau)
            d = (rng.random() ** 0.7) * (15 + v * 3)
            y = max(0.8, 7.5 - d * 0.5) * rng.uniform(0.4, 1.0)
            r = rng.uniform(3.2, 6.0) * (1.0 - d / 50)
            m.ell(V(math.cos(a) * d * 1.3, y, math.sin(a) * d * 0.8), (r * 1.2, r * 0.8, r), ROCK[int(rng.integers(0, 2))], R=h.rot_y(rng.uniform(0, 3)))
        for _ in range(8):
            m.ell(V(rng.uniform(-14, 14), 0.6, rng.uniform(-6, 9)), (rng.uniform(0.8, 1.6), 0.5, 0.8), STONE_L)
        for _ in range(4):
            m.ell(V(rng.uniform(-9, 9), rng.uniform(3, 7), rng.uniform(-3, 4)), (rng.uniform(1.8, 3.2), 0.8, 1.2), MOSS_L)
        if v != 1:
            crystal(m, rng, V(rng.uniform(-4, 4), 4.0, 0.0), 2, 5.0)
        arr = to_array(render(m, 56, 32, 26))
        out[:, v * 56:(v + 1) * 56] = shadowed(arr, 26, 24, 4)
    return out, 26


def pick_arr():
    """The knight's pickaxe leaning against the stone (it appears in his `set` clip, the same pick as in his hands). 40 x 56, feet row 46."""
    import art_adventurer as adv  # its pick, its ramps
    m = h.Model()
    adv.pickaxe(m, V(0, 2.0, 0), V(0.0, 0.97, 0.2))
    arr = to_array(render(m, 40, 56, 46))
    return shadowed(arr, 46, 8, 3), 46


def put(name, arr, glow_mats=(h.TEAL, h.VIOLET)):
    save(OUT / f"{name}.png", arr)
    g = glow_of(arr, glow_mats)
    if g[..., 3].any():
        save(OUT / f"{name}_glow.png", g)
    elif (OUT / f"{name}_glow.png").exists():
        (OUT / f"{name}_glow.png").unlink()
    return arr.shape[1], arr.shape[0]


def main():
    for name, fn in (("face", face_arr), ("blocks", blocks_arr), ("cart", cart_arr), ("tools", tools_arr), ("rubble", rubble_arr), ("pick", pick_arr)):
        arr, feet = fn()
        print("quarry_" + name, put("quarry_" + name, arr), feet)
    tripod, load, feet = crane_arrs()
    print("quarry_crane", put("quarry_crane", tripod), put("quarry_hang", load), feet)
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))


def preview(path):
    tiles = [load_png_arr(OUT / f"quarry_{n}.png") for n in ("face", "blocks", "cart", "tools", "rubble", "crane", "pick")]
    wid = sum(t.shape[1] for t in tiles) + 8 * (len(tiles) + 1)
    canvas = np.zeros((max(t.shape[0] for t in tiles) + 16, wid, 4), np.uint8)
    canvas[:] = (70, 82, 76, 255)
    x = 8
    for t in tiles:
        sub = canvas[8:8 + t.shape[0], x:x + t.shape[1]]
        a = t[..., 3:4] / 255.0
        sub[..., :3] = (t[..., :3] * a + sub[..., :3] * (1 - a)).astype(np.uint8)
        x += t.shape[1] + 8
    save(path, np.kron(canvas, np.ones((2, 2, 1), np.uint8)))


if __name__ == "__main__":
    main()
