"""Boss 2: Morwenna, die Spiegelhexe (docs/enemies/boss_mora.md). Eight true directions, three looks (one per phase of the fight).

    py -3 tools/art_morwenna.py [contact_sheet.png]     writes assets/enemies/morwenna/morwenna_{0,1,2}.png, the three _glow sheets and data/morwenna_rig.json
    py -3 tools/art_morwenna.py quick out.png [phase]   a few poses of one look (default 0) for a fast check, writes nothing else
    py -3 tools/art_morwenna.py clip <name> out.png [phase]   every frame of one clip in all eight directions

Built from ellipsoids with the heroine's renderer, on the proportions of the tower's witch (tools/art_witch.py) so the two read as the same kind.
A bent, wiry woman in what was once a grand witch's silk: the hem has gone to moss, resin and black void tendrils that drag behind her; a mossy hump
with shelf fungi sits on her shoulders (the tree is growing into her). A torn pointed hat with dry twigs. Her face is a dirty shard of mirror; two violet
curse fires burn behind it. Two rusted ceremonial sickles of curse silver.
Looks: 0 = the mirror is whole but for a hairline; 1 = a great crack splits it and violet light leaks out, more tendrils; 2 = most of the glass is gone,
the void face under it shows one big burning eye, magenta veins, the most tendrils.
Clips (frames): idle 4, run 6, slash_a 4, slash_b 4, slash_c 6 (frame 1 is the held wind-up of the scissor cut), cast 5 (the sickle rammed into the
ground, frame 3 = the strike), leap 4, leech 4 (kneeling, drinking from the tree), scream 4, down 6 (she breaks down; backwards = she rises)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 96, 96, 80
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
(SILK, SILK_D, FLESH, MOSS, RESIN, MIRROR, FSILVER, RUST, HATM, TWIG, VIO, MAG, HEXG, ASH) = range(BASE, BASE + 14)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['1c1428', '35264a', '57446c', '85729a'],  # the old silk: a faded, dusty lilac
    ['0e0a18', '1c1430', '2e2248', '463664'],  # its deep folds and the bodice
    ['040208', '0b0614', '160d28', '2a1c52'],  # void flesh (the shadow creatures' black)
    ['132a1c', '20422a', '386238', '5e8c4c'],  # moss
    ['46220a', '864812', 'c47c1c', 'f0c468'],  # tree resin, amber
    ['33455a', '6a8296', 'a6c0cc', 'ecf8fb'],  # the mirror shard
    ['2a3242', '525e74', '8e9fb4', 'dae6f2'],  # curse silver
    ['34160e', '602a16', '8e4a26', 'ba7440'],  # rust
    ['090612', '130e26', '21183c', '342856'],  # the hat
    ['181010', '2e201a', '4a362a', '6a523c'],  # dry twigs
    ['521896', '9438ee', 'cf7aff', 'f6dcff'],  # the curse fires: violet
    ['76085a', 'cc1e9c', 'ff58d0', 'ffd0f4'],  # void veins: magenta
    ['2e6a2a', '4a9a3a', 'a8ff6a', 'eaffc4'],  # witch green: the ritual's light in the fungi
    ['464254', '76728a', 'a6a2b4', 'd6d2dc'],  # ashen hair
]]
GLOWING = (VIO, MAG, HEXG)
V = lambda *x: np.array(x, float)
LOOKS = 3
CLIPS = {'idle': {'start': 0, 'count': 4, 'fps': 5}, 'run': {'start': 4, 'count': 6, 'fps': 13}, 'slash_a': {'start': 10, 'count': 4, 'fps': 14, 'strike': 1},
         'slash_b': {'start': 14, 'count': 4, 'fps': 14, 'strike': 1}, 'slash_c': {'start': 18, 'count': 6, 'fps': 13, 'strike': 3, 'hold': 1},
         'cast': {'start': 24, 'count': 5, 'fps': 10, 'strike': 3}, 'leap': {'start': 29, 'count': 4, 'fps': 9}, 'leech': {'start': 33, 'count': 4, 'fps': 6},
         'scream': {'start': 37, 'count': 4, 'fps': 7}, 'down': {'start': 41, 'count': 6, 'fps': 8}}
FRAMES = 47


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def unit(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-6)


def pose(kind, i):
    """Hands and blade directions are in the torso's own frame (they follow its lean and twist). x = her left, y = up, z = forward."""
    p = dict(feet=((3.2, 1.0, 0), (-3.2, -1.4, 0)), crouch=3.0, pz=0.0, lean=.42, twist=0.0, head=-.12, breath=0.0, tent=0.0, pitch=0.0, dy=0.0, sway=0.0,
             hr=(-7.6, 23.5, 3.5), hl=(7.6, 23.5, 3.0), br=(-.25, -.75, .6), bl=(.25, -.75, .6), kr=(0, .3, 1), kl=(0, .3, 1))
    if kind == 'idle':
        b = [0, .5, 1, .5][i]
        p.update(breath=b, tent=i / 4.0, head=-.12 + .03 * b, sway=[0, 0, .5, 0][i], hr=(-7.6, 23.5 + .5 * b, 3.5), hl=(7.6, 23.5 + .5 * b, 3.0))
    elif kind == 'run':
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        p.update(feet=((3.0, 5.4 * s, 2.6 * max(c, 0)), (-3.0, -5.4 * s, 2.6 * max(-c, 0))), crouch=5.0, pz=1.2, lean=.74, head=-.42, twist=.12 * s, tent=i / 6.0,
                 hr=(-8.4, 25.0 + s, -4.5 + 2.0 * s), hl=(8.4, 25.0 - s, -4.5 - 2.0 * s), br=(-.3, .1, -1), bl=(.3, .1, -1), kr=(0, 1, .2), kl=(0, 1, .2), breath=.5 + .5 * c)
    elif kind == 'slash_a':                                                            # the right sickle: from high behind, across to her left
        p.update([dict(twist=-.75, lean=.3, feet=((3.4, -1.5, 0), (-3.4, 3.0, 0)), hr=(-9.5, 38.0, -4.0), br=(-.5, .7, -.5), kr=(0, .2, 1), hl=(7.0, 27.0, 5.0), bl=(.3, -.3, .9)),
                  dict(twist=.25, lean=.6, pz=2.0, feet=((3.4, -2.5, 0), (-3.4, 6.0, 0)), hr=(1.5, 29.0, 12.5), br=(.75, -.2, .6), kr=(.6, -.6, .3), hl=(8.0, 26.0, 0.0), bl=(.5, -.3, -.6)),
                  dict(twist=.8, lean=.68, pz=2.6, feet=((3.4, -3.0, 0), (-3.4, 7.0, 0)), hr=(9.5, 23.0, 5.0), br=(.9, -.4, -.2), kr=(.2, -.9, -.3), hl=(8.5, 27.0, -3.0), bl=(.5, 0, -.9)),
                  dict(twist=.45, lean=.52, pz=1.4, feet=((3.3, -1.5, 0), (-3.3, 4.0, 0)), hr=(5.0, 23.0, 6.0), br=(.6, -.6, .4), hl=(8.0, 25.0, 0.0), bl=(.4, -.5, -.4))][i])
        p['tent'] = .2 * i
    elif kind == 'slash_b':                                                            # the left sickle, a backhand the other way
        p.update([dict(twist=.75, lean=.3, feet=((3.4, 3.0, 0), (-3.4, -1.5, 0)), hl=(9.5, 38.0, -4.0), bl=(.5, .7, -.5), kl=(0, .2, 1), hr=(-7.0, 27.0, 5.0), br=(-.3, -.3, .9)),
                  dict(twist=-.25, lean=.6, pz=2.0, feet=((3.4, 6.0, 0), (-3.4, -2.5, 0)), hl=(-1.5, 29.0, 12.5), bl=(-.75, -.2, .6), kl=(-.6, -.6, .3), hr=(-8.0, 26.0, 0.0), br=(-.5, -.3, -.6)),
                  dict(twist=-.8, lean=.68, pz=2.6, feet=((3.4, 7.0, 0), (-3.4, -3.0, 0)), hl=(-9.5, 23.0, 5.0), bl=(-.9, -.4, -.2), kl=(-.2, -.9, -.3), hr=(-8.5, 27.0, -3.0), br=(-.5, 0, -.9)),
                  dict(twist=-.45, lean=.52, pz=1.4, feet=((3.3, 4.0, 0), (-3.3, -1.5, 0)), hl=(-5.0, 23.0, 6.0), bl=(-.6, -.6, .4), hr=(-8.0, 25.0, 0.0), br=(-.4, -.5, -.4))][i])
        p['tent'] = .2 * i
    elif kind == 'slash_c':                                                            # the scissor cut: both arms flung wide, held, then they cross
        wide = dict(lean=.12, head=.1, crouch=4.5, feet=((4.4, 0, 0), (-4.4, 0, 0)), hr=(-13.0, 34.0, -1.0), hl=(13.0, 34.0, -1.0), br=(-.9, .35, .2), bl=(.9, .35, .2), kr=(0, .3, 1), kl=(0, .3, 1))
        p.update([dict(wide, lean=.3, hr=(-10.0, 30.0, 0.0), hl=(10.0, 30.0, 0.0)),
                  wide,
                  dict(lean=.5, pz=1.5, crouch=5.0, feet=((4.0, 3.5, 0), (-4.0, -2.5, 0)), hr=(-8.5, 30.0, 9.0), hl=(8.5, 30.0, 9.0), br=(-.5, 0, .85), bl=(.5, 0, .85), kr=(1, 0, .2), kl=(-1, 0, .2)),
                  dict(lean=.78, pz=3.0, crouch=6.0, head=-.5, feet=((4.0, 6.0, 0), (-4.0, -3.5, 0)), hr=(5.5, 27.0, 11.0), hl=(-5.5, 29.0, 11.5), br=(.85, -.1, .5), bl=(-.85, -.1, .5), kr=(.3, -.2, -1), kl=(-.3, -.2, -1)),
                  dict(lean=.82, pz=3.0, crouch=6.5, head=-.5, feet=((4.0, 6.0, 0), (-4.0, -3.5, 0)), hr=(8.5, 24.0, 6.0), hl=(-8.5, 25.0, 6.5), br=(.9, -.3, -.2), bl=(-.9, -.3, -.2), kr=(.2, -.5, -.8), kl=(-.2, -.5, -.8)),
                  dict(lean=.56, pz=1.5, crouch=4.0, feet=((3.6, 3.0, 0), (-3.6, -2.0, 0)), hr=(2.0, 24.0, 6.0), hl=(-2.0, 25.0, 6.5), br=(.5, -.7, .3), bl=(-.5, -.7, .3))][i])
        p['tent'] = .15 * i
    elif kind == 'cast':                                                               # the right sickle goes up, then into the ground
        p.update([dict(lean=.2, hr=(-8.0, 34.0, 2.0), br=(-.2, .9, .2), kr=(0, .2, 1)),
                  dict(lean=.02, head=.12, crouch=2.0, hr=(-6.5, 47.0, 0.0), br=(0, 1, .15), kr=(0, .2, 1), hl=(8.5, 28.0, 4.0), bl=(.5, -.2, .8)),
                  dict(lean=.0, head=.16, crouch=2.0, hr=(-5.5, 48.5, -1.0), br=(.1, 1, -.1), kr=(0, .2, 1), hl=(9.0, 30.0, 4.0), bl=(.6, 0, .7)),
                  dict(lean=1.02, pz=2.0, head=-.6, crouch=10.0, feet=((4.4, 4.5, 0), (-4.4, -4.0, 0)), hr=(-3.0, 22.0, 8.5), br=(.05, -.98, .1), kr=(0, .1, 1), hl=(9.0, 25.0, -2.0), bl=(.5, -.3, -.8)),
                  dict(lean=.96, pz=2.0, head=-.5, crouch=9.5, feet=((4.4, 4.5, 0), (-4.4, -4.0, 0)), hr=(-3.0, 22.6, 8.5), br=(.05, -.98, .1), kr=(0, .1, 1), hl=(9.0, 26.0, -2.0), bl=(.5, -.3, -.8))][i])
        p['tent'] = .2 * i
    elif kind == 'leap':                                                               # the backwards spring, the sickles flung out
        p.update([dict(crouch=10.0, lean=.8, head=-.4, feet=((3.8, 2.0, 0), (-3.8, -1.0, 0)), hr=(-7.5, 22.0, 6.0), hl=(7.5, 22.0, 6.0)),
                  dict(crouch=5.0, lean=-.1, head=.2, dy=7.0, pitch=-.25, feet=((3.0, 3.0, 2.0), (-3.0, 5.5, 4.0)), hr=(-13.0, 33.0, 3.0), hl=(13.0, 33.0, 3.0), br=(-.8, .4, .5), bl=(.8, .4, .5)),
                  dict(crouch=7.0, lean=.2, head=.0, dy=9.0, pitch=-.4, feet=((3.0, 5.0, 4.0), (-3.0, 2.0, 2.5)), hr=(-9.0, 30.0, 11.0), hl=(9.0, 30.0, 11.0), br=(-.4, -.2, .9), bl=(.4, -.2, .9)),
                  dict(crouch=8.5, lean=.66, head=-.3, feet=((4.2, -2.0, 0), (-4.2, 2.5, 0)), hr=(-9.0, 23.0, 2.0), hl=(9.0, 23.0, 2.0))][i])
        p['tent'] = .25 * i
    elif kind == 'leech':                                                              # on her knees, arms up to the tree, head thrown back
        w = [0, .5, 1, .5][i]
        p.update(crouch=11.0, lean=-.16 - .05 * w, head=.34 + .08 * w, feet=((3.6, -5.0, 0), (-3.6, -6.5, 0)), breath=w, tent=i / 4.0,
                 hr=(-7.0, 43.0 + 1.5 * w, 6.0), hl=(7.0, 44.0 + 1.5 * w, 6.0), br=(-.5, .85, .1), bl=(.5, .85, .1), kr=(1, 0, .3), kl=(-1, 0, .3))
    elif kind == 'scream':                                                             # she claws at the mask, then throws the scream out
        p.update([dict(lean=.62, head=-.3, hr=(-2.6, 40.0, 5.8), hl=(2.6, 40.0, 5.8), br=(-.7, .6, .2), bl=(.7, .6, .2)),
                  dict(lean=.76, head=-.5, crouch=6.0, sway=1.0, hr=(-2.8, 39.0, 6.2), hl=(2.8, 39.0, 6.2), br=(-.8, .5, .2), bl=(.8, .5, .2)),
                  dict(lean=-.2, head=.42, crouch=2.0, feet=((4.6, 0, 0), (-4.6, 0, 0)), hr=(-13.0, 30.0, -3.0), hl=(13.0, 30.0, -3.0), br=(-.9, -.3, -.2), bl=(.9, -.3, -.2)),
                  dict(lean=-.26, head=.48, crouch=2.0, sway=-1.0, feet=((4.6, 0, 0), (-4.6, 0, 0)), hr=(-13.5, 31.0, -4.0), hl=(13.5, 31.0, -4.0), br=(-.9, -.2, -.3), bl=(.9, -.2, -.3))][i])
        p['tent'] = .25 * i
    elif kind == 'down':                                                               # she breaks down: stagger, knees, on her hands, flat
        p.update([dict(lean=.7, head=-.4, crouch=5.0, sway=1.0),
                  dict(lean=.9, head=-.5, crouch=9.0, feet=((3.6, -3.0, 0), (-3.6, -5.0, 0)), hr=(-7.5, 21.0, 7.0), hl=(7.5, 21.0, 7.0)),
                  dict(lean=1.1, head=-.5, crouch=12.0, feet=((3.6, -5.0, 0), (-3.6, -6.5, 0)), hr=(-7.0, 20.0, 10.0), hl=(7.0, 20.0, 10.0), br=(-.6, -.2, .7), bl=(.6, -.2, .7)),
                  dict(lean=.5, head=-.2, crouch=12.5, pitch=.62, dy=1.0, feet=((3.6, -5.0, 0), (-3.6, -6.5, 0)), hr=(-8.5, 26.0, 9.0), hl=(8.5, 26.0, 9.0), br=(-.7, .1, .7), bl=(.7, .1, .7)),
                  dict(lean=.22, head=.1, crouch=12.5, pitch=1.06, dy=2.2, feet=((3.6, -5.0, 0), (-3.6, -6.5, 0)), hr=(-10.0, 30.0, 6.0), hl=(9.0, 33.0, 5.0), br=(-.8, .5, .3), bl=(.6, .7, .3)),
                  dict(lean=.16, head=.2, crouch=12.5, pitch=1.2, dy=2.6, feet=((3.6, -5.0, 0), (-3.6, -6.5, 0)), hr=(-10.5, 30.0, 5.0), hl=(9.5, 34.0, 4.0), br=(-.8, .5, .3), bl=(.6, .7, .3))][i])
        p['tent'] = .2 * i
    return p


