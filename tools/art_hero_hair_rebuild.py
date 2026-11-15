#!/usr/bin/env python3
"""Fast parallel multi-style builder for Ellie's custom hairstyles across all 25 sprite sheets.

Reuses `build_all_specs_and_jobs()` from `tools/art_hero_layers_rebuild.py`, rasterizes the shared
body + torso-shield depth buffers ONCE per frame (from the reference `default` mannequin so prone/wake
floor offsets match `assets/characters/<stem>.png` to 1e-12 precision), and renders `hair_front` + `hair_back`
for all requested hairstyles in a single pass.

Outputs for each `<style>` in `STYLE_IDS` and each of the 25 player sheets `<stem>`:
  - `assets/characters/hair/<style>/<stem>.png`       (Hair front layer)
  - `assets/characters/hair/<style>/<stem>_back.png`  (Hair back layer)

Usage:
  py -3 tools/art_hero_hair_rebuild.py [workers] [style1 style2 ...]
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
import art_hero_hair as hair_mod  # noqa: E402
import art_hero_layers_rebuild as base_rebuild  # noqa: E402
import art_hero_standby as standby  # noqa: E402
import art_hero_swim as swim  # noqa: E402

hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
ROOT = hero.ROOT


def _head_center(model: hero.Model) -> np.ndarray:
    for p in model.prims:
        if p.kind == "head":
            return p.c.copy()
    return np.zeros(3)


def _prepare_body_shield(tprims: list) -> tuple:
    return hero.prepare_hair_shield(tprims)


def _raster_hair_pair(h_prims: list, shared: tuple) -> tuple[np.ndarray, np.ndarray]:
    if not h_prims:
        z = np.zeros((hero.FH, hero.FW, 4), dtype=np.uint8)
        return z, z.copy()
    hf_rows, hb_rows = hero.raster_hair_pair(h_prims, shared)
    return np.asarray(hf_rows, dtype=np.uint8), np.asarray(hb_rows, dtype=np.uint8)


_WORKER_STYLES: tuple[str, ...] = hair_mod.STYLE_IDS


def _init_worker(styles: tuple[str, ...]) -> None:
    global _WORKER_STYLES
    _WORKER_STYLES = styles


def render_hair_job(job: tuple) -> tuple:
    kind = job[0]
    styles = _WORKER_STYLES

    if kind == "std":
        _, name, row, col, fw, fh, ground_row, sector, t, mode, crouch, pose, _wb, _wa = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        yaw = math.pi / 2 - sector * math.pi / 4
        ref_model = hero.build(t, mode, crouch, pose, outfit_id="default", hair_id="default")
        ref_hc = _head_center(ref_model)
        shared = _prepare_body_shield(ref_model.transform(yaw, ref_model.bob))

        out_dict = {}
        for st in styles:
            st_model = hero.build(t, mode, crouch, pose, outfit_id="default", hair_id=st)
            delta = ref_hc - _head_center(st_model)
            if float(np.abs(delta).max()) > 1e-6:
                for p in st_model.prims:
                    if p.layer == "hair":
                        p.c = p.c + delta
            h_only = hero.Model()
            h_only.prims = [p for p in st_model.prims if p.layer == "hair"]
            hf_arr, hb_arr = _raster_hair_pair(h_only.transform(yaw, ref_model.bob), shared)
            out_dict[st] = (hf_arr.tobytes(), hb_arr.tobytes())
        return (name, row, col, out_dict)

    if kind == "story":
        _, name, row, col, fw, fh, ground_row, sector, pose, _wb, wake_mode, empty_frame = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        if empty_frame:
            z = np.zeros((fh, fw, 4), dtype=np.uint8).tobytes()
            return (name, row, col, {st: (z, z) for st in styles})

        yaw = math.pi / 2 - sector * math.pi / 4
        ref_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id="default")
        if wake_mode:
            body_prims = [p for p in ref_model.prims if p.kind != "hair" and p.layer != "shield"]
            lowest = min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in body_prims)
            lift = float(pose["floor"]) - lowest
            for p in ref_model.prims:
                p.c = p.c + np.array([0.0, lift, 0.0])
        ref_hc = _head_center(ref_model)
        shared = _prepare_body_shield(ref_model.transform(yaw, 0.0))
        do_fade = pose.get("cut", 0.0) > 0.5

        out_dict = {}
        for st in styles:
            st_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id=st)
            delta = ref_hc - _head_center(st_model)
            h_only = hero.Model()
            for p in st_model.prims:
                if p.layer == "hair":
                    p.c = p.c + delta
                    h_only.prims.append(p)
            hf_arr, hb_arr = _raster_hair_pair(h_only.transform(yaw, 0.0), shared)
            if do_fade:
                hf_arr = base_rebuild._apply_shaft_fade(hf_arr, is_blood=False)
                hb_arr = base_rebuild._apply_shaft_fade(hb_arr, is_blood=False)
            out_dict[st] = (hf_arr.tobytes(), hb_arr.tobytes())
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
        shared = _prepare_body_shield(ref_tprims)

        out_dict = {}
        for st in styles:
            st_model = hero.build(0.0, "attack", False, pose, outfit_id="default", hair_id=st)
            delta = ref_hc - _head_center(st_model)
            h_only = hero.Model()
            for p in st_model.prims:
                if p.layer == "hair":
                    p.c = p.c + delta
                    h_only.prims.append(p)
            h_tprims = h_only.transform(yaw, 0.0)
            if not pose.get("dry"):
                swim._cut(h_tprims, True)
            hf_arr, hb_arr = _raster_hair_pair(h_tprims, shared)
            out_dict[st] = (hf_arr.tobytes(), hb_arr.tobytes())
        return (name, row, col, out_dict)

    raise ValueError(f"Unknown job kind: {kind}")


def main() -> None:
    t0 = time.time()
    args = sys.argv[1:]
    workers = min(12, os.cpu_count() or 4)
    if args and args[0].isdigit():
        workers = int(args.pop(0))
    styles = tuple(args) if args else hair_mod.STYLE_IDS
    for st in styles:
        if st not in hair_mod.BUILDERS:
            raise SystemExit(f"Unknown hairstyle id '{st}'. Valid: {hair_mod.STYLE_IDS}")

    specs, jobs, _meta = base_rebuild.build_all_specs_and_jobs()
    print(
        f"Building {len(styles)} hairstyles {styles} across {len(specs)} sheets ({len(jobs)} frame-groups) with {workers} workers...",
        flush=True,
    )

    buffers: dict[str, dict[str, dict[str, np.ndarray]]] = {st: {} for st in styles}
    for st in styles:
        for name, sp in specs.items():
            h_px, w_px = sp["rows"] * sp["fh"], sp["cols"] * sp["fw"]
            buffers[st][name] = {
                "hair_front": np.zeros((h_px, w_px, 4), dtype=np.uint8),
                "hair_back": np.zeros((h_px, w_px, 4), dtype=np.uint8),
            }

    with mp.Pool(workers, initializer=_init_worker, initargs=(styles,)) as pool:
        for done, (name, row, col, out_dict) in enumerate(pool.imap_unordered(render_hair_job, jobs, chunksize=8), 1):
            sp = specs[name]
            fw, fh = sp["fw"], sp["fh"]
            y0, x0 = row * fh, col * fw
            for st, (hf_b, hb_b) in out_dict.items():
                buf = buffers[st][name]
                buf["hair_front"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(hf_b, dtype=np.uint8).reshape(fh, fw, 4)
                buf["hair_back"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(hb_b, dtype=np.uint8).reshape(fh, fw, 4)
            if done % 1000 == 0 or done == len(jobs):
                print(f"  {done}/{len(jobs)} frame-groups ({time.time() - t0:.1f}s)", flush=True)

    # Post-process standby sweat glint on hair_front using base player_standby.png skin pixels
    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    sb_body_path = ROOT / "characters" / "player_standby.png"
    sb_body = None
    if sb_body_path.exists():
        from gen_doc_images import read_png
        sb_body = np.asarray(read_png(sb_body_path), dtype=np.uint8)
    for st in styles:
        standby._add_sweat_glint(buffers[st]["standby"]["hair_front"], sb_body)

    # Write all 50 PNGs per hairstyle
    char_dir = ROOT / "characters"
    for st in styles:
        hair_dir = char_dir / "hair" / st
        for name, sp in specs.items():
            stem = sp["stem"]
            buf = buffers[st][name]
            base_rebuild.write_array(hair_dir / f"{stem}.png", buf["hair_front"])
            base_rebuild.write_array(hair_dir / f"{stem}_back.png", buf["hair_back"])

    print(
        f"Done! Wrote {len(styles) * len(specs) * 2} hair sheets ({len(styles)} styles x 25 stems x front/back) in {time.time() - t0:.1f}s.",
        flush=True,
    )


if __name__ == "__main__":
    main()
