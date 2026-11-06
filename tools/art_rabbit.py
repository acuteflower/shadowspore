#!/usr/bin/env python3
"""Wild rabbits, using the heroine's miniature 3D/pixel renderer (numpy only).
Six fur/ear builds, eight true directions, 26 pose columns at 32x32; feet (16,25).
Idle 0..3, graze 4..9, alert 10..13, hop 14..19, groom 20..25.
python3 tools/art_rabbit.py [--preview-only] renders the sheet and a contact sheet.
"""
import math
from pathlib import Path
import sys
import numpy as np
import art_hero3d as art
from gen_art import hexc, write_png, CLEAR

ROOT = Path(__file__).resolve().parent.parent
FW, FH, COLS, VARIANTS = 32, 32, 26, 6
FUR = [
    ['4b3948', '79605e', 'a78a75', 'd0b797'],
    ['3e354d', '6d657d', '9e99ad', 'c8c3d0'],
    ['604340', '947051', 'bd986b', 'e1c69b'],
    ['241e32', '463b50', '6c5c70', '9b8796'],
    ['74616b', 'a59290', 'd0bdb0', 'eee0cc'],
    ['513341', '86534d', 'b77f64', 'd9ab86'],
]
FUR_MAT, BELLY, INNER, EYE, NOSE, TAIL, DARK, GLINT = range(8)
art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = FW, FH, 25.0, 3, 1.0
art.DECAL_WEIGHT = {EYE: 3.0, NOSE: 2.0, GLINT: 4.5, INNER: 1.4}
art.ink_color = lambda mat: hexc('322938' if mat not in (EYE, DARK) else '211c2d')


def materials(variant):
    ramps = [FUR[variant], ['796471','aa9492','d9c8b8','f2e7d4'],
             ['77505f','a7737c','c99599','e1b3b0'], ['100e1b','171323','241b30','30233a'],
             ['694351','8e5c6a','b98289','dbabb0'], ['817281','b9abb5','e7ddd8','fff3e4'],
             ['30263a','4c3c4b','705764','9b7c80'], ['cbbdc4','e2d7d7','f1e9df','fff7e9']]
    art.RAMPS = [[hexc(c) for c in ramp] for ramp in ramps]


