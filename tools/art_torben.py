"""Torben, Shadowspore's smith. Eight true directions, 18 clips (docs/characters/torben.md, docs/torben_konzept.md section 3).

    python3 tools/art_torben.py [contact_sheet.png]   writes assets/characters/torben.png, torben_glow.png and data/torben_rig.json
    python3 tools/art_torben.py quick out.png         renders a handful of poses for a fast look, writes nothing else
    python3 tools/art_torben.py compare out.png       Torben next to Ellie, Gustav and Valdric (same scale, feet on one line)

Built from ellipsoids with the heroine's renderer (same grain, ink and outline rules as Ellie, Gustav and Valdric). A wall of a man: no neck to speak of, a barrel
chest and shoulders as wide as a barn door, forearms thicker than most thighs covered in burn scars and soot, a short soot-black beard, hair tied tight at the
back, a two-layer apron of hardened bull hide over a sleeveless undyed wool shirt, a belt with tongs, a leather rag and a small hammer, boots with iron toe caps.
His sledge hammer (an ash haft with notches, an iron head) is the one thing that gives him away in every direction; its colours are the only warm ones
besides the glowing iron he works: that iron is the glow sheet (assets/characters/torben_glow.png, drawn unlit by `Settler`).

Coordinates of the model: x to his left, y up, z forward (toward the viewer at yaw 0). His right hand (the hammer hand) is at negative x.
"""
import json, math, multiprocessing as mp, os, sys
from pathlib import Path
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 88, 104, 88
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.1
BASE = len(h.RAMPS)
(HAIR, SKIN, SOOT, SCAR, APRON, APRON_L, STRAP, SHIRT, TROUSERS, BOOT, IRON, ASH, HOT, RAG, BRASS) = range(BASE, BASE + 15)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['0d0a0f', '1c161b', '30272b', '4e4246'],  # soot-black hair and beard
    ['34201f', '603a33', '8a5a46', 'b0826a'],  # weathered skin, tanned dark by the fire and ground in with soot
    ['1a1012', '2c1b1c', '40292a', '553838'],  # soot ground into the skin
    ['7a5048', 'a67a68', 'c9a08a', 'e6c4b0'],  # old burn scars, paler than the skin around them
    ['1d130f', '3a2418', '5f3d28', '86593a'],  # hardened bull hide: the upper layer of the apron
    ['150d0a', '2e1c12', '4d3020', '6e4a30'],  # the lower layer, scorched dark at the hem
    ['120b09', '261811', '3f271a', '5a3a26'],  # straps, belt, cuffs
    ['2a2630', '514b55', '7d767a', 'a89f9c'],  # undyed wool shirt
    ['17141c', '2d2832', '48404a', '675d63'],  # heavy wool trousers
    ['120e12', '241a1c', '3a2b2a', '574340'],  # boots
    ['14162a', '30384f', '566285', '8795b6'],  # iron: tongs, hammer head, buckle, toe caps (darker than the tools' steel: worked, scaled iron)
    ['3a2b26', '6e5139', 'a07c53', 'cfaa78'],  # ash wood: the haft
    ['6a1a10', 'c4461a', 'ff8a2a', 'ffd98a'],  # iron at forging heat (the glow sheet is every pixel of this ramp)
    ['2c2620', '4e463a', '766a58', 'a09580'],  # the leather rag at his hip
    ['3a2c14', '6e5426', 'a8883e', 'd8bc6a'],  # dull brass: rivets, the buckle's tongue
]]
HOT_COLORS = {tuple(c) for c in h.RAMPS[HOT]}
h.RAMPS[h.EYE] = hexc('1a1218'), hexc('3d2a20'), hexc('7a5638'), hexc('f0e6d4')  # deep-set, watchful brown eyes
SOFT = (HAIR, SKIN, SCAR, SOOT)
_shade = h.shade_band


def shade_band(lam, kind, mat):
    """Hair and skin get the heroine's soft bands, everything else the standard ones."""
    if mat in SOFT:
        return np.digitize(lam, (-0.1, 0.18, 0.62) if mat == HAIR else (-0.2, 0.12, 0.55))
    return _shade(lam, kind, mat)


