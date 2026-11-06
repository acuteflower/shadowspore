"""Shared helpers of the hut art (tools/art_hut.py): the world's wood palettes, the 3D renderer of the heroine/trees/signpost/knight (art_hero3d) used for
furniture and walls too, so everything wooden of the hut is made like the trunks, the signpost and the felled tree: rounded, lit from the top left, 4 bands
of shade, ink between forms, moss, violet veins and glowing fungi. Plus a few 2D passes (grain, stains, shadows)."""
import math
from pathlib import Path
import numpy as np

import art_hero3d as h
from gen_art import CLEAR, ROOT, hexc, write_png

BASE = len(h.RAMPS)
(BARK, BARK_D, PLANK, PLANK_W, MOSS, MOSS_L, STONE, IRON, STRAW, LINEN, FIRE, SOIL, CLAY, WAX, GAP, SKY, STONE_L, ROOF, SHUT, BANNER) = range(BASE, BASE + 20)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1a1322", "34283c", "55435a", "85697a"],  # bark, like the trees' trunks
    ["0e0914", "1d1428", "33253d", "4d3a54"],  # rotten, black-violet wood
    ["2b2128", "4d3d44", "7c6769", "ad9791"],  # weathered boards (the signpost's)
    ["2a1c22", "4c3433", "7a5a52", "ad8a7e"],  # warmer, older boards
    ["14281f", "1c3d36", "2b5646", "3a7550"],  # moss, dark
    ["2b5646", "3a7550", "74b268", "a6d88f"],  # moss, lit
    ["14121f", "2a2740", "46456a", "6f6f96"],  # old stones
    ["0f0e1a", "211f36", "3c3a5c", "7d7ca8"],  # iron
    ["3a2c1a", "6a5430", "a08844", "d4bc78"],  # straw
    ["2a2538", "4f4966", "7d7699", "aaa4c0"],  # linen, dingy
    ["8a2410", "e0601a", "ffa63a", "ffeaa0"],  # fire
    ["120d16", "2a1c22", "4a342e", "6e5242"],  # soil
    ["2a1a26", "55353f", "8a5a52", "b88a7a"],  # clay
    ["5a4a3a", "a89477", "d9c9a0", "f6ecc8"],  # wax
    ["07040b", "0b0710", "110b18", "180f22"],  # the dark gap between boards
    ["3a4a86", "5f7ab8", "9ab6e0", "dceeff"],  # daylight through an opening
    ["2a2740", "46456a", "6f6f96", "a3a2c4"],  # stones, lit
    ["1b1424", "3a2a3e", "5f4558", "8a6a78"],  # roof: marks the pixels roof_pass() turns into shingles
    ["141a30", "28365a", "44588a", "7a92bc"],  # painted shutters, dusty blue-violet
    ["102226", "1b4750", "2f7a80", "62bcb4"],  # the town's pennants, deep teal like its lamps
]]
WOOL = h.BLANKET
_FRESH = False
FRESH_RAMPS = {  # the renewed hut (tools/art_hut_fresh.py): the same plum-violet fir, cleaner and lighter, a little warmer, nothing rotten or grey
    BARK: ["20172a", "3f3043", "69505e", "977a80"],
    BARK_D: ["1c1426", "392b3e", "5e4858", "8c6f7a"],
    PLANK: ["2b2030", "4e3c52", "7a6270", "a88c92"],
    PLANK_W: ["33242e", "5e4448", "8c6a62", "bd9888"],
    STONE: ["1c1a2c", "38365a", "5a5884", "8c8bb8"],
    IRON: ["161426", "2c2a46", "4a4872", "8a89b4"],
    STRAW: ["4a3a22", "7e683a", "b49a52", "e2cc88"],
    LINEN: ["3a3452", "64608a", "a8a4c8", "e4e2f4"],
    CLAY: ["33202c", "63404a", "9a6a62", "c99a88"],
    STONE_L: ["36345a", "58577f", "8584ac", "b4b3d4"],
}


