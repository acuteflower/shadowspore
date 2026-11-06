#!/usr/bin/env python3
"""Brown bears: 80px frames, feet (40,68), three builds x eight facings.
Main: idle4, forage6, walk8, alert4, run8, groom4, sleep4, rear6.
Attack: eight continuous windup, swipe and recovery frames.
"""
import math
from pathlib import Path
import numpy as np
import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png

ROOT=Path(__file__).resolve().parent.parent
W=H=80
art.FW=art.FH=80
art.GROUND_ROW=68.
art.SS=3
art.SCALE=1.
art.ink_color=lambda mat: hexc('302631')
BLOCKS=[('idle',0,4),('forage',4,6),('walk',10,8),('alert',18,4),('run',22,8),('groom',30,4),('sleep',34,4),('special',38,6)]

def materials(v):
    coats=[['48343b','725046','9d735b','c6a080'],['40323d','654c49','8c6b5a','b89a7f'],['554047','896457','b58a6c','d3ad88']]
    art.RAMPS=[[hexc(c) for c in ramp] for ramp in [coats[v],['604848','967161','c09a79','dfc0a0'],['302b34','493b3e','69514c','8a7062'],['211e28']*4,['94877e','b8a99a','d9cbb6','eee3cf']]]

def bear(v,kind,t):
    m=art.Model(); s=.55 if v==2 else (1.0 if v==0 else .94); p=t*math.tau
    # Rear smoothly rises and holds; attack raises one forepaw across the body.
    rear=([0,.18,.42,.7,.94,1][min(5,int(t*6))] if kind=='special' else 0.)
    sleep=kind=='sleep'; by=(9 if sleep else 17)+(.18*math.sin(p) if kind in ('idle','sleep') else 0)
    by+=rear*2
    def q(x,y,z): return (x*s,y*s,z*s)
    def ell(pos,r,mat=0): m.ell(q(*pos),tuple(x*s for x in r),mat)
    def limb(a,b,r1,r2,mat=0): m.limb(q(*a),q(*b),r1*s,r2*s,mat,step=.5)
    # Heavy barrel, substantial shoulder hump and short tail.
    # The barrel rises from planted rump into a high chest. Interpolating
    # centres and radii keeps every transition pose physically connected.
    def mix(a,b): return a+(b-a)*rear
    ell((0,mix(by,16),mix(-4,-5)),(9,mix(9,10),mix(12,8)))
    ell((0,mix(by+1,29),mix(4,-3)),(9.5,mix(10.5,12),mix(10,7.5)))
    ell((0,mix(by+7,37),mix(4,-2)),(7.8,7,mix(6.8,6)))
    ell((0,mix(by-3,21),mix(0,0)),(8,mix(5,9),mix(11,6)),2)
    ell((0,mix(by+1,15),mix(-15,-12)),(2,2,1.8))
    moving=kind in ('walk','run')
    for side in (-1,1):
        for front in (False,True):
            x=side*6; z=8 if front else -10
            phase=(t+(0 if front else .25)+(0 if side>0 else .5))%1
            swing=(3.6 if kind=='run' else 2.1)*math.cos(phase*math.tau) if moving else 0
            lift=(2.7 if kind=='run' else 1.5)*max(0,math.sin(phase*math.tau)) if moving else 0
            if sleep:
                ell((x*.85,2,z*.8),(3,2,4),2); continue
            root=(x,mix(by-2,34 if front else 13),mix(z,-2 if front else -7)); foot=(x,2+lift,mix(z+swing,-8 if not front else z+swing))
            if front and rear:
                foot=(x,2+(29-2)*rear,8+(5-8)*rear)
            if front and kind in ('groom','play') and side==1:
                foot=(x,4+5*max(0,math.sin(p)),10+3*math.sin(p))
            if front and kind=='attack' and side==1:
                # Eight poses: pull back, lift, drive across, return.
                k=min(7,int(t*8)); xs=[6,7,8,5,0,-4,-1,4][k]; ys=[2,5,11,14,11,7,4,2][k]; zs=[8,6,5,15,17,14,12,9][k]
                foot=(xs,ys,zs)
            knee=(x,mix(by*.48+lift*.35,25 if front else 7),mix(z+swing*.4,1 if front else -10))
            limb(root,knee,3.7,3.1); limb(knee,foot,3.1,2.7)
            ell(foot,(3.3,2.2,4),2)
            for dx in (-1.7,0,1.7): ell((foot[0]+dx,foot[1]-.6,foot[2]+3.4),(.48,.5,1.2),4)
    # Forward muzzle stays low when alert; forage lowers to the earth.
    graze=[0,.45,.85,1,.8,.4][min(5,int(t*6))] if kind=='forage' else 0
    hy=(17 if sleep else 21)-graze*9+rear*24; hz=14+graze*3-rear*13
    if kind=='alert': hy=20
    if kind=='groom': hy-=2
    if rear: ell((0,mix(by+6,39),mix(8,0)),(6.5,6.5,6.5))
    ell((0,hy,hz-3),(6.8,6.8,7)); ell((0,hy,hz),(6.2,6,6.2))
    ell((0,hy-2,hz+5),(4,3,4),1); ell((0,hy-1.5,hz+8),(2.1,1.4,1.5),3)
    for side in (-1,1):
        ell((side*4.8,hy+5,hz-2),(2.3,2.5,1.8)); ell((side*4.8,hy+5,hz-.6),(1.1,1.3,.5),1)
        ell((side*4.4,hy+1,hz+4),(.65,.25 if sleep else .7,.65),3)
        if not sleep: ell((side*4.55,hy+1.2,hz+4.5),(.22,.22,.2),4)
    if kind=='play':
        # Roll about the spine and settle each pose on the ground. Adults rub
        # comfortably from side to side; the cub tumbles onto its back.
        k=min(5,int(t*6))
        angle=([0,.42,1.25,2.45,1.25,.42] if v==2 else [0,.25,.60,.85,.60,.25])[k]
        c, sn=math.cos(angle),math.sin(angle)
        rotation=np.array([[c,-sn,0],[sn,c,0],[0,0,1]])
        pivot=np.array([0.,by*s,0.])
        for primitive in m.prims:
            primitive.c=pivot+rotation@(primitive.c-pivot)
            primitive.R=rotation@primitive.R
            primitive.rot=True
        low=min(float(p.c[1]-np.sqrt(((p.R[1,:]*p.r)**2).sum())) for p in m.prims)
        for primitive in m.prims:
            primitive.c[1]-=low
    return m

