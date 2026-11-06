"""The first cooking station, built from the existing hut's wood, iron and stone.
python3 tools/art_cooking.py -> assets/ui/cooking/station.png, bowl.png
The animated broth, ingredients, fire, spoon and steam are layered by CookingWindow.
"""
import math
import numpy as np
import hut_lib as u
from hut_lib import h, V, BARK, BARK_D, PLANK_W, MOSS, MOSS_L, STONE, STONE_L, IRON, CLAY, GAP
from gen_art import ROOT, hexc

h.SCALE=1.0
rng=np.random.default_rng(3017)
m=h.Model()
# A weathered preparation board, curved round stones and open fire bed.
for z in range(-28,42,9):
    m.ell(V(rng.uniform(-1,1),1,z),(rng.uniform(87,91),2,4.7),PLANK_W)
    for row in range(3):
        a=V(-84+rng.uniform(0,8),3.0,z+row*1.8-1.8)
        u.log(m,a,a+V(rng.uniform(125,159),0,rng.uniform(-.5,.5)),.20,BARK_D)
    for x in [-85,85]: m.ell(V(x,3,z),(.7,.3,.7),IRON)
for x,z in [(-53,-6),(45,-14),(-37,29),(37,28)]:
    m.ell(V(x,4,z),(8,4,5),STONE_L if x<0 else STONE)
    m.ell(V(x+1,7,z),(4,.7,2.5),MOSS)
for phi in np.linspace(0,math.tau,15,endpoint=False):
    x,z=math.cos(phi)*37,math.sin(phi)*24
    m.ell(V(x,7+rng.uniform(-.5,.5),z),(rng.uniform(7,9),rng.uniform(5,6.6),rng.uniform(5,6.6)),STONE_L if x<0 else STONE)
    if rng.random()<.42: m.ell(V(x-1,12,z),(3,.6,1.8),MOSS)
for x in [-17,-6,8,19]:
    u.log(m,V(x,8,10),V(x-4,8,-11),3,BARK_D)
pot_start=len(m.prims)
# Copper-dark iron cauldron. Its large mouth is painted separately over the body.
m.ell(V(0,31,0),(31,24,25),IRON)
# Flat dark elliptical mouth, metal lip and small rivets.
m.ell(V(0,48,0),(31,2.8,25),STONE)
m.ell(V(0,49.4,0),(28,1.2,22),GAP)
for x in [-29,29]:
    m.ell(V(x,36,1),(3.5,7,3),IRON)
    for phi in np.linspace(0,math.tau,14):
        m.ell(V(x+math.sin(phi)*5,39+math.cos(phi)*6,0),(1.2,1.2,1.4),IRON)
# Blackened iron plates, hammer dents and a riveted binding, like the hut hardware.
for x in [-19,-9,4,16]:
    z=25*math.sqrt(max(.1,1-(x/32)**2))
    m.ell(V(x,28,z-.3),(rng.uniform(3,5),7,.5),IRON)
    for dy in [-3,3]:
        m.ell(V(x+rng.uniform(-1,1),28+dy,z+.15),(.85,.75,.35),GAP)
for phi in np.linspace(0,math.tau,46):
    m.ell(V(math.cos(phi)*29,28,math.sin(phi)*24),(.9,.65,.9),IRON)
for x in [-22,-12,0,12,22]:
    z=24*math.sqrt(max(.1,1-(x/31)**2))+.4
    m.ell(V(x,28,z),(1.,1.,.5),STONE_L if x<0 else IRON)
# Soot gathers at the bottom; tiny scratches pick up cool light.
for k in range(13):
    x=rng.uniform(-20,20)
    z=24*math.sqrt(max(.1,1-(x/31)**2))
    m.ell(V(x,rng.uniform(13,21),z-.5),(rng.uniform(1.1,2.8),1.4,.45),GAP)
for x in [-21,13]:
    z=24*math.sqrt(1-(x/31)**2)
    m.limb(V(x,34,z),V(x+2,36,z-.4),.22,.17,STONE_L)
for x,z in [(-17,9),(18,8),(0,-14)]: u.log(m,V(x,4,z),V(x,18,z),2.4,IRON)
pot_end=len(m.prims)
# Side dishes: berry bowl and sliced mushroom on the board.
for x,z in [(-63,14),(64,12)]:
    m.ell(V(x,9,z),(13,7,10),CLAY)
    m.ell(V(x,14,z),(11,1.4,8),GAP)
# Tattered napkin and wooden spoon resting nearby.
m.ell(V(59,3,35),(19,.8,9),u.LINEN)
u.log(m,V(-76,5,35),V(-35,5,38),1.4,PLANK_W)
m.ell(V(-33,5,38),(5.5,1.5,3.2),PLANK_W)
# A little sprig and moss in a board crack, familiar teal highlights.
for i in range(4):
    p=V(-82+i*3,4,-22+i)
    u.log(m,p,p+V(3,4,0),.5,MOSS)
    m.ell(p+V(3,4,0),(1.7,.7,1.2),MOSS_L)
def surface(arr):
    arr=u.grain(arr,410,amount=.48,mats=(STONE,STONE_L),scale=.52)
    arr=u.grain(arr,413,amount=.23,mats=(IRON,),scale=.45)
    arr=u.grain(arr,128,amount=.45,along=(1,.07),scale=.28)
    # Hand-pixelled curved iron binding: the same dark iron ramp as hut hardware.
    for x in range(85,140):
        y=151+round(9*math.sqrt(max(0,1-((x-112)/28)**2)))
        for dy,c in [(0,'211f36'),(1,'46456a'),(2,'211f36')]:
            if tuple(arr[y+dy,x]) in h.RAMPS[IRON]+h.RAMPS[STONE]:arr[y+dy,x]=hexc(c)
        if x in [89,99,112,125,136]:
            for dy in range(2):
                if tuple(arr[y+dy,x]) in h.RAMPS[IRON]+h.RAMPS[STONE]:arr[y+dy,x]=hexc('7d7ca8' if dy==0 else '3c3a5c')
    return arr
