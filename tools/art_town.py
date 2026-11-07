#!/usr/bin/env python3
"""The pieces of the player's town (docs/town.md), made like the hut and the trunks (ellipsoids through art_hero3d / hut_lib: violet-plum bark, mossy stones,
ink between forms, grain, glowing teal buds and warm iron light). Needs numpy.
    python3 tools/art_town.py [preview.png]     writes assets/town/<piece>.png (+ _glow with only the emissive pixels, + _pad: the trodden ground under big pieces)
                                                and the item icons assets/items/plank.png, rope.png
Frames and footprints are in data/town.json: the node stands on the FRONT edge of the footprint (the 'feet' row), the model's z runs from -depth (back) to 0 (front),
x is centred. 1 px of ground depth is 1 / (sin 26deg * 0.92) = 2.5 model units, so a footprint of 28 px is about 69 units deep."""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, glow_of, grain, hsh, rng_for, save, soft_shadow, to_array, V, log, slab, bayer, fbm  # noqa: E402
import hut_lib  # noqa: E402
from gen_art import hexc  # noqa: E402

OUT = ROOT / "town"
ICONS = ROOT / "items"
UNITS_PER_PX = 1.0 / (math.sin(math.radians(26.0)) * h.SCALE)  # model units of depth per px of ground depth
LIT = (h.TEAL, FIRE)
WOODISH = (BARK, BARK_D, PLANK, PLANK_W, MOSS, MOSS_L, STONE, STONE_L, IRON, STRAW, LINEN, CLAY)


def depth_units(px):
    return px * UNITS_PER_PX


def shade(arr, ground, rx, ry, dx=0):
    return soft_shadow(arr, arr.shape[1] / 2 + dx, ground + 1, rx, ry)


def finish(arr, seed, ground, rx, ry, dx=0, amount=0.5):
    arr = grain(arr, seed, amount=amount, mats=WOODISH)
    return shade(arr, ground, rx, ry, dx)


def put(name, arr, glow_mats=LIT):
    save(OUT / f"{name}.png", arr)
    g = glow_of(arr, glow_mats)
    if g[..., 3].any():
        save(OUT / f"{name}_glow.png", g)
    return arr


# ------------------------------------------------------------------ small building blocks
def upright(m, x, z, y0, y1, r, mat=BARK, taper=0.9):
    log(m, V(x, y0, z), V(x, y1, z), r, mat, step=1.1, taper=taper)


def boards_vertical(m, rng, x0, x1, y0, y1, z, mat=PLANK, width=2.2, gap_every=0):
    """Upright boards side by side (a plank wall facing +z), a little uneven."""
    x = x0 + width
    i = 0
    while x < x1:
        top = y1 - rng.uniform(0.0, 2.2) * (1 if i % 3 == 0 else 0.4)
        m_mat = PLANK_W if rng.random() < 0.3 else mat
        slab(m, V(x, y0, z + rng.uniform(-0.3, 0.3)), V(x + rng.uniform(-0.25, 0.25), top, z), width, 0.9, m_mat, (0, 0, 1), step=1.3)
        x += width * 2 - 0.1
        i += 1


def beam_x(m, x0, x1, y, z, r=1.5, mat=BARK):
    log(m, V(x0, y, z), V(x1, y, z), r, mat, step=1.1)


def roof(m, rng, x0, x1, back, front, mat=ROOF, plank=3.3, moss=0.35):
    """A mono-pitch roof of long planks. back = (y, z), front = (y, z): the planks run down the slope; they overlap like shingles' big cousins."""
    (by, bz), (fy, fz) = back, front
    slope = V(0, fy - by, fz - bz)
    normal = np.cross(V(1, 0, 0), slope)
    normal = normal / np.linalg.norm(normal)
    if normal[1] < 0:
        normal = -normal
    x = x0 + plank
    k = 0
    while x < x1:
        jitter = rng.uniform(-0.6, 0.6)
        slab(m, V(x, by + jitter * 0.4, bz), V(x + rng.uniform(-0.2, 0.2), fy + jitter * 0.4, fz), plank, 1.0, mat, tuple(normal), step=1.4)
        x += plank * 2 - 0.5
        k += 1
    for _ in range(int((x1 - x0) * moss * 0.9)):  # moss and a few glowing buds on the top
        t = rng.uniform(0.0, 1.0)
        px = rng.uniform(x0 + 2, x1 - 2)
        py = by + (fy - by) * t + 1.8
        pz = bz + (fz - bz) * t
        m.ell((px, py, pz), (rng.uniform(1.5, 3.6), 0.5, rng.uniform(1.0, 2.2)), MOSS_L if rng.random() < 0.5 else MOSS)
    for _ in range(3):
        t = rng.uniform(0.4, 0.95)
        m.ell((rng.uniform(x0 + 3, x1 - 3), by + (fy - by) * t + 2.4, bz + (fz - bz) * t), (0.8, 0.8, 0.8), h.TEAL, kind="emit")


def crate(m, c, s, mat=PLANK, rng=None):
    cx, cy, cz = c
    sx, sy, sz = s
    for dx in (-1, 1):
        for dz in (-1, 1):
            log(m, V(cx + dx * (sx - 0.8), cy, cz + dz * (sz - 0.8)), V(cx + dx * (sx - 0.8), cy + sy * 2, cz + dz * (sz - 0.8)), 0.9, BARK_D, step=1.0)
    for yy in np.linspace(cy + 1.4, cy + sy * 2 - 1.2, 3):
        for dz, ex in ((1, 0), (-1, 0)):
            slab(m, V(cx - sx, yy, cz + dz * sz), V(cx + sx, yy, cz + dz * sz), 1.6, 0.7, mat, (0, 0, 1), step=1.3)
        for dx in (-1, 1):
            slab(m, V(cx + dx * sx, yy, cz - sz), V(cx + dx * sx, yy, cz + sz), 1.6, 0.7, mat, (1, 0, 0), step=1.3)
    m.ell((cx, cy + sy * 2 - 0.3, cz), (sx - 0.4, 0.8, sz - 0.4), PLANK_W)


