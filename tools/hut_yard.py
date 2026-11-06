#!/usr/bin/env python3
"""The yard of the old hut (needs numpy): what stands in front of and beside it, made like the hut itself (ellipsoids through hut_lib / art_hero3d, the trunks'
violet bark, mossy stones, ink between forms, grain): a fire pit with a kettle and its flames, seats (log, stumps, stones, a plank bench), a chopping block with an axe and split wood, a rain barrel with a
bucket, a drying line whose rags sway too.
    python3 tools/hut_yard.py [preview.png]     writes assets/interior/hut/yard_*.png (+ _glow sheets with only the emissive pixels: unlit, a living glow at night)
Positions and footprints live in data/ground.json huts[].yard.props; the ground (trampled earth, stepping stones, ash, chips) is baked by tools/bake_ground.py."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from gen_art import hexc  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, load_png_arr, save  # noqa: E402

OUT = ROOT / "interior" / "hut"
WATER, ASH_M = len(h.RAMPS), len(h.RAMPS) + 1
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["0a0918", "17163a", "2c3466", "5f7ab8"],  # rain water: dark, a little sky in it
    ["120d16", "251d2e", "3f394f", "7f7893"],  # soot and ash
]]
FIRE_GLOW = (h.TEAL, h.VIOLET, FIRE)  # not SKY: the water must go dark with the evening


def shadowed(arr, ground, rx, ry, dx=0):
    return soft_shadow(arr, arr.shape[1] / 2 + dx, ground + 1, rx, ry)


def cap(m, c, axis, r, mat, thick=0.9):
    """A flat disc (the cut end of a log) facing along `axis`."""
    m.ell(c, (r, thick, r), mat, R=h.frame_from(np.asarray(axis, float), V(0, 0, 1) if abs(axis[2]) < 0.9 else V(1, 0, 0)))


def rings(m, c, axis, r, mat=BARK_D):
    for k in (0.32, 0.62, 0.9):
        n = int(18 * k) + 6
        for i in range(n):
            a = i / n * math.tau
            p = np.asarray(c, float) + (V(0, math.cos(a), math.sin(a)) if abs(axis[0]) > 0.9 else V(math.cos(a), 0, math.sin(a))) * r * k
            m.ell(p + np.asarray(axis, float) * 0.1, (0.5, 0.5, 0.5), mat)


# ------------------------------------------------------------------ fire pit
def pit_arr():
    """A ring of rounded stones, an ash bed with embers, charred logs leaning together at the back; the flames are the hut's fire frames, drawn on top.
    The kettle sits beside it. 80 x 64, feet row 46 (the middle of the ring)."""
    rng = rng_for(80)
    m = h.Model()
    R = 21.0
    n = 15
    for k in range(n):
        a = k / n * math.tau + 0.2
        c = V(math.cos(a) * R, 2.6, math.sin(a) * R)
        sz = rng.uniform(4.8, 6.4)
        m.ell(c, (sz * 1.15, rng.uniform(3.0, 4.4), sz * 0.95), (STONE, STONE_L, STONE, STONE_L, STONE)[k % 5], R=h.rot_y(-a))
        if rng.random() < 0.5:
            m.ell(c + V(rng.uniform(-1.5, 1.5), 3.6, rng.uniform(-1, 1)), (rng.uniform(2, 3.6), 0.8, 1.6), MOSS_L if rng.random() < 0.5 else MOSS)
        if 0.45 < a % math.tau < 2.4 and rng.random() < 0.7:  # sooted on the inside
            m.ell(c - V(math.cos(a) * 2.6, -1.0, math.sin(a) * 2.6), (2.0, 1.6, 2.0), GAP)
    m.ell((0, 1.4, 0), (R - 3.0, 1.2, R - 3.0), GAP)  # the ash bed
    m.ell((0, 2.0, 1), (R - 6.0, 0.9, R - 6.5), ASH_M)
    for _ in range(40):  # embers and ash
        a, d = rng.uniform(0, math.tau), (R - 7.0) * math.sqrt(rng.random())
        p = V(math.cos(a) * d, 2.6, math.sin(a) * d)
        if rng.random() < 0.55:
            m.ell(p, (rng.uniform(0.9, 1.8), 0.6, rng.uniform(0.8, 1.4)), FIRE, kind="emit")
        else:
            m.ell(p, (rng.uniform(1.2, 2.6), 0.6, rng.uniform(1.0, 2.0)), ASH_M)
    for k in range(3):  # charred logs leaning together at the back
        a = math.pi * (1.1 + 0.42 * k)
        base = V(math.cos(a) * (R - 3.5), 3.0, math.sin(a) * (R - 5.5))
        top = V(math.cos(a) * 3.0, 17.0 - 1.5 * k, math.sin(a) * 3.0 - 1.5)
        log(m, base, top, 2.6, BARK_D, step=1.1, taper=0.82)
        for q in range(3):  # a seam of glowing char
            t = 0.25 + q * 0.25
            m.ell(base + (top - base) * t + V(0, 0, 1.7), (0.9, 0.7, 0.5), FIRE, kind="emit")
    log(m, V(-9, 3.6, 9), V(10, 3.2, 12.5), 2.5, BARK_D, step=1.1)  # one lying across, half burnt
    cap(m, V(10.6, 3.2, 12.6), (1, 0, 0), 2.4, ASH_M)
    for k in range(3):  # the odd teal fungus on the back stones
        m.ell((-8 + k * 6.5, 8.0 - 0.6 * k, -R + 1.0), (2.0, 0.9, 1.6), h.TEAL, kind="emit")
    # the kettle: blackened iron on a flat stone beside the ring
    kc = V(31.0, 0, 9.0)
    m.ell(kc + V(0, 1.4, 0), (6.4, 1.6, 5.0), STONE_L)
    m.ell(kc + V(0, 5.4, 0), (5.4, 4.6, 5.2), IRON)
    m.ell(kc + V(0, 9.0, 0), (4.0, 1.4, 3.8), IRON)
    m.ell(kc + V(0, 10.4, 0), (2.6, 0.9, 2.5), IRON)
    m.ell(kc + V(0, 11.4, 0), (0.9, 0.8, 0.9), IRON)
    m.limb(kc + V(4.0, 5.0, 0), kc + V(9.4, 9.6, 0), 1.4, 0.7, IRON)
    arc = [kc + V(-math.cos(i / 8 * math.pi) * 5.0, 9.4 + math.sin(i / 8 * math.pi) * 4.8, 0.2) for i in range(9)]
    for a_, b_ in zip(arc[:-1], arc[1:]):  # the bail, a continuous arc
        m.limb(a_, b_, 0.55, 0.55, IRON)
    arr = to_array(render(m, 80, 64, 46))
    arr = grain(arr, 81, amount=0.5, mats=(STONE, STONE_L, BARK_D, IRON, MOSS))
    return shadowed(arr, 46, 36, 9), 46


# ------------------------------------------------------------------ flames
def campfire_frames(W=34, H=34, N=8):
    """The pit's fire, N looping frames of W x H, base row H - 7: a bed of embers, a dozen flame tongues of different height and sway (each loops on its own
    whole number of beats), teardrop-shaped, rounded and soft at the foot (no flat cut), frayed at the tips, a pale-yellow core, flying sparks. Unlit."""
    out = np.zeros((H, W * N, 4), np.uint8)
    base = H - 7
    cols = h.RAMPS[FIRE]
    tongues = []
    for i in range(7):  # x offset, width, height, beats, phase
        u = (i - 3) / 3.0
        tongues.append((u * 7.5 + 0.8 * math.sin(i * 2.3), 4.6 * (1.0 - 0.35 * abs(u)), (H - 11) * (1.0 - 0.38 * abs(u)) * (0.82 + 0.18 * hsh(i, 1, 9)), 1 + i % 3, i * 1.7))
    for f in range(N):
        ph = f / N * math.tau
        field = np.zeros((H, W))
        for (ox, w0, ht, beats, p0) in tongues:
            hh = ht * (0.72 + 0.28 * math.sin(ph * beats + p0)) * (0.9 + 0.1 * math.sin(ph * 2 + p0 * 2))
            sway = math.sin(ph * beats + p0 + 1.2) * 2.6
            for y in range(H):
                yy = base - y  # height above the base line
                if yy < -3 or yy > hh:
                    continue
                u = max(yy, 0) / hh
                width = w0 * (1.0 - u) ** 0.75 * (1.0 + 0.3 * math.sin(u * 6 + ph))
                if yy < 0:
                    width *= 1.0 + yy / 4.0  # rounded foot
                cx = W / 2 + ox * (1.0 - 0.25 * u) + sway * u ** 1.4
                for x in range(W):
                    d = abs(x + 0.5 - cx)
                    if d < width:
                        field[y, x] = max(field[y, x], (1.0 - d / max(width, 0.1)) * (1.0 - 0.55 * u) + 0.12 * (1.0 - u))
        for y in range(H):
            for x in range(W):
                v = field[y, x]
                if v <= 0.02:
                    continue
                u = (base - y) / (H - 11)
                v += (hsh(x, y, f) - 0.5) * 0.14 * (0.3 + u) + (bayer(x, y) - 0.5) * 0.06
                if v > 0.8:
                    tone = 3
                elif v > 0.5:
                    tone = 2
                elif v > 0.2:
                    tone = 1
                elif v > 0.05:
                    tone = 0
                else:
                    continue
                out[y, f * W + x] = (*cols[tone][:3], 255)
        for x in range(W):  # the bed of embers under it: a flat glowing ellipse that breathes, dithered into the ring's dark
            for y in range(base - 1, base + 5):
                e = ((x + 0.5 - W / 2) / 12.0) ** 2 + ((y + 0.5 - base - 1.5) / 3.2) ** 2
                if e < 1.0 and out[y, f * W + x, 3] == 0 and hsh(x, y, 5 + f % 3) < 0.7 - e * 0.5:
                    out[y, f * W + x] = (*cols[0 if e > 0.55 else 1][:3], 255)
        for k in range(4):  # sparks
            sx = int(W / 2 + (hsh(k, 3, 2) - 0.5) * 16 + math.sin(ph + k) * 2)
            t = (f / N + k / 4.0) % 1.0
            sy = int(base - 8 - t * 17)
            if 0 <= sy < H and 0 <= sx < W and out[sy, f * W + sx, 3] == 0:
                out[sy, f * W + sx] = (*cols[3 if t < 0.5 else 2][:3], 255)
    return out


# ------------------------------------------------------------------ seats
def seats_arr():
    """Four seats around the fire: a long log with a flattened top, a squat stump, a flat stone, a plank bench on two stumps. 4 frames of 48 x 34, feet row 26."""
    out = np.zeros((34, 48 * 4, 4), np.uint8)
    for v in range(4):
        rng = rng_for(90 + v)
        m = h.Model()
        if v == 0:
            L = 17.0
            log(m, V(-L, 5.6, 0), V(L, 5.6, 0), 5.6, BARK, step=1.2, rr=lambda t: 0.05 * math.sin(t * 9))
            for sx in (-1, 1):
                cap(m, V(sx * (L + 0.5), 5.6, 0), (1, 0, 0), 5.2, PLANK_W)
                rings(m, V(sx * (L + 0.9), 5.6, 0), (1, 0, 0), 5.0)
            m.ell((0, 10.2, 0.4), (L * 0.78, 0.9, 3.4), PLANK_W)  # worn flat by sitting
            for _ in range(10):
                m.ell((rng.uniform(-L, L), rng.uniform(7, 10.6), rng.uniform(2, 5.6)), (rng.uniform(1.5, 3.2), 0.8, 1.2), MOSS_L if rng.random() < 0.5 else MOSS)
            for k in range(3):
                m.ell((-L + 3.0 + k * 3.2, 4.4 + k * 0.6, 5.6), (1.5, 0.9, 1.0), h.TEAL, kind="emit")
        elif v == 3:
            for sx in (-1, 1):  # two stumps, a worn plank across, a moss-grown end
                log(m, V(sx * 15.0, 0, 0), V(sx * 15.0, 8.5, 0), 5.2, BARK, step=1.1, taper=0.92)
                cap(m, V(sx * 15.0, 8.8, 0), (0, 1, 0), 5.0, PLANK_W)
            slab(m, V(-19.5, 10.4, 0), V(19.5, 10.2, 0), 5.2, 1.3, PLANK_W, (0, 1, 0), step=1.3)
            slab(m, V(-19.5, 9.4, 4.8), V(19.5, 9.2, 4.8), 0.9, 1.0, BARK_D, (0, 0, 1), step=1.3)
            for _ in range(9):
                m.ell((rng.uniform(-18, 18), 11.8, rng.uniform(-3.5, 3.5)), (rng.uniform(1.2, 3), 0.4, 1.0), MOSS_L if rng.random() < 0.6 else MOSS)
            for k in range(2):
                m.ell((-15.0 + k * 3.0, 5.5, 5.4), (1.4, 0.9, 0.9), h.TEAL, kind="emit")
        elif v == 1:
            log(m, V(0, 0, 0), V(0, 11.5, 0), 6.8, BARK, step=1.1, taper=0.94)
            for k in range(5):
                a = k / 5 * math.tau + 0.3
                m.limb(V(math.cos(a) * 5.0, 3.0, math.sin(a) * 5.0), V(math.cos(a) * 9.5, 0.6, math.sin(a) * 8.5), 1.8, 0.7, BARK)
            cap(m, V(0, 11.8, 0), (0, 1, 0), 6.6, PLANK_W)
            rings(m, V(0, 12.2, 0), (0, 1, 0), 6.2)
            for _ in range(6):
                m.ell((rng.uniform(-4, 4), 12.4, rng.uniform(-3, 3)), (rng.uniform(1, 2), 0.4, 1.0), MOSS_L)
        else:
            m.ell((0, 3.2, 0), (11.0, 3.4, 6.6), STONE)
            m.ell((0, 5.8, -0.4), (9.2, 1.3, 5.4), STONE_L)
            for _ in range(8):
                m.ell((rng.uniform(-9, 9), 4.6, rng.uniform(3, 6.4)), (rng.uniform(1.5, 3.4), 0.9, 1.0), MOSS_L if rng.random() < 0.5 else MOSS)
        arr = to_array(render(m, 48, 34, 26))
        arr = grain(arr, 91 + v, amount=0.5, mats=(BARK, PLANK_W, BARK_D, STONE, STONE_L, MOSS))
        arr = shadowed(arr, 26, 15 if v != 1 else 9, 3)
        out[:, v * 48:(v + 1) * 48] = arr
    return out, 26


# ------------------------------------------------------------------ the bedroll
def bedroll_arr():
    """Where he sleeps now that she has his bed: a rolled blanket tied with cord on a worn wine-red cloak, a satchel, a tin cup. 64 x 36, feet row 28."""
    rng = rng_for(140)
    m = h.Model()
    m.ell((0, 0.9, 3), (19, 0.8, 9.5), WOOL)  # the cloak, spread out, its hem torn
    for _ in range(22):
        m.ell((rng.uniform(-16, 16), 1.5, rng.uniform(-4, 10)), (rng.uniform(3, 6), 0.6, rng.uniform(1.5, 3.2)), WOOL if rng.random() < 0.7 else CLAY)
    for k in range(10):
        m.limb(V(-18 + k * 4, 1.0, 12.4), V(-18 + k * 4 + rng.uniform(-1, 1), 0.7, 12.4 + rng.uniform(1.0, 2.6)), 0.5, 0.2, WOOL)
    log(m, V(-13, 5.4, -2), V(13, 5.6, -2), 4.8, LINEN, step=1.1)  # the roll
    for sx in (-1, 1):
        cap(m, V(sx * 13.5, 5.5, -2), (1, 0, 0), 4.5, LINEN)
        rings(m, V(sx * 13.9, 5.5, -2), (1, 0, 0), 4.3, CLAY)
    for x in (-7.5, 6.5):  # the cord round it
        for k in range(16):
            a = k / 16 * math.tau
            m.ell((x, 5.5 + math.cos(a) * 5.0, -2 + math.sin(a) * 5.0), (0.8, 0.8, 0.8), BARK_D)
    for _ in range(8):
        m.ell((rng.uniform(-11, 11), 9.8, rng.uniform(-3, 0)), (rng.uniform(1.5, 3), 0.7, 1.1), LINEN)
    m.ell((21, 4.4, 8.5), (5.6, 4.2, 3.8), CLAY)  # the satchel, its flap and buckle
    m.ell((21, 7.2, 9.0), (5.8, 2.0, 3.6), BARK)
    m.ell((21, 5.6, 12.4), (1.0, 1.2, 0.5), IRON)
    log(m, V(-19, 0, 9), V(-19, 4.4, 9), 2.1, IRON, step=0.9)  # a tin cup
    m.ell((-19, 4.7, 9), (1.6, 0.4, 1.6), GAP)
    arr = to_array(render(m, 64, 36, 28))
    arr = grain(arr, 141, amount=0.5, mats=(WOOL, LINEN, CLAY, BARK, BARK_D))
    return shadowed(arr, 28, 24, 5), 28


# ------------------------------------------------------------------ chopping block
def block_arr():
    """A stump with a bark of violet veins, rings and deep cuts on top, a woodcutter's axe left in it. 84 x 66, feet row 50."""
    rng = rng_for(100)
    m = h.Model()
    log(m, V(0, 0, 0), V(0, 16.0, 0), 11.5, BARK, step=1.2, taper=0.93)
    for k in range(6):  # root flare
        a = k / 6 * math.tau + 0.4
        m.limb(V(math.cos(a) * 9.0, 3.5, math.sin(a) * 9.0), V(math.cos(a) * 16.0, 0.6, math.sin(a) * 14.0), 2.6, 0.9, BARK)
    cap(m, V(0, 16.6, 0), (0, 1, 0), 11.2, PLANK_W)
    rings(m, V(0, 17.4, 0), (0, 1, 0), 10.6)
    for (a, ln, w) in ((0.5, 8.0, 1.0), (-0.6, 6.5, 0.8), (1.9, 5.0, 0.7)):  # the cuts of years of chopping
        m.ell((math.cos(a) * 1.0, 17.4, math.sin(a) * 1.0), (ln, 0.5, w), GAP, R=h.rot_y(a))
    for _ in range(40):  # chewed edge
        a = rng.uniform(0, math.tau)
        m.ell((math.cos(a) * 11.4, 16.0 + rng.uniform(-0.4, 0.8), math.sin(a) * 11.0), (rng.uniform(1, 2), 0.7, 1.0), PLANK_W if rng.random() < 0.5 else BARK_D)
    for g in range(3):  # violet veins in the bark
        a = 0.9 + g * 0.9
        for i in range(10):
            t = i / 10
            m.ell((math.cos(a + 0.12 * math.sin(i)) * 11.9, 2.0 + t * 12.5, math.sin(a + 0.12 * math.sin(i)) * 11.4), (0.4, 0.9, 0.4), h.VIOLET, kind="emit")
    for _ in range(8):
        a = rng.uniform(0.3, 2.8)
        m.ell((math.cos(a) * 11.6, rng.uniform(2.0, 9.0), math.sin(a) * 11.2), (rng.uniform(1.4, 2.6), 1.0, 0.9), MOSS_L if rng.random() < 0.5 else MOSS)
    # the axe: head sunk into the top, the handle leaning up and away
    head = V(1.5, 20.6, 1.0)
    m.ell(head, (5.2, 3.6, 1.0), IRON, R=h.frame_from(V(0.5, -0.5, 0), V(0, 0, 1)) @ h.rot_y(0.0))
    m.ell(head + V(4.8, 1.0, 0), (2.0, 2.6, 1.6), IRON)  # the eye
    m.ell(head + V(-3.6, -1.4, 0.2), (0.7, 3.2, 0.7), IRON)  # the edge, caught by the light
    log(m, head + V(5.4, 1.4, 0), V(19.0, 42.0, 4.0), 1.2, PLANK_W, step=1.0, taper=0.9)
    m.ell(V(19.4, 42.6, 4.0), (1.6, 1.1, 1.4), BARK_D)
    arr = to_array(render(m, 84, 66, 50))
    arr = grain(arr, 101, amount=0.6)
    return shadowed(arr, 50, 34, 8), 50