def fresh():
    """True while the renewed hut is drawn: the art functions leave out moss, ivy, roots, holes, cobwebs and breakage."""
    return _FRESH


def set_fresh():
    """Switches to the renewed look for the rest of this process (call before drawing anything)."""
    global _FRESH
    _FRESH = True
    for mat, row in FRESH_RAMPS.items():
        h.RAMPS[mat] = [hexc(c) for c in row]
GLOW_MATS = (h.TEAL, h.VIOLET, FIRE, SKY)
V = lambda *a: np.array(a, float)
U = 1.0 / h.SCALE  # px -> model units


def rng_for(seed):
    return np.random.default_rng(seed)


# ------------------------------------------------------------------ rendering
def render(model, fw, fh, ground, pitch=26.0, light=(-0.5, 0.72, 0.5)):
    """Rows of RGBA pixels. `pitch` 90 looks straight down (floors, rugs, wall tops)."""
    saved = (h.FW, h.FH, h.GROUND_ROW, h.PITCH, h.COSP, h.SINP, h.UHAT, h.WHAT, h.LIGHT)
    h.FW, h.FH, h.GROUND_ROW = fw, fh, ground
    h.PITCH = math.radians(pitch)
    h.COSP, h.SINP = math.cos(h.PITCH), math.sin(h.PITCH)
    h.UHAT = np.array([0.0, h.COSP, -h.SINP])
    h.WHAT = np.array([0.0, h.SINP, h.COSP])
    l = np.array(light, float)
    h.LIGHT = l / np.linalg.norm(l)
    try:
        depth, code = h.render(model.transform(0.0, 0.0))
        rows = h.to_pixels(depth, code)
    finally:
        h.FW, h.FH, h.GROUND_ROW, h.PITCH, h.COSP, h.SINP, h.UHAT, h.WHAT, h.LIGHT = saved
    return [[CLEAR if tuple(c) == (0, 0, 0, 70) else c for c in row] for row in rows]  # the renderer's own ground shadow: props get theirs


def to_array(rows):
    return np.array(rows, np.uint8)


def to_rows(arr):
    return [[tuple(int(v) for v in arr[y, x]) for x in range(arr.shape[1])] for y in range(arr.shape[0])]


def save(path, arr):
    write_png(Path(path), arr.shape[1], arr.shape[0], to_rows(arr))


def glow_of(arr, mats=GLOW_MATS, min_band=0):
    """Only the emissive pixels (the colours of the glowing ramps), for the unlit second sheet."""
    cols = {tuple(c[:3]) for mat in mats for b, c in enumerate(h.RAMPS[mat]) if b >= min_band}
    out = np.zeros_like(arr)
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in cols:
                out[y, x] = arr[y, x]
    return out


