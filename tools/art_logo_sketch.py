"""Shadowspore wordmark sketch (docs/logo_title_concept.md, option A "grown letters").

Pure numpy + PIL, deterministic. Writes docs/img/logo_sketch.png (640x360 stage, shown 3x with
nearest filtering) and docs/img/logo_sketch_1x.png. Run with: py -3 tools/art_logo_sketch.py
Not used by the game yet: this is a look study.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "img"
W, H = 640, 360
SS = 4
LH = 38          # letter height
T = 8            # stroke
K = 0.9          # width scale
rng = np.random.default_rng(11)


def hexc(s):
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


BARK = [hexc(c) for c in ("150e20", "271a38", "3d2d58", "58477f", "8270b0")]
VOID = [hexc(c) for c in ("07040d", "0e0919", "1a1030", "221740")]
INK = hexc("0a0612")
MOSS = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "7cb96d")]
TEAL = [hexc(c) for c in ("1f6f78", "2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
VEIN_V = hexc("8a4dff")
VEIN_V2 = hexc("b06bff")
MAGENTA = hexc("ff4fd8")
CORE = hexc("ecd2ff")
RIM = hexc("5a36b8")

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0


def bayer(shape):
    return np.tile(BAYER, (shape[0] // 4 + 1, shape[1] // 4 + 1))[:shape[0], :shape[1]]


def glyph(ch, w, h=LH, t=T):
    im = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(im)

    def rect(x0, y0, x1, y1):
        d.rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], fill=255)

    def line(x0, y0, x1, y1, wd):
        d.line([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=255, width=int(wd * SS))

    m = h / 2
    if ch == "H":
        rect(0, 0, t, h); rect(w - t, 0, w, h); rect(0, m - t / 2, w, m + t / 2)
    elif ch == "E":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, h - t, w, h); rect(0, m - t / 2, w * 0.85, m + t / 2)
    elif ch == "P":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, m - t / 2, w, m + t / 2); rect(w - t, 0, w, m + t / 2)
    elif ch == "R":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, m - t / 2, w, m + t / 2); rect(w - t, 0, w, m + t / 2)
        line(w * 0.38, m, w - t * 0.5, h + 2, t * 1.15)
    elif ch == "D":
        d.rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=int(h * 0.42 * SS), fill=255,
                            corners=(False, True, True, False))
        d.rounded_rectangle([t * SS, t * SS, (w - t) * SS - 1, (h - t) * SS - 1], radius=int(h * 0.22 * SS), fill=0,
                            corners=(False, True, True, False))
    elif ch == "S":
        rx, ry = (w - t) / 2, (h - t) / 4
        y1, y2 = t / 2 + ry, h - t / 2 - ry
        pts = [(w / 2 + rx * np.cos(a), y1 + ry * np.sin(a)) for a in np.radians(np.linspace(-25, -270, 24))]
        pts += [(w / 2 + rx * np.cos(a), y2 + ry * np.sin(a)) for a in np.radians(np.linspace(-90, 155, 24))]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 1.05)
    elif ch == "A":
        line(w * 0.1, h + 2, w * 0.36, -1, t * 1.15); line(w * 0.9, h + 2, w * 0.64, -1, t * 1.15)
        rect(w * 0.3, 0, w * 0.7, t); rect(w * 0.2, h * 0.58, w * 0.8, h * 0.58 + t * 0.9)
    elif ch == "W":
        pts = [(t * 0.5, -1), (w * 0.26, h), (w * 0.5, h * 0.32), (w * 0.74, h), (w - t * 0.5, -1)]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 1.2)
    elif ch == "O":
        d.ellipse([0, 0, w * SS - 1, h * SS - 1], fill=255)
        d.ellipse([t * SS, t * SS, (w - t) * SS - 1, (h - t) * SS - 1], fill=0)
    im = im.filter(ImageFilter.GaussianBlur(SS * 1.1))
    im = im.resize((w, h), Image.BOX)
    return np.array(im) > 128


def smooth1(a, k=(0.25, 0.5, 0.25)):
    return np.convolve(a, k, mode="same")


# ---------------------------------------------------------------- layout
SPEC = [("S", 30, 0), ("H", 32, 0), ("A", 34, 0), ("D", 32, 0), ("O", 0, 0), ("W", 48, 0), None,
        ("S", 30, 1), ("P", 30, 1), ("O", 0, 1), ("R", 32, 1), ("E", 28, 1)]
GAP, WORD_GAP = 4, 9
items = []
for s in SPEC:
    if s is None:
        items.append(None)
        continue
    ch, w, grp = s
    w = LH + 3 if ch == "O" else int(round(w * K))
    items.append((ch, w, grp))
total = sum((i[1] if i else WORD_GAP) for i in items) + GAP * (len([i for i in items if i]) - 1)
X0 = (W - total) // 2
Y0 = 146

M = np.zeros((H, W), bool)
group = np.full((H, W), -1, np.int8)
orbs = []   # (cx, cy, hole_radius, grp)
x = X0
first = True
for it in items:
    if it is None:
        x += WORD_GAP - GAP
        continue
    ch, w, grp = it
    g = glyph(ch, w)
    M[Y0:Y0 + LH, x:x + w] |= g
    group[Y0:Y0 + LH, x:x + w][g] = grp
    if ch == "O":
        orbs.append((x + w / 2 - 0.5, Y0 + LH / 2 - 0.5, min(w, LH) / 2 - T, grp))
    x += w + GAP

yy, xx = np.mgrid[0:H, 0:W]
canvas = np.zeros((H, W, 3), np.float32)
glow = []   # (x, y, color, strength)

# ---------------------------------------------------------------- background
cx, cy = W / 2, Y0 + LH / 2 + 10
dist = np.sqrt(((xx - cx) / 330) ** 2 + ((yy - cy) / 190) ** 2)
t = np.clip(1.0 - dist, 0, 1)
bg_idx = np.floor(t * 3.2 + bayer((H, W)) * 0.999).astype(int)
bg_cols = np.stack([hexc("050208"), hexc("07040d"), hexc("0e0919"), hexc("1a1030")])
canvas[:] = bg_cols[np.clip(bg_idx, 0, 3)]
# motes / stars
for _ in range(130):
    px, py = rng.integers(0, W), rng.integers(0, H)
    canvas[py, px] = RIM * (0.35 + 0.4 * rng.random()) if rng.random() < 0.9 else hexc("cbaaff") * 0.6

# ---------------------------------------------------------------- baseline crack under the word
by = Y0 + LH + 7
crack_x = np.arange(X0 - 40, X0 + total + 40)
cy_off = np.round(1.4 * np.sin(crack_x * 0.07) + 1.1 * np.sin(crack_x * 0.19 + 1.3)).astype(int)
env = np.clip(1.0 - np.abs((crack_x - W / 2) / (total / 2 + 40)) ** 2.2, 0, 1)
for px, off, e in zip(crack_x, cy_off, env):
    if rng.random() < e * 1.05 + 0.05:
        canvas[by + off, px] = VEIN_V * 0.55
        if rng.random() < e * 0.5:
            canvas[by + off + 1, px] = hexc("34185e")
        if rng.random() < 0.10 * e:
            glow.append((px, by + off, VEIN_V2, 0.8))

# ---------------------------------------------------------------- drop shadow
shadow = np.zeros_like(M)
shadow[3:, 2:] = M[:-3, :-2]
canvas[shadow & ~M] = hexc("030106")

# ---------------------------------------------------------------- bark shading
mimg = Image.fromarray((M * 255).astype(np.uint8))
hf = (np.array(mimg.filter(ImageFilter.GaussianBlur(1.6)), np.float32) * 0.6 +
      np.array(mimg.filter(ImageFilter.GaussianBlur(4.0)), np.float32) * 0.4) / 255.0
gy, gx = np.gradient(hf)
nx, ny = -gx * 5.0, -gy * 5.0
nz = np.ones_like(nx)
nl = np.sqrt(nx * nx + ny * ny + nz * nz)
lx, ly, lz = -0.55, -0.62, 0.56
shade = (nx * lx + ny * ly + nz * lz) / nl
shade = np.clip(0.02 + shade * 0.92, 0, 1)

# wood grain: vertical streaks + speckle
coarse = rng.random((H // 9 + 2, W // 2 + 2))
streak = np.kron(coarse, np.ones((9, 2)))[:H, :W]
speck = rng.random((H, W))
grain = (streak - 0.5) * 0.34 + (speck - 0.5) * 0.05
shade = np.clip(shade + grain, 0, 1)
idx = np.clip(np.floor(shade * (len(BARK) - 1) + bayer((H, W)) * 0.55 + 0.22).astype(int), 0, len(BARK) - 1)
bark = np.stack(BARK)[idx]
canvas[M] = bark[M]

# knots / horizontal cracks in the grain (dark flecks)
for _ in range(120):
    px, py = rng.integers(X0, X0 + total), rng.integers(Y0, Y0 + LH)
    if M[py, px] and M[py, min(px + 2, W - 1)]:
        canvas[py, px] = BARK[0]
        canvas[py, px + 1] = BARK[1]

# ink outline (1 px outside)
dil = np.zeros_like(M)
for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    dil |= np.roll(np.roll(M, dy, 0), dx, 1)
outline = dil & ~M
canvas[outline] = INK

# lit rim: top-left inner edge pixels
inner_top = M & ~np.roll(M, 1, 0)
inner_left = M & ~np.roll(M, 1, 1)
rim_mask = (inner_top | inner_left) & (rng.random((H, W)) < 0.8)
canvas[rim_mask] = BARK[4] * 0.92

# ---------------------------------------------------------------- the void eats the tops
run = np.zeros((H, W), np.int16)
for y in range(1, H):
    run[y] = np.where(M[y], run[y - 1] + 1, 0)
run[0] = M[0].astype(np.int16)
n = rng.random(W)
n = smooth1(smooth1(n))
n = (n - n.min()) / (n.max() - n.min())
vein_starts = []
eaten = np.zeros_like(M)
for gx_ in range(W):
    for gy_ in range(H):
        if not (M[gy_, gx_] and run[gy_, gx_] == 1):
            continue
        grp = group[gy_, gx_]
        amount = 0.75 if grp == 0 else 0.16
        depth = int(np.floor(max(0.0, n[gx_] - (1 - amount)) / amount * 8.0 + rng.random() * 0.8))
        if grp == 0 and depth == 0 and rng.random() < 0.25:
            depth = 1
        # follow this vertical run down for `depth` pixels
        for k in range(depth):
            yk = gy_ + k
            if yk >= H or not M[yk, gx_]:
                break
            eaten[yk, gx_] = True
            canvas[yk, gx_] = (VOID[0], VOID[1], VOID[2])[min(k % 3, 2)] if k < depth - 1 else hexc("34185e")
        if depth >= 2 and gy_ + depth < H and M[gy_ + depth, gx_]:
            vein_starts.append((gx_, gy_ + depth, grp))
            glow.append((gx_, gy_ + depth, RIM, 0.35))

# veins crawling down from the eaten edge
vein_px = set()


def walk(vx, vy, grp, length, branch_p):
    col = VEIN_V if grp == 0 else TEAL[2]
    hot = VEIN_V2 if grp == 0 else TEAL[3]
    for i in range(length):
        if not (0 <= vy < H and 0 <= vx < W and M[vy, vx]):
            break
        c = hot if i < 2 else col
        canvas[vy, vx] = c
        vein_px.add((vx, vy))
        if rng.random() < (0.5 if i < 3 else 0.18):
            glow.append((vx, vy, c, 0.45 if i < 3 else 0.3))
        vy += 1
        vx += int(rng.choice([-1, 0, 0, 0, 1]))
        if rng.random() < 0.07 and 0 <= vy < H and 0 <= vx < W and M[vy, vx]:
            canvas[vy, vx] = col
            vx += int(rng.choice([-1, 1]))
        if rng.random() < branch_p and i > 1:
            walk(vx, vy, grp, int(length * 0.5), branch_p * 0.4)


for vx, vy, grp in vein_starts:
    if rng.random() < (0.30 if grp == 0 else 0.26):
        walk(vx, vy, grp, int(rng.integers(8, 22)), 0.10)

# magenta fissures in the SHADOW half
for _ in range(7):
    px = int(rng.integers(X0, X0 + total // 2 + 20)); py = int(rng.integers(Y0 + 2, Y0 + LH - 6))
    if M[py, px] and group[py, px] == 0:
        for k in range(int(rng.integers(2, 5))):
            qx, qy = px + k * int(rng.choice([-1, 1])) if False else px + k, py + (k % 2)
            if 0 <= qy < H and M[qy, qx]:
                canvas[qy, qx] = MAGENTA
                glow.append((qx, qy, MAGENTA, 0.45))

# ---------------------------------------------------------------- moss + mushrooms on the SPORE half
bottom = M & ~np.roll(M, -1, 0)
top = M & ~np.roll(M, 1, 0)
for gx_ in range(W):
    for gy_ in range(H):
        if bottom[gy_, gx_]:
            grp = group[gy_, gx_]
            p = 0.50 if grp == 1 else 0.14
            if rng.random() < p:
                hang = int(rng.integers(1, 4 if grp == 1 else 3))
                for k in range(hang):
                    yk = gy_ - k
                    if M[yk, gx_] and not eaten[yk, gx_]:
                        canvas[yk, gx_] = MOSS[min(k, 2) + (1 if rng.random() < 0.3 else 0) if k < 3 else 2] if False else MOSS[min(2, k + 1)]
        if top[gy_, gx_] and not eaten[gy_, gx_] and group[gy_, gx_] == 1 and rng.random() < 0.18:
            canvas[gy_, gx_] = MOSS[3]
            if M[gy_ + 1, gx_]:
                canvas[gy_ + 1, gx_] = MOSS[2]


def shroom(sx, sy, s):
    """tiny teal cap standing on ground row sy."""
    stem = TEAL[0] * 0.8
    for k in range(s):
        canvas[sy - k, sx] = hexc("a9c5c7") * 0.55
    cap_y = sy - s
    for dx in range(-s, s + 1):
        canvas[cap_y, sx + dx] = TEAL[1]
    for dx in range(-s + 1, s):
        canvas[cap_y - 1, sx + dx] = TEAL[2]
    canvas[cap_y - 1, sx - 1] = TEAL[3]
    canvas[cap_y, sx - s] = TEAL[0]
    glow.append((sx - 1, cap_y - 1, TEAL[3], 0.55))
    glow.append((sx, cap_y, TEAL[2], 0.3))


ground_y = Y0 + LH
for _ in range(14):
    # choose spots just under letter feet in the SPORE half
    px = int(rng.integers(X0 + total // 2 + 6, X0 + total - 2))
    if M[ground_y - 1, px] and not M[ground_y, px]:
        shroom(px, ground_y + 2, int(rng.integers(1, 3)))
shroom(X0 + total - 6, ground_y + 4, 2)
shroom(X0 + total // 2 + 14, ground_y + 5, 1)

# ---------------------------------------------------------------- the two O: void spore and life spore
def sphere(cx, cy, r, tones, lightdir=(-0.55, -0.6)):
    for yk in range(int(cy - r - 1), int(cy + r + 2)):
        for xk in range(int(cx - r - 1), int(cx + r + 2)):
            ddx, ddy = xk - cx, yk - cy
            rr = np.hypot(ddx, ddy)
            if rr > r:
                continue
            z = np.sqrt(max(0.0, 1 - (rr / r) ** 2))
            nrm = np.array([ddx / r, ddy / r, z])
            sh = float(np.clip(nrm @ np.array([lightdir[0], lightdir[1], 0.58]), 0, 1))
            i = int(np.clip(np.floor(sh * (len(tones) - 1) + BAYER[yk % 4, xk % 4]), 0, len(tones) - 1))
            canvas[yk, xk] = tones[i]


for cx_, cy_, hr, grp in orbs:
    # dark cavity
    for yk in range(int(cy_ - hr - 2), int(cy_ + hr + 3)):
        for xk in range(int(cx_ - hr - 2), int(cx_ + hr + 3)):
            if np.hypot(xk - cx_, yk - cy_) <= hr + 0.4 and not M[yk, xk]:
                canvas[yk, xk] = hexc("030106")
    r = hr - 1.6
    if grp == 0:
        sphere(cx_, cy_, r, VOID)
        # cold rim light, lower right
        for ang in np.linspace(-0.2, 1.7, 40):
            px, py = int(round(cx_ + np.cos(ang) * r)), int(round(cy_ + np.sin(ang) * r))
            canvas[py, px] = RIM
            glow.append((px, py, RIM, 0.25))
        # cracks from the core
        for ang in (0.4, 1.9, 3.5, 5.0, 2.7):
            for k in range(2, int(r)):
                px, py = int(round(cx_ + np.cos(ang) * k)), int(round(cy_ + np.sin(ang) * k + (k % 2) * 0.0))
                if rng.random() < 0.8:
                    canvas[py, px] = VEIN_V
                    if k < 5:
                        glow.append((px, py, VEIN_V2, 0.4))
        # glitching rows
        for ro in (-3, 1, 4):
            yk = int(cy_ + ro)
            sh_ = int(rng.choice([-2, 2]))
            row = canvas[yk, int(cx_ - r):int(cx_ + r) + 1].copy()
            canvas[yk, int(cx_ - r) + sh_:int(cx_ + r) + 1 + sh_] = row
            canvas[yk, int(cx_ - r) + (0 if sh_ > 0 else int(2 * r) - 1)] = MAGENTA
        # the eye-like core
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            canvas[int(cy_) + ddy, int(cx_) + ddx] = MAGENTA
        canvas[int(cy_), int(cx_)] = CORE
        glow.append((int(cx_), int(cy_), MAGENTA, 1.4))
        glow.append((int(cx_) - 1, int(cy_), MAGENTA, 0.9))
        glow.append((int(cx_) + 1, int(cy_), MAGENTA, 0.9))
        glow.append((int(cx_), int(cy_) + 1, MAGENTA, 0.9))
        glow.append((int(cx_), int(cy_) - 1, MAGENTA, 0.9))
    else:
        sphere(cx_, cy_, r, [TEAL[0] * 0.8, TEAL[0], TEAL[1], TEAL[2], TEAL[3]])
        # pores
        for _ in range(7):
            ang, rad = rng.random() * 6.28, rng.random() * r * 0.8
            px, py = int(round(cx_ + np.cos(ang) * rad)), int(round(cy_ + np.sin(ang) * rad))
            canvas[py, px] = TEAL[0] * 0.75
        # warm golden seed in the heart
        for ddy in range(-2, 3):
            for ddx in range(-2, 3):
                rr = np.hypot(ddx, ddy)
                if rr <= 2.3:
                    canvas[int(cy_) + ddy, int(cx_) + ddx] = GOLD[1] if rr > 1.5 else GOLD[2]
        canvas[int(cy_), int(cx_)] = GOLD[3]
        canvas[int(cy_) - 1, int(cx_) - 1] = hexc("fffaf0")
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)):
            glow.append((int(cx_) + ddx, int(cy_) + ddy, GOLD[3], 1.1))
        for ang in np.linspace(0.3, 6.0, 9):
            px, py = int(round(cx_ + np.cos(ang) * (r - 0.5))), int(round(cy_ + np.sin(ang) * (r - 0.5)))
            glow.append((px, py, TEAL[3], 0.35))

# spores drifting up from the life O
cx_, cy_, hr, _ = orbs[1]
for i in range(13):
    t_ = i / 12.0
    px = cx_ + 3 + t_ * 34 + np.sin(t_ * 7.0 + 0.5) * 7 + rng.normal(0, 3.0)
    py = cy_ - hr - 7 - t_ * 78 - rng.random() * 6
    px, py = int(px), int(py)
    c = GOLD[3] if i % 3 == 0 else TEAL[3]
    canvas[py, px] = c
    glow.append((px, py, c, 0.9 * (1 - t_ * 0.5)))
    if i % 2 == 0:
        canvas[py + 1, px - 1] = (TEAL[2] if i % 3 else GOLD[2]) * 0.7
    if i % 4 == 1:
        canvas[py - 1, px] = c * 0.6
        canvas[py, px + 1] = c * 0.45

# ---------------------------------------------------------------- additive glow with dithered halos
G = np.zeros((H, W, 3), np.float32)
for px, py, col, st in glow:
    if 0 <= px < W and 0 <= py < H:
        G[py, px] += col / 255.0 * st
gi = Image.fromarray(np.clip(G * 255, 0, 255).astype(np.uint8))
g1 = np.array(gi.filter(ImageFilter.GaussianBlur(1.3)), np.float32) / 255.0
g2 = np.array(gi.filter(ImageFilter.GaussianBlur(3.6)), np.float32) / 255.0
g3 = np.array(gi.filter(ImageFilter.GaussianBlur(8.0)), np.float32) / 255.0
halo = g1 * 1.8 + g2 * 3.4 + g3 * 3.0
levels = 5
halo_q = np.floor(np.clip(halo, 0, 1) * levels + bayer((H, W))[..., None] * 0.999) / levels
halo_q = halo_q * np.where(M | outline, 0.28, 1.0)[..., None]
out = canvas / 255.0 + halo_q * 0.8
out = np.clip(out, 0, 1)
img = Image.fromarray((out * 255 + 0.5).astype(np.uint8))

OUT.mkdir(parents=True, exist_ok=True)
img.save(OUT / "logo_sketch_1x.png")
img.resize((W * 3, H * 3), Image.NEAREST).save(OUT / "logo_sketch.png")
print("logo", total, "x", LH, "at", X0, Y0, "->", OUT / "logo_sketch.png")
