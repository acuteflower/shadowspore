#!/usr/bin/env python3
"""Procedural Desert Biome Wildlife Suite (Sonnenquarz-Öde) in the miniature 3D pixel-art pipeline (SS=4).

Outputs (ZERO emissive pixels / ZERO night glow; 8 true rendered facings E, SE, S, SW, W, NW, N, NE; 1px tinted outlines):
  1. assets/wildlife/oryx.png          (64x64, GROUND_ROW=52.0, 52 cols x 32 rows = 4 builds x 8 dirs)
  2. assets/wildlife/fennec.png        (64x64, GROUND_ROW=52.0, 52 cols x 32 rows = 4 builds x 8 dirs)
  3. assets/wildlife/jerboa.png        (64x64, GROUND_ROW=52.0, 52 cols x 32 rows = 4 builds x 8 dirs)
  4. assets/wildlife/agama.png         (64x64, GROUND_ROW=52.0, 52 cols x 32 rows = 4 builds x 8 dirs)
  5. assets/wildlife/desert_falcon.png (64x64, GROUND_ROW=48.0, 62 cols x 24 rows = 3 builds x 8 dirs)
  6. assets/wildlife/desert_burrow.png (40x24 RGBA, offset=Vector2(0, -8), layered sandstone overhang + sand fan)
  +  docs/img/desert_wildlife.png      (2x nearest-neighbor desert sand & sun-quartz contact showcase sheet)

Usage:
  py -3 tools/art_desert_wildlife.py                  # Generate all 6 wildlife assets + docs/img/desert_wildlife.png
  py -3 tools/art_desert_wildlife.py --qa=path.png    # Fast 3x QA contact sheet of key poses/facings across all species
  py -3 tools/art_desert_wildlife.py --only=oryx      # Generate only specified species (+ preview if exists)
"""
from concurrent.futures import ProcessPoolExecutor
import math
from pathlib import Path
import sys
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as art  # noqa: E402
from gen_art import CLEAR, hexc  # noqa: E402
from world_data import save_png  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
W = H = 64


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def smooth(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def bezier3(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, u: float) -> np.ndarray:
    v = 1.0 - u
    return (v ** 3) * p0 + 3.0 * (v ** 2) * u * p1 + 3.0 * v * (u ** 2) * p2 + (u ** 3) * p3


def _to_frame_rgba(m: art.Model, d: int) -> np.ndarray:
    depth, code = art.render(m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def verify_sheet_bounds(name: str, sheet: np.ndarray, cols: int, rows: int, margin: int = 1) -> None:
    """Assert zero 64x64 cell border clipping and zero pure #000000 outlines."""
    clipped = []
    pure_black = int(np.sum(
        (sheet[:, :, 3] > 0)
        & (sheet[:, :, 0] == 0)
        & (sheet[:, :, 1] == 0)
        & (sheet[:, :, 2] == 0)
    ))
    assert pure_black == 0, f"{name}: found {pure_black} pure #000000 pixels!"
    for r in range(rows):
        for c in range(cols):
            cell = sheet[r * H:(r + 1) * H, c * W:(c + 1) * W]
            ys, xs = np.where(cell[:, :, 3] > 0)
            if len(xs) == 0:
                clipped.append(f"r{r}c{c}(empty)")
                continue
            if xs.min() < margin or xs.max() > W - 1 - margin or ys.min() < margin or ys.max() > H - 1 - margin:
                clipped.append(f"r{r}c{c}(x={xs.min()}..{xs.max()},y={ys.min()}..{ys.max()})")
    assert not clipped, f"{name} clipped 64x64 border ({len(clipped)} cells): {', '.join(clipped[:12])}"


# ==============================================================================
# 1. KRONEN-ORYX (assets/wildlife/oryx.png — 52 cols x 32 rows, GROUND_ROW=52.0)
# ==============================================================================
ORYX_BUILDS = 4
ORYX_COLS = 52
O_COAT, O_ACCENT, O_WHITE, O_MASK, O_HOOF, O_HORN, O_RIDGE, O_EYE, O_GLINT, O_EAR_IN = range(10)

ORYX_BLOCKS = [
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


def oryx_materials(v: int) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        O_GLINT: 4.7,
        O_EYE: 3.6,
        O_MASK: 1.55,
        O_WHITE: 1.40,
        O_RIDGE: 1.55,
        O_HORN: 1.35,
        O_EAR_IN: 1.65,
        O_ACCENT: 1.25,
    }
    art.ink_color = lambda mat: hexc('14101e' if mat in (O_MASK, O_HOOF, O_EYE, O_HORN) else '261b26')
    b = v % ORYX_BUILDS
    if b == 0:
        # 0 Elfenbein-Leitbulle: sun-reflecting cream-ivory, crisp black-and-white Gemsbok mask & flank band
        coat = ['7d6c64', 'b09c8e', 'ded0bf', 'faf2e4']
        accent = ['6a5852', '998377', 'c8b4a4', 'efe3d2']
        white = ['989296', 'c6c0c2', 'ebe6e4', 'ffffff']
        mask = ['15111e', '272034', '413750', '625572']
        horn = ['181422', '2f283e', '504662', '7a6f8e']
        ridge = ['282236', '463d5a', '6f6386', '9e92b6']
    elif b == 1:
        # 1 Sand-Kuh: sleeker warm sand-ivory cow with extra-fine scimitar horns
        coat = ['7c5e4c', 'ae886e', 'dbb898', 'f6dec2']
        accent = ['6e5040', '9c745c', 'ca9f80', 'ebd0b2']
        white = ['988e8c', 'c6bcba', 'ede4e0', 'fffcf8']
        mask = ['18121e', '2c2234', '483a52', '6a5874']
        horn = ['1a1524', '332a42', '564a68', '827496']
        ridge = ['2a2338', '4a3f5e', '74668c', 'a496bc']
    elif b == 2:
        # 2 Rotsand-Oryx (Scimitar morph): cream body + rich golden-rufous neck, shoulder & haunch sheen
        coat = ['826c60', 'b59c8a', 'e2cbb6', 'fbf0e0']
        accent = ['5e2820', '96442c', 'cc6e3e', 'f09e5e']
        white = ['9a9292', 'c8c0be', 'efe8e4', 'ffffff']
        mask = ['1c1320', '332234', '52394e', '76566e']
        horn = ['181322', '30273e', '524562', '7e6f8e']
        ridge = ['282136', '473c5a', '706286', 'a092b6']
    else:
        # 3 Oryx-Kalb: uniform warm cinnamon-sand fawn WITHOUT black face mask or flank stripe!
        coat = ['68422e', '9a6644', 'ca9264', 'efc08e']
        accent = ['5c3828', '8a583a', 'b88056', 'e0ad7e']
        white = ['8e7868', 'ba9f8a', 'e2cab4', 'f9e8d6']
        mask = ['281b24', '44303a', '664a54', '8c6a74']
        horn = ['241c2a', '3e3246', '60506a', '887694']
        ridge = ['32283a', '52445e', '7a6888', 'a694b4']

    ramps = [
        coat,                                               # 0 O_COAT
        accent,                                             # 1 O_ACCENT
        white,                                              # 2 O_WHITE
        mask,                                               # 3 O_MASK
        ['120f1c', '221d32', '3a334e', '584f6e'],           # 4 O_HOOF
        horn,                                               # 5 O_HORN
        ridge,                                              # 6 O_RIDGE
        ['0d0b16', '191528', '2b2540', '413958'],           # 7 O_EYE
        ['8e6a2c', 'c89a42', 'f2c868', 'fff0b4'],           # 8 O_GLINT
        ['644850', '926c72', 'be969a', 'e6c4c4'],           # 9 O_EAR_IN
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def _draw_oryx_legs(
    m: art.Model,
    t: float,
    rear_pt: np.ndarray,
    front_pt: np.ndarray,
    kind: str,
    s: float,
    calf: bool,
    drink_step: float,
    threat_k: float,
    rise_k: float,
) -> None:
    """Long slender desert-antelope legs: dark upper garter markings (adults), white lower stockings, cloven hooves."""
    upper_mat = O_COAT if calf else O_MASK
    sock_mat = O_COAT if calf else O_WHITE
    for side in (-1.0, 1.0):
        for front in (False, True):
            anchor = front_pt if front else rear_pt
            hip_x = side * (2.15 if front else 2.30) * s
            hip_y = float(anchor[1]) - (0.45 if front else 0.35) * s
            hip_z = float(anchor[2]) + (0.20 if front else -0.20) * s
            rc = max(0.62, 0.78 * s)

            bed_blend = 1.0 if kind == 'sleep' else (1.0 - rise_k if kind == 'stand_up' else 0.0)
            if bed_blend >= 0.999:
                ts = side * (0.92 if side > 0 else 0.74)
                root = np.array([hip_x * 0.90, hip_y + 0.30 * s, hip_z])
                if front:
                    knee = np.array([ts * 2.45 * s, 1.85 * s, hip_z + 2.45 * s])
                    hoof = np.array([ts * 1.85 * s, 0.95 * s, hip_z - 1.45 * s])
                else:
                    knee = np.array([ts * 2.85 * s, 1.95 * s, hip_z - 2.05 * s])
                    hoof = np.array([ts * 2.15 * s, 0.95 * s, hip_z + 2.25 * s])
                m.limb(root, knee, rc * 1.55, rc * 1.02, upper_mat, step=0.40)
                m.limb(knee, hoof, rc * 0.96, rc * 0.78, sock_mat, step=0.38)
                m.ell(hoof, (rc * 0.90, 0.64 * s, 0.98 * s), O_HOOF)
                continue

            swing = 0.0
            lift = 0.0
            knee_flex = 0.0

            if kind == 'walk':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                stance = 0.60
                if cyc < stance:
                    swing = (2.75 * s) * (1.0 - 2.0 * (cyc / stance))
                else:
                    c = (cyc - stance) / (1.0 - stance)
                    swing = -(2.75 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * (2.65 if front else 2.15) * s
                    knee_flex = math.sin(c * math.pi) * 1.35 * s
            elif kind == 'run':
                lead = 0.09 if side > 0 else -0.09
                cyc = (t + (0.45 if front else 0.0) + lead) % 1.0
                ang = cyc * math.tau
                airborne = max(0.0, math.sin(t * math.pi))
                if front:
                    swing = (4.4 * s) * math.sin(ang - 0.35)
                    lift = max(0.0, airborne * 2.8 * s + max(0.0, math.cos(ang)) * 1.5 * s)
                    knee_flex = max(0.0, -math.sin(ang)) * 1.4 * s
                else:
                    swing = -(4.6 * s) * math.sin(ang - 0.25)
                    lift = max(0.0, airborne * 2.4 * s + max(0.0, -math.cos(ang)) * 1.4 * s)
                    knee_flex = max(0.0, math.cos(ang)) * 1.3 * s
            elif kind == 'forage' and front:
                # Splayedoasis drinking / grazing foreleg stance
                swing = (1.55 if side > 0 else -0.75) * s * drink_step
            elif kind == 'special':
                # Braced wide horn-threat stance (one forehoof pawing/braced forward!)
                if front:
                    swing = (2.35 if side > 0 else -1.15) * s * threat_k
                    if side > 0 and 0.25 < t < 0.55:
                        lift = 1.45 * s * math.sin((t - 0.25) / 0.30 * math.pi)
                        knee_flex = 0.95 * s
                else:
                    swing = -0.85 * s * threat_k
            elif kind == 'stand_up':
                if front and rise_k < 0.58:
                    kneel = 1.0 - smooth(rise_k / 0.58)
                    swing = -1.85 * s * kneel
                    knee_flex = 2.25 * s * kneel

            splay_x = 1.18 if (kind == 'forage' and front and drink_step > 0.4) else 0.96
            root = np.array([hip_x, hip_y, hip_z])
            foot_y = 0.72 * s + lift
            foot = np.array([hip_x * splay_x, foot_y, hip_z + swing])

            if front:
                elbow = np.array([hip_x * 0.97, hip_y - 2.95 * s, hip_z - 0.55 * s + swing * 0.20])
                carpus = np.array([
                    0.5 * (hip_x + foot[0]),
                    foot_y + (hip_y - foot_y) * 0.46 + knee_flex * 0.38,
                    hip_z + swing * 0.56 + (0.65 * s if lift > 0.35 else 0.16 * s) + knee_flex * 0.50,
                ])
                m.limb(root, elbow, rc * 1.85, rc * 1.32, O_ACCENT if not calf else O_COAT, step=0.40)
                m.limb(elbow, carpus, rc * 1.28, rc * 0.95, upper_mat, step=0.38)
                m.ell(carpus + np.array([0.0, 0.0, 0.14 * s]), (rc * 0.98, rc * 0.90, rc * 0.98), upper_mat)
                m.limb(carpus, foot, rc * 0.88, rc * 0.74, sock_mat, step=0.36)
            else:
                stifle = np.array([hip_x * 1.03, hip_y - 2.85 * s, hip_z + 0.95 * s + swing * 0.22])
                hock = np.array([
                    0.5 * (hip_x + foot[0]),
                    foot_y + (hip_y - foot_y) * 0.47 + knee_flex * 0.35,
                    hip_z + swing * 0.42 - (1.75 * s - knee_flex * 0.35),
                ])
                m.limb(root, stifle, rc * 2.10, rc * 1.45, O_ACCENT if not calf else O_COAT, step=0.40)
                m.limb(stifle, hock, rc * 1.38, rc * 0.98, upper_mat, step=0.38)
                m.ell(hock + np.array([0.0, 0.0, -0.14 * s]), (rc * 0.96, rc * 0.92, rc * 1.00), upper_mat)
                m.limb(hock, foot, rc * 0.88, rc * 0.74, sock_mat, step=0.36)

            m.ell(foot + np.array([0.0, -0.02 * s, 0.24 * s]), (rc * 0.94, 0.70 * s, 1.12 * s), O_HOOF)


def build_oryx(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    b = v % ORYX_BUILDS
    bull = (b == 0)
    cow = (b == 1)
    scimitar = (b == 2)
    calf = (b == 3)

    s = 1.0 if bull else (0.94 if cow else (0.97 if scimitar else 0.70))
    head_scale = 1.10 if calf else (0.96 if cow else 1.0)

    p = t * math.tau
    breath = math.sin(p)

    # Tall long-legged antelope frame with proud muscular withers
    stand_rear_y = 14.3 * s
    stand_front_y = 15.1 * s
    rear_y, rear_z = stand_rear_y, -5.0 * s
    front_y, front_z = stand_front_y, 5.0 * s

    drink = 0.0
    drink_step = 0.0
    groom = 0.0
    threat_k = 0.0
    rise_k = 1.0
    tail_swish = 0.0

    if kind == 'idle':
        rear_y += 0.14 * breath * s
        front_y += 0.18 * breath * s
        tail_swish = 0.65 * math.sin(p)
    elif kind == 'forage':
        # Lowering neck deeply to drink at oasis edge / graze desert grass
        idx = int(t * 8) % 8
        drink = [0.25, 0.76, 1.0, 0.96, 1.0, 0.94, 0.82, 0.28][idx]
        drink_step = [0.3, 0.85, 1.0, 1.0, 1.0, 1.0, 0.85, 0.3][idx]
        front_y -= 1.35 * drink * s
        front_z += 0.55 * drink * s
        tail_swish = 0.45 * math.sin(p * 2.0)
    elif kind == 'walk':
        rear_y += 0.26 * math.cos(p * 2.0) * s
        front_y += 0.26 * math.cos(p * 2.0 - 0.55) * s
        tail_swish = 0.85 * math.sin(p)
    elif kind == 'alert':
        front_y += 0.48 * s
        rear_y += 0.20 * s
    elif kind == 'run':
        arc = math.sin(t * math.pi)
        wave = math.sin(p)
        lift_b = 2.85 * arc * s
        rear_y += lift_b - 0.90 * wave * s
        front_y += lift_b + 1.05 * wave * s
    elif kind == 'groom':
        groom = [0.35, 0.90, 1.0, 0.48][int(t * 4) % 4]
        front_y -= 0.25 * groom * s
    elif kind == 'sleep':
        rear_y = 5.0 * s + 0.10 * breath * s
        front_y = 5.5 * s + 0.12 * breath * s
    elif kind == 'special':
        # Defensive scimitar-horn threat posture ('LOWER'): chin tucked deep, long horns leveled straight forward!
        idx = int(t * 6) % 6
        threat_k = [0.35, 0.90, 1.0, 0.96, 0.80, 0.28][idx]
        front_y -= 2.85 * threat_k * s
        front_z += 0.95 * threat_k * s
        rear_y -= 0.35 * threat_k * s
        tail_swish = 1.25 * math.sin(p * 2.0)
    elif kind == 'stand_up':
        rise_k = smooth((t * 6.0 + 0.5) / 6.0)
        rump_k = smooth(min(1.0, rise_k * 1.24))
        fore_k = smooth(max(0.0, (rise_k - 0.18) / 0.82))
        rear_y = (5.0 + (14.3 - 5.0) * rump_k) * s
        front_y = (5.5 + (15.1 - 5.5) * fore_k) * s

    rear_pt = np.array([0.0, rear_y, rear_z])
    front_pt = np.array([0.0, front_y, front_z])
    torso_vec = front_pt - rear_pt
    spine_slope = math.atan2(float(torso_vec[1]), max(1.0, float(torso_vec[2])))
    R_spine = art.rot_x(-spine_slope)

    # ---- Sleek Muscular Antelope Torso + Withers Hump + Rufous Cape / Dark Flank Band ----
    for i in range(9):
        u = i / 8.0
        arch = math.sin(u * math.pi)
        withers = math.exp(-((u - 0.84) / 0.20) ** 2) * (0.95 if bull else 0.58)
        pt = rear_pt + torso_vec * u + np.array([0.0, (0.25 * arch + withers * 0.62) * s, 0.0])
        rx_r = (3.25 + 0.42 * arch + 0.22 * withers) * s
        ry_r = (3.70 + 0.50 * arch + 0.55 * withers) * s
        rz_r = (2.95 + 0.52 * arch) * s
        mat_body = O_ACCENT if (scimitar and (u > 0.66 or u < 0.20)) else O_COAT
        m.ell(pt, (rx_r, ry_r, rz_r), mat_body, R=R_spine)

    # Bright white underbelly + crisp dark Gemsbok lower-flank stripe (adults only!)
    for u_b in (0.20, 0.48, 0.76):
        pt_b = rear_pt + torso_vec * u_b + R_spine @ np.array([0.0, -2.55 * s, 0.0])
        m.ell(pt_b, (2.65 * s, 1.55 * s, 2.75 * s), O_WHITE, R=R_spine)
    if not calf:
        flank_a = rear_pt + torso_vec * 0.16 + R_spine @ np.array([0.0, -1.45 * s, 0.0])
        flank_b = rear_pt + torso_vec * 0.84 + R_spine @ np.array([0.0, -1.55 * s, 0.0])
        for side in (-1.0, 1.0):
            off_f = R_spine @ np.array([side * 2.55 * s, 0.0, 0.0])
            m.limb(flank_a + off_f, flank_b + off_f, 0.95 * s, 0.90 * s, O_MASK, step=0.45)
        # Dorsal short dark spine ridge
        m.limb(
            rear_pt + torso_vec * 0.55 + R_spine @ np.array([0.0, 3.55 * s, 0.0]),
            front_pt + R_spine @ np.array([0.0, 3.85 * s, 0.0]),
            0.75 * s, 0.85 * s, O_MASK if not scimitar else O_ACCENT, step=0.45,
        )

    # Long tufted horse-like black antelope tail tassel
    t_root = rear_pt + R_spine @ np.array([0.0, 1.25 * s, -2.65 * s])
    if kind == 'run':
        t_mid = t_root + np.array([0.25 * math.sin(p) * s, -0.65 * s, -3.4 * s])
        t_tip = t_mid + np.array([0.45 * math.sin(p - 0.6) * s, -1.15 * s, -3.6 * s])
    elif kind == 'sleep':
        t_mid = t_root + np.array([1.2 * s, -1.8 * s, -1.8 * s])
        t_tip = t_mid + np.array([1.8 * s, -1.2 * s, -1.2 * s])
    else:
        t_mid = t_root + np.array([tail_swish * 0.45 * s, -2.85 * s, -1.25 * s])
        t_tip = t_mid + np.array([tail_swish * 0.95 * s, -3.25 * s, -0.65 * s])
    m.limb(t_root, t_mid, 0.78 * s, 0.62 * s, O_COAT, step=0.38)
    m.limb(t_mid, t_tip, 0.92 * s, 0.48 * s, O_MASK, step=0.36)

    # ---- Proud Sculpted Neck, Gemsbok Masked Head & Long Ridged Scimitar Horns ----
    hs = s * head_scale
    neck_mat = O_ACCENT if scimitar else O_COAT
    hy = front_y + 7.6 * s
    hz = front_z + 3.4 * s
    hx = 0.0
    pitch = 0.12
    yaw = 0.0
    roll = 0.0

    if kind == 'idle':
        hy += 0.18 * breath * s
        yaw = 0.08 * math.sin(p)
    elif kind == 'forage':
        # Deep graceful neck reach down to oasis water / desert scrub (horns sweep cleanly up-forward!)
        hy = front_y + (7.6 - 11.2 * drink) * s
        hz = front_z + (3.4 + 5.2 * drink) * s
        pitch = 0.12 + 0.78 * drink
        yaw = 0.12 * math.sin(p)
    elif kind == 'walk':
        hy = front_y + (7.4 - 0.32 * math.sin(p * 2.0)) * s
        hz = front_z + (3.7 + 0.28 * math.cos(p * 2.0)) * s
        pitch = 0.14
    elif kind == 'alert':
        idx_a = int(t * 4) % 4
        hy = front_y + 8.6 * s
        hz = front_z + 2.9 * s
        pitch = 0.04
        yaw = [0.0, 0.22, 0.20, -0.14][idx_a]
        hx = math.sin(yaw) * 0.9 * s
    elif kind == 'run':
        hy = front_y + 6.6 * s
        hz = front_z + 4.5 * s
        pitch = 0.18
    elif kind == 'groom':
        # Turning head gracefully back toward flank (kept gentle so long horns stay inside 64x64!)
        hy = front_y + (6.8 - 1.6 * groom) * s
        hz = front_z + (3.2 - 3.8 * groom) * s
        hx = -2.2 * groom * s
        yaw = -1.18 * groom
        pitch = 0.34 * groom
    elif kind == 'sleep':
        # Calm upright rest in desert shade, scimitar horns held serenely upright!
        hy = front_y + 6.8 * s + 0.10 * breath * s
        hz = front_z + 2.4 * s
        pitch = 0.16
        yaw = 0.14
    elif kind == 'special':
        # LOWER horn-threat display: chin tucked deep to brisket, long scimitar horns aimed straight forward like lances!
        hy = front_y + (7.6 - 5.6 * threat_k) * s
        hz = front_z + (3.4 + 2.0 * threat_k) * s
        pitch = 0.12 + 1.36 * threat_k
        yaw = 0.08 * math.sin(p) * threat_k
    elif kind == 'stand_up':
        hy = front_y + (6.8 + 0.8 * rise_k) * s
        hz = front_z + (2.8 + 0.6 * rise_k) * s
        pitch = 0.24 - 0.12 * rise_k

    head = np.array([hx, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * hs)

    def head_ell(pos: tuple[float, float, float], r: tuple[float, float, float], mat: int, R_extra: np.ndarray | None = None) -> None:
        rs = (r[0] * hs, r[1] * hs, r[2] * hs)
        m.ell(hp(*pos), rs, mat, R=rot if R_extra is None else rot @ R_extra)

    # Sculpted muscular antelope neck + dark throat mane edge
    neck_base = front_pt + np.array([0.0, 0.95 * s, 0.65 * s])
    neck_top = hp(0.0, -0.85, -0.95)
    nw = 1.18 if bull else (0.94 if cow else 1.02)
    m.limb(neck_base, neck_top, 2.75 * s * nw, 1.95 * hs * nw, neck_mat, step=0.40)
    if not calf:
        m.limb(
            neck_base + np.array([0.0, -1.35 * s, 1.15 * s]),
            neck_top + rot @ np.array([0.0, -0.85 * hs, 0.85 * hs]),
            0.95 * s, 0.72 * hs, O_MASK, step=0.42,
        )

    # Noble elongated antelope skull & muzzle
    base_face = O_COAT if calf else O_WHITE
    head_ell((0.0, 0.20, -0.25), (2.05, 2.15, 2.55), base_face)
    head_ell((0.0, -0.35, 1.95), (1.42, 1.35, 2.15), base_face)
    head_ell((0.0, -0.65, 3.55), (1.08, 0.98, 1.35), O_WHITE if not calf else O_COAT)
    head_ell((0.0, -0.58, 4.45), (0.68, 0.56, 0.62), O_HOOF)

    # Iconic Gemsbok black facial harness mask (adults 0..2 ONLY; calf 3 has uniform warm fawn face!)
    if not calf:
        # Forehead dark diamond patch between horn bases + bridge stripe + cheek-to-chin bridle!
        head_ell((0.0, 1.05, 0.55), (1.18, 0.85, 1.35), O_MASK)
        head_ell((0.0, -0.05, 2.55), (0.76, 0.72, 1.15), O_MASK)
        for side in (-1.0, 1.0):
            m.limb(hp(side * 1.45, 0.45, 0.55), hp(side * 1.05, -0.85, 2.55), 0.62 * hs, 0.52 * hs, O_MASK, step=0.35)
        head_ell((0.0, -1.12, 2.35), (1.05, 0.48, 1.15), O_MASK)

    blink = (kind == 'sleep') or (kind == 'idle' and int(t * 4) % 4 == 3)
    for side in (-1.0, 1.0):
        # Long narrow desert-antelope ears tipped in dark charcoal
        ear_splay = 0.62 if not calf else 0.54
        ear_fwd = 0.24 if kind in ('alert', 'special') else (-0.18 if kind == 'run' else 0.06)
        R_ear = rot_z(-side * ear_splay) @ art.rot_x(ear_fwd)
        head_ell((side * 1.85, 1.05, -0.95), (0.72, 2.55, 0.48), O_COAT, R_ear)
        head_ell((side * 2.15, 2.65, -1.05), (0.52, 0.95, 0.38), O_MASK, R_ear)
        head_ell((side * 1.82, 1.02, -0.68), (0.40, 1.75, 0.24), O_EAR_IN, R_ear)

        # Expressive dark antelope eyes + warm desert glint
        if blink:
            head_ell((side * 1.68, 0.38, 0.68), (0.42, 0.16, 0.58), O_EYE)
        else:
            head_ell((side * 1.68, 0.38, 0.68), (0.48, 0.58, 0.64), O_EYE)
            head_ell((side * 1.78, 0.54, 0.84), (0.22, 0.22, 0.24), O_GLINT)

        # Long Sweeping Ridged Scimitar Horns (tiny buds on calf v=3!)
        if calf:
            m.limb(hp(side * 0.68, 1.65, -0.15), hp(side * 0.82, 3.45, -0.85), 0.50 * hs, 0.26 * hs, O_HORN, step=0.28)
        else:
            hlen = 1.0 if bull else (1.06 if cow else 1.02)
            hthick = 1.0 if bull else (0.78 if cow else 0.90)
            # Sweeps tall & gracefully backward in idle/walk; levels straight forward like twin lances in 'special'!
            arc_curve = 1.35 if scimitar else 1.0
            lance_straight = 1.0 - 0.78 * threat_k
            h_p0 = hp(side * 0.68, 1.68, -0.15)
            h_p1 = hp(side * 0.92, 1.68 + 4.6 * hlen, -0.15 - 1.6 * hlen * lance_straight)
            h_p2 = hp(side * 1.16, 1.68 + 8.3 * hlen, -0.15 - 5.4 * hlen * lance_straight)
            h_p3 = hp(side * 1.34, 1.68 + (9.2 - 1.0 * arc_curve * lance_straight) * hlen, -0.15 - (9.6 + 0.6 * arc_curve) * hlen * lance_straight)

            n_seg = 12
            prev_h = h_p0
            for hi in range(1, n_seg + 1):
                u0 = (hi - 1) / n_seg
                u1 = hi / n_seg
                cur_h = bezier3(h_p0, h_p1, h_p2, h_p3, u1)
                r0 = max(0.28, (0.96 * (1.0 - 0.68 * u0)) * hthick * hs)
                r1 = max(0.26, (0.96 * (1.0 - 0.72 * u1)) * hthick * hs)
                m.limb(prev_h, cur_h, r0, r1, O_HORN, step=0.30)
                if hi <= 8 and hi % 2 == 1:
                    rr = r1 * 1.14
                    m.ell(cur_h, (rr, rr, rr), O_RIDGE)
                prev_h = cur_h
            m.ell(h_p3, (0.28 * hs, 0.28 * hs, 0.32 * hs), O_RIDGE)

    _draw_oryx_legs(m, t, rear_pt, front_pt, kind, s, calf, drink_step, threat_k, rise_k)
    return m


def oryx_frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in ORYX_BLOCKS if x[1] <= col < x[1] + x[2])
    oryx_materials(v)
    return _to_frame_rgba(build_oryx(v, kind, (col - start) / n), d)


def _oryx_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, ORYX_COLS * W, 4), np.uint8)
    for col in range(ORYX_COLS):
        row[:, col * W:(col + 1) * W] = oryx_frame(v, d, col)
    return v, d, row


# ==============================================================================
# 2. DÜNEN-FENNEK (assets/wildlife/fennec.png — 52 cols x 32 rows, GROUND_ROW=52.0)
# ==============================================================================
FENNEC_BUILDS = 4
FENNEC_COLS = 52
F_COAT, F_CREAM, F_DARK, F_EYE, F_GLINT, F_EAR_IN = range(6)

FENNEC_BLOCKS = [
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


def fennec_materials(v: int) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {F_EYE: 3.7, F_GLINT: 4.8, F_EAR_IN: 1.95, F_CREAM: 1.30, F_DARK: 1.35}
    art.ink_color = lambda mat: hexc('16111e' if mat in (F_DARK, F_EYE) else '2a1d28')
    b = v % FENNEC_BUILDS
    if b == 0:
        # 0 Sahara-Creme: pale warm desert cream, white face/belly, rosy-sand inner ears, dark tail tip
        coat = ['7c5a42', 'b08664', 'dfb992', 'f8e4c4']
        cream = ['968e8e', 'c4bcba', 'ece6e2', 'ffffff']
        dark = ['1e1522', '382838', '584052', '7c5e70']
        ear_in = ['764c54', 'a67278', 'd49ea0', 'f4cac8']
    elif b == 1:
        # 1 Dünen-Zimt: warmer ochre-cinnamon back & flanks
        coat = ['683c26', '9e5e3a', 'cf8c58', 'f2bd84']
        cream = ['948884', 'c2b6b0', 'ebe2da', 'fffaf4']
        dark = ['1c121e', '342230', '543848', '785464']
        ear_in = ['74484e', 'a46c72', 'd2989a', 'f2c4c2']
    elif b == 2:
        # 2 Quarz-Silber: pale silver-sand morph matching white QUARTZ_W outcrops
        coat = ['5c6478', '8892a8', 'bac4d8', 'eef2fa']
        cream = ['8c92a2', 'bcc2d0', 'e6eaf4', 'ffffff']
        dark = ['181c2c', '2c3248', '48506c', '6c7694']
        ear_in = ['665268', '947a94', 'c2a8c0', 'ead6e8']
    else:
        # 3 Fennek-Welpe: soft warm sandy-peach juvenile puppy
        coat = ['78543e', 'ac7e5c', 'dbb28a', 'f7dfc0']
        cream = ['968e8c', 'c4bcba', 'ede6e2', 'ffffff']
        dark = ['201624', '3a2a3c', '5c4458', '806478']
        ear_in = ['7a4e58', 'aa747c', 'd8a2a6', 'f6cecc']

    ramps = [
        coat,                                               # 0 F_COAT
        cream,                                              # 1 F_CREAM
        dark,                                               # 2 F_DARK (characteristic dark tail tip!)
        ['0b0914', '161326', '26213a', '3a3352'],           # 3 F_EYE
        ['9e7e3e', 'cca656', 'f2d27c', 'fff4c2'],           # 4 F_GLINT
        ear_in,                                             # 5 F_EAR_IN
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def _draw_fennec_legs(m: art.Model, t: float, rear_y: float, front_y: float, kind: str, s: float, pounce_idx: int, groom_ear: float) -> None:
    """Dainty sandy-cream desert paws (furry soles for hot sand!)."""
    if kind == 'sleep':
        for side in (-1.0, 1.0):
            m.ell((side * 1.65 * s, 1.15 * s, 1.15 * s), (0.85 * s, 0.72 * s, 1.25 * s), F_CREAM)
        return

    seated = kind in ('alert', 'groom')
    for side in (-1.0, 1.0):
        for front in (False, True):
            hip_x = side * (1.75 if front else 1.90) * s
            hip_z = (3.8 if front else -3.9) * s
            hip_y = (front_y if front else rear_y) - 0.30 * s

            if seated and not front:
                thigh = np.array([side * 2.15 * s, rear_y - 0.55 * s, hip_z + 0.55 * s])
                hock = np.array([side * 2.05 * s, 1.25 * s, hip_z - 0.45 * s])
                paw = np.array([side * 1.85 * s, 0.75 * s, hip_z + 2.25 * s])
                m.limb((hip_x, hip_y, hip_z), thigh, 1.42 * s, 1.15 * s, F_COAT, step=0.38)
                m.limb(thigh, hock, 1.12 * s, 0.78 * s, F_COAT, step=0.36)
                m.limb(hock, paw, 0.76 * s, 0.66 * s, F_CREAM, step=0.34)
                m.ell(paw, (0.82 * s, 0.60 * s, 1.02 * s), F_CREAM)
                continue

            if kind == 'groom' and front and side < 0:
                # Near forepaw raised up to brush down the giant ear!
                elbow = np.array([side * 2.15 * s, front_y + 1.25 * s, hip_z + 1.35 * s])
                paw = np.array([side * 1.65 * s, front_y + (2.45 + 2.15 * groom_ear) * s, hip_z + 2.65 * s])
                m.limb((hip_x, hip_y, hip_z), elbow, 1.05 * s, 0.82 * s, F_COAT, step=0.36)
                m.limb(elbow, paw, 0.80 * s, 0.66 * s, F_CREAM, step=0.34)
                m.ell(paw, (0.78 * s, 0.65 * s, 0.88 * s), F_CREAM)
                continue

            swing = 0.0
            lift = 0.0
            if kind == 'forage':
                # Rapid alternating forepaw sand-digging (Scharren im Sand)!
                if front:
                    dig_phase = (t * 2.0 + (0.5 if side > 0 else 0.0)) % 1.0
                    swing = (1.85 * math.cos(dig_phase * math.tau) + 0.65) * s
                    lift = max(0.0, math.sin(dig_phase * math.tau)) * 1.65 * s
                else:
                    swing = -0.45 * s
            elif kind == 'walk':
                diag = 0.0 if ((side > 0) == front) else 0.5
                cyc = (t + diag) % 1.0
                if cyc < 0.56:
                    swing = (2.35 * s) * (1.0 - 2.0 * (cyc / 0.56))
                else:
                    c = (cyc - 0.56) / 0.44
                    swing = -(2.35 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.65 * s
            elif kind == 'stalk':
                offset = (0.25 if front else 0.0) + (0.5 if side > 0 else 0.0)
                cyc = (t + offset) % 1.0
                if cyc < 0.66:
                    swing = (1.85 * s) * (1.0 - 2.0 * (cyc / 0.66))
                else:
                    c = (cyc - 0.66) / 0.34
                    swing = -(1.85 * s) * math.cos(c * math.pi)
                    lift = math.sin(c * math.pi) * 1.25 * s
            elif kind == 'run':
                lead = 0.08 if side > 0 else -0.08
                ang = ((t + (0.48 if front else 0.0) + lead) % 1.0) * math.tau
                if front:
                    swing = 4.0 * s * math.sin(ang - 0.35)
                    lift = max(0.0, math.cos(ang)) * 2.2 * s
                else:
                    swing = -4.2 * s * math.sin(ang - 0.25)
                    lift = max(0.0, -math.cos(ang)) * 2.1 * s
            elif kind == 'special':
                # High parabolic Mäuselsprung pounce!
                if front:
                    swing = [-0.6, -1.0, 2.2, 3.5, 3.2, 3.6, 2.4, 0.8][pounce_idx] * s
                    lift = [0.0, 0.2, 2.8, 4.4, 3.8, 1.0, 0.0, 0.0][pounce_idx] * s
                else:
                    swing = [1.0, 1.4, -3.2, -4.5, -3.2, -2.2, -1.2, -0.4][pounce_idx] * s
                    lift = [0.0, 0.0, 0.8, 2.6, 4.2, 3.8, 1.6, 0.0][pounce_idx] * s

            paw_x = hip_x * (0.72 if kind == 'walk' else 0.88)
            foot_y = max(0.70 * s, 0.70 * s + lift)
            root = np.array([hip_x, hip_y, hip_z])
            foot = np.array([paw_x, foot_y, hip_z + swing])
            mid = np.array([
                0.5 * (hip_x + paw_x),
                foot_y + (hip_y - foot_y) * 0.46,
                hip_z + swing * 0.48 + (0.35 * s if front else -1.15 * s),
            ])
            m.limb(root, mid, (1.18 if front else 1.42) * s, 0.84 * s, F_COAT, step=0.36)
            m.limb(mid, foot, 0.80 * s, 0.66 * s, F_CREAM, step=0.34)
            m.ell(foot + np.array([0.0, 0.0, 0.20 * s]), (0.78 * s, 0.58 * s, 0.98 * s), F_CREAM)


def build_fennec(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    pup = (v % FENNEC_BUILDS == 3)
    # Markedly daintier & smaller than woodland fox.png (0.78 adult, 0.59 pup), with giant satellite ears!
    s = 0.59 if pup else 0.78
    ear_scale = 1.18 if pup else 1.0
    head_scale = 1.14 if pup else 1.02

    p = t * math.tau
    b = math.sin(p)
    pounce_idx = int(t * 8) % 8
    groom_ear = [0.35, 0.95, 1.0, 0.45][int(t * 4) % 4] if kind == 'groom' else 0.0

    # Curled desert sand-ball sleep with giant ears relaxed & dark-tipped fluffy tail across snout
    if kind == 'sleep':
        by = (4.2 + 0.14 * b) * s
        for i in range(9):
            ang = -0.55 + 2.65 * (i / 8.0)
            rad = 3.95 * s
            m.ell((math.sin(ang) * rad * 0.90 - 0.45 * s, by + 0.25 * s * math.sin(i * 0.4), math.cos(ang) * rad - 0.45 * s),
                  (3.05 * s, 2.85 * s, 3.05 * s), F_COAT)
        hx, hy, hz = -1.45 * s, by + 1.65 * s, 3.25 * s
        rot_h = art.rot_y(-0.48) @ art.rot_x(0.18)
        hs = s * head_scale
        m.ell((hx, hy, hz), (2.45 * hs, 2.25 * hs, 2.55 * hs), F_COAT, R=rot_h)
        m.ell((hx - 0.75 * hs, hy - 0.50 * hs, hz + 1.75 * hs), (1.05 * hs, 0.85 * hs, 1.45 * hs), F_CREAM, R=rot_h)
        m.ell((hx - 1.15 * hs, hy - 0.48 * hs, hz + 2.65 * hs), (0.48 * hs, 0.42 * hs, 0.48 * hs), F_EYE, R=rot_h)
        # Giant fennec ears folded softly outward-back during sleep
        es = hs * ear_scale
        for side in (-1.0, 1.0):
            R_ear = rot_h @ rot_z(-side * 0.78) @ art.rot_x(-0.28)
            ep = np.array([hx, hy, hz]) + rot_h @ np.array([side * 1.65 * hs, 1.65 * hs, -0.35 * hs])
            m.ell(ep + R_ear @ np.array([0.0, 2.45 * es, -0.15 * es]), (1.65 * es, 3.45 * es, 0.48 * es), F_COAT, R=R_ear)
            m.ell(ep + R_ear @ np.array([0.0, 2.25 * es, 0.16 * es]), (1.12 * es, 2.75 * es, 0.28 * es), F_EAR_IN, R=R_ear)
        # Lush bushy tail with dark fennec tip wrapped across nose
        p0 = np.array([2.2 * s, by - 0.1 * s, -3.5 * s])
        p1 = np.array([5.8 * s, by - 0.2 * s, -0.5 * s])
        p2 = np.array([4.8 * s, by - 0.3 * s, 5.2 * s])
        p3 = np.array([-0.7 * s, by - 0.3 * s, 5.3 * s])
        for ti, r_t in enumerate((2.0, 2.6, 2.95, 2.95, 2.7, 2.25, 1.7)):
            pt = bezier3(p0, p1, p2, p3, ti / 6.0)
            m.ell(pt, (r_t * 1.08 * s, r_t * 0.88 * s, r_t * 1.08 * s), F_DARK if ti >= 5 else F_COAT)
        _draw_fennec_legs(m, t, by, by, kind, s, 0, 0.0)
        return m

    rear_y = 8.4 * s
    front_y = 8.2 * s
    if kind == 'idle':
        rear_y += 0.14 * b * s
        front_y += 0.16 * b * s
    elif kind == 'forage':
        # Rump high, chest low while furiously digging sand with forepaws!
        rear_y = 9.0 * s
        front_y = 6.6 * s + 0.18 * math.sin(p * 2.0) * s
    elif kind == 'walk':
        bob = 0.22 * math.cos(p * 2.0) * s
        rear_y += bob
        front_y += bob
    elif kind == 'alert':
        rear_y = 5.0 * s
        front_y = 9.4 * s
    elif kind == 'groom':
        rear_y = 5.0 * s
        front_y = 8.8 * s
    elif kind == 'run':
        wave = math.sin(p)
        lift_g = 1.25 * max(0.0, math.sin(p - 0.3)) * s
        rear_y = 8.5 * s + lift_g - 0.72 * wave * s
        front_y = 8.3 * s + lift_g + 0.82 * wave * s
    elif kind == 'stalk':
        rear_y = (5.8 + 0.10 * math.cos(p * 2.0)) * s
        front_y = (5.2 + 0.10 * math.cos(p * 2.0)) * s
    elif kind == 'special':
        # High parabolic Mäuselsprung arc!
        rear_y = [5.6, 5.0, 8.8, 12.2, 14.8, 15.2, 11.4, 8.0][pounce_idx] * s
        front_y = [6.8, 6.2, 13.4, 16.4, 14.2, 8.6, 6.4, 7.8][pounce_idx] * s

    spine_slope = math.atan2(front_y - rear_y, 7.8 * s)
    R_spine = art.rot_x(-spine_slope)
    for i in range(9):
        u = i / 8.0
        sz = (-4.0 + 7.8 * u) * s
        arch = math.sin(u * math.pi)
        flex = (0.65 * arch * s if kind == 'special' and pounce_idx in (3, 4, 5) else 0.0)
        sy = rear_y * (1.0 - u) + front_y * u + flex
        m.ell((0.0, sy, sz), ((2.55 + 0.38 * arch) * s, (2.75 + 0.45 * arch) * s, (2.25 + 0.45 * arch) * s), F_COAT, R=R_spine)

    # Snowy white belly & fluffy chest bib
    for u_b in (0.22, 0.50, 0.78):
        bz = (-3.6 + 7.2 * u_b) * s
        by_b = rear_y * (1.0 - u_b) + front_y * u_b - 1.55 * s
        m.ell((0.0, by_b, bz), (2.15 * s, 1.45 * s, 2.25 * s), F_CREAM, R=R_spine)
    m.ell((0.0, front_y - 0.45 * s, 4.25 * s), (2.15 * s, 2.15 * s, 1.85 * s), F_CREAM, R=R_spine)

    # Disproportionately plush bushy fennec tail with DARK tip!
    t_root = np.array([0.0, rear_y + 0.15 * s, -4.3 * s])
    sway = (1.35 * math.sin(p - 0.7) if kind in ('walk', 'forage') else (0.55 * b if kind == 'idle' else 0.0)) * s
    if kind in ('alert', 'groom'):
        p0, p1, p2, p3 = t_root, np.array([0.4 * s, rear_y - 1.2 * s, -7.4 * s]), np.array([1.2 * s, 2.0 * s, -10.8 * s]), np.array([2.0 * s, 2.3 * s, -14.0 * s])
    elif kind == 'run':
        p0 = t_root
        p1 = np.array([0.3 * b * s, rear_y + 0.2 * s, -7.8 * s])
        p2 = np.array([0.6 * math.sin(p - 0.6) * s, rear_y + 0.3 * s, -11.8 * s])
        p3 = np.array([0.9 * math.sin(p - 1.1) * s, rear_y + 0.1 * s, -15.6 * s])
    elif kind == 'stalk':
        p0, p1, p2, p3 = t_root, np.array([0.2 * b * s, rear_y - 0.3 * s, -7.6 * s]), np.array([0.35 * b * s, rear_y - 0.7 * s, -11.4 * s]), np.array([0.5 * b * s, rear_y - 0.8 * s, -15.0 * s])
    elif kind == 'special':
        tl = [1.4, 2.8, 1.2, 2.8, 6.4, 8.8, 7.0, 2.2][pounce_idx] * s
        tb = [-13.4, -12.8, -14.4, -14.0, -12.0, -9.8, -11.0, -13.6][pounce_idx] * s
        p0, p1, p2, p3 = t_root, np.array([0.0, rear_y + tl * 0.32, -7.2 * s]), np.array([0.0, rear_y + tl * 0.72, 0.5 * (-7.2 * s + tb)]), np.array([0.0, rear_y + tl, tb])
    else:
        p0, p1, p2, p3 = t_root, np.array([sway * 0.35, rear_y - 1.4 * s, -7.2 * s]), np.array([sway * 0.75, 3.0 * s, -10.6 * s]), np.array([sway * 1.1, 3.4 * s, -13.8 * s])

    for ti, r_t in enumerate((2.05, 2.55, 3.05, 3.25, 3.15, 2.85, 2.35, 1.75)):
        pt = bezier3(p0, p1, p2, p3, ti / 7.0)
        m.ell(pt, (r_t * 0.98 * s, r_t * 1.00 * s, r_t * 1.18 * s), F_DARK if ti >= 5 else F_COAT)

    # Petite delicate face + ICONIC ENORMOUS TRIANGULAR SATELLITE EARS!
    hs = s * head_scale
    hy = front_y + 5.2 * s
    hz = 5.9 * s
    pitch = 0.08
    yaw = 0.0
    roll = 0.0
    ear_swivel_L = 0.0
    ear_swivel_R = 0.0

    if kind == 'idle':
        hy = front_y + (5.3 + 0.16 * b) * s
        yaw = 0.10 * b
        ear_swivel_L = 0.16 * math.sin(p)
        ear_swivel_R = -0.16 * math.sin(p)
    elif kind == 'forage':
        # Nose right down in the sand while forepaws dig!
        hy = 3.6 * s + 0.20 * abs(b) * s
        hz = 7.6 * s
        pitch = 0.64
        yaw = 0.14 * b
        ear_swivel_L = 0.25
        ear_swivel_R = 0.25
    elif kind == 'walk':
        hy = front_y + 4.5 * s
        hz = 6.5 * s
        pitch = 0.14
    elif kind == 'alert':
        # Seated LISTEN with cocked head-tilt & swiveling giant radar ears!
        idx_a = int(t * 4) % 4
        hy = front_y + 5.6 * s
        hz = 5.4 * s
        pitch = 0.10
        roll = [0.12, 0.42, 0.46, 0.18][idx_a]
        yaw = [0.0, 0.14, 0.16, 0.04][idx_a]
        ear_swivel_L = [0.15, 0.38, -0.22, 0.10][idx_a]
        ear_swivel_R = [-0.15, -0.28, 0.36, -0.08][idx_a]
    elif kind == 'groom':
        hy = front_y + (4.2 - 0.8 * groom_ear) * s
        hz = 5.6 * s
        roll = -0.36 * groom_ear
        yaw = -0.24 * groom_ear
        pitch = 0.22 * groom_ear
    elif kind == 'run':
        hy = front_y + (4.2 + 0.30 * math.sin(p)) * s
        hz = 7.2 * s
        pitch = 0.06
    elif kind == 'stalk':
        hy = front_y + 2.6 * s
        hz = 7.5 * s
        pitch = 0.10
        ear_swivel_L = 0.32
        ear_swivel_R = 0.32
    elif kind == 'special':
        hy = front_y + [3.6, 3.2, 5.0, 5.4, 3.6, -1.6, -2.2, 3.4][pounce_idx] * s
        hz = [6.6, 6.4, 7.2, 7.8, 8.0, 7.6, 7.0, 6.6][pounce_idx] * s
        pitch = [0.26, 0.32, -0.22, -0.10, 0.35, 0.78, 0.72, 0.20][pounce_idx]

    head = np.array([math.sin(yaw) * 0.9 * s, hy, hz])
    rot = art.rot_y(yaw) @ art.rot_x(pitch) @ rot_z(roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head + rot @ (np.array([x, y, z]) * hs)

    def head_ell(pos: tuple[float, float, float], r: tuple[float, float, float], mat: int, R_extra: np.ndarray | None = None) -> None:
        rs = (r[0] * hs, r[1] * hs, r[2] * hs)
        m.ell(hp(*pos), rs, mat, R=rot if R_extra is None else rot @ R_extra)

    neck_base = np.array([0.0, front_y + 0.55 * s, 3.5 * s])
    throat = hp(0.0, -0.95, -1.15)
    m.limb(neck_base, throat, 2.10 * s, 1.68 * hs, F_COAT, step=0.40)
    m.limb(neck_base + np.array([0.0, -0.75 * s, 0.55 * s]), throat + rot @ np.array([0.0, -0.45 * hs, 0.65 * hs]), 1.60 * s, 1.25 * hs, F_CREAM, step=0.42)

    # Rounded skull + snowy white facial mask/cheeks + tiny pointed dainty snout
    head_ell((0.0, 0.20, -0.15), (2.48, 2.38, 2.52), F_COAT)
    for side in (-1.0, 1.0):
        head_ell((side * 1.88, -0.55, 0.45), (1.18, 1.22, 1.65), F_CREAM)
        head_ell((side * 1.05, -0.65, 1.65), (1.02, 0.88, 1.45), F_CREAM)
    head_ell((0.0, -0.38, 1.95), (1.08, 0.88, 1.55), F_CREAM)
    head_ell((0.0, -0.52, 3.05), (0.76, 0.64, 1.05), F_CREAM)
    head_ell((0.0, -0.44, 3.85), (0.50, 0.44, 0.48), F_EYE)

    blink = kind == 'idle' and t >= 0.75
    es = hs * ear_scale * 1.22
    for side in (-1.0, 1.0):
        # ENORMOUS TRIANGULAR SATELLITE EARS (broad base tapering to pointed tip + rosy inner pinna + cream fluff!)
        splay = 0.58 if kind in ('alert', 'stalk', 'special') else (0.82 if kind == 'run' else 0.68)
        asym_fwd = (0.14 if side < 0 else -0.10) if kind in ('idle', 'walk') else 0.0
        fwd = (ear_swivel_L if side < 0 else ear_swivel_R) + asym_fwd + (-0.32 if kind == 'run' else 0.14)
        if kind == 'groom' and side < 0:
            # Near ear pulled forward-down under grooming paw!
            splay = 0.98 + 0.35 * groom_ear
            fwd = 0.52 * groom_ear
        R_ear = rot @ rot_z(-side * splay) @ art.rot_x(fwd)
        ebase = hp(side * 1.55, 1.50, -0.25 + (0.18 if side < 0 else -0.18))
        # Outer sandy-coat ear shell (tapered wide-to-pointed multi-ellipsoid triangle)
        m.ell(ebase + R_ear @ np.array([0.0, 2.05 * es, -0.18 * es]), (2.10 * es, 2.65 * es, 0.58 * es), F_COAT, R=R_ear)
        m.ell(ebase + R_ear @ np.array([0.0, 4.65 * es, -0.16 * es]), (1.48 * es, 2.55 * es, 0.48 * es), F_COAT, R=R_ear)
        m.ell(ebase + R_ear @ np.array([0.0, 6.85 * es, -0.14 * es]), (0.82 * es, 1.38 * es, 0.40 * es), F_COAT, R=R_ear)
        # Warm rosy-sand inner pinna dish + cream basal ear-hair tuft!
        m.ell(ebase + R_ear @ np.array([0.0, 2.25 * es, 0.18 * es]), (1.55 * es, 2.30 * es, 0.34 * es), F_EAR_IN, R=R_ear)
        m.ell(ebase + R_ear @ np.array([0.0, 4.55 * es, 0.16 * es]), (1.02 * es, 2.00 * es, 0.30 * es), F_EAR_IN, R=R_ear)
        m.ell(ebase + R_ear @ np.array([-side * 0.48 * es, 0.95 * es, 0.30 * es]), (0.95 * es, 0.90 * es, 0.44 * es), F_CREAM, R=R_ear)

        # Large soulful dark desert nocturnal eyes + bright glint
        if blink:
            head_ell((side * 1.38, 0.18, 1.52), (0.52, 0.16, 0.52), F_EYE)
        else:
            head_ell((side * 1.42, 0.22, 1.55), (0.72, 0.76, 0.74), F_EYE)
            head_ell((side * 1.52, 0.42, 1.84), (0.28, 0.28, 0.28), F_GLINT)

    _draw_fennec_legs(m, t, rear_y, front_y, kind, s, pounce_idx, groom_ear)
    return m


def fennec_frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in FENNEC_BLOCKS if x[1] <= col < x[1] + x[2])
    fennec_materials(v)
    return _to_frame_rgba(build_fennec(v, kind, (col - start) / n), d)


def _fennec_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, FENNEC_COLS * W, 4), np.uint8)
    for col in range(FENNEC_COLS):
        row[:, col * W:(col + 1) * W] = fennec_frame(v, d, col)
    return v, d, row


# ==============================================================================
# 3. PINSELOHR-SPRINGMAUS (assets/wildlife/jerboa.png — 52 cols x 32 rows)
# ==============================================================================
JERBOA_BUILDS = 4
JERBOA_COLS = 52
J_COAT, J_WHITE, J_BAND, J_PAW_EAR, J_EYE, J_GLINT = range(6)

JERBOA_BLOCKS = [
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


def jerboa_materials(v: int) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {J_GLINT: 4.8, J_EYE: 3.9, J_WHITE: 1.55, J_BAND: 1.65, J_PAW_EAR: 1.55}
    art.ink_color = lambda mat: hexc('14101e' if mat in (J_BAND, J_EYE) else '281c26')
    b = v % JERBOA_BUILDS
    if b == 0:
        # 0 Dünengold: warm golden dune sand + snowy belly + jet-black band & white banner tuft
        coat = ['6e4628', 'a46e3c', 'd69e5c', 'f5cb88']
        white = ['968e90', 'c6bec0', 'eee8e6', 'ffffff']
        band = ['120e1a', '231c30', '3c314c', '5a4b6c']
        ear = ['785058', 'a8767e', 'd6a2a8', 'f4ccd0']
    elif b == 1:
        # 1 Steppen-Umbra: reddish-cinnamon desert umber
        coat = ['582e20', '8c4e32', 'bf764c', 'e8a472']
        white = ['928684', 'c0b4b0', 'eae0dc', 'fffaf4']
        band = ['140f1a', '261d2e', '40324a', '604c6a']
        ear = ['724850', 'a26e76', 'd09aa0', 'f0c4c6']
    elif b == 2:
        # 2 Mondquarz: pale ivory-silver quartz morph with slate-indigo band & snow-white tuft
        coat = ['5a6278', '8690a8', 'b8c2d8', 'edf2fa']
        white = ['8e94a4', 'bec4d4', 'e8ecf6', 'ffffff']
        band = ['1c2034', '323854', '505878', '7680a2']
        ear = ['68546c', '967c98', 'c4aac4', 'ecd8ec']
    else:
        # 3 Jung-Springmaus (0.76x): warm sandy-buff juvenile puffball
        coat = ['724a2c', 'a87444', 'da9f62', 'f7ce90']
        white = ['968e90', 'c6bec0', 'eee8e6', 'ffffff']
        band = ['14101c', '261f34', '403552', '605272']
        ear = ['7a525a', 'aa7880', 'd8a6ac', 'f6d0d4']

    ramps = [
        coat,                                               # 0 J_COAT
        white,                                              # 1 J_WHITE (belly + white brush tuft!)
        band,                                               # 2 J_BAND (black subterminal tail band!)
        ear,                                                # 3 J_PAW_EAR (pinkish-sand tarsi & inner ears)
        ['0a0814', '151126', '251f3a', '383052'],           # 4 J_EYE
        ['a4989e', 'd0c6ca', 'f0eaec', 'ffffff'],           # 5 J_GLINT
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def build_jerboa(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    juv = (v % JERBOA_BUILDS == 3)
    s = 0.76 if juv else 1.0
    p = t * math.tau
    b = math.sin(p)

    # Sleep: tiny round feather-puff ball with folded ears & banner tail curled neatly beside toes
    if kind == 'sleep':
        by = (3.4 + 0.10 * b) * s
        m.ell((0.0, by, 0.0), (3.15 * s, 2.85 * s, 3.35 * s), J_COAT)
        m.ell((0.0, by - 1.15 * s, 0.45 * s), (2.55 * s, 1.45 * s, 2.65 * s), J_WHITE)
        m.ell((0.0, by + 0.65 * s, 2.35 * s), (2.25 * s, 2.05 * s, 2.25 * s), J_COAT)
        for side in (-1.0, 1.0):
            m.limb((side * 1.45 * s, by + 1.85 * s, 1.55 * s), (side * 1.95 * s, by + 1.45 * s, -1.65 * s), 0.72 * s, 0.45 * s, J_PAW_EAR, step=0.35)
            m.ell((side * 1.45 * s, by + 0.85 * s, 3.65 * s), (0.38 * s, 0.14 * s, 0.38 * s), J_EYE)
            m.limb((side * 1.65 * s, 0.58 * s, -0.85 * s), (side * 1.55 * s, 0.58 * s, 2.65 * s), 0.52 * s, 0.44 * s, J_PAW_EAR, step=0.34)
        # Curled banner tail around side showing crisp black band + white feather tuft!
        p0, p1, p2, p3 = np.array([0.8 * s, 1.6 * s, -3.0 * s]), np.array([4.8 * s, 1.0 * s, -2.4 * s]), np.array([5.2 * s, 0.9 * s, 3.2 * s]), np.array([1.8 * s, 1.0 * s, 4.8 * s])
        for ti in range(13):
            u = ti / 12.0
            pt = bezier3(p0, p1, p2, p3, u)
            if ti < 8:
                m.ell(pt, (0.52 * s, 0.48 * s, 0.52 * s), J_PAW_EAR)
            elif ti < 10:
                m.ell(pt, (0.85 * s, 0.72 * s, 0.85 * s), J_BAND)
            else:
                r_tf = (1.15 if ti == 11 else 0.88) * s
                m.ell(pt, (r_tf, r_tf * 0.78, r_tf), J_WHITE)
        return m

    # Default upright bipedal spherical kangaroo-mouse body perched high on stilt tarsi!
    bx, by, bz = 0.0, 8.4 * s, 0.3 * s
    body_pitch = -0.34  # pitched slightly upright (~20 deg)
    body_roll = 0.0
    head_pitch = 0.12
    head_yaw = 0.0
    ear_perk = 0.32

    # Long slender Z-folded kangaroo hindlegs (hip -> forward knee -> high rear heel/ankle -> long forward tarsus -> toes!)
    heel_L = np.array([-1.95 * s, 3.85 * s, -3.15 * s])
    heel_R = np.array([1.95 * s, 3.85 * s, -3.15 * s])
    toe_L = np.array([-1.85 * s, 0.56 * s, 1.85 * s])
    toe_R = np.array([1.85 * s, 0.56 * s, 1.85 * s])
    fpaw_reach = 0.0
    tail_mode = 'idle'

    if kind == 'idle':
        by += 0.16 * b * s
        head_yaw = 0.10 * b
    elif kind == 'forage':
        # Bobbing forward to nibble seeds held in tiny forepaws!
        idx = int(t * 6) % 6
        dip = [0.35, 0.90, 1.0, 0.85, 0.95, 0.30][idx]
        by = (8.4 - 1.85 * dip) * s
        bz = (0.3 + 1.55 * dip) * s
        body_pitch = -0.34 + 0.62 * dip
        head_pitch = 0.12 + 0.26 * dip
        fpaw_reach = dip
    elif kind == 'walk':
        # Bouncy 8-frame bipedal kangaroo hop!
        idx = int(t * 8) % 8
        hop_y = [6.8, 9.0, 11.8, 13.0, 11.4, 9.0, 6.6, 7.6][idx] * s
        hop_z = [-0.4, 0.6, 1.4, 1.6, 1.2, 0.6, 0.0, -0.2][idx] * s
        by, bz = hop_y, hop_z
        body_pitch = [-0.18, -0.45, -0.25, -0.05, 0.15, 0.10, -0.15, -0.28][idx]
        air = max(0.0, hop_y - 8.0 * s)
        heel_z = [-2.9, -5.0, -6.0, -4.8, -3.4, -2.9, -2.8, -3.0][idx] * s
        toe_y = [0.56, 1.05, 3.85, 5.15, 3.55, 1.25, 0.56, 0.56][idx] * s
        toe_z = [1.7, -2.2, -3.2, -0.8, 1.9, 2.3, 1.8, 1.8][idx] * s
        heel_L = np.array([-1.95 * s, toe_y + 2.85 * s + 0.15 * air, heel_z])
        heel_R = np.array([1.95 * s, toe_y + 2.85 * s + 0.15 * air, heel_z])
        toe_L = np.array([-1.85 * s, toe_y, toe_z])
        toe_R = np.array([1.85 * s, toe_y, toe_z])
        tail_mode = 'hop'
    elif kind == 'alert':
        # Tall vertical tiptoe sentry look!
        idx_a = int(t * 4) % 4
        by = 11.4 * s
        bz = -0.2 * s
        body_pitch = -0.68
        head_pitch = 0.42
        head_yaw = [0.0, 0.22, -0.18, 0.06][idx_a]
        ear_perk = 0.16
        heel_L = np.array([-1.85 * s, 5.45 * s, -1.85 * s])
        heel_R = np.array([1.85 * s, 5.45 * s, -1.85 * s])
        toe_L = np.array([-1.75 * s, 0.65 * s, 1.35 * s])
        toe_R = np.array([1.75 * s, 0.65 * s, 1.35 * s])
    elif kind == 'run':
        # Long high-speed desert escape leap with extended hind tarsi & streaming banner tail!
        idx = int(t * 8) % 8
        by = [5.6, 8.8, 12.8, 14.2, 12.4, 8.6, 5.5, 6.4][idx] * s
        bz = [-0.6, 1.2, 2.4, 2.6, 2.0, 1.0, 0.0, -0.3][idx] * s
        body_pitch = [-0.12, -0.38, -0.10, 0.08, 0.24, 0.18, -0.10, -0.22][idx]
        heel_z = [-2.5, -5.8, -7.8, -7.2, -4.6, -2.8, -2.4, -2.6][idx] * s
        toe_y = [0.58, 1.4, 5.8, 7.2, 5.2, 1.6, 0.58, 0.58][idx] * s
        toe_z = [1.4, -3.8, -6.4, -5.2, 0.6, 2.4, 1.6, 1.5][idx] * s
        heel_L = np.array([-1.90 * s, toe_y + 2.35 * s, heel_z])
        heel_R = np.array([1.90 * s, toe_y + 2.35 * s, heel_z])
        toe_L = np.array([-1.80 * s, toe_y, toe_z])
        toe_R = np.array([1.80 * s, toe_y, toe_z])
        tail_mode = 'run'
    elif kind == 'groom':
        # Seated pulling its long black-and-white tufted tail forward through tiny forepaws!
        by = 6.2 * s
        bz = -0.4 * s
        body_pitch = -0.15
        head_pitch = 0.42
        head_yaw = -0.28
        fpaw_reach = 0.95
        tail_mode = 'groom'
    elif kind == 'bark':
        # Rapid hind-foot sand-drumming ('Fußtrommeln')!
        idx = int(t * 6) % 6
        by = (8.4 + 0.40 * (idx % 2)) * s
        body_pitch = -0.28
        drum_L = [2.45, 0.56, 2.55, 0.56, 2.35, 0.56][idx] * s
        drum_R = [0.56, 2.45, 0.56, 2.55, 0.56, 2.35][idx] * s
        toe_L = np.array([-1.95 * s, drum_L, (2.35 if drum_L > 1.0 * s else 1.65) * s])
        toe_R = np.array([1.95 * s, drum_R, (2.35 if drum_R > 1.0 * s else 1.65) * s])
        heel_L = np.array([-2.05 * s, 3.65 * s + 0.4 * drum_L, -2.95 * s])
        heel_R = np.array([2.05 * s, 3.65 * s + 0.4 * drum_R, -2.95 * s])
    elif kind == 'special':
        # Joyful sideways 'Sand-Staubbad' (rolling onto flank in warm dry sand & kicking legs)!
        idx = int(t * 8) % 8
        roll_seq = [0.45, 1.25, 1.65, 1.45, -1.25, -1.60, -0.85, 0.0][idx]
        body_roll = roll_seq
        by = [5.4, 3.6, 3.3, 3.5, 3.6, 3.3, 4.6, 6.8][idx] * s
        bx = math.sin(roll_seq) * 1.15 * s
        body_pitch = -0.10 if abs(roll_seq) > 0.5 else -0.28
        if abs(roll_seq) > 0.6:
            sd = 1.0 if roll_seq > 0 else -1.0
            heel_L = np.array([bx - 2.4 * s, by + 0.8 * sd * s, -2.4 * s])
            heel_R = np.array([bx + 2.4 * s, by - 0.8 * sd * s, -2.4 * s])
            toe_L = np.array([bx - (3.2 if idx % 2 == 0 else 2.2) * s, max(0.7 * s, by + 1.8 * sd * s), 1.8 * s])
            toe_R = np.array([bx + (3.2 if idx % 2 == 1 else 2.2) * s, max(0.7 * s, by - 1.8 * sd * s), 1.8 * s])
        tail_mode = 'bath'

    R_body = rot_z(body_roll) @ art.rot_x(body_pitch)
    center = np.array([bx, by, bz])

    # Spherical puffball body + snowy chest/belly (compact so Z-folded stilt hindlegs read crisply underneath!)
    m.ell(center, (2.68 * s, 2.82 * s, 3.05 * s), J_COAT, R=R_body)
    m.ell(center + R_body @ np.array([0.0, -1.02 * s, 0.85 * s]), (2.22 * s, 2.02 * s, 2.22 * s), J_WHITE, R=R_body)

    # Large rounded jerboa head nestled seamlessly onto shoulders
    h_pos = center + R_body @ np.array([0.0, 2.05 * s, 1.82 * s])
    R_head = R_body @ art.rot_y(head_yaw) @ art.rot_x(head_pitch)
    m.ell(h_pos, (2.42 * s, 2.32 * s, 2.52 * s), J_COAT, R=R_head)
    m.ell(h_pos + R_head @ np.array([0.0, -0.65 * s, 1.35 * s]), (1.62 * s, 1.22 * s, 1.52 * s), J_WHITE, R=R_head)
    m.ell(h_pos + R_head @ np.array([0.0, -0.35 * s, 2.42 * s]), (0.48 * s, 0.42 * s, 0.48 * s), J_PAW_EAR, R=R_head)

    # Tiny tucked kangaroo forepaws at snowy chest!
    for side in (-1.0, 1.0):
        sh_p = center + R_body @ np.array([side * 1.22 * s, 0.65 * s, 2.08 * s])
        if kind == 'groom':
            pw_p = center + np.array([(-0.45 + side * 0.65) * s, 0.35 * s, 3.35 * s])
        else:
            pw_p = sh_p + R_body @ np.array([-side * 0.35 * s, (-0.85 - 0.55 * fpaw_reach) * s, (0.95 + 1.15 * fpaw_reach) * s])
        m.limb(sh_p, pw_p, 0.58 * s, 0.46 * s, J_WHITE, step=0.32)
        m.ell(pw_p, (0.50 * s, 0.42 * s, 0.56 * s), J_PAW_EAR)

    # Long translucent-pink & sandy rabbit-like jerboa ears + big glossy dark bead eyes!
    for side in (-1.0, 1.0):
        splay = ear_perk + (0.28 if kind == 'run' else 0.0)
        fwd_e = (-0.35 if kind == 'run' else 0.08) + (0.10 if side < 0 else -0.08)
        R_ear = R_head @ rot_z(-side * splay) @ art.rot_x(fwd_e)
        eb = h_pos + R_head @ np.array([side * 1.35 * s, 1.55 * s, -0.25 * s])
        m.ell(eb + R_ear @ np.array([0.0, 2.75 * s, -0.12 * s]), (1.06 * s, 3.25 * s, 0.46 * s), J_COAT, R=R_ear)
        m.ell(eb + R_ear @ np.array([0.0, 2.65 * s, 0.16 * s]), (0.72 * s, 2.68 * s, 0.30 * s), J_PAW_EAR, R=R_ear)

        # Big dark nocturnal jerboa eyes set high & wide
        m.ell(h_pos + R_head @ np.array([side * 1.65 * s, 0.35 * s, 1.15 * s]), (0.72 * s, 0.76 * s, 0.76 * s), J_EYE, R=R_head)
        m.ell(h_pos + R_head @ np.array([side * 1.80 * s, 0.56 * s, 1.40 * s]), (0.28 * s, 0.28 * s, 0.28 * s), J_GLINT, R=R_head)

    # Long Z-bent Kangaroo Hindlegs (drumstick thigh -> long slender ankle/tarsus -> 3-toed sand foot!)
    for side, heel, toe in ((-1.0, heel_L, toe_L), (1.0, heel_R, toe_R)):
        hip = center + R_body @ np.array([side * 1.75 * s, -0.85 * s, -1.15 * s])
        knee = 0.55 * hip + 0.45 * toe + np.array([side * 0.35 * s, 1.15 * s, 1.35 * s])
        m.limb(hip, knee, 1.45 * s, 0.95 * s, J_COAT, step=0.38)
        m.limb(knee, heel, 0.85 * s, 0.56 * s, J_COAT, step=0.35)
        m.ell(heel, (0.62 * s, 0.62 * s, 0.68 * s), J_PAW_EAR)
        m.limb(heel, toe, 0.54 * s, 0.46 * s, J_PAW_EAR, step=0.34)
        m.ell(toe + np.array([0.0, 0.0, 0.55 * s]), (0.68 * s, 0.44 * s, 1.18 * s), J_WHITE)

    # OVERLONG S-CURVED BALANCING TAIL WITH BLACK SUBTERMINAL BAND + SNOW-WHITE BRUSH TUFT!
    t_root = center + R_body @ np.array([0.0, -1.25 * s, -2.65 * s])
    if tail_mode == 'groom':
        # Curving right around left flank so the black-and-white brush rests in its tiny forepaws!
        p0 = t_root
        p1 = center + np.array([-4.6 * s, -2.2 * s, -2.4 * s])
        p2 = center + np.array([-4.4 * s, -0.8 * s, 3.8 * s])
        p3 = center + np.array([-0.2 * s, 0.35 * s + 0.35 * math.sin(p) * s, 3.6 * s])
    elif tail_mode == 'run':
        wave = math.sin(p)
        p0 = t_root
        p1 = t_root + np.array([0.3 * wave * s, 0.8 * s, -5.2 * s])
        p2 = t_root + np.array([-0.4 * wave * s, 2.2 * s, -10.4 * s])
        p3 = t_root + np.array([0.5 * wave * s, (1.6 + 1.2 * wave) * s, -15.6 * s])
    elif tail_mode == 'hop':
        p0 = t_root
        p1 = t_root + np.array([0.0, -1.6 * s, -4.8 * s])
        p2 = t_root + np.array([0.0, 1.2 * s, -9.8 * s])
        p3 = t_root + np.array([0.0, 3.4 * s, -14.6 * s])
    elif tail_mode == 'bath':
        p0 = t_root
        p1 = t_root + np.array([2.2 * math.sin(p) * s, 0.8 * s, -4.6 * s])
        p2 = t_root + np.array([3.6 * math.sin(p - 0.5) * s, 2.4 * s, -9.2 * s])
        p3 = t_root + np.array([4.2 * math.sin(p - 1.0) * s, 4.2 * s, -13.2 * s])
    else:
        # Classic S-curve tripod prop: dips to touch sand behind heels, then sweeps gracefully up to white banner!
        sw = 0.75 * b * s
        p0 = t_root
        p1 = np.array([sw * 0.3, 0.85 * s, bz - 6.8 * s])
        p2 = np.array([sw * 0.7, 2.25 * s, bz - 11.8 * s])
        p3 = np.array([sw * 1.1, (5.4 + 0.45 * b) * s, bz - 15.8 * s])

    n_t = 16
    prev_t = p0
    for ti in range(1, n_t + 1):
        u = ti / n_t
        cur_t = bezier3(p0, p1, p2, p3, u)
        if ti <= 10:
            m.limb(prev_t, cur_t, 0.48 * s, 0.44 * s, J_PAW_EAR, step=0.32)
        elif ti <= 13:
            # Crisp jet-black subterminal feather ring!
            m.limb(prev_t, cur_t, 0.78 * s, 0.92 * s, J_BAND, step=0.30)
        else:
            # Flat snowy-white feather-banner tuft (Pinselquaste) at tip!
            r_w = (1.18 if ti == 15 else 0.92) * s
            m.limb(prev_t, cur_t, r_w, r_w * 0.82, J_WHITE, step=0.30)
        prev_t = cur_t
    return m


def jerboa_frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in JERBOA_BLOCKS if x[1] <= col < x[1] + x[2])
    jerboa_materials(v)
    return _to_frame_rgba(build_jerboa(v, kind, (col - start) / n), d)


def _jerboa_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, JERBOA_COLS * W, 4), np.uint8)
    for col in range(JERBOA_COLS):
        row[:, col * W:(col + 1) * W] = jerboa_frame(v, d, col)
    return v, d, row


# ==============================================================================
# 4. SONNENQUARZ-AGAME (assets/wildlife/agama.png — 52 cols x 32 rows)
# ==============================================================================
AGAMA_BUILDS = 4
AGAMA_COLS = 52
A_BODY, A_HEAD, A_TAIL, A_BELLY, A_DARK, A_EYE, A_GLINT = range(7)

AGAMA_BLOCKS = [
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


def agama_materials(v: int) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {A_GLINT: 4.8, A_EYE: 4.0, A_HEAD: 1.55, A_DARK: 1.50, A_TAIL: 1.45, A_BELLY: 1.25}
    art.ink_color = lambda mat: hexc('121426' if mat in (A_HEAD, A_DARK, A_EYE) else '261b26')
    b = v % AGAMA_BUILDS
    if b == 0:
        # 0 Azurkamm-Männchen: slate-ochre back, rusty-amber tail base, vivid cobalt-turquoise head & dewlap (non-emissive!)
        body = ['48362e', '785842', 'ac8258', 'daa972']
        head = ['143264', '1e5ca2', '2fa2d8', '74def6']
        tail = ['5c2c1c', '964c28', 'cf7838', 'f4aa56']
        belly = ['78685c', 'a89484', 'd6c2b0', 'f5e8da']
        dark = ['1c1624', '34283c', '54405a', '785e7c']
    elif b == 1:
        # 1 Terrakotta-Weibchen: warm sandstone-ochre with dark diamond bands
        body = ['563024', '8c5236', 'c07c4e', 'e8aa72']
        head = ['643828', '9c5c3c', 'ce8856', 'f2b880']
        tail = ['4a2820', '7a4430', 'ac6846', 'd89468']
        belly = ['846c5c', 'b49a86', 'dec6b2', 'f8ece0']
        dark = ['221520', '3c2634', '5e3e4e', '845c6c']
    elif b == 2:
        # 2 Quarz-Bleichschuppe: crystalline white-blue-grey speckled morph synced to QUARTZ_W slabs!
        body = ['6e8694', '9ab3be', 'c9dce3', 'eef6f8']
        head = ['5b698e', '8191b6', 'bfcde7', 'f2f7ff']
        tail = ['5a6e82', '869cb0', 'b8ccd8', 'e4f0f6']
        belly = ['8496a6', 'b2c2d0', 'dce6ee', 'ffffff']
        dark = ['36425e', '526282', '7688a8', '9eb0cc']
    else:
        # 3 Streifen-Jungtier (0.74x): nimble pale sand-striped juvenile
        body = ['64462e', '986c44', 'ca9862', 'f0c48a']
        head = ['6c4c32', 'a2744a', 'd4a26a', 'f6cc94']
        tail = ['583c28', '8a603c', 'bc8a58', 'e4b67e']
        belly = ['8e7c6c', 'bca896', 'e4d2c0', 'fbf2e6']
        dark = ['281c22', '463238', '6a4c52', '906c72']

    ramps = [
        body,                                               # 0 A_BODY
        head,                                               # 1 A_HEAD
        tail,                                               # 2 A_TAIL
        belly,                                              # 3 A_BELLY
        dark,                                               # 4 A_DARK
        ['8a4c14', 'c87820', 'f4aa38', 'ffe07c'],           # 5 A_EYE (bright golden-amber reptile iris)
        ['100d1a', '1d182e', '302846', '483e62'],           # 6 A_GLINT (slit pupil)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def _draw_agama_limb(m: art.Model, root: np.ndarray, knee: np.ndarray, foot: np.ndarray, side: float, s: float, mat_upper: int) -> None:
    """Sprawled muscular reptile leg with 3 splayed clawed desert toes."""
    m.limb(root, knee, 1.18 * s, 0.92 * s, mat_upper, step=0.36)
    m.limb(knee, foot, 0.88 * s, 0.66 * s, A_BODY, step=0.34)
    m.ell(foot, (0.76 * s, 0.44 * s, 0.85 * s), A_BODY)
    for ang in (-0.42, 0.0, 0.42):
        tip = foot + np.array([(math.sin(ang) * 1.25 + side * 0.25) * s, -0.05 * s, math.cos(ang) * 1.25 * s])
        m.limb(foot, tip, 0.34 * s, 0.22 * s, A_DARK, step=0.30)


def build_agama(v: int, kind: str, t: float) -> art.Model:
    m = art.Model()
    b_idx = v % AGAMA_BUILDS
    male = (b_idx == 0)
    juv = (b_idx == 3)
    s = 0.74 if juv else 1.0

    p = t * math.tau
    wave = math.sin(p)

    # Default proud sun-basking agama posture: rump low, chest propped up on splayed forelegs!
    rump_y, rump_z = 2.8 * s, -4.4 * s
    chest_y, chest_z = 5.2 * s, 3.2 * s
    head_y, head_z = 7.4 * s, 5.8 * s
    head_pitch = -0.10
    head_yaw = 0.0
    head_roll = 0.0
    dewlap = 0.25 if male else 0.08
    spine_sway = 0.0
    tail_lift = 0.0
    flat_widen = 1.0
    eyes_shut = False

    # Splayed reptile feet planted around GROUND_ROW = 52.0
    ffoot_L = np.array([-4.45 * s, 0.56 * s, 3.85 * s])
    ffoot_R = np.array([4.45 * s, 0.56 * s, 3.85 * s])
    hfoot_L = np.array([-4.85 * s, 0.56 * s, -3.65 * s])
    hfoot_R = np.array([4.85 * s, 0.56 * s, -3.65 * s])

    if kind == 'idle':
        chest_y += 0.10 * wave * s
        head_y += 0.12 * wave * s
        head_yaw = 0.08 * wave
    elif kind == 'forage':
        # Lightning predatory forward snap at desert insect!
        idx = int(t * 6) % 6
        lunge = [0.2, 0.95, 1.0, 0.65, 0.30, 0.0][idx]
        rump_z += 1.4 * lunge * s
        chest_z += 2.2 * lunge * s
        chest_y = (5.2 - 1.2 * lunge) * s
        head_z = chest_z + (2.8 + 1.4 * lunge) * s
        head_y = (7.4 - 2.6 * lunge) * s
        head_pitch = -0.10 + 0.48 * lunge
        ffoot_R = np.array([4.35 * s, (0.56 + (1.2 if idx == 1 else 0.0)) * s, (3.85 + 2.2 * lunge) * s])
    elif kind == 'walk':
        # Reptilian diagonal sprawl gait (Kreuzgang) + lateral S-wave spine & spiny tail!
        spine_sway = 0.85 * wave * s
        chest_y = 4.2 * s
        rump_y = 3.4 * s
        head_y = 6.0 * s
        head_yaw = -0.18 * wave
        for side_i, side in enumerate((-1.0, 1.0)):
            for front in (False, True):
                diag = 0.0 if ((side > 0) == front) else 0.5
                cyc = (t + diag) % 1.0
                if cyc < 0.58:
                    sw = (2.2 * s) * (1.0 - 2.0 * (cyc / 0.58))
                    lf = 0.0
                else:
                    c = (cyc - 0.58) / 0.42
                    sw = -(2.2 * s) * math.cos(c * math.pi)
                    lf = math.sin(c * math.pi) * 1.45 * s
                pt = np.array([side * (4.45 if front else 4.85) * s, (0.56 * s + lf), (3.85 if front else -3.65) * s + sw])
                if front and side < 0:
                    ffoot_L = pt
                elif front and side > 0:
                    ffoot_R = pt
                elif not front and side < 0:
                    hfoot_L = pt
                else:
                    hfoot_R = pt
    elif kind == 'alert':
        # Flattened rock-hugging camouflage freeze + side-eye lookout!
        idx_a = int(t * 4) % 4
        rump_y, chest_y, head_y = 2.1 * s, 2.8 * s, 4.2 * s
        flat_widen = 1.22
        head_yaw = [0.0, 0.24, 0.22, -0.16][idx_a]
        head_roll = -0.16 * head_yaw
    elif kind == 'run':
        # High-bellied rapid desert sprint with spiny tail raised aloft!
        spine_sway = 1.05 * wave * s
        rump_y, chest_y, head_y = 5.2 * s, 5.8 * s, 7.6 * s
        tail_lift = 3.8 * s
        for side in (-1.0, 1.0):
            for front in (False, True):
                diag = 0.0 if ((side > 0) == front) else 0.5
                ang = ((t + diag) % 1.0) * math.tau
                sw = 3.1 * s * math.sin(ang)
                lf = max(0.0, math.cos(ang)) * 2.1 * s
                pt = np.array([side * (4.15 if front else 4.55) * s, 0.56 * s + lf, (3.85 if front else -3.65) * s + sw])
                if front and side < 0:
                    ffoot_L = pt
                elif front and side > 0:
                    ffoot_R = pt
                elif not front and side < 0:
                    hfoot_L = pt
                else:
                    hfoot_R = pt
    elif kind == 'groom':
        # Dewlap fan stretch & head-wipe against sand/foreleg
        idx_g = int(t * 4) % 4
        rub = [0.3, 1.0, 0.9, 0.2][idx_g]
        dewlap = 0.85 * rub
        chest_y = (4.6 - 1.1 * rub) * s
        head_y = (6.6 - 1.8 * rub) * s
        head_yaw = 0.42 * rub
        head_roll = 0.28 * rub
    elif kind == 'sleep':
        # Pancake-flat basking sleep on warm sun-quartz / rock
        rump_y, chest_y, head_y = 1.85 * s, 2.15 * s + 0.06 * wave * s, 3.05 * s
        flat_widen = 1.26
        eyes_shut = True
    elif kind == 'bark':
        # Iconic Agama territorial push-up & rapid head-bobbing ('Liegestütz-Kopfnicken') + flared dewlap!
        idx_b = int(t * 6) % 6
        push = [0.18, 1.0, 0.28, 1.0, 0.45, 0.12][idx_b]
        dewlap = [0.55, 1.0, 0.95, 1.0, 0.88, 0.40][idx_b]
        chest_y = (3.0 + 4.4 * push) * s
        head_y = (4.8 + 5.4 * push) * s
        head_z = (5.8 - 0.35 * push) * s
        head_pitch = -0.10 - 0.30 * push
        ffoot_L = np.array([-3.65 * s, 0.56 * s, 3.65 * s])
        ffoot_R = np.array([3.65 * s, 0.56 * s, 3.65 * s])
    elif kind == 'special':
        # Thermoregulatory 'Heißer-Sand-Tanz': standing high, lifting alternating diagonal fore + hind feet!
        idx_s = int(t * 8) % 8
        rump_y, chest_y, head_y = 5.6 * s, 6.6 * s, 8.6 * s
        tail_lift = 3.0 * s
        # Frames 0..3 lift Front-Left + Hind-Right high; Frames 4..7 lift Front-Right + Hind-Left high!
        lift_a = [1.8, 4.2, 3.9, 1.5, 0.0, 0.0, 0.0, 0.0][idx_s] * s
        lift_b = [0.0, 0.0, 0.0, 0.0, 1.8, 4.2, 3.9, 1.5][idx_s] * s
        body_tilt = (lift_a - lift_b) * 0.065
        head_roll = body_tilt
        ffoot_L = np.array([-4.15 * s, 0.56 * s + lift_a, (3.85 + (1.05 if lift_a > 0 else 0.0)) * s])
        hfoot_R = np.array([4.45 * s, 0.56 * s + lift_a * 0.92, (-3.65 - (0.75 if lift_a > 0 else 0.0)) * s])
        ffoot_R = np.array([4.15 * s, 0.56 * s + lift_b, (3.85 + (1.05 if lift_b > 0 else 0.0)) * s])
        hfoot_L = np.array([-4.45 * s, 0.56 * s + lift_b * 0.92, (-3.65 - (0.75 if lift_b > 0 else 0.0)) * s])

    # ---- Flattened Sun-Basking Lizard Torso + Diamond Cross-Bands / Stripes ----
    for i in range(8):
        u = i / 7.0
        sz_p = rump_z + (chest_z - rump_z) * u
        sy_p = rump_y + (chest_y - rump_y) * u
        arch = math.sin(u * math.pi)
        sx_p = spine_sway * math.sin(u * math.pi)
        rx = (2.85 + 1.15 * arch) * flat_widen * s
        ry = (1.95 + 0.55 * arch) * (0.82 if flat_widen > 1.15 else 1.0) * s
        rz = (2.15 + 0.45 * arch) * s
        mat_seg = A_HEAD if (male and u > 0.78) else A_BODY
        m.ell((sx_p, sy_p, sz_p), (rx, ry, rz), mat_seg)
        # Pale belly edge
        m.ell((sx_p, sy_p - ry * 0.58, sz_p), (rx * 0.84, ry * 0.52, rz * 0.88), A_BELLY)
        # Dorsal diamond cross-bands (or juvenile stripes) & nuchal spiny crest!
        if not juv and i in (1, 3, 5):
            m.ell((sx_p, sy_p + ry * 0.68, sz_p), (rx * 0.68, ry * 0.42, 1.15 * s), A_DARK)
        if i >= 2:
            m.ell((sx_p, sy_p + ry * 0.95, sz_p), (0.42 * s, 0.68 * s, 0.62 * s), A_HEAD if (male and i >= 5) else A_DARK)

    if juv:
        for side in (-1.0, 1.0):
            m.limb((side * 1.85 * s, rump_y + 1.2 * s, rump_z + 0.8 * s), (side * 1.85 * s, chest_y + 1.2 * s, chest_z - 0.8 * s), 0.52 * s, 0.52 * s, A_BELLY, step=0.40)

    # ---- Segmented Ringed Spiny Tail (Dornenschwanz) with Lateral Scale Whorls! ----
    t_p0 = np.array([0.0, rump_y - 0.15 * s, rump_z - 0.8 * s])
    t_sw = -spine_sway * 1.6 if kind in ('walk', 'run') else 0.55 * wave * s
    t_p1 = np.array([t_sw * 0.5, max(1.1 * s, rump_y - 0.8 * s + tail_lift * 0.35), rump_z - 4.5 * s])
    t_p2 = np.array([-t_sw * 0.8, max(0.95 * s, 1.2 * s + tail_lift * 0.75), rump_z - 8.6 * s])
    t_p3 = np.array([t_sw * 1.1, max(0.85 * s, 1.1 * s + tail_lift), rump_z - 12.6 * s])

    n_rings = 9
    for ri in range(n_rings):
        u = ri / (n_rings - 1)
        pt = bezier3(t_p0, t_p1, t_p2, t_p3, u)
        rw = (2.35 * (1.0 - 0.72 * u)) * s
        rh = (1.55 * (1.0 - 0.68 * u)) * s
        mat_r = A_TAIL if ri < 4 else (A_DARK if ri % 2 == 1 else A_BODY)
        m.ell(pt, (rw, rh, 1.15 * s), mat_r)
        # Projecting lateral & dorsal spiny scale whorls!
        if ri < 7:
            for side in (-1.0, 1.0):
                sp = pt + np.array([side * (rw + 0.42 * s), 0.12 * s, -0.18 * s])
                m.ell(sp, (0.58 * s, 0.34 * s, 0.42 * s), A_DARK if ri % 2 == 1 else A_TAIL)

    # ---- Broad Triangular Agama Head + Flared Gular Dewlap Fan (Kehlsack) ----
    h_pos = np.array([spine_sway * 0.4, head_y, head_z])
    R_h = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    m.limb((spine_sway * 0.3, chest_y + 0.35 * s, chest_z + 0.8 * s), h_pos + R_h @ np.array([0.0, -0.45 * s, -1.15 * s]), 2.45 * s, 2.05 * s, A_HEAD, step=0.38)

    # Wide flared jowls/temporal spines + wedged triangular snout
    m.ell(h_pos, (2.65 * s, 1.95 * s, 2.45 * s), A_HEAD, R=R_h)
    for side in (-1.0, 1.0):
        # Characteristic spiny ear-cluster jowls at back corners of triangular agama skull!
        m.ell(h_pos + R_h @ np.array([side * 2.35 * s, -0.15 * s, -0.85 * s]), (0.95 * s, 0.85 * s, 1.05 * s), A_HEAD, R=R_h)
    m.ell(h_pos + R_h @ np.array([0.0, -0.25 * s, 1.95 * s]), (1.65 * s, 1.35 * s, 1.85 * s), A_HEAD, R=R_h)
    m.ell(h_pos + R_h @ np.array([0.0, -0.42 * s, 3.15 * s]), (1.05 * s, 0.88 * s, 1.05 * s), A_HEAD, R=R_h)

    # Expandable gular dewlap fan under throat (prominently flared in 'bark' push-up display!)
    if dewlap > 0.05:
        fan_drop = (1.35 + 3.05 * dewlap) * s
        m.ell(h_pos + R_h @ np.array([0.0, -fan_drop * 0.62, 0.85 * s]), (0.78 * s, fan_drop * 0.76, 2.35 * s), A_HEAD if male else A_TAIL, R=R_h)

    # Fierce superciliary brow ridges + gleaming golden reptile eyes
    for side in (-1.0, 1.0):
        m.limb(h_pos + R_h @ np.array([side * 1.35 * s, 0.85 * s, -0.15 * s]), h_pos + R_h @ np.array([side * 1.15 * s, 0.65 * s, 1.75 * s]), 0.48 * s, 0.42 * s, A_HEAD, step=0.34)
        if eyes_shut:
            m.ell(h_pos + R_h @ np.array([side * 1.65 * s, 0.35 * s, 0.85 * s]), (0.42 * s, 0.16 * s, 0.55 * s), A_GLINT, R=R_h)
        else:
            m.ell(h_pos + R_h @ np.array([side * 1.68 * s, 0.35 * s, 0.85 * s]), (0.50 * s, 0.56 * s, 0.62 * s), A_EYE, R=R_h)
            m.ell(h_pos + R_h @ np.array([side * 1.85 * s, 0.35 * s, 0.88 * s]), (0.24 * s, 0.42 * s, 0.24 * s), A_GLINT, R=R_h)

    # 4 sprawled muscular clawed limbs
    sh_L = np.array([-2.35 * s, chest_y - 0.35 * s, chest_z + 0.35 * s])
    sh_R = np.array([2.35 * s, chest_y - 0.35 * s, chest_z + 0.35 * s])
    hp_L = np.array([-2.35 * s, rump_y - 0.15 * s, rump_z + 0.45 * s])
    hp_R = np.array([2.35 * s, rump_y - 0.15 * s, rump_z + 0.45 * s])

    el_L = 0.5 * (sh_L + ffoot_L) + np.array([-1.35 * s, 1.15 * s, -0.45 * s])
    el_R = 0.5 * (sh_R + ffoot_R) + np.array([1.35 * s, 1.15 * s, -0.45 * s])
    kn_L = 0.5 * (hp_L + hfoot_L) + np.array([-1.55 * s, 1.35 * s, 0.85 * s])
    kn_R = 0.5 * (hp_R + hfoot_R) + np.array([1.55 * s, 1.35 * s, 0.85 * s])

    _draw_agama_limb(m, sh_L, el_L, ffoot_L, -1.0, s, A_HEAD if male else A_BODY)
    _draw_agama_limb(m, sh_R, el_R, ffoot_R, 1.0, s, A_HEAD if male else A_BODY)
    _draw_agama_limb(m, hp_L, kn_L, hfoot_L, -1.0, s, A_BODY)
    _draw_agama_limb(m, hp_R, kn_R, hfoot_R, 1.0, s, A_BODY)
    return m


def agama_frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in AGAMA_BLOCKS if x[1] <= col < x[1] + x[2])
    agama_materials(v)
    return _to_frame_rgba(build_agama(v, kind, (col - start) / n), d)


def _agama_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, AGAMA_COLS * W, 4), np.uint8)
    for col in range(AGAMA_COLS):
        row[:, col * W:(col + 1) * W] = agama_frame(v, d, col)
    return v, d, row


# ==============================================================================
# 5. SONNENFALKE (assets/wildlife/desert_falcon.png — 62 cols x 24 rows, GR=48.0)
# ==============================================================================
FALCON_BUILDS = 3
FALCON_COLS = 62
K_MANTLE, K_CAP, K_BREAST, K_DARK, K_YELLOW, K_EYE, K_GLINT = range(7)

FALCON_BLOCKS = [
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


def falcon_materials(v: int) -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 48.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        K_GLINT: 4.8,
        K_EYE: 4.1,
        K_YELLOW: 2.35,
        K_DARK: 1.65,
        K_CAP: 1.45,
        K_BREAST: 1.30,
    }
    art.ink_color = lambda mat: hexc('11101c' if mat in (K_DARK, K_EYE) else '221926')
    b = v % FALCON_BUILDS
    if b == 0:
        # 0 Schiefer-Lanner: blue-slate mantle/wings, warm rufous-chestnut crown/nape cap, speckled cream breast
        mantle = ['263248', '3e506e', '62789a', '8ea6c8']
        cap = ['5c281e', '94422c', 'c86c40', 'ee9c62']
        breast = ['928680', 'c2b6ae', 'ebe0d6', 'fffaf2']
        dark = ['121320', '222438', '383c56', '545a78']
    elif b == 1:
        # 1 Dünensperber: golden sand-cinnamon mantle with contrasting dark charcoal wingtips
        mantle = ['583622', '8c5a36', 'c08652', 'e8b47c']
        cap = ['4a2a1c', '7a482c', 'ac6e44', 'd89a68']
        breast = ['8e7c6e', 'bea896', 'e8d4c0', 'fdf2e4']
        dark = ['15121e', '282234', '423850', '625470']
    else:
        # 2 Heller Quarzfalke: pale silver-ivory plumage with sharp dark malar moustache & black primary tips
        mantle = ['626c82', '8e98ae', 'bec8da', 'eef2fa']
        cap = ['727a8e', '9ea6ba', 'ccd2e2', 'f5f8ff']
        breast = ['9298a8', 'c2c8d6', 'eceff8', 'ffffff']
        dark = ['161828', '2a2e46', '464c6c', '687094']

    ramps = [
        mantle,                                             # 0 K_MANTLE
        cap,                                                # 1 K_CAP
        breast,                                             # 2 K_BREAST
        dark,                                               # 3 K_DARK (malar stripe, hooked bill tip, primary tips!)
        ['8e5814', 'c88a1e', 'f4be34', 'ffe878'],           # 4 K_YELLOW (yellow cere, eye-ring & talons!)
        ['0b0914', '161326', '28223c', '3c3456'],           # 5 K_EYE
        ['a6b0be', 'cdd6e2', 'edf2f8', 'ffffff'],           # 6 K_GLINT
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def _draw_falcon_sickle_wing(
    m: art.Model,
    side: float,
    shoulder: np.ndarray,
    span: float,
    lift: float,
    sweep_back: float,
    wrist_fold: float,
    camber: float,
) -> None:
    """Pointed aerodynamic swept-back falcon sickle wing (spitze Sichelflügel), strictly bounded inside 64x64!"""
    # Carpal wrist sweeps forward-outward; pointed primary blade sweeps sharply backward like a scythe!
    carpal = shoulder + np.array([
        side * span * (0.48 - 0.12 * wrist_fold),
        lift * 0.56 + camber,
        (2.45 - 0.85 * wrist_fold) - sweep_back * 0.15,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.20 * wrist_fold),
        lift - 1.15 * wrist_fold,
        (-5.25 - 1.45 * wrist_fold) - sweep_back,
    ])

    # Crisp leading-edge spar
    m.limb(shoulder, carpal, 1.55, 1.25, K_MANTLE, step=0.52)
    m.limb(carpal, tip, 1.18, 0.52, K_DARK, step=0.48)

    # Narrow tapered inner secondaries
    n_sec = 6
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (5.8 - 0.85 * u) * (1.0 - 0.16 * wrist_fold)
        te = le + np.array([side * 0.35 * u, -0.55 - 0.25 * camber, -chord])
        mid = le * 0.55 + te * 0.45
        m.limb(le, mid, 1.18, 0.96, K_MANTLE, step=0.52)
        m.limb(mid, te, 0.92, 0.58, K_BREAST if i % 2 == 0 else K_MANTLE, step=0.52)

    # Swept-back pointed sickle primaries (tapering to a razor-sharp falcon wingtip!)
    n_pri = 6
    for i in range(n_pri):
        u = (i + 0.15) / n_pri
        le = carpal * (1.0 - u) + tip * u
        plen = (6.4 * (1.0 - 0.68 * u)) * (1.0 - 0.14 * wrist_fold)
        te = le + np.array([side * plen * 0.22 * (1.0 - u), -0.25 * wrist_fold, -plen])
        m.limb(le, te, 0.96 * (1.0 - 0.35 * u), 0.44, K_DARK if u > 0.38 else K_MANTLE, step=0.48)


def build_falcon(v: int, kind: str, t: float) -> art.Model:
    falcon_materials(v)
    m = art.Model()
    p = t * math.tau
    bob = math.sin(p)
    flying = kind in ('fly', 'takeoff', 'land', 'glide')

    # Sleek, streamlined upright falcon perch posture (GROUND_ROW = 48.0)
    rump_y, rump_z = 7.4, -2.6
    chest_y, chest_z = 12.2, 1.6
    head_y, head_z = 16.4, 2.2
    head_pitch = 0.06
    head_yaw = 0.0
    head_roll = 0.0
    body_sway_x = 0.0
    fluff = 1.0
    beak_open = 0.0
    eye_slit = 0.0
    tail_pitch = -0.42
    tail_fan = 0.85
    wing_preen_side = 0.0
    hop_wing = 0.0

    foot_L = np.array([-1.65, 0.72, 0.55])
    foot_R = np.array([1.65, 0.72, 0.55])
    tuck_one_foot = False

    if kind == 'idle':
        idx = int(round(t * 4)) % 4
        chest_y += 0.14 * bob
        head_y += 0.16 * bob
        head_yaw = 0.16 * math.sin(p)
        if idx == 3:
            eye_slit = 0.85
    elif kind == 'peck':
        # Characteristic falcon distance-judging head-bob & keen downward peer!
        idx = int(round(t * 6)) % 6
        dip = [0.25, 0.92, 1.0, 0.45, 0.85, 0.20][idx]
        chest_y = 12.2 - 1.35 * dip
        chest_z = 1.6 + 0.55 * dip
        head_y = 16.4 - 2.15 * dip
        head_z = 2.2 + 2.25 * dip
        head_pitch = 0.06 + 0.38 * dip
        head_yaw = [0.0, 0.18, 0.16, -0.22, -0.20, 0.0][idx]
    elif kind == 'walk':
        for s_idx, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_idx == 0 else 0.5)) % 1.0
            if c < 0.56:
                fz = 1.85 - 3.20 * (c / 0.56)
                fy = 0.72
            else:
                u = (c - 0.56) / 0.44
                fz = -1.35 + 3.20 * u
                fy = 0.72 + math.sin(u * math.pi) * 2.15
            if s_idx == 0:
                foot_L = np.array([side * 1.75, fy, fz])
            else:
                foot_R = np.array([side * 1.75, fy, fz])
        body_sway_x = 0.55 * math.sin(p)
        chest_y += 0.28 * abs(math.sin(p))
        head_y += 0.28 * abs(math.sin(p))
    elif kind == 'preen':
        # Drawing long sickle primary feathers through hooked bill!
        idx = int(round(t * 6)) % 6
        turn = [0.42, 0.96, 1.0, 0.92, 0.35, 0.0][idx]
        head_yaw = 1.35 * turn
        head_pitch = 0.42 * turn
        head_roll = -0.18 * turn
        head_y = 16.4 - 1.55 * turn
        head_z = 2.2 - 1.45 * turn
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
    elif kind == 'watch':
        idx = int(round(t * 4)) % 4
        chest_y, head_y = 12.8, 17.2
        fluff = 0.90
        head_yaw = [0.0, 0.28, 0.0, -0.28][idx]
    elif kind == 'call':
        # Piercing 'kek-kek-kek' falcon call with forward bow & wide-open hooked beak!
        idx = int(round(t * 4)) % 4
        cry = [0.35, 1.0, 0.88, 0.40][idx]
        chest_y = 12.2 - 0.95 * cry
        chest_z = 1.6 + 1.15 * cry
        head_y = 16.4 - 1.25 * cry
        head_z = 2.2 + 1.85 * cry
        head_pitch = -0.12 * cry
        beak_open = 0.78 * cry
        tail_fan = 1.15
    elif kind == 'hop':
        idx = int(round(t * 4)) % 4
        if idx == 0:
            rump_y, chest_y, head_y = 6.4, 10.6, 14.8
            hop_wing = 0.38
        elif idx in (1, 2):
            lf = 3.2 if idx == 1 else 2.5
            rump_y, chest_y, head_y = 7.6 + lf, 12.0 + lf, 16.2 + lf
            foot_L = np.array([-1.75, 2.85, 1.85])
            foot_R = np.array([1.75, 2.85, 1.85])
            hop_wing = 0.88 if idx == 1 else 0.65
            tail_fan = 1.25
        else:
            rump_y, chest_y, head_y = 7.0, 11.4, 15.6
            hop_wing = 0.22
    elif kind == 'roost':
        # Fluffed calm desert night sleep with eyes shut & one yellow talon tucked into belly feathers!
        rump_y, chest_y, head_y = 7.2 + 0.08 * bob, 11.2 + 0.10 * bob, 14.6 + 0.10 * bob
        head_z = 1.6
        fluff = 1.18
        eye_slit = 1.0
        tuck_one_foot = True
    elif flying:
        if kind == 'fly':
            # Powerful pointed sickle-wing flapping / wind-hovering (Rüttelflug)!
            idx = int(round(t * 8)) % 8
            by = 16.8 + [-0.4, -0.1, 0.5, 0.8, 0.4, 0.0, -0.3, -0.5][idx]
            rump_y, rump_z = by - 0.55, -3.4
            chest_y, chest_z = by + 0.35, 2.2
            head_y, head_z = by + 1.15, 4.8
            head_pitch = 0.10
            tail_pitch = -0.05
            tail_fan = 1.15
            foot_L = np.array([-1.25, rump_y - 1.15, -1.85])
            foot_R = np.array([1.25, rump_y - 1.15, -1.85])
        elif kind == 'glide':
            # Serene desert thermal soaring with wide, taut, swept-back sickle wings!
            by = 17.0 + 0.16 * bob
            rump_y, rump_z = by - 0.50, -3.5
            chest_y, chest_z = by + 0.30, 2.3
            head_y, head_z = by + 1.05, 4.9
            head_pitch = 0.08
            head_yaw = 0.10 * bob
            tail_pitch = -0.04
            tail_fan = 1.32
            foot_L = np.array([-1.20, rump_y - 1.10, -1.95])
            foot_R = np.array([1.20, rump_y - 1.10, -1.95])
        elif kind == 'takeoff':
            idx = int(round(t * 6)) % 6
            if idx == 0:
                rump_y, chest_y, head_y = 6.2, 9.4, 13.4
                chest_z, head_z = 2.4, 4.0
                tail_fan = 1.28
            else:
                u = smooth(idx / 5.0)
                by = 10.6 + 6.4 * u
                rump_y, rump_z = by - 1.0 + 0.45 * u, -2.9 - 0.5 * u
                chest_y, chest_z = by + 0.6 - 0.25 * u, 2.25
                head_y, head_z = by + 2.8 - 1.65 * u, 4.55
                tail_fan = 1.30
                fy = 1.4 + 10.2 * u
                fz = 0.6 - 2.2 * u
                foot_L = np.array([-1.45, fy, fz])
                foot_R = np.array([1.45, fy, fz])
        elif kind == 'land':
            # Upright airbrake flare with fanned barred tail & bright yellow talons thrust forward!
            idx = int(round(t * 6)) % 6
            flare = [0.88, 1.0, 0.94, 0.66, 0.32, 0.0][idx]
            climb = [5.4, 4.2, 2.8, 1.5, 0.5, 0.0][idx]
            rump_y, rump_z = 7.2 + climb - 0.4 * flare, -2.6 - 0.5 * flare
            chest_y, chest_z = 12.2 + climb + 0.7 * flare, 1.6 - 0.3 * flare
            head_y, head_z = 16.4 + climb + 0.3 * flare, 2.2 + 0.3 * flare
            tail_pitch = -0.42 - 0.35 * flare
            tail_fan = 0.85 + 0.75 * flare
            rz_f = 0.55 + 2.65 * flare
            ry_f = 0.72 + climb * 0.68
            foot_L = np.array([-1.75, ry_f, rz_f])
            foot_R = np.array([1.75, ry_f, rz_f])

    # ---- Streamlined Tear-Drop Falcon Torso + Speckled Breast ----
    for u in (0.0, 0.28, 0.56, 0.82, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz_p = rump_z + (chest_z - rump_z) * u
        arch = math.sin(u * math.pi)
        rx = (2.55 + 0.78 * arch) * fluff
        ry = (2.65 + 0.75 * arch)
        rz = (2.65 + 0.35 * arch) * fluff
        m.ell((body_sway_x, sy, sz_p), (rx, ry, rz), K_BREAST if u > 0.35 else K_MANTLE)

    # Slate/cinnamon dorsal mantle saddle
    mid_y = 0.42 * rump_y + 0.58 * chest_y
    mid_z = 0.42 * rump_z + 0.58 * chest_z
    m.ell((body_sway_x, mid_y + 0.95, mid_z - 0.55), (2.55 * fluff, 2.25, 2.85 * fluff), K_MANTLE)

    # Fine dark falcon breast flecks
    if not flying or kind == 'land':
        for r_i in range(3):
            for c_i in (-1, 0, 1):
                if r_i == 0 and c_i == 0:
                    continue
                m.ell((
                    body_sway_x + c_i * 1.05 * fluff,
                    chest_y - (0.45 + r_i * 1.35),
                    chest_z + (2.15 - r_i * 0.35) * fluff - abs(c_i) * 0.25,
                ), (0.30, 0.52, 0.34), K_DARK)

    # Long narrow barred falcon tail (extends sleekly past wingtips when perched & forms crisp crossbow tail in flight!)
    t_base = np.array([body_sway_x, rump_y - 0.25, rump_z - 1.15])
    R_tail = art.rot_x(tail_pitch)
    n_tf = 5
    t_len = 8.4 if flying else 7.2
    for ti in range(n_tf):
        ang_f = ((ti / (n_tf - 1)) - 0.5) * 0.48 * tail_fan
        R_f = R_tail @ art.rot_y(ang_f)
        t_mid = t_base + R_f @ np.array([0.0, 0.0, -0.5 * t_len])
        t_tip = t_base + R_f @ np.array([0.0, 0.0, -t_len])
        m.limb(t_base, t_mid, 0.88, 0.76, K_MANTLE, step=0.45)
        m.limb(t_mid, t_tip, 0.74, 0.52, K_DARK if ti % 2 == 0 else K_BREAST, step=0.45)

    # ---- Wings: Folded Scissor-Crossed Primaries (Perched) vs Pointed Sickle Wings (Flight)! ----
    if flying:
        for side in (-1.0, 1.0):
            sh = np.array([body_sway_x + side * 2.15, chest_y + 0.35, chest_z - 0.25])
            if kind == 'glide':
                # Taut wide thermal-soaring sickle wings (kept strictly <= 21.5 lateral reach -> 10px margin inside 64x64!)
                _draw_falcon_sickle_wing(m, side, sh, span=18.2, lift=1.2, sweep_back=2.2, wrist_fold=0.0, camber=0.6)
            elif kind == 'fly':
                idx = int(round(t * 8)) % 8
                flap_lift = [7.6, 4.2, -1.8, -6.2, -4.4, 0.8, 5.2, 7.8][idx]
                span_f = [14.8, 17.4, 18.0, 15.2, 14.6, 15.8, 16.8, 14.5][idx]
                wf = [0.12, 0.0, 0.0, 0.16, 0.32, 0.25, 0.14, 0.12][idx]
                _draw_falcon_sickle_wing(m, side, sh, span=span_f, lift=flap_lift, sweep_back=1.8, wrist_fold=wf, camber=0.5)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                if idx == 0:
                    _draw_falcon_sickle_wing(m, side, sh, span=10.5, lift=3.5, sweep_back=1.2, wrist_fold=0.45, camber=0.4)
                else:
                    flap = [6.8, -4.8, 6.4, -3.6, 4.8][idx - 1]
                    _draw_falcon_sickle_wing(m, side, sh, span=16.8, lift=flap, sweep_back=1.8, wrist_fold=0.08, camber=0.5)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                flare = [0.88, 1.0, 0.94, 0.66, 0.32, 0.0][idx]
                if flare < 0.15:
                    m.ell((body_sway_x + side * 2.55, mid_y, mid_z - 0.35), (1.15, 3.25, 2.45), K_MANTLE)
                else:
                    _draw_falcon_sickle_wing(m, side, sh, span=8.5 + 8.5 * flare, lift=4.5 * flare, sweep_back=-0.8 * flare, wrist_fold=0.35 * (1.0 - flare), camber=0.8 * flare)
    else:
        for side in (-1.0, 1.0):
            if hop_wing > 0.15:
                sh = np.array([body_sway_x + side * 2.15, chest_y + 0.25, chest_z - 0.25])
                _draw_falcon_sickle_wing(m, side, sh, span=7.5 + 6.5 * hop_wing, lift=3.8 * hop_wing, sweep_back=1.2, wrist_fold=0.35, camber=0.4)
            else:
                out_p = 1.35 if (wing_preen_side * side > 0) else 0.0
                w_sh = np.array([body_sway_x + side * (2.45 * fluff + out_p), chest_y - 0.45, chest_z - 0.15])
                w_mid = np.array([body_sway_x + side * (2.35 * fluff + out_p * 1.2), rump_y + 1.45, rump_z - 1.25])
                w_tip = np.array([body_sway_x + side * 0.55, rump_y - 2.65, rump_z - 5.25])
                m.limb(w_sh, w_mid, 1.45, 1.18, K_MANTLE, step=0.45)
                m.limb(w_mid, w_tip, 1.08, 0.46, K_DARK, step=0.42)

    # ---- Feathered Trousers & Bright Yellow Raptor Talons (gelbe Fänge)! ----
    for s_idx, (side, f_pt) in enumerate(((-1.0, foot_L), (1.0, foot_R))):
        if tuck_one_foot and s_idx == 1:
            continue
        hip = np.array([body_sway_x + side * 1.45, rump_y + 0.25, rump_z + 1.15])
        hock = 0.52 * hip + 0.48 * f_pt + np.array([0.0, 0.85, -0.35])
        m.limb(hip, hock, 1.18, 0.82, K_BREAST, step=0.38)
        m.limb(hock, f_pt, 0.58, 0.48, K_YELLOW, step=0.34)
        for ang in (-0.38, 0.0, 0.38):
            toe = f_pt + np.array([math.sin(ang) * 1.15, -0.05, math.cos(ang) * 1.25])
            m.limb(f_pt, toe, 0.36, 0.24, K_YELLOW, step=0.30)

    # ---- Noble Falcon Head: Rufous Cap, White Cheek, Dark Malar Moustache & Yellow Cere! ----
    h_pos = np.array([body_sway_x, head_y, head_z])
    R_h = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    m.limb((body_sway_x, chest_y + 0.85, chest_z + 0.35), h_pos + R_h @ np.array([0.0, -1.05, -0.35]), 2.15 * fluff, 1.85, K_BREAST, step=0.40)

    # Rounded skull + warm rufous Lanner crown/nape cap (K_CAP) + snowy white cheeks/throat!
    m.ell(h_pos, (2.15, 2.15, 2.25), K_CAP, R=R_h)
    m.ell(h_pos + R_h @ np.array([0.0, -0.55, 0.75]), (1.88, 1.45, 1.75), K_BREAST, R=R_h)

    # Signature dark falcon malar moustache stripe ('Falken-Bartstreif') dropping vertically below each eye!
    for side in (-1.0, 1.0):
        m.limb(
            h_pos + R_h @ np.array([side * 1.55, 0.05, 0.95]),
            h_pos + R_h @ np.array([side * 1.38, -1.35, 0.85]),
            0.48, 0.40, K_DARK, step=0.32,
        )
        # Yellow orbital ring + large keen dark falcon eye + crisp glint
        if eye_slit > 0.6:
            m.ell(h_pos + R_h @ np.array([side * 1.58, 0.32, 0.92]), (0.38, 0.16, 0.48), K_DARK, R=R_h)
        else:
            m.ell(h_pos + R_h @ np.array([side * 1.55, 0.32, 0.90]), (0.52, 0.62, 0.64), K_YELLOW, R=R_h)
            m.ell(h_pos + R_h @ np.array([side * 1.66, 0.32, 0.94]), (0.44, 0.50, 0.52), K_EYE, R=R_h)
            m.ell(h_pos + R_h @ np.array([side * 1.74, 0.48, 1.12]), (0.20, 0.20, 0.20), K_GLINT, R=R_h)

    # Bright golden-yellow cere (Wachshaut) + sharp hooked dark-slate raptor bill!
    b_root = h_pos + R_h @ np.array([0.0, -0.08, 2.05])
    m.ell(b_root, (0.78, 0.68, 0.68), K_YELLOW, R=R_h)
    up_rot = R_h @ art.rot_x(-0.25 * beak_open)
    b_mid = b_root + up_rot @ np.array([0.0, -0.15, 0.95])
    b_hook = b_root + up_rot @ np.array([0.0, -0.82, 1.48])
    m.limb(b_root, b_mid, 0.62, 0.46, K_DARK, step=0.32)
    m.limb(b_mid, b_hook, 0.44, 0.22, K_DARK, step=0.30)
    if beak_open > 0.12:
        lo_tip = h_pos + R_h @ np.array([0.0, -0.78 - 0.45 * beak_open, 2.95])
        m.limb(h_pos + R_h @ np.array([0.0, -0.58, 1.95]), lo_tip, 0.44, 0.26, K_DARK, step=0.32)

    return m


def falcon_frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in FALCON_BLOCKS if x[1] <= col < x[1] + x[2])
    return _to_frame_rgba(build_falcon(v, kind, (col - start) / n), d)


def _falcon_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, FALCON_COLS * W, 4), np.uint8)
    for col in range(FALCON_COLS):
        row[:, col * W:(col + 1) * W] = falcon_frame(v, d, col)
    return v, d, row


