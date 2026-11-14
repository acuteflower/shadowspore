#!/usr/bin/env python3
"""The stone houses of Hallgrat (docs/stadt_westen_konzept.md stage 3b): an old town of the blue-violet stone of the Glaskamm, the same stone its
streets, stairs and terrace walls are made of. Built like the smithy (ellipsoids through art_hero3d / hut_lib): coursed ashlar with every row
offset, lintels and sills of lighter stone, round-arched doors, slate roofs (`roof_pass` with cold slate tones), chimneys, shutters of the
town's dusty blue, warm windows whose glass glows at night (a second, unlit sheet). The Fuß is half abandoned: boarded windows, moss on the
roofs, ivy on the walls.

Types (data/hallgrat_art.json keeps per picture: size, feet = the middle of the front edge on the ground, foot = the footprint in px, lights):
  haus_a, haus_b     a dwelling with its ridge along the street, one storey, door and two windows (two builds)
  haus_hoch          two storeys, a string course between them, three windows above
  giebel             a narrow house with its gable to the street, a round window under the ridge
  laden              a workshop: a wide arched shop window, a teal cloth awning, a sign bracket
  verlassen_a/_b     abandoned: boarded windows, a door nailed shut, moss and ivy
  halle              a hall (Hüterhalle, Rothalle, Archiv): gable to the street, a tall arched door, a round rose window, buttresses
  torhaus            a gatehouse: a square stone tower with merlons and an arrow slit
  stall              the stables (data/hallgrat.json `stallungen`): long, a big arched double door, a hayloft door, small high windows

    py -3 tools/art_hallgrat_houses.py [preview.png]      then      Godot --headless --path . --import
Needs numpy and PIL."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import (BARK, BARK_D, BANNER, FIRE, GAP, IRON, LINEN, MOSS, MOSS_L, PLANK, PLANK_W, ROOF, SHUT, STONE, STONE_L, STRAW,  # noqa: E402
                     ROOT, V, bayer, glow_of, hsh, log, rng_for, save, slab, to_array)
from gen_art import hexc  # noqa: E402

OUT = ROOT / "town" / "hallgrat"
DATA = Path(__file__).resolve().parent.parent / "data" / "hallgrat_art.json"
S = h.SCALE
SLATE = (  # slate of the Glaskamm: the walls' violet stone, split thin and a shade darker
    [hexc(c) for c in ("18162a", "2c2848", "463f6c", "6e6696")],
    [hexc(c) for c in ("1b1a28", "312e46", "4e4a68", "77728f")],
    [hexc(c) for c in ("1f1a30", "3a3254", "5a5080", "877cae")],
)
MASON = [hexc(c) for c in ("19172d", "292645", "3e3a5e", "58537b", "78729b", "a29cc1")]  # relief.gdshader MASON: streets, stairs, terrace walls
h.RAMPS[STONE] = MASON[1:5]          # the walls: the very stone of the streets
h.RAMPS[STONE_L] = MASON[2:6]        # lintels, sills, quoins, arches: the same stone, a lighter cut
STONES = (STONE, STONE, STONE)
CANVAS = (620, 440, 360)   # w, h, ground row of the render canvas (cropped afterwards)
# Ellie is 52 px tall and a door has to take her (about 40 px): the models are built small and grown to her size here, per kind
GROW = {"halle": 1.6, "torhaus": 1.7, "stall": 1.3, "mauer_ns": 1.6, "leitstein": 1.5, "stand": 1.6}


def grow_of(name):
    for k, v in GROW.items():
        if name.startswith(k):
            return v
    return 1.9


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def proj(x, y, z):
    """Model point -> px relative to the middle of the foot's front edge (up is negative)."""
    return (x * S, -(y * h.COSP - z * h.SINP) * S)


# ------------------------------------------------------------------ stone work
def ashlar_z(m, rng, x0, x1, y0, y1, z, depth=3.4, top=None):
    """A wall facing +z: courses of rounded blocks, every row offset. `top(x)` (optional) cuts the courses to a gable's slope."""
    y, row = y0, 0
    while y < y1 - 0.6:
        hgt = rng.uniform(4.4, 5.8)
        x = x0 - (row % 2) * 3.6 - rng.uniform(0, 2.4)
        while x < x1 - 0.5:
            w = rng.uniform(5.5, 10.5)
            lo, hi = max(x, x0 - 0.4), min(x + w, x1 + 0.4)
            cy = min(y + hgt / 2, y1 - 1.2)
            if hi - lo > 2.5 and (top is None or cy + hgt / 2 <= top((lo + hi) / 2) + 1.0):
                m.ell(V((lo + hi) / 2, cy, z + rng.uniform(-0.5, 0.5)), ((hi - lo) / 2 * 0.99, min(hgt, y1 - y) / 2 * 0.97, depth),
                      STONES[(row + int(x * 0.37)) % 3])
            x += w
        y += hgt * 0.93
        row += 1


def ashlar_x(m, rng, z0, z1, y0, y1, x, depth=3.4, top=None):
    y, row = y0, 0
    while y < y1 - 0.6:
        hgt = rng.uniform(4.4, 5.8)
        z = z0 - (row % 2) * 3.6 - rng.uniform(0, 2.4)
        while z < z1 - 0.5:
            w = rng.uniform(5.5, 10.5)
            lo, hi = max(z, z0 - 0.4), min(z + w, z1 + 0.4)
            cy = min(y + hgt / 2, y1 - 1.2)
            if hi - lo > 2.5 and (top is None or cy + hgt / 2 <= top((lo + hi) / 2) + 1.0):
                m.ell(V(x + rng.uniform(-0.5, 0.5), cy, (lo + hi) / 2), (depth, min(hgt, y1 - y) / 2 * 0.97, (hi - lo) / 2 * 0.99),
                      STONES[(row + int(z * 0.37)) % 3])
            z += w
        y += hgt * 0.93
        row += 1


def string_course(m, x0, x1, y, z):
    """A band of long lighter stones between two storeys."""
    x = x0
    while x < x1:
        m.ell(V(min(x + 4.5, x1 - 1), y, z + 2.2), (4.6, 1.3, 1.6), STONE_L)
        x += 9.4


def quoins(m, x, z, y1, along_x):
    """Big corner stones, alternating long and short, lighter than the wall."""
    y, k = 0.6, 0
    while y < y1 - 2:
        long = k % 2 == 0
        if along_x:
            m.ell(V(x, y + 2.6, z + 1.0), (4.8 if long else 3.0, 2.5, 3.8), STONE_L)
        else:
            m.ell(V(x, y + 2.6, z), (3.8, 2.5, 4.8 if long else 3.0), STONE_L)
        y += 5.2
        k += 1


