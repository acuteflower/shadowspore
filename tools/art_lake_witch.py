"""The lake witch (Seehexe, working name ILVA; docs/seehexe_konzept.md 4.2). Eight true directions.

    py -3 tools/art_lake_witch.py [contact_sheet.png]     writes assets/characters/lake_witch.png, lake_witch_glow.png and data/lake_witch_rig.json
    py -3 tools/art_lake_witch.py quick out.png           renders only a few poses for a fast look, writes nothing else

Built from ellipsoids with the heroine's renderer (the same grain, ink and outline rules as Ellie, Esma, Gustav, Torben), in Esma's frame and rig format
so `InteriorResident` plays her like Esma. An older, stocky woman with working hands: ash-grey hair in a thick braid laid round her head like a crown and
pinned with grown crystal needles (the spell crystals' pointed form), light grey-blue eyes, weathered skin with a few glittering crystal scars on the
bare forearms, a jeweller's loupe pushed up on her forehead; an oiled reed-green rain cape over a dark petrol dress with rolled sleeves, a leather apron
dusted with glittering grinding dust, a moonstone pendant (the gems' milky round form), wooden clogs, the hem dark with lake water.
Clips: idle 4, walk 6, grind 6 (both hands at the little wheel, `strike` 3: a spark), carve 6 (knife along a staff blank), basin 8 (she bends down and lays
a crystal into the water, lifts another), counter 4, talk 6, listen 4, point 6, give 6 (a glowing crystal held out in both hands)."""
import json, math, multiprocessing as mp, os, sys
import numpy as np
import art_hero3d as h
from art_hero_rebuild import write_array
from gen_art import ROOT, hexc

