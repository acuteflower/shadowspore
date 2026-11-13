#!/usr/bin/env python3
"""Bakes relief and sandstone-quartz mesas for Sonnenquarz-Öde (quartz_desert, biome byte 206, wall style 6):
- Regions 5 & 6 keep their existing sculpted heights, walls and connectors (so the waystone at (915, 308) and southern transitions stay
  untouched), restyled to biome byte 206 and sandstone-quartz wall style 6.
- Regions 32 & 33 (the new northern bay land) get sculpted desert mesas, stepped plateaus (levels 0..3), sandstone-quartz cliff faces,
  wind-blown sand ramps and hewn sandstone steps, joining smoothly at level 0 along the old R5/R6 north coast.
- Exports updated relief.png, relief_field.png, relief_block.png and data/relief.json without altering any non-desert tile in relief.png.
Run after tools/bake_land_sdf.tscn:
    python3 tools/bake_desert_terrain.py [debug.png]
then Godot --headless --path . --import and python3 tools/bake_lakes.py
"""
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_relief as br
from world_data import W, CELL, load_map, load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIOME, STYLE, SEED = 206, 6, 73  # quartz_desert index 6 -> 206, wall style 6 = desert quartz-sandstone
GATEWAY = (845, 255)  # central flat gateway between R5/R6 and the new northern desert bay
FLAT_JOIN = (9.0, 24.0)  # smooth level-0 join band north of R5/R6
SCALE = 42.0  # broad desert mesas & canyons


def distance_from(src, limit):
    d = np.full(src.shape, 99.0)
    d[src] = 0.0
    cur = src.copy()
    for i in range(1, limit + 1):
        nxt = br.dilate(cur) & ~cur
        d[nxt] = i
        cur |= nxt
    return d


