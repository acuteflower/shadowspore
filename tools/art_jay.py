#!/usr/bin/env python3
"""Eurasian Jay / Eichelhäher (Garrulus glandarius) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 48); 62 columns (WildCorvid / WildMeadowBird layout); 3 builds x 8 facings = 24 rows.
No emissive parts; natural woodland corvid palettes with top-left light and cool-violet shadows.

Builds:
  0: Eurasischer Eichelhäher (warm pinkish-cinnamon / vinaceous-fawn body, vivid electric sky-blue barred wing speculum,
                              black malar moustache & tail, crisp white throat, rump & wing patch)
  1: Dunkler Waldhäher (deeper russet-chestnut forest plumage, bold cobalt-blue barred speculum, crisp black-and-white streaked crest)
  2: Junger Eichelhäher (0.92x scale anchored on GROUND_ROW=48.0, softer warm fawn coat, bright sky-blue wing patch)

Columns (62):
  idle 0:4, peck 4:10 (acorn foraging & caching — holding oak acorn on 4..6, pressing into forest floor on 7..9!),
  walk 10:16, preen 16:22, watch 22:26 ("Waldpolizei" sentinel alert with erected crown crest!),
  call 26:30 (harsh "Räätsch!" alarm shriek with spiky-erect crest, wide bill & drooped blue-flashing wings!),
  fly 30:38, land 38:44, takeoff 44:50, glide 50:54, hop 54:58, roost 58:62.

Usage: py -3 tools/art_jay.py [--preview-only] [--qa=path.png]
"""
from concurrent.futures import ProcessPoolExecutor
import math
from pathlib import Path
import sys
import numpy as np
import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png

ROOT = Path(__file__).resolve().parent.parent
W = H = 64
BUILDS_N = 3
COLS = 62

BODY, WHITE, AZURE, BLACK, TERTIAL, BILL, LEG, ACORN_NUT, ACORN_CUP, EYE, GLINT = range(11)