def hsh(x, y, seed=0):
    n = (int(x) * 374761393 + int(y) * 668265263 + int(seed) * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, seed=0):
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hsh(xi, yi, seed), hsh(xi + 1, yi, seed)
    c, d = hsh(xi, yi + 1, seed), hsh(xi + 1, yi + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(x, y, seed=0):
    return 0.55 * vnoise(x, y, seed) + 0.3 * vnoise(x * 2.1, y * 2.1, seed + 7) + 0.15 * vnoise(x * 4.3, y * 4.3, seed + 13)


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def bayer(x, y):
    return BAYER[y % 4][x % 4] / 16.0


WOODS = (BARK, BARK_D, PLANK, PLANK_W)


def _ramp_lookup(mats):
    lut = {}
    for mat in mats:
        for b, c in enumerate(h.RAMPS[mat]):
            lut[tuple(c[:3])] = (mat, b)
    return lut


def grain(arr, seed, along=(1.0, 0.0), amount=0.5, mats=WOODS, scale=0.35):
    """The painterly speckle and grain of the trunks: a stretched noise nudges the shade of wood pixels one step up or down (dithered)."""
    lut = _ramp_lookup(mats)
    out = arr.copy()
    ax, ay = along
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            if arr[y, x, 3] == 0:
                continue
            key = tuple(int(v) for v in arr[y, x, :3])
            if key not in lut:
                continue
            mat, b = lut[key]
            u = (x * ax + y * ay)
            v = (-x * ay + y * ax)
            n = fbm(u * scale * 0.25, v * scale * 1.6, seed)
            r = hsh(x, y, seed + 3)
            shift = 0
            if n > 0.62 - amount * 0.12 and r < 0.8:
                shift = -1
            elif n < 0.34 + amount * 0.1 and r < 0.55:
                shift = 1
            elif r > 0.97:
                shift = -1 if r > 0.985 else 1
            if shift:
                nb = max(0, min(3, b + shift))
                out[y, x, :3] = h.RAMPS[mat][nb][:3]
    return out


def tint_region(arr, fn, seed=0):
    """Darken/stain pixels where fn(x, y) -> 0..1 (dithered)."""
    out = arr.copy()
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            if arr[y, x, 3] == 0:
                continue
            k = fn(x, y)
            if k > bayer(x, y) * 0.9 + 0.05:
                c = arr[y, x]
                out[y, x, :3] = (c[0] * 0.68, c[1] * 0.66, c[2] * 0.76)
    return out


def soft_shadow(arr, cx, cy, rx, ry, alpha=70):
    for y in range(max(0, int(cy - ry) - 1), min(arr.shape[0], int(cy + ry) + 2)):
        for x in range(max(0, int(cx - rx) - 1), min(arr.shape[1], int(cx + rx) + 2)):
            if arr[y, x, 3] == 0 and ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                arr[y, x] = (0, 0, 0, alpha)
    return arr


# ------------------------------------------------------------------ geometry on top of the renderer
def log(m, a, b, r, mat, step=1.3, taper=1.0, rr=None):
    """A round log/pole from a to b (a chain of ellipsoids along its axis); `taper` scales the radius at b."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    length = float(np.linalg.norm(axis))
    n = max(2, int(length / step))
    hint = V(0, 0, 1) if abs(axis[2]) < 0.9 * length else V(0, 1, 0)
    R = h.frame_from(axis, hint)
    for i in range(n + 1):
        t = i / n
        rad = r * (1.0 + (taper - 1.0) * t)
        if rr is not None:
            rad *= 1.0 + rr(t)
        m.ell(a + axis * t, (rad, step * 1.1, rad), mat, R=R)


def slab(m, a, b, w, t, mat, normal=(0, 1, 0), step=1.4):
    """A board from a to b: width w (half), thickness t (half), its face towards `normal`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    length = float(np.linalg.norm(axis))
    n = max(2, int(length / step))
    R = h.frame_from(axis, V(*normal))  # columns: x (width), y (along), z (towards the normal)
    for i in range(n + 1):
        m.ell(a + axis * (i / n), (w, step * 1.2, t), mat, R=R)


def blob(m, c, r, mat, R=None, kind=""):
    m.ell(c, r, mat, R=R, kind=kind)


def tuft(m, base, rng, blades=6, height=4.5, mat=MOSS_L, spread=1.6):
    for _ in range(blades):
        ang = rng.uniform(0, math.tau)
        d = rng.uniform(0.2, spread)
        tip = base + V(math.cos(ang) * d * 1.4, rng.uniform(0.6, 1.0) * height, math.sin(ang) * d * 1.4)
        m.limb(base + V(math.cos(ang) * 0.3, 0, math.sin(ang) * 0.3), tip, 0.42, 0.14, mat)


def ivy(m, start, length, rng, mat=MOSS, leaf=MOSS_L, glow_every=0, sway=1.0, down=True):
    """A strand of ivy climbing/hanging from `start` with leaves; the odd teal bud."""
    p = np.asarray(start, float)
    pts = [p.copy()]
    for i in range(int(length / 1.5)):
        p = p + V(math.sin(i * 0.5 + rng.uniform(0, 1)) * 0.8 * sway, (-1.5 if down else 1.5), rng.uniform(-0.15, 0.25))
        pts.append(p.copy())
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        m.limb(a, b, 0.4, 0.3, mat)
        if i % 2 == 0:
            side = 1 if (i // 2) % 2 == 0 else -1
            m.ell(b + V(side * 1.0, 0.2, 0.9), (1.3, 0.45, 0.9), leaf, R=h.rot_x(0.6 + 0.2 * side))
        if glow_every and i % glow_every == glow_every - 1:
            m.ell(b + V(0.5, 0.3, 1.2), (0.6, 0.6, 0.6), h.TEAL, kind="emit")


def load_png_arr(path):
    """A PNG as an RGBA array (tools/world_data.py reads them)."""
    import world_data
    arr = world_data.load_png(str(path))
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.full(arr.shape[:2] + (1,), 255, np.uint8)], axis=2)
    return arr


