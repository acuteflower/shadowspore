#!/usr/bin/env python3
"""Adds the Hexenwald to the frozen world map (data/world_map.json): region 31 in super region 5, grown out of the south coast
of the town's region as a wide extension of the land. Nothing that exists is moved: cells that are land stay as they are, regions 0-30 keep
their ids; only the neighbour lists of the regions the neck touches gain one entry. Repeatable: everything that belonged to
region 31 / super 5 is removed first.  Usage: python3 tools/bake_hexenwald_map.py [preview.png]
Afterwards: tools/bake_land_sdf.gd, tools/bake_hexenwald_relief.py, tools/bake_lakes.py (see docs/hexenwald_konzept.md)."""
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import CELL, W, load_map, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "data/world_map.json")
REGION, SUPER, BIOME, NAME = 31, 5, "witch_forest", "Hexenwald"
SEED = int(os.environ.get("HEX_SEED", "23"))
BODY = (830.0, 905.0, 122.0, 112.0)  # centre x, y and radii in tiles


def hash2(ix, iy, seed):
    n = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(X, Y, seed):
    x0, y0 = np.floor(X), np.floor(Y)
    fx, fy = X - x0, Y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(x0, y0, seed), hash2(x0 + 1, y0, seed)
    c, d = hash2(x0, y0 + 1, seed), hash2(x0 + 1, y0 + 1, seed)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def label(mask):
    """4-connected components by flood fill -> (labels, count); the grid is small (275 x 275)."""
    lab = np.zeros(mask.shape, dtype=np.int32)
    n = 0
    for y, x in zip(*np.nonzero(mask)):
        if lab[y, x]:
            continue
        n += 1
        stack = [(y, x)]
        lab[y, x] = n
        while stack:
            cy, cx = stack.pop()
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n
                    stack.append((ny, nx))
    return lab, n


def footprint(g):
    """True per cell where the Hexenwald stands: a big lobed body that overlaps the old south coast, so it joins the land along a wide front."""
    cy, cx = np.mgrid[0:g, 0:g]
    X, Y = (cx + 0.5) * CELL, (cy + 0.5) * CELL
    bx, by, rx, ry = BODY
    # the body: an ellipse whose radius is bent by slow noise (lobes, bays) and a finer ripple
    ang = np.arctan2((Y - by) / ry, (X - bx) / rx)
    lobes = vnoise(np.cos(ang) * 1.7 + 5.0, np.sin(ang) * 1.7 + 5.0, SEED) - 0.5
    ripple = vnoise(np.cos(ang) * 4.6 + 9.0, np.sin(ang) * 4.6 + 9.0, SEED + 1) - 0.5
    rad = 1.0 + lobes * 0.6 + ripple * 0.15
    warp = (vnoise(X / 21.0, Y / 21.0, SEED + 2) - 0.5) * 0.12
    body = np.hypot((X - bx) / rx, (Y - by) / ry) + warp < rad
    return body


def main():
    d, grid, _ = load_map(PATH)
    g = grid.shape[0]
    # start from the world without the Hexenwald (repeatable)
    grid = np.where(grid >= REGION, -1, grid)
    d["regions"] = [r for r in d["regions"] if int(r["id"]) < REGION]
    d["supers"] = [s for s in d["supers"] if int(s["id"]) < SUPER]
    for r in d["regions"]:
        r["neighbors"] = [n for n in r["neighbors"] if int(n) < REGION]
    for s in d["supers"]:
        s["neighbors"] = [n for n in s["neighbors"] if int(n) < SUPER]
    old_land = grid >= 0

    new = footprint(g) & ~old_land
    # cut off one-cell spikes (opening, the old land counts as solid so the join itself stays)
    m = new | old_land
    e = m.copy(); e[1:] &= m[:-1]; e[:-1] &= m[1:]; e[:, 1:] &= m[:, :-1]; e[:, :-1] &= m[:, 1:]
    o = e.copy(); o[1:] |= e[:-1]; o[:-1] |= e[1:]; o[:, 1:] |= e[:, :-1]; o[:, :-1] |= e[:, 1:]
    new &= o
    # one piece that touches the old land, no pinholes (a hole would become an enclosed lake)
    lab, n = label(new | old_land)
    old_label = lab[old_land][0]
    new &= lab == old_label
    old_holes, _ = label(~old_land)
    pre = old_holes > 0
    pre &= ~np.isin(old_holes, [int(old_holes[0, 0]), int(old_holes[0, -1]), int(old_holes[-1, 0]), int(old_holes[-1, -1])])  # the lakes the world already has
    holes, hn = label(~(new | old_land))
    outer = {int(holes[0, 0]), int(holes[0, -1]), int(holes[-1, 0]), int(holes[-1, -1])}
    for h in range(1, hn + 1):
        if h not in outer and not (pre & (holes == h)).any():
            new |= holes == h
    # the old coast stays what it was: only cells that were void are taken
    grid[new] = REGION
    cells = int(new.sum())
    ys, xs = np.nonzero(grid == REGION)
    centre = [float(((xs + 0.5) * CELL).mean()), float(((ys + 0.5) * CELL).mean())]
    touching = set()
    for y, x in zip(ys, xs):
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < g and 0 <= nx < g and 0 <= grid[ny, nx] < REGION:
                touching.add(int(grid[ny, nx]))
    touching = sorted(touching)
    by_id = {int(r["id"]): r for r in d["regions"]}
    depth = min(int(by_id[t]["depth"]) for t in touching) + 1
    for t in touching:
        by_id[t]["neighbors"].append(float(REGION))
    d["regions"].append({"id": float(REGION), "center": centre, "scale": 1.0, "neighbors": [float(t) for t in touching], "depth": float(depth), "area": float(cells * CELL * CELL), "super": float(SUPER)})
    sup_ids = sorted({int(by_id[t]["super"]) for t in touching})
    sup_depth = min(int(d["supers"][s]["depth"]) for s in sup_ids) + 1
    for s in sup_ids:
        d["supers"][s]["neighbors"].append(float(SUPER))
    d["supers"].append({"area": float(cells * CELL * CELL), "biome": BIOME, "center": centre, "depth": float(sup_depth), "id": float(SUPER), "neighbors": [float(s) for s in sup_ids], "regions": [float(REGION)], "name": NAME})
    d["own_biomes"] = [BIOME]

    runs, cur, count = [], int(grid.flat[0]), 0
    for v in grid.flat:
        if int(v) == cur:
            count += 1
        else:
            runs += [float(cur), float(count)]
            cur, count = int(v), 1
    runs += [float(cur), float(count)]
    d["grid"] = runs
    with open(PATH, "w") as f:
        f.write(json.dumps(d, separators=(",", ":")))
    print("Hexenwald: region %d, %d cells = %d tiles^2, depth %d, touches regions %s, centre (%.0f, %.0f)" % (REGION, cells, cells * CELL * CELL, depth, touching, centre[0], centre[1]))
    if len(sys.argv) > 1:
        img = np.zeros((g, g, 3), dtype=np.uint8)
        img[:] = (10, 10, 20)
        img[old_land] = (60, 110, 70)
        img[grid == REGION] = (110, 80, 150)
        save_png(sys.argv[1], np.repeat(np.repeat(img, 3, 0), 3, 1))


if __name__ == "__main__":
    main()
