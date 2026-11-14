"""Render Ellie's four standing gestures, their blood masks and hand rig.

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
CLIPS = ('stretch', 'hair', 'look', 'sweat')
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
    [(0.0, BASE),
     (0.18, pose(lean=0.025, twist=-0.02, left=(3.8, 38.5, 4.8), hair=(-0.15, 0.05, 0.05), head=-0.05)),
     (0.34, pose(lean=0.035, twist=-0.05, left=(0.8, 44.8, 5.4), hair=(-0.32, 0.12, 0.08), head=-0.12)),
     (0.52, pose(lean=0.025, twist=0.03, left=(4.6, 44.4, 4.8), hair=(0.36, 0.14, -0.22), head=0.10)),
     (0.68, pose(lean=-0.022, twist=0.02, left=(5.6, 33.5, 3.6), hair=(0.25, 0.08, -0.15), head=0.04)),
     (0.83, pose(lean=-0.010, left=(6.0, 28.2, 2.5), hair=(0.10, 0.02, -0.06))),
     (1.0, BASE)],
]


def _add_sweat_glint(color: np.ndarray, skin_source: np.ndarray = None) -> None:
    """Subtle 1-2 px glistening sweat droplet near temple/brow fringe on peak brow-wipe frames (8..12) of clip 3."""
    hair_cols = [c[:3] for c in h.RAMPS[h.HAIR]]
    skin_cols = [c[:3] for c in h.RAMPS[h.SKIN]]
    if skin_source is None:
        skin_source = color
    drop_hi = np.array([0xD8, 0xF6, 0xFF, 255], dtype=np.uint8)
    drop_lo = np.array([0x78, 0xF4, 0xE6, 255], dtype=np.uint8)
    sweat_clip = 3
    for s in (0, 1, 2, 3, 4):
        for f in (8, 9, 10, 11, 12):
            col = sweat_clip * FRAMES + f
            tile = color[s * h.FH:(s + 1) * h.FH, col * h.FW:(col + 1) * h.FW]
            sk_tile = skin_source[s * h.FH:(s + 1) * h.FH, col * h.FW:(col + 1) * h.FW]
            rgb = tile[..., :3]
            solid = tile[..., 3] == 255
            sk_rgb = sk_tile[..., :3]
            sk_solid = sk_tile[..., 3] == 255
            hair_m = np.zeros((h.FH, h.FW), dtype=bool)
            for hc in hair_cols:
                hair_m |= np.all(rgb == hc, axis=-1) & solid
            skin_m = np.zeros((h.FH, h.FW), dtype=bool)
            for sc in skin_cols:
                skin_m |= np.all(sk_rgb == sc, axis=-1) & sk_solid
            # Focus on head rows (y in 6..23) so hands/arms below never mislead temple lookup
            hy, hx = np.nonzero(hair_m[:24, :])
            if len(hy) == 0:
                continue
            top_y = int(hy.min())
            brow_y = min(21, top_y + 4 + (1 if f in (10, 11, 12) else 0))
            row_xs = np.nonzero(hair_m[brow_y, :])[0]
            if len(row_xs) < 3:
                continue
            # Pick temple side on her left/front fringe (right side of screen in S/SE/E, left in W/SW) without touching skin/eyes
            tx = int(row_xs[-2] if s in (0, 1, 2) else row_xs[1])
            if f in (11, 12):
                tx += (1 if s in (0, 1, 2) else -1)
            if 2 <= tx < h.FW - 2 and solid[brow_y, tx] and not skin_m[brow_y, tx]:
                tile[brow_y, tx] = drop_hi if f in (8, 9, 10) else drop_lo
                if f in (9, 10, 11) and brow_y + 1 < 23 and solid[brow_y + 1, tx] and not skin_m[brow_y + 1, tx]:
                    tile[brow_y + 1, tx] = drop_lo


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
    _add_sweat_glint(color)
    write_array(h.ROOT / 'characters' / 'player_standby.png', color)
    write_array(h.ROOT / 'characters' / 'player_standby_blood.png', blood)
    path = h.ROOT.parent / 'data' / 'hero_rig.json'
    rig = json.loads(path.read_text())
    rig['standby'] = {'frames': FRAMES, 'fps': FPS, 'clips': list(CLIPS), 'cols': cols, 'hand': hands, 'shoulder': shoulders}
    path.write_text(json.dumps(rig, separators=(',', ':')) + '\n')
    print('Standby sheets, masks and rig written', flush=True)


if __name__ == '__main__':
    main()
