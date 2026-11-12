#!/usr/bin/env python3
"""Carrion crows (builds 0..2) and common ravens (builds 3..5) in the 3D pixel-art pipeline.
48x48 frames, feet at (24, 35); 62 columns; 6 builds x 8 true facings. No emissive parts.
Columns:
  idle 0:4, peck 4:10, walk 10:16, preen 16:22, watch 22:26, call 26:30,
  fly 30:38, land 38:44, takeoff 44:50, glide 50:54, hop 54:58, roost 58:62.
Usage: py -3 tools/art_corvid.py [--preview-only]
"""
import math
from pathlib import Path
import sys
import numpy as np
import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png

ROOT = Path(__file__).resolve().parent.parent
W = H = 48
COLS = 62

BODY, WING, DARK, KERATIN, EYE, GLINT = range(6)

art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 35.0, 4, 1.0
art.TIDY_EYES = False
art.DECAL_WEIGHT = {EYE: 3.4, GLINT: 4.8, KERATIN: 1.35}
art.ink_color = lambda mat: hexc('05060c' if mat in (DARK, EYE) else '090b14')

# Six natural non-emissive iridescent corvid palettes: (body plumage, wing/mantle sheen, horn bill/legs)
# Builds 0..2 = Rabenkrähe (crow), Builds 3..5 = Kolkrabe (raven)
BUILDS = [
    # 0 Crow: coal-black with cool blue-slate sheen
    (['090b13', '131826', '232c40', '3c4b66'], ['0c0f1b', '1a2236', '2e3d59', '516686'], ['161926', '2a3040', '485064', '707a90']),
    # 1 Crow: soot-black with muted dusky violet-indigo sheen
    (['0a0a13', '161525', '28273f', '444263'], ['0e0d1b', '1e1c34', '353256', '5b567f'], ['171726', '2c2c3f', '4b4b63', '74748e']),
    # 2 Crow: smoky charcoal-mantle individual variation
    (['0b0d16', '181c2a', '2b3245', '47526a'], ['101320', '21273b', '38435e', '5d6b88'], ['181b27', '2d3343', '4d5568', '768094']),
    # 3 Raven: deep obsidian with cold midnight-steel gloss
    (['070910', '111624', '1f293e', '384966'], ['0b0e1a', '172035', '2b3c5b', '4f6789'], ['151926', '2b3244', '4d576c', '7a869d']),
    # 4 Raven: heavy raven black with dark royal-plum / aubergine sheen
    (['080710', '141122', '25213c', '423b62'], ['0d0b1a', '1c1832', '332c54', '594e7f'], ['161524', '2c2b3e', '4e4c64', '797892']),
    # 5 Raven: weathered ancient raven with beetle-teal / iron-slate sheen & pale culmen glint
    (['080b12', '131924', '232e3f', '3d4f66'], ['0b101a', '192434', '2e4057', '536b86'], ['191d2b', '32394b', '576177', '8893aa']),
]

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


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def material(v: int) -> None:
    body_r, wing_r, horn_r = BUILDS[v % 6]
    ramps = [
        body_r,                                            # 0 BODY
        wing_r,                                            # 1 WING / mantle / rectrices
        ['070810', '111320', '1f2335', '343a50'],          # 2 DARK primaries / lore mask / hackle crevices
        horn_r,                                            # 3 KERATIN bill & scaly legs
        ['060811', '0b0e1a', '141828', '1e2336'],          # 4 EYE
        ['8d9ba8', 'b4c2cc', 'd8e3e8', 'f4f8fa'],          # 5 GLINT
    ]
    art.RAMPS = [[hexc(c) for c in ramp] for ramp in ramps]