def window(m, x, y0, w, hgt, z, lit=True, shutters=True, boarded=False, arch=False, rng=None):
    """A window in a wall facing +z: the dark opening, warm glass (or boards), a lintel and a sill of lighter stone, a cross of iron bars, and
    painted shutters folded back against the wall."""
    cx, cy = x, y0 + hgt / 2
    m.ell(V(cx, cy, z + 2.6), (w / 2 + 0.4, hgt / 2 + 0.4, 1.0), GAP)
    if boarded:
        for k in range(3):
            yy = y0 + 1.5 + k * (hgt - 3) / 2
            tilt = (k - 1) * 0.08 + (rng.uniform(-0.05, 0.05) if rng is not None else 0)
            slab(m, V(cx - w / 2 - 1.5, yy - tilt * w, z + 3.9), V(cx + w / 2 + 1.5, yy + tilt * w, z + 3.9), 1.3, 0.6, PLANK if k != 1 else PLANK_W, (0, 0, 1), step=1.2)
    elif lit:
        m.ell(V(cx, cy, z + 3.1), (w / 2 - 0.2, hgt / 2 - 0.2, 0.5), FIRE, kind="emit")
        log(m, V(cx, y0 + 0.4, z + 3.7), V(cx, y0 + hgt - 0.4, z + 3.7), 0.35, IRON, step=0.8)
        log(m, V(cx - w / 2 + 0.4, cy + 0.5, z + 3.7), V(cx + w / 2 - 0.4, cy + 0.5, z + 3.7), 0.35, IRON, step=0.8)
    else:
        m.ell(V(cx, cy, z + 3.0), (w / 2 - 0.2, hgt / 2 - 0.2, 0.5), GAP)
    if arch:
        for k in range(9):
            a = math.pi * k / 8
            r = w / 2 + 1.3
            m.ell(V(cx + math.cos(a) * r, y0 + hgt - w / 2 + math.sin(a) * r, z + 3.4), (1.6, 1.6, 1.4), STONE_L, R=rot_z(a - math.pi / 2))
    else:
        m.ell(V(cx, y0 + hgt + 1.3, z + 3.6), (w / 2 + 2.4, 1.4, 1.5), STONE_L)   # lintel
    m.ell(V(cx, y0 - 1.0, z + 3.9), (w / 2 + 1.8, 0.9, 1.9), STONE_L)            # sill
    if shutters and not boarded:
        for sx in (-1, 1):
            xx = cx + sx * (w / 2 + 2.4)
            for k in range(3):
                slab(m, V(xx + sx * (k - 1) * 0.9, y0 + 0.2, z + 4.4), V(xx + sx * (k - 1) * 0.9, y0 + hgt - 0.2, z + 4.4), 0.85, 0.55, SHUT, (0, 0, 1), step=1.1)


def door(m, x, w, hgt, z, arch=True, nailed=False, steps=1, porch=True):
    """A doorway in a wall facing +z: deep dark opening, a plank door with iron straps, a round arch of wedge stones, a threshold step."""
    m.ell(V(x, hgt / 2, z + 2.2), (w / 2 + 0.6, hgt / 2 + 0.3, 1.2), GAP)
    xx = x - w / 2 + 1.2
    i = 0
    while xx < x + w / 2 - 0.6:
        slab(m, V(xx, 0.8, z + 3.0), V(xx, hgt - (0.0 if not arch else max(0.0, (abs(xx - x) / (w / 2)) ** 2 * w * 0.35)), z + 3.0), 1.1, 0.7,
             PLANK_W if i % 3 == 1 else PLANK, (0, 0, 1), step=1.2)
        xx += 2.2
        i += 1
    for yy in (hgt * 0.25, hgt * 0.62):
        log(m, V(x - w / 2 + 0.8, yy, z + 3.8), V(x + w / 2 - 0.8, yy, z + 3.8), 0.45, IRON, step=0.8)
    m.ell(V(x + w * 0.3, hgt * 0.45, z + 4.0), (0.6, 0.6, 0.5), IRON)          # the ring
    if nailed:
        for k in (-1, 1):
            slab(m, V(x - w / 2 - 1.5, hgt * 0.5 + k * 3.5 - 2, z + 4.6), V(x + w / 2 + 1.5, hgt * 0.5 + k * 3.5 + 2, z + 4.6), 1.3, 0.6, PLANK, (0, 0, 1), step=1.2)
    if arch:
        r = w / 2 + 1.6
        for k in range(13):
            a = math.pi * k / 12
            m.ell(V(x + math.cos(a) * r, hgt - w * 0.35 + math.sin(a) * r, z + 3.2), (2.1, 2.1, 1.6), STONE_L if k % 2 else STONE, R=rot_z(a - math.pi / 2))
    else:
        m.ell(V(x, hgt + 1.6, z + 3.4), (w / 2 + 3.0, 1.8, 1.7), STONE_L)
    for k in range(steps):
        m.ell(V(x, 0.5 - k * 0.2, z + 5.0 + k * 3.0), (w / 2 + 2.5 + k, 0.9, 2.6), STONE_L if k == 0 else STONE)
    if porch:
        top = hgt + (2.5 if not arch else 3.5)
        for k in range(int((w + 8) / 2.6) + 1):
            xx = x - w / 2 - 4 + k * 2.6
            slab(m, V(xx, top + 3.2, z + 2.6), V(xx, top + 0.6, z + 10.5), 1.5, 0.9, ROOF, (0, 1, 0.45), step=1.0)
        log(m, V(x - w / 2 - 4, top + 0.2, z + 10.8), V(x + w / 2 + 4, top + 0.2, z + 10.8), 0.8, BARK_D, step=0.9)
        for sx in (-1, 1):
            log(m, V(x + sx * (w / 2 + 2.6), top - 4.0, z + 3.0), V(x + sx * (w / 2 + 2.6), top + 0.4, z + 9.6), 0.45, IRON, step=0.7)


def chimney(m, rng, x, z, y0, y1):
    y, row = y0, 0
    while y < y1:
        hgt = rng.uniform(3.8, 4.6)
        m.ell(V(x + rng.uniform(-0.3, 0.3), y + hgt / 2, z), (4.0, hgt / 2, 3.6), STONES[row % 3])
        y += hgt * 0.94
        row += 1
    m.ell(V(x, y1 + 0.8, z), (5.2, 1.2, 4.6), STONE_L)
    m.ell(V(x, y1 + 1.6, z), (2.4, 0.9, 2.0), GAP)


