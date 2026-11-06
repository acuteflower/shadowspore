from pathlib import Path
from collections import deque
import numpy as np,json
from PIL import Image
r=Path(__file__).resolve().parents[1];d=json.loads((r/'data/rivers_baked.json').read_text());rel=np.array(Image.open(r/'assets/world/relief.png').convert('RGBA'));block=np.array(Image.open(r/'assets/world/relief_block.png').convert('L'));n=1100
base=(rel[:,:,3]>0)&~(block.reshape(n,4,n,4).max(axis=(1,3))>0)
water=np.zeros_like(base)
for key,v in d['chunks'].items():
 cx,cy=map(int,key.split(','));a=np.array(Image.open(r/v['field'].replace('res://','')))
 # tile-center passability; width of the generated fords leaves room for a body.
 q=a[8::16,8::16];water[cy*32:cy*32+32,cx*32:cx*32+32]=(q[:,:,0]>128)&(q[:,:,1]>163)
def comps(mask):
 seen=np.zeros_like(mask);sizes=[]
 for y,x in zip(*np.where(mask)):
  if seen[y,x]:continue
  todo=deque([(y,x)]);seen[y,x]=1;size=0
  while todo:
   yy,xx=todo.popleft();size+=1
   for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
    a,b=yy+dy,xx+dx
    if 0<=a<n and 0<=b<n and mask[a,b] and not seen[a,b]:seen[a,b]=1;todo.append((a,b))
  sizes.append(size)
 return sorted((s for s in sizes if s>=20),reverse=True)
before=comps(base);after=comps(base&~water)
print('significant walkable components before/after',before,after)
assert len(before)==len(after),'River creates new isolated land areas'
