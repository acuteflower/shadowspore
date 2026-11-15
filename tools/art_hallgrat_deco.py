#!/usr/bin/env python3
"""The small things of Hallgrat's streets (docs/stadt_westen_konzept.md 14.7): what makes the stone town look lived in. Built with the same
ellipsoid renderer, stone and wood as its houses (tools/art_hallgrat_houses.py), so they belong to them:

  (the low walls along the ways are built per run by tools/art_hallgrat_walls.py)
  fass, kisten, saecke, kruege, holz, heu, karren      what stands at a house's wall or a shop: barrels, crates, sacks, clay jugs, a woodpile,
                              a hay bale, a handcart
  bank_ew / bank_ns, trog     a stone bench, a stone trough with water
  laterne                     an iron lantern post (its glass shines at night, a warm light at its foot)
  kuebel, urne, beet          a stone planter with flowers, a tall urn with trailing ivy, a flat bed of flowers in a ring of stones
  prellstein, steine, saeule  a bollard, a heap of rubble, the stub of a broken column (the half abandoned Fuß and the lost quarter)
  brunnen                     a small well with a winch
  waesche, schild, koerbe     a washing line, a shop's hanging sign, baskets of the harvest
  hackklotz, quader           a chopping block with its axe, the stonemason's stacked blocks
  fahne, schrein              a banner pole of the town, a wayside shrine with candles (they shine at night)
  zaun_ew / zaun_ns, acker    a wooden fence, two rows of a kitchen field (walked over)

Every picture goes to assets/town/hallgrat/deko_<name>.png (+ _glow.png) and its numbers into data/hallgrat_art.json `types` (the house script
keeps them): size, feet (the middle of the front edge on the ground), foot (footprint px), poly (turned footprint of a diagonal wall), solid,
lights. `HallgratBuilding` draws them; tools/place_hallgrat_deco.py places them.

    py -3 tools/art_hallgrat_deco.py [preview.png]      then      Godot --headless --path . --import"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hallgrat_houses as hh  # noqa: E402  (sets the town's stone ramps)
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import (BARK, BARK_D, CLAY, FIRE, IRON, LINEN, MOSS, MOSS_L, PLANK, PLANK_W, SOIL, STONE, STONE_L, STRAW,  # noqa: E402
                     V, glow_of, log, rng_for, save, slab, to_array)
from gen_art import hexc  # noqa: E402

S = h.SCALE
G = 1.6          # every deco model is grown like the stalls: 1 unit = S * G px (about 1.47)
CANVAS = (260, 220, 160)
WATER = len(h.RAMPS)
h.RAMPS.append([hexc(c) for c in ("0e2232", "1a4258", "2c6a80", "6ab4c0")])
BLOOMS = (hh.WINE, hh.OCHRE, hh.PLUM, hh.FRUIT)


# ------------------------------------------------------------------ pieces
def stones_course(m, rng, x0, x1, y, z, hgt, depth, mats=(STONE, STONE, STONE_L)):
    x = x0
    while x < x1 - 0.8:
        w = rng.uniform(3.6, 6.4)
        hi = min(x + w, x1)
        m.ell(V((x + hi) / 2, y + hgt / 2, z + rng.uniform(-0.4, 0.4)), ((hi - x) / 2 * 0.98, hgt / 2, depth), mats[int(rng.random() * len(mats))])
        x += w


def barrel(m, x, z, y0=0.0, lying=False, rng=None):
    if lying:
        for k in range(7):
            xx = x - 4.5 + k * 1.5
            r = 4.0 - abs(k - 3) * 0.25
            m.ell(V(xx, r, z), (0.9, r, r), PLANK_W if k % 2 else PLANK)
        for xx in (x - 3.2, x + 3.2):
            m.ell(V(xx, 3.9, z), (0.5, 4.0, 4.0), IRON)
        m.ell(V(x + 5.1, 3.6, z), (0.4, 3.2, 3.2), PLANK_W)
        return
    for k in range(9):
        y = y0 + 0.7 + k * 1.45
        r = 4.0 + 0.5 * math.sin(k / 8 * math.pi)
        m.ell(V(x, y, z), (r, 0.9, r * 0.92), PLANK if k % 2 else PLANK_W)
    for y in (y0 + 2.4, y0 + 10.6):
        m.ell(V(x, y, z), (4.4, 0.55, 4.1), IRON)
    m.ell(V(x, y0 + 13.4, z), (3.8, 0.5, 3.5), PLANK_W)


def crate(m, x, y, z, s=4.6, mat=PLANK):
    m.ell(V(x, y + s, z), (s, s, s * 0.9), mat)
    for yy in (y + 1.0, y + 2 * s - 1.0):
        slab(m, V(x - s, yy, z + s * 0.9), V(x + s, yy, z + s * 0.9), 0.9, 0.4, BARK_D, (0, 0, 1), step=0.9)
    log(m, V(x - s + 0.6, y + 1.0, z + s * 0.95), V(x + s - 0.6, y + 2 * s - 1.0, z + s * 0.95), 0.35, BARK_D, step=0.7)


def sack(m, x, z, rng, mat=LINEN, tall=1.0):
    m.ell(V(x, 3.0 * tall, z), (3.6, 3.2 * tall, 3.0), mat)
    m.ell(V(x + 0.3, 6.0 * tall, z), (1.6, 1.4, 1.4), mat)
    m.ell(V(x + 0.3, 7.0 * tall, z), (0.8, 0.5, 0.8), STRAW)


def flowers(m, rng, cx, y, cz, rx, rz, n=9):
    for k in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random())
        p = V(cx + math.cos(a) * rx * d, y, cz + math.sin(a) * rz * d)
        tip = p + V(rng.uniform(-0.6, 0.6), rng.uniform(2.0, 3.6), rng.uniform(-0.3, 0.3))
        m.limb(p, tip, 0.35, 0.2, MOSS_L)
        m.ell(tip + V(0.6, -0.8, 0.3), (1.0, 0.4, 0.7), MOSS_L, R=h.rot_x(0.5))
        m.ell(tip, (0.9, 0.8, 0.9), BLOOMS[int(rng.random() * len(BLOOMS))])


def fass(rng):
    m = h.Model()
    barrel(m, -3.0, 0.0)
    barrel(m, 4.6, 1.6)
    if rng.random() < 0.7:
        m.ell(V(0.8, 0.8, 5.0), (2.0, 0.8, 1.2), PLANK_W)       # a lid leaning down
    return m, dict(W=9.0, D=4.5)


def fass_lieg(rng):
    m = h.Model()
    barrel(m, 0.0, 0.0, lying=True)
    barrel(m, 8.5, -2.0)
    return m, dict(W=13.0, D=4.5)


def kisten(rng):
    m = h.Model()
    crate(m, -2.6, 0.0, 0.0)
    crate(m, 6.0, 0.0, 1.0, 3.8, PLANK_W)
    crate(m, -1.8, 9.2, -0.4, 3.9, PLANK_W)
    return m, dict(W=10.0, D=4.5)


def saecke(rng):
    m = h.Model()
    sack(m, -3.4, 0.0, rng)
    sack(m, 3.0, 0.8, rng, tall=0.85)
    sack(m, 0.0, 4.0, rng, mat=STRAW, tall=0.7)
    for k in range(6):                                           # spilt grain
        m.ell(V(rng.uniform(-2, 4), 0.3, rng.uniform(5.5, 7.5)), (0.7, 0.3, 0.5), STRAW)
    return m, dict(W=7.0, D=4.5)


def kruege(rng):
    m = h.Model()
    for k, (x, z, s) in enumerate(((-3.6, 0.0, 1.0), (1.4, -0.6, 1.25), (4.6, 2.2, 0.8))):
        m.ell(V(x, 3.0 * s, z), (2.4 * s, 3.0 * s, 2.2 * s), CLAY)
        m.ell(V(x, 6.2 * s, z), (1.1 * s, 0.9 * s, 1.0 * s), CLAY)
        m.ell(V(x, 6.9 * s, z), (1.4 * s, 0.4, 1.3 * s), CLAY)
        if k == 1:
            log(m, V(x + 2.4, 5.6, z), V(x + 3.2, 3.2, z), 0.4, CLAY, step=0.6)
    return m, dict(W=7.0, D=3.5)


def holz(rng):
    m = h.Model()
    for row in range(4):
        for k in range(5 - row):
            x = -8.0 + row * 1.9 + k * 3.8
            y = 1.8 + row * 3.2
            log(m, V(x, y, -3.0), V(x, y, 3.0), 1.8, BARK, step=1.0)
            m.ell(V(x, y, 3.1), (1.6, 1.6, 0.4), PLANK_W)
    for x in (-10.5, 10.5):
        log(m, V(x, 0.0, 3.4), V(x, 13.0, 3.4), 0.6, BARK_D, step=0.9)
    return m, dict(W=11.0, D=3.6)


def heu(rng):
    m = h.Model()
    m.ell(V(0.0, 4.6, 0.0), (7.0, 4.6, 4.6), STRAW)
    for y in (2.6, 6.6):
        m.ell(V(0.0, y, 0.0), (7.2, 0.4, 4.8), BARK_D)
    for k in range(8):
        a = rng.uniform(0, math.tau)
        hut_lib.tuft(m, V(math.cos(a) * 7.0, rng.uniform(1, 8), math.sin(a) * 4.4), rng, blades=3, height=1.6, mat=STRAW)
    return m, dict(W=7.5, D=5.0)


def karren(rng):
    m = h.Model()
    slab(m, V(-8.0, 6.0, 0.0), V(6.0, 6.0, 0.0), 4.6, 0.6, PLANK, (0, 1, 0), step=1.0)
    for z in (-4.4, 4.4):
        slab(m, V(-8.0, 7.6, z), V(6.0, 7.6, z), 1.4, 0.4, PLANK_W, (0, 0, 1), step=1.0)
    for z in (-1.8, 1.8):
        log(m, V(-8.0, 6.0, z), V(-16.0, 2.2, z * 1.4), 0.55, BARK, step=0.8)
    for k in range(12):                                          # the near wheel
        a = k / 12 * math.tau
        m.ell(V(0.5 + math.cos(a) * 4.6, 4.8 + math.sin(a) * 4.6, 5.4), (1.0, 1.0, 0.6), PLANK_W)
    for k in range(4):
        a = k / 4 * math.pi
        log(m, V(0.5 - math.cos(a) * 4.2, 4.8 - math.sin(a) * 4.2, 5.4), V(0.5 + math.cos(a) * 4.2, 4.8 + math.sin(a) * 4.2, 5.4), 0.3, BARK, step=0.6)
    m.ell(V(0.5, 4.8, 5.6), (0.9, 0.9, 0.5), IRON)
    sack(m, -3.0, 0.0, rng, tall=0.6)
    m.prims[-3].c = m.prims[-3].c + V(0, 6.0, 0)
    m.prims[-2].c = m.prims[-2].c + V(0, 6.0, 0)
    m.prims[-1].c = m.prims[-1].c + V(0, 6.0, 0)
    return m, dict(W=11.0, D=5.6)


def bank(rng):
    m = h.Model()
    for x in (-7.0, 7.0):
        m.ell(V(x, 3.0, 0.0), (1.8, 3.2, 2.6), STONE)
    m.ell(V(0.0, 6.6, 0.0), (10.0, 1.1, 3.4), STONE_L)
    hut_lib.tuft(m, V(-9.0, 0.0, 2.4), rng, blades=4, height=2.4)
    return m, dict(W=10.0, D=3.4)


def trog(rng):
    m = h.Model()
    for z in (-3.4, 3.4):
        stones_course(m, rng, -9.0, 9.0, 0.0, z, 6.6, 1.2)
    for x in (-9.0, 9.0):
        m.ell(V(x, 3.3, 0.0), (1.3, 3.3, 3.8), STONE)
    m.ell(V(0.0, 5.9, 0.0), (8.0, 0.35, 2.4), WATER)
    for k in range(3):
        m.ell(V(rng.uniform(-6, 6), 6.6, 3.6), (1.4, 0.5, 0.5), MOSS)
    return m, dict(W=10.0, D=4.4)


def laterne(rng):
    m = h.Model()
    m.ell(V(0.0, 0.8, 0.0), (3.0, 0.9, 2.6), STONE_L)
    log(m, V(0.0, 1.0, 0.0), V(0.0, 30.0, 0.0), 0.75, IRON, step=1.0)
    log(m, V(0.0, 27.5, 0.0), V(4.8, 29.0, 0.0), 0.45, IRON, step=0.7)
    log(m, V(0.0, 23.0, 0.0), V(3.6, 28.0, 0.0), 0.3, IRON, step=0.6)
    lx, ly = 5.2, 25.0
    m.ell(V(lx, ly + 4.2, 0.0), (2.6, 0.7, 2.4), IRON)               # cap and cage
    for a in (0.6, 2.2, 3.8, 5.4):
        log(m, V(lx + math.cos(a) * 1.9, ly - 1.6, math.sin(a) * 1.7), V(lx + math.cos(a) * 1.9, ly + 3.6, math.sin(a) * 1.7), 0.25, IRON, step=0.5)
    m.ell(V(lx, ly + 1.0, 0.0), (1.6, 2.4, 1.5), FIRE)                # the glass (the window pass turns it into calm honey light)
    m.ell(V(lx, ly - 1.9, 0.0), (2.0, 0.5, 1.8), IRON)
    return m, dict(W=4.0, D=3.0, light=True)


def kuebel(rng):
    m = h.Model()
    for z in (-3.6, 3.6):
        stones_course(m, rng, -5.0, 5.0, 0.0, z, 5.6, 1.0, mats=(STONE_L,))
    for x in (-5.0, 5.0):
        m.ell(V(x, 2.8, 0.0), (1.0, 2.8, 4.0), STONE_L)
    m.ell(V(0.0, 5.0, 0.0), (4.2, 0.6, 2.8), SOIL)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        m.ell(V(math.cos(a) * 2.6, 6.6, math.sin(a) * 1.6), (2.0, 1.4, 1.6), MOSS)
    flowers(m, rng, 0.0, 5.4, 0.0, 3.8, 2.4, n=11)
    return m, dict(W=5.5, D=4.0)


def urne(rng):
    m = h.Model()
    m.ell(V(0.0, 1.0, 0.0), (3.4, 1.0, 3.0), STONE_L)
    for k in range(8):
        y = 2.0 + k * 1.5
        r = 2.4 + 1.6 * math.sin(min(1.0, k / 6) * math.pi * 0.9)
        m.ell(V(0.0, y, 0.0), (r, 0.9, r * 0.9), CLAY)
    m.ell(V(0.0, 13.6, 0.0), (3.4, 0.6, 3.0), CLAY)
    m.ell(V(0.0, 14.0, 0.0), (2.8, 0.5, 2.4), SOIL)
    for k in range(4):
        a = rng.uniform(0, math.tau)
        m.ell(V(math.cos(a) * 1.4, 15.4, math.sin(a) * 1.0), (1.8, 1.4, 1.5), MOSS_L)
    hut_lib.ivy(m, V(2.6, 14.0, 1.6), 9.0, rng, sway=0.6)
    hut_lib.ivy(m, V(-2.4, 14.0, 1.8), 6.0, rng, sway=0.5)
    flowers(m, rng, 0.0, 14.6, 0.0, 2.0, 1.4, n=5)
    return m, dict(W=3.6, D=3.2)


def beet(rng):
    m = h.Model()
    for k in range(16):
        a = k / 16 * math.tau
        m.ell(V(math.cos(a) * 9.0, 0.8, math.sin(a) * 5.0), (1.6, 1.1, 1.3), (STONE, STONE_L)[k % 2])
    m.ell(V(0.0, 0.4, 0.0), (8.2, 0.4, 4.4), SOIL)
    for k in range(6):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 1)
        m.ell(V(math.cos(a) * 5.5 * d, 1.4, math.sin(a) * 3.0 * d), (2.0, 1.2, 1.5), MOSS)
    flowers(m, rng, 0.0, 0.8, 0.0, 7.0, 3.8, n=18)
    return m, dict(W=10.0, D=5.6, solid=False)


def prellstein(rng):
    m = h.Model()
    for k in range(6):
        y = 0.8 + k * 1.4
        m.ell(V(0.0, y, 0.0), (2.5 - k * 0.12, 0.9, 2.2 - k * 0.1), STONE_L if k > 3 else STONE)
    m.ell(V(0.0, 8.8, 0.0), (1.8, 1.0, 1.6), STONE_L)
    for k in range(10):
        a = k / 10 * math.tau
        m.ell(V(math.cos(a) * 1.0, 5.6 + math.sin(a) * 1.0, 2.4), (0.35, 0.35, 0.3), IRON)
    return m, dict(W=2.6, D=2.4)


def steine(rng):
    m = h.Model()
    for k in range(9):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 1)
        r = rng.uniform(1.4, 3.0)
        m.ell(V(math.cos(a) * 6.0 * d, r * 0.7 + (2.0 if d < 0.4 else 0.0), math.sin(a) * 3.0 * d), (r * 1.2, r * 0.8, r), (STONE, STONE_L)[k % 2],
              R=h.rot_y(rng.uniform(0, 3)))
    for k in range(3):
        hut_lib.tuft(m, V(rng.uniform(-6, 6), 0.0, rng.uniform(-1, 3)), rng, blades=4, height=2.6)
    m.ell(V(rng.uniform(-3, 3), 3.0, 1.0), (2.4, 0.7, 1.6), MOSS)
    return m, dict(W=7.0, D=3.6, solid=False)


def saeule(rng):
    m = h.Model()
    m.ell(V(0.0, 1.0, 0.0), (5.0, 1.2, 4.2), STONE_L)
    m.ell(V(0.0, 2.6, 0.0), (4.2, 0.9, 3.6), STONE)
    for k in range(9):
        y = 3.6 + k * 1.6
        cut = 1.0 if k < 7 else 0.6 + 0.2 * (k - 7)
        m.ell(V(0.0 + (0.6 if k == 8 else 0.0), y, 0.0), (3.0 * cut, 1.0, 2.7 * cut), STONE_L if k % 3 else STONE)
    m.ell(V(5.8, 1.8, 3.6), (3.4, 1.8, 2.4), STONE_L, R=h.rot_y(0.5))   # the fallen drum
    hut_lib.ivy(m, V(-2.0, 16.0, 2.6), 12.0, rng, sway=0.7)
    hut_lib.tuft(m, V(-4.0, 0.0, 3.0), rng, blades=5, height=3.0)
    return m, dict(W=6.0, D=4.4)


def brunnen(rng):
    m = h.Model()
    for k in range(14):
        a = k / 14 * math.tau
        for y in (1.6, 4.6):
            m.ell(V(math.cos(a) * 6.2, y, math.sin(a) * 5.2), (2.0, 1.6, 1.4), (STONE, STONE_L)[(k + int(y)) % 2], R=h.rot_y(-a))
        m.ell(V(math.cos(a) * 6.2, 6.8, math.sin(a) * 5.2), (2.1, 0.7, 1.6), STONE_L, R=h.rot_y(-a))
    m.ell(V(0.0, 6.0, 0.0), (4.6, 0.3, 3.8), hut_lib.GAP)
    for x in (-6.4, 6.4):
        log(m, V(x, 6.0, 0.0), V(x, 21.0, 0.0), 0.8, BARK, step=1.0)
    log(m, V(-7.6, 19.0, 0.0), V(7.6, 19.0, 0.0), 0.9, BARK_D, step=1.0)
    log(m, V(0.0, 19.0, 0.0), V(0.0, 11.0, 0.0), 0.15, LINEN, step=0.5)
    barrel(m, 0.0, 0.0, y0=0.0)
    for p in m.prims[-12:]:                                         # the bucket: a small barrel hanging on the rope
        p.c = V(p.c[0] * 0.45, p.c[1] * 0.4 + 6.6, p.c[2] * 0.45)
        p.r = p.r * 0.45
    for k in range(4):
        hut_lib.tuft(m, V(math.cos(k * 1.7) * 7.2, 0.0, math.sin(k * 1.7) * 6.0), rng, blades=4, height=2.6)
    return m, dict(W=8.0, D=6.5)


def waesche(rng):
    """A washing line between two posts, sheets and shirts on it."""
    m = h.Model()
    for x in (-12.0, 12.0):
        log(m, V(x, 0.0, 0.0), V(x, 19.0, 0.0), 0.55, BARK, step=0.9)
        m.ell(V(x, 0.6, 0.0), (1.4, 0.7, 1.2), STONE)
    pts = [V(-12.0 + 24.0 * t, 18.4 - 2.2 * math.sin(t * math.pi), 0.0) for t in (k / 8 for k in range(9))]
    for a, b in zip(pts, pts[1:]):
        log(m, a, b, 0.14, LINEN, step=0.5)
    x = -9.5
    cloths = (LINEN, hh.WINE, LINEN, hh.OCHRE, hh.PLUM, LINEN)
    while x < 8.5:
        w = rng.uniform(1.6, 3.2)
        t = (x + w / 2 + 12.0) / 24.0
        top = 18.2 - 2.2 * math.sin(t * math.pi)
        drop = rng.uniform(4.5, 8.0)
        slab(m, V(x + w / 2, top, 0.1), V(x + w / 2 + rng.uniform(-0.4, 0.4), top - drop, 0.25), w, 0.25, cloths[int(rng.random() * len(cloths))],
             (0, 0, 1), step=0.8)
        x += w * 2 + rng.uniform(0.4, 1.4)
    hut_lib.tuft(m, V(-12.5, 0.0, 1.0), rng, blades=4, height=2.4)
    return m, dict(W=12.8, D=1.6)


def schild(rng):
    """A shop sign: a post with an iron arm, a board hanging from it, the trade painted on it."""
    m = h.Model()
    m.ell(V(0.0, 0.7, 0.0), (1.8, 0.8, 1.6), STONE_L)
    log(m, V(0.0, 0.5, 0.0), V(0.0, 21.0, 0.0), 0.6, BARK_D, step=0.9)
    log(m, V(0.0, 19.5, 0.0), V(7.5, 19.5, 0.0), 0.3, IRON, step=0.6)
    log(m, V(0.0, 16.5, 0.0), V(4.5, 19.5, 0.0), 0.22, IRON, step=0.6)
    for x in (3.4, 6.6):
        log(m, V(x, 19.5, 0.0), V(x, 17.6, 0.0), 0.12, IRON, step=0.4)
    slab(m, V(5.0, 17.6, 0.0), V(5.0, 12.4, 0.0), 4.4, 0.4, PLANK_W, (0, 0, 1), step=0.8)
    mark = (hh.WINE, hh.OCHRE, hh.FRUIT)[int(rng.random() * 3)]
    m.ell(V(5.0, 15.0, 0.45), (1.5, 1.3, 0.2), mark)
    m.ell(V(5.0, 12.6, 0.35), (2.3, 0.3, 0.25), BARK_D)
    return m, dict(W=4.0, D=1.8)


def koerbe(rng):
    """Baskets of the harvest: fruit, roots, greens."""
    m = h.Model()
    for x, z in ((-3.6, 0.6), (0.4, -0.8), (3.8, 0.8)):
        m.ell(V(x, 1.7, z), (2.3, 1.7, 2.0), STRAW)
        m.ell(V(x, 3.2, z), (2.4, 0.4, 2.1), BARK)
        fruit = (hh.FRUIT, hh.WINE, hh.OCHRE, hh.GREEN)[int(rng.random() * 4)]
        for k in range(6):
            m.ell(V(x + rng.uniform(-1.3, 1.3), 3.6 + rng.uniform(0, 0.8), z + rng.uniform(-1.1, 1.1)), (0.8, 0.75, 0.8), fruit)
    return m, dict(W=6.6, D=3.0)


def hackklotz(rng):
    """A chopping block with the axe in it, split wood around it."""
    m = h.Model()
    m.ell(V(0.0, 2.3, 0.0), (2.7, 2.3, 2.4), BARK)
    m.ell(V(0.0, 4.5, 0.0), (2.5, 0.3, 2.2), PLANK_W)
    log(m, V(0.4, 4.6, 0.2), V(3.2, 10.0, 0.9), 0.35, PLANK, step=0.6)
    m.ell(V(0.2, 5.0, 0.1), (1.5, 0.9, 0.35), IRON, R=h.rot_z(0.4) if hasattr(h, "rot_z") else None)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        x, z = math.cos(a) * rng.uniform(3.5, 5.5), math.sin(a) * rng.uniform(2.0, 3.0)
        log(m, V(x - 1.2, 0.6, z), V(x + 1.2, 0.6, z + rng.uniform(-0.6, 0.6)), 0.55, PLANK_W, step=0.6)
    hut_lib.tuft(m, V(-3.0, 0.0, 2.0), rng, blades=4, height=2.0)
    return m, dict(W=5.2, D=3.4)


def fahne(rng):
    """A banner pole of the town: a long wine-red banner with a gold hem."""
    m = h.Model()
    for k in range(6):
        a = k / 6 * math.tau
        m.ell(V(math.cos(a) * 1.9, 0.9, math.sin(a) * 1.6), (1.3, 0.9, 1.1), (STONE, STONE_L)[k % 2])
    log(m, V(0.0, 0.5, 0.0), V(0.0, 36.0, 0.0), 0.45, BARK_D, step=1.0)
    m.ell(V(0.0, 36.6, 0.0), (0.7, 0.7, 0.7), hh.OCHRE)
    log(m, V(-0.2, 33.0, 0.0), V(5.2, 33.0, 0.0), 0.22, IRON, step=0.6)
    for k in range(10):
        y = 32.6 - k * 1.45
        sway = math.sin(k * 0.6) * 0.5
        slab(m, V(2.6 + sway, y, 0.2), V(2.6 + sway, y - 1.5, 0.2), 4.6 - (0.6 if k > 7 else 0.0) - (k - 7) * 0.7 * (k > 7), 0.2,
             hh.WINE, (0, 0, 1), step=0.8)
    m.ell(V(2.6, 30.0, 0.45), (1.2, 1.2, 0.15), hh.OCHRE)
    m.ell(V(2.6 + math.sin(9 * 0.6) * 0.5, 18.4, 0.35), (1.6, 0.25, 0.2), hh.OCHRE)
    return m, dict(W=3.0, D=2.2)


def schrein(rng):
    """A wayside shrine: a stone niche under a little slate roof, candles burning, flowers laid before it."""
    m = h.Model()
    stones_course(m, rng, -4.0, 4.0, 0.0, 0.0, 3.0, 2.6)
    for x in (-3.4, 3.4):
        for k in range(4):
            m.ell(V(x, 4.0 + k * 2.4, 0.0), (1.2, 1.2, 2.2), (STONE, STONE_L)[k % 2])
    m.ell(V(0.0, 8.0, -1.4), (2.4, 4.6, 0.8), STONE)                  # the back of the niche
    m.ell(V(0.0, 14.6, 0.0), (5.4, 0.9, 3.2), STONE_L)
    m.ell(V(0.0, 16.2, 0.0), (4.4, 1.1, 2.6), hh.ROOF if hasattr(hh, "ROOF") else STONE_L)
    m.ell(V(0.0, 9.0, -0.6), (1.1, 2.6, 0.8), STONE_L)                # the small figure
    m.ell(V(0.0, 12.0, -0.6), (0.8, 0.8, 0.7), STONE_L)
    for x in (-1.9, 0.0, 1.9):
        log(m, V(x, 3.2, 1.2), V(x, 4.6 + (0.6 if x == 0 else 0.0), 1.2), 0.32, LINEN, step=0.4)
        m.ell(V(x, 5.2 + (0.6 if x == 0 else 0.0), 1.2), (0.3, 0.55, 0.3), FIRE)
    flowers(m, rng, 0.0, 0.6, 3.6, 3.0, 0.8, n=6)
    return m, dict(W=5.0, D=3.6, light=True)


def quader(rng):
    """Cut blocks of the stonemason, stacked to dry, a few lying loose, chips round them."""
    m = h.Model()
    for row, xs in ((0, (-5.6, -0.4, 4.8)), (1, (-3.0, 2.2)), (2, (-0.4,))):
        for x in xs:
            m.ell(V(x + rng.uniform(-0.3, 0.3), 1.9 + row * 3.6, rng.uniform(-0.3, 0.3)), (2.6, 1.8, 2.3), (STONE_L, STONE)[int(rng.random() * 2)])
    m.ell(V(8.6, 1.4, 2.0), (2.0, 1.4, 1.8), STONE_L, R=h.rot_y(0.5))
    for k in range(7):
        m.ell(V(rng.uniform(-8, 9), 0.4, rng.uniform(1.5, 3.4)), (0.6, 0.4, 0.5), STONE_L)
    return m, dict(W=9.5, D=3.6)


def zaun(rng):
    """A short wooden fence: posts and two rails, one rail sagging."""
    m = h.Model()
    xs = [-10.0, -5.0, 0.0, 5.0, 10.0]
    for x in xs:
        log(m, V(x, 0.0, 0.0), V(x + rng.uniform(-0.3, 0.3), 8.4 + rng.uniform(-0.5, 0.5), 0.0), 0.5, BARK, step=0.8)
    log(m, V(-10.0, 6.8, 0.2), V(10.0, 6.6, 0.2), 0.32, PLANK, step=0.8)
    log(m, V(-10.0, 3.4, 0.2), V(0.0, 2.6, 0.2), 0.3, PLANK, step=0.8)
    log(m, V(0.0, 2.6, 0.2), V(10.0, 3.3, 0.2), 0.3, PLANK, step=0.8)
    for k in range(3):
        hut_lib.tuft(m, V(rng.uniform(-9, 9), 0.0, 0.8), rng, blades=4, height=2.6)
    return m, dict(W=10.6, D=0.9)


def acker(rng):
    """Two rows of a kitchen field: furrows of dark earth, cabbages, roots, now and then a pumpkin (walked over)."""
    m = h.Model()
    for z in (-1.6, 1.6):
        for k in range(7):
            m.ell(V(-11.0 + k * 3.7, 0.3, z), (2.4, 0.5, 1.1), SOIL)
        x = -11.0
        while x < 11.5:
            q = rng.random()
            if q < 0.12:
                m.ell(V(x, 1.4, z), (1.5, 1.3, 1.4), hh.OCHRE)
                m.ell(V(x, 2.8, z), (0.3, 0.5, 0.3), MOSS)
            elif q < 0.6:
                m.ell(V(x, 1.3, z), (1.3, 1.1, 1.2), hh.GREEN)
                m.ell(V(x - 0.5, 1.8, z + 0.4), (0.9, 0.6, 0.7), MOSS_L)
            else:
                hut_lib.tuft(m, V(x, 0.4, z), rng, blades=4, height=2.4)
            x += rng.uniform(2.2, 3.0)
    return m, dict(W=12.0, D=3.0, solid=False)


def eimer(rng):
    """Two wooden buckets (one full of water) and a broom leaning beside them."""
    m = h.Model()
    for x, z, s in ((-3.2, 0.0, 1.0), (2.4, 1.4, 0.82)):
        for k in range(4):
            r = (2.1 + k * 0.22) * s
            m.ell(V(x, (0.7 + k * 1.15) * s, z), (r, 0.7 * s, r * 0.9), PLANK if k % 2 else PLANK_W)
        m.ell(V(x, 4.7 * s, z), (2.9 * s, 0.35, 2.6 * s), IRON)
        if s > 0.9:
            m.ell(V(x, 4.6 * s, z), (2.3 * s, 0.25, 2.0 * s), WATER)
        for k in range(7):                                       # the handle
            a = k / 6 * math.pi
            m.ell(V(x + math.cos(a) * 2.6 * s, 4.8 * s + math.sin(a) * 2.2 * s, z), (0.3, 0.3, 0.3), IRON)
    log(m, V(6.0, 0.6, -1.2), V(7.6, 17.0, -2.0), 0.45, BARK, step=0.8)
    for k in range(5):
        m.ell(V(5.7 + k * 0.25, 1.6, -1.0 + (k - 2) * 0.4), (0.6, 1.9, 0.5), STRAW)
    hut_lib.tuft(m, V(-5.5, 0.0, 1.6), rng, blades=4, height=2.2)
    return m, dict(W=6.5, D=3.0)


def toepfe(rng):
    """Clay pots of every size on a doorstep: flowers, herbs, a little shrub."""
    m = h.Model()
    for x, z, s in ((-4.8, 0.2, 1.0), (-0.8, -0.8, 1.3), (3.6, 0.4, 0.9), (1.2, 2.4, 0.7), (-3.2, 2.6, 0.75), (6.0, 2.0, 0.6)):
        for k in range(3):
            m.ell(V(x, (0.9 + k * 1.1) * s, z), ((1.6 + k * 0.3) * s, 0.75 * s, (1.5 + k * 0.28) * s), CLAY)
        m.ell(V(x, 3.6 * s, z), (2.5 * s, 0.4 * s, 2.3 * s), CLAY)
        m.ell(V(x, 3.8 * s, z), (2.1 * s, 0.3 * s, 1.9 * s), SOIL)
        q = rng.random()
        if q < 0.5:
            flowers(m, rng, x, 3.7 * s, z, 1.5 * s, 1.1 * s, n=5)
        elif q < 0.8:
            for k in range(4):
                a = rng.uniform(0, math.tau)
                m.ell(V(x + math.cos(a) * 1.0 * s, (4.6 + rng.uniform(0, 1.6)) * s, z + math.sin(a) * 0.8 * s), (1.4 * s, 1.2 * s, 1.2 * s),
                      (MOSS, MOSS_L)[k % 2])
        else:
            for k in range(5):
                p = V(x + rng.uniform(-1, 1) * s, 3.8 * s, z + rng.uniform(-0.6, 0.6))
                m.limb(p, p + V(rng.uniform(-0.8, 0.8), 4.0 * s, 0.0), 0.3, 0.2, MOSS_L)
    return m, dict(W=7.0, D=3.6, solid=False)


def regentonne(rng):
    """A rain barrel full to the brim, a tin scoop hanging on its rim, moss at its foot."""
    m = h.Model()
    barrel(m, 0.0, 0.0)
    m.ell(V(0.0, 13.75, 0.0), (3.3, 0.25, 3.0), WATER)
    log(m, V(3.6, 13.6, 0.8), V(5.0, 9.6, 1.2), 0.25, IRON, step=0.5)
    m.ell(V(5.1, 9.0, 1.2), (1.1, 0.9, 1.0), IRON)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        m.ell(V(math.cos(a) * 4.4, 0.5, math.sin(a) * 3.8), (1.5, 0.6, 1.0), MOSS)
    hut_lib.tuft(m, V(-4.0, 0.0, 2.6), rng, blades=5, height=3.0)
    return m, dict(W=5.0, D=4.4)


def amboss(rng):
    """A smith's anvil on a stump, the hammer lying on it, tongs leaning, a quench bucket beside."""
    m = h.Model()
    m.ell(V(0.0, 3.4, 0.0), (3.4, 3.4, 3.0), BARK)
    m.ell(V(0.0, 6.7, 0.0), (3.1, 0.3, 2.8), PLANK_W)
    m.ell(V(0.0, 7.6, 0.0), (1.6, 1.0, 1.4), IRON)                       # waist
    m.ell(V(0.0, 9.4, 0.0), (4.0, 1.2, 1.9), IRON)                       # face
    m.ell(V(4.8, 9.4, 0.0), (2.4, 0.8, 1.0), IRON)                       # horn
    m.ell(V(6.8, 9.5, 0.0), (1.0, 0.45, 0.5), IRON)
    log(m, V(-2.0, 10.8, 0.6), V(2.6, 10.9, 1.8), 0.35, PLANK, step=0.5)  # the hammer
    m.ell(V(-2.4, 10.9, 0.5), (1.0, 0.8, 0.8), IRON)
    log(m, V(-4.0, 0.4, 2.2), V(-3.4, 11.0, 0.4), 0.25, IRON, step=0.5)  # tongs
    log(m, V(-4.4, 0.4, 2.0), V(-3.0, 11.0, 0.2), 0.25, IRON, step=0.5)
    for k in range(4):
        r = 1.9 + k * 0.2
        m.ell(V(6.8, 0.7 + k * 1.1, 2.2), (r, 0.65, r * 0.9), PLANK if k % 2 else PLANK_W)
    m.ell(V(6.8, 4.3, 2.2), (2.2, 0.25, 2.0), WATER)
    for k in range(6):
        m.ell(V(rng.uniform(-5, 7), 0.3, rng.uniform(1.5, 4.0)), (0.5, 0.3, 0.4), BARK_D)   # scale and cinders
    return m, dict(W=7.5, D=3.6)


