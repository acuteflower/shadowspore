#!/usr/bin/env python3
"""Rebuild all 25 Ellie sprite sheets into modular customization layers + blood/depth maps + rig JSONs.

Outputs for every player sheet `<stem>`:
  - `assets/characters/<stem>.png`                    (Base Body mannequin + ground shadow + scene props)
  - `assets/characters/outfits/default/<stem>.png`    (Default plum travel outfit layer)
  - `assets/characters/hair/default/<stem>.png`       (Default silver-lavender hair front layer)
  - `assets/characters/hair/default/<stem>_back.png`  (Default silver-lavender hair back layer)
  - `assets/characters/<stem>_blood.png`              (Blood / bandage / 3D ArmPainter depth map, where applicable)
  - `assets/characters/player_swim_under.png`         (Underwater silhouette for SwimComponent)
  - `data/hero_rig.json`, `data/hero_arm3d.json`, `data/hero_jewelry.json`, `data/wall_climb.json`

Usage:
  python tools/art_hero_layers_rebuild.py [workers]
"""
import json
import math
import multiprocessing as mp
import os
import struct
import sys
import time
import zlib
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import art_hero3d as hero  # noqa: E402
import hut_lib  # noqa: F401, E402  (registers PLANK_W ramp in deterministic order)
import art_hero_carry as carry  # noqa: E402
import art_hero_carry_stone as carry_stone  # noqa: E402  (registers MOON ramp in deterministic order)
import art_hero_emerge as emerge  # noqa: E402
import art_hero_wake as wake  # noqa: E402
import art_hero_faint as faint  # noqa: E402
import art_hero_sit as sit  # noqa: E402
import art_hero_rest as rest  # noqa: E402
import art_hero_stumble as stumble  # noqa: E402
import art_hero_wardrobe as wardrobe  # noqa: E402
import art_hero_climb as climb  # noqa: E402
import art_hero_swim as swim  # noqa: E402
import art_hero_combo as combo  # noqa: E402
import art_hero_heavy as heavy  # noqa: E402
import art_hero_cast as cast  # noqa: E402
import art_hero_step as step_mod  # noqa: E402
import art_hero_fish as fish  # noqa: E402
import art_hero_standby as standby  # noqa: E402
import art_hero_jewelry as jewelry  # noqa: E402

# Restore standard hero constants after module-level imports
hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
ROOT = hero.ROOT


