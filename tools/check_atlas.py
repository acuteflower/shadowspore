#!/usr/bin/env python3
"""Static validator for the Shadowspore 2.0 World Atlas (data/world/).

Validates schema, size classes, curved Catmull-Rom footprints (clockwise winding,
no duplicate vertices, no self-intersections, exact triangulation parity), exact
polygon overlaps, threshold seam alignment (LINE_REACH & LINE_SNAP), directed
graph reachability (respecting one_way), downhill water flow, moods, tree
species (including zone borders[].mix), place vertex containment, and landscape
integrity.

Usage:
  py -3 tools/check_atlas.py [--continent <id>] [--verbose]
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from collections import deque
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
WORLD_DIR = DATA_DIR / "world"

LINE_REACH = 2.5
LINE_SNAP = 0.6
CURVE_STEP = 1.5
SEAMLESS_KINDS = {"path", "pass", "ford", "bridge", "jump"}
HARD_KINDS = {"tunnel", "ferry", "ship"}
ZONE_KINDS = {"field", "home", "settlement", "pass", "wonder", "coast", "void"}
DANGERS = {"ruhig": 0.0, "rau": 0.2, "wild": 0.4}
SIZE_CLASSES = {"S": (96, 160), "M": (160, 256), "L": (256, 384), "XL": (384, 576)}
WAY_KINDS = {"trail", "path", "cart"}
ALTMARK_REGIONS = {"suedwestkueste", "gruenland", "glaskamm", "hexenwald", "leerenbluehen"}


def load_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def polyline_length(pts: list[tuple[float, float]]) -> float:
    return sum(dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def point_along(pts: list[tuple[float, float]], share: float) -> tuple[float, float]:
    if not pts:
        return (0.0, 0.0)
    s = max(0.0, min(1.0, share))
    want = s * polyline_length(pts)
    for i in range(len(pts) - 1):
        part = dist(pts[i], pts[i + 1])
        if want <= part or i == len(pts) - 2:
            t = max(0.0, min(1.0, want / max(part, 1e-6)))
            return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
        want -= part
    return pts[-1]


def sub_polyline(pts: list[tuple[float, float]], f: float, t: float) -> list[tuple[float, float]]:
    if len(pts) < 2:
        return []
    total = max(polyline_length(pts), 1e-6)
    lo = max(0.0, min(1.0, min(f, t))) * total
    hi = max(0.0, min(1.0, max(f, t))) * total
    out = [point_along(pts, lo / total)]
    walked = 0.0
    for i in range(len(pts) - 1):
        walked += dist(pts[i], pts[i + 1])
        if lo < walked < hi:
            out.append(pts[i + 1])
    out.append(point_along(pts, hi / total))
    return out


def _curve_piece(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    step: float,
    out: list[tuple[float, float]],
) -> None:
    count = max(1, math.ceil(dist(p1, p2) / max(step, 0.1)))
    for k in range(count):
        t = k / float(count)
        t2 = t * t
        t3 = t2 * t
        x = 0.5 * (
            2.0 * p1[0]
            + (p2[0] - p0[0]) * t
            + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2
            + (3.0 * p1[0] - p0[0] - 3.0 * p2[0] + p3[0]) * t3
        )
        y = 0.5 * (
            2.0 * p1[1]
            + (p2[1] - p0[1]) * t
            + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2
            + (3.0 * p1[1] - p0[1] - 3.0 * p2[1] + p3[1]) * t3
        )
        out.append((x, y))


def smooth_closed(pts: list[tuple[float, float]], step: float = CURVE_STEP) -> list[tuple[float, float]]:
    n = len(pts)
    if n < 3:
        return list(pts)
    out: list[tuple[float, float]] = []
    for i in range(n):
        _curve_piece(pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n], step, out)
    return out


def smooth_open(pts: list[tuple[float, float]], step: float = CURVE_STEP) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for i in range(1, len(pts) - 2):
        _curve_piece(pts[i - 1], pts[i], pts[i + 1], pts[i + 2], step, out)
    return out


def build_footprint(
    zone_data: dict[str, Any],
    seams_map: dict[str, dict[str, Any]],
    problems: list[str],
) -> list[tuple[float, float]]:
    zid = str(zone_data.get("id", ""))
    ox, oy = (float(zone_data["origin"][0]), float(zone_data["origin"][1]))
    runs: list[dict[str, Any]] = []
    for entry in zone_data.get("footprint", []):
        if isinstance(entry, dict):
            sid = str(entry.get("seam", ""))
            if sid not in seams_map:
                problems.append(f"zone {zid}: unknown seam '{sid}'")
                continue
            cut = seams_map[sid]
            if cut.get("a") != zid and cut.get("b") != zid:
                problems.append(f"zone {zid} uses seam {sid} of {cut.get('a')}/{cut.get('b')}")
            runs.append({"seam": True, "pts": [(float(p[0]), float(p[1])) for p in cut["pts"]]})
        elif isinstance(entry, list) and len(entry) >= 2:
            v = (float(entry[0]) + ox, float(entry[1]) + oy)
            if not runs or runs[-1]["seam"]:
                runs.append({"seam": False, "pts": []})
            runs[-1]["pts"].append(v)

    for i, r in enumerate(runs):
        if not r["seam"]:
            continue
        pts = r["pts"]
        before = None
        if i > 0:
            before = runs[i - 1]["pts"][-1]
        elif len(runs) > 1:
            before = runs[-1]["pts"][-1]
        if before is not None and dist(before, pts[-1]) < dist(before, pts[0]):
            r["pts"] = list(reversed(pts))

    plan = [p for r in runs for p in r["pts"]]
    if len(plan) < 3:
        sx, sy = (float(zone_data["size"][0]), float(zone_data["size"][1]))
        return [(ox, oy), (ox + sx, oy), (ox + sx, oy + sy), (ox, oy + sy)]

    if not zone_data.get("curve", False):
        return plan
    if not any(r["seam"] for r in runs):
        return smooth_closed(plan)

    out: list[tuple[float, float]] = []
    count = len(runs)
    for i in range(count):
        pts = runs[i]["pts"]
        if runs[i]["seam"]:
            out.extend(pts)
            continue
        prev_pts = runs[(i - 1) % count]["pts"]
        next_pts = runs[(i + 1) % count]["pts"]
        chain = [
            prev_pts[max(0, len(prev_pts) - 2)],
            prev_pts[-1],
            *pts,
            next_pts[0],
            next_pts[min(1, len(next_pts) - 1)],
        ]
        cpts = smooth_open(chain)
        if cpts:
            cpts.pop(0)
        out.extend(cpts)
    return out


def bbox(poly: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return (min(xs), min(ys), max(xs), max(ys))


def point_in_polygon(pt: tuple[float, float], poly: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-18) + x1):
            inside = not inside
    return inside


def point_to_segment_dist(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    if l2 <= 1e-12:
        return dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return dist(p, (a[0] + t * dx, a[1] + t * dy))


def edge_distance(pt: tuple[float, float], poly: list[tuple[float, float]]) -> float:
    if len(poly) >= 3 and point_in_polygon(pt, poly):
        return 0.0
    return min(point_to_segment_dist(pt, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def rim_distance(pt: tuple[float, float], poly: list[tuple[float, float]]) -> float:
    return min(point_to_segment_dist(pt, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def polyline_to_poly_distance(line: list[tuple[float, float]], poly: list[tuple[float, float]]) -> float:
    if not line or not poly:
        return float("inf")
    return max(rim_distance(p, poly) for p in line)


def signed_area(poly: list[tuple[float, float]]) -> float:
    s = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return 0.5 * s


def _dedupe_poly(poly: list[tuple[float, float]]) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for p in poly:
        if not out or dist(out[-1], p) > 1e-6:
            out.append(p)
    if len(out) > 1 and dist(out[0], out[-1]) <= 1e-6:
        out.pop()
    return out


def _cross(o: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def find_duplicate_vertices(poly: list[tuple[float, float]]) -> int:
    seen: set[tuple[int, int]] = set()
    dups = 0
    for x, y in poly:
        k = (round(x * 1_000_000), round(y * 1_000_000))
        if k in seen:
            dups += 1
        else:
            seen.add(k)
    return dups


def _segments_intersect(
    a1: tuple[float, float],
    a2: tuple[float, float],
    b1: tuple[float, float],
    b2: tuple[float, float],
) -> bool:
    d1 = _cross(b1, b2, a1)
    d2 = _cross(b1, b2, a2)
    d3 = _cross(a1, a2, b1)
    d4 = _cross(a1, a2, b2)
    if ((d1 > 1e-9 and d2 < -1e-9) or (d1 < -1e-9 and d2 > 1e-9)) and (
        (d3 > 1e-9 and d4 < -1e-9) or (d3 < -1e-9 and d4 > 1e-9)
    ):
        return True
    # Collinear overlap check
    if abs(d1) <= 1e-9 and abs(d2) <= 1e-9 and abs(d3) <= 1e-9 and abs(d4) <= 1e-9:
        if (
            max(a1[0], a2[0]) >= min(b1[0], b2[0]) - 1e-9
            and max(b1[0], b2[0]) >= min(a1[0], a2[0]) - 1e-9
            and max(a1[1], a2[1]) >= min(b1[1], b2[1]) - 1e-9
            and max(b1[1], b2[1]) >= min(a1[1], a2[1]) - 1e-9
        ):
            return True
    return False


def count_self_intersections(poly: list[tuple[float, float]]) -> int:
    """Fast sweep-line self-intersection count for non-adjacent polygon edges."""
    n = len(poly)
    if n < 4:
        return 0
    segs: list[tuple[float, float, float, float, int, tuple[float, float], tuple[float, float]]] = []
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        segs.append((min(a[0], b[0]), max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1]), i, a, b))
    segs.sort(key=lambda s: s[0])
    hits = 0
    for idx_a in range(n):
        ax0, ax1, ay0, ay1, i, a1, a2 = segs[idx_a]
        for idx_b in range(idx_a + 1, n):
            bx0, bx1, by0, by1, j, b1, b2 = segs[idx_b]
            if bx0 > ax1 + 1e-9:
                break
            if by1 < ay0 - 1e-9 or ay1 < by0 - 1e-9:
                continue
            d_ij = abs(i - j)
            if d_ij <= 1 or d_ij == n - 1:
                continue
            if _segments_intersect(a1, a2, b1, b2):
                hits += 1
    return hits


def triangulate(
    poly_in: list[tuple[float, float]],
    strict: bool = True,
) -> list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]]:
    """Fast reflex-indexed ear-clipping triangulation for simple polygons."""
    pts = _dedupe_poly(poly_in)
    n = len(pts)
    if n < 3:
        return []
    if signed_area(pts) < 0:
        pts = list(reversed(pts))

    prev_idx = [(i - 1) % n for i in range(n)]
    next_idx = [(i + 1) % n for i in range(n)]
    alive = [True] * n
    reflex: set[int] = set()

    def is_convex(i: int) -> bool:
        return _cross(pts[prev_idx[i]], pts[i], pts[next_idx[i]]) > 1e-9

    for i in range(n):
        if not is_convex(i):
            reflex.add(i)

    tris: list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]] = []
    remaining = n
    cur = 0
    steps_since_ear = 0

    while remaining > 3:
        if not alive[cur]:
            cur = next_idx[cur]
            continue
        i0, i1, i2 = prev_idx[cur], cur, next_idx[cur]
        a, b, c = pts[i0], pts[i1], pts[i2]
        if i1 not in reflex and _cross(a, b, c) > 1e-9:
            minx = min(a[0], b[0], c[0]) - 1e-9
            maxx = max(a[0], b[0], c[0]) + 1e-9
            miny = min(a[1], b[1], c[1]) - 1e-9
            maxy = max(a[1], b[1], c[1]) + 1e-9
            has_inside = False
            for rj in reflex:
                if rj == i0 or rj == i1 or rj == i2:
                    continue
                px, py = pts[rj]
                if px < minx or px > maxx or py < miny or py > maxy:
                    continue
                if (_cross(a, b, (px, py)) >= -1e-9) and (_cross(b, c, (px, py)) >= -1e-9) and (_cross(c, a, (px, py)) >= -1e-9):
                    has_inside = True
                    break
            if not has_inside:
                tris.append((a, b, c))
                alive[i1] = False
                reflex.discard(i1)
                next_idx[i0] = i2
                prev_idx[i2] = i0
                remaining -= 1
                if is_convex(i0):
                    reflex.discard(i0)
                else:
                    reflex.add(i0)
                if is_convex(i2):
                    reflex.discard(i2)
                else:
                    reflex.add(i2)
                cur = i2
                steps_since_ear = 0
                continue
        steps_since_ear += 1
        if steps_since_ear >= remaining:
            if strict:
                raise ValueError(f"ear-clipping stalled with {remaining} vertices left (self-intersecting or degenerate polygon)")
            return tris
        cur = next_idx[cur]

    last_pts = [pts[i] for i in range(n) if alive[i]]
    if len(last_pts) == 3:
        tris.append((last_pts[0], last_pts[1], last_pts[2]))
    return tris


def _clip_poly_halfplane(
    subject: list[tuple[float, float]],
    a: tuple[float, float],
    b: tuple[float, float],
) -> list[tuple[float, float]]:
    if not subject:
        return []
    out: list[tuple[float, float]] = []
    n = len(subject)
    for i in range(n):
        cur = subject[i]
        prev = subject[i - 1]
        cur_in = _cross(a, b, cur) >= -1e-9
        prev_in = _cross(a, b, prev) >= -1e-9
        if cur_in != prev_in:
            x1, y1 = prev
            x2, y2 = cur
            x3, y3 = a
            x4, y4 = b
            denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
            if abs(denom) > 1e-12:
                t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom
                out.append((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
        if cur_in:
            out.append(cur)
    return out


def polygon_intersection_area(
    poly_a: list[tuple[float, float]],
    poly_b: list[tuple[float, float]],
    cached_a: tuple[tuple[float, float, float, float], list[tuple[tuple[tuple[float, float], tuple[float, float], tuple[float, float]], tuple[float, float, float, float]]]] | None = None,
    cached_b: tuple[tuple[float, float, float, float], list[tuple[tuple[tuple[float, float], tuple[float, float], tuple[float, float]], tuple[float, float, float, float]]]] | None = None,
) -> float:
    """Exact intersection area between two simple (possibly concave) polygons."""
    ba_root = cached_a[0] if cached_a else bbox(poly_a)
    bb_root = cached_b[0] if cached_b else bbox(poly_b)
    ix0, iy0 = max(ba_root[0], bb_root[0]), max(ba_root[1], bb_root[1])
    ix1, iy1 = min(ba_root[2], bb_root[2]), min(ba_root[3], bb_root[3])
    if ix1 <= ix0 or iy1 <= iy0:
        return 0.0

    ta_all = cached_a[1] if cached_a else [(t, bbox(list(t))) for t in triangulate(poly_a)]
    tb_all = cached_b[1] if cached_b else [(t, bbox(list(t))) for t in triangulate(poly_b)]
    fa = [(ta, b) for ta, b in ta_all if b[2] > ix0 and b[0] < ix1 and b[3] > iy0 and b[1] < iy1]
    fb = [(tb, b) for tb, b in tb_all if b[2] > ix0 and b[0] < ix1 and b[3] > iy0 and b[1] < iy1]
    if not fa or not fb:
        return 0.0

    cell = 16.0
    grid: dict[tuple[int, int], list[int]] = {}
    for idx, (_tb, bb) in enumerate(fb):
        gx0, gy0 = int(math.floor(bb[0] / cell)), int(math.floor(bb[1] / cell))
        gx1, gy1 = int(math.floor(bb[2] / cell)), int(math.floor(bb[3] / cell))
        for gy in range(gy0, gy1 + 1):
            for gx in range(gx0, gx1 + 1):
                grid.setdefault((gx, gy), []).append(idx)

    total = 0.0
    for ta, ba in fa:
        gx0, gy0 = int(math.floor(ba[0] / cell)), int(math.floor(ba[1] / cell))
        gx1, gy1 = int(math.floor(ba[2] / cell)), int(math.floor(ba[3] / cell))
        cand: set[int] = set()
        for gy in range(gy0, gy1 + 1):
            for gx in range(gx0, gx1 + 1):
                cand.update(grid.get((gx, gy), ()))
        for idx in cand:
            tb, bb = fb[idx]
            if ba[2] <= bb[0] or bb[2] <= ba[0] or ba[3] <= bb[1] or bb[3] <= ba[1]:
                continue
            clipped = list(ta)
            for k in range(3):
                clipped = _clip_poly_halfplane(clipped, tb[k], tb[(k + 1) % 3])
                if len(clipped) < 3:
                    break
            if len(clipped) >= 3:
                total += abs(signed_area(clipped))
    return total


def size_class_for(size: list[int]) -> str:
    edge = max(int(size[0]), int(size[1]))
    for key in ("S", "M", "L", "XL"):
        lo, hi = SIZE_CLASSES[key]
        if lo <= edge <= hi:
            return key
    return ""


def validate_atlas(continent_filter: str | None = None, verbose: bool = False) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []

    atlas_path = WORLD_DIR / "atlas.json"
    moods_path = WORLD_DIR / "moods.json"
    trees_path = DATA_DIR / "trees.json"
    grass_path = DATA_DIR / "grass_tiles.json"

    for p in (atlas_path, moods_path, trees_path, grass_path):
        if not p.exists():
            problems.append(f"missing required file: {p.relative_to(ROOT)}")
            return problems, notes

    atlas_data = load_json(atlas_path)
    moods_data = load_json(moods_path).get("moods", {})
    trees_data = load_json(trees_path)
    grass_data = load_json(grass_path)

    seen_continents: set[str] = set()
    seen_zones: set[str] = set()
    seen_thresholds: set[str] = set()
    zones_by_id: dict[str, dict[str, Any]] = {}
    footprints_by_id: dict[str, list[tuple[float, float]]] = {}
    tri_cache: dict[str, tuple[tuple[float, float, float, float], list[tuple[Any, tuple[float, float, float, float]]]]] = {}
    zones_by_continent: dict[str, list[str]] = {}
    thresholds_by_zone: dict[str, list[dict[str, Any]]] = {}

    continents_raw = atlas_data.get("continents", [])
    if not continents_raw:
        problems.append("atlas.json has no continents")
        return problems, notes

    for centry in continents_raw:
        cid = str(centry.get("id", ""))
        if continent_filter and cid != continent_filter:
            continue
        if not cid:
            problems.append("atlas.json: continent without id")
            continue
        if cid in seen_continents:
            problems.append(f"atlas.json: duplicate continent id '{cid}'")
            continue
        seen_continents.add(cid)

        chart = centry.get("chart", [])
        if not (isinstance(chart, list) and len(chart) >= 4):
            problems.append(f"continent {cid}: invalid chart rect")
        else:
            cx, cy, cw, ch = (float(chart[0]), float(chart[1]), float(chart[2]), float(chart[3]))
            if cx < 0 or cy < 0 or cw <= 0 or ch <= 0 or cx + cw > 1.001 or cy + ch > 1.001:
                problems.append(f"continent {cid}: chart {chart} outside [0..1]")

        cfile = DATA_DIR / str(centry.get("file", ""))
        if not cfile.exists():
            problems.append(f"continent {cid}: missing file {centry.get('file')}")
            continue
        cdata = load_json(cfile)
        csize = cdata.get("size", [0, 0])
        if int(csize[0]) <= 0 or int(csize[1]) <= 0:
            problems.append(f"continent {cid}: invalid size {csize}")

        regions = cdata.get("regions", [])
        region_ids = {str(r.get("id", "")) for r in regions if isinstance(r, dict)}
        if cid == "main":
            if region_ids != ALTMARK_REGIONS:
                missing_reg = ALTMARK_REGIONS - region_ids
                extra_reg = region_ids - ALTMARK_REGIONS
                if missing_reg:
                    problems.append(f"ALTMARK missing regions: {sorted(missing_reg)}")
                if extra_reg:
                    problems.append(f"ALTMARK unexpected regions: {sorted(extra_reg)}")
            ocean = cdata.get("ocean", {})
            if isinstance(ocean, dict) and ocean.get("void_ring", False):
                problems.append("ALTMARK must not have an outer void_ring around the ocean")
            rift = cdata.get("great_rift")
            if not isinstance(rift, dict) or not rift:
                problems.append("ALTMARK missing great_rift definition")
            else:
                if rift.get("region") != "leerenbluehen":
                    problems.append(f"ALTMARK great_rift must be in leerenbluehen, got {rift.get('region')}")
                rpos = rift.get("epicenter", rift.get("pos", rift.get("center")))
                if not (isinstance(rpos, list) and len(rpos) >= 2):
                    problems.append("ALTMARK great_rift missing epicenter/pos")

        seams_map: dict[str, dict[str, Any]] = {}
        for s in cdata.get("seams", []):
            sid = str(s.get("id", ""))
            pts = s.get("pts", [])
            if not sid or len(pts) < 2:
                problems.append(f"continent {cid}: seam without id or <2 pts")
                continue
            if sid in seams_map:
                problems.append(f"continent {cid}: duplicate seam '{sid}'")
                continue
            seams_map[sid] = s

        zones_by_continent[cid] = []
        for zref in cdata.get("zones", []):
            zid = str(zref)
            zpath = WORLD_DIR / "zones" / zid / "zone.json"
            if not zpath.exists():
                problems.append(f"continent {cid}: missing zone file {zpath.relative_to(ROOT)}")
                continue
            zdata = load_json(zpath)
            if str(zdata.get("id", "")) != zid:
                problems.append(f"zone {zid}: id mismatch '{zdata.get('id')}'")
            if zid in seen_zones:
                problems.append(f"zone {zid} duplicated")
                continue
            seen_zones.add(zid)
            zones_by_id[zid] = zdata
            zones_by_continent[cid].append(zid)
            thresholds_by_zone[zid] = []

            if str(zdata.get("continent", "")) != cid:
                problems.append(f"zone {zid}: continent '{zdata.get('continent')}' != '{cid}'")
            reg = str(zdata.get("region", ""))
            if region_ids and reg not in region_ids:
                problems.append(f"zone {zid}: unknown region '{reg}'")
            if str(zdata.get("kind", "")) not in ZONE_KINDS:
                problems.append(f"zone {zid}: invalid kind '{zdata.get('kind')}'")
            if str(zdata.get("danger", "")) not in DANGERS:
                problems.append(f"zone {zid}: invalid danger '{zdata.get('danger')}'")
            zsize = zdata.get("size", [0, 0])
            fitted = size_class_for(zsize)
            if not fitted or fitted != zdata.get("size_class"):
                problems.append(
                    f"zone {zid}: size {zsize} does not fit class '{zdata.get('size_class')}' (fits '{fitted}')"
                )

            mood_id = str(zdata.get("mood", ""))
            if mood_id and mood_id not in moods_data:
                problems.append(f"zone {zid}: unknown mood '{mood_id}'")

            for bidx, b in enumerate(zdata.get("borders", [])):
                if isinstance(b, dict):
                    for m in b.get("mix", []):
                        sp = str(m.get("species", ""))
                        if sp not in trees_data:
                            problems.append(f"zone {zid}: border[{bidx}] unknown tree species '{sp}'")

            raw_fp = [p for p in zdata.get("footprint", []) if isinstance(p, list)]
            if len(raw_fp) >= 2 and raw_fp[0] == raw_fp[-1]:
                problems.append(f"zone {zid}: footprint repeats closing vertex")

            fp = build_footprint(zdata, seams_map, problems)
            footprints_by_id[zid] = fp
            fp_bbox = bbox(fp)
            x0, y0, x1, y1 = fp_bbox
            ox, oy = float(zdata["origin"][0]), float(zdata["origin"][1])
            sx, sy = float(zsize[0]), float(zsize[1])
            if x0 < ox - 0.01 or y0 < oy - 0.01 or x1 > ox + sx + 0.01 or y1 > oy + sy + 0.01:
                problems.append(f"zone {zid}: footprint bbox ({x0:.1f},{y0:.1f}..{x1:.1f},{y1:.1f}) exceeds origin+size ({ox},{oy}..{ox+sx},{oy+sy})")
            if x0 < 0 or y0 < 0 or x1 > float(csize[0]) or y1 > float(csize[1]):
                problems.append(f"zone {zid}: reaches outside continent {cid}")

            s_area = signed_area(fp)
            if s_area <= 0:
                problems.append(f"zone {zid}: footprint winding is not clockwise (signed_area={s_area:.2f} <= 0 in Y-down)")

            dups = find_duplicate_vertices(fp)
            self_hits = count_self_intersections(fp)
            is_lab_fixture = cid == "lab"
            if dups > 0:
                msg = f"zone {zid}: curved footprint has {dups} duplicate vertices (split wrap-around run?)"
                if is_lab_fixture:
                    notes.append(f"[WARN] (lab fixture) {msg}")
                else:
                    problems.append(msg)
            if self_hits > 0:
                msg = f"zone {zid}: curved footprint has {self_hits} self-intersections"
                if is_lab_fixture:
                    notes.append(f"[WARN] (lab fixture) {msg}")
                else:
                    problems.append(msg)

            try:
                tris = triangulate(fp, strict=(not is_lab_fixture))
                tri_area = sum(abs(signed_area(list(t))) for t in tris)
                if abs(tri_area - abs(s_area)) > 0.5:
                    msg = f"zone {zid}: triangulation area mismatch (poly={abs(s_area):.2f} vs tri={tri_area:.2f})"
                    if is_lab_fixture:
                        notes.append(f"[WARN] (lab fixture) {msg}")
                    else:
                        problems.append(msg)
                tri_cache[zid] = (fp_bbox, [(t, bbox(list(t))) for t in tris])
            except ValueError as exc:
                problems.append(f"zone {zid}: {exc}")

            place_polys_by_id: dict[str, list[tuple[float, float]]] = {}
            for place in zdata.get("places", []):
                pid = str(place.get("id", ""))
                ppoly_raw = place.get("poly", [])
                if len(ppoly_raw) < 3:
                    problems.append(f"zone {zid}: place {pid} has <3 pts")
                    continue
                if ppoly_raw[0] == ppoly_raw[-1]:
                    problems.append(f"zone {zid}: place {pid} repeats closing vertex")
                ppoly = [(float(pt[0]) + ox, float(pt[1]) + oy) for pt in ppoly_raw]
                place_polys_by_id[pid] = ppoly
                px0, py0, px1, py1 = bbox(ppoly)
                center = ((px0 + px1) * 0.5, (py0 + py1) * 0.5)
                if not point_in_polygon(center, fp):
                    problems.append(f"zone {zid}: place {pid} center outside footprint")
                for vidx, pt in enumerate(ppoly):
                    if not point_in_polygon(pt, fp):
                        problems.append(f"zone {zid}: place {pid} vertex {vidx} ({pt[0]-ox},{pt[1]-oy}) outside footprint")
                pmood = str(place.get("mood", ""))
                if pmood and pmood not in moods_data:
                    problems.append(f"zone {zid}: place {pid} unknown mood '{pmood}'")

            for lm in zdata.get("landmarks", []):
                lpos = (float(lm["pos"][0]) + ox, float(lm["pos"][1]) + oy)
                if not point_in_polygon(lpos, fp):
                    problems.append(f"zone {zid}: landmark {lm.get('id')} outside footprint")

            # rocky[].poly & cliffs.highland_polys containment inside footprint (<= 0.5 tiles tolerance)
            for ridx, rk in enumerate(zdata.get("rocky", [])):
                if isinstance(rk, dict):
                    for vidx, pt in enumerate(rk.get("poly", [])):
                        wpt = (float(pt[0]) + ox, float(pt[1]) + oy)
                        if not point_in_polygon(wpt, fp) and edge_distance(wpt, fp) > 0.5:
                            problems.append(f"zone {zid}: rocky[{ridx}][{vidx}] ({pt[0]},{pt[1]}) outside footprint")
            cliffs_blk = zdata.get("cliffs", {})
            if isinstance(cliffs_blk, dict):
                for hidx, hpoly in enumerate(cliffs_blk.get("highland_polys", [])):
                    for vidx, pt in enumerate(hpoly):
                        wpt = (float(pt[0]) + ox, float(pt[1]) + oy)
                        if not point_in_polygon(wpt, fp) and edge_distance(wpt, fp) > 0.5:
                            problems.append(f"zone {zid}: cliffs.highland_polys[{hidx}][{vidx}] ({pt[0]},{pt[1]}) outside footprint")

            # veil_threads[].place must match a places[].poly containing that thread's tile
            for vt in zdata.get("veil_threads", []):
                if isinstance(vt, dict) and isinstance(vt.get("tile"), list) and len(vt["tile"]) >= 2:
                    vtid = str(vt.get("id", ""))
                    vplace = str(vt.get("place", ""))
                    vpt = (float(vt["tile"][0]) + ox, float(vt["tile"][1]) + oy)
                    if vplace not in place_polys_by_id:
                        problems.append(f"zone {zid}: veil_thread {vtid} references unknown place '{vplace}'")
                    elif not point_in_polygon(vpt, place_polys_by_id[vplace]):
                        problems.append(f"zone {zid}: veil_thread {vtid} ({vt['tile'][0]},{vt['tile'][1]}) outside declared place '{vplace}'")

            # Check downhill water inside zone brooks
            water_blk = zdata.get("water", {})
            if isinstance(water_blk, dict):
                for brook in water_blk.get("brooks", []):
                    bid = str(brook.get("id", ""))
                    elevs = brook.get("elevations", [])
                    for idx in range(len(elevs) - 1):
                        if float(elevs[idx + 1]) > float(elevs[idx]) + 1e-6:
                            problems.append(f"zone {zid}: brook {bid} flows uphill at index {idx} ({elevs[idx]} -> {elevs[idx+1]})")
                    if elevs and float(elevs[-1]) > 0.05 and zdata.get("kind") == "coast":
                        problems.append(f"zone {zid}: coast brook {bid} does not reach sea level (ends at {elevs[-1]})")

        # Zone overlap checks (cached triangles + bbox pre-filter)
        czones = zones_by_continent[cid]
        for i in range(len(czones)):
            for j in range(i + 1, len(czones)):
                za, zb = czones[i], czones[j]
                if za not in tri_cache or zb not in tri_cache:
                    continue
                ca_entry, cb_entry = tri_cache[za], tri_cache[zb]
                ba, bb = ca_entry[0], cb_entry[0]
                if ba[2] <= bb[0] or bb[2] <= ba[0] or ba[3] <= bb[1] or bb[3] <= ba[1]:
                    continue
                area = polygon_intersection_area(footprints_by_id[za], footprints_by_id[zb], ca_entry, cb_entry)
                if area > 0.5:
                    problems.append(f"continent {cid}: zones {za} and {zb} overlap ({area:.2f} tiles)")

        # Thresholds
        trel = str(cdata.get("thresholds", ""))
        if trel:
            tpath = DATA_DIR / trel
            if not tpath.exists():
                problems.append(f"continent {cid}: missing thresholds file {trel}")
            else:
                tdata = load_json(tpath)
                for t in tdata.get("thresholds", []):
                    tid = str(t.get("id", ""))
                    if not tid:
                        problems.append(f"continent {cid}: threshold without id")
                        continue
                    if tid in seen_thresholds:
                        problems.append(f"threshold {tid} duplicated")
                        continue
                    seen_thresholds.add(tid)
                    za_id, zb_id = str(t.get("a", "")), str(t.get("b", ""))
                    if za_id not in zones_by_id or zb_id not in zones_by_id:
                        problems.append(f"threshold {tid}: unknown zones {za_id}/{zb_id}")
                        continue
                    if za_id == zb_id:
                        problems.append(f"threshold {tid}: joins {za_id} with itself")
                        continue
                    kind = str(t.get("kind", "path"))
                    if kind not in SEAMLESS_KINDS and kind not in HARD_KINDS:
                        problems.append(f"threshold {tid}: unknown kind '{kind}'")
                    if kind != "ship" and zones_by_id[za_id]["continent"] != zones_by_id[zb_id]["continent"]:
                        problems.append(f"threshold {tid}: cross-continent must be ship")

                    line = [(float(p[0]), float(p[1])) for p in t.get("line", [])]
                    sid = str(t.get("seam", ""))
                    if sid:
                        if sid not in seams_map:
                            problems.append(f"threshold {tid}: unknown seam '{sid}'")
                        else:
                            cut = seams_map[sid]
                            if not ((cut["a"] == za_id and cut["b"] == zb_id) or (cut["a"] == zb_id and cut["b"] == za_id)):
                                problems.append(f"threshold {tid}: seam {sid} belongs to {cut['a']}/{cut['b']}")
                            span = t.get("span", [0.0, 1.0])
                            line = sub_polyline([(float(p[0]), float(p[1])) for p in cut["pts"]], float(span[0]), float(span[1]))

                    if kind in SEAMLESS_KINDS:
                        if len(line) < 2 or dist(line[0], line[-1]) < 1.0:
                            problems.append(f"threshold {tid}: seamless line too short")
                        else:
                            mid = point_along(line, 0.5)
                            for side_id in (za_id, zb_id):
                                fp_side = footprints_by_id[side_id]
                                ed = edge_distance(mid, fp_side)
                                snap = polyline_to_poly_distance(line, fp_side)
                                if ed > LINE_REACH:
                                    problems.append(f"threshold {tid}: midpoint {ed:.2f} > LINE_REACH ({LINE_REACH}) from {side_id}")
                                if snap > LINE_SNAP:
                                    problems.append(f"threshold {tid}: line {snap:.2f} > LINE_SNAP ({LINE_SNAP}) from {side_id}")

                    thresholds_by_zone[za_id].append(t)
                    thresholds_by_zone[zb_id].append(t)

                # Check zone blockers distance to their threshold sub_polyline (<= 2.5 tiles)
                th_lines: dict[str, list[tuple[float, float]]] = {}
                for t in tdata.get("thresholds", []):
                    tid = str(t.get("id", ""))
                    if not tid:
                        continue
                    tline = [(float(p[0]), float(p[1])) for p in t.get("line", [])]
                    sid = str(t.get("seam", ""))
                    if sid and sid in seams_map:
                        span = t.get("span", [0.0, 1.0])
                        tline = sub_polyline([(float(p[0]), float(p[1])) for p in seams_map[sid]["pts"]], float(span[0]), float(span[1]))
                    th_lines[tid] = tline
                for zid in czones:
                    zd = zones_by_id[zid]
                    zox, zoy = float(zd["origin"][0]), float(zd["origin"][1])
                    for bl in zd.get("blockers", []):
                        tid = str(bl.get("threshold_id", ""))
                        btile = bl.get("tile")
                        if not tid or tid not in th_lines:
                            problems.append(f"zone {zid}: blocker references unknown threshold '{tid}'")
                        elif isinstance(btile, list) and len(btile) >= 2 and len(th_lines[tid]) >= 2:
                            bpt = (float(btile[0]) + zox, float(btile[1]) + zoy)
                            tline = th_lines[tid]
                            d_line = min(point_to_segment_dist(bpt, tline[k], tline[k + 1]) for k in range(len(tline) - 1))
                            if d_line > 2.5:
                                problems.append(f"zone {zid}: blocker '{tid}' is {d_line:.2f} > 2.5 tiles from threshold line")

        # Coastline containment & islets validation (when coastline is authored)
        raw_coast = cdata.get("coastline", [])
        if isinstance(raw_coast, list) and len(raw_coast) >= 3:
            coast_raw = [(float(p[0]), float(p[1])) for p in raw_coast]
            coast_polys = [coast_raw]
            if len(coast_raw) < 80:
                coast_polys.append(smooth_closed(coast_raw, 4.0))
            for zid in czones:
                fp_z = footprints_by_id[zid]
                zd = zones_by_id[zid]
                zox, zoy = float(zd["origin"][0]), float(zd["origin"][1])
                if zid != "windkap":
                    for vidx, pt in enumerate(fp_z):
                        if any(not point_in_polygon(pt, cp) for cp in coast_polys):
                            problems.append(f"continent {cid}: zone {zid} footprint vertex {vidx} ({pt[0]:.1f},{pt[1]:.1f}) outside coastline")
                            break
                # Land POIs inside coastline
                land_pois: list[tuple[str, tuple[float, float]]] = []
                for pl in zd.get("places", []):
                    pid = str(pl.get("id", ""))
                    for vi, pt in enumerate(pl.get("poly", [])):
                        land_pois.append((f"place.{pid}[{vi}]", (float(pt[0]) + zox, float(pt[1]) + zoy)))
                for lm in zd.get("landmarks", []):
                    land_pois.append((f"landmark.{lm.get('id')}", (float(lm["pos"][0]) + zox, float(lm["pos"][1]) + zoy)))
                if not bool(zd.get("placeholder", False)):
                    for k in ("camp_tile",):
                        if isinstance(zd.get(k), list) and len(zd[k]) >= 2:
                            land_pois.append((k, (float(zd[k][0]) + zox, float(zd[k][1]) + zoy)))
                    if isinstance(zd.get("spawn"), dict) and isinstance(zd["spawn"].get("camp_tile"), list):
                        sp_t = zd["spawn"]["camp_tile"]
                        land_pois.append(("spawn.camp_tile", (float(sp_t[0]) + zox, float(sp_t[1]) + zoy)))
                    if isinstance(zd.get("camp"), dict):
                        camp_d = zd["camp"]
                        for k in ("tile", "campfire_tile", "seat_tile"):
                            if isinstance(camp_d.get(k), list) and len(camp_d[k]) >= 2:
                                land_pois.append((f"camp.{k}", (float(camp_d[k][0]) + zox, float(camp_d[k][1]) + zoy)))
                        if isinstance(camp_d.get("chest"), dict) and isinstance(camp_d["chest"].get("tile"), list):
                            ct = camp_d["chest"]["tile"]
                            land_pois.append(("camp.chest", (float(ct[0]) + zox, float(ct[1]) + zoy)))
                        for it in camp_d.get("starter_items", []):
                            if isinstance(it, dict) and isinstance(it.get("tile"), list):
                                st = it["tile"]
                                land_pois.append((f"camp.starter.{it.get('id')}", (float(st[0]) + zox, float(st[1]) + zoy)))
                    if isinstance(zd.get("ruin"), dict):
                        rd = zd["ruin"]
                        for k in ("tile", "lighthouse_tile"):
                            if isinstance(rd.get(k), list) and len(rd[k]) >= 2:
                                land_pois.append((f"ruin.{k}", (float(rd[k][0]) + zox, float(rd[k][1]) + zoy)))
                        if isinstance(rd.get("tablet"), dict) and isinstance(rd["tablet"].get("tile"), list):
                            tt = rd["tablet"]["tile"]
                            land_pois.append(("ruin.tablet", (float(tt[0]) + zox, float(tt[1]) + zoy)))
                    for grp, key in (("waystone", "waystones"), ("vista", "vistas"), ("chest", "chests"), ("puzzle", "puzzles"), ("veil_thread", "veil_threads"), ("blocker", "blockers")):
                        for it in zd.get(key, []):
                            if isinstance(it, dict) and isinstance(it.get("tile"), list) and len(it["tile"]) >= 2:
                                iid = it.get("id", it.get("threshold_id", ""))
                                land_pois.append((f"{grp}.{iid}", (float(it["tile"][0]) + zox, float(it["tile"][1]) + zoy)))
                for plabel, ppt in land_pois:
                    if any(not point_in_polygon(ppt, cp) for cp in coast_polys):
                        problems.append(f"continent {cid}: zone {zid} land POI {plabel} ({ppt[0]:.1f},{ppt[1]:.1f}) outside coastline")

            for isl in cdata.get("islets", []):
                if not isinstance(isl, dict):
                    continue
                iid = str(isl.get("id", ""))
                ipoly = [(float(p[0]), float(p[1])) for p in isl.get("poly", [])]
                if len(ipoly) < 3:
                    problems.append(f"continent {cid}: islet {iid} has <3 pts")
                    continue
                if count_self_intersections(ipoly) > 0:
                    problems.append(f"continent {cid}: islet {iid} has self-intersections")
                for vi, ipt in enumerate(ipoly):
                    if any(point_in_polygon(ipt, cp) for cp in coast_polys):
                        problems.append(f"continent {cid}: islet {iid} vertex {vi} inside coastline")
                        break
                for zid in czones:
                    if zid in tri_cache and polygon_intersection_area(ipoly, footprints_by_id[zid], None, tri_cache[zid]) > 0.5:
                        problems.append(f"continent {cid}: islet {iid} overlaps zone {zid}")

        # Graph reachability (directed when one_way is true)
        if len(czones) >= 2:
            for zid in czones:
                if not thresholds_by_zone[zid]:
                    problems.append(f"continent {cid}: zone {zid} has no threshold")
            start = "windkap" if "windkap" in czones else czones[0]
            visited: set[str] = {start}
            q: deque[str] = deque([start])
            while q:
                cur = q.popleft()
                for t in thresholds_by_zone[cur]:
                    ta, tb = str(t["a"]), str(t["b"])
                    one_way = bool(t.get("one_way", False))
                    if ta == cur:
                        nxt = tb
                    elif tb == cur and not one_way:
                        nxt = ta
                    else:
                        continue
                    if nxt not in visited:
                        visited.add(nxt)
                        q.append(nxt)
            missing = set(czones) - visited
            if missing:
                problems.append(f"continent {cid}: unreachable zones from {start}: {sorted(missing)}")

        # Landscape checks
        lrel = str(cdata.get("landscape", ""))
        if not lrel:
            problems.append(f"continent {cid}: missing landscape path")
        else:
            lpath = DATA_DIR / lrel
            if not lpath.exists():
                problems.append(f"continent {cid}: missing landscape file {lrel}")
            else:
                ldata = load_json(lpath)
                for st in ldata.get("stands", []):
                    if len(st.get("outline", [])) < 3:
                        problems.append(f"landscape {cid}: stand {st.get('id')} has <3 outline pts")
                    for m in st.get("mix", []):
                        sp = str(m.get("species", ""))
                        if sp not in trees_data:
                            problems.append(f"landscape {cid}: stand {st.get('id')} unknown tree species '{sp}'")
                for tr in ldata.get("trees", []):
                    sp = str(tr.get("species", ""))
                    if sp not in trees_data:
                        problems.append(f"landscape {cid}: tree unknown species '{sp}'")
                for w in ldata.get("ways", []):
                    wk = str(w.get("kind", ""))
                    if wk not in WAY_KINDS:
                        problems.append(f"landscape {cid}: invalid way kind '{wk}'")
                    if len(w.get("pts", [])) < 2:
                        problems.append(f"landscape {cid}: way has <2 pts")
                for key, tcfg in ldata.get("turf", {}).items():
                    for k in tcfg.get("kinds", []):
                        if k not in grass_data:
                            problems.append(f"landscape {cid}: turf.{key} unknown grass kind '{k}'")
                for rv in ldata.get("rivers", []):
                    rpts = rv.get("pts", [])
                    for idx in range(len(rpts) - 1):
                        if len(rpts[idx]) >= 3 and len(rpts[idx + 1]) >= 3:
                            if float(rpts[idx + 1][2]) > float(rpts[idx][2]) + 1e-6:
                                problems.append(f"landscape {cid}: river {rv.get('id')} flows uphill at seg {idx} ({rpts[idx][2]} -> {rpts[idx+1][2]})")

        notes.append(f"continent '{cid}' ({cdata.get('name', '')}): {len(czones)} zones, {len(seams_map)} seams")
        if verbose:
            for zid in czones:
                notes.append(f"  - {zid}: {len(thresholds_by_zone[zid])} thresholds, bbox={bbox(footprints_by_id[zid])}")

    return problems, notes


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Shadowspore 2.0 World Atlas.")
    parser.add_argument("--continent", help="Only validate a specific continent id", default=None)
    parser.add_argument("--verbose", action="store_true", help="Print per-zone details")
    args = parser.parse_args()

    problems, notes = validate_atlas(continent_filter=args.continent, verbose=args.verbose)
    for line in notes:
        print(f"[INFO] {line}")
    if problems:
        for p in problems:
            print(f"[FAIL] {p}", file=sys.stderr)
        print(f"ATLAS CHECK FAILED ({len(problems)} problems)", file=sys.stderr)
        return 1
    print("ATLAS CHECK OK (0 problems)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
