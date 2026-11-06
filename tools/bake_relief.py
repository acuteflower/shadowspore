#!/usr/bin/env python3
"""Bakes the world's relief (height levels) into assets/world/relief.png, 1 pixel per tile:
  R = level 0..3 (what you stand on; a wall tile has the level of its foot),
  G = kind (low nibble: 0 floor, 1 wall face, 2 ramp, 3 stairs, 4 rock steps) | style << 4
      (0 grass, 1 rock, 2 masonry, 3 crystal, 4 void),
  B = geometry: wall face: its row in the wall (0 top, 1 bottom: a wall is FACE_ROWS = 2 tiles, 32 px, tall);
      connector: row (bits 0-1, 0 = top, next to the plateau) | depth-1 << 2 | column << 4 (0 left .. 2 right),
  A = 0 void, else 200 + biome index.
Needs numpy. Usage: python3 tools/bake_relief.py [debug.png]

How it is made: a rank-normalised noise field is bent per biome (data/biomes.json "relief": gain, bias,
style weights), flattened near the coast and the start, cut into levels at fixed thresholds, then
cleaned per level (diamond opening + closing, tiny pieces and holes dropped, levels nested with a one
tile band) so plateaus are wide, rounded and never differ by more than one level between neighbours.
A wall face is the two tiles below every tile whose southern neighbour is lower (the 3/4 camera looks at south faces);
the other edges become thin walls at run time. Connectors (ramps, stairs, rock steps) cut into south
faces, and cross the plain cliff edges on the north, east and west sides (3 wide, 2 or 3 deep, B bits 6-7 = the way down): a union-find over the walkable pieces adds just enough of them to make everything reachable
from the start, plus a few extra for loops; what cannot be reached is merged into its surroundings.
Nothing is hand-placed: the whole map is made by the noise."""
import os, sys, json, collections
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import W, CELL, load_png, save_png, load_map, start_tile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 11
THRESH = [0.62, 0.80, 0.95]  # on the rank-normalised field, after gain and bias
FLOOR, FACE, RAMP, STAIRS, STEPS = 0, 1, 2, 3, 4
GRASS, ROCK, MASONRY, CRYSTAL, VOID = 0, 1, 2, 3, 4
COAST_FLAT = (7.0, 15.0)  # tiles from the coast: flat .. full relief (the baked coast distance saturates at 16)
FACE_ROWS = 2  # a wall is two tiles (32 px) tall
SOUTH, NORTH, EAST, WEST = 0, 1, 2, 3  # the way DOWN a connector leads (bits 6-7 of its geometry); south ones cut into the wall faces, the others cross a plain cliff edge
DOWN = {SOUTH: (0, 1), NORTH: (0, -1), EAST: (1, 0), WEST: (-1, 0)}
ACROSS = {SOUTH: (1, 0), NORTH: (1, 0), EAST: (0, 1), WEST: (0, 1)}
START_RECT = (-6, -6, 6, 6)  # tiles around the start that stay flat (a small clearing, the cliffs begin right behind it)
START_FADE = 8.0


