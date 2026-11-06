"""The fallen knight: a felled tree of this world (violet-veined bark, teal shelf fungi) with a dead knight slumped against it. He has Ellie's
proportions (same ellipsoid sizes as `build()` in art_hero3d.py) in worn plate, and the void is eating him: black flesh, glowing veins, a pool
on the ground.   python3 tools/art_fallen_knight.py [preview.png]
Writes assets/props/fallen_knight.png (112x88, feet/ground row 76) and fallen_knight_glow.png (only the emissive pixels, drawn unlit)."""
import math
import sys
import numpy as np
import art_hero3d as h
from gen_art import ROOT, hexc, write_png, CLEAR

h.FW, h.FH, h.GROUND_ROW = 112, 64, 47
FW, FH = h.FW, h.FH
BASE = len(h.RAMPS)
STEEL, STEEL_D, CLOTH, BARK, BARK_D, EARTH, RING, MOSS, VOID, VGLOW = range(BASE, BASE + 10)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1f1d30", "3d3d5a", "6c7090", "aeb4cc"],  # steel, cold and dull
    ["141221", "292840", "474a6a", "787ea0"],  # darker plate (gauntlets, greaves, sabatons)
    ["26111d", "4a1d31", "70304a", "985470"],  # tabard: old wine red
    ["1a1322", "34283c", "55435a", "85697a"],  # bark, like the trees' trunks
    ["0e0914", "1d1428", "33253d", "4d3a54"],  # bark grooves
    ["150f0e", "2a1f1a", "42332a", "685344"],  # earth
    ["5c4852", "8b727c", "bda3a8", "e6d3cf"],  # wood rings of the cut
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss
    ["040208", "0a0612", "170d28", "2c1d4c"],  # void flesh
    ["5a1c8c", "a02fd0", "e45cf0", "ffc8ff"],  # void glow: the standard magenta of every shadow creature
]]
GLOW_MATS = (h.TEAL, VGLOW, h.VIOLET)
rng = np.random.default_rng(11)
m = h.Model()
ell, limb, ribbon = m.ell, m.limb, m.ribbon
V = lambda *a: np.array(a, float)


# ------------------------------------------------------------------ the felled tree
X0, X1 = -40.0, 36.0
LOG_Z = -9.0


def radius(x):
    t = (x - X0) / (X1 - X0)
    return 7.4 + 3.8 * max(0.0, 1.0 - t * 4.5) ** 2 + 0.4 * math.sin(x * 0.13) - 0.7 * t


def spine(x):
    return V(x, radius(x) * 0.95, LOG_Z + 1.4 * math.sin(x * 0.07 + 1.0))


def surf(x, phi, out=0.0):
    """Point on the trunk: phi 0 = top, 90 = the side facing the viewer."""
    r = radius(x) + out
    p = math.radians(phi)
    return spine(x) + V(0.0, r * math.cos(p), r * math.sin(p) * 0.97)


x = X0
while x <= X1:
    r = radius(x)
    ell(spine(x), (1.5, r, r * 0.97), BARK)
    x += 0.8
# bark grooves along the trunk
for phi in (-25, 8, 32, 55, 76, 95):
    pts = []
    x = X0 + 2
    while x < X1 - 2:
        pts.append(surf(x, phi + 6 * math.sin(x * 0.21 + phi), -0.15))
        x += 2.5
    for a, b in zip(pts, pts[1:]):
        if rng.random() < 0.75:
            limb(a, b, 0.5, 0.5, BARK_D)
# violet veins (the trunks of these trees are veined with it)
for phi0, xs in ((14, -34), (62, -22), (84, 4), (40, 14)):
    phi, x = phi0, xs
    pts = []
    for _ in range(7):
        pts.append(surf(x, phi, 0.1))
        x += rng.uniform(2.5, 5.0)
        phi += rng.uniform(-9, 9)
    for a, b in zip(pts, pts[1:]):
        limb(a, b, 0.45, 0.38, h.VIOLET, kind="emit")
# moss on top, teal shelf fungi on the side
for xm in (-30, -9, 12, 30):
    ell(surf(xm, 8 + 10 * math.sin(xm), 0.5), (4.2, 1.1, 2.8), MOSS)
    ell(surf(xm + 4, 28, 0.5), (2.4, 0.9, 1.6), MOSS)
for xf, ph in ((-24, 70), (-5, 82), (24, 58)):
    for k in range(2):
        base = surf(xf + 0.6 * k, ph - 6 * k, 0.4)
        ell(base + V(0, -2.2 * k, 1.2 + 0.6 * k), (1.8 - 0.3 * k, 0.6, 1.4 - 0.2 * k), h.TEAL, kind="emit")
