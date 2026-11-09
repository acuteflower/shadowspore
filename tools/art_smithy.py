#!/usr/bin/env python3
"""The smithy (piece `smithy`, docs/torben_konzept.md section 6): Torben's building. Built like the rest of the town (ellipsoids through art_hero3d / hut_lib, the renewed
hut's warm violet wood), but a different form on purpose: stone, not logs.

  * a stone hall with a steep SLATE GABLE facing the street (the other buildings have single-slope roofs), open at the front under a tie beam, stone piers at the corners,
  * the forge on its right: a squat hearth block with a stone-arched, glowing mouth, a hood that narrows into a ROUND TAPERING CHIMNEY TOWER (iron hoops, corbelled cap)
    that stands taller than anything in the town,
  * inside: the anvil on an oak stump, a stone quench trough, the bellows at the hearth's flank, a tool wall, ore, coal and iron stacked.
Its pieces: smithy.png (+ _glow: only the fire, animated: 6 flicker frames side by side), _pad (the soot-black trodden ground), _spill (forge light on the floor), parts (lantern,
anvil sign, pennant), wear overlays (soot, coal and ore, slag heap, moss, neglect).

    python3 tools/art_smithy.py [preview.png]   writes assets/town/smithy*.png and prints the numbers data/town.json needs; with --json also writes the piece into data/town.json
Run after tools/art_town.py (it only adds). Needs numpy and PIL."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import art_town as T  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, bayer, fbm, glow_of, grain, hsh, log, rng_for, save, slab, to_array, V  # noqa: E402
import hut_yard as yard  # noqa: E402

T.y = yard
hut_lib.set_fresh()
STEEL = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("1f2438", "465170", "8190b4", "cfd9f0")])  # bright worked steel: anvil face, hammer heads, tongs (the dark IRON would vanish against the dark stone)
OUT = T.OUT
UP = T.UNITS_PER_PX
FW, FH, GROUND = 152, 140, 126
W = 60.8                                   # half the foot's width (112 px)
BACK, FRONT = -UP * 38 + 3.0, -3.0         # the foot's depth (38 px)
HALL_BACK = -54.0
GROUND_Y = 0.9
TOWER = (42.0, -74.0)                      # centre of the chimney tower (x, z)
TOWER_TOP = 76.0
HALL_X0, HALL_X1 = -58.0, 14.0             # the hall's walls
EAVE_Y, RIDGE_Y = 33.0, 57.0
RIDGE_X = (HALL_X0 + HALL_X1) / 2.0
ANVIL = (-12.0, -16.0)
SOOT_STONE = (STONE, STONE, STONE_L)  # mostly the dark stones: a forge's walls are black with age
INFO = T.INFO
K = 0  # the flicker frame being drawn (the glow sheet has 6)
FRAMES = 6


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def proj(x, y, z):
    """Where a model point lands in the piece's picture, relative to the middle of the foot's front edge (px; up is negative)."""
    return (x * h.SCALE, -(y * h.COSP - z * h.SINP) * h.SCALE)


# ------------------------------------------------------------------ stone work
def ashlar_z(m, rng, x0, x1, y0, y1, z, depth=3.4, flip=False):
    """A stone wall facing +z: courses of rounded blocks, every row offset."""
    y, row = y0, 0
    while y < y1 - 0.6:
        hgt = rng.uniform(4.6, 5.8)
        x = x0 - (row % 2) * 3.6 - rng.uniform(0, 2.4)
        while x < x1 - 0.5:
            w = rng.uniform(6.0, 10.0)
            lo, hi = max(x, x0 - 0.4), min(x + w, x1 + 0.4)
            if hi - lo > 2.5:
                m.ell(V((lo + hi) / 2, min(y + hgt / 2, y1 - 1.2), z + rng.uniform(-0.5, 0.5)), ((hi - lo) / 2 * 0.99, min(hgt, y1 - y) / 2 * 0.97, depth), SOOT_STONE[(row + int(x * 0.37)) % 3])
            x += w
        y += hgt * 0.93
        row += 1


def ashlar_x(m, rng, z0, z1, y0, y1, x, depth=3.4):
    """The same, a wall facing +x or -x (blocks long in z)."""
    y, row = y0, 0
    while y < y1 - 0.6:
        hgt = rng.uniform(4.6, 5.8)
        z = z0 - (row % 2) * 3.6 - rng.uniform(0, 2.4)
        while z < z1 - 0.5:
            w = rng.uniform(6.0, 10.0)
            lo, hi = max(z, z0 - 0.4), min(z + w, z1 + 0.4)
            if hi - lo > 2.5:
                m.ell(V(x + rng.uniform(-0.5, 0.5), min(y + hgt / 2, y1 - 1.2), (lo + hi) / 2), (depth, min(hgt, y1 - y) / 2 * 0.97, (hi - lo) / 2 * 0.99), SOOT_STONE[(row + int(z * 0.37)) % 3])
            z += w
        y += hgt * 0.93
        row += 1


def pier(m, rng, x, z, y1, r=4.6):
    """A square-ish stone pier of stacked blocks, a flat capstone on top."""
    y = 0.4
    row = 0
    while y < y1 - 3.5:
        hgt = rng.uniform(4.4, 5.4)
        m.ell(V(x + rng.uniform(-0.5, 0.5), y + hgt / 2, z + rng.uniform(-0.4, 0.4)), (r + rng.uniform(-0.4, 0.4), hgt / 2 * 0.97, r + rng.uniform(-0.4, 0.4)), SOOT_STONE[row % 3])
        y += hgt * 0.93
        row += 1
    m.ell(V(x, y1 - 1.2, z), (r + 1.5, 1.4, r + 1.5), STONE_L)


def tower_rings(m, rng, cx, cz, y0, y1, r0, r1):
    """The round chimney tower: rings of wedge-shaped stones, narrowing upward, every course turned a little."""
    y, row = y0, 0
    while y < y1:
        t = (y - y0) / (y1 - y0)
        r = r0 + (r1 - r0) * t
        hgt = rng.uniform(4.6, 5.6)
        n = max(8, int(2 * math.pi * r / 6.2))
        off = row * 0.37 + rng.uniform(0, 0.3)
        for k in range(n):
            a = off + 2 * math.pi * k / n
            if math.sin(a) < -0.9 and k % 2:  # the back is never seen: thin it out
                continue
            m.ell(V(cx + math.cos(a) * r, y + hgt / 2, cz + math.sin(a) * r), (math.pi * r / n * 1.04, hgt / 2 * 0.98, 3.7 - 0.5 * t), SOOT_STONE[(k + row) % 3], R=h.rot_y(-(a + math.pi / 2)))
        y += hgt * 0.94
        row += 1


def iron_hoop(m, cx, cz, y, r):
    n = max(10, int(2 * math.pi * r / 2.4))
    for k in range(n):
        a = 2 * math.pi * k / n
        if math.sin(a) > -0.5:
            m.ell(V(cx + math.cos(a) * (r + 4.0), y, cz + math.sin(a) * (r + 4.0)), (1.7, 1.2, 1.4), IRON, R=h.rot_y(-(a + math.pi / 2)))
    for k in (n // 2 - 2, n // 2, n // 2 + 2):  # rivets
        a = 2 * math.pi * k / n
        m.ell(V(cx + math.cos(a) * (r + 5.2), y, cz + math.sin(a) * (r + 5.2)), (0.7, 0.7, 0.7), STONE_L)


BRASS_OR_IRON = IRON


def gable_roof(m, rng, z0, z1):
    """A steep slate gable: two slopes of long slabs running down from the ridge, a ridge beam, iron finials. `roof_pass` turns the ROOF pixels into slate shingles."""
    half = (HALL_X1 - HALL_X0) / 2.0 + 6.0
    for side in (-1, 1):
        a = V(RIDGE_X, RIDGE_Y, 0)
        b = V(RIDGE_X + side * half, EAVE_Y - 1.0, 0)
        axis = b - a
        normal = np.cross(axis, V(0, 0, 1))
        normal = normal / np.linalg.norm(normal)
        if normal[1] < 0:
            normal = -normal
        z = z0 + 3.4
        while z < z1:
            jitter = rng.uniform(-0.5, 0.5)
            slab(m, a + V(0, 0.4 * jitter, z), b + V(0, 0.4 * jitter, z), 3.6, 1.0, ROOF, tuple(normal), step=1.4)
            z += 3.6 * 2 - 0.6
    log(m, V(RIDGE_X, RIDGE_Y + 1.1, z0), V(RIDGE_X, RIDGE_Y + 1.1, z1), 1.3, STONE, step=1.2)
    for side in (-1, 1):                                                                            # the barge boards along the front edge: the roof is visibly in front of the gable wall
        log(m, V(RIDGE_X, RIDGE_Y - 0.4, z1 + 0.6), V(RIDGE_X + side * half, EAVE_Y - 2.4, z1 + 0.6), 1.35, BARK_D, step=1.1)
        log(m, V(RIDGE_X, RIDGE_Y - 0.4, z1 + 0.6), V(RIDGE_X + side * half, EAVE_Y - 2.4, z1 + 0.6), 0.5, BARK, step=1.6)
    m.ell(V(RIDGE_X, RIDGE_Y + 2.2, z1 + 0.2), (1.1, 1.6, 1.1), STEEL)


def gable_face(m, rng, z):
    """The front gable under the roof: vertical dark boards cut to the roof's triangle, a vent with an iron grating."""
    x_mid = RIDGE_X
    half = (HALL_X1 - HALL_X0) / 2.0 - 1.0
    x = HALL_X0 + 1.5
    i = 0
    while x < HALL_X1 - 0.5:
        k = 1.0 - abs(x - x_mid) / half
        top = EAVE_Y + 0.2 + (RIDGE_Y - EAVE_Y - 1.5) * max(0.0, k)
        slab(m, V(x, EAVE_Y - 2.0, z + rng.uniform(-0.2, 0.2)), V(x, top, z), 2.1, 0.9, PLANK_W if i % 3 == 1 else PLANK, (0, 0, 1), step=1.3)
        x += 4.1
        i += 1
    ex, ey = x_mid, EAVE_Y + 9.0                                                                  # an anvil with a hammer across it, in iron, on the gable
    m.ell(V(ex, ey - 2.4, z + 0.9), (4.2, 0.9, 0.7), IRON)
    m.ell(V(ex, ey - 0.8, z + 0.9), (2.0, 1.0, 0.7), IRON)
    m.ell(V(ex, ey + 1.0, z + 0.9), (6.0, 1.1, 0.8), IRON)
    m.ell(V(ex + 7.0, ey + 0.9, z + 0.9), (2.6, 0.7, 0.6), IRON)
    log(m, V(ex - 6.0, ey + 6.4, z + 1.0), V(ex + 5.0, ey + 2.2, z + 1.0), 0.6, BARK_D, step=0.8)
    m.ell(V(ex + 5.6, ey + 2.0, z + 1.0), (1.8, 1.2, 1.0), IRON)
    m.ell(V(x_mid, RIDGE_Y - 5.0, z + 0.6), (1.2, 1.7, 0.6), GAP)                                  # a little vent under the ridge


