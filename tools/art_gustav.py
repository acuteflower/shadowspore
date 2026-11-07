"""Gustav, Shadowspore's carpenter. Eight true directions, idle/walk/run/work.

OPENBLAS_NUM_THREADS=1 .venv/bin/python tools/art_gustav.py [preview.png]
Outputs assets/characters/gustav.png and data/gustav_rig.json.
"""
import json, math, multiprocessing as mp, os, sys
from pathlib import Path
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW,FH,GROUND=72,76,62
h.FW,h.FH,h.GROUND_ROW,h.SCALE=FW,FH,GROUND,1.0
BASE=len(h.RAMPS)
HAIR,SHIRT,APRON,APRON_D,TROUSERS,WOOD,SKIN,MOUSTACHE=range(BASE,BASE+8)
h.RAMPS += [[hexc(c) for c in row] for row in [
 ['29232e','56505c','89828b','c4bbc2'], ['292b40','4a4d62','74788b','aaa9b2'],
 ['39222b','684135','94624a','c08b67'], ['241b25','49302d','704a3c','a67556'],
 ['191725','302b3c','4e4557','756877'], ['614530','987452','c69e70','edd0a0'],
 ['9e6b60','c9947f','e5b39a','f3d2b7'], ['302932','5a5055','938888','c6b6ae']]]
V=lambda *x: np.array(x,float)


def pose(kind,i):
    if kind in ('walk','run'):
        a=2*math.pi*i/6; s=math.sin(a); c=math.cos(a)
        stride=5.8 if kind=='run' else 4.0
        lift=3.2 if kind=='run' else 2.2
        return dict(feet=((3.0,stride*s,lift*max(c,0)),(-3.0,-stride*s,lift*max(-c,0))), breath=.3, lean=.12 if kind=='run' else .035, swing=s, work=0)
    if kind=='work':
        # Six poses strike on frame 3; the arm and mallet follow the same grip.
        return dict(feet=((3.0,1.0,0),(-3.0,-1.0,0)),breath=.3,lean=[.04,.02,.05,.23,.16,.08][i],swing=0,work=[0,.35,.9,1,.55,.15][i])
    return dict(feet=((3.0,0,0),(-3.0,0,0)),breath=[0,.45,.85,.45][i],lean=.025,swing=0,work=0)


