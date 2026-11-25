#!/usr/bin/env python3
"""Deterministic geology, coastline, 4-level relief, hydrology & 11-zone builder for ALTMARK & WINDKAP.

Generates:
  1. Baked 2400x1800 continental geospatial fields in data/world/continents/baked/main/:
       - continental_sdf.png       (L8:   128 + signed_dist_tiles * 8; >=128 land/islets/filled lakes, <128 ocean)
       - continental_relief.png    (RGBA: exact tools/bake_relief.py encoding:
                                    R = level 0..3,
                                    G = kind (0 floor, 1 wall face, 2 ramp, 3 stairs, 4 steps) | (style << 4),
                                    B = geom (wall row 0..1 or connector row|depth-1<<2|col<<4|dir<<6),
                                    A = 0 ocean else 200 + biome_idx)
       - continental_field.png     (RGB:  3x blurred masks of lvl>=1, lvl>=2, lvl>=3 for crisp 0.5 ink contours)
       - continental_water.png     (RGB:  R=coverage, G=depth, B=cartographic lake basin depth 0..255)
       - continental_lakes_sdf.png (L8:   128 + to_lake_tiles * 8; <128 inside lake, >=128 outside)
       - continental_areas.png     (RGB:  R=region_id (0 ocean, 1..5), G=zone_id (0 ocean, 1..11, 12 islet),
                                    B=biome_id (0 ocean, 1..7))
  2. World data JSONs:
       - data/world/continents/main.json
       - data/world/thresholds_main.json
       - data/world/landscape/main.json
       - data/world/zones/{windkap,suedkap,glimmrast,erlenfurt,muehlenaue,
                           klippenstieg,hallgrat,kristallgrat,hexenwald_saum,
                           hexenwald_kern,varnholm}/zone.json

Uses ONLY Python 3 stdlib + numpy + PIL (Pillow).
Usage:
  py -3 tools/build_altmark_world.py [--debug-preview <path.png>]
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import pathlib
import sys
import time
from typing import Any

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORLD_DIR = ROOT / "data" / "world"
BAKED_MAIN_DIR = WORLD_DIR / "continents" / "baked" / "main"

W = 2400
H = 1800
SEED = 47

# Exact bake_relief.py constants
FLOOR, FACE, RAMP, STAIRS, STEPS = 0, 1, 2, 3, 4
STYLE_GRASS, STYLE_ROCK, STYLE_MASONRY, STYLE_CRYSTAL, STYLE_VOID, STYLE_SLATE = 0, 1, 2, 3, 4, 5
SOUTH, NORTH, EAST, WEST = 0, 1, 2, 3
DOWN = {SOUTH: (0, 1), NORTH: (0, -1), EAST: (1, 0), WEST: (-1, 0)}
ACROSS = {SOUTH: (1, 0), NORTH: (1, 0), EAST: (0, 1), WEST: (0, 1)}

SIZE_CLASSES = {"S": (96, 160), "M": (160, 256), "L": (256, 384), "XL": (384, 576)}

# Canonical region IDs (R channel in continental_areas.png = 1..5, 0 = ocean)
REGIONS = [
    {"id": "suedwestkueste", "name": "SÜDWESTKÜSTE", "old_name": "KÜSTENSAUM DER ALTEN", "area_id": 1, "biome_idx": 0},
    {"id": "gruenland",      "name": "GRÜNLAND & ZINNEN", "old_name": "DIE MITTLERE MARK", "area_id": 2, "biome_idx": 0},
    {"id": "glaskamm",       "name": "DER GLASKAMM", "old_name": "GLASGRAD", "area_id": 3, "biome_idx": 2},
    {"id": "hexenwald",      "name": "DER HEXENWALD", "old_name": "DORNENFORST", "area_id": 4, "biome_idx": 5},
    {"id": "leerenbluehen",  "name": "DAS LEERENBLÜHEN", "old_name": "DER ÖSTLICHE SAUM", "area_id": 5, "biome_idx": 4},
]
REGION_AREA_ID = {r["id"]: r["area_id"] for r in REGIONS}
REGION_BIOME_IDX = {r["id"]: r["biome_idx"] for r in REGIONS}

# Canonical zone metadata (G channel in continental_areas.png = 1..11, 12 = islet, 0 = ocean)
ZONES_META: list[dict[str, Any]] = [
    {
        "id": "windkap", "znum": 1, "name": "WINDKAP", "old_name": "KAP DER ALTEN WACHE",
        "subtitle": "Wo der Bach ins weite Meer fällt",
        "region": "suedwestkueste", "kind": "coast", "mood": "windkap_coast",
        "danger": "ruhig", "placeholder": False, "seed": 201, "meadow": True,
        "turf": {"accents": 0.08, "kinds": ["tuft", "clump", "clover", "petal", "flower", "bloom"]},
    },
    {
        "id": "klippenstieg", "znum": 2, "name": "DER KLIPPENSTIEG", "old_name": "GRAUER HOCHWEG",
        "subtitle": "Schmaler Pfad über dem tiefen Klippenfjord",
        "region": "suedwestkueste", "kind": "pass", "mood": "glaskamm_stone",
        "danger": "ruhig", "placeholder": True, "seed": 301, "meadow": True,
        "turf": {"accents": 0.06, "kinds": ["tuft", "clump", "stone"]},
    },
    {
        "id": "suedkap", "znum": 3, "name": "SÜDKAP", "old_name": "STURMHAFEN",
        "subtitle": "Südliche Landzunge und alte Molen am offenen Meer",
        "region": "suedwestkueste", "kind": "coast", "mood": "windkap_coast",
        "danger": "ruhig", "placeholder": True, "seed": 302, "meadow": True,
        "turf": {"accents": 0.07, "kinds": ["tuft", "clump", "flower"]},
    },
    {
        "id": "erlenfurt", "znum": 4, "name": "ERLENFURT", "old_name": "FURT AM ERLENBACH",
        "subtitle": "Weites Flusstal zwischen Glaskamm und Südküste",
        "region": "gruenland", "kind": "field", "mood": "meadow_open",
        "danger": "ruhig", "placeholder": True, "seed": 303, "meadow": True,
        "turf": {"accents": 0.07, "kinds": ["tuft", "clump", "clover", "flower"]},
    },
    {
        "id": "hallgrat", "znum": 5, "name": "HALLGRAT AM GLASKAMM", "old_name": "STEINSETZER-HOCH",
        "subtitle": "Terrassierte Steinstadt auf dem westlichen Kap",
        "region": "glaskamm", "kind": "settlement", "mood": "glaskamm_stone",
        "danger": "rau", "placeholder": True, "seed": 304, "meadow": False,
        "turf": {"accents": 0.06, "kinds": ["tuft", "stone"]},
    },
    {
        "id": "kristallgrat", "znum": 6, "name": "DER KRISTALLGRAT", "old_name": "NÖRDLICHES KLANGFELD",
        "subtitle": "Zackiges Quarzgebirge am Nordkap der Altmark",
        "region": "glaskamm", "kind": "wonder", "mood": "glaskamm_stone",
        "danger": "rau", "placeholder": True, "seed": 305, "meadow": False,
        "turf": {"accents": 0.06, "kinds": ["tuft", "stone", "glyph"]},
    },
    {
        "id": "muehlenaue", "znum": 7, "name": "DIE MÜHLENAUE", "old_name": "WEIDENAUE",
        "subtitle": "Flussmündung und Wiesen an der Zinnenbucht",
        "region": "gruenland", "kind": "field", "mood": "meadow_open",
        "danger": "ruhig", "placeholder": True, "seed": 306, "meadow": True,
        "turf": {"accents": 0.07, "kinds": ["tuft", "clump", "clover", "flower"]},
    },
    {
        "id": "glimmrast", "znum": 8, "name": "GLIMMRAST-TAL", "old_name": "VALDRICS LICHTUNG",
        "subtitle": "Das grüne Herz der Altmark zwischen Seen und Tafelhügeln",
        "region": "gruenland", "kind": "home", "mood": "forest_glade",
        "danger": "ruhig", "placeholder": True, "seed": 307, "meadow": True,
        "turf": {"accents": 0.07, "kinds": ["tuft", "clump", "clover", "petal", "flower"]},
    },
    {
        "id": "hexenwald_saum", "znum": 9, "name": "SPORENSAUM", "old_name": "DUNKELSAUM",
        "subtitle": "Moosige Waldmark vor dem tiefen Hexenwald",
        "region": "hexenwald", "kind": "field", "mood": "hexenwald_edge",
        "danger": "rau", "placeholder": True, "seed": 308, "meadow": False,
        "turf": {"accents": 0.09, "kinds": ["fern", "mushroom", "tuft", "clump"]},
    },
    {
        "id": "hexenwald_kern", "znum": 10, "name": "HEXENWALD-KERN", "old_name": "ALTE EIBENMARK",
        "subtitle": "Südöstlicher Schieferkessel um den stillen Westsee",
        "region": "hexenwald", "kind": "wonder", "mood": "forest_deep",
        "danger": "wild", "placeholder": True, "seed": 309, "meadow": False,
        "turf": {"accents": 0.10, "kinds": ["fern", "mushroom", "tuft", "stone"]},
    },
    {
        "id": "varnholm", "znum": 11, "name": "VARNHOLM & LEERENBLÜHEN", "old_name": "HERRSCHAFT VARN",
        "subtitle": "Zerklüftetes Ost-Plateau am Großen Riss",
        "region": "leerenbluehen", "kind": "void", "mood": "leerenbluehen_rift",
        "danger": "wild", "placeholder": True, "seed": 310, "meadow": False,
        "turf": {"accents": 0.08, "kinds": ["tuft", "stone", "glyph"]},
    },
]
ZONE_BY_NUM = {z["znum"]: z for z in ZONES_META}
ZONE_BY_ID = {z["id"]: z for z in ZONES_META}


# =============================================================================
# 1. Vectorized Noise, Distance Transform, Morphology & Connected Components
# =============================================================================

def hash2(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    n = (
        ix.astype(np.int64).astype(np.uint64) * np.uint64(374761393)
        + iy.astype(np.int64).astype(np.uint64) * np.uint64(668265263)
        + np.uint64((seed * 1442695041) & 0xFFFFFFFF)
    )
    n = (n ^ (n >> np.uint64(13))) * np.uint64(1274126177)
    n = n ^ (n >> np.uint64(16))
    return (n & np.uint64(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def vnoise(X: np.ndarray, Y: np.ndarray, seed: int) -> np.ndarray:
    x0 = np.floor(X)
    y0 = np.floor(Y)
    fx = (X - x0).astype(np.float32)
    fy = (Y - y0).astype(np.float32)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a = hash2(x0, y0, seed)
    b = hash2(x0 + 1, y0, seed)
    c = hash2(x0, y0 + 1, seed)
    d = hash2(x0 + 1, y0 + 1, seed)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def fbm(X: np.ndarray, Y: np.ndarray, seed: int, octaves: int = 3) -> np.ndarray:
    v = np.zeros_like(X, dtype=np.float32)
    amp = 1.0
    total = 0.0
    cx, cy = X, Y
    for o in range(octaves):
        v += amp * vnoise(cx, cy, seed + o * 31)
        total += amp
        cx = cx * 2.03 + 17.3
        cy = cy * 2.03 + 9.7
        amp *= 0.5
    return v / total


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / max(b - a, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def chamfer_distance(mask: np.ndarray) -> np.ndarray:
    """Exact 3/4 chamfer distance inside `mask` (0 outside, positive tiles inside)."""
    h, w = mask.shape
    result = np.where(mask, 1 << 20, 0).astype(np.int32)
    ramp = np.arange(w, dtype=np.int32) * 3
    for y in range(h):
        row = result[y]
        if y > 0:
            prev = result[y - 1]
            np.minimum(row, prev + 3, out=row)
            np.minimum(row[1:], prev[:-1] + 4, out=row[1:])
            np.minimum(row[:-1], prev[1:] + 4, out=row[:-1])
        row[:] = np.minimum.accumulate(row - ramp) + ramp
    for y in range(h - 1, -1, -1):
        row = result[y]
        if y < h - 1:
            nxt = result[y + 1]
            np.minimum(row, nxt + 3, out=row)
            np.minimum(row[1:], nxt[:-1] + 4, out=row[1:])
            np.minimum(row[:-1], nxt[1:] + 4, out=row[:-1])
        row[::-1] = np.minimum.accumulate(row[::-1] - ramp) + ramp
    return np.maximum(result.astype(np.float32) / 3.0 - 0.5, 0.0)


def box_1d(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    n = a.shape[axis]
    pad_w = [(r, r) if ax == axis else (0, 0) for ax in range(2)]
    p = np.pad(a, pad_w, mode="edge")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    z = np.zeros((1, p.shape[1]) if axis == 0 else (p.shape[0], 1), dtype=np.float64)
    c = np.concatenate([z, c], axis=axis)
    if axis == 0:
        return ((c[2 * r + 1 : 2 * r + 1 + n, :] - c[:n, :]) / (2 * r + 1)).astype(np.float32)
    return ((c[:, 2 * r + 1 : 2 * r + 1 + n] - c[:, :n]) / (2 * r + 1)).astype(np.float32)


def blur(a: np.ndarray, r: int, passes: int = 3) -> np.ndarray:
    out = a.astype(np.float32)
    for _ in range(passes):
        out = box_1d(box_1d(out, r, 0), r, 1)
    return out


def erode(m: np.ndarray) -> np.ndarray:
    r = m.copy()
    r[1:] &= m[:-1]; r[0] = False
    r[:-1] &= m[1:]; r[-1] = False
    r[:, 1:] &= m[:, :-1]; r[:, 0] = False
    r[:, :-1] &= m[:, 1:]; r[:, -1] = False
    return r


def dilate(m: np.ndarray) -> np.ndarray:
    r = m.copy()
    r[1:] |= m[:-1]
    r[:-1] |= m[1:]
    r[:, 1:] |= m[:, :-1]
    r[:, :-1] |= m[:, 1:]
    return r


def opening(m: np.ndarray, n: int) -> np.ndarray:
    for _ in range(n):
        m = erode(m)
    for _ in range(n):
        m = dilate(m)
    return m


def closing(m: np.ndarray, n: int) -> np.ndarray:
    for _ in range(n):
        m = dilate(m)
    for _ in range(n):
        m = erode(m)
    return m


def label_cc(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """4-connected components (run-based union-find)."""
    h, w = mask.shape
    parent: list[int] = []
    runs_by_row: list[list[tuple[int, int, int]]] = []

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    prev: list[tuple[int, int, int]] = []
    m_i8 = mask.astype(np.int8)
    for y in range(h):
        row = m_i8[y]
        starts = np.nonzero((row == 1) & np.concatenate(([True], row[:-1] == 0)))[0].tolist()
        ends = (np.nonzero((row == 1) & np.concatenate((row[1:] == 0, [True])))[0] + 1).tolist()
        cur: list[tuple[int, int, int]] = []
        j = 0
        plen = len(prev)
        for s, e in zip(starts, ends):
            rid = len(parent)
            parent.append(rid)
            while j < plen and prev[j][1] <= s:
                j += 1
            k = j
            while k < plen and prev[k][0] < e:
                ra, rb = find(rid), find(prev[k][2])
                if ra != rb:
                    parent[ra] = rb
                k += 1
            cur.append((s, e, rid))
        runs_by_row.append(cur)
        prev = cur

    ids: dict[int, int] = {}
    out = np.zeros((h, w), dtype=np.int32)
    for y, runs in enumerate(runs_by_row):
        for s, e, rid in runs:
            root = find(rid)
            nid = ids.get(root)
            if nid is None:
                nid = len(ids) + 1
                ids[root] = nid
            out[y, s:e] = nid
    return out, len(ids)


def keep_largest_cc(mask: np.ndarray) -> np.ndarray:
    lab, n = label_cc(mask)
    if n <= 1:
        return mask.copy()
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    sizes[0] = 0
    best = int(np.argmax(sizes))
    return lab == best


def fill_interior_holes(mask: np.ndarray) -> np.ndarray:
    """Fills all 4-connected ~mask components that do not touch the image border."""
    inv = ~mask
    lab, n = label_cc(inv)
    if n == 0:
        return mask.copy()
    border_ids = set(np.unique(lab[0, :]).tolist())
    border_ids.update(np.unique(lab[-1, :]).tolist())
    border_ids.update(np.unique(lab[:, 0]).tolist())
    border_ids.update(np.unique(lab[:, -1]).tolist())
    border_ids.discard(0)
    is_outside = np.zeros(n + 1, dtype=bool)
    for bid in border_ids:
        is_outside[bid] = True
    return ~is_outside[lab]


def drop_small(mask: np.ndarray, min_area: int) -> np.ndarray:
    lab, n = label_cc(mask)
    if n == 0:
        return mask
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    keep = sizes >= min_area
    keep[0] = False
    return keep[lab]


def rank_normalise(field: np.ndarray, land: np.ndarray) -> np.ndarray:
    count = int(land.sum())
    order = np.empty(count, dtype=np.float32)
    order[np.argsort(field[land])] = np.arange(count, dtype=np.float32) / max(count, 1)
    out = np.zeros_like(field, dtype=np.float32)
    out[land] = order
    return out


# =============================================================================
# 2. Geometry Helpers (Polylines, Simplification, Winding, Distances)
# =============================================================================

def signed_area(poly: list[tuple[float, float]]) -> float:
    s = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return 0.5 * s


def dist2d(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def polyline_len(pts: list[tuple[float, float]]) -> float:
    return sum(dist2d(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def point_along(pts: list[tuple[float, float]], share: float) -> tuple[float, float]:
    if not pts:
        return (0.0, 0.0)
    want = max(0.0, min(1.0, share)) * polyline_len(pts)
    for i in range(len(pts) - 1):
        d = dist2d(pts[i], pts[i + 1])
        if want <= d or i == len(pts) - 2:
            t = max(0.0, min(1.0, want / max(d, 1e-6)))
            return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
        want -= d
    return pts[-1]


def rdp_simplify(pts: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    """Iterative Douglas-Peucker polyline simplification preserving exact endpoints."""
    if len(pts) <= 2:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = True
    keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i0, i1 = stack.pop()
        if i1 <= i0 + 1:
            continue
        ax, ay = pts[i0]
        bx, by = pts[i1]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        best_d = -1.0
        best_i = -1
        for k in range(i0 + 1, i1):
            px, py = pts[k]
            if l2 <= 1e-12:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > best_d:
                best_d = d
                best_i = k
        if best_d > eps and best_i != -1:
            keep[best_i] = True
            stack.append((i0, best_i))
            stack.append((best_i, i1))
    return [pts[i] for i in range(len(pts)) if keep[i]]


def smooth_open_pts(pts: list[tuple[float, float]], passes: int = 3) -> list[tuple[float, float]]:
    if len(pts) <= 2:
        return list(pts)
    cur = list(pts)
    for _ in range(passes):
        nxt = [cur[0]]
        for i in range(1, len(cur) - 1):
            x = 0.25 * cur[i - 1][0] + 0.5 * cur[i][0] + 0.25 * cur[i + 1][0]
            y = 0.25 * cur[i - 1][1] + 0.5 * cur[i][1] + 0.25 * cur[i + 1][1]
            nxt.append((x, y))
        nxt.append(cur[-1])
        cur = nxt
    return cur


def smooth_closed_pts(pts: list[tuple[float, float]], passes: int = 3) -> list[tuple[float, float]]:
    n = len(pts)
    if n <= 3:
        return list(pts)
    cur = list(pts)
    for _ in range(passes):
        nxt = []
        for i in range(n):
            p0, p1, p2 = cur[(i - 1) % n], cur[i], cur[(i + 1) % n]
            nxt.append((0.25 * p0[0] + 0.5 * p1[0] + 0.25 * p2[0], 0.25 * p0[1] + 0.5 * p1[1] + 0.25 * p2[1]))
        cur = nxt
    return cur


def resample_arc(
    pts: list[tuple[float, float]],
    step: float = 3.0,
    min_interior: int = 2,
    snap_digits: int = 1,
) -> list[tuple[float, float]]:
    """Resamples an open arc to ~`step` tile spacing while preserving exact endpoints."""
    if len(pts) < 2:
        return list(pts)
    total = polyline_len(pts)
    n_seg = max(min_interior + 1, int(round(total / max(step, 0.5))))
    out: list[tuple[float, float]] = [(round(pts[0][0], snap_digits), round(pts[0][1], snap_digits))]
    for k in range(1, n_seg):
        p = point_along(pts, k / float(n_seg))
        pr = (round(p[0], snap_digits), round(p[1], snap_digits))
        if dist2d(out[-1], pr) >= 0.4:
            out.append(pr)
    end_r = (round(pts[-1][0], snap_digits), round(pts[-1][1], snap_digits))
    if len(out) >= 2 and dist2d(out[-1], end_r) < 0.4:
        out[-1] = end_r
    else:
        out.append(end_r)
    return out


def resample_closed(pts: list[tuple[float, float]], step: float = 3.2, snap_digits: int = 1) -> list[tuple[float, float]]:
    ring = list(pts) + [pts[0]]
    total = polyline_len(ring)
    n_seg = max(6, int(round(total / max(step, 0.5))))
    out: list[tuple[float, float]] = []
    for k in range(n_seg):
        p = point_along(ring, k / float(n_seg))
        pr = (round(p[0], snap_digits), round(p[1], snap_digits))
        if not out or dist2d(out[-1], pr) >= 0.5:
            out.append(pr)
    while len(out) > 3 and dist2d(out[0], out[-1]) < 0.5:
        out.pop()
    return out


def catmull_open(ctrl: list[tuple[float, float]], step: float = 2.0) -> list[tuple[float, float]]:
    if len(ctrl) <= 2:
        return list(ctrl)
    ext = [
        (2 * ctrl[0][0] - ctrl[1][0], 2 * ctrl[0][1] - ctrl[1][1]),
        *ctrl,
        (2 * ctrl[-1][0] - ctrl[-2][0], 2 * ctrl[-1][1] - ctrl[-2][1]),
    ]
    out: list[tuple[float, float]] = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        cnt = max(2, int(math.ceil(dist2d(p1, p2) / max(step, 0.25))))
        for k in range(cnt):
            t = k / float(cnt)
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (p2[0] - p0[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (3 * p1[0] - p0[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (p2[1] - p0[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (3 * p1[1] - p0[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(ctrl[-1])
    return out


def point_in_poly(pt: tuple[float, float], poly: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-18) + x1):
            inside = not inside
    return inside


def size_class_for(w: int, h: int) -> str:
    edge = max(w, h)
    for key in ("S", "M", "L", "XL"):
        lo, hi = SIZE_CLASSES[key]
        if lo <= edge <= hi:
            return key
    raise ValueError(f"Size {(w, h)} (max edge {edge}) does not fit any Atlas SIZE_CLASS")


# =============================================================================
# 3. Step A: Continent Silhouette, Bays, Fjords & Offshore Islets
# =============================================================================

def _ellipse_signed(X: np.ndarray, Y: np.ndarray, cx: float, cy: float, rx: float, ry: float, ang_deg: float = 0.0) -> np.ndarray:
    """Positive inside ellipse, negative outside, in approximate tile units."""
    rad = math.radians(ang_deg)
    ca, sa = math.cos(rad), math.sin(rad)
    dx = X - cx
    dy = Y - cy
    u = (dx * ca + dy * sa) / rx
    v = (-dx * sa + dy * ca) / ry
    return (1.0 - np.hypot(u, v)) * math.sqrt(rx * ry)


def _smax(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """Smooth maximum with blend radius k (tiles)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return a * (1.0 - h) + b * h + k * h * (1.0 - h)


