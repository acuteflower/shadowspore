"""Props of the mine, zone 1 "Alte Stollen" (docs/mine.md): built from ellipsoids with the same renderer as the hut, the trees and the signpost
(hut_lib / art_hero3d), so they belong to the world: violet-plum timber, old stone, dull iron, a warm lantern light. Every builder returns (RGBA array,
feet row); the driver tools/art_mine_props.py writes them (+ `_glow` sheets with only the emissive pixels) and data/mine_props.json."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *

_B = len(h.RAMPS)
(ROPE, BRASS, RUST, COAL) = range(_B, _B + 4)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["2a2218", "4e4128", "7c6a42", "a8946a"],  # hemp rope
    ["3a2a14", "7a5a22", "c8943a", "f2d070"],  # brass of the lamps
    ["1c1014", "3a1e1c", "6a3426", "955a3c"],  # rust
    ["07050a", "120e18", "201a28", "342c3e"],  # coal, black stone
]]


def _shadowed(arr, ground, rx, ry, dx=0):
    return soft_shadow(arr, arr.shape[1] / 2 + dx, ground + 1, rx, ry)


def _damp(m, rng, n, xr, yr, z=3.0):
    """Moss and damp patches on timber."""
    for _ in range(n):
        m.ell((rng.uniform(*xr), rng.uniform(*yr), z), (rng.uniform(1.4, 3.0), 0.9, 1.0), MOSS_L if rng.random() < 0.5 else MOSS)


# ------------------------------------------------------------------ timber supports
def support_frame_arr(lamp=False):
    """A timber frame across a corridor (48 px): two posts on stone footings, a cross beam, two braces, wedges. You walk between the posts. `lamp`: a lantern hangs from the beam."""
    rng = rng_for(301)
    m = h.Model()
    for sx in (-20.0, 20.0):  # the posts stand inside the 48 px of floor, not in the rock
        m.ell((sx, 1.6, 0.0), (5.0, 2.2, 4.4), STONE if sx < 0 else STONE_L)
        log(m, V(sx, 2.0, 0.0), V(sx + 0.6 * np.sign(sx), 54, 0.0), 3.5, BARK if sx < 0 else BARK_D, step=1.1, rr=lambda t: 0.06 * math.sin(t * 9))
    log(m, V(-27, 52.5, 0.5), V(27, 52.5, 0.5), 3.4, BARK, step=1.1)
    for sx in (-1, 1):  # braces
        log(m, V(sx * 20, 38, 1.5), V(sx * 9, 52, 1.5), 1.8, PLANK_W, step=1.0)
        slab(m, V(sx * 24, 49, 3.0), V(sx * 24, 56, 3.0), 2.2, 0.8, IRON, (0, 0, 1))  # iron strap
    for k in range(3):  # wedges and a hanging root
        m.ell((-8 + k * 8, 56.5, 0.6), (2.4, 1.0, 2.0), PLANK)
    _damp(m, rng, 10, (-24, 24), (3, 50))
    if lamp:
        for k in range(3):
            m.ell((0, 50.6 - k * 1.8, 1.0), (0.5, 1.0, 0.4), IRON, R=h.rot_y(k * 1.57))
        m.ell((0, 44.4, 1.0), (3.0, 1.3, 3.0), BRASS)
        for k in range(4):
            a = k * 1.57 + 0.78
            log(m, V(math.cos(a) * 2.9, 44.0, 1.0 + math.sin(a) * 2.9), V(math.cos(a) * 2.9, 35.0, 1.0 + math.sin(a) * 2.9), 0.5, BRASS, step=0.9)
        m.ell((0, 34.4, 1.0), (3.2, 1.0, 3.2), BRASS)
        m.ell((0, 39.6, 1.0), (2.1, 3.4, 2.1), FIRE, kind="emit")
    arr = to_array(render(m, 78, 74, 64))
    return _shadowed(grain(arr, 302, amount=0.6), 64, 34, 3.5), 64


def post_arr():
    """A single support against the wall: a post, a short capping beam, an iron bracket."""
    rng = rng_for(303)
    m = h.Model()
    m.ell((0, 1.4, 0.0), (5.0, 2.2, 4.4), STONE)
    log(m, V(0, 2.0, 0.0), V(0.4, 46, 0.0), 3.5, BARK, step=1.1, rr=lambda t: 0.05 * math.sin(t * 8))
    log(m, V(-10, 44.5, 0.4), V(10, 44.5, 0.4), 3.0, BARK_D, step=1.1)
    slab(m, V(0, 40, 3.2), V(0, 47, 3.2), 2.4, 0.7, IRON, (0, 0, 1))
    m.limb(V(-6, 41, 1.5), V(0, 33, 1.5), 1.2, 1.0, PLANK_W)
    _damp(m, rng, 6, (-3, 3), (3, 40), 3.6)
    arr = to_array(render(m, 34, 62, 52))
    return _shadowed(grain(arr, 304, amount=0.6), 52, 12, 3), 52


# ------------------------------------------------------------------ lamps
def lamp_arr(lit=True):
    """A lantern on an iron bracket, hung on the wall face (feet = the foot of the wall): chain, brass cage, a warm flame. `lit` False: dead and dark."""
    m = h.Model()
    slab(m, V(0, 36, -0.6), V(0, 52, -0.6), 2.4, 0.7, IRON, (0, 0, 1))  # wall plate
    m.limb(V(0, 46, -0.2), V(6, 47, 3.0), 0.9, 0.8, IRON)  # arm
    for k in range(4):  # chain
        m.ell((6, 44.2 - k * 1.8, 3.4), (0.5, 1.0, 0.4), IRON, R=h.rot_y(k * 1.57))
    m.ell((6, 36.4, 3.4), (3.0, 1.3, 3.0), BRASS)
    for k in range(4):
        a = k * 1.57 + 0.78
        log(m, V(6 + math.cos(a) * 2.9, 36.0, 3.4 + math.sin(a) * 2.9), V(6 + math.cos(a) * 2.9, 27.0, 3.4 + math.sin(a) * 2.9), 0.5, BRASS, step=0.9)
    m.ell((6, 26.4, 3.4), (3.2, 1.0, 3.2), BRASS)
    if lit:
        m.ell((6, 31.6, 3.4), (2.1, 3.4, 2.1), FIRE, kind="emit")
    else:
        m.ell((6, 31.0, 3.4), (1.6, 2.0, 1.6), GAP)
        m.ell((7.5, 24.5, 3.6), (1.0, 2.0, 0.6), RUST)  # a broken pane's shard
    arr = to_array(render(m, 28, 64, 56))
    return grain(arr, 305, amount=0.3, mats=(IRON, BRASS)), 56


# ------------------------------------------------------------------ transport
def cart_arr(loaded):
    """A mine cart on four iron wheels: a tapering box of boards with iron bands; loaded with broken stone (or empty and dented)."""
    rng = rng_for(306 + int(loaded))
    m = h.Model()
    for sx in (-14, 14):
        for sz in (-8, 8):
            m.ell((sx, 4.2, sz), (4.4, 4.4, 1.3), IRON, R=h.rot_x(0.0))
            m.ell((sx, 4.2, sz * 1.04), (1.4, 1.4, 1.6), RUST)
    m.ell((0, 7.5, 0), (20, 1.4, 9.5), BARK_D)  # chassis
    for z, mat in ((-9.5, BARK), (9.5, PLANK_W)):  # long sides, leaning out
        for k in range(4):
            y = 9.0 + k * 3.4
            slab(m, V(-19 - k * 0.5, y, z * (1 + k * 0.03)), V(19 + k * 0.5, y, z * (1 + k * 0.03)), 1.9, 0.7, mat if k % 2 else BARK, (0, 0, np.sign(z)), step=1.3)
    for x in (-19.0, 19.0):  # short sides
        for k in range(4):
            slab(m, V(x, 9.0 + k * 3.4, -9), V(x, 9.0 + k * 3.4, 9), 1.9, 0.7, BARK if k % 2 else PLANK_W, (np.sign(x), 0, 0), step=1.3)
    for y in (10.5, 20.0):  # iron bands
        for z in (-10.6, 10.6):
            slab(m, V(-21, y, z), V(21, y, z), 0.9, 0.5, IRON, (0, 0, np.sign(z)), step=1.3)
    for sx in (-1, 1):
        m.limb(V(sx * 19, 10, 0), V(sx * 27, 8, 0), 0.9, 0.9, IRON)  # the coupling
    if loaded:
        for _ in range(26):
            x, z = rng.uniform(-16, 16), rng.uniform(-7, 7)
            m.ell((x, 20.5 + rng.uniform(0, 4.5) * (1 - (abs(x) / 18) ** 2), z), (rng.uniform(2.6, 4.6), rng.uniform(2.0, 3.2), rng.uniform(2.4, 4.0)), (STONE, STONE_L, COAL)[int(rng.integers(0, 3))], R=h.rot_y(rng.uniform(0, 3)))
        for _ in range(3):
            m.ell((rng.uniform(-9, 9), 25.5, rng.uniform(-3, 3)), (1.0, 1.0, 1.0), h.VIOLET, kind="emit")  # a vein-lit chunk
    else:
        m.ell((0, 20.5, 0), (17, 0.4, 7.5), GAP)
        _damp(m, rng, 8, (-16, 16), (9, 18), 10.2)
    arr = to_array(render(m, 76, 52, 40))
    return _shadowed(grain(arr, 308, amount=0.5), 40, 28, 5), 40


# ------------------------------------------------------------------ storage
def crates_arr():
    rng = rng_for(310)
    m = h.Model()

    def crate(c, w, hh, d, mat):
        for k in range(4):
            y = c[1] + 0.5 + k * hh / 4
            for sz in (-1, 1):
                slab(m, V(c[0] - w, y + hh / 8, c[2] + sz * d), V(c[0] + w, y + hh / 8, c[2] + sz * d), 1.0, hh / 8 - 0.35, mat if k % 2 else PLANK_W, (0, 0, sz), step=1.4)
        for sx in (-1, 1):
            for sz in (-1, 1):
                log(m, V(c[0] + sx * w, c[1], c[2] + sz * d), V(c[0] + sx * w, c[1] + hh, c[2] + sz * d), 1.4, BARK_D, step=1.2)
        slab(m, V(c[0] - w, c[1] + hh, c[2]), V(c[0] + w, c[1] + hh, c[2]), d, 0.9, mat, (0, 1, 0))

    crate(V(-10, 0, 0), 12, 17, 9, BARK)
    crate(V(14, 0, 3), 9, 12, 8, PLANK_W)
    crate(V(-6, 17.5, -1), 8, 10, 7, BARK_D)
    slab(m, V(-2, 13.5, 11.2), V(22, 13.5, 11.2), 3.5, 0.5, LINEN, (0, 0, 1))  # a tattered cloth over one
    _damp(m, rng, 12, (-22, 22), (1, 25), 9.5)
    arr = to_array(render(m, 62, 60, 52))
    return _shadowed(grain(arr, 311, amount=0.6), 52, 26, 4), 52


def barrel_arr():
    rng = rng_for(312)
    m = h.Model()
    for k in range(18):
        a = k / 18 * math.tau
        for s in range(14):
            t = s / 13
            y = 1.0 + t * 26
            rad = 10.0 + 2.4 * math.sin(t * math.pi)
            m.ell((math.cos(a) * rad, y, math.sin(a) * rad), (2.0, 2.2, 2.0), (BARK, PLANK_W, BARK_D)[k % 3], R=h.rot_y(-a))
    for y in (5.0, 22.0):
        for k in range(26):
            a = k / 26 * math.tau
            rad = 10.4 + 2.4 * math.sin((y - 1) / 26 * math.pi)
            m.ell((math.cos(a) * rad, y, math.sin(a) * rad), (1.0, 1.1, 1.0), IRON)
    m.ell((0, 27.0, 0), (10.0, 0.6, 10.0), PLANK_W)
    for k in range(20):
        a = k / 20 * math.tau
        m.ell((math.cos(a) * 11.0, 27.6, math.sin(a) * 11.0), (1.4, 0.8, 1.4), PLANK_W)
    _damp(m, rng, 8, (-10, 10), (1, 9), 11.5)
    arr = to_array(render(m, 34, 44, 36))
    return _shadowed(grain(arr, 313, amount=0.6), 36, 14, 3.5), 36


def sacks_arr():
    """Three sacks of grain or ore dust, tied at the neck, leaning on each other."""
    rng = rng_for(314)
    m = h.Model()
    for c, s, mat in (((-8, 0, 0), 1.0, LINEN), ((9, 0, 2), 0.9, STRAW), ((0, 11, -1), 0.85, LINEN)):
        x, y, z = c
        m.ell((x, y + 7 * s, z), (8.5 * s, 8 * s, 7 * s), mat)
        m.ell((x, y + 14 * s, z), (4.5 * s, 3.4 * s, 4 * s), mat)
        m.ell((x, y + 17.4 * s, z), (2.6 * s, 1.8 * s, 2.4 * s), mat)
        log(m, V(x - 3 * s, y + 15 * s, z + 0.3), V(x + 3 * s, y + 15 * s, z + 0.3), 0.7, ROPE, step=0.9)
    _damp(m, rng, 4, (-14, 14), (1, 8), 6)
    arr = to_array(render(m, 48, 50, 40))
    return _shadowed(grain(arr, 315, amount=0.5, mats=(LINEN, STRAW)), 40, 20, 3.5), 40


# ------------------------------------------------------------------ the way down and the way up
def stairs_down_arr():
    """The way down (floor level, 3 tiles wide), seen from higher up: a stone-framed pit whose steps fall away into the dark, a timber rail on both sides."""
    m = h.Model()
    m.ell((0, -16.0, -12.0), (20.5, 3.0, 12.0), GAP)  # the dark at the bottom
    shades = (STONE_L, STONE_L, STONE, STONE, IRON, IRON, COAL, GAP)
    for i in range(8):  # the treads, each lower and darker than the one in front of it
        m.ell((0, -i * 2.6, 15.0 - i * 3.9), (20.0 - i * 0.2, 1.3, 2.3), shades[i])
        m.ell((0, -i * 2.6 - 1.7, 15.0 - i * 3.9 - 1.5), (19.5, 1.2, 0.8), GAP if i > 3 else COAL)
    for sx in (-1, 1):  # stone lips round the pit and the timber rail
        m.ell((sx * 24.0, 0.8, 0.0), (3.8, 2.6, 22.0), STONE if sx < 0 else STONE_L)
        m.ell((sx * 22.0, -4.0, 0.0), (1.6, 4.0, 18.0), COAL)
        for z in (-15.0, 14.0):
            log(m, V(sx * 24.0, 1.5, z), V(sx * 24.0, 17, z), 1.5, BARK, step=1.0)
        log(m, V(sx * 24.0, 16.5, -16.0), V(sx * 24.0, 16.5, 15.0), 1.2, BARK_D, step=1.0)
    m.ell((0, 0.8, -19.0), (24, 2.6, 3.2), STONE)  # the back lip
    m.ell((0, 0.6, 20.5), (23, 1.7, 3.0), STONE_L)  # the front lip
    arr = to_array(render(m, 66, 62, 40, pitch=52.0))
    return grain(arr, 316, amount=0.4, mats=(STONE, STONE_L)), 40


def stairs_up_arr():
    """The way up (against the wall, 3 tiles wide): stone steps rising into the rock under a timber-framed arch, a faint daylight blue at the top."""
    rng = rng_for(317)
    m = h.Model()
    for i in range(6):
        m.ell((0, 1.8 + i * 3.1, -1.0 - i * 3.4), (19 - i * 0.4, 1.7, 3.4), (STONE_L, STONE, STONE_L, STONE, STONE, STONE)[i])
    m.ell((0, 28, -24), (19, 21, 1.2), GAP)
    m.ell((0, 36, -22.5), (7.4, 11, 0.6), SKY, kind="emit")  # the light far above
    for sx in (-1, 1):
        log(m, V(sx * 22.0, 0, 1.0), V(sx * 22.0, 50, 1.0), 3.6, BARK, step=1.1)
        m.ell((sx * 22, 1.5, 1.0), (5.4, 2.2, 4.8), STONE)
    log(m, V(-26, 50.5, 1.5), V(26, 50.5, 1.5), 3.6, BARK_D, step=1.1)
    for sx in (-1, 1):
        log(m, V(sx * 22, 38, 2.5), V(sx * 13, 50, 2.5), 1.6, PLANK_W, step=1.0)
    for _ in range(14):
        m.ell((rng.uniform(-26, 26), rng.uniform(51, 58), rng.uniform(-2, 2)), (rng.uniform(3, 6), rng.uniform(3, 5), 3), STONE if rng.random() < 0.6 else STONE_L)
    _damp(m, rng, 8, (-25, 25), (3, 48), 4.5)
    arr = to_array(render(m, 70, 80, 70))
    return _shadowed(grain(arr, 318, amount=0.5), 70, 28, 3.5), 70


def winch_arr():
    """The lift station: a timber head frame with a rope drum and pulleys, a plank cage hanging at the bottom with an open gate, a lantern, a crank."""
    rng = rng_for(319)
    m = h.Model()
    for sx in (-30.0, 30.0):  # A-frame legs
        log(m, V(sx, 2.0, 7.0), V(sx * 0.45, 78, 0.0), 3.4, BARK, step=1.2)
        log(m, V(sx, 2.0, -7.0), V(sx * 0.45, 78, 0.0), 3.4, BARK_D, step=1.2)
        m.ell((sx, 1.6, 7.0), (5.0, 2.2, 4.4), STONE)
        m.ell((sx, 1.6, -7.0), (5.0, 2.2, 4.4), STONE_L)
    log(m, V(-14, 78, 0), V(14, 78, 0), 3.0, BARK, step=1.1)
    for y, hw in ((24, 24.0), (46, 17.0)):
        log(m, V(-hw, y, 0.5), V(hw, y, 0.5), 1.8, PLANK_W, step=1.0)
    log(m, V(-9, 61, 0.5), V(9, 61, 0.5), 5.0, BARK_D, step=0.9)  # the drum
    for k in range(5):
        m.ell((-8 + k * 4, 61, 0.5), (1.4, 5.3, 5.3), ROPE)
    log(m, V(0, 61, 0.5), V(0, 24, 0.5), 0.7, ROPE, step=0.9)  # the rope down to the cage
    m.ell((0, 77.5, 2.0), (2.2, 2.2, 1.0), IRON)
    m.ell((19, 61, 0.5), (1.6, 6.0, 1.6), IRON, R=h.rot_x(0.5))  # crank
    for z, mat in ((-8, PLANK_W), (8, BARK)):  # the cage: floor, rails, bars
        slab(m, V(-17, 2.5, z), V(17, 2.5, z), 1.8, 0.7, mat, (0, 1, 0))
    m.ell((0, 1.8, 0), (17.5, 1.0, 9.5), BARK_D)
    for sx in (-17.0, 17.0):
        for z in (-8.0, 8.0):
            log(m, V(sx, 2.5, z), V(sx, 22, z), 1.0, IRON, step=1.0)
    for z in (-8.0, 8.0):
        log(m, V(-17, 22, z), V(17, 22, z), 1.1, IRON, step=1.0)
    for k in range(5):  # a bar of the gate
        log(m, V(-12 + k * 6, 4, 8), V(-12 + k * 6, 20, 8), 0.5, IRON, step=1.0)
    m.ell((-24, 36, 6), (3.0, 1.2, 3.0), BRASS)
    m.ell((-24, 33, 6), (1.8, 2.8, 1.8), FIRE, kind="emit")  # a lantern on the frame
    for sx in (-1, 1):
        m.ell((sx * 21, 30, 4), (0.8, 0.8, 0.8), h.VIOLET, kind="emit")
    _damp(m, rng, 14, (-30, 30), (3, 40), 8.0)
    arr = to_array(render(m, 96, 112, 100))
    return _shadowed(grain(arr, 320, amount=0.6), 100, 40, 4), 100


# ------------------------------------------------------------------ the entrance in the world
def entrance_arr():
    """The old mine's mouth in a rock face, seen from outside: boulders of the world's stone piled into a low cliff, a timber portal (two posts, two lintels, braces),
    the dark behind it with rails running out on sleepers, two lanterns, a plank sign, moss and ivy, violet veins in the cracks, teal fungi at the foot."""
    rng = rng_for(330)
    m = h.Model()
    hw, top = 25.0, 60.0  # the opening: half width, height

    def in_opening(x, y, r):
        return abs(x) < hw + 7 + r * 0.5 and y < top + 6 + r * 0.4

    m.ell((0, 26, -6.0), (hw + 2, 30, 0.8), GAP)  # the dark inside
    for _ in range(420):  # the cliff: boulders, dense at the foot, thinning to the top
        y = abs(rng.normal(0, 1)) * 42.0
        x = rng.uniform(-1, 1) * (96 - y * 0.5)
        r = rng.uniform(7, 13) * (1.0 - y / 190.0)
        if y > 96 or in_opening(x, y, r):
            continue
        z = rng.uniform(-3.0, 3.0) - y * 0.04
        m.ell((x, y + r * 0.4, z), (r * 1.25, r, r * 0.9), (STONE, STONE_L, STONE, COAL)[int(rng.integers(0, 4))], R=h.rot_y(rng.uniform(0, 3.1)))
    for sx in (-1, 1):  # the portal
        log(m, V(sx * (hw + 1.5), 0, 6.5), V(sx * (hw + 2.2), top - 1, 6.5), 4.6, BARK, step=1.2, rr=lambda t: 0.05 * math.sin(t * 7))
        m.ell((sx * (hw + 1.5), 1.6, 6.5), (7.0, 2.6, 6.0), STONE)
        log(m, V(sx * (hw + 1.0), 40, 8.4), V(sx * (hw - 11), top, 8.4), 1.9, PLANK_W, step=1.0)  # braces
    log(m, V(-hw - 10, top, 7.0), V(hw + 10, top, 7.0), 4.4, BARK_D, step=1.2)
    log(m, V(-hw - 6, top + 8.5, 6.0), V(hw + 6, top + 8.5, 6.0), 3.6, BARK, step=1.2)
    for k in range(5):  # planking between the lintels
        m.ell((-hw + 3 + k * 11.5, top + 4.0, 5.5), (5.6, 3.0, 1.2), PLANK if k % 2 else PLANK_W)
    for k in range(9):  # sleepers and two rails running out of the dark
        z = -2 + k * 6.4
        slab(m, V(-17, 1.0, z), V(17, 1.0, z), 1.6, 0.8, BARK_D, (0, 1, 0), step=1.4)
    for sx in (-10.0, 10.0):
        log(m, V(sx, 2.2, -2), V(sx, 2.2, 54), 0.9, IRON, step=1.2)
    for sx in (-1, 1):  # lanterns on the posts
        x = sx * (hw + 9.5)
        m.limb(V(sx * (hw + 3.5), 46, 8.4), V(x, 46, 11.0), 0.8, 0.8, IRON)
        m.ell((x, 41.0, 11.0), (2.8, 1.1, 2.8), BRASS)
        m.ell((x, 37.0, 11.0), (2.1, 3.0, 2.1), FIRE, kind="emit")
        m.ell((x, 33.0, 11.0), (2.9, 1.0, 2.9), BRASS)
    slab(m, V(-hw - 9, 28, 9.8), V(-hw - 9, 40, 9.8), 5.0, 0.7, PLANK_W, (0, 0, 1))  # the sign
    for k in range(2):
        m.ell((-hw - 11 + k * 4.4, 36, 10.7), (0.9, 1.4, 0.3), GAP)
    m.ell((-hw - 9, 31, 10.7), (2.4, 0.6, 0.3), GAP)
    for _ in range(46):  # moss on the rock and timber, violet veins, teal fungi
        x = rng.uniform(-80, 80)
        y = rng.uniform(2, 70)
        if not in_opening(x, y, 4):
            m.ell((x, y, 8.5), (rng.uniform(1.6, 4.2), 1.0, 1.2), MOSS_L if rng.random() < 0.5 else MOSS)
    for _ in range(7):
        x = rng.uniform(-70, 70)
        y = rng.uniform(8, 60)
        if not in_opening(x, y, 5):
            m.ell((x, y, 9.0), (0.7, rng.uniform(2, 5), 0.5), h.VIOLET, kind="emit", R=h.rot_z(rng.uniform(-0.8, 0.8)) if hasattr(h, "rot_z") else None)
    for _ in range(8):
        x = rng.choice([-1, 1]) * rng.uniform(34, 70)
        m.ell((x, rng.uniform(2.5, 5), 9.5), (rng.uniform(1.4, 2.4), 1.1, 1.4), h.TEAL, kind="emit")
    ivy(m, V(-hw - 8, top + 6, 8.5), 22, rng, glow_every=4)
    ivy(m, V(hw + 12, top + 6, 8.5), 14, rng)
    arr = to_array(render(m, 216, 176, 156))
    return _shadowed(grain(arr, 331, amount=0.55), 156, 84, 6), 156


# ------------------------------------------------------------------ rooms: dwellings, remains, nests, wet caves
import hut_props  # noqa: E402

BONE = len(h.RAMPS)
h.RAMPS += [[hexc(c) for c in ["2a2430", "6a6270", "a89ea0", "dcd2c4"]]]


def bunk_arr():
    """A two-storey bunk of rough timber: straw mattresses, a dingy blanket, a rope ladder at the end."""
    rng = rng_for(340)
    m = h.Model()
    for sx in (-21.0, 21.0):
        for sz in (-8.5, 8.5):
            log(m, V(sx, 1.0, sz), V(sx, 50, sz), 1.7, BARK if sx < 0 else BARK_D, step=1.1)
    for y in (13.0, 33.0):
        for k in range(5):  # boards
            slab(m, V(-22, y, -7 + k * 3.5), V(22, y, -7 + k * 3.5), 1.7, 0.8, PLANK_W if k % 2 else PLANK, (0, 1, 0), step=1.3)
        m.ell((0, y + 2.4, 0), (19.5, 2.4, 8.2), STRAW)
        for _ in range(8):
            a = V(rng.uniform(-18, 18), y + 4.0, rng.uniform(-7, 7))
            m.limb(a, a + V(rng.uniform(-3, 3), 0.6, rng.uniform(-2, 2)), 0.2, 0.14, STRAW)
    m.ell((-10, 38.5, 1.0), (7.5, 3.0, 6.5), WOOL)  # a heap of blanket on the top bunk
    m.ell((12, 18.0, 0.0), (9.0, 2.4, 7.0), WOOL)
    m.ell((-15, 16.5, 0.0), (4.5, 2.0, 4.0), LINEN)  # a pillow
    for k in range(5):  # a short ladder
        m.limb(V(26, 2 + k * 8, 9.0), V(26, 4 + k * 8, 9.0), 0.2, 0.2, ROPE)
    log(m, V(24.5, 2, 9.5), V(24.5, 38, 9.5), 0.6, ROPE, step=1.0)
    log(m, V(27.5, 2, 9.5), V(27.5, 38, 9.5), 0.6, ROPE, step=1.0)
    for k in range(5):
        log(m, V(24.5, 4 + k * 8, 9.5), V(27.5, 4 + k * 8, 9.5), 0.5, BARK, step=0.9)
    _damp(m, rng, 8, (-20, 20), (3, 45), 9.5)
    arr = to_array(render(m, 70, 70, 60))
    return _shadowed(grain(arr, 341, amount=0.6), 60, 30, 4), 60


def bones_arr():
    """What is left of a miner: skull, ribs, long bones, a dented helmet, a pickaxe, a rag of cloth."""
    rng = rng_for(342)
    m = h.Model()
    m.ell((-14, 2.6, 0), (3.4, 2.8, 3.0), BONE)  # skull
    m.ell((-15.5, 1.8, 1.8), (1.2, 0.9, 0.6), GAP)
    m.ell((-12.5, 1.8, 2.0), (1.2, 0.9, 0.6), GAP)
    m.ell((-14, 0.9, 0.6), (2.0, 0.9, 2.0), BONE)
    for k in range(5):  # ribs
        m.ell((-6 + k * 2.4, 2.4, 0), (1.0, 2.2, 4.6 - abs(k - 2) * 0.6), BONE, R=h.rot_y(0.0))
    log(m, V(-9, 1.2, 0), V(9, 1.0, 0), 0.7, BONE, step=0.9)  # the spine
    log(m, V(8, 1.2, 3), V(20, 0.9, 6), 0.8, BONE, step=0.9)  # the legs
    log(m, V(8, 1.2, -3), V(18, 0.9, -7), 0.8, BONE, step=0.9)
    log(m, V(-8, 1.0, 4), V(-2, 0.8, 11), 0.7, BONE, step=0.9)  # an arm
    m.ell((-20, 3.0, 5), (4.4, 2.6, 4.0), IRON)  # the helmet
    m.ell((-20, 1.6, 5), (4.8, 0.8, 4.4), RUST)
    log(m, V(0, 1.0, 12), V(16, 1.4, 14), 0.8, BARK, step=1.0)  # a pickaxe
    m.ell((0.6, 1.6, 12), (4.0, 1.4, 1.0), IRON)
    m.ell((12, 1.0, -4), (7.0, 0.7, 3.4), LINEN)
    arr = to_array(render(m, 60, 34, 22))
    return _shadowed(grain(arr, 343, amount=0.4, mats=(BONE, BARK)), 22, 26, 4), 22


def notes_arr():
    """A journal lying open, a tin cup and a candle stub beside it."""
    m = h.Model()
    m.ell((0, 1.2, 0), (6.4, 1.2, 4.6), h.LEATHER)
    m.ell((-2.7, 2.4, 0), (3.0, 0.6, 3.8), LINEN)
    m.ell((2.7, 2.4, 0), (3.0, 0.6, 3.8), STRAW)
    for k in range(4):
        m.ell((-3.4 + k * 1.1, 2.9, -1.4 + k * 0.4), (1.1, 0.15, 0.2), GAP)
    log(m, V(9, 0.6, 1.0), V(9, 4.4, 1.0), 2.0, IRON, step=0.8)
    log(m, V(-9, 0.6, 0.0), V(-9, 4.0, 0.0), 1.1, WAX, step=0.8)
    m.ell((-9, 5.0, 0.0), (0.5, 0.9, 0.5), FIRE, kind="emit")
    arr = to_array(render(m, 34, 22, 14))
    return _shadowed(arr, 14, 11, 2), 14


def nest_arr():
    """A lair of shadow spiders: a pool of tar, strands of web between stumps, egg sacs with magenta veins."""
    rng = rng_for(344)
    m = h.Model()
    m.ell((0, 0.6, 0), (24, 1.2, 14), COAL)
    for _ in range(5):
        m.ell((rng.uniform(-18, 18), 1.0, rng.uniform(-9, 9)), (rng.uniform(3, 7), 0.9, rng.uniform(2, 5)), GAP)
    for k, (x, z) in enumerate(((-12, 2), (-3, -4), (7, 3), (14, -3), (2, 7))):
        r = rng.uniform(3.6, 5.6)
        m.ell((x, r * 0.95, z), (r, r * 1.15, r), COAL)
        for v in range(4):
            a = rng.uniform(0, math.tau)
            m.ell((x + math.cos(a) * r * 0.82, r * (0.7 + 0.3 * rng.random()), z + math.sin(a) * r * 0.82 + 0.8), (0.5, rng.uniform(1.2, 2.2), 0.5), h.VIOLET, kind="emit")
    for _ in range(14):  # strands of web
        a = V(rng.uniform(-18, 18), rng.uniform(5, 16), rng.uniform(-8, 8))
        b = V(rng.uniform(-18, 18), rng.uniform(5, 16), rng.uniform(-8, 8))
        m.limb(a, b, 0.25, 0.25, LINEN)
    arr = to_array(render(m, 70, 50, 36))
    return arr, 36


def puddle_arr(w, hh, seed):
    """Still water on the floor (flat, 2D): dark blue, a pale rim, a few reflected points of light."""
    rng = np.random.default_rng(seed)
    arr = np.zeros((hh, w, 4), np.uint8)
    cx, cy = (w - 1) / 2, (hh - 1) / 2
    for y in range(hh):
        for x in range(w):
            d = ((x - cx) / (w / 2)) ** 2 + ((y - cy) / (hh / 2)) ** 2 + 0.22 * (rng.random() - 0.5)
            if d < 0.78:
                t = d / 0.78
                base = np.array([22, 36, 62]) * (1 - 0.3 * (1 - t)) + np.array([38, 62, 98]) * (t * 0.5)
                arr[y, x] = (*base.astype(int), 215)
            elif d < 1.0:
                arr[y, x] = (96, 122, 150, 150)
    for _ in range(max(2, w // 10)):
        x, y = int(rng.integers(3, w - 3)), int(rng.integers(2, hh - 2))
        if arr[y, x, 3] > 200:
            arr[y, x] = (150, 190, 230, 230)
            if x + 1 < w and arr[y, x + 1, 3] > 200:
                arr[y, x + 1] = (110, 150, 200, 230)
    return arr, hh // 2


def stalagmites_arr():
    rng = rng_for(345)
    m = h.Model()
    for x, hgt, r in ((-9, 26, 4.4), (4, 34, 5.0), (13, 18, 3.4), (-1, 14, 3.0)):
        z = rng.uniform(-3, 3)
        log(m, V(x, 0.5, z), V(x + rng.uniform(-1, 1), hgt, z), r, STONE if x < 4 else STONE_L, step=1.0, taper=0.12)
    for _ in range(6):
        m.ell((rng.uniform(-14, 16), 0.9, rng.uniform(-6, 6)), (rng.uniform(2, 3.4), 1.2, rng.uniform(1.6, 2.6)), STONE)
    arr = to_array(render(m, 48, 52, 42))
    return _shadowed(grain(arr, 346, amount=0.4, mats=(STONE, STONE_L)), 42, 18, 3), 42


def waysign_arr():
    """A post with two planks nailed on, pointing opposite ways, the marks of the shifts cut into them."""
    rng = rng_for(347)
    m = h.Model()
    m.ell((0, 1.4, 0), (5.0, 2.0, 4.4), STONE)
    log(m, V(0, 2, 0), V(0.3, 50, 0), 2.3, BARK, step=1.1)
    slab(m, V(-15, 42, 2.8), V(11, 44, 2.8), 4.0, 0.8, PLANK_W, (0, 0, 1))
    m.ell((-16.5, 42.4, 2.8), (3.0, 3.6, 0.8), PLANK_W, R=h.rot_z(0.8) if hasattr(h, "rot_z") else None)
    slab(m, V(-11, 30, 3.0), V(15, 29, 3.0), 4.0, 0.8, PLANK, (0, 0, 1))
    m.ell((16.5, 29.0, 3.0), (3.0, 3.6, 0.8), PLANK, R=h.rot_z(0.8) if hasattr(h, "rot_z") else None)
    for k in range(3):
        m.ell((-7 + k * 4, 43.0, 3.7), (0.7, 2.0, 0.3), GAP)
        m.ell((-3 + k * 4, 29.6, 3.9), (0.7, 2.0, 0.3), GAP)
    m.ell((0, 18, 2.8), (1.0, 1.0, 1.0), h.TEAL, kind="emit")
    _damp(m, rng, 5, (-2, 2), (4, 40), 2.6)
    arr = to_array(render(m, 46, 66, 56))
    return _shadowed(grain(arr, 348, amount=0.6), 56, 12, 3), 56


def web_arr():
    """A corner of cobweb (flat, 2D, pale and half see-through): strands from the corner and sagging arcs between them."""
    arr = np.zeros((22, 22, 4), np.uint8)
    for ang in (0.05, 0.38, 0.72, 1.05, 1.5):
        for r in range(0, 22):
            x, y = int(r * math.cos(ang)), int(r * math.sin(ang))
            if x < 22 and y < 22:
                arr[y, x] = (205, 205, 228, 170)
    for r in (6, 11, 16):
        for k in range(30):
            a = 0.05 + k / 29 * 1.45
            x, y = int(r * math.cos(a) * (1 - 0.1 * math.sin(a * 7))), int(r * math.sin(a))
            if 0 <= x < 22 and 0 <= y < 22:
                arr[y, x] = (190, 190, 214, 130)
    return arr, 0


def treasure_chest_arr():
    return hut_props.chest_arr()


def table_stool():
    return hut_props.table_arr()


def stool_arr():
    return hut_props.stool_arr(0)


def shelf_arr():
    return hut_props.shelf_arr()


def pots_arr():
    return hut_props.pots_arr()
