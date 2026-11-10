from PIL import Image, ImageDraw
import random, json, math
from pathlib import Path
from gen_art import ROOT

W,H=320,360
OUT=ROOT/'props'/'crow_tree'
OUT.mkdir(parents=True,exist_ok=True)
r=random.Random(7142)

def layer(): return Image.new('RGBA',(W,H))
pad,trunk,crown,moss,charms,glow=[layer() for _ in range(6)]
P,T,C,M,A,G=map(ImageDraw.Draw,(pad,trunk,crown,moss,charms,glow))
# Dark, low earth pad, deliberately narrower than the crown.
P.ellipse((67,324,253,350), fill='#121824')
P.ellipse((79,328,239,345), fill='#1b3030')
for i in range(35):
 x=r.randint(83,234); y=r.randint(331,343)
 P.line((x,y,x+r.randint(2,7),y),fill=r.choice(['#30483e','#243b36','#425349']))
# Principal limbs are individually hand composed, with broad, visible horizontal perches.
limbs=[([(158,316),(156,263),(150,211),(148,162),(154,113),(149,67),(157,31)],31),
 ([(150,230),(128,202),(112,177),(88,155),(55,151),(28,138)],18),
 ([(141,201),(115,169),(100,142),(79,126),(46,125)],14),
 ([(151,180),(177,157),(198,146),(226,141),(263,144),(289,133)],17),
 ([(163,220),(180,195),(206,181),(242,177),(278,165)],16),
 ([(151,154),(131,131),(123,101),(105,79),(78,75)],12),
 ([(157,136),(177,110),(192,83),(217,67),(240,67)],12),
 ([(155,104),(145,78),(145,48),(133,26)],10),
 ([(176,158),(192,127),(206,110),(232,105)],9),
 ([(107,177),(87,168),(67,169),(51,163)],8),
 ([(203,181),(219,160),(237,155),(254,156)],8)]
