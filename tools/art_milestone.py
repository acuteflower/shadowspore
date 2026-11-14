"""The milestones of the Westweg (docs/stadt_westen_konzept.md 2.4): squat stelae of the blue-violet stone of the Glaskamm with a rounded head,
the distance to Hallgrat chiselled into the face and a small crystal set into the crown, the first sign of the town's guide stones (Leitsteine).
Far from the town they are old, leaning, mossy and chipped and their crystal is a dead grey stump; the nearer they stand, the cleaner they are
cut and the more their crystal remembers its light: a violet glint from 150 on, and the last one (50) flickers teal at night.
Same ellipsoid renderer as the signpost and the heroine.
    py -3 tools/art_milestone.py [preview.png]
Writes assets/props/milestone.png (one frame of 40x52 per number of NUMBERS, ground row 46, stone centred at x 20) and milestone_glow.png
(only the crystal's emissive pixels, drawn unlit). `Milestone.FRAMES` must match NUMBERS."""
import math
import sys
import pathlib
import numpy as np
import art_hero3d as h
from gen_art import ROOT, hexc, write_png, CLEAR

FW1, FH, GROUND = 40, 52, 46
h.FW, h.FH, h.GROUND_ROW = FW1, FH, GROUND
NUMBERS = list(range(50, 851, 50))
BASE = len(h.RAMPS)
STONE, STONE_D, MOSS, LICHEN, DEAD = range(BASE, BASE + 5)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1c1a34", "2e2a52", "47436f", "8a83b8"],  # the Glaskamm's stone (art_stone.py STONE: shade .. light)
    ["120f22", "1c1a34", "2e2a52", "47436f"],  # chisel grooves, cracks, the shaded plinth
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss
    ["4a5a3a", "6e7a4c", "98a066", "c4c890"],  # pale lichen
    ["2a2538", "433c56", "625a78", "8a83a0"],  # a dead crystal: grey violet, no light
]]
V = lambda *a: np.array(a, float)
DIGITS = {  # 3 x 5 chisel font
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"], "2": ["##.", "..#", ".#.", "#..", "###"],
    "3": ["##.", "..#", ".#.", "..#", "##."], "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."], "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "##."],
}


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def age_of(n):
    """0 = kept up (by the town), 1 = forgotten for a long time."""
    return min(1.0, max(0.0, (n - 100) / 400.0))


def build(n, seed):
    rng = np.random.default_rng(seed)
    age = age_of(n)
    m = h.Model()
    lean = rot_z(math.radians(rng.uniform(4, 9) * age * (1 if seed % 2 else -1)))  # old stones have settled to one side

    def ell(c, r, mat, kind=""):
        m.ell(lean @ c, r, mat, R=lean, kind=kind)

    # plinth: two worn steps, half sunk in the ground
    ell(V(0, 1.0, 0), (9.0, 1.6, 6.2), STONE_D)
    ell(V(0, 2.4, 0), (7.6, 1.4, 5.0), STONE)
    # the stele: a squat block with soft corners, the face towards the road (the viewer), a rounded head
    height = 23.0
    y = 3.0
    while y <= height:
        w = 7.6 - 0.22 * max(0.0, y - 15.0) * (1.0 - 0.3 * age)
        m_ = STONE
        ell(V(0, y, 0), (w, 0.75, 3.4), m_)
        ell(V(-w * 0.55, y, 0.6), (w * 0.5, 0.75, 3.2), m_)  # flatter face: the front is squarer than an ellipse
        ell(V(w * 0.55, y, 0.6), (w * 0.5, 0.75, 3.2), m_)
        y += 0.6
    ell(V(0, height + 1.2, 0.2), (6.4, 3.0, 3.2), STONE)  # the rounded head
    # the crystal in its socket on the crown: dead and grey far out, violet nearer, teal and alive at the last stone
    ell(V(0, height + 3.8, 0.4), (2.4, 1.0, 2.0), STONE_D)
    if n <= 50:
        ell(V(0, height + 5.0, 0.4), (1.3, 2.4, 1.2), h.TEAL, kind="emit")
        ell(V(0.5, height + 5.8, 0.8), (0.5, 0.9, 0.5), h.TEAL, kind="emit")
    elif n <= 150:
        ell(V(0, height + 4.8, 0.4), (1.2, 2.0, 1.1), h.CRYSTAL, kind="emit")
    else:
        stump = 1.6 - 0.9 * age
        ell(V(0, height + 4.2 + stump * 0.5, 0.4), (1.1, stump, 1.0), DEAD)
    # weather: chips off the head, moss on the plinth and the top, lichen spots, a crack
    if age > 0.3:
        ell(V(5.2, height + 0.8, 1.6), (1.7, 1.5, 1.2), STONE_D)  # the broken corner shows darker stone
    for k in range(int(2 + 7 * age)):
        a = rng.uniform(0, math.tau)
        ell(V(7.2 * math.cos(a), 2.6, 4.6 * math.sin(a)), (rng.uniform(1.4, 2.6), 0.9, rng.uniform(1.0, 1.8)), MOSS)
    for k in range(int(4 * age)):
        ell(V(rng.uniform(-3, 3), height + 2.8, rng.uniform(-1.5, 1.5)), (rng.uniform(1.2, 2.2), 0.7, 1.2), MOSS)
    for k in range(int(1 + 4 * age)):
        ell(V(rng.uniform(-5, 5), rng.uniform(6, height - 1), 3.0), (rng.uniform(0.7, 1.3), rng.uniform(0.6, 1.1), 0.6), LICHEN)
    # grass at the foot
    for k in range(int(4 + 4 * age)):
        x0, z0 = rng.uniform(-9, 9), rng.uniform(2, 6)
        m.limb(V(x0, 1.5, z0), V(x0 + rng.uniform(-1, 1), 4.5 + rng.uniform(0, 3) * (0.5 + age), z0), 0.5, 0.2, MOSS)
    return m


