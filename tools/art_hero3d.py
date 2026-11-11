"""The heroine, modelled from ellipsoids and rendered to pixel art (needs numpy: pip3 install numpy).

A tiny orthographic z-buffer renderer: every body part is an ellipsoid, shaded in flat bands,
sampled 4x and reduced to one palette colour per pixel, then inked. One model gives all eight
facings, the walk cycle, the idle breathing and the crouch.

Sheet (assets/characters/player.png): COLS x 16 frames of FW x FH, feet at (FW/2, GROUND_ROW).
  rows 0-7  facing E SE S SW W NW N NE (the order of Player.SECTOR), rows 8-15 the same crouched
  cols 0-5  walk cycle, cols 6-11 sprint cycle (contacts at 0 and 3 of each), cols 12-15 idle loop, cols 16-21 jog cycle (crouched rows: the sneak)
A second sheet, assets/characters/player_attack.png (8 rows = the sectors, ATTACK_COLS columns), holds the sword combo:
  per attack (forehand, backhand, thrust) 7 leg variants x 6 keyframes; the column is (attack * 7 + variant) * 6 + keyframe.
  Variant 0 stands planted (lunge, steps); variants 1-6 keep the legs in the walk cycle at that phase, so she can swing
  while walking. The sword arm (her right) is NOT drawn into the sheets: the game draws it from the shoulder to the
sword grip. data/hero_rig.json holds, per frame, that shoulder and the natural hand position.
"""
import math
import sys

import numpy as np

from gen_art import CLEAR, ROOT, hexc, write_png

FW, FH = 48, 56
GROUND_ROW = 51.0
SS = 4
PITCH = math.radians(26.0)
COSP, SINP = math.cos(PITCH), math.sin(PITCH)
SCALE = 0.92
WALK_FRAMES, RUN_FRAMES, IDLE_FRAMES, JOG_FRAMES = 6, 6, 4, 6
COLS = WALK_FRAMES + RUN_FRAMES + IDLE_FRAMES + JOG_FRAMES
ATTACK_STEPS, ATTACK_FRAMES = 3, 6
ATTACK_LEGS = 1 + WALK_FRAMES  # leg variants per keyframe: 0 = planted stance, 1-6 = the walk cycle's six phases
ATTACK_COLS = ATTACK_STEPS * ATTACK_LEGS * ATTACK_FRAMES

XHAT = np.array([1.0, 0.0, 0.0])
UHAT = np.array([0.0, COSP, -SINP])
WHAT = np.array([0.0, SINP, COSP])
LIGHT = np.array([-0.5, 0.72, 0.5])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# ------------------------------------------------------------------ materials (dark -> light)
HAIR, SKIN, LEATHER, VIOLET, GOLD, LEGGING, EYE, MOUTH, BLUSH, CRYSTAL, TEAL, BOOT, BLANKET = range(13)
COAT = 13
RAMPS = [
    ["8f84c2", "bdb3e4", "e9e3f7", "fffaf0"],  # hair: cool shade, warm white light
    ["d79a88", "efc0a8", "f9dcc6", "fff1e4"],  # skin
    ["09060f", "150f22", "2c2347", "6a5aa6"],  # black leather
    ["34185e", "6636ad", "9468ee", "cbaaff"],  # violet trim / lining
    ["6f5020", "b48a38", "e6c468", "fff0b0"],  # gold
    ["130e1e", "241b3a", "3a2e58", "5a4a88"],  # leggings
    ["2a1c52", "5f3bc9", "a77bff", "efe6ff"],  # eyes
    ["84405a", "b25873", "d98aa0", "f0b2c2"],  # mouth
    ["d58a86", "e5a39b", "f2bab0", "f8cfc6"],  # blush
    ["5a2fb0", "8a5cf0", "b99bff", "f0e6ff"],  # glowing crystal
    ["2a8c94", "3cc0c6", "78f4e6", "d0fff8"],  # teal lining
    ["1e1626", "372a40", "574560", "7d6a86"],  # boots: dusty plum leather
    ["2c1a30", "4b2c47", "6e4562", "96688a"],  # an old wool blanket (the hut's bed, tools/art_hero_wake.py)
    ["171020", "30203c", "503359", "795884"],  # muted plum coat, matched to Ellie's approved concept
]
RAMPS = [[hexc(c) for c in ramp] for ramp in RAMPS]
DECAL_WEIGHT = {EYE: 2.4, MOUTH: 2.0, BLUSH: 1.4, CRYSTAL: 1.8, TEAL: 1.6, GOLD: 1.3}


def ink_color(mat: int):
    r, g, b, _ = RAMPS[mat][0]
    k = 0.5 if mat in (HAIR, SKIN) else 0.55
    return (int(r * k), int(g * k * 0.95), int(b * k), 255)


# ------------------------------------------------------------------ primitives
class Prim:
    __slots__ = ("c", "r", "R", "mat", "kind", "tag", "clip", "rot")

    def __init__(self, c, r, R, mat, kind="", tag=0.0, clip=None, rot=False):
        self.c, self.r, self.R, self.mat, self.kind, self.tag, self.clip, self.rot = c, r, R, mat, kind, tag, clip, rot


def rot_y(a: float):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_x(a: float):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def frame_from(axis_y, hint):
    """Orthonormal basis whose y axis follows `axis_y`; z is as close to `hint` as possible."""
    ty = np.asarray(axis_y, float)
    ty = ty / np.linalg.norm(ty)
    tx = np.cross(ty, hint)
    if np.linalg.norm(tx) < 1e-6:
        tx = np.cross(ty, [1.0, 0.0, 0.0])
    tx = tx / np.linalg.norm(tx)
    tz = np.cross(tx, ty)
    return np.stack([tx, ty, tz], axis=1)  # columns = local axes


class Model:
    def __init__(self) -> None:
        self.prims: list[Prim] = []
        self.off = np.zeros(3)  # added to every primitive: lets the whole upper body shift (lunges, crouching)

    def ell(self, c, r, mat, R=None, kind="", tag=0.0, clip=None):
        self.prims.append(Prim(np.array(c, float) + self.off, np.array(r, float), np.eye(3) if R is None else R, mat, kind, tag, clip))

    def limb(self, p0, p1, r0, r1, mat, kind="", step=0.5):
        p0, p1 = np.array(p0, float), np.array(p1, float)
        n = max(2, int(np.linalg.norm(p1 - p0) / step))
        for i in range(n + 1):
            t = i / n
            r = r0 + (r1 - r0) * t
            self.ell(p0 + (p1 - p0) * t, (r, r, r), mat, kind=kind)

    def ribbon(self, pts, widths, thick, mat, hint, tag=0.0, kind="hair"):
        """Flat strip of hair/cloth following a polyline: a chain of flattened ellipsoids."""
        pts = [np.array(p, float) for p in pts]
        for i in range(len(pts) - 1):
            seg = pts[i + 1] - pts[i]
            length = np.linalg.norm(seg)
            n = max(1, int(length / 0.6))
            R = frame_from(seg, np.asarray(hint, float))
            for k in range(n):
                t = (i + (k + 0.5) / n) / (len(pts) - 1)
                w = np.interp(t, np.linspace(0, 1, len(widths)), widths)
                self.ell(pts[i] + seg * (k + 0.5) / n, (w, length / n * 0.95 + 0.25, thick), mat, R=R, kind=kind, tag=tag)

    def transform(self, yaw: float, dy: float) -> list[Prim]:
        Ry = rot_y(yaw)
        out = []
        for p in self.prims:
            c = Ry @ (p.c + np.array([0.0, dy, 0.0])) * SCALE
            out.append(Prim(c, p.r * SCALE, Ry @ p.R, p.mat, p.kind, p.tag, p.clip, p.rot))
        return out


# ------------------------------------------------------------------ blood
# The blood she loses is baked as a second set of sheets (player_blood.png ... with the same layout as the colour sheets): every pixel holds a
# THRESHOLD (0 = bloody first, 255 = never). The game shows the pixel as blood when her blood loss is above it, so the stains grow from the
# wound as she loses health, sit on the body (in model space: they turn with every facing), keep the shading of the cloth underneath and
# never touch the outline. `python3 tools/art_hero3d.py blood` writes them.
WANT_BLOOD = False
POINTS_ONLY = False  # tools/art_hero_jewelry.py: frame() returns only the rig points (fast), no pixels
LAST_BLOOD = None
LAST_BAND = None  # the bandage mask of the last blood render (per supersample: 1 = a pixel of the bandage), see bandage_mask
WOUND_AT = np.array([2.6, 28.2, 2.6])  # front left of the waist


def _hash3(m, scale):
    return (np.sin(np.floor(m * scale) @ np.array([127.1, 311.7, 74.7])) * 43758.5453) % 1.0


def blood_intensity(m, kind, mat):
    """0..1 how soon the points `m` (N, 3, model space) get bloody: the wound, drips running down from it, a smear round the waist, the
    tips of the hair, a trickle down the temple, a few specks."""
    x, y, z = m[:, 0], m[:, 1], m[:, 2]
    n = _hash3(m, 2.0)
    out = np.zeros(len(m))
    if kind == "hair":
        out = np.clip((31.0 - y) / 15.0, 0.0, 1.0) * (n * 1.0 - 0.3)
        out = np.maximum(out, np.where((x > 3.0) & (y > 43.0) & (z > 0.5), 0.35 * n + 0.1, 0.0))  # the lock at the temple
        return np.clip(out, 0.0, 1.0)
    if kind == "head":
        wob = 3.7 + 0.25 * np.sin(y * 1.3)
        trickle = (1.0 - np.abs(x - wob) / 0.8) * np.clip((47.0 - y) / 8.0, 0.0, 1.0) * (z > 2.0) * (y > 38.5)
        return np.clip(trickle * 0.9, 0.0, 1.0)
    core = 1.25 * (1.0 - np.linalg.norm(m - WOUND_AT, axis=1) / 3.6)
    halo = 0.55 * (1.0 - np.linalg.norm(m - WOUND_AT, axis=1) / 8.5) * (0.6 + 0.8 * n)
    wob = 2.6 + 0.8 * np.sin(y * 0.7)
    drip = (1.0 - np.abs(x - wob) / 1.7) * (1.0 - (28.2 - y) / 15.0) * (z > 0.3) * (y < 28.2) * (y > 12.0)
    smear = 0.45 * (1.0 - np.abs(y - 27.0) / 4.0) * (0.5 + 0.5 * n) * np.clip(0.4 + x / 6.0, 0.0, 1.0)
    specks = (_hash3(m, 1.3) - 0.86) * 7.0 * ((y > 8.0) & (y < 40.0))
    out = np.maximum.reduce([core, halo, drip * 0.9, smear, specks])
    return np.clip(out, 0.0, 1.0)


def bandage_mask(m, kind, mat):
    """1 where the points `m` (N, 3, model space) lie on the bandage: a slanted wrap round the waist, on the corset only. It is baked next to the blood
    (the alpha of a blood-map pixel is 254 instead of 255 there) and drawn by the sprite shader once the story bandages her (`Player.bandaged`)."""
    if kind != "corset":
        return np.zeros(len(m))
    x, y = m[:, 0], m[:, 1]
    lo = 26.9 + 0.5 * np.sin(x * 0.8)
    hi = 31.6 + 0.6 * np.sin(x * 0.7 + 1.0)
    return ((y > lo) & (y < hi)).astype(float)


def to_blood(bl, code, band=None):
    """The threshold sheet frame from the supersampled buffer (same solidity rule as to_pixels): rows of (t, t, t, 255), or transparent."""
    sub = bl.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    csub = code.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    opaque = (csub >= 0).sum(-1)
    mean = np.where(csub >= 0, sub, 0.0).sum(-1) / np.maximum(opaque, 1)
    band_mean = None
    if band is not None:
        bsub = band.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
        band_mean = np.where(csub >= 0, bsub, 0.0).sum(-1) / np.maximum(opaque, 1)
    rows = []
    for y in range(FH):
        row = []
        for x in range(FW):
            if opaque[y, x] >= 6:
                v = int(round(float(np.clip(mean[y, x], 0.0, 1.0)) * 255))
                row.append((v, v, v, 254 if band_mean is not None and band_mean[y, x] >= 0.5 else 255))
            else:
                row.append((255, 255, 255, 0))
        rows.append(row)
    return rows


# ------------------------------------------------------------------ rasteriser
def shade_band(lam: np.ndarray, kind: str, mat: int) -> np.ndarray:
    th = {HAIR: (-0.1, 0.18, 0.62), SKIN: (-0.2, 0.12, 0.55)}.get(mat, (0.06, 0.34, 0.7))
    return np.digitize(lam, th)