def branch(draw,pts,width):
 draw.line(pts,fill='#100c19',width=width+4,joint='curve')
 draw.line(pts,fill='#302637',width=width,joint='curve')
 draw.line([(x-2,y-2) for x,y in pts],fill='#514052',width=max(2,width//3),joint='curve')
 draw.line([(x-4,y-3) for x,y in pts],fill='#716071',width=max(1,width//9),joint='curve')
for pts,w in limbs: branch(T,pts,w)
# Twist-gripped roots and the dark cavity.
for pts,w in [([(151,291),(133,316),(109,327),(77,332)],16), ([(143,305),(125,328),(111,337),(91,340)],12), ([(164,293),(177,316),(204,325),(239,328)],18), ([(166,306),(181,331),(205,339),(228,340)],12), ([(157,309),(157,330),(148,340),(132,343)],12)]: branch(T,pts,w)
T.ellipse((143,286,173,327),fill='#120d1d',outline='#67546b',width=2)
T.ellipse((149,293,169,323),fill='#0a0a17')
for pts in [[(157,318),(155,309),(160,304),(157,297)],[(160,304),(165,300),(167,296)],[(155,309),(151,306)]]:
 T.line(pts,fill='#743abc',width=2); G.line(pts,fill=(158,88,238,190),width=1)
# Curving bark furrows with coherent vertical strokes.
for x in range(136,176,5):
 pts=[]
 for y in range(218,315,4):
  xx=x+int(3*math.sin(y/19+x))
  if trunk.getpixel((xx,y))[3]: pts.append((xx,y))
 if len(pts)>1: T.line(pts, fill=r.choice(['#1a1324','#211929','#6b5868']),width=r.choice([1,1,2]))
for x,y in [(142,250),(168,270),(149,224)]:
 T.ellipse((x-3,y-6,x+4,y+5),outline='#1a1324',width=2); T.arc((x-2,y-5,x+3,y+3),180,300,fill='#786575')
# Bleached breaks and exposed tips.
for x,y in [(157,31),(133,26),(28,138),(289,133),(78,75),(240,67)]:
 T.line((x-3,y,x,y-4,x+3,y-1),fill='#a09a9e',width=2)
# Distinct foliage islands, leave branch ledges visibly clear.
clusters=[(48,107,30,15),(80,89,30,16),(110,70,26,14),(133,49,18,11),(180,66,24,14),(214,80,27,14),(256,109,27,15),(283,115,19,11),(43,125,23,10),(92,111,21,10),(191,108,20,9),(253,126,20,8)]
for cx,cy,rx,ry in clusters:
 for k in range(7):
  x=cx+r.randint(-rx//2,rx//2); y=cy+r.randint(-ry//2,ry//2); a=r.randint(rx//3,rx//2); b=r.randint(5,ry//2+2)
  C.ellipse((x-a,y-b,x+a,y+b),fill=r.choice(['#101827','#142831','#173638','#1e443f']))
 for k in range(18):
  x=cx+r.randint(-rx,rx); y=cy+r.randint(-ry,ry)
  if crown.getpixel((x,y))[3]: C.line((x,y,x+r.randint(2,5),y-1),fill=r.choice(['#29544b','#315e50','#3f6b58']))
# Cool hanging moss in separate layer, clustered strands.
for x,y,length in [(67,117,24),(95,97,34),(115,78,20),(194,77,29),(218,94,20),(258,119,32),(278,123,20),(125,139,28),(226,145,20)]:
 for j in range(4):
  xx=x+j*2; n=length-r.randint(0,12)
  M.line([(xx,y),(xx-2,y+n//2),(xx,y+n)],fill=r.choice(['#34504e','#557468','#304c49']),width=1)
  M.line((xx-2,y+n//2,xx-4,y+n//2+5),fill='#557468')
# Small hanging witch tokens, muted bone and cord.
for x,y in [(104,157),(237,155),(181,116)]:
 A.line((x,y,x+1,y+12),fill='#827568'); A.polygon([(x-3,y+12),(x+2,y+10),(x+5,y+14),(x+1,y+19),(x-3,y+17)],fill='#777481',outline='#302637')
 A.line((x-1,y+14,x+2,y+16),fill='#c0bbaf')
# shelf fungi, lichen, concentrated accents
for x,y in [(128,273),(176,253),(119,302),(186,310)]:
 T.polygon([(x,y),(x-7,y-2),(x-11,y),(x-7,y+3),(x+2,y+3)],fill='#594465',outline='#22172c'); T.line((x-8,y,x,y-1),fill='#a38aa5')
for x,y in [(135,237),(173,289),(124,311),(184,321),(138,201)]:
 for dx,dy in [(0,0),(1,0),(2,1),(0,1),(3,1)]: T.point((x+dx,y+dy),fill='#7b9984')
 G.point((x+1,y),fill=(168,255,106,180))
for name,img in [('pad',pad),('trunk',trunk),('crown',crown),('moss',moss),('charms',charms),('glow',glow)]: img.save(OUT/(name+'.png'))
# Coordinates are frame pixels; feet is world origin when the layer is positioned.
meta={'frame':[W,H],'feet':[160,340],'layers':['pad','trunk','crown','moss','charms','glow'],'collision':{'shape':'ellipse','center':[160,324],'radii':[31,14]},'perches':[[55,141],[78,117],[105,73],[217,60],[237,99],[263,135],[242,169],[67,164],[232,150]],'perch_coordinates':'frame pixels, feet at y=340; offsets = perch - feet'}
(OUT/'crow_tree.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf8')
# Day and night composite at native pixel scale. A 42px Ellie scale marker.
preview=Image.new('RGBA',(640,390),'#1b2c2d')
for k in range(2):
 bg=Image.new('RGBA',(W,H), '#1b2c2d' if k==0 else '#0a0f18')
 for img in [pad,trunk,crown,moss,charms]:
  q=img.copy()
  if k:
   a=q.getchannel('A'); q=q.convert('RGB').point(lambda v:int(v*.45)).convert('RGBA'); q.putalpha(a)
  bg.alpha_composite(q)
 if k: bg.alpha_composite(glow)
 preview.alpha_composite(bg,(k*W,20))
 d=ImageDraw.Draw(preview); d.text((k*W+8,4),'DAY' if k==0 else 'NIGHT',fill='#d9d3d9')
 d.rectangle((k*W+291,298,k*W+295,339),fill='#e9e3f7'); d.text((k*W+274,343),'42 PX',fill='#d9d3d9')
preview.convert('RGB').save(ROOT.parent/'docs'/'img'/'crow_tree.png')
print('crow tree written:',OUT)

