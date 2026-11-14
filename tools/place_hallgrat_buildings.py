#!/usr/bin/env python3
"""Places Hallgrat's buildings (docs/stadt_westen_konzept.md stage 3b) the way an old town grows: in rows along its streets, wall to wall,
every house turned to the street it stands on.

  * `buildings` in data/hallgrat.json are the named ones (halls, the inn, the gatehouses, the stables): {id, type, want [x, y], level, view}.
    `view` is the side the camera sees: s = the front (the house stands north of its street), n = the back (south of it), e = the east gable
    end (its front looks east, it stands west of a north-south street), w = the same mirrored. Each is moved to the nearest spot (8 tiles).
  * `rows` fill the streets: {street (a `paving` id), palette [types], gap px, sides [+1/-1], level}. Walking along the street's centre line,
    houses are set on both sides with their street side on the street's edge, as long as the whole footprint is plain floor of the level, off
    the paving and off the houses already standing.
  * `forum_market`: the stalls in a tight ring round the Wächterin, each turned to her (front, back or side view), on the forum's paving.

Writes the result to `placed` (one list: {id, type, view, tile, px: [x, y] of the feet, flip}). Needs numpy.
    py -3 tools/place_hallgrat_buildings.py [preview.png]"""
import json, math, os, random, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import load_png
import bake_hallgrat_ground as hg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELL = 4  # px of the occupancy grid
REASONS = {}


