"""Hallgrat's townsfolk, the extras kit (docs/hallgrat_bewohner_konzept.md 3). Thirteen bodies in eight true directions.

    py -3 tools/art_hallgrat_extras.py [contact.png]        writes assets/characters/hallgrat_extra_<k>.png (+ _glow.png) and data/hallgrat_extra_rig.json
    py -3 tools/art_hallgrat_extras.py quick out.png [k,k]  a few poses of each (or of the named kinds), writes nothing else

Same renderer, frame and rig format as the six core figures (`art_hallgrat_people.py`, 76x96, feet (38, 80)); ONE rig for every kind.
A kind is a build (schmal / kräftig / alt, stooped), a cut (kittel = tunic and trousers, rock = dress with apron, mantel = long coat), a head
(kurz, zopf, kapuze, hut, glatze) and a load (korb, sack, krug, brett, werkzeug, or nothing; the guard carries spear and lantern).
The clothes and the hair are drawn in three KEY ramps (`KEY_A` main cloth, `KEY_B` second cloth, `KEY_H` hair) whose colours appear nowhere
else: `HallgratExtra` swaps them per townsperson with `hallgrat_extra.gdshader` from the palettes in data/hallgrat_people.json, so 13 sheets
give hundreds of looks while arms, loads and clothes keep their real 3D overlap (layer sheets would not).

Clips: idle 4, walk 6, talk 4, wave 6, carry 6 (walking with the load; the load shows only here and while standing), sit 4 (on a bench),
work 6 (hands busy in front: laying out goods, scrubbing, setting stones)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
import art_hallgrat_people as P
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = P.FW, P.FH, P.GROUND
BASE = len(h.RAMPS)
KEY_A, KEY_B, KEY_H = BASE, BASE + 1, BASE + 2
KEYS = [['31405e', '475c80', '6680a6', '93aacb'],  # KEY_A main cloth (default: town slate blue)
        ['5d4b33', '82694a', 'a88c65', 'cfb68d'],  # KEY_B second cloth (default: oat linen)
        ['2d1d13', '4b321f', '6d4b2f', '936b45']]  # KEY_H hair (default: brown)
h.RAMPS += [[hexc(c) for c in row] for row in KEYS]
_used = {tuple(c) for k, ramp in enumerate(h.RAMPS) if k < BASE for c in ramp}
for ramp in KEYS:
    for c in ramp:
        assert tuple(hexc(c)) not in _used, 'key colour %s is not unique' % c
_soft = h.shade_band


def shade_band(lam, kind, mat):
    if mat == KEY_H:
        return np.digitize(lam, (-0.12, 0.16, 0.6))
    return _soft(lam, kind, mat)


h.shade_band = shade_band
V = P.V

KINDS = [  # build, cut, head, load, skin
    ('schmal', 'kittel', 'kurz', 'korb', P.SKIN_L),
    ('schmal', 'rock', 'zopf', 'krug', P.SKIN_W),
    ('kraeftig', 'kittel', 'glatze', 'sack', P.SKIN_T),
    ('kraeftig', 'mantel', 'hut', '', P.SKIN_L),
    ('alt', 'mantel', 'kapuze', '', P.SKIN_L),
    ('alt', 'rock', 'kurz', 'korb', P.SKIN_W),
    ('schmal', 'mantel', 'kapuze', '', P.SKIN_W),
    ('kraeftig', 'kittel', 'hut', 'brett', P.SKIN_W),
    ('schmal', 'kittel', 'zopf', 'werkzeug', P.SKIN_T),
    ('alt', 'kittel', 'glatze', '', P.SKIN_T),
    ('kraeftig', 'rock', 'kurz', 'sack', P.SKIN_L),
    ('schmal', 'mantel', 'kurz', 'korb', P.SKIN_T),
    ('kraeftig', 'mantel', 'helm', 'wache', P.SKIN_W),
]
BUILD = {'schmal': dict(scale=0.96, sh=5.0, lean=0.0, height=56), 'kraeftig': dict(scale=1.03, sh=6.6, lean=0.0, height=59),
         'alt': dict(scale=0.94, sh=5.3, lean=0.2, height=53)}
CLIPS = [('idle', 4, 3), ('walk', 6, 8), ('talk', 4, 5), ('wave', 6, 7), ('carry', 6, 7), ('sit', 4, 2), ('work', 6, 5)]
EYES = ('140e08', '3a2a1c', '6a4a30', 'f2ece2')


def clips():
    out, start = {}, 0
    for name, count, fps in CLIPS:
        out[name] = {'start': start, 'count': count, 'fps': fps}
        start += count
    return out, start


def pose(kind, i, n, old):
    base = 'walk' if kind == 'carry' else ('idle' if kind in ('sit', 'work') else kind)
    p = P.pose(base, i, n)
    if kind == 'work':
        p.update(lean=.22, t=i / n, head=.3, feet=((2.8, 0.8, 0), (-2.6, -0.6, 0)))
    if kind == 'sit':
        p.update(lean=.04, head=.05)
    if old:
        p['lean'] += 0.2 if kind != 'sit' else 0.1
        p['head'] -= 0.12
        if kind in ('walk', 'carry'):
            p['feet'] = tuple((x, y * 0.7, z * 0.7) for x, y, z in p['feet'])
    return p


def build(k, p, kind):
    bname, cut, head, load, skin = KINDS[k]
    b = BUILD[bname]
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    sw, t = p['swing'], p['t']
    sitting = kind == 'sit'
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None))
    hipy = 0.0
    if sitting:  # on a bench: thighs forward, shins down
        hipy = -6.0
        for sx in (-1, 1):
            hip = V(sx * 2.4, 10.0, 0.4)
            knee = V(sx * 2.6, 10.4, 7.0)
            ankle = V(sx * 2.6, 2.0, 7.6)
            limb(hip, knee, 2.7, 2.4, P.TROUSER if cut != 'rock' else KEY_A)
            limb(knee, ankle, 2.4, 2.1, P.TROUSER if cut != 'rock' else P.BOOTS)
            ell(ankle + V(0, -0.6, 1.0), (2.3, 1.8, 3.4), P.BOOTS)
    else:
        for hip, knee, ankle, *_ in legs:
            limb(hip, knee, 2.7, 2.4, P.TROUSER)
            limb(knee, ankle, 2.4, 2.1, P.TROUSER)
            ell(ankle + V(0, -0.6, 1.0), (2.3, 1.8, 3.4), P.BOOTS)
            ell(ankle + V(0, -1.2, 3.4), (1.8, 1.0, 1.8), P.BOOTS)
        m.off = V(0, drop, 0)
    R = h.rot_x(p['lean'])
    sh = b['sh']
    w = sh / 6.0
    br = p['breath']

    def T(v):
        v = np.asarray(v, float)
        return V(0, 26 + hipy, 0) + R @ (v + V(0, hipy, 0) - V(0, 26 + hipy, 0))

    # clothes below the waist
    if cut == 'rock':
        for j in range(9):
            u = j / 8.0
            if sitting:
                ell(V(0, 21.0 - 10.0 * u, 3.0 + 4.0 * u), (4.8 + 1.4 * u, 1.6, 4.4 + 1.2 * u), KEY_A)
            else:
                y = 27.0 - 21.0 * u
                ell(V(sw * .6 * u ** 2, y, 0.3), (4.4 + 3.6 * u ** .8, 1.7, (4.4 + 3.6 * u ** .8) * .86), KEY_A)
        if not sitting:
            ribbon([T((0, 29.5, 4.4)), V(sw * .3, 18.0, 6.8), V(sw * .5, 8.0, 7.4)], [3.0, 4.0, 4.4], 0.6, KEY_B, (0, 0, 1), kind='')
    elif cut == 'mantel':
        for j in range(7):
            u = j / 6.0
            if sitting:
                ell(V(0, 21.0 - 4.0 * u, 2.0 + 5.0 * u), (5.0 + .8 * u, 1.6, 4.4), KEY_A)
            else:
                y = 27.0 - 15.0 * u
                ell(V(sw * .5 * u ** 2, y, 0.0 - 0.6 * u), (4.8 + 2.2 * u, 1.7, 4.0 + 1.6 * u), KEY_A, clip=lambda q: q[..., 2] < 0.62)
        for sx in (-1, 1):  # the open front shows the trim
            ribbon([T((sx * 1.6, 37.0, 4.4)), T((sx * 2.2, 28.0, 4.8)), V(sx * 2.8 + sw * .3, 14.0 if not sitting else 20.0, 5.2 if not sitting else 7.4)],
                   [0.9, 1.0, 1.0], 0.5, KEY_B, (0, 0, 1), kind='')
    else:  # kittel to mid-thigh
        for j in range(5):
            u = j / 4.0
            ell(T((sw * .3 * u, 27.0 - 7.0 * u, 0.4 + (2.0 * u if sitting else 0))), (4.8 + 1.0 * u, 1.6, 3.9 + 0.8 * u), KEY_A)
    # torso
    body = KEY_A
    ell(T((0, 27.6, 0.3)), (5.0 * w, 2.8, 4.0 * w), body, R=R)
    ell(T((0, 31.4, 0.4)), (4.8 * w, 3.4, 3.8 * w), body, R=R)
    ell(T((0, 35.4 + br * .12, 0.5)), (5.6 * w, 3.0, 4.0 * w), body, R=R)
    for a in np.linspace(0, 2 * math.pi, 15)[:-1]:  # belt
        ell(T((math.cos(a) * 5.0 * w, 27.2, 0.4 + math.sin(a) * 4.1 * w)), (0.9, 0.6, 0.8), P.LEATHER_D if cut != 'rock' else KEY_B, R=R)
    ell(T((0, 37.4, 2.6)), (3.0 * w + 0.4, 1.0, 1.6), KEY_B, R=R)  # collar / neckline
    limb(T((0, 38.4, 0.2)), T((0, 40.2, 0.4)), 1.8 * w + 0.2, 1.7 * w + 0.2, skin)
    for sx in (-1, 1):
        ell(T((sx * sh, 36.6, 0.0)), (2.5, 2.5, 2.9), body, R=R)
    if load == 'wache':  # a slate tabard over the coat
        ribbon([T((0, 37.0, 4.2)), T((0, 30.0, 4.9)), T((sw * .2, 22.0, 5.4))], [3.0, 3.2, 3.0], 0.5, P.SLATE, (0, 0, 1), kind='')
        ell(T((0, 32.0, 5.0)), (1.2, 1.4, 0.4), P.BRASS, R=R)
    # arms
    show_load = load and kind in ('idle', 'carry', 'talk', 'walk') and load != 'wache'
    if load == 'wache':
        show_load = False
    hands = {}
    for side in (-1, 1):
        shoulder = T((side * sh, 36.2, 0.2))
        hand = T((side * (sh + 0.8), 25.6, side * sw * 2.0 + 0.6))
        if kind == 'talk' and side < 0:
            hand = T((-sh - 1.0 - 1.5 * t, 26.0 + 6.5 * t, 1.0 + 5.0 * t))
        elif kind == 'wave' and side > 0:
            hand = T((sh + 2.2 + (1.4 if p.get('i', 0) % 2 else -0.8) * t, 32.0 + 13.0 * t, 2.4))
        elif kind == 'work':
            a = math.tau * t + (0 if side > 0 else math.pi)
            hand = T((side * 2.0 + math.sin(a) * 1.0, 26.0 + math.cos(a) * 1.2, 8.6))
        elif kind == 'sit':
            hand = T((side * 3.2, 24.0, 5.2))
        if load == 'wache' and side < 0 and kind != 'talk':
            hand = T((-sh - 2.2, 29.5, 2.8 + (sw if kind == 'walk' else 0)))
        if load == 'wache' and side > 0 and kind in ('idle', 'walk', 'carry'):
            hand = T((sh + 1.4, 25.0, 2.6 - sw))
        if show_load and side > 0:
            if load in ('sack', 'brett'):
                hand = T((sh * 0.8, 39.0, -0.6))
            elif load in ('korb', 'krug'):
                hand = T((sh + 1.2, 27.6, 1.8))
            elif load == 'werkzeug':
                hand = T((sh + 1.0, 25.4, 1.2 - sw))
        mid = (shoulder + hand) / 2
        el = mid + V(side * 1.6, -1.2, -1.4)
        hands[side] = hand
        limb(shoulder, el, 2.2, 2.0, body)
        limb(el, hand, 1.9, 1.7, body)
        dd = (hand - el) / np.linalg.norm(hand - el)
        ell(hand + dd * .5, (1.6, 1.8, 1.5), skin)
    # loads
    if show_load:
        hr = hands[1]
        if load == 'korb':
            c = hr + V(0.6, -2.6, 0.6)
            ell(c, (2.8, 2.0, 2.2), P.STRAW)
            ell(c + V(0, 1.6, 0), (2.4, 0.6, 1.8), P.BROW_D)
            ell(c + V(-0.8, 2.0, 0.4), (0.9, 0.8, 0.9), P.WINE)  # apples
            ell(c + V(0.8, 2.0, -0.2), (0.9, 0.8, 0.9), P.WINE)
            limb(c + V(-2.0, 1.4, 0), hr + V(0, 0.4, 0), 0.3, 0.3, P.STRAW)
        elif load == 'krug':
            c = hr + V(0.4, -2.4, 0.6)
            ell(c, (1.6, 2.2, 1.6), P.CLAY)
            ell(c + V(0, 2.4, 0), (1.0, 0.6, 1.0), P.CLAY)
        elif load == 'sack':
            ell(T((sh * 0.4, 42.0, -2.0)), (3.8, 2.6, 3.0), P.CREAM, R=R @ P.rot_z(.3))
        elif load == 'brett':
            limb(T((sh * 0.8 + 2.0, 40.0, -9.0)), T((sh * 0.8 - 1.0, 40.6, 10.0)), 0.9, 0.9, P.WOOD)
        elif load == 'werkzeug':
            limb(hr + V(0, 1.0, 0), hr + V(0.2, -6.0, 0.6), 0.45, 0.45, P.WOOD)
            ell(hr + V(0.2, -6.4, 0.6), (1.6, 1.0, 1.0), P.IRON)
    if load == 'wache':
        hr = hands[-1]
        if kind != 'talk':
            limb(V(hr[0], 0.4 + hipy * 0, hr[2] + 0.4), V(hr[0] + 0.2, 62.0, hr[2] - 0.6), 0.6, 0.55, P.WOOD)
            ell(V(hr[0] + 0.2, 64.2, hr[2] - 0.6), (0.9, 2.6, 0.5), P.IRON)
        if kind in ('idle', 'walk', 'carry'):
            c = hands[1] + V(0.2, -2.6, 0.4)  # the lantern
            limb(hands[1], c + V(0, 1.6, 0), 0.25, 0.25, P.IRON)
            ell(c, (1.4, 1.8, 1.4), P.IRON)
            ell(c, (0.9, 1.2, 0.9), P.FLAME, kind='emit')
    # head
    Rh = R @ h.rot_x(p['head'])
    Ro = Rh * 1.1
    hc = T((0, 44.2 + br * .2, .5))
    ell(hc, (4.8, 5.2, 4.7), skin, R=Rh, kind='head')
    for side in (-1, 1):
        ell(hc + Ro @ V(side * 1.9, 1.2, 4.1), (1.4, .4, .5), P.BROW_G if bname == 'alt' else P.BROW_D, R=Rh @ P.rot_z(side * -.1))
        ell(hc + Ro @ V(side * 4.6, 0.0, 0.4), (0.8, 1.3, 0.9), skin, R=Rh)
    ell(hc + Ro @ V(0, -1.0, 4.45), (.6, .85, .5), skin, R=Rh)
    ell(hc + Ro @ V(0, -2.9, 3.85), (1.0, .4, .45), P.LIP, R=Rh)
    ell(hc + Ro @ V(0, -4.3, 2.9), (1.8, 1.0, 1.6), skin, R=Rh)
    hair = KEY_H if bname != 'alt' else P.GREY
    if head == 'glatze':
        for side in (-1, 1):
            ell(hc + Ro @ V(side * 4.2, 0.6, -1.4), (1.4, 1.8, 2.8), hair, R=Rh, kind='hair', tag=3.0)
        ell(hc + Ro @ V(0, -0.6, -4.2), (3.6, 2.0, 1.4), hair, R=Rh, kind='hair', tag=4.0)
        if bname != 'schmal':
            ell(hc + Ro @ V(0, -3.6, 3.8), (3.2, 2.0, 1.4), hair, R=Rh, kind='hair', tag=5.0)  # a beard
    elif head in ('kurz', 'hut', 'helm'):
        ell(hc + Ro @ V(0, .5, -.5), (5.1, 5.3, 5.0), hair, R=Rh, kind='hair', tag=3.0, clip=P.hair_short)
    elif head == 'zopf':
        ell(hc + Ro @ V(0, .5, -.4), (5.2, 5.6, 5.1), hair, R=Rh, kind='hair', tag=3.0, clip=P.hair_open)
        top = hc + Ro @ V(0, -1.0, -4.8)
        for j in range(6):
            ell(top + V(sw * -.1 * j, -1.7 * j, -0.5 - 0.3 * j), (1.3 - .1 * j, 1.1, 1.1), hair, kind='hair', tag=10.0 + j)
    elif head == 'kapuze':
        ell(hc + Ro @ V(0, .5, -.4), (5.2, 5.6, 5.1), hair, R=Rh, kind='hair', tag=3.0, clip=P.hair_open)
        ell(hc + Ro @ V(0, 1.0, -1.0), (6.0, 6.2, 6.0), KEY_B, R=Rh, clip=lambda q: ~((q[..., 2] > 0.25) & (q[..., 1] < 0.6)))
        ell(T((0, 37.2, -1.6)), (5.4 * w + 1.0, 1.8, 4.4), KEY_B, R=R)
    if head == 'hut':
        cap = hc + Ro @ V(0, 4.0, -0.2)
        ell(cap, (7.2, 0.7, 7.0), KEY_B, R=Rh)
        ell(cap + Ro @ V(0, 1.6, 0), (4.4, 2.2, 4.2), KEY_B, R=Rh)
        ell(cap + Ro @ V(0, 0.9, 0), (4.6, 0.5, 4.4), P.LEATHER_D, R=Rh)
    if head == 'helm':
        cap = hc + Ro @ V(0, 3.0, -0.2)
        ell(cap, (5.6, 3.2, 5.4), P.IRON, R=Rh, clip=lambda q: q[..., 1] > -0.2)
        ell(cap + Ro @ V(0, -0.6, 0), (6.0, 0.5, 5.8), P.IRON, R=Rh)
    return m


def render_one(job):
    k, sector, index, kind, i, n = job
    bname = KINDS[k][0]
    h.SCALE = BUILD[bname]['scale']
    h.RAMPS[h.EYE] = tuple(hexc(c) for c in EYES)
    p = pose(kind, i, n, bname == 'alt'); p['i'] = i
    model = build(k, p, kind)
    yaw = math.pi / 2 - sector * math.pi / 4
    depth, code, _ = h.render(model.transform(yaw, 0), yaw, 0)
    return k, sector, index, np.asarray(h.to_pixels(depth, code), dtype=np.uint8).tobytes()


def contact(sheets, path, scale=2):
    from PIL import Image
    cl, frames = clips()
    picks = [c['start'] + (c['count'] // 2 if name != 'idle' else 0) for name, c in cl.items()]
    rows = []
    for k, arr in sheets.items():
        for s in (2, 1):
            rows.append([arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] for i in picks])
    canvas = Image.new('RGB', (len(picks) * FW * scale, len(rows) * FH * scale), (26, 24, 36))
    for y, r in enumerate(rows):
        for x, a in enumerate(r):
            tile = Image.new('RGBA', (FW, FH), (26, 24, 36, 255)); tile.alpha_composite(Image.fromarray(a))
            canvas.paste(tile.convert('RGB').resize((FW * scale, FH * scale), Image.Resampling.NEAREST), (x * FW * scale, y * FH * scale))
    canvas.save(path)


def main():
    args = sys.argv[1:]
    quick = bool(args) and args[0] == 'quick'
    kinds = list(range(len(KINDS)))
    if quick and len(args) > 2:
        kinds = [int(x) for x in args[2].split(',')]
    cl, frames = clips()
    jobs = []
    for k in kinds:
        for kind, c in cl.items():
            for i in range(c['count']):
                if quick and i != c['count'] // 2:
                    continue
                for s in range(8):
                    if quick and s not in (2, 1):
                        continue
                    jobs.append((k, s, c['start'] + i, kind, i, c['count']))
    sheets = {k: np.zeros((8 * FH, frames * FW, 4), dtype=np.uint8) for k in kinds}
    print('Rendering', len(jobs), 'poses of', len(kinds), 'kinds', flush=True)
    with mp.Pool(min(8, os.cpu_count() or 1)) as pool:
        for k, s, i, data in pool.imap_unordered(render_one, jobs, chunksize=4):
            sheets[k][s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(sheets, args[1])
        print('quick sheet written', flush=True)
        return
    for k, arr in sheets.items():
        write_array(ROOT / ('characters/hallgrat_extra_%d.png' % k), arr)
        write_array(ROOT / ('characters/hallgrat_extra_%d_glow.png' % k), P.glow_of(arr))
    rig = {'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': frames, 'rows': 8, 'height': 56, 'clips': cl,
           'kinds': [{'build': b, 'cut': c, 'head': hd, 'load': ld, 'height': BUILD[b]['height']} for b, c, hd, ld, _ in KINDS],
           'keys': {'a': KEYS[0], 'b': KEYS[1], 'h': KEYS[2]}}
    (ROOT.parent / 'data/hallgrat_extra_rig.json').write_text(json.dumps(rig, indent=1) + '\n')
    if args:
        contact(sheets, args[0])
    print('Hallgrat extras written:', len(sheets), 'kinds', flush=True)


if __name__ == '__main__':
    main()