def render(prims: list[Prim], yaw=None, dy=0.0, blood_transform=None):
    Hs, Ws = FH * SS, FW * SS
    depth = np.full((Hs, Ws), -1e9)
    code = np.full((Hs, Ws), -1, dtype=np.int16)
    blood = np.full((Hs, Ws), 1.0) if yaw is not None else None
    bandage = np.zeros((Hs, Ws)) if yaw is not None else None
    ry_back = rot_y(-yaw) if yaw is not None else None
    for p in prims:
        cx = FW / 2 + p.c[0]
        cy = GROUND_ROW - (p.c[1] * COSP - p.c[2] * SINP)
        rr = float(p.r.max()) + 0.4
        x0, x1 = max(0, int((cx - rr) * SS)), min(Ws, int((cx + rr) * SS) + 1)
        y0, y1 = max(0, int((cy - rr) * SS)), min(Hs, int((cy + rr) * SS) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        a = (np.arange(x0, x1) + 0.5) / SS - FW / 2
        b = GROUND_ROW - (np.arange(y0, y1) + 0.5) / SS
        A, B = np.meshgrid(a, b)
        o = A[..., None] * XHAT + B[..., None] * UHAT
        M = np.diag(1.0 / p.r) @ p.R.T
        q0 = (o - p.c) @ M.T
        qd = M @ WHAT
        aa = qd @ qd
        bb = q0 @ qd
        cc = (q0 * q0).sum(-1) - 1.0
        disc = bb * bb - aa * cc
        ok = disc >= 0
        t = (-bb + np.sqrt(np.where(ok, disc, 0.0))) / aa
        q = q0 + t[..., None] * qd
        if p.clip is not None:
            ok &= p.clip(q)
        sub = depth[y0:y1, x0:x1]
        ok &= t > sub
        if not ok.any():
            continue
        n = (q / p.r) @ p.R.T
        n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        lam = 0.78 * (n @ LIGHT) + 0.22 * (0.5 + 0.5 * n[..., 1]) - 0.06
        mat = np.full(t.shape, p.mat, dtype=np.int16)
        band = shade_band(lam, p.kind, p.mat).astype(np.int16)
        if p.kind == "hair":
            stripe = (q[..., 0] * 1.6 + p.tag * 0.61) % 1.0 < 0.2
            band = np.where(stripe, np.maximum(band - 1, 0), band)
        elif p.kind == "head":
            mat, band = paint_face(q, mat, band)
        elif p.kind == "skirt":
            py = (o + t[..., None] * WHAT)[..., 1]
            trim = (q[..., 1] < -0.5) if p.rot else py < p.tag  # a body turned prone: the hem is the strand's lower part
            mat = np.where(trim, VIOLET, mat).astype(np.int16)
        elif p.kind == "corset":
            lace = (np.abs(q[..., 0]) < 0.11) & (q[..., 2] > 0.3)
            mat = np.where(lace, VIOLET, mat).astype(np.int16)
            band = np.where(lace, np.where((np.floor(q[..., 1] * 4.5) % 2) == 0, 3, 2), band)
        elif p.kind == "emit":
            band = np.maximum(band, 2)
        codes = mat * 4 + band
        sub[ok] = t[ok]
        cs = code[y0:y1, x0:x1]
        cs[ok] = codes[ok]
        if blood is not None:
            pts = (o + t[..., None] * WHAT)[ok]
            model_pts = (pts / SCALE) @ ry_back.T - np.array([0.0, dy, 0.0])
            if blood_transform is not None:
                model_pts = blood_transform(model_pts)
            inten = blood_intensity(model_pts, p.kind, p.mat)
            jitter = (_hash3(model_pts, 3.1) - 0.5) * 0.16
            blood[y0:y1, x0:x1][ok] = np.clip(1.0 - inten + jitter * (inten > 0.02), 0.0, 1.0)
            bandage[y0:y1, x0:x1][ok] = bandage_mask(model_pts, p.kind, p.mat)
    if blood is not None:
        global LAST_BAND
        LAST_BAND = bandage
        return depth, code, blood
    return depth, code


def paint_face(q, mat, band):
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    front = z > 0.35
    for sx in (-1, 1):
        ex = np.abs(x - sx * 0.38)
        eye = front & (ex < 0.14) & (np.abs(y - 0.02) < 0.23)
        lid = eye & (y > 0.1)
        mat = np.where(eye, EYE, mat)
        band = np.where(lid, 0, np.where(eye, 1, band))
        spark = front & (np.abs(x - sx * 0.38 - 0.03) < 0.04) & (np.abs(y + 0.04) < 0.06)
        band = np.where(spark & eye, 3, band)
        blush = front & (np.abs(x - sx * 0.55) < 0.15) & (np.abs(y + 0.3) < 0.09) & ~eye
        mat = np.where(blush, BLUSH, mat)
        band = np.where(blush, 1, band)
    mouth = front & (np.abs(x) < 0.13) & (np.abs(y + 0.56) < 0.055)
    mat = np.where(mouth, MOUTH, mat)
    band = np.where(mouth, 1, band)
    return mat.astype(np.int16), band.astype(np.int16)


def face_open(q):
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    opening = (z > -0.05) & (y < 0.55 - 0.22 * np.abs(x) ** 1.2) & (np.abs(x) < 0.97)
    return (y > -0.28) & ~opening


# ------------------------------------------------------------------ pixelise
def to_pixels(depth, code):
    k = len(RAMPS) * 4
    sub = code.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    dsub = depth.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    opaque = (sub >= 0).sum(-1)
    best = np.full((FH, FW), -1, dtype=np.int16)
    best_w = np.zeros((FH, FW))
    for v in range(k):
        w = (sub == v).sum(-1) * DECAL_WEIGHT.get(v // 4, 1.0)
        better = w > best_w
        best = np.where(better, v, best)
        best_w = np.where(better, w, best_w)
    solid = opaque >= 6
    best = np.where(solid, best, -1)
    dmean = np.where((sub >= 0), dsub, 0).sum(-1) / np.maximum(opaque, 1)

    # ink: pixels clearly behind a neighbour get their darkest shade (separates limbs, strands)
    ink = np.zeros((FH, FW), bool)
    for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        nb = np.roll(np.roll(dmean, dy, 0), dx, 1)
        nbs = np.roll(np.roll(solid, dy, 0), dx, 1)
        ink |= solid & nbs & (nb > dmean + 2.4)
    px = [[CLEAR] * FW for _ in range(FH)]
    for y in range(FH):
        for x in range(FW):
            v = int(best[y, x])
            if v >= 0:
                m, b = divmod(v, 4)
                if ink[y, x] and m not in (EYE, MOUTH, BLUSH):
                    b = 0
                px[y][x] = RAMPS[m][b]
    # outline: transparent pixels touching a drawn one
    out = [row[:] for row in px]
    for y in range(FH):
        for x in range(FW):
            if best[y, x] >= 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < FW and 0 <= ny < FH and best[ny, nx] >= 0:
                    out[y][x] = ink_color(int(best[ny, nx]) // 4)
                    break
    # ground shadow
    for y in range(FH):
        for x in range(FW):
            if out[y][x][3] == 0:
                ex = (x + 0.5 - FW / 2) / 8.5
                ey = (y + 0.5 - (GROUND_ROW + 0.5)) / 2.4
                if ex * ex + ey * ey <= 1.0:
                    out[y][x] = (0, 0, 0, 70)
    return out


# ------------------------------------------------------------------ the character
def ik2(root, target, l1: float, l2: float, pole):
    """Two-bone chain from `root` toward `target`; the middle joint bends toward `pole`.
    Returns (joint, end): the end stops short when the target is out of reach."""
    root = np.asarray(root, float)
    d = np.asarray(target, float) - root
    full = np.linalg.norm(d)
    dirv = d / full if full > 1e-6 else np.array([0.0, -1.0, 0.0])
    dist = min(max(full, 0.5), l1 + l2 - 0.01)
    x = (dist * dist + l1 * l1 - l2 * l2) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = np.asarray(pole, float)
    p = p - dirv * (p @ dirv)
    if np.linalg.norm(p) < 1e-6:
        p = np.cross(dirv, [1.0, 0.0, 0.0])
    p = p / np.linalg.norm(p)
    return root + dirv * x + p * h, root + dirv * dist


# The sprint, one leg over the six frames of the cycle: (thigh, knee flex, foot pitch; + = toes down). Foot strike, stance, toe-off (the flight begins),
# heel up, knee through, high knee (flight). The other leg is three frames ahead, so frames 0 and 3 are the two foot strikes.
SPRINT_LEG = [(0.38, 0.30, -0.12), (-0.18, 0.42, 0.0), (-0.66, 0.06, 0.85), (-0.42, 1.50, 1.15), (0.40, 1.75, 0.6), (1.02, 1.05, 0.15)]
SPRINT_LIFT = 1.4  # how far the flight carries the body above the height of the foot strike
# The jog (Higgsfield side-view reference, 2026-11-11): the easy trot between the walk and the sprint, same six-frame layout. The foot lands under
# the hips on a soft knee, pushes off behind, the heel kicks up behind to about knee height, the knee comes through at medium height; a short flight.
JOG_LEG = [(0.30, 0.24, -0.05), (-0.06, 0.44, 0.0), (-0.44, 0.14, 0.72), (-0.30, 1.45, 0.95), (0.30, 1.40, 0.45), (0.60, 0.72, 0.08)]
JOG_LIFT = 0.7


def sprint_leg(phase: float, keys=None):
    """(thigh, flex, foot pitch) of a sprinting (or, with `keys` = JOG_LEG, jogging) leg at `phase` (radians, 0 = its foot strike), eased."""
    keys = SPRINT_LEG if keys is None else keys
    u = (phase / (2 * math.pi)) % 1.0 * 6.0
    i = int(u) % 6
    k = u - int(u)
    k = k * k * (3 - 2 * k)
    a, b = keys[i], keys[(i + 1) % 6]
    return tuple(a[j] + (b[j] - a[j]) * k for j in range(3))


# The sneak (crouched rows): a stalking prowl, not a squat. The hips sit low over a long, lunge-like stride, the torso leans far forward, each foot is
# set down ball first and rolled flat, the other one peels off the ground heel first and glides through close to the earth. The foot's path is
# the key (the stance foot slides back at body speed, so it never skates), the leg is solved from it: `sneak_leg(phase)` -> (thigh, flex, foot pitch).
SNEAK_STRIDE = 9.2  # half stride: how far the stance foot travels in front of and behind the hip
SNEAK_PITCH = [(0.00, 0.16), (0.08, 0.0), (0.30, 0.0), (0.42, 0.30), (0.50, 0.78), (0.65, 0.55), (0.85, 0.30), (1.00, 0.16)]  # (cycle, toes down)


def sneak_foot(u: float):
    """The ankle relative to the hip for a leg `u` (0..1) into its cycle, 0 = foot set down in front: (forward, depth below the hip)."""
    if u < 0.5:  # stance: the foot rests, the body glides over it; the knee takes the weight in the middle, the heel lifts at the end
        k = u / 0.5
        return SNEAK_STRIDE * (1.0 - 2.0 * k), 18.2 - 0.8 * math.sin(math.pi * k) - 1.9 * max(0.0, (k - 0.72) / 0.28) ** 2
    k = (u - 0.5) / 0.5  # swing: peel off, glide through low, place softly
    e = k * k * (3.0 - 2.0 * k)
    return SNEAK_STRIDE * (-1.0 + 2.0 * e), (16.3 + 1.9 * e) - 3.4 * math.sin(math.pi * k) ** 1.2


def sneak_leg(phase: float):
    """(thigh, flex, foot pitch) of a sneaking leg at `phase` (radians, 0 = foot set down in front), solved from `sneak_foot`."""
    u = (phase / (2 * math.pi)) % 1.0
    z, depth = sneak_foot(u)
    d = min(math.hypot(z, depth), 21.3)
    a = math.acos(max(-1.0, min(1.0, (11.5 ** 2 + d * d - 10.0 ** 2) / (2 * 11.5 * d))))
    thigh = math.atan2(z, depth) + a
    kz, ky = 11.5 * math.sin(thigh), 11.5 * math.cos(thigh)
    shank = math.atan2(z - kz, depth - ky)
    pitch = SNEAK_PITCH[-1][1]
    for (u0, v0), (u1, v1) in zip(SNEAK_PITCH, SNEAK_PITCH[1:]):
        if u0 <= u <= u1:
            k = (u - u0) / (u1 - u0)
            pitch = v0 + (v1 - v0) * (k * k * (3 - 2 * k))
            break
    return thigh, thigh - shank, pitch


# The walk (Higgsfield reference, 2026-11-11): an even, symmetric stride. Like the sneak it is driven by the foot's path, not by joint angles, so the
# stance foot never skates and both steps are identical: heel strike in front (toes up), the foot rolls flat and glides straight back at body speed,
# the heel peels up and the toes push off, the leg swings through with the knee lifted and reaches forward again. The hips only ride a gentle,
# even bob (lowest at the double support, highest as the legs pass); the upper body stays calm (see `build`).
WALK_STRIDE = 7.4  # half stride: the stance foot lands this far in front of the hip
WALK_DUTY = 0.6  # share of the cycle a foot is on the ground (0.5..0.6 both feet touch)
WALK_REACH = 21.48  # the leading leg lands straight (thigh + shank = 21.5)
WALK_TOP = 23.85  # the hips never ride higher than this: the stance knee is only just soft as the legs pass (24 = standing straight)
WALK_PITCH = [(0.00, -0.30), (0.12, 0.0), (0.42, 0.0), (0.60, 0.80), (0.70, 0.75), (0.84, 0.2), (1.00, -0.30)]  # (cycle, toes down)


def walk_foot(u: float):
    """A walking foot `u` (0..1) into its cycle, 0 = heel strike: (forward of the hip, ankle lift above its grounded height, foot pitch)."""
    u %= 1.0
    if u < WALK_DUTY:
        z = WALK_STRIDE * (1.0 - 4.0 * u)  # glides back at body speed: the other foot strikes at u = 0.5, this one is then at -STRIDE
        k = max(0.0, (u - 0.44) / (WALK_DUTY - 0.44))
        lift = 2.0 * k * k  # the heel peels up late (the trailing leg stays straight at the other foot's strike), the toes stay down
    else:
        k = (u - WALK_DUTY) / (1.0 - WALK_DUTY)
        e = k * k * (3 - 2 * k)
        back = WALK_STRIDE * (1.0 - 4.0 * WALK_DUTY)
        z = back + (WALK_STRIDE - back) * e
        lift = 2.0 * (1.0 - e) + 1.9 * math.exp(-((k - 0.3) / 0.24) ** 2)  # the heel kicks up behind just after the push, the foot passes low
    pitch = WALK_PITCH[-1][1]
    for (u0, v0), (u1, v1) in zip(WALK_PITCH, WALK_PITCH[1:]):
        if u0 <= u <= u1:
            s = (u - u0) / (u1 - u0)
            pitch = v0 + (v1 - v0) * (s * s * (3 - 2 * s))
            break
    return z, lift, pitch


def walk_height(phase: float) -> float:
    """Hip height above the ground for the walk at `phase` (radians, the right foot strikes at 0): as high as the grounded legs allow."""
    h = 99.0
    for ph in (phase, phase + math.pi):
        u = (ph / (2 * math.pi)) % 1.0
        if u < WALK_DUTY:
            z, lift, _ = walk_foot(u)
            h = min(h, 2.5 + lift + math.sqrt(max(WALK_REACH ** 2 - z * z, 1.0)))
    return min(h, WALK_TOP)


def P(twist, lean, pz, feet, hand_r, hand_l, hair, flare=0.0):
    """One attack keyframe. twist/lean: upper body (radians, + = turned to her left / forward),
    pz: how far the pelvis moved forward, feet: ((x, z, lift) left, right), hands: model-space
    targets, hair: how far the hair tips lag (x, y, z), flare: skirt lift."""
    return {"twist": twist, "lean": lean, "pz": pz, "feet": feet, "hand_r": hand_r, "hand_l": hand_l, "hair": hair, "flare": flare}


def pose_legs(pose):
    """Legs for a keyframe: feet are planted where the pose says, the hips sink as far as the stance needs."""
    pz = pose["pz"]
    hips = [np.array([2.5, 0.0, pz + 0.2]), np.array([-2.5, 0.0, pz + 0.2])]
    ankles = [np.array([f[0], 2.5 + f[2], f[1]]) for f in pose["feet"]]
    hy = 24.0
    for hip, ank in zip(hips, ankles):
        horiz2 = (ank[0] - hip[0]) ** 2 + (ank[2] - hip[2]) ** 2
        hy = min(hy, ank[1] + math.sqrt(max(21.2 ** 2 - horiz2, 1.0)))
    legs = []
    for hip, ank in zip(hips, ankles):
        hip = hip + np.array([0.0, hy, 0.0])
        knee, end = ik2(hip, ank, 11.5, 10.0, (0.0, 0.0, 1.0))
        legs.append((hip, knee, end, 0.0, 0.0))
    return legs, hy - 24.0


def A(twist, lean, pz, feet, hand_r, hand_l, hair, flare=0.0, roll=0.0, look=0.7):
    """A combo keyframe: like P, but her eyes stay on the target (the head turns back by `look` x the twist) and the shoulders may tilt (`roll`)."""
    pose = P(twist, lean, pz, feet, hand_r, hand_l, hair, flare)
    pose["head_yaw"] = -look * twist
    if roll:
        pose["roll"] = roll
    return pose


# The sword combo, one block per step: wind-up pose (0), strike (1-2), follow-through (3), recovery (4-5).
# Step 1 is a forehand (right to left), step 2 a backhand (left to right), step 3 a lunging thrust. Every strike is a whole-body move: she coils
# against the cut with her weight on the back foot, steps into it, the hips lead and the shoulders over-turn in the follow-through, the free arm
# is thrown out as a counterweight, hair and coat whip after the turn, and her head stays on the target throughout.
ATTACK_POSES = [
    [
        A(-0.95, -0.10, -1.6, ((3.4, 3.0, 0), (-3.4, -4.5, 0)), (-9.0, 33.0, -3.5), (6.0, 32.0, 7.5), (-2.2, 0.4, 0.8), 0.0, 0.08),
        A(-0.30, 0.06, 0.6, ((3.2, 4.5, 0.8), (-3.2, -3.8, 0)), (-7.5, 32.0, 4.5), (6.5, 31.0, 3.0), (2.2, 0.8, -0.2), 0.12),
        A(0.35, 0.16, 1.8, ((3.2, 6.2, 0), (-3.2, -3.6, 0.5)), (-0.5, 32.0, 9.5), (7.5, 32.0, -2.0), (3.4, 1.2, -0.5), 0.25),
        A(0.90, 0.22, 2.6, ((3.2, 6.8, 0), (-3.2, -4.0, 0.3)), (5.0, 30.5, 7.5), (8.5, 35.0, -4.5), (4.2, 1.4, -0.8), 0.38, -0.10),
        A(0.55, 0.12, 1.8, ((3.0, 5.6, 0), (-3.0, -1.8, 0)), (3.5, 29.0, 6.5), (7.0, 31.5, -1.5), (-1.8, 0.4, 0.4), 0.15),
        P(0.1, 0.03, 0.6, ((2.8, 3.0, 0), (-2.8, -0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.4, 0.0, 0.0)),
    ],
    [
        A(0.90, -0.06, -0.6, ((3.2, 4.5, 0), (-3.2, -2.5, 0)), (5.5, 31.0, 5.0), (8.5, 34.0, -3.5), (-2.2, 0.5, 0.4), 0.0, -0.08),
        A(0.25, 0.06, 0.9, ((3.2, 3.4, 0), (-3.2, 0.5, 0.8)), (1.5, 32.0, 9.5), (7.0, 33.0, -2.0), (2.0, 0.8, 0.0), 0.12),
        A(-0.40, 0.14, 1.8, ((3.2, 1.5, 0.3), (-3.2, 5.2, 0)), (-5.0, 32.0, 7.5), (6.5, 31.0, 1.5), (-3.0, 1.1, -0.3), 0.25),
        A(-0.95, 0.20, 2.4, ((3.2, -0.6, 0.3), (-3.2, 6.4, 0)), (-9.5, 31.0, 2.0), (6.0, 32.5, 6.0), (-4.2, 1.3, -0.6), 0.38, 0.10),
        A(-0.55, 0.11, 1.6, ((3.0, 0.8, 0), (-3.0, 5.0, 0)), (-7.5, 29.5, 2.0), (5.5, 30.0, 3.5), (1.6, 0.4, 0.4), 0.15),
        P(-0.05, 0.03, 0.5, ((2.8, 0.5, 0), (-2.8, 3.0, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (-0.4, 0.0, 0.0)),
    ],
    [
        A(-0.90, -0.26, -2.6, ((3.5, 3.0, 0), (-3.4, -6.0, 0)), (-6.0, 29.5, -4.5), (4.5, 34.0, 8.0), (0.8, 0.2, 2.2)),
        A(-0.50, 0.00, 0.0, ((3.5, 5.0, 1.0), (-3.4, -5.0, 0)), (-5.0, 30.5, 3.0), (5.0, 33.0, 5.0), (0.8, 0.5, 0.6)),
        A(-0.05, 0.26, 3.0, ((3.0, 9.0, 0), (-3.0, -5.0, 0)), (-2.8, 31.5, 11.5), (7.0, 33.0, -1.5), (0.0, 1.0, -2.0), 0.15),
        A(0.30, 0.36, 4.0, ((3.0, 10.5, 0), (-3.0, -5.0, 0)), (-2.0, 32.5, 13.5), (7.5, 34.5, -5.0), (-0.5, 1.5, -3.2), 0.30),
        A(0.15, 0.22, 3.0, ((3.0, 9.0, 0), (-3.0, -4.0, 0)), (-3.0, 30.5, 9.0), (6.5, 32.0, -2.5), (0.6, 0.5, -0.8), 0.10),
        P(0.0, 0.03, 0.8, ((2.8, 4.0, 0), (-2.8, -1.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.0, 0.0, 0.0)),
    ],
]


# The picking animation (berries, herbs): one second, PICK_FRAMES frames sampled from this timeline of
# key poses (time 0..1, eased in between). She leans toward the plant, the left hand parts the leaves,
# the right hand reaches in and plucks (the grab is at about 0.34 s), pulls back, and both hands cup the
# harvest for a moment before she straightens up. Legs stay planted (a wide stance sinks the hips).
PICK_FRAMES = 12
PICK_KEYS = [
    (0.00, P(0.0, 0.06, 0.0, ((3.0, 2.5, 0), (-3.0, -1.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.0, 0.0, 0.0))),
    (0.16, P(0.3, 0.38, 2.6, ((3.0, 6.5, 0), (-3.0, -4.5, 0)), (-3.5, 28.5, 11.0), (5.0, 28.0, 8.5), (1.2, 0.8, 0.8), 0.05)),
    (0.32, P(0.36, 0.46, 3.2, ((3.0, 7.0, 0), (-3.0, -5.0, 0)), (-2.4, 27.0, 12.5), (5.0, 27.5, 10.0), (1.8, 1.0, 1.1), 0.08)),
    (0.44, P(0.2, 0.28, 2.0, ((3.0, 6.0, 0), (-3.0, -4.0, 0)), (-4.0, 27.5, 7.0), (5.0, 27.0, 6.5), (0.5, 0.6, 0.0), 0.04)),
    (0.62, P(0.04, 0.14, 0.7, ((3.0, 3.5, 0), (-3.0, -2.0, 0)), (-1.5, 27.0, 5.5), (2.5, 26.5, 5.5), (-0.6, 0.3, 0.2))),
    (0.78, P(0.02, 0.1, 0.4, ((3.0, 3.0, 0), (-3.0, -1.5, 0)), (-1.0, 28.0, 5.0), (2.0, 27.5, 5.0), (-0.3, 0.1, 0.1))),
    (1.00, P(0.0, 0.03, 0.0, ((2.8, 3.0, 0), (-2.8, -0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.0, 0.0, 0.0))),
]


def lerp_pose(a, b, k):
    mix = lambda u, v: np.asarray(u, float) * (1 - k) + np.asarray(v, float) * k  # noqa: E731
    result = {"twist": float(mix(a["twist"], b["twist"])), "lean": float(mix(a["lean"], b["lean"])),
            "pz": float(mix(a["pz"], b["pz"])), "feet": tuple(tuple(mix(x, y)) for x, y in zip(a["feet"], b["feet"])),
            "hand_r": tuple(mix(a["hand_r"], b["hand_r"])), "hand_l": tuple(mix(a["hand_l"], b["hand_l"])),
            "hair": tuple(mix(a["hair"], b["hair"])), "flare": float(mix(a["flare"], b["flare"]))}
    if "head_yaw" in a or "head_yaw" in b:
        result["head_yaw"] = float(mix(a.get("head_yaw", 0.0), b.get("head_yaw", 0.0)))
    if "roll" in a or "roll" in b:
        result["roll"] = float(mix(a.get("roll", 0.0), b.get("roll", 0.0)))
    return result


def timeline_pose(keys, t: float):
    """The pose at time t (0..1) on a timeline of key poses (eased between keys)."""
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return lerp_pose(a, b, k * k * (3 - 2 * k))
    return keys[-1][1]


def pick_pose(t: float):
    return timeline_pose(PICK_KEYS, t)


# Eating (a berry), a bit showy: she flicks the berry into the air with a thumb, leans back to catch it in
# her mouth (the game draws the berry's flight: launched at 0.20 s, bitten at 0.48 s), chomps with a fist
# pump, chews three times, swallows with her arms a little out and flips her hair back. One second.
REST_R, REST_L = (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0)
STAND = ((2.8, 3.0, 0), (-2.8, -0.5, 0))
EAT_KEYS = [
    (0.00, P(0.0, 0.02, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
    (0.10, P(0.06, 0.04, 0.0, STAND, (-3.5, 33.0, 6.5), (4.5, 27.0, 2.0), (0.2, 0.1, 0.1))),
    (0.17, P(0.08, 0.12, 0.5, STAND, (-3.8, 30.5, 6.0), (4.5, 27.0, 2.0), (0.4, 0.3, 0.2))),
    (0.24, P(0.05, -0.10, -0.2, STAND, (-2.0, 41.5, 7.5), (5.0, 29.0, 3.0), (-0.8, -0.2, -0.6))),
    (0.34, P(0.0, -0.22, -0.5, STAND, (-5.0, 28.0, 2.5), (5.5, 29.0, 2.0), (-1.6, -0.5, -1.2), 0.08)),
    (0.44, P(0.0, -0.20, -0.5, STAND, (-5.2, 27.5, 2.2), (5.5, 28.5, 2.0), (-1.7, -0.5, -1.3), 0.08)),
    (0.52, P(0.1, 0.16, 0.8, STAND, (-3.4, 33.5, 5.0), (4.2, 28.0, 3.0), (1.3, 0.9, 0.9), 0.04)),
    (0.60, P(0.08, 0.05, 0.3, STAND, (-3.3, 34.5, 5.0), (4.2, 28.0, 3.0), (0.3, 0.2, 0.1))),
    (0.68, P(0.08, 0.12, 0.5, STAND, (-3.3, 34.0, 5.0), (4.2, 28.0, 3.0), (0.8, 0.6, 0.5))),
    (0.76, P(0.06, 0.05, 0.2, STAND, (-3.4, 33.0, 4.8), (4.2, 27.5, 2.8), (0.3, 0.2, 0.1))),
    (0.85, P(-0.08, -0.12, -0.3, STAND, (-8.0, 31.0, 1.5), (8.0, 31.0, 1.5), (-1.1, -0.4, -0.7), 0.14)),
    (0.93, P(0.15, 0.04, 0.1, STAND, (-5.0, 27.0, 2.0), REST_L, (2.4, 0.9, 0.5), 0.05)),
    (1.00, P(0.0, 0.02, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
]


# Pulling a root out of the ground (carrot, beet): one second like the other actions. She steps in with a wide stance,
# gets both hands into the leaves, braces low, strains (a tremble), and at about 0.5 s the root gives: she is thrown
# back off balance (the back foot slips), staggers a step holding it up, finds her balance and shakes the earth off.
# The game spawns the root and a burst of crumbs at PULL_GRAB_TIME. `python3 tools/art_hero3d.py pullonly` rewrites
# player_pull.png, player_pull_blood.png and the "pull" entries of data/hero_rig.json; `pull out.png <sector>` is a contact sheet.
PULL_KEYS = [
    (0.00, P(0.0, 0.06, 0.0, ((3.0, 2.5, 0), (-3.0, -1.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.0, 0.0, 0.0))),
    (0.12, P(0.08, 0.42, 2.8, ((3.0, 6.0, 0), (-3.0, -5.0, 0)), (-0.5, 27.5, 12.0), (2.0, 27.5, 12.0), (1.2, 0.8, 0.8), 0.05)),
    (0.24, P(0.06, 0.50, 3.4, ((3.2, 7.0, 0), (-3.2, -6.0, 0)), (-0.6, 26.5, 12.8), (1.8, 26.5, 12.8), (1.6, 1.0, 1.1), 0.08)),
    (0.36, P(0.04, 0.36, 2.2, ((3.2, 7.0, 0), (-3.2, -6.0, 0)), (-0.6, 28.8, 11.0), (1.8, 28.8, 11.0), (0.8, 0.6, 0.4), 0.06)),
    (0.44, P(0.07, 0.42, 2.6, ((3.2, 7.0, 0), (-3.2, -6.0, 0)), (-0.6, 28.0, 11.6), (1.8, 28.0, 11.6), (1.0, 0.6, 0.6), 0.07)),
    (0.52, P(-0.08, -0.30, -0.8, ((3.0, 4.0, 0), (-3.0, -8.5, 0.6)), (-1.5, 38.0, 7.0), (1.8, 38.0, 7.0), (-1.6, -0.5, -1.4), 0.16)),
    (0.62, P(-0.05, -0.22, -1.0, ((3.0, 2.0, 0.4), (-3.0, -9.0, 0)), (-1.2, 40.0, 6.0), (1.8, 39.0, 6.0), (-1.0, -0.3, -0.9), 0.12)),
    (0.74, P(0.0, -0.05, 0.0, ((3.0, 2.5, 0), (-3.0, -5.0, 0)), (-1.2, 34.0, 8.0), (1.8, 34.0, 8.0), (-0.3, 0.1, -0.3), 0.06)),
    (0.88, P(0.03, 0.08, 0.2, ((2.9, 3.0, 0), (-2.9, -2.5, 0)), (-1.5, 30.0, 8.0), (2.0, 29.0, 7.0), (0.3, 0.2, 0.2), 0.03)),
    (1.00, P(0.0, 0.03, 0.0, ((2.8, 3.0, 0), (-2.8, -0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.0, 0.0, 0.0))),
]


# Touching a waystone statue (E at the goddess): one second like the other actions. She raises both hands, lays the palms flat on the stone at about 0.45 s
# (the game wakes the statue there), keeps them there (the game holds the frames 5-6 until the statue's light has run over it) and then draws back.
# `python3 tools/art_hero3d.py touchonly` writes player_touch.png, player_touch_blood.png and the "touch" entries of data/hero_rig.json.
TOUCH_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
    (0.16, P(0.05, 0.06, 0.3, STAND, (-4.5, 30.5, 7.5), (5.0, 30.0, 7.0), (0.2, 0.1, 0.1))),
    (0.34, P(0.06, 0.14, 1.0, STAND, (-3.0, 34.0, 13.0), (3.6, 34.2, 12.6), (0.6, 0.4, 0.3))),
    (0.44, P(0.06, 0.18, 1.5, STAND, (-2.8, 34.5, 14.2), (3.4, 34.8, 13.8), (1.0, 0.6, 0.4), 0.03)),
    (0.62, P(0.05, 0.17, 1.4, STAND, (-2.8, 34.4, 14.0), (3.4, 34.6, 13.6), (0.8, 0.5, 0.3), 0.03)),
    (0.80, P(0.03, 0.08, 0.5, STAND, (-4.5, 30.0, 8.0), (5.0, 29.5, 7.5), (-0.3, 0.1, 0.0))),
    (1.00, P(0.0, 0.03, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
]


# Holding out food to a wild bird (E at a crow or raven that has come close): one second like the other actions. She sinks into a low, wide
# crouch without hurry, the left hand rests on the knee, the right arm reaches forward and low with the palm up (the game draws the morsel in it).
# The pose is held at about 0.5 s until the bird has decided (the game keeps frame 6 up to four seconds), then the hand draws back and she
# rises. `python3 tools/art_hero3d.py feedonly` writes player_feed.png, player_feed_blood.png and the "feed" entries of data/hero_rig.json;
# `feed out.png <sector>` is a contact sheet.
FEED_LOW = ((3.0, 7.0, 0), (-3.0, -5.5, 0))
FEED_KEYS = [
    (0.00, P(0.0, 0.03, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
    (0.15, P(0.10, 0.22, 1.2, ((3.0, 4.0, 0), (-3.0, -3.0, 0)), (-4.0, 22.0, 5.0), (4.5, 22.0, 3.0), (0.6, 0.4, 0.4), 0.03)),
    (0.32, P(0.18, 0.40, 2.8, FEED_LOW, (-2.5, 17.0, 12.0), (4.0, 15.0, 5.5), (1.2, 0.8, 0.8), 0.05)),
    (0.46, P(0.20, 0.46, 3.2, FEED_LOW, (-1.8, 14.5, 15.0), (4.0, 14.0, 5.5), (1.6, 1.0, 1.0), 0.06)),
    (0.56, P(0.20, 0.47, 3.3, FEED_LOW, (-1.8, 14.3, 15.6), (4.0, 14.0, 5.6), (1.6, 1.0, 1.0), 0.06)),
    (0.72, P(0.10, 0.26, 1.8, ((3.0, 5.0, 0), (-3.0, -3.5, 0)), (-3.0, 20.0, 6.0), (4.2, 20.0, 3.0), (0.6, 0.4, 0.4), 0.03)),
    (0.88, P(0.03, 0.10, 0.4, STAND, (-4.5, 25.0, 3.0), (4.5, 26.0, 1.5), (0.0, 0.0, 0.0))),
    (1.00, P(0.0, 0.03, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
]


def write_feed():
    """Only the feeding animation: colour sheet, blood thresholds and rig entries."""
    import json
    global WANT_BLOOD, frame
    rows, shoulders, hands, _m = pick_sheet(FEED_KEYS)
    write_png(ROOT / "characters" / "player_feed.png", PICK_FRAMES * FW, 8 * FH, paste(rows, PICK_FRAMES, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"feed_cols": PICK_FRAMES, "feed_shoulder": shoulders, "feed_hand": hands})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    WANT_BLOOD = True
    real_frame, collected = frame, []

    def collecting(*args, **kwargs):
        result = real_frame(*args, **kwargs)
        collected.append(LAST_BLOOD)
        return result

    frame = collecting
    pick_sheet(FEED_KEYS)
    frame = real_frame
    WANT_BLOOD = False
    brows = [collected[r * PICK_FRAMES:(r + 1) * PICK_FRAMES] for r in range(8)]
    write_png(ROOT / "characters" / "player_feed_blood.png", PICK_FRAMES * FW, 8 * FH, paste(brows, PICK_FRAMES, 8))


# Drinking a potion (docs/alchemie_konzept.md): quick enough for a fight, 0.6 s in the game (the same 12 frames as the one-second actions, played faster).
# The right hand pulls the vial from the belt, brings it up (the cork is flicked off with the thumb at about 0.18), she tips her head back and drinks
# in one draught (the potion takes effect at 0.5 = 0.30 s), lowers it, tosses the empty vial back over her shoulder and wipes her mouth with the
# back of her left hand. Seven leg variants like eating, so she can walk while she drinks. The game draws the vial (DrinkEffect) at the rig hand.
# `python3 tools/art_hero3d.py drinkonly` writes player_drink.png, player_drink_blood.png and the "drink" entries of data/hero_rig.json;
# `drink out.png <sector>` is a contact sheet.
DRINK_KEYS = [
    (0.00, P(0.0, 0.02, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
    (0.12, P(0.10, 0.06, 0.2, STAND, (-6.0, 22.5, 1.0), (4.8, 26.0, 1.5), (0.3, 0.1, 0.1))),
    (0.24, P(0.04, 0.06, 0.2, STAND, (-2.6, 35.5, 6.5), (5.0, 27.5, 2.5), (0.6, 0.2, 0.3))),
    (0.36, P(0.0, -0.20, -0.4, STAND, (-1.2, 44.5, 5.2), (6.0, 29.0, 2.5), (-1.3, -0.4, -1.0), 0.05)),
    (0.50, P(0.0, -0.26, -0.5, STAND, (-0.9, 45.5, 4.6), (6.2, 29.5, 2.5), (-1.7, -0.5, -1.3), 0.06)),
    (0.62, P(0.04, -0.04, 0.0, STAND, (-3.2, 37.5, 6.0), (5.2, 28.0, 2.5), (-0.6, -0.2, -0.4))),
    (0.74, P(-0.30, 0.02, 0.0, STAND, (-8.0, 37.0, -3.5), (5.0, 27.5, 2.5), (0.8, 0.3, 0.4), 0.04)),
    (0.86, P(0.08, 0.04, 0.1, STAND, (-5.2, 27.0, 2.0), (1.6, 42.5, 5.2), (0.4, 0.2, 0.2))),
    (1.00, P(0.0, 0.02, 0.0, STAND, REST_R, REST_L, (0.0, 0.0, 0.0))),
]


def write_drink():
    """Only the drinking animation: colour sheet, blood thresholds and rig entries (7 leg variants like eating)."""
    import json
    global WANT_BLOOD, frame
    rows, shoulders, hands, mouths = pick_sheet(DRINK_KEYS, ATTACK_LEGS)
    cols = PICK_FRAMES * ATTACK_LEGS
    write_png(ROOT / "characters" / "player_drink.png", cols * FW, 8 * FH, paste(rows, cols, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"drink_cols": PICK_FRAMES, "drink_variants": ATTACK_LEGS, "drink_shoulder": shoulders, "drink_hand": hands, "drink_mouth": mouths})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    WANT_BLOOD = True
    real_frame, collected = frame, []

    def collecting(*args, **kwargs):
        result = real_frame(*args, **kwargs)
        collected.append(LAST_BLOOD)
        return result

    frame = collecting
    pick_sheet(DRINK_KEYS, ATTACK_LEGS)
    frame = real_frame
    WANT_BLOOD = False
    brows = [collected[r * cols:(r + 1) * cols] for r in range(8)]
    write_png(ROOT / "characters" / "player_drink_blood.png", cols * FW, 8 * FH, paste(brows, cols, 8))


def write_touch():
    """Only the touch animation: colour sheet, blood thresholds and rig entries."""
    import json
    global WANT_BLOOD, frame
    rows, shoulders, hands, _m = pick_sheet(TOUCH_KEYS)
    write_png(ROOT / "characters" / "player_touch.png", PICK_FRAMES * FW, 8 * FH, paste(rows, PICK_FRAMES, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"touch_cols": PICK_FRAMES, "touch_shoulder": shoulders, "touch_hand": hands})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    WANT_BLOOD = True
    real_frame, collected = frame, []

    def collecting(*args, **kwargs):
        result = real_frame(*args, **kwargs)
        collected.append(LAST_BLOOD)
        return result

    frame = collecting
    pick_sheet(TOUCH_KEYS)
    frame = real_frame
    WANT_BLOOD = False
    brows = [collected[r * PICK_FRAMES:(r + 1) * PICK_FRAMES] for r in range(8)]
    write_png(ROOT / "characters" / "player_touch_blood.png", PICK_FRAMES * FW, 8 * FH, paste(brows, PICK_FRAMES, 8))


def write_pull():
    """Only the pull animation: colour sheet, blood thresholds and rig entries (a few seconds)."""
    import json
    global WANT_BLOOD, frame
    rows, shoulders, hands, _m = pick_sheet(PULL_KEYS)
    write_png(ROOT / "characters" / "player_pull.png", PICK_FRAMES * FW, 8 * FH, paste(rows, PICK_FRAMES, 8))
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    rig = json.loads(rig_path.read_text())
    rig.update({"pull_cols": PICK_FRAMES, "pull_shoulder": shoulders, "pull_hand": hands})
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    WANT_BLOOD = True
    real_frame, collected = frame, []

    def collecting(*args, **kwargs):
        result = real_frame(*args, **kwargs)
        collected.append(LAST_BLOOD)
        return result

    frame = collecting
    pick_sheet(PULL_KEYS)
    frame = real_frame
    WANT_BLOOD = False
    brows = [collected[r * PICK_FRAMES:(r + 1) * PICK_FRAMES] for r in range(8)]
    write_png(ROOT / "characters" / "player_pull_blood.png", PICK_FRAMES * FW, 8 * FH, paste(brows, PICK_FRAMES, 8))


def build(t: float, mode: str, crouch: bool, pose=None) -> Model:
    """t in [0,1) is the loop phase; mode 'walk', 'run' or 'idle'; `pose` (an attack keyframe) overrides it all."""
    m = Model()
    w = 2 * math.pi * t
    running = mode in ("run", "jog")
    walking = mode in ("walk", "run", "jog")
    jog = mode == "jog"  # the jog runs the sprint's code with its own keys and gentler amplitudes (gk)
    gk = 0.6 if jog else 1.0
    gait_keys = JOG_LEG if jog else SPRINT_LEG
    mi = 1.0 if running else 0.0
    twist = pose["twist"] if pose else 0.0
    # --- natural body mechanics of the free loops (no pose): the pelvis turns with the stride and shifts over the standing leg, the standing hip
    # rides high, the shoulders counter-turn and tilt against the hips, the head stays on its line. Standing, she rests her weight on her left leg.
    free = pose is None
    cw, sw = math.cos(w), math.sin(w)
    pel_yaw = shift_x = hip_dy = sh_roll = head_yaw_free = 0.0
    hip_rest = (0.0, 0.0)  # extra height of the left / right hip
    sprint = free and running  # the sprint loop: a real run with a flight phase (keys in SPRINT_LEG)
    sneak = free and crouch  # the crouched loops: a stalking prowl (SNEAK_* above)
    if sprint:
        cr = math.cos(w + 0.45)
        pel_yaw = -0.22 * gk * cr
        twist = 0.30 * gk * cr
        shift_x = 0.3 * gk * sw
        sh_roll = -0.05 * gk * sw
        head_yaw_free = -0.85 * twist
    elif sneak:
        if walking:  # the hips turn a little with the stride, her weight rides over the stance leg, the head stays level and watchful
            cr = math.cos(w + 0.3)
            pel_yaw = -0.09 * cr
            twist = 0.12 * cr
            shift_x = 0.9 * sw
            sh_roll = -0.045 * sw
            head_yaw_free = -0.7 * twist + 0.05 * math.sin(w * 0.5)
        else:  # standing ready: weight a little forward, scanning slowly left and right
            shift_x = 0.6 + 0.15 * sw
            sh_roll = -0.03 + 0.01 * sw
            twist = -0.05
            head_yaw_free = 0.32 * math.sin(w - 0.4)
    elif free and walking:  # calm and even (the old hip sway read as a limp): a small pelvis turn, the shoulders answer it, hardly any side shift
        amp = 1.3 if running else (0.55 if crouch else 1.0)
        pel_yaw = -0.10 * amp * cw
        twist = 0.10 * amp * cw
        shift_x = (0.45 if running else 0.22) * sw
        hip_dy = (0.4 if running else 0.0) * amp * sw
        sh_roll = -0.018 * amp * sw
        head_yaw_free = -0.8 * twist
    elif free and not crouch:
        shift_x = 0.75 + 0.2 * sw
        hip_rest = (0.12, -0.26)
        sh_roll = -0.05 + 0.012 * sw
        twist = -0.07
        head_yaw_free = 0.11 + 0.05 * math.sin(w + 1.0)

    def rot_z(a: float):
        c, s_ = math.cos(a), math.sin(a)
        return np.array([[c, -s_, 0], [s_, c, 0], [0, 0, 1]])

    def sneak_phase(side: int):  # standing ready she holds a lunge: the right foot set down in front, the left behind it with the heel up
        return (w if side == 1 else w + math.pi) if walking else (0.3 if side == 1 else math.pi + 0.3)

    # --- legs: sagittal swing, solved for the lowest foot to stand on the ground
    walk_ik = walking and not running and not crouch  # the even walk: legs solved from the foot path (WALK_* above)

    def leg_chain(side: int, phase: float):
        hx = side * 2.5
        if walk_ik:
            hip = np.array([hx, 24.0, 0.2])
            if free:
                hip = np.array([shift_x, 24.0, 0.2]) + rot_y(pel_yaw) @ np.array([hx, 0.0, 0.0])
            z, lift, _pitch = walk_foot(phase / (2 * math.pi))
            ground = 24.0 - walk_height(w)
            target = np.array([side * 2.25 + 0.8 * shift_x, ground + 2.5 + lift, 0.2 + z])
            knee, ankle = ik2(hip, target, 11.5, 10.0, (0.0, 0.0, 1.0))
            thigh = math.atan2(knee[2] - hip[2], hip[1] - knee[1])
            shank = math.atan2(ankle[2] - knee[2], knee[1] - ankle[1])
            return hip, knee, ankle, thigh, shank
        if sneak:
            thigh, flex, _pitch = sneak_leg(sneak_phase(side))
        elif sprint:
            thigh, flex, _pitch = sprint_leg(phase, gait_keys)
        elif running:
            thigh = 0.06 + 0.30 * math.cos(phase)
            flex = 0.16 + 0.82 * max(0.0, -math.sin(phase))
        elif walking:
            thigh = (0.28 if crouch else 0.4) * math.cos(phase)  # a prowl takes short, careful steps
            flex = 0.08 + (0.45 if crouch else 0.55) * max(0.0, -math.sin(phase))
        elif free and not crouch and side == -1:
            thigh, flex = 0.14, 0.30  # the resting leg: knee loose, foot a little forward
        else:
            thigh, flex = 0.0, 0.04
        if crouch and not sneak:  # low and ready, knees bent but not sitting
            thigh += 0.38
            flex += 0.78
        hip = np.array([hx, 24.0, 0.2])
        if free:
            hip = np.array([shift_x, 24.0, 0.2]) + rot_y(pel_yaw) @ np.array([hx, 0.0 if sneak else side * hip_dy + hip_rest[0 if side == 1 else 1], 0.0])
        knee = hip + 11.5 * np.array([0.0, -math.cos(thigh), math.sin(thigh)])
        shank = thigh - flex
        ankle = knee + 10.0 * np.array([0.0, -math.cos(shank), math.sin(shank)])
        return hip, knee, ankle, thigh, shank

    if pose and pose.get("ankles"):
        drop, bob = float(pose["dy"]), 0.0
        legs = []
        for side, target in zip((1, -1), pose["ankles"]):
            hip = np.array([side * 2.5, 24.0 + drop, 0.2 + pose["pz"]])
            knee, ankle = ik2(hip, target, 11.5, 10.0, (side * 0.4, 0.0, 1.0))
            legs.append((hip, knee, ankle, 0.0, 0.0))
    elif pose and pose.get("leg_angles"):  # crawling: the legs are posed by angles (thigh, flex) per leg
        legs = []
        for side, (thigh, flex) in zip((1, -1), pose["leg_angles"]):
            hip = np.array([side * 2.5, 24.0, 0.2])
            knee = hip + 11.5 * np.array([0.0, -math.cos(thigh), math.sin(thigh)])
            shank = thigh - flex
            ankle = knee + 10.0 * np.array([0.0, -math.cos(shank), math.sin(shank)])
            legs.append((hip, knee, ankle, thigh, shank))
        bob, drop = 0.0, float(pose.get("dy", 0.0))
    elif pose and not walking and not pose.get("standby"):  # standing swing: feet planted by the keyframe
        legs, drop = pose_legs(pose)
        bob = 0.0
    else:
        legs = [leg_chain(1, w), leg_chain(-1, w + math.pi)]
        lowest = min(leg[2][1] - 2.5 for leg in legs)
        bob = -lowest
        if walk_ik:  # the ground sits where the walk put it (a heel-raised stance foot or a low swing foot must not lift the body)
            bob = walk_height(w) - 24.0
        drop = 0.0
    body_off = np.array([shift_x, drop, pose["pz"] if pose else 0.0])
    if sprint:  # grounded at the strike and in the stance (where the body sinks into the knee), then she flies
        def grounded(ph):
            return -min(leg[2][1] - 2.5 for leg in (leg_chain(1, ph), leg_chain(-1, ph + math.pi)))
        heights = [grounded(0.0), grounded(math.pi / 3.0), grounded(0.0) + (JOG_LIFT if jog else SPRINT_LIFT)]
        u = (t * 6.0) % 3.0
        k = u - int(u)
        k = k * k * (3 - 2 * k)
        bob = heights[int(u) % 3] + (heights[(int(u) + 1) % 3] - heights[int(u) % 3]) * k
    elif running:
        bob += 0.65 * (1.0 - math.cos(2 * w)) / 2.0  # a light lift between grounded contacts
    # torso lean and breathing
    lean = pose["lean"] if pose else (((0.27 + 0.02 * math.sin(2 * w)) if walking else 0.24) if crouch else (((0.17 if jog else 0.34) if sprint else 0.15) if running else (0.05 if walking else 0.0)))
    breath = 0.0 if (walking or pose) else math.sin(w)
    sway_x = 0.0 if (walking or pose) else 0.5 * math.sin(w)

    # --- pelvis, fitted coat and belt
    m.off = body_off
    m.ell((sway_x * 0.5, 24.5, 0.0), (4.2, 3.4, 3.2), LEGGING)
    m.ell((0, 26.6, 0.0), (3.9, 0.8, 3.4), LEATHER)
    m.ell((0, 26.6, 3.1), (0.9, 0.7, 0.4), GOLD, kind="emit")
    m.ell((-4.6, 24.6, 0.4), (1.0, 1.7, 1.4), LEATHER)  # pouch on the right hip
    for i in range(14):
        ph = 2 * math.pi * i / 14
        wave = (0.55 * math.sin(w + ph * 2) if not walking else 0.9 * math.sin(w + ph) - 0.5 * math.cos(ph)) * 0.7 * (1.3 if running else 1.0)
        tilt = 0.16 + 0.04 * (i % 2) + 0.04 * wave + (pose["flare"] * (0.6 + 0.4 * math.cos(ph)) if pose else 0.0)
        if sprint:
            tilt += 0.16 * gk * max(0.0, -math.sin(ph))  # the back of the skirt lifts in the wind of the run
        rx, rz = 4.7, 3.9
        ax = (math.cos(ph) * rx, 22.8, math.sin(ph) * rz)
        up = np.array([-math.sin(tilt) * math.cos(ph), math.cos(tilt), -math.sin(tilt) * math.sin(ph) * 0.8])
        tan = np.array([-math.sin(ph), 0, math.cos(ph)])
        R = frame_from(up, np.cross(tan, up))
        R = np.stack([np.cross(up / np.linalg.norm(up), R[:, 2]), up / np.linalg.norm(up), R[:, 2]], axis=1)
        m.ell(ax, (1.25, 2.5, 0.65), COAT, R=R)

    # Split coat tails sit behind the legs and sway independently, rather than
    # covering the stride. The same model-space panels are used in every view.
    for side in (-1, 1):
        follow = (0.7 * math.sin(w + side * 0.45) if walking else 0.25 * math.sin(w + side))
        if pose:
            follow = 0.4 * float(pose.get("flare", 0.0))
        drift = ((-0.9 if running else -0.35) * math.sin(w - 0.9) if walking else -0.5) if free and not crouch else 0.0  # the tails lag behind the sideways shift of the hips
        if sprint:  # the tails fly out behind her, each with its own wave
            flap = math.sin(2 * w + side * 0.9)
            m.ribbon([(side * 2.7, 24.0, -1.8),
                      (side * 3.2 + drift * 0.4, 22.6 - 1.6 * (1.0 - gk) + 0.5 * flap, -7.0 + 2.5 * (1.0 - gk)),
                      (side * 3.6 + drift, 21.2 - 4.0 * (1.0 - gk) + 1.5 * gk * math.sin(2 * w + side * 0.9 - 1.1), -13.0 + 6.0 * (1.0 - gk))],
                     [2.0, 3.5, 3.0, 0.45], 0.8, COAT, (1, 0, 0), kind="")
            continue
        m.ribbon([(side * 2.7, 24.0, -1.8),
                  (side * 3.1 + drift * 0.45, 19.0, -4.5 + follow * 0.5),
                  (side * 3.3 + drift, 13.0, -8.0 + follow)],
                 [2.0, 3.5, 3.0, 0.45], 0.8, COAT, (1, 0, 0), kind="")

    # --- legs and boots
    m.off = body_off if (pose and pose.get("leg_angles")) else np.zeros(3)  # climbing out: the legs sink with the body
    for side, (hip, knee, ankle, thigh, shank) in zip((1, -1), legs):
        m.limb(hip, knee, 2.35, 1.75, LEGGING)
        m.limb(knee, ankle, 1.85, 1.2, BOOT)
        up = knee + (ankle - knee) * -0.28  # boot top sits above the knee
        m.limb(up, knee, 2.05, 2.0, BOOT)
        m.ell(up, (2.25, 0.6, 2.25), VIOLET, kind="emit")
        fdir = np.array([0.0, -math.sin(shank) * 0.0, math.cos(shank)])
        if (free and walking) or sneak or walk_ik:  # the foot rolls: toes up at the heel strike, hanging while the leg swings through
            ph_leg = sneak_phase(side) if sneak else (w if side == 1 else w + math.pi)
            Rf = rot_x(-0.32 * max(0.0, math.cos(ph_leg)) ** 2 * (0.0 if crouch else 1.0) + (0.6 if running else 0.42) * max(0.0, -math.sin(ph_leg)))
            if sprint:
                Rf = rot_x(sprint_leg(ph_leg, gait_keys)[2])
            elif walk_ik:
                Rf = rot_x(walk_foot(ph_leg / (2 * math.pi))[2])
            elif sneak:
                Rf = rot_x(sneak_leg(ph_leg)[2])
            heel = ankle + np.array([0.0, -2.2, -0.9])
            m.ell(heel + Rf @ np.array([0.0, 0.7, 2.2]), (1.55, 1.1, 2.7), BOOT, R=Rf)
            m.ell(heel, (1.45, 0.8, 1.1), BOOT)
            m.ell(heel + Rf @ np.array([0.0, 2.7, 2.1]), (1.6, 0.35, 1.2), GOLD, kind="emit", R=Rf)
            continue
        m.ell(ankle + np.array([0.0, -1.5, 1.3]), (1.55, 1.1, 2.7), BOOT)
        m.ell(ankle + np.array([0.0, -2.2, -0.9]), (1.45, 0.8, 1.1), BOOT)
        m.ell(ankle + np.array([0.0, 0.5, 1.2]), (1.6, 0.35, 1.2), GOLD, kind="emit")  # buckle

    # --- torso
    m.off = body_off
    tor = rot_x(lean) @ rot_z(sh_roll) @ rot_y(twist) if free else rot_x(lean) @ rot_y(twist)
    if pose and pose.get("roll"):  # optional: the shoulders tilt into a cut
        tor = rot_x(lean) @ rot_z(float(pose["roll"])) @ rot_y(twist)
    TR = tor if (pose or twist or sh_roll) else None
    def T(p):
        base = np.array([0.0, 27.0, 0.0])
        return base + tor @ (np.array(p, float) - base)

    m.ell(T((0, 29.8 + breath * 0.05, 0)), (2.85, 3.3, 2.3), LEATHER, kind="corset", R=TR)
    m.ell(T((0, 34.2 + breath * 0.12, 0)), (3.7 + breath * 0.06, 4.1, 2.9 + breath * 0.05), LEATHER, kind="corset", R=TR)
    for sx in (-1, 1):
        m.ell(T((sx * 1.85, 33.5 + breath * 0.15, 2.2)), (1.8, 1.8, 1.6), LEATHER)
    m.ell(T((0, 36.8, 2.1)), (3.0, 0.9, 1.6), VIOLET, kind="emit", R=TR)  # neckline trim
    # --- arms (her right arm is drawn by the game from the shoulder to the sword grip)
    m.rig = {}
    arm_pts = {}
    for side in (1, -1):
        sh = T((side * 4.5, 38.0 + breath * 0.2, 0.0))
        if pose:  # attack: hands go where the keyframe puts them (the right one is drawn by the game)
            m.ell(sh, (1.75, 1.75, 1.75), LEATHER)
            sh_abs = sh + m.off
            if side == -1 and not pose.get("both_arms"):
                m.rig = {"shoulder": sh_abs, "hand": np.array(pose["hand_r"], float)}
                continue
            if side == -1:
                m.rig = {"shoulder": sh_abs, "hand": np.array(pose["hand_r"], float)}
            target = pose["hand_r"] if side == -1 else pose["hand_l"]
            pole = pose.get("pole_r", (-0.8, -0.6, -0.3)) if side == -1 else pose.get("pole_l", (0.8, -0.6, -0.3))
            elbow_abs, wrist_abs = ik2(sh_abs, target, 6.6, 6.0, pole)
            d2 = (wrist_abs - elbow_abs) / np.linalg.norm(wrist_abs - elbow_abs)
            elbow, wrist = elbow_abs - m.off, wrist_abs - m.off
            arm_pts["hand_l" if side == 1 else "hand_r"] = wrist_abs  # swimming: where the hands enter the water
            m.limb(sh, elbow, 1.35, 1.1, COAT)
            m.limb(elbow + 0.4 * d2, wrist, 1.2, 0.95, LEATHER)
            m.ell(elbow + 1.6 * d2, (1.3, 0.5, 1.3), VIOLET, kind="emit")
            m.ell(wrist + 0.9 * d2, (1.0, 1.15, 1.0), LEATHER)
            continue
        if running:
            swing = -0.58 * math.cos(w if side == 1 else w + math.pi)
        elif walking:
            swing = -(0.18 if crouch else 0.38) * math.cos(w if side == 1 else w + math.pi)
        else:
            swing = 0.08 * math.sin(w + (0 if side == 1 else 1.4))
        flex = 0.95 if running else 0.3 + (0.18 * max(0.0, -swing) if walking else 0.0)
        if sneak:  # stalking: the arms are held forward and bent, the free one counter-swings softly, the sword hand rides by the hip
            cy = math.cos((w if side == 1 else w + math.pi) - 0.4) if walking else 0.0
            swing = (0.30 - 0.14 * cy) if side == 1 else (0.25 - 0.06 * cy)  # upper arms hang close, forearms forward: hands loose before the chest
            flex = (1.50 + 0.12 * cy) if side == 1 else 1.15
            if not walking:
                swing += 0.03 * math.sin(w + side)
        elif free and walking and not running:  # a loose arm: the forearm lags behind the upper arm and folds on the way forward
            lagged = -(0.18 if crouch else 0.38) * math.cos((w if side == 1 else w + math.pi) - 0.55)
            flex = 0.2 + 1.0 * max(0.0, lagged) + 0.12 * max(0.0, -lagged)
        elif sprint:  # pumping arms: the free one bent square and driven hard, the sword arm calmer so the blade can trail
            pump = -math.cos((w if side == 1 else w + math.pi) + 0.45)
            swing = (0.95 * pump + 0.12) if side == 1 else (0.55 * pump - 0.05)
            flex = (1.45 + 0.3 * pump) if side == 1 else (0.95 + 0.2 * pump)
            if jog:  # the jog: both arms bent square, swinging easily, never driven
                swing = (0.55 * pump + 0.05) if side == 1 else (0.40 * pump - 0.02)
                flex = (1.5 + 0.15 * pump) if side == 1 else (1.2 + 0.12 * pump)
        elif free and not crouch and side == 1:
            flex = 0.42  # standing: the free hand rests a little bent
        if crouch and not sneak:  # arms held forward and bent, ready to spring
            swing += 0.5
            flex += 0.55
        abd = 0.16 - 0.08 * mi + (0.05 if free and walking and not running else 0.0)
        d1 = np.array([side * math.sin(abd), -math.cos(abd) * math.cos(swing), math.cos(abd) * math.sin(swing)])
        sw2 = swing + flex
        d2 = np.array([side * math.sin(abd * 0.6), -math.cos(sw2), math.sin(sw2)])
        if free and twist:  # the arms hang from the turned shoulders
            d1, d2 = rot_y(twist) @ d1, rot_y(twist) @ d2
        elbow = sh + 6.6 * d1
        wrist = elbow + 6.0 * d2
        m.ell(sh, (1.75, 1.75, 1.75), LEATHER)
        if side == -1:
            m.rig = {"shoulder": sh, "hand": wrist + 0.9 * d2}
            continue
        m.limb(sh, elbow, 1.35, 1.1, COAT)
        m.limb(elbow + 0.4 * d2, wrist, 1.2, 0.95, LEATHER)  # bracer
        m.ell(elbow + 1.6 * d2, (1.3, 0.5, 1.3), VIOLET, kind="emit")
        m.ell(wrist + 0.9 * d2, (1.0, 1.15, 1.0), LEATHER)
    m.rig.update(arm_pts)
    # --- neck, head
    m.limb(T((0, 38.8, 0.0)), T((0, 42.0, 0.3)), 1.2, 1.1, SKIN)
    m.ell(T((0, 40.2, 0.0)), (2.0, 0.9, 2.0), LEATHER)  # collar
    m.ell(T((0, 41.3, 0.15)), (1.5, 0.45, 1.5), LEATHER)  # choker
    m.ell(T((0, 41.2, 1.55)), (0.65, 0.65, 0.5), CRYSTAL, kind="emit")
    bobh = 0.2 * breath
    head_yaw = float(pose.get("head_yaw", 0.0)) if pose else head_yaw_free
    head_turn = rot_y(head_yaw)
    if pose and pose.get("nod"):  # optional: the head tips about its own centre (negative = the face comes up: swimming with the head carried high)
        head_turn = rot_x(float(pose["nod"])) @ head_turn
    def H(p):
        pivot = np.array([0.0, 45.0 + bobh, 0.35])
        if sneak:  # the prowl: the head stays upright on the leaning body (eyes forward), so the fringe and the hair do not tip over her face
            return T(pivot) + rot_y(twist + head_yaw) @ (np.asarray(p, float) - pivot)
        return T(pivot + head_turn @ (np.asarray(p, float) - pivot)) if (head_yaw or (pose and pose.get("nod"))) else T(p)
    def HL(p, l):  # a point of the long hair: its root follows the nodding head, further down it follows the body only
        a = H(p)
        if not (pose and pose.get("nod")):
            return a
        pv = np.array([0.0, 45.0 + bobh, 0.35])
        b = T(pv + rot_y(head_yaw) @ (np.asarray(p, float) - pv))
        return a + (b - a) * min(1.0, 1.5 * l)
    head_R = tor @ head_turn if pose else (rot_y(twist + head_yaw) if (twist or head_yaw) else None)  # free loops: the head only turns, it never nods with the lean
    hc = H((0.0, 45.0 + bobh, 0.35))
    Rhang = None  # sneaking: H already keeps the head and its hair upright

    def HH(p):  # sneaking: the long hair hangs by gravity, it does not lean over with the torso
        return p if Rhang is None else hc + Rhang @ (np.asarray(p, float) - hc)
    head_tilt = (0.06 * math.sin(w + 1.0)) if not walking else 0.0
    m.ell(hc, (4.65, 5.1, 4.55), SKIN, kind="head", R=head_R)
    if pose:  # where food goes (for the game's eating effects), absolute like the other rig points
        m.rig["mouth"] = hc + head_R @ np.array([0.0, -1.7, 4.3]) + m.off
    # --- where jewellery hangs (docs/talisman_konzept.md; `tools/art_hero_jewelry.py` exports them per frame): the ear lobes, both sides of the collar, the
    # chest where a pendant hangs, and the directions the torso, the head, both ears and both collar points face (`m.facing`, for the game's visibility test)
    hR = head_R if head_R is not None else np.eye(3)
    m.rig["ear_a"] = hc + hR @ np.array([4.55, -1.4, -0.3]) + m.off
    m.rig["ear_b"] = hc + hR @ np.array([-4.55, -1.4, -0.3]) + m.off
    m.rig["neck_a"] = T((1.9, 39.9, 1.0)) + m.off
    m.rig["neck_b"] = T((-1.9, 39.9, 1.0)) + m.off
    m.rig["pendant"] = T((0.0, 35.2, 3.7)) + m.off
    m.facing = [tor @ np.array([0.0, 0.0, 1.0]), hR @ np.array([0.0, 0.0, 1.0]), hR @ np.array([1.0, 0.0, 0.0]), hR @ np.array([-1.0, 0.0, 0.0]), tor @ np.array([1.0, 0.0, 0.0]), tor @ np.array([-1.0, 0.0, 0.0])]
    cap_c = hc + (head_R @ np.array([0.0, 0.45, -0.35]) if head_R is not None else np.array([0.0, 0.45, -0.35]))
    m.ell(cap_c, (5.05, 5.5, 4.95), HAIR, kind="hair", tag=3.0, clip=face_open, R=head_R)
    # --- hair: fringe, side locks, long back hair with a travelling wave
    def hair_off(l: float, i: int, side_scale: float = 1.0):
        ph = i * 0.9
        if pose and not pose.get("standby"):
            hx, hy, hz = pose["hair"]
            pc, ps = math.cos(pose.get("pitch", 0.0)), math.sin(pose.get("pitch", 0.0))
            # optional "spread" (strands fan out sideways and differ in how far they fall) and "curl" (an S bend along the strand): without them the
            # strands all fall on one line and the hair looks like a stiff stick
            spread, curl = float(pose.get("spread", 0.0)), float(pose.get("curl", 0.0))
            side = (((i * 0.618 + 0.3) % 1.0) - 0.5) * 2.0
            var = 1.0 + 0.45 * spread * ((((i * 0.381966) + 0.13) % 1.0) - 0.5) * 2.0
            droop = float(pose.get("droop", 0.0)) * var * l ** 1.2  # gravity, seen from the turned body: world down in model space
            bend = curl * math.sin(5.0 * l + ph * 1.3) * l  # sideways in the fall plane
            return np.array([hx * l ** 1.3 + 0.35 * l * math.sin(ph + 2.0 * l) + spread * side * 2.6 * l ** 1.1 + 0.7 * bend,
                             hy * l - droop * pc + bend * ps * 1.6, hz * l ** 1.3 + droop * ps + bend * pc * 1.6])
        if running:
            # The roots follow the head, while each tip lags the stride and
            # its neighbours. One full wave per two steps avoids identical
            # hair silhouettes on the two contact frames.
            lag = w - 1.4 * l + ph * 0.22
            x = 1.6 * l ** 1.2 * math.sin(lag + 0.5) * side_scale
            z = -(3.0 + 1.9 * math.sin(lag - 0.8)) * l ** 1.25
            y = (0.9 + 1.3 * math.sin(lag - 1.5)) * l ** 1.15
            if sprint:  # the hair flies: a long mane streaming out behind the head, a wave running down it twice a stride, the strands fanned apart
                run = 2 * w - 3.2 * l + ph * 0.5
                fan = math.sin(ph * 1.7 + 0.6)
                x = (1.5 * math.sin(run + 0.5) + 1.1 * fan) * l ** 1.2 * side_scale
                z = -(8.2 + 1.4 * math.sin(run - 0.8) + 1.0 * fan) * l ** 1.1
                y = 12.0 * l ** 1.1 - 4.5 * l ** 2.6 + (3.6 * math.sin(run) + 2.4 * fan) * l ** 1.3  # rises off the neck, the tips sink and whip
                if jog:  # the jog: the mane lifts and flows back, softer and lower than in the sprint
                    z = -(5.6 + 1.0 * math.sin(run - 0.8) + 0.8 * fan) * l ** 1.1
                    y = 6.5 * l ** 1.1 - 2.6 * l ** 2.6 + (2.2 * math.sin(run) + 1.4 * fan) * l ** 1.3
        elif walking:
            lag = w - 1.5 * l + ph * 0.24
            x = 1.2 * l ** 1.2 * math.sin(lag + 0.4) * side_scale
            if free:  # the mass of hair swings out behind the sideways shift of the hips
                x += 0.35 * l ** 1.3 * (math.sin(w - 1.3 - 0.8 * l) - sw)
            z = -(1.4 + 1.0 * math.sin(lag - 0.8)) * l ** 1.25
            y = (0.25 + 0.8 * math.sin(lag - 1.5)) * l ** 1.15
            if sneak:  # the prowl: the mane streams back softly off her shoulders
                z -= (1.1 + 0.4 * math.sin(2 * w - 2.0 * l + ph * 0.6)) * l ** 1.2
                y += 0.5 * l ** 1.2
            if free and not crouch:  # more life in the walk: the mane lifts off her back and each strand has its own beat
                z -= (1.3 + 0.9 * math.sin(2 * w - 2.4 * l + ph * 0.6)) * l ** 1.2
                y += (0.9 + 0.8 * math.sin(2 * w - 2.4 * l + ph * 0.6 - 0.7)) * l ** 1.2
        else:
            x = 1.3 * l ** 1.2 * math.sin(w + ph - 1.6 * l) * side_scale
            z = 0.8 * l * math.sin(w + ph * 0.5 - 1.0 * l)
            y = 0.45 * l * math.sin(2 * w - 1.0 * l)
        if pose and pose.get("standby"):
            hx, hy, hz = pose["hair"]
            x += hx * l ** 1.3
            y += hy * l
            z += hz * l ** 1.3
        return np.array([x, y, z])

    for side in (-1, 1):  # centre parting: the fringe sweeps out to the temples and leaves the brow free
        for j, (sx, drop) in enumerate(((1.0, 0.0), (2.2, 0.7), (3.4, 1.6))):
            top = H((side * 0.5 - 0.25, 50.3, 1.4))
            mid = H((side * (sx + 0.9), 48.3 - drop * 0.4, 3.6 - 0.3 * j))
            end = H((side * (sx * 1.25 + 1.6), 46.6 - drop, 3.2 - 0.5 * j))
            m.ribbon([top, mid, end + hair_off(0.15, j + side) * 0.3], [0.9, 0.95, 0.35], 0.75, HAIR, (0, 0, 1), tag=j * 2 + side)
    for side in (-1, 1):  # long side locks framing the face
        pts = []
        for k, l in enumerate(np.linspace(0, 1, 6)):
            base = HL((side * (4.9 + 0.3 * l), 45.2 - 15.0 * l, 1.8 + 0.5 * l), l)
            pts.append(HH(base + hair_off(l, 3 + side) * 0.7))
        m.ribbon(pts, [1.15, 1.2, 1.15, 0.9, 0.5], 0.85, HAIR, (0, 0, 1), tag=7 + side)
    back = [(-3.4, 1.0), (-2.2, 0.6), (-1.0, 0.0), (0.2, 0.4), (1.4, 0.0), (2.6, 0.7), (3.6, 1.1)]
    for i, (bx, extra) in enumerate(back):
        pts = []
        y_end = 16.8 + 4.5 * ((i * 7) % 5) / 4.0
        for l in np.linspace(0, 1, 9):
            spread = bx * (1.0 + 0.5 * l) + 0.35 * math.sin(3.0 * l + i) * l
            z = -3.0 - 0.9 * math.sin(math.pi * min(l * 1.3, 1.0)) - (0.35 + extra * 0.55) * l
            at_y = 45.5 - (45.5 - y_end) * l
            z -= min(max((28.0 - at_y) / 7.0, 0.0), 1.0) * (2.3 + 0.9 * mi)  # below the waist the hair hangs clear of the skirt
            p = HL((spread, at_y, z), l)
            pts.append(HH(p + hair_off(l, i)))
        m.ribbon(pts, [1.5, 1.65, 1.55, 1.4, 1.15, 0.85, 0.55, 0.3, 0.12], 0.95, HAIR, (0, 0, -1), tag=i * 1.7)
    # Two lighter, separated outer locks give the silhouette the portrait's
    # layered shape; their tips lag independently from the main hair mass.
    for side in (-1, 1):
        pts = []
        for l in np.linspace(0, 1, 7):
            base = HL((side * (4.0 + 1.5 * l), 45.2 - 23.0 * l, -1.5 - 2.4 * l), l)
            pts.append(HH(base + hair_off(l, 9 + side * 2, 1.1)))
        m.ribbon(pts, [0.85, 1.0, 0.85, 0.55, 0.1], 0.6, HAIR, (0, 0, -1), tag=13 + side * 1.3)
    # hair ornament: a small gold pin with a violet gem
    m.ell(H((4.7, 48.0 + bobh, 0.8)), (0.5, 0.9, 0.5), GOLD, kind="emit")
    m.ell(H((4.9, 47.0 + bobh, 0.9)), (0.55, 0.55, 0.55), CRYSTAL, kind="emit")
    if pose and pose.get("mug"):  # optional: a clay mug with a glowing brew held at this point (absolute, like the hand targets); "mug_tilt" tips it towards her mouth
        mc = np.array(pose["mug"], float) - m.off
        Rm = rot_x(float(pose.get("mug_tilt", 0.0)))
        m.ell(mc, (1.9, 2.3, 1.9), LEATHER, R=Rm)
        m.ell(mc + Rm @ np.array([0.0, 2.1, 0.0]), (1.95, 0.4, 1.95), GOLD, R=Rm)
        m.ell(mc + Rm @ np.array([0.0, 2.2, 0.0]), (1.45, 0.3, 1.45), TEAL, kind="emit", R=Rm)
        m.ell(mc + Rm @ np.array([-2.1, 0.2, 0.0]), (0.5, 1.2, 0.9), LEATHER, R=Rm)
    if pose and pose.get("plank"):  # optional: a long board carried in both hands: centre (absolute, like the hand targets), `plank_tilt` about x, `plank_mat` the ramp
        pc = np.array(pose["plank"], float) - m.off
        Rp = rot_x(float(pose.get("plank_tilt", 0.0)))
        pm = int(pose.get("plank_mat", LEATHER))
        for k in range(-int(pose.get("plank_len", 28)) // 2, int(pose.get("plank_len", 28)) // 2 + 1):
            m.ell(pc + Rp @ np.array([0.0, 0.0, k * 1.0]), (3.8, 0.9, 1.5), pm, R=Rp)
        m.ell(pc + Rp @ np.array([0.0, 0.5, 2.0]), (3.9, 0.4, 0.5), IRON_P if False else pm, R=Rp)
    if pose and pose.get("pitch"):  # the whole body turned about the pelvis (prone, crawling), then set down on the ground
        pivot = np.array([0.0, 24.0, 0.0])
        Rg = rot_x(float(pose["pitch"]))
        for p in m.prims:
            p.c = pivot + Rg @ (p.c - pivot)
            p.R = Rg @ p.R
            p.rot = True
        low = 0.0 if pose.get("level") else min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in m.prims)  # "level": no set-down, the pelvis stays at its height (swimming: the water plane is y = 0)
        for p in m.prims:
            p.c = p.c + np.array(pose.get("shift", (0.0, 0.0, 0.0)), float) + np.array([0.0, -low, 0.0])
        if pose.get("level"):  # the rig points (mouth, ears, hands) turn and move with the body
            for key, v in list(m.rig.items()):
                m.rig[key] = pivot + Rg @ (np.asarray(v, float) - pivot) + np.array(pose.get("shift", (0.0, 0.0, 0.0)), float)
    m.bob = bob
    return m


def project(model: Model, yaw: float, point) -> list[float]:
    """Feet-relative screen position (px, y down) of a model point, as the game places sprites."""
    p = rot_y(yaw) @ (np.asarray(point, float) + np.array([0.0, model.bob, 0.0])) * SCALE
    return [round(float(p[0]), 1), round(float(-(p[1] * COSP - p[2] * SINP)), 1)]


def frame(sector: int, t: float, mode: str, crouch: bool, pose=None):
    yaw = math.pi / 2 - sector * math.pi / 4
    model = build(t, mode, crouch, pose)
    global LAST_BLOOD
    if POINTS_ONLY:  # jewellery export: only the rig points are wanted, no pixels
        rig = {k: project(model, yaw, v) for k, v in model.rig.items()}
        rig["jf"] = [round(float((rot_y(yaw) @ v) @ WHAT), 3) for v in getattr(model, "facing", [])]
        return None, rig
    if WANT_BLOOD:
        depth, code, bl = render(model.transform(yaw, model.bob), yaw, model.bob)
        LAST_BLOOD = to_blood(bl, code, LAST_BAND)
    else:
        depth, code = render(model.transform(yaw, model.bob))
    rig = {k: project(model, yaw, v) for k, v in model.rig.items()}
    rig["jf"] = [round(float((rot_y(yaw) @ v) @ WHAT), 3) for v in getattr(model, "facing", [])]  # how much each part faces the camera (1 = straight at it)
    return to_pixels(depth, code), rig


def paste(rows, cols: int, nrows: int):
    sheet = [[CLEAR] * (cols * FW) for _ in range(nrows * FH)]
    for r, row in enumerate(rows):
        for c, fr in enumerate(row):
            for y in range(FH):
                sheet[r * FH + y][c * FW: (c + 1) * FW] = fr[y]
    return sheet


def hero_sheets():
    """(main sheet, attack sheet, rig data, pick sheet, eat sheet)."""
    rows, shoulders, hands = [], [], []
    for crouch in (False, True):
        for sector in range(8):
            frames = [frame(sector, i / WALK_FRAMES, "walk", crouch) for i in range(WALK_FRAMES)]
            frames += [frame(sector, i / RUN_FRAMES, "walk" if crouch else "run", crouch) for i in range(RUN_FRAMES)]
            frames += [frame(sector, i / IDLE_FRAMES, "idle", crouch) for i in range(IDLE_FRAMES)]
            frames += [frame(sector, i / JOG_FRAMES, "walk" if crouch else "jog", crouch) for i in range(JOG_FRAMES)]
            rows.append([f[0] for f in frames])
            shoulders += [f[1]["shoulder"] for f in frames]
            hands += [f[1]["hand"] for f in frames]
    arows, ashoulders, ahands = [], [], []
    for sector in range(8):
        frames = []
        for step in ATTACK_POSES:
            for variant in range(ATTACK_LEGS):
                for pose in step:
                    if variant == 0:
                        frames.append(frame(sector, 0.0, "attack", False, pose))
                    else:  # walking swing: the pelvis stays over the walking feet
                        frames.append(frame(sector, (variant - 1) / WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
        arows.append([f[0] for f in frames])
        ashoulders += [f[1]["shoulder"] for f in frames]
        ahands += [f[1]["hand"] for f in frames]
    prows, pshoulders, phands, _pm = pick_sheet()
    erows, eshoulders, ehands, emouths = pick_sheet(EAT_KEYS, ATTACK_LEGS)
    rig = {"cols": COLS, "shoulder": shoulders, "hand": hands,
           "attack_cols": ATTACK_COLS, "attack_shoulder": ashoulders, "attack_hand": ahands,
           "pick_cols": PICK_FRAMES, "pick_shoulder": pshoulders, "pick_hand": phands,
           "eat_cols": PICK_FRAMES, "eat_variants": ATTACK_LEGS, "eat_shoulder": eshoulders, "eat_hand": ehands, "eat_mouth": emouths}
    return paste(rows, COLS, 16), paste(arows, ATTACK_COLS, 8), rig, paste(prows, PICK_FRAMES, 8), paste(erows, PICK_FRAMES * ATTACK_LEGS, 8)


def pick_sheet(keys=None, variants=1):
    """(rows of frames per sector, right shoulders, right hands, mouths) of a one-second animation (default: picking).
    With `variants` > 1 every frame comes once per leg variant like the attack sheet (0 planted, 1-6 the walk cycle's
    phases), so the upper-body animation can play while she walks."""
    keys = keys or PICK_KEYS
    rows, shoulders, hands, mouths = [], [], [], []
    for sector in range(8):
        frames = []
        for v in range(variants):
            for i in range(PICK_FRAMES):
                pose = timeline_pose(keys, (i + 0.5) / PICK_FRAMES)
                frames.append(frame(sector, 0.0, "attack", False, pose) if v == 0 else frame(sector, (v - 1) / WALK_FRAMES, "walk", False, dict(pose, pz=0.0)))
        rows.append([f[0] for f in frames])
        shoulders += [f[1]["shoulder"] for f in frames]
        hands += [f[1]["hand"] for f in frames]
        mouths += [f[1]["mouth"] for f in frames]
    return rows, shoulders, hands, mouths


def blood_sheets():
    """Runs the sheet generation once more with blood on and collects the threshold frames in the order the colour sheets use them."""
    global WANT_BLOOD, frame
    WANT_BLOOD = True
    real_frame = frame
    collected = []

    def collecting(*args, **kwargs):
        result = real_frame(*args, **kwargs)
        collected.append(LAST_BLOOD)
        return result

    frame = collecting
    hero_sheets()
    frame = real_frame
    WANT_BLOOD = False
    sizes = [("player_blood", COLS, 16), ("player_attack_blood", ATTACK_COLS, 8), ("player_pick_blood", PICK_FRAMES, 8), ("player_eat_blood", PICK_FRAMES * ATTACK_LEGS, 8)]
    at = 0
    for name, cols, nrows in sizes:
        count = cols * nrows
        rows = [collected[at + r * cols: at + (r + 1) * cols] for r in range(nrows)]
        at += count
        write_png(ROOT / "characters" / f"{name}.png", cols * FW, nrows * FH, paste(rows, cols, nrows))
    print("blood sheets written", file=sys.stderr)


def update_jog():
    """Update only the standing jog frames, matching blood masks and hand rig."""
    import json
    from gen_doc_images import read_png

    global WANT_BLOOD
    color_path = ROOT / "characters" / "player.png"
    blood_path = ROOT / "characters" / "player_blood.png"
    rig_path = ROOT.parent / "data" / "hero_rig.json"
    color, blood = read_png(color_path), read_png(blood_path)
    rig = json.loads(rig_path.read_text())
    WANT_BLOOD = True
    try:
        for sector in range(8):
            for i in range(RUN_FRAMES):
                pixels, points = frame(sector, i / RUN_FRAMES, "run", False)
                col = WALK_FRAMES + i
                index = sector * COLS + col
                rig["shoulder"][index] = points["shoulder"]
                rig["hand"][index] = points["hand"]
                for y in range(FH):
                    start = col * FW
                    color[sector * FH + y][start:start + FW] = pixels[y]
                    blood[sector * FH + y][start:start + FW] = LAST_BLOOD[y]
    finally:
        WANT_BLOOD = False
    write_png(color_path, COLS * FW, 16 * FH, color)
    write_png(blood_path, COLS * FW, 16 * FH, blood)
    rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "blood":
        blood_sheets()
    elif len(sys.argv) > 1 and sys.argv[1] == "pullonly":
        write_pull()
    elif len(sys.argv) > 1 and sys.argv[1] == "feedonly":
        write_feed()
    elif len(sys.argv) > 1 and sys.argv[1] == "drinkonly":
        write_drink()
    elif len(sys.argv) > 1 and sys.argv[1] == "touchonly":
        write_touch()
    elif len(sys.argv) > 1 and sys.argv[1] == "jog":
        update_jog()
    elif len(sys.argv) > 1 and sys.argv[1] == "attack":
        # attack contact sheet for one sector: python3 art_hero3d.py attack out.png 0
        from pathlib import Path
        sector = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        cells = [frame(sector, 0.0, "attack", False, pose)[0] for step in ATTACK_POSES for pose in step]
        sheet = [[CLEAR] * (ATTACK_FRAMES * FW) for _ in range(ATTACK_STEPS * FH)]
        for i, fr in enumerate(cells):
            r, c = divmod(i, ATTACK_FRAMES)
            for y in range(FH):
                sheet[r * FH + y][c * FW: (c + 1) * FW] = fr[y]
        write_png(Path(sys.argv[2]), ATTACK_FRAMES * FW, ATTACK_STEPS * FH, sheet)
    elif len(sys.argv) > 1 and sys.argv[1] in ("pick", "eat", "pull", "feed", "drink", "animonly"):
        # pick|eat <out.png> <sector>: contact sheet of that one-second animation; animonly: rewrite only
        # assets/characters/player_pick.png / player_eat.png and their entries in data/hero_rig.json
        from pathlib import Path
        if sys.argv[1] in ("pick", "eat", "pull", "feed", "drink"):
            keys = {"pick": PICK_KEYS, "eat": EAT_KEYS, "pull": PULL_KEYS, "feed": FEED_KEYS, "drink": DRINK_KEYS}[sys.argv[1]]
            sector = int(sys.argv[3]) if len(sys.argv) > 3 else 0
            cells = [frame(sector, 0.0, "attack", False, timeline_pose(keys, (i + 0.5) / PICK_FRAMES))[0] for i in range(PICK_FRAMES)]
            sheet = [[CLEAR] * (6 * FW) for _ in range(2 * FH)]
            for i, fr in enumerate(cells):
                r, c = divmod(i, 6)
                for y in range(FH):
                    sheet[r * FH + y][c * FW: (c + 1) * FW] = fr[y]
            write_png(Path(sys.argv[2]), 6 * FW, 2 * FH, sheet)
        else:
            import json
            rig_path = ROOT.parent / "data" / "hero_rig.json"
            rig = json.loads(rig_path.read_text())
            for name, keys in (("pick", PICK_KEYS), ("eat", EAT_KEYS)):
                variants = ATTACK_LEGS if name == "eat" else 1
                rows_, shoulders_, hands_, mouths_ = pick_sheet(keys, variants)
                write_png(ROOT / "characters" / f"player_{name}.png", PICK_FRAMES * variants * FW, 8 * FH, paste(rows_, PICK_FRAMES * variants, 8))
                rig.update({f"{name}_cols": PICK_FRAMES, f"{name}_shoulder": shoulders_, f"{name}_hand": hands_, f"{name}_mouth": mouths_})
                if name == "eat":
                    rig["eat_variants"] = variants
            rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    elif len(sys.argv) > 1 and sys.argv[1] == "preview":
        # preview: sectors S, SW, W, NW, N at walk frame 0 and idle frame 0 -> scratch sheet
        out = sys.argv[2]
        secs = [2, 3, 4, 5, 6, 0]
        cells = []
        for mode, n in (("walk", WALK_FRAMES), ("run", RUN_FRAMES), ("idle", IDLE_FRAMES)):
            for s in secs:
                cells.append(frame(s, 0.0, mode, False)[0])
        cols = len(secs)
        rows = len(cells) // cols
        sheet = [[CLEAR] * (cols * FW) for _ in range(rows * FH)]
        for i, fr in enumerate(cells):
            r, c = divmod(i, cols)
            for y in range(FH):
                sheet[r * FH + y][c * FW: (c + 1) * FW] = fr[y]
        from pathlib import Path
        write_png(Path(out), cols * FW, rows * FH, sheet)
    else:
        import json
        sheet, attack_sheet, rig, pick_sheet_px, eat_sheet_px = hero_sheets()
        write_png(ROOT / "characters" / "player.png", COLS * FW, 16 * FH, sheet)
        write_png(ROOT / "characters" / "player_attack.png", ATTACK_COLS * FW, 8 * FH, attack_sheet)
        write_png(ROOT / "characters" / "player_pick.png", PICK_FRAMES * FW, 8 * FH, pick_sheet_px)
        write_png(ROOT / "characters" / "player_eat.png", PICK_FRAMES * ATTACK_LEGS * FW, 8 * FH, eat_sheet_px)
        rig_path = ROOT.parent / "data" / "hero_rig.json"
        if rig_path.exists():  # retain story-specific rigs written by their separate generators
            existing_rig = json.loads(rig_path.read_text())
            existing_rig.update(rig)
            rig = existing_rig
        rig_path.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("ok", file=sys.stderr)
