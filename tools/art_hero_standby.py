"""Render Ellie's three standing gestures, their blood masks and hand rig.

OPENBLAS_NUM_THREADS=1 python3 tools/art_hero_standby.py [workers]
The separate atlas preserves the existing main and story sheets and rig entries.
"""
import json
import math
import multiprocessing as mp
import os
import sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array

FRAMES, FPS = 24, 12
CLIPS = ('stretch', 'hair', 'look')
# These targets match the relaxed idle arm at phase zero. The right arm is
# drawn separately by the game; the left wrist is drawn into the atlas.
R0 = (-6.21288319, 25.09377656, 3.06503037)
L0 = (6.1266, 25.7523, 1.7731)


def pose(lean=0.0, twist=0.0, right=R0, left=L0, hair=(0.0, 0.0, 0.0), head=0.0):
    return dict(h.P(twist, lean, 0.0, h.STAND, right, left, hair), head_yaw=head)


BASE = pose()
KEYS = [
    [(0.0, BASE),
     (0.18, pose(lean=-0.025, right=(-7.0, 28.0, 1.0), left=(7.0, 28.0, 0.8), hair=(0.2, 0.1, -0.2))),
     (0.38, pose(lean=-0.10, right=(-8.3, 34.5, 0.3), left=(8.3, 34.5, 0.3), hair=(0.8, 0.45, -0.8))),
     (0.60, pose(lean=-0.08, right=(-8.3, 34.0, 0.5), left=(8.3, 34.0, 0.5), hair=(0.5, 0.15, -0.5))),
     (0.82, pose(lean=0.015, right=(-7.0, 28.0, 1.0), left=(7.0, 28.0, 0.8), hair=(-0.4, -0.15, 0.3))),
     (1.0, BASE)],
    [(0.0, BASE),
     (0.20, pose(twist=-0.035, left=(6.2, 31.0, 3.2), hair=(-0.1, 0.0, 0.0))),
     (0.38, pose(lean=0.025, twist=-0.06, left=(5.2, 41.5, 3.8), hair=(-0.5, 0.2, -0.15), head=-0.08)),
     (0.57, pose(lean=0.015, twist=-0.04, left=(5.0, 40.0, 4.1), hair=(0.9, 0.3, -0.8), head=-0.04)),
     (0.78, pose(left=(6.4, 31.0, 2.7), hair=(0.6, 0.1, -0.35))),
     (1.0, BASE)],
    [(0.0, BASE),
     (0.21, pose(twist=-0.025, hair=(-0.5, 0.1, 0.2), head=-0.50)),
     (0.36, pose(twist=-0.025, hair=(-0.3, 0.0, 0.1), head=-0.50)),
     (0.63, pose(twist=0.025, hair=(0.6, 0.1, -0.1), head=0.50)),
     (0.77, pose(twist=0.025, hair=(0.35, 0.0, 0.0), head=0.50)),
     (1.0, BASE)],
]


def render_job(job):
    sector, clip, frame = job
    h.WANT_BLOOD = True
    if frame in (0, FRAMES - 1):
        pixels, rig = h.frame(sector, 0.0, 'idle', False)
    else:
        p = dict(h.timeline_pose(KEYS[clip], frame / (FRAMES - 1)), standby=True)
        pixels, rig = h.frame(sector, 0.0, 'idle', False, p)
    return sector, clip, frame, np.asarray(pixels, dtype=np.uint8).tobytes(), np.asarray(h.LAST_BLOOD, dtype=np.uint8).tobytes(), rig


def main():
    cols = len(CLIPS) * FRAMES
    shape = (8 * h.FH, cols * h.FW, 4)
    color, blood = np.zeros(shape, np.uint8), np.zeros(shape, np.uint8)
    hands, shoulders = [None] * (8 * cols), [None] * (8 * cols)
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else min(6, os.cpu_count() or 1)
    jobs = [(s, clip, f) for s in range(8) for clip in range(len(CLIPS)) for f in range(FRAMES)]
    print(f'Rendering {len(jobs)} standby frames with {workers} workers', flush=True)
    with mp.Pool(workers) as pool:
        for done, (s, clip, f, px, bl, rig) in enumerate(pool.imap_unordered(render_job, jobs, chunksize=2), 1):
            col = clip * FRAMES + f
            for dest, data in ((color, px), (blood, bl)):
                dest[s*h.FH:(s+1)*h.FH, col*h.FW:(col+1)*h.FW] = np.frombuffer(data, dtype=np.uint8).reshape(h.FH, h.FW, 4)
            idx = s * cols + col
            hands[idx], shoulders[idx] = rig['hand'], rig['shoulder']
            if done % 100 == 0:
                print(f'{done}/{len(jobs)}', flush=True)
    assert all(point is not None for point in hands + shoulders)
    write_array(h.ROOT / 'characters' / 'player_standby.png', color)
    write_array(h.ROOT / 'characters' / 'player_standby_blood.png', blood)
    path = h.ROOT.parent / 'data' / 'hero_rig.json'
    rig = json.loads(path.read_text())
    rig['standby'] = {'frames': FRAMES, 'fps': FPS, 'clips': list(CLIPS), 'cols': cols, 'hand': hands, 'shoulder': shoulders}
    path.write_text(json.dumps(rig, separators=(',', ':')) + '\n')
    print('Standby sheets, masks and rig written', flush=True)


if __name__ == '__main__':
    main()
