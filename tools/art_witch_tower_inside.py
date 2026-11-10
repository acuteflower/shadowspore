#!/usr/bin/env python3
"""The inside of the witch's tower (docs/hexenwald_nebel_konzept.md): two ROUND rooms for the interior system (data/interiors.json, src/world/interior.gd).

  * witch_stairs: the keep's shaft. A round flagstone floor with a glowing sign in its middle, the cold slate wall going up into shadow, and a spiral
    stair that climbs along the inside of the wall from the east over the north to the west (runes on the wall light every third step, candle niches,
    green-lit slits); where it reaches the cut-away near wall it goes on up: the passage to the room above.
  * witch_room: the timber chamber under the hat. Dark planks, a round rug with a moon, the stair's head in the floor, shelves of jars on the curved
    wall, two windows into the fog, and the witch's workplace: a curved counter she stands behind and the big alchemy cauldron on its hearth behind her.

The rooms are painted per pixel from their geometry (a cylinder seen like every room of the game: the floor straight down, heights straight up), so
the stair is real: every tread, riser and the stair's inner face are found by depth. Furniture is built from ellipsoids with the tower's own renderer
and colours (tools/art_witch_tower.py). Writes assets/interior/witch_tower/*.png and the two entries of data/interiors.json (colliders included).

    py -3 tools/art_witch_tower_inside.py [preview.png]"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import BAYER, FIRE, GAP, IRON, LINEN, STRAW, CLAY, WAX, ROOT, V, glow_of, grain, log, rng_for, save, slab, to_array  # noqa: E402
import art_witch_tower as wt  # noqa: E402
from art_witch_tower import BONE, BREW, CSTONE, CSTONE_L, HAG, HAG_L, HAIRM, HEXG, HOODM, LEAF, SILVER, WINE, WOODP, WOODP_L, facing, rot_z  # noqa: E402
from gen_art import hexc  # noqa: E402
from hut_yard import campfire_frames  # noqa: E402

OUT = ROOT / "interior" / "witch_tower"
DATA = ROOT.parent / "data" / "interiors.json"
DIR = "res://assets/interior/witch_tower/"
T = 10  # the wall's thickness (its cut top)
LIT = (HEXG, BREW, FIRE)
GRAINED = (WOODP, WOODP_L, HAG, HAG_L, IRON, BONE, LEAF, HAIRM, CSTONE, CSTONE_L)
BAY = np.array(BAYER, float) / 16.0


def vh(a, b, s=0):
    """A hash of two whole-number arrays, 0..1."""
    n = (np.asarray(a, np.int64) * 73856093) ^ (np.asarray(b, np.int64) * 19349663) ^ (s * 83492791)
    n = ((n ^ (n >> 13)) & 0xFFFFF) * 1274126177
    return ((n >> 7) & 0xFFFF) / 65536.0


def vnoise(x, y, s=0):
    xi, yi = np.floor(x), np.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = vh(xi, yi, s), vh(xi + 1, yi, s), vh(xi, yi + 1, s), vh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


class Canvas:
    """What the room is painted on: per pixel a depth key (bigger = nearer), a material, a shade (0..3, fractions are dithered) and whether it shines."""

    def __init__(self, w, hh):
        self.w, self.h = w, hh
        self.ys, self.xs = np.mgrid[0:hh, 0:w]
        self.key = np.full((hh, w), -1e9)
        self.mat = np.full((hh, w), -1, int)
        self.band = np.zeros((hh, w))
        self.emit = np.zeros((hh, w), bool)

    def put(self, mask, key, mat, band, emit=False):
        m = mask & (key > self.key)
        self.key = np.where(m, key, self.key)
        self.mat = np.where(m, mat, self.mat)
        self.band = np.where(m, band, self.band)
        self.emit = np.where(m, emit, self.emit)

    def paint(self, mask, mat, band, emit=False):
        """Over whatever is there (details on a surface)."""
        self.mat = np.where(mask, mat, self.mat)
        self.band = np.where(mask, band, self.band)
        self.emit = np.where(mask, emit, self.emit)

    def stamp(self, x, y, rows, pal):
        """A little upright picture with its bottom middle on (x, y); pal: char -> (material, shade, shines)."""
        x0, y0 = int(round(x)) - len(rows[0]) // 2, int(round(y)) - len(rows) + 1
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch in pal and 0 <= y0 + j < self.h and 0 <= x0 + i < self.w and self.mat[y0 + j, x0 + i] >= 0:
                    mat, band, emit = pal[ch]
                    self.mat[y0 + j, x0 + i], self.band[y0 + j, x0 + i], self.emit[y0 + j, x0 + i] = mat, band, emit

    def image(self, mask=None, dither=0.7):
        ramps = np.array([[c[:3] for c in row] for row in h.RAMPS], np.uint8)
        b = np.clip(np.floor(self.band + (BAY[self.ys % 4, self.xs % 4] - 0.5) * dither + 0.5), 0, 3).astype(int)
        ok = self.mat >= 0 if mask is None else (self.mat >= 0) & mask
        arr = np.zeros((self.h, self.w, 4), np.uint8)
        arr[..., :3] = ramps[np.maximum(self.mat, 0), b]
        arr[..., 3] = np.where(ok, 255, 0)
        arr[~ok] = 0
        glow = arr.copy()
        glow[~(ok & self.emit)] = 0
        return arr, glow


# ------------------------------------------------------------------ surfaces
def stone(u, v, seed, ch=8.0, cw=14.0):
    """Courses of blocks in wall space (u along, v up): (shade offset, joint, lighter stone)."""
    row = np.floor(v / ch)
    uu = u + vh(row, 0, seed) * cw
    col = np.floor(uu / cw)
    lu, lv = uu - col * cw, v - row * ch
    joint = (lu < 1.1) | (lv < 1.0)
    j = vh(col, row, seed + 1)
    d = np.where(j > 0.78, 0.8, np.where(j < 0.2, -0.7, 0.0)) + np.where(lv > ch - 1.6, 0.7, 0.0) - np.where(lv < 2.2, 0.45, 0.0)
    return d, joint, vh(col, row, seed + 2) > 0.84


class Room:
    """A round room of radius R with a far wall WH high: floor (cx, cy), east = +x, north = up the screen, heights straight up."""

    def __init__(self, R, WH):
        self.R, self.WH = R, WH
        self.w, self.h = 2 * (R + T), WH + 2 * (R + T)
        self.cx, self.cy = R + T, R + T + WH
        self.c = Canvas(self.w, self.h)
        self.px = self.c.xs + 0.5 - self.cx
        self.sy = self.c.ys + 0.5
        self.front = np.zeros((self.h, self.w), bool)  # the near wall's cut top: its own picture, over the people

    def wall_xy(self, theta, v, r=None):
        r = self.R if r is None else r
        return self.cx + r * math.cos(theta), self.cy - r * math.sin(theta) - v

    def floor(self, fn):
        north = self.cy - self.sy
        r = np.hypot(self.px, north)
        mat, band, emit = fn(self.px, north, r, np.arctan2(north, self.px))
        band = band - np.clip((r - (self.R - 7)) / 7.0, 0, 1) * 0.9  # dark where it meets the wall
        self.c.put(r < self.R, -north, mat, band, emit)

    def wall(self, fn):
        R = self.R
        inside = np.abs(self.px) < R
        north = np.sqrt(np.maximum(R * R - self.px ** 2, 0.0))
        v = self.cy - north - self.sy
        theta = np.arctan2(north, self.px)
        mat, band, emit = fn(theta * R, v, theta)
        self.c.put(inside & (v >= 0) & (v < self.WH), -north + v, mat, band, emit)

    def rim(self, mat=CSTONE):
        """The wall's cut top: on the far wall at its height, on the near half at the floor (that part is the front picture), the wall's section between."""
        R, c = self.R, self.c
        for near in (False, True):
            north = self.cy - self.sy - (0 if near else self.WH)
            r = np.hypot(self.px, north)
            a = np.arctan2(north, self.px)
            ring = (r >= R) & (r < R + T) & ((north < 0) if near else (north >= 0))
            seg = np.floor(a * R / 13.0)
            joint = (np.abs(a * R / 13.0 - seg) < 0.09) | (np.abs(r - R - T / 2) < 0.5) & (vh(seg, 3, 9) > 0.5)
            band = np.where(joint, 0.0, 1.0 + (vh(seg, np.floor((r - R) / (T / 2)), 4) > 0.6) * 0.6 - (r - R < 1.5) * 0.8 + (r - R > T - 2) * 0.5)
            c.put(ring, 500.0 - north, mat, band)
            if near:
                self.front |= ring
        side = (np.abs(self.px) >= R) & (np.abs(self.px) < R + T) & (self.sy >= self.cy - self.WH) & (self.sy < self.cy)
        c.put(side, 400.0, mat, np.where(vh(np.floor(self.sy / 8), np.floor(self.px / 5), 6) > 0.7, 0.7, 0.2))


# ------------------------------------------------------------------ the shaft
SR, SWH, SW, SH, SN = 88, 124, 24, 72.0, 24  # radius, wall, the stair's width, its rise, its steps


def stairs_room():
    room = Room(SR, SWH)
    c, R, cx, cy = room.c, room.R, room.cx, room.cy
    rise = SH / SN

    def rise_at(theta):
        return np.clip(np.floor(theta / math.pi * SN) + 1, 0, SN) * rise

    def floor(px, north, r, a):
        ring = np.floor(r / 13.0)
        n = np.maximum(1, np.round(2 * math.pi * (ring + 0.5) * 13.0 / 15.0))
        t = (a + math.pi + ring * 0.9) / (2 * math.pi) * n
        idx = np.floor(t)
        joint = ((r - ring * 13.0 < 1.0) | ((t - idx) * (2 * math.pi * r / n) < 1.1)) & (ring > 0)
        j = vh(idx, ring, 11)
        band = 1.8 + np.where(j > 0.75, 0.7, np.where(j < 0.22, -0.6, 0.0)) + (vnoise(px * 0.05, north * 0.05, 5) - 0.5) * 0.9
        under = np.where(north > 0, np.clip(rise_at(np.maximum(a, 0.0)) / 24.0, 0, 1), (px < 0) * np.clip(1 + north / 12.0, 0, 1))
        band = np.where(joint, 0.0, band) - np.clip((r - (R - SW - 8)) / 8.0, 0, 1) * under * 0.9  # the stair's shadow at its foot
        mat = np.where(vh(idx, ring, 12) > 0.86, CSTONE_L, CSTONE)
        # the sign in the middle stone: a ring, three strokes and a heart of light
        sign = (ring == 0) & ((np.abs(r - 9.0) < 0.75) | (r < 1.6) | ((np.abs(np.sin(a * 1.5 + 0.5)) < 0.16) & (r > 3.0) & (r < 8.0)))
        return np.where(sign, HEXG, mat), np.where(sign, 2.0, band), sign

    def wall(u, v, theta):
        d, joint, light = stone(u, v, 21)
        lit = 1.6 + 0.95 * np.cos(theta - 0.9) - np.clip((v - rise_at(theta) - 26.0) / 64.0, 0, 1.6) ** 1.3
        band = np.where(joint, lit - 1.4, lit + d)
        return np.where(light, CSTONE_L, CSTONE), band, False

    room.floor(floor)
    room.wall(wall)
    room.rim()
    px, sy = room.px, room.sy
    # the stair: the inner face under it (with a low curb), then every tread and riser
    ri = R - SW
    inside = np.abs(px) < ri
    north = np.sqrt(np.maximum(ri * ri - px ** 2, 0.0))
    theta = np.arctan2(north, px)
    v = cy - north - sy
    top = rise_at(theta) + 3.0
    d, joint, light = stone(theta * ri, v, 33)
    lit = 1.25 + 0.9 * np.cos(theta - 0.9) - np.clip((top - v) / 46.0, 0, 1) * 0.5
    band = np.where(joint, lit - 1.3, lit + d)
    band = np.where(top - v < 3.0, 2.3 + 0.5 * np.cos(theta - 0.9), band)  # the curb's edge
    c.put(inside & (v >= 0) & (v <= top), -north + v + 0.01, np.where(light | (top - v < 3.0), CSTONE_L, CSTONE), band)
    for k in range(SN):
        t0, t1, hk = k * math.pi / SN, (k + 1) * math.pi / SN, (k + 1) * rise
        for lift, r0 in ((0.0, ri + 3.0), (3.0, ri)):  # the tread, and the curb's top along its inner edge
            north = cy - sy - hk - lift
            r = np.hypot(px, north)
            a = np.arctan2(north, px)
            ok = (a >= t0) & (a < t1) & (r >= r0) & (r < (R if lift == 0 else ri + 3.0)) & (north >= 0)
            arc = (a - t0) * r
            worn = np.exp(-((r - (ri + SW * 0.55)) / 6.0) ** 2) * 0.5
            band = 2.25 + (k % 2) * 0.3 + (vh(k, 0, 40) - 0.5) * 0.4 + worn + (vnoise(px * 0.3, north * 0.3, 8) - 0.5) * 0.5
            band = np.where(arc < 1.6, 3.0, band)  # the nosing catches the light
            band = np.where((a - t1) * r > -1.0, band - 1.2, band)  # the next riser's shadow
            band = band - np.clip((r - (R - 3.5)) / 3.5, 0, 1) * 1.0
            c.put(ok, -north + hk + lift, CSTONE_L if lift == 0 else CSTONE_L, band if lift == 0 else 2.2)
        if abs(math.cos(t0)) > 1e-3:  # the riser
            r = px / math.cos(t0)
            north = r * math.sin(t0)
            hv = cy - north - sy
            c.put((r >= ri) & (r < R) & (hv >= hk - rise) & (hv <= hk), -north + hv, CSTONE, 0.9 + (hv > hk - 1.2) * 0.8)
    # what is on the wall: a rune over every third step, candle niches, slits, moss
    rune_pal = {"g": (HEXG, 2.0, True), "G": (HEXG, 3.0, True)}
    runes = (("g.g", ".G.", "g.g", ".g."), (".g.", "gG.", ".gg", ".g."), ("g..", "gGg", "..g", "..g"), (".g.", "gGg", ".g.", "g.g"))
    lights = []
    for k in range(2, SN, 3):
        a = (k + 0.5) * math.pi / SN
        x, y = room.wall_xy(a, (k + 1) * rise + 15.0)
        c.stamp(x, y, runes[(k // 3) % 4], rune_pal)
    niche = ("..sss..", ".sdGds.", "sddgdds", "sddwdds", "sddwdds", "sssssss")
    npal = {"s": (CSTONE_L, 2.4, False), "d": (GAP, 1.0, False), "w": (WAX, 2.0, False), "g": (HEXG, 2.0, True), "G": (HEXG, 3.0, True)}
    for a in (0.55, 1.42, 2.3):
        x, y = room.wall_xy(a, rise_at(a) + 40.0)
        c.stamp(x, y, niche, npal)
        lights.append({"pos": [round(x), round(y) + 14], "color": "#a8ff6a", "radius": 54, "squash": 0.9, "energy": 0.7, "flicker": 0.2})
    slit = ("sss", "sGs", "sgs", "sgs", "sGs", "sgs", "sgs", "sgs", "sss", "SSS")
    spal = {"s": (CSTONE_L, 2.2, False), "S": (CSTONE_L, 3.0, False), "g": (HEXG, 1.6, True), "G": (HEXG, 2.6, True)}
    for a, v in ((0.98, 92.0), (1.9, 104.0), (2.62, 112.0)):
        x, y = room.wall_xy(a, v)
        c.stamp(x, y, slit, spal)
    rng = rng_for(5)
    for _ in range(70):  # witch-hair moss in the joints, more low down and on the shaded side
        a = rng.uniform(0.15, 3.0)
        v = rise_at(a) + 6.0 + rng.uniform(0, 1) ** 2 * 80.0
        x, y = room.wall_xy(a, v)
        c.stamp(x, y, (("mm", ".m") if rng.random() < 0.5 else ("m", "m", "m")), {"m": (HAIRM if rng.random() < 0.4 else LEAF, 1.6, False)})
    arr, glow = c.image(~room.front)
    front, _ = c.image(room.front)
    # colliders (room px): the floor's near half and the stair's outer edge; the stair's foot and its inner edge
    outer = [[cx - (R - 2), cy]] + [[cx + (R - 2) * math.cos(a), cy - (R - 2) * math.sin(a)] for a in np.linspace(math.pi, 2 * math.pi, 25)[1:]]
    outer += [[cx + (R - 2) * math.cos(a), cy - (R - 2) * math.sin(a) - SH * a / math.pi] for a in np.linspace(0, math.pi, 33)[1:]]
    outer += [[cx - ri + 1, cy - SH]]
    foot = [[cx - (R - 2), cy]] + [[cx + (ri - 1) * math.cos(a), cy - (ri - 1) * math.sin(a)] for a in np.linspace(math.pi, 0, 33)]
    foot += [[cx + (ri - 1) * math.cos(a), cy - (ri - 1) * math.sin(a) - SH * a / math.pi - 2.0] for a in np.linspace(0, math.pi, 33)[1:]]
    return room, arr, glow, front, [outer, foot], lights


# ------------------------------------------------------------------ the chamber
CR, CWH = 100, 66
WINDOWS = (0.66, math.pi - 0.66)  # where the two windows sit in the wall (angle)
SHELF = 5.0  # how far a shelf stands out of the wall
HOLE = (math.radians(182.0), math.radians(236.0), 30.0)  # the stair's head in the floor: from, to, width


def chamber_room():
    room = Room(CR, CWH)
    c, R, cx, cy = room.c, room.R, room.cx, room.cy
    rug = (0.0, -50.0, 36.0)  # east, north, radius

    def floor(px, north, r, a):
        y = -north
        row = np.floor((y + 200) / 8.0)
        uu = px + 400 + vh(row, 0, 51) * 46.0
        col = np.floor(uu / 46.0)
        joint = ((y + 200) - row * 8.0 < 1.0) | (uu - col * 46.0 < 1.0)
        j = vh(col, row, 52)
        band = 1.6 + np.where(j > 0.72, 0.6, np.where(j < 0.25, -0.6, 0.0)) + (vnoise(px * 0.04, north * 0.04, 7) - 0.5) * 0.8
        band = band - (vh(np.floor(px / 3.0), np.floor(y), 53) < 0.07) * 0.9
        mat = np.where(vh(col, row, 54) > 0.7, WOODP_L, WOODP)
        band = np.where(joint, 0.0, band)
        emit = np.zeros_like(band, bool)
        # the rug: a fringe, a wine border, a violet field with a silver moon and stars
        dx, dn = px - rug[0], north - rug[1]
        d = np.hypot(dx, dn)
        ra = np.arctan2(dn, dx)
        on = d < rug[2]
        weave = ((np.floor(px) + np.floor(y)) % 2) * 0.35
        rmat = np.where(d > rug[2] - 2, BONE, np.where(d > rug[2] - 7, WINE, np.where(d > rug[2] - 9, BONE, HOODM)))
        rband = np.where(d > rug[2] - 2, 0.6 + (np.floor(ra * 22) % 2) * 1.6, np.where(d > rug[2] - 7, 1.5, np.where(d > rug[2] - 9, 1.2, 1.7))) - weave
        moon = (np.hypot(dx + 2, dn) < 11.5) & (np.hypot(dx - 3, dn - 1.5) > 9.6)
        rmat, rband = np.where(moon, SILVER, rmat), np.where(moon, 1.8, rband)
        for sa, sr in ((0.5, 19.0), (1.9, 21.0), (3.6, 20.0), (5.2, 18.0), (4.4, 23.0), (2.8, 15.0)):
            star = np.abs(dx - math.cos(sa) * sr) + np.abs(dn - math.sin(sa) * sr) < 1.6
            rmat, rband = np.where(star, BONE, rmat), np.where(star, 2.6, rband)
        dots = (np.abs(d - 25.5) < 0.9) & (np.abs(np.sin(ra * 8)) > 0.92)
        rmat, rband = np.where(dots, WINE, rmat), np.where(dots, 2.8, rband)
        mat, band = np.where(on, rmat, mat), np.where(on, rband, band)
        band = band - np.where(~on & (d < rug[2] + 2.5), 0.9, 0.0)  # its shadow on the boards
        # the stair's head: steps going down into the shaft's green dark
        a2 = np.where(a < 0, a + 2 * math.pi, a)
        hole = (a2 > HOLE[0]) & (a2 < HOLE[1]) & (r > R - HOLE[2]) & (r < R - 2.5)
        t = (HOLE[1] - a2) / (HOLE[1] - HOLE[0]) * 6.0  # 0 at the top step
        step = np.floor(t)
        hband = 2.6 - step * 0.62 - (t - step < 0.14) * 1.6 + (t - step > 0.82) * 0.5 - np.clip((R - 4 - r) / -3.0 + 1, 0, 1) * 0.0
        deep = step >= 4
        glint = deep & (step == 4) & (vh(np.floor(px), np.floor(y), 55) > 0.9)
        mat = np.where(hole, np.where(glint, HEXG, np.where(deep, GAP, CSTONE_L)), mat)
        band = np.where(hole, np.where(glint, 0.4, np.where(deep, 2.0 - (step - 4), hband)), band)
        emit = np.where(hole & glint, True, emit)
        edge = (a2 > HOLE[0] - 0.03) & (a2 < HOLE[1] + 0.03) & (r > R - HOLE[2] - 2.0) & ~hole & (r < R)
        mat, band = np.where(edge, HAG_L, mat), np.where(edge, 2.3, band)
        return mat, band, emit

    def wall(u, v, theta):
        col = np.floor(u / 7.0)
        lu = u - col * 7.0
        lit = 1.45 + 0.9 * np.cos(theta - 0.9)
        j = vh(col, 0, 61)
        band = lit + np.where(j > 0.7, 0.5, np.where(j < 0.25, -0.5, 0.0)) - (vh(col, np.floor(v / 2.0), 62) < 0.1) * 0.8
        band = np.where(lu < 1.0, lit - 1.5, band)
        mat = np.where(vh(col, 1, 63) > 0.66, WOODP_L, WOODP)
        post = (u % 44.0) < 5.0
        mat, band = np.where(post, HAG_L, mat), np.where(post, lit + 0.2 - ((u % 44.0) > 3.6) * 1.0, band)
        beam = (v < 4.0) | (v > CWH - 6.0)
        mat, band = np.where(beam, HAG_L, mat), np.where(beam, lit + 0.5 - ((v % (CWH - 6.0)) < 1.0) * 1.3, band)
        emit = np.zeros_like(band, bool)
        for ac in WINDOWS:  # a window lies IN the wall: its sill and arch follow the curve, its far side is narrower
            du, dv = (theta - ac) * R, v - 18.0
            arch = 28.0 - np.maximum(np.abs(du) - 5.0, 0.0) ** 2 * 0.09
            hole = (np.abs(du) < 14.0) & (dv > 0) & (dv < arch)
            glass = (np.abs(du) < 11.5) & (dv > 2.5) & (dv < arch - 2.5)
            bars = (np.abs(du) < 0.9) | (np.abs(dv - 13.0) < 0.9)
            reveal = glass & ((du * np.sign(math.pi / 2 - ac) > 8.0) | (dv > arch - 5.5))  # the wall's thickness shows on the far side and under the arch
            fog = dv < 9.0 + vnoise(du * 0.3, dv * 0.3, 66) * 9.0
            moon = (np.hypot(du - 4.0, dv - 20.0) < 3.2) & (np.hypot(du - 5.6, dv - 21.0) > 2.6)
            mat = np.where(hole, np.where(glass, np.where(bars | reveal, HAG, np.where(moon, SILVER, np.where(fog, HEXG, LEAF))), HAG_L), mat)
            band = np.where(hole, np.where(glass, np.where(reveal, 0.4, np.where(bars, 1.2, np.where(moon, 2.6, np.where(fog, 0.2, 0.7)))), lit + 1.1 - (dv < 1.2) * 1.4), band)
            emit = np.where(hole & glass & ~bars & ~reveal, True, emit)
            sill = (np.abs(du) < 16.5) & (dv > -3.0) & (dv <= 0)
            mat, band = np.where(sill, HAG_L, mat), np.where(sill, np.where(dv > -1.2, 3.0, 1.2), band)
        return mat, band, emit

    room.floor(floor)
    room.wall(wall)
    room.rim(HAG)
    # windows into the fog, shelves with what a witch keeps, hanging things
    lights = []
    for a in WINDOWS:
        x, y = room.wall_xy(a, 22.0)
        lights.append({"pos": [round(x), round(y) + 26], "color": "#b9d6c8", "radius": 62, "squash": 0.8, "energy": 0.5})
    things = {
        "bg": ((".c.", ".n.", "gGg", "gGg", "ggg"), {"c": (BONE, 2.0, False), "n": (SILVER, 1.0, False), "g": (BREW, 2.0, True), "G": (BREW, 3.0, True)}),
        "bw": ((".c.", ".n.", "www", "wWw", "www"), {"c": (BONE, 2.0, False), "n": (SILVER, 1.0, False), "w": (WINE, 1.6, False), "W": (WINE, 3.0, False)}),
        "bv": (("c", "v", "V", "v"), {"c": (BONE, 2.0, False), "v": (HOODM, 2.2, False), "V": (HOODM, 3.0, False)}),
        "jar": (("lll", "jJj", "jJj", "jjj"), {"l": (BONE, 2.4, False), "j": (SILVER, 0.8, False), "J": (HAIRM, 2.4, False)}),
        "skull": ((".sss.", "sSSSs", "sdSds", ".sss.", ".s.s."), {"s": (BONE, 2.0, False), "S": (BONE, 3.0, False), "d": (GAP, 0.0, False)}),
        "books": (("w.vl", "wbvl", "wbvl", "wbvl", "wbvl"), {"w": (WINE, 1.8, False), "b": (LEAF, 2.2, False), "v": (HOODM, 2.4, False), "l": (BONE, 1.4, False)}),
        "candle": (("G", "g", "w", "w"), {"G": (HEXG, 3.0, True), "g": (HEXG, 2.0, True), "w": (WAX, 2.2, False)}),
        "pot": (("m.m", "mmm", "ccc", ".c."), {"m": (HAIRM, 2.4, False), "c": (CLAY, 1.6, False)}),
    }
    for a0, a1, v0, row in ((1.05, 1.42, 24.0, ("bg", "jar", "books", "bw", "candle")), (1.72, 2.1, 24.0, ("skull", "bv", "bg", "pot", "jar")), (1.05, 1.42, 43.0, ("books", "bv", "bw", "jar", "bg")), (1.72, 2.1, 43.0, ("jar", "candle", "books", "skull", "bw")), (0.24, 0.42, 30.0, ("bw", "bg")), (2.72, 2.9, 30.0, ("jar", "bv"))):
        steps = np.arange(a0 - 0.035, a1 + 0.035, 0.004)
        for n, a in enumerate(steps):  # the board: it stands SHELF px out of the wall, so its top shows, then its front edge, then its shadow on the wall
            x, y = room.wall_xy(a, v0)
            deep = int(round(SHELF * math.sin(a)))
            xi, yi = int(round(x - math.cos(a) * SHELF * 0.5)), int(round(y))
            end = n < 3 or n > len(steps) - 4
            for j in range(deep + 9):
                if c.mat[yi + j, xi] < 0:
                    continue
                if j < deep:
                    c.mat[yi + j, xi], c.band[yi + j, xi], c.emit[yi + j, xi] = HAG_L, (2.9 if j == 0 else 2.3) - end * 0.8, False
                elif j < deep + 2:
                    c.mat[yi + j, xi], c.band[yi + j, xi], c.emit[yi + j, xi] = HAG, 1.6 - (j - deep) * 0.9, False
                elif c.mat[yi + j, xi] not in (HAG_L, HAG) or c.band[yi + j, xi] < 2.0:
                    c.band[yi + j, xi] -= 1.5 * (1.0 - (j - deep - 2) / 7.0)
        for t in (0.08, 0.5, 0.92):  # brackets under it
            a = a0 + (a1 - a0) * t
            x, y = room.wall_xy(a, v0)
            deep = int(round(SHELF * math.sin(a)))
            for j in range(6):
                for i in range(max(1, 2 - j // 3)):
                    yy, xx = int(round(y)) + deep + 2 + j, int(round(x - math.cos(a) * SHELF * 0.5)) + i
                    if j < 6 - i * 3:
                        c.mat[yy, xx], c.band[yy, xx], c.emit[yy, xx] = HAG_L, 1.9 - i * 0.9 - j * 0.15, False
        for i, name in enumerate(row):
            a = a0 + (a1 - a0) * (i + 0.5) / len(row)
            x, y = room.wall_xy(a, v0)
            deep = int(round(SHELF * math.sin(a)))
            xi, yi = int(round(x - math.cos(a) * SHELF * 0.5)), int(round(y)) + max(deep - 2, 1)
            wide = len(things[name][0][0])
            for i2 in range(-(wide // 2), wide // 2 + 2):  # what stands on it throws a little shadow on the board
                c.band[yi + 1, xi + i2] -= 1.0
            c.stamp(xi, yi, *things[name])
    rng = rng_for(9)
    for a in (0.2, 0.86, 1.56, 2.3, 2.96):  # bundles hung from the top beam: herbs, a string of garlic-pale bulbs, feathers
        x, y = room.wall_xy(a, CWH - 7.0)
        n = int(rng.integers(5, 10))
        rows = [("." + "s" + ".")] * 2 + [("hHh" if j % 2 else "Hhh") for j in range(n)] + [".h."]
        kind = int(rng.integers(0, 3))
        c.stamp(x, y + len(rows) - 1, rows, {"s": (BONE, 1.0, False), "h": ((LEAF, HAIRM, WINE)[kind], 1.6, False), "H": ((LEAF, HAIRM, WINE)[kind], 2.8, False)})
    arr, glow = c.image(~room.front)
    front, _ = c.image(room.front)
    ring = [[cx + (R - 2) * math.cos(a), cy - (R - 2) * math.sin(a)] for a in np.linspace(0, 2 * math.pi, 49)]
    ri = R - HOLE[2] - 2
    pit = [[cx + ri * math.cos(a), cy - ri * math.sin(a)] for a in np.linspace(HOLE[0] - 0.04, HOLE[1] + 0.04, 9)]
    pit = [[cx + (R - 2) * math.cos(HOLE[0] - 0.04), cy - (R - 2) * math.sin(HOLE[0] - 0.04)]] + pit + [[cx + (R - 2) * math.cos(HOLE[1] + 0.04), cy - (R - 2) * math.sin(HOLE[1] + 0.04)]]
    return room, arr, glow, front, [ring, pit], lights


# ------------------------------------------------------------------ furniture (ellipsoids, the tower's renderer)
PARTS = {}


def render_part(name, m, seed, fw=200, fh=200, ground=170):
    arr = to_array(hut_lib.render(m, fw, fh, ground))
    ys, xs = np.nonzero(arr[..., 3])
    x0, x1, y0 = int(xs.min()), int(xs.max()) + 1, int(ys.min())
    half = max(fw // 2 - x0, x1 - fw // 2)  # keep the model's middle in the picture's middle
    crop = grain(arr[y0:ground + 1 if ys.max() <= ground else int(ys.max()) + 1, fw // 2 - half:fw // 2 + half], seed, amount=0.4, mats=GRAINED)
    save(OUT / f"{name}.png", crop)
    g = glow_of(crop, LIT)
    has = bool(g[..., 3].any())
    if has:
        save(OUT / f"{name}_glow.png", g)
    PARTS[name] = {"size": [crop.shape[1], crop.shape[0]], "feet": ground - y0, "glow": has}
    return crop


def candle(m, p, tall=3.0, r=0.8):
    log(m, p, p + V(0, tall, 0), r, WAX, step=0.8)
    m.ell(p + V(0, tall + 1.5, 0), (r * 0.8, 1.5, r * 0.7), HEXG, kind="emit")


def bottle(m, p, mat, s=1.0, lit=False):
    m.ell(p + V(0, 2.0 * s, 0), (1.5 * s, 2.0 * s, 1.5 * s), mat, kind="emit" if lit else "")
    m.limb(p + V(0, 3.6 * s, 0), p + V(0, 5.4 * s, 0), 0.6 * s, 0.5 * s, SILVER)
    m.ell(p + V(0, 5.8 * s, 0), (0.7 * s, 0.5 * s, 0.7 * s), BONE)


def skull(m, p, s=1.0):
    m.ell(p + V(0, 2.4 * s, 0), (2.4 * s, 2.3 * s, 2.5 * s), BONE)
    m.ell(p + V(0, 0.8 * s, 0.7 * s), (1.6 * s, 1.0 * s, 1.6 * s), BONE)
    for sx in (-1, 1):
        m.ell(p + V(sx * 0.95 * s, 2.3 * s, 2.2 * s), (0.65 * s, 0.75 * s, 0.5), GAP)


def counter(decorated=True):
    """The witch's counter: a bar of hag elm bent round her place, bone-wood pilasters, a moon on its front, and her things on its top."""
    m = h.Model()
    rc, top = 66.0, 26.0
    n = 54
    for k in range(n + 1):
        a = math.radians(18.0) + math.radians(144.0) * k / n
        ca, sa = math.cos(a), math.sin(a)
        m.ell(V(rc * ca, top / 2, rc * sa), (2.0, top / 2, 1.5), WOODP_L if k % 3 == 0 else WOODP, R=facing(a))
        m.ell(V(rc * ca, 1.6, rc * sa + 0.4), (2.2, 1.6, 2.2), HAG, R=facing(a))
        m.ell(V((rc - 4.0) * ca, top + 0.6, (rc - 4.0) * sa), (2.4, 1.3, 7.0), HAG_L, R=facing(a))  # the top: a thick worn board
        m.ell(V((rc + 2.6) * ca, top + 0.2, (rc + 2.6) * sa), (2.3, 1.0, 1.0), HAG_L, R=facing(a))
        if k % 9 == 0:
            log(m, V((rc + 1.7) * ca, 1.0, (rc + 1.7) * sa), V((rc + 1.7) * ca, top - 1.0, (rc + 1.7) * sa), 1.2, BONE, step=1.0)
            m.ell(V((rc + 2.2) * ca, top - 3.0, (rc + 2.2) * sa), (1.7, 1.2, 1.2), BONE, R=facing(a))
    if not decorated:
        return m
    a = math.pi / 2  # the moon carved into the front, and a rune row
    for j in range(9):
        b = -0.7 + 4.0 * j / 8
        m.ell(V(math.cos(b) * 4.6 - 0.5, 13.0 + math.sin(b) * 4.6, rc + 1.9), (1.3 - 0.13 * abs(j - 4), 1.3 - 0.13 * abs(j - 4), 0.6), SILVER)
    for sx, shape in ((-17.0, 0.5), (-11.0, -0.5), (11.0, 0.5), (17.0, -0.5)):
        aa = math.pi / 2 - sx / rc
        m.ell(V(rc * math.cos(aa), 13.0, rc * math.sin(aa) + 1.6), (0.5, 2.4, 0.5), HEXG, R=facing(aa) @ rot_z(shape), kind="emit")
    y, r = top + 1.9, rc - 4.0

    def at(deg, back=0.0):
        b = math.radians(deg)
        return V((r - back) * math.cos(b), y, (r - back) * math.sin(b))

    for d, t in ((30.0, 3.6), (33.5, 2.2), (27.0, 1.6)):  # candles run down into one lump of wax
        candle(m, at(d, 1.5 if d > 31 else -1.0), t)
    m.ell(at(30.0) + V(0, 0.2, 0), (3.4, 0.6, 2.4), WAX)
    bottle(m, at(46.0, 2.0), BREW, 1.15, True)
    bottle(m, at(51.5, -1.0), WINE, 0.9)
    bottle(m, at(56.0, 2.5), HOODM, 1.0)
    skull(m, at(70.0), 1.0)
    candle(m, at(70.0) + V(0, 4.4, 0), 1.6, 0.6)
    p = at(92.0)  # the open book
    for sx in (-1, 1):
        m.ell(p + V(sx * 3.0, 0.5, 0), (3.1, 0.6, 3.6), WINE, R=rot_z(-sx * 0.12))
        m.ell(p + V(sx * 2.9, 1.0, 0), (2.7, 0.5, 3.2), LINEN, R=rot_z(-sx * 0.12))
        for j in range(3):
            m.ell(p + V(sx * 2.9, 1.5, -1.6 + j * 1.6), (1.7, 0.2, 0.25), HEXG if (j + sx) % 3 == 0 else IRON, kind="emit" if (j + sx) % 3 == 0 else "")
    p = at(113.0)  # the scales
    m.limb(p, p + V(0, 8.0, 0), 0.5, 0.4, IRON)
    m.ell(p + V(0, 0.4, 0), (2.2, 0.6, 2.0), IRON)
    m.limb(p + V(-5.0, 7.2, 0), p + V(5.0, 8.4, 0), 0.4, 0.4, IRON)
    for sx, dy in ((-1, 7.2), (1, 8.4)):
        m.limb(p + V(sx * 5.0, dy, 0), p + V(sx * 5.0, dy - 4.0, 0), 0.2, 0.2, SILVER)
        m.ell(p + V(sx * 5.0, dy - 4.4, 0), (2.2, 0.6, 2.0), SILVER)
    m.ell(p + V(-5.0, 3.6, 0), (1.2, 1.0, 1.2), HEXG, kind="emit")
    p = at(133.0)  # mortar and pestle
    m.ell(p + V(0, 1.8, 0), (3.0, 2.0, 2.8), CSTONE_L)
    m.ell(p + V(0, 3.2, 0), (2.1, 0.5, 1.9), GAP)
    log(m, p + V(0.5, 3.0, 0), p + V(3.6, 7.0, -0.5), 0.7, BONE, step=0.8)
    bottle(m, at(147.0, 1.0), BREW, 0.85, True)
    p = at(154.0, 2.0)  # a jar with something pale in it
    m.ell(p + V(0, 2.6, 0), (2.2, 2.7, 2.2), SILVER)
    m.ell(p + V(0, 2.2, 0.6), (1.2, 1.3, 1.2), BONE)
    m.ell(p + V(0, 5.4, 0), (2.0, 0.6, 2.0), WINE)
    for k in range(3):  # a rag over the edge
        m.ell(V(-38.0 + k * 0.4, top - 2.0 - k * 2.6, rc * 0.82 + 1.8), (2.6 - 0.4 * k, 1.8, 0.5), WINE)
    return m