def barrel(m, c, r=6.0, height=12.0, mat=PLANK_W):
    cx, cy, cz = c
    for k in range(9):
        t = k / 8
        belly = 1.0 + 0.16 * math.sin(t * math.pi)
        m.ell((cx, cy + t * height, cz), (r * belly, 1.1, r * belly), mat)
    for t in (0.14, 0.5, 0.86):
        belly = 1.0 + 0.16 * math.sin(t * math.pi)
        m.ell((cx, cy + t * height, cz), (r * belly + 0.5, 0.55, r * belly + 0.5), IRON)
    m.ell((cx, cy + height + 0.4, cz), (r * 0.9, 0.6, r * 0.9), PLANK)


def sack(m, c, r=4.2, mat=LINEN, rng=None):
    cx, cy, cz = c
    m.ell((cx, cy + r * 0.85, cz), (r, r * 0.9, r * 0.85), mat)
    m.ell((cx, cy + r * 1.7, cz), (r * 0.5, r * 0.45, r * 0.45), mat)
    m.ell((cx, cy + r * 1.35, cz), (r * 0.42, 0.5, r * 0.42), CLAY)


def lantern(m, c, hang=5.0, mat=FIRE, kind="emit"):
    cx, cy, cz = c
    m.limb(V(cx, cy + hang, cz), V(cx, cy + 1.6, cz), 0.35, 0.35, IRON)
    m.ell((cx, cy + 0.9, cz), (1.8, 0.8, 1.8), IRON)
    m.ell((cx, cy - 1.6, cz), (1.5, 2.0, 1.5), mat, kind=kind)
    for a in (0.0, 1.57, 3.14, 4.71):
        m.limb(V(cx + math.cos(a) * 1.7, cy + 0.9, cz + math.sin(a) * 1.7), V(cx + math.cos(a) * 1.7, cy - 3.2, cz + math.sin(a) * 1.7), 0.28, 0.28, IRON)
    m.ell((cx, cy - 3.4, cz), (1.8, 0.7, 1.8), IRON)


INFO = {}  # what the JSON needs from this run: parts {at, frame}, spill boxes, spark points (printed at the end)


def fire_box(arr):
    cols = {tuple(c[:3]) for c in h.RAMPS[FIRE]}
    pts = [(x, y) for y in range(arr.shape[0]) for x in range(arr.shape[1]) if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in cols]
    if not pts:
        return None
    return (min(p[0] for p in pts), max(p[0] for p in pts), min(p[1] for p in pts), max(p[1] for p in pts))


def part(name, m, fw, fh, ground, glow=False, seed=1):
    """A separate picture hung on a piece (swaying in the wind): the model is rendered alone with the piece's camera and cropped to its pixels. Records its top-left `at` in the piece's frame."""
    arr = to_array(hut_lib.render(m, fw, fh, ground))
    ys, xs = np.nonzero(arr[..., 3])
    x0, y0 = int(xs.min()), int(ys.min())
    crop = grain(arr[y0:int(ys.max()) + 1, x0:int(xs.max()) + 1], seed, amount=0.4, mats=WOODISH)
    save(OUT / f"{name}.png", crop)
    if glow:
        g = glow_of(crop, LIT)
        if g[..., 3].any():
            save(OUT / f"{name}_glow.png", g)
    INFO[name] = {"at": [x0, y0], "frame": [crop.shape[1], crop.shape[0]]}
    return crop, (x0, y0)


def streamer(m, x, y_top, z, length, mat=None):
    """A pennant hanging from a short crossbar on a pole top: a narrow swallow-tailed strip of the town's teal with a gold stripe (the strip is its own picture, the pole stays in the piece)."""
    mat = BANNER if mat is None else mat
    slab(m, V(x + 0.1, y_top - 1.0, z + 0.6), V(x, y_top - length, z + 0.6), 2.3, 0.5, mat, (0, 0, 1), step=1.0)
    slab(m, V(x + 0.1, y_top - length * 0.42, z + 0.9), V(x + 0.1, y_top - length * 0.42 - 1.5, z + 0.9), 2.35, 0.4, STRAW, (0, 0, 1), step=0.9)
    m.ell(V(x - 1.2, y_top - length - 0.8, z + 0.6), (1.1, 1.5, 0.35), mat)  # the two tails
    m.ell(V(x + 1.3, y_top - length - 0.8, z + 0.6), (1.1, 1.5, 0.35), mat)


def side_banner(m, x, y_top, z, length, out=1, half=2.6, what="banner"):
    """The town's teal banner (gold stripe, swallow tail) hung at the SIDE of a roof: an iron bracket reaches out under the eave's end (`out` = +1 right, -1 left) and the banner
    hangs from a crossbar on it, beside the wall. The banner is its own picture (swaying), the bracket stays in the piece."""
    bx = x + out * 5.0
    if what == "bracket":  # stays in the piece
        m.limb(V(x - out * 1.5, y_top + 0.6, z), V(bx, y_top + 0.6, z), 0.5, 0.5, IRON)
        m.limb(V(x + out * 1.5, y_top - 2.2, z), V(bx - out * 0.3, y_top + 0.2, z), 0.4, 0.4, IRON)  # its brace
        m.ell(V(bx, y_top + 0.6, z), (0.9, 0.9, 0.9), IRON)
        return
    log(m, V(bx - half - 0.8, y_top - 0.4, z + 0.5), V(bx + half + 0.8, y_top - 0.4, z + 0.5), 0.45, IRON, step=0.8)  # the crossbar
    slab(m, V(bx, y_top - 0.8, z + 0.9), V(bx, y_top - length, z + 0.9), half, 0.5, BANNER, (0, 0, 1), step=1.0)
    slab(m, V(bx, y_top - length * 0.4, z + 1.2), V(bx, y_top - length * 0.4 - 1.6, z + 1.2), half + 0.05, 0.4, STRAW, (0, 0, 1), step=0.9)
    m.ell(V(bx - half * 0.5, y_top - length - 0.8, z + 0.9), (half * 0.55, 1.6, 0.35), BANNER)  # the two tails
    m.ell(V(bx + half * 0.5, y_top - length - 0.8, z + 0.9), (half * 0.55, 1.6, 0.35), BANNER)


