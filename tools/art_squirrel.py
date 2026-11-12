#!/usr/bin/env python3
"""European Red Squirrel (Europäisches Eichhörnchen - Sciurus vulgaris) in the 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 4 builds x 8 true facings = 32 rows (3328x2048). No emissive parts.
Builds:
  0: Klassisches Fuchsrot (vibrant burnt-orange / rust-red coat, white chest/belly)
  1: Bergwald-Dunkelbraun (deep espresso-chestnut coat, white chest/belly)
  2: Rußschwarz (sleek melanistic soot-black coat, crisp white chest/belly)
  3: Zimt-/Haselrot (warm golden-cinnamon woodland coat, white chest/belly)
Columns (52):
  idle 0:4 (perched upright on hind haunches, forepaws tucked at white chest, S-tail gently waving),
  forage 4:10 (all-fours nose-down digging & patting a seed/nut cache),
  walk 10:18 (bouncy arched-back ground hop-scamper),
  alert 18:22 (tall upright sentinel posture with rapid expressive S-tail whip - scolding!),
  run 22:30 (fast stretched-out darting bound, fluffy tail streaming horizontally behind),
  groom 30:34 (seated washing muzzle/ears with both forepaws),
  sleep 34:38 (curled ball with big fluffy tail wrapped warmly over back/head),
  special 38:46 (seated upright holding a distinct brown spruce cone / Tannenzapfen in both paws, rotating & gnawing),
  climb 46:52 (vertical tree-trunk climbing cycle ~72 deg nose-up, splayed limbs pulling upward, tail trailing down).
Usage: py -3 tools/art_squirrel.py [--preview-only] [--qa=path.png]
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
BUILDS_N = 4
COLS = 52

COAT, TAIL, BELLY, TUFT, EYE, GLINT, NOSE_PAW, CONE = range(8)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 6),
    ('walk', 10, 8),
    ('alert', 18, 4),
    ('run', 22, 8),
    ('groom', 30, 4),
    ('sleep', 34, 4),
    ('special', 38, 8),
    ('climb', 46, 6),
]

BUILDS = [
    # 0 Klassisches Fuchsrot: vibrant burnt-orange / rust-red coat & rich flame-russet plume
    (
        ['5c221c', '9b3c25', 'd46631', 'f4984e'],
        ['461816', '7c2d1e', 'b44f28', 'de7e3e'],
        ['3d1414', '6e251a', 'a24323', 'cc6e37'],
    ),
    # 1 Bergwald-Dunkelbraun: deep espresso-chestnut coat & rich dark umber plume
    (
        ['2a181c', '4c2c2b', '75473d', 'a16957'],
        ['1f1116', '3a2021', '5c3530', '845144'],
        ['1a0e14', '321b1d', '512e2a', '76483d'],
    ),
    # 2 Rußschwarz: sleek melanistic soot-black coat & velvety charcoal-black plume
    (
        ['11111a', '212131', '38384d', '55556e'],
        ['0c0c14', '191926', '2c2c3f', '46465d'],
        ['0a0a12', '161622', '28283a', '404056'],
    ),
    # 3 Zimt-/Haselrot: warm golden-cinnamon woodland coat & toasted hazel plume
    (
        ['55311e', '8e542c', 'c47f40', 'eab067'],
        ['442518', '744123', 'a56734', 'cf9452'],
        ['3a1f15', '66381f', '945a2d', 'bd8347'],
    ),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE: 4.2,
        GLINT: 5.0,
        TUFT: 2.45,
        CONE: 2.65,
        NOSE_PAW: 1.85,
        BELLY: 1.35,
    }
    art.ink_color = lambda mat: hexc('120f1b' if mat in (EYE, TUFT, CONE) else '241b25')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def bezier3(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, u: float) -> np.ndarray:
    v = 1.0 - u
    return (v ** 3) * p0 + 3.0 * (v ** 2) * u * p1 + 3.0 * v * (u ** 2) * p2 + (u ** 3) * p3


def materials(v: int) -> None:
    setup_art()
    coat, tail, tuft = BUILDS[v % BUILDS_N]
    belly = ['888286', 'b8b2b4', 'e6e0dc', 'fffaf2']
    if v == 2:
        belly = ['858a96', 'b6bcc8', 'e5e9f0', 'fcfdff']
    # Woody spruce cone (Tannenzapfen): rich dark conifer-brown on bright red/cinnamon coats, warm golden-bark brown on dark coats!
    if v in (0, 3):
        cone = ['1c1110', '38221a', '5d3a27', '85573b']
    else:
        cone = ['2c1b12', '573621', '8a5936', 'bc8354']
    ramps = [
        coat,                                               # 0 COAT
        tail,                                               # 1 TAIL (voluminous S-curved squirrel plume)
        belly,                                              # 2 BELLY (crisp cream-white chest & belly)
        tuft,                                               # 3 TUFT (prominent Pinselöhrchen ear-tufts)
        ['090811', '131120', '211d32', '322c46'],           # 4 EYE (dark glossy eye)
        ['c8c2ca', 'e2dce0', 'f5efe6', 'fffcf4'],           # 5 GLINT
        ['4d333c', '764f59', '9f6f78', 'c6959c'],           # 6 NOSE_PAW (dainty pink-brown nose & digits)
        cone,                                               # 7 CONE (distinct woody spruce cone / Tannenzapfen)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def build_squirrel(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)

    # ---- SLEEP: Cozy curled woodland ball with huge fluffy tail wrapped warmly over back & head! ----
    if kind == 'sleep':
        breath = 0.12 * b
        by = 2.75 + breath
        # Curled squirrel body low in a cozy round nest posture
        for i in range(8):
            ang = -0.55 + 2.65 * (i / 7.0)
            rad = 2.65
            cx = math.sin(ang) * rad * 0.92 - 0.35
            cz = math.cos(ang) * rad - 0.25
            m.ell((cx, by + 0.22 * math.sin(i * 0.5), cz), (2.25, 2.05, 2.25), COAT)
        # Tucked head resting peacefully inward
        hx, hy, hz = -1.15, by + 1.05, 2.35
        rot_h = art.rot_y(-0.48) @ art.rot_x(0.22)
        m.ell((hx, hy, hz), (1.82, 1.70, 2.00), COAT, R=rot_h)
        m.ell((hx - 0.55, hy - 0.32, hz + 1.42), (0.98, 0.82, 1.18), COAT, R=rot_h)
        for side in (-1.0, 1.0):
            m.ell((hx + side * 1.18, hy + 0.15, hz + 0.78), (0.38, 0.15, 0.40), EYE, R=rot_h)
            e_pos = np.array([hx + side * 0.98, hy + 1.48, hz - 0.35])
            m.ell(e_pos, (0.56, 0.92, 0.44), COAT, R=rot_h)
            m.limb(e_pos + np.array([0.0, 0.55, -0.05]), e_pos + np.array([side * 0.22, 1.75, -0.25]), 0.44, 0.28, TUFT, step=0.25)
        # Huge fluffy squirrel tail sweeping around the side and blanketing over back & crown of head!
        p0 = np.array([1.6, by - 0.1, -2.8])
        p1 = np.array([4.6, by + 1.4, -1.2])
        p2 = np.array([3.2, by + 3.4, 2.6])
        p3 = np.array([-1.2, by + 2.8, 3.4])
        radii = [1.55, 2.05, 2.50, 2.68, 2.55, 2.25, 1.75]
        for ti, r_t in enumerate(radii):
            u = ti / (len(radii) - 1)
            pt = bezier3(p0, p1, p2, p3, u)
            m.ell(pt, (r_t * 1.08, r_t * 0.92, r_t * 1.10), TAIL)
        return m

    # ---- Posture & Biomechanics across all active animations ----
    # Properly scaled nimble squirrel (~13-16px tall when upright, smaller than rabbit!)
    rump_y, rump_z = 2.95, -1.35
    chest_y, chest_z = 6.35, 0.65
    hy, hz = 9.45, 1.35
    pitch = 0.06
    yaw = 0.0
    roll = 0.0
    spine_arch = 0.45

    hind_L = np.array([-1.55, 0.68, 0.55])
    hind_R = np.array([1.55, 0.68, 0.55])
    hock_L = np.array([-1.75, 1.55, -1.65])
    hock_R = np.array([1.75, 1.55, -1.65])
    fore_L = np.array([-0.95, 5.55, 2.25])
    fore_R = np.array([0.95, 5.55, 2.25])

    idx4 = int(t * 4) % 4
    idx8 = int(t * 8) % 8

    if kind == 'idle':
        rump_y += 0.08 * b
        chest_y += 0.14 * b
        hy += 0.16 * b
        yaw = 0.12 * b
        fore_L = np.array([-0.88, chest_y - 0.75, chest_z + 1.65])
        fore_R = np.array([0.88, chest_y - 0.75, chest_z + 1.65])

    elif kind == 'forage':
        # All-fours nose-down digging & patting a seed/nut cache!
        dig = math.sin(p * 2.0)
        rump_y, rump_z = 4.35 + 0.12 * abs(b), -2.55
        chest_y, chest_z = 3.25 + 0.15 * abs(dig), 1.65
        hy, hz = 2.75 + 0.25 * abs(b), 4.15
        pitch = 0.56
        yaw = 0.14 * b
        spine_arch = 0.75
        hock_L = np.array([-1.75, 2.15, -3.35])
        hock_R = np.array([1.75, 2.15, -3.35])
        hind_L = np.array([-1.60, 0.68, -0.95])
        hind_R = np.array([1.60, 0.68, -0.95])
        fore_L = np.array([-1.05, 0.72 + max(0.0, dig) * 0.95, 3.15 + dig * 0.55])
        fore_R = np.array([1.05, 0.72 + max(0.0, -dig) * 0.95, 3.15 - dig * 0.55])
        # Hazelnut / seed cache on the ground right between digging paws!
        m.ell((0.0, 0.88, 4.45), (0.86, 0.76, 0.96), CONE)

    elif kind == 'walk':
        # Bouncy arched-back ground hop-scamper (8 frames)
        rump_y = [3.6, 4.8, 5.6, 5.2, 4.2, 3.5, 3.4, 3.5][idx8]
        rump_z = [-2.4, -2.0, -2.2, -2.1, -1.6, -1.8, -2.2, -2.4][idx8]
        chest_y = [3.8, 5.4, 5.6, 4.4, 3.5, 3.6, 3.9, 3.8][idx8]
        chest_z = [1.6, 2.2, 2.5, 2.4, 1.9, 1.7, 1.6, 1.6][idx8]
        hy = chest_y + [2.3, 2.5, 2.3, 2.0, 2.1, 2.3, 2.4, 2.3][idx8]
        hz = chest_z + 2.25
        pitch = [0.12, -0.06, 0.04, 0.18, 0.14, 0.10, 0.08, 0.10][idx8]
        spine_arch = [0.65, 0.55, 0.75, 0.80, 0.70, 0.60, 0.60, 0.65][idx8]

        f_swing = [0.8, 2.2, 2.8, 2.2, 0.8, -0.6, -1.0, 0.0][idx8]
        f_lift = [0.0, 1.6, 2.0, 0.9, 0.0, 0.0, 0.3, 0.2][idx8]
        h_swing = [0.4, -2.2, -3.2, -1.2, 1.2, 1.4, 0.6, 0.4][idx8]
        h_lift = [0.0, 0.8, 1.9, 1.5, 0.4, 0.0, 0.0, 0.0][idx8]

        fore_L = np.array([-1.15, 0.68 + f_lift, chest_z + 0.8 + f_swing])
        fore_R = np.array([1.15, 0.68 + f_lift, chest_z + 0.8 + f_swing * 0.88])
        hind_L = np.array([-1.65, 0.68 + h_lift, rump_z + 1.2 + h_swing])
        hind_R = np.array([1.65, 0.68 + h_lift, rump_z + 1.2 + h_swing * 0.92])
        hock_L = np.array([-1.75, rump_y - 1.35, rump_z - 0.85 + h_swing * 0.45])
        hock_R = np.array([1.75, rump_y - 1.35, rump_z - 0.85 + h_swing * 0.45])

    elif kind == 'alert':
        # Tall upright sentinel posture (~15-16px tall) with rapid expressive S-tail scolding whip!
        rump_y, rump_z = 3.45, -1.05
        chest_y, chest_z = 7.55 + 0.15 * abs(b), 0.35
        hy, hz = 10.85 + 0.15 * abs(b), 0.85
        pitch = -0.04
        yaw = [0.0, 0.16, -0.14, 0.06][idx4]
        roll = [0.0, 0.10, -0.08, 0.02][idx4]
        spine_arch = 0.25
        fore_L = np.array([-0.92, chest_y - 0.65, chest_z + 1.65])
        fore_R = np.array([0.92, chest_y - 0.65, chest_z + 1.65])
        hind_L = np.array([-1.50, 0.68, 0.65])
        hind_R = np.array([1.50, 0.68, 0.65])
        hock_L = np.array([-1.65, 1.75, -1.35])
        hock_R = np.array([1.65, 1.75, -1.35])

    elif kind == 'run':
        # Fast stretched-out darting bound, fluffy tail streaming horizontally behind!
        rump_y = [4.0, 5.2, 5.8, 5.2, 4.2, 3.8, 3.8, 4.0][idx8]
        rump_z = [-2.5, -2.4, -2.6, -2.4, -1.8, -1.9, -2.2, -2.4][idx8]
        chest_y = [4.4, 5.8, 5.9, 4.8, 3.8, 3.7, 4.0, 4.2][idx8]
        chest_z = [2.0, 2.8, 3.1, 2.8, 2.2, 1.9, 1.9, 2.0][idx8]
        hy = chest_y + [1.8, 1.9, 1.7, 1.6, 1.7, 1.9, 2.0, 1.9][idx8]
        hz = chest_z + 2.45
        pitch = 0.05
        spine_arch = [0.35, 0.15, 0.10, 0.25, 0.65, 0.75, 0.55, 0.40][idx8]

        f_swing = [1.4, 3.2, 3.8, 2.8, 0.8, -1.2, -1.6, 0.2][idx8]
        f_lift = [0.5, 2.2, 2.6, 1.2, 0.0, 0.0, 0.4, 0.6][idx8]
        h_swing = [-1.8, -3.8, -4.4, -2.4, 1.0, 2.0, 1.4, -0.4][idx8]
        h_lift = [0.3, 1.8, 2.5, 1.8, 0.5, 0.0, 0.0, 0.0][idx8]

        fore_L = np.array([-1.15, 0.68 + f_lift, chest_z + 0.8 + f_swing])
        fore_R = np.array([1.15, 0.68 + f_lift, chest_z + 0.8 + f_swing - 0.35])
        hind_L = np.array([-1.60, 0.68 + h_lift, rump_z + 0.8 + h_swing])
        hind_R = np.array([1.60, 0.68 + h_lift, rump_z + 0.8 + h_swing + 0.35])
        hock_L = np.array([-1.70, rump_y - 1.15, rump_z - 1.05 + h_swing * 0.50])
        hock_R = np.array([1.70, rump_y - 1.15, rump_z - 1.05 + h_swing * 0.50])

    elif kind == 'groom':
        # Seated washing muzzle & ears with BOTH forepaws!
        scrub = math.sin(p * 2.0)
        rump_y, rump_z = 2.95, -1.25
        chest_y, chest_z = 6.15, 0.55
        hy, hz = 8.75 - 0.25 * abs(b), 1.55
        pitch = 0.28
        roll = 0.14 * b
        fore_L = np.array([-1.05, hy - 0.45 + 0.45 * scrub, hz + 1.85])
        fore_R = np.array([1.05, hy - 0.45 - 0.45 * scrub, hz + 1.85])

    elif kind == 'special':
        # Seated upright holding a distinct elongated BROWN SPRUCE CONE (Tannenzapfen) in both paws, rotating & gnawing!
        gnaw = math.sin(p * 3.0)
        cone_bob = 0.32 * math.sin(p * 2.0)
        cone_tilt = 0.48 * math.sin(p)
        rump_y, rump_z = 3.00, -1.35
        chest_y, chest_z = 6.45, 0.45
        hy, hz = 9.45 + 0.16 * gnaw, 1.45
        pitch = 0.34 - 0.08 * gnaw
        yaw = 0.08 * math.cos(p)

        # Unmistakable elongated spruce cone held well forward of the white chest (triggers crisp outline separation!)
        cone_c = np.array([0.0, 7.15 + cone_bob, 4.35])
        R_cone = rot_z(0.58 + cone_tilt) @ art.rot_x(0.28)
        for u_c, r_c in ((-1.55, 0.92), (-0.52, 1.25), (0.52, 1.28), (1.55, 0.96)):
            pt_c = cone_c + R_cone @ np.array([0.0, u_c, 0.0])
            m.ell(pt_c, (r_c, 0.98, r_c), CONE, R=R_cone)

        # Both dainty forepaws gripping & rotating the spruce cone from the sides!
        fore_L = cone_c + np.array([-1.35, 0.22 * math.sin(p * 2.0), -0.45])
        fore_R = cone_c + np.array([1.35, -0.22 * math.sin(p * 2.0), -0.45])

    elif kind == 'climb':
        # VERTICAL TREE-TRUNK CLIMBING CYCLE (~72 deg nose-up)!
        # Body elevated cleanly so the voluminous tail hangs straight down vertically along the trunk!
        bob_c = 0.30 * math.sin(p * 2.0)
        rump_y, rump_z = 8.15 + bob_c, -0.55
        chest_y, chest_z = 12.85 + bob_c, 0.98     # ~72 deg pitch upward: atan2(4.7, 1.53) = 72.0 deg!
        hy, hz = 15.65 + bob_c, 1.75
        pitch = -0.92                              # Nose pointed steeply up the tree trunk!
        yaw = 0.08 * b
        spine_arch = -0.22

        stroke_a = math.sin(p)
        stroke_b = -stroke_a
        # Wide splayed fore & hind limbs hugging the vertical trunk and pulling upward in alternating strokes!
        fore_L = np.array([-2.95, chest_y + 1.35 + 2.05 * stroke_a, chest_z + 1.95])
        fore_R = np.array([2.95, chest_y + 1.35 + 2.05 * stroke_b, chest_z + 1.95])
        hind_L = np.array([-3.05, rump_y - 1.15 + 2.05 * stroke_b, rump_z + 2.05])
        hind_R = np.array([3.05, rump_y - 1.15 + 2.05 * stroke_a, rump_z + 2.05])
        hock_L = np.array([-3.25, rump_y - 0.35 + 1.05 * stroke_b, rump_z + 0.45])
        hock_R = np.array([3.25, rump_y - 0.35 + 1.05 * stroke_a, rump_z + 0.45])

    # ---- Nimble Compact Squirrel Torso + Crisp Cream-White Chest & Belly ----
    dz = chest_z - rump_z
    dy = chest_y - rump_y
    spine_slope = math.atan2(dy, max(abs(dz), 0.8))
    R_spine = art.rot_x(-spine_slope * 0.65)

    for i in range(7):
        u = i / 6.0
        arch = math.sin(u * math.pi) * spine_arch
        sy = rump_y + dy * u + arch
        sz = rump_z + dz * u - (0.35 * math.sin(u * math.pi) if kind in ('idle', 'alert', 'groom', 'special') else 0.0)
        rx = 2.20 - 0.30 * u
        ry = 2.25 - 0.25 * u
        rz = 2.25 - 0.20 * u
        m.ell((0.0, sy, sz), (rx, ry, rz), COAT, R=R_spine)

    # Crisp snowy/cream-white chest bib & belly
    for u_b in (0.28, 0.60, 0.90):
        by_b = rump_y + dy * u_b - (0.95 if kind in ('forage', 'walk', 'run') else 0.15)
        bz_b = rump_z + dz * u_b + (0.35 if kind in ('forage', 'walk', 'run') else 1.05)
        m.ell((0.0, by_b, bz_b), (1.62, 1.55, 1.45), BELLY, R=R_spine)

    # ---- Articulated Squirrel Limbs (muscular hind haunches + nimble forelimbs) ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        hf = hind_L if s_idx == 0 else hind_R
        hk = hock_L if s_idx == 0 else hock_R
        ff = fore_L if s_idx == 0 else fore_R

        hip = np.array([side * 1.45, rump_y + 0.10, rump_z + 0.15])
        m.ell(hip, (1.35, 1.55, 1.65), COAT)
        m.limb(hip, hk, 1.08, 0.80, COAT, step=0.35)
        m.limb(hk, hf, 0.78, 0.62, COAT, step=0.32)
        if kind == 'climb':
            m.ell(hf, (0.76, 1.05, 0.72), NOSE_PAW)
        else:
            m.ell(hf + np.array([0.0, 0.0, 0.35]), (0.72, 0.55, 1.15), COAT)
            m.ell(hf + np.array([0.0, -0.05, 0.85]), (0.58, 0.45, 0.58), NOSE_PAW)

        sh = np.array([side * 1.25, chest_y - 0.15, chest_z + 0.35])
        elbow = 0.50 * sh + 0.50 * ff + np.array([side * (0.95 if kind == 'climb' else 0.20), -0.25, -0.25])
        m.limb(sh, elbow, 0.90, 0.72, COAT, step=0.32)
        m.limb(elbow, ff, 0.70, 0.58, COAT, step=0.30)
        m.ell(ff, (0.72 if kind == 'climb' else 0.62, 0.92 if kind == 'climb' else 0.55, 0.72), NOSE_PAW)

    # ---- MAGNIFICENT VOLUMINOUS S-CURVED PLUMED TAIL (Buschiger Eichhörnchenschwanz)! ----
    if kind == 'climb':
        # Trailing straight downward vertically below rump with a gentle bushy plume wave!
        sway_c = 0.95 * b
        p0 = np.array([0.0, rump_y - 0.55, rump_z - 0.65])
        p1 = np.array([sway_c * 0.35, rump_y - 2.65, rump_z - 1.45])
        p2 = np.array([sway_c * 0.75, rump_y - 5.15, rump_z - 1.15])
        p3 = np.array([sway_c, rump_y - 7.15, rump_z - 1.95])
    elif kind == 'run':
        # Fast horizontal streaming bushy rudder!
        wave_r = 0.65 * b
        p0 = np.array([0.0, rump_y + 0.25, rump_z - 1.15])
        p1 = np.array([wave_r * 0.3, rump_y + 0.95, rump_z - 4.25])
        p2 = np.array([wave_r * 0.7, rump_y + 0.85, rump_z - 7.85])
        p3 = np.array([wave_r, rump_y + 1.35, rump_z - 11.25])
    elif kind in ('forage', 'walk'):
        sway_w = 0.95 * b
        lift_w = 0.65 * math.cos(p)
        p0 = np.array([0.0, rump_y + 0.15, rump_z - 1.15])
        p1 = np.array([sway_w * 0.3, rump_y + 2.65 + lift_w, rump_z - 4.45])
        p2 = np.array([sway_w * 0.7, rump_y + 4.85 + lift_w, rump_z - 3.25])
        p3 = np.array([sway_w, rump_y + 5.65 + lift_w, rump_z - 5.85])
    elif kind == 'alert':
        # Rapid expressive S-tail whip over head/back (scolding alarm)!
        whip_z = [0.0, 1.85, -1.15, 0.85][idx4]
        whip_x = [0.0, 0.85, -0.85, 0.35][idx4]
        p0 = np.array([0.0, rump_y + 0.15, rump_z - 1.25])
        p1 = np.array([whip_x * 0.3, rump_y + 2.85, rump_z - 5.25])
        p2 = np.array([whip_x * 0.7, chest_y + 2.85, rump_z - 1.45 + whip_z * 0.6])
        p3 = np.array([whip_x, hy + 3.65, rump_z - 2.85 + whip_z])
    else:
        # Classic iconic upright S-curved squirrel plume arched high behind & over the back!
        sway_i = 0.75 * b
        wave_z = 0.55 * math.cos(p)
        p0 = np.array([0.0, rump_y + 0.10, rump_z - 1.25])
        p1 = np.array([sway_i * 0.25, rump_y + 2.45, rump_z - 5.35])
        p2 = np.array([sway_i * 0.65, chest_y + 2.45, rump_z - 1.65 + wave_z * 0.5])
        p3 = np.array([sway_i, hy + 2.55, rump_z - 3.85 + wave_z])

    tail_radii = [1.35, 1.85, 2.35, 2.68, 2.72, 2.52, 2.18, 1.72, 1.22]
    for ti, r_t in enumerate(tail_radii):
        u_t = ti / (len(tail_radii) - 1)
        pt = bezier3(p0, p1, p2, p3, u_t)
        m.ell(pt, (r_t * 0.96, r_t * 1.04, r_t * 1.08), TAIL)

    # ---- Expressive Squirrel Head, Glossy Dark Eyes w/ Glint & Fluffy Ear-Tufts (Pinselöhrchen)! ----
    head = np.array([math.sin(yaw) * 0.55, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ np.array([x, y, z])

    def head_ell(
        pos: tuple[float, float, float],
        r: tuple[float, float, float],
        mat: int,
        R_extra: np.ndarray | None = None,
    ) -> None:
        m.ell(hp(*pos), r, mat, R=rot if R_extra is None else rot @ R_extra)

    m.limb((0.0, chest_y + 0.35, chest_z + 0.15), hp(0.0, -0.65, -0.55), 1.65, 1.45, COAT, step=0.35)
    m.ell(hp(0.0, -1.05, 0.75), (1.22, 0.95, 1.15), BELLY)

    head_ell((0.0, 0.05, 0.0), (1.85, 1.78, 2.02), COAT)
    for side in (-1.0, 1.0):
        head_ell((side * 1.05, -0.38, 0.75), (0.98, 0.92, 1.18), COAT)
    head_ell((0.0, -0.28, 1.58), (1.08, 0.92, 1.25), COAT)
    head_ell((0.0, -0.68, 1.65), (0.88, 0.55, 1.02), BELLY)
    head_ell((0.0, -0.22, 2.58), (0.45, 0.38, 0.44), NOSE_PAW)

    blink = (kind == 'groom' and idx4 in (1, 2)) or (kind == 'idle' and t >= 0.75)

    for side in (-1.0, 1.0):
        head_ell((side * 1.32, 0.25, 0.78), (0.48, 0.65, 0.68), BELLY)
        if blink:
            head_ell((side * 1.45, 0.25, 0.88), (0.42, 0.16, 0.48), EYE)
        else:
            head_ell((side * 1.44, 0.26, 0.88), (0.45, 0.58, 0.56), EYE)
            head_ell((side * 1.54, 0.44, 1.08), (0.22, 0.22, 0.20), GLINT)

        ear_splay = 0.14 if kind == 'alert' else (0.32 if kind == 'run' else 0.20)
        ear_fwd = 0.08 if kind == 'alert' else (-0.32 if kind == 'run' else 0.02 + 0.05 * math.sin(p + side))
        R_ear = rot @ rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        ebase = hp(side * 1.15, 1.38, -0.45)

        def ep(ex: float, ey: float, ez: float) -> np.ndarray:
            return ebase + R_ear @ np.array([ex, ey, ez])

        m.ell(ep(0.0, 0.55, 0.0), (0.68, 1.02, 0.48), COAT, R=R_ear)
        m.ell(ep(-side * 0.04, 0.52, 0.24), (0.38, 0.68, 0.20), NOSE_PAW, R=R_ear)

        t0 = ep(0.0, 1.25, -0.05)
        t1 = ep(side * 0.16, 2.25, -0.18)
        t2 = ep(side * 0.34, 3.15, -0.32)
        m.limb(t0, t1, 0.54, 0.46, TUFT, step=0.26)
        m.limb(t1, t2, 0.44, 0.28, TUFT, step=0.24)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_squirrel(v, kind, (col - start) / n)
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
        (0, 0),   # E idle (upright perch, white chest, S-curved plume, Pinselöhrchen)
        (1, 0),   # SE idle
        (2, 0),   # S idle (white chest/belly + ear tufts + S-tail crown)
        (4, 0),   # W idle
        (6, 0),   # N idle (voluminous S-plume from rear)
        (0, 6),   # E forage (nose-down digging & patting nut cache)
        (0, 12),  # E walk (bouncy arched-back hop-scamper)
        (1, 19),  # SE alert (tall upright sentinel + S-tail scolding whip)
        (0, 24),  # E run (stretched darting bound, horizontal streaming tail)
        (1, 31),  # SE groom (washing muzzle/ears with both forepaws)
        (1, 35),  # SE sleep (curled ball with fluffy tail wrapped over back/head)
        (0, 40),  # E special (upright holding & gnawing brown spruce cone / Tannenzapfen!)
        (1, 41),  # SE special (rotating spruce cone in front of white chest!)
        (0, 47),  # E climb (vertical ~72 deg nose-up tree climb, splayed limbs, trailing tail)
        (6, 47),  # N climb (classic rear view climbing up trunk w/ splayed limbs & hanging tail!)
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([44, 52, 48, 255], np.uint8)
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
                print(f'squirrel build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/squirrel.png', sheet)
    print('Saved assets/wildlife/squirrel.png', sheet.shape)


if __name__ == '__main__':
    main()
