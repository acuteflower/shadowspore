#!/usr/bin/env python3
"""Adds the Sonnenquarz-Öde (quartz_desert) to data/world_map.json:
- Moves the unbuilt northern coastal regions 5 and 6 out of super region 1 (Versunkene Ruinen) into super region 6.
- Grows three large organic northern desert regions (32 West Wing, 33 Central Dune Basin, 34 Eastern Mesa Reach) across the
  northwestern, northern, and northeastern void bay, joining ONLY regions 5 and 6 so Mornath's arena (region 4) and all other
  regions' coastlines & SDFs remain untouched.
Repeatable: strips regions >= 32 and super >= 6 and restores regions 5 & 6 first.
Usage: python3 tools/bake_desert_map.py [preview.png]
Afterwards: Godot --headless --path . res://tools/bake_land_sdf.tscn, python3 tools/bake_desert_terrain.py, python3 tools/bake_lakes.py
"""
import json, os, sys
from collections import deque
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import CELL, W, load_map, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "data/world_map.json")
REG_W, REG_C, REG_E = 32, 33, 34
NEW_REGS = (REG_W, REG_C, REG_E)
CLAIMED = (5, 6)
SUPER, BIOME, NAME = 6, "quartz_desert", "Sonnenquarz-Öde"
SEED = 67


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


def dilate(m, n=1):
    r = m.copy()
    for _ in range(n):
        nxt = r.copy()
        nxt[1:] |= r[:-1]
        nxt[:-1] |= r[1:]
        nxt[:, 1:] |= r[:, :-1]
        nxt[:, :-1] |= r[:, 1:]
        r = nxt
    return r


def erode(m, n=1):
    r = m.copy()
    for _ in range(n):
        nxt = r.copy()
        nxt[1:] &= r[:-1]; nxt[0] = False
        nxt[:-1] &= r[1:]; nxt[-1] = False
        nxt[:, 1:] &= r[:, :-1]; nxt[:, 0] = False
        nxt[:, :-1] &= r[:, 1:]; nxt[:, -1] = False
        r = nxt
    return r


def label(mask):
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


def lobe(X, Y, bx, by, rx, ry, seed, amp=0.34):
    ang = np.arctan2((Y - by) / ry, (X - bx) / rx)
    lobes = vnoise(np.cos(ang) * 1.9 + 4.0, np.sin(ang) * 1.9 + 4.0, seed) - 0.5
    ripple = vnoise(np.cos(ang) * 4.6 + 8.0, np.sin(ang) * 4.6 + 8.0, seed + 1) - 0.5
    rad = 1.0 + lobes * amp + ripple * 0.12
    warp = (vnoise(X / 28.0, Y / 28.0, seed + 2) - 0.5) * 0.14
    return np.hypot((X - bx) / rx, (Y - by) / ry) + warp < rad


def footprint(g):
    cy, cx = np.mgrid[0:g, 0:g]
    X, Y = (cx + 0.5) * CELL, (cy + 0.5) * CELL
    # Broad multi-lobe northern continent sweeping west to join Das Leerenblühen (R0/R1/R4) on land, north toward the void rim, and east past R6
    nw_headland = lobe(X, Y, 535.0, 118.0, 182.0, 102.0, SEED + 41, 0.32)
    west_join = lobe(X, Y, 575.0, 198.0, 155.0, 92.0, SEED + 45, 0.28)
    west_basin = lobe(X, Y, 718.0, 132.0, 164.0, 112.0, SEED, 0.34)
    north_crown = lobe(X, Y, 845.0, 104.0, 172.0, 84.0, SEED + 53, 0.32)
    east_reach = lobe(X, Y, 958.0, 166.0, 114.0, 132.0, SEED + 10, 0.32)
    se_cape = lobe(X, Y, 1004.0, 264.0, 68.0, 78.0, SEED + 67, 0.28)
    south_bridge = lobe(X, Y, 828.0, 224.0, 182.0, 96.0, SEED + 20, 0.30)
    body = nw_headland | west_join | west_basin | north_crown | east_reach | se_cape | south_bridge

    # Organic northwest coastal curve meeting R0's north cape cleanly without overhanging past it into the western sea
    nw_warp = (vnoise(X / 32.0, Y / 32.0, SEED + 73) - 0.5) * 44.0
    body &= X >= (368.0 + nw_warp)

    # Soft organic coastal margin near the outer world frame so coves & headlands vary naturally
    coast_jit = (vnoise(X / 34.0, Y / 34.0, SEED + 89) - 0.5) * 44.0 + (vnoise(X / 14.0, Y / 14.0, SEED + 93) - 0.5) * 16.0
    body &= (Y >= 34.0 + coast_jit * 0.65) & (Y >= 18.0)
    body &= (X <= 1064.0 + coast_jit * 0.55) & (X <= 1082.0)
    body &= Y <= 344.0
    return body


