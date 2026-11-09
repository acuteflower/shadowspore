"""The heroine, modelled from ellipsoids and rendered to pixel art (needs numpy: pip3 install numpy).

A tiny orthographic z-buffer renderer: every body part is an ellipsoid, shaded in flat bands,
sampled 4x and reduced to one palette colour per pixel, then inked. One model gives all eight
facings, the walk cycle, the idle breathing and the crouch.

Sheet (assets/characters/player.png): COLS x 16 frames of FW x FH, feet at (FW/2, GROUND_ROW).
  rows 0-7  facing E SE S SW W NW N NE (the order of Player.SECTOR), rows 8-15 the same crouched
  cols 0-5  walk cycle, cols 6-11 sprint cycle (contacts at 0 and 3 of each), cols 12-15 idle loop
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
WALK_FRAMES, RUN_FRAMES, IDLE_FRAMES = 6, 6, 4
COLS = WALK_FRAMES + RUN_FRAMES + IDLE_FRAMES
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


# The sword combo, one block per step: wind-up pose (0), strike (1-2), follow-through (3), recovery (4-5).
# Step 1 is a forehand (right to left), step 2 a backhand (left to right), step 3 a lunging thrust.
ATTACK_POSES = [
    [
        P(-0.65, -0.06, -0.8, ((3.2, 2.0, 0), (-3.0, -3.5, 0)), (-8.0, 31.5, -2.0), (5.5, 31.5, 6.0), (-1.5, 0.3, 0.5)),
        P(-0.2, 0.02, 0.3, ((3.0, 3.0, 0), (-3.0, -3.0, 0)), (-6.5, 31.5, 4.0), (6.0, 31.0, 3.0), (1.5, 0.6, 0.0)),
        P(0.2, 0.1, 1.2, ((3.0, 4.2, 0), (-3.0, -2.5, 0.6)), (-1.0, 32.0, 8.5), (6.5, 32.0, -1.0), (2.2, 0.9, -0.3)),
        P(0.6, 0.16, 2.0, ((3.0, 5.0, 0), (-3.0, -1.5, 0.2)), (4.0, 31.0, 7.0), (7.5, 34.0, -3.0), (3.0, 1.0, -0.5), 0.2),
        P(0.4, 0.1, 1.5, ((3.0, 4.4, 0), (-3.0, -1.2, 0)), (3.0, 29.0, 6.0), (6.5, 31.0, -1.0), (-1.2, 0.3, 0.3), 0.1),
        P(0.1, 0.03, 0.6, ((2.8, 3.0, 0), (-2.8, -0.5, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (0.4, 0.0, 0.0)),
    ],
    [
        P(0.6, -0.04, -0.2, ((3.0, 4.0, 0), (-3.0, -1.5, 0)), (4.5, 30.5, 5.0), (7.5, 33.0, -2.0), (-1.5, 0.4, 0.3)),
        P(0.15, 0.04, 0.8, ((3.0, 3.2, 0), (-3.0, -0.5, 0.3)), (1.5, 31.5, 8.5), (6.5, 33.0, -1.5), (1.5, 0.6, 0.0)),
        P(-0.3, 0.1, 1.4, ((3.0, 2.0, 0.3), (-3.0, 4.0, 0)), (-4.0, 31.5, 7.0), (6.0, 31.0, 1.0), (-2.0, 0.9, -0.2)),
        P(-0.65, 0.14, 1.8, ((3.0, 1.5, 0.3), (-3.0, 5.0, 0)), (-8.0, 31.0, 2.5), (5.5, 32.0, 4.5), (-3.0, 1.0, -0.4), 0.2),
        P(-0.4, 0.09, 1.3, ((3.0, 1.5, 0), (-3.0, 4.2, 0)), (-7.0, 29.5, 2.0), (5.5, 30.0, 3.0), (1.0, 0.3, 0.3), 0.1),
        P(-0.05, 0.03, 0.5, ((2.8, 0.5, 0), (-2.8, 3.0, 0)), (-5.0, 25.5, 2.0), (4.5, 26.0, 1.0), (-0.4, 0.0, 0.0)),
    ],
    [
        P(-0.7, -0.2, -1.8, ((3.5, 3.0, 0), (-3.2, -5.0, 0)), (-5.5, 29.0, -3.0), (4.5, 33.5, 6.5), (0.6, 0.2, 1.6)),
        P(-0.45, 0.0, 0.0, ((3.5, 4.0, 0), (-3.2, -4.5, 0)), (-5.0, 30.5, 2.5), (5.0, 33.0, 5.0), (0.8, 0.4, 0.6)),
        P(-0.1, 0.2, 2.2, ((3.0, 7.0, 0), (-3.0, -4.5, 0)), (-3.0, 31.5, 10.0), (6.5, 33.0, 0.0), (0.0, 0.8, -1.2)),
        P(0.2, 0.28, 3.0, ((3.0, 9.0, 0), (-3.0, -4.0, 0)), (-2.2, 32.5, 12.0), (6.5, 34.0, -3.0), (-0.5, 1.2, -2.2), 0.15),
        P(0.1, 0.18, 2.4, ((3.0, 8.0, 0), (-3.0, -3.5, 0)), (-3.0, 30.5, 8.0), (6.0, 32.0, -1.5), (0.4, 0.4, -0.6), 0.05),
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
    running = mode == "run"
    walking = mode in ("walk", "run")
    mi = 1.0 if running else 0.0
    twist = pose["twist"] if pose else 0.0

    # --- legs: sagittal swing, solved for the lowest foot to stand on the ground
    def leg_chain(side: int, phase: float):
        hx = side * 2.5
        if running:
            thigh = 0.06 + 0.30 * math.cos(phase)
            flex = 0.16 + 0.82 * max(0.0, -math.sin(phase))
        elif walking:
            thigh = (0.28 if crouch else 0.4) * math.cos(phase)  # a prowl takes short, careful steps
            flex = 0.08 + (0.45 if crouch else 0.55) * max(0.0, -math.sin(phase))
        else:
            thigh, flex = 0.0, 0.04
        if crouch:  # low and ready, knees bent but not sitting
            thigh += 0.38
            flex += 0.78
        hip = np.array([hx, 24.0, 0.2])
        knee = hip + 11.5 * np.array([0.0, -math.cos(thigh), math.sin(thigh)])
        shank = thigh - flex
        ankle = knee + 10.0 * np.array([0.0, -math.cos(shank), math.sin(shank)])
        return hip, knee, ankle, thigh, shank

    if pose and pose.get("leg_angles"):  # crawling and climbing: the legs are posed by angles (thigh, flex) per leg, not planted
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
        drop = 0.0
    body_off = np.array([0.0, drop, pose["pz"] if pose else 0.0])
    if running:
        bob += 0.65 * (1.0 - math.cos(2 * w)) / 2.0  # a light lift between grounded contacts
    # torso lean and breathing
    lean = pose["lean"] if pose else (0.36 if crouch else (0.15 if running else (0.05 if walking else 0.0)))
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
        m.ribbon([(side * 2.7, 24.0, -1.8),
                  (side * 3.1, 19.0, -4.5 + follow * 0.5),
                  (side * 3.3, 13.0, -8.0 + follow)],
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
        m.ell(ankle + np.array([0.0, -1.5, 1.3]), (1.55, 1.1, 2.7), BOOT)
        m.ell(ankle + np.array([0.0, -2.2, -0.9]), (1.45, 0.8, 1.1), BOOT)
        m.ell(ankle + np.array([0.0, 0.5, 1.2]), (1.6, 0.35, 1.2), GOLD, kind="emit")  # buckle

    # --- torso
    m.off = body_off
    tor = rot_x(lean) @ rot_y(twist)
    TR = tor if pose else None
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
        if crouch:  # arms held forward and bent, ready to spring
            swing += 0.5
            flex += 0.55
        abd = 0.16 - 0.08 * mi
        d1 = np.array([side * math.sin(abd), -math.cos(abd) * math.cos(swing), math.cos(abd) * math.sin(swing)])
        elbow = sh + 6.6 * d1
        sw2 = swing + flex
        d2 = np.array([side * math.sin(abd * 0.6), -math.cos(sw2), math.sin(sw2)])
        wrist = elbow + 6.0 * d2
        m.ell(sh, (1.75, 1.75, 1.75), LEATHER)
        if side == -1:
            m.rig = {"shoulder": sh, "hand": wrist + 0.9 * d2}
            continue
        m.limb(sh, elbow, 1.35, 1.1, COAT)
        m.limb(elbow + 0.4 * d2, wrist, 1.2, 0.95, LEATHER)  # bracer
        m.ell(elbow + 1.6 * d2, (1.3, 0.5, 1.3), VIOLET, kind="emit")
        m.ell(wrist + 0.9 * d2, (1.0, 1.15, 1.0), LEATHER)
    # --- neck, head
    m.limb(T((0, 38.8, 0.0)), T((0, 42.0, 0.3)), 1.2, 1.1, SKIN)
    m.ell(T((0, 40.2, 0.0)), (2.0, 0.9, 2.0), LEATHER)  # collar
    m.ell(T((0, 41.3, 0.15)), (1.5, 0.45, 1.5), LEATHER)  # choker
    m.ell(T((0, 41.2, 1.55)), (0.65, 0.65, 0.5), CRYSTAL, kind="emit")
    bobh = 0.2 * breath
    head_yaw = float(pose.get("head_yaw", 0.0)) if pose else 0.0
    head_turn = rot_y(head_yaw)
    def H(p):
        pivot = np.array([0.0, 45.0 + bobh, 0.35])
        return T(pivot + head_turn @ (np.asarray(p, float) - pivot)) if head_yaw else T(p)
    head_R = tor @ head_turn if pose else None
    hc = H((0.0, 45.0 + bobh, 0.35))
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
    cap_c = hc + (head_R @ np.array([0.0, 0.45, -0.35]) if pose else np.array([0.0, 0.45, -0.35]))
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
        elif walking:
            lag = w - 1.5 * l + ph * 0.24
            x = 1.2 * l ** 1.2 * math.sin(lag + 0.4) * side_scale
            z = -(1.4 + 1.0 * math.sin(lag - 0.8)) * l ** 1.25
            y = (0.25 + 0.8 * math.sin(lag - 1.5)) * l ** 1.15
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
            base = H((side * (4.9 + 0.3 * l), 45.2 - 15.0 * l, 1.8 + 0.5 * l))
            pts.append(base + hair_off(l, 3 + side) * 0.7)
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
            p = H((spread, at_y, z))
            pts.append(p + hair_off(l, i))
        m.ribbon(pts, [1.5, 1.65, 1.55, 1.4, 1.15, 0.85, 0.55, 0.3, 0.12], 0.95, HAIR, (0, 0, -1), tag=i * 1.7)
    # Two lighter, separated outer locks give the silhouette the portrait's
    # layered shape; their tips lag independently from the main hair mass.
    for side in (-1, 1):
        pts = []
        for l in np.linspace(0, 1, 7):
            base = H((side * (4.0 + 1.5 * l), 45.2 - 23.0 * l, -1.5 - 2.4 * l))
            pts.append(base + hair_off(l, 9 + side * 2, 1.1))
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
        low = min(float(p.c[1] - np.sqrt(((p.R[1, :] * p.r) ** 2).sum())) for p in m.prims)
        for p in m.prims:
            p.c = p.c + np.array(pose.get("shift", (0.0, 0.0, 0.0)), float) + np.array([0.0, -low, 0.0])
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
    elif len(sys.argv) > 1 and sys.argv[1] in ("pick", "eat", "pull", "animonly"):
        # pick|eat <out.png> <sector>: contact sheet of that one-second animation; animonly: rewrite only
        # assets/characters/player_pick.png / player_eat.png and their entries in data/hero_rig.json
        from pathlib import Path
        if sys.argv[1] in ("pick", "eat", "pull"):
            keys = {"pick": PICK_KEYS, "eat": EAT_KEYS, "pull": PULL_KEYS}[sys.argv[1]]
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