# ------------------------------------------------------------------ the pieces of work
FACADE_Z = -12.0                          # the hall's front wall
DOOR_X0, DOOR_X1 = -30.0, -2.0            # the round-arched doorway
HEARTH_X0, HEARTH_X1 = 24.0, 60.5
HEARTH_Z0, HEARTH_Z1 = -64.0, -30.0
HEARTH_TOP = 20.0


def apron(m, rng):
    """Flagstones: the forging yard in front of the hearth and the doorway, a few worn smooth, soot in the joints."""
    for x in np.arange(-4.0, 60.0, 7.4):
        for z in np.arange(-30.0, -1.0, 6.8):
            if x < 14 and z < FACADE_Z + 3:
                continue
            m.ell(V(x + rng.uniform(-0.6, 0.6), GROUND_Y - 0.15, z + rng.uniform(-0.5, 0.5)), (rng.uniform(3.2, 3.6), 0.65, rng.uniform(3.0, 3.4)), SOOT_STONE[int(hsh(x, z, 3) * 3)])
    for x in np.arange(DOOR_X0 + 3.0, DOOR_X1, 7.0):                                              # the threshold
        m.ell(V(x, GROUND_Y - 0.1, FACADE_Z + 4.0), (3.5, 0.7, 3.3), STONE_L)


