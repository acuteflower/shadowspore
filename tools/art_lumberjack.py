"""The dead lumberjack in his cabin: sat on the floor against the back wall, head sunk, one hand open in his lap, in a faded wool shirt, a leather vest, braces, heavy boots and a
cap, the void eating him (black flesh on the right arm and shoulder creeping up the neck, glowing magenta veins, a pool on the floor with tendrils and small blooms): the same fate as
the knight under the fallen tree, made the same way (ellipsoids, `art_hero3d` renderer). His axe lies beside him as its own sprite (the game takes it away when you search him).
    python3 tools/art_lumberjack.py [preview.png]
Writes assets/interior/cabin/lumberjack.png (64 x 64, ground row 54) + lumberjack_glow.png (only the emissive pixels, drawn unlit) + lumberjack_axe.png (40 x 24, ground row 16)."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

BASE = len(h.RAMPS)
SHIRT, VEST, TROUSERS, SKIN_D, BEARD, WOODA, IRONA, VOID, VGLOW, BOOT_D = range(BASE, BASE + 10)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["18241c", "27402e", "3f6246", "6b8d68"],  # faded green wool
    ["1a1018", "33202a", "52333a", "7a5650"],  # leather vest
    ["1a1626", "2f2a42", "4a4562", "6f6a88"],  # grey-brown trousers
    ["2a2230", "52485a", "857a88", "b5aab0"],  # grey, waxy skin
    ["4a4654", "7b7686", "aaa5b4", "d6d2dc"],  # grey beard
    ["2a1c22", "4c3433", "7a5a52", "ad8a7e"],  # wood
    ["0f0e1a", "211f36", "3c3a5c", "7d7ca8"],  # iron
    ["040208", "0a0612", "170d28", "2c1d4c"],  # void flesh
    ["5a1c8c", "a02fd0", "e45cf0", "ffc8ff"],  # void glow: the standard magenta of every shadow creature
    ["0e0914", "1d1428", "33253d", "4d3a54"],  # boots
]]
GLOW_MATS = (VGLOW, h.TEAL, h.VIOLET)
V = lambda *a: np.array(a, float)
rng = np.random.default_rng(23)
FW, FH, GROUND = 64, 64, 54


def build():
    h.FW, h.FH, h.GROUND_ROW = FW, FH, GROUND
    m = h.Model()
    ell, limb, ribbon = m.ell, m.limb, m.ribbon
    P = V(0.0, 4.2, 0.0)  # pelvis: sat on the floor
    LEAN = -0.16  # leaning back against the wall
    ROT = h.rot_x(LEAN)

    def Tl(p):
        return P + ROT @ (np.array(p, float) - V(0.0, 24.5, 0.0))

    # trousers and the belt
    ell(P, (4.4, 3.5, 3.4), TROUSERS)
    ell(Tl((0, 26.4, 0)), (4.0, 0.9, 3.5), h.LEATHER, R=ROT)
    ell(Tl((0, 26.4, 3.2)), (1.1, 0.8, 0.5), h.GOLD, kind="emit")
    # shirt, vest, braces
    ell(Tl((0, 30.4, 0)), (3.5, 3.6, 2.8), SHIRT, R=ROT)
    ell(Tl((0, 35.0, 0)), (4.3, 4.6, 3.3), SHIRT, R=ROT)
    ell(Tl((0, 34.4, 0.7)), (4.5, 4.3, 3.3), VEST, R=ROT)
    ell(Tl((0, 34.4, 4.0)), (0.5, 4.0, 0.5), SHIRT, R=ROT)  # the open front
    for sx in (-1.9, 1.9):
        ell(Tl((sx, 34.0, 3.6)), (0.8, 5.4, 0.6), h.LEATHER, R=ROT)  # braces
    # legs stretched out towards us (the left one a little bent), heavy boots
    for side, (spread, bend) in ((1, (0.12, 0.0)), (-1, (-0.3, 0.45))):
        hip = P + V(side * 2.6, -0.4, 0.4)
        thigh_end = hip + V(math.sin(spread) * 11.0, 0.8 + bend * 4.0, 11.0)
        ankle = thigh_end + V(math.sin(spread) * 9.0, -0.6 - bend * 1.0, 9.0 * (1.0 - bend * 0.35))
        limb(hip, thigh_end, 2.9, 2.6, TROUSERS)
        limb(thigh_end, ankle, 2.5, 2.1, TROUSERS)
        ell(thigh_end + V(0, 1.2, 0.4), (2.7, 2.0, 2.5), TROUSERS)  # the knee
        ell(ankle + V(0, 0.3, 1.8), (2.5, 2.4, 3.7), BOOT_D)
        ell(ankle + V(0, -0.8, 3.0), (2.7, 1.4, 3.2), h.LEATHER)  # the sole
        for k in range(3):
            ell(ankle + V(0, 2.3 - k * 1.4, 0.8), (2.6, 0.35, 2.4), h.LEATHER)  # boot laces
    # arms: the right (his left in front of us... the viewer's left) hangs to the floor; the other rests open on his thigh
    S_R, S_L = Tl((4.7, 38.0, 0.0)), Tl((-4.7, 38.0, 0.0))
    ell(S_R, (2.1, 2.1, 2.1), SHIRT)
    ell(S_L, (2.1, 2.1, 2.1), SHIRT)
    el, wr = h.ik2(S_R, P + V(7.6, 0.8, 8.4), 6.6, 6.0, V(1, -0.4, -0.4))
    limb(S_R, el, 1.8, 1.6, SHIRT)
    limb(el, wr, 1.7, 1.4, SHIRT)
    ell(wr + (wr - el) / np.linalg.norm(wr - el) * 1.1, (1.5, 1.0, 1.7), SKIN_D)  # a limp hand on the floor
    el2, wr2 = h.ik2(S_L, P + V(-8.6, 3.4, 9.0), 6.6, 6.0, V(-1, -0.5, -0.2))
    limb(S_L, el2, 1.8, 1.6, SHIRT)
    limb(el2, wr2, 1.7, 1.4, SHIRT)
    ell(wr2 + V(-0.4, 0.5, 0.9), (1.6, 0.8, 1.7), SKIN_D)  # the hand lies open on his thigh
    for k in range(4):  # fingers
        ell(wr2 + V(-1.1 + k * 0.6, 0.6, 2.2), (0.3, 0.3, 0.9), SKIN_D)
    # head: sunk onto the chest, tilted, a beard, a wool cap, closed eyes, the skin grey
    hc = Tl((0.4, 44.4, 1.8))
    RH = h.rot_x(0.4) @ h.rot_y(0.18)
    ell(hc, (4.2, 4.9, 4.5), SKIN_D, R=RH)
    ell(hc + RH @ V(0, -2.6, 2.2), (3.9, 3.4, 3.5), BEARD, R=RH)  # the beard
    for k in range(5):
        ell(hc + RH @ V(-2.2 + k * 1.1, -5.4 - 0.3 * (k % 2), 2.4), (0.8, 2.0, 0.8), BEARD, R=RH)
    ell(hc + RH @ V(0, 2.4, 2.0), (3.6, 1.0, 2.8), BEARD, R=RH)  # a brow of white hair
    for sx in (-1.5, 1.5):
        ell(hc + RH @ V(sx, 1.1, 4.1), (0.9, 0.18, 0.3), TROUSERS, R=RH)  # shut eyes
    ell(hc + RH @ V(0, -0.4, 4.5), (0.6, 1.0, 0.6), SKIN_D, R=RH)  # the nose
    ell(hc + RH @ V(0, 3.6, 0.4), (4.9, 2.6, 4.9), SHIRT, R=RH)  # the cap
    ell(hc + RH @ V(0, 3.0, 3.0), (4.9, 0.8, 2.2), TROUSERS, R=RH)  # its brim
    ribbon([hc + RH @ V(3.6, 4.0, 0.5), hc + RH @ V(5.0, 2.5, -2.5), hc + RH @ V(5.4, 0.0, -4.5)], [1.1, 1.0, 0.5], 0.4, SHIRT, (1, 0, 0), tag=3.0)  # a cap tail
    # a rope round his waist with a few tools: a whetstone and a coil
    for k in range(7):
        a = -1.4 + k * 0.45
        ell(Tl((4.6 * math.sin(a), 24.4, 3.6 * math.cos(a))), (0.9, 0.9, 0.9), WOODA)
    ell(Tl((-5.5, 24.0, 1.0)), (1.1, 2.4, 1.1), h.LEATHER)
    # the void takes him: black flesh from the right shoulder down the arm and up the neck, glowing veins
    for c, r in ((S_R + V(0.8, 0.8, 0.8), (2.6, 1.6, 2.4)), (Tl((3.4, 40.0, 1.6)), (2.0, 1.2, 1.9)), (Tl((2.4, 41.6, 2.6)), (1.5, 1.0, 1.4))):
        ell(c, r, VOID)
    ell(el + V(0.4, 0.4, 0.8), (1.9, 1.5, 1.9), VOID)
    limb(el, wr, 1.75, 1.5, VOID)
    ell(wr + (wr - el) / np.linalg.norm(wr - el) * 1.1, (1.6, 1.1, 1.8), VOID)
    for a, b in ((S_R + V(1.2, 1.2, 2.0), Tl((3.0, 41.5, 3.0))), (S_R + V(0.9, -0.5, 2.2), el + V(0.6, 0.4, 1.8)), (el + V(0.5, 0.2, 1.8), wr + V(0.4, 0.6, 1.4))):
        limb(a, b, 0.42, 0.36, VGLOW, kind="emit")
    for ang in (0.5, 1.6, 2.6):  # veins across the chest from a hole in the vest
        p = Tl((2.4, 33.0, 4.2))
        for i in range(6):
            q = p + V(math.cos(ang + 0.3 * i) * 1.1, math.sin(ang + 0.3 * i) * 1.1, 0.1)
            limb(p, q, 0.34, 0.3, VGLOW, kind="emit")
            p = q
    ell(Tl((2.4, 33.0, 4.0)), (1.5, 1.8, 0.9), VOID, R=ROT)
    # the pool on the floor, tendrils creeping, small blooms
    for c, r in (((6.0, 0.35, 10.0), (11.0, 0.5, 5.5)), ((-3.0, 0.35, 13.0), (9.0, 0.5, 4.6)), ((12.0, 0.3, 4.0), (7.0, 0.45, 3.4)), ((1.0, 0.3, 4.0), (6.0, 0.5, 3.0))):
        ell(V(*c), r, VOID)

    def tendril(p0, p1, r0=1.0, r1=0.3):
        p0, p1 = np.array(p0, float), np.array(p1, float)
        n = max(4, int(np.linalg.norm(p1 - p0) / 2.4))
        pts = [p0 + (p1 - p0) * (i / n) + V(rng.normal(0, 1.4), 0.0, rng.normal(0, 1.4)) * math.sin(math.pi * i / n) * 0.8 for i in range(n + 1)]
        for i, (a, b) in enumerate(zip(pts, pts[1:])):
            t = i / n
            limb(a, b, r0 + (r1 - r0) * t, r0 + (r1 - r0) * (t + 1.0 / n), VOID)
            if i % 3 == 1:
                ell(b + V(0, 0.7, 0), (0.6, 0.6, 0.6), VGLOW, kind="emit")

    tendril(V(8.0, 0.8, 8.0), V(28.0, 0.9, 15.0))
    tendril(V(-6.0, 0.8, 10.0), V(-24.0, 0.9, 8.0), 0.9, 0.3)
    tendril(V(2.0, 0.8, 12.0), V(6.0, 0.9, 25.0), 0.9, 0.3)
    for bx, bz in ((13.0, 12.0), (-9.0, 14.0), (18.0, 7.0)):
        top = V(bx, 3.6 + rng.uniform(0, 1.2), bz)
        limb(V(bx, 0.5, bz), top, 0.45, 0.3, VOID)
        ell(top + V(0, 0.4, 0), (0.95, 0.75, 0.95), VGLOW, kind="emit")
    return m


def render(m):
    h.FW, h.FH, h.GROUND_ROW = FW, FH, GROUND
    depth, code = h.render(m.transform(0.0, 0.0))
    return h.to_pixels(depth, code)


def shadow(rows):
    cx, cy = FW / 2, GROUND - 5
    for y in range(FH):
        for x in range(FW):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - cx) / 26.0, (y + 0.5 - cy) / 7.0
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 70)
    return rows


def glow(rows):
    colours = set()
    for mat in GLOW_MATS:
        for b, c in enumerate(h.RAMPS[mat]):
            if mat != h.VIOLET or b >= 1:
                colours.add(tuple(c))
    out = [[CLEAR] * FW for _ in range(FH)]
    for y in range(FH):
        for x in range(FW):
            if tuple(rows[y][x]) in colours:
                out[y][x] = rows[y][x]
    halo = [row[:] for row in out]
    pink = {tuple(c[:3]) for c in h.RAMPS[VGLOW]}
    for y in range(FH):
        for x in range(FW):
            if out[y][x][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < FW and 0 <= ny < FH and out[ny][nx][3] and tuple(out[ny][nx][:3]) in pink:
                        halo[y][x] = (160, 60, 220, 70)
                        break
    return halo


def axe_rows():
    """The axe lies on the floor: a long ash haft, a rusty broad head, the edge pointing away; 40 x 24, ground row 16."""
    h.FW, h.FH, h.GROUND_ROW = 40, 24, 16
    m = h.Model()
    ax = np.array([1.0, 0.0, 0.35])
    ax /= np.linalg.norm(ax)
    a, b = V(-17, 1.6, -3.0), V(14, 1.6, 4.0)
    n = 24
    for i in range(n + 1):
        t = i / n
        m.ell(a + (b - a) * t, (1.15, 1.3, 1.15), WOODA)
    head = b + V(0.8, 0.4, 0.2)
    m.ell(head, (2.3, 2.6, 2.1), IRONA)
    m.ell(head + V(0, 0, 3.0), (1.6, 3.4, 0.9), IRONA)
    m.ell(head + V(0, 0, 4.6), (0.5, 3.6, 0.6), h.GOLD)  # the dull edge
    m.ell(a + V(-0.4, 0.2, -0.2), (1.4, 1.5, 1.4), h.LEATHER)  # a wrapped grip
    for k in range(3):
        m.ell(a + (b - a) * (0.06 + 0.04 * k), (1.35, 1.55, 1.35), h.LEATHER)
    for k in range(3):  # moss and rust
        m.ell(head + V(-1 + k, 2.2, 1), (1.1, 0.4, 0.8), VGLOW if False else h.TEAL, kind="emit") if k == 1 else m.ell(head + V(-1 + k, 2.2, 1), (1.1, 0.4, 0.8), WOODA)
    depth, code = h.render(m.transform(0.0, 0.0))
    return h.to_pixels(depth, code)


def preview(rows, path, scale=6):
    bg = (88, 72, 80, 255)
    w, hh = len(rows[0]), len(rows)
    big = [[bg] * (w * scale) for _ in range(hh * scale)]
    for y in range(hh):
        for x in range(w):
            c = rows[y][x]
            a = c[3] / 255.0
            col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = col
    write_png(path, w * scale, hh * scale, big)


if __name__ == "__main__":
    rows = shadow(render(build()))
    out = ROOT / "interior" / "cabin"
    out.mkdir(parents=True, exist_ok=True)
    write_png(out / "lumberjack.png", FW, FH, rows)
    write_png(out / "lumberjack_glow.png", FW, FH, glow(rows))
    axe = axe_rows()
    write_png(out / "lumberjack_axe.png", 40, 24, axe)
    if len(sys.argv) > 1:
        preview(rows, Path(sys.argv[1]))
    print("lumberjack written")
