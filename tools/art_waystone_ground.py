"""The stone ground and the ground crystals of a waystone (flat 2D pixel art, drawn straight into the picture like the world's other ground decals).
    py -3 tools/art_waystone_ground.py [preview.png]
The bed is laid like hand work: a ring of neatly set slabs round the plinth, further out smaller and smaller, uneven cobbles and gravel, every slab with its own tone,
a lit top-left edge and a dark bottom-right joint, the colours taken from the statue's marble (a step darker). Twelve crystal SOCKETS are part of the picture: a fissure
with cracks running out of it, lifted fragments, loose splinters; the game stands 5-7 crystals on them (a different choice per statue).
Writes assets/props/waystone/:
  ground_wild.png   dormant: hairline cracks, moss in the joints and on a few corners, sprigs of grass, tiny pale flowers, ragged dithered rim, loose pebbles
  ground_clean.png  awakened: polished, mended, no growth (the joints and the sockets stay)
  ground_glow.png   emissive pixels of the awakened bed: leylines from the plinth ring to the sockets, a ring of runes, light in the fissures, lit splinters, a dithered halo
  ground_dim.png    the faint glints of the dormant splinters
  ground_wave.png   R = when the awakening reaches a pixel (0.12 at the plinth .. 1 at the rim), A = body mask
  crystals_wild.png / crystals_lit.png   NV groups of ground crystals (frames CW x CH, feet at (CW / 2, CGROUND)), dark and lit
and data/waystone_ground.json: sizes and the socket positions (px from the statue's feet)."""
import json
import math
import sys

import numpy as np

from gen_art import ROOT, hexc

W, H = 200, 120
CX, CY = 100, 60  # the statue's feet
RX, RY = 86.0, 50.0
CW, CH, CGROUND, NV = 28, 26, 23, 10
GROUND = [hexc(c) for c in ["2b2945", "46446a", "6e6c96", "9b99bd"]]  # the statue's marble, a step darker
GROUND_CLEAN = [hexc(c) for c in ["34325a", "504e7c", "7b79a4", "aaa8cb"]]
TINTS = [(-4, -1, 5), (0, 0, 0), (6, 1, -3)]  # cool, neutral, warm slabs: nothing is the same stone twice
JOINT = hexc("17142a")
CRACK = hexc("211e3a")
MOSS = [hexc(c) for c in ["1c3d36", "2b5646", "3a7550", "74b268"]]
CRYST_D = [hexc(c) for c in ["05030a", "120a26", "261852", "4e3d98"]]
CRYST_L = [hexc(c) for c in ["3a1d86", "7a4bdc", "b99bff", "f0e6ff"]]
TEAL = [hexc(c) for c in ["2a8c94", "3cc0c6", "78f4e6", "d0fff8"]]
INK = hexc("0b0614")
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def write_png(path, arr):
    from PIL import Image
    Image.fromarray(np.asarray(arr, np.uint8), "RGBA").save(path)


def smooth_noise(rng, scale, passes=3):
    a = rng.random((H, W))
    for _ in range(passes):
        for s in range(1, scale + 1):
            a = (a + np.roll(a, s, 0) + np.roll(a, -s, 0) + np.roll(a, s, 1) + np.roll(a, -s, 1)) / 5.0
    return (a - a.min()) / (a.max() - a.min())


def seeds_variable(rng):
    """Cobble seeds: big near the paved ring, smaller and smaller towards the rim (dart throwing)."""
    pts = []
    for _ in range(14000):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        e = math.hypot((x - CX) / RX, (y - CY) / RY)
        if e > 1.14 or e < 0.38:
            continue
        r = 12.5 - 8.0 * min(e, 1.0) ** 1.1 + rng.uniform(-1.6, 1.6)
        if all(math.hypot(x - px, (y - py) * 1.15) >= (r + pr) / 2.0 for px, py, pr in pts):
            pts.append((x, y, r))
    return np.array(pts)


