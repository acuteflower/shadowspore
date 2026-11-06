#!/usr/bin/env python3
"""Draw the Void Crusher's palette-locked, two-pass eight-direction sprites."""
from math import cos, sin, pi
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / 'assets/enemies/void_crusher'
SIZE = 80
ANCHOR = (40, 70)
C = {k: '#' + v for k, v in dict(out='040208', dark='07040d', flesh='0e0919', mid='1a1030', high='221740', rim='5a36b8', rim2='6a3fd0', rock0='141221', rock1='292840', rock2='474a6a', rock3='787ea0', eye='ff4fd8', vein='8a4dff', core='ecd2ff').items()}
DIRECTIONS = ('E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE')
ANIMS = {'idle': 4, 'walk': 6, 'windup': 3, 'lock': 1, 'strike': 2, 'hurt': 3, 'death': 4}


def render(direction, animation, frame):
    a = direction * pi / 4
    f = (cos(a), sin(a))
    r = (-sin(a), cos(a))  # anatomical right; never flip an image
    base = Image.new('RGBA', (SIZE, SIZE))
    glow = Image.new('RGBA', (SIZE, SIZE))
    d, g = ImageDraw.Draw(base), ImageDraw.Draw(glow)
    def pt(forward, right, height):
        return (round(40 + f[0]*forward + r[0]*right), round(65 + .48*(f[1]*forward + r[1]*right) - height))
    def poly(points, color, outline='out'):
        d.polygon(points, fill=C[color], outline=C[outline] if outline else None)
    def line(points, color, width=1, glowline=False):
        (g if glowline else d).line(points, fill=C[color], width=width, joint='curve')
    def oval(box, color): d.ellipse(box, fill=C[color], outline=C['out'])
    breath = (0, 1, 0, -1)[frame] if animation == 'idle' else 0
    phase = sin(frame*pi/3) if animation == 'walk' else 0
    lift = [0, 2, 5][frame] if animation == 'windup' else (5 if animation == 'lock' else (1 if animation == 'strike' and frame == 0 else 0))
    lean = [0, 1, 3][frame] if animation == 'windup' else (3 if animation == 'lock' else (6 if animation == 'strike' else (-2 if animation == 'hurt' and frame == 1 else 0)))
    h = 0 if animation == 'death' else breath
    # Project separate anatomical limbs; depth ordering is based on their world positions.
    def leg(side):
        step = phase * (3 if side > 0 else -3)
        hip = pt(-4, side*7, 22+h)
        knee = pt(-3+step*.4, side*8, 11)
        foot = (pt(1+step, side*8, 0)[0], 67 - round(max(0, phase*side)*3))
        line([hip, knee, foot], 'out', 9)
        line([hip, knee, foot], 'flesh', 7)
        line([pt(-4, side*7-1, 21+h), pt(-3+step*.4, side*8-1, 11)], 'mid', 3)
        x,y=foot
        poly([(x-5,y-2),(x+3,y-3),(x+5,y),(x+3,y+2),(x-5,y+2)], 'dark')
        line([(x-4,y-1),(x+2,y-1)], 'mid')
    def tendrils():
        root=pt(0+lean*.3,-13,34+h)
        for i in range(3):
            elbow=pt(3+i*2,-18-i*2,20+h+i)
            tip0=pt(8+i*2,-20-i*2,3+i*2)
            tip=(tip0[0], min(65, tip0[1]))
            line([root,elbow,tip], 'out', 4)
            line([root,elbow,tip], 'flesh', 2)
            line([elbow,tip], 'mid')
            x,y=tip
            poly([(x-1,y),(x+2,y+1),(x+1,y+4),(x-1,y+2)], 'mid')
    def arm():
        root=pt(0+lean*.3,13,36+h)
        elbow=pt(2+lean*.4,19,21+lift+h)
        hand0=pt(8+lean,22,3+lift*3)
        hand=(hand0[0], min(62, hand0[1]))
        line([root,elbow,hand], 'out', 15)
        line([root,elbow,hand], 'rock0', 13)
        line([pt(0+lean*.3,12,36+h),pt(2+lean*.4,18,22+lift+h),(hand[0]-1, hand[1]-2)], 'rock1', 9)
        x,y=elbow
        poly([(x-6,y-6),(x-2,y-10),(x+4,y-8),(x+7,y-4),(x+5,y+1),(x-3,y+3),(x-7,y)], 'rock1')
        poly([(x-5,y-6),(x-2,y-9),(x+3,y-7),(x+4,y-5),(x,y-3),(x-5,y-3)], 'rock2', None)
        line([(x-5,y-7),(x-2,y-9),(x+2,y-8)], 'rim')
        x,y=hand
        poly([(x-7,y-6),(x-3,y-10),(x+4,y-9),(x+8,y-5),(x+7,y+2),(x+3,y+5),(x-5,y+4),(x-8,y)], 'rock0')
        poly([(x-6,y-6),(x-3,y-9),(x+3,y-8),(x+5,y-6),(x+1,y-3),(x-5,y-2)], 'rock2', None)
        poly([(x-3,y-8),(x-1,y-10),(x+3,y-8),(x+2,y-7)], 'rock3', None)
        line([(x-5,y+1),(x-1,y-1),(x+2,y+1),(x+5,y)], 'rock1')
        p1=pt(1+lean*.3,14,34+h); p2=pt(3+lean*.4,19,23+lift+h); p3=pt(7+lean,21,8+lift*3)
        line([p1,p2,p3], 'vein', 1, True)
        line([p2,(p2[0]+3,p2[1]+3)], 'vein', 1, True)
    # Draw behind parts first, preserving left/right asymmetry for every view.
    parts=[(pt(-3,-8,0)[1],lambda:leg(-1)),(pt(-3,8,0)[1],lambda:leg(1)),(pt(2,-20,0)[1],tendrils),(pt(2,20,0)[1],arm)]
    for y,draw in sorted(parts,key=lambda x:x[0]):
        if y < 65: draw()
    # Torso and layered armor: chunky clusters, no dither or soft edges.
    bx,by=pt(-3+lean*.3,0,25+h)
    poly([(bx-13,by-13),(bx-9,by-20),(bx+8,by-20),(bx+14,by-13),(bx+15,by+1),(bx+10,by+14),(bx+3,by+20),(bx-9,by+17),(bx-15,by+7)], 'flesh')
    poly([(bx-11,by-12),(bx-7,by-18),(bx+5,by-18),(bx+11,by-10),(bx+9,by+4),(bx+4,by+10),(bx-9,by+6)], 'mid')
    poly([(bx-10,by+1),(bx-4,by+4),(bx+2,by+3),(bx+6,by+9),(bx+2,by+15),(bx-7,by+13)], 'dark')
    # Segmented, sloping horn mantle. Direction changes shift the facing plate.
    shift=round(f[0]*3)
    for side in (-1,1):
        x=bx+side*10; y=by-16
        poly([(x-side*3,y+4),(x-side*4,y-4),(x+side*1,y-9),(x+side*7,y-7),(x+side*10,y-2),(x+side*7,y+5),(x+side*2,y+7)], 'high')
        line([(x-side*3,y-3),(x+side*1,y-7),(x+side*6,y-6)], 'rim')
        line([(x-side*3,y+3),(x+side*2,y+1),(x+side*7,y+2)], 'mid', 2)
    hx,hy=pt(8+lean,0,36+h)
    poly([(hx-10,hy-7),(hx-6,hy-12),(hx+5,hy-12),(hx+10,hy-7),(hx+9,hy+3),(hx+4,hy+8),(hx-6,hy+7),(hx-10,hy+2)], 'dark')
    poly([(hx-9,hy-7),(hx-6,hy-11),(hx+5,hy-11),(hx+9,hy-7),(hx+7,hy-4),(hx-7,hy-4)], 'high')
    line([(hx-7,hy-10),(hx+3,hy-10),(hx+7,hy-7)], 'rim')
    # Facing the viewer exposes a recessed visor. Looking away exposes the nape.
    if f[1] > -0.35:
        line([(hx-7,hy),(hx+6,hy+1)], 'out', 3)
        eyes = [-5,-1,3] if f[1] > .35 else ([-2,2] if f[0]>0 else [-4,0])
        for x in eyes: line([(hx+x,hy),(hx+x+1,hy)], 'eye', 1, True)
    if f[1] < .35:
        cx=bx-round(f[0]*4); cy=by-4
        poly([(cx-4,cy-5),(cx+3,cy-5),(cx+4,cy+5),(cx+1,cy+11),(cx-3,cy+8)], 'dark')
        line([(cx,cy-3),(cx-1,cy+1),(cx+1,cy+4),(cx,cy+8)], 'vein', 3, True)
        line([(cx,cy-2),(cx,cy+5)], 'core', 1, True)
        line([(cx+2,cy),(cx+6,cy-2)], 'vein', 1, True)
    for y,draw in sorted(parts,key=lambda x:x[0]):
        if y >= 65: draw()
    # Add a single-pixel silhouette outline without altering internal clusters.
    alpha=base.getchannel('A')
    outline=Image.new('RGBA',(SIZE,SIZE),C['out'])
    outline.putalpha(alpha.filter(ImageFilter.MaxFilter(3)))
    outline.alpha_composite(base)
    base=outline
    # Constrain emissive pixels to the visible silhouette: no floating glow or halos.
    ga=glow.getchannel('A')
    import PIL.ImageChops
    glow.putalpha(PIL.ImageChops.multiply(ga,base.getchannel('A')))
    if animation == 'death' and frame:
        # Collapse to the shared foot anchor, nearest-neighbor only.
        height=(64,52,35,19)[frame]
        def squash(img):
            crop=img.crop((0,7,80,71)).resize((80,height),Image.Resampling.NEAREST)
            result=Image.new('RGBA',(80,80)); result.alpha_composite(crop,(0,71-height)); return result
        base,glow=squash(base),squash(glow)
    return base,glow


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    for anim,count in ANIMS.items():
        sheets=[Image.new('RGBA',(SIZE*count,SIZE*len(DIRECTIONS))) for _ in range(2)]
        for direction in range(len(DIRECTIONS)):
            for frame in range(count):
                for sheet,img in zip(sheets,render(direction,anim,frame)):
                    sheet.alpha_composite(img,(frame*SIZE,direction*SIZE))
        sheets[0].save(OUT / f'void_crusher_{anim}.png')
        sheets[1].save(OUT / f'void_crusher_{anim}_glow.png')
    print('Wrote',sum(ANIMS.values())*len(DIRECTIONS),'paired frames to',OUT)

if __name__ == '__main__': main()