def hall_walls(m, rng):
    ashlar_z(m, rng, HALL_X0, HALL_X1, 0.6, EAVE_Y + 0.5, HALL_BACK, depth=3.8)
    ashlar_x(m, rng, HALL_BACK, FACADE_Z, 0.6, EAVE_Y + 0.5, HALL_X0 + 2.4, depth=3.8)
    ashlar_x(m, rng, HALL_BACK, FACADE_Z, 0.6, EAVE_Y + 0.5, HALL_X1 - 2.0, depth=3.8)
    # the front: two stone masses either side of the arched doorway, the arch itself, and the stone gable above it
    ashlar_z(m, rng, HALL_X0, DOOR_X0, 0.6, EAVE_Y + 0.5, FACADE_Z, depth=3.8)
    ashlar_z(m, rng, DOOR_X1, HALL_X1, 0.6, EAVE_Y + 0.5, FACADE_Z, depth=3.8)
    cx, spring, r = (DOOR_X0 + DOOR_X1) / 2.0, 15.0, (DOOR_X1 - DOOR_X0) / 2.0
    ashlar_z(m, rng, DOOR_X0, DOOR_X1, spring + r + 2.4, EAVE_Y + 0.5, FACADE_Z, depth=3.8)         # over the arch
    for sx in (-1, 1):
        ashlar_z(m, rng, cx + sx * r - (0 if sx > 0 else 3.5), cx + sx * r + (3.5 if sx > 0 else 0), spring, spring + 4.5, FACADE_Z, depth=3.8)
    m.ell(V(cx, 7.0, FACADE_Z - 1.6), ((DOOR_X1 - DOOR_X0) / 2.0, 7.6, 3.0), GAP)                      # the dark inside the doorway
    m.ell(V(cx, spring + 3.0, FACADE_Z - 1.6), (r - 0.4, r - 1.6, 3.0), GAP)
    for k in range(17):                                                                           # the arch: wedge stones
        a = math.pi * k / 16
        m.ell(V(cx + math.cos(a) * (r + 1.6), spring + math.sin(a) * (r + 1.6), FACADE_Z + 1.2), (2.7, 2.7, 3.1), STONE_L if k % 2 else STONE, R=rot_z(a - math.pi / 2))
    for sx in (-1, 1):                                                                            # jamb stones, the lower ones big
        for k in range(3):
            m.ell(V(cx + sx * (r + 1.6), 2.6 + k * 4.4, FACADE_Z + 1.4), (2.6, 2.3, 3.0), STONE_L if k % 2 else STONE)
    # the glow inside: a banked fire at the back of the hall, seen through the door
    m.ell(V(cx + 3.0, 4.0, FACADE_Z - 3.0), (4.4, 2.2, 0.8), FIRE, kind="emit")                  # a banked fire deep inside, seen through the door
    m.ell(V(cx - 2.0, 2.8, FACADE_Z - 2.6), (2.8, 1.4, 0.7), FIRE, kind="emit")
    # the stone gable: courses cut to the roof's triangle
    half = (HALL_X1 - HALL_X0) / 2.0
    y, row = EAVE_Y + 0.5, 0
    while y < RIDGE_Y - 4.0:
        hgt = rng_for(7).uniform(4.6, 5.4)
        k = max(0.0, 1.0 - (y + hgt - EAVE_Y) / (RIDGE_Y - EAVE_Y))
        hw = half * k - 1.0
        if hw > 3.0:
            ashlar_z(m, rng, RIDGE_X - hw, RIDGE_X + hw, y, y + hgt + 0.6, FACADE_Z, depth=3.6)
        y += hgt * 0.93
        row += 1
    # an anvil-and-hammer emblem in bright steel on the gable
    ex, ey, z = RIDGE_X, EAVE_Y + 10.5, FACADE_Z + 3.6
    m.ell(V(ex, ey - 3.2, z), (5.4, 1.1, 1.0), STEEL)
    m.ell(V(ex, ey - 1.0, z), (2.6, 1.4, 1.0), STEEL)
    m.ell(V(ex, ey + 1.4, z), (8.0, 1.5, 1.1), STEEL)
    m.ell(V(ex + 9.2, ey + 1.3, z), (3.4, 1.0, 0.9), STEEL)
    log(m, V(ex - 7.0, ey + 8.4, z + 0.3), V(ex + 6.0, ey + 3.0, z + 0.3), 0.75, BARK_D, step=0.8)
    m.ell(V(ex + 6.8, ey + 2.7, z + 0.3), (2.3, 1.6, 1.3), STEEL)
    # the leaves of the door, folded flat against the wall either side: banded planks with iron straps and big hinges
    for x0, x1 in ((DOOR_X0 - 14.5, DOOR_X0 - 1.6), (DOOR_X1 + 1.6, DOOR_X1 + 14.5)):
        x = x0 + 1.5
        i = 0
        while x < x1:
            slab(m, V(x, 0.9, FACADE_Z + 5.4), V(x, 24.0 + rng.uniform(-0.3, 0.3), FACADE_Z + 5.4), 1.55, 0.9, PLANK_W if i % 3 == 1 else PLANK, (0, 0, 1), step=1.3)
            x += 3.0
            i += 1
        for yy in (5.0, 18.0):
            log(m, V(x0, yy, FACADE_Z + 6.5), V(x1, yy, FACADE_Z + 6.5), 0.7, IRON, step=0.9)
        for sx in (x0 + 1.0, x1 - 1.0):
            m.ell(V(sx, 5.0, FACADE_Z + 7.0), (0.7, 1.4, 0.5), IRON)


