#!/usr/bin/env python3
"""Deer, badger, fox and hedgehog via the established miniature 3D pixel renderer.
64x64 feet (32,52), 44 columns: idle4, forage6, walk8, alert4, run8, groom4, sleep4, special6.
Three builds, eight true facings per species; deer builds are doe / roe buck / fawn.
python3 tools/art_woodland.py [--preview-only]
"""
import math,sys
from pathlib import Path
import numpy as np
import art_hero3d as art
from gen_art import CLEAR,hexc
from world_data import save_png
ROOT=Path(__file__).resolve().parent.parent;W=H=64;COLS=44
art.FW,art.FH,art.GROUND_ROW,art.SS,art.SCALE=W,H,52.,3,1.
art.DECAL_WEIGHT={3:3.2,4:3.,5:1.8}
art.ink_color=lambda mat:hexc('332a37' if mat!=3 else '201d2b')
BLOCKS=[('idle',0,4),('forage',4,6),('walk',10,8),('alert',18,4),('run',22,8),('groom',30,4),('sleep',34,4),('special',38,6)]

def materials(species,v):
    coats={'deer':[['57404a','8c6658','b88c6c','dcb993'],['4d3b49','7d5e53','a7866c','d2b99a'],['65464d','a17458','cc9b6f','ecd0a0']],
      'badger':[['363342','626070','93919b','c4c1c0'],['3d3545','716576','a399a4','d2c9cc'],['3b353f','6e6368','a19799','cbc4bf']],
      'fox':[['66404a','aa6751','d39566','edc897'],['64505b','9c7c70','c6a68d','e8d1ae'],['533746','8e5650','bd8061','ddb18a']],
      'hedgehog':[['493845','796052','a38b70','cbb59a'],['403640','68594d','94806a','baa88b'],['59434b','8c6d59','b69874','d9c3a1']]}
    art.RAMPS=[[hexc(c) for c in r] for r in [coats[species][v],['897a83','b4a59f','dfd0b9','f8e9d2'],['24212e','3c3442','5b4b58','806876'],['12121e']*4,['a8a4a1','d0cabc','e9e1cd','fff4df'],['5f4c53','93716c','bb9690','dabbb0']]]
    if species=='hedgehog':
        art.RAMPS[2]=[hexc(c) for c in ['29262b','443b37','6f5c47','a38b69']]
        art.RAMPS[5]=[hexc(c) for c in ['68504c','9b7a62','c5a17f','e1c39e']]

def limb(m,a,b,r,mat=0):m.limb(a,b,r,r*.82,mat,step=.35)

def legs(m,species,phase,body,kind,scale=1.):
    walking=kind in ('walk','run');run=kind=='run';p=phase*math.tau
    for side in (-1,1):
        for front in (False,True):
            x=side*(2.9 if species=='deer' else (3.2 if species=='badger' else 2.15))*scale
            z=(5.6 if front else -5.6)*scale
            # Four-beat walk; faster diagonal trot/bound. Stance sweeps the planted hoof
            # backwards, swing lifts it forwards instead of paddling both ends together.
            offset=(0 if (side==1)==front else math.pi) if run else ((0 if front else math.pi*.5)+(math.pi if side<0 else 0))
            cycle=(phase+offset/math.tau)%1.
            stance=.52 if run else .64
            contact=cycle/stance if cycle<stance else (cycle-stance)/(1-stance)
            reach=(3.8 if run else 2.3)*scale
            swing=(reach*(1-2*contact) if cycle<stance else -reach*math.cos(contact*math.pi)) if walking else 0.
            lift=(math.sin(contact*math.pi)*(3.1 if run else 1.8)*scale if walking and cycle>=stance else 0.)
            if kind=='sleep':
                m.ell((x*.85,1.6,z*.8),(1.3,1.1,2.),0);continue
            h=(14. if species=='deer' else (4.2 if species=='badger' else 6.2))*scale
            root=np.array([x,body,z]);knee=np.array([x,body-h*.52,z+swing*.45+(-.8 if front else 1.4)])
            foot=np.array([x,1.+lift,z+swing])
            if species=='badger' and kind=='special' and front:foot[1]+=max(0,math.sin(p+side))*2.;foot[2]+=math.sin(p+side)*2.
            # Subpixel rods vanished after majority downsampling. Keep a continuous
            # readable shin even on the smaller fawn, while retaining a slender build.
            r=max(.86,(1.05 if species=='deer' else (1.15 if species=='badger' else 1.))*scale)
            limb(m,root,knee,r,2 if species=='badger' else 0);limb(m,knee,foot,r*.77,2 if species in ('fox','badger') else 0)
            m.ell(foot,(r*1.12,.8*scale,1.3*scale),2)

