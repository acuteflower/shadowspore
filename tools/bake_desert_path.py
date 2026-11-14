#!/usr/bin/env python3
"""Finds the ancient sand-drifted caravan trail (`desert_caravan_path`) across Sonnenquarz-Öde
and writes it to `data/ground.json` `paths` (px relative to start tile centre).
Runs a weighted A* on baked `relief.png` flat level-0 floor inside Überregion 6 (`quartz_desert` + border steppe),
starting north of Waystone 'Wächterin der Versunkenen' (915, 308), passing near `oasis_twins` and `oasis_lagoon`,
and curving east into Region 34's deep ruin field.
Then run:
    py -3 tools/bake_desert_path.py
    py -3 tools/bake_ground.py --path=desert_caravan_path
"""
import heapq
import json
import math
import os
import re
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_relief as br
from world_data import W, load_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN = (620, 45, 1080, 365)
LINE = '  {"id": "desert_caravan_path", "width": 28, "taper_in": 52, "taper_out": 52, "quartz_caravan": true, "points": %s}'


def water_mask():
    """True where a river or oasis pond (plus 4-tile margin) lies."""
    m = np.zeros((W, W), dtype=bool)
    x0, y0, x1, y1 = WIN
    for s in json.load(open(os.path.join(ROOT, "data/rivers_baked.json")))["segments"]:
        (ax, ay), (bx, by) = s["a"], s["b"]
        r = max(s["ra"], s["rb"]) / 16.0 + 4.5
        n = max(int(math.hypot(bx - ax, by - ay) / 8.0), 1)
        for i in range(n + 1):
            cx, cy = (ax + (bx - ax) * i / n) / 16.0, (ay + (by - ay) * i / n) / 16.0
            if x0 - 15 < cx < x1 + 15 and y0 - 15 < cy < y1 + 15:
                ya, yb = max(0, int(cy - r)), min(W - 1, int(cy + r) + 1)
                xa, xb = max(0, int(cx - r)), min(W - 1, int(cx + r) + 1)
                yy, xx = np.ogrid[ya:yb, xa:xb]
                m[ya:yb, xa:xb] |= (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    lakes = json.load(open(os.path.join(ROOT, "data/lakes.json")))
    for key in ("lakes", "ponds"):
        for lk in lakes.get(key, []):
            cx, cy = lk["center"]
            rx, ry = lk["radius"][0] + 4.5, lk["radius"][1] + 4.5
            ya, yb = max(0, int(cy - ry - 4)), min(W - 1, int(cy + ry + 5))
            xa, xb = max(0, int(cx - rx - 4)), min(W - 1, int(cx + rx + 5))
            yy, xx = np.ogrid[ya:yb, xa:xb]
            m[ya:yb, xa:xb] |= ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0
            for lb in lk.get("lobes", []):
                lcx, lcy = cx + lb["offset"][0], cy + lb["offset"][1]
                lrx, lry = lb["radius"][0] + 4.5, lb["radius"][1] + 4.5
                lya, lyb = max(0, int(lcy - lry - 4)), min(W - 1, int(lcy + lry + 5))
                lxa, lxb = max(0, int(lcx - lrx - 4)), min(W - 1, int(lcx + lrx + 5))
                lyy, lxx = np.ogrid[lya:lyb, lxa:lxb]
                m[lya:lyb, lxa:lxb] |= ((lxx - lcx) / lrx) ** 2 + ((lyy - lcy) / lry) ** 2 <= 1.0
    # Keep clear of Waystone (915, 308) plinth
    wy, wx = 308, 915
    yy, xx = np.ogrid[wy - 7:wy + 8, wx - 7:wx + 8]
    m[wy - 7:wy + 8, wx - 7:wx + 8] |= (xx - wx) ** 2 + (yy - wy) ** 2 <= 49
    return m


def nearest_flat(ok, target):
    ys, xs = np.nonzero(ok)
    i = int(np.argmin((xs - target[0]) ** 2 + (ys - target[1]) ** 2))
    return (int(xs[i]), int(ys[i]))


def astar(cost, src, dst):
    x0, y0, x1, y1 = WIN
    best, came, heap = {src: 0.0}, {}, [(0.0, src)]
    while heap:
        _f, p = heapq.heappop(heap)
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
    assert dst in came, f"no flat desert caravan route from {src} to {dst}"
    seg = [dst]
    while seg[-1] != src:
        seg.append(came[seg[-1]])
    seg.reverse()
    return seg


def main():
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    desert = relief[..., 3] == 206
    flat = desert & (relief[..., 0] == 0) & ((relief[..., 1] & 15) == br.FLOOR) & ((sdf - 128) / 8.0 >= 4.5) & ~water_mask()
    clear = np.full((W, W), 99.0)
    bad = ~flat
    cur = bad.copy()
    clear[bad] = 0
    for i in range(1, 6):
        nxt = br.dilate(cur) & ~cur
        clear[nxt] = i
        cur |= nxt
    ok_raw = flat & (clear >= 2)
    # Restrict to the main connected desert floor component containing oasis_twins (806, 224)
    from collections import deque
    seed = nearest_flat(ok_raw, (806, 224))
    ok = np.zeros((W, W), dtype=bool)
    ok[seed[1], seed[0]] = True
    q = deque([seed])
    x0, y0, x1, y1 = WIN
    while q:
        px, py = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = px + dx, py + dy
            if x0 <= nx < x1 and y0 <= ny < y1 and ok_raw[ny, nx] and not ok[ny, nx]:
                ok[ny, nx] = True
                q.append((nx, ny))

    # Waypoints entirely inside Sonnenquarz-Öde (biome byte 206):
    # 0) Southern steppe/desert gate pass entering Region 32 -> near (826, 318)
    # 1) Southern palm shore of oasis_twins (798, 209) -> (806, 224)
    # 2) Eastern shore of oasis_lagoon (708, 139) -> (736, 152)
    # 3) Singing Quartz Pass (Region 33/34 border) -> (846, 134)
    # 4) Sunken Ruin Field heart in Region 34 -> (948, 146)
    targets = [(826, 318), (806, 224), (736, 152), (846, 134), (948, 146)]
    wps = [nearest_flat(ok & (clear >= 4), t) for t in targets]

    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
    wob = br.vnoise(xx / 10.0, yy / 10.0, 193) * 2.4
    cost = np.where(ok, 1.0 + wob + np.where(clear < 5, (5.0 - clear) ** 2 * 0.9, 0.0), np.inf)

    route = [wps[0]]
    for a, b in zip(wps[:-1], wps[1:]):
        seg = astar(cost, a, b)
        route.extend(seg[1:])

    # Split into 3 compact, frustum-cullable ancient caravan road stretches with natural dune-buried gaps between them
    n_r = len(route)
    s1 = int(n_r * 0.34)
    s2 = int(n_r * 0.67)
    stretches = [
        ("desert_caravan_south", route[: max(s1 - 7, 16)]),
        ("desert_caravan_oases", route[s1 + 7 : max(s2 - 7, s1 + 24)]),
        ("desert_caravan_ruins", route[s2 + 7 :]),
    ]
    world = json.load(open(os.path.join(ROOT, "data/world_map.json")))
    cx, cy = world["start"][0] * 16 + 8, world["start"][1] * 16 + 8
    entries = []
    total_pts = 0
    for seg_id, sub in stretches:
        keep = sub[::8] + ([sub[-1]] if (len(sub) - 1) % 8 else [])
        pts = [[x * 16 + 8 - cx, y * 16 + 8 - cy] for x, y in keep]
        total_pts += len(pts)
        entries.append(
            '  {"id": "%s", "width": 28, "taper_in": 48, "taper_out": 48, "quartz_caravan": true, "points": %s}'
            % (seg_id, json.dumps(pts, separators=(",", ":")))
        )

    path = os.path.join(ROOT, "data/ground.json")
    text = open(path, encoding="utf-8").read()
    text = re.sub(r",\n  \{\"id\": \"desert_caravan_[^\"]*\".*\}", "", text)
    head, tail = text.split('\n ],\n "props"', 1)
    text = head + ",\n" + ",\n".join(entries) + '\n ],\n "props"' + tail
    tmp_path = path + ".tmp"
    open(tmp_path, "w", encoding="utf-8").write(text)
    os.replace(tmp_path, path)
    json.loads(text)

    # Also report 2 verified flat level-0 trial spots (clear >= 5, >= 16 tiles away from route) in Region 33 & Region 34
    route_arr = np.array(route, dtype=np.int32)
    for label, target in (("prism_seal_r33", (682, 196)), ("prism_seal_r34", (968, 174))):
        ys, xs = np.nonzero(ok & (clear >= 5))
        order = np.argsort((xs - target[0]) ** 2 + (ys - target[1]) ** 2)
        for idx in order[:4000]:
            tx, ty = int(xs[idx]), int(ys[idx])
            d2 = np.min((route_arr[:, 0] - tx) ** 2 + (route_arr[:, 1] - ty) ** 2)
            if d2 >= 15 * 15 and np.all(flat[ty - 5:ty + 6, tx - 5:tx + 6]):
                print(f"verified_trial_spot {label}: [{tx}, {ty}]")
                break

    print(f"desert_caravan: {len(route)} route tiles across 3 stretches ({total_pts} points), waypoints={wps}")


if __name__ == "__main__":
    main()
