#!/usr/bin/env python3
"""Fast parallel multi-style builder for Ellie's custom outfits across all 25 sprite sheets.

Reuses `build_all_specs_and_jobs()` from `tools/art_hero_layers_rebuild.py`, rasterizes the shared
body + prop occlusion buffers ONCE per frame (from the reference `default` mannequin so prone/wake
floor offsets match `assets/characters/<stem>.png` to 1e-12 precision), and renders the `outfit`
layer for all requested outfit styles in a single pass.

Outputs for each `<style>` in `STYLE_IDS` and each of the 25 player sheets `<stem>`:
  - `assets/characters/outfits/<style>/<stem>.png`

Usage:
  py -3 tools/art_hero_outfit_rebuild.py [workers] [style1 style2 ...]
"""
import math
import multiprocessing as mp
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import art_hero3d as hero  # noqa: E402
import hut_lib  # noqa: F401, E402  (deterministic RAMPS order)
import art_hero_carry_stone as _carry_stone  # noqa: F401, E402  (deterministic RAMPS order)
import art_hero_outfit as outfit_mod  # noqa: E402
import art_hero_layers_rebuild as base_rebuild  # noqa: E402
import art_hero_swim as swim  # noqa: E402

outfit_mod.ensure_ramps(hero)
hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
ROOT = hero.ROOT


def _head_center(model: hero.Model) -> np.ndarray:
    for p in model.prims:
        if p.kind == "head":
            return p.c.copy()
    return np.zeros(3)


def _prepare_body_occ(tprims: list) -> tuple:
    b_prims = [p for p in tprims if p.layer in ("body", "body_under", "prop")]
    b_occ_prims = [p for p in tprims if p.layer in ("body", "prop")]
    b_depth, b_code, _ = hero._raster_subset(b_prims)
    b_csub = b_code.reshape(hero.FH, hero.SS, hero.FW, hero.SS).transpose(0, 2, 1, 3).reshape(
        hero.FH, hero.FW, hero.SS * hero.SS
    )
    occ_depth, _, _ = hero._raster_subset(b_occ_prims)
    return b_depth, b_code, b_csub, occ_depth


def _raster_outfit(o_prims: list, shared: tuple) -> np.ndarray:
    if not o_prims:
        return np.zeros((hero.FH, hero.FW, 4), dtype=np.uint8)
    b_depth, b_code, b_csub, occ_depth = shared
    k = len(hero.RAMPS) * 4
    ss = hero.SS
    fh, fw = hero.FH, hero.FW

    bo_depth_occ, o_code, _ = hero._raster_subset(o_prims, occ_depth)
    bo_depth = np.where(o_code >= 0, bo_depth_occ, b_depth)
    bo_code = np.where(o_code >= 0, o_code, b_code)
    bo_csub = bo_code.reshape(fh, ss, fw, ss).transpose(0, 2, 1, 3).reshape(fh, fw, ss * ss)
    bo_dsub = bo_depth.reshape(fh, ss, fw, ss).transpose(0, 2, 1, 3).reshape(fh, fw, ss * ss)
    o_csub = o_code.reshape(fh, ss, fw, ss).transpose(0, 2, 1, 3).reshape(fh, fw, ss * ss)
    b_rem_csub = np.where(o_csub >= 0, -1, b_csub)

    bo_opaque = (bo_csub >= 0).sum(-1)
    bo_solid = bo_opaque >= 6
    bo_dmean = np.where(bo_csub >= 0, bo_dsub, 0.0).sum(-1) / np.maximum(bo_opaque, 1)
    best_o, w_o = hero._best_codes(o_csub, k)
    _, w_b = hero._best_codes(b_rem_csub, k)
    o_solid = bo_solid & ((o_csub >= 0).sum(-1) > 0) & (w_o >= w_b)
    best_o = np.where(o_solid, best_o, -1)
    bo_ink = hero._crease_ink(bo_dmean, bo_solid)
    outfit_rows = hero._rows_from_best(best_o, bo_ink, ~bo_solid)
    return np.asarray(outfit_rows, dtype=np.uint8)


_WORKER_STYLES: tuple[str, ...] = outfit_mod.OUTFIT_IDS


def _init_worker(styles: tuple[str, ...]) -> None:
    global _WORKER_STYLES
    outfit_mod.ensure_ramps(hero)
    _WORKER_STYLES = styles


