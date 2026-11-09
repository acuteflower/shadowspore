"""Gustav's dialogue portrait: the painted bust brought in line with his new sprite, plus speech and blink frames.

    py -3 tools/art_gustav_portrait.py [preview.png]     writes assets/ui/portrait_gustav_talk.png (+ portrait_gustav.png, data/gustav_portrait.json)

Base: assets/ui/sources/portrait_gustav_imagegen_v1.png (the painted 103x153 bust, Imagegen). It is changed pixel by pixel to the sprite's design
(tools/art_gustav.py, docs/characters/gustav.md):
  * the purple-grey hair, moustache and sideburns become the sprite's cool shaggy grey (`HAIR`), a few gold sawdust specks stay in the hair;
  * the slate shirt becomes the faded oatmeal linen (`SHIRT`), a moss-green neckerchief fills the open collar (`KERCH`), the wine apron the sprite's leather;
  * the grey stubble on the jaw is gone (the sprite has a clean chin), the ruddy cheeks and nose stay.
Speech animation is baked into frames, the way Ellie's shader does it at run time (`assets/shaders/dialogue_portrait.gdshader`): the upper lip and the
moustache stay, the lower lip and the chin slide down by 1-3 art pixels and the gap shows the inside of the mouth (dark, teeth, tongue); the corners
follow later so the opening is round. Viseme numbers as `ElliePortrait.viseme_for`: 0 closed, 1 consonant, 2 wide (e i), 3 open (a), 4 round (o u).
Blinking swaps only the lids. Sheet: 5 columns (viseme) x 2 rows (eyes open, eyes closed) of 103 x 153 px, no filtering, no scaling.
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets/ui/sources/portrait_gustav_imagegen_v1.png'
OUT_SHEET = ROOT / 'assets/ui/portrait_gustav_talk.png'
OUT_NEUTRAL = ROOT / 'assets/ui/portrait_gustav.png'
OUT_JSON = ROOT / 'data/gustav_portrait.json'
FW, FH = 103, 153
VISEMES = 5


def hexc(s):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


LAVENDER = [hexc(c) for c in ('4a294a', '553459', '573e69', '5e446f', '734f73', '76577d', '766089', '8e6d91')]   # dark -> light: painted hair / shirt / stubble
HAIR = [(0.0, '2b252f'), (0.4, '575059'), (0.75, '8d858f'), (1.0, 'c4bcc2')]
SHIRT = [(0.0, '3a303f'), (0.35, '6b5f68'), (0.65, 'a1948f'), (1.0, 'd0c1a8')]
LEATHER = [(0.0, '2a1822'), (0.4, '573630'), (0.8, '7a4c38'), (1.0, '8a5a40')]
KERCH = {'dark': hexc('1b2a25'), 'shade': hexc('33503f'), 'mid': hexc('5d8461'), 'light': hexc('9cba8b')}
SAWDUST = hexc('d4b987')
SKIN = {hexc(c) for c in ('e6978a', 'e69588', 'eca68f', 'd29c9e', 'd0908e', 'bf737a', 'b37581', '954955')}
SKIN_LIGHT = {hexc(c) for c in ('e6978a', 'e69588', 'eca68f')}
SKIN_FILL, SKIN_SHADE, SKIN_DEEP = hexc('e6978a'), hexc('b37581'), hexc('bf737a')
INK = hexc('22152f')
MOUTH_DARK, MOUTH_DEEP, TEETH, TEETH_SHADE, TONGUE = hexc('3a1a2e'), hexc('2a1424'), hexc('f0e2cf'), hexc('c9b8a8'), hexc('a24a60')


def ramp(t, stops):
    t = min(max(t, 0.0), 1.0)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / max(t1 - t0, 1e-6)
            a, b = hexc(c0), hexc(c1)
            return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(3))
    return hexc(stops[-1][1])


def lavender_t(rgb):
    """Where a painted lavender pixel sits between the darkest and the lightest (0..1), or None."""
    return LAVENDER.index(rgb) / (len(LAVENDER) - 1) if rgb in LAVENDER else None


def adapt(img):
    """The painted bust in the sprite's colours (neutral face, eyes open)."""
    px = img.load()
    for y in range(FH):
        for x in range(FW):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            rgb = (r, g, b)
            t = lavender_t(rgb)
            if t is not None:
                if y < 52 and x < 82:                                # hair, sideburns, brows and moustache: the sprite's cool grey
                    px[x, y] = ramp(t, HAIR) + (a,)
                elif y < 64 and 34 <= x <= 72:                       # the stubble on the jaw: bare skin
                    px[x, y] = (SKIN_SHADE if t > 0.6 else SKIN_DEEP) + (a,)
                elif y >= 56:                                        # the shirt: faded oatmeal linen
                    px[x, y] = ramp(t, SHIRT) + (a,)
                continue
            if rgb in SKIN and (y < 19 or (x < 34 and y < 26) or (x >= 66 and y < 26)):      # skin-coloured crescents inside the hair: grey locks
                lum = (r + g + b) / 3
                px[x, y] = ramp((lum - 0x70) / 0x70, HAIR[1:]) + (a,)
                continue
            if y >= 68 and g < 0x45 and r > g + 0x1a and 0x40 <= r <= 0x80 and not (44 <= x <= 64 and y < 90):   # the wine apron: the sprite's leather
                px[x, y] = ramp((r - 0x4b) / (0x6f - 0x4b), LEATHER) + (a,)
    # jaw: the painted stubble left a speckle of light and shade, make the chin calm
    for y in range(54, 64):
        for x in range(36, 66):
            if px[x, y][:3] in (hexc('d0908e'), hexc('d29c9e')) and y > 55:
                px[x, y] = SKIN_SHADE + (255,)
    # neckerchief in the open collar
    for y in range(68, 89):
        for x in range(44, 65):
            rgb = px[x, y][:3]
            if rgb in SKIN_LIGHT or rgb == hexc('d29c9e'):
                px[x, y] = (KERCH['light'] if rgb == hexc('eca68f') else KERCH['mid']) + (255,)
            elif rgb in (SKIN_DEEP, SKIN_SHADE, hexc('d0908e')):
                px[x, y] = KERCH['shade'] + (255,)
            elif rgb == hexc('954955'):
                px[x, y] = KERCH['dark'] + (255,)
    # a little sawdust in the hair
    for (x, y) in ((22, 9), (30, 6), (47, 4), (60, 7), (71, 14), (24, 22), (65, 5)):
        if px[x, y][:3] != INK and px[x, y][3] > 128 and px[x, y][:3] not in SKIN:
            px[x, y] = SAWDUST + (255,)
    return img