def carve(rows, n, seed):
    """The number chiselled into the face: dark grooves with a lit lower lip, the strokes a little uneven on the old stones."""
    rng = np.random.default_rng(seed + 99)
    age = age_of(n)
    groove, lip = h.RAMPS[STONE_D][0], h.RAMPS[STONE][3]
    text = str(n)
    width = len(text) * 4 - 1
    # the face: the first row (from the top) where the stele is at least 11 px wide; the number sits a little below it
    top = left = None
    for y in range(GROUND):
        xs = [x for x in range(FW1) if rows[y][x][3] == 255]
        if len(xs) >= 11:
            top, left = y + 5, (xs[0] + xs[-1] + 1) // 2 - width // 2
            break
    for i, ch in enumerate(text):
        for r, line in enumerate(DIGITS[ch]):
            for c, cell in enumerate(line):
                if cell != "#":
                    continue
                if age > 0.5 and rng.random() < 0.18 * age:  # worn away
                    continue
                x, y = left + i * 4 + c, top + r
                if rows[y][x][3] > 0:
                    rows[y][x] = tuple(groove[:3]) + (255,)
                    if r == 4 or line[c] == "#" and r + 1 < 5 and DIGITS[ch][r + 1][c] != "#":
                        if rows[y + 1][x][3] > 0 and tuple(rows[y + 1][x][:3]) != tuple(groove[:3]):
                            rows[y + 1][x] = tuple(lip[:3]) + (255,)
    # a cut line above and below the number on the cared-for stones
    if age < 0.3:
        for x in range(left - 1, left + width + 1):
            for y in (top - 2, top + 6):
                if rows[y][x][3] > 0:
                    rows[y][x] = tuple(h.RAMPS[STONE][1][:3]) + (255,)
    return rows


def render(m):
    depth, code = h.render(m.transform(0.0, 0.0))
    return h.to_pixels(depth, code)


def shadow(rows):
    for y in range(FH):
        for x in range(FW1):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW1 / 2) / 14.0, (y + 0.5 - GROUND) / 3.0
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 70)
    return rows


def glow(rows):
    cols = {tuple(c) for mat in (h.TEAL, h.CRYSTAL) for c in h.RAMPS[mat]}
    return [[c if tuple(c[:3]) in {k[:3] for k in cols} and c[3] > 0 else CLEAR for c in row] for row in rows]


if __name__ == "__main__":
    frames = []
    for i, n in enumerate(NUMBERS):
        rows = [list(r) for r in render(build(n, 11 + i * 7))]
        frames.append(shadow(carve(rows, n, 11 + i * 7)))
    W = FW1 * len(frames)
    sheet = [sum((list(f[y]) for f in frames), []) for y in range(FH)]
    write_png(ROOT / "props" / "milestone.png", W, FH, sheet)
    write_png(ROOT / "props" / "milestone_glow.png", W, FH, glow(sheet))
    if len(sys.argv) > 1:
        bg, sc = (58, 110, 70, 255), 6
        big = []
        for row in sheet:
            line = []
            for c in row:
                a = c[3] / 255.0
                col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
                line += [col] * sc
            big += [line] * sc
        write_png(pathlib.Path(sys.argv[1]), W * sc, FH * sc, big)
    print("milestone.png + milestone_glow.png written: %d frames (%s)" % (len(frames), ", ".join(map(str, NUMBERS))))