def roof_along_x(m, rng, x0, x1, zb, zf, eave, ridge, over=7.0):
    """A ridge along x (a long house beside the street): front and back slopes of slabs from the ridge to the eaves; `roof_pass` shingles them."""
    zr = (zb + zf) / 2.0
    for zs, ze in ((zr, zf + over), (zr, zb - over)):
        a = V(0, ridge, zs)
        b = V(0, eave - 1.0, ze)
        axis = b - a
        normal = np.cross(axis, V(1, 0, 0))
        normal = normal / np.linalg.norm(normal)
        if normal[1] < 0:
            normal = -normal
        x = x0 - over
        while x < x1 + over:
            j = rng.uniform(-0.4, 0.4)
            slab(m, V(x, ridge + j * 0.3, zs), V(x, eave - 1.0 + j * 0.3, ze), 3.6, 1.6, ROOF, tuple(normal), step=1.4)
            x += 6.6
    log(m, V(x0 - over, ridge + 1.3, zr), V(x1 + over, ridge + 1.3, zr), 1.6, STONE_L, step=1.2)
    # the eave: a dark fascia board along the front edge and the rafter ends under it, so the roof stands off the wall
    log(m, V(x0 - over, eave - 2.2, zf + over - 0.6), V(x1 + over, eave - 2.2, zf + over - 0.6), 1.5, BARK_D, step=1.1)
    for x in np.arange(x0 - over + 3, x1 + over - 2, 7.0):
        m.ell(V(x, eave - 3.4, zf + over * 0.55), (1.2, 1.4, over * 0.5), BARK, R=None)
    for side in (-1, 1):  # the gable's verge boards, so the roof's edge reads as a thickness
        xx = x1 + over if side > 0 else x0 - over
        log(m, V(xx, ridge + 0.4, zr), V(xx, eave - 2.0, zf + over - 0.4), 1.2, BARK_D, step=1.1)


def roof_along_z(m, rng, x0, x1, zb, zf, eave, ridge, over=6.0):
    """A ridge along z (a gable to the street): left and right slopes."""
    xr = (x0 + x1) / 2.0
    half = (x1 - x0) / 2.0 + over
    for side in (-1, 1):
        a = V(xr, ridge, 0)
        b = V(xr + side * half, eave - 1.0, 0)
        axis = b - a
        normal = np.cross(axis, V(0, 0, 1))
        normal = normal / np.linalg.norm(normal)
        if normal[1] < 0:
            normal = -normal
        z = zb - over
        while z < zf + 0.5:  # hardly any overhang at the front: the stone gable shows under the roof's edge
            j = rng.uniform(-0.4, 0.4)
            slab(m, a + V(0, 0.3 * j, z), b + V(0, 0.3 * j, z), 3.6, 1.6, ROOF, tuple(normal), step=1.4)
            z += 6.6
    log(m, V(xr, ridge + 1.0, zb - over), V(xr, ridge + 1.0, zf + 0.5), 1.25, STONE, step=1.2)
    for side in (-1, 1):  # the verge: a row of lighter coping stones along the gable's edges
        a, b = V(xr, ridge - 0.5, zf + 1.6), V(xr + side * (half - over + 1.5), eave - 0.5, zf + 1.6)
        for k in range(int(np.linalg.norm(b - a) / 4.2) + 1):
            m.ell(a + (b - a) * (k / max(1, int(np.linalg.norm(b - a) / 4.2))), (2.6, 1.8, 2.2), STONE_L)


def body(m, rng, W, D, eave, gable_front=False, ridge=0.0):
    """Four walls: the front at z = 0, the back at z = -D; side gables (ridge along x) or a front gable (ridge along z)."""
    ashlar_z(m, rng, -W, W, 0.6, eave + 0.5, -D)
    if gable_front:
        tri = lambda x: eave + (ridge - eave) * max(0.0, 1.0 - abs(x) / W)  # noqa: E731
        ashlar_z(m, rng, -W, W, 0.6, ridge, 0.0, top=tri)
        ashlar_x(m, rng, -D, 0.0, 0.6, eave + 0.5, -W)
        ashlar_x(m, rng, -D, 0.0, 0.6, eave + 0.5, W)
    else:
        ashlar_z(m, rng, -W, W, 0.6, eave + 0.5, 0.0)
        tri = lambda z: eave + (ridge - eave) * max(0.0, 1.0 - abs(z + D / 2) / (D / 2))  # noqa: E731
        ashlar_x(m, rng, -D, 0.0, 0.6, ridge, -W, top=tri)
        ashlar_x(m, rng, -D, 0.0, 0.6, ridge, W, top=tri)
    quoins(m, -W, 0.0, eave, True)
    quoins(m, W, 0.0, eave, True)
    for x in np.arange(-W + 4, W, 7.5):  # a plinth course of bigger dark stones at the foot
        m.ell(V(x, 1.4, 1.2), (3.9, 1.6, 1.4), STONE)


def moss_and_ivy(m, rng, W, D, eave, amount):
    for k in range(int(amount * 6)):
        x = rng.uniform(-W + 4, W - 4)
        hut_lib.ivy(m, V(x, eave - 1.0, 2.2), rng.uniform(8, eave - 4), rng)
    for k in range(int(amount * 10)):
        hut_lib.tuft(m, V(rng.uniform(-W, W), 0.4, rng.uniform(1.5, 4.0)), rng, blades=5, height=rng.uniform(3, 6))


# ------------------------------------------------------------------ the types
def haus(rng, seed_variant=0, abandoned=False):
    m = h.Model()
    W, D, eave, ridge = 40.0 + 4 * seed_variant, 66.0, 38.0, 60.0
    body(m, rng, W, D, eave, ridge=ridge)
    dx = -10.0 if seed_variant else 6.0
    door(m, dx, 11.0, 20.0, 0.0, arch=seed_variant == 0, nailed=abandoned)
    for wx in ((-26.0, 24.0) if not seed_variant else (-28.0, 12.0, 30.0)):
        if abs(wx - dx) < 12:
            continue
        window(m, wx, 11.0, 8.0, 10.0, 0.0, lit=not abandoned, shutters=not abandoned or wx < 0, boarded=abandoned, rng=rng)
    roof_along_x(m, rng, -W, W, -D, 0.0, eave, ridge)
    chimney(m, rng, W * 0.55, -D * 0.55, ridge - 8, ridge + 9)
    if abandoned:
        moss_and_ivy(m, rng, W, D, eave, 1.0)
    return m, dict(W=W, D=D, lights=[] if abandoned else [[-26.0 if not seed_variant else -28.0, 16.0]], moss=0.45 if abandoned else 0.08, abandoned=abandoned)


