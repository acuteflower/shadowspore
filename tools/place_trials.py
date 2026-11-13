"""Spreads the trials of the Wächterin over the real world (docs/raetsel_konzept.md): finds a fair place for every planned trial in its named area
and writes the entries into data/puzzles.json `placed` (entries it wrote before, marked `"auto": true`, are replaced; hand-placed ones are kept).
    python3 tools/place_trials.py            report only
    python3 tools/place_trials.py --write    report and write
A site must be dry land well inside the coast, on one height level, on floor tiles (no wall, ramp or step) for the whole footprint, away from rivers
and lakes, out of the town, the start, the story places, the waystones and every other trial. Walks (the wisp's route, the crow's mound, the raven's
stations) are searched on that same level, so they can always be walked. Among the good sites the one farthest from every trial already placed wins,
so the trials of an area spread out. Deterministic: the same maps give the same places.
The Hexenwald holds only the crow's hoard, the raven trade and one root weave (user's choice, 2026-11-13)."""
import copy
import json
import math
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
W = 1100
SCRATCH_VARIANTS = None  # set by --variants=path (the mirrored weaves with their solved start states)

# ------------------------------------------------------------------ the plan
AREAS = {"Die Lichtung": "lichtung", "Nebelwald": "nebelwald", "Glasklippen": "glasklippen", "Versunkene Ruinen": "ruinen",
         "Das Leerenblühen": "leerenbluehen", "Hexenwald": "hexenwald"}
PLAN = [
    # (area, kind, tier, template)
    ("Glasklippen", "root_weave", "legendary", "weave_altes_geflecht"),
    ("Das Leerenblühen", "root_weave", "legendary", "variant:legendary"),
    ("Die Lichtung", "root_weave", "rare", "weave_geflecht"),
    ("Hexenwald", "root_weave", "rare", "variant:rare"),
    ("Nebelwald", "root_weave", "common", "weave_keimling"),
    ("Versunkene Ruinen", "root_weave", "common", "variant:common"),
    ("Versunkene Ruinen", "star_mirror", "legendary", "stars_waechterin"),
    ("Glasklippen", "star_mirror", "rare", "stars_rabe"),
    ("Das Leerenblühen", "star_mirror", "rare", "eule"),
    ("Die Lichtung", "star_mirror", "common", "stars_sichel"),
    ("Nebelwald", "star_mirror", "common", "feder"),
    ("Glasklippen", "raven_trade", "rare", ""),
    ("Versunkene Ruinen", "raven_trade", "rare", ""),
    ("Hexenwald", "raven_trade", "rare", ""),
    ("Die Lichtung", "crow_hoard", "common", ""),
    ("Glasklippen", "crow_hoard", "common", ""),
    ("Versunkene Ruinen", "crow_hoard", "common", ""),
    ("Das Leerenblühen", "crow_hoard", "common", ""),
    ("Hexenwald", "crow_hoard", "common", ""),
    ("Die Lichtung", "wisp", "common", ""),
    ("Glasklippen", "wisp", "common", ""),
    ("Versunkene Ruinen", "wisp", "common", ""),
    ("Das Leerenblühen", "wisp", "common", ""),
]
NEW_STARS = {
    "feder": {"mirror": "y", "turn": 0, "stars": [[0.18, 0.78, 2], [0.36, 0.58, 3], [0.56, 0.44, 2], [0.78, 0.26, 3], [0.6, 0.18, 2]],
              "links": [[0, 1], [1, 2], [2, 3], [2, 4]], "stones": "stars_sichel"},
    "eule": {"mirror": "y", "turn": 60, "faint": True, "stars": [[0.3, 0.2, 2], [0.7, 0.2, 2], [0.38, 0.4, 3], [0.62, 0.4, 3], [0.5, 0.58, 1], [0.32, 0.8, 2], [0.7, 0.82, 1]],
             "links": [[0, 2], [1, 3], [2, 3], [2, 4], [3, 4], [4, 5], [4, 6]], "stones": "stars_rabe"},
}
# places that stay free of trials: (tile, radius in tiles)
STORY = [((463, 616), 70), ((480, 660), 40), ((498, 698), 36), ((493, 685), 25), ((786, 676), 90), ((755, 482), 26), ((738, 936), 32),
         ((884, 689), 26), ((754, 700), 26), ((891, 965), 32), ((499, 258), 46), ((736, 736), 26), ((791, 639), 26), ((814, 920), 36)]