# ---------------------------------------------------------------------------------- noise
def hash2(ix, iy, seed):
    n = ix.astype(np.int64).astype(np.uint64) * np.uint64(374761393) + iy.astype(np.int64).astype(np.uint64) * np.uint64(668265263) + np.uint64(seed * 1442695041 % (1 << 32))
    n = (n ^ (n >> np.uint64(13))) * np.uint64(1274126177)
    n = n ^ (n >> np.uint64(16))
    return (n & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def vnoise(X, Y, seed):
    x0, y0 = np.floor(X), np.floor(Y)
    fx, fy = X - x0, Y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(x0, y0, seed), hash2(x0 + 1, y0, seed)
    c, d = hash2(x0, y0 + 1, seed), hash2(x0 + 1, y0 + 1, seed)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def fbm(X, Y, seed, octaves=3):
    v, amp, total = 0.0, 1.0, 0.0
    for o in range(octaves):
        v = v + amp * vnoise(X, Y, seed + o * 31)
        total += amp
        X, Y, amp = X * 2.03 + 17.0, Y * 2.03 + 9.0, amp * 0.5
    return v / total


def rank_normalise(field, land):
    """The field's rank over the land, 0..1 and evenly spread (0 elsewhere)."""
    order = np.empty(int(land.sum()))
    order[field[land].argsort()] = np.arange(order.size) / order.size
    out = np.zeros_like(field)
    out[land] = order
    return out


def limit_steps(lvl, land):
    """Lowers tiles until no two neighbours differ by more than one level."""
    while True:
        changed = False
        for axis in (0, 1):
            a = lvl.astype(np.int16)
            for s in (1, -1):
                b = np.roll(a, s, axis=axis)
                bad = (a - b > 1) & land & np.roll(land, s, axis=axis)
                if bad.any():
                    lvl[bad] = (b[bad] + 1).astype(np.int8)
                    a = lvl.astype(np.int16)
                    changed = True
        if not changed:
            return


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def box(a, r, axis):
    n = a.shape[axis]
    p = np.pad(a, [(r, r) if ax == axis else (0, 0) for ax in range(2)], mode="edge")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
    return (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, np.arange(0, n), axis=axis)) / (2 * r + 1)


def blur(a, r, passes=3):
    a = a.astype(np.float64)
    for _ in range(passes):
        a = box(box(a, r, 0), r, 1)
    return a


# ---------------------------------------------------------------------------------- morphology
def erode(m):
    r = m.copy()
    r[1:] &= m[:-1]; r[0] = False
    r[:-1] &= m[1:]; r[-1] = False
    r[:, 1:] &= m[:, :-1]; r[:, 0] = False
    r[:, :-1] &= m[:, 1:]; r[:, -1] = False
    return r


def dilate(m):
    r = m.copy()
    r[1:] |= m[:-1]
    r[:-1] |= m[1:]
    r[:, 1:] |= m[:, :-1]
    r[:, :-1] |= m[:, 1:]
    return r


def opening(m, n):
    for _ in range(n): m = erode(m)
    for _ in range(n): m = dilate(m)
    return m


def closing(m, n):
    for _ in range(n): m = dilate(m)
    for _ in range(n): m = erode(m)
    return m


def label(mask):
    """4-connected components (run based union-find) -> (int32 labels, 0 = background; count)."""
    h, w = mask.shape
    parent, runs_by_row = [], []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    prev = []
    for y in range(h):
        d = np.diff(np.concatenate(([0], mask[y].astype(np.int8), [0])))
        cur, j = [], 0
        for s, e in zip(np.nonzero(d == 1)[0].tolist(), np.nonzero(d == -1)[0].tolist()):
            rid = len(parent)
            parent.append(rid)
            while j < len(prev) and prev[j][1] <= s:
                j += 1
            k = j
            while k < len(prev) and prev[k][0] < e:
                ra, rb = find(rid), find(prev[k][2])
                if ra != rb:
                    parent[ra] = rb
                k += 1
            cur.append((s, e, rid))
        runs_by_row.append(cur)
        prev = cur
    ids, out = {}, np.zeros((h, w), dtype=np.int32)
    for y, runs in enumerate(runs_by_row):
        for s, e, rid in runs:
            root = find(rid)
            out[y, s:e] = ids.setdefault(root, len(ids) + 1)
    return out, len(ids)


def drop_small(mask, min_area):
    lab, n = label(mask)
    if n == 0:
        return mask
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    keep = sizes >= min_area
    keep[0] = False
    return keep[lab]


