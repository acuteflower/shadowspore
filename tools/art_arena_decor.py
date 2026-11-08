#!/usr/bin/env python3
"""The decoration of the boss arena (numpy + PIL, deterministic; made like the quarry and the hut yard: ellipsoids through hut_lib / art_hero3d, in the pillars' grey-lavender
stone so everything belongs to the pillars and the floor): heaps of rubble, fallen drums of columns, broken column stumps, the plinth of a ruined sun-eagle statue (stone talons
still grip it), a bronze fire bowl with a cold teal flame, a tattered wine-red banner of the High Spire's order on an iron pole, huge dark moulted feathers and clusters of
dim crystal. Glow sheets (`*_glow.png`) hold only the emissive pixels.
    python3 tools/art_arena_decor.py [preview.png]     writes assets/props/arena/*.png
Placed from data/ground.json arenas[].decor (a `HutYard` of the level, folder assets/props/arena/)."""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, load_png_arr, save  # noqa: E402
from hut_yard import shadowed  # noqa: E402

OUT = ROOT / "props" / "arena"
OUT.mkdir(parents=True, exist_ok=True)
AS, AS_L, BRONZE = len(h.RAMPS), len(h.RAMPS) + 1, len(h.RAMPS) + 2
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["342e41", "4c465c", "7c768e", "b1abc2"],  # the arena's stone, as the pillars have it
    ["4c465c", "7c768e", "958fa6", "d3cee3"],  # the same, lit
    ["2a1c14", "5a3f24", "8c6a3a", "c4a060"],  # old bronze of the harness
]]
STN = (AS, AS_L)


def col(c):
    return tuple(int(v) for v in c[:3]) + (255,)


def put(name, arr, glow=True):
    save(OUT / f"{name}.png", arr)
    g = glow_of(arr, (h.TEAL, h.VIOLET)) if glow else np.zeros_like(arr)
    if g[..., 3].any():
        save(OUT / f"{name}_glow.png", g)
    elif (OUT / f"{name}_glow.png").exists():
        (OUT / f"{name}_glow.png").unlink()
    return arr.shape[1], arr.shape[0]


def block(m, c, w, hh, d, mat=AS, ang=0.0, tilt=0.0):
    """A cut block with a lit cap and a darker side (like the pillars' plinth stones)."""
    R = h.rot_y(ang) @ h.rot_x(tilt)
    c = np.asarray(c, float)
    m.ell(c + R @ V(0, hh * 0.5, 0), (w / 2, hh * 0.5, d), mat, R=R)
    m.ell(c + R @ V(-w * 0.04, hh * 0.92, -d * 0.04), (w * 0.44, hh * 0.14, d * 0.88), AS_L, R=R)
    m.ell(c + R @ V(w * 0.36, hh * 0.5, d * 0.1), (w * 0.16, hh * 0.46, d * 0.95), mat, R=R)


def moss(m, rng, x0, x1, y, z0, z1, n=4):
    for _ in range(n):
        m.ell(V(rng.uniform(x0, x1), y, rng.uniform(z0, z1)), (rng.uniform(2.5, 5.5), 0.8, rng.uniform(1.6, 3.2)), MOSS_L if rng.random() < 0.5 else MOSS)


