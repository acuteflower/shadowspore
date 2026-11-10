#!/usr/bin/env python3
"""Stage 2 of the Hexenwald: low hills, hollows and dark slate walls with ramps/steps, made ONLY on the Hexenwald's own tiles
(relief byte A = 205). Everything that is not the Hexenwald keeps its pixels (checked by tools/test_hexenwald_terrain.py): the world's
noise rank would shift if the whole map were baked again, so this reuses the functions of tools/bake_relief.py on the Hexenwald's land alone.
Needs numpy. Run after tools/bake_hexenwald_relief.py (it resets the area to flat first, so it is repeatable):
    python3 tools/bake_hexenwald_terrain.py [debug.png]
then  Godot --headless --import   and  python3 tools/bake_lakes.py (hashes)."""
import os, sys, json
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_relief as br
from world_data import W, load_png, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIOME, STYLE, SEED = 205, 5, 41  # byte of witch_forest, wall style 5 = dark slate (relief.gdshader), noise seed
HUT = (786, 676)  # the way in starts on the side that faces the town
FLAT_JOIN = (12.0, 28.0)  # tiles from the old land: flat .. full relief (the old coast meadow is flat there)
SCALE = 36.0  # hills of about this many tiles (the rest of the world: 50)


def distance_from(src, limit):
    """Steps (4-neighbour) from the set src, 99 beyond limit."""
    d = np.full(src.shape, 99.0)
    d[src] = 0.0
    cur = src.copy()
    for i in range(1, limit + 1):
        nxt = br.dilate(cur) & ~cur
        d[nxt] = i
        cur |= nxt
    return d


