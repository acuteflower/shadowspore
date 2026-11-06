"""Props of the deeper mine zones (docs/mine.md section 5): the forge of zone 2 (hearth with a coal bed, anvil, quenching trough), the crystal grottos of zone 3
(clusters that pulse) and the void chambers of zone 4 (cracks in the floor, pods, pairs of eyes in the dark). Same renderer and palettes as mine_props.py;
every builder returns (RGBA array, feet row), the driver tools/art_mine_props.py writes them."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *
from mine_props import COAL, RUST, _shadowed


def anvil_arr():
    """An iron anvil on a stump."""
    m = h.Model()
    m.ell((0, 5, 0), (7.5, 5.5, 6.5), BARK_D)  # the stump
    m.ell((0, 10.4, 0), (7.0, 1.0, 6.0), BARK)
    m.ell((0, 13.2, 0), (6.6, 2.2, 3.6), IRON)  # waist
    m.ell((0, 16.4, 0), (10.5, 2.0, 3.8), IRON)  # face
    m.ell((9.6, 15.6, 0), (4.4, 1.2, 2.2), IRON)  # horn
    m.ell((-8.6, 16.8, 0), (2.4, 1.2, 3.0), IRON)  # heel
    m.ell((0, 18.2, -0.6), (9.0, 0.5, 3.0), STONE_L)  # the polished top
    m.ell((-1.0, 18.6, 0.4), (1.6, 0.4, 1.2), FIRE, kind="emit")  # a cooling sliver of iron
    arr = to_array(render(m, 36, 34, 28))
    return _shadowed(grain(arr, 411, amount=0.4, mats=(BARK, BARK_D)), 28, 10, 3), 28


def forge_arr():
    """The forge: a stone hearth with a hood, a bed of glowing coals in the front, a chimney going up into the dark."""
    rng = rng_for(412)
    m = h.Model()
    m.ell((0, 5.0, 0), (22.0, 5.0, 10.0), STONE)  # the base
    m.ell((0, 10.6, -1.0), (22.5, 1.4, 11.0), STONE_L)  # the top of the base
    m.ell((0, 3.0, 9.0), (21.0, 2.8, 2.4), STONE_L)  # the front lip
    for _ in range(12):  # the bed of coals
        m.ell((rng.uniform(-14, 14), 11.4, rng.uniform(-1, 7)), (rng.uniform(1.6, 3.0), 0.9, rng.uniform(1.4, 2.4)), FIRE, kind="emit")
    for sx in (-1, 1):  # posts
        log(m, V(sx * 17.0, 11, -6), V(sx * 17.0, 40, -6), 2.4, STONE, step=1.2, taper=0.8)
    m.ell((0, 41.5, -6), (21, 2.4, 6.0), STONE_L)  # the lintel of the hood
    for i in range(7):  # the hood narrows into the chimney
        t = i / 6.0
        m.ell((0, 44.0 + i * 5.0, -7.0), (19.0 - 12.0 * t, 2.8, 5.0 - 1.5 * t), STONE if i % 2 else STONE_L)
    m.ell((0, 12.0, -9.0), (20.0, 14.0, 1.6), COAL)  # the sooty back wall
    for _ in range(8):  # soot and rust
        m.ell((rng.uniform(-16, 16), rng.uniform(14, 36), -8.0), (rng.uniform(1.6, 3.4), rng.uniform(1.2, 3.4), 0.6), COAL)
    log(m, V(-12, 4.4, 10.5), V(12, 4.4, 10.5), 0.9, RUST, step=1.0)  # a poker rod on the lip
    arr = to_array(render(m, 64, 90, 76))
    return _shadowed(grain(arr, 413, amount=0.45, mats=(STONE, STONE_L)), 76, 24, 4), 76


def quench_arr():
    """A quenching trough: an old timber trough full of black water, a hot iron bar resting across it."""
    m = h.Model()
    m.ell((0, 5.0, 0), (17.0, 5.0, 6.5), BARK)
    m.ell((0, 8.5, 0), (15.0, 1.6, 4.6), GAP)  # the water
    m.ell((0, 9.4, 0.4), (13.0, 0.4, 3.2), SKY, kind="emit")  # a reflection
    for sx in (-1, 1):
        m.ell((sx * 16.5, 5.0, 0), (1.6, 5.2, 6.8), BARK_D)
    log(m, V(-9, 10.6, -1.0), V(9, 10.6, 0.5), 0.9, IRON, step=1.0)
    m.ell((9.4, 10.6, 0.5), (1.3, 0.9, 0.9), FIRE, kind="emit")  # the hot end
    arr = to_array(render(m, 44, 30, 22))
    return _shadowed(grain(arr, 414, amount=0.4, mats=(BARK, BARK_D)), 22, 15, 3), 22


def _crystal(m, rng, x, z, height, mat, thick=2.4, lean=0.0):
    top = V(x + lean, height, z)
    log(m, V(x, 0.5, z), top, thick, mat, step=0.9, taper=0.2)
    m.ell((x + lean, height + 0.6, z), (thick * 0.3, 1.4, thick * 0.3), mat, kind="emit")


def crystal_arr(seed, mat, heights):
    rng = rng_for(seed)
    m = h.Model()
    m.ell((0, 0.6, 0), (14, 1.4, 8), STONE)  # the rock they grow from
    for k, hgt in enumerate(heights):
        x = (k - (len(heights) - 1) / 2) * 6.0 + rng.uniform(-1.5, 1.5)
        _crystal(m, rng, x, rng.uniform(-3, 3), hgt, mat, thick=rng.uniform(2.0, 3.0), lean=rng.uniform(-2.5, 2.5))
    arr = to_array(render(m, 52, 66, 54))
    return _shadowed(arr, 54, 14, 3), 54


def crystal_a_arr():
    return crystal_arr(421, h.TEAL, (22, 34, 16, 12))


def crystal_b_arr():
    return crystal_arr(422, h.VIOLET, (28, 18, 40, 14, 22))


def crystal_big_arr():
    """A pillar of crystal from the floor to far above the heroine's head: the heart of a grotto."""
    rng = rng_for(423)
    m = h.Model()
    m.ell((0, 0.8, 0), (20, 2.0, 12), STONE)
    _crystal(m, rng, 0, 0, 70, h.TEAL, thick=7.0, lean=3.0)
    _crystal(m, rng, -12, 3, 38, h.VIOLET, thick=3.6, lean=-3.0)
    _crystal(m, rng, 12, -2, 30, h.TEAL, thick=3.2, lean=3.0)
    arr = to_array(render(m, 64, 110, 96))
    return _shadowed(arr, 96, 20, 4), 96