def write_array(path: Path, pixels: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    hh, ww, _ = pixels.shape
    raw = b"".join(b"\0" + pixels[y].tobytes() for y in range(hh))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", ww, hh, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def _apply_shaft_fade(arr: np.ndarray, is_blood: bool = False) -> np.ndarray:
    out = arr.copy()
    fh = out.shape[0]
    for y in range(emerge.GROUND_CUT, fh):
        k = (y - emerge.GROUND_CUT) / emerge.SHAFT_FADE
        if k >= 1.0:
            out[y, :] = 0
        elif not is_blood:
            row = out[y].astype(np.float32)
            mask = row[:, 3] > 0
            row[mask, 0] = np.floor(row[mask, 0] * (1.0 - 0.85 * k))
            row[mask, 1] = np.floor(row[mask, 1] * (1.0 - 0.85 * k))
            row[mask, 2] = np.floor(row[mask, 2] * (1.0 - 0.80 * k))
            row[mask, 3] = np.floor(row[mask, 3] * (1.0 - k))
            out[y] = row.astype(np.uint8)
    return out


def render_job(job: tuple) -> tuple:
    kind = job[0]

    if kind == "std":
        _, name, row, col, fw, fh, ground_row, sector, t, mode, crouch, pose, want_blood, want_arm3 = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        yaw = math.pi / 2 - sector * math.pi / 4
        model = hero.build(t, mode, crouch, pose)
        tprims = model.transform(yaw, model.bob)
        layers = hero.render_layers(tprims, shadow=True)
        blood_b = None
        if want_blood:
            depth, code, bl = hero.render(tprims, yaw, model.bob)
            blood_rows = hero.to_blood(bl, code, hero.LAST_BAND, depth if want_arm3 else None)
            blood_b = np.asarray(blood_rows, dtype=np.uint8).tobytes()
        rig = {k: hero.project(model, yaw, v) for k, v in model.rig.items()}
        arm3 = [int(round(c * 20.0)) for pt in model.arm3 for c in hero.project_3d(model, yaw, pt)] if want_arm3 else None
        return (
            name,
            row,
            col,
            np.asarray(layers["body"], dtype=np.uint8).tobytes(),
            np.asarray(layers["outfit"], dtype=np.uint8).tobytes(),
            np.asarray(layers["hair_front"], dtype=np.uint8).tobytes(),
            np.asarray(layers["hair_back"], dtype=np.uint8).tobytes(),
            blood_b,
            None,
            rig,
            arm3,
        )

    if kind == "story":
        _, name, row, col, fw, fh, ground_row, sector, pose, want_blood, wake_mode, empty_frame = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        if empty_frame:
            z = np.zeros((fh, fw, 4), dtype=np.uint8).tobytes()
            return (name, row, col, z, z, z, z, z if want_blood else None, None, None, None)

        yaw = math.pi / 2 - sector * math.pi / 4
        model = hero.build(0.0, "attack", False, pose)
        lift = 0.0
        shadow = True
        if wake_mode:
            body_prims = [p for p in model.prims if p.kind != "hair" and p.layer != "shield"]
            lowest = min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in body_prims)
            lift = float(pose["floor"]) - lowest
            for p in model.prims:
                p.c = p.c + np.array([0.0, lift, 0.0])
            shadow = not (float(pose.get("bed", 0.0)) > 0.35)

        tprims = model.transform(yaw, 0.0)
        layers = hero.render_layers(tprims, shadow=shadow)
        b_arr = np.asarray(layers["body"], dtype=np.uint8)
        o_arr = np.asarray(layers["outfit"], dtype=np.uint8)
        hf_arr = np.asarray(layers["hair_front"], dtype=np.uint8)
        hb_arr = np.asarray(layers["hair_back"], dtype=np.uint8)

        blood_b = None
        if want_blood:
            blood_transform = None
            if pose.get("pitch"):
                rest_model = hero.build(0.0, "attack", False, dict(pose, pitch=0.0))
                pivot = np.array([0.0, 24.0, 0.0])
                rotation = hero.rot_x(float(pose["pitch"]))
                vis_rest = [p for p in rest_model.prims if p.layer != "shield"] or rest_model.prims
                low = min(
                    float((pivot + rotation @ (p.c - pivot))[1] - np.sqrt((((rotation @ p.R)[1, :] * p.r) ** 2).sum()))
                    for p in vis_rest
                )
                translation = np.array(pose.get("shift", (0, 0, 0)), float) + np.array([0.0, -low + lift, 0.0])
                blood_transform = lambda pts: (pts - pivot - translation) @ rotation + pivot
            use_band = name in ("sit", "rest") or wake_mode
            depth, code, thresholds = hero.render(model.transform(yaw, 0.0), yaw, 0.0, blood_transform)
            bl_rows = hero.to_blood(thresholds, code, hero.LAST_BAND if use_band else None)
            bl_arr = np.asarray(bl_rows, dtype=np.uint8)
            if wake_mode:
                mask = bl_arr[..., 3] > 0
                bl_arr[mask, :3] = 255
            if pose.get("cut", 0.0) > 0.5:
                bl_arr = _apply_shaft_fade(bl_arr, is_blood=True)
            blood_b = bl_arr.tobytes()

        if pose.get("cut", 0.0) > 0.5:
            b_arr = _apply_shaft_fade(b_arr, is_blood=False)
            o_arr = _apply_shaft_fade(o_arr, is_blood=False)
            hf_arr = _apply_shaft_fade(hf_arr, is_blood=False)
            hb_arr = _apply_shaft_fade(hb_arr, is_blood=False)

        return (
            name,
            row,
            col,
            b_arr.tobytes(),
            o_arr.tobytes(),
            hf_arr.tobytes(),
            hb_arr.tobytes(),
            blood_b,
            None,
            None,
            None,
        )

    if kind == "swim":
        _, name, row, col, fw, fh, ground_row, sector, pose = job
        hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, ground_row
        yaw = math.pi / 2 - sector * math.pi / 4
        model = hero.build(0.0, "attack", False, pose)
        prims_a = model.transform(yaw, 0.0)
        if not pose.get("dry"):
            swim._cut(prims_a, True)
        layers = hero.render_layers(prims_a, shadow=False)

        if pose.get("dry"):
            under_arr = np.zeros((fh, fw, 4), dtype=np.uint8)
        else:
            prims_b = model.transform(yaw, 0.0)
            swim._cut(prims_b, False)
            d_b, c_b = hero.render(prims_b)
            under_arr = np.asarray(hero.to_pixels(d_b, c_b, shadow=False), dtype=np.uint8)

        pts = {}
        for key in ("mouth", "ear_a", "ear_b", "hand_l", "hand_r", "neck_a", "neck_b"):
            if key in model.rig:
                pts[key] = hero.project(model, yaw, model.rig[key])
        heights = [round(float(model.rig[k][1]), 2) if k in model.rig else 0.0 for k in ("hand_l", "hand_r", "mouth")]
        return (
            name,
            row,
            col,
            np.asarray(layers["body"], dtype=np.uint8).tobytes(),
            np.asarray(layers["outfit"], dtype=np.uint8).tobytes(),
            np.asarray(layers["hair_front"], dtype=np.uint8).tobytes(),
            np.asarray(layers["hair_back"], dtype=np.uint8).tobytes(),
            None,
            under_arr.tobytes(),
            {"points": pts, "heights": heights},
            None,
        )

    raise ValueError(f"Unknown job kind: {kind}")


