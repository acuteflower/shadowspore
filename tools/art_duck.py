#!/usr/bin/env python3
"""Mallard Duck Family / Stockenten-Familie (Anas platyrhynchos) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, feet / waterline at (32, 52); 58 columns; 3 builds x 8 facings = 24 rows (3712x1536).
No emissive parts; natural iridescent & warm waterfowl palettes.

Builds:
  0: Stockenten-Erpel (Drake: glossy bottle-green head, crisp snow-white neck-ring, chestnut-burgundy breast,
     pale silvery-pearl grey flanks, black-and-white tail with upturned black drake curl 'Erpellocke',
     metallic violet-blue white-bordered wing speculum, yellow spatulate bill, bright orange webbed feet)
  1: Stockente (Hen: warm mottled buff-tan & dark umber scalloped plumage, dark crown & eye-stripe over buff cheek,
     warm brownish-orange bill, violet-blue white-edged wing speculum, orange webbed feet)
  2: Entenküken (Duckling: 0.55x fluffy juvenile anchored on GROUND_ROW = 52.0; buttercup-yellow cheeks/throat/belly
     with classic dark brown eye-line, olive-umber cap & back with two yellow back-spots, tiny dark stubby bill,
     tiny orange webbed feet)

Columns (58):
  float_idle 0:4 (waterline y>=0), swim 4:10 (waterline y>=0), dabble 10:16 (Up-Ending 'Gründeln' / 'Bürzel hoch!', y>=0),
  water_preen 16:20 (waterline y>=0), fly 20:28 (airborne), water_takeoff 28:34 (splashing takeoff run),
  shore_idle 34:38 (land), shore_waddle 38:46 (land), shore_wing_flap 46:52 (land), shore_sleep 52:58 (land).

Usage: py -3 tools/art_duck.py [--preview-only] [--qa=path.png]
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

HEAD, BREAST, BODY, BACK_DARK, WHITE, SPECULUM, BILL, FEET, EYE, GLINT = range(10)

BLOCKS = [
    ('float_idle', 0, 4),
    ('swim', 4, 6),
    ('dabble', 10, 6),
    ('water_preen', 16, 4),
    ('fly', 20, 8),
    ('water_takeoff', 28, 6),
    ('shore_idle', 34, 4),
    ('shore_waddle', 38, 8),
    ('shore_wing_flap', 46, 6),
    ('shore_sleep', 52, 6),
]

WATER_KINDS = {'float_idle', 'swim', 'dabble', 'water_preen'}


def setup_art() -> None:
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 52.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE: 3.8,
        GLINT: 4.6,
        WHITE: 1.95,
        SPECULUM: 1.85,
        BILL: 1.45,
        FEET: 1.45,
        BACK_DARK: 1.30,
    }
    art.ink_color = lambda mat: hexc('0b0b14' if mat in (BACK_DARK, EYE, HEAD) else '1b141d')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


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
        # 0 Stockenten-Erpel (Drake)
        head = ['0b2124', '124a3b', '1f7d59', '46b57f']       # Glossy bottle-green head & upper neck
        breast = ['2b121c', '54222c', '85393d', 'b55b56']     # Rich chestnut-burgundy breast
        body = ['5b5d70', '898ca1', 'bdc1d4', 'edf0fa']       # Pale silvery-pearl grey flanks
        back_dark = ['10101b', '1e1f30', '35374f', '535675']  # Coal-black rump, Erpellocke curl & dark mantle
        white = ['82869e', 'b2b7cc', 'e1e5f2', 'ffffff']      # Snow-white neck-ring, speculum bars & outer tail
        speculum = ['191a4a', '293585', '4063c7', '70a3fa']   # Metallic violet-blue wing speculum
        bill = ['6e5619', 'a68624', 'deb938', 'fce268']       # Warm yellow spatulate bill
    elif v == 1:
        # 1 Stockente (Hen)
        head = ['594032', '8a674c', 'bd956f', 'e8c69b']       # Warm buff-ochre cheek & throat
        breast = ['4f3428', '7d563e', 'b0805b', 'deb082']     # Warm mottled buff-tan breast
        body = ['422c22', '6e4a35', '9c6e4e', 'caa076']       # Warm buff-brown plumage
        back_dark = ['1c1317', '382523', '5c3e35', '855f4f']  # Dark umber crown, eye-stripe & scalloped crescents
        white = ['807e91', 'b0aebf', 'dfdee8', 'fcfcff']      # Crisp cream-white speculum border & tail edge
        speculum = ['191a4a', '293585', '4063c7', '70a3fa']   # Violet-blue wing speculum
        bill = ['693415', 'a3551e', 'db7e2c', 'ffad4a']       # Warm brownish-orange female bill (crisp contrast against buff cheek!)
    else:
        # 2 Entenküken (Duckling)
        head = ['785b20', 'b38b2c', 'e8c043', 'fff278']       # Warm buttercup-yellow downy cheeks & throat
        breast = ['755922', 'ad8730', 'e0ba4a', 'ffef82']     # Fluffy buttercup-yellow breast & belly
        body = ['29201c', '4a3a2b', '735b3f', '9e8158']       # Warm olive-umber downy cap & back
        back_dark = ['1a1316', '332421', '543c32', '785949']  # Classic dark brown eye-line & cap stripe
        white = ['806222', 'bd9431', 'f0c84b', 'fff58c']      # Bright buttercup-yellow dorsal back-spots!
        speculum = ['362b21', '5c4a35', '876f4e', 'b3966d']   # Downy olive-buff winglet
        bill = ['261e1d', '45352f', '6b5245', '947561']       # Tiny dark olive-horn stubby duckling bill

    ramps = [
        head,
        breast,
        body,
        back_dark,
        white,
        speculum,
        bill,
        ['782b12', 'b84818', 'ed7024', 'ffa048'],             # 7 FEET (bright orange webbed paddles)
        ['08070f', '131120', '252238', '3c3854'],             # 8 EYE
        ['98a3b3', 'c2cddb', 'e8eff7', 'ffffff'],             # 9 GLINT
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_webbed_foot(
    m: art.Model,
    hip: np.ndarray,
    ankle: np.ndarray,
    foot: np.ndarray,
    sz: float,
    foot_rot: np.ndarray | None = None,
    tucked: bool = False,
) -> None:
    """Bright orange duck leg & broad three-toed webbed paddle foot."""
    r_scale = 1.18 if sz < 0.7 else 1.0  # Keep duckling legs/feet crisp at 0.55x!
    m.limb(hip, ankle, 0.78 * sz * r_scale, 0.56 * sz * r_scale, FEET, step=0.38)
    R_f = np.eye(3) if foot_rot is None else foot_rot
    if tucked:
        m.ell(foot, (0.85 * sz * r_scale, 0.52 * sz * r_scale, 1.18 * sz * r_scale), FEET, R=R_f)
    else:
        pad_c = foot + R_f @ np.array([0.0, 0.0, 0.72 * sz * r_scale])
        m.ell(pad_c, (1.18 * sz * r_scale, 0.44 * sz * r_scale, 1.32 * sz * r_scale), FEET, R=R_f)
        for ti in (-0.85, 0.0, 0.85):
            toe_tip = foot + R_f @ np.array([ti * 1.05 * sz * r_scale, -0.04 * sz, 1.85 * sz * r_scale])
            m.limb(foot, toe_tip, 0.44 * sz * r_scale, 0.30 * sz * r_scale, FEET, step=0.35)


def draw_spread_duck_wing(
    m: art.Model,
    v: int,
    side: float,
    shoulder: np.ndarray,
    R_body: np.ndarray,
    span: float,
    lift: float,
    sweep_z: float,
    wrist_fold: float,
    sz: float,
) -> None:
    """Pointed aerodynamic waterfowl wing with flashing violet-blue & snow-white speculum on inner secondaries!"""
    if v == 2:
        # Adorable tiny stubby downy duckling winglet flutter!
        tip = shoulder + R_body @ np.array([
            side * 4.4 * sz,
            (1.6 + 0.30 * lift) * sz,
            (-0.9 + 0.25 * sweep_z) * sz,
        ])
        mid = 0.5 * (shoulder + tip) + R_body @ np.array([0.0, 0.45 * sz, -0.85 * sz])
        m.limb(shoulder, tip, 1.35 * sz, 0.85 * sz, BODY, step=0.35)
        m.ell(mid, (1.15 * sz, 0.80 * sz, 1.45 * sz), SPECULUM, R=R_body)
        m.ell(shoulder + R_body @ np.array([side * 0.8 * sz, 0.35 * sz, -0.5 * sz]), (0.85 * sz, 0.75 * sz, 0.95 * sz), WHITE, R=R_body)
        return

    carpal = shoulder + R_body @ np.array([
        side * span * (0.45 - 0.12 * wrist_fold) * sz,
        lift * (0.56 + 0.18 * wrist_fold) * sz,
        (1.65 - 0.75 * wrist_fold + 0.35 * sweep_z) * sz,
    ])
    tip = shoulder + R_body @ np.array([
        side * span * (1.0 - 0.20 * wrist_fold) * sz,
        (lift - 1.35 * wrist_fold) * sz,
        (-2.35 - 1.10 * wrist_fold + sweep_z) * sz,
    ])

    wing_mat = BODY if v == 0 else BREAST
    m.limb(shoulder, carpal, 1.48 * sz, 1.15 * sz, wing_mat, step=0.55)
    m.limb(carpal, tip, 1.12 * sz, 0.58 * sz, BACK_DARK, step=0.55)

    # Inner secondaries: Greater coverts -> WHITE anterior bar -> VIOLET-BLUE SPECULUM -> WHITE trailing edge!
    n_sec = 7
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (5.4 - 0.45 * u) * sz * (1.0 - 0.16 * wrist_fold)
        trail_dir = R_body @ np.array([side * 0.25 * u * sz, -0.45 * sz, -chord])
        p_cov = le + trail_dir * 0.24
        p_w1 = le + trail_dir * 0.44
        p_sp = le + trail_dir * 0.74
        p_w2 = le + trail_dir * 1.00
        m.limb(le, p_cov, 1.08 * sz, 0.96 * sz, wing_mat, step=0.48)
        m.limb(p_cov, p_w1, 0.92 * sz, 0.86 * sz, WHITE, step=0.42)
        m.limb(p_w1, p_sp, 0.90 * sz, 0.80 * sz, SPECULUM, step=0.42)
        m.limb(p_sp, p_w2, 0.76 * sz, 0.58 * sz, WHITE, step=0.42)

    # Pointed outer waterfowl primaries (sleek dark umber-slate flight feathers)
    n_pri = 6
    f_spread = 1.0 - 0.48 * wrist_fold
    for i in range(n_pri):
        u = (i + 0.12) / n_pri
        le = carpal * (1.0 - u) + tip * u
        plen = (5.8 - 1.45 * u) * sz * (1.0 - 0.12 * wrist_fold)
        fan = -0.15 + 0.72 * u
        delta = R_body @ np.array([
            side * math.sin(fan + 0.28) * plen * 0.46 * f_spread,
            ((u - 0.45) * 0.45 * f_spread - 0.35 * wrist_fold) * sz,
            -math.cos(fan * 0.58) * plen,
        ])
        m.limb(le, le + delta, (0.86 - 0.14 * u) * sz, 0.44 * sz, BACK_DARK, step=0.50)


def draw_duck_head(
    m: art.Model,
    v: int,
    head_c: np.ndarray,
    R_head: np.ndarray,
    sz: float,
    bill_open: float = 0.0,
    blink: bool = False,
    tucked_bill: bool = False,
) -> None:
    """Rounded Mallard cranium, steep forehead, broad spatulate bill (or tiny duckling bill) & expressive eye."""
    hs = sz * (1.26 if v == 2 else 1.0)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + R_head @ (np.array([x, y, z], float) * hs)

    # Plump rounded waterfowl head & cheek
    m.ell(hp(0.0, 0.10, 0.0), (2.05 * hs, 1.98 * hs, 2.32 * hs), HEAD, R=R_head)

    if v == 1:
        # Hen: dark umber crown cap + classic Mallard dark eye-stripe ('Augenstreif') across buff cheek!
        m.ell(hp(0.0, 1.25, -0.10), (1.72 * hs, 1.02 * hs, 2.08 * hs), BACK_DARK, R=R_head)
        for side in (-1.0, 1.0):
            m.limb(hp(side * 1.68, 0.38, 1.45), hp(side * 1.72, 0.28, -1.15), 0.42 * hs, 0.36 * hs, BACK_DARK, step=0.35)
    elif v == 2:
        # Duckling: warm olive-umber downy cap + dark brown eye-line across buttercup-yellow cheek!
        m.ell(hp(0.0, 1.32, -0.15), (1.82 * hs, 1.08 * hs, 2.05 * hs), BODY, R=R_head)
        m.ell(hp(0.0, 0.72, -1.35), (1.35 * hs, 1.25 * hs, 1.15 * hs), BODY, R=R_head)
        for side in (-1.0, 1.0):
            m.limb(hp(side * 1.65, 0.34, 1.45), hp(side * 1.68, 0.26, -1.10), 0.44 * hs, 0.38 * hs, BACK_DARK, step=0.32)

    # Bill: tucked into scapulars when sleeping, or broad flat spatulate Mallard bill!
    if not tucked_bill:
        if v == 2:
            # Tiny dark stubby duckling bill
            b_base = hp(0.0, -0.25, 1.75)
            b_tip = hp(0.0, -0.35, 3.15)
            m.limb(b_base, b_tip, 0.88 * hs, 0.66 * hs, BILL, step=0.32)
            m.ell(hp(0.0, -0.28, 2.55), (0.98 * hs, 0.52 * hs, 0.92 * hs), BILL, R=R_head)
        else:
            # Broad dorsoventrally flattened spatulate waterfowl bill ('Entenschnabel')
            up_rot = R_head @ art.rot_x(-0.18 * bill_open + 0.05)
            b_mid = hp(0.0, -0.24, 2.65)
            b_tip = b_mid + up_rot @ (np.array([0.0, -0.08, 1.35]) * hs)
            m.ell(b_mid, (1.12 * hs, 0.56 * hs, 1.35 * hs), BILL, R=up_rot)
            m.ell(b_tip, (1.22 * hs, 0.46 * hs, 0.98 * hs), BILL, R=up_rot)
            if v == 1:
                # Subtle dark saddle blotch on female Mallard culmen
                m.ell(hp(0.0, 0.06, 2.85), (0.68 * hs, 0.34 * hs, 0.82 * hs), BACK_DARK, R=up_rot)
            # Tiny dark bill nail at very tip
            m.ell(b_tip + up_rot @ (np.array([0.0, 0.04, 0.68]) * hs), (0.42 * hs, 0.28 * hs, 0.34 * hs), BACK_DARK, R=up_rot)
            if bill_open > 0.08:
                lo_rot = R_head @ art.rot_x(0.36 * bill_open + 0.08)
                lo_c = hp(0.0, -0.58 - 0.25 * bill_open, 2.95)
                m.ell(lo_c, (0.95 * hs, 0.38 * hs, 1.35 * hs), BILL, R=lo_rot)

    # Glossy dark waterfowl eye + crisp catchlight
    for side in (-1.0, 1.0):
        er = 0.56 if v == 2 else 0.48
        eh = 0.16 if blink else er
        m.ell(hp(side * 1.56, 0.42, 0.62), (0.44 * hs, eh * hs, er * hs), EYE, R=R_head)
        if not blink:
            gr = 0.25 if v == 2 else 0.21
            m.ell(hp(side * 1.68, 0.60, 0.82), (gr * hs, gr * hs, gr * hs), GLINT, R=R_head)


def draw_duck_torso_and_tail(
    m: art.Model,
    v: int,
    torso_c: np.ndarray,
    R_body: np.ndarray,
    sz: float,
    tail_wag: float = 0.0,
    tail_lift: float = 0.0,
    folded_wings: bool = True,
    wing_lift_side: float = 0.0,
) -> None:
    """Buoyant boat-hull Mallard body, chestnut breast, pearl flanks, folded speculum wings & upturned Erpellocke!"""
    def bp(x: float, y: float, z: float) -> np.ndarray:
        return torso_c + R_body @ (np.array([x, y, z], float) * sz)

    if v == 2:
        # Fluffy round-bottomed juvenile Mallard duckling:
        # Buttercup-yellow breast & belly + olive-umber mantle/back + two classic yellow dorsal spots!
        m.ell(bp(0.0, -0.15, 0.25), (3.45 * sz, 3.15 * sz, 4.45 * sz), BREAST, R=R_body)
        m.ell(bp(0.0, 0.35, 2.45), (3.15 * sz, 2.75 * sz, 2.95 * sz), BREAST, R=R_body)
        # Olive-umber dorsal saddle & rump
        m.ell(bp(0.0, 1.15, -0.55), (3.18 * sz, 2.35 * sz, 4.15 * sz), BODY, R=R_body)
        # Two iconic buttercup-yellow juvenile Mallard back-spots!
        for side in (-1.0, 1.0):
            m.ell(bp(side * 1.75, 1.85, -0.65), (0.95 * sz, 0.82 * sz, 1.10 * sz), WHITE, R=R_body)
        # Cute stubby fuzzy duckling tail tuft
        t_rot = R_body @ art.rot_y(tail_wag) @ art.rot_x(-0.38 - tail_lift)
        t_base = bp(0.0, 0.65, -3.95)
        t_tip = t_base + t_rot @ (np.array([0.0, 0.45, -2.15]) * sz)
        m.limb(t_base, t_tip, 1.45 * sz, 0.72 * sz, BODY, step=0.35)
        if folded_wings:
            for side in (-1.0, 1.0):
                wl = 0.75 if side * wing_lift_side > 0 else 0.0
                wc = bp(side * (2.65 + 0.55 * wl), 0.75 + 0.45 * wl, -0.25)
                m.ell(wc, (1.05 * sz, 1.55 * sz, 2.55 * sz), SPECULUM, R=R_body)
        return

    # Buoyant boat-hulled adult Mallard body (~17-19 px long!)
    # Main silvery-pearl (Erpel) or mottled buff (Ente) flank hull
    m.ell(bp(0.0, 0.0, -0.35), (3.75 * sz, 3.35 * sz, 5.55 * sz), BODY, R=R_body)
    # Full rounded chestnut-burgundy (Erpel) or warm buff-tan (Ente) breast prow
    m.ell(bp(0.0, 0.35, 3.45), (3.48 * sz, 3.05 * sz, 3.25 * sz), BREAST, R=R_body)
    # Darker mantle / rump saddle along dorsal spine
    m.ell(bp(0.0, 1.55, -1.65), (2.95 * sz, 1.95 * sz, 4.15 * sz), BACK_DARK if v == 0 else BODY, R=R_body)

    if v == 1:
        # Hen: warm dark-umber scalloped feather crescents on flanks & breast
        for side in (-1.0, 1.0):
            for fi, fz in enumerate((2.8, 0.6, -1.8)):
                m.ell(bp(side * 3.15, 0.15 + 0.25 * fi, fz), (0.68 * sz, 0.72 * sz, 0.98 * sz), BACK_DARK, R=R_body)

    # Folded wings resting high on flanks with visible metallic blue-and-white speculum flash!
    if folded_wings:
        for side in (-1.0, 1.0):
            wl = 1.0 if side * wing_lift_side > 0 else 0.0
            w_rot = R_body @ art.rot_y(side * (0.06 + 0.28 * wl)) @ art.rot_x(0.08 + 0.18 * wl)
            wc = bp(side * (2.95 + 0.75 * wl), 0.95 + 0.55 * wl, -0.85)
            m.ell(wc, (1.18 * sz, 2.05 * sz, 4.15 * sz), BODY, R=w_rot)
            # Crisp white anterior bar + metallic violet-blue speculum + white posterior bar!
            m.ell(wc + w_rot @ (np.array([side * 0.58, -0.22, -0.35]) * sz), (0.66 * sz, 0.95 * sz, 0.72 * sz), WHITE, R=w_rot)
            m.ell(wc + w_rot @ (np.array([side * 0.64, -0.28, -1.35]) * sz), (0.70 * sz, 1.02 * sz, 1.15 * sz), SPECULUM, R=w_rot)
            m.ell(wc + w_rot @ (np.array([side * 0.58, -0.32, -2.35]) * sz), (0.66 * sz, 0.90 * sz, 0.70 * sz), WHITE, R=w_rot)
            # Dark crossed primary tips extending toward tail
            m.ell(wc + w_rot @ (np.array([-side * 0.25, 0.15, -3.55]) * sz), (0.85 * sz, 0.95 * sz, 1.75 * sz), BACK_DARK, R=w_rot)

    # Plump rump + crisp white outer tail / undertail ('Bürzel') + Erpel's upturned black curl ('Erpellocke')!
    t_rot = R_body @ art.rot_y(tail_wag) @ art.rot_x(-0.22 - tail_lift)
    rump_p = bp(0.0, 0.35, -4.85)
    m.ell(rump_p, (2.55 * sz, 2.25 * sz, 2.15 * sz), BACK_DARK if v == 0 else BODY, R=R_body)
    # Fluffy snow-white undertail & outer rectrices!
    m.ell(bp(0.0, -0.45, -5.55), (2.35 * sz, 1.65 * sz, 2.15 * sz), WHITE, R=t_rot)
    for side in (-1.0, 1.0):
        t_out = rump_p + t_rot @ (np.array([side * 1.15, 0.25, -3.45]) * sz)
        m.limb(rump_p + t_rot @ (np.array([side * 0.85, 0.05, -0.85]) * sz), t_out, 1.05 * sz, 0.58 * sz, WHITE, step=0.42)
    # Central tail spike
    t_tip = rump_p + t_rot @ (np.array([0.0, 0.48, -3.85]) * sz)
    m.limb(rump_p, t_tip, 1.18 * sz, 0.56 * sz, BACK_DARK, step=0.42)

    if v == 0:
        # Iconic upturned glossy black drake tail curl ('Erpellocke')!
        c_mid = rump_p + t_rot @ (np.array([0.0, 1.35, -3.95]) * sz)
        c_top = rump_p + t_rot @ (np.array([0.0, 2.45, -3.15]) * sz)
        c_in = rump_p + t_rot @ (np.array([0.0, 2.35, -2.25]) * sz)
        m.limb(t_tip, c_mid, 0.68 * sz, 0.58 * sz, BACK_DARK, step=0.32)
        m.limb(c_mid, c_top, 0.58 * sz, 0.48 * sz, BACK_DARK, step=0.32)
        m.limb(c_top, c_in, 0.48 * sz, 0.38 * sz, BACK_DARK, step=0.32)


def draw_neck_and_collar(
    m: art.Model,
    v: int,
    neck_base: np.ndarray,
    head_c: np.ndarray,
    sz: float,
    curve_back: float = 0.55,
) -> None:
    """Graceful S-curved waterfowl neck with Erpel's crisp snow-white neck-ring ('Halsring')!"""
    ns = sz * (1.16 if v == 2 else 1.0)
    mid = 0.52 * neck_base + 0.48 * head_c + np.array([0.0, 0.0, -curve_back * sz])
    pts = [
        neck_base,
        0.5 * (neck_base + mid),
        mid,
        0.5 * (mid + head_c),
        head_c,
    ]
    for i, pt in enumerate(pts[:-1]):
        u = i / 3.0
        r = (1.72 - 0.30 * u) * ns
        if v == 0:
            if i == 0:
                mat = BREAST
            elif i == 1:
                mat = WHITE   # Crisp snow-white Mallard drake neck-ring!
            else:
                mat = HEAD
        elif v == 1:
            mat = BREAST if i == 0 else HEAD
        else:
            mat = BREAST if i == 0 else HEAD
        m.ell(pt, (r * 0.96, r * 1.05, r * 1.02), mat)
        if v == 0 and i == 1:
            # Extra crisp collar ring wrap so the snow-white neck-ring reads cleanly from all 8 angles!
            m.ell(pt + np.array([0.0, -0.10 * sz, 0.0]), (r * 1.12, 0.66 * sz, r * 1.12), WHITE)


