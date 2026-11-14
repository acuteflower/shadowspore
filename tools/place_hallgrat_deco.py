#!/usr/bin/env python3
"""Fills Hallgrat with life (docs/stadt_westen_konzept.md 14.7): street furniture and greenery round the placed buildings. Run it after
tools/place_hallgrat_buildings.py and tools/bake_hallgrat_ground.py (it reads the baked paving and door paths).

  * At the houses: one or two things at the front corners of every house, what fits the house (a shop's crates and barrels, a dwelling's
    planter and woodpile, an abandoned house's rubble, the stables' hay and cart), never on its door path.
  * Along the ways: low dry-stone walls in short pieces with gaps (turned with the way: east-west, north-south or diagonal), lantern posts at
    a steady distance, bollards, planters, benches, urns; in the Fuß and the lost quarter ruined walls, rubble and broken columns.
  * On the free grass: trees (blossom, birch, apple, fir by district), bushes, grass and flowers as real world plants (`greenery`: they come
    in through `PropGenerator.extra_props`, so they sway, glow, can be picked and felled like everywhere else).

Nothing stands on the paving, on a door path, in front of a door, behind a house's picture (it would be hidden) or on another thing; every
thing stands on plain floor of one level. Writes `deco` [{type, px [x, y] feet, flip}] and `greenery` [{kind, variant, tile}] into
data/hallgrat.json.
    py -3 tools/place_hallgrat_deco.py [preview.png]"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import load_png  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = 4  # px of the occupancy grid
SEED = 4417
WHY = {}

# what stands at a house, by the start of its type
AT_HOUSE = {
    "laden": ["kisten", "fass", "saecke", "kruege", "fass_lieg"],
    "verlassen": ["steine", "fass_lieg", "steine"],
    "stall": ["heu", "karren", "holz", "trog", "heu"],
    "halle": ["urne", "kuebel", "urne"],
    "torhaus": ["fass", "kisten"],
    "haus": ["kuebel", "holz", "fass", "urne", "kruege", "kisten", "saecke"],
    "giebel": ["kuebel", "urne", "holz", "fass"],
}
# along the ways, per district: (walls, things)
WAYSIDE = {
    "fuss": (("mauer_b", "ruine", "ruine"), ("steine", "saeule", "prellstein", "steine", "fass_lieg")),
    "verloren": (("ruine", "ruine", "mauer_b"), ("steine", "saeule", "steine")),
    "staffeln": (("mauer_a", "mauer_b", "mauer_a"), ("kuebel", "prellstein", "bank", "urne", "beet", "trog")),
    "stille": (("mauer_a", "mauer_a", "mauer_b"), ("kuebel", "bank", "urne", "beet", "prellstein")),
    "rand": (("mauer_a", "mauer_b", "ruine"), ("prellstein", "kuebel", "steine", "bank", "beet")),
}
TREES = {
    "fuss": (("tree", 0, 3), ("birch", 0, 3), ("blossom", 0, 2)),
    "verloren": (("tree", 1, 4), ("birch", 1, 4)),
    "staffeln": (("blossom", 0, 3), ("orchard_apple", 0, 2), ("birch", 0, 3)),
    "stille": (("blossom", 1, 4), ("birch", 1, 3), ("orchard_pear", 0, 2)),
    "rand": (("tree", 0, 3), ("birch", 0, 4), ("orchard_apple", 0, 2), ("blossom", 0, 3)),
}
SMALL = ("bush", 0, 7), ("grass", 0, 6)
FLOWERS = ("sunbloom", "moonbell", "mist_lily", "spark_poppy", "wound_leaf", "puffseed", "moon_iris")


def point_in(poly, x, y):
    c = False
    for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            c = not c
    return c


def contours(mask):
    """Marching squares over a boolean grid: the border lines of `mask` as lists of (row, col) points (cell coordinates, the points on
    the middles of the cells' edges), joined into chains and loops."""
    m = mask.astype(np.uint8)
    code = (m[:-1, :-1] << 3) | (m[:-1, 1:] << 2) | (m[1:, 1:] << 1) | m[1:, :-1]
    T = {1: (("L", "B"),), 2: (("B", "R"),), 3: (("L", "R"),), 4: (("T", "R"),), 5: (("L", "T"), ("B", "R")), 6: (("T", "B"),),
         7: (("L", "T"),), 8: (("L", "T"),), 9: (("T", "B"),), 10: (("T", "R"), ("L", "B")), 11: (("T", "R"),), 12: (("L", "R"),),
         13: (("B", "R"),), 14: (("L", "B"),)}
    nb = {}
    for r, c in zip(*np.nonzero((code > 0) & (code < 15))):
        key = {"T": ("h", r, c), "B": ("h", r + 1, c), "L": ("v", r, c), "R": ("v", r, c + 1)}
        for a, b in T[int(code[r, c])]:
            nb.setdefault(key[a], []).append(key[b])
            nb.setdefault(key[b], []).append(key[a])
    pos = lambda k: (k[1], k[2] + 0.5) if k[0] == "h" else (k[1] + 0.5, k[2])  # noqa: E731
    seen, out = set(), []
    starts = [k for k, v in nb.items() if len(v) == 1] + list(nb.keys())
    for s in starts:
        if s in seen:
            continue
        chain, cur, prev = [s], s, None
        seen.add(s)
        while True:
            nxt = [q for q in nb[cur] if q != prev and q not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            chain.append(cur)
        out.append([pos(k) for k in chain])
    return out


def chaikin(pts):
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        out += [(0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by), (0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by)]
    out.append(pts[-1])
    return out


def resample(pts, step):
    if len(pts) < 2:
        return pts
    out, carry = [pts[0]], 0.0
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        L = math.hypot(bx - ax, by - ay)
        if L < 1e-9:
            continue
        t = step - carry
        while t <= L:
            out.append((ax + (bx - ax) * t / L, ay + (by - ay) * t / L))
            t += step
        carry = L - (t - step)
    return out


def main():
    path = os.path.join(ROOT, "data/hallgrat.json")
    town = json.load(open(path, encoding="utf-8"))
    art = json.load(open(os.path.join(ROOT, "data/hallgrat_art.json"), encoding="utf-8"))["types"]
    plants = json.load(open(os.path.join(ROOT, "data/plants.json"), encoding="utf-8"))
    baked = json.load(open(os.path.join(ROOT, "data/ground_baked.json"), encoding="utf-8"))
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    level, kind, land = relief[..., 0].astype(int), relief[..., 1] & 15, relief[..., 3] > 0
    floor = land & (kind == 0)
    bx0, by0, bx1, by1 = [v * 16 for v in town["bounds"]]
    W, H = (bx1 - bx0) // C, (by1 - by0) // C

    def cell(x, y):
        return int((y - by0) // C), int((x - bx0) // C)

    paved = np.zeros((H, W), bool)      # streets, squares (4 px)
    path_ = np.zeros((H, W), bool)      # the door paths
    for d in baked["decals"]:
        if not d["id"].startswith("hallgrat_") or d["id"] == "hallgrat_clear":
            continue
        mk = np.array(Image.open(os.path.join(ROOT, d["mask"].replace("res://", ""))))[..., 0] > 0
        sub = mk[::C, ::C]
        r0, c0 = cell(d["x"], d["y"])
        r1, c1 = r0 + sub.shape[0], c0 + sub.shape[1]
        a0, b0 = max(0, r0), max(0, c0)
        a1, b1 = min(H, r1), min(W, c1)
        if a1 <= a0 or b1 <= b0:
            continue
        piece = sub[a0 - r0:a1 - r0, b0 - c0:b1 - c0]
        (path_ if d["id"].startswith("hallgrat_zugang") else paved)[a0:a1, b0:b1] |= piece
    taken = np.zeros((H, W), bool)      # footprints and what must stay free
    hidden = np.zeros((H, W), bool)     # behind a house's picture
    house = np.zeros((H, W), bool)      # the houses' own footprints (a wall may run up to them)
    near = paved | path_
    grown = near.copy()                 # the paving and the paths, grown by 4 px: nothing stands right on their edge
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grown |= np.roll(np.roll(near, dy, 0), dx, 1)
    rng = random.Random(SEED)

    def mark(arr, x0, y0, x1, y1):
        r0, c0 = cell(x0, y0)
        r1, c1 = cell(x1, y1)
        arr[max(0, r0):max(0, r1 + 1), max(0, c0):max(0, c1 + 1)] = True

    def poly_mark(arr, poly):
        xs, ys = [q[0] for q in poly], [q[1] for q in poly]
        for y in range(int(min(ys)) // C * C, int(max(ys)) + C, C):
            for x in range(int(min(xs)) // C * C, int(max(xs)) + C, C):
                if point_in(poly, x + C / 2, y + C / 2):
                    r, c_ = cell(x, y)
                    if 0 <= r < H and 0 <= c_ < W:
                        arr[r, c_] = True

    houses = []
    for b in town.get("placed", []):
        info = art[b["type"]]
        fx, fy = b["px"]
        fw, fd = info["foot"]
        sw, sh = info["size"]
        if "poly" in info:
            sx = -1.0 if b.get("flip") else 1.0
            poly = [(fx + q[0] * sx, fy + q[1]) for q in info["poly"]]
            poly_mark(taken, poly)
            poly_mark(house, poly)
            xs = [q[0] for q in poly]
            left, right = min(xs), max(xs)
        else:
            mark(taken, fx - fw / 2, fy - fd, fx + fw / 2, fy)
            mark(house, fx - fw / 2, fy - fd, fx + fw / 2, fy)
            left, right = fx - fw / 2, fx + fw / 2
        feet_x = info["feet"][0] if not b.get("flip") else sw - info["feet"][0]
        mark(hidden, fx - feet_x, fy - info["feet"][1], fx - feet_x + sw, fy - 2)
        if b.get("door"):
            dx, dy = b["door"]
            mark(taken, dx - 14, dy - 10, dx + 14, dy + 22)  # the doorstep
        houses.append((b, info, left, right))
    for wall in town.get("walls", []):
        (ax, ay), (bx_, by_) = wall["line"]
        mark(taken, min(ax, bx_) * 16 - 12, min(ay, by_) * 16 - 40, max(ax, bx_) * 16 + 28, max(ay, by_) * 16 + 20)
    for st in town.get("leitsteine", []):
        tx, ty = st["tile"]
        mark(taken, tx * 16 - 8, ty * 16 - 16, tx * 16 + 24, ty * 16 + 24)
    for m in town.get("milestones", []):
        mark(taken, m["pos"][0] - 16, m["pos"][1] - 16, m["pos"][0] + 16, m["pos"][1] + 16)
    districts = {d["id"]: [(x * 16.0, y * 16.0) for x, y in d["poly"]] for d in town["districts"]}

    def district_of(x, y):
        for k, poly in districts.items():
            if point_in(poly, x, y):
                return k
        return None

    def ground_ok(x0, y0, x1, y1, lv=None):
        """Every tile under the box is plain floor of one level; returns that level or None."""
        lvls = set()
        for ty in range(int(y0) // 16, int(y1) // 16 + 1):
            for tx in range(int(x0) // 16, int(x1) // 16 + 1):
                if not floor[ty, tx]:
                    return None
                lvls.add(int(level[ty, tx]))
        if len(lvls) != 1 or (lv is not None and lv not in lvls):
            return None
        return lvls.pop()

    pathy = path_.copy()                # the door paths grown by 4 px (things at a house may stand on the street, never on its path)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            pathy |= np.roll(np.roll(path_, dy, 0), dx, 1)

    def box_free(x0, y0, x1, y1, allow_hidden=False, street=False):
        r0, c0 = cell(x0, y0)
        r1, c1 = cell(x1, y1)
        if r0 < 0 or c0 < 0 or r1 >= H or c1 >= W:
            return False
        for nm, arr_ in (("taken", taken), ("grown", pathy if street else grown)) + (() if allow_hidden else (("hidden", hidden),)):
            if arr_[r0:r1 + 1, c0:c1 + 1].any():
                WHY[nm] = WHY.get(nm, 0) + 1
                return False
        return True

    deco = []

    def place(t, x, y, flip=False, pad=1, lv=None, allow_hidden=False, street=False):
        info = art.get("deko_" + t)
        if info is None:
            return False
        fw, fd = info["foot"]
        x0, y0, x1, y1 = x - fw / 2, y - fd, x + fw / 2, y
        if "poly" in info:
            sx = -1.0 if flip else 1.0
            pts = [(x + q[0] * sx, y + q[1]) for q in info["poly"]]
            x0, x1 = min(q[0] for q in pts), max(q[0] for q in pts)
            y0, y1 = min(q[1] for q in pts), max(q[1] for q in pts)
        if ground_ok(x0, y0, x1, y1, lv) is None:
            WHY["ground"] = WHY.get("ground", 0) + 1
            return False
        if not box_free(x0, y0, x1, y1, allow_hidden, street):
            WHY["busy"] = WHY.get("busy", 0) + 1
            return False
        sw, sh = info["size"]
        fx_ = info["feet"][0] if not flip else sw - info["feet"][0]
        top = y - info["feet"][1]
        mark(taken, x0 - pad * C, y0 - pad * C, x1 + pad * C, y1 + pad * C)
        mark(hidden, x - fx_, top, x - fx_ + sw, y0)  # nothing small hides behind it either
        deco.append({"type": "deko_" + t, "px": [round(x, 1), round(y, 1)], "flip": bool(flip)})
        return True

    # -1. the town wall: along the outer brink of the town's terraces (the districts on the plateau, level >= 1: over the void in the west,
    # on the cliffs' lip in the south and east), a little in from the edge. It opens where a street leaves the town (a gate between two
    # towers), round towers stand at both ends of every stretch, at its bends and every ~150 px; where it meets a house it is carried on
    # to the house's wall. Style `stadt` in tools/art_hallgrat_walls.py.
    wall_runs = []
    T_W, T_H = (bx1 - bx0) // 16, (by1 - by0) // 16
    inner = [districts[k] for k in ("verloren", "glasbruch") if k in districts]
    plateau = np.zeros((T_H, T_W), bool)
    for ty in range(T_H):
        for tx in range(T_W):
            X, Y = bx0 // 16 + tx, by0 // 16 + ty
            if land[Y, X] and level[Y, X] >= 1 and not any(point_in(q, X * 16 + 8, Y * 16 + 8) for q in inner):
                plateau[ty, tx] = True
    core = np.repeat(np.repeat(plateau, 16 // C, 0), 16 // C, 1)[:H, :W]
    for _ in range(3):  # the wall stands 12 px in from the brink
        core = core & np.roll(core, 1, 0) & np.roll(core, -1, 0) & np.roll(core, 1, 1) & np.roll(core, -1, 1)
    ramp_cells = np.zeros((H, W), bool)
    n_towers = 0
    tower_xy = []  # every tower so far: two stretches meeting at a gate share one tower each side, never two on one spot
    for line in contours(core):
        rows_, cols_ = [q[0] for q in line], [q[1] for q in line]
        if len(line) < 30 or math.hypot(max(rows_) - min(rows_), max(cols_) - min(cols_)) * C < 220:
            continue  # a little island of high ground: no town wall round it
        pts = resample(chaikin(chaikin(chaikin([(bx0 + c_ * C + C / 2, by0 + r * C + C / 2) for r, c_ in line]))), 3.0)
        info_pts = []
        for x, y in pts:
            r, c_ = cell(x, y)
            if not (2 <= r < H - 2 and 2 <= c_ < W - 2):
                info_pts.append((x, y, 0.0, 0.0, "edge"))
                continue
            win = core[max(0, r - 5):r + 6, max(0, c_ - 5):c_ + 6]
            py_, px_ = np.nonzero(win)
            nx, ny = (px_.mean() + max(0, c_ - 5)) - c_, (py_.mean() + max(0, r - 5)) - r
            ln = math.hypot(nx, ny) or 1.0
            nx, ny = nx / ln, ny / ln  # into the town
            tx, ty = int(x // 16), int(y // 16)
            ix, iy = int((x + nx * 12) // 16), int((y + ny * 12) // 16)
            box = (slice(max(0, r - 1), r + 2), slice(max(0, c_ - 1), c_ + 2))
            gate = (slice(max(0, r - 3), r + 4), slice(max(0, c_ - 3), c_ + 4))
            why = ""
            if not (floor[ty, tx] and floor[iy, ix] and level[ty, tx] == level[iy, ix]):
                why = "level"
            elif paved[gate].any() or path_[gate].any():
                why = "gate"
            elif house[box].any():
                why = "house"
            elif taken[box].any():
                why = "busy"
            info_pts.append((x, y, nx, ny, why))
        k = 0
        while k < len(info_pts):
            if info_pts[k][4]:
                k += 1
                continue
            j = k
            while j < len(info_pts) and not info_pts[j][4]:
                j += 1
            seg = info_pts[k:j]
            abut = [k > 0 and info_pts[k - 1][4] == "house", j < len(info_pts) and info_pts[j][4] == "house"]
            if abut[0]:
                seg = info_pts[max(0, k - 2):k] + seg
            if abut[1]:
                seg = seg + info_pts[j:j + 2]
            k = j
            if len(seg) < 12:
                continue
            arc = [0.0]
            for (ax, ay, *_), (bx_, by_, *_) in zip(seg, seg[1:]):
                arc.append(arc[-1] + math.hypot(bx_ - ax, by_ - ay))
            towers = []
            if not abut[0]:
                towers.append(4.0)
            if not abut[1]:
                towers.append(arc[-1] - 4.0)
            for q in range(4, len(seg) - 4):  # at the bends
                a1 = math.atan2(seg[q][1] - seg[q - 4][1], seg[q][0] - seg[q - 4][0])
                a2 = math.atan2(seg[q + 4][1] - seg[q][1], seg[q + 4][0] - seg[q][0])
                turn = abs((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
                if turn > 0.75 and all(abs(arc[q] - t) > 70 for t in towers):
                    towers.append(arc[q])
            towers.sort()
            fill_t = []
            for t0, t1 in zip(towers, towers[1:]):  # no stretch longer than ~170 px without a tower
                n_more = int((t1 - t0) // 170)
                fill_t += [t0 + (t1 - t0) * (m_ + 1) / (n_more + 1) for m_ in range(n_more)]
            towers = sorted(towers + fill_t)
            kept = []
            for t in towers:
                q = min(range(len(arc)), key=lambda i_: abs(arc[i_] - t))
                if all(math.hypot(seg[q][0] - tx_, seg[q][1] - ty_) > 44 for tx_, ty_ in tower_xy):
                    kept.append(t)
                    tower_xy.append((seg[q][0], seg[q][1]))
            towers = kept
            run = {"id": len(wall_runs), "style": "stadt", "seed": rng.randint(0, 99999),
                   "pts": [[round(p[0], 1), round(p[1], 1)] for p in seg],
                   "n": [[round(p[2], 2), round(p[3], 2)] for p in seg],
                   "towers": [round(t, 1) for t in towers], "posts": [False, False], "abut": abut}
            wall_runs.append(run)
            n_towers += len(towers)
            for p in seg:
                mark(taken, p[0] - 8, p[1] - 8, p[0] + 8, p[1] + 8)
                mark(hidden, p[0] - 6, p[1] - 48, p[0] + 6, p[1] - 6)
                mark(ramp_cells, p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4)
            for t in towers:
                q = min(range(len(arc)), key=lambda i_: abs(arc[i_] - t))
                x, y = seg[q][0], seg[q][1]
                mark(taken, x - 16, y - 14, x + 16, y + 14)
                mark(hidden, x - 14, y - 72, x + 14, y - 8)
    n_ramp = len(wall_runs)
    print("town wall: %d stretches, %d towers, %d px" % (n_ramp, n_towers, sum(3 * (len(r["pts"]) - 1) for r in wall_runs)))
    # 0. the walls: continuous runs a hand's breadth off the paving's edge, each its own stones (tools/art_hallgrat_walls.py renders them);
    # they stop at door paths (with a gate post), at houses and where the ground steps to another level
    reach = 2.6  # cells: the wall's line lies about 10 px off the paving
    near_paved = np.zeros((H, W), bool)
    rr_ = int(math.ceil(reach))
    for dy in range(-rr_, rr_ + 1):
        for dx in range(-rr_, rr_ + 1):
            if dx * dx + dy * dy <= reach * reach:
                near_paved |= np.roll(np.roll(paved, dy, 0), dx, 1)
    lines = contours(near_paved)
    wallm = np.zeros((H, W), bool)       # under a wall
    for line in lines:
        pts = resample(chaikin(chaikin([(bx0 + c_ * C + C / 2, by0 + r * C + C / 2) for r, c_ in line])), 3.0)
        info_pts = []
        for x, y in pts:
            r, c_ = cell(x, y)
            ok = 0 <= r < H and 0 <= c_ < W
            nx = ny = 0.0
            if ok:
                win = paved[max(0, r - 5):r + 6, max(0, c_ - 5):c_ + 6]
                py_, px_ = np.nonzero(win)
                if len(px_) < 4:
                    ok = False
                else:
                    nx, ny = (px_.mean() + max(0, c_ - 5)) - c_, (py_.mean() + max(0, r - 5)) - r
                    ln = math.hypot(nx, ny) or 1.0
                    nx, ny = nx / ln, ny / ln
            why = ""
            if ok:
                dist = district_of(x, y)
                tx, ty = int(x // 16), int(y // 16)
                sx_, sy_ = int((x + nx * 14) // 16), int((y + ny * 14) // 16)
                ox_, oy_ = int((x - nx * 6) // 16), int((y - ny * 6) // 16)
                if dist is None or dist == "glasbruch":
                    why = "out"
                elif not (floor[ty, tx] and floor[oy_, ox_] and level[ty, tx] == level[sy_, sx_] == level[oy_, ox_]):
                    why = "level"
                else:
                    box = (slice(max(0, r - 1), r + 2), slice(max(0, c_ - 1), c_ + 2))
                    big = (slice(max(0, r - 3), r + 4), slice(max(0, c_ - 3), c_ + 4))
                    if path_[big].any():
                        why = "path"
                    elif house[box].any() and not (taken[box] & ~house[box] & ~hidden[box]).any():
                        why = "house"
                    elif (taken[box] & ~house[box]).any() or paved[r, c_]:
                        why = "busy"
            info_pts.append((x, y, nx, ny, why if ok else "edge"))
        # the valid stretches, carved into runs with now and then a gap
        k = 0
        while k < len(info_pts):
            if info_pts[k][4]:
                k += 1
                continue
            j = k
            while j < len(info_pts) and not info_pts[j][4]:
                j += 1
            seg = info_pts[k:j]
            gate_a = k > 0 and info_pts[k - 1][4] == "path"
            gate_b = j < len(info_pts) and info_pts[j][4] == "path"
            abut_a = k > 0 and info_pts[k - 1][4] == "house"     # it meets a house: carry it on to the house's wall
            abut_b = j < len(info_pts) and info_pts[j][4] == "house"
            if abut_a:
                seg = info_pts[max(0, k - 2):k] + seg
            if abut_b:
                seg = seg + info_pts[j:j + 2]
            k = j
            if len(seg) < 10:
                continue
            dist = district_of(seg[len(seg) // 2][0], seg[len(seg) // 2][1])
            style_pool = {"fuss": ("ruine", "ruine", "feld"), "verloren": ("ruine",), "rand": ("feld", "feld", "garten")}.get(dist, ("garten", "garten", "feld"))
            if rng.random() > {"verloren": 0.55, "rand": 0.7}.get(dist, 0.9):
                continue
            i = 0
            while i < len(seg) - 8:
                n = int(rng.uniform(18, 70) if dist not in ("fuss", "verloren") else rng.uniform(8, 30))
                part = seg[i:i + n]
                if len(seg) - (i + n) < 8:  # no stub at the end
                    part = seg[i:]
                if len(part) >= 8:
                    style = rng.choice(style_pool)
                    run = {"id": len(wall_runs), "style": style, "seed": rng.randint(0, 99999),
                           "pts": [[round(p[0], 1), round(p[1], 1)] for p in part],
                           "n": [[round(p[2], 2), round(p[3], 2)] for p in part],
                           "posts": [bool(i == 0 and gate_a), bool(i + len(part) >= len(seg) and gate_b)],
                           "abut": [bool(i == 0 and abut_a), bool(i + len(part) >= len(seg) and abut_b)]}
                    wall_runs.append(run)
                    for p in part:
                        mark(taken, p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5)
                        mark(wallm, p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4)
                i += len(part)
                if rng.random() < (0.45 if dist in ("fuss", "verloren") else 0.2):
                    i += int(rng.uniform(5, 12))  # a gap: a fallen stretch, a way through
    n_wall = len(wall_runs) - n_ramp
    # 1. at the houses: little scenes, not single things (planters either side of a door, a shop's crates stacked with a barrel and
    # sacks before them, a woodpile against the side wall, a bench under the window, an abandoned house's rubble)
    n_house = 0
    WHY.clear()

    def group(items, allow=True):
        """[(type, x, y)]: placed one after another, touching each other, all on the street's edge if need be."""
        got = 0
        for t, x, y in items:
            if place(t, x, y, pad=0, allow_hidden=allow, street=True):
                got += 1
        return got
    for b, info, left, right in houses:
        t = b["type"]
        if t.startswith("stand_") or "poly" in info:
            continue
        fx, fy = b["px"]
        door_x = b["door"][0] if b.get("door") else fx
        front = b["view"] in ("s",)
        dw = lambda k: art["deko_" + k]["foot"][0]  # noqa: E731
        dd = lambda k: art["deko_" + k]["foot"][1]  # noqa: E731
        if front and not t.startswith(("laden", "verlassen", "stall", "torhaus")) and rng.random() < 0.8:  # a pair either side of the door
            k_ = rng.choice(("kuebel", "kuebel", "urne")) if not t.startswith("halle") else "urne"
            off = 21 + dw(k_) / 2
            n_house += group([(k_, door_x - off, fy + dd(k_) + 4), (k_, door_x + off, fy + dd(k_) + 4)])
        first = left + 12 if door_x - left > right - door_x else right - 12   # the corner away from the door first, then the other
        scene_roll = rng.random()
        for far in (first, left + right - first):
            if abs(far - door_x) < 34:
                continue
            side = -1 if far < fx else 1
            got = 0
            if t.startswith("laden"):
                x = far - side * 2
                got = group([("kisten", x, fy + dd("kisten") + 4), ("fass", x - side * (dw("kisten") / 2 + dw("fass") / 2 + 1), fy + dd("fass") + 4),
                             ("saecke", x + side * 2, fy + dd("kisten") + dd("saecke") + 9)])
                if got and front and rng.random() < 0.6:
                    got += group([("kruege", door_x - side * 30, fy + dd("kruege") + 4)])
                if got and front:
                    group([("schild", door_x - side * 24, fy + dd("schild") + 3)])
                    if rng.random() < 0.6:
                        group([("koerbe", door_x - side * 44, fy + dd("koerbe") + 5)])
            elif t.startswith("verlassen"):
                got = group([("steine", far, fy + dd("steine") + 3), ("fass_lieg", far - side * 30, fy + dd("fass_lieg") + 6)])
            elif t.startswith("stall"):
                got = group([("heu", far, fy + dd("heu") + 4), ("heu", far - side * (dw("heu") + 2), fy + dd("heu") + 4),
                             ("karren", far - side * 20, fy + dd("heu") + dd("karren") + 12), ("trog", door_x - side * 46, fy + dd("trog") + 5)])
            elif t.startswith("torhaus"):
                got = group([("fass", far, fy + dd("fass") + 4), ("kisten", far - side * 30, fy + dd("kisten") + 4)])
            elif scene_roll < 0.18:  # the woodpile against the side wall
                got = group([("holz", (left - dw("holz") / 2 - 3) if side < 0 else (right + dw("holz") / 2 + 3), fy - 3)])
            elif scene_roll < 0.3:
                got = group([("holz", far, fy + dd("holz") + 4)])
            elif scene_roll < 0.42:  # where the wood is split
                got = group([("hackklotz", far, fy + dd("hackklotz") + 6), ("holz", far - side * 26, fy + dd("holz") + 4)])
            elif scene_roll < 0.55:  # the washing hangs out beside the house
                got = group([("waesche", (left - dw("waesche") / 2 - 8) if side < 0 else (right + dw("waesche") / 2 + 8), fy - 2)])
            elif scene_roll < 0.75 and front:  # a bench under the window, a jug beside it
                got = group([("bank_ew", far - side * 8, fy + dd("bank_ew") + 4), ("kruege", far + side * 14, fy + dd("kruege") + 5)])
            elif scene_roll < 0.9:
                got = group([("fass", far, fy + dd("fass") + 4), ("saecke", far - side * 22, fy + dd("saecke") + 5)])
            n_house += got
            if got:
                break
    print("houses refused:", dict(WHY))
    WHY.clear()
    # 1b. the named places of the plan get what belongs there: wells, banners and benches on the squares, carts and hay in the yards, the
    # stonemason's blocks, kitchen fields behind fences, beds and a shrine in the gardens
    n_place = 0

    def scatter(items, rect, tries=60, street=True):
        x0, y0, w, h_ = rect
        got = 0
        for t in items:
            for _ in range(tries):
                x = (x0 + rng.uniform(0.1, 0.9) * w) * 16
                y = (y0 + rng.uniform(0.25, 0.97) * h_) * 16
                if place(t, x, y, pad=1, street=street):
                    got += 1
                    break
        return got
    PLACE_THINGS = {
        "forum": ["fahne", "fahne", "fahne", "fahne", "bank_ew", "bank_ew", "schrein"],
        "brunnenhof": ["fahne", "bank_ew", "kuebel", "kuebel", "urne", "bank_ns"],
        "steinmarkt": ["fahne", "fahne", "koerbe", "koerbe", "kisten", "fass", "saecke", "kruege", "bank_ew", "karren", "trog", "schild"],
        "karrenhof": ["karren", "karren", "heu", "heu", "heu", "trog", "fass", "kisten", "hackklotz", "saecke"],
        "steinmetzhof": ["quader", "quader", "quader", "steine", "saeule", "karren", "steine", "quader"],
        "brunnenmulde": ["beet", "beet", "beet", "kuebel", "bank_ew", "schrein", "urne", "beet", "kuebel"],
        "gedenkgarten": ["schrein", "urne", "urne", "bank_ew", "beet", "beet", "saeule", "kuebel"],
        "glasschleiferei": ["kisten", "quader", "fass"],
        "lampenmacherei": ["laterne", "kisten", "fass"],
        "stallungen": ["heu", "heu", "trog", "karren", "zaun_ew", "zaun_ew"],
    }
    for pl in town.get("places", []):
        x0, y0, w, h_ = pl["rect"]
        if pl["id"] == "brunnenhof" and place("brunnen", (x0 + w / 2) * 16, (y0 + h_ / 2) * 16 + 10, pad=2, street=True):
            n_place += 1
        if pl["id"] == "steinmarkt" and place("brunnen", (x0 + w * 0.3) * 16, (y0 + h_ * 0.6) * 16, pad=2, street=True):
            n_place += 1
        if pl["kind"] == "fields":  # rows of a kitchen field, a fence along the front
            for yy in range(y0 * 16 + 36, (y0 + h_) * 16 - 16, 20):
                for xx in range(x0 * 16 + 22, (x0 + w) * 16 - 20, 38):
                    if place("acker", xx + rng.uniform(-3, 3), yy, pad=0, street=False):
                        n_place += 1
            for xx in range(x0 * 16 + 16, (x0 + w) * 16 - 16, 32):
                if rng.random() < 0.8 and place("zaun_ew", xx, (y0 + h_) * 16 - 2, pad=0):
                    n_place += 1
        n_place += scatter(PLACE_THINGS.get(pl["id"], []), pl["rect"])
    print("named places: %d things" % n_place)
    # 2. along the ways: lantern posts at a steady distance; benches and troughs against the walls, on the street side
    lanterns = []
    n_way = 0
    for run in wall_runs:
        pts, ns = run["pts"], run["n"]
        mid = len(pts) // 2
        x, y = pts[mid]
        nx, ny = ns[mid]
        dx_, dy_ = pts[-1][0] - pts[0][0], pts[-1][1] - pts[0][1]
        straight = math.hypot(dx_, dy_) > 0.9 * 3.0 * (len(pts) - 1)
        if run["style"] not in ("ruine", "stadt") and straight and len(pts) > 18 and rng.random() < 0.35:
            t = "bank_ew" if abs(dx_) > 2.2 * abs(dy_) else ("bank_ns" if abs(dy_) > 2.2 * abs(dx_) else "")
            if t == "bank_ew" and rng.random() < 0.3:
                t = "trog"
            if t:
                fw, fd = art["deko_" + t]["foot"]
                if t == "bank_ns":
                    ox, oy = x + nx * (fw / 2 + 6), y + fd / 2
                else:
                    ox, oy = x, (y + fd + 6) if ny > 0 else (y - 6)
                if place(t, ox, oy, pad=0, allow_hidden=False, street=True):
                    n_way += 1
        if run["style"] != "stadt" and rng.random() < 0.4:  # a planter, a bollard, now and then a shrine by the way
            dist = district_of(x, y)
            pool = WAYSIDE.get(dist, (None, ("prellstein",)))[1] + (("schrein",) if dist in ("staffeln", "stille", "rand") and rng.random() < 0.25 else ())
            j = rng.randrange(len(pts))
            (x, y), (nx, ny) = pts[j], ns[j]
            t = rng.choice(pool)
            if "deko_" + t in art and place(t, x + nx * 9, y + ny * 9 + art["deko_" + t]["foot"][1] / 2, pad=0, street=True):
                n_way += 1
    edge = np.zeros((H, W), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        edge |= np.roll(np.roll(paved, dy, 0), dx, 1)
    edge &= ~paved & ~path_
    ys, xs = np.nonzero(edge)
    order = list(range(len(ys)))
    rng.shuffle(order)
    for i in order:
        r, c_ = ys[i], xs[i]
        x, y = bx0 + c_ * C + C / 2, by0 + r * C + C / 2
        dist = district_of(x, y)
        if dist in (None, "glasbruch", "verloren") or not all(math.hypot(x - lx, y - ly) > 120 for lx, ly in lanterns):
            continue
        win = paved[max(0, r - 4):r + 5, max(0, c_ - 4):c_ + 5]
        py_, px_ = np.nonzero(win)
        if len(px_) < 6:
            continue
        nx, ny = (px_.mean() + max(0, c_ - 4)) - c_, (py_.mean() + max(0, r - 4)) - r
        ln = math.hypot(nx, ny) or 1.0
        nx, ny = nx / ln, ny / ln
        ox, oy = x - nx * 6, y - ny * 6 + 2
        if place("laterne", ox, oy, flip=nx > 0.3, pad=1, lv=int(level[int(y) // 16, int(x) // 16]), street=True):
            lanterns.append((ox, oy))
            n_way += 1
    # 3. greenery on the free grass (tiles: the world places plants at a jittered spot inside their tile)
    green = []
    gtaken = np.zeros((H, W), bool)
    tiles = []
    for ty in range(by0 // 16, by1 // 16):
        for tx in range(bx0 // 16, bx1 // 16):
            cx, cy = tx * 16 + 8, ty * 16 + 11
            dist = district_of(cx, cy)
            if dist is None or dist == "glasbruch" or not floor[ty, tx]:
                continue
            tiles.append((tx, ty, dist))
    rng.shuffle(tiles)

    def green_ok(tx, ty, rad, trunk_pad, allow_hidden=False):
        cx, cy = tx * 16 + 8, ty * 16 + 13
        lv = ground_ok(cx - rad, cy - rad * 0.6, cx + rad, cy + 3)
        if lv is None:
            return False
        r0, c0 = cell(cx - trunk_pad, cy - trunk_pad)
        r1, c1 = cell(cx + trunk_pad, cy + 4)
        if r0 < 0 or c0 < 0 or r1 >= H or c1 >= W:
            return False
        sl = (slice(r0, r1 + 1), slice(c0, c1 + 1))
        return not (taken[sl].any() or grown[sl].any() or gtaken[sl].any() or (hidden[sl].any() and not allow_hidden))

    def take_green(tx, ty, rad):
        cx, cy = tx * 16 + 8, ty * 16 + 13
        r0, c0 = cell(cx - rad, cy - rad * 0.7)
        r1, c1 = cell(cx + rad, cy + rad * 0.5)
        gtaken[max(0, r0):r1 + 1, max(0, c0):c1 + 1] = True

    trees = []
    knots = {}

    def grove(tx, ty):
        """A smooth value noise (12-tile knots): where the trees stand close and the bushes gather."""
        fx, fy = tx / 12.0, ty / 12.0
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        u, v = fx - ix, fy - iy
        u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)

        def kn(a, b_):
            if (a, b_) not in knots:
                knots[(a, b_)] = random.Random(a * 7919 + b_ * 104729 + SEED).random() ** 1.6
            return knots[(a, b_)]
        return (kn(ix, iy) * (1 - u) + kn(ix + 1, iy) * u) * (1 - v) + (kn(ix, iy + 1) * (1 - u) + kn(ix + 1, iy + 1) * u) * v
    for tx, ty, dist in tiles:  # trees: far enough from each other and from the houses (their crowns must not cover a roof or a door)
        if rng.random() > 0.08 + 0.8 * grove(tx, ty):  # groves and open meadows, not an even sprinkle
            continue
        k, v0, v1 = rng.choice(TREES[dist])
        v = rng.randint(v0, v1)
        rad = plants[k]["radius"][v]
        cx, cy = tx * 16 + 8, ty * 16 + 13
        if any(math.hypot(cx - a, (cy - b_) * 1.4) < 46 + 30 * (1.0 - grove(tx, ty)) for a, b_ in trees):
            continue
        if not green_ok(tx, ty, rad, 16):
            continue
        r0, c0 = cell(cx - 30, cy - 10)  # a crown hanging over a house's front would hide its door
        r1, c1 = cell(cx + 30, cy + 6)
        if taken[max(0, r0):r1 + 1, max(0, c0):c1 + 1].any():
            continue
        trees.append((cx, cy))
        take_green(tx, ty, 20)
        green.append({"kind": k, "variant": v, "tile": [tx, ty]})
    n_trees = len(green)
    # what grows against the walls and the houses: grass and bushes at a wall's foot (flowers along a garden wall, brambles at a ruin),
    # flowers and a bush at a house's corners and sides
    seen_tiles = set()

    def hug(x, y, pool, near_house=False):
        cands = []
        for ty in range(int(y // 16) - 1, int(y // 16) + 2):
            for tx in range(int(x // 16) - 1, int(x // 16) + 2):
                d = math.hypot(tx * 16 + 8 - x, ty * 16 + 13 - y)
                if d <= 12 and (tx, ty) not in seen_tiles:
                    cands.append((d, tx, ty))
        for d, tx, ty in sorted(cands):
            dist = district_of(tx * 16 + 8, ty * 16 + 12)
            if dist is None or dist == "glasbruch":
                continue
            k, v0, v1 = rng.choice(pool)
            v = rng.randint(v0, v1)
            if not green_ok(tx, ty, min(10, plants[k]["radius"][v]), 3, near_house):
                continue
            seen_tiles.add((tx, ty))
            take_green(tx, ty, 7)
            green.append({"kind": k, "variant": v, "tile": [tx, ty]})
            return True
        return False
    HUG = {"garten": (("sunbloom", 0, 3), ("moonbell", 0, 3), ("bush", 0, 3), ("grass", 0, 2), ("mist_lily", 0, 3)),
           "feld": (("grass", 0, 6), ("grass", 0, 6), ("bush", 0, 7), ("puffseed", 0, 3), ("wound_leaf", 0, 3)),
           "ruine": (("grass", 0, 6), ("bush", 0, 7), ("bush", 0, 7), ("glowfern", 0, 3), ("wound_leaf", 0, 3))}
    for run in wall_runs:
        if run["style"] == "stadt":
            continue
        for j in range(1, len(run["pts"]) - 1, 3):
            if rng.random() < 0.6:
                (x, y), (nx, ny) = run["pts"][j], run["n"][j]
                hug(x - nx * 12, y - ny * 12, HUG[run["style"]])
    for b, info, left, right in houses:
        if b["type"].startswith("stand_") or "poly" in info:
            continue
        fx, fy = b["px"]
        pool = HUG["ruine"] if b["type"].startswith("verlassen") else HUG["garten"]
        for x, y in ((left - 9, fy - 6), (right + 9, fy - 6), (left - 9, fy - 22), (right + 9, fy - 22), (left + 6, fy + 9), (right - 6, fy + 9)):
            if rng.random() < 0.55:
                hug(x, y, pool, near_house=True)
    n_hug = len(green) - n_trees
    for tx, ty, dist in tiles:  # bushes and grass in the open, mostly in the groves
        if rng.random() > 0.05 + 0.4 * grove(tx, ty):
            continue
        k, v0, v1 = rng.choice(SMALL)
        v = rng.randint(v0, v1)
        rad = plants[k]["radius"][v]
        if not green_ok(tx, ty, rad, 6):
            continue
        take_green(tx, ty, rad + 4)
        green.append({"kind": k, "variant": v, "tile": [tx, ty]})
    n_small = len(green) - n_trees - n_hug
    for tx, ty, dist in tiles:  # flowers, in little drifts
        if rng.random() > 0.06 + 0.3 * grove(tx + 6, ty + 6) or dist == "verloren":  # drifts at the edges of the groves
            continue
        k = FLOWERS[(tx // 5 * 7 + ty // 5 * 3) % len(FLOWERS)]
        v = rng.randint(0, 3)
        if not green_ok(tx, ty, 8, 4):
            continue
        take_green(tx, ty, 9)
        green.append({"kind": k, "variant": v, "tile": [tx, ty]})
    town["wall_runs"] = wall_runs
    town["deco"] = sorted(deco, key=lambda q: (q["px"][1], q["px"][0]))
    town["greenery"] = green
    json.dump(town, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    open(path, "a", encoding="utf-8").write("\n")
    print("deco: %d at houses, %d wall runs, %d by the ways; greenery: %d trees, %d against walls and houses, %d bushes/grass, %d flowers"
          % (n_house, n_wall, n_way, n_trees, n_hug, n_small, len(green) - n_trees - n_small - n_hug))
    print("refused:", WHY)
    out = [a for a in sys.argv[1:] if a.endswith(".png")]
    if out:
        can = Image.new("RGBA", (bx1 - bx0, by1 - by0), (58, 98, 70, 255))
        for d in baked["decals"]:
            if d["id"].startswith("hallgrat_") and d["id"] != "hallgrat_clear":
                can.alpha_composite(Image.open(os.path.join(ROOT, d["texture"].replace("res://", ""))), (d["x"] - bx0, d["y"] - by0))
        items = [(p["px"][1], p["type"], p["px"][0], p.get("flip", False)) for p in town["placed"] + town["deco"]]
        dots = Image.new("RGBA", can.size)
        from PIL import ImageDraw
        dr = ImageDraw.Draw(dots)
        for g in green:
            x, y = g["tile"][0] * 16 + 8 - bx0, g["tile"][1] * 16 + 13 - by0
            r = 9 if g["kind"] in ("tree", "birch", "blossom", "orchard_apple", "orchard_pear") else (4 if g["kind"] in ("bush", "grass") else 2)
            col = (30, 70, 40, 255) if r == 9 else ((70, 130, 70, 255) if r == 4 else (230, 150, 200, 255))
            dr.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=col)
        can.alpha_composite(dots)
        for y, t, x, flip in sorted(items):
            info = art[t]
            im = Image.open(os.path.join(ROOT, "assets/town/hallgrat", t + ".png"))
            fx = info["feet"][0]
            if flip:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
                fx = info["size"][0] - fx
            can.alpha_composite(im, (int(x - fx - bx0), int(y - info["feet"][1] - by0)))
        can.save(out[0])


if __name__ == "__main__":
    main()
