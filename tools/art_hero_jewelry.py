#!/usr/bin/env python3
"""Where jewellery hangs on Ellie in every frame of every sheet the player steers (docs/talisman_konzept.md, step 5). Writes data/hero_jewelry.json.
No pixels are rendered (art_hero3d.POINTS_ONLY): the model of each frame is built exactly as the sheet scripts build it and only the rig points are
projected, so this takes seconds and never touches the sheets. Run it again whenever a sheet's poses or the model's body change:

    python3 tools/art_hero_jewelry.py

Per frame 16 integers, feet-relative screen pixels times ten (x right, y down; the game floors x/10 and y/10 to a pixel):
    0-1 collar point A, 2-3 collar point B, 4-5 pendant, 6-7 ear lobe A, 8-9 ear lobe B,
    10-15 how much torso forward, head forward, ear A, ear B, collar A, collar B face the camera, percent (100 = straight at it, negative = away).
Point A is the model's +x side (her left), B the -x side. The game decides what is visible from the facing numbers (an ear is shown when its side faces the camera
and her face is not turned away, the pendant when the torso faces the camera), so no depth buffer is needed.
File layout: {"stride": 16, "sheets": {name: {"cols": columns of the sheet, "rows": rows, "data": [frame 0 ints, frame 1 ints, ...]}}}; frame index = row * cols + col,
the same index the sprite's `frame` has. Sheets: main (player.png), attack, pick, eat, pull, touch, heavy, fish, standby."""
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import art_hero_fish as fish  # noqa: E402
import art_hero_heavy as heavy  # noqa: E402
import art_hero_standby as standby  # noqa: E402

COSP = h.COSP


def ints(rig) -> list:
    out = []
    for key in ("neck_a", "neck_b", "pendant", "ear_a", "ear_b"):
        out += [round(rig[key][0] * 10), round(rig[key][1] * 10)]
    out += [round(v / COSP * 100) for v in rig["jf"]]
    return out


def sheets():
    """{name: (cols, rows, [frame args])} in sprite-frame order (row-major)."""
    out = {}
    # main: rows = crouch * 8 + sector, columns = walk, run, idle, jog
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
    out["main"] = (h.COLS, 16, frames)
    # attack: per sector steps x leg variants x keyframes
    frames = []
    for sector in range(8):
        for step in h.ATTACK_POSES:
            for variant in range(h.ATTACK_LEGS):
                for pose in step:
                    frames.append((sector, 0.0, "attack", False, pose) if variant == 0 else (sector, (variant - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
    out["attack"] = (h.ATTACK_COLS, 8, frames)
    # one-second animations (pick, eat with leg variants, pull, touch)
    for name, keys, variants in (("pick", h.PICK_KEYS, 1), ("eat", h.EAT_KEYS, h.ATTACK_LEGS), ("pull", h.PULL_KEYS, 1), ("touch", h.TOUCH_KEYS, 1)):
        frames = []
        for sector in range(8):
            for v in range(variants):
                for i in range(h.PICK_FRAMES):
                    pose = h.timeline_pose(keys, (i + 0.5) / h.PICK_FRAMES)
                    frames.append((sector, 0.0, "attack", False, pose) if v == 0 else (sector, (v - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
        out[name] = (h.PICK_FRAMES * variants, 8, frames)
    # heavy blow: variant-major, key-minor
    frames = []
    for sector in range(8):
        for variant in range(h.ATTACK_LEGS):
            for pose in heavy.HEAVY_POSES:
                frames.append((sector, 0.0, "attack", False, pose) if variant == 0 else (sector, (variant - 1) / h.WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
    out["heavy"] = (heavy.KEYS * h.ATTACK_LEGS, 8, frames)
    # fishing clips
    order, _starts = fish.layout()
    frames = []
    for sector in range(8):
        for name, i in order:
            pose, _rod = fish.sample(name, i)
            frames.append((sector, 0.0, "attack", False, pose))
    out["fish"] = (len(order), 8, frames)
    # standby gestures
    frames = []
    for sector in range(8):
        for clip in range(len(standby.CLIPS)):
            for f in range(standby.FRAMES):
                if f in (0, standby.FRAMES - 1):
                    frames.append((sector, 0.0, "idle", False, None))
                else:
                    frames.append((sector, 0.0, "idle", False, dict(h.timeline_pose(standby.KEYS[clip], f / (standby.FRAMES - 1)), standby=True)))
    out["standby"] = (len(standby.CLIPS) * standby.FRAMES, 8, frames)
    return out


def main() -> None:
    h.POINTS_ONLY = True
    result = {}
    for name, (cols, rows, frames) in sheets().items():
        assert len(frames) == cols * rows, (name, len(frames), cols, rows)
        data = []
        for args in frames:
            _pixels, rig = h.frame(*args)
            data.append(ints(rig))
        result[name] = {"cols": cols, "rows": rows, "data": data}
        print(name, cols, "x", rows, "=", len(data), "frames")
    path = h.ROOT.parent / "data" / "hero_jewelry.json"
    flat = {name: {"cols": s["cols"], "rows": s["rows"], "data": [v for frame in s["data"] for v in frame]} for name, s in result.items()}
    path.write_text(json.dumps({"stride": 16, "sheets": flat}, separators=(",", ":")) + "\n")
    print("wrote", path)


if __name__ == "__main__":
    main()