def cauldron():
    """The alchemy cauldron, her workplace: a great black pot with glowing signs on a ringed hearth, a crane of bone wood, a coil and flask beside it, logs."""
    m = h.Model()
    rng = rng_for(31)
    for k in range(14):  # the hearth ring
        a = 2 * math.pi * k / 14
        m.ell(V(math.cos(a) * 19.0, 2.2, math.sin(a) * 15.0), (4.4, 2.6 + 0.6 * math.sin(k * 2.1), 3.6), (CSTONE, CSTONE_L, CSTONE)[k % 3], R=facing(a))
    m.ell(V(0, 1.2, 0), (15.0, 0.9, 11.5), GAP)
    m.ell(V(0, 1.8, 1.0), (10.5, 0.9, 8.0), IRON)  # charcoal underneath the moving embers
    for a in (0.5, 2.6, 4.4):  # three legs
        log(m, V(math.cos(a) * 11.0, 1.0, math.sin(a) * 9.0), V(math.cos(a) * 9.0, 9.0, math.sin(a) * 7.4), 1.4, IRON, step=1.0)
    m.ell(V(0, 19.0, 0), (17.5, 13.5, 15.5), IRON)  # the belly
    for k in range(24):  # the rim
        a = 2 * math.pi * k / 24
        m.ell(V(math.cos(a) * 15.2, 30.6, math.sin(a) * 13.2), (2.3, 1.3, 1.7), IRON, R=facing(a))
    m.ell(V(0, 30.8, 0), (13.6, 0.8, 11.8), BREW, kind="emit")
    for k, (da, shape) in enumerate(((-0.75, 0.5), (-0.45, -0.5), (-0.15, 0.0), (0.15, 0.6), (0.45, -0.6), (0.75, 0.0))):  # signs round the belly
        a = math.pi / 2 + da
        p = V(math.cos(a) * 17.6, 19.0 + (k % 2) * 1.5, math.sin(a) * 15.6)
        m.ell(p, (0.55, 2.6, 0.5), HEXG, R=facing(a) @ rot_z(shape), kind="emit")
        if k % 2:
            m.ell(p + V(0, 0.5, 0), (1.5, 0.5, 0.5), HEXG, R=facing(a), kind="emit")
    for sx in (-1, 1):  # ring handles
        for j in range(8):
            b = 2 * math.pi * j / 8
            m.ell(V(sx * 18.4, 22.0 + math.sin(b) * 2.6, 4.0 + math.cos(b) * 2.6), (0.7, 0.7, 0.7), SILVER)
    for j in range(5):  # a drip of brew down the side
        m.ell(V(7.0 + 0.3 * j, 29.0 - j * 2.2, 13.4 + (0.5 if j < 3 else 0.0)), (0.9 - 0.12 * j, 1.3, 0.6), BREW, kind="emit")
    # the crane: a crooked post of bone wood with an arm over the pot, a hook, a ladle hanging
    log(m, V(-25.0, 0.5, -6.0), V(-23.0, 56.0, -6.0), 1.9, BONE, step=1.1, taper=0.75)
    log(m, V(-23.0, 54.0, -6.0), V(2.0, 60.0, -3.0), 1.3, BONE, step=1.0, taper=0.7)
    log(m, V(-23.5, 40.0, -6.0), V(-12.0, 56.5, -5.0), 0.9, BONE, step=0.9)
    m.limb(V(0.0, 59.0, -3.0), V(0.0, 47.0, -2.0), 0.3, 0.3, IRON)
    m.limb(V(0.0, 47.0, -2.0), V(1.6, 44.5, -2.0), 0.5, 0.3, IRON)
    for k in range(3):
        m.ell(V(-23.6, 30.0 - k * 2.4, -4.4), (1.3 - 0.25 * k, 1.6, 0.4), WINE)
    # the still: a stone block to the right with a flask over a candle, a coil from the pot's rim into it
    for k in range(3):
        m.ell(V(31.0 + (k % 2) * 1.0, 3.0 + k * 5.2, -1.0), (7.0 - k * 0.5, 2.9, 6.0), (CSTONE_L, CSTONE, CSTONE_L)[k])
    m.ell(V(31.0, 20.0, -1.0), (4.2, 4.4, 4.0), SILVER)
    m.ell(V(31.0, 19.0, 0.6), (3.0, 2.8, 2.8), BREW, kind="emit")
    m.limb(V(31.0, 24.0, -1.0), V(31.0, 29.0, -1.0), 1.0, 0.8, SILVER)
    for j in range(22):  # the coil
        t = j / 21
        m.ell(V(15.0 + 16.0 * t, 32.0 + math.sin(t * math.pi) * 9.0 - 2.0 * t + math.sin(j * 1.6) * 1.1, 6.0 - 6.0 * t + math.cos(j * 1.6) * 1.2), (0.8, 0.8, 0.8), SILVER)
    candle(m, V(25.0, 16.6, 3.0), 2.2, 0.6)
    # logs of hag elm stacked on the left, toad caps drying on them
    for k, (x, y, z) in enumerate(((-33.0, 2.0, 8.0), (-28.0, 2.0, 9.5), (-30.5, 5.6, 8.8), (-36.0, 2.0, 11.0))):
        log(m, V(x - 0.5, y, z - 6.0), V(x + 0.5, y, z + 6.0), 2.2, HAG if k % 2 else HAG_L, step=1.2)
        m.ell(V(x + 0.5, y, z + 6.4), (1.9, 1.9, 0.5), BONE)
    m.ell(V(-31.0, 8.6, 9.0), (2.4, 1.3, 2.0), WINE)
    return m