# ------------------------------------------------------------------ roofs: shingles with overlap, shadow and colour (2D pass over the pixels of the ROOF material)
ROOF_TONES = (  # shingle colour families: plum, warm clay-brown, cool slate-violet (same family as the walls, a little darker and richer)
    [hexc(c) for c in ("171020", "37283b", "5a4256", "86687a")],
    [hexc(c) for c in ("1d1119", "432c30", "6a4a46", "94705e")],
    [hexc(c) for c in ("161225", "2f2a46", "4c4468", "746a92")],
)


def roof_pass(arr, seed, rowh=4, wid=7, moss=0.0, shadow=3):
    """Re-draws every ROOF pixel as rows of overlapping shingles: each shingle has its own tone and family, a lit lip on its lower edge and a shadow on the row it
    covers, dark joints staggered from row to row, wavy rows, patches of sun-bleached / damp wood, worn and replaced shingles, an eave with an underside, optional
    moss, and a cast shadow on whatever lies under the eave. Pixels on the roof's rim keep the renderer's ink line."""
    lut = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[ROOF])}
    H, W = arr.shape[:2]
    is_roof = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in lut:
                is_roof[y, x] = True
    if not is_roof.any():
        return arr
    ys, xs = np.nonzero(is_roof)
    eave = int(ys.max())
    top = int(ys.min())
    out = arr.copy()

    def roof_at(x, y):
        return 0 <= x < W and 0 <= y < H and is_roof[y, x]

    for y, x in zip(ys, xs):
        rim = not (roof_at(x - 1, y) and roof_at(x + 1, y) and roof_at(x, y - 1))
        if rim:
            continue  # the ink line of the roof's silhouette stays
        wob = int(round(1.1 * math.sin(x * 0.13 + seed) + 0.8 * math.sin(x * 0.047 + seed * 2.0)))
        yy = eave - y + wob
        r, ly = divmod(max(yy, 0), rowh)  # ly 0 = the lower lip of the row
        stagger = int(hsh(r, 0, seed) * wid)
        c, lx = divmod(x + stagger, wid + int(hsh(r, 1, seed) * 2.0))
        tone = hsh(r * 31 + c, c, seed + 5)
        fam = 0 if tone < 0.58 else (1 if tone < 0.86 else 2)
        base = 1 + (tone * 7.0 % 1.0 > 0.5)  # band 1..2 (3 is for the lips)
        patch = fbm(x * 0.045, y * 0.07, seed + 9)  # large patches: bleached by the sun / damp and dark
        if patch > 0.64:
            base += 1 if hsh(x, y, seed + 2) < 0.5 else 0
        elif patch < 0.34:
            base -= 1 if hsh(x, y, seed + 4) < 0.5 else 0
        if hsh(r, c, seed + 8) > 0.95:
            fam, base = 1, 2  # a replaced shingle: newer and warmer
        if lx == 0:
            b = base - 1  # the joint between two shingles
            if hsh(r, c, seed + 6) > 0.8:
                b = 0
        elif ly == rowh - 1:
            b = base - 2  # the shadow the row above throws
        elif ly == rowh - 2:
            b = base - 1
        elif ly == 0:
            b = base + 1  # the lit lip of the shingle's lower edge
            if lx == wid - 1 or lx == 1 and hsh(r, c, seed + 3) > 0.5:
                b = base  # a chipped corner
        else:
            b = base + (1 if ly == 1 and hsh(x, y, seed + 1) < 0.4 else 0)
        if r == 0 and ly == 0:
            b = 0  # the eave's underside
        if r == 0 and ly == 1:
            b = 3  # the eave's lit edge
        n = hsh(x, y, seed + 12)  # grain and speckle
        if n < 0.05:
            b -= 1
        elif n > 0.96:
            b += 1
        if ly >= 1 and ly < rowh - 1 and abs(fbm(x * 0.5, y * 0.12, seed + 21) - 0.5) < 0.03:
            b -= 1  # a hair-line crack along the grain
        b = max(0, min(3, b))
        col = ROOF_TONES[fam][b]
        if moss > 0.0 and ly in (rowh - 1, 0, 1) and (fbm(x * 0.09, y * 0.2, seed + 30) + 0.5 * (r == 0)) > 1.0 - moss * 0.9 and hsh(x, y, seed + 31) < 0.8:
            col = h.RAMPS[MOSS_L if hsh(x, y, seed + 32) < 0.3 else MOSS][1 + (ly == 1)]
        out[y, x, :3] = col[:3]
    if shadow:  # the eave throws a shadow on what lies below it (wall, goods): `shadow` px, dithered out
        for y, x in zip(ys, xs):
            if roof_at(x, y + 1):
                continue
            for k in range(1, int(shadow) + 1):
                yy = y + k
                if yy < H and out[yy, x, 3] and not is_roof[yy, x] and bayer(x, yy) < (shadow + 1 - k) / (shadow + 1.0) * 0.95:
                    c = out[yy, x]
                    out[yy, x, :3] = (c[0] * 0.55, c[1] * 0.5, c[2] * 0.66)
    return out