def schleifstein(rng):
    """A grindstone on a wooden frame with a crank and a trough of water under the wheel."""
    m = h.Model()
    for z in (-2.6, 2.6):
        log(m, V(-3.0, 0.0, z), V(0.0, 9.6, z), 0.55, BARK, step=0.8)
        log(m, V(3.0, 0.0, z), V(0.0, 9.6, z), 0.55, BARK, step=0.8)
    log(m, V(0.0, 9.0, -3.4), V(0.0, 9.0, 3.4), 0.35, IRON, step=0.5)
    m.ell(V(0.0, 9.0, 0.0), (5.0, 5.0, 1.3), STONE)                     # the wheel, standing in the x-y plane
    for k in range(20):
        a = k / 20 * math.tau
        m.ell(V(math.cos(a) * 4.7, 9.0 + math.sin(a) * 4.7, 0.2), (0.9, 0.9, 1.25), STONE_L if k % 3 else STONE)
    m.ell(V(0.0, 9.0, 1.4), (1.0, 1.0, 0.4), IRON)
    log(m, V(0.0, 9.0, 3.4), V(2.8, 11.4, 3.4), 0.3, IRON, step=0.5)       # the crank
    log(m, V(2.8, 11.4, 3.4), V(2.8, 11.4, 5.4), 0.3, PLANK, step=0.5)
    slab(m, V(-4.2, 2.6, 0.0), V(4.2, 2.6, 0.0), 3.4, 1.2, PLANK_W, (0, 0, 1), step=0.9)
    m.ell(V(0.0, 3.4, 0.0), (3.6, 0.25, 1.3), WATER)
    hut_lib.tuft(m, V(-4.2, 0.0, 2.4), rng, blades=4, height=2.4)
    return m, dict(W=5.5, D=3.6)