for _w in json.loads((ROOT / "data/waystones.json").read_text()).get("statues", []):  # the goddess statues and their flagstone beds
    STORY.append(((int(_w["tile"][0]), int(_w["tile"][1])), 24))
SPACING = 46  # tiles between any two trials' key points


# ------------------------------------------------------------------ maps
def load():
    relief = np.asarray(Image.open(ROOT / "assets/world/relief.png").convert("RGBA")).astype(np.int32)
    level = relief[:, :, 0]
    kind = relief[:, :, 1] & 15
    biome = relief[:, :, 3]
    land = np.asarray(Image.open(ROOT / "assets/world/land_sdf.png").convert("L")).astype(np.int32)
    water = np.asarray(Image.open(ROOT / "assets/world/map_water.png").convert("RGB"))[:, :, 0] > 0
    lakes = np.asarray(Image.open(ROOT / "assets/world/lakes_sdf.png").convert("L")) < 150
    wet = water | lakes
    for _ in range(3):  # three tiles of dry bank
        wet = wet | np.roll(wet, 1, 0) | np.roll(wet, -1, 0) | np.roll(wet, 1, 1) | np.roll(wet, -1, 1)
    good = (kind == 0) & (land >= 200) & ~wet
    wm = json.loads((ROOT / "data/world_map.json").read_text())
    runs, flat = wm["grid"], []
    for i in range(0, len(runs), 2):
        flat.extend([int(runs[i])] * int(runs[i + 1]))
    g = W // 4
    grid = np.array(flat, dtype=np.int32).reshape(g, g)
    names = [s.get("name", "") for s in wm["supers"]]
    sup = np.full((g, g), -1, np.int32)
    for r, reg in enumerate(wm["regions"]):
        sup[grid == r] = int(reg.get("super", -1))
    area = np.repeat(np.repeat(sup, 4, 0), 4, 1)[:W, :W]
    return level, good, biome, area, names