def legs_of(p):
    """Like h.pose_legs, with a crouch: the hips sink `crouch` below standing height (and further if the stance needs it)."""
    pz = p['pz']
    hips = [V(2.5, 0.0, pz + 0.2), V(-2.5, 0.0, pz + 0.2)]
    ankles = [V(f[0], 2.5 + f[2], f[1]) for f in p['feet']]
    hy = 24.0 - p['crouch']
    for hip, ank in zip(hips, ankles):
        horiz2 = (ank[0] - hip[0]) ** 2 + (ank[2] - hip[2]) ** 2
        hy = min(hy, ank[1] + math.sqrt(max(21.2 ** 2 - horiz2, 1.0)))
    out = []
    for hip, ank in zip(hips, ankles):
        hip = hip + V(0.0, hy, 0.0)
        knee, end = h.ik2(hip, ank, 11.5, 10.0, (0.0, 0.2, 1.0))
        out.append((hip, knee, end))
    return out, hy - 24.0


def sickle(m, hand, d, hook, look):
    """A ceremonial sickle held at `hand`: the grip runs along `d`, the blade leaves it and curls towards `hook`."""
    d = unit(d); hook = unit(np.asarray(hook, float) - d * (np.asarray(hook, float) @ d))
    m.limb(hand - d * 2.6, hand + d * 2.4, .62, .58, TWIG)
    m.ell(hand - d * 2.9, (.8, .8, .8), RUST)                                           # the pommel
    m.ell(hand + d * 2.6, (.95, .95, .95), FSILVER)                                     # the collar
    base = hand + d * 2.8; radius = 6.6
    n = 15
    for k in range(n + 1):
        a = 2.75 * k / n
        c = base + d * (radius * math.sin(a)) + hook * (radius * (1 - math.cos(a)))
        r = 1.18 * (1 - (k / n) ** 1.6) + .34
        mat = RUST if k in (3, 4, 9) else FSILVER
        m.ell(c, (r, r, .5), mat, R=h.frame_from(np.cross(d, hook), d))
    if look >= 1:                                                                       # the curse wakes in the edge
        for k in (5, 8, 11):
            a = 2.75 * k / n
            m.ell(base + d * (radius * math.sin(a)) * 1.06 + hook * (radius * (1 - math.cos(a))) * 1.06, (.38, .38, .38), VIO, kind='emit')