def anschlag(rng):
    """The town's notice board: two posts, a little slate roof, notices pinned on it, one with the red seal of the Vögtin."""
    m = h.Model()
    for x in (-7.0, 7.0):
        log(m, V(x, 0.0, 0.0), V(x, 20.0, 0.0), 0.7, BARK_D, step=0.9)
        m.ell(V(x, 0.6, 0.0), (1.6, 0.7, 1.4), STONE)
    slab(m, V(0.0, 18.0, 0.2), V(0.0, 7.6, 0.2), 13.6, 0.6, PLANK, (0, 0, 1), step=0.9)
    slab(m, V(-8.6, 20.6, -1.6), V(8.6, 20.6, -1.6), 2.2, 0.5, hut_lib.ROOF, (0, 0.7, 0.7), step=1.0)
    slab(m, V(-8.6, 20.0, 1.4), V(8.6, 20.0, 1.4), 2.4, 0.5, hut_lib.ROOF, (0, 0.8, 0.5), step=1.0)
    papers = [(-4.0, 15.0, 2.6, 2.8), (0.6, 14.4, 2.2, 3.2), (4.4, 15.6, 2.2, 2.0), (-2.4, 10.4, 3.0, 2.0), (3.6, 10.6, 2.0, 2.4)]
    for k, (x, y, w, hg) in enumerate(papers):
        slab(m, V(x, y + hg / 2, 0.75 + k * 0.03), V(x + rng.uniform(-0.3, 0.3), y - hg / 2, 0.75 + k * 0.03), w, 0.15,
             (LINEN, LINEN, hh.OCHRE)[k % 3], (0, 0, 1), step=0.6)
        m.ell(V(x, y + hg / 2 - 0.4, 1.0), (0.3, 0.3, 0.2), IRON)
    m.ell(V(0.6, 13.6, 1.05), (0.7, 0.7, 0.2), hh.WINE)
    hut_lib.tuft(m, V(-7.6, 0.0, 1.2), rng, blades=4, height=2.8)
    hut_lib.tuft(m, V(7.4, 0.0, 1.0), rng, blades=3, height=2.2)
    return m, dict(W=8.0, D=1.8)


