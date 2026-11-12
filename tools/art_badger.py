#!/usr/bin/env python3
"""European Badger (Meles meles / Europäischer Dachs) + Badger Sett (Dachsbau) in the SS=4 3D pixel-art pipeline.
badger.png: 64x64 frames, feet at (32, 52); 52 columns; 3 builds x 8 true facings = 24 rows (3328x1536).
Builds:
  0: Klassischer Silberdachs (bright silver-grey grizzled mantle, jet-black underparts, crisp white/black mask)
  1: Moor-/Altdachs (warmer grizzled umber-silver mantle, heavier shoulders)
  2: Jungdachs (0.80x scale anchored cleanly on GROUND_ROW=52.0, soft clean silver coat & bright mask)
Columns (52):
  idle 0:4, forage 4:10, walk 10:18, alert 18:22, run 22:30,
  groom 30:34, sleep 34:38, special 38:46 (digging), bark 46:52 (bristled warning grunt/lunge).
badger_den.png: 48x36 px (SS=4), grounded mossy forest earth mound framed by gnarled brown tree roots,
  excavated dirt fan with tiny stones in front, and deep shadowed arched burrow entrance at (24, 24..30).
Usage: py -3 tools/art_badger.py [--preview-only] [--qa=path.png]
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

COAT, GRIZZLE, WHITE_MASK, BLACK_UNDER, BLACK_STRIPE, NOSE_EYE, CLAW, PALE_TAIL, GLINT = range(9)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 6),
    ('walk', 10, 8),
    ('alert', 18, 4),
    ('run', 22, 8),
    ('groom', 30, 4),
    ('sleep', 34, 4),
    ('special', 38, 8),
    ('bark', 46, 6),
]

COATS = [
    # 0 Klassischer Silberdachs: coarse bright silver-grey grizzled mantle
    ['2d313a', '545a66', '87909e', 'c0c8d4'],
    # 1 Moor-/Altdachs: warmer grizzled umber-silver woodland coat
    ['332a27', '5b4d46', '8a786c', 'baa99a'],
    # 2 Jungdachs: soft clean bright silver-ash coat
    ['343944', '606776', '959dab', 'ccd4e0'],
]

GRIZZLES = [
    # 0 Darker slate-silver dorsal guard hair saddle
    ['21242c', '3f4450', '697180', '9aa2b0'],
    # 1 Deeper peat-umber grizzled saddle
    ['251e1d', '453935', '6e5e55', '9c8b7e'],
    # 2 Soft pewter dorsal tone
    ['282c36', '4b515e', '798190', 'aeb6c4'],
]

MASKS = [
    # 0 Crisp snow-white badger facial mask & ear rims
    ['90949e', 'c2c6d0', 'eff2f7', 'ffffff'],
    # 1 Warm ivory-white old badger mask
    ['8e847a', 'beb4a8', 'ebe3d6', 'fffaf2'],
    # 2 Pure bright white juvenile mask
    ['9498a2', 'c6cad4', 'f2f4f9', 'ffffff'],
]


def setup_badger_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        NOSE_EYE: 3.6,
        GLINT: 5.0,
        CLAW: 2.05,
        BLACK_STRIPE: 2.30,
        WHITE_MASK: 1.95,
        PALE_TAIL: 1.45,
        BLACK_UNDER: 1.25,
        GRIZZLE: 1.08,
    }
    art.ink_color = lambda mat: hexc('0e0d16' if mat in (BLACK_UNDER, BLACK_STRIPE, NOSE_EYE) else '1f1b26')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def materials(v: int) -> None:
    setup_badger_art()
    idx = v % BUILDS_N
    tail_tip = (
        ['7d756c', 'ada398', 'dbd2c6', 'f7f0e6']
        if idx == 1
        else ['828690', 'b2b7c2', 'dfe3ec', 'fafcfe']
    )
    ramps = [
        COATS[idx],                                         # 0 COAT (silver-grey grizzled mantle)
        GRIZZLES[idx],                                      # 1 GRIZZLE (dorsal guard-hair saddle nuance)
        MASKS[idx],                                         # 2 WHITE_MASK (crisp white head blaze, cheeks, ear rims)
        ['0c0c14', '171623', '282738', '3d3b50'],           # 3 BLACK_UNDER (jet-black throat, belly & digging legs)
        ['090911', '12111d', '201f2f', '323044'],           # 4 BLACK_STRIPE (bold black facial eye-to-ear stripes)
        ['06060d', '0e0d18', '1a1828', '2b283c'],           # 5 NOSE_EYE (wet black nose pad, eye core, mouth)
        ['665b4c', '94856e', 'c2b298', 'e6d9c2'],           # 6 CLAW (natural pale horn digging foreclaws)
        tail_tip,                                           # 7 PALE_TAIL (blunt pale-tipped tail)
        ['a6a8b2', 'cfd2da', 'f0f2f6', 'ffffff'],           # 8 GLINT (crisp eye highlight inside black mask)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def _head_stripe_clip(q: np.ndarray) -> np.ndarray:
    """Conformal 3D mask for the two bold black longitudinal stripes:
    leaves a crisp white center blaze (|x| <= 0.33) and crisp white lower cheeks (y <= -0.20)!"""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    ax = np.abs(x)
    return (ax > 0.33) & (ax < 0.85) & (y > -0.20) & (y < 0.72) & (z > -0.88) & (z < 0.90)


def _snout_stripe_clip(q: np.ndarray) -> np.ndarray:
    """Continues the two bold black longitudinal stripes forward along the sides of the snout toward the nose."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    ax = np.abs(x)
    return (ax > 0.34) & (ax < 0.87) & (y > -0.18) & (y < 0.68) & (z < 0.72)


