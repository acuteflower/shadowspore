"""The witch of the Hexenwald's tower. Eight true directions; idle / walk / stir / craft / counter / cast.

    py -3 tools/art_witch.py [contact_sheet.png]     writes assets/characters/witch.png, witch_glow.png and data/witch_rig.json
    py -3 tools/art_witch.py quick out.png           renders only a few poses for a fast look, writes nothing else

Built from ellipsoids with the heroine's renderer (same grain, ink and outline rules as Ellie, Gustav, Valdric, Torben).
A young woman: long dark brown hair with chestnut lights, parted in the middle and held back by a silver clip at each temple, falling over her
shoulders and down her back; dark brown eyes under strong dark brows, full rose lips; a pendant with a teal stone on a fine gold chain.
She wears the wood: a crooked pointed hat in the tower roof's dusky violet (wine band, silver buckle, a toad cap and a glowing leaf on the brim, a
crescent charm at the bent tip), a laced violet bodice over a black-plum dress with a ragged hem, a short plum capelet, wine-and-bone striped
sleeves and stockings, pointed buckled boots, a belt with a pouch and two vials of witch green (#a8ff6a) that glow.
Clips: idle 4, walk 6, stir 8 (both hands on the long ladle, round and round: at the cauldron), craft 6 (the little hammer at the jewellery
bench, `strike` 3), counter 4 (leaning on her counter), cast 6 (a witch flame grows in her raised hand)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 76, 96, 80
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
(HAIR, HAIR_L, SKIN, BROW, LIP, DRESS, BODICE, CAPE, HAT, WINE, BONE, SILVER, BOOT, HEXG) = range(BASE, BASE + 14)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['120a0c', '24140f', '3a2216', '54341f'],  # long dark brown hair (darker: the user's reference photos)
    ['1c100c', '362012', '52321a', '74502a'],  # its chestnut lights, kept for the lit side only
    ['7a4a48', 'b8806a', 'dca888', 'f2caa8'],  # warm skin
    ['120a0e', '22141a', '3a2420', '58382a'],  # strong dark brows
    ['6a2a38', 'a04858', 'c86a74', 'e89aa0'],  # rose lips
    ['0c0812', '1a1322', '2c2236', '44344c'],  # the dress: black plum, like the hag elm's bark
    ['100b1e', '1e1536', '30234e', '483666'],  # bodice: the witch's violet
    ['120e1e', '231a32', '382b48', '524060'],  # capelet: dusty plum
    ['0e0a1c', '1c1434', '2e224c', '463464'],  # the hat: the tower roof's dusky violet
    ['24081a', '481026', '701a34', '983044'],  # wine red: band, stripes, belt
    ['56506c', '8a8698', 'b8b4b8', 'dedacc'],  # bone: stripes, lacing, the ladle
    ['4a5670', '8a98b4', 'c8d4e8', 'f4f8ff'],  # silver: clips, buckles, charms
    ['0a0810', '18121c', '2a2030', '40324a'],  # boots
    ['2e6a2a', '4a9a3a', 'a8ff6a', 'eaffc4'],  # witch green: everything that shines
]]
h.RAMPS[h.EYE] = hexc('1a1014'), hexc('4a2a1a'), hexc('7a4a28'), hexc('f6efe6')  # dark brown eyes
SOFT = (HAIR, HAIR_L, SKIN)
_shade = h.shade_band


def shade_band(lam, kind, mat):
    if mat in SOFT:
        return np.digitize(lam, (-0.1, 0.18, 0.62) if mat != SKIN else (-0.2, 0.12, 0.55))
    return _shade(lam, kind, mat)


h.shade_band = shade_band
V = lambda *x: np.array(x, float)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def hair_open(q):
    """The hair cap leaves the face free: a middle parting, the hair drawn back to the temples."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.05) & (y < 0.5 - 0.42 * np.abs(x) ** 1.6) & (np.abs(x) < 0.86)
    return (y > -0.3) & ~opening


