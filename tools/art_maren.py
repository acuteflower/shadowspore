"""Maren, the river keeper: eight independent views and four seamless loops.

OPENBLAS_NUM_THREADS=1 .venv/bin/python tools/art_maren.py [contact-sheet.png]
The textures are geometric, part of the same model as the body; the braid has
phase-delayed motion. Work depicts mending a small hand-held net, not hammering.
"""
import json
import math
import multiprocessing as mp
import os
import sys
from pathlib import Path

import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 72, 76, 62
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 0.98
BASE = len(h.RAMPS)
HAIR, HAIR_L, SKIN, EYES, LINEN, LINEN_D, APRON, LEATHER, BOOT, REED, BONE = range(BASE, BASE + 11)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['29232b', '504147', '78645e', 'ac9689'],  # ashy brown plait
    ['3c3035', '6a5755', '96827a', 'c6b3a3'],
    ['805c50', 'ae7b68', 'd4a18b', 'efc5a9'],  # wind-weathered skin
    ['382821', '775236', 'ba8949', 'ebc778'],  # amber
    ['222733', '394952', '617379', '93a1a0'],  # waxed river-slate linen
    ['1b202a', '303a42', '4c5b5d', '76827d'],
    ['292a2d', '4c4d44', '777462', 'a6a08a'],  # oilskin moss
    ['29212a', '4b3735', '765849', 'a68469'],
    ['211b25', '3e3030', '635044', '8d7460'],
    ['423d34', '716550', 'a59a79', 'd3c5a2'],  # reeds, undyed fibre
    ['6c625a', 'a99b88', 'dbceb4', 'f1e7d2'],  # polished bone
]]
# The common face painter supplies legible eyes at native sprite size; this
# process uses Maren's amber eye ramp rather than Ellie's violet one.
h.EYE = EYES
h.DECAL_WEIGHT[EYES] = 2.4
V = lambda *args: np.array(args, float)
CLIPS = {
    'idle': {'start': 0, 'count': 8, 'fps': 5},
    'walk': {'start': 8, 'count': 8, 'fps': 8},
    'run': {'start': 16, 'count': 8, 'fps': 10},
    'work': {'start': 24, 'count': 12, 'fps': 8},
}


def pose(kind, i):
    n = CLIPS[kind]['count']
    phase = math.tau * i / n
    s, c = math.sin(phase), math.cos(phase)
    moving = kind in ('walk', 'run')
    stride = 5.3 if kind == 'run' else 3.5
    lift = 3.0 if kind == 'run' else 1.9
    feet = ((2.8, stride*s, lift*max(c, 0)), (-2.8, -stride*s, lift*max(-c, 0))) if moving else ((2.9, .5, 0), (-2.9, -.5, 0))
    return {'feet': feet, 'phase': phase, 'breath': .5-.5*c,
            'lean': .12 if kind == 'run' else (.08 if kind == 'work' else .025),
            'swing': s if moving else 0.0, 'moving': moving}


