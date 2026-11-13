#!/usr/bin/env python3
"""The town's heart, the fountain square (docs/brunnenplatz.md), first and modest stage: a round square of cobbles laid in rings round a low stone fountain.

Writes assets/town/:
  plaza.png             the floor (208x136): cobbles in rings (Voronoi stones on ring seeds, flattened for the 3/4 view), dark joints, moss creeping into the
                        outer joints, stones missing at the ragged rim so the meadow breaks in, three little flower tufts. Fountain centre at (104, 70).
  plaza_fountain.png    the fountain, 4 frames of 56x48 side by side (water ripples, a trickle down the column), feet = basin bottom centre at (28, 41).
  plaza_fountain_glow.png  only the water's light (unlit, soft teal at night).
  plaza_preview.png     floor + fountain (frame 0) for the build menu.
Light from the upper left, palette of the town's stone (art_town STONE_L) and the meadow. Deterministic. `python3 tools/art_plaza.py [contact.png]`
"""
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / "assets" / "town"
rng = np.random.default_rng(31)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float64)


STONES = [[hexc(c) for c in row] for row in (
    ("36345a", "58577f", "8584ac", "b4b3d4"),  # the town's light stone
    ("322f50", "4f4c74", "77739e", "a5a2c8"),  # a cooler one
    ("3a3352", "5c5274", "877c9c", "b3a8c4"),  # a warmer, plum one
)]
JOINT = hexc("221d34")
JOINT_D = hexc("16122a")
MOSS = [hexc("2e5a3e"), hexc("4f8a4a"), hexc("86c06a")]
INK = hexc("1b1a2e")
WATER = [hexc("143846"), hexc("1f5a68"), hexc("2f8a90"), hexc("6fd3cf"), hexc("d8fff6")]
PETALS = [hexc("f2a0c8"), hexc("b89ae6"), hexc("eef0ff"), hexc("ffd27a")]

W, H = 208, 136
CX, CY = 104.0, 70.0
RX, RY = 98.0, 60.0
FLAT = RY / RX


def hsh(*k):
    v = 0
    for x in k:
        v = (v * 1103515245 + int(x) * 2654435761 + 12345) & 0xFFFFFFFF
    v ^= v >> 13
    v = (v * 0x5bd1e995) & 0xFFFFFFFF
    return ((v ^ (v >> 15)) & 0xFFFFFF) / float(0xFFFFFF)


def bayer(x, y):
    m = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    return m[y % 4][x % 4] / 16.0


# ------------------------------------------------------------------ the floor
def seeds():
    """Cobble centres on rings round the fountain: about one stone every 7 px along each ring, rings 6.5 px apart (in the unflattened plane)."""
    out = []
    r = 13.0
    k = 0
    while r < RX + 6:
        n = max(6, int(2 * np.pi * r / 7.0))
        off = hsh(k, 3) * 2 * np.pi
        for i in range(n):
            a = off + 2 * np.pi * (i + (hsh(k, i, 1) - 0.5) * 0.35) / n
            rr = r + (hsh(k, i, 2) - 0.5) * 1.6
            out.append((CX + np.cos(a) * rr, CY + np.sin(a) * rr * FLAT, k, i))
        r += 6.5
        k += 1
    return out


