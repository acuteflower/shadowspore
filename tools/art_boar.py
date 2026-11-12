#!/usr/bin/env python3
"""European Wild Boar (Sus scrofa / Wildschwein) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 4 builds x 8 true facings = 32 rows (3328x2048). No emissive parts.
Builds:
  0: Leitbache (rich dark umber-brown bristled sow, grizzled cheek whisker streak, modest canine tips)
  1: Kapitaler Keiler (1.07x bulkier shoulder shield, charcoal-black coat, tall crest, prominent ivory lower tusks)
  2: Frischling (0.64x juvenile anchored on GROUND_ROW=52.0, chestnut-russet with cream-gold longitudinal stripes)
  3: Moor-/Nebelschwein (cool mossy slate-charcoal coat with silvered shoulder frost)
Columns (52):
  idle 0:4, forage 4:12, walk 12:20, alert 20:24, run 24:32,
  groom 32:36, sleep 36:40, bark 40:46, special 46:52.
Usage: py -3 tools/art_boar.py [--preview-only] [--qa=path.png]
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

COAT, BRISTLE, MARKING, FROST, DARK, SNOUT_DISC, NOSE_EYE, TUSK, INNER_EAR, GLINT = range(10)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 8),
    ('walk', 12, 8),
    ('alert', 20, 4),
    ('run', 24, 8),
    ('groom', 32, 4),
    ('sleep', 36, 4),
    ('bark', 40, 6),
    ('special', 46, 6),
]

COATS = [
    # 0 Leitbache: rich dark umber-brown bristled woodland sow
    ['2b1b19', '50342b', '7b523f', 'a77458'],
    # 1 Kapitaler Keiler: deep charcoal-black coarse bristled tusker
    ['15151d', '272632', '403e4d', '605d6e'],
    # 2 Frischling: warm chestnut-russet juvenile piglet
    ['45221b', '783e2b', 'ab5e3d', 'd68457'],
    # 3 Moor-/Nebelschwein: cool mossy slate-charcoal coat
    ['1d2325', '333d3f', '505f60', '748584'],
]

BRISTLES = [
    # 0 Dark espresso-umber dorsal crest & lower guard hairs
    ['181013', '2c1e20', '463131', '634844'],
    # 1 Jet-slate tall keiler Borstenkamm
    ['0c0c13', '171621', '292736', '3f3c4e'],
    # 2 Warm dark russet-brown juvenile dorsal stripe
    ['2c1513', '4f261e', '743a2b', '98523b'],
    # 3 Deep peat-moss slate crest
    ['111618', '20292b', '354244', '4e5f60'],
]

MARKINGS = [
    # 0 Grizzled warm buff-ash cheek whisker streak (Backenbart)
    ['6e6058', '99887d', 'c4b3a4', 'e8dad0'],
    # 1 Silver-grizzled jowl whisker streak on old Keiler
    ['585864', '828290', 'aeadba', 'd8d8e2'],
    # 2 Bright cream-gold longitudinal Frischling stripes!
    ['946e3e', 'c79b58', 'f0ca80', 'fff2b8'],
    # 3 Cool silver-mist cheek whisker streak
    ['5c686a', '88979a', 'b6c5c8', 'e2eff0'],
]


def setup_art(v: int = 0) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        NOSE_EYE: 3.5,
        GLINT: 4.8,
        TUSK: 4.0,
        MARKING: 1.55 if v == 2 else 2.0,
        FROST: 1.15,
        SNOUT_DISC: 2.1,
        INNER_EAR: 1.7,
        BRISTLE: 1.30,
    }
    art.ink_color = lambda mat: hexc('12101a' if mat in (DARK, BRISTLE, NOSE_EYE) else '231a22')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def materials(v: int) -> None:
    idx = v % BUILDS_N
    setup_art(idx)
    frost = (
        ['3d494b', '627275', '8fa1a4', 'bccdce']
        if idx == 3
        else ['2a2936', '454454', '686678', '8f8da0']
    )
    ramps = [
        COATS[idx],                                         # 0 COAT
        BRISTLES[idx],                                      # 1 BRISTLE (Borstenkamm, tail tassel, dark guard fur)
        MARKINGS[idx],                                      # 2 MARKING (cheek whisker, piglet stripes)
        frost,                                              # 3 FROST (silvered shoulder mantle on Moor-/Nebelschwein)
        ['14121c', '252130', '3d374a', '5a5268'],           # 4 DARK (coarse lower stockings & cloven hooves)
        ['452b31', '6d464d', '98666b', 'be8a8e'],           # 5 SNOUT_DISC (wet tough leathery Wühlscheibe)
        ['0a0a13', '131220', '211f32', '333046'],           # 6 NOSE_EYE (nostrils, eyes, mouth interior)
        ['8e7f66', 'c2ae8c', 'ecdcc0', 'fffbf0'],           # 7 TUSK (polished ivory Hauer / canines)
        ['4d363c', '78565c', 'a3797e', 'c9a2a4'],           # 8 INNER_EAR
        ['9ea0a8', 'c8cacf', 'eaeced', 'ffffff'],           # 9 GLINT
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_boar_legs(
    m: art.Model,
    t: float,
    rear_y: float,
    front_y: float,
    kind: str,
    s: float,
    bulk: float,
    paw_scrape: float,
    paw_lift: float,
    sway_x: float,
) -> None:
    """Sturdy cloven-hoofed suid limbs: muscular upper shoulder/ham -> hock/carpus -> dark bristled shank -> cloven hoof."""
    r_shank = max(0.74, 0.90 * s)

    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (2.50 * bulk if front else 2.20) * s + sway_x * 0.35
            hip_z = (4.4 if front else -5.0) * s
            hip_y = (front_y if front else rear_y) - 0.65 * s

            if kind == 'sleep':
                # Articulated folded suid legs tucked naturally beside bedded chest & ham (zero ball stumps, grounded on y=52!)
                tuck = side * (0.98 if side > 0 else 0.85)
                root = np.array([hip_x * 0.92, hip_y + 0.25 * s, hip_z * 0.92])
                if front:
                    carpus = np.array([tuck * 3.05 * s, 1.75 * s, hip_z + 2.15 * s])
                    hoof = np.array([tuck * 2.35 * s, 0.92 * s, hip_z - 1.25 * s])
                    m.limb(root, carpus, r_shank * 1.50, r_shank * 1.05, COAT, step=0.35)
                    m.limb(carpus, hoof, r_shank * 1.00, r_shank * 0.84, DARK, step=0.34)
                    m.ell(hoof, (r_shank * 0.92, max(0.58, 0.65 * s), max(0.82, 0.98 * s)), DARK)
                else:
                    hock = np.array([tuck * 2.95 * s, 1.85 * s, hip_z - 1.95 * s])
                    hoof = np.array([tuck * 2.45 * s, 0.92 * s, hip_z + 2.15 * s])
                    m.limb(root, hock, r_shank * 1.58, r_shank * 1.08, COAT, step=0.35)
                    m.limb(hock, hoof, r_shank * 1.00, r_shank * 0.84, DARK, step=0.34)
                    m.ell(hoof, (r_shank * 0.92, max(0.58, 0.65 * s), max(0.82, 0.98 * s)), DARK)
                continue

            swing = 0.0
            lift = 0.0
            flex = 0.0

            if kind == 'walk':
                # Crisp 4-beat cloven-hoof trot
                diag = 0.0 if ((side > 0) == front) else 0.5
                lead = 0.06 if front else 0.0
                cyc = (t + diag + lead) % 1.0
                stance = 0.58
                if cyc < stance:
                    c = cyc / stance
                    swing = (2.35 * s) * (1.0 - 2.0 * c)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(2.35 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * (1.75 if front else 1.55) * s
                    flex = math.sin(c * math.pi) * 0.85 * s
            elif kind == 'forage':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.72
                if cyc < stance:
                    swing = (1.30 * s) * (1.0 - 2.0 * (cyc / stance))
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(1.30 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 0.85 * s
                if front:
                    swing += 0.55 * s
            elif kind == 'run':
                # Powerful charging gallop!
                lead = 0.08 if side > 0 else -0.08
                ang = ((t + (0.46 if front else 0.0) + lead) % 1.0) * math.tau
                airborne = max(0.0, math.sin(t * math.pi))
                if front:
                    swing = (3.95 * s) * math.sin(ang - 0.35)
                    lift = max(0.0, math.cos(ang)) * 2.15 * s + airborne * 0.95 * s
                    flex = max(0.0, -math.sin(ang)) * 1.15 * s
                else:
                    swing = -(4.15 * s) * math.sin(ang - 0.25)
                    lift = max(0.0, -math.cos(ang)) * 2.00 * s + airborne * 0.85 * s
                    flex = max(0.0, math.cos(ang)) * 1.10 * s
            elif kind == 'bark' and front and side > 0:
                # Defensive forehoof pawing / scraping earth!
                swing = paw_scrape * s
                lift = paw_lift * s
                flex = paw_lift * 0.42 * s
            elif kind == 'special' and front:
                swing = (1.25 if side > 0 else -0.45) * s

            foot_y = max(0.80 * s, 0.80 * s + lift)
            foot_x = side * (2.30 * bulk if front else 2.05) * s
            root = np.array([hip_x, hip_y, hip_z])
            foot = np.array([foot_x, foot_y, hip_z + swing])

            if front:
                joint = np.array([
                    0.5 * (hip_x + foot_x),
                    foot_y + (hip_y - foot_y) * 0.46 + flex * 0.30,
                    hip_z + swing * 0.55 + 0.32 * s + flex * 0.40,
                ])
                m.limb(root, joint, r_shank * 1.72 * bulk, r_shank * 1.14, COAT, step=0.36)
                m.limb(joint, foot, r_shank * 1.08, r_shank * 0.86, DARK, step=0.34)
            else:
                joint = np.array([
                    0.5 * (hip_x + foot_x),
                    foot_y + (hip_y - foot_y) * 0.46 + flex * 0.28,
                    hip_z + swing * 0.44 - 1.25 * s,
                ])
                m.limb(root, joint, r_shank * 1.78, r_shank * 1.14, COAT, step=0.36)
                m.limb(joint, foot, r_shank * 1.08, r_shank * 0.86, DARK, step=0.34)

            m.ell(
                foot + np.array([0.0, 0.0, 0.26 * s]),
                (r_shank * 0.96, max(0.60, 0.68 * s), max(0.92, 1.16 * s)),
                DARK,
            )


def _piglet_stripe_clip(q: np.ndarray) -> np.ndarray:
    """Conformal 3D surface mask creating 3 crisp parallel longitudinal cream-gold stripes per side."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    flank = (np.abs(x) > 0.22) & (np.abs(z) < 0.92)
    s_top = np.abs(y - 0.56) < 0.125
    s_mid = np.abs(y - 0.04) < 0.135
    s_low = np.abs(y + 0.46) < 0.120
    return flank & (s_top | s_mid | s_low)