# ---- eyes -------------------------------------------------------------------------------------------------------------------------------------

# near eye: a dark slab (the iris) x 50-52, y 32-37 with a lash flick up to the left; far eye: x 62-63, y 33-36 beside the face's outline
EYE_BOXES = (((46, 53), (33, 37)), ((60, 63), (33, 37)))
LASH = ((48, 35), (49, 36), (50, 36), (51, 36), (52, 36), (53, 35),        # near lid, curving down in the middle
        (60, 35), (61, 36), (62, 36), (63, 35))                            # far lid


def blink(img):
    """Lids shut: the slits fill with skin, one thin lash line stays on each eye."""
    out = img.copy(); px = out.load()
    for (x0, x1), (y0, y1) in EYE_BOXES:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if px[x, y][:3] not in SKIN:
                    px[x, y] = SKIN_FILL + (255,)
    for x, y in LASH:
        px[x, y] = INK + (255,)
    return out


# ---- mouth ------------------------------------------------------------------------------------------------------------------------------------

MOUTH_X, LIP_Y = 58, 52
# per viseme: (opening in rows, half width in columns, teeth, tongue)
SHAPES = [(0, 5, False, False), (1, 4, False, False), (2, 6, True, False), (3, 5, True, True), (3, 4, False, True)]


def chin_bottom(px, x):
    """First row below the lower lip that is the outline of the chin in this column."""
    for y in range(LIP_Y + 3, 66):
        if sum(px[x, y][:3]) < 200 and px[x, y][0] < 0x60:
            return y
    return 62


def talk(img, viseme):
    """Lower lip and chin slide down, the gap shows the inside of the mouth."""
    rows, half, teeth, tongue = SHAPES[viseme]
    if rows == 0:
        return img.copy()
    src = img.copy(); sp = src.load()
    out = img.copy(); op = out.load()
    for x in range(MOUTH_X - half, MOUTH_X + half + 1):
        f = 1.0 - ((x - MOUTH_X) / (half + 0.5)) ** 2
        s = int(round(rows * f))
        if s <= 0:
            continue
        cb = chin_bottom(sp, x)
        for y in range(LIP_Y, cb + 1):                           # the lower lip and the chin move down as one block
            op[x, y + s] = sp[x, y]
        for k in range(s):                                       # the gap
            y = LIP_Y + k
            edge = abs(x - MOUTH_X) >= half - 1
            c = MOUTH_DARK if k == 0 or edge else MOUTH_DEEP
            if teeth and k == 0 and not edge and 55 <= x <= 61:
                c = TEETH
            if tongue and k == s - 1 and s >= 2 and abs(x - MOUTH_X) <= half - 2:
                c = TONGUE
            op[x, y] = c + (255,)
    return out


# ---- sheet ------------------------------------------------------------------------------------------------------------------------------------

def build():
    base = adapt(Image.open(SOURCE).convert('RGBA'))
    shut = blink(base)
    sheet = Image.new('RGBA', (FW * VISEMES, FH * 2), (0, 0, 0, 0))
    for row, src in enumerate((base, shut)):
        for v in range(VISEMES):
            sheet.paste(talk(src, v), (v * FW, row * FH))
    return base, sheet


def colour_count(img):
    a = np.array(img)
    return len({tuple(p) for p in a.reshape(-1, 4) if p[3] > 0})


def main():
    base, sheet = build()
    if len(sys.argv) > 1:
        bg = (44, 38, 58, 255)
        prev = Image.new('RGBA', (sheet.width, sheet.height), bg); prev.alpha_composite(sheet)
        prev.resize((prev.width * 3, prev.height * 3), Image.Resampling.NEAREST).save(sys.argv[1])
        print('preview ->', sys.argv[1], 'colours', colour_count(sheet))
        return
    sheet.save(OUT_SHEET)
    base.save(OUT_NEUTRAL)
    OUT_JSON.write_text(json.dumps({
        'sheet': 'res://assets/ui/portrait_gustav_talk.png', 'frame': [FW, FH], 'visemes': VISEMES, 'rows': ['open', 'closed'],
        'viseme_hold': 0.07, 'blink': {'interval': 3.4, 'length': 0.13},
    }, indent=1))
    print('wrote', OUT_SHEET.name, OUT_NEUTRAL.name, OUT_JSON.name, 'colours', colour_count(sheet))


if __name__ == '__main__':
    main()
