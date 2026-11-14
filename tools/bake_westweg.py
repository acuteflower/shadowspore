#!/usr/bin/env python3
"""The Westweg (docs/stadt_westen_konzept.md 2.4): the old road that forks off the caravan's cart road north of Glimmrast and leads west to the east gate
of Hallgrat on the Glaskamm.

It runs on the BAKED world: a weighted A* over flat level-0 floor that keeps clear of cliffs, the coast, lakes and rivers (it may cross a river
only at a baked ford), the Hexenwald and the desert, the invisible walls of the opening's corridor and every hand-made place (trials,
waystones, huts, quarries, arenas). The route is cut into pieces of about 70 tiles (`westweg_1` .. `westweg_N` in data/ground.json `paths`:
they share one curve, `arc` names each piece's stretch, so the baked pictures join without a seam and none of them is huge) and gets a
milestone every 50 tiles of road, counting down to the gate (data/hallgrat.json `milestones`).

    py -3 tools/bake_westweg.py [debug.png]     then     py -3 tools/bake_ground.py --path=westweg

Repeatable: it replaces its own path entries and milestones. Needs numpy."""
import heapq, json, math, os, re, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_relief as br
from bake_ground import catmull
from world_data import W, load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN = (90, 290, 830, 760)  # x0, y0, x1, y1: the search window (tiles)
SRC_NEAR = (788, 573)  # where the road leaves the caravan's cart road (data/ground.json `caravan_road`) north of Glimmrast
JOIN = (793.7, 573.5)  # the fork itself: the Westweg starts in the cart road's ruts
DST = (190, 345)  # in front of the east gate's steps (connector (186, 342), level 0 -> 1)
PIECE = 70.0  # tiles of road per baked picture
MILE = 50  # tiles between two milestones
WIDTH = 30  # px


def read_png_rgb(path):
    """map_water.png is 8-bit RGB (the shared loader only reads grey/RGBA)."""
    from PIL import Image
    return np.array(Image.open(path).convert("RGB"))


