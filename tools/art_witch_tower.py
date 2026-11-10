#!/usr/bin/env python3
"""The witch's tower of the Hexenwald (docs/hexenwald_nebel_konzept.md section 8). Built like the smithy and the hut (ellipsoids through art_hero3d / hut_lib: rounded forms,
light from the top left, four bands of shade, ink between forms), in the wood's own colours: cold dark curse-silver stone, the hag elms' black-violet wood, a violet shingle
hat, and witch green (#a8ff6a) for everything that shines.

  * a crooked round keep of dark stone that leans and tapers, on a plinth of boulders, narrow green-lit slits spiralling up it, a ring of runes halfway,
  * a timber chamber that overhangs the shaft on corbels, with a big arched window (somebody walks past it at night),
  * the roof is a WITCH'S HAT: a wide brim, a band with a buckle, a cone that bends over at the tip, a crescent moon on it, a round dormer that is an eye,
  * a little turret hangs off the left side under its own hat, held up by a bough,
  * a hag elm has grown round the whole thing: its trunk winds up the shaft (glowing veins, a face beside the door), its roots lie over the steps, its crown stands beside the chamber,
  * the gate with an iron-banded door, bone-wood posts with green lanterns, grave candles on the steps, a cauldron on its fire, toad caps, a crooked stove pipe.
Its pieces (assets/props/witch_tower/): tower.png + tower_glow.png (only the emissive pixels), tower_pad.png (the ground), the swaying parts crown / charms / lantern_l / lantern_r
(+ _glow), the little unlit animation strips window (a figure passes the big window), eye (the dormer looks about), cauldron (the brew bubbles), and witch_tower.json
(where every part sits in the frame, light and smoke points) for the node that puts it together (src/entities/props/witch_tower.gd).

    python3 tools/art_witch_tower.py [preview.png]      needs numpy (and PIL for the preview)"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, bayer, fbm, glow_of, grain, hsh, log, rng_for, save, slab, to_array, V  # noqa: E402
from gen_art import hexc  # noqa: E402

OUT = ROOT / "props" / "witch_tower"
BASE = len(h.RAMPS)
(CSTONE, CSTONE_L, HAG, HAG_L, HEXG, LEAF, WINE, BONE, HAIRM, SILVER, HOODM, BREW, WOODP, WOODP_L) = range(BASE, BASE + 14)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["0c0e18", "181d2b", "272d3d", "3b4354"],  # curse-silver stone: the Hexenwald's slate, dusky violet-grey like its cliffs (not a blue of its own)
    ["181d2b", "272d3d", "3b4354", "545c6c"],  # the same, lit (arches, string courses, caps)
    ["0c0812", "1a1322", "2c2236", "44344c"],  # hag elm bark: almost black, violet in the shade
    ["1a1322", "2c2236", "44344c", "625064"],  # its lit ridges
    ["2e6a2a", "4a9a3a", "a8ff6a", "eaffc4"],  # witch green: every light of the wood
    ["0a0e20", "15303a", "1d4a48", "2d6a58"],  # the elm's leaves: blue-black .. dull sea green
    ["24081a", "481026", "701a34", "983044"],  # wine red, dusky: toad caps, rags, the hat's band
    ["56506c", "8a8698", "b8b4b8", "dedacc"],  # bone wood
    ["1e3038", "34504e", "557468", "86a08a"],  # witch-hair moss
    ["4a5670", "8a98b4", "c8d4e8", "f4f8ff"],  # silver: the moon on the hat, the buckle
    ["100b1e", "1e1536", "30234e", "483666"],  # the dormer's and the turret's violet
    ["123a2a", "1e6a3a", "4ac85a", "c8ffa0"],  # the brew
    ["120c18", "21182a", "33283c", "4a3e50"],  # the chamber's planks: the hag elm's own wood, sawn
    ["1a1322", "2b2236", "41364a", "5a4e60"],  # the same, weathered
]]
PLANK, PLANK_W = WOODP, WOODP_L  # no warm timber in this wood
MOSS, MOSS_L = LEAF, HAIRM  # growth on the stone has the colours of the elm's leaves and the witch-hair moss
LIT = (HEXG, BREW)
GRAINED = (BARK, BARK_D, PLANK, PLANK_W, MOSS, MOSS_L, CSTONE, CSTONE_L, HAG, HAG_L, IRON, BONE, LEAF, HAIRM)
STONES = (CSTONE, CSTONE, CSTONE_L)
FW, FH, GROUND = 232, 336, 304
CZ = -46.0                # the keep's axis (z)
SHAFT_TOP = 168.0
CHAMBER = (182.0, 228.0)  # the timber chamber
CH_R = 37.0
HAT_Y, HAT_TIP = 226.0, 118.0  # the brim's height, the cone's length
TURRET = (-41.0, 98.0, CZ + 8.0)
INFO = {}


def proj(x, y, z):
    """Where a model point lands in the frame (px)."""
    return (FW / 2 + x * h.SCALE, GROUND - (y * h.COSP - z * h.SINP) * h.SCALE)


def lean(y):
    """The keep's axis is not straight: it leans left, then back, like something that grew."""
    return -5.0 * math.sin(y * 0.0125) + 0.02 * y


def radius(y):
    return 35.0 - 9.5 * min(y / SHAFT_TOP, 1.0) ** 0.8


def on_wall(a, y, out=0.0, r=None):
    """The point at angle `a` (0 = right, pi/2 = towards the viewer) on the keep's wall at height y, `out` units off it."""
    rr = (radius(y) if r is None else r) + out
    return V(lean(y) + math.cos(a) * rr, y, CZ + math.sin(a) * rr)


def facing(a):
    return h.rot_y(-(a + math.pi / 2))


# ------------------------------------------------------------------ stone
def ring(m, y, r, mat, size, n=None, cx=None, cz=CZ, skip_back=-0.85, off=0.0, kind=""):
    """A course of blocks round a circle; the far side is thinned out."""
    n = n or max(8, int(2 * math.pi * r / (size[0] * 1.7)))
    cx = lean(y) if cx is None else cx
    for k in range(n):
        a = off + 2 * math.pi * k / n
        if math.sin(a) < skip_back:
            continue
        m.ell(V(cx + math.cos(a) * r, y, cz + math.sin(a) * r), size, mat[k % len(mat)] if isinstance(mat, tuple) else mat, R=facing(a), kind=kind)


def plinth(m, rng):
    """Boulders at the keep's foot, bigger and rougher than the courses above; moss in the joints."""
    for row, (y, r, s) in enumerate(((3.0, 40.5, 5.6), (9.0, 38.5, 5.0), (14.5, 36.6, 4.4))):
        n = int(2 * math.pi * r / (s * 1.75))
        for k in range(n):
            a = row * 0.31 + 2 * math.pi * k / n
            if math.sin(a) < -0.8:
                continue
            j = rng.uniform(-0.6, 0.6)
            m.ell(V(lean(y) + math.cos(a) * (r + j), y + j * 0.5, CZ + math.sin(a) * (r + j)), (s * rng.uniform(0.95, 1.15), s * 0.72, 4.6), STONES[(k + row) % 3], R=facing(a))
            if rng.random() < 0.28 and math.sin(a) > 0.0:
                m.ell(V(lean(y) + math.cos(a) * (r + 3.4), y + s * 0.55, CZ + math.sin(a) * (r + 3.4)), (rng.uniform(1.6, 3.0), 0.9, 1.0), MOSS_L if rng.random() < 0.4 else MOSS, R=facing(a))