# ---------------------------------------------------------------------------------- the bake
def main():
    out_debug = sys.argv[1] if len(sys.argv) > 1 else None
    rng = np.random.default_rng(SEED)
    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    land = sdf >= 128
    coast = (sdf - 128) / 8.0  # tiles inside the coast
    d, grid, start_region = load_map(os.path.join(ROOT, "data/world_map.json"))
    sx, sy = start_tile(d, grid)
    biomes = json.load(open(os.path.join(ROOT, "data/biomes.json")))
    biome_ids = list(biomes.keys())

    # biome per tile, as in the game (without its small border jitter)
    sup_biome = {int(s["id"]): s["biome"] for s in d["supers"]}
    reg_biome = {int(r["id"]): sup_biome[int(r["super"])] for r in d["regions"]}
    cell_b = np.full(grid.shape, -1, dtype=np.int32)
    for rid, b in reg_biome.items():
        cell_b[grid == rid] = biome_ids.index(b)
    biome = np.repeat(np.repeat(cell_b, CELL, 0), CELL, 1)
    biome = np.where(biome < 0, 0, biome)
    gain_of = np.array([biomes[b]["relief"]["gain"] for b in biome_ids])
    bias_of = np.array([biomes[b]["relief"]["bias"] for b in biome_ids])
    styles_of = np.array([biomes[b]["relief"]["styles"] for b in biome_ids], dtype=np.float64)
    gain = blur(gain_of[biome], 14)
    bias = blur(bias_of[biome], 14)

    # the field: warped fbm, rank-normalised over the land, bent per biome, flattened at the coast and start
    Y, X = np.mgrid[0:W, 0:W].astype(np.float64)
    wx = X + (vnoise(X / 38.0, Y / 38.0, SEED + 1) - 0.5) * 30.0
    wy = Y + (vnoise(X / 38.0 + 50, Y / 38.0 + 50, SEED + 2) - 0.5) * 30.0
    n = fbm(wx / 50.0, wy / 50.0, SEED + 3, 3)
    rank = rank_normalise(n, land)
    v = 0.5 + (rank - 0.5) * gain + bias
    rx0, ry0, rx1, ry1 = START_RECT
    dx = np.maximum(np.maximum(sx + rx0 - X, X - (sx + rx1)), 0.0)
    dy = np.maximum(np.maximum(sy + ry0 - Y, Y - (sy + ry1)), 0.0)
    flat = smoothstep(*COAST_FLAT, coast) * smoothstep(0.0, START_FADE, np.hypot(dx, dy))
    v = 0.2 + (v - 0.2) * flat
    raw = (v > THRESH[0]).astype(np.int8) + (v > THRESH[1]) + (v > THRESH[2])
    raw = np.where(land, raw, 0)

    # clean per level, nest with a one tile band
    lvl = np.zeros((W, W), dtype=np.int8)
    below = land.copy()
    for k in (1, 2, 3):
        m = (raw >= k) & below
        m = drop_small(closing(opening(m, 2), 2), 90)
        m = ~drop_small(~m, 90)
        m &= land
        if k > 1:
            m &= erode(erode(erode(erode(erode(prev_mask)))))  # a ledge of at least 5 tiles around every higher level (2 of them wall)
        prev_mask = m
        lvl += m.astype(np.int8)
        below = m

    # style of the wall above each tile: low-frequency noise picks from the biome's weights
    sn = rank_normalise(fbm(X / 11.0, Y / 11.0, SEED + 9, 2), land)
    cum = np.cumsum(styles_of[biome], axis=-1)
    style_field = (sn[..., None] * cum[..., -1:] > cum).sum(axis=-1).astype(np.int8)
    style_field = np.minimum(style_field, 4)

    conns = []  # [x, y, kind, width, the way down]

    def settle(rounds):
        """Connects whatever is cut off from the start (analyse, connect, merge what cannot be reached), until all is reachable."""
        for attempt in range(rounds):
            res = analyse(lvl, land, style_field, conns, (sx, sy))
            added = connect(res, lvl, land, coast, conns, rng)
            if added == 0:
                merged = merge_unreached(res, lvl, land)
                print("  round %d: %d connectors, merged %d cut-off pieces" % (attempt, len(conns), merged))
                if merged == 0:
                    return res
            else:
                print("  round %d: %d connectors (+%d)" % (attempt, len(conns), added))
        raise SystemExit("cut-off pieces left")

    res = settle(40)
    extras(res, lvl, land, coast, conns, rng)  # more ways up, on every side; carving may cut something off, so settle again
    res = settle(40)
    res = analyse(lvl, land, style_field, conns, (sx, sy))
    assert merge_unreached(res, lvl, land) == 0, "cut-off pieces left"
    kind, geom, cstyle, face_style = res["kind"], res["geom"], res["cstyle"], res["fstyle"]

    style = np.where(kind == FACE, face_style, np.where(kind == FLOOR, res["src"], cstyle)).astype(np.uint8)
    img = np.zeros((W, W, 4), dtype=np.uint8)
    img[..., 0] = lvl
    img[..., 1] = kind | (style << 4)
    img[..., 2] = geom
    img[..., 3] = np.where(land, 200 + biome, 0)
    save_png(os.path.join(ROOT, "assets/world/relief.png"), img)
    json.dump({"connectors": [[int(v) for v in c] for c in conns]}, open(os.path.join(ROOT, "data/relief.json"), "w"))
    export_smooth(lvl, land, kind, conns)
    report(lvl, kind, land, biome, biome_ids, conns)
    if out_debug:
        debug_image(out_debug, lvl, kind, land)
    print("baked assets/world/relief.png")