def main():
    d, grid, start_region = load_map(PATH)
    g = grid.shape[0]

    # Reset any previous desert bake (idempotent)
    grid = np.where(grid >= REG_W, -1, grid)
    d["regions"] = [r for r in d["regions"] if int(r["id"]) < REG_W]
    d["supers"] = [s for s in d["supers"] if int(s["id"]) < SUPER]
    for r in d["regions"]:
        r["neighbors"] = [float(int(n)) for n in r["neighbors"] if int(n) < REG_W]
        if int(r["id"]) in CLAIMED:
            r["super"] = 1.0

    old_land = grid >= 0
    r56 = (grid == 5) | (grid == 6)
    # Allow direct seamless land connection to northern regions (R0, R1, R3, R4, R5, R6, R7); keep southern eastern coast (R12, y>=336) buffered
    cy_s, _ = np.mgrid[0:g, 0:g]
    south_other = old_land & ~r56 & ((cy_s + 0.5) * CELL >= 332.0)
    safe_zone = ~dilate(south_other, 5)

    new = footprint(g) & ~old_land & safe_zone
    # Smooth 1-cell spikes while treating R5+R6 as solid anchor
    solid = new | r56
    solid = dilate(erode(solid, 1), 1)
    new &= solid & ~old_land & safe_zone

    # Keep only the piece connected to R5+R6
    lab, _ = label(new | r56)
    anchor_lbl = int(lab[r56][0])
    new &= lab == anchor_lbl

    # Fill any newly enclosed void pinholes so no accidental lakes are created
    old_holes, _ = label(~old_land)
    outer_old = {int(old_holes[0, 0]), int(old_holes[0, -1]), int(old_holes[-1, 0]), int(old_holes[-1, -1])}
    pre_lakes = (old_holes > 0) & ~np.isin(old_holes, list(outer_old))
    holes, hn = label(~(new | old_land))
    outer_new = {int(holes[0, 0]), int(holes[0, -1]), int(holes[-1, 0]), int(holes[-1, -1])}
    for h in range(1, hn + 1):
        if h not in outer_new and not (pre_lakes & (holes == h)).any():
            new |= (holes == h) & safe_zone

    # Split new northern continent along two organic warped meridians into Regions 32 (West), 33 (Central), and 34 (East)
    cy, cx = np.mgrid[0:g, 0:g]
    X, Y = (cx + 0.5) * CELL, (cy + 0.5) * CELL
    split_wc = 708.0 + (vnoise(X / 52.0, Y / 52.0, SEED + 31) - 0.5) * 54.0
    split_ce = 902.0 + (vnoise(X / 52.0, Y / 52.0, SEED + 47) - 0.5) * 54.0
    w_mask = new & (X < split_wc)
    c_mask = new & (X >= split_wc) & (X < split_ce)
    e_mask = new & (X >= split_ce)

    # Ensure each new region is a single 4-connected component (reassign any tiny detached slivers across the nearest seam)
    masks = {REG_W: w_mask, REG_C: c_mask, REG_E: e_mask}
    for _pass in range(2):
        for rid, neighbor_rid in ((REG_W, REG_C), (REG_E, REG_C), (REG_C, REG_E)):
            m = masks[rid]
            rlab, rn = label(m)
            if rn > 1:
                sizes = np.bincount(rlab.ravel())
                sizes[0] = 0
                keep = int(np.argmax(sizes))
                extra = m & (rlab != keep)
                masks[rid] = m & ~extra
                masks[neighbor_rid] = masks[neighbor_rid] | extra

    for rid in NEW_REGS:
        grid[masks[rid]] = rid

    # Move regions 5 & 6 to super 6 and append regions 32, 33, 34
    by_id = {int(r["id"]): r for r in d["regions"]}
    for cid in CLAIMED:
        by_id[cid]["super"] = float(SUPER)

    for rid in NEW_REGS:
        ys, xs = np.nonzero(grid == rid)
        centre = [float(((xs + 0.5) * CELL).mean()), float(((ys + 0.5) * CELL).mean())]
        rec = {
            "id": float(rid),
            "center": centre,
            "scale": 1.0,
            "neighbors": [],
            "depth": 0.0,
            "area": float(int((grid == rid).sum()) * CELL * CELL),
            "super": float(SUPER),
        }
        d["regions"].append(rec)
        by_id[rid] = rec

    # Recompute mutual region adjacencies involving 32, 33, 34
    for rid in NEW_REGS:
        ys, xs = np.nonzero(grid == rid)
        touch = set()
        for y, x in zip(ys, xs):
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < g and 0 <= nx < g and grid[ny, nx] >= 0 and int(grid[ny, nx]) != rid:
                    touch.add(int(grid[ny, nx]))
        by_id[rid]["neighbors"] = [float(t) for t in sorted(touch)]
        for t in touch:
            cur_n = [int(x) for x in by_id[t]["neighbors"]]
            if rid not in cur_n:
                by_id[t]["neighbors"].append(float(rid))

    # Recompute BFS depth for the newly added regions from existing depths
    for rid in NEW_REGS:
        nbr_depths = [int(by_id[int(n)]["depth"]) for n in by_id[rid]["neighbors"] if int(n) < REG_W]
        by_id[rid]["depth"] = float((min(nbr_depths) + 1) if nbr_depths else 6)
    for _ in range(3):
        for rid in NEW_REGS:
            nbr_depths = [int(by_id[int(n)]["depth"]) for n in by_id[rid]["neighbors"]]
            by_id[rid]["depth"] = float(min(int(by_id[rid]["depth"]), min(nbr_depths) + 1))

    # Update Super 1 (Versunkene Ruinen) after handing off Regions 5 & 6, and build Super 6 (Sonnenquarz-Öde)
    sup_by_id = {int(s["id"]): s for s in d["supers"]}
    s1 = sup_by_id[1]
    s1["regions"] = [float(int(r)) for r in s1["regions"] if int(r) not in CLAIMED]
    s1_cells = np.isin(grid, [int(r) for r in s1["regions"]])
    s1_ys, s1_xs = np.nonzero(s1_cells)
    s1["area"] = float(int(s1_cells.sum()) * CELL * CELL)
    s1["center"] = [float(((s1_xs + 0.5) * CELL).mean()), float(((s1_ys + 0.5) * CELL).mean())]

    s6_regs = [5, 6, REG_W, REG_C, REG_E]
    s6_cells = np.isin(grid, s6_regs)
    s6_ys, s6_xs = np.nonzero(s6_cells)
    s6 = {
        "area": float(int(s6_cells.sum()) * CELL * CELL),
        "biome": BIOME,
        "center": [float(((s6_xs + 0.5) * CELL).mean()), float(((s6_ys + 0.5) * CELL).mean())],
        "depth": 0.0,
        "id": float(SUPER),
        "neighbors": [],
        "regions": [float(r) for r in s6_regs],
        "name": NAME,
    }
    d["supers"].append(s6)
    sup_by_id[SUPER] = s6

    # Recompute super-region neighbor graph cleanly from region neighbor graph so 1 and 6 are exact & mutual
    sup_adj = {sid: set() for sid in sup_by_id}
    for r in d["regions"]:
        sa = int(r["super"])
        for n in r["neighbors"]:
            sb = int(by_id[int(n)]["super"])
            if sa != sb:
                sup_adj[sa].add(sb)
                sup_adj[sb].add(sa)
    for sid, s in sup_by_id.items():
        s["neighbors"] = [float(x) for x in sorted(sup_adj[sid])]

    # BFS super depth from start super
    start_sup = int(by_id[int(start_region)]["super"])
    s_depth = {start_sup: 0}
    q = deque([start_sup])
    while q:
        cur = q.popleft()
        for nxt in sorted(sup_adj[cur]):
            if nxt not in s_depth:
                s_depth[nxt] = s_depth[cur] + 1
                q.append(nxt)
    for sid, s in sup_by_id.items():
        s["depth"] = float(s_depth[sid])

    d["own_biomes"] = ["witch_forest", BIOME]
    new_layout = "a4657b2dae21f404a87e9c9aeab933bafdc5e2b8f8b67fe746d443d7b22064f1"
    compat = d.get("editor_compatible_maps", [])
    prev_hashes = {c["hash"] for c in compat}
    if "f8f913acf3c853444a58baa3087da6757165b923e5a3b628585bc90125b51f90" not in prev_hashes:
        compat.append({"hash": "f8f913acf3c853444a58baa3087da6757165b923e5a3b628585bc90125b51f90", "layout": new_layout})
    for entry in compat:
        entry["layout"] = new_layout
    d["editor_compatible_maps"] = compat

    # Run-length encode grid
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

    new_total = sum(int(masks[r].sum()) for r in NEW_REGS) * CELL * CELL
    print(
        "Sonnenquarz-Öde baked: super %d, regions %s, total %d tiles^2 (new bay: %d tiles^2, R5+R6: %d tiles^2), bounds X=%.0f..%.0f Y=%.0f..%.0f, center (%.0f, %.0f), touches supers %s"
        % (
            SUPER,
            s6_regs,
            int(s6["area"]),
            new_total,
            int(r56.sum() * CELL * CELL),
            float(s6_xs.min() * CELL),
            float((s6_xs.max() + 1) * CELL),
            float(s6_ys.min() * CELL),
            float((s6_ys.max() + 1) * CELL),
            s6["center"][0],
            s6["center"][1],
            [int(x) for x in s6["neighbors"]],
        )
    )
    if len(sys.argv) > 1:
        img = np.zeros((g, g, 3), dtype=np.uint8)
        img[:] = (10, 10, 20)
        img[old_land & ~r56] = (60, 110, 70)
        img[grid == 31] = (90, 75, 130)
        img[r56] = (195, 145, 78)
        img[masks[REG_W]] = (214, 162, 86)
        img[masks[REG_C]] = (228, 178, 98)
        img[masks[REG_E]] = (240, 194, 114)
        save_png(sys.argv[1], np.repeat(np.repeat(img, 3, 0), 3, 1))


if __name__ == "__main__":
    main()
