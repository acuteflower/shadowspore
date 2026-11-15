"""Hallgrat's six core residents (docs/hallgrat_bewohner_konzept.md 2, 10). Eight true directions each.

    py -3 tools/art_hallgrat_people.py [contact.png]          writes assets/characters/hallgrat_<id>.png (+ _glow.png) and data/hallgrat_<id>_rig.json
    py -3 tools/art_hallgrat_people.py quick out.png [ids]    renders a few poses of each (or of the named ones) for a fast look, writes nothing else
    py -3 tools/art_hallgrat_people.py only brann,pim         renders only these

Built from ellipsoids with the heroine's renderer (the same grain, ink and outline rules as Ellie, Gustav, Torben, Jorun, Esma, Ilva), in the settlers'
frame and rig format (76x96, feet (38, 80)), so `HallgratResident` plays them like `InteriorResident` plays the witches. One shared body with
clothes, hair and tools per person:

* BRANN, the gate warden: an old soldier, upright and lean; short iron-grey hair, a scar over one brow; a padded gambeson in the town's slate blue under a
  worn mail shirt, a faded wine-red half-cloak on her left shoulder, a belt with a horn, a long spear she plants beside her.
* ILVANE, keeper of the Wächterin: long pale robe of bone and lilac down to the ground, a teal stole, long silver-white hair loose down her back;
  sweeps the forum with a birch broom, kneels before the statue, carries a candle (the flame glows).
* ODRIK "Meißelbart", the stonemason: broad and heavy, a long grey beard in two braids, a leather cap, rolled sleeves over strong forearms, a long
  leather apron dusty with stone; hammer and chisel.
* TAMSA, the glass grinder: young, quick, a bun of copper-red hair with a pencil through it, goggles pushed up on her forehead, a teal smock over a
  dark shirt, leather gloves; she grinds a little crystal (sparks glow), and runs.
* PIM, the lamp boy (14): small, a flat cap over brown curls, a mustard jacket a size too big, a soot smudge; polishes a lantern glass, raises the
  lighting pole whose wick glows; runs.
* HEDDA, the innkeeper: sturdy, a headscarf over brown hair, a wine-red dress with rolled sleeves and a cream apron; sweeps the step, carries a tray
  with two mugs.

Clips (each figure): idle 4, walk 6, talk 4, wave 6 + its own (see SPECIAL)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 76, 96, 80
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
NAMES = ['SKIN_L', 'SKIN_W', 'SKIN_T', 'LIP', 'BROW_D', 'BROW_G',
         'GREY', 'SILVER_H', 'COPPER', 'BROWN_H', 'CURLS',
         'SLATE', 'MAIL', 'WINE', 'BONE', 'LILAC', 'TEAL', 'LEATHER', 'LEATHER_D', 'TROUSER', 'BOOTS', 'IRON', 'BRASS', 'WOOD', 'STRAW',
         'CREAM', 'MUSTARD', 'SHIRT', 'DUST', 'GLASS', 'FLAME', 'CLAY', 'SCARF']
for k, n in enumerate(NAMES):
    globals()[n] = BASE + k
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['7a4a48', 'b8806a', 'dca888', 'f2caa8'],  # SKIN_L light skin
    ['6e4234', 'a46a50', 'cc9270', 'ecb894'],  # SKIN_W warm skin
    ['5e3a2a', '8e5a40', 'b67c5a', 'd8a07a'],  # SKIN_T weathered, tanned
    ['6a2a38', '9a4a52', 'bc6a6a', 'dc928a'],  # LIP
    ['1e140e', '3a281c', '5a4030', '7a5a44'],  # BROW_D dark brows
    ['3a3840', '5e5c66', '8a8892', 'b4b2ba'],  # BROW_G grey brows
    ['3a3842', '62606c', '8e8c98', 'bcbac4'],  # GREY iron-grey hair, Odrik's beard
    ['6e6a86', 'a4a2ba', 'd2d0e2', 'f6f4ff'],  # SILVER_H Ilvane's silver-white hair
    ['5a1e10', '8e3418', 'c05828', 'e8884a'],  # COPPER Tamsa's red hair
    ['24160e', '402818', '603e24', '845a36'],  # BROWN_H brown hair
    ['2a1a10', '4a2e1a', '6e4628', '946438'],  # CURLS Pim's curls
    ['1a2030', '2a3448', '3e4c66', '5a6c88'],  # SLATE the town's slate blue (gambeson)
    ['2a2c36', '4a4e5c', '767c8c', 'a8aebc'],  # MAIL worn mail
    ['3a0e18', '5e1a26', '842a36', 'a84650'],  # WINE faded wine red
    ['56506c', '8a8698', 'bcb6bc', 'e2dccc'],  # BONE
    ['3a3050', '5a4c78', '8270a0', 'ae9cc8'],  # LILAC
    ['123a3c', '1e5a5a', '2e8480', '5ab8aa'],  # TEAL
    ['2a1810', '462a1a', '664028', '885a3a'],  # LEATHER
    ['180e08', '2a1a10', '40281a', '583a26'],  # LEATHER_D
    ['14121a', '24202c', '383242', '504858'],  # TROUSER
    ['120c0a', '241814', '382820', '503c30'],  # BOOTS
    ['22242c', '3e424e', '666c7a', '9aa2b2'],  # IRON
    ['4a3418', '7a5a24', 'b4893a', 'e6c468'],  # BRASS
    ['2a1c12', '4a3220', '6e4c30', '927048'],  # WOOD
    ['5a4a20', '8a7432', 'b89c4a', 'e2c870'],  # STRAW (broom)
    ['6a604e', '9c927a', 'c8bea2', 'ece4cc'],  # CREAM apron
    ['5a3e10', '8a6018', 'b8862a', 'e0b44a'],  # MUSTARD
    ['181620', '2a2634', '403a4c', '5a5266'],  # SHIRT dark shirt
    ['4e4a52', '76707a', '9e98a0', 'c6c0c4'],  # DUST stone dust on Odrik's apron
    ['2e5a6a', '4a8aa0', '86c8d8', 'd8f6ff'],  # GLASS
    ['c26a1a', 'ffa83a', 'ffd27a', 'fff6d0'],  # FLAME (emissive)
    ['5a2e1e', '8a4a2e', 'b06a44', 'd48e62'],  # CLAY mugs
    ['3e3a1a', '62602a', '8a8840', 'b4b462'],  # SCARF olive headscarf
]]
SOFT = (SKIN_L, SKIN_W, SKIN_T, GREY, SILVER_H, COPPER, BROWN_H, CURLS)
_shade = h.shade_band


def shade_band(lam, kind, mat):
    if mat in SOFT:
        return np.digitize(lam, (-0.12, 0.16, 0.6) if mat not in (SKIN_L, SKIN_W, SKIN_T) else (-0.2, 0.12, 0.55))
    return _shade(lam, kind, mat)


h.shade_band = shade_band
V = lambda *x: np.array(x, float)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def hair_open(q):
    """A hair cap that leaves the face free (a parting, drawn back to the temples)."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.05) & (y < 0.45 - 0.42 * np.abs(x) ** 1.6) & (np.abs(x) < 0.86)
    return (y > -0.35) & ~opening