def jeweller():
    """The little jewellery forge where talismans are made: a bench of hag elm with a small furnace, a horned anvil on a stump, a lens on an arm,
    a bust with a necklace, rings on a cushion, the fine tools."""
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 15.0, 0.5, sz * 4.6), V(sx * 14.4, 16.0, sz * 4.4), 1.4, HAG, step=1.0)
    log(m, V(-14.6, 6.0, 4.6), V(14.6, 6.0, 4.6), 0.8, HAG_L, step=1.0)
    slab(m, V(-17.5, 17.4, 0), V(17.5, 17.4, 0), 6.4, 1.3, HAG_L, (0, 1, 0), step=1.5)
    for k in range(3):  # drawers with silver knobs
        m.ell(V(-9.0 + k * 9.0, 12.6, 5.8), (3.8, 2.6, 0.8), WOODP_L if k % 2 else WOODP)
        m.ell(V(-9.0 + k * 9.0, 12.6, 6.8), (0.6, 0.6, 0.5), SILVER)
    y = 18.8
    # the furnace: a little dome of stones with a glowing mouth and a crooked pipe
    for k in range(9):
        a = math.pi * k / 8
        m.ell(V(-11.5 + math.cos(a) * 4.6, y + 1.6 + math.sin(a) * 4.4, -1.0), (1.9, 1.9, 4.0), (CSTONE_L, CSTONE)[k % 2], R=rot_z(a))
    m.ell(V(-11.5, y + 2.0, -1.4), (4.2, 3.6, 3.6), CSTONE)
    m.ell(V(-11.5, y + 2.2, 2.6), (2.6, 2.3, 0.8), HEXG, kind="emit")
    m.ell(V(-11.5, y + 1.6, 3.2), (1.3, 1.0, 0.5), BREW, kind="emit")
    log(m, V(-12.5, y + 6.0, -2.0), V(-14.0, y + 13.0, -2.0), 1.1, IRON, step=0.9)
    log(m, V(-14.0, y + 13.0, -2.0), V(-12.0, y + 17.0, -2.0), 1.0, IRON, step=0.9)
    m.ell(V(-5.6, y + 1.3, 3.0), (1.5, 1.2, 1.4), CLAY)  # a crucible with molten silver
    m.ell(V(-5.6, y + 2.2, 3.0), (1.0, 0.4, 0.9), SILVER)
    # the anvil on its stump: flat face, a horn
    m.ell(V(2.0, y + 1.6, 0.5), (3.0, 1.8, 2.8), HAG)
    m.ell(V(2.0, y + 4.0, 0.5), (1.5, 1.2, 1.5), IRON)
    m.ell(V(2.0, y + 5.8, 0.5), (3.6, 1.1, 1.9), IRON)
    m.limb(V(5.0, y + 5.8, 0.5), V(8.2, y + 6.2, 0.5), 1.0, 0.3, IRON)
    m.ell(V(1.4, y + 7.2, 0.6), (1.4, 0.45, 1.2), SILVER)  # a ring being made
    m.ell(V(1.4, y + 7.4, 0.6), (0.6, 0.4, 0.5), HEXG, kind="emit")
    log(m, V(-1.5, y + 0.8, 4.4), V(4.5, y + 1.2, 5.0), 0.5, BONE, step=0.7)  # the little hammer
    m.ell(V(5.0, y + 1.3, 5.0), (1.0, 1.0, 1.5), IRON)
    # the lens on its arm
    m.limb(V(9.0, y, -3.0), V(8.4, y + 9.0, -3.0), 0.5, 0.4, IRON)
    m.limb(V(8.4, y + 9.0, -3.0), V(4.4, y + 11.4, -1.0), 0.4, 0.35, IRON)
    for k in range(10):
        b = 2 * math.pi * k / 10
        m.ell(V(3.4 + math.cos(b) * 2.3, y + 11.6 + math.sin(b) * 2.3, -0.6), (0.6, 0.6, 0.5), SILVER)
    m.ell(V(3.4, y + 11.6, -0.8), (1.9, 1.9, 0.4), LEAF)
    m.ell(V(2.8, y + 12.3, -0.4), (0.6, 0.6, 0.3), SILVER)
    # the bust with a necklace, earrings on its stand
    m.ell(V(13.4, y + 0.8, -1.0), (2.6, 0.9, 2.2), HAG)
    m.limb(V(13.4, y + 1.0, -1.0), V(13.4, y + 6.0, -1.0), 1.6, 1.0, BONE)
    m.ell(V(13.4, y + 5.4, -1.0), (3.2, 1.6, 1.8), BONE)
    for k in range(9):
        b = math.pi * (0.1 + 0.8 * k / 8)
        m.ell(V(13.4 + math.cos(b) * 2.6, y + 5.4 - math.sin(b) * 3.2, 0.9), (0.4, 0.4, 0.4), SILVER)
    m.ell(V(13.4, y + 1.8, 1.2), (0.9, 1.1, 0.6), HEXG, kind="emit")
    # rings and stones on a cushion, a bracelet on a peg, tongs over the edge
    m.ell(V(9.4, y + 0.7, 3.6), (3.2, 0.8, 2.2), WINE)
    for k, (dx, mat) in enumerate(((-1.8, HOODM), (0.0, BREW), (1.8, WINE))):
        m.ell(V(9.4 + dx, y + 1.5, 3.6), (0.7, 0.5, 0.7), SILVER)
        m.ell(V(9.4 + dx, y + 2.1, 3.6), (0.45, 0.45, 0.45), mat, kind="emit" if mat == BREW else "")
    m.limb(V(-17.4, y - 1.5, 5.0), V(-17.4, y - 8.5, 5.4), 0.35, 0.3, IRON)
    m.limb(V(-16.4, y - 1.5, 5.0), V(-16.0, y - 8.5, 5.4), 0.35, 0.3, IRON)
    for k in range(8):
        b = 2 * math.pi * k / 8
        m.ell(V(16.8 + math.cos(b) * 1.6, y - 4.0 + math.sin(b) * 1.6, 6.6), (0.5, 0.5, 0.4), SILVER)
    m.ell(V(16.8, y - 5.6, 6.8), (0.6, 0.6, 0.4), HEXG, kind="emit")
    return m