def layout():
    """Cell ids of the bed: the paved ring (rows of slabs set round the plinth), cobbles outside it."""
    rng = np.random.default_rng(3)
    ys, xs = np.mgrid[0:H, 0:W]
    ex, ey = (xs - CX) / RX, (ys - CY) / RY
    ell = np.hypot(ex, ey)
    n1 = smooth_noise(rng, 6)
    n2 = smooth_noise(rng, 2)
    d = ell + (n1 - 0.5) * 0.30 + (n2 - 0.5) * 0.08  # ragged outline
    seeds = seeds_variable(rng)
    dist = np.hypot(xs[..., None] - seeds[:, 0], (ys[..., None] - seeds[:, 1]) * 1.15) - seeds[:, 2] * 0.18
    nearest = np.argmin(dist, axis=-1)
    ang = np.arctan2(ey, ex)
    ring = np.floor((ell - 0.17) / 0.085).astype(int)
    n_ring = 12 + 5 * np.clip(ring, 0, 6)
    sector = np.floor((ang + math.pi) / math.tau * n_ring + 0.5 * (ring % 2)).astype(int)
    pave = (ell >= 0.17) & (ell < 0.45)
    cid = np.where(pave, 10000 + np.clip(ring, 0, 6) * 100 + sector, np.where(ell < 0.17, 9999, nearest))
    return ys, xs, ell, d, cid, n1, n2, seeds


def sockets(rng):
    """Twelve fissures where crystals can stand: irregular, never in front of the plinth."""
    out = []
    tries = 0
    while len(out) < 12 and tries < 400:
        tries += 1
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.52, 0.86)
        x, y = math.cos(a) * RX * r, math.sin(a) * RY * r
        if abs(x) < 30 and y > -4:
            continue
        if any(math.hypot(x - ox, (y - oy) * 1.6) < 17 for ox, oy in out):
            continue
        out.append((round(x), round(y)))
    return out


