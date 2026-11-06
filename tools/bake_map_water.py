#!/usr/bin/env python3
"""Downsample the actual river fields into the M-map atlas. No world regeneration.

R = area coverage, G = wet-area mean depth, B = cartographic lake depth
(0 outside lakes, 0.12 at the shore, 1 at each basin's deepest point). One pixel per tile;
area averaging and mipmaps preserve small tributaries at overview zoom.
Run after baking rivers: python3 tools/bake_map_water.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TILE = 16
WORLD = 1100


def bake():
    data = json.loads((ROOT / 'data/rivers_baked.json').read_text())
    lakes_path = ROOT / 'data/lakes_baked.json'
    if lakes_path.exists():
        data['chunks'].update(json.loads(lakes_path.read_text())['chunks'])
    atlas = np.zeros((WORLD, WORLD, 3), dtype=np.uint8)
    for key, chunk in data['chunks'].items():
        cx, cy = map(int, key.split(','))
        field = np.asarray(Image.open(ROOT / chunk['field'].removeprefix('res://')))
        wet = field[:, :, 0].astype(np.float32) / 255.0
        size = field.shape[0] // TILE
        coverage = wet.reshape(size, TILE, size, TILE).mean(axis=(1, 3))
        depth = (field[:, :, 1] * wet).reshape(size, TILE, size, TILE).mean(axis=(1, 3))
        mean_depth = np.divide(depth, coverage, out=np.zeros_like(depth), where=coverage > 0)
        x, y = cx * size, cy * size
        width, height = min(size, WORLD - x), min(size, WORLD - y)
        atlas[y:y + height, x:x + width, 0] = np.rint(coverage[:height, :width] * 255)
        atlas[y:y + height, x:x + width, 1] = np.rint(mean_depth[:height, :width])
    if lakes_path.exists():
        # Physical depth reaches its maximum near the bank. Give each entire lake
        # a separate, gentle ink wash, following its real outline and peninsulas.
        from bake_lakes import distance
        lake_sdf = np.asarray(Image.open(ROOT / 'assets/world/lakes_sdf.png').convert('L'))
        inside = lake_sdf < 128
        shore_distance = distance(inside)
        lake_depth = np.where(lake_sdf < 152, 0.12, 0.0)
        for lake in json.loads(lakes_path.read_text())['lakes']:
            x, y, width, height = lake['bounds']
            region = np.s_[y:y+height, x:x+width]
            local = shore_distance[region]
            depth = 0.12 + 0.88 * np.clip(local / max(float(local.max()), 1.0), 0, 1) ** 0.72
            lake_depth[region] = np.where(inside[region], depth, lake_depth[region])
        atlas[:, :, 2] = np.rint(lake_depth * 255)
    output = ROOT / 'assets/world/map_water.png'
    Image.fromarray(atlas).save(output)
    print(f'Map water: {len(data["chunks"])} fields, {np.count_nonzero(atlas[:, :, 0])} wet tiles -> {output.name}')
    return atlas


if __name__ == '__main__':
    bake()