def frame(v,d,kind,t):
    materials(v); m=bear(v,kind,t)
    depth,code=art.render(m.transform(math.pi/2-d*math.pi/4,0))
    return np.array([[CLEAR if c[3]<255 else c for c in row] for row in art.to_pixels(depth,code)],np.uint8)

def main():
    main=np.zeros((24*H,44*W,4),np.uint8); attack=np.zeros((24*H,8*W,4),np.uint8)
    play=np.zeros((24*H,6*W,4),np.uint8)
    preview=np.zeros((9*H,12*W,4),np.uint8)
    picks=[(0,'idle',0),(1,'idle',0),(2,'idle',0),(4,'idle',0),(6,'idle',0),(0,'forage',.5),(0,'walk',.25),(0,'alert',0),(0,'run',.25),(0,'groom',.25),(0,'sleep',0),(0,'special',5/6)]
    for v in range(3):
        for d in range(8):
            for kind,start,n in BLOCKS:
                for i in range(n):
                    px=frame(v,d,kind,i/n); main[(v*8+d)*H:(v*8+d+1)*H,(start+i)*W:(start+i+1)*W]=px
                    for j,(pd,pk,pt) in enumerate(picks):
                        if d==pd and kind==pk and abs(i/n-pt)<.001: preview[v*3*H:(v*3+1)*H,j*W:(j+1)*W]=px
            for i in range(8):
                px=frame(v,d,'attack',i/8); attack[(v*8+d)*H:(v*8+d+1)*H,i*W:(i+1)*W]=px
                if d==0: preview[(v*3+1)*H:(v*3+2)*H,i*W:(i+1)*W]=px
            for i in range(6):
                px=frame(v,d,'play',i/6); play[(v*8+d)*H:(v*8+d+1)*H,i*W:(i+1)*W]=px
                if d==0: preview[(v*3+2)*H:(v*3+3)*H,i*W:(i+1)*W]=px
        print('bear build',v+1,flush=True)
    save_png(ROOT/'assets/wildlife/bear.png',main)
    save_png(ROOT/'assets/wildlife/bear_attack.png',attack)
    save_png(ROOT/'assets/wildlife/bear_play.png',play)
    save_png(Path('/private/tmp/voidbloom-bear-art.png'),preview)
if __name__=='__main__': main()
