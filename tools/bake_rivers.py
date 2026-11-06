#!/usr/bin/env python3
"""Bake an organic, multi-elevation drainage network on the EXISTING world.
Features:
- Rivers originate at high-elevation springs or Felswand-Quelltöpfen (cliff springs).
- Rivers cross relief contours over south-facing cliff walls via animated WATERFALLS.
- Rivers meander naturally and empty into the VOID at the island coastline.
- Cross-channel shallow fords allow player traversal.
- Fields are rasterized in world coordinates per 512px chunk with 1px boundaries.
"""
from pathlib import Path
import json, heapq, math, hashlib
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
C = 512
T = 16

def read(name):
    return json.loads((ROOT / 'data' / f'{name}.json').read_text())

def collision_rects(nav, threshold):
    active = {}
    rects = []
    for y in range(129):
        spans = {}
        start = -1
        for x in range(129):
            blocked = x < 128 and y < 128 and nav[y, x, 0] <= 128 and nav[y, x, 1] > threshold * 255
            if blocked and start < 0:
                start = x
            if not blocked and start >= 0:
                span = (start, x)
                spans[span] = active.get(span, y)
                start = -1
        for span, first in active.items():
            if span not in spans:
                rects.append([span[0] * 4, first * 4, (span[1] - span[0]) * 4, (y - first) * 4])
        active = spans
    return rects

