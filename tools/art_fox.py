#!/usr/bin/env python3
"""European Red Fox (Vulpes vulpes) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 52); 52 columns; 4 builds x 8 true facings = 32 rows. No emissive parts.
Builds:
  0: Klassischer Rotfuchs (vibrant rust-red, white bib/cheeks/Blume, black stockings & ear-backs)
  1: Birk-/Kreuzfuchs (russet-copper with dark dorsal cross & smoky flanks)
  2: Nebel-/Silberfuchs (charcoal-silver mist fox with bright white Blume)
  3: Gold-/Sandfuchs (warm ochre-amber forest variant)
Columns (52):
  idle 0:4, forage 4:10 (sniff_trail), walk 10:18 (Schnüren trot),
  alert 18:22 (seated LISTEN + head tilt), run 22:30 (stretched gallop),
  groom 30:34, sleep 34:38 (curled ball with tail over snout),
  special 38:46 (Mäusesprung vertical mouse pounce), stalk 46:52 (low crouched creep).
Usage: py -3 tools/art_fox.py [--preview-only] [--qa=path.png]
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

COAT, CREAM, DARK, NOSE_EYE, GLINT, INNER_EAR = range(6)

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

COATS = [
    # 0 Klassischer Rotfuchs: rich burnt sienna / flame-rust
    ['562220', '943b2a', 'cd6236', 'f09350'],
    # 1 Birk-/Kreuzfuchs: deep copper-russet
    ['451f23', '7c362e', 'b4583a', 'de8752'],
    # 2 Nebel-/Silberfuchs: sleek charcoal-slate silver-frosted coat
    ['1e202b', '393e50', '646c82', '9da6ba'],
    # 3 Gold-/Sandfuchs: warm ochre-amber woodland coat
    ['543020', '8e522d', 'c47c3e', 'eab064'],
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {NOSE_EYE: 3.5, GLINT: 4.6, INNER_EAR: 1.8, CREAM: 1.2, DARK: 1.25}
    art.ink_color = lambda mat: hexc('14111d' if mat in (DARK, NOSE_EYE) else '261b26')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def bezier3(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, u: float) -> np.ndarray:
    v = 1.0 - u
    return (v ** 3) * p0 + 3.0 * (v ** 2) * u * p1 + 3.0 * v * (u ** 2) * p2 + (u ** 3) * p3


def materials(v: int) -> None:
    setup_art()
    cream = ['8c8282', 'bab0ac', 'e5ddd3', 'fdf7ee']
    if v == 2:
        cream = ['808592', 'b0b6c2', 'dde2ea', 'f8fafc']
    ramps = [
        COATS[v % BUILDS_N],                                # 0 COAT
        cream,                                              # 1 CREAM (bib, cheeks, belly, white Blume tail tip)
        ['11101a', '201e2d', '373346', '534d64'],           # 2 DARK (black lower stockings, black ear-backs, cross saddle)
        ['090912', '12111f', '201e30', '322e44'],           # 3 NOSE_EYE
        ['9e7e3e', 'cca452', 'efd078', 'fff2ba'],           # 4 GLINT (warm amber-gold eye glint)
        ['584448', '86686a', 'b49390', 'ddc0ba'],           # 5 INNER_EAR
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_fox_legs(
    m: art.Model,
    t: float,
    rear_y: float,
    front_y: float,
    kind: str,
    pounce_idx: int,
) -> None:
    """Slender predator limbs: coat-colored upper thigh/shoulder + jet-black lower stockings & compact paws."""
    if kind == 'sleep':
        # Tucked neatly underneath curled body
        for side in (-1.0, 1.0):
            m.ell((side * 2.1, 1.5, 1.4), (1.05, 0.95, 1.65), DARK)
        return

    seated = kind in ('alert', 'groom')
    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (1.85 if front else 2.05)
            hip_z = 4.6 if front else -4.8
            hip_y = (front_y if front else rear_y) - 0.35

            if seated and not front:
                # Seated haunches braced cleanly on the ground with black hock/paw forward
                thigh = np.array([side * 2.35, rear_y - 0.8, hip_z + 0.6])
                hock = np.array([side * 2.25, 1.45, hip_z - 0.6])
                paw = np.array([side * 2.05, 0.95, hip_z + 2.6])
                m.limb((hip_x, hip_y, hip_z), thigh, 1.65, 1.35, COAT, step=0.4)
                m.limb(thigh, hock, 1.30, 0.86, COAT, step=0.38)
                m.limb(hock, paw, 0.82, 0.72, DARK, step=0.36)
                m.ell(paw, (0.90, 0.68, 1.15), DARK)
                continue

            swing = 0.0
            lift = 0.0
            knee_flex = 0.0

            if kind == 'walk':
                # Signature straight-line diagonal trot (Schnüren): diagonal pairs move in sync!
                diag_offset = 0.0 if ((side > 0) == front) else 0.5
                cyc = (t + diag_offset) % 1.0
                stance = 0.56
                if cyc < stance:
                    c = cyc / stance
                    swing = 2.6 * (1.0 - 2.0 * c)
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -2.6 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.85
                    knee_flex = math.sin(c * math.pi) * 0.9
            elif kind == 'forage':
                # Slow sniffing walk
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.68
                if cyc < stance:
                    swing = 1.6 * (1.0 - 2.0 * (cyc / stance))
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -1.6 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.1
            elif kind == 'stalk':
                # Ultra-deliberate low belly-creep with high controlled paw placement
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.66
                if cyc < stance:
                    swing = 2.1 * (1.0 - 2.0 * (cyc / stance))
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -2.1 * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.55
                    knee_flex = 0.85
            elif kind == 'run':
                # Stretched rotary gallop
                lead = 0.08 if side > 0 else -0.08
                ang = ((t + (0.48 if front else 0.0) + lead) % 1.0) * math.tau
                if front:
                    swing = 4.4 * math.sin(ang - 0.35)
                    lift = max(0.0, math.cos(ang)) * 2.5
                else:
                    swing = -4.6 * math.sin(ang - 0.25)
                    lift = max(0.0, -math.cos(ang)) * 2.4
            elif kind == 'special':
                # Mäusesprung 8-frame biomechanics:
                # 0..1 deep coil, 2..3 steep upward hind launch, 4 tucked apex, 5..6 steep forepaw dive, 7 pin
                if front:
                    swing = [-0.6, -1.0, 2.2, 3.6, 3.2, 3.8, 2.6, 1.0][pounce_idx]
                    lift = [0.0, 0.2, 2.6, 4.0, 3.4, 0.8, 0.0, 0.0][pounce_idx]
                else:
                    swing = [1.2, 1.6, -3.4, -4.8, -3.2, -2.4, -1.4, -0.4][pounce_idx]
                    lift = [0.0, 0.0, 0.6, 2.2, 3.8, 3.6, 1.8, 0.0][pounce_idx]

            # Narrow track width under body during Schnüren!
            paw_x = hip_x * (0.68 if kind == 'walk' else 0.86)
            foot_y = max(0.85, 0.85 + lift)
            root = np.array([hip_x, hip_y, hip_z])
            foot = np.array([paw_x, foot_y, hip_z + swing])

            if front:
                carpus = np.array([
                    0.5 * (hip_x + paw_x),
                    foot_y + (hip_y - foot_y) * 0.46 + knee_flex * 0.3,
                    hip_z + swing * 0.55 + 0.35 + knee_flex * 0.45,
                ])
                # Coat upper arm -> jet-black stocking forearm & paw!
                m.limb(root, carpus, 1.28, 0.90, COAT, step=0.38)
                m.limb(carpus, foot, 0.86, 0.70, DARK, step=0.35)
            else:
                hock = np.array([
                    0.5 * (hip_x + paw_x),
                    foot_y + (hip_y - foot_y) * 0.45 + knee_flex * 0.3,
                    hip_z + swing * 0.42 - 1.45,
                ])
                # Muscular coat thigh -> jet-black stocking cannon & paw!
                m.limb(root, hock, 1.55, 0.95, COAT, step=0.38)
                m.limb(hock, foot, 0.88, 0.70, DARK, step=0.35)

            m.ell(foot + np.array([0.0, 0.0, 0.25]), (0.86, 0.66, 1.12), DARK)


def build_fox(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    pounce_idx = int(t * 8) % 8

    # Tight curled sleeping ball with bushy white-tipped tail wrapped across snout!
    if kind == 'sleep':
        breath = 0.16 * b
        by = 4.8 + breath
        # Lush curled C-shaped back from shoulder around flank to rump (matches standing body mass!)
        for i in range(9):
            ang = -0.55 + 2.65 * (i / 8.0)
            rad = 4.45
            cx = math.sin(ang) * rad * 0.90 - 0.55
            cz = math.cos(ang) * rad - 0.55
            m.ell((cx, by + 0.35 * math.sin(i * 0.4), cz), (3.45, 3.15, 3.45), COAT)
        if v == 1:
            m.limb((-2.2, by + 2.45, 1.4), (-1.4, by + 2.45, -3.2), 1.65, 1.45, DARK, step=0.45)
        # Head tucked inward over paws
        hx, hy, hz = -1.75, by + 1.85, 3.75
        rot_h = art.rot_y(-0.52) @ art.rot_x(0.20)
        m.ell((hx, hy, hz), (2.55, 2.30, 2.80), COAT, R=rot_h)
        m.ell((hx - 0.90, hy - 0.55, hz + 2.00), (1.20, 0.92, 1.75), COAT, R=rot_h)
        m.ell((hx - 1.45, hy - 0.55, hz + 3.15), (0.58, 0.48, 0.55), NOSE_EYE, R=rot_h)
        for side in (-1.0, 1.0):
            ex = hx + side * 1.55
            ez = hz - 0.45 + side * 0.55
            R_ear = rot_h @ rot_z(-side * 0.52)
            m.ell((ex, hy + 2.35, ez - 0.18), (0.85, 1.80, 0.45), DARK, R=R_ear)
            m.ell((ex, hy + 2.22, ez + 0.14), (0.50, 1.25, 0.25), INNER_EAR, R=R_ear)
            m.ell((hx + side * 1.35 - 0.35, hy + 0.15, hz + 1.20), (0.42, 0.15, 0.42), NOSE_EYE, R=rot_h)
        # Fluffy bushy brush wrapping right around front and across snout tip with bright white Blume!
        p0 = np.array([2.6, by - 0.1, -4.0])
        p1 = np.array([6.8, by - 0.3, -0.6])
        p2 = np.array([5.6, by - 0.4, 6.0])
        p3 = np.array([-0.8, by - 0.4, 6.1])
        radii = [2.25, 2.85, 3.15, 3.15, 2.85, 2.40, 1.85]
        for ti, r_t in enumerate(radii):
            u = ti / (len(radii) - 1)
            pt = bezier3(p0, p1, p2, p3, u)
            mat_t = CREAM if ti >= 5 else COAT
            m.ell(pt, (r_t * 1.10, r_t * 0.90, r_t * 1.10), mat_t)
        draw_fox_legs(m, t, by, by, kind, 0)
        return m

    # Lithe low-slung predator body heights
    rear_y = 9.2
    front_y = 9.0

    if kind == 'idle':
        rear_y += 0.14 * b
        front_y += 0.16 * b
    elif kind == 'forage':
        front_y = 8.2
        rear_y = 9.1
    elif kind == 'walk':
        bob = 0.20 * math.cos(p * 2.0)
        rear_y += bob
        front_y += bob
    elif kind == 'alert':
        # Seated LISTEN haunch posture!
        rear_y = 5.8
        front_y = 10.2
    elif kind == 'groom':
        rear_y = 5.8
        front_y = 9.6
    elif kind == 'run':
        wave = math.sin(p)
        lift_g = 1.2 * max(0.0, math.sin(p - 0.3))
        rear_y = 9.4 + lift_g - 0.75 * wave
        front_y = 9.2 + lift_g + 0.85 * wave
    elif kind == 'stalk':
        # Ultra-low belly-creep close to grass!
        rear_y = 6.7 + 0.10 * math.cos(p * 2.0)
        front_y = 6.1 + 0.10 * math.cos(p * 2.0)
    elif kind == 'special':
        # Mäusesprung postural pitch: deep coil -> steep upward launch -> apex curve -> steep vertical dive!
        rear_y = [6.4, 5.8, 8.6, 10.4, 12.6, 13.4, 11.2, 8.8][pounce_idx]
        front_y = [7.6, 7.2, 12.8, 14.8, 12.8, 8.2, 6.8, 8.4][pounce_idx]

    # Seamless 9-ellipsoid spine chain rotated along body pitch -> zero interior vertical ink seams!
    spine_slope = math.atan2(front_y - rear_y, 9.4)
    R_spine = art.rot_x(-spine_slope)
    for i in range(9):
        u = i / 8.0
        sz = -5.0 + 9.4 * u
        arch = math.sin(u * math.pi)
        # Subtle feline/vulpine spine flex in gallop/pounce
        flex = (0.55 * arch if kind == 'special' and pounce_idx in (3, 4, 5) else 0.0)
        sy = rear_y * (1.0 - u) + front_y * u + flex
        rx_r = 2.75 + 0.38 * arch - 0.15 * u
        ry_r = 3.05 + 0.48 * arch - 0.10 * u
        rz_r = 2.55 + 0.55 * arch
        m.ell((0.0, sy, sz), (rx_r, ry_r, rz_r), COAT, R=R_spine)

    # Build 1 (Kreuzfuchs): continuous smoky dorsal band & shoulder cross saddle
    if v == 1:
        c_back = np.array([0.0, rear_y * 0.82 + front_y * 0.18 + 2.15, -3.4])
        c_shld = np.array([0.0, rear_y * 0.15 + front_y * 0.85 + 2.10, 3.0])
        m.limb(c_back, c_shld, 1.35, 1.55, DARK, step=0.45)
        m.ell(c_shld + np.array([0.0, -0.35, -0.2]), (2.75, 1.35, 1.85), DARK, R=R_spine)

    # Snowy-cream belly & lush chest bib (Vorstoß)
    for u_b in (0.22, 0.50, 0.78):
        bz = -4.6 + 8.8 * u_b
        by_b = rear_y * (1.0 - u_b) + front_y * u_b - 1.75
        m.ell((0.0, by_b, bz), (2.25, 1.55, 2.45), CREAM, R=R_spine)
    m.ell((0.0, front_y - 0.55, 5.15), (2.25, 2.35, 2.05), CREAM, R=R_spine)

    # Iconic seamless bushy brush (Lunte) with broad snowy-white tip (Blume) — bridged smoothly from pelvis!
    t_root = np.array([0.0, rear_y + 0.15, -5.4])
    sway = 1.35 * math.sin(p - 0.7) if kind in ('walk', 'forage') else (0.55 * b if kind == 'idle' else 0.0)
    if kind in ('alert', 'groom'):
        # Brush sweeps down to the ground & curls gently behind seated haunches
        p0 = t_root
        p1 = np.array([0.4, rear_y - 1.6, -8.8])
        p2 = np.array([1.2, 2.2, -12.6])
        p3 = np.array([2.2, 2.4, -16.4])
    elif kind == 'run':
        # Straight horizontal streaming rudder!
        p0 = t_root
        p1 = np.array([0.3 * b, rear_y + 0.3, -9.2])
        p2 = np.array([0.6 * math.sin(p - 0.6), rear_y + 0.4, -13.8])
        p3 = np.array([0.9 * math.sin(p - 1.1), rear_y + 0.2, -18.2])
    elif kind == 'stalk':
        # Held dead-flat, low and rigid behind crouching body
        p0 = t_root
        p1 = np.array([0.2 * b, rear_y - 0.4, -9.0])
        p2 = np.array([0.35 * b, rear_y - 0.9, -13.4])
        p3 = np.array([0.5 * b, rear_y - 1.0, -17.6])
    elif kind == 'special':
        # Counterweight tail whip: rises steeply aloft during dive (frames 4..6)!
        tail_lift = [1.5, 2.8, 1.2, 2.6, 6.2, 8.8, 7.2, 2.5][pounce_idx]
        tail_back = [-15.8, -15.2, -16.8, -16.4, -14.2, -11.6, -12.8, -16.0][pounce_idx]
        p0 = t_root
        p1 = np.array([0.0, rear_y + tail_lift * 0.30, -8.6])
        p2 = np.array([0.0, rear_y + tail_lift * 0.72, 0.5 * (-8.6 + tail_back)])
        p3 = np.array([0.0, rear_y + tail_lift, tail_back])
    elif kind in ('walk', 'forage'):
        # Purposeful slightly lowered horizontal brush swaying in Schnüren / sniff_trail
        p0 = t_root
        p1 = np.array([sway * 0.35, rear_y - 0.6, -8.9])
        p2 = np.array([sway * 0.75, rear_y - 1.5, -13.2])
        p3 = np.array([sway * 1.10, rear_y - 1.1, -17.2])
    else:
        # Idle: heavy bushy brush draped gracefully downward at ~35 deg with soft upturned Blume tip!
        p0 = t_root
        p1 = np.array([sway * 0.35, rear_y - 1.9, -8.5])
        p2 = np.array([sway * 0.75, 3.3, -12.2])
        p3 = np.array([sway * 1.10, 3.6, -15.6])

    # 8 overlapping ellipsoids from pelvis bridge -> thick brush middle -> tapered white Blume tip
    tail_radii = [2.15, 2.55, 2.95, 3.15, 3.00, 2.65, 2.15, 1.55]
    for ti, r_t in enumerate(tail_radii):
        u = ti / (len(tail_radii) - 1)
        pt = bezier3(p0, p1, p2, p3, u)
        mat_t = CREAM if ti >= 6 else COAT
        m.ell(pt, (r_t * 0.96, r_t * 0.98, r_t * 1.18), mat_t)

    # Neck & pointed vulpine head with white cheek ruffs, black-backed ears, and inquisitive head-tilt!
    hy = front_y + 5.6
    hz = 7.4
    pitch = 0.08
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        hy = front_y + 5.7 + 0.16 * b
        yaw = 0.08 * b
    elif kind == 'forage':
        # SNIFF_TRAIL: nose right down by the grass sweeping left-right!
        hy = 4.2 + 0.25 * abs(b)
        hz = 9.8
        pitch = 0.58
        yaw = 0.22 * b
    elif kind == 'walk':
        hy = front_y + 4.6
        hz = 8.1
        pitch = 0.16
    elif kind == 'alert':
        # Seated LISTEN with signature lateral head-tilt (rot_z)!
        idx_a = int(t * 4) % 4
        hy = front_y + 6.2
        hz = 6.6
        pitch = 0.12
        roll = [0.10, 0.34, 0.38, 0.16][idx_a]
        yaw = [0.0, 0.10, 0.12, 0.04][idx_a]
    elif kind == 'groom':
        groom_k = [0.3, 0.9, 1.0, 0.45][int(t * 4) % 4]
        hy = front_y + 3.4 - 1.2 * groom_k
        hz = 6.4 - 4.2 * groom_k
        yaw = 1.22 * groom_k
        pitch = 0.35 * groom_k
    elif kind == 'run':
        hy = front_y + 4.4 + 0.35 * math.sin(p)
        hz = 8.8
        pitch = 0.06
    elif kind == 'stalk':
        # Locked horizontal gaze, chin low in the grass
        hy = front_y + 2.6
        hz = 9.2
        pitch = 0.08
    elif kind == 'special':
        # Mäusesprung head arc: locked down on coil, pitched up on launch, diving straight down on strike!
        hy = front_y + [3.8, 3.4, 5.2, 5.6, 3.8, -1.8, -2.6, 3.6][pounce_idx]
        hz = [8.2, 8.0, 8.8, 9.4, 9.6, 9.2, 8.6, 8.2][pounce_idx]
        pitch = [0.28, 0.34, -0.22, -0.10, 0.35, 0.78, 0.72, 0.22][pounce_idx]

    head = np.array([math.sin(yaw) * 1.1, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ np.array([x, y, z])

    def head_ell(pos: tuple[float, float, float], r: tuple[float, float, float], mat: int, R_extra: np.ndarray | None = None) -> None:
        m.ell(hp(*pos), r, mat, R=rot if R_extra is None else rot @ R_extra)

    # Smooth neck bridge + white throat collar
    neck_base = np.array([0.0, front_y + 0.65, 4.4])
    throat = hp(0.0, -1.05, -1.35)
    m.limb(neck_base, throat, 2.35, 1.85, COAT, step=0.42)
    m.limb(neck_base + np.array([0.0, -0.85, 0.65]), throat + rot @ np.array([0.0, -0.55, 0.75]), 1.75, 1.35, CREAM, step=0.45)

    # Broad cheek skull + fluffy white cheek ruffs (Backenbart) + narrow pointed muzzle + wet black nose
    head_ell((0.0, 0.15, -0.15), (2.45, 2.35, 2.65), COAT)
    for side in (-1.0, 1.0):
        # Iconic flared white fox cheek ruffs!
        head_ell((side * 2.05, -0.65, 0.25), (1.15, 1.25, 1.75), CREAM)
        head_ell((side * 1.15, -0.95, 1.65), (1.05, 0.82, 1.65), CREAM)

    # Slender red bridge of snout & white lower jaw + black nose button
    head_ell((0.0, -0.35, 2.15), (1.25, 0.98, 1.95), COAT)
    head_ell((0.0, -0.52, 3.45), (0.88, 0.72, 1.25), COAT)
    head_ell((0.0, -0.92, 3.15), (0.82, 0.48, 1.35), CREAM)
    head_ell((0.0, -0.45, 4.45), (0.58, 0.48, 0.55), NOSE_EYE)

    blink = kind == 'idle' and t >= 0.75
    for side in (-1.0, 1.0):
        # Large triangular ears: JET-BLACK backs (DARK), warm coat base, pale buff inner pinna!
        ear_splay = 0.34 if kind in ('alert', 'stalk', 'special') else (0.52 if kind == 'run' else 0.40)
        ear_fwd = 0.22 if kind in ('alert', 'stalk') else (-0.28 if kind == 'run' else 0.08 + 0.08 * math.sin(p + side))
        R_ear = rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        # Rear black ear shell + pointed tip
        head_ell((side * 1.65, 2.55, -0.78), (1.02, 2.15, 0.48), DARK, R_ear)
        head_ell((side * 1.78, 3.95, -0.82), (0.58, 1.05, 0.36), DARK, R_ear)
        # Front pale inner ear hollow
        head_ell((side * 1.58, 2.45, -0.36), (0.58, 1.55, 0.24), INNER_EAR, R_ear)

        # Sharp vulpine eye + warm amber-gold glint
        head_ell((side * 1.55, 0.28, 1.25), (0.42, 0.15 if blink else 0.48, 0.44), NOSE_EYE)
        if not blink:
            head_ell((side * 1.66, 0.45, 1.45), (0.18, 0.18, 0.15), GLINT)

    draw_fox_legs(m, t, rear_y, front_y, kind, pounce_idx)
    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    materials(v)
    m = build_fox(v, kind, (col - start) / n)
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
        (1, 0),   # SE idle
        (2, 0),   # S idle
        (4, 0),   # W idle
        (6, 0),   # N idle (shows black ear backs + white Blume!)
        (0, 6),   # E forage sniff_trail
        (0, 12),  # E Schnüren trot
        (2, 19),  # S seated LISTEN + lateral head tilt!
        (1, 19),  # SE seated LISTEN + head tilt
        (0, 24),  # E stretched gallop
        (1, 35),  # SE curled sleep ball (tail over snout)
        (0, 40),  # E Mäusesprung upward launch
        (0, 43),  # E Mäusesprung steep vertical dive!
        (0, 48),  # E low crouched stalk
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
                print(f'fox build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/fox.png', sheet)
    print('Saved assets/wildlife/fox.png', sheet.shape)


if __name__ == '__main__':
    main()