def haus_hoch(rng):
    m = h.Model()
    W, D, eave, ridge = 44.0, 68.0, 56.0, 78.0
    body(m, rng, W, D, eave, ridge=ridge)
    string_course(m, -W, W, 29.0, 0.0)
    door(m, -14.0, 11.0, 20.0, 0.0, arch=True)
    window(m, 16.0, 10.0, 9.0, 11.0, 0.0)
    for wx in (-28.0, 0.0, 26.0):
        window(m, wx, 35.0, 8.0, 11.0, 0.0, shutters=wx != 0.0)
    roof_along_x(m, rng, -W, W, -D, 0.0, eave, ridge)
    chimney(m, rng, -W * 0.5, -D * 0.5, ridge - 8, ridge + 9)
    return m, dict(W=W, D=D, lights=[[16.0, 15.0], [0.0, 40.0]], moss=0.06)


def giebel(rng):
    m = h.Model()
    W, D, eave, ridge = 32.0, 74.0, 40.0, 70.0
    body(m, rng, W, D, eave, gable_front=True, ridge=ridge)
    door(m, -9.0, 11.0, 20.0, 0.0, arch=True)
    window(m, 14.0, 11.0, 8.0, 11.0, 0.0)
    m.ell(V(0.0, 54.0, 2.6), (5.0, 5.0, 1.0), GAP)                         # a round window under the ridge
    m.ell(V(0.0, 54.0, 3.1), (4.0, 4.0, 0.5), FIRE, kind="emit")
    for k in range(10):
        a = 2 * math.pi * k / 10
        m.ell(V(math.cos(a) * 5.6, 54.0 + math.sin(a) * 5.6, 3.4), (1.5, 1.5, 1.3), STONE_L, R=rot_z(a))
    roof_along_z(m, rng, -W, W, -D, 0.0, eave, ridge)
    chimney(m, rng, -W * 0.4, -D * 0.7, ridge - 12, ridge + 6)
    return m, dict(W=W, D=D, lights=[[14.0, 16.0], [0.0, 54.0]], moss=0.08)


def laden(rng):
    m = h.Model()
    W, D, eave, ridge = 46.0, 66.0, 40.0, 62.0
    body(m, rng, W, D, eave, ridge=ridge)
    door(m, 26.0, 11.0, 20.0, 0.0, arch=False)
    window(m, -10.0, 6.0, 26.0, 16.0, 0.0, shutters=False, arch=True)        # the wide shop window
    for k in range(int(52 / 3.0)):                                          # a teal cloth awning over it, sagging between two irons
        x = -26.0 + k * 3.0
        sag = math.sin(k / 17.0 * math.pi) * 1.2
        slab(m, V(x, 28.5 - sag * 0.3, 1.5), V(x, 25.0 - sag, 10.0), 1.6, 0.6, BANNER, (0, 1, 0.3), step=1.2)
    for sx in (-27.0, 7.0):
        log(m, V(sx, 28.0, 1.0), V(sx, 25.0, 10.5), 0.45, IRON, step=0.8)
    log(m, V(-W + 2, 26.0, 1.5), V(-W - 7, 26.0, 1.5), 0.6, IRON, step=0.8)  # the sign bracket (the sign itself is a swaying part, later)
    roof_along_x(m, rng, -W, W, -D, 0.0, eave, ridge)
    chimney(m, rng, W * 0.6, -D * 0.6, ridge - 8, ridge + 8)
    return m, dict(W=W, D=D, lights=[[-10.0, 14.0]], moss=0.05)


def halle(rng):
    m = h.Model()
    W, D, eave, ridge = 64.0, 92.0, 50.0, 92.0
    body(m, rng, W, D, eave, gable_front=True, ridge=ridge)
    for bx in (-W + 1, -22.0, 22.0, W - 1):                                 # buttresses
        y, k = 0.6, 0
        while y < eave - 6:
            m.ell(V(bx, y + 2.5, 3.5 + max(0, 8 - y * 0.25)), (4.0, 2.6, 4.0 + max(0, 6 - y * 0.2)), STONES[k % 3])
            y += 4.8
            k += 1
    door(m, 0.0, 18.0, 30.0, 0.0, arch=True, steps=2)
    for wx in (-40.0, 40.0):
        window(m, wx, 14.0, 8.0, 22.0, 0.0, shutters=False, arch=True)
    m.ell(V(0.0, 68.0, 2.6), (9.0, 9.0, 1.0), GAP)                          # the rose window: teal light, the town's
    m.ell(V(0.0, 68.0, 3.1), (8.0, 8.0, 0.5), h.TEAL, kind="emit")
    for k in range(8):
        a = 2 * math.pi * k / 8
        log(m, V(0.0, 68.0, 3.7), V(math.cos(a) * 7.6, 68.0 + math.sin(a) * 7.6, 3.7), 0.5, STONE_L, step=0.8)
    for k in range(16):
        a = 2 * math.pi * k / 16
        m.ell(V(math.cos(a) * 9.8, 68.0 + math.sin(a) * 9.8, 3.4), (2.0, 2.0, 1.5), STONE_L, R=rot_z(a))
    roof_along_z(m, rng, -W, W, -D, 0.0, eave, ridge, over=5.0)
    return m, dict(W=W, D=D, lights=[[0.0, 68.0], [-40.0, 23.0], [40.0, 23.0]], moss=0.05)


def torhaus(rng):
    m = h.Model()
    W, D, top = 22.0, 44.0, 60.0
    ashlar_z(m, rng, -W, W, 0.6, top, -D)
    ashlar_z(m, rng, -W, W, 0.6, top, 0.0)
    ashlar_x(m, rng, -D, 0.0, 0.6, top, -W)
    ashlar_x(m, rng, -D, 0.0, 0.6, top, W)
    quoins(m, -W, 0.0, top, True)
    quoins(m, W, 0.0, top, True)
    m.ell(V(0.0, top - 0.5, -D / 2), (W - 2.0, 1.0, D / 2 - 2.0), STONE)      # the walkway on top
    for x in np.arange(-W + 4, W, 9.0):                                     # merlons along the front and back
        for z in (1.0, -D + 1.0):
            m.ell(V(x, top + 4.0, z), (3.4, 4.0, 3.2), STONE_L)
    for z in np.arange(-D + 9, -4, 9.0):
        for x in (-W + 1, W - 1):
            m.ell(V(x, top + 4.0, z), (3.2, 4.0, 3.4), STONE_L)
    m.ell(V(0.0, 36.0, 2.6), (1.4, 6.0, 1.0), GAP)                           # an arrow slit with a teal guard-light behind it
    m.ell(V(0.0, 36.0, 3.0), (0.8, 5.0, 0.5), FIRE, kind="emit")
    door(m, 0.0, 10.0, 18.0, 0.0, arch=True)
    string_course(m, -W, W, 30.0, 0.0)
    return m, dict(W=W, D=D, lights=[[0.0, 36.0]], moss=0.0, plain=True)