def anvil(m, x, z):
    log(m, V(x, 0.9, z), V(x, 11.0, z), 6.2, BARK, step=1.0, taper=0.9)                         # an oak stump
    yard.cap(m, V(x, 11.4, z), (0, 1, 0), 5.9, PLANK_W)
    m.ell(V(x, 12.8, z), (5.4, 1.2, 2.8), STEEL)                                                  # foot
    m.ell(V(x, 15.0, z), (3.2, 2.1, 2.4), STEEL)                                                  # waist
    m.ell(V(x, 17.8, z), (10.0, 1.9, 3.8), STEEL)                                                 # face
    m.ell(V(x + 10.6, 17.7, z), (5.0, 1.1, 1.7), STEEL)                                           # horn
    m.ell(V(x + 14.0, 17.4, z), (2.2, 0.9, 1.1), STEEL)
    m.ell(V(x - 10.0, 17.6, z), (2.6, 1.1, 2.8), STEEL)                                           # heel
    m.ell(V(x - 2.0, 19.8, z), (1.4, 0.5, 1.7), STONE_L)                                         # a worn bright patch on the face
    m.ell(V(x + 4.0, 19.6, z + 0.5), (2.0, 0.5, 1.0), FIRE, kind="emit")                          # a piece still hot


def trough(m, rng, x, z):
    """A quench trough: a basin of dressed blocks with dark water, a bucket beside it."""
    for sx in (-1, 1):
        m.ell(V(x + sx * 9.0, 4.4, z), (2.6, 4.4, 5.8), STONE_L)
    for sz in (-1, 1):
        m.ell(V(x, 4.4, z + sz * 4.8), (9.0, 4.4, 2.4), STONE)
    m.ell(V(x, 7.6, z), (7.4, 0.8, 3.9), SKY)                                                    # the water
    m.ell(V(x - 2.0, 8.1, z - 0.4), (2.2, 0.3, 1.0), SKY)
    T.barrel(m, (x - 14.0, 0.9, z - 0.5), 5.2, 10.5)                                              # the water barrel
    log(m, V(x - 14.0, 12.0, z - 0.5), V(x - 6.0, 11.0, z + 1.0), 0.5, IRON, step=0.8)           # a dipper


def bellows(m, x, z):
    """The bellows at the hearth's flank: two leather halves with ribs, a wooden lever, an iron nozzle into the hearth."""
    base = V(x, 5.0, z)
    slab(m, base + V(0, -0.6, -4.5), base + V(0, -0.6, 6.5), 4.4, 0.9, BARK, (0, 1, 0), step=1.2)
    for k in range(6):
        t = k / 5.0
        rx = 4.2 - 0.6 * abs(t - 0.5) * 2
        m.ell(base + V(0, 1.6 + 1.5 * t, 0.0 + 4.4 * t), (rx, 1.6, 1.3), CLAY if k % 2 else PLANK_W)
        m.ell(base + V(0, 1.7 + 1.5 * t, 0.0 + 4.4 * t), (rx + 0.5, 0.35, 1.4), IRON)
    slab(m, base + V(0, 4.8, 6.5), base + V(0, 6.2, -4.0), 4.0, 0.9, BARK, (0, 1, 0), step=1.2)
    log(m, base + V(0, 5.4, -3.0), base + V(-0.4, 17.0, -9.5), 0.85, BARK_D, step=0.9)            # the lever, up and back
    m.ell(base + V(-0.4, 17.6, -9.7), (1.5, 1.2, 1.3), IRON)
    log(m, base + V(1.0, 1.8, -4.0), base + V(6.0, 1.8, -9.0), 0.8, IRON, step=0.9)                # the nozzle pipe into the hearth flank


def yard_goods(m, rng):
    """Ore, coal and iron stacked in the corner by the hall: what a smith's yard looks like."""
    ox, oz = -51.5, -4.0
    for k in range(20):                                                                           # the heap of ore: rust-dark lumps with stone
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 7.0)
        m.ell(V(ox + math.cos(a) * rr, 1.5 + max(0.0, 5.0 - rr * 0.7) + rng.uniform(0, 1.0), oz + math.sin(a) * rr * 0.7), (rng.uniform(1.5, 2.8), rng.uniform(1.2, 2.0), rng.uniform(1.4, 2.5)), CLAY if k % 3 else IRON)
    for k in range(12):                                                                           # coal beside it, in a low timber frame
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 5.0)
        m.ell(V(ox + 14.5 + math.cos(a) * rr, 2.8 + max(0.0, 3.4 - rr * 0.5), oz + 2.0 + math.sin(a) * rr * 0.7), (rng.uniform(1.0, 1.9), rng.uniform(0.9, 1.5), rng.uniform(1.0, 1.8)), GAP if k % 2 else SOIL)
    for sz in (-1, 1):
        slab(m, V(ox + 8.0, 0.9, oz + 2.0 + sz * 5.0), V(ox + 21.5, 0.9 + 4.4, oz + 2.0 + sz * 5.0), 0.8, 2.2, BARK, (0, 0, 1), step=1.2)
    for row in range(3):                                                                          # iron bars, stacked on a stone ledge beside the right leaf
        for k in range(4 - row):
            m.ell(V(HALL_X1 - 1.5 - k * 4.6 - row * 2.3 + 4.0, 2.2 + row * 2.6, -5.0), (2.0, 1.1, 4.4), IRON, R=h.rot_y(math.pi / 2))
    m.ell(V(HALL_X1 + 4.5, 0.9, -5.0), (7.5, 0.7, 5.4), STONE_L)


def fire_mouth(m, mx, hz1):
    """The fire in the hearth's mouth: a bed of glowing coals and flame tongues whose heights change with the flicker frame K."""
    f = lambda ph, a=0.16: 1.0 + a * math.sin(K * 1.3 + ph)  # noqa: E731
    m.ell(V(mx, 6.0, hz1 + 2.2), (8.8 * f(0), 4.4 * f(1.2), 1.3), FIRE, kind="emit")
    m.ell(V(mx, 4.6, hz1 + 2.9), (6.2 * f(2.0), 2.8 * f(3.1), 1.3), FIRE, kind="emit")
    for j, (dx, ph) in enumerate(((-5.5, 0.3), (-2.0, 1.9), (1.8, 3.4), (5.6, 4.8))):
        hgt = 4.4 + 3.2 * (0.5 + 0.5 * math.sin(K * 1.6 + ph * 1.3)) + 1.4 * (j % 2)
        m.ell(V(mx + dx, 6.0 + hgt / 2, hz1 + 3.1), (1.5, hgt / 2, 0.9), FIRE, kind="emit")


