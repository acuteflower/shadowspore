"""Bake the water material and waterfall sprite sheet. Run: python3 tools/art_water.py"""
from pathlib import Path
from random import Random
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/water'
OUT.mkdir(parents=True, exist_ok=True)
rng = Random(41028)

# Channels are independent masks: submerged pebbles, travelling glints, bank roots.
detail = Image.new('RGBA', (128, 128), (0, 0, 0, 255))
d = ImageDraw.Draw(detail)
for _ in range(170):
    x, y = rng.randrange(128), rng.randrange(128)
    # Small coherent clusters, no pointillist noise.
    w = rng.choice((2, 3, 4, 5)); h = rng.choice((1, 2, 2, 3))
    d.rectangle((x, y, x+w-1, y+h-1), fill=(rng.choice((100, 155, 210)), 0, 0, 255))
for _ in range(100):
    x, y = rng.randrange(128), rng.randrange(128)
    w = rng.choice((2, 3, 4, 6, 8))
    d.line((x, y, x+w, y), fill=(0, rng.choice((130, 180, 230)), 0, 255))
    if rng.random() < .32:
        d.line((x+1, y+1, x+w-1, y+1), fill=(0, 100, 0, 255))
detail.save(OUT / 'water_detail.png')

# Repeatable bank material: damp plum earth, moss and short roots.
bank = Image.new('RGBA', (64, 64), '#384f40')
b = ImageDraw.Draw(bank)
for _ in range(300):
    x, y = rng.randrange(64), rng.randrange(64)
    color = rng.choice(('#33493b', '#405744', '#485a42', '#40513c', '#514c3e'))
    b.line((x, y, x+rng.randrange(1, 4), y), fill=color)
for _ in range(34):
    x, y = rng.randrange(64), rng.randrange(64)
    b.line([(x,y), (x+1,y+1), (x+3,y+1), (x+4,y+2)], fill='#625a45')
    b.point((x+1,y), fill='#786c50')
for _ in range(30):
    x, y = rng.randrange(64), rng.randrange(64)
    b.line((x,y,x+2,y-1), fill='#55985f')
    b.point((x+1,y-2), fill='#7cb96d')
bank.save(OUT / 'bank_material.png')

