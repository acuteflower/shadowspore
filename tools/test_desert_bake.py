#!/usr/bin/env python3
"""Checks the baked Sonnenquarz-Öde data (map, coast, relief, mesas, connectors, lakes).
Usage: python3 tools/test_desert_bake.py
"""
import hashlib, json, os, sys
from collections import deque
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import load_map, CELL
from bake_lakes import enclosed_components

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = 0


def check(ok, msg):
    global failed
    if not ok:
        failed += 1
        print("FAIL:", msg)


d, grid, _ = load_map(os.path.join(ROOT, "data/world_map.json"))
sdf = np.asarray(Image.open(os.path.join(ROOT, "assets/world/land_sdf.png")).convert("L"))
relief = np.asarray(Image.open(os.path.join(ROOT, "assets/world/relief.png")).convert("RGBA"))
block = np.asarray(Image.open(os.path.join(ROOT, "assets/world/relief_block.png")).convert("L"))
land = sdf >= 128
biomes = json.load(open(os.path.join(ROOT, "data/biomes.json")))

check([int(r["id"]) for r in d["regions"]] == list(range(35)), "regions 0-34 in order")
sup = d["supers"][6]
check(
    int(sup["id"]) == 6
    and sup["biome"] == "quartz_desert"
    and sup["name"] == "Sonnenquarz-Öde"
    and [int(r) for r in sup["regions"]] == [5, 6, 32, 33, 34],
    "super region 6 is Sonnenquarz-Öde with regions [5, 6, 32, 33, 34]",
)
check(
    d["biome"] == "meadow" and d["own_biomes"] == ["witch_forest", "quartz_desert"],
    "meadow stays shared, witch_forest and quartz_desert are own_biomes",
)
check(list(biomes).index("quartz_desert") == 6, "quartz_desert is biome index 6 (relief byte 206)")
check(biomes["quartz_desert"].get("bare") is True and biomes["quartz_desert"].get("arid") == 1.0, "quartz_desert has bare + arid")

for rid in (5, 6, 32, 33, 34):
    reg = d["regions"][rid]
    check(int(reg["super"]) == 6, f"region {rid} belongs to super 6")
    for n in reg["neighbors"]:
        check(rid in [int(x) for x in d["regions"][int(n)]["neighbors"]], f"mutual neighbor {rid} <-> {int(n)}")

des = relief[..., 3] == 206
lvl, kind, style = relief[..., 0], relief[..., 1] & 15, relief[..., 1] >> 4
check(150000 <= int(des.sum()) <= 210000, f"expanded desert size {int(des.sum())} tiles is >150k")
check(not (des & ~land).any(), "desert relief bytes lie strictly on land")
check((style[des & (kind <= 1)] == 6).all(), "all desert floor & cliff walls use sandstone-quartz style 6")
check((kind[des] == 1).sum() > 2500, f"desert has sandstone mesa cliff walls ({int((kind[des] == 1).sum())} tiles)")
check((kind[des] >= 2).sum() > 80, f"desert has ramps and sandstone steps ({int((kind[des] >= 2).sum())} tiles)")

# Walkability: every walkable desert tile is reachable on foot from the town's hut (786, 676)
walk_all = land & (kind != 1)
seen = np.zeros(land.shape, dtype=bool)
q = deque([(676, 786)])
seen[676, 786] = True
while q:
    y, x = q.popleft()
    for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
        if 0 <= ny < 1100 and 0 <= nx < 1100 and walk_all[ny, nx] and not seen[ny, nx] and (lvl[ny, nx] == lvl[y, x] or kind[ny, nx] >= 2 or kind[y, x] >= 2):
            seen[ny, nx] = True
            q.append((ny, nx))
walk_des = des & (kind != 1)
unreached = int((walk_des & ~seen).sum())
check(unreached == 0, f"all {int(walk_des.sum())} walkable desert tiles reachable by ramps/steps from the hut ({unreached} unreached)")

# Waystone versunkene_wachterin (915, 308) remains on flat walkable plateau floor
check(des[308, 915] and kind[308, 915] == 0 and style[308, 915] == 6, "southern gateway waystone (915, 308) stays on flat walkable desert floor")

# Lakes unchanged & hashes up to date
_, entries = enclosed_components(land)
check(len(entries) == 8, f"still 8 enclosed coast lakes, got {len(entries)}")
lk = json.load(open(os.path.join(ROOT, "data/lakes_baked.json")))
expected_hash = hashlib.sha256(
    open(os.path.join(ROOT, "assets/world/land_sdf.png"), "rb").read()
    + open(os.path.join(ROOT, "data/rivers_baked.json"), "rb").read()
    + open(os.path.join(ROOT, "data/lakes.json"), "rb").read()
).hexdigest()
check(lk["input_hash"] == expected_hash, "lakes_baked.json hash matches updated land_sdf.png")

ys_d, xs_d = np.nonzero(des)
dist_hut = float(np.hypot(xs_d - 786, ys_d - 676).min())
check(dist_hut >= 250, f"desert is far north of town (nearest tile {dist_hut:.0f} tiles from hut)")

print(
    "DESERT BAKE: %d tiles, %d cliff tiles, nearest %.0f tiles north of hut, %s"
    % (int(des.sum()), int((kind[des] == 1).sum()), dist_hut, "ok" if not failed else f"{failed} failures")
)
sys.exit(1 if failed else 0)
