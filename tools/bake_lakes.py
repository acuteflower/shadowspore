#!/usr/bin/env python3
"""Turn enclosed void components into lakes without changing region ids or relief.

Shares river field/bank/query/collision contracts; overlapping chunks are composited
offline. The exterior void keeps its own SDF. Run after baking coast/rivers.
"""
from collections import deque
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from bake_rivers import collision_rects

ROOT = Path(__file__).resolve().parents[1]
C = 512
T = 16


def enclosed_components(land):
    height, width = land.shape
    visited = land.copy()
    lakes = np.zeros_like(land)
    entries = []
    for y, x in zip(*np.where(~land)):
        if visited[y, x]:
            continue
        queue = deque([(int(x), int(y))])
        visited[y, x] = True
        points = []
        outside = False
        while queue:
            px, py = queue.popleft()
            points.append((px, py))
            outside |= px == 0 or py == 0 or px == width - 1 or py == height - 1
            for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                if 0 <= nx < width and 0 <= ny < height and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((nx, ny))
        if not outside:
            coords = np.asarray(points)
            lakes[coords[:, 1], coords[:, 0]] = True
            lo, hi = coords.min(axis=0), coords.max(axis=0)
            entries.append({'id': f'lake_{lo[0]}_{lo[1]}', 'area_tiles': len(points),
                            'bounds': [*lo.tolist(), *(hi-lo+1).tolist()],
                            'center': ((coords.mean(axis=0) + .5) * T).tolist()})
    return lakes, sorted(entries, key=lambda entry: -entry['area_tiles'])


def _ellipse_mask(xx, yy, cx, cy, rx, ry, angle_deg, seed):
    rng = np.random.default_rng(seed)
    amps = rng.uniform(0.03, 0.09, 4)
    phases = rng.uniform(0, 6.283, 4)
    rad = np.radians(angle_deg)
    ca, sa = np.cos(rad), np.sin(rad)
    ox, oy = xx + .5 - cx, yy + .5 - cy
    dx = (ox * ca + oy * sa) / rx
    dy = (-ox * sa + oy * ca) / ry
    angle = np.arctan2(dy, dx)
    edge = 1 + sum(a * np.sin(angle * (k + 2) + p) for k, (a, p) in enumerate(zip(amps, phases)))
    return np.hypot(dx, dy) < edge


def pond_mask(ponds, shape, land, relief):
    """Inland lakes drawn by hand (data/lakes.json `ponds`): wobbly rotated/multi-lobed ellipses on open flat floor only."""
    mask = np.zeros(shape, dtype=bool)
    entries = []
    yy, xx = np.mgrid[:shape[0], :shape[1]]
    for pond in ponds:
        cx, cy = pond['center']
        rx, ry = pond['radius']
        local = _ellipse_mask(xx, yy, cx, cy, rx, ry, pond.get('angle', 0.0), pond.get('seed', 1))
        for lobe in pond.get('lobes', []):
            lox, loy = lobe['offset']
            lrx, lry = lobe['radius']
            local |= _ellipse_mask(xx, yy, cx + lox, cy + loy, lrx, lry, lobe.get('angle', 0.0), lobe.get('seed', 1))
        wet = np.argwhere(local)
        ok = land[local].all() and not (relief[local][:, 1] & 15).any() and not relief[local][:, 0].any()
        assert ok, f"pond {pond['id']} lies on cliffs, other levels or the coast"
        mask |= local
        lo, hi = wet.min(axis=0)[::-1], wet.max(axis=0)[::-1]
        entries.append({'id': pond['id'], 'area_tiles': int(local.sum()),
                        'bounds': [int(lo[0]), int(lo[1]), int(hi[0] - lo[0] + 1), int(hi[1] - lo[1] + 1)],
                        'center': [cx * T, cy * T], 'inland': True})
    return mask, entries


