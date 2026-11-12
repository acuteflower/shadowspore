"""The loot chests of the wild (docs/beutetruhen_konzept.md): three tiers, each a sheet of opening frames + a glow sheet.
    py -3 tools/art_loot_chests.py [preview.png]
Same look as the hut, the wagon and the heroine (art_hero3d's palette rules, light from the top left, ink outline, four bands of shade), but the
boxy parts are real boxes: a small ray caster for oriented boxes (planks with grain, a bevel catching the light, gaps between them) next to the
ellipsoids of art_hero3d (moss, fungi, crystals, coins, chain links, gems).

Writes assets/props/chests/chest_<tier>.png (COLS frames: 0 locked, 1 unlocked, opening/overshoot poses, last resting open) and chest_<tier>_glow.png
(only the emissive pixels, drawn unlit by LootChest), and data/loot_chest_art.json (frame size, ground row, anchors in px from the feet: the mouth
the loot springs from, the lock / seal, the lid's gem, the chains' crossing, the candles, the footprint)."""
import json
import math
import pathlib
import sys

import numpy as np

import art_hero3d as h
from gen_art import CLEAR, ROOT, hexc, write_png

OUT = ROOT / "props" / "chests"
DATA = ROOT.parent / "data" / "loot_chest_art.json"
YAW = -0.32  # the east side shows (the shaded one), the front is lit
LID = [0.0, 0.0, 4.0, 9.0, 16.0, 25.0, 36.0, 49.0, 63.0, 78.0, 90.0, 100.0, 106.0, 114.0, 120.0, 110.0]  # overshoot poses precede the final resting pose
COLS = len(LID)
V = lambda *a: np.array(a, float)
BAYER_NP = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])

# ------------------------------------------------------------------ materials (dark -> light), appended to the hero's
BASE = len(h.RAMPS)
_RAMPS = [
    ("WOOD", ["2b1f27", "4b3741", "765862", "a6838a"]),  # weathered plum planks (the wanderer's crate)
    ("RUST", ["1d1216", "3b2124", "6b3a2c", "a05c3a"]),  # rusted iron
    ("MOSS", ["1c3d36", "2b5646", "3a7550", "74b268"]),
    ("BARK", ["1a1322", "34283c", "55435a", "85697a"]),  # roots, runners: the trees' bark
    ("DARK", ["06040a", "0c0913", "15101f", "211a30"]),  # the inside
    ("SILVER", ["5c6a86", "9aa8c4", "d4def2", "ffffff"]),  # a silvery shimmer (emits)
    ("COPPER", ["5a2e18", "8e4e26", "c87a40", "f2b47e"]),
    ("CLOTH", ["2a2430", "453b47", "6c5e66", "958579"]),
    ("IRONWOOD", ["0b0d1e", "171d38", "26305a", "3a4a7e"]),  # the moon chest's slate-blue wood
    ("STEEL", ["111528", "28345a", "5670a8", "a8c6f2"]),  # blue steel
    ("MOON", ["2a4ea0", "4a8ae6", "8ec8ff", "eaf8ff"]),  # moonstone, runes (emits)
    ("VELVET", ["1c0e2c", "34184e", "54287a", "7a44a8"]),
    ("LACQUER", ["0a0610", "160f1f", "251a34", "3c2a54"]),  # the reliquary's black lacquer
    ("CHAIN", ["0c0a14", "2a2638", "4e4a66", "8c86aa"]),  # the void's black chains
    ("AMBER", ["8a3a0c", "d2721c", "ffb347", "fff2cc"]),  # the sun heart, molten seams, flames (emits)
    ("STONE", ["14121f", "2a2740", "46456a", "6f6f96"]),
    ("WINE", ["240a12", "461424", "742236", "a63a4e"]),  # the order's wine-red velvet
    ("WAX", ["5a4a52", "8e7c7e", "c4b4a8", "efe4d2"]),  # candles
]
for i, (name, ramp) in enumerate(_RAMPS):
    globals()[name] = BASE + i
h.RAMPS += [[hexc(c) for c in ramp] for _, ramp in _RAMPS]
GOLD, TEAL, VIOLET, CRYSTAL = h.GOLD, h.TEAL, h.VIOLET, h.CRYSTAL
h.DECAL_WEIGHT.update({MOON: 1.9, AMBER: 1.9, SILVER: 1.6, COPPER: 1.3, GOLD: 1.5, VIOLET: 1.6})
EMISSIVE = {TEAL: 1, MOON: 1, AMBER: 1, SILVER: 2, VIOLET: 1}  # material -> lowest band that glows


# ------------------------------------------------------------------ scene: ellipsoids and boxes under a transform stack
class Box:
    __slots__ = ("c", "e", "R", "mat", "kind", "seed")

    def __init__(self, c, e, R, mat, kind, seed):
        self.c, self.e, self.R, self.mat, self.kind, self.seed = c, e, R, mat, kind, seed


class Scene:
    def __init__(self):
        self.items = []
        self.M = np.eye(3)
        self.T = np.zeros(3)

    def at(self, p):
        return self.T + self.M @ V(*p)

    def box(self, c, e, mat, R=None, kind="wood", seed=0.0):
        self.items.append(Box(self.at(c), V(*e), self.M @ (np.eye(3) if R is None else R), mat, kind, seed))

    def ell(self, c, r, mat, R=None, kind=""):
        self.items.append(h.Prim(self.at(c), V(*r), self.M @ (np.eye(3) if R is None else R), mat, kind))

    def limb(self, a, b, r0, r1, mat, kind="", step=0.45):
        a, b = V(*a), V(*b)
        n = max(2, int(np.linalg.norm(b - a) / step))
        for i in range(n + 1):
            t = i / n
            r = r0 + (r1 - r0) * t
            self.ell(a + (b - a) * t, (r, r, r), mat, kind=kind)

    def frame(self, M, T):
        """Enter a child frame (lid about its hinge): returns the old one for `restore`."""
        old = (self.M, self.T)
        self.T = self.T + self.M @ V(*T)
        self.M = self.M @ M
        return old

    def restore(self, old):
        self.M, self.T = old