def flames():
    """The town campfire's tongues, embers and sparks, sized for the hearth."""
    width, height, frames = 30, 24, 8
    green = [hexc(c) for c in ("315442", "67a34c", "a8ff6a", "f0ffd0")]
    save(OUT / "flames.png", campfire_frames(width, height, frames, green))
    PARTS["flames"] = {"size": [width, height], "feet": height - 4, "frames": frames}


def brew(frames=6):
    """The cauldron's surface: slow rings, bubbles that swell and burst."""
    w, hh = 27, 11
    g = h.RAMPS[BREW]
    strip = np.zeros((hh, w * frames, 4), np.uint8)
    spots = ((5, 6, 0), (13, 4, 2), (20, 7, 4), (10, 8, 3), (17, 5, 1))
    for f in range(frames):
        for y in range(hh):
            for x in range(w):
                u, v = (x - 13) / 12.5, (y - 5.5) / 4.6
                d = u * u + v * v
                if d > 1.0:
                    continue
                strip[y, f * w + x] = g[2] if int(math.sqrt(d) * 7 - f * 0.5) % 3 == 0 else g[1]
        for bx, by, ph in spots:
            age = (f + ph) % frames
            if age < 3:
                for dy in range(-age, 1):
                    for dx in range(-age, age + 1):
                        if dx * dx + dy * dy <= age * age + 0.5 and 0 <= by + dy < hh:
                            strip[by + dy, f * w + bx + dx] = g[3] if (dx, dy) == (-max(age - 1, 0), -age) or age == 0 else g[2]
            elif age == 3:
                for dx, dy in ((-2, -2), (2, -2), (0, -3)):
                    if 0 <= by + dy < hh:
                        strip[by + dy, f * w + bx + dx] = g[3]
    save(OUT / "brew.png", strip)
    PARTS["brew"] = {"size": [w, hh], "feet": hh, "frames": frames}