def pole(m, x, y0, y1, z, bar=3.8):
    upright(m, x, z, y0, y1, 0.9, BARK, 0.9)
    log(m, V(x - bar, y1 - 0.8, z), V(x + bar, y1 - 0.8, z), 0.45, IRON, step=0.8)
    m.ell(V(x, y1 + 1.0, z), (1.1, 1.1, 1.1), IRON)


# ------------------------------------------------------------------ lamp post
def lamp_post():
    """Redone in tools/art_lamp.py (twisted post, cairn, curling arm, hanging cage lantern, animated unlit sheets); this only calls it."""
    import art_lamp  # noqa: E402
    art_lamp.make()
    from PIL import Image
    return np.array(Image.open(OUT / "lamp_post.png").convert("RGBA"))


# ------------------------------------------------------------------ fence
def fence():
    rng = rng_for(41)
    m = h.Model()
    z = -depth_units(6) / 2.0
    for sx in (-1, 1):
        x = sx * 11.0 + rng.uniform(-0.4, 0.4)
        lean = rng.uniform(-0.12, 0.12)
        log(m, V(x, 0, z), V(x + lean * 15, 15.0, z), 1.9, BARK, step=0.9, taper=0.85)
        m.ell(V(x + lean * 15, 15.7, z), (1.9, 0.9, 1.9), BARK_D)
        for k in range(3):
            m.ell(V(x + 3 * (-1) ** k, 0.9, z + 1.0), (1.4, 0.6, 1.0), MOSS_L if k % 2 else MOSS)
    for yy, sag in ((5.5, 0.6), (11.0, 0.9)):
        slab(m, V(-12.5, yy, z + 2.0), V(12.5, yy - sag, z + 2.0), 1.2, 0.75, PLANK_W if yy > 8 else PLANK, (0, 0, 1), step=1.3)
        for sx in (-1, 1):
            m.ell(V(sx * 11.0, yy, z + 2.9), (0.55, 0.55, 0.4), IRON)
    m.limb(V(-9.5, 5.5, z + 1.2), V(8.0, 11.0, z + 1.2), 0.8, 0.8, BARK_D, step=0.8)
    m.ell(V(rng.uniform(-6, 6), 12.3, z + 2.2), (1.6, 0.45, 0.9), MOSS)
    m.ell(V(-11.5, 17.2, z), (0.65, 0.65, 0.65), h.TEAL, kind="emit")
    arr = to_array(hut_lib.render(m, 32, 28, 24))
    return put("fence", finish(arr, 42, 24, 12, 1.6))


# ------------------------------------------------------------------ bench
def bench():
    rng = rng_for(51)
    m = h.Model()
    z = -depth_units(10) / 2.0
    for sx in (-1, 1):
        upright(m, sx * 12.5, z, 0, 8.6, 4.2, BARK, 0.93)
        for k in range(4):
            a = k / 4 * math.tau + 0.4
            m.limb(V(sx * 12.5 + math.cos(a) * 3.2, 2.5, z + math.sin(a) * 3.2), V(sx * 12.5 + math.cos(a) * 6.0, 0.5, z + math.sin(a) * 5.4), 1.3, 0.5, BARK)
        y.cap(m, V(sx * 12.5, 8.9, z), (0, 1, 0), 4.0, PLANK_W)
    slab(m, V(-17.5, 10.3, z), V(17.5, 10.1, z), 5.2, 1.3, PLANK_W, (0, 1, 0), step=1.3)
    slab(m, V(-17.0, 8.9, z + 4.8), V(17.0, 8.7, z + 4.8), 0.9, 0.9, BARK_D, (0, 0, 1), step=1.3)
    for _ in range(7):
        m.ell(V(rng.uniform(-16, 16), 11.7, z + rng.uniform(-3, 3)), (rng.uniform(1.2, 3.0), 0.4, 1.0), MOSS_L if rng.random() < 0.6 else MOSS)
    m.ell(V(-15.0, 6.0, z + 4.4), (1.3, 0.9, 0.9), h.TEAL, kind="emit")
    arr = to_array(hut_lib.render(m, 40, 32, 26))
    return put("bench", finish(arr, 52, 26, 17, 2.4))


