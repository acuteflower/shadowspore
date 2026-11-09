"""Gustav's wagon (quest `gustav_rescue`): a covered carter's wagon, run aground in the grove: the front axle is broken and the front dropped, one wheel lies
beside it, the drawbar snapped off, the canvas torn and mossy, the rear door wedged shut with a bent beam. Same ellipsoid renderer as the signpost, the hut
and the heroine (violet-plum weathered boards, ink outline, moss, teal fungi, violet void veins).
    py -3 tools/art_wagon.py [preview.png]
Writes assets/props/gustav_wagon.png (two frames of 128x80 side by side: 0 = door wedged shut, 1 = door thrown open and dark inside; the middle of the
wagon is at x 64, the ground row is 60) and gustav_wagon_glow.png (only the emissive pixels, drawn unlit). The wagon stands turned a little towards the
viewer (YAW) so the rear door at the east end shows; prints the ground footprint and the door spot for src/entities/props/gustav_wagon.gd."""
import math
import sys
import pathlib
import numpy as np
import art_hero3d as h
from gen_art import ROOT, hexc, write_png, CLEAR

FW1, FH = 128, 80
h.FW, h.FH, h.GROUND_ROW = FW1, FH, 60
GROUND = 60
YAW = -0.7
BASE = len(h.RAMPS)
BARK, PLANK, PAINT, IRON, CANVAS, MOSS, DARK, STONE = range(BASE, BASE + 8)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1a1322", "34283c", "55435a", "85697a"],  # wheels, beams: the trees' bark
    ["2b2128", "4d3d44", "7c6769", "ad9791"],  # weathered boards
    ["3a2c1c", "5c4824", "86703a", "b89c58"],  # faded mustard paint of the carter
    ["0e0d16", "1e1d2c", "3b3a50", "6a6a86"],  # iron
    ["2a2430", "453b47", "6c5e66", "958579"],  # dirty, sun-bleached linen canvas
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss and ivy
    ["07050b", "0d0a14", "15111f", "211a30"],  # the dark inside
    ["14121f", "2a2740", "46456a", "6f6f96"],  # old stones
]]
GLOW = (h.TEAL, h.VIOLET)
V = lambda *a: np.array(a, float)
FLAT_ENDS = lambda q: np.abs(q[..., 1]) <= 0.78  # an ellipsoid cut to a board with square ends along its local y


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


HALF_L, HALF_W = 42.0, 17.0  # the box
AXLE_Y, WHEEL_R = 17.0, 17.0
FLOOR_Y, RAIL_Y = 15.0, 32.0  # floor and the top rail where the hoops spring
TILT = 0.17  # the broken front (west) end dropped
PIVOT = V(24.0, AXLE_Y, 0.0)  # the east axle: the only whole one
T = rz(TILT)


class Parts:
    """Wrappers: body parts are tilted about the east axle, world parts (wheels, drawbar, stones, grass) are not."""

    def __init__(self, m):
        self.m = m

    def E(self, c, r, mat, R=None, kind="", clip=None):  # tilted ellipsoid
        c = T @ (V(*c) - PIVOT) + PIVOT
        self.m.ell(c, r, mat, R=T if R is None else T @ R, kind=kind, clip=clip)

    def L(self, a, b, r0, r1, mat, kind=""):  # tilted limb
        pa = T @ (V(*a) - PIVOT) + PIVOT
        pb = T @ (V(*b) - PIVOT) + PIVOT
        self.m.limb(pa, pb, r0, r1, mat, kind=kind)

    def W(self, c, r, mat, R=None, kind=""):  # world ellipsoid
        self.m.ell(V(*c), r, mat, R=R, kind=kind)

    def WL(self, a, b, r0, r1, mat, kind=""):
        self.m.limb(V(*a), V(*b), r0, r1, mat, kind=kind)

    def point(self, p):  # where a body point ends up in the world
        return T @ (V(*p) - PIVOT) + PIVOT