# torn-off root end at the left: buttress roots and a clump of earth
for s, dx in ((-1.0, 0), (-0.45, -2), (0.4, -3), (1.0, 0)):
    p0 = V(X0 + 4, 7.0, LOG_Z + s * 6.0)
    p1 = V(X0 - 11 + dx, 1.0, LOG_Z + s * 13.0)
    limb(p0, p1, 3.6, 1.3, BARK)
    limb(p0 + V(0, 0.8, 0), p1 + V(0, 0.9, 0), 0.5, 0.4, BARK_D)
ell(V(X0 - 3, 4.5, LOG_Z + 1), (5.5, 5.0, 8.0), EARTH)
ell(V(X0 - 12, 1.6, LOG_Z + 9), (4.5, 1.8, 3.2), EARTH)
for k in range(5):
    ell(V(X0 - 8 + rng.uniform(-4, 4), 1.0, LOG_Z + rng.uniform(-9, 14)), (1.4, 0.8, 1.2), EARTH)
# the broken end at the right: wood rings, splinters
xe = X1 + 1.2
r_end = radius(X1)
for k, (f, mat) in enumerate(((1.0, BARK), (0.9, RING), (0.74, BARK_D), (0.66, RING), (0.5, BARK_D), (0.42, RING), (0.2, BARK_D))):
    ell(spine(X1) + V(xe - X1 + 0.15 * k, 0, 0), (0.7, r_end * f, r_end * f * 0.97), mat)
for k, (dy, dz) in enumerate(((5, 1), (-3, -4), (2, 6), (-6, 3))):
    c = spine(X1) + V(1.5, dy, dz)
    limb(c, c + V(4.5 + k, 1.0, 0.5), 1.1, 0.25, BARK_D if k % 2 else RING)

# ------------------------------------------------------------------ the knight (Ellie's proportions)
LEAN = 0.30
P = V(4.0, 3.7, 5.0)  # pelvis centre
ROT = h.rot_x(-LEAN)


def Tl(p):
    """A point of Ellie's model (pelvis at y 24.5), tipped back against the trunk."""
    return P + ROT @ (np.array(p, float) - V(0.0, 24.5, 0.0))


# cloth under the plate, belt, tabard
ell(P, (4.2, 3.4, 3.2), h.LEGGING)
ell(Tl((0, 26.6, 0)), (3.9, 0.9, 3.4), h.LEATHER)
ell(Tl((0, 26.6, 3.1)), (1.0, 0.8, 0.5), h.GOLD, kind="emit")
ell(Tl((0, 29.8, 0)), (2.85, 3.3, 2.3), CLOTH, R=ROT)
ell(Tl((0, 34.2, 0)), (3.7, 4.1, 2.9), CLOTH, R=ROT)
# breastplate with a centre ridge, waist plate, gorget, fauld lames round the hips
ell(Tl((0, 35.0, 0.9)), (4.5, 5.3, 3.5), STEEL, R=ROT)
ell(Tl((0, 35.0, 4.0)), (0.55, 4.6, 0.6), STEEL, R=ROT)
ell(Tl((0, 29.4, 0.5)), (3.5, 3.0, 2.7), STEEL_D, R=ROT)
ell(Tl((0, 40.0, 0.2)), (3.3, 1.5, 3.1), STEEL, R=ROT)
for th in np.linspace(-1.75, 1.75, 11):
    c = P + V(4.8 * math.sin(th), -0.4, 4.2 * math.cos(th) + 0.2)
    ell(c, (2.1, 3.2, 0.9), STEEL if abs(th) < 1.2 else STEEL_D, R=h.rot_y(th) @ h.rot_x(0.18))
# tabard: from the chest down over the lap
ribbon([Tl((0, 33.5, 3.9)), Tl((0, 27.5, 4.4)), P + V(0, 1.2, 8.0), P + V(0.4, 0.5, 14.5)], [3.4, 3.5, 3.2, 2.7, 2.2], 0.45, CLOTH, (0, 0.7, 1.0), tag=2.0)
ell(Tl((0, 31.0, 4.5)), (1.1, 1.1, 0.4), h.GOLD, kind="emit")  # a small tarnished crest
ell(Tl((0, 31.0, 4.6)), (0.35, 1.7, 0.4), h.GOLD, kind="emit")
ell(Tl((0, 31.4, 4.6)), (1.7, 0.35, 0.4), h.GOLD, kind="emit")