def rx(a):
    return h.rot_x(a)


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# ------------------------------------------------------------------ the ray caster
def render(scene, FW, FH, GR, detail=False):
    """`detail` (puzzle props, not the chests): dithered light on curved surfaces and a buffer of each hit's model height (contact shade)."""
    SS = h.SS
    Ry = h.rot_y(YAW)
    S = h.SCALE
    Hs, Ws = FH * SS, FW * SS
    depth = np.full((Hs, Ws), -1e9)
    code = np.full((Hs, Ws), -1, dtype=np.int16)
    ybuf = np.zeros((Hs, Ws)) if detail else None
    for it in scene.items:
        c = Ry @ it.c * S
        R = Ry @ it.R
        if isinstance(it, Box):
            e = it.e * S
            bound = float(np.linalg.norm(e)) + 0.5
        else:
            r = it.r * S
            bound = float(r.max()) + 0.4
        cx = FW / 2 + c[0]
        cy = GR - (c[1] * h.COSP - c[2] * h.SINP)
        x0, x1 = max(0, int((cx - bound) * SS)), min(Ws, int((cx + bound) * SS) + 1)
        y0, y1 = max(0, int((cy - bound) * SS)), min(Hs, int((cy + bound) * SS) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        a = (np.arange(x0, x1) + 0.5) / SS - FW / 2
        b = GR - (np.arange(y0, y1) + 0.5) / SS
        A, B = np.meshgrid(a, b)
        o = A[..., None] * h.XHAT + B[..., None] * h.UHAT
        sub = depth[y0:y1, x0:x1]
        if detail:  # a Bayer offset per art pixel: bands melt into each other on round surfaces
            PX, PY = np.meshgrid(np.arange(x0, x1) // SS, np.arange(y0, y1) // SS)
            dith = (BAYER_NP[PY % 4, PX % 4] / 16.0 - 0.47) * 0.16
        if isinstance(it, Box):
            q0 = (o - c) @ R  # local coordinates
            d = h.WHAT @ R
            d = np.where(np.abs(d) < 1e-9, 1e-9, d)
            t1 = (-e - q0) / d
            t2 = (e - q0) / d
            tmin = np.minimum(t1, t2).max(-1)
            tfar = np.maximum(t1, t2)
            t = tfar.min(-1)
            axis = tfar.argmin(-1)
            ok = (t >= tmin) & (t > sub)
            if not ok.any():
                continue
            q = q0 + t[..., None] * d
            nl = np.zeros(q.shape)
            for k in range(3):
                nl[..., k] = np.where(axis == k, np.sign(d[k]), 0.0)
            n = nl @ R.T
            lam = 0.78 * (n @ h.LIGHT) + 0.22 * (0.5 + 0.5 * n[..., 1]) - 0.06
            if detail and it.kind != "emit":
                lam = lam + dith * 0.6
            band = h.shade_band(lam, "", it.mat).astype(np.int16)
            ev = e / S  # model units for the texture rules
            ql = q / S
            if it.kind in ("wood", "metal", "stone"):
                # a bevel: the face's edges catch the light where the face is lit, and darken where it is not
                near = np.zeros(t.shape, int)
                for k in range(3):
                    near += (np.abs(ql[..., k]) > ev[k] - 0.62) & (axis != k)
                edge = near >= 1
                band = np.where(edge & (lam > 0.25), np.minimum(band + 1, 3), band)
                band = np.where(edge & (lam < 0.0), np.maximum(band - 1, 0), band)
            if it.kind == "wood":
                long = int(np.argmax(ev))
                o1, o2 = [k for k in range(3) if k != long]
                w = ql[..., o1] * 0.83 + ql[..., o2] * 0.83 + 0.45 * np.sin(ql[..., long] * 0.37 + it.seed * 5.1) + it.seed
                grain = (w % 1.6) < 0.32
                knot = ((ql[..., long] * 0.21 + it.seed * 3.3) % 1.0 < 0.05) & ((w % 2.3) < 0.9)
                band = np.where(grain | knot, np.maximum(band - 1, 0), band)
            elif it.kind == "stone":
                speck = (np.sin(ql[..., 0] * 3.1 + ql[..., 1] * 2.3) * np.sin(ql[..., 2] * 2.7 - ql[..., 0] * 1.3 + it.seed * 4.0)) > 0.62
                band = np.where(speck, np.maximum(band - 1, 0), band)
            elif it.kind == "emit":
                band = np.maximum(band, 2)
            codes = np.full(t.shape, it.mat, dtype=np.int16) * 4 + band
        else:
            M = np.diag(1.0 / r) @ R.T
            q0 = (o - c) @ M.T
            qd = M @ h.WHAT
            aa = qd @ qd
            bb = q0 @ qd
            cc = (q0 * q0).sum(-1) - 1.0
            disc = bb * bb - aa * cc
            ok = disc >= 0
            t = (-bb + np.sqrt(np.where(ok, disc, 0.0))) / aa
            ok &= t > sub
            if not ok.any():
                continue
            q = q0 + t[..., None] * qd
            n = (q / r) @ R.T
            n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
            lam = 0.78 * (n @ h.LIGHT) + 0.22 * (0.5 + 0.5 * n[..., 1]) - 0.06
            if detail and it.kind not in ("emit", "gem"):
                lam = lam + dith
            band = h.shade_band(lam, it.kind, it.mat).astype(np.int16)
            if it.kind == "emit":
                band = np.maximum(band, 2)
            elif it.kind == "gem":  # a cut stone: a hard glint and a deep core
                band = np.where(lam > 0.62, 3, np.where(lam > 0.1, 2, 1)).astype(np.int16)
            codes = np.full(t.shape, it.mat, dtype=np.int16) * 4 + band
        sub[ok] = t[ok]
        cs = code[y0:y1, x0:x1]
        cs[ok] = codes[ok]
        if detail:
            hit_y = (o[..., 1] + t * h.WHAT[1]) / S  # rotation about y keeps the height
            ybuf[y0:y1, x0:x1][ok] = hit_y[ok]
    if detail:
        return depth, code, ybuf
    return depth, code


def pixels(scene, FW, FH, GR, shadow):
    h.FW, h.FH, h.GROUND_ROW = FW, FH, GR
    depth, code = render(scene, FW, FH, GR)
    rows = h.to_pixels(depth, code)
    sx, sy, rxs, rys = shadow
    for y in range(FH):  # our own ground shadow (the hero's small one is wiped)
        for x in range(FW):
            if tuple(rows[y][x]) == (0, 0, 0, 70):
                rows[y][x] = CLEAR
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW / 2 - sx) / rxs, (y + 0.5 - GR - sy) / rys
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 80 if ex * ex + ey * ey < 0.55 else 54)
    return rows