def _smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    return -_smax(-a, -b, k)


def build_continent_masks(X: np.ndarray, Y: np.ndarray) -> tuple[np.ndarray, np.ndarray, list[dict[str, Any]]]:
    """Builds the proud, compact ~1560x1320 ALTMARK landmass + ~24 offshore rocky skerries."""
    # 1. Domain-warped coordinate field for multi-scale coastal sculpting
    w_macro_x = (fbm(X / 210.0, Y / 210.0, SEED + 11, 3) - 0.5) * 105.0
    w_macro_y = (fbm(X / 210.0 + 37.0, Y / 210.0 + 19.0, SEED + 17, 3) - 0.5) * 105.0
    w_meso_x = (fbm(X / 68.0, Y / 68.0, SEED + 23, 3) - 0.5) * 44.0
    w_meso_y = (fbm(X / 68.0 + 13.0, Y / 68.0 + 41.0, SEED + 29, 3) - 0.5) * 44.0
    w_fine_x = (vnoise(X / 19.0, Y / 19.0, SEED + 37) - 0.5) * 14.0
    w_fine_y = (vnoise(X / 19.0 + 7.0, Y / 19.0 + 23.0, SEED + 43) - 0.5) * 14.0

    # Keep Windkap's sheltered Silberbucht beach gently calm while the rest of the coast is fiercely craggy
    bay_calm = np.exp(-(((X - 600.0) / 145.0) ** 2 + ((Y - 1345.0) / 95.0) ** 2))
    rough = 1.0 - 0.72 * bay_calm

    WX = X + (w_macro_x + w_meso_x * rough + w_fine_x * rough)
    WY = Y + (w_macro_y + w_meso_y * rough + w_fine_y * rough)

    # 2. Macro tectonic shield plates (proud asymmetric organic continent ~x=[400..1970], y=[230..1560])
    # Sculpted to echo the reference image: sweeping tapered NW slope, bold Hallgrat west headland,
    # sheltered SW Silberbucht, proud southern cape, deep Sporenbucht gulf, SE Hexenwald peninsula,
    # and broad jagged NE Varnholm plateau!
    lobes = [
        # Central heartland (glimmrast + erlenfurt + muehlenaue) - broad proud body, zero dog-bone waist
        (1145.0, 885.0, 440.0, 380.0, -8.0),
        # Western Hallgrat promontory (bold westernmost cape echoing HALLGRAT in reference!)
        (610.0,  795.0, 225.0, 175.0, -14.0),
        # NW / North Kristallgrat massif (pulled slightly inward at NW corner so no boxy square corner!)
        (865.0,  465.0, 260.0, 215.0,  16.0),
        # NE / East Varnholm fractured plateau (broad proud upper-right plateau like reference!)
        (1625.0, 485.0, 320.0, 245.0, -10.0),
        # East-central Hexenwald Saum bridge
        (1525.0, 920.0, 260.0, 205.0,   8.0),
        # SE Hexenwald-Kern cauldron peninsula (distinct bottom-right peninsula like reference!)
        (1585.0, 1315.0, 205.0, 195.0,  16.0),
        # South-central Südkap headland (proud tapering southern cape reaching y~1560 like reference!)
        (935.0,  1340.0, 215.0, 225.0, -18.0),
        # SW Windkap peninsula & headland (slightly tucked SE of Hallgrat for organic taper!)
        (625.0,  1255.0, 175.0, 138.0,   8.0),
        # Klippenstieg western coastal cliff bridge between Windkap & Hallgrat
        (615.0,  1065.0, 140.0, 130.0,  -6.0),
        # Das Windkap rocky western cape framing Silberbucht
        (515.0,  1295.0,  64.0,  64.0,  14.0),
        # Northern Mühlenaue shoulder
        (1220.0, 440.0,  220.0, 185.0,  -4.0),
    ]
    field = np.full((H, W), -999.0, dtype=np.float32)
    for cx, cy, rx, ry, ang in lobes:
        e = _ellipse_signed(WX, WY, cx, cy, rx, ry, ang)
        field = _smax(field, e, 52.0)

    # 3. Subtract dramatic sea bays, fjords & estuaries (using warped coords, calmer on Silberbucht)
    # Silberbucht sheltered crescent bay (clean walkable sandy bay for Windkap!)
    silber_wx = X + w_fine_x * 0.28 + w_meso_x * 0.14
    silber_wy = Y + w_fine_y * 0.28 + w_meso_y * 0.14
    silberbucht = _ellipse_signed(silber_wx, silber_wy, 635.0, 1440.0, 132.0, 90.0, -6.0)
    field = _smin(field, -silberbucht, 14.0)

    fjords = [
        # Klippenfjord (crisp west coast notch between Windkap and Hallgrat, leaving cliff pass above it!)
        (435.0, 1072.0, 112.0,  62.0,  -8.0, 18.0),
        # Sweeping NW Fjord & Bay above Hallgrat (breaks up the blocky NW corner just like reference!)
        (490.0,  525.0, 175.0, 115.0,  24.0, 24.0),
        # North-central Zinnenbucht estuary bay (Mühlenstrom mouth)
        (1215.0, 235.0, 125.0, 108.0,   6.0, 22.0),
        # Deep East Fjord (sharp jagged notch beneath Varnholm plateau, echoing reference!)
        (1905.0, 810.0, 168.0,  82.0, -10.0, 18.0),
        # Eastern Great Rift coastal chasm bite!
        (1975.0, 565.0,  78.0,  52.0,  12.0, 14.0),
        # Deep Southern Sporenbucht Gulf (separating Südkap from Hexenwald-Kern peninsula!)
        (1275.0, 1450.0, 158.0, 198.0,  10.0, 22.0),
        # Hexenwald southern cove (Schwarzwasser outflow)
        (1550.0, 1535.0,  78.0,  56.0, -12.0, 16.0),
        # NW craggy fjord notch cutting into Kristallgrat coast
        (735.0,  245.0,   92.0,  68.0,  26.0, 16.0),
        # NE craggy bay above Varnholm plateau
        (1785.0, 235.0,   96.0,  58.0, -20.0, 16.0),
        # East cove on Hexenwald coast
        (1830.0, 1120.0,  94.0,  62.0,  14.0, 16.0),
        # SW coastal indentation between Windkap and Südkap cape tip
        (765.0,  1478.0,  62.0,  48.0,  18.0, 14.0),
        # Deep west cove right below Hallgrat promontory
        (450.0,  915.0,   68.0,  46.0, -15.0, 14.0),
    ]
    for cx, cy, rx, ry, ang, blend in fjords:
        fj = _ellipse_signed(WX, WY, cx, cy, rx, ry, ang)
        field = _smin(field, -fj, blend)

    # Fine rocky shoreline serrations (extra fractal coastline grit)
    coast_band = np.exp(-((field / 26.0) ** 2))
    serrate = (fbm(X / 24.0, Y / 24.0, SEED + 61, 3) - 0.5) * 18.0 * rough * coast_band
    field = field + serrate

    # Ensure generous ocean margin around the 2400x1800 canvas (at least ~190 px sea on all sides)
    edge_clip = np.minimum(
        np.minimum(X - 240.0, (W - 240.0) - X),
        np.minimum(Y - 195.0, (H - 195.0) - Y),
    )
    field = _smin(field, edge_clip, 36.0)

    raw_land = field > 0.0
    # Clean microscopic sea noise & keep single contiguous continent landmass with zero interior sea holes
    land_main = closing(opening(raw_land, 2), 2)
    land_main = keep_largest_cc(land_main)
    land_main = fill_interior_holes(land_main)

    # 4. Sculpt ~24 offshore rocky skerries / islets around capes, bays & fjords
    dilated_safe = land_main.copy()
    for _ in range(16):
        dilated_safe = dilate(dilated_safe)
    # Also stay clear of Windkap's swimmable western & southern coastal sea loop
    windkap_bay_clear = (X >= 398) & (X <= 760) & (Y >= 1152) & (Y <= 1458)
    forbidden = dilated_safe | windkap_bay_clear

    # Natural archipelago clusters (varied sizes tucked near headlands, fjord mouths & Great Rift — NOT a uniform ring!)
    islet_specs = [
        # Cluster 1: SW Windkap & Klippenfjord sea stacks
        ("windkap_west_schaere",   "WESTSCHÄRE",      422, 1348, 17, 12,  18),
        ("windkap_sued_klippe",    "SILBERKLIPPE",    532, 1482, 22, 13, -14),
        ("klippen_zahn",           "FJORDZAHN",       412, 1082, 28, 16,  24),
        ("klippen_nadel",          "STURMNADEL",      376, 1044, 12,  9, -30),
        # Cluster 2: Hallgrat & NW Glaskamm archipelago
        ("hallgrat_west_holm",     "HALLHOLM",        335,  808, 32, 20,  14),
        ("hallgrat_klein",         "HALLKLIFF",       366,  862, 12,  9, -22),
        ("glaskamm_zahn_1",        "GLASZAHN",        475,  558, 34, 19,  32),
        ("glaskamm_zahn_2",        "NORDKAP-SCHÄRE",  535,  482, 18, 12, -16),
        ("glaskamm_zahn_3",        "ZACKENHOLM",      592,  358, 26, 16,  20),
        ("glaskamm_nadel",         "GLASNADEL",       550,  395, 11,  8, -10),
        # Cluster 3: North Zinnenbucht estuary archipelago
        ("kristall_riff",          "QUARZRIFF",       742,  228, 22, 13, -18),
        ("zinnen_holm",            "ZINNENHOLM",     1196,  246, 36, 20,   8),
        ("zinnen_klein",           "MÜHLENSCHÄRE",   1258,  212, 15, 10, -28),
        ("zinnen_ost",             "NORDSTECK",      1140,  218, 13,  9,  22),
        # Cluster 4: Varnholm shattered Rift splinters (East)
        ("varn_ost_zahn",          "SCHERBENHOLM",   1875,  245, 24, 14, -32),
        ("varn_splitter_1",        "RISS-SCHÄRE",    2015,  535, 30, 17,  22),
        ("varn_splitter_2",        "ASCHENHOLM",     2038,  605, 16, 11, -15),
        ("varn_splitter_3",        "LEERENKLIPPE",   1958,  795, 25, 14,  28),
        ("varn_splitter_4",        "KLUFTZAHN",      1998,  748, 12,  9, -18),
        # Cluster 5: Sporenbucht Gulf & Southern Headlands archipelago
        ("hexen_ost_holm",         "MOOSHOLM",       1872, 1125, 22, 14, -18),
        ("hexen_sued_schaere",     "EIBENSCHÄRE",    1738, 1542, 26, 15, -14),
        ("sporenbucht_insel",      "NEBELINSEL",     1282, 1445, 38, 23,  16),
        ("sporenbucht_riff",       "SPORENRIFF",     1336, 1510, 16, 11, -24),
        ("suedkap_ost_holm",       "STURMHOLM",      1188, 1525, 18, 12,  18),
        ("suedkap_riff",           "STURMRIFF",       848, 1605, 28, 16,  -8),
    ]

    islets_mask = np.zeros((H, W), dtype=bool)
    islets_json: list[dict[str, Any]] = []
    for idx_i, (iid, iname, cx, cy, rx, ry, ang) in enumerate(islet_specs):
        # Local bounding box for speed
        pad = int(max(rx, ry) * 2.2)
        x0, x1 = max(20, int(cx - pad)), min(W - 20, int(cx + pad))
        y0, y1 = max(20, int(cy - pad)), min(H - 20, int(cy + pad))
        subX = X[y0:y1, x0:x1]
        subY = Y[y0:y1, x0:x1]
        # Shift center slightly outward if overlapping forbidden zone
        best_m = None
        for shift_r in (0, 20, 40, 65):
            # push away from continent center (1180, 900)
            vx, vy = cx - 1180.0, cy - 900.0
            vn = max(math.hypot(vx, vy), 1.0)
            tcx = cx + (vx / vn) * shift_r
            tcy = cy + (vy / vn) * shift_r
            x0, x1 = max(20, int(tcx - pad)), min(W - 20, int(tcx + pad))
            y0, y1 = max(20, int(tcy - pad)), min(H - 20, int(tcy + pad))
            subX = X[y0:y1, x0:x1]
            subY = Y[y0:y1, x0:x1]
            e = _ellipse_signed(subX, subY, tcx, tcy, rx, ry, ang)
            n_isl = (fbm(subX / 16.0, subY / 16.0, SEED + 200 + idx_i * 13, 3) - 0.5) * (rx * 0.85)
            m = (e + n_isl) > 0.0
            m = keep_largest_cc(closing(opening(m, 1), 1))
            m = fill_interior_holes(m)
            if m.sum() >= 120 and not np.any(m & forbidden[y0:y1, x0:x1]) and not np.any(m & islets_mask[y0:y1, x0:x1]):
                best_m = (x0, y0, x1, y1, m)
                break
        if best_m is None:
            continue
        x0, y0, x1, y1, m = best_m
        islets_mask[y0:y1, x0:x1] |= m
        # Mark safety ring around this islet so no two islets merge
        m_pad = dilate(dilate(dilate(dilate(m))))
        forbidden[y0:y1, x0:x1] |= m_pad
        poly = trace_single_mask_contour(m, ox=x0, oy=y0, step=4.0)
        if len(poly) >= 4:
            islets_json.append({
                "id": iid,
                "name": iname,
                "poly": [[round(p[0], 1), round(p[1], 1)] for p in poly],
            })

    return land_main, islets_mask, islets_json


# =============================================================================
# 4. Step B: 100% Gapless 11-Zone Partition & Exact Planar Boundary Extraction
# =============================================================================

def _resolve_diagonal_pinches(grid: np.ndarray, passes: int = 8) -> np.ndarray:
    """Eliminates 2x2 checkerboard corners [[a,b],[b,a]] so boundary extraction yields pure simple cycles."""
    g = grid.copy()
    for _ in range(passes):
        tl = g[:-1, :-1]
        tr = g[:-1, 1:]
        bl = g[1:, :-1]
        br = g[1:, 1:]
        pinch = (tl == br) & (tr == bl) & (tl != tr)
        ys, xs = np.nonzero(pinch)
        if ys.size == 0:
            break
        for y, x in zip(ys.tolist(), xs.tolist()):
            # Prefer expanding non-zero land or lower zone ID deterministically
            a, b = int(g[y, x]), int(g[y, x + 1])
            if a == 0:
                g[y, x] = b
            elif b == 0:
                g[y, x + 1] = a
            elif a < b:
                g[y, x + 1] = a
            else:
                g[y, x] = b
    return g


def partition_continent_zones(
    X: np.ndarray,
    Y: np.ndarray,
    land_main: np.ndarray,
) -> np.ndarray:
    """Partitions 100% of `land_main` into the 11 zones with zero interior gaps and strict SIZE_CLASSES fit."""
    # Smooth multi-scale organic domain warp so inner seams curve naturally like rivers, valleys & ridges
    swx = X + (fbm(X / 145.0, Y / 145.0, SEED + 81, 3) - 0.5) * 92.0 + (vnoise(X / 46.0, Y / 46.0, SEED + 83) - 0.5) * 24.0
    swy = Y + (fbm(X / 145.0 + 29.0, Y / 145.0 + 13.0, SEED + 89, 3) - 0.5) * 92.0 + (vnoise(X / 46.0 + 17.0, Y / 46.0 + 7.0, SEED + 97) - 0.5) * 24.0

    # Multi-site weighted Voronoi territories (carefully tuned so every zone fits SIZE_CLASSES <= 576,
    # and windkap is class L ~288x256 in the SW bay/cape!).
    # Each entry: (zone_num, cx, cy, sx, sy, bias)  -> score = ((swx-cx)/sx)^2 + ((swy-cy)/sy)^2 + bias
    # Lowest score wins!
    sites: list[tuple[int, float, float, float, float, float]] = [
        # 1: windkap (SW bay & headland, target ~288x256 L!)
        (1,  595.0, 1280.0, 145.0, 118.0, -0.24),
        # 2: klippenstieg (west fjord cliff pass bridging windkap and hallgrat, M/L)
        (2,  585.0, 1068.0, 128.0, 138.0, -0.34),
        # 3: suedkap (south headland east of windkap up to Sporenbucht, XL <= 540!)
        (3,  945.0, 1385.0, 200.0, 175.0, -0.06),
        (3,  845.0, 1375.0, 130.0, 120.0,  0.08),
        # 4: erlenfurt (river valley NE of windkap, S of hallgrat, W of glimmrast, L/XL)
        (4,  840.0, 1130.0, 205.0, 168.0, -0.18),
        # 5: hallgrat (western promontory, XL)
        (5,  620.0,  772.0, 225.0, 168.0, -0.14),
        # 6: kristallgrat (NW/N jagged quartz mountain plateau, XL)
        (6,  795.0,  460.0, 245.0, 200.0, -0.16),
        # 7: muehlenaue (N-central valley & Zinnenbucht estuary, XL)
        (7, 1210.0,  515.0, 240.0, 230.0, -0.18),
        # 8: glimmrast (green heart of ALTMARK, DIE LICHTUNG & central lakes, XL <= 540!)
        (8, 1140.0,  925.0, 235.0, 182.0, -0.14),
        # 9: hexenwald_saum (east-central mossy woodland margin, XL)
        (9, 1545.0,  930.0, 235.0, 185.0, -0.12),
        # 10: hexenwald_kern (SE sunken cauldron peninsula + Westsee, XL)
        (10, 1565.0, 1305.0, 225.0, 205.0, -0.18),
        # 11: varnholm (NE/East fractured plateau + Great Rift, XL)
        (11, 1665.0,  515.0, 265.0, 235.0, -0.18),
    ]

    best_score = np.full((H, W), 1e9, dtype=np.float32)
    z_grid = np.zeros((H, W), dtype=np.int8)
    for znum, cx, cy, sx, sy, bias in sites:
        sc = ((swx - cx) / sx) ** 2 + ((swy - cy) / sy) ** 2 + bias
        better = land_main & (sc < best_score)
        z_grid[better] = znum
        best_score[better] = sc[better]

    # Hard box guardrail for windkap so windkap stays strictly L (<= 292 wide, <= 264 tall incl. bay loop)
    wk_mask = z_grid == 1
    wy_idx, wx_idx = np.nonzero(wk_mask)
    if wx_idx.size > 0:
        wk_x0 = int(wx_idx.min())
        wk_y1 = int(wy_idx.max())
        wk_over = wk_mask & ((X > wk_x0 + 286) | (Y < wk_y1 - 228))
        if np.any(wk_over):
            # Reassign overflow pixels to best non-windkap site
            ov_score = np.full((H, W), 1e9, dtype=np.float32)
            ov_z = np.zeros((H, W), dtype=np.int8)
            for znum, cx, cy, sx, sy, bias in sites:
                if znum == 1:
                    continue
                sc = ((swx - cx) / sx) ** 2 + ((swy - cy) / sy) ** 2 + bias
                b = wk_over & (sc < ov_score)
                ov_z[b] = znum
                ov_score[b] = sc[b]
            z_grid[wk_over] = ov_z[wk_over]

    # Topological cleanup:
    # 1. Each zone must be a single 4-connected component (reassign detached scraps to neighbors)
    for _ in range(6):
        changed = False
        for znum in range(1, 12):
            m = z_grid == znum
            lab, n = label_cc(m)
            if n <= 1:
                continue
            sizes = np.bincount(lab.ravel(), minlength=n + 1)
            sizes[0] = 0
            main_id = int(np.argmax(sizes))
            scraps = m & (lab != main_id)
            if not np.any(scraps):
                continue
            changed = True
            # Flood-fill scraps from adjacent zones
            ys, xs = np.nonzero(scraps)
            q = collections.deque(zip(xs.tolist(), ys.tolist()))
            z_grid[scraps] = -1
            while q:
                px, py = q.popleft()
                nbrs = []
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < W and 0 <= ny < H:
                        nv = int(z_grid[ny, nx])
                        if nv > 0 and nv != znum:
                            nbrs.append(nv)
                if nbrs:
                    z_grid[py, px] = collections.Counter(nbrs).most_common(1)[0][0]
                else:
                    q.append((px, py))
        if not changed:
            break

    # 2. Fill any enclosed zone holes (an enclave of zone B completely surrounded by zone A)
    for znum in range(1, 12):
        filled = fill_interior_holes(z_grid == znum)
        z_grid[filled & land_main] = znum

    # 3. Gentle morphological smoothing of internal zone boundaries (removes 1-px teeth)
    for znum in range(1, 12):
        m = z_grid == znum
        m_s = closing(opening(m, 1), 1) & land_main
        # Only take pixels from land_main where smoothed mask agrees
        added = m_s & (~m)
        if np.any(added):
            z_grid[added] = znum

    # Re-verify single CC per zone after tiny smoothing
    for znum in range(1, 12):
        m = z_grid == znum
        lab, n = label_cc(m)
        if n > 1:
            sizes = np.bincount(lab.ravel(), minlength=n + 1)
            sizes[0] = 0
            best = int(np.argmax(sizes))
            scraps = m & (lab != best)
            ys, xs = np.nonzero(scraps)
            z_grid[scraps] = -1
            q = collections.deque(zip(xs.tolist(), ys.tolist()))
            while q:
                px, py = q.popleft()
                nbrs = [int(z_grid[ny, nx]) for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1))
                        if 0 <= nx < W and 0 <= ny < H and z_grid[ny, nx] > 0 and z_grid[ny, nx] != znum]
                if nbrs:
                    z_grid[py, px] = nbrs[0]
                else:
                    q.append((px, py))

    # 4. Eliminate 2x2 diagonal checkerboards so half-edge boundary tracing is 100% simple
    z_grid = _resolve_diagonal_pinches(z_grid)
    # Re-sync land_main in case pinch resolver nudged 1-2 coastal pixels
    return z_grid


