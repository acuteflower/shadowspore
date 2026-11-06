"""Rebuild Ellie's main, attack and action sheets and masks together.

Run with NumPy: python3 tools/art_hero_rebuild.py [workers]
The existing story rig entries are preserved; each colour frame, blood mask and
hand position comes from the same render. Story sheets have their own generators.
"""
import json
import multiprocessing as mp
import os
import struct
import sys
import zlib

import numpy as np
import art_hero3d as hero


def render_one(job):
    sheet, row, col, sector, t, mode, crouch, pose = job
    hero.WANT_BLOOD = True
    pixels, rig = hero.frame(sector, t, mode, crouch, pose)
    return (sheet, row, col, np.asarray(pixels, dtype=np.uint8).tobytes(),
            np.asarray(hero.LAST_BLOOD, dtype=np.uint8).tobytes(), rig)


def write_array(path, pixels):
    h, w, _ = pixels.shape
    raw = b''.join(b'\0' + pixels[y].tobytes() for y in range(h))
    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def jobs():
    for crouch in (False, True):
        for sector in range(8):
            row = sector + 8 * int(crouch)
            for col in range(hero.COLS):
                if col < hero.WALK_FRAMES:
                    mode, t = 'walk', col / hero.WALK_FRAMES
                elif col < hero.WALK_FRAMES + hero.RUN_FRAMES:
                    mode = 'walk' if crouch else 'run'
                    t = (col - hero.WALK_FRAMES) / hero.RUN_FRAMES
                else:
                    mode, t = 'idle', (col - hero.WALK_FRAMES - hero.RUN_FRAMES) / hero.IDLE_FRAMES
                yield ('main', row, col, sector, t, mode, crouch, None)
    for sector in range(8):
        for step, poses in enumerate(hero.ATTACK_POSES):
            for variant in range(hero.ATTACK_LEGS):
                for key, pose in enumerate(poses):
                    col = (step * hero.ATTACK_LEGS + variant) * hero.ATTACK_FRAMES + key
                    mode, t = ('attack', 0.0) if variant == 0 else ('walk', (variant - 1) / hero.WALK_FRAMES)
                    yield ('attack', sector, col, sector, t, mode, False, pose if variant == 0 else dict(pose, pz=0.0))
        for name, keys, variants in [('pick', hero.PICK_KEYS, 1), ('eat', hero.EAT_KEYS, hero.ATTACK_LEGS)]:
            for variant in range(variants):
                for key in range(hero.PICK_FRAMES):
                    pose = hero.timeline_pose(keys, (key + 0.5) / hero.PICK_FRAMES)
                    mode, t = ('attack', 0.0) if variant == 0 else ('walk', (variant - 1) / hero.WALK_FRAMES)
                    yield (name, sector, variant * hero.PICK_FRAMES + key, sector, t, mode, False,
                           pose if variant == 0 else dict(pose, pz=0.0))


def main():
    specs = {'main': (hero.COLS, 16), 'attack': (hero.ATTACK_COLS, 8),
             'pick': (hero.PICK_FRAMES, 8), 'eat': (hero.PICK_FRAMES * hero.ATTACK_LEGS, 8)}
    arrays = {name: [np.zeros((rows * hero.FH, cols * hero.FW, 4), dtype=np.uint8) for _ in range(2)]
              for name, (cols, rows) in specs.items()}
    rig_path = hero.ROOT.parent / 'data' / 'hero_rig.json'
    rig = json.loads(rig_path.read_text())
    for name, (cols, rows) in specs.items():
        prefix = '' if name == 'main' else name + '_'
        rig[prefix + 'shoulder'] = [None] * (cols * rows)
        rig[prefix + 'hand'] = [None] * (cols * rows)
        if name in ('pick', 'eat'):
            rig[prefix + 'mouth'] = [None] * (cols * rows)
    rig.update(cols=hero.COLS, attack_cols=hero.ATTACK_COLS, pick_cols=hero.PICK_FRAMES,
               eat_cols=hero.PICK_FRAMES, eat_variants=hero.ATTACK_LEGS)
    all_jobs = list(jobs())
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else min(6, os.cpu_count() or 1)
    print(f'Rendering {len(all_jobs)} frames with {workers} workers', flush=True)
    with mp.Pool(workers) as pool:
        for completed, (name, row, col, color, blood, points) in enumerate(pool.imap_unordered(render_one, all_jobs, chunksize=2), 1):
            y, x = row * hero.FH, col * hero.FW
            for dest, data in zip(arrays[name], (color, blood)):
                dest[y:y + hero.FH, x:x + hero.FW] = np.frombuffer(data, dtype=np.uint8).reshape(hero.FH, hero.FW, 4)
            prefix = '' if name == 'main' else name + '_'
            idx = row * specs[name][0] + col
            for key, value in points.items():
                if prefix + key in rig:
                    rig[prefix + key][idx] = value
            if completed % 100 == 0:
                print(f'{completed}/{len(all_jobs)}', flush=True)
    for name in specs:
        assert all(p is not None for p in rig[('' if name == 'main' else name + '_') + 'hand'])
        stem = 'player' if name == 'main' else 'player_' + name
        for suffix, pixels in zip(('', '_blood'), arrays[name]):
            write_array(hero.ROOT / 'characters' / (stem + suffix + '.png'), pixels)
    rig_path.write_text(json.dumps(rig, separators=(',', ':')) + '\n')
    print('Main, attack and action sheets, masks and rig updated.', flush=True)


if __name__ == '__main__':
    main()
