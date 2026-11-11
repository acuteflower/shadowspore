#!/usr/bin/env python3
"""The lake witch's house (docs/seehexe_konzept.md, step 1): a low, wide, crooked stilt house at the south shore of the Hexenwald lake, its yard, the jetty, the
ring of ward stones and its room. Made like the hut and the cabin (hut_lib / hut_room / hut_props, the trees' ellipsoid renderer), but in the Hexenwald's own
woods: pale bleached bone wood (Bleichholz) for the walls, dark veined hag elm for posts and beams, a heavy reed roof, crystals everywhere.
    py -3 tools/art_lake_hut.py [preview.png]        writes assets/interior/lake_hut/*.png (+ _glow sheets) and data/interiors.json "lake_hut"
Positions of the house and its yard are in data/ground.json huts[] (id lake_hut); the house picture's numbers (frame, feet, door) are printed and kept in
src/entities/props/hut.gd LOOKS["lake"]."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_fx as fx  # noqa: E402
import hut_lib  # noqa: E402
import hut_props as props  # noqa: E402
import hut_room as room  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, save  # noqa: E402

OUT = ROOT / "interior" / "lake_hut"
OUT.mkdir(parents=True, exist_ok=True)
SIZES = {}

# the Hexenwald's woods and the lake's stones (new ramps, appended like hut_lib's)
_B = len(h.RAMPS)
(BONE, BONE_D, REED, REED_D, MOON, GLASS, WSTONE, WSTONE_D, MIRROR, ROPE, REED_S, REED_L) = range(_B, _B + 12)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["2c2834", "5a5464", "9790a0", "cfc8d2"],  # bleached bone wood (Bleichbaum), pale and cool
    ["1d1924", "3a3444", "625a6c", "8e8598"],  # bone wood in shade / old boards
    ["262a1e", "47503a", "77805a", "a9ae82"],  # reed thatch, grey-olive
    ["15180f", "2a3020", "445034", "667050"],  # reed, wet and dark underneath
    ["4a5266", "8a94a8", "c4cad8", "eef0f6"],  # moonstone: milky, cool
    ["0c2a32", "1a5058", "3a8a8c", "8ad8d0"],  # crystal glass (not glowing)
    ["2a2238", "4a3d5e", "776a8e", "a99ec0"],  # the violet stone of the ward stones (the waystones' stone)
    ["17121f", "2c2338", "463a58", "6a5c80"],  # ward stone, scorched by the void
    ["3a4a6a", "7488b0", "b8cae8", "f4fbff"],  # mirror shards
    ["2a2230", "4c4050", "786878", "a89aa4"],  # old rope / string
    ["0e100c", "1c2016", "2e3424", "454c36"],  # reed in the roof's shade (the hip away from the light)
    ["3a3e2c", "626848", "959a6e", "c8c898"],  # reed in full light (the hip toward the light)
]]
GLOWS = (h.TEAL, h.VIOLET, FIRE, SKY)


def put(name, arr, glow=True):
    save(OUT / f"{name}.png", arr)
    SIZES[name] = (arr.shape[1], arr.shape[0])
    if glow:
        g = glow_of(arr, GLOWS)
        if g[..., 3].any():
            save(OUT / f"{name}_glow.png", g)
        elif (OUT / f"{name}_glow.png").exists():
            (OUT / f"{name}_glow.png").unlink()


def crystal(m, base, height, r, lean=(0.0, 0.0), emit=True, mat=None):
    """An upright grown crystal: a six-sided prism of stacked ellipsoids narrowing to a point; the core glows teal (emit) or stays dull glass."""
    body = mat if mat is not None else GLASS
    n = max(3, int(height / 0.9))
    for k in range(n + 1):
        t = k / n
        rr = r * (1.0 - t ** 1.6 * 0.95)
        p = base + V(lean[0] * height * t, height * t, lean[1] * height * t)
        m.ell(p, (rr, 0.7, rr), body)
        if emit and 0.15 < t < 0.8:  # the light inside shows through the front faces (on the surface, or small crystals would hide it)
            m.ell(p + V(-rr * 0.2, 0, rr * 0.72), (max(rr * 0.45, 0.75), 0.7, max(rr * 0.35, 0.7)), h.TEAL, kind="emit")


def scaled(m, k):
    """Grows a whole model by k (both positions and radii), for props that read too small."""
    for p in m.prims:
        p.c = p.c * k
        p.r = p.r * k
    return m


def gap_box(m_marker, fw, fh, ground):
    """Bounding box (x0, y0, x1, y1) of what a marker model covers in the picture."""
    arr = to_array(render(m_marker, fw, fh, ground))
    ys, xs = np.nonzero(arr[..., 3])
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


# ------------------------------------------------------------------ the house from outside
# A real body, turned a little (YAW) so its right side wall and the hip of the roof show: the front wall stands on z = 0 (the feet row), the house runs back to
# z = -DEPTH. A heavy hipped reed roof with a deep overhang, a crystal cluster bursting through it, a crescent-moon pole on the ridge, bottles and bundles
# under the eave, crystal lanterns by the door, carved runes on the door posts, a net with floats on the left wall, candles on the steps.
FW, FH, GROUND = 248, 160, 124
HALF = 50.0
DEPTH = 40.0
YAW = -0.32
FLOOR_Y = 7.0  # the house stands on stilts: its floor is this high
DOOR_X = (-9.0, 9.0)
DOOR_TOP = FLOOR_Y + 34.0
LENS = (28.0, FLOOR_Y + 19.0, 9.5)  # the big round lens window: centre x, centre y, radius
SMALL = (-32.0, FLOOR_Y + 22.0, 5.0)
WALL_TOP = FLOOR_Y + 49.0
DOOR_INFO = {}
LENS_BOX = None


def turned(m, yaw=YAW):
    """Turns a whole model about the vertical axis through the feet (the middle of the front wall)."""
    R = h.rot_y(yaw)
    for p in m.prims:
        p.c = R @ p.c
        p.R = R @ p.R
    return m


def roof_height(x, z, eave_h, ridge_h, xr, zr, rx):
    """The hipped roof's surface: two slopes (front/back toward the ridge line, the hips toward its ends), softly blended; None outside the eave outline."""
    zc = -DEPTH / 2
    a = (zr - abs(z - zc)) / zr  # 0 at the front/back eave .. 1 at the ridge line
    b = (xr - abs(x)) / (xr - rx)  # 0 at the side eave .. 1 where the ridge begins
    if a < 0 or b < 0:
        return None
    k = 0.18  # soft minimum: the hips curve into the slopes like a thick reed roof
    t = -k * math.log(math.exp(-a / k) + math.exp(-b / k))
    return eave_h + (ridge_h - eave_h) * min(1.0, max(0.0, t)), a, b