CLIPS = {'idle': {'start': 0, 'count': 4, 'fps': 4}, 'walk': {'start': 4, 'count': 6, 'fps': 8}, 'stir': {'start': 10, 'count': 8, 'fps': 7},
         'craft': {'start': 18, 'count': 6, 'fps': 7, 'strike': 3}, 'counter': {'start': 24, 'count': 4, 'fps': 3}, 'cast': {'start': 28, 'count': 6, 'fps': 7},
         'talk': {'start': 34, 'count': 6, 'fps': 5}, 'listen': {'start': 40, 'count': 4, 'fps': 4},
         'point': {'start': 44, 'count': 6, 'fps': 6}, 'inspect': {'start': 50, 'count': 6, 'fps': 5},
         'give': {'start': 56, 'count': 6, 'fps': 5}}
FRAMES = 62


def pose(kind, i):
    p = dict(feet=((2.3, 0, 0), (-2.3, 0, 0)), breath=0.3, lean=.02, swing=0.0, work=0.0, roll=0.0, t=0.0, head=0.0)
    if kind == 'walk':
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        p.update(feet=((2.2, 3.4 * s, 2.0 * max(c, 0)), (-2.2, -3.4 * s, 2.0 * max(-c, 0))), lean=.04, swing=s, roll=math.sin(2 * a))
    elif kind == 'stir':
        wave = math.sin(math.tau * i / 8)
        p.update(feet=((2.6, 1.2, 0), (-2.6, -0.8, 0)), lean=.16 + .045 * wave, t=i / 8.0, breath=.3 + .3 * wave, head=.17)
    elif kind == 'craft':
        p.update(feet=((2.5, 0.8, 0), (-2.5, -0.6, 0)), lean=[.15, .14, .15, .2, .18, .16][i], work=[0, .4, .9, 1, .5, .15][i], head=.22)
    elif kind == 'counter':
        p.update(lean=.11, breath=[0, .5, .9, .5][i], head=[0, .03, .06, .03][i])
    elif kind == 'cast':
        p.update(lean=-.03, t=[0, .3, .65, 1, 1, .9][i], work=[0, .1, .4, .8, 1, .7][i], breath=.2 + .12 * i)
    elif kind in ('talk', 'listen', 'point', 'inspect', 'give'):
        waves = {'talk': [0, .5, 1, .65, .25, .1], 'listen': [0, .3, .5, .2],
                 'point': [0, .35, .8, 1, 1, .9], 'inspect': [0, .4, .8, 1, .9, .7],
                 'give': [0, .25, .65, 1, 1, .85]}
        p.update(t=waves[kind][i], breath=.2 + .3 * waves[kind][i],
                 lean=.08 if kind == 'inspect' else .02,
                 head=.18 if kind == 'inspect' else (.08 if kind == 'listen' else 0))
    else:
        p.update(breath=[0, .45, .85, .45][i])
    return p