def build(p, look):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = legs_of(p); off = V(p['sway'] * .5, drop, p['pz'])
    ph = 2 * math.pi * p['tent']
    # ---------------------------------------------------------------- legs: thin, wrapped in dark rags, bare black feet
    for hip, knee, ankle in legs:
        limb(hip, knee, 2.3, 1.8, SILK_D)
        limb(knee, ankle, 1.75, 1.35, FLESH)
        for j in (2, 4):
            limb(knee + (ankle - knee) * (j / 6.0), knee + (ankle - knee) * ((j + .7) / 6.0), 1.75, 1.7, SILK)
        ell(ankle + V(0, -1.2, 1.4), (1.7, 1.2, 2.9), FLESH)
        ell(ankle + V(0, -.2, -.2), (1.6, 1.7, 1.7), FLESH)
    m.off = off
    R = h.rot_y(p['twist']) @ h.rot_x(p['lean']); b = p['breath']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    # ---------------------------------------------------------------- the robe: silk gone to rags; its hem is moss, resin and the void
    for i in range(9):
        t = i / 8.0
        ell(V(0, 26.5 - 12.5 * t, .2 - 1.2 * t), (4.2 + 4.0 * t ** .8, 1.7, 3.8 + 3.6 * t ** .8), SILK if i < 6 else SILK_D)
    for k in range(13):                                                                 # the tatters
        a = 2 * math.pi * k / 13
        long_ = 2.0 + 3.6 * ((k * 5) % 7) / 6.0
        mat = (SILK, SILK_D, MOSS, SILK, FLESH, SILK_D, MOSS)[k % 7]
        wob = .5 * math.sin(ph + k * 1.7)
        ell(V(math.cos(a) * 7.6 + wob, 13.6 - long_ * .5, -1.0 + math.sin(a) * 6.8), (1.7, long_, 1.1), mat, R=h.rot_y(-(a + math.pi / 2)))
    for k in range(4):                                                                  # drops of resin on the hem
        a = 1.1 + 1.5 * k
        ell(V(math.cos(a) * 7.2, 12.4 - (k % 2), -1.0 + math.sin(a) * 6.4), (.8, 1.2, .8), RESIN)
    # the void tendrils that hold her to the ground: they drag behind and writhe
    for k in range(3 + 2 * look):
        a = math.pi * (1.5 + (k - (1 + look)) * .34)
        out = 9.0 + 2.6 * (k % 3) + 2.0 * look
        wig = math.sin(ph + k * 2.1); wig2 = math.cos(ph * 1.0 + k * 1.3)
        p0 = V(math.cos(a) * 4.0, 15.0, math.sin(a) * 4.0 - 1.0)
        p1 = V(math.cos(a) * (out * .55) + wig * 1.2, 6.5 + wig2, math.sin(a) * out * .55 - 1.0)
        p2 = V(math.cos(a) * out + wig2 * 1.6, 1.4, math.sin(a) * out - 1.0 + wig)
        p3 = V(math.cos(a) * (out + 3.5) + wig * 2.2, 2.2 + 1.6 * max(wig, 0), math.sin(a) * (out + 3.5) - 1.0 + wig2 * 1.5)
        for q0, q1, r0, r1 in ((p0, p1, 1.6, 1.3), (p1, p2, 1.3, 1.0), (p2, p3, 1.0, .5)):
            limb(q0 - off, q1 - off, r0, r1, FLESH)
        ell(p3 - off, (.5, .5, .5), MAG, kind='emit')
        if look >= 1:
            ell((p1 + p2) / 2 - off + V(0, .9, 0), (.4, .4, .4), MAG, kind='emit')
    # ---------------------------------------------------------------- torso: narrow, bent, a bodice with what is left of its silver
    ell(T((0, 27.2, .2)), (4.2, 2.6, 3.5), SILK_D, R=R)
    ell(T((0, 30.8, .3)), (3.4, 3.3, 2.9), SILK_D, R=R)
    ell(T((0, 34.8 + b * .15, .7)), (4.3, 3.2, 3.4), SILK, R=R)
    ell(T((0, 37.3, 0)), (5.3, 1.9, 3.0), SILK_D, R=R)
    for k in range(3):
        ell(T((0, 30.0 + k * 1.9, 3.4)), (1.2, .3, .3), FSILVER, R=R @ rot_z(.5 if k % 2 else -.5))
    for a in np.linspace(0, 2 * math.pi, 13)[:-1]:                                      # a rope of root for a belt
        ell(T((math.cos(a) * 4.2, 27.9, .2 + math.sin(a) * 3.4)), (1.0, .7, .9), TWIG, R=R)
    ell(T((0, 38.4, 2.4)), (2.2, 1.3, 1.2), FLESH, R=R)
    limb(T((0, 38.2, .4)), T((0, 40.6, 1.2)), 1.5, 1.4, FLESH)
    # the hump: the tree grows into her. Moss, a knot of root, shelf fungi with the ritual's light
    ell(T((0, 37.6, -3.4)), (6.2, 3.6, 3.8), MOSS, R=R)
    ell(T((-2.6, 39.6, -4.2)), (3.2, 2.4, 2.6), MOSS, R=R)
    ell(T((2.8, 38.6, -4.6)), (2.6, 2.0, 2.4), TWIG, R=R)
    for k, (x, y, z) in enumerate(((-4.6, 39.4, -5.0), (3.8, 40.2, -5.4), (0.2, 41.4, -5.6))):
        ell(T((x, y, z)), (1.5, .5, 1.3), TWIG, R=R)
        ell(T((x, y - .5, z - .3)), (1.2, .35, 1.0), HEXG, R=R, kind='emit')
    for k, x in enumerate((-3.6, -1.2, 1.2, 3.6)):                                      # the torn back of the robe
        ribbon([T((x, 36.0, -4.6)), T((x * 1.2, 31.0, -6.2)), T((x * 1.3 + .6 * math.sin(ph + k), 26.0 - (k % 2) * 1.6, -6.6))], [2.0, 2.0, .9], .5, SILK if k % 2 else SILK_D, (0, 0, -1), kind='')
    # ---------------------------------------------------------------- arms: sinew in rags, void-black hands, the two sickles
    for side, hk, bk, kk in ((-1, 'hr', 'br', 'kr'), (1, 'hl', 'bl', 'kl')):
        shoulder = T((side * 5.3, 36.8, .2))
        want = T(p[hk])
        el, hand = h.ik2(shoulder, want, 8.4, 8.2, R @ V(side * .7, -.5, -.8))
        ell(shoulder, (2.3, 2.2, 2.3), SILK, R=R)
        limb(shoulder, el, 1.75, 1.45, SILK_D)
        limb(el, hand, 1.4, 1.15, FLESH)
        for j in (1, 3):
            limb(el + (hand - el) * (j / 5.0), el + (hand - el) * ((j + .7) / 5.0), 1.45, 1.35, SILK)
        ribbon([el, el + V(side * .6, -3.2, -.8), el + V(side * 1.0 + .5 * math.sin(ph + side), -6.0, -1.4)], [1.5, 1.3, .5], .45, SILK, (side, 0, 0), kind='')   # a rag hangs from the elbow
        ell(hand, (1.45, 1.5, 1.4), FLESH)
        sickle(m, hand, R @ np.asarray(p[bk], float), R @ np.asarray(p[kk], float), look)
    # ---------------------------------------------------------------- the head: ashen hair, the mirror, the fires behind it
    Rh = R @ h.rot_x(p['head'] - p['lean'] * .45)
    hc = T((0, 44.2 + b * .2, 1.4))
    ell(hc, (4.6, 5.0, 4.5), FLESH, R=Rh)
    ell(hc + Rh @ V(0, .6, -.7), (5.0, 5.3, 4.9), ASH, R=Rh, kind='hair', tag=3.0, clip=lambda q: (q[..., 2] < .15) | (q[..., 1] > .55))
    for k, x in enumerate((-4.4, -2.6, 2.6, 4.4)):                                      # lank strands beside the face and down the back
        lag = .8 * math.sin(ph + k)
        ribbon([hc + Rh @ V(x, 1.0, 1.4 - abs(x) * .3), hc + Rh @ V(x * 1.1, -4.6, 1.8), T((x * 1.15 + lag * .4, 34.0, 3.0 - abs(x) * .4)), T((x * 1.0 + lag, 29.0 - (k % 2) * 2, 2.6))],
               [1.3, 1.4, 1.1, .4], .6, ASH, (x, 0, 1), tag=float(8 + k))
    for k, x in enumerate((-3.0, 0.0, 3.0)):
        ribbon([hc + Rh @ V(x, 2.0, -3.6), hc + Rh @ V(x * 1.1, -3.4, -4.6), T((x * 1.2, 35.0, -7.4)), T((x * 1.1 + .7 * math.sin(ph + k), 30.0, -7.6))], [1.8, 2.0, 1.6, .6], .7, ASH, (0, 0, -1), tag=float(14 + k))
    face = hc + Rh @ V(0, -.5, 4.0)
    if look < 2:
        ell(face, (3.7, 4.7, .75), MIRROR, R=Rh)
        ell(face + Rh @ V(-1.2, 1.6, .5), (1.2, 2.0, .3), MIRROR, R=Rh @ rot_z(.5), kind='emit')            # what it reflects: a pale streak
        for sx in (-1, 1):                                                              # chipped corners
            ell(face + Rh @ V(sx * 3.0, -3.8, .3), (1.2, 1.1, .5), FLESH, R=Rh)
        ell(face + Rh @ V(2.6, 4.0, .3), (1.3, 1.0, .5), FLESH, R=Rh)
        for sx in (-1, 1):                                                              # the two fires
            ell(face + Rh @ V(sx * 1.6, .7, .7), (.75, .6, .4), VIO, R=Rh, kind='emit')
        crack = ((-.6, 3.6), (.2, 2.0), (-.4, .6), (.6, -1.0), (.1, -2.8), (.8, -4.2))
        for a_, b_ in zip(crack[:-1], crack[1:]) if look == 1 else zip(crack[3:-1], crack[4:]):
            limb(face + Rh @ V(a_[0], a_[1], .8), face + Rh @ V(b_[0], b_[1], .8), .42 if look == 1 else .3, .42 if look == 1 else .3, VIO if look == 1 else FLESH, kind='emit' if look == 1 else '')
        if look == 1:
            limb(face + Rh @ V(.2, 2.0, .8), face + Rh @ V(2.6, 2.8, .8), .32, .3, FLESH)
            limb(face + Rh @ V(-.4, .6, .8), face + Rh @ V(-3.0, -.4, .8), .32, .3, FLESH)
    else:                                                                               # the hour of the witch: a last splinter over her right eye, the void looks out
        ell(face + Rh @ V(-1.9, .9, .1), (2.0, 3.2, .75), MIRROR, R=Rh @ rot_z(-.25))
        ell(face + Rh @ V(-2.3, 2.0, .6), (.7, 1.3, .3), MIRROR, R=Rh @ rot_z(.4), kind='emit')
        ell(face + Rh @ V(-1.7, .7, .8), (.6, .5, .35), VIO, R=Rh, kind='emit')
        ell(face + Rh @ V(1.7, .8, .5), (1.25, 1.05, .5), VIO, R=Rh, kind='emit')        # the bare eye, wide
        ell(face + Rh @ V(1.7, .8, .9), (.45, .5, .3), MAG, R=Rh, kind='emit')
        for q in ((2.6, -1.0), (3.0, -2.4), (1.2, -2.6), (.4, -3.8), (2.2, 2.6)):         # veins over the bare cheek
            ell(face + Rh @ V(q[0], q[1], .2), (.36, .36, .3), MAG, R=Rh, kind='emit')
        limb(face + Rh @ V(-.6, -2.2, .3), face + Rh @ V(1.6, -2.8, .3), .4, .35, FLESH)
    # ---------------------------------------------------------------- the hat: torn, bent, dry twigs in the band
    hb = hc + Rh @ V(0, 4.4, -1.0)
    ell(hb, (8.0, .75, 7.0), HATM, R=Rh)
    for k in range(11):
        if k in (2, 7):
            continue                                                                    # bites out of the brim
        a = 2 * math.pi * k / 11
        ell(hb + Rh @ V(math.cos(a) * 7.7, .3 * math.sin(a * 3) - .2, math.sin(a) * 6.7), (1.6, .7, 1.5), HATM, R=Rh)
    for j in range(12):
        tt = j / 11.0
        c = hb + Rh @ V(-3.4 * tt ** 2.0, .8 + 12.5 * tt - 4.4 * tt ** 3, -4.4 * tt ** 1.8)
        r = 4.3 * (1 - tt) ** 1.1 + .45
        ell(c, (r, 1.5, r), HATM, R=Rh)
    for a in np.linspace(0, 2 * math.pi, 13)[:-1]:
        ell(hb + Rh @ V(math.cos(a) * 4.4, 1.5, math.sin(a) * 4.4), (1.1, .8, .9), TWIG, R=Rh)
    for k, (a, tilt, length) in enumerate(((.5, .7, 7.5), (1.4, .35, 9.5), (2.5, .8, 6.5), (3.6, .5, 8.5), (5.2, .9, 6.0))):   # the dry twigs
        root = hb + Rh @ V(math.cos(a) * 4.6, 1.8, math.sin(a) * 4.6)
        d = Rh @ unit(V(math.cos(a) * tilt, 1.0, math.sin(a) * tilt))
        limb(root, root + d * length, .5, .28, TWIG)
        side_d = Rh @ unit(V(math.cos(a + 1.2), .7, math.sin(a + 1.2)))
        limb(root + d * length * .55, root + d * length * .55 + side_d * 3.0, .34, .24, TWIG)
        if k in (1, 3):
            ell(root + d * length, (.42, .42, .42), HEXG, kind='emit')
    # ---------------------------------------------------------------- the whole body: a pitch about the feet (she falls), a lift (she springs)
    if p['pitch'] != 0.0 or p['dy'] != 0.0:
        Rp = h.rot_x(p['pitch']); piv = V(0, 3.0, 0)
        for q in m.prims:
            q.c = Rp @ (q.c - piv) + piv + V(0, p['dy'], 0)
            q.R = Rp @ q.R
    return m


