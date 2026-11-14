"""The travelling merchant's caravan (docs/haendler_konzept.md 8.2, 8.3): Jorun's covered wagon that folds open into a market stall, and the shaggy ox that
pulls it. Same ellipsoid renderer as Gustav's wagon, the woodland animals and the heroine (tools/art_hero3d.py), lit from the upper left, ink outline.
    py -3 tools/art_caravan.py [preview.png]
Writes assets/town/caravan/:
  wagon_roll.png   8 rows (facings E SE S SW W NW N NE) x 4 columns (the wheels turn a quarter spoke per frame), frames 144x108, feet (72, 90)
  wagon_stand.png  2 rows (0 = parked facing east, 1 = facing west; the counter side always faces the viewer) x 11 columns:
                   0 shut, 1-8 unfolding (counter down, awning out), 9 open, 10 night (shut, lantern lit)
  wagon_*_glow.png only the emissive pixels (lantern, the light through the canvas at night), drawn unlit
  ox.png           8 rows (facings) x 22 columns: idle 0-3, walk 4-11, graze 12-17, lie 18-21; frames 80x64, feet (40, 54)
  ox_glow.png      the lantern on the yoke
and data/caravan_art.json (frames, feet, clips, where the goods lie on the counter, the lantern, the ox's distance ahead of the wagon).
No ground shadows are baked: CaravanView draws them."""
import json
import math
import sys
import pathlib
import numpy as np
import art_hero3d as h
from gen_art import hexc, CLEAR
from world_data import save_png

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "town" / "caravan"
V = lambda *a: np.array(a, float)

# ------------------------------------------------------------------ materials
BARK, PLANK, CANVAS, IRON, BRASS, LIGHT, CLOTH, DARK, GREEN, FUR, HOOF, HORN, EYE = range(13)
RAMPS = [
    ["1a1322", "34283c", "55435a", "85697a"],  # wheels, chassis: the trees' bark
    ["3a2530", "5e3f52", "7d5a6c", "a37f8c"],  # cared-for plum boards (the renewed hut's wood)
    ["1e2a44", "2a3f66", "3d5a8a", "6f93c4"],  # caravan blue canvas
    ["0e0d16", "1e1d2c", "3b3a50", "6a6a86"],  # iron
    ["4a3418", "7a5a24", "b4893a", "e6c468"],  # brass: bell, lantern frame
    ["c28a3a", "ffb84a", "ffd27a", "fff2c0"],  # lantern light (emissive)
    ["4a1e2a", "7a2f3c", "a8484e", "d27a6a"],  # red cloth: patches, pennants, the sign's paint
    ["07050b", "0d0a14", "15111f", "211a30"],  # the dark inside the wagon
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss in the ox's coat, green jars
    ["2e221c", "4e3a2c", "73563e", "9a7a56"],  # the ox's shaggy brown coat
    ["120e12", "241c22", "3a2e34", "54454a"],  # hooves, muzzle
    ["6e5e48", "a08c6c", "cdbb98", "efe2c4"],  # horns
    ["0a0810", "0a0810", "2a2230", "5a4a60"],  # eyes
]
GLOW_MATS = (LIGHT,)


def setup(fw, fh, ground):
    h.FW, h.FH, h.GROUND_ROW, h.SS, h.SCALE = fw, fh, float(ground), 3, 1.0
    h.RAMPS = [[hexc(c) for c in row] for row in RAMPS]
    h.TIDY_EYES = False
    h.DECAL_WEIGHT = {BRASS: 1.6, LIGHT: 2.4, CLOTH: 1.3, EYE: 2.4, HORN: 1.4}
    h.ink_color = lambda mat: hexc("1b1a2e")


def yaw_of(d):
    """Facing index (E SE S SW W NW N NE) -> the model's yaw (the model looks along +z)."""
    return math.pi / 2 - d * math.pi / 4


def render(m, yaw):
    depth, code = h.render(m.transform(yaw, 0.0))
    rows = h.to_pixels(depth, code)
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in rows], np.uint8)


def glow(img):
    cols = {tuple(hexc(c)) + (255,) for mat in GLOW_MATS for c in RAMPS[mat]}
    out = np.zeros_like(img)
    for y in range(img.shape[0]):
        for x in range(img.shape[1]):
            if tuple(int(v) for v in img[y, x]) in cols:
                out[y, x] = img[y, x]
    return out