BLOCKS = [
    ('idle', 0, 4),
    ('peck', 4, 6),
    ('walk', 10, 6),
    ('preen', 16, 6),
    ('watch', 22, 4),
    ('call', 26, 4),
    ('fly', 30, 8),
    ('land', 38, 6),
    ('takeoff', 44, 6),
    ('glide', 50, 4),
    ('hop', 54, 4),
    ('roost', 58, 4),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 48.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE: 4.2,
        GLINT: 4.8,
        AZURE: 2.9,
        ACORN_NUT: 2.7,
        ACORN_CUP: 2.4,
        WHITE: 2.1,
        BLACK: 1.9,
        BILL: 1.5,
    }
    art.ink_color = lambda mat: hexc('0a0814' if mat in (BLACK, EYE, BILL) else '181221')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Eurasischer Eichelhäher: warm pinkish-cinnamon / vinaceous-fawn
        body = ['57333b', '8c5758', 'c28880', 'ebc0b4']
        azure = ['113e8a', '1d74db', '44b2ff', '9ee4ff']
        tertial = ['3b1c24', '693136', '99504d', 'c2766c']
    elif v == 1:
        # 1 Dunkler Waldhäher: deeper dark mahogany-russet woodland plumage & bold royal-cobalt speculum
        body = ['321720', '592b30', '874844', 'b87466']
        azure = ['0a2463', '154eb3', '2d86ed', '7cc4ff']
        tertial = ['241018', '451d23', '6e3333', '99524c']
    else:
        # 2 Junger Eichelhäher: softer warm sandy-fawn coat & bright sky-blue patch
        body = ['614245', '966a65', 'c99f92', 'f0d0c0']
        azure = ['164791', '267fe3', '54baff', 'a8e8ff']
        tertial = ['45242b', '733b3e', 'a35c57', 'ca8278']

    white = ['8e94ab', 'bfc6de', 'eef2fc', 'ffffff']
    black = ['080914', '121526', '222742', '3a4166']
    bill = ['191c2b', '2f354d', '4e5775', '7580a1']
    leg = ['4d333a', '7a5354', 'a87974', 'd1a49a']
    acorn_nut = ['593414', '91591e', 'c98b32', 'f2c15c']
    acorn_cup = ['291914', '4a2e22', '734a35', '9e6b4d']
    eye = ['526078', '8294b0', 'b8cae3', 'eaf3ff']
    glint = ['9aa6b5', 'c2cedb', 'e6eef7', 'ffffff']

    ramps = [body, white, azure, black, tertial, bill, leg, acorn_nut, acorn_cup, eye, glint]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_spread_jay_wing(
    m: art.Model,
    side: float,
    shoulder: np.ndarray,
    span: float,
    lift: float,
    sweep_z: float,
    wrist_fold: float,
    camber: float,
    sz: float,
) -> None:
    """Buoyant rounded woodland corvid wing flashing the electric azure-blue barred speculum,
    crisp snow-white central wing-bar, chestnut inner tertial, and jet-black primaries!"""
    carpal = shoulder + np.array([
        side * span * (0.46 - 0.14 * wrist_fold),
        lift * (0.58 + 0.22 * wrist_fold) + camber,
        (1.75 - 0.85 * wrist_fold) * sz + sweep_z * 0.36,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.22 * wrist_fold),
        lift - 1.55 * sz * wrist_fold,
        (-2.15 - 1.20 * wrist_fold) * sz + sweep_z,
    ])

    # Leading-edge arm & carpal spars
    m.limb(shoulder, carpal, 1.42 * sz, 1.15 * sz, BODY, step=0.60)
    m.limb(carpal, tip, 1.10 * sz, 0.54 * sz, BLACK, step=0.60)

    # Vivid electric azure-blue barred wing speculum ("Flügelspiegel") across outer arm / carpal coverts!
    for j in range(5):
        u = 0.25 + 0.75 * (j / 4.0)
        q = shoulder * (1.0 - u) + carpal * u + np.array([0.0, 0.24 * sz, -1.05 * sz])
        m.ell(q, (1.18 * sz, 0.68 * sz, 1.65 * sz), AZURE)
        if j in (1, 3):
            # Fine jet-black barring inside the blue speculum!
            m.ell(q + np.array([0.0, 0.14 * sz, -0.25 * sz]), (0.42 * sz, 0.48 * sz, 1.35 * sz), BLACK)

    # Inner & middle secondaries: chestnut inner tertial -> snow-white wing patch -> jet-black trailing edge!
    n_sec = 7
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (5.8 - 0.45 * u + 0.65 * math.sin(u * math.pi)) * sz * (1.0 - 0.18 * wrist_fold)
        te = le + np.array([side * 0.35 * u * sz, -0.58 * sz - 0.35 * camber, -chord])
        mid = le * 0.48 + te * 0.52
        if i <= 1:
            m.limb(le, mid, 1.08 * sz, 0.85 * sz, BODY, step=0.62)
            m.limb(mid, te, 0.85 * sz, 0.56 * sz, TERTIAL, step=0.62)
        elif i <= 4:
            # Bold snow-white wing-bar patch contrasting with azure coverts and black trailing tips!
            m.limb(le, mid, 1.05 * sz, 0.86 * sz, AZURE if i >= 3 else WHITE, step=0.60)
            m.limb(mid, le * 0.20 + te * 0.80, 0.88 * sz, 0.72 * sz, WHITE, step=0.58)
            m.limb(le * 0.20 + te * 0.80, te, 0.72 * sz, 0.50 * sz, BLACK, step=0.58)
        else:
            m.limb(le, mid, 1.02 * sz, 0.82 * sz, WHITE, step=0.60)
            m.limb(mid, te, 0.82 * sz, 0.52 * sz, BLACK, step=0.60)

    # Broad rounded fingered black corvid primaries (with white basal flash on inner primaries)
    n_pri = 6
    finger_spread = 1.0 - 0.52 * wrist_fold
    for i in range(n_pri):
        u = (i + 0.14) / n_pri
        le = carpal * (1.0 - u) + tip * u
        fan_angle = -0.22 + 0.88 * u
        plen = (6.3 - 1.25 * u + 0.55 * math.sin(u * math.pi)) * sz * (1.0 - 0.12 * wrist_fold)
        dx = side * math.sin(fan_angle + 0.35) * plen * 0.58 * finger_spread
        dz = -math.cos(fan_angle * 0.64) * plen
        dy = ((u - 0.42) * 0.60 * finger_spread - 0.45 * wrist_fold) * sz
        te = le + np.array([dx, dy, dz])
        if i <= 1:
            mid = le * 0.58 + te * 0.42
            m.limb(le, mid, 0.86 * sz, 0.68 * sz, WHITE, step=0.58)
            m.limb(mid, te, 0.68 * sz, 0.40 * sz, BLACK, step=0.58)
        else:
            m.limb(le, te, (0.82 - 0.14 * u) * sz, 0.38 * sz, BLACK, step=0.60)


def draw_acorn(m: art.Model, pos: np.ndarray, rot: np.ndarray, sz: float) -> None:
    """Warm golden-brown oak acorn (Eichel) with dark sculpted cupule (Fruchtbecher)."""
    # Cupule cap at base
    m.ell(pos + rot @ (np.array([0.0, 0.18, -0.38]) * sz), (0.98 * sz, 0.92 * sz, 0.68 * sz), ACORN_CUP, R=rot)
    # Stem nub
    m.ell(pos + rot @ (np.array([0.0, 0.36, -0.82]) * sz), (0.28 * sz, 0.32 * sz, 0.36 * sz), ACORN_CUP, R=rot)
    # Plump golden-ochre acorn nut body + pointed apex
    m.ell(pos + rot @ (np.array([0.0, -0.05, 0.42]) * sz), (0.86 * sz, 0.84 * sz, 1.18 * sz), ACORN_NUT, R=rot)
    m.ell(pos + rot @ (np.array([0.0, -0.14, 1.28]) * sz), (0.42 * sz, 0.42 * sz, 0.52 * sz), ACORN_NUT, R=rot)