# ------------------------------------------------------------------ walls: depth by ambient occlusion in 2D (band shifts inside the wood ramps, so the palette stays)
def wall_depth(arr, box, seed, eave=7, foot=4, side=4, dark=None):
    """Shades the wood pixels inside box (x0, x1, y0, y1) as if light had trouble reaching them: under the eave, at the foot, in the corners and beside dark openings
    (colours of the ramp `dark`, e.g. the door's GAP), plus a few knots. Every change is a band step within the pixel's own ramp, dithered."""
    lut = _ramp_lookup(WOODS + (STONE, STONE_L, IRON, SHUT))
    x0, x1, y0, y1 = box
    dk = {tuple(c[:3]) for c in h.RAMPS[dark]} if dark is not None else set()
    out = arr.copy()
    H, W = arr.shape[:2]
    dark_mask = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in dk:
                dark_mask[y, x] = True
    for y in range(max(0, y0), min(H, y1)):
        for x in range(max(0, x0), min(W, x1)):
            if arr[y, x, 3] == 0:
                continue
            key = tuple(int(v) for v in arr[y, x, :3])
            if key not in lut:
                continue
            mat, b = lut[key]
            k = 0.0
            if y - y0 < eave:
                k += (1.0 - (y - y0) / eave) * 1.7
            if y1 - y <= foot:
                k += (1.0 - (y1 - y - 1) / foot) * 1.1
            e = min(x - x0, x1 - 1 - x)
            if e < side:
                k += (1.0 - e / side) * 1.2
            if dk and dark_mask[max(0, y - 2):y + 3, max(0, x - 2):x + 3].any():
                k += 1.0
            if k <= 0:
                continue
            drop = int(k) + (1 if k - int(k) > bayer(x, y) else 0)
            if drop:
                out[y, x, :3] = h.RAMPS[mat][max(0, b - drop)][:3]
    rng = rng_for(seed + 77)
    for _ in range(7):  # knots
        kx, ky = int(rng.integers(x0 + 6, x1 - 6)), int(rng.integers(y0 + eave + 2, y1 - foot - 2))
        for dx, dy, d in ((0, 0, 3), (1, 0, 3), (-1, 0, 2), (0, 1, 1), (1, 1, 1), (0, -1, 1)):
            xx, yy = kx + dx, ky + dy
            if arr[yy, xx, 3] and tuple(int(v) for v in arr[yy, xx, :3]) in lut:
                mat, b = lut[tuple(int(v) for v in arr[yy, xx, :3])]
                out[yy, xx, :3] = h.RAMPS[mat][max(0, b - d)][:3]
    return out