def vein(m, a, b, n=8):
    """A thread of teal light in a crack."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    for k in range(n):
        p = a + (b - a) * (k / (n - 1)) + V(0.0, 0.0, 0.0)
        m.ell(p, (0.55, 0.55, 0.45), h.TEAL, kind="emit")


def crystal(m, rng, at, n=4, tall=9.0):
    for k in range(n):
        a = rng.uniform(-0.5, 0.5)
        ln = tall * rng.uniform(0.5, 1.0)
        base = np.asarray(at, float) + V(rng.uniform(-2.5, 2.5), 0, rng.uniform(-1.5, 1.5))
        m.limb(base, base + V(math.sin(a) * ln * 0.5, ln, rng.uniform(-0.5, 1.0)), 1.1, 0.25, h.VIOLET if k % 5 == 4 else h.TEAL, kind="emit")


# ------------------------------------------------------------------ rubble
def rubble_arr():
    """Four heaps of broken stone with chips and a little moss (3 + 1 with a splinter of crystal). 4 frames of 48 x 28, feet row 22."""
    out = np.zeros((28, 48 * 4, 4), np.uint8)
    for v in range(4):
        rng = rng_for(500 + v)
        m = h.Model()
        for _ in range(6 + v * 2):
            a = rng.uniform(0, math.tau)
            d = (rng.random() ** 0.7) * (11 + v * 3)
            y = max(0.8, 6.0 - d * 0.5) * rng.uniform(0.4, 1.0)
            r = rng.uniform(2.6, 5.0) * (1.0 - d / 44)
            m.ell(V(math.cos(a) * d * 1.3, y, math.sin(a) * d * 0.8), (r * 1.2, r * 0.8, r), STN[int(rng.integers(0, 2))], R=h.rot_y(rng.uniform(0, 3)))
        for _ in range(9):
            m.ell(V(rng.uniform(-14, 14), 0.5, rng.uniform(-6, 8)), (rng.uniform(0.7, 1.5), 0.45, 0.8), AS_L)
        for _ in range(3):
            m.ell(V(rng.uniform(-8, 8), rng.uniform(2, 6), rng.uniform(-3, 3)), (rng.uniform(1.6, 3.0), 0.8, 1.2), MOSS_L)
        if v == 3:
            crystal(m, rng, V(rng.uniform(-3, 3), 4.0, 0.0), 2, 5.0)
        arr = to_array(render(m, 48, 28, 22))
        out[:, v * 48:(v + 1) * 48] = shadowed(arr, 22, 18, 3)
    return out, 22


# ------------------------------------------------------------------ a fallen drum of a column
def drum_arr():
    """Two fallen column drums: one whole (end ring, flutes, a crack with light), one split in two with the pieces apart. 2 frames of 72 x 40, feet row 32."""
    out = np.zeros((40, 72 * 2, 4), np.uint8)
    for v in range(2):
        rng = rng_for(520 + v)
        m = h.Model()
        if v == 0:
            m.limb(V(-20, 8, 0), V(20, 8, 0), 8.0, 8.0, AS)
            for xx in (-20, -8, 8, 20):  # carved rings
                m.ell(V(xx, 8, 0), (0.45, 8.2, 8.2), GAP)  # a joint between two drums: a thin dark disc
            for k in range(5):  # flutes along the top
                a = -0.7 + k * 0.35
                m.limb(V(-19, 8 + math.cos(a) * 8.2, math.sin(a) * 8.2), V(19, 8 + math.cos(a) * 8.2, math.sin(a) * 8.2), 0.6, 0.6, AS)
            vein(m, V(-6, 15.8, 1.5), V(10, 15.2, 2.8), 10)
            moss(m, rng, -16, 14, 16.0, -2, 3, 9)
            for _ in range(5):
                m.ell(V(rng.uniform(-18, 18), 15.4, rng.uniform(-4, 4)), (rng.uniform(1.4, 2.6), 0.5, 0.9), GAP)  # pits and chips
        else:
            m.limb(V(-28, 7, 2), V(-6, 8, 0), 7.2, 7.4, AS, ) if False else m.limb(V(-28, 7, 2), V(-5, 8, 0), 7.2, 7.4, AS)
            m.limb(V(5, 7.5, -3), V(26, 6.5, -5), 7.4, 6.8, AS)
            m.limb(V(-6, 8, 0), V(-4, 8, 0), 8.0, 8.0, AS_L)
            for _ in range(5):
                m.ell(V(rng.uniform(-6, 5), rng.uniform(1.0, 3.5), rng.uniform(-3, 7)), (rng.uniform(2.0, 3.6), rng.uniform(1.2, 2.2), rng.uniform(1.6, 2.6)), STN[int(rng.integers(0, 2))], R=h.rot_y(rng.uniform(0, 3)))
            vein(m, V(-24, 14, 2.5), V(-10, 14.6, 2.2), 8)
            moss(m, rng, -24, 22, 14.5, -4, 3, 9)
        arr = to_array(render(m, 72, 40, 32))
        out[:, v * 72:(v + 1) * 72] = shadowed(arr, 32, 28, 4)
    return out, 32


# ------------------------------------------------------------------ the pillars' own pictures, cut
PILLARS = ROOT / "props" / "arena_pillars.png"
PILLARS_GLOW = ROOT / "props" / "arena_pillars_glow.png"
OUTLINE = (27, 26, 46, 255)
P_LIT, P_MID = (211, 206, 227, 255), (124, 118, 142, 255)


def pillar_frame(v, glow=False):
    sheet = load_png_arr(PILLARS_GLOW if glow else PILLARS)
    return sheet[:, v * 64:(v + 1) * 64].copy()


def stump_arr():
    """Two column stumps cut out of the pillars' own pictures (so the stone, the moss and the veins are exactly theirs): the pillar broken off along a jagged line, a fresh
    pale break, chips on the floor. 2 frames of 64 x 68, feet row 58 (the glow sheet is cut the same way)."""
    out = np.zeros((68, 64 * 2, 4), np.uint8)
    glow = np.zeros_like(out)
    for k, (v, cut) in enumerate(((0, 88), (2, 74))):
        rng = np.random.default_rng(700 + k)
        frame = pillar_frame(v)
        g = pillar_frame(v, True)
        y0 = 118 - 58
        jag = np.zeros(64, int)
        level = 0
        for x in range(64):
            if x % int(rng.integers(3, 7)) == 0:
                level = int(rng.integers(-4, 5))
            jag[x] = cut + level + (x - 32) // 9
        sub, gsub = frame[y0:128].copy(), g[y0:128].copy()
        for x in range(64):
            top = jag[x] - y0
            sub[:top, x] = 0
            gsub[:top, x] = 0
            if top < 68 and sub[top, x, 3]:
                sub[top, x] = P_LIT  # the fresh break
                if top + 1 < 68 and sub[top + 1, x, 3]:
                    sub[top + 1, x] = P_MID
                if top - 1 >= 0:
                    sub[top - 1, x] = OUTLINE
        for _ in range(10):  # chips that fell off
            cx, cy = int(rng.integers(8, 56)), int(rng.integers(52, 62))
            if sub[cy, cx, 3] == 0:
                sub[cy, cx] = P_MID
                sub[cy - 1, cx] = P_LIT
                sub[cy, cx + 1] = OUTLINE
        out[:, k * 64:(k + 1) * 64] = sub
        glow[:, k * 64:(k + 1) * 64] = gsub
    save(OUT / "arena_stump_glow.png", glow)
    return out, 58


def plinth_arr():
    """The plinth of a ruined statue of the sun eagle: the pillars' own stepped plinth and a short drum (cut flat from their picture), on top the stone talons that still grip it
    (the bird is gone, the ankle broken off). Two frames (left and right foot) of 64 x 68, feet row 58."""
    out = np.zeros((68, 64 * 2, 4), np.uint8)
    glow = np.zeros_like(out)
    rng = np.random.default_rng(720)
    ink, lit, mid, dark = OUTLINE, P_LIT, P_MID, (76, 70, 92, 255)
    cut = 98 - 60  # the plinth is cut flat here (row in the 68-row crop)
    for v in range(2):
        sub = pillar_frame(2 if v else 0)[60:128].copy()
        gsub = pillar_frame(2 if v else 0, True)[60:128].copy()
        sub[:cut] = 0
        gsub[:cut] = 0
        for x in range(64):  # the flat top: a lit edge
            if sub[cut, x, 3]:
                sub[cut, x] = lit
                sub[cut + 1, x] = mid
                sub[cut - 1, x] = ink
        img = Image.fromarray(sub)
        d = ImageDraw.Draw(img)
        s = -1 if v else 1
        cx, ytop = 32, cut
        d.polygon([(cx - 8, ytop), (cx + 8, ytop), (cx + 6, ytop - 12), (cx + 2, ytop - 15), (cx - 2, ytop - 11), (cx - 6, ytop - 13)], fill=dark, outline=ink)  # the broken ankle
        d.line([(cx - 5, ytop - 2), (cx - 5, ytop - 10)], fill=mid)
        for dx, reach in ((-12, 9), (-1, 12), (11, 9)):  # three toes: out along the top, then curling over the front edge
            x0 = cx + dx * s
            path = [(cx + dx * 0.25 * s, ytop - 3), (x0, ytop - 1), (x0 + dx * 0.1 * s, ytop + reach * 0.45), (x0 + dx * 0.2 * s, ytop + reach)]
            d.line(path, fill=ink, width=7, joint="curve")
            d.line(path, fill=mid, width=5, joint="curve")
            d.line([(px - 1, py) for px, py in path], fill=lit, width=1, joint="curve")
            d.point((int(path[-1][0]), int(path[-1][1]) + 2), fill=lit)
        arr = np.array(img)
        for _ in range(12):  # a vein of light up the ankle
            x, y = cx + int(rng.integers(-4, 5)), int(rng.integers(ytop - 11, ytop - 1))
            if arr[y, x, 3] and rng.random() < 0.55:
                arr[y, x] = (60, 160, 160, 255)
                gsub[y, x] = (120, 244, 230, 255)
        out[:, v * 64:(v + 1) * 64] = arr
        glow[:, v * 64:(v + 1) * 64] = gsub
    save(OUT / "arena_plinth_glow.png", glow)
    return out, 58


# ------------------------------------------------------------------ the fire bowl
def brazier_arr():
    """A bronze fire bowl on three iron legs: the bowl rimmed and dented, green with age, teal coals inside (the flame is a strip of its own). 32 x 48, feet row 44."""
    rng = rng_for(580)
    m = h.Model()
    for k in range(3):
        a = k / 3 * math.tau + 0.4
        m.limb(V(math.cos(a) * 9.0, 0, math.sin(a) * 6.5), V(math.cos(a) * 3.0, 17, math.sin(a) * 2.2), 1.5, 1.2, IRON)
    m.limb(V(0, 8, 0), V(0, 8.8, 0), 7.5, 7.5, IRON)  # a ring that ties the legs
    m.ell(V(0, 20, 0), (9.6, 4.6, 7.6), BRONZE)  # the bowl
    m.ell(V(0, 24.0, 0), (10.4, 1.3, 8.4), BRONZE, R=h.rot_x(0.0))  # the rim
    m.ell(V(0, 24.8, 0), (8.6, 0.8, 6.8), h.TEAL, kind="emit")  # the coals
    for _ in range(5):
        m.ell(V(rng.uniform(-6, 6), 24.9, rng.uniform(-4, 4)), (1.4, 0.6, 1.0), h.TEAL, kind="emit")
    m.ell(V(-6.0, 21.0, 5.2), (2.4, 1.2, 1.0), MOSS)  # verdigris
    arr = to_array(render(m, 32, 48, 44))
    return shadowed(arr, 44, 10, 3), 44


def flame_arr():
    """Four frames of a cold teal flame with a violet foot and a white heart (unlit strip). 4 frames of 20 x 26, feet row 24."""
    out = np.zeros((26, 80, 4), np.uint8)
    for f in range(4):
        img = Image.new("RGBA", (20, 26), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        rng = np.random.default_rng(600 + f)
        sway = [0, 1, 0, -1][f]
        tall = [18, 21, 17, 20][f]
        layers = [((90, 60, 200, 160), 1.0, 0), ((60, 190, 196, 215), 0.82, 1), ((150, 245, 235, 235), 0.55, 2), ((236, 250, 255, 255), 0.28, 3)]
        for col, k, _ in layers:
            wd = 6.8 * k
            ht = tall * k
            pts = [(10 - wd, 24), (10 - wd * 0.6, 24 - ht * 0.45), (10 + sway * 2 - wd * 0.2, 24 - ht * 0.8), (10 + sway * 3, 24 - ht), (10 + sway * 2 + wd * 0.35, 24 - ht * 0.7), (10 + wd * 0.7, 24 - ht * 0.4), (10 + wd, 24)]
            d.polygon(pts, fill=col)
        for _ in range(3):  # sparks
            d.point((int(rng.integers(5, 15)), int(rng.integers(1, 12))), fill=(180, 250, 240, 255))
        out[:, f * 20:(f + 1) * 20] = np.array(img)
    return out, 24


# ------------------------------------------------------------------ the banner
def pole_arr():
    """An iron pole with a hooked crossbar and a small bronze eagle's head at the top, leaning a little. 28 x 80, feet row 76."""
    rng = rng_for(620)
    m = h.Model()
    m.limb(V(0, 0, 0), V(-0.8, 60, 0), 1.7, 1.3, IRON)
    m.limb(V(-7.0, 56, 0), V(8.0, 56.5, 0), 1.1, 1.1, IRON)  # the bar the cloth hangs from
    m.ell(V(-0.9, 62.5, 0), (2.2, 2.6, 2.0), BRONZE)  # the head
    m.limb(V(-0.9, 63.0, 0), V(1.8, 62.0, 0.5), 0.9, 0.3, BRONZE)  # the beak
    for k in range(3):
        m.ell(V(-0.5, 2 + k * 0.8, 0), (3.0 - k * 0.5, 0.9, 2.4), AS)  # stones round its foot
    m.ell(V(-3.0, 1.0, 1.5), (1.8, 1.0, 1.4), MOSS_L)
    arr = to_array(render(m, 28, 80, 76))
    return shadowed(arr, 76, 8, 2), 76