def steam(frames=8):
    """Wisps rising from the brew (unlit, thin)."""
    w, hh = 22, 40
    strip = np.zeros((hh, w * frames, 4), np.uint8)
    for f in range(frames):
        for y in range(hh):
            for x in range(w):
                t = (hh - 1 - y) / hh
                cxs = w / 2 + math.sin(t * 5.0 + f * 0.8) * (2.0 + 4.0 * t)
                n = float(vnoise(np.array(x * 0.3), np.array(y * 0.25 + f * 1.5), 81))
                if abs(x - cxs) < (2.6 - 1.8 * t) + n * 2.0 and n > 0.34 + 0.4 * t and BAY[y % 4, x % 4] > t * 0.9:
                    strip[y, f * w + x] = (200, 255, 190, int(120 * (1.0 - t)))
    save(OUT / "steam.png", strip)
    PARTS["steam"] = {"size": [w, hh], "feet": hh, "frames": frames}


def bookcase():
    m = h.Model()
    w, tall, d = 17.0, 58.0, 5.0
    slab(m, V(0, 1.0, -d), V(0, tall, -d), w, 0.8, WOODP, (0, 0, 1), step=1.6)
    for sx in (-1, 1):
        log(m, V(sx * w, 0.5, 0), V(sx * (w + 0.8), tall + 2.0, 0), 1.6, HAG, step=1.1)
    rng = rng_for(41)
    for k, y in enumerate((2.0, 16.0, 30.0, 44.0, tall)):
        slab(m, V(-w, y, 0), V(w, y, 0), d, 0.9, HAG_L, (0, 1, 0), step=1.5)
        if y == tall:
            break
        x = -w + 2.5
        while x < w - 2.0:
            kind = rng.random()
            if kind < 0.72:  # a book, some leaning
                bw, bh = rng.uniform(1.0, 1.7), rng.uniform(8.0, 11.5)
                m.ell(V(x + bw, y + 1.0 + bh / 2, 1.0), (bw, bh / 2, 3.4), (WINE, HOODM, LEAF, WOODP_L, BONE, IRON)[int(rng.integers(0, 6))], R=rot_z(rng.uniform(-0.1, 0.1) if rng.random() < 0.8 else 0.3))
                if rng.random() < 0.3:
                    m.ell(V(x + bw, y + 1.0 + bh * 0.7, 4.2), (bw * 0.8, 0.5, 0.4), SILVER)
                x += bw * 2 + 0.3
            elif kind < 0.86:
                bottle(m, V(x + 2.0, y + 1.0, 1.5), BREW if rng.random() < 0.5 else WINE, 1.0, True)
                x += 4.6
            else:
                skull(m, V(x + 2.8, y + 1.0, 1.0), 0.9)
                x += 6.4
    m.ell(V(-6.0, tall + 3.6, 0), (3.6, 3.2, 3.4), CLAY)  # a pot of witch-hair on top
    for j in range(7):
        b = -1.2 + 2.4 * j / 6
        m.limb(V(-6.0, tall + 6.0, 0), V(-6.0 + math.sin(b) * 7.0, tall + 6.0 + math.cos(b) * 5.0 - abs(b) * 5.0, 1.0), 0.8, 0.3, HAIRM)
    candle(m, V(8.0, tall + 1.0, 0), 4.0)
    return m