def deer_legs(m, t, by, kind, s):
    """Four independent planted/swinging hooves, with a flexing hock on each leg."""
    moving=kind in ('walk','run'); running=kind=='run'
    for side in (-1,1):
        for front in (False,True):
            x=side*2.65*s; z=(5.0 if front else -5.8)*s
            if kind=='sleep':
                m.ell((x*.85,1.4*s,z*.8),(1.25*s,1.0*s,2.0*s),0)
                continue
            # A walk has four beats; the faster gait uses diagonal pairs.
            offset=(0.0 if (side==1)==front else .5) if running else ((0.0 if front else .25)+(0.5 if side<0 else 0.0))
            cycle=(t+offset)%1.0; stance=.55 if running else .65
            c=cycle/stance if cycle<stance else (cycle-stance)/(1.0-stance)
            reach=(4.3 if running else 2.4)*s
            swing=(reach*(1.0-2.0*c) if cycle<stance else -reach*math.cos(c*math.pi)) if moving else 0.0
            lift=(math.sin(c*math.pi)*(2.9 if running else 1.4)*s if moving and cycle>=stance else 0.0)
            root=np.array([x,by-.8*s,z]); foot=np.array([x,.9*s+lift,z+swing])
            knee=np.array([x,by*.52+lift*.30,z+swing*.38+(-.7 if front else 1.35)*s])
            r=max(.88,1.12*s)
            m.limb(root,knee,r*1.35,r,0,step=.45)
            m.limb(knee,foot,r,r*.72,0,step=.4)
            m.ell(foot,(r*.92,.72*s,1.12*s),2)