def screen(p, yaw):
    """Where a model point lands relative to the feet (px, y down)."""
    q = h.rot_y(yaw) @ V(*p) * h.SCALE
    return [round(float(q[0]), 1), round(float(-(q[1] * h.COSP - q[2] * h.SINP)), 1)]


# ------------------------------------------------------------------ the wagon (looks along +z)
HL, HW = 24.0, 12.0  # half length (z), half width (x) of the box
WHEEL_R, AXLE_Y = 8.0, 8.0
FLOOR_Y, RAIL_Y = 9.0, 21.0
WHEELS_Z = (-15.0, 15.0)
COUNTER_Y = 12.0
WAGON_SIZE = 1.3  # the model is built at 1 unit = 1 px and scaled up as a whole: a covered wagon stands well above a person


def wheel(m, centre, turn):
    """A spoked cart wheel in the y-z plane (axle along x)."""
    ctr = V(*centre)
    n = 14
    for i in range(n):
        a = i * 2 * math.pi / n + turn
        tang, rad = V(0, -math.sin(a), math.cos(a)) * 0 + V(0, math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)), V(0, math.cos(a), math.sin(a))
        R = np.stack([V(1, 0, 0), rad, tang], axis=1)
        m.ell(ctr + rad * (WHEEL_R - 0.9), (1.3, 1.3, WHEEL_R * math.pi / n + 0.35), BARK, R=R)
        m.ell(ctr + rad * (WHEEL_R + 0.25), (1.0, 0.45, WHEEL_R * math.pi / n + 0.2), IRON, R=R)
    for i in range(6):
        a = i * math.pi / 3 + turn
        m.limb(ctr + V(0, math.cos(a), math.sin(a)) * 1.6, ctr + V(0, math.cos(a), math.sin(a)) * (WHEEL_R - 1.2), 0.7, 0.6, BARK)
    m.ell(ctr, (1.8, 2.0, 2.0), IRON)


