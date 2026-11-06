"""Animated eight-facing preview from the exact Maren sprite atlas."""
import json
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent.parent
rig=json.loads((ROOT/'data/maren_rig.json').read_text())
atlas=Image.open(ROOT/'assets/characters/maren.png').convert('RGBA')
frames=[];durations=[]
for clip in ('idle','walk','run','work'):
    c=rig['clips'][clip]
    for i in range(c['count']*2):
        out=Image.new('RGBA',(576,304),(38,34,50,255));d=ImageDraw.Draw(out)
        for sector,name in enumerate(('E','SE','S','SW','W','NW','N','NE')):
            col=c['start']+i%c['count']
            tile=atlas.crop((col*72,sector*76,(col+1)*72,(sector+1)*76)).resize((144,152),Image.Resampling.NEAREST)
            x=sector%4*144;y=sector//4*152;out.alpha_composite(tile,(x,y));d.text((x+4,y+4),name,fill='white')
        d.text((8,286),clip.upper(),fill='white')
        frames.append(out.convert('RGB').convert('P',palette=Image.Palette.ADAPTIVE,colors=110))
        durations.append(round(1000/c['fps']))
frames[0].save(ROOT/'docs/img/maren_animation.gif',save_all=True,append_images=frames[1:],
               duration=durations,loop=0,optimize=True,disposal=2)