def hair_short(q):
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > 0.1) & (y < 0.55 - 0.35 * np.abs(x) ** 1.4) & (np.abs(x) < 0.9)
    return (y > -0.2) & ~opening


COMMON = [('idle', 4, 3), ('walk', 6, 8), ('talk', 4, 5), ('wave', 6, 7)]
SPECIAL = {
    'brann': [('guard', 4, 2), ('halt', 4, 4)],
    'ilvane': [('sweep', 6, 5), ('kneel', 4, 2), ('candle', 4, 3)],
    'odrik': [('chisel', 6, 6)],
    'tamsa': [('grind', 6, 7), ('run', 6, 12)],
    'pim': [('polish', 6, 6), ('light', 6, 5), ('run', 6, 12)],
    'hedda': [('sweep', 6, 5), ('serve', 4, 3)],
}
STRIKES = {'chisel': 3}
LOOK = {  # scale, shoulder half-width, hip width, skin, eye colours
    'brann': dict(scale=1.02, sh=5.8, skin=SKIN_T, eye=('140e0e', '3a3a4a', '6a6a80', 'f2ece2'), height=60),
    'ilvane': dict(scale=1.0, sh=5.2, skin=SKIN_L, eye=('101418', '2a4a5a', '4a7a8a', 'f6f2ea'), height=58),
    'odrik': dict(scale=1.06, sh=7.0, skin=SKIN_T, eye=('120c08', '3a2414', '6a4426', 'f2ece2'), height=62),
    'tamsa': dict(scale=0.95, sh=5.0, skin=SKIN_L, eye=('101810', '2a4a2a', '4a7a3e', 'f6efe6'), height=55),
    'pim': dict(scale=0.84, sh=4.8, skin=SKIN_W, eye=('140e08', '3e2a14', '6a4a26', 'f6efe6'), height=49),
    'hedda': dict(scale=1.0, sh=6.4, skin=SKIN_W, eye=('140e08', '3a2414', '6a4426', 'f2ece2'), height=58),
}
SKIRT = {'ilvane': 'robe', 'hedda': 'dress'}


def clips_of(who):
    out, start = {}, 0
    for name, count, fps in COMMON + SPECIAL[who]:
        out[name] = {'start': start, 'count': count, 'fps': fps}
        if name in STRIKES:
            out[name]['strike'] = STRIKES[name]
        start += count
    return out, start