def build(p, kind):
    m = h.Model()
    ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None))
    for hip, knee, ankle, *_ in legs:
        limb(hip, knee, 2.5, 2.15, LINEN_D)
        limb(knee, ankle, 2.15, 1.8, BOOT)
        ell(knee+(ankle-knee)*.35, (2.35, 2.2, 2.2), BOOT)
        ell(ankle+V(0,-1,1.35), (2.0,1.45,3.1), BOOT)
        ell(ankle+V(0,1.1,-.2), (2.0,2.2,2.1), BOOT)
    m.off = V(0, drop, 0)
    R = h.rot_x(p['lean'])
    def T(v):
        return V(0,26,0) + R @ (np.asarray(v,float) - V(0,26,0))
    ell(T((0,24.5,0)), (4.3,3.3,3.3), LINEN_D, R=R)
    # Long waxed linen kittel, with separated hems and restrained seam lines.
    ell(T((0,31.2,.1)), (4.9,7.6,3.6), LINEN, R=R)
    ribbon([T((0,27,0)),T((0,19,0)),T((0,14,-.4))], [4.5,5.0,4.9], 2.7, LINEN_D, (0,0,1), kind='')
    for side in (-1,1):
        ribbon([T((side*3.3,26.0,2.7)),T((side*3.8,19,2.6)),T((side*3.9,15.2,2.3))], [.32,.35,.25], .18, LINEN, (0,0,1), kind='')
    # Reinforced apron over waxed fabric, large shapes with quiet hand stitching.
    ribbon([T((0,36,3.2)),T((0,30,4.1)),T((0,24,4.1)),T((0,15,3.5))], [2.7,3.4,4.0,4.2], .48, APRON, (0,0,1), kind='')
    for side in (-1,1):
        ribbon([T((side*3.0,38,0)),T((side*2.8,34,2.9)),T((side*2.6,31,4.1))], [.42,.42,.42], .28, LEATHER, (0,0,1), kind='')
        ribbon([T((side*3,38,-1)),T((0,33,-3.9)),T((-side*3.1,27,-3.1))], [.36,.38,.38], .25, LEATHER, (0,0,1), kind='')
        for y in (19.1,21.0,22.9):
            ell(T((side*3.35,y,4.1)), (.18,.42,.18), REED, R=R)
    ell(T((0,26.7,3.95)),(4.4,.7,.8),LEATHER,R=R)
    ell(T((0,26.7,4.75)),(.8,.65,.3),BONE,R=R)
    ell(T((3.4,23.3,3.7)),(1.4,1.7,.6),LEATHER,R=R)
    # Right hip: an ivory bone awl and its dark sheath, fixed in model space.
    limb(T((-4.7,26,1.5)),T((-5.1,19.5,2.0)),.6,.5,LEATHER)
    limb(T((-4.7,25.8,1.7)),T((-4.7,29.4,1.5)),.4,.32,BONE)
    for side in (-1,1):
        sh = T((side*4.7,37,0))
        if kind == 'work':
            target = T((side*(3.3 + .45*math.sin(p['phase']+side*.6)), 29.3 + .7*math.sin(p['phase']+side), 6.5))
        else:
            target = T((side*5.4,25.5,side*p['swing']*1.9+.5))
        elbow, wrist = h.ik2(sh, target, 6.4, 6.1, (side,-.3,-.7))
        limb(sh,elbow,1.8,1.65,LINEN)
        limb(elbow,wrist,1.55,1.15,LINEN_D)
        # Multiple alternating reed wraps form a clear textured cuff.
        for j in range(3):
            v=elbow*.24+wrist*.76+(elbow-wrist)*(j*.12)
            ell(v,(1.5,.48,1.5),REED if j != 1 else LEATHER,R=R)
        ell(wrist,(1.35,1.55,1.35),SKIN,R=R)
    hc = T((0,44.5 + .18*p['breath'],.4))
    ell(hc,(4.55,5.1,4.4),SKIN,R=R,kind='head')
    ell(hc+R@V(0,3.3,-.7),(4.7,2.55,4.1),HAIR,R=R)
    # Swept hairline and temples, without changing the face silhouette.
    for side in (-1,1):
        ell(hc+R@V(side*3.8,1.5,.3),(1.0,2.4,2.0),HAIR,R=R)
        ell(hc+R@V(side*4.35,-.35,.0),(.62,1.05,.65),SKIN,R=R)
    ell(hc+R@V(0,-.65,4.15),(.65,.9,.75),SKIN,R=R)
    # A single tied plait with interwoven alternating lobes. Roots are anchored;
    # the tip lags smoothly behind the walking cycle and rests in idle.
    phase = p['phase']
    amp = 1.15 if p['moving'] else .16
    centers=[]
    for j in range(9):
        t=j/8
        drift=amp*t*t*math.sin(phase-1.2*t)
        centers.append(hc+R@V(drift, 1.0-18.0*t, -3.9-1.8*t-.35*math.cos(phase-1.1*t)*t))
    for j,center in enumerate(centers):
        r=1.8*(1-.52*j/8)
        ell(center,(r,r*1.25,r*.9),HAIR,R=R)
        if j < 8:
            ell(center+R@V((-.62 if j%2 else .62),-.35,-.4),(r*.62,r*.8,r*.65),HAIR_L,R=R)
        if j in (2,5,8):
            ell(center,(r*1.08,.3,r),REED,R=R)
    # Loose hand-held net patch while she works; anchored between her hands.
    if kind == 'work':
        flutter=.35*math.sin(phase)
        for j in range(4):
            x=-2.2+j*1.45
            limb(T((x,29.0,6.6)),T((x+flutter,24.9,6.8)),.12,.12,REED,step=1.0)
        for j in range(3):
            y=28.7-j*1.65
            limb(T((-2.2,y,6.7)),T((2.2,y-.3,6.7)),.12,.12,REED,step=1.0)
    return m


def render_one(job):
    sector, index, kind, i = job
    model=build(pose(kind,i),kind)
    yaw=math.pi/2-sector*math.pi/4
    depth,code,_=h.render(model.transform(yaw,0),yaw,0)
    return sector,index,np.asarray(h.to_pixels(depth,code),dtype=np.uint8).tobytes()


def main():
    count=sum(c['count'] for c in CLIPS.values())
    jobs=[(s,c['start']+i,name,i) for s in range(8) for name,c in CLIPS.items() for i in range(c['count'])]
    atlas=np.zeros((8*FH,count*FW,4),dtype=np.uint8)
    workers=min(6,os.cpu_count() or 1)
    print(f'Rendering {len(jobs)} Maren frames with {workers} workers',flush=True)
    with mp.Pool(workers) as pool:
        for s,i,data in pool.imap_unordered(render_one,jobs,chunksize=2):
            atlas[s*FH:(s+1)*FH,i*FW:(i+1)*FW]=np.frombuffer(data,dtype=np.uint8).reshape(FH,FW,4)
    write_array(ROOT/'characters/maren.png',atlas)
    rig={'frame':[FW,FH],'feet':[FW//2,GROUND],'frames':count,'rows':8,'clips':CLIPS}
    (ROOT.parent/'data/maren_rig.json').write_text(json.dumps(rig,indent=2)+'\n')
    if len(sys.argv)>1:
        from PIL import Image,ImageDraw
        bg=(38,34,50); out=Image.new('RGB',(5*FW*3,8*FH*3),bg); draw=ImageDraw.Draw(out)
        for s,direction in enumerate(('E','SE','S','SW','W','NW','N','NE')):
            for col,index in enumerate((0,8,10,24,30)):
                tile=Image.new('RGBA',(FW,FH),bg+(255,))
                tile.alpha_composite(Image.fromarray(atlas[s*FH:(s+1)*FH,index*FW:(index+1)*FW]))
                out.paste(tile.convert('RGB').resize((FW*3,FH*3),Image.Resampling.NEAREST),(col*FW*3,s*FH*3))
            draw.text((4,s*FH*3+4),direction,fill='white')
        out.save(sys.argv[1])
    print('Maren sprites and rig written',flush=True)

if __name__=='__main__':
    main()