def render_outfit_job(job: tuple) -> tuple:
    kind = job[0]
    styles = _WORKER_STYLES

    if kind == "std":
        _, name, row, col, fw, fh, ground_row, sector, t, mode, crouch, pose, _wb, _wa = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        yaw = math.pi / 2 - sector * math.pi / 4
        ref_model = hero.build(t, mode, crouch, pose, outfit_id="default", hair_id="default")
        ref_hc = _head_center(ref_model)
        shared = _prepare_body_occ(ref_model.transform(yaw, ref_model.bob))

        out_dict = {}
        for st in styles:
            st_model = hero.build(t, mode, crouch, pose, outfit_id=st, hair_id="none")
            delta = ref_hc - _head_center(st_model)
            o_only = hero.Model()
            for p in st_model.prims:
                if p.layer == "outfit":
                    if float(np.abs(delta).max()) > 1e-6:
                        p.c = p.c + delta
                    o_only.prims.append(p)
            o_arr = _raster_outfit(o_only.transform(yaw, ref_model.bob), shared)
            out_dict[st] = o_arr.tobytes()
        return (name, row, col, out_dict)

    if kind == "story":
        _, name, row, col, fw, fh, ground_row, sector, pose, _wb, wake_mode, empty_frame = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        if empty_frame:
            z = np.zeros((fh, fw, 4), dtype=np.uint8).tobytes()
            return (name, row, col, {st: z for st in styles})

        yaw = math.pi / 2 - sector * math.pi / 4
        ref_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id="default")
        if wake_mode:
            body_prims = [p for p in ref_model.prims if p.kind != "hair" and p.layer != "shield"]
            lowest = min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in body_prims)
            lift = float(pose["floor"]) - lowest
            for p in ref_model.prims:
                p.c = p.c + np.array([0.0, lift, 0.0])
        ref_hc = _head_center(ref_model)
        shared = _prepare_body_occ(ref_model.transform(yaw, 0.0))
        do_fade = pose.get("cut", 0.0) > 0.5

        out_dict = {}
        for st in styles:
            st_model = hero.build(0.0, "attack", False, pose, outfit_id=st, hair_id="none")
            delta = ref_hc - _head_center(st_model)
            o_only = hero.Model()
            for p in st_model.prims:
                if p.layer == "outfit":
                    p.c = p.c + delta
                    o_only.prims.append(p)
            o_arr = _raster_outfit(o_only.transform(yaw, 0.0), shared)
            if do_fade:
                o_arr = base_rebuild._apply_shaft_fade(o_arr, is_blood=False)
            out_dict[st] = o_arr.tobytes()
        return (name, row, col, out_dict)

    if kind == "swim":
        _, name, row, col, fw, fh, ground_row, sector, pose = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        yaw = math.pi / 2 - sector * math.pi / 4
        ref_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id="default")
        ref_hc = _head_center(ref_model)
        ref_tprims = ref_model.transform(yaw, 0.0)
        if not pose.get("dry"):
            swim._cut(ref_tprims, True)
        shared = _prepare_body_occ(ref_tprims)

        out_dict = {}
        for st in styles:
            st_model = hero.build(0.0, "attack", False, pose, outfit_id=st, hair_id="none")
            delta = ref_hc - _head_center(st_model)
            o_only = hero.Model()
            for p in st_model.prims:
                if p.layer == "outfit":
                    p.c = p.c + delta
                    o_only.prims.append(p)
            o_tprims = o_only.transform(yaw, 0.0)
            if not pose.get("dry"):
                swim._cut(o_tprims, True)
            o_arr = _raster_outfit(o_tprims, shared)
            out_dict[st] = o_arr.tobytes()
        return (name, row, col, out_dict)

    raise ValueError(f"Unknown job kind: {kind}")


def main() -> None:
    t0 = time.time()
    args = sys.argv[1:]
    workers = min(12, os.cpu_count() or 4)
    if args and args[0].isdigit():
        workers = int(args.pop(0))
    styles = tuple(args) if args else outfit_mod.OUTFIT_IDS
    for st in styles:
        if st not in outfit_mod.BUILDERS:
            raise SystemExit(f"Unknown outfit id '{st}'. Valid: {outfit_mod.OUTFIT_IDS}")

    specs, jobs, _meta = base_rebuild.build_all_specs_and_jobs()
    print(
        f"Building {len(styles)} outfits {styles} across {len(specs)} sheets ({len(jobs)} frames) with {workers} workers...",
        flush=True,
    )

    buffers: dict[str, dict[str, np.ndarray]] = {st: {} for st in styles}
    for st in styles:
        for name, sp in specs.items():
            h_px, w_px = sp["rows"] * sp["fh"], sp["cols"] * sp["fw"]
            buffers[st][name] = np.zeros((h_px, w_px, 4), dtype=np.uint8)

    with mp.Pool(workers, initializer=_init_worker, initargs=(styles,)) as pool:
        for done, (name, row, col, out_dict) in enumerate(pool.imap_unordered(render_outfit_job, jobs, chunksize=8), 1):
            sp = specs[name]
            fw, fh = sp["fw"], sp["fh"]
            y0, x0 = row * fh, col * fw
            for st, o_b in out_dict.items():
                buffers[st][name][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(o_b, dtype=np.uint8).reshape(fh, fw, 4)
            if done % 1000 == 0 or done == len(jobs):
                print(f"  {done}/{len(jobs)} frames ({time.time() - t0:.1f}s)", flush=True)

    char_dir = ROOT / "characters"
    for st in styles:
        outfit_dir = char_dir / "outfits" / st
        for name, sp in specs.items():
            stem = sp["stem"]
            base_rebuild.write_array(outfit_dir / f"{stem}.png", buffers[st][name])

    print(
        f"Done! Wrote {len(styles) * len(specs)} outfit sheets ({len(styles)} styles x 25 stems) in {time.time() - t0:.1f}s.",
        flush=True,
    )


if __name__ == "__main__":
    main()
