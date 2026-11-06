#!/usr/bin/env python3
"""Ravens/carrion crows in the existing miniature 3D pixel-art pipeline (numpy).
48x48, feet (24,35); 50 columns; 6 builds x 8 real facings. No emissive parts.
Idle 0:4, peck 4:10, walk 10:16, preen 16:22, watch 22:26, call 26:30,
flight 30:38, landing 38:44, takeoff 44:50. python3 tools/art_corvid.py
"""
import math
from pathlib import Path
import numpy as np
import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png
ROOT = Path(__file__).resolve().parent.parent
W=H=48
COLS=50
art.FW,art.FH,art.GROUND_ROW,art.SS,art.SCALE=W,H,35.,3,1.
art.DECAL_WEIGHT={3:3.,4:2.5}
art.ink_color=lambda mat: hexc('10141e')
RAMPS=[['11121e','242b3a','3c4858','626e7a'],['111322','242c41','3d5062','637b89'],['131421','2b2d40','4d4c65','777286']]

def material(v):
    art.RAMPS=[[hexc(c) for c in ramp] for ramp in [RAMPS[v%3],['11101b','252332','444051','6d6474'],
        ['131420','242632','40424c','616575'],['080c16']*4,['697d89','82939a','a1b0ae','bac6bb']]]

def build(v,kind,t):
    m=art.Model(); raven=v>=3; size=1.23 if raven else 1.
    by=5.6; hy=9.5; hz=3.2; bob=math.sin(t*math.tau)
    flying=kind in ('fly','takeoff','land')
    if kind=='peck':hy=3.5+abs(bob)*2.;hz=5.2;by=5.
    if kind=='preen':hy=7.+bob*.8;hz=.8
    if kind=='watch':hy=10.5;by=6.
    if kind=='call':hy=10.1;hz=3.3
    if kind=='walk':by+=abs(bob)*.3;hy+=abs(bob)*.4
    if flying:by=5.;hy=7.3;hz=4.3
    if kind=='takeoff':by-=max(0.,1-t*3)*1.5
    m.ell((0,by,0),(2.65*size,3.6*size,4.3*size),0)
    m.ell((0,hy*.8,2),(1.9*size,2.4*size,2.5*size),0)
    for s in (-1,1):
        if not flying:
            # Folded wings, overlap of long flight feathers makes a readable feather edge.
            m.ell((s*2.2*size,by+.1,-1.1),(1.05*size,2.1*size,4.*size),0, R=art.rot_x(-.15))
            for feather in range(3):
                m.ell((s*(2.15+feather*.16)*size,by-1.0+feather*.35,-3.-feather*.7),(0.55*size,.9,2.4*size),1)
        else:
            phase=t if kind=='fly' else (t*.9 if kind=='takeoff' else .3+t*.45)
            flap=math.sin(phase*math.tau)
            reach=(14.5 if raven else 12.0)*(1.-.17*abs(flap))
            rise=flap*(8.0 if raven else 6.5)
            if kind=='land':rise=3.+t*3.;reach*=.85
            shoulder=np.array([s*2.0*size,by+.8,1.])
            elbow=np.array([s*reach*.52,by+rise*.7,-.6])
            tip=np.array([s*reach,by+rise,-3.5])
            m.limb(shoulder,elbow,1.5*size,1.2*size,0,step=1.2)
            m.limb(elbow,tip,1.3*size,.4,0,step=1.2)
            for feather in range(6):
                f=feather/5.;pos=elbow*(1-f)+tip*f
                end=pos+np.array([s*(.5+f*2.4),-.7,-(5.5-f*1.4)*size])
                m.limb(pos,end,.75*size,.2,1 if feather%2 else 0,step=1.2)
    # Fan tail on crows; distinctly longer central feathers / wedge on ravens.
    for feather in range(-2,3):
        length=(6.8-abs(feather)*.95) if raven else 4.8
        m.ell((feather*.7,by-.7,-3.9-length*.5),(0.75, .45, length*.62),1,R=art.rot_y(-feather*.09))
    turn=.18*bob if kind in ('idle','watch') else (.8 if kind=='preen' else 0)
    m.ell((turn,hy,hz),(2.0*size,2.25*size,2.35*size),0)
    if raven:
        for s in (-1,0,1):m.ell((s*.7,hy-2.,hz+1),(0.6,1.35,.6),1,R=art.rot_x(-.45))
    bill=2.8 if raven else 2.0
    for i in range(3):
        m.ell((turn,hy-.35,hz+1.9+i*bill*.36),((.85-i*.22)*size,(.55-i*.13)*size,.9),2)
    if kind=='call':
        m.ell((turn,hy-1.15-abs(bob)*.7,hz+2.6),(.8,.25,1.4),2,R=art.rot_x(-abs(bob)*.3))
    for s in (-1,1):
        m.ell((s*1.65*size+turn,hy+.35,hz+1.1),(.5,.53,.55),3)
        if not(kind=='idle' and t>.7):m.ell((s*1.7*size+turn,hy+.55,hz+1.5),(.18,.18,.18),4)
        # Small scaly toes, tucked during cruising, extended for landing.
        ly=1.6 if not flying else 3.8
        lz=1.+s*bob*1.2 if kind=='walk' else .8
        if kind=='land':ly=1.2
        m.limb((s*1.25,by-1.8,lz),(s*1.4,ly,lz),.35,.27,2,step=.8)
        for toe in (-1,0,1):m.limb((s*1.4,ly,lz),(s*1.4+toe*.55,ly-.4,lz+1.2),.23,.12,2,step=.8)
    return m


def render(v,d,col):
    blocks=[('idle',0,4),('peck',4,6),('walk',10,6),('preen',16,6),('watch',22,4),('call',26,4),('fly',30,8),('land',38,6),('takeoff',44,6)]
    kind,start,n=next(b for b in blocks if b[1]<=col<b[1]+b[2]);t=(col-start)/n
    material(v); model=build(v,kind,t)
    depth,code=art.render(model.transform(math.pi/2-d*math.pi/4,0))
    return np.array([[CLEAR if c[3]<255 else c for c in row] for row in art.to_pixels(depth,code)],dtype=np.uint8)


def main():
    sheet=np.zeros((6*8*H,COLS*W,4),np.uint8)
    picks=[(0,0),(1,0),(2,0),(4,0),(6,0),(0,6),(0,12),(0,18),(0,23),(0,27),(0,31),(0,33),(0,35),(0,40)]
    preview=np.zeros((6*H,len(picks)*W,4),np.uint8)
    for v in range(6):
        for d in range(8):
            for col in range(COLS):
                px=render(v,d,col);y=(v*8+d)*H;x=col*W;sheet[y:y+H,x:x+W]=px
                if(d,col) in picks:
                    x=picks.index((d,col))*W;preview[v*H:(v+1)*H,x:x+W]=px
        print('Corvid build',v+1,'/ 6',flush=True)
    save_png(ROOT/'assets/wildlife/corvid.png',sheet)
    save_png(ROOT/'docs/img/corvids.png',preview)
if __name__=='__main__':main()