# ------------------------------------------------------------------ the lit window: glass as a warm gradient with the room behind it
CURTAIN = [hexc(c) for c in ("3a2230", "6a4040", "a2685a", "d09a84")]


def window_pass(arr, seed, dim=0.0):
    """Re-paints the FIRE pixels (the glass) of a building picture: bright at the bottom middle (the fire inside), darker toward the top and corners, a dithered
    gradient, the dark shapes of a shelf, hanging herbs and a pot against it, a warm linen curtain drawn back at both sides. Returns (array, glass bbox)."""
    lut = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[FIRE])}
    H, W = arr.shape[:2]
    pts = [(x, y) for y in range(H) for x in range(W) if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in lut]
    if not pts:
        return arr, None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    gx0, gx1, gy0, gy1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (gx0 + gx1) / 2.0, (gy0 + gy1) / 2.0
    hw, hh = max(1.0, (gx1 - gx0) / 2.0), max(1.0, (gy1 - gy0) / 2.0)
    out = arr.copy()
    for x, y in pts:
        u, v = (x - cx) / hw, (y - cy) / hh
        i = 0.5 + 0.34 * (v + 1.0) / 2.0 + 0.3 * (1.0 - u * u) + (bayer(x, y) - 0.5) * 0.16 - dim
        b = 3 if i > 1.02 else 2 if i > 0.80 else 1 if i > 0.62 else 0
        if abs(u + 0.15) < 0.42 and abs(v + 0.12) < 0.1:  # a shelf with something on it
            b = max(0, b - 1)
        if abs(u + 0.6) < 0.2 and -1.0 <= v < -0.45 and (abs(u + 0.6) < 0.12 or v > -0.7):  # a hanging bundle of herbs
            b = max(0, b - 2)
        if (u - 0.5) ** 2 + ((v - 0.35) * 0.9) ** 2 < 0.04 + 0.01 * (v < 0.2) and (v < 0.5):  # the round belly of a pot
            b = max(0, b - 2)
        if v < -0.8:  # the lintel's shadow on the top row
            b = max(0, b - 1)
        col = h.RAMPS[FIRE][b]
        if abs(u) > 0.74 and v < 0.35 + 0.5 * (abs(u) - 0.74):  # the curtain, pulled aside, hanging in a soft fold
            fold = 1 + int((u * 9.0 + hsh(y, 0, seed)) % 2 > 1.0) + (1 if v > -0.2 else 0)
            col = CURTAIN[min(3, fold)]
        out[y, x, :3] = col[:3]
    return out, (gx0, gx1, gy0, gy1)