def taubenschlag(rng):
    """A dovecote on a tall post: a little house with round holes, a slate hat, grey doves on its roof and perch."""
    m = h.Model()
    m.ell(V(0.0, 0.7, 0.0), (2.0, 0.8, 1.8), STONE)
    log(m, V(0.0, 0.4, 0.0), V(0.0, 22.0, 0.0), 0.7, BARK, step=0.9)
    for k in range(5):
        m.ell(V(0.0, 23.0 + k * 1.5, 0.0), (4.0, 0.8, 3.2), PLANK_W if k % 2 else PLANK)
    for x in (-1.8, 1.8):
        for y in (24.2, 27.0):
            m.ell(V(x, y, 3.2), (0.8, 0.8, 0.3), hut_lib.GAP)
    log(m, V(-4.4, 23.0, 3.4), V(4.4, 23.0, 3.4), 0.25, PLANK_W, step=0.5)
    for side in (-1, 1):
        slab(m, V(side * 2.6, 31.6, 0.0), V(side * 5.0, 29.2, 0.0), 4.2, 0.4, hut_lib.ROOF, (side * 0.7, 0.7, 0.0), step=0.8)
    m.ell(V(0.0, 32.2, 0.0), (0.6, 0.7, 0.6), IRON)
    for x, y, z in ((-2.6, 23.8, 3.6), (2.2, 31.0, 1.0), (-3.8, 30.0, -0.8)):  # the doves
        m.ell(V(x, y + 0.9, z), (1.2, 0.9, 0.8), STONE_L)
        m.ell(V(x + 0.9, y + 1.8, z), (0.55, 0.55, 0.5), STONE_L)
        m.ell(V(x - 1.0, y + 0.8, z), (0.7, 0.3, 0.4), STONE)
    hut_lib.tuft(m, V(-1.6, 0.0, 1.4), rng, blades=4, height=2.6)
    return m, dict(W=4.5, D=3.4)