def pose(kind, i, n):
    p = dict(feet=((2.4, 0, 0), (-2.4, 0, 0)), breath=0.3, lean=.03, swing=0.0, t=0.0, head=0.0, drop=0.0)
    u = i / max(n, 1)
    if kind in ('walk', 'run'):
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        stride, lift = (3.4, 1.8) if kind == 'walk' else (5.0, 3.2)
        p.update(feet=((2.3, stride * s, lift * max(c, 0)), (-2.3, -stride * s, lift * max(-c, 0))), lean=.06 if kind == 'walk' else .2, swing=s * (1 if kind == 'walk' else 1.5))
    elif kind == 'talk':
        p.update(t=[0, .6, 1, .4][i], breath=[.2, .5, .7, .4][i], head=[0, .04, .02, -.02][i])
    elif kind in ('wave', 'halt'):
        p.update(t=[0, .6, 1, .8, 1, .7][i] if kind == 'wave' else [.6, .9, 1, .9][i], breath=.4)
    elif kind == 'guard':
        p.update(breath=[0, .45, .85, .45][i], head=[0, .03, 0, -.03][i])
    elif kind == 'sweep':
        p.update(feet=((2.8, 1.0, 0), (-2.4, -1.0, 0)), lean=.16, t=math.sin(math.tau * u), head=.12)
    elif kind == 'kneel':
        p.update(drop=8.5, lean=.12, breath=[0, .45, .85, .45][i], head=.2)
    elif kind == 'candle':
        p.update(breath=[0, .45, .85, .45][i], head=.14, t=u)
    elif kind == 'chisel':
        p.update(feet=((2.8, 1.2, 0), (-2.6, -0.8, 0)), lean=.2, t=[0, .5, 1, .1, .3, .15][i], head=.25)
    elif kind == 'grind':
        p.update(feet=((2.6, 0.8, 0), (-2.4, -0.6, 0)), lean=.18, t=u, head=.28)
    elif kind == 'polish':
        p.update(lean=.08, t=u, head=.3)
    elif kind == 'light':
        p.update(t=[0, .35, .75, 1, 1, .6][i], head=-.25, breath=.4)
    elif kind == 'serve':
        p.update(breath=[0, .45, .85, .45][i], lean=-.02)
    else:
        p.update(breath=[0, .45, .85, .45][i % 4])
    return p