# ------------------------------------------------------------------ path stone (a flat plate seen from above)
def path_stone():
    n = 16
    arr = np.zeros((n, n, 4), np.uint8)
    cols = [h.RAMPS[STONE_L][b][:3] for b in range(4)]
    dark = h.RAMPS[GAP][2][:3]
    moss = [h.RAMPS[MOSS][2][:3], h.RAMPS[MOSS_L][2][:3]]
    for y in range(n):
        for x in range(n):
            # a rounded, lopsided slab that fills the cell (so neighbours join into a path) with chipped, dithered corners
            dx, dy = (x + 0.5 - n / 2) / (n / 2), (y + 0.5 - n / 2) / (n / 2)
            edge = max(abs(dx), abs(dy)) ** 5 + (dx * dx + dy * dy) * 0.25
            wobble = (fbm(x * 0.5, y * 0.5, 7) - 0.5) * 0.45
            if edge + wobble > 1.05 - 0.06 * bayer(x, y):
                continue
            light = (-dx - dy) * 0.5 + (fbm(x * 0.35, y * 0.35, 11) - 0.5) * 0.9
            tone = 3 if light > 0.55 else 2 if light > 0.1 else 1 if light > -0.45 else 0
            arr[y, x] = (*cols[tone], 255)
            if hsh(x, y, 5) > 0.93:
                arr[y, x, :3] = cols[max(tone - 1, 0)]
            if edge + wobble > 0.82:  # the dark joint round the stone
                arr[y, x, :3] = dark
            elif hsh(x, y, 9) > 0.9 and fbm(x * 0.7, y * 0.7, 3) > 0.52:
                arr[y, x, :3] = moss[hsh(x, y, 4) > 0.5]
    for k in range(2):  # one crack
        cx = int(3 + hsh(k, 1, 77) * 8)
        for i in range(5):
            xx, yy = min(n - 1, cx + int(i * 0.8)), min(n - 1, 3 + i * 2 + k * 3)
            if arr[yy, xx, 3]:
                arr[yy, xx, :3] = dark
    return put("path_stone", arr, glow_mats=())


# ------------------------------------------------------------------ the ground under big pieces
def pad(name, foot_w, foot_h, seed):
    """Trodden earth with a few chips and tufts, dithered into the meadow at the edge. Drawn flat under the piece."""
    w, hh = int(foot_w) + 14, int(foot_h) + 12
    arr = np.zeros((hh, w, 4), np.uint8)
    earth = [hexc(c)[:3] for c in ("4a3a30", "6b5646", "8a7258", "a88c6a")]  # trodden dry earth, like the footpath's
    stone = h.RAMPS[STONE][2][:3]
    for y in range(hh):
        for x in range(w):
            dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - hh / 2) / (hh / 2)
            r = (abs(dx) ** 3.2 + abs(dy) ** 3.2) ** (1 / 3.2) + (fbm(x * 0.18, y * 0.22, seed) - 0.5) * 0.4
            if r > 1.0 - 0.1 * bayer(x, y):
                continue
            tone = 1 + (fbm(x * 0.3, y * 0.4, seed + 4) > 0.5) + (r < 0.6 and fbm(x * 0.5, y * 0.6, seed + 8) > 0.6)
            if r > 0.84:
                tone = 0 if bayer(x, y) < 0.5 else 1
            arr[y, x] = (*earth[min(tone, 3)], 255)
            if hsh(x, y, seed) > 0.985:
                arr[y, x, :3] = stone
    save(OUT / f"{name}_pad.png", arr)


# ------------------------------------------------------------------ stockpile
def stockpile():
    """An open timber store: a back wall, a roof over the back two thirds (so the goods stay visible), crates, barrels, sacks, firewood, a hanging lantern and sign."""
    rng = rng_for(61)
    m = h.Model()
    W = 35.0
    back, front = -depth_units(28) + 3.0, -2.0
    rf = back + 0.62 * (front - back)  # where the roof ends
    for zz in np.arange(back + 4, front - 1, 5.0):  # the floor
        slab(m, V(-W + 2, 0.9, zz), V(W - 2, 0.9, zz), 2.6, 0.8, PLANK if int(zz) % 2 else PLANK_W, (0, 1, 0), step=1.4)
    boards_vertical(m, rng, -W + 1, W - 1, 1, 34, back, PLANK, 2.2)
    for zz in np.arange(back + 4, rf - 2, 4.5):  # the left wall
        slab(m, V(-W + 1.2, 1, zz), V(-W + 1.2, 28, zz), 2.1, 0.9, PLANK_W if int(zz) % 2 else PLANK, (1, 0, 0), step=1.3)
    for x, z, ytop in ((-W + 2, back, 38), (W - 2, back, 38), (-W + 2, rf, 31), (W - 2, rf, 31)):
        upright(m, x, z, 0, ytop, 2.5, BARK, 0.92)
    beam_x(m, -W - 1, W + 1, 31.5, rf, 1.8, BARK)
    beam_x(m, -W - 1, W + 1, 38.5, back, 1.8, BARK)
    for sx in (-1, 1):
        log(m, V(sx * (W - 2), 38.5, back), V(sx * (W - 2), 31.5, rf), 1.5, BARK, step=1.1)
    cz = back + 14.0  # goods under the roof
    crate(m, (-24, 0.9, cz), (7.5, 5.5, 7.5), PLANK, rng)
    crate(m, (-24, 12.4, cz), (6.5, 4.6, 6.5), PLANK_W, rng)
    crate(m, (-9, 0.9, cz - 2), (6.0, 4.6, 6.0), PLANK_W, rng)
    barrel(m, (13, 0.9, cz - 3), 6.2, 13)
    barrel(m, (26, 0.9, cz + 2), 5.6, 12)
    barrel(m, (21, 0.9, cz - 8), 5.2, 11)
    for c in ((-2, 0.9, cz + 12), (6, 0.9, cz + 14)):
        sack(m, c, 4.4, LINEN if rng.random() < 0.6 else STRAW)
    sack(m, (2, 7.2, cz + 13), 3.8, STRAW)
    for row in range(3):  # split firewood stacked in the open front, at the right
        for k in range(4 - row):
            log(m, V(W - 22 + k * 6.6 + row * 3.3, 3.4 + row * 5.6, front - 4), V(W - 22 + k * 6.6 + row * 3.3, 3.4 + row * 5.6, front - 22), 3.1, BARK if (k + row) % 2 else BARK_D, step=1.1)
    for k in range(3):
        y.cap(m, V(W - 22 + k * 6.6, 3.4, front - 3.2), (0, 0, 1), 2.9, PLANK_W)
    crate(m, (-22, 0.9, front - 10), (6.0, 4.4, 6.0), PLANK, rng)  # one more outside, a lid half open
    side_banner(m, W + 8, 40.0, back - 5, 14.0, out=1, what="bracket")  # the banner's bracket at the roof peak, right end
    roof(m, rng, -W - 5, W + 5, (41.0, back - 5), (32.5, rf + 7), ROOF, 3.4, moss=0.12)
    for k in range(3):
        m.ell(V(-W + 4 + k * 18, 31.4, rf + 1.5), (0.9, 0.9, 0.9), h.TEAL, kind="emit")
    arr = to_array(hut_lib.render(m, 120, 80, 68))
    pad("stockpile", 64, 28, 3)
    # the parts that swing in the wind: the lantern (with its glow), the sign, the pennant
    lm = h.Model()
    lantern(lm, (-W + 14, 30.0, rf - 1), hang=2.2)
    lantern_arr, (lx, ly) = part("stockpile_lantern", lm, 120, 80, 68, glow=True, seed=3)
    sm = h.Model()
    log(sm, V(10.0, 30.5, rf - 0.5), V(10.0, 26.0, rf - 0.5), 0.3, IRON, step=0.6)  # the sign
    slab(sm, V(2.5, 24.0, rf - 0.3), V(17.5, 24.0, rf - 0.3), 3.2, 0.7, PLANK_W, (0, 0, 1), step=1.2)
    for k in range(4):
        sm.ell(V(5 + k * 3.2, 24.0, rf + 0.5), (0.8, 1.6 - 0.3 * (k % 2), 0.3), BARK_D)
    part("stockpile_sign", sm, 120, 80, 68, seed=4)
    pm = h.Model()
    side_banner(pm, W + 8, 40.0, back - 5, 14.0, out=1)
    part("stockpile_pennant", pm, 120, 80, 68, seed=5)
    # the lantern's light on the floor under the roof (an additive picture, breathing with the light)
    fb = fire_box(lantern_arr)
    box = (fb[0] + lx, fb[1] + lx, fb[2] + ly, fb[3] + ly)
    floor_y = 68 + (rf - 1) / UNITS_PER_PX
    save(OUT / "stockpile_spill.png", hut_lib.pool_spill(120, 80, box, [((box[0] + box[1]) / 2, floor_y + 1, 17, 6, 0.95), ((box[0] + box[1]) / 2 + 6, floor_y + 2, 30, 9, 0.4)], reach=6, seed=7, bloom=0.4))
    wear_stockpile(W, rng_for(64))
    return put("stockpile", finish(roof_pass(arr, 62, moss=0.16, shadow=7), 62, 68, 40, 6))