def paint(wild, parts, socks):
    ys, xs, ell, d, cid, n1, n2, seeds = parts
    rng = np.random.default_rng(41)
    ramp = GROUND if wild else GROUND_CLEAN
    rnd = np.random.default_rng(5)
    r1, r2, r3, r4 = (rnd.random(20000) for _ in range(4))
    c = np.clip(cid, 0, 19999)
    tone = (1 + (r1[c] > 0.5).astype(int) + (r2[c] > 0.88).astype(int) - (r1[c] < 0.18).astype(int))
    tone = np.clip(tone + (n2 > 0.72).astype(int) - (n2 < 0.27).astype(int), 0, 3)
    speck = np.random.default_rng(9).random((H, W))
    tone = np.clip(tone + (speck > 0.955).astype(int) - (speck < 0.045).astype(int), 0, 3)
    edge_tl = (cid != np.roll(cid, 1, 1)) | (cid != np.roll(cid, 1, 0))  # the slab's left / top edge catches the light
    joint = (cid != np.roll(cid, -1, 1)) | (cid != np.roll(cid, -1, 0))  # its right / bottom edge is the dark joint
    tone = np.clip(tone + (edge_tl & ~joint).astype(int), 0, 3)
    img = np.zeros((H, W, 4), np.int16)
    for t in range(4):
        img[tone == t] = ramp[t] + ()
    tint = np.array(TINTS)[(r3[c] * 3).astype(int)]
    img[..., :3] += tint
    img[joint] = JOINT + ()
    chips = joint & (np.random.default_rng(13).random((H, W)) < 0.18)  # chips along the joints
    img[chips] = [ramp[1][0], ramp[1][1], ramp[1][2], 255]
    for _ in range(26 if wild else 0):  # hairline cracks (a few): dark pixel with a lit lip
        x, y = rng.uniform(20, W - 20), rng.uniform(15, H - 15)
        if math.hypot((x - CX) / RX, (y - CY) / RY) > 0.9:
            continue
        a = rng.uniform(0, math.tau)
        for _s in range(int(rng.integers(5, 11))):
            xi, yi = int(x), int(y)
            if 0 <= xi < W - 1 and 0 <= yi < H and not joint[yi, xi]:
                img[yi, xi] = CRACK + ()
                if cid[yi, xi + 1] == cid[yi, xi] and not joint[yi, xi + 1]:
                    img[yi, xi + 1, :3] = np.minimum(img[yi, xi + 1, :3] + 16, 255)
            a += rng.uniform(-0.7, 0.7)
            x += math.cos(a)
            y += math.sin(a) * 0.7
    # sockets: shadow of the fissure, cracks running out, lifted fragments, splinters
    splinters = []
    cracks_px = []
    for sx, sy in socks:
        px, py = CX + sx, CY + sy
        for yy in range(-3, 4):
            for xx in range(-7, 8):
                rr = (xx / 7.0) ** 2 + (yy / 2.6) ** 2
                if rr <= 1.0 and 0 <= px + xx < W and 0 <= py + yy < H and (rr < 0.6 or BAYER[(py + yy) % 4, (px + xx) % 4] < 0.55):
                    dark = np.array((5, 3, 10) if rr < 0.35 else (18, 12, 32))
                    img[py + yy, px + xx, :3] = (img[py + yy, px + xx, :3] * (0.45 if rr < 0.35 else 0.3) + dark * (0.55 if rr < 0.35 else 0.7)).astype(np.int16)
        for _k in range(int(rng.integers(4, 7))):
            a = rng.uniform(0, math.tau)
            x, y = px + math.cos(a) * 6, py + math.sin(a) * 2.6
            for _s in range(int(rng.integers(5, 13))):
                xi, yi = int(x), int(y)
                if 0 <= xi < W - 1 and 0 <= yi < H:
                    img[yi, xi] = CRACK + ()
                    cracks_px.append((xi, yi))
                    if not joint[yi, xi + 1]:
                        img[yi, xi + 1, :3] = np.minimum(img[yi, xi + 1, :3] + 14, 255)
                a += rng.uniform(-0.5, 0.5)
                x += math.cos(a) * 1.05
                y += math.sin(a) * 0.72
        for _k in range(int(rng.integers(3, 6))):  # lifted fragments round the fissure
            a = rng.uniform(0, math.tau)
            fx, fy = int(px + math.cos(a) * rng.uniform(8, 13)), int(py + math.sin(a) * rng.uniform(3.5, 6))
            if 1 <= fx < W - 3 and 1 <= fy < H - 2:
                img[fy, fx:fx + 2] = ramp[3] + ()
                img[fy + 1, fx:fx + 2] = ramp[1] + ()
                img[fy + 1, fx + 2] = JOINT + ()
        for _k in range(int(rng.integers(2, 4))):  # splinters of crystal in the dust
            a = rng.uniform(0, math.tau)
            fx, fy = int(px + math.cos(a) * rng.uniform(5, 11)), int(py + math.sin(a) * rng.uniform(2.5, 5))
            if 1 <= fx < W - 3 and 1 <= fy < H - 2:
                shape = [(0, 0), (1, 0), (1, -1)] if rng.random() < 0.5 else [(0, 0), (1, 0), (2, 0), (1, -1)]
                for ox, oy in shape:
                    img[fy + oy, fx + ox] = (CRYST_D[2] if (ox + oy) % 2 == 0 else CRYST_D[1]) + ()
                splinters.append((fx, fy, shape))
    if wild:
        # moss: in the joints, a fringe on the slabs beside them, thicker at the rim
        m = smooth_noise(np.random.default_rng(21), 3)
        moss_zone = (m + np.clip(ell - 0.4, 0, 1) * 0.8) > 0.78
        mj = joint & (np.random.default_rng(22).random((H, W)) < 0.7) & moss_zone
        near_mj = (np.roll(mj, 1, 1) | np.roll(mj, 1, 0) | np.roll(mj, -1, 1)) & ~joint & (np.random.default_rng(23).random((H, W)) < 0.45)
        for mask, base in ((mj, 1), (near_mj, 2)):
            tt = np.clip(tone + base - 1, 0, 3)
            for t in range(4):
                img[mask & (tt == t)] = MOSS[t] + ()
        for _ in range(34):  # sprigs of grass out of the joints
            a = rng.uniform(0, math.tau)
            e = rng.uniform(0.3, 1.0)
            x, y = CX + math.cos(a) * RX * e, CY + math.sin(a) * RY * e
            for b in range(int(rng.integers(2, 4))):
                xi, yi = int(x) + b - 1, int(y)
                for hgt in range(int(rng.integers(2, 5))):
                    if 0 <= xi + (hgt > 2) < W and 0 <= yi - hgt < H:
                        img[yi - hgt, xi + (hgt > 2)] = MOSS[2 if hgt < 2 else 3] + ()
        for _ in range(9):  # tiny pale flowers in the moss
            a = rng.uniform(0, math.tau)
            e = rng.uniform(0.55, 0.95)
            xi, yi = int(CX + math.cos(a) * RX * e), int(CY + math.sin(a) * RY * e) - 3
            if 0 <= xi < W and 0 <= yi < H - 1:
                img[yi, xi] = (241, 230, 255, 255)
                img[yi + 1, xi] = MOSS[1] + ()
    else:  # polished: a few sparkles on the slabs
        for _ in range(40):
            a = rng.uniform(0, math.tau)
            e = rng.uniform(0.2, 0.95)
            xi, yi = int(CX + math.cos(a) * RX * e), int(CY + math.sin(a) * RY * e)
            if 0 <= xi < W and 0 <= yi < H and not joint[yi, xi]:
                img[yi, xi, :3] = np.minimum(img[yi, xi, :3] + 34, 255)
    # outline of the bed: dithered ragged rim, loose gravel outside
    bay = BAYER[ys % 4, xs % 4]
    alpha = (d < 0.8) | ((d >= 0.8) & (d < 1.0) & (bay < (1.0 - d) / 0.2))
    gravel = (d >= 1.0) & (d < 1.08) & (np.random.default_rng(33).random((H, W)) < 0.018)
    img[..., 3] = np.where(alpha | gravel, 255, 0)
    img[gravel & ~alpha] = ramp[2] + ()
    img = np.clip(img, 0, 255)
    below = np.roll(alpha, 1, 0) & ~alpha
    img[below] = (11, 6, 20, 150)
    return img.astype(np.uint8), d, alpha, joint, splinters, cracks_px