def build(p,kind):
    m=h.Model(); ell,limb,ribbon=m.ell,m.limb,m.ribbon
    legs,drop=h.pose_legs(dict(p,pz=0,hair=None)); off=V(0,drop,0)
    for hip,knee,ankle,*_ in legs:
        limb(hip,knee,3.0,2.65,TROUSERS); limb(knee,ankle,2.6,2.0,TROUSERS)
        ell(ankle+V(0,-1,1.3),(2.35,1.65,3.3),APRON_D)
        ell(ankle+V(0,1.1,-.1),(2.3,2.0,2.4),APRON_D)
    m.off=off
    lean=p['lean']; R=h.rot_x(lean); b=p['breath']
    def T(v):
        return V(0,26,0)+R@(np.asarray(v,float)-V(0,26,0))
    ell(T((0,25,0)),(5.1,3.4,3.7),TROUSERS,R=R)
    ell(T((0,31.0,1.0)),(7.1,6.9,5.8),SHIRT,R=R)
    ell(T((0,35.4,0)),(7.0,4.5,4.2),SHIRT,R=R)
    # Leather apron bib and skirt: broad front; back straps are asymmetric in projection.
    ribbon([T((0,37,4.7)),T((0,32,7.4)),T((0,25,5.8)),T((0,15,4.4))],[4.0,4.6,5.2,5.5],.55,APRON,(0,0,1),kind='')
    for side in (-1,1):
        ribbon([T((side*3,39,0)),T((side*3,37,3.2)),T((side*3,35,4.7))],[.65,.65,.65],.25,APRON_D,(0,0,1),kind='')
        ribbon([T((side*3,39,-2)),T((0,33,-5.3)),T((-side*3.5,27,-4.0))],[.65,.65,.65],.25,APRON_D,(0,0,1),kind='')
        ell(T((side*3,35.4,5.0)),(.65,.65,.35),h.GOLD,R=R)
    ell(T((0,27.0,6.8)),(4.8,.7,.55),APRON_D,R=R)
    ell(T((.1,27.0,7.35)),(1.0,.75,.3),h.GOLD,R=R)
    ell(T((1.8,22.0,5.8)),(2.2,2.3,.65),APRON_D,R=R)
    ell(T((1.8,23.8,6.4)),(2.3,.45,.35),APRON,R=R)
    # Left pouch and right carpenter's ruler preserve actual physical asymmetry.
    ell(T((5.8,24,-.6)),(2.0,2.6,1.65),APRON_D,R=R)
    ell(T((5.8,26,-.6)),(2.1,.65,1.8),APRON,R=R)
    limb(T((-4.0,24.0,5.0)),T((-4.0,31.5,4.5)),.46,.46,WOOD)
    for side in (-1,1):
        shoulder=T((side*6.0,37.5,0)); el=T((side*7.7,31.0,0))
        if kind=='work' and side==-1:
            hand=T((-6.0+2.0*p['work'],25.0+8.0*(1-p['work']),6.3)); el=T((-8.0,31.0,2.0))
        else:
            hand=T((side*7.0,25.0,side*p['swing']*2.0))
        limb(shoulder,el,2.4,2.05,SHIRT); ell(el,(2.3,1.3,2.3),SHIRT,R=R)
        limb(el,hand,2.0,1.7,SKIN);ell(hand,(1.8,2.0,1.8),SKIN)
        if kind=='work' and side==-1:
            direction=V(-.35, .85-1.4*p['work'], .4);direction/=np.linalg.norm(direction)
            tip=hand+direction*8
            limb(hand-direction*1.7,tip,.55,.55,WOOD)
            ell(tip,(2.6,1.5,1.5),APRON_D,R=h.rot_x(-p['work']*.7))
    hc=T((0,44+b*.22,.4)); ell(hc,(4.9,5.2,4.8),SKIN,R=R)
    # Lively hair cap, a few large silver locks and two very readable moustache lobes.
    ell(hc+R@V(0,3.5,-.6),(5.0,2.4,4.5),HAIR,R=R)
    for x,y,z in [(-3.5,3.9,0),(-1.9,5,-.4),(.1,5.1,-1.1),(2.0,4.7,-.7),(3.8,3.5,-.5),(-4.3,.7,-1.8),(4.3,.7,-1.8)]:
        ell(hc+R@V(x,y,z),(1.3,1.45,1.35),HAIR,R=R)
    for side in (-1,1):
        ell(hc+R@V(side*2.0,.35,4.45),(.72,.7,.55),h.EYE,R=R)
        ell(hc+R@V(side*1.35,-1.7,4.8),(1.65,.75,.75),MOUSTACHE,R=R)
        ell(hc+R@V(side*4.7,-.55,.1),(.8,1.35,.7),SKIN,R=R)
    ell(hc+R@V(0,-.9,4.8),(.85,1.1,.8),SKIN,R=R)
    # Pencil tucked behind his right ear, never mirrored.
    limb(hc+R@V(-4.8,-.2,-.55),hc+R@V(-5.1,4.2,-.9),.32,.32,WOOD)
    ell(hc+R@V(-5.1,4.3,-.9),(.4,.4,.4),h.GOLD,R=R)
    return m


def render_one(job):
    sector,index,kind,i=job; p=pose(kind,i); model=build(p,kind)
    yaw=math.pi/2-sector*math.pi/4
    depth,code,_=h.render(model.transform(yaw,0),yaw,0)
    return sector,index,np.asarray(h.to_pixels(depth,code),dtype=np.uint8).tobytes()


def main():
    clips={'idle':{'start':0,'count':4,'fps':4},'walk':{'start':4,'count':6,'fps':8},'run':{'start':10,'count':6,'fps':10},'work':{'start':16,'count':6,'fps':7,'strike':3}}
    jobs=[(s,entry['start']+i,k,i) for s in range(8) for k,entry in clips.items() for i in range(entry['count'])]
    arr=np.zeros((8*FH,22*FW,4),dtype=np.uint8)
    print('Rendering',len(jobs),'Gustav poses',flush=True)
    with mp.Pool(min(6,os.cpu_count() or 1)) as pool:
        for s,i,data in pool.imap_unordered(render_one,jobs,chunksize=2):
            arr[s*FH:(s+1)*FH,i*FW:(i+1)*FW]=np.frombuffer(data,dtype=np.uint8).reshape(FH,FW,4)
    write_array(ROOT/'characters/gustav.png',arr)
    (ROOT.parent/'data/gustav_rig.json').write_text(json.dumps({'frame':[FW,FH],'feet':[FW//2,GROUND],'frames':22,'rows':8,'clips':clips},indent=2)+'\n')
    if len(sys.argv)>1:
        from PIL import Image,ImageDraw
        canvas=Image.new('RGB',(4*FW*3,8*FH*3),(38,34,50))
        for s in range(8):
            for j,i in enumerate([0,4,6,19]):
                src=Image.fromarray(arr[s*FH:(s+1)*FH,i*FW:(i+1)*FW]); tile=Image.new('RGBA',(FW,FH),(38,34,50,255));tile.alpha_composite(src)
                canvas.paste(tile.convert('RGB').resize((FW*3,FH*3),Image.Resampling.NEAREST),(j*FW*3,s*FH*3))
        canvas.save(sys.argv[1])
    print('Gustav sheet and rig written',flush=True)

if __name__=='__main__': main()
