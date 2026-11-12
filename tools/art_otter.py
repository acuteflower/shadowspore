#!/usr/bin/env python3
"""Eurasian River Otter / Eurasischer Fischotter (Lutra lutra) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet/waterline at (32, 52); 58 columns; 3 builds x 8 facings = 24 rows (3712x1536).
No emissive parts; natural glossy river-mustelid palettes.

Builds:
  0: Eurasischer Flussotter (glossy wet rich chestnut-chocolate coat, warm cream throat/cheeks/whiskers)
  1: Dunkler Bachotter (sleek dark espresso-slate coat, silvery-cream chin & whiskers)
  2: Jungotter (0.82x scale anchored on GROUND_ROW = 52.0, warmer cocoa-brown coat, playful proportions)

Columns (58):
  idle 0:4, float_idle 4:8, periscope 8:12, land_bound 12:20, swim 20:28,
  dive_plunge 28:34, groom 34:38, surface_catch 38:44, back_feast 44:52, sun_sleep 52:58.

Usage: py -3 tools/art_otter.py [--preview-only] [--qa=path.png]
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

COAT, CREAM, DARK, NOSE_EYE, SILVER_FISH, FISH_ACCENT = range(6)

BLOCKS = [
    ('idle', 0, 4),
    ('float_idle', 4, 4),
    ('periscope', 8, 4),
    ('land_bound', 12, 8),
    ('swim', 20, 8),
    ('dive_plunge', 28, 6),
    ('groom', 34, 4),
    ('surface_catch', 38, 6),
    ('back_feast', 44, 8),
    ('sun_sleep', 52, 6),
]

WATER_KINDS = {'float_idle', 'periscope', 'swim', 'dive_plunge', 'surface_catch', 'back_feast'}


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        NOSE_EYE: 3.6,
        SILVER_FISH: 3.0,
        FISH_ACCENT: 2.2,
        CREAM: 1.35,
        DARK: 1.30,
    }
    art.ink_color = lambda mat: hexc('0d0b12' if mat in (DARK, NOSE_EYE) else '1c1418')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def bezier3(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, u: float) -> np.ndarray:
    v = 1.0 - u
    return (v ** 3) * p0 + 3.0 * (v ** 2) * u * p1 + 3.0 * v * (u ** 2) * p2 + (u ** 3) * p3


def _cut_waterline(prims: list[art.Prim]) -> None:
    """Clip primitives cleanly at the 3D horizontal water surface y >= 0.0 (GROUND_ROW = 52.0)."""
    for p in prims:
        old = p.clip

        def clip(q, p=p, old=old):
            y = p.c[1] + ((q * p.r) @ p.R.T)[..., 1]
            ok = y >= 0.0
            return (ok & old(q)) if old is not None else ok

        p.clip = clip


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Eurasischer Flussotter: glossy wet rich chestnut-chocolate coat, warm cream throat/whiskers
        coat = ['26150f', '4c2c1d', '7a4b32', 'ad7452']
        cream = ['786654', 'a69079', 'd4c1aa', 'f5ead8']
        dark = ['140c0a', '291a15', '452e26', '66483d']
    elif v == 1:
        # 1 Dunkler Bachotter: sleek dark espresso-slate coat, silvery-cream chin & whiskers
        coat = ['16141b', '2c2834', '4d4658', '776e85']
        cream = ['6e707a', '9b9ea8', 'cacdd6', 'f0f2f7']
        dark = ['0c0b10', '1a1822', '2e2b3b', '474359']
    else:
        # 2 Jungotter: warmer cocoa-brown coat, soft biscuit-cream throat
        coat = ['331d14', '5e3824', '915b3c', 'c4855e']
        cream = ['826e5a', 'b09980', 'decab2', 'faefe0']
        dark = ['1c110d', '36221a', '57392d', '7a5444']

    ramps = [
        coat,                                               # 0 COAT
        cream,                                              # 1 CREAM (whisker pads, chin, throat, chest/belly)
        dark,                                               # 2 DARK (webbed paws, dorsal fish back)
        ['09080e', '16131d', '282232', '3e364c'],           # 3 NOSE_EYE (wet nose & dark mustelid eyes)
        ['4f6d82', '7fa3bd', 'b6daef', 'f0faff'],           # 4 SILVER_FISH (gleaming silver-blue brook trout + glint + whiskers)
        ['6e3532', '9e524b', 'cc7a6e', 'ebb0a4'],           # 5 FISH_ACCENT (trout rosy lateral band & mouth gape)
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_brook_fish(
    m: art.Model,
    center: np.ndarray,
    R_fish: np.ndarray,
    sz: float,
    wiggle: float = 0.0,
) -> None:
    """Gleaming silver brook trout (head along +x of R_fish, forked tail along -x of R_fish)."""
    def fp(x: float, y: float, z: float) -> np.ndarray:
        return center + R_fish @ (np.array([x, y, z], float) * sz)

    # Plump silver-blue fusiform brook fish body
    m.ell(fp(0.65, 0.0, 0.0), (3.10 * sz, 1.12 * sz, 0.88 * sz), SILVER_FISH, R=R_fish)
    # Dark slate-olive dorsal trout back for crisp contrast against pale fur!
    m.ell(fp(0.65, 0.58, 0.0), (2.65 * sz, 0.54 * sz, 0.68 * sz), DARK, R=R_fish)
    # Rosy-salmon lateral trout flash
    for sz_s in (-0.38, 0.38):
        m.ell(fp(1.15, -0.08, sz_s), (1.45 * sz, 0.48 * sz, 0.52 * sz), FISH_ACCENT, R=R_fish)
        m.ell(fp(2.65, 0.20, sz_s * 1.25), (0.32 * sz, 0.32 * sz, 0.32 * sz), NOSE_EYE, R=R_fish)

    # Tapering caudal peduncle + crisp splayed forked tail fin!
    ped = fp(-2.15, 0.0, wiggle * 0.55)
    m.limb(fp(-0.85, 0.0, 0.0), ped, 0.88 * sz, 0.52 * sz, SILVER_FISH, step=0.38)
    fin_up = fp(-4.05, 1.18, wiggle * 1.35)
    fin_lo = fp(-4.05, -1.12, wiggle * 1.35)
    m.limb(ped, fin_up, 0.48 * sz, 0.30 * sz, SILVER_FISH, step=0.35)
    m.limb(ped, fin_lo, 0.48 * sz, 0.30 * sz, SILVER_FISH, step=0.35)


def draw_otter_head(
    m: art.Model,
    head_c: np.ndarray,
    R_head: np.ndarray,
    sz: float,
    pup_scale: float,
    jaw_open: float = 0.0,
    blink: bool = False,
) -> None:
    """Broad dorsoventrally flattened mustelid otter head, tiny low-set ears, cream whisker pads & whiskers."""
    hs = sz * pup_scale

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + R_head @ (np.array([x, y, z], float) * hs)

    # Broad flattened otter skull
    m.ell(hp(0.0, 0.05, 0.0), (2.52 * hs, 1.80 * hs, 2.78 * hs), COAT, R=R_head)
    # Cream chin, cheeks & lower jaw throat transition
    m.ell(hp(0.0, -0.74, 0.35), (2.10 * hs, 1.02 * hs, 2.28 * hs), CREAM, R=R_head)

    # Tiny low-set rounded mustelid ears (hallmark of Lutra lutra!)
    for side in (-1.0, 1.0):
        m.ell(hp(side * 2.22, 0.32, -0.68), (0.54 * hs, 0.60 * hs, 0.54 * hs), COAT, R=R_head)
        m.ell(hp(side * 2.32, 0.30, -0.52), (0.30 * hs, 0.34 * hs, 0.30 * hs), DARK, R=R_head)

    # Broad snout bridge + twin plump pale cream whisker cushions ("Schnurrhaarkissen")!
    m.ell(hp(0.0, 0.02, 2.15), (1.72 * hs, 1.15 * hs, 1.48 * hs), COAT, R=R_head)
    for side in (-1.0, 1.0):
        m.ell(hp(side * 0.90, -0.32, 2.68), (1.06 * hs, 0.85 * hs, 1.18 * hs), CREAM, R=R_head)

    # Stiff pale tactile otter whiskers fanning out from muzzle cushions!
    for side in (-1.0, 1.0):
        for wi, wy in enumerate((-0.16, -0.46)):
            w_root = hp(side * 1.45, wy, 2.88 - wi * 0.25)
            w_tip = hp(side * (3.42 + wi * 0.25), wy - 0.32 - wi * 0.16, 2.35 - wi * 0.45)
            m.limb(w_root, w_tip, 0.24 * hs, 0.17 * hs, SILVER_FISH if wi == 0 else CREAM, step=0.35)

    # Lower jaw
    lo_rot = R_head @ art.rot_x(0.55 * jaw_open)
    lo_base = hp(0.0, -0.68, 1.35)
    lo_tip = lo_base + lo_rot @ (np.array([0.0, -0.08, 1.88]) * hs)
    m.limb(lo_base, lo_tip, 0.98 * hs, 0.64 * hs, CREAM, step=0.4)
    if jaw_open > 0.12:
        mouth_in = lo_base + lo_rot @ (np.array([0.0, 0.22, 1.15]) * hs)
        m.ell(mouth_in, (0.70 * hs, 0.36 * hs, 0.74 * hs), FISH_ACCENT, R=lo_rot)

    # Broad dark diamond nose pad at tip of snout
    m.ell(hp(0.0, 0.06, 3.58), (0.70 * hs, 0.54 * hs, 0.54 * hs), NOSE_EYE, R=R_head)

    # High-set dark glossy otter eyes + wet catchlight
    for side in (-1.0, 1.0):
        eh = 0.16 if blink else 0.54
        m.ell(hp(side * 1.40, 0.60, 1.58), (0.48 * hs, eh * hs, 0.54 * hs), NOSE_EYE, R=R_head)
        if not blink:
            m.ell(hp(side * 1.50, 0.76, 1.82), (0.22 * hs, 0.22 * hs, 0.22 * hs), SILVER_FISH, R=R_head)


def draw_spine_and_tail(
    m: art.Model,
    spine_pts: list[np.ndarray],
    tail_pts: list[np.ndarray],
    sz: float,
    belly_up: bool = False,
) -> None:
    """Seamless hydrodynamic cylindrical otter body (COAT + ventral CREAM band) & thick tapered rudder tail."""
    radii_x = [2.28, 2.58, 2.80, 2.82, 2.72, 2.48, 2.25]
    radii_y = [2.18, 2.46, 2.62, 2.66, 2.56, 2.32, 2.08]

    n_sp = len(spine_pts)
    for i in range(n_sp):
        u = i / (n_sp - 1)
        pt = spine_pts[i]
        rx = np.interp(u, np.linspace(0.0, 1.0, len(radii_x)), radii_x) * sz
        ry = np.interp(u, np.linspace(0.0, 1.0, len(radii_y)), radii_y) * sz
        if i < n_sp - 1:
            tang = spine_pts[i + 1] - spine_pts[i]
        else:
            tang = spine_pts[i] - spine_pts[i - 1]
        tnorm = np.linalg.norm(tang)
        fwd = tang / max(tnorm, 1e-6)
        hint_up = np.array([0.0, -1.0, 0.0]) if belly_up else np.array([0.0, 1.0, 0.0])
        right = np.cross(hint_up, fwd)
        if np.linalg.norm(right) < 1e-5:
            right = np.cross(np.array([0.0, 0.0, -1.0]), fwd)
        right = right / max(np.linalg.norm(right), 1e-6)
        up_vec = np.cross(fwd, right)
        R_seg = np.stack([right, up_vec, fwd], axis=1)

        seg_len = max(2.15 * sz, tnorm * 0.92)
        m.ell(pt, (rx, ry, seg_len), COAT, R=R_seg)

        # Continuous cream throat/chest/belly band along ventral (-up_vec) surface!
        if u >= 0.16:
            belly_w = rx * (0.76 if u < 0.65 else 0.84)
            belly_off = -up_vec * (ry * 0.54)
            m.ell(pt + belly_off, (belly_w, ry * 0.62, seg_len * 0.92), CREAM, R=R_seg)

    # Long, thick, muscular tapered rudder tail
    n_tl = len(tail_pts)
    for i in range(n_tl - 1):
        u0 = i / (n_tl - 1)
        u1 = (i + 1) / (n_tl - 1)
        r0 = (2.20 * (1.0 - 0.78 * (u0 ** 0.85))) * sz
        r1 = (2.20 * (1.0 - 0.78 * (u1 ** 0.85))) * sz
        m.limb(tail_pts[i], tail_pts[i + 1], max(0.44 * sz, r0), max(0.40 * sz, r1), COAT, step=0.45)


def draw_webbed_leg(
    m: art.Model,
    hip: np.ndarray,
    knee: np.ndarray,
    paw: np.ndarray,
    sz: float,
    paw_rot: np.ndarray | None = None,
    splay_paddle: bool = False,
) -> None:
    """Short sturdy muscular otter limb + dark broad five-toed webbed paddle paw."""
    m.limb(hip, knee, 1.56 * sz, 1.18 * sz, COAT, step=0.42)
    m.limb(knee, paw, 1.12 * sz, 0.86 * sz, COAT, step=0.40)
    R_p = np.eye(3) if paw_rot is None else paw_rot
    if splay_paddle:
        m.ell(paw, (1.34 * sz, 0.60 * sz, 1.62 * sz), DARK, R=R_p)
        for ti in (-1.0, 0.0, 1.0):
            toe_end = paw + R_p @ (np.array([ti * 0.82, 0.15, 1.30]) * sz)
            m.limb(paw, toe_end, 0.44 * sz, 0.32 * sz, DARK, step=0.35)
    else:
        m.ell(paw, (1.16 * sz, 0.64 * sz, 1.46 * sz), DARK, R=R_p)


def build_otter(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    # Adult river otter = 1.18, Build 2 Jungotter = 0.82 * 1.18 (strictly 0.82x adult scale, anchored at GROUND_ROW = 52.0!)
    base_sz = 1.18
    sz = base_sz * (0.82 if v == 2 else 1.0)
    pup_scale = 1.09 if v == 2 else 1.0
    p = t * math.tau
    bob = math.sin(p)

    # Shift longitudinal center +1.4 so long rudder tail & snout stay symmetrically centered inside 64x64!
    z_off = 1.4 if kind in ('idle', 'float_idle', 'land_bound', 'swim', 'back_feast') else 0.0

    def S(x: float, y: float, z: float) -> np.ndarray:
        return np.array([x * sz, y * sz, (z + z_off) * sz], float)

    if kind == 'idle':
        # Low sinuous bank stance, whiskers & thick rudder tail sway
        idx = int(round(t * 4)) % 4
        sway = 0.90 * math.sin(p)
        breathe = 0.16 * bob
        p0, p1, p2, p3 = (
            S(0.0, 4.4, -6.2),
            S(0.0, 5.5 + breathe, -1.8),
            S(0.0, 4.3 + breathe, 3.2),
            S(0.0, 5.9 + breathe, 7.6),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = (
            p0,
            S(sway * 0.4, 2.6, -9.8),
            S(sway * 1.1, 1.1, -13.2),
            S(sway * 1.6, 0.85, -16.4),
        )
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz)

        for side in (-1.0, 1.0):
            draw_webbed_leg(m, S(side * 1.9, 4.1, -5.4), S(side * 2.2, 2.3, -6.2), S(side * 2.1, 0.62, -4.6), sz)
            draw_webbed_leg(m, S(side * 1.8, 4.0, 4.6), S(side * 2.0, 2.2, 4.2), S(side * 1.95, 0.62, 5.6), sz)

        R_h = art.rot_y(0.16 * math.sin(p)) @ art.rot_x(-0.06)
        draw_otter_head(m, S(0.0, 6.8 + breathe, 9.5), R_h, sz, pup_scale, blink=(idx == 3))

    elif kind == 'float_idle':
        # Floating low in water: only wet head, upper mid-back arch, and rudder tail tip emerge cleanly above y=0!
        sway = 1.25 * math.sin(p)
        bob_w = 0.18 * bob
        p0, p1, p2, p3 = (
            S(0.0, -3.4 + bob_w, -6.5),
            S(0.0, 0.65 + bob_w, -1.5),   # Upper back arch crests just above y=0 (with ry~2.6 -> top at +3.2)!
            S(0.0, -4.2 + bob_w, 3.5),    # Neck saddle dips cleanly underwater between back arch & head!
            S(0.0, -0.4 + bob_w, 7.6),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = (
            p0,
            S(sway * 0.4, -3.6 + bob_w, -9.8),  # Submerged tail base!
            S(sway * 0.9, -0.8 + bob_w, -13.0),
            S(sway * 1.4, 1.35 + bob_w, -15.8), # Emergent sculling rudder tail tip!
        )
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz)

        R_h = art.rot_y(0.14 * math.sin(p)) @ art.rot_x(-0.10)
        draw_otter_head(m, S(0.0, 1.45 + bob_w, 9.5), R_h, sz, pup_scale)

    elif kind == 'periscope':
        # Curious upright water periscope: head, long sleek neck & cream chest raised high vertically above waterline!
        idx = int(round(t * 4)) % 4
        bob_w = 0.30 * bob
        look_yaw = [0.0, 0.48, -0.08, -0.48][idx]
        look_roll = [0.0, 0.10, 0.0, -0.10][idx]

        p0, p1, p2, p3 = (
            S(0.0, -4.5, -2.6),
            S(0.0, 1.5 + bob_w, 0.4),
            S(0.0, 9.0 + bob_w, 1.3),
            S(0.0, 15.6 + bob_w, 0.9),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = (
            p0,
            S(0.0, -3.5, -6.2),
            S(0.4 * bob, -0.6, -10.0),
            S(0.7 * bob, 1.10, -13.0),
        )
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 6)]
        draw_spine_and_tail(m, spine, tail, sz)

        for side in (-1.0, 1.0):
            sh = S(side * 2.1, 8.8 + bob_w, 1.2)
            el = S(side * 2.5, 6.9 + bob_w, 2.2)
            pw = S(side * 1.35, 6.1 + bob_w, 3.4)
            draw_webbed_leg(m, sh, el, pw, sz, paw_rot=art.rot_x(0.65))

        R_h = art.rot_y(look_yaw) @ art.rot_x(-0.04) @ rot_z(look_roll)
        draw_otter_head(m, S(0.0, 17.6 + bob_w, 1.4), R_h, sz, pup_scale)

    elif kind == 'land_bound':
        # 8-frame supple arched-back mustelid bound ("Buckelsprung") on shore/rocks!
        arch = 0.5 - 0.5 * math.cos((t - 0.08) * math.tau)
        leap = max(0.0, math.sin((t + 0.15) * math.tau))

        rz_pelvis = -7.0 + 3.4 * arch
        fz_chest = 6.8 - 1.8 * arch
        pelvis_y = 4.5 + 1.6 * arch + 1.2 * leap
        mid_y = 4.6 + 5.4 * arch + 1.4 * leap
        chest_y = 4.8 + 0.8 * arch + 2.4 * leap

        p0 = S(0.0, pelvis_y, rz_pelvis)
        p1 = S(0.0, mid_y + 0.8 * arch, 0.5 * (rz_pelvis + fz_chest) - 1.5)
        p2 = S(0.0, mid_y, 0.5 * (rz_pelvis + fz_chest) + 1.8)
        p3 = S(0.0, chest_y + 1.2, fz_chest)
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]

        t_wave = math.sin(p - 0.8)
        t0 = p0
        t1 = S(0.0, pelvis_y - 1.2 + 1.2 * t_wave, rz_pelvis - 3.5)
        t2 = S(0.0, max(1.1, 2.2 - 1.2 * t_wave), rz_pelvis - 7.0)
        t3 = S(0.0, max(0.9, 1.8 + 1.4 * math.cos(p)), rz_pelvis - 10.2)
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz)

        for s_i, side in enumerate((-1.0, 1.0)):
            lead = 0.06 * s_i
            f_ph = (t + lead) % 1.0
            f_z = fz_chest + 2.8 * math.cos(f_ph * math.tau) - 0.8
            f_y = 0.65 + max(0.0, math.sin((f_ph + 0.22) * math.tau)) * 2.8
            draw_webbed_leg(
                m,
                S(side * 1.85, chest_y + 0.2, fz_chest - 1.2),
                S(side * 2.05, 0.5 * (chest_y + f_y) + 0.4, 0.5 * (fz_chest + f_z) - 0.6),
                S(side * 1.95, f_y, f_z),
                sz,
            )
            h_ph = (t + lead + 0.48) % 1.0
            h_z = rz_pelvis + 3.4 * math.cos(h_ph * math.tau) + 0.8
            h_y = 0.65 + max(0.0, math.sin((h_ph + 0.20) * math.tau)) * 2.8
            draw_webbed_leg(
                m,
                S(side * 1.95, pelvis_y - 0.2, rz_pelvis + 0.8),
                S(side * 2.25, 0.5 * (pelvis_y + h_y) + 0.5, 0.5 * (rz_pelvis + h_z) - 0.8),
                S(side * 2.10, h_y, h_z),
                sz,
            )

        h_pitch = -0.14 + 0.22 * arch - 0.12 * leap
        draw_otter_head(m, S(0.0, chest_y + 2.1, fz_chest + 2.0), art.rot_x(h_pitch), sz, pup_scale)

    elif kind == 'swim':
        # 8-frame sleek serpentine river surface swim: pronounced horizontal S-wave low at waterline, limbs tucked!
        spine = []
        for i in range(9):
            u = i / 8.0
            z_s = -6.6 + 14.4 * u  # -6.6 .. +7.8
            amp = 2.95 - 1.85 * u
            sx = amp * math.sin(u * 4.4 - p)
            sy = -0.35 + 0.65 * math.sin(u * math.pi * 1.3) + 0.45 * u
            spine.append(S(sx, sy, z_s))

        tail = []
        for i in range(7):
            v_u = i / 6.0
            u_eff = -0.76 * v_u
            z_t = -6.6 - 10.0 * v_u  # -6.6 .. -16.6
            amp_t = 2.95 + 2.15 * v_u
            tx = amp_t * math.sin(u_eff * 4.4 - p)
            ty = 0.35 + 0.15 * v_u + 0.25 * math.cos(v_u * 2.5 - p)
            tail.append(S(tx, ty, z_t))

        draw_spine_and_tail(m, spine, tail, sz)

        head_x = 1.05 * math.sin(4.4 - p)
        head_yaw = 0.32 * math.cos(4.4 - p)
        draw_otter_head(m, S(head_x, 1.55, 9.6), art.rot_y(head_yaw) @ art.rot_x(-0.08), sz, pup_scale)

    elif kind == 'dive_plunge':
        # 6-frame porpoising arc up out of water & plunging nose-first downward into water!
        idx = int(round(t * 6)) % 6
        arcs = [
            # 0: Surging chest-first upward out of river
            ((-5.6, -0.8), (-2.0, 2.2), (1.8, 5.2), (5.0, 7.8), (-9.2, -1.8), (-13.0, -0.5), (6.6, 9.6, -0.48)),
            # 1: High upward porpoise leap clear of surface!
            ((-5.0, 3.6), (-1.4, 8.2), (2.4, 11.4), (5.8, 13.0), (-8.5, 1.2), (-12.2, -0.2), (7.6, 14.0, -0.18)),
            # 2: Rainbow apex of porpoise arc, nose curving downward toward water!
            ((-4.4, 7.8), (-0.8, 12.8), (3.0, 12.6), (6.2, 9.2), (-7.8, 4.5), (-11.4, 1.8), (7.6, 7.2, 0.58)),
            # 3: Nose-first plunge! Head/neck submerged (<0, clipped!), arched back & tail high!
            ((-2.6, 9.6), (0.8, 10.2), (3.5, 4.8), (5.2, -2.2), (-6.0, 8.8), (-9.2, 6.8), (6.0, -5.2, 1.15)),
            # 4: Torso submerged, hindquarters slipping under & thick rudder tail raised steeply!
            ((0.5, 2.8), (2.2, -1.8), (3.6, -5.5), (4.8, -8.5), (-1.6, 7.8), (-3.4, 12.6), (5.5, -10.5, 1.35)),
            # 5: Sleek tapered tail tip vanishing cleanly downward into the river!
            ((2.0, -3.8), (3.0, -6.5), (4.0, -8.5), (4.8, -10.0), (1.0, 1.2), (0.2, 5.8), (5.2, -11.5, 1.40)),
        ]
        (z0, y0), (z1, y1), (z2, y2), (z3, y3), (tz1, ty1), (tz3, ty3), (hz, hy, hpitch) = arcs[idx]
        p0, p1, p2, p3 = S(0.0, y0, z0), S(0.0, y1, z1), S(0.0, y2, z2), S(0.0, y3, z3)
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0 = p0
        tm1 = S(0.0, 0.5 * (y0 + ty1), 0.5 * (z0 + tz1))
        tm2 = S(0.0, ty1, tz1)
        t3 = S(0.0, ty3, tz3)
        tail = [bezier3(t0, tm1, tm2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz)

        if idx in (1, 2, 3):
            for side in (-1.0, 1.0):
                if y3 > 1.5:
                    m.limb(S(side * 1.9, y2 - 1.2, z2), S(side * 1.8, y2 - 2.4, z2 - 2.2), 1.15 * sz, 0.82 * sz, DARK, step=0.45)
                if y0 > 1.5:
                    m.limb(S(side * 2.0, y0 - 0.8, z0), S(side * 1.8, y0 - 1.8, z0 - 2.6), 1.25 * sz, 0.85 * sz, DARK, step=0.45)

        if hy > -3.5:
            draw_otter_head(m, S(0.0, hy, hz), art.rot_x(hpitch), sz, pup_scale)

    elif kind == 'groom':
        # 4-frame seated on riverbank vigorously rubbing cheeks/chest fur with forepaws!
        idx = int(round(t * 4)) % 4
        scrub = [1.0, -1.0, 0.8, -0.8][idx]
        p0, p1, p2, p3 = (
            S(0.0, 2.5, -2.6),
            S(0.0, 5.4, -1.8),
            S(0.0, 8.8, -0.2),
            S(0.0, 11.4, 1.2),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = (
            p0,
            S(1.8, 1.3, -5.8),
            S(3.8, 0.9, -7.8),
            S(5.4, 0.8, -6.2),
        )
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz)

        for side in (-1.0, 1.0):
            draw_webbed_leg(m, S(side * 2.2, 3.0, -2.4), S(side * 2.6, 1.6, -0.8), S(side * 2.3, 0.65, 1.4), sz)

        for side in (-1.0, 1.0):
            up_alt = scrub * side
            sh = S(side * 2.1, 9.8, 0.8)
            el = S(side * 3.1, 9.6 + 0.6 * up_alt, 2.4)
            pw = S(side * 1.65, 11.2 + 0.95 * up_alt, 4.1)
            draw_webbed_leg(m, sh, el, pw, sz, paw_rot=art.rot_x(-0.55))

        R_h = art.rot_y(0.14 * scrub) @ art.rot_x(0.32) @ rot_z(-0.12 * scrub)
        draw_otter_head(m, S(0.0, 12.6, 2.5), R_h, sz, pup_scale, blink=(idx in (1, 3)))

    elif kind == 'surface_catch':
        # 6 frames: bursting chest-up at waterline with a gleaming silver brook fish clamped across its jaws!
        idx = int(round(t * 6)) % 6
        burst = [0.55, 1.0, 0.96, 0.88, 0.72, 0.62][idx]
        shake_yaw = [0.0, 0.24, -0.26, 0.18, -0.10, 0.0][idx]
        fish_wig = [0.35, -0.55, 0.60, -0.45, 0.25, -0.15][idx]

        ch_y = 8.0 + 3.8 * burst
        p0, p1, p2, p3 = (
            S(0.0, -4.2, -3.2),
            S(0.0, 1.2 + 1.8 * burst, -0.4),
            S(0.0, 5.2 + 2.8 * burst, 1.2),
            S(0.0, ch_y, 1.8),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = p0, S(0.0, -3.0, -7.0), S(0.0, -0.4, -10.8), S(0.0, 1.0, -13.8)
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 6)]
        draw_spine_and_tail(m, spine, tail, sz)

        for side in (-1.0, 1.0):
            sh = S(side * 2.1, ch_y - 3.6, 1.5)
            el = S(side * 2.8, ch_y - 5.4, 2.6)
            pw = S(side * 2.1, ch_y - 6.0, 3.9)
            draw_webbed_leg(m, sh, el, pw, sz)

        head_c = S(0.0, ch_y + 2.1, 2.5)
        R_h = art.rot_y(shake_yaw) @ art.rot_x(-0.14)
        draw_otter_head(m, head_c, R_h, sz, pup_scale, jaw_open=0.62)

        # Gleaming silver brook fish clamped crosswise right in the otter's jaws!
        fish_c = head_c + R_h @ np.array([0.0, -0.45 * sz, 3.45 * sz])
        R_fish = R_h @ art.rot_y(0.14 * fish_wig) @ rot_z(0.08 * fish_wig)
        draw_brook_fish(m, fish_c, R_fish, sz * 1.15, wiggle=fish_wig)

    elif kind == 'back_feast':
        # 8 frames: floating buoyantly on its back in water (belly-up!), holding the silver fish on its
        # cream chest with both forepaws & chewing while webbed hind feet & tail tip bob above water!
        idx = int(round(t * 8)) % 8
        bob_w = 0.25 * math.sin(p)
        chew = 0.56 if idx % 2 == 1 else 0.12
        nod = 0.12 if idx % 2 == 1 else 0.0

        # Buoyant supine spine: cream chest & belly face UP (+y above waterline!)
        p0, p1, p2, p3 = (
            S(0.0, 0.90 + bob_w, -6.0),
            S(0.0, 1.65 + bob_w, -1.5),
            S(0.0, 2.05 + bob_w, 3.0),
            S(0.0, 3.10 + bob_w, 6.8),
        )
        spine = [bezier3(p0, p1, p2, p3, u) for u in np.linspace(0.0, 1.0, 9)]
        t0, t1, t2, t3 = (
            p0,
            S(0.0, 0.50 + bob_w, -9.4),
            S(0.35 * math.sin(p), 1.65 + bob_w, -12.4),
            S(0.55 * math.sin(p), 3.05 + bob_w, -14.8),
        )
        tail = [bezier3(t0, t1, t2, t3, u) for u in np.linspace(0.0, 1.0, 7)]
        draw_spine_and_tail(m, spine, tail, sz, belly_up=True)

        # Gleaming silver brook fish held clearly elevated atop the buoyant cream chest!
        # Oriented along chest/diagonal (+z/-z) so full gleaming silver trout profile & forked tail pop in side & 3/4 views!
        fish_c = S(0.0, 4.75 + bob_w, 2.2)
        R_fish = art.rot_y(-1.22) @ art.rot_x(0.18)
        draw_brook_fish(m, fish_c, R_fish, sz * 1.12, wiggle=0.14 * math.sin(p * 2.0))

        # Both dark webbed forepaws reaching up onto the cream chest to grip the silver fish!
        for side in (-1.0, 1.0):
            sh = S(side * 2.30, 1.95 + bob_w, 4.0)
            el = S(side * 3.05, 3.45 + bob_w, 3.2)
            pw = S(side * 1.35, 4.85 + bob_w + (0.20 if idx % 2 == 0 else 0.0), 2.5 - side * 0.35)
            draw_webbed_leg(m, sh, el, pw, sz, paw_rot=rot_z(-side * 0.65))

        # Webbed hind paddles splayed in a cute buoyant V bobbing above the waterline!
        for side in (-1.0, 1.0):
            h_bob = 0.35 * math.sin(p + side * 0.8)
            hip = S(side * 1.85, 0.95 + bob_w, -5.4)
            knee = S(side * 2.40, 1.95 + bob_w + h_bob, -6.3)
            paw = S(side * 2.75, 3.45 + bob_w + h_bob, -7.0)
            R_pad = art.rot_y(side * 0.38) @ art.rot_x(-1.15)
            draw_webbed_leg(m, hip, knee, paw, sz, paw_rot=R_pad, splay_paddle=True)

        # Supine head propped up (chin tucked toward chest, snout pointing right at the fish!) chewing eagerly!
        head_c = S(0.0, 5.45 + bob_w - 0.25 * nod, 7.2)
        R_h = art.rot_y(math.pi + 0.08 * math.sin(p)) @ art.rot_x(0.36 + nod)
        draw_otter_head(m, head_c, R_h, sz, pup_scale, jaw_open=chew)

    elif kind == 'sun_sleep':
        # 6 frames: curled sleek nose-to-tail rest on riverbank/boulder!
        breathe = 0.16 * math.sin(p)
        spine = []
        for i in range(9):
            u = i / 8.0
            ang = -0.55 + 2.85 * u
            rad = 4.45 - 0.35 * u
            sx = math.cos(ang) * rad
            sz_p = math.sin(ang) * rad
            sy = 2.25 + (0.35 + breathe) * math.sin(u * math.pi)
            spine.append(S(sx, sy, sz_p))

        tail = []
        for i in range(7):
            v_u = i / 6.0
            ang = -0.55 - 2.15 * v_u
            rad = 4.65 + 0.65 * math.sin(v_u * math.pi)
            tx = math.cos(ang) * rad
            tz = math.sin(ang) * rad
            ty = 1.65 - 0.72 * v_u
            tail.append(S(tx, ty, tz))

        draw_spine_and_tail(m, spine, tail, sz)
        m.ell(S(-2.2, 0.95, 3.2), (1.08 * sz, 0.65 * sz, 1.28 * sz), DARK)

        head_c = S(-3.20, 3.00 + breathe * 0.6, 2.40)
        R_h = art.rot_y(-0.85) @ art.rot_x(0.16)
        draw_otter_head(m, head_c, R_h, sz, pup_scale, blink=True)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_otter(v, kind, (col - start) / n)
    prims = m.transform(math.pi / 2.0 - d * math.pi / 4.0, 0.0)
    if kind in WATER_KINDS:
        _cut_waterline(prims)
    depth, code = art.render(prims)
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], np.uint8)


def _render_row(args: tuple[int, int]) -> tuple[int, int, np.ndarray]:
    v, d = args
    row = np.zeros((H, COLS * W, 4), np.uint8)
    for col in range(COLS):
        row[:, col * W:(col + 1) * W] = frame(v, d, col)
    return v, d, row


def render_qa(out_path: Path, zoom: int = 3) -> None:
    picks = [
        (0, 0),   # E idle bank stance
        (1, 0),   # SE idle bank stance (cream throat, whiskers & rudder tail)
        (2, 0),   # S idle front view
        (6, 0),   # N idle rear tail margin check
        (1, 5),   # SE float_idle (wet head, upper back arch & tail tip!)
        (1, 9),   # SE periscope (tall upright chest & neck above waterline!)
        (2, 9),   # S periscope front cream bib!
        (0, 12),  # E land_bound stretched reach
        (0, 16),  # E land_bound supple arched-back mustelid hump!
        (1, 21),  # SE swim serpentine S-wave!
        (2, 23),  # S swim serpentine S-wave!
        (0, 29),  # E dive_plunge porpoising leap!
        (0, 31),  # E dive_plunge nose-first plunge into water!
        (1, 35),  # SE groom seated rubbing cheeks!
        (2, 39),  # S surface_catch bursting up with silver brook fish across jaws!
        (0, 45),  # E back_feast belly-up floating with silver fish on cream chest & hind paddles!
        (1, 46),  # SE back_feast chewing fish on chest!
        (1, 53),  # SE sun_sleep curled nose-to-tail rest!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bank_bg = np.array([46, 52, 44, 255], np.uint8)
    water_top = np.array([34, 56, 66, 255], np.uint8)
    water_sub = np.array([26, 44, 54, 255], np.uint8)

    for v in range(BUILDS_N):
        for ci, (d, col) in enumerate(picks):
            kind = next(x[0] for x in BLOCKS if x[1] <= col < x[1] + x[2])
            cell = grid[v * H:(v + 1) * H, ci * W:(ci + 1) * W]
            if kind in WATER_KINDS:
                cell[:52, :] = water_top
                cell[52:, :] = water_sub
                cell[52, ::3] = np.array([120, 165, 180, 255], np.uint8)
            else:
                cell[:, :] = bank_bg
                cell[52, ::4] = np.array([90, 102, 86, 255], np.uint8)
            px = frame(v, d, col)
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
                print(f'otter build {done // 8}/{BUILDS_N}', flush=True)
    save_png(ROOT / 'assets/wildlife/otter.png', sheet)
    print('Saved assets/wildlife/otter.png', sheet.shape)


if __name__ == '__main__':
    main()