def shaft(m, rng):
    """The keep: courses of wedge stones, every one turned a little, leaning with the axis. Lighter string courses, a few stones missing or pushed out by the tree."""
    y, row = 17.0, 0
    while y < SHAFT_TOP:
        hgt = rng.uniform(4.6, 5.6)
        r = radius(y)
        n = max(10, int(2 * math.pi * r / 6.4))
        off = row * 0.37 + rng.uniform(0, 0.3)
        for k in range(n):
            a = off + 2 * math.pi * k / n
            if math.sin(a) < -0.86 and k % 2:
                continue
            push = 0.9 if hsh(k, row, 5) > 0.94 else 0.0  # a stone the roots have pushed out
            m.ell(V(lean(y) + math.cos(a) * (r + push), y + hgt / 2, CZ + math.sin(a) * (r + push)), (math.pi * r / n * 1.05, hgt / 2 * 0.98, 3.8), STONES[(k + row) % 3], R=facing(a))
        y += hgt * 0.94
        row += 1
    for yy in (58.0, 118.0):  # string courses
        ring(m, yy, radius(yy) + 1.3, CSTONE_L, (3.0, 1.5, 2.8), n=int(2 * math.pi * radius(yy) / 5.4), skip_back=-0.6)


def slit(m, a, y, tall=7.0, wide=1.5):
    """A narrow window in the keep: a lit slot in a frame of lighter stones, a sill."""
    p = on_wall(a, y, 2.6)
    m.ell(p, (wide + 1.5, tall + 1.6, 1.6), CSTONE_L, R=facing(a))
    m.ell(on_wall(a, y, 3.4), (wide, tall, 1.2), HEXG, R=facing(a), kind="emit")
    m.ell(on_wall(a, y + tall * 0.55, 3.6), (wide * 0.6, tall * 0.25, 1.0), HEXG, R=facing(a), kind="emit")
    m.ell(on_wall(a, y - tall - 1.0, 3.6), (wide + 2.2, 1.0, 1.8), CSTONE_L, R=facing(a))
    m.ell(on_wall(a, y, 4.2), (0.45, tall, 0.5), IRON, R=facing(a))  # the bar


def runes(m):
    """A ring of carved signs under the upper string course: they glow."""
    y = 110.0
    marks = ("|/", "\\|", "<>", "|-", "/\\", "||", "X", "|<")
    n = 13
    for k in range(n):
        a = 0.25 + (math.pi - 0.5) * k / (n - 1)
        for i, ch in enumerate(marks[k % len(marks)]):
            p = on_wall(a + (i - 0.5) * 0.045, y, 3.9)
            R = facing(a)
            if ch == "|":
                m.ell(p, (0.45, 2.3, 0.5), HEXG, R=R, kind="emit")
            elif ch == "-":
                m.ell(p, (1.2, 0.45, 0.5), HEXG, R=R, kind="emit")
            elif ch in "/\\":
                m.ell(p, (0.45, 2.3, 0.5), HEXG, R=R @ rot_z(0.6 if ch == "/" else -0.6), kind="emit")
            elif ch in "<>X":
                for s in (-1, 1):
                    m.ell(p + V(0, s * 0.9, 0), (0.45, 1.3, 0.5), HEXG, R=R @ rot_z(s * (0.7 if ch != ">" else -0.7)), kind="emit")


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# ------------------------------------------------------------------ the gate
def gate(m, rng):
    """The door faces the viewer: a tall arch of lighter wedge stones, a dark iron-banded door a little ajar with green light in the crack, steps, a threshold."""
    g = 1.5
    cx, zf = lean(14.0), CZ + radius(10.0) + 3.6
    m.ell(V(cx, 14.0 * g, zf - 1.0), (9.6 * g, 13.5 * g, 2.4), GAP)
    m.ell(V(cx, 26.0 * g, zf - 1.0), (9.2 * g, 8.0 * g, 2.4), GAP)
    x = cx - 8.2 * g
    i = 0
    while x < cx + 8.4 * g:  # the door's planks
        top = (25.5 + math.sqrt(max(0.0, 1.0 - ((x - cx) / (9.4 * g)) ** 2)) * 7.6) * g
        if not (cx + 5.0 * g < x < cx + 8.0 * g):  # the crack it stands open
            slab(m, V(x, 1.6, zf), V(x, top, zf), 1.5, 0.8, PLANK if i % 3 == 1 else HAG_L, (0, 0, 1), step=1.2)
        x += 3.0
        i += 1
    m.ell(V(cx + 6.6 * g, 13.0 * g, zf - 0.6), (1.5, 11.0 * g, 0.6), HEXG, kind="emit")  # light through the crack
    for yy in (7.0, 20.0, 33.0):  # iron bands, a ring
        log(m, V(cx - 8.6 * g, yy, zf + 1.0), V(cx + 4.4 * g, yy, zf + 1.0), 0.9, IRON, step=0.9)
    for k in range(12):
        b = 2 * math.pi * k / 12
        m.ell(V(cx - 4.0 + math.cos(b) * 2.6, 14.0 + math.sin(b) * 2.6, zf + 1.4), (0.7, 0.7, 0.5), IRON)
    m.ell(V(cx - 3.0, 27.5 * g, zf + 0.9), (2.0, 2.0, 0.5), HEXG, kind="emit")  # a round spy hole
    m.ell(V(cx - 3.0, 27.5 * g, zf + 1.2), (0.4, 2.0, 0.4), IRON)
    for k in range(19):  # the arch
        b = math.pi * k / 18
        m.ell(V(cx + math.cos(b) * 11.6 * g, (21.0 + math.sin(b) * 13.6) * g, zf + 0.6), (3.3, 3.3, 3.6), CSTONE_L, R=rot_z(b - math.pi / 2))
    m.ell(V(cx, 35.6 * g, zf + 1.2), (3.4, 3.2, 3.2), CSTONE_L)  # keystone
    m.ell(V(cx, 35.6 * g, zf + 4.2), (1.2, 1.6, 0.5), HEXG, kind="emit")  # with a sign cut in it
    for s in (-1, 1):
        for k in range(6):
            m.ell(V(cx + s * 11.8 * g, 3.0 + k * 5.0, zf + 0.8), (3.3, 2.7, 3.6), CSTONE_L)
    for k, (zz, w, yy) in enumerate(((zf + 5.0, 19.0, 2.6), (zf + 10.5, 21.5, 1.5), (zf + 16.0, 24.0, 0.5))):  # three worn steps
        xx = cx - w
        while xx < cx + w:
            ww = rng.uniform(4.4, 6.4)
            m.ell(V(xx + ww / 2, yy, zz + rng.uniform(-0.4, 0.4)), (ww / 2, 0.9, 3.0), STONES[int(hsh(xx, k, 3) * 3)])
            xx += ww
    return cx, zf


