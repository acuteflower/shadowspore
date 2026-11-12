#!/usr/bin/env python3
"""Grey Heron (Ardea cinerea) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet at (32, 54); 58 columns; 3 builds x 8 true facings = 24 rows. No emissive parts.
Builds:
  0: Altvogel Silberschiefer (classic slate-blue mantle, crisp white S-neck, black crest & shoulder patch, muted horn-ochre bill)
  1: Dunkelschiefer-Nebelreiher (deeper storm-indigo slate for misty forest rivers)
  2: Jungreiher (ash-grey neck & mantle, shorter crest plumes, duskier horn bill)
Columns (58):
  idle 0:4, one_leg 4:8, hunch 8:12, wade 12:20, strike 20:26, catch 26:30,
  preen 30:34, alert 34:38, fly 38:46, glide 46:50, takeoff 50:54, land 54:58.
Usage: py -3 tools/art_heron.py [--preview-only] [--qa=path.png]
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
COLS = 58

MANTLE, WHITE, BLACK_PLUME, BILL, EYE_IRIS, SCAPULAR, LEGS = range(7)

BLOCKS = [
    ('idle', 0, 4),
    ('one_leg', 4, 4),
    ('hunch', 8, 4),
    ('wade', 12, 8),
    ('strike', 20, 6),
    ('catch', 26, 4),
    ('preen', 30, 4),
    ('alert', 34, 4),
    ('fly', 38, 8),
    ('glide', 46, 4),
    ('takeoff', 50, 4),
    ('land', 54, 4),
]


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 54.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {EYE_IRIS: 3.6, BLACK_PLUME: 1.5, BILL: 1.8}
    art.ink_color = lambda mat: hexc('121320' if mat == BLACK_PLUME else '1b1b29')


def bez2(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, n: int = 16) -> list[np.ndarray]:
    p0, p1, p2 = (np.asarray(p, float) for p in (p0, p1, p2))
    return [(1.0 - u) ** 2 * p0 + 2.0 * u * (1.0 - u) * p1 + (u ** 2) * p2 for u in (i / n for i in range(n + 1))]


def lerp(a: np.ndarray | list[float], b: np.ndarray | list[float], k: float) -> np.ndarray:
    return np.asarray(a, float) * (1.0 - k) + np.asarray(b, float) * k


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Classic adult silver-slate Ardea cinerea
        mantle = ['273445', '455a73', '728ba3', 'aebfcb']
        white = ['8896a4', 'b4c1cd', 'dce5ec', 'f6fafa']
        bill = ['6b4e22', '9a7232', 'c49848', 'dfc072']
        scap = ['4b5a6d', '6f8298', '9ab0c4', 'cddbe6']
    elif v == 1:
        # 1 Deep storm-slate mist heron
        mantle = ['1f2a3a', '384b62', '607892', '9bb0c2']
        white = ['7d8b9a', 'aab8c6', 'd4dfe8', 'f0f5f8']
        bill = ['614720', '8e682e', 'b88e44', 'd6b66a']
        scap = ['404e62', '63768e', '8ea4ba', 'c2d2e0']
    else:
        # 2 Subadult grey heron (softer ash-grey neck & duskier horn bill)
        mantle = ['313844', '535d6c', '7e8998', 'b2bcc8']
        white = ['6e7682', '969fa8', 'c0c8d0', 'e2e7ec']
        bill = ['524026', '7a6038', 'a2824e', 'c2a672']
        scap = ['48505c', '6c7684', '96a0ae', 'c4ccd6']

    ramps = [
        mantle,                                             # 0 MANTLE
        white,                                              # 1 WHITE (neck, crown, breast plumes)
        ['0d101b', '1c2132', '30374c', '4a536b'],           # 2 BLACK_PLUME (crest, primaries, shoulder patch, pupil)
        bill,                                               # 3 BILL (muted horn-ochre dagger bill)
        ['b89844', 'dec05e', 'f5e28c', 'fff8cc'],           # 4 EYE_IRIS (pale golden-amber heron iris)
        scap,                                               # 5 SCAPULAR (silvery-blue coverts & brook fish)
        ['34352a', '555542', '7a7960', 'a4a082'],           # 6 LEGS (dull olive-slate wading legs & culmen ridge)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_heron_wing(
    m: art.Model,
    side: float,
    T_fn,
    R_body: np.ndarray,
    by: float,
    kind: str,
    t: float,
) -> None:
    """Broad, deeply cambered/bowed Ardea cinerea wing with slate coverts and dark fingered primaries."""
    if kind == 'glide':
        # Classic heron arched M-wing glide: inner arm angled up, wrist bowed, outer primaries gently drooped!
        flutter = 0.04 * math.sin(t * math.tau)
        a_s = 0.28 + flutter
        a_w = -0.06 + flutter * 0.8
        a_t = -0.34 + flutter * 1.2
        sweep = -0.8
    elif kind == 'takeoff':
        ph = (0.15 + t * 0.85) * math.tau
        a_s = 0.25 + 0.62 * math.sin(ph)
        a_w = 0.12 + 0.80 * math.sin(ph - 0.45)
        a_t = -0.05 + 0.95 * math.sin(ph - 0.90)
        sweep = 1.2
    elif kind == 'land':
        # Upright cupped braking flare!
        flare = 1.0 - 0.35 * t
        a_s = 0.52 * flare + 0.15 * math.sin(t * math.tau)
        a_w = 0.42 * flare + 0.20 * math.sin(t * math.tau - 0.4)
        a_t = 0.22 * flare
        sweep = 2.4 * flare
    else:
        # Slow, deep, bowed cruising wingbeats (fly 0..8)
        ph = t * math.tau
        a_s = 0.16 + 0.50 * math.sin(ph)
        a_w = 0.02 + 0.68 * math.sin(ph - 0.52)
        a_t = -0.20 + 0.86 * math.sin(ph - 1.02)
        sweep = 0.4 * math.cos(ph)

    # Keep total lateral reach <= 25.0 so 64x64 frame never clips on any of the 8 facings!
    L1, L2, L3 = 8.4, 8.2, 5.8
    S = T_fn(side * 2.7, by + 2.0, 1.2)
    E = S + R_body @ np.array([side * L1 * math.cos(a_s), L1 * math.sin(a_s), 1.4 + sweep * 0.3])
    W_pt = E + R_body @ np.array([side * L2 * math.cos(a_w), L2 * math.sin(a_w), -1.1 + sweep * 0.5])
    P = W_pt + R_body @ np.array([side * L3 * math.cos(a_t), L3 * math.sin(a_t), -2.5 + sweep * 0.4])

    # Leading-edge wing bones & patagium
    m.limb(S, E, 1.95, 1.55, MANTLE, step=0.65)
    m.limb(E, W_pt, 1.55, 1.15, MANTLE, step=0.65)
    m.limb(W_pt, P, 1.10, 0.72, BLACK_PLUME, step=0.65)

    # Pale/slate upper wing coverts along inner arm & forearm (characteristic two-tone heron upperwing!)
    for j in range(6):
        u = j / 5.0
        q = S * (1.0 - u) + W_pt * u
        m.ell(q + R_body @ np.array([0.0, -0.25, -1.5]), (1.55, 0.65, 2.35), SCAPULAR if j >= 2 else MANTLE, R=R_body)

    # Broad cambered secondaries (inner trailing fan, slate-grey)
    for j in range(8):
        u = j / 7.0
        q = S * (1.0 - u) + W_pt * u + R_body @ np.array([0.0, -0.2, -1.3])
        droop = -0.8 - 0.35 * math.sin(u * math.pi)
        tip = q + R_body @ np.array([side * (0.4 + 0.15 * j), droop, -(8.6 - 0.45 * j)])
        m.limb(q, tip, 1.25, 0.45, MANTLE if j < 3 else SCAPULAR, step=0.7)

    # Dark slate-black outer primaries (hand-wing + splayed primary fingers!)
    for j in range(8):
        u = j / 7.0
        q = W_pt * (1.0 - u) + P * u
        tip = q + R_body @ np.array([
            side * (1.0 + 2.2 * u),
            -0.35 + 0.45 * math.sin(a_t),
            -(7.8 - 1.65 * u),
        ])
        m.limb(q, tip, 1.05, 0.32, BLACK_PLUME, step=0.65)


def build_heron(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    flying = kind in ('fly', 'glide', 'takeoff', 'land')
    juvenile = (v == 2)

    by = 23.6
    if kind in ('idle', 'one_leg', 'alert'):
        by += 0.20 * b
    elif kind == 'hunch':
        by = 21.4 + 0.15 * b
    elif kind == 'wade':
        by = 23.4 + 0.25 * math.cos(p * 2.0)

    s_pose = 0.0
    hunch = 0.0
    alert_stretch = 0.0
    tuck_rest = 0.0
    turn = 0.0
    fish = False

    if kind == 'one_leg':
        tuck_rest = 1.0
    elif kind == 'hunch':
        hunch = 1.0
    elif kind == 'alert':
        alert_stretch = 1.0
    elif kind == 'strike':
        # Frame 0: coiled drawback; Frames 1..2: lightning harpoon plunge; Frame 3: clamp; Frames 4..5: withdrawal
        idx_s = int(t * 6) % 6
        s_pose = [0.0, 0.82, 1.0, 0.72, 0.32, 0.08][idx_s]
        hunch = [1.0, 0.3, 0.0, 0.25, 0.65, 0.85][idx_s]
    elif kind == 'catch':
        hunch = 0.25
        fish = True
    elif kind == 'preen':
        turn = [0.35, 0.95, 1.0, 0.45][int(t * 4) % 4]
        hunch = 0.35

    pitch = 0.24 - 0.16 * hunch - 0.42 * s_pose + 0.08 * alert_stretch + 0.06 * tuck_rest
    fl = 0.0  # 0 = standing legs, 1 = trailing straight behind in flight

    if flying:
        hunch = 1.0
        if kind == 'fly':
            by = 26.0 + 0.55 * math.sin(p - 0.5)
            pitch = 0.05 + 0.04 * math.sin(p)
            fl = 1.0
        elif kind == 'glide':
            by = 25.8 + 0.15 * b
            pitch = 0.04
            fl = 1.0
        elif kind == 'takeoff':
            by = 19.0 + 7.0 * ease(t)
            pitch = 0.56 - 0.46 * ease(t)
            fl = ease(t * 1.15)
        else:  # land
            by = 26.0 - 2.4 * ease(t)
            pitch = 0.52 - 0.26 * ease(t)
            fl = 1.0 - ease(t * 1.2)

    R_body = art.rot_x(-pitch)
    c_body = np.array([0.0, by, 0.0])

    def T(x: float, y: float, z: float) -> np.ndarray:
        return c_body + R_body @ np.array([x, y - by, z], float)

    # Sculpted multi-ellipsoid teardrop body (seamless dorsal mantle + pale belly/breast + short tail)
    for u_b in (0.0, 0.25, 0.5, 0.75, 1.0):
        bz = -5.8 + 10.6 * u_b
        arch = math.sin(u_b * math.pi)
        rx_b = 2.45 + 0.95 * arch
        ry_b = 2.85 + 1.25 * arch
        m.ell(T(0.0, by + 0.2 * u_b, bz), (rx_b, ry_b, 3.2), MANTLE, R=R_body)
    m.ell(T(0.0, by + 0.35, 4.4), (2.85, 3.55, 3.9), WHITE, R=R_body)
    m.ell(T(0.0, by - 1.15, -8.2), (1.55, 1.05, 2.35), MANTLE, R=R_body)

    # Loose lanceolate white/silvery breast plumes hanging from lower neck
    for j in range(5):
        px_x = (j - 2) * 0.72
        m.limb(
            T(px_x, by + 1.5, 6.1),
            T(px_x * 1.18, by - 3.6 - (j % 2) * 1.1, 5.8 - abs(j - 2) * 0.28),
            0.62, 0.18, WHITE if j % 2 == 0 else SCAPULAR, step=0.52,
        )

    # Long silvery scapular plumes draped along the back
    for side in (-1.0, 1.0):
        for j in range(2):
            m.limb(
                T(side * (1.45 + j * 0.48), by + 3.25 - j * 0.28, 0.2 - j * 0.9),
                T(side * (1.15 + j * 0.30), by + 0.55 - j * 0.45, -10.6 - j * 1.1),
                0.62, 0.16, SCAPULAR, step=0.58,
            )

    # Graceful S-curved neck (white foreneck + pale grey hindneck + dark dotted throat streak)
    shoulder = T(0.0, by + 1.9, 5.2)
    head_idle = np.array([0.0, by + 17.2, 7.2])
    head_tuck = np.array([0.0, by + 8.6, 5.8])
    head_hunch = np.array([0.0, by + 5.8, 8.6])
    head_alert = np.array([0.0, by + 22.2, 5.6])
    head_strike = np.array([0.0, 8.2, 19.8])

    head = lerp(head_idle, head_tuck, tuck_rest)
    head = lerp(head, head_hunch, hunch)
    head = lerp(head, head_alert, alert_stretch)
    head = lerp(head, head_strike, s_pose)

    ctrl_idle = np.array([0.0, by + 12.2, 0.6])
    ctrl_tuck = np.array([0.0, by + 5.6, 0.2])
    ctrl_hunch = np.array([0.0, by + 7.2, -0.8])
    ctrl_alert = np.array([0.0, by + 14.5, 3.2])
    ctrl_strike = np.array([0.0, 15.0, 11.5])

    ctrl = lerp(ctrl_idle, ctrl_tuck, tuck_rest)
    ctrl = lerp(ctrl, ctrl_hunch, hunch)
    ctrl = lerp(ctrl, ctrl_alert, alert_stretch)
    ctrl = lerp(ctrl, ctrl_strike, s_pose)

    if kind == 'catch':
        idx_c = int(t * 4) % 4
        toss = [0.0, 0.3, 1.0, 0.4][idx_c]
        head = np.array([0.0, by + 13.5 + 3.2 * toss, 7.6 - 1.2 * toss])
        ctrl = np.array([0.0, by + 9.5 + 1.5 * toss, 1.2])
    elif turn > 0.0:
        head = lerp(head_idle, np.array([2.8, by + 10.5, -1.6]), turn)
        ctrl = lerp(ctrl_idle, np.array([1.2, by + 12.0, 0.5]), turn)
    elif kind == 'wade':
        head = head + np.array([0.0, 0.35 * math.sin(p * 2.0), 0.55 * math.sin(p)])
    elif flying:
        # Authentic Ardea cinerea retracted thick S-neck in flight!
        head = T(0.0, by + 3.2, 9.2)
        ctrl = T(0.0, by + 7.2, 3.8)

    neck_end = head - np.array([0.0, 0.0, 1.2]) if turn < 0.2 else head
    neck_pts = bez2(shoulder, ctrl, neck_end, n=16)
    r_n0 = 1.85 if not flying else 2.05
    r_n1 = 1.08
    for i in range(len(neck_pts) - 1):
        a = i / (len(neck_pts) - 1)
        b_u = (i + 1) / (len(neck_pts) - 1)
        m.limb(neck_pts[i], neck_pts[i + 1], r_n0 + (r_n1 - r_n0) * a, r_n0 + (r_n1 - r_n0) * b_u, WHITE, step=0.45)

    # Characteristic dark dashed foreneck streak
    for i in range(2, 14, 2):
        m.ell(neck_pts[i] + np.array([0.0, -0.1, 0.95 if turn < 0.3 else -0.6]), (0.34, 0.52, 0.34), BLACK_PLUME)

    # Flat-crowned head, black superciliary band & twin trailing black crest plumes!
    yaw_h = -1.25 * turn if turn > 0.0 else 0.0
    pitch_h = 0.0
    if s_pose > 0.35:
        pitch_h = 0.52 * s_pose
    elif kind == 'catch' and int(t * 4) % 4 == 2:
        pitch_h = -0.35
    elif tuck_rest > 0.5:
        pitch_h = 0.14
    R_head = art.rot_y(yaw_h) @ art.rot_x(pitch_h)

    def HP(x: float, y: float, z: float) -> np.ndarray:
        return head + R_head @ np.array([x, y, z], float)

    m.ell(HP(0.0, 0.0, 0.0), (1.62, 1.48, 2.45), WHITE, R=R_head)
    m.ell(HP(0.0, -0.48, 0.85), (1.18, 0.86, 1.65), WHITE, R=R_head)

    blink = (kind in ('idle', 'one_leg') and t >= 0.75)
    crest_len = 5.2 if juvenile else 8.4
    crest_lift = 0.85 if alert_stretch > 0.5 else 0.0

    for side in (-1.0, 1.0):
        # Jet-black eye-to-nape superciliary stripe + twin ornamental crest plumes
        m.ell(HP(side * 1.25, 0.58, 0.15), (0.38, 0.52, 1.85), BLACK_PLUME, R=R_head)
        if not juvenile:
            m.limb(HP(side * 0.52, 1.02, -1.1), HP(side * 0.68, -0.25 + crest_lift, -crest_len), 0.56, 0.16, BLACK_PLUME, step=0.48)
        m.limb(HP(side * 0.35, 0.82, -1.0), HP(side * 0.25, -1.15 + crest_lift * 0.7, -(crest_len - 1.6)), 0.45, 0.15, BLACK_PLUME, step=0.48)

        # Sharp pale-amber iris + dark pupil
        m.ell(HP(side * 1.38, 0.50, 1.28), (0.32, 0.14 if blink else 0.38, 0.38), EYE_IRIS, R=R_head)
        if not blink:
            m.ell(HP(side * 1.46, 0.52, 1.42), (0.16, 0.18, 0.18), BLACK_PLUME, R=R_head)

    # Long sharp muted-ochre dagger bill (slightly parted during strike & fish catch!)
    jaw_open = (kind == 'strike' and s_pose > 0.45) or (kind == 'catch' and int(t * 4) % 4 < 3)
    bill_base = HP(0.0, -0.32, 1.65)
    bill_tip = HP(0.0, -0.65, 9.65)
    m.limb(bill_base, bill_tip, 0.86, 0.22, BILL, step=0.42)
    # Dusky culmen ridge along top of upper mandible
    m.limb(HP(0.0, -0.05, 1.8), HP(0.0, -0.45, 8.6), 0.38, 0.18, LEGS, step=0.45)
    if jaw_open:
        m.limb(HP(0.0, -0.62, 1.75), HP(0.0, -1.65, 8.85), 0.58, 0.18, BILL, step=0.45)

    # Caught silver brook fish clamped in bill (catch cols 26..29)!
    if fish:
        idx_c = int(t * 4) % 4
        if idx_c < 3:
            fish_mid = HP(0.0, -1.1, 6.8 if idx_c < 2 else 4.5)
            m.limb(fish_mid + R_head @ np.array([-2.6, -0.8, 0.0]), fish_mid + R_head @ np.array([2.8, 0.6, 0.2]), 0.82, 0.52, SCAPULAR, step=0.42)
            m.ell(fish_mid + R_head @ np.array([3.2, 0.8, 0.2]), (0.35, 0.85, 0.55), MANTLE, R=R_head)
        else:
            # Throat bulge as fish is swallowed!
            m.ell(neck_pts[11], (1.55, 1.55, 1.65), WHITE)

    # Folded wings at rest vs. broad bowed wings in flight
    for side in (-1.0, 1.0):
        if not flying:
            m.ell(T(side * 3.15, by + 0.35, -0.9), (1.22, 3.55, 7.2), MANTLE, R=R_body @ art.rot_x(-0.06))
            # Signature jet-black carpal shoulder patch (Bugfleck)!
            m.ell(T(side * 3.45, by + 1.35, 2.75), (0.82, 1.25, 1.85), BLACK_PLUME, R=R_body)
            for j in range(4):
                m.limb(
                    T(side * (2.95 - j * 0.15), by - 1.35 + j * 0.24, -3.8 - j * 0.75),
                    T(side * (2.10 - j * 0.55), by - 3.25 + j * 0.20, -12.0 - j * 1.0),
                    0.78, 0.24, BLACK_PLUME if j % 2 == 0 else SCAPULAR, step=0.55,
                )
        else:
            draw_heron_wing(m, side, T, R_body, by, kind, t)

    # Long articulated olive-slate wading legs (white feathered tibia top -> tibiotarsal joint -> tarsus -> spread toes)
    for side in (-1.0, 1.0):
        # In one_leg rest, tuck the right leg (side > 0) snugly up into belly feathers!
        if kind == 'one_leg' and side > 0:
            hip_t = np.array([side * 1.55, by - 2.8, -0.8])
            m.ell(hip_t + np.array([0.0, -0.8, 1.2]), (1.35, 1.45, 2.0), WHITE)
            continue

        swing = 0.0
        lift = 0.0
        toe_curl = 0.0
        if kind == 'wade':
            # Deliberate slow-motion stalker wade: high knee/ankle lift, curled toes on lift, flat placement
            ph_w = (t + (0.5 if side > 0 else 0.0)) % 1.0
            stance = 0.58
            if ph_w < stance:
                c_w = ph_w / stance
                swing = 3.8 * (1.0 - 2.0 * c_w)
            else:
                c_w = (ph_w - stance) / (1.0 - stance)
                swing = -3.8 * math.cos(c_w * math.pi)
                lift = math.sin(c_w * math.pi) * 6.8
                toe_curl = math.sin(c_w * math.pi)

        hip = np.array([side * (0.35 if kind == 'one_leg' else 1.55), by - 2.8, -1.1])
        ankle_stand = np.array([hip[0], 11.2 + lift * 0.72, -2.2 + swing * 0.52 - lift * 0.18])
        foot_stand = np.array([hip[0], 0.55 + lift, -0.6 + swing])

        # Trailing straight behind body in flight (clearly extending past tail & secondaries)!
        ankle_fly = T(side * 1.15, by - 3.6, -13.8)
        foot_fly = T(side * 1.05, by - 5.2, -24.2)

        ankle = lerp(ankle_stand, ankle_fly, fl)
        foot = lerp(foot_stand, foot_fly, fl)

        # Feathered white drumstick/thigh -> prominent tibiotarsal joint -> slender olive-slate tarsus
        upper_mid = lerp(hip, ankle, 0.42)
        m.limb(hip, upper_mid, 1.55, 1.02, WHITE, step=0.48)
        m.limb(upper_mid, ankle, 0.96, 0.68, LEGS, step=0.45)
        m.ell(ankle, (0.78, 0.78, 0.82), LEGS)
        m.limb(ankle, foot, 0.68, 0.56, LEGS, step=0.42)

        # Three spread front toes + hind hallux (folded backward/down when lifted in wade or trailing in flight)
        for ang in (-0.36, 0.0, 0.36):
            if fl > 0.5:
                toe_end = foot + R_body @ np.array([math.sin(ang) * 0.7, -0.25, -3.2])
            elif toe_curl > 0.25:
                toe_end = foot + np.array([math.sin(ang) * 1.4, -1.6 * toe_curl, 2.2 * (1.0 - 0.5 * toe_curl)])
            else:
                toe_end = foot + np.array([math.sin(ang) * 2.1, -0.15, math.cos(ang) * 3.4])
            m.limb(foot, toe_end, 0.48, 0.30, LEGS, step=0.38)
        if fl <= 0.5 and toe_curl <= 0.25:
            m.limb(foot, foot + np.array([0.0, -0.15, -2.0]), 0.44, 0.28, LEGS, step=0.38)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_heron(v, kind, (col - start) / n)
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
        (6, 0),   # N idle
        (1, 5),   # SE one-leg tucked rest!
        (0, 9),   # E coiled hunch
        (0, 15),  # E high-stepping wade
        (0, 22),  # E lightning harpoon strike!
        (0, 26),  # E fish clamped in bill!
        (0, 31),  # E chest preen
        (1, 35),  # SE tall alert stretched neck!
        (1, 40),  # SE fly upstroke
        (1, 44),  # SE fly downstroke
        (2, 47),  # S arched M-wing glide!
        (0, 56),  # E upright braking flare land!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([38, 52, 58, 255], np.uint8)
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
                print(f'heron build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/heron.png', sheet)
    print('Saved assets/wildlife/heron.png', sheet.shape)


if __name__ == '__main__':
    main()