# ==============================================================================
# 6. WÜSTEN-SANDBAU (assets/wildlife/desert_burrow.png — 40x24 RGBA)
# ==============================================================================
def build_desert_burrow() -> np.ndarray:
    """40x24 RGBA desert wildlife shelter matching badger_den.py footprint (offset=Vector2(0,-8)), ZERO grass!"""
    a = np.zeros((24, 40, 4), np.uint8)

    # Harmonized red-ochre sandstone slabs, golden dune sand apron, cool indigo cave hollow & sun-quartz chips
    INK = hexc('281924')
    SAND_FAN = [hexc(c) for c in ('8c5c3a', 'b88450', 'dca96c', 'f2cc92')]
    ROCK = [hexc(c) for c in ('462726', '724234', 'a46844', 'd29a62', 'f2cc90')]
    HOLE = [hexc(c) for c in ('36232e', '211828', '13101e')]
    QUARTZ = [hexc(c) for c in ('5b698e', 'a2b3d4', 'ffffff')]

    def poly(pts: list[tuple[float, float]], col: tuple) -> None:
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(max(1, int(min(ys))), min(23, int(max(ys)) + 1)):
            for x in range(max(1, int(min(xs))), min(39, int(max(xs)) + 1)):
                inside = False
                px_c, py_c = x + 0.5, y + 0.5
                n = len(pts)
                for i in range(n):
                    x1, y1 = pts[i]
                    x2, y2 = pts[(i + 1) % n]
                    if (y1 > py_c) != (y2 > py_c):
                        xin = (x2 - x1) * (py_c - y1) / (y2 - y1) + x1
                        if px_c < xin:
                            inside = not inside
                if inside:
                    a[y, x] = col

    def oval(cx: float, cy: float, rx: float, ry: float, col: tuple) -> None:
        for y in range(max(1, int(cy - ry) - 1), min(23, int(cy + ry) + 2)):
            for x in range(max(1, int(cx - rx) - 1), min(39, int(cx + rx) + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    a[y, x] = col

    # 1. Excavated golden-sand apron fan in front of burrow mouth (y ~ 15..22, x ~ 5..35)
    oval(20.0, 18.4, 14.8, 4.2, SAND_FAN[0])
    oval(19.6, 18.2, 13.0, 3.6, SAND_FAN[1])
    oval(19.0, 18.3, 10.2, 2.8, SAND_FAN[2])
    for rx_i, ry_i in ((13, 19), (14, 20), (15, 20), (16, 20), (22, 20), (23, 20), (24, 19), (18, 21), (19, 21)):
        a[ry_i, rx_i] = SAND_FAN[3]

    # 2. Faceted wind-carved desert sandstone slabs forming a natural stepped rock arch (top-left sunlight!)
    # Base shadow mass
    poly([(4, 16), (6, 11), (12, 7), (21, 6), (29, 7), (35, 11), (36, 16), (31, 18), (9, 18)], ROCK[0])
    # Left sunlit sandstone buttress slab
    poly([(5, 16), (7, 11), (13, 8), (15, 11), (11, 16)], ROCK[2])
    poly([(6, 13), (8, 10), (13, 8), (13, 10), (8, 14)], ROCK[3])
    # Upper keystone cap slab (brightest top-left sunlit sandstone bevel!)
    poly([(11, 9), (15, 6), (24, 6), (28, 9), (25, 11), (13, 11)], ROCK[2])
    poly([(12, 8), (15, 6), (22, 6), (24, 8), (14, 9)], ROCK[3])
    for hx in range(14, 21):
        a[6, hx] = ROCK[4]
        if hx < 18:
            a[7, hx - 1] = ROCK[4]
    # Right shaded sandstone buttress slab
    poly([(25, 10), (29, 8), (34, 11), (35, 16), (29, 17), (26, 13)], ROCK[1])
    poly([(26, 10), (29, 8), (32, 10), (29, 12)], ROCK[2])

    # Horizontal wind-eroded strata crevice lines across slabs
    for sx, sy in ((8, 12), (9, 12), (10, 12), (15, 9), (16, 9), (17, 9), (22, 9), (23, 9), (29, 12), (30, 12), (31, 12)):
        a[sy, sx] = ROCK[0]

    # 3. Cool shaded subterranean burrow entrance hollow (exact center (20, 15..16) matching badger_den!)
    poly([(10, 16), (12, 12), (16, 10.5), (24, 10.5), (28, 12), (30, 16), (26, 18), (14, 18)], HOLE[0])
    poly([(12, 16), (14, 12.5), (17, 11.5), (23, 11.5), (26, 12.5), (28, 16), (24, 17.5), (16, 17.5)], HOLE[1])
    poly([(14, 16), (16, 13.5), (24, 13.5), (26, 16), (23, 17), (17, 17)], HOLE[2])

    # Crisp overhanging sandstone lintel lip above cave mouth
    for lx in range(12, 29):
        ly = 10 + (1 if abs(lx - 20) > 4 else 0) + (1 if abs(lx - 20) > 6 else 0)
        a[ly, lx] = ROCK[3 if lx < 19 else (2 if lx < 24 else 1)]
        a[ly + 1, lx] = ROCK[1 if lx < 20 else 0]

    # 4. Selective 1px dark plum-earth upper silhouette contour on sandstone rock (seamless sand apron at bottom!)
    src_alpha = a[:, :, 3].copy()
    for y in range(1, 17):
        for x in range(1, 39):
            if src_alpha[y, x] > 0:
                continue
            if any(src_alpha[y + dy, x + dx] > 0 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                a[y, x] = INK

    # 5. Faceted sandstone pebbles & 2 gleaming white sun-quartz chips flanking the entrance (ZERO grass!)
    for px_i, py_i, hi, sh in ((6, 17, ROCK[3], ROCK[1]), (10, 20, ROCK[3], ROCK[1]), (30, 19, ROCK[2], ROCK[0]), (34, 17, ROCK[2], ROCK[0])):
        a[py_i, px_i] = hi
        a[py_i, px_i + 1] = sh
        a[py_i + 1, px_i] = ROCK[0]
    for qx, qy in ((12, 18), (28, 18)):
        a[qy, qx] = QUARTZ[2]
        a[qy, qx + 1] = QUARTZ[1]
        a[qy + 1, qx + 1] = QUARTZ[0]

    return a


# ==============================================================================
# 7. PREVIEW & QA CONTACT SHEETS + PARALLEL GENERATOR
# ==============================================================================
def render_qa_sheet(out_path: Path, zoom: int = 3) -> None:
    """Fast high-scrutiny 3x QA contact sheet across all 5 animated desert species + desert_burrow."""
    rows_px = []
    specs = [
        ('oryx', ORYX_BUILDS, oryx_frame, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 6), (0, 14), (1, 21), (0, 26), (1, 37), (0, 42), (6, 42)]),
        ('fennec', FENNEC_BUILDS, fennec_frame, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 6), (0, 12), (2, 19), (0, 24), (0, 31), (1, 35), (0, 41)]),
        ('jerboa', JERBOA_BUILDS, jerboa_frame, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 6), (0, 13), (1, 19), (0, 25), (1, 31), (0, 39), (1, 46)]),
        ('agama', AGAMA_BUILDS, agama_frame, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 5), (1, 12), (1, 19), (0, 24), (1, 35), (0, 39), (1, 45)]),
        ('falcon', FALCON_BUILDS, falcon_frame, [(0, 0), (1, 0), (2, 0), (6, 0), (1, 6), (1, 18), (1, 27), (2, 30), (2, 33), (0, 39), (2, 51)]),
    ]
    n_cols = max(len(p) for _, _, _, p in specs)
    total_rows = sum(b for _, b, _, _ in specs)
    canvas = np.zeros((total_rows * H + 40, n_cols * W, 4), np.uint8)
    sand_bg = np.array([208, 168, 108, 255], np.uint8)
    quartz_bg = np.array([214, 226, 245, 255], np.uint8)
    grid_line = np.array([168, 132, 82, 255], np.uint8)
    canvas[:, :] = sand_bg

    ry = 0
    for name, n_b, fn, picks in specs:
        for b in range(n_b):
            is_quartz_morph = (name in ('fennec', 'jerboa', 'agama', 'falcon') and b == 2)
            for ci, (d, col) in enumerate(picks):
                cell = canvas[ry * H:(ry + 1) * H, ci * W:(ci + 1) * W]
                if is_quartz_morph and ci < 4:
                    cell[:, :] = quartz_bg
                px = fn(b, d, col)
                ys, xs = np.where(px[:, :, 3] > 0)
                if len(xs):
                    assert xs.min() >= 1 and xs.max() <= W - 2 and ys.min() >= 1 and ys.max() <= H - 2, (
                        f"QA {name} build={b} d={d} col={col} clipped: x={xs.min()}..{xs.max()} y={ys.min()}..{ys.max()}"
                    )
                mask = px[:, :, 3] > 0
                cell[mask] = px[mask]
                cell[0, :] = grid_line
                cell[:, 0] = grid_line
            ry += 1

    # Paste desert_burrow at bottom row on both sand & quartz backgrounds
    burrow = build_desert_burrow()
    for bi in range(4):
        ox = 16 + bi * 64
        oy = total_rows * H + 8
        if bi == 2:
            canvas[oy - 4:oy + 28, ox - 6:ox + 46] = quartz_bg
        mask_b = burrow[:, :, 3] > 0
        canvas[oy:oy + 24, ox:ox + 40][mask_b] = burrow[mask_b]

    zoomed = np.repeat(np.repeat(canvas, zoom, axis=0), zoom, axis=1)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    save_png(out_path, zoomed)


