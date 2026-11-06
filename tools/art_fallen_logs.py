"""Fallen trunks rendered with the game's existing tree/knight/hut pixel renderer.
Three models in eight baked facings, no rotated/filtered sprites at runtime.
python3 tools/art_fallen_logs.py -> fallen_logs.png, _glow.png, fallen_logs.json
"""
import json
import math
import numpy as np
import art_hero3d as h
from gen_art import ROOT, CLEAR, hexc, write_png

h.FW, h.FH, h.GROUND_ROW, h.SCALE = 112, 80, 43, 1.0
BASE = len(h.RAMPS)
BARK, GROOVE, WOOD, MOSS, EARTH, RIDGE, SHELF = range(BASE, BASE+7)
h.RAMPS += [[hexc(c) for c in row] for row in [
 ['1a1322','34283c','55435a','85697a'],
 ['0e0914','1d1428','33253d','4d3a54'],
 ['5c4852','8b727c','bda3a8','e6d3cf'],
 ['14281f','2f624e','3e7d56','55985f'],
 ['150f0e','2a1f1a','42332a','685344'],
 ['34283c','55435a','85697a','b09690'],
 ['1a4a52','2f8a8c','6ae0d2','9af0dc']]]
V=lambda *p: np.array(p,float)

def build(variant):
    """Uneven bark plates and grain follow the length, like the standing spruce.
    Overlapping axial volumes prevent the old transverse 'stack of coins' seams.
    Dimensions and ground anchors intentionally stay identical to revision 1.
    """
    rng=np.random.default_rng(571+variant*73)
    m=h.Model()
    half=[34.,26.,38.][variant]
    radius=[5.8,4.8,6.4][variant]
    def spine(x):
        return V(x,radius+.4,math.sin(x*.07+variant)*1.2)
    def rad(x):
        return radius*(.96-.10*x/half) + .18*math.sin(x*.31+variant)
    def surf(x,phi,lift=0):
        p=math.radians(phi)
        r=rad(x)
        return spine(x)+V(0,(r+lift)*math.cos(p),(r+lift)*math.sin(p)*.97)
    def surface_ell(x,phi,rx,ry,rz,mat,lift=.1):
        m.ell(surf(x,phi,lift),(rx,ry,rz),mat,R=h.rot_x(math.radians(phi)))

    for x in np.arange(-half,half+.4,.7):
        r=rad(x)
        m.ell(spine(x),(3.2,r,r*.97),BARK)

    # Broad broken plates, then dark meandering fissures and their raised lit lip.
    for phi in [-42,-10,19,47,77,110,146,183,223,271]:
        start=-half+rng.uniform(2,8)
        while start < half-4:
            length=rng.uniform(5,11)
            x=min(start+length*.5,half-3)
            surface_ell(x,phi+rng.uniform(-5,5),length*.5,.45,
                        rng.uniform(.55,1.1),GROOVE if rng.random()<.27 else BARK,lift=.05)
            start += length+rng.uniform(1,4)
        xs=np.arange(-half+2,half-2,2.0)
        pts=[surf(x,phi+7*math.sin(x*.17+phi*.07)+3*math.sin(x*.39),.17) for x in xs]
        for i,(a,b) in enumerate(zip(pts,pts[1:])):
            if rng.random()<.84:
                m.limb(a,b,.45,.33,GROOVE)
                if i%4!=0:
                    # Offset along the surface, rather than across the trunk.
                    x=xs[i]
                    m.limb(surf(x,phi-4+7*math.sin(x*.17+phi*.07),.26),
                           surf(x+1.7,phi-4+7*math.sin((x+1.7)*.17+phi*.07),.26),
                           .27,.23,RIDGE)

    # Individual knots / old branch scars, with an inset dark eye and a bark rim.
    for x,phi in [(-half*.34,56),(half*.31,-24),(half*.58,118)]:
        surface_ell(x,phi,3.3,.35,2.0,GROOVE,.27)
        surface_ell(x-.35,phi-1,2.8,.38,1.65,RIDGE,.44)
        surface_ell(x+.15,phi,2.1,.39,1.1,BARK,.65)
        surface_ell(x+.3,phi,1.25,.41,.65,GROOVE,.79)
        m.limb(surf(x-4,phi,.25),surf(x-6,phi-5,.25),.35,.2,GROOVE)
    if variant==2:
        # A small hollow in the rotten bark, not an oversized black hole.
        surface_ell(-4,69,4.5,.4,2.8,RIDGE,.2)
        surface_ell(-3.6,69,3.6,.55,2.0,GROOVE,.51)
        surface_ell(12,-15,5.0,.35,1.8,WOOD,.18) # exposed splintered wood
        for dx in [-2,0,2]:
            m.limb(surf(10+dx,-20,.4),surf(14+dx,-14,.4),.22,.18,BARK)

    # The knight's layered, uneven annual rings, with radial splits and splinters.
    for side in [-1,1]:
        end=side*(half+.7)
        r=rad(side*half)
        for k,(factor,mat) in enumerate([(1.,BARK),(.91,WOOD),(.75,GROOVE),
                                         (.67,WOOD),(.50,GROOVE),(.42,WOOD),(.20,BARK)]):
            m.ell(spine(side*half)+V(side*(.8+.16*k),0,0),
                  (.7,r*factor,r*factor*.97),mat)
        for phi in [35,151,263]:
            angle=math.radians(phi+variant*13)
            center=spine(side*half)+V(side*2.0,0,0)
            m.limb(center,center+V(0,math.cos(angle)*r*.8,math.sin(angle)*r*.8),.3,.16,GROOVE)
        for k in range(3 if variant==1 else 4):
            phi=42+k*83+variant*11
            a=surf(side*(half-1),phi,.05)
            b=a+V(side*rng.uniform(3,5.5),rng.uniform(-.5,1),rng.uniform(-.5,.5))
            m.limb(a,b,.7,.15,WOOD if k%2 else BARK)

    # Root flare, soil wedged into the base and asymmetric forked root fingers.
    if variant!=1:
        m.ell(spine(-half+1)+V(1,-1.7,0),(3.7,4.3,5.5),BARK)
        m.ell(V(-half-2,2.3,0),(3.2,2.5,5.5),EARTH)
        for i in range(4):
            a=spine(-half+2)+V(0,-2,(i-1.5)*2.1)
            b=V(-half-6-rng.random()*3,1.2,(i-1.5)*5)
            m.limb(a,b,2.2,.55,BARK)
            m.limb(a+V(0,.7,0),b+V(0,.4,0),.45,.22,GROOVE)
            m.limb(b,b+V(-1.7,0,(-1 if i%2 else 1)*2.3),.65,.18,BARK)
        for i in range(5):
            m.ell(V(-half+rng.uniform(-5,1),1.0,rng.uniform(-6,6)),(1.2,.9,1.0),EARTH)

    # Broken-off branches have collars and real exposed pale end grain.
    for x,z in [(-half*.3,1.),(half*.45,-1.)]:
        a=surf(x,65 if z>0 else -60,.1)
        b=a+V(3,1.8,z*6)
        m.ell(a,(2.5,2.1,2.0),GROOVE)
        m.limb(a,b,1.7,.95,BARK)
        m.ell(b,(.85,.7,.85),WOOD)
        m.limb(a+V(-.3,.6,0),b+V(-.3,.5,0),.27,.16,RIDGE)

    # Moss grows as ragged overlapping cushions with little lips and hanging ends.
    for patch in range([6,4,8][variant]):
        x=rng.uniform(-half*.83,half*.80)
        phi=rng.uniform(-32,38)
        surface_ell(x,phi,rng.uniform(2.4,4.1),.65,1.8,MOSS,.25)
        for k in range(rng.integers(3,6)):
            dx=rng.uniform(-3.3,3.3)
            dp=rng.uniform(-15,18)
            surface_ell(x+dx,phi+dp,rng.uniform(.8,1.8),.55,
                        rng.uniform(.6,1.2),MOSS,.75)
        if patch%2==0:
            a=surf(x+2,phi+34,.5)
            m.limb(a,a+V(.4,-1.5,1.5),.45,.2,MOSS)

    # Connected crooked violet cracks with sparse forks (same scale as the knight).
    for trail in range(1 if variant==1 else 2):
        x=-half*rng.uniform(.25,.8)
        phi=16 if trail==0 else 72
        pts=[]
        for k in range(8):
            pts.append(surf(x,phi,.38))
            x += rng.uniform(1.7,3.8)
            phi += rng.uniform(-11,10)
        for k,(a,b) in enumerate(zip(pts,pts[1:])):
            m.limb(a,b,.42,.32,h.VIOLET,kind='emit')
            if k==3:
                m.limb(a,a+V(2,-1.1,1.2),.30,.17,h.VIOLET,kind='emit')

    # Layered bracket fungi: dark attachment, broad cool cap, pale rim, smaller shelf.
    for i in range(1 if variant==1 else 2):
        x=-half*.4+i*half*.72
        a=surf(x,70,.7)
        m.ell(a+V(0,-.5,0),(2.4,.8,1.65),GROOVE)
        m.ell(a+V(0,.1,.6),(2.8,.55,1.9),SHELF,kind='emit')
        m.ell(a+V(.2,.35,.8),(2.4,.25,1.5),h.TEAL,kind='emit')
        m.ell(a+V(.9,-1.65,1.1),(1.8,.4,1.35),SHELF,kind='emit')
    return m,half