def wheel(P, centre, M, broken, rng, n=20, spokes=10):
    """A cart wheel in the local x-y plane (axle = local z), placed with the matrix M at `centre`: felloe segments, iron tyre, spokes, hub."""
    R = WHEEL_R
    ctr = V(*centre)
    gaps = set(rng.choice(n, 5, replace=False).tolist()) if broken else set()
    arc = 2 * math.pi * R / n
    for i in range(n):
        if i in gaps:
            continue
        a = i * 2 * math.pi / n + 0.1
        tang, rad = V(-math.sin(a), math.cos(a), 0), V(math.cos(a), math.sin(a), 0)
        Rl = np.stack([tang, rad, V(0, 0, 1)], axis=1)
        P.W(ctr + M @ (rad * (R - 1.0)), (arc / 2 + 0.35, 1.9, 1.8), BARK, R=M @ Rl)  # felloe
        P.W(ctr + M @ (rad * (R + 0.7) + V(0, 0, 0)), (arc / 2 + 0.2, 0.55, 2.0), IRON, R=M @ Rl)  # tyre
    lost = set(rng.choice(spokes, 3, replace=False).tolist()) if broken else set()
    for i in range(spokes):
        if i in lost:
            a = i * 2 * math.pi / spokes + 0.3
            P.m.limb(ctr + M @ V(2.5 * math.cos(a), 2.5 * math.sin(a), 0), ctr + M @ V(7.0 * math.cos(a), 7.0 * math.sin(a), 0), 0.9, 0.75, BARK)  # a stump
            continue
        a = i * 2 * math.pi / spokes + 0.3
        P.m.limb(ctr + M @ V(2.5 * math.cos(a), 2.5 * math.sin(a), 0), ctr + M @ V((R - 1.5) * math.cos(a), (R - 1.5) * math.sin(a), 0), 1.0, 0.85, BARK)
    P.W(ctr, (3.1, 3.1, 3.4), BARK, R=M)  # hub
    P.W(ctr + M @ V(0, 0, 3.2), (1.7, 1.7, 0.8), IRON, R=M)
    P.W(ctr + M @ V(0, 0, 2.2), (3.4, 3.4, 0.55), IRON, R=M)