def disc(mask, cx, cy, r):
    y0, y1 = max(0, int(cy - r)), min(W, int(cy + r) + 1)
    x0, x1 = max(0, int(cx - r)), min(W, int(cx + r) + 1)
    yy, xx = np.ogrid[y0:y1, x0:x1]
    mask[y0:y1, x0:x1] |= (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def grow(mask, n):
    cur = mask.copy()
    for _ in range(n):
        cur = br.dilate(cur) | cur
    return cur


def steps_to(bad, n):
    """Steps to the nearest `bad` tile, capped at n."""
    d = np.full((W, W), float(n))
    cur = bad.copy()
    d[cur] = 0
    for i in range(1, n):
        nxt = br.dilate(cur) & ~cur
        d[nxt] = i
        cur |= nxt
    return d


def main():
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    water = read_png_rgb(os.path.join(ROOT, "assets/world/map_water.png"))[..., 0] > 0
    rivers = json.load(open(os.path.join(ROOT, "data/rivers_baked.json")))
    ground = json.load(open(os.path.join(ROOT, "data/ground.json")))
    world = json.load(open(os.path.join(ROOT, "data/world_map.json")))
    cx, cy = world["start"][0] * 16 + 8, world["start"][1] * 16 + 8
    biome = relief[..., 3]
    land = biome > 0
    floor = land & (relief[..., 0] == 0) & ((relief[..., 1] & 15) == br.FLOOR) & ~np.isin(biome, (205, 206))
    floor &= (sdf - 128) / 8.0 >= 6.0
    wet = np.zeros((W, W), dtype=bool)  # every river (its radius + 3 tiles) and every lake (+3 tiles)
    for s in rivers["segments"]:
        (ax, ay), (bx, by) = s["a"], s["b"]
        r = max(s["ra"], s["rb"]) / 16.0 + 3.0
        n = max(int(math.hypot(bx - ax, by - ay) / 8.0), 1)
        for i in range(n + 1):
            disc(wet, (ax + (bx - ax) * i / n) / 16.0, (ay + (by - ay) * i / n) / 16.0, r)
    wet |= grow(water, 3)
    ford = np.zeros((W, W), dtype=bool)
    for f in rivers["fords"]:
        fx, fy = f[0], f[1]
        disc(ford, fx / 16.0, fy / 16.0, 2.5)
    keep_out = np.zeros((W, W), dtype=bool)  # the opening's corridor (its invisible walls) and every hand-made place
    corridor = ground.get("barrier", {})
    for p in ground["paths"]:
        if p["id"] in corridor.get("paths", []):
            for (ax, ay), (bx, by) in zip(p["points"][:-1], p["points"][1:]):
                n = max(int(math.hypot(bx - ax, by - ay) / 16.0), 1)
                for i in range(n + 1):
                    disc(keep_out, (cx + ax + (bx - ax) * i / n) / 16.0, (cy + ay + (by - ay) * i / n) / 16.0, corridor.get("half", 150) / 16.0 + 6)
    places = [t["tile"] for t in json.load(open(os.path.join(ROOT, "data/puzzles.json")))["placed"]]
    places += [s["tile"] for s in json.load(open(os.path.join(ROOT, "data/waystones.json")))["statues"]]
    for key in ("huts", "quarries", "wagons", "mines", "arenas", "signposts", "towers", "smith_camps"):
        places += [e["tile"] for e in ground.get(key, []) if "tile" in e]
    for t in places:
        disc(keep_out, t[0], t[1], 11)
    ok = floor & ~keep_out & (~wet | ford)
    cliff = steps_to(land & ~floor & ~wet, 6)
    ok &= cliff >= 2
    x0, y0, x1, y1 = WIN
    ys, xs = np.nonzero(ok[y0:y1, x0:x1])
    xs, ys = xs + x0, ys + y0
    i = int(np.argmin((xs - SRC_NEAR[0]) ** 2 + (ys - SRC_NEAR[1]) ** 2))
    src = (int(xs[i]), int(ys[i]))
    i = int(np.argmin((xs - DST[0]) ** 2 + (ys - DST[1]) ** 2))
    dst = (int(xs[i]), int(ys[i]))
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
    wob = br.vnoise(xx / 14.0, yy / 14.0, 313) * 1.6  # the old road swings gently, it was laid along the land, not across it
    cost = np.where(ok, 1.0 + wob + (6.0 - cliff) * 0.45 + np.where(wet, 40.0, 0.0), np.inf)
    best, came, heap = {src: 0.0}, {}, [(0.0, src)]
    while heap:
        f, p = heapq.heappop(heap)
        if p == dst:
            break
        if f - math.hypot(p[0] - dst[0], p[1] - dst[1]) * 1.0 > best[p] + 1e-6:
            continue
        g = best[p]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            q = (p[0] + dx, p[1] + dy)
            if not (x0 <= q[0] < x1 and y0 <= q[1] < y1):
                continue
            c = cost[q[1], q[0]]
            if not np.isfinite(c):
                continue
            ng = g + c * (1.4142 if dx and dy else 1.0)
            if ng < best.get(q, 1e18):
                best[q], came[q] = ng, p
                heapq.heappush(heap, (ng + math.hypot(q[0] - dst[0], q[1] - dst[1]), q))
    assert dst in came, "no flat way from %s to %s" % (src, dst)
    route = [dst]
    while route[-1] != src:
        route.append(came[route[-1]])
    route.reverse()
    # control points every ~8 route tiles; the Catmull curve through them must stay on good ground (one tile of margin), else densify there
    idx = list(range(0, len(route), 8))
    if idx[-1] != len(route) - 1:
        idx.append(len(route) - 1)
    safe = ok & ~grow(~ok, 1)
    for _ in range(6):
        pts = [(route[k][0] * 16 + 8.0, route[k][1] * 16 + 8.0) for k in idx]
        curve = catmull(pts, step=8.0)
        bad = []
        for j, (px, py) in enumerate(curve):
            tx, ty = int(px // 16), int(py // 16)
            if not safe[ty, tx] and not ok[ty, tx]:
                bad.append(j)
        if not bad:
            break
        seg_of = np.searchsorted(np.cumsum([0] + [math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(pts) - 1)]),
                                 [j * 8.0 for j in bad])
        add = set()
        for s in seg_of:
            s = min(max(int(s) - 1, 0), len(idx) - 2)
            add.add((idx[s] + idx[s + 1]) // 2)
        idx = sorted(set(idx) | add)
    pts = [(JOIN[0] * 16 + 8.0, JOIN[1] * 16 + 8.0)] + [(route[k][0] * 16 + 8.0, route[k][1] * 16 + 8.0) for k in idx]
    curve = catmull(pts, step=2.0)
    seg = np.linalg.norm(np.diff(curve, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(arc[-1])
    print("westweg: %d route tiles, %.0f tiles of road, from %s to %s, %d control points" % (len(route), total / 16.0, src, dst, len(pts)))
    # the pieces (each a baked picture of one stretch of the same curve)
    rel = [[int(round(x - cx)), int(round(y - cy))] for x, y in pts]
    n_pieces = max(1, int(round(total / 16.0 / PIECE)))
    entries = []
    for k in range(n_pieces):
        a0, a1 = total * k / n_pieces, total * (k + 1) / n_pieces
        entries.append('  {"id": "westweg_%d", "width": %d, "taper_in": 120, "taper_out": 6, "old_road": true, "seed": 4711, "arc": [%.1f, %.1f], "points": %s}'
                       % (k + 1, WIDTH, a0, a1, json.dumps(rel, separators=(",", ":"))))
    path = os.path.join(ROOT, "data/ground.json")
    text = open(path, encoding="utf-8").read()
    text = re.sub(r',\n  \{"id": "westweg_\d+".*\}', "", text)
    head, tail = text.split('\n ],\n "props"', 1)
    text = head + ",\n" + ",\n".join(entries) + '\n ],\n "props"' + tail
    json.loads(text)
    open(path, "w", encoding="utf-8").write(text)
    # milestones: every 50 tiles of road counting down to the gate, beside the road on its right (south/east) shoulder, on good ground
    hp = os.path.join(ROOT, "data/hallgrat.json")
    town = json.load(open(hp, encoding="utf-8"))
    stones = []
    tang = np.gradient(curve, axis=0)
    tang /= np.linalg.norm(tang, axis=1)[:, None] + 1e-9
    left = total / 16.0
    n = MILE
    while n < left - 20:
        j = int(np.searchsorted(arc, total - n * 16.0))
        tx, ty = tang[j]
        for side in (1.0, -1.0):
            for off in (WIDTH * 0.5 + 14, WIDTH * 0.5 + 22, WIDTH * 0.5 + 30):
                px, py = curve[j][0] - ty * off * side, curve[j][1] + tx * off * side
                if safe[int(py // 16), int(px // 16)]:
                    break
            else:
                continue
            break
        else:
            print("  no ground for milestone %d" % n)
            n += MILE
            continue
        stones.append({"id": "meile_%d" % n, "number": n, "pos": [int(round(px)), int(round(py))], "tile": [int(px // 16), int(py // 16)]})
        n += MILE
    town["milestones"] = stones
    town["westweg"] = {"paths": ["westweg_%d" % (k + 1) for k in range(n_pieces)], "from": list(src), "to": list(dst), "tiles": int(total / 16.0)}
    json.dump(town, open(hp, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    open(hp, "a", encoding="utf-8").write("\n")
    print("  %d pieces, %d milestones: %s" % (n_pieces, len(stones), ", ".join(str(s["number"]) for s in stones)))
    if len(sys.argv) > 1:
        img = np.zeros((y1 - y0, x1 - x0, 3), dtype=np.uint8)
        img[:] = (10, 8, 24)
        sub = (slice(y0, y1), slice(x0, x1))
        img[land[sub]] = (120, 70, 60)
        img[floor[sub]] = (50, 90, 60)
        img[(wet & land)[sub]] = (40, 70, 140)
        img[(ford & wet)[sub]] = (90, 140, 200)
        img[keep_out[sub] & land[sub]] = (90, 60, 110)
        for x, y in route:
            img[y - y0, x - x0] = (255, 220, 60)
        for s in stones:
            img[s["tile"][1] - y0, s["tile"][0] - x0] = (255, 255, 255)
        save_png(sys.argv[1], np.repeat(np.repeat(img, 2, 0), 2, 1))


if __name__ == "__main__":
    main()