def draw_spread_wing(m: art.Model, side: float, shoulder: np.ndarray, span: float, lift: float,
                     sweep_z: float, wrist_fold: float, camber: float, raven: bool) -> None:
    """Articulated avian wing: inner arm-wing (secondaries patagium) + outer hand-wing + splayed primary fingers."""
    # Carpal (wrist) joint sits forward and partway out; tip sweeps back
    carpal = shoulder + np.array([
        side * span * (0.46 - 0.14 * wrist_fold),
        lift * (0.58 + 0.22 * wrist_fold) + camber,
        1.55 - 0.85 * wrist_fold + sweep_z * 0.35,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.22 * wrist_fold),
        lift - (1.65 * wrist_fold),
        -2.35 + sweep_z - 1.25 * wrist_fold,
    ])

    # Leading-edge arm & hand spars
    s_scale = 1.22 if raven else 1.0
    m.limb(shoulder, carpal, 1.45 * s_scale, 1.15 * s_scale, WING, step=0.7)
    m.limb(carpal, tip, 1.10 * s_scale, 0.52 * s_scale, WING, step=0.7)

    # Continuous inner secondary feathers (closes any gap between shoulder, body, and wrist)
    n_sec = 6 if raven else 5
    for i in range(n_sec):
        u = i / max(n_sec - 1, 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (5.0 - 0.7 * u) * s_scale * (1.0 - 0.18 * wrist_fold)
        te = le + np.array([side * 0.35 * u, -0.55 - 0.35 * camber, -chord])
        m.limb(le, te, 0.98 * s_scale, 0.52 * s_scale, WING if i < n_sec - 1 else DARK, step=0.75)

    # Outer primaries: fanned & fingered at the wingtip (5 distinct primary fingers on ravens, 4 tighter on crows)
    n_pri = 6 if raven else 5
    finger_spread = (1.0 - 0.55 * wrist_fold)
    for i in range(n_pri):
        u = (i + 0.15) / n_pri
        le = carpal * (1.0 - u) + tip * u
        fan_angle = -0.25 + 0.88 * u
        plen = (5.8 - 1.35 * u + (0.65 if raven and i >= 2 else 0.0)) * s_scale
        dx = side * math.sin(fan_angle + 0.35) * plen * 0.62 * finger_spread
        dz = -math.cos(fan_angle * 0.65) * plen
        dy = (u - 0.4) * 0.65 * finger_spread - 0.45 * wrist_fold
        te = le + np.array([dx, dy, dz])
        r0 = (0.78 - 0.18 * u) * s_scale
        r1 = (0.34 if (raven and i >= 2) else 0.40) * s_scale
        m.limb(le, te, r0, r1, DARK if i >= 1 else WING, step=0.7)


def build(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    raven = v >= 3
    sz = 1.24 if raven else 1.0
    tau = math.tau
    p = t * tau
    bob = math.sin(p)

    flying = kind in ('fly', 'takeoff', 'land', 'glide')

    # Default proud corvid ground posture (~34 deg back-to-breast angle, crisp visible tarsus legs)
    rump_y, rump_z = 5.85 * sz, -2.65 * sz
    chest_y, chest_z = 8.35 * sz, 1.95 * sz
    head_y, head_z = 12.15 * sz, 3.15 * sz
    head_pitch = 0.04
    head_yaw = 0.0
    head_roll = 0.0
    body_sway_x = 0.0
    tail_pitch = -0.18
    tail_fan = 1.0
    beak_open = 0.0
    hackle_puff = 1.0 if raven else 0.0
    blink = False
    wing_preen_side = 0.0
    hop_wing = 0.0

    # Default planted feet on ground (GROUND_ROW = 35 -> y ~ 0.65..0.85)
    foot_L = np.array([-1.45 * sz, 0.68, 0.55 * sz])
    foot_R = np.array([1.45 * sz, 0.68, 0.55 * sz])
    toes_curl = 0.0

    if kind == 'idle':
        idx = int(round(t * 4)) % 4
        chest_y += 0.14 * bob * sz
        head_y += 0.16 * bob * sz
        head_yaw = 0.14 * math.sin(p)
        blink = (idx == 3)

    elif kind == 'peck':
        # 6 frames: hip-hinge bow (0), sharp turf strike (1,2), sideways bill pry (3), lift & swallow (4,5)
        idx = int(round(t * 6)) % 6
        dip = [0.38, 0.92, 1.0, 0.86, 0.42, 0.12][idx]
        rump_y = (5.85 + 0.95 * dip) * sz
        chest_y = (8.35 - 1.85 * dip) * sz
        chest_z = (1.95 + 0.85 * dip) * sz
        head_y = (12.15 - 7.35 * dip) * sz + (0.35 * sz if idx == 2 else 0.0)
        head_z = (3.15 + 4.55 * dip) * sz
        head_pitch = 0.04 + 0.56 * dip
        head_yaw = 0.26 if idx == 3 else (-0.12 if idx == 2 else 0.0)
        tail_pitch = -0.18 + 0.46 * dip
        beak_open = 0.45 if idx in (1, 3) else 0.0

    elif kind == 'walk':
        # 6-frame alternating corvid strut with 2-beat head-bob thrust & hip waddle!
        # Left foot swings on frames 0,1,2; Right foot swings on frames 3,4,5
        for s_idx, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_idx == 0 else 0.5)) % 1.0
            if c < 0.55:  # Stance phase: planted foot sweeps backward relative to body
                u = c / 0.55
                fz = (1.95 - 3.30 * u) * sz
                fy = 0.68
            else:         # Swing phase: lifted flexed foot carries forward
                u = (c - 0.55) / 0.45
                fz = (-1.35 + 3.30 * u) * sz
                fy = 0.68 + math.sin(u * math.pi) * 1.95 * sz
            if s_idx == 0:
                foot_L = np.array([side * 1.48 * sz, fy, fz])
            else:
                foot_R = np.array([side * 1.48 * sz, fy, fz])
        # Double-frequency corvid head-thrust + subtle lateral waddle
        bob2 = math.sin(p * 2.0)
        body_sway_x = 0.32 * math.sin(p) * sz
        chest_y += 0.28 * abs(bob2) * sz
        rump_y += 0.22 * abs(bob2) * sz
        head_z += (0.85 * max(0.0, bob2) + 0.25) * sz
        head_y += (0.25 * bob2 - 0.20) * sz
        tail_pitch = -0.14 + 0.08 * bob2

    elif kind == 'preen':
        # 6 frames: turn head over left wing (0,1), lift wing & stroke primaries (2,3), fluff & settle (4,5)
        idx = int(round(t * 6)) % 6
        turn_amt = [0.45, 0.95, 1.0, 0.95, 0.35, 0.0][idx]
        fluff = 1.12 if idx == 4 else 1.0
        head_yaw = 1.25 * turn_amt
        head_pitch = 0.38 * turn_amt + (0.15 if idx == 3 else 0.0)
        head_y = (12.15 - 1.55 * turn_amt + (0.45 if idx == 4 else 0.0)) * sz
        head_z = (3.15 - 1.85 * turn_amt) * sz
        chest_y *= fluff
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
        tail_fan = 1.25 if idx == 4 else 1.0

    elif kind == 'watch':
        # Tall alert neck + inquisitive lateral head-cock (monocular corvid gaze!)
        idx = int(round(t * 4)) % 4
        cock = [0.18, 0.34, 0.28, -0.22][idx]
        chest_y = 8.85 * sz
        head_y = 13.15 * sz
        head_z = 3.05 * sz
        head_pitch = -0.05
        head_yaw = cock * 0.85
        head_roll = cock
        tail_pitch = -0.24 + (0.10 if idx == 2 else 0.0)

    elif kind == 'call':
        # Authentic corvid caw/croak full-body bow: inhale (0), thrust & wide gape + fanned tail (1,2), recover (3)
        idx = int(round(t * 4)) % 4
        bow = [0.15, 0.95, 1.0, 0.35][idx]
        rump_y = (5.85 + 0.55 * bow) * sz
        chest_y = (8.35 - 0.65 * bow) * sz
        chest_z = (1.95 + 0.85 * bow) * sz
        head_y = (12.15 - 1.45 * bow) * sz
        head_z = (3.15 + 2.05 * bow) * sz
        head_pitch = -0.08 + 0.26 * bow
        beak_open = [0.15, 1.0, 0.88, 0.20][idx]
        tail_fan = 1.0 + 0.65 * bow
        tail_pitch = -0.18 - 0.18 * bow
        hackle_puff = (1.65 if raven else 0.75) * bow + (1.0 if raven else 0.0)

    elif kind == 'hop':
        # 4-frame agile two-footed corvid ground hop: crouch (0), springy airborne hop (1,2), land (3)
        idx = int(round(t * 4)) % 4
        if idx == 0:
            rump_y, chest_y, head_y = 5.15 * sz, 7.25 * sz, 10.85 * sz
            hop_wing = 0.35
        elif idx in (1, 2):
            lift = 2.45 if idx == 1 else 2.15
            rump_y, chest_y, head_y = (6.25 + lift) * sz, (8.45 + lift) * sz, (12.05 + lift) * sz
            chest_z += 0.55 * sz
            head_z += 0.75 * sz
            foot_L = np.array([-1.45 * sz, 2.15 * sz, 1.65 * sz])
            foot_R = np.array([1.45 * sz, 2.15 * sz, 1.65 * sz])
            hop_wing = 0.85 if idx == 1 else 0.55
            tail_fan = 1.25
        else:
            rump_y, chest_y, head_y = 5.55 * sz, 7.85 * sz, 11.55 * sz
            hop_wing = 0.20

    elif kind == 'roost':
        # 4-frame calm perched roost / night sleep: head nestled into fluffed rounded chest, drooped tail, drowsy eyes
        idx = int(round(t * 4)) % 4
        rump_y, rump_z = (5.45 + 0.08 * bob) * sz, -2.35 * sz
        chest_y, chest_z = (7.25 + 0.10 * bob) * sz, 1.55 * sz
        head_y, head_z = (9.85 + 0.08 * bob) * sz, 2.15 * sz
        head_pitch = 0.16
        tail_pitch = -0.34
        blink = idx in (1, 2, 3)
        hackle_puff = (1.35 if raven else 0.45)

    elif flying:
        # Streamlined horizontal flight body; upright braking flare in 'land'; deep crouch on 'takeoff' frame 0
        if kind == 'fly':
            idx = int(round(t * 8)) % 8
            # Subtle counter-lift of body during power downstroke (frames 2,3)
            body_lift = [-0.25, -0.10, 0.35, 0.55, 0.25, -0.05, -0.25, -0.30][idx] * sz
            rump_y, rump_z = 6.55 * sz + body_lift, -3.05 * sz
            chest_y, chest_z = 7.15 * sz + body_lift, 2.25 * sz
            head_y, head_z = 8.35 * sz + body_lift, 4.95 * sz
            head_pitch = 0.10
            tail_pitch = -0.04
            tail_fan = 1.12
            toes_curl = 1.0
            foot_L = np.array([-1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])
            foot_R = np.array([1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])

        elif kind == 'glide':
            # Calm soaring / gliding: steady horizontal trim, wide spread wedge/fan tail, subtle bank breath
            rump_y, rump_z = (6.65 + 0.12 * bob) * sz, -3.05 * sz
            chest_y, chest_z = (7.25 + 0.12 * bob) * sz, 2.25 * sz
            head_y, head_z = (8.45 + 0.12 * bob) * sz, 4.95 * sz
            head_yaw = 0.10 * bob
            head_pitch = 0.08
            tail_pitch = -0.05
            tail_fan = 1.38 if raven else 1.25
            toes_curl = 1.0
            foot_L = np.array([-1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])
            foot_R = np.array([1.25 * sz, rump_y - 1.55 * sz, -1.25 * sz])

        elif kind == 'takeoff':
            idx = int(round(t * 6)) % 6
            if idx == 0:  # Deep coil on ground before leap!
                rump_y, rump_z = 4.95 * sz, -2.55 * sz
                chest_y, chest_z = 6.35 * sz, 2.25 * sz
                head_y, head_z = 9.45 * sz, 4.25 * sz
                head_pitch = 0.16
                tail_fan = 1.25
            else:
                u = idx / 5.0
                rump_y, rump_z = (5.85 + 1.25 * u) * sz, -2.85 * sz
                chest_y, chest_z = (7.45 + 0.85 * u) * sz, 2.35 * sz
                head_y, head_z = (9.85 - 0.65 * u) * sz, 4.75 * sz
                tail_fan = 1.35
                toes_curl = min(1.0, u * 1.2)
                fy = (1.35 + 3.25 * u) * sz
                fz = (0.55 - 1.65 * u) * sz
                foot_L = np.array([-1.35 * sz, fy, fz])
                foot_R = np.array([1.35 * sz, fy, fz])

        elif kind == 'land':
            # Braking flare: upright ~45 deg body pitch, wide downward fanned tail brake, talons reaching forward!
            idx = int(round(t * 6)) % 6
            flare = [0.85, 1.0, 0.95, 0.72, 0.38, 0.0][idx]
            rump_y, rump_z = (5.85 - 0.35 * flare) * sz, (-2.65 - 0.35 * flare) * sz
            chest_y, chest_z = (8.35 + 0.85 * flare) * sz, (1.95 - 0.35 * flare) * sz
            head_y, head_z = (12.15 - 0.35 * flare) * sz, (3.15 - 0.15 * flare) * sz
            tail_pitch = -0.18 - 0.38 * flare
            tail_fan = 1.0 + 0.65 * flare
            reach_z = (0.55 + 1.45 * flare) * sz
            reach_y = 0.68 + (1.65 * sz if idx < 3 else (0.65 * sz if idx == 3 else 0.0))
            foot_L = np.array([-1.45 * sz, reach_y, reach_z])
            foot_R = np.array([1.45 * sz, reach_y, reach_z])

    # ---- Smooth Seamless Avian Torso (rump -> belly/breast -> mantle -> neck) ----
    fluff_r = 1.08 if kind == 'roost' else 1.0
    for u in (0.0, 0.33, 0.67, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz_p = rump_z + (chest_z - rump_z) * u
        rx = (2.45 + 0.45 * math.sin(u * math.pi)) * sz * fluff_r
        ry = (2.55 + 0.55 * math.sin(u * math.pi)) * sz * fluff_r
        rz = (2.85 - 0.25 * u) * sz
        m.ell((body_sway_x, sy, sz_p), (rx, ry, rz), BODY)
    # Subtle dorsal mantle sheen
    mid_y = 0.45 * rump_y + 0.55 * chest_y
    mid_z = 0.45 * rump_z + 0.55 * chest_z
    m.ell((body_sway_x, mid_y + 0.95 * sz, mid_z - 0.15 * sz), (2.25 * sz, 1.65 * sz, 2.85 * sz), WING)

    # Neck column connecting breast smoothly to head
    for u in (0.35, 0.70):
        ny = chest_y + (head_y - chest_y) * u
        nz = chest_z + (head_z - chest_z) * u - 0.25 * sz
        nr = (2.05 - 0.30 * u) * sz * (1.08 if hackle_puff > 0.5 else 1.0)
        m.ell((body_sway_x, ny, nz), (nr, nr * 1.05, nr), BODY)

    # Shaggy throat hackles ("Kehlbart" — prominent on ravens, puffed when calling!)
    if hackle_puff > 0.15:
        for hs in (-1.0, 0.0, 1.0):
            hx = body_sway_x + hs * 0.78 * sz
            hy_p = head_y - 2.15 * sz
            hz_p = head_z + (1.05 + 0.28 * hackle_puff) * sz
            m.ell((hx, hy_p, hz_p), (0.62 * sz, 1.25 * sz * min(1.35, 0.7 + 0.4 * hackle_puff), 0.78 * sz),
                  DARK if hs != 0.0 else WING, R=art.rot_x(-0.42))

    # ---- Wings: Folded (layered coverts + crossed dark primaries) OR Spread Flight Kinematics ----
    for side in (-1.0, 1.0):
        sh = np.array([body_sway_x + side * 2.15 * sz, chest_y + 0.35 * sz, chest_z - 0.35 * sz])
        if not flying or (kind == 'takeoff' and int(round(t * 6)) % 6 == 0) or (kind == 'land' and int(round(t * 6)) % 6 == 5):
            # Folded wing: upper scapular/covert shield + 3 stepped primary tips crossing toward tail!
            preen_open = (1.0 if side * wing_preen_side > 0 else 0.0)
            flick = hop_wing + 0.65 * preen_open
            w_rot = art.rot_y(side * (0.12 + 0.28 * flick)) @ art.rot_x(-0.32 + 0.18 * flick) @ rot_z(-side * 0.25 * flick)
            w_center = np.array([
                body_sway_x + side * (2.25 + 0.85 * flick) * sz,
                mid_y + (0.25 + 0.55 * flick) * sz,
                mid_z - 0.55 * sz,
            ])
            m.ell(w_center, (1.12 * sz, 2.05 * sz, 3.65 * sz), WING, R=w_rot)
            # Layered dark primary flight feathers extending neatly past rump
            for pf in range(3):
                p_pos = w_center + w_rot @ np.array([
                    -side * 0.28 * pf * sz,
                    (-0.55 + 0.22 * pf) * sz,
                    (-2.55 - 0.95 * pf) * sz,
                ])
                m.ell(p_pos, (0.68 * sz, 0.82 * sz, 2.15 * sz), DARK if pf >= 1 else WING, R=w_rot)
        else:
            max_span = 16.2 if raven else 13.4
            if kind == 'fly':
                # 8-frame asymmetric real wingbeat:
                # 0 high-back, 1 wide sweep, 2 mid-camber, 3 deep downstroke, 4 wrist fold, 5 compact upstroke, 6 high wrist, 7 unfurl
                idx = int(round(t * 8)) % 8
                lifts = [7.8, 3.8, -1.2, -5.8, -3.2, 1.8, 5.8, 8.2][idx] * (1.15 if raven else 1.0)
                folds = [0.08, 0.0, 0.0, 0.10, 0.52, 0.62, 0.38, 0.16][idx]
                sweeps = [-1.4, 0.8, 2.2, 2.8, 0.5, -1.2, -2.0, -1.8][idx] * sz
                cambers = [0.6, 1.3, 1.5, 0.9, 0.3, 0.5, 0.9, 0.8][idx] * sz
                draw_spread_wing(m, side, sh, max_span, lifts, sweeps, folds, cambers, raven)
            elif kind == 'glide':
                # Majestic soaring wings: flat/slight dihedral with primary tip trim
                dihedral = (1.35 if not raven else 0.75) + 0.45 * bob
                draw_spread_wing(m, side, sh, max_span * 1.04, dihedral, -0.35 * sz, 0.02, 0.95 * sz, raven)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                # 1 high throw, 2 wide power down, 3 deep push, 4 fold recovery, 5 high climb
                lifts = [0.0, 8.5, 2.2, -5.2, 0.8, 7.2][idx] * (1.15 if raven else 1.0)
                folds = [0.0, 0.08, 0.0, 0.08, 0.48, 0.15][idx]
                sweeps = [0.0, -1.2, 1.8, 2.8, -0.6, -1.4][idx] * sz
                draw_spread_wing(m, side, sh, max_span, lifts, sweeps, folds, 1.1 * sz, raven)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                # Cupped forward braking beats, folding on 4->5
                lifts = [5.2, 1.5, 6.4, 3.2, 1.8, 0.0][idx] * (1.10 if raven else 1.0)
                folds = [0.12, 0.08, 0.15, 0.35, 0.68, 1.0][idx]
                sweeps = [2.4, 3.2, 2.0, 1.2, -0.5, 0.0][idx] * sz
                draw_spread_wing(m, side, sh, max_span * 0.92, lifts, sweeps, folds, 1.2 * sz, raven)

    # ---- Tail: Rounded Fan on Crow vs Long Stepped Diamond Wedge ("Keilschwanz") on Raven ----
    t_base = np.array([body_sway_x, rump_y - 0.35 * sz, rump_z - 1.85 * sz])
    for f_i in range(-2, 3):
        if raven:
            t_len = (8.2 - abs(f_i) * 1.35) * sz
        else:
            t_len = (5.7 - abs(f_i) * 0.32) * sz
        f_yaw = -f_i * 0.13 * tail_fan
        t_rot = art.rot_y(f_yaw) @ art.rot_x(tail_pitch)
        t_end = t_base + t_rot @ np.array([0.0, 0.0, -t_len])
        m.limb(t_base, t_end, 0.88 * sz, 0.62 * sz, WING if abs(f_i) <= 1 else DARK, step=0.75)

    # ---- Legs: Feathered Tibia "Trousers" ("Hosen") + Crisp Scaly Tarsus + Gripping Toes ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        ft = foot_L if s_idx == 0 else foot_R
        hip = np.array([body_sway_x + side * 1.35 * sz, rump_y - 0.55 * sz, rump_z + 2.15 * sz])
        ankle = 0.42 * hip + 0.58 * ft + np.array([0.0, 0.65 * sz, -0.45 * sz])
        # Feathered thigh ("Hose")
        m.ell(0.65 * hip + 0.35 * ankle, (1.05 * sz, 1.35 * sz, 1.15 * sz), BODY)
        # Crisp scaly tarsus (thick enough at SS=4 to read cleanly in every facing!)
        m.limb(ankle, ft, 0.62 * sz, 0.54 * sz, KERATIN, step=0.45)
        if toes_curl < 0.7:
            # Three forward toes + short hind hallux
            for toe in (-1, 0, 1):
                t_tip = ft + np.array([toe * 0.68 * sz, -0.18, 1.45 * sz])
                m.limb(ft, t_tip, 0.46 * sz, 0.34 * sz, KERATIN, step=0.45)
            m.limb(ft, ft + np.array([0.0, -0.15, -0.95 * sz]), 0.42 * sz, 0.32 * sz, KERATIN, step=0.45)
        else:
            m.ell(ft, (0.68 * sz, 0.58 * sz, 0.85 * sz), KERATIN)

    # ---- Sculpted Corvid Head, Dark Lore Mask, Heavy Arched Culmen Bill & Crisp Eye ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([body_sway_x, head_y, head_z])

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ (np.array([x, y, z]) * sz)

    # Cranium (ravens have a flatter crown & heavier brow; crows have a sleek rounded dome)
    m.ell(hp(0.0, 0.0, 0.0), (2.05 * sz, (2.05 if raven else 2.22) * sz, (2.55 if raven else 2.32) * sz), BODY, R=h_rot)
    if raven:
        # Heavy superciliary brow & steep forehead bridge
        m.ell(hp(0.0, 0.55, 0.95), (1.75 * sz, 1.25 * sz, 1.65 * sz), BODY, R=h_rot)

    # Dark velvet lore patch between eye and bill base (frames the eye & beak in front/3-4 views!)
    for side in (-1.0, 1.0):
        m.ell(hp(side * 1.25, 0.10, 1.35), (0.68 * sz, 0.78 * sz, 0.95 * sz), DARK, R=h_rot)

    # Upper mandible (arched culmen; massive Roman wedge on raven, sleek stout cone on crow)
    bill_len = 4.25 if raven else 3.10
    bill_h = 1.02 if raven else 0.76
    bill_w = 1.04 if raven else 0.84
    up_rot = h_rot @ art.rot_x(-0.28 * beak_open + (0.06 if raven else 0.03))
    b_base = hp(0.0, -0.06 + 0.12 * beak_open, 1.75)
    for i in range(5):
        u = i / 4.0
        arch_y = (0.18 * math.sin(u * math.pi) - 0.24 * u * u) * (1.35 if raven else 0.85)
        pos = b_base + up_rot @ (np.array([0.0, arch_y, u * bill_len]) * sz)
        rw = bill_w * (1.0 - 0.68 * u) * sz
        rh = bill_h * (1.0 - 0.65 * u) * sz
        m.ell(pos, (max(0.36, rw), max(0.34, rh), 0.80 * sz), KERATIN, R=up_rot)

    # Nasal bristles over bill root (prominent hallmark of Kolkrabe!)
    if raven:
        m.ell(hp(0.0, 0.24, 2.20), (0.88 * sz, 0.52 * sz, 0.95 * sz), DARK, R=h_rot)

    # Lower mandible (separates cleanly into an unmistakable open gape when calling or prying!)
    lo_rot = h_rot @ art.rot_x(0.52 * beak_open)
    l_base = hp(0.0, -0.52 - 0.36 * beak_open, 1.72)
    l_tip = l_base + lo_rot @ (np.array([0.0, -0.12, bill_len * 0.90]) * sz)
    m.limb(l_base, l_tip, 0.66 * sz, 0.34 * sz, KERATIN, step=0.5)

    # Eyes & natural tiny catchlight
    for side in (-1.0, 1.0):
        eh = 0.18 if blink else 0.62
        m.ell(hp(side * 1.68, 0.34, 0.92), (0.52 * sz, eh * sz, 0.60 * sz), EYE, R=h_rot)
        if not blink:
            m.ell(hp(side * 1.76, 0.54, 1.18), (0.22 * sz, 0.22 * sz, 0.22 * sz), GLINT, R=h_rot)

    return m


def pose_for_col(col: int) -> tuple[str, float]:
    for kind, start, count in BLOCKS:
        if start <= col < start + count:
            return kind, (col - start) / count
    return 'idle', 0.0


def render(v: int, d: int, col: int) -> np.ndarray:
    kind, t = pose_for_col(col)
    material(v)
    model = build(v, kind, t)
    depth, code = art.render(model.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], dtype=np.uint8)


