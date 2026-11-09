"""Build an animated eight-direction preview from Torben's actual game atlas (docs/img/torben_animation.gif): every clip in turn, the glow sheet laid over it."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parent.parent
rig = json.loads((ROOT / 'data/torben_rig.json').read_text())
atlas = Image.open(ROOT / 'assets/characters/torben.png').convert('RGBA')
glow = Image.open(ROOT / 'assets/characters/torben_glow.png').convert('RGBA')
FW, FH = rig['frame']
frames = []
for clip, spec in rig['clips'].items():
    for index in range(max(spec['count'], 6)):
        frame = Image.new('RGBA', (FW * 4 * 2, FH * 2 * 2), (38, 34, 50, 255))
        draw = ImageDraw.Draw(frame)
        for sector, name in enumerate(('E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE')):
            col = spec['start'] + index % spec['count']
            box = (col * FW, sector * FH, (col + 1) * FW, (sector + 1) * FH)
            tile = atlas.crop(box)
            tile.alpha_composite(glow.crop(box))
            tile = tile.resize((FW * 2, FH * 2), Image.Resampling.NEAREST)
            x, y = sector % 4 * FW * 2, sector // 4 * FH * 2
            frame.alpha_composite(tile, (x, y))
            draw.text((x + 4, y + 4), name, fill='white')
        draw.text((8, FH * 4 - 14), clip.upper(), fill='white')
        frames.append(frame.convert('RGB').convert('P', palette=Image.Palette.ADAPTIVE, colors=120))
frames[0].save(ROOT / 'docs/img/torben_animation.gif', save_all=True, append_images=frames[1:], duration=130, loop=0, optimize=True, disposal=2)
print('torben_animation.gif written (%d frames)' % len(frames))
