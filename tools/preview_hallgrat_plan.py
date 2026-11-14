#!/usr/bin/env python3
"""Checks and draws the ground plan of Hallgrat (data/hallgrat.json, docs/stadt_westen_konzept.md stage 1) on the real baked relief.

    py -3 tools/preview_hallgrat_plan.py [--fix] [out.png]      (default docs/img/hallgrat_plan.png)

`--fix` writes back into the JSON: every way is routed over the real ground through its `via` points (`line`: a walkable route that only
changes level on a connector), and a place that does not fit its level is moved to the nearest spot (within 8 tiles) where it does.

Checks (prints `HALLGRAT PLAN OK` or the problems):
- every place stands on floor of its own level (at least 85 % of its tiles; connectors count as floor),
- every leitstein and gate stands on land, every place lies inside its district,
- every way only changes level on a connector (it is walkable as drawn),
- every milestone stands on flat level-0 floor off the road.
Needs numpy and PIL."""
import heapq, json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world_data import load_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PX = 6  # picture pixels per tile
LEVEL_TONE = [(58, 74, 62), (84, 104, 82), (112, 132, 104), (146, 160, 128)]
TONES = ["e7d27a", "78f4e6", "c79bff", "ff9f7a"]  # the four notes of the town's motif


def hexc(s, a=255):
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def inside(poly, x, y):
    c = False
    for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            c = not c
    return c


def route(level, kind, land, a, b, box):
    """A* over walkable tiles: same level, or through a connector (level steps by one). -> list of tiles or None."""
    x0, y0, x1, y1 = box

    def walk(x, y):
        return x0 <= x < x1 and y0 <= y < y1 and land[y, x] and kind[y, x] != 1

    def step(p, q):
        lp, lq = level[p[1], p[0]], level[q[1], q[0]]
        if lp == lq:
            return True
        return abs(int(lp) - int(lq)) == 1 and (kind[p[1], p[0]] in (2, 3, 4) or kind[q[1], q[0]] in (2, 3, 4))

    best, came, heap = {a: 0.0}, {}, [(0.0, a)]
    while heap:
        _, p = heapq.heappop(heap)
        if p == b:
            out = [b]
            while out[-1] != a:
                out.append(came[out[-1]])
            return out[::-1]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dx, p[1] + dy)
            if not walk(*q) or not step(p, q):
                continue
            ng = best[p] + 1.0 + (0.4 if kind[q[1], q[0]] in (2, 3, 4) else 0.0)
            if ng < best.get(q, 1e18):
                best[q], came[q] = ng, p
                heapq.heappush(heap, (ng + abs(q[0] - b[0]) + abs(q[1] - b[1]), q))
    return None


def simplify(tiles):
    """Keep the corners of a 4-connected route (and its ends)."""
    if len(tiles) < 3:
        return [list(t) for t in tiles]
    out = [tiles[0]]
    for i in range(1, len(tiles) - 1):
        d0 = (tiles[i][0] - tiles[i - 1][0], tiles[i][1] - tiles[i - 1][1])
        d1 = (tiles[i + 1][0] - tiles[i][0], tiles[i + 1][1] - tiles[i][1])
        if d0 != d1:
            out.append(tiles[i])
    out.append(tiles[-1])
    return [list(t) for t in out]


def fit(level, kind, land, rect, lv):
    x, y, w, h = rect
    good = 0
    for ty in range(y, y + h):
        for tx in range(x, x + w):
            good += land[ty, tx] and kind[ty, tx] != 1 and (level[ty, tx] == lv or kind[ty, tx] in (2, 3, 4))
    return good / float(w * h)