def candles(m, rng, cx, zf):
    """Grave candles on the steps and the plinth: wax stubs with a cold green flame."""
    spots = [(cx - 21.0, 3.6, zf + 5.5, 4.2), (cx - 23.5, 2.4, zf + 10.0, 2.6), (cx + 20.0, 3.6, zf + 5.0, 3.2), (cx + 23.0, 1.4, zf + 16.5, 4.8), (cx - 18.0, 1.4, zf + 17.0, 2.2), (cx + 18.0, 2.4, zf + 11.0, 2.0)]
    for x, y, z, tall in spots:
        log(m, V(x, y, z), V(x, y + tall, z), 0.95, WAX, step=0.8)
        m.ell(V(x, y + 0.3, z), (1.5, 0.5, 1.3), WAX)  # the run wax
        m.ell(V(x, y + tall + 1.6, z), (0.75, 1.5, 0.6), HEXG, kind="emit")
    INFO["candles"] = [[round(v) for v in proj(x, y + tall + 1.6, z)] for x, y, z, tall in spots]


def posts(m, rng, cx, zf):
    """Two crooked posts of bone wood beside the steps, an arm each for a lantern (the lanterns are their own swaying pictures), a red rag."""
    out = []
    for s in (-1, 1):
        bx, bz = cx + s * 31.0, zf + 15.0
        top = V(bx + s * 1.6, 40.0, bz)
        log(m, V(bx, 0.6, bz), top, 1.5, BONE, step=1.0, taper=0.7)
        arm = V(bx - s * 6.2, 42.0, bz + 0.6)
        log(m, top + V(0, -1.5, 0), arm, 0.7, BONE, step=0.8, taper=0.7)
        m.ell(V(bx, 1.0, bz + 1.0), (2.6, 1.0, 1.6), CSTONE)  # stones at its foot
        m.ell(V(bx + s * 2.0, 0.9, bz - 1.2), (1.8, 0.8, 1.3), CSTONE_L)
        for k in range(3):
            m.ell(V(bx + s * 1.7, 24.0 - k * 2.4, bz + 1.0), (1.3 - 0.25 * k, 1.6, 0.4), WINE)  # the rag
        out.append(arm)
    return out


def lantern(m, at):
    """A cage lantern with a green flame, hung from the post's arm."""
    x, y, z = at
    m.limb(V(x, y, z), V(x, y - 2.6, z), 0.3, 0.3, IRON)
    m.ell(V(x, y - 3.2, z), (1.9, 0.8, 1.9), IRON)
    m.ell(V(x, y - 5.8, z), (1.5, 2.1, 1.5), HEXG, kind="emit")
    for b in (0.0, 1.57, 3.14, 4.71):
        m.limb(V(x + math.cos(b) * 1.8, y - 3.2, z + math.sin(b) * 1.8), V(x + math.cos(b) * 1.8, y - 8.0, z + math.sin(b) * 1.8), 0.28, 0.28, IRON)
    m.ell(V(x, y - 8.2, z), (1.9, 0.7, 1.9), IRON)


def cauldron(m, rng, cx, zf):
    """Left of the steps: a black pot on three stones over embers, full of a green brew, a ladle, toad caps round it."""
    x, z = cx - 47.0, zf + 9.0
    for b in (0.4, 2.5, 4.6):
        m.ell(V(x + math.cos(b) * 6.4, 1.6, z + math.sin(b) * 4.6), (2.6, 1.9, 2.2), CSTONE_L if b > 2 else CSTONE)
    m.ell(V(x, 1.4, z + 0.6), (4.2, 0.8, 3.0), FIRE, kind="emit")  # the embers
    m.ell(V(x, 7.4, z), (7.6, 5.8, 6.6), IRON)  # the belly
    for k in range(14):  # the rim
        b = 2 * math.pi * k / 14
        m.ell(V(x + math.cos(b) * 6.6, 12.2, z + math.sin(b) * 5.6), (1.5, 0.9, 1.3), IRON, R=facing(b))
    m.ell(V(x, 12.4, z), (5.9, 0.7, 4.9), BREW, kind="emit")
    log(m, V(x + 2.0, 12.6, z + 1.0), V(x + 9.5, 19.5, z - 1.0), 0.5, BONE, step=0.8)  # the ladle
    INFO["cauldron"] = [round(v) for v in proj(x, 12.6, z)]
    for dx, dz, s in ((-11.0, 4.5, 1.0), (-13.5, 0.5, 0.7), (10.5, 6.0, 0.8), (-8.0, 8.0, 0.6)):  # toad caps
        m.limb(V(x + dx, 0.6, z + dz), V(x + dx, 3.2 * s, z + dz), 0.8 * s, 0.7 * s, WAX)
        m.ell(V(x + dx, 3.8 * s, z + dz), (2.8 * s, 1.7 * s, 2.4 * s), WINE)
        m.ell(V(x + dx - 0.8 * s, 4.9 * s, z + dz + 0.9 * s), (0.5, 0.4, 0.4), WAX)
        m.ell(V(x + dx + 1.0 * s, 4.5 * s, z + dz + 1.3 * s), (0.4, 0.35, 0.4), WAX)


# ------------------------------------------------------------------ the chamber and the hat
def corbels(m):
    """The chamber overhangs the keep: stone corbels step out under it, wooden braces between them."""
    cx = lean(SHAFT_TOP)
    for k, (yy, r) in enumerate(((SHAFT_TOP + 1.5, 27.5), (SHAFT_TOP + 5.5, 30.5), (SHAFT_TOP + 9.5, 33.5))):
        ring(m, yy, r, (CSTONE_L, CSTONE), (3.4, 2.2, 3.2), n=int(2 * math.pi * r / 6.0), cx=cx, off=k * 0.2)
    n = 11
    for k in range(n):
        a = 0.1 + (math.pi - 0.2) * k / (n - 1)
        log(m, V(cx + math.cos(a) * 26.5, SHAFT_TOP - 7.0, CZ + math.sin(a) * 26.5), V(cx + math.cos(a) * 36.5, SHAFT_TOP + 12.0, CZ + math.sin(a) * 36.5), 1.25, HAG_L, step=1.0)


