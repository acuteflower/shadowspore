#!/usr/bin/env python3
"""Add hand-authored river links to the EXISTING baked drainage network.

`data/river_links.json` lists polylines in tiles (first point = where the water comes from,
last point = where it flows to). The links are added to `data/rivers_baked.json` as extra edges /
segments / fords (tagged with `link`), and ONLY the 512 px chunks they touch are rasterised again,
with the very same code as `bake_rivers.py` (section 9), so every other chunk stays byte-identical.
Running it again replaces the old links. Run it BEFORE `tools/bake_lakes.py` (the lake bake composites
river chunks), then `Godot --headless --path . --import`.

    py -3 tools/bake_river_links.py [--check]      (--check: only validate the terrain, write nothing)
"""
from pathlib import Path
import json, math, sys
import numpy as np
from PIL import Image

from bake_rivers import collision_rects

ROOT = Path(__file__).resolve().parents[1]
C = 512
T = 16
STEP = 10.0  # px between two edges of a link


def read(name):
    return json.loads((ROOT / 'data' / f'{name}.json').read_text())


def snap(spec, edges):
    """A control point may be {"snap": [x, y]} = the nearest node of an existing river (tiles)."""
    if isinstance(spec, dict):
        want = np.array(spec['snap'], dtype=float) * T
        best, node, rad = 1e18, None, 0.0
        for e in edges:
            if 'link' in e:
                continue
            for key, r in (('a', e['ra']), ('b', e['rb'])):
                d = np.linalg.norm(np.array(e[key]) - want)
                if d < best:
                    best, node, rad = d, e[key], r
        return np.array(node, dtype=float), rad
    return np.array(spec, dtype=float) * T, None


def catmull(points, step):
    pts = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for j in range(n):
            t = j / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(points[-1])
    return out


def build_link(link, edges, cfg):
    ctrl, radii = [], []
    for spec in link['points']:
        p, r = snap(spec, edges)
        ctrl.append(p)
        radii.append(r)
    ra = radii[0] if radii[0] is not None else link['radius'][0]
    rb = radii[-1] if radii[-1] is not None else link['radius'][1]
    line = catmull(ctrl, STEP)
    # a gentle meander that dies out at both ends, so the joins hit the old rivers exactly
    total = sum(np.linalg.norm(line[i + 1] - line[i]) for i in range(len(line) - 1))
    amp, wave, phase = link.get('meander', [10.0, 150.0, 0.0])
    pts, s = [], 0.0
    for i, p in enumerate(line):
        if i > 0:
            s += np.linalg.norm(line[i] - line[i - 1])
        a, b = line[max(i - 1, 0)], line[min(i + 1, len(line) - 1)]
        d = b - a
        d = d / max(np.linalg.norm(d), 1e-6)
        k = math.sin(math.pi * s / max(total, 1e-6)) ** 0.7
        pts.append(p + np.array([-d[1], d[0]]) * amp * k * math.sin(s / wave * 2 * math.pi + phase))
    pts[0], pts[-1] = ctrl[0].copy(), ctrl[-1].copy()  # the joins must be exact, not just close
    out_edges, ford_pts = [], []
    s = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        t0, t1 = s / total, (s + np.linalg.norm(b - a)) / total
        s += np.linalg.norm(b - a)
        out_edges.append({'a': a.tolist(), 'b': b.tolist(),
                          'ra': ra + (rb - ra) * t0, 'rb': ra + (rb - ra) * t1,
                          'flow': link.get('flow', 0.8), 'basin': link.get('basin', 0),
                          'level': 0, 'head_a': 0.0, 'head_b': 0.0, 'link': link['id']})
        before, after = int((s - np.linalg.norm(b - a)) / cfg['ford_spacing']), int(s / cfg['ford_spacing'])
        if before != after and 90 < s < total - 90:
            ford_pts.append([*((a + b) * 0.5).tolist(), cfg['ford_half_length'], link['id']])
    return out_edges, ford_pts