def build(who, p, kind):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    look = LOOK[who]
    skin = look['skin']
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None))
    d = p['drop']
    off = V(0, drop - d, 0)
    sw = p['swing']
    t = p['t']
    skirt = SKIRT.get(who)
    # ---------------------------------------------------------------- legs
    if d > 0:  # kneeling (only Ilvane, under her robe): one knee down, the other foot planted ahead; the robe hides the rest
        limb(V(2.5, 15.5, 0.4), V(2.5, 10.0, 6.0), 2.6, 2.3, TROUSER)
        limb(V(2.5, 10.0, 6.0), V(2.6, 2.4, 6.4), 2.3, 2.1, TROUSER)
        limb(V(-2.5, 15.5, 0.4), V(-2.6, 2.0, 2.4), 2.6, 2.3, TROUSER)
        limb(V(-2.6, 2.0, 2.4), V(-2.6, 2.4, -6.0), 2.3, 2.1, TROUSER)
        ell(V(2.6, 1.2, 7.4), (1.8, 1.4, 3.0), BOOTS)
    else:
        for hip, knee, ankle, *_ in legs:
            trouser = TROUSER if who != 'odrik' else LEATHER_D
            limb(hip, knee, 2.7, 2.4, trouser)
            limb(knee, ankle, 2.4, 2.1, trouser if who in ('pim', 'tamsa') else BOOTS)
            if who in ('brann', 'odrik'):
                ell(knee + V(0, -0.6, 0.4), (2.6, 0.9, 2.6), BOOTS)  # boot tops
            ell(ankle + V(0, -0.6, 1.0), (2.3, 1.8, 3.4), BOOTS)
            ell(ankle + V(0, -1.2, 3.4), (1.8, 1.0, 1.8), BOOTS)
    m.off = off
    R = h.rot_x(p['lean']); b = p['breath']
    sh = look['sh']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    # ---------------------------------------------------------------- skirts and robes
    if skirt:
        hem = 3.0 if skirt == 'robe' else 7.0
        main = LILAC if who == 'ilvane' else WINE
        for k in range(10):
            u = k / 9.0
            y = 27.0 - (27.0 - hem - (d * 0.4 if d else 0)) * u
            flare = (4.6 + 4.0 * u ** 0.8) * (1.15 if d else 1.0)
            ell(V(sw * 0.7 * u ** 2, y, 0.3 + (1.6 * u if d else 0)), (flare, 1.7, flare * 0.88), main if (who == 'hedda' or k < 8) else BONE)
        if who == 'ilvane':  # the bone-coloured front panel and the teal stole hanging down
            ribbon([V(0, 27.0, 4.6), V(sw * .2, 18.0, 7.0), V(sw * .4, hem + 1.0, 8.4 + (3 if d else 0))], [3.0, 3.6, 4.2], 0.6, BONE, (0, 0, 1), kind='')
    if who == 'hedda':  # the cream apron over the dress
        ribbon([T((0, 30.0, 4.6)), V(sw * .3, 20.0, 7.2), V(sw * .5, 9.0, 8.0)], [3.2, 4.4, 4.8], 0.6, CREAM, (0, 0, 1), kind='')
    if who == 'odrik':  # the long leather apron, dusty
        ribbon([T((0, 37.0, 5.4)), T((0, 28.0, 6.0)), V(sw * .2, 14.0, 5.8 + sw * .2)], [3.6, 5.0, 5.2], 0.7, LEATHER, (0, 0, 1), kind='')
        for k, (x, y) in enumerate(((1.6, 24.0), (-2.4, 19.0), (0.8, 16.0), (-1.0, 29.0))):
            ell(V(x, y, 6.6), (1.0, 0.8, 0.3), DUST)
    if who == 'tamsa':  # the teal smock to mid-thigh
        for k in range(5):
            u = k / 4.0
            ell(T((sw * 0.4 * u, 27.0 - 8.0 * u, 0.4)), (4.6 + 1.4 * u, 1.6, 3.8 + 1.0 * u), TEAL)
    # ---------------------------------------------------------------- torso
    body = {'brann': SLATE, 'ilvane': LILAC, 'odrik': SHIRT, 'tamsa': TEAL, 'pim': MUSTARD, 'hedda': WINE}[who]
    w = sh / 6.0
    ell(T((0, 27.6, 0.3)), (5.0 * w, 2.8, 4.0 * w), body, R=R)
    ell(T((0, 31.4, 0.4)), (4.8 * w, 3.4, 3.8 * w), body, R=R)
    ell(T((0, 35.4 + b * .12, 0.5)), (5.6 * w, 3.0, 4.0 * w), body, R=R)
    if who == 'brann':  # the mail shirt over the gambeson, the belt with a horn
        for k in range(3):
            ell(T((0, 26.6 + k * 2.6, 0.4)), (5.4 * w, 1.4, 4.4 * w), MAIL, R=R)
        for a in np.linspace(0, 2 * math.pi, 15)[:-1]:
            ell(T((math.cos(a) * 5.4 * w, 25.8, 0.4 + math.sin(a) * 4.4 * w)), (1.0, 0.7, 0.9), LEATHER, R=R)
        ell(T((0, 25.8, 4.8)), (1.0, 0.8, 0.4), IRON, R=R)
        ell(T((5.6, 24.4, 1.6)), (1.0, 1.0, 2.2), BONE, R=R @ h.rot_y(.5))  # the horn
    elif who == 'odrik':
        for a in np.linspace(0, 2 * math.pi, 15)[:-1]:
            ell(T((math.cos(a) * 5.6 * w, 26.2, 0.4 + math.sin(a) * 4.4 * w)), (1.0, 0.7, 0.9), LEATHER_D, R=R)
        if kind != 'chisel':  # the hammer hangs from his belt
            limb(T((-5.6, 26.0, 2.6)), T((-5.8, 19.0, 3.2)), 0.5, 0.5, WOOD)
            ell(T((-5.8, 18.4, 3.2)), (1.6, 1.0, 1.0), IRON, R=R)
    elif who == 'tamsa':
        for a in np.linspace(0, 2 * math.pi, 13)[:-1]:
            ell(T((math.cos(a) * 4.8 * w, 27.4, 0.4 + math.sin(a) * 3.9 * w)), (0.9, 0.6, 0.8), LEATHER_D, R=R)
        ell(T((4.4, 25.6, 2.2)), (1.3, 1.6, 1.0), LEATHER, R=R)  # a pouch of stones
    elif who == 'pim':
        for k in range(3):  # the jacket's big brass buttons, a size too big
            ell(T((0.4, 34.0 - k * 2.6, 4.2 * w + 0.4)), (0.5, 0.5, 0.3), BRASS, R=R)
        ell(T((0, 25.4, 0.4)), (4.8 * w, 2.4, 4.0 * w), MUSTARD, R=R)  # the jacket's long hem
        ell(T((-3.6, 24.6, 2.8)), (1.0, 1.6, 0.9), LEATHER, R=R)  # a rag hanging from a pocket
    elif who == 'hedda':
        ell(T((0, 36.6, 2.8)), (3.6, 1.2, 1.6), CREAM, R=R)  # the neckline of her blouse
    if who == 'ilvane':  # the teal stole over the shoulders, both ends down the front
        for sx in (-1, 1):
            ribbon([T((sx * 2.8, 38.4, 2.4)), T((sx * 2.4, 32.0, 4.6)), T((sx * 2.2, 25.0, 4.9)), V(sx * 2.0 + sw * .3, 17.0, 6.6 + (2 if d else 0))],
                   [1.6, 1.7, 1.7, 1.8], 0.5, TEAL, (0, 0, 1), kind='')
    limb(T((0, 38.4, 0.2)), T((0, 40.2, 0.4)), 1.8 * w + 0.2, 1.7 * w + 0.2, skin)
    # shoulders; Brann's half-cloak
    for sx in (-1, 1):
        ell(T((sx * sh, 36.6, 0.0)), (2.5, 2.5, 2.9), body, R=R)
    if who == 'brann':
        ell(T((sh * 0.9, 37.6, 0.2)), (3.2, 1.6, 3.6), WINE, R=R)
        for k, x in enumerate((1.0, 3.2, 5.4)):
            ribbon([T((x, 38.0, -3.2)), T((x * 1.15, 31.0, -4.6 - sw * .2)), V(x * 1.2 + sw * .3, 22.0 + (k % 2), -5.2 - sw * .5)], [2.2, 2.6, 2.4], 0.6,
                   WINE, (0.3, 0, -1), kind='')
    # ---------------------------------------------------------------- arms and hands
    hands = {}
    for side in (-1, 1):  # -1 = their right
        shoulder = T((side * sh, 36.2, 0.2))
        hand = T((side * (sh + 0.8), 25.6, side * sw * 2.0 + 0.6))
        el = None
        if kind == 'talk' and side < 0:
            hand = T((-sh - 1.0 - 1.5 * t, 26.0 + 6.5 * t, 1.0 + 5.0 * t))
        elif kind == 'wave' and side > 0:
            hand = T((sh + 2.2 + (1.4 if p.get('i', 0) % 2 else -0.8) * t, 32.0 + 13.0 * t, 2.4))
        elif kind == 'halt' and side > 0:
            hand = T((sh * 0.6, 33.0 + 6.0 * t, 6.0 + 4.0 * t))
        elif who == 'brann' and side < 0 and kind not in ('talk',):  # the spear hand
            hand = T((-sh - 2.2, 29.5, 2.8 + (sw * 1.0 if kind == 'walk' else 0)))
        elif kind == 'guard' and side > 0:
            hand = T((sh * 0.8, 26.4, 3.6))
        elif kind == 'sweep':
            hand = T((t * 2.2 + side * 0.6, 25.0 + (5.5 if side < 0 else 0.6), 6.4 + (1.2 if side < 0 else 2.6)))
        elif kind == 'kneel':
            hand = T((side * 1.0, 33.6, 5.6))
        elif kind == 'candle':
            hand = T((side * 1.4, 30.4, 6.4))
        elif kind == 'chisel':
            if side > 0:
                hand = T((1.6, 25.6, 9.2))  # the chisel hand, low and forward
            else:
                hand = T((-2.2, 27.0 + 9.0 * t, 7.2 - 2.2 * t))
        elif kind == 'grind':
            a = math.tau * t
            hand = T((side * 1.8 + math.sin(a) * 0.8, 27.6 + math.cos(a) * 0.6 * side, 8.4))
        elif kind == 'polish':
            if side > 0:
                hand = T((1.6, 29.6, 6.6))
            else:
                a = math.tau * t
                hand = T((0.0 + math.cos(a) * 1.2, 30.6 + math.sin(a) * 1.2, 8.0))
        elif kind == 'light':
            hand = T((side * 1.0 - 1.2, 30.0 + 9.0 * t + (2.0 if side < 0 else 0), 4.0 + 3.0 * t))
        elif kind == 'serve':
            hand = T((side * 3.4, 30.4 + b * 0.3, 7.2))
        if el is None:
            mid = (shoulder + hand) / 2
            el = mid + V(side * 1.6, -1.2, -1.4)
        hands[side] = hand
        sleeve = body if who not in ('odrik',) else SHIRT
        rolled = who in ('odrik', 'hedda', 'tamsa')
        limb(shoulder, el, 2.2, 2.0, sleeve)
        limb(el, hand, 1.9, 1.7, skin if rolled else sleeve)
        if rolled:
            ell(el + (hand - el) * 0.12, (2.1, 1.0, 2.1), sleeve)
        dd = (hand - el) / np.linalg.norm(hand - el)
        glove = who == 'tamsa' and kind == 'grind'
        ell(hand + dd * .5, (1.6, 1.8, 1.5), LEATHER if glove else skin)
        ell(hand + dd * .3 + V(side * -0.8, 0, 0.9), (.6, .9, .6), LEATHER if glove else skin)
    # ---------------------------------------------------------------- tools
    if who == 'brann':
        hr = hands[-1] if kind != 'talk' else T((-sh - 2.2, 29.5, 2.8))
        foot = V(hr[0], 0.4, hr[2] + 0.4)
        top = V(hr[0] + 0.2, 64.0, hr[2] - 0.6)
        limb(foot, top, 0.6, 0.55, WOOD)
        ell(top + V(0, 2.2, 0), (0.9, 2.6, 0.5), IRON)
        ell(top + V(0, -0.4, 0), (1.0, 0.5, 1.0), BRASS)
        ell(top + V(0, -1.6, 0), (0.6, 1.2, 0.3), WINE)  # a red pennon tuft
    if kind == 'sweep':
        hc_ = (hands[-1] + hands[1]) / 2
        a = hands[-1] + (hands[-1] - hands[1]) * 0.4
        foot = V(hc_[0] + 4.5 + t * 3.0, 0.8, hc_[2] + 2.0)
        limb(a, foot, 0.5, 0.5, WOOD)
        for k in range(7):
            ell(foot + V(-1.8 + k * 0.6, -0.2, 0.6 * math.sin(k)), (0.6, 1.6, 0.6), STRAW, R=rot_z((k - 3) * 0.12))
    if kind == 'candle':
        c = (hands[-1] + hands[1]) / 2 + V(0, 1.4, 0.6)
        ell(c, (0.9, 2.0, 0.9), BONE)
        ell(c + V(0, 2.6, 0), (0.55, 1.0, 0.55), FLAME, kind='emit')
        ell(c + V(0, 3.6, 0), (0.3, 0.6, 0.3), FLAME, kind='emit')
    if kind == 'kneel':  # a candle stands on the ground before her
        ell(V(-3.0, 1.8, 9.0), (0.8, 1.8, 0.8), BONE)
        ell(V(-3.0, 4.2, 9.0), (0.5, 0.9, 0.5), FLAME, kind='emit')
    if kind == 'chisel':
        ch = hands[1]
        limb(ch + V(-0.4, 1.2, 0.4), ch + V(-0.6, -3.6, 1.8), 0.35, 0.3, IRON)
        hd = hands[-1]
        dr = V(.5, -.2, .8); dr /= np.linalg.norm(dr)
        limb(hd - dr * 1.0, hd + dr * 4.0, .45, .45, WOOD)
        ell(hd + dr * 4.4, (1.4, 1.0, 1.0), IRON)
        if t < 0.15 and p['lean'] > 0:  # the blow lands: chips fly
            for dx, dy in ((-1.2, 0.8), (1.4, 1.2), (0.2, 2.0)):
                ell(ch + V(-0.6 + dx, -3.8 + dy, 2.2), (.35, .35, .35), DUST)
    if kind == 'grind':
        c = (hands[-1] + hands[1]) / 2 + V(0, 1.0, 1.0)
        ell(c, (0.9, 1.2, 0.9), GLASS)
        a = math.tau * t
        for k in range(3):
            if (k + int(t * 6)) % 2 == 0:
                ell(c + V(math.cos(a + k * 2.1) * 2.4, 0.8 + k * 0.7, math.sin(a + k * 2.1) * 1.4 + 1.0), (.3, .3, .3), FLAME, kind='emit')
    if kind == 'polish':
        c = hands[1] + V(-0.6, 1.8, 0.8)
        ell(c, (1.4, 1.8, 1.4), GLASS)
        ell(c + V(0, 2.0, 0), (1.2, 0.5, 1.2), IRON)
        ell(c + V(0, -1.8, 0), (1.3, 0.5, 1.3), IRON)
    if kind == 'light':
        base = (hands[-1] + hands[1]) / 2
        tip = base + V(-1.0, 14.0 + 6.0 * t, 6.0 + 4.0 * t)
        limb(base + V(0.4, -6.0, -2.0), tip, 0.45, 0.4, WOOD)
        ell(tip, (0.6, 0.9, 0.6), BRASS)
        ell(tip + V(0, 1.2, 0), (0.5, 0.8, 0.5), FLAME, kind='emit')
    if kind == 'serve':
        c = (hands[-1] + hands[1]) / 2 + V(0, 0.8, 0.6)
        ell(c, (4.6, 0.4, 3.0), WOOD)
        for x in (-1.8, 1.8):
            ell(c + V(x, 1.8, 0), (1.1, 1.6, 1.1), CLAY)
            ell(c + V(x, 3.5, 0), (1.0, 0.4, 1.0), CREAM)  # the froth
    # ---------------------------------------------------------------- head
    Rh = R @ h.rot_x(p['head'])
    Ro = Rh * 1.1
    hc = T((0, 44.2 + b * .2, .5))
    ell(hc, (4.8, 5.2, 4.7), skin, R=Rh, kind='head')
    brow = BROW_G if who in ('brann', 'odrik') else BROW_D
    for side in (-1, 1):
        ell(hc + Ro @ V(side * 1.9, 1.2, 4.1), (1.4, .4, .5), brow, R=Rh @ rot_z(side * -.1))
        ell(hc + Ro @ V(side * 4.6, 0.0, 0.4), (0.8, 1.3, 0.9), skin, R=Rh)
    ell(hc + Ro @ V(0, -1.0, 4.45), (.6, .85, .5), skin, R=Rh)  # nose
    ell(hc + Ro @ V(0, -2.9, 3.85), (1.0, .4, .45), LIP, R=Rh)
    ell(hc + Ro @ V(0, -4.3, 2.9), (1.8, 1.0, 1.6), skin, R=Rh)  # chin
    if who == 'brann':
        ell(hc + Ro @ V(0, .5, -.5), (5.1, 5.3, 5.0), GREY, R=Rh, kind='hair', tag=3.0, clip=hair_short)
        ell(hc + Ro @ V(-2.2, 2.0, 4.3), (0.25, 1.4, 0.3), SKIN_W, R=Rh @ rot_z(.3))  # the scar over her right brow
        ell(hc + Ro @ V(0, -2.4, -3.8), (2.6, 2.0, 1.8), GREY, R=Rh, kind='hair', tag=4.0)  # a short knot at the nape
    elif who == 'ilvane':
        ell(hc + Ro @ V(0, .5, -.4), (5.2, 5.6, 5.1), SILVER_H, R=Rh, kind='hair', tag=3.0, clip=hair_open)
        for k, x in enumerate((-3.6, -1.8, 0.0, 1.8, 3.6)):  # the long hair down her back
            lag = -sw * (0.4 + 0.15 * abs(k - 2))
            ribbon([hc + Ro @ V(x * .9, 3.0, -3.3), hc + Ro @ V(x * 1.08, -2.4, -4.5), T((x * 1.2, 34.0, -4.8 + lag)), T((x * 1.15, 27.0, -4.8 + lag * 1.6)), T((x * .9, 20.0 - (k % 2), -4.2 + lag * 2.2))],
                   [2.0, 2.4, 2.4, 2.0, 1.0], .9, SILVER_H, (0, 0, -1), tag=float(20 + k))
        for side in (-1, 1):
            ribbon([hc + Ro @ V(side * 4.0, -0.5, 1.4), T((side * 4.4, 38.0, 2.0)), T((side * 4.0, 32.0, 3.6))], [1.4, 1.6, 0.8], .8, SILVER_H, (side * .5, 0, 1), tag=side + 11.0)
        ell(hc + Ro @ V(0, 4.0, 3.2), (2.6, 0.5, 0.6), TEAL, R=Rh)  # a thin teal band across her brow
    elif who == 'odrik':
        ell(hc + Ro @ V(0, .3, -.6), (5.1, 5.2, 5.0), GREY, R=Rh, kind='hair', tag=3.0, clip=hair_short)
        for k in range(11):  # the full beard along the jaw
            a = math.pi * (0.08 + 0.84 * k / 10)
            ell(hc + Ro @ V(math.cos(a) * 4.0, -3.0 - math.sin(a) * 1.8, 1.6 + math.sin(a) * 2.4), (1.6, 1.7, 1.4), GREY, R=Rh, kind='hair', tag=5.0 + (k % 2))
        ell(hc + Ro @ V(0, -2.3, 4.5), (2.0, .55, .55), GREY, R=Rh)  # moustache
        for side in (-1, 1):  # the two long braids of his beard, down over the apron
            top = hc + Ro @ V(side * 1.4, -5.2, 3.6)
            pts = [top, T((side * 1.6, 37.0, 5.6)), T((side * 1.5, 32.5, 6.4)), T((side * 1.3, 28.6, 6.6 + sw * .2))]
            for k in range(3):
                for j in range(3):
                    q = pts[k] + (pts[k + 1] - pts[k]) * (j / 3.0)
                    ell(q, (1.1, 1.0, 0.9), GREY, kind='hair', tag=30.0 + k + side)
            ell(pts[-1] + V(0, -0.8, 0.2), (0.6, 0.5, 0.5), BRASS)  # a brass bead at each end
        cap = hc + Ro @ V(0, 3.6, -0.4)  # the leather cap
        ell(cap, (5.2, 2.2, 5.0), LEATHER, R=Rh)
        ell(cap + Ro @ V(0, -1.6, 2.6), (5.0, 0.5, 3.4), LEATHER_D, R=Rh)  # its short peak
    elif who == 'tamsa':
        ell(hc + Ro @ V(0, .5, -.4), (5.2, 5.6, 5.1), COPPER, R=Rh, kind='hair', tag=3.0, clip=hair_open)
        bun = hc + Ro @ V(0, 3.8, -3.8)
        ell(bun, (2.6, 2.4, 2.4), COPPER, R=Rh, kind='hair', tag=4.0)
        limb(bun + Ro @ V(-2.8, 1.2, 0), bun + Ro @ V(2.8, -1.0, 0.2), 0.3, 0.3, WOOD)  # a pencil through the bun
        for side in (-1, 1):  # loose strands at the temples
            ribbon([hc + Ro @ V(side * 3.8, 1.0, 2.6), hc + Ro @ V(side * 4.4, -2.0, 2.8), hc + Ro @ V(side * 4.0, -4.0, 2.4)], [0.9, 0.8, 0.4], .6, COPPER, (side, 0, 1), tag=side + 8.0)
        gog = hc + Ro @ V(0, 3.4, 3.4)  # the goggles pushed up on her forehead
        for side in (-1, 1):
            ell(gog + Ro @ V(side * 1.7, 0, 0.6), (1.4, 1.1, 0.7), GLASS, R=Rh)
            ell(gog + Ro @ V(side * 1.7, 0, 0.2), (1.6, 1.3, 0.6), BRASS, R=Rh)
        for a in np.linspace(0, 2 * math.pi, 15)[:-1]:
            ell(hc + Ro @ V(math.cos(a) * 5.2, 3.2, math.sin(a) * 5.0), (0.8, 0.5, 0.8), LEATHER_D, R=Rh)
    elif who == 'pim':
        ell(hc + Ro @ V(0, .3, -.5), (5.1, 5.4, 5.0), CURLS, R=Rh, kind='hair', tag=3.0, clip=hair_short)
        for k in range(7):  # curls poking out under the cap
            a = math.pi * (0.1 + 0.8 * k / 6)
            ell(hc + Ro @ V(math.cos(a) * 4.8, 1.4 - 0.6 * (k % 2), -math.sin(a) * 2.4 + 1.6), (1.2, 1.2, 1.2), CURLS, R=Rh, kind='hair', tag=5.0 + k)
        cap = hc + Ro @ V(0.4, 3.6, 0.2)  # the flat cap, its peak forward
        ell(cap, (5.6, 1.6, 5.4), SLATE, R=Rh)
        ell(cap + Ro @ V(0, -0.6, 4.4), (3.6, 0.5, 2.4), SLATE, R=Rh)
        ell(hc + Ro @ V(2.6, -1.8, 3.8), (0.8, 0.5, 0.3), LEATHER_D, R=Rh)  # a soot smudge on his cheek
    elif who == 'hedda':
        ell(hc + Ro @ V(0, .5, -.4), (5.2, 5.6, 5.1), BROWN_H, R=Rh, kind='hair', tag=3.0, clip=hair_open)
        scarf = hc + Ro @ V(0, 2.4, -0.8)  # the headscarf, knotted at the nape
        ell(scarf, (5.5, 3.6, 5.3), SCARF, R=Rh, clip=lambda q: q[..., 1] > -0.1)
        ell(hc + Ro @ V(0, 0.6, -5.2), (1.6, 1.4, 1.2), SCARF, R=Rh)
        for side in (-1, 1):
            ribbon([hc + Ro @ V(side * 0.6, 0.4, -5.6), hc + Ro @ V(side * 1.6, -3.4, -5.8)], [1.0, 0.6], .5, SCARF, (side, 0, -1), kind='')
    return m


