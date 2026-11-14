#!/usr/bin/env python3
"""The town's heart, the fountain square (docs/brunnenplatz.md), across all three stages:
  Stage 1 (modest):
    plaza.png (208x136, feet 78), plaza_fountain.png & _glow.png (4x 56x48 = 224x48, feet 28,41), plaza_preview.png
  Stage 2 (dressed & two-tier):
    plaza_2.png (208x136, feet 78), plaza_fountain_2.png & _glow.png (4x 56x56 = 224x56, feet 28,49), plaza_2_preview.png
  Stage 3 (grand sanctuary):
    plaza_3.png & plaza_3_glow.png (208x136, feet 78), plaza_fountain_3.png & _glow.png (4x 56x64 = 224x64, feet 28,57), plaza_3_preview.png

Light from the upper left, palette of the town's stone (art_town STONE_L), gold inlay, and turquoise glow. Deterministic.
`py -3 tools/art_plaza.py [contact.png]`
"""
from pathlib import Path
import math
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
DRESSED = [hexc(c) for c in ("424068", "6c6a98", "9c9ac4", "ceccf0")]
SANCTUARY = [hexc(c) for c in ("4a4874", "7a78a8", "b0aed8", "e4e2fa")]
GOLD_TRIM = [hexc(c) for c in ("583e1c", "8e692c", "c89c4c", "f0cf7e")]
TEAL_INLAY = [hexc(c) for c in ("163c48", "22606e", "2f8e98", "64cec8")]
RUNE_GLOW = [hexc(c) for c in ("2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
WARM_GLOW = [hexc(c) for c in ("9a4418", "e07c28", "ffb852", "fff0b0")]
PURE_WHITE = hexc("ffffff")

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


# ================================================================== STAGE 1
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


def _voronoi_grid(pts):
    sx = np.array([p[0] for p in pts])
    sy = np.array([p[1] for p in pts])
    ys, xs = np.mgrid[0:H, 0:W]
    px = xs + 0.5
    py = ys + 0.5
    dx = px[..., None] - sx[None, None, :]
    dy = (py[..., None] - sy[None, None, :]) / FLAT
    d = np.sqrt(dx * dx + dy * dy)
    order = np.argsort(d, axis=2)[..., :2]
    near = np.take_along_axis(d, order, axis=2)
    owner = order[..., 0]
    border = (near[..., 1] - near[..., 0]) * 0.5
    return px, py, owner, border


def floor():
    arr = np.zeros((H, W, 4), np.uint8)
    pts = seeds()
    px, py, owner, border = _voronoi_grid(pts)
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
            missing = hsh(k, i, 9) < outer * 0.55
            if missing:
                if hsh(x, y, 4) < 0.12 * (1 - outer) + 0.05:
                    arr[y, x] = (*MOSS[0].astype(np.uint8), 255)
                continue
            b = border[y, x]
            if b < 0.5:
                col = JOINT_D if b < 0.2 else JOINT
                if hsh(x, y, 11) < 0.15 + outer * 0.7:
                    col = MOSS[0] if hsh(x, y, 12) < 0.6 else MOSS[1]
                if r + wob > 0.94 and bayer(x, y) < (r + wob - 0.94) * 14:
                    continue
                arr[y, x] = (*col.astype(np.uint8), 255)
                continue
            ramp = STONES[int(hsh(k, i, 5) * 3) % 3]
            ndx = (px[y, x] - pts[o][0])
            ndy = (py[y, x] - pts[o][1]) / FLAT
            ln = max(np.hypot(ndx, ndy), 0.001)
            facing = (-ndx * 0.6 - ndy * 0.8) / ln
            edge = 1.0 - min(b / 2.6, 1.0)
            light = facing * edge * 1.3 + (hsh(k, i, 6) - 0.5) * 0.5 + (hsh(x, y, 13) - 0.5) * 0.2 - outer * 0.3 + 0.3
            tone = 3 if light > 0.55 else 2 if light > -0.4 else 1 if light > -1.0 else 0
            if hsh(k, i, 8) < 0.05:
                tone = max(tone - 1, 0)
            arr[y, x] = (*ramp[tone].astype(np.uint8), 255)
            if outer > 0.2 and hsh(x, y, 14) < outer * 0.12 and edge > 0.5:
                arr[y, x, :3] = MOSS[1 + (hsh(x, y, 15) > 0.6)].astype(np.uint8)
    for k_t, (ang, size) in enumerate(((2.55, 8), (0.55, 7), (1.9, 6), (4.3, 5), (3.4, 6), (5.6, 5))):
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


FW, FH = 56, 48
BX, BY = 28.0, 30.0
ORX, ORY = 22.0, 11.0
IRX, IRY = 17.0, 8.0
WALL = 7
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

    stone = [hexc(c) for c in ("4a4870", "7a78a6", "aaa8cc", "d6d4ec")]
    for y in range(FH):
        for x in range(FW):
            e = ((x + 0.5 - BX) / (ORX + 3)) ** 2 + ((y + 0.5 - (BY + WALL + 1)) / (ORY * 0.7)) ** 2
            if e < 1.0 and bayer(x, y) < 0.75 - e * 0.5:
                put(x, y, INK, 110)
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
                    col = WATER[0]
                put(x, y, col)
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
    for side in (-1, 1):
        for i in range(3):
            y = 13 + ((i * 6 + frame * 2) % 16)
            x = 28 + side * 4
            if y < BY:
                put(x, y, WATER[3])
                shine(x, y, WATER[3], 170)
                put(x, y + 1, WATER[2])
    return arr, glow


# ================================================================== STAGE 2
def seeds_neat(step_r=6.0, step_arc=6.5, jitter=0.18):
    """Cleaner, tighter concentric cobble & flagstone seeds for upgraded plazas."""
    out = []
    r = 12.0
    k = 0
    while r < RX + 6:
        # Larger flagstone blocks in the inner sanctum ring (r < 40)
        arc = 9.0 if r < 38.0 else step_arc
        n = max(8, int(2 * np.pi * r / arc))
        off = (k % 2) * (np.pi / n) + hsh(k, 31) * 0.12
        for i in range(n):
            a = off + 2 * np.pi * (i + (hsh(k, i, 41) - 0.5) * jitter) / n
            rr = r + (hsh(k, i, 42) - 0.5) * (0.8 if r < 38.0 else 1.0)
            out.append((CX + np.cos(a) * rr, CY + np.sin(a) * rr * FLAT, k, i))
        r += 7.2 if r < 38.0 else step_r
        k += 1
    return out


def _ell_radius(dx_n, dy_n):
    """Pure 3/4 ground-plane radius and angle around (CX, CY), matching Stage 1 & fountain ellipses."""
    return math.hypot(dx_n, dy_n), math.atan2(dy_n, dx_n)


def floor_2():
    """Stage 2 floor (208x136, feet 78): richer dressed flagstone court, complete cobbled ring, dressed stone curb, subtle inlaid trim."""
    arr = np.zeros((H, W, 4), np.uint8)
    pts = seeds_neat(step_r=6.0, step_arc=6.6, jitter=0.20)
    px, py, owner, border = _voronoi_grid(pts)

    for y in range(H):
        for x in range(W):
            dx_n = (px[y, x] - CX) / RX
            dy_n = (py[y, x] - CY) / RY
            r, ang = _ell_radius(dx_n, dy_n)
            wob = (hsh(x // 3, y // 3, 21) - 0.5) * 0.022
            rw = r + wob
            if rw > 0.992:
                continue

            light_dir = (-dx_n * 0.6 - dy_n * 0.8) / max(r, 0.001)

            # 1) Outer dressed stone curb ring (0.892 .. 0.992), nestled naturally into the meadow
            if rw >= 0.892:
                n_curb = 36
                u_ang = (ang + math.pi) / (2 * math.pi) * n_curb
                blk = int(u_ang) % n_curb
                blk_jit = (hsh(blk, 22) - 0.5) * 0.016
                if rw + blk_jit > 0.985:
                    if rw + blk_jit < 0.996 and hsh(x, y, 23) < 0.45:
                        arr[y, x] = (*MOSS[0 if dy_n > 0 else 1].astype(np.uint8), 255)
                    continue
                if rw + blk_jit > 0.968:
                    # Subtle earthy/stone outer rim lip (darker on shaded bottom-right, mossy/soft on top-left)
                    col = JOINT_D if light_dir < -0.1 else (MOSS[0] if hsh(x, y, 24) < 0.35 else STONES[0][0])
                    arr[y, x] = (*col.astype(np.uint8), 255)
                    continue
                seam = abs(u_ang - round(u_ang)) < 0.065 or rw < 0.902
                if seam:
                    col = JOINT_D if rw > 0.95 else JOINT
                    if hsh(x, y, 25) < 0.16:
                        col = MOSS[0]
                    arr[y, x] = (*col.astype(np.uint8), 255)
                else:
                    bevel = 0.32 if rw < 0.928 else (-0.20 if rw > 0.952 else 0.0)
                    lt = light_dir * 0.65 + bevel + (hsh(blk, 26) - 0.5) * 0.32
                    tone = 3 if lt > 0.42 else 2 if lt > -0.15 else 1 if lt > -0.6 else 0
                    arr[y, x] = (*DRESSED[tone].astype(np.uint8), 255)
                continue

            # 2) Subtle outer & inner inlaid trim bands (flat flush stone + warm bronze/teal-slate tesserae)
            in_outer_trim = 0.858 <= rw < 0.892
            in_inner_trim = 0.380 <= rw < 0.414
            if in_outer_trim or in_inner_trim:
                n_tess = 48 if in_outer_trim else 24
                u_ang = (ang + math.pi) / (2 * math.pi) * n_tess
                idx = int(u_ang) % n_tess
                edge_r = (rw < 0.864 or rw > 0.886) if in_outer_trim else (rw < 0.386 or rw > 0.408)
                seam = edge_r or abs(u_ang - round(u_ang)) < 0.08
                if seam:
                    arr[y, x] = (*JOINT.astype(np.uint8), 255)
                else:
                    pal = GOLD_TRIM if (idx % 2 == 0) else TEAL_INLAY
                    lt = light_dir * 0.5 + 0.25 + (hsh(idx, 29) - 0.5) * 0.2
                    tone = 3 if lt > 0.55 else 2 if lt > 0.0 else 1
                    arr[y, x] = (*pal[tone].astype(np.uint8), 255)
                continue

            # 3) Cobble ring (0.414 .. 0.858) & dressed inner court (< 0.380)
            o = owner[y, x]
            k, i = pts[o][2], pts[o][3]
            b = border[y, x]
            is_inner = rw < 0.380
            joint_w = 0.42 if is_inner else 0.46
            if b < joint_w:
                col = JOINT_D if b < 0.16 else JOINT
                if not is_inner and rw > 0.75 and hsh(x, y, 27) < (rw - 0.75) * 0.85:
                    col = MOSS[0] if hsh(x, y, 28) < 0.7 else MOSS[1]
                arr[y, x] = (*col.astype(np.uint8), 255)
                continue

            ramp = DRESSED if (is_inner and (k + i) % 2 == 0) else STONES[int(hsh(k, i, 5) * 3) % 3]
            ndx = (px[y, x] - pts[o][0])
            ndy = (py[y, x] - pts[o][1]) / FLAT
            ln = max(np.hypot(ndx, ndy), 0.001)
            facing = (-ndx * 0.6 - ndy * 0.8) / ln
            edge = 1.0 - min(b / (3.2 if is_inner else 2.6), 1.0)
            light = facing * edge * (1.05 if is_inner else 1.25) + (hsh(k, i, 6) - 0.5) * 0.38 + (0.38 if is_inner else 0.28)
            tone = 3 if light > 0.55 else 2 if light > -0.32 else 1 if light > -0.95 else 0
            arr[y, x] = (*ramp[tone].astype(np.uint8), 255)

    # Neat manicured herb & flower tufts tucked along the outer curb edge
    for k_t, (ang, size) in enumerate(((2.45, 6), (0.65, 6), (1.80, 5), (4.40, 5), (3.65, 5), (5.50, 5))):
        bx = CX + np.cos(ang) * RX * 0.965
        by = CY + np.sin(ang) * RY * 0.965
        for j in range(size * 3):
            x = int(bx + (hsh(k_t + 10, j, 1) - 0.5) * size * 1.6)
            y = int(by + (hsh(k_t + 10, j, 2) - 0.5) * size * 1.0)
            if 0 <= x < W and 1 <= y < H:
                arr[y, x] = (*MOSS[1 + (j % 3 == 0)].astype(np.uint8), 255)
                if j % 3 == 0:
                    arr[y - 1, x] = (*MOSS[2].astype(np.uint8), 255)
        for j in range(max(2, size - 1)):
            x = int(bx + (hsh(k_t + 10, j, 3) - 0.5) * size * 1.4)
            y = int(by - 1 + (hsh(k_t + 10, j, 4) - 0.5) * size * 0.8)
            if 0 <= x < W and 0 <= y < H:
                arr[y, x] = (*PETALS[(k_t + j) % 4].astype(np.uint8), 255)
    return arr


FW2, FH2 = 56, 56
FOOT2 = (28, 49)


def fountain_2(frame):
    """Stage 2 fountain (56x56 x4, feet at 28,49): two-tier carved stone basin, animated turquoise ripples,
    taller arcing water jets, subtle teal rune buds on rim."""
    arr = np.zeros((FH2, FW2, 4), np.uint8)
    glow = np.zeros((FH2, FW2, 4), np.uint8)
    by = 38.0
    orx, ory = 23.5, 11.0
    irx, iry = 18.2, 8.2
    wall = 7

    def put(x, y, col, a=255):
        if 0 <= x < FW2 and 0 <= y < FH2:
            arr[y, x] = (*np.clip(col, 0, 255).astype(np.uint8), a)

    def shine(x, y, col, a):
        if 0 <= x < FW2 and 0 <= y < FH2 and a > 0:
            if a >= glow[y, x, 3]:
                glow[y, x] = (*np.clip(col, 0, 255).astype(np.uint8), int(min(255, a)))

    stone = DRESSED
    # 1) Contact shadow
    for y in range(FH2):
        for x in range(FW2):
            e = ((x + 0.5 - BX) / (orx + 3.0)) ** 2 + ((y + 0.5 - (by + wall + 1)) / (ory * 0.72)) ** 2
            if e < 1.0 and bayer(x, y) < 0.75 - e * 0.5:
                put(x, y, INK, 115)

    # 2) Lower carved stone front wall (pilasters + recessed panels)
    for x in range(FW2):
        t = (x + 0.5 - BX) / orx
        if abs(t) >= 1.0:
            continue
        rim = by + ory * math.sqrt(1.0 - t * t)
        pilaster = any(abs(t - pt) < 0.085 for pt in (-0.68, -0.22, 0.22, 0.68))
        for yy in range(wall):
            y = int(rim) + yy
            ang_u = (math.asin(max(-1.0, min(1.0, t))) + 2.0) * 6.5
            light = -t * 0.85 + (0.28 if pilaster else -0.12) - yy * 0.05
            tone = 3 if light > 0.48 else 2 if light > -0.05 else 1 if light > -0.55 else 0
            col = stone[tone]
            if yy == 0:
                col = stone[min(tone + 1, 3)]
            elif yy == 1 and not pilaster:
                col = JOINT  # carved shadow groove under cornice lip
            elif yy == wall - 1:
                col = JOINT_D
            elif not pilaster and abs(ang_u - round(ang_u)) < 0.10 and yy > 1:
                col = JOINT
            put(x, y, col)
        put(x, int(rim) + wall, INK)

    # 3) Lower rim ring + animated water inside
    for y in range(FH2):
        for x in range(FW2):
            ox = (x + 0.5 - BX) / orx
            oy = (y + 0.5 - by) / ory
            ix = (x + 0.5 - BX) / irx
            iy = (y + 0.5 - by - 0.4) / iry
            outer = ox * ox + oy * oy
            inner = ix * ix + iy * iy
            if outer < 1.0 and inner >= 1.0:
                ang = math.atan2(oy, ox)
                u = (ang + math.pi) / (2 * math.pi) * 20.0
                seam = abs(u - round(u)) < 0.065
                light = (-ox * 0.6 - oy * 0.8) + (hsh(int(u), 17) - 0.5) * 0.28
                tone = 3 if light > 0.35 else 2 if light > -0.3 else 1
                col = JOINT if seam else stone[tone]
                if inner < 1.16:
                    col = GOLD_TRIM[2 if light > 0 else 1]  # subtle carved inner trim lip
                if outer > 0.86:
                    col = INK if (oy < 0 or outer > 0.92) else col
                put(x, y, col)
            elif inner < 1.0:
                tone = 1 if inner > 0.78 else (2 if iy > -0.32 else 1)
                col = WATER[tone]
                if iy < -0.58:
                    col = WATER[0]
                put(x, y, col)
                dist = math.sqrt(inner)
                for ring in range(3):
                    phase = (frame / 4.0 + ring / 3.0) % 1.0
                    rr = 0.20 + phase * 0.74
                    if abs(dist - rr) < 0.048 and hsh(x, y, frame + ring * 7) < 0.88:
                        c_w = WATER[4] if phase < 0.35 else WATER[3]
                        put(x, y, c_w)
                        shine(x, y, RUNE_GLOW[2 if phase >= 0.35 else 3], int(165 * (1.0 - phase * 0.75)))
                if hsh(x, y, 40 + frame) > 0.982:
                    put(x, y, WATER[4])
                    shine(x, y, RUNE_GLOW[3], 210)

    # 6 subtle teal rune buds set into the lower stone rim
    rmx, rmy = (orx + irx) * 0.5, (ory + iry) * 0.5
    for k in range(6):
        ang = k * (math.tau / 6.0) + math.pi / 6.0
        rx_p = int(round(BX + math.cos(ang) * rmx - 0.5))
        ry_p = int(round(by + math.sin(ang) * rmy - 0.5))
        pulse = 0.65 + 0.35 * math.sin(frame / 4.0 * math.tau + k * 1.05)
        put(rx_p, ry_p, RUNE_GLOW[3 if pulse > 0.85 else 2])
        shine(rx_p, ry_p, RUNE_GLOW[3 if pulse > 0.82 else 2], int(150 + 85 * pulse))
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shine(rx_p + dx, ry_p + dy, RUNE_GLOW[1], int(55 * pulse))

    # 4) Central carved stone pedestal column (rising from lower pool y=39 up to upper bowl y=23)
    for y in range(23, int(by) + 2):
        w_col = 4 if y > 35 else 3
        for x in range(28 - w_col, 28 + w_col):
            t = (x + 0.5 - 28.0) / w_col
            col = stone[3 if t < -0.25 else (2 if t < 0.3 else 1)]
            if x in (28 - w_col, 28 + w_col - 1):
                col = INK
            elif y in (27, 32, 36):
                col = JOINT
            put(x, y, col)
    # Foam collar around pedestal foot
    for dx in range(-4, 5):
        if (dx + frame) % 2 == 0:
            put(28 + dx, int(by) + 1, WATER[3])
            shine(28 + dx, int(by) + 1, RUNE_GLOW[2], 140)

    # 5) Upper carved stone tier bowl (centre 28, 21)
    uby, uorx, uory, uirx, uiry = 21.0, 11.5, 4.6, 8.4, 3.0
    # Underside / front lip of upper bowl
    for x in range(int(BX - uorx) - 1, int(BX + uorx) + 2):
        t = (x + 0.5 - BX) / uorx
        if abs(t) >= 1.0:
            continue
        rim_u = uby + uory * math.sqrt(1.0 - t * t)
        for yy in range(4):
            y = int(rim_u) + yy
            col = stone[3 if (t < -0.2 and yy == 0) else (2 if t < 0.35 and yy < 2 else (1 if yy < 3 else 0))]
            if yy == 3:
                col = INK
            put(x, y, col)
    # Top rim & water of upper bowl
    for y in range(int(uby - uory) - 1, int(uby + uory) + 2):
        for x in range(int(BX - uorx) - 1, int(BX + uorx) + 2):
            ox = (x + 0.5 - BX) / uorx
            oy = (y + 0.5 - uby) / uory
            ix = (x + 0.5 - BX) / uirx
            iy = (y + 0.5 - uby - 0.2) / uiry
            if ox * ox + oy * oy < 1.0:
                if ix * ix + iy * iy < 1.0:
                    col = WATER[3 if (ix + iy + frame * 0.3) % 1.0 < 0.35 else 2]
                    put(x, y, col)
                    if (x + y + frame) % 3 == 0:
                        shine(x, y, RUNE_GLOW[2], 130)
                else:
                    col = INK if (oy < -0.15 and ox * ox + oy * oy > 0.80) or ox * ox + oy * oy > 0.90 else stone[3 if (-ox - oy) > 0.2 else 2]
                    put(x, y, col)

    # 6) Carved top spout finial (y = 11..20)
    for y in range(12, 21):
        hw = 3 if y in (14, 15) else 2
        for x in range(28 - hw, 28 + hw):
            if x in (28 - hw, 28 + hw - 1):
                put(x, y, INK)
            else:
                put(x, y, GOLD_TRIM[2] if y == 15 else stone[3 if x < 28 else 2])
    # Glowing teal spout crown bud
    put(27, 11, RUNE_GLOW[3])
    put(28, 11, PURE_WHITE if frame % 2 == 0 else RUNE_GLOW[3])
    put(27, 10, INK)
    put(28, 10, INK)
    shine(27, 11, RUNE_GLOW[3], 220)
    shine(28, 11, RUNE_GLOW[3], 240)

    # 7) Taller arcing water jets from top spout into upper bowl + cascading streams into lower basin
    for side in (-1, 1):
        # High parabolic arc from (27.5 + side*0.5, 11) peaking at y=7..8 and landing at (28 + side*7, 20)
        for step in range(11):
            u = step / 10.0
            jx = int(round(27.5 + side * (1.0 + 6.5 * u)))
            jy = int(round(11.0 - 4.2 * math.sin(u * math.pi) + 9.0 * (u ** 1.5)))
            active = (step + (frame if side < 0 else 4 - frame)) % 3 != 0
            c_jet = WATER[4] if (step + frame) % 4 == 0 else WATER[3]
            if active:
                put(jx, jy, c_jet)
                shine(jx, jy, RUNE_GLOW[3 if c_jet is WATER[4] else 2], 185)
        # Outer shorter jet from upper bowl rim arcing out into lower pool
        for step in range(13):
            u = step / 12.0
            cx_s = int(round(27.5 + side * (8.5 + 4.8 * u)))
            cy_s = int(round(22.5 + 14.5 * (u ** 1.35)))
            if cy_s <= int(by) + 2:
                bright = (step - frame) % 3 == 0
                put(cx_s, cy_s, WATER[4] if bright else WATER[3])
                shine(cx_s, cy_s, RUNE_GLOW[3 if bright else 2], 175 if bright else 120)
        # Inner vertical cascade stream from upper lip
        sx_in = 28 + side * 5
        for y in range(24, int(by) + 1):
            if (y - frame * 2) % 3 != 0:
                put(sx_in, y, WATER[4] if (y + frame) % 4 == 0 else WATER[3])
                shine(sx_in, y, RUNE_GLOW[2], 145)
        # Splash foam in lower pool where outer jet lands
        lx, ly = int(round(27.5 + side * 13.0)), int(by) + 1
        put(lx, ly, WATER[4])
        shine(lx, ly, RUNE_GLOW[3], 200)
        if frame % 2 == (0 if side < 0 else 1):
            put(lx - side, ly - 1, WATER[4])
            shine(lx - side, ly - 1, RUNE_GLOW[3], 160)

    return arr, glow


# ================================================================== STAGE 3
def floor_3():
    """Stage 3 floor (208x136, feet 78) + glow: grand masterwork cobblestone plaza with 8-way radial gold/stone inlay
    & subtle teal runic center glow. Caravan side slots remain completely flat & clear."""
    arr = np.zeros((H, W, 4), np.uint8)
    glow = np.zeros((H, W, 4), np.uint8)
    pts = seeds_neat(step_r=5.8, step_arc=6.2, jitter=0.14)
    px, py, owner, border = _voronoi_grid(pts)

    for y in range(H):
        for x in range(W):
            dx_n = (px[y, x] - CX) / RX
            dy_n = (py[y, x] - CY) / RY
            r, ang = _ell_radius(dx_n, dy_n)
            wob = (hsh(x // 4, y // 4, 51) - 0.5) * 0.015
            rw = r + wob
            if rw > 0.995:
                continue

            light_dir = (-dx_n * 0.6 - dy_n * 0.8) / max(r, 0.001)

            # Closest of the 8 compass rays (0, pi/4, pi/2, ...)
            ray_u = (ang + math.pi) / (math.pi / 4.0)
            ray_dist = abs(ray_u - round(ray_u)) * (math.pi / 4.0) * max(r, 0.05) * RX  # perp distance in ground px

            # 1) Grand masterwork outer sanctuary curb + corner keystones (0.888 .. 0.995), nestled in meadow
            if rw >= 0.888:
                n_curb = 36
                u_ang = (ang + math.pi) / (2 * math.pi) * n_curb
                blk_jit = (hsh(int(u_ang) % n_curb, 53) - 0.5) * 0.012
                if rw + blk_jit > 0.988:
                    if rw + blk_jit < 0.996 and hsh(x, y, 54) < 0.35:
                        arr[y, x] = (*MOSS[0 if dy_n > 0 else 1].astype(np.uint8), 255)
                    continue
                if rw + blk_jit > 0.972:
                    col = JOINT_D if light_dir < -0.05 else STONES[0][0]
                    arr[y, x] = (*col.astype(np.uint8), 255)
                    continue
                is_keystone = ray_dist < 4.2
                seam = (not is_keystone and abs(u_ang - round(u_ang)) < 0.06) or (abs(ray_dist - 4.2) < 0.55) or rw < 0.898
                if seam:
                    arr[y, x] = (*(JOINT_D if rw > 0.955 else JOINT).astype(np.uint8), 255)
                elif is_keystone and 0.924 <= rw <= 0.956 and ray_dist < 2.1:
                    arr[y, x] = (*GOLD_TRIM[3 if light_dir > 0 else 2].astype(np.uint8), 255)
                else:
                    pal = SANCTUARY if is_keystone else DRESSED
                    bevel = 0.36 if rw < 0.928 else (-0.20 if rw > 0.956 else 0.05)
                    lt = light_dir * 0.65 + bevel + (hsh(int(u_ang), 52) - 0.5) * 0.24
                    tone = 3 if lt > 0.40 else 2 if lt > -0.15 else 1 if lt > -0.6 else 0
                    arr[y, x] = (*pal[tone].astype(np.uint8), 255)
                continue

            # 2) Outer gold inlay ring (0.854 .. 0.888) — pure concentric r!
            if 0.854 <= r < 0.888:
                if r < 0.860 or r > 0.882:
                    arr[y, x] = (*JOINT_D.astype(np.uint8), 255)
                else:
                    lt = light_dir * 0.55 + 0.25
                    tone = 3 if lt > 0.45 else 2 if lt > -0.1 else 1
                    arr[y, x] = (*GOLD_TRIM[tone].astype(np.uint8), 255)
                continue

            # 3) Glowing teal runic center ring (pure concentric r = 0.346 .. 0.382) + 8 radial rune nodes at r ~ 0.432
            in_rune_ring = 0.346 <= r < 0.382
            node_d = math.hypot((r - 0.432) * RX, ray_dist)
            in_rune_node = node_d < 3.0
            if in_rune_ring or in_rune_node:
                groove_core = (0.356 <= r <= 0.372) if in_rune_ring else (node_d < 1.70)
                if groove_core:
                    seg_u = (ang + math.pi) / (2 * math.pi) * 16.0
                    is_bridge = in_rune_ring and not in_rune_node and abs(seg_u - round(seg_u)) < 0.11 and ray_dist >= 2.2
                    if is_bridge:
                        arr[y, x] = (*JOINT_D.astype(np.uint8), 255)
                    else:
                        hot = in_rune_node and node_d < 0.95
                        arr[y, x] = (*TEAL_INLAY[3 if hot else 2].astype(np.uint8), 255)
                        g_col = RUNE_GLOW[3 if hot else 2]
                        glow[y, x] = (*g_col.astype(np.uint8), 225 if hot else 175)
                else:
                    arr[y, x] = (*JOINT_D.astype(np.uint8), 255)
                    glow[y, x] = (*RUNE_GLOW[1].astype(np.uint8), 70)
                continue

            # 4) 8 Radial masterwork inlay spokes (from r=0.382 out to r=0.854)
            if 0.382 <= r < 0.854 and ray_dist < 2.6:
                if ray_dist > 1.95:
                    arr[y, x] = (*JOINT.astype(np.uint8), 255)
                elif ray_dist < 0.85:
                    tone = 3 if light_dir > 0.25 else 2
                    arr[y, x] = (*GOLD_TRIM[tone].astype(np.uint8), 255)
                else:
                    tone = 3 if light_dir > 0.2 else 2
                    arr[y, x] = (*SANCTUARY[tone].astype(np.uint8), 255)
                continue

            # 5) Inner sanctuary ring (< 0.346) & 8 masterwork cobbled fan sectors (0.382 .. 0.854)
            o = owner[y, x]
            k, i = pts[o][2], pts[o][3]
            b = border[y, x]
            is_sanctum = r < 0.346
            if b < (0.40 if is_sanctum else 0.44):
                col = JOINT_D if b < 0.15 else JOINT
                arr[y, x] = (*col.astype(np.uint8), 255)
                continue

            if is_sanctum:
                ramp = SANCTUARY if (k + i) % 2 == 0 else DRESSED
            else:
                sel = int(hsh(k, i, 5) * 3) % 3
                ramp = DRESSED if (k % 4 == 0 and i % 2 == 0) else STONES[sel]
            ndx = (px[y, x] - pts[o][0])
            ndy = (py[y, x] - pts[o][1]) / FLAT
            ln = max(np.hypot(ndx, ndy), 0.001)
            facing = (-ndx * 0.6 - ndy * 0.8) / ln
            edge = 1.0 - min(b / (3.2 if is_sanctum else 2.7), 1.0)
            light = facing * edge * 1.15 + (hsh(k, i, 6) - 0.5) * 0.32 + (0.42 if is_sanctum else 0.32)
            tone = 3 if light > 0.52 else 2 if light > -0.30 else 1 if light > -0.92 else 0
            arr[y, x] = (*ramp[tone].astype(np.uint8), 255)

    # Small neat sanctuary blossom tufts along the outer rim (clear of E/W caravan lanes)
    for k_t, (ang, size) in enumerate(((2.35, 5), (0.78, 5), (1.78, 4), (4.60, 4), (3.88, 5), (5.38, 4))):
        bx = CX + np.cos(ang) * RX * 0.972
        by = CY + np.sin(ang) * RY * 0.972
        for j in range(size * 3):
            x = int(bx + (hsh(k_t + 30, j, 1) - 0.5) * size * 1.5)
            y = int(by + (hsh(k_t + 30, j, 2) - 0.5) * size * 0.9)
            if 0 <= x < W and 1 <= y < H:
                arr[y, x] = (*MOSS[1 + (j % 2 == 0)].astype(np.uint8), 255)
        for j in range(max(2, size - 1)):
            x = int(bx + (hsh(k_t + 30, j, 3) - 0.5) * size * 1.3)
            y = int(by - 1 + (hsh(k_t + 30, j, 4) - 0.5) * size * 0.8)
            if 0 <= x < W and 0 <= y < H:
                arr[y, x] = (*PETALS[(k_t + j) % 4].astype(np.uint8), 255)
    return arr, glow


FW3, FH3 = 56, 64
FOOT3 = (28, 57)


def fountain_3(frame):
    """Stage 3 fountain (56x64 x4, feet at 28,57): grand tiered sanctuary fountain with sculpted spire finial,
    dual cascading water tiers, sparkling animated jets, glowing cyan-teal crystal crown and warm/teal basin lights."""
    arr = np.zeros((FH3, FW3, 4), np.uint8)
    glow = np.zeros((FH3, FW3, 4), np.uint8)
    by = 46.0
    orx, ory = 24.8, 11.0
    irx, iry = 19.4, 8.4
    wall = 7

    def put(x, y, col, a=255):
        if 0 <= x < FW3 and 0 <= y < FH3:
            arr[y, x] = (*np.clip(col, 0, 255).astype(np.uint8), a)

    def shine(x, y, col, a):
        if 0 <= x < FW3 and 0 <= y < FH3 and a > 0:
            if a >= glow[y, x, 3]:
                glow[y, x] = (*np.clip(col, 0, 255).astype(np.uint8), int(min(255, a)))

    stone = SANCTUARY
    # 1) Contact shadow
    for y in range(FH3):
        for x in range(FW3):
            e = ((x + 0.5 - BX) / (orx + 3.2)) ** 2 + ((y + 0.5 - (by + wall + 1)) / (ory * 0.72)) ** 2
            if e < 1.0 and bayer(x, y) < 0.78 - e * 0.5:
                put(x, y, INK, 120)

    # 2) Grand sanctuary lower basin wall (marble ashlar, gold fillets, carved pilasters & warm basin lights)
    pilaster_ts = (-0.75, -0.28, 0.28, 0.75)
    warm_niche_ts = (-0.52, 0.0, 0.52)
    for x in range(FW3):
        t = (x + 0.5 - BX) / orx
        if abs(t) >= 1.0:
            continue
        rim = by + ory * math.sqrt(1.0 - t * t)
        pilaster = any(abs(t - pt) < 0.075 for pt in pilaster_ts)
        niche = any(abs(t - nt) < 0.055 for nt in warm_niche_ts)
        for yy in range(wall):
            y = int(rim) + yy
            light = -t * 0.85 + (0.32 if pilaster else -0.05) - yy * 0.05
            tone = 3 if light > 0.42 else 2 if light > -0.10 else 1 if light > -0.58 else 0
            col = stone[tone]
            if yy == 0:
                col = GOLD_TRIM[3 if t < 0 else 2] if pilaster else stone[min(tone + 1, 3)]
            elif yy == wall - 2 and pilaster:
                col = GOLD_TRIM[2 if t < 0 else 1]
            elif yy == wall - 1:
                col = JOINT_D
            elif niche and yy in (2, 3, 4):
                # Warm golden-amber basin sconce / niche light
                flick = 0.82 + 0.18 * math.sin(frame / 4.0 * math.tau + t * 5.0)
                w_tone = 3 if (yy == 3 and flick > 0.86) else 2
                col = WARM_GLOW[w_tone]
                shine(x, y, WARM_GLOW[w_tone], int(195 * flick))
                shine(x, y - 1, WARM_GLOW[1], int(75 * flick))
                shine(x, y + 1, WARM_GLOW[1], int(75 * flick))
            put(x, y, col)
        put(x, int(rim) + wall, INK)

    # 3) Grand lower rim + golden inner lip + animated luminous pool
    for y in range(FH3):
        for x in range(FW3):
            ox = (x + 0.5 - BX) / orx
            oy = (y + 0.5 - by) / ory
            ix = (x + 0.5 - BX) / irx
            iy = (y + 0.5 - by - 0.3) / iry
            outer = ox * ox + oy * oy
            inner = ix * ix + iy * iy
            if outer < 1.0 and inner >= 1.0:
                ang = math.atan2(oy, ox)
                u = (ang + math.pi) / (2 * math.pi) * 24.0
                seam = abs(u - round(u)) < 0.06
                light = (-ox * 0.6 - oy * 0.8) + (hsh(int(u), 61) - 0.5) * 0.22
                tone = 3 if light > 0.32 else 2 if light > -0.32 else 1
                col = JOINT if seam else stone[tone]
                if inner < 1.18:
                    col = GOLD_TRIM[3 if light > 0.35 else (2 if light > -0.2 else 1)]
                if outer > 0.87:
                    col = INK if (oy < 0 or outer > 0.93) else col
                put(x, y, col)
            elif inner < 1.0:
                tone = 2 if inner < 0.68 and iy > -0.42 else 1
                col = WATER[tone]
                if iy < -0.60:
                    col = WATER[0]
                put(x, y, col)
                dist = math.sqrt(inner)
                for ring in range(3):
                    phase = (frame / 4.0 + ring / 3.0) % 1.0
                    rr = 0.18 + phase * 0.76
                    if abs(dist - rr) < 0.052 and hsh(x, y, 70 + frame + ring * 5) < 0.90:
                        c_w = WATER[4] if phase < 0.4 else WATER[3]
                        put(x, y, c_w)
                        shine(x, y, RUNE_GLOW[3 if phase < 0.4 else 2], int(180 * (1.0 - phase * 0.7)))
                if hsh(x, y, 80 + frame) > 0.975:
                    put(x, y, PURE_WHITE)
                    shine(x, y, RUNE_GLOW[3], 225)

    # 8 glowing teal basin rim gems
    rmx, rmy = (orx + irx) * 0.5, (ory + iry) * 0.5
    for k in range(8):
        ang = k * (math.tau / 8.0) + math.pi / 8.0
        rx_p = int(round(BX + math.cos(ang) * rmx - 0.5))
        ry_p = int(round(by + math.sin(ang) * rmy - 0.5))
        pulse = 0.70 + 0.30 * math.sin(frame / 4.0 * math.tau + k * 0.8)
        put(rx_p, ry_p, RUNE_GLOW[3 if pulse > 0.85 else 2])
        shine(rx_p, ry_p, RUNE_GLOW[3], int(170 + 75 * pulse))
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shine(rx_p + dx, ry_p + dy, RUNE_GLOW[1], int(60 * pulse))

    # 4) Lower fluted pedestal column (y = 31..47)
    for y in range(31, int(by) + 2):
        hw = 5 if y > 43 else 4
        for x in range(28 - hw, 28 + hw):
            t = (x + 0.5 - 28.0) / hw
            if x in (28 - hw, 28 + hw - 1):
                col = INK
            elif y in (34, 42):
                col = GOLD_TRIM[2 if t < 0 else 1]
            else:
                flute = -0.15 if (x % 2 == 0 and abs(t) < 0.7) else 0.1
                lt = -t * 0.8 + flute
                col = stone[3 if lt > 0.35 else 2 if lt > -0.2 else 1]
            put(x, y, col)
    for dx in range(-5, 6):
        if (dx + frame) % 2 == 0:
            put(28 + dx, int(by) + 1, WATER[4] if abs(dx) < 3 else WATER[3])
            shine(28 + dx, int(by) + 1, RUNE_GLOW[3], 165)

    # 5) Middle sculpted basin tier (centre 28, 29.5)
    mby, morx, mory, mirx, miry = 29.5, 14.0, 5.2, 10.5, 3.5
    for x in range(int(BX - morx) - 1, int(BX + morx) + 2):
        t = (x + 0.5 - BX) / morx
        if abs(t) >= 1.0:
            continue
        rim_m = mby + mory * math.sqrt(1.0 - t * t)
        for yy in range(4):
            y = int(rim_m) + yy
            if yy == 0:
                col = GOLD_TRIM[3 if t < -0.1 else 2]
            elif yy == 3:
                col = INK
            else:
                col = stone[2 if t < 0.2 else 1]
            put(x, y, col)
    for y in range(int(mby - mory) - 1, int(mby + mory) + 2):
        for x in range(int(BX - morx) - 1, int(BX + morx) + 2):
            ox = (x + 0.5 - BX) / morx
            oy = (y + 0.5 - mby) / mory
            ix = (x + 0.5 - BX) / mirx
            iy = (y + 0.5 - mby - 0.2) / miry
            if ox * ox + oy * oy < 1.0:
                if ix * ix + iy * iy < 1.0:
                    col = WATER[3 if ((x + frame) % 3 == 0) else 2]
                    put(x, y, col)
                    shine(x, y, RUNE_GLOW[2], 135)
                else:
                    col = INK if (oy < -0.15 and ox * ox + oy * oy > 0.78) or ox * ox + oy * oy > 0.90 else stone[3 if (-ox - oy) > 0.15 else 2]
                    put(x, y, col)

    # 6) Upper column (y = 18..29) + upper chalice bowl (centre 28, 17.5)
    for y in range(18, 30):
        for x in range(25, 31):
            if x in (25, 30):
                put(x, y, INK)
            elif y == 22:
                put(x, y, GOLD_TRIM[2 if x < 28 else 1])
            else:
                put(x, y, stone[3 if x < 28 else 2])

    cby, corx, cory, cirx, ciry = 17.2, 8.2, 3.1, 5.8, 1.9
    for x in range(int(BX - corx) - 1, int(BX + corx) + 2):
        t = (x + 0.5 - BX) / corx
        if abs(t) >= 1.0:
            continue
        rim_c = cby + cory * math.sqrt(1.0 - t * t)
        put(x, int(rim_c), GOLD_TRIM[3 if t < 0 else 2])
        put(x, int(rim_c) + 1, stone[2 if t < 0.2 else 1])
        put(x, int(rim_c) + 2, INK)
    for y in range(int(cby - cory) - 1, int(cby + cory) + 2):
        for x in range(int(BX - corx) - 1, int(BX + corx) + 2):
            ox = (x + 0.5 - BX) / corx
            oy = (y + 0.5 - cby) / cory
            ix = (x + 0.5 - BX) / cirx
            iy = (y + 0.5 - cby) / ciry
            if ox * ox + oy * oy < 1.0:
                if ix * ix + iy * iy < 1.0:
                    put(x, y, WATER[3])
                    shine(x, y, RUNE_GLOW[3], 170)
                else:
                    put(x, y, INK if ox * ox + oy * oy > 0.82 else stone[3 if ox < 0 else 2])

    # 7) Sculpted spire finial & glowing cyan-teal crystal crown (y = 2..16)
    # Golden pronged cradle (y = 11..16)
    for y in range(12, 17):
        for x in range(26, 30):
            put(x, y, INK if x in (26, 29) and y > 13 else GOLD_TRIM[3 if x == 27 else 2])
    for side, gx in ((-1, 24), (1, 31)):
        put(gx, 11, GOLD_TRIM[3 if side < 0 else 2])
        put(gx, 12, GOLD_TRIM[2 if side < 0 else 1])
        put(gx, 13, INK)
    # Faceted cyan-teal sanctuary crystal spire (y = 3..12, x = 25..30)
    crystal_widths = {3: (27, 29), 4: (27, 29), 5: (26, 30), 6: (25, 31), 7: (25, 31), 8: (25, 31), 9: (26, 30), 10: (26, 30), 11: (27, 29)}
    pulse_c = 0.85 + 0.15 * math.sin(frame / 4.0 * math.tau)
    # Soft unlit halo behind crystal crown
    for hy in range(1, 15):
        for hx in range(21, 35):
            hd = math.hypot((hx - 27.5) / 6.2, (hy - 7.5) / 6.2)
            if hd < 1.0:
                shine(hx, hy, RUNE_GLOW[1], int((1.0 - hd) ** 1.6 * 115 * pulse_c))
    for cy_k, (x0, x1) in crystal_widths.items():
        put(x0 - 1, cy_k, INK)
        put(x1, cy_k, INK)
        for cx_k in range(x0, x1):
            is_core = cx_k in (27, 28) and 5 <= cy_k <= 8
            col = PURE_WHITE if is_core else (RUNE_GLOW[3] if cx_k <= 27 else RUNE_GLOW[2 if cy_k < 9 else 1])
            put(cx_k, cy_k, col)
            shine(cx_k, cy_k, PURE_WHITE if is_core else RUNE_GLOW[3], 250 if is_core else 220)
    put(27, 2, INK)
    put(28, 2, INK)

    # 8) Dual cascading water tiers & sparkling animated jets
    for side in (-1, 1):
        # Upper jets: arcing from spire base (28, 12) out into upper chalice
        for step in range(8):
            u = step / 7.0
            jx = int(round(27.5 + side * (1.2 + 4.8 * u)))
            jy = int(round(12.0 - 2.6 * math.sin(u * math.pi) + 4.8 * (u ** 1.4)))
            if (step + frame) % 3 != 0:
                put(jx, jy, WATER[4] if step < 4 else WATER[3])
                shine(jx, jy, RUNE_GLOW[3], 195)

        # Tier 1 -> Tier 2 cascade (upper chalice lip y=19 down to middle basin y=29)
        cx1 = int(round(27.5 + side * 6.0))
        for y in range(19, 30):
            if (y - frame * 2) % 3 != 0:
                bright = (y + frame) % 4 == 0
                put(cx1, y, WATER[4] if bright else WATER[3])
                shine(cx1, y, RUNE_GLOW[3 if bright else 2], 180 if bright else 135)

        # Tier 2 -> Tier 1 arcing outer spouts (from middle basin rim arcing wide into grand lower pool)
        for step in range(15):
            u = step / 14.0
            jx2 = int(round(27.5 + side * (11.0 + 6.2 * u)))
            jy2 = int(round(30.5 - 2.2 * math.sin(u * math.pi) + 15.0 * (u ** 1.45)))
            if jy2 <= int(by) + 2 and (step + frame + (1 if side > 0 else 0)) % 3 != 0:
                bright = (step - frame) % 4 == 0
                put(jx2, jy2, PURE_WHITE if bright else WATER[3])
                shine(jx2, jy2, RUNE_GLOW[3 if bright else 2], 210 if bright else 145)

        # Tier 2 -> Tier 1 inner vertical cascade curtains
        cx2 = int(round(27.5 + side * 7.5))
        for y in range(32, int(by) + 1):
            if (y - frame) % 3 != 0:
                put(cx2, y, WATER[4] if (y + frame) % 3 == 0 else WATER[3])
                shine(cx2, y, RUNE_GLOW[2], 150)

        # Sparkling splash crown in lower pool
        sx_p = int(round(27.5 + side * 16.8))
        put(sx_p, int(by) + 1, PURE_WHITE)
        shine(sx_p, int(by) + 1, RUNE_GLOW[3], 220)
        if (frame + (0 if side < 0 else 2)) % 2 == 0:
            put(sx_p - side, int(by), WATER[4])
            shine(sx_p - side, int(by), RUNE_GLOW[3], 175)

        # Rising cyan-gold mist sparkles near crown
        sp_t = (frame / 4.0 + (0.0 if side < 0 else 0.5)) % 1.0
        sp_x = int(round(27.5 + side * (4.5 + 1.5 * math.sin(sp_t * math.tau))))
        sp_y = int(round(9.0 - sp_t * 5.0))
        if sp_t < 0.75:
            put(sp_x, sp_y, RUNE_GLOW[3])
            shine(sp_x, sp_y, RUNE_GLOW[3], int(220 * (1.0 - sp_t)))

    return arr, glow


def _save_stage(Image, fl_arr, fl_glow, fn_fountain, fw, fh, foot, floor_name, fount_name, prev_name):
    Image.fromarray(fl_arr).save(ROOT / f"{floor_name}.png")
    if fl_glow is not None:
        Image.fromarray(fl_glow).save(ROOT / f"{floor_name}_glow.png")
    sheet = np.zeros((fh, fw * 4, 4), np.uint8)
    gsheet = np.zeros((fh, fw * 4, 4), np.uint8)
    for f in range(4):
        a, g = fn_fountain(f)
        sheet[:, f * fw:(f + 1) * fw] = a
        gsheet[:, f * fw:(f + 1) * fw] = g
    Image.fromarray(sheet).save(ROOT / f"{fount_name}.png")
    Image.fromarray(gsheet).save(ROOT / f"{fount_name}_glow.png")
    prev = Image.fromarray(fl_arr).copy()
    if fl_glow is not None:
        fg_im = Image.fromarray(fl_glow)
        fg_im.putalpha(fg_im.getchannel("A").point(lambda v: int(v * 0.35)))
        prev.alpha_composite(fg_im)
    fr = Image.fromarray(np.ascontiguousarray(sheet[:, :fw]))
    prev.alpha_composite(fr, (int(CX) - foot[0], int(CY) + 8 - foot[1]))
    prev.save(ROOT / f"{prev_name}.png")
    return prev


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    from PIL import Image

    prev1 = _save_stage(Image, floor(), None, fountain, FW, FH, FOOT, "plaza", "plaza_fountain", "plaza_preview")
    prev2 = _save_stage(Image, floor_2(), None, fountain_2, FW2, FH2, FOOT2, "plaza_2", "plaza_fountain_2", "plaza_2_preview")
    fl3, fl3_g = floor_3()
    prev3 = _save_stage(Image, fl3, fl3_g, fountain_3, FW3, FH3, FOOT3, "plaza_3", "plaza_fountain_3", "plaza_3_preview")

    if len(sys.argv) > 1:
        scale = 3
        pad = 8
        cw = (W * 3 + pad * 4) * scale
        ch = (H * 2 + pad * 3) * scale
        bg = Image.new("RGBA", (cw, ch), (58, 100, 62, 255))
        # Row 0: day on meadow; Row 1: night with glow!
        night_bar = Image.new("RGBA", (cw, H * scale + pad * 2 * scale), (16, 18, 34, 255))
        bg.paste(night_bar, (0, H * scale + pad * scale))
        stages = [
            ("plaza", None, "plaza_fountain", FW, FH, FOOT, prev1),
            ("plaza_2", None, "plaza_fountain_2", FW2, FH2, FOOT2, prev2),
            ("plaza_3", "plaza_3_glow", "plaza_fountain_3", FW3, FH3, FOOT3, prev3),
        ]
        for idx, (fl_n, flg_n, fn_n, fw, fh, foot, pv) in enumerate(stages):
            ox = (pad + idx * (W + pad)) * scale
            oy_day = pad * scale
            bg.alpha_composite(pv.resize((W * scale, H * scale), Image.NEAREST), (ox, oy_day))
            # Night composite with dark world tint + full unlit glow
            n_tile = Image.open(ROOT / f"{fl_n}.png").convert("RGBA")
            arr_n = np.array(n_tile, np.float32)
            arr_n[..., 0] *= 0.32
            arr_n[..., 1] *= 0.34
            arr_n[..., 2] *= 0.52
            n_img = Image.fromarray(arr_n.astype(np.uint8), "RGBA")
            if flg_n:
                n_img.alpha_composite(Image.open(ROOT / f"{flg_n}.png").convert("RGBA"))
            f_lit = Image.open(ROOT / f"{fn_n}.png").convert("RGBA").crop((0, 0, fw, fh))
            fa = np.array(f_lit, np.float32)
            fa[..., 0] *= 0.35
            fa[..., 1] *= 0.37
            fa[..., 2] *= 0.55
            n_img.alpha_composite(Image.fromarray(fa.astype(np.uint8), "RGBA"), (int(CX) - foot[0], int(CY) + 8 - foot[1]))
            f_glow = Image.open(ROOT / f"{fn_n}_glow.png").convert("RGBA").crop((0, 0, fw, fh))
            n_img.alpha_composite(f_glow, (int(CX) - foot[0], int(CY) + 8 - foot[1]))
            oy_night = (H + pad * 2) * scale
            bg.alpha_composite(n_img.resize((W * scale, H * scale), Image.NEAREST), (ox, oy_night))
        bg.save(sys.argv[1])

    print("plaza stages 1..3 written: floor %dx%d, fountains 56x48 / 56x56 / 56x64 x4" % (W, H))


if __name__ == "__main__":
    main()