def wagon(turn=0.0, bob=0.0, fold=0.0, side=0, night=False, rng_seed=5):
    """`side` -1/+1: the x side whose wall folds down into the counter (0 = driving, nothing folds). `fold` 0 shut .. 1 open."""
    rng = np.random.default_rng(rng_seed)
    m = h.Model()
    E = lambda c, r, mat, R=None, kind="": m.ell(V(c[0], c[1] + bob, c[2]), r, mat, R=R, kind=kind)
    L = lambda a, b, r0, r1, mat, kind="": m.limb(V(a[0], a[1] + bob, a[2]), V(b[0], b[1] + bob, b[2]), r0, r1, mat, kind=kind)
    # chassis and axles
    for sx in (-1, 1):
        E((sx * 7.0, FLOOR_Y - 1.6, 0), (1.3, 1.3, HL + 1.0), BARK)
    for z in WHEELS_Z:
        m.limb(V(-HW - 3.5, AXLE_Y, z), V(HW + 3.5, AXLE_Y, z), 1.0, 1.0, BARK)
    # the floor
    E((0, FLOOR_Y, 0), (HW, 1.0, HL), PLANK)
    # walls: three boards each side, a band of red paint on the middle one
    for sx in (-1, 1):
        folding = sx == side and fold > 0.0
        for i in range(3):
            y = FLOOR_Y + 2.2 + i * 3.2
            if folding and i < 2:
                continue  # these two boards are the counter flap (drawn below)
            mat = CLOTH if i == 1 else PLANK
            E((sx * (HW + 0.2), y, rng.uniform(-0.2, 0.2)), (0.8, 1.55, HL), mat)
        for z in (-HL, -8.0, 8.0, HL):
            E((sx * (HW + 0.8), FLOOR_Y + 5.6, z), (1.0, 6.2, 1.0), BARK)  # posts
        E((sx * (HW + 0.6), RAIL_Y, 0), (1.0, 0.9, HL + 0.6), BARK)  # top rail
    for zz in (-HL - 0.4, HL + 0.4):  # front and back boards
        E((0, FLOOR_Y + 5.6, zz), (HW, 5.4, 0.8), PLANK)
    # the counter flap: two boards hinged at the floor rail; shut = upright in the wall, open = lying out at counter height on two legs
    if side != 0 and fold > 0.0:
        ang = fold * math.pi / 2  # 0 upright .. 90 degrees out
        hinge = V(side * (HW + 0.2), FLOOR_Y + 0.8, 0)
        out = V(side * math.sin(ang), math.cos(ang), 0)
        for i in range(2):
            c = hinge + out * (1.8 + i * 3.2)
            Rb = np.stack([V(math.cos(ang) * side, -math.sin(ang), 0) * -1 if False else np.cross(out, V(0, 0, 1)), out, V(0, 0, 1)], axis=1)
            m.ell(c + V(0, bob, 0), (0.8, 1.6, HL - 1.0), PLANK if i == 0 else CLOTH, R=Rb)
        if fold > 0.85:
            for z in (-HL + 3.0, HL - 3.0):  # the legs under the counter's outer edge
                tip = hinge + out * 6.6
                m.limb(V(tip[0], tip[1] - 0.6 + bob, z), V(tip[0], 0.3, z), 0.6, 0.6, BARK)
    # inside: a dark hold with crates and jars (seen once the wall is down)
    E((0, FLOOR_Y + 4.0, 0), (HW - 1.2, 4.0, HL - 1.2), DARK)
    if side != 0 and fold > 0.3:
        E((side * 1.0, RAIL_Y - 4.0, 0), (HW - 2.0, 0.6, HL - 2.0), PLANK)  # a shelf along the inside
        for k, z in enumerate(np.linspace(-HL + 4.0, HL - 4.0, 8)):
            E((side * 3.0, RAIL_Y - 2.2, z), (1.3, 1.6, 1.3), (GREEN, BRASS, CLOTH, PLANK)[k % 4])  # jars and bundles on the shelf
        for k, z in enumerate((-16.0, -6.0, 5.0, 15.0)):
            E((side * 6.0, FLOOR_Y + 3.0, z), (3.6, 2.6, 3.4), PLANK)  # crates
            E((side * 6.5, FLOOR_Y + 6.6, z + 1.0), (1.4, 1.4, 1.4), (GREEN, BRASS, CLOTH, GREEN)[k])
    # hoops and the canvas; with the stall open the canvas on the counter side is rolled up into an awning
    steps = 9
    for zc in (-18.0, -6.0, 6.0, 18.0):
        for k in range(steps):
            am = math.pi * (k + 0.5) / steps
            n = V(math.cos(am), math.sin(am), 0.0)
            on_side = side != 0 and (n[0] * side) > 0.25
            if on_side and fold > 0.0:
                continue
            c = V(0, RAIL_Y, zc) + n * (HW + 0.8)
            Rl = h.frame_from(n, V(-math.sin(am), math.cos(am), 0.0))
            E(c, (6.4, 1.0, HW * math.pi / steps / 2 + 1.1), CANVAS, R=Rl)
    for zc in (-HL + 0.5, HL - 0.5):  # the hoops at the ends, a little proud of the canvas
        for k in range(steps):
            a0, a1 = math.pi * k / steps, math.pi * (k + 1) / steps
            L((math.cos(a0) * (HW + 1.6), RAIL_Y + math.sin(a0) * (HW + 1.6), zc), (math.cos(a1) * (HW + 1.6), RAIL_Y + math.sin(a1) * (HW + 1.6), zc), 0.85, 0.85, PLANK)
    E((-4.0, RAIL_Y + 9.0, 8.0), (3.0, 0.5, 2.6), CLOTH, R=h.frame_from(V(-0.4, 0.9, 0), V(0, 0, 1)))  # a sewn patch
    for zc, closed in ((-HL - 0.3, True), (HL + 0.3, False)):  # the canvas ends: drawn shut at the back, a puckered opening over the bench at the front
        for k in range(steps):
            am = math.pi * (k + 0.5) / steps
            r_in = 0.0 if closed else HW * 0.62
            for rr in np.linspace(r_in + 1.6, HW + 0.6, 3):
                E((math.cos(am) * rr, RAIL_Y + math.sin(am) * rr, zc), (1.9, 1.9, 0.6), CANVAS)
        if closed:
            E((0, RAIL_Y + 1.0, zc), (HW, 2.0, 0.6), CANVAS)
    if side != 0 and fold > 0.0:
        # the awning: the rolled-up side canvas pulled out on two poles, edge a little lower
        reach = 1.0 + 5.0 * fold
        for k in range(3):
            t = (k + 0.5) / 3
            c = V(side * (HW + 1.6 + reach * t), RAIL_Y + 9.0 - 1.6 * t, 0)
            E(c, (reach / 6 + 0.8, 0.6, HL + 1.0), CANVAS, R=h.frame_from(V(side * 0.2, 1.0, 0), V(0, 0, 1)))
        E((side * (HW + 1.4), RAIL_Y + 9.6, 0), (1.3, 1.3, HL + 0.8), CANVAS)  # the roll at the ridge
        if fold > 0.6:
            for z in (-HL + 1.0, HL - 1.0):
                L((side * (HW + 1.6 + reach), RAIL_Y + 7.4, z), (side * (HW + 1.6 + reach), 0.3, z), 0.55, 0.55, BARK)
            for k, z in enumerate(np.linspace(-HL + 3.0, HL - 3.0, 7)):  # pennants along the awning's edge
                E((side * (HW + 1.8 + reach), RAIL_Y + 6.4, z), (0.5, 1.3, 0.9), (CLOTH, BRASS)[k % 2])
            E((side * (HW + 2.0 + reach), RAIL_Y + 3.6, -HL + 6.0), (0.5, 2.2, 4.2), PLANK)  # the sign hanging from the awning
            E((side * (HW + 2.5 + reach), RAIL_Y + 3.6, -HL + 6.0), (0.3, 1.0, 2.8), CLOTH)
    # the shafts and the driver's bench at the front
    for sx in (-1, 1):
        m.limb(V(sx * 5.5, FLOOR_Y - 1.0 + bob, HL), V(sx * 5.0, 12.0, HL + 20.0), 0.9, 0.75, BARK)
    E((0, FLOOR_Y + 9.5, HL + 1.6), (HW - 1.0, 0.9, 2.2), PLANK)  # bench
    E((0, FLOOR_Y + 6.0, HL + 2.6), (HW - 2.0, 3.0, 0.6), PLANK)
    # the bell and the lantern at the front corner
    L((HW - 1.0, RAIL_Y + 3.0, HL + 1.0), (HW + 1.5, RAIL_Y + 4.0, HL + 2.5), 0.4, 0.35, IRON)
    E((HW + 1.6, RAIL_Y + 2.4, HL + 2.6), (1.2, 1.5, 1.2), BRASS)  # bell
    L((-HW + 1.0, RAIL_Y + 2.0, HL + 1.0), (-HW - 2.0, RAIL_Y + 2.6, HL + 3.0), 0.4, 0.35, IRON)
    E((-HW - 2.0, RAIL_Y - 0.2, HL + 3.0), (1.3, 1.9, 1.3), LIGHT if (night or fold > 0.0) else BRASS, kind="emit" if (night or fold > 0.0) else "")
    E((-HW - 2.0, RAIL_Y + 1.9, HL + 3.0), (1.5, 0.5, 1.5), BRASS)
    if night:  # the light inside shows through the canvas: a warm slit at the back
        E((0, RAIL_Y + 3.0, -HL - 0.9), (2.4, 4.0, 0.4), LIGHT, kind="emit")
    # wheels
    for z in WHEELS_Z:
        for sx in (-1, 1):
            wheel(m, (sx * (HW + 2.2), WHEEL_R, z), turn + (0.3 if z > 0 else 0.0))
    for p in m.prims:
        p.c = p.c * WAGON_SIZE
        p.r = p.r * WAGON_SIZE
    return m


