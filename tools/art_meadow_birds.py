#!/usr/bin/env python3
"""Barn owl / hoopoe in the established ellipsoid pixel renderer. No existing assets rewritten.
48x48 frames, feet (24,35), same 50-column action layout as corvids, 3 builds per species.
python3 tools/art_meadow_birds.py [--preview-only]
"""
import math
from pathlib import Path
import sys
import numpy as np
import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png
ROOT=Path(__file__).resolve().parent.parent
W=H=48; COLS=50
art.FW,art.FH,art.GROUND_ROW,art.SS,art.SCALE=W,H,35.,3,1.
art.DECAL_WEIGHT={3:3.2,4:3.,5:2.3}
art.ink_color=lambda mat:hexc('433940' if mat in (0,1) else '252331')
BLOCKS=[('idle',0,4),('listen',4,6),('walk',10,6),('preen',16,6),('watch',22,4),('call',26,4),('fly',30,8),('land',38,6),('takeoff',44,6)]


def materials(v):
    if v<3:
        back=[['675561','998078','c8ae8c','eddbb9'],['625a6b','928897','c3b8b1','e7dfcd'],['795d60','ad8b76','d3b697','f1dfbb']][v]
        ramps=[back,['aaa0a0','d0c4b4','eee5cf','fff5de'],['70616c','9d8b83','c3ae96','e3cdb0'],['171522']*4,['7b776e','a59c85','c8bda0','ded4b7'],['6a5b67','8b7880','b49b92','d0b6a1']]
    else:
        back=[['70505a','a7755d','cea171','ead1a3'],['725264','a27c72','d0a88a','ecd6b3'],['6c494e','a76e4f','d49a69','efd0a0']][v-3]
        ramps=[back,['aaa19e','d3c7b7','efe1c9','fff2d8'],['1e2030','353447','4f4b5c','777080'],['171522']*4,['a59f91','cac3ac','e8dfc7','fff0d2'],['403341','66505a','8b6870','b08586']]
    art.RAMPS=[[hexc(c) for c in ramp] for ramp in ramps]


def feather(m,start,end,r,mat):m.limb(start,end,r,.16,mat,step=1.2)


def owl(v,kind,t):
    m=art.Model();breath=math.sin(t*math.tau); flying=kind in ('fly','takeoff','land')
    by=6.7;hy=12.1;hz=1.0;tilt=0.0
    if kind=='idle':by+=breath*.18;hy+=breath*.16
    if kind=='listen':hy-=.4;tilt=math.sin(t*math.tau)*.16
    if kind=='preen':hy=9.5+breath*.5;hz=-.4;tilt=.22
    if flying:by=5.8;hy=8.6;hz=4.0
    if kind=='walk':by+=abs(breath)*.3;hy+=abs(breath)*.3
    m.ell((0,by,-.7),(3.6,5.6,4.4),0)
    m.ell((0,by+.2,1.9),(3.1,4.8,2.2),1)
    for side in (-1,1):
        if not flying:
            m.ell((side*3.,by-.6,-1.3),(1.2,4.7,3.1),0,R=art.rot_x(-.16))
            for j in range(3):m.ell((side*(3.1+j*.1),by-1.6,-3.1-j*.4),(.45,2.2,1.2),2)
        else:
            wave=math.sin(t*math.tau)
            reach=17.8-abs(wave)*2.5;rise=wave*7.
            if kind=='land':rise=3.2+t*2.;reach*=.91
            if kind=='takeoff':rise=math.sin(t*math.pi)*7.;reach*=.8+.2*t
            shoulder=np.array([side*2.5,by+1.,1.])
            elbow=np.array([side*reach*.52,by+rise*.55,-.5])
            tip=np.array([side*reach,by+rise,-2.6])
            m.limb(shoulder,elbow,2.,1.55,0,step=1.2);m.limb(elbow,tip,1.6,.55,0,step=1.2)
            for j in range(7):
                f=j/6;start=elbow*(1-f)+tip*f
                end=start+np.array([side*(1.2+f*1.3),-.4,-(6.1-1.4*f)])
                feather(m,start,end,.85,1 if j%3 else 0)
                # Discrete warm bars on pale flight feathers.
                mid=start*.45+end*.55;m.ell(mid,(.7,.32,.45),2)
    for j in range(-2,3):m.ell((j*.52,by-3.8,-4.2),(.6,.45,3.5),0)
    # Heart-shaped pale facial disc: two cheeks narrowing around a hooked central bill.
    turn=math.sin(t*math.tau)*.42 if kind in ('watch','listen') else 0.
    center=np.array([turn,hy,hz]);headrot=art.rot_x(tilt)
    m.ell(center,(3.75,4.0,3.),0,R=headrot)
    for side in (-1,1):
        cheek=center+np.array([side*1.35,.1,2.05]);m.ell(cheek,(2.05,2.7,1.25),1,R=headrot)
        m.ell(center+np.array([side*.65,-2.2,2.1]),(1.15,1.8,1.),1)
        closed=kind=='idle';eyeheight=.15 if closed else .94
        m.ell(center+np.array([side*1.45,.45,3.]),(.76,eyeheight,.38),3)
        if not closed:m.ell(center+np.array([side*1.48,.75,3.26]),(.19,.19,.15),4)
        # Feathered shins and small muted talons.
        footy=1.0 if not flying or kind=='land' else 4.
        step=side*breath if kind=='walk' else 0.
        m.ell((side*1.55,3.2,1.2+step),(.85,2.0,.85),1)
        for toe in (-1,0,1):feather(m,(side*1.55,footy,1.4+step),(side*1.55+toe*.55,footy-.3,2.3+step),.22,2)
    m.ell(center+np.array([0,-.7,3.2]),(.48,.9,.6),2,R=art.rot_x(.28))
    for x,y in [(-1.5,6.7),(1.2,7.8),(-.6,5.2),(.6,8.9)]:m.ell((x,y,3.3),(.18,.28,.2),5)
    return m