def stall(rng):
    m = h.Model()
    W, D, eave, ridge = 118.0, 88.0, 38.0, 64.0
    body(m, rng, W, D, eave, ridge=ridge)
    door(m, -34.0, 26.0, 26.0, 0.0, arch=True, steps=0, porch=False)         # the big double door for carts and animals
    log(m, V(-34.0, 1.0, 3.8), V(-34.0, 22.0, 3.8), 0.6, BARK_D, step=0.9)   # the meeting of its two leaves
    for wx in (-90.0, -70.0, 8.0, 30.0, 52.0, 74.0, 96.0):                  # small high windows of the boxes
        window(m, wx, 20.0, 6.0, 6.0, 0.0, lit=wx in (30.0, 74.0), shutters=False)
    door(m, 60.0, 10.0, 18.0, 0.0, arch=False)                                # the tack room
    roof_along_x(m, rng, -W, W, -D, 0.0, eave, ridge)
    # the hayloft: a dormer in the roof with a door and a hoist beam, straw poking out
    hx = -34.0
    ashlar_z(m, rng, hx - 12, hx + 12, eave, eave + 18, -6.0)
    m.ell(V(hx, eave + 8.0, -3.4), (6.0, 7.0, 1.0), GAP)
    for k in range(6):
        m.ell(V(hx - 4.0 + k * 1.6, eave + 2.5 + (k % 3) * 0.4, -2.6), (1.6, 0.8, 1.0), STRAW)
    log(m, V(hx, eave + 18.0, -6.0), V(hx, eave + 18.0, 8.0), 1.0, BARK, step=1.0)
    log(m, V(hx, eave + 18.0, 8.0), V(hx, eave + 8.0, 8.0), 0.25, LINEN, step=0.6)
    for side in (-1, 1):
        slab(m, V(hx + side * 13, eave + 20, -12.0), V(hx + side * 13, eave - 1, 2.0), 1.0, 2.0, ROOF, (side, 0.6, 0.3), step=1.2)
    for k in range(5):                                                       # a stack of hay beside the door and a cart wheel leaning on the wall
        m.ell(V(-68.0 + k * 3.0, 2.2 + (k % 2) * 3.0, 6.0), (4.0, 2.4, 3.0), STRAW)
    for k in range(14):
        a = 2 * math.pi * k / 14
        m.ell(V(-4.0 + math.cos(a) * 7.0, 8.0 + math.sin(a) * 7.0, 5.0), (1.3, 1.3, 0.9), PLANK_W)
    log(m, V(-11.0, 8.0, 5.2), V(3.0, 8.0, 5.2), 0.5, BARK, step=0.8)
    log(m, V(-4.0, 1.0, 5.2), V(-4.0, 15.0, 5.2), 0.5, BARK, step=0.8)
    chimney(m, rng, 60.0, -D * 0.5, ridge - 10, ridge + 6)
    return m, dict(W=W, D=D, lights=[[30.0, 23.0], [74.0, 23.0]], moss=0.15)


# ------------------------------------------------------------------ the market round the Wächterin (forum stalls)
WINE = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("3a1022", "6a1c34", "9a3048", "c86070")])   # the order's wine red, faded cloth
OCHRE = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("4a3014", "7a5422", "b08038", "e0b866")])   # ochre cloth
PLUM = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("2a1838", "4a2c60", "71488e", "a07cbc")])   # dyed violet
FRUIT = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("4a1418", "8a2a24", "c8543a", "f09a6a")])   # apples and roots
GREEN = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("1c3420", "2e5a30", "4e8a44", "86c070")])   # herbs and greens
CLOTHS = ((BANNER, LINEN), (WINE, OCHRE), (PLUM, LINEN))


def basket(m, rng, x, y, z, goods):
    for k in range(8):
        a = 2 * math.pi * k / 8
        m.ell(V(x + math.cos(a) * 2.6, y + 1.0, z + math.sin(a) * 2.0), (1.2, 1.3, 1.0), STRAW)
    m.ell(V(x, y + 0.6, z), (2.6, 0.8, 2.0), STRAW)
    for k in range(5):
        m.ell(V(x + rng.uniform(-1.4, 1.4), y + 2.2 + rng.uniform(0, 0.8), z + rng.uniform(-1.0, 1.0)), (1.0, 1.0, 1.0), goods)


def stand(rng, variant, facing):
    """A market stall: a plank counter on trestles with a stone footing, four posts and a cloth roof in two stripes with a scalloped hem,
    baskets, jars, bolts of cloth or glinting crystals on the counter, crates behind. Built facing +z, then turned to `facing` (radians)."""
    m = h.Model()
    c1, c2 = CLOTHS[variant % 3]
    W, D = 16.0, 9.0
    for x in (-W + 2, W - 2):                                                # trestles and the counter
        for z in (-D + 2, D - 2):
            log(m, V(x, 0.6, z), V(x, 10.5, z), 0.7, BARK, step=1.0)
    for k in range(7):
        z = -D + 1.5 + k * (2 * D - 3) / 6
        slab(m, V(-W, 11.2, z), V(W, 11.2, z), 1.5, 0.7, PLANK_W if k % 2 else PLANK, (0, 1, 0), step=1.3)
    slab(m, V(-W, 9.0, D + 0.8), V(W, 9.0, D + 0.8), 1.6, 0.6, PLANK, (0, 0, 1), step=1.3)   # the front board
    for x in np.arange(-W + 2, W, 6.5):
        m.ell(V(x, 1.0, D + 1.5), (3.2, 1.0, 1.6), STONE)
    for x, z in ((-W - 1, D + 1), (W + 1, D + 1), (-W - 1, -D - 6), (W + 1, -D - 6)):     # posts
        log(m, V(x, 0.6, z), V(x, 23.5 if z > 0 else 25.0, z), 0.8, BARK_D, step=1.0)
    for x in (-W - 1, W + 1):
        log(m, V(x, 0.6, -D * 0.25), V(x, 30.5, -D * 0.25), 0.8, BARK_D, step=1.0)
    n = 9                                                                     # the cloth roof: a ridge pole, two slopes that sag between the posts
    log(m, V(-W - 3, 30.5, -D * 0.25), V(W + 3, 30.5, -D * 0.25), 0.8, BARK_D, step=1.0)
    for k in range(n + 1):
        x = -W - 2 + k * (2 * W + 4) / n
        mat = c1 if k % 2 == 0 else c2
        belly = 1.6 * math.sin(k / n * math.pi)                                # the cloth hangs lower between the end posts
        for (za, ya), (zb_, yb) in (((-D * 0.25, 30.2), (D + 4.0, 23.2 - belly)), ((-D * 0.25, 30.2), (-D - 8.0, 24.6 - belly))):
            pts = [V(x, ya + (yb - ya) * s - 1.3 * math.sin(s * math.pi) * (0.6 + belly * 0.3), za + (zb_ - za) * s) for s in np.linspace(0, 1, 6)]
            for p0, p1 in zip(pts, pts[1:]):
                slab(m, p0, p1, (2 * W + 4) / n / 2 + 0.35, 0.9, mat, (0, 1, 0.2), step=1.0)
        for zz, yy in ((D + 4.6, 22.0 - belly), (-D - 8.6, 23.4 - belly)):         # the hem: a scalloped flap hanging down
            m.ell(V(x, yy - 1.0, zz), ((2 * W + 4) / n / 2 + 0.2, 1.9 + (0.8 if k % 2 == 0 else 0.0), 0.7), mat)
    for x in (-W - 1, W + 1):                                                  # ropes from the ridge pole to the posts
        log(m, V(x, 30.0, -D * 0.25), V(x, 23.0, D + 1), 0.25, LINEN, step=0.7)
    goods = (FRUIT, h.TEAL, GREEN)[variant % 3]
    if variant % 3 == 1:                                                      # crystals and clay jars
        for k in range(4):
            x = -W + 5 + k * 7.5
            m.ell(V(x, 13.0, 2.0), (1.8, 2.0, 1.6), hut_lib.CLAY)
            m.ell(V(x + 3.0, 13.4, -2.0), (0.9, 2.4, 0.9), h.TEAL, kind="emit")
    elif variant % 3 == 2:                                                    # bolts of cloth and bundles of herbs
        for k in range(3):
            log(m, V(-W + 4 + k * 9, 12.6, -3.0), V(-W + 4 + k * 9, 12.6, 4.0), 1.6, (WINE, OCHRE, PLUM)[k], step=0.8)
        for k in range(3):
            basket(m, rng, -W + 8 + k * 9, 11.8, 5.0, GREEN)
    else:                                                                     # baskets of apples and roots
        for k in range(4):
            basket(m, rng, -W + 5 + k * 7.6, 11.8, 2.0 + (k % 2) * 3.0, FRUIT if k % 2 == 0 else GREEN)
    for k in range(3):                                                        # crates behind the counter
        x = -W + 6 + k * 10
        m.ell(V(x, 4.0, -D - 4), (4.4, 4.0, 3.6), PLANK)
        log(m, V(x - 4, 6.0, -D - 0.6), V(x + 4, 6.0, -D - 0.6), 0.35, BARK_D, step=0.8)
    Ry = h.rot_y(facing)
    for p in m.prims:
        p.c = Ry @ p.c
        p.R = Ry @ p.R
    return m, dict(W=W + 3, D=2 * D + 8, lights=[], moss=0.0, stall=True)


