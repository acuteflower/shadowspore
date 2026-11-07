#!/usr/bin/env python3
"""Three ancient, overgrown pillars for the first boss arena (numpy + PIL, deterministic).
  assets/props/arena_pillars.png       192x128, 3 frames of 64x128, feet (32, 118) in every frame
  assets/props/arena_pillars_glow.png  same layout, only the emissive vein / crystal pixels (+ small halos)
  docs/img/arena_pillars.png           3x contact sheet: on the meadow green, and standing on the arena's flagstone floor
Built like the arena floor (tools/bake_ground.py flagstone): cut blocks in courses with dark mortar joints, 3-4 tones per
block, lit upper-left rims, Bayer-dithered grain, pitting, weathering streaks, chipped corners; moss and ivy in the floor's
greens. Stepped plinth, drums (some fluted), carved bands, astragal, echinus with egg-and-dart, abacus slab.
Light from the top left, 1 px ink outline. Emissive pixels (veins along cracks, crystal sprouts) live only in the glow sheet;
the base sheet keeps them as dark crevices / dim crystal.
Variants: 0 intact, ornate capital; 1 shorter, chipped abacus corner, more moss/ivy/roots, one long crack; 2 broken capital,
slight lean, missing chunk, chips at the foot, stronger vein.
Usage: py -3 tools/art_arena_pillars.py [contact_sheet_out.png]"""
import bisect
import math
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
W, H, FOOT = 64, 128, (32, 118)


