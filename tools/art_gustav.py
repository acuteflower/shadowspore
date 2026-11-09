"""Gustav, Shadowspore's carpenter. Eight true directions, idle/walk/run/work.

    py -3 tools/art_gustav.py [contact_sheet.png]     writes assets/characters/gustav.png and data/gustav_rig.json
    py -3 tools/art_gustav.py quick out.png           renders only a few poses (idle, walk, work) for a fast look, writes nothing else

Built from ellipsoids with the heroine's renderer (same grain, ink and outline rules as Ellie and Valdric). Design: docs/characters/gustav.md.
A stocky, broad man in his late forties: shaggy grey hair full of sawdust, a bushy moustache over a kind smile, a ruddy nose, twinkling blue eyes,
a faded oatmeal linen shirt with the sleeves rolled to the elbow, a moss-green neckerchief, a stained leather apron stretched over a comfortable belly
(chest pocket with a chisel, two patch pockets, a folding rule, nails), a belt with a buckle, a hammer and a nail pouch on his hips, a hand saw and a
coil of rope on his back, patched wool trousers tucked into sturdy boots. The pencil behind his right ear is never mirrored.
"""
import json, math, multiprocessing as mp, os, sys
from pathlib import Path
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 72, 76, 62
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
(HAIR, SHIRT, SHIRT_D, APRON, APRON_D, TROUSERS, WOOD, SKIN, MOUSTACHE, BOOTM, STEEL, KERCH, SAWDUST, ROPE) = range(BASE, BASE + 14)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['2b252f', '575059', '8d858f', 'c4bcc2'],  # shaggy grey hair: cool shade, warm light
    ['4e4350', '8d7f86', 'c8b9a2', 'ecdfc4'],  # oatmeal linen shirt
    ['2d2634', '564a56', '84747a', 'b0a090'],  # the shirt in shade / sweat / rolled cuffs
    ['2a1822', '573630', '8a5a40', 'bf8b5d'],  # leather apron
    ['1b1019', '3a2122', '5e3a2e', '845840'],  # apron straps, stains, belt, pockets
    ['1c1926', '38333f', '59505a', '7f716f'],  # patched wool trousers
    ['4f3a34', '8a6a4d', 'bf9a6c', 'e8cc98'],  # ash wood: haft, ruler, chisel
    ['8f5558', 'c0806f', 'dfa688', 'f3c8a8'],  # weathered, ruddy skin
    ['4d4349', '8f858a', 'c9c0c0', 'f0e9e3'],  # moustache and brows
    ['150e14', '36211c', '5b3a2b', '8a6342'],  # sturdy boots
    ['1c1e30', '484d68', '8a93b0', 'cdd4e8'],  # steel: saw, hammer, chisel, nails
    ['1b2a25', '33503f', '5d8461', '9cba8b'],  # moss-green neckerchief
    ['76603f', 'a88d5f', 'd4b987', 'f4e6bd'],  # sawdust
    ['4a3a2a', '7b6444', 'ad9363', 'd8c593'],  # hemp rope
]]
h.RAMPS[h.EYE] = hexc('24202e'), hexc('4a6f90'), hexc('8abbd4'), hexc('f4fcff')  # kind blue eyes with a twinkle, not Ellie's violet
SOFT = (HAIR, SKIN, MOUSTACHE)
_shade = h.shade_band


def shade_band(lam, kind, mat):
    """Hair, skin and the moustache get the heroine's soft bands, everything else the standard ones."""
    if mat in SOFT:
        return np.digitize(lam, (-0.1, 0.18, 0.62) if mat != SKIN else (-0.2, 0.12, 0.55))
    return _shade(lam, kind, mat)