def glow_layer(rng, d, alpha, socks, splinters, cracks_px):
    """The awakened bed's light: leylines from the plinth ring to every socket (and a few free branches), a ring of runes, light in the fissures, lit splinters."""
    core = np.zeros((H, W), bool)

    def line(x0, y0, x1, y1, wobble=0.5):
        n = int(max(abs(x1 - x0), abs(y1 - y0) * 1.5)) + 1
        phase = rng.uniform(0, 6.28)
        for i in range(n + 1):
            t = i / n
            x = x0 + (x1 - x0) * t + math.sin(t * 9 + phase) * wobble * 2.0 * math.sin(t * math.pi)
            y = y0 + (y1 - y0) * t + math.cos(t * 7 + phase) * wobble * 1.2 * math.sin(t * math.pi)
            xi, yi = int(x), int(y)
            if 0 <= xi < W and 0 <= yi < H:
                core[yi, xi] = True
    for sx, sy in socks:
        a = math.atan2(sy / RY, sx / RX)
        line(CX + math.cos(a) * RX * 0.30, CY + math.sin(a) * RY * 0.30, CX + sx, CY + sy, 1.0)
        if rng.random() < 0.6:  # a branch off the line
            t = rng.uniform(0.35, 0.65)
            bx, by = CX + math.cos(a) * RX * (0.30 + 0.5 * t), CY + math.sin(a) * RY * (0.30 + 0.5 * t)
            b = a + rng.choice([-1, 1]) * rng.uniform(0.5, 0.9)
            line(bx, by, bx + math.cos(b) * 12, by + math.sin(b) * 7, 0.4)
    for k in range(16):  # the ring of runes
        a = k * math.tau / 16 + 0.1
        rx, ry = CX + math.cos(a) * RX * 0.40, CY + math.sin(a) * RY * 0.40
        tang = (-math.sin(a), math.cos(a) * 0.62)
        for s in (-1, 0, 1):
            xi, yi = int(rx + tang[0] * s * 1.4), int(ry + tang[1] * s * 1.4)
            if 0 <= xi < W and 0 <= yi < H:
                core[yi, xi] = True
        if k % 2 == 0:
            xi, yi = int(rx + math.cos(a) * 2.4), int(ry + math.sin(a) * 1.5)
            if 0 <= xi < W and 0 <= yi < H:
                core[yi, xi] = True
    for (xi, yi) in cracks_px:  # light seeping out of the fissures
        if (xi * 5 + yi * 3) % 3 == 0:
            core[yi, xi] = True
    core &= alpha
    out = np.zeros((H, W, 4), np.uint8)
    near = np.zeros((H, W))
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            dist = math.hypot(dx, dy)
            if dist <= 2.2:
                near = np.maximum(near, np.roll(np.roll(core.astype(float), dy, 0), dx, 1) * (1.0 - dist / 2.6))
    ys, xs = np.mgrid[0:H, 0:W]
    halo = ~core & alpha & (near > BAYER[ys % 4, xs % 4] * 0.9 + 0.1)
    out[halo] = (90, 200, 215, 80)
    for y, x in zip(*np.where(core)):
        out[y, x] = TEAL[3] if (x * 7 + y * 3) % 5 == 0 else TEAL[2]
    for fx, fy, shape in splinters:  # the splinters light up violet
        for ox, oy in shape:
            out[fy + oy, fx + ox] = CRYST_L[3] if (ox + oy) % 2 == 0 else CRYST_L[2]
    return out