def build_jay(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    # Expressive ~16-18 px forest corvid; Junger Eichelhäher (v==2) is 0.92x scale anchored on GROUND_ROW=48!
    base_sz = 0.98
    sz = base_sz * (0.92 if v == 2 else 1.0)
    tau = math.tau
    p = t * tau
    bob = math.sin(p)

    flying = kind in ('fly', 'takeoff', 'land', 'glide')

    # Default alert woodland corvid stance (GROUND_ROW = 48.0)
    rump_y, rump_z = 5.95 * sz, -2.55 * sz
    chest_y, chest_z = 8.65 * sz, 1.95 * sz
    head_y, head_z = 12.55 * sz, 3.05 * sz
    head_pitch = 0.03
    head_yaw = 0.0
    head_roll = 0.0
    body_sway_x = 0.0
    crest_erect = 0.08          # sleek in idle/fly, high in watch (0.78), spiky-erect in call (1.0)!
    beak_open = 0.0
    blink = False
    tail_pitch = -0.14
    tail_fan = 1.0
    wing_preen_side = 0.0
    wing_droop = 0.0            # drooped/flashed in "Räätsch!" alarm shriek!
    hop_wing = 0.0
    acorn_mode = 0              # 0=none, 1=in bill, 2=caching into ground

    # Feet anchored cleanly on GROUND_ROW = 48.0 (y = 0.68 independent of sz!)
    foot_L = np.array([-1.42 * sz, 0.68, 0.58 * sz])
    foot_R = np.array([1.42 * sz, 0.68, 0.58 * sz])
    toes_curl = 0.0

    if kind == 'idle':
        idx = int(round(t * 4)) % 4
        chest_y += 0.15 * bob * sz
        head_y += 0.18 * bob * sz
        head_yaw = 0.15 * math.sin(p)
        crest_erect = 0.10 + 0.05 * max(0.0, bob)
        blink = (idx == 3)

    elif kind == 'peck':
        # 6 frames: Acorn Foraging & Caching!
        # Frames 4..6 (idx 0,1,2): holding golden oak acorn with dark cupule in bill!
        # Frames 7..9 (idx 3,4,5): bending down deep to press/cache it into the forest floor!
        idx = int(round(t * 6)) % 6
        if idx == 0:
            # Proudly holding freshly found acorn in bill
            acorn_mode = 1
            head_y, head_z = 12.65 * sz, 3.25 * sz
            head_pitch = 0.04
            beak_open = 0.36
            crest_erect = 0.25
        elif idx == 1:
            # Weighing/tilting acorn slightly upward before caching
            acorn_mode = 1
            chest_y = 8.95 * sz
            head_y, head_z = 13.15 * sz, 3.15 * sz
            head_pitch = -0.10
            head_yaw = 0.16
            beak_open = 0.38
            crest_erect = 0.30
        elif idx == 2:
            # Beginning forward bow toward caching spot with acorn in bill
            acorn_mode = 1
            rump_y = 6.35 * sz
            chest_y, chest_z = 7.65 * sz, 2.45 * sz
            head_y, head_z = 9.25 * sz, 5.15 * sz
            head_pitch = 0.34
            beak_open = 0.36
            tail_pitch = 0.10
        elif idx == 3:
            # Deep bow pressing acorn down into the forest floor!
            acorn_mode = 2
            rump_y = 6.95 * sz
            chest_y, chest_z = 6.65 * sz, 2.85 * sz
            head_y, head_z = 5.05 * sz, 7.15 * sz
            head_pitch = 0.62
            beak_open = 0.34
            tail_pitch = 0.32
        elif idx == 4:
            # Driving/tamping acorn deep into the turf!
            acorn_mode = 2
            rump_y = 7.05 * sz
            chest_y, chest_z = 6.45 * sz, 2.95 * sz
            head_y, head_z = 4.45 * sz, 7.35 * sz
            head_pitch = 0.68
            beak_open = 0.22
            tail_pitch = 0.36
        else:
            # Rising back up after caching acorn cleanly into soil
            acorn_mode = 0
            rump_y = 6.25 * sz
            chest_y, chest_z = 7.95 * sz, 2.25 * sz
            head_y, head_z = 10.65 * sz, 4.25 * sz
            head_pitch = 0.18
            beak_open = 0.06
            crest_erect = 0.22
            tail_pitch = 0.04

    elif kind == 'walk':
        # 6-frame lively woodland corvid stride/strut
        for s_idx, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_idx == 0 else 0.5)) % 1.0
            if c < 0.55:
                u = c / 0.55
                fz = (1.95 - 3.30 * u) * sz
                fy = 0.68
            else:
                u = (c - 0.55) / 0.45
                fz = (-1.35 + 3.30 * u) * sz
                fy = 0.68 + math.sin(u * math.pi) * 2.05 * sz
            if s_idx == 0:
                foot_L = np.array([side * 1.45 * sz, fy, fz])
            else:
                foot_R = np.array([side * 1.45 * sz, fy, fz])
        bob2 = math.sin(p * 2.0)
        body_sway_x = 0.32 * math.sin(p) * sz
        chest_y += 0.30 * abs(bob2) * sz
        rump_y += 0.24 * abs(bob2) * sz
        head_z += (0.80 * max(0.0, bob2) + 0.22) * sz
        head_y += (0.28 * bob2 - 0.15) * sz
        crest_erect = 0.18
        tail_pitch = -0.10 + 0.10 * bob2

    elif kind == 'preen':
        # 6 frames: preening electric-blue wing speculum & cinnamon breast feathers
        idx = int(round(t * 6)) % 6
        turn_amt = [0.45, 0.96, 1.0, 0.94, 0.38, 0.0][idx]
        fluff = 1.10 if idx == 4 else 1.0
        head_yaw = 1.28 * turn_amt
        head_pitch = 0.38 * turn_amt + (0.14 if idx == 3 else 0.0)
        head_y = (12.55 - 1.55 * turn_amt + (0.42 if idx == 4 else 0.0)) * sz
        head_z = (3.05 - 1.85 * turn_amt) * sz
        chest_y *= fluff
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
        crest_erect = 0.28 if idx == 4 else 0.12
        tail_fan = 1.25 if idx == 4 else 1.0

    elif kind == 'watch':
        # 4 frames: "Waldpolizei" Sentinel Alert!
        # Black-and-white crown crest erected high, tail flicked slightly up, intense watchful gaze!
        idx = int(round(t * 4)) % 4
        cock = [0.18, 0.38, -0.32, -0.14][idx]
        chest_y = 9.25 * sz
        chest_z = 2.15 * sz
        head_y = 13.55 * sz
        head_z = 3.25 * sz
        head_pitch = -0.06
        head_yaw = cock * 0.95
        head_roll = cock * 0.75
        crest_erect = 0.82
        tail_pitch = 0.16 + (0.10 if idx in (1, 2) else 0.0)
        tail_fan = 1.18

    elif kind == 'call':
        # 4 frames: Harsh "Räätsch!" Alarm Shriek!
        # Crown crest fully spiky-erect, bill wide open, wings slightly drooped showing bright blue speculum, body pitched forward!
        idx = int(round(t * 4)) % 4
        shriek = [0.28, 1.0, 0.94, 0.38][idx]
        rump_y = (5.95 + 0.75 * shriek) * sz
        chest_y = (8.65 - 0.65 * shriek) * sz
        chest_z = (1.95 + 1.05 * shriek) * sz
        head_y = (12.55 - 1.15 * shriek) * sz
        head_z = (3.05 + 2.25 * shriek) * sz
        head_pitch = -0.05 + 0.22 * shriek
        beak_open = [0.25, 1.0, 0.92, 0.28][idx]
        crest_erect = 0.55 + 0.45 * shriek
        wing_droop = 0.85 * shriek
        tail_pitch = 0.12 * shriek
        tail_fan = 1.0 + 0.65 * shriek

    elif kind == 'hop':
        # 4-frame springy two-footed corvid ground hop!
        idx = int(round(t * 4)) % 4
        if idx == 0:
            rump_y, chest_y, head_y = 5.15 * sz, 7.45 * sz, 11.15 * sz
            hop_wing = 0.35
            crest_erect = 0.22
        elif idx in (1, 2):
            lift = 2.65 if idx == 1 else 2.25
            rump_y, chest_y, head_y = (6.25 + lift) * sz, (8.65 + lift) * sz, (12.35 + lift) * sz
            chest_z += 0.55 * sz
            head_z += 0.75 * sz
            foot_L = np.array([-1.42 * sz, 2.25 * sz, 1.65 * sz])
            foot_R = np.array([1.42 * sz, 2.25 * sz, 1.65 * sz])
            hop_wing = 0.88 if idx == 1 else 0.58
            crest_erect = 0.35
            tail_fan = 1.28
        else:
            rump_y, chest_y, head_y = 5.55 * sz, 8.05 * sz, 11.85 * sz
            hop_wing = 0.20
            crest_erect = 0.18

    elif kind == 'roost':
        # 4-frame fluffed nocturnal branch roost: bill tucked slightly, crest completely relaxed
        idx = int(round(t * 4)) % 4
        rump_y, rump_z = (5.55 + 0.08 * bob) * sz, -2.25 * sz
        chest_y, chest_z = (7.55 + 0.10 * bob) * sz, 1.55 * sz
        head_y, head_z = (10.25 + 0.08 * bob) * sz, 2.15 * sz
        head_pitch = 0.18
        crest_erect = 0.0
        tail_pitch = -0.34
        blink = idx in (1, 2, 3)

    elif flying:
        if kind == 'fly':
            idx = int(round(t * 8)) % 8
            body_lift = [-0.28, -0.10, 0.38, 0.60, 0.28, -0.06, -0.26, -0.32][idx] * sz
            by = 11.8 * sz + body_lift
            rump_y, rump_z = by - 0.55 * sz, -3.05 * sz
            chest_y, chest_z = by + 0.35 * sz, 2.25 * sz
            head_y, head_z = by + 1.45 * sz, 4.95 * sz
            head_pitch = 0.08
            crest_erect = 0.05
            tail_pitch = -0.04
            tail_fan = 1.18
            toes_curl = 1.0
            foot_L = np.array([-1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])
            foot_R = np.array([1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])

        elif kind == 'glide':
            by = (12.0 + 0.14 * bob) * sz
            rump_y, rump_z = by - 0.55 * sz, -3.05 * sz
            chest_y, chest_z = by + 0.35 * sz, 2.25 * sz
            head_y, head_z = by + 1.45 * sz, 4.95 * sz
            head_yaw = 0.08 * bob
            head_pitch = 0.06
            crest_erect = 0.04
            tail_pitch = -0.05
            tail_fan = 1.38
            toes_curl = 1.0
            foot_L = np.array([-1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])
            foot_R = np.array([1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])

        elif kind == 'takeoff':
            idx = int(round(t * 6)) % 6
            if idx == 0:
                rump_y, rump_z = 5.05 * sz, -2.55 * sz
                chest_y, chest_z = 6.55 * sz, 2.25 * sz
                head_y, head_z = 9.75 * sz, 4.25 * sz
                head_pitch = 0.16
                crest_erect = 0.32
                tail_fan = 1.28
            else:
                u = ease(idx / 5.0)
                by = (7.5 + 4.5 * u) * sz
                rump_y, rump_z = by - (1.0 - 0.45 * u) * sz, (-2.6 - 0.45 * u) * sz
                chest_y, chest_z = by + (0.8 - 0.45 * u) * sz, 2.30 * sz
                head_y, head_z = by + (2.7 - 1.25 * u) * sz, 4.75 * sz
                crest_erect = 0.25 * (1.0 - u)
                tail_fan = 1.38
                toes_curl = min(1.0, u * 1.2)
                fy = (1.4 + 6.8 * u) * sz
                fz = (0.6 - 1.8 * u) * sz
                foot_L = np.array([-1.32 * sz, fy, fz])
                foot_R = np.array([1.32 * sz, fy, fz])

        elif kind == 'land':
            # Fanned black tail (+ bright white rump!) & outstretched blue-and-white wings braking to land!
            idx = int(round(t * 6)) % 6
            flare = [0.86, 1.0, 0.94, 0.70, 0.36, 0.0][idx]
            climb_y = [3.6, 2.8, 1.9, 1.0, 0.3, 0.0][idx] * sz
            rump_y, rump_z = 5.95 * sz + climb_y - 0.35 * flare * sz, (-2.55 - 0.40 * flare) * sz
            chest_y, chest_z = 8.65 * sz + climb_y + 0.85 * flare * sz, (1.95 - 0.35 * flare) * sz
            head_y, head_z = 12.55 * sz + climb_y - 0.20 * flare * sz, (3.05 - 0.10 * flare) * sz
            crest_erect = 0.38 * flare + 0.12
            tail_pitch = -0.14 - 0.42 * flare
            tail_fan = 1.0 + 0.72 * flare
            reach_z = (0.58 + 1.65 * flare) * sz
            reach_y = 0.68 + climb_y * 0.65
            foot_L = np.array([-1.42 * sz, reach_y, reach_z])
            foot_R = np.array([1.42 * sz, reach_y, reach_z])

    # ---- Plump Expressive Vinaceous-Cinnamon Torso + Snow-White Rump & Undertail ----
    fluff_r = 1.10 if kind == 'roost' else 1.0
    for u in (0.15, 0.42, 0.72, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz_p = rump_z + (chest_z - rump_z) * u
        arch = math.sin(u * math.pi)
        rx = (2.55 + 0.52 * arch) * sz * fluff_r
        ry = (2.62 + 0.56 * arch) * sz * fluff_r
        rz = (2.82 - 0.20 * u) * sz
        m.ell((body_sway_x, sy, sz_p), (rx, ry, rz), BODY)

    # Iconic bright snow-white rump & uppertail/undertail cushion ("weißer Bürzel")!
    m.ell((body_sway_x, rump_y + 0.25 * sz, rump_z - 0.65 * sz), (2.38 * sz * fluff_r, 2.25 * sz, 2.25 * sz), WHITE)
    m.ell((body_sway_x, rump_y - 0.65 * sz, rump_z - 0.35 * sz), (1.85 * sz, 1.55 * sz, 1.85 * sz), WHITE)

    # Neck bridge (warm cinnamon nape/sides + crisp white front throat)
    for u in (0.35, 0.72):
        ny = chest_y + (head_y - chest_y) * u
        nz = chest_z + (head_z - chest_z) * u - 0.22 * sz
        nr = (2.10 - 0.25 * u) * sz * fluff_r
        m.ell((body_sway_x, ny, nz), (nr, nr * 1.04, nr), BODY)

    # Pure white throat bib ("weiße Kehle")
    m.ell((body_sway_x, head_y - 1.65 * sz, head_z + 1.18 * sz), (1.35 * sz, 1.45 * sz, 1.15 * sz), WHITE)

    # ---- Wings: Folded (Electric Azure-Blue Barred Speculum + White Patch + Black Primaries) OR Spread ----
    mid_y = 0.45 * rump_y + 0.55 * chest_y
    mid_z = 0.45 * rump_z + 0.55 * chest_z
    max_span = 15.2
    for side in (-1.0, 1.0):
        sh = np.array([body_sway_x + side * 2.22 * sz, chest_y + 0.35 * sz, chest_z - 0.35 * sz])
        folded_now = (
            not flying
            or (kind == 'takeoff' and int(round(t * 6)) % 6 == 0)
            or (kind == 'land' and int(round(t * 6)) % 6 == 5)
        )
        if folded_now:
            preen_open = 1.0 if side * wing_preen_side > 0 else 0.0
            flick = hop_wing + 0.65 * preen_open + 0.55 * wing_droop
            if hop_wing > 0.65:
                draw_spread_jay_wing(
                    m, side, sh,
                    span=max_span * 0.68,
                    lift=4.2 * hop_wing * sz,
                    sweep_z=0.5 * sz,
                    wrist_fold=0.32,
                    camber=0.8 * sz,
                    sz=sz,
                )
            else:
                droop_y = -0.75 * wing_droop
                w_rot = (
                    art.rot_y(side * (0.11 + 0.30 * flick))
                    @ art.rot_x(-0.30 + 0.14 * preen_open - 0.22 * wing_droop)
                    @ rot_z(-side * 0.24 * flick)
                )
                w_center = np.array([
                    body_sway_x + side * (2.35 + 0.85 * flick) * sz,
                    mid_y + (0.25 + 0.45 * preen_open + droop_y) * sz,
                    mid_z - 0.45 * sz,
                ])
                # Base scapular/tertial cushion
                m.ell(w_center, (1.08 * sz, 2.05 * sz, 3.45 * sz), TERTIAL, R=w_rot)
                # Iconic gleaming electric azure-blue barred speculum on upper/anterior folded wing!
                spec_c = w_center + w_rot @ (np.array([side * 0.45, 0.42, 0.72]) * sz)
                m.ell(spec_c, (0.66 * sz, 1.25 * sz, 1.85 * sz), AZURE, R=w_rot)
                # Fine jet-black cross-bars across the azure speculum
                for sb in (-0.55, 0.45):
                    m.ell(spec_c + w_rot @ (np.array([side * 0.22, 0.05, sb]) * sz),
                          (0.52 * sz, 0.92 * sz, 0.26 * sz), BLACK, R=w_rot)
                # Crisp snow-white wing patch right behind/below the azure speculum!
                m.ell(w_center + w_rot @ (np.array([side * 0.40, -0.35, -0.88]) * sz),
                      (0.60 * sz, 0.85 * sz, 1.25 * sz), WHITE, R=w_rot)
                # Stepped jet-black folded primary tips extending toward tail!
                for pf in range(3):
                    p_pos = w_center + w_rot @ (np.array([
                        -side * 0.24 * pf,
                        -0.65 + 0.18 * pf,
                        -2.35 - 0.95 * pf,
                    ]) * sz)
                    m.ell(p_pos, (0.66 * sz, 0.78 * sz, 1.95 * sz), BLACK, R=w_rot)
        else:
            if kind == 'fly':
                idx = int(round(t * 8)) % 8
                lifts = [8.4, 4.0, -1.4, -6.2, -3.4, 1.8, 6.0, 8.8][idx] * sz
                folds = [0.08, 0.0, 0.0, 0.10, 0.50, 0.60, 0.36, 0.15][idx]
                sweeps = [-1.4, 0.8, 2.2, 2.8, 0.5, -1.2, -2.0, -1.7][idx] * sz
                cambers = [0.6, 1.3, 1.5, 0.9, 0.3, 0.5, 0.9, 0.8][idx] * sz
                draw_spread_jay_wing(m, side, sh, max_span, lifts, sweeps, folds, cambers, sz)
            elif kind == 'glide':
                dihedral = (1.15 + 0.40 * bob) * sz
                draw_spread_jay_wing(m, side, sh, max_span * 1.04, dihedral, -0.30 * sz, 0.02, 1.05 * sz, sz)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                lifts = [0.0, 9.0, 2.4, -5.6, 0.9, 7.6][idx] * sz
                folds = [0.0, 0.08, 0.0, 0.08, 0.48, 0.15][idx]
                sweeps = [0.0, -1.2, 1.8, 2.8, -0.6, -1.4][idx] * sz
                draw_spread_jay_wing(m, side, sh, max_span, lifts, sweeps, folds, 1.1 * sz, sz)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                lifts = [5.8, 1.8, 6.8, 3.5, 1.8, 0.0][idx] * sz
                folds = [0.10, 0.06, 0.14, 0.35, 0.68, 1.0][idx]
                sweeps = [2.4, 3.2, 2.0, 1.2, -0.4, 0.0][idx] * sz
                draw_spread_jay_wing(m, side, sh, max_span * 0.94, lifts, sweeps, folds, 1.2 * sz, sz)

    # ---- Medium-Long Jet-Black Jay Tail (contrasting sharply against snow-white rump!) ----
    tail_len_base = 6.35 if v == 2 else 7.15
    t_base = np.array([body_sway_x, rump_y - 0.25 * sz, rump_z - 2.05 * sz])
    for f_i in range(-2, 3):
        t_len = (tail_len_base - abs(f_i) * 0.38) * sz
        f_yaw = -f_i * 0.14 * tail_fan
        t_rot = art.rot_y(f_yaw) @ art.rot_x(tail_pitch)
        t_end = t_base + t_rot @ np.array([0.0, 0.0, -t_len])
        m.limb(t_base, t_end, 0.88 * sz, 0.60 * sz, BLACK, step=0.62)

    # ---- Cinnamon Thighs + Warm Pinkish-Horn Tarsus Legs & Gripping Toes ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        ft = foot_L if s_idx == 0 else foot_R
        hip = np.array([body_sway_x + side * 1.38 * sz, rump_y - 0.55 * sz, rump_z + 2.15 * sz])
        ankle = 0.42 * hip + 0.58 * ft + np.array([0.0, 0.65 * sz, -0.42 * sz])
        m.ell(0.65 * hip + 0.35 * ankle, (1.05 * sz, 1.35 * sz, 1.15 * sz), BODY)
        m.limb(ankle, ft, 0.60 * sz, 0.52 * sz, LEG, step=0.44)
        if toes_curl < 0.7:
            for toe in (-1, 0, 1):
                t_tip = ft + np.array([toe * 0.68 * sz, -0.16, 1.45 * sz])
                m.limb(ft, t_tip, 0.44 * sz, 0.32 * sz, LEG, step=0.42)
            m.limb(ft, ft + np.array([0.0, -0.14, -0.95 * sz]), 0.40 * sz, 0.30 * sz, LEG, step=0.42)
        else:
            m.ell(ft, (0.68 * sz, 0.58 * sz, 0.85 * sz), LEG)

    # ---- Expressive Jay Head, Black-Streaked White Crest ("Federhaube"), Moustache & Stout Bill ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([body_sway_x, head_y, head_z])

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ (np.array([x, y, z]) * sz)

    # Vinaceous-fawn cheeks & nape cranium
    m.ell(hp(0.0, -0.05, -0.05), (2.10 * sz, 2.18 * sz, 2.38 * sz), BODY, R=h_rot)
    # Pure white chin/upper throat cushion right under lower mandible
    m.ell(hp(0.0, -0.95, 1.25), (1.32 * sz, 0.98 * sz, 1.25 * sz), WHITE, R=h_rot)

    # Bold jet-black malar moustache stripe ("kräftiger schwarzer Bartstreif")!
    for side in (-1.0, 1.0):
        m.limb(hp(side * 1.10, -0.35, 1.68), hp(side * 1.72, -1.05, 0.15), 0.56 * sz, 0.50 * sz, BLACK, step=0.36)

    # Black-streaked whitish forehead & erectile crown crest ("Federhaube")!
    # Sleek against skull when crest_erect ~ 0, sharply erected in 'watch', fully spiky-erect in 'call'!
    m.ell(hp(0.0, 1.18, 0.78), (1.58 * sz, 0.82 * sz, 1.38 * sz), WHITE, R=h_rot)
    # Warm vinaceous rear-nape cushion so sleek crown transitions naturally into cinnamon nape
    m.ell(hp(0.0, 0.55, -1.25), (1.82 * sz, 1.45 * sz, 1.35 * sz), BODY, R=h_rot)
    # Prominent black longitudinal forehead & crown streaks ("schwarz-weiß gestrichelte Haube")
    for sx in (-0.92, 0.0, 0.92):
        m.limb(hp(sx, 1.48, 1.52), hp(sx, 1.88, -0.25), 0.38 * sz, 0.36 * sz, BLACK, step=0.34)

    # Erectile black-and-white crown crest feather spikes (5 rows from fore-crown to rear crown!)
    for c_i in range(5):
        u = c_i / 4.0
        base_z = 0.85 - u * 1.95
        base_y = 1.52 - u * 0.22
        # Angle sweeps from sleek backward (-1.35 rad from +y) to spiky-erect upward (-0.10..-0.52 rad)!
        ang = -1.34 * (1.0 - crest_erect) + (-0.10 - u * 0.42) * crest_erect
        f_len = (1.45 + 1.50 * crest_erect) * (1.05 - 0.15 * abs(u - 0.4))
        dy = math.cos(ang) * f_len
        dz = math.sin(ang) * f_len
        for sx in (-0.78, 0.0, 0.78):
            # Alternating snow-white & jet-black streaked crest spikes!
            is_black = ((c_i + (1 if sx == 0.0 else 0)) % 2 == 0)
            mat_c = BODY if (crest_erect < 0.35 and c_i == 4 and not is_black) else (BLACK if is_black else WHITE)
            p0 = hp(sx * (1.0 - 0.15 * u), base_y, base_z)
            p1 = hp(sx * (1.0 + 0.18 * crest_erect), base_y + dy, base_z + dz)
            m.limb(p0, p1, 0.50 * sz, 0.26 * sz, mat_c, step=0.36)

    # Stout Dark Corvid Bill (arched upper culmen + separating lower mandible)
    bill_len = 2.95
    up_rot = h_rot @ art.rot_x(-0.30 * beak_open + 0.04)
    b_base = hp(0.0, -0.05 + 0.12 * beak_open, 1.75)
    for i in range(5):
        u = i / 4.0
        arch_y = 0.14 * math.sin(u * math.pi) - 0.18 * u * u
        pos = b_base + up_rot @ (np.array([0.0, arch_y, u * bill_len]) * sz)
        rw = 0.86 * (1.0 - 0.66 * u) * sz
        rh = 0.78 * (1.0 - 0.64 * u) * sz
        m.ell(pos, (max(0.34, rw), max(0.32, rh), 0.72 * sz), BILL, R=up_rot)

    lo_rot = h_rot @ art.rot_x(0.54 * beak_open)
    l_base = hp(0.0, -0.48 - 0.34 * beak_open, 1.70)
    l_tip = l_base + lo_rot @ (np.array([0.0, -0.10, bill_len * 0.90]) * sz)
    m.limb(l_base, l_tip, 0.64 * sz, 0.32 * sz, BILL, step=0.44)

    # Oak Acorn ("Eichel") in 'peck' (4..6 held prominently in bill; 7..8 pressed into forest floor)!
    if acorn_mode == 1:
        ac_pos = hp(0.0, -0.36, 4.48)
        ac_rot = h_rot @ art.rot_x(0.42) @ art.rot_y(0.22)
        draw_acorn(m, ac_pos, ac_rot, sz * 1.12)
    elif acorn_mode == 2:
        # Pressed vertically/angled right into the forest floor at the bill tip!
        tip_world = hp(0.0, -0.35, 4.25)
        ground_ac = np.array([tip_world[0], max(1.08, tip_world[1] - 0.30 * sz), tip_world[2] + 0.32 * sz])
        ac_rot = art.rot_x(1.12)
        draw_acorn(m, ground_ac, ac_rot, sz * 1.05)

    # Pale Pearly Bluish-Grey Corvid Iris + Dark Pupil + Catchlight
    for side in (-1.0, 1.0):
        eh = 0.16 if blink else 0.62
        m.ell(hp(side * 1.62, 0.36, 0.92), (0.52 * sz, eh * sz, 0.62 * sz), EYE, R=h_rot)
        if not blink:
            m.ell(hp(side * 1.80, 0.35, 0.98), (0.28 * sz, 0.32 * sz, 0.32 * sz), BLACK, R=h_rot)
            m.ell(hp(side * 1.76, 0.56, 1.18), (0.22 * sz, 0.22 * sz, 0.22 * sz), GLINT, R=h_rot)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_jay(v, kind, (col - start) / n)
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_qa(out_path: Path, zoom: int = 3) -> None:
    picks = [
        (0, 0),   # E idle (sleek crest, black moustache, white throat, gleaming azure wing speculum!)
        (1, 0),   # SE idle 3/4 view
        (2, 0),   # S idle front view (white throat + black moustache!)
        (6, 0),   # N idle dorsal view (white rump + black tail + blue wing patches!)
        (0, 5),   # E peck frame 5: holding golden oak acorn with dark cupule in bill!
        (1, 4),   # SE peck frame 4: holding oak acorn in bill!
        (0, 7),   # E peck frame 7: bending down to press/cache acorn into forest floor!
        (0, 11),  # E lively ground stride
        (1, 18),  # SE preening azure wing speculum
        (1, 23),  # SE "Waldpolizei" watch (erected black-and-white crown crest!)
        (0, 27),  # E harsh "Räätsch!" alarm shriek (spiky-erect crest, wide bill, drooped blue wing!)
        (1, 27),  # SE harsh "Räätsch!" alarm shriek!
        (1, 30),  # SE fly upstroke (sky-blue patch, white wing-bar, white rump, black tail!)
        (1, 33),  # SE fly downstroke
        (2, 51),  # S broad woodland glide (full blue/white/black wing pattern check!)
        (0, 39),  # E braking landing flare (fanned black tail + white rump + blue/white wings!)
        (1, 59),  # SE fluffed nocturnal roost
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([34, 42, 50, 255], np.uint8)
    grid[:, :] = bg
    for v in range(BUILDS_N):
        for ci, (d, col) in enumerate(picks):
            px = frame(v, d, col)
            cell = grid[v * H:(v + 1) * H, ci * W:(ci + 1) * W]
            mask = px[:, :, 3] > 0
            cell[mask] = px[mask]
    zoomed = np.repeat(np.repeat(grid, zoom, axis=0), zoom, axis=1)
    save_png(out_path, zoomed)


def main() -> None:
    for arg in sys.argv[1:]:
        if arg.startswith('--qa='):
            out = Path(arg.split('=', 1)[1])
            out.parent.mkdir(parents=True, exist_ok=True)
            render_qa(out, zoom=3)
            print(f'QA sheet written to {out}')
            return

    if '--preview-only' in sys.argv:
        return

    sheet = np.zeros((BUILDS_N * 8 * H, COLS * W, 4), np.uint8)
    jobs = [(v, d) for v in range(BUILDS_N) for d in range(8)]
    with ProcessPoolExecutor() as pool:
        for done, (v, d, row_px) in enumerate(pool.map(_render_row, jobs), 1):
            y = (v * 8 + d) * H
            sheet[y:y + H, :] = row_px
            if done % 8 == 0:
                print(f'jay build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/jay.png', sheet)
    print('Saved assets/wildlife/jay.png', sheet.shape)


if __name__ == '__main__':
    main()
