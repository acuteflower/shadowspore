"""Render QA: python3 tools/check_water_capture.py FRAME_FOLDER DAY.png NIGHT.png [NO_DISTURBANCES.png]."""
import sys,json
from pathlib import Path
import numpy as np
from PIL import Image
folder=Path(sys.argv[1])
files=sorted(p for p in folder.glob('*.png') if p.stem.isdigit())
frames=[np.array(Image.open(p).convert('RGB')) for p in files]
field=np.array(Image.open(folder/'field.png'))
bank=np.array(Image.open(folder/'banks.png'))
h,w=frames[0].shape[:2]
water=np.array(Image.fromarray((field[:,:,0]>128).astype('uint8')).resize((w,h),Image.Resampling.NEAREST)).astype(bool)
# Only the guaranteed opaque wet rim: narrower outer banks intentionally expose
# meadow pixels, whose separate wind/mist shader continues animating.
banks=np.array(Image.fromarray(((field[:,:,0]<128)&(bank[:,:,0]<26)).astype('uint8')).resize((w,h),Image.Resampling.NEAREST)).astype(bool)
layout=json.loads((Path(__file__).resolve().parent.parent/'data/water_design.json').read_text())['preview']
for x,y in layout['waterfalls']:
    banks[int(y*h/360):int((y+48)*h/360),int((x-24)*w/640):int((x+24)*w/640)]=False
changed=np.any(np.stack(frames)!=frames[0],axis=(0,3))
assert len(frames)>=16,'Insufficient animation samples'
assert changed[water].sum()>100,'Water is static'
assert changed[banks].sum()==0,'Dry bank flickers or drifts'
day=np.array(Image.open(sys.argv[2]).convert('RGB')).astype(float)
night=np.array(Image.open(sys.argv[3]).convert('RGB')).astype(float)
assert night[water].mean()<day[water].mean()*.65,'Water ignores night tint'
assert np.isfinite(day).all() and day[water].mean()>10,'Invalid render'
print(f'Render QA passed: {len(frames)} frames; {changed[water].sum()} animated water pixels; banks stable; night/day water brightness {night[water].mean()/day[water].mean():.2f}')
if len(sys.argv)>4:
    quiet=np.array(Image.open(sys.argv[4]).convert('RGB'))
    disturbed=np.array(Image.open(sys.argv[2]).convert('RGB'))
    effect=np.any(quiet!=disturbed,axis=2)&water
    yy,xx=np.mgrid[:h,:w]
    near=np.zeros((h,w),dtype=bool)
    for x,y,radius,strength in layout.get('disturbances',[]):
        near|=((xx/(w/640)-x)**2+(yy/(h/360)-y)**2)<(radius*1.15)**2
    assert effect.sum()>40,'Disturbances have no visible effect'
    assert not effect[~near].any(),'Local disturbances affect remote water'
    print(f'Disturbance QA passed: {effect.sum()} affected water pixels, confined to fall/rock anchors')
