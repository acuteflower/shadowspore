#!/usr/bin/env python3
"""Eurasian Lynx (Eurasischer Luchs - Lynx lynx) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 3 builds x 8 true facings = 24 rows (3328x1536). No emissive parts.
Builds:
  0: Karpaten-Rotluchs (warm rufous-tawny coat with dark spots, cream belly & ruffs, black ear-tufts & bobtail tip)
  1: Nordischer Silberluchs (frosty pale silver-ash coat with crisp charcoal spots & white ruffs)
  2: Dämmer-/Schattenluchs (smoky slate-taupe deep-forest coat with dark charcoal markings)
Columns (52):
  idle 0:4 (regal standing poise, subtle ear-tuft & bobtail twitch),
  forage 4:10 (low-head scent-prowl sniffing ground),
  walk 10:18 (long-legged supple feline stride with prominent shoulder blade motion),
  alert 18:22 (seated/poised intense gaze, tufted ears locked forward),
  run 22:30 (extended silent feline bounding leap),
  groom 30:34 (seated royal forepaw-licking & cheek-ruff wash),
  sleep 34:38 (tucked feline loaf rest, paws folded under chest, head resting peacefully),
  special 38:46 (coiled feline crouch -> explosive horizontal pounce -> landing),
  stalk 46:52 (ultra-low slinking belly-creep with high shoulder blades).
Usage: py -3 tools/art_lynx.py [--preview-only] [--qa=path.png]
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
COLS = 52

COAT, CREAM, SPOT, DARK, AMBER_EYE, NOSE, INNER_EAR = range(7)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 6),
    ('walk', 10, 8),
    ('alert', 18, 4),
    ('run', 22, 8),
    ('groom', 30, 4),
    ('sleep', 34, 4),
    ('special', 38, 8),
    ('stalk', 46, 6),
]

BUILDS = [
    # 0 Karpaten-Rotluchs: warm rufous-tawny coat, warm cream belly/ruffs, dark espresso-umber spots
    (
        ['553028', '8b523b', 'be7d56', 'e4ad7e'],
        ['8c7e7c', 'bcb0aa', 'e6dcd2', 'fcf6ec'],
        ['24151a', '3f2427', '5e3937', '80524a'],
    ),
    # 1 Nordischer Silberluchs: frosty pale silver-ash coat, crisp white ruffs, charcoal spots
    (
        ['464958', '757b8d', 'abb2c3', 'dde3ee'],
        ['868c9a', 'b6bdc9', 'e3e8f1', 'fafcff'],
        ['191c28', '2d3244', '484f64', '687086'],
    ),
    # 2 Dämmer-/Schattenluchs: smoky slate-taupe deep-forest coat, misty cream ruffs, dark charcoal markings
    (
        ['2e2b38', '544e61', '7e768a', 'aca3b6'],
        ['74707e', 'a29da8', 'cfc9d3', 'eee9f0'],
        ['110f1a', '1f1c2b', '342f42', '4e485e'],
    ),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        AMBER_EYE: 4.5,
        DARK: 2.55,
        SPOT: 2.35,
        NOSE: 2.8,
        INNER_EAR: 1.75,
        CREAM: 1.25,
    }
    art.ink_color = lambda mat: hexc('13101c' if mat in (DARK, SPOT, NOSE) else '251c28')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def materials(v: int) -> None:
    setup_art()
    coat, cream, spot = BUILDS[v % BUILDS_N]
    ramps = [
        coat,                                               # 0 COAT
        cream,                                              # 1 CREAM (ruffs, belly, inner legs, ear ocelli)
        spot,                                               # 2 SPOT (flank/limb rosettes & ruff stripes)
        ['0a0912', '161422', '282538', '3f3a52'],           # 3 DARK (black ear-tufts, bobtail tip, eye liner)
        ['785016', 'b47e22', 'e6b43f', 'ffe27a'],           # 4 AMBER_EYE (piercing amber-gold feline iris)
        ['2c1b24', '4e303b', '764a55', '9d6973'],           # 5 NOSE
        ['624d52', '917476', 'bfa09e', 'e3c7c2'],           # 6 INNER_EAR
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_lynx_legs(
    m: art.Model,
    t: float,
    rear_y: float,
    front_y: float,
    kind: str,
    idx8: int,
) -> tuple[float, float]:
    """Long muscular wildcat limbs with cream inner fur, spotted thighs, and broad snowshoe paws.
    Returns (scapula_L, scapula_R) vertical lift for prominent feline shoulder-blade motion."""
    scap_l = 0.0
    scap_r = 0.0

    if kind == 'sleep':
        # Tucked feline loaf: forepaws folded neatly beneath cream chest, hind haunches tucked smooth
        for side in (-1.0, 1.0):
            m.ell((side * 2.55, 2.55, -2.4), (1.75, 1.85, 2.65), COAT)
            m.ell((side * 3.95, 2.75, -2.2), (0.58, 0.72, 0.80), SPOT)
            m.ell((side * 1.65, 1.45, 4.15), (1.35, 1.05, 1.65), COAT)
            m.ell((side * 1.15, 1.25, 4.85), (1.15, 0.85, 1.25), CREAM)
        return scap_l, scap_r

    seated = kind in ('alert', 'groom')
    groom_idx = int(t * 4) % 4

    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (2.05 if front else 2.25)
            hip_z = 4.2 if front else -4.6
            hip_y = (front_y if front else rear_y) - 0.35

            if seated and not front:
                thigh = np.array([side * 2.55, rear_y - 0.5, hip_z + 0.8])
                hock = np.array([side * 2.45, 1.65, hip_z - 0.5])
                paw = np.array([side * 2.20, 1.05, hip_z + 3.4])
                m.limb((hip_x, hip_y, hip_z), thigh, 1.95, 1.55, COAT, step=0.42)
                m.ell((side * 3.95, rear_y - 0.2, hip_z + 0.6), (0.58, 0.76, 0.82), SPOT)
                m.limb(thigh, hock, 1.50, 1.08, COAT, step=0.40)
                m.limb(hock, paw, 1.05, 1.02, COAT, step=0.38)
                m.limb((side * 1.65, rear_y - 0.8, hip_z + 1.0), (side * 1.75, 1.35, hip_z + 2.4), 0.85, 0.72, CREAM, step=0.45)
                m.ell(paw + np.array([0.0, 0.0, 0.35]), (1.26, 0.86, 1.52), COAT)
                m.ell(paw + np.array([-side * 0.22, -0.05, 0.65]), (0.95, 0.68, 1.10), CREAM)
                continue

            if kind == 'groom' and front and side > 0:
                # Right broad furry forepaw raised royally to wash cheek ruff (Backenbart)!
                lift_k = [0.45, 0.95, 1.0, 0.55][groom_idx]
                sh = np.array([hip_x, hip_y, hip_z])
                elbow = np.array([2.55, front_y - 2.2 + 0.8 * lift_k, hip_z + 1.5])
                paw = np.array([1.85, front_y + 0.6 + 2.6 * lift_k, hip_z + 3.2 - 0.3 * groom_idx])
                m.limb(sh, elbow, 1.52, 1.18, COAT, step=0.38)
                m.limb(elbow, paw, 1.15, 1.08, COAT, step=0.36)
                m.ell(paw, (1.28, 0.96, 1.42), COAT)
                m.ell(paw + np.array([-0.35, 0.05, 0.25]), (0.92, 0.78, 1.05), CREAM)
                continue

            swing = 0.0
            lift = 0.0
            knee_flex = 0.0
            stance_push = 0.0

            if kind == 'walk':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.58
                if cyc < stance:
                    c = cyc / stance
                    swing = 3.2 * (1.0 - 2.0 * c)
                    stance_push = math.sin(c * math.pi)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -3.2 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 2.35
                    knee_flex = math.sin(c * math.pi) * 1.15
            elif kind == 'forage':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.66
                if cyc < stance:
                    c = cyc / stance
                    swing = 2.1 * (1.0 - 2.0 * c)
                    stance_push = 0.6 * math.sin(c * math.pi)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -2.1 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.45
                    knee_flex = 0.65
            elif kind == 'stalk':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.66
                if cyc < stance:
                    c = cyc / stance
                    swing = 2.6 * (1.0 - 2.0 * c)
                    stance_push = 1.0 + 0.45 * math.sin(c * math.pi)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -2.6 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.65
                    knee_flex = 1.35
                    stance_push = 0.55
            elif kind == 'run':
                # 8-frame extended silent feline bounding leap (with natural left/right lead asymmetry)
                lead = 0.55 if side > 0 else -0.55
                if front:
                    swing = [1.4, 4.2, 5.4, 4.4, 1.2, -2.4, -3.8, -1.6][idx8] + lead * 0.45
                    lift = [0.6, 2.8, 3.8, 2.2, 0.0, 0.0, 0.8, 1.4][idx8]
                    knee_flex = [0.8, 0.3, 0.2, 0.3, 0.6, 0.5, 1.1, 1.2][idx8]
                    stance_push = [0.0, 0.0, 0.0, 0.0, 0.8, 0.9, 0.2, 0.0][idx8]
                else:
                    swing = [-2.6, -5.0, -5.6, -3.4, 0.8, 3.2, 3.6, 0.4][idx8] - lead * 0.45
                    lift = [0.2, 2.2, 3.4, 2.8, 1.2, 0.0, 0.0, 0.0][idx8]
                    knee_flex = [0.4, 0.2, 0.2, 0.6, 1.1, 0.8, 0.6, 0.5][idx8]
            elif kind == 'special':
                # 8-frame feline horizontal pounce:
                # 0..1 deep coiled crouch, 2..3 explosive hind launch, 4..5 stretched horizontal flight, 6..7 forepaw strike & settle
                if front:
                    swing = [-0.8, -1.2, 3.8, 5.4, 5.6, 4.4, 2.4, 0.8][idx8]
                    lift = [0.0, 0.0, 2.4, 3.8, 3.2, 1.4, 0.0, 0.0][idx8]
                    knee_flex = [1.2, 1.5, 0.4, 0.2, 0.3, 0.5, 0.8, 0.4][idx8]
                    stance_push = [0.9, 1.2, 0.0, 0.0, 0.0, 0.0, 0.7, 0.3][idx8]
                else:
                    swing = [1.4, 2.0, -4.4, -5.8, -5.2, -3.2, -1.0, -0.2][idx8]
                    lift = [0.0, 0.0, 0.5, 2.6, 3.6, 2.4, 0.4, 0.0][idx8]
                    knee_flex = [1.2, 1.5, 0.2, 0.2, 0.4, 0.8, 0.9, 0.3][idx8]

            if front:
                if side < 0:
                    scap_l = stance_push
                else:
                    scap_r = stance_push

            paw_x = hip_x * (0.78 if kind in ('walk', 'stalk') else 0.88)
            foot_y = max(0.95, 0.95 + lift)
            root = np.array([hip_x, hip_y, hip_z])
            foot = np.array([paw_x, foot_y, hip_z + swing])

            if front:
                elbow_out = 0.45 * knee_flex * side
                carpus = np.array([
                    0.5 * (hip_x + paw_x) + elbow_out * 0.4,
                    foot_y + (hip_y - foot_y) * 0.47 + knee_flex * 0.25,
                    hip_z + swing * 0.52 + 0.35 + knee_flex * 0.45,
                ])
                m.limb(root, carpus, 1.55, 1.15, COAT, step=0.40)
                m.limb(carpus, foot, 1.12, 1.05, COAT, step=0.38)
                m.limb(root + np.array([-side * 0.48, -0.3, 0.1]), carpus + np.array([-side * 0.38, 0.0, 0.1]), 0.92, 0.75, CREAM, step=0.48)
                m.ell(0.55 * root + 0.45 * carpus + np.array([side * 1.12, 0.25, 0.05]), (0.52, 0.68, 0.72), SPOT)
            else:
                hock = np.array([
                    0.5 * (hip_x + paw_x),
                    foot_y + (hip_y - foot_y) * 0.46 + knee_flex * 0.30,
                    hip_z + swing * 0.42 - 1.65 - knee_flex * 0.35,
                ])
                m.limb(root, hock, 1.88, 1.18, COAT, step=0.40)
                m.limb(hock, foot, 1.12, 1.04, COAT, step=0.38)
                m.limb(root + np.array([-side * 0.55, -0.4, 0.2]), hock + np.array([-side * 0.42, 0.0, 0.2]), 1.02, 0.76, CREAM, step=0.48)
                m.ell(0.65 * root + 0.35 * hock + np.array([side * 1.35, 0.35, 0.2]), (0.56, 0.74, 0.78), SPOT)
                m.ell(0.32 * root + 0.68 * hock + np.array([side * 1.05, 0.1, -0.1]), (0.48, 0.62, 0.66), SPOT)

            # Broad oversized furry lynx snowshoe paw!
            m.ell(foot + np.array([0.0, 0.0, 0.35]), (1.25, 0.86, 1.52), COAT)
            m.ell(foot + np.array([-side * 0.18, -0.04, 0.68]), (0.96, 0.68, 1.12), CREAM)

    return scap_l, scap_r


def build_lynx(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    idx8 = int(t * 8) % 8

    # Tall long-legged wildcat: hindquarters noticeably higher than shoulders!
    rear_y = 12.6
    front_y = 11.4

    if kind == 'idle':
        rear_y += 0.14 * b
        front_y += 0.18 * b
    elif kind == 'forage':
        rear_y = 12.2 + 0.12 * math.cos(p * 2.0)
        front_y = 9.8 + 0.12 * math.cos(p * 2.0)
    elif kind == 'walk':
        bob = 0.24 * math.cos(p * 2.0)
        rear_y = 12.5 + bob
        front_y = 11.3 + bob
    elif kind == 'alert':
        rear_y = 6.6
        front_y = 12.4 + 0.10 * b
    elif kind == 'groom':
        rear_y = 6.6
        front_y = 11.6
    elif kind == 'sleep':
        rear_y = 5.0 + 0.14 * b
        front_y = 5.2 + 0.16 * b
    elif kind == 'run':
        rear_y = [11.6, 13.4, 14.2, 13.4, 11.8, 11.0, 11.4, 11.8][idx8]
        front_y = [12.4, 14.0, 13.8, 12.2, 10.6, 10.4, 11.2, 11.8][idx8]
    elif kind == 'stalk':
        rear_y = 8.1 + 0.10 * math.cos(p * 2.0)
        front_y = 6.9 + 0.10 * math.cos(p * 2.0)
    elif kind == 'special':
        rear_y = [7.6, 7.0, 11.4, 13.8, 13.6, 12.2, 9.6, 11.8][idx8]
        front_y = [7.2, 6.6, 13.2, 14.4, 13.2, 10.2, 8.2, 10.8][idx8]

    scap_l, scap_r = draw_lynx_legs(m, t, rear_y, front_y, kind, idx8)

    # Compact muscular feline spine chain
    z_back = -4.8 if kind == 'sleep' else -5.2
    z_front = 4.2 if kind == 'sleep' else 4.6
    spine_len = z_front - z_back
    spine_slope = math.atan2(front_y - rear_y, spine_len)
    R_spine = art.rot_x(-spine_slope)

    for i in range(9):
        u = i / 8.0
        sz = z_back + spine_len * u
        arch = math.sin(u * math.pi)
        flex = 0.0
        if kind == 'run':
            flex = [0.2, 0.45, 0.50, 0.25, -0.15, -0.35, -0.20, 0.0][idx8] * arch
        elif kind == 'special' and idx8 in (0, 1):
            flex = 0.55 * arch
        elif kind == 'special' and idx8 in (3, 4):
            flex = 0.40 * arch
        sy = rear_y * (1.0 - u) + front_y * u + flex
        rx_r = (3.45 if kind == 'sleep' else 3.05) + 0.42 * arch - 0.12 * u
        ry_r = (3.15 if kind == 'sleep' else 3.35) + 0.48 * arch - 0.10 * u
        rz_r = 2.65 + 0.55 * arch
        m.ell((0.0, sy, sz), (rx_r, ry_r, rz_r), COAT, R=R_spine)

    # Prominent feline shoulder blades (Scapulae) — distinctly visible in walk & ultra-high in stalk!
    if kind != 'sleep':
        base_scap = 0.90 if kind == 'stalk' else (0.35 if kind in ('walk', 'forage', 'special') else 0.20)
        for side, sc in ((-1.0, scap_l), (1.0, scap_r)):
            sh_y = front_y + 1.85 + base_scap + 0.85 * sc
            m.ell((side * 1.45, sh_y, z_front - 0.85), (1.38, 1.65, 2.05), COAT, R=R_spine)

    # Cream belly & deep furry chest bib
    if kind != 'sleep':
        for u_b in (0.20, 0.48, 0.76):
            bz = z_back + spine_len * u_b
            by_b = rear_y * (1.0 - u_b) + front_y * u_b - 2.05
            m.ell((0.0, by_b, bz), (2.45, 1.65, 2.55), CREAM, R=R_spine)
    m.ell((0.0, front_y - (0.95 if kind == 'sleep' else 0.75), z_front + 0.85), (2.55, 2.45, 2.15), CREAM, R=R_spine)

    # Crisp dark spot rosettes sitting cleanly on the outer flank surface!
    flank_spots = [
        (0.20, 0.85),
        (0.34, -0.55),
        (0.48, 0.95),
        (0.60, -0.65),
        (0.74, 0.65),
        (0.84, -0.45),
    ]
    for side in (-1.0, 1.0):
        for u_s, dy_s in flank_spots:
            sz = z_back + spine_len * u_s
            arch = math.sin(u_s * math.pi)
            sy = rear_y * (1.0 - u_s) + front_y * u_s + dy_s
            rx_r = (3.45 if kind == 'sleep' else 3.05) + 0.42 * arch - 0.12 * u_s
            ry_r = (3.15 if kind == 'sleep' else 3.35) + 0.48 * arch - 0.10 * u_s
            x_surf = rx_r * math.sqrt(max(0.25, 1.0 - (dy_s / ry_r) ** 2))
            m.ell((side * (x_surf - 0.12), sy, sz), (0.50, 0.74, 0.82), SPOT, R=R_spine)

    # UNMISTAKABLE SHORT BOBTAIL (~4-5 px) WITH A JET-BLACK TIP! (Never a long tail!)
    if kind == 'sleep':
        p0 = np.array([0.8, rear_y + 0.1, z_back - 0.4])
        p1 = np.array([3.6, rear_y - 0.5, z_back - 2.2])
    else:
        twitch_x = 0.55 * math.sin(p * 2.0) if kind in ('idle', 'special') else (0.45 * math.sin(p) if kind == 'walk' else 0.0)
        twitch_y = 0.40 * math.cos(p * 2.0) if kind == 'idle' else (0.65 if kind in ('run', 'special') else 0.0)
        base_drop = -0.85 if kind in ('alert', 'groom') else (-1.05 + twitch_y)
        tail_len_z = -3.6 if kind in ('alert', 'groom') else -4.1
        p0 = np.array([0.0, rear_y + 0.35, z_back - 0.35])
        p1 = np.array([twitch_x, rear_y + base_drop, z_back + tail_len_z])

    bob_radii = [1.42, 1.38, 1.35, 1.32, 1.18]
    for ti, r_b in enumerate(bob_radii):
        u_t = ti / (len(bob_radii) - 1)
        pt = p0 * (1.0 - u_t) + p1 * u_t
        mat_b = DARK if ti >= 3 else COAT
        m.ell(pt, (r_b, r_b * 0.96, r_b * 1.12), mat_b)

    # Sculpted Feline Neck & Head with Flared Cheek Ruffs (Backenbart) + Tall Black Ear-Tufts (Pinselohren)
    hy = front_y + 5.8
    hz = 7.2
    pitch = 0.06
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        hy = front_y + 5.9 + 0.15 * b
        yaw = 0.10 * b
    elif kind == 'forage':
        hy = 5.2 + 0.25 * abs(b)
        hz = 9.8
        pitch = 0.48
        yaw = 0.24 * b
    elif kind == 'walk':
        hy = front_y + 4.9 + 0.15 * math.sin(p * 2.0)
        hz = 8.0
        pitch = 0.12
    elif kind == 'alert':
        idx_a = int(t * 4) % 4
        hy = front_y + 6.1
        hz = 6.2
        pitch = 0.04
        yaw = [0.0, 0.12, 0.14, 0.04][idx_a]
        roll = [0.0, 0.08, 0.10, 0.02][idx_a]
    elif kind == 'groom':
        g_idx = int(t * 4) % 4
        wash = [0.4, 0.95, 1.0, 0.5][g_idx]
        hy = front_y + 4.8 - 1.1 * wash
        hz = 6.3 + 0.5 * wash
        pitch = 0.38 * wash
        yaw = -0.32 * wash
        roll = 0.28 * wash
    elif kind == 'sleep':
        hy = front_y + 3.6 + 0.10 * b
        hz = 6.0
        pitch = 0.20
        yaw = -0.18
        roll = 0.06
    elif kind == 'run':
        hy = front_y + [4.6, 4.4, 4.0, 3.8, 4.0, 4.4, 4.8, 4.8][idx8]
        hz = [8.4, 9.2, 9.6, 9.4, 8.8, 8.4, 8.2, 8.4][idx8]
        pitch = [0.04, 0.02, 0.08, 0.14, 0.18, 0.14, 0.08, 0.06][idx8]
    elif kind == 'stalk':
        hy = front_y + 2.1
        hz = 9.4
        pitch = 0.04
    elif kind == 'special':
        hy = front_y + [2.6, 2.2, 4.4, 4.2, 3.6, 2.8, 2.6, 4.4][idx8]
        hz = [8.4, 8.2, 9.2, 9.8, 9.8, 9.4, 8.8, 8.0][idx8]
        pitch = [0.12, 0.16, -0.08, 0.04, 0.12, 0.24, 0.28, 0.12][idx8]

    head = np.array([math.sin(yaw) * 0.9, hy, hz])
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

    # Thick muscular coat-colored feline neck + front cream throat bib (keeps rear nape rich COAT from N!)
    neck_base = np.array([0.0, front_y + 0.85, z_front - 0.2])
    throat = hp(0.0, -0.95, -1.05)
    m.limb(neck_base, throat, 2.65, 2.15, COAT, step=0.42)
    m.limb(neck_base + np.array([0.0, -0.95, 1.15]), throat + rot @ np.array([0.0, -0.65, 1.15]), 1.75, 1.35, CREAM, step=0.45)

    # Rounded powerful feline cranium + forehead spot markings
    head_ell((0.0, 0.20, -0.10), (2.68, 2.52, 2.68), COAT)
    head_ell((0.0, 1.65, 0.35), (1.35, 0.95, 1.55), SPOT)

    # UNMISTAKABLE FLARED WHITE-AND-DARK CHEEK RUFFS (Backenbart)!
    for side in (-1.0, 1.0):
        R_ruff = rot_z(-side * 0.48) @ art.rot_y(-side * 0.16)
        # Coat backing behind ruff so N-facing skull stays clean coat-colored with flared dark-tipped side ruffs
        head_ell((side * 2.25, -0.55, -0.45), (1.35, 1.25, 1.15), COAT, R_ruff)
        # Lush cream-white flared front/side ruff sweeping wide & downward from cheeks
        head_ell((side * 2.38, -0.55, 0.38), (1.45, 1.38, 1.45), CREAM, R_ruff)
        head_ell((side * 3.05, -1.45, 0.15), (1.12, 1.22, 1.15), CREAM, R_ruff)
        # Signature dark ruff bar & pointed jet-black lower-outer ruff tips!
        head_ell((side * 2.85, -1.05, -0.25), (0.85, 0.95, 1.05), SPOT, R_ruff)
        head_ell((side * 3.38, -2.15, -0.05), (0.80, 0.95, 0.92), DARK, R_ruff)

    # Short, broad feline muzzle + full cream whisker pads + chin + feline nose pad
    head_ell((0.0, -0.32, 1.95), (1.65, 1.25, 1.65), COAT)
    for side in (-1.0, 1.0):
        head_ell((side * 0.95, -0.78, 2.25), (1.05, 0.88, 1.25), CREAM)
    head_ell((0.0, -1.25, 2.05), (1.05, 0.62, 1.20), CREAM)
    head_ell((0.0, -0.32, 3.25), (0.68, 0.52, 0.58), NOSE)

    blink = (kind == 'sleep') or (kind == 'groom' and int(t * 4) % 4 in (1, 2)) or (kind == 'idle' and t >= 0.75)

    for side in (-1.0, 1.0):
        # Triangular feline ears (warm coat base + black rim/back + pale ocellus) + TALL SHARP BLACK EAR-TUFTS!
        ear_splay = 0.18 if kind in ('alert', 'stalk', 'special') else (0.34 if kind in ('run', 'sleep') else 0.25)
        ear_fwd = 0.20 if kind in ('alert', 'stalk') else (-0.22 if kind == 'run' else 0.04 + 0.06 * math.sin(p + side))
        R_ear = rot @ rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        ebase = hp(side * 1.75, 1.85, -0.58)

        def ep(ex: float, ey: float, ez: float) -> np.ndarray:
            return ebase + R_ear @ np.array([ex, ey, ez])

        # Broad coat-colored feline ear base -> black upper triangle & back -> silver-white central ocellus -> pale inner pinna
        m.ell(ep(0.0, 0.45, 0.0), (1.05, 1.15, 0.62), COAT, R=R_ear)
        m.ell(ep(0.0, 1.15, -0.10), (0.88, 1.15, 0.48), DARK, R=R_ear)
        m.ell(ep(0.0, 0.95, -0.42), (0.45, 0.58, 0.22), CREAM, R=R_ear)
        m.ell(ep(-side * 0.05, 0.82, 0.30), (0.58, 1.05, 0.26), INNER_EAR, R=R_ear)

        # Tall vertical jet-black ear-tuft (Pinselohr) rising sharply from the ear apex and rotating with R_ear!
        tuft_sway = 0.12 * math.sin(p * 2.0 + side) if kind == 'idle' else 0.0
        t0 = ep(0.0, 1.95, -0.08)
        t1 = ep(side * (0.12 + tuft_sway * 0.5), 3.35, -0.10)
        t2 = ep(side * (0.26 + tuft_sway), 4.75, -0.14)
        m.limb(t0, t1, 0.52, 0.44, DARK, step=0.30)
        m.limb(t1, t2, 0.42, 0.30, DARK, step=0.28)

        # Pale feline eye-spectacle arc + dark liner + piercing amber-gold iris!
        head_ell((side * 1.48, 0.26, 1.38), (0.62, 0.72, 0.68), CREAM)
        if blink:
            head_ell((side * 1.58, 0.24, 1.56), (0.52, 0.20, 0.54), DARK)
        else:
            head_ell((side * 1.55, 0.26, 1.52), (0.54, 0.62, 0.58), DARK)
            head_ell((side * 1.64, 0.28, 1.66), (0.46, 0.52, 0.48), AMBER_EYE)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_lynx(v, kind, (col - start) / n)
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
        (0, 0),   # E idle (tall hindquarters, bobtail w/ black tip, ear tufts, cheek ruff, flank spots)
        (1, 0),   # SE idle
        (2, 0),   # S idle (flared Backenbart + tall Pinselohren + amber eyes)
        (4, 0),   # W idle
        (6, 0),   # N idle (coat skull, black ear backs w/ white ocelli, black ear tufts, stubby bobtail)
        (0, 6),   # E forage scent-prowl
        (0, 12),  # E walk (long-legged stride + scapula motion)
        (2, 19),  # S alert seated/poised
        (1, 19),  # SE alert seated/poised
        (0, 24),  # E run extended silent feline bounding leap
        (1, 32),  # SE groom royal forepaw & cheek-ruff wash
        (1, 35),  # SE sleep tucked feline loaf
        (0, 39),  # E special coiled crouch
        (0, 42),  # E special explosive horizontal pounce
        (0, 48),  # E stalk ultra-low belly creep w/ high shoulder blades
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
                print(f'lynx build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/lynx.png', sheet)
    print('Saved assets/wildlife/lynx.png', sheet.shape)


if __name__ == '__main__':
    main()
