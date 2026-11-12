#!/usr/bin/env python3
"""Wild hares / rabbits, using the heroine's miniature 3D/pixel renderer (numpy only).
Six natural wild coat builds, eight true directions, 44 pose columns at 32x32; feet (16, 25).
Idle/sniff 0..5, graze 6..13, alert 14..17, stand/lookout 18..23,
hop/bound 24..29, groom 30..35, loaf/doze 36..39, thump 40..43.
python3 tools/art_rabbit.py [--preview-only] renders the sheet and a contact sheet.
"""
import math
from pathlib import Path
import sys
import numpy as np
import art_hero3d as art
from gen_art import hexc, CLEAR

ROOT = Path(__file__).resolve().parent.parent
FW, FH, COLS, VARIANTS = 32, 32, 44, 6

# Six muted wild lagomorph coats: (flank coat, darker dorsal agouti saddle, warm nape patch)
COATS = [
    # 0 Wildbraun (classic agouti hare/rabbit)
    (['473543', '785d58', 'a88970', 'd2b796'], ['342636', '5b4448', '85685a', 'af9278'], ['56383f', '8c5c4d', 'b98463', 'dcb089']),
    # 1 Aschgrau (silver-slate moor coat)
    (['3b334a', '686178', '9894a9', 'c6c2d1'], ['2b253a', '4e485f', '78738a', 'a5a0b4'], ['493d52', '78697c', 'a595a4', 'cfc3cc']),
    # 2 Honig (warm meadow buff)
    (['593e3c', '8e6b4d', 'bc9668', 'e2c698'], ['442f33', '70513e', '9b7553', 'c49f76'], ['66423b', '9d6c49', 'c99663', 'e8be8c']),
    # 3 Dunkelbraun (deep woodland espresso-slate)
    (['231d30', '44394e', '6b5b6f', '998695'], ['191425', '32293c', '524458', '7c6a7b'], ['352536', '5c414b', '856266', 'ad8986']),
    # 4 Sand / Falb (pale fawn-sand with crisp dark ear tips)
    (['695761', '9a8784', 'c7b4a5', 'e9dac5'], ['50414d', '7c6a6b', 'a8958b', 'cfc0b0'], ['735656', 'a47f72', 'cda690', 'ebd0b8']),
    # 5 Rotbraun (russet field hare)
    (['4d2f3d', '835049', 'b57b5f', 'd9aa84'], ['392231', '643b3b', '915c4c', 'ba856a'], ['5b333a', '965748', 'c68362', 'e4b189']),
]

COAT, SADDLE, NAPE, BELLY, INNER, TAIL, DARK, EYE, GLINT, NOSE = range(10)

art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = FW, FH, 25.0, 4, 1.0
art.TIDY_EYES = False
art.DECAL_WEIGHT = {EYE: 3.4, GLINT: 4.8, NOSE: 2.2, INNER: 1.5, DARK: 1.35}
art.ink_color = lambda mat: hexc('1e1828' if mat in (EYE, DARK) else '2d2436')

BLOCKS = [
    ('idle', 0, 6),
    ('graze', 6, 8),
    ('alert', 14, 4),
    ('stand', 18, 6),
    ('hop', 24, 6),
    ('groom', 30, 6),
    ('loaf', 36, 4),
    ('thump', 40, 4),
]


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def materials(variant: int) -> None:
    coat, saddle, nape = COATS[variant]
    ramps = [
        coat,                                              # COAT
        saddle,                                            # SADDLE
        nape,                                              # NAPE
        ['786572', 'ab9795', 'dacab9', 'f4ead8'],          # BELLY / eye-ring / chin
        ['6e4a59', '9c6c76', 'c28f94', 'ddb0ae'],          # INNER ear
        ['857786', 'bdb0ba', 'ebe2dd', 'fff6ea'],          # TAIL (white-cream scut)
        ['1c1626', '312738', '4e3e50', '6f5a69'],          # DARK ear tips & pads
        ['0d0b17', '151122', '221a30', '2e233c'],          # EYE (natural dark)
        ['cfc2c9', 'e5dcdb', 'f4ece2', 'fff9ee'],          # GLINT
        ['633f4d', '895866', 'b47e86', 'd7a8ad'],          # NOSE
    ]
    art.RAMPS = [[hexc(c) for c in ramp] for ramp in ramps]