def main() -> None:
    picks = [
        (0, 0), (1, 0), (2, 0), (4, 0), (6, 0),                        # facings E, SE, S, W, N
        (0, 6), (0, 11), (1, 18), (1, 23), (0, 27),                    # peck, walk, preen, watch(cock), call(bow)
        (0, 31), (0, 33), (0, 35), (0, 40), (0, 51), (0, 55), (1, 59)  # fly down, deep, upstroke, land, glide, hop, roost
    ]
    preview_only = '--preview-only' in sys.argv
    sheet = None if preview_only else np.zeros((6 * 8 * H, COLS * W, 4), np.uint8)
    preview = np.zeros((6 * H, len(picks) * W, 4), np.uint8)
    pick_set = set(picks)
    for v in range(6):
        for d in range(8):
            for col in range(COLS):
                if preview_only and (d, col) not in pick_set:
                    continue
                px = render(v, d, col)
                if sheet is not None:
                    y = (v * 8 + d) * H
                    x = col * W
                    sheet[y:y + H, x:x + W] = px
                if (d, col) in pick_set:
                    x = picks.index((d, col)) * W
                    preview[v * H:(v + 1) * H, x:x + W] = px
        print('Corvid build', v + 1, '/ 6', flush=True)
    if sheet is not None:
        save_png(ROOT / 'assets/wildlife/corvid.png', sheet)
    save_png(ROOT / 'docs/img/corvids.png', preview)


if __name__ == '__main__':
    main()