# ------------------------------------------------------------------ workshop
def workshop():
    """Roofed bench area at the back, the open front with an anvil, a grindstone and the forge (a stone hearth with a glowing mouth and a chimney) at the right."""
    rng = rng_for(71)
    m = h.Model()
    W = 52.0
    back, front = -depth_units(40) + 3.0, -3.0
    rf = back + 0.58 * (front - back)
    for zz in np.arange(back + 4, front - 1, 5.0):
        slab(m, V(-W + 2, 0.9, zz), V(W - 2, 0.9, zz), 2.6, 0.8, PLANK if int(zz) % 2 else PLANK_W, (0, 1, 0), step=1.4)
    boards_vertical(m, rng, -W + 1, W - 1, 1, 44, back, PLANK, 2.3)
    for zz in np.arange(back + 4, rf - 2, 4.5):
        slab(m, V(-W + 1.2, 1, zz), V(-W + 1.2, 36, zz), 2.1, 0.9, PLANK_W if int(zz) % 2 else PLANK, (1, 0, 0), step=1.3)
    for x, z, ytop in ((-W + 2, back, 52), (W - 2, back, 52), (-W + 2, rf, 43), (W - 2, rf, 43)):
        upright(m, x, z, 0, ytop, 2.7, BARK, 0.92)
    beam_x(m, -W - 2, W + 2, 43.5, rf, 1.9, BARK)
    beam_x(m, -W - 2, W + 2, 52.5, back, 1.9, BARK)
    for sx in (-W + 2, W - 2):
        log(m, V(sx, 52.5, back), V(sx, 43.5, rf), 1.6, BARK, step=1.1)
    # the workbench along the back wall, with a vise, a plank in the making, tools
    bz = back + 11.0
    slab(m, V(-W + 8, 15.0, bz), V(W - 8, 15.0, bz), 8.2, 1.7, PLANK_W, (0, 1, 0), step=1.4)
    for lx in (-W + 11, 0.0, W - 11):
        for lz in (bz - 5.0, bz + 5.0):
            upright(m, lx, lz, 0, 14.5, 1.7, BARK, 0.95)
    slab(m, V(-W + 9, 8.2, bz + 5.2), V(W - 9, 8.2, bz + 5.2), 0.9, 0.9, BARK_D, (0, 0, 1), step=1.4)
    slab(m, V(-36, 16.8, bz + 1), V(-12, 17.0, bz - 1), 3.2, 0.7, PLANK, (0, 1, 0), step=1.2)
    m.ell(V(-4.0, 17.8, bz + 3.0), (2.6, 2.6, 2.2), IRON)  # the vise
    m.ell(V(-4.0, 20.5, bz + 3.0), (1.0, 2.2, 1.0), IRON)
    log(m, V(10, 16.9, bz + 3), V(22, 16.9, bz + 2), 0.9, BARK_D, step=0.8)  # a hammer
    m.ell(V(23.5, 17.2, bz + 2), (2.6, 2.0, 1.6), IRON)
    m.ell(V(-26.0, 17.4, bz - 3.0), (3.0, 0.8, 1.8), STRAW)  # shavings
    for k, tx in enumerate((-40, -30, -20, -8, 4, 16, 28)):  # the wall behind it: hanging tools, a saw, coils of rope
        m.limb(V(tx, 26.0, back + 1.5), V(tx, 38.0 - 3.0 * (k % 2), back + 1.5), 0.45, 0.45, IRON)
        m.ell(V(tx, 24.8, back + 1.5), (1.8, 2.3, 0.8), IRON if k % 2 else STONE_L)
    slab(m, V(36, 36.0, back + 1.5), V(46, 36.0, back + 1.5), 4.4, 0.4, IRON, (0, 0, 1), step=1.2)
    for r_ in range(3):
        m.ell(V(-46, 22.0 + r_ * 1.8, back + 3.0), (4.2 - r_ * 0.4, 0.9, 3.6 - r_ * 0.3), STRAW)
    # in the open front: a plank on two trestles, the grindstone, the anvil and the forge
    for tx in (-W + 8, -W + 26):
        slab(m, V(tx, 0.5, front - 16), V(tx + 2, 11.0, front - 16), 1.2, 0.9, BARK, (1, 0, 0), step=1.1)
        slab(m, V(tx, 0.5, front - 24), V(tx + 2, 11.0, front - 24), 1.2, 0.9, BARK, (1, 0, 0), step=1.1)
    slab(m, V(-W + 3, 11.6, front - 20), V(-W + 31, 11.8, front - 20), 3.0, 1.0, PLANK, (0, 1, 0), step=1.2)
    gx_ = -W + 40
    for sx in (-1, 1):
        slab(m, V(gx_ + sx * 5.6, 0.5, front - 22), V(gx_ + sx * 5.6, 12.0, front - 22), 1.3, 0.9, BARK, (1, 0, 0), step=1.1)
    m.ell(V(gx_, 11.0, front - 22), (1.0, 6.2, 6.2), STONE_L, R=h.rot_y(math.pi / 2))
    m.ell(V(gx_ - 1.1, 11.0, front - 22), (1.2, 5.6, 5.6), STONE, R=h.rot_y(math.pi / 2))
    ax = W - 33.0
    upright(m, ax, front - 16, 0, 9.0, 5.6, BARK, 0.95)
    y.cap(m, V(ax, 9.4, front - 16), (0, 1, 0), 5.4, PLANK_W)
    m.ell(V(ax, 12.0, front - 16), (7.5, 2.0, 3.0), IRON)
    m.ell(V(ax, 14.3, front - 16), (8.4, 1.6, 3.4), IRON)
    m.ell(V(ax + 9.0, 14.2, front - 16), (3.0, 1.0, 1.6), IRON)
    m.ell(V(ax - 9.0, 14.0, front - 16), (2.2, 1.0, 2.0), IRON)
    fx0, fx1 = W - 24.0, W - 4.0
    fz0, fz1 = front - 36.0, front - 8.0  # the hearth block (back, front)
    for gy in range(0, 4):
        for gx in range(0, 4):
            bx = fx0 + (gx + 0.5) * (fx1 - fx0) / 4.0 + ((gy % 2) - 0.5) * 2.2
            for gz in (fz0 + 5.0, fz1 - 5.0):
                m.ell(V(bx, 2.8 + gy * 5.2, gz), (rng.uniform(3.6, 4.6), rng.uniform(2.4, 2.9), rng.uniform(4.4, 5.6)), (STONE, STONE_L, STONE, STONE_L)[(gx + gy) % 4])
    fmx = (fx0 + fx1) / 2.0
    m.ell(V(fmx, 7.5, fz1 - 1.0), (9.0, 5.2, 3.2), GAP)  # the mouth, the fire inside it
    m.ell(V(fmx, 6.6, fz1 - 0.2), (6.6, 3.4, 2.4), FIRE, kind="emit")
    m.ell(V(fmx, 5.6, fz1 + 0.4), (4.0, 1.9, 1.6), FIRE, kind="emit")
    m.ell(V(fmx, 22.0, (fz0 + fz1) / 2), (11.6, 3.0, 15.0), STONE_L)  # the top of the hearth and the hood
    m.ell(V(fmx, 25.5, fz0 + 6.0), (8.5, 3.6, 6.5), STONE)
    for k in range(5):  # the chimney
        m.ell(V(fmx, 28.0 + k * 6.0, fz0 + 5.0), (5.8 - k * 0.4, 3.2, 5.0 - k * 0.3), STONE if k % 2 else STONE_L)
    for gx in (-1, 1):
        m.ell(V(fmx + gx * 5.0, 56.0, fz0 + 5.0), (1.4, 1.6, 4.2), STONE)
    for k in range(3):
        m.ell(V(fx0 + 3 + k * 7.0, 1.6, fz1 + 2.0), (3.0, 1.2, 2.0), STONE_L)  # stones at its foot
    side_banner(m, -W - 9, 53.0, back - 6, 17.0, out=-1, half=3.0, what="bracket")  # the banner's bracket at the roof peak, left end
    roof(m, rng, -W - 6, W + 6, (54.0, back - 6), (43.0, rf + 8), ROOF, 3.5, moss=0.12)
    for k in range(3):
        m.ell(V(-W + 6 + k * 16, 42.0, rf + 1.0), (0.9, 0.9, 0.9), h.TEAL, kind="emit")
    arr = to_array(hut_lib.render(m, 144, 112, 98))
    pad("workshop", 96, 40, 5)
    lm = h.Model()
    lantern(lm, (-W + 16, 41.0, rf - 1), hang=2.4)
    lantern_arr, (lx, ly) = part("workshop_lantern", lm, 144, 112, 98, glow=True, seed=6)
    pm = h.Model()
    side_banner(pm, -W - 9, 53.0, back - 6, 17.0, out=-1, half=3.0)
    part("workshop_pennant", pm, 144, 112, 98, seed=8)
    mouth = fire_box(arr)  # the forge's mouth: its light spills on the floor in front of the hearth, the lantern's under the roof
    mx = (mouth[0] + mouth[1]) / 2.0
    my = (mouth[2] + mouth[3]) / 2.0
    fb = fire_box(lantern_arr)
    lbox = (fb[0] + lx, fb[1] + lx, fb[2] + ly, fb[3] + ly)
    lamp_floor = 98 + (rf - 1) / UNITS_PER_PX
    forge = hut_lib.pool_spill(144, 112, mouth, [(mx, 98 + (front - 8) / UNITS_PER_PX + 7, 24, 8, 1.0), (mx - 8, 98 + (front - 8) / UNITS_PER_PX + 9, 40, 13, 0.45)], reach=10, color=(255, 120, 40), seed=9, bloom=0.8)
    lamp = hut_lib.pool_spill(144, 112, lbox, [((lbox[0] + lbox[1]) / 2, lamp_floor + 1, 17, 6, 0.8)], reach=6, seed=10, bloom=0.4)
    save(OUT / "workshop_spill.png", np.maximum(forge, lamp))
    INFO["workshop_forge"] = {"at": [round(mx - 72, 1), round(my - 98 - 1, 1)]}
    wear_workshop(W, rng_for(74), front, back, fmx=(W - 24.0 + W - 4.0) / 2.0, fz1=front - 8.0)
    return put("workshop", finish(roof_pass(arr, 72, moss=0.14, shadow=8), 72, 98, 52, 8))