def limb(m: art.Model, p0, p1, r0: float, r1: float, mat: int, step: float = 0.4) -> None:
    m.limb(p0, p1, r0, r1, mat, step=step)


def build(variant: int, kind: str, phase: float) -> art.Model:
    m = art.Model()
    tau = math.tau
    p = phase * tau
    breath = math.sin(p)
    size = [1.0, 0.95, 0.92, 0.94, 1.03, 1.01][variant]
    ear_len = [4.45, 4.75, 4.15, 4.35, 4.65, 4.85][variant]

    # Default alert-relaxed sitting posture
    rump_y, rump_z = 4.25 * size, -2.35 * size
    chest_y, chest_z = 4.85 * size, 1.95 * size
    head_y, head_z = 8.05 * size, 3.85 * size
    head_pitch = 0.08
    head_yaw = 0.0
    head_roll = 0.0
    ear_pitch = 0.14
    ear_splay = 0.19
    ear_asym = 0.0
    blink = False
    nose_jit = 0.0
    tail_lift = 0.0

    # Limb targets (left/right symmetric unless overridden)
    fore_foot_L = np.array([-1.55 * size, 0.72, 3.05 * size])
    fore_foot_R = np.array([1.55 * size, 0.72, 3.05 * size])
    hind_foot_L = np.array([-2.35 * size, 0.78, -0.85 * size])
    hind_foot_R = np.array([2.35 * size, 0.78, -0.85 * size])
    hock_L = np.array([-2.55 * size, 2.15 * size, -3.55 * size])
    hock_R = np.array([2.55 * size, 2.15 * size, -3.55 * size])

    if kind == 'idle':
        idx = int(round(phase * 6)) % 6
        rump_y += 0.12 * breath
        chest_y += 0.16 * breath
        head_y += 0.18 * breath
        # Subtle nose twitch & independent radar ear swivel
        nose_jit = 0.18 * math.sin(p * 2.0)
        head_yaw = 0.09 * math.sin(p)
        ear_asym = 0.22 * math.sin(p + 0.7)
        blink = (idx == 4)

    elif kind == 'graze':
        # 8 frames: smooth lower (0), nibble (1,2), slight chew lift + step (3,4), dip nibble (5,6), smooth rise (7)
        idx = int(round(phase * 8)) % 8
        dip = [0.32, 0.85, 1.0, 0.58, 0.50, 0.92, 0.98, 0.38][idx]
        chew = [0.0, 0.12, -0.10, 0.16, -0.14, 0.10, -0.12, 0.0][idx]
        chest_y = (4.85 - 0.85 * dip) * size
        chest_z = (1.85 + 0.35 * dip) * size
        rump_y = (4.35 + 0.12 * dip) * size
        head_y = (8.05 - 4.15 * dip) * size + (0.18 if idx in (2, 6) else 0.0)
        head_z = (3.85 + 1.65 * dip) * size
        head_pitch = 0.08 + 0.62 * dip
        head_yaw = chew * 0.55
        ear_pitch = 0.18 + 0.52 * dip
        ear_splay = 0.22
        step_f = 0.50 * size if idx in (3, 4, 5) else 0.0
        fore_foot_L[2] += step_f
        fore_foot_R[2] -= step_f * 0.4

    elif kind == 'alert':
        # Tense freeze: braced tall forelegs, high head, locked forward radar ears
        chest_y = 5.55 * size
        head_y = 9.45 * size
        head_z = 3.55 * size
        head_pitch = -0.04
        head_yaw = 0.12 * math.sin(p)
        ear_pitch = -0.10 + 0.05 * math.sin(p)
        ear_splay = 0.14
        ear_asym = 0.12 * math.cos(p)

    elif kind == 'stand':
        # Upright "Männchen machen" lookout! 6 frames: rise (0), tall scan (1..4), lower (5)
        idx = int(round(phase * 6)) % 6
        up = [0.55, 0.96, 1.0, 1.0, 0.95, 0.50][idx]
        scan = [0.0, 0.18, 0.26, -0.22, -0.12, 0.0][idx]
        rump_y = (3.95 + 0.55 * up) * size
        rump_z = (-2.35 + 1.15 * up) * size
        chest_y = (4.85 + 4.35 * up) * size
        chest_z = (1.95 - 1.55 * up) * size
        head_y = (8.05 + 5.15 * up) * size
        head_z = (3.85 - 2.35 * up) * size
        head_pitch = 0.04 * (1.0 - up)
        head_yaw = scan
        head_roll = scan * 0.25
        ear_pitch = -0.08 + 0.06 * math.sin(p)
        ear_splay = 0.15
        # Forepaws tucked gracefully in front of the chest!
        if up > 0.4:
            fore_foot_L = np.array([-1.25 * size, chest_y - 1.15 * size, chest_z + 2.15 * size])
            fore_foot_R = np.array([1.25 * size, chest_y - 1.15 * size, chest_z + 2.15 * size])
        hind_foot_L = np.array([-2.15 * size, 0.78, 0.15 * size])
        hind_foot_R = np.array([2.15 * size, 0.78, 0.15 * size])
        hock_L = np.array([-2.35 * size, 1.85 * size, -2.25 * size])
        hock_R = np.array([2.35 * size, 1.85 * size, -2.25 * size])

    elif kind == 'hop':
        # 6 biomechanical bound phases:
        # 0 coil, 1 launch push-off, 2 airborne stretch, 3 descent reach, 4 forepaw touchdown, 5 hind gather/settle
        idx = int(round(phase * 6)) % 6
        if idx == 0:  # Deep coil
            rump_y, rump_z = 3.75 * size, -2.55 * size
            chest_y, chest_z = 3.95 * size, 1.85 * size
            head_y, head_z = 6.95 * size, 3.85 * size
            ear_pitch = 0.42
            hind_foot_L[2] = hind_foot_R[2] = -0.35 * size
            fore_foot_L[2] = fore_foot_R[2] = 2.65 * size
        elif idx == 1:  # Explosive launch (hindlegs kicked straight back!)
            rump_y, rump_z = 4.85 * size, -1.65 * size
            chest_y, chest_z = 6.05 * size, 2.85 * size
            head_y, head_z = 8.75 * size, 4.95 * size
            head_pitch = -0.10
            ear_pitch = 0.72
            tail_lift = 0.5
            hock_L = np.array([-2.15 * size, 3.15 * size, -4.65 * size])
            hock_R = np.array([2.15 * size, 3.15 * size, -4.65 * size])
            hind_foot_L = np.array([-1.95 * size, 1.15 * size, -7.25 * size])
            hind_foot_R = np.array([1.95 * size, 1.15 * size, -7.25 * size])
            fore_foot_L = np.array([-1.45 * size, 3.35 * size, 5.35 * size])
            fore_foot_R = np.array([1.45 * size, 3.35 * size, 5.35 * size])
        elif idx == 2:  # Full airborne suspension (arched athletic hare bound)
            rump_y, rump_z = 5.45 * size, -2.15 * size
            chest_y, chest_z = 5.65 * size, 2.75 * size
            head_y, head_z = 8.15 * size, 5.15 * size
            head_pitch = 0.04
            ear_pitch = 0.88
            tail_lift = 0.55
            hock_L = np.array([-2.0 * size, 3.85 * size, -5.05 * size])
            hock_R = np.array([2.0 * size, 3.85 * size, -5.05 * size])
            hind_foot_L = np.array([-1.8 * size, 2.45 * size, -7.45 * size])
            hind_foot_R = np.array([1.8 * size, 2.45 * size, -7.45 * size])
            fore_foot_L = np.array([-1.35 * size, 3.05 * size, 5.65 * size])
            fore_foot_R = np.array([1.35 * size, 3.05 * size, 5.65 * size])
        elif idx == 3:  # Descent reach (forelegs reaching down, hindlegs pulling under)
            rump_y, rump_z = 5.35 * size, -2.15 * size
            chest_y, chest_z = 4.45 * size, 2.75 * size
            head_y, head_z = 6.95 * size, 5.05 * size
            head_pitch = 0.18
            ear_pitch = 0.78
            tail_lift = 0.45
            hock_L = np.array([-2.35 * size, 3.45 * size, -3.25 * size])
            hock_R = np.array([2.35 * size, 3.45 * size, -3.25 * size])
            hind_foot_L = np.array([-2.15 * size, 2.35 * size, -1.15 * size])
            hind_foot_R = np.array([2.15 * size, 2.35 * size, -1.15 * size])
            fore_foot_L = np.array([-1.45 * size, 1.35 * size, 5.25 * size])
            fore_foot_R = np.array([1.45 * size, 1.35 * size, 5.25 * size])
        elif idx == 4:  # Forepaw touchdown & hind-leg overreach!
            rump_y, rump_z = 4.65 * size, -1.35 * size
            chest_y, chest_z = 3.95 * size, 2.15 * size
            head_y, head_z = 6.85 * size, 4.35 * size
            head_pitch = 0.14
            ear_pitch = 0.48
            fore_foot_L = np.array([-1.45 * size, 0.72, 3.65 * size])
            fore_foot_R = np.array([1.45 * size, 0.72, 3.65 * size])
            hock_L = np.array([-2.55 * size, 2.25 * size, -1.85 * size])
            hock_R = np.array([2.55 * size, 2.25 * size, -1.85 * size])
            hind_foot_L = np.array([-2.35 * size, 0.95, 1.15 * size])
            hind_foot_R = np.array([2.35 * size, 0.95, 1.15 * size])
        else:  # 5 Settle
            rump_y, rump_z = 4.10 * size, -2.25 * size
            chest_y, chest_z = 4.45 * size, 1.95 * size
            head_y, head_z = 7.65 * size, 3.85 * size
            ear_pitch = 0.24

    elif kind == 'groom':
        # 6 frames: sit up (0), lick paws (1), scrub face (2,3), stroke ear (4), settle (5)
        idx = int(round(phase * 6)) % 6
        sit = [0.45, 0.90, 1.0, 1.0, 0.92, 0.42][idx]
        rump_y = 4.15 * size
        rump_z = (-2.35 + 0.55 * sit) * size
        chest_y = (4.85 + 2.35 * sit) * size
        chest_z = (1.95 - 1.05 * sit) * size
        head_y = (8.05 + 1.85 * sit - (0.35 if idx in (1, 2, 3) else 0.0)) * size
        head_z = (3.85 - 1.15 * sit) * size
        head_pitch = 0.22 if idx in (1, 2, 3) else (0.18 if idx == 4 else 0.08)
        head_roll = 0.24 if idx == 4 else 0.0
        ear_pitch = 0.20 if idx != 4 else 0.30
        blink = idx in (2, 3)
        scrub = 0.42 * math.sin(p * 2.0)
        if idx in (1, 2, 3):
            fore_foot_L = np.array([-1.15 * size, head_y - 0.85 * size + scrub, head_z + 2.05 * size])
            fore_foot_R = np.array([1.15 * size, head_y - 0.85 * size - scrub, head_z + 2.05 * size])
        elif idx == 4:
            fore_foot_L = np.array([-1.35 * size, head_y + 0.45 * size, head_z + 1.55 * size])
            fore_foot_R = np.array([1.15 * size, chest_y - 0.55 * size, chest_z + 1.95 * size])
        else:
            fore_foot_L = np.array([-1.35 * size, chest_y - 1.35 * size, chest_z + 1.95 * size])
            fore_foot_R = np.array([1.35 * size, chest_y - 1.35 * size, chest_z + 1.95 * size])

    elif kind == 'loaf':
        # Tucked calm loafing / dozing low in the grass
        idx = int(round(phase * 4)) % 4
        rump_y, rump_z = (3.45 + 0.08 * breath) * size, -2.15 * size
        chest_y, chest_z = (3.35 + 0.10 * breath) * size, 1.85 * size
        head_y, head_z = (6.15 + 0.10 * breath) * size, 3.65 * size
        head_pitch = 0.14
        ear_pitch = 1.08 + 0.04 * breath
        ear_splay = 0.26
        blink = idx in (1, 2, 3)
        # Paws tucked neatly beneath breast
        fore_foot_L = np.array([-1.35 * size, 1.25 * size, 2.35 * size])
        fore_foot_R = np.array([1.35 * size, 1.25 * size, 2.35 * size])
        hock_L = np.array([-2.45 * size, 1.75 * size, -3.05 * size])
        hock_R = np.array([2.45 * size, 1.75 * size, -3.05 * size])
        hind_foot_L = np.array([-2.15 * size, 0.85, -0.65 * size])
        hind_foot_R = np.array([2.15 * size, 0.85, -0.65 * size])

    elif kind == 'thump':
        # Alarm hindfoot stamp! 0 lift, 1 high cock, 2 sharp ground slam, 3 alert rebound
        idx = int(round(phase * 4)) % 4
        chest_y = 5.15 * size
        head_y = 9.05 * size
        head_z = 3.65 * size
        ear_pitch = -0.08
        ear_splay = 0.15
        if idx in (0, 1):
            lift = 1.45 if idx == 0 else 2.85
            hock_R = np.array([2.55 * size, (2.45 + lift * 0.55) * size, -2.55 * size])
            hind_foot_R = np.array([2.55 * size, 0.85 + lift * size, 0.75 * size])
        elif idx == 2:
            rump_y = 3.85 * size
            hind_foot_R = np.array([2.55 * size, 0.62, 0.35 * size])

    # ---- Smooth seamless spine chain (prevents depth-discontinuity ink creases across fur) ----
    for u in (0.0, 0.25, 0.50, 0.75, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz = rump_z + (chest_z - rump_z) * u
        rx = (3.30 - 0.32 * u) * size
        ry = (3.35 - 0.42 * u) * size
        rz = (3.45 - 0.45 * u) * size
        m.ell((0.0, sy, sz), (rx, ry, rz), COAT)
        if 0.15 <= u <= 0.85:
            m.ell((0.0, sy + 0.95 * size, sz - 0.15 * size), (rx * 0.76, ry * 0.62, rz * 0.85), SADDLE)

    # Soft cream chest & belly
    mid_y = 0.50 * rump_y + 0.50 * chest_y
    mid_z = 0.50 * rump_z + 0.50 * chest_z
    m.ell((0.0, chest_y - 0.45 * size, chest_z + 1.15 * size), (2.25 * size, 2.15 * size, 2.05 * size), BELLY)
    m.ell((0.0, mid_y - 1.35 * size, mid_z + 0.25 * size), (2.35 * size, 1.55 * size, 3.25 * size), BELLY)

    # Warm rufous nape / neck bridge connecting shoulders to cranium
    for u in (0.35, 0.68):
        ny = chest_y + (head_y - chest_y) * u
        nz = chest_z + (head_z - chest_z) * u - 0.45 * size
        m.ell((0.0, ny, nz), (2.05 * size, 1.95 * size, 1.95 * size), NAPE)

    # Scut (tail): dark upper root, bright fluffy cream-white underside/tip
    tail_z = rump_z - 3.25 * size
    tail_y = rump_y + (0.35 + tail_lift) * size
    m.ell((0.0, tail_y + 0.55 * size, tail_z + 0.35 * size), (1.10 * size, 1.00 * size, 1.10 * size), DARK)
    m.ell((0.0, tail_y - 0.10 * size, tail_z - 0.20 * size), (1.55 * size, 1.50 * size, 1.45 * size), TAIL)

    # ---- Articulated Hind Legs (haunch -> hock -> long metatarsal pes) & Slender Forelegs ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        hf = hind_foot_L if s_idx == 0 else hind_foot_R
        hk = hock_L if s_idx == 0 else hock_R
        ff = fore_foot_L if s_idx == 0 else fore_foot_R

        hip = np.array([side * 1.78 * size, rump_y - 0.35 * size, rump_z + 0.35 * size])
        m.ell(hip, (1.62 * size, 2.10 * size, 2.35 * size), COAT)
        limb(m, hip, hk, 1.30 * size, 0.90 * size, COAT, step=0.42)
        limb(m, hk, hf, 0.88 * size, 0.78 * size, BELLY, step=0.38)
        pes_dir = hf - hk
        pes_yaw = math.atan2(pes_dir[0], max(abs(pes_dir[2]), 0.4)) * 0.25
        m.ell(hf + np.array([0.0, 0.0, 0.52 * size]), (0.95 * size, 0.72 * size, 1.50 * size), BELLY, R=art.rot_y(pes_yaw))

        # Foreleg: shoulder -> elbow/wrist -> forepaw
        sh = np.array([side * 1.52 * size, chest_y - 0.42 * size, chest_z + 0.55 * size])
        mid_fore = 0.5 * (sh + ff) + np.array([0.0, 0.15 * size, -0.20 * size])
        limb(m, sh, mid_fore, 1.00 * size, 0.80 * size, COAT, step=0.36)
        limb(m, mid_fore, ff, 0.80 * size, 0.72 * size, BELLY, step=0.36)
        m.ell(ff, (0.84 * size, 0.68 * size, 1.12 * size), BELLY)

    # ---- Sculpted Lagomorph Head, Cheeks, Muzzle, Eye-Ring & Long Black-Tipped Ears ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([0.0, head_y, head_z])

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ (np.array([x, y, z]) * size)

    # Cranium + crown saddle + cheek jowls + tapered snout bridge + pale muzzle + rose nose
    m.ell(hp(0.0, 0.0, 0.0), (2.40 * size, 2.35 * size, 2.65 * size), COAT, R=h_rot)
    m.ell(hp(0.0, 0.92, -0.15), (1.80 * size, 1.30 * size, 2.10 * size), SADDLE, R=h_rot)
    for side in (-1.0, 1.0):
        m.ell(hp(side * 1.25, -0.42, 0.75), (1.30 * size, 1.30 * size, 1.60 * size), COAT, R=h_rot)
    # Roman nose bridge & pale whisker pads
    m.ell(hp(0.0, -0.18, 1.95), (1.50 * size, 1.32 * size, 1.62 * size), COAT, R=h_rot)
    m.ell(hp(0.0, -0.80, 2.15), (1.62 * size, 1.02 * size, 1.32 * size), BELLY, R=h_rot)
    m.ell(hp(0.0, -0.40 + nose_jit, 3.20), (0.58 * size, 0.46 * size, 0.46 * size), NOSE, R=h_rot)

    for side in (-1.0, 1.0):
        # Pale spectacle / eye-ring subtly frames the dark eye so it reads crisply on every coat
        m.ell(hp(side * 1.72, 0.44, 1.08), (0.68 * size, 0.90 * size, 0.98 * size), BELLY, R=h_rot)
        eye_h = 0.18 if blink else 0.74
        m.ell(hp(side * 1.88, 0.46, 1.18), (0.58 * size, eye_h * size, 0.68 * size), EYE, R=h_rot)
        if not blink:
            m.ell(hp(side * 1.96, 0.69, 1.50), (0.24 * size, 0.25 * size, 0.24 * size), GLINT, R=h_rot)

        # Long sculpted lagomorph ears ("Löffel") with concave inner hollow and crisp black tips
        e_pitch = ear_pitch + (ear_asym if side < 0 else -ear_asym * 0.6)
        if kind == 'groom' and int(round(phase * 6)) % 6 == 4 and side < 0:
            e_pitch = 1.15  # pulled forward/down while grooming ear
        splay = side * ear_splay + (0.12 if side < 0 and variant in (2, 5) else 0.0)
        swivel = side * (0.32 + 0.15 * ear_asym)
        e_rot = h_rot @ art.rot_y(swivel) @ art.rot_x(e_pitch) @ rot_z(-splay)

        ebase = hp(side * 1.12, 1.65, -0.68)
        emid = ebase + e_rot @ np.array([0.0, ear_len * 0.50 * size, 0.0])
        etip = ebase + e_rot @ np.array([0.0, ear_len * 0.96 * size, 0.0])

        # Outer ear blade (narrower stalk -> broader mid-spoon -> tapered dark tip)
        m.ell(ebase + e_rot @ np.array([0.0, ear_len * 0.24 * size, 0.0]), (0.78 * size, ear_len * 0.36 * size, 0.58 * size), COAT, R=e_rot)
        m.ell(emid, (1.02 * size, ear_len * 0.48 * size, 0.62 * size), COAT, R=e_rot)
        # Inner ear channel
        m.ell(ebase + e_rot @ np.array([0.0, ear_len * 0.46 * size, 0.42 * size]), (0.52 * size, ear_len * 0.36 * size, 0.24 * size), INNER, R=e_rot)
        # Signature black/dark wild hare ear tip!
        m.ell(etip, (0.76 * size, ear_len * 0.22 * size, 0.52 * size), DARK, R=e_rot)

    return m


def pose_for_col(col: int) -> tuple[str, float]:
    for kind, start, count in BLOCKS:
        if start <= col < start + count:
            return kind, (col - start) / count
    return 'idle', 0.0


def frame(variant: int, sector: int, col: int) -> list:
    kind, phase = pose_for_col(col)
    materials(variant)
    model = build(variant, kind, phase)
    depth, code = art.render(model.transform(math.pi / 2.0 - sector * math.pi / 4.0, 0.0))
    px = art.to_pixels(depth, code)
    # Keep the shadow separate at runtime, so it stays on the ground during airborne frames.
    return [[CLEAR if c[3] < 255 else c for c in row] for row in px]


def main() -> None:
    picks = [
        (0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (6, 0),   # facings E, SE, S, SW, W, N
        (0, 7), (0, 14), (1, 20), (0, 25), (0, 26), (1, 32), (0, 37), (0, 41),  # graze, alert, stand, launch, fly, groom, loaf, thump
    ]
    preview = np.zeros((VARIANTS * FH, len(picks) * FW, 4), dtype=np.uint8)
    preview_only = '--preview-only' in sys.argv
    sheet = None if preview_only else np.zeros((VARIANTS * 8 * FH, COLS * FW, 4), dtype=np.uint8)
    pick_set = set(picks)
    for variant in range(VARIANTS):
        for sector in range(8):
            for col in range(COLS):
                if preview_only and (sector, col) not in pick_set:
                    continue
                px = np.asarray(frame(variant, sector, col), dtype=np.uint8)
                if sheet is not None:
                    y = (variant * 8 + sector) * FH
                    x = col * FW
                    sheet[y:y + FH, x:x + FW] = px
                if (sector, col) in pick_set:
                    x = picks.index((sector, col)) * FW
                    y = variant * FH
                    preview[y:y + FH, x:x + FW] = px
        print('Rabbit variant', variant + 1, '/', VARIANTS, flush=True)
    from world_data import save_png
    if sheet is not None:
        save_png(ROOT / 'assets/wildlife/rabbit.png', sheet)
    save_png(ROOT / 'docs/img/rabbits.png', preview)


if __name__ == '__main__':
    main()
