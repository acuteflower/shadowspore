"""The hut seen from outside (3D like the rest): a log cabin with notched corners on a foundation of fieldstones, a sagging roof of boards with a hole and moss,
a crooked stone chimney, a window with a broken shutter and a warm glow, ivy, roots, glowing mushrooms, a woodpile, a lantern. Door leaf: hut_room.door_arr."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *

FW, FH, GROUND = 208, 200, 174
WINDOW_BOX = None  # (x0, x1, y0, y1) of the glass in the renewed picture, set by hut_arr
DOOR_W, DOOR_H = 36, 40  # px of the doorway
HALF = 62.0  # half of the front wall, units


def hut_arr(seed=11):
    rng = rng_for(seed)
    m = h.Model()
    wall_top = 54.0
    door_x = (-17.0, 17.0)
    win = (38.0, 16.0, 40.0) if fresh() else (40.0, 18.0, 37.0)  # centre x, y0, y1 (renewed: bigger)
    WH = 12.0 if fresh() else 10.5  # the log wall is cut this wide each side of the window

    def cut(x, y):
        if door_x[0] - 3 < x < door_x[1] + 3 and y < 47:
            return True
        return abs(x - win[0]) < WH and win[1] < y < win[2]

    # foundation stones
    x = -HALF - 6
    while x < HALF + 6:
        w = rng.uniform(7, 12)
        m.ell((x + w / 2, 2.2, 3.0), (w / 2, rng.uniform(2.4, 3.6), rng.uniform(4.0, 6.0)), STONE if rng.random() < 0.6 else STONE_L)
        if rng.random() < 0.5 and not fresh():
            m.ell((x + w / 2, 5.0, 4.5), (rng.uniform(2, 4), 0.8, 1.6), MOSS_L)
        x += w
    # the front wall: five logs; the corners' log ends stand out
    mats = [BARK, PLANK_W, BARK_D, BARK, PLANK_W, BARK_D]
    for li in range(6):
        y = 7.0 + li * 8.6
        x = -HALF
        while x <= HALF:
            if not cut(x, y):
                r = 4.7 * (1.0 + 0.06 * math.sin(x * 0.1 + li * 1.7))
                m.ell((x, y + 0.4 * math.sin(x * 0.05 + li), 1.5), (3.1, r, r), mats[li])
            x += 1.4
        for sx in (-1, 1):  # the notched ends
            log(m, V(sx * (HALF - 3), y, 1.5), V(sx * (HALF + 6), y + 0.4 * sx, 1.5), 4.6, BARK_D if li % 2 else BARK, step=1.2)
            m.ell((sx * (HALF + 6.3), y + 0.4 * sx, 1.5), (1.0, 4.4, 4.4), PLANK_W)
    # doorway: posts, lintel, the dark inside, a stone step
    for sx in door_x:
        log(m, V(sx - 2.0 * np.sign(sx), 0, 3.4), V(sx - 2.0 * np.sign(sx), 50, 3.4), 3.4, BARK_D, step=1.3)
    log(m, V(door_x[0] - 7, 49.5, 3.0), V(door_x[1] + 7, 49.5, 3.0), 3.0, BARK, step=1.3)
    m.ell((0, 24, -4.0), (door_x[1] + 3, 27, 0.8), GAP)
    for k in range(4):
        m.ell((-13 + k * 9, 1.2, 8.5), (5.2, 1.8, 3.6), STONE_L if k % 2 else STONE)
    # window: frame, a glow from inside, one shutter hanging askew
    wx, wy0, wy1 = win
    if fresh():  # renewed: a deep recess, a framed pane with a cross of bars, a sill and a lintel, two painted shutters folded back, a flower box
        gy = (wy0 + wy1) / 2
        m.ell((wx, gy, -2.4), (11.0, (wy1 - wy0) / 2 + 0.6, 0.6), GAP)
        m.ell((wx, gy, -1.4), (10.0, (wy1 - wy0) / 2 - 0.9, 0.5), FIRE, kind="emit")
        slab(m, V(wx - 10.4, gy, 3.6), V(wx + 10.4, gy, 3.6), 0.8, 0.8, PLANK_W, (0, 0, 1))  # the cross
        slab(m, V(wx, wy0, 3.6), V(wx, wy1, 3.6), 0.8, 0.8, PLANK_W, (0, 0, 1))
        for dy in (wy0 - 1.3, wy1 + 1.3):  # frame head and foot
            slab(m, V(wx - 12.8, dy, 4.4), V(wx + 12.8, dy, 4.4), 1.7, 1.2, BARK, (0, 0, 1))
        for dx in (wx - 11.7, wx + 11.7):
            slab(m, V(dx, wy0 - 1, 4.4), V(dx, wy1 + 1, 4.4), 1.5, 1.2, BARK, (0, 0, 1))
        slab(m, V(wx - 15.0, wy1 + 4.2, 5.0), V(wx + 15.0, wy1 + 4.2, 5.0), 1.9, 1.7, PLANK_W, (0, 0, 1))  # the lintel, wider than the frame
        slab(m, V(wx - 14.0, wy0 - 3.7, 7.4), V(wx + 14.0, wy0 - 3.9, 7.4), 2.4, 2.0, PLANK_W, (0, 0, 1))  # the sill, jutting out
        for sx in (-1, 1):  # painted shutters, boards and a Z brace, iron hinges
            cx = wx + sx * 17.4
            for k in range(2):
                slab(m, V(cx + (k - 0.5) * 4.4, wy1 + 2.0, 5.8), V(cx + (k - 0.5) * 4.4, wy0 - 2.0, 5.8), 2.1, 1.0, SHUT, (0, 0, 1), step=1.3)
            slab(m, V(cx - 4.2, wy0 + 1.0, 6.9), V(cx + 4.2, wy1 - 1.0, 6.9), 0.9, 0.5, BARK, (0, 0, 1), step=1.1)
            for yy in (wy0 + 2.5, wy1 - 2.5):
                m.ell((wx + sx * 13.0, yy, 6.9), (2.2, 0.5, 0.4), IRON)
        slab(m, V(wx - 11.5, wy0 - 5.5, 9.0), V(wx + 11.5, wy0 - 5.5, 9.0), 1.7, 2.2, BARK_D, (0, 0, 1))  # the flower box on the sill
        for k in range(7):
            t = wx - 10 + k * 3.3
            m.ell((t, wy0 - 2.4, 9.0), (1.2, 1.9, 1.1), MOSS if k % 2 else MOSS_L)
            if k % 2 == 0:
                m.ell((t + 0.4, wy0 - 0.6, 9.3), (0.9, 0.9, 0.9), h.TEAL, kind="emit")
    else:
        m.ell((wx, (wy0 + wy1) / 2, -2.0), (9.5, (wy1 - wy0) / 2, 0.6), GAP)
        m.ell((wx, (wy0 + wy1) / 2, -1.2), (8.6, (wy1 - wy0) / 2 - 0.8, 0.5), FIRE, kind="emit")
        slab(m, V(wx - 9, (wy0 + wy1) / 2, 4.2), V(wx + 9, (wy0 + wy1) / 2, 4.2), 0.7, 0.7, PLANK_W, (0, 0, 1))
        slab(m, V(wx, wy0, 4.2), V(wx, wy1, 4.2), 0.7, 0.7, PLANK_W, (0, 0, 1))
        for dy in (wy0 - 1.2, wy1 + 1.2):
            slab(m, V(wx - 11.5, dy, 4.8), V(wx + 11.5, dy, 4.8), 1.5, 0.9, PLANK_W, (0, 0, 1))
        for dx in (wx - 10.5, wx + 10.5):
            slab(m, V(dx, wy0 - 1, 4.8), V(dx, wy1 + 1, 4.8), 1.3, 0.9, PLANK_W, (0, 0, 1))
        slab(m, V(wx + 11, wy1, 5.6), V(wx + 15.5, wy0 - 3, 6.8), 4.0, 0.9, BARK_D, (0, 0, 1))  # the shutter
        slab(m, V(wx - 12, wy1 + 0.5, 5.6), V(wx - 11.0, wy0 + 3, 5.6), 3.6, 0.9, PLANK_W, (0, 0, 1))
    # the roof: boards in rows up the south slope (eaves y 45 z 14, ridge y 70 z -34), sagging, one hole, moss, rotten patches
    eave = V(0, 61.0, 14.0)
    ridge = V(0, 82.0, -26.0)
    slope = ridge - eave
    length = float(np.linalg.norm(slope))
    up = slope / length
    normal = np.cross(V(1, 0, 0), up)
    normal = normal * (1 if normal[1] > 0 else -1)
    rows = int(length / 4.3)
    roof_a = math.atan2(normal[2], normal[1])
    hole_c = (1.0e4, 0.45) if fresh() else (14.0, 0.45)  # x, fraction up the slope (renewed: no hole)
    for r in range(rows + 1):
        t = r / rows
        base = eave + slope * t
        sag = -2.4 * math.sin(math.pi * t) * (0.12 if fresh() else 0.5)
        mat = ROOF  # shingles (roof_pass); in the old roof 30 % of the segments below are bare, rotten boards instead
        rng.integers(0, 4)
        x = -HALF - 12
        while x < HALF + 12:
            seg = rng.uniform(26, 50)
            smat = mat if (fresh() or rng.random() < 0.7) else (BARK_D, PLANK_W, BARK)[int(rng.integers(0, 3))]
            xi = x
            while xi < x + seg - 1 and xi < HALF + 12:
                dx = xi - hole_c[0]
                dt = t - hole_c[1]
                d = math.hypot(dx / 13.0, dt / 0.16) + (fbm(xi * 0.2, r * 3.0, 4) - 0.5) * 0.5
                droop = -2.0 * math.sin((xi + HALF + 12) / (2 * HALF + 24) * math.pi) * (0.25 if fresh() else 1.0)
                if d > 1.0:
                    p = base + V(xi, sag + droop * 0.3, 0) + normal * 0.0
                    m.ell(p, (3.2, 1.0, 2.6), smat, R=h.rot_x(roof_a))
                xi += 1.5
            x += seg
    # the roof's boards as slabs would show edges; add the lit lower edge of each row as a thin ledge
    for r in range(rows + 1):
        t = r / rows
        base = eave + slope * t
        for xi in np.arange(-HALF - 12, HALF + 12, 2.5):
            dx, dt = xi - hole_c[0], t - hole_c[1]
            if math.hypot(dx / 13.0, dt / 0.16) > 1.05 and rng.random() < 0.6:
                m.ell(base + V(xi, -1.3, 0.7), (1.8, 0.6, 0.7), ROOF, R=h.rot_x(roof_a))
    if not fresh():
        m.ell(V(hole_c[0], 73.0, -6.0), (11.0, 4.2, 0.8), GAP)  # the hole shows the dark inside
    for k in range(0 if fresh() else 14):  # splinters round the hole
        a = k / 14 * math.tau
        p = V(hole_c[0] + math.cos(a) * 12.5, 73.0 + math.sin(a) * 5.0 + 1.0, -4.0 + math.sin(a) * 2.0)
        m.ell(p, (0.8, rng.uniform(1.6, 3.4), 0.6), BARK_D, R=h.rot_x(rng.uniform(-0.8, 0.8)))
    # the ridge beam, heavy, with ends sticking out
    log(m, V(-HALF - 14, 82.8, -26), V(HALF + 14, 82.8, -26), 3.6, BARK if fresh() else BARK_D, step=1.4)
    # moss over the roof, thick on the north-east side
    for _ in range(0 if fresh() else 150):
        t = rng.uniform(0.0, 1.0)
        xx = rng.uniform(-HALF - 10, HALF + 10)
        if math.hypot((xx - hole_c[0]) / 15.0, (t - hole_c[1]) / 0.2) < 1.0:
            continue
        p = eave + slope * t + V(xx, 0.6, 0.6)
        m.ell(p, (rng.uniform(2.5, 7), 0.8, rng.uniform(1.4, 3.4)), MOSS_L if rng.random() < 0.3 else MOSS)
    for _ in range(0 if fresh() else 38):  # hanging moss from the eaves
        xx = rng.uniform(-HALF - 8, HALF + 8)
        ln = rng.uniform(4, 13)
        m.limb(eave + V(xx, 0.0, 1.2), eave + V(xx + rng.uniform(-0.6, 0.6), -ln, 1.6), 0.5, 0.15, MOSS)
    # the chimney: crooked, of stones, soot at the top, a violet crack, teal fungi at its foot
    for k in range(44):
        y = 64.0 + k * 1.2
        px = -40.0 + 0.09 * (y - 64.0)
        for j in range(4):
            m.ell((px + rng.uniform(-6.5, 6.5), y + rng.uniform(-0.3, 0.3), -14.0 + rng.uniform(-4.5, 4.5)), (rng.uniform(2.8, 4.8), 2.3, rng.uniform(2.6, 4.4)), (STONE, STONE_L, STONE)[int(rng.integers(0, 3))])
    m.ell((-36.0, 117.0, -14.0), (9.0, 1.8, 7.4), STONE_L)
    m.ell((-36.0, 118.6, -14.0), (5.4, 0.6, 4.2), GAP)
    for k in range(0 if fresh() else 5):
        m.ell((-36.0 + rng.uniform(-6, 6), 78 + k * 7, -9.0 + rng.uniform(-1, 3)), (rng.uniform(2, 4), 0.9, 1.6), MOSS_L if k % 2 else MOSS)
    p = V(-38.0, 78.0, -9.0)
    for s_ in range(0 if fresh() else 12):
        q = p + V(rng.uniform(-0.5, 0.8), rng.uniform(1.5, 2.6), 0)
        m.limb(p, q, 0.28, 0.24, h.VIOLET, kind="emit")
        p = q
    # ivy over the left corner and up, roots at the foot, glowing mushrooms by the door, a woodpile on the right, a lantern on a hook
    for k in range(0 if fresh() else 6):
        ivy(m, V(-HALF + 2 + k * 1.8, rng.uniform(46, 66), 5.4 + k * 0.1), rng.uniform(30, 58), rng, glow_every=4, sway=0.7)
    for k in range(0 if fresh() else 5):
        base = V(-HALF + 2 + k * 26.0, 2.5, 7.0)
        p = base.copy()
        a = rng.uniform(0, math.tau)
        for s in range(6):
            q = p + V(math.cos(a) * 2.0 + rng.uniform(-0.6, 0.6), -0.1, 1.0 + abs(math.sin(a)) * 0.8)
            m.limb(p, q, max(2.0 - s * 0.28, 0.4), max(1.8 - s * 0.28, 0.35), BARK)
            p = q
    for k in range(0 if fresh() else 6):
        mx = 22.0 + k * 4.4
        m.ell((mx, 3.0, 8.0 + k % 2), (1.4, 1.2, 1.4), LINEN)
        m.ell((mx, 5.2 + (k % 2) * 0.6, 8.0 + k % 2), (2.8 - 0.2 * k % 1, 1.1, 2.4), h.TEAL, kind="emit")
    for k in range(12):
        log(m, V(HALF - 4 + (k % 4) * 4.2, 3 + (k // 4) * 4.2, 9), V(HALF - 4 + (k % 4) * 4.2 + 0.4, 3 + (k // 4) * 4.2, 1), 2.1, (BARK, PLANK_W, BARK_D)[k % 3], step=1.1)
    if not fresh():
        m.ell((HALF + 2, 14.0, 10.0), (9.0, 1.2, 2.2), MOSS_L)
    # the lantern on an iron hook beside the door
    m.limb(V(-22, 42, 3.5), V(-22, 42, 11.0), 0.5, 0.45, IRON)
    m.limb(V(-22, 42, 11.0), V(-22, 37, 11.0), 0.4, 0.35, IRON)
    m.ell((-22, 32.5, 11.0), (2.8, 4.0, 2.8), h.TEAL, kind="emit")
    for k in range(4):
        a = k * 1.57 + 0.78
        log(m, V(-22 + math.cos(a) * 3.0, 28.0, 11.0 + math.sin(a) * 3.0), V(-22 + math.cos(a) * 3.0, 37.0, 11.0 + math.sin(a) * 3.0), 0.45, IRON, step=0.9)
    arr = to_array(render(m, FW, FH, GROUND))
    arr = grain(arr, 11, along=(1.0, 0.0), amount=0.7)
    arr = roof_pass(arr, 11, shadow=6, moss=0.0 if fresh() else 0.5)
    arr, box = window_pass(arr, 11, dim=0.0 if fresh() else 0.14)
    global WINDOW_BOX
    WINDOW_BOX = box
    arr = wall_depth(arr, (24, 186, 99, GROUND - 3), 11, dark=GAP)
    return soft_shadow(arr, FW / 2, GROUND + 4, 74, 9, 70), GROUND


def vane_arr():
    """A small iron weathervane for the renewed roof ridge (24 x 30, the mast's foot at the bottom middle): mast, a cross of compass arms, a gilt ball and a long arrow with
    a fletched tail that points east. Hand-placed pixels with the iron ramp; Hut mirrors it with the wind."""
    ramp = [tuple(c[:3]) for c in h.RAMPS[IRON]]
    ink = (20, 14, 30)
    arr = np.zeros((30, 24, 4), np.uint8)

    def px(x, y, band):
        if 0 <= x < 24 and 0 <= y < 30:
            arr[y, x] = (*(ink if band < 0 else ramp[band]), 255)

    for y in range(14, 28):  # the mast: a lit left edge, a dark right edge
        px(11, y, 3 if y % 5 else 2)
        px(12, y, 1)
        px(10, y, -1)
        px(13, y, -1)
    for x in range(7, 17):  # the compass arms
        px(x, 17, 2 if x < 12 else 1)
        px(x, 16, -1)
        px(x, 18, -1)
    for x, y in ((6, 16), (6, 17), (6, 18), (17, 16), (17, 17), (17, 18)):
        px(x, y, 1)
    for dy in range(-1, 2):  # the gilt ball on the mast
        for dx in range(-1, 2):
            if abs(dx) + abs(dy) < 3:
                arr[12 + dy, 11 + dx] = (212, 188, 120, 255) if (dx <= 0 and dy <= 0) else (160, 136, 68, 255)
    for x in range(3, 21):  # the arrow's shaft
        px(x, 8, 3 if x < 12 else 2)
        px(x, 9, 1)
        px(x, 7, -1)
        px(x, 10, -1)
    for k in range(5):  # the head
        for dy in range(-(4 - k), 5 - k):
            px(17 + k, 8 + dy, 2 if dy < 0 else 1)
    for k in range(5):  # the fletching: two fins fanning out behind
        px(3 + k, 8 - 1 - k, 2)
        px(3 + k, 9 + 1 + k, 1)
        px(4 + k, 8 - 1 - k, 3 if k < 3 else 2)
        px(4 + k, 9 + 1 + k, 1)
    return arr