FW, FH, GROUND = 76, 96, 80
h.FW, h.FH, h.GROUND_ROW, h.SCALE = FW, FH, GROUND, 1.0
BASE = len(h.RAMPS)
(HAIR, HAIR_L, SKIN, BROW, LIP, DRESS, CAPE, CAPE_D, APRON, CLOG, MOONS, SILVER, GLASS) = range(BASE, BASE + 13)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ['2a2830', '46444e', '6a6872', '8e8c96'],  # ash-grey hair (darker than Ellie's silver-white: never mistaken for her)
    ['34323c', '56545e', '7e7c88', 'a4a2ac'],  # its lit strands
    ['6e4436', 'a8745c', 'cc9a7c', 'e6bea0'],  # weathered skin
    ['3a3640', '5a5662', '807c88', 'a8a4ae'],  # grey brows
    ['5e3236', '8a4c50', 'ab6a6a', 'c88c86'],  # lips
    ['081618', '102a2e', '1a4044', '285a5c'],  # the dress: dark petrol
    ['18200e', '2c3a1a', '46562a', '687a3e'],  # the oiled reed-green cape
    ['0e1408', '1a2410', '2a381a', '3e4e26'],  # the cape in its folds
    ['2a1810', '4a2c1c', '6e4630', '966a48'],  # leather apron
    ['1e1410', '3a2618', '5a3c24', '7e5834'],  # wooden clogs
    ['4a5266', '8a94a8', 'c4cad8', 'eef0f6'],  # moonstone (milky, cool)
    ['4a5670', '8a98b4', 'c8d4e8', 'f4f8ff'],  # silver: the loupe, the pins' heads
    ['0c2a32', '1a5058', '3a8a8c', '8ad8d0'],  # crystal glass
]]
h.RAMPS[h.EYE] = hexc('1a1a22'), hexc('3a4a5a'), hexc('7090a8'), hexc('f2f4f6')  # light grey-blue eyes
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
    """The hair cap leaves the face free, the hair drawn back to the braid."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.05) & (y < 0.62 - 0.38 * np.abs(x) ** 1.6) & (np.abs(x) < 0.88)
    return (y > -0.35) & ~opening


CLIPS = {'idle': {'start': 0, 'count': 4, 'fps': 4}, 'walk': {'start': 4, 'count': 6, 'fps': 7}, 'grind': {'start': 10, 'count': 6, 'fps': 7, 'strike': 3},
         'carve': {'start': 16, 'count': 6, 'fps': 6}, 'basin': {'start': 22, 'count': 8, 'fps': 5}, 'counter': {'start': 30, 'count': 4, 'fps': 3},
         'talk': {'start': 34, 'count': 6, 'fps': 5}, 'listen': {'start': 40, 'count': 4, 'fps': 4}, 'point': {'start': 44, 'count': 6, 'fps': 6},
         'give': {'start': 50, 'count': 6, 'fps': 5}}
FRAMES = 56


def pose(kind, i):
    p = dict(feet=((2.6, 0, 0), (-2.6, 0, 0)), breath=0.3, lean=.03, swing=0.0, work=0.0, t=0.0, head=0.0, crouch=0.0)
    if kind == 'walk':
        a = 2 * math.pi * i / 6; s = math.sin(a); c = math.cos(a)
        p.update(feet=((2.5, 3.0 * s, 1.6 * max(c, 0)), (-2.5, -3.0 * s, 1.6 * max(-c, 0))), lean=.05, swing=s)
    elif kind == 'grind':
        p.update(feet=((2.8, 0.8, 0), (-2.8, -0.6, 0)), lean=.2, work=[0, .3, .7, 1, .6, .2][i], t=i / 6.0, head=.22)
    elif kind == 'carve':
        p.update(feet=((2.8, 0.6, 0), (-2.8, -0.4, 0)), lean=.17, work=[0, .35, .75, 1, .55, .15][i], head=.24)
    elif kind == 'basin':
        w = [0, .25, .6, .9, 1, .9, .55, .2][i]
        p.update(feet=((3.0, 1.4, 0), (-3.0, -1.0, 0)), lean=.15 + .3 * w, crouch=w, t=w, head=.2 + .12 * w)
    elif kind == 'counter':
        p.update(lean=.13, breath=[0, .5, .9, .5][i], head=[0, .03, .06, .03][i])
    elif kind in ('talk', 'listen', 'point', 'give'):
        waves = {'talk': [0, .5, 1, .65, .25, .1], 'listen': [0, .3, .5, .2], 'point': [0, .35, .8, 1, 1, .9], 'give': [0, .25, .65, 1, 1, .85]}
        p.update(t=waves[kind][i], breath=.2 + .3 * waves[kind][i], head=.08 if kind == 'listen' else 0)
    else:
        p.update(breath=[0, .45, .85, .45][i])
    return p


def crystal(m, base, height, r, mat=GLASS, lean=V(0, 0, 0), glow=True):
    n = max(3, int(height / 0.6))
    for k in range(n + 1):
        t = k / n
        rr = r * (1.0 - t ** 1.6 * 0.92)
        m.ell(base + lean * t * height + V(0, height * t, 0), (rr, 0.5, rr), mat)
        if glow and 0.2 < t < 0.75:
            m.ell(base + lean * t * height + V(-rr * 0.2, height * t, rr * 0.7), (max(rr * 0.5, 0.4), 0.5, 0.4), h.TEAL, kind='emit')


def build(p, kind):
    m = h.Model(); ell, limb, ribbon = m.ell, m.limb, m.ribbon
    crouch = p['crouch']
    legs, drop = h.pose_legs(dict(p, pz=0, hair=None)); off = V(0, drop - 3.0 * crouch, 0)
    sw = p['swing']
    # ---------------------------------------------------------------- legs: thick dark stockings, wooden clogs
    for hip, knee, ankle, *_ in legs:
        limb(hip, knee, 2.8, 2.4, DRESS)
        limb(knee, ankle, 2.3, 2.0, DRESS)
        ell(ankle + V(0, -0.6, 1.0), (2.5, 1.9, 3.6), CLOG)
        ell(ankle + V(0, -1.3, 3.6), (1.9, 1.1, 1.9), CLOG)
        ell(ankle + V(0, 0.8, -0.2), (2.3, 0.9, 2.4), CLOG)
    m.off = off
    lean = p['lean']; R = h.rot_x(lean); b = p['breath']

    def T(v):
        return V(0, 26, 0) + R @ (np.asarray(v, float) - V(0, 26, 0))

    # ---------------------------------------------------------------- the skirt: wide, heavy petrol, the hem darker and wet
    for i in range(10):
        t = i / 9.0
        ell(V(sw * 0.7 * t ** 2, 26.5 - 12.0 * t, 0.2), (5.2 + 4.0 * t ** 0.8, 1.6, 4.6 + 3.4 * t ** 0.8), DRESS)
    for k in range(16):
        a = 2 * math.pi * k / 16
        ell(V(sw * 0.7 + math.cos(a) * 8.6, 14.4, 0.2 + math.sin(a) * 7.6), (1.8, 1.2, 1.3), CAPE_D if k % 2 else DRESS, R=h.rot_y(-(a + math.pi / 2)))
    # the leather apron: from the waist to the knees, dusted with glittering stone dust
    ribbon([T((0, 28.0, 4.6)), V(0.2 + sw * .3, 22.0, 7.0), V(0.4 + sw * .6, 16.0, 8.3)], [4.4, 5.0, 4.8], 0.6, APRON, (0, 0, 1), kind='')
    for k, (x, y) in enumerate(((-2.2, 23.0), (1.6, 20.5), (-0.8, 18.0), (2.6, 24.6), (0.4, 16.6), (-3.0, 19.6))):
        ell(V(x + sw * .4, y, 7.9 + (25 - y) * 0.13), (0.35, 0.35, 0.3), h.TEAL if k % 3 == 0 else MOONS, kind='emit' if k % 3 == 0 else '')
    # ---------------------------------------------------------------- torso: broad, sturdy; the cape over shoulders and back
    ell(T((0, 27.4, 0.2)), (5.4, 2.8, 4.2), DRESS, R=R)
    ell(T((0, 31.2, 0.3)), (5.0, 3.4, 3.8), DRESS, R=R)
    ell(T((0, 35.0 + b * .12, 0.6)), (5.4, 3.0, 3.9), DRESS, R=R)
    for a in np.linspace(0, 2 * math.pi, 15)[:-1]:  # apron strings round the waist
        ell(T((math.cos(a) * 5.4, 28.2, 0.2 + math.sin(a) * 4.3)), (1.0, 0.6, 0.8), APRON, R=R)
    ell(T((-5.6, 25.8, 1.4)), (1.8, 2.2, 1.6), APRON, R=R)  # a pouch of stones
    ell(T((-5.6, 27.2, 1.6)), (1.9, 0.6, 1.7), CLOG, R=R)
    limb(T((0, 38.2, 0.2)), T((0, 40.0, 0.4)), 2.0, 1.9, SKIN)
    # the moonstone pendant on a cord
    for sx in (-1, 1):
        for k in range(3):
            ell(T((sx * (2.2 - k * 0.7), 38.0 - k * 1.0, 3.6 + k * 0.25)), (0.28, 0.28, 0.25), CAPE_D, R=R)
    ell(T((0, 35.2, 4.3)), (1.1, 1.3, 0.6), MOONS, R=R)
    ell(T((-0.3, 35.5, 4.8)), (0.45, 0.45, 0.3), h.TEAL, R=R, kind='emit')
    # the cape: over both shoulders, down the back to the knees, the collar turned up
    ell(T((0, 37.6, -1.2)), (7.0, 2.6, 4.0), CAPE, R=R)
    for sx in (-1, 1):
        ell(T((sx * 6.0, 37.0, 0.4)), (2.8, 2.8, 3.4), CAPE, R=R)
        ell(T((sx * 3.4, 39.2, 2.4)), (1.8, 1.4, 1.0), CAPE_D, R=R)
    for k, x in enumerate((-5.4, -2.7, 0.0, 2.7, 5.4)):
        ribbon([T((x, 38.0, -3.4)), T((x * 1.1, 31.0, -5.2 - sw * .2)), V(x * 1.15 + sw * .3, 18.0 + (k % 2), -6.2 - sw * .6)], [2.4, 2.6, 2.2], 0.6,
               CAPE_D if k % 2 else CAPE, (0, 0, -1), kind='')
    # ---------------------------------------------------------------- arms: sleeves rolled to the elbow, bare forearms with crystal scars
    wr = p['work']; t = p['t']
    hands = {}
    for side in (-1, 1):  # -1 = her right
        shoulder = T((side * 6.0, 36.4, 0.2))
        hand = T((side * 7.0, 25.6, side * sw * 1.8 + 0.8)); el = None
        if kind == 'grind':
            a = math.tau * t
            hand = T((side * 2.6 + math.sin(a + side) * 1.2, 28.6 + math.cos(a + side) * 1.2, 7.8))
        elif kind == 'carve':
            hand = T((-3.6 + 4.4 * wr, 28.0 + 1.0 * wr, 7.6)) if side < 0 else T((3.0, 27.4, 7.4))
        elif kind == 'basin':
            hand = T((side * 3.0, 26.0 - 7.0 * t, 6.0 + 4.0 * t))
        elif kind == 'counter':
            hand = T((side * 5.6, 27.6, 7.2))
        elif kind == 'talk':
            hand = T((-7.0 - 2 * t, 26 + 7 * t, 1 + 5 * t)) if side < 0 else T((5.6, 28.0, 2.6))
        elif kind == 'listen':
            hand = T((-5.6, 28.6, 3.2)) if side < 0 else T((5.2, 28.0 + t, 3.4))
        elif kind == 'point':
            hand = T((-7.0 - 9 * t, 26 + 9 * t, 1 + 7 * t)) if side < 0 else T((5.6, 27, 2))
        elif kind == 'give':
            hand = T((side * (4.0 - 1.6 * t), 27 + 3 * t, 2 + 11 * t))
        if el is None:
            mid = (shoulder + hand) / 2
            el = mid + V(side * 1.6, -1.2, -1.4)
        hands[side] = hand
        ell(shoulder, (2.8, 2.6, 2.8), CAPE, R=R)
        limb(shoulder, el, 2.2, 2.0, DRESS)
        ell(el, (2.2, 1.3, 2.2), DRESS)  # the rolled sleeve
        limb(el, hand, 1.75, 1.6, SKIN)
        d = (hand - el) / np.linalg.norm(hand - el)
        for k in range(2):  # crystal scars glitter on the forearm
            ell(el + d * (1.6 + k * 1.8) + V(0, 0.4, 1.2), (0.3, 0.3, 0.25), h.TEAL, kind='emit')
        ell(hand + d * .5, (1.7, 1.8, 1.6), SKIN)
        ell(hand + d * .3 + V(side * -0.9, 0, 1.0), (.65, 1.0, .65), SKIN)
    if kind == 'point' and t > .3:
        limb(hands[-1], hands[-1] + V(-2.4 * t, .5 * t, 2.6 * t), .55, .35, SKIN)
    if kind == 'grind':  # the little wheel in front of her hands, a spark at the strike
        c = T((0, 28.6, 10.5))
        for k in range(14):
            a = k / 14 * math.tau + t * math.tau
            ell(c + V(math.cos(a) * 2.6, math.sin(a) * 2.6, 0), (0.7, 0.7, 0.8), MOONS if k % 3 else SILVER)
        if wr > 0.95:
            for dx, dy in ((-1.6, 1.4), (1.4, 2.2), (0.2, 3.0)):
                ell(c + V(dx, dy, 1.0), (.3, .3, .3), h.TEAL, kind='emit')
    if kind == 'carve':  # a staff blank across her left hand, the knife in her right
        limb(hands[1] + V(-8, -1, 0), hands[1] + V(6, 2, 0), 0.7, 0.6, CLOG)
        dk = V(0.6, 0.3, 0.4); dk /= np.linalg.norm(dk)
        limb(hands[-1], hands[-1] + dk * 3.0, 0.35, 0.2, SILVER)
    if kind in ('basin', 'give'):  # a crystal in her hands, glowing
        c = (hands[-1] + hands[1]) * .5 + V(0, 0.6, 1.0)
        crystal(m, c, 3.6, 1.0)
    # ---------------------------------------------------------------- head: an older face, the braided crown with crystal pins, the loupe
    Rh = R @ h.rot_x(p['head'])
    Ro = Rh * 1.1
    hc = T((0, 44.0 + b * .2, .6))
    ell(hc, (5.1, 5.3, 4.9), SKIN, R=Rh, kind='head')
    ell(hc + Ro @ V(0, .6, -.5), (5.4, 5.6, 5.3), HAIR, R=Rh, kind='hair', tag=3.0, clip=hair_open)
    for side in (-1, 1):
        ell(hc + Ro @ V(side * 1.9, 1.3, 4.25), (1.5, .4, .55), BROW, R=Rh @ rot_z(side * .12))
        ell(hc + Ro @ V(side * 3.0, -1.4, 3.4), (1.1, .8, .6), h.BLUSH, R=Rh)
        ell(hc + Ro @ V(side * 2.3, -0.2, 3.9), (0.9, 0.25, 0.4), SKIN, R=Rh @ rot_z(side * .2))  # a crease under the eye
    ell(hc + Ro @ V(0, -1.0, 4.6), (.7, .9, .55), SKIN, R=Rh)  # a strong nose
    ell(hc + Ro @ V(0, -3.0, 4.0), (1.25, .42, .45), LIP, R=Rh)
    ell(hc + Ro @ V(0, -4.4, 3.1), (2.2, 1.1, 1.8), SKIN, R=Rh)
    # the braid: a thick rope of hair laid round the head like a crown
    for k in range(26):
        a = k / 26 * math.tau
        q = hc + Ro @ V(math.cos(a) * 4.7, 3.6 + 0.4 * math.sin(a * 2), math.sin(a) * 4.5 - 0.6)
        ell(q, (1.5, 1.2, 1.5), HAIR_L if k % 2 else HAIR, R=Rh @ h.rot_y(-a), kind='hair', tag=4.0 + (k % 2))
    for k, a in enumerate((0.6, 1.9, 3.2, 4.4, 5.5)):  # crystal needles through the braid, standing out at angles
        base = hc + Ro @ V(math.cos(a) * 4.9, 4.2, math.sin(a) * 4.6 - 0.6)
        direction = Ro @ V(math.cos(a) * 0.5, 1.0, math.sin(a) * 0.4)
        crystal(m, base, 2.6, 0.55, lean=direction * 0.35 - V(0, 0.35, 0), glow=k % 2 == 0)
    # the loupe pushed up on her forehead: a silver ring with a lens on a band
    lp = hc + Ro @ V(1.6, 3.3, 4.3)
    for k in range(10):
        a = k / 10 * math.tau
        ell(lp + Ro @ V(math.cos(a) * 1.1, math.sin(a) * 1.1, 0), (.35, .35, .35), SILVER, R=Rh)
    ell(lp + Ro @ V(0, 0, 0.2), (0.8, 0.8, 0.3), GLASS, R=Rh)
    ell(lp + Ro @ V(-0.3, 0.3, 0.45), (0.3, 0.3, 0.2), MOONS, R=Rh)
    # two loose strands of grey at the temples
    for side in (-1, 1):
        ribbon([hc + Ro @ V(side * 4.6, 1.6, 2.0), hc + Ro @ V(side * 5.0, -1.6, 2.2), hc + Ro @ V(side * 4.8, -3.6, 1.8)], [0.9, 0.8, 0.4], 0.5, HAIR_L, (side, 0, 1), tag=side + 11.0)
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
    """Only the pixels that shine (the teal of the crystals, the scars and the dust): the unlit second sheet."""
    cols = {tuple(c[:3]) for c in h.RAMPS[h.TEAL]}
    flat = arr.reshape(-1, 4)
    keep = np.array([tuple(int(v) for v in px[:3]) in cols and px[3] > 0 for px in flat])
    out = np.zeros_like(flat); out[keep] = flat[keep]
    return out.reshape(arr.shape)


def main():
    quick = len(sys.argv) > 1 and sys.argv[1] == 'quick'
    jobs = [(s, entry['start'] + i, k, i) for s in range(8) for k, entry in CLIPS.items() for i in range(entry['count'])]
    picks = [0, 6, 13, 19, 26, 31, 36, 46, 53]
    if quick:
        jobs = [j for j in jobs if j[1] in picks]
    arr = np.zeros((8 * FH, FRAMES * FW, 4), dtype=np.uint8)
    print('Rendering', len(jobs), 'lake witch poses', flush=True)
    with mp.Pool(min(6, os.cpu_count() or 1)) as pool:
        for s, i, data in pool.imap_unordered(render_one, jobs, chunksize=2):
            arr[s * FH:(s + 1) * FH, i * FW:(i + 1) * FW] = np.frombuffer(data, dtype=np.uint8).reshape(FH, FW, 4)
    if quick:
        contact(arr, sys.argv[2], picks)
        print('quick sheet written', flush=True)
        return
    write_array(ROOT / 'characters/lake_witch.png', arr)
    write_array(ROOT / 'characters/lake_witch_glow.png', glow_of(arr))
    (ROOT.parent / 'data/lake_witch_rig.json').write_text(json.dumps({'frame': [FW, FH], 'feet': [FW // 2, GROUND], 'frames': FRAMES, 'rows': 8, 'clips': CLIPS}, indent=2) + '\n')
    if len(sys.argv) > 1:
        contact(arr, sys.argv[1], picks)
    print('Lake witch sheet, glow and rig written', flush=True)


if __name__ == '__main__':
    main()