def fix(town, level, kind, land):
    for p in town["places"]:
        if fit(level, kind, land, p["rect"], p["level"]) >= 0.85:
            continue
        x, y, w, h = p["rect"]
        best = None
        for r in range(1, 9):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if max(abs(dx), abs(dy)) != r:
                        continue
                    f = fit(level, kind, land, [x + dx, y + dy, w, h], p["level"])
                    if f >= 0.92 and (best is None or f > best[0] + 0.02):
                        best = (f, dx, dy)
            if best:
                break
        if best:
            print("moved %s by (%d, %d) -> %.0f %% on level %d" % (p["id"], best[1], best[2], best[0] * 100, p["level"]))
            p["rect"] = [x + best[1], y + best[2], w, h]
        else:
            print("could not fit %s" % p["id"])
    for wy in town["ways"]:
        line = []
        for a, b in zip(wy["via"][:-1], wy["via"][1:]):
            seg = route(level, kind, land, tuple(a), tuple(b), town["bounds"])
            if seg is None:
                print("no route for %s from %s to %s" % (wy["id"], a, b))
                break
            line += seg if not line else seg[1:]
        wy["line"] = simplify(line)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = args[0] if args else os.path.join(ROOT, "docs/img/hallgrat_plan.png")
    town = json.load(open(os.path.join(ROOT, "data/hallgrat.json"), encoding="utf-8"))
    relief = load_png(os.path.join(ROOT, "assets/world/relief.png"))
    level = relief[..., 0].astype(int)
    kind = (relief[..., 1] & 15).astype(int)
    land = relief[..., 3] > 0
    bx0, by0, bx1, by1 = town["bounds"]
    if "--fix" in sys.argv:
        fix(town, level, kind, land)
        path = os.path.join(ROOT, "data/hallgrat.json")
        json.dump(town, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
        open(path, "a", encoding="utf-8").write("\n")
    problems = []
    districts = {d["id"]: d for d in town["districts"]}

    def at(x, y):
        return int(level[y, x]), int(kind[y, x]), bool(land[y, x])

    for p in town["places"]:
        x, y, w, h = p["rect"]
        good = n = 0
        for ty in range(y, y + h):
            for tx in range(x, x + w):
                lv, k, ld = at(tx, ty)
                n += 1
                good += ld and (k != 1) and (lv == p["level"] or k in (2, 3, 4))
        if good < 0.85 * n:
            problems.append("place %s: only %d of %d tiles are level-%d floor" % (p["id"], good, n, p["level"]))
        d = districts.get(p["district"])
        if d is None or not inside(d["poly"], x + w / 2.0, y + h / 2.0):
            problems.append("place %s: not inside district %s" % (p["id"], p["district"]))
        if "paddock" in p:
            x, y, w, h = p["paddock"]
            bad = sum(1 for ty in range(y, y + h) for tx in range(x, x + w) if not (land[ty, tx] and kind[ty, tx] == 0 and level[ty, tx] == p["level"]))
            if bad > 0.05 * w * h:
                problems.append("paddock of %s: %d tiles off the floor" % (p["id"], bad))
    for s in town["leitsteine"]:
        lv, k, ld = at(*s["tile"])
        if not ld or k == 1:
            problems.append("leitstein %s: not on floor" % s["id"])
    for wy in town["ways"]:
        pts = wy.get("line", [])
        if len(pts) < 2:
            problems.append("way %s: not routed (run with --fix)" % wy["id"])
            continue
        prev = None
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            n = max(int(math.hypot(bx - ax, by - ay) * 3), 1)
            for i in range(n + 1):
                tx, ty = int(round(ax + (bx - ax) * i / n)), int(round(ay + (by - ay) * i / n))
                lv, k, ld = at(tx, ty)
                if not ld or k == 1:
                    problems.append("way %s: crosses a wall or the void at (%d, %d)" % (wy["id"], tx, ty))
                    break
                if prev is not None and lv != prev[0] and k not in (2, 3, 4) and prev[1] not in (2, 3, 4):
                    problems.append("way %s: jumps from level %d to %d at (%d, %d) without a connector" % (wy["id"], prev[0], lv, tx, ty))
                    break
                prev = (lv, k)
    for m in town.get("milestones", []):
        lv, k, ld = at(*m["tile"])
        if not ld or k != 0 or lv != 0:
            problems.append("milestone %s: not on flat level-0 floor" % m["id"])

    # the picture
    w, h = (bx1 - bx0) * PX, (by1 - by0) * PX
    img = Image.new("RGBA", (w, h), (10, 8, 22, 255))
    px = np.zeros((h, w, 4), dtype=np.uint8)
    sub = level[by0:by1, bx0:bx1]
    kd = kind[by0:by1, bx0:bx1]
    ld = land[by0:by1, bx0:bx1]
    base = np.zeros((by1 - by0, bx1 - bx0, 4), dtype=np.uint8)
    base[...] = (10, 8, 22, 255)
    for lv in range(4):
        base[ld & (sub == lv)] = LEVEL_TONE[lv] + (255,)
    base[ld & (kd == 1)] = (40, 34, 52, 255)
    base[ld & np.isin(kd, (2, 3, 4))] = (196, 170, 120, 255)
    px[...] = np.repeat(np.repeat(base, PX, 0), PX, 1)
    img = Image.fromarray(px, "RGBA")
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(over)

    def P(x, y):
        return ((x - bx0) * PX, (y - by0) * PX)

    for d in town["districts"]:
        poly = [P(x, y) for x, y in d["poly"]]
        dr.polygon(poly, fill=hexc(d["color"], 46), outline=hexc(d["color"], 230))
    for wy in town["ways"]:
        dr.line([P(x + 0.5, y + 0.5) for x, y in wy["line"]], fill=(255, 236, 190, 230), width=3)
    for p in town["places"]:
        x, y, ww, hh = p["rect"]
        col = (255, 214, 150, 255) if p["kind"] != "stable" else (255, 150, 90, 255)
        dr.rectangle([P(x, y), P(x + ww, y + hh)], outline=col, width=2 if p["kind"] != "stable" else 3)
        if "paddock" in p:
            x2, y2, w2, h2 = p["paddock"]
            dr.rectangle([P(x2, y2), P(x2 + w2, y2 + h2)], outline=(255, 150, 90, 200), width=1)
            dr.text(P(x2 + 1, y2 + h2 - 2), "KOPPEL", fill=(255, 190, 140, 255))
        dr.text(P(x + 0.4, y + 0.3), p["name"].replace("Ä", "AE").replace("Ü", "UE").replace("Ö", "OE"), fill=(255, 246, 230, 255))
    for g in town["gates"]:
        x, y = g["tile"]
        dr.ellipse([P(x - 0.2, y - 0.2), P(x + 3.2, y + 3.2)], outline=(255, 90, 140, 255) if g.get("sealed") else (255, 255, 255, 255), width=2)
        for hx, hy, hw, hh in g.get("houses", []):
            dr.rectangle([P(hx, hy), P(hx + hw, hy + hh)], fill=(150, 140, 170, 200), outline=(255, 255, 255, 255))
    for s in town["leitsteine"]:
        x, y = s["tile"]
        c = hexc(TONES[s["tone"]]) if not s.get("dead") else (120, 90, 120, 255)
        dr.ellipse([P(x + 0.15, y + 0.15), P(x + 0.85, y + 0.85)], fill=c, outline=(20, 20, 30, 255))
    fx, fy = town["forum"]
    dr.ellipse([P(fx - 0.3, fy - 0.6), P(fx + 1.3, fy + 1.3)], fill=(120, 244, 230, 255), outline=(255, 255, 255, 255), width=2)
    for m in town.get("milestones", []):
        x, y = m["tile"]
        if bx0 <= x < bx1 and by0 <= y < by1:
            dr.rectangle([P(x, y), P(x + 1, y + 1)], fill=(230, 230, 240, 255))
            dr.text(P(x + 1.2, y - 0.4), str(m["number"]), fill=(230, 230, 240, 255))
    ground = json.load(open(os.path.join(ROOT, "data/ground.json"), encoding="utf-8"))
    world = json.load(open(os.path.join(ROOT, "data/world_map.json")))
    cx, cy = world["start"][0] * 16 + 8, world["start"][1] * 16 + 8
    road = next((p for p in ground["paths"] if p["id"] == "westweg_1"), None)
    if road:
        dr.line([P((cx + x) / 16.0, (cy + y) / 16.0) for x, y in road["points"]], fill=(222, 196, 140, 200), width=4)
    dr.text((8, 8), "%s - %s   Grundriss (Stufe 1)" % (town["name"], town["title"].replace("Ä", "AE")), fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, over)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    for p in problems:
        print("PROBLEM:", p)
    print("HALLGRAT PLAN OK" if not problems else "HALLGRAT PLAN: %d problems" % len(problems), "->", out)


if __name__ == "__main__":
    main()
