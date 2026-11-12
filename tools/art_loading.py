"""Bake small, pure silhouette E-facing walk/run loops from the actual cast.

No changes to the character sources. Run: py -3 tools/art_loading.py
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CELL = (96, 104)
sheet = Image.new('RGBA', (CELL[0] * 16, CELL[1] * 4))
for row, name in enumerate(['player', 'adventurer', 'gustav', 'torben']):
    source = Image.open(ROOT / f'assets/characters/{name}.png').convert('RGBA')
    if name == 'player':
        size, feet = (48, 56), (24, 51)
        clips = [(16, 6), (6, 6)]
    else:
        rig = json.loads((ROOT / f'data/{name}_rig.json').read_text())
        size, feet = rig['frame'], rig['feet']
        clips = [(rig['clips'][key]['start'], rig['clips'][key]['count']) for key in ['walk', 'run']]
    for gait, (start, count) in enumerate(clips):
        for frame in range(8):
            index = start + frame % count
            tile = source.crop((index * size[0], 0, (index + 1) * size[0], size[1]))
            alpha = tile.getchannel('A').point(lambda a: 255 if a >= 100 else 0)
            tile = Image.new('RGBA', tile.size, '#f3dfbe')
            tile.putalpha(alpha)
            sheet.paste(tile, ((gait * 8 + frame) * CELL[0] + 48 - feet[0], row * CELL[1] + 92 - feet[1]))
sheet.save(ROOT / 'assets/ui/loading_cast.png')
print('Baked loading_cast.png (four cast members, two gaits).')