def bienen(rng):
    """Three straw bee skeps on a plank bench, their dark entrances to the sun."""
    m = h.Model()
    for x in (-7.0, 7.0):
        m.ell(V(x, 1.4, 0.0), (1.8, 1.5, 1.6), STONE)
    slab(m, V(-9.0, 3.2, 0.0), V(9.0, 3.2, 0.0), 3.6, 0.6, PLANK, (0, 1, 0), step=1.0)
    for x in (-5.6, 0.0, 5.6):
        for k in range(5):
            r = 2.6 - k * 0.42
            m.ell(V(x, 4.2 + k * 1.15, 0.0), (r, 0.75, r * 0.9), STRAW)
        m.ell(V(x, 4.6, 2.2), (0.8, 0.5, 0.3), hut_lib.GAP)
    hut_lib.tuft(m, V(-8.0, 0.0, 1.6), rng, blades=5, height=3.0)
    flowers(m, rng, 2.0, 0.0, 3.0, 6.0, 0.8, n=6)
    return m, dict(W=9.5, D=3.0)


def vogelscheuche(rng):
    """A scarecrow in a wine-red coat with a straw hat, straw poking out of its sleeves."""
    m = h.Model()
    log(m, V(0.0, 0.0, 0.0), V(0.0, 19.0, 0.0), 0.5, BARK, step=0.8)
    log(m, V(-7.0, 14.6, 0.0), V(7.0, 14.0, 0.0), 0.45, BARK, step=0.8)
    m.ell(V(0.0, 12.6, 0.3), (3.2, 3.6, 1.6), hh.WINE)
    for side in (-1, 1):
        log(m, V(side * 2.0, 14.4, 0.4), V(side * 6.0, 14.2, 0.4), 1.0, hh.WINE, step=0.8)
        for k in range(3):
            m.ell(V(side * 7.0, 14.0 - k * 0.5, 0.4), (1.0, 0.4, 0.4), STRAW)
    for k in range(4):
        m.ell(V(-1.6 + k * 1.1, 8.6, 0.6), (0.4, 1.2, 0.4), STRAW)
    m.ell(V(0.0, 18.0, 0.2), (1.8, 1.9, 1.6), LINEN)
    m.ell(V(-0.6, 18.3, 1.7), (0.3, 0.3, 0.2), hut_lib.GAP)
    m.ell(V(0.7, 18.3, 1.7), (0.3, 0.3, 0.2), hut_lib.GAP)
    m.ell(V(0.0, 20.0, 0.2), (3.6, 0.4, 3.0), STRAW)
    m.ell(V(0.0, 21.0, 0.2), (1.8, 1.2, 1.5), STRAW)
    hut_lib.tuft(m, V(1.0, 0.0, 1.0), rng, blades=4, height=2.4)
    return m, dict(W=4.0, D=1.4)


