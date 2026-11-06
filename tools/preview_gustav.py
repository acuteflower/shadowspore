"""Build an animated eight-direction preview from Gustav's actual game atlas."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parent.parent
rig = json.loads((ROOT / 'data/gustav_rig.json').read_text())
atlas = Image.open(ROOT / 'assets/characters/gustav.png').convert('RGBA')
frames = []
for clip in ('idle', 'walk', 'run', 'work'):
    spec = rig['clips'][clip]
    for index in range(12):
        frame = Image.new('RGBA', (576, 304), (38, 34, 50, 255))
        draw = ImageDraw.Draw(frame)
        for sector, name in enumerate(('E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE')):
            col = spec['start'] + index % spec['count']
            tile = atlas.crop((col * 72, sector * 76, (col + 1) * 72, (sector + 1) * 76))
            tile = tile.resize((144, 152), Image.Resampling.NEAREST)
            x, y = sector % 4 * 144, sector // 4 * 152
            frame.alpha_composite(tile, (x, y))
            draw.text((x + 4, y + 4), name, fill='white')
        draw.text((8, 286), clip.upper(), fill='white')
        frames.append(frame.convert('RGB').convert('P', palette=Image.Palette.ADAPTIVE, colors=100))
frames[0].save(ROOT / 'docs/img/gustav_animation.gif', save_all=True, append_images=frames[1:],
               duration=125, loop=0, optimize=True, disposal=2)