def deer(v,kind,t):
    m=art.Model(); fawn=v==2; s=.70 if fawn else 1.; p=t*math.tau; b=math.sin(p)
    by=16.2*s
    if kind=='sleep': by=7.0*s
    elif kind=='run': by+=(.6+.6*math.cos(p*2))*s
    elif kind=='walk': by+=.22*math.cos(p*2)*s
    else: by+=.13*b*s

    # The rump, shoulder and belly overlap to form a soft, tapered silhouette.
    m.ell((0,by,-3.5*s),(4.25*s,4.8*s,5.8*s),0)
    m.ell((0,by-.25*s,2.5*s),(3.75*s,4.35*s,5.4*s),0)
    m.ell((0,by-2.2*s,1.0*s),(3.0*s,2.0*s,5.7*s),1)
    m.ell((0,by-.4*s,-8.6*s),(2.6*s,2.5*s,.85*s),1)
    m.ell((0,by+1.2*s,-9.0*s),(.85*s,1.15*s,.8*s),0)

    # The six forage frames lower the whole head, graze, and rise again.
    # Keeping the first and last poses near standing also softens mood changes.
    graze=[0.0,.45,.90,1.0,.90,.45][int(t*6)%6] if kind=='forage' else 0.0
    groom=[0.0,.45,.8,.45][int(t*4)%4] if kind=='groom' else 0.0
    hy=(28.0-18.0*graze-5.0*groom)*s
    hz=(10.0+4.0*graze-2.0*groom)*s
    if kind=='sleep': hy=16.0*s; hz=7.0*s
    if kind in ('walk','run'): hy+=(by-16.2*s)*.7
    if kind in ('idle','alert'): hy+=.18*b*s
    head=np.array([0.,hy,hz])
    pitch=.12+graze*.88+groom*.28
    yaw=groom*.48
    rot=art.rot_y(yaw) @ art.rot_x(pitch)
    def hp(x,y,z): return head+rot @ (np.array([x,y,z])*s)
    def head_ell(pos,r,mat,R=None):
        m.ell(hp(*pos),tuple(a*s for a in r),mat,R=rot if R is None else rot @ R)

    # Taper the neck into the head instead of a vertical, uniform tube.
    base=np.array([0.,by+1.0*s,4.4*s]); throat=hp(0,-1.6,-1.9)
    m.limb(base,base*.48+throat*.52,2.8*s,2.25*s,0,step=.5)
    m.limb(base*.48+throat*.52,throat,2.25*s,1.55*s,0,step=.5)
    head_ell((0,0,0),(2.2,2.5,3.0),0)
    head_ell((0,-.85,2.35),(1.45,1.1,1.8),0)
    head_ell((0,-1.3,3.35),(1.12,.65,.75),1)
    head_ell((0,-.92,3.9),(.75,.55,.55),3)
    for side in (-1,1):
        angle=side*(.65+.08*math.sin(p+side))
        ear=np.array([[math.cos(angle),-math.sin(angle),0],[math.sin(angle),math.cos(angle),0],[0,0,1]])
        head_ell((side*2.2,2.7,-.8),(1.05,2.9,.65),0,ear)
        head_ell((side*2.2,2.7,-.25),(.52,2.0,.23),5,ear)
        head_ell((side*1.9,.35,1.0),(.42,.15 if kind=='sleep' else .48,.45),3)
        if v==1:
            a=hp(side*1.15,2.0,-.8); top=hp(side*2.0,8.2,-1.5)
            m.limb(a,top,.68,.50,2,step=.4)
            m.limb(a*.43+top*.57,hp(side*3.6,6.4,-.9),.50,.38,2,step=.4)
            m.limb(a*.25+top*.75,hp(side*1.3,7.9,1.0),.46,.36,2,step=.4)
    deer_legs(m,t,by,kind,s)
    if fawn:
        for side in (-1,1):
            for z in (-5.,-2.,1.,4.):
                m.ell((side*3.15*s,by+1.25*s,z*s),(.58*s,.5*s,.62*s),1)
    return m

def badger(v,kind,t):
    m=art.Model();b=math.sin(t*math.tau);by=8.;hy=8.;hz=8.8
    if kind=='forage':hy=4.+abs(b)*.5;hz=10.
    if kind=='alert':hy=10.;hz=8.
    if kind=='groom':hy=7.;hz=5.7
    if kind=='sleep':by=4.7;hy=4.1;hz=6.
    if kind in ('idle','sleep'):by+=b*.16
    if kind in ('walk','run'):by+=math.cos(t*math.tau*2)*.2
    if kind=='special':by+=math.sin(t*math.tau*2)*.3;hy=4.;hz=10.
    # Heavy pear-shaped haunches, lower shoulders and a visible dark undercarriage.
    m.ell((0,by-2.,-.5),(4.3,2.4,6.6),2)
    m.ell((0,by,-3.),(5.1,4.3,6.),0)
    m.ell((0,by-.5,3.1),(4.25,3.75,4.8),0)
    m.limb((0,by-.5,-8),(0,by-1.2,-11.2),1.3,1.05,0,step=.4)
    # Silvery saddle follows the back in deliberate clumps, not random speckling.
    for side in (-1,1):
        for z in (-5.,-2.,1.):
            m.ell((side*2.6,by+2.8,z),(1.3,.62,2.1),0)
    m.ell((0,hy-1.2,hz-2.),(3.,2.4,2.7),2)
    m.ell((0,hy,hz),(3.,2.85,3.6),1)
    m.ell((0,hy-1.2,hz+2.9),(1.65,1.3,2.3),1)
    for side in (-1,1):
        # Broad black eye-to-ear bands leave a continuous cream forehead blaze.
        m.ell((side*2.4,hy+.6,hz-.1),(.95,1.85,3.),3)
        m.ell((side*1.4,hy-.5,hz+2.4),(.72,1.05,1.7),3)
        m.ell((side*2.35,hy+2.45,hz-2.1),(1.1,1.2,.85),1)
        m.ell((side*2.35,hy+2.5,hz-1.5),(.63,.72,.25),2)
        m.ell((side*2.95,hy+.4,hz+1.25),(.5,.18 if kind=='sleep' else .55,.5),3)
        if kind!='sleep':m.ell((side*3.05,hy+.6,hz+1.5),(.21,.2,.15),4)
    m.ell((0,hy-.8,hz+4.8),(.95,.65,.75),3)
    legs(m,'badger',t,by,kind)
    if kind=='special':
        for side in (-1,1):
            reach=math.sin(t*math.tau+side)*2.
            for dx in (-.4,.4):
                m.ell((side*3.2+dx,1.2+max(0,math.sin(t*math.tau+side))*2.,7.+reach),(.3,.3,.9),1)
    return m

