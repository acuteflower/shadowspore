"""The furniture and the odd things of the hut (3D ellipsoid models like the trunks and the signpost, see hut_lib). Every builder returns an RGBA array whose
feet row (the floor at the object's depth centre) is returned too."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *

BED_H = 13.0  # the mattress top above the floor (units): tools/art_hero_wake.py lies her there


def _shadowed(arr, ground, rx, ry, dx=0):
    return soft_shadow(arr, arr.shape[1] / 2 + dx, ground + 1, rx, ry)


def bed_frames():
    """2 frames of 88 x 72: 0 the bed made (she lies under her own blanket), 1 the blanket as a heap. Feet row 62."""
    out = []
    for f in range(2):
        rng = rng_for(40)
        m = h.Model()
        L2 = 35.0
        # posts and rails
        for sx in (-1, 1):
            for sz in (-1, 1):
                tall = 40.0 if sx < 0 else 19.0
                log(m, V(sx * L2, 0, sz * 12.5), V(sx * L2, tall, sz * 12.5), 2.5, BARK_D if sx < 0 else BARK, step=1.3)
                m.ell((sx * L2, tall + 1.0, sz * 12.5), (2.8, 2.5, 2.8), BARK)  # finials
        for sz in (-1, 1):
            slab(m, V(-L2, 8.5, sz * 12.5), V(L2, 8.3, sz * 12.5), 1.9, 1.2, PLANK_W if sz > 0 else BARK, (0, 0, sz), step=1.4)
        for k in range(7):  # the headboard: slats, one missing, one hanging
            if k == 4 and not fresh():
                continue
            z = -10.5 + k * 3.5
            hang = 1.2 if k == 2 and not fresh() else 0.0
            slab(m, V(-L2, 12.0, z + hang), V(-L2 + hang * 2, 34.0 - (5 if k == 5 and not fresh() else 0), z), 1.4, 1.2, PLANK_W if k % 2 else BARK, (-1, 0, 0), step=1.3)
        for r_ in range(10):  # a carved ring on it
            a = r_ / 10 * math.tau
            m.ell((-L2 - 1.4, 27.5 + math.sin(a) * 3.0, math.cos(a) * 3.0), (0.4, 0.5, 0.5), BARK_D)
        if not fresh():
            slab(m, V(L2, 8.0, -11), V(L2, 11.5, -3), 1.2, 1.1, BARK_D, (1, 0, 0), step=1.2)  # the footboard is gone but for a splintered stump either side
            slab(m, V(L2, 8.0, 3), V(L2 - 3, 6.5, 11), 1.2, 1.1, BARK_D, (1, 0, 0), step=1.2)
        # the mattress: a linen cover over straw, burst at one corner, lumpy, patched
        m.ell((0, 11.0, 0), (L2 - 1.5, 2.3, 12.2), LINEN)
        for _ in range(12 if fresh() else 40):
            m.ell((rng.uniform(-30, 30), 12.4 + rng.uniform(-0.3, 0.5), rng.uniform(-9, 9)), (rng.uniform(3, 8), 0.9, rng.uniform(2, 4)), LINEN if (fresh() or rng.random() < 0.7) else STRAW)
        for _ in range(0 if fresh() else 26):  # straw out of the tear
            a = V(24 + rng.uniform(-3, 3), 12.8, 8 + rng.uniform(-2, 3))
            m.limb(a, a + V(rng.uniform(1, 6), rng.uniform(0.5, 3), rng.uniform(0, 4)), 0.22, 0.14, STRAW)
        m.ell((-27, 14.4, 0), (9.0, 2.4, 7.0), LINEN)  # the pillow
        m.ell((-27, 15.9, 0), (5.0, 0.7, 3.2), LINEN)
        if f == 1:
            from hut_cloth import cloth
            cloth(m, 1.0)  # the blanket left as a heap (the wake sheet's last blanket frame is the same)
        for _ in range(0 if fresh() else 26):  # moss and ivy on the foot, a teal bracket fungus on a post
            m.ell((rng.uniform(26, 36), rng.uniform(2, 18), 12.0 + rng.uniform(0, 1.5)), (rng.uniform(1.5, 3.5), 1.0, 1.3), MOSS_L)
        for k in range(0 if fresh() else 3):
            m.ell((-L2 - 2.4, 22 + k * 5, 11.6 + k * 0.4), (1.4, 0.9, 2.0), h.TEAL, kind="emit")
        if not fresh():
            ivy(m, V(-L2 - 1, 38, 12.8), 22, rng, glow_every=4)
        arr = to_array(render(m, 88, 76, 66))
        arr = grain(arr, 41, amount=0.6)
        out.append(_shadowed(arr, 66, 38, 6))
    sheet = np.zeros((76, 176, 4), np.uint8)
    sheet[:, :88] = out[0]
    sheet[:, 88:] = out[1]
    return sheet, 66


def table_arr():
    rng = rng_for(41)
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 32, 0, sz * 11), V(sx * 32.5, 25, sz * 11), 2.2, BARK if fresh() else BARK_D, step=1.3)
    slab(m, V(-32, 18, 11), V(32, 18, 11), 1.4, 3.6, BARK, (0, 0, 1))  # the apron
    for k in range(4):  # the top: boards, one missing, a crack, burn marks
        z = -12.5 + k * 8.4
        if k == 2 and not fresh():
            slab(m, V(-35, 25.5, z), V(-8, 25.4, z), 3.9, 1.3, PLANK_W)
            slab(m, V(14, 25.6, z), V(35, 25.5, z + 0.3), 3.9, 1.3, PLANK_W)
            continue
        slab(m, V(-36, 25.5, z), V(36, 25.6, z), 3.9, 1.3, (BARK, PLANK_W, PLANK, BARK)[k])
    p = V(-4, 27.0, -4)
    for s in range(0 if fresh() else 12):  # a violet crack
        q = p + V(rng.uniform(0.5, 2.5), 0, rng.uniform(0.4, 1.6))
        m.limb(p, q, 0.24, 0.2, h.VIOLET, kind="emit")
        p = q
    # things on it: a wooden bowl, a tin cup, a candle in a puddle of wax, an old book, a crust, spilt grain
    m.ell((-20, 28.0, 3), (5.2, 2.2, 5.2), BARK_D)
    m.ell((-20, 29.2, 3), (4.0, 1.2, 4.0), GAP)
    m.ell((-19, 29.5, 3), (1.6, 0.8, 1.6), STRAW)
    log(m, V(-6, 26.8, 6), V(-6, 31.5, 6), 1.9, IRON, step=1.0)
    m.ell((-6, 32.0, 6), (1.7, 0.4, 1.7), GAP)
    m.ell((22, 27.4, 5), (3.2, 0.9, 2.5), WAX)
    log(m, V(22, 27.0, 5), V(22, 32.0, 5), 1.0, WAX, step=0.9)
    m.ell((22, 32.6, 5), (0.6, 0.9, 0.6), FIRE, kind="emit")
    m.ell((26, 28.2, -6), (6.0, 1.1, 4.0), LINEN)
    m.ell((26, 29.4, -6), (5.6, 0.5, 3.6), CLAY)
    for _ in range(0 if fresh() else 14):
        m.ell((rng.uniform(-30, -10), 27.0, rng.uniform(-9, -3)), (0.5, 0.3, 0.4), STRAW)
    for _ in range(0 if fresh() else 6):  # moss growing at the legs' feet
        m.ell((rng.choice([-33, 33]), 1.5, rng.choice([-10, 10])), (2.5, 1.0, 2.0), MOSS_L)
    arr = to_array(render(m, 90, 66, 56))
    return _shadowed(grain(arr, 42, amount=0.6), 56, 38, 5), 56


def stool_arr(variant):
    rng = rng_for(43 + variant)
    m = h.Model()
    if variant == 2 and not fresh():  # tipped over
        m.ell((0, 5.5, 0), (7.4, 2.0, 7.0), BARK, R=h.rot_x(1.35))
        for k in range(3):
            a = k * 2.1 + 0.4
            log(m, V(math.cos(a) * 4.0, 5.4, math.sin(a) * 4.0), V(math.cos(a) * 6.0 + 9.0, 3.2 + k, math.sin(a) * 6.0 - 4.0), 1.3, BARK_D, step=1.0)
    else:
        for k in range(3):
            a = k * 2.1 + 0.4 + variant
            log(m, V(math.cos(a) * 5.0, 0, math.sin(a) * 4.0), V(math.cos(a) * 3.6, 12.0, math.sin(a) * 3.0), 1.5, BARK_D, step=1.0)
        m.ell((0, 12.6, 0), (8.0, 1.8, 7.0), BARK if variant == 0 else PLANK_W)
        m.ell((0, 13.9, 0), (6.2, 0.5, 5.4), PLANK_W if variant == 0 else BARK)
        for _ in range(0 if fresh() else 5):
            m.ell((rng.uniform(-5, 5), 14.0, rng.uniform(-4, 4)), (rng.uniform(1, 2.2), 0.4, rng.uniform(0.8, 1.6)), MOSS_L)
    arr = to_array(render(m, 28, 30, 24))
    return _shadowed(grain(arr, 44 + variant, amount=0.6), 24, 10, 2.5), 24


def chair_arr():
    rng = rng_for(46)
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 6.5, 0, sz * 6.0), V(sx * 6.4, 14, sz * 6.0), 1.5, BARK if fresh() else BARK_D, step=1.1)
    m.ell((0, 14.6, 0), (8.2, 1.4, 7.4), PLANK_W)
    log(m, V(-6.4, 14, -6), V(-6.0, 40, -6.2), 1.5, BARK, step=1.1)  # the back posts: one whole, one snapped
    log(m, V(6.4, 14, -6), V(6.6, 40 if fresh() else 27, -6.1), 1.5, BARK, step=1.1)
    for k in range(3):
        slab(m, V(-6.0, 22 + k * 5, -6.4), V(6.0 if (k != 2 or fresh()) else 0.0, 22 + k * 5 - (3 if (k == 1 and not fresh()) else 0), -6.4), 0.9, 1.2, PLANK_W, (0, 0, 1), step=1.1)
    if not fresh():
        m.limb(V(0.5, 32, -6.4), V(7.5, 24.5, -4.0), 0.9, 0.7, BARK_D)  # a rail hanging by a nail
    for _ in range(0 if fresh() else 5):
        m.ell((rng.uniform(-6, 6), 15.9, rng.uniform(-5, 5)), (rng.uniform(1, 2.5), 0.4, rng.uniform(0.8, 1.6)), MOSS)
    arr = to_array(render(m, 34, 56, 48))
    return _shadowed(grain(arr, 47, amount=0.6), 48, 12, 3), 48


def cupboard_arr():
    rng = rng_for(48)
    m = h.Model()
    W2, Hh = 26.0, 66.0
    for sx in (-1, 1):  # the sides
        slab(m, V(sx * W2, 0, 0), V(sx * W2, Hh, 0), 10.0, 1.6, BARK, (sx, 0, 0), step=1.3)
    slab(m, V(-W2, Hh, 0), V(W2, Hh, 0), 10.5, 1.6, PLANK_W, (0, 1, 0))  # the top with moss and fungi
    for y in (0.5, 22.0, 40.0):  # shelves
        slab(m, V(-W2, y + 3, 1), V(W2, y + 3, 1), 9.0, 1.2, PLANK_W, (0, 1, 0))
    if fresh():
        slab(m, V(0, 4, -9), V(0, Hh - 2, -9.2), W2, 1.0, BARK, (0, 0, 1), step=2.0)  # the back, a straight panel
    else:
        slab(m, V(-W2, 4, -9), V(W2, Hh - 2, -9.2), 1.0, 25.0, BARK_D, (0, 0, 1), step=2.0)  # the back
    # doors: the left one hangs from its lower hinge, the right is gone (renewed: two whole doors on the lower shelf, the upper ones stand open)
    if fresh():
        for sx in (-1, 1):
            slab(m, V(sx * 12.8, 5, 10.5), V(sx * 12.8, 21, 10.5), 12.0, 1.4, PLANK_W if sx < 0 else BARK, (0, 0, 1))
            m.ell((sx * 3.0, 14, 12.0), (1.0, 1.0, 0.8), h.GOLD)
    else:
        slab(m, V(-W2 + 1, 6, 10.5), V(-W2 + 2, 36, 10.5), 11.0, 1.4, PLANK_W, (0, 0, 1))
        for k in range(3):
            m.ell((-W2 + 12.6, 6 + k * 14, 11.4), (0.6, 0.7, 0.4), IRON)
        m.ell((-W2 + 20, 21, 12.0), (1.1, 1.1, 0.8), h.GOLD)
    # what is on the shelves: jars of clay and glass (teal), a stack of linen, an oil flask
    for (x, y, mat, r_, hh) in ((-12, 26, CLAY, 3.4, 8), (-4, 26, h.TEAL, 2.6, 7), (6, 26, CLAY, 3.0, 6), (16, 26, LINEN, 3.2, 5), (-14, 45, CLAY, 4.0, 9), (2, 45, h.TEAL, 3.0, 8), (14, 45, CLAY, 2.6, 6)):
        log(m, V(x, y, 2), V(x, y + hh, 2), r_, mat, step=1.0)
        if mat == h.TEAL:
            for q in range(3):
                m.ell((x, y + 1.5 + q * 2, 2 + r_ * 0.8), (0.9, 0.9, 0.5), h.TEAL, kind="emit")
        else:
            m.ell((x, y + hh + 0.5, 2), (r_ * 0.8, 0.5, r_ * 0.8), GAP)
    for _ in range(0 if fresh() else 18):
        m.ell((rng.uniform(-W2, W2), Hh + 1.6, rng.uniform(-8, 8)), (rng.uniform(2, 5), 0.9, rng.uniform(1.5, 3)), MOSS_L if rng.random() < 0.6 else MOSS)
    for k in range(0 if fresh() else 4):  # teal bracket fungi on the top and the side
        m.ell((W2 - 2 - k * 4.5, Hh + 2.2, 4 - k), (2.2, 1.0, 1.8), h.TEAL, kind="emit")
        m.ell((W2 + 1.4, 12 + k * 7, 8), (1.0, 1.2, 2.0), h.TEAL, kind="emit")
    if not fresh():
        ivy(m, V(W2 + 1.8, 60, 8), 38, rng, glow_every=5, sway=0.6)
    arr = to_array(render(m, 64, 92, 82))
    return _shadowed(grain(arr, 49, amount=0.6), 82, 28, 5), 82


def chest_arr():
    rng = rng_for(50)
    m = h.Model()
    for sx in (-1, 1):
        slab(m, V(sx * 21, 0, 0), V(sx * 21, 14, 0), 8.0, 1.5, BARK, (sx, 0, 0))
    slab(m, V(-21, 7, 8), V(21, 7, 8), 7.2, 1.5, PLANK_W, (0, 0, 1))
    slab(m, V(-21, 7, -8), V(21, 7, -8), 7.2, 1.5, BARK_D, (0, 0, -1))
    m.ell((0, 1.5, 0), (20, 1.0, 8), BARK_D)
    # the lid, ajar: a half cylinder tipped back
    R = h.rot_x(-0.0 if fresh() else -0.55)
    for k in range(34):
        x = -20 + k * 1.2
        if fresh():  # closed: a gently curved lid
            m.ell((x, 14.6 + 1.2 * (1 - abs(k - 16.5) / 17.0), 0.0), (1.6, 2.3, 9.2), PLANK_W if k % 2 else BARK)
        else:
            m.ell((x, 18.5, -5.0), (1.6, 4.2, 9.0), PLANK_W if k % 2 else BARK, R=R)
    for bx in (-12, 12):  # iron bands over the lid and the front
        for k in range(0 if fresh() else 10):
            a = k / 9 * 1.3
            m.ell((bx, 14.5 + math.sin(a) * 8.0 - 2 - 0.0, 4.0 - math.cos(a) * 9.0 + 5.0), (1.6, 1.0, 1.0), IRON)
        slab(m, V(bx, 0.5, 8.6), V(bx, 13.5, 8.6), 1.7, 0.6, IRON, (0, 0, 1))
    m.ell((0, 8.0 if not fresh() else 9.5, 9.2), (2.2, 2.6, 0.6), IRON)  # the lock, hanging open
    if not fresh():
        m.ell((0, 5.5, 9.6), (1.0, 1.8, 0.4), IRON)
    for _ in range(0 if fresh() else 22):  # what spilled: coins, a string of beads
        m.ell((rng.uniform(-9, 8), 14.2 + rng.uniform(0, 0.8), rng.uniform(-3, 4)), (0.9, 0.25, 0.9), h.GOLD)
    for _ in range(0 if fresh() else 18):
        m.ell((rng.uniform(-21, 21), rng.uniform(13, 15), -8 + rng.uniform(0, 14)), (rng.uniform(2, 4), 0.8, 1.5), MOSS_L if rng.random() < 0.5 else MOSS)
    arr = to_array(render(m, 56, 52, 44))
    return _shadowed(grain(arr, 51, amount=0.6), 44, 22, 4), 44


def barrel_arr():
    rng = rng_for(52)
    m = h.Model()
    for k in range(18):
        a = k / 18 * math.tau
        for s in range(14):
            t = s / 13
            y = 1.0 + t * 26
            rad = 10.0 + 2.4 * math.sin(t * math.pi)
            m.ell((math.cos(a) * rad, y, math.sin(a) * rad), (2.0, 2.2, 2.0), (BARK, PLANK_W, BARK_D)[k % 3], R=h.rot_y(-a))
    for y in (5.0, 22.0):  # hoops
        for k in range(26):
            a = k / 26 * math.tau
            rad = 10.4 + 2.4 * math.sin((y - 1) / 26 * math.pi)
            m.ell((math.cos(a) * rad, y, math.sin(a) * rad), (1.0, 1.1, 1.0), IRON)
    m.ell((0, 27.0, 0), (10.0, 0.6, 10.0), PLANK_W if fresh() else GAP)  # the open top, dark inside (renewed: a lid)
    for k in range(20):
        a = k / 20 * math.tau
        m.ell((math.cos(a) * 11.0, 27.6, math.sin(a) * 11.0), (1.4, 0.8, 1.4), PLANK_W)
    for _ in range(0 if fresh() else 12):
        a = rng.uniform(0, math.tau)
        m.ell((math.cos(a) * 11.5, rng.uniform(1, 9), math.sin(a) * 11.5), (rng.uniform(1.5, 3), 1.0, 1.0), MOSS_L)
    arr = to_array(render(m, 34, 44, 36))
    return _shadowed(grain(arr, 53, amount=0.6), 36, 14, 3.5), 36


def crates_arr():
    rng = rng_for(54)
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
    crate(V(-6, 17.5, -1), 8, 10, 7, BARK if fresh() else BARK_D)
    for _ in range(0 if fresh() else 16):  # straw spilling out of a broken one, the lid askew
        a = V(14 + rng.uniform(-4, 4), 11.5, 6)
        m.limb(a, a + V(rng.uniform(-3, 4), rng.uniform(-6, 1), rng.uniform(2, 6)), 0.2, 0.14, STRAW)
    if not fresh():
        slab(m, V(10, 12.4, 3), V(22, 15, 3), 6, 0.9, BARK_D, (0, 1, 0.3))
    for _ in range(0 if fresh() else 20):
        m.ell((rng.uniform(-22, 22), rng.uniform(1, 25), 9.0), (rng.uniform(1.5, 3), 0.9, 1.2), MOSS_L if rng.random() < 0.5 else MOSS)
    arr = to_array(render(m, 62, 60, 52))
    return _shadowed(grain(arr, 55, amount=0.6), 52, 26, 4), 52


def shelf_arr():
    """A shelf on the back wall: a board on two brackets with clay jars, a glass flask (glowing teal), candle stubs and a carved wooden bird."""
    rng = rng_for(56)
    m = h.Model()
    slab(m, V(-28, 0, 4), V(28, 0, 4), 4.5, 1.2, PLANK_W, (0, 1, 0))
    for sx in (-20, 20):
        m.limb(V(sx, -0.5, 1.0), V(sx, -7, 0.0), 1.1, 0.8, BARK_D)
        m.limb(V(sx, -3.0, 4.5), V(sx, -0.8, 1.5), 0.7, 0.6, BARK_D)
    for x, mat, r_, hh in ((-22, CLAY, 3.2, 7), (-14, CLAY, 2.5, 5), (-3, h.TEAL, 2.4, 8), (16, CLAY, 3.0, 6)):
        log(m, V(x, 1.2, 4), V(x, 1.2 + hh, 4), r_, mat, step=1.0)
        if mat == h.TEAL:
            for q in range(3):
                m.ell((x, 3 + q * 2, 4 + r_ * 0.8), (0.9, 0.9, 0.4), h.TEAL, kind="emit")
    for x, hh in ((7, 3.0), (11, 5.0)):  # candle stubs with drips
        log(m, V(x, 1.2, 4), V(x, 1.2 + hh, 4), 1.1, WAX, step=0.9)
        m.limb(V(x + 1.0, 1.2 + hh, 4.8), V(x + 1.0, 0.8 + hh * 0.4, 4.9), 0.3, 0.25, WAX)
    m.ell((23, 4.0, 4), (2.2, 2.4, 1.6), BARK)  # the carved bird
    m.ell((25.4, 5.6, 4), (1.2, 1.1, 1.0), BARK)
    m.ell((26.8, 5.4, 4), (0.9, 0.4, 0.4), PLANK_W)
    for _ in range(0 if fresh() else 8):
        m.ell((rng.uniform(-28, 28), 1.5, 4 + rng.uniform(-2, 3)), (rng.uniform(1.5, 3), 0.8, 1.3), MOSS)
    arr = to_array(render(m, 70, 34, 18))
    return grain(arr, 57, amount=0.6), 18


def rack_arr():
    """The knight's sword rack on the wall: an old board with three pegs, empty but for dust and a hook with a leather strap; one rusty dagger."""
    rng = rng_for(58)
    m = h.Model()
    slab(m, V(-16, 0, 0), V(16, 0, 0), 4.5, 1.4, BARK, (0, 0, 1))
    for x in (-9, 0, 9):
        log(m, V(x, 2.0, 1.0), V(x, 2.6, 6.5), 1.1, BARK_D, step=0.9)
    for x in (-9, 9):  # the swords' bed: two grooves of cleaner wood
        slab(m, V(x - 8, 10, 1.6), V(x + 8, 10, 1.6), 0.9, 0.35, PLANK_W, (0, 0, 1))
    m.limb(V(0, 2.8, 6.8), V(0, -6.0, 7.2), 0.5, 0.4, h.LEATHER)
    slab(m, V(-6, 12, 2.4), V(6, 15, 2.4), 0.8, 0.5, IRON, (0, 0, 1))  # a dagger
    m.ell((8.0, 15.4, 2.4), (1.0, 1.0, 0.6), h.LEATHER)
    for _ in range(0 if fresh() else 6):
        m.ell((rng.uniform(-16, 16), 6.0, 1.2), (rng.uniform(1.5, 3), 0.8, 1.0), MOSS)
    arr = to_array(render(m, 44, 40, 20))
    return grain(arr, 59, amount=0.6), 20