h.shade_band = shade_band
V = lambda *x: np.array(x, float)
rot_x, rot_y = h.rot_x, h.rot_y


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def hair_open(q):
    """Like the heroine's face_open, but the shaggy fringe hangs lower over the forehead."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.05) & (y < 0.27 - 0.25 * np.abs(x) ** 1.2) & (np.abs(x) < 0.95)
    return (y > -0.28) & ~opening


def pose(kind, i):
    if kind in ('walk', 'run'):
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        stride = 5.8 if kind == 'run' else 4.0
        lift = 3.2 if kind == 'run' else 2.2
        return dict(feet=((3.0, stride * s, lift * max(c, 0)), (-3.0, -stride * s, lift * max(-c, 0))), breath=.3, lean=.12 if kind == 'run' else .035, swing=s, work=0, roll=math.sin(2 * a))
    if kind == 'work':
        # Six poses strike on frame 3; the arm and mallet follow the same grip.
        return dict(feet=((3.0, 1.0, 0), (-3.0, -1.0, 0)), breath=.3, lean=[.04, .02, .05, .23, .16, .08][i], swing=0, work=[0, .35, .9, 1, .55, .15][i], roll=0)
    return dict(feet=((3.0, 0, 0), (-3.0, 0, 0)), breath=[0, .45, .85, .45][i], lean=.025, swing=0, work=0, roll=0)


def build(p, kind):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None)); off = V(0, drop, 0)
    # ---------------------------------------------------------------- legs: patched wool, tucked into sturdy boots
    for hip, knee, ankle, *_ in legs:
        limb(hip, knee, 3.3, 2.85, TROUSERS); limb(knee, ankle, 2.8, 2.3, TROUSERS)
        ell(knee + V(0, 0.4, 2.55), (2.0, 2.0, 0.55), APRON_D)                      # a leather knee patch
        shaft = ankle + V(0, 4.2, -0.2)
        limb(ankle + V(0, 0.4, -0.2), shaft, 2.5, 2.65, BOOTM)                      # boot shaft
        ell(shaft + V(0, 0.9, 0), (2.95, 0.85, 2.9), BOOTM)                         # folded cuff
        ell(shaft + V(0, 1.45, 0), (2.7, 0.3, 2.65), TROUSERS)                      # trousers bunching over it
        ell(ankle + V(0, -1.0, 1.3), (2.55, 1.75, 3.5), BOOTM)                      # toe box
        ell(ankle + V(0, 1.0, 1.3), (2.0, 0.55, 1.5), BOOTM)                         # tongue
        ell(ankle + V(0, 1.25, 2.3), (1.55, 0.3, 0.3), ROPE)                         # laces
        ell(ankle + V(0, -2.35, 1.4), (2.65, 0.55, 4.0), APRON_D)                    # thick sole
        ell(ankle + V(0, 0.2, -0.5), (2.45, 2.3, 2.5), BOOTM)                        # heel
        ell(ankle + V(0, -2.25, -1.4), (2.3, 0.6, 1.3), APRON_D)                     # heel block
    m.off = off
    lean = p['lean']; R = h.rot_x(lean); b = p['breath']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    # ---------------------------------------------------------------- torso: broad shoulders, a comfortable belly
    ell(T((0, 25, 0.3)), (5.9, 3.7, 4.5), TROUSERS, R=R)
    ell(T((0, 29.6 + b * .05, 1.7)), (6.4, 5.6, 5.5), SHIRT, R=R)                    # the belly under the apron
    ell(T((0, 34.6 + b * .12, 0.3)), (7.3, 4.6, 4.7), SHIRT, R=R)
    ell(T((0, 37.3, 0.0)), (7.9, 2.5, 4.2), SHIRT, R=R)                               # shoulders
    ell(T((0, 32.8, -4.4)), (3.7, 3.4, 0.6), SHIRT_D, R=R)                            # a sweat patch on his back
    ell(T((-1.5, 36.2, -4.2)), (2.0, 1.6, 0.4), SHIRT_D, R=R)
    # neckerchief: a faded moss-green cloth knotted at the front
    ell(T((0, 39.2, 0.3)), (3.9, 1.35, 3.8), KERCH, R=R)
    ell(T((0.8, 38.3, 3.5)), (1.25, 1.15, 0.95), KERCH, R=R)
    ribbon([T((0.8, 38.0, 3.9)), T((0.4, 36.5, 5.0)), T((0.9, 35.0, 5.4))], [1.0, 0.9, 0.55], 0.4, KERCH, (0, 0, 1), kind='')
    # ---------------------------------------------------------------- the leather apron: bib, stretched over the belly, hem, straps, pockets
    ribbon([T((0, 38.4, 4.6)), T((0, 35.0, 6.2)), T((0, 29.6, 8.1)), T((0, 22.6, 6.7)), T((0, 15.4, 5.1))], [3.4, 4.9, 6.1, 6.3, 5.8], 0.72, APRON, (0, 0, 1), kind='')
    ell(T((0, 15.0, 5.1)), (5.9, 0.5, 0.8), APRON_D, R=R)                             # darker hem
    ell(T((-2.2, 19.0, 6.55)), (1.9, 2.4, 0.5), APRON_D, R=R)                         # old stains
    ell(T((3.1, 29.4, 8.65)), (1.5, 1.2, 0.35), APRON_D, R=R)
    ell(T((-3.6, 26.8, 8.0)), (1.0, 0.8, 0.3), APRON_D, R=R)
    for side in (-1, 1):
        # neck straps over the shoulders and crossing on his back, riveted to the bib corners
        ribbon([T((side * 3.2, 38.0, 4.5)), T((side * 4.0, 39.9, 1.4)), T((side * 3.4, 39.6, -2.3))], [.85, .85, .8], .35, APRON_D, (0, 0, 1), kind='')
        ribbon([T((side * 3.4, 39.2, -2.6)), T((0, 33.0, -5.1)), T((-side * 4.0, 27.2, -5.0))], [.8, .8, .8], .3, APRON_D, (0, 0, 1), kind='')
        ell(T((side * 3.6, 37.3, 5.15)), (.5, .5, .35), h.GOLD, R=R, kind='emit')
        # waist strap round the belly, with a buckle
        ribbon([T((side * 6.5, 26.4, 1.6)), T((side * 5.4, 26.4, -2.6)), T((side * 2.0, 26.4, -5.3))], [1.0, 1.0, 1.0], .5, APRON_D, (0, 0, 1), kind='')
    ribbon([T((-6.6, 26.4, 1.6)), T((-4.2, 26.4, 6.3)), T((0, 26.4, 8.2)), T((4.2, 26.4, 6.3)), T((6.6, 26.4, 1.6))], [1.05] * 5, .5, APRON_D, (0, 0, 1), kind='')
    ell(T((0, 26.4, 8.75)), (1.25, 1.0, 0.35), h.GOLD, R=R, kind='emit')
    ell(T((0, 26.4, 9.05)), (0.55, 0.5, 0.25), APRON_D, R=R)
    # apron ties and a bow on his back
    ell(T((0, 26.0, -5.7)), (1.0, 0.8, 0.8), APRON_D, R=R)
    for side in (-1, 1):
        ell(T((side * 1.4, 26.3, -5.8)), (1.5, 0.75, 0.55), APRON_D, R=R)
        ribbon([T((side * .8, 25.6, -5.8)), T((side * 1.5, 22.0, -6.0)), T((side * 2.1, 18.4, -5.6))], [.8, .75, .45], .3, APRON_D, (0, 0, 1), kind='')
    # chest pocket with a chisel and a tape roll; two patch pockets with flaps and rivets
    ell(T((2.1, 33.6, 7.1)), (2.2, 1.9, 0.5), APRON, R=R)
    ell(T((2.1, 35.2, 7.35)), (2.3, 0.5, 0.45), APRON_D, R=R)
    limb(T((1.3, 33.8, 7.0)), T((1.6, 38.3, 6.9)), .62, .55, WOOD)                    # chisel handle
    ell(T((1.6, 38.7, 6.9)), (.7, .45, .7), STEEL, R=R)                                # its steel ferrule
    ell(T((2.9, 34.0, 7.65)), (.7, .85, .35), h.GOLD, R=R, kind='emit')                # brass tape roll
    for x in (-3.0, 3.0):
        ell(T((x, 20.8, 6.95)), (2.6, 2.7, 0.55), APRON, R=R)
        ell(T((x, 22.9, 7.25)), (2.7, 0.65, 0.5), APRON_D, R=R)
    # a folding rule sticks out of the right pocket, nails and a wedge out of the left
    limb(T((-3.0, 22.0, 7.2)), T((-3.7, 30.2, 7.65)), .62, .62, WOOD)
    for t in (0.35, 0.68):
        ell(T((-3.0 - .7 * t, 22.0 + 8.2 * t, 7.75)), (.62, .38, .3), h.GOLD, R=R, kind='emit')
    for k, x in enumerate((2.0, 2.9, 3.8)):
        limb(T((x, 22.4, 7.3)), T((x + .2, 24.6 + k * .5, 7.35)), .3, .3, STEEL)
    ell(T((4.2, 22.9, 7.45)), (.7, .9, .35), WOOD, R=R)
    # ---------------------------------------------------------------- belt gear: hammer in a loop on the left hip, nail pouch behind it, a hand saw and a coil of rope on his back
    ell(T((6.7, 26.9, 0.9)), (1.8, 1.25, 1.2), STEEL, R=R)
    ell(T((6.7, 26.9, 2.0)), (.6, .85, .3), STEEL, R=R)
    limb(T((6.7, 26.5, 0.9)), T((7.0, 17.6, 0.3)), .7, .62, WOOD)
    ell(T((7.0, 17.3, 0.3)), (.62, .9, .62), APRON_D, R=R)
    ell(T((6.0, 23.4, -2.7)), (2.1, 2.4, 1.8), APRON_D, R=R)
    ell(T((6.0, 25.5, -2.7)), (2.2, 0.8, 1.95), APRON, R=R)
    ell(T((6.1, 25.0, -0.8)), (.45, .45, .35), h.GOLD, R=R, kind='emit')
    ell(T((2.9, 25.3, -5.4)), (1.1, 1.7, 0.9), WOOD, R=R)                              # the saw's handle
    ell(T((2.9, 25.6, -5.35)), (0.45, 0.55, 1.05), APRON_D, R=R)
    for k in range(16):                                                               # the blade, teeth down
        y = 23.2 - k * 0.9
        ell(T((2.9, y, -5.6)), (2.0 - 0.07 * k, .6, .3), STEEL, R=R)
    ell(T((2.9, 9.0, -5.6)), (1.0, .5, .3), STEEL, R=R)
    for k in range(10):
        a = 2 * math.pi * k / 10
        ell(T((-4.9 + 2.3 * math.cos(a), 21.8 + 2.3 * math.sin(a), -5.3)), (.8, .8, .8), ROPE, R=R)   # a coil of rope
    ell(T((-4.9, 21.8, -5.6)), (1.0, 1.0, .7), ROPE, R=R)
    # sawdust on the shoulders and the apron
    for x, y, z in [(-5.6, 39.8, 0.5), (4.4, 40.0, -1.0), (6.3, 39.2, 1.0)]:
        ell(T((x, y, z)), (.55, .4, .5), SAWDUST, R=R)
    # ---------------------------------------------------------------- arms: thick rolled sleeves, strong forearms, big hands
    for side in (-1, 1):
        shoulder = T((side * 7.3, 36.8, 0)); el = T((side * 9.0, 30.4, 0.3))
        if kind == 'work' and side == -1:
            hand = T((-6.8 + 2.0 * p['work'], 25.0 + 8.0 * (1 - p['work']), 6.3)); el = T((-9.4, 31.0, 2.0))
        else:
            hand = T((side * 8.4, 24.6, side * p['swing'] * 2.2 + 0.4))
        ell(shoulder, (3.4, 3.2, 3.3), SHIRT, R=R)
        limb(shoulder, el, 3.0, 2.65, SHIRT)
        d = (hand - el) / np.linalg.norm(hand - el)
        ell(el + d * .5, (2.9, 1.15, 2.9), SHIRT_D, R=R)                              # the rolled cuff
        ell(el + d * 1.2, (2.75, 0.8, 2.75), SHIRT, R=R)
        limb(el + d * 1.3, hand, 2.3, 1.85, SKIN)                                     # forearm
        ell(el + d * 5.0 + V(side * .9, 0, .5), (.5, 0.9, 0.4), MOUSTACHE, R=R)       # arm hair
        limb(hand - d * 2.8, hand - d * .9, 2.0, 1.95, APRON_D)                       # leather wrist strap
        ell(hand - d * 1.9, (.45, .45, .35), h.GOLD, kind='emit')
        ell(hand + d * .6, (2.1, 2.3, 1.95), SKIN)
        ell(hand + d * .3 + V(side * -1.1, 0, 1.2), (.85, 1.2, .8), SKIN)             # thumb
        if kind == 'work' and side == -1:
            direction = V(-.35, .85 - 1.4 * p['work'], .4); direction /= np.linalg.norm(direction)
            tip = hand + direction * 8.4
            limb(hand - direction * 1.9, tip, .62, .62, WOOD)
            ell(hand + direction * 1.6, (.85, .85, .85), APRON_D)
            head_c = tip + direction * .6
            Rm = h.frame_from(np.cross(direction, V(0, 0, 1)), direction)
            ell(head_c, (2.0, 3.3, 2.0), WOOD, R=Rm)                                  # a heavy wooden mallet head
            for sgn in (-1, 1):
                ell(head_c + Rm @ V(0, sgn * 2.45, 0), (2.08, .5, 2.08), STEEL, R=Rm)   # iron bands
    # ---------------------------------------------------------------- head: shaggy hair, bushy brows, a ruddy nose, a big moustache over a smile
    hc = T((0, 43.7 + b * .22, .4)); ell(hc, (5.0, 5.25, 4.85), SKIN, R=R, kind='head')
    ell(hc + R @ V(0, .4, -.35), (5.25, 5.5, 5.1), HAIR, R=R, kind='hair', tag=3.0, clip=hair_open)
    rng = np.random.default_rng(11)
    for n in range(26):                                                                # shaggy tufts, each lying radially on the skull
        th = rng.uniform(0, 2 * math.pi); ph = math.acos(rng.uniform(-.35, 1.0))
        dirv = V(math.sin(ph) * math.sin(th), math.cos(ph), math.sin(ph) * math.cos(th))
        if dirv[2] > -.1 and dirv[1] < .86:
            continue                                                                   # keep the face clear
        rad = rng.uniform(.8, 1.2)
        centre = hc + R @ (V(0, .4, -.35) + dirv * V(5.0, 5.3, 4.9))
        axis = R @ (dirv * V(1, 1.1, 1) + V(rng.uniform(-.25, .25), .15, rng.uniform(-.25, .25)))
        ell(centre, (rad, rng.uniform(1.3, 1.9), rad), HAIR, R=h.frame_from(axis, V(0, 0, 1)), kind='hair', tag=float(n))
    for side in (-1, 1):
        ell(hc + R @ V(side * 5.1, -1.5, 0.3), (.85, 1.55, .95), SKIN, R=R)             # ears
        ell(hc + R @ V(side * 5.25, -1.5, 0.45), (.45, 1.0, .5), SKIN, R=R)
        ell(hc + R @ V(side * 5.0, .7, -.6), (1.1, 1.4, 1.2), HAIR, R=R, kind='hair', tag=side + 7.0)   # grey sideburns over the ears
        ell(hc + R @ V(side * 2.2, 1.45, 4.55), (1.9, .7, .85), MOUSTACHE, R=R @ rot_z(side * -.14))  # bushy brows
        ell(hc + R @ V(side * 3.3, -1.0, 3.55), (1.35, 1.0, .75), h.BLUSH, R=R)         # ruddy cheeks
    ell(hc + R @ V(0, -1.0, 4.95), (1.2, 1.3, 1.05), h.BLUSH, R=R)                       # a round, ruddy nose
    ell(hc + R @ V(0, -1.35, 5.4), (.55, .55, .35), SKIN, R=R)
    ell(hc + R @ V(0, -3.6, 4.1), (1.35, .28, .45), h.MOUTH, R=R)                       # the kind smile
    ell(hc + R @ V(0, -5.0, 3.0), (2.3, 1.1, 2.0), SKIN, R=R)                          # chin
    for side in (-1, 1):                                                               # the moustache: two thick lobes that sweep out and curl up
        limb(hc + R @ V(side * .6, -2.3, 5.25), hc + R @ V(side * 4.0, -3.6, 4.2), 1.35, 1.0, MOUSTACHE)
        ell(hc + R @ V(side * 4.6, -3.0, 3.8), (1.0, 1.0, .95), MOUSTACHE, R=R)
        ell(hc + R @ V(side * 2.1, -2.0, 5.45), (1.4, .8, .75), MOUSTACHE, R=R)
    ell(hc + R @ V(0, -2.2, 5.5), (1.5, .85, .8), MOUSTACHE, R=R)
    for x, y, z in [(-2.6, 4.9, 1.3), (3.4, 4.2, 1.0)]:   # sawdust in his hair
        ell(hc + R @ V(x, y, z), (.55, .4, .5), SAWDUST, R=R)
    # the carpenter's pencil tucked behind his right ear, never mirrored
    limb(hc + R @ V(-5.0, -.6, -.9), hc + R @ V(-5.6, 3.0, -1.2), .42, .42, WOOD)
    ell(hc + R @ V(-5.7, 3.3, -1.2), (.45, .55, .45), h.GOLD, R=R, kind='emit')
    ell(hc + R @ V(-4.85, -.8, -.85), (.38, .55, .38), SKIN, R=R)
    return m


def render_one(job):
    sector, index, kind, i = job; p = pose(kind, i); model = build(p, kind)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


CLIPS = {'idle': {'start': 0, 'count': 4, 'fps': 4}, 'walk': {'start': 4, 'count': 6, 'fps': 8},
         'run': {'start': 10, 'count': 6, 'fps': 10}, 'work': {'start': 16, 'count': 6, 'fps': 7, 'strike': 3}}


def contact(arr, path, picks, scale=3):
    from PIL import Image
    canvas = Image.new('RGB', (len(picks) * FW * scale, 8 * FH * scale), (38, 34, 50))
    for s in range(8):
        for j, i in enumerate(picks):
            src = Image.fromarray(arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW]); tile = Image.new('RGBA', (FW, FH), (38, 34, 50, 255)); tile.alpha_composite(src)
            canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (j * FW * scale, s * FH * scale))
    canvas.save(path)


def main():
    quick = len(sys.argv) > 1 and sys.argv[1] == 'quick'
    jobs = [(s, entry['start'] + i, k, i) for s in range(8) for k, entry in CLIPS.items() for i in range(entry['count'])]
    if quick:
        keep = {0, 5, 19}
        jobs = [j for j in jobs if j[1] in keep]
    arr = np.zeros((8 * FH, 22 * FW, 4), dtype=np.uint8)
    print('Rendering', len(jobs), 'Gustav poses', flush=True)
    with mp.Pool(min(6, os.cpu_count() or 1)) as pool:
        for s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(arr, sys.argv[2], [0, 5, 19])
        print('quick sheet written', flush=True)
        return
    write_array(ROOT / 'characters/gustav.png', arr)
    (ROOT.parent / 'data/gustav_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': 22, 'rows': 8, 'clips': CLIPS}, indent=2) + '\n')
    if len(sys.argv) > 1:
        contact(arr, sys.argv[1], [0, 4, 6, 19])
    print('Gustav sheet and rig written', flush=True)


if __name__ == '__main__':
    main()