arr=surface(u.to_array(u.render(m,224,208,177,pitch=36)))
u.save(ROOT/'ui'/'cooking'/'station.png',arr)
base=h.Model();base.prims=m.prims[:pot_start]+m.prims[pot_end:]
pot=h.Model();pot.prims=m.prims[pot_start:pot_end]
u.save(ROOT/'ui'/'cooking'/'station_base.png',surface(u.to_array(u.render(base,224,208,177,pitch=36))))
u.save(ROOT/'ui'/'cooking'/'cauldron.png',surface(u.to_array(u.render(pot,224,208,177,pitch=36))))
# Served bowl: same clay as the hut pots. Contents animated/tinted in the UI.
b=h.Model()
b.ell(V(0,7,0),(19,10,15),CLAY)
b.ell(V(0,14,0),(19,1.8,15),PLANK_W)
b.ell(V(0,14.5,0),(16.5,1.1,12.5),u.SOIL)
u.save(ROOT/'ui'/'cooking'/'bowl.png',u.to_array(u.render(b,64,48,37,pitch=36)))
# Gnarled HUD roots: actual world bark colors, long grain, knots and forked ends.
from gen_art import hexc
W,H=320,24
root=np.zeros((H,W,4),np.uint8)
bark=[hexc(c) for c in ['120c1c','1a1322','34283c','55435a','85697a','b09690']]
def px(x,y,c):
    x,y=int(x),int(y)
    if 0<=x<W and 0<=y<H:root[y,x]=c
def twig(points,width):
    for a,b in zip(points,points[1:]):
        a,b=np.array(a,float),np.array(b,float)
        for t in np.linspace(0,1,max(2,int(np.linalg.norm(b-a)*2))):
            x,y=a+(b-a)*t
            for dy in range(-width,width+1):px(round(x),round(y)+dy,bark[2 if dy>0 else 3])
            px(round(x),round(y)-width,bark[4])
for x in range(W):
    cy=9+round(2.2*math.sin(x*.035)+1.4*math.sin(x*.12)+.6*math.sin(x*.41))
    radius=2+round((math.sin(x*.071)+1)*1.1)
    for dy in range(-radius-1,radius+2):
        if abs(dy)>radius:color=bark[0]
        else:
            tone=4 if dy<-1 else (3 if dy<1 else 2)
            if (int(x/7)+dy)%7==0:tone=max(1,tone-1)
            color=bark[tone]
        px(x,cy+dy,color)
    if x%13<8:px(x,cy+math.sin(x*.11),bark[1])
for x in [12,64,116,203,276,309]:
    cy=9+round(2.2*math.sin(x*.035)+1.4*math.sin(x*.12)+.6*math.sin(x*.41))
    side=-1 if x%2 else 1
    twig([(x,cy),(x+7,cy+side*4),(x+15,cy+side*8)],1)
    twig([(x+7,cy+side*4),(x+7,cy+side*8)],1)
    for dx in range(10):
        for dy in range(-4,5):
            if (dx-4.5)**2/25+dy**2/10<1:
                px(x+10+dx,cy+side*7+dy,hexc('3e7d56' if dy>0 else '55985f'))
    for dx in range(1,8):px(x+10+dx,cy+side*7,hexc('78ab70' if dx<5 else '3e7d56'))
    for dx in range(-5,6):
        for dy in range(-2,3):
            d=(dx/5)**2+(dy/2)**2
            if .48<d<1:px(x+dx,cy+dy,bark[1] if dy>0 else bark[4])
    px(x-1,cy,bark[0]);px(x,cy,bark[0]);px(x+1,cy,bark[0])
u.save(ROOT/'ui'/'cooking'/'roots.png',root)
# Small bound recipe book: uneven parchment, leather spine, stitched edges.
book=np.zeros((120,152,4),np.uint8)
leather=hexc('34283c');edge=hexc('85697a');paper=hexc('bda99a');light=hexc('d7c7af')
book[2:118,1:151]=leather
book[3:116,3:149]=edge
book[5:114,5:74]=paper;book[5:114,78:147]=paper
book[6:112,6:72]=light;book[6:112,80:146]=light
for y in range(7,112):
    for x in [6,71,80,145]:
        if (y//3+x)%5==0:book[y,x]=paper
    book[y,73:79]=hexc('55435a')
    if y%10<3:book[y,75:77]=hexc('ad8a7e')
for i in range(130):
    x=int(rng.integers(7,145));y=int(rng.integers(7,111))
    if x<71 or x>80:book[y,x]=paper
for y in range(13,110,15):
    book[y,2:4]=hexc('e6c468');book[y,148:150]=hexc('e6c468')
# A pressed sprig at the page corner and an old ribbon bookmark.
for y in range(92,118):book[y,143:145]=hexc('70304a')
for i in range(9):
    x=11+i;y=106-i
    book[y,x]=hexc('3e7d56')
    if i%2==0:book[y,x+1:x+4]=hexc('55985f')
u.save(ROOT/'ui'/'cooking'/'book.png',book)
print('COOKING ART V2: weathered station, roots and bound book written')