def fireplace_arr():
    """The chimney breast of rounded stones with the opening (black, a bed of embers), a heavy mantel log with a clay pot and candle stubs, an iron arm with a pot,
    a woodpile and a root coming down. The flames are separate frames (hut_fx.py). Feet row 96."""
    rng = rng_for(60)
    m = h.Model()
    # the stones: rows, rounded, mossy, the opening left free
    def opening(x, y):
        return abs(x) < 17 and 0 <= y < 28 + 4 * math.cos(x / 17 * 1.4)

    y = 1.5
    row = 0
    while y < 74:
        x = -34.0 + (row % 2) * 4.0
        while x < 34.0:
            w = rng.uniform(6, 11)
            hh = rng.uniform(5.5, 8.5)
            cx = x + w / 2
            if not opening(cx, y) and not (row > 6 and abs(cx) > 20 + (row - 6) * 0.9):
                m.ell((cx, y + hh / 2, 0), (w / 2 * 0.95, hh / 2 * 0.95, 7.5), (STONE, STONE_L, STONE, STONE_L)[int(rng.integers(0, 4))])
                if rng.random() < 0.35 and not fresh():
                    m.ell((cx + rng.uniform(-2, 2), y + hh * 0.85, 6.5), (rng.uniform(2, 4), 0.8, 1.6), MOSS_L if rng.random() < 0.5 else MOSS)
            x += w
        y += rng.uniform(5.5, 8.0)
        row += 1
    m.ell((0, 14, -4), (17, 14, 2.0), GAP)  # the black of the opening
    for k in range(5):  # logs and embers
        m.ell((-12 + k * 6, 3.0, 4.0), (3.4, 2.0, 2.2), BARK_D, R=h.rot_y(0.4 * (k % 2) - 0.2))
        m.ell((-12 + k * 6, 4.6, 4.2), (2.4, 0.9, 1.6), FIRE, kind="emit")
    # the mantel: a heavy log across, a clay pot and candle stubs on it
    log(m, V(-27, 33.5, 8), V(27, 33.5, 8), 3.4, BARK_D, step=1.4)
    m.ell((-18, 40, 8), (3.2, 4.0, 3.2), CLAY)
    for x, hh in ((-6, 4.0), (8, 6.0), (13, 3.0)):
        log(m, V(x, 37, 8), V(x, 37 + hh, 8), 1.0, WAX, step=0.9)
    # iron arm and pot
    log(m, V(-14, 28, 2), V(6, 28, 2), 0.7, IRON, step=1.0)
    m.limb(V(0, 28, 2), V(0, 23, 2), 0.35, 0.3, IRON)
    m.ell((0, 20, 2), (4.5, 3.6, 4.0), IRON)
    m.ell((0, 23.2, 2), (3.4, 0.6, 3.0), GAP)
    # woodpile at the right
    for k in range(12 if fresh() else 9):
        log(m, V(36 + (k % 3) * 3.2, 3 + (k // 3) * 3.6, 10), V(36 + (k % 3) * 3.2 + 0.5, 3 + (k // 3) * 3.6, 2), 1.7, (BARK, PLANK_W, BARK_D)[k % 3], step=1.0)
    p = V(-31, 72, 7)
    for s in range(0 if fresh() else 30):  # a root down the breast, a violet vein in it
        q = p + V(rng.uniform(-0.8, 1.2) + 0.5 * math.sin(s * 0.4), -2.3, rng.uniform(-0.1, 0.3))
        m.limb(p, q, max(1.1 - s * 0.025, 0.4), max(1.0 - s * 0.025, 0.35), BARK)
        if s % 2 == 0:
            m.limb(p + V(0.3, 0, 0.7), q + V(0.3, 0, 0.7), 0.17, 0.15, h.VIOLET, kind="emit")
        p = q
    for k in range(0 if fresh() else 4):
        m.ell((29 - k * 3.5, 74.5, 6), (2.2, 1.0, 1.7), h.TEAL, kind="emit")
    arr = to_array(render(m, 112, 112, 100))
    return _shadowed(grain(arr, 61, amount=0.5, mats=(STONE, STONE_L, BARK_D, BARK, PLANK_W)), 100, 38, 5), 100


def herbs_arr():
    """Bundles of dried herbs and flowers hanging from a cord (it sways in the game): 5 bundles, moss green, straw, a few teal blossoms. Hung from row 0."""
    rng = rng_for(62)
    m = h.Model()
    log(m, V(-18, 0, 0), V(18, -0.5, 0), 0.6, BARK_D, step=1.0)
    for k in range(5):
        x = -14 + k * 7
        ln = rng.uniform(8, 15)
        m.limb(V(x, -0.5, 0.5), V(x, -3.5, 0.6), 0.3, 0.25, BARK)
        for q in range(10):
            a = rng.uniform(-0.5, 0.5)
            L_ = ln * rng.uniform(0.6, 1.0)
            mat = (MOSS, MOSS_L, STRAW, MOSS)[int(rng.integers(0, 4))]
            m.limb(V(x, -3.5, 0.6), V(x + a * L_ * 0.5, -3.5 - L_, 0.6 + rng.uniform(-0.8, 0.8)), 0.9, 0.2, mat)
        for q in range(3):
            m.ell((x + rng.uniform(-2, 2), -3.5 - ln * rng.uniform(0.5, 1.0), 1.6), (0.9, 0.9, 0.9), h.TEAL, kind="emit")
    arr = to_array(render(m, 44, 46, 3))
    return grain(arr, 63, amount=0.4, mats=(MOSS, MOSS_L, STRAW)), 3


def lantern_arr():
    """A hanging lantern: a chain, an iron cage, a glowing teal core (the lanterns of the trees); swings in the game. Hung from row 0."""
    m = h.Model()
    for k in range(7):
        m.ell((0, -1.4 - k * 2.2, 0), (0.55, 1.0, 0.4), IRON, R=h.rot_y(k * 1.57))
    m.ell((0, -17.5, 0), (3.2, 1.4, 3.2), IRON)
    m.ell((0, -23.5, 0), (3.0, 4.4, 3.0), h.TEAL, kind="emit")
    for k in range(4):
        a = k * 1.57 + 0.78
        log(m, V(math.cos(a) * 3.4, -17.5, math.sin(a) * 3.4), V(math.cos(a) * 3.4, -29.5, math.sin(a) * 3.4), 0.5, IRON, step=0.9)
    m.ell((0, -30.5, 0), (3.8, 1.5, 3.8), IRON)
    m.ell((0, -29.0, 0), (1.6, 1.1, 1.6), h.VIOLET, kind="emit")
    arr = to_array(render(m, 24, 38, 2))
    return arr, 2


def sapling_arrs():
    """The young tree that has grown through the floor: a slender, veined trunk with a root flare, two branches. Returns (trunk, crown) with the same frame:
    the crown (leaves, buds) is separate so it can sway. Feet row 150."""
    rng = rng_for(64)
    m = h.Model()
    c = h.Model()
    H = 118.0

    def spine(t):
        return V(5.0 * math.sin(t * 2.2) + 2.0 * t, t * H, 2.0 * math.sin(t * 3.1))

    for k in range(7):  # the root flare and roots on the floor
        a = k / 7 * math.tau
        m.limb(V(math.cos(a) * 2.0, 3.0, math.sin(a) * 2.0), V(math.cos(a) * 12.0, 0.8, math.sin(a) * 9.0), 2.2, 0.8, BARK)
    n = 70
    for i in range(n + 1):
        t = i / n
        p = spine(t)
        r = 4.2 * (1.0 - t) + 1.5 * t + 0.3 * math.sin(t * 20)
        m.ell(p + V(0, 3.0, 0), (r, 1.4, r), BARK if i % 9 else BARK_D)
    for g in range(5):  # veins (violet) and moss
        p = spine(0.05) + V(0.0, 3.0, 3.6)
        for i in range(10, 60, 2):
            t = i / n
            q = spine(t) + V(math.sin(t * 9 + g) * 1.4, 3.0, 3.0 * (1.0 - t) + 1.5)
            if (i // 2 + g) % 4:
                m.ell(q, (0.4, 0.9, 0.3), h.VIOLET, kind="emit")
        break
    for _ in range(14):
        t = rng.uniform(0.0, 0.5)
        m.ell(spine(t) + V(rng.uniform(-3, 3), 3.0, rng.uniform(1.5, 3.4)), (rng.uniform(1, 2.4), 1.2, 0.9), MOSS_L if rng.random() < 0.5 else MOSS)
    # two branches and the crown of leaves with buds
    tops = []
    for base_t, dirx, ln in ((0.55, -1, 22), (0.72, 1, 20), (0.95, 0, 12)):
        a = spine(base_t) + V(0, 3.0, 0)
        e = a + V(dirx * ln, ln * 0.55, rng.uniform(-3, 3))
        m.limb(a, e, 1.5, 0.6, BARK)
        tops.append(e)
    tops.append(spine(1.0) + V(0, 3.0, 0))
    for e in tops:
        for _ in range(46):
            q = e + V(rng.normal(0, 9), rng.normal(2, 7), rng.normal(0, 6))
            R = h.rot_x(rng.uniform(-1, 1)) @ h.rot_y(rng.uniform(0, math.tau))
            c.ell(q, (rng.uniform(2.6, 4.4), 0.7, rng.uniform(1.4, 2.4)), MOSS_L if rng.random() < 0.38 else MOSS, R=R)
        for _ in range(5):
            q = e + V(rng.normal(0, 8), rng.normal(0, 6), rng.uniform(2, 6))
            c.ell(q, (0.9, 0.9, 0.9), h.TEAL, kind="emit")
        for _ in range(2):
            q = e + V(rng.normal(0, 7), rng.normal(-1, 5), rng.uniform(2, 6))
            c.ell(q, (0.8, 0.8, 0.8), h.VIOLET, kind="emit")
    arr_trunk = to_array(render(m, 96, 170, 150))
    arr_crown = to_array(render(c, 96, 170, 150))
    # the trunk's own picture without the crown overlapped? both are drawn; the crown on top
    return _shadowed(grain(arr_trunk, 65, amount=0.5), 150, 20, 4), arr_crown, 150


def pots_arr():
    rng = rng_for(66)
    m = h.Model()
    for (x, z, r_, hh, mat) in ((-9, 2, 4.2, 9, CLAY), (0, -3, 3.4, 7, CLAY), (8, 3, 5.0, 10, STONE_L), (15, -2, 2.6, 5, CLAY)):
        for s in range(10):
            t = s / 9
            m.ell((x, 0.8 + t * hh, z), (r_ * (0.85 + 0.35 * math.sin(t * math.pi)), hh / 8, r_ * (0.85 + 0.35 * math.sin(t * math.pi))), mat)
        m.ell((x, hh + 1.2, z), (r_ * 0.6, 0.5, r_ * 0.6), GAP)
    if not fresh():
        m.ell((-9, 6.0, 6.2), (1.6, 1.2, 0.5), GAP)  # a crack
    for _ in range(0 if fresh() else 5):
        m.ell((rng.uniform(-12, 18), 0.8, rng.uniform(-3, 6)), (rng.uniform(1.4, 3), 0.7, 1.4), MOSS_L)
    arr = to_array(render(m, 44, 30, 24))
    return _shadowed(grain(arr, 67, amount=0.4, mats=(CLAY, STONE_L, MOSS)), 24, 20, 3), 24


def rug_arr():
    """The old rug seen from above (a woven oval-ish rectangle in wine and straw with a border, fringe, moth holes and worn patches). 128 x 56."""
    rng = rng_for(68)
    m = h.Model()
    W, D = 128 * U, 56 * U
    nx, nz = 84, 38
    for i in range(nx):
        for j in range(nz):
            x = -W / 2 + (i + 0.5) * W / nx
            z = -D / 2 + (j + 0.5) * D / nz
            u, v = abs(x) / (W / 2), abs(z) / (D / 2)
            edge = max(u, v)
            if edge > 1.0:
                continue
            if fbm(x * 0.2, z * 0.2, 9) > 0.7 and rng.random() < 0.9 and edge < 0.92 and not fresh():
                continue  # a moth hole
            if edge > 0.86:
                mat = STRAW if (i + j) % 4 else WOOL
            elif edge > 0.78:
                mat = WOOL
            elif (int(u * 9) + int(v * 9)) % 3 == 0:
                mat = LINEN
            elif (int(u * 9) + int(v * 9)) % 3 == 1:
                mat = CLAY
            else:
                mat = WOOL
            m.ell((x, 0.6 + 0.15 * rng.random(), z), (W / nx * 0.75, 0.55, D / nz * 0.75), mat)
    for i in range(30):  # fringe
        x = -W / 2 + (i + 0.5) * W / 30
        for sz in (-1, 1):
            m.limb(V(x, 0.6, sz * D / 2), V(x + rng.uniform(-0.6, 0.6), 0.5, sz * (D / 2 + rng.uniform(2.0, 3.6))), 0.3, 0.2, STRAW)
    for _ in range(0 if fresh() else 22):
        m.ell((rng.uniform(-W / 2, W / 2), 1.0, rng.uniform(-D / 2, D / 2)), (rng.uniform(2, 5), 0.5, rng.uniform(1.5, 3)), MOSS)
    arr = to_array(render(m, 128 + 8, 56 + 12, 34, pitch=90.0, light=(-0.5, 0.72, -0.5)))
    return grain(arr, 69, amount=0.4, mats=(WOOL, LINEN, STRAW, CLAY)), 34