def hearth(m, rng):
    """The forge: a broad hearth block, a hood that narrows into the chimney tower. The mouth is a wide stone arch with a glowing fire and a dark gap behind it."""
    hx0, hx1, hz0, hz1, top = HEARTH_X0, HEARTH_X1, HEARTH_Z0, HEARTH_Z1, HEARTH_TOP
    ashlar_z(m, rng, hx0, hx1, 0.6, top, hz1, depth=3.8)
    ashlar_x(m, rng, hz0, hz1, 0.6, top, hx1 - 0.6, depth=3.6)
    ashlar_x(m, rng, hz0, hz1, 0.6, top, hx0 + 0.6, depth=3.6)
    mx = (hx0 + hx1) / 2.0
    m.ell(V(mx, 9.0, hz1 + 0.8), (10.2, 8.2, 2.0), GAP)
    fire_mouth(m, mx, hz1)
    for k in range(13):
        a = math.pi * k / 12
        m.ell(V(mx + math.cos(a) * 11.4, 7.4 + math.sin(a) * 9.4, hz1 + 1.6), (2.1, 2.1, 2.2), STONE_L if k % 2 else STONE)
    m.ell(V(mx, 17.4, hz1 + 1.6), (2.6, 2.0, 2.4), STONE_L)
    for sx in (-1, 1):
        m.ell(V(mx + sx * 12.4, 3.6, hz1 + 1.6), (2.2, 3.8, 2.2), STONE_L)
    m.ell(V(mx, 0.9, hz1 + 4.2), (12.5, 0.6, 4.0), STONE_L)
    m.ell(V(mx - 3.0, 1.5, hz1 + 6.0), (5.0, 0.4, 1.2), FIRE, kind="emit")
    m.ell(V(mx + 5.0, 1.4, hz1 + 5.6), (2.4, 0.4, 0.9), FIRE, kind="emit")
    for k, (yy, rx, rz, zc) in enumerate(((top + 1.0, 18.5, 17.0, -47.0), (top + 5.5, 16.5, 15.0, -50.0), (top + 10.0, 14.5, 13.5, -55.0), (top + 14.5, 13.0, 12.5, -60.0))):
        for j in range(5):
            m.ell(V(mx + (j - 2.0) * rx * 0.42, yy, zc), (rx * 0.27, 2.7, rz * 0.9), SOOT_STONE[(j + k) % 3])
    slab(m, V(mx - 14.0, top + 0.6, hz1 + 3.2), V(mx + 14.0, top + 0.6, hz1 + 3.2), 2.4, 0.7, IRON, (0, 0, 1), step=1.2)
    for k in range(8):
        m.ell(V(mx - 11.5 + k * 3.3, top + 1.6, hz1 + 3.9), (0.55, 0.55, 0.4), IRON)
    return mx, hz1


def tower(m, rng):
    cx, cz = TOWER
    tower_rings(m, rng, cx, cz, 30.0, TOWER_TOP - 6.0, 14.0, 9.0)
    for y in (44.0, 60.0):                                                                          # two string courses: bands of lighter, flatter stones that stand out a little
        r = 14.0 + (9.0 - 14.0) * (y - 30.0) / (TOWER_TOP - 36.0)
        n = int(2 * math.pi * r / 5.6)
        for k in range(n):
            a = 2 * math.pi * k / n
            if math.sin(a) > -0.6:
                m.ell(V(cx + math.cos(a) * (r + 1.2), y, cz + math.sin(a) * (r + 1.2)), (math.pi * r / n * 1.05, 1.5, 2.6), STONE_L, R=h.rot_y(-(a + math.pi / 2)))
    for k, (yy, r) in enumerate(((TOWER_TOP - 5.4, 10.4), (TOWER_TOP - 3.0, 11.2), (TOWER_TOP - 0.8, 10.2))):
        n = 14
        for j in range(n):
            a = 2 * math.pi * j / n + k * 0.2
            m.ell(V(cx + math.cos(a) * r * 0.86, yy, cz + math.sin(a) * r * 0.86), (3.2, 1.5, 3.0), STONE_L if (j + k) % 2 else STONE, R=h.rot_y(-(a + math.pi / 2)))
    for j in range(10):
        a = 2 * math.pi * j / 10
        m.ell(V(cx + math.cos(a) * 5.6, TOWER_TOP + 3.0, cz + math.sin(a) * 5.6), (2.4, 2.4, 2.0), IRON, R=h.rot_y(-(a + math.pi / 2)))
    m.ell(V(cx, TOWER_TOP + 3.2, cz), (4.8, 1.0, 4.8), GAP)


def sign_bracket(m):
    x, z = HALL_X1 + 3.0, FACADE_Z + 6.5
    log(m, V(HALL_X1 - 1.5, 31.0, z), V(x + 6.5, 31.0, z), 0.55, IRON, step=0.8)
    log(m, V(HALL_X1 - 1.5, 26.5, z), V(HALL_X1 + 5.0, 31.0, z), 0.45, IRON, step=0.8)
    m.ell(V(x + 6.7, 31.0, z), (1.0, 1.0, 1.0), IRON)


LANTERN_XS = (DOOR_X0 - 7.5, DOOR_X1 + 7.5)
LANTERN_Y = 29.0
LANTERN_Z = FACADE_Z + 9.5


def brackets(m):
    for x in LANTERN_XS:                                                                           # iron arms from the facade for the night lanterns
        log(m, V(x, LANTERN_Y, FACADE_Z + 2.0), V(x, LANTERN_Y, LANTERN_Z), 0.5, IRON, step=0.8)
        log(m, V(x, LANTERN_Y - 4.5, FACADE_Z + 2.0), V(x, LANTERN_Y, LANTERN_Z - 1.5), 0.4, IRON, step=0.8)
    T.side_banner(m, HALL_X0 - 4.0, EAVE_Y + 1.0, FACADE_Z + 0.5, 15.0, out=-1, half=2.8, what="bracket")


