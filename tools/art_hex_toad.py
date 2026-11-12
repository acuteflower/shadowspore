#!/usr/bin/env python3
"""Große Hexenkröte / Moor-Unke (Hexenwald Folklore Warty Toad) in the 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 3 builds x 8 true facings = 24 rows (3328x1536). No emissive parts.
Builds:
  0: Schiefer-Violett Sporenkröte (dark slate-indigo & deep plum warty back, dusty-lavender belly & vocal sac, copper-gold eyes)
  1: Moos-Kupfer Unke (dark bog-moss olive & tarnished bronze warts, warm amber-marbled belly/throat, gold eyes)
  2: Bleiche Geisterkröte (chalky bone-ivory & pale ash-lilac skin, dark plum eye rim & pale gold iris)
Columns (52):
  idle 0:4, forage 4:10, walk 10:18 (heavy toad hop), alert 18:22 (defensive puff-up on stiffened legs),
  run 22:30 (high-arc escape frog-leap), groom 30:34 (forepaw eye/snout wipe), sleep 34:38 (hunkered flat),
  bark 38:44 (giant inflated Kehlsack vocal sac), special 44:52 (lightning sticky pink-lavender tongue-lash).
Usage: py -3 tools/art_hex_toad.py [--preview-only] [--qa=path.png]
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

SKIN, WART, BELLY, SAC, DARK, PUPIL, EYE_GOLD, GLINT, TONGUE = range(9)

BLOCKS = [
    ('idle', 0, 4),
    ('forage', 4, 6),
    ('walk', 10, 8),
    ('alert', 18, 4),
    ('run', 22, 8),
    ('groom', 30, 4),
    ('sleep', 34, 4),
    ('bark', 38, 6),
    ('special', 44, 8),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE_GOLD: 4.2,
        PUPIL: 3.3,
        GLINT: 4.7,
        TONGUE: 3.2,
        SAC: 1.65,
        WART: 1.60,
        BELLY: 1.20,
    }
    art.ink_color = lambda mat: hexc('110d1c' if mat in (SKIN, DARK, PUPIL) else '1d1528')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def materials(v: int) -> None:
    setup_art()
    b = v % BUILDS_N
    if b == 0:
        # 0 Schiefer-Violett Sporenkröte: slate-indigo & deep plum warts, dusty-lavender belly/sac, copper-gold eyes
        skin = ['18152b', '2d274b', '4b4073', '73649c']
        wart = ['2c1536', '532660', '82418e', 'b268bc']
        belly = ['4e4463', '786a90', 'a899bf', 'd8cee8']
        sac = ['5e4d78', '8e76ab', 'bfa7d8', 'ece0f7']
        dark = ['100d1e', '201a34', '362d52', '524672']
        eye = ['6e3914', 'b06120', 'e49434', 'fbd270']
    elif b == 1:
        # 1 Moos-Kupfer Unke: dark bog-moss olive & tarnished bronze warts, warm amber-marbled belly/throat
        skin = ['18221b', '2c3e2d', '486344', '6f8f63']
        wart = ['3a2316', '694125', '9d6638', 'cd9358']
        belly = ['593716', '925b22', 'ca8834', 'f0b85a']
        sac = ['6b4118', 'a86924', 'de993a', 'f9cf70']
        dark = ['111814', '202d22', '354836', '51694f']
        eye = ['704814', 'b27820', 'e8b038', 'fce27a']
    else:
        # 2 Bleiche Geisterkröte: chalky bone-ivory & pale ash-lilac skin, dark plum eye rim & pale gold iris
        skin = ['49425c', '78708c', 'b0a9be', 'e7e1db']
        wart = ['3f2f4d', '6a507a', '9b7faa', 'cdc0d6']
        belly = ['5a526e', '8a829e', 'bcb6cc', 'ede9f2']
        sac = ['685a82', '9a8ab6', 'cdc0e4', 'f5eefc']
        dark = ['1f102a', '3a1f4a', '5d3670', '86569a']
        eye = ['6b561e', 'aa8c32', 'dfc45a', 'faf09c']

    ramps = [
        skin,                                               # 0 SKIN
        wart,                                               # 1 WART (parotoids & dorsal warts)
        belly,                                              # 2 BELLY
        sac,                                                # 3 SAC (Kehlsack vocal sac)
        dark,                                               # 4 DARK (eye rim, mouth seam, webbing shade)
        ['090711', '131021', '211c34', '332c4a'],           # 5 PUPIL
        eye,                                                # 6 EYE_GOLD (non-emissive gleaming copper-gold)
        ['9e96a8', 'c8c2d0', 'ebe7ee', 'fcfbfd'],           # 7 GLINT
        ['5e2246', '983b6e', 'ce659c', 'f29ec8'],           # 8 TONGUE (sticky pink-lavender tongue)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_webbed_hind_foot(m: art.Model, ankle: np.ndarray, foot: np.ndarray, side: float, pitch_foot: float = 0.0) -> None:
    """Broad webbed amphibian hind foot (tarsus + 3 splayed toes connected by webbed pad)."""
    m.limb(ankle, foot, 0.92, 0.78, SKIN, step=0.35)
    R_f = art.rot_y(side * 0.22) @ art.rot_x(pitch_foot)
    # Webbed sole membrane
    m.ell(foot + R_f @ np.array([side * 0.15, -0.05, 0.95]), (1.35, 0.46, 1.45), DARK, R=R_f)
    for ti, ang in enumerate((-0.36, 0.02, 0.38)):
        toe_len = (1.85 if ti == 1 else 1.55)
        toe_tip = foot + R_f @ np.array([math.sin(ang) * toe_len + side * 0.12, -0.06, math.cos(ang) * toe_len + 0.35])
        m.limb(foot, toe_tip, 0.44, 0.30, SKIN, step=0.32)
        m.ell(toe_tip, (0.34, 0.28, 0.38), WART)


def draw_forepaw(m: art.Model, wrist: np.ndarray, side: float, lift_rot: float = 0.0) -> None:
    """Sturdy inward-turned pigeon-toed toad forepaw."""
    R_p = art.rot_y(-side * 0.44) @ art.rot_x(lift_rot)
    m.ell(wrist + R_p @ np.array([0.0, -0.04, 0.38]), (0.98, 0.50, 1.05), SKIN, R=R_p)
    for ang in (-0.42, -0.05, 0.32):
        tip = wrist + R_p @ np.array([math.sin(ang) * 1.15, -0.06, math.cos(ang) * 1.18 + 0.20])
        m.limb(wrist, tip, 0.38, 0.26, BELLY, step=0.30)


def build_toad(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    p = t * math.tau
    breath = math.sin(p)

    # Squat wide ~18px body footprint (rump ~ -4.15, chest ~ +1.55, snout to ~ +7.9; ZERO tail!)
    rump_y, rump_z = 3.15, -4.15
    chest_y, chest_z = 5.45, 1.55
    head_y, head_z = 6.85, 3.95
    head_pitch = -0.06
    head_yaw = 0.0
    head_roll = 0.0

    puff_x, puff_y, puff_z = 1.0, 1.0, 1.0
    throat_pulse = 0.0
    sac_inflate = 0.0
    jaw_open = 0.0
    tongue_ext = 0.0
    tongue_curl = 0.0
    eye_sink = 0.0
    blink_L = False
    blink_R = False
    hooded = False

    # Default muscular Z-folded hind limbs & bowed inward-turned forelegs planted at GROUND_ROW=52
    knee_L = np.array([-6.15, 2.85, -1.05])
    knee_R = np.array([6.15, 2.85, -1.05])
    heel_L = np.array([-5.45, 1.45, -5.25])
    heel_R = np.array([5.45, 1.45, -5.25])
    hfoot_L = np.array([-5.75, 0.62, -2.15])
    hfoot_R = np.array([5.75, 0.62, -2.15])
    hfoot_pitch = 0.0

    elbow_L = np.array([-5.05, 2.75, 2.35])
    elbow_R = np.array([5.05, 2.75, 2.35])
    fpaw_L = np.array([-3.35, 0.60, 4.85])
    fpaw_R = np.array([3.35, 0.60, 4.85])
    fpaw_rot_L = 0.0

    if kind == 'idle':
        # Stone-still squat crouch, subtle amphibian buccal throat pulse
        idx = int(t * 4) % 4
        throat_pulse = [0.15, 0.65, 1.0, 0.45][idx]
        chest_y += 0.08 * breath
        head_y += 0.08 * breath

    elif kind == 'forage':
        # Predatory weight-shift & head-aiming tilt eyeing bog insects
        idx = int(t * 6) % 6
        shift_z = [0.25, 0.85, 1.15, 1.10, 0.75, 0.20][idx]
        aim_yaw = [0.0, 0.22, 0.28, -0.24, -0.18, 0.0][idx]
        aim_pitch = [0.04, 0.16, 0.24, 0.22, 0.14, 0.02][idx]
        rump_z += 0.45 * shift_z
        chest_z += 0.65 * shift_z
        chest_y -= 0.25 * shift_z
        head_z += 0.85 * shift_z
        head_y -= 0.35 * shift_z
        head_yaw = aim_yaw
        head_pitch = -0.06 + aim_pitch
        head_roll = -0.16 * aim_yaw
        throat_pulse = 0.55 if idx in (2, 4) else 0.2
        if idx in (1, 2, 3):
            fpaw_R = np.array([3.25, 0.60, 5.55])

    elif kind == 'walk':
        # Full 8-frame heavy toad hop cycle: deep crouch -> powerful hind-leg extension -> airborne stretch -> tucked heavy landing
        idx = int(t * 8) % 8
        if idx == 0:  # Deep launch crouch
            rump_y, rump_z = 2.45, -4.65
            chest_y, chest_z = 4.65, 1.45
            head_y, head_z = 6.15, 3.95
            head_pitch = -0.14
            knee_L, knee_R = np.array([-6.45, 2.45, -0.85]), np.array([6.45, 2.45, -0.85])
        elif idx == 1:  # Powerful hind-leg extension push-off
            rump_y, rump_z = 4.55, -3.15
            chest_y, chest_z = 7.55, 2.55
            head_y, head_z = 9.25, 4.95
            head_pitch = -0.22
            knee_L, knee_R = np.array([-4.85, 3.35, -6.85]), np.array([4.85, 3.35, -6.85])
            heel_L, heel_R = np.array([-4.35, 1.85, -10.15]), np.array([4.35, 1.85, -10.15])
            hfoot_L, hfoot_R = np.array([-4.55, 0.75, -11.85]), np.array([4.55, 0.75, -11.85])
            hfoot_pitch = 0.55
            elbow_L, elbow_R = np.array([-4.65, 5.15, 3.95]), np.array([4.65, 5.15, 3.95])
            fpaw_L, fpaw_R = np.array([-3.25, 3.25, 6.35]), np.array([3.25, 3.25, 6.35])
        elif idx == 2:  # Rising airborne stretch
            rump_y, rump_z = 6.45, -2.85
            chest_y, chest_z = 8.55, 2.95
            head_y, head_z = 9.95, 5.45
            head_pitch = -0.08
            knee_L, knee_R = np.array([-4.35, 5.05, -7.45]), np.array([4.35, 5.05, -7.45])
            heel_L, heel_R = np.array([-3.95, 3.85, -11.15]), np.array([3.95, 3.85, -11.15])
            hfoot_L, hfoot_R = np.array([-4.15, 2.95, -13.45]), np.array([4.15, 2.95, -13.45])
            hfoot_pitch = 0.85
            elbow_L, elbow_R = np.array([-4.55, 6.35, 4.55]), np.array([4.55, 6.35, 4.55])
            fpaw_L, fpaw_R = np.array([-3.15, 4.85, 7.15]), np.array([3.15, 4.85, 7.15])
        elif idx == 3:  # Hop apex (leveling heavy body, legs starting to gather)
            rump_y, rump_z = 7.35, -3.05
            chest_y, chest_z = 8.25, 2.85
            head_y, head_z = 9.45, 5.45
            head_pitch = 0.06
            knee_L, knee_R = np.array([-5.15, 5.85, -5.25]), np.array([5.15, 5.85, -5.25])
            heel_L, heel_R = np.array([-4.65, 4.65, -8.85]), np.array([4.65, 4.65, -8.85])
            hfoot_L, hfoot_R = np.array([-4.85, 3.85, -10.25]), np.array([4.85, 3.85, -10.25])
            hfoot_pitch = 0.55
            elbow_L, elbow_R = np.array([-4.75, 5.85, 4.45]), np.array([4.75, 5.85, 4.45])
            fpaw_L, fpaw_R = np.array([-3.25, 3.95, 6.95]), np.array([3.25, 3.95, 6.95])
        elif idx == 4:  # Descent reach (pitched nose-down toward ground)
            rump_y, rump_z = 6.25, -3.35
            chest_y, chest_z = 6.15, 2.55
            head_y, head_z = 7.35, 5.15
            head_pitch = 0.18
            knee_L, knee_R = np.array([-5.85, 4.75, -2.55]), np.array([5.85, 4.75, -2.55])
            heel_L, heel_R = np.array([-5.25, 3.35, -6.15]), np.array([5.25, 3.35, -6.15])
            hfoot_L, hfoot_R = np.array([-5.55, 2.35, -3.65]), np.array([5.55, 2.35, -3.65])
            elbow_L, elbow_R = np.array([-4.85, 3.65, 3.65]), np.array([4.85, 3.65, 3.65])
            fpaw_L, fpaw_R = np.array([-3.35, 1.35, 5.95]), np.array([3.35, 1.35, 5.95])
        elif idx == 5:  # Forepaw touchdown, hindlegs folding forward
            rump_y, rump_z = 4.55, -3.75
            chest_y, chest_z = 4.65, 2.05
            head_y, head_z = 6.05, 4.65
            head_pitch = 0.10
            knee_L, knee_R = np.array([-6.25, 3.45, -1.25]), np.array([6.25, 3.45, -1.25])
            heel_L, heel_R = np.array([-5.55, 1.95, -5.05]), np.array([5.55, 1.95, -5.05])
            hfoot_L, hfoot_R = np.array([-5.75, 0.95, -1.95]), np.array([5.75, 0.95, -1.95])
            fpaw_L, fpaw_R = np.array([-3.45, 0.60, 5.25]), np.array([3.45, 0.60, 5.25])
        elif idx == 6:  # Heavy belly-thud squash landing!
            rump_y, rump_z = 2.55, -4.25
            chest_y, chest_z = 4.45, 1.75
            head_y, head_z = 5.95, 4.25
            puff_x, puff_y, puff_z = 1.10, 0.88, 1.04
            knee_L, knee_R = np.array([-6.55, 2.45, -0.95]), np.array([6.55, 2.45, -0.95])
        else:  # 7 Recover to squat stance
            rump_y, rump_z = 3.05, -4.35
            chest_y, chest_z = 5.25, 1.65
            head_y, head_z = 6.70, 4.15

    elif kind == 'alert':
        # Classic toad defensive puff-up (Abwehrblähen): inflated round & raised HIGH off ground on stiffened four legs!
        idx = int(t * 4) % 4
        puff = [0.78, 1.0, 1.0, 0.88][idx]
        puff_x = 1.0 + 0.28 * puff
        puff_y = 1.0 + 0.34 * puff
        puff_z = 1.0 + 0.14 * puff
        rump_y = 3.15 + 4.25 * puff
        rump_z = -4.15
        chest_y = 5.45 + 3.45 * puff
        chest_z = 1.55
        # Head tucked defensively slightly down to display swollen poison parotoid glands!
        head_y = chest_y + 0.85
        head_z = chest_z + 2.35
        head_pitch = 0.22 * puff
        throat_pulse = 0.65 * puff
        # Four stiffened pillar-like legs lifting belly clearly above ground!
        knee_L, knee_R = np.array([-5.35, 4.85, -3.05]), np.array([5.35, 4.85, -3.05])
        heel_L, heel_R = np.array([-5.05, 2.55, -4.55]), np.array([5.05, 2.55, -4.55])
        hfoot_L, hfoot_R = np.array([-5.15, 0.62, -3.25]), np.array([5.15, 0.62, -3.25])
        elbow_L, elbow_R = np.array([-4.55, 4.85, 2.35]), np.array([4.55, 4.85, 2.35])
        fpaw_L, fpaw_R = np.array([-3.65, 0.60, 3.85]), np.array([3.65, 0.60, 3.85])

    elif kind == 'run':
        # Long high-arc escape frog-leap!
        idx = int(t * 8) % 8
        if idx == 0:  # Deep coiled spring
            rump_y, rump_z = 2.35, -4.75
            chest_y, chest_z = 4.55, 1.35
            head_y, head_z = 6.15, 3.85
            head_pitch = -0.18
            knee_L, knee_R = np.array([-6.65, 2.35, -0.75]), np.array([6.65, 2.35, -0.75])
        elif idx == 1:  # Explosive 40-deg launch!
            rump_y, rump_z = 5.45, -2.85
            chest_y, chest_z = 9.25, 2.75
            head_y, head_z = 11.15, 5.05
            head_pitch = -0.32
            knee_L, knee_R = np.array([-4.55, 3.85, -7.25]), np.array([4.55, 3.85, -7.25])
            heel_L, heel_R = np.array([-4.05, 2.05, -11.25]), np.array([4.05, 2.05, -11.25])
            hfoot_L, hfoot_R = np.array([-4.25, 0.85, -13.45]), np.array([4.25, 0.85, -13.45])
            hfoot_pitch = 0.75
            elbow_L, elbow_R = np.array([-4.45, 7.15, 4.55]), np.array([4.45, 7.15, 4.55])
            fpaw_L, fpaw_R = np.array([-3.05, 5.65, 7.35]), np.array([3.05, 5.65, 7.35])
        elif idx == 2:  # High streamlined ascending flight
            rump_y, rump_z = 9.45, -2.55
            chest_y, chest_z = 12.15, 3.25
            head_y, head_z = 13.55, 5.75
            head_pitch = -0.14
            knee_L, knee_R = np.array([-3.95, 7.65, -7.85]), np.array([3.95, 7.65, -7.85])
            heel_L, heel_R = np.array([-3.55, 6.25, -12.15]), np.array([3.55, 6.25, -12.15])
            hfoot_L, hfoot_R = np.array([-3.75, 5.15, -15.05]), np.array([3.75, 5.15, -15.05])
            hfoot_pitch = 0.95
            elbow_L, elbow_R = np.array([-4.25, 9.85, 5.15]), np.array([4.25, 9.85, 5.15])
            fpaw_L, fpaw_R = np.array([-2.85, 8.65, 8.15]), np.array([2.85, 8.65, 8.15])
        elif idx == 3:  # Grand frog-leap apex!
            rump_y, rump_z = 11.65, -2.75
            chest_y, chest_z = 12.45, 3.25
            head_y, head_z = 13.55, 5.95
            head_pitch = 0.04
            knee_L, knee_R = np.array([-4.15, 10.25, -7.65]), np.array([4.15, 10.25, -7.65])
            heel_L, heel_R = np.array([-3.75, 9.15, -11.95]), np.array([3.75, 9.15, -11.95])
            hfoot_L, hfoot_R = np.array([-3.95, 8.25, -14.85]), np.array([3.95, 8.25, -14.85])
            hfoot_pitch = 0.90
            elbow_L, elbow_R = np.array([-4.45, 9.95, 5.25]), np.array([4.45, 9.95, 5.25])
            fpaw_L, fpaw_R = np.array([-3.05, 8.15, 8.25]), np.array([3.05, 8.15, 8.25])
        elif idx == 4:  # Diving arc forward
            rump_y, rump_z = 10.35, -3.05
            chest_y, chest_z = 9.45, 2.95
            head_y, head_z = 10.25, 5.65
            head_pitch = 0.24
            knee_L, knee_R = np.array([-5.25, 8.95, -5.25]), np.array([5.25, 8.95, -5.25])
            heel_L, heel_R = np.array([-4.65, 7.65, -9.05]), np.array([4.65, 7.65, -9.05])
            hfoot_L, hfoot_R = np.array([-4.85, 6.85, -10.55]), np.array([4.85, 6.85, -10.55])
            hfoot_pitch = 0.55
            elbow_L, elbow_R = np.array([-4.65, 6.45, 4.65]), np.array([4.65, 6.45, 4.65])
            fpaw_L, fpaw_R = np.array([-3.15, 3.85, 7.25]), np.array([3.15, 3.85, 7.25])
        elif idx == 5:  # Low diving reach just before touchdown
            rump_y, rump_z = 6.85, -3.45
            chest_y, chest_z = 5.65, 2.35
            head_y, head_z = 6.75, 5.05
            head_pitch = 0.22
            knee_L, knee_R = np.array([-6.05, 5.05, -2.15]), np.array([6.05, 5.05, -2.15])
            heel_L, heel_R = np.array([-5.35, 3.45, -5.85]), np.array([5.35, 3.45, -5.85])
            hfoot_L, hfoot_R = np.array([-5.65, 2.25, -3.15]), np.array([5.65, 2.25, -3.15])
            elbow_L, elbow_R = np.array([-4.85, 3.15, 3.65]), np.array([4.85, 3.15, 3.65])
            fpaw_L, fpaw_R = np.array([-3.35, 0.95, 5.85]), np.array([3.35, 0.95, 5.85])
        elif idx == 6:  # Heavy skid/squash touchdown
            rump_y, rump_z = 2.65, -4.15
            chest_y, chest_z = 4.35, 1.85
            head_y, head_z = 5.85, 4.35
            puff_x, puff_y = 1.12, 0.86
            knee_L, knee_R = np.array([-6.55, 2.45, -0.85]), np.array([6.55, 2.45, -0.85])
        else:  # 7 Rapid gather for next leap
            rump_y, rump_z = 2.85, -4.45
            chest_y, chest_z = 4.95, 1.55
            head_y, head_z = 6.45, 4.05

    elif kind == 'groom':
        # Classic amphibian forepaw wipe over near-side (-x) eye/snout!
        idx = int(t * 4) % 4
        if idx == 0:
            head_roll = 0.10
            elbow_L = np.array([-5.45, 4.85, 2.85])
            fpaw_L = np.array([-4.15, 5.15, 5.25])
            fpaw_rot_L = -0.65
        elif idx == 1:
            # Paw raised high over near-side gleaming eye & parotoid gland!
            head_roll = 0.18
            head_pitch = 0.06
            blink_L = True
            elbow_L = np.array([-5.65, 7.05, 2.95])
            fpaw_L = np.array([-3.15, 9.15, 4.95])
            fpaw_rot_L = -0.95
        elif idx == 2:
            # Wiping down across closed eye & snout!
            head_roll = 0.14
            head_pitch = 0.14
            blink_L = True
            elbow_L = np.array([-5.35, 5.65, 3.65])
            fpaw_L = np.array([-2.25, 6.75, 7.05])
            fpaw_rot_L = -0.55
        else:
            elbow_L = np.array([-5.15, 3.35, 2.65])
            fpaw_L = np.array([-3.45, 1.15, 5.05])

    elif kind == 'sleep':
        # Hunkered flat into moss, limbs tucked tight, eyes half-hooded
        rump_y, rump_z = 2.25, -4.25
        chest_y, chest_z = 3.55 + 0.06 * breath, 1.45
        head_y, head_z = 4.65 + 0.06 * breath, 3.95
        head_pitch = 0.12
        puff_x, puff_y = 1.08, 0.82
        hooded = True
        knee_L, knee_R = np.array([-5.65, 2.05, -1.35]), np.array([5.65, 2.05, -1.35])
        heel_L, heel_R = np.array([-5.05, 1.15, -4.85]), np.array([5.05, 1.15, -4.85])
        hfoot_L, hfoot_R = np.array([-5.25, 0.58, -2.25]), np.array([5.25, 0.58, -2.25])
        elbow_L, elbow_R = np.array([-4.55, 1.85, 2.15]), np.array([4.55, 1.85, 2.15])
        fpaw_L, fpaw_R = np.array([-3.05, 0.58, 4.25]), np.array([3.05, 0.58, 4.25])

    elif kind == 'bark':
        # Giant round inflated vocal sac (Kehlsack) swelling prominently under chin/throat for deep Unkenruf!
        idx = int(t * 6) % 6
        sac_inflate = [0.28, 0.78, 1.0, 0.94, 0.58, 0.16][idx]
        # Toad raises chest & tilts head back slightly to give room for giant gleaming Kehlsack!
        chest_y = 5.45 + 1.35 * sac_inflate
        head_y = 6.85 + 1.75 * sac_inflate
        head_z = 4.15 - 0.35 * sac_inflate
        head_pitch = -0.06 - 0.24 * sac_inflate
        # Flanks compress slightly as air pumps from lungs into vocal sac
        puff_x = 1.0 + (0.14 if idx == 0 else -0.06 * sac_inflate)

    elif kind == 'special':
        # Lightning sticky pink-lavender tongue-lash (8 frames: 44..51)!
        idx = int(t * 8) % 8
        if idx == 0:  # Predatory coil & jaw crack
            chest_z += 0.35
            head_z += 0.45
            head_pitch = -0.02
            jaw_open = 0.22
        elif idx == 1:  # Mouth snaps WIDE open, sticky tongue launches!
            chest_y, chest_z = 5.75, 2.35
            head_y, head_z = 7.25, 4.95
            head_pitch = -0.20
            jaw_open = 0.92
            tongue_ext = 0.58
        elif idx == 2:  # FULL LIGHTNING EXTENSION (+z) with bulbous sticky tip!
            rump_z = -3.85
            chest_y, chest_z = 5.85, 2.75
            head_y, head_z = 7.35, 5.45
            head_pitch = -0.24
            jaw_open = 1.0
            tongue_ext = 1.0
        elif idx == 3:  # Sticky impact flare & snap-back start
            rump_z = -3.95
            chest_y, chest_z = 5.75, 2.55
            head_y, head_z = 7.25, 5.15
            head_pitch = -0.18
            jaw_open = 0.95
            tongue_ext = 0.72
            tongue_curl = 1.0
        elif idx == 4:  # Rapid snap retraction into jaws
            chest_y, chest_z = 5.55, 1.95
            head_y, head_z = 6.95, 4.45
            head_pitch = -0.10
            jaw_open = 0.68
            tongue_ext = 0.30
        elif idx == 5:  # Authentic amphibian eyeball-retraction swallow!
            chest_y, chest_z = 5.35, 1.55
            head_y, head_z = 6.65, 4.05
            head_pitch = 0.08
            eye_sink = 1.0
            blink_L = blink_R = True
            throat_pulse = 1.35
        elif idx == 6:  # Gulp settle, gleaming eyes pop back up!
            throat_pulse = 0.75
        else:  # 7 Calm crouch
            throat_pulse = 0.20

    # ---- Squat Wide Tailless Toad Body (5 overlapping ellipsoids + pale marbled belly) ----
    rump_pt = np.array([0.0, rump_y, rump_z])
    chest_pt = np.array([0.0, chest_y, chest_z])
    body_vec = chest_pt - rump_pt
    body_slope = math.atan2(float(body_vec[1]), max(1.0, float(body_vec[2])))
    R_body = art.rot_x(-body_slope)

    for i in range(6):
        u = i / 5.0
        bulge = math.sin(u * math.pi)
        pt = rump_pt + body_vec * u
        rx = (3.45 + 1.55 * bulge) * puff_x
        ry = (2.45 + 1.15 * bulge) * puff_y
        rz = (2.85 + 0.55 * bulge) * puff_z
        m.ell(pt, (rx, ry, rz), SKIN, R=R_body)

    # Rounded urostyle sacral hump (ZERO tail!)
    m.ell(rump_pt + R_body @ np.array([0.0, 0.55 * puff_y, -0.85]), (2.65 * puff_x, 1.85 * puff_y, 2.35 * puff_z), SKIN, R=R_body)

    # Pale lavender / amber-marbled belly under flanks
    for u_b in (0.22, 0.52, 0.82):
        pt_b = rump_pt + body_vec * u_b + R_body @ np.array([0.0, -1.25 * puff_y, 0.35])
        m.ell(pt_b, (4.05 * puff_x, 1.75 * puff_y, 2.75 * puff_z), BELLY, R=R_body)

    # ---- Distinct Bumpy Dorsal & Flank Warts (Warzen) ----
    wart_specs = [
        (0.18, 1.45, 2.15, 0.88),
        (0.32, 2.75, 1.95, 0.95),
        (0.46, 1.35, 2.95, 1.05),
        (0.58, 3.35, 1.75, 0.92),
        (0.72, 1.65, 2.85, 1.02),
        (0.84, 3.05, 1.85, 0.86),
    ]
    for u_w, wx, wy, wr in wart_specs:
        base_w = rump_pt + body_vec * u_w
        for side in (-1.0, 1.0):
            z_j = 0.25 if side > 0 else -0.22
            w_pt = base_w + R_body @ np.array([side * wx * puff_x, wy * puff_y, z_j])
            m.ell(w_pt, (wr * 0.95, wr * 0.78, wr * 1.08), WART, R=R_body)

    # ---- Broad Rounded Amphibian Skull, Parotoid Poison Glands, Bulging Copper-Gold Eyes & Vocal Sac ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([0.0, head_y, head_z])

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ np.array([x, y, z])

    # Broad rounded cranium & blunt frog/toad upper jaw
    m.ell(hp(0.0, 0.25, -0.25), (4.25, 2.25, 3.35), SKIN, R=h_rot)
    m.ell(hp(0.0, -0.15, 1.45), (3.85, 1.75, 2.75), SKIN, R=h_rot)
    # Wide dark grumpy mouth seam along upper lip
    m.ell(hp(0.0, -0.72, 1.75), (3.92, 0.58, 2.65), DARK, R=h_rot)
    # Nostril bosses near blunt snout tip
    for side in (-1.0, 1.0):
        m.ell(hp(side * 1.15, 0.38, 3.55), (0.48, 0.42, 0.48), DARK, R=h_rot)

    # Articulated wide lower jaw (drops open during tongue-lash!)
    j_rot = h_rot @ art.rot_x(0.68 * jaw_open)
    jaw_pivot = hp(0.0, -0.78, -0.35)
    m.ell(jaw_pivot + j_rot @ np.array([0.0, -0.35, 1.95]), (3.65, 0.95, 2.75), BELLY, R=j_rot)
    if jaw_open > 0.15:
        # Fleshy pink-lavender inner mouth floor & upper palate cavity
        m.ell(jaw_pivot + j_rot @ np.array([0.0, 0.08, 1.85]), (2.95, 0.58, 2.25), TONGUE, R=j_rot)
        m.ell(hp(0.0, -0.58, 1.55), (2.95, 0.55, 2.15), PUPIL, R=h_rot)

    # Subtle buccal throat pulse OR Giant Round Inflated Vocal Sac (Kehlsack) in bark!
    if sac_inflate > 0.05:
        sac_r_x = 2.45 + 2.55 * sac_inflate
        sac_r_y = 1.65 + 2.75 * sac_inflate
        sac_r_z = 2.35 + 2.55 * sac_inflate
        sac_c = hp(0.0, -1.55 - 1.35 * sac_inflate, 1.55 + 1.25 * sac_inflate)
        m.ell(sac_c, (sac_r_x, sac_r_y, sac_r_z), SAC)
    else:
        pulse_r = 0.55 * throat_pulse
        m.ell(hp(0.0, -1.25 - 0.35 * throat_pulse, 1.35), (2.75 + pulse_r * 0.5, 0.95 + pulse_r, 2.25 + pulse_r * 0.5), BELLY, R=h_rot)

    # Lightning Sticky Pink-Lavender Tongue-Lash (+z) with prominent bulbous clubbed tip!
    if tongue_ext > 0.05:
        t_root = jaw_pivot + j_rot @ np.array([0.0, 0.25, 2.15])
        reach_z = 4.4 + 15.8 * tongue_ext
        t_tip = head_c + np.array([0.0, -0.32 - 0.32 * tongue_ext, reach_z])
        t_mid = 0.5 * (t_root + t_tip) + np.array([0.0, 0.35 * tongue_curl, 0.0])
        m.limb(t_root, t_mid, 0.72, 0.56, TONGUE, step=0.35)
        m.limb(t_mid, t_tip, 0.56, 0.64, TONGUE, step=0.35)
        # Bulbous sticky insect-catching tongue pad at the tip + wet specular highlight!
        tip_rx = 1.48 + 0.28 * tongue_curl
        tip_ry = 1.38 + 0.30 * tongue_curl
        m.ell(t_tip, (tip_rx, tip_ry, 1.72), TONGUE)
        m.ell(t_tip + np.array([-0.25, 0.58, 0.35]), (0.36, 0.34, 0.42), GLINT)

    # Prominent Raised Parotoid Poison Glands & Large Gleaming Copper-Gold Amphibian Eyes
    for side in (-1.0, 1.0):
        # Swollen kidney-shaped parotoid poison gland directly behind each eye!
        R_par = h_rot @ art.rot_y(side * 0.24) @ rot_z(-side * 0.14)
        m.ell(hp(side * 3.05, 1.15, -1.75), (1.36, 1.08, 2.25), WART, R=R_par)
        # Secondary warty ridge bead on parotoid
        m.ell(hp(side * 3.22, 1.48, -1.65), (0.68, 0.58, 1.15), WART, R=R_par)

        # Bulging dorsal-lateral eye turret (retracts down during swallow!)
        ey_off = -0.85 * eye_sink
        is_blink = (blink_L if side < 0 else blink_R)
        # Warty supraorbital brow dome & dark plum/moss eye socket rim
        m.ell(hp(side * 2.38, 1.85 + ey_off, 0.92), (1.15, 1.18, 1.32), DARK, R=h_rot)
        m.ell(hp(side * 2.15, 2.28 + ey_off, 0.88), (0.98, 0.62, 1.25), SKIN, R=h_rot)
        if is_blink:
            m.ell(hp(side * 2.68, 1.75 + ey_off, 0.96), (0.78, 0.36, 1.05), SKIN, R=h_rot)
            m.ell(hp(side * 2.78, 1.72 + ey_off, 0.98), (0.62, 0.18, 0.92), DARK, R=h_rot)
        elif hooded:
            # Half-hooded resting amphibian eye
            m.ell(hp(side * 2.68, 1.72, 0.98), (0.78, 0.68, 1.02), EYE_GOLD, R=h_rot)
            m.ell(hp(side * 2.65, 2.08, 0.96), (0.85, 0.52, 1.08), SKIN, R=h_rot)
            m.ell(hp(side * 2.86, 1.66, 1.02), (0.38, 0.18, 0.72), PUPIL, R=h_rot)
        else:
            # Large gleaming copper-gold amphibian iris + horizontal slit pupil + crisp glint!
            m.ell(hp(side * 2.68, 1.82 + ey_off, 0.98), (0.88, 1.04, 1.12), EYE_GOLD, R=h_rot)
            m.ell(hp(side * 2.94, 1.80 + ey_off, 1.02), (0.42, 0.24, 0.78), PUPIL, R=h_rot)
            m.ell(hp(side * 2.88, 2.22 + ey_off, 1.34), (0.30, 0.32, 0.30), GLINT, R=h_rot)

    # ---- Muscular Z-Folded Hind Legs & Sturdy Inward-Turned Forelegs ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        kn = knee_L if s_idx == 0 else knee_R
        hl = heel_L if s_idx == 0 else heel_R
        hf = hfoot_L if s_idx == 0 else hfoot_R
        el = elbow_L if s_idx == 0 else elbow_R
        fp = fpaw_L if s_idx == 0 else fpaw_R

        # Hind leg: Hip -> muscular thigh -> knee -> warty calf (crus) -> heel -> webbed foot
        hip = rump_pt + R_body @ np.array([side * 3.35 * puff_x, -0.15, 0.25])
        m.limb(hip, kn, 1.78, 1.35, SKIN, step=0.40)
        # Warty bump on thigh & calf
        m.ell(0.55 * hip + 0.45 * kn + np.array([0.0, 0.85, 0.0]), (0.78, 0.65, 0.82), WART)
        m.limb(kn, hl, 1.38, 1.02, SKIN, step=0.38)
        m.ell(0.5 * kn + 0.5 * hl + np.array([side * 0.45, 0.65, 0.0]), (0.72, 0.58, 0.75), WART)
        draw_webbed_hind_foot(m, hl, hf, side, pitch_foot=hfoot_pitch)

        # Foreleg: Shoulder -> bowed elbow -> inward-angled forearm -> forepaw
        sh = chest_pt + R_body @ np.array([side * 3.65 * puff_x, -0.45, 0.55])
        m.limb(sh, el, 1.38, 1.08, SKIN, step=0.38)
        m.limb(el, fp, 1.05, 0.84, SKIN, step=0.36)
        draw_forepaw(m, fp, side, lift_rot=(fpaw_rot_L if side < 0 else 0.0))

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_toad(v, kind, (col - start) / n)
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_qa(out_path: Path, zoom: int = 3) -> None:
    """Render a crisp nearest-neighbor zoomed QA contact sheet showing all 3 builds, key facings, and key poses."""
    picks = [
        (0, 0),   # E idle squat
        (1, 0),   # SE idle
        (2, 0),   # S idle wide squat
        (4, 0),   # W idle
        (6, 0),   # N idle warty back (ZERO tail!)
        (1, 6),   # SE forage aim tilt
        (0, 12),  # E walk hop stretch
        (1, 19),  # SE alert defensive puff-up on stiff legs!
        (0, 25),  # E run high-arc frog-leap apex
        (1, 31),  # SE groom forepaw eye-wipe
        (1, 35),  # SE sleep hunkered flat
        (0, 40),  # E bark giant Kehlsack vocal sac!
        (1, 40),  # SE bark giant Kehlsack vocal sac!
        (0, 46),  # E special full sticky tongue-lash!
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
                print(f'hex_toad build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/hex_toad.png', sheet)
    print('Saved assets/wildlife/hex_toad.png', sheet.shape)


if __name__ == '__main__':
    main()
