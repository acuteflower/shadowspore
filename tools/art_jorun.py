"""Jorun, the travelling merchant of the caravan (docs/haendler_konzept.md 2.1, 8.1). Eight true directions.

    py -3 tools/art_jorun.py [contact_sheet.png]     writes assets/characters/jorun.png, jorun_glow.png and data/jorun_rig.json
    py -3 tools/art_jorun.py quick out.png           renders only a few poses for a fast look, writes nothing else

Built from ellipsoids with the heroine's renderer (the same grain, ink and outline rules as Ellie, Gustav, Torben, Esma, Ilva), in the settlers' frame and rig
format (76x96, feet (38, 80)) so `CaravanMerchant` plays him like `InteriorResident` plays the witches. An older, broad man who has walked a long way: a
long earth-brown travelling coat open over a faded mustard waistcoat, a band of caravan blue round the coat's hem and a blue neckerchief (the wagon's
canvas), a satchel strap across the chest and pouches all along the belt, dark trousers in knee boots; a weathered tan face with a short grey-brown
beard and bushy brows, dark brown eyes; a wide-brimmed hat whose band carries strings of little charms (brass, red glass, a feather, a key); a walking
staff with a small lantern hanging from its hook (the only thing that glows).
Clips: idle 4, walk 6, counter 6 (hands on the counter, leaning in), arrange 6 (moving goods about), count 6 (coins from hand to hand), call 6 (a hand at
his mouth, calling out), wave 6, present 6 (holds a bundle out to the customer), smoke 6 (the pipe)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 76, 96, 80
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
(HAIR, SKIN, BROW, LIP, COAT, COAT_D, VEST, BLUE, TROUSER, BOOTS, STRAP, BRASS, RED, LIGHT, HAT, FEATHER) = range(BASE, BASE + 16)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['3a3028', '5e5044', '857464', 'ad9c8a'],  # grey-brown hair and beard
    ['6a3e2c', '9c6448', 'c48a66', 'e2b08a'],  # weathered, sun-tanned skin
    ['2e261e', '4e4236', '6e6052', '8e8070'],  # bushy brows
    ['5a2e26', '84463a', 'a46050', 'c27e6a'],  # lips
    ['2a1c14', '4a3222', '6e4c32', '927048'],  # the long travelling coat: earth brown
    ['1a120c', '2e2016', '463222', '5e4630'],  # the coat in its folds and lining
    ['4a3818', '74582a', '9a7c40', 'bea25e'],  # faded mustard waistcoat
    ['1e2a44', '2a3f66', '3d5a8a', '6f93c4'],  # caravan blue (the wagon's canvas): the hem band, the neckerchief
    ['14121a', '24202c', '383242', '504858'],  # dark trousers
    ['160e0c', '2a1c16', '44302a', '624840'],  # knee boots
    ['241610', '40281a', '5e3e28', '7e583a'],  # leather: strap, belt, pouches
    ['4a3418', '7a5a24', 'b4893a', 'e6c468'],  # brass: buckles, charms, coins
    ['4a1e2a', '7a2f3c', 'a8484e', 'd27a6a'],  # red glass charm, the bundle he offers
    ['c28a3a', 'ffb84a', 'ffd27a', 'fff2c0'],  # the lantern's light (emissive)
    ['22180e', '3a2a1a', '58422a', '76603e'],  # the wide-brimmed hat, sun-faded felt
    ['3a3a44', '6a6a78', 'a4a4b0', 'dcdce4'],  # a grey feather
]]
h.RAMPS[h.EYE] = hexc('120c08'), hexc('3a2414'), hexc('6a4426'), hexc('f2ece2')  # dark brown eyes
SOFT = (HAIR, SKIN)
_shade = h.shade_band


def shade_band(lam, kind, mat):
    if mat in SOFT:
        return np.digitize(lam, (-0.12, 0.16, 0.6) if mat != SKIN else (-0.2, 0.12, 0.55))
    return _shade(lam, kind, mat)


h.shade_band = shade_band
V = lambda *x: np.array(x, float)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def hair_back(q):
    """Hair only at the back and the sides under the hat: the face stays free."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    return (z < 0.35) & (y < 0.5) & (y > -0.55)


CLIPS = {'idle': {'start': 0, 'count': 4, 'fps': 3}, 'walk': {'start': 4, 'count': 6, 'fps': 7}, 'counter': {'start': 10, 'count': 6, 'fps': 3},
         'arrange': {'start': 16, 'count': 6, 'fps': 5}, 'count': {'start': 22, 'count': 6, 'fps': 6}, 'call': {'start': 28, 'count': 6, 'fps': 5},
         'wave': {'start': 34, 'count': 6, 'fps': 7}, 'present': {'start': 40, 'count': 6, 'fps': 5}, 'smoke': {'start': 46, 'count': 6, 'fps': 3}}