def build(open_door: bool, seed: int = 11):
    rng = np.random.default_rng(seed)
    m = h.Model()
    P = Parts(m)
    E, L = P.E, P.L

    # --- the ground: stones and grass round the wreck -----------------------------------------------------------------------------------------
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        rx, rz_ = rng.uniform(46, 62), rng.uniform(22, 30)
        P.W((rx * math.cos(a) * 0.95, 1.0, rz_ * math.sin(a)), (rng.uniform(1.8, 3.4), rng.uniform(1.1, 2.2), rng.uniform(1.6, 2.6)), STONE)
    for k in range(14):
        x0, z0 = rng.uniform(-60, 60), rng.uniform(-24, 28)
        if abs(z0) < 12 and abs(x0) < 40:
            continue
        P.WL((x0, 0.5, z0), (x0 + rng.uniform(-1.4, 1.4), 4.0 + rng.uniform(0, 3.4), z0), 0.55, 0.2, MOSS)

    # --- the chassis: two long beams, the bolster, the axles ---------------------------------------------------------------------------------
    for sz in (-1, 1):
        E((0, FLOOR_Y - 2.4, sz * 12.0), (HALF_L + 1.5, 1.9, 1.9), BARK)
    for x in (-24.0, 24.0):
        E((x, FLOOR_Y - 1.4, 0.0), (2.2, 1.6, 15.0), BARK)  # bolsters over the axles
    # the east axle is whole, the west one snapped
    P.WL((24, AXLE_Y, -23), (24, AXLE_Y, 23), 1.5, 1.5, BARK)
    P.WL(P.point((-24, AXLE_Y, -23)), P.point((-24, AXLE_Y, 8.0)), 1.5, 1.4, BARK)
    P.W(P.point((-24, AXLE_Y, 9.0)), (1.3, 1.1, 1.9), BARK)  # the splintered end
    P.W(P.point((-24, AXLE_Y - 0.5, 11.0)), (0.8, 0.6, 1.4), PLANK)

    # --- the floor ----------------------------------------------------------------------------------------------------------------------------
    E((0, FLOOR_Y, 0), (HALF_L, 1.3, HALF_W), PLANK)
    E((0, FLOOR_Y + 1.1, 0), (HALF_L - 1.0, 0.4, HALF_W - 1.0), DARK)

    # --- the walls: weathered planks, a faded mustard band, one board broken out -----------------------------------------------------------
    broken_row, gap = 3, (6.0, 21.0)
    for side in (1, -1):
        z = side * (HALF_W + 0.3)
        for i in range(5):
            y = FLOOR_Y + 3.2 + i * 3.35
            mat = PAINT if i == 2 else PLANK
            jitter = rng.uniform(-0.25, 0.25)
            segs = [(-HALF_L, HALF_L)]
            if i == broken_row and side == 1:
                segs = [(-HALF_L, gap[0]), (gap[1], HALF_L)]
            for a, b in segs:
                E((jitter + (a + b) / 2, y, z), ((b - a) / 2, 1.6, 0.95), mat)
        if side == 1:  # the splinters of the broken-out board, inside it the dark
            E(((gap[0] + gap[1]) / 2, FLOOR_Y + 3.2 + broken_row * 3.35, z - 1.0), ((gap[1] - gap[0]) / 2, 1.8, 0.4), DARK)
            L((gap[0], FLOOR_Y + 3.2 + broken_row * 3.35 + 0.4, z + 0.2), (gap[0] + 3.2, FLOOR_Y + 3.2 + broken_row * 3.35 + 1.0, z + 1.6), 0.7, 0.35, PLANK)
            L((gap[1], FLOOR_Y + 3.2 + broken_row * 3.35 - 0.4, z + 0.2), (gap[1] - 4.0, FLOOR_Y + 3.2 + broken_row * 3.35 - 1.0, z + 2.0), 0.7, 0.3, PLANK)
    for x in (-HALF_L, -21.0, 0.0, 21.0, HALF_L):  # posts and iron straps on the south side
        E((x, FLOOR_Y + 9.0, HALF_W + 0.9), (1.5, 9.3, 1.3), BARK)
        if x not in (-HALF_L, HALF_L):
            E((x + 1.6, FLOOR_Y + 9.0, HALF_W + 1.9), (0.55, 8.0, 0.35), IRON)
            for ny in (3.0, 9.5, 15.0):
                E((x + 1.6, FLOOR_Y + ny, HALF_W + 2.3), (0.4, 0.4, 0.3), IRON)
        E((x, FLOOR_Y + 9.0, -HALF_W - 0.9), (1.5, 9.3, 1.3), BARK)
    E((0, RAIL_Y + 0.6, HALF_W + 0.9), (HALF_L + 0.6, 1.0, 1.5), BARK)  # the top rails
    E((0, RAIL_Y + 0.6, -HALF_W - 0.9), (HALF_L + 0.6, 1.0, 1.5), BARK)
    E((-HALF_L - 0.5, FLOOR_Y + 9.0, 0), (0.95, 9.0, HALF_W), PLANK)  # the front board (turned away from us)
    # a cracked place with a violet vein of the void, creeping out of the broken board
    L((gap[1] + 1.0, FLOOR_Y + 3.4, HALF_W + 1.4), (gap[1] + 5.5, FLOOR_Y + 7.6, HALF_W + 1.35), 0.38, 0.3, h.VIOLET, kind="emit")
    L((gap[1] + 5.5, FLOOR_Y + 7.6, HALF_W + 1.35), (gap[1] + 9.0, FLOOR_Y + 10.4, HALF_W + 1.3), 0.3, 0.22, h.VIOLET, kind="emit")
    L((gap[1] + 5.5, FLOOR_Y + 7.6, HALF_W + 1.35), (gap[1] + 8.0, FLOOR_Y + 4.0, HALF_W + 1.3), 0.28, 0.2, h.VIOLET, kind="emit")

    # --- the hoops and the canvas -------------------------------------------------------------------------------------------------------------
    hoops = [-36.0, -18.0, 0.0, 18.0, 36.0]
    steps = 10
    for x in hoops:
        for k in range(steps):
            a0, a1 = math.pi * k / steps, math.pi * (k + 1) / steps
            p0 = (x, RAIL_Y + (HALF_W + 1.5) * math.sin(a0), (HALF_W + 1.5) * math.cos(a0))
            p1 = (x, RAIL_Y + (HALF_W + 1.5) * math.sin(a1), (HALF_W + 1.5) * math.cos(a1))
            L(p0, p1, 1.15, 1.15, PLANK)
    cols = [-27.0, -9.0, 9.0, 27.0]
    for ci, xc in enumerate(cols):
        for k in range(steps):
            am = math.pi * (k + 0.5) / steps
            n = V(0.0, math.sin(am), math.cos(am))
            # the tear in the roof: column 1 from 60 to 160 degrees, column 0 from 110 to 150 degrees (ragged)
            deg = math.degrees(am)
            if ci == 1 and 28 <= deg <= 118:
                continue
            if ci == 0 and 66 <= deg <= 112:
                continue
            if ci == 2 and 80 <= deg <= 96:
                continue
            c = V(xc, RAIL_Y, 0.0) + n * (HALF_W + 0.75)
            Rl = h.frame_from(n, V(0.0, math.cos(am), -math.sin(am)))
            mat = CANVAS
            E(c, (9.0 + 0.6, 1.1, HALF_W * math.pi / steps / 2 + 1.3), mat, R=Rl)
    # sewn patches, a dark one on the south side, a pale one on the ridge
    for xc, deg, w, hh in ((9.0, 22.0, 4.2, 3.0), (-27.0, 52.0, 3.6, 2.6), (27.0, 70.0, 3.0, 3.4)):
        am = math.radians(deg)
        n = V(0.0, math.sin(am), math.cos(am))
        E(V(xc, RAIL_Y, 0.0) + n * (HALF_W + 1.35), (w, 0.25, hh), PLANK, R=h.frame_from(n, V(0.0, math.cos(am), -math.sin(am))))
    # the flap of the tear hanging down over the north side, and ragged strips at its edges
    for k in range(5):
        am = math.radians(150.0 + k * 3.0)
        n = V(0.0, math.sin(am), math.cos(am))
        base = V(-9.0 + (k - 2) * 3.4, RAIL_Y, 0.0) + n * (HALF_W + 0.9)
        L(tuple(base), tuple(base + V(0.0, -3.6 - 1.4 * (k % 2), -1.6 + k * 0.1)), 0.9, 0.35, CANVAS)
    for k in range(5):
        am = math.radians(60.0 + k * 1.0)
        n = V(0.0, math.sin(am), math.cos(am))
        base = V(-9.0 + (k - 2) * 3.8, RAIL_Y, 0.0) + n * (HALF_W + 0.9)
        L(tuple(base), tuple(base + V(0.0, 1.6 + (k % 3) * 0.7, 3.2 - 0.4 * k)), 0.8, 0.3, CANVAS)
    # darkness inside the tear
    E((-12.0, RAIL_Y + 7.0, 0.0), (11.0, 7.0, 12.0), DARK)
    # moss on the ridge and along the south rail
    for xc in (-30.0, -14.0, 4.0, 22.0, 33.0):
        E((xc, RAIL_Y + HALF_W + 0.5 + rng.uniform(-0.2, 0.2), rng.uniform(-3.0, 3.0)), (rng.uniform(3.4, 5.5), 0.8, rng.uniform(2.2, 3.4)), MOSS)
    for xc in (-30.0, -6.0, 14.0, 34.0):
        E((xc, RAIL_Y + 1.7, HALF_W + 1.6), (rng.uniform(3.0, 5.0), 0.9, 1.2), MOSS)
    for xc in (-34.0, 2.0, 28.0):  # ivy hanging down the south wall
        top = FLOOR_Y + 15.0
        L((xc, top, HALF_W + 2.0), (xc + 0.8, top - 6.0 - rng.uniform(0, 3), HALF_W + 2.3), 0.5, 0.25, MOSS)
        E((xc + 0.5, top - 3.0, HALF_W + 2.6), (1.3, 0.35, 0.9), MOSS, R=h.rot_x(0.5))

    # --- the rear door, east end (x = HALF_L) ---------------------------------------------------------------------------------------------------
    DX = HALF_L + 0.6
    door_y0, door_y1, door_hw = FLOOR_Y + 1.6, FLOOR_Y + 21.0, 12.2
    E((DX - 0.4, (door_y0 + door_y1) / 2, door_hw + 1.9), (1.7, (door_y1 - door_y0) / 2 + 1.6, 1.8), BARK)  # frame posts
    E((DX - 0.4, (door_y0 + door_y1) / 2, -door_hw - 1.9), (1.7, (door_y1 - door_y0) / 2 + 1.6, 1.8), BARK)
    E((DX - 0.4, door_y1 + 1.8, 0.0), (1.7, 1.7, door_hw + 3.4), BARK)  # header
    E((DX - 0.3, door_y0 - 1.0, 0.0), (1.9, 1.0, door_hw + 3.6), BARK)  # threshold
    E((DX - 0.9, 44.0, 0.0), (0.7, 6.4, 12.5), CANVAS)  # the canvas closing the arch above the door
    E((DX - 0.5, door_y1 + 5.5, 0.0), (0.45, 0.6, 12.0), PLANK)
    # inside
    E((DX - 1.6, (door_y0 + door_y1) / 2, 0.0), (0.5, (door_y1 - door_y0) / 2, door_hw + 0.2), DARK)
    if open_door:
        # dark inside, a hint of a sack and a glow cap in the doorway, the leaf thrown open on its far hinge
        E((DX - 4.0, door_y0 + 3.0, 4.0), (2.6, 2.6, 4.5), PLANK)  # a crate inside
        E((DX - 3.0, door_y0 + 1.2, -4.0), (1.4, 1.0, 1.6), h.TEAL, kind="emit")
        hinge = V(DX + 0.4, 0.0, -door_hw - 0.6)
        phi, sag = math.radians(82.0), 0.14
        M = h.rot_y(phi) @ rz(sag)
        for k in range(6):
            q = V(0.0, (door_y0 + door_y1) / 2, 2.4 + k * 4.05)
            c = hinge + M @ q
            c = V(c[0], c[1], c[2])
            E(c, (0.95, (door_y1 - door_y0) / 2 / 0.78, 2.1), PLANK, R=M, clip=FLAT_ENDS)
        for yy in (door_y0 + 9.0,):
            L_ = tuple(hinge + M @ V(1.05, yy, 0.8)), tuple(hinge + M @ V(1.05, yy, 23.6))
            L(L_[0], L_[1], 0.9, 0.9, PAINT)
        for yy in (door_y0 + 3.5, door_y1 - 3.5):  # the two iron straps, the lower hinge hangs by a nail
            q0, q1 = V(0.5, yy, 0.6), V(0.5, yy, 22.0)
            L(tuple(hinge + M @ q0), tuple(hinge + M @ q1), 0.55, 0.5, IRON)
        L(tuple(hinge + M @ V(1.0, door_y0 + 2.0, 8.0)), tuple(hinge + M @ V(1.0, door_y1 - 2.0, 15.0)), 0.5, 0.5, PLANK)  # a brace
        # the wedge: the bent beam lies broken on the ground
        P.WL((DX + 6, 1.4, 4), (DX + 15, 1.6, 10), 1.5, 1.4, PLANK)
        P.WL((DX + 15, 1.6, 10), (DX + 21, 2.3, 7), 1.4, 0.9, PLANK)
        P.W((DX + 22, 1.2, 5), (1.4, 0.8, 2.6), PLANK)
    else:
        for k in range(6):
            E((DX + (0.2 if k % 2 else 0.0), (door_y0 + door_y1) / 2 - 0.2 * (k % 3), -10.15 + k * 4.06), (0.95, (door_y1 - door_y0) / 2 / 0.78, 2.1), PLANK, clip=FLAT_ENDS)
        for yy in (door_y0 + 3.5, door_y1 - 3.5):  # strap hinges
            E((DX + 1.0, yy, 0.0), (0.5, 0.5, door_hw), IRON)
        for zz in (-9.0, 9.0):
            E((DX + 1.3, door_y0 + 3.5, zz), (0.5, 0.9, 0.9), IRON)
            E((DX + 1.3, door_y1 - 3.5, zz), (0.5, 0.9, 0.9), IRON)
        # the bent beam wedged across: three pieces with a kink and a splintered end
        pts = [V(DX + 2.4, door_y0 + 1.0, -door_hw + 1.0), V(DX + 3.0, door_y0 + 7.0, -4.0), V(DX + 2.8, door_y0 + 13.0, 4.0), V(DX + 2.2, door_y1 - 0.5, door_hw - 0.5)]
        for a, b in zip(pts, pts[1:]):
            L(tuple(a), tuple(b), 1.65, 1.55, PLANK)
        L(tuple(pts[1]), tuple(pts[1] + V(1.4, 1.2, 0.4)), 0.9, 0.6, PLANK)  # the splinter at the kink
        E(tuple(pts[0] + V(0.0, -0.3, -0.4)), (1.4, 1.8, 1.8), BARK)  # wedge blocks in the corners
        E(tuple(pts[3] + V(0.0, 0.4, 0.6)), (1.4, 1.8, 1.8), BARK)
        # the void has crept into the door: a violet vein across the boards
        L((DX + 1.5, door_y0 + 3.0, -8.0), (DX + 1.5, door_y0 + 7.5, -6.0), 0.4, 0.32, h.VIOLET, kind="emit")
        L((DX + 1.5, door_y0 + 7.5, -6.0), (DX + 1.5, door_y0 + 10.0, -2.8), 0.32, 0.26, h.VIOLET, kind="emit")
        L((DX + 1.5, door_y0 + 10.0, -2.8), (DX + 1.5, door_y0 + 12.0, -3.6), 0.26, 0.2, h.VIOLET, kind="emit")
    # fungi and moss round the door's foot
    for k, (zz, hh) in enumerate(((13.0, 1.6), (15.0, 2.2), (-14.0, 1.8))):
        P.W(P.point((DX + 1.0, door_y0 - 1.0 + hh, zz)), (1.1 + 0.2 * (k % 2), 0.55, 1.1), h.TEAL, kind="emit")
        P.WL(P.point((DX + 1.0, door_y0 - 1.0, zz)), P.point((DX + 1.0, door_y0 - 1.0 + hh, zz)), 0.4, 0.35, PLANK)
    E((DX + 0.6, door_y0 - 0.2, door_hw + 1.2), (1.8, 1.0, 3.0), MOSS)
    E((DX + 0.6, door_y1 + 3.7, -door_hw - 1.0), (1.4, 0.9, 2.8), MOSS)

    # --- wheels: the east pair whole, the west one lying in the grass --------------------------------------------------------------------------
    wheel(P, (24, WHEEL_R, HALF_W + 4.4), np.eye(3), False, rng)  # south east (whole)
    wheel(P, (24, WHEEL_R, -HALF_W - 4.4), np.eye(3), False, rng)  # north east
    Mlie = h.rot_y(0.5) @ h.rot_x(-1.28)  # the broken west wheel, lying flat, leaning on a stone
    wheel(P, (-34, 4.2, 30), Mlie, True, rng)
    P.W((-34, 1.0, 38), (4.0, 1.7, 3.0), STONE)
    P.W((-39, 1.4, 36), (2.4, 1.2, 2.0), STONE)
    # moss on the lying wheel
    P.W((-40, 6.6, 31), (4.5, 0.9, 2.6), MOSS)
    P.W((-27, 6.0, 33), (3.2, 0.8, 2.0), MOSS)
    # a teal fungus shelf growing from the whole wheel's felloe
    P.W((24 + 11.5, WHEEL_R + 11.0, HALF_W + 6.4), (2.2, 1.0, 1.0), h.TEAL, kind="emit")
    P.W((24 + 13.0, WHEEL_R + 8.4, HALF_W + 6.4), (1.5, 0.8, 0.8), h.TEAL, kind="emit")

    # --- the snapped drawbar -------------------------------------------------------------------------------------------------------------------
    front = P.point((-HALF_L - 1.0, FLOOR_Y - 1.2, 0.0))
    far = V(-HALF_L - 20.0, 2.6, -2.5)
    P.WL(tuple(front), tuple(far), 2.2, 1.9, BARK)
    P.W(tuple(far + V(-1.0, 0.0, -0.2)), (2.2, 1.5, 1.6), BARK)  # the splintered end
    P.WL(tuple(far + V(-0.5, 0.9, 0.4)), tuple(far + V(-4.0, 1.9, 1.2)), 0.8, 0.3, PLANK)
    P.WL(tuple(far + V(-0.5, -0.4, -0.6)), tuple(far + V(-3.4, 0.5, -1.8)), 0.7, 0.3, PLANK)
    P.W(tuple(front + V(-3.0, 0.8, 0.0)), (0.7, 2.2, 2.2), IRON, R=rz(0.4))  # the iron ring
    # the moss on the bar and a fungus
    P.W(tuple((front + far) / 2 + V(0.0, 2.0, 0.6)), (4.8, 0.8, 1.4), MOSS)
    P.W(tuple((front + far) / 2 + V(-7.0, 2.4, -0.6)), (1.5, 0.8, 0.9), h.TEAL, kind="emit")
    return m