def house_arr(seed=41):
    rng = rng_for(seed)
    m = h.Model()

    def cut(x, y):
        if DOOR_X[0] - 2.5 < x < DOOR_X[1] + 2.5 and y < DOOR_TOP + 1:
            return True
        if math.hypot(x - LENS[0], y - LENS[1]) < LENS[2] + 1.2:
            return True
        return math.hypot(x - SMALL[0], y - SMALL[1]) < SMALL[2] + 1.0

    # the dark under the floor, stilts along the front and the right side, standing in stones
    m.ell((0, 3.0, -DEPTH / 2), (HALF, 3.4, DEPTH / 2), GAP)
    posts = [(sx, 1.6) for sx in np.linspace(-HALF + 2, HALF - 2, 6)] + [(HALF - 2, z) for z in (-14.0, -27.0, -DEPTH + 2)]
    for k, (sx, sz) in enumerate(posts):
        log(m, V(sx, -0.5, sz), V(sx + rng.uniform(-0.6, 0.6), FLOOR_Y + 0.5, sz), 2.3, BARK_D, step=1.0)
        m.ell((sx, 0.6, sz + 1.0), (3.6, 1.5, 3.2), STONE if k % 2 else STONE_L)
        if k % 3 == 1:
            m.limb(V(sx + 0.8, 1.5, sz + 2.2), V(sx + 0.6, FLOOR_Y - 1, sz + 2.2), 0.25, 0.22, h.VIOLET, kind="emit")
    # the floor's edge: heavy beams of hag elm along the front and the side
    log(m, V(-HALF - 4, FLOOR_Y + 1.0, 1.0), V(HALF + 4, FLOOR_Y + 1.2, 1.0), 2.5, BARK, step=1.2)
    log(m, V(HALF + 1.0, FLOOR_Y + 1.2, 2.0), V(HALF + 1.0, FLOOR_Y + 1.0, -DEPTH - 2), 2.5, BARK_D, step=1.2)
    # the body behind the planks (so no gap shows the world through it)
    m.ell((0, (FLOOR_Y + WALL_TOP) / 2, -DEPTH / 2), (HALF - 1.5, (WALL_TOP - FLOOR_Y) / 2, DEPTH / 2 - 1.5), BONE_D)
    # front wall: vertical bone-wood planks; the top rows darker (the eave's shadow)
    x = -HALF
    while x < HALF:
        w = rng.uniform(4.2, 6.0)
        mat = BONE if rng.random() < 0.72 else BONE_D
        top = WALL_TOP + rng.uniform(-1.5, 1.0)
        y = FLOOR_Y + 2.0
        while y < top:
            if not cut(x + w / 2, y):
                shade = BONE_D if y > WALL_TOP - 7 else mat
                m.ell((x + w / 2, y, 0.4 + 0.25 * math.sin(x * 0.4)), (w / 2 - 0.3, 1.2, 1.4), shade)
            y += 1.1
        x += w
    # the right side wall, running back: planks along z, a small round window, the eave's shadow
    z = 0.0
    while z > -DEPTH:
        w = rng.uniform(4.2, 6.0)
        mat = BONE if rng.random() < 0.6 else BONE_D
        y = FLOOR_Y + 2.0
        top = WALL_TOP + rng.uniform(-1.0, 0.5)
        while y < top:
            if math.hypot(z - w / 2 + 20.0, y - (FLOOR_Y + 24.0)) > 5.6:
                m.ell((HALF + 0.3, y, z - w / 2), (1.4, 1.2, w / 2 - 0.3), BONE_D if y > WALL_TOP - 8 else mat)
            y += 1.1
        z -= w
    for k in range(20):
        a = k / 20 * math.tau
        m.ell((HALF + 1.4, FLOOR_Y + 24.0 + math.sin(a) * 5.6, -20.0 + math.cos(a) * 5.6), (1.2, 1.2, 1.2), BARK_D)
    m.ell((HALF + 0.8, FLOOR_Y + 24.0, -20.0), (0.6, 4.6, 4.6), FIRE, kind="emit")
    # corner posts of hag elm with violet veins; the top beams
    for (px, pz) in ((-HALF - 1.5, 1.2), (HALF + 1.5, 1.2), (HALF + 1.5, -DEPTH)):
        log(m, V(px, FLOOR_Y, pz), V(px + 0.2, WALL_TOP + 2, pz), 3.0, BARK_D, step=1.1)
        p = V(px + 1.2, FLOOR_Y + 6, pz + 2.6)
        for s in range(7):
            q = p + V(rng.uniform(-0.6, 0.6), rng.uniform(2.0, 3.2), 0)
            m.limb(p, q, 0.25, 0.22, h.VIOLET, kind="emit")
            p = q
    log(m, V(-HALF - 3, WALL_TOP + 1.5, 1.6), V(HALF + 3, WALL_TOP + 0.8, 1.6), 2.6, BARK, step=1.2)
    log(m, V(HALF + 1.6, WALL_TOP + 0.8, 2.0), V(HALF + 1.6, WALL_TOP + 1.2, -DEPTH - 2), 2.6, BARK_D, step=1.2)
    # the doorway: crooked posts carved with glowing runes, a lintel, the dark inside, steps down to the yard with candles
    for sx in DOOR_X:
        px = sx - 1.8 * np.sign(sx)
        log(m, V(px, FLOOR_Y, 2.4), V(px + 0.3, DOOR_TOP + 1, 2.4), 2.6, BARK_D, step=1.2)
        for k in range(5):
            y = FLOOR_Y + 5 + k * 6.0
            m.limb(V(px - 0.9, y, 5.0), V(px + 0.9, y + (1.6 if k % 2 else -1.0), 5.0), 0.35, 0.35, h.VIOLET if k % 2 else h.TEAL, kind="emit")
    log(m, V(DOOR_X[0] - 5, DOOR_TOP + 2.0, 2.2), V(DOOR_X[1] + 5, DOOR_TOP + 2.6, 2.2), 2.4, BARK, step=1.2)
    m.ell((0, FLOOR_Y + DOOR_TOP / 2 - 2, -3.6), (DOOR_X[1] + 2.5, DOOR_TOP / 2 - 1, 0.8), GAP)
    for k in range(3):
        slab(m, V(-12 - k, FLOOR_Y - 2.4 * k, 4.4 + 3.6 * k), V(12 + k, FLOOR_Y - 2.4 * k, 4.4 + 3.6 * k), 1.9, 1.3, PLANK_W if k else BARK, (0, 1, 0.3), step=1.2)
    m.ell((0, 0.8, 16.0), (13.0, 1.6, 3.6), STONE_L)
    for sx, k in ((-12.0, 0), (11.0, 1), (-13.5, 2)):  # candles on the steps
        y0 = FLOOR_Y - 2.4 * (k % 2) + 1.0
        m.limb(V(sx, y0, 6.0 + 3.6 * (k % 2)), V(sx, y0 + 3.0 - k * 0.6, 6.0 + 3.6 * (k % 2)), 0.9, 0.8, WAX)
        m.ell((sx, y0 + 4.0 - k * 0.6, 6.0 + 3.6 * (k % 2)), (0.7, 1.2, 0.7), FIRE, kind="emit")
    # a crystal over the door, in a fork of wood; crystal lanterns on brackets either side
    m.limb(V(-3.5, DOOR_TOP + 3.5, 2.6), V(0, DOOR_TOP + 6.0, 3.2), 0.7, 0.6, BARK_D)
    m.limb(V(3.5, DOOR_TOP + 3.5, 2.6), V(0, DOOR_TOP + 6.0, 3.2), 0.7, 0.6, BARK_D)
    crystal(m, V(0, DOOR_TOP + 5.5, 3.6), 7.0, 1.7)
    for sx in (-17.0, 17.0):
        m.limb(V(sx, DOOR_TOP - 3, 1.5), V(sx, DOOR_TOP - 3, 7.0), 0.5, 0.45, IRON)
        m.limb(V(sx, DOOR_TOP - 3, 7.0), V(sx, DOOR_TOP - 6.5, 7.0), 0.3, 0.3, ROPE)
        for k in range(4):
            a = k * 1.57 + 0.78
            log(m, V(sx + math.cos(a) * 2.2, DOOR_TOP - 13.5, 7.0 + math.sin(a) * 2.2), V(sx + math.cos(a) * 2.2, DOOR_TOP - 7.0, 7.0 + math.sin(a) * 2.2), 0.4, BARK_D, step=0.8)
        crystal(m, V(sx, DOOR_TOP - 13.0, 7.0), 5.5, 1.3)
    # the big lens window: a ring of dark wood, a milky dome, a teal heart (the basin's light inside)
    lx, ly, lr = LENS
    for k in range(36):
        a = k / 36 * math.tau
        m.ell((lx + math.cos(a) * (lr + 0.6), ly + math.sin(a) * (lr + 0.6), 1.8), (1.6, 1.6, 1.6), BARK_D)
    m.ell((lx, ly, 0.4), (lr - 0.4, lr - 0.4, 2.6), MOON)
    m.ell((lx + 0.5, ly - 0.6, 2.2), (lr * 0.55, lr * 0.5, 1.0), h.TEAL, kind="emit")
    m.ell((lx - lr * 0.45, ly + lr * 0.45, 2.8), (1.4, 1.0, 0.5), MIRROR)
    m.limb(V(lx - lr, ly - lr - 1.5, 3.3), V(lx + lr, ly - lr - 1.2, 3.3), 1.0, 1.0, PLANK_W)
    # the small round window: dark, a candle-warm speck
    sx_, sy_, sr_ = SMALL
    for k in range(24):
        a = k / 24 * math.tau
        m.ell((sx_ + math.cos(a) * (sr_ + 0.5), sy_ + math.sin(a) * (sr_ + 0.5), 1.8), (1.2, 1.2, 1.2), BARK_D)
    m.ell((sx_, sy_, -0.2), (sr_ - 0.3, sr_ - 0.3, 0.6), GAP)
    m.ell((sx_ + 0.6, sy_ - 0.8, 0.4), (2.2, 2.0, 0.5), FIRE, kind="emit")
    # mirror shards facing the void (south), a fishing net with floats on the left of the wall
    for k, (mx, my) in enumerate(((-46.0, FLOOR_Y + 30), (-20.0, FLOOR_Y + 37), (45.0, FLOOR_Y + 34))):
        m.limb(V(mx, my + 5, 2.2), V(mx, my + 1.5, 3.0), 0.25, 0.25, ROPE)
        m.ell((mx, my, 3.4), (1.8 - 0.2 * k, 2.6, 0.5), MIRROR, R=h.rot_x(0.3))
    for k in range(7):
        y = FLOOR_Y + 8 + k * 4.0
        m.limb(V(-47, y, 2.2), V(-38, y - 2.0, 2.2), 0.18, 0.18, ROPE, step=0.4)
        m.limb(V(-47 + k * 1.4, FLOOR_Y + 6, 2.2), V(-46 + k * 1.4, FLOOR_Y + 33, 2.4), 0.18, 0.18, ROPE, step=0.4)
    for k in range(3):
        m.ell((-44 + k * 3.0, FLOOR_Y + 12 + k * 7, 2.8), (1.3, 1.3, 1.1), MOON if k % 2 else GLASS)
    # the roof: hipped, deep overhang, rounded hips, streaked reed
    eave_h, ridge_h = WALL_TOP + 1.0, WALL_TOP + 34.0
    xr, zr, rx = HALF + 11.0, DEPTH / 2 + 13.0, HALF - 18.0
    streak = {}
    xx = -xr
    while xx <= xr:
        zz = -DEPTH / 2 - zr
        while zz <= -DEPTH / 2 + zr:
            got = roof_height(xx, zz, eave_h, ridge_h, xr, zr, rx)
            if got is not None:
                y, a, b = got
                along = xx if a <= b else zz * 1.7  # the strands run downhill: on the front/back across x, on the hips across z
                key = int((along + 200) / 1.3)
                if key not in streak:
                    streak[key] = fbm(key * 0.9, 3.0, 11)
                tone = streak[key] + (fbm(xx * 0.05, zz * 0.08, 13) - 0.5) * 0.6
                bulge = 1.2 * math.sin(math.pi * min(1.0, min(a, b) * 1.6)) if min(a, b) < 0.62 else 1.2
                if a <= b:  # the front slope faces the viewer (and the light from the front left)
                    mat = REED if tone > 0.47 else REED_D
                elif xx > 0:  # the right hip turns away from the light: in shade
                    mat = REED_D if tone > 0.55 else REED_S
                else:  # the left hip faces the light
                    mat = REED_L if tone > 0.5 else REED
                if min(a, b) < 0.07:
                    mat = REED_S if xx > 0 and b < a else REED_D  # the cut lip is darker
                m.ell((xx, y + bulge, zz), (1.0, 1.1, 1.0), mat)
            zz += 1.15
        xx += 1.15
    for k in range(int((2 * xr) / 1.4)):  # the ragged lip of cut reed ends along the front eave and the right hip
        x0 = -xr + k * 1.4
        ln = rng.uniform(2.5, 4.5)
        m.limb(V(x0, eave_h + 0.6, zr - DEPTH / 2 + 0.2), V(x0 + rng.uniform(-0.3, 0.3), eave_h - ln, zr - DEPTH / 2 + 1.0), 0.9, 0.65, REED_D)
    for k in range(int(2 * zr / 1.4)):
        z0 = -DEPTH / 2 - zr + k * 1.4
        ln = rng.uniform(2.5, 4.5)
        m.limb(V(xr - 0.2, eave_h + 0.6, z0), V(xr + 0.8, eave_h - ln, z0 + rng.uniform(-0.3, 0.3)), 0.9, 0.65, REED_D)
    for _ in range(70):  # moss cushions, more up toward the ridge
        xx, zz = rng.uniform(-xr + 4, xr - 4), rng.uniform(-DEPTH / 2 - zr + 4, -DEPTH / 2 + zr - 4)
        got = roof_height(xx, zz, eave_h, ridge_h, xr, zr, rx)
        if got is not None and min(got[1], got[2]) > 0.25:
            m.ell((xx, got[0] + 2.0, zz), (rng.uniform(1.6, 4.0), 0.8, rng.uniform(1.4, 3.0)), MOSS_L if rng.random() < 0.18 else MOSS)
    for _ in range(18):  # hanging strands of moss from the front eave
        x0 = rng.uniform(-xr + 4, xr - 4)
        m.limb(V(x0, eave_h - 2.5, zr - DEPTH / 2 + 1.0), V(x0, eave_h - rng.uniform(4, 8), zr - DEPTH / 2 + 1.4), 0.4, 0.15, MOSS)
    log(m, V(-rx, ridge_h + 2.0, -DEPTH / 2), V(rx, ridge_h + 1.4, -DEPTH / 2), 2.6, REED_D, step=1.1)  # the ridge roll, bound with rope
    for k in range(6):
        bx = -rx + 3 + k * (2 * rx - 6) / 5
        m.limb(V(bx, ridge_h - 0.6, -DEPTH / 2 + 2.4), V(bx, ridge_h + 4.4, -DEPTH / 2 + 1.0), 0.45, 0.45, ROPE)
    for k in range(5):
        cx = -rx + 10 + k * (2 * rx - 6) / 5
        crystal(m, V(cx, ridge_h + 3.6, -DEPTH / 2), rng.uniform(3.5, 6.0), rng.uniform(1.0, 1.4), lean=(rng.uniform(-0.15, 0.15), 0.0))
    # the crescent-moon pole at the ridge's right end
    pole = V(rx - 1.0, ridge_h + 3.0, -DEPTH / 2)
    log(m, pole, pole + V(0.6, 16.0, 0), 0.8, BARK_D, step=0.8)
    for k in range(13):
        a = math.radians(-130 + k * 20)
        m.ell(pole + V(0.6 + math.cos(a) * 4.6, 21.0 + math.sin(a) * 4.6, 0.2), (1.1 - abs(k - 6) * 0.07, 1.1 - abs(k - 6) * 0.07, 0.8), MOON)
    m.ell(pole + V(4.4, 21.0, 0.8), (0.6, 0.6, 0.5), h.TEAL, kind="emit")
    # a cluster of grown crystal bursting through the roof's left front, the reed torn round it
    base = V(-28.0, 0, -9.0)
    got = roof_height(base[0], base[2], eave_h, ridge_h, xr, zr, rx)
    base[1] = got[0] - 2.0
    for k in range(10):
        a = k / 10 * math.tau
        m.limb(base + V(math.cos(a) * 5.0, 1.5, math.sin(a) * 4.0), base + V(math.cos(a) * 7.0, 4.5, math.sin(a) * 5.5), 0.9, 0.5, REED_D)
    crystal(m, base, 36.0, 4.8, lean=(0.10, 0.05))
    for dx, dz, ht, r, lx_ in ((-6.0, 2.0, 18.0, 2.8, -0.38), (5.5, 2.5, 22.0, 3.0, 0.3), (1.0, -4.5, 14.0, 2.4, 0.1), (-3.0, 5.0, 11.0, 2.0, -0.2), (7.5, -1.0, 9.0, 1.6, 0.45)):
        crystal(m, base + V(dx, 0.5, dz), ht, r, lean=(lx_, 0.12))
    # bottles and bundles hanging under the front eave
    for k, x0 in enumerate(np.linspace(-HALF + 6, HALF - 6, 9)):
        if abs(x0) < 14:
            continue
        drop = rng.uniform(3.0, 7.0)
        zf = zr - DEPTH / 2 - 2.5
        m.limb(V(x0, eave_h - 1.0, zf), V(x0, eave_h - drop, zf), 0.15, 0.15, ROPE, step=0.4)
        if k % 2:
            m.ell((x0, eave_h - drop - 2.0, zf), (1.4, 2.0, 1.4), GLASS)
            m.ell((x0, eave_h - drop - 2.3, zf + 0.9), (0.7, 1.0, 0.5), h.VIOLET if k % 4 == 1 else h.TEAL, kind="emit")
        else:
            m.limb(V(x0, eave_h - drop, zf), V(x0, eave_h - drop - 5.0, zf), 1.3, 0.6, REED if k % 3 else MOSS)
    # the chimney: crooked stones at the back right, rising out of the thatch
    for k in range(34):
        y = WALL_TOP + 12 + k * 1.15
        px = 24.0 + 0.10 * k
        for j in range(3):
            m.ell((px + rng.uniform(-3.4, 3.4), y, -26.0 + rng.uniform(-2.6, 2.6)), (rng.uniform(2.2, 3.2), 2.0, rng.uniform(2.0, 2.8)), (STONE, STONE_L, STONE)[int(rng.integers(0, 3))])
    m.ell((27.4, WALL_TOP + 51.5, -26.0), (4.8, 1.4, 4.0), STONE_L)
    m.ell((27.4, WALL_TOP + 52.5, -26.0), (2.6, 0.5, 2.0), GAP)
    # glowing crystals at the foot of the stilts, reeds growing round them
    for k in range(5):
        crystal(m, V(-HALF + 6 + k * 3.4, 0.0, 6.0 + (k % 2) * 1.5), rng.uniform(2.0, 4.0), 0.9)
    for k in range(9):
        bx = HALF - 4 + rng.uniform(-4, 6)
        m.limb(V(bx + 3, 0, 3.0 - k * 1.2), V(bx + 3 + rng.uniform(-1, 1), rng.uniform(7, 13), 3.4 - k * 1.2), 0.45, 0.2, REED)
    turned(m)
    arr = to_array(render(m, FW, FH, GROUND))
    arr = grain(arr, 41, along=(0.0, 1.0), amount=0.6, mats=(BONE, BONE_D, BARK, BARK_D))
    arr = grain(arr, 42, along=(0.0, 1.0), amount=0.5, mats=(REED, REED_D))
    # where the door and the lens are (the leaf is its own sprite)
    mk = h.Model()
    mk.ell((0, FLOOR_Y + DOOR_TOP / 2 - 2, -3.6), (DOOR_X[1] + 2.5, DOOR_TOP / 2 - 1, 0.8), GAP)
    DOOR_INFO["box"] = gap_box(turned(mk), FW, FH, GROUND)
    ml = h.Model()
    ml.ell((lx, ly, 0.4), (lr - 0.4, lr - 0.4, 2.6), MOON)
    global LENS_BOX
    b = gap_box(turned(ml), FW, FH, GROUND)
    LENS_BOX = (b[0], b[2], b[1], b[3])
    return soft_shadow(arr, FW / 2, GROUND - 6, 78, 16, 70), GROUND