def dim_layer(splinters):
    out = np.zeros((H, W, 4), np.uint8)
    for fx, fy, shape in splinters:
        ox, oy = shape[-1]
        out[fy + oy, fx + ox] = CRYST_D[3] + ()
    return out


# (dx, height, half width, lean) of every prism of a variant: very different silhouettes, mostly small
VARIANTS = [
    [(0, 17, 2, 1)],  # one tall thin
    [(0, 11, 2, -1), (5, 7, 1, 2)],  # a pair
    [(-3, 14, 2, -2), (3, 9, 1, 2), (7, 5, 1, 3)],  # a family
    [(0, 8, 3, 0)],  # squat and broad
    [(-4, 4, 1, -1), (0, 6, 1, 0), (4, 5, 1, 1), (8, 3, 1, 2)],  # a crowd of splinters
    [(0, 20, 2, 3)],  # the tallest, leaning
    [(-4, 10, 2, -2), (2, 13, 2, 1)],  # two, the right one taller
    [(0, 12, 2, 3), (-5, 6, 1, -2)],  # leaning with a stub
    [(0, 5, 2, 0), (5, 9, 2, 2)],  # a stump and a spike
    [(0, 15, 3, -1)],  # chunky
]


def crystal_cluster(variant, ramp, lit):
    """One group of ground crystals in a CW x CH frame (feet at (CW / 2, CGROUND)): hexagonal prisms with a pointed tip, left faces lit, a dark right edge, an ink outline."""
    img = np.zeros((CH, CW, 4), np.uint8)
    mask = np.zeros((CH, CW), int)  # 0 none, else face band + 1
    for dx, h, hw, lean in sorted(VARIANTS[variant], key=lambda sh: sh[1]):
        cx, base = CW // 2 + dx, CGROUND - (1 if dx else 0)
        for k in range(h):
            t = k / h
            y = base - k
            w = hw if t < 0.62 else max(0.0, hw * (1.0 - (t - 0.62) / 0.38) + 0.35)
            off = lean * t
            left, right = int(round(cx + off - w)), int(round(cx + off + w))
            for x in range(left, right + 1):
                if not (0 <= x < CW and 0 <= y < CH):
                    continue
                band = 2 if x < cx + off - 0.2 else 1
                if x == left:
                    band = 3
                if x == right and right > left:
                    band = 0
                if k == h - 1 or (t > 0.62 and x == int(round(cx + off))):
                    band = 3 if x <= cx + off else 2
                mask[y, x] = band + 1
    for y in range(CH):
        for x in range(CW):
            if mask[y, x]:
                img[y, x] = ramp[mask[y, x] - 1]
    solid = mask > 0
    for y in range(CH):
        for x in range(CW):
            if not solid[y, x]:
                for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + ddx, y + ddy
                    if 0 <= nx < CW and 0 <= ny < CH and solid[ny, nx]:
                        img[y, x] = INK + ()
                        break
    if lit:  # lit crystals get the white heart line
        for y in range(CH):
            for x in range(CW):
                if solid[y, x] and mask[y, x] == 3 and (x + y) % 3 == 0:
                    img[y, x] = CRYST_L[3]
    return img