# ------------------------------------------------------------------ wear: what a building collects the longer it stands (each its own overlay picture, data `wear` {texture, days})
def _wear(name, m, fw, fh, ground, seed):
    arr = to_array(hut_lib.render(m, fw, fh, ground))
    save(OUT / f"{name}.png", grain(arr, seed, amount=0.5, mats=WOODISH))


def wear_stockpile(W, rng):
    front = -2.0
    m = h.Model()  # day 0: the splitting block with its wedge, split logs and chips, where the carpenter keeps kindling ready
    bx, bz = 50.0, front - 8.0
    upright(m, bx, bz, 0.9, 9.0, 5.0, BARK, 0.96)
    y.cap(m, V(bx, 9.4, bz), (0, 1, 0), 4.8, PLANK_W)
    for k in range(5):
        a = k / 5 * math.tau
        m.ell(V(bx + math.cos(a) * 3.2, 9.7, bz + math.sin(a) * 2.2), (0.5, 0.35, 0.5), BARK_D)  # the rings' cracks
    m.ell(V(bx + 0.5, 10.8, bz), (1.1, 1.8, 0.8), IRON)  # the wedge in a half split log
    log(m, V(bx - 2, 12.0, bz + 1), V(bx + 2.5, 12.0, bz - 1), 1.9, BARK, step=1.0)
    log(m, V(bx + 8, 1.8, bz + 4), V(bx + 16, 1.8, bz + 6), 2.4, BARK_D, step=1.0)  # split halves on the ground
    log(m, V(bx - 11, 1.8, bz + 6), V(bx - 5, 1.8, bz + 12), 2.2, BARK, step=1.0)
    log(m, V(bx + 4, 1.8, bz + 10), V(bx + 10, 1.8, bz + 9), 2.0, BARK, step=1.0)
    for _ in range(22):  # chips
        m.ell(V(bx + rng.uniform(-13, 14), 1.2, bz + rng.uniform(-6, 13)), (rng.uniform(0.7, 1.5), 0.35, rng.uniform(0.5, 0.9)), PLANK if rng.random() < 0.6 else STRAW)
    _wear("stockpile_wear_a", m, 120, 80, 68, 11)
    m = h.Model()  # day 2: more crates and a sack by the left corner
    crate(m, (-47, 0.9, front - 18), (6.4, 4.8, 6.4), PLANK, rng)
    crate(m, (-47, 10.8, front - 18), (5.2, 4.0, 5.2), PLANK_W, rng)
    crate(m, (-47, 0.9, front - 7), (5.6, 4.4, 5.6), PLANK_W, rng)
    sack(m, (-40, 0.9, front - 11), 4.2, STRAW)
    _wear("stockpile_wear_b", m, 120, 80, 68, 12)
    m = h.Model()  # day 4: a neat stack of split firewood behind the block
    for row in range(3):
        for k in range(3 - row):
            xx = bx - 8 + k * 6.2 + row * 3.1
            log(m, V(xx, 3.2 + row * 5.4, bz - 14), V(xx, 3.2 + row * 5.4, bz - 30), 3.0, BARK if (k + row) % 2 else BARK_D, step=1.1)
    for k in range(3):
        y.cap(m, V(bx - 8 + k * 6.2, 3.2, bz - 13.2), (0, 0, 1), 2.8, PLANK_W)
    _wear("stockpile_wear_c", m, 120, 80, 68, 13)