FRAMES = 52
STAFF = ('idle', 'walk', 'call', 'wave', 'smoke')  # clips where the lantern staff is in his right hand


def pose(kind, i):
    p = dict(feet=((2.8, 0, 0), (-2.8, 0, 0)), breath=0.3, lean=.03, swing=0.0, t=0.0, head=0.0)
    if kind == 'walk':
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        p.update(feet=((2.7, 3.4 * s, 1.7 * max(c, 0)), (-2.7, -3.4 * s, 1.7 * max(-c, 0))), lean=.07, swing=s)
    elif kind == 'counter':
        p.update(lean=.2, breath=[0, .4, .8, 1, .7, .3][i], head=.08, t=[0, .2, .5, .8, .5, .2][i])
    elif kind == 'arrange':
        p.update(feet=((3.0, 0.8, 0), (-2.6, -0.6, 0)), lean=.18, t=[0, .3, .7, 1, .6, .2][i], head=.2)
    elif kind == 'count':
        p.update(lean=.06, t=i / 6.0, head=.28)
    elif kind in ('call', 'wave', 'present', 'smoke'):
        waves = {'call': [0, .4, .9, 1, 1, .5], 'wave': [0, .6, 1, .7, 1, .6], 'present': [0, .25, .6, .9, 1, .9], 'smoke': [0, .4, .9, 1, .6, .2]}
        p.update(t=waves[kind][i], breath=.25 + .3 * waves[kind][i], head=(-.08 if kind == 'call' else 0.04))
        if kind == 'wave':
            p['wave_i'] = i
    else:
        p.update(breath=[0, .45, .85, .45][i])
    return p