# legs: the right one stretched out, the left one drawn up; knee cops, greaves, sabatons
LEG = {1: (2.15, 1.3, 0.55), -1: (2.3, 1.4, 0.42)}  # thigh angle, knee bend, splay
KNEE = {}
for side, (t, flex, splay) in LEG.items():
    hip = P + V(side * 2.5, -0.6, 0.2)
    Rs = h.rot_y(side * splay)
    knee = hip + Rs @ (11.5 * V(0, -math.cos(t), math.sin(t)))
    ankle = knee + Rs @ (10.0 * V(0, -math.cos(t - flex), math.sin(t - flex)))
    KNEE[side] = knee
    limb(hip, knee, 2.9, 2.5, STEEL_D)
    limb(hip + (knee - hip) * 0.15, knee, 2.5, 2.2, h.LEGGING)
    limb(knee, ankle, 2.35, 1.7, STEEL)
    ell(knee + V(0, 1.1, 0.9), (3.1, 2.7, 3.0), STEEL, R=Rs)  # knee cop
    ell(knee + V(0, 1.1, 0.9), (3.4, 0.6, 3.2), h.GOLD, kind="emit", R=Rs)
    fwd = Rs @ V(0, 0, 1)
    ell(ankle + V(0, -0.9, 0) + fwd * 2.2, (2.0, 1.4, 3.6), STEEL_D, R=Rs @ h.rot_x(-0.12))  # sabaton
    ell(ankle + V(0, 0.2, 0) - fwd * 0.6, (1.9, 1.9, 1.9), STEEL_D)

# arms: the right hand rests on the thigh, the left hangs to the ground
S_R, S_L = Tl((4.7, 38.0, 0.0)), Tl((-4.7, 38.0, 0.0))
for S, target, pole in ((S_R, KNEE[1] + V(1.0, 2.4, -3.5), V(1, -0.3, -0.6)), (S_L, P + V(-9.8, 2.2, 7.5), V(-1, -0.5, -0.3))):
    ell(S + V(np.sign(S[0] - P[0]) * 0.6, 0.4, 0), (3.5, 2.4, 3.2), STEEL)  # pauldron
    ell(S + V(np.sign(S[0] - P[0]) * 0.8, -1.5, 0), (3.0, 1.6, 2.8), STEEL_D)
    el, wr = h.ik2(S, target, 6.6, 6.0, pole)
    d2 = (wr - el) / np.linalg.norm(wr - el)
    limb(S, el, 1.75, 1.6, CLOTH)
    limb(el, wr, 1.65, 1.4, STEEL)
    ell(el, (2.1, 2.1, 2.1), STEEL)
    ell(wr + d2 * 1.1, (1.6, 1.9, 1.6), STEEL_D)

# head: a closed helm bowed onto the chest, the visor dark, a single dim glint in the slit
hc = Tl((0.0, 43.6, 2.0))
RH = h.rot_x(0.28)
ell(hc, (4.9, 5.5, 5.1), STEEL, R=RH)
ell(hc + RH @ V(0, -3.1, 1.2), (4.3, 2.8, 4.3), STEEL_D, R=RH)
ell(hc + RH @ V(0, 5.3, 0), (0.8, 0.7, 4.6), STEEL, R=RH)
ell(hc + RH @ V(0, 0.9, 4.95), (3.5, 0.6, 0.9), VOID, R=RH)
ell(hc + RH @ V(0, -0.8, 5.1), (0.55, 2.4, 0.8), STEEL, R=RH)
ell(hc + RH @ V(-1.9, 0.9, 5.45), (0.6, 0.4, 0.3), VGLOW, R=RH, kind="emit")
ribbon([hc + RH @ V(0, 5.2, -1.5), hc + RH @ V(0, 6.4, -4.5), hc + RH @ V(1.0, 3.5, -8.5), hc + RH @ V(2.2, -1.0, -9.5)], [1.4, 1.5, 1.2, 0.6], 0.4, CLOTH, (1, 0, 0), tag=5.0)  # a broken plume
# sword at his hip: the scabbard lies along the ground, the hilt at the belt
sw0 = P + V(-5.4, 1.7, 0.6)
limb(sw0, P + V(-8.4, 0.9, 9.0), 1.0, 1.0, h.LEATHER)
limb(P + V(-8.4, 0.9, 9.0), P + V(-9.4, 0.9, 19.0), 1.0, 0.9, h.LEATHER)
ell(P + V(-9.6, 0.9, 19.8), (1.1, 1.0, 1.0), STEEL_D)
limb(sw0, sw0 + V(-0.6, 4.2, -1.8), 0.85, 0.8, h.LEATHER)
ell(sw0 + V(-0.7, 4.8, -2.0), (1.0, 1.0, 1.0), h.GOLD, kind="emit")
ell(sw0 + V(-0.3, 2.3, -0.8), (2.9, 0.45, 0.6), STEEL)
# a dented shield leaning against the trunk
SHR = h.rot_x(-0.5)
n_sh = SHR @ V(0, 0, 1)
shc = V(-22.0, 6.6, -1.2)
ell(shc, (7.6, 7.6, 1.0), STEEL_D, R=SHR)
ell(shc + n_sh * 0.6, (6.4, 6.4, 1.0), CLOTH, R=SHR)
ell(shc + n_sh * 1.4, (1.9, 1.9, 1.0), STEEL, R=SHR)
ell(shc + n_sh * 1.1 + SHR @ V(0, 3.4, 0), (1.3, 0.9, 0.8), h.GOLD, kind="emit", R=SHR)