def write_showcase_preview(sheets: dict[str, np.ndarray], burrow: np.ndarray, out_path: Path) -> None:
    """Write docs/img/desert_wildlife.png (2x zoomed showcase of all 5 species, all builds, key poses + desert_burrow)."""
    picks_map = {
        'oryx': (ORYX_BUILDS, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 6), (0, 14), (0, 26), (1, 37), (0, 42)]),
        'fennec': (FENNEC_BUILDS, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 6), (2, 19), (0, 24), (1, 35), (0, 41)]),
        'jerboa': (JERBOA_BUILDS, [(0, 0), (1, 0), (2, 0), (6, 0), (0, 13), (1, 19), (0, 25), (0, 39), (1, 46)]),
        'agama': (AGAMA_BUILDS, [(0, 0), (1, 0), (2, 0), (6, 0), (1, 12), (0, 24), (1, 35), (0, 39), (1, 45)]),
        'desert_falcon': (FALCON_BUILDS, [(0, 0), (1, 0), (2, 0), (6, 0), (1, 6), (1, 27), (2, 30), (0, 39), (2, 51)]),
    }
    n_cols = 9
    total_rows = sum(nb for nb, _ in picks_map.values())
    pad_b = 44
    canvas = np.zeros((total_rows * H + pad_b, n_cols * W, 4), np.uint8)

    # Warm desert dune sand background with a pale QUARTZ_W band on quartz-adapted Build 2 rows!
    sand_hi = np.array([216, 178, 118, 255], np.uint8)
    sand_lo = np.array([202, 162, 102, 255], np.uint8)
    quartz_tile = np.array([214, 226, 245, 255], np.uint8)
    sep_col = np.array([156, 118, 74, 255], np.uint8)

    for r_i in range(total_rows):
        canvas[r_i * H:(r_i + 1) * H, :] = sand_hi if r_i % 2 == 0 else sand_lo
    canvas[total_rows * H:, :] = sand_hi

    ry = 0
    for key, (nb, picks) in picks_map.items():
        sh = sheets[key]
        for b in range(nb):
            if key != 'oryx' and b == 2:
                canvas[ry * H:(ry + 1) * H, :3 * W] = quartz_tile
            for ci, (d, col) in enumerate(picks):
                src_r = b * 8 + d
                px = sh[src_r * H:(src_r + 1) * H, col * W:(col + 1) * W]
                dst = canvas[ry * H:(ry + 1) * H, ci * W:(ci + 1) * W]
                m = px[:, :, 3] > 0
                dst[m] = px[m]
            ry += 1
        canvas[ry * H - 1, :] = sep_col

    # Showcase desert_burrow along bottom bar (sand + quartz context)
    for idx_b, ox in enumerate((24, 120, 216, 312)):
        oy = total_rows * H + 10
        if idx_b == 2:
            canvas[oy - 4:oy + 28, ox - 8:ox + 48] = quartz_tile
        mb = burrow[:, :, 3] > 0
        canvas[oy:oy + 24, ox:ox + 40][mb] = burrow[mb]

    zoom = 2
    zoomed = np.repeat(np.repeat(canvas, zoom, axis=0), zoom, axis=1)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    save_png(out_path, zoomed)
    print(f"Saved preview {out_path} {zoomed.shape}")


