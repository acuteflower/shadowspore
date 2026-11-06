#!/usr/bin/env python3
"""The lumberjack's cabin (needs numpy): a small, old, overgrown log cabin far north of the knight's hut, its forecourt, the board that lies across its door and its
dusty room. Made exactly like the hut (hut_lib / hut_room / hut_props, the trees' ellipsoid renderer): violet-plum bark, moss, ivy, teal fungi, violet veins; but smaller,
older (a collapsed corner of the roof with a sapling growing out of it, a boarded window, a toppled chimney, no light inside) and thick with dust.
    python3 tools/art_cabin.py [preview.png]      writes assets/interior/cabin/*.png (+ _glow sheets with only the emissive pixels) and, with an argument, previews
Positions are in data/interiors.json "cabin" and data/ground.json huts[] (id cabin); the body of the lumberjack is tools/art_lumberjack.py."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_fx as fx  # noqa: E402
import hut_props as props  # noqa: E402
import hut_room as room  # noqa: E402
import hut_yard as yard  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, save  # noqa: E402

OUT = ROOT / "interior" / "cabin"
OUT.mkdir(parents=True, exist_ok=True)
SIZES = {}

# the room: a floor of 224 x 144 px; the shell is 256 wide, the doorway sits in the middle of the front lip
FLOOR = (224, 144)
DOOR_X = 128  # shell px
ROOM_PARAMS = dict(floor=FLOOR, holes=[(34, 66, 13, 10), (176, 52, 10, 8), (180, 116, 13, 9), (96, 22, 7, 5)], sapling=(180, 116), damp=(224, 0),
                   windows=[(room.SIDE_W + 150, 40.0, 12.0, 32.0)], hole_wall=None, pilasters=(room.SIDE_W + 92,), door_gap=(DOOR_X - 24, DOOR_X + 24),
                   hearth=[(DOOR_X - 38, 124, DOOR_X + 14, 144)], hearth_at=(200, 14))


def put(name, arr, glow=True):
    save(OUT / f"{name}.png", arr)
    SIZES[name] = (arr.shape[1], arr.shape[0])
    if glow:
        g = glow_of(arr)
        if g[..., 3].any():
            save(OUT / f"{name}_glow.png", g)
        elif (OUT / f"{name}_glow.png").exists():
            (OUT / f"{name}_glow.png").unlink()


def dusty(arr, amount=0.7, seed=1):
    """Years of dust and cobweb-grey: the top edges of everything go pale, the rest is speckled."""
    rng = np.random.default_rng(seed)
    out = arr.copy()
    dust = np.array([168, 158, 176], float)
    hh, ww = arr.shape[:2]
    for y in range(hh):
        for x in range(ww):
            if arr[y, x, 3] < 200:
                continue
            depth = 0
            while depth < 3 and y - depth - 1 >= 0 and arr[y - depth - 1, x, 3] >= 200:
                depth += 1
            top = 3 - depth if depth < 3 else 0  # 3 on the very top edge .. 1 three rows below
            k = (0.55, 0.34, 0.2)[3 - top] * amount if top else 0.0
            if rng.random() < 0.05 * amount:
                k = max(k, 0.3 * amount)
            if k > 0.0:
                out[y, x, :3] = (arr[y, x, :3] * (1 - k) + dust * k).astype(np.uint8)
    return out


# ------------------------------------------------------------------ the room
def room_shell():
    room.configure(**ROOM_PARAMS)
    put("floor", room.floor_arr(seed=15), glow=False)
    put("wall", dusty(room.back_wall_arr(seed=17), 0.5, 3))
    put("side", room.side_arr(seed=13))
    put("front", room.front_arr(seed=19))
    put("door", room.door_arr(48, 40, seed=33))
    put("rays", fx.rays_arr(), glow=False)
    put("web", fx.webs_arr(), glow=False)
    drip, splash = fx.drip_arr()
    put("drip", drip, glow=False)
    put("splash", splash, glow=False)


def room_props():
    sheet, _ = props.bed_frames()
    put("bed", dusty(sheet, 0.8, 5))
    for name, fn in (("table", props.table_arr), ("chair", props.chair_arr), ("chest", props.chest_arr), ("barrel", props.barrel_arr), ("crates", props.crates_arr),
                     ("shelf", props.shelf_arr), ("rack", props.rack_arr), ("herbs", props.herbs_arr), ("lantern", props.lantern_arr), ("pots", props.pots_arr),
                     ("fireplace", props.fireplace_arr), ("rug", props.rug_arr)):
        arr, feet = fn()
        put(name, dusty(arr, 0.85, len(name)))
        SIZES[name + "_feet"] = feet
    # a cold hearth has no flames and no embers
    for stale in ("fireplace_glow.png", "lantern_glow.png", "table_glow.png", "bed_glow.png", "shelf_glow.png"):
        if (OUT / stale).exists():
            (OUT / stale).unlink()
    stools = [props.stool_arr(v) for v in range(3)]
    sheet = np.zeros((30, 28 * 3, 4), np.uint8)
    for i, (arr, _) in enumerate(stools):
        sheet[:arr.shape[0], i * 28:i * 28 + arr.shape[1]] = arr[:30, :28]
    put("stool", dusty(sheet, 0.8, 9), glow=False)


# ------------------------------------------------------------------ the cabin from outside
FW, FH, GROUND = 160, 156, 132
HALF = 38.0


def cabin_arr(seed=31):
    rng = rng_for(seed)
    m = h.Model()
    wall_top = 41.0
    door_x = (-9.5, 9.5)
    win = (24.0, 16.0, 31.0)

    def cut(x, y):
        if door_x[0] - 3 < x < door_x[1] + 3 and y < 37:
            return True
        return abs(x - win[0]) < 8.5 and win[1] < y < win[2]

    x = -HALF - 5
    while x < HALF + 5:  # foundation stones, one of them gone
        w = rng.uniform(7, 11)
        if not (HALF * 0.55 < x < HALF * 0.55 + 9):
            m.ell((x + w / 2, 2.0, 3.0), (w / 2, rng.uniform(2.2, 3.4), rng.uniform(3.6, 5.4)), STONE if rng.random() < 0.6 else STONE_L)
            if rng.random() < 0.5:
                m.ell((x + w / 2, 4.8, 4.2), (rng.uniform(2, 4), 0.8, 1.6), MOSS_L)
        x += w
    mats = [BARK, PLANK_W, BARK_D, BARK, PLANK_W]
    for li in range(5):  # five logs, the corner ends proud, one log slipped
        y = 6.5 + li * 8.4
        x = -HALF
        slip = -1.4 if li == 3 else 0.0
        while x <= HALF:
            if not cut(x, y):
                r = 4.5 * (1.0 + 0.07 * math.sin(x * 0.11 + li * 1.7))
                m.ell((x, y + 0.45 * math.sin(x * 0.06 + li) + (slip if x > 10 else 0.0), 1.5), (3.1, r, r), mats[li])
            x += 1.4
        for sx in (-1, 1):
            log(m, V(sx * (HALF - 3), y, 1.5), V(sx * (HALF + 5), y + 0.5 * sx, 1.5), 4.4, BARK_D if li % 2 else BARK, step=1.2)
            m.ell((sx * (HALF + 5.3), y + 0.5 * sx, 1.5), (1.0, 4.2, 4.2), PLANK_W)
    # doorway: crooked posts and lintel, a dark inside, the threshold stones
    for sx in door_x:
        log(m, V(sx - 1.6 * np.sign(sx), 0, 3.4), V(sx - 1.6 * np.sign(sx) + 0.4, 38, 3.4), 3.1, BARK_D, step=1.3)
    log(m, V(door_x[0] - 6, 38.8, 3.0), V(door_x[1] + 6, 39.6, 3.0), 2.9, BARK, step=1.3)
    m.ell((0, 20, -4.0), (door_x[1] + 3, 22, 0.8), GAP)
    for k in range(3):
        m.ell((-8 + k * 8, 1.2, 8.0), (4.6, 1.7, 3.4), STONE_L if k % 2 else STONE)
    # the boarded window: dark, three planks nailed across, one hanging loose, a broken shutter
    wx, wy0, wy1 = win
    m.ell((wx, (wy0 + wy1) / 2, -2.0), (8.5, (wy1 - wy0) / 2, 0.6), GAP)
    for k, dy in enumerate((wy0 + 2.5, (wy0 + wy1) / 2, wy1 - 2.5)):
        if k == 1:
            slab(m, V(wx - 10, dy - 3.0, 5.2), V(wx + 4.0, dy + 1.0, 5.4), 1.9, 0.9, BARK_D, (0, 0, 1))  # slipped, one end down
        else:
            slab(m, V(wx - 11, dy, 5.0 + 0.2 * k), V(wx + 11, dy + 0.6, 5.0 + 0.2 * k), 1.9, 0.9, PLANK_W if k == 0 else BARK, (0, 0, 1))
        for nx in (-8, 8):
            m.ell((wx + nx, dy, 6.0), (0.5, 0.5, 0.4), IRON)
    slab(m, V(wx + 9.5, wy1, 5.6), V(wx + 13.5, wy0 - 4, 6.8), 3.4, 0.9, BARK_D, (0, 0, 1))
    # the roof: boards up the south slope, sagging, a big collapsed corner (left) where the rafters show, moss, rotten patches
    eave = V(0, 52.0, 12.0)
    ridge = V(0, 71.0, -22.0)
    slope = ridge - eave
    length = float(np.linalg.norm(slope))
    up = slope / length
    normal = np.cross(V(1, 0, 0), up)
    normal = normal * (1 if normal[1] > 0 else -1)
    rows = int(length / 4.2)
    roof_a = math.atan2(normal[2], normal[1])
    hole_c = (-14.0, 0.5)
    for r in range(rows + 1):
        t = r / rows
        base = eave + slope * t
        sag = -2.0 * math.sin(math.pi * t) * 0.5
        mat = (PLANK_W, BARK, BARK_D, PLANK_W)[int(rng.integers(0, 4))]
        x = -HALF - 10
        while x < HALF + 10:
            seg = rng.uniform(22, 44)
            smat = mat if rng.random() < 0.7 else (BARK_D, PLANK_W, BARK)[int(rng.integers(0, 3))]
            xi = x
            while xi < x + seg - 1 and xi < HALF + 10:
                dx, dt = xi - hole_c[0], t - hole_c[1]
                d = math.hypot(dx / 17.0, dt / 0.27) + (fbm(xi * 0.2, r * 3.0, 4) - 0.5) * 0.5
                droop = -2.2 * math.sin((xi + HALF + 10) / (2 * HALF + 20) * math.pi)
                if d > 1.0:
                    m.ell(base + V(xi, sag + droop * 0.3, 0), (3.2, 1.0, 2.6), smat, R=h.rot_x(roof_a))
                xi += 1.5
            x += seg
    for r in range(rows + 1):
        t = r / rows
        base = eave + slope * t
        for xi in np.arange(-HALF - 10, HALF + 10, 2.5):
            if math.hypot((xi - hole_c[0]) / 17.0, (t - hole_c[1]) / 0.27) > 1.1 and rng.random() < 0.55:
                m.ell(base + V(xi, -1.2, 0.7), (1.8, 0.6, 0.7), (PLANK_W, BARK)[r % 2], R=h.rot_x(roof_a))
    m.ell(V(hole_c[0], 62.0, -4.0), (15.0, 6.5, 0.8), GAP)  # the hole shows the dark inside
    for k in range(3):  # the bare rafters across the hole
        a = V(hole_c[0] - 15 + k * 0.5, 56.0 + k * 3.6, 0.0 - k * 4.0)
        log(m, a, a + V(30, -1.4 + k * 0.5, 0.4), 1.7, BARK_D, step=1.2)
    for k in range(16):  # splinters round the hole
        a = k / 16 * math.tau
        m.ell(V(hole_c[0] + math.cos(a) * 16.5, 62.0 + math.sin(a) * 7.2 + 1.0, -3.0 + math.sin(a) * 2.0), (0.8, rng.uniform(1.6, 3.6), 0.6), BARK_D, R=h.rot_x(rng.uniform(-0.8, 0.8)))
    log(m, V(-HALF - 12, 71.6, -22), V(HALF + 12, 71.4, -22), 3.3, BARK_D, step=1.4)  # the ridge beam
    for _ in range(170):  # moss
        t = rng.uniform(0.0, 1.0)
        xx = rng.uniform(-HALF - 8, HALF + 8)
        if math.hypot((xx - hole_c[0]) / 19.0, (t - hole_c[1]) / 0.3) < 1.0:
            continue
        m.ell(eave + slope * t + V(xx, 0.6, 0.6), (rng.uniform(2.5, 7), 0.8, rng.uniform(1.4, 3.4)), MOSS_L if rng.random() < 0.35 else MOSS)
    for _ in range(34):
        xx = rng.uniform(-HALF - 6, HALF + 6)
        ln = rng.uniform(4, 12)
        m.limb(eave + V(xx, 0.0, 1.2), eave + V(xx + rng.uniform(-0.6, 0.6), -ln, 1.6), 0.5, 0.15, MOSS)
    # a young tree grows out of the hole: a veined trunk, a few clumps of leaves (the same violet-touched green as the world's trees)
    p = V(hole_c[0] + 2.0, 58.0, -6.0)
    for s in range(14):
        q = p + V(0.35 * math.sin(s * 0.7), 2.3, 0.0)
        m.limb(p, q, 1.9 - s * 0.09, 1.8 - s * 0.09, BARK)
        if s % 4 == 1:
            m.limb(p + V(0.7, 0, 0.3), q + V(0.7, 0, 0.3), 0.2, 0.18, h.VIOLET, kind="emit")
        if s in (7, 10, 12):
            side = 1 if s % 2 else -1
            b = q + V(side * 6.5, 2.4, 0.5)
            m.limb(q, b, 0.9, 0.5, BARK)
            for _ in range(5):
                m.ell(b + V(rng.uniform(-3, 3), rng.uniform(-1.5, 2.5), rng.uniform(-1.5, 1.5)), (rng.uniform(2.2, 3.6), rng.uniform(1.4, 2.4), 1.7), MOSS_L if rng.random() < 0.5 else MOSS)
        p = q
    for _ in range(9):
        m.ell(p + V(rng.uniform(-4, 4), rng.uniform(-1.5, 3.5), rng.uniform(-1.5, 1.5)), (rng.uniform(2.6, 4.2), rng.uniform(1.6, 2.6), 1.8), MOSS_L if rng.random() < 0.45 else MOSS)
    m.ell(p + V(0.5, 2.5, 1.5), (0.7, 0.7, 0.7), h.TEAL, kind="emit")
    # the chimney broke off: a stump of stones at the right, stones scattered on the roof and in the grass
    for k in range(16):
        y = 58.0 + k * 1.1
        for j in range(3):
            m.ell((27.0 + rng.uniform(-5.5, 5.5), y, -14.0 + rng.uniform(-4, 4)), (rng.uniform(2.6, 4.2), 2.2, rng.uniform(2.4, 3.8)), (STONE, STONE_L, STONE)[int(rng.integers(0, 3))])
    m.ell((27.0, 76.0, -14.0), (6.4, 1.4, 5.2), STONE_L)
    m.ell((27.0, 77.2, -14.0), (3.4, 0.6, 2.8), GAP)
    for k in range(7):
        m.ell((rng.uniform(14, 40), rng.uniform(52, 66) if k < 3 else 2.4, rng.uniform(-3, 14)), (rng.uniform(1.8, 3.2), rng.uniform(1.4, 2.4), rng.uniform(1.6, 3.0)), STONE if k % 2 else STONE_L)
    m.ell((27.0, 66.0, -9.0), (4.6, 0.8, 1.6), MOSS_L)
    # ivy over the left corner and the right wall, roots at the foot, glowing mushrooms by the door, a mossy woodpile on the right
    for k in range(8):
        ivy(m, V(-HALF + 2 + k * 1.4, rng.uniform(38, 56), 5.2 + k * 0.1), rng.uniform(26, 50), rng, glow_every=4, sway=0.7)
    for k in range(5):
        ivy(m, V(HALF - 12 + k * 3.5, rng.uniform(36, 46), 5.2), rng.uniform(14, 30), rng, glow_every=5, sway=0.7)
    for k in range(4):
        p = V(-HALF + 3 + k * 24.0, 2.5, 7.0)
        a = rng.uniform(0, math.tau)
        for s in range(6):
            q = p + V(math.cos(a) * 2.0 + rng.uniform(-0.6, 0.6), -0.1, 1.0 + abs(math.sin(a)) * 0.8)
            m.limb(p, q, max(1.9 - s * 0.27, 0.4), max(1.7 - s * 0.27, 0.35), BARK)
            p = q
    for k in range(5):
        mx = -22.0 - k * 3.6
        m.ell((mx, 3.0, 8.0 + k % 2), (1.3, 1.1, 1.3), LINEN)
        m.ell((mx, 5.0 + (k % 2) * 0.6, 8.0 + k % 2), (2.6, 1.0, 2.3), h.TEAL, kind="emit")
    for k in range(9):
        log(m, V(HALF - 3 + (k % 3) * 4.0, 3 + (k // 3) * 4.0, 9), V(HALF - 3 + (k % 3) * 4.0 + 0.4, 3 + (k // 3) * 4.0, 1), 2.0, (BARK, PLANK_W, BARK_D)[k % 3], step=1.1)
    m.ell((HALF + 1, 13.0, 10.0), (7.0, 1.2, 2.2), MOSS_L)
    arr = to_array(render(m, FW, FH, GROUND))
    arr = grain(arr, 31, along=(1.0, 0.0), amount=0.7)
    return soft_shadow(arr, FW / 2, GROUND + 4, 56, 8, 70), GROUND


# ------------------------------------------------------------------ the board across the door, the yard
def board_arr():
    """The board: a broad old plank propped across the cabin's door (frame 0, it leans from the doorstep against the door frame) and the same plank lying flat on the ground (frame 1, where
    she sets it down). Grey, cracked, nails, moss, a small mushroom growing from its crack. 2 frames of 64 x 56, ground row 48."""
    rng = rng_for(71)
    frames = []
    for lying in (False, True):
        m = h.Model()
        if not lying:
            a, b = V(0, 1.5, 11.0), V(1.0, 41.0, -6.0)
            slab(m, a, b, 10.5, 2.4, PLANK_W, (0, 0.5, 1), step=1.2)
            slab(m, a + V(-3.5, 0, 2.0), b + V(-3.2, -6, 2.0), 3.0, 0.8, BARK_D, (0, 0.5, 1), step=1.2)
            for y, z in ((15.0, 5.2), (31.0, -1.6)):  # two cross battens nailed on
                slab(m, V(-11.5, y, z + 2.3), V(11.5, y + 0.4, z + 2.3), 1.7, 0.9, BARK, (0, 0.5, 1), step=1.3)
                for nx in (-8, 8):
                    m.ell((nx, y + 0.2, z + 3.3), (0.55, 0.55, 0.4), IRON)
            m.limb(V(2, 8.0, 8.0), V(-1, 36.0, -3.0), 0.4, 0.3, GAP)  # the crack
            for _ in range(8):
                t = rng.uniform(0.05, 0.9)
                p = a + (b - a) * t
                m.ell(p + V(rng.uniform(-8, 8), 0.2, 2.6), (rng.uniform(2, 5), 0.8, 1.2), MOSS_L if rng.random() < 0.4 else MOSS)
            for k in range(3):  # a small fungus at the foot
                m.ell(V(7 + k * 2.2, 3.0 + 0.4 * k, 12.6 + 0.4 * k), (1.7 - 0.3 * k, 0.6, 1.4 - 0.2 * k), h.TEAL, kind="emit")
            m.ell(V(-9, 1.0, 13.0), (4.2, 1.2, 2.4), MOSS)
        else:
            slab(m, V(-27, 3.4, -2.0), V(27, 3.2, 0.6), 4.6, 2.3, PLANK_W, (0, 1, 0), step=1.2)
            slab(m, V(-26, 3.0, 5.4), V(22, 2.9, 6.6), 3.4, 2.0, BARK_D, (0, 1, 0), step=1.2)
            slab(m, V(-27, 5.6, 3.0), V(26, 5.4, 4.4), 0.4, 0.2, GAP, (0, 1, 0), step=1.3)
            for nx in (-22.0, 20.0):
                m.ell((nx, 5.9, -1.2), (0.7, 0.4, 0.7), IRON)
            m.limb(V(-24, 5.6, 0.2), V(-27.5, 7.0, 1.0), 0.45, 0.3, IRON)
            for _ in range(9):
                m.ell((rng.uniform(-24, 24), 5.8, rng.uniform(-3, 6)), (rng.uniform(2.5, 6), 0.7, rng.uniform(1.4, 3)), MOSS_L if rng.random() < 0.4 else MOSS)
            for k in range(3):
                m.ell((6 + k * 2.2, 6.4, 3.4 + 0.5 * k), (0.9, 0.9, 0.9), LINEN)
                m.ell((6 + k * 2.2, 7.4 + 0.3 * k, 3.4 + 0.5 * k), (1.7 - 0.3 * k, 0.6, 1.5 - 0.2 * k), h.TEAL, kind="emit")
        arr = to_array(render(m, 64, 56, 48))
        arr = soft_shadow(grain(arr, 72, amount=0.6), 32, 49, 24 if not lying else 30, 4, 70)
        frames.append(arr)
    sheet = np.zeros((56, 128, 4), np.uint8)
    sheet[:, :64] = frames[0]
    sheet[:, 64:] = frames[1]
    return sheet, 48


def stump_arr():
    """A chopping stump of grey old wood with split rings, a wedge stuck in it, mossy, one old axe cut. 40 x 40, ground row 32."""
    rng = rng_for(73)
    m = h.Model()
    for k in range(7):  # the trunk piece
        a = k / 7 * math.tau
        m.ell(V(math.cos(a) * 8.0, 6.5, math.sin(a) * 7.0), (4.0, 7.0, 3.6), BARK if k % 2 else BARK_D, R=h.rot_y(-a))
    m.ell(V(0, 12.4, 0), (11.6, 1.3, 10.4), RING_W)
    for f in (0.78, 0.56, 0.34):
        m.ell(V(0, 13.5, 0), (11.4 * f, 0.4, 10.2 * f), BARK_D)
    m.limb(V(-9, 13.6, 0), V(9, 13.6, 0.5), 0.35, 0.3, GAP)  # the split
    m.limb(V(-1, 13.0, 1), V(-1, 20.0, 0.5), 1.4, 0.8, IRON)  # the wedge
    m.ell((-1, 13.8, 1.2), (1.9, 0.5, 1.2), IRON)
    for _ in range(5):
        m.ell(V(rng.uniform(-9, 9), 13.2, rng.uniform(-8, 8)), (rng.uniform(1.6, 3.4), 0.5, rng.uniform(1.2, 2.2)), MOSS_L if rng.random() < 0.4 else MOSS)
    for sx in (-1, 1):  # roots at the foot
        m.limb(V(sx * 8.5, 2.0, 2.0), V(sx * 15.0, 0.6, 5.5), 2.2, 0.7, BARK)
    for k in range(3):
        m.ell(V(7 + k * 2.2, 4.0 + k, 7.2 + k * 0.4), (2.0 - 0.4 * k, 0.7, 1.4), h.TEAL, kind="emit")
    arr = to_array(render(m, 44, 44, 34))
    return soft_shadow(grain(arr, 74, amount=0.6), 22, 35, 16, 4, 70), 34


def woodpile_arr():
    """An old, mossy stack of split logs, collapsing on one side, two rows, a rotten top. 56 x 40, ground row 32."""
    rng = rng_for(75)
    m = h.Model()
    for row in range(3):
        n = 7 - row
        for k in range(n):
            x = -18 + row * 3.4 + k * 6.2 + rng.uniform(-0.5, 0.5)
            log(m, V(x, 3.2 + row * 5.6, 5), V(x + rng.uniform(-0.6, 0.6), 3.2 + row * 5.6, -5), 3.0, (BARK, PLANK_W, BARK_D)[(k + row) % 3], step=1.1)
            m.ell((x, 3.2 + row * 5.6, 5.6), (2.4, 2.4, 0.5), RING_W)
    for k in range(3):  # fallen logs on the right
        x, z = 22 + k * 5.0, 6 + k * 3.0
        log(m, V(x, 2.6, z + 4), V(x + 5, 2.6, z - 4), 2.7, BARK_D if k % 2 else BARK, step=1.1)
    for _ in range(10):
        m.ell(V(rng.uniform(-20, 20), 15.5 + rng.uniform(-2, 1.5), rng.uniform(-4, 4)), (rng.uniform(2.5, 6), 0.9, rng.uniform(1.6, 3)), MOSS_L if rng.random() < 0.4 else MOSS)
    for k in range(4):
        m.ell(V(-14 + k * 9, 6.0 + (k % 2) * 6, 5.9), (1.8, 0.7, 1.5), h.TEAL, kind="emit")
    arr = to_array(render(m, 60, 40, 32))
    return soft_shadow(grain(arr, 76, amount=0.6), 30, 33, 28, 5, 70), 32


def sawhorse_arr():
    """A sawbuck with a half-cut log on it and a rusty bow saw stuck in the cut. 56 x 40, ground row 32."""
    rng = rng_for(77)
    m = h.Model()
    for sx in (-1, 1):
        log(m, V(sx * 12, 1.0, -7), V(sx * 6, 13, 0), 1.9, BARK_D, step=1.1)
        log(m, V(sx * 12, 1.0, 7), V(sx * 6, 13, 0), 1.9, BARK_D, step=1.1)
    log(m, V(-18, 13.5, -2), V(18, 13.5, 2), 2.2, PLANK_W, step=1.1)
    log(m, V(-16, 18.5, 0), V(17, 18.8, 0), 3.4, BARK, step=1.1)  # the log on the horse
    m.ell(V(17.4, 18.8, 0), (0.8, 3.2, 3.2), RING_W)
    log(m, V(2, 22.0, 1), V(2.4, 29.0, 1), 0.7, IRON, step=0.8)  # the saw: two ends and a blade
    log(m, V(-10, 28.8, 1), V(12, 29.2, 1), 0.55, BARK_D, step=0.9)
    m.ell(V(1, 24.5, 1.1), (0.5, 4.6, 0.3), IRON)
    for _ in range(6):
        m.ell(V(rng.uniform(-14, 14), 21.9, rng.uniform(-2, 2)), (rng.uniform(2.2, 5), 0.7, rng.uniform(1.2, 2.2)), MOSS_L if rng.random() < 0.4 else MOSS)
    for k in range(5):  # sawdust gone to soil beneath
        m.ell(V(rng.uniform(-12, 12), 0.8, rng.uniform(-6, 6)), (rng.uniform(1.5, 3), 0.5, rng.uniform(1.2, 2.4)), SOIL)
    arr = to_array(render(m, 60, 44, 36))
    return soft_shadow(grain(arr, 78, amount=0.6), 30, 37, 24, 4, 70), 36


RING_W = len(h.RAMPS)
h.RAMPS += [[hexc(c) for c in row] for row in [["5c4852", "8b727c", "bda3a8", "e6d3cf"]]]


def cabin_door_leaf():
    return room.door_arr(22, 36, seed=37)


def main():
    room_shell()
    room_props()
    ext, feet = cabin_arr()
    put("cabin", ext)
    SIZES["cabin_feet"] = feet
    put("cabin_door", cabin_door_leaf(), glow=False)
    for name, fn in (("yard_board", board_arr), ("yard_stump", stump_arr), ("yard_woodpile", woodpile_arr), ("yard_sawhorse", sawhorse_arr)):
        arr, feet = fn()
        put(name, arr)
        SIZES[name + "_feet"] = feet
    print(json.dumps(SIZES))


if __name__ == "__main__":
    main()