def trace_single_mask_contour(mask: np.ndarray, ox: int = 0, oy: int = 0, step: float = 3.2) -> list[tuple[float, float]]:
    """Traces the outer CW boundary of a single simply-connected boolean mask."""
    m = _resolve_diagonal_pinches(mask.astype(np.int8)) > 0
    h, w = m.shape
    pad = np.pad(m, 1, mode="constant", constant_values=False)
    # Directed CW edges (u -> v) where mask is on the right side
    nxt_map: dict[tuple[int, int], tuple[int, int]] = {}
    ys, xs = np.nonzero(m)
    for y, x in zip(ys.tolist(), xs.tolist()):
        py, px = y + 1, x + 1
        if not pad[py - 1, px]:  # top
            nxt_map[(x, y)] = (x + 1, y)
        if not pad[py, px + 1]:  # right
            nxt_map[(x + 1, y)] = (x + 1, y + 1)
        if not pad[py + 1, px]:  # bottom
            nxt_map[(x + 1, y + 1)] = (x, y + 1)
        if not pad[py, px - 1]:  # left
            nxt_map[(x, y + 1)] = (x, y)
    if not nxt_map:
        return []
    # Pick top-leftmost vertex -> guaranteed outer cycle
    start = min(nxt_map.keys(), key=lambda p: (p[1], p[0]))
    cycle: list[tuple[float, float]] = []
    cur = start
    guard = len(nxt_map) + 5
    while guard > 0:
        cycle.append((float(cur[0] + ox), float(cur[1] + oy)))
        cur = nxt_map[cur]
        guard -= 1
        if cur == start:
            break
    if len(cycle) < 4:
        return cycle
    sm = smooth_closed_pts(cycle, passes=3)
    res = resample_closed(sm, step=step, snap_digits=1)
    if signed_area(res) < 0:
        res.reverse()
    return res


def extract_planar_zones_and_seams(
    z_grid: np.ndarray,
) -> tuple[dict[int, list[dict[str, Any]]], dict[str, dict[str, Any]]]:
    """Extracts exact 100%-gapless CW zone loops and shared interior seams from `z_grid`.

    Returns:
      zone_arcs[znum]: ordered CW list of arc dicts:
          {"neighbor": int (0=coast or znum2), "j0": (x,y), "j1": (x,y), "pts": [(x,y)...], "seam_id": str|None}
      seams_by_id[sid]: {"id", "a", "b", "za_num", "zb_num", "pts": [...], "j0": (x,y), "j1": (x,y)}
    """
    h, w = z_grid.shape
    pad = np.pad(z_grid, 1, mode="constant", constant_values=0)

    raw_zone_cycles: dict[int, list[tuple[tuple[int, int], tuple[int, int], int]]] = {}
    for znum in range(1, 12):
        # Collect directed CW boundary edges (u -> v, neighbor_label)
        out_edges: dict[tuple[int, int], list[tuple[tuple[int, int], int]]] = collections.defaultdict(list)
        ys, xs = np.nonzero(z_grid == znum)
        for y, x in zip(ys.tolist(), xs.tolist()):
            py, px = y + 1, x + 1
            n_top = int(pad[py - 1, px])
            if n_top != znum:
                out_edges[(x, y)].append(((x + 1, y), n_top))
            n_right = int(pad[py, px + 1])
            if n_right != znum:
                out_edges[(x + 1, y)].append(((x + 1, y + 1), n_right))
            n_bot = int(pad[py + 1, px])
            if n_bot != znum:
                out_edges[(x + 1, y + 1)].append(((x, y + 1), n_bot))
            n_left = int(pad[py, px - 1])
            if n_left != znum:
                out_edges[(x, y + 1)].append(((x, y), n_left))

        # Every vertex should have out-degree 1 (since diagonal pinches were eliminated)
        for v, elist in out_edges.items():
            if len(elist) != 1:
                raise RuntimeError(f"Zone {znum} vertex {v} has out-degree {len(elist)} (expected 1)")

        start = min(out_edges.keys(), key=lambda p: (p[1], p[0]))
        cycle: list[tuple[tuple[int, int], tuple[int, int], int]] = []
        cur = start
        while True:
            nxt, nbr = out_edges[cur][0]
            cycle.append((cur, nxt, nbr))
            cur = nxt
            if cur == start:
                break
        if len(cycle) != len(out_edges):
            raise RuntimeError(f"Zone {znum} boundary has multiple loops ({len(cycle)} vs {len(out_edges)})")
        raw_zone_cycles[znum] = cycle

    # Identify all global junction vertices (where >=3 distinct labels meet around a grid corner)
    # In fact, any vertex where `nbr` changes along ANY zone's cycle is a junction!
    junctions: set[tuple[int, int]] = set()
    for znum, cycle in raw_zone_cycles.items():
        n = len(cycle)
        for i in range(n):
            if cycle[i][2] != cycle[(i - 1) % n][2]:
                junctions.add(cycle[i][0])

    # Split each zone's cycle at global junctions into directed runs
    raw_arcs_by_zone: dict[int, list[dict[str, Any]]] = {}
    canonical_arcs: dict[tuple[int, int, tuple[int, int], tuple[int, int], int], list[tuple[float, float]]] = {}

    for znum, cycle in raw_zone_cycles.items():
        n = len(cycle)
        j_indices = [i for i in range(n) if cycle[i][0] in junctions]
        if not j_indices:
            raise RuntimeError(f"Zone {znum} has no boundary junctions!")
        arcs: list[dict[str, Any]] = []
        m = len(j_indices)
        for k in range(m):
            i0 = j_indices[k]
            i1 = j_indices[(k + 1) % m]
            pts: list[tuple[int, int]] = []
            idx = i0
            nbr = cycle[i0][2]
            while True:
                u, v, enbr = cycle[idx]
                assert enbr == nbr, f"Mixed neighbor inside arc of zone {znum}: {enbr} vs {nbr}"
                pts.append(u)
                idx = (idx + 1) % n
                if idx == i1:
                    pts.append(v)
                    break
            j0, j1 = pts[0], pts[-1]
            # Canonical undirected key so both sides of a shared seam get the EXACT same smoothed points!
            if nbr > 0:
                lo_z, hi_z = (znum, nbr) if znum < nbr else (nbr, znum)
                if j0 <= j1:
                    canon_pts = pts
                    ckey = (lo_z, hi_z, j0, j1, len(pts))
                    reversed_flag = False
                else:
                    canon_pts = list(reversed(pts))
                    ckey = (lo_z, hi_z, j1, j0, len(pts))
                    reversed_flag = True
                if ckey not in canonical_arcs:
                    fpts = [(float(p[0]), float(p[1])) for p in canon_pts]
                    sm = smooth_open_pts(fpts, passes=4)
                    simp = rdp_simplify(sm, eps=0.55)
                    res = resample_arc(simp, step=3.2, min_interior=3, snap_digits=1)
                    canonical_arcs[ckey] = res
                arc_pts = list(reversed(canonical_arcs[ckey])) if reversed_flag else list(canonical_arcs[ckey])
            else:
                # Coastal arc (high-resolution fractal coastline, points every ~3.0 tiles!)
                fpts = [(float(p[0]), float(p[1])) for p in pts]
                sm = smooth_open_pts(fpts, passes=3)
                simp = rdp_simplify(sm, eps=0.42)
                arc_pts = resample_arc(simp, step=3.0, min_interior=2, snap_digits=1)
            arcs.append({
                "neighbor": nbr,
                "j0": (round(float(j0[0]), 1), round(float(j0[1]), 1)),
                "j1": (round(float(j1[0]), 1), round(float(j1[1]), 1)),
                "pts": arc_pts,
                "seam_id": None,
            })
        raw_arcs_by_zone[znum] = arcs

    # Name all unique interior seams
    seams_by_id: dict[str, dict[str, Any]] = {}
    pair_counts: dict[tuple[int, int], int] = collections.defaultdict(int)
    arc_to_seam_id: dict[tuple[int, int, tuple[float, float], tuple[float, float]], str] = {}

    for znum in range(1, 12):
        for arc in raw_arcs_by_zone[znum]:
            nbr = arc["neighbor"]
            if nbr == 0:
                continue
            lo_z, hi_z = (znum, nbr) if znum < nbr else (nbr, znum)
            j0, j1 = arc["j0"], arc["j1"]
            ukey = (lo_z, hi_z, min(j0, j1), max(j0, j1))
            if ukey not in arc_to_seam_id:
                pair_counts[(lo_z, hi_z)] += 1
                za_id = ZONE_BY_NUM[lo_z]["id"]
                zb_id = ZONE_BY_NUM[hi_z]["id"]
                suffix = "" if pair_counts[(lo_z, hi_z)] == 1 else f"_{pair_counts[(lo_z, hi_z)]}"
                sid = f"naht_{za_id}_{zb_id}{suffix}"
                arc_to_seam_id[ukey] = sid
                # Store interior points only (excluding the two pinned junction vertices J0 and J1),
                # so both adjacent zones emit [J0_local, {"seam": sid}, J1_local] with ZERO duplicate vertices!
                full_pts = arc["pts"] if znum == lo_z else list(reversed(arc["pts"]))
                interior_pts = full_pts[1:-1]
                if len(interior_pts) < 2:
                    # Fallback midpoint split if arc was tiny
                    p_a = point_along(full_pts, 0.33)
                    p_b = point_along(full_pts, 0.67)
                    interior_pts = [(round(p_a[0], 1), round(p_a[1], 1)), (round(p_b[0], 1), round(p_b[1], 1))]
                seams_by_id[sid] = {
                    "id": sid,
                    "a": za_id,
                    "b": zb_id,
                    "za_num": lo_z,
                    "zb_num": hi_z,
                    "pts": interior_pts,
                    "full_pts": full_pts,
                    "length": polyline_len(full_pts),
                    "j0": full_pts[0],
                    "j1": full_pts[-1],
                }
            arc["seam_id"] = arc_to_seam_id[ukey]

    return raw_arcs_by_zone, seams_by_id


# =============================================================================
# 5. Step C: Inland Lakes & Downhill Branching River Networks
# =============================================================================

def _organic_lake_mask(
    X: np.ndarray,
    Y: np.ndarray,
    lobes: list[tuple[float, float, float, float, float]],
    seed: int,
    warp_amp: float = 16.0,
) -> np.ndarray:
    """Builds an irregular multi-lobed FBM-warped inland lake basin (never a plain circle)."""
    xs = [l[0] for l in lobes]
    ys = [l[1] for l in lobes]
    max_r = max(max(l[2], l[3]) for l in lobes) + warp_amp + 20.0
    x0 = max(10, int(min(xs) - max_r))
    x1 = min(W - 10, int(max(xs) + max_r))
    y0 = max(10, int(min(ys) - max_r))
    y1 = min(H - 10, int(max(ys) + max_r))
    sX = X[y0:y1, x0:x1]
    sY = Y[y0:y1, x0:x1]
    wx = sX + (fbm(sX / 36.0, sY / 36.0, seed + 1, 3) - 0.5) * warp_amp * 2.0
    wy = sY + (fbm(sX / 36.0 + 19.0, sY / 36.0 + 11.0, seed + 2, 3) - 0.5) * warp_amp * 2.0
    f = np.full(sX.shape, -999.0, dtype=np.float32)
    for cx, cy, rx, ry, ang in lobes:
        f = _smax(f, _ellipse_signed(wx, wy, cx, cy, rx, ry, ang), 14.0)
    f += (vnoise(sX / 12.0, sY / 12.0, seed + 5) - 0.5) * 6.0
    sub = keep_largest_cc(closing(opening(f > 0.0, 2), 2))
    sub = fill_interior_holes(sub)
    out = np.zeros((H, W), dtype=bool)
    out[y0:y1, x0:x1] = sub
    return out