def side_tiles(d, ox, oy, depth, w=3):
    """(row, column, x, y) of the tiles of a side connector: row 0 is the high lip tile (origin), rows run down, columns across."""
    (dx, dy), (ax, ay) = DOWN[d], ACROSS[d]
    return [(r, c, ox + dx * r + ax * c, oy + dy * r + ay * c) for r in range(depth) for c in range(w)]


def side_pattern(d):
    """(dx, dy, offset) of the tiles around a side connector whose origin (the high lip) is (0, 0): offset 0 = the high level,
    -1 = the low one: a straight cliff edge with a flank tile on each side, and floor to walk on at both ends."""
    out = []
    if d == EAST:
        out = [(dx, dy, 0 if dx <= 0 else -1) for dy in range(-1, 4) for dx in range(-2, 5)]
    elif d == WEST:
        out = [(dx, dy, 0 if dx >= 0 else -1) for dy in range(-1, 4) for dx in range(-4, 3)]
    elif d == NORTH:
        out = [(dx, dy, 0 if dy >= 0 else -1) for dx in range(-1, 4) for dy in range(-4, 3)]
    return out


def site_ok_side(lvl, kind, land, d, ox, oy):
    hi = int(lvl[oy, ox])
    if hi < 1:
        return False
    for dx, dy, off in side_pattern(d):
        x, y = ox + dx, oy + dy
        if not (0 <= x < W and 0 <= y < W and land[y, x] and kind[y, x] == FLOOR and lvl[y, x] == hi + off):
            return False
    return True


def carve_side(lvl, ox, oy, d):
    """Straightens the cliff edge around a side connector."""
    hi = int(lvl[oy, ox])
    for dx, dy, off in side_pattern(d):
        lvl[oy + dy, ox + dx] = hi + off


def ends(x, y, d):
    """The walkable tiles just outside the high and the low end of a connector candidate: (hx, hy, lx, ly)."""
    if d == SOUTH:
        return x, y - 1, x, y + 2
    (dx, dy), (ax, ay) = DOWN[d], ACROSS[d]
    return x - dx + ax, y - dy + ay, x + dx * 2 + ax, y + dy * 2 + ay


def origin(x, y, d):
    """The top-left tile a connector candidate is stored under."""
    return (x - 1, y) if d == SOUTH else (x, y)


def site_ok(lvl, kind, x, y, w=3):
    """A connector of width w fits at columns x.., wall rows y and y+1: floor above, floor below, wall on both sides."""
    lo = lvl[y, x]
    for c in range(w):
        xx = x + c
        if not (kind[y, xx] == FACE and kind[y + 1, xx] == FACE and kind[y - 1, xx] == FLOOR and lvl[y - 1, xx] == lo + 1 and lvl[y + 1, xx] == lo):
            return False
        if not (kind[y + 2, xx] == FLOOR and lvl[y + 2, xx] == lo and kind[y + 3, xx] == FLOOR and lvl[y + 3, xx] == lo):
            return False
    for xx in (x - 1, x + w):
        if not (kind[y, xx] == FACE and kind[y + 1, xx] == FACE and kind[y + 2, xx] == FLOOR and lvl[y + 2, xx] == lo):
            return False
    return True