def counter_points(side, yaw):
    """Where the goods lie on the open counter, relative to the feet (8 places, left to right in the picture)."""
    pts = []
    for row, (out, dy) in enumerate(((5.6, 0.6), (3.2, 0.7))):
        for z in np.linspace(-HL + 5.0, HL - 5.0, 5 if row == 0 else 3):
            pts.append(screen(V(side * (HW + 0.2 + out), FLOOR_Y + 0.8 + dy + 0.9, z) * WAGON_SIZE, yaw))
    pts.sort(key=lambda p: (p[1], p[0]))
    return pts


# ------------------------------------------------------------------ the ox (looks along +z)
OX_BLOCKS = [("idle", 0, 4), ("walk", 4, 8), ("graze", 12, 6), ("lie", 18, 4)]
OX_COLS = 22
OX_SIZE = 1.3


def ox_leg(m, x, z, body_y, phase, lifted, lie):
    if lie:
        m.ell(V(x * 0.9, 1.6, z), (1.8, 1.4, 3.0), FUR)
        return
    p = phase * 2 * math.pi
    swing = 2.6 * math.sin(p) if lifted else 0.0
    lift = max(0.0, math.cos(p)) * 1.8 if lifted else 0.0
    hip = V(x, body_y - 3.0, z)
    knee = V(x, body_y * 0.45 + lift * 0.4, z + swing * 0.5 + 0.6)
    foot = V(x, 0.9 + lift, z + swing)
    m.limb(hip, knee, 2.2, 1.6, FUR)
    m.limb(knee, foot, 1.5, 1.2, FUR)
    m.ell(foot, (1.5, 0.9, 1.7), HOOF)