def cloth_arr():
    """The banner: wine red of the order, a gold hem and a gold sun, torn into three tails, stained and frayed; it sways in the wind (hung from its top row). 20 x 64, pivot row 20."""
    img = Image.new("RGBA", (20, 44), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rows = [("3a0a16", "5e1426", "8a2038")]
    dark, mid, light = (hexc("3a0a16"), hexc("5e1426"), hexc("8a2038"))
    gold, gold_d = hexc("d4bc78"), hexc("a08844")
    ink = hexc("1b1a2e")
    tails = [(0, 40), (7, 34), (14, 42)]  # x start, length of three tails
    for x0, ln in tails:
        w = 6 if x0 < 14 else 6
        d.rectangle([x0, 2, x0 + w - 1, ln], fill=col(mid))
        d.polygon([(x0, ln), (x0 + w - 1, ln), (x0 + w // 2, ln + 3)], fill=col(mid))
        d.line([(x0, 2), (x0, ln)], fill=col(light))
        d.line([(x0 + w - 1, 2), (x0 + w - 1, ln)], fill=col(dark))
    d.rectangle([0, 0, 19, 3], fill=col(gold_d))  # the hem the cloth hangs by
    d.line([(0, 1), (19, 1)], fill=col(gold))
    cx, cy = 9, 14
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], outline=col(gold))  # a gold sun
    for k in range(8):
        a = k / 8 * math.tau
        d.line([(cx + math.cos(a) * 5, cy + math.sin(a) * 5), (cx + math.cos(a) * 8, cy + math.sin(a) * 8)], fill=col(gold_d))
    d.point([(cx, cy), (cx - 1, cy), (cx, cy - 1)], fill=col(gold))
    arr = np.array(img)
    rng = np.random.default_rng(630)
    for _ in range(30):  # holes, stains, frayed edge
        x, y = int(rng.integers(0, 20)), int(rng.integers(5, 42))
        if arr[y, x, 3]:
            if rng.random() < 0.35:
                arr[y, x] = (0, 0, 0, 0)
            else:
                arr[y, x, :3] = dark[:3]
    for (x0, ln) in tails:
        for yy in range(ln - 5, ln + 3):
            for xx in range(x0, x0 + 6):
                if 0 <= yy < 44 and arr[yy, xx, 3] and rng.random() < 0.32:
                    arr[yy, xx] = (0, 0, 0, 0)
    # a 1 px ink outline
    alpha = arr[..., 3] > 0
    grown = alpha.copy()
    grown[1:, :] |= alpha[:-1, :]
    grown[:-1, :] |= alpha[1:, :]
    grown[:, 1:] |= alpha[:, :-1]
    grown[:, :-1] |= alpha[:, 1:]
    edge = grown & ~alpha
    arr[edge] = col(ink)
    padded = np.zeros((64, 20, 4), np.uint8)  # 20 empty rows on top: the hem hangs from the pole's bar, the sway pivots on row 20
    padded[20:] = arr
    return padded, 20


# ------------------------------------------------------------------ moulted feathers
def feather_arr():
    """Three huge dark feathers lying on the floor, black flesh with a violet rim and a thread of light along the shaft (the ones he lost). 3 frames of 64 x 24, feet row 12."""
    out = np.zeros((24, 64 * 3, 4), np.uint8)
    flesh, mid, rim, rim_l, out_c = hexc("0c0814"), hexc("150e24"), hexc("5a36b8"), hexc("8a68f0"), hexc("040208")
    for v in range(3):
        img = Image.new("RGBA", (64, 24), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        ang = [-0.18, 0.12, -0.04][v]
        length = [52, 46, 56][v]
        x0, y0 = 6, 12 - ang * 20
        pts_u, pts_l = [], []
        for i in range(0, length + 1):
            u = i / length
            half = 0.5 + 5.2 * (math.sin(math.pi * min(1.0, u * 1.15)) ** 0.6) * (1 - u ** 3)
            cx, cy = x0 + i, y0 + ang * i
            pts_u.append((cx, cy - half))
            pts_l.append((cx, cy + half))
        d.polygon(pts_u + pts_l[::-1], fill=col(mid), outline=col(out_c))
        for i in range(3, length - 2):  # the lit upper edge, the barbs, a split
            u = i / length
            cx, cy = x0 + i, y0 + ang * i
            half = 0.5 + 5.2 * (math.sin(math.pi * min(1.0, u * 1.15)) ** 0.6) * (1 - u ** 3)
            d.point((cx, cy - half + 0.5), fill=col(rim_l) if i % 3 == 0 else col(rim))
            if i % 4 == 0:
                d.line([(cx, cy - half * 0.2), (cx + 3, cy - half * 0.95)], fill=col(flesh))
                d.line([(cx, cy + half * 0.2), (cx + 3, cy + half * 0.95)], fill=col(flesh))
            if i == int(length * 0.55):
                d.line([(cx, cy - half), (cx + 4, cy + half * 0.1)], fill=(0, 0, 0, 0))
        d.line([(x0, y0), (x0 + length, y0 + ang * length)], fill=col(rim_l))
        arr = np.array(img)
        # the shaft glows a little: it is a feather of the void
        out[:, v * 64:(v + 1) * 64] = arr
    return out, 12


def feather_glow(arr):
    """Only the light along the shaft, as emissive pixels the glow pass can pick."""
    g = np.zeros_like(arr)
    teal = np.array(h.RAMPS[h.VIOLET][2], np.uint8)
    for f in range(3):
        sub = arr[:, f * 64:(f + 1) * 64]
        m = (sub[..., 0] == 138) & (sub[..., 1] == 104) & (sub[..., 2] == 240)
        g[:, f * 64:(f + 1) * 64][m] = col(sub[m][0]) if m.any() else (0, 0, 0, 0)
    return g


# ------------------------------------------------------------------ crystals
def crystals_arr():
    """Three clusters of dim teal crystal growing out of a crack in the stone. 3 frames of 32 x 32, feet row 26."""
    out = np.zeros((32, 32 * 3, 4), np.uint8)
    for v in range(3):
        rng = rng_for(660 + v)
        m = h.Model()
        for k in range(3):
            m.ell(V(rng.uniform(-3, 3), 0.8, rng.uniform(-1.5, 1.5)), (rng.uniform(2.5, 4.0), 1.4, 2.0), STN[k % 2], R=h.rot_y(rng.uniform(0, 3)))
        crystal(m, rng, V(0, 1.0, 0), 5 + v, 11.0 + 2 * v)
        arr = to_array(render(m, 32, 32, 26))
        out[:, v * 32:(v + 1) * 32] = shadowed(arr, 26, 9, 2)
    return out, 26


def main():
    for name, fn in (("rubble", rubble_arr), ("drum", drum_arr), ("stump", stump_arr), ("plinth", plinth_arr), ("brazier", brazier_arr), ("flame", flame_arr), ("pole", pole_arr), ("cloth", cloth_arr), ("feather", feather_arr), ("crystals", crystals_arr)):
        arr, feet = fn()
        size = put("arena_" + name, arr, glow=name not in ("flame", "cloth", "feather", "stump", "plinth"))
        print("arena_" + name, size, "feet", feet)
    feathers, _ = feather_arr()
    g = feather_glow(feathers)
    if g[..., 3].any():
        save(OUT / "arena_feather_glow.png", g)
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))


def preview(path):
    tiles = [load_png_arr(OUT / f"arena_{n}.png") for n in ("rubble", "drum", "stump", "plinth", "brazier", "flame", "pole", "cloth", "feather", "crystals")]
    wid = sum(t.shape[1] for t in tiles) + 8 * (len(tiles) + 1)
    canvas = np.zeros((max(t.shape[0] for t in tiles) + 16, wid, 4), np.uint8)
    canvas[:] = (70, 82, 76, 255)
    x = 8
    for t in tiles:
        sub = canvas[8:8 + t.shape[0], x:x + t.shape[1]]
        a = t[..., 3:4] / 255.0
        sub[..., :3] = (t[..., :3] * a + sub[..., :3] * (1 - a)).astype(np.uint8)
        x += t.shape[1] + 8
    save(path, np.kron(canvas, np.ones((2, 2, 1), np.uint8)))


if __name__ == "__main__":
    main()
