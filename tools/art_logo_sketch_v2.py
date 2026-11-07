"""Shadowspore wordmark sketch v2 (docs/logo_title_concept.md).

Stacked layout: SHADOW above SPORE, the two O aligned. Letters are thick and nearly touching; the void of
SHADOW eats into the living green of SPORE where the rows meet. Pure numpy + PIL, deterministic.
Writes docs/img/logo_sketch_v2.png (640x360 stage shown 3x) and docs/img/logo_sketch_v2_1x.png.
Run: py -3 tools/art_logo_sketch_v2.py        (a look study, not used by the game yet)
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "img"
W, H = 640, 360
SS = 4
LH = 52          # letter height
T = 11           # stroke
TO = 10          # stroke of the O rings
K = 1.12
GAP = 2          # between letters: nearly touching
ROWGAP = 2       # between the two rows
rng = np.random.default_rng(23)


def hexc(s):
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


BARK0 = [hexc(c) for c in ("150e20", "271a38", "3d2d58", "58477f", "8270b0")]
BARK1 = [hexc(c) for c in ("131320", "232a3a", "37445c", "4f6585", "7fa0b8")]
VOID = [hexc(c) for c in ("07040d", "0e0919", "1a1030", "221740")]
INK = hexc("0a0612")
MOSS = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
TEAL = [hexc(c) for c in ("1f6f78", "2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
VEIN_V, VEIN_V2 = hexc("8a4dff"), hexc("b06bff")
MAGENTA, CORE, RIM = hexc("ff4fd8"), hexc("ecd2ff"), hexc("5a36b8")
PURPLE_EDGE = hexc("34185e")
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
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, h - t, w, h); rect(0, m - t / 2, w * 0.86, m + t / 2)
    elif ch == "P":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, m - t / 2, w, m + t / 2); rect(w - t, 0, w, m + t / 2)
    elif ch == "R":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, m - t / 2, w, m + t / 2); rect(w - t, 0, w, m + t / 2)
        line(w * 0.36, m, w - t * 0.45, h + 2, t * 1.15)
    elif ch == "D":
        d.rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=int(h * 0.42 * SS), fill=255,
                            corners=(False, True, True, False))
        d.rounded_rectangle([t * SS, t * SS, (w - t) * SS - 1, (h - t) * SS - 1], radius=int(h * 0.2 * SS), fill=0,
                            corners=(False, True, True, False))
    elif ch == "S":
        rx, ry = (w - t) / 2, (h - t) / 4
        y1, y2 = t / 2 + ry, h - t / 2 - ry
        pts = [(w / 2 + rx * np.cos(a), y1 + ry * np.sin(a)) for a in np.radians(np.linspace(-25, -270, 26))]
        pts += [(w / 2 + rx * np.cos(a), y2 + ry * np.sin(a)) for a in np.radians(np.linspace(-90, 155, 26))]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 1.05)
    elif ch == "A":
        line(w * 0.1, h + 2, w * 0.38, -1, t * 1.1); line(w * 0.9, h + 2, w * 0.62, -1, t * 1.1)
        rect(w * 0.3, 0, w * 0.7, t); rect(w * 0.18, h * 0.6, w * 0.82, h * 0.6 + t * 0.85)
    elif ch == "W":
        pts = [(t * 0.5, -1), (w * 0.26, h), (w * 0.5, h * 0.3), (w * 0.74, h), (w - t * 0.5, -1)]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 1.15)
    elif ch == "O":
        d.ellipse([0, 0, w * SS - 1, h * SS - 1], fill=255)
        d.ellipse([t * SS, t * SS, (w - t) * SS - 1, (h - t) * SS - 1], fill=0)
    im = im.filter(ImageFilter.GaussianBlur(SS * 1.15))
    im = im.resize((w, h), Image.BOX)
    return np.array(im) > 128


def glyph_shade(g):
    pad = 8
    a = np.pad(g, pad)
    im = Image.fromarray((a * 255).astype(np.uint8))
    hf = (np.array(im.filter(ImageFilter.GaussianBlur(1.7)), np.float32) * 0.6 +
          np.array(im.filter(ImageFilter.GaussianBlur(4.5)), np.float32) * 0.4) / 255.0
    gy, gx = np.gradient(hf)
    nx, ny = -gx * 5.0, -gy * 5.0
    nl = np.sqrt(nx * nx + ny * ny + 1.0)
    sh = (nx * -0.55 + ny * -0.62 + 0.56) / nl
    return np.clip(0.02 + sh * 0.92, 0, 1)[pad:-pad, pad:-pad]


def smooth1(a, k=(0.25, 0.5, 0.25)):
    return np.convolve(a, k, mode="same")


# ---------------------------------------------------------------- layout: SHADOW over SPORE, the two O aligned
WIDTHS = dict(S=30, H=32, A=34, D=32, W=48, P=30, R=32, E=28)
ROW0, ROW1 = "SHADOW", "SPORE"


def wid(ch):
    return LH + 2 if ch == "O" else int(round(WIDTHS[ch] * K))


def row_positions(word, start):
    xs, x = [], start
    for ch in word:
        xs.append(x)
        x += wid(ch) + GAP
    return xs


r0 = row_positions(ROW0, 0)
o0 = r0[ROW0.index("O")]
pre1 = sum(wid(c) + GAP for c in ROW1[:ROW1.index("O")])
r1 = row_positions(ROW1, o0 - pre1)
total = max(r0[-1] + wid(ROW0[-1]), r1[-1] + wid(ROW1[-1]))
X0 = (W - total) // 2 + 2
Y0 = 108
Y1 = Y0 + LH + ROWGAP
LOGO_H = 2 * LH + ROWGAP

M = np.zeros((H, W), bool)
group = np.full((H, W), -1, np.int8)
shade = np.zeros((H, W), np.float32)
orbs = []   # (cx, cy, hole_radius, row)
letters = []
for row, (word, xs, y) in enumerate(((ROW0, r0, Y0), (ROW1, r1, Y1))):
    for ch, x in zip(word, xs):
        w = wid(ch)
        g = glyph(ch, w, LH, TO if ch == "O" else T)
        gx0 = X0 + x
        M[y:y + LH, gx0:gx0 + w] |= g
        group[y:y + LH, gx0:gx0 + w][g] = row
        sh = glyph_shade(g)
        shade[y:y + LH, gx0:gx0 + w][g] = sh[g]
        letters.append((ch, gx0, y, w, row))
        if ch == "O":
            orbs.append((gx0 + w / 2 - 0.5, y + LH / 2 - 0.5, min(w, LH) / 2 - TO, row))

canvas = np.zeros((H, W, 3), np.float32)
glow = []
eaten = np.zeros_like(M)


def inb(x, y):
    return 0 <= x < W and 0 <= y < H


# ---------------------------------------------------------------- background
cx, cy = W / 2, Y0 + LOGO_H / 2 + 6
dist = np.sqrt(((np.arange(W)[None, :] - cx) / 340) ** 2 + ((np.arange(H)[:, None] - cy) / 200) ** 2)
tt = np.clip(1.0 - dist, 0, 1)
bg_idx = np.floor(tt * 3.2 + bayer((H, W)) * 0.999).astype(int)
bg_cols = np.stack([hexc("050208"), hexc("07040d"), hexc("0e0919"), hexc("1a1030")])
canvas[:] = bg_cols[np.clip(bg_idx, 0, 3)]
for _ in range(140):
    px, py = rng.integers(0, W), rng.integers(0, H)
    canvas[py, px] = RIM * (0.35 + 0.4 * rng.random()) if rng.random() < 0.9 else hexc("cbaaff") * 0.6

# ---------------------------------------------------------------- baseline crack: void on the left, life on the right
by = Y1 + LH + 9
cxs = np.arange(X0 - 40, X0 + total + 40)
off = np.round(1.6 * np.sin(cxs * 0.06) + 1.2 * np.sin(cxs * 0.17 + 1.3)).astype(int)
env = np.clip(1.0 - np.abs((cxs - W / 2) / (total / 2 + 40)) ** 2.0, 0, 1)
for px, o, e in zip(cxs, off, env):
    if rng.random() < e * 1.1 + 0.08:
        k = (px - cxs[0]) / (cxs[-1] - cxs[0])
        col = VEIN_V * (1 - k) + TEAL[2] * k
        hot = VEIN_V2 * (1 - k) + TEAL[3] * k
        canvas[by + o, px] = hot * 0.8 if rng.random() < 0.35 else col * 0.75
        canvas[by + o + 1, px] = (PURPLE_EDGE * (1 - k) + TEAL[0] * k) * (0.9 if rng.random() < 0.7 else 0.6)
        if rng.random() < 0.06 * e:
            ln = int(rng.integers(3, 7)); sx = int(rng.choice([-1, 1]))
            for q in range(ln):
                canvas[by + o + 2 + q, px + (q // 2) * sx] = col * (0.7 - q * 0.08)
        if rng.random() < 0.22 * e:
            glow.append((px, by + o, hot, 0.9))
# contact shadow under the word so it sits on the ground
gy0 = Y1 + LH
for yk in range(gy0, gy0 + 9):
    a = 1.0 - (yk - gy0) / 9.0
    for xk in range(X0 - 6, X0 + total + 6):
        if BAYER[yk % 4, xk % 4] < a * 0.85:
            canvas[yk, xk] *= 0.45

# ---------------------------------------------------------------- drop shadow
sh_m = np.zeros_like(M)
sh_m[3:, 2:] = M[:-3, :-2]
canvas[sh_m & ~M] = hexc("030106")

# ---------------------------------------------------------------- bark: SHADOW plum, SPORE greener and livelier
coarse = rng.random((H // 9 + 2, W // 2 + 2))
streak = np.kron(coarse, np.ones((9, 2)))[:H, :W]
grain = (streak - 0.5) * 0.34 + (rng.random((H, W)) - 0.5) * 0.05
s_all = np.clip(shade + grain, 0, 1)
bd = bayer((H, W))
for row, ramp in ((0, BARK0), (1, BARK1)):
    n = len(ramp)
    idx = np.clip(np.floor(s_all * (n - 1) + bd * 0.55 + 0.22).astype(int), 0, n - 1)
    sel = M & (group == row)
    canvas[sel] = np.stack(ramp)[idx][sel]

# mossy patches across the faces of SPORE
blob = np.array(Image.fromarray((rng.random((H // 7 + 2, W // 7 + 2)) * 255).astype(np.uint8))
                .resize((W + 14, H + 14), Image.BICUBIC), np.float32)[:H, :W] / 255.0
blob = blob + np.clip(1.0 - (np.arange(H)[:, None] - Y1) / (LH * 0.9), 0, 1) * 0.22
moss_sel = M & (group == 1) & (blob > 0.60)
midx = np.clip(np.floor(s_all * 3.2 + bd * 0.7 + 0.5).astype(int), 0, 4)
canvas[moss_sel] = np.stack(MOSS)[midx][moss_sel]
me_top = moss_sel & ~np.roll(moss_sel, 1, 0)
me_left = moss_sel & ~np.roll(moss_sel, 1, 1)
me_bot = moss_sel & ~np.roll(moss_sel, -1, 0)
canvas[me_top | me_left] = MOSS[4]
canvas[me_bot] = MOSS[0]
for _ in range(110):
    px, py = rng.integers(X0, X0 + total), rng.integers(Y1, Y1 + LH)
    if moss_sel[py, px] and not me_bot[py, px]:
        canvas[py, px] = MOSS[5] if rng.random() < 0.3 else MOSS[4]
        if inb(px + 1, py + 1) and moss_sel[py + 1, px + 1]:
            canvas[py + 1, px + 1] = MOSS[3]

# knots in the grain
for _ in range(220):
    px, py = rng.integers(X0, X0 + total), rng.integers(Y0, Y1 + LH)
    if M[py, px] and M[py, min(px + 2, W - 1)] and not moss_sel[py, px]:
        canvas[py, px] = (BARK0 if group[py, px] == 0 else BARK1)[0]
        canvas[py, px + 1] = (BARK0 if group[py, px] == 0 else BARK1)[1]

# outline (1 px outside) and lit rim
dil = np.zeros_like(M)
for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    dil |= np.roll(np.roll(M, dy, 0), dx, 1)
outline = dil & ~M
canvas[outline] = INK
inner_top = M & ~np.roll(M, 1, 0)
inner_left = M & ~np.roll(M, 1, 1)
rim = (inner_top | inner_left) & (rng.random((H, W)) < 0.8)
canvas[rim & (group == 0)] = BARK0[4] * 0.92
canvas[rim & (group == 1)] = BARK1[4] * 0.95
dark_edge = (M & ~np.roll(M, -1, 0)) | (M & ~np.roll(M, -1, 1))
canvas[dark_edge] *= 0.7

# runs from top / bottom within each letter column
run_top = np.zeros((H, W), np.int16)
run_bot = np.zeros((H, W), np.int16)
for y in range(1, H):
    run_top[y] = np.where(M[y], run_top[y - 1] + 1, 0)
run_top[0] = M[0].astype(np.int16)
for y in range(H - 2, -1, -1):
    run_bot[y] = np.where(M[y], run_bot[y + 1] + 1, 0)
run_bot[H - 1] = M[H - 1].astype(np.int16)

# ---------------------------------------------------------------- helpers
vein_px = set()


def walk(vx, vy, dy, col, hot, length, branch_p, only_row=None, g0=0.5, beads=False):
    dx = int(rng.choice([-1, 0, 1]))
    for i in range(length):
        if not (inb(vx, vy) and M[vy, vx]):
            break
        if only_row is not None and group[vy, vx] != only_row:
            break
        c = hot if i < 2 else col
        canvas[vy, vx] = c
        vein_px.add((vx, vy))
        if rng.random() < (g0 if i < 3 else g0 * 0.4):
            glow.append((vx, vy, c, 0.45 if i < 3 else 0.3))
        if beads and i % 6 == 5:
            canvas[vy, vx] = hot
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if inb(vx + ddx, vy + ddy) and M[vy + ddy, vx + ddx]:
                    canvas[vy + ddy, vx + ddx] = c
            glow.append((vx, vy, hot, 1.0))
        vy += dy
        if rng.random() < 0.22:
            dx = int(rng.choice([-1, 0, 0, 1]))
        if i % 2 == 0:
            vx += dx
        if rng.random() < branch_p and i > 2:
            walk(vx, vy, dy, col, hot, int(length * 0.5), branch_p * 0.3, only_row, g0, beads)


def shroom(sx, sy, s, hot=TEAL[3]):
    for k in range(s + 1):
        if inb(sx, sy - k):
            canvas[sy - k, sx] = hexc("a9c5c7") * 0.6
    cy_ = sy - s - 1
    for dx in range(-s, s + 1):
        if inb(sx + dx, cy_):
            canvas[cy_, sx + dx] = TEAL[1]
    for dx in range(-s + 1, s):
        if inb(sx + dx, cy_ - 1):
            canvas[cy_ - 1, sx + dx] = TEAL[2]
    if s >= 2:
        for dx in range(-s + 2, s - 1):
            canvas[cy_ - 2, sx + dx] = TEAL[2]
    canvas[cy_ - 1, sx - 1] = hot
    canvas[cy_, sx - s] = TEAL[0]
    glow.append((sx - 1, cy_ - 1, hot, 0.6))
    glow.append((sx, cy_, TEAL[2], 0.3))


def free_above(x, y, n):
    return all(inb(x, y - k) and not M[y - k, x] and not outline[y - k, x] for k in range(1, n + 1))


def free_below(x, y, n):
    return all(inb(x, y + k) and not M[y + k, x] and not outline[y + k, x] for k in range(1, n + 1))


# ---------------------------------------------------------------- SHADOW: the void eats the tops, veins creep down
n_ = smooth1(smooth1(rng.random(W)))
n_ = (n_ - n_.min()) / (n_.max() - n_.min())
starts = []
for x in range(W):
    for y in range(H):
        if not (M[y, x] and run_top[y, x] == 1 and group[y, x] == 0):
            continue
        depth = int(np.floor(max(0.0, n_[x] - 0.25) / 0.75 * 9.0 + rng.random() * 0.8))
        for k in range(depth):
            if y + k >= H or not M[y + k, x]:
                break
            eaten[y + k, x] = True
            canvas[y + k, x] = VOID[min(k % 3, 2)] if k < depth - 1 else PURPLE_EDGE
        if depth >= 2 and M[y + depth, x]:
            starts.append((x, y + depth))
            glow.append((x, y + depth, RIM, 0.35))
for vx, vy in starts:
    if rng.random() < 0.30:
        walk(vx, vy, 1, VEIN_V, VEIN_V2, int(rng.integers(8, 24)), 0.10, only_row=0)
for _ in range(9):
    px = int(rng.integers(X0, X0 + total)); py = int(rng.integers(Y0 + 2, Y0 + LH - 6))
    if M[py, px] and group[py, px] == 0 and not eaten[py, px]:
        for k in range(int(rng.integers(2, 6))):
            qx, qy = px + k, py + (k % 2)
            if inb(qx, qy) and M[qy, qx]:
                canvas[qy, qx] = MAGENTA
                glow.append((qx, qy, MAGENTA, 0.45))

# ---------------------------------------------------------------- the seam: the void bites into the green
contact = {}
for x in range(W):
    ys0 = np.where(M[:, x] & (group[:, x] == 0))[0]
    ys1 = np.where(M[:, x] & (group[:, x] == 1))[0]
    if len(ys0) and len(ys1):
        b0, t1 = int(ys0.max()), int(ys1.min())
        if 0 < t1 - b0 <= ROWGAP + 2:
            contact[x] = (b0, t1)
depth_map = np.zeros(W)
if contact:
    xc = min(contact) + int(rng.integers(0, 4))
    while xc <= max(contact):
        wd = int(rng.integers(2, 5)); dd = float(rng.integers(5, 16))
        for dx in range(-wd, wd + 1):
            xx = xc + dx
            if xx in contact:
                depth_map[xx] = max(depth_map[xx], dd * np.sqrt(max(0.0, 1 - (dx / (wd + 0.6)) ** 2)))
        xc += int(rng.integers(7, 15))
for x, (b0, t1) in contact.items():
    d_ = int(round(depth_map[x]))
    if d_ > 0:
        for yk in range(b0 + 1, t1):
            canvas[yk, x] = VOID[1]
        for k in range(d_):
            yk = t1 + k
            if M[yk, x] and group[yk, x] == 1:
                eaten[yk, x] = True
                canvas[yk, x] = VOID[min(k % 3, 2)]
        yk = t1 + d_ - 1
        canvas[yk, x] = RIM
        if d_ > 1:
            canvas[yk - 1, x] = PURPLE_EDGE
        glow.append((x, yk, RIM, 0.7))
    else:
        # the green pushes back: moss tufts reach up into the dark
        left, right = depth_map[max(x - 1, 0)], depth_map[min(x + 1, W - 1)]
        if rng.random() < 0.75:
            for k, yk in enumerate(range(t1 - 1, b0 - 2, -1)):
                if k < 4 and inb(x, yk):
                    canvas[yk, x] = MOSS[min(5, 2 + k)]
        if left > 0 or right > 0:
            canvas[t1, x] = TEAL[4]
            glow.append((x, t1, TEAL[4], 0.9))
for x, (b0, t1) in contact.items():
    d_ = int(round(depth_map[x]))
    if d_ >= 5 and depth_map[x] >= depth_map[max(x - 1, 0)] and depth_map[x] >= depth_map[min(x + 1, W - 1)] and rng.random() < 0.8:
        walk(x, t1 + d_, 1, VEIN_V, VEIN_V2, int(rng.integers(5, 12)), 0.08, only_row=1)

# SHADOW's free bottoms: drips of void hang down
for x in range(W):
    for y in range(H):
        if M[y, x] and group[y, x] == 0 and run_bot[y, x] == 1 and free_below(x, y, 8) and rng.random() < 0.20:
            ln = int(rng.integers(3, 9))
            for k in range(1, ln + 1):
                canvas[y + k, x] = VOID[1] if k < ln else RIM
            glow.append((x, y + ln, RIM, 0.55))

# ---------------------------------------------------------------- SPORE: alive
def tuft(x, y, h):
    for dx, hh, lean in ((0, h, int(rng.choice([-1, 0, 1]))), (-2, max(2, h - 2), -1), (2, max(2, h - 2), 1)):
        for k in range(1, hh + 1):
            px = x + dx + (lean if k > hh * 0.6 else 0)
            if inb(px, y - k):
                canvas[y - k, px] = MOSS[min(5, 1 + (k * 4) // hh)]
    glow.append((x, y - h, MOSS[5], 0.15))


def flower(x, y, h):
    for k in range(1, h):
        canvas[y - k, x] = MOSS[2]
    mid = h // 2
    canvas[y - mid, x - 1] = MOSS[3]; canvas[y - mid - 1, x - 2] = MOSS[4]
    canvas[y - mid + 1, x + 1] = MOSS[3]; canvas[y - mid, x + 2] = MOSS[4]
    tx, ty = x, y - h
    for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        canvas[ty + ddy, tx + ddx] = TEAL[4] if ddy < 0 else TEAL[3]
    for ddx, ddy in ((1, -1), (-1, -1)):
        canvas[ty + ddy, tx + ddx] = TEAL[2]
    canvas[ty, tx] = GOLD[3]
    glow.append((tx, ty, GOLD[3], 1.1))
    for ddx, ddy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
        glow.append((tx + ddx, ty + ddy, TEAL[3], 0.75))


last_x = -99
for x in range(W):
    for y in range(H):
        if not (M[y, x] and group[y, x] == 1):
            continue
        if run_top[y, x] == 1 and not eaten[y, x] and free_above(x, y, 10) and x - last_x >= 3:
            r = rng.random()
            if r < 0.30:
                tuft(x, y, int(rng.integers(3, 7))); last_x = x
            elif r < 0.37:
                flower(x, y, int(rng.integers(6, 10))); last_x = x + 3
            elif r < 0.42:
                shroom(x, y - 1, int(rng.integers(1, 3))); last_x = x + 2
        if run_bot[y, x] == 1 and not eaten[y, x] and free_below(x, y, 10) and rng.random() < 0.20:
            ln = int(rng.integers(3, 10))
            vx = x
            for k in range(1, ln + 1):
                if k % 3 == 0:
                    vx += int(rng.choice([-1, 1]))
                canvas[y + k, vx] = MOSS[1] if k < ln - 1 else MOSS[4]
                if k % 3 == 2:
                    canvas[y + k, vx + 1] = MOSS[3]
            glow.append((vx, y + ln, TEAL[3], 0.6))
            canvas[y + ln, vx] = TEAL[3]

# life roots: a few clean, beaded veins growing up from the bottom
bottoms = [(x, y) for x in range(W) for y in range(H)
           if M[y, x] and group[y, x] == 1 and run_bot[y, x] == 1 and not eaten[y, x]]
rng.shuffle(bottoms)
picked = []
for x, y in bottoms:
    if all(abs(x - px) > 11 for px, _ in picked):
        picked.append((x, y))
for x, y in picked[:9]:
    walk(x, y - 1, -1, TEAL[2], TEAL[3], int(rng.integers(12, 26)), 0.07, only_row=1, g0=0.3, beads=True)

# glimmer berries and buds on the mossy faces
cands = [(x, y) for x in range(X0, X0 + total) for y in range(Y1 + 3, Y1 + LH - 3)
         if moss_sel[y, x] and not eaten[y, x] and (x, y) not in vein_px and M[y, x]]
rng.shuffle(cands)
placed = []
for x, y in cands:
    if len(placed) >= 16:
        break
    if all(abs(x - px) + abs(y - py) > 9 for px, py in placed):
        placed.append((x, y))
        gold = len(placed) % 3 != 0
        c0, c1 = (GOLD[2], GOLD[3]) if gold else (TEAL[3], TEAL[4])
        for ddx, ddy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            canvas[y + ddy, x + ddx] = c0
        canvas[y, x] = c1
        for ddx, ddy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            glow.append((x + ddx, y + ddy, c1, 0.8))

# mushrooms standing on the ground in front of SPORE
for _ in range(34):
    px = int(rng.integers(X0 + 6, X0 + total))
    gy_ = Y1 + LH
    if inb(px, gy_) and M[gy_ - 1, px] and not M[gy_, px]:
        shroom(px, gy_ + int(rng.integers(2, 7)), int(rng.integers(2, 5)))
shroom(X0 + total - 4, Y1 + LH + 7, 4)
shroom(X0 + total + 5, Y1 + LH + 3, 2)

# ---------------------------------------------------------------- the two O
def sphere(cx_, cy_, r, tones, lightdir=(-0.55, -0.6)):
    for yk in range(int(cy_ - r - 1), int(cy_ + r + 2)):
        for xk in range(int(cx_ - r - 1), int(cx_ + r + 2)):
            ddx, ddy = xk - cx_, yk - cy_
            rr = np.hypot(ddx, ddy)
            if rr > r:
                continue
            z = np.sqrt(max(0.0, 1 - (rr / r) ** 2))
            sh = float(np.clip(np.array([ddx / r, ddy / r, z]) @ np.array([lightdir[0], lightdir[1], 0.58]), 0, 1))
            i = int(np.clip(np.floor(sh * (len(tones) - 1) + BAYER[yk % 4, xk % 4]), 0, len(tones) - 1))
            canvas[yk, xk] = tones[i]


for cx_, cy_, hr, row in orbs:
    for yk in range(int(cy_ - hr - 2), int(cy_ + hr + 3)):
        for xk in range(int(cx_ - hr - 2), int(cx_ + hr + 3)):
            if np.hypot(xk - cx_, yk - cy_) <= hr + 0.4 and not M[yk, xk]:
                canvas[yk, xk] = hexc("030106")
    r = hr - 1.8
    ix, iy = int(cx_), int(cy_)
    if row == 0:
        sphere(cx_, cy_, r, VOID)
        for ang in np.linspace(-0.2, 1.7, 46):
            px, py = int(round(cx_ + np.cos(ang) * r)), int(round(cy_ + np.sin(ang) * r))
            canvas[py, px] = RIM
            glow.append((px, py, RIM, 0.25))
        for ang in (0.4, 1.9, 3.5, 5.0, 2.7, 4.3):
            for k in range(2, int(r)):
                px, py = int(round(cx_ + np.cos(ang) * k)), int(round(cy_ + np.sin(ang) * k))
                if rng.random() < 0.8:
                    canvas[py, px] = VEIN_V
                    if k < 6:
                        glow.append((px, py, VEIN_V2, 0.4))
        for ro in (-4, 1, 5):
            yk = iy + ro
            sh_ = int(rng.choice([-2, 2]))
            rowpx = canvas[yk, int(cx_ - r):int(cx_ + r) + 1].copy()
            canvas[yk, int(cx_ - r) + sh_:int(cx_ + r) + 1 + sh_] = rowpx
            canvas[yk, int(cx_ - r) + (0 if sh_ > 0 else int(2 * r) - 1)] = MAGENTA
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)):
            canvas[iy + ddy, ix + ddx] = MAGENTA
        canvas[iy, ix] = CORE
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            glow.append((ix + ddx, iy + ddy, MAGENTA, 1.1 if (ddx or ddy) else 1.5))
    else:
        sphere(cx_, cy_, r, [TEAL[0] * 0.8, TEAL[0], TEAL[1], TEAL[2], TEAL[3]])
        for _ in range(9):
            ang, rad = rng.random() * 6.28, rng.random() * r * 0.8
            canvas[int(round(cy_ + np.sin(ang) * rad)), int(round(cx_ + np.cos(ang) * rad))] = TEAL[0] * 0.75
        for ddy in range(-3, 4):
            for ddx in range(-3, 4):
                rr = np.hypot(ddx, ddy)
                if rr <= 3.2:
                    canvas[iy + ddy, ix + ddx] = GOLD[0] if rr > 2.5 else (GOLD[1] if rr > 1.6 else GOLD[2])
        canvas[iy, ix] = GOLD[3]
        canvas[iy - 1, ix - 1] = hexc("fffaf0")
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
            glow.append((ix + ddx, iy + ddy, GOLD[3], 1.0))
        for ang in np.linspace(0.3, 6.0, 11):
            px, py = int(round(cx_ + np.cos(ang) * (r - 0.5))), int(round(cy_ + np.sin(ang) * (r - 0.5)))
            glow.append((px, py, TEAL[3], 0.35))
        # a void tendril reaching into the life O from above, held back by the light
        for k in range(4):
            if M[int(cy_ - r) - 1 + k, ix] is not None:
                pass

# spores rising from the right-hand end of SPORE
ex = X0 + r1[-1] + wid("E") / 2 + 8
for i in range(22):
    t_ = i / 21.0
    px = int(ex - 14 + rng.random() * 36 + t_ * 40 + np.sin(t_ * 7.0) * 6)
    py = int(Y1 - 4 - t_ * 95 - rng.random() * 8)
    if not inb(px, py) or M[py, px]:
        continue
    c = GOLD[3] if i % 3 == 0 else TEAL[3]
    canvas[py, px] = c
    glow.append((px, py, c, 0.9 * (1 - t_ * 0.5)))
    if i % 2 == 0 and inb(px - 1, py + 1):
        canvas[py + 1, px - 1] = (TEAL[2] if i % 3 else GOLD[2]) * 0.7
    if i % 4 == 1 and inb(px, py - 1):
        canvas[py - 1, px] = c * 0.6

# void motes rising off SHADOW, drifting the other way
for i in range(16):
    t_ = i / 15.0
    px = int(X0 + 20 + rng.random() * total * 0.62 - t_ * 34)
    py = int(Y0 - 3 - t_ * 62 - rng.random() * 8)
    if not inb(px, py) or M[py, px]:
        continue
    c = MAGENTA if i % 5 == 0 else (VEIN_V2 if i % 2 else RIM)
    canvas[py, px] = c * 0.9
    glow.append((px, py, c, 0.55 * (1 - t_ * 0.5)))
    if i % 3 == 0 and inb(px, py + 1):
        canvas[py + 1, px] = c * 0.45

# ---------------------------------------------------------------- additive glow with dithered halos
G = np.zeros((H, W, 3), np.float32)
for px, py, col, st in glow:
    if inb(px, py):
        G[py, px] += col / 255.0 * st
gi = Image.fromarray(np.clip(G * 255, 0, 255).astype(np.uint8))
g1 = np.array(gi.filter(ImageFilter.GaussianBlur(1.3)), np.float32) / 255.0
g2 = np.array(gi.filter(ImageFilter.GaussianBlur(3.6)), np.float32) / 255.0
g3 = np.array(gi.filter(ImageFilter.GaussianBlur(8.0)), np.float32) / 255.0
halo = g1 * 1.8 + g2 * 3.4 + g3 * 3.0
levels = 5
halo_q = np.floor(np.clip(halo, 0, 1) * levels + bayer((H, W))[..., None] * 0.999) / levels
halo_q = halo_q * np.where(M | outline, 0.28, 1.0)[..., None]
out = np.clip(canvas / 255.0 + halo_q * 0.8, 0, 1)
img = Image.fromarray((out * 255 + 0.5).astype(np.uint8))

OUT.mkdir(parents=True, exist_ok=True)
img.save(OUT / "logo_sketch_v2_1x.png")
img.resize((W * 3, H * 3), Image.NEAREST).save(OUT / "logo_sketch_v2.png")
print("logo", total, "x", LOGO_H, "at", X0, Y0, "->", OUT / "logo_sketch_v2.png")