def armchair():
    """A deep chair in wine red with a black cat asleep on it."""
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 10.0, 0.5, sz * 7.0), V(sx * 10.5, 7.0, sz * 7.0), 1.3, HAG, step=1.0)
        m.ell(V(sx * 11.0, 16.0, 0.5), (2.6, 4.6, 8.0), WINE)  # the arms
        m.ell(V(sx * 11.0, 20.4, 1.0), (2.9, 1.3, 8.4), HAG_L)
    m.ell(V(0, 9.5, 0.5), (10.5, 3.6, 8.5), WINE)
    m.ell(V(0, 24.0, -7.0), (11.5, 14.0, 3.2), WINE)  # the back, winged
    for sx in (-1, 1):
        m.ell(V(sx * 10.5, 31.0, -5.0), (2.6, 6.5, 3.0), WINE)
    for j in range(3):
        m.ell(V(-4.0 + 4.0 * j, 27.0, -3.6), (0.6, 0.6, 0.6), SILVER)  # buttons
    m.ell(V(0, 38.6, -7.0), (10.0, 1.4, 2.6), HAG_L)
    m.ell(V(-1.0, 14.4, 1.5), (5.6, 2.6, 4.4), GAP)  # the cat, curled
    m.ell(V(4.4, 15.4, 3.0), (2.5, 2.2, 2.4), GAP)
    for sx in (-1, 1):
        m.ell(V(4.4 + sx * 1.5, 17.6, 3.0), (0.7, 1.0, 0.6), GAP)
    m.ell(V(3.6, 15.6, 5.4), (0.5, 0.3, 0.3), HEXG, kind="emit")
    m.limb(V(-6.0, 13.6, 4.0), V(1.0, 12.6, 6.4), 1.0, 0.7, GAP)
    return m


def ball_table():
    """A little round table with a cloth and the crystal ball on its claw."""
    m = h.Model()
    log(m, V(0, 0.5, 0), V(0, 14.0, 0), 1.6, HAG, step=1.0)
    for a in (0.4, 2.5, 4.6):
        log(m, V(0, 3.0, 0), V(math.cos(a) * 6.0, 0.6, math.sin(a) * 5.0), 1.0, HAG, step=0.9)
    m.ell(V(0, 15.0, 0), (9.0, 1.2, 8.0), HAG_L)
    m.ell(V(0, 15.9, 0), (7.6, 0.7, 6.6), HOODM)
    for k in range(10):
        a = 2 * math.pi * k / 10
        m.ell(V(math.cos(a) * 8.0, 14.0, math.sin(a) * 7.0), (1.6, 1.8, 1.0), HOODM, R=facing(a))
    for a in (0.6, 2.7, 4.8):
        m.limb(V(math.cos(a) * 2.6, 16.4, math.sin(a) * 2.4), V(math.cos(a) * 3.4, 19.6, math.sin(a) * 3.0), 0.5, 0.4, SILVER)
    m.ell(V(0, 21.6, 0), (4.3, 4.3, 4.3), LEAF)
    m.ell(V(-0.6, 22.2, 1.6), (3.0, 3.0, 2.8), HEXG, kind="emit")
    m.ell(V(-1.6, 23.4, 3.4), (0.9, 0.9, 0.6), HEXG, kind="emit")
    candle(m, V(5.6, 16.4, 2.4), 2.4, 0.6)
    return m


def lectern():
    m = h.Model()
    log(m, V(0, 0.5, 0), V(0.6, 24.0, -1.0), 1.8, HAG, step=1.1, taper=0.8)
    for a in (0.3, 2.4, 4.5):
        log(m, V(0, 2.4, 0), V(math.cos(a) * 6.5, 0.6, math.sin(a) * 5.5), 1.1, HAG_L, step=0.9)
    R = h.rot_x(-0.6)
    m.ell(V(0.6, 26.0, 0.0), (8.6, 1.0, 6.4), HAG_L, R=R)
    for sx in (-1, 1):
        m.ell(V(0.6 + sx * 3.9, 27.2, 0.2), (3.9, 0.7, 5.2), WINE, R=R)
        m.ell(V(0.6 + sx * 3.8, 27.9, 0.3), (3.4, 0.6, 4.7), LINEN, R=R)
        for j in range(3):
            m.ell(V(0.6 + sx * 3.8, 28.9 - j * 1.1 + 1.2, -1.6 + j * 2.0), (2.2, 0.25, 0.3), HEXG, R=R, kind="emit")
    m.limb(V(0.6, 28.6, 1.0), V(0.4, 22.0, 6.4), 0.4, 0.3, WINE)  # a ribbon marks the page
    return m


def broom_corner():
    """Her broom against a barrel, a hat on the barrel."""
    m = h.Model()
    m.ell(V(0, 9.0, 0), (7.6, 9.0, 6.6), WOODP)
    for y in (3.0, 15.0):
        for k in range(16):
            a = 2 * math.pi * k / 16
            m.ell(V(math.cos(a) * 7.4, y, math.sin(a) * 6.4), (1.6, 0.8, 0.8), IRON, R=facing(a))
    m.ell(V(0, 18.2, 0), (7.0, 0.9, 6.0), HAG_L)
    for k in range(18):  # the hat
        a = 2 * math.pi * k / 18
        m.ell(V(math.cos(a) * 6.4, 19.4, math.sin(a) * 5.4), (1.8, 0.7, 1.6), HOODM, R=facing(a))
    for j in range(9):
        t = j / 8
        m.ell(V(2.6 * t ** 2, 20.0 + 11.0 * t, 0), (3.8 * (1 - t) + 0.5, 1.6, 3.4 * (1 - t) + 0.5), HOODM)
    for k in range(12):
        a = 2 * math.pi * k / 12
        m.ell(V(math.cos(a) * 3.6, 21.4, math.sin(a) * 3.2), (1.0, 0.8, 0.7), WINE, R=facing(a))
    log(m, V(13.0, 1.0, 4.0), V(9.0, 52.0, -3.0), 0.9, BONE, step=1.0)  # the broom
    for j in range(11):
        b = -0.5 + 1.0 * j / 10
        m.limb(V(12.4, 10.0, 3.4), V(13.4 + math.sin(b) * 5.0, 0.8, 4.4 + math.cos(j * 2.0) * 1.6), 0.7, 0.4, STRAW)
    m.ell(V(12.4, 10.4, 3.4), (1.7, 1.2, 1.5), WINE)
    return m


def fern_pot():
    m = h.Model()
    m.ell(V(0, 4.0, 0), (5.0, 4.2, 4.6), CLAY)
    m.ell(V(0, 7.6, 0), (5.4, 1.0, 5.0), CLAY)
    rng = rng_for(43)
    for j in range(11):
        a = 2 * math.pi * j / 11
        reach, tall = rng.uniform(5.0, 9.0), rng.uniform(9.0, 17.0)
        prev = V(0, 7.6, 0)
        for s in range(1, 6):
            t = s / 5
            nxt = V(math.cos(a) * reach * t, 7.6 + tall * math.sin(t * 2.2), math.sin(a) * reach * t * 0.8)
            m.limb(prev, nxt, 1.1 * (1 - t) + 0.4, 0.9 * (1 - t) + 0.3, HAIRM if j % 2 else LEAF)
            prev = nxt
        if j % 3 == 0:
            m.ell(prev, (0.7, 0.7, 0.6), HEXG, kind="emit")
    return m