def lens_spill():
    """The teal light that leaves the lens window at night: a bloom round the glass and a pool on the yard in front."""
    x0, x1, y0, y1 = LENS_BOX
    cx = (x0 + x1) / 2
    return pool_spill(FW, FH, LENS_BOX, [(cx + 2, GROUND + 9, 22, 7, 0.85), (cx + 4, GROUND + 20, 14, 4, 0.45)], reach=7, color=(120, 240, 226), seed=43, bloom=0.5)


# ------------------------------------------------------------------ the yard
def jetty_arr():
    """The jetty: a short walk of grey bone-wood boards on hag elm posts, running north from the shore into the shallow water, a mooring post with rope,
    a lantern pole at its end with a hanging crystal (glow). Drawn flat (it lies under the walkers, z -2). 56 x 116, ground row 104 (the near, shore end)."""
    rng = rng_for(51)
    m = h.Model()
    L = 92.0
    for k in range(int(L / 3.1)):  # boards across, receding north (-z)
        z = 2.0 - k * 3.1
        mat = BONE_D if rng.random() < 0.55 else (PLANK_W if rng.random() < 0.5 else BONE)
        slab(m, V(-12.5 + rng.uniform(-0.6, 0.6), 3.0, z), V(12.5 + rng.uniform(-0.6, 0.6), 3.0, z + rng.uniform(-0.3, 0.3)), 1.35, 0.7, mat, (0, 1, 0), step=1.2)
    for sx in (-1, 1):  # side beams and posts
        log(m, V(sx * 13.5, 2.2, 3.0), V(sx * 13.5, 2.2, -L + 1), 1.4, BARK_D, step=1.1)
        for k in range(5):
            z = 1.0 - k * (L / 4.2)
            log(m, V(sx * 14.2, -3.0, z), V(sx * 14.2, 5.0, z), 1.8, BARK_D, step=1.0)
            m.ell((sx * 14.2, 5.4, z), (1.9, 0.6, 1.9), BONE_D)
    log(m, V(-15, 0, -L + 2), V(-15, 14, -L + 2), 1.5, BARK_D, step=1.0)  # the lantern pole
    m.limb(V(-15, 14, -L + 2), V(-9, 15, -L + 2), 0.5, 0.45, BARK_D)
    m.limb(V(-9, 15, -L + 2), V(-9, 12, -L + 2), 0.2, 0.2, ROPE)
    crystal(m, V(-9, 9.5, -L + 2), 3.0, 1.0)
    for k in range(6):  # rope coiled on a board, a bucket of moonstones
        a = k * 1.1
        m.ell((7 + math.cos(a) * 2.2, 3.9, -40 + math.sin(a) * 1.6), (1.2, 0.5, 1.0), ROPE)
    m.ell((-6, 5.5, -20), (3.0, 2.6, 2.6), BONE_D)
    for k in range(5):
        m.ell((-6 + rng.uniform(-1.6, 1.6), 8.0, -20 + rng.uniform(-1.4, 1.4)), (1.1, 0.8, 1.0), MOON)
    arr = to_array(render(m, 56, 116, 104, pitch=40.0))
    return grain(arr, 52, along=(1.0, 0.0), amount=0.6, mats=(BONE, BONE_D, PLANK_W, BARK_D)), 104


def boat_arr():
    """A small flat-bottomed punt of bone wood lying in the shallows by the jetty, a pole across it, a crate of crystals. 56 x 32, ground row 24."""
    rng = rng_for(53)
    m = h.Model()
    for k in range(17):  # hull: a long, flat bowl
        x = -20 + k * 2.5
        w = 6.5 * math.sin(math.pi * (k + 0.5) / 17) ** 0.6 + 1.0
        m.ell((x, 2.6, 0), (1.6, 2.2, w), BONE_D)
        m.ell((x, 3.6, 0), (1.5, 1.2, w - 1.2), GAP)
    log(m, V(-20, 4.4, 0), V(20, 4.4, 0), 0.7, BONE, step=1.0)
    for z in (-5.4, 5.4):
        log(m, V(-17, 4.6, z * 0.8), V(17, 4.6, z), 0.6, BONE, step=1.0)
    log(m, V(-22, 5.6, -3), V(24, 6.4, 4), 0.5, BARK_D, step=0.9)  # the pole
    m.ell((6, 5.0, 0), (3.4, 2.0, 2.6), PLANK_W)
    for k in range(3):
        crystal(m, V(5 + k * 1.6, 6.6, -0.5 + k * 0.4), 2.2 + k * 0.4, 0.7)
    arr = to_array(render(m, 56, 32, 24))
    return grain(arr, 54, mats=(BONE, BONE_D, PLANK_W)), 24