def render_one(job):
    look, sector, index, kind, i = job
    model = build(pose(kind, i), look)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return look, sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


def glow_of(arr):
    cols = {tuple(c[:3]) for mat in GLOWING for c in h.RAMPS[mat]}
    flat = arr.reshape(-1, 4)
    packed = (flat[:, 0].astype(np.int64) << 16) | (flat[:, 1].astype(np.int64) << 8) | flat[:, 2].astype(np.int64)
    keys = np.array([(c[0] << 16) | (c[1] << 8) | c[2] for c in cols], dtype=np.int64)
    keep = np.isin(packed, keys) & (flat[:, 3] > 0)
    out = np.zeros_like(flat); out[keep] = flat[keep]
    return out.reshape(arr.shape)


def contact(sheets, path, picks, scale=3, sectors=range(8)):
    from PIL import Image
    sectors = list(sectors)
    canvas = Image.new('RGB', (len(picks) * FW * scale, len(sectors) * len(sheets) * FH * scale), (30, 40, 38))
    for n, arr in enumerate(sheets):
        for r, s in enumerate(sectors):
            for j, i in enumerate(picks):
                src = Image.fromarray(arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW]); tile = Image.new('RGBA', (FW, FH), (30, 40, 38, 255)); tile.alpha_composite(src)
                canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (j * FW * scale, (n * len(sectors) + r) * FH * scale))
    canvas.save(path)


