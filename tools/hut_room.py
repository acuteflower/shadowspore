"""The room of the hut: the plank floor (seen from straight above like the world's ground), the back wall of logs with its windows, the tops of the side
walls, the front lip with the doorway, and the door. Built from ellipsoids like the trunks and the signpost, see hut_lib."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *

FLOOR_W, FLOOR_H = 400, 224  # px
WALL_H = 58  # px of the back wall's face
SIDE_W = 16
TOP_PAD = 14  # room above the back wall's top edge in the shell picture (the beam, the cap)
SHELL_W = FLOOR_W + 2 * SIDE_W
BACK_Y = TOP_PAD + WALL_H  # where the back wall meets the floor, in shell pixels
LIP_H = 36

# holes in the floor (px from the floor's top left: cx, cy, rx, ry)
HOLES = [(66, 124, 17, 13), (170, 46, 11, 9), (262, 168, 24, 17), (338, 90, 15, 11), (34, 204, 11, 9), (386, 40, 13, 10)]
SAPLING_AT = (262, 168)  # the hole the young tree grows from
DAMP = (400, 0)  # the damp corner (north east)
WINDOWS_PX = [(SIDE_W + 100, 50.0, 12.0, 34.0), (SIDE_W + 310, 46.0, 12.0, 34.0)]  # window centres from the shell's left (px), width (units), y0, y1
HOLE_WALL = (SIDE_W + 365, 14.0, 10.0, 40.0)  # the hole to the forest in the back wall: centre px, half width, y0, y1 (None = no hole)
PILASTERS_PX = (SIDE_W + 130, SIDE_W + 268)
DOOR_GAP = (296, 344)  # the doorway in the front lip (shell px)
HEARTH_RECTS = [(226, 0, 318, 28), (294, 202, 346, 224)]  # flagstones on the floor (floor px)
HEARTH_AT = (272, 14)  # where the floor is scorched


def configure(floor=None, holes=None, sapling=None, damp=None, windows=None, hole_wall="keep", pilasters=None, door_gap=None, hearth=None, hearth_at=None):
    """Re-sizes the room for another interior (the lumberjack's cabin) and returns nothing: the functions read these module values when they are called."""
    global FLOOR_W, FLOOR_H, SHELL_W, BACK_Y, HOLES, SAPLING_AT, DAMP, WINDOWS_PX, HOLE_WALL, PILASTERS_PX, DOOR_GAP, HEARTH_RECTS, HEARTH_AT
    if floor:
        FLOOR_W, FLOOR_H = floor
        SHELL_W = FLOOR_W + 2 * SIDE_W
    if holes is not None:
        HOLES = holes
    if sapling is not None:
        SAPLING_AT = sapling
    if damp is not None:
        DAMP = damp
    if windows is not None:
        WINDOWS_PX = windows
    if hole_wall != "keep":
        HOLE_WALL = hole_wall
    if pilasters is not None:
        PILASTERS_PX = pilasters
    if door_gap is not None:
        DOOR_GAP = door_gap
    if hearth is not None:
        HEARTH_RECTS = hearth
    if hearth_at is not None:
        HEARTH_AT = hearth_at


def _px_to_units(cx, cy):
    return (cx - FLOOR_W / 2.0) * U, (cy - FLOOR_H / 2.0) * U


def floor_arr(seed=5):
    rng = rng_for(seed)
    m = h.Model()
    W, D = FLOOR_W * U, FLOOR_H * U
    m.ell((0, -2.4, 0), (W / 2 + 6, 1.0, D / 2 + 6), GAP)
    holes = [] if fresh() else [(*_px_to_units(cx, cy), rx * U, ry * U) for cx, cy, rx, ry in HOLES]

    def in_hole(x, z):
        for cx, cz, rx, rz in holes:
            d = math.hypot((x - cx) / rx, (z - cz) / rz) + (fbm(x * 0.12, z * 0.12, 31) - 0.5) * 0.55
            if d < 1.0:
                return True
        return False

    def damp(x, z):
        if fresh():
            return 0.0
        px, py = x / U + FLOOR_W / 2.0, z / U + FLOOR_H / 2.0
        corner = max(0.0, 1.0 - math.hypot((px - DAMP[0]) / 160.0, (py - DAMP[1]) / 100.0))
        near = max((max(0.0, 1.0 - math.hypot((x - cx) / (rx * 2.2), (z - cz) / (rz * 2.2))) for cx, cz, rx, rz in holes), default=0.0)
        return min(1.0, corner * 0.9 + near * 0.8)

    rows = int(D / 10.4)
    pitch = D / rows
    for r in range(rows):
        zc = -D / 2 + pitch * (r + 0.5)
        x0 = -W / 2 - rng.uniform(0, 60)
        while x0 < W / 2:
            length = rng.uniform(62, 150)
            x1 = x0 + length
            d_here = damp((x0 + x1) / 2, zc)
            roll = rng.random()
            mat = (BARK if roll < 0.3 else (PLANK_W if roll < 0.66 else PLANK)) if fresh() else (BARK_D if roll < 0.1 + 0.35 * d_here else (BARK if roll < 0.48 else (PLANK_W if roll < 0.78 else PLANK)))
            y_off = rng.uniform(-0.3, 0.35)
            bow = rng.uniform(-0.5, 0.5)
            tilt = rng.uniform(-0.012, 0.012)
            xi = max(x0, -W / 2 - 3)
            while xi < min(x1 - 0.8, W / 2 + 3):
                t = (xi - x0) / length
                z = zc + bow * math.sin(math.pi * t) + tilt * (xi - x0)
                if not in_hole(xi, z):
                    m.ell((xi, 1.0 + y_off, z), (3.2, 1.8, 4.7), mat)
                xi += 1.3
            if min(x1, W / 2) - max(x0, -W / 2) > 12:  # nails at the ends, a knot, a crack, moss
                for nx in (x0 + 4.0, x1 - 4.0):
                    if -W / 2 < nx < W / 2 and not in_hole(nx, zc):
                        for dz in (-1.8, 1.8):
                            m.ell((nx, 2.4 + y_off, zc + dz), (0.55, 0.4, 0.55), IRON)
                if rng.random() < 0.55:
                    kx = rng.uniform(x0 + 12, x1 - 12)
                    if -W / 2 < kx < W / 2 and not in_hole(kx, zc):
                        m.ell((kx, 2.55 + y_off, zc + rng.uniform(-1.5, 1.5)), (1.7, 0.45, 1.25), BARK_D)
                        m.ell((kx, 2.75 + y_off, zc), (0.8, 0.3, 0.55), mat)
                if rng.random() < 0.6 and not fresh():
                    cx_ = rng.uniform(x0 + 8, x1 - 8)
                    ang = rng.uniform(-0.25, 0.25)
                    ln = rng.uniform(8, 22)
                    if -W / 2 < cx_ < W / 2 and not in_hole(cx_, zc):
                        m.limb(V(cx_, 2.6 + y_off, zc + rng.uniform(-2, 2)), V(cx_ + math.cos(ang) * ln, 2.6 + y_off, zc + math.sin(ang) * ln * 0.3), 0.2, 0.12, GAP)
            x0 = x1 + 0.9
    # moss on the boards, thick where it is damp
    for _ in range(0 if fresh() else 420):
        x = rng.uniform(-W / 2, W / 2)
        z = rng.uniform(-D / 2, D / 2)
        if rng.random() < damp(x, z) * 1.15 and not in_hole(x, z):
            m.ell((x, 2.7, z), (rng.uniform(2, 6), 0.7, rng.uniform(1.4, 3.6)), MOSS_L if rng.random() < 0.5 else MOSS)
    # the holes: soil, tufts of grass, small stones, splintered rims
    for hi, (cx, cz, rx, rz) in enumerate(holes):
        m.ell((cx, -0.9, cz), (rx * 1.0, 1.2, rz * 1.0), SOIL)
        for _ in range(int(rx * 0.9)):
            a = rng.uniform(0, math.tau)
            d = math.sqrt(rng.random()) * 0.8
            tuft(m, V(cx + math.cos(a) * rx * d, 0.2, cz + math.sin(a) * rz * d), rng, blades=5, height=rng.uniform(3, 6.5))
        for _ in range(3):
            a = rng.uniform(0, math.tau)
            m.ell((cx + math.cos(a) * rx * 0.6, 0.6, cz + math.sin(a) * rz * 0.6), (rng.uniform(1, 2.2), rng.uniform(0.7, 1.3), rng.uniform(1, 2)), STONE)
        for k in range(int(rx * 1.5)):  # splinters round the rim
            a = k / (rx * 1.5) * math.tau + rng.uniform(-0.1, 0.1)
            px, pz = cx + math.cos(a) * rx * 1.04, cz + math.sin(a) * rz * 1.04
            R = h.rot_x(-math.sin(a) * rng.uniform(0.5, 1.0)) @ h.rot_y(rng.uniform(-0.4, 0.4))
            m.ell((px, 2.4, pz), (0.8, rng.uniform(2.0, 4.0), 0.6), BARK_D if rng.random() < 0.4 else PLANK_W, R=R)
    # a root crawling across the floor from the sapling's hole, with a violet vein
    sx, sz = _px_to_units(*SAPLING_AT)
    for k, ang in enumerate(() if fresh() else (2.9, 3.6, 0.1)):
        p = V(sx, 1.4, sz)
        for step in range(16):
            ang += rng.uniform(-0.25, 0.25)
            q = p + V(math.cos(ang) * 4.5, 0.0, math.sin(ang) * 3.2)
            q[1] = 1.9 + 0.3 * math.sin(step)
            rad = 1.5 * (1.0 - step / 18.0)
            m.limb(p, q, rad, max(rad * 0.85, 0.35), BARK)
            if step % 3 == 0:
                m.limb(p + V(0, rad * 0.7, 0), q + V(0, rad * 0.7, 0), 0.2, 0.18, h.VIOLET, kind="emit")
            p = q
    # the hearth: flagstones in front of the fireplace (px 230..314, y 0..26) and the threshold of the door (296..344, y 204..224)
    for (x0, y0, x1, y1) in HEARTH_RECTS:
        sx0, sz0 = _px_to_units(x0, y0)
        sx1, sz1 = _px_to_units(x1, y1)
        cxx = sx0
        while cxx < sx1 - 3:
            wd = rng.uniform(7, 12)
            czz = sz0
            while czz < sz1 - 2:
                hd = rng.uniform(5, 8)
                m.ell((cxx + wd / 2, 2.0 if fresh() else 1.2, czz + hd / 2), (wd / 2 * (1.04 if fresh() else 0.95), 1.7, hd / 2 * (1.04 if fresh() else 0.95)), STONE_L if rng.random() < 0.55 else STONE)
                czz += hd
            cxx += wd
    arr = to_array(render(m, FLOOR_W, FLOOR_H, FLOOR_H // 2, pitch=90.0, light=(-0.5, 0.72, -0.5)))
    arr = grain(arr, 4, along=(1.0, 0.0), amount=0.6)
    def stain(x, y):
        burn = max(0.0, 1.0 - math.hypot((x - HEARTH_AT[0]) / 38.0, (y - HEARTH_AT[1]) / 18.0))
        wet = fbm(x * 0.045, y * 0.05, 19)
        ao = max(0.0, 1.0 - y / 12.0) * 0.8 + max(0.0, 1.0 - x / 8.0) * 0.5 + max(0.0, 1.0 - (FLOOR_W - 1 - x) / 8.0) * 0.5
        if fresh():
            return max(0.0, burn - 0.4) * 0.9 + ao * 0.7
        return max(0.0, burn - 0.15) * 1.4 + (0.55 if wet > 0.66 else 0.0) + ao
    return tint_region(arr, stain, 3)


def _wall_logs(m, rng, x0, x1, y_levels, r_log, cut_fn, mat_fn, windows):
    """Horizontal logs from x0 to x1 at the given heights; `cut_fn(x, y)` True where the wall is open (a window, a hole)."""
    for li, y in enumerate(y_levels):
        mat = mat_fn(li)
        x = x0
        wob = rng.uniform(0, 6)
        while x <= x1:
            if not cut_fn(x, y):
                r = r_log * (1.0 + 0.07 * math.sin(x * 0.09 + li * 2.0) + 0.05 * math.sin(x * 0.33 + li))
                m.ell((x, y + 0.5 * math.sin(x * 0.04 + wob), 0.0), (3.1, r, r), mat)
            x += 1.4
        # grooves and a violet vein along some logs
        for g in range(3):
            ang = rng.uniform(0.2, 1.4)
            gx0 = rng.uniform(x0, x1 - 60)
            gx1 = gx0 + rng.uniform(40, 120)
            segs = 0
            gx = gx0
            while gx < min(gx1, x1):
                if not cut_fn(gx, y):
                    m.limb(V(gx, y + math.cos(ang) * r_log * 0.97, math.sin(ang) * r_log * 0.97), V(gx + 4, y + math.cos(ang) * r_log * 0.97, math.sin(ang) * r_log * 0.97), 0.3, 0.26, BARK_D)
                gx += 4
        if rng.random() < 0.6 and not fresh():
            vx0 = rng.uniform(x0 + 20, x1 - 100)
            p = V(vx0, y + r_log * 0.55, r_log * 0.8)
            for s in range(14):
                q = p + V(rng.uniform(3, 6), rng.uniform(-1.0, 1.0), 0)
                if not cut_fn(q[0], y):
                    m.limb(p, q, 0.3, 0.26, h.VIOLET, kind="emit")
                p = q


def back_wall_arr(seed=7):
    """The back wall seen from the front, 432 wide: logs (7 high), corner posts, two windows (one with a broken shutter, curtain remnants), a hole to the
    forest, the beam on top with roots and moss hanging from it, ivy, shelf fungi."""
    rng = rng_for(seed)
    m = h.Model()
    W = SHELL_W * U
    x0, x1 = -W / 2 + 6, W / 2 - 6
    r_log = 4.9
    levels = [r_log + i * 8.8 for i in range(7)]
    win = [(-W / 2 + px * U, w, ya, yb) for px, w, ya, yb in WINDOWS_PX]  # cx, width, y0, y1
    hole_cfg = None if fresh() else HOLE_WALL
    hole = (-W / 2 + hole_cfg[0] * U, hole_cfg[1], hole_cfg[2], hole_cfg[3]) if hole_cfg else (-1.0e4, 1.0, 0.0, 1.0)  # cx, rx, y0, y1

    def cut(x, y):
        for cx, w, ya, yb in win:
            if abs(x - cx) < w / 2 and ya < y < yb:
                return True
        d = math.hypot((x - hole[0]) / hole[1], (y - (hole[2] + hole[3]) / 2) / ((hole[3] - hole[2]) / 2)) + (fbm(x * 0.2, y * 0.2, 5) - 0.5) * 0.5
        return d < 1.0

    # the sky behind the openings
    for cx, w, ya, yb in win:
        m.ell((cx, (ya + yb) / 2, -6.0), (w / 2 + 2, (yb - ya) / 2 + 2, 0.6), SKY)
    m.ell((hole[0], (hole[2] + hole[3]) / 2, -6.0), (hole[1] + 3, (hole[3] - hole[2]) / 2 + 3, 0.6), SKY)
    for cx, w, ya, yb in win + [(hole[0], hole[1] * 2, hole[2], hole[3])]:  # tree crowns and a branch in front of the sky
        for _ in range(9):
            m.ell((cx + rng.uniform(-w / 2, w / 2), rng.uniform(ya, yb), -5.0), (rng.uniform(3, 6), rng.uniform(2, 4.5), 0.7), MOSS if rng.random() < 0.7 else MOSS_L)
        m.limb(V(cx - w / 2, ya + 3, -5.2), V(cx + w / 3, yb - 3, -5.2), 0.9, 0.5, BARK_D)
    mats = [BARK, PLANK_W, BARK, BARK_D, PLANK_W, BARK, BARK_D]
    _wall_logs(m, rng, x0, x1, levels, r_log, cut, lambda i: mats[i % len(mats)], win)
    # corner posts and two pilasters: vertical logs standing proud
    for px in (x0 + 4, x1 - 4) + tuple(-W / 2 + p * U for p in PILASTERS_PX):
        log(m, V(px, 0, 4.0), V(px, 66, 4.0), 3.6, BARK_D if abs(px) > W / 2 - 20 else BARK, step=1.4)
        for k in range(5):
            m.ell((px + rng.uniform(-0.6, 0.6), 6 + k * 12 + rng.uniform(-2, 2), 7.4), (1.2, 0.6, 0.5), IRON)
    # window frames and shutters
    for wi, (cx, w, ya, yb) in enumerate(win):
        for dy in (ya - 1.5, yb + 1.5):
            slab(m, V(cx - w / 2 - 3, dy, 5.2), V(cx + w / 2 + 3, dy, 5.2), 1.7, 0.9, PLANK_W, (0, 0, 1))
        for dx in (cx - w / 2 - 1.5, cx + w / 2 + 1.5):
            slab(m, V(dx, ya - 1, 5.2), V(dx, yb + 1, 5.2), 1.5, 0.9, PLANK_W, (0, 0, 1))
        if fresh():  # two whole shutters folded back against the wall, a valance and two curtains tied back
            for sx in (-1, 1):
                slab(m, V(cx + sx * (w / 2 + 9.0), ya - 1, 6.0), V(cx + sx * (w / 2 + 9.0), yb + 1, 6.0), 5.8, 0.9, BARK_D if sx < 0 else BARK, (0, 0, 1))
                for yy in (ya + 4, yb - 4):
                    slab(m, V(cx + sx * (w / 2 + 3.4), yy, 7.0), V(cx + sx * (w / 2 + 14.6), yy, 7.0), 0.7, 0.5, IRON, (0, 0, 1))
            slab(m, V(cx - w / 2 - 1, yb - 2.5, 6.6), V(cx + w / 2 + 1, yb - 2.5, 6.6), 2.6, 0.9, LINEN, (0, 0, 1))
            for sx in (-1, 1):
                m.limb(V(cx + sx * (w / 2 - 2), yb - 4, 6.8), V(cx + sx * (w / 2 - 1), yb - 17, 6.9), 2.6, 1.5, LINEN)
        elif wi == 0:  # a broken shutter hanging from one hinge
            for k in range(4):
                a0 = V(cx + w / 2 + 1.5 + k * 3.0, yb - 1 - k * 0.8, 6.0 + k * 0.3)
                slab(m, a0, a0 + V(1.0 * k, -(20 - k * 3.0), 0.7), 1.5, 0.8, BARK_D if k % 2 else PLANK_W, (0, 0, 1))
        else:  # tattered curtain
            for k in range(7):
                top = V(cx - w / 2 + 3 + k * 6.2, yb - 0.5, 6.4)
                ln = rng.uniform(10, 24)
                m.limb(top, top + V(rng.uniform(-1.2, 1.2), -ln, 0.6), 1.6, 0.8, LINEN)
        # ivy and a root hanging into the window
        if not fresh():
            ivy(m, V(cx + rng.uniform(-w / 3, w / 3), yb + 1, 6.6), 18, rng, glow_every=4)
    # the hole to the forest: splintered log ends and ferns against the light
    hx, hrx, hy0, hy1 = hole
    for k in range(0 if fresh() else 18):
        a = k / 18 * math.tau
        px = hx + math.cos(a) * (hrx + 1.0)
        py = (hy0 + hy1) / 2 + math.sin(a) * ((hy1 - hy0) / 2 + 1.0)
        R = h.rot_x(rng.uniform(-0.7, 0.7)) @ h.rot_y(rng.uniform(-0.5, 0.5))
        m.ell((px, py, 4.0), (0.9, rng.uniform(2.2, 4.5), 0.8), BARK_D if k % 2 else PLANK_W, R=R)
    for k in range(0 if fresh() else 7):
        base = V(hx - 8 + k * 2.6, hy0 + 1.0, 2.0)
        for f in range(3):
            tip = base + V(rng.uniform(-3, 3), rng.uniform(9, 20), rng.uniform(0.5, 2.0))
            m.limb(base, tip, 0.45, 0.18, MOSS_L)
    # the beam on top: a heavy rotten log with roots, moss and glowing fungi hanging from it
    log(m, V(x0 - 2, 66.5, 3.0), V(x1 + 2, 66.5, 3.0), 4.6, BARK if fresh() else BARK_D, step=1.5)
    for k in range(0 if fresh() else 40):
        bx = rng.uniform(x0 + 4, x1 - 4)
        m.ell((bx, 70.0, 2.0), (rng.uniform(2, 5), 1.1, rng.uniform(1.5, 3)), MOSS_L if rng.random() < 0.6 else MOSS)
    for k in range(0 if fresh() else 22):  # hanging moss
        bx = rng.uniform(x0 + 6, x1 - 6)
        ln = rng.uniform(5, 16)
        m.limb(V(bx, 63.5, 6.8), V(bx + rng.uniform(-0.8, 0.8), 63.5 - ln, 7.0), 0.55, 0.15, MOSS)
    for k in range(0 if fresh() else 5):  # roots through the roof, down the wall
        bx = rng.uniform(x0 + 20, x1 - 20)
        p = V(bx, 64.0, 6.5)
        for s in range(int(rng.uniform(10, 24))):
            q = p + V(rng.uniform(-1.4, 1.4) + 0.4 * math.sin(s * 0.5), -2.0, rng.uniform(-0.1, 0.2))
            m.limb(p, q, max(0.9 - s * 0.03, 0.3), max(0.8 - s * 0.03, 0.25), BARK)
            if s % 3 == 0:
                m.limb(p + V(0.4, 0, 0.7), q + V(0.4, 0, 0.7), 0.15, 0.14, h.VIOLET, kind="emit")
            p = q
    # moss on top of the logs and creeping up from below, ivy strands, shelf fungi (teal) low down
    for _ in range(0 if fresh() else 150):
        x = rng.uniform(x0, x1)
        y = levels[int(rng.integers(0, 7))] + r_log * rng.uniform(0.6, 1.0)
        if not cut(x, y):
            m.ell((x, y, r_log * 0.55), (rng.uniform(2, 6), 1.0, rng.uniform(1.5, 3.2)), MOSS_L if rng.random() < 0.5 else MOSS)
    for _ in range(0 if fresh() else 12):
        sx = rng.uniform(x0 + 10, x1 - 10)
        if not cut(sx, 40):
            ivy(m, V(sx, rng.uniform(40, 62), 5.6), rng.uniform(14, 40), rng, glow_every=5)
    for _ in range(0 if fresh() else 9):
        fx = rng.uniform(x0 + 20, x1 - 20)
        fy = rng.uniform(3, 20)
        if not cut(fx, fy):
            for k in range(3):
                m.ell((fx + k * 3.2, fy + 1.0 - k * 1.2, 5.4 + k * 0.5), (2.6 - k * 0.5, 0.9, 1.7 - k * 0.3), h.TEAL, kind="emit")
                m.ell((fx + k * 3.2, fy - 0.2 - k * 1.2, 5.2 + k * 0.5), (2.2 - k * 0.45, 0.5, 1.4 - k * 0.3), LINEN)
    fh = TOP_PAD + WALL_H + 4
    arr = to_array(render(m, SHELL_W, fh, BACK_Y))
    arr = grain(arr, 8, along=(1.0, 0.0), amount=0.7)
    return arr


def side_arr(seed=3):
    """The top of a side wall seen from above (16 x tall): two rows of log tops with notches, moss, ivy and a glowing fungus; used mirrored on both sides."""
    rng = rng_for(seed)
    m = h.Model()
    height = BACK_Y + FLOOR_H + 6
    for k, x in enumerate((-4.4, 4.4)):
        log(m, V(x, 0, (-height / 2 + 2) * U), V(x, 0, (height / 2 - 2) * U), 4.6, BARK if k == 0 else BARK_D, step=1.4)
    for _ in range(0 if fresh() else 26):  # notches where the cross logs lie, moss, cracks
        z = rng.uniform(-height / 2, height / 2) * U
        m.ell((rng.uniform(-6, 6), 3.2, z), (rng.uniform(2, 4.5), 1.0, rng.uniform(1.5, 3.4)), MOSS_L if rng.random() < 0.5 else MOSS)
    for k in range(int(height / 28)):
        z = (-height / 2 + 10 + k * 28 + rng.uniform(-3, 3)) * U
        log(m, V(-8.6, 1.0, z), V(8.6, 1.0, z), 1.7, BARK if fresh() else BARK_D, step=1.2)
    for _ in range(0 if fresh() else 3):
        z = rng.uniform(-height / 2 + 20, height / 2 - 20) * U
        m.ell((rng.uniform(-4, 4), 3.4, z), (1.6, 0.8, 1.2), h.TEAL, kind="emit")
    arr = to_array(render(m, SIDE_W, height, height // 2, pitch=90.0, light=(-0.5, 0.72, -0.5)))
    return grain(arr, 12, along=(0.0, 1.0), amount=0.6)


def front_arr(seed=9):
    """The south wall with the doorway (x 296..344 in shell pixels): its top, lit, and its outer face of logs, a stone threshold, moss."""
    rng = rng_for(seed)
    m = h.Model()
    W = SHELL_W * U
    gap0 = (-W / 2 + DOOR_GAP[0] * U, -W / 2 + DOOR_GAP[1] * U)
    for li, y in enumerate((4.6, 13.2, 21.8)):
        x = -W / 2 + 2
        mat = (BARK_D, BARK, PLANK_W)[li % 3]
        while x < W / 2 - 2:
            if not (gap0[0] - 4 < x < gap0[1] + 4):
                r = 4.7 * (1.0 + 0.06 * math.sin(x * 0.11 + li))
                m.ell((x, y, 0), (3.1, r, r), mat)
            x += 1.4
    for px in (gap0[0] - 4, gap0[1] + 4):  # door posts
        log(m, V(px, 0, 1.0), V(px, 33, 1.0), 4.0, BARK_D, step=1.4)
    log(m, V(gap0[0] - 6, 31.5, 1.0), V(gap0[1] + 6, 31.5, 1.0), 3.0, BARK, step=1.4)  # the lintel
    x = gap0[0] + 2
    while x < gap0[1] - 2:  # the threshold stone
        m.ell((x + 4, 1.0, 5.0), (5.0, 1.6, 4.0), STONE_L if rng.random() < 0.5 else STONE)
        x += 8
    for _ in range(0 if fresh() else 90):
        x = rng.uniform(-W / 2 + 4, W / 2 - 4)
        if not (gap0[0] - 8 < x < gap0[1] + 8):
            m.ell((x, rng.uniform(3, 27), 4.6), (rng.uniform(2, 5), 1.0, rng.uniform(1.2, 2.6)), MOSS_L if rng.random() < 0.5 else MOSS)
    for _ in range(0 if fresh() else 8):
        x = rng.uniform(-W / 2 + 10, W / 2 - 10)
        if not (gap0[0] - 8 < x < gap0[1] + 8):
            ivy(m, V(x, 28, 5.2), rng.uniform(10, 24), rng, glow_every=5)
    arr = to_array(render(m, SHELL_W, LIP_H, LIP_H - 4))
    return grain(arr, 14, along=(1.0, 0.0), amount=0.6)


def door_arr(width=48, height=40, seed=21, strap_rows=(0.22, 0.72)):
    """A door leaf seen from the front: vertical boards of different woods, iron straps with rivets, a latch, a violet crack, knots, a broken corner, moss."""
    rng = rng_for(seed)
    m = h.Model()
    W, H = width * U, height * U
    n = max(4, int(width / 7))
    bw = W / n
    for i in range(n):
        x = -W / 2 + bw * (i + 0.5)
        mat = (BARK, PLANK_W, BARK_D, PLANK)[int(rng.integers(0, 4))]
        top = H - rng.uniform(0, 2.5)
        if i == n - 1 and not fresh():
            top = H * 0.62  # the broken corner
        slab(m, V(x, 1.0, 0), V(x + rng.uniform(-0.4, 0.4), top, 0), bw / 2 - 0.25, 1.9, mat, (0, 0, 1), step=1.3)
        if rng.random() < 0.5 and not fresh():
            ky = rng.uniform(8, top - 6)
            m.ell((x, ky, 1.9), (1.4, 1.1, 0.5), BARK_D)
    for frac in strap_rows:
        y = H * frac
        slab(m, V(-W / 2, y, 2.1), V(W / 2, y, 2.1), 1.9, 0.6, IRON, (0, 0, 1), step=1.3)
        for k in range(n + 1):
            m.ell((-W / 2 + k * (W / n), y, 2.8), (0.55, 0.55, 0.4), IRON)
    m.ell((W * 0.28, H * 0.5, 3.0), (1.7, 1.2, 0.6), IRON)  # the latch
    m.ell((W * 0.28, H * 0.5, 3.4), (0.7, 0.5, 0.3), h.GOLD)
    p = V(-W * 0.1, H * 0.35, 2.3)
    for s in range(0 if fresh() else 10):  # a violet crack
        q = p + V(rng.uniform(-1.0, 1.0), rng.uniform(1.0, 2.2), 0)
        m.limb(p, q, 0.28, 0.24, h.VIOLET, kind="emit")
        p = q
    for _ in range(0 if fresh() else 14):
        m.ell((rng.uniform(-W / 2, W / 2), rng.uniform(1, 9), 2.4), (rng.uniform(1.5, 3.5), 0.8, 1.0), MOSS_L if rng.random() < 0.5 else MOSS)
    arr = to_array(render(m, width + 8, height + 8, height + 4))
    return grain(arr, 5, along=(0.0, 1.0), amount=0.6)