def build_lakes_and_rivers(
    X: np.ndarray,
    Y: np.ndarray,
    land_main: np.ndarray,
    coast_dist: np.ndarray,
    windkap_origin: tuple[int, int],
    windkap_brook_world: list[tuple[float, float, float]],
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, list[dict[str, Any]], list[dict[str, Any]]]:
    """Builds 7 sculpted inland lakes + fully interconnected wide downhill rivers + flared coastal estuaries.

    Returns:
      lakes_mask, lakes_sdf, water_rgb, river_dist, estuary_open_mask, lake_entries, rivers_json
    """
    # 7 scenic multi-lobed inland lakes placed inside flat valley basins (safe distance >= 16 tiles from sea)
    lake_defs = [
        # 1. Der Große Lichtungsee (central-west Glimmrast, iconic vertical-lobed lake like reference!)
        ("lichtungsee", "DER LICHTUNGSEE", 101, 18.0, [
            (1005, 865, 36, 64, -14),
            ( 982, 816, 30, 36,  18),
            (1028, 918, 34, 38,  22),
        ]),
        # 2. Der Spiegelsee (central-east Glimmrast, elongated curving lake like reference!)
        ("spiegelsee", "DER SPIEGELSEE", 107, 16.0, [
            (1195, 922, 64, 28,  -8),
            (1260, 905, 44, 26,  16),
            (1134, 938, 38, 24, -22),
        ]),
        # 3. Der Mühlensee (NE Mühlenaue/Glimmrast feeding the northern Mühlenstrom!)
        ("muehlensee", "DER MÜHLENSEE", 113, 15.0, [
            (1265, 650, 46, 36,  14),
            (1222, 682, 36, 26, -18),
            (1302, 616, 30, 24,  24),
        ]),
        # 4. Der Westsee / Schiefersee (sunken Hexenwald-Kern cauldron lake, SE peninsula!)
        ("westsee", "DER WESTSEE", 127, 15.0, [
            (1538, 1295, 50, 36, -12),
            (1585, 1326, 38, 28,  20),
            (1494, 1272, 30, 25,  14),
        ]),
        # 5. Der Erlenweiher (tranquil upper Erlenfurt tarn feeding Erlenbach toward Windkap)
        ("erlenweiher", "DER ERLENWEIHER", 131, 11.0, [
            (848, 1075, 30, 21, -15),
            (876, 1090, 24, 18,  18),
        ]),
        # 6. Der Hochgrat-Karsee (alpine glacial tarn in Kristallgrat/Hallgrat saddle)
        ("hochgrat_karsee", "DER HOCHGRAT-KARSEE", 137, 11.0, [
            (795, 620, 32, 24,  22),
            (826, 636, 24, 19, -14),
        ]),
        # 7. Der Klammsee (dark forest tarn in Hexenwald-Saum)
        ("klammsee", "DER KLAMMSEE", 149, 11.0, [
            (1535, 935, 34, 23, -18),
            (1568, 950, 26, 19,  15),
        ]),
    ]

    lakes_mask = np.zeros((H, W), dtype=bool)
    lake_entries: list[dict[str, Any]] = []
    lake_bounds: list[tuple[int, int, int, int, np.ndarray]] = []

    safe_inland = land_main & (coast_dist >= 14.0)
    for lid, lname, lseed, wamp, lobes in lake_defs:
        lm = _organic_lake_mask(X, Y, lobes, lseed, wamp) & safe_inland
        lm = keep_largest_cc(opening(lm, 1))
        if lm.sum() < 150:
            continue
        lakes_mask |= lm
        ys, xs = np.nonzero(lm)
        y0, y1 = max(0, int(ys.min()) - 4), min(H, int(ys.max()) + 5)
        x0, x1 = max(0, int(xs.min()) - 4), min(W, int(xs.max()) + 5)
        lake_bounds.append((x0, y0, x1, y1, lm[y0:y1, x0:x1]))
        poly = trace_single_mask_contour(lm[y0:y1, x0:x1], ox=x0, oy=y0, step=5.0)
        lake_entries.append({
            "id": lid,
            "name": lname,
            "center": [round(float(xs.mean()), 1), round(float(ys.mean()), 1)],
            "area_tiles": int(lm.sum()),
            "poly": [[round(p[0], 1), round(p[1], 1)] for p in poly],
        })

    out_lake_d_raw = chamfer_distance(~lakes_mask)

    # Interconnected downhill river watersheds (every lake has generous inflow + outflow, every sea mouth flares into an estuary!)
    # Widths are half-widths in tiles (so half-width 2.5 -> 5t wide headwater, 4.5..6.8 -> 9..13.5t main trunk,
    # flaring to 10..16t half-width = 20..32t wide trumpet estuary directly into the sea!).
    def make_river(
        rid: str,
        rname: str,
        ctrl: list[tuple[float, float]],
        elev_start: float,
        elev_end: float,
        hw_start: float,
        hw_end: float,
        seed: int,
        meander_amp: float = 14.0,
        estuary_flare: float = 0.0,
    ) -> dict[str, Any]:
        sm = catmull_open(ctrl, step=7.0)
        n = len(sm)
        pts_xy: list[tuple[float, float]] = []
        for i, (px, py) in enumerate(sm):
            t = i / max(n - 1, 1)
            env = math.sin(math.pi * t) ** 1.1
            prev_p = sm[max(0, i - 1)]
            next_p = sm[min(n - 1, i + 1)]
            tx, ty = next_p[0] - prev_p[0], next_p[1] - prev_p[1]
            tn = max(math.hypot(tx, ty), 1e-6)
            nx, ny = -ty / tn, tx / tn
            wob = (
                math.sin(t * 17.0 + seed * 0.37) * 0.55
                + math.cos(t * 29.0 + seed * 0.71) * 0.30
                + math.sin(t * 47.0 + seed * 1.13) * 0.15
            ) * meander_amp * env
            pts_xy.append((px + nx * wob, py + ny * wob))
        # For sea-bound rivers, march smoothly past the coastline ~16 tiles into open bay water so the estuary is 100% continuous!
        if elev_end <= 0.01 and len(pts_xy) >= 2:
            ex, ey = pts_xy[-1]
            dx = ex - pts_xy[-2][0]
            dy = ey - pts_xy[-2][1]
            dn = max(math.hypot(dx, dy), 1e-6)
            dx, dy = dx / dn, dy / dn
            ix, iy = int(round(ex)), int(round(ey))
            steps = 0
            while 0 <= ix < W and 0 <= iy < H and land_main[iy, ix] and steps < 45:
                ex += dx * 5.0
                ey += dy * 5.0
                pts_xy.append((ex, ey))
                ix, iy = int(round(ex)), int(round(ey))
                steps += 1
            for _ in range(3):
                ex += dx * 5.5
                ey += dy * 5.5
                pts_xy.append((ex, ey))
        m = len(pts_xy)
        # Detect if the river starts inside a lake (broad outflow) vs a mountain headwater spring (gentle taper)
        sx0, sy0 = int(round(pts_xy[0][0])), int(round(pts_xy[0][1]))
        starts_in_lake = (0 <= sx0 < W and 0 <= sy0 < H and out_lake_d_raw[sy0, sx0] < 12.0)
        pts_json = []
        widths = []
        for i, (px, py) in enumerate(pts_xy):
            t = i / max(m - 1, 1)
            elev = elev_start * (1.0 - t) + elev_end * t
            w_t = hw_start + (hw_end - hw_start) * (t ** 1.15)
            if not starts_in_lake and elev_start >= 8.0 and t < 0.08:
                # Natural headwater spring taper so mountain streams emerge organically
                w_t *= 0.45 + 0.55 * (t / 0.08)
            pts_json.append([round(px, 1), round(py, 1), round(elev, 2)])
            widths.append(w_t)
        return {
            "id": rid,
            "name": rname,
            "pts": pts_json,
            "widths": widths,
            "estuary_flare": estuary_flare if elev_end <= 0.01 else 0.0,
        }

    # Exact upstream entry point of Windkap's handcrafted Erlenbach
    wk_brook_start = (windkap_brook_world[0][0], windkap_brook_world[0][1])

    rivers: list[dict[str, Any]] = [
        # 1a. Upper Erlenbach: Hallgrat foothills -> Erlenweiher tarn -> Windkap entry
        make_river(
            "erlenbach_oberlauf", "ERLENBACH-OBERLAUF",
            [(682, 912), (748, 968), (806, 1022), (855, 1078), (812, 1126), (766, 1170), wk_brook_start],
            elev_start=14.0, elev_end=5.4, hw_start=2.4, hw_end=3.8, seed=21, meander_amp=11.0,
        ),
        # 1b. Windkap Erlenbach (verbatim centerline with windkap/zone.json, flaring cleanly into Silberbucht!)
        {
            "id": "erlenbach",
            "name": "DER ERLENBACH",
            "pts": [[round(p[0], 1), round(p[1], 1), round(p[2], 2)] for p in windkap_brook_world],
            "widths": [3.5 + 2.0 * (i / max(len(windkap_brook_world) - 1, 1)) for i in range(len(windkap_brook_world))],
            "estuary_flare": 6.5,
        },
        # 2a. Glaskamm/Kristallgrat mountain river -> Hochgrat-Karsee -> Lichtungsee
        make_river(
            "klangbach", "DER KLANGBACH",
            [(755, 412), (780, 512), (804, 624), (868, 708), (938, 780), (998, 848)],
            elev_start=17.5, elev_end=9.2, hw_start=2.5, hw_end=4.6, seed=33, meander_amp=13.0,
        ),
        # 2b. Hallgrat east tributary -> Lichtungsee
        make_river(
            "hallbach", "DER HALLBACH",
            [(592, 768), (695, 796), (795, 824), (898, 854), (992, 874)],
            elev_start=14.0, elev_end=9.2, hw_start=2.3, hw_end=4.0, seed=41, meander_amp=10.0,
        ),
        # 2c. Central Lichtungsstrom: Lichtungsee -> broad channel -> Spiegelsee -> wide winding river -> Sporenbucht trumpet estuary!
        make_river(
            "lichtungsstrom", "DER LICHTUNGSSTROM",
            [(1012, 898), (1076, 936), (1162, 926), (1248, 918), (1278, 995), (1220, 1085), (1168, 1175), (1216, 1255), (1205, 1320)],
            elev_start=9.2, elev_end=0.0, hw_start=4.8, hw_end=7.4, seed=55, meander_amp=22.0, estuary_flare=11.0,
        ),
        # 2d. Südbach: rises in Südkap highland hills -> winds NE to join lower Lichtungsstrom
        make_river(
            "wiesenaue_bach", "DER WIESENBACH",
            [(952, 1338), (1012, 1272), (1072, 1218), (1132, 1185), (1182, 1182)],
            elev_start=9.0, elev_end=3.2, hw_start=2.3, hw_end=3.8, seed=62, meander_amp=12.0,
        ),
        # 3a. Mühlenstrom: Spiegelsee -> broad channel -> Mühlensee -> wide river -> Zinnenbucht trumpet estuary!
        make_river(
            "muehlenstrom", "DER MÜHLENSTROM",
            [(1256, 904), (1292, 822), (1252, 742), (1264, 650), (1228, 558), (1254, 465), (1214, 378), (1208, 305)],
            elev_start=8.0, elev_end=0.0, hw_start=4.6, hw_end=7.0, seed=74, meander_amp=18.0, estuary_flare=10.5,
        ),
        # 3b. Kristallgrat east fork -> Mühlensee
        make_river(
            "kristallbach", "DER KRISTALLBACH",
            [(936, 428), (1022, 506), (1116, 545), (1192, 614), (1254, 646)],
            elev_start=16.0, elev_end=6.2, hw_start=2.4, hw_end=4.2, seed=83, meander_amp=15.0,
        ),
        # 3c. Mühlenstrom estuary east delta arm -> Zinnenbucht
        make_river(
            "muehlenstrom_ostarm", "MÜHLENSTROM-OSTARM",
            [(1222, 412), (1248, 372), (1268, 336), (1276, 302)],
            elev_start=1.8, elev_end=0.0, hw_start=4.0, hw_end=5.4, seed=88, meander_amp=6.0, estuary_flare=7.0,
        ),
        # 4a. Das Schwarzwasser: Glimmrast/Saum ridge -> Klammsee -> wide winding channel -> Westsee -> Hexenwald South Cove estuary!
        make_river(
            "schwarzwasser", "DAS SCHWARZWASSER",
            [(1408, 788), (1482, 856), (1538, 936), (1584, 1022), (1522, 1118), (1564, 1205), (1540, 1292), (1516, 1384), (1546, 1468)],
            elev_start=12.0, elev_end=0.0, hw_start=2.8, hw_end=6.4, seed=95, meander_amp=20.0, estuary_flare=10.0,
        ),
        # 4b. Hexenquell eastern tributary -> Westsee
        make_river(
            "hexenquell", "DER HEXENQUELL",
            [(1708, 1048), (1682, 1136), (1628, 1204), (1592, 1274), (1558, 1308)],
            elev_start=9.5, elev_end=3.5, hw_start=2.3, hw_end=3.8, seed=103, meander_amp=13.0,
        ),
        # 5. Varnholm Klammbach: northern Varnholm highlands -> carved canyon -> East Fjord trumpet estuary!
        make_river(
            "varn_klammbach", "DER KLAMMBACH",
            [(1588, 388), (1652, 486), (1638, 586), (1702, 676), (1748, 742), (1808, 782)],
            elev_start=15.5, elev_end=0.0, hw_start=2.6, hw_end=5.6, seed=117, meander_amp=16.0, estuary_flare=9.5,
        ),
    ]

    # Subtle bank organic wobble so river edges feel hand-drawn instead of smooth CAD tubes
    bank_wobble = (vnoise(X / 11.0, Y / 11.0, SEED + 251) - 0.5) * 1.6 + (vnoise(X / 5.0, Y / 5.0, SEED + 257) - 0.5) * 0.6

    # Rasterize rivers with smooth lake-inlet/outlet funnels AND wide coastal trumpet estuaries!
    water_cov = np.where(lakes_mask, 1.0, 0.0).astype(np.float32)
    water_dep = np.zeros((H, W), dtype=np.float32)
    river_core = np.zeros((H, W), dtype=bool)
    estuary_open_mask = np.zeros((H, W), dtype=bool)
    lake_funnel_mask = np.zeros((H, W), dtype=bool)

    for rv in rivers:
        rpts = rv["pts"]
        rws = rv["widths"]
        flare = float(rv.get("estuary_flare", 0.0))
        for i in range(len(rpts) - 1):
            ax, ay = float(rpts[i][0]), float(rpts[i][1])
            bx, by = float(rpts[i + 1][0]), float(rpts[i + 1][1])
            ra, rb = float(rws[i]), float(rws[i + 1])
            rmax = max(ra, rb) * 1.85 + flare + 5.0
            x0 = max(0, int(math.floor(min(ax, bx) - rmax)))
            x1 = min(W, int(math.ceil(max(ax, bx) + rmax)) + 1)
            y0 = max(0, int(math.floor(min(ay, by) - rmax)))
            y1 = min(H, int(math.ceil(max(ay, by) + rmax)) + 1)
            if x1 <= x0 or y1 <= y0:
                continue
            sx = X[y0:y1, x0:x1]
            sy = Y[y0:y1, x0:x1]
            dx, dy = bx - ax, by - ay
            l2 = max(dx * dx + dy * dy, 1e-6)
            t = np.clip(((sx - ax) * dx + (sy - ay) * dy) / l2, 0.0, 1.0)
            dist_seg = np.hypot(sx - (ax + t * dx), sy - (ay + t * dy)) + bank_wobble[y0:y1, x0:x1]
            rad = ra + (rb - ra) * t

            # Organic funnel widening where river meets ANY lake shore!
            sub_ld = out_lake_d_raw[y0:y1, x0:x1]
            lake_prox = 1.0 - smoothstep(0.0, 24.0, sub_ld)
            rad = rad * (1.0 + 0.65 * (lake_prox ** 1.35))

            # True coastal trumpet estuary flare near ocean coastline!
            sub_cd = coast_dist[y0:y1, x0:x1]
            if flare > 0.0:
                sea_prox = 1.0 - smoothstep(0.0, 52.0, sub_cd)
                rad = rad + flare * (sea_prox ** 1.65)
                # Smooth V-tapered fjord estuary throat carved directly into continental_sdf:
                # full flared width at sea edge (sub_cd=0), tapering gracefully to 0 along the river centerline (~36t inland)
                throat_t = 1.0 - smoothstep(0.0, 36.0, sub_cd)
                est_throat = (sub_cd <= 36.0) & (dist_seg <= rad * (throat_t ** 0.68))
                estuary_open_mask[y0:y1, x0:x1] |= est_throat

            # Smooth anti-aliased river coverage (clean 1.4-tile transition, rich deep center!)
            cov = np.clip((rad + 0.7 - dist_seg) / 1.4, 0.0, 1.0)
            # Rich ocean-matching depth profile: gentle shallow edge -> deep center proportional to river width
            core_frac = np.clip(1.0 - dist_seg / np.maximum(rad + 0.3, 0.5), 0.0, 1.0)
            dep = (0.28 + 0.72 * (core_frac ** 0.75)) * np.clip(0.55 + 0.075 * rad, 0.55, 0.98)

            water_cov[y0:y1, x0:x1] = np.maximum(water_cov[y0:y1, x0:x1], cov)
            water_dep[y0:y1, x0:x1] = np.maximum(water_dep[y0:y1, x0:x1], dep * (cov > 0.05))
            river_core[y0:y1, x0:x1] |= dist_seg <= (rad + 0.5)
            # Merge funnel mouths into lakes_sdf so rivers flow seamlessly into lakes with ZERO divider lip!
            lake_funnel_mask[y0:y1, x0:x1] |= (sub_ld <= 14.0) & (dist_seg <= rad)

    # Clean estuary_open_mask to stay inside land_main and connected to the sea (never creates detached sea puddles!)
    estuary_open_mask &= land_main
    # Keep only estuary components that actually touch the open ocean (~land_main)
    sea_touch = dilate(~land_main) & estuary_open_mask
    if np.any(sea_touch):
        elab, en = label_cc(estuary_open_mask)
        good_e = np.unique(elab[sea_touch])
        estuary_open_mask = np.isin(elab, good_e[good_e > 0])
    else:
        estuary_open_mask[:] = False

    # Build unified lakes + lake-mouth funnels mask for continental_lakes_sdf.png and lake_basin_depth (B)!
    # NO outer synthetic halo ring (strictly 0 outside lakes_unified!) so lakes never get thick sticker outlines!
    lakes_unified = (lakes_mask | (lake_funnel_mask & land_main)) & (~estuary_open_mask)
    in_lake_d = chamfer_distance(lakes_unified)
    out_lake_d = chamfer_distance(~lakes_unified)
    to_lake = np.where(lakes_unified, -in_lake_d, out_lake_d)
    lakes_sdf = np.clip(np.rint(128.0 + to_lake * 8.0), 0, 255).astype(np.uint8)

    # Compute smooth per-basin cartographic lake depth strictly inside lakes_unified (NO outer 144-halo!)
    lake_basin_depth = np.zeros((H, W), dtype=np.float32)
    ulab, un = label_cc(lakes_unified)
    for uid in range(1, un + 1):
        um = ulab == uid
        u_max = max(float(in_lake_d[um].max()), 1.0)
        lake_basin_depth[um] = 0.14 + 0.86 * np.clip(in_lake_d[um] / u_max, 0.0, 1.0) ** 0.70

    # Blend lake depth smoothly into water_dep (G) — fading out the river centerline groove inside lakes
    # so lakes show pure smooth basin bathymetry while funnels transition seamlessly into river depth!
    lake_dep_val = np.where(lakes_unified, 0.26 + 0.74 * lake_basin_depth, 0.0)
    inside_lake_d = chamfer_distance(lakes_mask)
    in_lake_blend = smoothstep(0.0, 10.0, inside_lake_d)
    water_dep = np.where(
        lakes_mask,
        water_dep * (1.0 - in_lake_blend) + lake_dep_val * in_lake_blend,
        np.maximum(water_dep, lake_dep_val),
    )

    # Keep water coverage slightly overlapping into estuary_open_mask & sea mouth (up to 12 tiles offshore)
    # so @map-painter has a 100% seamless ocean<->river transition with zero seam or coast-rim bar!
    coast_overlap = land_main | (chamfer_distance(~land_main) <= 12.0)
    water_cov *= coast_overlap.astype(np.float32)
    water_dep *= coast_overlap.astype(np.float32)
    lake_basin_depth *= land_main.astype(np.float32)

    river_dist = chamfer_distance(~(river_core | estuary_open_mask))

    water_rgb = np.zeros((H, W, 3), dtype=np.uint8)
    water_rgb[..., 0] = np.clip(np.rint(water_cov * 255.0), 0, 255).astype(np.uint8)
    water_rgb[..., 1] = np.clip(np.rint(water_dep * 255.0), 0, 255).astype(np.uint8)
    water_rgb[..., 2] = np.clip(np.rint(lake_basin_depth * 255.0), 0, 255).astype(np.uint8)

    rivers_json = [{"id": rv["id"], "name": rv["name"], "pts": rv["pts"]} for rv in rivers]
    return lakes_mask, lakes_sdf, water_rgb, river_dist, estuary_open_mask, lake_entries, rivers_json


# =============================================================================
# 6. Step D: Exact 4-Level Morphological Relief (bake_relief.py Quality!)
# =============================================================================

def limit_steps(lvl: np.ndarray, land: np.ndarray) -> None:
    while True:
        changed = False
        for axis in (0, 1):
            a = lvl.astype(np.int16)
            for s in (1, -1):
                b = np.roll(a, s, axis=axis)
                bad = (a - b > 1) & land & np.roll(land, s, axis=axis)
                if bad.any():
                    lvl[bad] = (b[bad] + 1).astype(np.int8)
                    a = lvl.astype(np.int16)
                    changed = True
        if not changed:
            return


def _side_tiles(d: int, ox: int, oy: int, depth: int, w: int = 3) -> list[tuple[int, int, int, int]]:
    (dx, dy), (ax, ay) = DOWN[d], ACROSS[d]
    return [(r, c, ox + dx * r + ax * c, oy + dy * r + ay * c) for r in range(depth) for c in range(w)]


def _side_pattern(d: int) -> list[tuple[int, int, int]]:
    if d == EAST:
        return [(dx, dy, 0 if dx <= 0 else -1) for dy in range(-1, 4) for dx in range(-2, 5)]
    if d == WEST:
        return [(dx, dy, 0 if dx >= 0 else -1) for dy in range(-1, 4) for dx in range(-4, 3)]
    if d == NORTH:
        return [(dx, dy, 0 if dy >= 0 else -1) for dx in range(-1, 4) for dy in range(-4, 3)]
    return []


def _site_ok_side(lvl: np.ndarray, kind: np.ndarray, land: np.ndarray, d: int, ox: int, oy: int) -> bool:
    hi = int(lvl[oy, ox])
    if hi < 1:
        return False
    for dx, dy, off in _side_pattern(d):
        x, y = ox + dx, oy + dy
        if not (0 <= x < W and 0 <= y < H and land[y, x] and kind[y, x] == FLOOR and lvl[y, x] == hi + off):
            return False
    return True


def _site_ok_south(lvl: np.ndarray, kind: np.ndarray, x: int, y: int, w: int = 3) -> bool:
    if x < 2 or x + w + 2 >= W or y < 2 or y + 4 >= H:
        return False
    lo = lvl[y, x]
    for c in range(w):
        xx = x + c
        if not (kind[y, xx] == FACE and kind[y + 1, xx] == FACE and kind[y - 1, xx] == FLOOR and lvl[y - 1, xx] == lo + 1 and lvl[y + 1, xx] == lo):
            return False
        if not (kind[y + 2, xx] == FLOOR and lvl[y + 2, xx] == lo and kind[y + 3, xx] == FLOOR and lvl[y + 3, xx] == lo):
            return False
    for xx in (x - 1, x + w):
        if not (kind[y, xx] == FACE and kind[y + 1, xx] == FACE and kind[y + 2, xx] == FLOOR and lvl[y + 2, xx] == lo):
            return False
    return True


def _conn_ends(x: int, y: int, d: int) -> tuple[int, int, int, int]:
    if d == SOUTH:
        return x, y - 1, x, y + 2
    (dx, dy), (ax, ay) = DOWN[d], ACROSS[d]
    return x - dx + ax, y - dy + ay, x + dx * 2 + ax, y + dy * 2 + ay


def _conn_origin(x: int, y: int, d: int) -> tuple[int, int]:
    return (x - 1, y) if d == SOUTH else (x, y)


def _analyse_relief(
    lvl: np.ndarray,
    land: np.ndarray,
    style_field: np.ndarray,
    conns: list[list[int]],
    start: tuple[int, int],
) -> dict[str, Any]:
    limit_steps(lvl, land)
    north = np.zeros_like(lvl)
    north[1:] = lvl[:-1]
    face0 = land & (north > lvl)
    face1 = np.zeros_like(face0)
    face1[1:] = face0[:-1]
    face1 &= land & (~face0) & (lvl == np.roll(lvl, 1, axis=0))
    face = face0 | face1
    kind = np.where(face, FACE, FLOOR).astype(np.uint8)
    geom = face1.astype(np.uint8)

    s1 = np.zeros_like(style_field); s1[1:] = style_field[:-1]
    s2 = np.zeros_like(style_field); s2[2:] = style_field[:-2]
    fstyle = np.where(face0, s1, np.where(face1, s2, 0)).astype(np.int8)
    cstyle = np.zeros((H, W), dtype=np.int8)

    walk = land & (~face)
    comp = np.zeros((H, W), dtype=np.int32)
    ncomp = 0
    for k in range(4):
        lab, n = label_cc(walk & (lvl == k))
        comp = np.where(lab > 0, lab + ncomp, comp)
        ncomp += n
    parent = list(range(ncomp + 1))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    kept: list[list[int]] = []
    for c in conns:
        x, y, kd, cw, d = c
        depth = 3 if kd == RAMP else 2
        if d == SOUTH:
            if not _site_ok_south(lvl, kind, x, y, cw):
                continue
            st = int(fstyle[y, x + 1])
            a, b = int(comp[y - 1, x + 1]), int(comp[y + depth, x + 1])
            for cc in range(cw):
                for r in range(depth):
                    kind[y + r, x + cc] = kd
                    geom[y + r, x + cc] = r | ((depth - 1) << 2) | (cc << 4)
                    cstyle[y + r, x + cc] = st
        else:
            if not _site_ok_side(lvl, kind, land, d, x, y):
                continue
            st = int(style_field[y, x])
            for r, cc, tx, ty in _side_tiles(d, x, y, depth):
                kind[ty, tx] = kd
                geom[ty, tx] = r | ((depth - 1) << 2) | (cc << 4) | (d << 6)
                cstyle[ty, tx] = st
            hx, hy, _, _ = _conn_ends(x, y, d)
            lx = x + DOWN[d][0] * depth + ACROSS[d][0]
            ly = y + DOWN[d][1] * depth + ACROSS[d][1]
            a, b = int(comp[hy, hx]), int(comp[ly, lx])
        parent[find(a)] = find(b)
        kept.append(c)
    conns[:] = kept
    roots = np.array([find(i) for i in range(ncomp + 1)], dtype=np.int32)
    start_root = int(roots[comp[start[1], start[0]]])
    return {
        "src": style_field, "kind": kind, "geom": geom, "cstyle": cstyle,
        "fstyle": fstyle, "comp": comp, "roots": roots, "start_root": start_root, "walk": walk,
    }


def _candidates(res: dict[str, Any], land: np.ndarray, coast: np.ndarray, lvl: np.ndarray, conns: list[list[int]]) -> list[tuple[int, int, int, int]]:
    kind, geom = res["kind"], res["geom"]

    def at(a: np.ndarray, dy: int) -> np.ndarray:
        return np.roll(a, -dy, axis=0)

    sel = (
        (kind == FACE) & (geom == 0)
        & (at(kind, -1) == FLOOR) & (at(kind, 1) == FACE) & (at(kind, 2) == FLOOR) & (at(kind, 3) == FLOOR)
        & (at(lvl, -1) == lvl + 1) & (at(lvl, 2) == lvl) & (at(lvl, 3) == lvl)
    )
    ys, xs = np.nonzero(sel)
    out: list[tuple[int, int, int, int]] = []
    block = np.zeros((H, W), dtype=bool)
    for cx, cy, _, cw, d in conns:
        if d == SOUTH:
            block[max(0, cy - 6):min(H, cy + 9), max(0, cx - 8):min(W, cx + cw + 8)] = True
        else:
            block[max(0, cy - 8):min(H, cy + 11), max(0, cx - 8):min(W, cx + 11)] = True
    for y, x in zip(ys.tolist(), xs.tolist()):
        if x < 6 or x > W - 7 or y < 6 or y > H - 9 or block[y, x]:
            continue
        if not land[y - 3:y + 5, x - 3:x + 4].all() or coast[y + 4, x] < 5 or coast[y - 3, x] < 5:
            continue
        straight = int(((kind[y, x - 4:x + 5] == FACE) & (kind[y + 1, x - 4:x + 5] == FACE)).sum())
        out.append((straight, x, y, SOUTH))

    floor = land & (kind == FLOOR)

    def sh(a: np.ndarray, dy: int, dx: int) -> np.ndarray:
        return np.roll(np.roll(a, -dy, axis=0), -dx, axis=1)

    for d, (dy, dx) in ((EAST, (0, 1)), (WEST, (0, -1)), (NORTH, (-1, 0))):
        edge = floor & sh(floor, dy, dx) & (lvl >= 1) & (sh(lvl, dy, dx) == lvl - 1)
        along = (1, 0) if d != NORTH else (0, 1)
        straight3 = edge & sh(edge, along[0], along[1]) & sh(edge, 2 * along[0], 2 * along[1])
        ys, xs = np.nonzero(straight3)
        for y, x in zip(ys.tolist(), xs.tolist()):
            if x < 9 or x > W - 10 or y < 9 or y > H - 10 or block[y, x]:
                continue
            if coast[y, x] < 5 or coast[y + dy * 4, x + dx * 4] < 5 or coast[y - dy * 4, x - dx * 4] < 5:
                continue
            run = int(sum(edge[y + along[0] * k, x + along[1] * k] for k in range(-3, 7)))
            out.append((run, x, y, d))
    return out


def _put_connector(res: dict[str, Any], lvl: np.ndarray, conns: list[list[int]], x: int, y: int, d: int, rng: np.random.Generator) -> None:
    if d == SOUTH:
        hi = int(lvl[y - 1, x])
        lo = hi - 1
        lvl[y - 3:y, x - 3:x + 4] = hi
        lvl[y:y + 5, x - 3:x + 4] = lo
    else:
        hi = int(lvl[y, x])
        for dx, dy, off in _side_pattern(d):
            lvl[y + dy, x + dx] = hi + off
    st = int(res["fstyle"][y, x]) if d == SOUTH else int(res["src"][y, x])
    if st == STYLE_MASONRY:
        kd = STAIRS
    elif st == STYLE_GRASS:
        kd = RAMP
    else:
        kd = RAMP if rng.random() < 0.18 else STEPS
    ox, oy = _conn_origin(x, y, d)
    conns.append([ox, oy, kd, 3, d])