def wear_workshop(W, rng, front, back, fmx, fz1):
    bz = back + 11.0
    m = h.Model()  # day 1: shavings and offcuts under the bench and round the trestles
    for _ in range(26):
        px = rng.uniform(-W + 6, W - 30)
        pz = rng.uniform(bz + 5, front - 8)
        m.ell(V(px, 1.1, pz), (rng.uniform(1.0, 2.2), 0.3, rng.uniform(0.6, 1.2)), PLANK if rng.random() < 0.6 else (STRAW if rng.random() < 0.5 else PLANK_W))
    for k in range(4):
        slab(m, V(-W + 18 + k * 9, 1.6, bz + 8 + (k % 2) * 6), V(-W + 22 + k * 9, 1.6, bz + 10 + (k % 2) * 6), 1.3, 0.5, PLANK, (0, 1, 0), step=0.9)
    _wear("workshop_wear_a", m, 144, 112, 98, 21)
    m = h.Model()  # day 3: a stack of boards drying beside the left wall, laid on stickers
    for layer in range(5):
        for k in range(3 if layer < 4 else 2):
            xx = -W - 14 + k * 5.6 + (layer % 2) * 1.2
            slab(m, V(xx, 2.4 + layer * 2.1, front - 34), V(xx, 2.4 + layer * 2.1, front - 8), 2.6, 0.9, PLANK_W if (k + layer) % 3 == 0 else PLANK, (0, 1, 0), step=1.3)
    for zz in (front - 32, front - 21, front - 10):
        slab(m, V(-W - 18, 1.2, zz), V(-W - 0.5, 1.2, zz), 0.8, 0.8, BARK_D, (0, 1, 0), step=1.0)
    _wear("workshop_wear_b", m, 144, 112, 98, 22)
    m = h.Model()  # day 6: soot on the floor before the forge, a bucket of coal and a few lumps
    m.ell(V(fmx, 0.95, fz1 + 5), (15, 0.35, 8), SOIL)
    m.ell(V(fmx - 12, 0.95, fz1 + 12), (8, 0.3, 4), SOIL)
    log(m, V(fmx - 17, 0.9, fz1 + 9), V(fmx - 17, 6.8, fz1 + 9), 3.4, IRON, step=0.9)
    m.ell(V(fmx - 17, 6.9, fz1 + 9), (3.0, 0.7, 3.0), GAP)
    for _ in range(5):
        m.ell(V(fmx - 17 + rng.uniform(-2, 2), 7.1, fz1 + 9 + rng.uniform(-2, 2)), (0.9, 0.7, 0.9), IRON)
    for _ in range(6):
        m.ell(V(fmx + rng.uniform(-15, 4), 1.2, fz1 + rng.uniform(5, 14)), (0.9, 0.6, 0.8), IRON)
    _wear("workshop_wear_c", m, 144, 112, 98, 23)


