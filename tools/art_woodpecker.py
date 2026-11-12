#!/usr/bin/env python3
"""Woodpeckers / Spechte in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet/tail-anchor at (32, 48); 62 columns (WildCorvid / WildMeadowBird layout); 3 builds x 8 facings = 24 rows.
No emissive parts; natural woodland palettes with top-left light and cool-violet shadows.

Builds:
  0: Buntspecht (Dendrocopos major — glossy jet-black back/wings/crown, snow-white oval shoulder patches & barred flight feathers,
                 warm creamy-white cheeks & breast, vivid crimson-red nape patch & crimson undertail coverts)
  1: Schwarzspecht (Dryocopus martius — 1.12x larger charcoal-black woodpecker, vivid crimson-red crown/crest cap,
                    pale ivory-yellow chisel bill, pale amber-ivory eye)
  2: Grünspecht (Picus viridis — rich mossy olive-green back & wings, bright golden-olive rump, crimson-red crown + red malar stripe,
                 black Zorro mask around pale eye, pale buff-greenish underparts)

Columns (62):
  idle 0:4, peck 4:10 (rapid vertical bark drumming & chiseling!), walk 10:16,
  preen 16:22, watch 22:26, call 26:30, fly 30:38, land 38:44, takeoff 44:50,
  glide 50:54 (Wellenflug torpedo dart — wings folded tightly sleek against body!),
  hop 54:58 (vertical trunk hitch-hop!), roost 58:62 (vertical trunk cling / rest).

Usage: py -3 tools/art_woodpecker.py [--preview-only] [--qa=path.png]
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

BACK, BREAST, WHITE_PATCH, RUMP_ACCENT, CRIMSON, MASK_DARK, BILL, LEG, EYE, GLINT = range(10)

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
        EYE: 4.2,
        GLINT: 4.8,
        CRIMSON: 2.6,
        WHITE_PATCH: 2.3,
        MASK_DARK: 1.9,
        BILL: 1.7,
        RUMP_ACCENT: 1.6,
    }
    art.ink_color = lambda mat: hexc('0a0814' if mat in (MASK_DARK, BACK, EYE) else '151121')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Buntspecht (Dendrocopos major)
        back = ['0c0c19', '181a2e', '2b304f', '464f78']
        breast = ['877e8f', 'b8aebf', 'e6dfd8', 'fcf8f0']
        white_p = ['8f95ad', 'bfc6de', 'edf1fc', 'ffffff']
        rump = ['0c0c19', '181a2e', '2b304f', '464f78']
        crimson = ['5e0f24', '9e1831', 'de2b43', 'ff5969']
        mask = ['080812', '121324', '21243d', '373c5e']
        bill = ['1b1f30', '323952', '525c7c', '7986ab']
        leg = ['1a1e2e', '2f364d', '4d5775', '717e9e']
        eye = ['2b0b16', '541526', '85263c', 'b53e56']
        glint = ['9aa6b5', 'c2cedb', 'e6eef7', 'ffffff']
    elif v == 1:
        # 1 Schwarzspecht (Dryocopus martius)
        back = ['090914', '141526', '252742', '3e4166']
        breast = ['0b0b17', '16172a', '272945', '404469']
        white_p = ['101221', '1d2036', '303554', '4b5278']
        rump = ['090914', '141526', '252742', '3e4166']
        crimson = ['590e22', '99172f', 'db283f', 'ff5465']
        mask = ['070711', '101121', '1e2038', '333657']
        bill = ['7d7456', 'b0a67b', 'dfd6a6', 'fff9cf']
        leg = ['1a1e2e', '2f364d', '4c5573', '707b9c']
        eye = ['7d6b32', 'b8a14c', 'ebd578', 'fff6b3']
        glint = ['9aa6b5', 'c2cedb', 'e6eef7', 'ffffff']
    else:
        # 2 Grünspecht (Picus viridis)
        back = ['223830', '375e42', '568a4d', '80b862']
        breast = ['6d7870', '98a892', 'c5d4b6', 'ebf2d8']
        white_p = ['787d74', 'a8ada0', 'd8dcc8', 'f7f8e8']
        rump = ['405c28', '6d9633', 'a4cf42', 'd8f266']
        crimson = ['5c1024', '9c1830', 'db2b42', 'ff5768']
        mask = ['080812', '121324', '21243d', '373c5e']
        bill = ['2b303a', '4a525e', '737d8a', 'a1acb5']
        leg = ['232b2e', '3c484c', '5c6d70', '829696']
        eye = ['667085', '96a3ba', 'cad6eb', 'f5f9ff']
        glint = ['9aa6b5', 'c2cedb', 'e6eef7', 'ffffff']

    ramps = [back, breast, white_p, rump, crimson, mask, bill, leg, eye, glint]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_spread_woodpecker_wing(
    m: art.Model,
    v: int,
    side: float,
    shoulder: np.ndarray,
    span: float,
    lift: float,
    sweep_z: float,
    wrist_fold: float,
    camber: float,
    sz: float,
) -> None:
    """Rounded woodland woodpecker wing: white shoulder oval + white-barred primaries on Buntspecht,
    broad charcoal-black on Schwarzspecht, mossy olive + cream-barred wingtips on Grünspecht."""
    carpal = shoulder + np.array([
        side * span * (0.46 - 0.14 * wrist_fold),
        lift * (0.58 + 0.22 * wrist_fold) + camber,
        (1.65 - 0.80 * wrist_fold) * sz + sweep_z * 0.36,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.22 * wrist_fold),
        lift - 1.45 * sz * wrist_fold,
        (-1.85 - 1.15 * wrist_fold) * sz + sweep_z,
    ])

    m.limb(shoulder, carpal, 1.38 * sz, 1.08 * sz, BACK, step=0.58)
    m.limb(carpal, tip, 1.05 * sz, 0.56 * sz, MASK_DARK if v != 2 else BACK, step=0.58)

    # Prominent white oval scapular/shoulder patch on Buntspecht!
    if v == 0:
        scap = shoulder * 0.62 + carpal * 0.38 + np.array([0.0, 0.45 * sz, -1.05 * sz])
        m.ell(scap, (2.15 * sz, 0.92 * sz, 2.25 * sz), WHITE_PATCH)

    # Inner secondaries
    n_sec = 6
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (5.4 - 0.55 * u) * sz * (1.0 - 0.18 * wrist_fold)
        te = le + np.array([side * 0.32 * u * sz, -0.52 * sz - 0.32 * camber, -chord])
        base_mat = BACK if v == 2 else (BACK if i < 2 else MASK_DARK)
        m.limb(le, te, 0.96 * sz, 0.56 * sz, base_mat, step=0.60)
        if v == 0 and i >= 1:
            for b_u in (0.36, 0.70):
                bp = le * (1.0 - b_u) + te * b_u + np.array([0.0, 0.18 * sz, 0.0])
                m.ell(bp, (0.78 * sz, 0.52 * sz, 0.62 * sz), WHITE_PATCH)

    # Outer primaries (rounded woodpecker paddle wingtip)
    n_pri = 5
    finger_spread = 1.0 - 0.52 * wrist_fold
    for i in range(n_pri):
        u = (i + 0.14) / n_pri
        le = carpal * (1.0 - u) + tip * u
        fan_angle = -0.22 + 0.86 * u
        plen = (5.9 - 1.15 * u) * sz * (1.0 - 0.12 * wrist_fold)
        dx = side * math.sin(fan_angle + 0.34) * plen * 0.56 * finger_spread
        dz = -math.cos(fan_angle * 0.62) * plen
        dy = ((u - 0.42) * 0.55 * finger_spread - 0.42 * wrist_fold) * sz
        te = le + np.array([dx, dy, dz])
        pri_mat = MASK_DARK if v != 2 else (BACK if i < 2 else MASK_DARK)
        m.limb(le, te, (0.82 - 0.14 * u) * sz, 0.42 * sz, pri_mat, step=0.58)
        if v == 0:
            for b_u in (0.34, 0.68):
                bp = le * (1.0 - b_u) + te * b_u + np.array([0.0, 0.16 * sz, 0.0])
                m.ell(bp, (0.68 * sz, 0.48 * sz, 0.56 * sz), WHITE_PATCH)
        elif v == 2 and i >= 2:
            bp = le * 0.48 + te * 0.52 + np.array([0.0, 0.12 * sz, 0.0])
            m.ell(bp, (0.58 * sz, 0.40 * sz, 0.48 * sz), WHITE_PATCH)


def build_woodpecker(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    # Agile ~14-17 px body; Schwarzspecht (v==1) is 1.12x larger!
    base_sz = 0.90
    sz = base_sz * (1.12 if v == 1 else 1.0)
    tau = math.tau
    p = t * tau
    bob = math.sin(p)

    flying = kind in ('fly', 'takeoff', 'land', 'glide')
    trunk_cling = kind in ('peck', 'hop', 'roost')

    # Default alert upright woodland woodpecker branch/log stance (GROUND_ROW = 48.0)
    rump_y, rump_z = 5.05 * sz, -2.05 * sz
    chest_y, chest_z = 8.85 * sz, 1.35 * sz
    head_y, head_z = 12.65 * sz, 2.05 * sz
    head_pitch = 0.02
    head_yaw = 0.0
    head_roll = 0.0
    body_sway_x = 0.0
    crest_raise = 0.25 if v == 1 else 0.05
    beak_open = 0.0
    blink = False
    tail_pitch = -0.44
    tail_fan = 0.72
    tail_brace = False
    wing_preen_side = 0.0
    hop_wing = 0.0
    torpedo_tight = False

    # Feet anchored cleanly on GROUND_ROW = 48.0 (y = 0.68 independent of sz so all builds sit flush!)
    foot_L = np.array([-1.32 * sz, 0.68, 0.65 * sz])
    foot_R = np.array([1.32 * sz, 0.68, 0.65 * sz])
    toes_curl = 0.0
    trunk_grip_feet = False

    if kind == 'idle':
        idx = int(round(t * 4)) % 4
        chest_y += 0.14 * bob * sz
        head_y += 0.16 * bob * sz
        head_yaw = 0.14 * math.sin(p)
        crest_raise += 0.06 * max(0.0, bob)
        blink = (idx == 3)

    elif kind == 'peck':
        # 6 frames: Rapid Vertical Bark Drumming & Chiseling!
        # Body braced ~72 deg upright on trunk, stiff prop-tail pressed down, neck & chisel bill hammering rapidly!
        idx = int(round(t * 6)) % 6
        # Alternating coil (-1) and hard forward chisel strikes (+1)
        strikes = [-0.90, 1.0, -0.60, 0.96, -0.65, 0.90][idx]
        trunk_grip_feet = True
        tail_brace = True
        rump_y, rump_z = 5.15 * sz, -0.55 * sz
        chest_y = (9.75 - 0.28 * max(0.0, strikes)) * sz
        chest_z = (0.95 + 0.55 * strikes) * sz
        head_y = (13.65 - 0.65 * max(0.0, strikes)) * sz
        head_z = (1.15 + 2.85 * strikes) * sz
        head_pitch = -0.20 + 0.44 * strikes
        crest_raise = (0.48 if v == 1 else 0.30) + 0.18 * max(0.0, -strikes)
        foot_L = np.array([-1.42 * sz, 5.55 * sz, 2.15 * sz])
        foot_R = np.array([1.42 * sz, 5.55 * sz, 2.15 * sz])

    elif kind == 'walk':
        # 6-frame brisk two-footed hop-walk along a fallen trunk!
        hop_phase = math.sin(p * 2.0)
        lift = max(0.0, math.sin(p)) * 1.55 * sz
        stride = math.cos(p) * 1.35 * sz
        rump_y += lift + 0.18 * abs(hop_phase) * sz
        chest_y += lift + 0.22 * abs(hop_phase) * sz
        head_y += lift + 0.20 * hop_phase * sz
        head_z += 0.55 * max(0.0, hop_phase) * sz
        body_sway_x = 0.24 * math.sin(p) * sz
        tail_pitch = -0.38 + 0.12 * math.sin(p)
        foot_L = np.array([-1.32 * sz, 0.68 + lift * 0.88, 0.65 * sz + stride])
        foot_R = np.array([1.32 * sz, 0.68 + lift * 0.88, 0.65 * sz - stride * 0.35])

    elif kind == 'preen':
        # 6 frames: turning head over shoulder to preen wing/shoulder plumage
        idx = int(round(t * 6)) % 6
        turn_amt = [0.42, 0.94, 1.0, 0.92, 0.36, 0.0][idx]
        head_yaw = 1.28 * turn_amt
        head_pitch = 0.38 * turn_amt + (0.14 if idx == 2 else 0.0)
        head_roll = -0.15 * turn_amt
        head_y = (12.65 - 1.50 * turn_amt + (0.35 if idx == 4 else 0.0)) * sz
        head_z = (2.05 - 1.70 * turn_amt) * sz
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
        if idx == 4:
            chest_y += 0.35 * sz
            crest_raise += 0.22

    elif kind == 'watch':
        # 4 frames: crest raised sharply, head cocked sideways scanning bark/surroundings!
        idx = int(round(t * 4)) % 4
        cock = [0.24, 0.42, -0.34, -0.18][idx]
        chest_y = 9.35 * sz
        head_y = 13.45 * sz
        head_z = 2.15 * sz
        head_pitch = -0.06
        head_yaw = cock * 1.05
        head_roll = cock * 0.85
        crest_raise = 0.85 if v == 1 else 0.72
        tail_pitch = -0.48

    elif kind == 'call':
        # 4 frames: sharp "Kix!" / "Klü-klü-klü" call with wide-open chisel bill & raised red crown!
        idx = int(round(t * 4)) % 4
        shout = [0.22, 1.0, 0.92, 0.30][idx]
        rump_y = (5.05 + 0.35 * shout) * sz
        chest_y = (8.85 + 0.25 * shout) * sz
        chest_z = (1.35 + 0.65 * shout) * sz
        head_y = (12.65 + 0.35 * shout) * sz
        head_z = (2.05 + 1.15 * shout) * sz
        head_pitch = -0.14 * shout
        beak_open = [0.18, 1.0, 0.88, 0.22][idx]
        crest_raise = (0.95 if v == 1 else 0.85) * shout + 0.20
        tail_fan = 0.72 + 0.38 * shout
        hop_wing = 0.22 * shout

    elif kind == 'hop':
        # 4 frames: Vertical Trunk Hitch-Hop (~72 deg upright trunk-clinging upward hop + braced prop-tail!)
        idx = int(round(t * 4)) % 4
        trunk_grip_feet = True
        tail_brace = True
        climb = [0.0, 2.85, 2.25, 0.35][idx] * sz
        crouch = 0.65 * sz if idx == 0 else 0.0
        rump_y = 5.35 * sz + climb - crouch
        rump_z = (-0.55 - (0.35 if idx in (1, 2) else 0.0)) * sz
        chest_y = 9.85 * sz + climb - crouch * 0.7
        chest_z = (0.95 + (0.45 if idx == 1 else 0.0)) * sz
        head_y = 13.65 * sz + climb - crouch * 0.6
        head_z = (1.35 + (0.55 if idx == 1 else 0.0)) * sz
        head_pitch = -0.12 if idx in (1, 2) else -0.04
        crest_raise = 0.48 if v == 1 else 0.35
        hop_wing = 0.38 if idx == 1 else (0.20 if idx == 2 else 0.0)
        reach_up = (1.15 if idx == 1 else (0.65 if idx == 2 else 0.0)) * sz
        foot_L = np.array([-1.42 * sz, 5.75 * sz + climb + reach_up - crouch, 2.20 * sz])
        foot_R = np.array([1.42 * sz, 5.75 * sz + climb + reach_up - crouch, 2.20 * sz])

    elif kind == 'roost':
        # 4 frames: Vertical Trunk Cling / Rest (~75 deg upright against bark, prop-tail braced below, calm/tucked)
        idx = int(round(t * 4)) % 4
        trunk_grip_feet = True
        tail_brace = True
        breath = 0.08 * bob * sz
        rump_y, rump_z = 5.45 * sz + breath, -0.42 * sz
        chest_y, chest_z = 9.75 * sz + breath, 0.78 * sz
        head_y, head_z = 12.65 * sz + breath, 0.88 * sz
        head_pitch = 0.08
        head_yaw = 0.08 * math.sin(p)
        crest_raise = 0.15 if v == 1 else 0.0
        blink = idx in (1, 2, 3)
        foot_L = np.array([-1.38 * sz, 5.85 * sz, 2.10 * sz])
        foot_R = np.array([1.38 * sz, 5.85 * sz, 2.10 * sz])

    elif flying:
        if kind == 'fly':
            idx = int(round(t * 8)) % 8
            body_lift = [-0.30, -0.10, 0.40, 0.65, 0.30, -0.08, -0.28, -0.35][idx] * sz
            by = 11.4 * sz + body_lift
            rump_y, rump_z = by - 0.55 * sz, -2.95 * sz
            chest_y, chest_z = by + 0.35 * sz, 2.15 * sz
            head_y, head_z = by + 1.25 * sz, 4.75 * sz
            head_pitch = 0.08
            tail_pitch = -0.05
            tail_fan = 0.95
            toes_curl = 1.0
            foot_L = np.array([-1.15 * sz, rump_y - 1.35 * sz, -0.95 * sz])
            foot_R = np.array([1.15 * sz, rump_y - 1.35 * sz, -0.95 * sz])

        elif kind == 'glide':
            # Wellenflug Torpedo Dart! Wings folded tightly sleek against torso during downward wave bound!
            idx = int(round(t * 4)) % 4
            torpedo_tight = True
            wave_y = [12.4, 11.4, 10.2, 11.2][idx] * sz
            wave_pitch = [0.06, -0.10, -0.18, -0.04][idx]
            rump_y = wave_y - math.sin(wave_pitch) * 2.8 * sz
            rump_z = -3.25 * sz
            chest_y = wave_y + math.sin(wave_pitch) * 2.2 * sz
            chest_z = 2.35 * sz
            head_y = chest_y + (0.55 + math.sin(wave_pitch) * 2.4) * sz
            head_z = 5.35 * sz
            head_pitch = 0.14 - wave_pitch * 0.65
            crest_raise = 0.0
            tail_pitch = -wave_pitch * 0.85
            tail_fan = 0.32
            toes_curl = 1.0
            foot_L = np.array([-0.95 * sz, rump_y - 1.05 * sz, -0.65 * sz])
            foot_R = np.array([0.95 * sz, rump_y - 1.05 * sz, -0.65 * sz])

        elif kind == 'takeoff':
            idx = int(round(t * 6)) % 6
            if idx == 0:
                trunk_grip_feet = True
                tail_brace = True
                rump_y, rump_z = 5.05 * sz, -0.85 * sz
                chest_y, chest_z = 8.95 * sz, 1.65 * sz
                head_y, head_z = 12.55 * sz, 2.95 * sz
                head_pitch = -0.10
                foot_L = np.array([-1.42 * sz, 5.25 * sz, 2.05 * sz])
                foot_R = np.array([1.42 * sz, 5.25 * sz, 2.05 * sz])
            else:
                u = ease(idx / 5.0)
                by = (8.2 + 4.0 * u) * sz
                rump_y, rump_z = by - (1.2 - 0.6 * u) * sz, (-2.2 - 0.7 * u) * sz
                chest_y, chest_z = by + (0.9 - 0.5 * u) * sz, 2.15 * sz
                head_y, head_z = by + (2.8 - 1.4 * u) * sz, (3.6 + 1.1 * u) * sz
                tail_fan = 1.10
                toes_curl = min(1.0, u * 1.25)
                fy = (2.8 + 5.8 * u) * sz
                fz = (1.2 - 2.0 * u) * sz
                foot_L = np.array([-1.20 * sz, fy, fz])
                foot_R = np.array([1.20 * sz, fy, fz])

        elif kind == 'land':
            # Swooping upward flare onto vertical bark: claws forward & stiff prop-tail braced down!
            idx = int(round(t * 6)) % 6
            flare = [0.75, 0.95, 1.0, 0.85, 0.55, 0.25][idx]
            approach_z = [-2.2, -1.2, -0.4, 0.0, 0.0, 0.0][idx] * sz
            trunk_grip_feet = True
            tail_brace = idx >= 3
            rump_y = (6.8 - 1.35 * (idx / 5.0)) * sz
            rump_z = -0.75 * sz + approach_z
            chest_y = (10.9 - 1.05 * (idx / 5.0)) * sz
            chest_z = 0.95 * sz + approach_z
            head_y = (14.4 - 0.85 * (idx / 5.0)) * sz
            head_z = 1.45 * sz + approach_z
            head_pitch = -0.14 * flare
            tail_pitch = -0.68
            tail_fan = 0.75 + 0.45 * flare
            foot_L = np.array([-1.42 * sz, 5.95 * sz, (2.25 + 0.55 * flare) * sz + approach_z])
            foot_R = np.array([1.42 * sz, 5.95 * sz, (2.25 + 0.55 * flare) * sz + approach_z])

    # ---- Sleek Agile Woodpecker Torso (ventral BREAST + dorsal BACK + RUMP_ACCENT + undertail) ----
    fluff = 1.08 if kind == 'roost' else (0.88 if torpedo_tight else 1.0)
    torso_axis = np.array([0.0, chest_y - rump_y, chest_z - rump_z])
    # Non-singular ventral hint across 0..90 deg pitch (keeps dorsal BACK on top even in horizontal Wellenflug!)
    t_rot = art.frame_from(torso_axis, [0.0, -0.55, 0.85])

    for u in (0.0, 0.32, 0.66, 1.0):
        sy = rump_y + (chest_y - rump_y) * u
        sz_p = rump_z + (chest_z - rump_z) * u
        arch = math.sin(u * math.pi)
        rx = (2.15 + 0.42 * arch) * sz * fluff
        ry = (2.10 + 0.38 * arch) * sz
        rz = (2.18 + 0.28 * arch) * sz * fluff
        # Ventral breast/belly cushion (offset slightly forward along local +z)
        v_off = t_rot @ np.array([0.0, 0.0, 0.38 * sz * fluff])
        m.ell(np.array([body_sway_x, sy, sz_p]) + v_off, (rx * 0.96, ry, rz * 0.92), BREAST, R=t_rot)
        # Dorsal mantle/back cushion (offset slightly back along local -z)
        d_off = t_rot @ np.array([0.0, 0.0, -0.42 * sz * fluff])
        d_mat = RUMP_ACCENT if u < 0.25 else BACK
        m.ell(np.array([body_sway_x, sy, sz_p]) + d_off, (rx * 0.95, ry, rz * 0.90), d_mat, R=t_rot)

    # Vivid golden-olive rump cap on Grünspecht (v==2) so it gleams in flight & rear/side views!
    if v == 2:
        r_pos = np.array([body_sway_x, rump_y, rump_z]) + t_rot @ np.array([0.0, -0.15 * sz, -1.05 * sz])
        m.ell(r_pos, (1.88 * sz, 1.75 * sz, 1.45 * sz), RUMP_ACCENT, R=t_rot)

    # Vivid crimson undertail coverts ("rote Unterschwanzdecken") on Buntspecht (v==0)!
    if v == 0:
        ut_pos = np.array([body_sway_x, rump_y, rump_z]) + t_rot @ np.array([0.0, -1.15 * sz, 0.35 * sz])
        m.ell(ut_pos, (1.28 * sz, 1.15 * sz, 1.18 * sz), CRIMSON, R=t_rot)

    # Black lateral breast crescent bridle on Buntspecht (frames creamy chest from white shoulder!)
    if v == 0:
        for side in (-1.0, 1.0):
            br_p = np.array([body_sway_x, chest_y, chest_z]) + t_rot @ np.array([side * 1.68 * sz, 0.35 * sz, 0.95 * sz])
            m.ell(br_p, (0.68 * sz, 1.05 * sz, 0.82 * sz), MASK_DARK, R=t_rot)

    # Muscular neck column (allows rapid chisel-hammer extension!)
    for u in (0.35, 0.72):
        ny = chest_y + (head_y - chest_y) * u
        nz = chest_z + (head_z - chest_z) * u
        nr = (1.68 - 0.18 * u) * sz * (1.06 if kind == 'roost' else 1.0)
        m.ell((body_sway_x, ny, nz + 0.22 * sz), (nr * 0.92, nr, nr * 0.88), BREAST)
        m.ell((body_sway_x, ny, nz - 0.32 * sz), (nr * 0.90, nr, nr * 0.88), BACK)

    # ---- Wings: Folded / Wellenflug Torpedo Sleek OR Spread Woodland Wingbeats ----
    max_span = 14.2
    mid_p = np.array([body_sway_x, 0.45 * rump_y + 0.55 * chest_y, 0.45 * rump_z + 0.55 * chest_z])
    for side in (-1.0, 1.0):
        sh = np.array([body_sway_x, chest_y, chest_z]) + t_rot @ np.array([side * 1.95 * sz, 0.25 * sz, -0.25 * sz])
        folded_now = (
            not flying
            or torpedo_tight
            or (kind == 'takeoff' and int(round(t * 6)) % 6 == 0)
            or (kind == 'land' and int(round(t * 6)) % 6 == 5)
        )
        if folded_now:
            preen_open = 1.0 if side * wing_preen_side > 0 else 0.0
            flick = (0.0 if torpedo_tight else hop_wing) + 0.65 * preen_open
            w_rot = t_rot @ art.rot_y(side * (0.08 + 0.30 * flick)) @ rot_z(-side * 0.22 * flick)
            tight_x = 1.82 if torpedo_tight else (2.05 + 0.75 * flick)
            w_center = mid_p + t_rot @ np.array([side * tight_x * sz, (0.05 + 0.35 * flick) * sz, -0.42 * sz])
            m.ell(w_center, (0.98 * sz, 3.15 * sz, 1.65 * sz), BACK, R=w_rot)

            if v == 0:
                # Iconic Buntspecht snow-white oval shoulder/scapular patch!
                ov_p = w_center + w_rot @ np.array([side * 0.46 * sz, 0.95 * sz, 0.28 * sz])
                m.ell(ov_p, (0.56 * sz, 1.52 * sz, 0.88 * sz), WHITE_PATCH, R=w_rot)
                # White-barred black primary feathers below shoulder oval
                for bar_i in range(3):
                    yb = (-0.55 - bar_i * 1.05) * sz
                    zb = (-0.35 - bar_i * 0.28) * sz
                    m.ell(w_center + w_rot @ np.array([side * 0.36 * sz, yb, zb]),
                          (0.50 * sz, 0.42 * sz, 0.72 * sz), WHITE_PATCH, R=w_rot)
                    m.ell(w_center + w_rot @ np.array([side * 0.32 * sz, yb - 0.50 * sz, zb - 0.14 * sz]),
                          (0.52 * sz, 0.52 * sz, 0.76 * sz), MASK_DARK, R=w_rot)
            elif v == 1:
                # Charcoal-black folded primaries on Schwarzspecht
                for pf in range(2):
                    m.ell(w_center + w_rot @ np.array([side * 0.22 * sz, (-1.85 - pf * 1.05) * sz, (-0.45 - pf * 0.25) * sz]),
                          (0.58 * sz, 1.35 * sz, 0.82 * sz), MASK_DARK, R=w_rot)
            else:
                # Mossy olive coverts + cream-spotted dark primary tips on Grünspecht
                for bar_i in range(2):
                    yb = (-1.65 - bar_i * 0.95) * sz
                    m.ell(w_center + w_rot @ np.array([side * 0.30 * sz, yb, -0.45 * sz]),
                          (0.48 * sz, 0.40 * sz, 0.68 * sz), WHITE_PATCH, R=w_rot)
                    m.ell(w_center + w_rot @ np.array([side * 0.26 * sz, yb - 0.45 * sz, -0.55 * sz]),
                          (0.50 * sz, 0.52 * sz, 0.72 * sz), MASK_DARK, R=w_rot)
        else:
            if kind == 'fly':
                idx = int(round(t * 8)) % 8
                lifts = [8.2, 4.0, -1.5, -6.2, -3.4, 1.8, 5.8, 8.6][idx] * sz
                folds = [0.08, 0.0, 0.0, 0.10, 0.50, 0.60, 0.36, 0.14][idx]
                sweeps = [-1.2, 0.8, 2.0, 2.6, 0.5, -1.1, -1.8, -1.5][idx] * sz
                cambers = [0.6, 1.2, 1.4, 0.8, 0.3, 0.5, 0.8, 0.7][idx] * sz
                draw_spread_woodpecker_wing(m, v, side, sh, max_span, lifts, sweeps, folds, cambers, sz)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                lifts = [0.0, 8.8, 2.4, -5.6, 1.0, 7.6][idx] * sz
                folds = [0.0, 0.08, 0.0, 0.08, 0.46, 0.15][idx]
                sweeps = [0.0, -1.1, 1.8, 2.6, -0.5, -1.3][idx] * sz
                draw_spread_woodpecker_wing(m, v, side, sh, max_span, lifts, sweeps, folds, 1.0 * sz, sz)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                lifts = [6.2, 2.0, 7.2, 3.8, 1.8, 0.0][idx] * sz
                folds = [0.10, 0.06, 0.14, 0.34, 0.66, 1.0][idx]
                sweeps = [2.2, 3.0, 1.8, 1.0, -0.4, 0.0][idx] * sz
                draw_spread_woodpecker_wing(m, v, side, sh, max_span * 0.94, lifts, sweeps, folds, 1.1 * sz, sz)

    # ---- Stiff Wedge-Shaped Prop-Tail ("Stützschwanz") ----
    if tail_brace:
        # Braced firmly downward & forward against vertical bark right on GROUND_ROW = 48!
        t_base = np.array([body_sway_x, rump_y - 0.55 * sz, rump_z - 0.50 * sz])
        for f_i in (-2, -1, 0, 1, 2):
            x_sp = f_i * 0.48 * tail_fan * sz
            t_mid = np.array([body_sway_x + x_sp * 0.7, 2.75 * sz, rump_z + 0.35 * sz])
            # Pointed central rectrices brace right on GROUND_ROW = 48; outer ones form crisp wedge
            tip_y = 0.72 + abs(f_i) * 0.58 * sz
            t_end = np.array([body_sway_x + x_sp, tip_y, rump_z + 1.55 * sz])
            f_mat = WHITE_PATCH if (v == 0 and abs(f_i) == 2) else (BACK if v == 2 and abs(f_i) <= 1 else MASK_DARK)
            m.limb(t_base, t_mid, 0.82 * sz, 0.68 * sz, MASK_DARK if v != 2 else BACK, step=0.44)
            m.limb(t_mid, t_end, 0.68 * sz, 0.46 * sz, f_mat, step=0.38)
    else:
        t_base = np.array([body_sway_x, rump_y - 0.35 * sz, rump_z - 1.55 * sz])
        for f_i in (-2, -1, 0, 1, 2):
            # Wedge-shaped pointed woodpecker tail (central feathers longest!)
            t_len = (5.4 - abs(f_i) * 0.72) * sz
            f_yaw = -f_i * 0.11 * tail_fan
            tr = art.rot_y(f_yaw) @ art.rot_x(tail_pitch)
            t_end = t_base + tr @ np.array([0.0, 0.0, -t_len])
            f_mat = WHITE_PATCH if (v == 0 and abs(f_i) == 2) else (BACK if v == 2 and abs(f_i) == 0 else MASK_DARK)
            m.limb(t_base, t_end, 0.76 * sz, 0.28 * sz, f_mat, step=0.52)

    # ---- Zygodactyl Gripping Feet (2 forward/upward + 2 outer/rear claws) ----
    for s_idx, side in enumerate((-1.0, 1.0)):
        ft = foot_L if s_idx == 0 else foot_R
        if trunk_grip_feet:
            hip = np.array([body_sway_x + side * 1.25 * sz, rump_y + 0.35 * sz, rump_z + 0.95 * sz])
            ankle = 0.48 * hip + 0.52 * ft + np.array([0.0, -0.35 * sz, -0.25 * sz])
            m.ell(0.60 * hip + 0.40 * ankle, (0.95 * sz, 1.12 * sz, 0.98 * sz), BREAST if v != 1 else BACK)
            m.limb(ankle, ft, 0.58 * sz, 0.48 * sz, LEG, step=0.40)
            # 2 upward bark-gripping zygodactyl toes + 1 lateral/downward bracing toe
            for ty_d, tx_d in ((1.35, -0.35), (1.45, 0.42), (-1.05, side * 0.45)):
                claw_p = ft + np.array([tx_d * sz, ty_d * sz, 0.55 * sz])
                m.limb(ft, claw_p, 0.44 * sz, 0.24 * sz, LEG, step=0.36)
        else:
            hip = np.array([body_sway_x + side * 1.22 * sz, rump_y - 0.35 * sz, rump_z + 1.85 * sz])
            ankle = 0.45 * hip + 0.55 * ft + np.array([0.0, 0.55 * sz, -0.35 * sz])
            m.ell(0.62 * hip + 0.38 * ankle, (0.95 * sz, 1.18 * sz, 1.02 * sz), BREAST if v != 1 else BACK)
            m.limb(ankle, ft, 0.58 * sz, 0.48 * sz, LEG, step=0.42)
            if toes_curl < 0.7:
                # 2 zygodactyl forward toes + 2 zygodactyl rear/outer toes
                for tx_d in (-0.52, 0.52):
                    m.limb(ft, ft + np.array([tx_d * sz, -0.12, 1.38 * sz]), 0.42 * sz, 0.26 * sz, LEG, step=0.38)
                for tx_d in (-0.42, 0.42):
                    m.limb(ft, ft + np.array([tx_d * sz, -0.10, -1.02 * sz]), 0.38 * sz, 0.24 * sz, LEG, step=0.38)
            else:
                m.ell(ft, (0.62 * sz, 0.52 * sz, 0.78 * sz), LEG)

    # ---- Angular Woodpecker Head, Species Markings, Crest & Straight Chisel Bill ----
    h_rot = art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)
    head_c = np.array([body_sway_x, head_y, head_z])

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + h_rot @ (np.array([x, y, z]) * sz)

    if v == 0:
        # Buntspecht: creamy-white cheek/face base + glossy black crown + vivid crimson nape + black bridle!
        m.ell(hp(0.0, -0.05, 0.12), (1.88 * sz, 1.95 * sz, 2.18 * sz), BREAST, R=h_rot)
        m.ell(hp(0.0, 1.02, -0.08), (1.72 * sz, 1.18 * sz, 2.15 * sz), MASK_DARK, R=h_rot)
        # Vivid crimson-red nape patch ("roter Genickfleck") + occipital tuft
        m.ell(hp(0.0, 0.88 + 0.35 * crest_raise, -1.45), (1.48 * sz, (0.98 + 0.32 * crest_raise) * sz, 1.12 * sz), CRIMSON, R=h_rot)
        # Crisp black bridle ("Zügel" & malar bar framing the white cheek & white neck spot)
        for side in (-1.0, 1.0):
            m.limb(hp(side * 0.95, -0.35, 1.55), hp(side * 1.62, -0.58, -0.15), 0.44 * sz, 0.46 * sz, MASK_DARK, step=0.38)
            m.limb(hp(side * 1.62, -0.58, -0.15), hp(side * 1.45, 0.65, -0.85), 0.44 * sz, 0.42 * sz, MASK_DARK, step=0.38)
            # Snow-white lateral neck oval behind black cheek bar
            m.ell(hp(side * 1.42, -0.35, -1.22), (0.58 * sz, 0.78 * sz, 0.72 * sz), WHITE_PATCH, R=h_rot)

    elif v == 1:
        # Schwarzspecht: charcoal-black head + striking full vivid crimson-red crown & pointed occipital crest!
        m.ell(hp(0.0, -0.08, 0.10), (1.92 * sz, 1.98 * sz, 2.24 * sz), MASK_DARK, R=h_rot)
        # Full crimson crown cap from forehead to rear crest tip
        m.ell(hp(0.0, 1.18, 0.25), (1.62 * sz, 1.08 * sz, 2.05 * sz), CRIMSON, R=h_rot)
        crest_tip = hp(0.0, 1.55 + 0.95 * crest_raise, -2.25 - 0.35 * crest_raise)
        m.limb(hp(0.0, 1.15, -0.65), crest_tip, 1.15 * sz, 0.38 * sz, CRIMSON, step=0.38)

    else:
        # Grünspecht: sage-cream throat/cheek + mossy neck + full crimson crown/nape + black Zorro mask + red malar!
        m.ell(hp(0.0, -0.10, 0.12), (1.90 * sz, 1.95 * sz, 2.20 * sz), BREAST, R=h_rot)
        m.ell(hp(0.0, -0.35, -0.95), (1.76 * sz, 1.65 * sz, 1.45 * sz), BACK, R=h_rot)
        # Full vivid crimson crown + nape crest
        m.ell(hp(0.0, 1.12, 0.10), (1.68 * sz, 1.12 * sz, 2.18 * sz), CRIMSON, R=h_rot)
        m.limb(hp(0.0, 1.05, -0.85), hp(0.0, 1.25 + 0.75 * crest_raise, -2.05), 1.12 * sz, 0.44 * sz, CRIMSON, step=0.40)
        for side in (-1.0, 1.0):
            # Bold jet-black Zorro mask around lore & eye!
            m.ell(hp(side * 1.28, 0.32, 0.92), (0.78 * sz, 0.82 * sz, 1.38 * sz), MASK_DARK, R=h_rot)
            # Vivid crimson malar moustache stripe ("roter Bartstreif") below Zorro mask!
            m.limb(hp(side * 1.02, -0.45, 1.48), hp(side * 1.58, -0.78, 0.05), 0.46 * sz, 0.42 * sz, CRIMSON, step=0.36)

    # Straight Sharp Chisel Bill ("Meißelschnabel" — dead-straight wedge!)
    bill_len = 3.65 if v == 1 else 3.25
    up_rot = h_rot @ art.rot_x(-0.26 * beak_open)
    b_root = hp(0.0, 0.08 + 0.08 * beak_open, 1.78)
    b_tip = b_root + up_rot @ (np.array([0.0, 0.02, bill_len]) * sz)
    m.limb(b_root, b_tip, 0.68 * sz, 0.24 * sz, BILL, step=0.38)

    lo_rot = h_rot @ art.rot_x(0.44 * beak_open)
    l_root = hp(0.0, -0.28 - 0.26 * beak_open, 1.72)
    l_tip = l_root + lo_rot @ (np.array([0.0, 0.04, bill_len * 0.94]) * sz)
    m.limb(l_root, l_tip, 0.56 * sz, 0.22 * sz, BILL, step=0.38)

    # Crisp 3D Eyes (TIDY_EYES = False — natural occlusion across all 8 facings!)
    for side in (-1.0, 1.0):
        eh = 0.16 if blink else 0.58
        m.ell(hp(side * 1.54, 0.36, 0.88), (0.50 * sz, eh * sz, 0.58 * sz), EYE, R=h_rot)
        if not blink:
            if v in (1, 2):
                # Dark pupil core inside pale amber/ivory iris so gaze reads sharply!
                m.ell(hp(side * 1.72, 0.35, 0.95), (0.26 * sz, 0.30 * sz, 0.30 * sz), MASK_DARK, R=h_rot)
            m.ell(hp(side * 1.68, 0.55, 1.12), (0.21 * sz, 0.21 * sz, 0.21 * sz), GLINT, R=h_rot)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_woodpecker(v, kind, (col - start) / n)
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
        (0, 0),   # E idle (chisel bill, shoulder oval, crimson nape/crown, Zorro mask!)
        (1, 0),   # SE idle 3/4 view
        (2, 0),   # S idle front view
        (6, 0),   # N idle dorsal view (white ovals / golden-olive rump!)
        (0, 4),   # E peck coil on vertical bark (~70 deg upright + braced prop-tail!)
        (0, 5),   # E peck forward chisel strike!
        (1, 5),   # SE peck forward chisel strike!
        (0, 11),  # E brisk log hop-walk
        (1, 18),  # SE preen shoulder plumage
        (1, 23),  # SE watch (crest raised, head cocked!)
        (0, 27),  # E sharp "Kix!" call (open chisel bill + raised red crest!)
        (1, 30),  # SE fly upstroke (white wing bars / golden rump!)
        (1, 33),  # SE fly downstroke
        (0, 40),  # E trunk landing flare (claws forward + braced prop-tail!)
        (0, 52),  # E Wellenflug torpedo dart (wings tightly folded sleek!)
        (0, 55),  # E vertical trunk hitch-hop!
        (1, 59),  # SE vertical trunk cling / roost!
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
                print(f'woodpecker build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/woodpecker.png', sheet)
    print('Saved assets/wildlife/woodpecker.png', sheet.shape)


if __name__ == '__main__':
    main()
