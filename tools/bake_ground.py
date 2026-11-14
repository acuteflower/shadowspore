#!/usr/bin/env python3
"""Bakes the hand-authored ground decals of the world into pictures (needs numpy). Reads data/ground.json:
  stone_fields  patches of old flagstone floor, overgrown and random: a list of rectangles (px, relative to the start tile's
                centre) that are warped into an organic outline, thinned out by noise, with grass breaking through
  paths         THE footpath of this world, drawn along a list of points (px, relative to the start tile's centre): a narrow
                trodden strip of light dirt that wobbles in width, has a faint wear line on each side, pebbles, tufts of grass
                and ragged edges that melt into the meadow; it tapers away at both ends
Writes assets/world/ground/<id>.png and <id>_mask.png (R: 60 stone, 80 path, 0 none) and data/ground_baked.json (where each
decal goes, world px of its top left corner). The game (`GroundDecal`, `WorldLevel._add_ground_decals`) lays them on the ground
and reads the surface (stone, path) from the mask. To add a path or a field: edit data/ground.json and run this again, then
`Godot --headless --path . --import`. Usage: python3 tools/bake_ground.py [preview.png]"""
import json
import math
import os
import pathlib
import random
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BUSH, MEADOW  # noqa: E402
from art_mushroom import MOSS  # noqa: E402
from art_stone import STONE  # noqa: E402
from gen_art import hexc, noise, write_png  # noqa: E402
from world_data import load_png  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
MORTAR = hexc("14112a")
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
CELL = 13  # size of a flagstone
PATH = [hexc(c) for c in ("55465a", "75666a", "958776", "b3a58a", "cfc2a2", "e4d8ba")]  # packed dry earth, violet in the shade
STONE_CODE, PATH_CODE = 60, 80
ARENA_GLOW = {}  # arena id -> glow picture (only the inlaid light of the floor), filled by bake_arena


def clampi(v, lo, hi):
    return max(lo, min(hi, v))


