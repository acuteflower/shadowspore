#!/usr/bin/env python3
"""Bake per-pixel 3D depth & material into Ellie's *_blood.png masks (G = depth, B = material) and export
exact 3D right-arm joints (shoulder, elbow, wrist, fist in GripRig space x20) into data/hero_arm3d.json.

Does NOT touch any colour sprite sheet (player*.png), so hand-tuned eyes and silhouettes stay bit-identical.
Run with NumPy: OPENBLAS_NUM_THREADS=1 python3 tools/art_hero_arm_depth.py [workers]
"""
import json
import math
import multiprocessing as mp
import os
import pathlib
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import art_hero_cast as cast  # noqa: E402
import art_hero_combo as combo  # noqa: E402
import art_hero_fish as fish  # noqa: E402
import art_hero_heavy as heavy  # noqa: E402
import art_hero_standby as standby  # noqa: E402


def write_array(path: pathlib.Path, pixels: np.ndarray) -> None:
    hh, ww, _ = pixels.shape
    raw = b"".join(b"\0" + pixels[y].tobytes() for y in range(hh))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", ww, hh, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def all_sheets() -> dict:
    out = {}
    # main (player.png / player_blood.png)
    frames = []
    for crouch in (False, True):
        for sector in range(8):
            for i in range(h.WALK_FRAMES):
                frames.append((sector, i / h.WALK_FRAMES, "walk", crouch, None))
            for i in range(h.RUN_FRAMES):
                frames.append((sector, i / h.RUN_FRAMES, "walk" if crouch else "run", crouch, None))
            for i in range(h.IDLE_FRAMES):
                frames.append((sector, i / h.IDLE_FRAMES, "idle", crouch, None))
            for i in range(h.JOG_FRAMES):
                frames.append((sector, i / h.JOG_FRAMES, "walk" if crouch else "jog", crouch, None))
    out["main"] = ("player.png", "player_blood.png", h.COLS, 16, frames)

    # attack
    frames = []
    for sector in range(8):
        for step in h.ATTACK_POSES:
            for variant in range(h.ATTACK_LEGS):
                for pose in step:
                    frames.append((sector, 0.0, "attack", False, pose) if variant == 0 else (sector, (variant - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
    out["attack"] = ("player_attack.png", "player_attack_blood.png", h.ATTACK_COLS, 8, frames)

    # combo (4th & 5th learned strike)
    frames = []
    for sector in range(8):
        for block in range(combo.BLOCKS):
            for variant in range(h.ATTACK_LEGS):
                for pose in combo.COMBO_POSES[block]:
                    frames.append((sector, 0.0, "attack", False, pose) if variant == 0 else (sector, (variant - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
    out["combo"] = ("player_combo.png", "player_combo_blood.png", combo.BLOCKS * h.ATTACK_LEGS * h.ATTACK_FRAMES, 8, frames)

    # heavy
    frames = []
    for sector in range(8):
        for variant in range(h.ATTACK_LEGS):
            for pose in heavy.HEAVY_POSES:
                frames.append((sector, 0.0, "attack", False, pose) if variant == 0 else (sector, (variant - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
    out["heavy"] = ("player_heavy.png", "player_heavy_blood.png", heavy.KEYS * h.ATTACK_LEGS, 8, frames)

    # one-second actions
    for name, keys, variants in (
        ("pick", h.PICK_KEYS, 1),
        ("eat", h.EAT_KEYS, h.ATTACK_LEGS),
        ("pull", h.PULL_KEYS, 1),
        ("touch", h.TOUCH_KEYS, 1),
        ("feed", h.FEED_KEYS, 1),
        ("drink", h.DRINK_KEYS, h.ATTACK_LEGS),
    ):
        frames = []
        for sector in range(8):
            for v in range(variants):
                for i in range(h.PICK_FRAMES):
                    pose = h.timeline_pose(keys, (i + 0.5) / h.PICK_FRAMES)
                    frames.append((sector, 0.0, "attack", False, pose) if v == 0 else (sector, (v - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
        out[name] = (f"player_{name}.png", f"player_{name}_blood.png", h.PICK_FRAMES * variants, 8, frames)

    # cast
    frames = []
    for sector in range(8):
        for _clip_name, keys in cast.CLIPS:
            for i in range(h.PICK_FRAMES):
                pose = h.timeline_pose(keys, (i + 0.5) / h.PICK_FRAMES)
                frames.append((sector, 0.0, "attack", False, pose))
    out["cast"] = ("player_cast.png", "player_cast_blood.png", h.PICK_FRAMES * len(cast.CLIPS), 8, frames)

    # fish
    order, _starts = fish.layout()
    frames = []
    for sector in range(8):
        for cname, i in order:
            pose, _rod = fish.sample(cname, i)
            frames.append((sector, 0.0, "attack", False, pose))
    out["fish"] = ("player_fish.png", "player_fish_blood.png", len(order), 8, frames)

    # standby
    frames = []
    for sector in range(8):
        for clip in range(len(standby.CLIPS)):
            for f in range(standby.FRAMES):
                if f in (0, standby.FRAMES - 1):
                    frames.append((sector, 0.0, "idle", False, None))
                else:
                    frames.append((sector, 0.0, "idle", False, dict(h.timeline_pose(standby.KEYS[clip], f / (standby.FRAMES - 1)), standby=True)))
    out["standby"] = ("player_standby.png", "player_standby_blood.png", len(standby.CLIPS) * standby.FRAMES, 8, frames)
    return out


def render_job(job):
    name, idx, sector, t, mode, crouch, pose = job
    yaw = math.pi / 2 - sector * math.pi / 4
    model = h.build(t, mode, crouch, pose)
    depth, code, bl = h.render(model.transform(yaw, model.bob), yaw, model.bob)
    blood_rows = h.to_blood(bl, code, h.LAST_BAND, depth)
    blood_bytes = np.asarray(blood_rows, dtype=np.uint8).tobytes()
    arm3 = [int(round(c * 20.0)) for pt in model.arm3 for c in h.project_3d(model, yaw, pt)]
    return name, idx, blood_bytes, arm3


def main() -> None:
    only = None
    pos_args = []
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1]
        else:
            pos_args.append(a)

    all_sp = all_sheets()
    if only is not None:
        assert only in all_sp, f"Unknown sheet '{only}', expected one of {sorted(all_sp)}"
        specs = {only: all_sp[only]}
    else:
        specs = all_sp

    jobs = []
    buffers = {}
    arm_data = {}
    for name, (_tex_file, _blood_file, cols, rows, frames) in specs.items():
        assert len(frames) == cols * rows, (name, len(frames), cols, rows)
        buffers[name] = np.zeros((rows * h.FH, cols * h.FW, 4), dtype=np.uint8)
        arm_data[name] = [None] * len(frames)
        for idx, args in enumerate(frames):
            jobs.append((name, idx, *args))

    workers = int(pos_args[0]) if pos_args else min(8, os.cpu_count() or 1)
    print(f"Rendering {len(specs)} hero depth blood map(s) + 3D arm rigs ({len(jobs)} frames, {workers} workers)...", flush=True)
    with mp.Pool(workers) as pool:
        for done, (name, idx, blood_bytes, arm3) in enumerate(pool.imap_unordered(render_job, jobs, chunksize=8), 1):
            cols = specs[name][2]
            row, col = divmod(idx, cols)
            y, x = row * h.FH, col * h.FW
            buffers[name][y:y + h.FH, x:x + h.FW] = np.frombuffer(blood_bytes, dtype=np.uint8).reshape(h.FH, h.FW, 4)
            arm_data[name][idx] = arm3
            if done % 500 == 0 or done == len(jobs):
                print(f"  {done}/{len(jobs)}", flush=True)

    for name, (_tex_file, blood_file, _cols, _rows, _frames) in specs.items():
        # Ensure sheet (0, 0) carries the depth-map marker (255, 137, 42, 1)
        if buffers[name][0, 0, 3] == 0:
            buffers[name][0, 0] = (255, 137, 42, 1)
        write_array(h.ROOT / "characters" / blood_file, buffers[name])

    arm3_path = h.ROOT.parent / "data" / "hero_arm3d.json"
    if only is not None and arm3_path.exists():
        arm3_out = json.loads(arm3_path.read_text())
        for name in specs:
            arm3_out["sheets"][specs[name][0]] = {
                "cols": specs[name][2],
                "rows": specs[name][3],
                "data": [v for fr in arm_data[name] for v in fr],
            }
    else:
        arm3_out = {
            "scale": 20,
            "stride": 12,
            "sheets": {
                specs[name][0]: {
                    "cols": specs[name][2],
                    "rows": specs[name][3],
                    "data": [v for fr in arm_data[name] for v in fr],
                }
                for name in specs
            },
        }
    arm3_path.write_text(json.dumps(arm3_out, separators=(",", ":")) + "\n")
    print(f"Done: updated {len(specs)} *_blood.png depth map(s) and data/hero_arm3d.json.", flush=True)


if __name__ == "__main__":
    main()