def draw_badger_legs(
    m: art.Model,
    t: float,
    rear_y: float,
    front_y: float,
    kind: str,
    s: float,
    bulk: float,
    sway_x: float,
    dig_idx: int,
    lunge_z: float,
) -> None:
    """Short, powerful jet-black plantigrade digging legs with sturdy pale horn foreclaws."""
    r_leg = max(0.82, 1.02 * s)

    if kind == 'sleep':
        # Tucked neatly beneath curled badger ball on GROUND_ROW=52.0 (zero detached stumps)
        for side in (-1.0, 1.0):
            paw_pos = np.array([side * 2.35 * s, 0.95 * s, 1.45 * s])
            m.limb((side * 2.45 * s, 2.55 * s, 0.65 * s), paw_pos, r_leg * 1.25, r_leg * 0.95, BLACK_UNDER, step=0.35)
            m.ell(paw_pos, (r_leg * 1.05, max(0.62, 0.72 * s), 1.35 * s), BLACK_UNDER)
        return

    seated = (kind == 'groom')
    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (2.65 * bulk if front else 2.85) * s + sway_x * 0.45
            hip_z = (4.1 if front else -4.6) * s + lunge_z * (0.75 if front else 0.25)
            hip_y = (front_y if front else rear_y) - 0.85 * s

            if seated and not front:
                hock = np.array([side * 3.05 * s, 1.45 * s, hip_z - 0.45 * s])
                paw = np.array([side * 2.75 * s, 0.85 * s, hip_z + 2.15 * s])
                m.limb((hip_x, hip_y, hip_z), hock, r_leg * 1.45, r_leg * 1.02, BLACK_UNDER, step=0.36)
                m.limb(hock, paw, r_leg * 0.98, r_leg * 0.88, BLACK_UNDER, step=0.34)
                m.ell(paw, (r_leg * 1.05, max(0.62, 0.70 * s), 1.35 * s), BLACK_UNDER)
                continue

            swing = 0.0
            lift = 0.0
            flex = 0.0

            if kind == 'walk':
                # Characteristic rolling plantigrade 4-beat waddle
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.62
                if cyc < stance:
                    c = cyc / stance
                    swing = (2.15 * s) * (1.0 - 2.0 * c)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(2.15 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.35 * s
                    flex = math.sin(c * math.pi) * 0.65 * s
            elif kind == 'forage':
                # Slow nose-to-earth shuffling step
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.70
                if cyc < stance:
                    swing = (1.35 * s) * (1.0 - 2.0 * (cyc / stance))
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(1.35 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 0.85 * s
            elif kind == 'run':
                # Fast low-bellied lumbering mustelid trot/gallop
                lead = 0.10 if side > 0 else -0.10
                ang = ((t + (0.48 if front else 0.0) + lead) % 1.0) * math.tau
                if front:
                    swing = (3.35 * s) * math.sin(ang - 0.30)
                    lift = max(0.0, math.cos(ang)) * 1.75 * s
                else:
                    swing = -(3.45 * s) * math.sin(ang - 0.25)
                    lift = max(0.0, -math.cos(ang)) * 1.65 * s
            elif kind == 'special' and front:
                # Vigorous two-forepaw earth-digging motion (alternating fast overlapping scoops!)
                dig_phase = (dig_idx + (4 if side < 0 else 0)) % 8
                swing = [2.6, 1.4, -0.8, -2.4, -1.6, 0.4, 2.0, 2.8][dig_phase] * s
                lift = [0.6, 0.0, 0.0, 0.3, 1.5, 2.2, 1.8, 1.1][dig_phase] * s
                flex = [0.4, 0.2, 0.3, 0.6, 1.1, 1.2, 0.9, 0.5][dig_phase] * s
            elif kind == 'bark' and front:
                # Wide braced defensive forepaws sliding forward on bluff lunge
                swing = (0.85 * s) + lunge_z * 0.35

            foot_y = max(0.80 * s, 0.80 * s + lift)
            paw_x = side * (2.45 * bulk if front else 2.60) * s
            root = np.array([hip_x, hip_y, hip_z])
            foot = np.array([paw_x, foot_y, hip_z + swing])

            if front:
                elbow = np.array([
                    0.5 * (hip_x + paw_x),
                    foot_y + (hip_y - foot_y) * 0.48 + flex * 0.28,
                    hip_z + swing * 0.52 + 0.30 * s + flex * 0.35,
                ])
                m.limb(root, elbow, r_leg * 1.55 * bulk, r_leg * 1.12, BLACK_UNDER, step=0.36)
                m.limb(elbow, foot, r_leg * 1.08, r_leg * 0.92, BLACK_UNDER, step=0.34)
                # Broad flat plantigrade digging forepaw
                paw_c = foot + np.array([0.0, 0.0, 0.35 * s])
                m.ell(paw_c, (r_leg * 1.10, max(0.62, 0.70 * s), max(1.05, 1.35 * s)), BLACK_UNDER)
                # Sturdy pale horn digging foreclaws at toe tips!
                claw_ext = 1.65 if kind == 'special' else 1.42
                for cx_off in (-0.55, 0.0, 0.55):
                    c_base = paw_c + np.array([cx_off * s, -0.10 * s, 0.88 * s])
                    c_tip = paw_c + np.array([cx_off * 1.05 * s, -0.18 * s, claw_ext * s])
                    m.limb(c_base, c_tip, max(0.34, 0.38 * s), max(0.28, 0.32 * s), CLAW, step=0.22)
            else:
                hock = np.array([
                    0.5 * (hip_x + paw_x),
                    foot_y + (hip_y - foot_y) * 0.48 + flex * 0.25,
                    hip_z + swing * 0.44 - 0.95 * s,
                ])
                m.limb(root, hock, r_leg * 1.65, r_leg * 1.12, BLACK_UNDER, step=0.36)
                m.limb(hock, foot, r_leg * 1.06, r_leg * 0.90, BLACK_UNDER, step=0.34)
                m.ell(
                    foot + np.array([0.0, 0.0, 0.28 * s]),
                    (r_leg * 1.05, max(0.60, 0.68 * s), max(1.05, 1.32 * s)),
                    BLACK_UNDER,
                )


def build_badger(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    old_moor = (v == 1)
    cub = (v == 2)

    s = 0.80 if cub else 1.0
    bulk = 1.09 if old_moor else (0.96 if cub else 1.0)

    p = t * math.tau
    b = math.sin(p)
    dig_idx = int(t * 8) % 8

    # ---- Curled Nose-to-Tail Sleeping Ball (cols 34:38) ----
    if kind == 'sleep':
        breath = 0.14 * b * s
        by = (3.95 + 0.10 * b) * s
        # Broad silver-grey grizzled C-curled back curving from front-left shoulder around rear to right haunch
        for i in range(9):
            u_c = i / 8.0
            ang = -0.75 - 2.65 * u_c
            rad = 3.65 * s
            cx = math.sin(ang) * rad * 0.95
            cz = math.cos(ang) * rad - 0.35 * s
            rx_c = (3.35 + 0.45 * math.sin(u_c * math.pi)) * bulk * s
            ry_c = (2.85 + 0.30 * math.sin(u_c * math.pi)) * s + breath
            m.ell((cx, by, cz), (rx_c, ry_c, rx_c), COAT)
            if 2 <= i <= 6:
                m.ell((cx, by + 0.90 * s, cz), (rx_c * 0.76, ry_c * 0.64, rx_c * 0.76), GRIZZLE)
            m.ell((cx * 0.88, max(1.40 * s, by - 1.55 * s), cz * 0.88), (rx_c * 0.82, 1.30 * s, rx_c * 0.82), BLACK_UNDER)

        # Short blunt pale-tipped tail curling forward on the right side to meet the snout!
        m.limb((2.4 * s, by - 0.30 * s, -2.6 * s), (3.4 * s, by - 0.50 * s, 0.2 * s), 1.65 * s, 1.45 * s, COAT, step=0.36)
        m.ell((3.0 * s, by - 0.55 * s, 1.65 * s), (1.50 * s, 1.20 * s, 1.55 * s), PALE_TAIL)

        # Tucked crisp white-and-black striped head resting visibly nose-to-tail in front-right pocket!
        hx, hy_s, hz_s = 0.35 * s, by + 0.95 * s, 2.55 * s
        rot_h = art.rot_y(0.68) @ art.rot_x(0.30)
        r_sk = np.array([2.40 * s, 2.05 * s, 2.50 * s])
        m.ell((hx, hy_s, hz_s), r_sk, WHITE_MASK, R=rot_h)
        m.ell((hx, hy_s, hz_s), r_sk + 0.05, BLACK_STRIPE, R=rot_h, clip=_head_stripe_clip)
        sn_c = np.array([hx, hy_s, hz_s]) + rot_h @ np.array([0.0, -0.32 * s, 1.95 * s])
        r_sn = np.array([1.45 * s, 1.18 * s, 1.70 * s])
        m.ell(sn_c, r_sn, WHITE_MASK, R=rot_h)
        m.ell(sn_c, r_sn + 0.05, BLACK_STRIPE, R=rot_h, clip=_snout_stripe_clip)
        nose_c = np.array([hx, hy_s, hz_s]) + rot_h @ np.array([0.0, -0.42 * s, 3.40 * s])
        m.ell(nose_c, (max(0.50, 0.62 * s), max(0.45, 0.52 * s), max(0.50, 0.56 * s)), NOSE_EYE, R=rot_h)
        for side in (-1.0, 1.0):
            eb = np.array([hx, hy_s, hz_s]) + rot_h @ np.array([side * 1.65 * s, 1.45 * s, -0.75 * s])
            er = np.array([hx, hy_s, hz_s]) + rot_h @ np.array([side * 1.75 * s, 1.92 * s, -0.70 * s])
            m.ell(eb, (max(0.55, 0.72 * s), max(0.65, 0.85 * s), max(0.48, 0.58 * s)), BLACK_STRIPE, R=rot_h)
            m.ell(er, (max(0.52, 0.68 * s), max(0.45, 0.55 * s), max(0.45, 0.52 * s)), WHITE_MASK, R=rot_h)
        draw_badger_legs(m, t, by, by, kind, s, bulk, 0.0, 0, 0.0)
        return m

    # ---- Low-Slung Broad Wedge Mustelid Body Heights ----
    rear_y = 7.35 * s
    front_y = 6.75 * s
    sway_x = 0.0
    bristle_w = 1.0
    lunge_z = 0.0
    jaw_open = 0.0

    # Head pose defaults
    hy = front_y + 1.25 * s
    hz = 8.3 * s
    pitch = 0.18
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        rear_y += 0.12 * b * s
        front_y += 0.15 * b * s
        # Low stance, nose sniffing air
        hy = front_y + (1.35 + 0.35 * math.sin(p)) * s
        pitch = 0.15 - 0.08 * math.sin(p)
        yaw = 0.08 * math.cos(p)
    elif kind == 'forage':
        # Nose-to-earth shuffling worm/root search (6 frames)
        front_y = 5.95 * s
        rear_y = 7.45 * s
        hy = (2.85 + 0.25 * abs(b)) * s
        hz = 9.2 * s
        pitch = 0.52
        yaw = 0.24 * b
        sway_x = 0.35 * b * s
    elif kind == 'walk':
        # Characteristic rolling plantigrade waddle!
        bob = 0.18 * math.cos(p * 2.0) * s
        sway_x = 0.68 * math.sin(p) * s
        rear_y += bob
        front_y += 0.18 * math.cos(p * 2.0 - 0.6) * s
        hy = front_y + 0.75 * s
        hz = 8.6 * s
        pitch = 0.22
        yaw = 0.10 * math.sin(p)
        roll = -0.10 * math.sin(p)
    elif kind == 'alert':
        # Head & forequarters raised sniffing evening breeze, showing bold black-and-white mask clearly!
        idx_a = int(t * 4) % 4
        front_y = 8.15 * s
        rear_y = 7.05 * s
        hy = front_y + (2.55 + 0.25 * b) * s
        hz = 7.8 * s
        pitch = -0.04 - 0.05 * b
        yaw = [0.06, 0.20, 0.14, -0.08][idx_a]
        roll = [0.04, 0.16, 0.14, -0.04][idx_a]
    elif kind == 'run':
        # Fast low-bellied lumbering trot
        wave = math.sin(p)
        lift_g = 0.85 * max(0.0, math.sin(p - 0.3)) * s
        rear_y = (7.45 * s) + lift_g - 0.55 * wave * s
        front_y = (6.85 * s) + lift_g + 0.65 * wave * s
        hy = front_y + 0.95 * s + 0.30 * wave * s
        hz = 8.8 * s
        pitch = 0.16
    elif kind == 'groom':
        # Seated/leaning flank scratch & vigorous coat shake
        idx_g = int(t * 4) % 4
        groom_k = [0.35, 0.95, 1.0, 0.40][idx_g]
        rear_y = 5.15 * s
        front_y = 7.45 * s
        sway_x = [0.2, -0.5, 0.6, -0.3][idx_g] * s
        hy = front_y + (0.85 - 0.95 * groom_k) * s
        hz = (7.4 - 3.8 * groom_k) * s
        yaw = 1.18 * groom_k
        pitch = 0.32 * groom_k
        roll = -0.22 * groom_k
    elif kind == 'special':
        # Vigorous two-forepaw earth-digging motion (8 frames)
        rear_y = (7.95 + 0.20 * math.sin(p * 2.0)) * s
        front_y = (5.75 + 0.25 * math.cos(p * 2.0)) * s
        hy = front_y - (1.35 - 0.30 * math.sin(p * 2.0)) * s
        hz = 8.4 * s
        pitch = 0.46
        yaw = 0.08 * math.sin(p * 2.0)
    elif kind == 'bark':
        # Bristled low defensive warning grunt / lunge (6 frames)!
        idx_b = int(t * 6) % 6
        bristle_w = [1.10, 1.18, 1.18, 1.15, 1.10, 1.04][idx_b]
        lunge_z = [-0.65, 1.35, 1.65, 1.10, 0.35, 0.0][idx_b] * s
        jaw_open = [0.2, 0.95, 1.0, 0.70, 0.25, 0.0][idx_b]
        rear_y = (7.25 + 0.25 * (1.0 if idx_b in (1, 2) else 0.0)) * s
        front_y = (6.15 if idx_b == 0 else (6.95 if idx_b in (1, 2, 3) else 6.65)) * s
        hy = front_y + (0.75 if idx_b == 0 else 1.65) * s
        hz = 8.4 * s + lunge_z * 1.15
        pitch = 0.22 if idx_b == 0 else 0.04

    # ---- Broad Low-Slung Mustelid Wedge Torso (Silver-Grey Mantle + Jet-Black Belly) ----
    spine_slope = math.atan2(front_y - rear_y, 9.0 * s)
    R_spine = art.rot_x(-spine_slope)
    for i in range(9):
        u = i / 8.0
        sz = (-4.9 + 9.2 * u) * s + lunge_z * (0.3 + 0.7 * u)
        sx = sway_x * (0.5 + 0.5 * math.sin(u * math.pi))
        arch = math.sin(u * math.pi)
        sy = rear_y * (1.0 - u) + front_y * u + 0.32 * arch * s
        taper_w = (4.35 * (1.0 - 0.16 * u) + 0.42 * arch) * (bulk if u > 0.45 else 1.0) * bristle_w * s
        ry_r = (3.50 * (1.0 - 0.10 * u) + 0.35 * arch) * s
        rz_r = (2.75 + 0.65 * arch) * s
        m.ell((sx, sy, sz), (taper_w, ry_r, rz_r), COAT, R=R_spine)

        # Subtle darker grizzled dorsal guard-hair band along center of mantle
        if 1 <= i <= 6:
            m.ell(
                (sx, sy + 0.85 * s, sz),
                (taper_w * 0.72, ry_r * 0.74, rz_r * 0.85),
                GRIZZLE,
                R=R_spine,
            )

    # Reverse countershading: JET-BLACK belly, lower flanks & chest!
    for u_b in (0.18, 0.46, 0.74, 0.94):
        bz = (-4.6 + 8.9 * u_b) * s + lunge_z * (0.3 + 0.7 * u_b)
        by_b = rear_y * (1.0 - u_b) + front_y * u_b - 1.75 * s
        bw = (3.85 * (1.0 - 0.14 * u_b)) * bulk * bristle_w * s
        m.ell((sway_x * 0.5, by_b, bz), (bw, 1.85 * s, 2.65 * s), BLACK_UNDER, R=R_spine)

    # ---- Short Broad Blunt Pale-Tipped Tail ----
    t_root = np.array([sway_x * 0.4, rear_y - 0.15 * s, -5.2 * s + lunge_z * 0.25])
    t_sway = (0.55 * math.sin(p) if kind in ('idle', 'walk') else 0.0) * s
    t_lift = (0.95 * s if kind == 'bark' else 0.0)
    t_mid = t_root + np.array([t_sway * 0.5, -0.95 * s + t_lift * 0.5, -1.85 * s])
    t_tip = t_root + np.array([t_sway, -1.85 * s + t_lift, -3.45 * s])
    m.limb(t_root, t_mid, 1.95 * s, 1.65 * s, COAT, step=0.38)
    m.limb(t_mid, t_tip, 1.62 * s, 1.38 * s, PALE_TAIL, step=0.36)
    m.ell(t_tip, (1.45 * s, 1.22 * s, 1.35 * s), PALE_TAIL)

    # ---- Thick Neck & Iconic Crisp White Head with Two Bold Black Longitudinal Stripes ----
    head = np.array([math.sin(yaw) * 1.15 * s + sway_x * 0.75, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * s)

    # Muscular neck bridge: silver nape above, jet-black throat underneath
    neck_top = np.array([sway_x * 0.65, front_y + 0.85 * s, 4.3 * s + lunge_z * 0.85])
    skull_back = hp(0.0, 0.35, -1.55)
    m.limb(neck_top, skull_back, 3.05 * bulk * s, 2.45 * s, COAT, step=0.38)
    m.limb(neck_top + np.array([0.0, 1.55 * s, 0.35 * s]), hp(0.0, 1.75, -1.15), 0.98 * s, 0.92 * s, WHITE_MASK, step=0.35)
    m.limb(
        neck_top + np.array([0.0, -1.55 * s, 0.25 * s]),
        hp(0.0, -1.25, -0.65),
        2.35 * bulk * s,
        1.75 * s,
        BLACK_UNDER,
        step=0.38,
    )

    # Conical white cranium + conformal bold black eye-to-ear longitudinal stripes!
    r_skull = np.array([2.58 * s, 2.25 * s, 2.75 * s])
    m.ell(hp(0.0, 0.20, -0.25), r_skull, WHITE_MASK, R=rot)
    m.ell(hp(0.0, 0.20, -0.25), r_skull + 0.05, BLACK_STRIPE, R=rot, clip=_head_stripe_clip)

    # Tapered conical white snout + forward continuation of the two bold black stripes!
    r_snout = np.array([1.60 * s, 1.32 * s, 2.05 * s])
    m.ell(hp(0.0, -0.28, 1.95), r_snout, WHITE_MASK, R=rot)
    m.ell(hp(0.0, -0.28, 1.95), r_snout + 0.05, BLACK_STRIPE, R=rot, clip=_snout_stripe_clip)

    # Crisp white muzzle tip ring & broad wet jet-black badger nose pad
    m.ell(hp(0.0, -0.42, 3.25), (1.14 * s, 0.94 * s, 1.05 * s), WHITE_MASK, R=rot)
    m.ell(hp(0.0, -0.38, 3.98), (max(0.56, 0.72 * s), max(0.48, 0.58 * s), max(0.52, 0.62 * s)), NOSE_EYE, R=rot)

    # Jet-black chin & lower jaw (drops during defensive bark/grunt!)
    drop = 0.85 * jaw_open
    if jaw_open > 0.2:
        m.ell(hp(0.0, -1.02 - drop * 0.45, 2.35), (0.82 * s, 0.46 * s, 1.25 * s), NOSE_EYE, R=rot)
    m.ell(hp(0.0, -1.12 - drop, 2.05), (1.18 * s, 0.62 * s, 1.75 * s), BLACK_UNDER, R=rot)

    # Small rounded low-set badger ears (black base in stripe + CRISP WHITE UPPER RIM!) & sparkling eyes
    blink = (kind == 'idle' and t >= 0.75)
    for side in (-1.0, 1.0):
        R_ear = rot @ rot_z(-side * 0.42)
        m.ell(
            hp(side * 1.82, 1.60, -0.95),
            (max(0.58, 0.76 * s), max(0.75, 0.95 * s), max(0.48, 0.58 * s)),
            BLACK_STRIPE,
            R=R_ear,
        )
        m.ell(
            hp(side * 1.95, 2.18, -0.90),
            (max(0.56, 0.74 * s), max(0.48, 0.62 * s), max(0.46, 0.54 * s)),
            WHITE_MASK,
            R=R_ear,
        )

        # Dark eye nestled inside the black facial stripe + bright pinpoint glint!
        m.ell(
            hp(side * 1.58, 0.32, 1.15),
            (max(0.42, 0.48 * s), max(0.16, (0.18 if blink else 0.48) * s), max(0.42, 0.48 * s)),
            NOSE_EYE,
            R=rot,
        )
        if not blink:
            m.ell(
                hp(side * 1.70, 0.48, 1.32),
                (max(0.20, 0.22 * s), max(0.20, 0.22 * s), max(0.18, 0.20 * s)),
                GLINT,
                R=rot,
            )

    draw_badger_legs(m, t, rear_y, front_y, kind, s, bulk, sway_x, dig_idx, lunge_z)
    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_badger(v, kind, (col - start) / n)
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_badger_den() -> np.ndarray:
    """Render badger_den.png (48x36 px, SS=4): grounded mossy forest earth mound framed by gnarled brown tree roots,
    excavated dirt fan with tiny stones in front, and a deep shadowed arched burrow entrance at (24, 24..30)."""
    den_w, den_h = 48, 36
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = den_w, den_h, 27.0, 4, 1.0
    art.TIDY_EYES = False

    MOUND_EARTH, SPOIL_DIRT, MOSS, MOSS_DEEP, ROOT_WOOD, ARCH_SHADE, BURROW_VOID, STONE = range(8)
    art.DECAL_WEIGHT = {
        BURROW_VOID: 3.6,
        ARCH_SHADE: 1.9,
        STONE: 2.8,
        ROOT_WOOD: 1.85,
        MOSS: 1.45,
        MOSS_DEEP: 1.30,
        SPOIL_DIRT: 1.25,
    }
    art.ink_color = lambda mat: hexc('090810' if mat in (BURROW_VOID, ARCH_SHADE) else '1b151e')
    den_ramps = [
        ['1c1414', '332420', '4e3932', '6c5146'],           # 0 MOUND_EARTH (dark damp woodland loam)
        ['362920', '594535', '82674f', 'ad8d6e'],           # 1 SPOIL_DIRT (warm sandy excavated earth fan)
        ['172c1e', '2b5236', '477c4e', '6da866'],           # 2 MOSS (lush sunlit woodland moss cushion)
        ['102018', '1e3b29', '335c3d', '4f8052'],           # 3 MOSS_DEEP (rich shaded forest moss tufts)
        ['362118', '613e2b', '916142', 'bf8b64'],           # 4 ROOT_WOOD (warm gnarled exposed tree roots!)
        ['100d16', '1c1724', '2d2536', '42374b'],           # 5 ARCH_SHADE (recessed earthen tunnel arch)
        ['04040a', '080710', '0e0d19', '151322'],           # 6 BURROW_VOID (deep shadowed burrow interior)
        ['3a3946', '626172', '908fa2', 'c2c1d0'],           # 7 STONE (crisp woodland pebbles on dirt fan)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in den_ramps]

    m = art.Model()

    # 1. Grounded Earthen Mound Base (set back around z = -3.5..-1.0 so foreground roots & arch have crisp 3D relief!)
    mound_blobs = [
        (0.0, 6.2, -3.2, 16.0, 7.8, 7.2),
        (-8.2, 4.4, -2.0, 10.2, 5.8, 6.0),
        (8.4, 4.5, -1.8, 10.0, 5.9, 6.0),
        (-13.2, 2.4, 0.0, 6.4, 3.4, 4.5),
        (13.0, 2.3, 0.2, 6.4, 3.3, 4.5),
        (0.0, 9.0, -4.6, 12.2, 6.2, 5.8),
    ]
    for cx, cy, cz, rx, ry, rz in mound_blobs:
        m.ell((cx, cy, cz), (rx, ry, rz), MOUND_EARTH)

    # 2. Lush Layered Forest Moss Cap draping organically over mound top & flanks
    moss_blobs = [
        (0.0, 11.4, -4.0, 11.4, 4.2, 5.2, MOSS),
        (-6.8, 9.2, -2.8, 7.8, 3.6, 4.5, MOSS),
        (6.8, 9.0, -2.6, 7.6, 3.6, 4.5, MOSS_DEEP),
        (-12.4, 5.2, -0.8, 5.4, 2.7, 3.8, MOSS_DEEP),
        (12.2, 5.0, -0.6, 5.2, 2.6, 3.8, MOSS),
        (-3.4, 13.2, -4.8, 5.6, 2.5, 3.6, MOSS),
        (3.8, 12.8, -4.6, 5.2, 2.4, 3.5, MOSS_DEEP),
        (-15.5, 1.8, 2.4, 3.2, 1.6, 2.4, MOSS_DEEP),
        (15.2, 1.8, 2.2, 3.2, 1.6, 2.4, MOSS),
    ]
    for cx, cy, cz, rx, ry, rz, mat_m in moss_blobs:
        m.ell((cx, cy, cz), (rx, ry, rz), mat_m)

    # 3. Deep Shadowed Arched Burrow Entrance right at screen (24, 24..30)!
    # With GROUND_ROW = 27.0: (0, 3.3, 3.8) -> cy = 27.0 - (2.97 - 1.66) = 25.7, spanning cy = 21..30, cx = 17..31!
    def _arch_clip(q: np.ndarray) -> np.ndarray:
        return q[..., 1] > -0.72

    m.ell((0.0, 3.6, 2.8), (8.2, 5.6, 2.6), ARCH_SHADE, clip=_arch_clip)
    m.ell((0.0, 3.1, 3.9), (6.5, 4.6, 2.2), BURROW_VOID, clip=_arch_clip)
    m.ell((0.0, 1.9, 4.3), (5.9, 2.7, 2.0), BURROW_VOID, clip=_arch_clip)

    # 4. Prominent Gnarled Brown Tree Roots arching proud in 3D relief (+z) around the burrow mouth!
    # Main overarching root collar & gnarled left branch
    l_root = [
        (-1.8, 9.6, 1.8),
        (-6.2, 8.4, 2.6),
        (-9.0, 5.6, 3.6),
        (-10.6, 2.6, 4.8),
        (-13.8, 1.0, 5.8),
    ]
    for a, b_pt, r0, r1 in zip(l_root[:-1], l_root[1:], (1.65, 1.75, 1.55, 1.25), (1.75, 1.55, 1.25, 0.88)):
        m.limb(a, b_pt, r0, r1, ROOT_WOOD, step=0.32)
    # Inner-left root finger gripping edge of burrow arch
    m.limb((-8.4, 5.8, 3.6), (-7.4, 1.6, 4.8), 1.22, 0.82, ROOT_WOOD, step=0.32)

    # Gnarled right tree root branch
    r_root = [
        (-1.8, 9.6, 1.8),
        (2.8, 9.5, 2.0),
        (6.6, 8.0, 2.8),
        (9.2, 5.2, 3.8),
        (11.0, 2.4, 4.9),
        (14.2, 1.0, 5.8),
    ]
    for a, b_pt, r0, r1 in zip(
        r_root[:-1], r_root[1:], (1.65, 1.68, 1.72, 1.50, 1.22), (1.68, 1.72, 1.50, 1.22, 0.86)
    ):
        m.limb(a, b_pt, r0, r1, ROOT_WOOD, step=0.32)
    # Inner-right root finger gripping edge of burrow arch
    m.limb((8.6, 5.4, 3.8), (7.5, 1.5, 4.9), 1.20, 0.82, ROOT_WOOD, step=0.32)

    # Upper gnarled root knot emerging from moss crown
    m.limb((-4.2, 11.8, -0.4), (-1.8, 9.6, 1.8), 1.35, 1.55, ROOT_WOOD, step=0.32)
    m.limb((4.8, 11.4, -0.2), (2.8, 9.5, 2.0), 1.25, 1.48, ROOT_WOOD, step=0.32)

    # 5. Excavated Dirt Fan (Auswurf) spilling forward from y=29..34 BELOW the dark burrow entrance!
    # At y = -0.3, z = 7.4 -> cy = 27.0 - (-0.27 - 3.24) = 30.5!
    m.ell((0.0, -0.2, 7.0), (11.8, 1.15, 4.2), SPOIL_DIRT)
    m.ell((-5.2, -0.3, 7.8), (7.2, 0.98, 3.2), SPOIL_DIRT)
    m.ell((5.4, -0.3, 7.6), (7.0, 0.98, 3.2), SPOIL_DIRT)

    # 6. Crisp Tiny Stones nestled proudly on top of the excavated dirt fan!
    pebbles = [
        (-8.2, 0.75, 7.8, (1.45, 0.95, 1.20)),
        (-3.8, 0.65, 9.2, (1.18, 0.82, 1.02)),
        (4.4, 0.70, 8.9, (1.35, 0.90, 1.12)),
        (8.8, 0.75, 7.5, (1.25, 0.88, 1.05)),
    ]
    for px_c, py_c, pz_c, pr in pebbles:
        m.ell((px_c, py_c, pz_c), pr, STONE)

    depth, code = art.render(m.transform(0.0, 0.0))
    px = np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)
    setup_badger_art()
    return px


def render_qa(out_path: Path, zoom: int = 3) -> None:
    """Render a crisp 3x nearest-neighbor QA contact sheet showing all 3 badger builds + facings + poses."""
    picks = [
        (0, 0),   # E idle (low wedge, white/black facial stripe, black legs & pale claws)
        (1, 0),   # SE idle (shows iconic 2 black stripes on crisp white head!)
        (2, 0),   # S idle (front view: white blaze + twin black eye-to-ear stripes!)
        (4, 0),   # W idle
        (6, 0),   # N idle (broad silver back + blunt pale-tipped tail + white ear rims)
        (0, 6),   # E forage nose-to-earth worm search
        (1, 12),  # SE rolling plantigrade waddle
        (1, 19),  # SE alert (head raised + inquisitive tilt showing bold mask!)
        (2, 19),  # S alert
        (0, 24),  # E fast low-bellied trot
        (1, 31),  # SE groom flank scratch
        (1, 35),  # SE curled nose-to-tail sleep ball
        (0, 39),  # E special earth-digging reach
        (0, 41),  # E special earth-digging scoop
        (1, 48),  # SE bark bristled defensive lunge!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([44, 53, 47, 255], np.uint8)
    grid[:, :] = bg
    for v in range(BUILDS_N):
        grid[v * H + 52, :] = np.array([60, 72, 62, 255], np.uint8)
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
            den_px = render_badger_den()
            save_png(ROOT / 'assets/wildlife/badger_den.png', den_px)
            print(f'QA sheet written to {out} and badger_den.png ({den_px.shape})')
            return

    if '--preview-only' in sys.argv:
        return

    den_px = render_badger_den()
    save_png(ROOT / 'assets/wildlife/badger_den.png', den_px)
    print('Saved assets/wildlife/badger_den.png', den_px.shape, flush=True)

    sheet = np.zeros((BUILDS_N * 8 * H, COLS * W, 4), np.uint8)
    jobs = [(v, d) for v in range(BUILDS_N) for d in range(8)]
    with ProcessPoolExecutor() as pool:
        for done, (v, d, row_px) in enumerate(pool.map(_render_row, jobs), 1):
            y = (v * 8 + d) * H
            sheet[y:y + H, :] = row_px
            if done % 8 == 0:
                print(f'badger build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/badger.png', sheet)
    print('Saved assets/wildlife/badger.png', sheet.shape)


if __name__ == '__main__':
    main()