def analyse(lvl, land, style_field, conns, start):
    """Walls, connectors that still fit, walkable pieces and which of them are reachable from the start."""
    limit_steps(lvl, land)
    north = np.zeros_like(lvl)
    north[1:] = lvl[:-1]
    face0 = land & (north > lvl)
    face1 = np.zeros_like(face0)
    face1[1:] = face0[:-1]
    face1 &= land & ~face0 & (lvl == np.roll(lvl, 1, axis=0))
    face = face0 | face1
    kind = np.where(face, FACE, FLOOR).astype(np.uint8)
    geom = face1.astype(np.uint8)
    # a wall takes the style of the plateau above it
    src = style_field
    s1 = np.zeros_like(src); s1[1:] = src[:-1]
    s2 = np.zeros_like(src); s2[2:] = src[:-2]
    fstyle = np.where(face0, s1, np.where(face1, s2, 0)).astype(np.int8)
    cstyle = np.zeros((W, W), dtype=np.int8)

    walk = land & ~face
    comp = np.zeros((W, W), dtype=np.int32)
    ncomp = 0
    for k in range(4):
        lab, n = label(walk & (lvl == k))
        comp = np.where(lab > 0, lab + ncomp, comp)
        ncomp += n
    parent = list(range(ncomp + 1))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    kept = []
    for c in conns:
        x, y, kd, w, d = c
        depth = 3 if kd == RAMP else 2
        if d == SOUTH:
            if not site_ok(lvl, kind, x, y, w):
                continue
            st = int(fstyle[y, x + 1])
            a, b = int(comp[y - 1, x + 1]), int(comp[y + depth, x + 1])
            for cc in range(w):
                for r in range(depth):
                    kind[y + r, x + cc] = kd
                    geom[y + r, x + cc] = r | ((depth - 1) << 2) | (cc << 4)
                    cstyle[y + r, x + cc] = st
        else:
            if not site_ok_side(lvl, kind, land, d, x, y):
                continue
            st = int(src[y, x])
            for r, cc, tx, ty in side_tiles(d, x, y, depth):
                kind[ty, tx] = kd
                geom[ty, tx] = r | ((depth - 1) << 2) | (cc << 4) | (d << 6)
                cstyle[ty, tx] = st
            hx, hy, _lx, _ly = ends(x, y, d)
            lx, ly = x + DOWN[d][0] * depth + ACROSS[d][0], y + DOWN[d][1] * depth + ACROSS[d][1]
            a, b = int(comp[hy, hx]), int(comp[ly, lx])
        parent[find(a)] = find(b)
        kept.append(c)
    conns[:] = kept
    roots = np.array([find(i) for i in range(ncomp + 1)], dtype=np.int32)
    start_root = int(roots[comp[start[1], start[0]]])
    return {"src": src, "kind": kind, "geom": geom, "cstyle": cstyle, "fstyle": fstyle, "comp": comp, "roots": roots, "start_root": start_root, "walk": walk}


def pick_kind(res, x, y, rng, d=SOUTH):
    st = int(res["fstyle"][y, x]) if d == SOUTH else int(res["src"][y, x])
    if st == MASONRY: return STAIRS
    if st == GRASS: return RAMP
    return RAMP if rng.random() < 0.15 else STEPS


def carve(lvl, x, y):
    """Straightens the cliff at column x, wall rows y and y+1 so a 3 wide connector fits: 3 rows of the upper level above, 5 of the lower below."""
    hi = int(lvl[y - 1, x])
    lo = hi - 1
    lvl[y - 3:y, x - 3:x + 4] = hi
    lvl[y:y + 5, x - 3:x + 4] = lo


