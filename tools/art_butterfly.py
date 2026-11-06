#!/usr/bin/env python3
"""Four subtle butterfly palettes, eight true facings and eight wing poses; numpy renderer.
16x16 feet (8,11), columns = flap, rows = palette*8 + direction. No emission.
"""
import math
from pathlib import Path
import numpy as np
import art_hero3d as art
from gen_art import CLEAR,hexc
from world_data import save_png
ROOT=Path(__file__).resolve().parent.parent
art.FW=art.FH=16;art.GROUND_ROW=11.;art.SS=4;art.SCALE=1.
# Show the wing silhouette at this tiny scale without making an oversized insect.
art.PITCH=math.radians(48);art.COSP,art.SINP=math.cos(art.PITCH),math.sin(art.PITCH)
art.UHAT=np.array([0.,art.COSP,-art.SINP]);art.WHAT=np.array([0.,art.SINP,art.COSP])
art.DECAL_WEIGHT={2:1.4};art.ink_color=lambda mat:hexc('383244')
RAMPS=[['785d45','b38d57','ddbc7a','f2deaf'],['8d8392','b9afbc','dfd9d9','f6f0df'],['554c7a','8172a0','ad9fc5','d6cce2'],['375e60','588c85','8eb5a0','c7d8b3']]
a=np.zeros((32*16,8*16,4),np.uint8)
for v in range(4):
 art.RAMPS=[[hexc(c) for c in r] for r in [RAMPS[v],['413848','635568','89778e','b3a3b9'],['ddd0b6','e8dcc3','f0e5d2','faf0dc'],['24232f']*4]]
 for d in range(8):
  for col in range(8):
   m=art.Model()
   # Seven periodic flying poses plus one genuinely upright, folded resting pose.
   angle=.08+1.38*(.5-.5*math.cos(col/7.*math.tau)) if col<7 else 1.48
   for side in (-1,1):
    # All markings rotate with the wing about its thorax hinge. Forewings are
    # larger and point forwards; rounded hindwings form a separate lower lobe.
    c,s=math.cos(angle),math.sin(angle)*side
    rot=np.array([[c,-s,0],[s,c,0],[0,0,1]])
    hinge=np.array([side*.2,1.8,0.])
    def wing(center,radii,mat):m.ell(hinge+rot@np.array(center),radii,mat,R=rot)
    wing((side*2.35,0,1.15),(2.65,.28,3.05),1)
    wing((side*1.8,-.03,-2.05),(1.95,.27,1.95),1)
    wing((side*2.25,.24,1.25),(2.12,.16,2.4),0)
    wing((side*1.75,.22,-2.05),(1.4,.16,1.4),0)
    wing((side*3.15,.4,1.1),(.68,.1,.85),1)
    wing((side*3.2,.5,1.15),(.32,.08,.4),2)
    wing((side*2.1,.39,-2.4),(.46,.1,.38),2)
    wing((side*1.05,.4,.1),(.18,.1,1.85),1)
    wing((side*3.6,.4,2.7),(.25,.1,.3),2)
   m.ell((0,1.9,-.2),(.38,.4,2.2),3)
   m.ell((0,2.,2.1),(.48,.5,.6),3)
   for side in (-1,1):
    m.limb((side*.2,2.1,2.3),(side*1.2,2.4,3.8),.22,.2,3,step=.2)
   dep,cod=art.render(m.transform(math.pi/2-d*math.pi/4,0));px=art.to_pixels(dep,cod)
   px=np.array([[CLEAR if c[3]<255 else c for c in row]for row in px],np.uint8)
   y=(v*8+d)*16;x=col*16;a[y:y+16,x:x+16]=px
save_png(ROOT/'assets/wildlife/butterfly.png',a)
preview=np.concatenate([a[v*128+d*16:v*128+d*16+16] for v in range(4) for d in (0,1,2)],axis=0)
save_png(ROOT/'docs/img/butterflies.png',preview)
print('Butterflies: 256 frames')