def ox(kind, t, seed=3):
    rng = np.random.default_rng(seed)
    m = h.Model()
    lie = kind == "lie"
    walk = kind == "walk"
    breathe = math.sin(t * 2 * math.pi) * 0.25
    by = (6.2 if lie else 13.0) + (math.cos(t * 4 * math.pi) * 0.3 if walk else breathe)
    # body: a deep barrel with a shoulder hump, shaggy fringes hanging below
    m.ell(V(0, by, 0), (5.6, 5.6 + breathe * 0.4, 11.0), FUR)
    m.ell(V(0, by + 3.0, 6.0), (5.0, 4.6, 5.0), FUR)  # hump
    m.ell(V(0, by - 0.4, -8.0), (5.0, 5.0, 4.4), FUR)  # rump
    for k in range(9):  # shaggy fringe along the belly and flanks
        z = -9.0 + k * 2.3
        for sx in (-1, 1):
            m.ell(V(sx * 4.6, by - 4.4 + rng.uniform(-0.3, 0.3), z), (1.3, 2.2, 1.5), FUR)
    for z, x in ((2.0, -2.0), (7.0, 1.5), (-5.0, 1.0)):  # moss in the coat
        m.ell(V(x, by + 5.0 + (2.0 if z == 7.0 else 0.0), z), (2.2, 0.8, 2.6), GREEN)
    # tail
    sw = math.sin(t * 2 * math.pi * (2 if kind == "idle" else 1)) * (1.6 if not lie else 0.4)
    m.limb(V(0, by + 2.0, -12.5), V(sw * 0.5, by - 3.0, -13.6), 0.7, 0.6, FUR)
    m.limb(V(sw * 0.5, by - 3.0, -13.6), V(sw, by - 7.0, -13.2), 0.6, 1.0, HOOF)
    # legs
    if lie:
        for x, z in ((-4.0, 7.0), (4.0, 7.5), (-4.5, -6.0), (4.5, -6.5)):
            ox_leg(m, x, z, by, 0, False, True)
    else:
        for i, (x, z) in enumerate(((-3.4, 7.0), (3.4, 7.0), (-3.6, -7.0), (3.6, -7.0))):
            ph = t + (0.0, 0.5, 0.25, 0.75)[i]
            ox_leg(m, x, z, by, ph, walk, False)
    # head: low on a thick neck, a broad muzzle, horns curling out and up, the yoke with a bell and a little lantern
    graze = kind == "graze"
    nod = (math.sin(t * 2 * math.pi) * 0.6 if walk else 0.0)
    if graze:
        hy, hz = 4.2 + abs(math.sin(t * 4 * math.pi)) * 0.6, 15.0
    elif lie:
        hy, hz = by + 1.0, 12.5
    else:
        hy, hz = by + 2.4 + nod, 14.5
    m.limb(V(0, by + 2.0, 8.0), V(0, hy + 0.5, hz - 2.0), 4.2, 3.2, FUR)
    m.ell(V(0, hy, hz), (3.4, 3.2, 3.6), FUR)
    m.ell(V(0, hy - 1.2, hz + 3.0), (2.4, 2.0, 2.0), HOOF)  # muzzle
    m.ell(V(0, hy + 2.2, hz + 0.6), (2.6, 1.4, 2.2), FUR)  # forelock
    for sx in (-1, 1):
        m.ell(V(sx * 2.6, hy + 0.6, hz + 1.6), (0.5, 0.5, 0.5), EYE)
        m.limb(V(sx * 2.6, hy + 1.8, hz - 0.4), V(sx * 6.0, hy + 2.4, hz - 0.2), 1.0, 0.75, HORN)
        m.limb(V(sx * 6.0, hy + 2.4, hz - 0.2), V(sx * 7.0, hy + 5.4, hz + 1.2), 0.75, 0.3, HORN)
        m.ell(V(sx * 3.6, hy + 0.4, hz - 1.4), (1.2, 0.6, 1.0), FUR)  # ears
    if not lie:
        yoke_y, yoke_z = by + 4.6, 9.5
        m.limb(V(-6.0, yoke_y, yoke_z), V(6.0, yoke_y, yoke_z), 1.0, 1.0, PLANK)
        m.ell(V(0, yoke_y - 2.4, yoke_z + 1.6), (1.1, 1.3, 1.1), BRASS)  # bell
        m.ell(V(5.6, yoke_y + 1.6, yoke_z), (0.9, 1.3, 0.9), LIGHT, kind="emit")  # the little lantern
    for p in m.prims:  # a big draught animal: the model is scaled up as a whole
        p.c = p.c * OX_SIZE
        p.r = p.r * OX_SIZE
    return m