def _build_species_sheet(name: str, builds_n: int, cols_n: int, row_fn, pool: ProcessPoolExecutor) -> np.ndarray:
    sheet = np.zeros((builds_n * 8 * H, cols_n * W, 4), np.uint8)
    jobs = [(v, d) for v in range(builds_n) for d in range(8)]
    for done, (v, d, row_px) in enumerate(pool.map(row_fn, jobs), 1):
        y = (v * 8 + d) * H
        sheet[y:y + H, :] = row_px
    verify_sheet_bounds(name, sheet, cols_n, builds_n * 8, margin=1)
    out_file = ROOT / 'assets' / 'wildlife' / f'{name}.png'
    out_file.parent.mkdir(parents=True, exist_ok=True)
    save_png(out_file, sheet)
    print(f"Saved {out_file} {sheet.shape} (bounds & outline verified!)", flush=True)
    return sheet


def main() -> None:
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith('--qa='):
            out = Path(arg.split('=', 1)[1])
            render_qa_sheet(out, zoom=3)
            print(f"QA sheet written to {out}")
            return
        if arg.startswith('--only='):
            only = arg.split('=', 1)[1]

    burrow = build_desert_burrow()
    burrow_path = ROOT / 'assets' / 'wildlife' / 'desert_burrow.png'
    burrow_path.parent.mkdir(parents=True, exist_ok=True)
    save_png(burrow_path, burrow)
    print(f"Saved {burrow_path} {burrow.shape}", flush=True)
    if only == 'desert_burrow':
        return

    tasks = [
        ('oryx', ORYX_BUILDS, ORYX_COLS, _oryx_row),
        ('fennec', FENNEC_BUILDS, FENNEC_COLS, _fennec_row),
        ('jerboa', JERBOA_BUILDS, JERBOA_COLS, _jerboa_row),
        ('agama', AGAMA_BUILDS, AGAMA_COLS, _agama_row),
        ('desert_falcon', FALCON_BUILDS, FALCON_COLS, _falcon_row),
    ]
    sheets: dict[str, np.ndarray] = {}
    with ProcessPoolExecutor() as pool:
        for name, b_n, c_n, r_fn in tasks:
            if only and only != name:
                continue
            sheets[name] = _build_species_sheet(name, b_n, c_n, r_fn, pool)

    if not only and len(sheets) == 5:
        write_showcase_preview(sheets, burrow, ROOT / 'docs' / 'img' / 'desert_wildlife.png')


if __name__ == '__main__':
    main()