def main():
    biomes = json.load(open(os.path.join(ROOT, "data/biomes.json")))
    assert list(biomes).index("quartz_desert") == BIOME - 200
    d, grid, _ = load_map(os.path.join(ROOT, "data/world_map.json"))
    cell_reg = np.repeat(np.repeat(grid, CELL, 0), CELL, 1)

    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    land = sdf >= 128
    coast = (sdf - 128) / 8.0
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png")).copy()
    # Strip any previous northern-bay desert bake that now falls outside land so re-bakes are idempotent
    stale_void = (~land) & (relief[..., 3] == BIOME)
    relief[stale_void] = 0
    assert not (relief[..., 3][~land] != 0).any(), "relief marks non-desert land outside land_sdf"

    # Identify desert tiles: claimed R5+R6 (already had baked heights) vs all newly added land (R32..R34 + SDF seam rounding)
    in_r56 = land & np.isin(cell_reg, [5, 6])
    prior_bay = land & (relief[..., 3] == BIOME) & ~in_r56
    in_new_cells = land & np.isin(cell_reg, [32, 33, 34])
    was_void = land & (relief[..., 3] == 0)
    new_mask = in_new_cells | prior_bay | was_void
    claimed_old = in_r56 & ~new_mask
    desert_all = claimed_old | new_mask
    assert new_mask.sum() > 90000, f"expected >90k new desert tiles, got {new_mask.sum()}"

    # Verify the join between claimed_old (R5/R6) and new_mask is completely level 0 so no cliff seam appears
    join_band = br.dilate(br.dilate(br.dilate(new_mask))) & (land & ~new_mask)
    assert not relief[..., 0][join_band].any(), "old coast touching new desert bay has non-zero level!"

    # Sculpt desert mesas & plateaus on new_mask
    rng = np.random.default_rng(SEED)
    old_world = land & ~new_mask
    join = distance_from(old_world, 36)
    b_cfg = biomes["quartz_desert"]["relief"]

    Y, X = np.mgrid[0:W, 0:W].astype(np.float64)
    wx = X + (br.vnoise(X / 34.0, Y / 34.0, SEED + 1) - 0.5) * 26.0
    wy = Y + (br.vnoise(X / 34.0 + 40.0, Y / 34.0 + 40.0, SEED + 2) - 0.5) * 26.0
    rank = br.rank_normalise(br.fbm(wx / SCALE, wy / SCALE, SEED + 3, 3), new_mask)
    v = 0.5 + (rank - 0.5) * b_cfg["gain"] + b_cfg["bias"]
    flat = br.smoothstep(*br.COAST_FLAT, coast) * br.smoothstep(*FLAT_JOIN, join)
    v = 0.2 + (v - 0.2) * flat
    raw = np.where(new_mask, (v > br.THRESH[0]).astype(np.int8) + (v > br.THRESH[1]) + (v > br.THRESH[2]), 0)

    lvl = np.zeros((W, W), dtype=np.int8)
    below, prev = new_mask.copy(), None
    for k in (1, 2, 3):
        m = (raw >= k) & below
        m = br.drop_small(br.closing(br.opening(m, 2), 2), 75)
        m = ~br.drop_small(~m, 75)
        m &= new_mask
        if k > 1:
            m &= br.erode(br.erode(br.erode(br.erode(br.erode(prev)))))
        prev = m
        lvl += m.astype(np.int8)
        below = m

    # Start reachability on flat level-0 ground just inside the southern join of R32/R33
    ys, xs = np.nonzero(new_mask & (lvl == 0) & (join >= 4) & (join <= 12) & (coast >= 10))
    flat_ok = br.erode(br.erode(br.erode(lvl == 0)))
    pick = flat_ok[ys, xs]
    ys, xs = ys[pick], xs[pick]
    idx = int(np.argmin((xs - GATEWAY[0]) ** 2 + (ys - GATEWAY[1]) ** 2))
    start = (int(xs[idx]), int(ys[idx]))

    style_field = np.full((W, W), STYLE, dtype=np.int8)
    conns = []
    # Mix of wind-blown sand ramps (58%) and chiseled ruin sandstone steps (42%)
    br.pick_kind = lambda res, x, y, rng_, d_=br.SOUTH: br.RAMP if rng_.random() < 0.58 else br.STEPS

    def settle():
        for _attempt in range(45):
            res = br.analyse(lvl, new_mask, style_field, conns, start)
            if br.connect(res, lvl, new_mask, coast, conns, rng) == 0:
                if br.merge_unreached(res, lvl, new_mask) == 0:
                    return res
        raise SystemExit("cut-off mesa pieces left in new desert")

    res = settle()
    br.extras(res, lvl, new_mask, coast, conns, rng)
    res = settle()
    res = br.analyse(lvl, new_mask, style_field, conns, start)
    assert br.merge_unreached(res, lvl, new_mask) == 0, "cut-off pieces left"

    kind, geom, cstyle, fstyle = res["kind"], res["geom"], res["cstyle"], res["fstyle"]
    style = np.where(kind == br.FACE, fstyle, np.where(kind == br.FLOOR, res["src"], cstyle)).astype(np.uint8)

    out = relief.copy()
    # 1. Restyle claimed R5 & R6 to sandstone-quartz style 6 and biome 206 while keeping their exact heights & connectors
    out[claimed_old, 1] = (out[claimed_old, 1] & 15) | (STYLE << 4)
    out[claimed_old, 3] = BIOME

    # 2. Write sculpted mesas & connectors onto new northern desert bay (R32 & R33)
    out[new_mask, 0] = lvl[new_mask]
    out[new_mask, 1] = (kind | (style << 4))[new_mask]
    out[new_mask, 2] = geom[new_mask]
    out[new_mask, 3] = BIOME

    assert (out[~desert_all] == relief[~desert_all]).all(), "non-desert tiles in relief.png were modified!"
    save_png(os.path.join(ROOT, "assets/world/relief.png"), out)

    # Export combined smooth contours (relief_field.png) and 4px collision (relief_block.png)
    cpath = os.path.join(ROOT, "data/relief.json")
    old_conns = [c for c in json.load(open(cpath))["connectors"] if land[int(c[1]), int(c[0])] and not new_mask[int(c[1]), int(c[0])]]
    all_conns = old_conns + [[int(a) for a in c] for c in conns]
    kind_full = (out[..., 1] & 15).astype(np.uint8)
    br.export_smooth(out[..., 0].astype(np.int8), out[..., 3] > 0, kind_full, all_conns)
    json.dump({"connectors": all_conns}, open(cpath, "w"))

    dl = out[desert_all, 0]
    dk = out[desert_all, 1] & 15
    print(
        "Sonnenquarz-Öde terrain: %d total tiles (%d claimed R5/R6 + %d new bay), levels %s, cliff walls %d tiles, +%d new connectors (%d ramps, %d steps)"
        % (
            int(desert_all.sum()),
            int(claimed_old.sum()),
            int(new_mask.sum()),
            "  ".join("L%d %.1f%%" % (k, 100.0 * float((dl == k).mean())) for k in range(4)),
            int((dk == br.FACE).sum()),
            len(conns),
            sum(1 for c in conns if c[2] == br.RAMP),
            sum(1 for c in conns if c[2] == br.STEPS),
        )
    )
    if len(sys.argv) > 1:
        ys, xs = np.nonzero(desert_all)
        y0, y1, x0, x1 = max(ys.min() - 24, 0), min(ys.max() + 24, W), max(xs.min() - 24, 0), min(xs.max() + 24, W)
        pal = np.array([[196, 146, 82], [220, 168, 98], [236, 194, 128], [248, 226, 184]], dtype=np.uint8)
        img = pal[out[..., 0]]
        img[~desert_all & (out[..., 3] > 0)] = (58, 102, 68)
        img[(out[..., 1] & 15) == br.FACE] = (88, 52, 74)
        img[(out[..., 1] & 15) >= br.RAMP] = (120, 240, 228)
        img[out[..., 3] == 0] = (12, 10, 26)
        save_png(sys.argv[1], np.repeat(np.repeat(img[y0:y1, x0:x1], 2, 0), 2, 1))


if __name__ == "__main__":
    main()