# ------------------------------------------------------------------ item icons (16 x 16, outline 1b1a2e, lit from the top left)
OUTLINE = hexc("1b1a2e")


def icon(name, painter):
    n = 16
    grid = {}
    painter(grid)
    arr = np.zeros((n, n, 4), np.uint8)
    for (x, y), c in grid.items():
        arr[y, x] = (*c[:3], 255)
    out = arr.copy()
    for y in range(n):  # an ink outline round the subject
        for x in range(n):
            if arr[y, x, 3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < n and 0 <= yy < n and arr[yy, xx, 3]:
                    out[y, x] = (*OUTLINE[:3], 255)
    save(ICONS / f"{name}.png", out)


def plank_icon(grid):
    wood = [h.RAMPS[PLANK_W][b][:3] for b in range(4)]
    for k, (y0, shift) in enumerate(((10, 0), (6, 1), (3, 2))):  # three boards, 45 degrees, bottom left to top right
        for i in range(11):
            x, y = 2 + i + shift, y0 + 3 - i // 2 * 1
            for t in range(3):
                yy = y - i // 3 + t
                xx = x
                tone = 3 if t == 0 else 2 if t == 1 else 1
                if 0 <= xx < 15 and 0 <= yy < 15:
                    grid[(xx, yy)] = wood[tone] if (i + k) % 5 else wood[max(tone - 1, 0)]


def rope_icon(grid):
    rope = [h.RAMPS[STRAW][b][:3] for b in range(4)]
    cx, cy = 7.5, 8.0
    for y in range(16):
        for x in range(16):
            d = math.hypot((x - cx) / 6.2, (y - cy) / 5.2)
            if 0.45 < d < 1.0:
                light = (-(x - cx) - (y - cy)) / 9.0
                tone = 3 if light > 0.45 else 2 if light > 0.0 else 1 if light > -0.5 else 0
                if int(math.atan2(y - cy, x - cx) * 4 + d * 6) % 3 == 0:
                    tone = max(tone - 1, 0)
                grid[(x, y)] = rope[tone]
    for x, y in ((12, 3), (13, 2), (13, 3), (14, 4)):  # the loose end
        grid[(x, y)] = rope[2]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    hut_lib.set_fresh()  # the renewed hut's warmer plum-violet wood: the town is new work next to it
    pieces = {"lamp_post": lamp_post, "fence": fence, "bench": bench, "path_stone": path_stone, "stockpile": stockpile, "workshop": workshop}
    only = [a for a in sys.argv[1:] if a in pieces]
    arrays = {}
    for name, fn in pieces.items():
        if only and name not in only:
            continue
        arrays[name] = fn()
        print("written", name, arrays[name].shape)
    if not only:
        icon("plank", plank_icon)
        icon("rope", rope_icon)
    print("INFO", json.dumps(INFO))
    return arrays


def contact(arrays, path, scale=6):
    from PIL import Image
    bg = (58, 110, 70, 255)
    tiles = []
    for name, arr in arrays.items():
        img = Image.new("RGBA", (arr.shape[1], arr.shape[0]), bg)
        img.alpha_composite(Image.fromarray(arr))
        tiles.append(img)
    W = sum(t.width for t in tiles) + 6 * (len(tiles) + 1)
    H = max(t.height for t in tiles) + 12
    sheet = Image.new("RGBA", (W, H), bg)
    x = 6
    for t in tiles:
        sheet.paste(t, (x, H - t.height - 6))
        x += t.width + 6
    sheet = sheet.resize((W * scale, H * scale), Image.NEAREST)
    sheet.save(path)


if __name__ == "__main__":
    import hut_yard as y  # noqa: E402  (cap helper; its extra ramps are appended after ours)
    result = main()
    out_png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if out_png and result:
        contact(result, out_png[0])