def build_boar(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    keiler = (v == 1)
    piglet = (v == 2)
    moor = (v == 3)

    s = 1.07 if keiler else (0.64 if piglet else 1.0)
    bulk = 1.09 if keiler else (0.95 if piglet else 1.02)

    p = t * math.tau
    b = math.sin(p)

    # Stocky, front-heavy wild boar Keilform: massive deep shoulders sloping down to compact muscular hindquarters!
    stand_rear = 8.9 * s
    stand_front = (11.1 * bulk) * s

    rear_y = stand_rear
    front_y = stand_front
    crest_flare = 0.0
    sway_x = 0.0
    paw_scrape = 0.0
    paw_lift = 0.0
    jaw_open = 0.0
    body_z_shift = 0.0

    # Head pose defaults (wedge head continuing shoulder slope)
    hy = front_y - 0.50 * s
    hz = 8.8 * s
    pitch = 0.28
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        rear_y += 0.15 * b * s
        front_y += 0.22 * b * s
        hy = front_y - (0.46 - 0.16 * b) * s
        pitch = 0.28 - 0.03 * b
    elif kind == 'forage':
        # Snout lowered plowing forward into soil & scooping (8 frames)
        idx = int(t * 8) % 8
        plow = [0.35, 0.80, 1.0, 0.95, 1.0, 0.85, 0.55, 0.25][idx]
        scoop = [0.0, 0.15, 0.45, 0.85, 0.35, 0.90, 0.50, 0.10][idx]
        front_y -= 1.15 * plow * s
        rear_y += 0.20 * plow * s
        body_z_shift = 0.50 * scoop * s
        hy = front_y - (3.35 * plow - 0.65 * scoop) * s
        hz = (8.8 + 1.35 * plow + 0.60 * scoop) * s
        pitch = 0.28 + 0.40 * plow - 0.16 * scoop
        yaw = 0.10 * math.sin(p * 2.0) * plow
    elif kind == 'walk':
        bob = 0.24 * math.cos(p * 2.0) * s
        rear_y += bob
        front_y += 0.26 * math.cos(p * 2.0 - 0.5) * s
        hy = front_y - 0.55 * s + 0.18 * math.sin(p * 2.0) * s
        hz = 9.0 * s
        pitch = 0.30
    elif kind == 'alert':
        # Head & snout raised sniffing wind, dorsal bristle crest erected!
        crest_flare = 1.0
        front_y += 0.55 * s
        hy = front_y + (1.45 + 0.22 * b) * s
        hz = 8.4 * s
        pitch = 0.03 - 0.05 * b
        yaw = 0.08 * b
    elif kind == 'run':
        # Powerful charging gallop, tail held up!
        arc = math.sin(t * math.pi)
        wave = math.sin(p)
        lift_g = (1.55 * max(0.0, arc)) * s
        rear_y += lift_g - 0.70 * wave * s
        front_y += lift_g + 0.80 * wave * s
        crest_flare = 0.65
        hy = front_y - 0.30 * s + 0.40 * wave * s
        hz = 9.3 * s
        pitch = 0.22 - 0.08 * wave
    elif kind == 'groom':
        # Flank-rubbing sway & vigorous head-shake
        idx = int(t * 4) % 4
        sway_x = [0.65, -0.85, 0.90, -0.55][idx] * s
        roll = [-0.28, 0.38, -0.42, 0.22][idx]
        yaw = [0.16, -0.24, 0.26, -0.14][idx]
        hy = front_y - 0.75 * s
        pitch = 0.32
    elif kind == 'sleep':
        # Bedded low in forest litter on folded legs, chin/snout resting horizontally on ground!
        rear_y = (3.85 + 0.10 * b) * s
        front_y = (4.35 + 0.14 * b) * s
        hy = (3.15 + 0.08 * b) * s
        hz = 7.4 * s
        pitch = 0.14
        yaw = 0.10
    elif kind == 'bark':
        # Defensive warning snort + raised hackles + forehoof pawing/scraping earth + head toss!
        idx = int(t * 6) % 6
        crest_flare = 1.25
        paw_lift = [2.2, 1.6, 0.2, 0.0, 1.3, 0.0][idx]
        paw_scrape = [2.3, 0.4, -1.9, -1.1, 1.5, 0.0][idx]
        toss = [0.15, 0.45, 1.0, 0.85, 0.35, 0.10][idx]
        jaw_open = [0.2, 0.7, 1.0, 0.75, 0.3, 0.0][idx]
        front_y += (0.35 + 0.65 * toss) * s
        hy = front_y + (-0.35 + 2.30 * toss) * s
        hz = (8.7 + 0.50 * toss) * s
        pitch = 0.26 - 0.38 * toss
    elif kind == 'special':
        # Deep truffle-rooting plow (frames 0..3) & upward tusk/snout toss (frames 4..5)!
        idx = int(t * 6) % 6
        plow_k = [0.55, 0.95, 1.0, 0.90, 0.0, 0.0][idx]
        toss_k = [0.0, 0.0, 0.0, 0.15, 1.0, 0.55][idx]
        crest_flare = 0.60 * toss_k
        front_y += (-1.35 * plow_k + 0.85 * toss_k) * s
        rear_y += (0.35 * plow_k - 0.15 * toss_k) * s
        body_z_shift = (0.75 * plow_k - 0.20 * toss_k) * s
        hy = front_y + (-3.55 * plow_k + 2.45 * toss_k) * s
        hz = (8.8 + 1.55 * plow_k + 0.45 * toss_k) * s
        pitch = 0.28 + 0.44 * plow_k - 0.46 * toss_k
        jaw_open = 0.55 * toss_k

    # ---- Seamless wedge torso spine (9 overlapping ellipsoids from compact rump to massive shoulder shield) ----
    spine_slope = math.atan2(front_y - rear_y, 9.6 * s)
    R_spine = art.rot_x(-spine_slope)
    for i in range(9):
        u = i / 8.0
        sz = (-5.2 + 9.8 * u) * s + body_z_shift
        sx = sway_x * (0.4 + 0.6 * math.sin(u * math.pi))
        arch = math.sin(u * math.pi)
        # Prominent high shoulder hump peaking around u = 0.78..0.90
        hump = (1.15 * bulk * (u ** 1.5) * math.sin(u * math.pi * 0.88)) * s
        sy = rear_y * (1.0 - u) + front_y * u + hump
        rx_r = (3.20 + (1.20 * bulk - 0.10) * (u ** 1.2) + 0.38 * arch) * s
        ry_r = (3.65 + (1.40 * bulk - 0.05) * (u ** 1.3) + 0.48 * arch) * s
        rz_r = (2.75 + 0.75 * arch + 0.35 * u) * s
        m.ell((sx, sy, sz), (rx_r, ry_r, rz_r), COAT, R=R_spine)

        # Build 2 (Frischling): Conformal 3-stripe cream-gold juvenile flank shell!
        if piglet and 1 <= i <= 7:
            m.ell(
                (sx, sy, sz),
                (rx_r + 0.06, ry_r + 0.06, rz_r + 0.06),
                MARKING,
                R=R_spine,
                clip=_piglet_stripe_clip,
            )

    # Dark coarse bristled lower belly & deep chest keel
    for u_b in (0.25, 0.55, 0.84):
        bz = (-4.8 + 9.2 * u_b) * s + body_z_shift
        by_b = rear_y * (1.0 - u_b) + front_y * u_b - (2.25 + 0.48 * u_b) * s
        m.ell((sway_x * 0.5, by_b, bz), (2.70 * bulk * s, 1.85 * s, 2.75 * s), BRISTLE, R=R_spine)

    # Build 3 (Moor-/Nebelschwein): Natural silvered shoulder frost cap draped across upper shoulder shield!
    if moor:
        for u_f in (0.58, 0.74, 0.88):
            fz = (-5.2 + 9.8 * u_f) * s + body_z_shift
            hump_f = (1.15 * bulk * (u_f ** 1.5) * math.sin(u_f * math.pi * 0.88)) * s
            fy = rear_y * (1.0 - u_f) + front_y * u_f + hump_f + 1.55 * s
            m.ell(
                (sway_x * 0.6, fy, fz),
                (4.05 * bulk * s, 3.15 * s, 2.55 * s),
                FROST,
                R=R_spine,
            )

    # ---- Raised Dorsal Bristle Crest (Borstenkamm / Federn) ----
    crest_h_scale = (1.45 if keiler else (0.45 if piglet else 1.0)) + 0.55 * crest_flare
    for ci in range(8):
        uc = 0.16 + 0.84 * (ci / 7.0)
        cz = (-5.2 + 9.8 * uc) * s + body_z_shift
        hump_c = (1.15 * bulk * (uc ** 1.5) * math.sin(uc * math.pi * 0.88)) * s
        base_ry = (3.65 + (1.40 * bulk - 0.05) * (uc ** 1.3) + 0.48 * math.sin(uc * math.pi)) * s
        profile = math.sin(((uc - 0.12) / 0.92) * math.pi) ** 0.75
        cy_c = rear_y * (1.0 - uc) + front_y * uc + hump_c + base_ry - 0.35 * s
        tuft_h = max(0.55, (0.75 + 1.25 * profile) * crest_h_scale * s)
        m.ell(
            (sway_x * 0.7, cy_c + tuft_h * 0.42, cz),
            (max(0.62, 0.88 * s), tuft_h, max(0.85, 1.35 * s)),
            BRISTLE,
            R=R_spine,
        )

    # ---- Thin Tasseled Tail (Pürzel + Quaste) ----
    tail_root = np.array([sway_x * 0.3, rear_y + 1.15 * s, -6.2 * s + body_z_shift])
    r_tail = max(0.58, 0.64 * s)
    if kind in ('run', 'bark'):
        # Tail held straight up like a battle pennant when charging or barking!
        swish = 0.45 * math.sin(p * 2.0) * s
        tail_mid = tail_root + np.array([swish * 0.5, 2.35 * s, -1.05 * s])
        tail_tip = tail_root + np.array([swish, 4.55 * s, -1.45 * s])
    elif kind == 'alert':
        tail_mid = tail_root + np.array([0.0, 1.15 * s, -1.75 * s])
        tail_tip = tail_root + np.array([0.0, 2.25 * s, -2.85 * s])
    elif kind == 'sleep':
        tail_mid = tail_root + np.array([0.6 * s, -1.05 * s, -1.35 * s])
        tail_tip = tail_root + np.array([1.1 * s, -1.85 * s, -2.05 * s])
    else:
        swish = (1.25 * math.sin(p) if kind == 'idle' else 0.65 * math.sin(p * 2.0)) * s
        tail_mid = tail_root + np.array([swish * 0.5, -1.35 * s, -1.65 * s])
        tail_tip = tail_root + np.array([swish, -3.05 * s, -2.45 * s])
    m.limb(tail_root, tail_mid, r_tail * 1.15, r_tail * 0.90, COAT, step=0.35)
    m.limb(tail_mid, tail_tip, r_tail * 0.88, r_tail * 0.80, BRISTLE, step=0.35)
    m.ell(tail_tip, (r_tail * 1.25, r_tail * 1.45, r_tail * 1.25), BRISTLE)

    # ---- Thick Wedge Neck Collar & Conical Rooting Head + Flat Nasal Disc (Wühlscheibe) ----
    head = np.array([math.sin(yaw) * 1.2 * s + sway_x * 0.85, hy, hz + body_z_shift])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * s)

    def head_ell(
        pos: tuple[float, float, float],
        r: tuple[float, float, float],
        mat: int,
        R_extra: np.ndarray | None = None,
    ) -> None:
        m.ell(
            hp(*pos),
            tuple(max(0.45, a * s) for a in r),
            mat,
            R=rot if R_extra is None else rot @ R_extra,
        )

    # Thick neckless muscular shoulder-to-skull wedge bridge
    neck_shld = np.array([sway_x * 0.75, front_y + 0.55 * s, 4.4 * s + body_z_shift])
    skull_back = hp(0.0, 0.35, -1.65)
    m.limb(neck_shld, skull_back, 3.65 * bulk * s, 2.95 * bulk * s, COAT, step=0.40)
    if moor:
        m.ell(0.6 * neck_shld + 0.4 * skull_back + np.array([0.0, 1.35 * s, 0.0]), (3.35 * s, 2.45 * s, 2.35 * s), FROST)
    # Nape bristle crest continuation onto crown
    m.limb(
        neck_shld + np.array([0.0, 3.35 * bulk * s, 0.0]),
        hp(0.0, 2.95, -0.85),
        max(0.65, 0.85 * s),
        max(0.60, 0.72 * s),
        BRISTLE,
        step=0.38,
    )

    # Broad rear skull & muscular jowls -> straight conical rooting snout -> flat tilted Wühlscheibe!
    head_ell((0.0, 0.35, -0.55), (2.95 * bulk, 2.85, 2.95), COAT)
    head_ell((0.0, -0.15, 1.55), (2.15, 2.05, 2.35), COAT)
    head_ell((0.0, -0.45, 3.45), (1.58, 1.42, 2.05), COAT)
    head_ell((0.0, -0.62, 4.85), (1.32, 1.18, 1.35), DARK)

    # Iconic flat circular/oval wet rooting nasal disc (Wühlscheibe) with raised upper rim & nostrils!
    R_disc = art.rot_x(-0.18)
    head_ell((0.0, -0.48, 5.75), (1.38, 1.26, 0.65), SNOUT_DISC, R_disc)
    for side in (-1.0, 1.0):
        head_ell((side * 0.48, -0.46, 6.18), (0.34, 0.38, 0.32), NOSE_EYE, R_disc)

    # Lower jaw & chin (parts during warning bark / tusk toss)
    drop = 0.95 * jaw_open
    if jaw_open > 0.2:
        head_ell((0.0, -1.25 - drop * 0.45, 3.25), (0.95, 0.52, 1.55), NOSE_EYE)
    head_ell((0.0, -1.35 - drop, 2.95), (1.28, 0.72, 2.15), BRISTLE)

    # Grizzled pale cheek whisker streak (Backenbart) sweeping back along lower cheek (Builds 0, 1, 3)
    if not piglet:
        for side in (-1.0, 1.0):
            m.limb(
                hp(side * 1.65, -1.05, 1.95),
                hp(side * 2.55 * bulk, -0.80, -0.65),
                max(0.56, 0.64 * s),
                max(0.62, 0.78 * s),
                MARKING,
                step=0.35,
            )

    # ---- Tusks (Hauer / Gewehr) ----
    if keiler:
        # Prominent upward-curved ivory lower tusks sweeping outward & upward beside snout!
        for side in (-1.0, 1.0):
            t_base = hp(side * 1.25, -0.95 - drop * 0.6, 3.65)
            t_mid = hp(side * 2.22, -0.05 - drop * 0.3, 3.82)
            t_tip = hp(side * 2.52, 1.45, 3.35)
            m.limb(t_base, t_mid, 0.68 * s, 0.58 * s, TUSK, step=0.22)
            m.limb(t_mid, t_tip, 0.58 * s, 0.48 * s, TUSK, step=0.20)
            m.ell(t_tip, (0.48 * s, 0.54 * s, 0.48 * s), TUSK)
    elif moor:
        # Medium adult tusks on Moor-/Nebelschwein
        for side in (-1.0, 1.0):
            t_base = hp(side * 1.25, -0.92 - drop * 0.5, 3.60)
            t_tip = hp(side * 1.98, 0.48, 3.55)
            m.limb(t_base, t_tip, 0.56 * s, 0.45 * s, TUSK, step=0.22)
    elif v == 0:
        # Small modest canine tips (Haken) on Leitbache
        for side in (-1.0, 1.0):
            head_ell((side * 1.55, -0.68 - drop * 0.5, 3.65), (0.46, 0.48, 0.46), TUSK)

    # ---- Forward/Upward Hairy Ears (Teller) & Deep-Set Expressive Boar Eyes ----
    blink = (kind == 'idle' and t >= 0.75) or (kind == 'sleep' and int(t * 4) % 4 in (1, 2, 3))
    for side in (-1.0, 1.0):
        ear_flick = 0.18 * math.sin(p * 2.0 + (0.8 if side > 0 else -0.5)) if kind == 'idle' else 0.0
        ear_splay = 0.38 if kind in ('alert', 'bark') else (0.58 if kind == 'sleep' else 0.46)
        ear_fwd = 0.36 if kind in ('alert', 'bark') else (-0.12 if kind == 'run' else 0.22 + ear_flick)
        R_ear = rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        head_ell((side * 2.05 * bulk, 2.55, -1.15), (0.98, 2.15, 0.68), BRISTLE, R_ear)
        head_ell((side * 1.98 * bulk, 2.40, -1.05), (0.82, 1.85, 0.58), COAT, R_ear)
        head_ell((side * 1.95 * bulk, 2.35, -0.68), (0.52, 1.35, 0.28), INNER_EAR, R_ear)

        # Deep-set wild boar eye under heavy brow ridge
        eye_x = 1.92 if not piglet else 1.82
        head_ell((side * eye_x, 0.72, 0.95), (0.48, 0.18 if blink else 0.52, 0.52), NOSE_EYE)
        if not blink:
            head_ell((side * (eye_x + 0.12), 0.90, 1.12), (0.20, 0.20, 0.18), GLINT)

    draw_boar_legs(m, t, rear_y, front_y, kind, s, bulk, paw_scrape, paw_lift, sway_x)
    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_boar(v, kind, (col - start) / n)
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_qa(out_path: Path, zoom: int = 3) -> None:
    """Render a crisp 3x nearest-neighbor QA contact sheet showing all 4 builds across facings and all 9 animations."""
    picks = [
        (0, 0),   # E idle (wedge silhouette, tusks, piglet stripes)
        (1, 0),   # SE idle (3/4 tusks & Wühlscheibe)
        (2, 0),   # S idle (front wedge, ears & tusks)
        (4, 0),   # W idle
        (6, 0),   # N idle (rear view)
        (0, 6),   # E forage rooting plow
        (0, 14),  # E walk trot
        (1, 21),  # SE alert (snout raised + erected Borstenkamm)
        (0, 26),  # E charging gallop (tail held up!)
        (2, 33),  # S groom head-shake/sway
        (1, 37),  # SE sleep (bedded on folded legs, snout on ground)
        (0, 41),  # E bark (forehoof pawing + raised hackles)
        (0, 42),  # E bark (head toss + open jaw)
        (0, 48),  # E special deep truffle plow
        (0, 50),  # E special upward tusk/snout toss!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([46, 55, 47, 255], np.uint8)
    grid[:, :] = bg
    for v in range(BUILDS_N):
        grid[v * H + 52, :] = np.array([62, 74, 63, 255], np.uint8)
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
                print(f'boar build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/boar.png', sheet)
    print('Saved assets/wildlife/boar.png', sheet.shape)


if __name__ == '__main__':
    main()