def generate():
    cfg = read('rivers')
    world = read('world_map')
    ground = read('ground')
    rng = np.random.default_rng(cfg['seed'])

    relief = np.array(Image.open(ROOT / 'assets/world/relief.png').convert('RGBA'))
    sdf = np.array(Image.open(ROOT / 'assets/world/land_sdf.png').convert('L'))
    levels = relief[:, :, 0]
    kinds = relief[:, :, 1] & 15
    styles = relief[:, :, 1] >> 4
    n = relief.shape[0]

    # 1. World regions and biome filtering
    flat = []
    runs = world['grid']
    for i in range(0, len(runs), 2):
        flat.extend([int(runs[i])] * int(runs[i+1]))
    ids = np.repeat(np.repeat(np.array(flat).reshape(n//4, n//4), 4, axis=0), 4, axis=1)
    green_ids = [int(r['id']) for r in world['regions'] if world['supers'][int(r['super'])]['biome'] in ('meadow', 'mist_forest')]

    # 2. Protection mask (story areas, start, huts, paths)
    protected = Image.new('L', (n, n), 0)
    draw = ImageDraw.Draw(protected)
    start = world['start']
    sx, sy = start[0] * T, start[1] * T
    r = cfg['start_margin'] / T
    draw.ellipse((sx/T - r, sy/T - r, sx/T + r, sy/T + r), fill=255)

    for decal in read('ground_baked')['decals']:
        im = Image.open(ROOT / decal['texture'].replace('res://', ''))
        x, y = decal['x'] / T, decal['y'] / T
        m = cfg['story_margin'] / T
        draw.rectangle((x - m, y - m, x + im.width/T + m, y + im.height/T + m), fill=255)

    def protect(val):
        if isinstance(val, dict):
            if 'tile' in val and isinstance(val['tile'], list) and len(val['tile']) == 2:
                x, y = val['tile']
                rad = max(cfg['story_margin'] / T, float(val.get('clear_radius', 0)) + 8)
                draw.ellipse((x - rad, y - rad, x + rad, y + rad), fill=255)
            for child in val.values():
                protect(child)
        elif isinstance(val, list):
            for child in val:
                protect(child)

    protect(ground)
    prot_arr = np.array(protected) > 0

    # 3. Inland floor mask: rivers must stay strictly inland (sdf >= 165)
    wall_any = (kinds != 0)
    wall_dilated = np.array(Image.fromarray(wall_any.astype('uint8') * 255).filter(ImageFilter.MaxFilter(5))) > 0
    inland_floor = np.isin(ids, green_ids) & (sdf >= 165) & (kinds == 0) & (~wall_dilated) & (relief[:, :, 3] > 0) & (~prot_arr)

    # 4. Discrete routing graph on pitch = 2 tiles (32 px)
    grid = 2
    offset = 1
    pitch = grid * T  # 32 px
    gn = n // grid

    # Clear floor for waterfall lip/base clearance
    clear_floor = (kinds == 0) & (~prot_arr)
    waterfall_links = {}
    for y in range(3, n - 5):
        match = (kinds[y, :] == 1) & (kinds[y+1, :] == 1) & clear_floor[y-3, :] & clear_floor[y+4, :]
        for x in np.where(match)[0]:
            if sdf[y, x] >= 165:
                l_up = int(levels[y-3, x])
                l_down = int(levels[y+4, x])
                if l_up > l_down:
                    upper_node = ((y - 3) // grid, x // grid)
                    lower_node = ((y + 4) // grid, x // grid)
                    waterfall_links[upper_node] = (lower_node, y, x, int(styles[y, x]))

    reverse_waterfall = {lower: (upper, data) for upper, (lower, *data) in waterfall_links.items()}

    def node_xy(p):
        return np.array([(p[1] * grid + offset + 0.5) * T, (p[0] * grid + offset + 0.5) * T])

    # 5. Coast outlets: find clean coast nodes (sdf <= 135) with a direct, short neck into the inland
    coast_cands = []
    for y in range(5, gn - 5):
        for x in range(5, gn - 5):
            sy = y * grid + offset
            sx = x * grid + offset
            if 128 <= sdf[sy, sx] <= 135 and levels[sy, sx] == 0 and not wall_dilated[sy, sx] and np.isin(ids[sy, sx], green_ids) and not prot_arr[sy, sx]:
                coast_cands.append((y, x))

    rng.shuffle(coast_cands)

    neck_outlets = []
    for oy, ox in coast_cands:
        queue = [(0, oy, ox, [(oy, ox)])]
        visited = {(oy, ox)}
        found = None
        while queue:
            cost, cy, cx, path = heapq.heappop(queue)
            sy = cy * grid + offset
            sx = cx * grid + offset
            if sdf[sy, sx] >= 165 and inland_floor[sy, sx]:
                found = path
                break
            if cost > 8:
                continue
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
                ny, nx = cy + dy, cx + dx
                if (ny, nx) not in visited and 0 <= ny < gn and 0 <= nx < gn:
                    nsy = ny * grid + offset
                    nsx = nx * grid + offset
                    if levels[nsy, nsx] == 0 and not wall_dilated[nsy, nsx] and not prot_arr[nsy, nsx]:
                        visited.add((ny, nx))
                        s_diff = float(sdf[sy, sx]) - float(sdf[nsy, nsx])
                        step_cost = math.hypot(dy, dx) + max(0.0, s_diff * 0.15)
                        heapq.heappush(queue, (cost + step_cost, ny, nx, path + [(ny, nx)]))
        if found and len(found) <= 8:
            neck_outlets.append(((oy, ox), found))

    selected_outlets = []
    for (oy, ox), neck in neck_outlets:
        pos = node_xy((oy, ox))
        if all(np.linalg.norm(pos - node_xy(s[0])) > 4500 for s in selected_outlets):
            selected_outlets.append(((oy, ox), neck))
            if len(selected_outlets) >= cfg['basins']:
                break

    # Build active graph: inland nodes + selected outlet necks
    active_nodes = set()
    for y in range(gn):
        for x in range(gn):
            sy = y * grid + offset
            sx = x * grid + offset
            if inland_floor[sy, sx]:
                active_nodes.add((y, x))

    neck_dict = {}
    for basin_id, ((oy, ox), neck) in enumerate(selected_outlets):
        for i in range(len(neck)):
            active_nodes.add(neck[i])
            if i < len(neck) - 1:
                neck_dict[neck[i]] = neck[i+1]

    node_levels = {p: int(levels[p[0]*grid+offset, p[1]*grid+offset]) for p in active_nodes}
    node_sdf = {p: int(sdf[p[0]*grid+offset, p[1]*grid+offset]) for p in active_nodes}

    def upstream_neighbors(p):
        if p in neck_dict:
            yield neck_dict[p], 1.0, False, None
            return
        y, x = p
        lvl = node_levels[p]
        py = y * grid + offset
        px = x * grid + offset
        for dy, dx in ((-1, 0), (0, -1), (0, 1), (1, 0), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            q = (y + dy, x + dx)
            if q in active_nodes:
                if node_levels[q] == lvl:
                    qy = q[0] * grid + offset
                    qx = q[1] * grid + offset
                    steps = max(abs(qy - py), abs(qx - px)) * 2
                    ys = np.linspace(py, qy, steps + 1).round().astype(int)
                    xs = np.linspace(px, qx, steps + 1).round().astype(int)
                    if np.all(kinds[ys, xs] == 0):
                        yield q, math.hypot(dx, dy), False, None
        if p in reverse_waterfall:
            upper, data = reverse_waterfall[p]
            if upper in active_nodes:
                yield upper, 1.8, True, data

    # 6. Multi-source Dijkstra from coast outlets to partition island into disjoint catchments
    dist = {}
    parent = {}
    basin_map = {}
    wf_info = {}
    heap = []

    for basin_id, ((oy, ox), neck) in enumerate(selected_outlets):
        dist[(oy, ox)] = 0.0
        basin_map[(oy, ox)] = basin_id
        heapq.heappush(heap, (0.0, (oy, ox)))

    while heap:
        cost, p = heapq.heappop(heap)
        if cost != dist[p]:
            continue
        p_basin = basin_map[p]
        for q, step, is_wf, data in upstream_neighbors(p):
            if q in basin_map and basin_map[q] != p_basin:
                continue
            rough = 1.0 + 0.12 * math.sin(q[1] * 0.17 + math.cos(q[0] * 0.23))
            step_cost = step * rough
            if is_wf:
                step_cost *= 0.4  # encourage waterfalls into higher plateau catchments
            nc = cost + step_cost
            if nc < dist.get(q, math.inf):
                dist[q] = nc
                parent[q] = p
                basin_map[q] = p_basin
                if is_wf:
                    wf_info[q] = data
                heapq.heappush(heap, (nc, q))

    # 7. Select sources and build edges per basin
    edges = []
    basins = []
    fords = []
    waterfalls = []
    cliff_springs = []

    for basin_id, ((oy, ox), neck) in enumerate(selected_outlets):
        root = (oy, ox)
        basin_nodes = [p for p, b in basin_map.items() if b == basin_id and p in dist]
        def score_source(p):
            sy = p[0] * grid + offset
            sx = p[1] * grid + offset
            is_cliff = any(0 <= sy+dy < n and 0 <= sx+dx < n and kinds[sy+dy, sx+dx] == 1 for dy in (-3,-2,-1,1,2,3) for dx in (-3,-2,-1,0,1,2,3))
            return (node_levels[p] * 1000.0) + (500.0 if is_cliff else 0.0) + dist[p]

        candidates = sorted(basin_nodes, key=lambda p: -score_source(p))

        sources = []
        used = set()
        flux = {}

        for p in candidates:
            if dist[p] * pitch < cfg['minimum_run']:
                break
            pos = node_xy(p)
            if any(np.linalg.norm(pos - node_xy(s)) < cfg['source_separation'] for s in sources):
                continue
            path = []
            q = p
            while q != root and q not in used:
                path.append(q)
                q = parent[q]
            if len(path) * pitch < cfg['minimum_run'] * 0.4:
                continue
            sources.append(p)
            discharge = float(rng.uniform(0.65, 1.25))
            q = p
            while True:
                flux[q] = flux.get(q, 0.0) + discharge
                used.add(q)
                if q == root:
                    break
                q = parent[q]
            if len(sources) >= cfg['sources_per_basin']:
                break

        if not sources:
            continue

        # Check cliff spring sources
        for src in sources:
            sy = src[0] * grid + offset
            sx = src[1] * grid + offset
            wall_found = False
            wall_style = 1
            for dy in (-3, -2, -1, 1, 2, 3):
                for dx in (-3, -2, -1, 0, 1, 2, 3):
                    if 0 <= sy + dy < n and 0 <= sx + dx < n and kinds[sy + dy, sx + dx] == 1:
                        wall_found = True
                        wall_style = int(styles[sy + dy, sx + dx])
                        break
                if wall_found:
                    break
            if wall_found:
                cliff_springs.append([float((sx + 0.5) * T), float((sy + 0.5) * T), wall_style])

        radius = lambda p: min(cfg['max_radius'], cfg['base_radius'] + cfg['flow_radius'] * math.sqrt(flux[p]))

        for p in sorted(used):
            if p == root:
                continue
            q = parent[p]
            a, b = node_xy(p), node_xy(q)

            # If this edge is a waterfall transition
            if p in wf_info:
                ly, lx, wstyle = wf_info[p]
                fall_x = float((lx + 0.5) * T)
                fall_y = float(ly * T)
                waterfalls.append([fall_x, fall_y, 32.0, 28.0, int(node_levels[p]), int(node_levels[q]), wstyle])

                # Upper segment: from a to waterfall lip
                lip_pt = np.array([fall_x, fall_y])
                base_pt = np.array([fall_x, fall_y + 32.0])
                head_a = dist[p]
                head_b = dist[q]
                h_mid1 = (2.0 * head_a + head_b) / 3.0
                h_mid2 = (head_a + 2.0 * head_b) / 3.0
                ra_p = radius(p)
                rb_q = max(ra_p, radius(q))

                edges.append({
                    'a': a.tolist(), 'b': lip_pt.tolist(),
                    'ra': ra_p, 'rb': ra_p,
                    'flow': flux[p], 'basin': basin_id,
                    'level': int(node_levels[p]),
                    'head_a': head_a, 'head_b': h_mid1
                })
                # Waterfall vertical step: connects upper lip to lower base
                edges.append({
                    'a': lip_pt.tolist(), 'b': base_pt.tolist(),
                    'ra': ra_p, 'rb': ra_p,
                    'flow': flux[p], 'basin': basin_id,
                    'level': int(node_levels[p]),
                    'head_a': h_mid1, 'head_b': h_mid2,
                    'is_waterfall': True
                })
                # Lower segment: from waterfall base to b
                edges.append({
                    'a': base_pt.tolist(), 'b': b.tolist(),
                    'ra': ra_p, 'rb': rb_q,
                    'flow': flux[p], 'basin': basin_id,
                    'level': int(node_levels[q]),
                    'head_a': h_mid2, 'head_b': head_b
                })
            else:
                ra_p = radius(p)
                rb_q = max(ra_p, radius(q))
                edges.append({
                    'a': a.tolist(), 'b': b.tolist(),
                    'ra': ra_p, 'rb': rb_q,
                    'flow': flux[p], 'basin': basin_id,
                    'level': int(node_levels[p]),
                    'head_a': dist[p], 'head_b': dist[q]
                })
                # Cross-channel fords
                if int(dist[p] * pitch / cfg['ford_spacing']) != int(dist[q] * pitch / cfg['ford_spacing']):
                    fords.append([*((a + b) * 0.5).tolist(), cfg['ford_half_length']])

        basins.append({
            'outlet': node_xy(root).tolist(),
            'radius': radius(root) * 1.4,
            'sources': [node_xy(p).tolist() for p in sources],
            'level': int(node_levels[root]),
            'discharge': flux[root]
        })

    # Deduplicate waterfalls and cliff springs
    unique_wfs = {}
    for wf in waterfalls:
        unique_wfs[(round(wf[0]), round(wf[1]))] = wf
    waterfalls = list(unique_wfs.values())

    unique_springs = {}
    for cs in cliff_springs:
        unique_springs[(round(cs[0]), round(cs[1]))] = cs
    cliff_springs = list(unique_springs.values())

    # 8. Curve interpolation with shared tangents
    outgoing = {tuple(e['a']): e for e in edges}
    incoming = {}
    for e in edges:
        incoming.setdefault(tuple(e['b']), []).append(e)

    tangents = {}
    for node in set(outgoing) | set(incoming):
        es = incoming.get(node, [])
        after = outgoing.get(node)
        directions = []
        lengths = []
        for e in es:
            v = np.array(e['b']) - np.array(e['a'])
            l = max(np.linalg.norm(v), 1e-6)
            lengths.append(l)
            directions.append(v / l * e['flow'])
        if after:
            v = np.array(after['b']) - np.array(after['a'])
            l = max(np.linalg.norm(v), 1e-6)
            lengths.append(l)
            directions.append(v / l * after['flow'])
        v_sum = sum(directions)
        tangents[node] = v_sum / max(np.linalg.norm(v_sum), 1e-6) * (min(lengths) if lengths else 16.0) * 0.60

    segments = []
    for e in edges:
        a, b = np.array(e['a']), np.array(e['b'])
        chord = b - a
        chord_len = np.linalg.norm(chord)
        if chord_len < 1e-4:
            continue

        if e.get('is_waterfall'):
            va = chord
            vb = chord
        else:
            va = tangents.get(tuple(a), chord * 0.5).copy()
            vb = tangents.get(tuple(b), chord * 0.5).copy()
            # If node b has no outgoing edge (terminal outlet into void/coast), continue along chord
            if tuple(b) not in outgoing:
                vb = (chord / chord_len) * min(chord_len, np.linalg.norm(vb)) * 0.60
            # If node a has no incoming edge (spring source), start along chord
            if tuple(a) not in incoming:
                va = (chord / chord_len) * min(chord_len, np.linalg.norm(va)) * 0.60
            # Guard against reverse tangents that could cause loops
            if np.dot(va, chord) <= 0:
                va = chord * 0.5
            if np.dot(vb, chord) <= 0:
                vb = chord * 0.5

        last = a
        for j in range(1, 9):
            t = j / 8.0
            point = (2*t**3 - 3*t**2 + 1)*a + (t**3 - 2*t**2 + t)*va + (-2*t**3 + 3*t**2)*b + (t**3 - t**2)*vb
            seg = dict(e)
            seg.update(
                a=last.tolist(), b=point.tolist(),
                ra=e['ra'] + (e['rb'] - e['ra']) * (j - 1) / 8.0,
                rb=e['ra'] + (e['rb'] - e['ra']) * t
            )
            segments.append(seg)
            last = point

    # 9. Chunk rasterization
    chunks = {}
    reach = cfg['max_radius'] * 1.5 + cfg['bank_width'] + 6
    for seg in segments:
        a, b = np.array(seg['a']), np.array(seg['b'])
        lo = np.floor((np.minimum(a, b) - reach) / C).astype(int)
        hi = np.floor((np.maximum(a, b) + reach) / C).astype(int)
        for cy in range(lo[1], hi[1] + 1):
            for cx in range(lo[0], hi[0] + 1):
                chunks.setdefault((cx, cy), []).append(seg)

    output = ROOT / 'assets/water/world'
    output.mkdir(exist_ok=True)
    registry = {}

    for (cx, cy), segs in sorted(chunks.items()):
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
            depth = np.where(hit, np.clip(1.0 - dist_val / rad, 0.0, 1.0)**0.8, depth)
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
            depth = np.where(hit, np.clip(1.0 - dist_val / r, 0.0, 1.0)**0.8, depth)

        wet = best <= 0.0
        if not np.any(best < cfg['bank_width']):
            continue

        for x, y, half in fords:
            if x + 75 < cx * C or x - 75 >= (cx + 1) * C or y + 75 < cy * C or y - 75 >= (cy + 1) * C:
                continue
            dist_val = np.hypot(xx - x, yy - y)
            along = np.abs((xx - x) * fx + (yy - y) * fy)
            blend = np.maximum(np.clip((along - half * 0.4) / (half * 0.6), 0.0, 1.0), np.clip((dist_val - 50.0) / 25.0, 0.0, 1.0))
            blend = blend * blend * (3.0 - 2.0 * blend)
            depth = np.minimum(depth, cfg['ford_depth'] * (1.0 - blend) + depth * blend)

        field = np.stack([wet * 255, depth * 255, (fx * 0.5 + 0.5) * 255, (fy * 0.5 + 0.5) * 255], axis=-1).astype('uint8')
        # R: distance from the water on land, G: depth under the surface (0..8 px), for the shore shading.
        bank = np.stack([np.clip(best / cfg['bank_width'] * 255.0, 0.0, 255.0),
                         np.clip(-best / 8.0 * 255.0, 0.0, 255.0), np.zeros_like(best)], axis=-1).astype('uint8')
        Image.fromarray(field).save(output / f'field_{cx}_{cy}.png')
        Image.fromarray(bank).save(output / f'bank_{cx}_{cy}.png')

        clear = np.clip(best, -127, 127).reshape(128, 4, 128, 4).min(axis=(1, 3))
        dep = np.where(wet, depth, 0).reshape(128, 4, 128, 4).max(axis=(1, 3))
        nav = np.stack([np.clip(clear + 128, 0, 255), dep * 255, np.zeros_like(dep), np.full_like(dep, 255)], axis=-1).astype('uint8')
        Image.fromarray(nav).save(output / f'query_{cx}_{cy}.png')

        # Collect waterfalls and cliff springs in this chunk
        c_waterfalls = [wf for wf in waterfalls if cx * C <= wf[0] < (cx + 1) * C and cy * C <= wf[1] < (cy + 1) * C]
        c_springs = [cs for cs in cliff_springs if cx * C <= cs[0] < (cx + 1) * C and cy * C <= cs[1] < (cy + 1) * C]

        registry[f'{cx},{cy}'] = {
            'blocks': collision_rects(nav, cfg['deep_threshold']),
            'field': f'res://assets/water/world/field_{cx}_{cy}.png',
            'bank': f'res://assets/water/world/bank_{cx}_{cy}.png',
            'query': f'res://assets/water/world/query_{cx}_{cy}.png',
            'waterfalls': c_waterfalls,
            'cliff_springs': c_springs
        }

    data = {
        'generator_hash': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'version': 2,
        'seed': cfg['seed'],
        'input_hash': hashlib.sha256((ROOT / 'assets/world/relief.png').read_bytes() + (ROOT / 'data/world_map.json').read_bytes() + (ROOT / 'data/rivers.json').read_bytes()).hexdigest(),
        'edges': edges,
        'segments': segments,
        'basins': basins,
        'fords': fords,
        'waterfalls': waterfalls,
        'cliff_springs': cliff_springs,
        'chunks': registry
    }

    (ROOT / 'data/rivers_baked.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print(f'Rivers: {len(basins)} basins, {sum(len(b["sources"]) for b in basins)} sources, {len(edges)} edges, {len(waterfalls)} waterfalls, {len(cliff_springs)} cliff springs, {len(fords)} fords, {len(registry)} chunks')
    return data

if __name__ == '__main__':
    generate()
