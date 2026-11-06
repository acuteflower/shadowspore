"""Ellie's sitting: eight directions, breathing and five small gestures.

OPENBLAS_NUM_THREADS=1 python3 tools/art_hero_rest.py [optional-preview.png]
Renders matching color and injury/bandage atlases and preserves all other rig data.
"""
import json
import sys
from pathlib import Path
import numpy as np

import art_hero_sit as sit
import art_hero_emerge as em
import art_hero3d as hero
from art_hero_rebuild import write_array
from gen_art import ROOT

DOWN = sit.DOWN
LOOP = sit.LOOP
GESTURE = 24
GESTURE_NAMES = ('warm', 'stretch', 'hair', 'look', 'settle')


def gesture_pose(base, **changes):
    return dict(base, **changes)


def poses():
    down = [em.timeline(sit.KEYS, (i + 1) * 0.75 / DOWN) for i in range(DOWN)]
    rest = sit.LOOP_POSES
    base = dict(rest[0], head_yaw=0.0)
    warm = gesture_pose(base, lean=0.22, pz=1.0, hand_l=(3.5, 20.0, 14.0), hand_r=(-3.5, 20.0, 13.6), hair=(0.3, 0.1, -0.3))
    stretch = gesture_pose(base, lean=-0.045, hand_l=(7.0, 30.0, 3.0), hand_r=(-7.0, 30.0, 3.0), hair=(0.5, 0.25, -0.45))
    hair = gesture_pose(base, lean=0.08, hand_l=(5.2, 33.0, 3.8), head_yaw=-0.10, hair=(0.65, 0.15, -0.4))
    look_left = gesture_pose(base, lean=0.09, twist=-0.025, head_yaw=-0.42, hair=(-0.35, 0.08, 0.15))
    look_right = gesture_pose(base, lean=0.09, twist=0.025, head_yaw=0.42, hair=(0.35, 0.08, -0.15))
    settle = gesture_pose(base, lean=0.14, twist=0.07, pz=0.95, hand_l=(4.4, 16.0, 8.0), hand_r=(-4.2, 15.5, 8.3), hair=(0.35, 0.0, -0.15))
    timelines = [
        [(0.0, base), (0.30, warm), (0.68, warm), (1.0, base)],
        [(0.0, base), (0.32, stretch), (0.65, stretch), (1.0, base)],
        [(0.0, base), (0.32, hair), (0.55, hair), (1.0, base)],
        [(0.0, base), (0.25, look_left), (0.42, look_left), (0.68, look_right), (0.80, look_right), (1.0, base)],
        [(0.0, base), (0.32, settle), (0.60, settle), (1.0, base)],
    ]
    out = down + rest
    for keys in timelines:
        out += [em.timeline(keys, i / (GESTURE - 1)) for i in range(GESTURE)]
    return out


def main():
    ps = poses()
    color, blood = sit.render_atlas(ps)
    write_array(ROOT / 'characters' / 'player_rest.png', color)
    write_array(ROOT / 'characters' / 'player_rest_blood.png', blood)
    rig_path = ROOT.parent / 'data' / 'hero_rig.json'
    rig = json.loads(rig_path.read_text())
    meta = {'fps': 24, 'frame_w': hero.FW, 'frame_h': hero.FH, 'cols': len(ps), 'rows': 8,
            'down': [0, DOWN], 'idle': [DOWN, LOOP], 'idle_fps': 5,
            'gesture_names': list(GESTURE_NAMES), 'gesture_fps': 12,
            'gesture_wait_min': 5.0, 'gesture_wait_max': 10.0}
    for i, name in enumerate(GESTURE_NAMES):
        meta[name] = [DOWN + LOOP + i * GESTURE, GESTURE]
    rig['rest'] = meta
    rig_path.write_text(json.dumps(rig, separators=(',', ':')) + '\n')
    if len(sys.argv) > 1:
        selected = [DOWN - 1, DOWN + LOOP + 9, DOWN + LOOP + GESTURE * 2 + 10,
                    DOWN + LOOP + GESTURE * 3 + 8, DOWN + LOOP + GESTURE * 4 + 10]
        bg = np.array([38, 34, 50], dtype=np.float32)
        preview = np.empty((8 * hero.FH, len(selected) * hero.FW, 4), dtype=np.uint8)
        preview[:, :, :3], preview[:, :, 3] = bg.astype(np.uint8), 255
        for s in range(8):
            for j, index in enumerate(selected):
                frame = color[s*hero.FH:(s+1)*hero.FH, index*hero.FW:(index+1)*hero.FW]
                alpha = frame[:, :, 3:4].astype(np.float32) / 255.0
                preview[s*hero.FH:(s+1)*hero.FH, j*hero.FW:(j+1)*hero.FW, :3] = (frame[:, :, :3] * alpha + bg * (1.0-alpha)).astype(np.uint8)
        write_array(Path(sys.argv[1]), np.repeat(np.repeat(preview, 3, axis=0), 3, axis=1))
    print('Eight-direction rest sheets, blood masks and rig written', flush=True)


if __name__ == '__main__':
    main()
