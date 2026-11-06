"""The standard signpost of this world: a leaning post of the trees' violet-veined wood with weathered arrow boards, overgrown with moss, ivy
and a few glowing buds, standing on a heap of old stones. Same ellipsoid renderer as the knight and the heroine.
    python3 tools/art_signpost.py [preview.png]
Writes assets/props/signpost.png (VARIANTS frames of 56x64 side by side, feet/ground row 58, post at x 28) and signpost_glow.png (only the
emissive pixels, drawn unlit). To add a layout, add a row to VARIANTS: boards = (height, direction -1 left / +1 right, yaw in degrees (+ turns
the tip away from the viewer), length)."""
import math
import sys
import pathlib
import numpy as np
import art_hero3d as h
from gen_art import ROOT, hexc, write_png, CLEAR

FW1, FH = 56, 64
h.FW, h.FH, h.GROUND_ROW = FW1, FH, 58
BASE = len(h.RAMPS)
BARK, BARK_D, PLANK, MOSS, STONE = range(BASE, BASE + 5)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1a1322", "34283c", "55435a", "85697a"],  # post: the trees' bark
    ["0e0914", "1d1428", "33253d", "4d3a54"],  # grooves
    ["2b2128", "4d3d44", "7c6769", "ad9791"],  # weathered boards, a little lighter than the bark
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss and ivy
    ["14121f", "2a2740", "46456a", "6f6f96"],  # old stones
]]
GLOW = (h.TEAL, h.VIOLET)
V = lambda *a: np.array(a, float)

# (board height, direction, yaw, length) per board
VARIANTS = [
    [(37, -1, 10, 17), (29, 1, 4, 17), (21, 1, -26, 15)],  # the crossroad: back the way she came, two ways on
    [(32, 1, -10, 17)],  # a lone waymarker
]


