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


def bake_path(spec, seed, centre):
    width = float(spec.get("width", 26))
    curve = catmull(spec["points"])
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    total = arc[-1]
    margin = int(width) + 14
    x0, y0 = int(curve[:, 0].min()) - margin, int(curve[:, 1].min()) - margin
    x1, y1 = int(curve[:, 0].max()) + margin, int(curve[:, 1].max()) + margin
    w, h = x1 - x0, y1 - y0
    rng = np.random.default_rng(seed)
    phase = rng.random(8) * math.tau
    # width and "grassiness" along the path
    half = np.array([width * 0.5 * (0.88 + 0.22 * math.sin(a / 47.0 + phase[0]) + 0.1 * math.sin(a / 19.0 + phase[1])) for a in arc])
    taper_in = np.clip(arc / float(spec.get("taper_in", 0.0) or 1.0), 0.0, 1.0) if spec.get("taper_in", 0) else np.ones_like(arc)
    taper_out = np.clip((total - arc) / float(spec.get("taper_out", 70.0)), 0.0, 1.0)
    half = half * np.minimum(taper_in, 0.25 + 0.75 * taper_out)
    grass = np.array([0.5 + 0.5 * math.sin(a / 33.0 + phase[2]) * math.sin(a / 71.0 + phase[3]) for a in arc])
    tangents = np.gradient(curve, axis=0)
    tangents /= np.linalg.norm(tangents, axis=1)[:, None] + 1e-9
    edge_noise = vnoise(w, h, 5, seed + 11) - 0.5
    pebble_noise = vnoise(w, h, 2, seed + 12)
    img = np.zeros((h, w, 4), dtype=np.uint8)
    mask = np.zeros((h, w, 4), dtype=np.uint8)
    light = np.array([-0.7, -0.7])
    prng = random.Random(seed)
    for y in range(h):
        py = y + y0 + 0.5
        px = np.arange(w) + x0 + 0.5
        dx = px[:, None] - curve[None, :, 0]
        dy = py - curve[None, :, 1]
        d2 = dx * dx + dy * dy
        idx = np.argmin(d2, axis=1)
        d = np.sqrt(d2[np.arange(w), idx])
        hw = half[idx]
        t = d / np.maximum(hw, 0.5) + edge_noise[y] * 0.5
        vx = (px - curve[idx, 0]) / np.maximum(d, 1e-6)
        vy = (py - curve[idx, 1]) / np.maximum(d, 1e-6)
        side = vx * light[0] + vy * light[1]  # >0: on the lit side (north-west) of the line
        lat = vx * (-tangents[idx, 1]) + vy * tangents[idx, 0]  # signed sideways offset, -1 .. 1 times t
        for x in range(w):
            tt = t[x]
            if tt >= 1.0 or hw[x] < 1.0:
                continue
            gx, gy = x + x0, y + y0
            b = BAYER[gy % 4][gx % 4]
            cover = 1.0 - max(0.0, tt - 0.55) / 0.45  # the edge thins out into the meadow
            cover *= 1.0 - 0.55 * grass[idx[x]] * min(1.0, tt * 1.4)  # grass grows through in places
            if cover <= b * 0.95 + 0.04 * (noise(gx, gy, 3) / 255.0):
                continue
            n = noise(gx // 2, gy // 2, 21) / 255.0
            base = 2.75 + (n - 0.5) * 1.6 + (b - 0.5) * 0.7 - 0.7 * tt
            if tt > 0.72:  # the path lies a little sunk: shade on the north-west bank, a light rim on the other side
                base += -0.9 if side[x] > 0.25 else (0.5 if side[x] < -0.25 else 0.0)
            wear = abs(abs(lat[x]) * d[x] - 0.3 * hw[x]) < 0.8 and tt < 0.7  # two faint wear lines
            if wear:
                base -= 0.7
            c = PATH[clampi(int(base), 0, 5)]
            pn = pebble_noise[y, x]
            if pn > 0.88 and noise(gx, gy, 5) > 140:  # a pebble
                c = STONE[2 + (noise(gx, gy, 6) > 128)] if (gx + gy) % 2 else PATH[5]
            img[y, x] = c
            if tt < 0.85:
                mask[y, x] = (PATH_CODE, 0, 0, 255)
    for _ in range(int(total / 9)):  # tufts of grass here and there on the path itself
        i = prng.randrange(len(curve))
        lateral = prng.uniform(-0.8, 0.8) * half[i]
        x = int(curve[i, 0] - tangents[i, 1] * lateral - x0)
        y = int(curve[i, 1] + tangents[i, 0] * lateral - y0)
        if 4 <= x < w - 4 and 6 <= y < h - 2 and img[y, x, 3] and half[i] > 4:
            tuft(img, x, y, prng.randrange(2, 5), prng, MEADOW)
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
    h, w = arr.shape[:2]
    path.parent.mkdir(parents=True, exist_ok=True)
    write_png(path, w, h, [[tuple(int(v) for v in arr[y, x]) for x in range(w)] for y in range(h)])


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
    if only_path:
        i, spec = next((i, p) for i, p in enumerate(data["paths"]) if p["id"] == only_path)
        img, mask, (ox, oy) = bake_path(spec, int(data.get("seed", 1)) + i * 101 + 7, centre)
        if spec.get("gloom"):
            gloom_tone(img, (centre[0] + ox, centre[1] + oy))
        save(ROOT / "assets" / "world" / "ground" / (spec["id"] + ".png"), img)
        save(ROOT / "assets" / "world" / "ground" / (spec["id"] + "_mask.png"), mask)
        entry = {"id": spec["id"], "texture": "res://assets/world/ground/%s.png" % spec["id"], "mask": "res://assets/world/ground/%s_mask.png" % spec["id"], "x": centre[0] + ox, "y": centre[1] + oy}
        out = json.load(open(ROOT / "data" / "ground_baked.json"))
        out["decals"] = [d for d in out["decals"] if d["id"] != spec["id"]] + [entry]
        json.dump(out, open(ROOT / "data" / "ground_baked.json", "w"), separators=(",", ":"))
        print("baked", spec["id"], img.shape[1], "x", img.shape[0])
        return
    only_yards = "--yards" in sys.argv  # quick rebuild of the hut yards alone: the rest of data/ground_baked.json stays as it is
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    baked, shown, yards = [], [], []
    jobs = [] if only_yards else [("stone_fields", bake_stone_field), ("paths", bake_path)]
    stones = []
    for key, fn in jobs:
        for i, spec in enumerate(data.get(key, [])):
            img, mask, (ox, oy) = fn(spec, seed + i * 101 + (7 if key == "paths" else 0), centre)
            if key == "stone_fields":
                stones.append((img, mask, (ox, oy)))
            else:
                cut_under_stones(img, mask, (ox, oy), stones)
                if spec.get("gloom"):
                    gloom_tone(img, (centre[0] + ox, centre[1] + oy))
            save(ROOT / "assets" / "world" / "ground" / (spec["id"] + ".png"), img)
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