# ------------------------------------------------------------------ the void takes him
def plate_point(px, py):
    """A point on the breastplate (Ellie coordinates: plate centre (0, 35, 0.9), radii 4.5 / 5.3 / 3.5), a little outside."""
    q = 1.0 - (px / 4.5) ** 2 - ((py - 35.0) / 5.3) ** 2
    return Tl((px, py, 0.9 + 3.5 * math.sqrt(max(q, 0.0)) + 0.25))


def vein(start, steps, step_len, bias, mat_r=0.4, nodule=True):
    px, py = start
    ang = bias
    prev = plate_point(px, py)
    for i in range(steps):
        ang += rng.uniform(-0.8, 0.8)
        px += step_len * math.cos(ang)
        py += step_len * math.sin(ang)
        if ((px / 4.2) ** 2 + ((py - 35.0) / 5.0) ** 2) > 0.92:
            break
        cur = plate_point(px, py)
        limb(prev, cur, mat_r, mat_r * 0.85, VGLOW, kind="emit")
        if nodule and i % 3 == 2:
            ell(cur, (0.7, 0.7, 0.7), VGLOW, kind="emit")
        prev = cur


# a breach in the breastplate, filled with black flesh and veined all over the plate
for dx, dy, rr in ((-1.9, 34.0, 1.6), (-2.7, 32.4, 1.1)):
    ell(plate_point(dx, dy) + ROT @ V(0, 0, 0.3), (rr, rr * 1.25, 0.9), VOID, R=ROT)
for ang in (0.5, 2.0, 3.6, 4.6, 5.8):
    vein((-1.9, 34.0), 7, 1.0, ang)
# black growth crawling over the left shoulder and up the neck
for c, r in ((S_L + V(-0.3, 1.9, 0.6), (2.4, 1.2, 2.2)), (Tl((-2.4, 39.6, 1.2)), (1.8, 1.0, 1.7)), (Tl((-3.4, 37.5, 2.0)), (1.5, 1.0, 1.4))):
    ell(c, r, VOID)
for a, b in ((S_L + V(-1.0, 1.8, 1.8), Tl((-2.6, 39.8, 2.6))), (Tl((-3.4, 37.8, 2.6)), Tl((-2.4, 34.4, 3.8)))):
    limb(a, b, 0.4, 0.34, VGLOW, kind="emit")
# it has swallowed the drawn-up left leg: a skin of black flesh on the greave and the knee, tendrils round it
kn = KNEE[-1]
ell(kn + V(-0.6, 1.5, 1.4), (3.0, 2.4, 2.5), VOID)
ell(kn + V(-0.5, -2.8, 2.9), (2.3, 3.0, 2.0), VOID)
ell(kn + V(0.7, -5.2, 3.8), (2.0, 2.4, 1.7), VOID)
for k in range(3):
    a = kn + V(-0.4, 1.5 - 2.4 * k, 1.8 + 0.7 * k)
    b = kn + V(1.6, 0.8 - 2.0 * k, 3.1 + 0.8 * k)
    limb(a, b, 0.4, 0.34, VGLOW, kind="emit")


def tendril(p0, p1, radius0=1.1, radius1=0.35, sway=1.6, glow=3):
    p0, p1 = np.array(p0, float), np.array(p1, float)
    n = max(4, int(np.linalg.norm(p1 - p0) / 2.6))
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(p0 + (p1 - p0) * t + V(rng.normal(0, sway), 0.0, rng.normal(0, sway)) * math.sin(math.pi * t) * 0.8)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        t = i / n
        limb(a, b, radius0 + (radius1 - radius0) * t, radius0 + (radius1 - radius0) * (t + 1.0 / n), VOID)
        if i % glow == 1:
            ell(b + V(0, 0.7, 0), (0.62, 0.62, 0.62), VGLOW, kind="emit")