def chamber(m, rng):
    """A round room of dark timber: a floor beam ring, posts, planks between them, a big arched window to the front and two small ones."""
    y0, y1 = CHAMBER
    cx = lean(y0)
    for yy in (y0, y1 - 1.0):
        ring(m, yy, CH_R + 0.8, HAG_L, (2.6, 1.7, 2.0), n=44, cx=cx)
    n = 46
    for k in range(n):  # planks
        a = 2 * math.pi * k / n
        if math.sin(a) < -0.8:
            continue
        m.ell(V(cx + math.cos(a) * CH_R, (y0 + y1) / 2, CZ + math.sin(a) * CH_R), (2.7, (y1 - y0) / 2, 1.6), PLANK if k % 3 else PLANK_W, R=facing(a))
    for k in range(12):  # posts
        a = 2 * math.pi * (k + 0.5) / 12
        if math.sin(a) < -0.7:
            continue
        log(m, V(cx + math.cos(a) * (CH_R + 1.3), y0, CZ + math.sin(a) * (CH_R + 1.3)), V(cx + math.cos(a) * (CH_R + 1.3), y1, CZ + math.sin(a) * (CH_R + 1.3)), 1.3, HAG, step=1.1)
    for a, w, tall, yy in ((math.pi / 2, 8.6, 12.0, y0 + 20.0), (0.42, 3.4, 6.0, y0 + 24.0), (math.pi - 0.42, 3.4, 6.0, y0 + 24.0)):  # the windows
        p = V(cx + math.cos(a) * (CH_R + 1.7), yy, CZ + math.sin(a) * (CH_R + 1.7))
        m.ell(p, (w + 1.6, tall + 1.6, 1.4), HAG_L, R=facing(a))
        m.ell(p + V(math.cos(a), 0, math.sin(a)) * 0.8, (w, tall, 1.0), HEXG, R=facing(a), kind="emit")
        m.ell(p + V(math.cos(a), -tall - 1.2, math.sin(a)) * 1.0 + V(0, -tall - 1.2, 0) * 0.0, (w + 2.4, 1.0, 1.8), HAG_L, R=facing(a))
        if w > 5:
            INFO["window_box"] = [round(proj(*(p + V(-w, tall, 0)))[0]), round(proj(*(p + V(-w, tall, 0)))[1]), round(proj(*(p + V(w, -tall, 0)))[0]), round(proj(*(p + V(w, -tall, 0)))[1])]
            INFO["window"] = [round(v) for v in proj(*p)]
            front = p + V(0, 0, 1.6)
            m.ell(front, (0.5, tall, 0.5), HAG)  # the mullion and two bars
            for dy in (-3.5, 4.0):
                m.ell(front + V(0, dy, 0), (w * (0.95 if dy < 0 else 0.78), 0.5, 0.5), HAG)
    return cx


def hat_axis(t, cx):
    """Centre and radius of the hat's cone at t (0 brim .. 1 tip): it bends over to the right near the top and droops at the very end."""
    bend = 30.0 * t ** 2.4
    y = HAT_Y + HAT_TIP * (t - 0.16 * t ** 3.2)
    return cx + bend, y, 41.0 * (1.0 - t) ** 1.18 + 0.8


def hat(m, rng, cx):
    """The roof: a witch's hat. `roof_pass` turns its ROOF pixels into shingles."""
    for k, (r, yy) in enumerate(((52.0, HAT_Y - 2.4), (49.0, HAT_Y - 0.8), (45.0, HAT_Y + 0.8))):  # the brim: wide, flat, a little wavy
        n = 46
        for j in range(n):
            a = 2 * math.pi * j / n
            wave = 1.6 * math.sin(a * 3.0 + 0.8)
            m.ell(V(cx + math.cos(a) * r, yy + wave - (2.0 if k == 0 else 0.0), CZ + math.sin(a) * r), (4.4, 1.5, 4.6), ROOF, R=facing(a))
    ring(m, HAT_Y - 4.6, 46.0, GAP, (4.2, 1.2, 4.0), n=40, cx=cx, skip_back=0.1)  # the dark under the brim
    steps = 44
    for i in range(steps + 1):
        t = i / steps
        x, y, r = hat_axis(t, cx)
        if r > 3.2:
            n = max(6, int(2 * math.pi * r / 5.2))
            for j in range(n):
                a = i * 0.41 + 2 * math.pi * j / n
                if math.sin(a) < -0.8 and j % 2:
                    continue
                m.ell(V(x + math.cos(a) * r, y, CZ + math.sin(a) * r), (math.pi * r / n * 1.12, 2.7, 3.2), ROOF, R=facing(a))
        else:
            m.ell(V(x, y, CZ), (r + 0.6, 2.4, r + 0.6), ROOF)
    x, y, r = hat_axis(0.1, cx)  # the band and its buckle
    ring(m, y, r + 0.9, WINE, (3.2, 3.0, 2.4), n=int(2 * math.pi * r / 4.6), cx=x)
    b = math.pi / 2 - 0.25
    p = V(x + math.cos(b) * (r + 2.6), y, CZ + math.sin(b) * (r + 2.6))
    m.ell(p, (4.2, 4.2, 1.0), SILVER, R=facing(b))
    m.ell(p + V(math.cos(b), 0, math.sin(b)) * 0.7, (2.5, 2.5, 0.8), WINE, R=facing(b))
    # the dormer: a round window in the hat, an eye
    x, y, r = hat_axis(0.33, cx)
    a = math.pi / 2 + 0.2
    c = V(x + math.cos(a) * (r + 1.2), y, CZ + math.sin(a) * (r + 1.2))
    for j in range(12):
        bb = 2 * math.pi * j / 12
        m.ell(c + V(math.cos(bb) * 5.6, math.sin(bb) * 5.6, 0.6), (1.7, 1.7, 2.2), HOODM)
    m.ell(c + V(0, 0, 1.2), (4.6, 4.6, 1.2), HEXG, kind="emit")
    m.ell(c + V(0, 6.8, 1.0), (6.6, 1.6, 3.2), ROOF)  # its own little brow
    INFO["eye"] = [round(v) for v in proj(*(c + V(0, 0, 1.2)))]
    # the tip: a crescent moon of silver, a charm hanging from it
    x, y, r = hat_axis(1.0, cx)
    tip = V(x + 1.0, y - 0.5, CZ)
    m.limb(tip, tip + V(0.5, 5.0, 0), 0.5, 0.4, IRON)
    mc = tip + V(0.5, 10.0, 0)
    for j in range(9):
        bb = -0.6 + 3.9 * j / 8
        m.ell(mc + V(math.cos(bb) * 4.4, math.sin(bb) * 4.4, 0.4), (1.5 - 0.11 * abs(j - 4) * 1.5, 1.5 - 0.11 * abs(j - 4) * 1.5, 0.7), SILVER)
    INFO["moon"] = [round(v) for v in proj(*mc)]
    # the stove pipe: crooked, out of the chamber's right side and up through the brim
    q = V(cx + 31.0, CHAMBER[0] + 30.0, CZ + 18.0)
    pts = [q, q + V(9.0, 4.0, 2.0), q + V(11.0, 20.0, 1.0), q + V(15.0, 34.0, 2.0), q + V(13.5, 46.0, 1.0)]
    for u, v in zip(pts, pts[1:]):
        log(m, u, v, 2.3, IRON, step=1.1)
    for u in pts[1:-1]:
        m.ell(u, (3.0, 1.4, 3.0), IRON)
    top = pts[-1]
    m.ell(top + V(0, 2.6, 0), (4.2, 1.3, 4.2), IRON)
    m.ell(top + V(0, 0.9, 0), (2.0, 0.9, 2.0), GAP)
    INFO["smoke"] = [round(v) for v in proj(*(top + V(0, 4.0, 0)))]


