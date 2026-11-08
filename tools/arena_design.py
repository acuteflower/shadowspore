#!/usr/bin/env python3
"""The carved designs and the rubble of the boss arena's floor (called by `bake_arena` in tools/bake_ground.py; numpy, deterministic).

Mornath was a sun eagle of the High Spire's order, so the old floor is a consecrated sun sigil: a hub with a lit core, rings of polished stone with carved runes,
sixteen rays, and three ley lines that run from the sigil to the three pillars, whose feet stand on round slabs with a ring of runes. The void is eating it:
cracks of violet run out of the middle. Along the edge a chequered frieze runs a hand's width inside the lip. Everything is inlaid in the same dim teal
the pillars' veins have; the same pixels go into a glow picture that the level draws unlit and brighter at night.

`design(spec, X, Y, sd, seed)` -> (paint [h, w, 4] uint8, glow [h, w, 4] uint8, solid [h, w] bool): the pixels of the design (alpha 255 where it replaces the flagstone).
`rubble(img, keep, top, sd, spec, X, Y, seed)` lays chips and broken slabs onto `img` in place (only where the floor is `keep`).
Ground circles are drawn squashed (`SQ`) like everything in the 3/4 view.
Contact picture: `python3 tools/arena_design.py out.png` (the arena on its own, flat grey beside it).
"""
import math
import pathlib
import random
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_arena_pillars import CRY_D, CRY_M, P, TEAL, TEAL_L, VIO, VIO_L  # noqa: E402

SQ = 0.7
TAU = math.tau
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
GROOVE = (22, 19, 38)
CRACK = (26, 17, 46)
CRACK_SPECK = (75, 47, 154)
CRY_BRIGHT = (60, 160, 160)  # inlaid light that is dim but readable on the dark floor


