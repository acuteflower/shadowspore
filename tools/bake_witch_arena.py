"""The Schieferkessel am Rabenbaum: the arena of boss 2 (Morwenna, docs/enemies/boss_mora.md).

    py -3 tools/bake_witch_arena.py [preview.png]

Reads data/witch_arena.json (hand written: the tree's tile and the limits of the hollow), assets/world/relief.png and relief_block.png.
Writes assets/world/ground/witch_arena_zone.png (1 px per world px, alpha = the fight's floor: what warnings and damage are cut to, the
contract of `FeatherField.setup`) and data/witch_arena_baked.json:
    zone {x, y, w, h}            world px of the mask's top left corner and its size
    gates [{rect [x, y, w, h], thorns [[x, y, variant, flip, glow]]}]   the ways out: solid while the fight runs, thorn hedges grow in them
                                 (the gate tiles grown by one tile, diagonals too, so no corner stays open; the hedges are scattered per tile
                                 with a ragged depth, only some carry glowing buds)
    rows [[y, x0, x1]]           tile rows of the hollow (kept free of generated plants)
    floor [[x, y]]               a few hundred free floor points (world px), far from walls: where clones, roots and shards may be put
Run it again after the relief changes, then `Godot --headless --import`."""
import json, random, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
T = 16


def main():
    spec = json.loads((ROOT / 'data/witch_arena.json').read_text(encoding='utf-8'))
    relief = np.array(Image.open(ROOT / 'assets/world/relief.png').convert('RGBA'))
    block = np.array(Image.open(ROOT / 'assets/world/relief_block.png').convert('L'))
    tx, ty = spec['tile']
    x0, y0, x1, y1 = spec['limits']                      # tiles, inclusive
    cuts = spec.get('cuts', [])                          # [x0, y0, x1, y1] tile boxes that are outside
    level = relief[..., 0]; kind = relief[..., 1] & 15; land = relief[..., 3] >= 200
    floor = land & (kind == 0) & (level == 0)

    def allowed(x, y):
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return False
        return not any(c[0] <= x <= c[2] and c[1] <= y <= c[3] for c in cuts)

    inside = set(); todo = [(tx, ty)]
    while todo:
        x, y = todo.pop()
        if (x, y) in inside or not floor[y, x] or not allowed(x, y):
            continue
        inside.add((x, y))
        todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    # the ways out: walkable tiles (floor of any level, ramps, stairs, steps) that touch the hollow from outside
    walk = land & (kind != 1)
    gate_tiles = set()
    for x, y in inside:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q in inside or not walk[q[1], q[0]]:
                continue
            if kind[q[1], q[0]] == 0 and level[q[1], q[0]] != 0:
                continue                                 # higher floor beside the hollow is a cliff edge, the wall is there already
            gate_tiles.add(q)
    # one tile more around every gate (diagonals too): a gate that meets the slate at a slant must not leave a corner to slip through
    grown = set(gate_tiles)
    for x, y in gate_tiles:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q in inside or q in grown or not walk[q[1], q[0]]:
                    continue
                if kind[q[1], q[0]] == 0 and level[q[1], q[0]] != 0:
                    continue
                grown.add(q)
    # and the hollow's own rim tiles right behind a gate (diagonal neighbours of the gate), so the hedge closes against the slate on the inside too
    gate_tiles = grown
    xs = [p[0] for p in inside]; ys = [p[1] for p in inside]
    bx0, by0, bx1, by1 = min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1
    w, h = (bx1 - bx0 + 1) * T, (by1 - by0 + 1) * T
    mask = np.zeros((h, w), dtype=bool)
    for x, y in inside:
        mask[(y - by0) * T:(y - by0 + 1) * T, (x - bx0) * T:(x - bx0 + 1) * T] = True
    solid = np.kron(block[by0 * 4:(by1 + 1) * 4, bx0 * 4:(bx1 + 1) * 4] > 127, np.ones((4, 4), dtype=bool))
    mask &= ~solid
    rgba = np.zeros((h, w, 4), dtype=np.uint8); rgba[mask] = (255, 255, 255, 255)
    Image.fromarray(rgba).save(ROOT / 'assets/world/ground/witch_arena_zone.png')
    # gates: runs of gate tiles joined into rectangles (rows first, then equal rows stacked)
    rows = {}
    for x, y in sorted(gate_tiles, key=lambda p: (p[1], p[0])):
        runs = rows.setdefault(y, [])
        if runs and runs[-1][1] == x - 1:
            runs[-1][1] = x
        else:
            runs.append([x, x])
    rects = []
    for y in sorted(rows):
        for a, b in rows[y]:
            for r in rects:
                if r[0] == a and r[2] == b and r[3] == y - 1:
                    r[3] = y; break
            else:
                rects.append([a, y, b, y])
    rng = random.Random(8792)
    gates = []
    for a, ya, b, yb in rects:
        rect = [a * T, ya * T, (b - a + 1) * T, (yb - ya + 1) * T]
        thorns = []
        for ty_ in range(ya, yb + 1):
            for tx_ in range(a, b + 1):
                # a hedge clump per tile: 2-4 bushes at ragged spots, sometimes one spilling a little further, never in a line
                for k in range(rng.choice([2, 3, 3, 4])):
                    px = tx_ * T + rng.uniform(1, T - 1)
                    py = ty_ * T + rng.uniform(2, T + 2)
                    thorns.append([round(px), round(py), rng.choice([0, 0, 1, 1, 2]), rng.random() < 0.5, rng.random() < 0.22])
                if rng.random() < 0.35:
                    thorns.append([round(tx_ * T + rng.uniform(-6, T + 6)), round(ty_ * T + rng.uniform(-5, T + 8)), rng.choice([1, 2]), rng.random() < 0.5, False])
        thorns.sort(key=lambda t: t[1])
        gates.append({'rect': rect, 'thorns': thorns})
    # free floor points: 20 px grid, at least 18 px from anything that is not floor and 46 px from the tree
    dist = mask.copy()
    for _ in range(18):
        dist[1:-1, 1:-1] &= dist[:-2, 1:-1] & dist[2:, 1:-1] & dist[1:-1, :-2] & dist[1:-1, 2:]
    tree = np.array([tx * T + 8, ty * T + 8])
    points = []
    for py in range(10, h, 20):
        for px in range(10, w, 20):
            wx, wy = bx0 * T + px, by0 * T + py
            if dist[py, px] and np.hypot(wx - tree[0], (wy - tree[1]) * 1.4) > 46:
                points.append([wx, wy])
    runs = []
    for y in range(by0, by1 + 1):
        row = sorted(x for x, yy in inside if yy == y)
        if row:
            runs.append([y, row[0], row[-1]])
    baked = {'tile': [tx, ty], 'rows': runs, 'zone': {'x': bx0 * T, 'y': by0 * T, 'w': w, 'h': h, 'mask': 'res://assets/world/ground/witch_arena_zone.png'},
             'gates': gates, 'floor': points}
    (ROOT / 'data/witch_arena_baked.json').write_text(json.dumps(baked, separators=(',', ':')) + '\n', encoding='utf-8')
    print('hollow: %d tiles, %d x %d px, %d gates (%d thorn hedges), %d floor points' % (len(inside), w, h, len(gates), sum(len(g['thorns']) for g in gates), len(points)))
    if len(sys.argv) > 1:
        view = np.zeros((h, w, 3), dtype=np.uint8); view[...] = (16, 14, 26); view[mask] = (44, 70, 62)
        for g in gates:
            r = g['rect']; view[r[1] - by0 * T:r[1] - by0 * T + r[3], r[0] - bx0 * T:r[0] - bx0 * T + r[2]] = (150, 60, 190)
            for t in g['thorns']:
                view[t[1] - by0 * T - 2:t[1] - by0 * T + 2, t[0] - bx0 * T - 2:t[0] - bx0 * T + 2] = (170, 255, 110)
        for p in points:
            view[p[1] - by0 * T, p[0] - bx0 * T] = (255, 255, 255)
        cy, cx = tree[1] - by0 * T, tree[0] - bx0 * T
        view[cy - 4:cy + 4, cx - 4:cx + 4] = (255, 220, 120)
        Image.fromarray(view).save(sys.argv[1])


if __name__ == '__main__':
    main()
