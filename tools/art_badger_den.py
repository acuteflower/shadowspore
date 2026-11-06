#!/usr/bin/env python3
"""Small rooted earthen badger sett, same 40x24 footprint/pivot as the original."""
from pathlib import Path
import numpy as np
from gen_art import hexc
from world_data import save_png

def build():
    a=np.zeros((24,40,4),np.uint8)
    def oval(cx,cy,rx,ry,color):
        for y in range(max(0,int(cy-ry)),min(24,int(cy+ry)+1)):
            for x in range(max(0,int(cx-rx)),min(40,int(cx+rx)+1)):
                if ((x-cx)/rx)**2+((y-cy)/ry)**2<=1:a[y,x]=hexc(color)
    for x,y,rx,ry in [(11,15,10,5),(25,14,12,6),(20,11,12,6)]:oval(x,y,rx,ry,'39353d')
    oval(19,12,15,6,'675347');oval(19,11,12,4,'806852')
    for x,y in [(7,13),(11,9),(16,7),(24,8),(30,11),(33,15)]:
        oval(x,y,3,2,'96816a');oval(x,y+1,3,1,'675347')
    oval(20,14,11,5,'493b37');oval(20,15,9,4,'27232d');oval(20,16,7,3,'181824')
    # Crooked exposed roots arch around the mouth rather than crossing the hole.
    for x,y in [(10,14),(11,12),(12,10),(14,9),(17,8),(20,8),(23,9),(26,10),(28,12),(30,14)]:
        oval(x,y,1.4,1.1,'b09876')
    for x,y in [(4,18),(8,19),(31,18),(35,18),(12,21),(28,21)]:
        oval(x,y,3,1,'415743')
        for dx,h in [(-1,3),(0,4),(1,2)]:
            for k in range(h):
                if 0<=y-k<24:a[y-k,x+dx]=hexc('6c8758' if dx==0 else '4d6d4c')
    for x,y in [(6,16),(9,20),(30,20),(34,15)]:oval(x,y,2,1,'776c68')
    return a

if __name__=='__main__':save_png(Path(__file__).resolve().parent.parent/'assets/wildlife/badger_den.png',build())