def main():
    out_dir = ROOT / "props" / "waystone"
    out_dir.mkdir(parents=True, exist_ok=True)
    parts = layout()
    socks = sockets(np.random.default_rng(17))
    wild, d, alpha_w, _j, splinters, cracks_px = paint(True, parts, socks)
    clean, _d, alpha_c, _j2, _s2, _c2 = paint(False, parts, socks)
    glow = glow_layer(np.random.default_rng(8), d, alpha_c, socks, splinters, cracks_px)
    dim = dim_layer(splinters)
    ys, xs = np.mgrid[0:H, 0:W]
    ell = np.hypot((xs - CX) / RX, (ys - CY) / RY)
    noise = smooth_noise(np.random.default_rng(12), 3)
    t = np.clip(0.12 + 0.88 * np.clip(ell, 0, 1.0) + (noise - 0.5) * 0.12, 0.0, 1.0)
    body = (alpha_w | alpha_c) | (wild[..., 3] > 0) | (clean[..., 3] > 0) | (glow[..., 3] > 0)
    wave = np.zeros((H, W, 4), np.uint8)
    wave[..., 0] = (t * 255).astype(np.uint8)
    wave[..., 3] = np.where(body, 255, 0)
    write_png(out_dir / "ground_wild.png", wild)
    write_png(out_dir / "ground_clean.png", clean)
    write_png(out_dir / "ground_glow.png", glow)
    write_png(out_dir / "ground_dim.png", dim)
    write_png(out_dir / "ground_wave.png", wave)
    dark_sheet = np.zeros((CH, CW * NV, 4), np.uint8)
    lit_sheet = np.zeros((CH, CW * NV, 4), np.uint8)
    for v in range(NV):
        dark_sheet[:, v * CW:(v + 1) * CW] = crystal_cluster(v, CRYST_D, False)
        lit_sheet[:, v * CW:(v + 1) * CW] = crystal_cluster(v, CRYST_L, True)
    write_png(out_dir / "crystals_wild.png", dark_sheet)
    write_png(out_dir / "crystals_lit.png", lit_sheet)
    (ROOT.parent / "data" / "waystone_ground.json").write_text(json.dumps({"size": [W, H], "centre": [CX, CY], "frame": [CW, CH], "ground": CGROUND, "variants": NV,
                                                                         "radius": [RX, RY], "sockets": [list(s) for s in socks]}, indent=1))
    if len(sys.argv) > 1:
        from PIL import Image
        sc = 4
        bg = np.array((52, 96, 70))
        sheets = [wild, clean, glow]
        big = np.zeros((H * sc, W * len(sheets) * sc, 3), np.uint8)
        for i, a in enumerate(sheets):
            al = a[..., 3:4] / 255.0
            base = (bg * (0.35 if i == 2 else 1.0)).astype(np.uint8)
            col = (a[..., :3] * al + base * (1 - al)).astype(np.uint8)
            big[:, i * W * sc:(i + 1) * W * sc] = np.repeat(np.repeat(col, sc, 0), sc, 1)
        Image.fromarray(big).save(sys.argv[1])
    print("waystone ground written,", len(socks), "sockets")


if __name__ == "__main__":
    main()