def _hsh(x, y, seed=0):
    n = (x.astype(np.int64) * 374761393 + y.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _vnoise(x, y, seed=0):
    xi, yi = np.floor(x), np.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hsh(xi, yi, seed), _hsh(xi + 1, yi, seed)
    c_, d = _hsh(xi, yi + 1, seed), _hsh(xi + 1, yi + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c_ * (1 - fx) + d * fx) * fy


def _fbm(x, y, seed=0):
    return 0.55 * _vnoise(x, y, seed) + 0.3 * _vnoise(x * 2.1, y * 2.1, seed + 7) + 0.15 * _vnoise(x * 4.3, y * 4.3, seed + 13)


def pixels_detail(scene, FW, FH, GR, shadow, stones=(), woods=(), metals=(), lichen=None, seed=3):
    """The puzzle props' finish (the chests keep `pixels`): the hero renderer's majority vote per art pixel, then
    occlusion where a pixel sits deeper than its neighbours (joints, the bowl's hollow, under a rim), a darker band where
    it touches the ground, blotchy weathered stone with flecks of lichen, stretched grain on wood, rare glints on metal,
    a catch-light on top edges and a little reflected light on the dark rim, then the ink and outline as everywhere."""
    h.FW, h.FH, h.GROUND_ROW = FW, FH, GR
    SS = h.SS
    depth, code, ybuf = render(scene, FW, FH, GR, detail=True)
    k = len(h.RAMPS) * 4
    sub = code.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    dsub = depth.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    ysub = ybuf.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    opaque = (sub >= 0).sum(-1)
    best = np.full((FH, FW), -1, dtype=np.int32)
    best_w = np.zeros((FH, FW))
    for v in np.unique(sub[sub >= 0]):
        w = (sub == v).sum(-1) * h.DECAL_WEIGHT.get(int(v) // 4, 1.0)
        better = w > best_w
        best = np.where(better, v, best)
        best_w = np.where(better, w, best_w)
    solid = (opaque >= 6) & (best >= 0)
    dmean = np.where(sub >= 0, dsub, 0).sum(-1) / np.maximum(opaque, 1)
    ymean = np.where(sub >= 0, ysub, 0).sum(-1) / np.maximum(opaque, 1)
    mat = np.where(solid, best // 4, -1)
    band = np.where(solid, best % 4, 0)
    YY, XX = np.mgrid[0:FH, 0:FW]
    bay = BAYER_NP[YY % 4, XX % 4] / 16.0
    emissive = np.zeros((FH, FW), bool)
    for m, lo in EMISSIVE.items():
        emissive |= (mat == m) & (band >= lo)
    plain = solid & ~emissive
    # occlusion: how many neighbours (5 x 5) stand clearly in front of this pixel
    pad = 2
    dp = np.pad(np.where(solid, dmean, -1e9), pad, constant_values=-1e9)
    occ = np.zeros((FH, FW))
    for dy in range(-pad, pad + 1):
        for dx in range(-pad, pad + 1):
            if dx == 0 and dy == 0:
                continue
            nb = dp[pad + dy:pad + dy + FH, pad + dx:pad + dx + FW]
            occ += nb > dmean + 1.6
    occ /= 24.0
    band = np.where(plain & (occ > 0.22 + bay * 0.3), np.maximum(band - 1, 0), band)
    band = np.where(plain & (occ > 0.5 + bay * 0.2), np.maximum(band - 1, 0), band)
    # contact with the ground
    band = np.where(plain & (ymean < 0.9) & (bay < 0.75), np.maximum(band - 1, 0), band)
    band = np.where(plain & (ymean < 2.0) & (bay < 0.3), np.maximum(band - 1, 0), band)
    # surfaces
    xs, ys = XX.astype(float), YY.astype(float)
    n_st = _fbm(xs * 0.34, ys * 0.34, seed)
    r = _hsh(XX, YY, seed + 5)
    is_st = np.isin(mat, list(stones)) & plain
    band = np.where(is_st & (n_st > 0.62) & (r < 0.85), np.maximum(band - 1, 0), band)
    band = np.where(is_st & (n_st < 0.3) & (r < 0.55), np.minimum(band + 1, 3), band)
    band = np.where(is_st & (r > 0.965), np.maximum(band - 1, 0), band)  # pits
    is_wd = np.isin(mat, list(woods)) & plain
    n_wd = _fbm(xs * 0.09, ys * 0.62, seed + 11)
    band = np.where(is_wd & (n_wd > 0.6) & (r < 0.8), np.maximum(band - 1, 0), band)
    band = np.where(is_wd & (n_wd < 0.33) & (r < 0.5), np.minimum(band + 1, 3), band)
    is_mt = np.isin(mat, list(metals)) & plain
    band = np.where(is_mt & (r > 0.94) & (band >= 2), 3, band)
    lich = np.zeros((FH, FW), bool)
    if lichen is not None:  # small pale-green flecks on the upward stone
        n_li = _fbm(xs * 0.5, ys * 0.5, seed + 23)
        lich = is_st & (n_li > 0.66) & (r < 0.45) & (band >= 1)
        mat = np.where(lich, lichen, mat)
        band = np.where(lich, np.where(band >= 2, 2, 1), band)
    # catch-light on top edges, reflected light on the dark right rim
    above_clear = np.vstack([np.ones((1, FW), bool), ~solid[:-1]])
    right_clear = np.hstack([~solid[:, 1:], np.ones((FH, 1), bool)])
    band = np.where(plain & ~lich & above_clear & (band < 3) & (band >= 1), band + 1, band)
    band = np.where(plain & right_clear & (band == 0) & (bay < 0.6), 1, band)
    # ink where a pixel lies clearly behind a neighbour, then the outline (as art_hero3d.to_pixels)
    ink = np.zeros((FH, FW), bool)
    for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        nb = np.roll(np.roll(dmean, dy, 0), dx, 1)
        nbs = np.roll(np.roll(solid, dy, 0), dx, 1)
        ink |= solid & nbs & (nb > dmean + 2.4)
    px = [[CLEAR] * FW for _ in range(FH)]
    for y in range(FH):
        for x in range(FW):
            if solid[y, x]:
                m, b = int(mat[y, x]), int(band[y, x])
                if ink[y, x] and not emissive[y, x]:
                    b = 0
                px[y][x] = h.RAMPS[m][b]
    out = [row[:] for row in px]
    for y in range(FH):
        for x in range(FW):
            if solid[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < FW and 0 <= ny < FH and solid[ny, nx]:
                    out[y][x] = h.ink_color(int(mat[ny, nx]))
                    break
    sx, sy, rxs, rys = shadow
    for y in range(FH):
        for x in range(FW):
            if out[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW / 2 - sx) / rxs, (y + 0.5 - GR - sy) / rys
                q = ex * ex + ey * ey
                if q <= 1.0 and (q < 0.5 or bay[y, x] < 0.75):
                    out[y][x] = (0, 0, 0, 86 if q < 0.45 else 56)
    return out


def screen(p, FW, GR):
    """Model point -> px from the feet (the node's origin) after the yaw and the projection."""
    q = h.rot_y(YAW) @ V(*p) * h.SCALE
    return [round(float(q[0]), 1), round(float(-(q[1] * h.COSP - q[2] * h.SINP)), 1)]


def glow(rows):
    cols = {tuple(h.RAMPS[m][b]) for m, lo in EMISSIVE.items() for b in range(lo, 4)}
    return [[c if tuple(c) in cols else CLEAR for c in row] for row in rows]


# ------------------------------------------------------------------ shared pieces
def plank_wall(s, cx, cy, cz, half_w, half_h, axis_x, mat, n, seed, gap_mat=None):
    """`n` planks stacked up a wall: along x when `axis_x`, else along z. Thin dark gaps between them."""
    ph = half_h / n
    for i in range(n):
        y = cy - half_h + ph * (2 * i + 1)
        jit = ((i * 7 + seed * 13) % 5 - 2) * 0.06
        if axis_x:
            s.box((cx + jit, y, cz), (half_w, ph - 0.22, 0.62), mat, seed=seed + i * 0.37)
        else:
            s.box((cx, y, cz + jit), (0.62, ph - 0.22, half_w), mat, seed=seed + i * 0.37)
    if gap_mat is not None:  # what shows through the gaps
        if axis_x:
            s.box((cx, cy, cz - 0.15 * np.sign(cz or 1)), (half_w - 0.1, half_h - 0.1, 0.45), gap_mat, kind="")
        else:
            s.box((cx - 0.15 * np.sign(cx or 1), cy, cz), (0.45, half_h - 0.1, half_w - 0.1), gap_mat, kind="")


def barrel_lid(s, W, D, rise, k, mat, seed, band_xs=(), band_mat=None, band_kind="metal"):
    """A rounded lid of `k` planks running along x, in the hinge frame (hinge at the back top edge, the lid reaching towards +z)."""
    r = D / 2
    pts = []
    for i in range(k):
        a0 = math.pi * i / k
        a1 = math.pi * (i + 1) / k
        am = (a0 + a1) / 2
        z = r - r * math.cos(am)  # 0 at the hinge (back), D at the front
        y = rise * math.sin(am)
        pts.append((am, z, y))
        dz = r * (math.cos(a0) - math.cos(a1))
        dy = rise * (math.sin(a1) - math.sin(a0))
        length = math.hypot(dz, dy)
        tilt = math.atan2(dy, dz)
        s.box((0, y - 0.3, z), (W / 2, 0.8, length / 2 - 0.12), mat, R=rx(tilt), seed=seed + i * 0.53)
    s.box((0, rise * 0.45 - 0.4, D / 2), (W / 2 - 0.6, rise * 0.45, D / 2 - 0.4), DARK, kind="")  # the hollow under it (dark when open)
    for bx in band_xs:  # metal bands over the arc
        for i in range(k):
            a0 = math.pi * i / k
            a1 = math.pi * (i + 1) / k
            am = (a0 + a1) / 2
            z = r - r * math.cos(am)
            y = rise * math.sin(am)
            dz = r * (math.cos(a0) - math.cos(a1))
            dy = rise * (math.sin(a1) - math.sin(a0))
            length = math.hypot(dz, dy)
            tilt = math.atan2(dy, dz)
            s.box((bx, y + 0.62, z), (1.1, 0.32, length / 2 + 0.05), band_mat, R=rx(tilt), kind=band_kind)
    return pts


def lid_point(D, rise, am):
    r = D / 2
    return r - r * math.cos(am), rise * math.sin(am)


def hinge_frame(s, H, D, angle):
    """Enter the lid's frame: hinge at the back top edge, rotated up and back by `angle` degrees."""
    return s.frame(rx(-math.radians(angle)), (0, H, -D / 2))


def tufts(s, rng, around, n, mat=None, keep_out=None):
    mat = MOSS if mat is None else mat
    cx, cz, rxx, rzz = around
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        f = rng.uniform(0.95, 1.25)
        x, z = cx + math.cos(a) * rxx * f, cz + math.sin(a) * rzz * f
        if keep_out is not None and keep_out(x, z):
            continue
        for k in range(3):
            s.limb((x + k * 0.6 - 0.6, 0.0, z), (x + k * 0.9 - 0.9 + rng.uniform(-0.6, 0.6), rng.uniform(2.6, 4.6), z + rng.uniform(-0.4, 0.6)), 0.5, 0.18, mat)


# ------------------------------------------------------------------ gewöhnlich: die Wurzelkiste
CW, CD, CH, CRISE = 26.0, 15.0, 10.5, 4.6


def build_common(col):
    s = Scene()
    rng = np.random.default_rng(3)
    angle = LID[col]
    W, D, H = CW, CD, CH
    y0 = 1.2  # on two runners
    # the runners, half sunk in the turf
    for x in (-8.5, 8.5):
        s.box((x, 0.7, 0), (1.6, 0.9, D / 2 + 1.0), BARK, seed=x)
    # floor and the dark inside
    s.box((0, y0 + 0.5, 0), (W / 2 - 0.4, 0.5, D / 2 - 0.4), WOOD, seed=0.2)
    s.box((0, y0 + 1.1, 0), (W / 2 - 1.3, 0.2, D / 2 - 1.3), DARK, kind="")
    # walls: three planks front and back, two on the ends; inside dark linings
    plank_wall(s, 0, y0 + H / 2, D / 2 - 0.62, W / 2, H / 2, True, WOOD, 3, 1.1)
    plank_wall(s, 0, y0 + H / 2, -D / 2 + 0.62, W / 2, H / 2, True, WOOD, 3, 2.3)
    plank_wall(s, W / 2 - 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, WOOD, 3, 3.7)
    plank_wall(s, -W / 2 + 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, WOOD, 3, 4.9)
    for z, sgn in ((D / 2 - 1.35, -1), (-D / 2 + 1.35, 1)):
        s.box((0, y0 + H / 2 - 0.5, z), (W / 2 - 1.4, H / 2 - 0.7, 0.1), DARK, kind="")
    for x in (W / 2 - 1.35, -W / 2 + 1.35):
        s.box((x, y0 + H / 2 - 0.5, 0), (0.1, H / 2 - 0.7, D / 2 - 1.4), DARK, kind="")
    # corner posts and rusty corner brackets
    for x in (-W / 2, W / 2):
        for z in (-D / 2, D / 2):
            s.box((x - 0.2 * np.sign(x), y0 + H / 2, z - 0.2 * np.sign(z)), (0.95, H / 2 + 0.2, 0.95), WOOD, seed=x * 0.1 + z)
            s.box((x, y0 + H - 1.6, z), (1.15, 1.6, 1.15), RUST, kind="metal")
            s.box((x, y0 + 1.6, z), (1.15, 1.6, 1.15), RUST, kind="metal")
    # two rusty bands down the front and over the east end
    for x in (-7.0, 7.0):
        s.box((x, y0 + H / 2, D / 2 + 0.2), (1.0, H / 2, 0.28), RUST, kind="metal")
        for yy in (2.0, H - 2.0):
            s.ell((x, y0 + yy, D / 2 + 0.55), (0.45, 0.45, 0.3), RUST)
    s.box((W / 2 + 0.2, y0 + H / 2, 0), (0.28, H / 2, 1.0), RUST, kind="metal")
    # A worn iron pull on the visible end, with a real hollow centre.
    for z in (-2.2, 2.2):
        s.ell((W / 2 + 0.9, y0 + H * 0.65, z), (0.5, 0.8, 0.65), RUST)
    for k in range(12):
        a = math.pi * k / 11
        s.ell((W / 2 + 1.2, y0 + H * 0.65 - 2.1 * math.sin(a), 2.2 * math.cos(a)), (0.48, 0.48, 0.48), RUST)
    # the inside (shows when the lid is up): a cloth bundle, copper coins, a glass vial, a silvery shimmer
    s.ell((-5.5, y0 + H - 3.0, -1.0), (4.6, 3.6, 4.0), CLOTH)  # a tied bundle, a strap round it
    s.ell((-5.5, y0 + H + 0.3, -1.4), (1.8, 0.9, 1.3), CLOTH)
    s.limb((-5.5, y0 + H - 6.0, 2.6), (-5.5, y0 + H + 0.2, 1.8), 0.45, 0.45, RUST)
    s.ell((3.0, y0 + H - 3.4, 0.0), (3.0, 2.6, 2.6), CLOTH)
    # Folded linen and a small leather-bound field journal behind the bundle.
    for k in range(3):
        s.box((2.2, y0 + H - 2.1 + k * 0.55, -3.4), (3.0, 0.22, 1.6), CLOTH, kind="")
    s.box((-7.8, y0 + H - 0.1, -3.3), (2.3, 0.65, 1.6), BARK, kind="")
    s.box((-7.8, y0 + H + 0.15, -1.65), (1.7, 0.22, 0.12), CLOTH, kind="")
    for k, (x, z) in enumerate(((1.0, 2.2), (3.2, 0.8), (5.0, 2.6), (2.4, -1.6), (5.8, -0.2), (0.0, 0.2), (3.8, 3.4))):
        s.ell((x, y0 + H - 0.6 + (k % 3) * 0.4, z), (1.25, 0.32, 1.1), COPPER, R=rx(0.15 * (k % 3 - 1)), kind="emit" if k % 2 else "")
    s.limb((8.2, y0 + H - 5.0, -2.4), (8.6, y0 + H + 1.2, -2.8), 1.1, 0.9, TEAL, kind="emit")
    s.ell((8.65, y0 + H + 1.8, -2.85), (0.65, 0.5, 0.65), CLOTH)
    # the overgrowth: a root clawing up the east end, moss on the runners and the base, a teal shelf fungus
    pts = [(W / 2 + 3.0, 0.2, -D / 2 + 1.0), (W / 2 + 1.4, 2.6, -D / 2 + 3.0), (W / 2 + 0.9, 5.6, -2.4), (W / 2 + 1.1, 8.0, 0.4), (W / 2 + 0.6, 9.6, 3.2)]
    for a, b in zip(pts, pts[1:]):
        s.limb(a, b, 1.15, 0.8, BARK)
    s.limb(pts[2], (W / 2 + 1.6, 4.0, 2.2), 0.6, 0.35, BARK)
    s.ell((W / 2 + 1.1, 2.4, 3.8), (1.0, 0.45, 1.6), TEAL, kind="emit")
    s.ell((W / 2 + 1.2, 3.4, 5.0), (0.75, 0.38, 1.1), TEAL, kind="emit")
    s.ell((-W / 2 + 1.0, y0 + 0.8, D / 2 + 1.0), (4.0, 1.0, 1.6), MOSS)
    s.ell((W / 2 - 3.0, y0 + 0.6, D / 2 + 1.0), (3.0, 0.9, 1.2), MOSS)
    tufts(s, rng, (0, 1.0, W / 2 + 2.5, D / 2 + 2.5), 14)
    s.ell((-W / 2 - 3.5, 0.9, D / 2 + 0.5), (1.8, 1.1, 1.4), STONE, kind="stone")
    s.ell((-W / 2 - 1.2, 0.7, D / 2 + 2.4), (1.1, 0.8, 0.9), STONE, kind="stone")
    # the padlock: hanging shut on the hasp (column 0), else lying open in the grass in front
    if col == 0:
        s.limb((-1.0, y0 + H - 1.6, D / 2 + 1.25), (1.0, y0 + H - 1.6, D / 2 + 1.25), 0.38, 0.38, RUST)
        s.limb((-1.0, y0 + H - 1.6, D / 2 + 1.25), (-1.0, y0 + H - 3.2, D / 2 + 1.25), 0.38, 0.38, RUST)
        s.limb((1.0, y0 + H - 1.6, D / 2 + 1.25), (1.0, y0 + H - 3.2, D / 2 + 1.25), 0.38, 0.38, RUST)
        s.box((0, y0 + H - 4.6, D / 2 + 1.25), (1.7, 1.5, 0.75), RUST, kind="metal")
        s.ell((0, y0 + H - 4.8, D / 2 + 2.05), (0.3, 0.45, 0.2), DARK)
    else:
        s.box((4.5, 0.75, D / 2 + 4.0), (1.7, 0.75, 1.5), RUST, R=h.rot_y(0.6), kind="metal")
        s.limb((3.4, 1.4, D / 2 + 3.2), (2.6, 2.4, D / 2 + 3.6), 0.35, 0.35, RUST)
    # the lid
    old = hinge_frame(s, y0 + H, D, angle)
    barrel_lid(s, W + 0.6, D + 0.6, CRISE, 5, WOOD, 7.0, band_xs=(-7.0, 7.0), band_mat=RUST)
    for x in (-W / 2 - 0.3, W / 2 + 0.3):  # end boards of the lid (half discs)
        for i in range(4):
            am = math.pi * (i + 0.5) / 4
            z, y = lid_point(D + 0.6, CRISE, am)
            s.box((x, y * 0.5, z), (0.5, y * 0.5 + 0.2, (D + 0.6) / 8 + 0.2), WOOD, seed=i + x)
    z, y = lid_point(D + 0.6, CRISE, math.pi * 0.62)
    s.ell((-6.0, y + 0.9, z - 1.0), (4.2, 0.7, 2.6), MOSS)  # moss on the lid
    z, y = lid_point(D + 0.6, CRISE, math.pi * 0.45)
    s.ell((5.0, y + 0.8, z), (2.6, 0.6, 1.8), MOSS)
    s.box((0, -1.2, D + 0.75), (1.4, 1.9, 0.3), RUST, kind="metal")  # the hasp hanging over the front
    s.ell((0, -2.6, D + 1.0), (0.5, 0.5, 0.3), DARK)
    s.box((0, -0.5, D * 0.4), (W / 2 - 3.0, 0.16, D * 0.22), CLOTH, kind="")  # a rag nailed to the lid's inside
    # Rag folds, a patched corner and uneven stitches, all beneath the lid.
    for x in (-7.0, -2.0, 3.0, 7.0):
        s.limb((x, -0.95, D * 0.2), (x + 1.2, -0.95, D * 0.6), 0.45, 0.3, BARK)
    s.box((5.0, -0.85, D * 0.43), (1.6, 0.12, 1.3), WOOD, kind="")
    for x in (-8.0, -5.0, -2.0, 1.0, 4.0, 7.0):
        s.ell((x, -0.86, D * 0.22), (0.3, 0.18, 0.48), WAX)
    for x in (-W / 2 + 2.0, W / 2 - 2.0):
        s.box((x, -0.55, D * 0.45), (0.55, 0.3, D * 0.36), BARK)
    s.restore(old)
    return s


def common_info(FW, GR):
    return {
        "mouth": screen((0, 1.2 + CH + 1.0, 0), FW, GR),
        "lock": screen((0, 1.2 + CH - 4.6, CD / 2 + 1.25), FW, GR),
        "lid_top": screen((0, 1.2 + CH + CRISE, 0), FW, GR),
        "foot": [CW * h.SCALE + 2, 9],
    }


# ------------------------------------------------------------------ selten: die Mondsiegeltruhe
RW, RD, RH, RRISE = 30.0, 17.0, 11.5, 6.2


def build_rare(col):
    s = Scene()
    rng = np.random.default_rng(5)
    angle = LID[col]
    W, D, H = RW, RD, RH
    y0 = 2.0  # on claw feet
    for x in (-W / 2 + 1.6, W / 2 - 1.6):  # claw feet
        for z in (-D / 2 + 1.6, D / 2 - 1.6):
            s.ell((x, 1.1, z), (1.9, 1.3, 1.9), STEEL)
            for k in (-1, 0, 1):
                s.ell((x + k * 1.1, 0.5, z + 1.4 * np.sign(z)), (0.55, 0.5, 0.9), STEEL)
    s.box((0, y0 + 0.5, 0), (W / 2 - 0.4, 0.5, D / 2 - 0.4), IRONWOOD, seed=1.0)
    s.box((0, y0 + 1.1, 0), (W / 2 - 1.3, 0.2, D / 2 - 1.3), VELVET, kind="")
    plank_wall(s, 0, y0 + H / 2, D / 2 - 0.62, W / 2, H / 2, True, IRONWOOD, 3, 2.2)
    plank_wall(s, 0, y0 + H / 2, -D / 2 + 0.62, W / 2, H / 2, True, IRONWOOD, 3, 3.1)
    plank_wall(s, W / 2 - 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, IRONWOOD, 3, 4.4)
    plank_wall(s, -W / 2 + 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, IRONWOOD, 3, 5.6)
    for z in (D / 2 - 1.35, -D / 2 + 1.35):  # velvet lining inside
        s.box((0, y0 + H / 2 - 0.6, z), (W / 2 - 1.4, H / 2 - 0.9, 0.1), VELVET, kind="")
    for x in (W / 2 - 1.35, -W / 2 + 1.35):
        s.box((x, y0 + H / 2 - 0.6, 0), (0.1, H / 2 - 0.9, D / 2 - 1.4), VELVET, kind="")
    # steel: corner caps, a rim at the top and the base, rivets
    for x in (-W / 2, W / 2):
        for z in (-D / 2, D / 2):
            s.box((x, y0 + H / 2, z), (1.2, H / 2 + 0.3, 1.2), STEEL, kind="metal")
            s.ell((x + 0.9 * np.sign(x), y0 + H - 1.4, z + 0.9 * np.sign(z)), (0.45, 0.45, 0.45), STEEL)
            s.ell((x + 0.9 * np.sign(x), y0 + 1.6, z + 0.9 * np.sign(z)), (0.45, 0.45, 0.45), STEEL)
    for yy in (y0 + 0.9, y0 + H - 0.7):
        s.box((0, yy, D / 2 + 0.05), (W / 2, 0.7, 0.3), STEEL, kind="metal")
        s.box((W / 2 + 0.05, yy, 0), (0.3, 0.7, D / 2), STEEL, kind="metal")
        for x in np.linspace(-W / 2 + 4, W / 2 - 4, 6):
            s.ell((x, yy, D / 2 + 0.45), (0.35, 0.35, 0.25), STEEL)
    # runes cut into the front planks, glowing faintly
    for k, x in enumerate((-11.0, -8.0, 8.0, 11.0)):
        yy = y0 + H / 2 + (0.6 if k % 2 else -0.4)
        s.box((x, yy, D / 2 + 0.05), (0.32, 1.3, 0.12), MOON, kind="emit")
        s.box((x + 0.6 * (1 if k < 2 else -1), yy + 0.7, D / 2 + 0.05), (0.55, 0.28, 0.12), MOON, kind="emit")
    # Paired silver chevrons frame the seal; dark centres keep the carving readable.
    for side in (-1, 1):
        for height in (3.3, 7.0):
            x = side * 7.0
            for dx in (-1.8, 1.8):
                s.limb((x + dx, y0 + height, D / 2 + 0.4), (x, y0 + height + 1.6, D / 2 + 0.4), 0.32, 0.32, STEEL)
    # the lock plate with the crescent and the moonstone seal
    ly = y0 + H - 4.0
    s.ell((0, ly, D / 2 + 0.55), (3.9, 3.9, 0.6), STEEL, kind="")
    for k in range(9):  # the crescent round the stone
        a = math.radians(200 + k * 17.5)
        s.ell((3.0 * math.cos(a), ly + 3.0 * math.sin(a), D / 2 + 1.0), (0.55, 0.55, 0.3), STEEL)
    if col == 0:
        s.ell((0, ly, D / 2 + 1.25), (1.9, 1.9, 1.0), MOON, kind="gem")
        s.ell((-0.55, ly + 0.6, D / 2 + 2.05), (0.5, 0.5, 0.25), MOON, kind="emit")
        for k in range(6):  # the wax-like rim of the seal
            a = k * math.pi / 3 + 0.3
            s.ell((2.25 * math.cos(a), ly + 2.25 * math.sin(a), D / 2 + 1.1), (0.55, 0.55, 0.35), MOON, kind="emit")
    else:
        s.ell((0, ly, D / 2 + 0.9), (1.7, 1.7, 0.5), DARK)
        for a in (0.4, 2.3, 4.4):
            s.ell((1.4 * math.cos(a), ly + 1.4 * math.sin(a), D / 2 + 1.1), (0.45, 0.6, 0.35), MOON, kind="emit")
    # moon crystals growing out of the ground at the back east corner and a small cluster at the front west
    for (x, z, sc) in ((W / 2 + 2.0, -D / 2 + 1.0, 1.0), (-W / 2 - 1.6, D / 2 + 1.2, 0.6)):
        s.ell((x, 0.8, z), (3.4 * sc, 1.3, 2.6 * sc), STONE, kind="stone")
        for k, (dx, dz, ln, lean) in enumerate(((0.0, 0.0, 8.5, 0.12), (1.6, 0.8, 5.5, -0.42), (-1.5, 0.5, 6.0, 0.5), (0.6, -1.3, 4.4, -0.2), (-0.4, 1.5, 3.6, 0.3))):
            ln *= sc
            base = V(x + dx * sc, 0.8, z + dz * sc)
            tip = base + V(math.sin(lean) * ln * 0.6, ln, math.sin(lean * 1.7) * ln * 0.2)
            mid = (base + tip) / 2
            axis = tip - base
            R = h.frame_from(axis, V(0, 0, 1))
            s.ell(tuple(mid), (0.95 * sc + 0.35, ln / 2, 0.95 * sc + 0.35), MOON, R=R, kind="gem")
    # the inside: a blue crystal, a rolled scroll, silver coins, a small potion
    s.ell((0, y0 + H - 3.4, 0), (W / 2 - 2.0, 3.0, D / 2 - 2.0), VELVET)  # a velvet cushion filling the chest
    s.ell((4.5, y0 + H + 1.2, -1.2), (1.7, 3.6, 1.7), MOON, R=rz(0.35), kind="gem")  # the moon crystal standing in it
    s.ell((6.4, y0 + H + 0.2, 0.4), (1.0, 2.2, 1.0), MOON, R=rz(-0.55), kind="gem")
    s.ell((2.8, y0 + H - 0.3, 0.6), (0.8, 1.6, 0.8), MOON, R=rz(0.9), kind="gem")
    s.limb((-11.0, y0 + H - 0.4, 1.8), (-4.0, y0 + H + 0.2, -0.8), 1.4, 1.4, CLOTH)  # a scroll with a blue ribbon
    s.ell((-7.4, y0 + H + 0.0, 0.5), (0.5, 1.5, 1.5), MOON, kind="emit")
    for k, (x, z) in enumerate(((-6.0, 3.2), (-3.8, 3.6), (-1.0, 2.6), (0.8, 3.8), (-9.0, -1.8), (-2.0, -2.2))):
        s.ell((x, y0 + H - 0.2 + (k % 2) * 0.4, z), (1.2, 0.32, 1.05), SILVER, kind="emit" if k % 2 else "")
    s.limb((10.5, y0 + H - 2.0, 2.4), (10.5, y0 + H + 2.4, 2.4), 1.3, 0.55, VELVET)  # a small potion
    s.ell((10.5, y0 + H - 0.4, 2.4), (1.45, 1.7, 1.45), VIOLET, kind="emit")
    # A narrow fitted tray separates scrolls from the moonstones.
    s.box((-2.8, y0 + H - 0.7, 0), (0.38, 1.4, D / 2 - 2.0), STEEL, kind="metal")
    for x in (-10.0, -6.0):
        s.limb((x, y0 + H + 0.5, -4.5), (x + 0.8, y0 + H + 0.5, -1.0), 0.95, 0.95, WAX)
        s.ell((x + 0.8, y0 + H + 0.5, -0.9), (0.5, 0.5, 0.25), CLOTH)
        s.ell((x + 0.4, y0 + H + 0.6, -2.7), (1.0, 1.0, 0.28), VELVET)
    tufts(s, rng, (0, 1.0, W / 2 + 3.0, D / 2 + 2.6), 10)
    # the lid: rounded ironwood, three steel bands, a crescent of moonstone on the front, runes along the middle band
    old = hinge_frame(s, y0 + H, D, angle)
    barrel_lid(s, W + 0.8, D + 0.8, RRISE, 6, IRONWOOD, 3.0, band_xs=(-10.5, 0.0, 10.5), band_mat=STEEL)
    for x in (-W / 2 - 0.4, W / 2 + 0.4):
        for i in range(5):
            am = math.pi * (i + 0.5) / 5
            z, y = lid_point(D + 0.8, RRISE, am)
            s.box((x, y * 0.5, z), (0.55, y * 0.5 + 0.2, (D + 0.8) / 10 + 0.25), IRONWOOD, seed=i * 1.3 + x)
        s.box((x * 1.02, RRISE * 0.5, (D + 0.8) / 2), (0.3, 0.6, (D + 0.8) / 2), STEEL, kind="metal")
    for k in range(7):  # runes along the middle band
        am = math.pi * (0.2 + k * 0.1)
        z, y = lid_point(D + 0.8, RRISE, am)
        s.ell((0, y + 1.0, z), (0.42, 0.3, 0.42), MOON, kind="emit")
    z, y = lid_point(D + 0.8, RRISE, math.pi * 0.8)
    for k in range(7):  # a crescent moon on the lid's front slope
        a = math.radians(120 + k * 20)
        s.ell((5.6 + 2.0 * math.cos(a), y + 0.9 + 1.2 * math.sin(a) * 0.4, z + 2.0 * math.sin(a) * 0.5), (0.6, 0.4, 0.6), MOON, kind="emit")
    # Constellation engraving on the dome, carried by the lid through every pose.
    for x, am in ((-5.5, 0.35), (-3.5, 0.48), (-5.0, 0.63)):
        z, y = lid_point(D + 0.8, RRISE, math.pi * am)
        s.ell((x, y + 0.8, z), (0.45, 0.3, 0.45), MOON, kind="emit")
    s.box((0, -0.8, D + 0.95), (1.6, 1.6, 0.3), STEEL, kind="metal")  # the hasp
    s.box((0, -0.5, D * 0.45), (W / 2 - 1.2, 0.16, D * 0.42), VELVET, kind="")  # velvet inside the lid with silver stars
    # Stitched velvet panels and an inset silver border, surrounding a constellation.
    for x in (-W / 2 + 2.1, W / 2 - 2.1):
        s.limb((x, -1.0, 1.4), (x, -1.0, D * 0.8), 0.48, 0.48, STEEL)
    for z in (1.4, D * 0.8):
        s.limb((-W / 2 + 2.1, -1.0, z), (W / 2 - 2.1, -1.0, z), 0.48, 0.48, STEEL)
    constellation = [(-8.0, 3.0), (-3.0, 5.0), (2.0, 2.6), (7.0, 4.4), (11.0, 2.4)]
    for (x1, z1), (x2, z2) in zip(constellation, constellation[1:]):
        s.limb((x1, -1.0, z1), (x2, -1.0, z2), 0.4, 0.4, STEEL)
    for x in (-9.0, -3.0, 3.0, 9.0):
        s.limb((x - 2.0, -1.0, 9.0), (x, -1.0, 11.0), 0.4, 0.4, DARK)
        s.limb((x, -1.0, 11.0), (x + 2.0, -1.0, 9.0), 0.4, 0.4, DARK)
    for k, (x, z) in enumerate(((-8.0, 3.0), (-3.0, 5.0), (2.0, 2.6), (7.0, 4.4), (11.0, 2.4), (-11.0, 4.6))):
        s.ell((x, -0.72, z), (0.35, 0.2, 0.35), MOON if k % 2 else SILVER, kind="emit")
    s.restore(old)
    return s


def rare_info(FW, GR):
    y0 = 2.0
    return {
        "mouth": screen((0, y0 + RH + 1.0, 0), FW, GR),
        "lock": screen((0, y0 + RH - 4.0, RD / 2 + 1.3), FW, GR),
        "lid_top": screen((0, y0 + RH + RRISE, 0), FW, GR),
        "crystals": screen((RW / 2 + 2.0, 5.0, -RD / 2 + 1.0), FW, GR),
        "foot": [RW * h.SCALE + 2, 10],
    }


# ------------------------------------------------------------------ legendär: das Glutreliquiar
LW, LD, LH, LRISE, LY0 = 32.0, 18.0, 12.5, 7.4, 4.4


def chain(s, pts, phase=0.0):
    """Black chain links along a polyline, every third with a violet vein of the void."""
    pts = [V(*p) for p in pts]
    k = 0
    for a, b in zip(pts, pts[1:]):
        seg = b - a
        length = float(np.linalg.norm(seg))
        n = max(1, int(length / 2.5))
        for i in range(n):
            c = a + seg * (i + 0.5) / n
            R = h.frame_from(seg, V(0, 0, 1) if (k % 2) else V(1, 0, 0))
            s.ell(tuple(c), (1.15, 1.6, 0.6), VIOLET if (k + int(phase)) % 4 == 0 else CHAIN, R=R, kind="emit" if (k + int(phase)) % 4 == 0 else "")
            k += 1


def build_legendary(col):
    s = Scene()
    rng = np.random.default_rng(9)
    angle = LID[col]
    W, D, H, y0 = LW, LD, LH, LY0
    # the plinth: two steps of old stone, cracked, mossy, with the void's veins creeping over it from the back
    s.box((0, 1.2, 0), (W / 2 + 6.0, 1.2, D / 2 + 4.6), STONE, kind="stone", seed=0.4)
    s.box((0, 3.2, -0.4), (W / 2 + 3.2, 1.0, D / 2 + 2.4), STONE, kind="stone", seed=1.7)
    for x in np.linspace(-W / 2 - 4.0, W / 2 + 4.0, 7):  # the joints of the lower step's front
        s.box((x, 1.2, D / 2 + 4.62), (0.12, 1.1, 0.1), DARK, kind="")
    s.ell((-W / 2 - 3.6, 2.5, D / 2 + 3.4), (3.2, 0.7, 1.4), MOSS)
    s.ell((W / 2 + 4.6, 2.5, 2.0), (2.0, 0.6, 3.0), MOSS)
    for pts in (((-W / 2 - 4.0, 4.25, -D / 2 - 1.5), (-W / 2, 4.25, -D / 2 + 2.0), (-W / 2 - 1.5, 4.25, 1.0)),
                ((W / 2 + 2.6, 4.25, -D / 2 - 1.8), (W / 2 + 1.2, 4.25, -2.0), (W / 2 + 3.0, 4.25, 3.0), (W / 2 + 3.0, 2.0, D / 2 + 2.6))):
        for a, b in zip(pts, pts[1:]):
            s.limb(a, b, 0.42, 0.32, VIOLET, kind="emit")
    # two candles on the upper step's front corners
    for x, tall in ((-W / 2 - 4.2, 6.4), (W / 2 + 4.2, 4.6)):
        cz = D / 2 + 2.6
        s.ell((x, 2.6, cz), (2.0, 0.45, 1.7), WAX)  # the puddle of old wax
        s.limb((x, 2.4, cz), (x, 2.4 + tall, cz), 1.15, 1.0, WAX)
        s.ell((x - 0.6, 2.4 + tall * 0.6, cz + 1.0), (0.45, 1.2, 0.35), WAX)  # a drip
        s.limb((x, 2.4 + tall, cz), (x + 0.15, 4.9 + tall, cz), 0.85, 0.2, AMBER, kind="emit")
    # the body: black lacquer planks, gold everywhere
    s.box((0, y0 + 0.5, 0), (W / 2 - 0.4, 0.5, D / 2 - 0.4), LACQUER, seed=2.0)
    s.box((0, y0 + 1.1, 0), (W / 2 - 1.3, 0.2, D / 2 - 1.3), WINE, kind="")
    plank_wall(s, 0, y0 + H / 2, D / 2 - 0.62, W / 2, H / 2, True, LACQUER, 3, 6.1)
    plank_wall(s, 0, y0 + H / 2, -D / 2 + 0.62, W / 2, H / 2, True, LACQUER, 3, 7.2)
    plank_wall(s, W / 2 - 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, LACQUER, 3, 8.3)
    plank_wall(s, -W / 2 + 0.62, y0 + H / 2, 0, D / 2 - 1.2, H / 2, False, LACQUER, 3, 9.4)
    for z in (D / 2 - 1.35, -D / 2 + 1.35):
        s.box((0, y0 + H / 2 - 0.6, z), (W / 2 - 1.4, H / 2 - 0.9, 0.1), WINE, kind="")
    for x in (W / 2 - 1.35, -W / 2 + 1.35):
        s.box((x, y0 + H / 2 - 0.6, 0), (0.1, H / 2 - 0.9, D / 2 - 1.4), WINE, kind="")
    for x in (-W / 2, W / 2):  # gold corners with a leaf flourish at the top
        for z in (-D / 2, D / 2):
            s.box((x, y0 + H / 2, z), (1.0, H / 2 + 0.4, 1.0), GOLD, kind="metal")
            for k, (dy, lean) in enumerate(((1.8, 0.7), (3.6, 0.35))):
                s.ell((x - np.sign(x) * dy * 0.7, y0 + H - dy * 0.55, z + np.sign(z) * 1.3), (dy * 0.55, 0.65, 0.3), GOLD, R=rz(np.sign(x) * lean))
            s.ell((x, y0 + 0.4, z), (1.9, 0.9, 1.9), GOLD)
    for yy in (y0 + 0.9, y0 + H - 0.7):  # gold rims
        s.box((0, yy, D / 2 + 0.05), (W / 2, 0.55, 0.32), GOLD, kind="metal")
        s.box((W / 2 + 0.05, yy, 0), (0.32, 0.75, D / 2), GOLD, kind="metal")
    for x in (-9.5, 9.5):  # gold vine bands up the front with curls and molten seams
        s.box((x, y0 + H / 2, D / 2 + 0.2), (0.7, H / 2 - 0.6, 0.3), GOLD, kind="metal")
        s.box((x, y0 + H / 2, D / 2 + 0.52), (0.2, H / 2 - 1.6, 0.08), AMBER, kind="emit")
        for yy in (y0 + 3.4, y0 + H - 3.2):
            s.ell((x, yy, D / 2 + 0.6), (0.6, 0.6, 0.3), GOLD)
    # A recessed diamond escutcheon on the visible end, with a garnet centre.
    for k in range(4):
        a, b = k * math.pi / 2, (k + 1) * math.pi / 2
        s.limb((W / 2 + 0.65, y0 + H / 2 + 3.5 * math.sin(a), 3.7 * math.cos(a)),
               (W / 2 + 0.65, y0 + H / 2 + 3.5 * math.sin(b), 3.7 * math.cos(b)), 0.42, 0.42, GOLD)
    s.ell((W / 2 + 1.0, y0 + H / 2, 0), (0.6, 1.55, 1.1), WINE, kind="gem")
    # the sun lock: a gold disc with rays, an amber heart
    ly = y0 + H - 5.4
    s.ell((0, ly, D / 2 + 0.6), (4.4, 4.4, 0.7), GOLD, kind="")
    for k in range(12):
        a = k * math.pi / 6
        ln = 2.2 if k % 2 else 1.4
        s.limb((4.4 * math.cos(a), ly + 4.4 * math.sin(a), D / 2 + 0.7), ((4.4 + ln) * math.cos(a), ly + (4.4 + ln) * math.sin(a), D / 2 + 0.6), 0.5, 0.2, GOLD)
    s.ell((0, ly, D / 2 + 1.35), (2.2, 2.2, 1.0), AMBER, kind="gem")
    s.ell((-0.6, ly + 0.7, D / 2 + 2.2), (0.55, 0.55, 0.25), AMBER, kind="emit")
    # the inside: wine-red velvet, heaped gold coins, a goblet, the glow of the hoard
    s.ell((0, y0 + H - 2.2, 0), (W / 2 - 3.0, 3.2, D / 2 - 3.0), WINE)
    for k in range(34):
        x, z = rng.uniform(-W / 2 + 3, W / 2 - 3), rng.uniform(-D / 2 + 2.6, D / 2 - 2.6)
        hgt = H + 1.6 - 3.4 * ((x / (W / 2)) ** 2 + (z / (D / 2)) ** 2)
        s.ell((x, y0 + hgt + rng.uniform(-0.3, 0.3), z), (1.25, 0.34, 1.1), GOLD, R=rx(rng.uniform(-0.4, 0.4)), kind="")
    # Distinct coin stacks, a pearl strand and a garnet brooch on the velvet.
    for x, z, count in ((-3.5, -3.0, 4), (8.0, -3.8, 3), (9.5, 2.5, 2)):
        for k in range(count):
            s.ell((x, y0 + H + k * 0.58, z), (1.5, 0.22, 1.3), GOLD)
    for k in range(11):
        a = math.pi * 0.15 + k * math.pi * 1.6 / 10
        s.ell((2.3 + 3.6 * math.cos(a), y0 + H + 1.2, 1.4 + 2.1 * math.sin(a)), (0.45, 0.45, 0.45), WAX)
    s.ell((3.0, y0 + H + 1.5, 3.0), (1.6, 0.45, 1.3), GOLD)
    s.ell((3.0, y0 + H + 2.0, 3.0), (0.95, 0.65, 0.8), WINE, kind="gem")
    s.ell((-8.5, y0 + H, -1.5), (1.4, 0.5, 1.2), GOLD)  # a goblet standing in the hoard
    s.limb((-8.5, y0 + H, -1.5), (-8.5, y0 + H + 2.4, -1.5), 0.55, 0.45, GOLD)
    s.ell((-8.5, y0 + H + 3.4, -1.5), (1.9, 1.5, 1.9), GOLD)
    s.ell((-8.5, y0 + H + 4.3, -1.5), (1.3, 0.4, 1.3), WINE)
    s.ell((6.5, y0 + H + 1.0, 0.5), (1.4, 1.4, 1.4), WINE, kind="gem")
    s.ell((2.0, y0 + H + 1.3, -2.0), (1.1, 1.1, 1.1), MOON, kind="gem")
    # the lid: lacquer dome, gold bands and ridge, the sun heart with gold wings, molten seams
    old = hinge_frame(s, y0 + H, D, angle)
    barrel_lid(s, W + 1.0, D + 1.0, LRISE, 7, LACQUER, 5.0, band_xs=(-9.0, 9.0), band_mat=GOLD)
    for x in (-W / 2 - 0.5, W / 2 + 0.5):
        for i in range(6):
            am = math.pi * (i + 0.5) / 6
            z, y = lid_point(D + 1.0, LRISE, am)
            s.box((x, y * 0.5, z), (0.6, y * 0.5 + 0.2, (D + 1.0) / 12 + 0.3), LACQUER, seed=i + x * 0.7)
        s.box((x * 1.03, LRISE * 0.5, (D + 1.0) / 2), (0.32, 0.7, (D + 1.0) / 2), GOLD, kind="metal")
    z, y = lid_point(D + 1.0, LRISE, math.pi / 2)
    s.box((0, y + 0.9, z), (W / 2 + 0.6, 0.6, 0.8), GOLD, kind="metal")  # the ridge
    for x in (-9.0, 9.0):  # molten seams along the gold bands
        for k in range(5):
            am = math.pi * (0.3 + k * 0.1)
            z, y = lid_point(D + 1.0, LRISE, am)
            s.ell((x, y + 1.05, z), (0.3, 0.2, 0.55), AMBER, kind="emit")
    z, y = lid_point(D + 1.0, LRISE, math.pi * 0.74)  # the sun heart on the front slope
    s.ell((0, y + 0.8, z), (3.2, 1.4, 2.6), GOLD)
    s.ell((0, y + 1.9, z + 0.4), (2.0, 1.3, 1.7), AMBER, kind="gem")
    s.ell((-0.6, y + 2.8, z + 0.6), (0.6, 0.35, 0.5), AMBER, kind="emit")
    for side in (-1, 1):  # two small gold wings beside it
        for k in range(4):
            s.ell((side * (3.6 + k * 1.3), y + 1.2 + k * 0.35, z - k * 0.5), (1.3, 0.45, 0.9 - k * 0.12), GOLD, R=rz(side * (0.35 + k * 0.12)))
    s.box((0, -0.8, D + 1.15), (1.8, 1.8, 0.32), GOLD, kind="metal")  # the hasp
    s.box((0, -0.5, D * 0.45), (W / 2 - 1.2, 0.16, D * 0.42), WINE, kind="")  # wine velvet inside the lid with a gold sun
    # Double gold piping and quilted burgundy panels frame the order's sun.
    for x in (-W / 2 + 2.2, W / 2 - 2.2):
        s.limb((x, -1.0, 1.5), (x, -1.0, D * 0.8), 0.48, 0.48, GOLD)
    for z in (1.5, D * 0.8):
        s.limb((-W / 2 + 2.2, -1.0, z), (W / 2 - 2.2, -1.0, z), 0.48, 0.48, GOLD)
    for x in (-9.0, 9.0):
        for z in (4.4, 9.5):
            for k in range(4):
                a, b = k * math.pi / 2, (k + 1) * math.pi / 2
                s.limb((x + 2.6 * math.cos(a), -1.0, z + 2.2 * math.sin(a)),
                       (x + 2.6 * math.cos(b), -1.0, z + 2.2 * math.sin(b)), 0.42, 0.42, LACQUER)
            s.ell((x, -0.9, z), (0.35, 0.2, 0.35), GOLD)
    s.ell((0, -0.75, D * 0.45), (2.4, 0.2, 2.0), GOLD)
    for k in range(8):
        a = k * math.pi / 4
        s.limb((2.4 * math.cos(a), -0.75, D * 0.45 + 2.0 * math.sin(a)), (3.8 * math.cos(a), -0.75, D * 0.45 + 3.2 * math.sin(a)), 0.32, 0.18, GOLD)
    s.restore(old)
    if col == 0:  # the void's chains: an X over the lid's front and down the sides to the plinth, and a black padlock
        top = y0 + H + LRISE
        fz = D / 2 + 1.3
        r = (D + 1.0) / 2

        def over(x, am, out=1.7):  # a point on the closed lid's arc (am 0 = back, pi = front), lifted off the planks
            return (x, y0 + H + LRISE * math.sin(am) + out * math.sin(am) + 0.6, -D / 2 + r - r * math.cos(am) - out * math.cos(am))
        for sgn, ph in ((1, 0), (-1, 2)):
            arc = [over(sgn * (-W / 2 + 1.5 + (W - 3.0) * (1 - am / math.pi)), am) for am in np.linspace(math.pi, 0.0, 9)]
            chain(s, [(sgn * (-W / 2 - 2.6), y0 + 0.4, D / 2 + 1.4), (sgn * (-W / 2 + 0.6), y0 + H - 1.0, D / 2 + 2.0)] + arc + [(sgn * (W / 2 + 2.2), y0 + 0.4, -D / 2 - 1.4)], ph)
        chain(s, [(-W / 2 + 0.6, y0 + H - 1.0, D / 2 + 2.0), (-2.4, y0 + H - 4.0, D / 2 + 2.4), (0, y0 + H - 6.0, D / 2 + 2.6)], 1)
        chain(s, [(W / 2 - 0.6, y0 + H - 1.0, D / 2 + 2.0), (2.4, y0 + H - 4.0, D / 2 + 2.4), (0, y0 + H - 6.0, D / 2 + 2.6)], 3)
        s.box((0, y0 + H - 8.0, D / 2 + 2.4), (2.4, 2.2, 1.0), CHAIN, kind="metal")
        s.limb((-1.6, y0 + H - 5.8, D / 2 + 2.4), (1.6, y0 + H - 5.8, D / 2 + 2.4), 0.55, 0.55, CHAIN)
        s.ell((0, y0 + H - 8.2, D / 2 + 3.45), (0.55, 0.85, 0.2), VIOLET, kind="emit")
        s.limb((-1.8, y0 + H - 9.5, D / 2 + 3.45), (-0.6, y0 + H - 7.3, D / 2 + 3.45), 0.22, 0.18, VIOLET, kind="emit")
    tufts(s, rng, (0, 1.0, W / 2 + 7.0, D / 2 + 5.4), 12)
    return s


def legendary_info(FW, GR):
    y0 = LY0
    z, y = lid_point(LD + 1.0, LRISE, math.pi * 0.74)
    gem = (0, y0 + LH + y + 1.9, -LD / 2 + z + 0.4)
    return {
        "mouth": screen((0, y0 + LH + 1.0, 0), FW, GR),
        "lock": screen((0, y0 + LH - 5.4, LD / 2 + 1.35), FW, GR),
        "lid_top": screen((0, y0 + LH + LRISE, 0), FW, GR),
        "gem": screen(gem, FW, GR),
        "chain_cross": screen((0, y0 + LH - 6.0, LD / 2 + 2.2), FW, GR),
        "padlock": screen((0, y0 + LH - 8.0, LD / 2 + 3.4), FW, GR),
        "candles": [screen((-LW / 2 - 4.2, 2.4 + 6.4 + 2.6, LD / 2 + 2.6), FW, GR), screen((LW / 2 + 4.2, 2.4 + 4.6 + 2.6, LD / 2 + 2.6), FW, GR)],
        "chain_ends": [screen((-LW / 2 - 2.6, y0, LD / 2 + 0.8), FW, GR), screen((LW / 2 + 2.6, y0, LD / 2 + 0.8), FW, GR)],
        "foot": [(LW + 10) * h.SCALE, 16],
    }


TIERS = {
    "common": (build_common, common_info, 56, 50, 41, (0, -1, 19, 6)),
    "rare": (build_rare, rare_info, 60, 56, 46, (0, -1, 21, 7)),
    "legendary": (build_legendary, legendary_info, 84, 76, 62, (0, -1, 31, 11)),
}


def write_tier(name):
    build, info, FW, FH, GR, shadow = TIERS[name]
    frames = [pixels(build(c), FW, FH, GR, shadow) for c in range(COLS)]
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    OUT.mkdir(parents=True, exist_ok=True)
    write_png(OUT / f"chest_{name}.png", FW * COLS, FH, sheet)
    write_png(OUT / f"chest_{name}_glow.png", FW * COLS, FH, glow(sheet))
    entry = info(FW, GR)
    entry.update({"frame": [FW, FH], "ground": GR, "cols": COLS, "lid": LID})
    # sanity: nothing may touch the frame's border (the opened lid, the candles)
    for f in frames:
        for y in range(FH):
            for x in (0, FW - 1):
                if f[y][x][3] > 100:
                    print(f"  WARNING {name}: pixel at the left/right border, row {y}")
                    break
        if any(c[3] > 100 for c in f[0]):
            print(f"  WARNING {name}: pixel at the top border")
    return sheet, FW * COLS, FH, entry


if __name__ == "__main__":
    data = {}
    previews = []
    for name in TIERS:
        sheet, w, hgt, entry = write_tier(name)
        data[name] = entry
        previews.append((sheet, w, hgt))
        print(name, "written", entry["frame"], "mouth", entry["mouth"])
    DATA.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
    if len(sys.argv) > 1:
        sc = 4
        bg = (58, 92, 66, 255)
        width = max(w for _, w, _ in previews) * sc
        big = []
        for sheet, w, hgt in previews:
            for row in sheet:
                line = []
                for c in row:
                    a = c[3] / 255.0
                    line += [tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)] * sc
                line += [bg] * (width - len(line))
                big += [line] * sc
            big += [[(30, 40, 34, 255)] * width] * 4
        write_png(pathlib.Path(sys.argv[1]), width, len(big), big)
        print("preview", sys.argv[1])