def chest():
    m = h.Model()
    for y in (2.6, 7.4):
        slab(m, V(-10.0, y, 0), V(10.0, y, 0), 6.0, 2.5, WOODP if y < 5 else WOODP_L, (0, 0, 1), step=1.5)
    m.ell(V(0, 11.6, 0), (10.6, 3.4, 6.4), HAG_L)
    for x in (-7.0, 0.0, 7.0):
        log(m, V(x, 0.6, 6.2), V(x, 12.0, 6.0), 0.8, IRON, step=0.9)
        m.ell(V(x, 13.8, 2.0), (0.9, 1.6, 4.6), IRON)
    m.ell(V(0, 8.0, 6.8), (1.5, 1.7, 0.6), SILVER)
    m.ell(V(0, 7.6, 7.3), (0.4, 0.7, 0.4), GAP)
    return m


def candelabra():
    """A stand of bone wood with three grave candles (the shaft)."""
    m = h.Model()
    log(m, V(0, 0.5, 0), V(0.5, 26.0, 0), 1.4, BONE, step=1.0, taper=0.7)
    for a in (0.5, 2.6, 4.7):
        log(m, V(0, 2.0, 0), V(math.cos(a) * 5.4, 0.5, math.sin(a) * 4.6), 0.9, BONE, step=0.9)
    for sx, yy in ((-1, 22.0), (1, 24.0)):
        log(m, V(0.4, yy - 4.0, 0), V(sx * 6.0, yy, 0.5), 0.8, BONE, step=0.9)
        m.ell(V(sx * 6.0, yy + 0.6, 0.5), (1.7, 0.5, 1.5), IRON)
        candle(m, V(sx * 6.0, yy + 0.8, 0.5), 3.4 if sx < 0 else 2.2)
    m.ell(V(0.5, 26.4, 0), (1.8, 0.5, 1.6), IRON)
    candle(m, V(0.5, 26.6, 0), 4.2)
    return m


def crates():
    """What is kept at the foot of the stair: crates of hag elm, a sack, jars."""
    m = h.Model()
    for (x, z, s, y0) in ((-8.0, 0.0, 8.0, 0.0), (9.0, 2.0, 6.5, 0.0), (-6.0, -1.0, 6.0, 16.0)):
        for k in range(3):
            slab(m, V(x - s, y0 + 2.6 + k * 5.0, z), V(x + s, y0 + 2.6 + k * 5.0, z), s * 0.8, 2.4, WOODP if k % 2 else WOODP_L, (0, 0, 1), step=1.5)
        for sx in (-1, 1):
            log(m, V(x + sx * s, y0 + 0.5, z + s * 0.8), V(x + sx * s, y0 + 15.0, z + s * 0.8), 1.0, HAG, step=1.0)
    m.ell(V(19.0, 5.0, 5.0), (5.4, 5.4, 4.6), LINEN)  # a sack, tied
    m.ell(V(19.0, 10.6, 5.0), (2.0, 1.6, 1.8), LINEN)
    m.ell(V(19.0, 9.6, 5.0), (2.4, 0.6, 2.2), WINE)
    bottle(m, V(9.0, 13.4, 2.0), BREW, 1.1, True)
    skull(m, V(-6.0, 31.2, -1.0), 0.9)
    for dx, dz, s in ((-17.0, 6.0, 1.0), (-19.5, 2.0, 0.7), (26.0, 3.0, 0.8)):  # toad caps in the damp
        m.limb(V(dx, 0.6, dz), V(dx, 3.2 * s, dz), 0.8 * s, 0.7 * s, WAX)
        m.ell(V(dx, 3.8 * s, dz), (2.8 * s, 1.7 * s, 2.4 * s), WINE)
        m.ell(V(dx - 0.8 * s, 4.9 * s, dz + 0.9 * s), (0.5, 0.4, 0.4), WAX)
    return m


def hung(name, build, seed):
    """Something that hangs: rendered with its top at the picture's top, the cord in the middle."""
    m = h.Model()
    build(m)
    arr = to_array(hut_lib.render(m, 120, 220, 200))
    ys, xs = np.nonzero(arr[..., 3])
    half = max(60 - int(xs.min()), int(xs.max()) + 1 - 60)
    crop = grain(arr[int(ys.min()):int(ys.max()) + 1, 60 - half:60 + half], seed, amount=0.4, mats=GRAINED)
    save(OUT / f"{name}.png", crop)
    g = glow_of(crop, LIT)
    if g[..., 3].any():
        save(OUT / f"{name}_glow.png", g)
    PARTS[name] = {"size": [crop.shape[1], crop.shape[0]], "glow": bool(g[..., 3].any())}


def chandelier(m):
    """A wheel of bone wood on chains, candles all round it."""
    top = 80.0
    for j in range(16):
        m.ell(V(0, top - j * 1.9, 0), (0.55, 0.8, 0.4) if j % 2 else (0.4, 0.8, 0.55), IRON)
    y = top - 44.0
    for a in (0.5, 2.6, 4.7):
        m.limb(V(0, top - 30.0, 0), V(math.cos(a) * 12.0, y + 1.0, math.sin(a) * 10.0), 0.3, 0.3, IRON)
    for k in range(26):
        a = 2 * math.pi * k / 26
        m.ell(V(math.cos(a) * 13.0, y, math.sin(a) * 11.0), (2.0, 1.2, 1.3), BONE, R=facing(a))
    for k in range(6):
        a = 2 * math.pi * (k + 0.3) / 6
        candle(m, V(math.cos(a) * 13.0, y + 1.0, math.sin(a) * 11.0), 2.4 + (k % 2), 0.7)
    for k in range(3):
        a = 2 * math.pi * (k + 0.1) / 3
        m.limb(V(math.cos(a) * 13.0, y - 1.0, math.sin(a) * 11.0), V(math.cos(a) * 13.0, y - 7.0 - k * 2.0, math.sin(a) * 11.0), 0.3, 0.2, HAIRM)
        m.ell(V(math.cos(a) * 13.0, y - 8.0 - k * 2.0, math.sin(a) * 11.0), (0.9, 1.2, 0.7), BONE)


def shaft_lantern(m):
    """A cage lantern on a long chain down the middle of the shaft."""
    top = 150.0
    for j in range(50):
        m.ell(V(0, top - j * 2.0, 0), (0.55, 0.9, 0.4) if j % 2 else (0.4, 0.9, 0.55), IRON)
    y = top - 100.0
    m.ell(V(0, y - 1.0, 0), (3.6, 1.1, 3.4), IRON)
    m.ell(V(0, y - 6.0, 0), (2.6, 3.4, 2.4), HEXG, kind="emit")
    for b in np.linspace(0, 2 * math.pi, 7)[:-1]:
        m.limb(V(math.cos(b) * 3.4, y - 1.0, math.sin(b) * 3.2), V(math.cos(b) * 3.4, y - 11.0, math.sin(b) * 3.2), 0.3, 0.3, IRON)
    m.ell(V(0, y - 11.4, 0), (3.6, 1.0, 3.4), IRON)
    m.limb(V(0, y - 12.0, 0), V(0, y - 16.0, 0), 0.3, 0.2, HAIRM)
    m.ell(V(0, y - 17.0, 0), (1.0, 1.3, 0.8), BONE)


def door_leaf():
    """The gate from inside: planks of hag elm in an arch, iron bands, the spy hole."""
    m = h.Model()
    for i, x in enumerate(np.arange(-12.0, 12.1, 3.0)):
        top = 19.0 + math.sqrt(max(0.0, 1.0 - (x / 14.0) ** 2)) * 9.0
        slab(m, V(x, 1.0, 0), V(x, top, 0), 1.5, 0.8, WOODP_L if i % 3 == 1 else WOODP, (0, 0, 1), step=1.2)
    for y in (5.0, 14.0, 22.0):
        log(m, V(-13.0, y, 1.0), V(13.0, y, 1.0), 0.9, IRON, step=0.9)
    m.ell(V(0, 18.0, 1.2), (1.6, 1.6, 0.5), HEXG, kind="emit")
    for k in range(10):
        b = 2 * math.pi * k / 10
        m.ell(V(8.0 + math.cos(b) * 2.0, 10.0 + math.sin(b) * 2.0, 1.4), (0.6, 0.6, 0.5), SILVER)
    arr = to_array(hut_lib.render(m, 80, 80, 70, pitch=4.0))
    ys, xs = np.nonzero(arr[..., 3])
    crop = grain(arr[int(ys.min()):int(ys.max()) + 1, int(xs.min()):int(xs.max()) + 1], 3, amount=0.4, mats=GRAINED)
    save(OUT / "door.png", crop)
    PARTS["door"] = {"size": [crop.shape[1], crop.shape[0]]}


def railing(room):
    """The stair head's railing: short pieces (two posts and their rails) that each sort by their own foot."""
    R, cx, cy = room.R, room.cx, room.cy
    ri = R - HOLE[2] - 3.0
    pts = [(cx + ri * math.cos(a), cy - ri * math.sin(a)) for a in np.linspace(HOLE[0] - 0.05, HOLE[1] - 0.2, 6)]
    pts = [(cx + (R - 4) * math.cos(HOLE[0] - 0.05), cy - (R - 4) * math.sin(HOLE[0] - 0.05))] + pts
    out = []
    post, rail, dark, bone = h.RAMPS[HAG_L][2], h.RAMPS[HAG_L][3], h.RAMPS[HAG][0], h.RAMPS[BONE][2]
    for i, (p, q) in enumerate(zip(pts, pts[1:])):
        x0, x1 = int(min(p[0], q[0])) - 2, int(max(p[0], q[0])) + 3
        y1 = int(max(p[1], q[1])) + 1
        y0 = int(min(p[1], q[1])) - 15
        arr = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        for n in range(40):  # two rails
            t = n / 39
            x, y = p[0] + (q[0] - p[0]) * t - x0, p[1] + (q[1] - p[1]) * t - y0
            for lift, col in ((13, rail), (12, post), (7, post)):
                arr[int(y) - lift, int(x)] = col
        for (x, y) in (p, q):
            xi, yi = int(x) - x0, int(y) - y0
            for j in range(15):
                arr[yi - j, xi - 1:xi + 2] = (dark, post if j < 14 else bone, dark)
            arr[yi - 15, xi] = bone
        save(OUT / f"rail_{i}.png", arr)
        out.append({"id": f"rail_{i}", "tex": f"rail_{i}.png", "pos": [x0 + (x1 - x0) / 2.0, y1], "feet": arr.shape[0]})
    return out


