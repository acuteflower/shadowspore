"""Ensure the map atlas still represents every actual baked water field, including chunk seams."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
atlas = np.asarray(Image.open(ROOT / 'assets/world/map_water.png'))
relief = Image.open(ROOT / 'assets/world/relief.png')
assert atlas.shape == (relief.height, relief.width, 3)
data = json.loads((ROOT / 'data/rivers_baked.json').read_text())
lake_path = ROOT / 'data/lakes_baked.json'
if lake_path.exists():
    data['chunks'].update(json.loads(lake_path.read_text())['chunks'])
expected = np.zeros(atlas.shape[:2], dtype=np.uint8)
checks = 1
for key, chunk in data['chunks'].items():
    cx, cy = map(int, key.split(','))
    field = Image.open(ROOT / chunk['field'].removeprefix('res://'))
    coverage = np.asarray(field.getchannel('R').reduce(16))
    x, y = cx * 32, cy * 32
    h, w = min(32, atlas.shape[0] - y), min(32, atlas.shape[1] - x)
    expected[y:y+h, x:x+w] = coverage[:h, :w]
    checks += 1
assert np.abs(atlas[:, :, 0].astype(int) - expected.astype(int)).max() <= 1, 'Re-bake map water after changing river fields'
assert np.count_nonzero(atlas[:, :, 0]) > 1000
assert np.any((atlas[:, :, 0] > 0) & (atlas[:, :, 0] < 128)), 'Narrow banks/tributaries lost'
checks += 3
if lake_path.exists():
    lake_sdf = np.asarray(Image.open(ROOT / 'assets/world/lakes_sdf.png').convert('L'))
    inside = lake_sdf < 128
    assert np.all(atlas[:, :, 2][inside] > 30), 'A lake has no cartographic wash'
    assert np.all(atlas[:, :, 2][lake_sdf >= 152] == 0), 'Lake wash leaks into unrelated terrain'
    checks += 2
    for lake in json.loads(lake_path.read_text())['lakes']:
        x, y, w, h = lake['bounds']
        tones = atlas[y:y+h, x:x+w, 2][inside[y:y+h, x:x+w]]
        assert int(tones.max()) == 255 and int(tones.max()) - int(tones.min()) > 96, 'Lake lost its shore-to-center shading'
        checks += 1
print(f'MAP WATER: {checks} checks, PASS; water coverage and lake washes verified')