def wheel_arr():
    """The treadle grinding wheel under the lean-to: a stone wheel in a frame of hag elm, a treadle, a trough of water under it, glittering grinding dust,
    a basket of moonstones beside it. 48 x 48, ground row 40."""
    rng = rng_for(55)
    m = h.Model()
    for sz in (-1, 1):  # the frame: two A-legs of hag elm either side of the wheel (front and back), the axle runs toward the viewer
        log(m, V(-8, 0, sz * 4.5), V(0, 16, sz * 4.5), 1.3, BARK_D, step=0.9)
        log(m, V(8, 0, sz * 4.5), V(0, 16, sz * 4.5), 1.3, BARK_D, step=0.9)
    log(m, V(0, 15, -5.5), V(0, 15, 5.5), 0.7, IRON, step=0.6)
    for k in range(32):  # the wheel: a stone disc facing the viewer, its rim lit
        a = k / 32 * math.tau
        m.ell((math.cos(a) * 8.6, 15 + math.sin(a) * 8.6, 0), (1.7, 1.7, 1.9), STONE_L if math.sin(a) > -0.2 else STONE)
    m.ell((0, 15, 0), (7.6, 7.6, 1.6), STONE)
    m.ell((0, 15, 1.8), (1.4, 1.4, 0.6), IRON)
    for k in range(4):  # the crank and the spokes of glittering dust
        a = k / 4 * math.tau + 0.3
        m.ell((math.cos(a) * 4.6, 15 + math.sin(a) * 4.6, 1.5), (0.5, 0.5, 0.3), MOON)
    m.limb(V(0, 15, 6.0), V(3.6, 12.0, 6.2), 0.45, 0.45, IRON)
    slab(m, V(-6, 3.5, 4), V(6, 3.5, 4), 4.0, 1.2, BONE_D, (0, 1, 0))  # the trough
    m.ell((0, 4.4, 4), (5.0, 0.4, 3.2), GLASS)
    slab(m, V(-10, 1.6, 9), V(8, 2.6, 7), 1.6, 0.6, BARK, (0, 1, 0))  # the treadle
    for _ in range(26):  # grinding dust that glitters (some teal specks glow)
        p = (rng.uniform(-12, 12), 0.4, rng.uniform(-6, 12))
        if rng.random() < 0.25:
            m.ell(p, (0.45, 0.3, 0.45), h.TEAL, kind="emit")
        else:
            m.ell(p, (rng.uniform(0.6, 1.4), 0.3, rng.uniform(0.6, 1.2)), MOON)
    for k in range(4):  # a basket of moonstones on the right
        a = k / 4 * math.tau
        m.ell((15 + math.cos(a) * 3.2, 3.0, 6 + math.sin(a) * 2.6), (1.6, 3.0, 1.6), STRAW)
    for k in range(6):
        m.ell((15 + rng.uniform(-2.2, 2.2), 6.2, 6 + rng.uniform(-1.6, 1.6)), (1.2, 0.9, 1.1), MOON)
    arr = to_array(render(scaled(m, 1.45), 72, 64, 54))
    return soft_shadow(grain(arr, 56, mats=(BARK_D, BONE_D)), 36, 55, 28, 5, 70), 54


def rack_arr():
    """A drying rack: two forked posts, a cross pole, strings of crystals and a few moonstones in nets hanging from it (the strings are the swaying layer
    `rack_strings`). 64 x 52, ground row 46."""
    m = h.Model()
    for sx in (-1, 1):
        log(m, V(sx * 22, 0, 0), V(sx * 21, 24, 0), 1.3, BARK_D, step=0.9)
        m.limb(V(sx * 21, 22, 0), V(sx * 19, 27, 0), 0.7, 0.5, BARK_D)
        m.limb(V(sx * 21, 22, 0), V(sx * 23.5, 27, 0), 0.7, 0.5, BARK_D)
    log(m, V(-24, 25, 0), V(24, 25.4, 0), 1.0, BONE_D, step=0.9)
    arr = to_array(render(m, 64, 52, 46))
    return soft_shadow(arr, 32, 47, 24, 3, 60), 46


def rack_strings_arr():
    """The strings of the drying rack: crystals on strings, a net with moonstones, a bundle of reeds, one mirror shard; same frame as rack_arr."""
    rng = rng_for(58)
    m = h.Model()
    for k, x in enumerate(np.linspace(-18, 18, 7)):
        ln = rng.uniform(7, 14)
        m.limb(V(x, 25, 0.6), V(x, 25 - ln, 0.6), 0.2, 0.2, ROPE, step=0.4)
        kind = k % 3
        if kind == 0:
            crystal(m, V(x, 25 - ln - 4.0, 0.6), 4.0, 0.9, emit=True)
        elif kind == 1:
            for j in range(3):
                m.ell((x + rng.uniform(-0.8, 0.8), 25 - ln - 1.2 - j * 1.7, 0.8), (1.2, 0.9, 1.0), MOON)
            m.limb(V(x - 1.6, 25 - ln, 1.0), V(x, 25 - ln - 6.0, 1.0), 0.15, 0.15, ROPE)
            m.limb(V(x + 1.6, 25 - ln, 1.0), V(x, 25 - ln - 6.0, 1.0), 0.15, 0.15, ROPE)
        else:
            m.ell((x, 25 - ln - 2.0, 0.8), (1.2, 2.4, 0.5), MIRROR)
    arr = to_array(render(m, 64, 52, 46))
    return arr


def chimes_arr():
    """The crystal wind chimes that hang under the eave: a bar of bone wood, nine strings of different lengths, each a slim crystal at its end
    (teal hearts); the bar row is the pivot (hut.gd LOOKS hangs). 40 x 28, pivot row 2."""
    rng = rng_for(59)
    m = h.Model()
    log(m, V(-16, 26, 0), V(16, 26, 0), 0.9, BONE_D, step=0.8)
    for k, x in enumerate(np.linspace(-14, 14, 9)):
        ln = 6 + 7 * abs(math.sin(k * 1.3)) + rng.uniform(0, 2)
        m.limb(V(x, 26, 0.4), V(x, 26 - ln, 0.4), 0.14, 0.14, ROPE, step=0.35)
        crystal(m, V(x, 26 - ln - 4.6, 0.4), 4.6, 0.75, emit=k % 2 == 0)
    return to_array(render(m, 40, 30, 28, pitch=10.0))


WARD_FW, WARD_FH, WARD_GROUND = 64, 112, 100


def ward_arr(variant, awake, seed=60):
    """A ward stone (Bannstein): a half-sunk stele of the waystones' violet stone, a grown crystal head, runes. Variants: 0 tall, 1 leaning, 2 cracked and
    scorched (the void side). Dormant: dull glass, cold runes; awake: teal heart, glowing runes, a ring of small crystals at the foot. 40 x 60, ground 52."""
    rng = rng_for(seed + variant * 7)
    m = h.Model()
    lean = (0.0, 0.0) if variant == 0 else ((0.10, 0.04) if variant == 1 else (-0.07, 0.0))
    height = (26.0, 22.0, 19.0)[variant]
    stone = WSTONE_D if variant == 2 else WSTONE
    for k in range(int(height / 1.2)):
        t = k / (height / 1.2)
        w = 5.6 * (1.0 - 0.28 * t) + 0.5 * math.sin(k * 1.7)
        m.ell((lean[0] * height * t, 1.0 + k * 1.2, lean[1] * height * t), (w, 1.0, w * 0.62), stone if (k * 7 + variant) % 5 else WSTONE_D)
    top = V(lean[0] * height, height + 0.8, lean[1] * height)
    m.ell(top, (4.4, 1.6, 3.0), stone)
    crystal(m, top + V(0, 0.6, 0), 9.0 if variant != 2 else 6.5, 2.1, lean=(lean[0] * 0.8, lean[1]), emit=awake, mat=GLASS if awake else WSTONE_D)
    for k in range(4):  # runes on the face: short strokes, cold when dormant
        y = 5.0 + k * (height - 9) / 3.5
        x0 = lean[0] * y - 1.6 + (k % 2) * 0.8
        mat, kind = (h.TEAL, "emit") if awake else (WSTONE_D, "")
        m.limb(V(x0, y, 3.4 + lean[1] * y), V(x0 + 3.0, y + 0.8 * (1 if k % 2 else -1), 3.4 + lean[1] * y), 0.32, 0.32, mat, kind=kind)
    if variant == 2:  # a crack with the void in it
        p = V(1.2, 3.0, 3.6)
        for s in range(9):
            q = p + V(rng.uniform(-0.9, 0.9), rng.uniform(1.2, 2.0), 0)
            m.limb(p, q, 0.32, 0.28, h.VIOLET if awake else GAP, kind="emit" if awake else "")
            p = q
    for _ in range(5):  # moss and lichen at the foot, stones around
        m.ell((rng.uniform(-6, 6), rng.uniform(1, 4), 3.5), (rng.uniform(1.4, 3), 0.6, 1.0), MOSS_L if rng.random() < 0.4 else MOSS)
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        m.ell((math.cos(a) * 8.0, 0.8, math.sin(a) * 5.0), (2.0, 1.2, 1.6), STONE_L if k % 2 else STONE)
    if awake:
        for k in range(3):
            a = k / 3 * math.tau + 1.1
            crystal(m, V(math.cos(a) * 7.0, 0.0, math.sin(a) * 4.4), 2.6, 0.7)
        tip = top + V(lean[0] * 9.0, (9.0 if variant != 2 else 6.5) + 4.0, 0)
        for k in range(3):  # shards of crystal hovering over the head, held by the light
            a = k / 3 * math.tau + 0.5
            m.ell(tip + V(math.cos(a) * 3.6, 1.0 + k * 1.3, math.sin(a) * 2.0), (0.7, 1.5, 0.7), h.TEAL, kind="emit")
    else:  # dormant: soot of the void creeping up from the foot
        for _ in range(6):
            m.ell((rng.uniform(-4, 4), rng.uniform(1, 6), 3.6), (rng.uniform(1.0, 2.2), rng.uniform(0.8, 1.8), 0.6), GAP)
    arr = to_array(render(scaled(m, 1.75), WARD_FW, WARD_FH, WARD_GROUND))
    return soft_shadow(arr, WARD_FW / 2, WARD_GROUND + 1, 18, 4, 70)


