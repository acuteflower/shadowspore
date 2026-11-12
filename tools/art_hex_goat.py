#!/usr/bin/env python3
"""Schwarzer Hexenbock (Hexenwald Folklore Billy Goat) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 4 builds x 8 true facings = 32 rows (3328x2048). No emissive parts.
Builds:
  0: Pechschwarzer Hexenbock (obsidian-charcoal shaggy coat with slate-indigo shadow & cool steel highlight,
     dark iron-horn ridged scimitar horns, bright non-emissive amber-gold eyes)
  1: Aschbleicher Knochenbock (ghostly pale bone-ivory / ash-grey coat matching bleached bone_tree wood,
     dark slate scimitar horns, eerie violet-gold eyes)
  2: Rußgraue Hexenziege (0.93x leaner nanny goat in smoky slate-violet charcoal, shorter curved horns & smaller beard)
  3: Dunkles Zicklein (0.68x juvenile kid anchored on GROUND_ROW=52.0, dark soot-slate coat, tiny horn buds & perked ears)
Columns (52):
  idle 0:4, forage 4:12, walk 12:20, alert 20:24, run 24:32,
  groom 32:36, sleep 36:40, special 40:46 (Aufbäumen rear-up), stand_up 46:52.
Usage: py -3 tools/art_hex_goat.py [--preview-only] [--qa=path.png]
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

COAT, SHAG, TRIM, HOOF_DARK, NOSE_PUPIL, EYE_GOLD, HORN, HORN_RIDGE, INNER_EAR = range(9)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 8),
    ('walk', 12, 8),
    ('alert', 20, 4),
    ('run', 24, 8),
    ('groom', 32, 4),
    ('sleep', 36, 4),
    ('special', 40, 6),
    ('stand_up', 46, 6),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE_GOLD: 4.4,
        NOSE_PUPIL: 3.1,
        HORN_RIDGE: 1.55,
        HORN: 1.35,
        INNER_EAR: 1.65,
        TRIM: 1.15,
    }
    art.ink_color = lambda mat: hexc('0c0914' if mat in (COAT, SHAG, HOOF_DARK, NOSE_PUPIL) else '181324')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def smooth(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def bezier3(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, u: float) -> np.ndarray:
    v = 1.0 - u
    return (v ** 3) * p0 + 3.0 * (v ** 2) * u * p1 + 3.0 * v * (u ** 2) * p2 + (u ** 3) * p3


def materials(v: int) -> None:
    setup_art()
    b = v % BUILDS_N
    if b == 0:
        # 0 Pechschwarzer Hexenbock: deep obsidian-charcoal with slate-indigo shadow & cool steel highlight
        coat = ['11101e', '212236', '3b3e59', '646a8c']
        shag = ['0c0b16', '191a2b', '2f324a', '535878']
        trim = ['191a2b', '2e3048', '4d5170', '787ea0']
        hoof = ['0b0a13', '161525', '2a273d', '47435f']
        eye = ['7d5316', 'bf8622', 'edb83c', 'fbe27a']
        horn = ['151320', '2b273a', '4b4560', '78708e']
        ridge = ['231f32', '403a54', '696080', '9b91b4']
        ear_in = ['2a2135', '473955', '6a5879', '927ea0']
    elif b == 1:
        # 1 Aschbleicher Knochenbock: ghostly bleached bone-ivory / ash-grey matching bone_tree wood
        coat = ['48435c', '79748c', 'b3afbe', 'ece7db']
        shag = ['39344c', '645f78', '9c98a8', 'dad5c8']
        trim = ['59546e', '8c879e', 'c4c0cc', 'f5f1e6']
        hoof = ['191526', '2e2840', '4c4462', '706788']
        eye = ['582e6c', '99603e', 'd8a848', 'f7e28a']
        horn = ['151222', '29243b', '48405e', '72688a']
        ridge = ['231e35', '3f3756', '665b80', '968ab0']
        ear_in = ['4c3c56', '786282', 'a892ae', 'd4c2d6']
    elif b == 2:
        # 2 Rußgraue Hexenziege: smoky slate-violet charcoal nanny goat
        coat = ['1f1a2e', '38304c', '5b4f72', '87799e']
        shag = ['171324', '2c253d', '4a3f60', '726588']
        trim = ['2b243c', '483e5e', '6e6286', '9b8eb2']
        hoof = ['100d19', '1f1a2d', '362e49', '564b6c']
        eye = ['7a5016', 'b88022', 'e8b238', 'f9df76']
        horn = ['181424', '302842', '524668', '7e7096']
        ridge = ['262038', '453b5c', '6e6188', '9e90b8']
        ear_in = ['382a44', '5c466a', '846a92', 'ae94ba']
    else:
        # 3 Dunkles Zicklein: dark soot-slate juvenile kid
        coat = ['1a1928', '2f2e45', '4e4d6b', '787798']
        shag = ['141320', '252438', '3f3e58', '646382']
        trim = ['252438', '3f3e5a', '636282', '8e8dae']
        hoof = ['0e0d18', '1b192b', '312d46', '504a68']
        eye = ['7c5216', 'bc8424', 'ebb63c', 'fae27c']
        horn = ['181624', '2f2b42', '504a66', '7a7392']
        ridge = ['262238', '443e5a', '6c6484', '9b92b2']
        ear_in = ['342840', '564366', '7e668e', 'a68eb4']

    ramps = [
        coat,                                               # 0 COAT
        shag,                                               # 1 SHAG
        trim,                                               # 2 TRIM
        hoof,                                               # 3 HOOF_DARK
        ['090811', '131120', '221e33', '35304a'],           # 4 NOSE_PUPIL
        eye,                                                # 5 EYE_GOLD (non-emissive high-contrast gold)
        horn,                                               # 6 HORN
        ridge,                                              # 7 HORN_RIDGE
        ear_in,                                             # 8 INNER_EAR
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_goat_legs(
    m: art.Model,
    t: float,
    rear_pt: np.ndarray,
    front_pt: np.ndarray,
    kind: str,
    s: float,
    shaggy: float,
    browse_step: float,
    rear_k: float,
    rise_k: float,
) -> None:
    """Sturdy 3-segment mountain-caprid limbs with bony knees/hocks, fetlock shag, and split cloven hooves."""
    for side in (-1.0, 1.0):
        for front in (False, True):
            anchor = front_pt if front else rear_pt
            hip_x = side * (2.35 if front else 2.50) * s
            hip_y = float(anchor[1]) - (0.55 if front else 0.45) * s
            hip_z = float(anchor[2]) + (0.25 if front else -0.25) * s
            r_cannon = max(0.70, 0.88 * s)

            # Bedded folded slate-ledge legs (sleep or early stand_up)
            bed_blend = 1.0 if kind == 'sleep' else (1.0 - rise_k if kind == 'stand_up' else 0.0)
            if bed_blend >= 0.999:
                tuck_side = side * (0.92 if side > 0 else 0.72)
                root = np.array([hip_x * 0.92, hip_y + 0.35 * s, hip_z])
                if front:
                    carpus = np.array([tuck_side * 2.65 * s, 1.95 * s, hip_z + 2.55 * s])
                    hoof = np.array([tuck_side * 1.95 * s, 1.05 * s, hip_z - 1.55 * s])
                    m.limb(root, carpus, r_cannon * 1.55, r_cannon * 1.08, SHAG if shaggy > 0.5 else COAT, step=0.4)
                    m.limb(carpus, hoof, r_cannon * 1.0, r_cannon * 0.82, COAT, step=0.38)
                    m.ell(hoof, (r_cannon * 0.92, 0.68 * s, 1.02 * s), HOOF_DARK)
                else:
                    hock = np.array([tuck_side * 3.05 * s, 2.05 * s, hip_z - 2.15 * s])
                    hoof = np.array([tuck_side * 2.35 * s, 1.05 * s, hip_z + 2.35 * s])
                    m.limb(root, hock, r_cannon * 1.72, r_cannon * 1.12, COAT, step=0.4)
                    m.limb(hock, hoof, r_cannon * 1.02, r_cannon * 0.82, COAT, step=0.38)
                    m.ell(hoof, (r_cannon * 0.92, 0.68 * s, 1.02 * s), HOOF_DARK)
                continue

            # Dramatic Aufbäumen rear-up pose: braced hind legs, prominent forward-hooked forehooves!
            if kind == 'special' and rear_k > 0.08:
                root = np.array([hip_x, hip_y, hip_z])
                if front:
                    # Near leg (-x) lifts slightly higher than far leg (+x) for unmistakable heraldic separation!
                    asym = (-0.65 if side > 0 else 0.75) * rear_k
                    elbow = root + np.array([0.0, (-1.85 + 0.55 * rear_k) * s, (0.35 + 1.85 * rear_k) * s])
                    carpus = elbow + np.array([
                        -side * 0.12 * s,
                        (-1.65 + 2.45 * rear_k + asym * 0.85) * s,
                        (0.85 + 3.35 * rear_k + asym * 0.55) * s,
                    ])
                    hoof_hook = carpus + np.array([
                        -side * 0.18 * s,
                        (-2.95 - 0.35 * rear_k) * s,
                        (0.20 - 1.45 * rear_k) * s,
                    ])
                    hoof_hook[1] = max(0.76 * s, float(hoof_hook[1]))
                    m.limb(root, elbow, r_cannon * 1.82, r_cannon * 1.32, SHAG if shaggy > 0.4 else COAT, step=0.4)
                    m.limb(elbow, carpus, r_cannon * 1.25, r_cannon * 0.98, COAT, step=0.38)
                    m.ell(carpus, (r_cannon * 1.05, r_cannon * 1.00, r_cannon * 1.05), TRIM)
                    m.limb(carpus, hoof_hook, r_cannon * 0.92, r_cannon * 0.78, COAT, step=0.36)
                    R_hoof = art.rot_x(0.95 * rear_k)
                    m.ell(hoof_hook, (r_cannon * 0.96, 0.74 * s, 1.18 * s), HOOF_DARK, R=R_hoof)
                else:
                    # Braced wide mountain-goat hind stance under the reared center of mass
                    foot_z = (-4.8 + 1.35 * rear_k + (-0.65 if side > 0 else 0.75) * rear_k) * s
                    foot = np.array([hip_x * (1.0 + 0.08 * rear_k), 0.76 * s, foot_z])
                    stifle = np.array([hip_x * 1.04, hip_y - 2.6 * s, hip_z + 1.35 * s])
                    hock = np.array([hip_x * 1.02, 0.46 * (hip_y + 0.76 * s), foot_z - 1.75 * s])
                    m.limb(root, stifle, r_cannon * 2.15, r_cannon * 1.48, COAT, step=0.4)
                    m.limb(stifle, hock, r_cannon * 1.40, r_cannon * 1.02, SHAG if shaggy > 0.4 else COAT, step=0.38)
                    m.limb(hock, foot, r_cannon * 0.95, r_cannon * 0.80, COAT, step=0.36)
                    m.ell(foot + np.array([0.0, 0.0, 0.26 * s]), (r_cannon * 0.98, 0.74 * s, 1.18 * s), HOOF_DARK)
                continue

            swing = 0.0
            lift = 0.0
            knee_flex = 0.0

            if kind == 'walk':
                # Sure-footed 4-beat mountain-goat lateral sequence
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.62
                if cyc < stance:
                    c = cyc / stance
                    swing = (2.45 * s) * (1.0 - 2.0 * c)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(2.45 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * (2.55 if front else 2.05) * s
                    knee_flex = math.sin(c * math.pi) * 1.25 * s
            elif kind == 'run':
                # Rocky stiff-legged caprid bound / mountain canter
                lead = 0.09 if side > 0 else -0.09
                cyc = (t + (0.44 if front else 0.0) + lead) % 1.0
                ang = cyc * math.tau
                airborne = max(0.0, math.sin(t * math.pi))
                if front:
                    swing = (4.1 * s) * math.sin(ang - 0.35)
                    lift = max(0.0, airborne * 3.1 * s + max(0.0, math.cos(ang)) * 1.4 * s)
                    knee_flex = max(0.0, -math.sin(ang)) * 1.35 * s
                else:
                    swing = -(4.4 * s) * math.sin(ang - 0.25)
                    lift = max(0.0, airborne * 2.6 * s + max(0.0, -math.cos(ang)) * 1.3 * s)
                    knee_flex = max(0.0, math.cos(ang)) * 1.25 * s
            elif kind == 'forage' and front:
                # Braced wide shrub-browsing foreleg stance
                swing = (1.65 if side > 0 else -0.65) * s * browse_step
            elif kind == 'stand_up':
                if front and rise_k < 0.58:
                    kneel = 1.0 - smooth(rise_k / 0.58)
                    swing = -1.75 * s * kneel
                    knee_flex = 2.15 * s * kneel

            root = np.array([hip_x, hip_y, hip_z])
            foot_y = 0.76 * s + lift
            foot = np.array([hip_x * (0.95 if front else 0.97), foot_y, hip_z + swing])

            if front:
                elbow = np.array([hip_x * 0.97, hip_y - 2.75 * s, hip_z - 0.65 * s + swing * 0.20])
                carpus = np.array([
                    hip_x * 0.96,
                    foot_y + (hip_y - foot_y) * 0.45 + knee_flex * 0.38,
                    hip_z + swing * 0.56 + (0.65 * s if lift > 0.35 else 0.18 * s) + knee_flex * 0.52,
                ])
                # Shaggy upper foreleg breeches + bony carpus knob + sturdy cannon
                m.limb(root, elbow, r_cannon * (1.88 + 0.18 * shaggy), r_cannon * (1.36 + 0.12 * shaggy), SHAG if shaggy > 0.4 else COAT, step=0.4)
                m.limb(elbow, carpus, r_cannon * 1.26, r_cannon * 0.98, COAT, step=0.38)
                m.ell(carpus + np.array([0.0, 0.0, 0.16 * s]), (r_cannon * 1.02, r_cannon * 0.92, r_cannon * 1.02), TRIM)
                m.limb(carpus, foot, r_cannon * 0.92, r_cannon * 0.78, COAT, step=0.36)
            else:
                stifle = np.array([hip_x * 1.03, hip_y - 2.65 * s, hip_z + 1.05 * s + swing * 0.22])
                hock = np.array([
                    hip_x * 0.98,
                    foot_y + (hip_y - foot_y) * 0.46 + knee_flex * 0.35,
                    hip_z + swing * 0.42 - (1.75 * s - knee_flex * 0.35),
                ])
                m.limb(root, stifle, r_cannon * (2.15 + 0.18 * shaggy), r_cannon * 1.48, COAT, step=0.4)
                m.limb(stifle, hock, r_cannon * 1.40, r_cannon * 1.00, SHAG if shaggy > 0.4 else COAT, step=0.38)
                m.ell(hock + np.array([0.0, 0.0, -0.14 * s]), (r_cannon * 1.00, r_cannon * 0.94, r_cannon * 1.04), TRIM)
                m.limb(hock, foot, r_cannon * 0.92, r_cannon * 0.78, COAT, step=0.36)

            # Fetlock tuft & split cloven mountain hoof
            if shaggy > 0.35:
                m.ell(foot + np.array([0.0, 0.65 * s, -0.35 * s]), (r_cannon * 0.88, 0.68 * s, 0.88 * s), SHAG)
            m.ell(foot + np.array([0.0, -0.02 * s, 0.26 * s]), (r_cannon * 0.96, 0.72 * s, 1.16 * s), HOOF_DARK)


def build_goat(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    b_idx = v % BUILDS_N
    billy = b_idx in (0, 1)
    nanny = (b_idx == 2)
    kid = (b_idx == 3)

    s = 1.0 if billy else (0.93 if nanny else 0.68)
    shaggy = 1.0 if billy else (0.55 if nanny else 0.30)
    head_scale = 1.08 if kid else (0.97 if nanny else 1.02)

    p = t * math.tau
    breath = math.sin(p)

    # Billy goats stand sturdy & muscular, slightly higher at the shaggy withers than the croup
    stand_rear_y = 14.1 * s
    stand_front_y = 14.9 * s
    torso_len = 9.8 * s

    rear_y = stand_rear_y
    rear_z = -4.9 * s
    front_y = stand_front_y
    front_z = 4.9 * s

    browse = 0.0
    browse_tug = 0.0
    browse_step = 0.0
    groom = 0.0
    rear_k = 0.0
    rise_k = 1.0
    chew_x = 0.0
    beard_sway = 0.0
    tail_perk = 0.0

    if kind == 'idle':
        idx = int(t * 4) % 4
        rear_y += 0.14 * breath * s
        front_y += 0.18 * breath * s
        # Subtle sideways cud-chew & beard sway
        chew_x = [0.0, 0.32, -0.28, 0.18][idx]
        beard_sway = 0.36 * math.sin(p)
    elif kind == 'forage':
        # Browsing Hexenwald shrubs (Dämmerstrauch / Besenginster) at mid-low height & tugging twigs!
        idx = int(t * 8) % 8
        browse = [0.22, 0.72, 1.0, 0.92, 1.0, 0.86, 0.95, 0.32][idx]
        browse_tug = [0.0, 0.0, 0.25, -0.85, 0.45, -0.95, 0.30, 0.0][idx]
        browse_step = [0.3, 0.8, 1.0, 1.0, 1.0, 1.0, 0.8, 0.3][idx]
        front_y -= 0.75 * browse * s
        front_z += (0.45 * browse + 0.45 * browse_tug) * s
        rear_z += 0.25 * browse_tug * s
        beard_sway = 0.45 * browse_tug
        chew_x = 0.28 * math.sin(p * 2.0)
    elif kind == 'walk':
        bob = 0.26 * math.cos(p * 2.0) * s
        rear_y += bob
        front_y += 0.26 * math.cos(p * 2.0 - 0.55) * s
        beard_sway = 0.38 * math.sin(p)
        tail_perk = 0.12 * math.sin(p * 2.0)
    elif kind == 'alert':
        front_y += 0.45 * s
        rear_y += 0.18 * s
        tail_perk = 0.25
    elif kind == 'run':
        # Stiff-legged rocky caprid bound / mountain canter
        arc = math.sin(t * math.pi)
        pitch_wave = math.sin(p)
        lift_body = 3.1 * arc * s
        rear_y += lift_body - 0.95 * pitch_wave * s
        front_y += lift_body + 1.15 * pitch_wave * s
        beard_sway = 0.28 * math.cos(p)
        tail_perk = 0.35
    elif kind == 'groom':
        groom = [0.32, 0.88, 1.0, 0.48][int(t * 4) % 4]
        front_y -= 0.25 * groom * s
    elif kind == 'sleep':
        rear_y = 5.2 * s
        front_y = 5.6 * s
        rear_y += 0.10 * breath * s
        front_y += 0.12 * breath * s
        chew_x = 0.20 * math.sin(p)
    elif kind == 'special':
        # Aufbäumen: dramatic ~55 deg rear-up onto braced hind legs, horned head cocked down to butt!
        idx = int(t * 6) % 6
        rear_k = [0.22, 0.72, 1.0, 0.98, 0.56, 0.12][idx]
        torso_ang = rear_k * math.radians(55.0)
        rear_y = (14.1 - 2.3 * rear_k) * s
        rear_z = (-4.9 + 1.75 * rear_k) * s
        front_y = rear_y + torso_len * math.sin(torso_ang)
        front_z = rear_z + torso_len * math.cos(torso_ang)
        tail_perk = 0.38 * rear_k
    elif kind == 'stand_up':
        rise_k = smooth((t * 6.0 + 0.5) / 6.0)
        rump_k = smooth(min(1.0, rise_k * 1.24))
        fore_k = smooth(max(0.0, (rise_k - 0.18) / 0.82))
        rear_y = (5.2 + (14.1 - 5.2) * rump_k) * s
        front_y = (5.6 + (14.9 - 5.6) * fore_k) * s

    rear_pt = np.array([0.0, rear_y, rear_z])
    front_pt = np.array([0.0, front_y, front_z])
    torso_vec = front_pt - rear_pt
    spine_slope = math.atan2(float(torso_vec[1]), max(1.0, float(torso_vec[2])))
    R_spine = art.rot_x(-spine_slope)

    # ---- Seamless 9-ellipsoid gnarled caprid torso + withers hump + shaggy cape locks ----
    for i in range(9):
        u = i / 8.0
        arch = math.sin(u * math.pi)
        withers = math.exp(-((u - 0.82) / 0.22) ** 2) * (0.95 if billy else 0.45)
        pt = rear_pt + torso_vec * u + np.array([0.0, (0.28 * arch + withers * 0.55) * s, 0.0])
        rx_r = (3.40 + 0.45 * arch + 0.25 * withers * shaggy) * s
        ry_r = (3.85 + 0.55 * arch + 0.55 * withers) * s
        rz_r = (2.95 + 0.55 * arch) * s
        m.ell(pt, (rx_r, ry_r, rz_r), COAT, R=R_spine)

    # Highlighted dorsal bony spine / withers ridge & lighter flank/belly edge so obsidian volume pops!
    for u_t in (0.22, 0.48, 0.74):
        pt_b = rear_pt + torso_vec * u_t + R_spine @ np.array([0.0, -2.55 * s, 0.0])
        m.ell(pt_b, (2.75 * s, 1.65 * s, 2.75 * s), TRIM, R=R_spine)

    # Shaggy shoulder mantle, dorsal razor-mane & hanging chest/brisket locks (Zotteln)
    if shaggy > 0.35:
        for u_m in (0.58, 0.74, 0.90, 1.02):
            pt_m = rear_pt + torso_vec * min(u_m, 1.0)
            crest = pt_m + R_spine @ np.array([0.0, (3.65 + 0.55 * shaggy) * s, (u_m - 0.8) * 1.4 * s])
            m.ell(crest, (1.45 * s, 1.55 * s, 1.95 * s), SHAG, R=R_spine)
        # Hanging brisket / chest locks
        for side in (-1.0, 0.0, 1.0):
            lock_top = front_pt + R_spine @ np.array([side * 1.45 * s, -1.65 * s, 1.65 * s])
            lock_bot = lock_top + np.array([side * 0.25 * s, -(2.45 + 0.85 * abs(1.0 - abs(side))) * shaggy * s, 0.45 * s])
            m.limb(lock_top, lock_bot, 1.25 * s, 0.52 * s, SHAG, step=0.42)
        # Lateral shaggy shoulder & haunch locks for gnarled feral silhouette
        for side in (-1.0, 1.0):
            for u_l, drop_l in ((0.18, 2.2), (0.82, 2.7), (0.94, 2.4)):
                l_root = rear_pt + torso_vec * u_l + R_spine @ np.array([side * 2.75 * s, -0.85 * s, 0.0])
                l_tip = l_root + np.array([side * 0.42 * s, -drop_l * shaggy * s, -0.25 * s])
                m.limb(l_root, l_tip, 1.15 * s, 0.48 * s, SHAG, step=0.42)

    # Characteristic short upturned goat tail (Bürzel) held jauntily erect at the croup!
    tail_base = rear_pt + R_spine @ np.array([0.0, 1.85 * s, -2.65 * s])
    tail_tip = tail_base + np.array([0.0, (2.65 + tail_perk) * s, (-1.45 + 0.35 * tail_perk) * s])
    m.limb(tail_base, tail_tip, 1.05 * s, 0.58 * s, SHAG if shaggy > 0.4 else COAT, step=0.35)

    # ---- Muscular Caprid Neck & Gnarled Angular Head ----
    hs = s * head_scale
    neck_thick = 1.22 if billy else (0.96 if nanny else 0.92)

    hy = front_y + 8.3 * s
    hz = front_z + 3.6 * s
    hx = 0.0
    pitch = 0.14
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        hy += 0.18 * breath * s
        yaw = 0.07 * math.sin(p)
    elif kind == 'forage':
        # Browsing woody Hexenwald shrubs at mid-low chest/knee height & tugging twigs!
        hy = front_y + (8.3 - 9.4 * browse - 0.8 * browse_tug) * s
        hz = front_z + (3.6 + 4.8 * browse + 1.1 * browse_tug) * s
        pitch = 0.14 + 0.48 * browse - 0.18 * browse_tug
        yaw = 0.22 * browse_tug
        roll = -0.14 * browse_tug
        hx = math.sin(yaw) * 1.2 * s
    elif kind == 'walk':
        hy = front_y + (8.1 - 0.35 * math.sin(p * 2.0)) * s
        hz = front_z + (3.85 + 0.32 * math.cos(p * 2.0)) * s
        pitch = 0.16
    elif kind == 'alert':
        # Eerie unblinking head-turned stare toward near side (-x) — horns separate crisply in silhouette!
        idx = int(t * 4) % 4
        yaw = [-0.48, -0.56, -0.56, -0.50][idx]
        hy = front_y + (9.3 + 0.15 * breath) * s
        hz = front_z + 3.05 * s
        hx = math.sin(yaw) * 1.65 * s
        pitch = 0.06
        roll = 0.06
    elif kind == 'run':
        hy = front_y + (8.2 + 0.65 * math.sin(p)) * s
        hz = front_z + (4.15 + 0.55 * math.cos(p)) * s
        pitch = 0.10 - 0.12 * math.sin(p)
    elif kind == 'groom':
        # Turning head back toward near flank (-x) to scratch shoulder/flank with scimitar horn tip!
        scratch_osc = 0.14 * math.sin(p * 2.0)
        yaw = -(1.42 + scratch_osc) * groom
        hy = front_y + (6.8 - 1.0 * groom) * s
        hz = front_z + (3.2 - 5.4 * groom) * s
        hx = -math.sin(min(-yaw, 1.35)) * 2.35 * groom * s
        pitch = 0.16 + (0.28 + scratch_osc) * groom
        roll = 0.26 * groom
    elif kind == 'sleep':
        # Folded-leg slate-ledge rest, head held upright & watchful!
        hy = front_y + (8.0 - 0.16 * breath) * s
        hz = front_z + 2.65 * s
        pitch = 0.16
        yaw = 0.16 + 0.05 * math.sin(p)
        hx = math.sin(yaw) * 0.8 * s
    elif kind == 'special':
        # Aufbäumen: horned head cocked steeply down to butt while reared up! (Keeps horns >=2px inside 64x64!)
        idx = int(t * 6) % 6
        butt_thrust = 0.45 if idx == 3 else 0.0
        hy = front_y + (8.3 - 3.05 * rear_k - 0.35 * butt_thrust) * s
        hz = front_z + (3.6 + 0.55 * rear_k + 0.85 * butt_thrust) * s
        pitch = 0.14 + 0.68 * rear_k + 0.12 * butt_thrust
        yaw = 0.08 * rear_k if idx == 2 else (-0.06 * rear_k if idx == 3 else 0.0)
    elif kind == 'stand_up':
        hy = front_y + (8.0 + 0.3 * rise_k) * s
        hz = front_z + (2.65 + 0.95 * rise_k) * s
        pitch = 0.22 * (1.0 - rise_k) + 0.14

    head = np.array([hx, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * hs)

    def head_ell(pos: tuple[float, float, float], r: tuple[float, float, float], mat: int, R_extra: np.ndarray | None = None) -> None:
        m.ell(hp(*pos), tuple(a * hs for a in r), mat, R=rot if R_extra is None else rot @ R_extra)

    # Thick muscular caprid neck collar & shaggy throat crest
    neck_base = front_pt + R_spine @ np.array([0.0, 0.95 * s, 1.55 * s])
    throat_top = hp(0.0, -1.15, -1.45)
    neck_mid = 0.52 * neck_base + 0.48 * throat_top + np.array([0.0, -0.35 * (1.0 - browse) * s, -0.30 * s])
    m.ell(neck_base + np.array([0.0, -0.35 * s, -0.35 * s]), (2.65 * neck_thick * s, 2.95 * s, 2.45 * s), SHAG if shaggy > 0.5 else COAT)
    m.limb(neck_base, neck_mid, 2.42 * neck_thick * s, 1.95 * neck_thick * s, COAT, step=0.42)
    m.limb(neck_mid, throat_top, 1.95 * neck_thick * s, 1.52 * hs, COAT, step=0.42)
    if shaggy > 0.45:
        # Shaggy throat ruff along ventral neck
        m.limb(
            neck_base + np.array([0.0, -1.35 * s, 0.85 * s]),
            throat_top + rot @ np.array([0.0, -0.85 * hs, 0.65 * hs]),
            1.35 * s,
            0.85 * hs,
            SHAG,
            step=0.45,
        )

    # Angular bony caprid skull + Roman convex bridge (Ramsnase) + bony cheeks + tapered muzzle
    head_ell((0.0, 0.25, -0.30), (2.15, 2.28, 2.55), COAT)
    # Roman convex nasal bridge catching crisp top-plane highlight
    R_roman = art.rot_x(0.22)
    head_ell((0.0, -0.10, 1.75), (1.38, 1.28, 1.95), TRIM if b_idx == 0 else COAT, R_roman)
    head_ell((0.0, -0.72, 3.18), (1.12, 0.96, 1.22), COAT)
    head_ell((0.0, -0.62, 3.98), (0.82, 0.66, 0.68), HOOF_DARK)
    head_ell((0.0, -0.54, 4.32), (0.58, 0.42, 0.42), NOSE_PUPIL)

    # Angular cheekbones (Jochbein) for gnarled caprid skull silhouette
    for side in (-1.0, 1.0):
        head_ell((side * 1.48, -0.48, 0.85), (0.88, 0.92, 1.45), TRIM if b_idx == 0 else COAT)
        # Bony supraorbital brow ridge framing the golden eye
        head_ell((side * 1.45, 1.02, 0.58), (0.78, 0.52, 0.98), SHAG if billy else COAT)

    # Lower jaw with subtle cud-chew offset
    jaw_x = chew_x * 0.42
    head_ell((jaw_x, -1.32, 2.25), (0.94, 0.58, 1.68), SHAG if billy else COAT)

    # ---- Signature Pointed Chin Beard (Ziegenbart) ----
    beard_len = 5.85 if billy else (3.15 if nanny else 1.35)
    beard_r0 = 1.18 if billy else (0.82 if nanny else 0.54)
    chin_anchor = hp(jaw_x, -1.42, 3.25)
    # Gravity-dominated hang with crisp forward curl under chin so Ziegenbart separates cleanly from throat!
    fwd_world = rot @ np.array([0.0, 0.0, 1.0])
    side_world = rot @ np.array([1.0, 0.0, 0.0])
    b_p1 = chin_anchor + np.array([0.0, -0.38 * beard_len * hs, 0.0]) + fwd_world * (0.18 * beard_len * hs) + side_world * (0.25 * beard_sway * hs)
    b_p2 = chin_anchor + np.array([0.0, -0.76 * beard_len * hs, 0.0]) + fwd_world * (0.38 * beard_len * hs) + side_world * (0.75 * beard_sway * hs)
    b_p3 = chin_anchor + np.array([0.0, -1.00 * beard_len * hs, 0.0]) + fwd_world * (0.64 * beard_len * hs) + side_world * (1.15 * beard_sway * hs)
    n_beard = 6 if billy else 4
    prev_b = chin_anchor
    for bi in range(1, n_beard + 1):
        ub = bi / n_beard
        cur_b = bezier3(chin_anchor, b_p1, b_p2, b_p3, ub)
        rb0 = beard_r0 * (1.0 - 0.72 * ((bi - 1) / n_beard)) * hs
        rb1 = max(0.26, beard_r0 * (1.0 - 0.78 * ub) * hs)
        m.limb(prev_b, cur_b, rb0, rb1, SHAG, step=0.34)
        prev_b = cur_b

    # ---- Ears, Bright Amber-Gold Caprid Eyes, and Backward-Sweeping Ridged Scimitar Horns ----
    blink = (kind == 'idle' and int(t * 4) % 4 == 3)
    for side in (-1.0, 1.0):
        # Narrow pointed caprid ears set outward below horn bases (perked on kid & alert)
        ear_splay = 0.78 if billy else (0.72 if nanny else 0.56)
        ear_fwd = 0.08
        if kind in ('alert', 'special'):
            ear_splay -= 0.16
            ear_fwd = 0.28
        elif kind == 'run':
            ear_splay += 0.14
            ear_fwd = -0.24
        else:
            ear_fwd += 0.10 * math.sin(p + (0.8 if side > 0 else -0.5))
        ear_h = 2.45 if not kid else 2.65
        R_ear = rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        head_ell((side * 1.95, 0.92, -0.95), (0.78, ear_h, 0.52), HOOF_DARK, R_ear)
        head_ell((side * 1.92, 0.88, -0.88), (0.66, ear_h * 0.88, 0.46), COAT, R_ear)
        head_ell((side * 1.90, 0.90, -0.62), (0.40, ear_h * 0.68, 0.24), INNER_EAR, R_ear)

        # High-contrast non-emissive Amber-Gold Caprid Eye + dark socket & horizontal caprid pupil accent!
        head_ell((side * 1.66, 0.40, 0.68), (0.50, 0.66, 0.72), HOOF_DARK)
        if blink:
            head_ell((side * 1.78, 0.40, 0.70), (0.42, 0.18, 0.58), NOSE_PUPIL)
        else:
            head_ell((side * 1.80, 0.40, 0.70), (0.46, 0.56, 0.62), EYE_GOLD)
            # Horizontal rectangular caprid pupil slit across center of gold iris
            head_ell((side * 1.92, 0.38, 0.72), (0.24, 0.16, 0.44), NOSE_PUPIL)

        # Horns: tiny forehead buds on kid (v=3), shorter curved horns on nanny (v=2),
        # massive backward-sweeping ridged scimitar horns on Billy builds (v=0, 1)!
        if kid:
            bud_base = hp(side * 0.82, 1.72, -0.22)
            bud_tip = hp(side * 1.05, 3.35, -0.95)
            m.limb(bud_base, bud_tip, 0.58 * hs, 0.28 * hs, HORN_RIDGE, step=0.28)
        else:
            hlen = 1.0 if b_idx == 0 else (1.03 if b_idx == 1 else 0.56)
            hthick = 1.0 if billy else 0.72
            flare = 1.0 if b_idx == 0 else (1.12 if b_idx == 1 else 0.78)
            h_p0 = hp(side * 0.82, 1.72, -0.25)
            h_p1 = hp(side * (1.28 * flare), 1.72 + 4.85 * hlen, -0.25 + 0.55 * hlen)
            h_p2 = hp(side * (2.15 * flare), 1.72 + 7.45 * hlen, -0.25 - 3.65 * hlen)
            h_p3 = hp(side * (2.68 * flare), 1.72 + 5.15 * hlen, -0.25 - 7.35 * hlen)

            n_seg = 12 if billy else 8
            prev_h = h_p0
            for hi in range(1, n_seg + 1):
                u0 = (hi - 1) / n_seg
                u1 = hi / n_seg
                cur_h = bezier3(h_p0, h_p1, h_p2, h_p3, u1)
                r0 = max(0.32, (1.12 * (1.0 - 0.68 * u0)) * hthick * hs)
                r1 = max(0.30, (1.12 * (1.0 - 0.70 * u1)) * hthick * hs)
                m.limb(prev_h, cur_h, r0, r1, HORN, step=0.30)
                # Gnarled transverse growth rings (Wülste) along the scimitar curve!
                if hi < n_seg and (hi % 2 == 1):
                    r_ring = r1 * 1.14
                    m.ell(cur_h, (r_ring, r_ring * 1.06, r_ring), HORN_RIDGE)
                prev_h = cur_h
            # Sharp weathered horn tip
            m.ell(h_p3, (0.34 * hs, 0.34 * hs, 0.38 * hs), HORN_RIDGE)

    draw_goat_legs(m, t, rear_pt, front_pt, kind, s, shaggy, browse_step, rear_k, rise_k)
    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_goat(v, kind, (col - start) / n)
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_qa(out_path: Path, zoom: int = 3) -> None:
    """Render a crisp nearest-neighbor zoomed QA contact sheet showing all 4 builds, key facings, and key poses."""
    picks = [
        (0, 0),   # E idle
        (1, 0),   # SE idle
        (2, 0),   # S idle
        (4, 0),   # W idle
        (6, 0),   # N idle
        (0, 7),   # E forage shrub tug
        (0, 14),  # E walk
        (1, 21),  # SE alert head-turn stare
        (0, 27),  # E rocky run bound
        (0, 34),  # E groom horn-scratch
        (1, 37),  # SE sleep watchful rest
        (0, 42),  # E special Aufbäumen rear apex
        (6, 42),  # N special Aufbäumen rear apex (top-margin check!)
        (0, 48),  # E stand_up mid-rise
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([38, 44, 52, 255], np.uint8)
    grid[:, :] = bg
    grid[::H, :] = np.array([28, 33, 40, 255], np.uint8)
    grid[:, ::W] = np.array([28, 33, 40, 255], np.uint8)
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
                print(f'hex_goat build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/hex_goat.png', sheet)
    print('Saved assets/wildlife/hex_goat.png', sheet.shape)


if __name__ == '__main__':
    main()