def build(p, kind):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None)); off = V(0, drop, 0)
    sw = p['swing']
    # ---------------------------------------------------------------- legs: striped stockings, pointed boots with a buckle
    for hip, knee, ankle, *_ in legs:
        limb(hip, knee, 2.5, 2.1, DRESS)
        for j in range(6):
            a0, a1 = knee + (ankle - knee) * (j / 6.0), knee + (ankle - knee) * ((j + 1) / 6.0)
            limb(a0, a1, 2.0 - 0.06 * j, 1.95 - 0.06 * j, WINE if j % 2 == 0 else BONE)
        ell(ankle + V(0, 1.7, -0.1), (2.3, 1.0, 2.3), BOOT)                           # the cuff
        ell(ankle + V(0, 0.2, -0.3), (2.1, 2.0, 2.2), BOOT)
        ell(ankle + V(0, -1.0, 1.4), (2.0, 1.5, 3.2), BOOT)
        ell(ankle + V(0, -1.2, 4.2), (1.2, 1.0, 1.7), BOOT)                           # the pointed toe ...
        ell(ankle + V(0, -0.5, 5.5), (0.7, 0.75, 0.8), BOOT)                          # ... curls up
        ell(ankle + V(0, -2.2, -1.3), (1.5, 0.9, 1.2), BOOT)                          # a small heel
        ell(ankle + V(0, 0.6, 1.9), (1.0, 0.8, 0.4), SILVER)                          # buckle
    m.off = off
    lean = p['lean']; R = h.rot_x(lean); b = p['breath']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    # ---------------------------------------------------------------- the skirt: black plum, flaring, a ragged hem that swings with her step; a violet overskirt on her left
    for i in range(10):
        t = i / 9.0
        ell(V(sw * 0.9 * t ** 2, 26.5 - 11.5 * t, 0.2), (4.3 + 4.6 * t ** 0.8, 1.6, 3.9 + 3.9 * t ** 0.8), DRESS)
    for k in range(14):                                                               # the hem: tatters of unequal length
        a = 2 * math.pi * k / 14
        long_ = 1.5 + 2.2 * ((k * 7) % 5) / 4.0
        ell(V(sw * 0.9 + math.cos(a) * 8.3, 14.6 - long_ * 0.5, 0.2 + math.sin(a) * 7.3 - sw * 0.5 * math.sin(a)), (1.7, long_, 1.2), DRESS if k % 3 else BODICE, R=h.rot_y(-(a + math.pi / 2)))
    ribbon([V(2.0, 26.5, 4.0), V(3.6 + sw * .3, 21.0, 5.9), V(4.9 + sw * .6, 17.0, 7.4), V(4.0 + sw * .8, 14.2, 7.6)], [2.6, 3.4, 3.2, 1.4], 0.6, BODICE, (0.3, 0, 1), kind='')
    ell(V(4.3 + sw * .5, 18.6, 7.7), (0.6, 0.6, 0.35), SILVER)                         # a little moon stitched on it
    # ---------------------------------------------------------------- torso: slim, a laced bodice, the belt with her things
    ell(T((0, 27.0, 0.2)), (4.4, 2.5, 3.6), DRESS, R=R)
    ell(T((0, 30.6, 0.3)), (3.6, 3.2, 3.0), BODICE, R=R)
    ell(T((0, 34.6 + b * .12, 0.8)), (4.5, 3.2, 3.5), BODICE, R=R)
    ell(T((0, 37.1, 0.0)), (5.5, 1.9, 3.0), DRESS, R=R)
    for k in range(4):                                                                # the lacing
        y = 29.4 + k * 1.7
        ell(T((0, y, 3.5 + (0.5 if k > 1 else 0.0))), (1.3, 0.3, 0.3), BONE, R=R @ rot_z(0.5 if k % 2 else -0.5))
    for a in np.linspace(0, 2 * math.pi, 15)[:-1]:                                     # the belt
        ell(T((math.cos(a) * 4.3, 27.9, 0.2 + math.sin(a) * 3.5)), (1.1, 0.8, 0.9), WINE, R=R)
    ell(T((0, 27.9, 3.9)), (1.1, 1.0, 0.4), SILVER, R=R)
    ell(T((0, 27.9, 4.2)), (0.5, 0.45, 0.3), WINE, R=R)
    ell(T((-4.6, 25.4, 1.2)), (1.6, 1.9, 1.4), CAPE, R=R)                              # a pouch on her right hip
    ell(T((-4.6, 26.7, 1.4)), (1.7, 0.6, 1.5), WINE, R=R)
    for k, x in enumerate((4.2, 5.4)):                                                 # two vials on her left: they glow
        ell(T((x, 25.2 - k * 0.5, 1.6 - k * 1.6)), (0.8, 1.5, 0.8), HEXG, R=R, kind='emit')
        ell(T((x, 27.0 - k * 0.5, 1.6 - k * 1.6)), (0.5, 0.5, 0.5), BONE, R=R)
    # neck and neckline, the pendant with the teal stone
    limb(T((0, 38.2, 0.2)), T((0, 40.2, 0.4)), 1.7, 1.6, SKIN)
    ell(T((0, 37.5, 2.3)), (2.5, 1.5, 1.4), SKIN, R=R)
    for sx in (-1, 1):
        for k in range(3):
            ell(T((sx * (2.0 - k * 0.7), 38.2 - k * 0.9, 3.2 + k * 0.25)), (0.3, 0.3, 0.25), h.GOLD, R=R, kind='emit')
    ell(T((0, 35.9, 4.0)), (0.75, 1.0, 0.5), h.TEAL, R=R, kind='emit')
    ell(T((0, 36.9, 3.95)), (0.5, 0.4, 0.35), h.GOLD, R=R, kind='emit')
    # the capelet: over the shoulders, short, ragged at the back, a silver clasp
    ell(T((0, 37.5, -1.1)), (6.4, 2.2, 3.6), CAPE, R=R)
    for sx in (-1, 1):
        ell(T((sx * 5.4, 37.0, 0.4)), (2.4, 2.6, 3.0), CAPE, R=R)
        ell(T((sx * 2.9, 38.3, 2.9)), (1.6, 1.0, 0.8), CAPE, R=R)
    for k, x in enumerate((-4.4, -2.2, 0.0, 2.2, 4.4)):
        ribbon([T((x, 38.0, -3.0)), T((x * 1.15, 34.6, -4.5 - sw * .2)), T((x * 1.2, 31.6 - (k % 2) * 1.2, -4.7 - sw * .5))], [2.0, 2.1, 1.0], 0.5, CAPE, (0, 0, -1), kind='')
    ell(T((0, 38.4, 3.3)), (0.7, 0.7, 0.4), SILVER, R=R)
    # ---------------------------------------------------------------- arms: striped sleeves, bare hands, a bracelet
    wr = p['work']; t = p['t']
    if kind == 'stir':
        a = math.tau * t
        # From her station (116, 116), the brew is centred at (138, 86.5).
        # The shaft enters the liquid there. Keep its bowl submerged.
        tip = V(5.4 * math.sin(a), 32.8, 22.0 + 5.0 * math.cos(a)) - off
        grip = T((1.1 * math.sin(a), 39.0, 10.7 + 1.5 * math.cos(a)))
        axis = (grip - tip) / np.linalg.norm(grip - tip)
    hands = {}
    for side in (-1, 1):                                                              # -1 = her right
        shoulder = T((side * 5.4, 36.6, 0.2))
        hand = T((side * 6.3, 25.6, side * sw * 2.2 + 0.6)); el = None
        if kind == 'stir':
            hand = grip + axis * (2.2 if side < 0 else -2.6) + V(side * 0.55, 0, 0)
        elif kind == 'craft':
            hand = T((-4.2 + 1.2 * wr, 27.0 + 6.5 * (1 - wr), 7.2)) if side < 0 else T((2.6, 26.6, 7.6))
        elif kind == 'counter':
            hand = T((side * 5.2, 27.6, 7.0))
        elif kind == 'cast':
            hand = T((-7.4, 26.0 + 14.5 * t, 1.0 + 5.2 * t)) if side < 0 else T((5.0, 28.4, 2.6))
            if side > 0:
                el = T((8.4, 31.0, -0.6))
        elif kind == 'talk':
            hand = T((-6.3 - 2*t, 26 + 7*t, 1 + 5*t)) if side < 0 else T((5.0, 28.0, 2.5))
        elif kind == 'listen':
            hand = T((-5.5, 27.5, 2.0)) if side < 0 else T((4.5, 29 + t, 3.0))
        elif kind == 'point':
            hand = T((-6.3 - 9*t, 26 + 9*t, 1 + 7*t)) if side < 0 else T((5, 27, 2))
        elif kind == 'inspect':
            hand = T((side * (4.7 - 2*t), 26 + 8*t, 1 + 7*t))
        elif kind == 'give':
            hand = T((side * (5.2 - 2*t), 26 + 3*t, 1 + 13*t))
        if el is None:
            mid = (shoulder + hand) / 2
            el = mid + V(side * 1.5, -1.2, -1.4)
        hands[side] = hand
        ell(shoulder, (2.5, 2.4, 2.5), CAPE, R=R)
        for a_, b_, r0 in ((shoulder, el, 1.9), (el, hand, 1.65)):
            for j in range(4):
                limb(a_ + (b_ - a_) * (j / 4.0), a_ + (b_ - a_) * ((j + 1) / 4.0), r0 - 0.06 * j, r0 - 0.06 * (j + 1), WINE if j % 2 == 0 else BONE)
        d = (hand - el) / np.linalg.norm(hand - el)
        ell(hand - d * 1.3, (1.75, 0.6, 1.75), SILVER if side > 0 else DRESS)          # bracelet / a dark cuff
        ell(hand + d * .5, (1.5, 1.7, 1.4), SKIN)
        ell(hand + d * .3 + V(side * -0.8, 0, 0.9), (.6, .9, .6), SKIN)
    if kind == 'point' and t > .3:
        limb(hands[-1], hands[-1] + V(-2.4*t, .5*t, 2.6*t), .55, .35, SKIN)
    if kind in ('inspect', 'give'):
        # A pair of silver earrings with witch-green stones held between her palms.
        center = (hands[-1] + hands[1]) * .5 + V(0, 1.6, 1.2)
        for side in (-1, 1):
            c = center + V(side * 1.4, 0, 0)
            ell(c, (.5, .7, .4), SILVER)
            ell(c + V(0, -.9, 0), (.45, .55, .4), HEXG, kind='emit')
    if kind == 'stir':
        limb(tip, grip + axis * 4.3, .58, .65, BONE)
        ell(grip + axis * 4.5, (.84, .84, .84), BONE)
    if kind == 'craft':                                                                # the little hammer, and the piece she holds: a ring with a stone
        hd = hands[-1]
        direction = V(.25, .8 - 1.3 * wr, .55); direction /= np.linalg.norm(direction)
        limb(hd - direction * 1.2, hd + direction * 5.2, .42, .42, BONE)
        ell(hd + direction * 5.6, (1.0, 1.5, 1.0), SILVER, R=h.frame_from(np.cross(direction, V(0, 0, 1)), direction))
        ell(hands[1] + V(-1.6, 0.6, 0.6), (.8, .5, .8), SILVER)
        ell(hands[1] + V(-1.6, 1.1, 0.6), (.45, .45, .45), HEXG, kind='emit')
        if wr > 0.95:
            for dx, dy in ((-1.4, 1.6), (1.2, 2.0), (0.0, 2.8)):
                ell(hands[1] + V(-1.6 + dx, 1.0 + dy, 0.8), (.3, .3, .3), HEXG, kind='emit')
    if kind == 'cast':                                                                 # a witch flame in her raised palm
        size = p['work']
        c = hands[-1] + V(0, 2.2 + 1.5 * size, 0.6)
        if size > 0.05:
            ell(c, (1.0 + 1.5 * size, 1.3 + 2.4 * size, 1.0 + 1.3 * size), HEXG, kind='emit')
            ell(c + V(0.3, 2.0 + 2.4 * size, 0), (.5 + .5 * size, 1.0 + 1.2 * size, .5), HEXG, kind='emit')
            for k in range(3):
                a = 2.1 * k + 6.0 * size
                ell(c + V(math.cos(a) * (2.4 + 2 * size), 1.0 + k * 1.6 * size + 1.5, math.sin(a) * 2.0), (.35, .35, .35), HEXG, kind='emit')
    # ---------------------------------------------------------------- head: her face, the long hair, the clips
    Rh = R @ h.rot_x(p['head'])
    Ro = Rh * 1.1  # everything on the head sits a tenth further out: a slightly bigger head reads better under the brim
    hc = T((0, 44.0 + b * .2, .5))
    ell(hc, (4.9, 5.3, 4.75), SKIN, R=Rh, kind='head')
    ell(hc + Ro @ V(0, .5, -.4), (5.3, 5.65, 5.2), HAIR, R=Rh, kind='hair', tag=3.0, clip=hair_open)
    for side in (-1, 1):
        ell(hc + Ro @ V(side * 1.9, 1.25, 4.15), (1.55, .42, .55), BROW, R=Rh @ rot_z(side * -.1))   # strong dark brows
        ell(hc + Ro @ V(side * 2.9, -1.3, 3.3), (1.0, .7, .6), h.BLUSH, R=Rh)
        # the hair drawn from the parting back over the temple, held by a silver clip
        ell(hc + Ro @ V(side * 2.7, 3.0, 3.0), (2.4, 1.3, 1.5), HAIR_L if side > 0 else HAIR, R=Rh @ rot_z(side * -.55), kind='hair', tag=side + 5.0)
        ell(hc + Ro @ V(side * 4.2, 0.6, 1.9), (1.0, 2.6, 1.6), HAIR, R=Rh, kind='hair', tag=side + 8.0)
        ell(hc + Ro @ V(side * 4.3, 2.0, 2.9), (.45, 1.1, .5), SILVER, R=Rh @ rot_z(side * -.5))
        # a long lock over each shoulder, down the chest
        lag = -sw * 0.5
        ribbon([hc + Ro @ V(side * 4.2, -0.5, 1.6), T((side * 4.8, 38.6, 2.4)), T((side * 4.3, 34.0, 3.9 + lag)), T((side * 3.7, 30.0, 3.9 + lag * 1.5)), T((side * 3.3, 27.0, 3.3 + lag * 2))],
               [1.5, 1.8, 1.7, 1.3, .6], .8, HAIR_L if side < 0 else HAIR, (side * .5, 0, 1), tag=side + 11.0)
    ell(hc + Ro @ V(0, -1.0, 4.45), (.6, .8, .5), SKIN, R=Rh)                          # nose
    ell(hc + Ro @ V(0, -2.9, 3.85), (1.15, .5, .5), LIP, R=Rh)                         # full lips
    ell(hc + Ro @ V(0, -4.4, 2.9), (1.9, 1.0, 1.7), SKIN, R=Rh)                        # chin
    for k, x in enumerate((-3.9, -2.0, 0.0, 2.0, 3.9)):                                # the hair down her back, to the waist
        lag = -sw * (0.4 + 0.15 * abs(k - 2))
        ribbon([hc + Ro @ V(x * .9, 3.2, -3.3), hc + Ro @ V(x * 1.08, -2.4, -4.5), T((x * 1.25, 35.0, -4.9 + lag)), T((x * 1.2, 29.5, -4.9 + lag * 1.6)), T((x * .95, 24.6 - (k % 2), -4.2 + lag * 2.2))],
               [2.0, 2.4, 2.4, 2.1, 1.0], .9, HAIR_L if k in (1, 4) else HAIR, (0, 0, -1), tag=float(20 + k))
    # ---------------------------------------------------------------- the hat: set back on her head so her face stays free
    hb = hc + Ro @ V(0, 4.9, -1.4)
    ell(hb + Ro @ V(0, -0.5, 0), (7.4, 0.6, 6.6), DRESS, R=Rh)                         # the brim's dark underside
    ell(hb, (8.3, 0.75, 7.3), HAT, R=Rh)
    for k in range(12):                                                                # a wavy, worn edge
        a = 2 * math.pi * k / 12
        ell(hb + Ro @ V(math.cos(a) * 7.9, 0.25 * math.sin(a * 3), math.sin(a) * 6.9), (1.5, 0.7, 1.4), HAT, R=Rh)
    for j in range(13):                                                                # the cone: it bends back and to her left, the tip droops
        tt = j / 12.0
        c = hb + Ro @ V(2.8 * tt ** 2.2, 0.8 + 14.0 * tt - 2.6 * tt ** 3, -3.6 * tt ** 2.0)
        r = 4.5 * (1 - tt) ** 1.15 + 0.45
        ell(c, (r, 1.55, r), HAT, R=Rh)
    tip = hb + Ro @ V(2.8, 12.2, -3.6)
    limb(tip, tip + V(0.8, -2.6, -0.4), .22, .2, SILVER)                               # the crescent charm
    for j in range(5):
        a = -0.6 + 3.6 * j / 4
        ell(tip + V(0.8 + math.cos(a) * 1.3, -3.9 + math.sin(a) * 1.3, -0.4), (.5, .5, .35), SILVER)
    for a in np.linspace(0, 2 * math.pi, 15)[:-1]:                                     # the band
        ell(hb + Ro @ V(math.cos(a) * 4.5, 1.5, math.sin(a) * 4.5), (1.15, 0.9, 0.9), WINE, R=Rh)
    ell(hb + Ro @ V(0.3, 1.6, 4.6), (1.15, 1.0, .4), SILVER, R=Rh)
    ell(hb + Ro @ V(0.3, 1.6, 4.9), (.55, .45, .3), WINE, R=Rh)
    ell(hb + Ro @ V(-5.6, 1.0, 2.2), (.5, .9, .5), BONE, R=Rh)                         # a toad cap grows on the brim
    ell(hb + Ro @ V(-5.6, 2.1, 2.2), (1.4, .8, 1.3), WINE, R=Rh)
    ell(hb + Ro @ V(-5.9, 2.7, 2.6), (.3, .25, .3), BONE, R=Rh)
    ell(hb + Ro @ V(5.2, 1.3, -3.4), (.9, .5, 1.3), HEXG, R=Rh @ rot_z(.5), kind='emit')   # a glowing leaf of the hag elm
    return m