def floor():
    arr = np.zeros((H, W, 4), np.uint8)
    pts = seeds()
    sx = np.array([p[0] for p in pts])
    sy = np.array([p[1] for p in pts])
    ys, xs = np.mgrid[0:H, 0:W]
    px = xs + 0.5
    py = ys + 0.5
    dx = px[..., None] - sx[None, None, :]
    dy = (py[..., None] - sy[None, None, :]) / FLAT  # the stones lie flat: distances in the ground plane
    d = np.sqrt(dx * dx + dy * dy)
    order = np.argsort(d, axis=2)[..., :2]
    near = np.take_along_axis(d, order, axis=2)
    owner = order[..., 0]
    border = (near[..., 1] - near[..., 0]) * 0.5  # distance to the joint, ground units
    rn = np.sqrt(((px - CX) / RX) ** 2 + ((py - CY) / RY) ** 2)
    for y in range(H):
        for x in range(W):
            r = rn[y, x]
            wob = (hsh(x // 3, y // 3, 7) - 0.5) * 0.06
            if r + wob > 1.0:
                continue
            o = owner[y, x]
            k, i = pts[o][2], pts[o][3]
            outer = max(0.0, (r - 0.78) / 0.22)
            missing = hsh(k, i, 9) < outer * 0.55  # stones lost at the rim: the meadow comes through
            if missing:
                if hsh(x, y, 4) < 0.12 * (1 - outer) + 0.05:
                    arr[y, x] = (*MOSS[0].astype(np.uint8), 255)
                continue
            b = border[y, x]
            if b < 0.5:  # the joint
                col = JOINT_D if b < 0.2 else JOINT
                if hsh(x, y, 11) < 0.15 + outer * 0.7:
                    col = MOSS[0] if hsh(x, y, 12) < 0.6 else MOSS[1]
                if r + wob > 0.94 and bayer(x, y) < (r + wob - 0.94) * 14:
                    continue  # the ragged edge dithers into the meadow
                arr[y, x] = (*col.astype(np.uint8), 255)
                continue
            ramp = STONES[int(hsh(k, i, 5) * 3) % 3]
            ndx = (px[y, x] - pts[o][0])
            ndy = (py[y, x] - pts[o][1]) / FLAT
            ln = max(np.hypot(ndx, ndy), 0.001)
            facing = (-ndx * 0.6 - ndy * 0.8) / ln  # +1 = towards the light (upper left)
            edge = 1.0 - min(b / 2.6, 1.0)  # stronger near the joint: the stones are domed
            light = facing * edge * 1.3 + (hsh(k, i, 6) - 0.5) * 0.5 + (hsh(x, y, 13) - 0.5) * 0.2 - outer * 0.3 + 0.3
            tone = 3 if light > 0.55 else 2 if light > -0.4 else 1 if light > -1.0 else 0
            if hsh(k, i, 8) < 0.05:
                tone = max(tone - 1, 0)  # an old dark stone here and there
            arr[y, x] = (*ramp[tone].astype(np.uint8), 255)
            if outer > 0.2 and hsh(x, y, 14) < outer * 0.12 and edge > 0.5:
                arr[y, x, :3] = MOSS[1 + (hsh(x, y, 15) > 0.6)].astype(np.uint8)
    for k_t, (ang, size) in enumerate(((2.55, 8), (0.55, 7), (1.9, 6), (4.3, 5), (3.4, 6), (5.6, 5))):  # flower tufts at the rim
        bx = CX + np.cos(ang) * RX * 0.9
        by = CY + np.sin(ang) * RY * 0.9
        for j in range(size * 4):
            x = int(bx + (hsh(k_t, j, 1) - 0.5) * size * 2)
            y = int(by + (hsh(k_t, j, 2) - 0.5) * size * 1.2)
            if 0 <= x < W and 1 <= y < H:
                arr[y, x] = (*MOSS[1 + (j % 3 == 0)].astype(np.uint8), 255)
                if j % 2 == 0:
                    arr[y - 1, x] = (*MOSS[2].astype(np.uint8), 255)
        for j in range(size):
            x = int(bx + (hsh(k_t, j, 3) - 0.5) * size * 1.8)
            y = int(by - 1 + (hsh(k_t, j, 4) - 0.5) * size)
            if 0 <= x < W and 0 <= y < H:
                arr[y, x] = (*PETALS[(k_t + j) % 4].astype(np.uint8), 255)
    return arr


# ------------------------------------------------------------------ the fountain
FW, FH = 56, 48
BX, BY = 28.0, 30.0  # the basin rim's centre
ORX, ORY = 22.0, 11.0  # outer rim
IRX, IRY = 17.0, 8.0  # inner rim (the water)
WALL = 7  # the front wall's height
FOOT = (28, 41)


def fountain(frame):
    arr = np.zeros((FH, FW, 4), np.uint8)
    glow = np.zeros((FH, FW, 4), np.uint8)

    def put(x, y, col, a=255):
        if 0 <= x < FW and 0 <= y < FH:
            arr[y, x] = (*np.clip(col, 0, 255).astype(np.uint8), a)

    def shine(x, y, col, a):
        if 0 <= x < FW and 0 <= y < FH:
            glow[y, x] = (*col.astype(np.uint8), a)

    stone = [hexc(c) for c in ("4a4870", "7a78a6", "aaa8cc", "d6d4ec")]  # the fountain's dressed stone, lighter than the cobbles
    # contact shadow on the cobbles
    for y in range(FH):
        for x in range(FW):
            e = ((x + 0.5 - BX) / (ORX + 3)) ** 2 + ((y + 0.5 - (BY + WALL + 1)) / (ORY * 0.7)) ** 2
            if e < 1.0 and bayer(x, y) < 0.75 - e * 0.5:
                put(x, y, INK, 110)
    # front wall: below the outer rim's lower half
    for x in range(FW):
        t = (x + 0.5 - BX) / ORX
        if abs(t) >= 1.0:
            continue
        rim = BY + ORY * np.sqrt(1 - t * t)
        for yy in range(WALL):
            y = int(rim) + yy
            block = int((np.arcsin(max(-1, min(1, t))) + 2) * 6) + (yy // 4) * 3
            light = -t * 0.9 + (hsh(block, 3) - 0.5) * 0.5 - yy * 0.06
            tone = 2 if light > 0.3 else 1 if light > -0.5 else 0
            col = stone[tone]
            if yy == 0:
                col = stone[min(tone + 1, 3)]
            if yy == WALL - 1 or abs((np.arcsin(max(-1, min(1, t))) + 2) * 6 - round((np.arcsin(max(-1, min(1, t))) + 2) * 6)) < 0.12 and yy > 0:
                col = JOINT
            if yy == 3 and hsh(block, 4) < 0.5:
                col = JOINT
            if yy >= WALL - 3 and hsh(x, yy, 5) < 0.3:
                col = MOSS[0] if hsh(x, yy, 6) < 0.6 else MOSS[1]
            put(x, y, col)
        put(x, int(rim) + WALL, INK)
    # the rim ring on top and the water inside
    for y in range(FH):
        for x in range(FW):
            ox = (x + 0.5 - BX) / ORX
            oy = (y + 0.5 - BY) / ORY
            ix = (x + 0.5 - BX) / IRX
            iy = (y + 0.5 - BY - 0.5) / IRY
            outer = ox * ox + oy * oy
            inner = ix * ix + iy * iy
            if outer < 1.0 and inner >= 1.0:
                ang = np.arctan2(oy, ox)
                block = int((ang + np.pi) / (2 * np.pi) * 18)
                seam = abs((ang + np.pi) / (2 * np.pi) * 18 - round((ang + np.pi) / (2 * np.pi) * 18)) < 0.07
                light = (-ox * 0.6 - oy * 0.8) + (hsh(block, 7) - 0.5) * 0.4
                tone = 3 if light > 0.45 else 2 if light > -0.3 else 1
                col = JOINT if seam else stone[tone]
                if outer > 0.86:
                    col = INK if oy < 0 or outer > 0.93 else col
                put(x, y, col)
            elif inner < 1.0:
                depth = inner
                tone = 1 if depth > 0.75 else 2 if iy > -0.3 else 1
                col = WATER[tone]
                if iy < -0.55:
                    col = WATER[0]  # the rim's shadow on the water
                put(x, y, col)
                # ripples running out from the column, one frame further each
                dist = np.sqrt(ix * ix + iy * iy)
                for ring in range(2):
                    phase = (frame / 4.0 + ring * 0.5) % 1.0
                    rr = 0.25 + phase * 0.7
                    if abs(dist - rr) < 0.05 and hsh(x, y, frame) < 0.85:
                        put(x, y, WATER[3])
                        shine(x, y, WATER[3], int(150 * (1 - phase)))
                if hsh(x, y, 20 + frame) > 0.985:
                    put(x, y, WATER[4])
                    shine(x, y, WATER[4], 200)
    # the column with its little bowl and the trickle
    for y in range(12, int(BY) + 2):
        for x in range(25, 31):
            t = (x - 27.5) / 3.0
            light = -t * 0.8 + (hsh(y // 3, 9) - 0.5) * 0.3
            tone = 3 if light > 0.5 else 2 if light > -0.2 else 1
            col = stone[tone]
            if x in (25, 30):
                col = INK
            if (y - 12) % 5 == 4 and 25 < x < 30:
                col = JOINT
            put(x, y, col)
    for y in range(8, 14):
        for x in range(19, 37):
            e = ((x + 0.5 - 28) / 8.5) ** 2 + ((y + 0.5 - 11) / 3.2) ** 2
            if e < 1.0:
                col = WATER[2] if y < 10 and e < 0.55 else stone[3 if x < 26 else 2 if x < 32 else 1]
                if e > 0.75:
                    col = INK if y >= 11 or y < 9 else stone[2]
                put(x, y, col)
    put(28, 9, WATER[4])
    shine(28, 9, WATER[4], 220)
    for side in (-1, 1):  # water running over the bowl's lip and down the column
        for i in range(3):
            y = 13 + ((i * 6 + frame * 2) % 16)
            x = 28 + side * 4
            if y < BY:
                put(x, y, WATER[3])
                shine(x, y, WATER[3], 170)
                put(x, y + 1, WATER[2])
    return arr, glow


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    from PIL import Image  # noqa: E402 (only for writing)
    fl = floor()
    Image.fromarray(fl).save(ROOT / "plaza.png")
    sheet = np.zeros((FH, FW * 4, 4), np.uint8)
    gsheet = np.zeros((FH, FW * 4, 4), np.uint8)
    for f in range(4):
        a, g = fountain(f)
        sheet[:, f * FW:(f + 1) * FW] = a
        gsheet[:, f * FW:(f + 1) * FW] = g
    Image.fromarray(sheet).save(ROOT / "plaza_fountain.png")
    Image.fromarray(gsheet).save(ROOT / "plaza_fountain_glow.png")
    prev = Image.fromarray(fl)
    fr = Image.fromarray(np.ascontiguousarray(sheet[:, :FW]))
    prev.alpha_composite(fr, (int(CX) - FOOT[0], int(CY) + 8 - FOOT[1]))
    prev.save(ROOT / "plaza_preview.png")
    if len(sys.argv) > 1:
        big = prev.resize((W * 4, H * 4), Image.NEAREST)
        bg = Image.new("RGBA", big.size, (74, 120, 70, 255))
        bg.alpha_composite(big)
        bg.save(sys.argv[1])
    print("plaza written: floor %dx%d, fountain %dx%d x4, feet %s, fountain centre on the floor (%d, %d)" % (W, H, FW, FH, FOOT, CX, CY + 8))


if __name__ == "__main__":
    main()