def ward_sheet():
    """3 variants x 2 states (row 0 dormant, row 1 awake)."""
    sheet = np.zeros((WARD_FH * 2, WARD_FW * 3, 4), np.uint8)
    for row, awake in enumerate((False, True)):
        for v in range(3):
            sheet[row * WARD_FH:(row + 1) * WARD_FH, v * WARD_FW:(v + 1) * WARD_FW] = ward_arr(v, awake)
    return sheet


def glimmer_arr():
    """The lake stones as pickups (docs/seehexe_konzept.md 6), 4 frames of 20 x 18, ground row 14: 0-1 Seeglimmer (small clusters of grown crystals in the
    shallows: glow), 2-3 Seemondstein (milky round pebbles on the dry shore)."""
    sheet = np.zeros((18, 80, 4), np.uint8)
    for f in range(4):
        rng = rng_for(70 + f)
        m = h.Model()
        if f < 2:
            for k in range(2 + f):
                a = k * 2.1 + f
                crystal(m, V(math.cos(a) * 2.0, 0.0, math.sin(a) * 1.6), rng.uniform(3.0, 5.0), rng.uniform(0.8, 1.1), lean=(rng.uniform(-0.25, 0.25), rng.uniform(-0.1, 0.1)))
            m.ell((0, 0.4, 0), (3.4, 0.6, 2.4), STONE)
        else:
            for k in range(1 + (f - 2) * 2):
                m.ell((k * 2.6 - (f - 2) * 2.6, 1.3, (k % 2) * 1.2), (2.0 - 0.3 * k, 1.4, 1.6 - 0.2 * k), MOON)
            m.ell((-0.6, 2.2, 1.0), (0.6, 0.4, 0.5), h.TEAL, kind="emit")
        arr = to_array(render(m, 20, 18, 14))
        sheet[:, f * 20:(f + 1) * 20] = soft_shadow(arr, 10, 15, 5, 2, 60)
    return sheet


# the item icons (16 x 16, lit from the top left, outline 1b1a2e; checked like tools/art_bush.py check_icon)
ICON_PAL = {"o": "1b1a2e", "a": "0c2a32", "b": "1a5058", "c": "3a8a8c", "d": "8ad8d0", "e": "e8fff8", "s": "2a2740", "t": "46456a", "u": "6f6f96",
            "m": "4a5266", "n": "8a94a8", "p": "c4cad8", "q": "eef0f6", "r": "c8a8d8", "g": "a8e0d0"}
ICON_GLIMMER = [
    "................",
    "........o.......",
    ".......oeo......",
    "...o...odco.....",
    "..odo..odcbo....",
    "..odeo.odcbo....",
    "..odcbo.dcbo..o.",
    "...dcbo.dcbo.oe.",
    "...odcbodcbo.od.",
    "...odcbbdcboodc.",
    "..osodcbbcbodcb.",
    ".ostuodcbbbbcbo.",
    ".ostuuudcbbbbbo.",
    ".ossttuuussssso.",
    "..ooooooooooooo.",
    "................",
]
ICON_MOONSTONE = [
    "................",
    "................",
    "......oooo......",
    "....ooqqppoo....",
    "...oqqeqppnno...",
    "..oqqqqppgnnmo..",
    "..oqqppppnnrmo..",
    ".oqpppppnnrrnmo.",
    ".opppppnnnrnmmo.",
    ".oppppnnnnnmmmo.",
    "..onpnnnnnmmmo..",
    "..onnnnnmmmmmo..",
    "...ommmmmmmmo...",
    "....oommmmoo....",
    "......oooo......",
    "................",
]


def icon(name, rows):
    arr = np.zeros((16, 16, 4), np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                c = hexc(ICON_PAL[ch])
                arr[y, x] = (c[0], c[1], c[2], 255)
    pts = {(x, y) for y in range(16) for x in range(16) if arr[y, x, 3]}
    assert min(x for x, _ in pts) >= 1 and max(x for x, _ in pts) <= 14 and min(y for _, y in pts) >= 1 and max(y for _, y in pts) <= 14, name + " leaves the frame"
    seen, stack = set(), [next(iter(pts))]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        stack += [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (x + dx, y + dy) in pts]
    assert len(seen) == len(pts), name + " has loose pixels"
    return arr


# ------------------------------------------------------------------ the room
FLOOR = (256, 176)
DOOR_GAP = (120, 168)  # shell px (the shell is FLOOR_W + 32 wide)


def witchy(arr, light):
    """Her room's wood: the hut's planks pulled toward a cool, dark plum-indigo (lake light and old smoke), the glowing pixels left alone."""
    out = arr.copy()
    glow = glow_of(arr, GLOWS)[..., 3] > 0
    rgb = out[..., :3].astype(float)
    lum = rgb.mean(axis=2, keepdims=True)
    tint = np.array([0.78, 0.74, 1.0])
    rgb = (rgb * 0.55 + lum * 0.45) * tint * light
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    keep = (out[..., 3] > 0) & ~glow
    out[..., :3][keep] = rgb[keep]
    return out


def room_shell():
    room.configure(floor=FLOOR, holes=[], sapling=(-999, -999), damp=(256, 0), windows=[], hole_wall=None,
                   pilasters=(room.SIDE_W + 92,), door_gap=DOOR_GAP, hearth=[(14, 0, 82, 26)], hearth_at=(48, 12))
    put("floor", witchy(room.floor_arr(seed=81), 0.62), glow=False)
    put("wall", witchy(room.back_wall_arr(seed=83), 0.7))
    put("side", witchy(room.side_arr(seed=85), 0.7))
    put("front", witchy(room.front_arr(seed=87), 0.72))
    put("door", room.door_arr(48, 40, seed=89))
    put("rays", fx.rays_arr(), glow=False)


def counter_arr():
    """The counter by the door: a low table of bone wood, a velvet board with stones laid out, a balance, a loupe on a stand, a lamp crystal. 64 x 44, ground 36."""
    rng = rng_for(91)
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 22, 0, sz * 6), V(sx * 22, 12, sz * 6), 1.2, BARK_D, step=0.9)
    slab(m, V(-25, 13.2, 0), V(25, 13.2, 0), 8.0, 1.0, BONE, (0, 1, 0))
    slab(m, V(-16, 14.4, 1), V(2, 14.4, 1), 4.6, 0.3, h.COAT if hasattr(h, "COAT") else SHUT, (0, 1, 0))
    for k in range(6):
        if k % 2:
            m.ell((-14 + k * 3.0, 15.0, 1 + rng.uniform(-2, 2)), (0.9, 0.6, 0.8), MOON)
        else:
            crystal(m, V(-14 + k * 3.0, 14.6, 1 + rng.uniform(-2, 2)), 2.4, 0.6)
    log(m, V(12, 13.5, -2), V(12, 21, -2), 0.4, IRON, step=0.5)  # balance
    log(m, V(7, 21, -2), V(17, 21, -2), 0.3, IRON, step=0.5)
    for sx in (7, 17):
        m.ell((sx, 18.6, -2), (2.0, 0.4, 2.0), h.GOLD)
    m.limb(V(20, 13.8, 3), V(20, 18, 3), 0.3, 0.3, IRON)  # loupe
    m.ell((20, 19.6, 3.2), (1.6, 1.6, 0.4), MIRROR)
    crystal(m, V(-22, 14, -4), 4.0, 1.1)
    arr = to_array(render(m, 64, 44, 36))
    return soft_shadow(grain(arr, 92, mats=(BONE, BONE_D, BARK_D)), 32, 37, 26, 4, 70), 36


def grind_arr():
    """The grinding table at the lens window: a heavy bench, a small hand-wheel, polishing bowls, glittering dust, half-cut moonstones. 64 x 48, ground 40."""
    rng = rng_for(93)
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 24, 0, sz * 7), V(sx * 24, 13, sz * 7), 1.5, BARK_D, step=0.9)
    slab(m, V(-27, 14.4, 0), V(27, 14.4, 0), 9.0, 1.4, BONE_D, (0, 1, 0))
    for k in range(20):  # the small wheel
        a = k / 20 * math.tau
        m.ell((-12, 22 + math.sin(a) * 5.6, math.cos(a) * 5.6), (1.6, 1.2, 1.2), STONE_L if k % 3 else STONE)
    m.ell((-12, 22, 0), (1.4, 4.6, 4.6), STONE)
    log(m, V(-16, 16, 0), V(-16, 22, 0), 0.7, BARK_D, step=0.6)
    m.limb(V(-9, 22, 0), V(-6, 25, 2), 0.4, 0.4, IRON)  # crank
    for k, (x, z) in enumerate(((4, -3), (12, 2), (20, -2))):  # bowls with stones
        m.ell((x, 16.4, z), (3.2, 1.4, 2.6), CLAY)
        m.ell((x, 17.4, z), (2.4, 0.4, 1.9), GAP)
        m.ell((x, 17.9, z), (1.0, 0.6, 0.9), MOON if k != 1 else GLASS)
    for _ in range(18):
        p = (rng.uniform(-24, 24), 16.0, rng.uniform(-7, 7))
        if rng.random() < 0.3:
            m.ell(p, (0.4, 0.3, 0.4), h.TEAL, kind="emit")
        else:
            m.ell(p, (0.7, 0.25, 0.6), MOON)
    arr = to_array(render(m, 64, 48, 40))
    return soft_shadow(grain(arr, 94, mats=(BONE_D, BARK_D)), 32, 41, 28, 4, 70), 40


def carve_arr():
    """The carving bench: a long low bench with a vise, two staff blanks of hag elm (one half carved, a crown of twigs), a coil of curse-silver wire, shavings.
    72 x 44, ground 36."""
    rng = rng_for(95)
    m = h.Model()
    for sx in (-1, 1):
        log(m, V(sx * 28, 0, 0), V(sx * 26, 10, 0), 1.6, BARK_D, step=0.9)
    slab(m, V(-31, 11.0, 0), V(31, 11.0, 0), 6.5, 1.3, BONE_D, (0, 1, 0))
    for k in range(3):  # the vise
        m.ell((-20, 13 + k * 1.4, 0), (2.6, 0.8, 4.4 - k * 0.6), IRON)
    log(m, V(-22, 15, 0), V(14, 16.5, 0.5), 1.2, BARK_D, step=0.7)  # a blank in the vise
    for k in range(5):
        a = k / 5 * math.tau
        m.limb(V(14, 16.5, 0.5), V(18 + math.cos(a) * 1.2, 19 + math.sin(a) * 2.0, 0.5 + math.sin(a)), 0.45, 0.25, BARK_D)
    p = V(-10, 16.0, 1.4)
    for s in range(6):
        q = p + V(2.6, 0.2, 0)
        m.limb(p + V(0, 0.4, 0.6), q + V(0, 0.4, 0.6), 0.4, 0.4, h.VIOLET, kind="emit")
        p = q
    log(m, V(-28, 12.4, -4.5), V(20, 12.6, -5.0), 0.9, BARK, step=0.7)  # a second blank lying back
    for k in range(7):  # silver wire coil
        a = k * 0.9
        m.ell((24 + math.cos(a) * 2.6, 12.8, 3 + math.sin(a) * 2.0), (0.9, 0.4, 0.7), h.SILVER if hasattr(h, "SILVER") else MOON)
    for _ in range(26):  # shavings on bench and floor
        y = 12.4 if rng.random() < 0.5 else 0.4
        m.ell((rng.uniform(-30, 30), y, rng.uniform(-6, 8)), (rng.uniform(0.8, 1.6), 0.3, 0.6), BONE)
    arr = to_array(render(m, 72, 44, 36))
    return soft_shadow(grain(arr, 96, mats=(BONE_D, BARK, BARK_D)), 36, 37, 30, 4, 70), 36