def render_one(job):
    sector, index, kind, i = job; p = pose(kind, i); model = build(p, kind)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


def contact(arr, path, picks, scale=3):
    from PIL import Image
    canvas = Image.new('RGB', (len(picks) * FW * scale, 8 * FH * scale), (26, 24, 36))
    for s in range(8):
        for j, i in enumerate(picks):
            src = Image.fromarray(arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW]); tile = Image.new('RGBA', (FW, FH), (26, 24, 36, 255)); tile.alpha_composite(src)
            canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (j * FW * scale, s * FH * scale))
    canvas.save(path)


def glow_of(arr):
    """Only the pixels that shine (witch green, the teal stone): the unlit second sheet."""
    cols = {tuple(c[:3]) for mat in (HEXG, h.TEAL) for c in h.RAMPS[mat]}
    flat = arr.reshape(-1, 4)
    keep = np.array([tuple(int(v) for v in px[:3]) in cols and px[3] > 0 for px in flat])
    out = np.zeros_like(flat); out[keep] = flat[keep]
    return out.reshape(arr.shape)


def main():
    quick = len(sys.argv) > 1 and sys.argv[1] == 'quick'
    jobs = [(s, entry['start'] + i, k, i) for s in range(8) for k, entry in CLIPS.items() for i in range(entry['count'])]
    picks = [35, 37, 41, 43, 46, 47, 52, 53, 58, 59]
    if quick:
        jobs = [j for j in jobs if j[1] in picks]
    arr = np.zeros((8 * FH, FRAMES * FW, 4), dtype=np.uint8)
    print('Rendering', len(jobs), 'witch poses', flush=True)
    with mp.Pool(min(6, os.cpu_count() or 1)) as pool:
        for s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(arr, sys.argv[2], picks)
        print('quick sheet written', flush=True)
        return
    write_array(ROOT / 'characters/witch.png', arr)
    write_array(ROOT / 'characters/witch_glow.png', glow_of(arr))
    (ROOT.parent / 'data/witch_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': FRAMES, 'rows': 8, 'clips': CLIPS}, indent=2) + '\n')
    if len(sys.argv) > 1:
        contact(arr, sys.argv[1], picks)
    print('Witch sheet, glow and rig written', flush=True)


if __name__ == '__main__':
    main()