# ------------------------------------------------------------------ the data
def prop(pid, name, pos, solid=None, light=None, extra=None):
    p = PARTS[name]
    out = {"id": pid, "tex": f"{name}.png", "pos": [round(pos[0]), round(pos[1])], "feet": p["feet"]}
    if p.get("glow"):
        out["glow"] = f"{name}_glow.png"
    if solid:
        out["solid"] = solid
    if light:
        out["light"] = light
    out.update(extra or {})
    return out


def counter_walls(bar):
    """Follow the counter's wood silhouette. Candles and bottles sit above the back edge."""
    width, height, feet = 200, 200, 170  # same render and anchor as render_part
    alpha = to_array(hut_lib.render(counter(decorated=False), width, height, feet))[:, :, 3]
    x0, y0 = bar[0] - width // 2, bar[1] - feet
    columns = np.flatnonzero(alpha.any(axis=0))
    out = []
    for x in range(int(columns[0]), int(columns[-1]) + 1, 4):
        end = min(x + 4, int(columns[-1]) + 1)
        rows = np.flatnonzero(alpha[:, x:end].any(axis=1))
        top = y0 + int(rows[0])
        base = y0 + int(rows[-1]) - 6  # the top of the player's foot capsule is 6 px above the feet
        if base > top:
            out.append([x0 + x, top, end - x, base - top])
    return out


def rounded(poly):
    return [[round(float(x), 1), round(float(y), 1)] for x, y in poly]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    green = "#a8ff6a"
    # ---- the shaft
    room, arr, glow, front, outlines, lights = stairs_room()
    save(OUT / "stairs.png", arr)
    save(OUT / "stairs_glow.png", glow)
    save(OUT / "stairs_front.png", front[room.cy:])
    door_leaf()
    render_part("candelabra", candelabra(), 11)
    render_part("crates", crates(), 12)
    hung("shaft_lantern", shaft_lantern, 13)
    cx, cy, R = room.cx, room.cy, room.R
    dw, dh = PARTS["door"]["size"]
    top = (cx - (R - SW / 2), cy - SH)  # the stair's head
    stairs = {
        "title": "Hexenturm", "dir": DIR, "size": [room.w, room.h], "corner": room.w // 2, "front_y": cy, "front_tex": "stairs_front.png",
        "ambient": {"day": "#a4aebb", "night": "#565678"}, "entry": [cx, cy + R - 26],
        "exit_door": {"id": "door", "pos": [cx, cy + R - 9], "leaf": [cx - dw // 2, cy + R + T - dh]},
        "shell": [{"tex": "stairs.png", "pos": [0, 0], "z": -6, "glow": True}],
        "outlines": [rounded(o) for o in outlines],
        "passages": [{"pos": [round(top[0]), round(top[1]) + 6], "to": "witch_room", "label": "HINAUF", "face": [1, 0]}],
        "props": [
            prop("candelabra_a", "candelabra", (cx - 34, cy + 52), [8, 6, -4, -5], {"color": green, "radius": 60, "energy": 0.8}),
            prop("candelabra_b", "candelabra", (cx + 46, cy + 40), [8, 6, -4, -5], {"color": green, "radius": 60, "energy": 0.8}),
            prop("crates", "crates", (cx - 22, cy - 34), [46, 12, -22, -11]),
        ],
        "hanging": [{"id": "lantern", "tex": "shaft_lantern.png", "glow": "shaft_lantern_glow.png", "pos": [cx + 6, cy - 150], "sway": 0.025, "speed": 0.5, "light": {"color": green, "radius": 96, "energy": 0.9, "drop": 150}}],
        "lights": lights + [{"pos": [cx, cy], "color": green, "radius": 46, "squash": 0.9, "energy": 0.5}],
    }
    shaft_room, shaft_arr = room, arr
    # ---- the chamber
    room, arr, glow, front, outlines, lights = chamber_room()
    save(OUT / "room.png", arr)
    save(OUT / "room_glow.png", glow)
    save(OUT / "room_front.png", front[room.cy:])
    for name, build, seed in (("counter", counter, 21), ("cauldron", cauldron, 22), ("bookcase", bookcase, 23), ("armchair", armchair, 24), ("ball_table", ball_table, 25), ("lectern", lectern, 26), ("jeweller", jeweller, 31), ("broom", broom_corner, 27), ("fern", fern_pot, 28), ("chest", chest, 29)):
        render_part(name, build(), seed)
    flames(), brew(), steam()
    hung("chandelier", chandelier, 30)
    cx, cy, R = room.cx, room.cy, room.R
    rails = railing(room)
    pot = (cx + 28, cy - 64)  # the cauldron's feet
    bar = (cx, cy - 8)  # the counter's
    head_a = HOLE[1] + 0.2
    head = (cx + (R - 18) * math.cos(head_a), cy - (R - 18) * math.sin(head_a))  # where she stands when she comes up
    shaft_cx, shaft_cy = shaft_room.cx, shaft_room.cy
    stairs["passages"][0]["at"] = [round(head[0]), round(head[1])]
    chamber = {
        "title": "Hexenstube", "dir": DIR, "size": [room.w, room.h], "corner": room.w // 2,
        "ambient": {"day": "#b4b8c4", "night": "#5e5a7a"}, "entry": [round(head[0]), round(head[1])],
        "shell": [{"tex": "room.png", "pos": [0, 0], "z": -6, "glow": True}],
        "front": [{"tex": "room_front.png", "pos": [0, cy]}],
        "outlines": [rounded(o) for o in outlines],
        "passages": [{"pos": [round(cx + (R - 16) * math.cos(HOLE[1] - 0.02)), round(cy - (R - 16) * math.sin(HOLE[1] - 0.02))], "to": "witch_stairs", "label": "HINAB", "face": [1, 0], "reach": 9,
                      "at": [round(shaft_cx - (shaft_room.R - SW / 2) + 8), round(shaft_cy - SH - 12)]}],  # on the stair's top landing (y +5 lay below its closed end, outside every walkable piece: stuck)
        "witch_spot": [cx - 10, cy - 40], "resident": "witch",
        "props": [
            prop("cauldron", "cauldron", pot, [70, 22, -34, -20], {"color": green, "radius": 92, "energy": 1.1}),
            prop("jeweller", "jeweller", (cx - 40, cy - 68), [36, 10, -18, -9], {"color": green, "radius": 36, "energy": 0.5}),
            prop("counter", "counter", bar, None, {"color": green, "radius": 50, "energy": 0.45}),
            prop("bookcase", "bookcase", (cx - 64, cy - 44), [40, 9, -20, -8]),  # against the left wall behind the counter: the right end stays free, a way round to her
            prop("armchair", "armchair", (cx + 62, cy + 44), [22, 12, -11, -11]),
            prop("ball_table", "ball_table", (cx + 48, cy + 70), [12, 8, -6, -7], {"color": green, "radius": 44, "energy": 0.6}),
            prop("lectern", "lectern", (cx - 44, cy + 22), [10, 7, -5, -6], {"color": green, "radius": 36, "energy": 0.4}),
            prop("broom", "broom", (cx - 80, cy - 26), [32, 10, -14, -9]),
            prop("fern_a", "fern", (cx + 86, cy + 22), [8, 6, -4, -5]),
            prop("fern_b", "fern", (cx + 80, cy - 52), [8, 6, -4, -5]),
            prop("chest", "chest", (cx + 14, cy + 95), [20, 9, -10, -8]),
        ] + rails,
        "walls": counter_walls(bar),
        "anims": [
            {"id": "flames", "tex": "flames.png", "frames": PARTS["flames"]["frames"], "pos": [pot[0], pot[1] + 1], "feet": PARTS["flames"]["feet"], "fps": 11.0, "unlit": True, "z": 0},
            {"id": "brew", "tex": "brew.png", "frames": 6, "pos": [pot[0], pot[1] + 1], "feet": 32, "fps": 5.0, "unlit": True, "z": 0},
            {"id": "steam", "tex": "steam.png", "frames": 8, "pos": [pot[0], pot[1] + 1], "feet": 69, "fps": 6.0, "unlit": True, "z": 0},
        ],
        "hanging": [{"id": "chandelier", "tex": "chandelier.png", "glow": "chandelier_glow.png", "pos": [cx - 3, cy - 174], "sway": 0.02, "speed": 0.45, "light": {"color": green, "radius": 110, "energy": 0.8, "drop": 90}}],
        "lights": lights,
    }
    text = DATA.read_text(encoding="utf-8")
    table = json.loads(text)
    table["witch_stairs"], table["witch_room"] = stairs, chamber
    DATA.write_text(json.dumps(table, indent=1, ensure_ascii=False), encoding="utf-8", newline="\n")
    print("witch tower inside:", {k: v["size"] for k, v in PARTS.items()})
    png = [a for a in sys.argv[1:] if a.endswith(".png")]
    if png:
        from PIL import Image

        def compose(spec, base, front_name):
            img = Image.fromarray(base).convert("RGBA")
            items = []
            for p in spec["props"]:
                im = Image.open(OUT / p["tex"])
                items.append((p["pos"][1], im, (int(p["pos"][0] - im.width / 2), int(p["pos"][1] - p["feet"]) if p["feet"] else int(p["pos"][1] - im.height))))
            for _, im, at in sorted(items, key=lambda t: t[0]):
                img.alpha_composite(im, (max(at[0], 0), max(at[1], 0)))
            for a in spec.get("anims", []):
                im = Image.open(OUT / a["tex"])
                fw = im.width // a["frames"]
                img.alpha_composite(im.crop((0, 0, fw, im.height)), (int(a["pos"][0] - fw / 2), int(a["pos"][1] - a["feet"])))
            fr = Image.open(OUT / front_name)
            img.alpha_composite(fr, (0, img.height - fr.height))
            for hg in spec.get("hanging", []):
                im = Image.open(OUT / hg["tex"])
                img.alpha_composite(im, (int(hg["pos"][0] - im.width / 2), max(int(hg["pos"][1]), 0)))
            return img
        a, b = compose(stairs, shaft_arr, "stairs_front.png"), compose(chamber, arr, "room_front.png")
        sheet = Image.new("RGBA", (a.width + b.width + 30, max(a.height, b.height) + 20), (9, 6, 16, 255))
        sheet.alpha_composite(a, (10, 10))
        sheet.alpha_composite(b, (a.width + 20, 10))
        sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(png[0])


if __name__ == "__main__":
    main()
