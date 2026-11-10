#!/usr/bin/env python3
"""Gives the Hexenwald's new land its relief entry: level 0, floor, grass style, biome byte 205 (the sixth biome of data/biomes.json).
Everything that already was land keeps its pixels. relief_field.png and relief_block.png need nothing: a flat floor has no contour,
no wall and no collision there (checked here). Repeatable. Run after tools/bake_land_sdf.tscn:  python3 tools/bake_hexenwald_relief.py"""
import json, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIOME = 205  # 200 + index of witch_forest in data/biomes.json


def main():
    assert list(json.load(open(os.path.join(ROOT, "data/biomes.json")))).index("witch_forest") == BIOME - 200
    land = np.asarray(Image.open(os.path.join(ROOT, "assets/world/land_sdf.png")).convert("L")) >= 128
    path = os.path.join(ROOT, "assets/world/relief.png")
    relief = np.array(Image.open(path).convert("RGBA"))
    fresh = land & ((relief[..., 3] == 0) | (relief[..., 3] == BIOME))
    assert not (relief[..., 3][~land] != 0).any(), "old relief marks land that the coast no longer has"
    relief[fresh] = (0, 0, 0, BIOME)
    Image.fromarray(relief).save(path)
    field = np.asarray(Image.open(os.path.join(ROOT, "assets/world/relief_field.png")).convert("RGB"))
    block = np.asarray(Image.open(os.path.join(ROOT, "assets/world/relief_block.png")).convert("L"))
    assert not field[fresh].any(), "contour field reaches into the new land"
    assert not block[np.repeat(np.repeat(fresh, 4, 0), 4, 1)].any(), "collision reaches into the new land"
    print("Hexenwald relief: %d tiles (level 0, floor, biome %d)" % (int(fresh.sum()), BIOME))


if __name__ == "__main__":
    main()
