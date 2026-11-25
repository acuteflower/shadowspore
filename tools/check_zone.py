#!/usr/bin/env python3
"""Static validator for a single Shadowspore 2.0 zone (data/world/zones/<id>/zone.json).

Checks:
  1. Schema, size/size_class fit, continent bounds, clockwise winding, moods, catalogs.
  2. Containment of all places, landmarks, camp, ruin, waystones, vistas,
     chests, puzzles, blockers, and veil_threads inside the curved footprint.
  3. Border coverage (valid kinds, strict 1e-4 full 0.0..1.0 perimeter span
     coverage including wrap-around spans, and border-vs-seam consistency).
  4. Threshold reachability (scanline-rasterized walkable grid + BFS flood-fill
     from thresholds to all walkable land and all POIs with r<=1 rock-safe lookup).
  5. Downhill brook elevations and night_spawns species validation.
  6. Density rule (Dichteregel, concept 3.2: <= 150 tiles max gap without place/landmark).
  7. Zone identity checklist (concept 3.3) for non-placeholder zones.

Usage:
  py -3 tools/check_zone.py <id> [--continent <cid>] [--json]
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from collections import deque
from typing import Any

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from check_atlas import (  # noqa: E402
    DANGERS,
    DATA_DIR,
    ROOT,
    SIZE_CLASSES,
    WORLD_DIR,
    ZONE_KINDS,
    bbox,
    build_footprint,
    dist,
    edge_distance,
    load_json,
    point_along,
    point_in_polygon,
    point_to_segment_dist,
    signed_area,
    size_class_for,
    smooth_closed,
    sub_polyline,
)

BORDER_KINDS = {"cliff", "abyss", "forest_sea", "water", "mountain", "ridge", "meadow", "void_edge", "structure"}
PUZZLE_KINDS = {"wisp", "crow_hoard", "raven_trade", "root_weave", "star_mirror", "prism_seal"}
MAX_DENSITY_GAP_TILES = 150.0


def _merge_intervals(spans: list[tuple[float, float]]) -> tuple[list[tuple[float, float]], list[str]]:
    errs: list[str] = []
    if not spans:
        return [], errs
    parts: list[tuple[float, float]] = []
    for a, b in spans:
        if a < -1e-6 or a > 1.0 + 1e-6 or b < -1e-6 or b > 1.0 + 1e-6:
            errs.append(f"border span ({a}, {b}) out of [0.0..1.0]")
            continue
        if abs(a - b) < 1e-9:
            errs.append(f"border span ({a}, {b}) has zero length")
            continue
        a_c = max(0.0, min(1.0, a))
        b_c = max(0.0, min(1.0, b))
        if b_c > a_c:
            parts.append((a_c, b_c))
        else:
            # Wrap-around span [a..1.0] U [0.0..b]
            if a_c < 1.0 - 1e-9:
                parts.append((a_c, 1.0))
            if b_c > 1e-9:
                parts.append((0.0, b_c))
    if not parts:
        return [], errs
    parts.sort()
    merged: list[tuple[float, float]] = []
    for lo, hi in parts:
        if not merged or lo > merged[-1][1] + 1e-4:
            merged.append((lo, hi))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
    return merged, errs


def _border_kinds_at_share(borders: list[dict[str, Any]], share: float) -> list[str]:
    if not borders:
        return []
    ranged = [b for b in borders if "from" in b and "to" in b]
    if not ranged:
        return [str(borders[0].get("kind", ""))]
    s = share % 1.0
    hits: list[str] = []
    for b in ranged:
        fr = float(b["from"])
        to = float(b["to"])
        if fr <= to:
            if fr - 1e-6 <= s <= to + 1e-6:
                hits.append(str(b.get("kind", "")))
        else:
            if s >= fr - 1e-6 or s <= to + 1e-6:
                hits.append(str(b.get("kind", "")))
    return hits


def _scanline_polygon_cells(
    fp: list[tuple[float, float]],
    ox: int,
    oy: int,
    sx: int,
    sy: int,
) -> dict[int, list[tuple[int, int]]]:
    """Return {gy: [(gx_start, gx_end_inclusive), ...]} matching point_in_polygon((ox+gx+0.5, oy+gy+0.5), fp)."""
    n = len(fp)
    edges = [(fp[i], fp[(i + 1) % n]) for i in range(n)]
    rows: dict[int, list[tuple[int, int]]] = {}
    for gy in range(sy):
        wy = oy + gy + 0.5
        xs_int: list[float] = []
        for (x1, y1), (x2, y2) in edges:
            if (y1 > wy) != (y2 > wy):
                x_hit = (x2 - x1) * (wy - y1) / (y2 - y1) + x1
                xs_int.append(x_hit)
        if not xs_int:
            continue
        xs_int.sort()
        spans: list[tuple[int, int]] = []
        for i in range(0, len(xs_int) - 1, 2):
            x_lo = xs_int[i]
            x_hi = xs_int[i + 1]
            # point_in_polygon toggles strictly for x < x_hit -> wx in [x_lo, x_hi)
            gx0 = max(0, math.ceil(x_lo - ox - 0.5))
            gx1 = min(sx - 1, math.ceil(x_hi - ox - 0.5) - 1)
            if gx0 <= gx1:
                spans.append((gx0, gx1))
        if spans:
            rows[gy] = spans
    return rows


def _nearest_walkable_threshold(
    pt: tuple[float, float],
    grid: bytearray,
    ox: int,
    oy: int,
    sx: int,
    sy: int,
) -> tuple[int, int] | None:
    gx = max(0, min(sx - 1, int(round(pt[0] - ox))))
    gy = max(0, min(sy - 1, int(round(pt[1] - oy))))
    if grid[gy * sx + gx]:
        return (gx, gy)
    for r in range(1, 5):
        best: tuple[int, int] | None = None
        best_d = 1e18
        for dy in range(-r, r + 1):
            cy = gy + dy
            if cy < 0 or cy >= sy:
                continue
            row = cy * sx
            for dx in range(-r, r + 1):
                if abs(dx) != r and abs(dy) != r:
                    continue
                cx = gx + dx
                if 0 <= cx < sx and grid[row + cx]:
                    d2 = dx * dx + dy * dy
                    if d2 < best_d:
                        best_d = d2
                        best = (cx, cy)
        if best is not None:
            return best
    return None


def _nearest_walkable_poi(
    pt: tuple[float, float],
    grid: bytearray,
    blocked_rocks: set[tuple[int, int]],
    ox: int,
    oy: int,
    sx: int,
    sy: int,
) -> tuple[int, int] | None:
    gx = max(0, min(sx - 1, int(round(pt[0] - ox))))
    gy = max(0, min(sy - 1, int(round(pt[1] - oy))))
    if (gx, gy) in blocked_rocks:
        return None
    if grid[gy * sx + gx]:
        return (gx, gy)
    best: tuple[int, int] | None = None
    best_d = 1e18
    for dy in (-1, 0, 1):
        cy = gy + dy
        if cy < 0 or cy >= sy:
            continue
        row = cy * sx
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            cx = gx + dx
            if 0 <= cx < sx and grid[row + cx]:
                d2 = dx * dx + dy * dy
                if d2 < best_d:
                    best_d = d2
                    best = (cx, cy)
    return best


def check_zone(zone_id: str, continent_filter: str | None = None) -> dict[str, Any]:
    problems: list[str] = []
    warnings: list[str] = []
    metrics: dict[str, Any] = {"zone_id": zone_id}

    zpath = WORLD_DIR / "zones" / zone_id / "zone.json"
    if not zpath.exists():
        return {"ok": False, "problems": [f"zone file not found: {zpath.relative_to(ROOT)}"], "warnings": [], "metrics": metrics}

    zdata = load_json(zpath)
    cid = continent_filter or str(zdata.get("continent", "main"))
    atlas_data = load_json(WORLD_DIR / "atlas.json")
    moods_data = load_json(WORLD_DIR / "moods.json").get("moods", {})
    trees_data = load_json(DATA_DIR / "trees.json")
    grass_data = load_json(DATA_DIR / "grass_tiles.json")
    plants_data = load_json(DATA_DIR / "plants.json")
    wildlife_data = load_json(DATA_DIR / "wildlife.json")
    river_data = load_json(DATA_DIR / "river_animals.json")
    night_path = DATA_DIR / "night.json"
    enemies_path = DATA_DIR / "enemies.json"
    valid_night_species: set[str] = set()
    if night_path.exists():
        ndata = load_json(night_path)
        for sp in ndata.get("species", []):
            if isinstance(sp, dict) and sp.get("id"):
                valid_night_species.add(str(sp["id"]))
        if isinstance(ndata.get("water"), dict) and ndata["water"].get("id"):
            valid_night_species.add(str(ndata["water"]["id"]))
        if isinstance(ndata.get("elite"), dict) and ndata["elite"].get("species"):
            valid_night_species.add(str(ndata["elite"]["species"]))
    if enemies_path.exists():
        valid_night_species.update(str(k) for k in load_json(enemies_path).keys())

    c_entry = next((c for c in atlas_data.get("continents", []) if c.get("id") == cid), None)
    if c_entry is None:
        return {"ok": False, "problems": [f"continent '{cid}' not found in atlas.json"], "warnings": [], "metrics": metrics}

    cdata = load_json(DATA_DIR / str(c_entry["file"]))
    seams_map = {str(s["id"]): s for s in cdata.get("seams", []) if "id" in s}
    region_ids = {str(r.get("id", "")) for r in cdata.get("regions", []) if isinstance(r, dict)}

    # 1. Header & Size Class
    if str(zdata.get("id", "")) != zone_id:
        problems.append(f"id mismatch: '{zdata.get('id')}' != '{zone_id}'")
    if str(zdata.get("kind", "")) not in ZONE_KINDS:
        problems.append(f"invalid kind '{zdata.get('kind')}'")
    if str(zdata.get("danger", "")) not in DANGERS:
        problems.append(f"invalid danger '{zdata.get('danger')}'")
    if region_ids and str(zdata.get("region", "")) not in region_ids:
        problems.append(f"unknown region '{zdata.get('region')}' in continent '{cid}'")

    origin = zdata.get("origin", [0, 0])
    size = zdata.get("size", [0, 0])
    ox, oy = int(origin[0]), int(origin[1])
    sx, sy = int(size[0]), int(size[1])
    fitted = size_class_for(size)
    if not fitted or fitted != zdata.get("size_class"):
        problems.append(f"size {size} does not fit size_class '{zdata.get('size_class')}' (fits '{fitted}')")

    mood = str(zdata.get("mood", ""))
    if mood and mood not in moods_data:
        problems.append(f"unknown mood '{mood}'")

    raw_fp_pts = [p for p in zdata.get("footprint", []) if isinstance(p, list)]
    if len(raw_fp_pts) >= 2 and raw_fp_pts[0] == raw_fp_pts[-1]:
        problems.append("footprint repeats closing vertex")

    fp = build_footprint(zdata, seams_map, problems)
    if signed_area(fp) <= 0:
        problems.append("footprint winding is not clockwise (signed_area <= 0 in Y-down)")

    xs = [p[0] for p in fp]
    ys = [p[1] for p in fp]
    csize = cdata.get("size", [0, 0])
    if min(xs) < ox - 0.01 or min(ys) < oy - 0.01 or max(xs) > ox + sx + 0.01 or max(ys) > oy + sy + 0.01:
        problems.append(f"footprint exceeds Rect2(origin={origin}, size={size})")
    if min(xs) < 0 or min(ys) < 0 or max(xs) > float(csize[0]) or max(ys) > float(csize[1]):
        problems.append("footprint extends outside continent bounds")

    metrics["area_tiles"] = round(abs(signed_area(fp)), 1)
    metrics["size"] = size
    metrics["size_class"] = zdata.get("size_class")

    # 2. Containment checks for places, landmarks, rocky, highland_polys, and additive objects
    place_polys: list[list[tuple[float, float]]] = []
    place_polys_by_id: dict[str, list[tuple[float, float]]] = {}
    place_centers: list[tuple[float, float]] = []
    poi_points: list[tuple[float, float]] = []
    poi_targets: list[tuple[str, tuple[float, float]]] = []
    land_pois: list[tuple[str, tuple[float, float]]] = []

    for idx, pl in enumerate(zdata.get("places", [])):
        pid = str(pl.get("id", ""))
        raw_poly = pl.get("poly", [])
        if len(raw_poly) < 3:
            problems.append(f"place '{pid}' has <3 vertices")
            continue
        if raw_poly[0] == raw_poly[-1]:
            problems.append(f"place '{pid}' repeats closing vertex")
        ppoly = [(float(pt[0]) + ox, float(pt[1]) + oy) for pt in raw_poly]
        place_polys_by_id[pid] = ppoly
        pxs = [p[0] for p in ppoly]
        pys = [p[1] for p in ppoly]
        center = ((min(pxs) + max(pxs)) * 0.5, (min(pys) + max(pys)) * 0.5)
        if not point_in_polygon(center, fp):
            problems.append(f"place '{pid}' center outside footprint")
        for vidx, pt in enumerate(ppoly):
            if not point_in_polygon(pt, fp):
                problems.append(f"place '{pid}' vertex {vidx} ({pt[0]-ox},{pt[1]-oy}) outside footprint")
            land_pois.append((f"place.{pid}[{vidx}]", pt))
        pmood = str(pl.get("mood", ""))
        if pmood and pmood not in moods_data:
            problems.append(f"place '{pid}' unknown mood '{pmood}'")
        place_polys.append(ppoly)
        place_centers.append(center)
        poi_points.append(center)
        poi_targets.append((f"place.{pid or idx}", center))

    for lm in zdata.get("landmarks", []):
        lid = str(lm.get("id", ""))
        pos = (float(lm["pos"][0]) + ox, float(lm["pos"][1]) + oy)
        if not point_in_polygon(pos, fp):
            problems.append(f"landmark '{lid}' outside footprint")
        poi_points.append(pos)
        poi_targets.append((f"landmark.{lid}", pos))
        land_pois.append((f"landmark.{lid}", pos))

    for ridx, rk in enumerate(zdata.get("rocky", [])):
        if isinstance(rk, dict):
            for vidx, pt_raw in enumerate(rk.get("poly", [])):
                wpt = (float(pt_raw[0]) + ox, float(pt_raw[1]) + oy)
                if not point_in_polygon(wpt, fp) and edge_distance(wpt, fp) > 0.5:
                    problems.append(f"rocky[{ridx}][{vidx}] ({pt_raw[0]},{pt_raw[1]}) outside footprint")
    cliffs_blk = zdata.get("cliffs", {})
    if isinstance(cliffs_blk, dict):
        for hidx, hpoly in enumerate(cliffs_blk.get("highland_polys", [])):
            for vidx, pt_raw in enumerate(hpoly):
                wpt = (float(pt_raw[0]) + ox, float(pt_raw[1]) + oy)
                if not point_in_polygon(wpt, fp) and edge_distance(wpt, fp) > 0.5:
                    problems.append(f"cliffs.highland_polys[{hidx}][{vidx}] ({pt_raw[0]},{pt_raw[1]}) outside footprint")

    def _check_local_pt(label: str, tile_pair: Any, track_reach: bool = True) -> tuple[float, float] | None:
        if not isinstance(tile_pair, list) or len(tile_pair) < 2:
            problems.append(f"{label}: invalid tile coords {tile_pair}")
            return None
        pt = (float(tile_pair[0]) + ox, float(tile_pair[1]) + oy)
        if not point_in_polygon(pt, fp):
            problems.append(f"{label} at {tile_pair} lies outside footprint")
        elif track_reach:
            poi_targets.append((label, pt))
        land_pois.append((label, pt))
        return pt

    is_placeholder = bool(zdata.get("placeholder", False))
    if not is_placeholder:
        if "camp_tile" in zdata:
            pt = _check_local_pt("camp_tile", zdata.get("camp_tile"))
            if pt:
                poi_points.append(pt)
        if "spawn" in zdata:
            pt = _check_local_pt("spawn.camp_tile", zdata["spawn"].get("camp_tile"))
            if pt:
                poi_points.append(pt)
        if "camp" in zdata:
            for k in ("tile", "campfire_tile", "seat_tile"):
                if k in zdata["camp"]:
                    pt = _check_local_pt(f"camp.{k}", zdata["camp"][k])
                    if pt:
                        poi_points.append(pt)
            if "chest" in zdata["camp"]:
                _check_local_pt("camp.chest.tile", zdata["camp"]["chest"].get("tile"))
            for item in zdata["camp"].get("starter_items", []):
                _check_local_pt(f"camp.starter.{item.get('id')}", item.get("tile"))
        if "ruin" in zdata:
            _check_local_pt("ruin.tile", zdata["ruin"].get("tile"))
            _check_local_pt("ruin.lighthouse_tile", zdata["ruin"].get("lighthouse_tile"))
            if "tablet" in zdata["ruin"]:
                pt = _check_local_pt("ruin.tablet.tile", zdata["ruin"]["tablet"].get("tile"))
                if pt:
                    poi_points.append(pt)
        for ws in zdata.get("waystones", []):
            pt = _check_local_pt(f"waystone.{ws.get('id')}", ws.get("tile"))
            if pt:
                poi_points.append(pt)
        for vs in zdata.get("vistas", []):
            pt = _check_local_pt(f"vista.{vs.get('id')}", vs.get("tile"))
            if pt:
                poi_points.append(pt)
        for ch in zdata.get("chests", []):
            pt = _check_local_pt(f"chest.{ch.get('id')}", ch.get("tile"))
            if pt:
                poi_points.append(pt)
        for pz in zdata.get("puzzles", []):
            pkind = str(pz.get("kind", ""))
            if pkind not in PUZZLE_KINDS:
                problems.append(f"puzzle '{pz.get('id')}' has invalid kind '{pkind}'")
            pt = _check_local_pt(f"puzzle.{pz.get('id')}", pz.get("tile"))
            if pt:
                poi_points.append(pt)
        for vt in zdata.get("veil_threads", []):
            pt = _check_local_pt(f"veil_thread.{vt.get('id')}", vt.get("tile"))
            if pt:
                poi_points.append(pt)
                vplace = str(vt.get("place", ""))
                if vplace not in place_polys_by_id:
                    problems.append(f"veil_thread '{vt.get('id')}' references unknown place '{vplace}'")
                elif not point_in_polygon(pt, place_polys_by_id[vplace]):
                    problems.append(f"veil_thread '{vt.get('id')}' at {vt.get('tile')} outside declared place '{vplace}'")
        for bl in zdata.get("blockers", []):
            _check_local_pt(f"blocker.{bl.get('threshold_id')}", bl.get("tile"))

    # Coastline containment check for all land POIs
    raw_coast = cdata.get("coastline", [])
    if isinstance(raw_coast, list) and len(raw_coast) >= 3 and land_pois:
        coast_raw = [(float(p[0]), float(p[1])) for p in raw_coast]
        coast_polys = [coast_raw]
        if len(coast_raw) < 80:
            coast_polys.append(smooth_closed(coast_raw, 4.0))
        for plabel, ppt in land_pois:
            if any(not point_in_polygon(ppt, cp) for cp in coast_polys):
                problems.append(f"land POI {plabel} ({ppt[0]:.1f},{ppt[1]:.1f}) lies outside coastline")

    # 3. Border Coverage & Border-vs-Seam Consistency
    borders = zdata.get("borders", [])
    if not borders:
        problems.append("borders list is empty")
    else:
        spans: list[tuple[float, float]] = []
        require_spans = len(borders) > 1 or not is_placeholder
        has_explicit_spans = require_spans or any("from" in b and "to" in b for b in borders)
        for idx, b in enumerate(borders):
            bkind = str(b.get("kind", ""))
            if bkind not in BORDER_KINDS:
                problems.append(f"border[{idx}] invalid kind '{bkind}'")
            if has_explicit_spans:
                if "from" not in b or "to" not in b:
                    problems.append(f"border[{idx}] missing required from/to span")
                else:
                    spans.append((float(b["from"]), float(b["to"])))
            for m in b.get("mix", []):
                sp = str(m.get("species", ""))
                if sp not in trees_data:
                    problems.append(f"border[{idx}] unknown tree species '{sp}'")
        if has_explicit_spans:
            merged, span_errs = _merge_intervals(spans)
            problems.extend(span_errs)
            if len(merged) != 1 or merged[0][0] > 1e-4 or merged[0][1] < 1.0 - 1e-4:
                problems.append(f"borders spans do not cover 100% of perimeter [0.0..1.0]: {merged}")

        # Border-vs-seam consistency: every seam in footprint must match border kind covering its perimeter share
        n_fp = len(fp)
        if n_fp >= 3:
            cum = [0.0]
            for i in range(n_fp):
                cum.append(cum[-1] + dist(fp[i], fp[(i + 1) % n_fp]))
            tot_perim = max(cum[-1], 1e-6)
            for entry in zdata.get("footprint", []):
                if not isinstance(entry, dict):
                    continue
                sid = str(entry.get("seam", ""))
                if sid not in seams_map:
                    continue
                cut = seams_map[sid]
                skind = str(cut.get("kind", "forest_sea"))
                spts = [(float(p[0]), float(p[1])) for p in cut.get("pts", [])]
                if len(spts) < 2:
                    continue
                # Find indices on fp matching seam start, mid, end (seam points are embedded verbatim in fp)
                for frac in (0.25, 0.5, 0.75):
                    sp = point_along(spts, frac)
                    best_i = min(range(n_fp), key=lambda idx_fp: dist(fp[idx_fp], sp))
                    if dist(fp[best_i], sp) > 1.5:
                        continue
                    sh = cum[best_i] / tot_perim
                    bkinds = _border_kinds_at_share(borders, sh)
                    if bkinds and skind not in bkinds:
                        problems.append(
                            f"border-vs-seam mismatch: seam '{sid}' (kind='{skind}') at share {sh:.4f} falls under border kind {bkinds}"
                        )
                        break

    # Nature, Flora, Wildlife, Night, Downhill Water checks
    nat = zdata.get("nature", {})
    for tk in nat.get("turf", {}).get("kinds", []):
        if tk not in grass_data:
            problems.append(f"nature.turf unknown grass kind '{tk}'")

    flora = zdata.get("flora", {})
    if isinstance(flora, dict):
        for b in flora.get("bushes", []):
            if str(b.get("kind", "")) not in plants_data:
                problems.append(f"flora bush unknown kind '{b.get('kind')}'")
        for pa in flora.get("patches", []):
            if str(pa.get("kind", "")) not in plants_data:
                problems.append(f"flora patch unknown kind '{pa.get('kind')}'")

    wl = zdata.get("wildlife", {})
    if isinstance(wl, dict):
        for sp in wl.get("species", []):
            if sp not in wildlife_data and sp not in river_data:
                problems.append(f"wildlife unknown species '{sp}'")

    ns = zdata.get("night_spawns", {})
    if isinstance(ns, dict) and valid_night_species:
        for sp in ns.get("species", []):
            if str(sp) not in valid_night_species:
                problems.append(f"night_spawns unknown species '{sp}'")

    water_cfg = zdata.get("water", {})
    if isinstance(water_cfg, dict):
        for br in water_cfg.get("brooks", []):
            bid = str(br.get("id", ""))
            elevs = br.get("elevations", [])
            for idx in range(len(elevs) - 1):
                if float(elevs[idx + 1]) > float(elevs[idx]) + 1e-6:
                    problems.append(f"brook '{bid}' flows uphill at index {idx} ({elevs[idx]} -> {elevs[idx+1]})")
            if elevs and float(elevs[-1]) > 0.05 and zdata.get("kind") == "coast":
                problems.append(f"coast brook '{bid}' does not reach sea level (ends at {elevs[-1]})")

    # 4. Thresholds & Reachability Flood-Fill (scanline rasterized)
    trel = str(cdata.get("thresholds", ""))
    zone_thresholds: list[dict[str, Any]] = []
    if trel:
        tdata = load_json(DATA_DIR / trel)
        for t in tdata.get("thresholds", []):
            if t.get("a") == zone_id or t.get("b") == zone_id:
                zone_thresholds.append(t)
    if not zone_thresholds:
        problems.append(f"zone {zone_id} has no thresholds in {trel}")

    # Blocker distance to threshold sub_polyline (<= 2.5 tiles)
    th_lines_by_id: dict[str, list[tuple[float, float]]] = {}
    for t in zone_thresholds:
        tid = str(t.get("id", ""))
        tline = [(float(p[0]), float(p[1])) for p in t.get("line", [])]
        sid = str(t.get("seam", ""))
        if sid and sid in seams_map:
            span = t.get("span", [0.0, 1.0])
            tline = sub_polyline([(float(p[0]), float(p[1])) for p in seams_map[sid]["pts"]], float(span[0]), float(span[1]))
        th_lines_by_id[tid] = tline
    for bl in zdata.get("blockers", []):
        tid = str(bl.get("threshold_id", ""))
        btile = bl.get("tile")
        if not tid or tid not in th_lines_by_id:
            problems.append(f"blocker references unknown threshold '{tid}'")
        elif isinstance(btile, list) and len(btile) >= 2 and len(th_lines_by_id[tid]) >= 2:
            bpt = (float(btile[0]) + ox, float(btile[1]) + oy)
            tline = th_lines_by_id[tid]
            d_line = min(point_to_segment_dist(bpt, tline[k], tline[k + 1]) for k in range(len(tline) - 1))
            if d_line > 2.5:
                problems.append(f"blocker '{tid}' is {d_line:.2f} > 2.5 tiles from threshold line")

    blocked_rocks: set[tuple[int, int]] = set()
    for r in zdata.get("cliffs", {}).get("rocks", []):
        rt = r.get("tile", [])
        if len(rt) >= 2:
            blocked_rocks.add((int(round(rt[0])), int(round(rt[1]))))

    coast_cfg = water_cfg.get("coast", {}) if isinstance(water_cfg, dict) else {}
    shore_pts = [(float(p[0]) + ox, float(p[1]) + oy) for p in coast_cfg.get("shore_pts", [])]
    drift_limit = float(coast_cfg.get("drift_offshore_tiles", 14.0))
    ocean_rect = coast_cfg.get("ocean_rect")
    ocean_y_cut = (oy + float(ocean_rect[1]) + 6.0) if (ocean_rect and shore_pts) else None

    rows_spans = _scanline_polygon_cells(fp, ox, oy, sx, sy)
    grid = bytearray(sx * sy)
    walkable_count = 0
    for gy, gx_ranges in rows_spans.items():
        row_off = gy * sx
        wy = oy + gy + 0.5
        check_ocean = ocean_y_cut is not None and wy > ocean_y_cut
        for gx0, gx1 in gx_ranges:
            span_len = gx1 - gx0 + 1
            grid[row_off + gx0 : row_off + gx1 + 1] = b"\x01" * span_len
            walkable_count += span_len
            if check_ocean:
                for gx in range(gx0, gx1 + 1):
                    wx = ox + gx + 0.5
                    d_shore = min(
                        point_to_segment_dist((wx, wy), shore_pts[i], shore_pts[i + 1])
                        for i in range(len(shore_pts) - 1)
                    )
                    if d_shore > drift_limit + 4.0:
                        grid[row_off + gx] = 0
                        walkable_count -= 1

    for rx, ry in blocked_rocks:
        if 0 <= rx < sx and 0 <= ry < sy and grid[ry * sx + rx]:
            grid[ry * sx + rx] = 0
            walkable_count -= 1

    metrics["walkable_tiles"] = walkable_count

    threshold_seeds: list[tuple[str, tuple[int, int]]] = []
    for t in zone_thresholds:
        tid = str(t.get("id", ""))
        line = [(float(p[0]), float(p[1])) for p in t.get("line", [])]
        sid = str(t.get("seam", ""))
        if sid and sid in seams_map:
            span = t.get("span", [0.0, 1.0])
            line = sub_polyline([(float(p[0]), float(p[1])) for p in seams_map[sid]["pts"]], float(span[0]), float(span[1]))
        if not line:
            continue
        mid = point_along(line, 0.5)
        poi_points.append(mid)
        cell = _nearest_walkable_threshold(mid, grid, ox, oy, sx, sy)
        if cell is None:
            problems.append(f"threshold '{tid}' has no nearby walkable tile inside {zone_id}")
        else:
            threshold_seeds.append((tid, cell))

    if walkable_count > 0 and threshold_seeds:
        start_tid, start_cell = threshold_seeds[0]
        # 1 = unvisited walkable, 2 = reached
        start_idx = start_cell[1] * sx + start_cell[0]
        grid[start_idx] = 2
        reached_count = 1
        q: deque[int] = deque([start_idx])
        total_cells = sx * sy
        while q:
            idx = q.popleft()
            x_cur = idx % sx
            if x_cur + 1 < sx and grid[idx + 1] == 1:
                grid[idx + 1] = 2
                reached_count += 1
                q.append(idx + 1)
            if x_cur > 0 and grid[idx - 1] == 1:
                grid[idx - 1] = 2
                reached_count += 1
                q.append(idx - 1)
            if idx + sx < total_cells and grid[idx + sx] == 1:
                grid[idx + sx] = 2
                reached_count += 1
                q.append(idx + sx)
            if idx >= sx and grid[idx - sx] == 1:
                grid[idx - sx] = 2
                reached_count += 1
                q.append(idx - sx)

        reach_ratio = reached_count / float(walkable_count)
        metrics["reachable_ratio"] = round(reach_ratio, 4)
        if reach_ratio < 0.95:
            problems.append(f"reachability from threshold '{start_tid}' is only {reach_ratio*100:.1f}% (< 95%)")

        for tid, cell in threshold_seeds[1:]:
            if grid[cell[1] * sx + cell[0]] != 2:
                problems.append(f"threshold '{tid}' is NOT reachable from threshold '{start_tid}'")

        if not is_placeholder:
            for label, pt in poi_targets:
                c = _nearest_walkable_poi(pt, grid, blocked_rocks, ox, oy, sx, sy)
                if c is None:
                    problems.append(f"{label} at ({pt[0]-ox:.1f},{pt[1]-oy:.1f}) is blocked/buried in rocks or non-walkable")
                elif grid[c[1] * sx + c[0]] != 2:
                    problems.append(f"{label} at ({pt[0]-ox:.1f},{pt[1]-oy:.1f}) is NOT reachable from thresholds")

    # 5. Density Rule (Dichteregel, §3.2)
    if walkable_count > 0 and poi_points:
        max_gap = 0.0
        max_pt = (0.0, 0.0)
        place_entries = [(bbox(pp), pp) for pp in place_polys]
        for gy in range(0, sy, 2):
            row_off = gy * sx
            wy = oy + gy + 0.5
            for gx in range(0, sx, 2):
                if grid[row_off + gx] == 0:
                    continue
                wx = ox + gx + 0.5
                best = 1e18
                for (bx0, by0, bx1, by1), ppoly in place_entries:
                    dx_b = 0.0 if bx0 <= wx <= bx1 else (bx0 - wx if wx < bx0 else wx - bx1)
                    dy_b = 0.0 if by0 <= wy <= by1 else (by0 - wy if wy < by0 else wy - by1)
                    if dx_b * dx_b + dy_b * dy_b >= best * best:
                        continue
                    d = edge_distance((wx, wy), ppoly)
                    if d < best:
                        best = d
                        if best <= 0.0:
                            break
                if best > 0.0:
                    for p in poi_points:
                        d = dist((wx, wy), p)
                        if d < best:
                            best = d
                if best > max_gap:
                    max_gap = best
                    max_pt = (wx - ox, wy - oy)
        metrics["max_density_gap_tiles"] = round(max_gap, 1)
        metrics["max_density_gap_local"] = [round(max_pt[0], 1), round(max_pt[1], 1)]
        if max_gap > MAX_DENSITY_GAP_TILES:
            msg = f"Dichteregel violated: max gap {max_gap:.1f} tiles at local {metrics['max_density_gap_local']} > {MAX_DENSITY_GAP_TILES}"
            if is_placeholder:
                warnings.append(f"(placeholder) {msg}")
            else:
                problems.append(msg)

    # 6. Zone Identity Checklist (§3.3) for non-placeholder zones
    if not is_placeholder:
        places = zdata.get("places", [])
        if not (3 <= len(places) <= 8):
            problems.append(f"§3.3 #2 places count {len(places)} not in 3..8")
        lms = zdata.get("landmarks", [])
        if not any(lm.get("kind") == "lighthouse" for lm in lms):
            problems.append("§3.3 #1 missing landmark with kind 'lighthouse'")
        has_secret = bool(zdata.get("puzzles")) or bool(zdata.get("chests")) or bool(zdata.get("veil_threads"))
        if not has_secret:
            problems.append("§3.3 #4 missing secret (puzzles/chests/veil_threads)")
        has_vista = bool(zdata.get("vistas")) or any(lm.get("kind") == "vista" for lm in lms)
        if not has_vista:
            problems.append("§3.3 #5 missing vista")
        has_ws = bool(zdata.get("waystones")) or any(lm.get("kind") == "waystone" for lm in lms) or bool(zdata.get("no_waystone_reason"))
        if not has_ws:
            problems.append("§3.3 #6 missing waystone (or no_waystone_reason)")
        if not zdata.get("night") and not zdata.get("night_spawns"):
            problems.append("§3.3 #7 missing night character")
        if not mood:
            problems.append("§3.3 #8 missing mood")

        if zone_id == "windkap":
            vts = zdata.get("veil_threads", [])
            if len(vts) != 8:
                problems.append(f"windkap must have exactly 8 veil_threads, got {len(vts)}")
            bls = zdata.get("blockers", [])
            if len(bls) != 2:
                problems.append(f"windkap must have 2 blocked inland threshold blockers (windkap_suedkap is open), got {len(bls)}")
        elif zone_id == "suedkap":
            vts = zdata.get("veil_threads", [])
            if len(vts) != 8:
                problems.append(f"suedkap must have exactly 8 veil_threads, got {len(vts)}")
            bls = zdata.get("blockers", [])
            if len(bls) != 3:
                problems.append(f"suedkap must have 3 blocked inland threshold blockers, got {len(bls)}")

    return {"ok": len(problems) == 0, "problems": problems, "warnings": warnings, "metrics": metrics}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Shadowspore 2.0 zone(s).")
    parser.add_argument("zone_id", nargs="?", default=None, help="Zone ID under data/world/zones/<id>/zone.json")
    parser.add_argument("--all", action="store_true", help="Validate all zones in the continent (default: main)")
    parser.add_argument("--continent", default=None, help="Override continent id")
    parser.add_argument("--json", action="store_true", help="Output JSON result")
    args = parser.parse_args()

    if args.all:
        cid = args.continent or "main"
        atlas_data = load_json(WORLD_DIR / "atlas.json")
        c_entry = next((c for c in atlas_data.get("continents", []) if c.get("id") == cid), None)
        if c_entry is None:
            print(f"[FAIL] continent '{cid}' not found", file=sys.stderr)
            return 1
        cdata = load_json(DATA_DIR / str(c_entry["file"]))
        zids = [str(z) for z in cdata.get("zones", [])]
        results = [check_zone(zid, continent_filter=cid) for zid in zids]
        all_ok = all(r["ok"] for r in results)
        if args.json:
            print(json.dumps({"ok": all_ok, "results": results}, indent=2, ensure_ascii=False))
        else:
            for r in results:
                zid = r["metrics"]["zone_id"]
                print(f"[INFO] zone '{zid}' metrics: {r['metrics']}")
                for w in r["warnings"]:
                    print(f"[WARN] {w}")
                for p in r["problems"]:
                    print(f"[FAIL] {zid}: {p}", file=sys.stderr)
                if not r["problems"]:
                    print(f"ZONE CHECK OK: {zid} (0 problems)")
        return 0 if all_ok else 1

    if not args.zone_id:
        parser.error("zone_id is required unless --all is specified")

    res = check_zone(args.zone_id, continent_filter=args.continent)
    if args.json:
        print(json.dumps(res, indent=2, ensure_ascii=False))
    else:
        print(f"[INFO] zone '{args.zone_id}' metrics: {res['metrics']}")
        for w in res["warnings"]:
            print(f"[WARN] {w}")
        if res["problems"]:
            for p in res["problems"]:
                print(f"[FAIL] {p}", file=sys.stderr)
            print(f"ZONE CHECK FAILED ({len(res['problems'])} problems)", file=sys.stderr)
        else:
            print(f"ZONE CHECK OK: {args.zone_id} (0 problems)")
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
