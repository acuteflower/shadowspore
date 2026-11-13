#!/usr/bin/env python3
"""Checks the baked Hexenwald data (map, coast, relief, lakes). Usage: python3 tools/test_hexenwald_bake.py"""
import hashlib, json, os, sys
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
land = sdf >= 128
biomes = json.load(open(os.path.join(ROOT, "data/biomes.json")))

check([int(r["id"]) for r in d["regions"]] == list(range(len(d["regions"]))) and len(d["regions"]) >= 32, "regions in order")
sup = d["supers"][5]
check(int(sup["id"]) == 5 and sup["biome"] == "witch_forest" and sup["name"] == "Hexenwald" and [int(r) for r in sup["regions"]] == [31], "super region 5 is the Hexenwald")
check(d["biome"] == "meadow" and "witch_forest" in d["own_biomes"], "meadow stays shared, the Hexenwald is its own biome")
check(list(biomes).index("witch_forest") == 5, "witch_forest is the sixth biome (relief byte 205)")
check(biomes["witch_forest"].get("bare") is True, "no props yet")
reg = d["regions"][31]
cells = int((grid == 31).sum())
check(int(reg["area"]) == cells * CELL * CELL, "region area matches its cells")
check(all(int(r["super"]) == 5 for r in [reg]) and all(31 in [int(n) for n in d["regions"][int(n)]["neighbors"]] for n in reg["neighbors"]), "neighbour lists are mutual")
check(all(int(r["super"]) != 5 for r in d["regions"] if int(r["id"]) != 31), "only region 31 belongs to Hexenwald")

tiles = int(land[np.repeat(np.repeat(grid == 31, CELL, 0), CELL, 1)].sum())
check(25000 <= tiles <= 60000, "size %d tiles is big enough and not huge" % tiles)

fresh = relief[..., 3] == 205
check(fresh.sum() > 25000 and not (fresh & ~land).any(), "the Hexenwald's relief bytes lie on land only")
check(relief[..., 0][fresh].max() <= 3 and (relief[..., 0][fresh] == 0).mean() > 0.5, "mostly level 0, hills up to level 3 (stage 2: tools/test_hexenwald_terrain.py)")
cell_of = np.repeat(np.repeat(grid, CELL, 0), CELL, 1)
check(((cell_of == 31) & land & ~fresh).sum() < 0.01 * tiles, "(almost) all land of region 31 has the biome byte")
check(not (fresh & (cell_of >= 0) & (cell_of != 31)).any() or (fresh & (cell_of >= 0) & (cell_of != 31)).sum() < 0.02 * tiles, "the biome byte does not leak into the old regions")

# one landmass: the Hexenwald is reachable by land from the town
labels = np.zeros(land.shape, dtype=np.int32)
from collections import deque
q = deque([(676, 786)]); labels[676, 786] = 1
while q:
    y, x = q.popleft()
    for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
        if 0 <= ny < 1100 and 0 <= nx < 1100 and land[ny, nx] and not labels[ny, nx]:
            labels[ny, nx] = 1
            q.append((ny, nx))
check(labels[892, 821] == 1, "Hexenwald centre is reachable on land from the town's hut")
check(labels[fresh].all(), "every Hexenwald tile is part of the one landmass")

# no new lakes
lakes, entries = enclosed_components(land)
check(len(entries) == 8, "still the eight lakes of the world, got %d" % len(entries))
lk = json.load(open(os.path.join(ROOT, "data/lakes_baked.json")))
check(lk["input_hash"] == hashlib.sha256((os.path.join(ROOT, "assets/world/land_sdf.png") and open(os.path.join(ROOT, "assets/world/land_sdf.png"), "rb").read()) + open(os.path.join(ROOT, "data/rivers_baked.json"), "rb").read() + open(os.path.join(ROOT, "data/lakes.json"), "rb").read()).hexdigest(), "lakes bake is up to date with the coast")

# near the town, but not too near
ys, xs = np.nonzero(fresh)
near = float(np.hypot(xs - 786, ys - 676).min())
check(100 <= near <= 190, "nearest Hexenwald tile is %.0f tiles from the hut" % near)
check(float(np.hypot(xs.mean() - 786, ys.mean() - 676)) <= 260, "centre is within a short walk of the town")
print("HEXENWALD BAKE: %d tiles, nearest %.0f tiles from the hut, %s" % (int(fresh.sum()), near, "ok" if not failed else "%d failures" % failed))
sys.exit(1 if failed else 0)