def turret(m, rng):
    """A little round turret hanging off the keep's left side: braces under it, one lit window, its own crooked hat."""
    x, y, z = TURRET
    for k in range(5):  # the braces fan down to the wall
        b = 0.35 + 2.4 * k / 4
        log(m, V(x + math.cos(b) * 10.0, y, z + math.sin(b) * 10.0), V(x + 11.0, y - 22.0, z - 4.0), 1.0, HAG_L, step=1.0)
    ring(m, y + 1.0, 12.4, HAG_L, (2.2, 1.5, 1.8), n=20, cx=x, cz=z)
    n = 18
    for k in range(n):
        a = 2 * math.pi * k / n
        if math.sin(a) < -0.7:
            continue
        m.ell(V(x + math.cos(a) * 11.4, y + 13.0, z + math.sin(a) * 11.4), (2.2, 12.0, 1.4), PLANK_W if k % 3 == 0 else PLANK, R=facing(a))
    a = math.pi / 2 + 0.35
    p = V(x + math.cos(a) * 12.6, y + 15.0, z + math.sin(a) * 12.6)
    m.ell(p, (3.6, 5.4, 1.2), HAG_L, R=facing(a))
    m.ell(p + V(math.cos(a), 0, math.sin(a)) * 0.7, (2.4, 4.2, 1.0), HEXG, R=facing(a), kind="emit")
    m.ell(p + V(math.cos(a), 0, math.sin(a)) * 1.4, (0.4, 4.2, 0.4), HAG, R=facing(a))
    INFO["turret_window"] = [round(v) for v in proj(*p)]
    for k, (r, yy) in enumerate(((17.0, y + 25.0), (15.0, y + 26.4))):  # its brim
        ring(m, yy, r, ROOF, (3.0, 1.2, 3.2), n=22, cx=x, cz=z, skip_back=-2.0)
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        r = 12.6 * (1.0 - t) ** 1.15 + 0.6
        xx = x - 7.0 * t ** 2.2
        yy = y + 27.5 + 31.0 * t
        if r > 2.4:
            ring(m, yy, r, ROOF, (math.pi * r / max(6, int(2 * math.pi * r / 4.6)) * 1.15, 2.5, 2.6), n=max(6, int(2 * math.pi * r / 4.6)), cx=xx, cz=z, off=i * 0.4, skip_back=-2.0)
        else:
            m.ell(V(xx, yy, z), (r + 0.5, 2.2, r + 0.5), ROOF)
    m.ell(V(x - 7.2, y + 61.0, z), (1.1, 1.1, 1.1), SILVER)


# ------------------------------------------------------------------ the hag elm
def helix():
    """The trunk's path: out of the ground right of the gate, across the keep's right flank and round its front, up to the turret on the left."""
    pts = []
    for i in range(41):
        t = i / 40
        a = -0.25 + 3.05 * t ** 0.9
        y = 1.0 + 100.0 * t ** 0.95
        if 0.33 < t < 0.5:
            y += 0.0
        pts.append((on_wall(a, max(y, 17.0), 10.5 - 5.5 * t) if y > 17.0 else V(lean(17.0) + math.cos(a) * (radius(17.0) + 9.0 - y * 0.2), y, CZ + math.sin(a) * (radius(17.0) + 9.0 - y * 0.2)), 12.5 - 6.5 * t, a))
    return pts


def elm(m, rng):
    """The tree that holds the tower: the winding trunk with glowing veins and a face, roots over the plinth, a second stem up the right side whose boughs carry the crown."""
    pts = helix()
    for (p, r, _), (q, r2, _) in zip(pts, pts[1:]):
        log(m, p, q, r, HAG, step=1.3, taper=r2 / r, rr=lambda t: 0.08 * math.sin(t * 9.0))
    for i, (p, r, a) in enumerate(pts):
        if i % 3 == 1:  # ridges of bark, lit
            m.ell(p + V(math.cos(a), 0.6, math.sin(a)) * (r * 0.72), (r * 0.5, r * 0.9, r * 0.45), HAG_L, R=facing(a))
        if 6 < i < 38 and i % 2 == 0:  # the vein
            m.ell(p + V(math.cos(a + 0.12), 0.0, math.sin(a + 0.12)) * (r * 0.96) + V(0, math.sin(i * 1.3) * 1.2, 0), (0.75, 1.5, 0.6), HEXG, R=facing(a), kind="emit")
    # the face, where the trunk crosses beside the door
    p, r, a = pts[15]
    out = V(math.cos(a), 0, math.sin(a))
    side = V(-math.sin(a), 0, math.cos(a))
    for s in (-1, 1):
        m.ell(p + out * (r * 0.9) + side * (s * 3.4) + V(0, 2.6, 0), (2.0, 1.3, 0.7), HEXG, R=facing(a) @ rot_z(-0.35 * s), kind="emit")
        m.ell(p + out * (r * 0.95) + side * (s * 3.4) + V(0, 5.0, 0), (3.0, 1.0, 1.0), HAG_L, R=facing(a) @ rot_z(-0.5 * s))  # the brow
    for k in range(5):
        m.ell(p + out * (r * 0.92) + side * ((k - 2) * 1.5) + V(0, -3.6 + 0.6 * abs(k - 2), 0), (0.8, 1.0 if k % 2 else 1.8, 0.6), HEXG, R=facing(a), kind="emit")  # the mouth: crooked teeth of light
    INFO["face"] = [round(v) for v in proj(*(p + out * r))]
    # roots
    base = pts[0][0]
    for k, (ang, length, r) in enumerate(((1.75, 30.0, 4.4), (1.2, 24.0, 3.8), (0.6, 21.0, 3.6), (2.3, 26.0, 3.4), (0.0, 16.0, 3.0), (2.8, 34.0, 3.0))):
        prev = base + V(0, 3.0, 0)
        for j in range(1, 6):
            t = j / 5
            wig = math.sin(j * 1.7 + k) * 2.2
            nxt = base + V(math.cos(ang) * length * t - math.sin(ang) * wig, max(0.8, 3.4 * (1 - t) ** 1.5), math.sin(ang) * length * t * 0.72 + math.cos(ang) * wig)
            log(m, prev, nxt, r * (1 - 0.72 * t) + 0.4, HAG if j % 2 else HAG_L, step=1.1)
            prev = nxt
    # shelf fungi on the trunk
    for i in (5, 8, 16, 24, 31):
        p, r, a = pts[i]
        for k in range(2):
            m.ell(p + V(math.cos(a - 0.5), 0, math.sin(a - 0.5)) * (r + 1.0) + V(0, -1.5 - k * 2.2, 0), (2.6 - 0.6 * k, 0.75, 1.9), WINE if i % 2 else WAX, R=facing(a - 0.5))
    # the bough that carries the turret
    p, r, a = pts[-1]
    log(m, p, V(TURRET[0] + 5.0, TURRET[1] - 6.0, TURRET[2] + 4.0), r, HAG, step=1.2, taper=0.7)
    log(m, V(TURRET[0] + 5.0, TURRET[1] - 6.0, TURRET[2] + 4.0), V(TURRET[0] - 14.0, TURRET[1] - 2.0, TURRET[2] + 6.0), 2.6, HAG, step=1.1, taper=0.45)
    # the second stem: up the right flank and out
    stem = [V(lean(1) + 44.0, 0.8, CZ + 6.0), V(lean(40) + 36.0, 42.0, CZ + 10.0), V(lean(90) + 31.0, 92.0, CZ + 12.0), V(lean(140) + 33.0, 140.0, CZ + 9.0), V(lean(170) + 46.0, 172.0, CZ + 6.0), V(lean(190) + 58.0, 196.0, CZ + 4.0)]
    rr = [7.4, 6.6, 5.6, 4.8, 3.9, 3.0]
    for (u, v), r0, r1 in zip(zip(stem, stem[1:]), rr, rr[1:]):
        log(m, u, v, r0, HAG, step=1.3, taper=r1 / r0, rr=lambda t: 0.07 * math.sin(t * 11.0))
        m.ell((u + v) / 2 + V(1.5, 0, r0 * 0.8), (r0 * 0.45, r0 * 1.2, r0 * 0.4), HAG_L)
    for j in range(9):  # its vein
        t = j / 8
        k = min(int(t * 4), 3)
        u, v = stem[k + 1], stem[k + 2] if k + 2 < len(stem) else stem[-1]
        m.ell(stem[1] + (stem[4] - stem[1]) * t + V(-1.0 + math.sin(j) * 1.0, 0, 5.4 - t), (0.7, 1.4, 0.6), HEXG, kind="emit")
    return stem[-1], stem[-2]