def distance(mask):
    """Same 3/4 chamfer metric as bake_land_sdf.gd, vectorized along each row."""
    result = np.where(mask, 1 << 20, 0).astype(np.int32)
    ramp = np.arange(mask.shape[1], dtype=np.int32) * 3
    for y in range(mask.shape[0]):
        row = result[y]
        if y > 0:
            np.minimum(row, result[y-1] + 3, out=row)
            row[1:] = np.minimum(row[1:], result[y-1, :-1] + 4)
            row[:-1] = np.minimum(row[:-1], result[y-1, 1:] + 4)
        row[:] = np.minimum.accumulate(row - ramp) + ramp
    for y in range(mask.shape[0]-1, -1, -1):
        row = result[y]
        if y < mask.shape[0]-1:
            np.minimum(row, result[y+1] + 3, out=row)
            row[1:] = np.minimum(row[1:], result[y+1, :-1] + 4)
            row[:-1] = np.minimum(row[:-1], result[y+1, 1:] + 4)
        row[::-1] = np.minimum.accumulate(row[::-1] - ramp) + ramp
    return result / 3.0 - .5


def sample(image, xx, yy):
    x, y = xx / T - .5, yy / T - .5
    ix, iy = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - ix, y - iy
    ix = np.clip(ix, 0, image.shape[1]-2)
    iy = np.clip(iy, 0, image.shape[0]-2)
    return ((image[iy, ix]*(1-fx) + image[iy, ix+1]*fx)*(1-fy)
            + (image[iy+1, ix]*(1-fx) + image[iy+1, ix+1]*fx)*fy)


