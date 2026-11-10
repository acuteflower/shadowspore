#!/usr/bin/env python3
"""The plant world of the Hexenwald (stdlib only; builds on the meadow's art scripts so both worlds share light and grain):
  assets/props/hag_tree.png          Hexenulme: 4 gnarled, twisted trees (80, 114, 148, 178 px) under torn dark crowns with
                                     witch-hair moss and hanging bone charms; 4 rows of 112x200 frames, feet (56, 196):
                                     0 trunk, 1 crown, 2 crown glow, 3 trunk glow (like tree.png)
  assets/props/bone_tree.png         Bleichbaum: 4 dead, bleached trees (72, 102, 134, 162 px), clawed bare boughs with
                                     twig charms, red rags and caged wisps; the same rows
  assets/props/{hag,bone}_tree_growth.png   stump (small), stump (large), sapling, young tree
  assets/props/thorn_hedge.png       Dornenhecke: 3 tangles x 2 rows (with hex berries, picked) + _glow + _stripped
  assets/props/grave_candle.png      Totenkerze: 3 stands of waxen flower candles with a ghost-green flame x 2 rows (lit, picked)
  assets/props/witch_hat.png         Hexenhut: 3 stands of violet hooded blooms shaped like crooked hats x 2 rows
  assets/props/toad_cap.png          Krötenschirm: 3 groups of squat wine-red toadstools with pale warts x 2 rows
  assets/props/ghost_fern.png        Geisterfarn: 3 pale ferns x 2 rows (+ _stripped), the Leuchtfern in a ghost palette
  assets/props/mandrake.png          Alraune: 3 leaf rosettes with a root face showing x 2 rows (in the ground, pulled)
  assets/props/curse_rock.png        Fluchsilber: 6 dark rocks shot through with pale green silver x 4 states (64x56, like iron_rock.png)
  every sheet has a `_glow` twin with only the emissive pixels
  assets/items/{hag_wood,bone_wood,hex_thorn,hex_berry,grave_candle,witch_hat,toad_cap,ghost_frond,mandrake,curse_silver}.png
Palette: the meadow's light (top left, cool rim right, ink outline) at the Hexenwald's cold dusk: foliage between
blue-black and a dull sea green, bark almost black, bone white, wine red, and the wood's own light, a sickly witch green.

  python3 tools/art_hexenwald.py            writes everything
  python3 tools/art_hexenwald.py preview    also writes docs/img/hexenwald_flora.png (day above, night below)"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_flora as F  # noqa: E402
import art_iron as I  # noqa: E402
import art_stone as S  # noqa: E402
import art_tree  # noqa: E402
from art_brush import Glow, outline, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, check_icon, clamp, put_shadow  # noqa: E402
from art_spruce import CH, CW, FEET_X, FEET_Y, Emitters, grid  # noqa: E402
from art_spruce import put as tput  # noqa: E402
from art_willow import lobes_shade  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402


def ramp(*c):
    return [hexc(x) for x in c]


LEAF = ramp("0a0e20", "0f1c2c", "15303a", "1d4a48", "2d6a58", "4e9070")  # blue-black shade .. dull sea green
GREEN = ramp("0a1020", "10242c", "183c3a", "24584a", "3a785a", "62a070")  # small plants: a little livelier, still cold
RIM = ramp("1c5a6a", "3a9aa8")
BARK = ramp("0c0812", "1a1322", "2c2236", "44344c", "625064", "8c7880")  # almost black, violet in the shade
BONE = ramp("2e2a44", "56506c", "8a8698", "b8b4b8", "dedacc", "f6f2e0")  # bleached wood, violet shade
HEX_DIM, HEX, HEX_HOT = hexc("4a9a3a"), hexc("a8ff6a"), hexc("eaffc4")  # the wood's own light: witch green
VIO_DIM, VIO, VIO_HOT = hexc("6434a6"), hexc("c690ec"), hexc("ecdcff")  # its second light: a cold violet (lichen on the dead wood, fungi, buds)
LICHEN = ramp("2e3a40", "4c6060", "7a9488", "a8c4b0")  # pale crust lichen on bark and bone
VIO, VIO_L = hexc("8a4dff"), hexc("d9c8ff")
WINE = ramp("2a0612", "5a0a1e", "8e1430", "c43044", "ee6a6a")
HAIR = ramp("1e3038", "34504e", "557468", "86a08a")  # witch-hair moss: grey-green
HOOD = ramp("120a26", "26124a", "40207a", "6434a6", "9458cc", "c690ec")
WAX = ramp("4a4664", "7c7894", "b0acbc", "dcd8d4", "fbf8e8")
ROOT_C = ramp("2a1c22", "46322e", "6a4e42", "927460", "c0a484")
CUT = ramp("3a2c40", "5e4a5c", "8a7480", "b8a4a4")
RAG = ramp("5a0a1e", "9a1830", "d03a48")
ICON_OUT = hexc("1b1a2e")


# ================================================================== trees
def limb(g, x, y, ang, length, width, depth, rng, wood, tips, bend=None):
    """A crooked, tapering bough from (x, y): it kinks, forks into two thinner ones and ends in a claw. Collects its tips."""
    bend = rng.uniform(-0.035, 0.035) if bend is None else bend
    steps = max(2, int(length))
    for i in range(steps):
        t = i / steps
        w = width * (1.0 - 0.45 * t)
        for k in range(-int(w + 0.5), int(w + 0.5) + 1):
            if abs(k) > w and w >= 0.5:
                continue
            vertical = abs(math.sin(ang)) > 0.6  # a rising bough is lit on its left, a lying one on its top
            lit = -k / max(w, 0.6)
            tone = 2.4 + lit * 1.7 + (noise(int(x), int(y), 77) / 255.0 - 0.5) * 0.9
            px, py = (int(round(x)) + k, int(round(y))) if vertical else (int(round(x)), int(round(y)) + k)
            tput(g, px, py, wood[int(clamp(tone, 0, len(wood) - 2))])
        ang += bend + (rng.uniform(-0.3, 0.3) if i % 5 == 4 else 0.0)  # knuckles
        ang -= 0.012 * math.cos(ang) * (1 if depth > 1 else 0)  # the young wood strives up
        x += math.cos(ang)
        y += math.sin(ang)
    if depth <= 0 or width < 0.45:
        hook = 1 if math.cos(ang) > 0 else -1
        for k in range(1, 4):  # the claw
            tput(g, int(round(x)) + (hook if k > 1 else 0), int(round(y)) + k - 1, wood[1 if k > 1 else 2])
        tips.append((int(round(x)), int(round(y))))
        return
    spread = rng.uniform(0.5, 0.85)
    side = rng.choice((-1, 1))
    limb(g, x, y, ang - side * spread * 0.55, length * rng.uniform(0.6, 0.78), width * 0.62, depth - 1, rng, wood, tips)
    limb(g, x, y, ang + side * spread, length * rng.uniform(0.45, 0.62), width * 0.5, depth - 1, rng, wood, tips)
    if depth >= 3 and rng.random() < 0.6:
        limb(g, x, y, ang + rng.uniform(-0.25, 0.25), length * 0.5, width * 0.45, depth - 2, rng, wood, tips)


def trunk_body(g, glow, lights, spec, rng, seed, wood, extras, face):
    """The twisted trunk: an S-curve of spiral furrows, knots, clawing roots; `face` hollows two slit eyes and a mouth into it."""
    top, hw0, twist = FEET_Y - spec["trunk"], spec["trunk_hw"], spec["twist"]
    phase = rng.random() * 6.0
    centers = {}
    n = len(wood)
    for y in range(top, FEET_Y + 1):
        t = (FEET_Y - y) / max(spec["trunk"], 1)
        cx = FEET_X + twist * (math.sin(t * 3.4 + phase) - math.sin(phase)) * (0.4 + 0.6 * t)
        bulge = 1.0 + 0.16 * math.sin(t * 9.0 + phase * 2.0)  # gnarls
        hw = hw0 * (1.0 - 0.38 * t) * bulge + max(0.0, (y - (FEET_Y - 9)) * 0.75)
        centers[y] = (int(round(cx)), hw)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = int(round(cx)) + dx
            lit = 0.5 - 0.52 * dx / max(hw, 1.0)
            furrow = ((dx * 1.3 + (FEET_Y - y) * 0.55 * (1 if twist >= 0 else -1) + noise(x // 3, y // 5, seed) / 60.0) % 4.2) < 1.15  # the bark winds round the trunk
            v = lit * (n - 1.6) + (noise(x, y, seed + 2) / 255.0 - 0.5) * 1.0 - (1.2 if furrow else 0.0) + (0.5 if furrow is False and (dx + y) % 5 == 0 and lit > 0.4 else 0.0)
            g[y][x] = wood[int(clamp(v, 0, n - 2))]
            if wood is BARK and y > FEET_Y - 13 and dx < 1 and noise(x, y, seed + 8) > 165 and noise(x // 2, y // 2, seed + 9) > 110:
                g[y][x] = HAIR[1 + int(noise(x, y, seed + 4) > 150)]
    for side in (-1, 1):  # roots like fingers gripping the ground
        for r in range(2 if hw0 > 4 else 1):
            length = int(hw0 * (1.9 - 0.5 * r)) + 5 + rng.randrange(0, 3)
            for k in range(length):
                x = FEET_X + side * (int(hw0 * (0.7 if r else 1.0)) + k)
                arch = int(round(2.2 * math.sin(k / length * math.pi) * (1 if r == 0 else 0.4)))
                y = FEET_Y - max(0, 4 - k // 2) - arch + (2 if k > length - 3 else 0) + r
                thick = 3 if k < length // 2 else (2 if k < length - 2 else 1)
                for yy in range(y, min(y + thick, FEET_Y + 2)):
                    tput(g, x, yy, wood[int(clamp((3 if side < 0 else 2) - k // 4 + (1 if yy == y else 0), 0, n - 2))])
    for f in (0.34, 0.6, 0.8):  # knots and broken stubs
        y = FEET_Y - int(spec["trunk"] * f) + rng.randrange(-3, 4)
        if y not in centers or spec["trunk"] < 30:
            continue
        cx, hw = centers[y]
        side = rng.choice((-1, 1))
        for k in range(rng.randrange(3, 7)):
            tput(g, cx + side * (int(hw) + k), y - k // 3, wood[3 if side < 0 else 2])
            tput(g, cx + side * (int(hw) + k), y - k // 3 + 1, wood[1])
        kx = cx - side * int(hw * 0.3)
        for dx, dy, c in ((0, 0, 0), (1, 0, 1), (-1, 0, 3), (0, -1, 3), (0, 1, 1)):
            tput(g, kx + dx, y + 5 + dy, wood[c])
    if not extras:
        return centers
    if face and spec["trunk"] >= 40:  # a hollow face: two slanted eyes burning witch green, a ragged mouth
        y = FEET_Y - int(spec["trunk"] * 0.52)
        cx, hw = centers[y]
        e = max(2, int(hw * 0.45))
        for side in (-1, 1):
            for k in range(3):
                tput(g, cx + side * (e + k - 1) - 1, y - (k if side > 0 else 2 - k) + 1, wood[0])
                tput(g, cx + side * (e + k - 1) - 1, y - (k if side > 0 else 2 - k) + 2, wood[0])
            lights.pixel(g, cx + side * e - 1, y + 1, HEX_DIM, HEX, 2)
        for k in range(-e, e + 1):
            tput(g, cx + k - 1, y + 6 + (1 if k % 2 else 0) + abs(k) // 3, wood[0])
        tput(g, cx - 1, y + 8, wood[0])
    dim_c, mid_c, hot_c = (HEX_DIM, HEX, HEX_HOT) if wood is BARK else (VIO_DIM, VIO, VIO_HOT)
    for v in range(spec.get("veins", 0)):  # a short crack with the wood's light in it: it wanders, forks once, and breaks off
        y = FEET_Y - int(spec["trunk"] * (rng.uniform(0.1, 0.55) if wood is BARK else rng.uniform(0.4, 0.85)))  # the dead wood cracks high up
        off = rng.uniform(-0.55, 0.25)
        drift = 0.0
        for k in range(int(spec["trunk"] * rng.uniform(0.05, 0.1)) + 3):
            if y - k not in centers:
                break
            cx, hw = centers[y - k]
            drift += rng.choice((-1, 0, 0, 1)) * 0.45
            xx = cx + int(round(off * hw + drift))
            if abs(xx - cx) < hw - 0.5 and rng.random() > 0.18:
                lights.pixel(g, xx, y - k, dim_c, mid_c if rng.random() < 0.6 else dim_c, 0)
                if k == 3 and rng.random() < 0.6:  # one short fork
                    for j in range(1, 4):
                        lights.pixel(g, xx + j * (1 if off < 0 else -1), y - k - j // 2, dim_c, mid_c, 0)
    for _ in range(spec.get("lichen", 0)):  # crusts of pale lichen on the lit side, a few of their dots glowing
        y = FEET_Y - int(spec["trunk"] * rng.uniform(0.12, 0.92))
        if y not in centers:
            continue
        cx, hw = centers[y]
        x0 = cx - int(hw * rng.uniform(0.0, 0.7))
        for _k in range(rng.randrange(4, 9)):
            xx, yy = x0 + rng.randrange(-2, 3), y + rng.randrange(-2, 3)
            if yy in centers and abs(xx - centers[yy][0]) < centers[yy][1] - 0.5:
                tput(g, xx, yy, LICHEN[rng.randrange(1, 4)])
        if rng.random() < 0.7:
            lights.pixel(g, x0, y, LICHEN[3], (mid_c if rng.random() < 0.5 else (HEX if wood is BARK else VIO)), 1)
    for f in range(spec.get("fungi", 0)):  # pale shelf fungi, wine red underneath
        y = FEET_Y - int(spec["trunk"] * rng.uniform(0.15, 0.85))
        if y not in centers:
            continue
        cx, hw = centers[y]
        side = -1 if f % 2 else 1
        for i in range(4):
            x = cx + side * (int(hw) + i)
            tput(g, x, y + (1 if i > 2 else 0), BONE[4 if i < 3 else 3])
            tput(g, x, y + 1 + (1 if i > 2 else 0), WINE[2 if i < 2 else 1])
        lights.pixel(g, cx + side * (int(hw) + 1), y - 1, BONE[5], VIO_HOT if wood is BARK else HEX_HOT, 1)
        for i in range(1, 3):  # the gills underneath breathe light
            lights.pixel(g, cx + side * (int(hw) + i), y + 2 + (1 if i > 2 else 0), WINE[1], VIO if wood is BARK else HEX, 0)
    return centers


def charm(g, lights, x, y, kind, rng, extras):
    """What witches hang into trees, on a thread from (x, y): a twig triangle, a bone, a rag or a caged wisp."""
    thread = rng.randrange(3, 8)
    for k in range(1, thread + 1):
        tput(g, x, y + k, HAIR[0], over=False)
    cy = y + thread + 1
    if kind == "twig":  # a triangle of sticks with the light caught inside
        for k in range(4):
            tput(g, x - k, cy + k, BARK[4])
            tput(g, x + k, cy + k, BARK[3])
        for k in range(-3, 4):
            tput(g, x + k, cy + 4, BARK[4 if k < 0 else 2])
        if extras:
            lights.pixel(g, x, cy + 2, HEX_DIM, HEX, 2)
    elif kind == "bone":
        for k in range(4):
            tput(g, x, cy + k, BONE[5 if k < 2 else 4])
        tput(g, x - 1, cy, BONE[4])
        tput(g, x + 1, cy + 3, BONE[3])
    elif kind == "rag":
        for k in range(rng.randrange(4, 8)):
            tput(g, x + (1 if (k // 2) % 2 else 0), cy + k - 1, RAG[2 if k < 2 else (1 if k < 5 else 0)])
    else:  # a wisp in a cage of twigs
        for dx, dy in ((-1, 0), (1, 0), (-2, 1), (2, 1), (-2, 2), (2, 2), (-1, 3), (1, 3), (0, 4), (0, -1)):
            tput(g, x + dx, cy + dy, BARK[3 if dx < 0 else 2])
        tput(g, x, cy + 2, HEX_DIM)
        if extras:
            lights.pixel(g, x, cy + 1, HEX, HEX_HOT, 3)
            lights.pixel(g, x, cy + 2, HEX_DIM, HEX, 1)


HAGS = [
    dict(height=80, w=58, h=46, trunk_hw=4.4, twist=2.0, masses=3, hair=5, charms=1, veins=0, fungi=1, lichen=2, vines=2),
    dict(height=114, w=78, h=60, trunk_hw=6.0, twist=3.2, masses=4, hair=9, charms=2, veins=1, fungi=2, lichen=3, vines=5),
    dict(height=148, w=96, h=74, trunk_hw=7.8, twist=4.4, masses=5, hair=14, charms=4, veins=1, fungi=3, lichen=4, vines=7),
    dict(height=178, w=106, h=86, trunk_hw=9.2, twist=5.4, masses=6, hair=18, charms=5, veins=1, fungi=4, lichen=6, vines=8),
]
HAG_SAPLING = dict(height=38, w=24, h=20, trunk_hw=1.6, twist=0.8, masses=1, hair=0, charms=0, veins=0, fungi=0)
HAG_YOUNG = dict(height=70, w=44, h=36, trunk_hw=3.2, twist=1.6, masses=3, hair=2, charms=0, veins=0, fungi=0)
# the crown's masses: (u across the half width, v down the crown's height, size): a high hunched head, drooping shoulders
MASSES = [(-0.10, 0.30, 1.0), (-0.58, 0.56, 0.78), (0.54, 0.46, 0.84), (0.20, 0.13, 0.6), (0.84, 0.74, 0.5), (-0.88, 0.80, 0.48)]


def bough(g, p0, p1, w0, wood, rng):
    """A bough from the fork to a mass of leaves: a kinked arc, tapering, lit on its upper left."""
    mid = (p0[0] + (p1[0] - p0[0]) * 0.2 + rng.uniform(-2, 2), p0[1] + (p1[1] - p0[1]) * 0.75)
    pts = bezier(p0, mid, p1, n=int(abs(p1[0] - p0[0]) + abs(p1[1] - p0[1])) * 2 + 4)
    for i, (x, y) in enumerate(pts):
        t = i / len(pts)
        r = max(0.6, w0 * (1.0 - 0.7 * t))
        for yy in range(int(y - r), int(y + r) + 1):
            for xx in range(int(x - r), int(x + r) + 1):
                if math.hypot(xx - x, yy - y) <= r:
                    lit = (-(xx - x) * 0.6 - (yy - y) * 0.8) / max(r, 0.6)
                    tput(g, xx, yy, wood[int(clamp(2.3 + lit * 1.9 + (noise(xx, yy, 5) / 255.0 - 0.5) * 0.9, 0, len(wood) - 2))])


def hag_tree(spec, seed, extras=True):
    """Hexenulme: the crown is not one ball but hunched masses of dark leaves on crooked boughs, a high head and drooping
    shoulders with holes between them where the bare wood shows; claws reach out of it, grey witch hair and charms hang
    from the hems."""
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    w, h = spec["w"], spec["h"]
    top_y = FEET_Y - spec["height"]
    spec = dict(spec, trunk=int(spec["height"] - h * 0.6))
    centers = trunk_body(trunk, glow_t, lights_t, spec, rng, seed, BARK, extras, face=True)
    fork_y = FEET_Y - spec["trunk"]
    fx = centers[fork_y][0]
    boughs, lobes, tips = grid(), [], []
    flip = rng.choice((-1, 1))
    for u, v, size in MASSES[: spec["masses"]]:
        rad = max(5.0, size * w * 0.2)
        mx = clamp(FEET_X + flip * u * (w * 0.5 - rad * 0.55), FEET_X - w / 2 + rad * 0.8 + 2, FEET_X + w / 2 - rad * 0.8 - 2)
        my = top_y + max(v * h, rad * 0.75 + 4)
        bough(boughs, (fx, fork_y + 3), (mx, my + rad * 0.25), spec["trunk_hw"] * 0.62 * (0.6 + 0.4 * size), BARK, rng)
        for _ in range(7 + int(rad * 0.9)):  # cushions of leaves, flatter than round, heavier below
            a, r = rng.uniform(0, math.tau), math.sqrt(rng.random())
            lr = clamp(rad * rng.uniform(0.3, 0.5), 3.4, 9.0)
            lobes.append((mx + math.cos(a) * r * rad * 0.95, my + math.sin(a) * r * rad * 0.62, lr, lr * 0.82, my * 0.03 + rng.uniform(0, 2)))
        for k in range(int(rad / 2.2)):  # tatters under the hem
            lobes.append((mx + rng.uniform(-1, 1) * rad * 0.95, my + rad * rng.uniform(0.5, 0.85), rng.uniform(1.8, 3.2), rng.uniform(2.4, 4.6), 6.0))
        if rad > 6:
            for side in (-1, 1):  # claws reaching out of the leaves
                if rng.random() < 0.75:
                    limb(boughs, mx + side * rad * 0.45, my - rad * 0.3, -math.pi / 2 + side * rng.uniform(0.3, 1.0), rad * rng.uniform(0.55, 0.8), 0.9, 1, rng, BARK, tips)
    half = w / 2 - 1
    lobes = [(clamp(x, FEET_X - half + rx, FEET_X + half - rx), max(top_y + ry + 2, y), rx, ry, z) for x, y, rx, ry, z in lobes]
    for y in range(CH):
        for x in range(CW):
            if boughs[y][x] is not None and trunk[y][x] is None and abs(x - FEET_X) <= half and y > top_y:
                trunk[y][x] = boughs[y][x]
    lobes_shade(crown, lobes, LEAF, seed + 1, -0.3)
    pixels = [(x, y) for y in range(CH) for x in range(CW) if crown[y][x] is not None]
    for x, y in pixels:  # leaf texture: scalloped rows, violet in the deepest shade, a rare dead wine-red leaf
        k = LEAF.index(crown[y][x])
        if (x + (y // 3) * 2) % 5 == 0 and y % 3 == 0 and 1 <= k <= 4:
            crown[y][x] = LEAF[k - 1]
        elif (x + (y // 3) * 2) % 5 == 1 and y % 3 == 1 and 1 <= k <= 3:
            crown[y][x] = LEAF[k + 1]
        if k == 0 and noise(x, y, seed + 6) > 170:
            crown[y][x] = HOOD[1]
        elif 2 <= k <= 3 and noise(x, y, seed + 7) > 253:
            crown[y][x] = WINE[2]
    for y in range(1, CH - 1):  # lit contour on top and left, cool rim on the right
        for x in range(1, CW - 1):
            c = crown[y][x]
            if c is None or c not in LEAF:
                continue
            k = LEAF.index(c)
            if crown[y - 1][x] is None:
                crown[y][x] = LEAF[min(k + 2, 5)]
            elif crown[y][x - 1] is None and k < 5:
                crown[y][x] = LEAF[k + 1]
            elif crown[y][x + 1] is None and noise(x, y, seed + 9) > 110 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 170)]
    hem = [(x, y) for y in range(int(top_y + h * 0.4), CH - 30) for x in range(2, CW - 2) if crown[y][x] in LEAF and crown[y + 1][x] is None and trunk[y + 1][x] is None]
    if hem and extras:
        for _ in range(spec["hair"]):  # witch hair: long grey strands, the tips catching light
            x, y = hem[rng.randrange(len(hem))]
            length = rng.randrange(5, 9 + int(h * 0.26))
            for k in range(length):
                xx = x + int(round(math.sin(k * 0.35 + x) * min(k / 8.0, 1.0)))
                tput(crown, xx, y + 1 + k, HAIR[1 if k < length * 0.4 else (2 if k < length - 2 else 3)], over=False)
            if rng.random() < 0.4:
                lights_c.pixel(crown, x + int(round(math.sin((length - 1) * 0.35 + x) * min((length - 1) / 8.0, 1.0))), y + length, HAIR[3], VIO if rng.random() < 0.34 else HEX, 0)
        for i in range(spec["charms"]):
            x, y = hem[rng.randrange(len(hem))]
            charm(crown, lights_c, x, y, ("twig", "bone", "wisp", "twig", "rag")[i % 5], rng, extras)
        for _ in range(2 + int(w / 20)):  # eyes of light deep in the leaves
            x, y = pixels[rng.randrange(len(pixels))]
            if crown[y][x] in LEAF[:3]:
                lights_c.pixel(crown, x, y, HEX_DIM, HEX, 1)
    vines, vine_mask, vine_glow = hang_vines(hem if extras else [], spec, h, rng, seed)
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t, "vines": vines, "vine_mask": vine_mask, "vine_glow": vine_glow}


def hang_vines(hem, spec, h, rng, seed):
    """Ivy ropes hanging from the crown's hem: a dark rope with leaves in pairs and a curled tip, some with a bud of light. They live on
    their own layer (tools: hag_tree_vines.png) and breathe in the game (vine_breathe.gdshader), so the mask holds for every pixel how
    far down its rope it hangs (0 at the hem .. 1 at the tip, red channel): the further down, the further it sways."""
    art, mask, glow = grid(), grid(), grid()
    lights = Emitters(glow)
    if not hem:
        return art, mask, glow
    picks = sorted(hem, key=lambda p: noise(p[0], p[1], seed + 21))
    used = []
    for x, y in picks:
        if len(used) >= spec.get("vines", 0):
            break
        if any(abs(x - a) < 5 for a, _ in used) or y > CH - 40:
            continue
        used.append((x, y))
        length = rng.randrange(12, 16 + int(h * 0.42))
        phase = rng.uniform(0, 6.3)
        side = 1 if rng.random() < 0.5 else -1
        last = (x, y)
        for k in range(length):
            w = (k + 1) / length
            xx = x + int(round(1.6 * math.sin(k * 0.21 + phase) * min(k / 6.0, 1.0)))
            yy = y + 1 + k
            put_m = lambda px_, py_, c, ww=w: (tput(art, px_, py_, c), tput(mask, px_, py_, (int(ww * 255), 0, 0, 255)))  # noqa: E731
            put_m(xx, yy, LEAF[2] if (k // 2) % 2 else LEAF[1])
            if k > 2 and k % 4 == 1 and k < length - 2:  # a pair of small leaves, alternating sides, lit on the upper left
                side = -side
                put_m(xx + side, yy, LEAF[3] if side < 0 else LEAF[2])
                put_m(xx + side * 2, yy - 1, LEAF[4] if side < 0 else LEAF[3])
                if rng.random() < 0.4:
                    put_m(xx + side * 2, yy, LEAF[2])
            last = (xx, yy)
        lx, ly = last  # the curled tip: a little heart of leaves
        for dx, dy, c in ((-1, 1, 3), (0, 1, 2), (1, 1, 2), (0, 2, 1), (-1, 0, 4)):
            tput(art, lx + dx, ly + dy, LEAF[c])
            tput(mask, lx + dx, ly + dy, (255, 0, 0, 255))
        if rng.random() < 0.3:
            lights.pixel(art, lx, ly + 2, VIO_DIM, VIO if rng.random() < 0.6 else HEX, 0)
            tput(mask, lx, ly + 2, (255, 0, 0, 255))
    lights.halos()
    for y in range(CH):  # the halo pixels sway with the bud they belong to
        for x in range(CW):
            if glow[y][x] is not None and mask[y][x] is None:
                mask[y][x] = (255, 0, 0, 255)
    src = [row[:] for row in art]  # ink outline round ropes and leaves
    for y in range(CH):
        for x in range(CW):
            if src[y][x] is not None:
                continue
            for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= a < CW and 0 <= b < CH and src[b][a] is not None:
                    art[y][x] = art_tree.OUT
                    mask[y][x] = mask[b][a]
                    break
    return art, mask, glow


BONES = [
    dict(height=72, w=50, trunk=30, trunk_hw=3.4, twist=1.6, depth=2, charms=1, rags=1, veins=1, fungi=0, lichen=2),
    dict(height=102, w=66, trunk=42, trunk_hw=4.6, twist=2.6, depth=3, charms=2, rags=2, veins=1, fungi=1, lichen=3),
    dict(height=134, w=84, trunk=56, trunk_hw=6.0, twist=3.6, depth=4, charms=4, rags=3, veins=2, fungi=2, lichen=4),
    dict(height=162, w=96, trunk=70, trunk_hw=7.0, twist=4.4, depth=4, charms=5, rags=4, veins=2, fungi=2, lichen=5),
]
BONE_SAPLING = dict(height=36, w=20, trunk=16, trunk_hw=1.2, twist=0.6, depth=1, charms=0, rags=0, veins=0, fungi=0)
BONE_YOUNG = dict(height=64, w=40, trunk=26, trunk_hw=2.6, twist=1.2, depth=2, charms=0, rags=0, veins=0, fungi=0)


def bone_tree(spec, seed, extras=True):
    """Bleichbaum: long dead, stripped of bark and bleached like bone. Its crown is only boughs: crooked fingers against the
    dark, hung with charms, rags and caged wisps."""
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    centers = trunk_body(trunk, glow_t, lights_t, spec, rng, seed, BONE, extras, face=False)
    fork_y = FEET_Y - spec["trunk"]
    fx = centers[fork_y][0]
    reach = spec["height"] - spec["trunk"]
    tips = []
    for attempt in range(40):  # grow until the boughs fill the frame without leaving it
        test, tips = grid(), []
        r2 = random.Random(seed * 31 + attempt)
        for i, a in enumerate((-2.3, -1.6, -0.85)):
            limb(test, fx, fork_y + 2, a + r2.uniform(-0.12, 0.12), reach * (0.36 if i != 1 else 0.42), spec["trunk_hw"] * 0.62, spec["depth"], r2, BONE, tips)
        xs = [x for y in range(CH) for x in range(CW) if test[y][x] is not None]
        ys = [y for y in range(CH) for x in range(CW) if test[y][x] is not None]
        if min(xs) >= FEET_X - spec["w"] / 2 and max(xs) <= FEET_X + spec["w"] / 2 and min(ys) >= FEET_Y - spec["height"] - 2 and max(xs) - min(xs) > spec["w"] * 0.6:
            break
    for y in range(CH):
        for x in range(CW):
            if test[y][x] is not None:
                (crown if y < fork_y - 4 else trunk)[y][x] = test[y][x] if trunk[y][x] is None or y < fork_y - 4 else trunk[y][x]
    for y in range(1, CH - 1):  # violet shade under every bough, a cool rim on the right
        for x in range(1, CW - 1):
            if crown[y][x] in BONE and crown[y + 1][x] is None and crown[y - 1][x] is not None:
                crown[y][x] = BONE[1]
    if extras:
        hang = [t for t in tips if t[1] < fork_y - 6]
        rng.shuffle(hang)
        kinds = ["wisp", "twig", "bone", "twig", "wisp"]
        for i, (x, y) in enumerate(hang[: spec["charms"]]):
            charm(crown, lights_c, x, y + 1, kinds[i % 5], rng, extras)
        for x, y in hang[spec["charms"]: spec["charms"] + spec["rags"]]:
            charm(crown, lights_c, x, y + 1, "rag", rng, extras)
        for x, y in hang[spec["charms"] + spec["rags"]:][:4]:  # a shred of witch hair on the rest
            for k in range(rng.randrange(3, 8)):
                tput(crown, x, y + 2 + k, HAIR[2 if k < 4 else 3], over=False)
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}


def tree_sheet(rows):
    out = [[CLEAR] * (CW * 4) for _ in range(CH * len(rows))]
    for r, frames in enumerate(rows):
        for i, f in enumerate(frames):
            for y in range(CH):
                out[r * CH + y][i * CW:(i + 1) * CW] = f[y]
    return out


def tree_files(name, make, variants, sapling, young, seed, wood, cut):
    parts = [make(s, seed + i * 9) for i, s in enumerate(variants)]
    lit = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.6 + 3) for p, s in zip(parts, variants)]
    write_png(ROOT / "props" / (name + ".png"), CW * 4, CH * 4, tree_sheet([[t for t, c in lit], [c for t, c in lit], [art_tree.to_pixels(p["glow_crown"]) for p in parts], [art_tree.to_pixels(p["glow_trunk"]) for p in parts]]))
    keep = art_tree.BARK, art_tree.WOOD
    art_tree.BARK, art_tree.WOOD = wood[1:6], cut  # the stumps in this tree's wood
    frames = [art_tree.stump(r, 3)[0] for r in (5.0, 9.0)]
    art_tree.BARK, art_tree.WOOD = keep
    for spec, sd in ((sapling, seed + 60), (young, seed + 61)):
        p = make(spec, sd, extras=False)
        t, c = art_tree.finish(p["trunk"], p["crown"], spec["w"] / 2.6 + 2)
        frames.append([[c[y][x] if c[y][x][3] else t[y][x] for x in range(CW)] for y in range(CH)])
    write_png(ROOT / "props" / (name + "_growth.png"), CW * 4, CH, tree_sheet([frames]))
    if "vines" in parts[0]:  # row 0 the ropes, row 1 their sway mask, row 2 the buds' light (see hang_vines)
        write_png(ROOT / "props" / (name + "_vines.png"), CW * 4, CH * 3, tree_sheet([[art_tree.to_pixels(p[k]) for p in parts] for k in ("vines", "vine_mask", "vine_glow")]))
    return lit, parts


# ================================================================== small plants (40x34 frames, feet (20, 31))
def blade(px, x0, length, lean, tone, colors=GREEN):
    for i in range(int(length) + 1):
        t = i / max(length, 1)
        x = x0 + lean * length * t * (1.0 + 0.5 * t)
        put(px, int(round(x)), int(round(GROUND - length * (t - 0.14 * t * t))), colors[int(clamp(tone + (2 if t > 0.75 else 0) - (1 if t < 0.2 else 0), 0, 5))])


def foot(px, rng, spread, n=6, hi=5):
    for _ in range(n):
        blade(px, 20 + rng.uniform(-spread, spread), rng.uniform(2, hi), rng.uniform(-0.3, 0.3), rng.choice((1, 2, 3)))


def finish(px, spread, seed):
    """Cool rim on the right of the greens, ground shadow, ink outline (the meadow flora's finish, with this wood's ramps)."""
    for y in range(FH):
        for x in range(1, FW - 1):
            c = px[y][x]
            if c[3] == 255 and (c in GREEN[1:4] or c in LEAF[1:4]) and px[y][x + 1][3] == 0 and noise(x, y, seed + 3) > 110:
                px[y][x] = RIM[int(noise(x, y, seed + 4) > 160)]
    base = blank(FW, FH)
    put_shadow(base, [(20, GROUND - 2, spread + 3, 3, 0)])
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base)
    return base


# ---- Dornenhecke
HEDGES = [
    {"canes": 5, "spread": 9, "height": 15, "berries": 3},
    {"canes": 7, "spread": 13, "height": 20, "berries": 5},
    {"canes": 8, "spread": 14, "height": 16, "berries": 5},
]
THORN = ramp("120c1c", "2a1c38", "4a3458", "6e5478", "a894b4")


def thorn_cane(px, x0, spread_x, height, rng, thick):
    """A cane that arches over and digs back towards the ground, long pale thorns on its back."""
    pts = bezier((x0, GROUND + 0.5), (x0 + spread_x * 0.1, GROUND - height * 1.5), (x0 + spread_x * 0.9, GROUND - height * 1.35), (x0 + spread_x * 1.05, GROUND - height * rng.uniform(0.05, 0.5)), n=44)
    last = None
    for i, (x, y) in enumerate(pts):
        xi, yi = int(round(x)), int(round(y))
        if (xi, yi) == last:
            continue
        last = (xi, yi)
        t = i / len(pts)
        put(px, xi, yi, THORN[3])
        if t < (0.8 if thick else 0.4):
            put(px, xi + 1, yi, THORN[2])
            put(px, xi, yi + 1, THORN[1])
        if i % 6 == 2 and 0.1 < t < 0.95:  # long pale thorns point outwards from the arch
            sx = (1 if spread_x > 0 else -1) * (1 if i % 12 == 2 else -1)
            put(px, xi + sx, yi - 1, THORN[4])
            put(px, xi + sx * 2, yi - 2, BONE[4])
    return pts


def hex_berry(px, glow, x, y):
    for dx, dy, c in ((0, 0, 4), (1, 0, 2), (0, 1, 2), (1, 1, 1), (-1, 0, 3), (0, -1, 3), (-1, 1, 2), (1, -1, 2), (0, 2, 0), (-1, -1, 4)):
        put(px, x + dx, y + dy, HOOD[c])
    glow.emit(px, x - 1, y - 1, HEX, HEX, 1)


def make_hedge(spec, seed, berries=True, stripped=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    all_pts = []
    n = spec["canes"] if not stripped else spec["canes"] // 2 + 1
    if not stripped:  # the dark heart of the tangle
        F.blob(px, 20, GROUND - spec["height"] * 0.42, spec["spread"] * 0.8, spec["height"] * 0.46, [LEAF[0], LEAF[1], LEAF[1], LEAF[2], LEAF[3]])
    for i in range(n):
        side = -1 if i % 2 == 0 else 1
        x0 = 20 + side * rng.uniform(0.5, spec["spread"] * 0.45)
        sp_x = side * spec["spread"] * rng.uniform(0.35, 1.0) * (-1 if rng.random() < 0.25 else 1)
        sp_x = clamp(sp_x, 6 - x0, FW - 7 - x0) / 1.05
        all_pts.append(thorn_cane(px, x0, sp_x, spec["height"] * rng.uniform(0.55, 1.0) * (0.55 if stripped else 1.0), rng, i < 3))
    if stripped:
        base = blank(FW, FH)
        put_shadow(base, [(20, GROUND - 2, spec["spread"] + 3, 2.5, 0)])
        for y in range(FH):
            for x in range(FW):
                if px[y][x][3] == 255:
                    base[y][x] = px[y][x]
        outline(base)
        return base, glow.done()
    for pts in all_pts:  # few, dark leaves in pairs; some already wine red
        for i in range(6, len(pts) - 2, 9):
            x, y = pts[i]
            side = rng.choice((-1, 1))
            red = rng.random() < 0.08
            for k in range(1, rng.choice((2, 3, 3))):
                xx, yy = int(round(x + side * k)), int(round(y - 1 + rng.choice((-1, 0, 1))))
                put(px, xx, yy, WINE[3] if red else LEAF[4 if side < 0 else 3])
                put(px, xx, yy + 1, WINE[1] if red else LEAF[2 if side < 0 else 1])
            if rng.random() < 0.25:
                put(px, int(round(x)) + side * 2, int(round(y)) - 2, LEAF[5])
    foot(px, rng, spec["spread"] * 0.8, 5, 4)
    if berries:
        placed = []
        spots = [p[int(len(p) * f)] for p in all_pts for f in (0.45, 0.7)]
        rng.shuffle(spots)
        for x, y in spots:
            xi, yi = int(round(x)), int(round(y))
            if len(placed) >= spec["berries"] or yi > GROUND - 5 or yi < 4 or not 3 < xi < FW - 4 or any(abs(xi - a) + abs(yi - b) < 5 for a, b in placed):
                continue
            put(px, xi, yi + 1, THORN[2])
            hex_berry(px, glow, xi, yi + 2)
            placed.append((xi, yi))
    return finish(px, spec["spread"], seed), glow.done()


# ---- Dämmerstrauch and Besenginster: the Hexenwald's own plain bushes (nothing to pick, the sickle takes fibre and sticks)
SHRUBS = [
    {"spread": 9, "height": 12, "lobes": 5},
    {"spread": 12, "height": 16, "lobes": 7},
    {"spread": 14, "height": 19, "lobes": 9},
]
BROOMS = [
    {"rods": 13, "spread": 8, "height": 18},
    {"rods": 17, "spread": 11, "height": 23},
    {"rods": 21, "spread": 14, "height": 26},
]
BROOM = ramp("0e161c", "1a2a2e", "2a403e", "426052", "68866c")  # rods: dark sea green, lighter where the light catches them


def make_shrub(spec, seed, stripped=False):
    """Dämmerstrauch: a low, dense cushion of small blue-black leaves, violet in its deepest shade, a few twigs poking out and a
    handful of pale dusk leaves; at night two or three drops of violet dew."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    sp, ht = spec["spread"], spec["height"]
    if stripped:
        for i in range(5 + sp // 3):
            x0 = 20 + rng.uniform(-sp * 0.6, sp * 0.6)
            lean = (x0 - 20) / max(sp, 1) * 0.8 + rng.uniform(-0.2, 0.2)
            for k in range(rng.randrange(3, 4 + ht // 3)):
                put(px, int(round(x0 + lean * k)), GROUND - k, BARK[3 if k % 3 else 4])
        foot(px, rng, sp * 0.7, 5, 3)
        return finish(px, sp, seed), glow.done()
    for i in range(3 + sp // 4):  # twigs under and through the cushion
        x0 = 20 + rng.uniform(-sp * 0.5, sp * 0.5)
        lean = (x0 - 20) / max(sp, 1) * 1.1
        for k in range(int(ht * rng.uniform(0.7, 1.05))):
            put(px, int(round(x0 + lean * k * 0.6)), GROUND - k, BARK[2 if k % 2 else 3])
    lobes = []
    for i in range(spec["lobes"]):
        t = i / max(spec["lobes"] - 1, 1)
        x = 20 + (t - 0.5) * sp * 1.5 + rng.uniform(-1.5, 1.5)
        top = 1.0 - abs(t - 0.5) * 1.3
        r = rng.uniform(3.2, 4.6) * (0.8 + 0.3 * top)
        lobes.append((x, GROUND - 2 - ht * 0.55 * top - rng.uniform(0, 2.5), r, r * 0.8, rng.random()))
    lobes.append((20, GROUND - ht * 0.72, sp * 0.42, ht * 0.32, 0.5))  # the crown of the cushion
    lobes.append((20, GROUND - 3.2, sp * 0.95, 3.6, 0.0))  # its skirt sits on the ground: no stems show
    for x, y, rx, ry, _z in sorted(lobes, key=lambda l: l[1]):
        F.blob(px, x, y, rx, ry, [LEAF[1], LEAF[2], LEAF[3], LEAF[4]])
    for y in range(FH):  # leaf scallops, violet in the deepest shade, lit rim on top
        for x in range(FW):
            c = px[y][x]
            if c not in LEAF:
                continue
            k = LEAF.index(c)
            if (x + (y // 2) * 3) % 4 == 0 and y % 2 == 0 and k > 1:
                px[y][x] = LEAF[k - 1]
            if k <= 1 and noise(x, y, seed + 5) > 175:
                px[y][x] = HOOD[1]
            if y > 0 and px[y - 1][x][3] == 0 and k < 5:
                px[y][x] = LEAF[min(k + 2, 5)]
    pale = [(x, y) for y in range(FH) for x in range(FW) if px[y][x] in LEAF[2:5] and px[y - 1][x] in LEAF]
    rng.shuffle(pale)
    for x, y in pale[: 2 + sp // 5]:  # pale dusk leaves
        put(px, x, y, BONE[3])
        put(px, x + 1, y, BONE[2])
    for x, y in pale[6: 6 + 1 + sp // 6]:  # violet dew
        glow.emit(px, x, y - 1, VIO_DIM, VIO, 1)
    for k in range(int(sp * 1.6)):  # dead leaves under the skirt
        x = int(20 + rng.uniform(-sp, sp))
        if px[GROUND][x][3] == 0:
            put(px, x, GROUND, (ROOT_C[1], LEAF[1], HOOD[1])[k % 3])
    return finish(px, sp, seed), glow.done()


def make_broom(spec, seed, stripped=False):
    """Besenginster, the witches' broom bush: a fan of thin upright rods out of one root, scale-leaved, a few rods ending in a
    tiny pale bud; stripped, only a crown of cut stubs."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    sp, ht = spec["spread"], spec["height"]
    n = spec["rods"]
    for i in range(n):
        t = (i + 0.5) / n
        ang = (t - 0.5) * 1.9 + rng.uniform(-0.12, 0.12)  # out of one root, fanning wider towards the sides
        length = ht * (1.0 - abs(t - 0.5) * 0.7) * rng.uniform(0.6, 1.08) * (0.3 if stripped else 1.0)
        bend = (t - 0.5) * 1.2 + rng.uniform(-0.2, 0.2)  # the rods arch outwards at their tips, like a fountain
        x0 = 20 + (t - 0.5) * 3
        for k in range(int(length)):
            u = k / max(length, 1)
            x = x0 + math.sin(ang) * k * 0.95 * (sp / ht) * 1.6 + bend * u * u * 6
            y = GROUND - k * math.cos(ang * 0.6)
            lit = 3 if (ang < 0) and k % 4 else 2
            put(px, int(round(x)), int(round(y)), BROOM[lit if u > 0.2 else 1])
            if not stripped and k > 4 and k % 4 == 0 and rng.random() < 0.3:  # sparse scale leaves
                put(px, int(round(x)) + (1 if ang > 0 else -1), int(round(y)), BROOM[4 if ang < 0 else 3])
        if stripped:
            put(px, int(round(x0 + math.sin(ang) * length * 0.95 * (sp / ht) * 1.6)), int(round(GROUND - length)), BONE[3])
        elif rng.random() < 0.35:
            tx = int(round(x0 + math.sin(ang) * (length - 1) * 0.95 * (sp / ht) * 1.6 + bend * 6))
            ty = int(round(GROUND - (length - 1) * math.cos(ang * 0.6))) - 1
            put(px, tx, ty, HOOD[4])
            put(px, tx, ty + 1, HOOD[2])
    foot(px, rng, sp * 0.4, 3, 3)
    return finish(px, sp, seed), glow.done()


# ---- Totenkerze
CANDLES = [
    {"stalks": [(20, 15)], "leaves": 4, "spread": 5},
    {"stalks": [(15, 12), (21, 19), (26, 14)], "leaves": 6, "spread": 9},
    {"stalks": [(11, 11), (16, 17), (21, 21), (25, 14), (30, 10)], "leaves": 8, "spread": 13},
]


def make_candle(spec, seed, picked=False):
    """Waxen, leafless flower candles: a pale column that runs with drops of wax, a ghost-green flame standing on it."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for i in range(spec["leaves"]):  # broad dark basal leaves
        a = -math.pi / 2 + (i / max(spec["leaves"] - 1, 1) - 0.5) * 2.7 + rng.uniform(-0.1, 0.1)
        F.leaf(px, 20 + math.cos(a) * spec["spread"] * 0.4, GROUND - 1, a, rng.uniform(5, 8), 1.8, GREEN, curve=-(a + math.pi / 2) * 0.6, tone=2)
    for x, h in sorted(spec["stalks"], key=lambda s: -s[1]):
        if picked:
            for k in range(3):
                put(px, x, GROUND - k, WAX[1])
            put(px, x, GROUND - 3, WAX[3])
            continue
        top = GROUND - h
        lean = (x - 20) / 26.0
        for k in range(h + 1):
            y = GROUND - k
            xx = int(round(x + lean * k * 0.25))
            if k < 3:
                put(px, xx, y, GREEN[2])
                continue
            put(px, xx - 1, y, WAX[4 if k > h - 3 else 3])
            put(px, xx, y, WAX[2])
            put(px, xx + 1, y, WAX[1 if k % 4 else 0])
            if k == 3:
                put(px, xx - 2, y, GREEN[3])
                put(px, xx + 2, y, GREEN[2])
        tx = int(round(x + lean * h * 0.25))
        for dx, dy in ((-2, 2), (-2, 3), (2, 4), (-2, 7)):  # runs of wax
            if top + dy < GROUND - 4:
                put(px, tx + dx, top + dy, WAX[3 if dx < 0 else 1])
        put(px, tx - 1, top - 1, WAX[4])
        put(px, tx, top - 1, WAX[3])
        put(px, tx, top - 2, HEX_DIM)  # the flame: a teardrop of cold green
        put(px, tx, top - 3, HEX_DIM)
        put(px, tx - 1, top - 3, HEX_DIM)
        glow.emit(px, tx, top - 3, HEX, HEX_HOT, 2)
        glow.emit(px, tx, top - 4, HEX, HEX, 1)
        glow.emit(px, tx + (1 if lean >= 0 else -1), top - 5, HEX_DIM, HEX, 0)
    foot(px, rng, spec["spread"], 4, 4)
    return finish(px, spec["spread"], seed), glow.done()


# ---- Hexenhut
HATS = [
    {"stalks": 1, "spread": 4, "lo": 15, "hi": 17, "leaves": 4},
    {"stalks": 3, "spread": 8, "lo": 12, "hi": 21, "leaves": 6},
    {"stalks": 5, "spread": 12, "lo": 10, "hi": 22, "leaves": 9},
]


def hat(px, glow, x, y, side, big):
    """A hooded bloom like a crooked pointed hat: wide brim, a cone whose tip kinks over; the light sits under the brim."""
    rows = [1, 1, 2, 3, 3, 4, 5] if big else [1, 1, 2, 3, 4]
    n = len(rows)
    for r, w in enumerate(rows):
        off = side * (2 if r == 0 else (1 if r < 3 else 0))  # the kinked tip
        for c in range(w):
            xx = x + off - w // 2 + c
            put(px, xx, y - n + r, HOOD[4 if c == 0 and w > 1 else (3 if c < (w + 1) // 2 else 2)])
    put(px, x + side * 3, y - n + 1, HOOD[2])  # the tip hangs
    bw = rows[-1] // 2 + 2
    for c in range(-bw, bw + 1):  # the brim
        put(px, x + c, y, HOOD[5 if c < -1 else (3 if c < bw - 1 else 1)])
        if abs(c) < bw - 1:
            put(px, x + c, y + 1, HOOD[0])
    put(px, x - 1, y - 1, WINE[3])  # a wine-red band
    put(px, x, y - 1, WINE[2])
    put(px, x + 1, y - 1, WINE[1])
    glow.emit(px, x, y + 1, HEX_DIM, HEX, 1)


def make_hat(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(spec["leaves"]):  # deeply cut leaves
        a = -math.pi / 2 + rng.uniform(-1.3, 1.3)
        F.leaf(px, 20 + math.cos(a) * 2, GROUND - 1, a, rng.uniform(5, 9), 1.4, GREEN, curve=rng.uniform(-0.6, 0.6), tone=3)
    heads = []
    for i, x0 in enumerate(F.stalks_at(rng, spec["stalks"], spec["spread"])):
        side = 1 if x0 >= 20 else -1
        h = rng.uniform(3, 5) if picked else rng.uniform(spec["lo"], spec["hi"])
        end = (clamp(x0 + side * rng.uniform(1, 3), 7, FW - 8), GROUND - h)
        pts = bezier((x0, GROUND + 0.5), (x0 - side * 1.2, GROUND - h * 0.6), end, n=26)
        for j, (x, y) in enumerate(pts):
            put(px, int(round(x)), int(round(y)), GREEN[2 if j % 7 else 3])
        if not picked:
            for f in (0.35, 0.6):  # small leaves up the stalk
                x, y = pts[int(len(pts) * f)]
                put(px, int(round(x)) + side, int(round(y)), GREEN[4])
                put(px, int(round(x)) - side, int(round(y)) + 1, GREEN[3])
            heads.append((int(round(end[0])), int(round(end[1])), side, i == 0 or h > spec["hi"] - 4))
    for x, y, side, big in sorted(heads, key=lambda v: -v[1]):
        hat(px, glow, x, max(y, 9), side, big)
    foot(px, rng, spec["spread"], 4, 4)
    return finish(px, spec["spread"], seed), glow.done()


# ---- Krötenschirm
TOADS = [
    {"caps": [(20, 9, 6)], "spread": 6},
    {"caps": [(14, 7, 5), (23, 12, 7), (30, 5, 4)], "spread": 11},
    {"caps": [(10, 6, 4), (16, 11, 6), (24, 14, 8), (31, 8, 5), (20, 4, 3)], "spread": 14},
]


def make_toad(spec, seed, picked=False):
    """Squat, fat toadstools: a pale bulging stem, a low wine-red cap with a darker rim and bone-white warts that glow at night."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    foot(px, rng, spec["spread"], 5, 4)
    for cx, h, r in sorted(spec["caps"], key=lambda c: c[1], reverse=True):
        if picked:
            F.blob(px, cx, GROUND - 0.5, max(1.5, r * 0.3), 1.2, BONE[1:5], dither=False)
            continue
        for k in range(h):  # the stem bulges at its foot
            w = max(1.0, r * 0.32 + (1.2 if k < 2 else 0.0))
            for dx in range(-int(w), int(w) + 1):
                put(px, cx + dx, GROUND - k, BONE[int(clamp(4 - (dx + w) / max(w, 0.5) * 1.6 - (1 if k > h - 3 else 0), 1, 5))])
        cy = GROUND - h
        ry = max(2.0, r * 0.55)
        for y in range(int(cy - ry) - 1, int(cy) + 2):
            for x in range(cx - r - 1, cx + r + 2):
                dx, dy = (x + 0.5 - cx) / (r + 0.3), (y + 0.5 - cy) / ry
                if dy > 0.35 or dx * dx + dy * dy > 1.0:
                    continue
                lit = 0.55 - 0.45 * dx - 0.55 * (dy + 0.5) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.25
                put(px, x, y, WINE[int(clamp(lit * 3.6 + 0.5, 0, 3))])
        for x in range(cx - r, cx + r + 1):  # gills in the shade under the rim
            if (x - cx) % 2 == 0 and abs(x - cx) < r - 0.5:
                put(px, x, int(cy) + 1, BONE[1])
            put(px, x, int(cy), WINE[0] if abs(x - cx) > r * 0.4 else WINE[1])
        for k in range(2 + r // 2):  # warts
            wx = cx + int(round((rng.random() * 2 - 1) * r * 0.75))
            wy = int(cy - ry * rng.uniform(0.25, 0.85))
            if px[wy][wx] in WINE:
                glow.emit(px, wx, wy, BONE[5 if wx <= cx else 4], HEX_HOT if k == 0 else HEX, 1 if k == 0 else 0)
    return finish(px, spec["spread"], seed), glow.done()


# ---- Geisterfarn: the Leuchtfern drawn with a ghost's colours
GHOST = ramp("101a34", "1e3650", "34586e", "568690", "8ab8b0", "c8ecdc")
GHOST_FID = ramp("4a2a7a", "9458cc", "d8b8f4")


def make_ghost(spec, seed, picked=False, stripped=False):
    keep = F.FERN, F.FID, F.SPORE, F.RIM
    F.FERN, F.FID, F.SPORE, F.RIM = GHOST, GHOST_FID, hexc("c8ecdc"), RIM
    try:
        frame = F.make_fern(spec, seed, picked=picked, stripped=stripped)
    finally:
        F.FERN, F.FID, F.SPORE, F.RIM = keep
    glow = [[(216, 184, 255, c[3]) if c[3] and c[:3] == (216, 255, 128) else c for c in row] for row in frame[1]]  # the fiddleheads glow violet here
    return frame[0], glow


# ---- Alraune
MANDRAKES = [
    {"roots": [(20, 4.0)], "leaves": 7, "len": (7, 10), "spread": 8},
    {"roots": [(15, 3.4), (25, 4.4)], "leaves": 10, "len": (7, 11), "spread": 12},
    {"roots": [(13, 3.2), (20, 4.8), (28, 3.6)], "leaves": 13, "len": (6, 9), "spread": 13},
]


def make_mandrake(spec, seed, pulled=False):
    """A flat rosette of crinkled dark leaves; the shoulders of the root show above the earth with a sleeping face
    (two slits, a crooked mouth), small violet bell flowers and a wine-red berry or two in the heart."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    if pulled:
        F.crater(px, rng, [(cx, r * 0.9) for cx, r in spec["roots"]], spec["spread"])
        return finish(px, spec["spread"], seed), glow.done()
    for cx, r in spec["roots"]:
        F.blob(px, cx, GROUND - 0.5, r + 3.0, 2.6, F.SOIL)
    n = spec["leaves"]
    for i in sorted(range(n), key=lambda i: -abs(i - (n - 1) / 2.0)):
        cx, r = spec["roots"][i % len(spec["roots"])]
        a = -math.pi / 2 + (i / max(n - 1, 1) - 0.5) * 2.9 + rng.uniform(-0.15, 0.15)
        F.leaf(px, cx + math.cos(a) * r * 0.6, GROUND - r * 0.9, a, rng.uniform(*spec["len"]), 2.5, GREEN, curve=-(a + math.pi / 2) * 0.7, tone=2)
    for cx, r in spec["roots"]:
        cy = GROUND - r * 0.55
        F.blob(px, cx, cy, r, r * 0.85, ROOT_C)
        cx = int(cx)
        ey = int(round(cy - r * 0.15))
        for side in (-1, 1):  # closed eyes: slanted slits
            put(px, cx + side * 2, ey, BARK[0])
            put(px, cx + side, ey + 1, BARK[0])
        for k in range(-1, 2):  # the mouth
            put(px, cx + k, ey + 2 + (1 if k == 1 else 0), ROOT_C[0])
        put(px, cx - int(r) + 1, int(cy - r * 0.4), ROOT_C[4])
        for side in (-1, 1):  # arms: side roots
            put(px, cx + side * (int(r) + 1), int(cy) + 1, ROOT_C[2])
        for k, dx in enumerate((-2, 1, 3)[: 1 + int(r > 3.3) + int(r > 4.2)]):  # bell flowers and berries in the heart
            fy = int(cy - r * 0.85) - 2 - k % 2
            put(px, cx + dx, fy + 1, GREEN[3])
            if k == 1:
                put(px, cx + dx, fy, WINE[3])
                put(px, cx + dx + 1, fy, WINE[2])
                glow.emit(px, cx + dx, fy - 0, WINE[4], hexc("ff8a9a"), 0)
            else:
                put(px, cx + dx, fy, HOOD[4])
                put(px, cx + dx - 1, fy, HOOD[5])
                put(px, cx + dx, fy - 1, HOOD[3])
                glow.emit(px, cx + dx, fy, HOOD[5], VIO_L, 1)
    foot(px, rng, spec["spread"], 3, 3)
    return finish(px, spec["spread"], seed), glow.done()


# ================================================================== Fluchsilber (cursed silver): the iron rocks' build in this wood's stone
CURSE_STONE = ramp("0c0c1a", "17182c", "262a42", "3a425c", "56627c", "98a6bc")
CURSE_ORE = ("070b10", "0d161c", "13222a", "1a3236", "2e5c54", "c4f8d4")
CURSE_TARNISH = ("1a1028", "2c1a40", "44285a", "5e3a74")
CURSE_STAIN = ("1c1630", "2a2044", "3a2c58")
CURSE_METAL = ramp("5a9a7a", "8ad0a0", "c4f4c8", "f2fff0")
CURSE_MOSS = ramp("15182a", "1c2236", "262e44", "323c52")


def curse_rocks():
    """render_iron with the cursed palettes; the silver itself goes into the glow layer (it shines by night)."""
    keep = (I.STONE, I.ORE, I.RUST, I.STAIN, I.RUST_AMOUNT, I.METAL, S.MOSS, S.STONE)
    I.PALETTES["fluch"] = (CURSE_ORE, CURSE_TARNISH, CURSE_STAIN, 0.3)
    I.use("fluch")
    I.STONE, I.METAL, S.MOSS, S.STONE = CURSE_STONE, CURSE_METAL, CURSE_MOSS, CURSE_STONE
    bright = {tuple(c) for c in (I.ORE[4], I.ORE[5], CURSE_METAL[2], CURSE_METAL[3])}
    try:
        n = len(I.IRON_ROCKS)
        frames = []
        for st in range(4):
            for i in range(n):
                px, glow = I.render_iron(i, st, 200 + i * 17 + st)
                glow = [[CLEAR if c[3] else c for c in row] for row in glow]  # no void veins or teal fungi here
                for y in range(S.RH):
                    for x in range(S.RW):
                        if tuple(px[y][x]) in bright:
                            glow[y][x] = (*(HEX_HOT if tuple(px[y][x]) in (tuple(I.ORE[5]), tuple(CURSE_METAL[3])) else HEX)[:3], 255 if tuple(px[y][x]) != tuple(I.ORE[4]) else 150)
                for y in range(1, S.RH - 1):  # a breath of light round the silver
                    for x in range(1, S.RW - 1):
                        if glow[y][x][3] == 0 and any(glow[b][a][3] >= 150 for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))):
                            glow[y][x] = (*HEX[:3], 46)
                frames.append((px, glow))
        icon = I.icon_ore()
    finally:
        I.STONE, I.ORE, I.RUST, I.STAIN, I.RUST_AMOUNT, I.METAL, S.MOSS, S.STONE = keep
    return frames, icon


# ================================================================== icons
def icon_log(wood, cut):
    from art_bush import stroke
    px = blank(16, 16)
    stroke(px, bezier((4.8, 11.6), (7.6, 8.6), (10.4, 5.4), n=24), 3.0, 3.0, wood[1:5])
    for t in range(0, 24, 3):
        px[int(10.8 - t * 0.24)][int(5.5 + t * 0.24)] = wood[0]
    stroke(px, [(11.2, 4.6)], 3.0, 3.0, cut[1:])
    stroke(px, [(11.2, 4.6)], 1.5, 1.5, [cut[2], cut[2], cut[3]])
    px[4][11] = cut[0]
    check_icon("log", px)
    return outline_pass(px, ICON_OUT)


def i_thorn(px, g):  # a piece of cane, bent, with long pale thorns on its back
    for k, (x, y) in enumerate(bezier((3.0, 13.0), (5.0, 5.0), (13.0, 4.0), n=30)):
        xi, yi = int(round(x)), int(round(y))
        px[yi][xi] = THORN[3]
        px[yi + 1][xi] = THORN[1]
        if k in (4, 12, 20, 27):
            px[yi - 1][xi - 1] = THORN[4]
            px[yi - 2][xi - 2] = BONE[4]
            px[yi - 3][xi - 2] = BONE[5]
    px[13][2], px[14][3] = THORN[2], THORN[1]


def i_berry(px, g):
    for x, y in ((8, 2), (8, 3), (7, 4), (9, 4), (6, 5), (10, 5)):
        px[y][x] = THORN[3]
    px[2][9], px[2][10], px[3][10] = LEAF[4], LEAF[5], LEAF[3]
    for cx, cy in ((5, 8), (10, 8), (8, 11)):
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if dx * dx + dy * dy <= 5:
                    px[cy + dy][cx + dx] = HOOD[int(clamp(2.4 - dx * 0.8 - dy * 0.8, 0, 4))]
        px[cy - 1][cx - 1] = HEX
    px[10][7] = HEX_HOT


def i_candle(px, g):
    for y in range(6, 14):
        px[y][7], px[y][8], px[y][9] = WAX[4], WAX[2], WAX[1]
    px[8][6], px[9][6], px[11][10] = WAX[3], WAX[3], WAX[1]
    px[14][7], px[14][8], px[14][9], px[14][6], px[14][10] = GREEN[3], GREEN[2], GREEN[2], GREEN[4], GREEN[1]
    px[5][8], px[4][8], px[3][8], px[4][7], px[2][8], px[4][9] = HEX_DIM, HEX, HEX_HOT, HEX_DIM, HEX, HEX_DIM


def i_hat(px, g):
    gl = Glow(16, 16)
    for y in range(11, 15):
        px[y][8] = GREEN[2]
    px[13][9], px[12][7] = GREEN[4], GREEN[3]
    full = blank(FW, FH)
    hat(full, Glow(), 20, 20, 1, True)
    for y in range(FH):
        for x in range(FW):
            if full[y][x][3] and 0 < x - 12 < 15 and 0 < y - 10 < 15:
                px[y - 10][x - 12] = full[y][x]


def i_toad(px, g):
    for y in range(9, 14):
        for x in range(7, 10):
            px[y][x] = BONE[5 - (x - 7) - (1 if y == 9 else 0)]
    px[13][6], px[13][10] = BONE[4], BONE[2]
    for y in range(3, 10):
        for x in range(2, 14):
            dx, dy = (x + 0.5 - 8) / 5.8, (y + 0.5 - 8.5) / 5.4
            if dx * dx + dy * dy <= 1.0 and y < 9:
                px[y][x] = WINE[int(clamp(2.6 - dx * 2.0 - (dy + 0.5) * 2.4, 0, 4))]
    for x in range(3, 13):
        px[8][x] = WINE[0] if x % 2 else WINE[1]
    for x, y in ((5, 5), (8, 4), (10, 6), (7, 6)):
        px[y][x] = BONE[5]


def i_frond(px, g):
    for k in range(12):
        x, y = 3 + k * 0.8, 13 - k * 0.85
        px[int(y)][int(x)] = GHOST[2]
        ln = int(max(1, 4 - abs(k - 5) * 0.6))
        for j in range(1, ln + 1):
            if 0 < int(y) - j and int(x) - j > 0:
                px[int(y) - j][int(x) - j // 2] = GHOST[5 if j == ln else 4]
            if int(x) + j < 15 and int(y) + j // 2 < 15:
                px[int(y) + j // 2][int(x) + j] = GHOST[3 if j < ln else 2]
    px[2][13] = GHOST_FID[2]


def i_mandrake(px, g):
    F.blob(px, 8, 8.5, 3.6, 3.4, ROOT_C)
    for x, y in ((6, 12), (5, 13), (10, 12), (11, 13), (8, 12), (8, 13), (4, 9), (3, 10), (12, 9), (13, 10)):  # legs and arms
        px[y][x] = ROOT_C[2]
    px[8][6], px[8][7], px[8][9], px[8][10] = ROOT_C[0], ROOT_C[0], ROOT_C[0], ROOT_C[0]
    px[10][7], px[10][8], px[11][9] = ROOT_C[0], ROOT_C[0], ROOT_C[0]
    for x, y, c in ((8, 4, 2), (8, 3, 3), (7, 2, 4), (6, 2, 3), (9, 2, 3), (10, 2, 2), (5, 3, 4), (11, 3, 2), (6, 4, 3), (10, 4, 2)):
        px[y][x] = GREEN[c]
    px[1][8] = HOOD[5]


# ================================================================== run
def frames_sheet(frames, cols, rows):
    return sheet([f[0] for f in frames], cols, rows), sheet([f[1] for f in frames], cols, rows)


def main():
    props, items = ROOT / "props", ROOT / "items"
    hags = tree_files("hag_tree", hag_tree, HAGS, HAG_SAPLING, HAG_YOUNG, 15, BARK, CUT)
    bones = tree_files("bone_tree", bone_tree, BONES, BONE_SAPLING, BONE_YOUNG, 23, BONE, BONE[2:6])
    sheets = {
        "thorn_hedge": [make_hedge(s, 2100 + i * 23, berries=r) for r in (True, False) for i, s in enumerate(HEDGES)],
        "hex_shrub": [make_shrub(s, 2700 + i * 31) for i, s in enumerate(SHRUBS)],
        "witch_broom": [make_broom(s, 2800 + i * 37) for i, s in enumerate(BROOMS)],
        "grave_candle": [make_candle(s, 2200 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(CANDLES)],
        "witch_hat": [make_hat(s, 2300 + i * 13, picked=r) for r in (False, True) for i, s in enumerate(HATS)],
        "toad_cap": [make_toad(s, 2400 + i * 11, picked=r) for r in (False, True) for i, s in enumerate(TOADS)],
        "ghost_fern": [make_ghost(s, 2500 + i * 7, picked=r) for r in (False, True) for i, s in enumerate(F.FERNS)],
        "mandrake": [make_mandrake(s, 2600 + i * 29, pulled=r) for r in (False, True) for i, s in enumerate(MANDRAKES)],
    }
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            F.fit(name, i, base)
        rows = len(frames) // 3
        lit, glow = frames_sheet(frames, 3, rows)
        write_png(props / (name + ".png"), FW * 3, FH * rows, lit)
        write_png(props / (name + "_glow.png"), FW * 3, FH * rows, glow)
    assert not F.CUT, "cut off at the frame edge:\n" + "\n".join(F.CUT)
    write_png(props / "thorn_hedge_stripped.png", FW * 3, FH, sheet([make_hedge(s, 2150 + i, stripped=True)[0] for i, s in enumerate(HEDGES)], 3, 1))
    write_png(props / "hex_shrub_stripped.png", FW * 3, FH, sheet([make_shrub(s, 2700 + i * 31, stripped=True)[0] for i, s in enumerate(SHRUBS)], 3, 1))
    write_png(props / "witch_broom_stripped.png", FW * 3, FH, sheet([make_broom(s, 2800 + i * 37, stripped=True)[0] for i, s in enumerate(BROOMS)], 3, 1))
    write_png(props / "ghost_fern_stripped.png", FW * 3, FH, sheet([make_ghost(s, 2500 + i * 7, stripped=True)[0] for i, s in enumerate(F.FERNS)], 3, 1))
    rocks, ore_icon = curse_rocks()
    n = len(I.IRON_ROCKS)
    write_png(props / "curse_rock.png", S.RW * n, S.RH * 4, S.sheet([f[0] for f in rocks], n, 4, S.RW, S.RH))
    write_png(props / "curse_rock_glow.png", S.RW * n, S.RH * 4, S.sheet([f[1] for f in rocks], n, 4, S.RW, S.RH))
    icons = {"hag_wood": icon_log(BARK, CUT), "bone_wood": icon_log(BONE, BONE[2:6]), "curse_silver": ore_icon}
    for name, draw in (("hex_thorn", i_thorn), ("hex_berry", i_berry), ("grave_candle", i_candle), ("witch_hat", i_hat), ("toad_cap", i_toad), ("ghost_frond", i_frond), ("mandrake", i_mandrake)):
        icons[name] = F.icon(name, draw)
    for name, px in icons.items():
        write_png(items / (name + ".png"), 16, 16, px)
    print("Hexenwald: 2 trees, hedge, 5 plants, cursed silver and %d icons written" % len(icons))
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(hags, bones, sheets, rocks, icons)


def preview(hags, bones, sheets, rocks, icons):
    """docs/img/hexenwald_flora.png: everything at 2x on the Hexenwald's ground, by day (top) and by night with the glow (bottom)."""
    z = 2
    w = max(CW * 8, FW * 3 * len(sheets))
    h1 = CH + FH * 2 + S.RH + 24
    img = [[(27, 44, 45, 255) if (y // z) < h1 else (10, 15, 24, 255) for _ in range(w * z)] for y in range(h1 * 2 * z)]

    def paste(layer, ox, oy, dim=1.0, k=z):
        for y, row in enumerate(layer):
            for x, c in enumerate(row):
                if c is None or not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(k):
                    for dx in range(k):
                        X, Y = ox * z + x * k + dx, oy * z + y * k + dy
                        if 0 <= X < w * z and 0 <= Y < len(img):
                            b = img[Y][X]
                            img[Y][X] = tuple(int(b[i] * (1 - a) + c[i] * dim * a) for i in range(3)) + (255,)

    for night in (0, 1):
        oy = night * h1
        dim = 0.42 if night else 1.0
        for j, (lit, parts) in enumerate((hags, bones)):
            for i, (t, c) in enumerate(lit):
                paste(t, (j * 4 + i) * CW, oy, dim)
                paste(c, (j * 4 + i) * CW, oy, dim)
                if "vines" in parts[i]:
                    paste(art_tree.to_pixels(parts[i]["vines"]), (j * 4 + i) * CW, oy, dim)
                    if night:
                        paste(art_tree.to_pixels(parts[i]["vine_glow"]), (j * 4 + i) * CW, oy)
                if night:
                    paste(parts[i]["glow_trunk"], (j * 4 + i) * CW, oy)
                    paste(parts[i]["glow_crown"], (j * 4 + i) * CW, oy)
        for s, frames in enumerate(sheets.values()):
            for i, (base, glow) in enumerate(frames):
                x, y = s * FW * 3 + (i % 3) * FW, oy + CH + 4 + (i // 3) * FH
                paste(base, x, y, dim)
                if night:
                    paste(glow, x, y)
        n = len(I.IRON_ROCKS)
        for i in range(n * 2):
            px, glow = rocks[i if i < n else n + i]
            paste(px, i * S.RW, oy + CH + FH * 2 + 12, dim)
            if night:
                paste(glow, i * S.RW, oy + CH + FH * 2 + 12)
    for i, px in enumerate(icons.values()):
        paste(px, w - 24 * (len(icons) - i), h1 - 20, 1.0, 2)
    write_png(ROOT.parent / "docs" / "img" / "hexenwald_flora.png", w * z, len(img), img)
    print("preview written: docs/img/hexenwald_flora.png")


if __name__ == "__main__":
    main()