# ------------------------------------------------------------------ rain barrel
def barrel_arr():
    """A rain barrel with dark water holding a bit of the sky, a bucket and a ladle. 70 x 56, feet row 46."""
    rng = rng_for(110)
    m = h.Model()
    bx = -7.0
    n = 18
    for k in range(n):
        a = k / n * math.tau
        for s in range(14):
            t = s / 13
            y = 1.0 + t * 26
            rad = 9.4 + 2.2 * math.sin(t * math.pi)
            m.ell((bx + math.cos(a) * rad, y, math.sin(a) * rad), (2.0, 2.2, 2.0), (BARK, PLANK_W, BARK_D)[(k + (1 if k == 7 else 0)) % 3], R=h.rot_y(-a))
    for y in (5.0, 22.0):
        for k in range(26):
            a = k / 26 * math.tau
            rad = 9.8 + 2.2 * math.sin((y - 1) / 26 * math.pi)
            m.ell((bx + math.cos(a) * rad, y, math.sin(a) * rad), (1.0, 1.1, 1.0), IRON)
    for k in range(20):  # the rim
        a = k / 20 * math.tau
        m.ell((bx + math.cos(a) * 10.6, 27.4, math.sin(a) * 10.6), (1.4, 0.8, 1.4), PLANK_W)
    m.ell((bx, 26.0, 0), (9.6, 0.5, 9.6), WATER)  # the water
    for _ in range(14):  # leaves and a reflection of the sky
        m.ell((bx + rng.uniform(-6, 6), 26.4, rng.uniform(-5, 5)), (rng.uniform(0.8, 1.6), 0.3, rng.uniform(0.6, 1.0)), MOSS if rng.random() < 0.5 else WATER)
    for _ in range(12):
        a = rng.uniform(0.2, 2.9)
        m.ell((bx + math.cos(a) * 11.2, rng.uniform(1, 12), math.sin(a) * 11.2), (rng.uniform(1.5, 3), 1.0, 1.0), MOSS_L if rng.random() < 0.5 else MOSS)
    for q in range(5):  # water weeping green down one side
        m.ell((bx + 10.2, 24 - q * 3.5, 4.2), (0.7, 1.4, 0.6), MOSS_L)
    # the ladle hangs on the rim
    m.limb(V(bx + 2, 28.0, -6), V(bx + 9, 29.0, 6), 0.5, 0.4, IRON)
    m.ell((bx + 9.4, 28.6, 7.0), (2.2, 1.0, 2.0), IRON)
    # a bucket beside it, rope handle and a wet ring
    cx, cz = 20.0, 8.0
    log(m, V(cx, 0, cz), V(cx, 9.5, cz), 5.0, PLANK_W, step=1.0, taper=1.12)
    for y in (2.5, 7.5):
        for k in range(16):
            a = k / 16 * math.tau
            m.ell((cx + math.cos(a) * 5.7, y, cz + math.sin(a) * 5.7), (0.8, 0.7, 0.8), IRON)
    m.ell((cx, 9.8, cz), (5.0, 0.5, 5.0), WATER)
    arc = [V(cx - 5.6 * math.cos(i / 8 * math.pi), 9.8 + math.sin(i / 8 * math.pi) * 6.0, cz) for i in range(9)]
    for a_, b_ in zip(arc[:-1], arc[1:]):  # a rope handle, a continuous arc
        m.limb(a_, b_, 0.5, 0.5, STRAW)
    arr = to_array(render(m, 70, 56, 46))
    arr = grain(arr, 111, amount=0.6)
    return shadowed(arr, 46, 30, 6), 46