def kraeuter(rng):
    """A drying rack: an A-frame with bundles of herbs and flowers hanging head down."""
    m = h.Model()
    for x in (-7.0, 7.0):
        log(m, V(x - 1.5, 0.0, -1.0), V(x, 12.0, 0.0), 0.45, BARK, step=0.8)
        log(m, V(x + 1.5, 0.0, 1.0), V(x, 12.0, 0.0), 0.45, BARK, step=0.8)
    log(m, V(-7.5, 11.8, 0.0), V(7.5, 11.8, 0.0), 0.4, BARK_D, step=0.7)
    for k in range(6):
        x = -5.4 + k * 2.15
        log(m, V(x, 11.6, 0.0), V(x, 10.4, 0.0), 0.12, LINEN, step=0.4)
        col = (MOSS_L, MOSS, hh.PLUM, MOSS_L, hh.OCHRE, MOSS)[k]
        for j in range(3):
            m.ell(V(x + (j - 1) * 0.35, 8.6 - j * 0.7, 0.2), (0.8, 1.8, 0.7), col)
    m.ell(V(0.0, 1.0, 1.0), (3.4, 1.4, 1.8), STRAW)                    # a basket of picked herbs
    flowers(m, rng, 0.0, 2.2, 1.0, 2.4, 1.2, n=5)
    return m, dict(W=8.0, D=2.0)


def heuraufe(rng):
    """A hay rack for the horses: a slatted V on four legs, stuffed with hay, wisps fallen round it."""
    m = h.Model()
    for x in (-8.0, 8.0):
        for z in (-2.0, 2.0):
            log(m, V(x, 0.0, z), V(x, 9.0, z * 1.4), 0.5, BARK, step=0.8)
    for z in (-1, 1):
        log(m, V(-8.6, 9.0, z * 3.0), V(8.6, 9.0, z * 3.0), 0.4, BARK_D, step=0.7)
        for k in range(9):
            x = -7.6 + k * 1.9
            log(m, V(x, 4.0, z * 0.6), V(x, 9.0, z * 3.0), 0.22, PLANK_W, step=0.5)
    for k in range(10):
        m.ell(V(-7.0 + k * 1.55, 8.4 + rng.uniform(-0.3, 0.8), rng.uniform(-1.2, 1.2)), (1.8, 1.4, 1.7), STRAW)
    for k in range(7):
        m.ell(V(rng.uniform(-9, 9), 0.25, rng.uniform(2.6, 4.4)), (1.4, 0.25, 0.7), STRAW)
    return m, dict(W=9.0, D=3.6)


def sattel(rng):
    """A saddle rack: a trestle with a leather saddle and a wine-red blanket, a bridle hanging off the end."""
    m = h.Model()
    for x in (-5.0, 5.0):
        log(m, V(x, 0.0, -1.8), V(x, 8.0, 0.0), 0.45, BARK, step=0.8)
        log(m, V(x, 0.0, 1.8), V(x, 8.0, 0.0), 0.45, BARK, step=0.8)
    log(m, V(-6.0, 8.0, 0.0), V(6.0, 8.0, 0.0), 0.6, BARK_D, step=0.8)
    slab(m, V(-3.4, 9.0, 0.0), V(-3.4, 4.6, 2.6), 4.2, 0.3, hh.WINE, (0, 0.4, 1), step=0.7)
    slab(m, V(-3.4, 9.0, 0.0), V(-3.4, 4.6, -2.6), 4.2, 0.3, hh.WINE, (0, 0.4, -1), step=0.7)
    m.ell(V(-3.4, 4.8, 2.7), (4.2, 0.35, 0.3), hh.OCHRE)
    m.ell(V(1.6, 9.6, 0.0), (3.6, 1.2, 2.4), BARK_D)                       # the saddle
    m.ell(V(4.2, 10.6, 0.0), (0.9, 1.4, 1.6), BARK_D)
    m.ell(V(-0.6, 10.4, 0.0), (0.8, 1.4, 1.4), BARK_D)
    log(m, V(1.8, 9.0, 2.2), V(1.8, 4.0, 2.6), 0.2, BARK_D, step=0.5)     # stirrup leather and iron
    m.ell(V(1.8, 3.6, 2.6), (0.9, 0.6, 0.3), IRON)
    log(m, V(6.0, 8.0, 0.0), V(6.6, 3.0, 0.6), 0.18, BARK_D, step=0.5)    # the bridle
    m.ell(V(6.6, 2.6, 0.6), (0.6, 0.6, 0.3), IRON)
    return m, dict(W=6.5, D=2.4)


def mist(rng):
    """The muck heap behind the stables: straw and dung piled up, a pitchfork stuck in it, a wheelbarrow tipped against it."""
    m = h.Model()
    for k in range(16):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random())
        x, z = math.cos(a) * 6.4 * d, math.sin(a) * 3.2 * d
        m.ell(V(x, 3.4 * (1.0 - d) + 1.0, z), (2.6, 1.6, 1.8), (SOIL, SOIL, STRAW, BARK_D)[k % 4])
    for k in range(8):
        m.ell(V(rng.uniform(-6, 6), rng.uniform(1.5, 4.8), rng.uniform(-2, 2.6)), (1.0, 0.3, 0.5), STRAW)
    log(m, V(1.6, 4.0, 0.6), V(3.4, 16.0, -1.0), 0.3, PLANK, step=0.6)  # the pitchfork
    for k in (-1, 0, 1):
        log(m, V(1.6 + k * 0.7, 4.6, 0.6), V(1.3 + k * 0.7, 2.0, 0.8), 0.15, IRON, step=0.4)
    slab(m, V(-9.6, 3.8, 1.6), V(-7.0, 1.0, 2.6), 4.2, 0.5, PLANK_W, (-0.5, 0.3, 1), step=0.8)   # the barrow
    for k in range(10):
        a = k / 10 * math.tau
        m.ell(V(-8.0, 1.6 + math.sin(a) * 1.5, 4.4 + math.cos(a) * 1.5), (0.4, 0.5, 0.5), PLANK_W)
    hut_lib.tuft(m, V(6.0, 0.0, 2.6), rng, blades=5, height=3.0)
    return m, dict(W=9.0, D=4.4)