def bake():
    read = lambda name: json.loads((ROOT / 'data' / f'{name}.json').read_text())
    cfg, rivers, river_cfg = read('lakes'), read('rivers_baked'), read('rivers')
    original = np.asarray(Image.open(ROOT / 'assets/world/land_sdf.png').convert('L'))
    land = original >= 128
    lakes, entries = enclosed_components(land)
    relief_all = np.asarray(Image.open(ROOT / 'assets/world/relief.png'))
    ponds, pond_entries = pond_mask(cfg.get('ponds', []), land.shape, land, relief_all)
    lakes = lakes | ponds
    entries = entries + pond_entries  # appended: the indices of the void lakes stay as they were
    to_lake = np.where(lakes, -distance(lakes), distance(~lakes))
    lake_sdf = np.clip(np.rint(128 + to_lake * 8), 0, 255).astype('uint8')
    filled = land | lakes
    # On exterior void pixels, preserve the original bake exactly. Only filled land
    # distances need updating, so the outer coast cannot move during this operation.
    outside_sdf = original.copy()
    outside_sdf[filled] = np.clip(np.rint(128 + distance(filled)[filled] * 8), 128, 255)
    Image.fromarray(lake_sdf).save(ROOT / 'assets/world/lakes_sdf.png')
    Image.fromarray(outside_sdf).save(ROOT / 'assets/world/outer_sdf.png')
    # Store actual deepest wet tile rather than a centroid that could fall on a peninsula.
    for entry in entries:
        x, y, w, h = entry['bounds']
        iy, ix = np.unravel_index(np.argmin(to_lake[y:y+h, x:x+w]), (h, w))
        entry['deep'] = [(x + int(ix) + .5) * T, (y + int(iy) + .5) * T]
        relief = np.asarray(Image.open(ROOT / 'assets/world/relief.png'))
        block = np.asarray(Image.open(ROOT / 'assets/world/relief_block.png').convert('L'))
        shore_y, shore_x = np.where(lakes[y:y+h, x:x+w] & (to_lake[y:y+h, x:x+w] > -1.5))
        candidates = sorted(zip(shore_x+x, shore_y+y), key=lambda p: np.linalg.norm(np.array(p)*T - entry['center']))
        for sx, sy in candidates:
            for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                dry_x, dry_y = sx+dx, sy+dy
                if not land[dry_y, dry_x] or lakes[dry_y, dry_x] or relief[dry_y, dry_x, 1] & 15:
                    continue
                if relief[dry_y, dry_x, 0] != 0:
                    continue
                x0, x1 = min(sx, dry_x)*4+1, max(sx, dry_x)*4+3
                y0, y1 = min(sy, dry_y)*4+1, max(sy, dry_y)*4+3
                if np.any(block[y0:y1+1, x0:x1+1]):
                    continue
                entry['shore'] = [(int(sx)+.5)*T, (int(sy)+.5)*T]
                entry['dry'] = [(int(dry_x)+.5)*T, (int(dry_y)+.5)*T]
                break
            if 'shore' in entry:
                break
    output = ROOT / 'assets/water/lakes'
    output.mkdir(exist_ok=True)
    keys = set()
    bank_width = river_cfg['bank_width']
    for entry in entries:
        x, y, w, h = entry['bounds']
        lo = np.floor((np.array([x, y])*T - bank_width - 24) / C).astype(int)
        hi = np.floor((np.array([x+w, y+h])*T + bank_width + 24) / C).astype(int)
        keys.update((cx, cy) for cy in range(lo[1], hi[1]+1) for cx in range(lo[0], hi[0]+1))
    chunks = {}
    for cx, cy in sorted(keys):
        yy, xx = np.mgrid[:C, :C]
        xx, yy = xx + cx*C + .5, yy + cy*C + .5
        signed = (sample(lake_sdf.astype(float), xx, yy) - 128) * 2
        signed += (np.sin(xx*.043 + np.sin(yy*.019)) + np.sin(yy*.057 + xx*.013)) * cfg['shore_wobble'] * .5
        if not np.any(signed < bank_width):
            continue
        wet = signed <= 0
        depth = np.clip(-signed / cfg['depth_distance'], 0, 1) ** .8
        field = np.zeros((C, C, 4), dtype=np.uint8)
        field[:, :, 0] = wet * 255
        field[:, :, 1] = np.rint(depth * 255)
        field[:, :, 2] = round((cfg['drift'][0]*.5+.5)*255)
        field[:, :, 3] = round((cfg['drift'][1]*.5+.5)*255)
        bank = np.stack([np.clip(signed / bank_width * 255, 0, 255),
                         np.clip(-signed / 8 * 255, 0, 255), (signed < bank_width)*255], axis=-1).astype('uint8')
        clear = np.clip(signed, -127, 127).reshape(128, 4, 128, 4).min(axis=(1, 3))
        clear = np.clip(clear + 128, 0, 255).astype('uint8')
        key = f'{cx},{cy}'
        record = rivers['chunks'].get(key, {}).copy()
        if record:
            river_field = np.asarray(Image.open(ROOT / record['field'].removeprefix('res://')))
            river_bank = np.asarray(Image.open(ROOT / record['bank'].removeprefix('res://')))
            river_query = np.asarray(Image.open(ROOT / record['query'].removeprefix('res://')))
            field[~wet] = river_field[~wet]
            field[:, :, 1] = np.maximum(field[:, :, 1], np.where(river_field[:, :, 0] > 0, river_field[:, :, 1], 0))
            bank[:, :, :2] = np.stack([np.minimum(bank[:, :, 0], river_bank[:, :, 0]),
                                      np.maximum(bank[:, :, 1], river_bank[:, :, 1])], axis=-1)
            clear = np.minimum(clear, river_query[:, :, 0])
        nav_depth = np.where(field[:, :, 0] > 0, field[:, :, 1], 0).reshape(128, 4, 128, 4).max(axis=(1, 3))
        query = np.stack([clear, nav_depth, np.zeros_like(clear), np.full_like(clear, 255)], axis=-1)
        for name, image in [('field', field), ('bank', bank), ('query', query)]:
            path = output / f'{name}_{cx}_{cy}.png'
            Image.fromarray(image).save(path)
            record[name] = 'res://' + str(path.relative_to(ROOT))
        record['blocks'] = collision_rects(query, river_cfg['deep_threshold'])
        chunks[key] = record
    data = {'version': 1, 'input_hash': hashlib.sha256((ROOT/'assets/world/land_sdf.png').read_bytes()
            + (ROOT/'data/rivers_baked.json').read_bytes() + (ROOT/'data/lakes.json').read_bytes()).hexdigest(),
            'lakes': entries, 'chunks': chunks}
    (ROOT / 'data/lakes_baked.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print(f'Lakes: {len(entries)} enclosed basins, {int(lakes.sum())} tiles, {len(chunks)} streamed chunks')
    from bake_map_water import bake as bake_map
    bake_map()
    return data


if __name__ == '__main__':
    bake()