def build(boards, seed):
    rng = np.random.default_rng(seed)
    m = h.Model()
    ell, limb = m.ell, m.limb
    # heap of stones and earth, the post leans a little
    ell(V(0, 1.6, 0), (8.5, 2.2, 6.5), STONE)
    for k in range(7):
        a = k * 0.9 + 0.4
        ell(V(7.0 * math.cos(a), 1.5, 5.0 * math.sin(a)), (rng.uniform(2.0, 3.2), rng.uniform(1.4, 2.2), rng.uniform(1.6, 2.4)), STONE)
    for k in range(6):
        a = k * 1.1
        ell(V(5.5 * math.cos(a), 2.6, 4.2 * math.sin(a)), (rng.uniform(1.6, 2.6), 0.9, rng.uniform(1.2, 2.0)), MOSS)
    top = 47.0
    lean = 0.6

    def post(y):
        return V(lean * y / top + 0.3 * math.sin(y * 0.25), y, 0.0)

    y = 2.0
    while y <= top:
        r = 3.0 - 0.8 * y / top + 0.5 * max(0.0, 1.0 - y / 6.0)
        ell(post(y), (r, 0.9, r * 0.95), BARK)
        y += 0.7
    ell(post(top) + V(0, 0.6, 0), (2.5, 1.0, 2.4), BARK_D)  # the cut top
    ell(post(top) + V(0, 1.4, 0), (2.0, 0.8, 1.9), BARK)
    for ang in (-0.9, 0.2, 1.0, 2.0):  # grooves, one violet vein
        for y0 in (4, 18, 30):
            a, b = post(y0) + V(math.sin(ang) * 2.6, 0, math.cos(ang) * 2.6), post(y0 + 9) + V(math.sin(ang) * 2.2, 0, math.cos(ang) * 2.2)
            limb(a, b, 0.35, 0.3, BARK_D)
    limb(post(5) + V(1.0, 0, 2.7), post(20) + V(1.6, 0, 2.2), 0.4, 0.35, h.VIOLET, kind="emit")
    # roots into the stones
    for sx in (-1, 1):
        limb(post(3) + V(sx * 1.5, 0, 0), V(sx * 6.5, 1.2, 1.5), 1.6, 0.6, BARK)

    # the boards: weathered planks with a pointed end, nailed to the post
    for height, d, yaw, length in boards:
        a = math.radians(yaw)
        R = h.rot_y(a)
        base = post(height)
        sagging = 0.04 * rng.uniform(-1, 1)
        n = int(length / 0.9)
        for i in range(n + 1):
            t = i / n
            x = d * (1.0 + t * length)
            half = 2.4 if t < 0.7 else 2.4 * max(0.05, 1.0 - (t - 0.7) / 0.3)  # the arrow tip
            c = base + R @ V(x, -sagging * x * x * 0.1 * d, 3.2)
            ell(c, (0.85, half, 0.8), PLANK, R=R)
        tip = base + R @ V(d * (length + 1.0), 0, 3.2)
        # carved arrow and a rusty nail
        limb(base + R @ V(d * length * 0.22, 0, 4.0), base + R @ V(d * length * 0.8, 0, 4.0), 0.4, 0.4, BARK_D)
        limb(base + R @ V(d * length * 0.62, 1.3, 4.0), base + R @ V(d * length * 0.82, 0.0, 4.0), 0.38, 0.36, BARK_D)
        limb(base + R @ V(d * length * 0.62, -1.3, 4.0), base + R @ V(d * length * 0.82, 0.0, 4.0), 0.38, 0.36, BARK_D)
        ell(base + R @ V(d * 3.0, 0.6, 3.9), (0.4, 0.4, 0.3), h.LEATHER)
        ell(base + R @ V(d * 3.0, -0.8, 3.9), (0.4, 0.4, 0.3), h.LEATHER)
        # moss on the top edge, a vine hanging from the end
        ell(base + R @ V(d * length * rng.uniform(0.2, 0.5), 2.1, 3.0), (3.0, 0.9, 1.4), MOSS, R=R)
        limb(tip + R @ V(-d * 3, -1.5, 0), tip + R @ V(-d * 3.4, -5.0, 0), 0.4, 0.22, MOSS)
    # ivy winding up the post with leaves and a few glowing buds
    pts = [post(y) + V(3.2 * math.sin(y * 0.55), 0, 3.2 * math.cos(y * 0.55) * 0.9) for y in np.arange(2.0, 33.0, 1.3)]
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        limb(a, b, 0.45, 0.4, MOSS)
        if i % 2 == 0:
            ell(b + V(0.4 * (-1) ** i, 0.2, 0.9), (1.1, 0.35, 0.8), MOSS, R=h.rot_x(0.5))
    for i in (3, 8, 13):
        ell(pts[i] + V(0.5, 0.4, 1.2), (0.55, 0.55, 0.55), h.TEAL, kind="emit")
    # tufts of grass at the foot
    for k in range(5):
        x0 = rng.uniform(-8, 8)
        z0 = rng.uniform(2.5, 7)
        limb(V(x0, 2.5, z0), V(x0 + rng.uniform(-1, 1), 6.0 + rng.uniform(0, 2), z0), 0.5, 0.2, MOSS)
    return m


def render(m):
    depth, code = h.render(m.transform(0.0, 0.0))
    return h.to_pixels(depth, code)


def shadow(rows):
    for y in range(FH):
        for x in range(FW1):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW1 / 2) / 17.0, (y + 0.5 - 58) / 3.4
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 70)
    return rows


def glow(rows):
    cols = {tuple(c) for mat in GLOW for b, c in enumerate(h.RAMPS[mat]) if mat != h.VIOLET or b >= 1}
    return [[c if tuple(c) in cols else CLEAR for c in row] for row in rows]


if __name__ == "__main__":
    frames = [shadow(render(build(b, 5 + i))) for i, b in enumerate(VARIANTS)]
    W = FW1 * len(frames)
    sheet = [sum((f[y] for f in frames), []) for y in range(FH)]
    write_png(ROOT / "props" / "signpost.png", W, FH, sheet)
    write_png(ROOT / "props" / "signpost_glow.png", W, FH, glow(sheet))
    if len(sys.argv) > 1:
        bg, sc = (58, 110, 70, 255), 8
        big = []
        for row in sheet:
            line = []
            for c in row:
                a = c[3] / 255.0
                col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
                line += [col] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), W * sc, FH * sc, big)
    print("signpost.png + signpost_glow.png written")