def render_one(job):
    who, sector, index, kind, i, n = job
    look = LOOK[who]
    h.SCALE = look['scale']
    h.RAMPS[h.EYE] = tuple(hexc(c) for c in look['eye'])
    p = pose(kind, i, n); p['i'] = i
    model = build(who, p, kind)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return who, sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


def glow_of(arr):
    cols = {tuple(c[:3]) for c in h.RAMPS[FLAME]}
    flat = arr.reshape(-1, 4)
    keep = np.array([tuple(int(v) for v in px[:3]) in cols and px[3] > 0 for px in flat])
    out = np.zeros_like(flat); out[keep] = flat[keep]
    return out.reshape(arr.shape)


def contact(sheets, path, scale=2):
    from PIL import Image
    rows = []
    for who, arr in sheets.items():
        clips, frames = clips_of(who)
        picks = [c['start'] + (c['count'] // 2 if name != 'idle' else 0) for name, c in clips.items()]
        for s in (2, 1, 0, 6):
            rows.append([arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] for i in picks])
    width = max(len(r) for r in rows)
    canvas = Image.new('RGB', (width * FW * scale, len(rows) * FH * scale), (26, 24, 36))
    for y, r in enumerate(rows):
        for x, a in enumerate(r):
            tile = Image.new('RGBA', (FW, FH), (26, 24, 36, 255)); tile.alpha_composite(Image.fromarray(a))
            canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (x * FW * scale, y * FH * scale))
    canvas.save(path)