def main_model(rng):
    m = h.Model()
    apron(m, rng)
    hall_walls(m, rng)
    yard_goods(m, rng)
    anvil(m, 31.0, -13.0)
    trough(m, rng, 5.0, -6.0)
    bellows(m, 18.5, -26.0)
    mx, hz1 = hearth(m, rng)
    tower(m, rng)
    sign_bracket(m)
    brackets(m)
    gable_roof(m, rng, HALL_BACK - 4.0, FACADE_Z + 7.5)
    return m, mx, hz1


SLATE = (
    [hexc(c) for c in ("0f1320", "222a40", "3e4a6a", "65779c")],   # cold blue slate
    [hexc(c) for c in ("14161f", "2c3040", "4a5066", "737a92")],   # grey slate
    [hexc(c) for c in ("1a1822", "3a2e3c", "5a4650", "866a72")],   # a few warmer, replaced ones
)


def soot(arr, mouth_px):
    """The stone blackens with the years: soot above the forge's mouth running up the hood and the tower, round the chimney's rim, and in the hall's corners."""
    mx, my = FW / 2 + mouth_px[0], GROUND + mouth_px[1]
    tx = FW / 2 + proj(TOWER[0], TOWER_TOP, TOWER[1])[0]
    ty = GROUND + proj(TOWER[0], TOWER_TOP, TOWER[1])[1]

    def k(x, y):
        up = max(0.0, (my - y) / max(my - ty, 1.0))                                                # 0 at the mouth .. 1 at the tower's rim
        stripe = max(0.0, 1.0 - abs(x - (mx + (tx - mx) * up)) / (11.0 + 7.0 * up))               # a plume that leans from the mouth to the rim
        base = stripe * (0.9 - 0.45 * up) if y < my else 0.0
        rim = max(0.0, 1.0 - math.hypot(x - tx, (y - ty) * 1.6) / 15.0) * 1.1                      # black round the chimney pot
        side = 0.5 * max(0.0, 1.0 - abs(x - mx) / 26.0) * max(0.0, 1.0 - abs(y - my) / 10.0)       # soot beside the mouth
        return min(1.0, base + rim + side) * (0.75 + 0.5 * fbm(x * 0.25, y * 0.25, 5))
    out = hut_lib.tint_region(arr, k, seed=5)
    fire = {tuple(c[:3]) for c in h.RAMPS[FIRE]}
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in fire:
                out[y, x] = arr[y, x]
    return out


def pad_dark(name, foot_w, foot_h, seed):
    """The ground under the smithy: soot-black trodden earth with coal chips and ash, dithered into the meadow."""
    w, hh = int(foot_w) + 16, int(foot_h) + 14
    arr = np.zeros((hh, w, 4), np.uint8)
    earth = [hexc(c)[:3] for c in ("17131b", "262029", "3a323c", "534a55")]
    for y in range(hh):
        for x in range(w):
            dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - hh / 2) / (hh / 2)
            r = (abs(dx) ** 3.2 + abs(dy) ** 3.2) ** (1 / 3.2) + (fbm(x * 0.18, y * 0.22, seed) - 0.5) * 0.4
            if r > 1.0 - 0.1 * bayer(x, y):
                continue
            tone = 1 + (fbm(x * 0.3, y * 0.4, seed + 4) > 0.5) + (r < 0.6 and fbm(x * 0.5, y * 0.6, seed + 8) > 0.6)
            if r > 0.84:
                tone = 0 if bayer(x, y) < 0.5 else 1
            arr[y, x] = (*earth[min(tone, 3)], 255)
            n = hsh(x, y, seed)
            if n > 0.985:
                arr[y, x, :3] = h.RAMPS[IRON][2][:3]
            elif n < 0.012:
                arr[y, x, :3] = (96, 52, 34)  # a dull ember-red fleck
    save(OUT / f"{name}_pad.png", arr)


def overlay(name, m, seed):
    arr = to_array(hut_lib.render(m, FW, FH, GROUND))
    save(OUT / f"{name}.png", grain(arr, seed, amount=0.5, mats=T.WOODISH))