# ------------------------------------------------------------------ the west wall and the guide stones (stage 3c)
def mauer_ns(rng):
    """One stretch (16 px of ground) of the west wall running north-south on the outer ring: a parapet of coursed blocks, the walkway's flags
    on top, merlons along its west (void) side with the crenels between them, moss in the joints."""
    m = h.Model()
    L = 16.0 / (h.SINP * S)        # model depth of 16 px of ground
    ashlar_x(m, rng, -L - 1.0, 1.0, 0.6, 12.0, -4.0, depth=3.6)
    ashlar_x(m, rng, -L - 1.0, 1.0, 0.6, 12.0, 4.0, depth=3.6)
    for z in np.arange(-L + 3.0, 0.0, 6.5):                                 # the walkway
        m.ell(V(0.0, 12.4, z), (5.6, 0.9, 3.2), STONE_L)
    for k, z in enumerate(np.arange(-L + 4.0, 0.5, L / 2.0)):              # merlons on the west side, a crenel between
        if k % 2 == 0:
            m.ell(V(-5.0, 17.0, z), (2.8, 4.6, 4.4), STONES[k % 3])
            m.ell(V(-5.0, 21.6, z), (3.2, 0.9, 4.8), STONE_L)
    if rng.random() < 0.6:
        hut_lib.tuft(m, V(4.0, 12.6, -L * 0.4), rng, blades=4, height=3.0)
    return m, dict(W=6.0, D=L, lights=[], moss=0.0, plain=True)


def leitstein(rng, state="still"):
    """A guide stone of the town: a slender six-sided post of the Glaskamm's stone on a stepped foot, an iron band, and in its head a crystal
    of Klangstein in a stone collar. `still`: the crystal is asleep (a dim violet, it remembers its light), `wach`: it shines teal (the town
    has woken, stage 4), `tot`: dead and cracked (the lost quarter)."""
    m = h.Model()
    m.ell(V(0.0, 1.0, 0.0), (6.0, 1.4, 5.0), STONE)
    m.ell(V(0.0, 2.6, 0.0), (4.6, 1.2, 3.8), STONE_L)
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        log(m, V(math.cos(a) * 2.4, 3.0, math.sin(a) * 2.0), V(math.cos(a) * 2.0, 20.0, math.sin(a) * 1.7), 1.25, STONES[k % 3], step=1.0)
    log(m, V(0.0, 3.0, 0.0), V(0.0, 20.0, 0.0), 2.4, STONE, step=1.0)
    for y in (8.0, 17.0):
        m.ell(V(0.0, y, 0.0), (3.2, 0.7, 2.7), IRON)
    for k in range(6):                                                       # the collar the crystal sits in
        a = 2 * math.pi * k / 6
        m.ell(V(math.cos(a) * 2.6, 21.0, math.sin(a) * 2.2), (1.4, 1.6, 1.2), STONE_L)
    if state == "tot":
        m.ell(V(0.0, 22.6, 0.4), (1.4, 1.6, 1.2), hut_lib.GAP)
        m.ell(V(0.8, 23.2, 0.6), (0.7, 1.4, 0.6), STONE)
        log(m, V(-1.2, 19.0, 1.8), V(0.8, 12.0, 2.0), 0.35, hut_lib.GAP, step=0.6)
    else:
        mat = h.TEAL if state == "wach" else h.CRYSTAL
        m.ell(V(0.0, 25.0, 0.3), (2.1, 4.6, 1.8), mat, kind="emit")
        m.ell(V(1.4, 23.6, 0.7), (1.0, 2.8, 0.9), mat, kind="emit")
        m.ell(V(-1.4, 23.2, 0.5), (0.9, 2.3, 0.8), mat, kind="emit")
    return m, dict(W=6.0, D=10.0, lights=[], moss=0.0, plain=True)