def main():
    args = sys.argv[1:]
    quick = bool(args) and args[0] == 'quick'
    who_list = list(LOOK)
    if quick and len(args) > 2:
        who_list = args[2].split(',')
    if args and args[0] == 'only':
        who_list = args[1].split(',')
    jobs = []
    for who in who_list:
        clips, frames = clips_of(who)
        for kind, c in clips.items():
            for i in range(c['count']):
                if quick and i != c['count'] // 2:
                    continue
                for s in range(8):
                    if quick and s not in (2, 1, 0, 6):
                        continue
                    jobs.append((who, s, c['start'] + i, kind, i, c['count']))
    sheets = {who: np.zeros((8 * FH, clips_of(who)[1] * FW, 4), dtype=np.uint8) for who in who_list}
    print('Rendering', len(jobs), 'poses of', ', '.join(who_list), flush=True)
    with mp.Pool(min(8, os.cpu_count() or 1)) as pool:
        for who, s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            sheets[who][s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(sheets, args[1])
        print('quick sheet written', flush=True)
        return
    for who, arr in sheets.items():
        clips, frames = clips_of(who)
        write_array(ROOT / ('characters/hallgrat_%s.png' % who), arr)
        write_array(ROOT / ('characters/hallgrat_%s_glow.png' % who), glow_of(arr))
        rig = {'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': frames, 'rows': 8, 'height': LOOK[who]['height'], 'clips': clips}
        (ROOT.parent / ('data/hallgrat_%s_rig.json' % who)).write_text(json.dumps(rig, indent=2) + '\n')
    if args and args[0] not in ('only',):
        contact(sheets, args[0])
    print('Hallgrat people written:', ', '.join(who_list), flush=True)


if __name__ == '__main__':
    main()