def aufsitz(rng):
    """A mounting block: three worn stone steps, a tuft growing out of a joint."""
    m = h.Model()
    for k, (w, y) in enumerate(((4.6, 1.3), (3.6, 3.7), (2.4, 6.1))):
        m.ell(V(-k * 0.8, y, -k * 1.2), (w, 1.25, 3.0 - k * 0.5), (STONE, STONE_L, STONE_L)[k])
    m.ell(V(1.4, 2.6, 2.4), (2.2, 0.5, 0.6), MOSS)
    hut_lib.tuft(m, V(4.2, 0.0, 1.4), rng, blades=4, height=2.4)
    return m, dict(W=4.8, D=3.2)


def raeder(rng):
    """Two spare cart wheels leaning against each other, a loose spoke and a hub in the grass."""
    m = h.Model()
    for cx, lean, z in ((-4.6, 0.2, 0.0), (4.4, -0.25, 1.0)):
        R = hh.rot_z(lean)
        for k in range(14):
            a = k / 14 * math.tau
            m.ell(V(cx, 5.2, z) + R @ V(math.cos(a) * 4.8, math.sin(a) * 4.8, 0.0), (1.0, 1.0, 0.7), (PLANK_W, BARK)[k % 2])
            m.ell(V(cx, 5.2, z) + R @ V(math.cos(a) * 5.4, math.sin(a) * 5.4, 0.0), (0.7, 0.7, 0.5), IRON)
        for k in range(4):
            a = k / 4 * math.pi
            log(m, V(cx, 5.2, z) + R @ V(-math.cos(a) * 4.4, -math.sin(a) * 4.4, 0.0), V(cx, 5.2, z) + R @ V(math.cos(a) * 4.4, math.sin(a) * 4.4, 0.0),
                0.3, BARK, step=0.6)
        m.ell(V(cx, 5.2, z + 0.3), (1.0, 1.0, 0.6), IRON)
    log(m, V(-6.0, 0.4, 3.0), V(-2.0, 0.4, 3.6), 0.3, BARK, step=0.6)
    hut_lib.tuft(m, V(5.4, 0.0, 2.0), rng, blades=5, height=3.0)
    return m, dict(W=10.0, D=3.0)


def wagen(rng):
    """The big hay wagon of the stables: four spoked wheels, a slatted bed heaped with hay, the shafts resting on the ground."""
    m = h.Model()
    slab(m, V(-13.0, 7.6, 0.0), V(9.0, 7.6, 0.0), 8.0, 0.7, PLANK, (0, 1, 0), step=1.0)
    for z in (-4.2, 4.2):
        for y in (9.0, 11.6):
            log(m, V(-13.0, y, z), V(9.0, y, z), 0.35, PLANK_W, step=0.8)
        for x in (-12.0, -6.0, 0.0, 6.0):
            log(m, V(x, 7.6, z), V(x, 12.6, z), 0.3, BARK_D, step=0.6)
    for k in range(14):
        m.ell(V(-12.0 + k * 1.6, 13.4 + 1.6 * math.sin(k / 13 * math.pi), rng.uniform(-1.5, 1.5)), (2.6, 2.6, 4.2), STRAW)
    for x, z, rr in ((-9.0, 4.8, 4.2), (5.0, 4.8, 3.6), (-9.0, -4.8, 4.2), (5.0, -4.8, 3.6)):
        for k in range(14):
            a = k / 14 * math.tau
            m.ell(V(x + math.cos(a) * rr, rr + 0.4 + math.sin(a) * rr, z), (0.9, 0.9, 0.5), PLANK_W)
        for k in range(4):
            a = k / 4 * math.pi
            log(m, V(x - math.cos(a) * rr * 0.9, rr + 0.4 - math.sin(a) * rr * 0.9, z), V(x + math.cos(a) * rr * 0.9, rr + 0.4 + math.sin(a) * rr * 0.9, z),
                0.25, BARK, step=0.6)
        m.ell(V(x, rr + 0.4, z + (0.4 if z > 0 else -0.4)), (0.8, 0.8, 0.4), IRON)
    for z in (-2.0, 2.0):
        log(m, V(9.0, 6.0, z), V(19.0, 0.6, z * 1.5), 0.45, BARK, step=0.8)
    for k in range(5):
        m.ell(V(rng.uniform(-12, 8), 0.25, rng.uniform(5.5, 7.5)), (1.2, 0.25, 0.6), STRAW)
    return m, dict(W=15.0, D=7.0)


def pferdetrog(rng):
    """A long wooden water trough for the horses on two trestles, a pump at its end."""
    m = h.Model()
    for x in (-8.0, 8.0):
        log(m, V(x, 0.0, -1.6), V(x, 4.0, 0.0), 0.45, BARK, step=0.7)
        log(m, V(x, 0.0, 1.6), V(x, 4.0, 0.0), 0.45, BARK, step=0.7)
    for z in (-2.4, 2.4):
        slab(m, V(-10.0, 5.6, z), V(10.0, 5.6, z), 3.2, 0.5, PLANK if z > 0 else PLANK_W, (0, 0, 1 if z > 0 else -1), step=1.0)
    slab(m, V(-10.0, 4.2, 0.0), V(10.0, 4.2, 0.0), 5.0, 0.5, PLANK_W, (0, 1, 0), step=1.0)
    m.ell(V(0.0, 6.6, 0.0), (9.6, 0.3, 2.0), WATER)
    for x in (-10.0, 10.0):
        m.ell(V(x, 5.6, 0.0), (0.6, 1.8, 2.6), PLANK)
    log(m, V(12.6, 0.0, 0.0), V(12.6, 12.0, 0.0), 0.9, IRON, step=0.8)  # the pump
    log(m, V(12.6, 10.0, 0.0), V(10.4, 9.0, 0.0), 0.35, IRON, step=0.5)
    log(m, V(12.6, 12.0, 0.0), V(16.0, 14.0, 0.0), 0.3, IRON, step=0.5)
    m.ell(V(12.6, 12.6, 0.0), (1.2, 0.6, 1.2), IRON)
    for k in range(4):
        m.ell(V(rng.uniform(-9, 11), 0.3, rng.uniform(3.0, 4.6)), (1.4, 0.25, 0.8), WATER)
    return m, dict(W=13.0, D=3.4)


