#!/usr/bin/env python3
"""Checks stage 2 of the Hexenwald (hills, slate walls, connectors, the way in). Usage: python3 tools/test_hexenwald_terrain.py"""
import json, os, subprocess, sys
from collections import deque
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = 0


def check(ok, msg):
    global failed
    if not ok:
        failed += 1
        print("FAIL:", msg)


def img(name):
    return np.asarray(Image.open(os.path.join(ROOT, "assets/world", name)))


relief, block, field = img("relief.png"), img("relief_block.png"), img("relief_field.png")
hexm = relief[..., 3] == 205
lvl, kind, style = relief[..., 0], relief[..., 1] & 15, relief[..., 1] >> 4
check(hexm.sum() > 25000, "the Hexenwald's tiles exist")

# the old world is exactly what it was at the last commit (pixels of every tile that is not the Hexenwald)
try:
    head = subprocess.run(["git", "show", "HEAD:assets/world/relief.png"], cwd=ROOT, capture_output=True, check=True).stdout
    import io
    old = np.asarray(Image.open(io.BytesIO(head)).convert("RGBA"))
    check((old[~hexm] == relief[~hexm]).all(), "relief.png outside the Hexenwald equals HEAD")
except (subprocess.CalledProcessError, FileNotFoundError):
    print("skip: no git HEAD to compare with")

# shape of the terrain
share = [float((lvl[hexm] == k).mean()) for k in range(4)]
check(share[0] > 0.6 and 0.08 < 1.0 - share[0] < 0.4, "mostly flat with hills: level shares %s" % ["%.2f" % v for v in share])
check((kind[hexm] == 1).sum() > 300, "there are cliff walls")
check((style[hexm & (kind <= 1)] == 5).all(), "floor and walls use the slate style 5")
check(((kind[hexm] >= 2).sum()) > 30, "ramps/steps exist")
check(lvl[~hexm][relief[..., 3][~hexm] > 0].max() <= 3, "old levels intact")

# every walkable Hexenwald tile can be reached from the flat by level or by connector tiles
walk = hexm & (kind != 1)
ys, xs = np.nonzero(walk & (lvl == 0))
seen = np.zeros(hexm.shape, dtype=bool)
q = deque([(int(ys[0]), int(xs[0]))])
seen[q[0]] = True
while q:
    y, x = q.popleft()
    for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
        if walk[ny, nx] and not seen[ny, nx] and (lvl[ny, nx] == lvl[y, x] or kind[ny, nx] >= 2 or kind[y, x] >= 2):
            seen[ny, nx] = True
            q.append((ny, nx))
check(not (walk & ~seen).any(), "all %d walkable tiles of the Hexenwald are reachable (%d are not)" % (walk.sum(), (walk & ~seen).sum()))

# connectors in data/relief.json agree with relief.png
conns = json.load(open(os.path.join(ROOT, "data/relief.json")))["connectors"]
mine = [c for c in conns if hexm[c[1], c[0]]]
check(len(mine) > 10 and all(kind[c[1], c[0]] == c[2] for c in mine), "%d connectors of the Hexenwald agree with relief.png" % len(mine))
check(len(conns) >= 462, "old connectors are kept")

# collision: walls block, the flat does not
hb = np.repeat(np.repeat(hexm & (lvl == 0) & (kind == 0), 4, 0), 4, 1)
check(block[np.repeat(np.repeat(hexm, 4, 0), 4, 1)].any(), "walls have collision")
flat_core = hexm & (lvl == 0) & (kind == 0)
for _ in range(4):  # away from the hills
    r = flat_core.copy(); r[1:] &= flat_core[:-1]; r[:-1] &= flat_core[1:]; r[:, 1:] &= flat_core[:, :-1]; r[:, :-1] &= flat_core[:, 1:]; flat_core = r
check(not block[np.repeat(np.repeat(flat_core, 4, 0), 4, 1)].any(), "no collision on the open flat")

# the way in
g = open(os.path.join(ROOT, "data/ground.json")).read()
spec = next((p for p in json.loads(g)["paths"] if p["id"] == "hexenwald_path"), None)
check(spec is not None and len(spec["points"]) > 8, "hexenwald_path exists")
if spec:
    w = json.load(open(os.path.join(ROOT, "data/world_map.json")))
    cx, cy = w["start"][0] * 16 + 8, w["start"][1] * 16 + 8
    pts = np.array([[cx + p[0], cy + p[1]] for p in spec["points"]], dtype=float) / 16.0
    bad = 0
    for a, b in zip(pts[:-1], pts[1:]):
        for t in np.linspace(0, 1, 40):
            x, y = (a + (b - a) * t).astype(int)
            if relief[y, x, 3] == 0 or lvl[y, x] != 0 or kind[y, x] != 0:
                bad += 1
    check(bad == 0, "the way stays on flat level-0 floor (%d bad samples)" % bad)
    check(hexm[int(pts[-1][1]), int(pts[-1][0])] and not hexm[int(pts[0][1]), int(pts[0][0])], "it starts on the old coast meadow and ends inside the Hexenwald")
    baked = json.load(open(os.path.join(ROOT, "data/ground_baked.json")))["decals"]
    check(any(d["id"] == "hexenwald_path" for d in baked), "path is baked into ground_baked.json")
    check(os.path.exists(os.path.join(ROOT, "assets/world/ground/hexenwald_path.png")), "path picture exists")

print("HEXENWALD TERRAIN: %s" % ("ok" if not failed else "%d failed" % failed))
sys.exit(1 if failed else 0)
