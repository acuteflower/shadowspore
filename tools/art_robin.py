#!/usr/bin/env python3
"""European Robin / Rotkehlchen (Erithacus rubecula) in the miniature 3D pixel-art pipeline (SS=4).
64x64 frames, dainty slender dark tarsi feet anchored on (32, 50); 62 columns (WildCorvid / WildMeadowBird layout);
3 builds x 8 facings = 24 rows (3968x1536).
No emissive parts; natural woodland songbird palettes.

Builds:
  0: Klassisches Rotkehlchen (warm olive-brown crown/back/wings/tail, soft powder-blue-grey margin framing a
     glowing tangerine-vermilion orange-red face, throat & upper breast, clean creamy-white lower belly)
  1: Aufgeplustertes Herbst-Rotkehlchen (1.07x extra-round fluffed-up sphere silhouette, rich burnt-persimmon
     orange-red breast, warm russet-olive back)
  2: Junges Rotkehlchen (0.92x dainty fledgling with warm golden-buff mottled back and soft apricot-orange
     emerging breast wash)

Columns (62):
  idle 0:4 (quick curtsy knee-dip bob + perky upward tail-flick!),
  peck 4:10 (darting forward to tug a tiny pink-brown earthworm / grub from soil & swallow it!),
  walk 10:16 (dainty rapid songbird hop-run),
  preen 16:22 (fluffing round orange breast & preening wing),
  watch 22:26 (Curious Gardener's Companion ~25 deg sideways head-cock tilt!),
  call 26:30 (Dawn/Dusk Song: head tilted upward, tiny bill open, orange throat puffed & pulsing, tail slightly drooped!),
  fly 30:38 (rapid whirring rounded-wing songbird flutter),
  land 38:44 (fluttering brake with fanned tail & dainty legs extended),
  takeoff 44:50 (quick upward spring into flutter),
  glide 50:54 (compact folded-wing songbird bound),
  hop 54:58 (bouncy two-footed robin hop!),
  roost 58:62 (adorable round fluffed-up sleeping puffball with bill tucked into orange breast feathers).

Usage: py -3 tools/art_robin.py [--preview-only] [--qa=path.png]
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

BACK, BREAST_RED, GREY_MARGIN, BELLY, DARK, BUFF_SPOT, WORM, EYE, GLINT = range(9)

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
    art.FW, art.FH, art.GROUND_ROW, art.SS, art.SCALE = W, H, 50.0, 4, 1.0
    art.TIDY_EYES = False
    art.DECAL_WEIGHT = {
        EYE: 4.1,
        GLINT: 4.9,
        WORM: 2.8,
        DARK: 1.65,
        BREAST_RED: 1.40,
        GREY_MARGIN: 1.35,
        BUFF_SPOT: 1.55,
    }
    art.ink_color = lambda mat: hexc('0c0a14' if mat in (DARK, EYE) else '1d141c')


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def materials(v: int) -> None:
    setup_art()
    if v == 0:
        # 0 Klassisches Rotkehlchen
        back = ['28201b', '4d3f2f', '786346', 'a38963']          # Warm olive-brown crown/back/wings/tail
        breast = ['7d2014', 'c23c18', 'f26722', 'ff9b42']        # Glowing tangerine-vermilion face, throat & breast
        grey_m = ['363c52', '58627d', '828fab', 'b0bed9']        # Soft powder-blue-grey margin framing orange bib
        belly = ['787587', 'aba8ba', 'dedce8', 'fcfaf5']         # Clean creamy-white lower belly
        buff = ['544330', '806748', 'ad8d64', 'd9b889']          # Subtle warm covert tips
    elif v == 1:
        # 1 Aufgeplustertes Herbst-Rotkehlchen (1.07x extra-round fluffed autumn sphere)
        back = ['2e1f19', '573b29', '855c3d', 'b07e56']          # Warm russet-olive back
        breast = ['6e1a14', 'ad3017', 'e0541d', 'fa8437']        # Rich burnt-persimmon orange-red breast
        grey_m = ['33384d', '545c78', '7c86a3', 'a8b3cf']        # Soft slate-blue-grey margin
        belly = ['757080', 'a6a1b2', 'dbd6e3', 'faf6ed']         # Fluffy warm cream belly
        buff = ['593d29', '875f3f', 'b58459', 'dfb080']          # Russet-buff wing bar tips
    else:
        # 2 Junges Rotkehlchen (0.92x dainty fledgling with golden-buff mottling & apricot breast wash)
        back = ['30231b', '59422d', '8a6843', 'ba9260']          # Warm golden-umber mantle
        breast = ['6e3820', 'a35b31', 'd4864c', 'f7b576']        # Soft apricot-orange emerging breast wash
        grey_m = ['423d4a', '696373', '948e9e', 'bfb9c9']        # Soft buff-grey neck margin
        belly = ['756e7a', 'a69fab', 'dbd4de', 'faf5eb']         # Soft buff-cream lower belly
        buff = ['6b5128', '9e793b', 'cfa455', 'f7d27e']          # Warm golden-buff fledgling speckles!

    ramps = [
        back,                                                    # 0 BACK
        breast,                                                  # 1 BREAST_RED
        grey_m,                                                  # 2 GREY_MARGIN
        belly,                                                   # 3 BELLY
        ['181421', '302840', '524669', '786894'],                # 4 DARK (slender dark plum-slate tarsi legs, fine bill, primary tips)
        buff,                                                    # 5 BUFF_SPOT
        ['662233', 'a13d52', 'db6b7e', 'ffa3b1'],                # 6 WORM (pink-rose earthworm / grub!)
        ['07060e', '110f1f', '221e36', '383352'],                # 7 EYE (liquid dark bead eye)
        ['9aa4b5', 'c4cedc', 'eaf0f8', 'ffffff'],                # 8 GLINT
    ]
    art.RAMPS = [[hexc(c) for c in r] for r in ramps]


def draw_spread_robin_wing(
    m: art.Model,
    side: float,
    shoulder: np.ndarray,
    span: float,
    lift: float,
    sweep_z: float,
    wrist_fold: float,
    sz: float,
) -> None:
    """Short, compact, rounded woodland-passerine wing for rapid whirring robin flutter!"""
    carpal = shoulder + np.array([
        side * span * (0.46 - 0.12 * wrist_fold) * sz,
        lift * (0.56 + 0.18 * wrist_fold) * sz,
        (1.05 - 0.55 * wrist_fold + 0.35 * sweep_z) * sz,
    ])
    tip = shoulder + np.array([
        side * span * (1.0 - 0.20 * wrist_fold) * sz,
        (lift - 0.95 * wrist_fold) * sz,
        (-1.25 - 0.75 * wrist_fold + sweep_z) * sz,
    ])

    m.limb(shoulder, carpal, 1.02 * sz, 0.82 * sz, BACK, step=0.42)
    m.limb(carpal, tip, 0.80 * sz, 0.48 * sz, BACK, step=0.42)

    # Rounded olive-brown secondaries + subtle buff covert bar
    n_sec = 5
    for i in range(n_sec):
        u = i / (n_sec - 1)
        le = shoulder * (1.0 - u) + carpal * u
        chord = (3.45 + 0.35 * math.sin(u * math.pi)) * sz * (1.0 - 0.15 * wrist_fold)
        te = le + np.array([side * 0.20 * u * sz, -0.28 * sz, -chord])
        m.limb(le, te, 0.78 * sz, 0.48 * sz, BACK, step=0.42)
        if i in (1, 3):
            m.ell(0.65 * le + 0.35 * te, (0.45 * sz, 0.36 * sz, 0.45 * sz), BUFF_SPOT)

    # Rounded passerine outer primaries (no hawk-like fingers — soft cup-shaped songbird wing!)
    n_pri = 5
    f_spread = 1.0 - 0.45 * wrist_fold
    for i in range(n_pri):
        u = (i + 0.15) / n_pri
        le = carpal * (1.0 - u) + tip * u
        plen = (3.65 - 0.55 * u + 0.45 * math.sin(u * math.pi)) * sz * (1.0 - 0.12 * wrist_fold)
        fan = -0.10 + 0.62 * u
        te = le + np.array([
            side * math.sin(fan + 0.25) * plen * 0.42 * f_spread,
            ((u - 0.45) * 0.32 * f_spread - 0.25 * wrist_fold) * sz,
            -math.cos(fan * 0.55) * plen,
        ])
        m.limb(le, te, 0.68 * sz, 0.42 * sz, DARK if i >= 2 else BACK, step=0.40)


def draw_dainty_leg(
    m: art.Model,
    hip: np.ndarray,
    foot: np.ndarray,
    sz: float,
    tucked: bool = False,
) -> None:
    """Delicate slender longish dark songbird tarsus & fine three-toed foot."""
    if tucked:
        m.ell(foot, (0.50 * sz, 0.44 * sz, 0.65 * sz), DARK)
        return
    # Avian intertarsal ('reverse knee') joint angled subtly backward so slender tarsi read cleanly!
    knee = 0.38 * hip + 0.62 * foot + np.array([0.0, 0.55 * sz, -0.62 * sz])
    m.limb(hip, knee, 0.50 * sz, 0.40 * sz, DARK, step=0.30)
    m.limb(knee, foot, 0.40 * sz, 0.35 * sz, DARK, step=0.28)
    # Fine dainty songbird toes resting flat on GROUND_ROW = 50.0
    for toe_x in (-0.56, 0.0, 0.56):
        m.limb(
            foot,
            foot + np.array([toe_x * sz, -0.04 * sz, 1.15 * sz]),
            0.30 * sz,
            0.22 * sz,
            DARK,
            step=0.26,
        )
    m.limb(foot, foot + np.array([0.0, -0.04 * sz, -0.78 * sz]), 0.28 * sz, 0.20 * sz, DARK, step=0.26)


def draw_earthworm(
    m: art.Model,
    p0: np.ndarray,
    p1: np.ndarray,
    p2: np.ndarray,
    sz: float,
) -> None:
    """Tiny curved pink-rose earthworm / grub tugged from soil in 'peck' (4:10)!"""
    pts = []
    for i in range(7):
        u = i / 6.0
        v = 1.0 - u
        pts.append((v * v) * p0 + 2.0 * v * u * p1 + (u * u) * p2)
    for i in range(len(pts) - 1):
        r = (0.50 if i in (2, 3) else 0.40) * sz
        m.limb(pts[i], pts[i + 1], r, r * 0.94, WORM, step=0.24)


def build_robin(v: int, kind: str, t: float) -> art.Model:
    materials(v)
    m = art.Model()
    # Plump round spherical songbird (~10-12 px body — noticeably daintier & rounder than crows/jays!):
    # v=0 Klassisch (1.0x), v=1 Aufgeplustertes Herbst-Rotkehlchen (1.07x), v=2 Junges Rotkehlchen (0.92x)
    base_sz = 1.16
    sz = base_sz * [1.0, 1.07, 0.92][v]
    base_fluff = 1.08 if v == 1 else 1.0
    p = t * math.tau
    bob = math.sin(p)

    flying = kind in ('fly', 'land', 'takeoff', 'glide')

    # Compact round spherical body + head nestled directly together above slender longish dark Tarsi legs!
    body_x = 0.0
    body_y = 6.55 * sz
    body_z = -0.15 * sz
    body_pitch = 0.0       # +rot_x pitches +z (breast) down & -z (rump) up
    fluff = base_fluff

    head_off = np.array([0.0, 1.80 * sz, 1.25 * sz])
    head_pitch = 0.02
    head_yaw = 0.0
    head_roll = 0.0
    throat_puff = 0.0
    beak_open = 0.0
    tucked_sleep = False
    blink = False

    # Perky narrow olive-brown tail: +tail_pitch cocks tail UP (+y), -tail_pitch droops tail DOWN (-y)!
    tail_pitch = 0.45
    tail_fan = 1.0
    tail_wag = 0.0
    wing_preen_side = 0.0
    hop_wing = 0.0

    # Slender longish dark Tarsi feet anchored cleanly on GROUND_ROW = 50.0 (y ~ 0.42*sz)
    foot_L = np.array([-1.15 * sz, 0.42 * sz, 0.22 * sz])
    foot_R = np.array([1.15 * sz, 0.42 * sz, 0.22 * sz])
    feet_tucked = False

    worm_pts: tuple[np.ndarray, np.ndarray, np.ndarray] | None = None

    if kind == 'idle':
        # Characteristic robin quick curtsy knee-dip bob + perky upward tail-flick!
        idx = int(round(t * 4)) % 4
        dip = [0.0, 1.0, 0.28, 0.0][idx]
        flick = [0.44, 0.98, 0.70, 0.45][idx]
        body_y = (6.55 - 1.45 * dip) * sz
        body_pitch = 0.12 * dip
        tail_pitch = flick
        head_yaw = [0.0, 0.08, -0.06, 0.12][idx]
        blink = (idx == 3)

    elif kind == 'peck':
        # 6 frames: darting forward to tug a tiny pink-brown earthworm / grub from the soil and swallow it!
        idx = int(round(t * 6)) % 6
        if idx == 0:
            # Dart forward & bow sharply toward soil
            body_y, body_z = 5.55 * sz, 0.75 * sz
            body_pitch = 0.48
            head_off = np.array([0.0, 0.95 * sz, 1.95 * sz])
            head_pitch = 0.55
            tail_pitch = 0.68
        elif idx == 1:
            # Strike soil & clamp pink earthworm emerging at ground level!
            body_y, body_z = 4.95 * sz, 1.15 * sz
            body_pitch = 0.66
            head_off = np.array([0.0, 0.35 * sz, 2.25 * sz])
            head_pitch = 0.72
            beak_open = 0.35
            tail_pitch = 0.78
            worm_pts = (
                np.array([0.0, 0.32 * sz, 4.75 * sz]),
                np.array([0.45 * sz, 1.25 * sz, 5.05 * sz]),
                np.array([0.0, 2.35 * sz, 4.65 * sz]),
            )
        elif idx == 2:
            # Classic robin lean-back tug! Legs braced, stretching taut pink earthworm up out of soil!
            body_y, body_z = 6.75 * sz, -0.45 * sz
            body_pitch = -0.22
            head_off = np.array([0.0, 1.85 * sz, 1.15 * sz])
            head_pitch = 0.22
            beak_open = 0.32
            tail_pitch = 0.25
            foot_L = np.array([-1.18 * sz, 0.42 * sz, 1.05 * sz])
            foot_R = np.array([1.18 * sz, 0.42 * sz, 1.05 * sz])
            worm_pts = (
                np.array([0.0, 0.35 * sz, 4.05 * sz]),
                np.array([0.65 * sz, 3.65 * sz, 4.45 * sz]),
                np.array([0.0, 7.15 * sz, 3.95 * sz]),
            )
        elif idx == 3:
            # Worm snaps free! Upright proud hold with wriggling curved pink worm in bill!
            body_y, body_z = 6.85 * sz, -0.20 * sz
            head_off = np.array([0.0, 2.00 * sz, 1.25 * sz])
            head_pitch = -0.06
            beak_open = 0.36
            tail_pitch = 0.58
            worm_pts = (
                np.array([-1.35 * sz, 7.25 * sz, 4.65 * sz]),
                np.array([0.0, 8.75 * sz, 4.85 * sz]),
                np.array([1.45 * sz, 6.95 * sz, 4.55 * sz]),
            )
        elif idx == 4:
            # Toss head up to gulp worm down!
            body_y = 6.70 * sz
            head_off = np.array([0.0, 2.10 * sz, 1.05 * sz])
            head_pitch = -0.44
            beak_open = 0.62
            throat_puff = 0.45
            tail_pitch = 0.46
            worm_pts = (
                np.array([0.0, 9.45 * sz, 3.55 * sz]),
                np.array([0.30 * sz, 10.35 * sz, 4.05 * sz]),
                np.array([-0.20 * sz, 11.05 * sz, 4.35 * sz]),
            )
        else:
            # Satisfied swallow & perky tail-flick
            body_y = 6.55 * sz
            tail_pitch = 0.68

    elif kind == 'walk':
        # 6-frame dainty rapid songbird hop-run across grass!
        for s_i, side in enumerate((-1.0, 1.0)):
            c = (t + (0.0 if s_i == 0 else 0.5)) % 1.0
            if c < 0.52:
                u = c / 0.52
                fz = (1.45 - 2.65 * u) * sz
                fy = 0.42 * sz
            else:
                u = (c - 0.52) / 0.48
                fz = (-1.20 + 2.65 * u) * sz
                fy = (0.42 + 1.65 * math.sin(u * math.pi)) * sz
            if s_i == 0:
                foot_L = np.array([side * 1.15 * sz, fy, fz])
            else:
                foot_R = np.array([side * 1.15 * sz, fy, fz])
        bounce = abs(math.sin(p))
        body_y = (6.45 + 0.55 * bounce) * sz
        body_z = 0.25 * sz
        body_pitch = 0.14
        body_x = 0.22 * math.sin(p) * sz
        tail_pitch = 0.52 + 0.18 * bounce

    elif kind == 'preen':
        # 6 frames: fluffing round orange breast & turning head to preen wing!
        idx = int(round(t * 6)) % 6
        turn = [0.45, 0.95, 1.0, 0.92, 0.35, 0.0][idx]
        fluff = base_fluff * (1.16 if idx in (3, 4) else 1.08)
        head_yaw = -1.35 * turn
        head_pitch = 0.38 * turn + (0.12 if idx == 2 else 0.0)
        head_roll = 0.18 * turn
        head_off = np.array([-0.45 * turn * sz, (1.75 - 0.35 * turn) * sz, (1.25 - 1.15 * turn) * sz])
        wing_preen_side = -1.0 if idx in (1, 2, 3) else 0.0
        tail_fan = 1.30 if idx == 4 else 1.0
        tail_pitch = 0.48
        blink = (idx == 2)

    elif kind == 'watch':
        # 4 frames: Curious Gardener's Companion Tilt — standing tall on slender legs,
        # head cocked inquisitively sideways (~25-30 deg tilt) watching a nearby digger!
        idx = int(round(t * 4)) % 4
        body_y = 7.15 * sz
        body_pitch = -0.08
        rolls = [0.42, 0.55, 0.48, -0.48][idx]   # ~25-32 deg inquisitive sideways head-cock!
        yaws = [0.16, 0.24, 0.18, -0.22][idx]
        side_shift = 0.42 if rolls > 0 else -0.42
        head_off = np.array([side_shift * sz, 2.05 * sz, 1.35 * sz])
        head_roll = rolls
        head_yaw = yaws
        head_pitch = 0.08
        tail_pitch = 0.58

    elif kind == 'call':
        # 4 frames: Dawn/Dusk Song!
        # Perched proud with head tilted upward, tiny bill open, orange throat puffed & pulsing in song, tail slightly drooped!
        idx = int(round(t * 4)) % 4
        sing = [0.45, 1.0, 0.88, 0.55][idx]
        body_y = (6.80 + 0.25 * sing) * sz
        body_pitch = -0.18 * sing
        head_off = np.array([0.0, (2.00 + 0.25 * sing) * sz, (1.15 - 0.15 * sing) * sz])
        head_pitch = -0.50 * sing          # Head tilted proudly UPWARD toward sky!
        beak_open = 1.05 * sing            # Tiny dark insectivore bill open wide in song!
        throat_puff = sing                 # Glowing orange throat puffed & pulsing!
        tail_pitch = -0.35 * sing - 0.08   # Tail slightly drooped (-rot_x drops -z tail downward)!

    elif kind == 'hop':
        # 4-frame bouncy two-footed robin hop!
        idx = int(round(t * 4)) % 4
        if idx == 0:
            # Quick spring crouch on slender knees
            body_y = 5.25 * sz
            body_pitch = 0.18
            tail_pitch = 0.68
            hop_wing = 0.25
        elif idx in (1, 2):
            # Cheerful high two-footed airborne hop arc!
            lift = 3.85 if idx == 1 else 2.95
            body_y = (6.65 + lift) * sz
            body_z = (0.35 if idx == 1 else 0.55) * sz
            body_pitch = -0.06 if idx == 1 else 0.08
            foot_L = np.array([-1.15 * sz, (2.65 if idx == 1 else 2.05) * sz, 0.85 * sz])
            foot_R = np.array([1.15 * sz, (2.65 if idx == 1 else 2.05) * sz, 0.85 * sz])
            hop_wing = 0.78 if idx == 1 else 0.52
            tail_pitch = 0.55
            tail_fan = 1.25
        else:
            # Light landing curtsy + tail-flick!
            body_y = 5.85 * sz
            tail_pitch = 0.82
            hop_wing = 0.15

    elif kind == 'roost':
        # 4-frame adorable round fluffed-up sleeping puffball with bill tucked into orange breast feathers!
        fluff = base_fluff * 1.18
        body_y = (5.05 + 0.10 * bob) * sz
        body_z = 0.0
        head_off = np.array([-0.22 * sz, 1.10 * sz, 0.55 * sz])
        head_pitch = 0.42
        head_yaw = -0.35
        tucked_sleep = True
        blink = True
        tail_pitch = 0.18
        foot_L = np.array([-1.05 * sz, 0.42 * sz, 0.25 * sz])
        foot_R = np.array([1.05 * sz, 0.42 * sz, 0.25 * sz])

    elif flying:
        if kind == 'fly':
            # 8-frame rapid whirring rounded-wing songbird flutter
            idx = int(round(t * 8)) % 8
            b_lift = [-0.25, 0.0, 0.35, 0.55, 0.20, -0.10, -0.25, -0.30][idx]
            body_y = (14.2 + b_lift) * sz
            body_z = -0.35 * sz
            body_pitch = 0.10
            head_off = np.array([0.0, 1.45 * sz, 1.85 * sz])
            head_pitch = -0.05
            tail_pitch = 0.08
            tail_fan = 1.25
            feet_tucked = True
            foot_L = np.array([-0.95 * sz, body_y - 2.45 * sz, -0.45 * sz])
            foot_R = np.array([0.95 * sz, body_y - 2.45 * sz, -0.45 * sz])

        elif kind == 'glide':
            # 4-frame compact folded-wing songbird bound ('Wellflug' torpedo bound!)
            body_y = (14.5 + 0.45 * bob) * sz
            body_z = -0.25 * sz
            body_pitch = 0.08 - 0.12 * bob
            head_off = np.array([0.0, 1.35 * sz, 1.95 * sz])
            head_pitch = -0.04
            tail_pitch = 0.04
            tail_fan = 0.85
            feet_tucked = True
            foot_L = np.array([-0.90 * sz, body_y - 2.35 * sz, -0.55 * sz])
            foot_R = np.array([0.90 * sz, body_y - 2.35 * sz, -0.55 * sz])

        elif kind == 'takeoff':
            # 6-frame quick upward spring into flutter
            idx = int(round(t * 6)) % 6
            if idx == 0:
                body_y = 4.95 * sz
                body_pitch = -0.18
                tail_pitch = 0.65
                tail_fan = 1.35
            else:
                u = ease(idx / 5.0)
                body_y = (7.8 + 6.8 * u) * sz
                body_pitch = -0.24 + 0.30 * u
                head_off = np.array([0.0, 1.65 * sz, 1.65 * sz])
                tail_pitch = 0.25 * (1.0 - u)
                tail_fan = 1.35
                feet_tucked = (idx >= 3)
                fy = (1.6 + 8.8 * u) * sz
                foot_L = np.array([-1.02 * sz, fy, (0.45 - 0.85 * u) * sz])
                foot_R = np.array([1.02 * sz, fy, (0.45 - 0.85 * u) * sz])

        elif kind == 'land':
            # 6-frame fluttering brake with fanned tail & dainty legs extended!
            idx = int(round(t * 6)) % 6
            flare = [0.90, 1.0, 0.92, 0.65, 0.32, 0.0][idx]
            climb = [4.6, 3.6, 2.4, 1.2, 0.3, 0.0][idx] * sz
            body_y = 5.95 * sz + climb
            body_pitch = -0.32 * flare
            head_off = np.array([0.0, 1.90 * sz, (1.25 - 0.25 * flare) * sz])
            tail_pitch = -0.38 * flare + 0.42 * (1.0 - flare)
            tail_fan = 1.0 + 0.75 * flare
            fy = 0.42 * sz + climb * 0.62
            fz = (0.22 + 1.55 * flare) * sz
            foot_L = np.array([-1.12 * sz, fy, fz])
            foot_R = np.array([1.12 * sz, fy, fz])

    # ---- Plump Spherical Robin Body (~10-12 px chubby tennis-ball silhouette!) ----
    R_b = art.rot_x(body_pitch)
    torso_c = np.array([body_x, body_y, body_z])

    def bp(x: float, y: float, z: float) -> np.ndarray:
        return torso_c + R_b @ (np.array([x, y, z], float) * sz)

    # Core olive-brown dorsal/rump sphere
    m.ell(bp(0.0, 0.20, -0.25), (3.08 * sz * fluff, 2.92 * sz * fluff, 3.25 * sz * fluff), BACK, R=R_b)
    # Clean creamy-white lower belly & undertail cushion (leaves ~2.5 px of slender dark tarsi legs exposed below!)
    m.ell(bp(0.0, -0.78, 0.15), (2.75 * sz * fluff, 1.98 * sz * fluff, 2.85 * sz * fluff), BELLY, R=R_b)
    # Delicate powder-blue-grey lateral margin framing the sides of the glowing orange breast!
    for side in (-1.0, 1.0):
        m.ell(bp(side * 2.15 * fluff, 0.65, 0.45), (1.08 * sz, 1.95 * sz * fluff, 1.75 * sz), GREY_MARGIN, R=R_b)
    # Broad, glowing tangerine-vermilion upper breast cushion!
    puff_r = 1.0 + 0.22 * throat_puff
    m.ell(
        bp(0.0, 0.65 + 0.15 * throat_puff, 1.38 + 0.35 * throat_puff),
        (2.85 * sz * fluff * puff_r, 2.25 * sz * fluff * puff_r, 2.28 * sz * puff_r),
        BREAST_RED,
        R=R_b,
    )

    if v == 2:
        # Juvenile golden-buff mottling flecks on mantle & breast sides
        for side in (-1.0, 1.0):
            m.ell(bp(side * 1.35, 1.95, -0.85), (0.62 * sz, 0.52 * sz, 0.72 * sz), BUFF_SPOT, R=R_b)
            m.ell(bp(side * 1.95, 0.35, 1.55), (0.55 * sz, 0.55 * sz, 0.58 * sz), BUFF_SPOT, R=R_b)

    # ---- Perky Narrow Olive-Brown Songbird Tail ----
    t_base = bp(0.0, 0.25, -2.95)
    for f_i in (-1, 0, 1):
        t_len = (3.85 - abs(f_i) * 0.25) * sz
        f_yaw = -f_i * 0.14 * tail_fan + tail_wag
        t_rot = R_b @ art.rot_y(f_yaw) @ art.rot_x(tail_pitch)
        t_tip = t_base + t_rot @ np.array([0.0, 0.0, -t_len])
        m.limb(t_base, t_tip, 0.68 * sz, 0.42 * sz, BACK if f_i == 0 else DARK, step=0.38)

    # ---- Wings: Folded Dainty Wing Coverts, Bounded Torpedo Tuck, OR Whirring Songbird Flutter ----
    for side in (-1.0, 1.0):
        sh = bp(side * 2.45 * fluff, 0.75, 0.35)
        folded_now = (
            not flying
            or kind == 'glide'
            or (kind == 'takeoff' and int(round(t * 6)) % 6 == 0)
            or (kind == 'land' and int(round(t * 6)) % 6 == 5)
        )
        if folded_now:
            preen_open = 1.0 if side * wing_preen_side > 0 else 0.0
            flick = hop_wing + 0.65 * preen_open + (0.22 if kind == 'glide' else 0.0)
            if hop_wing > 0.55:
                draw_spread_robin_wing(m, side, sh, span=6.8, lift=3.8 * hop_wing, sweep_z=0.4, wrist_fold=0.32, sz=sz)
            else:
                # Folded robin wing often droops its tip slightly below tail base in perky ground stance!
                w_rot = R_b @ art.rot_y(side * (0.08 + 0.26 * flick)) @ art.rot_x(-0.22 + 0.14 * flick)
                wc = bp(side * (2.55 * fluff + 0.45 * flick), 0.05 + 0.25 * flick, -0.75)
                m.ell(wc, (0.95 * sz, 1.75 * sz, 2.65 * sz), BACK, R=w_rot)
                # Tiny warm buff greater-covert wing bar dots
                m.ell(wc + w_rot @ (np.array([side * 0.48, 0.35, 0.45]) * sz), (0.42 * sz, 0.42 * sz, 0.62 * sz), BUFF_SPOT, R=w_rot)
                # Dark primary wingtips extending neatly back
                m.ell(wc + w_rot @ (np.array([-side * 0.15, -0.45, -2.15]) * sz), (0.58 * sz, 0.65 * sz, 1.25 * sz), DARK, R=w_rot)
        else:
            max_span = 9.4
            if kind == 'fly':
                idx = int(round(t * 8)) % 8
                lifts = [6.8, 3.2, -1.6, -5.2, -2.4, 1.8, 5.2, 7.2][idx]
                folds = [0.06, 0.0, 0.0, 0.10, 0.44, 0.52, 0.28, 0.10][idx]
                sweeps = [-0.8, 0.5, 1.4, 1.8, 0.3, -0.6, -1.1, -0.9][idx]
                draw_spread_robin_wing(m, side, sh, max_span, lifts, sweeps, folds, sz)
            elif kind == 'takeoff':
                idx = int(round(t * 6)) % 6
                lifts = [0.0, 7.2, 2.0, -4.8, 1.4, 6.4][idx]
                folds = [0.0, 0.05, 0.0, 0.08, 0.38, 0.12][idx]
                sweeps = [0.0, -0.8, 1.2, 1.8, -0.4, -0.9][idx]
                draw_spread_robin_wing(m, side, sh, max_span, lifts, sweeps, folds, sz)
            elif kind == 'land':
                idx = int(round(t * 6)) % 6
                lifts = [5.6, 2.2, 6.2, 3.4, 1.6, 0.0][idx]
                folds = [0.08, 0.04, 0.12, 0.32, 0.64, 1.0][idx]
                sweeps = [1.6, 2.2, 1.5, 0.8, -0.2, 0.0][idx]
                draw_spread_robin_wing(m, side, sh, max_span * 0.94, lifts, sweeps, folds, sz)

    # ---- Delicate Slender Dark Songbird Legs ('Tarsi') ----
    for s_i, side in enumerate((-1.0, 1.0)):
        ft = foot_L if s_i == 0 else foot_R
        hip = bp(side * 1.12, -1.85, -0.05)
        draw_dainty_leg(m, hip, ft, sz, tucked=feet_tucked)

    # ---- Nestled Spherical Robin Head, Glowing Orange Face/Throat, Liquid Bead Eye & Fine Bill ----
    head_c = torso_c + R_b @ head_off
    R_h = R_b @ art.rot_y(head_yaw) @ art.rot_x(head_pitch) @ rot_z(head_roll)

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return head_c + R_h @ (np.array([x, y, z], float) * sz)

    # Olive-brown crown & nape sphere
    m.ell(hp(0.0, 0.28, -0.18), (2.48 * sz * (1.05 if v == 1 else 1.0), 2.35 * sz, 2.48 * sz), BACK, R=R_h)
    # Delicate powder-blue-grey cheek/nape border framing the orange face mask!
    for side in (-1.0, 1.0):
        m.ell(hp(side * 1.95, 0.05, -0.28), (0.85 * sz, 1.55 * sz, 1.45 * sz), GREY_MARGIN, R=R_h)
    # Broad, glowing tangerine-vermilion forehead, lores, cheeks & throat mask!
    m.ell(hp(0.0, -0.22, 0.82), (2.32 * sz, 1.85 * sz, 2.05 * sz), BREAST_RED, R=R_h)
    m.ell(hp(0.0, 0.35, 1.12), (2.22 * sz, 1.35 * sz, 1.72 * sz), BREAST_RED, R=R_h)

    if throat_puff > 0.08:
        # Pulsing puffed orange song-throat in 'call' (Dawn/Dusk Song)!
        m.ell(
            hp(0.0, -1.05 - 0.15 * throat_puff, 1.45 + 0.65 * throat_puff),
            ((1.75 + 0.55 * throat_puff) * sz, (1.40 + 0.45 * throat_puff) * sz, (1.60 + 0.55 * throat_puff) * sz),
            BREAST_RED,
            R=R_h,
        )

    if v == 2:
        # Juvenile crown/nape golden-buff speckles
        m.ell(hp(0.0, 1.95, -0.25), (0.75 * sz, 0.45 * sz, 0.75 * sz), BUFF_SPOT, R=R_h)

    # Tiny fine pointed dark insectivore bill (tucked into orange breast when roosting!)
    if not tucked_sleep:
        if beak_open > 0.08:
            up_tip = hp(0.0, 0.35 + 0.55 * beak_open, 4.15)
            lo_tip = hp(0.0, -0.45 - 0.65 * beak_open, 3.95)
            m.limb(hp(0.0, 0.12, 2.25), up_tip, 0.44 * sz, 0.26 * sz, DARK, step=0.26)
            m.limb(hp(0.0, -0.24, 2.20), lo_tip, 0.42 * sz, 0.24 * sz, DARK, step=0.26)
            # Warm pink-orange inner song-gape!
            m.ell(hp(0.0, -0.06, 2.95), (0.38 * sz, 0.42 * beak_open * sz, 0.52 * sz), WORM, R=R_h)
        else:
            m.limb(hp(0.0, -0.04, 2.25), hp(0.0, -0.10, 4.05), 0.46 * sz, 0.25 * sz, DARK, step=0.26)

    # Large, dark, expressive liquid bead eye + crisp white sparkle!
    for side in (-1.0, 1.0):
        eh = 0.18 if blink else 0.70
        m.ell(hp(side * 1.84, 0.38, 1.25), (0.58 * sz, eh * sz, 0.70 * sz), EYE, R=R_h)
        if not blink:
            m.ell(hp(side * 2.02, 0.64, 1.52), (0.26 * sz, 0.26 * sz, 0.26 * sz), GLINT, R=R_h)

    # Tiny pink-brown earthworm / grub during 'peck' (4:10)!
    if worm_pts is not None:
        draw_earthworm(m, worm_pts[0], worm_pts[1], worm_pts[2], sz)

    return m


def frame(v: int, d: int, col: int) -> np.ndarray:
    kind, start, n = next(x for x in BLOCKS if x[1] <= col < x[1] + x[2])
    m = build_robin(v, kind, (col - start) / n)
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
        (0, 0),   # E idle perky round stance + slender tarsi + cocked tail!
        (1, 0),   # SE idle (glowing orange breast, blue-grey margin, liquid bead eye!)
        (1, 1),   # SE idle curtsy knee-dip + upward tail-flick!
        (2, 0),   # S idle front spherical orange breast!
        (6, 0),   # N idle olive-brown back & tail
        (0, 5),   # E peck striking earthworm at soil
        (0, 6),   # E peck leaning back tugging taut pink earthworm!
        (1, 7),   # SE peck holding wriggling pink earthworm in bill!
        (1, 11),  # SE dainty hop-run walk
        (1, 18),  # SE preen fluffed orange breast
        (2, 23),  # S watch: Curious Gardener's Companion ~28 deg sideways head-cock tilt!
        (1, 23),  # SE watch sideways head-cock tilt!
        (0, 27),  # E call: Dawn/Dusk Song (head tilted up, open bill, puffed orange throat, drooped tail!)
        (1, 27),  # SE call Dawn/Dusk Song!
        (1, 30),  # SE fly rapid rounded-wing flutter upstroke
        (1, 33),  # SE fly downstroke
        (0, 39),  # E land braking flare with fanned tail & dainty legs extended
        (0, 51),  # E glide compact folded-wing songbird torpedo bound!
        (1, 55),  # SE hop bouncy two-footed robin hop!
        (1, 59),  # SE roost adorable round fluffed sleeping puffball!
    ]
    grid = np.zeros((BUILDS_N * H, len(picks) * W, 4), np.uint8)
    bg = np.array([38, 48, 42, 255], np.uint8)
    grid[:, :] = bg
    for v in range(BUILDS_N):
        for ci, (d, col) in enumerate(picks):
            cell = grid[v * H:(v + 1) * H, ci * W:(ci + 1) * W]
            cell[50, ::4] = np.array([86, 104, 82, 255], np.uint8)
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
                print(f'robin build {done // 8}/{BUILDS_N}', flush=True)
    out_file = ROOT / 'assets/wildlife/robin.png'
    out_file.parent.mkdir(parents=True, exist_ok=True)
    save_png(out_file, sheet)
    print('Saved assets/wildlife/robin.png', sheet.shape)


if __name__ == '__main__':
    main()