def muehle(rng):
    """The windmill of the fields: a round stone tower that tapers, a string course, a cart door, small windows (one lit), a slate cap
    and four lattice sails in an X, two of them clothed in linen, the other two bare; sacks of grain at its foot."""
    m = h.Model()
    top = 46.0

    def rad(y):
        return 12.5 - 4.0 * y / top
    for k in range(int(top / 1.8)):
        y = 1.0 + k * 1.8
        m.ell(V(0.0, y, 0.0), (rad(y), 1.1, rad(y)), STONE)
    for k in range(20):                                                # the foot: a ring of big stones
        a = k / 20 * math.tau
        m.ell(V(math.cos(a) * 13.0, 1.3, math.sin(a) * 13.0), (2.4, 1.4, 1.6), STONE_L, R=h.rot_y(-a))
    for y in (18.0, top - 1.0):
        m.ell(V(0.0, y, 0.0), (rad(y) + 0.6, 0.7, rad(y) + 0.6), STONE_L)
    m.ell(V(0.0, 7.0, rad(7.0) - 0.2), (3.4, 6.2, 0.9), PLANK)        # the cart door with its arch
    for k in range(9):
        a = math.pi * k / 8
        m.ell(V(math.cos(a) * 4.2, 12.4 + math.sin(a) * 3.2, rad(12.0) + 0.2), (1.1, 1.1, 0.7), STONE_L)
    log(m, V(0.0, 1.2, rad(7.0) + 0.6), V(0.0, 12.6, rad(7.0) + 0.6), 0.3, BARK_D, step=0.6)
    for x, y, lit in ((-4.0, 26.0, True), (3.6, 36.0, False)):
        r_ = rad(y)
        z = math.sqrt(max(0.0, r_ * r_ - x * x))
        m.ell(V(x, y, z), (1.5, 2.2, 0.7), hut_lib.GAP)
        if lit:
            m.ell(V(x, y, z + 0.3), (1.0, 1.6, 0.4), FIRE)
        m.ell(V(x, y - 2.4, z + 0.4), (1.9, 0.4, 0.6), STONE_L)
    for k in range(12):                                                # the cap
        y = top + k * 1.3
        r_ = (rad(top) + 1.6) * (1.0 - k / 12.0) + 0.5
        m.ell(V(0.0, y, -0.8), (r_, 0.9, r_), hut_lib.ROOF)
    m.ell(V(0.0, top + 16.0, -0.8), (0.7, 0.9, 0.7), IRON)
    hub = V(0.0, top + 3.0, rad(top) + 3.0)
    log(m, V(0.0, top + 3.0, -2.0), hub, 1.0, BARK_D, step=0.8)       # the wind shaft
    m.ell(hub, (1.8, 1.8, 1.4), BARK_D)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2 + 0.12
        d = V(math.cos(a), math.sin(a), 0.0)
        pp = V(-d[1], d[0], 0.0)
        tip = hub + d * 30.0
        log(m, hub, tip, 0.55, BARK, step=0.8)
        log(m, hub + d * 7.0 + pp * 5.0, tip + pp * 5.0, 0.25, PLANK_W, step=0.6)
        for j in range(8):
            q = hub + d * (8.0 + j * 3.0)
            log(m, q, q + pp * 5.0, 0.2, PLANK_W, step=0.5)
        if i % 2 == 0:
            slab(m, hub + d * 8.0 + pp * 2.5 + V(0, 0, 0.4), tip + pp * 2.5 + V(0, 0, 0.4), 4.6, 0.2, LINEN, (0, 0, 1), step=0.8)
    for x, z in ((6.0, 12.6), (8.6, 11.0), (-6.8, 12.4)):
        sack(m, x, z, rng, tall=0.8)
    hut_lib.tuft(m, V(-10.0, 0.0, 9.0), rng, blades=6, height=3.4)
    hut_lib.tuft(m, V(11.0, 0.0, 7.0), rng, blades=5, height=3.0)
    return m, dict(W=14.0, D=13.0, light=True)


def marktstand(rng, variant, yaw):
    """A market stall of the forum's kind (tools/art_hallgrat_houses.py `stand`), for the Steinmarkt; its middle moved to the deco box's."""
    m, info = hh.stand(rng, variant, yaw)
    shift = 2.5 if abs(yaw) < 1.0 else -2.5
    for p in m.prims:
        p.c = p.c + V(0.0, 0.0, shift)
    return m, dict(W=19.0, D=13.5)


TYPES = {
    "eimer": eimer, "toepfe": toepfe, "regentonne": regentonne, "amboss": amboss, "schleifstein": schleifstein, "anschlag": anschlag,
    "taubenschlag": taubenschlag, "bienen": bienen, "vogelscheuche": vogelscheuche, "kraeuter": kraeuter,
    "heuraufe": heuraufe, "sattel": sattel, "mist": mist, "aufsitz": aufsitz, "raeder": raeder, "wagen": wagen, "pferdetrog": pferdetrog,
    "markt_s0": lambda r: marktstand(r, 0, 0.0), "markt_s1": lambda r: marktstand(r, 1, 0.0), "markt_s2": lambda r: marktstand(r, 2, 0.0),
    "muehle": muehle,
    "markt_n0": lambda r: marktstand(r, 0, math.pi), "markt_n2": lambda r: marktstand(r, 2, math.pi),
    "waesche": waesche, "schild": schild, "koerbe": koerbe, "hackklotz": hackklotz, "fahne": fahne, "schrein": schrein, "quader": quader,
    "acker": acker,
    "fass": fass, "fass_lieg": fass_lieg, "kisten": kisten, "saecke": saecke, "kruege": kruege, "holz": holz, "heu": heu, "karren": karren,
    "trog": trog, "laterne": laterne, "kuebel": kuebel, "urne": urne, "beet": beet, "prellstein": prellstein, "steine": steine,
    "saeule": saeule, "brunnen": brunnen,
}
TURNED = {  # name: (model, the views it comes in)
    "bank": (bank, ("ew", "ns")),
    "zaun": (zaun, ("ew", "ns")),
}
# the yaw of a view: ew = along x; ns = turned a quarter; d = its line runs down to the right on the squashed ground ("\\", 45 degrees on screen)
YAW = {"ew": 0.0, "ns": math.pi / 2, "d": -math.atan(1.0 / h.SINP)}


# ------------------------------------------------------------------ rendering
def build(fn, seed, yaw=0.0):
    rng = rng_for(seed)
    m, info = fn(rng)
    W, D = info["W"], info["D"]
    Ry = h.rot_y(yaw)
    rel = [Ry @ V(x, 0.0, z) for x, z in ((-W, D), (W, D), (W, -D), (-W, -D))]
    zmax = max(q[2] for q in rel)
    zmin = min(q[2] for q in rel)
    xmax = max(abs(q[0]) for q in rel)
    hh.turn(m, yaw, shift=(0.0, -zmax))                               # the front edge on z = 0: the feet are the middle of the front
    for p in m.prims:
        p.c = p.c * G
        p.r = p.r * G
    k = S * G
    raw = to_array(hut_lib.render(m, CANVAS[0], CANVAS[1], CANVAS[2]))
    arr = hh.wall_pass(raw, seed)
    arr = hh.windows_glow(arr, seed)
    arr = hut_lib.grain(arr, seed, amount=0.5, mats=(PLANK, PLANK_W, BARK))
    ys, xs = np.nonzero(arr[..., 3] > 0)
    pad = 2
    x0, x1, y0 = int(xs.min()), int(xs.max()) + 1, int(ys.min())
    y1 = max(int(ys.max()) + 1, CANVAS[2] + 3)
    arr = arr[max(0, y0 - pad):y1, max(0, x0 - pad):x1 + pad]
    feet = (CANVAS[0] // 2 - max(0, x0 - pad), CANVAS[2] - max(0, y0 - pad))
    foot_w, foot_d = int(round(2 * xmax * k)), max(4, int(round((zmax - zmin) * h.SINP * k)))
    hut_lib.soft_shadow(arr, feet[0], feet[1] - foot_d / 2.0, foot_w / 2.0 + 2, foot_d / 2.0 + 2, alpha=60)
    glow = glow_of(arr, (FIRE, h.TEAL, h.CRYSTAL))
    for yy, xx in zip(*np.nonzero(arr[..., 3] > 0)):
        if tuple(int(c) for c in arr[yy, xx, :3]) in hh.GLASS_SET:
            glow[yy, xx] = arr[yy, xx]
    gy, gx = np.nonzero(glow[..., 3] > 0)
    out = {"size": [arr.shape[1], arr.shape[0]], "feet": list(feet), "foot": [foot_w, foot_d],
           "lights": [[int(gx.mean()), int(gy.mean())]] if info.get("light") and len(gx) else [], "deco": True}
    if not info.get("solid", True):
        out["solid"] = False
    if abs(math.sin(yaw * 2)) > 0.05:  # a turned footprint: the polygon for the collision
        out["poly"] = [[round(float(q[0]) * k, 1), round(float(q[2] - zmax) * h.SINP * k, 1)] for q in rel]
    return arr, glow, out


def main():
    data = json.loads(hh.DATA.read_text(encoding="utf-8"))
    data["types"] = {kk: v for kk, v in data["types"].items() if not kk.startswith("deko_")}
    shown = []
    jobs = [(n, fn, 0.0, "deko_" + n) for n, fn in TYPES.items()]
    for n, (fn, views) in TURNED.items():
        jobs += [(n, fn, YAW[v], "deko_%s_%s" % (n, v)) for v in views]
    for i, (n, fn, yaw, key) in enumerate(jobs):
        arr, glow, info = build(fn, 5200 + sum(ord(c) for c in n) * 7, yaw)
        save(hh.OUT / f"{key}.png", arr)
        save(hh.OUT / f"{key}_glow.png", glow)
        data["types"][key] = info
        shown.append(arr)
        print(key, info["size"], "foot", info["foot"])
    hh.DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image
        wsum = sum(a.shape[1] for a in shown) + 6 * len(shown)
        hmax = max(a.shape[0] for a in shown)
        comp = Image.new("RGBA", (wsum, hmax), (58, 110, 70, 255))
        x = 0
        for a in shown:
            comp.alpha_composite(Image.fromarray(a), (x, hmax - a.shape[0]))
            x += a.shape[1] + 6
        comp.resize((comp.width * 3, comp.height * 3), Image.NEAREST).save(png[0])


if __name__ == "__main__":
    main()
