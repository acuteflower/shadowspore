"""Small things that make the mine look lived in and fallen apart (docs/mine.md section 7): heaps of rubble, broken planks, glowing mushrooms, a dropped lantern, tools,
a coil of rope, a bucket, a ladder and a chain on the wall. Same renderer and palettes as mine_props.py; every builder returns (RGBA array, feet row)."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *
from mine_props import COAL, ROPE, BRASS, RUST, _shadowed


def _rubble(name, feet):
    """The rubble of the mine's own rocks (tools/art_mine_rocks.py writes the pictures)."""
    from PIL import Image
    arr = np.array(Image.open(ROOT / "mine" / "props" / f"rubble_{name}.png").convert("RGBA"))
    return arr, feet


def rubble_a_arr():
    return _rubble("a", 8)


def rubble_b_arr():
    return _rubble("b", 9)


def rubble_c_arr():
    return _rubble("c", 8)


def planks_arr():
    """Broken boards and a splintered post lying in a heap."""
    rng = rng_for(514)
    m = h.Model()
    for k in range(5):
        a = V(rng.uniform(-12, -3), 1.0 + k * 1.6, rng.uniform(-4, 4))
        b = V(rng.uniform(3, 14), 1.0 + k * 1.2 + rng.uniform(-0.5, 2.5), rng.uniform(-4, 4))
        slab(m, a, b, 1.8, 0.7, PLANK if k % 2 else PLANK_W)
    log(m, V(-9, 1.6, 3.0), V(10, 4.5, 2.0), 1.7, BARK_D, step=1.0)
    for _ in range(4):
        m.ell((rng.uniform(-12, 12), 0.8, rng.uniform(-5, 5)), (rng.uniform(1.2, 2.2), 0.6, 0.7), BARK)
    arr = to_array(render(m, 38, 22, 15))
    return _shadowed(grain(arr, 515, amount=0.5, mats=(PLANK, PLANK_W, BARK_D, BARK)), 15, 14, 3), 15


def mushrooms_arr():
    """Glow caps in the damp: pale stems, caps that light themselves."""
    rng = rng_for(516)
    m = h.Model()
    m.ell((0, 0.6, 0), (12, 1.2, 6), MOSS)
    for x, z, hgt, r in ((-7, 1, 9, 3.6), (0, -2, 14, 4.8), (7, 2, 7, 3.0), (3, 4, 5, 2.4), (-3, 4, 4, 2.0)):
        log(m, V(x, 0.8, z), V(x + rng.uniform(-1, 1), hgt, z), 1.0, LINEN, step=1.0, taper=0.8)
        m.ell((x, hgt + 0.6, z), (r, r * 0.55, r), h.TEAL, kind="emit")
        m.ell((x, hgt + 1.8, z), (r * 0.5, r * 0.22, r * 0.5), h.CRYSTAL, kind="emit")
    arr = to_array(render(m, 34, 30, 24))
    return _shadowed(arr, 24, 11, 2.4), 24


def lantern_arr():
    """A lantern dropped on the floor, still burning."""
    m = h.Model()
    m.ell((0, 0.8, 0), (4.6, 1.2, 3.4), IRON)
    m.ell((0, 4.4, 0), (3.6, 3.6, 2.8), BRASS)
    m.ell((0, 4.6, 1.6), (2.0, 2.4, 0.6), FIRE, kind="emit")
    m.ell((0, 8.4, 0), (3.0, 0.9, 2.4), IRON)
    log(m, V(-2.6, 8.8, 0), V(2.6, 11.5, 0), 0.5, IRON, step=0.8)
    arr = to_array(render(m, 16, 18, 14))
    return _shadowed(arr, 14, 6, 1.6), 14


def pickaxe_arr():
    """A pickaxe on the floor, its haft grey with use."""
    m = h.Model()
    log(m, V(-12, 1.0, 0), V(11, 1.4, 1.5), 1.1, PLANK_W, step=0.9)
    m.ell((-12.6, 1.8, 0), (0.7, 3.4, 1.0), IRON)
    m.ell((-11.4, 1.6, 0), (1.4, 1.4, 4.4), IRON)
    m.ell((-11.4, 1.6, -4.8), (0.7, 0.8, 0.9), STONE_L)
    arr = to_array(render(m, 34, 12, 9))
    return _shadowed(arr, 9, 11, 1.8), 9


def bucket_arr():
    m = h.Model()
    m.ell((0, 4.0, 0), (4.6, 4.2, 4.2), PLANK_W)
    m.ell((0, 7.4, 0), (4.0, 0.8, 3.6), GAP)
    m.ell((0, 5.0, 0), (4.9, 0.7, 4.5), IRON)
    m.ell((0, 2.4, 0), (4.7, 0.7, 4.3), IRON)
    log(m, V(-4.2, 8.2, 0), V(4.2, 8.2, 0), 0.4, IRON, step=0.7)
    arr = to_array(render(m, 18, 18, 14))
    return _shadowed(grain(arr, 517, amount=0.4, mats=(PLANK_W,)), 14, 6, 1.6), 14


def rope_arr():
    m = h.Model()
    for k in range(5):
        r = 5.6 - k * 0.5
        m.ell((0, 1.0 + k * 0.9, 0), (r, 0.9, r * 0.78), ROPE)
    m.ell((0, 5.5, 0), (2.4, 0.7, 1.8), ROPE)
    arr = to_array(render(m, 20, 14, 10))
    return _shadowed(arr, 10, 7, 1.8), 10


def ladder_arr():
    """A timber ladder leaning on the wall: two rails and rungs, seen from the front."""
    m = h.Model()
    for sx in (-1, 1):
        log(m, V(sx * 5.0, 0.8, 1.0), V(sx * 4.4, 36.0, -2.0), 1.3, BARK, step=1.0, taper=0.9)
    for k in range(8):
        y = 4.0 + k * 4.4
        log(m, V(-5.0, y, 0.6 - k * 0.07), V(5.0, y, 0.6 - k * 0.07), 0.9, PLANK_W, step=1.0)
    arr = to_array(render(m, 24, 46, 40))
    return _shadowed(grain(arr, 518, amount=0.5, mats=(BARK, PLANK_W)), 40, 6, 1.6), 40


def chain_arr():
    """A rusty chain hanging down the wall from a bracket."""
    m = h.Model()
    m.ell((0, 34.0, 0), (2.0, 1.2, 1.4), IRON)
    for k in range(11):
        y = 33.0 - k * 3.0
        m.ell((0, y, 0), (1.0, 1.7, 0.7) if k % 2 else (0.7, 1.7, 1.0), RUST if k % 3 else IRON)
    m.ell((0, 0.6, 0), (2.4, 1.4, 1.8), IRON)
    arr = to_array(render(m, 12, 40, 36))
    return arr, 36