def boughs(rng, tip, below):
    """The clawed boughs at the end of the second stem: (from, to, radius) segments, and where the leaf masses sit."""
    segs, masses = [], []

    def grow(p, d, length, r, depth):
        q = p + d * length
        segs.append((p, q, r))
        if depth == 0 or r < 0.8:
            masses.append(q)
            return
        for s in (-1, 1):
            nd = d @ rot_z(s * rng.uniform(0.35, 0.75)).T + V(0, 0.18, rng.uniform(-0.15, 0.15))
            grow(q, nd / np.linalg.norm(nd), length * rng.uniform(0.62, 0.8), r * 0.62, depth - 1)
    d0 = (tip - below) / np.linalg.norm(tip - below)
    grow(tip, d0 @ rot_z(0.25).T, 17.0, 2.8, 3)
    grow(tip, d0 @ rot_z(-0.75).T, 20.0, 2.6, 3)
    grow(below, V(0.92, 0.38, 0.1), 19.0, 2.4, 2)
    return segs, masses


def bare_boughs(m, segs):
    for p, q, r in segs:
        if r >= 1.4:  # the thick ones stay with the tower, the twigs sway with the crown
            log(m, p, q, r, HAG, step=1.0, taper=0.7)


def crown(m, rng, segs, masses):
    """The swaying part: twigs, ragged dark leaf masses, witch-hair moss hanging from them, a few lights among the leaves."""
    for p, q, r in segs:
        if r < 1.4:
            m.limb(p, q, r, r * 0.5, HAG)
    for c in masses:
        for k in range(9):
            o = V(rng.uniform(-7, 7), rng.uniform(-3.5, 4.5), rng.uniform(-4, 4))
            m.ell(c + o, (rng.uniform(3.0, 5.4), rng.uniform(2.0, 3.2), rng.uniform(2.6, 4.2)), LEAF, R=rot_z(rng.uniform(-0.5, 0.5)))
        for k in range(3):  # ragged fingers hanging off the mass
            o = c + V(rng.uniform(-6, 6), -2.5, rng.uniform(-1, 3))
            m.limb(o, o + V(rng.uniform(-1.5, 1.5), -rng.uniform(6.0, 12.0), 0.5), 1.1, 0.25, LEAF)
        if rng.random() < 0.75:
            o = c + V(rng.uniform(-5, 5), -3.0, 3.0)
            m.limb(o, o + V(rng.uniform(-1.0, 1.0), -rng.uniform(9.0, 17.0), 0.3), 0.5, 0.2, HAIRM)
        if rng.random() < 0.5:
            m.ell(c + V(rng.uniform(-5, 5), rng.uniform(-3, 2), 4.6), (0.8, 0.8, 0.6), HEXG, kind="emit")


def charms(m, rng, cx):
    """What hangs from the chamber's floor ring: twig triangles, bones, rags and little lights on strings (their own swaying picture)."""
    y = CHAMBER[0] - 2.0
    for k in range(9):
        a = 0.22 + (math.pi - 0.44) * k / 8
        p = V(cx + math.cos(a) * (CH_R + 2.6), y, CZ + math.sin(a) * (CH_R + 2.6))
        length = rng.uniform(7.0, 16.0)
        m.limb(p, p + V(0, -length, 0), 0.22, 0.22, HAIRM)
        e = p + V(0, -length, 0)
        kind = k % 4
        if kind == 0:  # a triangle of twigs
            for (u, v) in ((V(-2.4, -3.6, 0), V(2.4, -3.6, 0)), (V(-2.4, -3.6, 0), V(0, 0.4, 0)), (V(2.4, -3.6, 0), V(0, 0.4, 0))):
                m.limb(e + u, e + v, 0.42, 0.42, BONE)
        elif kind == 1:  # a bone
            m.limb(e, e + V(0.6, -4.2, 0), 0.55, 0.55, BONE)
            m.ell(e + V(0.6, -4.6, 0), (1.0, 0.7, 0.6), BONE)
        elif kind == 2:  # a rag
            for j in range(3):
                m.ell(e + V(0.3 * j, -1.2 - j * 2.0, 0), (1.5 - 0.3 * j, 1.5, 0.4), WINE)
        else:  # a light in a little cage
            m.ell(e + V(0, -1.6, 0), (1.2, 1.5, 1.0), HEXG, kind="emit")
            m.ell(e + V(0, -0.2, 0), (1.3, 0.5, 1.1), IRON)


def growth(m, rng):
    """Ivy and moss on the stone, more on the left and low down; a few lights in it."""
    for k in range(7):
        a = math.pi * 0.62 + rng.uniform(0, 0.55)
        y = rng.uniform(40.0, 150.0)
        hut_lib.ivy(m, on_wall(a, y, 4.2), rng.uniform(14.0, 30.0), rng, mat=MOSS, leaf=MOSS_L)
    for k in range(46):
        a = rng.uniform(0.1, math.pi - 0.1)
        y = rng.uniform(18.0, 160.0) ** 0.5 * rng.uniform(18.0, 160.0) ** 0.5
        if rng.random() < 0.6:
            a = math.pi * 0.55 + rng.uniform(0, 0.42)
        m.ell(on_wall(a, y, 3.6), (rng.uniform(1.6, 3.2), rng.uniform(0.7, 1.2), 0.9), MOSS_L if rng.random() < 0.3 else MOSS, R=facing(a))


