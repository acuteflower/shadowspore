"""Rebuild Ellie's story sheets in isolation and merge their rig entries.

Run after art_hero_rebuild.py: python3 tools/art_hero_story_rebuild.py [workers]
Each story generator writes to its own temporary tree so rig updates cannot race.
"""
import importlib
import json
import multiprocessing as mp
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from art_hero_rebuild import write_array

ROOT = Path(__file__).resolve().parent.parent
NAMES = ('emerge', 'wake', 'faint', 'sit', 'rest', 'carry')


def generate_story(name, folder):
    module = importlib.import_module('art_hero_' + name)
    module.ROOT = Path(folder) / 'assets'
    sys.argv = [sys.argv[0]]
    module.main()


def work(job):
    if job[0] == 'story':
        _, name, folder = job
        result = subprocess.run([sys.executable, __file__, '--job', name, folder], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(f'{name}: {result.stdout}\n{result.stderr}')
        return ('story', name)
    _, sector, index = job
    import art_hero_stumble as stumble
    import art_hero_emerge as em
    import art_hero3d as hero
    hero.FW, hero.FH = em.FRAME_W, em.FRAME_H
    em.SECTOR = sector
    pose = stumble.timeline(stumble.KEYS, (index + 0.5) / stumble.FPS)
    color = np.asarray(em.render_frame(pose, False), dtype=np.uint8)
    blood = np.asarray(em.render_frame(pose, True), dtype=np.uint8)
    return ('stumble', sector, index, color.tobytes(), blood.tobytes())


def main():
    import art_hero_stumble as stumble
    import art_hero_emerge as em
    count = int(round(stumble.DURATION * stumble.FPS))
    width, height = em.FRAME_W, em.FRAME_H
    arrays = [np.zeros((8 * height, count * width, 4), dtype=np.uint8) for _ in range(2)]
    rig_path = ROOT / 'data' / 'hero_rig.json'
    workers = int(sys.argv[1]) if len(sys.argv) > 1 else min(6, os.cpu_count() or 1)
    with tempfile.TemporaryDirectory(prefix='ellie-story-') as tmp:
        folders = {}
        for name in NAMES:
            folder = Path(tmp) / name
            (folder / 'data').mkdir(parents=True)
            (folder / 'assets' / 'characters').mkdir(parents=True)
            (folder / 'assets' / 'interior' / 'hut').mkdir(parents=True)
            shutil.copyfile(rig_path, folder / 'data' / 'hero_rig.json')
            folders[name] = folder
        jobs = [('story', name, str(folders[name])) for name in NAMES]
        jobs += [('stumble', sector, i) for sector in range(8) for i in range(count)]
        print(f'Rendering {len(jobs)} story jobs with {workers} workers', flush=True)
        with mp.Pool(workers) as pool:
            for done, result in enumerate(pool.imap_unordered(work, jobs, chunksize=1), 1):
                if result[0] == 'story':
                    print(f'{result[1]} finished', flush=True)
                else:
                    _, sector, index, color, blood = result
                    for arr, data in zip(arrays, (color, blood)):
                        arr[sector * height:(sector + 1) * height, index * width:(index + 1) * width] = np.frombuffer(data, dtype=np.uint8).reshape(height, width, 4)
                if done % 100 == 0:
                    print(f'{done}/{len(jobs)} story jobs', flush=True)
        rig = json.loads(rig_path.read_text())
        for name in NAMES:
            staged_rig = json.loads((folders[name] / 'data' / 'hero_rig.json').read_text())
            rig[name] = staged_rig[name]
            for src in (folders[name] / 'assets' / 'characters').glob('player_*.png'):
                shutil.copyfile(src, ROOT / 'assets' / 'characters' / src.name)
        for suffix, arr in zip(('', '_blood'), arrays):
            write_array(ROOT / 'assets' / 'characters' / ('player_stumble' + suffix + '.png'), arr)
        rig['stumble'] = {'fps': stumble.FPS, 'frames': count, 'events': stumble.EVENTS, 'duration': stumble.DURATION}
        rig_path.write_text(json.dumps(rig, separators=(',', ':')) + '\n')
    print('Story sheets, masks and rig entries updated.', flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--job':
        generate_story(sys.argv[2], sys.argv[3])
    else:
        main()