def vnoise(w, h, scale, seed):
    """Smooth value noise 0..1, one random value per `scale` px, bilinear in between."""
    rng = np.random.default_rng(seed)
    gw, gh = w // scale + 3, h // scale + 3
    grid = rng.random((gh, gw))
    ys = np.arange(h) / scale
    xs = np.arange(w) / scale
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = grid[np.ix_(y0, x0)]
    b = grid[np.ix_(y0, x0 + 1)]
    c = grid[np.ix_(y0 + 1, x0)]
    d = grid[np.ix_(y0 + 1, x0 + 1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def vnoise_at(ox, oy, w, h, scale, seed):
    """Like vnoise, but anchored in the world: the lattice is hashed from absolute coordinates (ox, oy = the image's top left), so two
    pictures that share an edge see the same noise there (the pieces of a long road, `arc` in bake_path)."""
    xs = (np.arange(w) + ox) / scale
    ys = (np.arange(h) + oy) / scale
    gx, gy = np.floor(xs).astype(np.int64), np.floor(ys).astype(np.int64)
    fx, fy = xs - gx, ys - gy
    fx, fy = (fx * fx * (3 - 2 * fx))[None, :], (fy * fy * (3 - 2 * fy))[:, None]

    def lat(ix, iy):
        v = (ix[None, :] * 374761393 + iy[:, None] * 668265263 + (seed * 2246822519) % 4294967296) & 0xFFFFFFFF
        v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0

    a, b, c, d = lat(gx, gy), lat(gx + 1, gy), lat(gx, gy + 1), lat(gx + 1, gy + 1)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def tuft(img, x, y, h, rng, palette):
    for k in range(rng.randrange(3, 6)):
        lean = rng.choice((-2, -1, 0, 1, 2))
        for j in range(h - rng.randrange(0, 3)):
            xx, yy = x + int(lean * j / h * 2) + k - 2, y - j
            if 0 <= yy < img.shape[0] and 0 <= xx < img.shape[1]:
                img[yy, xx] = palette[clampi(2 + j * 3 // max(h, 1) + (lean < 0), 1, 5)]


def cell_of(x, y):
    """Voronoi cell of the flagstone pattern: (id, distance to the nearest centre, to the second, centre)."""
    gx, gy = x // CELL, y // CELL
    best, second, bid, bc = 1e9, 1e9, 0, (0.0, 0.0)
    for j in range(-1, 2):
        for i in range(-1, 2):
            cx = (gx + i) * CELL + CELL / 2.0 + (noise(gx + i, gy + j, 41) / 255.0 - 0.5) * CELL * 0.7
            cy = (gy + j) * CELL + CELL / 2.0 + (noise(gx + i, gy + j, 42) / 255.0 - 0.5) * CELL * 0.7
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 1.15)
            if d < best:
                second, best, bid, bc = best, d, (gx + i) * 997 + (gy + j), (cx, cy)
            elif d < second:
                second = d
    return bid, best, second, bc


def flagstone(x, y, seed):
    sx, sy = x + seed * 5, y + seed * 3  # the pattern is shifted by the seed (all of its maths in the shifted frame)
    cid, d1, d2, (ccx, ccy) = cell_of(sx, sy)
    tone = 1 + int(noise(cid, 7, 43) / 110) + (1 if noise(cid, 8, 44) > 200 else 0)
    if d2 - d1 < 1.3:  # a joint
        c = MORTAR if noise(x, y, 45) > 60 else STONE[0]
        if noise(x, y, 46) > 236:
            c = MOSS[noise(x, y, 47) // 128]
        return c
    lit = -0.45 * ((sx + 0.5 - ccx) + (sy + 0.5 - ccy)) / (CELL * 0.6)
    val = tone + 0.6 + lit + (noise(x, y, 48) / 255.0 - 0.5) * 0.7 + (BAYER[y % 4][x % 4] - 0.5) * 0.4
    c = STONE[clampi(int(val), 1, 4)]
    if d2 - d1 < 2.8 and (sx + 0.5 - ccx) + (sy + 0.5 - ccy) < 0:  # a lit upper-left rim on each stone
        c = STONE[clampi(tone + 1, 2, 4)]
    if noise(cid, 9, 49) > 240 and noise(x, y, 52) > 110:  # a sunken stone, mossy in patches
        c = MOSS[clampi(int(val) - 1, 0, 2)]
    return c


# ------------------------------------------------------------------ height levels
_RELIEF = None


def relief_zone(x0, y0, w, h, centre):
    """Per pixel (world px = centre + offset) 0..1: how much the ground belongs to a plateau or its wall (the wall hangs 32 px below
    every contour, so the zone reaches 3 tiles south of anything above level 0, and a tile to each side). Flat ground has 0.
    Decals are cut by it, so nothing of the hand-made ground runs up onto a cliff."""
    global _RELIEF
    if _RELIEF is None:
        _RELIEF = load_png(str(ROOT / "assets" / "world" / "relief.png"))[:, :, 0] > 0
    high = _RELIEF
    zone = high.copy()
    for k in (1, 2, 3):  # the wall below a contour
        zone[k:, :] |= high[:-k, :]
    zone[:, 1:] |= zone[:, :-1].copy()
    zone[:, :-1] |= zone[:, 1:].copy()
    wx = (np.arange(w) + x0 + centre[0]) // 16
    wy = (np.arange(h) + y0 + centre[1]) // 16
    wx = np.clip(wx, 0, zone.shape[1] - 1).astype(int)
    wy = np.clip(wy, 0, zone.shape[0] - 1).astype(int)
    blocks = zone[np.ix_(wy, wx)].astype(float)
    k = 7  # soften the 16 px steps (box blur) so the border can be dithered
    pad = np.pad(blocks, k, mode="edge")
    c = np.cumsum(np.cumsum(pad, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    size = 2 * k + 1
    blur = (c[size:, size:] - c[:-size, size:] - c[size:, :-size] + c[:-size, :-size]) / float(size * size)
    return blur


# ------------------------------------------------------------------ stone fields
def bake_stone_field(spec, seed, centre):
    rects = spec["rects"]
    pad = 28
    x0, y0 = int(min(r[0] for r in rects)) - pad, int(min(r[1] for r in rects)) - pad
    x1, y1 = int(max(r[2] for r in rects)) + pad, int(max(r[3] for r in rects)) + pad
    w, h = x1 - x0, y1 - y0
    X = np.arange(w)[None, :] + x0 + 0.5
    Y = np.arange(h)[:, None] + y0 + 0.5
    warp_x = (vnoise(w, h, 16, seed + 1) - 0.5) * 22 + (vnoise(w, h, 6, seed + 2) - 0.5) * 7
    warp_y = (vnoise(w, h, 16, seed + 3) - 0.5) * 22 + (vnoise(w, h, 6, seed + 4) - 0.5) * 7
    Xw, Yw = X + warp_x, Y + warp_y
    sd = np.full((h, w), 1e9)
    for (ax, ay, bx, by) in rects:  # union of rounded boxes
        cx, cy, hw, hh = (ax + bx) / 2.0, (ay + by) / 2.0, (bx - ax) / 2.0, (by - ay) / 2.0
        r = min(18.0, hw, hh)
        dx, dy = np.abs(Xw - cx) - hw + r, np.abs(Yw - cy) - hh + r
        d = np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0) - r
        sd = np.minimum(sd, d)
    density = 0.62 + 0.55 * vnoise(w, h, 44, seed + 5)  # some places are sparser than others
    holes = 0.62 * vnoise(w, h, 26, seed + 6) + 0.38 * vnoise(w, h, 9, seed + 9)  # grass takes whole patches back
    pits = vnoise(w, h, 6, seed + 7)
    jitter = (vnoise(w, h, 3, seed + 8) - 0.5) * 0.3
    bayer = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    edge = np.clip((12.0 - sd) / 16.0, 0.0, 1.0)  # 1 well inside, fading to 0 beyond the border
    keep = (edge * density + jitter) > (bayer * 0.9 + 0.05)
    keep &= ~((holes > 0.72 + (bayer - 0.5) * 0.1))
    keep &= ~(relief_zone(x0, y0, w, h, centre) > 0.42 + (bayer - 0.5) * 0.5)  # nothing runs up onto a cliff
    keep &= ~((pits > 0.84) & (bayer > 0.2))
    import arena_design  # the carved sun sigil, the ley lines to the pillars, the frieze (tools/arena_design.py)
    paint, glow, solid = arena_design.design(spec, X, Y, sd, seed)
    keep |= solid & top  # no hole of grass in the sigil or under a pillar
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    ys, xs = np.nonzero(keep)
    for y, x in zip(ys, xs):
        img[y, x] = flagstone(int(x + x0), int(y + y0), seed)
        mask[y, x] = (STONE_CODE, 0, 0, 255)
    rng = random.Random(seed)
    for _ in range(int(w * h / 90)):  # grass and moss creep in through the joints
        x, y = rng.randrange(0, w), rng.randrange(1, h)
        if keep[y, x]:
            c = MOSS[1 + rng.randrange(3)] if rng.random() < 0.7 else BUSH[3]
            img[y, x] = c
            if rng.random() < 0.5:
                img[y - 1, x] = c
    for _ in range(int(w * h / 1500)):  # tufts at the ragged edges
        x, y = rng.randrange(4, w - 4), rng.randrange(8, h - 2)
        if keep[y, x] and sd[y, x] > -14:
            tuft(img, x, y, rng.randrange(3, 6), rng, MEADOW)
    for _ in range(int(w * h / 700)):  # loose pebbles and chips just outside
        x, y = rng.randrange(2, w - 2), rng.randrange(2, h - 2)
        if not keep[y, x] and -6 < sd[y, x] < 14 and img[y, x, 3] == 0:
            img[y, x] = STONE[2 + rng.randrange(2)]
            mask[y, x] = (STONE_CODE, 0, 0, 255)
            if rng.random() < 0.4:
                img[y, x + 1] = STONE[1]
    return img, mask, (x0, y0)


# ------------------------------------------------------------------ arenas (stone floor on a plateau, drawn as a polygon)
_FIELDS = {}


def relief_field(channel, px, py):
    """Smooth relief field (0..1, channel 0/1/2 = level >= 1/2/3) at world px arrays (bilinear, the way the game reads it)."""
    if "f" not in _FIELDS:
        from PIL import Image
        _FIELDS["f"] = np.array(Image.open(ROOT / "assets" / "world" / "relief_field.png").convert("RGB"))
    f = _FIELDS["f"][:, :, channel] / 255.0
    u, v = px / 16.0 - 0.5, py / 16.0 - 0.5
    x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fx, fy = u - x0, v - y0
    def g(x, y):
        return f[np.clip(y, 0, f.shape[0] - 1), np.clip(x, 0, f.shape[1] - 1)]
    return (g(x0, y0) * (1 - fx) + g(x0 + 1, y0) * fx) * (1 - fy) + (g(x0, y0 + 1) * (1 - fx) + g(x0 + 1, y0 + 1) * fx) * fy


def _grow(mask, n):
    out = mask.copy()
    for i in range(n):
        nxt = out.copy()
        nxt[1:, :] |= out[:-1, :]
        nxt[:-1, :] |= out[1:, :]
        nxt[:, 1:] |= out[:, :-1]
        nxt[:, :-1] |= out[:, 1:]
        if i % 2:
            nxt[1:, 1:] |= out[:-1, :-1]
            nxt[:-1, :-1] |= out[1:, 1:]
            nxt[1:, :-1] |= out[:-1, 1:]
            nxt[:-1, 1:] |= out[1:, :-1]
        out = nxt
    return out


def _signed_distance(inside, reach):
    """Roughly the distance (px) to the border of `inside`: negative inside, positive outside, clipped to +-reach."""
    sd = np.zeros(inside.shape)
    cur = inside.copy()
    for k in range(reach):  # outside: how many growth steps until a pixel is reached
        nxt = _grow(cur, 1)
        sd[nxt & ~cur] = k + 1
        cur = nxt
    sd[~cur] = reach
    cur = ~inside
    for k in range(reach):
        nxt = _grow(cur, 1)
        sd[nxt & ~cur & inside] = -(k + 1)
        cur = nxt
    sd[inside & ~cur] = -reach
    return sd


def bake_arena(spec, seed):
    """An old flagstone floor in the shape of a hand-drawn polygon (px relative to the arena tile's centre), laid on a plateau:
    like the field around the manhole (broken plates, grass and moss breaking through, ragged edges) but only where the smooth
    relief field says the plateau top is (`level` = 3 reads channel 2), a few px away from its lip. Returns (img, mask, (ox, oy))
    with the offset relative to the tile's centre."""
    from PIL import Image, ImageDraw
    poly = spec["poly"]
    pad = 22
    x0, y0 = int(min(p[0] for p in poly)) - pad, int(min(p[1] for p in poly)) - pad
    x1, y1 = int(max(p[0] for p in poly)) + pad, int(max(p[1] for p in poly)) + pad
    w, h = x1 - x0, y1 - y0
    centre = (spec["tile"][0] * 16 + 8, spec["tile"][1] * 16 + 8)
    X = np.arange(w)[None, :] + x0 + 0.5
    Y = np.arange(h)[:, None] + y0 + 0.5
    warp_x = (vnoise(w, h, 16, seed + 1) - 0.5) * 16 + (vnoise(w, h, 6, seed + 2) - 0.5) * 6
    warp_y = (vnoise(w, h, 16, seed + 3) - 0.5) * 16 + (vnoise(w, h, 6, seed + 4) - 0.5) * 6
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).polygon([(p[0] - x0, p[1] - y0) for p in poly], fill=255)
    inside = np.array(shape) > 0
    sd = _signed_distance(inside, 24)
    # warp the edge a little: sample the distance field at a noisy position
    wy_i = np.clip((np.arange(h)[:, None] + warp_y).astype(int), 0, h - 1)
    wx_i = np.clip((np.arange(w)[None, :] + warp_x).astype(int), 0, w - 1)
    sd = sd[wy_i, wx_i]
    density = 0.62 + 0.5 * vnoise(w, h, 44, seed + 5)
    holes = 0.62 * vnoise(w, h, 26, seed + 6) + 0.38 * vnoise(w, h, 9, seed + 9)
    pits = vnoise(w, h, 6, seed + 7)
    jitter = (vnoise(w, h, 3, seed + 8) - 0.5) * 0.3
    bayer = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    edge = np.clip((10.0 - sd) / 14.0, 0.0, 1.0)
    keep = (edge * density + jitter) > (bayer * 0.9 + 0.05)
    keep &= ~(holes > 0.70 + (bayer - 0.5) * 0.1)  # grass takes whole patches back
    keep &= ~((pits > 0.86) & (bayer > 0.2))
    PX, PY = np.broadcast_arrays(X + centre[0], Y + centre[1])
    field = relief_field(int(spec.get("level", 3)) - 1, PX, PY)
    lip = field <= 0.58
    top = ~_grow(lip, 1)  # the plateau top
    depth = np.maximum(-_signed_distance(~lip, 14), 0.0)  # px inside the lip (0 at the lip)
    fade = np.clip((depth - 0.5) / 12.0, 0.0, 1.0)  # the stones thin out towards the lip instead of ending in a clean edge
    keep &= top & ((fade * 1.1 + jitter) > (bayer * 0.9 + 0.05))
    for pillar in spec.get("pillars", []):  # every pillar stands on paving, whatever the lip does
        near = np.hypot((X - pillar["pos"][0]) / 1.0, (Y - pillar["pos"][1]) * 1.6) < 26
        keep |= near & top & (holes < 0.8)
    import arena_design  # the carved sun sigil, the ley lines to the pillars, the frieze (tools/arena_design.py)
    paint, glow, solid = arena_design.design(spec, X, Y, sd, seed)
    keep |= solid & top  # no hole of grass in the sigil or under a pillar
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    ys, xs = np.nonzero(keep)
    grown = vnoise(w, h, 5, seed + 11) + (vnoise(w, h, 2, seed + 12) - 0.5) * 0.3
    for y, x in zip(ys, xs):
        img[y, x] = flagstone(int(x + x0), int(y + y0), seed)
        mask[y, x] = (STONE_CODE, 0, 0, 255)
        if depth[y, x] < 16 and grown[y, x] > 0.30 + depth[y, x] / 24.0:  # moss and grass grow over the stones near the lip
            img[y, x] = MOSS[(x + y) % 3] if grown[y, x] < 0.62 else (BUSH[3] if (x * 7 + y * 3) % 5 else MEADOW[3])
    pm = (paint[:, :, 3] == 255) & keep
    img[pm] = paint[pm]
    glow[~pm] = 0
    mossy = pm & (depth < 14) & (grown > 0.55 + depth / 30.0)  # moss and grass grow over the carvings too, near the lip
    for y, x in zip(*np.nonzero(mossy)):
        img[y, x] = MOSS[(x + y) % 3]
        glow[y, x] = 0
    ARENA_GLOW[spec["id"]] = glow
    rng = random.Random(seed)
    for _ in range(int(w * h / 38)):  # grass blades and tufts creeping over the lip
        x, y = rng.randrange(4, w - 4), rng.randrange(8, h - 2)
        if top[y, x] and 0.5 < depth[y, x] < 13 and keep[y, x] and rng.random() < 1.0 - depth[y, x] / 14.0:
            tuft(img, x, y, rng.randrange(2, 5), rng, MEADOW)
    for _ in range(int(w * h / 80)):  # grass and moss creep in through the joints
        x, y = rng.randrange(0, w), rng.randrange(1, h)
        if keep[y, x]:
            c = MOSS[1 + rng.randrange(3)] if rng.random() < 0.7 else BUSH[3]
            img[y, x] = c
            if rng.random() < 0.5:
                img[y - 1, x] = c
    for _ in range(int(w * h / 1400)):  # tufts at the ragged edges
        x, y = rng.randrange(4, w - 4), rng.randrange(8, h - 2)
        if keep[y, x] and sd[y, x] > -12:
            tuft(img, x, y, rng.randrange(3, 6), rng, MEADOW)
    arena_design.rubble(img, keep, top, sd, spec, X, Y, seed)
    arena_design.plant_remains(img, keep, sd, spec, X, Y, seed)
    for _ in range(int(w * h / 650)):  # loose pebbles and chips just outside
        x, y = rng.randrange(2, w - 2), rng.randrange(2, h - 2)
        if not keep[y, x] and top[y, x] and -6 < sd[y, x] < 12 and img[y, x, 3] == 0:
            img[y, x] = STONE[2 + rng.randrange(2)]
            mask[y, x] = (STONE_CODE, 0, 0, 255)
            if rng.random() < 0.4:
                img[y, x + 1] = STONE[1]
    return img, mask, (x0, y0)


def bake_arena_zone(spec):
    """Where the boss fight reaches: the WHOLE top of the plateau (not only the flagstones that survived: the grass between them and the green rim count too), cut 2 px inside
    the lip, and only the piece that is connected to the drawn polygon. Returns (RGBA picture with alpha 255 inside, (ox, oy) relative to the tile's centre)."""
    from PIL import Image, ImageDraw
    poly = spec["poly"]
    pad = 70
    x0, y0 = int(min(p[0] for p in poly)) - pad, int(min(p[1] for p in poly)) - pad
    x1, y1 = int(max(p[0] for p in poly)) + pad, int(max(p[1] for p in poly)) + pad
    w, h = x1 - x0, y1 - y0
    centre = (spec["tile"][0] * 16 + 8, spec["tile"][1] * 16 + 8)
    X = np.arange(w)[None, :] + x0 + 0.5
    Y = np.arange(h)[:, None] + y0 + 0.5
    PX, PY = np.broadcast_arrays(X + centre[0], Y + centre[1])
    field = relief_field(int(spec.get("level", 3)) - 1, PX, PY)
    top = ~_grow(field <= 0.58, 2)
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).polygon([(p[0] - x0, p[1] - y0) for p in poly], fill=255)
    seed_px = np.array(shape) > 0
    zone = np.zeros((h, w), bool)
    stack = [tuple(p) for p in zip(*np.nonzero(seed_px & top))][::97]  # a few seeds inside the polygon, then flood over the plateau top
    for y, x in stack:
        if zone[y, x]:
            continue
        zone[y, x] = True
        todo = [(y, x)]
        while todo:
            cy, cx = todo.pop()
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and top[ny, nx] and not zone[ny, nx]:
                    zone[ny, nx] = True
                    todo.append((ny, nx))
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[zone] = (STONE_CODE, 0, 0, 255)
    return img, (x0, y0)


# ------------------------------------------------------------------ the footpath
def catmull(points, step=2.0):
    """A smooth curve through the points, sampled about every `step` px."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(pts[i + k], dtype=float) for k in (-1, 0, 1, 2))
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(np.array(pts[-2], dtype=float))
    return np.array(out)


PATH_RAMP = [hexc(c) for c in ("463852", "5e4f62", "7b6b6e", "988978", "b4a58b", "cdc0a2", "e3d7ba")]
DAMP_RAMP = [hexc(c) for c in ("2d2540", "433852", "5c4f64", "796b78", "96888c", "b4a7a0", "ccc0b6")]
MEADOW_HI = MEADOW + [hexc("a8dc8c")]
WILDFLOWERS = [hexc("dc9ac4"), hexc("b6ace0"), hexc("fff0e4"), hexc("ffe28a")]
ROOT_BARK = [hexc(c) for c in ("281d34", "523e52", "826876", "b29690")]


def _draw_path_pebble(img, mask, cx, cy, size):
    """Shaded 3D twilight-slate pebble/cobble with top-left glint and cool-violet seat shadow."""
    h, w = img.shape[:2]
    ix, iy = int(round(cx)), int(round(cy))
    if size <= 1.15:
        if 1 <= ix < w - 1 and 1 <= iy < h - 1 and img[iy, ix, 3] > 0:
            img[iy, ix] = STONE[4]
            if img[iy, ix + 1, 3] > 0:
                img[iy, ix + 1] = STONE[2]
        return
    rx, ry = size, max(1.2, size * 0.76)
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if not (0 <= x < w and 0 <= y < h):
                continue
            dx, dy = (x - cx) / rx, (y - cy) / ry
            d = dx * dx + dy * dy
            if d <= 1.0:
                lit = -(dx * 0.65 + dy * 0.75)
                img[y, x] = STONE[clampi(int(round(2.8 + lit * 1.8)), 1, 5)]
                if size >= 2.2:
                    mask[y, x] = (STONE_CODE, 0, 0, 255)
            elif d <= 1.38 and dy > 0.15 and dx > -0.2 and img[y, x, 3] > 0:
                img[y, x, :3] = (
                    int(img[y, x, 0] * 0.76),
                    int(img[y, x, 1] * 0.74),
                    min(255, int(img[y, x, 2] * 0.84 + 6)),
                )


def _draw_path_slab(img, mask, cx, cy, rx, ry, angle_deg, seed, mossy=0.28, at=(0, 0)):
    """Cluster-clean crooked sunken flagstone slab (top-left bevel, mortar seat, moss cushions)."""
    h, w = img.shape[:2]
    ca, sa = math.cos(math.radians(angle_deg)), math.sin(math.radians(angle_deg))
    reach = int(max(rx, ry)) + 3
    tone_shift = (noise(int(cx) + at[0], int(cy) + at[1], seed) / 255.0 - 0.5) * 0.65  # `at`: the picture's origin, for stones that must match across pictures
    for y in range(int(cy) - reach, int(cy) + reach + 1):
        for x in range(int(cx) - reach, int(cx) + reach + 1):
            if not (0 <= x < w and 0 <= y < h):
                continue
            ux, uy = x - cx, y - cy
            dx = (ux * ca + uy * sa) / rx
            dy = (-ux * sa + uy * ca) / ry
            ang = math.atan2(dy, dx)
            wob = 1.0 + 0.11 * math.sin(ang * 3.0 + seed) + 0.06 * math.cos(ang * 5.0 - seed * 0.7)
            d = (abs(dx) ** 3.0 + abs(dy) ** 3.0) ** (1.0 / 3.0) / wob
            if d > 1.10:
                continue
            if d > 0.96:
                if ux * 0.6 + uy * 0.8 > 0.0 and img[y, x, 3] > 0:
                    img[y, x] = MORTAR
                continue
            lit = -(ux / rx * 0.55 + uy / ry * 0.80)
            if d > 0.78:
                c = STONE[4] if lit > 0.22 else (STONE[1] if lit < -0.25 else STONE[2])
            else:
                cush = (noise((x + at[0]) // 3, (y + at[1]) // 3, seed + 9) / 255.0 - 0.5) * 0.85
                val = 2.65 + tone_shift + lit * 0.85 + cush
                c = STONE[clampi(int(round(val)), 1, 4)]
                if mossy > 0 and noise((x + at[0]) // 2, (y + at[1]) // 2, seed + 17) > int(255 * (1.0 - mossy)):
                    c = MOSS[clampi(int(lit + 1.6), 0, 3)]
            img[y, x] = c
            mask[y, x] = (STONE_CODE, 0, 0, 255)


QUARTZ_CARAVAN = [hexc(c) for c in ("5b698e", "8191b6", "a2b3d4", "bfcde7", "d6e2f5", "ffffff")]
SANDSTONE_CARAVAN = [hexc(c) for c in ("483038", "785042", "aa7a4e", "d8a868", "f2cf8e")]
SAND_DRIFT_RAMP = [hexc(c) for c in ("6b433e", "946247", "bd8754", "dfb06e", "f5d596")]
CARAVAN_MORTAR = hexc("5c3d38")
CARAVAN_GLOW_TEAL = hexc("78f4e6")
CARAVAN_GLOW_GOLD = hexc("ffd86b")


def bake_quartz_caravan_path(spec, seed, centre):
    """Bakes the ancient sand-drifted Sonnenquarz-Öde caravan road:
    - Weathered Voronoi pale-quartz (QUARTZ_W) & carved golden-sandstone flagstones
    - Intermittently buried beneath wind-blown desert sand dunes (alpha=0, mask=0 in gaps)
    - Feathered warm ochre-amber sand shoulders (zero green meadow grass!)
    - Subtle inlaid turquoise-gold rune seams in *_glow.png."""
    width = float(spec.get("width", 28))
    curve = catmull(spec["points"], step=1.8)
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(arc[-1])
    margin = int(width) + 18
    x0, y0 = int(curve[:, 0].min()) - margin, int(curve[:, 1].min()) - margin
    x1, y1 = int(curve[:, 0].max()) + margin, int(curve[:, 1].max()) + margin
    w, h = x1 - x0, y1 - y0

    rng = np.random.default_rng(seed)
    phase = rng.random(8) * math.tau

    taper_in = np.clip(arc / float(spec.get("taper_in", 48.0) or 1.0), 0.0, 1.0)
    taper_out = np.clip((total - arc) / float(spec.get("taper_out", 48.0) or 1.0), 0.0, 1.0)
    end_env = np.minimum(taper_in, taper_out)
    # Wind-sand burial wave: > 0.68 buries the stones completely beneath live desert sand!
    drift = (
        0.48
        + 0.34 * np.sin(arc / 58.0 + phase[0])
        + 0.22 * np.sin(arc / 23.0 + phase[1])
        + 0.16 * np.cos(arc / 105.0 + phase[2])
    )
    expose = np.clip((0.72 - drift) / 0.28, 0.0, 1.0) * end_env
    half = width * 0.5 * (0.86 + 0.18 * np.sin(arc / 47.0 + phase[3])) * np.where(expose > 0.05, 0.45 + 0.55 * expose, 0.0)

    d2_map = np.full((h, w), 1e9, dtype=np.float32)
    idx_map = np.zeros((h, w), dtype=np.int32)
    cx_local = curve[:, 0] - x0
    cy_local = curve[:, 1] - y0
    for i in range(len(curve)):
        hw_i = float(half[i])
        if hw_i < 1.5:
            continue
        reach = int(hw_i * 1.35) + 4
        lx0, lx1 = max(0, int(cx_local[i]) - reach), min(w - 1, int(cx_local[i]) + reach)
        ly0, ly1 = max(0, int(cy_local[i]) - reach), min(h - 1, int(cy_local[i]) + reach)
        if lx1 < lx0 or ly1 < ly0:
            continue
        px = (np.arange(lx0, lx1 + 1, dtype=np.float32) + 0.5)[None, :]
        py = (np.arange(ly0, ly1 + 1, dtype=np.float32) + 0.5)[:, None]
        dd2 = (px - cx_local[i]) ** 2 + (py - cy_local[i]) ** 2
        cur_sub = d2_map[ly0:ly1 + 1, lx0:lx1 + 1]
        better = dd2 < cur_sub
        cur_sub[better] = dd2[better]
        idx_map[ly0:ly1 + 1, lx0:lx1 + 1][better] = i

    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    glow = np.zeros((h, w, 4), dtype=np.uint8)
    ys_b, xs_b = np.nonzero(d2_map < 1e8)
    if len(ys_b) == 0:
        return img, mask, (x0, y0), glow

    edge_wob = (vnoise(w, h, 7, seed + 21) - 0.5) * 0.30 + (vnoise(w, h, 3, seed + 22) - 0.5) * 0.12
    sand_veil = vnoise(w, h, 6, seed + 25)

    for py_i, px_i in zip(ys_b.tolist(), xs_b.tolist()):
        ci = int(idx_map[py_i, px_i])
        hw_v = float(half[ci])
        if hw_v < 2.0:
            continue
        exp_v = float(expose[ci])
        te = math.sqrt(float(d2_map[py_i, px_i])) / hw_v + float(edge_wob[py_i, px_i])
        if te >= 1.05:
            continue
        gx, gy = px_i + x0 + seed * 3, py_i + y0 + seed * 5
        # Soft warm drifted sand shoulder around exposed stones
        if te > 0.80 or float(sand_veil[py_i, px_i]) > exp_v * 0.92 + 0.16:
            if te < 0.98 and exp_v > 0.22 and (noise(gx // 2, gy // 2, seed + 31) % 100) < int(58 * exp_v):
                st = clampi(int(round(2.4 - (te - 0.75) * 2.2 + (float(sand_veil[py_i, px_i]) - 0.5))), 1, 4)
                sc = SAND_DRIFT_RAMP[st]
                img[py_i, px_i] = (sc[0], sc[1], sc[2], 220)
            continue
        cid, d1, d2, (ccx, ccy) = cell_of(gx, gy)
        # Skip whole Voronoi stone cells near sand-buried transitions so flagstones are never sliced cleanly in half
        cell_keep = (noise(cid, 5, seed + 41) / 255.0)
        if cell_keep > exp_v * 1.08 + 0.06:
            if (noise(gx // 2, gy // 2, seed + 43) % 100) < 42:
                sc = SAND_DRIFT_RAMP[2]
                img[py_i, px_i] = (sc[0], sc[1], sc[2], 195)
            continue
        is_quartz_slab = (noise(cid, 11, seed + 53) % 100) < 62
        mask[py_i, px_i] = (STONE_CODE, 0, 0, 255)
        if d2 - d1 < 1.25:
            # Sand-filled mortar joint, with rare inlaid rune seam on center slabs
            if is_quartz_slab and te < 0.34 and (noise(cid, 19, seed + 61) % 100) < 16:
                rc = CARAVAN_GLOW_TEAL if (cid % 2 == 0) else CARAVAN_GLOW_GOLD
                img[py_i, px_i] = rc
                glow[py_i, px_i] = (rc[0], rc[1], rc[2], 190)
            else:
                img[py_i, px_i] = SAND_DRIFT_RAMP[1] if (noise(gx, gy, 67) > 150) else CARAVAN_MORTAR
        else:
            lit = -0.56 * ((gx + 0.5 - ccx) + (gy + 0.5 - ccy)) / (CELL * 0.6)
            c_cush = (noise(gx // 3, gy // 3, 71) / 255.0 - 0.5) * 0.55
            if is_quartz_slab:
                base_t = 2 + (noise(cid, 7, 73) % 2)
                if d2 - d1 < 2.4 and (gx + 0.5 - ccx) + (gy + 0.5 - ccy) < -0.4:
                    img[py_i, px_i] = QUARTZ_CARAVAN[5]
                else:
                    img[py_i, px_i] = QUARTZ_CARAVAN[clampi(int(round(base_t + 0.55 + lit + c_cush)), 1, 4)]
            else:
                base_t = 1 + (noise(cid, 7, 79) % 2)
                if d2 - d1 < 2.4 and (gx + 0.5 - ccx) + (gy + 0.5 - ccy) < -0.4:
                    img[py_i, px_i] = SANDSTONE_CARAVAN[4]
                else:
                    img[py_i, px_i] = SANDSTONE_CARAVAN[clampi(int(round(base_t + 0.6 + lit + c_cush)), 0, 3)]
    return img, mask, (x0, y0), glow


def bake_path(spec, seed, centre):
    """Bakes a rich, organic Shadowspore path decal:
    - Cluster-shaded earth cushions (orphan-cleaned, zero 4x4 Bayer static)
    - Alternating double-rut stretches, warm single-track sections, and natural grassy spur-islands
    - Whole-cell Voronoi twilight-slate flagstones & crooked curbstones in weathered stretches
    - Damp violet-umber hollows with sky-reflecting puddles, shaded pebbles, bark chips & bank roots
    - Scalloped overhanging NW turf & curved SE grass blades melting seamlessly into grass.png."""
    width = float(spec.get("width", 26))
    is_gloom = bool(spec.get("gloom", False))
    seed = int(spec.get("seed", seed))  # the pieces of one road share a seed, so their widths, ruts and paving run on without a seam
    curve = catmull(spec["points"], step=1.6)
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(arc[-1])
    # A piece of a long road (`arc` [from, to] in px along the curve): everything is computed over the piece plus a margin of the
    # neighbours, but only the pixels nearest to its own stretch are kept (`own_lo` .. `own_hi`), so the pictures meet on a clean cut.
    piece = spec.get("arc")
    own_lo, own_hi = 0, len(curve)
    if piece:
        own_lo = int(np.searchsorted(arc, float(piece[0])))
        own_hi = len(curve) if float(piece[1]) >= total - 1.0 else int(np.searchsorted(arc, float(piece[1])))
    pad = int((width + 40) / 1.6) if piece else 0
    r_lo, r_hi = max(0, own_lo - pad), min(len(curve), own_hi + pad)
    span = total if not piece else float(arc[own_hi - 1] - arc[own_lo])
    margin = int(width) + 18
    x0, y0 = int(curve[r_lo:r_hi, 0].min()) - margin, int(curve[r_lo:r_hi, 1].min()) - margin
    x1, y1 = int(curve[r_lo:r_hi, 0].max()) + margin, int(curve[r_lo:r_hi, 1].max()) + margin
    w, h = x1 - x0, y1 - y0
    if piece:
        vnoise_l = lambda w_, h_, sc, sd: vnoise_at(x0 + centre[0], y0 + centre[1], w_, h_, sc, sd)  # noqa: E731
    else:
        vnoise_l = vnoise

    def own(ci):  # a feature centred on this curve index belongs to this picture (with room to spare at a cut)
        if not piece:
            return True
        return own_lo <= ci < own_hi and arc[ci] - arc[own_lo] >= (16.0 if own_lo > 0 else -1.0) and arc[own_hi - 1] - arc[ci] >= (16.0 if own_hi < len(curve) else -1.0)

    rng = np.random.default_rng(seed)
    prng = random.Random(seed)
    phase = rng.random(12) * math.tau

    # Breathing width, ruts, dampness, stone paving, and occasional spur-islands along arc `s`
    half = width * 0.5 * (
        0.88
        + 0.20 * np.sin(arc / 53.0 + phase[0])
        + 0.11 * np.sin(arc / 21.0 + phase[1])
        + 0.08 * np.maximum(0.0, np.sin(arc / 115.0 + phase[2]) - 0.35)
    )
    taper_in = np.clip(arc / float(spec.get("taper_in", 0.0) or 1.0), 0.0, 1.0) if spec.get("taper_in", 0) else np.ones_like(arc)
    taper_out = np.clip((total - arc) / float(spec.get("taper_out", 70.0)), 0.0, 1.0)
    end_env = np.minimum(taper_in, 0.25 + 0.75 * taper_out)
    half = half * end_env

    rut_amt = np.clip(0.55 + 0.55 * np.sin(arc / 85.0 + phase[3]), 0.0, 1.0)
    damp_amt = np.clip(0.38 + 0.58 * np.sin(arc / 130.0 + phase[4]) * np.cos(arc / 67.0 + phase[5]), 0.0, 1.0)
    if is_gloom:
        damp_amt = np.clip(damp_amt * 0.7 + 0.35, 0.0, 1.0)
    # Stone flagstone patches: stronger near start_ruins on footpath_start, plus organic old remnants along the way
    ruin_boost = np.exp(-arc / 160.0) * (0.42 if spec.get("id") == "footpath_start" else 0.0)
    pave_amt = np.clip(0.45 * np.sin(arc / 95.0 + phase[6]) * np.sin(arc / 43.0 + phase[7]) + ruin_boost, 0.0, 1.0)
    island_amt = np.where((half >= 12.2) & (arc > 75.0) & (arc < total - 95.0), np.sin(arc / 145.0 + phase[8]), -1.0)
    is_ruts = bool(spec.get("ruts", False))  # a cart road (the caravan's, docs/haendler_konzept.md 4.1): two worn wheel ruts, grass down the middle, no paving
    mid_amt = np.zeros_like(arc)
    city = np.zeros_like(arc)
    if spec.get("old_road"):  # the Westweg (docs/stadt_westen_konzept.md 2.4): remnants of an old paved road that grows whole towards the city
        u = np.clip((arc / max(total, 1.0) - 0.55) / 0.40, 0.0, 1.0)
        city = u * u * (3.0 - 2.0 * u)
        pave_amt = np.clip(pave_amt * (1.0 - city) + 0.10 + 0.22 * np.maximum(0.0, np.sin(arc / 211.0 + phase[10])) + city * 0.98, 0.0, 1.0)
        rut_amt = rut_amt * (1.0 - 0.75 * city)
        island_amt = np.where(city > 0.25, -1.0, island_amt)
    if is_ruts:
        rut_amt = np.clip(0.86 + 0.14 * np.sin(arc / 60.0 + phase[3]), 0.0, 1.0)
        pave_amt = np.zeros_like(arc)
        island_amt = np.full_like(arc, -1.0)
        mid_amt = np.clip(0.75 + 0.45 * np.sin(arc / 70.0 + phase[9]), 0.0, 1.0) * np.clip(arc / 40.0, 0.0, 1.0)

    tangents = np.gradient(curve, axis=0)
    tangents /= np.linalg.norm(tangents, axis=1)[:, None] + 1e-9

    # Fast band-restricted distance & nearest-index rasterization around the curve!
    d2_map = np.full((h, w), 1e9, dtype=np.float32)
    idx_map = np.zeros((h, w), dtype=np.int32)
    cx_local = curve[:, 0] - x0
    cy_local = curve[:, 1] - y0
    for i in range(r_lo, r_hi):
        hw_i = float(half[i])
        if hw_i < 0.8:
            continue
        reach = int(hw_i * 1.45) + 5
        lx0, lx1 = max(0, int(cx_local[i]) - reach), min(w - 1, int(cx_local[i]) + reach)
        ly0, ly1 = max(0, int(cy_local[i]) - reach), min(h - 1, int(cy_local[i]) + reach)
        if lx1 < lx0 or ly1 < ly0:
            continue
        px = (np.arange(lx0, lx1 + 1, dtype=np.float32) + 0.5)[None, :]
        py = (np.arange(ly0, ly1 + 1, dtype=np.float32) + 0.5)[:, None]
        dd2 = (px - cx_local[i]) ** 2 + (py - cy_local[i]) ** 2
        cur_sub = d2_map[ly0:ly1 + 1, lx0:lx1 + 1]
        better = dd2 < cur_sub
        cur_sub[better] = dd2[better]
        idx_map[ly0:ly1 + 1, lx0:lx1 + 1][better] = i

    near_band = d2_map < 1e8
    ys_b, xs_b = np.nonzero(near_band)
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    if len(ys_b) == 0:
        return img, mask, (x0, y0)

    edge_wob = (vnoise_l(w, h, 8, seed + 11) - 0.5) * 0.28 + (vnoise_l(w, h, 3, seed + 12) - 0.5) * 0.10
    cush = (vnoise_l(w, h, 9, seed + 13) - 0.5) * 1.55 + (vnoise_l(w, h, 4, seed + 14) - 0.5) * 0.55

    c_idx = idx_map[ys_b, xs_b]
    d_val = np.sqrt(d2_map[ys_b, xs_b])
    hw_val = np.maximum(half[c_idx], 0.5)
    vx = (xs_b + 0.5 - cx_local[c_idx]) / np.maximum(d_val, 1e-6)
    vy = (ys_b + 0.5 - cy_local[c_idx]) / np.maximum(d_val, 1e-6)
    nw_val = vx * (-0.7071) + vy * (-0.7071)
    lat_val = vx * (-tangents[c_idx, 1]) + vy * tangents[c_idx, 0]

    # Spur-Insel: where island_amt > 0.78, push the two tracks gently apart around a tiny meadow island
    isl = np.clip((island_amt[c_idx] - 0.76) / 0.24, 0.0, 1.0)
    eff_t = np.where(
        isl > 0.0,
        np.abs(d_val - isl * hw_val * 0.48) / (hw_val * (1.0 - 0.26 * isl)),
        d_val / hw_val,
    )
    te_val = eff_t + edge_wob[ys_b, xs_b]

    keep_sub = (te_val < 1.0) & (hw_val >= 1.0)
    if is_ruts:  # the grass strip between the wheels: the meadow shows through, ragged at its edges
        lat_frac = np.abs(lat_val * eff_t)
        strip = 0.17 + (edge_wob[ys_b, xs_b] * 0.35)
        keep_sub &= ~((lat_frac < strip) & (mid_amt[c_idx] > 0.35))
    ky, kx = ys_b[keep_sub], xs_b[keep_sub]
    k_cidx = c_idx[keep_sub]
    k_te = te_val[keep_sub]
    k_t = eff_t[keep_sub]
    k_nw = nw_val[keep_sub]
    k_lat = lat_val[keep_sub]
    k_isl = isl[keep_sub]

    keep = np.zeros((h, w), dtype=bool)
    keep[ky, kx] = True
    nw_grid = np.zeros((h, w), dtype=np.float32)
    nw_grid[ky, kx] = k_nw
    te_grid = np.ones((h, w), dtype=np.float32) * 2.0
    te_grid[ky, kx] = k_te

    # Compute cluster-shaded soil index (0..6)
    rut_profile = np.exp(-((np.abs(k_lat * k_t) - 0.44) / 0.18) ** 2) * rut_amt[k_cidx] * (1.0 - k_isl)
    center_warm = (1.0 - rut_amt[k_cidx]) * 0.75 * np.maximum(0.0, 1.0 - (k_t / 0.62) ** 2)
    bank_shade = np.where(
        k_te > 0.74,
        np.where(k_nw > 0.16, -0.75, np.where(k_nw < -0.16, 0.55, 0.0)),
        0.0,
    )
    raw_tone = (
        3.65
        + cush[ky, kx]
        + center_warm
        - 1.30 * rut_profile
        - 0.75 * np.maximum(0.0, k_te - 0.62) / 0.38
        + bank_shade
    )
    tone_grid = np.zeros((h, w), dtype=np.int32)
    tone_grid[ky, kx] = np.clip(np.rint(raw_tone), 0, 6).astype(np.int32)

    # Vectorized 2-pass orphan cleanup so every soil patch reads as crisp cel-shaded cushions!
    for _ in range(2):
        up = np.pad(tone_grid[:-1, :], ((1, 0), (0, 0)), mode="edge")
        dn = np.pad(tone_grid[1:, :], ((0, 1), (0, 0)), mode="edge")
        lf = np.pad(tone_grid[:, :-1], ((0, 0), (1, 0)), mode="edge")
        rt = np.pad(tone_grid[:, 1:], ((0, 0), (0, 1)), mode="edge")
        same = (tone_grid == up).astype(int) + (tone_grid == dn).astype(int) + (tone_grid == lf).astype(int) + (tone_grid == rt).astype(int)
        orphan = keep & (same == 0)
        med = np.sort(np.stack([up, dn, lf, rt], axis=-1), axis=-1)[..., 1]
        tone_grid[orphan] = med[orphan]

    # Blend between warm sunlit EARTH and cool violet-umber DAMP_RAMP along damp stretches
    earth_arr = np.array(PATH_RAMP, dtype=np.float32)
    damp_arr = np.array(DAMP_RAMP, dtype=np.float32)
    t_idx = tone_grid[ky, kx]
    d_mix = damp_amt[k_cidx][:, None]
    cols = np.clip(earth_arr[t_idx] * (1.0 - d_mix) + damp_arr[t_idx] * d_mix, 0, 255).astype(np.uint8)
    cols[:, 3] = 255
    img[ky, kx] = cols

    solid_mask = keep & (te_grid < 0.88)
    mask[solid_mask] = (PATH_CODE, 0, 0, 255)

    # Subtle 2-3 px horizontal soil ripples inside wide beds
    for _ in range(int(span * 0.45)):
        ci = prng.randrange(own_lo, own_hi)
        if half[ci] < 5.0:
            continue
        off = prng.uniform(-0.65, 0.65) * half[ci]
        sx_i = int(cx_local[ci] - tangents[ci, 1] * off)
        sy_i = int(cy_local[ci] + tangents[ci, 0] * off)
        if 2 <= sx_i < w - 4 and 2 <= sy_i < h - 2 and keep[sy_i, sx_i]:
            nt = clampi(tone_grid[sy_i, sx_i] + prng.choice((-1, 1)), 0, 6)
            dm = float(damp_amt[ci])
            rc = tuple(int(earth_arr[nt, ch] * (1.0 - dm) + damp_arr[nt, ch] * dm) for ch in range(3)) + (255,)
            for dx in range(prng.randint(2, 3)):
                if keep[sy_i, sx_i + dx]:
                    img[sy_i, sx_i + dx] = rc

    # Whole-cell Voronoi twilight-slate flagstones in weathered paved stretches (never sliced mid-stone!)
    stone_drawn = np.zeros((h, w), dtype=bool)
    pave_indices = np.nonzero(pave_amt > 0.16)[0]
    whole_stones = bool(spec.get("old_road"))  # the old road: a stone is there or not as a whole (decided at its own centre), never cut by a box
    visited_boxes = set()
    for ci in pave_indices[::6]:
        bx_c, by_c = (int(cx_local[ci]) // 16, int(cy_local[ci]) // 16) if not piece else (int(curve[ci, 0]) // 16, int(curve[ci, 1]) // 16)  # pieces: world boxes, so both sides of a cut lay the same stones
        if (bx_c, by_c) in visited_boxes:
            continue
        visited_boxes.add((bx_c, by_c))
        reach = int(half[ci]) + (14 if whole_stones else 4)
        ya, yb = max(0, int(cy_local[ci]) - reach), min(h - 1, int(cy_local[ci]) + reach)
        xa, xb = max(0, int(cx_local[ci]) - reach), min(w - 1, int(cx_local[ci]) + reach)
        loc_thresh = 1.0 - pave_amt[ci] * 1.15
        for py_i in range(ya, yb + 1):
            for px_i in range(xa, xb + 1):
                if not keep[py_i, px_i] or stone_drawn[py_i, px_i]:
                    continue
                gx, gy = px_i + x0 + seed * 5, py_i + y0 + seed * 3
                cid, d1, d2, (ccx, ccy) = cell_of(gx, gy)
                icx = clampi(int(round(ccx - seed * 5 - x0)), 0, w - 1)
                icy = clampi(int(round(ccy - seed * 3 - y0)), 0, h - 1)
                if te_grid[icy, icx] >= 0.72:
                    continue
                if (noise(cid, 3, seed + 91) / 255.0) < ((1.0 - pave_amt[idx_map[icy, icx]] * 1.15) if whole_stones else loc_thresh):
                    continue
                stone_drawn[py_i, px_i] = True
                mask[py_i, px_i] = (STONE_CODE, 0, 0, 255)
                if d2 - d1 < 1.25:
                    img[py_i, px_i] = MOSS[noise(gx, gy, 47) % 3] if noise(gx // 2, gy // 2, 46) > 198 else MORTAR
                else:
                    tone = 1 + (noise(cid, 7, 43) % 3)
                    lit = -0.52 * ((gx + 0.5 - ccx) + (gy + 0.5 - ccy)) / (CELL * 0.6)
                    if d2 - d1 < 2.5 and (gx + 0.5 - ccx) + (gy + 0.5 - ccy) < -0.4:
                        img[py_i, px_i] = STONE[clampi(tone + 1, 2, 5)]
                    else:
                        c_cush = (noise(gx // 3, gy // 3, 48) / 255.0 - 0.5) * 0.65
                        img[py_i, px_i] = STONE[clampi(int(round(tone + 0.6 + lit + c_cush)), 1, 4)]

    # Crooked sunken stepping slabs, mossy island boulders, occasional puddles, and bank roots
    last_feature_a = -40.0
    for ci in range(max(12, own_lo), min(len(curve) - 12, own_hi), 8):
        if not own(ci):
            continue
        a_cur = float(arc[ci])
        if a_cur - last_feature_a < 26.0 or half[ci] < 7.5:
            continue
        nx_v, ny_v = -tangents[ci, 1], tangents[ci, 0]
        ang = math.degrees(math.atan2(ny_v, nx_v)) + 90.0
        # Mossy boulder on Spur-Insel centers!
        if island_amt[ci] > 0.88:
            _draw_path_slab(img, mask, cx_local[ci], cy_local[ci], 5.6, 4.0, ang + prng.uniform(-15, 15), seed + ci, mossy=0.45)
            last_feature_a = a_cur + 22.0
            continue
        r_roll = prng.random()
        if damp_amt[ci] > 0.78 and half[ci] >= 11.0 and r_roll < 0.22:
            # Small organic rainwater puddle reflecting the sky
            pcx = cx_local[ci] + nx_v * prng.uniform(-2.5, 2.5)
            pcy = cy_local[ci] + ny_v * prng.uniform(-2.5, 2.5)
            prx, pry = prng.uniform(4.2, 6.4), prng.uniform(2.6, 3.8)
            for yy in range(max(0, int(pcy - pry - 2)), min(h, int(pcy + pry + 3))):
                for xx in range(max(0, int(pcx - prx - 2)), min(w, int(pcx + prx + 3))):
                    if not keep[yy, xx] or stone_drawn[yy, xx]:
                        continue
                    pa = math.atan2(yy - pcy, xx - pcx)
                    pw = 1.0 + 0.14 * math.sin(pa * 2.0 + ci)
                    dd = math.hypot((xx - pcx) / prx, (yy - pcy) / pry) / pw
                    if 1.0 < dd <= 1.26:
                        img[yy, xx] = DAMP_RAMP[0]
                    elif dd <= 1.0:
                        pt = 0 if dd > 0.76 else (2 if (yy - pcy) < -0.1 * pry else 1)
                        if -0.4 * prx < (xx - pcx) < 0.05 * prx and -0.4 * pry < (yy - pcy) < -0.05 * pry:
                            pt = 3
                        img[yy, xx] = PUDDLE[pt]
            last_feature_a = a_cur + 28.0
        elif r_roll < (0.28 if is_gloom else 0.18):
            # Crooked sunken curbstone or stepping slab
            side_sgn = prng.choice((-1, 1))
            off = side_sgn * half[ci] * (prng.uniform(0.55, 0.78) if not is_gloom else prng.uniform(0.1, 0.65))
            _draw_path_slab(
                img, mask,
                cx_local[ci] + nx_v * off, cy_local[ci] + ny_v * off,
                prng.uniform(3.8, 5.2), prng.uniform(2.6, 3.6),
                ang + prng.uniform(-14, 14), seed + ci * 3, mossy=0.32
            )
            last_feature_a = a_cur
        elif r_roll < (0.52 if is_gloom else 0.25):
            # Tapering gnarled root gripping from the shady bank into the sunken path bed
            side_sgn = -1 if (nx_v * (-0.7) + ny_v * (-0.7)) < 0 else 1
            r_start = (cx_local[ci] + nx_v * side_sgn * half[ci] * 0.92, cy_local[ci] + ny_v * side_sgn * half[ci] * 0.92)
            r_mid = (
                cx_local[ci] + nx_v * side_sgn * half[ci] * 0.42 + tangents[ci, 0] * prng.uniform(-4, 4),
                cy_local[ci] + ny_v * side_sgn * half[ci] * 0.42 + tangents[ci, 1] * prng.uniform(-4, 4),
            )
            r_end = (
                cx_local[ci] + nx_v * side_sgn * half[ci] * 0.05 + tangents[ci, 0] * prng.uniform(-7, 7),
                cy_local[ci] + ny_v * side_sgn * half[ci] * 0.05 + tangents[ci, 1] * prng.uniform(-7, 7),
            )
            rc = catmull([r_start, r_mid, r_end], step=0.6)
            for ri, (rx_f, ry_f) in enumerate(rc):
                rad = 1.65 * (1.0 - 0.65 * ri / max(1, len(rc) - 1))
                for yy in range(max(0, int(ry_f - 2)), min(h, int(ry_f + 3))):
                    for xx in range(max(0, int(rx_f - 2)), min(w, int(rx_f + 3))):
                        if not keep[yy, xx]:
                            continue
                        dd = math.hypot(xx - rx_f, yy - ry_f)
                        if dd <= rad:
                            lit = -((xx - rx_f) * 0.65 + (yy - ry_f) * 0.75) / max(rad, 0.5)
                            img[yy, xx] = ROOT_BARK[clampi(int(round(1.7 + lit * 1.2)), 0, 3)]
            last_feature_a = a_cur

    if spec.get("old_road"):  # kerbstones along both edges where the old road was kept up (more and more towards the city)
        def rnd(ci, k):  # hashed, not drawn from prng: the neighbour piece lays the very same stones in its margin
            return noise(ci, k, seed + 613) / 255.0

        for ci in range(max(4, r_lo - r_lo % 4), min(len(curve) - 4, r_hi), 4):
            if half[ci] < 8.0 or rnd(ci, 0) > city[ci] * 0.9:
                continue
            ang = math.degrees(math.atan2(tangents[ci, 1], tangents[ci, 0]))
            for k, side in ((1, -1.0), (2, 1.0)):
                if rnd(ci, k) < 0.16:  # a stone gone here and there
                    continue
                off = side * (half[ci] - 2.4)
                _draw_path_slab(img, mask, cx_local[ci] - tangents[ci, 1] * off, cy_local[ci] + tangents[ci, 0] * off,
                                3.3 + rnd(ci, k + 2), 1.8 + 0.5 * rnd(ci, k + 4), ang - 7 + 14 * rnd(ci, k + 6), seed + ci * 7 + k,
                                mossy=0.16 + 0.32 * (1.0 - float(city[ci])), at=(x0, y0))

    # Shaded 3D slate pebbles & occasional bark chips
    for _ in range(int(span / 6.5)):
        ci = prng.randrange(own_lo, own_hi)
        if half[ci] < 4.0:
            continue
        off = prng.uniform(-0.82, 0.82) * half[ci]
        px_f = cx_local[ci] - tangents[ci, 1] * off
        py_f = cy_local[ci] + tangents[ci, 0] * off
        ix, iy = int(px_f), int(py_f)
        if 3 <= ix < w - 3 and 3 <= iy < h - 3 and keep[iy, ix] and not stone_drawn[iy, ix]:
            if prng.random() < 0.22:
                img[iy, ix] = WOOD_CHIP[prng.randrange(1, 4)]
                if keep[iy, ix + 1]:
                    img[iy, ix + 1] = WOOD_CHIP[prng.randrange(0, 3)]
            else:
                _draw_path_pebble(img, mask, px_f, py_f, prng.choice((1.0, 1.0, 1.5, 2.1)))

    # Melted turf edge: scalloped overhanging NW grass cushions + curved SE grass blades & wildflowers
    eroded = keep.copy()
    eroded[1:, :] &= keep[:-1, :]
    eroded[:-1, :] &= keep[1:, :]
    eroded[:, 1:] &= keep[:, :-1]
    eroded[:, :-1] &= keep[:, 1:]
    rim_ys, rim_xs = np.nonzero(keep & ~eroded)
    rim_pts = list(zip(rim_xs.tolist(), rim_ys.tolist()))
    prng.shuffle(rim_pts)
    for bx, by in rim_pts:
        if prng.random() > 0.62:
            continue
        nw = nw_grid[by, bx]
        if nw > 0.05:
            w_clump = prng.randint(2, 4)
            for dx in range(w_clump):
                xx = bx + dx - 1
                if not (0 <= xx < w):
                    continue
                drop = 1 if (dx == 0 or dx == w_clump - 1) else prng.randint(1, 2)
                for dy in range(0, drop):
                    yy = by + dy
                    if 0 <= yy < h and keep[yy, xx]:
                        img[yy, xx] = MEADOW_HI[clampi(4 - dy, 1, 5)]
                if 0 <= by + drop < h and keep[by + drop, xx]:
                    img[by + drop, xx, :3] = (
                        int(img[by + drop, xx, 0] * 0.80),
                        int(img[by + drop, xx, 1] * 0.78),
                        min(255, int(img[by + drop, xx, 2] * 0.88 + 6)),
                    )
        else:
            for k in range(prng.randint(2, 4)):
                xx0 = bx + k - 1
                ln = prng.randint(2, 5)
                lean = prng.choice((-1, 0, 0, 1))
                for j in range(ln):
                    xx = xx0 + (lean if j >= ln - 1 else 0)
                    yy = by + 1 - j
                    if 0 <= xx < w and 0 <= yy < h:
                        img[yy, xx] = MEADOW_HI[clampi(2 + (j * 4) // max(ln, 1), 1, 6)]
            if not is_gloom and prng.random() < 0.045 and 2 <= by < h - 1 and 1 <= bx < w - 1:
                img[by - 1, bx] = prng.choice(WILDFLOWERS)

    # Occasional grass tufts on outer shoulders and grassy median strips
    for _ in range(int(span / 8.5)):
        ci = prng.randrange(own_lo, own_hi)
        if half[ci] <= 5.0:
            continue
        in_med = rut_amt[ci] > 0.68 and prng.random() < 0.42
        lateral = (prng.uniform(-0.14, 0.14) if in_med else prng.choice((-1, 1)) * prng.uniform(0.62, 0.86)) * half[ci]
        x = int(cx_local[ci] - tangents[ci, 1] * lateral)
        y = int(cy_local[ci] + tangents[ci, 0] * lateral)
        if 4 <= x < w - 4 and 6 <= y < h - 2 and keep[y, x] and not stone_drawn[y, x]:
            tuft(img, x, y, prng.randrange(2, 5), prng, MEADOW_HI[:6])
    if piece:  # keep only this piece's own stretch (the margin of the neighbours was only there so the edges match), cropped tight
        owned = near_band & (idx_map >= own_lo) & (idx_map < own_hi)
        img[~owned] = 0
        mask[~owned] = 0
        ys_o, xs_o = np.nonzero(img[..., 3] > 0)
        if len(ys_o):
            ya, yb, xa, xb = int(ys_o.min()), int(ys_o.max()) + 1, int(xs_o.min()), int(xs_o.max()) + 1
            return img[ya:yb, xa:xb].copy(), mask[ya:yb, xa:xb].copy(), (x0 + xa, y0 + ya)
    return img, mask, (x0, y0)


# ------------------------------------------------------------------ the yard of a hut
WOOD_CHIP = [hexc(c) for c in ("3a2530", "5a3c38", "8a6a58", "c4a47a")]  # split wood: the bark's violet browns, pale heartwood
GRAVEL = [hexc(c) for c in ("2d2b45", "47446a", "615d86", "7e7aa2", "a19db9", "c5c2d6")]  # stone dust and gravel of a quarry
STONE_CHIP = [hexc(c) for c in ("2d2b45", "47446a", "8581a8", "c5c2d6")]
ASH = [hexc(c) for c in ("120d16", "251d2e", "3f394f", "7f7893", "b9b2c6")]  # soot and ash
PUDDLE = [hexc(c) for c in ("2a2850", "46477c", "7d8ec4", "c6d6f2")]  # dark water holding a bit of the sky


def _segment_distance(X, Y, pts):
    """Distance of every pixel to a polyline (list of (x, y))."""
    best = np.full(X.shape, 1e9)
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        dx, dy = bx - ax, by - ay
        t = np.clip(((X - ax) * dx + (Y - ay) * dy) / max(dx * dx + dy * dy, 1e-6), 0.0, 1.0)
        best = np.minimum(best, np.hypot(X - (ax + t * dx), Y - (ay + t * dy)))
    return best


def _flat_stone(img, mask, x0, y0, cx, cy, rx, ry, seed, angle=0.0):
    """One flat stone sunk into the ground (a flagstone of the old yard): a rounded slab, a little crooked (`angle` degrees), lit from the upper left, a dark
    gap on its lower right, a few specks of moss."""
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    reach = int(max(rx, ry)) + 4
    for y in range(int(cy) - reach, int(cy) + reach + 1):
        for x in range(int(cx) - reach, int(cx) + reach + 1):
            ix, iy = x - x0, y - y0
            if not (0 <= ix < img.shape[1] and 0 <= iy < img.shape[0]):
                continue
            ux, uy = x + 0.5 - cx, y + 0.5 - cy
            dx, dy = (ux * ca + uy * sa) / rx, (-ux * sa + uy * ca) / ry
            ang = math.atan2(dy, dx)
            wob = 1.0 + 0.14 * (noise(int((ang + math.pi) * 2.6), int(cx * 3 + cy), seed) / 255.0 - 0.5) * 2.0
            d = (abs(dx) ** 3.2 + abs(dy) ** 3.2) ** (1 / 3.2) / wob
            if d > 1.0:
                continue
            lit = -(ux / rx * 0.55 + uy / ry * 0.85)  # the upper left is lit
            if d > 0.86:  # the rim: lit on the upper left, a dark gap on the lower right
                c = STONE[4] if lit > 0.25 else (MORTAR if lit < -0.15 else STONE[2])
            else:
                val = 2.7 + lit * 0.8 + (noise(x, y, seed + 3) / 255.0 - 0.5) * 1.3 + (BAYER[y % 4][x % 4] - 0.5) * 0.45
                c = STONE[clampi(int(val), 2, 4)]
                if noise(x // 2, y // 2, seed + 5) > 238:
                    c = MOSS[noise(x, y, seed + 6) // 128]
                elif noise(x, y, seed + 8) > 250:  # a crack
                    c = STONE[1]
            img[iy, ix] = c
            mask[iy, ix] = (STONE_CODE, 0, 0, 255)


def bake_yard(spec, seed):
    """The forecourt of a hut, in px relative to the hut's feet: trampled earth (`trample` ellipses [cx, cy, rx, ry, wear 0..1] and `tracks` {w, k, pts}
    worn lines, grass surviving in patches, stubble along the ragged edge), flat `slabs` [cx, cy, rx, ry] sunk into it, `puddles`, and whatever the yard
    props ask for on the ground: `ash` (a soot ring round a fire) and `chips` (split wood round a chopping block) with a radius. Returns (img, mask, (x0, y0))."""
    gravel = spec.get("palette") == "gravel"  # a quarry: cool stone dust and gravel instead of trodden earth, chips of stone instead of wood
    earth = GRAVEL if gravel else PATH
    chip_pal = STONE_CHIP if gravel else WOOD_CHIP
    ells, tracks = spec["trample"], spec.get("tracks", [])
    spots = [(p["pos"][0], p["pos"][1], p.get("ash", 0), p.get("chips", 0)) for p in spec.get("props", [])]
    xs0 = [e[0] - e[2] for e in ells] + [s[0] - s[2] for s in spec.get("slabs", [])] + [p[0] - max(p[2], p[3]) for p in spots]
    xs1 = [e[0] + e[2] for e in ells] + [s[0] + s[2] for s in spec.get("slabs", [])] + [p[0] + max(p[2], p[3]) for p in spots]
    ys0 = [e[1] - e[3] for e in ells] + [s[1] - s[3] for s in spec.get("slabs", [])] + [p[1] - max(p[2], p[3]) for p in spots]
    ys1 = [e[1] + e[3] for e in ells] + [s[1] + s[3] for s in spec.get("slabs", [])] + [p[1] + max(p[2], p[3]) for p in spots]
    for t in tracks:
        xs0 += [q[0] - t["w"] for q in t["pts"]]
        xs1 += [q[0] + t["w"] for q in t["pts"]]
        ys0 += [q[1] - t["w"] for q in t["pts"]]
        ys1 += [q[1] + t["w"] for q in t["pts"]]
    x0, y0, x1, y1 = int(min(xs0)) - 12, int(min(ys0)) - 12, int(max(xs1)) + 12, int(max(ys1)) + 12
    w, h = x1 - x0, y1 - y0
    X = np.arange(w)[None, :] + x0 + 0.5
    Y = np.arange(h)[:, None] + y0 + 0.5
    warp_x = (vnoise(w, h, 14, seed + 1) - 0.5) * 12 + (vnoise(w, h, 5, seed + 2) - 0.5) * 4
    warp_y = (vnoise(w, h, 14, seed + 3) - 0.5) * 12 + (vnoise(w, h, 5, seed + 4) - 0.5) * 4
    Xw, Yw = X + warp_x, Y + warp_y
    wear = np.zeros((h, w))
    for cx, cy, rx, ry, k in ells:
        d = np.hypot((Xw - cx) / rx, (Yw - cy) / ry)
        wear = np.maximum(wear, k * np.clip((1.0 - d) / 0.55, 0.0, 1.0))
    for t in tracks:
        d = _segment_distance(Xw, Yw, t["pts"])
        wear = np.maximum(wear, t.get("k", 0.8) * np.clip((t["w"] - d) / (t["w"] * 0.6), 0.0, 1.0))
    holes = vnoise(w, h, 7, seed + 5) * 0.65 + vnoise(w, h, 3, seed + 6) * 0.35  # grass survives in patches even where it is trampled
    wear *= 1.0 - 0.55 * np.clip((holes - 0.6) / 0.2, 0.0, 1.0)
    damp = vnoise(w, h, 18, seed + 7)  # damp, darker places
    bayer = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    keep = np.clip(wear * 1.5, 0.0, 1.0) > bayer * 0.92 + 0.05  # a solid core that thins out into the meadow
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    for y, x in zip(*np.nonzero(keep)):
        gx, gy = int(x + x0), int(y + y0)
        n = noise(gx // 2, gy // 2, 21) / 255.0
        base = 2.8 + (n - 0.5) * 1.5 + (BAYER[gy % 4][gx % 4] - 0.5) * 0.7 - 1.1 * (1.0 - min(1.0, wear[y, x] * 1.3)) - 0.9 * damp[y, x]
        c = earth[clampi(int(base), 0, 5)]
        if noise(gx, gy, 31) > 247:  # a pebble pressed in
            c = STONE[2 + (noise(gx, gy, 32) > 128)]
        img[y, x] = c
        mask[y, x] = (PATH_CODE, 0, 0, 255)
    rng = random.Random(seed)
    for _ in range(int(w * h / 70)):  # flattened, dead stubble and grass blades along the ragged edge, a few heel prints inside
        x, y = rng.randrange(2, w - 2), rng.randrange(3, h - 1)
        if 0.04 < wear[y, x] < 0.5 and not keep[y, x] and rng.random() < 0.8:
            img[y, x] = MEADOW[rng.randrange(1, 4)]
            img[y - 1, x + rng.choice((-1, 0, 1))] = MEADOW[rng.randrange(2, 5)]
            mask[y, x] = (PATH_CODE, 0, 0, 255)
        elif keep[y, x] and wear[y, x] > 0.7 and rng.random() < 0.18:
            for dx in (0, 1, 2):  # a boot: heel and sole pressed a little darker
                img[y, x + dx] = earth[clampi(rng.choice((1, 2)), 0, 5)]
    for _ in range(int(w * h / 900)):
        x, y = rng.randrange(5, w - 5), rng.randrange(8, h - 2)
        if 0.02 < wear[y, x] < 0.45 and not keep[y, x]:
            tuft(img, x, y, rng.randrange(3, 6), rng, MEADOW)
    for cx, cy, rx, ry in spec.get("puddles", []):  # a puddle that never quite dries
        for y in range(int(cy - ry) - 3, int(cy + ry) + 4):
            for x in range(int(cx - rx) - 3, int(cx + rx) + 4):
                ix, iy = x - x0, y - y0
                dd = math.hypot((x + 0.5 - cx) / (rx * (1 + 0.15 * math.sin(y * 0.9))), (y + 0.5 - cy) / ry)
                if dd > 1.35 or not (0 <= ix < w and 0 <= iy < h):
                    continue
                if dd > 1.0:  # the wet, dark rim of mud
                    if BAYER[y % 4][x % 4] < 0.6 and img[iy, ix, 3]:
                        img[iy, ix] = earth[0]
                    continue
                tone = 1 if dd > 0.72 else 0
                tone += 1 if (y + 0.5 - cy) < -ry * 0.1 else 0  # the far edge catches the light
                if noise(x, y, 61) > 238:
                    tone = 3
                img[iy, ix] = PUDDLE[clampi(tone, 0, 3)]
                mask[iy, ix] = (PATH_CODE, 0, 0, 255)
    for i, slab_spec in enumerate(spec.get("slabs", [])):
        _flat_stone(img, mask, x0, y0, *slab_spec[:4], seed + 100 + i * 7, slab_spec[4] if len(slab_spec) > 4 else 0.0)
    for px, py, ash, chips in spots:
        for _ in range(int(ash * ash * 0.8)):  # soot and ash round the fire, the ring of sooty earth lighter outwards
            ang, dist = rng.uniform(0, math.tau), ash * math.sqrt(rng.random()) * (1 + 0.1 * math.sin(rng.uniform(0, 9)))
            x, y = int(px + math.cos(ang) * dist - x0), int(py + math.sin(ang) * dist * 0.62 - y0)
            if 0 <= x < w and 0 <= y < h and img[y, x, 3] and mask[y, x, 0] != STONE_CODE:
                k = dist / ash
                img[y, x] = ASH[clampi(int(k * 2.6 + rng.random() * 1.6), 0, 4)]
                if rng.random() < 0.5 and x + 1 < w:
                    img[y, x + 1] = ASH[clampi(int(k * 2.2 + rng.random() * 1.4), 0, 4)]
        for _ in range(int(chips * chips * 0.35)):  # split wood, bark scraps and pale chips round a chopping block
            ang, dist = rng.uniform(0, math.tau), chips * rng.random() ** 0.6
            x, y = int(px + math.cos(ang) * dist - x0), int(py + math.sin(ang) * dist * 0.6 - y0)
            if 0 <= x < w - 3 and 0 <= y < h - 2 and img[y, x, 3] and mask[y, x, 0] != STONE_CODE:
                c = chip_pal[rng.choice((0, 1, 2, 3, 3, 2))]
                img[y, x] = c
                if rng.random() < 0.55:
                    img[y, x + 1] = chip_pal[rng.randrange(0, 3)]
                if rng.random() < 0.25:
                    img[y + 1, x] = chip_pal[rng.randrange(0, 3)]
    return img, mask, (x0, y0)


# ------------------------------------------------------------------ output
def save(path, arr):
    from PIL import Image
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr).save(path)


def preview(items, path):
    xs0 = min(o[0] for _, _, o in items)
    ys0 = min(o[1] for _, _, o in items)
    xs1 = max(o[0] + im.shape[1] for im, _, o in items)
    ys1 = max(o[1] + im.shape[0] for im, _, o in items)
    bg = np.zeros((ys1 - ys0, xs1 - xs0, 4), dtype=np.uint8)
    bg[:, :] = (*MEADOW[2][:3], 255)
    for im, _, (ox, oy) in items:
        a = im[:, :, 3:4] / 255.0
        sub = bg[oy - ys0:oy - ys0 + im.shape[0], ox - xs0:ox - xs0 + im.shape[1], :3]
        sub[:] = (sub * (1 - a) + im[:, :, :3] * a).astype(np.uint8)
    save(path, np.kron(bg, np.ones((2, 2, 1), dtype=np.uint8)))


def gloom_tone(img, top_left):
    """Darkens a decal where the Hexenwald's ground is dark (python twin of src/world/biome_blend.gd: smoothstep over 48 tiles from the old land),
    so a path that runs from the meadow into the dark wood does not glow against it. top_left = the decal's corner in world px."""
    from PIL import Image
    rel = np.asarray(Image.open(ROOT / "assets" / "world" / "relief.png").convert("RGBA"))
    hexm = rel[..., 3] == 205
    cur = (rel[..., 3] > 0) & ~hexm
    dist = np.full(hexm.shape, 99.0)
    dist[cur] = 0.0
    for i in range(1, 49):
        nxt = cur.copy()
        nxt[1:] |= cur[:-1]; nxt[:-1] |= cur[1:]; nxt[:, 1:] |= cur[:, :-1]; nxt[:, :-1] |= cur[:, 1:]
        dist[nxt & ~cur] = i
        cur = nxt
    t = np.clip(dist / 48.0, 0.0, 1.0)
    gloom = np.where(hexm, t * t * (3 - 2 * t), 0.0)
    h, w = img.shape[:2]
    ty = np.clip((np.arange(h) + top_left[1]) // 16, 0, gloom.shape[0] - 1)
    tx = np.clip((np.arange(w) + top_left[0]) // 16, 0, gloom.shape[1] - 1)
    g = gloom[np.ix_(ty, tx)][..., None]
    dark = np.array([0.48, 0.56, 0.62])
    img[..., :3] = np.where(img[..., 3:4] > 0, img[..., :3] * (1.0 - g + g * dark), img[..., :3]).astype(np.uint8)


def cut_under_stones(img, mask, offset, stones):
    """A path does not grow on flagstones: wherever a stone field lies over it (and one pixel around each stone, so no slivers of
    path peek out between them), the path is gone. It looks as if the stones lie over it and it comes out from under them."""
    h, w = img.shape[:2]
    covered = np.zeros((h, w), dtype=bool)
    for simg, _, (sx, sy) in stones:
        x0, y0 = max(offset[0], sx), max(offset[1], sy)
        x1, y1 = min(offset[0] + w, sx + simg.shape[1]), min(offset[1] + h, sy + simg.shape[0])
        if x1 <= x0 or y1 <= y0:
            continue
        solid = simg[y0 - sy:y1 - sy, x0 - sx:x1 - sx, 3] > 0
        covered[y0 - offset[1]:y1 - offset[1], x0 - offset[0]:x1 - offset[0]] |= solid
    grown = covered.copy()
    grown[1:, :] |= covered[:-1, :]
    grown[:-1, :] |= covered[1:, :]
    grown[:, 1:] |= covered[:, :-1]
    grown[:, :-1] |= covered[:, 1:]
    img[grown] = 0
    mask[grown] = 0


def bake_barrier(spec, data, centre):
    """The invisible walls that keep her near the footpath at the start of the story (and the tiles where no berries grow, so nothing
    heals her there): the allowed ground is the union of discs (radius `half`) along the listed paths and of the stone fields' rectangles
    (padded by `pad`); the walls are a 2 cell thick shell around it, merged into rectangles. Returns ({"rects": [[x, y, w, h]] in world px},
    {"berry_free": [[tx0, ty0, tx1, ty1]] tile runs of the allowed ground, grown by 4 tiles})."""
    half, pad, cell = float(spec["half"]), float(spec.get("pad", 24)), int(spec.get("cell", 8))
    curves = []
    for path in data["paths"]:
        if path["id"] in spec["paths"]:
            curves.append(catmull(path["points"], 4.0))
    rects = [r for f in data.get("stone_fields", []) for r in f["rects"]]
    xs = [c[:, 0] for c in curves]
    ys = [c[:, 1] for c in curves]
    x0 = int(min([a.min() for a in xs] + [r[0] for r in rects]) - half - pad - 4 * cell)
    x1 = int(max([a.max() for a in xs] + [r[2] for r in rects]) + half + pad + 4 * cell)
    y0 = int(min([a.min() for a in ys] + [r[1] for r in rects]) - half - pad - 4 * cell)
    y1 = int(max([a.max() for a in ys] + [r[3] for r in rects]) + half + pad + 4 * cell)
    x0, y0 = x0 // cell * cell, y0 // cell * cell
    gw, gh = (x1 - x0) // cell + 2, (y1 - y0) // cell + 2
    allowed = np.zeros((gh, gw), dtype=bool)
    gx = (np.arange(gw) * cell + x0 + cell / 2.0)[None, :]
    gy = (np.arange(gh) * cell + y0 + cell / 2.0)[:, None]
    for curve in curves:
        for px, py in curve[::2]:
            lo_x, hi_x = int((px - half - x0) // cell), int((px + half - x0) // cell) + 1
            lo_y, hi_y = int((py - half - y0) // cell), int((py + half - y0) // cell) + 1
            sub = (gx[:, max(lo_x, 0):hi_x] - px) ** 2 + (gy[max(lo_y, 0):hi_y, :] - py) ** 2 <= half * half
            allowed[max(lo_y, 0):hi_y, max(lo_x, 0):hi_x] |= sub
    for (ax, ay, bx, by) in rects:
        allowed |= (gx >= ax - pad) & (gx <= bx + pad) & (gy >= ay - pad) & (gy <= by + pad)

    def grow(mask, n):
        out = mask.copy()
        for _ in range(n):
            nxt = out.copy()
            nxt[1:, :] |= out[:-1, :]
            nxt[:-1, :] |= out[1:, :]
            nxt[:, 1:] |= out[:, :-1]
            nxt[:, :-1] |= out[:, 1:]
            out = nxt
        return out

    shell = grow(allowed, 2) & ~allowed
    runs = {}
    out = []
    for gy_i in range(gh):  # runs along x, merged downwards when two rows have the same run
        row_runs = []
        x = 0
        while x < gw:
            if shell[gy_i, x]:
                start = x
                while x < gw and shell[gy_i, x]:
                    x += 1
                row_runs.append((start, x))
            else:
                x += 1
        new_runs = {}
        for run in row_runs:
            new_runs[run] = runs.pop(run) if run in runs else gy_i
        for run, start_row in runs.items():
            out.append((run[0], start_row, run[1], gy_i))
        runs = new_runs
    for run, start_row in runs.items():
        out.append((run[0], start_row, run[1], gh))
    walls = [[centre[0] + x0 + a * cell, centre[1] + y0 + b * cell, (c - a) * cell, (d - b) * cell] for a, b, c, d in out]
    free = grow(allowed, 4 * cell // cell if cell >= 4 else 4)  # (4 cells of 8 px is small: berries stay away by whole tiles below)
    tiles = {}
    for gy_i, gx_i in zip(*np.nonzero(allowed)):
        wx, wy = centre[0] + x0 + gx_i * cell, centre[1] + y0 + gy_i * cell
        tiles[(int(wx // 16), int(wy // 16))] = True
    cells = set(tiles)
    for (tx, ty) in list(tiles):
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                cells.add((tx + dx, ty + dy))
    by_row = {}
    for tx, ty in cells:
        by_row.setdefault(ty, []).append(tx)
    berry_free = []
    for ty, txs in sorted(by_row.items()):
        txs.sort()
        start = prev = txs[0]
        for tx in txs[1:]:
            if tx != prev + 1:
                berry_free.append([start, ty, prev, ty])
                start = tx
            prev = tx
        berry_free.append([start, ty, prev, ty])
    return {"id": spec["id"], "rects": walls}, {"berry_free": berry_free}


def main():
    data = json.load(open(ROOT / "data" / "ground.json"))
    world = json.load(open(ROOT / "data" / "world_map.json"))
    sx, sy = world["start"]
    centre = (sx * 16 + 8, sy * 16 + 8)
    seed = int(data.get("seed", 1))
    only_path = next((a[7:] for a in sys.argv[1:] if a.startswith("--path=")), "")  # bakes just that path (e.g. hexenwald_path) and merges it into data/ground_baked.json
    only_paths = "--paths" in sys.argv  # quick rebuild of all paths in data/ground.json (with stone_fields cut-out & gloom)
    if only_path or only_paths:
        baked_json = ROOT / "data" / "ground_baked.json"
        out = json.loads(baked_json.read_text(encoding="utf-8"))
        by_id = {d["id"]: d for d in out.get("decals", [])}
        loaded_stones = []
        for sf in data.get("stone_fields", []):
            d_sf = by_id.get(sf["id"])
            sf_path = ROOT / "assets" / "world" / "ground" / (sf["id"] + ".png")
            if d_sf and sf_path.exists():
                loaded_stones.append((load_png(str(sf_path)), None, (int(d_sf["x"]) - centre[0], int(d_sf["y"]) - centre[1])))
        targets = [(i, p) for i, p in enumerate(data["paths"]) if (not only_path or p["id"] == only_path or p["id"].startswith(only_path))]
        rebuilt = {}
        for i, spec in targets:
            glow_img = None
            if spec.get("quartz_caravan"):
                img, mask, (ox, oy), glow_img = bake_quartz_caravan_path(spec, seed + i * 101 + 7, centre)
            else:
                img, mask, (ox, oy) = bake_path(spec, seed + i * 101 + 7, centre)
            if loaded_stones:
                cut_under_stones(img, mask, (ox, oy), loaded_stones)
            if spec.get("gloom"):
                gloom_tone(img, (centre[0] + ox, centre[1] + oy))
            save(ROOT / "assets" / "world" / "ground" / (spec["id"] + ".png"), img)
            save(ROOT / "assets" / "world" / "ground" / (spec["id"] + "_mask.png"), mask)
            entry_d = {
                "id": spec["id"],
                "texture": "res://assets/world/ground/%s.png" % spec["id"],
                "mask": "res://assets/world/ground/%s_mask.png" % spec["id"],
                "x": centre[0] + ox,
                "y": centre[1] + oy,
            }
            if glow_img is not None and np.any(glow_img[..., 3] > 0):
                save(ROOT / "assets" / "world" / "ground" / (spec["id"] + "_glow.png"), glow_img)
                entry_d["glow"] = "res://assets/world/ground/%s_glow.png" % spec["id"]
            rebuilt[spec["id"]] = entry_d
            print("baked", spec["id"], img.shape[1], "x", img.shape[0])
        kept = []
        seen = set()
        for d in out.get("decals", []):
            did = d["id"]
            if did in rebuilt:
                kept.append(rebuilt[did])
                seen.add(did)
            else:
                kept.append(d)
        for did, entry in rebuilt.items():
            if did not in seen:
                kept.append(entry)
        out["decals"] = kept
        payload = json.dumps(out, separators=(",", ":"))
        tmp_json = ROOT / "data" / "ground_baked.json.tmp"
        tmp_json.write_text(payload, encoding="utf-8")
        os.replace(tmp_json, baked_json)
        return
    only_yards = "--yards" in sys.argv  # quick rebuild of the hut yards alone: the rest of data/ground_baked.json stays as it is
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    baked, shown, yards = [], [], []
    jobs = [] if only_yards else [("stone_fields", bake_stone_field), ("paths", bake_path)]
    stones = []
    for key, fn in jobs:
        for i, spec in enumerate(data.get(key, [])):
            glow_img = None
            if key == "paths" and spec.get("quartz_caravan"):
                img, mask, (ox, oy), glow_img = bake_quartz_caravan_path(spec, seed + i * 101 + 7, centre)
            else:
                img, mask, (ox, oy) = fn(spec, seed + i * 101 + (7 if key == "paths" else 0), centre)
            if key == "stone_fields":
                stones.append((img, mask, (ox, oy)))
            else:
                cut_under_stones(img, mask, (ox, oy), stones)
                if spec.get("gloom"):
                    gloom_tone(img, (centre[0] + ox, centre[1] + oy))
            save(ROOT / "assets" / "world" / "ground" / (spec["id"] + ".png"), img)
            if glow_img is not None and np.any(glow_img[..., 3] > 0):
                save(ROOT / "assets" / "world" / "ground" / (spec["id"] + "_glow.png"), glow_img)
            save(ROOT / "assets" / "world" / "ground" / (spec["id"] + "_mask.png"), mask)
            baked.append({"id": spec["id"], "texture": "res://assets/world/ground/%s.png" % spec["id"], "mask": "res://assets/world/ground/%s_mask.png" % spec["id"], "x": centre[0] + ox, "y": centre[1] + oy})
            shown.append((img, mask, (ox, oy)))
            print("baked", spec["id"], img.shape[1], "x", img.shape[0])
    places = data.get("huts", []) + data.get("quarries", [])
    order = [p for p in places if "seed_index" not in p.get("yard", {})]  # later yards carry their own seed_index, so adding one never reshuffles the older ones
    for hut in places:  # the forecourt of each hut and the gravel of each quarry (px relative to its tile's centre)
        if "yard" not in hut:
            continue
        i = hut["yard"].get("seed_index", order.index(hut) if hut in order else 0)
        img, mask, (ox, oy) = bake_yard(hut["yard"], seed + 900 + i * 13)
        if hut["yard"].get("gloom"):  # a yard in the Hexenwald (the lake witch's) is darkened like its paths
            gloom_tone(img, (hut["tile"][0] * 16 + 8 + ox, hut["tile"][1] * 16 + 8 + oy))
        name = hut["id"] + "_yard"
        save(ROOT / "assets" / "world" / "ground" / (name + ".png"), img)
        save(ROOT / "assets" / "world" / "ground" / (name + "_mask.png"), mask)
        feet = (hut["tile"][0] * 16 + 8, hut["tile"][1] * 16 + 8)
        baked.append({"id": name, "texture": "res://assets/world/ground/%s.png" % name, "mask": "res://assets/world/ground/%s_mask.png" % name, "x": feet[0] + ox, "y": feet[1] + oy})
        yards.append((img, mask, (ox, oy)))
        print("baked", name, img.shape[1], "x", img.shape[0])
    for i, arena in enumerate(data.get("arenas", [])):  # stone floors of the boss arenas (polygon in px relative to the arena tile's centre)
        img, mask, (ox, oy) = bake_arena(arena, seed + 1300 + i * 17)
        name = arena["id"] + "_arena"
        save(ROOT / "assets" / "world" / "ground" / (name + ".png"), img)
        save(ROOT / "assets" / "world" / "ground" / (name + "_mask.png"), mask)
        save(ROOT / "assets" / "world" / "ground" / (name + "_glow.png"), ARENA_GLOW[arena["id"]])
        zone, (zx, zy) = bake_arena_zone(arena)
        save(ROOT / "assets" / "world" / "ground" / (name + "_zone.png"), zone)
        feet = (arena["tile"][0] * 16 + 8, arena["tile"][1] * 16 + 8)
        baked.append({"zone": "res://assets/world/ground/%s_zone.png" % name, "zone_x": feet[0] + zx, "zone_y": feet[1] + zy, "id": name, "texture": "res://assets/world/ground/%s.png" % name, "mask": "res://assets/world/ground/%s_mask.png" % name, "glow": "res://assets/world/ground/%s_glow.png" % name, "x": feet[0] + ox, "y": feet[1] + oy})
        yards.append((img, mask, (ox, oy)))
        print("baked", name, img.shape[1], "x", img.shape[0])
    if only_yards:
        out = json.load(open(ROOT / "data" / "ground_baked.json"))
        out["decals"] = [d for d in out["decals"] if not (d["id"].endswith("_yard") or d["id"].endswith("_arena"))] + baked
        json.dump(out, open(ROOT / "data" / "ground_baked.json", "w"), separators=(",", ":"))
        if args and yards:
            preview(yards, pathlib.Path(args[0]))
        return
    out = {"decals": baked}
    if "manhole" in data:
        out["manhole"] = [centre[0] + data["manhole"][0], centre[1] + data["manhole"][1]]
    if "barrier" in data:
        barrier, free = bake_barrier(data["barrier"], data, centre)
        out["barriers"] = [barrier]
        out.update(free)
        print("barrier", len(barrier["rects"]), "rects; berry-free runs", len(free["berry_free"]))
    json.dump(out, open(ROOT / "data" / "ground_baked.json", "w"), separators=(",", ":"))
    if args:
        preview(shown, pathlib.Path(args[0]))
        if yards:
            preview(yards, pathlib.Path(args[0]).with_name(pathlib.Path(args[0]).stem + "_yard.png"))


if __name__ == "__main__":
    main()