def void_crack_arr():
    """A crack in the floor with a violet light in it (flat, 2D)."""
    rng = np.random.default_rng(431)
    w, hh = 48, 18
    arr = np.zeros((hh, w, 4), np.uint8)
    y = hh / 2
    for x in range(2, w - 2):
        y += rng.uniform(-0.9, 0.9)
        y = min(max(y, 3.0), hh - 4.0)
        thick = 1 + int(rng.random() < 0.35)
        for t in range(thick):
            yy = int(y) + t
            arr[yy, x] = (8, 4, 14, 255)
            if rng.random() < 0.7:
                arr[yy, x] = (186, 120, 255, 255) if rng.random() < 0.6 else (236, 190, 255, 255)
        if rng.random() < 0.18:  # a branch
            by = int(y) + rng.choice([-1, 1]) * int(rng.integers(2, 4))
            if 0 <= by < hh:
                arr[by, x] = (120, 70, 200, 255)
    return arr, hh // 2


def void_pod_arr():
    """A pod grown out of the floor: dark flesh, magenta veins, a core that glows."""
    rng = rng_for(432)
    m = h.Model()
    m.ell((0, 1.0, 0), (9, 1.6, 7), COAL)
    m.ell((0, 9.0, 0), (6.4, 8.5, 5.6), COAL)
    for _ in range(9):  # veins
        a = rng.uniform(0, math.tau)
        m.ell((math.cos(a) * 5.4, rng.uniform(4, 13), math.sin(a) * 4.6 + 1.0), (0.5, rng.uniform(1.6, 3.4), 0.5), h.VIOLET, kind="emit")
    m.ell((0, 10.0, 3.6), (2.2, 2.6, 1.2), h.CRYSTAL, kind="emit")  # the core
    for sx in (-1, 1):  # stalks
        log(m, V(sx * 6, 1, 0), V(sx * 9, 8, 1), 1.2, COAL, step=1.0, taper=0.3)
    arr = to_array(render(m, 34, 40, 32))
    return _shadowed(arr, 32, 9, 2), 32


def void_eyes_arr():
    """Two eyes in the dark of a wall niche (flat, 2D): a slit of magenta light each, a faint halo."""
    w, hh = 26, 12
    arr = np.zeros((hh, w, 4), np.uint8)
    for cx in (8, 17):
        for dx in range(-3, 4):
            arr[5 + (abs(dx) > 1), cx + dx] = (255, 90, 220, 255)
            arr[4 + (abs(dx) > 2), cx + dx] = (200, 40, 170, 255) if abs(dx) < 3 else arr[4 + (abs(dx) > 2), cx + dx]
        arr[5, cx] = (255, 235, 250, 255)
        for dx in range(-4, 5):
            for dy in (3, 7):
                if arr[dy, cx + dx, 3] == 0 and (dx + dy) % 2 == 0:
                    arr[dy, cx + dx] = (160, 40, 150, 120)
    return arr, hh // 2
