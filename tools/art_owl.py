#!/usr/bin/env python3
"""Eurasian Eagle-Owl / Europäischer Uhu (Bubo bubo) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 48); 62 columns (WildCorvid / WildMeadowBird layout); 3 builds x 8 facings = 24 rows.
No emissive parts; natural non-emissive nocturnal palettes.

Builds:
  0: Eurasischer Uhu (rich warm tawny-ochre & dark umber-bark mottled plumage, pale buff facial disc, bright orange-amber eyes)
  1: Dunkler Karpaten-Uhu (deep espresso-bark & charcoal-slate forest plumage, fiery amber eyes)
  2: Bleicher Hexenwald-Uhu (ghostly ash-ivory & cool violet-slate barred plumage, pale gold-amber eyes)

Columns (62):
  idle 0:4, peck 4:10 (180-deg head-rotation & lateral listening tilt!), walk 10:16,
  preen 16:22, watch 22:26, call 26:30 (deep "U-huuu" hoot with bright white puffed throat!),
  fly 30:38, land 38:44, takeoff 44:50, glide 50:54, hop 54:58,
  roost 58:62 (daytime tall slim bark-camouflage sleep with vertical ear-tufts & slit eyes!).

Usage: py -3 tools/art_owl.py [--preview-only] [--qa=path.png]
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

BODY, MOTTLE, DISC, DARK, THROAT, EYE_AMBER, GLINT = range(7)

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
        EYE_AMBER: 4.0,
        GLINT: 4.8,
        THROAT: 2.3,
        DARK: 1.5,
        DISC: 1.3,
    }
    art.ink_color = lambda mat: hexc('0c0a12' if mat in (DARK, EYE_AMBER) else '18131d')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Eurasischer Uhu: rich warm tawny-ochre & dark umber-bark mottled plumage
        body = ['4d2e16', '825125', 'ba7b3a', 'e3ab5e']
        mottle = ['2b1910', '4d2e1c', '784c2e', 'a66f45']
        disc = ['73573b', 'a3815a', 'd1ae83', 'f0d6b2']
        dark = ['120d0e', '241b1a', '3d2e2a', '5c4740']
        throat = ['8c8377', 'bab0a2', 'e8e0d3', 'fdfbf7']
        eye = ['942e08', 'd4500e', 'f78216', 'ffbe3d']
        glint = ['9aa4b2', 'c2ccd8', 'e6eef5', 'ffffff']
    elif v == 1:
        # 1 Dunkler Karpaten-Uhu: deep espresso-bark & charcoal-slate forest plumage
        body = ['291b16', '483026', '704d3c', '9c7058']
        mottle = ['181316', '2c2329', '473a42', '695861']
        disc = ['4a3b32', '705a4c', '9c816e', 'c4a892']
        dark = ['0b0a10', '171520', '2a2637', '433e54']
        throat = ['7d7772', 'ada69f', 'ded7ce', 'f8f4ee']
        eye = ['8c2206', 'cc400a', 'f56f10', 'ffad30']
        glint = ['9aa4b2', 'c2ccd8', 'e6eef5', 'ffffff']
    else:
        # 2 Bleicher Hexenwald-Uhu: ghostly ash-ivory & cool violet-slate barred phantom owl
        body = ['5c5c6e', '88899e', 'b8b9cc', 'e4e5f2']
        mottle = ['35334a', '535070', '787496', 'a39fc2']
        disc = ['77788c', 'a5a6ba', 'd2d3e3', 'f5f6fc']
        dark = ['141321', '26243b', '403d5c', '605c80']
        throat = ['9698ab', 'c2c4d6', 'e8eaf5', 'ffffff']
        eye = ['8c5814', 'c48824', 'f0ba42', 'ffe885']
        glint = ['a8b4c4', 'cdd7e6', 'edf2fa', 'ffffff']

    ramps = [body, mottle, disc, dark, throat, eye, glint]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_spread_owl_wing(
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
    """Broad, deeply rounded, barred silent-flight Bubo bubo wing (kept cleanly inside 64x64!)."""
    carpal = shoulder + np.array([
        side * span * (0.47 - 0.13 * wrist_fold),
        lift * (0.58 + 0.20 * wrist_fold) + camber,
        (2.25 - 0.85 * wrist_fold) * sz + sweep_z * 0.38,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.22 * wrist_fold),
        lift - 1.55 * sz * wrist_fold,
        (-1.85 - 1.25 * wrist_fold) * sz + sweep_z,
    ])

    # Thick velvety leading-edge spars ("comb" leading edge for silent nocturnal flight)
    m.limb(shoulder, carpal, 2.15 * sz, 1.72 * sz, BODY, step=0.65)
    m.limb(carpal, tip, 1.65 * sz, 0.92 * sz, MOTTLE, step=0.65)

    # Upper wing coverts with warm/mottled barring along inner arm
    for j in range(6):
        u = j / 5.0
        q = shoulder * (1.0 - u) + carpal * u
        m.ell(
            q + np.array([0.0, 0.20 * sz, -1.55 * sz]),
            (1.75 * sz, 0.88 * sz, 2.65 * sz),
            BODY if j % 2 == 0 else MOTTLE,
        )

    # Broad, deeply rounded inner secondaries with alternating dark/ochre transverse bars!
    n_sec = 8
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (8.6 - 0.55 * u + 1.15 * math.sin(u * math.pi)) * sz * (1.0 - 0.18 * wrist_fold)
        te = le + np.array([side * 0.45 * u * sz, -0.85 * sz - 0.38 * camber, -chord])
        mid1 = le * 0.64 + te * 0.36
        mid2 = le * 0.32 + te * 0.68
        m.limb(le, mid1, 1.52 * sz, 1.25 * sz, BODY if i % 2 == 0 else MOTTLE, step=0.65)
        m.limb(mid1, mid2, 1.22 * sz, 0.96 * sz, DARK if i % 2 == 1 else MOTTLE, step=0.65)
        m.limb(mid2, te, 0.94 * sz, 0.62 * sz, DISC if i % 2 == 0 else DARK, step=0.65)

    # Rounded slotted outer primaries (6 barred primary feathers, softly rounded owl wingtip)
    n_pri = 6
    finger_spread = 1.0 - 0.52 * wrist_fold
    for i in range(n_pri):
        u = (i + 0.12) / n_pri
        le = carpal * (1.0 - u) + tip * u
        fan_angle = -0.20 + 0.84 * u
        plen = (8.8 - 1.55 * u + 0.95 * math.sin(u * math.pi)) * sz * (1.0 - 0.12 * wrist_fold)
        dx = side * math.sin(fan_angle + 0.32) * plen * 0.50 * finger_spread
        dz = -math.cos(fan_angle * 0.60) * plen
        dy = ((u - 0.45) * 0.65 * finger_spread - 0.48 * wrist_fold) * sz
        te = le + np.array([dx, dy, dz])
        mid = le * 0.52 + te * 0.48
        m.limb(le, mid, (1.22 - 0.18 * u) * sz, (0.92 - 0.14 * u) * sz, MOTTLE if i % 2 == 0 else BODY, step=0.62)
        m.limb(mid, te, (0.88 - 0.14 * u) * sz, 0.52 * sz, DARK, step=0.62)


def build_owl(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    sz = 1.22  # Imposing Eurasian Eagle-Owl stature while keeping full wingspan cleanly inside 64x64!
    tau = math.tau
    p = t * tau
    bob = math.sin(p)

    flying = kind in ('fly', 'takeoff', 'land', 'glide')

    # Default upright barrel-chested Eagle-Owl ground/perch posture (GROUND_ROW = 48.0)
    rump_y, rump_z = 7.2 * sz, -2.45 * sz
    chest_y, chest_z = 11.4 * sz, 1.85 * sz
    head_y, head_z = 16.0 * sz, 2.35 * sz
    head_pitch = 0.04
    head_yaw = 0.0
    head_roll = 0.0
    body_sway_x = 0.0
    slim_factor = 1.0          # <1.0 in daytime bark-camouflage roost!
    tuft_angle = 0.62          # ~36 deg outward from vertical in calm idle
    tuft_sweep = -0.35 * sz
    tuft_len = 4.65 * sz
    tuft_asym = 0.0
    throat_puff = 0.0          # bright white hoot throat balloon in 'call'!
    beak_open = 0.0
    eye_slit = 0.0
    brow_scowl = 0.35
    tail_pitch = -0.32
    tail_fan = 1.0
    wing_preen_side = 0.0
    hop_wing = 0.0

    # Planted feathered talons around (0, 0.78, 0.65*sz) -> right on GROUND_ROW = 48
    foot_L = np.array([-2.05 * sz, 0.78, 0.65 * sz])
    foot_R = np.array([2.05 * sz, 0.78, 0.65 * sz])
    toes_curl = 0.0

    if kind == 'idle':
        idx = int(round(t * 4)) % 4
        chest_y += 0.18 * bob * sz
        head_y += 0.20 * bob * sz
        head_yaw = 0.12 * math.sin(p)
        tuft_angle = 0.64 + 0.04 * bob
        if idx == 3:
            eye_slit = 0.88

    elif kind == 'peck':
        # Owls NEVER peck grass: 6-frame nocturnal acoustic listening & 180-deg head-turn / lateral head-tilt scan!
        idx = int(round(t * 6)) % 6
        yaws = [0.76, 1.56, 0.20, -1.52, -0.78, -0.18]
        rolls = [0.36, 0.16, -0.50, -0.18, 0.42, 0.12]
        pitches = [-0.04, 0.02, 0.12, 0.02, -0.05, 0.02]
        head_yaw = yaws[idx]
        head_roll = rolls[idx]
        head_pitch = pitches[idx]
        head_y += [0.25, 0.42, -0.15, 0.42, 0.25, 0.10][idx] * sz
        tuft_angle = [0.46, 0.38, 0.52, 0.38, 0.46, 0.56][idx]
        tuft_asym = [0.18, 0.10, -0.22, -0.10, 0.20, 0.0][idx]
        brow_scowl = 0.20

    elif kind == 'walk':
        # 6-frame heavy talon-step side-shuffle / waddle!
        for s_idx, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_idx == 0 else 0.5)) % 1.0
            if c < 0.56:
                u = c / 0.56
                fz = (2.05 - 3.50 * u) * sz
                fy = 0.78
            else:
                u = (c - 0.56) / 0.44
                fz = (-1.45 + 3.50 * u) * sz
                fy = 0.78 + math.sin(u * math.pi) * 2.45 * sz
            if s_idx == 0:
                foot_L = np.array([side * 2.15 * sz, fy, fz])
            else:
                foot_R = np.array([side * 2.15 * sz, fy, fz])
        bob2 = abs(math.sin(p))
        body_sway_x = 0.72 * math.sin(p) * sz
        head_roll = -0.10 * math.sin(p)
        head_yaw = 0.14 * math.sin(p)
        chest_y += 0.35 * bob2 * sz
        rump_y += 0.28 * bob2 * sz
        head_y += 0.32 * bob2 * sz

    elif kind == 'preen':
        # 6 frames: turning head deep into shoulder/wing feathers to preen
        idx = int(round(t * 6)) % 6
        turn_amt = [0.45, 0.96, 1.0, 0.94, 0.38, 0.0][idx]
        fluff = 1.12 if idx == 4 else 1.0
        head_yaw = 1.38 * turn_amt
        head_pitch = 0.44 * turn_amt + (0.14 if idx == 2 else 0.0)
        head_roll = -0.18 * turn_amt
        head_y = (16.0 - 1.65 * turn_amt + (0.45 if idx == 4 else 0.0)) * sz
        head_z = (2.35 - 1.75 * turn_amt) * sz
        slim_factor = fluff
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
        tuft_angle = 0.78
        if idx in (2, 3):
            eye_slit = 0.65

    elif kind == 'watch':
        # 4 frames: intense forward lock, ear-tufts raised alertly, blazing eyes wide!
        idx = int(round(t * 4)) % 4
        chest_y = 11.8 * sz
        chest_z = 2.45 * sz
        head_y = 16.4 * sz
        head_z = 3.25 * sz
        head_pitch = 0.10
        head_yaw = [0.0, 0.10, 0.0, -0.10][idx]
        head_roll = [0.0, 0.08, 0.0, -0.08][idx]
        tuft_angle = 0.28   # raised alertly!
        tuft_len = 5.05 * sz
        brow_scowl = 0.58

    elif kind == 'call':
        # 4 frames: deep Eagle-Owl "U-huuu" hoot!
        # Chest bowed forward, white throat patch puffed out brightly, ear-tufts lowered slightly!
        idx = int(round(t * 4)) % 4
        hoot = [0.30, 1.0, 0.92, 0.38][idx]
        rump_y = (7.2 + 0.95 * hoot) * sz
        rump_z = (-2.45 - 0.35 * hoot) * sz
        chest_y = (11.4 - 1.05 * hoot) * sz
        chest_z = (1.85 + 1.45 * hoot) * sz
        head_y = (16.0 - 1.55 * hoot) * sz
        head_z = (2.35 + 2.15 * hoot) * sz
        head_pitch = 0.16 * hoot
        throat_puff = hoot
        beak_open = 0.42 * hoot
        tuft_angle = 0.64 + 0.34 * hoot   # lowered/swept slightly outward during hoot!
        tuft_sweep = (-0.55 * hoot - 0.30) * sz
        tail_pitch = -0.32 + 0.38 * hoot
        tail_fan = 1.0 + 0.25 * hoot

    elif kind == 'hop':
        # 4-frame talon pounce / branch hop with half-open wings
        idx = int(round(t * 4)) % 4
        if idx == 0:
            rump_y, chest_y, head_y = 6.2 * sz, 9.8 * sz, 14.2 * sz
            chest_z, head_z = 2.3 * sz, 3.0 * sz
            hop_wing = 0.42
        elif idx in (1, 2):
            lift = 3.2 if idx == 1 else 2.6
            rump_y, chest_y, head_y = (7.6 + lift) * sz, (11.5 + lift) * sz, (15.9 + lift) * sz
            chest_z, head_z = 2.55 * sz, 3.45 * sz
            foot_L = np.array([-2.15 * sz, 2.85 * sz, 2.15 * sz])
            foot_R = np.array([2.15 * sz, 2.85 * sz, 2.15 * sz])
            hop_wing = 0.95 if idx == 1 else 0.72
            tail_fan = 1.35
        else:
            rump_y, chest_y, head_y = 6.8 * sz, 10.6 * sz, 15.1 * sz
            hop_wing = 0.25

    elif kind == 'roost':
        # 4-frame daytime bark-camouflage sleep ("Tarnstellung"):
        # Tall, slimmed-down posture, ear-tufts pointing straight vertically up, eyes closed to narrow slits!
        rump_y, rump_z = (7.8 + 0.08 * bob) * sz, -1.75 * sz
        chest_y, chest_z = (12.5 + 0.10 * bob) * sz, 1.15 * sz
        head_y, head_z = (17.5 + 0.10 * bob) * sz, 1.45 * sz
        slim_factor = 0.75
        head_pitch = -0.03
        tuft_angle = 0.07   # pointing straight vertically up!
        tuft_sweep = -0.08 * sz
        tuft_len = 5.35 * sz
        eye_slit = 1.0      # narrow camouflage slits!
        tail_pitch = -0.48
        tail_fan = 0.72
        foot_L = np.array([-1.55 * sz, 0.78, 0.55 * sz])
        foot_R = np.array([1.55 * sz, 0.78, 0.55 * sz])

    elif flying:
        if kind == 'fly':
            idx = int(round(t * 8)) % 8
            body_lift = [-0.35, -0.10, 0.45, 0.75, 0.35, -0.05, -0.35, -0.45][idx] * sz
            by = 15.2 * sz + body_lift
            rump_y, rump_z = by - 0.65 * sz, -3.55 * sz
            chest_y, chest_z = by + 0.35 * sz, 2.35 * sz
            head_y, head_z = by + 1.45 * sz, 5.15 * sz
            head_pitch = 0.08
            tuft_angle = 0.85
            tuft_sweep = -0.95 * sz
            tail_pitch = -0.05
            tail_fan = 1.25
            toes_curl = 1.0
            foot_L = np.array([-1.65 * sz, rump_y - 1.65 * sz, -1.65 * sz])
            foot_R = np.array([1.65 * sz, rump_y - 1.65 * sz, -1.65 * sz])

        elif kind == 'glide':
            by = (15.5 + 0.16 * bob) * sz
            rump_y, rump_z = by - 0.65 * sz, -3.55 * sz
            chest_y, chest_z = by + 0.35 * sz, 2.35 * sz
            head_y, head_z = by + 1.45 * sz, 5.15 * sz
            head_pitch = 0.06
            head_yaw = 0.08 * bob
            tuft_angle = 0.82
            tuft_sweep = -0.90 * sz
            tail_pitch = -0.06
            tail_fan = 1.42
            toes_curl = 1.0
            foot_L = np.array([-1.65 * sz, rump_y - 1.65 * sz, -1.65 * sz])
            foot_R = np.array([1.65 * sz, rump_y - 1.65 * sz, -1.65 * sz])

        elif kind == 'takeoff':
            idx = int(round(t * 6)) % 6
            if idx == 0:
                rump_y, rump_z = 6.0 * sz, -2.65 * sz
                chest_y, chest_z = 8.6 * sz, 2.65 * sz
                head_y, head_z = 12.6 * sz, 4.35 * sz
                head_pitch = 0.16
                tuft_angle = 0.48
                tail_fan = 1.32
            else:
                u = ease(idx / 5.0)
                by = (9.8 + 6.4 * u) * sz
                rump_y, rump_z = by + (-1.2 + 0.5 * u) * sz, (-3.1 - 0.4 * u) * sz
                chest_y, chest_z = by + (0.8 - 0.4 * u) * sz, 2.45 * sz
                head_y, head_z = by + (3.2 - 1.6 * u) * sz, 4.85 * sz
                tuft_angle = 0.55 + 0.25 * u
                tuft_sweep = (-0.45 - 0.45 * u) * sz
                tail_fan = 1.38
                toes_curl = min(1.0, u * 1.25)
                fy = (1.5 + 8.5 * u) * sz
                fz = (0.8 - 2.2 * u) * sz
                foot_L = np.array([-1.85 * sz, fy, fz])
                foot_R = np.array([1.85 * sz, fy, fz])

        elif kind == 'land':
            # Upright wing-braking flare: feathered talons extended forward to grip branch!
            idx = int(round(t * 6)) % 6
            flare = [0.88, 1.0, 0.94, 0.68, 0.34, 0.0][idx]
            climb_y = [4.8, 3.8, 2.6, 1.4, 0.4, 0.0][idx] * sz
            rump_y, rump_z = 7.0 * sz + climb_y - 0.4 * flare * sz, (-2.45 - 0.55 * flare) * sz
            chest_y, chest_z = 11.4 * sz + climb_y + 0.85 * flare * sz, (1.85 - 0.35 * flare) * sz
            head_y, head_z = 15.8 * sz + climb_y + 0.35 * flare * sz, (2.35 + 0.25 * flare) * sz
            tuft_angle = 0.42
            tail_pitch = -0.32 - 0.38 * flare
            tail_fan = 1.0 + 0.68 * flare
            reach_z = (0.65 + 2.45 * flare) * sz
            reach_y = 0.78 + climb_y * 0.68
            foot_L = np.array([-2.15 * sz, reach_y, reach_z])
            foot_R = np.array([2.15 * sz, reach_y, reach_z])

    # ---- Stocky Barrel-Chested Eagle-Owl Torso (seamless multi-ellipsoid loft + barred breast flecks) ----
    for u in (0.0, 0.28, 0.56, 0.82, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz_p = rump_z + (chest_z - rump_z) * u
        arch = math.sin(u * math.pi)
        rx = (3.45 + 0.92 * arch) * sz * slim_factor
        ry = (3.55 + 0.88 * arch) * sz * (0.94 if slim_factor < 0.85 else 1.0)
        rz = (3.65 + 0.35 * arch) * sz * slim_factor
        m.ell((body_sway_x, sy, sz_p), (rx, ry, rz), BODY)

    # Rich dark-mottled dorsal mantle & scapular saddle
    mid_y = 0.42 * rump_y + 0.58 * chest_y
    mid_z = 0.42 * rump_z + 0.58 * chest_z
    m.ell(
        (body_sway_x, mid_y + 1.15 * sz, mid_z - 0.55 * sz),
        (3.35 * sz * slim_factor, 2.55 * sz, 3.55 * sz * slim_factor),
        MOTTLE,
    )

    # Characteristic Bubo bubo dark longitudinal chest streaks / bark vermiculations on breast!
    if not flying or kind == 'land':
        for row_i in range(3):
            for col_i in (-1, 0, 1):
                if row_i == 2 and col_i == 0:
                    continue
                bx = body_sway_x + col_i * 1.40 * sz * slim_factor
                by_f = chest_y - (0.55 + row_i * 1.48) * sz
                bz_f = chest_z + ((2.95 - row_i * 0.42) * slim_factor - abs(col_i) * 0.32) * sz
                m.ell(
                    (bx, by_f, bz_f),
                    (0.38 * sz * slim_factor, 0.76 * sz, 0.44 * sz),
                    DARK if (row_i + col_i) % 2 == 0 else MOTTLE,
                )

    # Thick feathered neck bridge (seamless collar between barrel chest & broad owl head)
    for u in (0.35, 0.72):
        ny = chest_y + (head_y - chest_y) * u
        nz = chest_z + (head_z - chest_z) * u - 0.25 * sz
        nr = (3.15 - 0.25 * u) * sz * slim_factor
        m.ell((body_sway_x, ny, nz), (nr, nr * 0.95, nr * 0.95), BODY)

    # ---- Pale/White Throat Patch ("Kehlfleck"): subtle bib at rest, puffed brightly in 'call'! ----
    if throat_puff > 0.08:
        tp_r = (1.42 + 1.25 * throat_puff) * sz
        tp_pos = np.array([
            body_sway_x,
            head_y - (2.15 + 0.25 * throat_puff) * sz,
            head_z + (2.10 + 1.10 * throat_puff) * sz,
        ])
        m.ell(tp_pos, (tp_r * 1.14, tp_r * 0.92, tp_r * 0.96), THROAT)
    else:
        m.ell(
            (body_sway_x, head_y - 2.30 * sz, head_z + 1.90 * sz * slim_factor),
            (1.32 * sz * slim_factor, 0.82 * sz, 0.90 * sz),
            THROAT,
        )

    # ---- Wings: Folded Barred Owl Coverts OR Broad Rounded Silent-Flight Wings ----
    # Shoulder at ±4.05, span = 19.6 -> tip at ±23.65, plus primary feather ~2.5 -> ±26.2 (52.4 px inside 64 px!)
    max_span = 19.6
    for side in (-1.0, 1.0):
        sh = np.array([body_sway_x + side * 3.30 * sz * slim_factor, chest_y + 0.55 * sz, chest_z - 0.35 * sz])
        folded_now = (
            not flying
            or (kind == 'takeoff' and int(round(t * 6)) % 6 == 0)
            or (kind == 'land' and int(round(t * 6)) % 6 == 5)
        )
        if folded_now:
            preen_open = 1.0 if side * wing_preen_side > 0 else 0.0
            flick = hop_wing + 0.65 * preen_open
            if hop_wing > 0.55:
                draw_spread_owl_wing(
                    m, side, sh,
                    span=max_span * (0.72 if hop_wing > 0.8 else 0.55),
                    lift=5.2 * hop_wing,
                    sweep_z=0.7 * sz,
                    wrist_fold=0.35,
                    camber=1.0 * sz,
                    sz=sz,
                )
            else:
                w_rot = (
                    art.rot_y(side * (0.10 + 0.32 * flick))
                    @ art.rot_x(-0.30 + 0.16 * flick)
                    @ rot_z(-side * 0.24 * flick)
                )
                w_center = np.array([
                    body_sway_x + side * (3.42 * slim_factor + 0.95 * flick) * sz,
                    mid_y + (0.35 + 0.55 * flick) * sz,
                    mid_z - 0.55 * sz,
                ])
                m.ell(w_center, (1.42 * sz * slim_factor, 2.95 * sz, 4.55 * sz), MOTTLE, R=w_rot)
                for cb in range(3):
                    c_pos = w_center + w_rot @ (np.array([
                        side * 0.68 * slim_factor,
                        0.68 - cb * 0.95,
                        1.15 - cb * 1.48,
                    ]) * sz)
                    m.ell(c_pos, (0.68 * sz, 0.60 * sz, 0.98 * sz), DISC if cb == 0 else BODY, R=w_rot)
                for pf in range(3):
                    p_pos = w_center + w_rot @ (np.array([
                        -side * 0.32 * pf,
                        -0.85 + 0.22 * pf,
                        -2.95 - 1.05 * pf,
                    ]) * sz)
                    m.ell(p_pos, (0.80 * sz, 0.95 * sz, 2.20 * sz), DARK if pf % 2 == 1 else MOTTLE, R=w_rot)
        else:
            if kind == 'fly':
                idx = int(round(t * 8)) % 8
                lifts = [11.6, 5.6, -2.0, -8.8, -4.8, 2.6, 8.2, 12.0][idx]
                folds = [0.08, 0.0, 0.0, 0.10, 0.48, 0.58, 0.34, 0.14][idx]
                sweeps = [-1.4, 0.9, 2.4, 3.0, 0.6, -1.2, -2.0, -1.6][idx] * sz
                cambers = [0.9, 1.6, 1.8, 1.1, 0.5, 0.7, 1.1, 1.0][idx] * sz
                draw_spread_owl_wing(m, side, sh, max_span, lifts, sweeps, folds, cambers, sz)
            elif kind == 'glide':
                dihedral = 0.75 + 0.45 * bob
                draw_spread_owl_wing(m, side, sh, max_span * 1.02, dihedral, -0.25 * sz, 0.02, 1.45 * sz, sz)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                lifts = [0.0, 12.0, 3.4, -8.2, 1.5, 10.2][idx]
                folds = [0.0, 0.06, 0.0, 0.08, 0.44, 0.14][idx]
                sweeps = [0.0, -1.2, 2.0, 3.2, -0.6, -1.4][idx] * sz
                draw_spread_owl_wing(m, side, sh, max_span, lifts, sweeps, folds, 1.45 * sz, sz)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                lifts = [8.2, 2.6, 9.2, 4.8, 2.4, 0.0][idx]
                folds = [0.10, 0.06, 0.14, 0.34, 0.66, 1.0][idx]
                sweeps = [2.8, 3.6, 2.4, 1.4, -0.4, 0.0][idx] * sz
                draw_spread_owl_wing(m, side, sh, max_span * 0.94, lifts, sweeps, folds, 1.55 * sz, sz)

    # ---- Short Broad Barred Owl Tail (rectrices) ----
    t_base = np.array([body_sway_x, rump_y - 0.35 * sz, rump_z - 2.15 * sz])
    for f_i in range(-2, 3):
        t_len = (5.7 - abs(f_i) * 0.35) * sz
        f_yaw = -f_i * 0.14 * tail_fan
        t_rot = art.rot_y(f_yaw) @ art.rot_x(tail_pitch)
        t_mid = t_base + t_rot @ np.array([0.0, 0.0, -t_len * 0.52])
        t_end = t_base + t_rot @ np.array([0.0, 0.0, -t_len])
        m.limb(t_base, t_mid, 1.12 * sz, 0.92 * sz, MOTTLE if abs(f_i) % 2 == 0 else BODY, step=0.65)
        m.limb(t_mid, t_end, 0.90 * sz, 0.68 * sz, DARK if abs(f_i) % 2 == 1 else DISC, step=0.65)

    # ---- Thickly Feathered Talons ("Befiederte Fänge") + Curved Dark Slate Claws ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        ft = foot_L if s_idx == 0 else foot_R
        hip = np.array([body_sway_x + side * 1.85 * sz * slim_factor, rump_y - 0.65 * sz, rump_z + 2.25 * sz])
        ankle = 0.45 * hip + 0.55 * ft + np.array([0.0, 0.75 * sz, -0.35 * sz])
        m.ell(0.60 * hip + 0.40 * ankle, (1.48 * sz * slim_factor, 1.68 * sz, 1.58 * sz), BODY)
        m.limb(ankle, ft, 1.05 * sz, 0.86 * sz, DISC, step=0.45)
        if toes_curl < 0.7:
            for toe in (-0.75, 0.0, 0.75):
                t_knuckle = ft + np.array([toe * 0.95 * sz, -0.05, 1.25 * sz])
                t_claw = ft + np.array([toe * 1.15 * sz, -0.45, 2.10 * sz])
                m.limb(ft, t_knuckle, 0.66 * sz, 0.52 * sz, DISC, step=0.42)
                m.limb(t_knuckle, t_claw, 0.46 * sz, 0.25 * sz, DARK, step=0.38)
            m.limb(ft, ft + np.array([0.0, -0.28, -1.25 * sz]), 0.54 * sz, 0.28 * sz, DARK, step=0.40)
        else:
            m.ell(ft, (0.98 * sz, 0.88 * sz, 1.18 * sz), DISC)
            m.ell(ft + np.array([0.0, -0.25 * sz, -0.55 * sz]), (0.70 * sz, 0.58 * sz, 0.75 * sz), DARK)

    # ---- Broad Rounded Bubo bubo Head, Framed Facial Disc, Ear-Tufts & Blazing Amber Eyes ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([body_sway_x, head_y, head_z])
    hsx = 0.82 if slim_factor < 0.85 else 1.0

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ (np.array([x * hsx, y, z]) * sz)

    # Broad flat-crowned owl cranium & mottled nape
    m.ell(hp(0.0, 0.15, -0.15), (3.65 * sz * hsx, 3.12 * sz, 3.22 * sz), BODY, R=h_rot)
    m.ell(hp(0.0, 0.45, -0.85), (3.22 * sz * hsx, 2.72 * sz, 2.52 * sz), MOTTLE, R=h_rot)

    # Framed Facial Disc ("Gesichtsschleier"):
    # Dark outer cheek/jaw rim ("Schleierrand") + concave pale buff disc cushions on left & right!
    for side in (-1.0, 1.0):
        disc_rot = h_rot @ art.rot_y(side * 0.22)
        m.ell(hp(side * 1.98, -0.06, 1.35), (1.52 * sz * hsx, 2.18 * sz, 1.08 * sz), DARK, R=disc_rot)
        m.ell(hp(side * 1.52, -0.02, 1.74), (1.48 * sz * hsx, 1.98 * sz, 0.96 * sz), DISC, R=disc_rot)

    # Central forehead bridge & dark medial crease between the two facial discs
    m.limb(hp(0.0, 1.55, 2.02), hp(0.0, 0.25, 2.42), 0.50 * sz, 0.38 * sz, DARK, step=0.4)

    # Prominent Feathered Ear-Tufts ("Federohren") — hallmark of Bubo bubo!
    for side in (-1.0, 1.0):
        ang = tuft_angle + side * tuft_asym
        tl_u = tuft_len / sz
        ts_u = tuft_sweep / sz
        t_base_p = hp(side * 2.08, 2.18, 0.65)
        t_mid_p = hp(
            side * (2.08 + math.sin(ang) * tl_u * 0.52),
            2.18 + math.cos(ang) * tl_u * 0.52,
            0.65 + ts_u * 0.45,
        )
        t_tip_p = hp(
            side * (2.08 + math.sin(ang) * tl_u),
            2.18 + math.cos(ang) * tl_u + 0.15,
            0.65 + ts_u,
        )
        m.limb(t_base_p, t_mid_p, 1.04 * sz, 0.76 * sz, MOTTLE, step=0.42)
        m.limb(t_mid_p, t_tip_p, 0.76 * sz, 0.32 * sz, DARK, step=0.38)
        m.limb(
            hp(side * 1.78, 2.08, 0.95),
            hp(side * (1.78 + math.sin(ang) * tl_u * 0.45), 2.08 + math.cos(ang) * tl_u * 0.45, 0.95 + ts_u * 0.35),
            0.50 * sz, 0.30 * sz, DISC, step=0.42,
        )

    # Short hooked dark slate raptor bill nestled between facial discs + pale chin bristles
    m.ell(hp(0.0, -0.70, 2.40), (0.88 * sz * hsx, 0.68 * sz, 0.78 * sz), THROAT, R=h_rot)
    up_rot = h_rot @ art.rot_x(-0.22 * beak_open + 0.24)
    b_root = hp(0.0, -0.28, 2.38)
    b_mid = b_root + up_rot @ (np.array([0.0, -0.18, 1.08]) * sz)
    b_hook = b_root + up_rot @ (np.array([0.0, -0.84, 1.78]) * sz)
    m.limb(b_root, b_mid, 0.72 * sz, 0.54 * sz, DARK, step=0.36)
    m.limb(b_mid, b_hook, 0.52 * sz, 0.26 * sz, DARK, step=0.34)
    m.ell(b_root + up_rot @ (np.array([0.0, 0.08, 0.65]) * sz), (0.30 * sz, 0.25 * sz, 0.48 * sz), GLINT, R=up_rot)
    if beak_open > 0.08:
        lo_tip = hp(0.0, -0.90 - 0.48 * beak_open, 3.32)
        m.limb(hp(0.0, -0.70, 2.30), lo_tip, 0.50 * sz, 0.28 * sz, DARK, step=0.36)

    # Large Forward-Facing Blazing Orange-Amber Eyes + Fierce Pale Superciliary V-Brows!
    for side in (-1.0, 1.0):
        e_rot = h_rot @ art.rot_y(side * 0.26)
        if eye_slit > 0.55:
            slit_a = hp(side * 0.85, 0.15, 2.52)
            slit_b = hp(side * 2.22, 0.56, 2.10)
            m.limb(slit_a, slit_b, 0.38 * sz, 0.34 * sz, DARK, step=0.34)
            if eye_slit < 0.95:
                m.ell(hp(side * 1.52, 0.32, 2.35), (0.48 * sz, 0.24 * sz, 0.38 * sz), EYE_AMBER, R=e_rot)
        else:
            m.ell(hp(side * 1.52, 0.32, 2.24), (1.06 * sz, 1.10 * sz, 0.72 * sz), DARK, R=e_rot)
            m.ell(hp(side * 1.54, 0.32, 2.42), (0.92 * sz, 0.96 * sz, 0.68 * sz), EYE_AMBER, R=e_rot)
            m.ell(hp(side * 1.56, 0.30, 2.78), (0.42 * sz, 0.46 * sz, 0.40 * sz), DARK, R=e_rot)
            m.ell(hp(side * 1.35, 0.60, 2.86), (0.24 * sz, 0.24 * sz, 0.24 * sz), GLINT, R=e_rot)

        # Fierce pale V-shaped superciliary brow ridge ("Federbraue") angling down to bill base!
        brow_in = hp(side * 0.42, 0.58 - 0.18 * brow_scowl, 2.58)
        brow_out = hp(side * 2.42, 1.34 + 0.12 * brow_scowl, 1.92)
        m.limb(brow_in, brow_out, 0.48 * sz, 0.42 * sz, THROAT, step=0.38)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_owl(v, kind, (col - start) / n)
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
        (0, 0),   # E idle
        (1, 0),   # SE idle (facial disc, ear-tufts & blazing amber eyes!)
        (2, 0),   # S idle (front facial disc & V-brows!)
        (6, 0),   # N idle (mottled back & barred tail)
        (1, 5),   # SE peck/listen: 180-deg over-shoulder owl head rotation!
        (2, 6),   # S peck/listen: lateral owl head-tilt!
        (1, 11),  # SE talon-step waddle
        (1, 18),  # SE preen into shoulder
        (2, 23),  # S intense forward watch lock!
        (1, 27),  # SE "U-huuu" hoot with bright white puffed throat!
        (2, 27),  # S "U-huuu" hoot front view!
        (1, 30),  # SE fly high upstroke (wing margin check!)
        (1, 33),  # SE fly deep downstroke
        (2, 51),  # S broad silent nocturnal glide (full wingspan margin check!)
        (0, 39),  # E upright landing flare with talons extended forward!
        (2, 59),  # S daytime tall slim bark-camouflage roost (vertical ear-tufts & slit eyes!)
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
                print(f'owl build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/owl.png', sheet)
    print('Saved assets/wildlife/owl.png', sheet.shape)


if __name__ == '__main__':
    main()
