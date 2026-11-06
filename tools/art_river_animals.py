"""Bake 24px river animals: five species, eight directions and eight phases."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/water/river_animals.png'
# E SE S SW W NW N NE; actual poses are drawn on the grid, not image-rotated.
DIR = [(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)]
sheet = Image.new('RGBA', (24*8, 24*40))
for species in range(5):
    for direction, (dx,dy) in enumerate(DIR):
        for frame in range(8):
            im = Image.new('RGBA', (24,24)); p = ImageDraw.Draw(im)
            def pos(a, b):
                # 3/4 projection preserves readable bodies for diagonal facings.
                if dx and dy:
                    return (12 + round((a*dx-b*dy)*0.72), 16 + round((a*dy+b*dx)*0.55))
                return (12 + a*dx-b*dy, 16 + round((a*dy+b*dx)*0.72))
            def dot(a,b,c): p.point(pos(a,b),fill=c)
            def line(coords,c,w=1): p.line([pos(a,b) for a,b in coords],fill=c,width=w)
            if species in (0,1):
                # Tapered body, asymmetric head and tail flick preserve facing.
                n = 2 if species == 0 else 4
                outline = '#374e49' if species == 0 else '#354b45'
                body = '#8c9b83' if species == 0 else '#71816b'
                light = '#bcc6a7' if species == 0 else '#a2a98b'
                for a in range(-n,n+1):
                    width = 1 if species == 0 else (2 if abs(a)<3 else 1)
                    for b in range(-width,width+1): dot(a,b,outline if abs(b)==width else body)
                line([(-n-1,-1),(-n,0),(-n-1,1)], outline)
                tail = (0,0,1,1,0,0,-1,-1)[frame]
                line([(-n-1,tail-1),(-n,0),(-n-1,tail+1)], body)
                line([(-n+1,-1),(n-1,-1)],light)
                dot(n-1,0,'#263c39')
                if species == 1:
                    dot(-1,0,'#465c50'); dot(1,1,'#4c6256'); dot(-2,-1,'#586c58')
            elif species == 2:
                # Rounded body and directional head; legs extend on hop frames.
                jump = (0,1,3,5,3,1,0,0)[frame]
                # Move sprite body up, while its designated foot anchor stays fixed.
                def frog(a,b,c):
                    x,y=pos(a,b); p.point((x,y-jump),fill=c)
                for a in range(-3,4):
                    for b in range(-2,3):
                        if (a*a/16+b*b/9) <= 1:
                            frog(a,b,'#385440' if abs(b)==2 or abs(a)==3 else '#6d8d56')
                for b in (-2,2):
                    frog(2,b,'#8faa69'); frog(3,b,'#283d35')
                reach = 3 if frame in (2,3,4) else 2
                for sign in (-1,1):
                    coords=[(-2,sign),(-3,sign*reach),(-4,sign*(reach+1))]
                    pts=[]
                    for a,b in coords:
                        x,y=pos(a,b); pts.append((x,y-jump))
                    p.line(pts,fill='#506c49',width=1)
                frog(-1,-1,'#9aab70')
            elif species == 3:
                # Slender body, two pairs of translucent-looking solid pixel wings.
                line([(-4,0),(4,0)],'#437b72',1)
                line([(-3,0),(1,0)],'#70a49a',1)
                dot(4,0,'#a8c1aa')
                wing = (3,2,1,2,3,2,1,2)[frame]
                for sign in (-1,1):
                    line([(-1,0),(-3,sign*wing)],'#a4bcb0')
                    line([(1,0),(2,sign*wing)],'#849f9a')
            else:
                # Long slender legs skim the surface; broken pale contacts read as water.
                line([(-2,0),(2,0)], '#354c45', 2)
                line([(-1,0),(2,0)], '#718576')
                stroke = (0,0,1,1,0,0,-1,-1)[frame]
                for sign in (-1,1):
                    line([(-1,sign),(-3+stroke,sign*3),(-4+stroke,sign*4)], '#5b7167')
                    line([(1,sign),(3-stroke,sign*3),(4-stroke,sign*4)], '#5b7167')
                    dot(-4+stroke,sign*4,'#8aaba0')
                    dot(4-stroke,sign*4,'#8aaba0')
            sheet.alpha_composite(im,(frame*24,(species*8+direction)*24))
OUT.parent.mkdir(parents=True,exist_ok=True)
sheet.save(OUT)
# First, third and fifth phases show motion without an oversized contact sheet.
preview=Image.new('RGBA',(24*3,24*40),'#28545a')
for i,frame in enumerate((0,3,6)):
    preview.alpha_composite(sheet.crop((frame*24,0,(frame+1)*24,24*40)),(i*24,0))
preview.resize((432,5760),Image.Resampling.NEAREST).save('/private/tmp/river-animals-art.png')