def basin_frames():
    """The resonance basin in the floor: a round rim of dressed violet stone with carved runes, lake water, crystals growing in it and one tall crystal out of
    its middle, glowing. Seen steeply from above. 4 frames (the ripples move, the crystals breathe) of 88 x 84, ground row 66."""
    frames = []
    for f in range(4):
        rng = rng_for(97)
        m = h.Model()
        for k in range(40):
            a = k / 40 * math.tau
            m.ell((math.cos(a) * 26, 1.8, math.sin(a) * 17), (3.6, 2.4, 3.0), WSTONE if k % 5 else WSTONE_D, R=h.rot_y(-a))
            if k % 5 == 2:  # a rune cut into the rim, glowing
                m.ell((math.cos(a) * 26, 4.3, math.sin(a) * 17), (1.2, 0.4, 0.6), h.TEAL if k % 10 == 2 else h.VIOLET, kind="emit", R=h.rot_y(-a))
        m.ell((0, 1.0, 0), (24, 1.0, 15.6), GLASS)
        for r in range(3):  # ripples, moving outward with the frame
            rr = 7 + ((r * 6 + f * 2) % 18)
            for k in range(int(rr * 2)):
                a = k / (rr * 2) * math.tau
                if (k + f) % 3:
                    m.ell((math.cos(a) * rr, 1.9, math.sin(a) * rr * 0.66), (0.7, 0.2, 0.5), MOON)
        for k in range(8):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(6, 17)
            crystal(m, V(math.cos(a) * d, 1.0, math.sin(a) * d * 0.66), rng.uniform(3.0, 7.0), rng.uniform(0.9, 1.4),
                    lean=(rng.uniform(-0.25, 0.25), rng.uniform(-0.15, 0.15)), emit=(k + f) % 4 != 0)
        crystal(m, V(0, 1.0, 0), 22.0, 3.2, lean=(0.04, 0.0))  # the heart crystal, taller than a person's knee
        for k in range(3):
            crystal(m, V(math.cos(k * 2.1) * 3.6, 1.0, math.sin(k * 2.1) * 2.4), 10.0 - k * 2, 1.8, lean=(math.cos(k * 2.1) * 0.3, 0.0))
        for k in range(4):  # motes rising from the water, a different height each frame
            a = k * 1.7
            y = 6 + ((f * 5 + k * 7) % 20)
            m.ell((math.cos(a) * 10, y, math.sin(a) * 6), (0.5, 0.5, 0.5), h.TEAL, kind="emit")
        arr = to_array(render(m, 88, 84, 66, pitch=48.0))
        frames.append(arr)
    sheet = np.zeros((84, 88 * 4, 4), np.uint8)
    for f, arr in enumerate(frames):
        sheet[:, f * 88:(f + 1) * 88] = arr
    return sheet, 66