def build_all_specs_and_jobs() -> tuple[dict, list, dict]:
    """Returns `(specs, jobs, meta)` for all 25 sheets."""
    specs = {}
    jobs = []
    meta = {}

    def add_spec(name: str, stem: str, cols: int, rows: int, fw: int, fh: int, has_blood: bool, has_arm3: bool = False, has_under: bool = False) -> None:
        specs[name] = {
            "stem": stem,
            "cols": cols,
            "rows": rows,
            "fw": fw,
            "fh": fh,
            "has_blood": has_blood,
            "has_arm3": has_arm3,
            "has_under": has_under,
        }

    # 1. main (player.png)
    add_spec("main", "player", hero.COLS, 16, 48, 56, True, True)
    for crouch in (False, True):
        for s in range(8):
            r = s + 8 * int(crouch)
            for col in range(hero.COLS):
                if col < hero.WALK_FRAMES:
                    m_mode, t = "walk", col / hero.WALK_FRAMES
                elif col < hero.WALK_FRAMES + hero.RUN_FRAMES:
                    m_mode = "walk" if crouch else "run"
                    t = (col - hero.WALK_FRAMES) / hero.RUN_FRAMES
                elif col < hero.WALK_FRAMES + hero.RUN_FRAMES + hero.IDLE_FRAMES:
                    m_mode, t = "idle", (col - hero.WALK_FRAMES - hero.RUN_FRAMES) / hero.IDLE_FRAMES
                else:
                    m_mode = "walk" if crouch else "jog"
                    t = (col - hero.WALK_FRAMES - hero.RUN_FRAMES - hero.IDLE_FRAMES) / hero.JOG_FRAMES
                jobs.append(("std", "main", r, col, 48, 56, 51.0, s, t, m_mode, crouch, None, True, True))

    # 2. attack
    add_spec("attack", "player_attack", hero.ATTACK_COLS, 8, 48, 56, True, True)
    for s in range(8):
        for step_i, poses in enumerate(hero.ATTACK_POSES):
            for var in range(hero.ATTACK_LEGS):
                for key, p in enumerate(poses):
                    col = (step_i * hero.ATTACK_LEGS + var) * hero.ATTACK_FRAMES + key
                    m_mode, t = ("attack", 0.0) if var == 0 else ("walk", (var - 1) / hero.WALK_FRAMES)
                    jobs.append(("std", "attack", s, col, 48, 56, 51.0, s, t, m_mode, False, p if var == 0 else dict(p, pz=0.0), True, True))

    # 3-8. 1s action sheets: pick, eat, pull, feed, drink, touch
    for act_name, keys, variants in (
        ("pick", hero.PICK_KEYS, 1),
        ("eat", hero.EAT_KEYS, hero.ATTACK_LEGS),
        ("pull", hero.PULL_KEYS, 1),
        ("feed", hero.FEED_KEYS, 1),
        ("drink", hero.DRINK_KEYS, hero.ATTACK_LEGS),
        ("touch", hero.TOUCH_KEYS, 1),
    ):
        cols = hero.PICK_FRAMES * variants
        add_spec(act_name, f"player_{act_name}", cols, 8, 48, 56, True, True)
        for s in range(8):
            for var in range(variants):
                for key in range(hero.PICK_FRAMES):
                    p = hero.timeline_pose(keys, (key + 0.5) / hero.PICK_FRAMES)
                    m_mode, t = ("attack", 0.0) if var == 0 else ("walk", (var - 1) / hero.WALK_FRAMES)
                    jobs.append(("std", act_name, s, var * hero.PICK_FRAMES + key, 48, 56, 51.0, s, t, m_mode, False, p if var == 0 else dict(p, pz=0.0), True, True))

    # 9. combo
    combo_cols = combo.BLOCKS * hero.ATTACK_LEGS * hero.ATTACK_FRAMES
    add_spec("combo", "player_combo", combo_cols, 8, 48, 56, True, True)
    for s in range(8):
        col = 0
        for blk in range(combo.BLOCKS):
            for var in range(hero.ATTACK_LEGS):
                for p in combo.COMBO_POSES[blk]:
                    m_mode, t = ("attack", 0.0) if var == 0 else ("walk", (var - 1) / hero.WALK_FRAMES)
                    jobs.append(("std", "combo", s, col, 48, 56, 51.0, s, t, m_mode, False, p if var == 0 else dict(p, pz=0.0), True, True))
                    col += 1

    # 10. heavy
    heavy_cols = heavy.KEYS * hero.ATTACK_LEGS
    add_spec("heavy", "player_heavy", heavy_cols, 8, 48, 56, True, True)
    for s in range(8):
        col = 0
        for var in range(hero.ATTACK_LEGS):
            for p in heavy.HEAVY_POSES:
                m_mode, t = ("attack", 0.0) if var == 0 else ("walk", (var - 1) / hero.WALK_FRAMES)
                jobs.append(("std", "heavy", s, col, 48, 56, 51.0, s, t, m_mode, False, p if var == 0 else dict(p, pz=0.0), True, True))
                col += 1

    # 11. cast
    cast_cols = hero.PICK_FRAMES * len(cast.CLIPS)
    add_spec("cast", "player_cast", cast_cols, 8, 48, 56, True, True)
    for s in range(8):
        col = 0
        for _cname, keys in cast.CLIPS:
            for i in range(hero.PICK_FRAMES):
                p = hero.timeline_pose(keys, (i + 0.5) / hero.PICK_FRAMES)
                jobs.append(("std", "cast", s, col, 48, 56, 51.0, s, 0.0, "attack", False, p, True, True))
                col += 1

    # 12. step (both arms baked, no arm3 needed)
    add_spec("step", "player_step", step_mod.FRAMES, 8, 48, 56, True, False)
    for s in range(8):
        for col, p in enumerate(step_mod.POSES):
            jobs.append(("std", "step", s, col, 48, 56, 51.0, s, 0.0, "attack", False, p, True, False))

    # 13. fish
    fish_order, fish_starts = fish.layout()
    fish_cols = len(fish_order)
    add_spec("fish", "player_fish", fish_cols, 8, 48, 56, True, True)
    fish_rods = []
    for col, (cname, i) in enumerate(fish_order):
        p, rod = fish.sample(cname, i)
        fish_rods.append([round(v, 3) for v in rod])
        for s in range(8):
            jobs.append(("std", "fish", s, col, 48, 56, 51.0, s, 0.0, "attack", False, p, True, True))
    meta["fish"] = (fish_cols, fish_starts, fish_rods)

    # 14. standby
    sb_cols = len(standby.CLIPS) * standby.FRAMES
    add_spec("standby", "player_standby", sb_cols, 8, 48, 56, True, True)
    for s in range(8):
        for clip_i in range(len(standby.CLIPS)):
            for f in range(standby.FRAMES):
                col = clip_i * standby.FRAMES + f
                if f in (0, standby.FRAMES - 1):
                    jobs.append(("std", "standby", s, col, 48, 56, 51.0, s, 0.0, "idle", False, None, True, True))
                else:
                    p = dict(hero.timeline_pose(standby.KEYS[clip_i], f / (standby.FRAMES - 1)), standby=True)
                    jobs.append(("std", "standby", s, col, 48, 56, 51.0, s, 0.0, "idle", False, p, True, True))

    # 15. climb (60x68, GROUND_ROW=63.0)
    climb_clips = [[climb.render_pose(i / (climb.FRAMES - 1), tall) for i in range(climb.FRAMES)] for tall in (False, True)]
    climb_poses = [p for cl in climb_clips for p, _ in cl]
    add_spec("climb", "player_climb", len(climb_poses), 8, 60, 68, True, False)
    for s in range(8):
        for col, p in enumerate(climb_poses):
            jobs.append(("story", "climb", s, col, 60, 68, 63.0, s, p, True, False, False))
    meta["climb_clips"] = climb_clips

    # 16. swim (64x72, GROUND_ROW=46.0)
    add_spec("swim", "player_swim", swim.TOTAL, 8, 64, 72, False, False, has_under=True)
    for cname, count, _fps in swim.CLIPS:
        start_col = swim.STARTS[cname]
        for i in range(count):
            p = swim.FUNCS[cname](i)
            for s in range(8):
                jobs.append(("swim", "swim", s, start_col + i, 64, 72, float(swim.WATER_ROW), s, p))

    # 17. emerge (72x76, 1 row, sector 0)
    em_count = int(round(emerge.DURATION * emerge.FPS))
    add_spec("emerge", "player_emerge", em_count, 1, 72, 76, True, False)
    em_offsets = []
    for i in range(em_count):
        t = (i + 0.5) / emerge.FPS
        if t < emerge.KEYS[0][0] - 0.1:
            em_offsets.append([0.0, 0.0])
            jobs.append(("story", "emerge", 0, i, 72, 76, 51.0, 0, {}, True, False, True))
        else:
            p = emerge.timeline(emerge.KEYS, t)
            em_offsets.append([round(p["anchor"][0], 2), round(p["anchor"][1], 2)])
            jobs.append(("story", "emerge", 0, i, 72, 76, 51.0, 0, p, True, False, False))
    meta["emerge_offsets"] = em_offsets

    # 18. wake (80x64, 1 row, sector 0)
    wake_poses = wake.frame_poses()
    add_spec("wake", "player_wake", len(wake_poses), 1, 80, 64, True, False)
    wake_offsets = []
    for i, p in enumerate(wake_poses):
        wake_offsets.append([round(p["anchor"][0], 2), round(p["anchor"][1], 2)])
        jobs.append(("story", "wake", 0, i, 80, 64, 51.0, 0, p, True, True, False))
    meta["wake_offsets"] = wake_offsets

    # 19. faint (72x76, 2 rows: east=0, west=4)
    faint_count = int(round(faint.DURATION * faint.FPS))
    add_spec("faint", "player_faint", faint_count, 2, 72, 76, True, False)
    for row_i, s in enumerate((0, 4)):
        for i in range(faint_count):
            p = faint.timeline(faint.KEYS, (i + 0.5) / faint.FPS)
            jobs.append(("story", "faint", row_i, i, 72, 76, 51.0, s, p, True, False, False))

    # 20. sit (72x76, 8 rows)
    sit_poses = sit.poses()
    add_spec("sit", "player_sit", len(sit_poses), 8, 72, 76, True, False)
    for s in range(8):
        for i, p in enumerate(sit_poses):
            jobs.append(("story", "sit", s, i, 72, 76, 51.0, s, p, True, False, False))

    # 21. rest (72x76, 8 rows)
    rest_poses = rest.poses()
    add_spec("rest", "player_rest", len(rest_poses), 8, 72, 76, True, False)
    for s in range(8):
        for i, p in enumerate(rest_poses):
            jobs.append(("story", "rest", s, i, 72, 76, 51.0, s, p, True, False, False))
    meta["rest_cols"] = len(rest_poses)

    # 22. carry (72x76, 2 rows: east=0, west=4, no blood)
    carry_poses = carry.LIFT_KEYS + carry.WALK_KEYS
    add_spec("carry", "player_carry", len(carry_poses), 2, 72, 76, False, False)
    for row_i, s in enumerate((0, 4)):
        for i, p in enumerate(carry_poses):
            jobs.append(("story", "carry", row_i, i, 72, 76, 51.0, s, p, False, False, False))

    # 23. carry_stone (72x76, 8 rows, no blood)
    cstone_poses = carry_stone.LIFT_KEYS + carry_stone.WALK_KEYS
    add_spec("carry_stone", "player_carry_stone", len(cstone_poses), 8, 72, 76, False, False)
    for s in range(8):
        for i, p in enumerate(cstone_poses):
            jobs.append(("story", "carry_stone", s, i, 72, 76, 51.0, s, p, False, False, False))

    # 24. stumble (72x76, 8 rows)
    stumble_count = int(round(stumble.DURATION * stumble.FPS))
    add_spec("stumble", "player_stumble", stumble_count, 8, 72, 76, True, False)
    for s in range(8):
        for i in range(stumble_count):
            p = stumble.timeline(stumble.KEYS, (i + 0.5) / stumble.FPS)
            jobs.append(("story", "stumble", s, i, 72, 76, 51.0, s, p, True, False, False))
    meta["stumble_count"] = stumble_count

    # 25. wardrobe (72x76, 1 row, sector 6, no blood)
    wardrobe_count = int(round(wardrobe.DURATION * wardrobe.FPS))
    add_spec("wardrobe", "player_wardrobe", wardrobe_count, 1, 72, 76, False, False)
    for i in range(wardrobe_count):
        p = wardrobe.pose((i + 0.5) / wardrobe.FPS)
        jobs.append(("story", "wardrobe", 0, i, 72, 76, 51.0, 6, p, False, False, False))
    meta["wardrobe_count"] = wardrobe_count

    return specs, jobs, meta