def build(p, kind):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None)); off = V(0, drop, 0)
    sw = p['swing']
    # ---------------------------------------------------------------- legs: dark trousers tucked into knee boots
    for hip, knee, ankle, *_ in legs:
        limb(hip, knee, 3.0, 2.6, TROUSER)
        limb(knee, ankle, 2.6, 2.3, BOOTS)
        ell(knee + V(0, 0.2, 0.6), (2.9, 1.0, 2.9), BOOTS)  # the boots' turned-down tops
        ell(ankle + V(0, -0.6, 1.1), (2.6, 1.9, 3.8), BOOTS)
        ell(ankle + V(0, -1.3, 3.8), (2.0, 1.1, 2.0), BOOTS)
    m.off = off
    lean = p['lean']; R = h.rot_x(lean); b = p['breath']

    def T(v):
        return V(0, 27, 0) + R @ (np.asarray(v, float) - V(0, 27, 0))

    # ---------------------------------------------------------------- torso: broad, a little stout; the waistcoat, belt with pouches, the strap
    ell(T((0, 28.4, 0.4)), (6.0, 3.2, 4.8), VEST, R=R)
    ell(T((0, 32.4, 0.4)), (5.8, 3.6, 4.4), VEST, R=R)
    ell(T((0, 36.2 + b * .12, 0.5)), (6.2, 3.0, 4.2), VEST, R=R)
    for k in range(4):  # the waistcoat's brass buttons
        ell(T((0.3, 35.0 - k * 2.4, 4.7 + (k == 0) * 0.1)), (0.45, 0.45, 0.3), BRASS, R=R)
    for a in np.linspace(0, 2 * math.pi, 17)[:-1]:  # the belt
        ell(T((math.cos(a) * 6.0, 27.0, 0.4 + math.sin(a) * 4.9)), (1.0, 0.75, 0.9), STRAP, R=R)
    ell(T((0, 27.0, 5.3)), (1.2, 0.9, 0.4), BRASS, R=R)  # buckle
    for k, (x, z) in enumerate(((-4.6, 3.2), (-6.2, 0.2), (5.6, 2.2), (6.4, -1.4), (-4.8, -3.4))):  # pouches all along the belt
        ell(T((x, 25.2, z)), (1.5, 1.9, 1.2), STRAP if k % 2 else COAT, R=R)
        ell(T((x, 26.6, z + 0.2)), (1.6, 0.5, 1.3), STRAP, R=R)
    for k in range(9):  # the satchel strap from the right shoulder across to the left hip
        t = k / 8
        ell(T((-5.2 + 10.6 * t, 38.0 - 11.0 * t, 4.4 + 0.6 * math.sin(t * math.pi))), (0.9, 0.9, 0.55), STRAP, R=R)
    ell(T((6.6, 25.0, -1.0)), (2.4, 2.8, 2.6), STRAP, R=R)  # the satchel on his left hip
    ell(T((6.9, 27.0, -0.8)), (2.5, 0.8, 2.7), STRAP, R=R)
    limb(T((0, 39.2, 0.2)), T((0, 41.2, 0.4)), 2.3, 2.2, SKIN)
    # the blue neckerchief, knotted at the front
    for a in np.linspace(0, 2 * math.pi, 11)[:-1]:
        ell(T((math.cos(a) * 3.0, 39.4, 0.5 + math.sin(a) * 2.8)), (1.4, 1.0, 1.3), BLUE, R=R)
    ell(T((0.4, 38.0, 3.6)), (1.4, 1.6, 0.9), BLUE, R=R)
    # ---------------------------------------------------------------- the long coat: open at the front, down to the knees, a blue band at the hem
    for sx in (-1, 1):
        ell(T((sx * 6.4, 37.4, 0.0)), (2.9, 2.9, 3.6), COAT, R=R)  # shoulders
        ribbon([T((sx * 5.6, 38.0, 3.0)), T((sx * 6.2, 30.0, 4.6)), V(sx * 6.4 + sw * .4, 19.0, 5.0 + sw * sx * .4)], [2.2, 2.8, 3.2], 0.7, COAT, (sx, 0, 1), kind='')
        ribbon([V(sx * 6.4 + sw * .4, 19.6, 5.0), V(sx * 6.5 + sw * .5, 17.4, 5.1)], [3.0, 3.2], 0.75, BLUE, (sx, 0, 1), kind='')  # the hem band in front
        ell(T((sx * 6.0, 34.0, 4.6)), (1.0, 4.0, 0.6), COAT_D, R=R)  # the turned-back lapels
    for k, x in enumerate((-6.2, -3.1, 0.0, 3.1, 6.2)):  # the back of the coat, swinging with the stride
        ribbon([T((x, 38.6, -3.8)), T((x * 1.08, 30.0, -5.4 - sw * .2)), V(x * 1.12 + sw * .3, 19.0 + (k % 2) * 0.5, -6.4 - sw * .6)], [2.6, 2.9, 2.6], 0.7,
               COAT_D if k % 2 else COAT, (0, 0, -1), kind='')
        ribbon([V(x * 1.12 + sw * .3, 19.6, -6.4 - sw * .6), V(x * 1.14 + sw * .3, 17.2, -6.6 - sw * .7)], [2.7, 2.7], 0.75, BLUE, (0, 0, -1), kind='')
    for sx in (-1, 1):  # the coat's sides
        ribbon([T((sx * 7.0, 37.0, 0.0)), T((sx * 7.4, 28.0, 0.2)), V(sx * 7.8 + sw * .3, 18.6, 0.2)], [3.2, 3.4, 3.2], 0.75, COAT, (sx, 0, 0), kind='')
    # ---------------------------------------------------------------- arms: coat sleeves, gloveless weathered hands
    t = p['t']
    hands = {}
    for side in (-1, 1):  # -1 = his right
        shoulder = T((side * 6.6, 36.8, 0.2))
        hand = T((side * 7.6, 26.0, side * sw * 2.0 + 0.8))
        if kind in STAFF and side < 0 and kind != 'call':
            hand = T((-8.2, 27.6, 3.0 + sw * 1.2))  # holding the staff
        if kind == 'counter':
            hand = T((side * 4.6, 27.4 - t * 0.4, 8.8))
        elif kind == 'arrange':
            hand = T((side * 3.0 + (2.0 * t - 1.0) * 2.4, 27.0 + side * t, 8.6))
        elif kind == 'count':
            a = math.tau * t
            hand = T((side * 2.4 + side * math.sin(a) * 0.6, 29.6 + (math.sin(a) if side > 0 else -math.sin(a)) * 0.8, 6.8))
        elif kind == 'call' and side > 0:
            hand = T((2.2 * t + 5.8 * (1 - t), 26.0 + 17.6 * t, 1.0 + 4.6 * t))  # the left hand at his mouth
        elif kind == 'call' and side < 0:
            hand = T((-8.2, 27.6, 3.0))
        elif kind == 'wave' and side > 0:
            i = p.get('wave_i', 0)
            hand = T((8.4 + (1.2 if i % 2 else -0.8) * t, 34.0 + 13.0 * t, 2.6))
        elif kind == 'present':
            hand = T((side * (3.6 - 1.4 * t), 27.0 + 4.0 * t, 2.2 + 9.4 * t))
        elif kind == 'smoke' and side > 0:
            hand = T((2.4 + 3.0 * (1 - t), 30.0 + 11.6 * t, 2.4 + 2.6 * t))  # the pipe to his mouth and down again
        mid = (shoulder + hand) / 2
        el = mid + V(side * 1.8, -1.4, -1.6)
        hands[side] = hand
        limb(shoulder, el, 2.5, 2.3, COAT)
        limb(el, hand, 2.2, 2.0, COAT)
        ell(hand + (el - hand) / np.linalg.norm(el - hand) * 1.4, (2.1, 1.0, 2.1), COAT_D)  # cuff
        d = (hand - el) / np.linalg.norm(hand - el)
        ell(hand + d * .5, (1.8, 1.9, 1.7), SKIN)
        ell(hand + d * .3 + V(side * -0.9, 0, 1.0), (.7, 1.0, .7), SKIN)
    if kind in STAFF:  # the walking staff with its lantern
        hr = hands[-1]
        top = hr + V(-0.4, 16.0, 0.2)
        foot = hr + V(0.2, -27.0 + (0 if kind != 'walk' else 1.0 * sw), 0.4)
        foot[1] = max(foot[1], 0.4)
        limb(foot, top, 0.75, 0.65, STRAP)
        limb(top, top + V(-2.2, 1.0, 0), 0.55, 0.45, STRAP)  # the hook
        lamp = top + V(-2.6, -2.2, 0)
        ell(lamp + V(0, 1.4, 0), (1.1, 0.5, 1.1), BRASS)
        ell(lamp, (1.2, 1.6, 1.2), LIGHT, kind='emit')
        ell(lamp + V(0, -1.5, 0), (1.2, 0.4, 1.2), BRASS)
    if kind == 'count':  # coins between his hands
        for k in range(3):
            ell((hands[-1] + hands[1]) / 2 + V(-1 + k, 0.4 + 0.6 * math.sin(t * math.tau + k), 0.6), (0.7, 0.25, 0.7), BRASS)
    if kind == 'present':  # a bundle in red cloth tied with string
        c = (hands[-1] + hands[1]) * .5 + V(0, 1.4, 0.4)
        ell(c, (2.4, 1.8, 1.8), RED)
        ell(c + V(0, 1.6, 0), (0.6, 0.6, 0.6), RED)
        limb(c + V(-2.2, 0.4, 0.6), c + V(2.2, 0.4, 0.6), 0.25, 0.25, BRASS)
    if kind == 'arrange':  # a little jar he moves about
        ell(hands[1] + V(0, 1.6, 0.6), (1.1, 1.5, 1.1), BLUE)
    # ---------------------------------------------------------------- head: a weathered face, short grey-brown beard, bushy brows, the hat
    Rh = R @ h.rot_x(p['head'])
    Ro = Rh * 1.1
    hc = T((0, 45.6 + b * .2, .6))
    ell(hc, (5.0, 5.3, 4.9), SKIN, R=Rh, kind='head')
    ell(hc + Ro @ V(0, .2, -.8), (5.3, 5.2, 5.1), HAIR, R=Rh, kind='hair', tag=3.0, clip=hair_back)
    for side in (-1, 1):
        ell(hc + Ro @ V(side * 1.9, 1.2, 4.3), (1.6, .55, .6), BROW, R=Rh @ rot_z(side * -.1))  # bushy brows
        ell(hc + Ro @ V(side * 2.4, -0.4, 3.9), (1.0, 0.25, 0.4), SKIN, R=Rh @ rot_z(side * .2))  # crow's feet
        ell(hc + Ro @ V(side * 4.8, 0.0, 0.4), (0.9, 1.4, 1.0), SKIN, R=Rh)  # ears
    ell(hc + Ro @ V(0, -0.8, 4.7), (.85, 1.1, .7), SKIN, R=Rh)  # a broad nose
    # the beard: short and full along the jaw and chin, a moustache over the lip
    for k in range(11):
        a = math.pi * (0.08 + 0.84 * k / 10)
        ell(hc + Ro @ V(math.cos(a) * 4.1, -3.0 - math.sin(a) * 1.7, 1.6 + math.sin(a) * 2.4), (1.5, 1.6, 1.4), HAIR, R=Rh, kind='hair', tag=5.0 + (k % 2))
    ell(hc + Ro @ V(0, -4.6, 3.4), (2.4, 1.6, 1.6), HAIR, R=Rh, kind='hair', tag=6.0)
    if kind != 'call':
        ell(hc + Ro @ V(0, -2.4, 4.5), (1.9, .5, .55), HAIR, R=Rh)  # moustache
    ell(hc + Ro @ V(0, -3.0, 4.3), (1.0, .35, .35), LIP, R=Rh)
    if kind == 'smoke' and p['t'] > 0.5:  # the pipe in his mouth
        limb(hc + Ro @ V(0.8, -3.0, 4.6), hc + Ro @ V(2.8, -3.8, 6.4), 0.35, 0.3, STRAP)
        ell(hc + Ro @ V(3.0, -3.0, 6.6), (0.8, 1.0, 0.8), STRAP, R=Rh)
    # the hat: a wide, slightly drooping brim, a dented crown, a band with strings of charms
    hat = hc + Ro @ V(0, 4.5, -0.8)
    for k in range(18):
        a = k / 18 * math.tau
        droop = 0.4 + 0.3 * math.cos(a)  # the brim dips a little at the front
        ell(hat + Ro @ V(math.cos(a) * 6.2, -0.6 * droop + 0.5 * max(math.sin(a), 0.0), math.sin(a) * 5.8), (2.2, 0.5, 2.2), HAT, R=Rh @ h.rot_y(-a))
    ell(hat + Ro @ V(0, 0.2, 0), (6.2, 0.6, 6.0), HAT, R=Rh)
    ell(hat + Ro @ V(0, 2.4, -0.2), (3.9, 2.6, 3.7), HAT, R=Rh)
    ell(hat + Ro @ V(0, 4.6, -0.2), (2.8, 0.8, 2.4), HAT, R=Rh)
    for k in range(14):  # the band
        a = k / 14 * math.tau
        ell(hat + Ro @ V(math.cos(a) * 3.95, 1.0, math.sin(a) * 3.75), (0.9, 0.55, 0.9), BLUE, R=Rh)
    sway = math.sin(p['t'] * math.tau + sw) * 0.4
    for k, (a, mat, drop_len) in enumerate(((0.9, BRASS, 3.4), (2.2, RED, 2.6), (3.6, BRASS, 4.0), (4.6, FEATHER, 3.0), (5.6, RED, 2.2))):
        base = hat + Ro @ V(math.cos(a) * 6.0, -0.4, math.sin(a) * 5.8)
        end = base + V(sway * 0.5, -drop_len, 0.2)
        limb(base, end, 0.18, 0.18, STRAP)
        if mat == FEATHER:
            limb(end, end + V(0.3, -2.4, 0.2), 0.6, 0.25, FEATHER)
        else:
            ell(end, (0.55, 0.65, 0.55), mat)
    # a feather tucked into the band
    limb(hat + Ro @ V(3.6, 1.2, -1.8), hat + Ro @ V(5.2, 5.6, -3.4), 0.7, 0.3, FEATHER)
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
    """Only the lantern's light: the unlit second sheet."""
    cols = {tuple(c[:3]) for c in h.RAMPS[LIGHT]}
    flat = arr.reshape(-1, 4)
    keep = np.array([tuple(int(v) for v in px[:3]) in cols and px[3] > 0 for px in flat])
    out = np.zeros_like(flat); out[keep] = flat[keep]
    return out.reshape(arr.shape)


def main():
    quick = len(sys.argv) > 1 and sys.argv[1] == 'quick'
    jobs = [(s, entry['start'] + i, k, i) for s in range(8) for k, entry in CLIPS.items() for i in range(entry['count'])]
    picks = [0, 6, 12, 19, 25, 31, 37, 44, 49]
    if quick:
        jobs = [j for j in jobs if j[1] in picks]
    arr = np.zeros((8 * FH, FRAMES * FW, 4), dtype=np.uint8)
    print('Rendering', len(jobs), 'Jorun poses', flush=True)
    with mp.Pool(min(6, os.cpu_count() or 1)) as pool:
        for s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(arr, sys.argv[2], picks)
        print('quick sheet written', flush=True)
        return
    write_array(ROOT / 'characters/jorun.png', arr)
    write_array(ROOT / 'characters/jorun_glow.png', glow_of(arr))
    (ROOT.parent / 'data/jorun_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': FRAMES, 'rows': 8, 'height': 58, 'clips': CLIPS}, indent=2) + '\n')
    if len(sys.argv) > 1:
        contact(arr, sys.argv[1], picks)
    print('Jorun sheet, glow and rig written', flush=True)


if __name__ == '__main__':
    main()