def main():
    path = os.path.join(ROOT, "data/hallgrat.json")
    town = json.load(open(path, encoding="utf-8"))
    art = json.load(open(os.path.join(ROOT, "data/hallgrat_art.json"), encoding="utf-8"))["types"]
    baked = json.load(open(os.path.join(ROOT, "data/ground_baked.json"), encoding="utf-8"))
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    level, kind, land = relief[..., 0], relief[..., 1] & 15, relief[..., 3] > 0
    paved = np.zeros(level.shape, bool)
    for y, a, b in baked.get("hallgrat_streets", baked.get("hallgrat_clear", [])):
        paved[y, a:b + 1] = True
    N = 1100 * 16 // CELL
    taken = np.zeros((N, N), bool)
    solid = np.zeros((N, N), bool)  # only the footprints (doorways are walkable, they are where the paths start)

    def key(btype, view):
        return btype if view == "s" else "%s_%s" % (btype, "e" if view in ("e", "w") else view)

    def foot(btype, view):
        info = art.get(key(btype, view))
        return (info["foot"][0], info["foot"][1]) if info else None

    def rect_for(btype, view, edge_x, edge_y):
        """The footprint (px) whose street side lies on the street edge point: s = bottom edge, n = top, e = right, w = left."""
        fw, fd = foot(btype, view)
        if view == "s":
            return edge_x - fw / 2, edge_y - fd, fw, fd
        if view == "n":
            return edge_x - fw / 2, edge_y, fw, fd
        if view == "e":
            return edge_x - fw, edge_y - fd / 2, fw, fd
        return edge_x, edge_y - fd / 2, fw, fd

    def fits(r, lv, allow_paved=False):
        x, y, w, d = r
        m = 5.0  # tiles are 16 px: a footprint touching a street tile by a few px still stands beside the street, not on it
        for ty in range(int((y + m) // 16), int((y + d - m) // 16) + 1):
            for tx in range(int((x + m) // 16), int((x + w - m) // 16) + 1):
                if not (land[ty, tx] and kind[ty, tx] == 0 and level[ty, tx] == lv):
                    return False
                if paved[ty, tx] and not allow_paved:
                    return False
        cx0, cy0, cx1, cy1 = int(x // CELL), int(y // CELL), int((x + w) // CELL), int((y + d) // CELL)
        return not taken[cy0:cy1 + 1, cx0:cx1 + 1].any()

    def take(r, pad=0):
        x, y, w, d = r
        taken[int(y // CELL) - pad:int((y + d) // CELL) + 1 + pad, int(x // CELL) - pad:int((x + w) // CELL) + 1 + pad] = True

    placed = []
    polys = [[(x * 16.0, y * 16.0) for x, y in dd["poly"]] for dd in town["districts"] if dd["id"] not in ("verloren", "glasbruch")]

    def inside_town(r):
        x, y, w, d = r
        cx, cy = x + w / 2.0, y + d / 2.0
        for poly in polys:
            c = False
            for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
                if (ay > cy) != (by > cy) and cx < ax + (cy - ay) * (bx - ax) / (by - ay):
                    c = not c
            if c:
                return True
        return False

    def doorway(r):
        """The strip in front of a house's door (its front edge, 22 px deep): nothing may be built there, so every door opens onto its way."""
        x, y, w, d = r
        return (x - 4, y + d, w + 8, 60)  # a roof rises about 60 px above its footprint: the next house in front keeps that far off

    def doorway_free(r):
        x, y, w, d = doorway(r)
        return not taken[int(y // CELL):int((y + d) // CELL) + 1, int(x // CELL):int((x + w) // CELL) + 1].any()

    def put(bid, btype, view, r):
        x, y, w, d = r
        solid[int(y // CELL):int((y + d) // CELL) + 1, int(x // CELL):int((x + w) // CELL) + 1] = True
        feet = (x + w / 2.0, y + d)
        placed.append({"id": bid, "type": key(btype, view), "view": view, "px": [round(feet[0], 1), round(feet[1], 1)],
                       "tile": [int(feet[0] // 16), int((feet[1] - 1) // 16)], "flip": view == "w"})

    # the named buildings first
    for b in town.get("buildings", []):
        view = b.get("view", "s")
        best = None
        wx, wy = b["want"][0] * 16 + 8, b["want"][1] * 16 + 8  # the middle of the building's street side
        for rr in range(0, int(b.get("reach", 8)) * 16 + 1, 4):
            for ang in range(0, 360, 15 if rr else 360):
                ex, ey = wx + rr * math.cos(math.radians(ang)), wy + rr * math.sin(math.radians(ang))
                r = rect_for(b["type"], view, ex, ey)
                if fits(r, b["level"], allow_paved=b.get("on_paving", False)) and (view != "s" or doorway_free(r)):
                    best = r
                    break
            if best:
                break
        if best is None:
            print("NO PLACE for", b["id"])
            continue
        take(best, pad=1)
        if view == "s":
            take(doorway(best))
        put(b["id"], b["type"], view, best)
    # rows along the streets
    streets = {p["id"]: p for p in town.get("paving", [])}
    for row in town.get("rows", []):
        if "line" in row:  # a street that is no paving of its own (the Torstraße is the Westweg's end, the edges of a square)
            pts = [(x * 16 + 8.0, y * 16 + 8.0) for x, y in row["line"]]
            half = row.get("half", 14.0)
        else:
            spec = streets[row["street"]]
            line = spec.get("line") or next(w["line"] for w in town["ways"] if w["id"] == spec["way"])
            pts = hg.smooth_line([(x * 16 + 8.0, y * 16 + 8.0) for x, y in line])
            half = spec.get("width", 36) / 2.0
        name = row.get("street", row.get("id", "row"))
        rng = random.Random(sum(ord(ch) for ch in name) * 31 + row["level"])
        for side in row.get("sides", [1, -1]):
            pal = list(row["palette"])
            i = 0
            s_pos, k = 0.0, 0
            seg = [(pts[j], pts[j + 1]) for j in range(len(pts) - 1)]
            lens = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in seg]
            total = sum(lens)
            while s_pos < total:
                # the point and the normal at arc length s_pos
                acc, j = 0.0, 0
                while j < len(lens) - 1 and acc + lens[j] < s_pos:
                    acc += lens[j]
                    j += 1
                (ax, ay), (bx, by) = seg[j]
                t = (s_pos - acc) / max(lens[j], 1e-6)
                px, py = ax + (bx - ax) * t, ay + (by - ay) * t
                tx, ty = (bx - ax) / max(lens[j], 1e-6), (by - ay) / max(lens[j], 1e-6)
                nx, ny = -ty * side, tx * side  # from the street towards this side
                if abs(ny) >= abs(nx):
                    view = "s" if ny < 0 else "n"
                else:
                    view = "e" if nx < 0 else "w"
                btype = pal[i % len(pal)]
                ex, ey = px + nx * (half + 3), py + ny * (half + 3)
                r = rect_for(btype, view, ex, ey)
                along = r[2] if view in ("s", "n") else r[3]
                why = "view" if view not in row.get("views", ["s"]) else ("fit" if not fits(r, row["level"]) else ("town" if not inside_town(r) else ("door" if not doorway_free(r) else "")))
                REASONS[name] = REASONS.get(name, {})
                REASONS[name][why] = REASONS[name].get(why, 0) + 1
                if why == "":
                    take(r)
                    take(doorway(r))
                    put("%s_%d_%d_%d" % (name, row["level"], side, k), btype, view, r)
                    k += 1
                    i += 1
                    s_pos += along + row.get("gap", 2)
                    if rng.random() < row.get("lane", 0.12):  # now and then a narrow lane between two houses
                        s_pos += 18
                else:
                    s_pos += 6
    # fill the terraces: in every district and level, from the back (north) to the front, houses that face the camera; the strip in
    # front of each door stays free, so no house stands in front of another, and every door gets its own path to the streets (below)
    for fill in town.get("fill", []):
        pal = list(fill["palette"])
        rng = random.Random(sum(ord(ch) for ch in fill["district"]) * 7 + fill["level"])
        poly = next(dd["poly"] for dd in town["districts"] if dd["id"] == fill["district"])
        xs = [p_[0] * 16 for p_ in poly]
        ys = [p_[1] * 16 for p_ in poly]
        k = i = 0
        for fy in range(int(min(ys)) + 32, int(max(ys)), 4):
            for fx in range(int(min(xs)), int(max(xs)), 4):
                if k >= fill.get("max", 99):
                    break
                btype = pal[i % len(pal)]
                fw, fd = foot(btype, "s")
                r = (fx - fw / 2.0, fy - fd, fw, fd)
                if fits(r, fill["level"]) and inside_town(r) and doorway_free(r):
                    take(r)
                    take(doorway(r))
                    put("%s_%d_%d" % (fill["district"], fill["level"], k), btype, "s", r)
                    k += 1
                    i += 1 + (1 if rng.random() < 0.3 else 0)
    # a path from every door to the nearest street: A* over the free floor of the door's level on a 4 px grid
    street_px = np.zeros((N, N), bool)
    for dd in baked["decals"]:
        if dd["id"].startswith("hallgrat_") and not dd["id"].startswith("hallgrat_zugang"):
            from PIL import Image
            mk = np.array(Image.open(os.path.join(ROOT, dd["mask"].replace("res://", ""))))[..., 0] > 0
            hh, ww = mk.shape
            sub = mk[::CELL, ::CELL]
            y0, x0 = dd["y"] // CELL, dd["x"] // CELL
            street_px[y0:y0 + sub.shape[0], x0:x0 + sub.shape[1]] |= sub
    doors = json.load(open(os.path.join(ROOT, "data/hallgrat_art.json"), encoding="utf-8")).get("doors", {})
    paths = []
    lost = set()
    import heapq
    for b in placed:
        if b["view"] != "s" or b["type"].startswith("stand_"):
            continue
        base = b["type"]
        dx = float(doors.get(base, 0.0))
        sx, sy = int((b["px"][0] + dx) // CELL), int((b["px"][1] + 3) // CELL)
        lv = int(level[int(b["px"][1] // 16), int(b["px"][0] // 16)])
        if street_px[sy:sy + 3, sx - 1:sx + 2].any():
            continue  # the door opens right onto a street
        start = (sx, sy)
        best, came, heap, goal = {start: 0.0}, {}, [(0.0, start)], None
        while heap and len(best) < 120000:
            _, cur = heapq.heappop(heap)
            if street_px[cur[1], cur[0]]:
                goal = cur
                break
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (cur[0] + ddx, cur[1] + ddy)
                tx, ty = q[0] * CELL // 16, q[1] * CELL // 16
                if not land[ty, tx] or kind[ty, tx] == 1 or (kind[ty, tx] == 0 and level[ty, tx] != lv):
                    continue
                if solid[q[1], q[0]]:
                    continue
                ng = best[cur] + 1.0 + (0.6 if ddy == 0 else 0.0)  # straight out of the door first, then along
                if ng < best.get(q, 1e18):
                    best[q], came[q] = ng, cur
                    heapq.heappush(heap, (ng, q))
        if goal is None:
            print("no path from the door of", b["id"], "- left out (every house opens onto a way)")
            lost.add(b["id"])
            continue
        line = [goal]
        while line[-1] != start:
            line.append(came[line[-1]])
        line.reverse()
        pts = hg.simplify([(x * CELL + 2.0, y * CELL + 2.0) for x, y in line], 3.0)
        paths.append({"id": b["id"], "px": [[round(x, 1), round(y, 1)] for x, y in pts]})
    placed[:] = [b for b in placed if b["id"] not in lost]
    town["door_paths"] = paths
    print("%d door paths" % len(paths))
    # the market round the Wächterin
    market = town.get("forum_market", {})
    if market:
        cx, cy = town["forum"][0] * 16 + 8, town["forum"][1] * 16 + 8
        rx, ry = market["radius"]
        stalls = []
        for i, deg in enumerate(market["angles"]):
            a = math.radians(deg)
            sx, sy = cx + rx * 16 * math.cos(a), cy + ry * 16 * math.sin(a)
            c, s = math.cos(a), math.sin(a)
            face = "hinten" if s > 0.5 else ("vorn" if s < -0.5 else "seite")
            btype = "stand_%d_%s" % (i % 3, face)
            fw, fd = art[btype]["foot"]
            r = (sx - fw / 2, sy - fd, fw, fd)
            stalls.append({"id": "stand_%d" % i, "type": btype, "view": "s", "px": [round(sx, 1), round(sy, 1)],
                           "tile": [int(sx // 16), int((sy - 1) // 16)], "flip": face == "seite" and c < 0})
            take(r)
        placed.extend(stalls)
        print("forum market: %d stalls" % len(stalls))
    town["placed"] = placed
    for b in town.get("buildings", []):
        b.pop("tile", None)
    market.pop("stalls", None)
    json.dump(town, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    open(path, "a", encoding="utf-8").write("\n")
    print("%d buildings placed" % len(placed))
    if "--why" in sys.argv:
        for k, v in REASONS.items():
            print("  ", k, v)
    if len([a for a in sys.argv[1:] if not a.startswith("--")]):
        sys.argv = [sys.argv[0]] + [a for a in sys.argv[1:] if not a.startswith("--")]
        from PIL import Image
        bx0, by0, bx1, by1 = [v * 16 for v in town["bounds"]]
        can = Image.new("RGBA", (bx1 - bx0, by1 - by0), (58, 98, 70, 255))
        for d in baked["decals"]:
            if d["id"].startswith("hallgrat_"):
                can.alpha_composite(Image.open(os.path.join(ROOT, d["texture"].replace("res://", ""))), (d["x"] - bx0, d["y"] - by0))
        for p in sorted(placed, key=lambda q: q["px"][1]):
            info = art[p["type"]]
            im = Image.open(os.path.join(ROOT, "assets/town/hallgrat", p["type"] + ".png"))
            fx = info["feet"][0]
            if p["flip"]:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
                fx = info["size"][0] - fx
            can.alpha_composite(im, (int(p["px"][0] - fx - bx0), int(p["px"][1] - info["feet"][1] - by0)))
        can.save(sys.argv[1])


if __name__ == "__main__":
    main()