# the pool it spreads on the ground, tendrils reaching away from him and up the trunk
for c, r in (((-9.0, 0.35, 12.0), (10.0, 0.5, 5.5)), ((9.0, 0.35, 15.5), (11.0, 0.5, 5.0)), ((-17.0, 0.3, 7.0), (6.0, 0.45, 3.4)),
             ((21.0, 0.3, 10.0), (6.5, 0.45, 3.6)), ((1.0, 0.3, 21.0), (7.0, 0.45, 2.8)), ((-3.0, 0.4, 5.0), (6.5, 0.5, 3.5))):
    ell(V(*c), r, VOID)
tendril(P + V(-5.0, 0.8, 5.0), V(-26.0, 0.9, 16.0))
tendril(P + V(9.0, 0.8, 4.0), V(34.0, 0.9, 12.0), 1.0, 0.3)
tendril(V(-14.0, 0.9, 3.0), V(-33.0, 0.9, 4.0), 0.9, 0.3)
# onto the trunk: black flesh on its lower side, veins climbing up
for xx, ph, r in ((-12, 90, (3.6, 2.4, 2.2)), (-4, 78, (4.4, 3.0, 2.4)), (4, 88, (3.2, 2.2, 2.0)), (10, 70, (3.8, 2.6, 2.3)), (18, 84, (3.0, 2.0, 1.9))):
    ell(surf(xx, ph, 0.2) + V(0, 0, 0.3), r, VOID)
for xx, ph in ((-8, 70), (-1, 62), (7, 76), (14, 60)):
    pts = [surf(xx + 1.4 * k * rng.uniform(0.5, 1.2), ph - 10 * k, 0.5) for k in range(5)]
    for a, b in zip(pts, pts[1:]):
        limb(a, b, 0.42, 0.32, VGLOW, kind="emit")
# a few void blooms in the pool
for bx, bz in ((-14.0, 11.0), (13.0, 18.0), (-24.0, 12.0), (2.0, 24.0)):
    top = V(bx, 3.8 + rng.uniform(0, 1.4), bz)
    limb(V(bx, 0.5, bz), top, 0.45, 0.3, VOID)
    ell(top + V(0, 0.4, 0), (0.95, 0.75, 0.95), VGLOW, kind="emit")
    for sx in (-1, 1):
        ell(top + V(sx * 1.0, -0.2, 0), (0.7, 0.3, 0.45), VOID, R=h.rot_x(0.0))


# ------------------------------------------------------------------ render
def render():
    yaw = -0.3
    depth, code = h.render(m.transform(yaw, 0.0))
    return h.to_pixels(depth, code)


def add_shadow(rows):
    cx, cy = FW / 2 - 2, h.GROUND_ROW - 7
    for y in range(FH):
        for x in range(FW):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - cx) / 46.0, (y + 0.5 - cy) / 10.5
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 70)
    return rows


def glow_rows(rows):
    colours = {}
    for mat in GLOW_MATS:
        for b, c in enumerate(h.RAMPS[mat]):
            if mat != h.VIOLET or b >= 1:
                colours[tuple(c)] = mat
    out = [[CLEAR] * FW for _ in range(FH)]
    for y in range(FH):
        for x in range(FW):
            if tuple(rows[y][x]) in colours:
                out[y][x] = rows[y][x]
    halo = [row[:] for row in out]
    for y in range(FH):
        for x in range(FW):
            if out[y][x][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < FW and 0 <= ny < FH and out[ny][nx][3] and tuple(out[ny][nx][:3]) in [c[:3] for c in h.RAMPS[VGLOW]]:
                        halo[y][x] = (160, 60, 220, 70)
                        break
    return halo


def preview(rows, path, scale=6):
    bg = (58, 110, 70, 255)
    big = [[bg] * (FW * scale) for _ in range(FH * scale)]
    for y in range(FH):
        for x in range(FW):
            c = rows[y][x]
            a = c[3] / 255.0
            col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = col
    write_png(path, FW * scale, FH * scale, big)


if __name__ == "__main__":
    rows = add_shadow(render())
    write_png(ROOT / "props" / "fallen_knight.png", FW, FH, rows)
    write_png(ROOT / "props" / "fallen_knight_glow.png", FW, FH, glow_rows(rows))
    if len(sys.argv) > 1:
        import pathlib
        preview(rows, pathlib.Path(sys.argv[1]))
    print("fallen_knight.png + fallen_knight_glow.png written")