# Broken falling curtains, eight looping frames. Body spans 32 pixels.
sheet = Image.new('RGBA', (48*8, 48))
for frame in range(8):
    im = Image.new('RGBA', (48,48)); p = ImageDraw.Draw(im)
    # Uneven lip and two overlapping curtains expose mossy rock on either side.
    p.polygon([(12,0),(18,0),(22,2),(27,0),(34,0),(37,3),(38,7),(37,15),
               (39,23),(36,30),(37,36),(30,37),(27,34),(23,36),
               (19,34),(14,36),(10,33),(11,26),(9,20)], fill='#326b70')
    p.polygon([(13,0),(18,0),(20,3),(21,9),(20,19),(22,24),(19,34),
               (14,34),(13,27),(14,19)], fill='#438781')
    p.polygon([(25,0),(31,0),(34,3),(35,9),(34,17),(36,25),(33,34),
               (27,35),(28,26),(25,19)], fill='#3d7e7b')
    p.line([(13,0),(14,3),(16,5)], fill='#6da79b')
    p.line([(29,0),(30,3),(32,5)], fill='#6da79b')
    for i in range(11):
        x = 13 + i*2
        shade = ('#5d9d93','#6aa89d','#4d8e87','#79b3a5')[i % 4]
        offset = (i*7 + frame*3) % 19
        for y in range(9 + offset - 19, 34, 19):
            y0 = max(9,y); y1 = min(34,y+5+i%6)
            if y1 >= y0: p.line((x,y0,x,y1), fill=shade)
    # Broken soft foam, with darker gaps and a few cream-tinted bubbles.
    p.polygon([(9,34),(15,34),(18,36),(24,34),(31,35),(38,34),(38,38),(34,39),(30,37),(24,39),(19,37),(13,39),(9,37)], fill='#60978f')
    p.line([(12,36),(17,37),(21,36)], fill='#79aaa0')
    p.line([(26,36),(31,37),(36,36)], fill='#79aaa0')
    for i in range(10):
        x = 8 + (i*7 + frame*2) % 33
        y = 35 + (i*3 + frame//2) % 8
        p.line((x,y,x+2+(i%2),y), fill=('#b6cbb6' if i%3==0 else '#91bbae'))
    sheet.alpha_composite(im, (frame*48,0))
sheet.save(OUT / 'waterfall.png')

# Static rock ledge behind the falls: the channel remains open at the top and bottom.
rock = Image.new('RGBA', (48, 48))
p = ImageDraw.Draw(rock)
p.polygon([(1,7),(5,3),(14,2),(18,5),(19,10),(19,31),(15,36),(7,36),(2,32)], fill='#303b41')
p.polygon([(29,6),(34,2),(43,4),(47,8),(46,31),(42,36),(33,36),(29,32)], fill='#303b41')
p.polygon([(3,8),(8,4),(16,4),(18,9),(17,29),(13,33),(5,32)], fill='#53605c')
p.polygon([(31,8),(35,4),(42,5),(45,9),(44,30),(40,33),(33,33),(30,29)], fill='#53605c')
p.polygon([(4,9),(9,5),(16,5),(16,9),(11,11),(5,12)], fill='#718078')
p.polygon([(32,8),(36,5),(42,6),(44,9),(39,11),(32,11)], fill='#718078')
p.line([(4,19),(8,17),(12,18),(16,16)], fill='#3e4a49')
p.line([(32,17),(37,19),(43,17)], fill='#3e4a49')
p.line([(5,27),(9,25),(15,26)], fill='#3e4a49')
p.line([(32,27),(38,25),(43,27)], fill='#3e4a49')
for x, y in [(5,6),(8,5),(12,4),(34,5),(38,4),(42,6),(5,30),(41,30)]:
    p.line((x,y,x+3,y), fill='#55985f')
    p.point((x+1,y-1), fill='#7cb96d')
rock.save(OUT / 'waterfall_rock.png')

# Four 32px shore accents; placement anchor at (16, 28).
shore = Image.new('RGBA', (128, 32))
# Low reeds: muted stems rooted in a little muddy water.
p = ImageDraw.Draw(shore)
p.ellipse((5,26,27,29), fill='#304e44')
for x,h,lean in [(9,8,-1),(12,11,-2),(15,9,0),(18,12,1),(21,7,2),(24,9,1)]:
    p.line([(x,27),(x,27-h//2),(x+lean,27-h)], fill='#3e7d56')
    p.point((x+lean,27-h), fill='#7cb96d')
    p.line((x,25-h//2,x-2,23-h//2), fill='#55985f')
# Tangled exposed roots over a short patch of moss and damp earth.
x = 32
p.ellipse((x+3,24,x+28,29), fill='#374c3b')
p.line([(x+4,26),(x+9,25),(x+13,23),(x+17,24),(x+23,21),(x+27,22)], fill='#786b4e', width=2)
p.line([(x+13,24),(x+12,27),(x+9,28)], fill='#685c48')
p.line([(x+19,23),(x+21,26),(x+25,27)], fill='#685c48')
p.line([(x+5,24),(x+10,23),(x+13,24)], fill='#55985f')
p.line([(x+22,21),(x+25,20),(x+28,21)], fill='#7cb96d')
# Gravel bar, deliberately broad and low.
x = 64
p.polygon([(x+3,27),(x+6,24),(x+12,23),(x+17,24),(x+22,23),(x+28,26),(x+28,29),(x+4,29)], fill='#4a6256')
for cx,cy,w,h in [(7,26,3,2),(12,25,4,2),(18,26,4,2),(23,25,3,2),(15,28,3,1),(25,28,2,1)]:
    p.ellipse((x+cx,cy,x+cx+w,cy+h), fill='#8b9277')
    p.line((x+cx+1,cy,x+cx+w-1,cy), fill='#b3b59a')
# Half-submerged rock with small painted foam curls.
x = 96
p.ellipse((x+3,26,x+29,30), fill='#5d9990')
p.polygon([(x+7,26),(x+8,21),(x+12,18),(x+20,18),(x+24,21),(x+26,26),(x+23,28),(x+10,28)], fill='#3b484b')
p.polygon([(x+9,24),(x+11,20),(x+15,19),(x+21,20),(x+23,23),(x+20,24)], fill='#717c74')
p.line((x+11,20,x+17,19), fill='#9ba99a')
p.line((x+5,27,x+9,27), fill='#b1cbbb')
p.line((x+23,28,x+28,27), fill='#a5c8b9')
p.line((x+12,29,x+19,29), fill='#85b5a8')
shore.save(OUT / 'shore_details.png')