def hoopoe(v,kind,t):
    m=art.Model();b=math.sin(t*math.tau);flying=kind in ('fly','takeoff','land')
    by=5.6;hy=9.;hz=3.;spread=0.0
    if kind=='idle':by+=b*.14;hy+=b*.2
    if kind=='listen':hy=4.+abs(b)*1.3;hz=5.1
    if kind=='walk':by+=abs(b)*.3;hy+=abs(b)*.4
    if kind=='preen':hy=7.2;hz=.4
    if kind=='watch':spread=[.3,.8,1.,.4][min(3,int(t*4))];hy+=.6
    if kind=='call':spread=.25;hy+=.3+b*.35
    if flying:hy=7.5;hz=4.2
    if kind=='takeoff':spread=(1-t)*.65
    m.ell((0,by,-.4),(2.6,3.45,4.3),0)
    m.ell((0,by-1.3,1.4),(2.3,2.1,2.8),1)
    for side in (-1,1):
        if not flying:
            m.ell((side*2.2,by-.1,-1.2),(1.1,2.5,3.7),2)
            for j in range(3):m.ell((side*2.7,by+.6-j*.8,-.8-j*.9),(.55,.38,1.8),1)
        else:
            wave=math.sin(t*math.tau);reach=13.8-abs(wave)*2.;rise=wave*7.5
            if kind=='land':rise=3.+t*2.
            shoulder=np.array([side*2,by+.7,.9]);elbow=np.array([side*reach*.5,by+rise*.7,-.4]);tip=np.array([side*reach,by+rise,-2.4])
            m.limb(shoulder,elbow,1.5,1.3,2,step=1.2);m.limb(elbow,tip,1.3,.4,2,step=1.2)
            for j in range(7):
                f=j/6;start=elbow*(1-f)+tip*f;end=start+np.array([side*.9,-.3,-(6.-1.5*f)])
                feather(m,start,end,.75,2)
                mid=start*.48+end*.52;m.ell(mid,(.8,.42,.9),1)
    for j in range(-2,3):
        m.ell((j*.5,by-1.8,-5.1),(.65,.45,3.2),2)
        m.ell((j*.5,by-1.7,-5.9),(.7,.48,.5),1)
    m.ell((0,hy,hz),(2.,2.15,2.05),0)
    for side in (-1,1):
        m.ell((side*1.6,hy+.4,hz+1.1),(.48,.14 if kind=='idle' and t>.7 else .54,.42),3)
        if not(kind=='idle' and t>.7):m.ell((side*1.64,hy+.58,hz+1.42),(.16,.16,.14),4)
        footy=1.0 if not flying or kind=='land' else 3.8
        z=1.+side*b*1.1 if kind=='walk' else 1.
        feather(m,(side*1.25,by-1.8,z),(side*1.35,footy,z),.3,5)
        for toe in (-1,0,1):feather(m,(side*1.35,footy,z),(side*1.35+toe*.5,footy-.3,z+1.2),.18,5)
    # Slender decurved bill, angled down while probing.
    for j in range(5):m.ell((0,hy-.2-j*j*.055,hz+1.9+j*.86),(.37-j*.045,.3-j*.035,.7),2)
    base=np.array([0,hy+1.5,hz-.3])
    for j in range(7):
        angle=-1.05+(j-3)*spread*.29
        length=4.1+(3-abs(j-3))*.48
        direction=np.array([0,math.cos(angle),math.sin(angle)])
        end=base+direction*length
        feather(m,base,end,.43,0)
        m.ell(end,(.5,.55,.5),2)
    return m


def frame(v,d,col):
    kind,start,n=next(x for x in BLOCKS if x[1]<=col<x[1]+x[2]);t=(col-start)/n
    materials(v);m=owl(v,kind,t) if v<3 else hoopoe(v,kind,t)
    depth,code=art.render(m.transform(math.pi/2-d*math.pi/4,0))
    return np.array([[CLEAR if c[3]<255 else c for c in row] for row in art.to_pixels(depth,code)],dtype=np.uint8)


def main():
    picks=[(0,0),(1,22),(2,22),(4,22),(6,22),(0,6),(0,12),(0,18),(0,23),(0,27),(0,31),(0,33),(0,35),(0,40)]
    only='--preview-only' in sys.argv
    sheet=None if only else np.zeros((6*8*H,COLS*W,4),np.uint8)
    preview=np.zeros((6*H,len(picks)*W,4),np.uint8)
    for v in range(6):
        for d in range(8):
            for col in range(COLS):
                if only and (d,col) not in picks:continue
                px=frame(v,d,col)
                if sheet is not None:
                    y=(v*8+d)*H;x=col*W;sheet[y:y+H,x:x+W]=px
                if(d,col) in picks:
                    x=picks.index((d,col))*W;preview[v*H:(v+1)*H,x:x+W]=px
        print('Meadow bird build',v+1,'/ 6',flush=True)
    if sheet is not None:save_png(ROOT/'assets/wildlife/meadow_birds.png',sheet)
    save_png(ROOT/'docs/img/meadow_birds.png',preview)
if __name__=='__main__':main()