sheet=[[CLEAR]*(112*8) for _ in range(80*3)]
glow=[[CLEAR]*(112*8) for _ in range(80*3)]
metadata=[]
glow_colors={hexc(c) for mat in [h.TEAL,h.VIOLET,SHELF] for c in ['%02x%02x%02x'%tuple(p[:3]) for p in h.RAMPS[mat]]}
for variant in range(3):
    model,half=build(variant)
    for facing in range(8):
        yaw=facing*math.tau/8
        depth,code=h.render(model.transform(yaw,0))
        pixels=h.to_pixels(depth,code)
        # Anchor at the forwardmost ground contact for correct world Y sorting.
        foot=abs(math.sin(yaw))*half*h.SINP+5
        a=[-half*math.cos(yaw), half*math.sin(yaw)*h.SINP-foot]
        b=[ half*math.cos(yaw),-half*math.sin(yaw)*h.SINP-foot]
        metadata.append({'variant':variant,'facing':facing,'anchor':[56,43+foot],'a':a,'b':b,'radius':4.5 if variant==1 else 5.5})
        for y,row in enumerate(pixels):
            for x,c in enumerate(row):
                if c[3]==70: c=CLEAR # runtime contact shadow follows collision footprint
                sheet[variant*80+y][facing*112+x]=c
                if c in glow_colors: glow[variant*80+y][facing*112+x]=c
        print('log',variant,'facing',facing,flush=True)
write_png(ROOT/'props'/'fallen_logs.png',896,240,sheet)
write_png(ROOT/'props'/'fallen_logs_glow.png',896,240,glow)
(ROOT.parent/'data'/'fallen_logs.json').write_text(json.dumps({'frames':metadata,'cell':8,'chance':.42},separators=(',',':'))+'\n')
print('FALLEN LOGS: 24 baked frames')