def render(jobs, looks):
    sheets = {look: np.zeros((8 * FH, FRAMES * FW, 4), dtype=np.uint8) for look in looks}
    print('Rendering', len(jobs), 'poses of Morwenna', flush=True)
    with mp.Pool(min(8, os.cpu_count() or 1)) as pool:
        for look, s, i, data in pool.imap_unordered(render_one, jobs, chunksize=4):
            sheets[look][s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    return sheets


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    every = [(k, i) for k, entry in CLIPS.items() for i in range(entry['count'])]
    if mode == 'quick':
        look = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        picks = [0, 5, 10, 11, 19, 21, 26, 27, 30, 34, 39, 44]
        jobs = [(look, s, CLIPS[k]['start'] + i, k, i) for s in (0, 1, 2, 3, 6) for k, i in every if CLIPS[k]['start'] + i in picks]
        contact([render(jobs, [look])[look]], sys.argv[2], picks, 3, (0, 1, 2, 3, 6))
        return
    if mode == 'clip':
        look = int(sys.argv[4]) if len(sys.argv) > 4 else 0
        entry = CLIPS[sys.argv[2]]
        jobs = [(look, s, entry['start'] + i, sys.argv[2], i) for s in range(8) for i in range(entry['count'])]
        contact([render(jobs, [look])[look]], sys.argv[3], [entry['start'] + i for i in range(entry['count'])], 3)
        return
    jobs = [(look, s, CLIPS[k]['start'] + i, k, i) for look in range(LOOKS) for s in range(8) for k, i in every]
    sheets = render(jobs, range(LOOKS))
    out = ROOT / 'enemies/morwenna'; out.mkdir(parents=True, exist_ok=True)
    for look in range(LOOKS):
        write_array(out / ('morwenna_%d.png' % look), sheets[look])
        write_array(out / ('morwenna_%d_glow.png' % look), glow_of(sheets[look]))
    (ROOT.parent / 'data/morwenna_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': FRAMES, 'rows': 8, 'looks': LOOKS, 'clips': CLIPS}, indent=2) + '\n')
    if mode:
        contact([sheets[0], sheets[2]], mode, [0, 5, 11, 21, 27, 34, 39, 45], 2, (0, 2, 6))
    print('Morwenna: three looks, glow sheets and rig written', flush=True)


if __name__ == '__main__':
    main()