h.shade_band = shade_band
V = lambda *x: np.array(x, float)
rot_x, rot_y = h.rot_x, h.rot_y
L = 26.0  # the haft


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def unit(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def hair_clip(q):
    """The hair pulled back: a high forehead, the hairline curving down over the temples."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.1) & (y < 0.52 - 0.32 * np.abs(x) ** 1.3) & (np.abs(x) < 0.99)
    return (y > -0.22) & ~opening


def beard_clip(q):
    """A short beard on the jaw and the chin with a gap for the mouth; the cheek line runs from the ear to the corner of the mouth."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    line = -0.12 - 0.42 * (1.0 - np.minimum(np.abs(x), 1.0)) ** 1.2
    mouth = (z > 0.45) & (np.abs(x) < 0.3) & (y > -0.66) & (y < -0.46)
    return (y < line) & (z > -0.55) & ~mouth


# --------------------------------------------------------------------------------------------- poses
STAND = ((3.3, 0.0, 0.0), (-3.3, 0.0, 0.0))


def base(**k):
    d = dict(feet=STAND, hy=None, hz=0.0, lean=0.04, twist=0.0, breath=0.0, hp=0.0, hyaw=0.0, ham=None, rh=None, lh=None, tongs=None, pole_r=None, pole_l=None, dust=0)
    d.update(k)
    return d


# hammer specs: ('G', space, hand, head) the hand on the haft, ('B', space, butt, head) both ends; space 'T' follows the torso (lean, twist), 'W' is the model's own
CARRY = ('G', 'T', (-10.6, 29.8, 3.6), (-9.0, 47.5, -6.4))   # over the right shoulder
BACK = ('B', 'T', (-8.5, 22.0, -7.4), (8.5, 47.0, -7.6))      # slung across the back
LEAN_HAM = ('G', 'W', (-14.0, 30.0, 4.0), (-14.0, 4.2, 4.0))  # standing on its head, his hand on the butt


def smooth(t):
    return t * t * (3 - 2 * t)


def pose(clip, i):
    n = CLIPS[clip]['count']
    a = 2 * math.pi * i / n
    if clip in ('walk', 'run'):
        s, c = math.sin(a), math.cos(a)
        run = clip == 'run'
        stride, lift = (5.6, 3.0) if run else (3.7, 1.9)
        return base(feet=((3.3, stride * s, lift * max(c, 0)), (-3.3, -stride * s, lift * max(-c, 0))), lean=0.15 if run else 0.06, twist=0.08 * s, breath=0.3, hp=0.02 * math.cos(2 * a),
                    ham=CARRY, rh=('ham',), lh=('pt', 'T', (11.4, 25.8 + (1.2 if run else 0.0) * abs(s), (5.2 if run else 3.4) * s + 0.4)))
    if clip == 'idle':
        b = [0, .4, .8, 1, .7, .3][i]
        return base(breath=b, hp=[0, 0, .03, .03, 0, 0][i], feet=((3.3, 0.3 * (i in (2, 3)), 0), (-3.3, 0, 0)), ham=CARRY, rh=('ham',), lh=('pt', 'T', (11.2, 25.4, 0.8 + 0.2 * b)), twist=0.02)
    if clip == 'stand':
        b = [0, .5, 1, .5][i]
        return base(breath=b, lean=0.05, twist=0.1, ham=LEAN_HAM, rh=('ham',), lh=('pt', 'T', (9.8, 26.2, 1.2)), hp=0.04)
    if clip == 'work':
        # one hand on the sledge, choked up, the other holds the tongs at the anvil; the blow lands on frame 4
        W = V(1.8, 25.6, 11.6)
        f = [
            dict(G=(-8.8, 31.0, 6.8), Hd=(0.8, 28.6, 12.2), lean=.10, hp=.06),                    # 0 the hammer rests on the iron
            dict(G=(-9.6, 35.2, 5.0), Hd=(-5.0, 41.8, 11.0), lean=.06, hp=.0),                   # 1 lifts
            dict(G=(-9.8, 41.5, 1.4), Hd=(-8.0, 51.8, 5.2), lean=.0, hp=-.04),                   # 2 raised
            dict(G=(-9.6, 43.5, 0.6), Hd=(-8.2, 54.6, -2.0), lean=-.04, hp=-.06),                # 3 the top of the swing
            dict(G=(-8.8, 31.5, 7.2), Hd=(0.8, 28.4, 12.0), lean=.26, hp=.12),                   # 4 the blow
            dict(G=(-9.0, 33.2, 6.4), Hd=(0.2, 32.6, 12.2), lean=.14, hp=.06),                   # 5 rebound
            dict(G=(-8.8, 31.0, 6.8), Hd=(0.8, 28.8, 11.8), lean=.11, hp=.04),                   # 6 settles
            dict(G=(-8.8, 31.2, 6.8), Hd=(0.6, 29.4, 11.6), lean=.08, hp=.10),                   # 7 a look at the iron
        ][i]
        raise_w = 1.4 if i == 7 else 0.0
        return base(lean=f['lean'], hp=f['hp'], breath=.3, twist=-.12, ham=('G', 'W', f['G'], f['Hd'], 15.0), rh=('ham',), lh=('pt', 'W', (8.4, 27.2 + raise_w, 7.8)),
                    tongs=(W + V(0, raise_w, 0), 1.0), feet=((3.6, 1.0, 0), (-3.6, -1.2, 0)), pole_r=(-.4, -.2, -.9))
    if clip == 'sledge':
        # both hands: a heavy overhead blow into the ground in front of him; frame 4 is the impact
        f = [
            (('B', 'W', (-5.0, 30.0, 6.0), (1.5, 11.0, 15.0)), .12, 0),                           # 0 ready, low
            (('B', 'W', (-4.5, 38.0, 4.0), (-1.0, 58.0, 0.0)), .0, 0),                            # 1 up
            (('B', 'W', (-4.8, 44.0, 0.0), (-2.6, 64.0, -8.0)), -.12, 0),                         # 2 behind the head
            (('B', 'W', (-4.8, 43.0, 1.5), (-2.4, 62.0, -4.0)), -.04, 0),                         # 3 top
            (('B', 'W', (-3.0, 27.0, 6.0), (-1.0, 6.0, 15.0)), .42, 1),                           # 4 impact
            (('B', 'W', (-3.2, 29.0, 6.0), (-1.0, 9.0, 15.2)), .34, 1),                           # 5 recoil
            (('B', 'W', (-3.6, 30.0, 6.0), (0.0, 9.5, 15.0)), .24, 0),                            # 6 hold
            (('B', 'W', (-4.6, 31.0, 6.0), (1.0, 12.0, 14.6)), .14, 0),                           # 7 heaves it up again
        ][i]
        return base(lean=f[1], breath=.4, twist=-.1, ham=f[0], rh=('ham', .1), lh=('ham', .42), feet=((4.4, 3.5, 0), (-4.4, -2.5, 0)) if i != 4 else ((4.6, 4.5, 0), (-4.6, -1.5, 0)),
                    pole_r=(-.7, -.3, -.4), pole_l=(.7, -.3, -.4), hp=.0 if i < 4 else .1)
    if clip == 'swat':
        # one-handed, flat and fast: the hammer sweeps across his front from his right to his left (frame 2 is the contact)
        f = [
            (('G', 'T', (-11.6, 31.0, 1.0), (-13.5, 31.0, -9.0)), -.35),
            (('G', 'T', (-8.8, 30.0, 6.0), (-4.5, 30.0, 15.5)), -.1),
            (('G', 'T', (-2.0, 30.2, 8.5), (10.5, 30.0, 14.2)), .22),
            (('G', 'T', (3.0, 30.4, 6.5), (14.0, 30.0, 7.0)), .3),
            (('G', 'T', (-7.0, 30.6, 4.5), (-8.5, 31.2, 12.0)), .06),
        ][i]
        return base(twist=f[1], lean=.1, breath=.3, ham=f[0], rh=('ham',), lh=('pt', 'T', (11.5, 29.0, 2.5)), feet=((3.5, 1.0, 0), (-3.5, -2.0, 0)))
    if clip in ('sit_down', 'sit'):
        e = smooth(i / (CLIPS['sit_down']['count'] - 1)) if clip == 'sit_down' else 1.0
        hy = 24.2 - 11.4 * e
        b = [0, .5, 1, .5][i % 4] if clip == 'sit' else 0
        hg = 4.2 + 3.0 * e
        return base(hy=hy, hz=-2.5 * e, lean=.05 + .30 * math.sin(math.pi * e) * (1 if clip == 'sit_down' else 0) + (.08 if clip == 'sit' else 0), breath=b, twist=.1,
                    feet=((3.7, 10.5 * e, 0), (-3.7, 9.5 * e, 0)), ham=('G', 'W', (-14.0, 30.0 - 4.4 * e, 5.0 + 1.0 * e), (-14.0, hg, 5.0 + 1.0 * e)), rh=('ham',),
                    lh=('pt', 'W', (7.4, 24.2 - 7.4 * e + 0.0, 4.0 + 6.0 * e)), hp=.05 * e)
    if clip == 'bellows':
        e = [0, .5, 1, .8, .4, .1][i]
        return base(lean=.10 + .08 * e, twist=.12, breath=.3, ham=CARRY, rh=('pt', 'W', (-12.6, 36.5 - 10.0 * e, 6.0 + 3.0 * e)), lh=('pt', 'T', (10.0, 25.4, 1.6)), feet=((3.6, 1.0, 0), (-3.6, -1.0, 0)), hp=.06)
    if clip == 'quench':
        # the tongs lift the glowing piece from the anvil, swing to the water barrel on his left, dip it (it goes dark) and lift it out
        path = [(1.8, 25.6, 11.6), (2.4, 32.5, 11.0), (9.0, 33.0, 9.4), (13.0, 25.0, 9.2), (13.2, 24.2, 9.2), (12.2, 32.0, 9.4)][i]
        hot = 1.0 if i < 3 else 0.0
        hand = V(path[0] - 3.4, path[1] + 1.6, path[2] - 3.5)
        return base(lean=.10, twist=-.05 - .22 * (1 if i >= 2 else 0), breath=.3, ham=CARRY, rh=('ham',), lh=('pt', 'W', tuple(hand)), tongs=(V(*path), hot), feet=((3.6, 1.0, 0), (-3.6, -1.0, 0)), hp=.1 if i in (3, 4) else .0)
    if clip in ('lift', 'carry', 'set_down'):
        # the right arm shoots out for a collar, hoists, carries, sets down (the hammer rides on his back)
        reach = {'lift': [0.2, .55, 1.0, 1.0, 1.0, 1.0], 'carry': [1.0] * 4, 'set_down': [1.0, .6, .2, 0.0]}[clip][i]
        raise_y = {'lift': [0, 0, 0, .5, 1.0, 1.0], 'carry': [1.0] * 4, 'set_down': [1.0, .5, .1, 0.0]}[clip][i]
        fist = V(-5.8, 30.0 + 7.5 * raise_y + 4.0 * reach, 6.0 + 9.5 * reach)
        step = 0.0
        feet = STAND
        if clip == 'carry':
            s = math.sin(a)
            feet = ((3.3, 3.2 * s, 1.6 * max(math.cos(a), 0)), (-3.3, -3.2 * s, 1.6 * max(-math.cos(a), 0)))
        return base(feet=feet, lean=.08 + .08 * reach, twist=.18 * reach, breath=.3, ham=BACK, rh=('pt', 'W', tuple(fist)), lh=('pt', 'T', (11.0, 25.6, 1.2)), pole_r=(-.8, -.2, -.1), hp=.05 * reach)
    if clip == 'shove':
        e = [0, .6, 1, 1, .4][i]
        return base(lean=.06 + .18 * e, twist=-.1 * e, breath=.3, ham=BACK, rh=('pt', 'T', (-10.4, 26.0, 1.2)), lh=('pt', 'W', (-1.0, 35.4, 7.0 + 9.0 * e)), pole_l=(.5, -.5, -.3),
                    feet=((3.3, 3.2 * e, 0), (-3.3, -2.0 * e, 0)))
    if clip == 'grab_armor':
        sh = [-1.2, 1.2, -1.2, 1.2, -.6, .6][i]
        return base(lean=.10, breath=.3, ham=BACK, rh=('pt', 'W', (-5.0, 36.5 + sh * .5, 14.5 + sh)), lh=('pt', 'W', (5.0, 36.5 - sh * .5, 14.5 - sh)), twist=.04 * sh, pole_r=(-.5, -.2, -.4), pole_l=(.5, -.2, -.4))
    if clip == 'nod':
        return base(hp=[0, .3, .04, 0][i], breath=[0, .2, 0, 0][i], ham=CARRY, rh=('ham',), lh=('pt', 'T', (11.2, 25.4, .8)))
    if clip == 'snort':
        return base(hp=[-.08, -.14, .12, .0][i], breath=[1.2, 1.5, .2, 0][i], lean=[.02, -.02, .1, .05][i], ham=CARRY, rh=('ham',), lh=('pt', 'T', (11.2, 25.4, .8)))
    raise KeyError(clip)


CLIPS = {
    'idle': {'start': 0, 'count': 6, 'fps': 5},
    'walk': {'start': 6, 'count': 8, 'fps': 8},
    'run': {'start': 14, 'count': 6, 'fps': 10},
    'stand': {'start': 20, 'count': 4, 'fps': 3},
    'work': {'start': 24, 'count': 8, 'fps': 6, 'strike': 4},
    'sledge': {'start': 32, 'count': 8, 'fps': 7, 'strike': 4},
    'swat': {'start': 40, 'count': 5, 'fps': 12, 'loop': False},
    'sit_down': {'start': 45, 'count': 6, 'fps': 8, 'loop': False},
    'sit': {'start': 51, 'count': 4, 'fps': 3},
    'bellows': {'start': 55, 'count': 6, 'fps': 5},
    'quench': {'start': 61, 'count': 6, 'fps': 6},
    'lift': {'start': 67, 'count': 6, 'fps': 10, 'loop': False},
    'carry': {'start': 73, 'count': 4, 'fps': 6},
    'set_down': {'start': 77, 'count': 4, 'fps': 8, 'loop': False},
    'shove': {'start': 81, 'count': 5, 'fps': 10, 'loop': False},
    'grab_armor': {'start': 86, 'count': 6, 'fps': 8},
    'nod': {'start': 92, 'count': 4, 'fps': 6, 'loop': False},
    'snort': {'start': 96, 'count': 4, 'fps': 6, 'loop': False},
}
FRAMES = 100


# --------------------------------------------------------------------------------------------- the model
def legs_for(p):
    feet = p['feet']
    hips = [V(3.2, 0, p['hz'] + 0.2), V(-3.2, 0, p['hz'] + 0.2)]
    ankles = [V(f[0], 2.5 + f[2], f[1]) for f in feet]
    if p['hy'] is None:
        hy = 26.0
        for hip, ank in zip(hips, ankles):
            hy = min(hy, ank[1] + math.sqrt(max(23.3 ** 2 - ((ank[0] - hip[0]) ** 2 + (ank[2] - hip[2]) ** 2), 1.0)))
    else:
        hy = p['hy']
    out = []
    for hip, ank in zip(hips, ankles):
        hip = hip + V(0, hy, 0)
        knee, end = h.ik2(hip, ank, 12.6, 11.0, (0.0, 0.0, 1.0))
        out.append((hip, knee, end))
    return out, hy - 24.0


def build(p, clip):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = legs_for(p); off = V(0, drop, 0)
    # ---------------------------------------------------------------- legs: heavy wool, boots with iron toe caps and a buckled strap
    for hip, knee, ankle in legs:
        limb(hip, knee, 4.1, 3.5, TROUSERS); limb(knee, ankle, 3.4, 2.8, TROUSERS)
        ell(knee + V(0, 0.2, 2.9), (2.4, 2.3, 0.6), STRAP)                                      # a knee patch
        shaft = ankle + V(0, 4.6, -0.2)
        limb(ankle + V(0, 0.4, -0.2), shaft, 2.8, 3.0, BOOT); ell(shaft + V(0, 1.0, 0), (3.3, 0.9, 3.25), BOOT)
        ell(shaft + V(0, 0.3, 2.9), (0.85, 0.6, 0.4), BRASS)                                    # buckle
        ell(shaft + V(0, -1.7, 0), (3.1, 0.45, 3.05), STRAP)                                    # the strap round the shaft
        ell(ankle + V(0, -1.0, 1.5), (2.95, 1.95, 3.9), BOOT)                                    # toe box
        ell(ankle + V(0, -1.4, 4.6), (2.3, 0.9, 1.0), IRON)                                    # a sliver of iron toe cap
        ell(ankle + V(0, -2.35, 1.5), (3.0, 0.55, 4.4), STRAP)                                  # sole
        ell(ankle + V(0, 0.2, -0.5), (2.8, 2.5, 2.7), BOOT)                                      # heel
    m.off = off
    R = rot_x(p['lean']) @ rot_y(p['twist']); b = p['breath']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    def S(space, v):
        return T(v) if space == 'T' else np.asarray(v, float) - off

    # ---------------------------------------------------------------- torso: a barrel chest, a short thick neck, shoulders as wide as a barn door
    ell(T((0, 25, 0.2)), (7.0, 4.0, 4.9), TROUSERS, R=R)
    ell(T((0, 30.2, 0.6)), (7.7, 5.5, 5.7), SHIRT, R=R)
    ell(T((0, 35.4 + b * .15, 0.5)), (9.4, 5.0, 5.5), SHIRT, R=R)                                # chest
    ell(T((0, 38.5 + b * .1, -0.2)), (10.6, 2.8, 4.7), SHIRT, R=R)                                # yoke of the shoulders
    ell(T((0, 40.4, -0.6)), (5.4, 2.2, 3.9), SKIN, R=R)                                           # trapezius
    ell(T((0, 41.9, 0.2)), (3.9, 2.7, 3.6), SKIN, R=R)                                            # the neck
    ell(T((0, 37.9, 5.1)), (2.7, 2.7, 0.55), SKIN, R=R)                                           # the V of the open collar
    for x, y in ((-0.9, 38.4), (0.7, 37.4), (-0.2, 36.4)):
        ell(T((x, y, 5.5)), (0.55, 0.45, 0.3), SOOT, R=R)                                         # chest hair, black with soot
    ell(T((-2.4, 33.5, -5.2)), (4.2, 3.6, 0.6), SOOT, R=R)                                        # a sweat-and-soot patch on his back
    ell(T((-5.6, 35.8, 4.4)), (1.5, 1.2, 0.4), SOOT, R=R)
    # ---------------------------------------------------------------- the apron: two layers of bull hide, the lower scorched at the hem, straps crossed on his back
    ribbon([T((0, 37.8, 5.2)), T((0, 33.0, 6.9)), T((0, 27.6, 7.0))], [4.6, 6.2, 6.9], 0.85, APRON, (0, 0, 1), kind='')
    ribbon([T((0, 28.2, 7.2)), T((0, 20.4, 7.5)), T((0, 12.0, 6.9))], [7.2, 7.8, 7.2], 0.9, APRON_L, (0, 0, 1), kind='')
    ell(T((0, 11.4, 6.9)), (7.1, 0.5, 1.0), STRAP, R=R)                                           # the scorched hem
    for x, y in ((-3.4, 17.5), (2.8, 14.5), (-1.0, 21.5)):
        ell(T((x, y, 8.3)), (0.9, 0.9, 0.3), SOOT, R=R)                                           # burn holes
    ell(T((2.4, 24.5, 8.2)), (2.4, 1.6, 0.4), APRON, R=R)                                         # a patched seam
    for side in (-1, 1):
        ribbon([T((side * 3.3, 37.4, 5.2)), T((side * 4.2, 40.0, 1.0)), T((side * 3.6, 39.6, -2.6))], [.95, .95, .9], .4, STRAP, (0, 0, 1), kind='')
        ribbon([T((side * 3.6, 39.4, -3.0)), T((0, 33.0, -5.6)), T((-side * 4.2, 27.4, -5.5))], [.9, .9, .9], .35, STRAP, (0, 0, 1), kind='')
        ell(T((side * 3.8, 37.2, 5.7)), (0.5, 0.5, 0.3), BRASS, R=R)
    ribbon([T((-7.4, 26.4, 1.8)), T((-4.6, 26.4, 6.5)), T((0, 26.4, 8.6)), T((4.6, 26.4, 6.5)), T((7.4, 26.4, 1.8)), T((6.0, 26.4, -3.4)), T((0, 26.4, -5.8)), T((-6.0, 26.4, -3.4))],
           [1.5] * 8, .55, STRAP, (0, 0, 1), kind='')                                              # a broad belt
    ell(T((0, 26.4, 9.1)), (1.7, 1.4, 0.45), IRON, R=R)                                           # iron buckle
    ell(T((0, 26.4, 9.5)), (0.55, 0.9, 0.3), BRASS, R=R)
    # belt gear: the tongs hang from the left hip, a leather rag from the right, the small hammer behind
    limb(T((7.6, 25.6, 1.2)), T((8.4, 12.5, 1.6)), .5, .5, IRON)
    limb(T((7.0, 25.6, 1.5)), T((7.6, 12.2, 2.2)), .5, .5, IRON)
    ell(T((7.5, 25.8, 1.4)), (1.1, 1.1, .8), IRON, R=R)
    ell(T((-7.6, 22.4, 1.4)), (1.5, 4.4, 0.55), RAG, R=R @ rot_z(.08))
    ell(T((-7.7, 18.0, 1.6)), (1.45, 1.0, 0.5), SOOT, R=R @ rot_z(.08))
    limb(T((3.4, 25.6, -5.4)), T((5.2, 31.4, -5.8)), .55, .5, ASH)
    ell(T((5.5, 32.0, -5.8)), (1.5, .9, .9), IRON, R=R)
    # ---------------------------------------------------------------- the sledge hammer
    ham = p['ham']
    hammer = None
    if ham is not None:
        mode, space, p1, p2 = ham[:4]
        Lh = ham[4] if len(ham) > 4 else L                                                          # the work hammer has a shorter haft and a smaller head
        hs = min(1.0, max(0.74, Lh / L))
        p1, p2 = S(space, p1), S(space, p2)
        if mode == 'G':
            d = unit(p2 - p1)
            head = p1 + d * min(np.linalg.norm(p2 - p1), Lh * .95)
            butt = head - d * Lh
        else:
            butt, head = p1, p2
            d = unit(head - butt)
            head = butt + d * Lh
        hammer = (butt, head, d, Lh)
        limb(butt, head, 0.98, 1.1, ASH)
        for t in (0.32, 0.56, 0.78):                                                              # the haft is notched where his hand has been
            ell(butt + d * Lh * t + V(.45, 0, 0), (.45, .6, .5), STRAP, R=h.frame_from(d, V(0, 0, 1)))
        ell(butt, (1.3, .7, 1.3), ASH, R=h.frame_from(d, V(0, 0, 1)))
        ax = V(1, 0, 0) - d * d[0]
        ax = unit(ax) if np.linalg.norm(ax) > 1e-3 else V(0, 0, 1)
        Rh = h.frame_from(ax, d)
        ell(head, (3.0 * hs, 4.5 * hs, 3.05 * hs), IRON, R=Rh)                                                    # the heavy head
        for sgn in (-1, 1):
            ell(head + ax * sgn * 3.9 * hs, (3.15 * hs, 1.1, 3.2 * hs), IRON, R=Rh)                              # its faces
        ell(head, (3.12 * hs, 1.3, 3.18 * hs), STRAP, R=Rh)                                                  # the wedge band round the eye
        ell(head - d * 1.8, (1.25, 1.0, 1.25), ASH, R=Rh)                                          # haft entering the eye

    def hand_target(spec, side):
        kind = spec[0]
        if kind == 'ham':
            tt = spec[1] if len(spec) > 1 else None
            butt, head, d, Lh = hammer
            return butt + d * (Lh * tt) if tt is not None else None
        return S(spec[1], spec[2])

    def arm(side, spec, pole):
        sh = T((side * 9.8, 37.6, 0))
        if spec is None:
            tgt = T((side * 11.4, 25.4, 0.9))
        elif spec[0] == 'ham':
            butt, head, d, Lh = hammer
            if len(spec) > 1:
                tgt = butt + d * (Lh * spec[1])
            else:
                g = p['ham']
                tgt = S(g[1], g[2]) if g[0] == 'G' else butt + d * (Lh * 0.12)
        else:
            tgt = S(spec[1], spec[2])
        elbow, wrist = h.ik2(sh, tgt, 8.2, 7.6, pole if pole is not None else (side * .5, -.6, -.6))
        ell(sh, (4.3, 4.1, 4.1), SKIN, R=R)                                                       # the shoulder
        limb(sh, elbow, 4.0, 3.4, SKIN)
        up = unit(elbow - sh)
        ell(sh + up * 4.2 + V(0, 0, 0.9), (3.7, 3.4, 3.6), SKIN)                                   # a bulging upper arm
        ell(elbow, (3.3, 3.2, 3.3), SKIN)
        d = unit(wrist - elbow)
        limb(elbow, wrist, 3.5, 2.8, SKIN)
        ell(elbow + d * 3.0, (3.75, 3.3, 3.5), SKIN)                                               # the forearm muscle
        limb(wrist - d * 3.3, wrist - d * .7, 3.15, 3.05, STRAP)                                   # a leather burn cuff
        ell(wrist - d * 2.0 + V(side * 0.0, 0, 3.0), (.5, .5, .35), BRASS)
        ell(wrist + d * 1.5, (3.0, 2.8, 2.6), SKIN)                                                # the fist
        ell(wrist + d * 2.5, (2.6, 1.15, 2.35), SKIN)
        ell(wrist + d * 1.0 + V(-side * 1.4, 0, 1.6), (.95, 1.3, .85), SKIN)                       # thumb
        for k, shift in enumerate((-1.2, 0.0, 1.2)):                                               # scars and soot ground into the arm
            ell(elbow + d * (2.0 + 1.6 * k) + V(side * (1.2 - .5 * k), shift * .5, 2.0), (.3 + .2 * k, .9, .3), SCAR)
        ell(elbow + d * 4.6 + V(0, 0.4, 2.6), (1.2, 1.4, .5), SOOT)
        ell(sh + up * 2.0 + V(side * 1.2, .8, 2.4), (1.0, .35, .35), SCAR)
        return wrist, d

    r_wrist, r_dir = arm(-1, p['rh'] if p['rh'] is None else (p['rh'] if p['rh'][0] != 'ham' else ('ham',) + tuple(p['rh'][1:])), p['pole_r'] if p['pole_r'] is not None else (-.5, -.6, -.6))
    l_wrist, l_dir = arm(1, p['lh'], p['pole_l'] if p['pole_l'] is not None else (.5, -.6, -.6))
    # ---------------------------------------------------------------- the tongs and the iron in them
    if p['tongs'] is not None:
        W, hot = p['tongs']
        W = np.asarray(W, float) - off
        t_dir = unit(W - l_wrist)
        side_v = unit(np.cross(t_dir, V(0, 1, 0)))
        for sgn in (-1, 1):
            limb(l_wrist - t_dir * 2.4 + side_v * sgn * 1.2, W - t_dir * 1.6 + side_v * sgn * 0.5, .55, .6, IRON)
            limb(W - t_dir * 1.8 + side_v * sgn * 0.5, W + t_dir * 1.0 + side_v * sgn * 0.4, .6, .55, IRON)
        piece = h.frame_from(t_dir, V(0, 1, 0))
        ell(W + t_dir * 1.8, (1.5, 3.6, 0.8), HOT if hot > 0.5 else IRON, R=piece, kind='emit' if hot > 0.5 else '')
    # ---------------------------------------------------------------- the head: a short thick neck under a heavy jaw, tied-back hair, a short soot beard
    Rn = R @ rot_x(p['hp']) @ rot_y(p['hyaw'])
    neck = T((0, 41.4, 0.2))
    hc = neck + R @ (rot_x(p['hp']) @ rot_y(p['hyaw']) @ V(0, 4.2, 0.6))
    ell(hc, (5.0, 5.2, 4.95), SKIN, R=Rn, kind='head')
    ell(hc + Rn @ V(0, -3.6, 1.2), (4.1, 2.7, 3.8), SKIN, R=Rn)                                   # the jaw
    ell(hc + Rn @ V(0, -5.2, 2.9), (2.7, 1.5, 2.1), SKIN, R=Rn)                                   # a square chin
    ell(hc + Rn @ V(0, .5, -.4), (5.3, 5.5, 5.15), HAIR, R=Rn, kind='hair', tag=3.0, clip=hair_clip)
    ell(hc + Rn @ V(0, -.8, -.2), (5.3, 5.8, 5.2), HAIR, R=Rn, kind='hair', tag=7.0, clip=beard_clip)
    ell(hc + Rn @ V(0, 1.8, -5.5), (2.4, 2.5, 2.4), HAIR, R=Rn, kind='hair', tag=5.0)            # the knot at the back
    ell(hc + Rn @ V(0, 1.6, -7.1), (2.55, .8, 2.55), STRAP, R=Rn)
    ribbon([hc + Rn @ V(0, 1.2, -7.3), hc + Rn @ V(0, -1.8, -8.1), hc + Rn @ V(0, -5.2, -8.0)], [1.7, 1.4, .7], .8, HAIR, (0, 0, 1), kind='hair')
    for side in (-1, 1):
        ell(hc + Rn @ V(side * 5.1, -1.4, 0.3), (.85, 1.7, 1.0), SKIN, R=Rn)                          # ears
        ell(hc + Rn @ V(side * 2.3, 1.7, 4.45), (2.25, .95, 1.2), HAIR, R=Rn @ rot_z(side * -.30))  # heavy brows, slanting in
        ell(hc + Rn @ V(side * 2.3, 1.4, 4.3), (2.4, .8, .9), SKIN, R=Rn)                          # the brow ridge over deep-set eyes
        ell(hc + Rn @ V(side * 3.1, -0.9, 3.5), (1.7, 1.4, 1.2), SKIN, R=Rn)                       # cheek bones
    ell(hc + Rn @ V(0, -1.0, 4.9), (1.45, 1.9, 1.5), SKIN, R=Rn)                                   # a strong nose
    ell(hc + Rn @ V(0.2, -2.0, 5.2), (0.8, .5, .6), SKIN, R=Rn)
    for side in (-1, 1):
        limb(hc + Rn @ V(side * .5, -2.5, 5.1), hc + Rn @ V(side * 3.6, -3.3, 4.2), 1.05, .8, HAIR)  # a thin, down-swept moustache
    ell(hc + Rn @ V(-3.2, -2.2, 3.7), (1.1, .55, .4), SOOT, R=Rn)                                  # soot on the cheek
    ell(hc + Rn @ V(1.6, 3.9, 3.6), (.3, 1.3, .3), SCAR, R=Rn @ rot_z(.5))                         # a pale scar through the left brow
    ell(hc + Rn @ V(-1.0, 3.2, 4.3), (1.3, .5, .4), SOOT, R=Rn)                                     # a smear on the forehead
    return m


def render_one(job):
    sector, index, clip, i = job
    p = pose(clip, i); model = build(p, clip)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


def glow_of(frame):
    """Only the pixels of the forging-heat ramp (exact colours), brighter, with a faint one-pixel halo on empty ground around them."""
    out = np.zeros_like(frame)
    hot = np.zeros(frame.shape[:2], bool)
    for y in range(frame.shape[0]):
        for x in range(frame.shape[1]):
            if tuple(frame[y, x]) in HOT_COLORS:
                out[y, x] = frame[y, x]; hot[y, x] = True
    for y, x in zip(*np.nonzero(hot)):
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < frame.shape[0] and 0 <= xx < frame.shape[1] and not hot[yy, xx] and out[yy, xx, 3] == 0:
                out[yy, xx] = (255, 150, 60, 80)
    return out


def contact(arr, path, picks, scale=3):
    from PIL import Image
    canvas = Image.new('RGB', (len(picks) * FW * scale, 8 * FH * scale), (38, 34, 50))
    for s in range(8):
        for j, i in enumerate(picks):
            src = Image.fromarray(arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW]); tile = Image.new('RGBA', (FW, FH), (38, 34, 50, 255)); tile.alpha_composite(src)
            canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (j * FW * scale, s * FH * scale))
    canvas.save(path)


