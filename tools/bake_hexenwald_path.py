#!/usr/bin/env python3
"""Finds the way into the Hexenwald and writes it to data/ground.json `paths` as `hexenwald_path` (px relative to the start tile's centre, like the other
footpaths). It runs on the BAKED relief: a weighted A* over flat level-0 floor that keeps clear of cliffs, the coast and the rivers, starting on the
coast meadow of the town's side and ending in the Hexenwald. Repeatable (replaces its own line). Then bake the picture:
    python3 tools/bake_hexenwald_path.py [debug.png]   then   python3 tools/bake_ground.py --path=hexenwald_path
Needs numpy. Run after tools/bake_hexenwald_terrain.py."""
import heapq, json, math, os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_relief as br
from world_data import W, load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUT = (786, 676)
CENTRE = (821, 892)  # the Hexenwald's middle (data/world_map.json region 31)
WIN = (640, 700, 960, 1000)  # x0, y0, x1, y1 of the search window (tiles)
LINE = '  {"id": "hexenwald_path", "width": 28, "taper_in": 60, "taper_out": 24, "gloom": true, "points": %s}'


def river_mask():
    """True where a river (plus a margin of 5 tiles) lies, from data/rivers_baked.json (px)."""
    m = np.zeros((W, W), dtype=bool)
    x0, y0, x1, y1 = WIN
    for s in json.load(open(os.path.join(ROOT, "data/rivers_baked.json")))["segments"]:
        (ax, ay), (bx, by) = s["a"], s["b"]
        r = max(s["ra"], s["rb"]) / 16.0 + 5.0
        n = max(int(math.hypot(bx - ax, by - ay) / 8.0), 1)
        for i in range(n + 1):
            cx, cy = (ax + (bx - ax) * i / n) / 16.0, (ay + (by - ay) * i / n) / 16.0
            if x0 - 10 < cx < x1 + 10 and y0 - 10 < cy < y1 + 10:
                yy, xx = np.ogrid[int(cy - r):int(cy + r) + 1, int(cx - r):int(cx + r) + 1]
                m[int(cy - r):int(cy + r) + 1, int(cx - r):int(cx + r) + 1] |= (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    return m


def main():
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    hexmask = relief[..., 3] == 205
    old = (relief[..., 3] > 0) & ~hexmask
    flat = (relief[..., 3] > 0) & (relief[..., 0] == 0) & ((relief[..., 1] & 15) == br.FLOOR) & ((sdf - 128) / 8.0 >= 4.0) & ~river_mask()
    clear = np.full((W, W), 99.0)  # steps to the nearest unwalkable tile (capped at 5)
    bad = ~flat
    cur = bad.copy()
    clear[bad] = 0
    for i in range(1, 6):
        nxt = br.dilate(cur) & ~cur
        clear[nxt] = i
        cur |= nxt
    x0, y0, x1, y1 = WIN
    # start: on the old coast meadow ~20 steps from the Hexenwald, nearest the town; goal: flat ground nearest the Hexenwald's middle
    near = np.full((W, W), 99.0)
    cur = hexmask.copy()
    near[cur] = 0
    for i in range(1, 25):
        nxt = br.dilate(cur) & ~cur
        near[nxt] = i
        cur |= nxt
    ok = flat & (clear >= 4)
    ys, xs = np.nonzero(ok & old & (near >= 18) & (near <= 24))
    i = int(np.argmin((xs - HUT[0]) ** 2 + (ys - HUT[1]) ** 2))
    src = (int(xs[i]), int(ys[i]))
    # the witch tower (src/entities/props/witch_tower.gd, origin = the foot of its gate) stands where a 17 x 10 tile rectangle (body behind the gate,
    # the yard in front) is all flat open floor, nearest the Hexenwald's middle; the way ends at its gate
    good = (ok & hexmask).astype(np.int64)
    integ = np.pad(good.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    ys, xs = np.nonzero(good)
    best = None
    for y, x in zip(ys.tolist(), xs.tolist()):
        ya, yb, xa, xb = y - 6, y + 4, x - 8, x + 9
        if ya < 0 or xa < 0 or yb >= W or xb >= W:
            continue
        if integ[yb, xb] - integ[ya, xb] - integ[yb, xa] + integ[ya, xa] == (yb - ya) * (xb - xa):
            d = -((x - src[0]) ** 2 + (y - src[1]) ** 2)  # the farthest fitting place from the way in (the tower lies deep in the forest)
            if best is None or d < best[0]:
                best = (d, x, y)
    assert best, "no flat place for the tower"
    tower = (best[1], best[2])
    dst = (tower[0], tower[1] + 3)
    ok[tower[1] - 6:tower[1] + 1, tower[0] - 7:tower[0] + 8] = False  # the tower's body is no way
    # weighted A*: worn ground is no cheaper, but the way wanders with a slow noise and keeps off cliff feet
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
    wob = br.vnoise(xx / 9.0, yy / 9.0, 77) * 2.6
    cost = np.where(ok, 1.0 + wob + np.where(clear < 5, (5.0 - clear) * 0.6, 0.0), np.inf)
    best, came, heap = {src: 0.0}, {}, [(0.0, src)]
    while heap:
        f, p = heapq.heappop(heap)
        if p == dst:
            break
        g = best[p]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            q = (p[0] + dx, p[1] + dy)
            if not (x0 <= q[0] < x1 and y0 <= q[1] < y1) or not np.isfinite(cost[q[1], q[0]]):
                continue
            ng = g + cost[q[1], q[0]] * (1.4142 if dx and dy else 1.0)
            if ng < best.get(q, 1e18):
                best[q], came[q] = ng, p
                heapq.heappush(heap, (ng + math.hypot(q[0] - dst[0], q[1] - dst[1]), q))
    assert dst in came, "no flat way from %s to %s" % (src, dst)
    route = [dst]
    while route[-1] != src:
        route.append(came[route[-1]])
    route.reverse()
    keep = route[::9] + ([route[-1]] if (len(route) - 1) % 9 else [])
    world = json.load(open(os.path.join(ROOT, "data/world_map.json")))
    cx, cy = world["start"][0] * 16 + 8, world["start"][1] * 16 + 8
    pts = [[x * 16 + 8 - cx, y * 16 + 8 - cy] for x, y in keep]
    path = os.path.join(ROOT, "data/ground.json")
    text = open(path).read()
    entry = LINE % json.dumps(pts, separators=(",", ":"))
    if '"id": "hexenwald_path"' in text:
        text = re.sub(r",\n  \{\"id\": \"hexenwald_path\".*\}", lambda m: ",\n" + entry, text)
    else:
        head, tail = text.split('\n ],\n "props"', 1)
        text = head + ",\n" + entry + '\n ],\n "props"' + tail
    tline = ' "towers": [{"id": "hexenwald_tower", "tile": [%d, %d]}],' % tower
    if '"towers"' in text:
        text = re.sub(r' "towers": \[.*\],', lambda m: tline, text)
    else:
        text = text.replace('\n "arenas": [', '\n' + tline + '\n "arenas": [', 1)
    open(path, "w").write(text)
    json.loads(text)
    print("hexenwald_path: %d tiles of route, %d points, from %s (old coast meadow) to the gate %s of the tower at %s" % (len(route), len(pts), src, dst, tower))
    if len(sys.argv) > 1:
        img = np.zeros((W, W, 3), dtype=np.uint8)
        img[:] = (10, 8, 24)
        img[relief[..., 3] > 0] = (50, 90, 60)
        img[hexmask] = (30, 70, 70)
        img[~flat & (relief[..., 3] > 0)] = (120, 70, 60)
        for x, y in route:
            img[y, x] = (255, 220, 60)
        save_png(sys.argv[1], np.repeat(np.repeat(img[y0 - 20:y1 + 20, x0 - 20:x1 + 20], 3, 0), 3, 1))


if __name__ == "__main__":
    main()