def build_duck(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    # Adult Erpel = 1.12 (~18px buoyant body), Ente = 1.04 (~17px body), Küken = 0.55 * 1.12 = 0.616 (exact 0.55x scale!)
    base_sz = 1.12
    sz = base_sz * [1.0, 0.93, 0.55][v]
    is_chick = (v == 2)
    p = t * math.tau
    bob = math.sin(p)

    if kind == 'float_idle':
        # Buoyant calm water float on GROUND_ROW = 52.0 (y >= 0.0 clipped), subtle breast bob & tail wag
        idx = int(round(t * 4)) % 4
        by = (1.65 + 0.22 * bob) * sz
        pitch = 0.03 * math.cos(p)
        wag = 0.14 * math.sin(p)
        R_b = art.rot_x(pitch)
        torso_c = np.array([0.0, by, -0.35 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_wag=wag, tail_lift=0.12)

        neck_base = torso_c + R_b @ np.array([0.0, 1.55 * sz, 4.05 * sz])
        head_c = np.array([0.0, (7.45 + 0.24 * bob) * sz, 4.15 * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.65)
        R_h = art.rot_y(0.12 * math.sin(p)) @ art.rot_x(0.03)
        draw_duck_head(m, v, head_c, R_h, sz, blink=(idx == 3))

    elif kind == 'swim':
        # Smooth 6-frame paddling glide, neck poised gracefully, subtle waterfowl head-bob!
        bob2 = math.sin(p * 2.0)
        by = (1.48 + 0.16 * bob) * sz
        wag = 0.20 * math.sin(p)
        R_b = art.rot_x(0.04)
        torso_c = np.array([0.18 * math.sin(p) * sz, by, -0.45 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_wag=wag, tail_lift=0.08)

        thrust_z = 0.65 * math.sin(p)
        neck_base = torso_c + R_b @ np.array([0.0, 1.45 * sz, 4.10 * sz])
        head_c = np.array([0.12 * math.sin(p) * sz, (7.15 + 0.16 * bob2) * sz, (4.75 + thrust_z) * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.45)
        draw_duck_head(m, v, head_c, art.rot_x(0.04), sz)

    elif kind == 'dabble':
        # 6-frame Up-Ending 'Gründeln' ('Bürzel hoch!'), waterline clipped y >= 0.0:
        # Frame 0: tipping forward; Frames 1..4: head & neck plunged completely underwater (y < 0 clipped out!)
        # while plump rump, white undertail, curled tail & kicking orange webbed feet stick straight up!
        # Frame 5: tipping back level! (For Küken v==2, cute miniature bobbing dip / half-tip!)
        idx = int(round(t * 6)) % 6
        if v == 2:
            # Cute miniature duckling half-tip bobbing dip!
            tip_amt = [0.45, 0.95, 1.0, 0.98, 0.92, 0.35][idx]
            pitch = 0.88 * tip_amt  # +rot_x pitches +z (chest/head) downward, -z (rump/tail) upward!
            R_b = art.rot_x(pitch)
            torso_c = np.array([0.0, (1.85 + 1.55 * tip_amt) * sz, (-0.35 + 1.45 * tip_amt) * sz])
            draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_wag=0.22 * math.sin(p * 2.0), tail_lift=0.28 * tip_amt)

            if idx in (1, 2, 3, 4):
                # Cute tiny orange webbed feet kicking right at the surface behind the duckling!
                for side in (-1.0, 1.0):
                    kick = 0.85 * math.sin(p * 2.0 + side * 1.5)
                    hip = torso_c + R_b @ np.array([side * 2.1 * sz, -1.2 * sz, -2.0 * sz])
                    ank = hip + np.array([side * 0.4 * sz, (0.8 + 0.4 * kick) * sz, (-1.8 - 0.5 * kick) * sz])
                    ft = ank + np.array([side * 0.3 * sz, (0.6 + 0.5 * kick) * sz, -1.2 * sz])
                    draw_webbed_foot(m, hip, ank, ft, sz, foot_rot=art.rot_x(-0.95))

            neck_base = torso_c + R_b @ np.array([0.0, 1.25 * sz, 3.25 * sz])
            head_c = torso_c + R_b @ np.array([0.0, (4.2 - 1.4 * tip_amt) * sz, (4.2 + 0.8 * tip_amt) * sz])
            draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.25)
            draw_duck_head(m, v, head_c, R_b @ art.rot_x(0.25 * tip_amt), sz)
        else:
            if idx in (0, 5):
                # Frame 0 tipping forward (~44 deg), Frame 5 tipping back level (~32 deg)
                pitch = 0.78 if idx == 0 else 0.56
                R_b = art.rot_x(pitch)
                torso_c = np.array([0.0, 2.35 * sz, 0.85 * sz])
                draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_lift=0.20)
                neck_base = torso_c + R_b @ np.array([0.0, 1.35 * sz, 4.05 * sz])
                head_c = np.array([0.0, (2.35 if idx == 0 else 4.25) * sz, 5.85 * sz])
                draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.25)
                draw_duck_head(m, v, head_c, art.rot_x(0.55 if idx == 0 else 0.25), sz)
            else:
                # Frames 1..4: FULL VERTICAL UP-ENDING ('Bürzel hoch!')!
                # +rot_x(1.48 rad ~ 85 deg) plunges chest/neck/head deep below y=0 (clipped out!)
                # while plump feathered rump, white undertail, Erpellocke & kicking orange webbed feet stick straight up!
                sway_x = [0.0, 0.35, -0.35, 0.20][idx - 1]
                pitch = [1.44, 1.50, 1.48, 1.45][idx - 1]
                R_b = rot_z(0.05 * sway_x) @ art.rot_x(pitch)
                torso_c = np.array([sway_x * sz, 2.75 * sz, 0.15 * sz])
                draw_duck_torso_and_tail(
                    m, v, torso_c, R_b, sz,
                    tail_wag=0.14 * sway_x,
                    tail_lift=0.22,
                    folded_wings=True,
                )
                # Bright-orange webbed feet kicking alternately clearly visible on ventral (+y/+z) side of vertical rump!
                for s_i, side in enumerate((-1.0, 1.0)):
                    alt = 1.0 if ((idx + s_i) % 2 == 0) else -1.0
                    hip = np.array([side * 2.45 * sz, 3.35 * sz, 1.45 * sz])
                    ank = np.array([side * 3.35 * sz, (5.25 + 0.95 * alt) * sz, (2.45 + 0.75 * alt) * sz])
                    ft = np.array([side * 3.65 * sz, (6.95 + 1.25 * alt) * sz, (3.05 + 0.95 * alt) * sz])
                    R_f = art.rot_y(side * 0.32) @ art.rot_x(-0.92 + 0.28 * alt)
                    draw_webbed_foot(m, hip, ank, ft, sz, foot_rot=R_f)

    elif kind == 'water_preen':
        # 4 frames: floating while turning bill into lifted wing / scapular feathers
        idx = int(round(t * 4)) % 4
        turn = [0.55, 1.0, 0.95, 0.40][idx]
        by = (1.65 + 0.15 * bob) * sz
        R_b = art.rot_x(0.02)
        torso_c = np.array([0.0, by, -0.35 * sz])
        draw_duck_torso_and_tail(
            m, v, torso_c, R_b, sz,
            tail_wag=0.12 * bob,
            tail_lift=0.12,
            wing_lift_side=(-1.0 if idx in (1, 2) else 0.0),
        )
        neck_base = torso_c + np.array([0.0, 1.55 * sz, 3.85 * sz])
        head_c = np.array([-1.35 * turn * sz, (7.05 - 0.85 * turn) * sz, (4.05 - 3.65 * turn) * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.35 * (1.0 - turn))
        R_h = art.rot_y(-2.15 * turn) @ art.rot_x(0.32 * turn + (0.14 if idx == 2 else 0.0))
        draw_duck_head(m, v, head_c, R_h, sz, blink=(idx == 2))

    elif kind == 'fly':
        # Energetic 8-frame Mallard flight: outstretched neck, tucked orange feet, blue-and-white speculum flashing!
        idx = int(round(t * 8)) % 8
        lifts = [9.8, 4.6, -1.8, -7.2, -3.6, 2.4, 7.2, 10.2][idx]
        folds = [0.06, 0.0, 0.0, 0.10, 0.44, 0.52, 0.28, 0.10][idx]
        sweeps = [-1.0, 0.6, 1.8, 2.2, 0.4, -0.8, -1.4, -1.2][idx]
        body_lift = [-0.30, -0.05, 0.40, 0.65, 0.25, -0.10, -0.30, -0.35][idx]

        by = (15.5 + body_lift) * (1.0 if v < 2 else 0.78)
        R_b = art.rot_x(-0.08)
        torso_c = np.array([0.0, by, -1.35 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_lift=0.05, folded_wings=False)

        # Outstretched aerodynamic Mallard neck & head reaching forward!
        neck_base = torso_c + R_b @ np.array([0.0, 0.95 * sz, 4.35 * sz])
        head_c = torso_c + R_b @ np.array([0.0, 2.05 * sz, 9.65 * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=-0.15)
        draw_duck_head(m, v, head_c, art.rot_x(-0.04), sz)

        # Tucked bright-orange webbed feet streamlined right beneath tail!
        for side in (-1.0, 1.0):
            hip = torso_c + R_b @ np.array([side * 1.65 * sz, -2.15 * sz, -2.85 * sz])
            ank = torso_c + R_b @ np.array([side * 1.45 * sz, -2.35 * sz, -4.65 * sz])
            ft = torso_c + R_b @ np.array([side * 1.35 * sz, -2.25 * sz, -5.85 * sz])
            draw_webbed_foot(m, hip, ank, ft, sz, foot_rot=art.rot_x(1.25), tucked=True)

        # Flashing violet-blue & white speculum on outstretched beating wings (span kept safely inside 64x64!)
        for side in (-1.0, 1.0):
            sh = torso_c + R_b @ np.array([side * 2.85 * sz, 1.35 * sz, 1.05 * sz])
            draw_spread_duck_wing(m, v, side, sh, R_b, span=14.4, lift=lifts, sweep_z=sweeps, wrist_fold=folds, sz=sz)

    elif kind == 'water_takeoff':
        # 6-frame splashing takeoff run: wings raised/beating high while pattering orange webbed feet forward off GROUND_ROW=52!
        idx = int(round(t * 6)) % 6
        u = ease(idx / 5.0)
        climb = (5.0 + 8.6 * u) * (sz if idx == 0 else (0.72 + 0.28 * sz))
        R_b = art.rot_x(-0.46 + 0.24 * u)  # Negative rot_x pitches chest UP, rump DOWN for climbing run!
        torso_c = np.array([0.0, climb, (-1.15 + 0.55 * u) * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_lift=0.18, folded_wings=False)

        neck_base = torso_c + R_b @ np.array([0.0, 1.25 * sz, 4.15 * sz])
        head_c = torso_c + R_b @ np.array([0.0, 3.85 * sz, 7.95 * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.15)
        draw_duck_head(m, v, head_c, art.rot_x(-0.18), sz, bill_open=(0.35 if idx in (0, 1) else 0.0))

        # Rapidly pattering bright-orange webbed feet running up off GROUND_ROW = 52.0!
        for s_i, side in enumerate((-1.0, 1.0)):
            alt = 1.0 if ((idx + s_i) % 2 == 0) else -1.0
            hip = torso_c + R_b @ np.array([side * 1.95 * sz, -2.35 * sz, -0.85 * sz])
            base_fy = max(0.62 * sz, climb - 4.35 * sz + (0.95 if alt > 0 else 0.0) * sz)
            fz = (1.65 * alt - 0.55) * sz
            ank = 0.48 * hip + 0.52 * np.array([side * 1.95 * sz, base_fy, fz]) + np.array([0.0, 0.45 * sz, -0.55 * sz])
            ft = np.array([side * 1.95 * sz, base_fy, fz])
            draw_webbed_foot(m, hip, ank, ft, sz, foot_rot=art.rot_x(0.35 if alt > 0 else 0.05))

        lifts = [8.8, 2.2, -5.8, 5.2, 9.4, -3.2][idx]
        folds = [0.12, 0.04, 0.08, 0.25, 0.08, 0.10][idx]
        sweeps = [-0.8, 1.4, 2.0, -0.6, -1.2, 1.8][idx]
        for side in (-1.0, 1.0):
            sh = torso_c + R_b @ np.array([side * 2.85 * sz, 1.35 * sz, 1.05 * sz])
            draw_spread_duck_wing(m, v, side, sh, R_b, span=14.0, lift=lifts, sweep_z=sweeps, wrist_fold=folds, sz=sz)

    elif kind == 'shore_idle':
        # Standing on GROUND_ROW = 52.0 with bright orange webbed feet clearly visible!
        idx = int(round(t * 4)) % 4
        breathe = 0.18 * bob
        stand_y = 5.05 if is_chick else 5.65
        R_b = art.rot_x(-0.08)
        torso_c = np.array([0.0, (stand_y + breathe) * sz, -0.35 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_wag=0.08 * bob, tail_lift=0.14)

        for side in (-1.0, 1.0):
            hip = torso_c + R_b @ np.array([side * 1.95 * sz, -2.25 * sz, 0.15 * sz])
            ank = np.array([side * 1.85 * sz, 1.85 * sz, -0.25 * sz])
            ft = np.array([side * 1.85 * sz, 0.55 * sz, 0.15 * sz])
            draw_webbed_foot(m, hip, ank, ft, sz)

        neck_base = torso_c + R_b @ np.array([0.0, 1.45 * sz, (3.15 if is_chick else 4.05) * sz])
        head_c = np.array([0.0, ((9.85 if is_chick else 11.45) + breathe) * sz, (3.25 if is_chick else 3.85) * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=(0.35 if is_chick else 0.65))
        R_h = art.rot_y(0.16 * math.sin(p)) @ art.rot_x(0.02)
        draw_duck_head(m, v, head_c, R_h, sz, blink=(idx == 3))

    elif kind == 'shore_waddle':
        # Charming 8-frame side-to-side Mallard waddle on bright orange webbed feet!
        bob2 = abs(math.sin(p))
        sway_x = 0.95 * math.sin(p)
        roll = -0.14 * math.sin(p)
        stand_y = 5.05 if is_chick else 5.65
        R_b = rot_z(roll) @ art.rot_x(-0.08)
        torso_c = np.array([sway_x * sz, (stand_y + 0.32 * bob2) * sz, -0.35 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_wag=-0.26 * math.sin(p), tail_lift=0.15)

        for s_i, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_i == 0 else 0.5)) % 1.0
            if c < 0.55:
                u = c / 0.55
                fz = (1.85 - 3.45 * u) * sz
                fy = 0.55 * sz
                f_pitch = 0.0
            else:
                u = (c - 0.55) / 0.45
                fz = (-1.60 + 3.45 * u) * sz
                fy = (0.55 + 1.85 * math.sin(u * math.pi)) * sz
                f_pitch = 0.35 * math.sin(u * math.pi)
            hip = torso_c + R_b @ np.array([side * 1.95 * sz, -2.25 * sz, 0.15 * sz])
            ft = np.array([(side * 1.95 + 0.35 * sway_x) * sz, fy, fz])
            ank = 0.45 * hip + 0.55 * ft + np.array([0.0, 0.65 * sz, -0.45 * sz])
            draw_webbed_foot(m, hip, ank, ft, sz, foot_rot=art.rot_x(f_pitch))

        neck_base = torso_c + R_b @ np.array([0.0, 1.45 * sz, (3.15 if is_chick else 4.05) * sz])
        head_c = np.array([
            0.45 * sway_x * sz,
            ((9.85 if is_chick else 11.45) + 0.28 * bob2) * sz,
            ((3.35 if is_chick else 4.05) + 0.35 * math.sin(p * 2.0)) * sz,
        ])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=(0.30 if is_chick else 0.55))
        R_h = art.rot_y(0.10 * math.sin(p)) @ rot_z(-0.45 * roll)
        draw_duck_head(m, v, head_c, R_h, sz)

    elif kind == 'shore_wing_flap':
        # 6 frames: rising up proudly on webbed feet with chest puffed and flapping open wings briskly to shake off water!
        idx = int(round(t * 6)) % 6
        proud = [0.55, 0.96, 1.0, 0.98, 0.92, 0.50][idx]
        stand_y = 5.05 if is_chick else 5.65
        R_b = art.rot_x(-0.08 - (0.38 if is_chick else 0.56) * proud)
        torso_c = np.array([0.0, (stand_y + (1.25 if is_chick else 1.75) * proud) * sz, (-0.35 - 0.50 * proud) * sz])
        draw_duck_torso_and_tail(
            m, v, torso_c, R_b, sz,
            tail_wag=0.18 * math.sin(p * 2.0),
            tail_lift=0.22,
            folded_wings=False,
        )

        # Standing tall on extended orange webbed feet!
        for side in (-1.0, 1.0):
            hip = torso_c + R_b @ np.array([side * 1.95 * sz, -2.25 * sz, -0.25 * sz])
            ank = np.array([side * 1.90 * sz, (2.15 + 0.45 * proud) * sz, -0.25 * sz])
            ft = np.array([side * 1.90 * sz, 0.55 * sz, 0.25 * sz])
            draw_webbed_foot(m, hip, ank, ft, sz)

        neck_base = torso_c + R_b @ np.array([0.0, 1.45 * sz, (3.15 if is_chick else 4.05) * sz])
        head_c = np.array([
            0.0,
            ((9.85 if is_chick else 11.55) + (2.35 if is_chick else 3.75) * proud) * sz,
            ((3.25 if is_chick else 3.65) - 0.95 * proud) * sz,
        ])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=0.30)
        draw_duck_head(m, v, head_c, art.rot_x(-0.14 * proud), sz, bill_open=(0.28 if idx in (1, 2) else 0.0))

        # Brisk open-wing strokes back & forth!
        lifts = [3.2, 8.8, 1.5, 9.2, 2.0, 4.0][idx]
        sweeps = [-0.5, -2.0, 2.6, -2.2, 2.4, 0.2][idx]
        folds = [0.35, 0.06, 0.08, 0.05, 0.10, 0.42][idx]
        for side in (-1.0, 1.0):
            sh = torso_c + R_b @ np.array([side * 2.85 * sz, 1.35 * sz, 1.25 * sz])
            draw_spread_duck_wing(m, v, side, sh, np.eye(3), span=13.8, lift=lifts, sweep_z=sweeps, wrist_fold=folds, sz=sz)

    elif kind == 'shore_sleep':
        # 6 frames: settled cozily onto grassy bank (GROUND_ROW = 52.0) with head turned back & bill tucked into back feathers!
        breathe = 0.14 * bob
        R_b = art.rot_x(-0.02)
        torso_c = np.array([0.0, (3.15 + breathe) * sz, -0.25 * sz])
        draw_duck_torso_and_tail(m, v, torso_c, R_b, sz, tail_lift=0.08)

        # Subtle glimpse of orange webbed foot edge nestled cozily under warm flank
        for side in (-1.0, 1.0):
            m.ell(np.array([side * 2.15 * sz, 0.55 * sz, 0.85 * sz]), (0.85 * sz, 0.45 * sz, 1.05 * sz), FEET)

        # Neck curved cozily back & head nestled snugly onto warm dorsal scapulars with bill tucked in!
        neck_base = torso_c + np.array([0.0, 1.05 * sz, 3.15 * sz])
        head_c = np.array([-0.45 * sz, (5.55 + breathe) * sz, 0.65 * sz])
        draw_neck_and_collar(m, v, neck_base, head_c, sz, curve_back=-0.45)
        R_h = art.rot_y(-2.70) @ art.rot_x(0.16)
        draw_duck_head(m, v, head_c, R_h, sz, blink=True, tucked_bill=True)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_duck(v, kind, (col - start) / n)
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
        (0, 0),   # E float_idle (green head, white ring, chestnut breast, Erpellocke, waterline!)
        (1, 0),   # SE float_idle
        (2, 0),   # S float_idle front view
        (1, 5),   # SE swim paddling glide
        (0, 10),  # E dabble tipping forward
        (0, 12),  # E dabble FULL UP-ENDING ('Bürzel hoch!' + kicking orange webbed feet!)
        (2, 12),  # S dabble UP-ENDING rear/front check!
        (1, 17),  # SE water_preen
        (1, 20),  # SE fly upstroke (blue-white wing speculum flash!)
        (1, 23),  # SE fly downstroke
        (2, 20),  # S fly wingspan margin check
        (0, 29),  # E water_takeoff splashing run with pattering orange webbed feet!
        (0, 34),  # E shore_idle standing on orange webbed feet!
        (1, 34),  # SE shore_idle
        (2, 40),  # S shore_waddle side-to-side waddle!
        (1, 47),  # SE shore_wing_flap proud upright wing-flap!
        (1, 53),  # SE shore_sleep cozily tucked bill on grassy bank!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bank_bg = np.array([46, 56, 44, 255], np.uint8)
    water_top = np.array([34, 56, 68, 255], np.uint8)
    water_sub = np.array([25, 42, 54, 255], np.uint8)

    for v in range(BUILDS_N):
        for ci, (d, col) in enumerate(picks):
            kind = next(x[0] for x in BLOCKS if x[1] <= col < x[1] + x[2])
            cell = grid[v * H:(v + 1) * H, ci * W:(ci + 1) * W]
            if kind in WATER_KINDS or kind == 'water_takeoff':
                cell[:52, :] = water_top
                cell[52:, :] = water_sub
                cell[52, ::3] = np.array([120, 168, 185, 255], np.uint8)
            else:
                cell[:, :] = bank_bg
                cell[52, ::4] = np.array([92, 108, 86, 255], np.uint8)
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
                print(f'duck build {done // 8}/{BUILDS_N}', flush=True)
    out_file = ROOT / 'assets/wildlife/duck.png'
    out_file.parent.mkdir(parents=True, exist_ok=True)
    save_png(out_file, sheet)
    print('Saved assets/wildlife/duck.png', sheet.shape)


if __name__ == '__main__':
    main()