def _hash(a, b, s=0):
    n = (np.asarray(a, dtype=np.int64) * 374761393 + np.asarray(b, dtype=np.int64) * 668265263 + s * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def sigil_centre(spec):
    return tuple(spec.get("sigil", [26, -48]))


def design(spec, X, Y, sd, seed):
    h, w = sd.shape
    sd = -sd  # bake_arena's field is negative inside: from here on `sd` is the depth inside the lip
    X = np.broadcast_to(X, (h, w))
    Y = np.broadcast_to(Y, (h, w))
    bay = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    paint = np.zeros((h, w, 4), dtype=np.uint8)
    solid = np.zeros((h, w), dtype=bool)  # where the floor must exist (the sigil and the slabs are never cut by a hole of grass)
    glow = np.zeros((h, w, 4), dtype=np.uint8)
    cx, cy = sigil_centre(spec)
    dx, dy = X - cx, (Y - cy) / SQ
    r = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    solid |= r < 72.0

    def put(mask, colour):
        paint[mask] = (*colour, 255)

    def lit(mask, hi, lo):
        """A polished surface: mostly `lo`, `hi` towards the upper left (a soft dithered gradient, not noise)."""
        tone = (bay * 0.5 - (dx + dy) * 0.012) > 0.12
        paint[mask & ~tone] = (*hi, 255)
        paint[mask & tone] = (*lo, 255)

    def inlay(mask, strength=1.0, tone=0):
        """Dim teal in the picture, the same pixels (a touch brighter) in the glow picture."""
        base = np.where(bay > 0.3, 1, 0)[..., None] * np.array(CRY_BRIGHT) + np.where(bay > 0.3, 0, 1)[..., None] * np.array(CRY_M)
        paint[mask] = np.concatenate([base[mask], np.full((int(mask.sum()), 1), 255)], axis=1).astype(np.uint8)
        glow[mask] = (*TEAL, int(200 * strength))

    # --- the sigil -----------------------------------------------------------------------------------------------
    for ring_r, width in ((16.0, 0.9), (34.0, 0.9), (36.0, 0.6), (46.0, 0.9), (65.0, 1.1)):
        put(np.abs(r - ring_r) < width, GROOVE)
    hub = r < 9.0
    lit(hub, P[5], P[4])
    put(np.abs(r - 9.5) < 0.9, GROOVE)
    inlay(r < 3.4)
    glow[r < 3.4] = (*TEAL_L, 230)
    inlay((np.abs(r - 6.2) < 0.55) & (np.sin(th * 8.0) > -0.2))  # a broken ring round the core
    # the inner band: sixteen rays, long and short in turn, tapering to a point
    for k in range(16):
        ang = k * TAU / 16.0 + TAU / 32.0
        da = np.abs((th - ang + math.pi) % TAU - math.pi)
        perp = da * r
        long_ray = k % 2 == 0
        r0, r1 = 17.0, 33.0 if long_ray else 26.0
        t = np.clip((r - r0) / (r1 - r0), 0.0, 1.0)
        half = (2.6 if long_ray else 1.9) * (1.0 - t) + 0.35
        inlay((r >= r0) & (r <= r1) & (perp < half) & (da < 1.0))
    # the polished band with runes
    band = (r > 36.6) & (r < 45.4)
    lit(band, P[4], P[3])
    sector = np.floor((th + math.pi) / TAU * 24.0).astype(np.int64)
    a = ((th + math.pi) / TAU * 24.0) % 1.0 - 0.5
    rr = r - 41.0
    glyph = _hash(sector, 3, seed % 97)
    bar = (np.abs(a) < 0.07) & (np.abs(rr) < 3.6)
    cross = (np.abs(rr) < 0.55) & (np.abs(a) < 0.2)
    dots = ((np.abs(a - 0.16) < 0.05) | (np.abs(a + 0.16) < 0.05)) & (np.abs(rr) < 0.9)
    diag = np.abs(a * 8.0 - rr * 0.5) < 0.35
    rune = np.where(glyph < 0.25, bar, np.where(glyph < 0.5, bar | cross, np.where(glyph < 0.75, dots | (np.abs(a) < 0.05) & (np.abs(rr) < 2.2), diag & (np.abs(rr) < 3.2))))
    inlay(band & rune, 0.85)
    # the outer band: fine radial lines of light between two grooves, and a dashed thread of light on the outside
    for k in range(48):
        ang = k * TAU / 48.0
        da = np.abs((th - ang + math.pi) % TAU - math.pi)
        reach = 64.0 if k % 2 == 0 else 58.0
        inlay((r > 47.5) & (r < reach) & (da * r < 0.62), 0.7)
    inlay((np.abs(r - 68.0) < 0.5) & (np.sin(th * 40.0) > 0.0), 0.8)

    # --- under the pillars: a round slab with a ring of runes, and a ley line to the sigil ----------------------------
    for pil in spec.get("pillars", []):
        px, py = pil["pos"][0], pil["pos"][1]
        py_c = py - 5.0  # the footprint's middle lies behind the feet row (the plinth is about 14 px deep)
        pdx, pdy = X - px, (Y - py_c) / SQ
        pr = np.hypot(pdx, pdy)
        plate = pr < 24.0
        solid |= pr < 27.0
        lip = (np.hypot(pdx, (Y - (py_c + 3.0)) / SQ) < 24.0) & ~plate  # the slab is raised: a dark front edge three pixels deep
        put(lip, P[1])
        put(lip & (np.hypot(pdx, (Y - (py_c + 3.0)) / SQ) > 22.5), GROOVE)
        lit(plate, P[3], P[2])
        pth0 = np.arctan2(pdy, pdx)
        put(plate & (np.abs(pr - 14.0) < 0.7), GROOVE)
        put(plate & (pr > 6.0) & (np.abs(np.sin(pth0 * 4.0)) * pr < 0.8), GROOVE)  # eight slabs
        put((pr > 22.0) & plate & ((pdx + pdy) < 0), P[5])  # a lit rim at the upper left
        put(plate & (pr > 23.0), GROOVE)
        # the contact shadow round the foot of the pillar
        shade = ((X - px) / 18.0) ** 2 + ((Y - (py - 3.0)) / 7.0) ** 2 < 1.0
        paint[shade & (bay > 0.35)] = (*GROOVE, 255)
        pth = np.arctan2(pdy, pdx)
        inlay((np.abs(pr - 28.0) < 0.6) & (np.sin(pth * 10.0 + 0.4) > 0.15), 0.8)
        # (the sprite covers the middle of the plate, so the runes sit on the outer ring)
        # the ley line
        vx, vy = cx - px, (cy - py_c) / SQ
        length = math.hypot(vx, vy)
        ux, uy = vx / length, vy / length
        t = pdx * ux + pdy * uy
        perp = np.abs(-pdx * uy + pdy * ux)
        span = (t > 31.0) & (t < length - 70.0)
        put(span & (perp > 1.6) & (perp < 2.5), GROOVE)
        inlay(span & (perp < 0.8) & (np.floor(t / 5.0) % 4 != 3), 0.9)

    # --- the void is eating the sigil: cracks run out of the middle -------------------------------------------------
    rng = random.Random(seed + 77)
    for k in range(7):
        ang = rng.random() * TAU
        x, y = cx + math.cos(ang) * 18.0, cy + math.sin(ang) * 18.0 * SQ
        width = 2.2
        for step in range(rng.randrange(14, 34)):
            ang += rng.uniform(-0.5, 0.5)
            x += math.cos(ang) * 3.0
            y += math.sin(ang) * 3.0 * SQ
            width = max(0.6, width - 0.05)
            near = (np.abs(X - x) < width + 1) & (np.abs(Y - y) < width * SQ + 1)
            hit = near & ((X - x) ** 2 + ((Y - y) / SQ) ** 2 < width * width)
            paint[hit] = (*CRACK, 255)
            speck = hit & (_hash(X.astype(np.int64), Y.astype(np.int64), 5) > 0.82)
            paint[speck] = (*CRACK_SPECK, 255)
            glow[speck] = (*VIO, 190)
            if rng.random() < 0.12:
                branch = ang + rng.choice((-1.0, 1.0)) * 0.9
                bx, by = x, y
                for _ in range(rng.randrange(3, 7)):
                    bx += math.cos(branch) * 2.5
                    by += math.sin(branch) * 2.5 * SQ
                    bh = (np.abs(X - bx) < 1.4) & (np.abs(Y - by) < 1.4) & ((X - bx) ** 2 + ((Y - by) / SQ) ** 2 < 1.2)
                    paint[bh] = (*CRACK, 255)
    # --- a chequered frieze a hand's width inside the lip -----------------------------------------------------------
    frieze = (sd > 7.0) & (sd < 10.5)
    cell = ((np.floor(X / 3.0) + np.floor(Y / 3.0)) % 2) == 0
    lit(frieze & cell, P[5], P[4])
    put(frieze & ~cell, P[1])
    put((sd > 6.0) & (sd <= 7.0), GROOVE)
    put((sd >= 10.5) & (sd < 11.4), GROOVE)
    # --- old and worn: the design breaks up in patches ---------------------------------------------------------------
    worn = _hash(np.floor(X / 3.0).astype(np.int64), np.floor(Y / 3.0).astype(np.int64), 9) > 0.93
    worn |= _hash(X.astype(np.int64), Y.astype(np.int64), 13) > 0.985
    paint[worn] = 0
    glow[worn] = 0
    return paint, glow, solid


def _chip(img, x, y, size, rng, keep):
    """A broken piece of stone: a lit top left, a mid face, a dark right and bottom, a drop of shadow on the floor."""
    h, w = img.shape[0], img.shape[1]
    sw, sh = size, max(2, int(size * 0.7))
    shape = [(i, j) for j in range(sh) for i in range(sw) if (i - sw / 2.0 + 0.5) ** 2 / (sw / 2.0) ** 2 + (j - sh / 2.0 + 0.5) ** 2 / (sh / 2.0) ** 2 < rng.uniform(0.7, 1.15)]
    cells = set(shape)
    for (i, j) in shape:
        xx, yy = x + i, y + j
        if not (0 <= xx < w and 0 <= yy < h) or not keep[yy, xx]:
            continue
        top_left = (i - 1, j) not in cells or (i, j - 1) not in cells
        bottom_right = (i + 1, j) not in cells or (i, j + 1) not in cells
        img[yy, xx] = (*(P[5] if top_left else (P[1] if bottom_right else P[3])), 255)
    for (i, j) in shape:
        xx, yy = x + i + 1, y + j + 1
        if 0 <= xx < w and 0 <= yy < h and keep[yy, xx] and (i + 1, j + 1) not in cells and (i + 1, j) not in cells:
            img[yy, xx] = (*GROOVE, 255)


def rubble(img, keep, top, sd, spec, X, Y, seed):
    """Light rubble on the flagstones: chips and broken pieces gather at the feet of the pillars, along the lip, round the cracks and in a few loose drifts."""
    rng = random.Random(seed + 303)
    h, w = img.shape[0], img.shape[1]
    centre_x, centre_y = sigil_centre(spec)
    sites = []
    for pil in spec.get("pillars", []):  # round the feet
        for _ in range(16):
            ang = rng.random() * TAU
            d = rng.uniform(16.0, 34.0)
            sites.append((pil["pos"][0] + math.cos(ang) * d, pil["pos"][1] + math.sin(ang) * d * 0.7, 1.0))
    ys, xs = np.nonzero(keep & (sd < -3.0) & (sd > -20.0))  # along the lip (sd is negative inside)
    for i in rng.sample(range(len(xs)), min(70, len(xs))):
        sites.append((xs[i] + float(X[0, 0]) - 0.5, ys[i] + float(Y[0, 0]) - 0.5, 0.8))
    for _ in range(26):  # drifts of rubble anywhere on the floor
        ys2, xs2 = np.nonzero(keep & (sd < -12.0))
        j = rng.randrange(len(xs2))
        sites.append((xs2[j] + float(X[0, 0]) - 0.5, ys2[j] + float(Y[0, 0]) - 0.5, 1.0))
    x0 = float(X[0, 0]) - 0.5
    y0 = float(Y[0, 0]) - 0.5
    for sx, sy, power in sites:
        for _ in range(rng.randrange(2, 6)):
            px = int(sx - x0 + rng.gauss(0, 5.0))
            py = int(sy - y0 + rng.gauss(0, 3.5))
            if 0 <= px < w - 6 and 0 <= py < h - 5 and keep[py, px]:
                _chip(img, px, py, rng.choice((2, 2, 3, 3, 4, 5)), rng, keep)
        for _ in range(rng.randrange(3, 9)):  # grit and dust
            px = int(sx - x0 + rng.gauss(0, 7.0))
            py = int(sy - y0 + rng.gauss(0, 5.0))
            if 0 <= px < w and 0 <= py < h and keep[py, px] and img[py, px, 3] == 255:
                img[py, px] = (*P[4 + rng.randrange(3)], 255)


DRY = [(58, 48, 34), (84, 70, 44), (112, 96, 58), (140, 122, 74)]  # withered grass and stalks
LEAF = [(70, 52, 40), (98, 70, 48), (120, 88, 52)]  # fallen leaves


def plant_remains(img, keep, sd, spec, X, Y, seed):
    """What is left of the plants: tufts of dry grass and stalks gathering at the pillars' feet, in the joints and along the lip, a litter of fallen leaves, and thin creepers
    of green running along the joints. Only where the floor is `keep`, never on the sigil's centre."""
    rng = random.Random(seed + 505)
    h, w = img.shape[0], img.shape[1]
    x0, y0 = float(X[0, 0]) - 0.5, float(Y[0, 0]) - 0.5
    cx, cy = sigil_centre(spec)
    sites = []
    for pil in spec.get("pillars", []):
        for _ in range(7):
            sites.append((pil["pos"][0] + rng.gauss(0, 14), pil["pos"][1] + rng.gauss(0, 9)))
    ys, xs = np.nonzero(keep & (sd < -2.0) & (sd > -16.0))
    for i in rng.sample(range(len(xs)), min(46, len(xs))):
        sites.append((xs[i] + x0, ys[i] + y0))
    for sx, sy in sites:
        px, py = int(sx - x0), int(sy - y0)
        if not (4 <= px < w - 4 and 8 <= py < h - 2) or not keep[py, px]:
            continue
        if ((sx - cx) / 70.0) ** 2 + ((sy - cy) / 50.0) ** 2 < 1.0:
            continue
        for k in range(rng.randrange(3, 6)):  # a tuft: dry blades leaning, a few stalks with a head
            lean = rng.choice((-2, -1, 0, 1, 2))
            ln = rng.randrange(3, 7)
            for j in range(ln):
                xx, yy = px + k - 2 + int(lean * j / max(ln, 1) * 1.5), py - j
                if 0 <= xx < w and 0 <= yy < h:
                    img[yy, xx] = (*DRY[min(3, 1 + j * 3 // ln)], 255)
        for _ in range(rng.randrange(2, 6)):  # leaves
            lx, ly = px + int(rng.gauss(0, 5)), py + int(rng.gauss(0, 3))
            if 0 <= lx < w - 1 and 0 <= ly < h and keep[ly, lx]:
                c = LEAF[rng.randrange(3)]
                img[ly, lx] = (*c, 255)
                if rng.random() < 0.5:
                    img[ly, lx + 1] = (*c, 255)


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("arena_design.png")
    import json
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import bake_ground
    data = json.load(open(pathlib.Path(__file__).resolve().parent.parent / "data" / "ground.json"))
    spec = data["arenas"][0]
    img, mask, _ = bake_ground.bake_arena(spec, 1300)
    h, w = img.shape[0], img.shape[1]
    sheet = Image.new("RGBA", (w * 2 + 8, h), (40, 74, 60, 255))
    sheet.paste(Image.fromarray(img, "RGBA"), (0, 0), Image.fromarray(img, "RGBA"))
    glow = bake_ground.ARENA_GLOW.get(spec["id"])
    if glow is not None:
        g = Image.fromarray(glow, "RGBA")
        sheet.paste(g, (w + 8, 0), g)
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
