"""Whole-network hydrology / raster safety checks. No game saves or world edits."""
import json,math
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
d=json.loads((ROOT/'data/rivers_baked.json').read_text());cfg=json.loads((ROOT/'data/rivers.json').read_text())
parent={tuple(e['a']):tuple(e['b']) for e in d['edges']};out={tuple(e['a']):e for e in d['edges']};roots={tuple(b['outlet']):b for b in d['basins']}
checks=0
for e in d['edges']:
 assert e['head_a']>e['head_b'];assert 0<e['ra']<=e['rb']<=cfg['max_radius'];checks+=2
 p=tuple(e['a']);seen=set()
 while p in parent:
  assert p not in seen;seen.add(p);p=parent[p]
 assert p in roots;checks+=1
incoming={}
for e in d['edges']:incoming.setdefault(tuple(e['b']),[]).append(e)
confluences=0
for p,es in incoming.items():
 if len(es)>1:
  confluences+=1;flow=out[p]['flow'] if p in out else roots[p]['discharge']
  assert math.isclose(sum(e['flow'] for e in es),flow,rel_tol=1e-9);checks+=1
assert confluences>0
relief=np.array(Image.open(ROOT/'assets/world/relief.png').convert('RGBA'));sdf=np.array(Image.open(ROOT/'assets/world/land_sdf.png').convert('L'))
wet_count=0;blocked_count=0
for key,record in d['chunks'].items():
 cx,cy=map(int,key.split(','));field=np.array(Image.open(ROOT/record['field'].replace('res://','')));wet=field[:,:,0]>128;yy,xx=np.where(wet);tx=(xx+cx*512)//16;ty=(yy+cy*512)//16
 is_floor=(relief[ty,tx,1]&15)==0
 is_wf=np.zeros_like(is_floor)
 for wf in d.get('waterfalls',[]):
  wtx,wty=int(wf[0])//16,int(wf[1])//16
  is_wf|=(np.abs(tx-wtx)<=2)&(ty>=wty-1)&(ty<=wty+3)
 is_spring=np.zeros_like(is_floor)
 for cs in d.get('cliff_springs',[]):
  stx,sty=int(cs[0])//16,int(cs[1])//16
  is_spring|=(np.abs(tx-stx)<=2)&(np.abs(ty-sty)<=2)
 is_void_mouth = sdf[ty, tx] < 128
 assert np.all((relief[ty, tx, 3] > 0) | is_void_mouth) and np.all(is_floor | is_wf | is_spring | is_void_mouth), 'Water painted across invalid cliff/connector'
 assert np.all(sdf[ty,tx]>=110),'Water intrudes on void'
 assert field.shape==(512,512,4);checks+=3;wet_count+=wet.sum()
 nav=np.array(Image.open(ROOT/record['query'].replace('res://','')));blocked_count+=((nav[:,:,0]<=128)&(nav[:,:,1]>cfg['deep_threshold']*255)).sum()
for record in d['chunks'].values():
 nav=np.array(Image.open(ROOT/record['query'].replace('res://','')))
 expected=(nav[:,:,0]<=128)&(nav[:,:,1]>cfg['deep_threshold']*255)
 actual=np.zeros((128,128),dtype=np.uint8)
 for x,y,w,h in record['blocks']:actual[y//4:(y+h)//4,x//4:(x+w)//4]+=1
 assert np.array_equal(actual,expected.astype('uint8')),'Serialized collision mismatch'
 checks+=1
# Finite differences at graph joins catch the former near-right-angle seams.
starts={};ends={}
for segment in d['segments']:
 a,b=np.array(segment['a']),np.array(segment['b']);direction=(b-a)/np.linalg.norm(b-a)
 starts.setdefault(tuple(a),[]).append(direction);ends.setdefault(tuple(b),[]).append(direction)
for point,ds in ends.items():
 for a in ds:
  for b in starts.get(point,[]):
   assert np.dot(a,b)>math.cos(math.radians(40)),'Hard direction seam in river curve'
   checks+=1
assert wet_count>100000 and blocked_count>0 and len(d['fords'])>0
assert len(d.get('waterfalls',[]))>0,'No waterfalls baked'
assert len(d.get('cliff_springs',[]))>0,'No cliff springs baked'
checks+=2
print(f'River bake: {checks} checks passed; {confluences} confluences; {wet_count} water pixels; {len(d["waterfalls"])} waterfalls; {len(d["cliff_springs"])} cliff springs; {len(d["fords"])} crossing bands; raster stays on safe floors')