def window_spill(frame_w, frame_h, ground, box, seed=5):
    """The light that leaves the window, as one additive picture of the building's size (drawn unlit and breathing by Hut): a bloom on the wall round the glass
    and a patch of lamp light on the ground in front of the wall, widening with distance, with the window's cross of bars cast into it. Stepped and dithered."""
    gx0, gx1, gy0, gy1 = box
    img = np.zeros((frame_h, frame_w, 4), np.uint8)
    cx, cy = (gx0 + gx1) / 2.0, (gy0 + gy1) / 2.0
    warm = (255, 150, 70)

    def put_px(x, y, a):
        if 0 <= x < frame_w and 0 <= y < frame_h and a > 0:
            img[y, x] = (*warm, int(a))

    reach = 7
    for y in range(gy0 - reach, gy1 + reach + 1):
        for x in range(gx0 - reach, gx1 + reach + 1):
            dx = max(gx0 - x, 0, x - gx1)
            dy = max(gy0 - y, 0, y - gy1)
            d = math.hypot(dx, dy)
            if d <= 0 or d > reach:
                continue
            f = (1.0 - d / reach) ** 1.8 * 0.55
            if f > bayer(x, y) * 0.45 + 0.04:
                put_px(x, y, 255 * min(1.0, f * 1.4))
    depth, spread = 19, 12.0
    y_top = ground - 1
    for t_i in range(depth):
        t = t_i / (depth - 1.0)
        y = y_top + t_i
        half = (gx1 - gx0) / 2.0 + 2.0 + spread * t
        mid = cx + 6.0 * t  # leans toward the right: the light comes from the left of the fire
        for x in range(int(mid - half - 2), int(mid + half + 3)):
            u = (x - mid) / half
            if abs(u) > 1.0 + (fbm(x * 0.3, y * 0.4, seed) - 0.5) * 0.35:
                continue
            f = (1.0 - t) ** 1.4 * (1.0 - 0.6 * u * u) * 0.95
            if abs(u) < 0.07 + 0.05 * t:  # the vertical bar's shadow
                f *= 0.25
            if 0.36 < t < 0.5:  # the cross bar's
                f *= 0.3
            if f > 0.06:
                step = (0.12, 0.26, 0.42, 0.6, 0.78)  # six brightness steps, dithered into each other
                q = sum(f > s + (bayer(x, y) - 0.5) * 0.12 for s in step)
                put_px(x, y, (0, 34, 62, 90, 124, 158)[q] if q else 0)
    return img


def pool_spill(fw, fh, box, pools, reach=8, color=(255, 150, 70), seed=5, bloom=0.55):
    """Additive light picture for a lamp, a forge or the like (like window_spill): a dithered bloom of `reach` px round `box` (x0, x1, y0, y1) and one or more elliptical
    pools on the ground, each (cx, cy, rx, ry, strength): brightest in the middle, six dithered steps, ragged rim."""
    img = np.zeros((fh, fw, 4), np.uint8)

    def put_px(x, y, a):
        if 0 <= x < fw and 0 <= y < fh and a > 0:
            img[y, x] = (*color, int(min(255, a)))

    x0, x1, y0, y1 = box
    for y in range(y0 - reach, y1 + reach + 1):
        for x in range(x0 - reach, x1 + reach + 1):
            d = math.hypot(max(x0 - x, 0, x - x1), max(y0 - y, 0, y - y1))
            if d <= 0 or d > reach:
                continue
            f = (1.0 - d / reach) ** 1.8 * bloom
            if f > bayer(x, y) * 0.45 + 0.04:
                put_px(x, y, 255 * min(1.0, f * 1.4))
    steps = (0.12, 0.26, 0.42, 0.6, 0.78)
    levels = (0, 34, 62, 90, 124, 158)
    for cx, cy, rx, ry, strength in pools:
        for y in range(int(cy - ry) - 2, int(cy + ry) + 3):
            for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
                d = math.hypot((x - cx) / rx, (y - cy) / ry) + (fbm(x * 0.3, y * 0.4, seed) - 0.5) * 0.3
                if d >= 1.0:
                    continue
                f = (1.0 - d) ** 1.1 * strength
                q = sum(f > s_ + (bayer(x, y) - 0.5) * 0.12 for s_ in steps)
                if q and img[y, x, 3] == 0 if 0 <= x < fw and 0 <= y < fh else False:
                    put_px(x, y, levels[q])
                elif q and 0 <= x < fw and 0 <= y < fh:
                    put_px(x, y, max(int(img[y, x, 3]), levels[q]))
    return img