TYPES = {
    "haus_a": lambda r: haus(r, 0),
    "haus_b": lambda r: haus(r, 1),
    "haus_hoch": haus_hoch,
    "giebel": giebel,
    "laden": laden,
    "verlassen_a": lambda r: haus(r, 0, abandoned=True),
    "verlassen_b": lambda r: haus(r, 1, abandoned=True),
    "halle": halle,
    "torhaus": torhaus,
    "stall": stall,
    "mauer_ns": mauer_ns,
    "leitstein": lambda r: leitstein(r, "still"),
    "leitstein_wach": lambda r: leitstein(r, "wach"),
    "leitstein_tot": lambda r: leitstein(r, "tot"),
}
for _v in range(3):  # three stalls (cloth and goods), each from the front, the back and the side (the other side is the mirror)
    for _o, _yaw in (("vorn", 0.0), ("hinten", math.pi), ("seite", -math.pi / 2)):
        TYPES["stand_%d_%s" % (_v, _o)] = (lambda v, yaw: (lambda r: stand(r, v, yaw)))(_v, _yaw)


DOORS = {"haus_a": 6.0, "haus_b": -10.0, "verlassen_a": 6.0, "verlassen_b": -10.0, "haus_hoch": -14.0, "giebel": -9.0, "laden": 26.0,
         "halle": 0.0, "torhaus": 0.0, "stall": -34.0}  # x of the front door in the model (units), as built by the types above


# ------------------------------------------------------------------ finishing
# lamplight behind glass: a calm honey tone, never the flickering fire ramp (that read as flames in the windows)
GLASS = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in ("4a3044", "8a5a3e", "c08a52", "e2b872")]
GLASS_SET = set(GLASS)


def windows_glow(arr, seed):
    """Every pane of lit glass, separately per window: one even warm tone, a little brighter in its middle, the top row in the lintel's
    shadow and the side columns a step darker (the reveal of the thick wall); a few panes dimmer than others (not every lamp burns as bright)."""
    fire = {tuple(c[:3]) for c in h.RAMPS[FIRE]}
    H, W = arr.shape[:2]
    mask = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in fire:
                mask[y, x] = True
    seen = np.zeros_like(mask)
    out = arr.copy()
    for y0 in range(H):
        for x0 in range(W):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            stack, comp = [(x0, y0)], []
            seen[y0, x0] = True
            while stack:
                x, y = stack.pop()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < W and 0 <= ny < H and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((nx, ny))
            xs = [p[0] for p in comp]
            ys = [p[1] for p in comp]
            gx0, gx1, gy0, gy1 = min(xs), max(xs), min(ys), max(ys)
            cx, cy = (gx0 + gx1) / 2.0, (gy0 + gy1) / 2.0
            hw, hh = max(1.0, (gx1 - gx0) / 2.0), max(1.0, (gy1 - gy0) / 2.0)
            dim = hsh(gx0, gy0, seed + 77) < 0.3
            big = len(comp) > 30
            for x, y in comp:
                u, v = (x - cx) / hw, (y - cy) / hh
                b = 2
                if y == gy0 or abs(u) > 0.8:
                    b = 1
                elif big and u * u + v * v < 0.18 and bayer(x, y) < 0.6:
                    b = 3
                if dim:
                    b = max(0, b - 1)
                out[y, x, :3] = GLASS[b]
    return out


def turn(m, yaw, about=(0.0, 0.0), shift=(0.0, 0.0)):
    """Turns the model about the point (x, z) = `about` and moves it by `shift` afterwards."""
    Ry = h.rot_y(yaw)
    for p in m.prims:
        c = p.c - V(about[0], 0.0, about[1])
        p.c = Ry @ c + V(shift[0], 0.0, shift[1])
        p.R = Ry @ p.R


def attach(m, part, yaw, at):
    """Draws `part` (made facing +z at z = 0) turned by `yaw` and moved to `at` (x, z) into `m`."""
    turn(part, yaw, shift=at)
    m.prims.extend(part.prims)


def other_sides(m, rng, W, D, eave, info):
    """The sides the street sees when the house is turned: a back door and small windows in the back wall, a window in each gable end."""
    if info.get("plain"):
        return
    back = h.Model()
    door(back, W * 0.35, 9.0, 17.0, 0.0, arch=False, steps=0, porch=False)
    for k, wx in enumerate((-W * 0.45, W * 0.0 if W > 50 else -W * 0.05)):
        window(back, wx - (6.0 if k else 0.0), 12.0, 6.0, 8.0, 0.0, lit=k == 0, shutters=k == 0, boarded=info.get("abandoned", False), rng=rng)
    attach(m, back, math.pi, (0.0, -D))
    for side in (-1, 1):
        gable = h.Model()
        window(gable, 0.0, 14.0, 6.0, 8.0, 0.0, lit=side > 0, shutters=False, boarded=info.get("abandoned", False), rng=rng)
        attach(m, gable, side * math.pi / 2, (side * W, -D / 2.0))


VIEWS = {"s": 0.0, "n": math.pi, "e": math.pi / 2}  # front, back, the east gable end (west = the east one mirrored in the game)
# turned halfway, for diagonal ways (48 degrees in the model: front and side both show, the door stays in sight; the true yaw for a
# 45-degree street on the squashed ground, atan(1 / SINP), hid the front almost entirely); se = the front looks south-east (house north-west of its way), ne = north-east (the back shows); the game
# mirrors them for sw / nw
DIAG_YAW = math.radians(48.0)
DIAG = {"se": DIAG_YAW, "ne": math.pi - DIAG_YAW}
DIAG_TYPES = ("haus_a", "haus_b", "haus_hoch", "giebel", "laden", "verlassen_a", "verlassen_b")


def eave_shadow(arr, mask, reach=7, strength=0.62):
    """The shadow a roof (or a cloth) throws onto what lies under it: in every column the pixels just below the covering are darkened,
    most right under its edge, fading out with a dither (no light comes from below)."""
    H, W = mask.shape
    out = arr.copy()
    for x in range(W):
        col = mask[:, x]
        for y in range(1, H):
            if col[y - 1] and not col[y]:
                for k in range(reach):
                    yy = y + k
                    if yy >= H or col[yy] or arr[yy, x, 3] < 200:
                        break
                    s = strength * (1.0 - k / reach)
                    if s * 1.25 > bayer(x, yy) * 0.9 + 0.05:
                        out[yy, x, :3] = (arr[yy, x, :3] * (1.0 - s)).astype(np.uint8)
    return out


