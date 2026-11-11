"""Topology, coast preservation, composite water, queries and offline collision for lakes."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
read = lambda name: json.loads((ROOT/'data'/f'{name}.json').read_text())
lakes, rivers, cfg = read('lakes_baked'), read('rivers_baked'), read('rivers')
original = np.asarray(Image.open(ROOT/'assets/world/land_sdf.png').convert('L'))
outer = np.asarray(Image.open(ROOT/'assets/world/outer_sdf.png').convert('L'))
lake_sdf = np.asarray(Image.open(ROOT/'assets/world/lakes_sdf.png').convert('L'))
mask = lake_sdf < 128
ponds = [lake for lake in lakes['lakes'] if lake.get('inland')]
assert len(lakes['lakes']) == 8 + len(ponds) == 9 and int(mask.sum()) == sum(lake['area_tiles'] for lake in lakes['lakes'])
pond_zone = np.zeros_like(mask)
for pond in ponds:
    x, y, w, h = pond['bounds']
    pond_zone[y:y+h, x:x+w] = True
assert not np.any(mask & (original >= 128) & ~pond_zone), 'Lake replaces existing land'
assert not np.any(mask[[0, -1]]) and not np.any(mask[:, [0, -1]]), 'Exterior void became lake'
assert np.all(outer[mask] >= 128), 'Void still cuts through a lake'
assert np.array_equal(outer[(original < 128) & ~mask], original[(original < 128) & ~mask]), 'Exterior coastline changed'
assert lakes['input_hash'] == hashlib.sha256((ROOT/'assets/world/land_sdf.png').read_bytes()
    + (ROOT/'data/rivers_baked.json').read_bytes() + (ROOT/'data/lakes.json').read_bytes()).hexdigest(), 'Lake bake is stale'
checks = 6
for key, record in lakes['chunks'].items():
    field = np.asarray(Image.open(ROOT/record['field'].removeprefix('res://')))
    bank = np.asarray(Image.open(ROOT/record['bank'].removeprefix('res://')))
    nav = np.asarray(Image.open(ROOT/record['query'].removeprefix('res://')))
    assert field.shape == (512, 512, 4) and bank.shape == (512, 512, 3) and nav.shape == (128, 128, 4)
    wet = field[:, :, 0] > 0
    max_depth = np.where(wet, field[:, :, 1], 0).reshape(128, 4, 128, 4).max(axis=(1, 3))
    assert np.array_equal(nav[:, :, 1], max_depth), 'Query loses deep pixels at a shore/seam'
    expected = (nav[:, :, 0] <= 128) & (nav[:, :, 1] > cfg['deep_threshold']*255)
    actual = np.zeros((128, 128), dtype=int)
    for x, y, w, h in record['blocks']:
        actual[y//4:(y+h)//4, x//4:(x+w)//4] += 1
    assert np.array_equal(expected, actual), 'Serialized lake collision differs from water depth'
    if key in rivers['chunks']:
        old = np.asarray(Image.open(ROOT/rivers['chunks'][key]['field'].removeprefix('res://')))
        assert np.all(wet[old[:, :, 0] > 0]), 'Lake composite removed river water'
    checks += 4
for lake in lakes['lakes']:
    assert 'shore' in lake and 'dry' in lake, 'No accessible shore sample'
    px, py = lake['deep']
    key = f'{int(px)//512},{int(py)//512}'
    field = np.asarray(Image.open(ROOT/lakes['chunks'][key]['field'].removeprefix('res://')))
    assert field[int(py)%512, int(px)%512, 0] == 255 and field[int(py)%512, int(px)%512, 1] > 220
    assert outer[int(py)//16, int(px)//16] > 240
    checks += 3
print(f'LAKE BAKE: {checks} checks, PASS; {len(lakes["lakes"])} lakes, original regions/relief preserved')