def fox(v,kind,t):
    m=art.Model();b=math.sin(t*math.tau);by=9.;hy=15.;hz=7.3
    if kind=='forage':hy=7.;hz=9.4
    if kind=='alert':hy=16.;hz=7.
    if kind=='groom':hy=11.;hz=2.4
    if kind=='sleep':by=4.4;hy=5.3;hz=3.
    if kind=='special':by-=math.cos(t*math.pi)*1.2;hy=12.+b*1.4
    if kind=='idle':by+=b*.16;hy+=b*.2
    m.ell((0,by,-1),(3.2,3.8,6.6),0)
    m.ell((0,by-1.8,1.6),(2.5,2.,4.),1)
    # A separate full brush with a broad cream tip, not a pointed extension of the torso.
    # Root-to-tip lag follows the gait; the brush wraps visibly around a sleeping fox.
    tail=([(0,by+.1,-6),(5.,by-.2,-3),(5.7,by-.5,2),(3.9,by-.6,5.)] if kind=='sleep' else
          [(0,by+.1,-6),(1.+b*.7,by-.1,-9),(1.8+math.sin(t*math.tau-.6)*1.4,by+.1,-13.2),(2.1+math.sin(t*math.tau-1)*1.7,by+.6,-17.)])
    for i,(a,c) in enumerate(zip(tail,tail[1:])):
        m.limb(a,c,[1.6,2.8,3.1][i],[2.8,3.1,2.1][i],1 if i==2 else 0,step=.45)
    m.ell(tail[-1],(2.05,2.,2.2),1)
    # Shoulder ruff, cheek tufts and black-backed ears read at the game's actual scale.
    for side in (-1,1):
        m.ell((side*2.4,hy-2.8,5.7),(1.35,2.1,2.),1)
        m.ell((side*2.4,hy-.6,hz+.3),(1.,1.3,1.9),1)
        m.ell((side*2.9,hy-1.1,hz-.3),(.8,.7,1.2),0)
    m.ell((0,hy-2.,5.6),(2.,2.6,2.5),0)
    m.ell((0,hy,hz),(2.5,2.7,3.0),0)
    for side in (-1,1):
        m.ell((side*1.5,hy-.9,hz+1.5),(1.4,1.1,1.8),1)
        for j in range(3):m.ell((side*(1.7+j*.17),hy+2.3+j*1.05,hz-.5),(.95-j*.24,1.3-j*.26,.65-j*.12),0)
        m.ell((side*1.8,hy+3.,hz-.8),(.8,1.3,.35),2)
        m.ell((side*1.55,hy+3.,hz+.05),(.45,.9,.22),5)
        m.ell((side*1.8,hy+.4,hz+1.5),(.42,.16 if kind=='sleep' else .55,.4),3)
        if kind!='sleep':m.ell((side*1.9,hy+.6,hz+1.72),(.16,.16,.14),4)
    m.ell((0,hy-.8,hz+3.1),(1.2,.9,2.),0)
    m.ell((0,hy-.75,hz+4.8),(.6,.5,.5),3)
    legs(m,'fox',t,by,kind)
    return m