def render_all(jobs, frames=FRAMES):
    arr = np.zeros((8 * FH, frames * FW, 4), dtype=np.uint8)
    with mp.Pool(min(6, os.cpu_count() or 1)) as pool:
        for s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    return arr


def compare(path):
    """Ellie (idle), Gustav (idle), Valdric (idle) and Torben (idle) from the south, feet on one line, 4x."""
    from PIL import Image
    sheets = [('assets/characters/player.png', 48, 56, (24, 51), 12 + 0, 2), ('assets/characters/gustav.png', 72, 76, (36, 62), 0, 2),
              ('assets/characters/adventurer.png', 84, 100, (42, 84), 0, 2), ('assets/characters/torben.png', FW, FH, (FW // 2, GROUND), 0, 2)]
    k = 4
    canvas = Image.new('RGBA', (4 * 100 * k, 110 * k), (38, 34, 50, 255))
    for n, (f, w, hh, feet, col, row) in enumerate(sheets):
        im = Image.open(ROOT / f.replace('assets/', '')).convert('RGBA')
        tile = im.crop((col * w, row * hh, (col + 1) * w, (row + 1) * hh)).resize((w * k, hh * k), Image.Resampling.NEAREST)
        canvas.alpha_composite(tile, (n * 100 * k + 50 * k - feet[0] * k, 100 * k - feet[1] * k))
    canvas.convert('RGB').save(path)


def grid(path, sector):
    """Every frame of the written sheet for one facing (rows follow the clips), 2x, with the clip names on the left."""
    from PIL import Image, ImageDraw
    sheet = Image.open(ROOT / 'characters/torben.png').convert('RGBA')
    k, cols = 2, 10
    rows = (FRAMES + cols - 1) // cols
    canvas = Image.new('RGBA', (cols * FW * k, rows * FH * k), (38, 34, 50, 255))
    draw = ImageDraw.Draw(canvas)
    for i in range(FRAMES):
        tile = sheet.crop((i * FW, sector * FH, (i + 1) * FW, (sector + 1) * FH)).resize((FW * k, FH * k), Image.Resampling.NEAREST)
        canvas.alpha_composite(tile, (i % cols * FW * k, i // cols * FH * k))
        for name, c in CLIPS.items():
            if c['start'] == i:
                draw.text((i % cols * FW * k + 3, i // cols * FH * k + 3), name, fill=(255, 220, 120, 255))
    canvas.convert('RGB').save(path)


def clip_sheet(name, path, sectors=(2, 0, 6)):
    """One clip in a few facings (rows), 3x: python3 tools/art_torben.py clip work out.png [sector,sector,...]"""
    from PIL import Image
    entry = CLIPS[name]
    jobs = [(s, entry['start'] + i, name, i) for s in sectors for i in range(entry['count'])]
    arr = render_all(jobs)
    k = 3
    canvas = Image.new('RGB', (entry['count'] * FW * k, len(sectors) * FH * k), (38, 34, 50))
    for r, s in enumerate(sectors):
        for i in range(entry['count']):
            col = entry['start'] + i
            tile = Image.new('RGBA', (FW, FH), (38, 34, 50, 255)); tile.alpha_composite(Image.fromarray(arr[s * FH:(s + 1) * FH, col * FW:(col + 1) * FW]))
            canvas.paste(tile.convert('RGB').resize((FW * k, FH * k), Image.Resampling.NEAREST), (i * FW * k, r * FH * k))
    canvas.save(path)


def main():
    if len(sys.argv) > 3 and sys.argv[1] == 'clip':
        clip_sheet(sys.argv[2], sys.argv[3], tuple(int(x) for x in sys.argv[4].split(',')) if len(sys.argv) > 4 else (2, 0, 6)); print('clip sheet written'); return
    if len(sys.argv) > 3 and sys.argv[1] == 'grid':
        grid(sys.argv[2], int(sys.argv[3])); print('grid written'); return
    if len(sys.argv) > 2 and sys.argv[1] == 'compare':
        compare(sys.argv[2]); print('comparison written'); return
    quick = len(sys.argv) > 1 and sys.argv[1] == 'quick'
    jobs = [(s, entry['start'] + i, k, i) for s in range(8) for k, entry in CLIPS.items() for i in range(entry['count'])]
    picks = [0, 8, 28, 36, 52, 21]  # idle, walk, work (strike), sledge (impact), sit, stand
    if quick:
        jobs = [j for j in jobs if j[1] in picks]
    print('Rendering', len(jobs), 'Torben poses', flush=True)
    arr = render_all(jobs)
    if quick:
        contact(arr, sys.argv[2], picks); print('quick sheet written', flush=True); return
    write_array(ROOT / 'characters/torben.png', arr)
    glow = np.zeros_like(arr)
    for s in range(8):
        for i in range(FRAMES):
            glow[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = glow_of(arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW])
    write_array(ROOT / 'characters/torben_glow.png', glow)
    (ROOT.parent / 'data/torben_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': FRAMES, 'rows': 8, 'height': 55, 'clips': CLIPS}, indent=2) + '\n')
    if len(sys.argv) > 1:
        contact(arr, sys.argv[1], [0, 8, 28, 36, 52, 69])
    print('Torben sheet, glow sheet and rig written', flush=True)


if __name__ == '__main__':
    main()