def candidates(res, land, coast, lvl, conns):
    """(straight, x, y, d) of every place a connector could go: wall rows on a south edge (floor above at level h, two wall
    rows, floor below at h - 1) and straight stretches of plain cliff edge on the north, east and west sides; clear of other connectors."""
    kind, geom = res["kind"], res["geom"]

    def at(a, dy):
        return np.roll(a, -dy, axis=0)

    sel = (kind == FACE) & (geom == 0) & (at(kind, -1) == FLOOR) & (at(kind, 1) == FACE) & (at(kind, 2) == FLOOR) & (at(kind, 3) == FLOOR)
    sel &= (at(lvl, -1) == lvl + 1) & (at(lvl, 2) == lvl) & (at(lvl, 3) == lvl)
    ys, xs = np.nonzero(sel)
    out = []
    block = np.zeros((W, W), dtype=bool)
    for cx, cy, _, w, d in conns:
        if d == SOUTH:
            block[cy - 6:cy + 9, cx - 8:cx + w + 8] = True
        else:
            block[cy - 8:cy + 11, cx - 8:cx + 11] = True
    for y, x in zip(ys.tolist(), xs.tolist()):
        if x < 4 or x > W - 5 or y < 5 or y > W - 8 or block[y, x]:
            continue
        if not land[y - 3:y + 5, x - 3:x + 4].all() or coast[y + 4, x] < 6 or coast[y - 3, x] < 6:
            continue
        straight = int(((kind[y, x - 4:x + 5] == FACE) & (kind[y + 1, x - 4:x + 5] == FACE)).sum())
        out.append((straight, x, y, SOUTH))

    floor = land & (kind == FLOOR)

    def sh(a, dy, dx):  # a[y + dy, x + dx]
        return np.roll(np.roll(a, -dy, axis=0), -dx, axis=1)

    for d, (dy, dx) in ((EAST, (0, 1)), (WEST, (0, -1)), (NORTH, (-1, 0))):
        edge = floor & sh(floor, dy, dx) & (lvl >= 1) & (sh(lvl, dy, dx) == lvl - 1)  # a tile of the high level whose neighbour that way is the low one
        along = (1, 0) if d != NORTH else (0, 1)
        straight3 = edge & sh(edge, along[0], along[1]) & sh(edge, 2 * along[0], 2 * along[1])
        ys, xs = np.nonzero(straight3)
        for y, x in zip(ys.tolist(), xs.tolist()):
            if x < 8 or x > W - 9 or y < 8 or y > W - 9 or block[y, x]:
                continue
            if coast[y, x] < 6 or coast[y + dy * 4, x + dx * 4] < 6 or coast[y - dy * 4, x - dx * 4] < 6:
                continue
            run = int(sum(edge[y + along[0] * k, x + along[1] * k] for k in range(-3, 7)))
            out.append((run, x, y, d))
    return out


def connect(res, lvl, land, coast, conns, rng):
    """Adds a carved connector for every cut-off group that has an edge to a different group. Returns how many."""
    roots, comp = res["roots"], res["comp"]
    cand = candidates(res, land, coast, lvl, conns)
    if not cand:
        return 0
    by_group = collections.defaultdict(list)
    for straight, x, y, d in cand:
        hx, hy, lx, ly = ends(x, y, d)
        a, b = int(roots[comp[hy, hx]]), int(roots[comp[ly, lx]])
        if a == b:
            continue
        for g, other in ((a, b), (b, a)):
            if g != res["start_root"]:
                by_group[g].append(((2.0 if other == res["start_root"] else 0.0) + min(straight, 9) / 9.0 + rng.random() * 0.8, x, y, d))
    added, used = 0, np.zeros((W, W), dtype=bool)
    groups = list(by_group.keys())
    for gi in rng.permutation(len(groups)):
        options = sorted(by_group[groups[gi]], reverse=True)
        for score, x, y, d in options[:12]:
            if used[y - 8:y + 11, x - 8:x + 11].any():
                continue
            put_connector(res, lvl, conns, x, y, d, rng)
            used[y - 8:y + 11, x - 8:x + 11] = True
            added += 1
            break
    return added


def put_connector(res, lvl, conns, x, y, d, rng):
    """Carves the cliff and records a connector of a kind that fits the plateau's style."""
    if d == SOUTH:
        carve(lvl, x, y)
    else:
        carve_side(lvl, x, y, d)
    ox, oy = origin(x, y, d)
    conns.append([ox, oy, int(pick_kind(res, x, y, rng, d)), 3, d])


