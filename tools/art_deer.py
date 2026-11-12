#!/usr/bin/env python3
"""European Roe Deer (Capreolus capreolus) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 4 builds x 8 true facings = 32 rows. No emissive parts.
Builds:
  0: Sommer-Ricke (warm rufous-chestnut doe)
  1: Sechser-Rehbock (russet-umber buck with pearled 6-point antlers)
  2: Rehkitz (0.73x spotted fawn)
  3: Nebelwald-Ricke (cool ash-slate grey-brown winter/mist doe)
Columns (52):
  idle 0:4, forage 4:12, walk 12:20, alert 20:24, run 24:32 (bounding/stotting),
  groom 32:36, sleep 36:40 (folded-leg woodland bed), special 40:46 (Schrecken bark + stamp),
  stand_up 46:52 (cervid rump-first rise from bed).
Usage: py -3 tools/art_deer.py [--preview-only] [--qa=path.png]
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

COAT, CREAM, DARK, NOSE_EYE, GLINT, INNER_EAR, ANTLER = range(7)

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

COATS = [
    # 0 Sommer-Ricke: rich warm rufous-chestnut
    ['4a2926', '804837', 'b56c49', 'de9868'],
    # 1 Sechser-Rehbock: deeper russet-umber
    ['422624', '744234', 'a66446', 'd18e62'],
    # 2 Rehkitz: warm golden-chestnut fawn
    ['502e28', '89503b', 'be7650', 'e6a574'],
    # 3 Nebelwald-Ricke: cool slate-ash winter/mist coat
    ['36323a', '5d565d', '887f82', 'b6aba6'],
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {NOSE_EYE: 3.4, GLINT: 4.6, INNER_EAR: 1.8, CREAM: 1.15, ANTLER: 1.9}
    art.ink_color = lambda mat: hexc('191522' if mat in (DARK, NOSE_EYE) else '29202c')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def smooth(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    cream = ['8c7e7b', 'b8a89f', 'e2d5c8', 'fbf3e8']
    if v == 3:
        cream = ['7e7a80', 'aba6aa', 'd7d2d2', 'f5f2f0']
    ramps = [
        COATS[v % BUILDS_N],                                # 0 COAT
        cream,                                              # 1 CREAM (throat, belly, Spiegel, fawn spots)
        ['1c1824', '302938', '4e4252', '726170'],           # 2 DARK (hooves, muzzle band, ear rim)
        ['0b0b14', '141422', '222133', '333146'],           # 3 NOSE_EYE
        ['9ca0a6', 'c5c8cc', 'e6e8ea', 'fcfdfd'],           # 4 GLINT
        ['584048', '886368', 'b58b8c', 'dcc0bc'],           # 5 INNER_EAR
        ['4f3d32', '7e644f', 'b39474', 'e3cca8'],           # 6 ANTLER (pearled warm brown-to-ivory bone)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_deer_legs(
    m: art.Model,
    t: float,
    rear_y: float,
    front_y: float,
    kind: str,
    s: float,
    graze_step: float,
    stamp_lift: float,
    rise_k: float,
) -> None:
    """Articulated 3-segment cervid limbs: muscled upper haunch/shoulder -> hock/carpus -> slender cannon -> cloven hoof."""
    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (2.25 if front else 2.45) * s
            hip_z = (5.0 if front else -5.4) * s
            hip_y = (front_y if front else rear_y) - 0.55 * s
            r_cannon = max(0.66, 0.78 * s)

            # Bedded folded legs (sleep or early stand_up)
            bed_blend = 1.0 if kind == 'sleep' else (1.0 - rise_k if kind == 'stand_up' else 0.0)
            if bed_blend >= 0.999:
                # Realistic folded cervid legs tucked beside/under torso — no ball stumps!
                tuck_side = side * (0.85 if side > 0 else 0.65)
                root = np.array([hip_x * 0.92, hip_y + 0.4 * s, hip_z * 0.88])
                if front:
                    carpus = np.array([tuck_side * 2.5 * s, 2.2 * s, (hip_z + 2.6 * s)])
                    hoof = np.array([tuck_side * 1.8 * s, 1.3 * s, (hip_z - 1.6 * s)])
                    m.limb(root, carpus, r_cannon * 1.45, r_cannon * 1.02, COAT, step=0.4)
                    m.limb(carpus, hoof, r_cannon * 0.95, r_cannon * 0.78, COAT, step=0.4)
                    m.ell(hoof, (r_cannon * 0.85, 0.65 * s, 0.95 * s), DARK)
                else:
                    hock = np.array([tuck_side * 2.9 * s, 2.3 * s, (hip_z - 2.1 * s)])
                    hoof = np.array([tuck_side * 2.3 * s, 1.3 * s, (hip_z + 2.4 * s)])
                    m.limb(root, hock, r_cannon * 1.65, r_cannon * 1.08, COAT, step=0.4)
                    m.limb(hock, hoof, r_cannon * 0.98, r_cannon * 0.78, COAT, step=0.4)
                    m.ell(hoof, (r_cannon * 0.85, 0.65 * s, 0.95 * s), DARK)
                continue

            swing = 0.0
            lift = 0.0
            hock_flex = 0.0

            if kind == 'walk':
                # Graceful 4-beat lateral-sequence walk: LH(0.0), LF(0.25), RH(0.5), RF(0.75)
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.64
                if cyc < stance:
                    c = cyc / stance
                    swing = (2.6 * s) * (1.0 - 2.0 * c)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(2.6 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * (2.4 if front else 1.9) * s
                    hock_flex = math.sin(c * math.pi) * 1.1 * s
            elif kind == 'run':
                # True roe-deer bounding gait: paired hind push + paired fore reach with slight lead offset
                lead = 0.07 if side > 0 else -0.07
                cyc = (t + (0.46 if front else 0.0) + lead) % 1.0
                airborne = math.sin(t * math.pi)
                if front:
                    # Forelegs tuck up on launch (t~0.15..0.45), reach far forward on descent (t~0.5..0.8), push back
                    ang = cyc * math.tau
                    swing = (4.6 * s) * math.sin(ang - 0.4)
                    lift = max(0.0, math.sin(t * math.pi) * 3.4 * s + max(0.0, math.cos(ang)) * 1.6 * s)
                    hock_flex = max(0.0, -math.sin(ang)) * 1.8 * s
                else:
                    # Hindlegs extend powerfully backward on launch (t~0.1..0.4), then gather forward on recovery
                    ang = cyc * math.tau
                    swing = -(5.0 * s) * math.sin(ang - 0.25)
                    lift = max(0.0, airborne * 2.8 * s + max(0.0, -math.cos(ang)) * 1.5 * s)
                    hock_flex = max(0.0, math.cos(ang)) * 1.6 * s
            elif kind == 'forage' and front and side > 0:
                # Subtle forward browse stance step on right foreleg
                swing = 1.6 * s * graze_step
            elif kind == 'special' and front and side > 0:
                # Forehoof warning stamp during Schrecken!
                lift = stamp_lift * s
                swing = 1.5 * s * (1.0 if stamp_lift > 0.2 else 0.4)
                hock_flex = stamp_lift * 0.45 * s
            elif kind == 'stand_up':
                # Cervids push rump up first while forelegs are still kneeling, then unfold forelegs
                if front and rise_k < 0.55:
                    kneel = 1.0 - smooth(rise_k / 0.55)
                    lift = 0.0
                    swing = -1.8 * s * kneel
                    hock_flex = 2.2 * s * kneel

            root = np.array([hip_x, hip_y, hip_z])
            foot_y = max(0.85 * s, 0.85 * s + lift)
            foot = np.array([hip_x * (0.94 if front else 0.96), foot_y, hip_z + swing])

            if front:
                # Scapula/humerus -> carpus (subtle forward knee) -> cannon -> cloven hoof
                elbow = np.array([hip_x * 0.96, hip_y - 3.0 * s, hip_z - 0.7 * s + swing * 0.18])
                carpus = np.array([
                    hip_x * 0.95,
                    foot_y + (hip_y - foot_y) * 0.44 + hock_flex * 0.4,
                    hip_z + swing * 0.55 + (0.65 * s if lift > 0.4 else 0.15 * s) + hock_flex * 0.55,
                ])
                m.limb(root, elbow, r_cannon * 1.75, r_cannon * 1.28, COAT, step=0.42)
                m.limb(elbow, carpus, r_cannon * 1.22, r_cannon * 0.94, COAT, step=0.4)
                m.limb(carpus, foot, r_cannon * 0.90, r_cannon * 0.74, COAT, step=0.38)
            else:
                # Muscular haunch/thigh -> stifle -> backward-angled hock -> slender cannon -> hoof
                stifle = np.array([hip_x * 1.02, hip_y - 2.8 * s, hip_z + 1.1 * s + swing * 0.22])
                hock = np.array([
                    hip_x * 0.97,
                    foot_y + (hip_y - foot_y) * 0.45 + hock_flex * 0.35,
                    hip_z + swing * 0.42 - (1.85 * s - hock_flex * 0.35),
                ])
                m.limb(root, stifle, r_cannon * 2.05, r_cannon * 1.42, COAT, step=0.42)
                m.limb(stifle, hock, r_cannon * 1.35, r_cannon * 0.96, COAT, step=0.4)
                m.limb(hock, foot, r_cannon * 0.90, r_cannon * 0.74, COAT, step=0.38)

            # Distinct dark cloven hoof
            m.ell(foot + np.array([0.0, 0.0, 0.22 * s]), (r_cannon * 0.88, 0.68 * s, 1.08 * s), DARK)


def build_deer(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    fawn = (v == 2)
    buck = (v == 1)
    s = 0.73 if fawn else 1.0
    p = t * math.tau
    b = math.sin(p)

    # Base heights: Roe deer authentically stand slightly higher at the croup than at the withers!
    stand_rear = 16.4 * s
    stand_front = 15.8 * s

    rear_y = stand_rear
    front_y = stand_front
    graze = 0.0
    graze_step = 0.0
    groom = 0.0
    alert_flare = 0.0
    bark_open = 0.0
    stamp_lift = 0.0
    rise_k = 1.0

    if kind == 'idle':
        rear_y += 0.14 * b * s
        front_y += 0.16 * b * s
    elif kind == 'forage':
        idx = int(t * 8) % 8
        graze = [0.08, 0.52, 0.92, 1.0, 0.96, 1.0, 0.62, 0.15][idx]
        graze_step = [0.2, 0.7, 1.0, 1.0, 1.0, 1.0, 0.7, 0.2][idx]
        front_y -= 0.45 * graze * s
    elif kind == 'walk':
        bob = 0.24 * math.cos(p * 2.0) * s
        rear_y += bob
        front_y += 0.24 * math.cos(p * 2.0 - 0.6) * s
    elif kind == 'alert':
        alert_flare = 1.0
        front_y += 0.35 * s
        rear_y += 0.15 * s
    elif kind == 'run':
        # True bounding arc inside the 8-frame gait + body pitch wave
        arc = math.sin(t * math.pi)
        pitch_wave = math.sin(p)
        lift_body = (3.4 * arc) * s
        rear_y += lift_body - 0.9 * pitch_wave * s
        front_y += lift_body + 1.1 * pitch_wave * s
        alert_flare = 1.0
    elif kind == 'groom':
        groom = [0.25, 0.85, 1.0, 0.45][int(t * 4) % 4]
    elif kind == 'sleep':
        rear_y = 5.6 * s
        front_y = 5.8 * s
        rear_y += 0.12 * b * s
        front_y += 0.12 * b * s
    elif kind == 'special':
        # Schrecken: stamp forehoof + recoil bark + flared white Spiegel!
        idx = int(t * 6) % 6
        stamp_lift = [4.0, 0.0, 0.0, 0.0, 0.8, 0.0][idx]
        bark_open = [0.25, 1.0, 0.90, 0.55, 0.2, 0.0][idx]
        front_y += (0.65 if idx == 0 else (0.35 if idx in (1, 2) else 0.2)) * s
        alert_flare = 1.0
    elif kind == 'stand_up':
        rise_k = smooth((t * 6.0 + 0.5) / 6.0)
        # Rump rises slightly ahead of forequarters (authentic cervid rising!)
        rump_k = smooth(min(1.0, rise_k * 1.22))
        fore_k = smooth(max(0.0, (rise_k - 0.16) / 0.84))
        rear_y = (5.6 + (16.4 - 5.6) * rump_k) * s
        front_y = (5.8 + (15.8 - 5.8) * fore_k) * s

    # Seamless 9-ellipsoid spine chain rotated along body slope -> zero interior ink cuts even on steep bounds/stand_up!
    spine_slope = math.atan2(front_y - rear_y, 9.7 * s)
    R_spine = art.rot_x(-spine_slope)
    for i in range(9):
        u = i / 8.0
        sz = -5.3 + 9.9 * u
        arch = math.sin(u * math.pi)
        sy = rear_y * (1.0 - u) + front_y * u + (0.25 * (1.0 - u) - 0.12 * u) * s
        rx_r = (3.35 + 0.38 * arch - 0.22 * u) * s
        ry_r = (3.75 + 0.52 * arch - 0.18 * u) * s
        rz_r = (2.85 + 0.65 * arch) * s
        m.ell((0.0, sy, sz * s), (rx_r, ry_r, rz_r), COAT, R=R_spine)

    # Pale cream belly & lower brisket seamlessly blended under ribcage
    for u_b in (0.18, 0.42, 0.66, 0.86):
        bz = -5.0 + 9.2 * u_b
        by_b = rear_y * (1.0 - u_b) + front_y * u_b - 2.35 * s
        m.ell((0.0, by_b, bz * s), (2.72 * s, 1.80 * s, 2.75 * s), CREAM, R=R_spine)

    # Iconic white rump mirror (Spiegel): compact heart/kidney patch at rest, flares bright & wide in alert/bark/bound!
    spiegel_w = (2.35 + 0.95 * alert_flare) * s
    spiegel_h = (2.30 + 0.65 * alert_flare) * s
    m.ell((0.0, rear_y - 0.35 * s, -7.85 * s), (spiegel_w, spiegel_h, 1.05 * s), CREAM)
    # Tiny roe-deer vestigial tail tuft above the Spiegel
    m.ell((0.0, rear_y + 1.25 * s, -8.15 * s), (0.85 * s, 0.95 * s, 0.85 * s), COAT)

    # Fawn longitudinal cream spot rows along dorsal flanks
    if fawn:
        for side in (-1.0, 1.0):
            for row_y, zs in ((1.35, (-5.2, -3.1, -1.0, 1.1, 3.1)), (-0.15, (-4.2, -2.0, 0.2, 2.3))):
                for z_pos in zs:
                    sy = rear_y * (0.5 - z_pos / 14.0) + front_y * (0.5 + z_pos / 14.0)
                    m.ell((side * 3.25 * s, sy + row_y * s, z_pos * s), (0.56 * s, 0.44 * s, 0.62 * s), CREAM)

    # Graceful S-tapered neck (Träger) & delicate wedge head
    neck_thick = 1.12 if buck else 1.0
    hy = front_y + 11.0 * s
    hz = 9.5 * s
    pitch = 0.12
    yaw = 0.0
    roll = 0.0

    if kind == 'forage':
        chew_yaw = 0.12 * math.sin(p * 2.0) * graze
        hy = front_y + (11.0 - 21.5 * graze) * s
        hz = (9.5 + 6.4 * graze) * s
        pitch = 0.12 + 0.86 * graze
        yaw = chew_yaw
    elif kind == 'alert':
        hy = front_y + (13.2 + 0.22 * b) * s
        hz = 8.6 * s
        pitch = 0.05
    elif kind == 'walk':
        hy = front_y + (10.7 - 0.35 * math.sin(p * 2.0)) * s
        hz = (9.8 + 0.35 * math.cos(p * 2.0)) * s
        pitch = 0.14
    elif kind == 'run':
        hy = front_y + (10.8 + 0.8 * math.sin(p)) * s
        hz = (10.2 + 0.7 * math.cos(p)) * s
        pitch = 0.08 - 0.12 * math.sin(p)
    elif kind == 'groom':
        hy = front_y + (8.6 - 1.6 * groom) * s
        hz = (8.8 - 5.8 * groom) * s
        yaw = 1.25 * groom
        pitch = 0.12 + 0.38 * groom
        roll = -0.18 * groom
    elif kind == 'sleep':
        hy = front_y + (9.2 - 0.25 * b) * s
        hz = 7.4 * s
        pitch = 0.18
        yaw = 0.18
    elif kind == 'special':
        hy = front_y + (12.4 + 1.0 * bark_open) * s
        hz = (9.1 + 1.3 * bark_open) * s
        pitch = 0.04 - 0.15 * bark_open
    elif kind == 'stand_up':
        hy = front_y + (9.2 + 1.8 * rise_k) * s
        hz = (7.4 + 2.1 * rise_k) * s
        pitch = 0.24 * (1.0 - rise_k) + 0.12

    head = np.array([math.sin(yaw) * 1.4 * s, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * s)

    def head_ell(pos: tuple[float, float, float], r: tuple[float, float, float], mat: int, R_extra: np.ndarray | None = None) -> None:
        m.ell(hp(*pos), tuple(a * s for a in r), mat, R=rot if R_extra is None else rot @ R_extra)

    # Smooth shoulder-to-neck collar bridge + curved S-neck chain
    neck_base = np.array([0.0, front_y + 0.85 * s, 4.9 * s])
    throat_top = hp(0.0, -1.25, -1.55)
    neck_mid = 0.52 * neck_base + 0.48 * throat_top + np.array([0.0, -0.55 * (1.0 - graze) * s, -0.45 * (1.0 - graze) * s])
    m.ell(neck_base + np.array([0.0, -0.3 * s, -0.4 * s]), (2.55 * neck_thick * s, 2.85 * s, 2.35 * s), COAT)
    m.limb(neck_base, neck_mid, 2.35 * neck_thick * s, 1.82 * neck_thick * s, COAT, step=0.42)
    m.limb(neck_mid, throat_top, 1.82 * neck_thick * s, 1.38 * s, COAT, step=0.42)
    # Pale throat bib patch (Kehlmarke) common on roe deer
    m.ell(throat_top + rot @ np.array([0.0, -0.35 * s, 1.05 * s]), (0.95 * s, 1.15 * s, 0.95 * s), CREAM, R=rot)

    # Delicate tapered cervid cranium + slender bridge + dark muzzle band + wet black nose pad
    head_ell((0.0, 0.1, -0.15), (2.05, 2.25, 2.65), COAT)
    head_ell((0.0, -0.55, 1.95), (1.32, 1.18, 1.85), COAT)
    head_ell((0.0, -0.82, 3.25), (1.02, 0.82, 1.05), DARK)
    head_ell((0.0, -0.68, 3.95), (0.68, 0.56, 0.58), NOSE_EYE)

    # Lower jaw & chin (drops open during Schrecken bark!)
    jaw_drop = 0.85 * bark_open
    if bark_open > 0.25:
        head_ell((0.0, -1.25 - jaw_drop * 0.45, 2.65), (0.72, 0.45, 1.15), NOSE_EYE)
    head_ell((0.0, -1.25 - jaw_drop, 2.85), (0.92, 0.52, 1.45), CREAM)

    # Blink on last frame of idle or drowsy half-closed in sleep
    blink = (kind == 'idle' and t >= 0.75) or (kind == 'sleep' and int(t * 4) % 4 in (1, 2))

    for side in (-1.0, 1.0):
        # Large expressive radar ears (Lauscher) with dark outer rim & warm pale inner pinna
        ear_swivel = 0.0
        ear_splay = 0.52
        ear_fwd = 0.12
        if kind == 'alert' or kind == 'special':
            ear_splay = 0.36
            ear_fwd = 0.34
        elif kind == 'run':
            ear_splay = 0.62
            ear_fwd = -0.22
        elif kind == 'sleep':
            ear_splay = 0.78
            ear_fwd = -0.18
        else:
            ear_swivel = 0.14 * math.sin(p + (0.9 if side > 0 else -0.4))
        R_ear = rot_z(-side * (ear_splay + ear_swivel)) @ art.rot_x(ear_fwd)
        head_ell((side * 1.85, 2.55, -0.95), (0.92, 2.85, 0.58), DARK, R_ear)
        head_ell((side * 1.82, 2.45, -0.88), (0.78, 2.55, 0.52), COAT, R_ear)
        head_ell((side * 1.80, 2.45, -0.52), (0.48, 1.95, 0.24), INNER_EAR, R_ear)

        # Expressive dark eye + orbital brow + crisp top-left glint
        head_ell((side * 1.72, 0.38, 0.85), (0.45, 0.16 if blink else 0.54, 0.52), NOSE_EYE)
        if not blink:
            head_ell((side * 1.84, 0.58, 1.05), (0.18, 0.19, 0.16), GLINT)

        # Build 1: Sechser-Rehbock pearled 6-point antler rack (coronet burr + main beam + brow tine + rear fork)
        if buck:
            pedicle = hp(side * 0.92, 2.00, -0.65)
            burr = hp(side * 1.05, 2.55, -0.72)
            mid_beam = hp(side * 1.65, 5.55, -1.20)
            top_beam = hp(side * 1.90, 8.65, -0.85)
            brow_tip = hp(side * 1.48, 6.85, 1.35)
            back_tip = hp(side * 2.55, 7.75, -2.65)
            m.ell(burr, (0.85 * s, 0.56 * s, 0.85 * s), DARK, R=rot)
            m.limb(pedicle, mid_beam, 0.72 * s, 0.60 * s, ANTLER, step=0.32)
            m.limb(mid_beam, top_beam, 0.58 * s, 0.42 * s, ANTLER, step=0.32)
            m.limb(mid_beam, brow_tip, 0.50 * s, 0.36 * s, ANTLER, step=0.32)
            m.limb(0.35 * mid_beam + 0.65 * top_beam, back_tip, 0.48 * s, 0.36 * s, ANTLER, step=0.32)
            # Polished pale ivory-buff tine tips
            for tip_pt in (top_beam, brow_tip, back_tip):
                m.ell(tip_pt, (0.36 * s, 0.40 * s, 0.36 * s), GLINT)

    draw_deer_legs(m, t, rear_y, front_y, kind, s, graze_step, stamp_lift, rise_k)
    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_deer(v, kind, (col - start) / n)
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
        (0, 7),   # E forage low
        (0, 14),  # E walk
        (1, 21),  # SE alert (flared Spiegel)
        (0, 27),  # E bound apex
        (0, 34),  # E groom
        (1, 37),  # SE sleep bed
        (0, 40),  # E Schrecken forehoof lift
        (0, 41),  # E Schrecken open-mouth bark
        (0, 48),  # E stand_up mid-rise
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([46, 56, 48, 255], np.uint8)
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
                print(f'deer build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/deer.png', sheet)
    print('Saved assets/wildlife/deer.png', sheet.shape)


if __name__ == '__main__':
    main()