def main():
    rng = np.random.default_rng(SEED)
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    sdf = load_png(os.path.join(ROOT, "assets/world/land_sdf.png")).astype(np.int32)
    hexmask = relief[..., 3] == BIOME
    old = (relief[..., 3] > 0) & ~hexmask
    assert hexmask.sum() > 25000, "run tools/bake_hexenwald_relief.py first"
    near_old = br.dilate(br.dilate(br.dilate(br.dilate(hexmask)))) & old
    assert not relief[..., 0][near_old].any(), "old land beside the Hexenwald is not flat"
    coast = (sdf - 128) / 8.0
    join = distance_from(old, 40)
    biome = json.load(open(os.path.join(ROOT, "data/biomes.json")))["witch_forest"]["relief"]

    # the field: warped fbm, rank-normalised over the Hexenwald, flat at the coast and along the join
    Y, X = np.mgrid[0:W, 0:W].astype(np.float64)
    wx = X + (br.vnoise(X / 30.0, Y / 30.0, SEED + 1) - 0.5) * 24.0
    wy = Y + (br.vnoise(X / 30.0 + 50, Y / 30.0 + 50, SEED + 2) - 0.5) * 24.0
    rank = br.rank_normalise(br.fbm(wx / SCALE, wy / SCALE, SEED + 3, 3), hexmask)
    v = 0.5 + (rank - 0.5) * biome["gain"] + biome["bias"]
    flat = br.smoothstep(*br.COAST_FLAT, coast) * br.smoothstep(*FLAT_JOIN, join)
    v = 0.2 + (v - 0.2) * flat
    raw = np.where(hexmask, (v > br.THRESH[0]).astype(np.int8) + (v > br.THRESH[1]) + (v > br.THRESH[2]), 0)

    lvl = np.zeros((W, W), dtype=np.int8)
    below, prev = hexmask.copy(), None
    for k in (1, 2, 3):
        m = (raw >= k) & below
        m = br.drop_small(br.closing(br.opening(m, 2), 2), 60)
        m = ~br.drop_small(~m, 60)
        m &= hexmask
        if k > 1:
            m &= br.erode(br.erode(br.erode(br.erode(br.erode(prev)))))
        prev = m
        lvl += m.astype(np.int8)
        below = m

    # reachability starts on the flat just inside the join, on the side of the town
    ys, xs = np.nonzero(hexmask & (lvl == 0) & (join >= 4) & (join <= 10) & (coast >= 12))
    flat_ok = br.erode(br.erode(br.erode(lvl == 0)))
    pick = flat_ok[ys, xs]
    ys, xs = ys[pick], xs[pick]
    i = int(np.argmin((xs - HUT[0]) ** 2 + (ys - HUT[1]) ** 2))
    start = (int(xs[i]), int(ys[i]))
    style_field = np.full((W, W), STYLE, dtype=np.int8)
    conns = []
    # a way into the hills is a ramp most of the time (a trodden slope), now and then rock steps
    br.pick_kind = lambda res, x, y, rng_, d=br.SOUTH: br.RAMP if rng_.random() < 0.7 else br.STEPS

    def settle():
        for attempt in range(40):
            res = br.analyse(lvl, hexmask, style_field, conns, start)
            if br.connect(res, lvl, hexmask, coast, conns, rng) == 0:
                if br.merge_unreached(res, lvl, hexmask) == 0:
                    return res
        raise SystemExit("cut-off pieces left")

    res = settle()
    br.extras(res, lvl, hexmask, coast, conns, rng)
    res = settle()
    res = br.analyse(lvl, hexmask, style_field, conns, start)
    assert br.merge_unreached(res, lvl, hexmask) == 0, "cut-off pieces left"

    kind, geom, cstyle, fstyle = res["kind"], res["geom"], res["cstyle"], res["fstyle"]
    style = np.where(kind == br.FACE, fstyle, np.where(kind == br.FLOOR, res["src"], cstyle)).astype(np.uint8)
    out = relief.copy()
    out[hexmask, 0] = lvl[hexmask]
    out[hexmask, 1] = (kind | (style << 4))[hexmask]
    out[hexmask, 2] = geom[hexmask]
    out[hexmask, 3] = BIOME
    assert (out[~hexmask] == relief[~hexmask]).all(), "the old world changed"
    save_png(os.path.join(ROOT, "assets/world/relief.png"), out)

    # the smooth contours and collision of the whole map from the combined levels (old tiles come out as before)
    path = os.path.join(ROOT, "data/relief.json")
    old_conns = [c for c in json.load(open(path))["connectors"] if not hexmask[int(c[1]), int(c[0])]]
    all_conns = old_conns + [[int(a) for a in c] for c in conns]
    kind_full = (out[..., 1] & 15).astype(np.uint8)
    br.export_smooth(out[..., 0].astype(np.int8), out[..., 3] > 0, kind_full, all_conns)
    json.dump({"connectors": all_conns}, open(path, "w"))

    hl = lvl[hexmask]
    print("Hexenwald terrain: start %s, level share %s, walls %d tiles, %d connectors (%d ramps, %d steps)" % (
        start, "  ".join("L%d %.1f%%" % (k, 100.0 * float((hl == k).mean())) for k in range(4)), int((kind[hexmask] == br.FACE).sum()),
        len(conns), sum(1 for c in conns if c[2] == br.RAMP), sum(1 for c in conns if c[2] == br.STEPS)))
    if len(sys.argv) > 1:
        ys, xs = np.nonzero(hexmask)
        y0, y1, x0, x1 = max(ys.min() - 30, 0), ys.max() + 30, max(xs.min() - 30, 0), xs.max() + 30
        pal = np.array([[34, 60, 52], [70, 130, 80], [150, 190, 100], [240, 240, 200]], dtype=np.uint8)
        img = pal[out[..., 0]]
        img[old] = img[old] // 2
        img[(out[..., 1] & 15) == br.FACE] = (20, 16, 40)
        img[(out[..., 1] & 15) >= br.RAMP] = (255, 120, 40)
        img[out[..., 3] == 0] = (10, 8, 24)
        img[start[1] - 1:start[1] + 2, start[0] - 1:start[0] + 2] = (255, 0, 0)
        save_png(sys.argv[1], np.repeat(np.repeat(img[y0:y1, x0:x1], 3, 0), 3, 1))


if __name__ == "__main__":
    main()