def build(variant, kind, phase):
    model = art.Model()
    t = phase
    breath = math.sin(t * math.tau)
    size = [1.0, .94, .91, .93, 1.02, .97][variant]
    body_y, body_z, head_y, head_z = 4.5, -1.4, 7.2, 3.6
    stretch, ear_back, crouch = 1.0, .05, 0.0
    blink = kind == 'idle' and phase > .7
    if kind == 'graze':
        head_y, head_z = 3.1 + .35 * breath, 5.1
        body_y = 4.0
        ear_back = .9 + .08 * breath
    elif kind == 'alert':
        body_y, head_y, head_z = 5.1, 9.4, 3.1
        ear_back = -.14
    elif kind == 'hop':
        stretch = 1.0 + .23 * math.sin(t * math.pi)
        body_y = 4.3 + .4 * math.sin(t * math.pi)
        head_y, head_z = 6.5, 4.0
        ear_back = .5 + .6 * math.sin(t * math.pi)
        crouch = math.cos(t * math.tau)
    elif kind == 'groom':
        head_y, head_z = 5.8 + .7 * breath, 3.8
        ear_back = .45
        blink = True
    else:
        body_y += breath * .15
        head_y += breath * .2
    # Plump rump, slim shoulders and haunches; belly is exposed only from below/front.
    model.ell((0, body_y, body_z), (3.8 * size, 3.65 * size, 4.7 * size * stretch), FUR_MAT)
    model.ell((0, body_y - 1.7, -.2), (3.1 * size, 1.7, 3.9), BELLY)
    model.ell((0, body_y + .1, -5.8 * stretch), (1.7, 1.7, 1.65), TAIL)
    for side in (-1, 1):
        model.ell((side * 2.6, 2.6, -2.5), (2.15, 2.4, 2.7), FUR_MAT)
        hind_z = -2.8 + crouch * 1.3 if kind == 'hop' else -1.7
        model.ell((side * 2.7, .9, hind_z), (1.35, .85, 2.3), BELLY)
        paw_y = .85
        paw_z = 3.0 + (1.5 * math.sin(t * math.tau) if kind == 'hop' else 0)
        if kind == 'groom':
            paw_y, paw_z = 5.3 + breath * .7, 5.2
        model.ell((side * 1.7, paw_y, paw_z), (.85, .8, 1.55), BELLY)
    head_turn = .12 * breath if kind in ('alert', 'idle') else .04 * breath
    model.ell((head_turn, head_y, head_z), (2.85 * size, 2.65, 2.8), FUR_MAT)
    # Pale cheeks and muzzle, a tiny rose nose. Eyes stay natural black, never emissive.
    model.ell((head_turn, head_y - .9, head_z + 2.2), (2.0, 1.2, 1.2), BELLY)
    model.ell((head_turn, head_y - .6, head_z + 3.0), (.56, .4, .38), NOSE)
    for side in (-1, 1):
        eye_h = .17 if blink else .72
        model.ell((side * 2.1 + head_turn, head_y + .55, head_z + 1.8), (.64, eye_h, .64), EYE)
        if not blink:
            model.ell((side * 2.12 + head_turn, head_y + .81, head_z + 2.24), (.21, .22, .2), GLINT)
        ear_len = [3.55, 3.9, 3.3, 3.6, 3.7, 3.45][variant]
        flick = .16 * math.sin(t * math.tau + side * 1.4) if kind in ('idle','alert') else .05 * breath
        lean = ear_back + flick + (.16 if side == -1 and variant in (2, 5) else 0)
        rot = art.rot_x(lean) @ np.array([[math.cos(side*.16), -math.sin(side*.16), 0],
                                        [math.sin(side*.16), math.cos(side*.16), 0], [0,0,1]])
        c = np.array([side * 1.35, head_y + 2.0, head_z - .5]) + rot @ np.array([0, ear_len*.78, 0])
        model.ell(c, (1.03, ear_len, .7), FUR_MAT, R=rot)
        model.ell(c + rot @ np.array([0, .25, .54]), (.48, ear_len*.72, .2), INNER, R=rot)
        # Narrow darker ear tips are part of the wild coat, not accessories.
        model.ell(c + rot @ np.array([0, ear_len*.83, .02]), (.65, .65, .48), DARK, R=rot)
    return model


def frame(variant, sector, col):
    kind, phase = ('idle', col/4) if col < 4 else (('graze',(col-4)/6) if col < 10 else
                 (('alert',(col-10)/4) if col < 14 else (('hop',(col-14)/6) if col < 20 else ('groom',(col-20)/6))))
    materials(variant)
    model = build(variant, kind, phase)
    depth, code = art.render(model.transform(math.pi/2 - sector*math.pi/4, 0))
    px = art.to_pixels(depth, code)
    # Keep the shadow separate at runtime, so it stays on the ground during airborne frames.
    return [[CLEAR if c[3] < 255 else c for c in row] for row in px]


def main():
    preview = np.zeros((VARIANTS * FH, 12 * FW, 4), dtype=np.uint8)
    preview_only = '--preview-only' in sys.argv
    sheet = None if preview_only else np.zeros((VARIANTS * 8 * FH, COLS * FW, 4), dtype=np.uint8)
    for variant in range(VARIANTS):
        for sector in range(8):
            for col in range(COLS):
                if preview_only and not ((sector == 0 and col in (0,4,10,14,16,20)) or (col == 0 and sector in (1,2,3,4,5,6))):
                    continue
                px = np.asarray(frame(variant,sector,col),dtype=np.uint8)
                if sheet is not None:
                    y=(variant*8+sector)*FH; x=col*FW
                    sheet[y:y+FH,x:x+FW]=px
                choices = [(0,0),(1,0),(2,0),(3,0),(4,0),(5,0),(6,0),(0,4),(0,10),(0,14),(0,16),(0,20)]
                if (sector,col) in choices:
                    x=choices.index((sector,col))*FW; y=variant*FH
                    preview[y:y+FH,x:x+FW]=px
        print('Rabbit variant',variant+1,'/',VARIANTS,flush=True)
    from world_data import save_png
    if sheet is not None: save_png(ROOT/'assets/wildlife/rabbit.png',sheet)
    save_png(ROOT/'docs/img/rabbits.png',preview)

if __name__ == '__main__': main()
