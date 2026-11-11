"""Speaking dialogue portraits from the Higgsfield templates (Ellie, Gustav): baked mouth shapes and blinks.

    py -3 tools/art_portrait_talk.py [preview.png]

Sources: assets/ui/sources/higgsfield/{ellie,gustav}.png (688x1024, magenta background). Each is keyed, reduced to 103x153 (area average), 30 colours,
hard alpha (like tools/art_portraits_hf.py), then animated per pixel like Ellie's old shader: the upper lip stays, the lower lip and chin slide down 1-3
art pixels and the gap shows the inside of the mouth; blinking closes only the lids. Visemes as `SpeechPortrait`: 0 closed, 1 consonant, 2 wide (e i),
3 open (a), 4 round (o u). Writes
    assets/ui/portrait_gustav_talk.png (5 x 2: eyes open / closed), portrait_gustav.png, data/gustav_portrait.json
    assets/ui/ellie_dialogue_v4.png    (5 x 4: healthy open, healthy closed, hurt open, hurt closed), data/ellie_portrait.json
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets/ui/sources/higgsfield'
FW, FH, VIS = 103, 153, 5
OUTLINE = np.array([0x1f, 0x1d, 0x30], np.float32)
MOUTH_DARK, MOUTH_DEEP, TEETH, TONGUE = (0x3a, 0x1a, 0x2e), (0x2a, 0x14, 0x24), (0xf0, 0xe2, 0xcf), (0xa2, 0x4a, 0x60)
INK = (0x22, 0x15, 0x2f)


def load_art(name):
    a = np.asarray(Image.open(SRC / f'{name}.png').convert('RGB')).astype(np.float32)
    key = (a[..., 0] > 170) & (a[..., 2] > 170) & (a[..., 1] < 110)
    r = a.copy(); r[key] = OUTLINE
    img = Image.fromarray(r.astype(np.uint8)).resize((FW, FH), Image.BOX)
    m = np.asarray(Image.fromarray(((~key) * 255).astype(np.uint8)).resize((FW, FH), Image.BOX)) >= 128
    q = np.asarray(img.quantize(30, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB'))
    out = np.zeros((FH, FW, 4), np.uint8); out[..., :3] = q; out[..., 3] = np.where(m, 255, 0)
    return Image.fromarray(out, 'RGBA')


def blink(img, boxes, skin_at, lash_y, lash_cols):
    """Lids shut: inside each eye box everything but a lash line becomes skin."""
    out = img.copy(); px = out.load(); skin = px[skin_at][:3]
    for (x0, x1), (y0, y1) in boxes:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px[x, y] = skin + (255,)
    for (x0, x1), y in lash_cols:
        for x in range(x0, x1 + 1):
            px[x, y] = INK + (255,)
    return out


def talk(img, viseme, cx, lip_y, chin, shapes):
    rows, half, teeth, tongue = shapes[viseme]
    if rows == 0:
        return img.copy()
    src = img.copy(); sp = src.load(); out = img.copy(); op = out.load()
    for x in range(cx - half, cx + half + 1):
        f = 1.0 - ((x - cx) / (half + 0.5)) ** 2
        s = int(round(rows * f))
        if s <= 0:
            continue
        for y in range(lip_y, chin + 1):
            op[x, y + s] = sp[x, y]
        for k in range(s):
            y = lip_y + k; edge = abs(x - cx) >= half - 1
            c = MOUTH_DARK if k == 0 or edge else MOUTH_DEEP
            if teeth and k == 0 and not edge and s >= 2:
                c = TEETH
            if tongue and k == s - 1 and s >= 2 and abs(x - cx) <= half - 2:
                c = TONGUE
            op[x, y] = c + (255,)
    return out


def frames(base, **cfg):
    base = base.copy(); shut = blink(base, cfg['eyes'], cfg['skin_at'], 0, cfg['lash'])
    return [[talk(src, v, cfg['mouth_x'], cfg['lip_y'], cfg['chin'], cfg['shapes']) for v in range(VIS)] for src in (base, shut)]


def sheet_of(rows):
    s = Image.new('RGBA', (FW * VIS, FH * len(rows)), (0, 0, 0, 0))
    for r, line in enumerate(rows):
        for v, im in enumerate(line):
            s.paste(im, (v * FW, r * FH))
    return s


def spec(path, sheet, rows):
    Path(path).write_text(json.dumps({'sheet': sheet, 'frame': [FW, FH], 'visemes': VIS, 'rows': rows, 'viseme_hold': 0.07,
                                      'blink': {'interval': 3.4, 'length': 0.13}}, indent=1))


GUSTAV = dict(eyes=(((52, 58), (34, 38)), ((62, 66), (34, 38))), skin_at=(58, 41), lash=(((52, 58), 37), ((62, 66), 37)),
              mouth_x=58, lip_y=53, chin=60, shapes=[(0, 5, False, False), (1, 4, False, False), (2, 5, True, False), (3, 5, True, True), (3, 4, False, True)])
ELLIE = dict(eyes=(((43, 51), (39, 45)), ((60, 66), (39, 43))), skin_at=(52, 49), lash=(((43, 51), 39), ((60, 66), 39)),
             mouth_x=59, lip_y=53, chin=57, shapes=[(0, 3, False, False), (1, 2, False, False), (1, 4, True, False), (2, 3, True, True), (2, 2, False, True)])


def ellie_base():
    img = load_art('ellie').copy(); px = img.load()
    for x in range(57, 63):                                    # the resting mouth: a short lip line
        px[x, 52] = (0xb0, 0x70, 0x82, 255)
    return img


def ellie_hurt(img):
    out = img.copy(); px = out.load()
    for (x, y), c in {(49, 46): (0x8a, 0x12, 0x26), (50, 47): (0x8a, 0x12, 0x26), (51, 47): (0x6a, 0x0e, 0x20), (52, 48): (0x8a, 0x12, 0x26), (53, 48): (0x6a, 0x0e, 0x20)}.items():
        px[x, y] = c + (255,)
    return out


def main():
    gus = frames(load_art('gustav'), **GUSTAV)
    eb = ellie_base(); eh = ellie_hurt(eb)
    ok = frames(eb, **ELLIE); hurt = frames(eh, **ELLIE)
    sg = sheet_of(gus); se = sheet_of([ok[0], ok[1], hurt[0], hurt[1]])
    if len(sys.argv) > 1:
        bg = Image.new('RGBA', (sg.width + se.width + 20, se.height), (44, 38, 58, 255))
        bg.alpha_composite(sg, (0, 0)); bg.alpha_composite(se, (sg.width + 20, 0))
        bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST).save(sys.argv[1]); print('preview ->', sys.argv[1]); return
    sg.save(ROOT / 'assets/ui/portrait_gustav_talk.png'); gus[0][0].save(ROOT / 'assets/ui/portrait_gustav.png')
    spec(ROOT / 'data/gustav_portrait.json', 'res://assets/ui/portrait_gustav_talk.png', ['open', 'closed'])
    se.save(ROOT / 'assets/ui/ellie_dialogue_v4.png')
    spec(ROOT / 'data/ellie_portrait.json', 'res://assets/ui/ellie_dialogue_v4.png', ['open', 'closed', 'hurt_open', 'hurt_closed'])
    print('written')


main()