# ------------------------------------------------------------------ sheets

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    W, H, G = 144, 108, 90
    setup(W, H, G)
    roll = np.zeros((8 * H, 4 * W, 4), np.uint8)
    for d in range(8):
        for k in range(4):
            roll[d * H:(d + 1) * H, k * W:(k + 1) * W] = render(wagon(turn=k * math.pi / 12, bob=0.5 if k % 2 else 0.0), yaw_of(d))
    save_png(OUT / "wagon_roll.png", roll)
    save_png(OUT / "wagon_roll_glow.png", glow(roll))
    stand = np.zeros((2 * H, 11 * W, 4), np.uint8)
    stands = [(0, -1), (4, 1)]  # facing east: its left (-x) side faces the viewer; facing west: its right (+x)
    for row, (d, side) in enumerate(stands):
        for k in range(11):
            if k == 10:
                m = wagon(side=side, fold=0.0, night=True)
            else:
                m = wagon(side=side, fold=k / 9.0)
            stand[row * H:(row + 1) * H, k * W:(k + 1) * W] = render(m, yaw_of(d))
    save_png(OUT / "wagon_stand.png", stand)
    save_png(OUT / "wagon_stand_glow.png", glow(stand))
    meta = {
        "wagon": {"frame": [W, H], "feet": [W // 2, G], "roll_frames": 4, "stand_frames": 11, "night_frame": 10, "open_frame": 9,
                  "display": [counter_points(side, yaw_of(d)) for d, side in stands],
                  "lantern": screen(V(-HW - 2.0, RAIL_Y - 0.2, HL + 3.0) * WAGON_SIZE, yaw_of(0)),
                  "ox_ahead": (HL + 20.0) * WAGON_SIZE + 14.0},
    }
    OW, OH, OG = 80, 64, 54
    setup(OW, OH, OG)
    sheet = np.zeros((8 * OH, OX_COLS * OW, 4), np.uint8)
    for d in range(8):
        for kind, start, n in OX_BLOCKS:
            for i in range(n):
                sheet[d * OH:(d + 1) * OH, (start + i) * OW:(start + i + 1) * OW] = render(ox(kind, i / n), yaw_of(d))
    save_png(OUT / "ox.png", sheet)
    save_png(OUT / "ox_glow.png", glow(sheet))
    meta["ox"] = {"frame": [OW, OH], "feet": [OW // 2, OG], "frames": OX_COLS,
                  "clips": {k: {"start": s, "count": n, "fps": {"idle": 3, "walk": 8, "graze": 4, "lie": 2}[k]} for k, s, n in OX_BLOCKS}}
    (ROOT / "data" / "caravan_art.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    if len(sys.argv) > 1:
        bg = np.array([58, 110, 70, 255], np.uint8)
        a = stand[:, :, 3:4].astype(float) / 255.0
        big = (stand[:, :, :3] * a + bg[:3] * (1 - a)).astype(np.uint8)
        b2 = roll[:, :, 3:4].astype(float) / 255.0
        big2 = (roll[:, :, :3] * b2 + bg[:3] * (1 - b2)).astype(np.uint8)
        o2 = sheet[:, :, 3:4].astype(float) / 255.0
        big3 = (sheet[:, :, :3] * o2 + bg[:3] * (1 - o2)).astype(np.uint8)
        wmax = max(big.shape[1], big2.shape[1], big3.shape[1])
        pad = lambda img: np.pad(img, ((0, 0), (0, wmax - img.shape[1]), (0, 0)), constant_values=40)
        comp = np.concatenate([pad(big), pad(big2), pad(big3)], axis=0)
        comp = comp.repeat(2, 0).repeat(2, 1)
        save_png(pathlib.Path(sys.argv[1]), comp)
    print("caravan art written to", OUT)


if __name__ == "__main__":
    main()