def main() -> None:
    t0 = time.time()
    specs, jobs, meta = build_all_specs_and_jobs()
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else min(12, os.cpu_count() or 4)
    print(f"Rebuilding {len(specs)} layered hero sheets ({len(jobs)} frames) with {workers} workers...", flush=True)

    buffers = {}
    rigs_out = {}
    arm3_out = {}
    swim_pts = {k: [[None] * swim.TOTAL for _ in range(8)] for k in ("mouth", "ear_a", "ear_b", "hand_l", "hand_r")}
    swim_heights = [None] * swim.TOTAL

    for name, sp in specs.items():
        h_px, w_px = sp["rows"] * sp["fh"], sp["cols"] * sp["fw"]
        buffers[name] = {
            "body": np.zeros((h_px, w_px, 4), dtype=np.uint8),
            "outfit": np.zeros((h_px, w_px, 4), dtype=np.uint8),
            "hair_front": np.zeros((h_px, w_px, 4), dtype=np.uint8),
            "hair_back": np.zeros((h_px, w_px, 4), dtype=np.uint8),
        }
        if sp["has_blood"]:
            buffers[name]["blood"] = np.zeros((h_px, w_px, 4), dtype=np.uint8)
        if sp["has_under"]:
            buffers[name]["under"] = np.zeros((h_px, w_px, 4), dtype=np.uint8)
        rigs_out[name] = [None] * (sp["rows"] * sp["cols"])
        if sp["has_arm3"]:
            arm3_out[name] = [None] * (sp["rows"] * sp["cols"])

    with mp.Pool(workers) as pool:
        for done, res in enumerate(pool.imap_unordered(render_job, jobs, chunksize=6), 1):
            name, row, col, b_b, o_b, hf_b, hb_b, bl_b, un_b, rig_d, arm3_d = res
            sp = specs[name]
            fw, fh, cols = sp["fw"], sp["fh"], sp["cols"]
            y0, x0 = row * fh, col * fw
            buf = buffers[name]
            buf["body"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(b_b, dtype=np.uint8).reshape(fh, fw, 4)
            buf["outfit"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(o_b, dtype=np.uint8).reshape(fh, fw, 4)
            buf["hair_front"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(hf_b, dtype=np.uint8).reshape(fh, fw, 4)
            buf["hair_back"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(hb_b, dtype=np.uint8).reshape(fh, fw, 4)
            if bl_b is not None:
                buf["blood"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(bl_b, dtype=np.uint8).reshape(fh, fw, 4)
            if un_b is not None:
                buf["under"][y0:y0 + fh, x0:x0 + fw] = np.frombuffer(un_b, dtype=np.uint8).reshape(fh, fw, 4)
            idx = row * cols + col
            if name == "swim" and rig_d is not None:
                for k in swim_pts:
                    swim_pts[k][row][col] = rig_d["points"].get(k)
                swim_heights[col] = rig_d["heights"]
            elif rig_d is not None:
                rigs_out[name][idx] = rig_d
            if arm3_d is not None:
                arm3_out[name][idx] = arm3_d
            if done % 1000 == 0 or done == len(jobs):
                print(f"  {done}/{len(jobs)} frames ({time.time() - t0:.1f}s)", flush=True)

    # Post-process standby sweat glint on hair_front (referencing body for skin mask)
    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    standby._add_sweat_glint(buffers["standby"]["hair_front"], buffers["standby"]["body"])

    # Post-process climb ground shadow fade at clip ends on body
    climb_body = buffers["climb"]["body"]
    for col in range(2 * climb.FRAMES):
        i = col % climb.FRAMES
        alpha = climb_body[:, col * 60:(col + 1) * 60, 3]
        alpha[alpha == 70] = round(70 * max(0.0, 1.0 - i / 5, 1.0 - (climb.FRAMES - 1 - i) / 5))

    # Write PNGs for all 25 sheets
    char_dir = ROOT / "characters"
    outfit_dir = char_dir / "outfits" / "default"
    hair_dir = char_dir / "hair" / "default"

    for name, sp in specs.items():
        stem = sp["stem"]
        buf = buffers[name]
        write_array(char_dir / f"{stem}.png", buf["body"])
        write_array(outfit_dir / f"{stem}.png", buf["outfit"])
        write_array(hair_dir / f"{stem}.png", buf["hair_front"])
        write_array(hair_dir / f"{stem}_back.png", buf["hair_back"])
        if sp["has_blood"]:
            bl_arr = buf["blood"]
            if sp["has_arm3"] and bl_arr[0, 0, 3] == 0:
                bl_arr[0, 0] = (255, 137, 42, 1)
            write_array(char_dir / f"{stem}_blood.png", bl_arr)
        if sp["has_under"]:
            write_array(char_dir / f"{stem}_under.png", buf["under"])

    # Update data/hero_rig.json
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text()) if rig_path.exists() else {}

    rig.update(
        cols=hero.COLS,
        shoulder=[r["shoulder"] for r in rigs_out["main"]],
        hand=[r["hand"] for r in rigs_out["main"]],
        attack_cols=hero.ATTACK_COLS,
        attack_shoulder=[r["shoulder"] for r in rigs_out["attack"]],
        attack_hand=[r["hand"] for r in rigs_out["attack"]],
    )
    for act_name, variants, has_mouth in (
        ("pick", 1, True),
        ("eat", hero.ATTACK_LEGS, True),
        ("pull", 1, False),
        ("feed", 1, False),
        ("drink", hero.ATTACK_LEGS, True),
        ("touch", 1, False),
    ):
        rig[f"{act_name}_cols"] = hero.PICK_FRAMES
        if variants > 1:
            rig[f"{act_name}_variants"] = variants
        rig[f"{act_name}_shoulder"] = [r["shoulder"] for r in rigs_out[act_name]]
        rig[f"{act_name}_hand"] = [r["hand"] for r in rigs_out[act_name]]
        if has_mouth:
            rig[f"{act_name}_mouth"] = [r["mouth"] for r in rigs_out[act_name]]

    rig.update(
        combo_cols=specs["combo"]["cols"],
        combo_shoulder=[r["shoulder"] for r in rigs_out["combo"]],
        combo_hand=[r["hand"] for r in rigs_out["combo"]],
        heavy_keys=heavy.KEYS,
        heavy_variants=hero.ATTACK_LEGS,
        heavy_shoulder=[r["shoulder"] for r in rigs_out["heavy"]],
        heavy_hand=[r["hand"] for r in rigs_out["heavy"]],
        cast_cols=hero.PICK_FRAMES,
        cast_clips=[cname for cname, _k in cast.CLIPS],
        cast_shoulder=[r["shoulder"] for r in rigs_out["cast"]],
        cast_hand=[r["hand"] for r in rigs_out["cast"]],
        step_frames=step_mod.FRAMES,
        step_shoulder=[r["shoulder"] for r in rigs_out["step"]],
        step_hand=[r["hand"] for r in rigs_out["step"]],
    )

    fish_cols, fish_starts, fish_rods = meta["fish"]
    rig["fish"] = {
        "cols": fish_cols,
        "release": fish.RELEASE,
        "hand": [r["hand"] for r in rigs_out["fish"]],
        "shoulder": [r["shoulder"] for r in rigs_out["fish"]],
        "rod": fish_rods,
        "clips": {
            cname: {"start": fish_starts[cname], "count": fish.CLIPS[cname][0], "fps": fish.CLIPS[cname][1], "loop": fish.CLIPS[cname][2]}
            for cname in fish.CLIPS
        },
    }

    sb_cols = specs["standby"]["cols"]
    rig["standby"] = {
        "frames": standby.FRAMES,
        "fps": standby.FPS,
        "clips": list(standby.CLIPS),
        "cols": sb_cols,
        "hand": [r["hand"] for r in rigs_out["standby"]],
        "shoulder": [r["shoulder"] for r in rigs_out["standby"]],
    }

    # Swim events & rig
    swim_events = {}
    for cname, count, _fps in swim.CLIPS:
        st = swim.STARTS[cname]
        ev = {"enter_l": [], "enter_r": [], "exit_l": [], "exit_r": []}
        for i in range(count):
            prev_h = swim_heights[st + (i - 1) % count]
            cur_h = swim_heights[st + i]
            for idx_s, side in ((0, "l"), (1, "r")):
                if prev_h[idx_s] >= 0.0 > cur_h[idx_s]:
                    ev["enter_" + side].append(i)
                if prev_h[idx_s] < 0.0 <= cur_h[idx_s]:
                    ev["exit_" + side].append(i)
        swim_events[cname] = ev
    rig["swim"] = {
        "frame": [64, 72],
        "water_row": swim.WATER_ROW,
        "total": swim.TOTAL,
        "clips": {cname: {"start": swim.STARTS[cname], "count": count, "fps": fps} for cname, count, fps in swim.CLIPS},
        "events": swim_events,
        "height": swim_heights,
        "points": {k: [[None if p is None else [round(p[0], 1), round(p[1], 1)] for p in r] for r in rows] for k, rows in swim_pts.items()},
    }

    # Story rig entries
    em_offsets = meta["emerge_offsets"]
    rig["emerge"] = {
        "fps": emerge.FPS,
        "frames": len(em_offsets),
        "offset": em_offsets,
        "events": emerge.EVENTS,
        "duration": emerge.DURATION,
    }
    wake_offsets = meta["wake_offsets"]
    rig["wake"] = {
        "fps": wake.FPS,
        "frames": len(wake_offsets),
        "sleep": [0, wake.SLEEP],
        "awake": [wake.SLEEP, wake.AWAKE],
        "getup": [wake.SLEEP + wake.AWAKE, len(wake_offsets) - wake.SLEEP - wake.AWAKE],
        "offset": wake_offsets,
        "events": wake.EVENTS,
        "duration": wake.GETUP_SECONDS,
        "frame_w": wake.FRAME_W,
        "frame_h": wake.FRAME_H,
    }
    rig["faint"] = {"fps": faint.FPS, "frames": specs["faint"]["cols"], "events": faint.EVENTS, "duration": faint.DURATION}
    rig["sit"] = {
        "fps": sit.FPS,
        "down": sit.DOWN,
        "loop": sit.LOOP,
        "loop_fps": 5,
        "take": len(sit.TAKE),
        "hold": len(sit.HOLD),
        "sip": len(sit.SIP),
        "rows": 8,
    }
    rest_meta = {
        "fps": 24,
        "frame_w": 72,
        "frame_h": 76,
        "cols": meta["rest_cols"],
        "rows": 8,
        "down": [0, rest.DOWN],
        "idle": [rest.DOWN, rest.LOOP],
        "idle_fps": 5,
        "gesture_names": list(rest.GESTURE_NAMES),
        "gesture_fps": 12,
        "gesture_wait_min": 5.0,
        "gesture_wait_max": 10.0,
    }
    for i, gname in enumerate(rest.GESTURE_NAMES):
        rest_meta[gname] = [rest.DOWN + rest.LOOP + i * rest.GESTURE, rest.GESTURE]
    rig["rest"] = rest_meta
    rig["carry"] = {"lift": carry.LIFT, "walk": carry.WALK, "lift_fps": carry.FPS_LIFT, "walk_fps": carry.FPS_WALK}
    rig["carry_stone"] = {
        "lift": carry_stone.LIFT,
        "walk": carry_stone.WALK,
        "lift_fps": carry_stone.FPS_LIFT,
        "walk_fps": carry_stone.FPS_WALK,
        "frame": [72, 76],
    }
    rig["stumble"] = {"fps": stumble.FPS, "frames": meta["stumble_count"], "events": stumble.EVENTS, "duration": stumble.DURATION}
    w_count = meta["wardrobe_count"]
    rig["wardrobe"] = {
        "frames": w_count,
        "fps": wardrobe.FPS,
        "duration": wardrobe.DURATION,
        "thud": wardrobe.THUD,
        "stand": [wardrobe.STAND_X, wardrobe.STAND_G],
        "door": [round(math.degrees(wardrobe.door_angle((i + 0.5) / wardrobe.FPS)), 1) for i in range(w_count)],
    }
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")

    # Update data/wall_climb.json
    climb_motion = {"pitch_sine": round(hero.SINP, 5), "clips": [[mv for _, mv in cl] for cl in meta["climb_clips"]]}
    (ROOT.parent / "data" / "wall_climb.json").write_text(json.dumps(climb_motion, separators=(",", ":")) + "\n")

    # Update data/hero_arm3d.json
    arm3_json = {
        "scale": 20,
        "stride": 12,
        "sheets": {
            f"{specs[name]['stem']}.png": {
                "cols": specs[name]["cols"],
                "rows": specs[name]["rows"],
                "data": [v for fr in arm3_out[name] for v in fr],
            }
            for name in arm3_out
        },
    }
    (ROOT.parent / "data" / "hero_arm3d.json").write_text(json.dumps(arm3_json, separators=(",", ":")) + "\n")

    # Update data/hero_jewelry.json
    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    jewelry.main()
    hero.POINTS_ONLY = False

    print(f"All 25 layered sheets, blood/depth maps, and rigs rebuilt in {time.time() - t0:.1f}s!", flush=True)


if __name__ == "__main__":
    main()