# ------------------------------------------------------------------ the drying line
LINE = dict(w=128, h=84, ground=70)
LINE_SPAN = 54.0  # units from the pole to the hut's eave
LINE_TOP = 52.0


def rope_y(x, pole_x):
    t = (pole_x - x) / LINE_SPAN
    return LINE_TOP + 5.0 * t - 5.2 * math.sin(math.pi * min(max(t, 0.0), 1.0))


def line_arrs():
    """A pole with a rope running to the hut's eave and, in a sheet of its own (they sway), rags hung out to dry: linen, one stained dark, a torn one.
    Returns (pole and rope, rags, feet row, the row of the rope, where the rags are hung from)."""
    rng = rng_for(130)
    m = h.Model()
    c = h.Model()
    px = 36.0
    log(m, V(px, 0, 0), V(px + 0.8, LINE_TOP + 2, 0), 2.1, BARK, step=1.2, taper=0.8)
    for k in range(5):
        a = k / 5 * math.tau + 0.3
        m.limb(V(px + math.cos(a) * 2, 2.6, math.sin(a) * 2), V(px + math.cos(a) * 7.5, 0.5, math.sin(a) * 6.5), 1.6, 0.7, BARK)
    for _ in range(6):
        m.ell((px + rng.uniform(-2, 2), rng.uniform(2, 10), rng.uniform(1.4, 2.2)), (rng.uniform(1.2, 2.4), 1.0, 0.8), MOSS_L if rng.random() < 0.5 else MOSS)
    m.ell((px + 0.8, LINE_TOP + 3.2, 0), (2.4, 1.2, 2.4), BARK_D)
    m.ell((px + 0.8, LINE_TOP + 3.6, 1.8), (0.9, 0.9, 0.9), h.TEAL, kind="emit")  # a bud on the pole's top
    xs = np.arange(px, px - LINE_SPAN - 0.1, -1.4)
    for x0, x1 in zip(xs[:-1], xs[1:]):
        m.limb(V(x0, rope_y(x0, px), 0.3), V(x1, rope_y(x1, px), 0.3), 0.42, 0.42, STRAW, step=0.6)
    m.ell((px - LINE_SPAN, rope_y(px - LINE_SPAN, px), 0.3), (1.4, 1.4, 1.4), STRAW)  # the knot at the eave
    pegs = [(px - 11, 17.0, LINEN, 0), (px - 24, 23.0, WOOL, 1), (px - 36, 15.0, LINEN, 2), (px - 47, 20.0, STRAW, 3)]
    for x, ln, mat, k in pegs:
        y0 = rope_y(x, px)
        m.ell((x, y0 + 0.2, 0.6), (0.8, 1.3, 0.8), BARK_D)  # the peg stays on the line
        wid = 4.6 if k != 3 else 3.6
        for s in range(int(ln / 0.9)):
            t = s / (ln / 0.9)
            ww = wid * (1.0 - 0.1 * t) * (1.0 if k != 3 or s % 5 else 0.5)  # the last rag is torn
            sx = 0.9 * math.sin(s * 0.33 + k) + 0.7 * t * (1 if k % 2 else -1)
            mm = mat
            if k == 1:  # the dark stain a wound leaves in linen
                mm = WOOL if hsh(s // 2, k, 4) > 0.3 or t < 0.2 else LINEN
            elif k == 0 and t > 0.55 and hsh(s, 1, 6) > 0.78:
                mm = WOOL
            c.ell(V(x + sx, y0 - 1.2 - s * 0.9, 1.1 + 0.4 * math.sin(s * 0.5 + k)), (ww, 0.8, 0.6), mm, R=h.rot_y(0.25 * math.sin(s * 0.3 + k)))
        c.ell(V(x, y0 - 0.4, 1.2), (wid + 0.6, 0.9, 0.9), mat)  # the fold over the rope
    fw, fh, g = LINE["w"], LINE["h"], LINE["ground"]
    pole = to_array(render(m, fw, fh, g))
    pole = grain(pole, 131, amount=0.5, mats=WOODS)
    rags = to_array(render(c, fw, fh, g))
    return shadowed(pole, g, 8, 2.5, dx=px * 0.92), rags, g


# ------------------------------------------------------------------ output
def put(name, arr, glow_mats=FIRE_GLOW):
    save(OUT / f"{name}.png", arr)
    g = glow_of(arr, glow_mats) if glow_mats else None
    if g is not None and g[..., 3].any():
        save(OUT / f"{name}_glow.png", g)
    elif (OUT / f"{name}_glow.png").exists():
        (OUT / f"{name}_glow.png").unlink()
    return arr.shape[1], arr.shape[0]


def main():
    sizes = {}
    arr, feet = pit_arr()
    sizes["yard_pit"] = (put("yard_pit", arr), feet)
    import hut_fx
    sizes["yard_fire"] = (put("yard_fire", campfire_frames(), None), 27)
    arr, feet = seats_arr()
    sizes["yard_seats"] = (put("yard_seats", arr), feet)
    arr, feet = bedroll_arr()
    sizes["yard_bedroll"] = (put("yard_bedroll", arr, None), feet)
    arr, feet = block_arr()
    sizes["yard_block"] = (put("yard_block", arr), feet)
    arr, feet = barrel_arr()
    sizes["yard_barrel"] = (put("yard_barrel", arr, (h.TEAL, h.VIOLET)), feet)
    pole, rags, feet = line_arrs()
    sizes["yard_line"] = (put("yard_line", pole), feet)
    sizes["yard_rags"] = (put("yard_rags", rags, None), feet)
    for k, v in sizes.items():
        print(k, v)
    if len(sys.argv) > 1:
        preview(Path(sys.argv[1]))


def preview(path):
    """A contact sheet on meadow green (2x): every yard sprite once, the fire frame on the pit, the garden with its plants."""
    names = ["yard_pit", "yard_seats", "yard_bedroll", "yard_block", "yard_barrel", "yard_line"]
    tiles = []
    for n in names:
        a = load_png_arr(OUT / f"{n}.png")
        if n == "yard_line":
            a = over(a, load_png_arr(OUT / "yard_rags.png"))
        if n == "yard_pit":
            fire = load_png_arr(OUT / "yard_fire.png")[:, :34]
            a = over(a, place(fire, a.shape, (a.shape[1] // 2 - 17, 46 - 26)))
        tiles.append(a)
    wid = sum(t.shape[1] for t in tiles) + 8 * (len(tiles) + 1)
    hei = max(t.shape[0] for t in tiles) + 16
    canvas = np.zeros((hei, wid, 4), np.uint8)
    canvas[:] = (58, 96, 66, 255)
    x = 8
    for t in tiles:
        canvas[8:8 + t.shape[0], x:x + t.shape[1]] = over(canvas[8:8 + t.shape[0], x:x + t.shape[1]], t)
        x += t.shape[1] + 8
    save(path, np.kron(canvas, np.ones((2, 2, 1), np.uint8)))


def over(base, top):
    out = base.copy()
    a = top[..., 3:4] / 255.0
    out[..., :3] = (top[..., :3] * a + base[..., :3] * (1 - a)).astype(np.uint8)
    out[..., 3] = np.maximum(base[..., 3], top[..., 3])
    return out


def place(small, shape, at):
    out = np.zeros(shape, np.uint8)
    hh, ww = small.shape[:2]
    out[at[1]:at[1] + hh, at[0]:at[0] + ww] = small
    return out


if __name__ == "__main__":
    main()