def render(m):
    depth, code = h.render(m.transform(YAW, 0.0))
    return h.to_pixels(depth, code)


def screen(p):
    """Where a model point lands in the 128x80 frame (x, y) after the yaw and the renderer's projection."""
    q = h.rot_y(YAW) @ V(*p) * h.SCALE
    return FW1 / 2 + q[0], GROUND - (q[1] * h.COSP - q[2] * h.SINP)


def shadow(rows):
    pts = [screen((x, 0.0, z * 0.7)) for x in np.linspace(-HALF_L - 6, HALF_L + 6, 15) for z in (-1.0, 0.0, 1.0)]
    for y in range(FH):
        for x in range(FW1):
            if rows[y][x][3] == 0 or tuple(rows[y][x]) == (0, 0, 0, 70):
                for px, py in pts:
                    ex, ey = (x + 0.5 - px) / 11.5, (y + 0.5 - py) / 5.2
                    if ex * ex + ey * ey <= 1.0:
                        rows[y][x] = (0, 0, 0, 70)
                        break
    return rows


def glow(rows):
    cols = {tuple(c) for mat in GLOW for b, c in enumerate(h.RAMPS[mat]) if mat != h.VIOLET or b >= 1}
    return [[c if tuple(c) in cols else CLEAR for c in row] for row in rows]


if __name__ == "__main__":
    frames = [shadow(render(build(o))) for o in (False, True)]
    W = FW1 * len(frames)
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    write_png(ROOT / "props" / "gustav_wagon.png", W, FH, sheet)
    write_png(ROOT / "props" / "gustav_wagon_glow.png", W, FH, glow(sheet))
    # for the node: ground footprint (the box) and the door, relative to the ground point (64, 60)
    print("footprint corners (px from the feet):", [tuple(round(v - o, 1) for v, o in zip(screen((x, 0.0, z)), (FW1 / 2, GROUND))) for x, z in ((-HALF_L, -HALF_W), (HALF_L, -HALF_W), (HALF_L, HALF_W), (-HALF_L, HALF_W))])
    door = screen((HALF_L + 0.6, 0.0, 0.0))
    print("door foot:", (round(door[0] - FW1 / 2, 1), round(door[1] - GROUND, 1)))
    if len(sys.argv) > 1:
        bg, sc = (58, 110, 70, 255), 6
        big = []
        for row in sheet:
            line = []
            for c in row:
                a = c[3] / 255.0
                col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
                line += [col] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), W * sc, FH * sc, big)
    print("gustav_wagon.png + gustav_wagon_glow.png written")