def hedgehog(v,kind,t):
    m=art.Model();b=math.sin(t*math.tau);curl=min(1.,t*1.2) if kind=='special' else (1. if kind=='sleep' else 0.)
    walking=kind in ('walk','run');by=4.+(math.cos(t*math.tau*2)*.16 if walking else b*.1)
    # Warm face and a dark, domed spine coat; the curl shortens the body into a ball.
    m.ell((0,by-1.,.2),(3.2,2.4,4.3-curl),5)
    m.ell((0,by,-.7),(3.9+curl*.5,3.5+curl*.5,5.0-curl*.6),2)
    for z in (-3.5,-1.1,1.3,2.7):
        for angle in (-1.12,-.56,0.,.56,1.12):
            root=np.array([math.sin(angle)*3.3,by+math.cos(angle)*2.7,z])
            tip=root+np.array([math.sin(angle)*1.15,math.cos(angle)*1.45,-.65])
            m.limb(root,tip,.68,.3,0,step=.3)
            m.ell(tip,(.42,.5,.5),1)
    if curl<.96:
        hz=4.1-curl*3.;hy=3.3+(.6 if kind=='alert' else (-.6+abs(b)*.35 if kind=='forage' else 0))
        m.ell((0,hy,hz),(2.3*(1-curl*.45),2.0,2.5),5)
        m.ell((0,hy-.5,hz+2.),(1.25,.95,1.8),5)
        m.ell((0,hy-.4,hz+3.5),(.65,.55,.6),3)
        for side in (-1,1):
            blink=kind=='idle' and t>.7
            m.ell((side*1.9,hy+.3,hz+.8),(.48,.15 if blink else .55,.5),3)
            if not blink:m.ell((side*2.0,hy+.5,hz+1.),(.18,.18,.15),4)
            m.ell((side*1.85,hy+1.65,hz-.8),(.85,1.,.5),5)
            m.ell((side*1.85,hy+1.7,hz-.4),(.4,.6,.2),1)
            for z in (-2.7,2.2):
                leg_phase=t*math.tau+(0 if side>0 else math.pi)+(math.pi*.5 if z<0 else 0)
                swing=math.sin(leg_phase)*1.0 if walking else 0.
                lift=max(0.,math.cos(leg_phase))*.6 if walking else 0.
                m.ell((side*2.65,.85+lift,z+swing),(.7,.7,1.0),5)
    return m

BUILDERS={'deer':deer,'badger':badger,'fox':fox,'hedgehog':hedgehog}

def frame(species,v,d,col):
    kind,start,n=next(x for x in BLOCKS if x[1]<=col<x[1]+x[2]);materials(species,v)
    m=BUILDERS[species](v,kind,(col-start)/n)
    depth,code=art.render(m.transform(math.pi/2-d*math.pi/4,0))
    return np.array([[CLEAR if c[3]<255 else c for c in row] for row in art.to_pixels(depth,code)],np.uint8)

def main():
    picks=[(0,0),(1,0),(2,0),(4,0),(6,0),(0,6),(0,12),(0,19),(0,25),(0,31),(0,35),(0,43)]
    only='--preview-only' in sys.argv;preview=np.zeros((12*H,len(picks)*W,4),np.uint8)
    selected=set(next((a.split('=',1)[1] for a in sys.argv if a.startswith('--species=')),','.join(BUILDERS)).split(','))
    for si,species in enumerate(BUILDERS):
        sheet=None if only or species not in selected else np.zeros((24*H,COLS*W,4),np.uint8)
        for v in range(3):
            for d in range(8):
                for col in range(COLS):
                    if sheet is None and (d,col) not in picks:continue
                    px=frame(species,v,d,col)
                    if sheet is not None:
                        y=(v*8+d)*H;x=col*W;sheet[y:y+H,x:x+W]=px
                    if(d,col) in picks:
                        x=picks.index((d,col))*W;y=(si*3+v)*H;preview[y:y+H,x:x+W]=px
            print(species,v+1,'/3',flush=True)
        if sheet is not None:save_png(ROOT/f'assets/wildlife/{species}.png',sheet)
    save_png(ROOT/'docs/img/woodland_animals.png',preview)
    from art_badger_den import build as den_art
    save_png(ROOT/'assets/wildlife/badger_den.png',den_art())
if __name__=='__main__':main()