def runes_arr():
    """The circle painted on the floor round the basin: two rings of chalky lake-blue paint, a seven-pointed star between them and runes in the band;
    the paint lines are emissive teal and violet (the glow sheet makes them breathe at night). 160 x 104 (an ellipse, the floor seen at a slant)."""
    W, H = 160, 104
    arr = np.zeros((H, W, 4), np.uint8)
    teal = h.RAMPS[h.TEAL]
    violet = h.RAMPS[h.VIOLET]
    cx, cy = W / 2, H / 2

    def px(x, y, c, a=255):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H:
            arr[y, x] = (c[0], c[1], c[2], a)

    for rx, col in ((76.0, teal[2]), (70.0, teal[1]), (52.0, violet[2])):
        n = int(rx * 7)
        for k in range(n):
            a = k / n * math.tau
            if (k * 7) % 23 < 2:
                continue  # worn gaps in the paint
            px(cx + math.cos(a) * rx, cy + math.sin(a) * rx * 0.62, col)
    pts = [(cx + math.cos(-math.pi / 2 + k * math.tau / 7) * 70, cy + math.sin(-math.pi / 2 + k * math.tau / 7) * 70 * 0.62) for k in range(7)]
    for k in range(7):  # the star: every third point joined
        a, b = pts[k], pts[(k + 3) % 7]
        n = int(math.hypot(b[0] - a[0], b[1] - a[1]))
        for s in range(n):
            if (s // 3) % 5 == 4:
                continue
            t = s / n
            px(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, violet[1] if (s // 9) % 2 else teal[1])
    glyphs = [["#.#", ".#.", "#.#"], ["###", ".#.", ".#."], ["#..", "###", "..#"], [".#.", "###", ".#."], ["##.", "#.#", ".##"], ["#.#", "###", "#.#"]]
    for k in range(18):  # runes in the band between the two outer rings
        a = k / 18 * math.tau + 0.12
        gx, gy = cx + math.cos(a) * 73 - 1, cy + math.sin(a) * 73 * 0.62 - 1
        g = glyphs[k % len(glyphs)]
        for yy, row in enumerate(g):
            for xx, ch in enumerate(row):
                if ch == "#":
                    px(gx + xx, gy + yy, teal[3] if k % 3 == 0 else teal[2])
    for k in range(7):  # a dot of light at each point of the star
        px(pts[k][0], pts[k][1], teal[3])
        px(pts[k][0] + 1, pts[k][1], teal[2])
    return arr


def potions_arr():
    """A tall crooked shelf of hag elm full of bottles and jars: glowing tinctures (teal, violet, witch green), jars of moonstones and crystals,
    a stack of books, candles burned down to stumps, a pickled toadstool, dried reed. 64 x 92, ground 84."""
    rng = rng_for(103)
    m = h.Model()
    for sx in (-26, 26):
        log(m, V(sx, 0, 0), V(sx + rng.uniform(-1, 1), 70, 0), 1.6, BARK_D, step=1.0)
    for r in range(4):
        y = 4 + r * 17.0
        slab(m, V(-28, y, 0), V(28, y + rng.uniform(-1, 1), 0), 6.0, 0.9, BARK, (0, 1, 0))
        x = -23.0
        while x < 22:
            kind = int(rng.integers(0, 6))
            if kind <= 2:  # a bottle with a glowing tincture
                hgt = rng.uniform(5, 9)
                m.limb(V(x, y + 1, 0.6), V(x, y + hgt, 0.6), 1.6, 1.3, GLASS)
                m.limb(V(x, y + hgt, 0.6), V(x, y + hgt + 2.4, 0.6), 0.6, 0.5, GLASS)
                m.ell((x, y + hgt + 2.8, 0.6), (0.7, 0.5, 0.7), CLAY)
                glow = (h.TEAL, h.VIOLET, h.TEAL)[kind]
                m.limb(V(x - 0.2, y + 1.6, 1.8), V(x - 0.2, y + hgt * 0.6, 1.8), 0.9, 0.8, glow, kind="emit")
                x += 4.2
            elif kind == 3:  # a fat jar of moonstones
                m.ell((x + 1.5, y + 4.0, 0.6), (3.0, 3.6, 2.4), GLASS)
                for j in range(3):
                    m.ell((x + 0.6 + j * 1.3, y + 2.6 + (j % 2) * 1.6, 2.2), (0.9, 0.8, 0.6), MOON)
                m.ell((x + 1.5, y + 7.8, 0.6), (2.4, 0.7, 2.0), BARK_D)
                x += 7.0
            elif kind == 4:  # books leaning
                for j in range(int(rng.integers(2, 4))):
                    mat = (SHUT, CLAY, BANNER)[j % 3]
                    slab(m, V(x + j * 1.6, y + 1, 0.6), V(x + j * 1.6 + rng.uniform(-0.6, 0.6), y + rng.uniform(7, 9.5), 0.6), 0.75, 2.4, mat, (1, 0, 0))
                x += 5.5
            else:  # a candle stump
                m.limb(V(x, y + 1, 0.6), V(x, y + 3.6, 0.6), 1.0, 0.9, WAX)
                m.ell((x, y + 4.8, 0.8), (0.6, 1.1, 0.6), FIRE, kind="emit")
                x += 3.5
    slab(m, V(-30, 72, 0), V(30, 73, 0), 7.0, 1.2, BARK_D, (0, 1, 0))
    for k in range(5):  # dried reed and herbs hanging from the top board
        x0 = -22 + k * 11
        m.limb(V(x0, 71, 4.2), V(x0 + rng.uniform(-1, 1), 64, 4.6), 1.2, 0.4, REED if k % 2 else MOSS)
    crystal(m, V(18, 73.5, 0), 7.0, 1.6)
    arr = to_array(render(m, 64, 92, 84))
    return soft_shadow(grain(arr, 104, mats=(BARK, BARK_D)), 32, 85, 28, 4, 70), 84


def candles_arr():
    """A cluster of candles grown into each other on a flat stone, wax run down in tongues, five flames. 32 x 28, ground 22."""
    rng = rng_for(105)
    m = h.Model()
    m.ell((0, 0.8, 0), (9.0, 1.4, 6.0), STONE_L)
    for k, (x, z, ht) in enumerate(((-4, 1, 8.0), (1, -2, 11.0), (4, 2, 6.0), (-1, 3, 4.5), (6, -1, 9.0))):
        m.limb(V(x, 1.4, z), V(x, 1.4 + ht, z), 1.2, 1.1, WAX)
        for j in range(2):
            m.limb(V(x + rng.uniform(-1, 1), 1.4 + ht, z + 1.0), V(x + rng.uniform(-1, 1), 1.4 + ht - rng.uniform(2, 5), z + 1.2), 0.5, 0.35, WAX)
        m.ell((x, 2.6 + ht, z), (0.65, 1.3, 0.65), FIRE, kind="emit")
    for _ in range(6):
        m.ell((rng.uniform(-7, 7), 1.6, rng.uniform(-4, 4)), (rng.uniform(1, 2), 0.5, rng.uniform(0.8, 1.5)), WAX)
    return to_array(render(m, 32, 28, 22)), 22


def astrolabe_arr():
    """An orrery of tarnished brass on a crooked stand: three rings round a hanging crystal, a little moon on a wire, pointing at the window. 44 x 70, ground 62."""
    m = h.Model()
    for k in range(3):  # the tripod
        a = k / 3 * math.tau
        log(m, V(math.cos(a) * 7, 0, math.sin(a) * 5), V(0, 22, 0), 0.8, BARK_D, step=0.8)
    log(m, V(0, 22, 0), V(0, 34, 0), 0.6, h.GOLD, step=0.6)
    c = V(0, 44, 0)
    for ring, (tilt, r) in enumerate(((0.0, 11.0), (1.0, 9.0), (2.1, 7.5))):
        R = h.rot_x(tilt) @ h.rot_y(ring * 0.9)
        for k in range(40):
            a = k / 40 * math.tau
            p = c + R @ V(math.cos(a) * r, math.sin(a) * r, 0)
            m.ell(p, (0.55, 0.55, 0.55), h.GOLD)
    crystal(m, c + V(0, -4.0, 0), 8.0, 1.8)
    m.limb(c, c + V(9, 6, 2), 0.2, 0.2, IRON)
    m.ell(c + V(9.5, 6.5, 2), (1.6, 1.6, 1.6), MOON)
    arr = to_array(render(m, 44, 70, 62))
    return soft_shadow(arr, 22, 63, 12, 3, 70), 62


def moonchart_arr():
    """A cloth hung on the back wall: dark indigo, the eight phases of the moon in a ring, stars stitched in silver thread that glint teal, an eye in the middle.
    A flat wall picture (decal), 64 x 44."""
    W, H = 64, 44
    arr = np.zeros((H, W, 4), np.uint8)
    cloth = [hexc(c) for c in ("12122a", "1c1c3c", "26264e", "32325e")]
    for y in range(1, H - 2):
        sag = int(1.5 * math.sin(math.pi * y / H))
        for x in range(2 + sag, W - 2 - sag):
            b = 1 + (1 if (x + y * 3) % 7 == 0 else 0) - (1 if y > H - 8 and (x * 5 + y) % 4 == 0 else 0)
            c = cloth[max(0, min(3, b))]
            arr[y, x] = (c[0], c[1], c[2], 255)
    rod = [hexc(c) for c in ("1d1428", "33253d")]
    for x in range(0, W):
        arr[0, x] = (*rod[0][:3], 255)
        arr[1, x] = (*rod[1][:3], 255)
    moon = [hexc(c) for c in ("8a94a8", "c4cad8", "eef0f6")]
    teal = h.RAMPS[h.TEAL]
    cx, cy = W / 2, H / 2 + 1
    for k in range(8):
        a = -math.pi / 2 + k * math.tau / 8
        mx, my = cx + math.cos(a) * 22, cy + math.sin(a) * 14
        phase = k / 8.0
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx * dx + dy * dy <= 9:
                    lit = (dx / 3.0) < math.cos(phase * math.tau) * (1 if phase < 0.5 else -1) if k not in (0, 4) else k == 4
                    if k == 0:
                        lit = False
                    col = moon[2] if lit else cloth[0]
                    if not lit and dx * dx + dy * dy >= 7:
                        col = moon[0]
                    arr[int(my + dy), int(mx + dx)] = (col[0], col[1], col[2], 255)
    for (sx, sy) in ((8, 6), (14, 36), (52, 8), (56, 34), (30, 5), (44, 38), (6, 22), (58, 21)):
        arr[sy, sx] = (teal[3][0], teal[3][1], teal[3][2], 255)
    for dx, dy in ((-2, 0), (-1, -1), (0, -1), (1, -1), (2, 0), (1, 1), (0, 1), (-1, 1)):  # the eye
        arr[int(cy + dy), int(cx + dx)] = (teal[2][0], teal[2][1], teal[2][2], 255)
    arr[int(cy), int(cx)] = (h.RAMPS[h.VIOLET][3][0], h.RAMPS[h.VIOLET][3][1], h.RAMPS[h.VIOLET][3][2], 255)
    for x in range(4, W - 4, 3):  # a fringe
        arr[H - 2, x] = (*cloth[2][:3], 255)
        arr[H - 1, x] = (*cloth[1][:3], 255)
    return arr


def mobile_arr():
    """A mobile of the moon's phases hanging from the ceiling: a hoop of bone wood, crescents and full moons of moonstone on threads, two glass orbs. 44 x 44."""
    rng = rng_for(107)
    m = h.Model()
    for k in range(30):
        a = k / 30 * math.tau
        m.ell((math.cos(a) * 14, 38, math.sin(a) * 5), (0.8, 0.8, 0.8), BONE_D)
    m.limb(V(0, 44, 0), V(0, 38, 0), 0.2, 0.2, ROPE)
    for k in range(7):
        a = k / 7 * math.tau
        x, z = math.cos(a) * 14, math.sin(a) * 5
        ln = rng.uniform(6, 16)
        m.limb(V(x, 38, z), V(x, 38 - ln, z), 0.15, 0.15, ROPE, step=0.4)
        y = 38 - ln - 2.5
        if k % 3 == 2:
            m.ell((x, y, z), (2.0, 2.0, 2.0), GLASS)
            m.ell((x - 0.3, y - 0.2, z + 1.4), (0.9, 0.9, 0.5), h.VIOLET if k % 2 else h.TEAL, kind="emit")
        else:
            for j in range(7):
                b = math.radians(-120 + j * 40)
                m.ell((x + math.cos(b) * 2.2, y + math.sin(b) * 2.2, z), (0.75, 0.75, 0.6), MOON)
    return to_array(render(m, 44, 48, 46, pitch=12.0))


def broom_arr():
    """A witch's broom leaning against the wall: a crooked hag elm handle, a bundle of reed bound with silver wire. 24 x 60, ground 54."""
    rng = rng_for(109)
    m = h.Model()
    log(m, V(-3, 10, 0), V(3, 54, -4), 0.8, BARK_D, step=0.7)
    for k in range(18):
        a = k / 18 * math.tau
        m.limb(V(-3.0, 12, 0), V(-3.0 + math.cos(a) * rng.uniform(3, 5), 0.5, math.sin(a) * 3), 0.55, 0.3, REED if k % 3 else REED_D)
    for y in (11.0, 13.0):
        for k in range(10):
            a = k / 10 * math.tau
            m.ell((-3 + math.cos(a) * 1.4, y, math.sin(a) * 1.4), (0.4, 0.4, 0.4), MOON)
    return soft_shadow(to_array(render(m, 24, 60, 54)), 12, 55, 7, 2, 70), 54


def stonewall_arr():
    """The crystal wall: a tall cabinet of hag elm with dozens of small drawers and open pigeonholes, stones and crystals in them, a little ladder. 88 x 76, ground 70."""
    rng = rng_for(99)
    m = h.Model()
    slab(m, V(-40, 0, 0), V(-40, 52, 0), 1.6, 5.0, BARK_D, (1, 0, 0))
    slab(m, V(40, 0, 0), V(40, 52, 0), 1.6, 5.0, BARK_D, (1, 0, 0))
    for r in range(7):
        y = 2 + r * 7.6
        slab(m, V(-40, y, 1), V(40, y, 1), 5.2, 0.9, BARK, (0, 1, 0))
        for c in range(10):
            x = -36 + c * 8.0
            if (r + c) % 3 == 0:  # an open hole with a stone or a crystal
                m.ell((x, y + 3.6, -2.0), (3.2, 2.8, 0.6), GAP)
                if rng.random() < 0.55:
                    crystal(m, V(x, y + 1.2, 0.6), rng.uniform(2.4, 4.5), 0.8, emit=rng.random() < 0.6)
                else:
                    m.ell((x, y + 2.2, 0.8), (1.5, 1.1, 1.2), MOON)
            else:  # a drawer front with a knob
                m.ell((x, y + 3.7, 2.6), (3.4, 3.0, 0.8), BONE if (r * 3 + c) % 4 else BONE_D)
                m.ell((x, y + 3.6, 3.6), (0.6, 0.6, 0.4), IRON if (r + c) % 2 else h.GOLD)
    slab(m, V(-42, 55, 1), V(42, 55, 1), 6.0, 1.3, BARK_D, (0, 1, 0))
    for k in range(5):
        crystal(m, V(-30 + k * 15, 56.2, 0), rng.uniform(3, 6), 1.0)
    for sx in (-1, 1):  # the ladder leaning on the right
        log(m, V(30 + sx * 3.4, 0, 9), V(34 + sx * 3.4, 46, 2), 0.7, BONE_D, step=0.8)
    for k in range(6):
        t = (k + 0.5) / 6
        log(m, V(27 + 4 * t, 46 * t, 9 - 7 * t), V(34 + 4 * t, 46 * t, 9 - 7 * t), 0.45, BONE_D, step=0.7)
    arr = to_array(render(m, 92, 76, 70))
    return soft_shadow(grain(arr, 100, mats=(BARK, BARK_D, BONE, BONE_D)), 46, 71, 40, 4, 70), 70


def chimes_room_arr():
    """A cluster of hanging crystals from the ceiling beam (a `hanging` prop of the room). 28 x 36."""
    rng = rng_for(101)
    m = h.Model()
    for k in range(5):
        x = -8 + k * 4
        ln = rng.uniform(4, 12)
        m.limb(V(x, 32, 0), V(x, 32 - ln, 0), 0.15, 0.15, ROPE, step=0.4)
        crystal(m, V(x, 32 - ln - 5.0, 0), 5.0, 0.9, emit=k % 2 == 0)
    log(m, V(-11, 32.5, 0), V(11, 32.5, 0), 0.8, BONE_D, step=0.7)
    return to_array(render(m, 28, 36, 34, pitch=12.0))


def room_props():
    for name, fn in (("counter", counter_arr), ("grind", grind_arr), ("carve", carve_arr), ("stonewall", stonewall_arr), ("potions", potions_arr),
                     ("candles", candles_arr), ("astrolabe", astrolabe_arr), ("broom", broom_arr)):
        arr, feet = fn()
        put(name, arr)
        SIZES[name + "_feet"] = feet
    sheet, feet = basin_frames()
    put("basin", sheet)
    SIZES["basin_feet"] = feet
    put("hang_crystals", chimes_room_arr())
    put("mobile", mobile_arr())
    put("runes", runes_arr())
    put("moonchart", moonchart_arr())
    for name, fn in (("fireplace", props.fireplace_arr), ("chair", props.chair_arr), ("herbs", props.herbs_arr), ("pots", props.pots_arr), ("barrel", props.barrel_arr)):
        arr, feet = fn()
        put(name, arr)
        SIZES[name + "_feet"] = feet
    fire = fx.fire_frames()
    put("fire", fire if isinstance(fire, np.ndarray) else fire[0], glow=False)
    for stale in ("bed", "rug", "chest"):
        for suffix in (".png", "_glow.png"):
            if (OUT / (stale + suffix)).exists():
                (OUT / (stale + suffix)).unlink()


# ------------------------------------------------------------------ the interior JSON (data/interiors.json "lake_hut")
def interior_entry():
    fw, fh = FLOOR
    shell_w = fw + 2 * room.SIDE_W
    floor_bottom = 72 + fh
    front_y = floor_bottom - 22
    H = floor_bottom + 16
    g0, g1 = DOOR_GAP
    door_mid = (g0 + g1) // 2
    f = SIZES
    return {
        "title": "Haus der Seehexe",
        "dir": "res://assets/interior/lake_hut/",
        "size": [shell_w, H],
        "floor": [16, 72, fw, fh],
        "front_y": front_y,
        "ambient": {"day": "#bcc4d8", "night": "#3a3a64"},
        "entry": [door_mid, front_y - 12],
        "exit_door": {"id": "door", "pos": [door_mid, front_y + 18], "leaf": [g0, front_y - 18]},
        "shell": [{"tex": "floor.png", "pos": [16, 72], "z": -6}, {"tex": "wall.png", "pos": [0, 0], "z": -5, "glow": True},
                  {"tex": "side.png", "pos": [0, 0], "z": -5, "glow": True}, {"tex": "side.png", "pos": [shell_w - 16, 0], "z": -5, "glow": True},
                  {"tex": "runes.png", "pos": [144 - 80, 148 - 52], "z": -5, "glow": True},
                  {"tex": "moonchart.png", "pos": [180, 10], "z": -4, "glow": True}],
        "walls": [[16, 48, fw, 28], [0, 40, 24, H - 52], [shell_w - 24, 40, 24, H - 52], [0, front_y + 10, g0, 30], [g1, front_y + 10, shell_w - g1, 30],
                  [g0, front_y + 32, g1 - g0, 10]],
        "props": [
            {"id": "fireplace", "tex": "fireplace.png", "pos": [64, 82], "feet": f["fireplace_feet"], "glow": "fireplace_glow.png", "solid": [64, 14, -32, -12]},
            {"id": "stonewall", "tex": "stonewall.png", "pos": [140, 80], "feet": f["stonewall_feet"], "glow": "stonewall_glow.png", "solid": [84, 12, -42, -10],
             "light": {"color": "#78f4e6", "radius": 44, "energy": 0.45}},
            {"id": "potions", "tex": "potions.png", "pos": [246, 82], "feet": f["potions_feet"], "glow": "potions_glow.png", "solid": [56, 12, -28, -10],
             "light": {"color": "#b48cff", "radius": 46, "energy": 0.5}},
            {"id": "grind", "tex": "grind.png", "pos": [234, 140], "feet": f["grind_feet"], "glow": "grind_glow.png", "solid": [56, 14, -28, -12]},
            {"id": "basin", "tex": "basin.png", "frames": 4, "frame": 0, "pos": [144, 162], "feet": f["basin_feet"], "glow": "basin_glow.png", "solid": [52, 16, -26, -13],
             "light": {"color": "#78f4e6", "radius": 90, "energy": 1.1}},
            {"id": "carve", "tex": "carve.png", "pos": [54, 176], "feet": f["carve_feet"], "glow": "carve_glow.png", "solid": [64, 12, -32, -10]},
            {"id": "counter", "tex": "counter.png", "pos": [214, 210], "feet": f["counter_feet"], "glow": "counter_glow.png", "solid": [52, 12, -26, -10]},
            {"id": "astrolabe", "tex": "astrolabe.png", "pos": [196, 112], "feet": f["astrolabe_feet"], "glow": "astrolabe_glow.png", "solid": [14, 8, -7, -6]},
            {"id": "chair", "tex": "chair.png", "pos": [104, 110], "feet": f["chair_feet"], "solid": [18, 8, -9, -6]},
            {"id": "candles_a", "tex": "candles.png", "pos": [96, 140], "feet": f["candles_feet"], "glow": "candles_glow.png", "light": {"color": "#ffb060", "radius": 34, "energy": 0.6}},
            {"id": "candles_b", "tex": "candles.png", "pos": [196, 170], "feet": f["candles_feet"], "glow": "candles_glow.png", "light": {"color": "#ffb060", "radius": 30, "energy": 0.5}},
            {"id": "candles_c", "tex": "candles.png", "pos": [258, 186], "feet": f["candles_feet"], "glow": "candles_glow.png", "light": {"color": "#ffb060", "radius": 28, "energy": 0.45}},
            {"id": "broom", "tex": "broom.png", "pos": [176, 222], "feet": f["broom_feet"]},
            {"id": "barrel", "tex": "barrel.png", "pos": [34, 212], "feet": f["barrel_feet"], "solid": [20, 10, -10, -8]},
            {"id": "pots", "tex": "pots.png", "pos": [94, 222], "feet": f["pots_feet"]},
        ],
        "anims": [{"id": "fire", "tex": "fire.png", "frames": 6, "pos": [64, 80], "feet": 28, "fps": 9.0, "unlit": True}],
        "hanging": [{"id": "herbs", "tex": "herbs.png", "glow": "herbs_glow.png", "pos": [92, 20], "sway": 0.05, "speed": 0.8},
                    {"id": "mobile", "tex": "mobile.png", "glow": "mobile_glow.png", "pos": [144, 16], "sway": 0.07, "speed": 0.5,
                     "light": {"color": "#b48cff", "radius": 40, "energy": 0.4, "drop": 40}},
                    {"id": "crystals_a", "tex": "hang_crystals.png", "glow": "hang_crystals_glow.png", "pos": [204, 22], "sway": 0.06, "speed": 0.7,
                     "light": {"color": "#78f4e6", "radius": 46, "energy": 0.55, "drop": 36}},
                    {"id": "crystals_b", "tex": "hang_crystals.png", "glow": "hang_crystals_glow.png", "pos": [40, 26], "sway": 0.05, "speed": 0.9}],
        "decals": [],
        "lights": [{"pos": [64, 98], "color": "#ff9a4a", "radius": 100, "squash": 0.75, "energy": 1.0, "flicker": 0.24},
                   {"pos": [144, 150], "color": "#78f4e6", "radius": 120, "squash": 0.75, "energy": 0.9},
                   {"pos": [200, 110], "color": "#cfe8ff", "radius": 60, "squash": 0.8, "energy": 0.45, "day": True}],
        "rays": [],
        "resident": "lake_witch",
    }


def write_interior():
    path = ROOT.parent / "data" / "interiors.json"
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    entry = interior_entry()
    for group in ("props", "hanging"):  # only glow sheets that were written (a prop without emissive pixels has none)
        for item in entry[group]:
            if "glow" in item and not (OUT / item["glow"]).exists():
                del item["glow"]
    data["lake_hut"] = entry
    newline = "\r\n" if "\r\n" in raw else "\n"
    text = json.dumps(data, ensure_ascii=False, indent=1)
    path.write_text(text.replace("\n", newline) + newline, encoding="utf-8", newline="")


# ------------------------------------------------------------------ preview
def preview(path):
    from PIL import Image
    names = ["lake_hut", "jetty", "boat", "wheel", "rack", "chimes", "ward", "counter", "grind", "carve", "stonewall", "potions", "candles", "astrolabe", "broom", "mobile", "runes", "moonchart", "basin", "wall", "floor"]
    ims = [Image.open(OUT / f"{n}.png").convert("RGBA") for n in names]
    W = 1100
    x = y = 0
    row_h = 0
    places = []
    for im in ims:
        if x + im.width > W:
            x, y, row_h = 0, y + row_h + 6, 0
        places.append((x, y))
        x += im.width + 6
        row_h = max(row_h, im.height)
    canvas = Image.new("RGBA", (W, y + row_h), (38, 44, 40, 255))
    for im, p in zip(ims, places):
        canvas.alpha_composite(im, p)
    canvas = canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST)
    canvas.save(path)


def main():
    ext, feet = house_arr()
    put("lake_hut", ext)
    SIZES["lake_hut_feet"] = feet
    put("lake_hut_window_light", lens_spill(), glow=False)
    gx0, gy0, gx1, gy1 = DOOR_INFO["box"]
    gw, gh = gx1 - gx0 + 1, gy1 - gy0 + 1  # the leaf picture is (gw + 8) x (gh + 8), its boards stand on row gh + 4 from x 4
    put("lake_hut_door", room.door_arr(gw, gh, seed=45), glow=False)
    SIZES["door_at"] = (gx0 - 4, gy1 + 1 - (gh + 4))
    SIZES["door_box"] = DOOR_INFO["box"]
    for name, fn in (("jetty", jetty_arr), ("boat", boat_arr), ("wheel", wheel_arr), ("rack", rack_arr)):
        arr, ft = fn()
        put(name, arr)
        SIZES[name + "_feet"] = ft
    put("rack_strings", rack_strings_arr())
    put("chimes", chimes_arr())
    put("ward", ward_sheet())
    sheet = glimmer_arr()  # the lake stones as world pickups (data/plants.json lake_glimmer / lake_moonstone) and their item icons
    props_dir = ROOT / "props"
    save(props_dir / "lake_glimmer.png", sheet[:, :40])
    g = glow_of(sheet[:, :40], GLOWS)
    save(props_dir / "lake_glimmer_glow.png", g)
    save(props_dir / "lake_moonstone.png", sheet[:, 40:])
    save(props_dir / "lake_moonstone_glow.png", glow_of(sheet[:, 40:], GLOWS))
    for name, art in (("lake_glimmer", ICON_GLIMMER), ("lake_moonstone", ICON_MOONSTONE)):
        save(ROOT / "items" / f"{name}.png", icon(name, art))
    hut_lib.set_fresh()  # her room is cared for: the renewed wood, no moss, holes or cobwebs
    room_shell()
    room_props()
    write_interior()
    print(json.dumps(SIZES))
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
