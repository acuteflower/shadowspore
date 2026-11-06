"""Ellie sits down by the fire (story step 6), breathes, and gets up again. Eight independently rendered directions,
with a matching blood and bandage map for each frame.
  python3 tools/art_hero_sit.py [sheet out.png]   writes assets/characters/player_sit.png and data/hero_rig.json "sit"
Frames 0..DOWN-1 are the sitting down (played backwards: getting up), then LOOP frames of resting breath."""
import json
import math
import multiprocessing as mp
import os
import sys
from pathlib import Path

import numpy as np
import art_hero_emerge as em
import art_hero3d as hero
from art_hero_rebuild import write_array
from gen_art import CLEAR, ROOT, write_png

Q = em.Q
FPS = 24
DOWN = 18
LOOP = 6
SIT_LEGS = ((1.38, 1.50), (1.34, 1.46))
SIT_DY = -10.0
HANDS = dict(hand_l=(4.0, 15.5, 8.5), hand_r=(-4.0, 15.0, 8.0))
KEYS = [
    (0.0, Q(hand_l=em.REST_L, hand_r=em.REST_R)),
    (0.22, Q(lean=0.12, pz=0.5, dy=-1.5, legs=((0.25, 0.5), (0.15, 0.4)), hand_l=(4.5, 24.0, 3.0), hand_r=(-4.5, 23.5, 3.0))),
    (0.5, Q(lean=0.3, pz=1.5, dy=-7.0, legs=((0.9, 1.2), (0.8, 1.1)), hand_l=(4.5, 19.0, 6.0), hand_r=(-4.5, 18.5, 6.0))),
    (0.75, Q(lean=0.10, pz=0.6, dy=SIT_DY, legs=SIT_LEGS, droop=0.8, **HANDS)),
]
LOOP_POSES = [Q(lean=0.1 + 0.02 * s, pz=0.6 + 0.4 * s, dy=SIT_DY, legs=SIT_LEGS, droop=0.8, hand_l=(4.0, 15.5 + 0.2 * s, 8.5), hand_r=(-4.0, 15.0 + 0.2 * s, 8.0))
              for s in (0.0, 0.5, 0.9, 1.0, 0.6, 0.2)]


def mugpose(lh, rh, mug, tilt=0.0, s=0.0, lean=0.16):
    return dict(Q(lean=lean, pz=1.0, dy=SIT_DY, legs=SIT_LEGS, droop=0.8, hand_l=lh, hand_r=rh), mug=mug, mug_tilt=tilt)


# she takes the mug (hands come up, the mug is in them), holds it, sips
TAKE = [Q(lean=0.16 + 0.02 * k, pz=1.0, dy=SIT_DY, legs=SIT_LEGS, droop=0.8, hand_l=(4.0 - 1.4 * k / 5, 15.5 + 4.0 * k / 5, 8.5 + 4.0 * k / 5), hand_r=(-4.0 + 1.4 * k / 5, 15.0 + 4.5 * k / 5, 8.0 + 5.0 * k / 5)) for k in range(6)]
TAKE = [dict(p, mug=(0.0, 21.0, 13.5)) if i >= 2 else p for i, p in enumerate(TAKE)]
TAKE = [dict(p, mug_tilt=0.0) for p in TAKE]
HOLD = [mugpose((2.6, 21.5 + 0.15 * b, 8.2), (-2.6, 21.5 + 0.15 * b, 8.2), (0.0, 21.8 + 0.15 * b, 9.0)) for b in (0.0, 0.5, 0.9, 1.0, 0.6, 0.2)]
SIP = [mugpose((2.6, y, z), (-2.6, y, z), (0.0, y + 0.3, z + 0.8), tilt=t, lean=0.16 + 0.07 * t) for k, (y, z, t) in enumerate(
    [(21.5, 8.2, 0.0), (24.0, 8.0, -0.2), (28.0, 7.5, -0.5), (31.5, 7.2, -0.9), (33.0, 7.0, -1.2), (33.0, 7.0, -1.25), (33.0, 7.0, -1.2), (31.0, 7.2, -0.7), (26.0, 8.0, -0.3), (21.5, 8.2, 0.0)])]


def poses():
    return [em.timeline(KEYS, (i + 1) * 0.75 / DOWN) for i in range(DOWN)] + LOOP_POSES + TAKE + HOLD + SIP


def frames():
    return [em.render_frame(p, False) for p in poses()]


def _render_pose(job):
    sector, index, pose = job
    model = hero.build(0.0, "attack", False, pose)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, thresholds = hero.render(model.transform(yaw, 0.0), yaw, 0.0)
    color = np.asarray(hero.to_pixels(depth, code), dtype=np.uint8)
    blood = np.asarray(hero.to_blood(thresholds, code, hero.LAST_BAND), dtype=np.uint8)
    return sector, index, color.tobytes(), blood.tobytes()


def render_atlas(ps):
    """Color and injury/bandage maps, sampled from the same eight-direction render."""
    count = len(ps)
    arrays = [np.zeros((8 * hero.FH, count * hero.FW, 4), dtype=np.uint8) for _ in range(2)]
    workers = min(6, os.cpu_count() or 1)
    jobs = [(sector, i, pose) for sector in range(8) for i, pose in enumerate(ps)]
    print(f"Rendering {len(jobs)} sitting frames with {workers} workers", flush=True)
    with mp.Pool(workers) as pool:
        for done, (sector, i, color, blood) in enumerate(pool.imap_unordered(_render_pose, jobs, chunksize=2), 1):
            for dest, data in zip(arrays, (color, blood)):
                dest[sector*hero.FH:(sector+1)*hero.FH, i*hero.FW:(i+1)*hero.FW] = np.frombuffer(data, dtype=np.uint8).reshape(hero.FH, hero.FW, 4)
            if done % 200 == 0:
                print(f"{done}/{len(jobs)}", flush=True)
    return arrays


def main():
    W, H = hero.FW, hero.FH
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        frs = frames()
        sheet, rows_n = em.sheet_pixels(frs, 8)
        k = 3
        out = [[(62, 125, 86, 255)] * (8 * W * k) for _ in range(rows_n * H * k)]
        for y, row in enumerate(sheet):
            for x, px in enumerate(row):
                if px[3]:
                    for dy in range(k):
                        for dx in range(k):
                            out[y * k + dy][x * k + dx] = px
        write_png(Path(sys.argv[2]), 8 * W * k, rows_n * H * k, out)
        return
    ps = poses()
    sheet, blood = render_atlas(ps)
    write_array(ROOT / "characters" / "player_sit.png", sheet)
    write_array(ROOT / "characters" / "player_sit_blood.png", blood)
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig["sit"] = {"fps": FPS, "down": DOWN, "loop": LOOP, "loop_fps": 5, "take": len(TAKE), "hold": len(HOLD), "sip": len(SIP), "rows": 8}
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("sit sheet written")


if __name__ == "__main__":
    main()