def wall_pass(arr, seed):
    """Lays the walls in the paving's stone: courses 5 px high, blocks 7-12 px long, every course offset, dark joints, a lit top and left
    edge and a darker bottom on every block, each block its own tone. The renderer's band (how much light the wall gets) stays the light,
    so fronts, shaded sides and the cast shadows keep their depth."""
    lut = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[STONE])}
    H, W = arr.shape[:2]
    out = arr.copy()
    rnd = lambda a, b, s: ((a * 374761393 + b * 668265263 + s * 2246822519) & 0xFFFFFFFF) / 4294967295.0  # noqa: E731
    for y in range(H):
        course = y // 5
        cy = y % 5
        width = 7 + int(rnd(course, 1, seed) * 6)
        off = int(rnd(course, 2, seed) * width)
        for x in range(W):
            if not arr[y, x, 3]:
                continue
            b = lut.get(tuple(int(v) for v in arr[y, x, :3]))
            if b is None:
                continue
            bx = (x + off) // width
            cx = (x + off) % width
            if cy == 0 or cx == 0:
                out[y, x, :3] = MASON[0][:3] if b < 3 else MASON[1][:3]
                continue
            tone = b + 1 + (rnd(bx, course, seed + 7) - 0.5) * 1.1
            if cy == 1 or cx == 1:
                tone += 0.9
            elif cy == 4 or cx == width - 1:
                tone -= 0.6
            if rnd(bx, course, seed + 9) > 0.93 and cy == 2:
                tone -= 1.4  # a chipped or weathered stone
            out[y, x, :3] = MASON[max(0, min(5, int(round(tone))))][:3]
    return out


def mask_of(arr, mats):
    cols = {tuple(c[:3]) for mat in mats for c in h.RAMPS[mat]}
    H, W = arr.shape[:2]
    return np.array([[arr[y, x, 3] > 0 and tuple(int(v) for v in arr[y, x, :3]) in cols for x in range(W)] for y in range(H)])


def build(name, seed, view="s"):
    rng = rng_for(seed)
    m, info = TYPES[name](rng)
    W, D = info["W"], info["D"]
    extra = {}
    if not info.get("stall"):
        other_sides(m, rng_for(seed + 1), W, D, 0, info)
        if view in DIAG:  # turned about the middle; the front corner of its box is moved to z = 0, the box gives the footprint
            Ry = h.rot_y(DIAG[view])
            rel = [Ry @ V(x, 0.0, z) for x, z in ((-W, D / 2.0), (W, D / 2.0), (W, -D / 2.0), (-W, -D / 2.0))]
            zmax = max(r_[2] for r_ in rel)
            zmin = min(r_[2] for r_ in rel)
            xmax = max(abs(r_[0]) for r_ in rel)
            dm = Ry @ V(DOORS.get(name, 0.0), 0.0, D / 2.0)
            turn(m, DIAG[view], about=(0.0, -D / 2.0), shift=(0.0, -zmax))
            g_ = grow_of(name)
            k_ = S * g_
            extra = {"diag": True, "door": [round(float(dm[0]) * k_, 1), round(float(dm[2] - zmax) * h.SINP * k_, 1)],
                     "poly": [[round(float(r_[0]) * k_, 1), round(float(r_[2] - zmax) * h.SINP * k_, 1)] for r_ in rel]}
            W, D = xmax, zmax - zmin
        elif view != "s":  # turned about the house's middle, then moved so the new front edge is at z = 0 again
            yaw = VIEWS[view]
            half = D / 2.0 if view == "n" else W
            turn(m, yaw, about=(0.0, -D / 2.0), shift=(0.0, -half))
            if view == "e":
                W, D = D / 2.0, 2.0 * W
    g = grow_of(name)
    for p_ in m.prims:
        p_.c = p_.c * g
        p_.r = p_.r * g
    W, D = W * g, D * g
    raw = to_array(hut_lib.render(m, CANVAS[0], CANVAS[1], CANVAS[2]))
    cover = mask_of(raw, (ROOF, BARK_D) if not info.get("stall") else (BANNER, LINEN, WINE, OCHRE, PLUM))
    arr = hut_lib.roof_pass(raw, seed, moss=info["moss"], shadow=6)
    arr = eave_shadow(arr, cover, reach=8 if not info.get("stall") else 6)
    arr = wall_pass(arr, seed)
    arr = windows_glow(arr, seed)
    arr = hut_lib.grain(arr, seed, amount=0.5, mats=(PLANK, PLANK_W, BARK, SHUT))
    ys, xs = np.nonzero(arr[..., 3] > 0)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
    foot_w, foot_d = int(round(2 * W * S)), int(round(D * h.SINP * S))
    pad = 2
    y1 = max(y1, CANVAS[2] + 3)
    arr = arr[max(0, y0 - pad):y1, max(0, x0 - pad):x1 + pad]
    feet = (CANVAS[0] // 2 - max(0, x0 - pad), CANVAS[2] - max(0, y0 - pad))
    hut_lib.soft_shadow(arr, feet[0], feet[1] - foot_d / 2.0, foot_w / 2.0 + 4, foot_d / 2.0 + 3)
    glow = glow_of(arr, (FIRE, h.TEAL, h.CRYSTAL))
    for yy, xx in zip(*np.nonzero(arr[..., 3] > 0)):
        if tuple(int(c) for c in arr[yy, xx, :3]) in GLASS_SET:
            glow[yy, xx] = arr[yy, xx]
    gy, gx = np.nonzero(glow[..., 3] > 0)
    lights = [[int(gx.mean()), int(gy.mean())]] if len(gx) else []  # one warm light where the lit glass is
    return arr, glow, dict({"size": [arr.shape[1], arr.shape[0]], "feet": list(feet), "foot": [foot_w, foot_d], "lights": lights}, **extra)


def main():
    hut_lib.ROOF_TONES = SLATE
    OUT.mkdir(parents=True, exist_ok=True)
    data = {"about": "Written by tools/art_hallgrat_houses.py: per picture its size, feet (middle of the front edge on the ground, px in the picture), foot (footprint w x d in px) and the window lights (px in the picture).", "types": {}}
    shown = []
    for i, name in enumerate(TYPES):
        views = ("s",) if name.startswith(("stand_", "mauer", "leitstein")) else ("s", "n", "e") + (("se", "ne") if name in DIAG_TYPES else ())
        for view in views:
            key = name if view == "s" else "%s_%s" % (name, view)
            arr, glow, info = build(name, 3100 + i * 17, view)
            save(OUT / f"{key}.png", arr)
            save(OUT / f"{key}_glow.png", glow)
            data["types"][key] = info
            shown.append(arr)
            print(key, info["size"], "foot", info["foot"])
    data["doors"] = {k: round(v * S * grow_of(k), 1) for k, v in DOORS.items()}  # the front door's x (px from the feet) of every front view, for the door paths
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image
        wsum = sum(a.shape[1] for a in shown) + 8 * len(shown)
        hmax = max(a.shape[0] for a in shown)
        comp = Image.new("RGBA", (wsum, hmax), (58, 110, 70, 255))
        x = 0
        for a in shown:
            comp.alpha_composite(Image.fromarray(a), (x, hmax - a.shape[0]))
            x += a.shape[1] + 8
        comp.resize((comp.width * 3, comp.height * 3), Image.NEAREST).save(png[0])


if __name__ == "__main__":
    main()