def model(rng, with_crown=False):
    m = h.Model()
    plinth(m, rng)
    shaft(m, rng)
    for a, y in ((1.05, 52.0), (2.25, 84.0), (0.62, 132.0), (1.55, 148.0)):
        slit(m, a, y)
    runes(m)
    growth(m, rng)
    cx, zf = gate(m, rng)
    candles(m, rng, cx, zf)
    arms = posts(m, rng, cx, zf)
    cauldron(m, rng, cx, zf)
    tip, below = elm(m, rng)
    turret(m, rng)
    corbels(m)
    ccx = chamber(m, rng)
    segs, masses = boughs(rng_for(77), tip, below)
    bare_boughs(m, segs)
    hat(m, rng, ccx)
    return m, arms, ccx, segs, masses


HAT_TONES = (
    [hexc(c) for c in ("100b1e", "1e1536", "30234e", "483666")],  # witch violet, dusky like the wood's shade
    [hexc(c) for c in ("120e1e", "231a32", "382b48", "524060")],  # dusty plum
    [hexc(c) for c in ("0d0f1a", "191d2e", "292f44", "3e465c")],  # cold slate, damp
)


# ------------------------------------------------------------------ 2D passes and the pieces
def part(name, m, seed, glow=True):
    """A separate picture (rendered alone with the tower's camera, cropped); records where it sits in the frame."""
    arr = to_array(hut_lib.render(m, FW, FH, GROUND))
    ys, xs = np.nonzero(arr[..., 3])
    x0, y0 = int(xs.min()), int(ys.min())
    crop = grain(arr[y0:int(ys.max()) + 1, x0:int(xs.max()) + 1], seed, amount=0.4, mats=GRAINED)
    save(OUT / f"{name}.png", crop)
    g = glow_of(crop, LIT)
    has_glow = glow and bool(g[..., 3].any())
    if has_glow:
        save(OUT / f"{name}_glow.png", g)
    INFO.setdefault("parts", {})[name] = {"at": [x0, y0], "size": [crop.shape[1], crop.shape[0]], "glow": has_glow}
    return arr


def pad():
    """The ground under the tower: quiet trodden earth in the Hexenwald's own ground tones (big soft zones, ordered dither, no speckle) that thins out into the grass,
    and a forecourt of worn flagstones of the keep's slate fanning out from the gate, with a tuft of moss where one is missing."""
    w, hh = 190, 96
    arr = np.zeros((hh, w, 4), np.uint8)
    earth = [hexc(c)[:3] for c in ("10161f", "141d26", "19252d")]  # trodden middle .. the rim, one step under the dark grass
    flags = [hexc(c)[:3] for c in ("1c2231", "232a3a", "2b3344")]
    joint, moss = hexc("0e131b")[:3], hexc("243a36")[:3]
    gx, gy = w / 2, 53.0  # the middle of the forecourt, a little in front of the gate's foot
    for y in range(hh):
        for x in range(w):
            dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - hh / 2) / (hh / 2)
            r = (abs(dx) ** 2.3 + abs(dy) ** 2.3) ** (1 / 2.3) + (fbm(x * 0.045, y * 0.06, 4) - 0.5) * 0.3
            b = bayer(x, y)
            if r > 0.74 + 0.26 * b:  # a wide dithered rim
                continue
            t = 1.0 - r + (fbm(x * 0.05, y * 0.07, 9) - 0.5) * 0.25 + (b - 0.5) * 0.12
            arr[y, x] = (*earth[0 if t > 0.6 else (1 if t > 0.32 else 2)], 255)
            d = math.hypot((x - gx) / 52.0, (y - gy) / 25.0) + (fbm(x * 0.07, y * 0.09, 12) - 0.5) * 0.25
            row = (y - 30) // 7
            xo = x + (row % 2) * 5 + int(hsh(row, 0, 3) * 4)
            col, lx, ly = xo // 11, xo % 11, (y - 30) % 7
            if y < 30 or d > 1.0 or r > 0.7:
                continue
            if hsh(col, row, 21) < 1.25 - d * 1.1:  # a flagstone: whole in the middle, fewer towards the rim
                corner = lx in (1, 10) and ly in (1, 6)
                if lx == 0 or ly == 0 or corner:
                    arr[y, x, :3] = joint
                else:
                    k = int(hsh(col, row, 5) * 2)
                    arr[y, x, :3] = flags[k + (1 if ly == 1 and 2 <= lx <= 8 else 0)]
            elif hsh(col, row, 33) < 0.3 and (lx, ly) in ((5, 3), (6, 3), (5, 4), (4, 4), (7, 4)):
                arr[y, x, :3] = moss
    save(OUT / "tower_pad.png", arr)


def window_strip(arr, frames=10):
    """Somebody walks past the big window: the lit pixels of the window with a hunched figure in a pointed hat crossing them. Frame 0 is the empty window."""
    x0, y0, x1, y1 = INFO["window_box"]
    x0, y0, x1, y1 = x0 - 1, y0 - 1, x1 + 2, y1 + 2
    crop = arr[y0:y1, x0:x1]
    lit = {tuple(c[:3]) for c in h.RAMPS[HEXG]}
    mask = np.array([[bool(crop[y, x, 3]) and tuple(int(v) for v in crop[y, x, :3]) in lit for x in range(crop.shape[1])] for y in range(crop.shape[0])])
    w, hh = crop.shape[1], crop.shape[0]
    shade = hexc("0c0812")
    strip = np.zeros((hh, w * frames, 4), np.uint8)
    for f in range(frames):
        frame = np.zeros_like(crop)
        frame[mask] = crop[mask]
        if f > 0:
            fx = -5 + (w + 10) * (f - 1) / (frames - 2)  # the figure's middle
            bob = 1 if f % 2 else 0
            for y in range(hh):
                for x in range(w):
                    if not mask[y, x]:
                        continue
                    u, v = x - fx, hh - 1 - y - bob  # v: up from the sill
                    body = abs(u + 0.12 * v) < 3.6 - 0.1 * v and v < 11  # a hunched back, leaning the way she walks
                    head = (u - 1.0) ** 2 + (v - 12.5) ** 2 < 5.0
                    brim = abs(u - 1.0) < 4.6 and 14.0 <= v < 15.2
                    cone = abs(u - 1.0 + 0.25 * (v - 15)) < max(0.0, 2.6 - 0.42 * (v - 15)) and v >= 15
                    nose = 3.0 < u < 5.4 and 11.5 < v < 13.0
                    if body or head or brim or cone or nose:
                        frame[y, x] = shade
        strip[:, f * w:(f + 1) * w] = frame
    save(OUT / "tower_window.png", strip)
    INFO["window_anim"] = {"at": [x0, y0], "size": [w, hh], "frames": frames}