def assign_islet_biomes(
    land_main: np.ndarray,
    islets_mask: np.ndarray,
    z_grid: np.ndarray,
    islets_json: list[dict[str, Any]],
    rift_center: tuple[float, float],
) -> tuple[np.ndarray, np.ndarray]:
    """Assigns each offshore islet the region_id (1..5) and biome_idx (0,2,4,5) of the nearest mainland coast pixel."""
    biome_names = {0: "meadow", 2: "glass_cliffs", 4: "void_bloom", 5: "witch_forest"}
    region_names = {r["area_id"]: r["id"] for r in REGIONS}

    # Build mainland coastal pixel lookup (only ~8k pixels -> sub-millisecond nearest lookup!)
    main_reg = np.zeros((H, W), dtype=np.int8)
    main_bio = np.zeros((H, W), dtype=np.int8)
    for z in ZONES_META:
        m = z_grid == z["znum"]
        main_reg[m] = REGION_AREA_ID[z["region"]]
        main_bio[m] = REGION_BIOME_IDX[z["region"]]

    coast_px = land_main & (~erode(land_main))
    cy, cx = np.nonzero(coast_px)
    cx_f = cx.astype(np.float32)
    cy_f = cy.astype(np.float32)
    c_reg = main_reg[cy, cx]
    c_bio = main_bio[cy, cx]

    islet_reg = np.zeros((H, W), dtype=np.int8)
    islet_bio = np.zeros((H, W), dtype=np.int8)

    lab, n_isl = label_cc(islets_mask)
    comp_info: list[tuple[float, float, int, int]] = []
    for cid in range(1, n_isl + 1):
        m = lab == cid
        iy, ix = np.nonzero(m)
        mx, my = float(ix.mean()), float(iy.mean())
        best_i = int(np.argmin((cx_f - mx) ** 2 + (cy_f - my) ** 2))
        rid = int(c_reg[best_i])
        bid = int(c_bio[best_i])
        islet_reg[m] = rid
        islet_bio[m] = bid
        comp_info.append((mx, my, rid, bid))

    # Also tag each entry in main.json["islets"] with region, biome & near_rift
    rx, ry = rift_center
    counts: collections.Counter[str] = collections.Counter()
    for entry in islets_json:
        pts = entry.get("poly", [])
        if not pts:
            continue
        px = sum(float(p[0]) for p in pts) / len(pts)
        py = sum(float(p[1]) for p in pts) / len(pts)
        best_i = int(np.argmin((cx_f - px) ** 2 + (cy_f - py) ** 2))
        rid = int(c_reg[best_i])
        bid = int(c_bio[best_i])
        rname = region_names[rid]
        bname = biome_names[bid]
        d_rift = math.hypot(px - rx, py - ry)
        entry["region"] = rname
        entry["biome"] = bname
        if rid == 5 and d_rift < 260.0:
            entry["near_rift"] = True
        counts[f"{rname}({bname})"] += 1

    print("  [islets] biome assignment: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return islet_reg, islet_bio


def build_continental_relief(
    X: np.ndarray,
    Y: np.ndarray,
    land_main: np.ndarray,
    islets_mask: np.ndarray,
    z_grid: np.ndarray,
    islet_reg: np.ndarray,
    islet_bio: np.ndarray,
    lakes_mask: np.ndarray,
    coast_dist: np.ndarray,
    river_dist: np.ndarray,
    windkap_features: dict[str, Any],
    rift_center: tuple[float, float],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Builds exact bake_relief.py 4-level relief -> (continental_relief RGBA, continental_field RGB, lvl int8)."""
    rng = np.random.default_rng(SEED + 303)
    land_all = land_main | islets_mask
    walk_land = land_main & (~lakes_mask)

    # Region-specific tectonic gain, bias, and wall style weights
    # (1=suedwestkueste, 2=gruenland, 3=glaskamm, 4=hexenwald, 5=leerenbluehen)
    region_grid = np.zeros((H, W), dtype=np.int8)
    biome_grid = np.zeros((H, W), dtype=np.int8)
    for z in ZONES_META:
        m = z_grid == z["znum"]
        region_grid[m] = REGION_AREA_ID[z["region"]]
        biome_grid[m] = REGION_BIOME_IDX[z["region"]]
    # Offshore islets inherit exact nearest mainland coast region & biome!
    region_grid[islets_mask] = islet_reg[islets_mask]
    biome_grid[islets_mask] = islet_bio[islets_mask]

    # Regional gain / bias tuned for crisp multi-tiered concentric mesas (L0 > L1 > L2 > L3, zero L3 pancakes!)
    gain_lut = np.array([1.0, 1.12, 1.24, 1.32, 1.04, 1.30], dtype=np.float32)
    bias_lut = np.array([-0.2, -0.09, -0.02, 0.06, -0.15, 0.05], dtype=np.float32)
    gain = blur(gain_lut[region_grid], 18, passes=2)
    bias = blur(bias_lut[region_grid], 18, passes=2)

    # Warped FBM relief field (sculptural twisted finger mesas like media_1795533966881_304f99c7.jpg!)
    wx = X + (vnoise(X / 48.0, Y / 48.0, SEED + 101) - 0.5) * 46.0
    wy = Y + (vnoise(X / 48.0 + 47.0, Y / 48.0 + 31.0, SEED + 103) - 0.5) * 46.0
    n_base = fbm(wx / 62.0, wy / 62.0, SEED + 107, octaves=3)
    # Secondary sculptural ridges for crisp mesa chains
    n_ridge = 1.0 - np.abs(fbm(wx / 96.0 + 19.0, wy / 96.0 + 11.0, SEED + 109, octaves=2) - 0.5) * 2.0
    n_mix = n_base * 0.72 + n_ridge * 0.28
    rank = rank_normalise(n_mix, walk_land)
    v = 0.5 + (rank - 0.5) * gain + bias

    # Craft iconic geological landmarks directly into `v` (subtle boosts preserving crisp stepped tiers!):
    # 1. Hallgrat western plateau terrace & acropolis (matching reference HALLGRAT!)
    v += 0.12 * np.exp(-(((X - 585.0) / 130.0) ** 2 + ((Y - 785.0) / 115.0) ** 2))
    # 2. Kristallgrat alpine massif (dramatic concentric L1->L2->L3 spires, NOT a giant solid L3 slab!)
    v += 0.13 * np.exp(-(((X - 840.0) / 160.0) ** 2 + ((Y - 430.0) / 125.0) ** 2))
    # 3. Varnholm fractured NE plateau + Great Rift chasm crater on the east rim!
    v += 0.12 * np.exp(-(((X - 1655.0) / 195.0) ** 2 + ((Y - 475.0) / 160.0) ** 2))
    rx, ry = rift_center
    rift_d = np.hypot((X - rx) * 1.15, (Y - ry) * 0.72)
    # Shattered cliff ring around the chasm, deep crater right inside the rift!
    v += 0.15 * np.exp(-(((rift_d - 78.0) / 34.0) ** 2))
    v = np.where(rift_d < 50.0, 0.14, v)
    # 4. Hexenwald sunken slate cauldron around Westsee, rimmed by broken slate ridges on north/east!
    ws_d = np.hypot((X - 1542.0) / 125.0, (Y - 1295.0) / 105.0)
    v -= 0.28 * np.exp(-(ws_d ** 2))
    v += 0.16 * np.exp(-(((X - 1675.0) / 88.0) ** 2 + ((Y - 1175.0) / 68.0) ** 2))
    # 5. Windkap handcrafted terrain:
    #    Keep Windkap lowland valleys/meadows/camp/Apfeltrift flat L0, raise Das Windkap west cape & NW cliff ridge!
    wk_ox, wk_oy = windkap_features["origin"]
    wk_zone = z_grid == 1
    v = np.where(wk_zone, np.minimum(v, 0.42), v)
    # Raise Das Windkap stepped headland (L1 + L2 crown at lighthouse ruin)
    h1x, h1y = wk_ox + windkap_features["headland_center"][0], wk_oy + windkap_features["headland_center"][1]
    hd1 = np.hypot((X - h1x) / 30.0, (Y - h1y) / 25.0)
    v = np.where(hd1 < 1.35, np.maximum(v, 0.88 - 0.34 * hd1), v)
    # Raise NW Klippenstieg stepped cliff plateau (L1 + L2 ridge)
    h2x, h2y = wk_ox + windkap_features["nw_cliff_center"][0], wk_oy + windkap_features["nw_cliff_center"][1]
    hd2 = np.hypot((X - h2x) / 38.0, (Y - h2y) / 32.0)
    v = np.where(hd2 < 1.35, np.maximum(v, 0.92 - 0.36 * hd2), v)

    # Coast, lake, river & Windkap camp flattening
    lake_dist = chamfer_distance(~lakes_mask)
    cliff_coast_region = (region_grid == 3) | (region_grid == 5) | (z_grid == 2) | (hd1 < 1.45)
    coast_flat_gentle = smoothstep(7.0, 17.0, coast_dist)
    coast_flat_cliff = smoothstep(3.5, 10.5, coast_dist)
    coast_flat = np.where(cliff_coast_region, coast_flat_cliff, coast_flat_gentle)

    # Deep fluvial valley & lake-basin carving so INK cliff contours FLANK rivers/lakes and NEVER slice across them!
    lake_flat = smoothstep(8.0, 24.0, lake_dist)
    river_flat = smoothstep(7.0, 22.0, river_dist)

    camp_wx = wk_ox + windkap_features["camp_tile"][0]
    camp_wy = wk_oy + windkap_features["camp_tile"][1]
    camp_flat = smoothstep(14.0, 28.0, np.hypot(X - camp_wx, Y - camp_wy))
    ws_wx = wk_ox + windkap_features["waystone_tile"][0]
    ws_wy = wk_oy + windkap_features["waystone_tile"][1]
    ws_flat = smoothstep(10.0, 22.0, np.hypot(X - ws_wx, Y - ws_wy))

    flat = coast_flat * lake_flat * river_flat * camp_flat * ws_flat
    v = 0.18 + (v - 0.18) * flat

    # Threshold into 4 height levels (0..3) -> ~59% L0, ~24% L1, ~12% L2, ~5% L3!
    THRESH = (0.60, 0.79, 0.94)
    raw = ((v > THRESH[0]).astype(np.int8) + (v > THRESH[1]).astype(np.int8) + (v > THRESH[2]).astype(np.int8))
    raw = np.where(walk_land, raw, 0)

    # Strict valley floor clearance enforced AFTER closing() so cliffs never bridge across a river or lake!
    valley_clear = walk_land & (river_dist >= 5.5) & (lake_dist >= 6.5)

    # Clean each level via diamond opening + closing, drop tiny speckles/holes, nest with 4-tile ledges
    lvl = np.zeros((H, W), dtype=np.int8)
    below = valley_clear.copy()
    prev_mask = valley_clear.copy()
    for k in (1, 2, 3):
        m = (raw >= k) & below
        m = drop_small(closing(opening(m, 2), 2), 140)
        m = ~drop_small(~m, 140)
        m &= valley_clear
        m = drop_small(opening(m, 1), 110)
        if k > 1:
            e = prev_mask
            for _ in range(4):
                e = erode(e)
            m &= e
        prev_mask = m
        lvl += m.astype(np.int8)
        below = m

    # Give larger offshore rocky skerries a scenic L1 peak crag in their middle
    isl_peak = islets_mask & (coast_dist >= 5.5)
    isl_peak = drop_small(opening(isl_peak, 1), 35)
    lvl[isl_peak] = 1

    limit_steps(lvl, land_all)

    # Per-tile cliff wall style (0=GRASS, 1=ROCK, 2=MASONRY, 3=CRYSTAL, 4=VOID, 5=SLATE)
    # Offshore islets automatically inherit their nearest coastal region's wall style via region_grid!
    sn = rank_normalise(fbm(X / 16.0, Y / 16.0, SEED + 131, 2), land_all)
    style_field = np.zeros((H, W), dtype=np.int8)
    # suedwestkueste & gruenland -> GRASS (0) & ROCK (1)
    m_mg = (region_grid == 1) | (region_grid == 2)
    style_field[m_mg] = np.where(sn[m_mg] > 0.65, STYLE_ROCK, STYLE_GRASS)
    # glaskamm -> ROCK (1), CRYSTAL (3), MASONRY (2 around Hallgrat)
    m_gk = region_grid == 3
    style_field[m_gk] = np.where(sn[m_gk] > 0.55, STYLE_CRYSTAL, STYLE_ROCK)
    m_hg = z_grid == 5
    style_field[m_hg] = np.where(sn[m_hg] > 0.62, STYLE_MASONRY, style_field[m_hg])
    # hexenwald -> HEXENWALD SLATE (5)
    style_field[region_grid == 4] = STYLE_SLATE
    # leerenbluehen -> VOID (4) & ROCK (1); islets near the Great Rift carry strong VOID corruption!
    m_lb = region_grid == 5
    style_field[m_lb] = np.where(sn[m_lb] > 0.42, STYLE_VOID, STYLE_ROCK)
    isl_rift = islets_mask & (region_grid == 5) & (np.hypot(X - rx, Y - ry) < 260.0)
    style_field[isl_rift] = STYLE_VOID

    # Run bake_relief.py connector placement so every walkable plateau on the continent has ramps/stairs/steps!
    start_pt = (int(round(camp_wx)), int(round(camp_wy)))
    conns: list[list[int]] = []

    def settle(rounds: int) -> dict[str, Any]:
        for _ in range(rounds):
            res = _analyse_relief(lvl, walk_land, style_field, conns, start_pt)
            cand = _candidates(res, walk_land, coast_dist, lvl, conns)
            roots, comp = res["roots"], res["comp"]
            by_group: dict[int, list[tuple[float, int, int, int]]] = collections.defaultdict(list)
            for straight, x, y, d in cand:
                hx, hy, lx, ly = _conn_ends(x, y, d)
                a, b = int(roots[comp[hy, hx]]), int(roots[comp[ly, lx]])
                if a == b:
                    continue
                for g, other in ((a, b), (b, a)):
                    if g != res["start_root"]:
                        by_group[g].append(((2.0 if other == res["start_root"] else 0.0) + min(straight, 9) / 9.0 + float(rng.random()) * 0.8, x, y, d))
            added = 0
            used = np.zeros((H, W), dtype=bool)
            groups = list(by_group.keys())
            for gi in rng.permutation(len(groups)):
                for _, x, y, d in sorted(by_group[groups[int(gi)]], reverse=True)[:10]:
                    if used[max(0, y - 8):min(H, y + 11), max(0, x - 8):min(W, x + 11)].any():
                        continue
                    _put_connector(res, lvl, conns, x, y, d, rng)
                    used[max(0, y - 8):min(H, y + 11), max(0, x - 8):min(W, x + 11)] = True
                    added += 1
                    break
            if added == 0:
                unreached = (~np.isin(res["roots"][res["comp"]], [res["start_root"]])) & res["walk"]
                if not unreached.any():
                    return res
                lab, n = label_cc(unreached)
                for idx_c in range(1, n + 1):
                    piece = lab == idx_c
                    k_lv = int(lvl[piece][0])
                    if k_lv >= 1:
                        lvl[piece] = k_lv - 1
                    else:
                        lvl[piece] = 1
        return _analyse_relief(lvl, walk_land, style_field, conns, start_pt)

    res = settle(20)
    # Add extra scenic connectors on different sides of major plateaus
    cand = _candidates(res, walk_land, coast_dist, lvl, conns)
    by_side: dict[tuple[int, int], list[tuple[float, int, int, int]]] = collections.defaultdict(list)
    comp = res["comp"]
    for straight, x, y, d in cand:
        hx, hy, _, _ = _conn_ends(x, y, d)
        by_side[(int(comp[hy, hx]), d)].append((straight + float(rng.random()) * 3.0, x, y, d))
    blk = np.zeros((H, W), dtype=bool)
    for cx, cy, _, _, _ in conns:
        blk[max(0, cy - 14):min(H, cy + 15), max(0, cx - 14):min(W, cx + 17)] = True
    per_p: collections.Counter[int] = collections.Counter()
    keys = list(by_side.keys())
    rng.shuffle(keys)
    for key in keys:
        if per_p[key[0]] >= 4:
            continue
        for _, x, y, d in sorted(by_side[key], reverse=True)[:15]:
            ox, oy = _conn_origin(x, y, d)
            if blk[oy, ox]:
                continue
            _put_connector(res, lvl, conns, x, y, d, rng)
            blk[max(0, oy - 14):min(H, oy + 15), max(0, ox - 14):min(W, ox + 17)] = True
            per_p[key[0]] += 1
            break
    res = settle(15)
    # Final wall analysis over full land_all (including islet peaks!)
    res_all = _analyse_relief(lvl, land_all & (~lakes_mask), style_field, conns, start_pt)

    kind, geom, cstyle, face_style = res_all["kind"], res_all["geom"], res_all["cstyle"], res_all["fstyle"]
    style = np.where(kind == FACE, face_style, np.where(kind == FLOOR, style_field, cstyle)).astype(np.uint8)

    # Pack exact bake_relief.py RGBA image
    relief_rgba = np.zeros((H, W, 4), dtype=np.uint8)
    relief_rgba[..., 0] = lvl.astype(np.uint8)
    relief_rgba[..., 1] = kind | (style << 4)
    relief_rgba[..., 2] = geom
    relief_rgba[..., 3] = np.where(land_all, np.uint8(200) + biome_grid.astype(np.uint8), np.uint8(0))

    # Export 3-channel blurred relief_field.png (exact bake_relief.py export_smooth!)
    field_rgb = np.zeros((H, W, 3), dtype=np.uint8)
    for ch, k in enumerate((1, 2, 3)):
        m = (lvl >= k).astype(np.float32)
        m = blur(m, 1, passes=3)
        field_rgb[..., ch] = np.clip(np.rint(m * 255.0), 0, 255).astype(np.uint8)

    print(
        f"  [relief] L0={int((walk_land & (lvl == 0)).sum())}, "
        f"L1={int((walk_land & (lvl == 1)).sum())}, "
        f"L2={int((walk_land & (lvl == 2)).sum())}, "
        f"L3={int((walk_land & (lvl == 3)).sum())}, "
        f"walls={int((kind == FACE).sum())}, conns={len(conns)}"
    )
    return relief_rgba, field_rgb, lvl


# =============================================================================
# 7. Step E: Organic Multi-Lobed Forest Stands & Continent Ways
# =============================================================================

def build_organic_forest_stands(
    X: np.ndarray,
    Y: np.ndarray,
    land_main: np.ndarray,
    z_grid: np.ndarray,
    lvl: np.ndarray,
    coast_dist: np.ndarray,
    lakes_mask: np.ndarray,
    river_dist: np.ndarray,
    windkap_stands: list[dict[str, Any]],
    rift_center: tuple[float, float],
) -> list[dict[str, Any]]:
    """Extracts FBM-sculpted, multi-lobed organic forest stands (ZERO circles, ZERO donuts)."""
    lake_dist = chamfer_distance(~lakes_mask)
    wx = X + (fbm(X / 85.0, Y / 85.0, SEED + 401, 3) - 0.5) * 62.0
    wy = Y + (fbm(X / 85.0 + 23.0, Y / 85.0 + 41.0, SEED + 409, 3) - 0.5) * 62.0
    fn = fbm(wx / 72.0, wy / 72.0, SEED + 419, 3)

    # Regional woodland affinity (dense in Hexenwald, picturesque groves in Grünland & Südkap, sparse on cliffs)
    thresh = np.full((H, W), 0.62, dtype=np.float32)
    thresh[z_grid == 3] = 0.58   # suedkap coastal groves
    thresh[z_grid == 4] = 0.58   # erlenfurt riparian groves
    thresh[z_grid == 7] = 0.60   # muehlenaue meadow groves
    thresh[z_grid == 8] = 0.59   # glimmrast groves framing lakes
    thresh[z_grid == 5] = 0.66   # hallgrat sparse pine copses
    thresh[z_grid == 6] = 0.67   # kristallgrat sparse alpine pines
    thresh[z_grid == 9] = 0.44   # hexenwald_saum lush primeval forest
    thresh[z_grid == 10] = 0.45  # hexenwald_kern deep cauldron woods
    thresh[z_grid == 11] = 0.64  # varnholm western margin copses

    rx, ry = rift_center
    not_rift = np.hypot(X - rx, Y - ry) > 135.0
    # Exclude windkap (windkap has handcrafted stands!), sea, beach, lakes, rivers, and steep L2/L3 peaks
    can_forest = (
        land_main
        & (z_grid != 1)
        & (coast_dist >= 12.0)
        & (lake_dist >= 6.0)
        & (river_dist >= 6.0)
        & (lvl <= 1)
        & not_rift
    )
    fmask = can_forest & (fn > thresh)
    fmask = drop_small(closing(opening(fmask, 3), 2), 950)
    # Break any enclosed circular holes > 400 tiles stay as real glades, tiny holes filled
    fmask = fill_interior_holes(fmask)

    lab, n = label_cc(fmask)
    stands: list[dict[str, Any]] = list(windkap_stands)

    # Sort components by area descending and take up to 24 crisp organic woodlands
    sizes = np.bincount(lab.ravel(), minlength=n + 1)
    order = sorted(range(1, n + 1), key=lambda i: int(sizes[i]), reverse=True)[:24]

    for idx_s, cid in enumerate(order):
        m = lab == cid
        if int(sizes[cid]) < 950:
            continue
        ys, xs = np.nonzero(m)
        y0, y1 = max(0, int(ys.min()) - 2), min(H, int(ys.max()) + 3)
        x0, x1 = max(0, int(xs.min()) - 2), min(W, int(xs.max()) + 3)
        sub = m[y0:y1, x0:x1]
        outline = trace_single_mask_contour(sub, ox=x0, oy=y0, step=14.0)
        if len(outline) < 5:
            continue
        # Pick dominant zone for species mix
        dom_z = int(collections.Counter(z_grid[m].tolist()).most_common(1)[0][0])
        dom_reg = ZONE_BY_NUM[dom_z]["region"]
        if dom_reg == "hexenwald":
            mix = [
                {"species": "valley_oak", "w": 0.68, "stages": [3, 4, 5, 5]},
                {"species": "silver_birch", "w": 0.32, "stages": [2, 3, 4]},
            ]
            sp_val = 4.9
        elif dom_reg in ("glaskamm", "leerenbluehen"):
            mix = [
                {"species": "valley_oak", "w": 0.55, "stages": [3, 4, 5]},
                {"species": "silver_birch", "w": 0.45, "stages": [2, 3, 4]},
            ]
            sp_val = 5.8
        else:
            mix = [
                {"species": "valley_oak", "w": 0.54, "stages": [3, 4, 5]},
                {"species": "silver_birch", "w": 0.38, "stages": [2, 3, 4]},
                {"species": "wild_apple", "w": 0.08, "stages": [2, 3, 4]},
            ]
            sp_val = 5.6
        stands.append({
            "id": f"altmark_forst_{idx_s + 1:02d}",
            "name": f"{ZONE_BY_NUM[dom_z]['name']}-FORST",
            "soil": True,
            "spacing": sp_val,
            "edge": 6.0,
            "seed": 310 + idx_s * 17,
            "mix": mix,
            "outline": [[round(p[0], 1), round(p[1], 1)] for p in outline],
            "glades": [],
        })
    return stands


# =============================================================================
# 8. Step F: Handcrafted WINDKAP Authoring & Full 11-Zone Assembly
# =============================================================================

def _clamp_inside(pt: tuple[float, float], poly: list[tuple[float, float]], target_center: tuple[float, float], margin: float = 4.0) -> tuple[float, float]:
    """Pulls `pt` gently toward `target_center` if it isn't strictly inside `poly` with `margin`."""
    cur = pt
    for step in range(40):
        ok = point_in_poly(cur, poly)
        if ok:
            # Check small ring around cur so it stays comfortably inside
            if all(point_in_poly((cur[0] + dx, cur[1] + dy), poly) for dx, dy in ((margin, 0), (-margin, 0), (0, margin), (0, -margin))):
                return (round(cur[0], 1), round(cur[1], 1))
        cur = (cur[0] * 0.92 + target_center[0] * 0.08, cur[1] * 0.92 + target_center[1] * 0.08)
    return (round(cur[0], 1), round(cur[1], 1))


def _seam_kind_for_pair(za: str, zb: str) -> str:
    pair = frozenset((za, zb))
    if pair == frozenset(("windkap", "klippenstieg")):
        return "cliff"
    if pair == frozenset(("klippenstieg", "hallgrat")):
        return "cliff"
    if pair == frozenset(("hallgrat", "kristallgrat")):
        return "ridge"
    if pair == frozenset(("windkap", "suedkap")):
        return "forest_sea"
    if pair == frozenset(("hexenwald_saum", "hexenwald_kern")):
        return "forest_sea"
    if pair == frozenset(("hexenwald_saum", "varnholm")):
        return "cliff"
    if pair == frozenset(("muehlenaue", "varnholm")):
        return "ridge"
    return "meadow"


def _coast_border_kind(z_id: str, mid_pt: tuple[float, float], rift_center: tuple[float, float]) -> str:
    if z_id == "varnholm":
        if dist2d(mid_pt, rift_center) < 130.0:
            return "void_edge"
        return "cliff"
    if z_id in ("klippenstieg", "hallgrat", "kristallgrat"):
        return "cliff"
    return "water"


def _windkap_bay_footprint_and_shore(
    arcs: list[dict[str, Any]],
    land_main: np.ndarray,
    z_grid: np.ndarray,
) -> tuple[list[dict[str, Any]], list[tuple[float, float]], list[tuple[float, float]]]:
    """Builds Windkap's continuous ocean coastline (`water` border) along BOTH the southern Silberbucht beach
    AND the entire western cape/cove coast up to the NW Klippenstieg junction, so the sea never cuts off mid-coast!
    Returns `(new_arcs, full_shore_pts_nw_to_se, bay_shore_w_to_e)`.
    """
    new_arcs: list[dict[str, Any]] = []
    full_shore_pts: list[tuple[float, float]] = []
    bay_shore_pts: list[tuple[float, float]] = []
    out_sea_d = chamfer_distance(~land_main)
    for arc in arcs:
        if arc["neighbor"] != 0:
            new_arcs.append(arc)
            continue
        pts = arc["pts"]
        # In CW winding on SW corner, coastal arc runs from SE (windkap-suedkap coast junction)
        # westward along Silberbucht beach, around Das Windkap cape, then northward up the west coast
        # to the NW (windkap-klippenstieg coast junction).
        ys = [p[1] for p in pts]
        ymin, ymax = min(ys), max(ys)
        cape_idx = min(
            range(len(pts)),
            key=lambda i: pts[i][0] + max(0.0, (ymin + (ymax - ymin) * 0.48) - pts[i][1]) * 3.0,
        )
        cape_idx = max(3, min(len(pts) - 4, cape_idx))
        bay_land_shore = pts[: cape_idx + 1]  # SE -> W cape (CW)

        # Full shore_pts ordered NW -> W cape -> SE (reversed CW arc) so WaterField covers 100% of Windkap's sea coast!
        full_shore_pts = list(reversed(pts))
        bay_shore_pts = list(reversed(bay_land_shore))

        # Build smooth, guaranteed non-self-intersecting offshore water arc from SE -> SW -> W -> NW (~18..22 tiles seaward)!
        # Smooth the shoreline heavily first so outward normals `(dy, -dx)` vary monotonically around the convex SW cape.
        p_se = pts[0]
        p_nw = pts[-1]
        n_samp = 26
        base_samples = [point_along(pts, k / float(n_samp)) for k in range(n_samp + 1)]
        sm_shore = smooth_open_pts(base_samples, passes=6)
        sea_ctrl: list[tuple[float, float]] = [p_se]
        for k in range(1, n_samp):
            t = k / float(n_samp)
            px, py = sm_shore[k]
            # Wide-chord CW tangent -> smooth outward sea normal (dy, -dx) in +Y-down coordinates
            k0 = max(0, k - 3)
            k1 = min(n_samp, k + 3)
            tx_v = sm_shore[k1][0] - sm_shore[k0][0]
            ty_v = sm_shore[k1][1] - sm_shore[k0][1]
            tlen = max(math.hypot(tx_v, ty_v), 1e-4)
            nx_out = ty_v / tlen
            ny_out = -tx_v / tlen
            bow = (math.sin(math.pi * t) ** 0.72) * 20.0
            ox_p = px + nx_out * bow
            oy_p = py + ny_out * bow
            # Guarantee strictly in open sea (at least 4 tiles clear of all mainland pixels)
            for _ in range(14):
                ix = max(0, min(W - 1, int(round(ox_p))))
                iy = max(0, min(H - 1, int(round(oy_p))))
                if land_main[iy, ix] or out_sea_d[iy, ix] < 3.5:
                    ox_p += nx_out * 2.5
                    oy_p += ny_out * 2.5
                else:
                    break
            sea_ctrl.append((round(ox_p, 1), round(oy_p, 1)))
        sea_ctrl.append(p_nw)
        bay_offshore = resample_arc(smooth_open_pts(sea_ctrl, passes=4), step=5.0, min_interior=10, snap_digits=1)

        new_arcs.append({
            "neighbor": 0,
            "coast_kind": "water",
            "j0": bay_offshore[0],
            "j1": bay_offshore[-1],
            "pts": bay_offshore,
            "seam_id": None,
        })
    return new_arcs, full_shore_pts, bay_shore_pts


def build_all_world_data(debug_preview: pathlib.Path | None = None) -> None:
    t0 = time.perf_counter()
    print("[ALTMARK] Generating 2400x1800 coordinate grids...")
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)

    # 1. Continent landmass & ~24 offshore skerries
    print("[ALTMARK] Sculpting continent silhouette, fjords, bays & offshore skerries...")
    land_main, islets_mask, islets_json = build_continent_masks(X, Y)
    ys_m, xs_m = np.nonzero(land_main)
    print(
        f"  [land] bbox x={int(xs_m.min())}..{int(xs_m.max())} ({int(xs_m.max()-xs_m.min())}t), "
        f"y={int(ys_m.min())}..{int(ys_m.max())} ({int(ys_m.max()-ys_m.min())}t), "
        f"area={int(land_main.sum())} tiles, islets={len(islets_json)}"
    )

    # 2. 100% gapless 11-zone partition
    print("[ALTMARK] Partitioning continent into 11 gapless zones...")
    z_grid = partition_continent_zones(X, Y, land_main)
    # Re-sync land_main to z_grid > 0 (after 2x2 pinch resolution)
    land_main = z_grid > 0
    for z in ZONES_META:
        zy, zx = np.nonzero(z_grid == z["znum"])
        zw, zh = int(zx.max() - zx.min()), int(zy.max() - zy.min())
        print(f"  [zone] {z['id']:16s} x={int(zx.min()):4d}..{int(zx.max()):4d} ({zw:3d}) y={int(zy.min()):4d}..{int(zy.max()):4d} ({zh:3d}) area={int(zx.size)}")

    # 3. Extract exact planar boundary arcs & shared seams
    print("[ALTMARK] Extracting planar zone footprints & shared seams...")
    zone_arcs, seams_by_id = extract_planar_zones_and_seams(z_grid)

    # Outer continent coastline from 1-tile dilated land_main so EVERY non-windkap zone vertex
    # is strictly inside `coastline` (check_atlas.py parity!) while visually matching to <1 px
    coast_mask = fill_interior_holes(dilate(land_main))
    coastline_poly = trace_single_mask_contour(coast_mask, step=3.2)
    print(f"  [coast] coastline vertices={len(coastline_poly)}, seams={len(seams_by_id)}")

    # Great Rift epicenter on Varnholm's jagged eastern rim
    vy, vx = np.nonzero(z_grid == 11)
    rift_cx = float(vx.max()) - 38.0
    rift_cy = float(vy.min() + (vy.max() - vy.min()) * 0.56)
    # Pull rift slightly inland onto land_main
    while int(round(rift_cx)) > 0 and not land_main[int(round(rift_cy)), int(round(rift_cx))]:
        rift_cx -= 4.0
    rift_center = (round(rift_cx, 1), round(rift_cy, 1))
    rift_void_edge = [
        [round(rift_cx - 26.0, 1), round(rift_cy - 110.0, 1)],
        [round(rift_cx + 18.0, 1), round(rift_cy - 34.0, 1)],
        [round(rift_cx + 14.0, 1), round(rift_cy + 48.0, 1)],
        [round(rift_cx - 32.0, 1), round(rift_cy + 116.0, 1)],
    ]

    # Assign canonical border kind to every seam
    for sid, sdata in seams_by_id.items():
        sdata["kind"] = _seam_kind_for_pair(sdata["a"], sdata["b"])

    # Special continuous offshore bay & western sea curve for Windkap
    wk_arcs, wk_shore_world, wk_bay_shore_world = _windkap_bay_footprint_and_shore(zone_arcs[1], land_main, z_grid)
    zone_arcs[1] = wk_arcs

    # Build final zone footprints, origins, sizes, and exact perimeter border spans
    # IMPORTANT: Rotate each zone's arc list so arc[0] is NEVER `forest_sea` (eliminating fake 360-deg belt rings!)
    zones_built: dict[str, dict[str, Any]] = {}
    for z in ZONES_META:
        znum = z["znum"]
        zid = z["id"]
        arcs = list(zone_arcs[znum])

        # Determine border kind for each arc
        arc_kinds: list[str] = []
        for a in arcs:
            if a["neighbor"] == 0:
                ck = a.get("coast_kind") or _coast_border_kind(zid, point_along(a["pts"], 0.5), rift_center)
                arc_kinds.append(ck)
            else:
                arc_kinds.append(seams_by_id[a["seam_id"]]["kind"])

        # Rotate arcs so index 0 is NOT forest_sea (prefer cliff, ridge, water, or meadow)
        rot = 0
        for idx_r, ak in enumerate(arc_kinds):
            if ak != "forest_sea":
                rot = idx_r
                break
        arcs = arcs[rot:] + arcs[:rot]
        arc_kinds = arc_kinds[rot:] + arc_kinds[:rot]

        # Assemble exact world-coordinate polygon (for bbox, origin, size & exact border spans)
        world_poly: list[tuple[float, float]] = []
        arc_seg_lengths: list[float] = []
        for a in arcs:
            pts = a["pts"]
            # Each arc contributes pts[0 .. -2]; closing segment connects last point to next arc's pts[0]
            seg_len = polyline_len(pts)
            arc_seg_lengths.append(seg_len)
            world_poly.extend(pts[:-1])

        xs_p = [p[0] for p in world_poly]
        ys_p = [p[1] for p in world_poly]
        # Clean integer origin & size fitting Atlas.SIZE_CLASSES with 2-tile padding
        ox = int(math.floor(min(xs_p))) - 2
        oy = int(math.floor(min(ys_p))) - 2
        max_x = int(math.ceil(max(xs_p))) + 2
        max_y = int(math.ceil(max(ys_p))) + 2
        sw = max_x - ox
        sh = max_y - oy
        sclass = size_class_for(sw, sh)

        # Build JSON footprint array:
        # Each arc emits its starting junction J0_local, followed by either coastal interior points or {"seam": sid}.
        fp_json: list[Any] = []
        for a in arcs:
            j0 = a["j0"]
            fp_json.append([round(j0[0] - ox, 1), round(j0[1] - oy, 1)])
            if a["seam_id"] is not None:
                fp_json.append({"seam": a["seam_id"]})
            else:
                for pt in a["pts"][1:-1]:
                    fp_json.append([round(pt[0] - ox, 1), round(pt[1] - oy, 1)])

        # Build exact perimeter-share borders covering [0.0 .. 1.0]
        total_p = sum(arc_seg_lengths)
        borders_json: list[dict[str, Any]] = []
        acc = 0.0
        for idx_a, (ak, slen) in enumerate(zip(arc_kinds, arc_seg_lengths)):
            f_sh = round(acc / total_p, 6)
            acc += slen
            t_sh = 1.0 if idx_a == len(arc_kinds) - 1 else round(acc / total_p, 6)
            if t_sh <= f_sh + 1e-6:
                continue
            # Merge adjacent identical border kinds (except keep rift/water attributes intact)
            if (
                borders_json
                and borders_json[-1]["kind"] == ak
                and ak not in ("water", "void_edge")
            ):
                borders_json[-1]["to"] = t_sh
            else:
                bentry: dict[str, Any] = {"kind": ak, "from": f_sh, "to": t_sh}
                if ak == "cliff":
                    bentry["height_px"] = 48.0
                elif ak == "water" and zid == "windkap":
                    bentry["regime"] = "ocean"
                    bentry["drift_offshore_tiles"] = 14.0
                elif ak == "forest_sea":
                    bentry["depth"] = 5
                    bentry["mix"] = [
                        {"species": "valley_oak", "w": 0.55, "stages": [2, 3, 4, 5]},
                        {"species": "silver_birch", "w": 0.35, "stages": [2, 3, 4]},
                        {"species": "wild_apple", "w": 0.10, "stages": [2, 3, 4]},
                    ]
                elif ak == "void_edge" and zid == "varnholm":
                    bentry["rift"] = "der_grosse_riss"
                borders_json.append(bentry)
        # Ensure exact 0.0 and 1.0 endpoints
        borders_json[0]["from"] = 0.0
        borders_json[-1]["to"] = 1.0

        zones_built[zid] = {
            "meta": z,
            "origin": (ox, oy),
            "size": (sw, sh),
            "size_class": sclass,
            "world_poly": world_poly,
            "fp_json": fp_json,
            "borders_json": borders_json,
            "arcs": arcs,
        }

    # 4. Handcraft WINDKAP interior coordinates (relative to its exact new footprint & shore!)
    wk = zones_built["windkap"]
    wk_ox, wk_oy = wk["origin"]
    wk_sw, wk_sh = wk["size"]
    wk_poly = wk["world_poly"]
    # Land-only polygon of Windkap (using land_main pixels of windkap) for placing land POIs safely inside coastline!
    wk_land_poly = trace_single_mask_contour(z_grid == 1, step=3.0)
    wly, wlx = np.nonzero(z_grid == 1)
    wk_land_center = (float(wlx.mean()), float(wly.mean()))
    wk_lx0, wk_lx1 = float(wlx.min()) - wk_ox, float(wlx.max()) - wk_ox
    wk_ly0, wk_ly1 = float(wly.min()) - wk_oy, float(wly.max()) - wk_oy
    wk_lw, wk_lh = wk_lx1 - wk_lx0, wk_ly1 - wk_ly0

    def wk_pt(fx: float, fy: float, margin: float = 6.0) -> list[float]:
        """Maps normalized Windkap land coords (fx, fy in 0..1) -> safe local [x, y] inside both footprint & coastline."""
        wx_p = wk_ox + wk_lx0 + fx * wk_lw
        wy_p = wk_oy + wk_ly0 + fy * wk_lh
        clamped = _clamp_inside((wx_p, wy_p), wk_land_poly, wk_land_center, margin=margin)
        return [round(clamped[0] - wk_ox, 1), round(clamped[1] - wk_oy, 1)]

    def wk_poly_local(norm_pts: list[tuple[float, float]], margin: float = 3.0) -> list[list[float]]:
        out = [wk_pt(fx, fy, margin=margin) for fx, fy in norm_pts]
        # Ensure CW winding
        if signed_area([(p[0], p[1]) for p in out]) < 0:
            out.reverse()
        return out

    # Find exact midpoints of Windkap's 3 seams for blockers & connecting paths
    def seam_mid_for(za: str, zb: str) -> tuple[float, float]:
        for s in seams_by_id.values():
            if {s["a"], s["b"]} == {za, zb}:
                return point_along(s["pts"], 0.5)
        raise RuntimeError(f"Missing expected seam between {za} and {zb}!")

    mid_wk_klip = seam_mid_for("windkap", "klippenstieg")
    mid_wk_erl = seam_mid_for("windkap", "erlenfurt")
    mid_wk_sued = seam_mid_for("windkap", "suedkap")

    # Pull each blocker 1.4 tiles inward into Windkap from its seam midpoint (guaranteed <= 2.5 tiles & inside footprint+coast!)
    def blocker_local(mid_w: tuple[float, float]) -> list[float]:
        vx, vy = wk_land_center[0] - mid_w[0], wk_land_center[1] - mid_w[1]
        vn = max(math.hypot(vx, vy), 1.0)
        cand = (mid_w[0] + (vx / vn) * 1.4, mid_w[1] + (vy / vn) * 1.4)
        if not point_in_poly(cand, wk_land_poly):
            cand = (mid_w[0] + (vx / vn) * 2.1, mid_w[1] + (vy / vn) * 2.1)
        return [round(cand[0] - wk_ox, 1), round(cand[1] - wk_oy, 1)]

    blk_klip = blocker_local(mid_wk_klip)
    blk_erl = blocker_local(mid_wk_erl)
    blk_sued = blocker_local(mid_wk_sued)

    # Handcrafted Windkap shore_pts in local coords (sorted NW -> W cape -> SE along the entire sea coast!)
    wk_shore_local = [[round(p[0] - wk_ox, 1), round(p[1] - wk_oy, 1)] for p in wk_shore_world[::3]]
    if wk_shore_world:
        first_s = [round(wk_shore_world[0][0] - wk_ox, 1), round(wk_shore_world[0][1] - wk_oy, 1)]
        last_s = [round(wk_shore_world[-1][0] - wk_ox, 1), round(wk_shore_world[-1][1] - wk_oy, 1)]
        if wk_shore_local[0] != first_s:
            wk_shore_local.insert(0, first_s)
        if wk_shore_local[-1] != last_s:
            wk_shore_local.append(last_s)

    # Anchor coastal camp right behind the sandy beach curve of Die Silberbucht
    # Find middle of Silberbucht southern bay shore
    shore_mid_w = point_along(wk_bay_shore_world, 0.42)
    camp_w = _clamp_inside((shore_mid_w[0] - 8.0, shore_mid_w[1] - 18.0), wk_land_poly, wk_land_center, margin=8.0)
    camp_loc = [round(camp_w[0] - wk_ox, 1), round(camp_w[1] - wk_oy, 1)]
    campfire_loc = [round(camp_loc[0] + 4.0, 1), round(camp_loc[1] - 1.5, 1)]
    seat_loc = [round(camp_loc[0] + 6.5, 1), round(camp_loc[1] - 0.5, 1)]
    camp_chest_loc = [round(camp_loc[0] - 2.5, 1), round(camp_loc[1] - 3.5, 1)]
    sword_loc = [round(camp_loc[0] + 2.0, 1), round(camp_loc[1] + 2.0, 1)]
    axe_loc = [round(camp_loc[0] + 7.5, 1), round(camp_loc[1] - 2.5, 1)]

    # Das Windkap stepped headland (west cape overlooking Silberbucht & open sea!)
    headland_loc = wk_pt(0.16, 0.72, margin=14.0)
    ruin_loc = [round(headland_loc[0], 1), round(headland_loc[1], 1)]
    tablet_loc = [round(headland_loc[0] + 6.0, 1), round(headland_loc[1] + 4.0, 1)]
    vista_loc = [round(headland_loc[0] - 9.0, 1), round(headland_loc[1] + 5.0, 1)]
    # Verify vista & tablet inside land
    vista_w = _clamp_inside((wk_ox + vista_loc[0], wk_oy + vista_loc[1]), wk_land_poly, wk_land_center, margin=5.0)
    vista_loc = [round(vista_w[0] - wk_ox, 1), round(vista_w[1] - wk_oy, 1)]

    # NW Klippenstieg cliff plateau center
    nw_cliff_loc = wk_pt(0.24, 0.30, margin=18.0)

    # Waystone in Der Wächterhain (north-central)
    waystone_loc = wk_pt(0.49, 0.25, margin=14.0)

    # Natural meandering Erlenbach brook inside Windkap (from NE Erlenfurt seam -> under stone bridge -> Silberbucht!)
    brook_mouth_w = point_along(wk_bay_shore_world, 0.58)
    brook_ctrl_w = [
        (mid_wk_erl[0] - 4.0, mid_wk_erl[1] + 2.0),
        (wk_ox + wk_lx0 + 0.78 * wk_lw, wk_oy + wk_ly0 + 0.36 * wk_lh),
        (wk_ox + wk_lx0 + 0.68 * wk_lw, wk_oy + wk_ly0 + 0.49 * wk_lh),
        (wk_ox + wk_lx0 + 0.61 * wk_lw, wk_oy + wk_ly0 + 0.62 * wk_lh),
        (wk_ox + wk_lx0 + 0.59 * wk_lw, wk_oy + wk_ly0 + 0.74 * wk_lh),
        (brook_mouth_w[0] + 2.0, brook_mouth_w[1] - 4.0),
        (brook_mouth_w[0], brook_mouth_w[1] + 10.0),
    ]
    brook_sm_w = catmull_open(brook_ctrl_w, step=14.0)
    n_bk = len(brook_sm_w)
    wk_brook_world: list[tuple[float, float, float]] = []
    wk_brook_pts_local: list[list[float]] = []
    wk_brook_elevs: list[float] = []
    for i, (bx, by) in enumerate(brook_sm_w):
        t = i / max(n_bk - 1, 1)
        elev_b = round(5.4 * (1.0 - t) ** 1.15, 2)
        if i == n_bk - 1:
            elev_b = 0.0
        # Gentle organic width ramp (world px radius: 22 -> 34 at bridge -> 48 at sandy estuary; NO circular pool!)
        rad_px = round(22.0 + 18.0 * t + 10.0 * (t ** 2.4), 1)
        wk_brook_world.append((bx, by, elev_b))
        wk_brook_pts_local.append([round(bx - wk_ox, 1), round(by - wk_oy, 1), rad_px])
        wk_brook_elevs.append(elev_b)

    # Bridge & ford right on the Erlenbach centerline!
    bridge_w = point_along([(p[0], p[1]) for p in brook_sm_w], 0.56)
    bridge_loc = [round(bridge_w[0] - wk_ox, 1), round(bridge_w[1] - wk_oy, 1)]
    ford_w = point_along([(p[0], p[1]) for p in brook_sm_w], 0.28)
    ford_loc = [round(ford_w[0] - wk_ox, 1), round(ford_w[1] - wk_oy, 1)]

    # 5. Compute lakes, interconnected rivers, coastal trumpet estuaries, continental SDF & 4-level relief!
    print("[ALTMARK] Computing inland lakes, interconnected rivers & flared coastal estuaries...")
    land_filled_raw = land_main | islets_mask
    in_coast_d_raw = chamfer_distance(land_filled_raw)

    lakes_mask, lakes_sdf, water_rgb, river_dist, estuary_open_mask, lake_entries, rivers_json = build_lakes_and_rivers(
        X, Y, land_main, in_coast_d_raw, (wk_ox, wk_oy), wk_brook_world
    )

    # Carve flared trumpet estuaries directly out of continental_sdf so rivers and ocean form ONE continuous body of water!
    land_for_sdf = (land_main & (~estuary_open_mask)) | islets_mask
    in_coast_d = chamfer_distance(land_for_sdf)
    out_coast_d = chamfer_distance(~land_for_sdf)
    signed_coast = np.where(land_for_sdf, in_coast_d, -out_coast_d)
    continental_sdf = np.clip(np.rint(128.0 + signed_coast * 8.0), 0, 255).astype(np.uint8)
    print(
        f"  [hydro] lakes={len(lake_entries)}, rivers={len(rivers_json)}, "
        f"wet_tiles={int((water_rgb[..., 0] > 10).sum())}, estuary_open_tiles={int(estuary_open_mask.sum())}"
    )

    print("[ALTMARK] Assigning nearest-coast region & biome to offshore islets...")
    islet_reg, islet_bio = assign_islet_biomes(land_main, islets_mask, z_grid, islets_json, rift_center)

    print("[ALTMARK] Baking exact 4-level morphological relief & smooth contour field...")
    windkap_features = {
        "origin": (wk_ox, wk_oy),
        "headland_center": headland_loc,
        "nw_cliff_center": nw_cliff_loc,
        "camp_tile": camp_loc,
        "waystone_tile": waystone_loc,
    }
    relief_rgba, field_rgb, lvl = build_continental_relief(
        X, Y, land_main & (~estuary_open_mask), islets_mask, z_grid, islet_reg, islet_bio, lakes_mask, in_coast_d, river_dist, windkap_features, rift_center
    )

    # 6. Build continental_areas.png (R=region_id 0..5, G=zone_id 0..11 & 12=islet, B=biome_id 0..7)
    areas_rgb = np.zeros((H, W, 3), dtype=np.uint8)
    for z in ZONES_META:
        m = (z_grid == z["znum"]) & (~estuary_open_mask)
        areas_rgb[m, 0] = REGION_AREA_ID[z["region"]]
        areas_rgb[m, 1] = z["znum"]
        areas_rgb[m, 2] = REGION_BIOME_IDX[z["region"]] + 1
    # Offshore islets inherit their nearest mainland coast's exact region (R) and biome+1 (B), keeping G=12!
    areas_rgb[islets_mask, 0] = islet_reg[islets_mask].astype(np.uint8)
    areas_rgb[islets_mask, 1] = 12
    areas_rgb[islets_mask, 2] = (islet_bio[islets_mask] + 1).astype(np.uint8)

    # Write all 6 baked continental PNGs!
    BAKED_MAIN_DIR.mkdir(parents=True, exist_ok=True)
    Image.fromarray(continental_sdf, mode="L").save(BAKED_MAIN_DIR / "continental_sdf.png", compress_level=1)
    Image.fromarray(relief_rgba, mode="RGBA").save(BAKED_MAIN_DIR / "continental_relief.png", compress_level=1)
    Image.fromarray(field_rgb, mode="RGB").save(BAKED_MAIN_DIR / "continental_field.png", compress_level=1)
    Image.fromarray(water_rgb, mode="RGB").save(BAKED_MAIN_DIR / "continental_water.png", compress_level=1)
    Image.fromarray(lakes_sdf, mode="L").save(BAKED_MAIN_DIR / "continental_lakes_sdf.png", compress_level=1)
    Image.fromarray(areas_rgb, mode="RGB").save(BAKED_MAIN_DIR / "continental_areas.png", compress_level=1)
    print(f"[ALTMARK] Wrote 6 baked continental maps to {BAKED_MAIN_DIR.relative_to(ROOT)}")

    # 7. Handcrafted Windkap places, stands, rocky/cliffs, puzzles, chests, 8 veil threads!
    def _place_blob(center_l: list[float], rx: float, ry: float, seed_p: int, n_pts: int = 8) -> list[list[float]]:
        pts_p: list[list[float]] = []
        rng_p = np.random.default_rng(seed_p)
        ph1, ph2 = float(rng_p.uniform(0, 6.28)), float(rng_p.uniform(0, 6.28))
        for k in range(n_pts):
            ang = 2.0 * math.pi * k / n_pts
            wob = 1.0 + 0.14 * math.sin(2.0 * ang + ph1) + 0.08 * math.cos(3.0 * ang + ph2)
            wx_p = wk_ox + center_l[0] + math.cos(ang) * rx * wob
            wy_p = wk_oy + center_l[1] + math.sin(ang) * ry * wob
            cl = _clamp_inside((wx_p, wy_p), wk_land_poly, wk_land_center, margin=4.0)
            pts_p.append([round(cl[0] - wk_ox, 1), round(cl[1] - wk_oy, 1)])
        if signed_area([(p[0], p[1]) for p in pts_p]) < 0:
            pts_p.reverse()
        return pts_p

    # Construct the 6 named places of Windkap cleanly covering the whole zone (satisfying Dichteregel <= 150!)
    # 1. Die Silberbucht: follows the sandy crescent shoreline behind the beach!
    sb_top: list[list[float]] = []
    sb_bot: list[list[float]] = []
    for sh_f in (0.14, 0.30, 0.48, 0.66, 0.84):
        sp_w = point_along(wk_bay_shore_world, sh_f)
        p_in = _clamp_inside((sp_w[0], sp_w[1] - 28.0), wk_land_poly, wk_land_center, margin=5.0)
        p_sh = _clamp_inside((sp_w[0], sp_w[1] - 5.0), wk_land_poly, wk_land_center, margin=3.5)
        sb_top.append([round(p_in[0] - wk_ox, 1), round(p_in[1] - wk_oy, 1)])
        sb_bot.append([round(p_sh[0] - wk_ox, 1), round(p_sh[1] - wk_oy, 1)])
    silberbucht_poly = sb_top + list(reversed(sb_bot))
    if signed_area([(p[0], p[1]) for p in silberbucht_poly]) < 0:
        silberbucht_poly.reverse()

    das_windkap_poly = _place_blob(headland_loc, 26.0, 22.0, 601, n_pts=7)
    apfeltrift_center = wk_pt(0.41, 0.56, margin=16.0)
    apfeltrift_poly = _place_blob(apfeltrift_center, 34.0, 26.0, 603, n_pts=8)
    waechterhain_poly = _place_blob([waystone_loc[0] - 8.0, waystone_loc[1] + 6.0], 46.0, 28.0, 605, n_pts=8)
    erlenbach_poly = _place_blob([bridge_loc[0], bridge_loc[1] + 2.0], 22.0, 32.0, 607, n_pts=7)
    kronen_center = wk_pt(0.80, 0.48, margin=16.0)
    kronensaum_poly = _place_blob(kronen_center, 32.0, 36.0, 609, n_pts=8)

    windkap_places = [
        {"id": "silberbucht",  "name": "DIE SILBERBUCHT", "mood": "windkap_coast",    "mood_amount": 0.80, "poly": silberbucht_poly},
        {"id": "das_windkap",  "name": "DAS WINDKAP",     "mood": "windkap_headland", "mood_amount": 0.85, "poly": das_windkap_poly},
        {"id": "erlenbach",    "name": "DER ERLENBACH",   "mood": "windkap_brook",    "mood_amount": 0.65, "poly": erlenbach_poly},
        {"id": "apfeltrift",   "name": "DIE APFELTRIFT",  "mood": "windkap_orchard",  "mood_amount": 0.70, "poly": apfeltrift_poly},
        {"id": "waechterhain", "name": "DER WÄCHTERHAIN", "mood": "windkap_grove",    "mood_amount": 0.85, "poly": waechterhain_poly},
        {"id": "kronensaum",   "name": "DER KRONENSAUM",  "mood": "forest_glade",     "mood_amount": 0.65, "poly": kronensaum_poly},
    ]
    place_poly_map = {pl["id"]: [(p[0], p[1]) for p in pl["poly"]] for pl in windkap_places}

    def _safe_in_place(pid: str, pref_l: list[float]) -> list[float]:
        pp = place_poly_map[pid]
        cx = sum(p[0] for p in pp) / len(pp)
        cy = sum(p[1] for p in pp) / len(pp)
        pt = _clamp_inside((pref_l[0], pref_l[1]), pp, (cx, cy), margin=2.5)
        wpt = _clamp_inside((pt[0] + wk_ox, pt[1] + wk_oy), wk_land_poly, wk_land_center, margin=4.0)
        cand = (round(wpt[0] - wk_ox, 1), round(wpt[1] - wk_oy, 1))
        if point_in_poly(cand, pp):
            return [cand[0], cand[1]]
        return [round(cx, 1), round(cy, 1)]

    # 8 Veil Threads strictly inside their declared places!
    sb_west = [round((sb_top[0][0] + sb_bot[0][0]) * 0.5 + 4.0, 1), round((sb_top[0][1] + sb_bot[0][1]) * 0.5, 1)]
    sb_east = [round((sb_top[-1][0] + sb_bot[-1][0]) * 0.5 - 4.0, 1), round((sb_top[-1][1] + sb_bot[-1][1]) * 0.5, 1)]
    windkap_veil_threads = [
        {"id": "windkap_thread_1", "tile": _safe_in_place("das_windkap",  [headland_loc[0] - 8.0, headland_loc[1] - 8.0]),  "place": "das_windkap",  "hint": "Am Felsvorsprung hinter dem alten Leuchtturm"},
        {"id": "windkap_thread_2", "tile": _safe_in_place("silberbucht",  sb_west),                                           "place": "silberbucht",  "hint": "Zwischen Treibholz am Westrand der Silberbucht"},
        {"id": "windkap_thread_3", "tile": _safe_in_place("waechterhain", [waystone_loc[0] - 30.0, waystone_loc[1] + 10.0]), "place": "waechterhain", "hint": "Auf einer windumtosten Geröllstufe am Klippenpfad"},
        {"id": "windkap_thread_4", "tile": _safe_in_place("apfeltrift",   [apfeltrift_center[0], apfeltrift_center[1]]),      "place": "apfeltrift",   "hint": "Im Schatten des alten wilden Apfelbaums"},
        {"id": "windkap_thread_5", "tile": _safe_in_place("waechterhain", [waystone_loc[0] - 2.0, waystone_loc[1] - 10.0]),  "place": "waechterhain", "hint": "Im Moosring hinter der Wächterin der Bucht"},
        {"id": "windkap_thread_6", "tile": _safe_in_place("erlenbach",    [bridge_loc[0] + 6.0, bridge_loc[1] + 14.0]),       "place": "erlenbach",    "hint": "Am Schilfufer des klaren Erlenbachs"},
        {"id": "windkap_thread_7", "tile": _safe_in_place("kronensaum",   [kronen_center[0] + 4.0, kronen_center[1] - 12.0]), "place": "kronensaum",   "hint": "Auf einer versteckten Lichtung im Kronensaum"},
        {"id": "windkap_thread_8", "tile": _safe_in_place("silberbucht",  sb_east),                                           "place": "silberbucht",  "hint": "An den östlichen Dünen vor dem Dornenwall"},
    ]

    # Stepped Windkap rocky terraces & cliffs (matching the continental_relief plateaus on Das Windkap & NW Klippen!)
    nw_poly_1 = _place_blob(nw_cliff_loc, 32.0, 26.0, 621, n_pts=9)
    nw_poly_2 = _place_blob(nw_cliff_loc, 23.0, 18.0, 623, n_pts=7)
    nw_poly_3 = _place_blob([nw_cliff_loc[0] - 2.0, nw_cliff_loc[1] - 2.0], 13.0, 10.0, 625, n_pts=6)
    hd_poly_1 = _place_blob(headland_loc, 25.0, 21.0, 627, n_pts=7)
    hd_poly_2 = _place_blob(headland_loc, 16.0, 13.0, 629, n_pts=6)

    wk_rocky = [
        {"poly": nw_poly_1, "height": 0.24},
        {"poly": nw_poly_2, "height": 0.38},
        {"poly": nw_poly_3, "height": 0.50},
        {"poly": hd_poly_1, "height": 0.22},
        {"poly": hd_poly_2, "height": 0.35},
    ]

    # Cliffs metadata (quarry trail climbing the NW cliff, boulders clear of all POIs!)
    q_pts = catmull_open([
        (nw_cliff_loc[0] + 8.0, nw_cliff_loc[1] + 24.0),
        (nw_cliff_loc[0] + 15.0, nw_cliff_loc[1] + 14.0),
        (nw_cliff_loc[0] + 16.0, nw_cliff_loc[1] + 4.0),
        (nw_cliff_loc[0] + 8.0, nw_cliff_loc[1] - 2.0),
    ], step=3.5)
    wk_cliffs = {
        "bounds": [
            max(4, int(nw_cliff_loc[0] - 38)),
            max(4, int(nw_cliff_loc[1] - 30)),
            80,
            72,
        ],
        "highland_polys": [nw_poly_1, hd_poly_1],
        "bedrock_shelves": [
            {"center": nw_cliff_loc, "radii": [18, 12], "strength": 0.92},
            {"center": headland_loc, "radii": [16, 11], "strength": 0.88},
        ],
        "scree_fans": [
            {"center": [round(nw_cliff_loc[0] + 12.0, 1), round(nw_cliff_loc[1] + 16.0, 1)], "radii": [14, 10], "strength": 0.78},
        ],
        "quarry_trails": [[[round(p[0], 1), round(p[1], 1)] for p in q_pts]],
        "moss_pockets": [
            {"center": [round(nw_cliff_loc[0] + 22.0, 1), round(nw_cliff_loc[1] + 4.0, 1)], "radii": [10, 7], "strength": 0.75},
        ],
        "rocks": [
            {"tile": [round(nw_cliff_loc[0] - 12.0, 1), round(nw_cliff_loc[1] - 8.0, 1)], "stage": 3, "seed": 1101},
            {"tile": [round(nw_cliff_loc[0] + 4.0, 1), round(nw_cliff_loc[1] + 8.0, 1)], "stage": 2, "seed": 1102},
            {"tile": [round(nw_cliff_loc[0] + 18.0, 1), round(nw_cliff_loc[1] - 10.0, 1)], "stage": 4, "seed": 1103},
            {"tile": [round(nw_cliff_loc[0] - 16.0, 1), round(nw_cliff_loc[1] + 14.0, 1)], "stage": 2, "seed": 1104},
        ],
    }

    # Chests & Puzzles (safely inside land & away from rocks!)
    klippen_truhe = _safe_in_place("waechterhain", [nw_cliff_loc[0] + 20.0, nw_cliff_loc[1] + 12.0])
    kronen_truhe = _safe_in_place("kronensaum", [kronen_center[0] + 12.0, kronen_center[1] + 2.0])
    wisp_start = _safe_in_place("kronensaum", [kronen_center[0] - 12.0, kronen_center[1] - 10.0])
    wisp_route = [
        wisp_start,
        _safe_in_place("kronensaum", [kronen_center[0] - 4.0, kronen_center[1] - 2.0]),
        _safe_in_place("kronensaum", [kronen_center[0] + 4.0, kronen_center[1] + 6.0]),
        _safe_in_place("kronensaum", [kronen_center[0] + 10.0, kronen_center[1] + 14.0]),
        _safe_in_place("kronensaum", [kronen_center[0] + 14.0, kronen_center[1] + 20.0]),
    ]
    hoard_tile = _safe_in_place("apfeltrift", [apfeltrift_center[0] + 12.0, apfeltrift_center[1] - 4.0])
    hoard_mound = _safe_in_place("apfeltrift", [apfeltrift_center[0] + 20.0, apfeltrift_center[1] - 10.0])

    # Handcrafted organic Windkap stands (in continent coordinates!)
    def _org_stand_world(cx_w: float, cy_w: float, rx: float, ry: float, seed_st: int, n_pts: int = 16) -> list[list[float]]:
        rng_s = np.random.default_rng(seed_st)
        a2, a3, a4 = rng_s.uniform(0.10, 0.22, 3)
        p2, p3, p4 = rng_s.uniform(0.0, 6.28, 3)
        out = []
        for k in range(n_pts):
            ang = 2.0 * math.pi * k / n_pts
            r_mod = 1.0 + a2 * math.sin(2 * ang + p2) + a3 * math.sin(3 * ang + p3) + a4 * math.cos(4 * ang + p4)
            px = cx_w + math.cos(ang) * rx * r_mod
            py = cy_w + math.sin(ang) * ry * r_mod
            out.append([round(px, 1), round(py, 1)])
        return out

    wk_stands: list[dict[str, Any]] = [
        {
            "id": "windkap_waechterhain",
            "name": "DER WÄCHTERHAIN",
            "soil": True,
            "spacing": 5.0,
            "edge": 5.5,
            "seed": 211,
            "mix": [
                {"species": "valley_oak", "w": 0.56, "stages": [3, 4, 5]},
                {"species": "silver_birch", "w": 0.44, "stages": [2, 3, 4]},
            ],
            "outline": _org_stand_world(wk_ox + waystone_loc[0] + 6.0, wk_oy + waystone_loc[1] + 2.0, 44.0, 28.0, 711, n_pts=16),
            "glades": [
                _org_stand_world(wk_ox + waystone_loc[0], wk_oy + waystone_loc[1], 12.0, 10.0, 713, n_pts=10),
            ],
        },
        {
            "id": "windkap_apfeltrift",
            "name": "DIE APFELTRIFT",
            "soil": False,
            "spacing": 9.2,
            "edge": 0.0,
            "seed": 223,
            "mix": [{"species": "wild_apple", "w": 1.0, "stages": [2, 3, 4, 4]}],
            "outline": _org_stand_world(wk_ox + apfeltrift_center[0], wk_oy + apfeltrift_center[1], 32.0, 22.0, 719, n_pts=12),
            "glades": [],
        },
        {
            "id": "kronenforst_suedwest",
            "name": "DER KRONENFORST",
            "soil": True,
            "spacing": 5.2,
            "edge": 6.5,
            "seed": 237,
            "mix": [
                {"species": "valley_oak", "w": 0.62, "stages": [3, 4, 5]},
                {"species": "silver_birch", "w": 0.30, "stages": [2, 3, 4]},
                {"species": "wild_apple", "w": 0.08, "stages": [2, 3]},
            ],
            "outline": _org_stand_world(wk_ox + kronen_center[0] + 24.0, wk_oy + kronen_center[1] + 8.0, 56.0, 54.0, 727, n_pts=18),
            "glades": [],
        },
    ]

    # Build all continental organic forest stands
    print("[ALTMARK] Sculpting organic multi-lobed forest stands...")
    all_stands = build_organic_forest_stands(
        X, Y, land_main, z_grid, lvl, in_coast_d, lakes_mask, river_dist, wk_stands, rift_center
    )
    print(f"  [forests] total stands={len(all_stands)}")

    # 8. Build Thresholds (1 threshold on every shared seam of sufficient length!)
    thresholds_json: list[dict[str, Any]] = []
    # Map windkap blockers explicitly
    wk_threshold_defs = {
        frozenset(("windkap", "klippenstieg")): {
            "id": "windkap_klippenstieg", "kind": "pass", "mask": "cliff",
            "open": {"flag": "windkap_pass_open"},
            "closed_reason": "Ein gewaltiger Felssturz versperrt den Klippenstieg.",
            "blocker": "rockfall", "span": [0.35, 0.65],
        },
        frozenset(("windkap", "erlenfurt")): {
            "id": "windkap_erlenfurt", "kind": "path", "mask": "canopy",
            "open": {"flag": "windkap_erlenfurt_open"},
            "closed_reason": "Das alte Steinsetzertor nach Erlenfurt ist eingestürzt.",
            "blocker": "collapsed_gate", "span": [0.35, 0.65],
        },
        frozenset(("windkap", "suedkap")): {
            "id": "windkap_suedkap", "kind": "path", "mask": "canopy",
            "open": {"flag": "windkap_suedkap_open"},
            "closed_reason": "Ein dichter Wall aus Dornen und Wurzeln blockiert den Küstenpfad.",
            "blocker": "bramble_wall", "span": [0.35, 0.65],
        },
    }

    seen_pairs: set[frozenset[str]] = set()
    for sid, sdata in seams_by_id.items():
        za, zb = sdata["a"], sdata["b"]
        pair = frozenset((za, zb))
        if pair in seen_pairs:
            continue
        # Only place walkable thresholds on substantial borders (>= 24 tiles long); tiny corner contacts remain closed seams
        if pair not in wk_threshold_defs and sdata["length"] < 24.0:
            continue
        seen_pairs.add(pair)
        if pair in wk_threshold_defs:
            td = dict(wk_threshold_defs[pair])
            td["a"] = "windkap"
            td["b"] = zb if za == "windkap" else za
            td["seam"] = sid
            thresholds_json.append(td)
        else:
            sk = sdata["kind"]
            tkind = "pass" if sk in ("cliff", "ridge") else ("bridge" if pair == frozenset(("erlenfurt", "glimmrast")) else "path")
            tmask = "cliff" if sk in ("cliff", "ridge") else ("void" if "varnholm" in pair else "canopy")
            thresholds_json.append({
                "id": f"{za}_{zb}",
                "kind": tkind,
                "a": za,
                "b": zb,
                "seam": sid,
                "span": [0.38, 0.62],
                "mask": tmask,
                "closed_reason": "",
            })

    # 9. Build smooth curved paths (`ways`) in Windkap & across the whole continent!
    def _way(kind: str, seed_w: int, damp: float, ctrl: list[tuple[float, float]]) -> dict[str, Any]:
        sm = catmull_open(ctrl, step=10.0)
        return {
            "kind": kind,
            "seed": seed_w,
            "damp": damp,
            "pts": [[round(p[0], 1), round(p[1], 1)] for p in sm],
        }

    camp_world = (wk_ox + camp_loc[0], wk_oy + camp_loc[1])
    ruin_world = (wk_ox + ruin_loc[0], wk_oy + ruin_loc[1])
    vista_world = (wk_ox + vista_loc[0], wk_oy + vista_loc[1])
    ws_world = (wk_ox + waystone_loc[0], wk_oy + waystone_loc[1])
    bridge_world = (wk_ox + bridge_loc[0], wk_oy + bridge_loc[1])
    apfel_world = (wk_ox + apfeltrift_center[0], wk_oy + apfeltrift_center[1])

    def zone_center(zid: str) -> tuple[float, float]:
        zy, zx = np.nonzero(z_grid == ZONE_BY_ID[zid]["znum"])
        return (float(zx.mean()), float(zy.mean()))

    ways_json = [
        # Windkap: Camp -> Das Windkap ruin & Kapkanzel
        _way("path", 501, 0.15, [camp_world, (camp_world[0] - 28, camp_world[1] - 4), (ruin_world[0] + 18, ruin_world[1] + 16), ruin_world, vista_world]),
        # Windkap: Camp -> Alte Bogenbrücke -> Südkap coastal road
        _way("cart", 502, 0.10, [camp_world, (camp_world[0] + 24, camp_world[1] - 18), bridge_world, (bridge_world[0] + 34, bridge_world[1] + 4), mid_wk_sued, zone_center("suedkap")]),
        # Windkap: Fork -> Apfeltrift -> Wächterhain waystone
        _way("path", 503, 0.12, [(camp_world[0] + 16, camp_world[1] - 12), apfel_world, (apfel_world[0] + 8, (apfel_world[1] + ws_world[1]) * 0.5), ws_world]),
        # Windkap -> Klippenstieg -> Hallgrat -> Kristallgrat western highland road
        _way("trail", 504, 0.08, [ws_world, mid_wk_klip, zone_center("klippenstieg"), zone_center("hallgrat"), zone_center("kristallgrat")]),
        # Windkap -> Erlenfurt -> Glimmrast -> Hexenwald-Saum -> Varnholm trans-continental highway
        _way("path", 505, 0.14, [bridge_world, (bridge_world[0] + 28, bridge_world[1] - 28), mid_wk_erl, zone_center("erlenfurt"), (1075, 965), (1325, 945), zone_center("hexenwald_saum"), (1615, 650)]),
        # Central north-south road: Kristallgrat -> Mühlenaue -> Glimmrast -> Hexenwald-Kern
        _way("path", 506, 0.12, [zone_center("kristallgrat"), (1095, 520), (1165, 665), (1120, 845), (1365, 1085), (1495, 1215)]),
    ]

    # 10. Assemble Windkap complete zone.json!
    # Ocean rect starts right at the southern beach edge (BELOW all dry-land POIs!)
    wk_ocean_y = int(max(p[1] for p in wk_shore_local)) - 2
    wk_zone_json: dict[str, Any] = {
        "_doc": "Spielbare Zone 1: WINDKAP — Wo der Bach ins weite Meer fällt. Alle Koordinaten (außer {\"seam\": id}) sind zonen-lokal relativ zu `origin`.",
        "id": "windkap",
        "name": "WINDKAP",
        "old_name": "KAP DER ALTEN WACHE",
        "subtitle": "Wo der Bach ins weite Meer fällt",
        "continent": "main",
        "region": "suedwestkueste",
        "kind": "coast",
        "size_class": wk["size_class"],
        "origin": [wk_ox, wk_oy],
        "size": [wk_sw, wk_sh],
        "biomes": ["meadow"],
        "mood": "windkap_coast",
        "night": "meadow_default",
        "danger": "ruhig",
        "placeholder": False,
        "curve": False,
        "footprint": wk["fp_json"],
        "borders": wk["borders_json"],
        "places": windkap_places,
        "landmarks": [
            {"id": "windkap_leuchtturm",   "kind": "lighthouse", "name": "DAS STERNENAUGE", "pos": ruin_loc},
            {"id": "windkap_kartentafel",  "kind": "tablet",     "name": "STEINSETZER-KARTENTAFEL",     "pos": tablet_loc},
            {"id": "waechterin_der_bucht", "kind": "waystone",   "name": "WÄCHTERIN DER BUCHT",         "pos": waystone_loc},
            {"id": "erlenbach_bruecke",    "kind": "bridge",     "name": "ALTE BOGENBRÜCKE",            "pos": bridge_loc},
            {"id": "kapkanzel",            "kind": "vista",      "name": "KAPKANZEL AM WINDKAP",        "pos": vista_loc},
        ],
        "nature": {
            "seed": 201,
            "meadow": True,
            "turf": {"accents": 0.08, "kinds": ["tuft", "clump", "clover", "petal", "flower", "bloom"]},
        },
        "camp_tile": camp_loc,
        "spawn": {"camp_tile": camp_loc, "face": [0, 1]},
        "camp": {
            "tile": campfire_loc,
            "campfire_tile": campfire_loc,
            "seat_tile": seat_loc,
            "chest": {"id": "windkap_camp_chest", "tier": "common", "tile": camp_chest_loc, "flip": False},
            "starter_items": [
                {"id": "sword_basic", "tile": sword_loc},
                {"id": "axe_basic", "tile": axe_loc},
            ],
        },
        "ruin": {
            "id": "windkap_ruin",
            "tile": ruin_loc,
            "lighthouse_tile": ruin_loc,
            "tablet": {"id": "windkap_map_tablet", "tile": tablet_loc, "unlocks": "continent_world"},
        },
        "waystones": [
            {"id": "bucht_waechterin", "name": "WÄCHTERIN DER BUCHT", "tile": waystone_loc, "reveal": 16.0, "clear_radius": 5, "paved": True},
        ],
        "vistas": [
            {"id": "windkap_seeblick", "name": "KAPKANZEL AM WINDKAP", "sub": "AUSBLICK ÜBER DAS WEITE MEER",
             "tile": vista_loc, "sector": 3, "variant": 3, "reveal_cells": 24.0, "xp_reward": 12},
        ],
        "water": {
            "coast": {
                "sea_side": -1,
                "shore_pts": wk_shore_local,
                "dry_sand_width": 6.0,
                "swash_margin": 2.5,
                "max_surf_depth": 0.48,
                "headlands": [],
                "ocean_rect": [6, wk_ocean_y, wk_sw - 12, max(24, wk_sh - wk_ocean_y - 4)],
                "shelf_start_x": wk_sw - 48,
                "shelf_width": 14.0,
                "reefs": [],
                "drift_offshore_tiles": 14.0,
                "min_ocean_depth": 0.72,
            },
            "brooks": [
                {
                    "id": "erlenbach",
                    "pts": wk_brook_pts_local,
                    "elevations": wk_brook_elevs,
                    "base_depth": 0.62,
                    "bank_width": 3.0,
                    "bed": 1,
                    "bank_bed": 5,
                    "fords": [{"pos": ford_loc, "radius": 5.0, "depth": 0.22, "bed": 1}],
                    "pools": [],
                }
            ],
            "bridges": [{"id": "erlenbach_bridge", "tile": bridge_loc, "axis": "ew"}],
        },
        "rocky": wk_rocky,
        "cliffs": wk_cliffs,
        "blockers": [
            {"threshold_id": "windkap_klippenstieg", "kind": "rockfall",       "tile": blk_klip, "hint": "Ein gewaltiger Felssturz versperrt den Klippenstieg. [E]"},
            {"threshold_id": "windkap_erlenfurt",    "kind": "collapsed_gate", "tile": blk_erl,  "hint": "Das alte Steinsetzertor nach Erlenfurt ist eingestürzt. [E]"},
            {"threshold_id": "windkap_suedkap",      "kind": "bramble_wall",   "tile": blk_sued, "hint": "Ein dichter Wall aus Dornen und Wurzeln blockiert den Küstenpfad. [E]"},
        ],
        "veil_threads": windkap_veil_threads,
        "chests": [
            {"id": "windkap_klippen_truhe", "tier": "common", "tile": klippen_truhe, "flip": False},
            {"id": "windkap_kronen_truhe",  "tier": "rare",   "tile": kronen_truhe,  "flip": True},
        ],
        "puzzles": [
            {"id": "wisp_kronensaum", "kind": "wisp", "tier": "common", "tile": wisp_start,
             "route": wisp_route, "stops": [1, 2, 3, 4], "linger": [2]},
            {"id": "hoard_windkap_apfeltrift", "kind": "crow_hoard", "tier": "common", "tile": hoard_tile,
             "variant": 1, "mound": hoard_mound},
        ],
        "flora": {
            "bushes": [
                {"kind": "berry_bush", "tile": _safe_in_place("apfeltrift", [apfeltrift_center[0] - 10.0, apfeltrift_center[1] + 12.0])},
                {"kind": "berry_bush", "tile": _safe_in_place("apfeltrift", [apfeltrift_center[0] + 14.0, apfeltrift_center[1] + 14.0])},
                {"kind": "bush",       "tile": _safe_in_place("das_windkap", [headland_loc[0] + 16.0, headland_loc[1] - 6.0])},
                {"kind": "berry_bush", "tile": _safe_in_place("kronensaum", [kronen_center[0] - 10.0, kronen_center[1] - 4.0])},
                {"kind": "bush",       "tile": _safe_in_place("waechterhain", [waystone_loc[0] + 16.0, waystone_loc[1] + 8.0])},
            ],
            "patches": [
                {"kind": "sunbloom",    "center": apfeltrift_center, "radius": 18.0, "count": 14},
                {"kind": "moonbell",    "center": waystone_loc,      "radius": 14.0, "count": 10},
                {"kind": "spark_poppy", "center": [round(camp_loc[0] - 8.0, 1), round(camp_loc[1] - 18.0, 1)], "radius": 14.0, "count": 10},
                {"kind": "cattail",     "center": [round(bridge_loc[0] - 6.0, 1), round(bridge_loc[1] + 14.0, 1)], "radius": 10.0, "count": 12},
                {"kind": "brook_mint",  "center": [round(bridge_loc[0] + 6.0, 1), round(bridge_loc[1] - 12.0, 1)], "radius": 9.0, "count": 9},
                {"kind": "marsh_gold",  "center": [round(bridge_loc[0] - 10.0, 1), round(bridge_loc[1] + 24.0, 1)], "radius": 9.0, "count": 8},
                {"kind": "glowfern",    "center": kronen_center, "radius": 14.0, "count": 10},
                {"kind": "puffseed",    "center": [round(headland_loc[0] + 14.0, 1), round(headland_loc[1] - 10.0, 1)], "radius": 12.0, "count": 8},
            ],
        },
        "wildlife": {
            "species": [
                "rabbit", "crow", "raven", "owl", "hoopoe", "deer", "badger", "fox", "hedgehog",
                "butterfly", "bee", "snail", "ladybug", "woodpecker", "jay", "robin",
                "frog", "dragonfly", "strider", "heron", "otter", "kingfisher", "duck", "shoal",
            ],
            "crow_sites": [
                hoard_tile,
                [round(headland_loc[0] + 8.0, 1), round(headland_loc[1] - 4.0, 1)],
                [round(waystone_loc[0] - 8.0, 1), round(waystone_loc[1] + 6.0, 1)],
            ],
            "pet_corvids": True,
        },
        "night_spawns": {
            "enabled": True,
            "danger": "ruhig",
            "light_fisher": True,
            "species": ["shadow_spider", "light_fisher"],
        },
    }

    # 11. Write all 11 zone.json files!
    for z in ZONES_META:
        zid = z["id"]
        zpath = WORLD_DIR / "zones" / zid / "zone.json"
        zpath.parent.mkdir(parents=True, exist_ok=True)
        if zid == "windkap":
            zobj = wk_zone_json
        else:
            zb = zones_built[zid]
            zobj = {
                "id": zid,
                "name": z["name"],
                "old_name": z["old_name"],
                "subtitle": z["subtitle"],
                "continent": "main",
                "region": z["region"],
                "kind": z["kind"],
                "size_class": zb["size_class"],
                "origin": [zb["origin"][0], zb["origin"][1]],
                "size": [zb["size"][0], zb["size"][1]],
                "biomes": ["meadow"],
                "mood": z["mood"],
                "night": "meadow_default",
                "danger": z["danger"],
                "placeholder": True,
                "curve": False,
                "footprint": zb["fp_json"],
                "borders": zb["borders_json"],
                "places": [],
                "landmarks": [],
                "nature": {
                    "seed": z["seed"],
                    "meadow": z["meadow"],
                    "turf": z["turf"],
                },
            }
        zpath.write_text(json.dumps(zobj, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")

    # 12. Write data/world/continents/main.json
    seams_json = [
        {
            "id": s["id"],
            "a": s["a"],
            "b": s["b"],
            "kind": s["kind"],
            "pts": [[round(p[0], 1), round(p[1], 1)] for p in s["pts"]],
        }
        for s in seams_by_id.values()
    ]
    main_json = {
        "_doc": "ALTMARK (2400x1800 Tiles) — Kompakter, geologisch gegliederter Inselkontinent von Shadowspore 2.0 (lückenlose 11-Zonen-Partition, 4-Stufen-Morphologie-Relief, Seen, Flüsse & Schären; einziger Leerenriss in Varnholm / Leerenblühen).",
        "id": "main",
        "name": "ALTMARK",
        "size": [W, H],
        "regions": [{"id": r["id"], "name": r["name"], "old_name": r["old_name"]} for r in REGIONS],
        "zones": [z["id"] for z in ZONES_META],
        "thresholds": "world/thresholds_main.json",
        "landscape": "world/landscape/main.json",
        "coastline": [[round(p[0], 1), round(p[1], 1)] for p in coastline_poly],
        "islets": islets_json,
        "lakes": [{"id": lk["id"], "name": lk["name"], "center": lk["center"], "poly": lk["poly"]} for lk in lake_entries],
        "ocean": {
            "void_ring": False,
            "margin_tiles": 220,
            "currents": [
                {"id": "west_drift",    "pts": [[165, 1580], [140, 1210], [175, 810], [260, 420], [410, 165]], "strength": 0.8},
                {"id": "south_swell",   "pts": [[290, 1690], [720, 1705], [1220, 1655], [1640, 1690], [2020, 1520]], "strength": 1.0},
                {"id": "north_current", "pts": [[580, 130], [1040, 125], [1480, 130], [1920, 175], [2210, 340]], "strength": 0.7},
                {"id": "east_eddy",     "pts": [[2240, 520], [2265, 880], [2185, 1240], [1995, 1560]], "strength": 0.6},
            ],
        },
        "great_rift": {
            "id": "der_grosse_riss",
            "name": "DER GROSSE RISS",
            "region": "leerenbluehen",
            "zone": "varnholm",
            "void_edge": rift_void_edge,
            "pos": [rift_center[0], rift_center[1]],
            "epicenter": [rift_center[0], rift_center[1]],
        },
        "seams": seams_json,
    }
    (WORLD_DIR / "continents" / "main.json").write_text(
        json.dumps(main_json, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8"
    )

    # 13. Write data/world/thresholds_main.json
    thresholds_doc = {
        "_doc": "Schwellen von ALTMARK. Jede Schwelle liegt auf ihrer gemeinsamen Naht (`seam` + `span`). Die drei Binnen-Schwellen von WINDKAP sind anfangs physisch blockiert (`open.flag` + `closed_reason` + `blocker`).",
        "thresholds": thresholds_json,
    }
    (WORLD_DIR / "thresholds_main.json").write_text(
        json.dumps(thresholds_doc, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8"
    )

    # 14. Write data/world/landscape/main.json
    landscape_doc = {
        "_doc": "Kontinentweite Landschaft von ALTMARK in Kontinent-Tiles (2400x1800). Organische FBM-gelappte Naturwälder ohne Kreise/Donuts, geschwungene Wege, verzweigte Flüsse und Binnenseen.",
        "turf": {
            "forest": {"accents": 0.11, "kinds": ["fern", "mushroom", "tuft", "clump", "stone"]},
        },
        "stands": all_stands,
        "ways": ways_json,
        "rivers": rivers_json,
        "lakes": [{"id": lk["id"], "name": lk["name"], "poly": lk["poly"]} for lk in lake_entries],
        "moss": [
            [round(ws_world[0] - 8.0, 1), round(ws_world[1] + 6.0, 1), 11.0, 8.0],
            [round(bridge_world[0] - 12.0, 1), round(bridge_world[1] - 14.0, 1), 10.0, 7.0],
        ],
        "hollows": [
            [round(bridge_world[0] + 10.0, 1), round(bridge_world[1] + 18.0, 1), 9.0, 6.0],
        ],
        "trees": [
            {"species": "wild_apple", "pos": [round(wk_ox + apfeltrift_center[0], 1), round(wk_oy + apfeltrift_center[1], 1)], "stage": 5, "seed": 9101, "traits": {}},
            {"species": "valley_oak", "pos": [round(ws_world[0] - 14.0, 1), round(ws_world[1] - 8.0, 1)], "stage": 5, "seed": 9102, "traits": {}},
            {"species": "silver_birch", "pos": [round(bridge_world[0] - 14.0, 1), round(bridge_world[1] + 6.0, 1)], "stage": 4, "seed": 9103, "traits": {}},
        ],
    }
    (WORLD_DIR / "landscape" / "main.json").write_text(
        json.dumps(landscape_doc, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8"
    )

    dt = time.perf_counter() - t0
    print(f"[ALTMARK] World build complete in {dt:.2f}s! ({len(seams_json)} seams, {len(thresholds_json)} thresholds)")

    # Optional visual diagnostic preview (renders 1200x900 composite of continent, relief, lakes, rivers, forests, seams & Windkap!)
    if debug_preview is not None:
        _write_debug_preview(
            debug_preview, land_main & (~estuary_open_mask), islets_mask, areas_rgb, z_grid, lvl, relief_rgba,
            lakes_mask, water_rgb, all_stands, seams_by_id, rift_center, wk_zone_json
        )


def _write_debug_preview(
    out_path: pathlib.Path,
    land_main: np.ndarray,
    islets_mask: np.ndarray,
    areas_rgb: np.ndarray,
    z_grid: np.ndarray,
    lvl: np.ndarray,
    relief_rgba: np.ndarray,
    lakes_mask: np.ndarray,
    water_rgb: np.ndarray,
    stands: list[dict[str, Any]],
    seams_by_id: dict[str, dict[str, Any]],
    rift_center: tuple[float, float],
    wk_zone: dict[str, Any],
) -> None:
    """Writes a crisp 1200x900 visual QA preview showing silhouette, regions, 4-level mesas, lakes, rivers, estuaries, islets, forests & seams."""
    # Downsample 2x for quick crisp inspection
    ds = 2
    img = np.zeros((H // ds, W // ds, 3), dtype=np.uint8)
    img[:, :] = (11, 25, 45)  # ocean blue

    lm_ds = land_main[::ds, ::ds]
    reg = areas_rgb[::ds, ::ds, 0]
    lv = lvl[::ds, ::ds]
    kind = (relief_rgba[::ds, ::ds, 1] & 15)
    lk = lakes_mask[::ds, ::ds]
    wat = water_rgb[::ds, ::ds, 0] > 40
    isl = islets_mask[::ds, ::ds]
    land_ds = lm_ds | isl

    # Region palettes (4 tones for L0, L1, L2, L3) — applied identically to mainland AND biome-matched islets!
    pal = {
        1: [(56, 120, 84), (78, 152, 98), (112, 182, 118), (154, 210, 146)],   # suedwestkueste
        2: [(52, 116, 82), (76, 148, 96), (110, 178, 116), (148, 206, 140)],   # gruenland
        3: [(58, 96, 102), (88, 128, 134), (128, 166, 172), (176, 208, 214)],  # glaskamm
        4: [(42, 54, 78),  (62, 78, 106), (88, 106, 136), (118, 138, 168)],    # hexenwald
        5: [(112, 78, 72), (154, 114, 86), (196, 156, 108), (228, 198, 142)],  # leerenbluehen
    }
    for rid in range(1, 6):
        m = land_ds & (reg == rid)
        for k in range(4):
            img[m & (lv == k)] = pal[rid][k]

    # Dark ink on south faces & level transitions
    pad_lv = np.pad(lv, 1, mode="edge")
    edge_lv = land_ds & ((lv != pad_lv[:-2, 1:-1]) | (lv != pad_lv[2:, 1:-1]) | (lv != pad_lv[1:-1, :-2]) | (lv != pad_lv[1:-1, 2:]))
    img[edge_lv] = (17, 11, 28)
    img[kind == FACE] = (28, 22, 42)
    img[kind >= RAMP] = (232, 186, 114)

    # Coastline rim (suppressed in river mouths where river meets open ocean)
    pad_l = np.pad(land_ds, 1, mode="constant", constant_values=False)
    coast_e = land_ds & ((~pad_l[:-2, 1:-1]) | (~pad_l[2:, 1:-1]) | (~pad_l[1:-1, :-2]) | (~pad_l[1:-1, 2:]))
    img[coast_e] = (150, 235, 224)

    # Lakes & rivers drawn seamlessly into carved estuaries
    img[wat] = (46, 118, 132)
    img[lk] = (28, 76, 104)

    pil = Image.fromarray(img, mode="RGB")
    draw = ImageDraw.Draw(pil)

    # Draw forest stand outlines lightly in dark emerald
    for st in stands:
        pts = [(p[0] / ds, p[1] / ds) for p in st["outline"]]
        if len(pts) >= 3:
            draw.polygon(pts, outline=(24, 62, 46))

    # Draw seams as dashed cream lines
    for s in seams_by_id.values():
        pts = [(p[0] / ds, p[1] / ds) for p in s["full_pts"]]
        for i in range(0, len(pts) - 1, 2):
            draw.line([pts[i], pts[i + 1]], fill=(240, 220, 170), width=1)

    # Mark Great Rift in bright magenta
    rx, ry = rift_center[0] / ds, rift_center[1] / ds
    draw.ellipse([rx - 14, ry - 18, rx + 14, ry + 18], outline=(255, 80, 220), width=2)

    # Mark Windkap POIs
    ox, oy = wk_zone["origin"]
    for lm in wk_zone["landmarks"]:
        lx, ly = (ox + lm["pos"][0]) / ds, (oy + lm["pos"][1]) / ds
        draw.ellipse([lx - 3, ly - 3, lx + 3, ly + 3], fill=(255, 230, 120))
    cx, cy = (ox + wk_zone["camp_tile"][0]) / ds, (oy + wk_zone["camp_tile"][1]) / ds
    draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 110, 70))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    pil.save(out_path)
    print(f"[ALTMARK] Wrote debug preview -> {out_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build ALTMARK continent, relief, hydrology & 11 zones.")
    parser.add_argument("--debug-preview", type=str, default=None, help="Optional PNG path for visual QA preview")
    args = parser.parse_args()
    preview = pathlib.Path(args.debug_preview) if args.debug_preview else None
    build_all_world_data(debug_preview=preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