def hx(c):
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# the arena floor's stone, as it shows in the game (the ground shader greys the raw STONE ramp of art_stone.py)
P = [hx(c) for c in ("1d1a2c", "342e41", "4c465c", "645e76", "7c768e", "958fa6", "b1abc2", "d3cee3")]
MORTAR = hx("1d1a2c")
MOSS = [hx(c) for c in ("2f624e", "3e7d56", "55985f", "7cb96d")]
MEADOW = [hx(c) for c in ("1d2748", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
ROOTC = [hx(c) for c in ("2a2133", "40344a", "5a4a5c", "7a6678")]
OUT = hx("1b1a2e")
TEAL, TEAL_L, VIO, VIO_L = hx("3cc0c6"), hx("78f4e6"), hx("8a4dff"), hx("d9c8ff")
CRY_D, CRY_M = hx("1f5a64"), hx("2f868c")  # dim crystal in the base sheet
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def hsh(x, y, s):
    n = (int(x) * 374761393 + int(y) * 668265263 + s * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, s):
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


class Seg:
    def __init__(self, name, kind, yt, yb, hw_t, hw_b, courses=None, dx=0.0, top=0, rows=None, **kw):
        self.name, self.kind, self.yt, self.yb = name, kind, yt, yb
        self.hw_t, self.hw_b, self.dx, self.top, self.rows = hw_t, hw_b, dx, top, rows
        self.courses = courses or [yb - yt - top]
        self.flute = kw.get("flute", False)
        self.band = kw.get("band")
        self.egg = kw.get("egg", False)
        self.beads = kw.get("beads", False)
        self.joints = []  # per course: sorted joint coordinates (theta for round, ux for box)
        self.cy = []  # course top rows


def layout(v):
    """Segments top -> bottom."""
    s = []
    if v == 0:
        s += [Seg("abacus", "box", 11, 16, 14.3, 14.3, top=2, rows=None),
              Seg("echinus", "bowl", 16, 25, 13.0, 9.8, egg=True, courses=[9]),
              Seg("astra", "round", 25, 28, 10.4, 10.4, beads=True, rows=[0.9, 0.2, -1.2]),
              Seg("d3", "round", 28, 46, 10.8, 11.1, courses=[9, 9], dx=0.3),
              Seg("band", "round", 46, 53, 12.0, 12.0, band="chev"),
              Seg("d2", "round", 53, 74, 11.5, 11.9, courses=[21], flute=True, dx=-0.4),
              Seg("ring", "round", 74, 77, 12.5, 12.5, rows=[1.0, 0.2, -1.3]),
              Seg("d1", "round", 77, 103, 11.8, 12.2, courses=[13, 13], dx=0.4)]
    elif v == 1:
        s += [Seg("abacus", "box", 22, 27, 13.6, 13.6, top=2),
              Seg("echinus", "bowl", 27, 36, 12.4, 9.7, egg=True, courses=[9]),
              Seg("astra", "round", 36, 39, 10.3, 10.3, beads=True, rows=[0.9, 0.2, -1.2]),
              Seg("d3", "round", 39, 47, 10.7, 10.9, courses=[8], dx=-0.4),
              Seg("band", "round", 47, 54, 11.8, 11.8, band="dia"),
              Seg("d2", "round", 54, 76, 11.3, 11.7, courses=[11, 11], dx=0.5),
              Seg("ring", "round", 76, 79, 12.4, 12.4, rows=[1.0, 0.2, -1.3]),
              Seg("d1", "round", 79, 103, 11.7, 12.1, courses=[24], flute=True, dx=-0.3)]
    else:
        s += [Seg("abacus", "box", 17, 21, 12.2, 12.2, top=0),
              Seg("echinus", "bowl", 21, 28, 11.4, 9.7, egg=True, courses=[7]),
              Seg("astra", "round", 28, 31, 10.3, 10.3, beads=True, rows=[0.9, 0.2, -1.2]),
              Seg("d3", "round", 31, 50, 10.7, 11.0, courses=[10, 9], dx=0.7),
              Seg("band", "round", 50, 57, 11.8, 11.8, band="chev"),
              Seg("d2", "round", 57, 77, 11.4, 11.8, courses=[10, 10], dx=-0.6),
              Seg("ring", "round", 77, 80, 12.4, 12.4, rows=[1.0, 0.2, -1.3]),
              Seg("d1", "round", 80, 103, 11.8, 12.2, courses=[23], flute=True, dx=0.3)]
    s += [Seg("plinth2", "box", 103, 110, 13.0, 13.0, top=2, courses=[5]),
          Seg("plinth1", "box", 110, 118, 14.5, 14.5, top=3, courses=[5])]
    return s


def setup_joints(segs, v):
    for si, sg in enumerate(segs):
        y = sg.yt + sg.top
        sg.cy = []
        for ci, ch in enumerate(sg.courses):
            sg.cy.append((y, ch))
            y += ch
            r = 100 + v * 31 + si * 7 + ci * 3
            js = []
            if sg.kind == "box":
                u = -1.2 + hsh(si, ci, r) * 0.6
                step = 0.8 if sg.name != "abacus" else 1.0
                while u < 1.3:
                    js.append(u)
                    u += step * (0.8 + hsh(len(js), si + ci, r) * 0.5)
            elif sg.band or sg.rows or sg.kind == "bowl" or sg.flute:
                js = []
            else:
                th = -math.pi / 2 - hsh(si, ci, r) * 1.0
                while th < math.pi / 2 + 0.3:
                    js.append(th)
                    th += 0.85 + hsh(len(js), si * 5 + ci, r) * 0.55
            sg.joints.append(sorted(js))


def seg_at(segs, y):
    for sg in segs:
        if sg.yt <= y < sg.yb:
            return sg
    return None


def hw_at(sg, ye):
    t = (ye - sg.yt) / max(1.0, sg.yb - sg.yt)
    t = min(max(t, 0.0), 1.0)
    if sg.kind == "bowl":
        tu = 1 - t
        return sg.hw_b + (sg.hw_t - sg.hw_b) * (tu ** 0.85)
    return sg.hw_t + (sg.hw_b - sg.hw_t) * t


def build(v):
    segs = layout(v)
    setup_joints(segs, v)
    top = segs[0].yt
    lean = [0.0, 0.0, 2.0][v]
    seed = 11 + v * 7
    mossy = {0: 0.85, 1: 1.45, 2: 1.15}[v]
    col = np.zeros((H, W, 3), np.uint8)
    mask = np.zeros((H, W), bool)
    lit_map = np.zeros((H, W), float)
    mortar = np.zeros((H, W), bool)
    topface = np.zeros((H, W), bool)
    segid = np.full((H, W), -1)
    val = np.zeros((H, W), float)
    ueff = np.zeros((H, W), float)
    cx_of = lambda y, sg: 32 + lean * (118 - y) / 100.0 + sg.dx

    # ---------- carving (broken parts) ----------
    def carved(x, y):
        if v == 1:  # chipped upper right corner of the abacus
            if y < top + 6 and x > 33 + 4.5 + (y - top) * 1.5:
                return True
        if v == 2:
            # jagged broken top: everything above the break is gone, the break steps down to the right
            xr = x - 32
            edge = top + 3 + int(2.2 * abs(math.sin(xr * .5)) + 1.8 * hsh(x, 0, 5))
            if xr > 1:
                edge += int((xr - 1) * 1.15)
            if xr < -9:
                edge += int((-9 - xr) * 0.9)
            if y < edge:
                return True
            # a missing chunk on the right of the upper drum
            if 38 < y < 49 and x > 39 + (y - 38) * 0.35 - abs(y - 43) * 0.55 + 6 * hsh(y, 2, 6) * 0.3:
                return x > 41 + hsh(y, 1, 7) * 2.5 + abs(y - 43) * 0.45
        # little chips in the silhouette
        return False

    # ---------- geometry + tone ----------
    for y in range(top, 118):
        for x in range(W):
            sg0 = seg_at(segs, y)
            if sg0 is None:
                continue
            cx0 = cx_of(y, sg0)
            hw0 = hw_at(sg0, y)
            u0 = (x + .5 - cx0) / hw0
            sg, ye = sg0, float(y)
            if sg0.kind in ("round", "bowl") and abs(u0) <= 1:
                nz0 = math.sqrt(max(0.0, 1 - u0 * u0))
                ye = min(y + 1.9 * (1 - nz0), 117.9)
                ye = max(ye, top)
                sg = seg_at(segs, int(ye)) or sg0
            cx = cx_of(y, sg)
            hw = hw_at(sg, ye)
            u = (x + .5 - cx) / hw
            if abs(u) > 1 or carved(x, y):
                continue
            mask[y, x] = True
            segid[y, x] = segs.index(sg)
            ueff[y, x] = u
            r_in = ye - sg.yt
            n_grain = (vnoise(x * .8, y * .45, seed) - .5) * .5 + (vnoise(x * 2.3, y * 1.4, seed + 3) - .5) * .3
            dith = (BAYER[y % 4, x % 4] - .5) * .55
            v_ = 0.0
            lit = 0.0
            if sg.kind == "box":
                if r_in < sg.top:  # top surface of the ledge: light, with a lit left and a shaded right
                    topface[y, x] = True
                    v_ = 5.0 + (-u * .5) + n_grain * .8 + dith * .8
                    if r_in < 0.9 and sg.name != "abacus":
                        v_ -= .5
                    lit = 1.0
                else:
                    v_ = 3.55 + n_grain + dith
                    if u < -0.86:
                        v_ += .75
                    if u > 0.8:
                        v_ -= .8
                    if u > 0.92:
                        v_ -= .7
                    lit = 0.45 - max(0, u - .4)
                    v_ = _courses(sg, ye, u, x, y, v_, seed, mortar, box=True)
            else:
                th = math.asin(max(-1.0, min(1.0, u)))
                nz = math.sqrt(max(0.0, 1 - u * u))
                lit = -0.8 * u + 0.55 * nz
                v_ = 3.1 + 1.45 * lit + n_grain + dith
                if sg.kind == "bowl":
                    tu = (sg.yb - ye) / (sg.yb - sg.yt)
                    v_ += 0.55 + (tu - .5) * .8
                    if sg.egg and .35 < tu < .75:
                        ph = (th / 0.52) % 1.0
                        row = tu
                        if abs(ph - 0.5) < 0.1 and abs(u) < .93:  # dart between the eggs
                            v_ -= 2.0 if row < .6 else .8
                        elif abs(ph - 0.0) < 0.1 or abs(ph - 1.0) < 0.1:
                            v_ += .35
                    v_ = _courses(sg, ye, u, x, y, v_, seed, mortar, box=False, th=th, hw=hw)
                elif sg.rows is not None:
                    ri = int(r_in)
                    v_ += sg.rows[min(ri, len(sg.rows) - 1)]
                    if sg.beads and ri == 1:
                        v_ += 0.9 if int((th + 3.2) / 0.3) % 2 == 0 else -0.6
                elif sg.band:
                    v_ = _band(sg, int(r_in), th, v_)
                else:
                    if sg.flute and abs(th) < 1.2:
                        ph = (th / 0.43) % 1.0
                        dgr = (ph - 0.5) * 0.43 * hw
                        if abs(dgr) < 0.55:
                            v_ -= 1.3
                        elif 0.55 <= dgr < 1.5:
                            v_ += 0.35
                        elif -1.5 < dgr <= -0.55:
                            v_ -= .35
                    v_ = _courses(sg, ye, u, x, y, v_, seed, mortar, box=False, th=th, hw=hw)
            # shade under an overhanging ledge above
            idx = segs.index(sg)
            if idx > 0:
                above = segs[idx - 1]
                if above.kind != "bowl" or True:
                    if above.hw_b > sg.hw_t + 0.8 and r_in < 2.2 and sg.kind != "box":
                        v_ -= 1.2 if r_in < 1.2 else 0.6
            # pitting and flecks: short horizontal strokes (like the floor's grain)
            h1 = hsh(x // 2, y, seed + 7)
            if h1 > 0.945:
                v_ -= 1.0
            elif h1 < 0.02:
                v_ += 0.9
            # weathering streaks running down from ledges / joints
            stn = vnoise(x * 0.9, y * 0.07, seed + 13)
            if stn > 0.66 and BAYER[y % 4, x % 4] < (stn - 0.62) * 5:
                v_ -= 0.7
            # scratches: short diagonal strokes
            gx, gy = x // 5, y // 6
            if hsh(gx, gy, seed + 95) > 0.88 and sg.kind != "box" or (sg.kind == "box" and hsh(gx, gy, seed + 96) > .93):
                ddx, ddy = x - gx * 5, y - gy * 6
                if ddy == ddx + 1 and 0 <= ddx <= 3:
                    v_ -= 0.9
                elif ddy == ddx + 2 and 0 <= ddx <= 2:
                    v_ += 0.45
            val[y, x] = v_
            lit_map[y, x] = lit

    # ---------- chips: dark notch + lit break at silhouette seams ----------
    rng_chips = {0: [(21, 103, 1), (44, 77, 1), (22, 28, 1)], 1: [(20, 79, 2), (45, 54, 1), (44, 76, 1), (21, 103, 1)],
                 2: [(20, 80, 2), (46, 57, 2), (22, 104, 1), (44, 110, 1), (20, 50, 1)]}[v]
    for (cxp, cyp, r) in rng_chips:
        for dy in range(0, r + 2):
            for dx in range(0, r + 2):
                xx, yy = cxp + (dx if cxp > 32 else -dx), cyp + dy
                if 0 <= xx < W and 0 <= yy < H and dx + dy <= r + 1 and mask[yy, xx]:
                    if dx + dy <= r:
                        mask[yy, xx] = False
                    else:
                        val[yy, xx] += 1.0 if cxp < 32 else -0.8

    # quantise
    for y, x in zip(*np.where(mask)):
        if mortar[y, x]:
            col[y, x] = MORTAR if hsh(x, y, seed + 21) < .9 else P[1]
        else:
            col[y, x] = P[int(np.clip(math.floor(val[y, x]), 1, 7))]

    # broken joints: stone corners crumble into the mortar, mortar bites into the stone
    snap = col.copy()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not mask[y, x] or mortar[y, x]:
                continue
            h2 = hsh(x, y, seed + 88)
            if mortar[y - 1, x] and h2 > 0.84:
                col[y, x] = P[1] if h2 > .93 else P[2]
            elif mortar[y, x - 1] and h2 > 0.9:
                col[y, x] = P[2]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if mask[y, x] and mortar[y, x] and hsh(x, y, seed + 89) > .93:
                nb = snap[y + 1, x] if mask[y + 1, x] and not mortar[y + 1, x] else (snap[y, x - 1] if mask[y, x - 1] and not mortar[y, x - 1] else P[2])
                col[y, x] = nb
                mortar[y, x] = False
    ys, xs = np.where(mask)
    stone_px = list(zip(ys, xs))

    # ---------- cracks (follow joints, jump along mortar rows) ----------
    seam_rows = [sg.yb - 1 for sg in segs]
    cracks = []  # list of dicts: pts, power

    def crack(x0, y0, length, drift, s, power=1.0, branch=True):
        x, y = float(x0), int(y0)
        pts = []
        for i in range(length):
            y += 1
            x += (hsh(i, s, 3) - .5 + drift) * 0.75
            xi = int(round(x))
            if 0 <= xi < W and 0 <= y < H and mask[y, xi]:
                pts.append((xi, y))
            if (y in seam_rows or hsh(i, s, 4) > .96) and hsh(i, s, 5) > .5:
                d = 1 if hsh(i, s, 6) > .5 else -1
                for _ in range(1 + int(hsh(i, s, 7) * 3)):
                    x += d
                    xi = int(round(x))
                    if 0 <= xi < W and mask[y, xi]:
                        pts.append((xi, y))
        cracks.append({"pts": pts, "power": power})
        if branch and len(pts) > 14:
            j = int(len(pts) * (.35 + .3 * hsh(s, 1, 8)))
            bx, by = pts[j]
            crack(bx, by, max(6, length // 3), (0.45 if hsh(s, 2, 9) > .5 else -0.45), s + 50, power * .6, False)

    hair = {0: [(25, 31, 9, .1, 11), (40, 79, 12, -.1, 12), (22, 58, 14, .12, 13), (41, 92, 9, 0, 14)],
            1: [(37, 41, 10, -.1, 15), (23, 60, 12, .1, 16), (42, 66, 14, -.05, 17), (26, 92, 10, .05, 18), (36, 28, 5, 0, 19)],
            2: [(41, 60, 12, -.1, 20), (24, 38, 9, .1, 21), (37, 84, 11, .05, 22), (22, 100, 8, 0, 23)]}[v]
    for (hx0, hy0, hl, hd, hs) in hair:
        crack(hx0, hy0, hl, hd, hs, 0.0, False)
    if v == 0:
        crack(36, 56, 36, 0.03, 1, 1.0)
        crack(26, 86, 14, -.1, 2, .5, False)
    elif v == 1:
        crack(30, 30, 80, 0.02, 3, 1.0)
        crack(36, 84, 14, .2, 4, .6, False)
    else:
        crack(34, 38, 52, .08, 5, 1.0)
        crack(27, 84, 20, -.12, 6, .8)
        crack(38, 22, 10, .1, 7, .8, False)
    crack_px = {}
    for ck in cracks:
        for i, (x, y) in enumerate(ck["pts"]):
            crack_px[(x, y)] = (i / max(1, len(ck["pts"])), ck["power"])
    for (x, y), _ in crack_px.items():
        col[y, x] = MORTAR
        if x + 1 < W and mask[y, x + 1] and (x + 1, y) not in crack_px and hsh(x, y, 61) > .45:
            col[y, x + 1] = P[min(7, max(1, int(val[y, x + 1]) + 1))]

    # ---------- moss ----------
    is_bright = np.zeros((H, W), bool)
    for y, x in stone_px:
        sg = segs[segid[y, x]]
        r_in = y - sg.yt
        p = 0.0
        if y > 92:
            p += (1.0 - max(0.0, (118 - y) / 26.0)) * 0.34
        if topface[y, x]:
            p += 0.55
        elif sg.kind != "box" and r_in < 2:
            p += 0.5
        if mortar[y, x]:
            p += 0.28
        if ueff[y, x] > 0.15:
            p += 0.3 * ueff[y, x]
        if sg.name in ("ring", "astra") and r_in < 1:
            p += 0.4
        n = vnoise(x * .24, y * .2, seed + 20) * .75 + vnoise(x * .8, y * .6, seed + 30) * .35
        if y < 62 and not topface[y, x]:
            p *= 0.5
        p = p * mossy + (vnoise(x * .13, y * .1, seed + 40) - .6) * 1.5 * mossy
        thr = 0.6 + (BAYER[y % 4, x % 4] - .5) * 0.5
        if p * (0.62 + n) > thr and (x, y) not in crack_px:
            lit = lit_map[y, x]
            m = 1 if lit < 0.0 else (3 if (lit > .5 and hsh(x, y, seed + 72) > .6) else 2)
            if topface[y, x]:
                m = 3 if hsh(x, y, seed + 73) > .45 else 2
            if BAYER[(y + 2) % 4, (x + 1) % 4] > .83 and m > 0:
                m -= 1
            if hsh(x, y, seed + 70) > .93:
                m = min(3, m + 1)
            col[y, x] = MOSS[m]
            is_bright[y, x] = m == 3
        elif p * (0.62 + n) > thr - 0.28 and hsh(x, y, seed + 71) > .55 and not mortar[y, x]:
            # damp, dark stain at the fringe of a patch
            col[y, x] = P[max(1, int(val[y, x]) - 1)]

    # ---------- fallen chunks at the foot (inside the frame) ----------
    def chunk(cxp, by, w_, h_, tone, s):
        for dy in range(-h_, 1):
            left = -w_ + (2 if dy == -h_ else (1 if dy == -h_ + 1 else 0)) + (1 if dy == 0 else 0)
            right = w_ - (3 if dy == -h_ else (1 if dy == -h_ + 1 else 0)) - (1 if dy == 0 else 0)
            for dx in range(left, right + 1):
                x, y = cxp + dx, by + dy
                if not (0 <= x < W and 0 <= y < H):
                    continue
                mask[y, x] = True
                f = (dx - left) / max(1, right - left)
                t = tone + (BAYER[y % 4, x % 4] - .5) * .6 + (hsh(x, y, s) - .5) * .5
                if dy <= -h_ + 1:
                    t += 1.4
                elif f > .7:
                    t -= 1.2
                elif f < .2:
                    t += .6
                if dy == 0:
                    t -= 1.0
                c = P[int(np.clip(math.floor(t), 1, 6))]
                if dy <= -h_ + 1 and hsh(x, y, s + 3) > .5:
                    c = MOSS[2 if hsh(x, y, s + 4) > .5 else 1]
                col[y, x] = c
                segid[y, x] = 0

    chunks = {0: [(14, 121, 4, 5, 3.2, 1), (51, 122, 3, 4, 3.0, 2)],
              1: [(13, 120, 4, 4, 3.1, 3), (51, 121, 5, 6, 3.3, 4), (39, 125, 2, 2, 3.0, 5), (43, 112, 2, 2, 3.2, 10)],
              2: [(12, 121, 5, 6, 3.2, 6), (52, 123, 4, 5, 3.0, 7), (23, 125, 2, 2, 3.2, 8), (43, 126, 3, 2, 2.9, 9), (21, 112, 2, 2, 3.1, 11)]}[v]
    for c in chunks:
        chunk(*c)

    # ---------- glowing veins along the cracks ----------
    vein = {}  # (x,y) -> intensity 0..1
    for ci, ck in enumerate(cracks):
        n = len(ck["pts"])
        i = 0
        on = True
        while i < n:
            run = 2 + int(hsh(i, ci, 81) * 5) if on else 2 + int(hsh(i, ci, 82) * 5)
            for j in range(i, min(n, i + run)):
                if on:
                    fade = 1.0 - 0.85 * (j / max(1, n))
                    x, y = ck["pts"][j]
                    vein[(x, y)] = max(0.0, min(1.0, ck["power"] * fade * (0.75 + 0.5 * hsh(x, y, 83))
                                               * (1.25 if v == 2 else 1.0)))
            i += run
            on = not on
    for (x, y), it in vein.items():
        col[y, x] = MORTAR

    # ---------- ivy (spiral round the shaft), roots ----------
    deco = []  # (x, y, color) painted over everything, may stick out of the silhouette

    def vine(y_from, y_to, phase0, turns, amp, s, bright=0):
        n = abs(y_to - y_from)
        sgn = 1 if y_to > y_from else -1
        for i in range(n):
            y = y_from + sgn * i
            sg = seg_at(segs, y)
            if sg is None or sg.kind == "box":
                continue
            ph = phase0 + turns * i / 18.0 + 0.8 * math.sin(i * .21 + s)
            if math.cos(ph) < 0.05:
                continue
            xx = int(round(cx_of(y, sg) + hw_at(sg, y) * amp * math.sin(ph)))
            if not mask[y, xx]:
                continue
            deco.append((xx, y, MEADOW[1]))
            if i % 2 == 0:
                deco.append((xx + 1 if math.sin(ph) < 0.5 else xx - 1, y, MEADOW[2]))
            if i % 5 == 2:  # a leaf pair
                d = 1 if (i // 5 + s) % 2 == 0 else -1
                for (ox, oy, c) in ((d, 0, 3 + bright), (2 * d, -1, 4), (d, -1, 4), (2 * d, 0, 3), (d, 1, 2)):
                    if mask[y + oy, min(W - 1, max(0, xx + ox))]:
                        deco.append((xx + ox, y + oy, MEADOW[c]))
            if i % 9 == 4:  # a hanging tendril
                for k in range(1, 3 + int(hsh(i, s, 84) * 3)):
                    if mask[y + k, xx]:
                        deco.append((xx, y + k, MEADOW[2 if k % 2 else 3]))

    def root(x0, y0, pts_up, thick, s):
        """A root crawling up the plinth: (dx, dy) steps from the ground."""
        x, y = x0, y0
        for (dx, dy) in pts_up:
            for t in range(max(abs(dx), abs(dy), 1)):
                x += int(np.sign(dx)) if abs(dx) > t else 0
                y += int(np.sign(dy)) if abs(dy) > t else 0
                for k in range(thick):
                    c = ROOTC[1 if k else 2]
                    if k == 0:
                        c = ROOTC[3] if hsh(x, y, s) > .55 else ROOTC[2]
                    if k == thick - 1:
                        c = ROOTC[0]
                    deco.append((x, y + k, c))

    if v == 0:
        vine(68, 100, 0.4, 2.6, 0.85, 1)
        root(48, 121, [(-2, -3), (-1, -4), (0, -3)], 2, 3)
    elif v == 1:
        vine(48, 100, 0.2, 4.6, 0.88, 2)
        vine(70, 98, 3.4, 3.0, 0.8, 3, 1)
        vine(96, 52, 2.2, 3.2, 0.82, 5)
        root(17, 122, [(2, -3), (3, -4), (1, -5), (0, -4)], 3, 4)
        root(49, 122, [(-2, -4), (-2, -4), (0, -4)], 2, 6)
    else:
        vine(60, 100, 1.5, 3.4, 0.86, 4)
        root(46, 122, [(-2, -3), (-1, -4), (-1, -4)], 3, 5)
        root(19, 122, [(2, -3), (0, -4)], 2, 7)

    # ---------- outline ----------
    out = np.zeros((H, W, 4), float)
    # soft ground shadow with a dithered rim
    for y in range(H):
        for x in range(W):
            d = ((x + .5 - 33) / 23.0) ** 2 + ((y + .5 - 120) / 5.4) ** 2
            if d < 1.0:
                a = 84 if d < 0.5 else (66 if BAYER[y % 4, x % 4] * 0.9 + 0.1 < (1.0 - d) * 2.2 else 0)
                if a:
                    out[y, x] = (*P[0], a)
    for y, x in zip(*np.where(mask)):
        out[y, x] = (*col[y, x], 255)
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not mask[y, x] and (mask[y - 1, x] or mask[y + 1, x] or mask[y, x - 1] or mask[y, x + 1]):
                out[y, x] = (*OUT, 255)
    # inner dark line under big overhangs is already in the tone; deco over everything
    for (x, y, c) in deco:
        if 0 <= x < W and 0 <= y < H:
            out[y, x] = (*c, 255)

    # ---------- foliage on ledges, hanging moss, grass at the foot ----------
    def blades(tx, ty, n, hmax, s, palette=MEADOW):
        for b in range(n):
            bx = tx + b - n // 2
            hgt = max(2, 2 + int(hsh(bx, tx, s) * (hmax - 2)) - abs(b - n // 2) // 2)
            lean = -1 if hsh(bx, s, 15) > .5 else 1
            for j in range(hgt):
                xx = bx + (lean if j >= hgt - 2 and hgt > 3 else 0)
                yy = ty - j
                if 0 <= xx < W and 0 <= yy < H:
                    out[yy, xx] = (*palette[min(5, 2 + (j * 4) // hgt + (b % 2))], 255)

    def strands(x0, x1, y0, s, dens=0.5, maxl=7):
        for x in range(x0, x1):
            if hsh(x, y0, s) < dens:
                L = 2 + int(hsh(x, y0, s + 1) ** 1.5 * maxl)
                for k in range(L):
                    yy = y0 + k
                    if 0 <= yy < H:
                        c = MOSS[2 if k < L - 1 else 1] if (x + k) % 3 else MOSS[3]
                        out[yy, x] = (*c, 255)

    ab = segs[0]
    if v == 0:
        strands(21, 44, ab.yb, 31, .5, 5)       # under the abacus
        blades(24, ab.yt + 1, 4, 4, 41)
        blades(41, 108, 4, 5, 42)
        blades(24, 111, 4, 5, 43)
        blades(18, 118, 5, 6, 44); blades(47, 119, 5, 5, 45)
        strands(20, 30, 103, 32, .55, 5); strands(36, 44, 77, 33, .5, 6)
    elif v == 1:
        strands(23, 42, ab.yb, 34, .6, 8)
        blades(27, ab.yt, 3, 4, 51)
        blades(20, 109, 4, 5, 52)
        blades(40, 102, 5, 6, 53)
        blades(17, 118, 5, 6, 54); blades(30, 120, 4, 5, 55); blades(47, 118, 6, 6, 56)
        strands(24, 40, 36, 35, .55, 7); strands(21, 30, 79, 36, .5, 7); strands(35, 44, 103, 37, .6, 6)
    else:
        blades(26, ab.yt + 5, 3, 4, 61)
        blades(21, 109, 4, 5, 62); blades(44, 102, 4, 6, 63)
        blades(17, 118, 4, 5, 64); blades(46, 119, 5, 6, 65); blades(32, 121, 3, 4, 66)
        strands(24, 41, 28, 38, .55, 6); strands(22, 32, 80, 39, .5, 6); strands(37, 46, 103, 40, .55, 5)

    # ---------- emissive: veins + crystals ----------
    G = np.zeros((H, W, 4), float)
    strong = v == 2
    for (x, y), it in vein.items():
        if it < 0.18 or not mask[y, x]:
            continue
        if it > 0.68:
            violet = hsh(x, y, 90) > .86
            G[y, x] = (*(VIO_L if violet else TEAL_L), 255)
        else:
            G[y, x] = (*(TEAL), 90 + int(it * 280))
    for (x, y), it in list(vein.items()):
        if it <= 0.68 or not mask[y, x]:
            continue
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            xx, yy = x + dx, y + dy
            if mask[yy, xx] and G[yy, xx, 3] < 110 and (xx, yy) not in vein:
                G[yy, xx] = (*TEAL, 40 + int(it * 34) + (22 if strong else 0))
        if strong:
            for dx, dy in ((-1, -1), (1, 1), (-1, 1), (1, -1)):
                xx, yy = x + dx, y + dy
                if mask[yy, xx] and G[yy, xx, 3] == 0:
                    G[yy, xx] = (*VIO, 40)

    def crystal(x, y, h, lean, s):
        """A small cluster of crystal sprouts on the stone: dim in the base sheet, bright tip only in the glow sheet."""
        for k, (dx, hh) in enumerate(((0, h), (-1, max(2, h - 2)), (2, max(2, h - 3)))):
            for j in range(hh):
                xx = x + dx + (lean if j > hh // 2 and k != 1 else 0)
                yy = y - j
                if not (0 <= xx < W and 0 <= yy < H):
                    continue
                tip = j >= hh - 2
                out[yy, xx] = (*(CRY_M if (j % 2 == 0 and dx <= 0) else CRY_D), 255)
                if j == 0:
                    out[yy, xx] = (*MORTAR, 255)
                if tip and j > 0:
                    G[yy, xx] = (*(TEAL_L if k == 0 else TEAL), 255 if k == 0 else 200)
            xx = x + dx
            if 0 <= xx < W and 0 <= y - hh < H and out[y - hh, xx, 3] == 0:
                out[y - hh, xx] = (*OUT, 255)
        for dx in (-2, -1, 0, 1, 2, 3):
            for dy in (-h - 1, -h, -2, -1):
                xx, yy = x + dx, y + dy
                if 0 <= xx < W and 0 <= yy < H and G[yy, xx, 3] == 0 and mask[yy, xx] and hsh(xx, yy, s) > .7:
                    G[yy, xx] = (*TEAL, 46)

    cr = {0: [(35, 101, 4, 0), (38, 62, 3, 1)],
          1: [(28, 52, 3, 1), (31, 96, 4, 1), (39, 108, 3, 0)],
          2: [(35, 60, 4, 1), (29, 94, 5, 1), (37, 47, 3, 0), (43, 101, 3, -1)]}[v]
    for (x, y, h, ln) in cr:
        crystal(x, y, h, ln, 91 + x)
    return out, G


def _courses(sg, ye, u, x, y, v_, seed, mortar, box, th=None, hw=None):
    """Cut blocks in courses: mortar row at each course's last row, lit top / shaded bottom rim, staggered vertical joints,
    a tone shift per block."""
    r = ye - sg.yt
    ci = 0
    for i, (ct, ch) in enumerate(sg.cy):
        if ct <= ye < ct + ch or i == len(sg.cy) - 1:
            ci = i
            if ct <= ye < ct + ch:
                break
    ct, ch = sg.cy[ci]
    rr = int(ye - ct)
    if rr >= ch - 1:
        mortar[y, x] = True
        return 0.0
    v_ += (0.5 - rr / max(1.0, ch - 1.0)) * 0.55
    if rr == ch - 2:
        v_ -= 0.65
    if rr == 0 and (ct > sg.yt + sg.top or sg.kind == "box"):
        v_ += 0.6
    js = sg.joints[ci]
    if not js:
        v_ += (hsh(ci, sg.yt, seed + 2) - .5) * 0.5
        return v_
    coord = u if box else th
    bi = bisect.bisect(js, coord)
    left = js[bi - 1] if bi > 0 else None
    right = js[bi] if bi < len(js) else None
    # distance to joints in px
    if box:
        dl = (coord - left) * hw_box(sg) if left is not None else 99
        dr = (right - coord) * hw_box(sg) if right is not None else 99
    else:
        dl = (u - math.sin(left)) * hw if left is not None and abs(left) < math.pi / 2 else 99
        dr = (math.sin(right) - u) * hw if right is not None and abs(right) < math.pi / 2 else 99
    if dl < 0.5 or dr < 0.5:
        mortar[y, x] = True
        return 0.0
    if dl < 1.5:
        v_ += 0.7
    if dr < 1.6:
        v_ -= 0.8
    shift = (-1.15, -0.5, 0.0, 0.55, 1.05)[int(hsh(bi, ci * 7 + sg.yt, seed + 5) * 5) % 5]
    return v_ + shift


def hw_box(sg):
    return sg.hw_t


def _band(sg, ri, th, v_):
    """Carved band: raised fillets top and bottom, a chevron (or diamond) relief between."""
    n = sg.yb - sg.yt
    if ri == 0:
        return v_ + 0.9
    if ri == n - 1:
        return v_ - 1.4
    if ri == n - 2:
        return v_ - 0.5
    ph = (th / 0.62) % 1.0
    if sg.band == "chev":
        zz = abs(ph * 2 - 1) * 2.0
        for off in (1.2, 3.0):
            if abs(ri - (off + zz)) < 0.55:
                return v_ - 2.4
            if 0.55 <= ri - (off + zz) < 1.5:
                return v_ + 1.0
        return v_ + 0.1
    zz = abs(ph * 2 - 1) * 2.4
    d = zz + abs(ri - 3.0)
    if abs(d - 2.5) < 0.6:
        return v_ - 2.2
    if d < 0.8:
        return v_ + 1.2
    return v_ + 0.1


# ------------------------------------------------------------------ contact sheet
def floor_strip(w, h):
    """A strip of the real arena floor (assets/world/ground/boss_arena_arena.png) in its in-game greys, on the meadow."""
    p = ROOT / "assets/world/ground/boss_arena_arena.png"
    bg = Image.new("RGBA", (w, h), (0x3e, 0x7d, 0x56, 255))
    if not p.exists():
        return bg
    a = np.array(Image.open(p).convert("RGBA")).astype(int)
    raw = [hx(c) for c in ("1c1a34", "2e2a52", "47436f", "665f94", "8a83b8", "d0cbec")]
    tgt = [hx(c) for c in ("342e41", "4c4658", "645e72", "7c748c", "9a8ea6", "bdb0c8")]
    rawa = np.array(raw)
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            if a[y, x, 3] == 0:
                continue
            c = a[y, x, :3]
            d = np.abs(rawa - c).sum(1)
            k = int(d.argmin())
            if d[k] < 60:
                a[y, x, :3] = tgt[k]
            elif tuple(c) == hx("14112a"):
                a[y, x, :3] = MORTAR
    img = Image.fromarray(a.astype(np.uint8), "RGBA")
    x0, y0 = 40, 90
    crop = img.crop((x0, y0, x0 + w, y0 + h))
    bg.alpha_composite(crop)
    return bg


def main():
    sheet = np.zeros((H, W * 3, 4), np.uint8)
    glow = np.zeros_like(sheet)
    for v in range(3):
        a, g = build(v)
        sheet[:, W * v:W * (v + 1)] = np.clip(a, 0, 255).astype(np.uint8)
        glow[:, W * v:W * (v + 1)] = np.clip(g, 0, 255).astype(np.uint8)
    (ROOT / "assets/props").mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(ROOT / "assets/props/arena_pillars.png")
    Image.fromarray(glow, "RGBA").save(ROOT / "assets/props/arena_pillars_glow.png")

    def comp(bg):
        bg.alpha_composite(Image.fromarray(sheet, "RGBA"))
        bg.alpha_composite(Image.fromarray(glow, "RGBA"))
        return bg
    top = comp(Image.new("RGBA", (W * 3, H), (0x3e, 0x7d, 0x56, 255)))
    bot = comp(floor_strip(W * 3, H))
    both = Image.new("RGBA", (W * 3, H * 2), (0, 0, 0, 255))
    both.paste(top, (0, 0))
    both.paste(bot, (0, H))
    both = both.resize((W * 3 * 3, H * 2 * 3), Image.NEAREST)
    outp = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/img/arena_pillars.png"
    outp.parent.mkdir(parents=True, exist_ok=True)
    both.save(outp)
    print("wrote", outp)


if __name__ == "__main__":
    main()