def eye_strip():
    """The dormer is an eye: a slit pupil that looks left, ahead, right, and a blink."""
    cx, cy = INFO["eye"]
    s = 11
    g = [hexc(c) for c in ("2e6a2a", "4a9a3a", "a8ff6a", "eaffc4")]
    dark = hexc("0c0812")
    looks = [0, -2, -2, 0, 2, 2, 0, None]  # None = shut
    strip = np.zeros((s, s * len(looks), 4), np.uint8)
    for f, look in enumerate(looks):
        for y in range(s):
            for x in range(s):
                u, v = x - s // 2, y - s // 2
                d = math.hypot(u, v)
                if d > 4.6:
                    continue
                if look is None:
                    c = g[2] if abs(v) < 1 and abs(u) < 4 else (dark if d < 4.2 else g[0])
                else:
                    c = g[3] if d < 2.0 else (g[2] if d < 3.4 else g[1])
                    if abs(u - look) < 1 and abs(v) < 3.6:
                        c = dark
                    if (u - look, v) == (1, -2):
                        c = g[3]
                strip[y, f * s + x] = c
    save(OUT / "tower_eye.png", strip)
    INFO["eye_anim"] = {"at": [cx - s // 2, cy - s // 2], "size": [s, s], "frames": len(looks)}


def cauldron_strip(frames=6):
    """The brew bubbles: the pot's lit surface with bubbles that swell and burst, a drip over the rim now and then."""
    cx, cy = INFO["cauldron"]
    w, hh = 15, 9
    g = [hexc(c) for c in ("123a2a", "1e6a3a", "4ac85a", "c8ffa0")]
    strip = np.zeros((hh, w * frames, 4), np.uint8)
    spots = ((3, 5, 0), (8, 4, 2), (11, 6, 4), (6, 6, 3))
    for f in range(frames):
        for y in range(hh):
            for x in range(w):
                u, v = (x - 7) / 6.0, (y - 5.5) / 2.2
                if u * u + v * v > 1.0:
                    continue
                c = g[1] if (x + y + f) % 5 else g[2]
                strip[y, f * w + x] = c
        for bx, by, ph in spots:
            age = (f + ph) % frames
            if age < 3:
                r = age
                for dy in range(-r, 1):
                    for dx in range(-r, r + 1):
                        if dx * dx + dy * dy <= r * r + 0.5 and 0 <= by + dy < hh:
                            strip[by + dy, f * w + bx + dx] = g[3] if (dx, dy) == (-max(r - 1, 0), -r) or r == 0 else g[2]
            elif age == 3:  # burst: a ring of sparks
                for dx, dy in ((-2, -2), (2, -2), (0, -3)):
                    if 0 <= by + dy < hh and 0 <= bx + dx < w:
                        strip[by + dy, f * w + bx + dx] = g[3]
    save(OUT / "tower_cauldron.png", strip)
    INFO["cauldron_anim"] = {"at": [cx - 7, cy - 6], "size": [w, hh], "frames": frames}


def veil(arr):
    """Age on the stone: damp streaks running down from the brim and the slits, a darker foot, lichen (one shade lighter) on the weather side."""
    lut = {tuple(c[:3]): (mat, b) for mat in (CSTONE, CSTONE_L) for b, c in enumerate(h.RAMPS[mat])}
    out = arr.copy()
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            key = tuple(int(v) for v in arr[y, x, :3])
            if not arr[y, x, 3] or key not in lut:
                continue
            mat, b = lut[key]
            streak = fbm(x * 0.55, y * 0.045, 31)
            foot = max(0.0, (y - (GROUND - 46)) / 46.0)
            n = hsh(x, y, 17)
            if (streak > 0.63 and n < 0.7) or (foot > 0.35 and n < foot * 0.6):
                b = max(0, b - 1)
            elif fbm(x * 0.12, y * 0.12, 44) > 0.66 and x < FW * 0.5 and n < 0.5:
                b = min(3, b + 1)
            out[y, x, :3] = h.RAMPS[mat][b][:3]
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    hut_lib.ROOF_TONES = HAT_TONES
    rng = rng_for(613)
    m, arms, ccx, segs, masses = model(rng)
    raw = to_array(hut_lib.render(m, FW, FH, GROUND))
    arr = hut_lib.roof_pass(raw, 613, rowh=4, wid=6, moss=0.1, shadow=7)
    arr = veil(arr)
    arr = grain(arr, 613, amount=0.5, mats=GRAINED)
    arr = hut_lib.soft_shadow(arr, FW / 2 - 2, GROUND + 2, 84, 13, alpha=90)
    save(OUT / "tower.png", arr)
    save(OUT / "tower_glow.png", glow_of(arr, LIT + (FIRE,)))
    window_strip(arr)
    eye_strip()
    cauldron_strip()
    pad()
    cm = h.Model()
    crown(cm, rng_for(78), segs, masses)
    part("tower_crown", cm, 21)
    hm = h.Model()
    charms(hm, rng_for(79), ccx)
    part("tower_charms", hm, 22)
    for name, arm in zip(("tower_lantern_l", "tower_lantern_r"), arms):
        lm = h.Model()
        lantern(lm, arm)
        part(name, lm, 23)
        INFO.setdefault("lanterns", []).append([round(v) for v in proj(arm[0], arm[1] - 5.8, arm[2])])
    INFO.update({"frame": [FW, FH], "ground": GROUND, "pad": {"size": [190, 96], "feet": 44}})
    (OUT / "witch_tower.json").write_text(json.dumps(INFO, indent=1) + "\n", encoding="utf-8")
    print("witch tower", arr.shape, {k: v for k, v in INFO.items() if k != "parts"})
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image
        def compose(night):
            comp = Image.new("RGBA", (FW + 40, FH + 16), (19, 30, 38, 255) if not night else (8, 11, 20, 255))
            o = (20, 8)
            padi = Image.open(OUT / "tower_pad.png")
            comp.alpha_composite(padi, (o[0] + FW // 2 - 95, o[1] + GROUND - 44))
            layers = [Image.fromarray(arr)] + [None]
            comp_t = Image.new("RGBA", comp.size, (0, 0, 0, 0))
            comp_t.alpha_composite(Image.fromarray(arr), o)
            for name, p_ in INFO["parts"].items():
                comp_t.alpha_composite(Image.open(OUT / f"{name}.png"), (o[0] + p_["at"][0], o[1] + p_["at"][1]))
            if night:
                dark = Image.new("RGBA", comp.size, (10, 14, 40, 150))
                comp_t = Image.composite(Image.alpha_composite(comp_t, dark), comp_t, comp_t.split()[3])
                comp.alpha_composite(comp_t)
                comp.alpha_composite(Image.open(OUT / "tower_glow.png"), o)
                for name, p_ in INFO["parts"].items():
                    if p_["glow"]:
                        comp.alpha_composite(Image.open(OUT / f"{name}_glow.png"), (o[0] + p_["at"][0], o[1] + p_["at"][1]))
                w = INFO["window_anim"]
                comp.alpha_composite(Image.open(OUT / "tower_window.png").crop((w["size"][0] * 5, 0, w["size"][0] * 6, w["size"][1])), (o[0] + w["at"][0], o[1] + w["at"][1]))
            else:
                comp.alpha_composite(comp_t)
            return comp
        day, night = compose(False), compose(True)
        sheet = Image.new("RGBA", (day.width * 2, day.height))
        sheet.paste(day, (0, 0))
        sheet.paste(night, (day.width, 0))
        sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(png[0])


if __name__ == "__main__":
    main()