def wear_set():
    rng = rng_for(141)
    m = h.Model()  # day 1: soot on the flagstones round the hearth and a first scatter of coal
    for k in range(9):
        m.ell(V(rng.uniform(26, 56), 1.05, rng.uniform(-28, -6)), (rng.uniform(3.0, 6.0), 0.3, rng.uniform(1.6, 3.0)), SOIL)
    for k in range(14):
        m.ell(V(rng.uniform(22, 58), 1.2, rng.uniform(-28, -4)), (rng.uniform(0.7, 1.4), 0.6, rng.uniform(0.6, 1.2)), GAP)
    overlay("smithy_wear_a", m, 31)
    m = h.Model()  # day 3: a coal heap and an ore basket by the hearth, a pair of tongs left on the stump
    for k in range(26):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 7.5)
        m.ell(V(54.0 + math.cos(a) * rr * 0.8, 1.6 + max(0.0, 5.0 - rr * 0.6), -8.5 + math.sin(a) * rr * 0.6), (rng.uniform(1.0, 2.0), rng.uniform(0.9, 1.6), rng.uniform(1.0, 1.9)), GAP if k % 2 else SOIL)
    for k in range(6):
        m.ell(V(41.0 + k * 0.4, 1.6 + (k // 3) * 2.0, -6.0), (2.4, 1.2, 2.0), CLAY if k % 2 else IRON)
    _wear_overlay = overlay("smithy_wear_b", m, 32)
    m = h.Model()  # day 6: a heap of slag (black, glassy, violet-glinting), old horseshoes and scrap iron
    for k in range(30):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.0, 9.0)
        m.ell(V(-56.0 + math.cos(a) * rr, 1.6 + max(0.0, 6.0 - rr * 0.65), -23.0 + math.sin(a) * rr * 0.6), (rng.uniform(1.2, 2.6), rng.uniform(1.0, 1.9), rng.uniform(1.2, 2.4)), GAP if k % 3 else IRON)
    for k in range(5):
        m.ell(V(-56.0 + rng.uniform(-6, 6), 7.5 + rng.uniform(0, 1.5), -23.0 + rng.uniform(-3, 3)), (0.7, 0.7, 0.5), h.VIOLET, kind="emit")
    for k in range(4):
        m.ell(V(-40.0 + k * 3.0, 1.4, -2.0), (1.6, 0.4, 1.4), IRON)
    overlay("smithy_wear_c", m, 33)
    m = h.Model()  # age 5: moss in the low joints of the walls, on the string courses and at the foot of the tower
    for k in range(40):
        side = rng.random()
        x = rng.uniform(HALL_X0 + 2, HALL_X1 - 2) if side < 0.55 else rng.uniform(26, 58)
        z = FACADE_Z + 4.4 if side < 0.55 else HEARTH_Z1 + 4.4
        m.ell(V(x, rng.uniform(1.2, 8.0), z), (rng.uniform(1.4, 3.0), rng.uniform(0.7, 1.3), 0.8), MOSS_L if k % 3 == 0 else MOSS)
    overlay("smithy_moss_a", m, 34)
    m = h.Model()  # age 11: the roof's edge and the gable's foot green as well
    for k in range(34):
        m.ell(V(rng.uniform(HALL_X0 - 4, HALL_X1 + 4), EAVE_Y - 0.4 + rng.uniform(-1, 1), FACADE_Z + 2.0), (rng.uniform(1.8, 3.4), 0.9, 0.8), MOSS_L if k % 3 == 0 else MOSS)
    for k in range(20):
        m.ell(V(rng.uniform(HALL_X0, HALL_X1), rng.uniform(EAVE_Y, EAVE_Y + 8.0), FACADE_Z + 4.0), (rng.uniform(1.2, 2.4), 0.8, 0.7), MOSS if k % 2 else MOSS_L)
    overlay("smithy_moss_b", m, 35)
    m = h.Model()  # neglect: cobwebs in the doorway and over the hearth's mouth, a cold grey ash on the flagstones, rust on the anvil
    import art_town_decor as D  # noqa: E402
    D.cobweb(m, (DOOR_X0 + DOOR_X1) / 2.0 - 8.0, 26.0, FACADE_Z + 4.6, 9.0, sign=1)
    D.cobweb(m, (DOOR_X0 + DOOR_X1) / 2.0 + 8.0, 26.0, FACADE_Z + 4.6, 9.0, sign=-1)
    D.cobweb(m, 40.0, 19.5, HEARTH_Z1 + 3.5, 9.0, sign=1)
    for k in range(10):
        m.ell(V(rng.uniform(26, 56), 1.1, rng.uniform(-28, -6)), (rng.uniform(2.0, 5.0), 0.3, rng.uniform(1.2, 2.4)), LINEN)
    overlay("smithy_neglect", m, 36)


def parts_and_light(arr, mx, hz1):
    """Lanterns, the anvil sign and the pennant as swaying parts; the light spills (forge mouth, doorway, lanterns); returns the numbers for data/town.json."""
    parts = []
    # the lanterns over the doorway's two sides, with their glow
    spill = hut_lib.pool_spill(FW, FH, (0, 0, 0, 0), [], reach=0)
    mouth = (int(FW / 2 + proj(mx - 9.5, 4.0, hz1)[0]), int(FW / 2 + proj(mx + 9.5, 4.0, hz1)[0]), int(GROUND + proj(mx, 12.5, hz1)[1]), int(GROUND + proj(mx, 3.0, hz1)[1]))
    fy = GROUND + proj(mx, GROUND_Y, hz1 + 9.0)[1]
    cxm = FW / 2 + proj(mx, 0, 0)[0]
    forge = hut_lib.pool_spill(FW, FH, mouth, [(cxm, fy, 26, 9, 1.0), (cxm - 10, fy + 3, 46, 15, 0.45)], reach=11, color=(255, 120, 40), seed=9, bloom=0.85)
    door_cx = (DOOR_X0 + DOOR_X1) / 2.0
    dbox = (int(FW / 2 + proj(door_cx - 6, 0, FACADE_Z)[0]), int(FW / 2 + proj(door_cx + 6, 0, FACADE_Z)[0]), int(GROUND + proj(door_cx, 8, FACADE_Z)[1]), int(GROUND + proj(door_cx, 1, FACADE_Z)[1]))
    door = hut_lib.pool_spill(FW, FH, dbox, [(FW / 2 + proj(door_cx, 0, 0)[0], GROUND + proj(door_cx, GROUND_Y, FACADE_Z + 8.0)[1], 18, 6, 0.7)], reach=7, color=(255, 120, 40), seed=11, bloom=0.5)
    spill = np.maximum(forge, door)
    for side, x in zip(("l", "r"), LANTERN_XS):
        lm = h.Model()
        T.lantern(lm, (x, LANTERN_Y - 0.6, LANTERN_Z), hang=2.0)
        name = f"smithy_lantern_{side}"
        larr, (lx, ly) = T.part(name, lm, FW, FH, GROUND, glow=True, seed=90 + (side == "r"))
        fb = T.fire_box(larr)
        box = (fb[0] + lx, fb[1] + lx, fb[2] + ly, fb[3] + ly)
        floor_y = GROUND + proj(x, GROUND_Y, LANTERN_Z)[1] + 4.0
        spill = np.maximum(spill, hut_lib.pool_spill(FW, FH, box, [((box[0] + box[1]) / 2, floor_y, 17, 6, 0.75)], reach=6, seed=93, bloom=0.4))
        parts.append({"texture": name, "frame": INFO[name]["frame"], "at": INFO[name]["at"], "window": [0.75, 1.0], "sway": {"pivot": 0, "amount": 1.4, "flutter": 0.3}, "glow": {"frames": 1, "fps": 1}})
    save(OUT / "smithy_spill.png", spill)
    # the sign: an iron anvil on a board, on two short chains from the bracket
    sm = h.Model()
    bx, bz = HALL_X1 + 6.5, FACADE_Z + 6.5
    for sx in (-3.6, 3.6):
        log(sm, V(bx + sx, 30.6, bz), V(bx + sx, 27.8, bz), 0.3, IRON, step=0.6)
    slab(sm, V(bx - 6.2, 25.4, bz + 0.1), V(bx + 6.2, 25.4, bz + 0.1), 3.0, 0.8, PLANK_W, (0, 0, 1), step=1.2)
    sm.ell(V(bx, 23.9, bz + 1.0), (3.4, 0.7, 0.7), STEEL)
    sm.ell(V(bx, 25.1, bz + 1.0), (1.5, 0.8, 0.7), STEEL)
    sm.ell(V(bx, 26.4, bz + 1.0), (5.0, 0.8, 0.8), STEEL)
    sm.ell(V(bx + 4.8, 26.4, bz + 1.0), (2.2, 0.6, 0.6), STEEL)
    T.part("smithy_sign", sm, FW, FH, GROUND, seed=94)
    parts.append({"texture": "smithy_sign", "frame": INFO["smithy_sign"]["frame"], "at": INFO["smithy_sign"]["at"], "window": [0.7, 1.0], "sway": {"pivot": 0, "amount": 1.8, "flutter": 0.4}})
    pm = h.Model()
    T.side_banner(pm, HALL_X0 - 4.0, EAVE_Y + 1.0, FACADE_Z + 0.5, 15.0, out=-1, half=2.8)
    T.part("smithy_pennant", pm, FW, FH, GROUND, seed=95)
    parts.append({"texture": "smithy_pennant", "frame": INFO["smithy_pennant"]["frame"], "at": INFO["smithy_pennant"]["at"], "window": [0.8, 1.0], "sway": {"pivot": 0, "amount": 3.2, "flutter": 0.9}})
    return parts


def write_json(parts, mx, hz1):
    path = Path(__file__).resolve().parent.parent / "data" / "town.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    sx, sy = proj(mx, 7.0, hz1 + 6.0)
    tx, ty = proj(TOWER[0], TOWER_TOP + 4.0, TOWER[1])
    pieces = data["pieces"]
    entry = {
        "name": "SCHMIEDE", "needs_resident": "torben", "category": "craft", "texture": "smithy", "frame": [FW, FH], "feet": GROUND, "foot": [112, 38], "snap": 8, "pad": True,
        "cost": {"wood": 16, "stone": 30, "plank": 6, "iron_ore": 8}, "build_seconds": 40.0, "reach": 64.0, "worth": 18, "role": "smith", "glow": True,
        "anim": {"frames": FRAMES, "fps": 7},
        "light": {"color": "ff8a3a", "radius": 78, "energy": 1.15, "at": [round(sx), round(sy) - 6], "flicker": 0.4},
        "info": "ESSE, AMBOSS UND EISEN", "paths": True, "front": [104, 26],
        "smoke": {"at": [round(tx), round(ty)]},
        "sparks": {"at": [round(sx), round(sy) - 4], "color": "ffb25a"},
        "spill": {"texture": "smithy_spill", "forge": True, "base": 0.9},
        "parts": parts,
        "wear": [
            {"texture": "smithy_wear_a", "days": 1}, {"texture": "smithy_wear_b", "days": 3}, {"texture": "smithy_wear_c", "days": 6},
            {"texture": "smithy_moss_a", "days": 5, "track": "age"}, {"texture": "smithy_moss_b", "days": 11, "track": "age"}, {"texture": "smithy_neglect", "days": 2, "track": "neglect"},
        ],
        "perches": [[round(proj(RIDGE_X, RIDGE_Y + 2.0, -30.0)[0]), round(proj(RIDGE_X, 0, -30.0)[1]), round(-proj(RIDGE_X, RIDGE_Y + 2.0, -30.0)[1] + proj(RIDGE_X, 0, -30.0)[1])],
                    [round(tx), round(proj(TOWER[0], 0, TOWER[1])[1]), round(-ty + proj(TOWER[0], 0, TOWER[1])[1])]],
        "trample": {"strength": 1.0, "margin": 18, "front": True},
    }
    order = list(pieces.keys())
    pieces["smithy"] = entry
    if "smithy" not in order:
        idx = order.index("workshop") + 1
        order.insert(idx, "smithy")
    data["pieces"] = {k: pieces[k] for k in order}
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(json.dumps(data, indent=1, ensure_ascii=False) + "\n")


def main():
    global K
    hut_lib.ROOF_TONES = SLATE
    frames, glows, base = [], [], None
    for k in range(FRAMES):
        K = k
        m, mx, hz1 = main_model(rng_for(131))
        raw = to_array(hut_lib.render(m, FW, FH, GROUND))
        glows.append(glow_of(raw, T.LIT))
        if k == 0:
            base = raw
    arr = hut_lib.roof_pass(base, 83, moss=0.1, shadow=8)
    arr = soot(arr, proj(mx, 8.0, hz1))
    arr = T.finish(arr, 83, GROUND, 58, 8)
    save(OUT / "smithy.png", arr)
    strip = np.concatenate(glows, axis=1)
    save(OUT / "smithy_glow.png", strip)
    pad_dark("smithy", 112, 38, 7)
    parts = parts_and_light(arr, mx, hz1)
    wear_set()
    print("smithy", arr.shape, "glow strip", strip.shape)
    print("mouth", proj(mx, 7.0, hz1), "tower top", proj(TOWER[0], TOWER_TOP + 4, TOWER[1]))
    if "--json" in sys.argv:
        write_json(parts, mx, hz1)
        print("data/town.json: smithy written")
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image
        comp = Image.new("RGBA", (FW, FH), (58, 110, 70, 255))
        comp.alpha_composite(Image.fromarray(arr))
        for p_ in parts:
            comp.alpha_composite(Image.open(OUT / f"{p_['texture']}.png"), tuple(p_["at"]))
        comp.alpha_composite(Image.fromarray(strip[:, :FW]))
        comp.resize((FW * 5, FH * 5), Image.NEAREST).save(png[0])


if __name__ == "__main__":
    main()