class Sites:
    def __init__(self):
        self.level, self.good, self.biome, self.area, self.names = load()
        self.integrals = {}
        self.taken = []  # key points of placed trials (tile)

    def _ii(self, lvl):
        if lvl not in self.integrals:
            m = (self.good & (self.level == lvl)).astype(np.int32)
            self.integrals[lvl] = np.pad(m.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        return self.integrals[lvl]

    def rect_ok(self, x0, y0, x1, y1, lvl):
        """Every tile of [x0, x1] x [y0, y1] is good floor of level `lvl`."""
        if x0 < 0 or y0 < 0 or x1 >= W or y1 >= W:
            return False
        ii = self._ii(lvl)
        s = ii[y1 + 1, x1 + 1] - ii[y0, x1 + 1] - ii[y1 + 1, x0] + ii[y0, x0]
        return s == (x1 - x0 + 1) * (y1 - y0 + 1)

    def in_area(self, x, y, name, margin=10):
        idx = self.names.index(name)
        hexen = name == "Hexenwald"
        for dx, dy in ((0, 0), (margin, 0), (-margin, 0), (0, margin), (0, -margin), (margin, margin), (-margin, -margin), (margin, -margin), (-margin, margin)):
            xx, yy = min(W - 1, max(0, x + dx)), min(W - 1, max(0, y + dy))
            if self.area[yy, xx] != idx or (self.biome[yy, xx] == 205) != hexen:
                return False
        return True

    def free(self, pts, gap=SPACING):
        for p in pts:
            for (s, r) in STORY:
                if math.dist(p, s) < r:
                    return False
            for q in self.taken:
                if math.dist(p, q) < gap:
                    return False
        return True

    def score(self, pts):
        if not self.taken:
            return 1e9
        return min(math.dist(p, q) for p in pts for q in self.taken)

    def walk(self, start, lvl, limit, avoid_edge=1):
        """Breadth-first over good floor of one level (`avoid_edge` tiles off its edge) within `limit` tiles: dist and parent maps."""
        sx, sy = start
        dist = {start: 0}
        par = {}
        q = deque([start])
        while q:
            p = q.popleft()
            d = dist[p]
            if d >= limit:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (p[0] + dx, p[1] + dy)
                if n in dist or abs(n[0] - sx) > limit or abs(n[1] - sy) > limit:
                    continue
                if not self.rect_ok(n[0] - avoid_edge, n[1] - avoid_edge, n[0] + avoid_edge, n[1] + avoid_edge, lvl):
                    continue
                dist[n] = d + 1
                par[n] = p
                q.append(n)
        return dist, par

    @staticmethod
    def path(par, end):
        out = [end]
        while out[-1] in par:
            out.append(par[out[-1]])
        return out[::-1]


def candidates(sites, name, stride=4):
    idx = sites.names.index(name)
    ys, xs = np.nonzero(sites.area[::stride, ::stride] == idx)
    pts = [(int(x) * stride, int(y) * stride) for x, y in zip(xs, ys)]
    pts.sort(key=lambda p: (p[0] * 7919 + p[1] * 104729) % 1000003)  # a fixed shuffle
    return pts


def weave_box(template):
    xs = [c["at"][0] for c in template["cubes"].values()]
    ys = [c["at"][1] for c in template["cubes"].values()]
    return int(math.floor(min(xs))) - 3, int(math.floor(min(ys))) - 3, int(math.ceil(max(xs))) + 3, int(math.ceil(max(ys))) + 3


def place(sites, name, kind, templ):
    """Cheap checks first, then the sites farthest from every placed trial are tried in turn; the first whose walks work wins."""
    pre = []
    for (x, y) in candidates(sites, name):
        if not sites.in_area(x, y, name):
            continue
        lvl = int(sites.level[y, x])
        if kind == "root_weave":
            bx0, by0, bx1, by1 = weave_box(templ)
            ok = sites.rect_ok(x + bx0, y + by0, x + bx1, y + by1, lvl)
            pts = [(x, y)]
        elif kind == "star_mirror":
            ok = sites.rect_ok(x - 10, y - 5, x + 10, y + 17, lvl)
            pts = [(x, y), (x, y + 10)]
        else:
            r = 2 if kind == "wisp" else 3
            ok = sites.rect_ok(x - r, y - r, x + r, y + r, lvl)
            pts = [(x, y)]
        if ok and sites.free(pts, SPACING):
            pre.append((sites.score(pts), x, y, lvl, pts))
    pre.sort(key=lambda c: (-c[0], c[1], c[2]))
    for sc, x, y, lvl, pts in pre[:400]:
        entry = None
        if kind in ("root_weave", "star_mirror"):
            entry = {"tile": [x, y]}
        elif kind in ("crow_hoard", "raven_trade"):
            far = 70 if kind == "raven_trade" else 44
            dist, par = sites.walk((x, y), lvl, far)
            ring = [p for p, d in dist.items() if (far - 14) <= d <= far and sites.rect_ok(p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2, lvl)]
            if not ring:
                continue
            ring.sort(key=lambda p: (-math.dist(p, (x, y)), p))
            end = ring[0]
            if math.dist(end, (x, y)) < (34 if kind == "raven_trade" else 22) or not sites.free([end], SPACING * 0.6):
                continue
            entry = {"tile": [x, y], "mound": [end[0], end[1]]}
            pts = [(x, y), end]
            if kind == "raven_trade":
                path = sites.path(par, end)
                n = len(path)
                entry["stations"] = [[path[int(n * f)][0], path[int(n * f)][1]] for f in (0.28, 0.52, 0.76)]
        elif kind == "wisp":
            dist, par = sites.walk((x, y), lvl, 96, avoid_edge=2)
            ring = [p for p, d in dist.items() if 80 <= d <= 96 and sites.rect_ok(p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 3, lvl)]
            if not ring:
                continue
            ring.sort(key=lambda p: (-math.dist(p, (x, y)), p))
            end = ring[0]
            if math.dist(end, (x, y)) < 45:
                continue
            path = sites.path(par, end)
            route = [path[i] for i in range(0, len(path), 11)]
            if math.dist(route[-1], end) > 4:
                route.append(end)
            else:
                route[-1] = end
            if not sites.free([route[len(route) // 2], end], SPACING * 0.6):
                continue
            n = len(route)
            entry = {"tile": [x, y], "route": [[p[0], p[1]] for p in route], "stops": list(range(2, n - 1, 2)) + [n - 1], "linger": [min(n - 2, max(2, (n // 2) // 2 * 2))]}
            pts = [(x, y), route[n // 2], end]
        if entry is None:
            continue
        return (sites.score(pts), entry, pts)
    return None


def main():
    write = "--write" in sys.argv
    variants = {}
    for a in sys.argv:
        if a.startswith("--variants="):
            variants = json.loads(Path(a.split("=", 1)[1]).read_text())
    path = ROOT / "data/puzzles.json"
    table = json.loads(path.read_text(encoding="utf-8"))
    trial = {e["id"]: e for e in table["trial_world"]}
    hand = [e for e in table["placed"] if not e.get("auto")]
    sites = Sites()
    for e in hand:  # the trials placed by hand count as taken
        for k in ("tile", "mound"):
            if k in e:
                sites.taken.append(tuple(e[k]))
        for p in e.get("route", []) + e.get("stations", []):
            sites.taken.append(tuple(p))
    out = []
    used_ids = set()
    for name, kind, tier, tmpl_id in PLAN:
        slug = AREAS[name]
        base = {"wisp": "wisp", "crow_hoard": "hoard", "raven_trade": "raben", "root_weave": "weave", "star_mirror": "stars"}[kind]
        tid = "%s_%s" % (base, slug)
        k = 2
        while tid in used_ids:
            tid = "%s_%s_%d" % (base, slug, k)
            k += 1
        used_ids.add(tid)
        templ = None
        if kind == "root_weave":
            templ = copy.deepcopy(variants[tmpl_id.split(":")[1]] if tmpl_id.startswith("variant:") else trial[tmpl_id])
        elif kind == "star_mirror":
            if tmpl_id in NEW_STARS:
                spec = NEW_STARS[tmpl_id]
                templ = copy.deepcopy(trial[spec["stones"]])
                for key in ("mirror", "turn", "stars", "links"):
                    templ[key] = spec[key]
                templ["faint"] = spec.get("faint", False)
                templ.pop("lines", None)
            else:
                templ = copy.deepcopy(trial[tmpl_id])
        best = place(sites, name, kind, templ)
        if best is None:
            print("NO SITE: %s %s %s" % (name, kind, tier))
            continue
        sc, site, pts = best
        sites.taken += pts
        entry = {"id": tid, "kind": kind, "tier": tier, "area": name, "auto": True}
        if templ is not None:
            for key, v in templ.items():
                if key not in ("id", "kind", "tier", "tile"):
                    entry[key] = v
        entry.update(site)
        if kind in ("crow_hoard", "raven_trade"):
            entry["variant"] = int(sum(site["tile"]) % (4 if kind == "crow_hoard" else 3))
        out.append(entry)
        print("%-24s %-18s %-10s %-9s at %s (nearest other trial %.0f tiles)" % (tid, name, kind, tier, site["tile"], sc), flush=True)
    if write:
        table["placed"] = hand + out
        text = json.dumps(table, indent="\t", ensure_ascii=False) + "\n"
        path.write_text(text, encoding="utf-8")
        print("wrote %d trials (%d by hand kept)" % (len(out), len(hand)))


if __name__ == "__main__":
    main()