def validate(edges, cfg, ground_clear):
    """Every link point must stand on open level-0 floor with room for the water and its bank."""
    relief = np.array(Image.open(ROOT / 'assets/world/relief.png').convert('RGBA'))
    sdf = np.array(Image.open(ROOT / 'assets/world/land_sdf.png').convert('L'))
    problems = []
    ends = {}
    for e in edges:
        ends.setdefault(e['link'], []).append(e)
    for e in edges:
        for key, r in (('a', e['ra']), ('b', e['rb'])):
            x, y = e[key]
            first, last = ends[e['link']][0]['a'], ends[e['link']][-1]['b']
            if min(math.hypot(x - first[0], y - first[1]), math.hypot(x - last[0], y - last[1])) < 48:
                continue  # the joins sit where the old rivers already are
            reach = int(math.ceil((r + cfg['bank_width'] * 0.5) / T))
            tx, ty = int(x // T), int(y // T)
            win = relief[ty - reach:ty + reach + 1, tx - reach:tx + reach + 1]
            if np.any(win[:, :, 1] & 15) or np.any(win[:, :, 0] != 0):
                problems.append((e['link'], round(x / T), round(y / T), 'cliff / level nearby'))
            if sdf[ty - reach:ty + reach + 1, tx - reach:tx + reach + 1].min() < 150:
                problems.append((e['link'], round(x / T), round(y / T), 'coast nearby'))
    return sorted(set(problems))


def rasterize(cx, cy, segs, basins, fords, cfg):
    yy, xx = np.mgrid[:C, :C]
    xx = xx + cx * C + 0.5
    yy = yy + cy * C + 0.5
    best = np.full((C, C), np.inf)
    depth = np.zeros((C, C))
    fx = np.zeros((C, C))
    fy = np.ones((C, C))
    wobble = np.sin(xx * 0.08 + np.sin(yy * 0.035) * 1.8) * 1.1 + np.sin(yy * 0.14 + xx * 0.03) * 0.5
    for e in segs:
        a, b = np.array(e['a']), np.array(e['b'])
        d = b - a
        l2 = np.dot(d, d)
        if l2 < 1e-4:
            continue
        t = np.clip(((xx - a[0]) * d[0] + (yy - a[1]) * d[1]) / l2, 0.0, 1.0)
        rad = e['ra'] + (e['rb'] - e['ra']) * t
        dist_val = np.hypot(xx - a[0] - d[0] * t, yy - a[1] - d[1] * t)
        signed = dist_val - rad - wobble
        hit = signed < best
        best = np.minimum(best, signed)
        depth = np.where(hit, np.clip(1.0 - dist_val / rad, 0.0, 1.0) ** 0.8, depth)
        l = math.sqrt(l2)
        fx = np.where(hit, d[0] / l, fx)
        fy = np.where(hit, d[1] / l, fy)
    for basin in basins:
        bx, by = basin['outlet']
        r = basin['radius']
        dist_val = np.hypot(xx - bx, yy - by)
        sd = dist_val - r - wobble
        hit = sd < best
        best = np.minimum(best, sd)
        depth = np.where(hit, np.clip(1.0 - dist_val / r, 0.0, 1.0) ** 0.8, depth)
    wet = best <= 0.0
    if not np.any(best < cfg['bank_width']):
        return None
    for ford in fords:
        x, y, half = ford[0], ford[1], ford[2]
        if x + 75 < cx * C or x - 75 >= (cx + 1) * C or y + 75 < cy * C or y - 75 >= (cy + 1) * C:
            continue
        dist_val = np.hypot(xx - x, yy - y)
        along = np.abs((xx - x) * fx + (yy - y) * fy)
        blend = np.maximum(np.clip((along - half * 0.4) / (half * 0.6), 0.0, 1.0), np.clip((dist_val - 50.0) / 25.0, 0.0, 1.0))
        blend = blend * blend * (3.0 - 2.0 * blend)
        depth = np.minimum(depth, cfg['ford_depth'] * (1.0 - blend) + depth * blend)
    field = np.stack([wet * 255, depth * 255, (fx * 0.5 + 0.5) * 255, (fy * 0.5 + 0.5) * 255], axis=-1).astype('uint8')
    bank = np.stack([np.clip(best / cfg['bank_width'] * 255.0, 0.0, 255.0),
                     np.clip(-best / 8.0 * 255.0, 0.0, 255.0), np.zeros_like(best)], axis=-1).astype('uint8')
    clear = np.clip(best, -127, 127).reshape(128, 4, 128, 4).min(axis=(1, 3))
    dep = np.where(wet, depth, 0).reshape(128, 4, 128, 4).max(axis=(1, 3))
    nav = np.stack([np.clip(clear + 128, 0, 255), dep * 255, np.zeros_like(dep), np.full_like(dep, 255)], axis=-1).astype('uint8')
    return field, bank, nav


def chunks_of(segs, reach):
    result = {}
    for seg in segs:
        a, b = np.array(seg['a']), np.array(seg['b'])
        lo = np.floor((np.minimum(a, b) - reach) / C).astype(int)
        hi = np.floor((np.maximum(a, b) + reach) / C).astype(int)
        for cy in range(lo[1], hi[1] + 1):
            for cx in range(lo[0], hi[0] + 1):
                result.setdefault((cx, cy), []).append(seg)
    return result


def bake(check_only=False):
    cfg = read('rivers')
    links = read('river_links')['links']
    data = read('rivers_baked')
    # forget the links of an earlier run
    for key in ('edges', 'segments'):
        data[key] = [e for e in data[key] if 'link' not in e]
    data['fords'] = [f for f in data['fords'] if len(f) < 4]
    new_edges, new_fords = [], []
    for link in links:
        edges, fords = build_link(link, data['edges'], cfg)
        new_edges += edges
        new_fords += fords
    problems = validate(new_edges, cfg, None)
    for p in problems:
        print('PROBLEM', p)
    if check_only or problems:
        print(f'{len(new_edges)} link edges, {len(new_fords)} fords, {len(problems)} problems')
        return 1 if problems else 0
    data['edges'] += new_edges
    data['segments'] += [dict(e) for e in new_edges]
    data['fords'] += new_fords
    reach = cfg['max_radius'] * 1.5 + cfg['bank_width'] + 6
    all_chunks = chunks_of(data['segments'], reach)
    touched = chunks_of(new_edges, reach)
    output = ROOT / 'assets/water/world'
    written = 0
    for (cx, cy) in sorted(touched):
        result = rasterize(cx, cy, all_chunks[(cx, cy)], data['basins'], data['fords'], cfg)
        if result is None:
            continue
        field, bank, nav = result
        Image.fromarray(field).save(output / f'field_{cx}_{cy}.png')
        Image.fromarray(bank).save(output / f'bank_{cx}_{cy}.png')
        Image.fromarray(nav).save(output / f'query_{cx}_{cy}.png')
        old = data['chunks'].get(f'{cx},{cy}', {})
        data['chunks'][f'{cx},{cy}'] = {
            'blocks': collision_rects(nav, cfg['deep_threshold']),
            'field': f'res://assets/water/world/field_{cx}_{cy}.png',
            'bank': f'res://assets/water/world/bank_{cx}_{cy}.png',
            'query': f'res://assets/water/world/query_{cx}_{cy}.png',
            'waterfalls': old.get('waterfalls', []),
            'cliff_springs': old.get('cliff_springs', []),
        }
        written += 1
    data['chunks'] = dict(sorted(data['chunks'].items(), key=lambda kv: tuple(map(int, kv[0].split(',')))))
    (ROOT / 'data/rivers_baked.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print(f'River links: {len(links)} links, {len(new_edges)} edges, {len(new_fords)} fords, {written} chunks re-rasterised')
    return 0


if __name__ == '__main__':
    sys.exit(bake('--check' in sys.argv))