def merge_unreached(res, lvl, land):
    """What no connector can reach is flattened: a cut-off plateau drops one level, a cut-off pit on the lowest level
    rises to the lowest floor around it."""
    unreached = ~np.isin(res["roots"][res["comp"]], [res["start_root"]]) & res["walk"]
    if not unreached.any():
        return 0
    lab, n = label(unreached)
    walk = res["walk"]
    for i in range(1, n + 1):
        piece = lab == i
        k = int(lvl[piece][0])
        if os.environ.get("RELIEF_DEBUG"):
            yy, xx = np.nonzero(piece)
            print("    piece level %d size %d bbox x %d..%d y %d..%d" % (k, piece.sum(), xx.min(), xx.max(), yy.min(), yy.max()))
        if k >= 1:
            lvl[piece] = k - 1
            continue
        ys, xs = np.nonzero(piece)
        around = []
        for yy, xx in zip(ys.tolist(), xs.tolist()):
            for ny, nx in ((yy - 1, xx), (yy + 1, xx), (yy, xx - 1), (yy, xx + 1)):
                if 0 <= ny < W and 0 <= nx < W and not piece[ny, nx] and walk[ny, nx]:
                    around.append(int(lvl[ny, nx]))
        lvl[piece] = max(min(around), 1) if around else 1
    return n


def extras(res, lvl, land, coast, conns, rng):
    """More ways up: every plateau gets connectors on different sides (south, north, east, west) and a second one where an
    edge is long, so the world is full of loops to walk and nobody has to run round to the one stair."""
    cand = candidates(res, land, coast, lvl, conns)
    comp = res["comp"]
    by = collections.defaultdict(list)
    for straight, x, y, d in cand:
        hx, hy, _lx, _ly = ends(x, y, d)
        by[(int(comp[hy, hx]), d)].append((straight + rng.random() * 3.0, x, y, d))
    block = np.zeros((W, W), dtype=bool)
    for cx, cy, _, w, d in conns:
        block[cy - 12:cy + 13, cx - 12:cx + 15] = True
    per_plateau = collections.Counter()
    keys = list(by.keys())
    for rnd in range(3):  # round 0: one per plateau and side, then a second and third where the edge is long
        rng.shuffle(keys)
        for key in keys:
            if per_plateau[key[0]] >= 6 or (rnd > 0 and rng.random() > 0.6):
                continue
            for score, x, y, d in sorted(by[key], reverse=True)[:25]:
                ox, oy = origin(x, y, d)
                if block[oy, ox] or (rnd > 0 and score < 5):
                    continue
                put_connector(res, lvl, conns, x, y, d, rng)
                block[oy - 12:oy + 13, ox - 12:ox + 15] = True
                per_plateau[key[0]] += 1
                break


def make_wobble(path):
    """A tileable 256x256 noise (L8, 128 = 0) that is added to the smooth field before the 0.5 threshold, so contours
    wander like real ground: slow lobes, mid bumps and fine ragged edges. Shader and collision bake read the same pixels."""
    rng = np.random.default_rng(SEED + 5)
    t = np.arange(256, dtype=np.float64)
    total = np.zeros((256, 256))
    for cells, amp in ((6, 0.045), (18, 0.04), (52, 0.022)):
        lat = rng.random((cells, cells))
        u = t * cells / 256.0
        i0 = np.floor(u).astype(int) % cells
        i1 = (i0 + 1) % cells
        f = u - np.floor(u)
        f = f * f * (3 - 2 * f)
        rows = lat[:, i0] * (1 - f) + lat[:, i1] * f
        total += amp * ((rows[i0] * (1 - f)[:, None] + rows[i1] * f[:, None]) - 0.5) * 2.0
    img = np.clip(np.round(128 + total * 255.0), 0, 255).astype(np.uint8)
    save_png(path, img)
    return (img.astype(np.float32) - 128.0) / 255.0


def export_smooth(lvl, land, kind, conns):
    """The smooth picture of the levels. relief_field.png: per tile the level masks (>= 1, 2, 3) blurred, so a 0.5
    threshold gives round contours instead of tile steps (R, G, B). relief_block.png: collision at 4 px, 255 where
    the ground is blocked: the wall (32 px below every contour, the same rule the shader uses) and a thin rim along
    every contour, minus the connectors."""
    fields = []
    for k in (1, 2, 3):
        m = (lvl >= k).astype(np.float64)
        for _ in range(3):
            m = box(box(m, 1, 0), 1, 1)
        fields.append(np.clip(np.round(m * 255.0), 0, 255).astype(np.uint8))
    save_png(os.path.join(ROOT, "assets/world/relief_field.png"), np.stack(fields, axis=-1))
    wobble = make_wobble(os.path.join(ROOT, "assets/world/relief_wobble.png"))

    n4 = W * 4
    idx = (np.arange(n4) + 0.5) / 4.0 - 0.5  # tile index (texel centre = tile centre) of every 4 px cell
    i0 = np.clip(np.floor(idx).astype(np.int64), 0, W - 1)
    i1 = np.clip(i0 + 1, 0, W - 1)
    fr = (idx - np.floor(idx)).astype(np.float32)
    up = np.zeros((n4, n4), dtype=np.int8)
    wi = (np.arange(n4) * 4 + 2) % 256  # the art pixel each 4 px cell stands for
    wob = wobble[np.ix_(wi, wi)]
    for f in fields:
        a = f.astype(np.float32) / 255.0
        a = a[:, i0] * (1 - fr) + a[:, i1] * fr
        a = a[i0] * (1 - fr)[:, None] + a[i1] * fr[:, None]
        up += ((a + wob) > 0.5).astype(np.int8)
    wall = np.zeros((n4, n4), dtype=bool)
    for d in range(1, 9):
        above = np.zeros_like(up)
        above[d:] = up[:-d]
        wall |= above > up
    rim = np.zeros((n4, n4), dtype=bool)
    for axis in (0, 1):
        for s in (1, -1):
            rim |= np.roll(up, s, axis=axis) != up
    block = (wall | rim) & np.repeat(np.repeat(land, 4, 0), 4, 1)
    for cx, cy, kd, w, d in conns:
        depth = 3 if kd == RAMP else 2
        if d == SOUTH:
            block[cy * 4 - 2:(cy + depth) * 4, cx * 4:(cx + w) * 4] = False
        else:
            tiles = side_tiles(d, cx, cy, depth, w)
            xs, ys = [t[2] for t in tiles], [t[3] for t in tiles]
            block[min(ys) * 4:(max(ys) + 1) * 4, min(xs) * 4:(max(xs) + 1) * 4] = False
    save_png(os.path.join(ROOT, "assets/world/relief_block.png"), (block * 255).astype(np.uint8))


def report(lvl, kind, land, biome, biome_ids, conns):
    print("levels (share of land) per biome:")
    for i, b in enumerate(biome_ids):
        sel = land & (biome == i)
        total = max(int(sel.sum()), 1)
        print("  %-14s " % b + "  ".join("L%d %4.1f%%" % (k, 100.0 * int((sel & (lvl == k)).sum()) / total) for k in range(4)))
    names = {RAMP: "ramps", STAIRS: "stairs", STEPS: "steps"}
    count = collections.Counter(c[2] for c in conns)
    sides = collections.Counter(c[4] for c in conns)
    print("walls %d tiles, connectors: %s; by the way down: %d south, %d north, %d east, %d west" % (int((kind == FACE).sum()), ", ".join("%d %s" % (count[k], names[k]) for k in names), sides[SOUTH], sides[NORTH], sides[EAST], sides[WEST]))


def debug_image(path, lvl, kind, land):
    pal = np.array([[34, 60, 52], [70, 130, 80], [150, 190, 100], [240, 240, 200]], dtype=np.uint8)
    img = pal[lvl]
    img[kind == FACE] = (20, 16, 40)
    img[kind >= RAMP] = (255, 120, 40)
    img[~land] = (10, 8, 24)
    save_png(path, img)


if __name__ == "__main__":
    main()
