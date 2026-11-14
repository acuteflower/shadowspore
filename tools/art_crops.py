#!/usr/bin/env python3
"""The crops of the town's fields and their seed packets (docs/farming.md). Needs numpy + PIL (`py -3`).
  assets/props/crops/crop_<id>.png        4 stages side by side (sprout, young, grown, ripe), frames 24x32, feet at (12, 29)
  assets/props/crops/crop_<id>_glow.png   only the emissive pixels of the ripe crop (ember carrot, night beet), same layout, drawn unlit by FieldCell
  assets/items/<seed>.png                 seed packets 16x16 (check: one piece, 1 px margin, ink outline 1b1a2e)
Style like the rest of the meadow: lit from the top left, a cool rim on the right, violet-ink outline. Every part is drawn flat into a material
index image first (polygons, ellipses), then one shading pass lights the edges (top / left rim bright, bottom / right dark) and adds a little dither, so
all plants share the same light. The ripe crops of the town and of the wild (`tools/art_flora.py`) use the same ramps.
`py -3 tools/art_crops.py [preview.png]` writes the files, the optional argument also a 6x contact sheet."""
import math
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import ROOT, hexc  # noqa: E402

FW, FH = 24, 32
FEET = (12, 29)
STAGES = 4
INK = hexc("12141f")
ICON_INK = hexc("1b1a2e")
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def ramp(*c):
    return [hexc(x) for x in c]


LEAFW = ramp("12283a", "1c4a46", "2c6e54", "449a62", "6cc47a", "a4eca0")
CARG = ramp("10283a", "1c4a50", "2e7a64", "4aa87a", "7ad89a", "b8f4c0")
CARR = ramp("4a1410", "9a2e18", "e0701c", "ffa83a", "ffe08a")
BEETL = ramp("1a0a2a", "3a1450", "5a2a70", "7a4a98", "a070c0", "d0a0e8")
BEETR = ramp("0e0820", "2a1248", "4a2478", "7a3ca0", "a870d0")
BEET_ST = ramp("4a0e3a", "8a1e64", "c8408c")
TUB = ramp("3a2450", "6a4a80", "a082a8", "d8c0d0", "f4e8ec")
SOIL = ramp("1e1428", "3a2838", "5a4048", "7a6068")
SPIKE = ramp("4a2c6a", "8a5ab0", "c890d8", "f0c8f0")
SHEEN = hexc("4cc8c8")
EMBER_G = hexc("ffb25a")
EMBER_GL = hexc("fff0b0")
PAPER = ramp("3a2c3a", "6a5560", "a08a82", "d0bca8", "ece0cc")
TWINE = ramp("4a3220", "7a5a38", "b08a58")

# New Etappe 1 crop ramps: Mondlauch (moon_leek), Quellmelone (oasis_melon), Bernsteinkorn (amber_grain)
LEEK_BASE = ramp("34405a", "5c748c", "94b6c2", "cdeae8", "f2fffa")
LEEK_LEAF = ramp("142c3e", "1f4e58", "327a7a", "54ae9e", "86d8c4", "c4f6e6")
LEEK_UMBEL = ramp("1e5264", "368894", "64cecc", "a8f6ec", "ecfffa")
MOON_GLOW = hexc("96fcf0")
MOON_HOT = hexc("ecfffa")
MOON_STEM_GLOW = hexc("58dfd2")

VINE_LEAF = ramp("122838", "1c4c48", "2c785c", "48a874", "76d492", "b2f2bc")
MELON_RIND = ramp("0e2838", "164e5c", "207c86", "32aeb2", "5ed8d4", "a8f8f0")
MELON_BLOSSOM = ramp("6a3218", "b46220", "eea238", "ffd874", "fff4b8")

GRAIN_SHOOT = ramp("182834", "264c44", "3e7652", "64a462", "96cc78", "c8ec9e")
GRAIN_STALK = ramp("3a2218", "6e4422", "a87230", "dca448", "f6cc72", "ffea9e")
GRAIN_EAR = ramp("4a2014", "8c3e18", "cc6e1e", "f4a22e", "ffd25a", "fff2a6")

MATERIALS = {
    "leaf": LEAFW, "carg": CARG, "carr": CARR, "beetl": BEETL, "beetr": BEETR, "stem": BEET_ST, "tub": TUB, "soil": SOIL, "spike": SPIKE,
    "paper": PAPER, "twine": TWINE,
    "leek_base": LEEK_BASE, "leek_leaf": LEEK_LEAF, "leek_umbel": LEEK_UMBEL,
    "vine": VINE_LEAF, "melon": MELON_RIND, "blossom": MELON_BLOSSOM,
    "grain_shoot": GRAIN_SHOOT, "grain_stalk": GRAIN_STALK, "grain_ear": GRAIN_EAR,
}
ORDER = list(MATERIALS)


class Canvas:
    """A material-index image plus detail/emissive layers; `render()` shades it."""

    def __init__(self, w=FW, h=FH):
        self.w, self.h = w, h
        self.img = Image.new("L", (w, h), 0)
        self.draw = ImageDraw.Draw(self.img)
        self.detail = {}  # (x, y) -> rgba painted before outline
        self.glow = {}  # (x, y) -> colour
        self.soft_glow = {}  # (x, y) -> (r, g, b, a) subtle emissive-only accents

    def mat(self, name):
        return ORDER.index(name) + 1

    def poly(self, pts, name):
        self.draw.polygon([(round(x), round(y)) for x, y in pts], fill=self.mat(name))

    def ellipse(self, cx, cy, rx, ry, name):
        self.draw.ellipse([round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry)], fill=self.mat(name))

    def line(self, pts, name, width=1):
        self.draw.line([(round(x), round(y)) for x, y in pts], fill=self.mat(name), width=width)

    def dot(self, x, y, name):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((int(x), int(y)), self.mat(name))

    def paint(self, x, y, colour):
        xi, yi = int(round(x)), int(round(y))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            self.detail[(xi, yi)] = (*colour[:3], 255)

    def emit(self, x, y, colour, dim_name=None):
        xi, yi = int(round(x)), int(round(y))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            self.glow[(xi, yi)] = colour
            if dim_name:
                self.dot(xi, yi, dim_name)

    def emit_subtle(self, x, y, colour, alpha=145):
        xi, yi = int(round(x)), int(round(y))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            self.soft_glow[(xi, yi)] = (*colour[:3], int(alpha))

    def leaf(self, x0, y0, ang, length, width, name, curve=0.0, rib=None):
        """A lanceolate leaf from (x0, y0) pointing along `ang` (0 = right, -pi/2 = up), bending by `curve` radians over its length."""
        n = 14
        if length > 9:
            length = 9 + (length - 9) * 0.5  # the big stages must stay inside the 24 px frame
            width *= 0.92
        if abs(math.cos(ang)) > 0.85 and length > 7:
            length *= 0.72  # the flat outer leaves reach sideways the furthest
        left, right, mid = [], [], []
        x, y, a = float(x0), float(y0), ang
        for i in range(n + 1):
            t = i / n
            w = width * math.sin(math.pi * min(1.0, t ** 0.7)) * 0.5 + (0.0 if i < n else 0.0)
            nx, ny = math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)
            left.append((x + nx * w, y + ny * w))
            right.append((x - nx * w, y - ny * w))
            mid.append((x, y))
            x += math.cos(a) * length / n
            y += math.sin(a) * length / n
            a += curve / n
        self.poly(left + right[::-1], name)
        if rib:
            self.line(mid[1:-2], rib)

    def render(self, outline=True, ink_col=None):
        """-> (RGBA numpy array (h, w, 4) lit and outlined, RGBA glow array)."""
        oc = INK if ink_col is None else ink_col
        a = np.array(self.img)
        out = np.zeros((self.h, self.w, 4), np.uint8)
        glow = np.zeros((self.h, self.w, 4), np.uint8)
        for y in range(self.h):
            for x in range(self.w):
                m = int(a[y, x])
                if m == 0:
                    continue
                ramp_ = MATERIALS[ORDER[m - 1]]

                def other(dx, dy):
                    xx, yy = x + dx, y + dy
                    return not (0 <= xx < self.w and 0 <= yy < self.h) or int(a[yy, xx]) != m

                top, left = other(0, -1), other(-1, 0)
                bottom, right = other(0, 1), other(1, 0)
                n = len(ramp_)
                if top or left:
                    idx = n - 2 if not (bottom or right) else n - 3
                elif bottom or right:
                    idx = 1
                else:
                    idx = n // 2
                    if BAYER[y % 4][x % 4] < 5:
                        idx = n // 2 + 1 if n > 3 else idx
                    elif BAYER[y % 4][x % 4] > 12:
                        idx = n // 2 - 1
                idx = max(0, min(n - 1, idx))
                out[y, x] = ramp_[idx]
        for (x, y), colour in self.detail.items():
            out[y, x] = colour
        for (x, y), rgba in self.soft_glow.items():
            glow[y, x] = rgba
        for (x, y), colour in self.glow.items():
            out[y, x] = (*colour[:3], 255)
            glow[y, x] = (*colour[:3], 255)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < self.w and 0 <= yy < self.h and glow[yy, xx][3] == 0:
                    glow[yy, xx] = (*colour[:3], 70)
        if outline:
            src = out.copy()
            for y in range(self.h):
                for x in range(self.w):
                    if src[y, x][3]:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < self.w and 0 <= yy < self.h and src[yy, xx][3]:
                            out[y, x] = oc
                            break
        return out, glow


# ------------------------------------------------------------------ crops
def mound(c, cx, w=9):
    c.ellipse(cx, FEET[1] - 0.5, w / 2.0, 2.2, "soil")


def tuber(stage, rng):
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 9 + stage)
    if stage == 0:
        c.leaf(cx - 1, gy - 2, -2.2, 5, 3.2, "leaf")
        c.leaf(cx + 1, gy - 2, -0.95, 5, 3.2, "carg")
    elif stage == 1:
        for ang, ln, nm in ((-2.5, 8, "carg"), (-0.65, 8, "leaf"), (-1.57, 9, "leaf"), (-2.0, 7, "leaf")):
            c.leaf(cx, gy - 2, ang, ln, 4.2, nm, curve=0.5 if math.cos(ang) > 0 else -0.5, rib="carg")
    elif stage == 2:
        for ang, ln, nm in ((-2.9, 11, "carg"), (-0.25, 11, "carg"), (-2.4, 12, "leaf"), (-0.75, 12, "leaf"), (-1.57, 13, "leaf"), (-1.95, 11, "carg"), (-1.2, 11, "carg")):
            c.leaf(cx, gy - 2, ang, ln, 5.2, nm, curve=0.6 if math.cos(ang) > 0 else -0.6, rib="leaf")
    else:
        for ang, ln, nm in ((-2.75, 12, "carg"), (-0.4, 12, "carg"), (-2.45, 14, "leaf"), (-0.7, 14, "leaf"), (-1.57, 15, "leaf"), (-2.0, 13, "carg"), (-1.15, 13, "carg")):
            c.leaf(cx, gy - 3, ang, ln, 5.6, nm, curve=0.7 if math.cos(ang) > 0 else -0.7, rib="leaf")
        c.ellipse(cx - 3, gy - 1.5, 4.0, 3.0, "tub")  # the pale tubers pushing out of the earth
        c.ellipse(cx + 3.5, gy - 1, 3.2, 2.5, "tub")
    return c


def ember_carrot(stage, rng):
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 8 + stage)
    fronds = {0: 3, 1: 5, 2: 7, 3: 8}[stage]
    height = {0: 5, 1: 9, 2: 13, 3: 15}[stage]
    for i in range(fronds):
        t = (i - (fronds - 1) / 2.0) / max((fronds - 1) / 2.0, 1.0)
        ang = -math.pi / 2 + t * 0.72
        c.leaf(cx + t * 1.5, gy - 3, ang, height * (1.0 - 0.18 * abs(t)), 2.4 + 0.5 * stage, "carg" if i % 2 else "leaf", curve=t * 0.5)
        if stage >= 2:  # feathery: a second pair of small blades on the stalk
            c.leaf(cx + t * 3.0, gy - 3 - height * 0.5, ang + 0.5 * (1 if t > 0 else -1), height * 0.4, 1.8, "leaf", curve=t * 0.4)
    if stage == 3:
        c.ellipse(cx, gy - 1.5, 3.6, 2.4, "carr")  # the glowing shoulder of the carrot
        for dx, dy in ((-2, -2), (-1, -3), (1, -2), (0, -1), (2, -1)):
            c.emit(cx + dx, gy + dy, EMBER_G if (dx + dy) % 2 else EMBER_GL, "carr")
    return c


def night_beet(stage, rng):
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 9 + stage)
    if stage == 0:
        c.leaf(cx - 1, gy - 2, -2.1, 5, 3.0, "beetl")
        c.leaf(cx + 1, gy - 2, -1.0, 5, 3.0, "beetl")
    else:
        count = {1: 4, 2: 5, 3: 6}[stage]
        ln = {1: 8, 2: 12, 3: 14}[stage]
        for i in range(count):
            t = (i - (count - 1) / 2.0) / ((count - 1) / 2.0)
            ang = -math.pi / 2 + t * 0.8
            x0, y0 = cx + t * 1.5, gy - 3
            c.line([(x0, y0), (x0 + math.cos(ang) * ln * 0.45, y0 + math.sin(ang) * ln * 0.45)], "stem")  # the magenta stalk
            c.leaf(x0 + math.cos(ang) * ln * 0.3, y0 + math.sin(ang) * ln * 0.3, ang, ln * 0.8, 4.6 + stage * 0.4, "beetl", curve=t * 0.6, rib="stem")
    if stage == 3:
        c.ellipse(cx, gy - 1.2, 4.0, 2.8, "beetr")  # the dark crown showing
        for dx, dy in ((-2, -2), (1, -3), (2, -1), (-1, -1), (3, -2)):
            c.emit(cx + dx, gy + dy, SHEEN, "beetr")
    return c


def wound_leaf(stage, rng):
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 9 + stage)
    leaves = {0: [(-2.4, 5), (-0.75, 5)], 1: [(-2.7, 7), (-0.45, 7), (-1.57, 8)],
              2: [(-2.95, 9), (-0.2, 9), (-2.4, 11), (-0.75, 11), (-1.57, 12)], 3: [(-3.0, 10), (-0.15, 10), (-2.45, 12), (-0.7, 12), (-1.9, 13), (-1.25, 13)]}[stage]
    for i, (ang, ln) in enumerate(leaves):
        c.leaf(cx, gy - 2, ang, ln, 4.8 + stage * 0.4, "carg" if i % 2 else "leaf", curve=0.55 if math.cos(ang) > 0 else -0.55, rib="carg")
    if stage == 3:
        for dx, h in ((-3, 20), (1, 23), (4, 18)):  # the violet spikes: ready to pluck
            c.line([(cx + dx * 0.5, gy - 4), (cx + dx, gy - h + 6)], "carg")
            c.poly([(cx + dx - 1, gy - h + 6), (cx + dx + 1, gy - h + 6), (cx + dx + 1, gy - h + 1), (cx + dx, gy - h), (cx + dx - 1, gy - h + 1)], "spike")
    return c


def moon_leek(stage, rng):
    """Mondlauch: slender silvery-jade leek shanks & arching strap blades crowned at Stage 3 with luminous mint-teal moonflower umbels."""
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 8 + stage)
    if stage == 0:
        c.line([(cx, gy - 1), (cx, gy - 4)], "leek_base", width=2)
        c.leaf(cx - 0.5, gy - 3, -1.9, 5.5, 2.2, "leek_leaf", curve=-0.35)
        c.leaf(cx + 0.5, gy - 3, -1.25, 5.8, 2.2, "leek_leaf", curve=0.35)
    elif stage == 1:
        for ox, top in ((-1.2, 5), (1.2, 6)):
            c.line([(cx + ox, gy - 1), (cx + ox, gy - top)], "leek_base", width=2)
        for ang, ln, cv in ((-2.35, 8.5, -0.55), (-1.85, 10.0, -0.25), (-1.3, 10.2, 0.25), (-0.8, 8.5, 0.55)):
            c.leaf(cx, gy - 4, ang, ln, 2.7, "leek_leaf", curve=cv)
    elif stage == 2:
        for ang, ln, cv in ((-2.5, 9.5, -0.68), (-2.05, 11.5, -0.42), (-1.1, 11.5, 0.42), (-0.65, 9.5, 0.68)):
            c.leaf(cx, gy - 5, ang, ln, 2.9, "leek_leaf", curve=cv)
        for ox, top in ((-1.8, 6), (1.5, 5)):
            c.line([(cx + ox, gy - 1), (cx + ox, gy - top)], "leek_base", width=2)
        c.paint(cx, gy - 3, LEEK_BASE[1])
        c.paint(cx, gy - 4, LEEK_LEAF[2])
        # two tall slender scapes with closed teardrop moonflower spathes (budding)
        for sx, tx, ty in ((cx - 1.5, cx - 2, gy - 18), (cx + 1.5, cx + 3, gy - 14)):
            c.line([(sx, gy - 5), (tx, ty + 2)], "leek_leaf")
            c.poly([(tx - 1.5, ty + 2), (tx + 1.5, ty + 2), (tx, ty - 2)], "leek_umbel")
    else:
        for ang, ln, cv in ((-2.55, 10.0, -0.72), (-2.08, 12.0, -0.48), (-1.08, 12.0, 0.48), (-0.6, 10.0, 0.72)):
            c.leaf(cx, gy - 5, ang, ln, 3.0, "leek_leaf", curve=cv)
        # slender cylindrical silvery-pearl leek shanks separated by a cool jade crease
        for ox, top in ((-2, 7), (2, 6)):
            for yy in range(gy - top, gy):
                c.paint(cx + ox - 1, yy, LEEK_BASE[4 if yy < gy - 2 else 3])
                c.paint(cx + ox, yy, LEEK_BASE[2 if yy < gy - 2 else 1])
        for yy in range(gy - 6, gy - 1):
            c.paint(cx, yy, LEEK_LEAF[1 if yy > gy - 4 else 2])
        # central & companion allium scapes rising to luminous moonflower umbels
        scapes = [
            ((cx - 1, gy - 7), (cx - 1, gy - 21), 3.6),
            ((cx + 2, gy - 6), (cx + 4, gy - 15), 2.7),
        ]
        for (x0, y0), (ux, uy), ur in scapes:
            steps = int(abs(y0 - uy))
            for k in range(steps + 1):
                t = k / max(steps, 1)
                sx = round(x0 + (ux - x0) * t)
                sy = round(y0 + (uy - y0) * t)
                c.dot(sx, sy, "leek_leaf")
                if k % 2 == 1 and t > 0.22:  # subtle luminescent vein highlights along the upper stem
                    c.paint(sx, sy, LEEK_LEAF[4])
                    c.emit_subtle(sx, sy, MOON_STEM_GLOW, 155)
            c.ellipse(ux, uy, ur, ur * 0.88, "leek_umbel")
        # starry glowing florets across the main and side umbels
        for dx, dy, hot in (
            (-1, -23, True), (-3, -22, False), (1, -22, True), (-2, -20, True), (0, -21, True),
            (-4, -20, False), (2, -20, False), (-1, -19, False),
            (4, -17, True), (2, -15, False), (5, -15, True), (4, -14, False),
        ):
            c.emit(cx + dx, gy + dy, MOON_HOT if hot else MOON_GLOW, "leek_umbel")
    return c


def _paint_melon(c, mx, my, rx, ry, stripes=3):
    """Shades a plump round Quellmelone with curved turquoise/deep-teal stripes and a dewy highlight."""
    c.ellipse(mx, my, rx, ry, "melon")
    for y in range(int(my - ry) - 1, int(my + ry) + 2):
        for x in range(int(mx - rx) - 1, int(mx + rx) + 2):
            dx = (x - mx) / rx
            dy = (y - my) / ry
            d2 = dx * dx + dy * dy
            if d2 > 0.96:
                continue
            # spherical light from top-left + curved longitudinal stripes
            light = -0.55 * dx - 0.65 * dy + 0.25 * math.sqrt(max(0.0, 1.0 - d2))
            lon = dx / math.sqrt(max(0.18, 1.0 - 0.72 * dy * dy))
            band = math.cos(lon * math.pi * stripes)
            if band > 0.42:  # dark emerald-teal meridian stripe
                idx = 1 if light < 0.05 else 2 if light < 0.42 else 3
            else:  # bright turquoise rind between stripes
                idx = 2 if light < -0.15 else 3 if light < 0.22 else 4 if light < 0.55 else 5
            c.paint(x, y, MELON_RIND[idx])
    # dewy white-cyan highlight & stem curl
    c.paint(mx - rx * 0.38, my - ry * 0.38, hexc("ebffff"))
    c.paint(mx - rx * 0.18, my - ry * 0.48, MELON_RIND[5])
    c.paint(mx, my - ry - 0.5, VINE_LEAF[3])


def oasis_melon(stage, rng):
    """Quellmelone: broad trailing desert-vine leaves bearing plump turquoise-and-teal striped oasis melons with dewy highlight."""
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 9 + stage)
    if stage == 0:
        c.ellipse(cx - 2.2, gy - 3.2, 2.2, 1.5, "vine")
        c.ellipse(cx + 2.2, gy - 3.2, 2.2, 1.5, "vine")
        c.line([(cx, gy - 1), (cx, gy - 3)], "vine")
    elif stage == 1:
        c.line([(cx - 5, gy - 2), (cx, gy - 4), (cx + 5, gy - 2)], "vine")
        for lx, ly, rx, ry in ((cx - 4.5, gy - 3.2, 3.0, 2.0), (cx + 4.5, gy - 3.0, 3.0, 2.0), (cx - 1.2, gy - 5.5, 3.2, 2.2), (cx + 2.0, gy - 4.8, 2.6, 1.8)):
            c.ellipse(lx, ly, rx, ry, "vine")
    elif stage == 2:
        c.line([(cx - 7, gy - 2), (cx - 2, gy - 5), (cx + 3, gy - 5), (cx + 7, gy - 2)], "vine")
        for lx, ly, rx, ry in (
            (cx - 6.2, gy - 2.8, 3.4, 2.2), (cx + 6.2, gy - 2.8, 3.4, 2.2),
            (cx - 3.0, gy - 6.5, 3.6, 2.5), (cx + 3.2, gy - 6.2, 3.6, 2.5),
            (cx, gy - 8.5, 3.2, 2.2),
        ):
            c.ellipse(lx, ly, rx, ry, "vine")
        # golden vine blossoms & young green-teal fruit swelling in the center
        c.ellipse(cx - 4.5, gy - 5.5, 1.6, 1.4, "blossom")
        c.paint(cx - 5, gy - 6, MELON_BLOSSOM[4])
        c.ellipse(cx + 4.8, gy - 4.8, 1.5, 1.3, "blossom")
        c.ellipse(cx + 0.5, gy - 3.5, 2.6, 2.2, "melon")
    else:
        for lx, ly, rx, ry in (
            (cx - 6.5, gy - 3.2, 3.5, 2.3), (cx + 6.5, gy - 3.0, 3.3, 2.2),
            (cx - 3.8, gy - 8.2, 3.8, 2.6), (cx + 3.6, gy - 8.0, 3.8, 2.5),
            (cx + 0.2, gy - 10.2, 3.4, 2.2),
        ):
            c.ellipse(lx, ly, rx, ry, "vine")
        # curly vine tendril at top
        c.line([(cx - 1, gy - 11), (cx + 1, gy - 13), (cx + 3, gy - 12)], "vine")
        # companion melon tucked right + hero plump striped oasis melon in front
        _paint_melon(c, cx + 4.2, gy - 3.4, 3.2, 2.8, stripes=2)
        _paint_melon(c, cx - 1.5, gy - 4.6, 4.9, 4.3, stripes=3)
        # extra morning dewdrop on the left vine leaf
        c.paint(cx - 6, gy - 4, hexc("ebffff"))
    return c


def _quad_pts(p0, p1, p2, n=12):
    return [
        (
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1],
        )
        for t in (i / n for i in range(n + 1))
    ]


def _paint_grain_ear(c, p0, p1, p2):
    """Curved braided honey-amber grain ear along quadratic curve p0->p1->p2, staying cleanly inside frame."""
    pts = _quad_pts(p0, p1, p2, n=10)
    c.line(pts, "grain_ear", width=3)
    for k in range(1, len(pts) - 1):
        x, y = pts[k]
        dx = pts[k + 1][0] - pts[k - 1][0]
        dy = pts[k + 1][1] - pts[k - 1][1]
        ln = max(math.hypot(dx, dy), 0.1)
        nx, ny = -dy / ln, dx / ln
        # upper-facing kernel row (bright honey-gold) and lower-facing kernel row (warm amber)
        if ny > 0:
            nx, ny = -nx, -ny
        c.paint(x + nx * 0.85, y + ny * 0.85, GRAIN_EAR[5 if k in (2, 4, 6) else 4])
        c.paint(x, y, GRAIN_EAR[4 if k % 2 == 0 else 3])
        c.paint(x - nx * 0.75, y - ny * 0.75, GRAIN_EAR[2 if k % 2 == 0 else 1])
    # crisp golden awn tip
    tx, ty = pts[-1]
    dx, dy = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
    ln = max(math.hypot(dx, dy), 0.1)
    c.paint(min(21, max(2, round(tx + dx / ln))), min(29, max(2, round(ty + dy / ln))), GRAIN_EAR[5])


def amber_grain(stage, rng):
    """Bernsteinkorn: sturdy golden-amber wheat/grain stalks bowing warmly under heavy honey-amber ears at Stage 3."""
    c = Canvas()
    cx, gy = FEET
    mound(c, cx, 8 + stage)
    if stage == 0:
        for ang, ln, cv in ((-1.95, 6.0, -0.25), (-1.57, 7.0, 0.05), (-1.2, 5.8, 0.25)):
            c.leaf(cx, gy - 2, ang, ln, 2.0, "grain_shoot", curve=cv)
    elif stage == 1:
        for i, (ang, ln, cv) in enumerate(((-2.25, 8.5, -0.45), (-1.85, 11.0, -0.2), (-1.55, 12.0, 0.08), (-1.25, 10.8, 0.25), (-0.9, 8.5, 0.45))):
            c.leaf(cx + (i - 2) * 0.6, gy - 2, ang, ln, 2.3, "grain_shoot" if i % 2 == 0 else "leaf", curve=cv)
    elif stage == 2:
        # bundled golden-green sheaf rising into upright young amber ears
        c.poly([(cx - 2, gy - 1), (cx + 2, gy - 1), (cx + 2, gy - 10), (cx - 2, gy - 10)], "grain_stalk")
        c.leaf(cx - 1.5, gy - 5, -2.4, 7.2, 2.3, "grain_shoot", curve=-0.5)
        c.leaf(cx + 1.5, gy - 5, -0.75, 7.2, 2.3, "grain_shoot", curve=0.5)
        for ox, tx, ty in ((-1.5, -3.5, gy - 17), (0.0, 0.0, gy - 20), (1.5, 3.5, gy - 16)):
            c.line([(cx + ox, gy - 9), (cx + tx, ty + 4)], "grain_shoot", width=2)
            c.poly([(cx + tx - 1.3, ty + 4), (cx + tx + 1.3, ty + 4), (cx + tx, ty - 1)], "grain_ear")
    else:
        # sturdy bundled golden-amber culms at base + warm arching flag leaves
        c.poly([(cx - 2.2, gy - 1), (cx + 2.2, gy - 1), (cx + 1.8, gy - 10), (cx - 1.8, gy - 10)], "grain_stalk")
        for yy in range(gy - 9, gy - 1):
            c.paint(cx - 2, yy, GRAIN_STALK[4])
            c.paint(cx, yy, GRAIN_STALK[3 if yy % 2 else 4])
            c.paint(cx + 1, yy, GRAIN_STALK[2])
        c.leaf(cx - 1.5, gy - 4, -2.42, 7.5, 2.4, "grain_stalk", curve=-0.55)
        c.leaf(cx + 1.5, gy - 4, -0.72, 7.5, 2.4, "grain_stalk", curve=0.55)
        # three curving golden stalks bowing under heavy honey-amber ears (all inside x=3..20)
        arcs = [
            # left-bowing ear
            ((cx - 1.5, gy - 8), (cx - 2.5, gy - 15), (cx - 3.5, gy - 16), (cx - 6.0, gy - 17), (cx - 8.0, gy - 13)),
            # tall central ear bowing right
            ((cx, gy - 9), (cx - 1.0, gy - 17), (cx - 0.5, gy - 21), (cx + 3.0, gy - 22), (cx + 6.0, gy - 18)),
            # lower right ear bowing warmly outward
            ((cx + 1.5, gy - 8), (cx + 2.5, gy - 13), (cx + 3.5, gy - 15), (cx + 6.5, gy - 15), (cx + 8.0, gy - 11)),
        ]
        for s0, s1, e0, e1, e2 in arcs:
            c.line(_quad_pts(s0, s1, e0, n=8), "grain_stalk", width=2)
            _paint_grain_ear(c, e0, e1, e2)
    return c


CROPS = {
    "tuber": tuber,
    "ember_carrot": ember_carrot,
    "night_beet": night_beet,
    "wound_leaf": wound_leaf,
    "moon_leek": moon_leek,
    "oasis_melon": oasis_melon,
    "amber_grain": amber_grain,
}


def crop_sheet(fn, seed):
    rng = random.Random(seed)
    lit = np.zeros((FH, FW * STAGES, 4), np.uint8)
    glow = np.zeros((FH, FW * STAGES, 4), np.uint8)
    for stage in range(STAGES):
        a, g = fn(stage, rng).render()
        lit[:, stage * FW:(stage + 1) * FW] = a
        glow[:, stage * FW:(stage + 1) * FW] = g
    return lit, glow


# ------------------------------------------------------------------ seed packets & harvested item icons (16x16, outline 1b1a2e)
SEEDS = {
    "tuber_seed": {"band": TUB, "seed": hexc("d8c0d0"), "dark": hexc("6a4a80")},
    "ember_carrot_seed": {"band": CARR, "seed": hexc("ffa83a"), "dark": hexc("9a2e18")},
    "night_beet_seed": {"band": BEETL, "seed": hexc("a070c0"), "dark": hexc("3a1450")},
    "wound_leaf_seed": {"band": LEAFW, "seed": hexc("6cc47a"), "dark": hexc("1c4a46")},
    "moon_leek_seed": {"band": LEEK_UMBEL, "seed": hexc("ecfffa"), "dark": hexc("368894"), "ink": ICON_INK},
    "oasis_melon_seed": {"band": MELON_RIND, "seed": hexc("5ed8d4"), "dark": hexc("164e5c"), "ink": ICON_INK},
    "amber_grain_seed": {"band": GRAIN_EAR, "seed": hexc("ffd25a"), "dark": hexc("8c3e18"), "ink": ICON_INK},
}


def _outline_icon(body, ink=ICON_INK):
    """Checks 1px margin & single connected component on `body` (16x16 RGBA), then wraps with 1px `ink` outline."""
    pts = {(x, y) for y in range(16) for x in range(16) if body[y, x, 3] > 0}
    xs, ys = [x for x, _ in pts], [y for _, y in pts]
    assert min(xs) >= 1 and max(xs) <= 14 and min(ys) >= 1 and max(ys) <= 14, (
        f"icon body leaves 1px margin: x {min(xs)}..{max(xs)} y {min(ys)}..{max(ys)}"
    )
    seen, stack = set(), [next(iter(pts))]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) in pts:
                    stack.append((x + dx, y + dy))
    assert len(seen) == len(pts), f"icon has {len(pts) - len(seen)} disconnected pixels"
    out = body.copy()
    for y in range(16):
        for x in range(16):
            if body[y, x, 3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < 16 and 0 <= yy < 16 and body[yy, xx, 3]:
                    out[y, x] = ink
                    break
    return out


def seed_icon(spec):
    ink = spec.get("ink", INK)
    c = Canvas(16, 16)
    c.poly([(4, 5), (11, 5), (12, 14), (3, 14)], "paper")  # the packet
    c.poly([(4, 5), (11, 5), (10, 3), (5, 3)], "paper")  # the folded top
    c.line([(4, 8), (11, 8)], "twine")
    out, _ = c.render(ink_col=ink)
    # the band colour on the packet's belly and the seeds spilling out at the top, painted after shading so the colours stay clean
    for y in (10, 11, 12):
        for x in range(4, 12):
            if out[y, x][3] and tuple(out[y, x][:3]) != tuple(ink[:3]):
                out[y, x] = spec["band"][3 if (x + y) % 3 else 2]
    for x, y in ((6, 2), (8, 2), (7, 1), (9, 3)):
        out[y, x] = spec["seed"]
    for x, y in ((6, 3), (8, 3)):
        out[y, x] = spec["dark"]
    # ink around the new seed pixels
    src = out.copy()
    for y in range(16):
        for x in range(16):
            if src[y, x][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < 16 and 0 <= yy < 16 and src[yy, xx][3] and tuple(src[yy, xx][:3]) != tuple(ink[:3]):
                    out[y, x] = ink
                    break
    return out


def icon_moon_leek():
    """16x16 harvested Mondlauch: plump silvery-pearl leek bulb at bottom-left, jade stalk & blades, glowing mint-teal moonflower umbel at top-right."""
    body = np.zeros((16, 16, 4), np.uint8)

    def put(x, y, col):
        body[y, x] = (*col[:3], 255)

    # plump silvery-white leek shank/bulb (bottom-left) + tiny rootlets
    bulb = [
        (2, 13, LEEK_BASE[2]), (3, 14, LEEK_BASE[1]),
        (3, 12, LEEK_BASE[4]), (4, 12, LEEK_BASE[3]), (4, 13, LEEK_BASE[2]), (5, 13, LEEK_BASE[1]),
        (4, 11, LEEK_BASE[4]), (5, 11, LEEK_BASE[3]), (5, 12, LEEK_BASE[2]), (6, 12, LEEK_BASE[1]),
        (5, 10, LEEK_BASE[3]), (6, 10, LEEK_BASE[2]), (6, 11, LEEK_BASE[1]),
    ]
    for x, y, col in bulb:
        put(x, y, col)
    # silvery-jade stalk & two flaring strap blades
    stalk = [
        (6, 9, LEEK_LEAF[4]), (7, 9, LEEK_LEAF[3]), (7, 10, LEEK_LEAF[2]),
        (7, 8, LEEK_LEAF[4]), (8, 8, LEEK_LEAF[3]), (8, 9, LEEK_LEAF[2]),
        (8, 7, LEEK_LEAF[4]), (9, 7, LEEK_LEAF[3]),
        # upper-left arching blade
        (6, 7, LEEK_LEAF[5]), (5, 6, LEEK_LEAF[4]), (4, 5, LEEK_LEAF[3]), (3, 5, LEEK_LEAF[4]),
        # lower-right arching blade
        (9, 9, LEEK_LEAF[3]), (10, 9, LEEK_LEAF[2]), (11, 10, LEEK_LEAF[3]), (12, 10, LEEK_LEAF[2]),
        # scape neck into umbel
        (9, 6, LEEK_LEAF[4]), (10, 6, LEEK_LEAF[3]),
    ]
    for x, y, col in stalk:
        put(x, y, col)
    # luminous pale mint-teal moonflower umbel crown (top-right, x=9..14, y=2..6)
    umbel = [
        (10, 2, MOON_HOT), (11, 2, LEEK_UMBEL[3]), (12, 2, MOON_HOT),
        (9, 3, MOON_HOT), (10, 3, LEEK_UMBEL[3]), (11, 3, MOON_HOT), (12, 3, LEEK_UMBEL[3]), (13, 3, LEEK_UMBEL[2]),
        (9, 4, LEEK_UMBEL[3]), (10, 4, MOON_HOT), (11, 4, LEEK_UMBEL[2]), (12, 4, MOON_HOT), (13, 4, LEEK_UMBEL[2]), (14, 4, LEEK_UMBEL[1]),
        (10, 5, LEEK_UMBEL[2]), (11, 5, LEEK_UMBEL[3]), (12, 5, LEEK_UMBEL[1]), (13, 5, LEEK_UMBEL[2]),
    ]
    for x, y, col in umbel:
        put(x, y, col)
    return _outline_icon(body)


def icon_oasis_melon():
    """16x16 Quellmelone: plump round turquoise-and-teal striped oasis melon with curly vine stem, leaf, and dewy highlight."""
    body = np.zeros((16, 16, 4), np.uint8)
    mx, my, rx, ry = 8.0, 9.0, 5.2, 4.7
    for y in range(4, 15):
        for x in range(2, 15):
            dx = (x + 0.5 - mx) / rx
            dy = (y + 0.5 - my) / ry
            d2 = dx * dx + dy * dy
            if d2 > 1.0:
                continue
            light = -0.58 * dx - 0.65 * dy + 0.25 * math.sqrt(max(0.0, 1.0 - d2))
            lon = dx / math.sqrt(max(0.18, 1.0 - 0.72 * dy * dy))
            stripe = math.cos(lon * math.pi * 2.8) > 0.36
            if stripe:
                idx = 1 if light < 0.0 else 2 if light < 0.40 else 3
            else:
                idx = 2 if light < -0.18 else 3 if light < 0.18 else 4 if light < 0.52 else 5
            body[y, x] = (*MELON_RIND[idx][:3], 255)
    # crisp dewy specular glint & water bead on upper-left rind
    body[6, 5] = (*hexc("ebffff")[:3], 255)
    body[6, 6] = (*MELON_RIND[5][:3], 255)
    body[7, 5] = (*MELON_RIND[5][:3], 255)
    body[10, 11] = (*hexc("a8f8f0")[:3], 255)  # tiny cool dew bead on lower right
    # curly stem & small vine leaf at top (rows 2..4)
    for x, y, col in (
        (8, 4, VINE_LEAF[2]), (8, 3, VINE_LEAF[3]), (9, 2, VINE_LEAF[4]),
        (6, 3, VINE_LEAF[5]), (7, 3, VINE_LEAF[4]), (6, 4, VINE_LEAF[3]),
        (10, 3, VINE_LEAF[3]), (11, 3, VINE_LEAF[2]),
    ):
        body[y, x] = (*col[:3], 255)
    return _outline_icon(body)


def icon_amber_grain():
    """16x16 Bernsteinkorn: bundled golden-amber grain stalks bowing into heavy braided honey-amber wheat ears."""
    body = np.zeros((16, 16, 4), np.uint8)

    def put(x, y, col):
        body[y, x] = (*col[:3], 255)

    # lower-left bundled golden stalks + warm tie band
    stalk_px = [
        (2, 13, GRAIN_STALK[3]), (3, 13, GRAIN_STALK[3]), (3, 14, GRAIN_STALK[2]), (4, 14, GRAIN_STALK[1]),
        (3, 12, GRAIN_STALK[4]), (4, 12, GRAIN_STALK[3]), (4, 13, GRAIN_STALK[3]), (5, 13, GRAIN_STALK[2]),
        (4, 11, GRAIN_STALK[4]), (5, 12, GRAIN_STALK[3]), (6, 12, GRAIN_STALK[2]),
        # tie twine knot
        (5, 10, GRAIN_EAR[1]), (5, 11, GRAIN_EAR[2]), (6, 11, GRAIN_EAR[1]), (7, 11, GRAIN_EAR[0]),
        # small golden flag leaf curving left
        (3, 9, GRAIN_STALK[4]), (4, 9, GRAIN_STALK[3]), (4, 10, GRAIN_STALK[2]),
        # upper necks splitting into two rich ears
        (6, 9, GRAIN_STALK[4]), (6, 10, GRAIN_STALK[3]), (7, 9, GRAIN_STALK[3]), (7, 10, GRAIN_STALK[2]),
    ]
    for x, y, col in stalk_px:
        put(x, y, col)
    # Main upper braided honey-amber ear (diagonal up-right, x=6..13, y=2..8)
    ear_top = [
        (6, 7, GRAIN_EAR[4]), (6, 8, GRAIN_EAR[3]), (7, 8, GRAIN_EAR[2]),
        (7, 5, GRAIN_EAR[5]), (7, 6, GRAIN_EAR[4]), (7, 7, GRAIN_EAR[3]), (8, 7, GRAIN_EAR[2]),
        (8, 4, GRAIN_EAR[5]), (8, 5, GRAIN_EAR[3]), (8, 6, GRAIN_EAR[4]), (9, 6, GRAIN_EAR[2]),
        (9, 3, GRAIN_EAR[5]), (9, 4, GRAIN_EAR[4]), (9, 5, GRAIN_EAR[3]), (10, 5, GRAIN_EAR[2]),
        (10, 2, GRAIN_EAR[5]), (10, 3, GRAIN_EAR[3]), (10, 4, GRAIN_EAR[4]), (11, 4, GRAIN_EAR[2]),
        (11, 2, GRAIN_EAR[4]), (11, 3, GRAIN_EAR[3]), (12, 2, GRAIN_EAR[5]), (13, 2, GRAIN_STALK[5]),
    ]
    # Second bowing companion ear to the right (x=8..14, y=7..10)
    ear_side = [
        (8, 8, GRAIN_EAR[3]), (8, 9, GRAIN_EAR[2]), (9, 8, GRAIN_EAR[4]), (9, 9, GRAIN_EAR[2]),
        (10, 7, GRAIN_EAR[5]), (10, 8, GRAIN_EAR[3]), (10, 9, GRAIN_EAR[2]),
        (11, 7, GRAIN_EAR[4]), (11, 8, GRAIN_EAR[3]), (11, 9, GRAIN_EAR[1]),
        (12, 7, GRAIN_EAR[5]), (12, 8, GRAIN_EAR[3]), (12, 9, GRAIN_EAR[2]),
        (13, 8, GRAIN_EAR[4]), (13, 9, GRAIN_EAR[2]), (14, 9, GRAIN_STALK[5]),
    ]
    for x, y, col in ear_top + ear_side:
        put(x, y, col)
    return _outline_icon(body)


HARVEST_ICONS = {
    "moon_leek": icon_moon_leek,
    "oasis_melon": icon_oasis_melon,
    "amber_grain": icon_amber_grain,
}


def save(arr, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, "RGBA").save(path)


def main(preview=None):
    props = ROOT / "props" / "crops"
    items = ROOT / "items"
    tiles = []
    glows = []
    for i, (cid, fn) in enumerate(CROPS.items()):
        lit, glow = crop_sheet(fn, 100 + i * 13)
        save(lit, props / f"crop_{cid}.png")
        has_glow = bool(glow[..., 3].any())
        if has_glow:
            save(glow, props / f"crop_{cid}_glow.png")
        tiles.append(lit)
        glows.append(glow)
        print(cid, "glow" if has_glow else "")
    for sid, spec in SEEDS.items():
        save(seed_icon(spec), items / f"{sid}.png")
    for iid, fn in HARVEST_ICONS.items():
        save(fn(), items / f"{iid}.png")
    if preview:
        scale = 6
        w_px = max(FW * STAGES * 2 + 8, len(SEEDS) * 18 + 8)
        h_px = FH * len(tiles) + 42
        sheet = Image.new("RGBA", (w_px * scale, h_px * scale), (58, 88, 60, 255))
        # right column dark night backdrop so glow masks are clearly visible
        night_x = (FW * STAGES + 4) * scale
        night_bg = Image.new("RGBA", (FW * STAGES * scale, FH * len(tiles) * scale), (18, 22, 38, 255))
        sheet.alpha_composite(night_bg, (night_x, 0))
        for r, (lit, glow) in enumerate(zip(tiles, glows)):
            im = Image.fromarray(lit, "RGBA").resize((lit.shape[1] * scale, lit.shape[0] * scale), Image.NEAREST)
            sheet.alpha_composite(im, (0, r * FH * scale))
            # dimmed night version + unlit glow
            dark = (lit.astype(np.float32) * np.array([0.36, 0.38, 0.55, 1.0])).clip(0, 255).astype(np.uint8)
            im_n = Image.fromarray(dark, "RGBA").resize((lit.shape[1] * scale, lit.shape[0] * scale), Image.NEAREST)
            sheet.alpha_composite(im_n, (night_x, r * FH * scale))
            if glow[..., 3].any():
                im_g = Image.fromarray(glow, "RGBA").resize((glow.shape[1] * scale, glow.shape[0] * scale), Image.NEAREST)
                sheet.alpha_composite(im_g, (night_x, r * FH * scale))
        y_icons = (FH * len(tiles) + 4) * scale
        for k, sid in enumerate(SEEDS):
            im = Image.fromarray(seed_icon(SEEDS[sid]), "RGBA").resize((16 * scale, 16 * scale), Image.NEAREST)
            sheet.alpha_composite(im, ((4 + k * 18) * scale, y_icons))
        for k, (iid, fn) in enumerate(HARVEST_ICONS.items()):
            im = Image.fromarray(fn(), "RGBA").resize((16 * scale, 16 * scale), Image.NEAREST)
            sheet.alpha_composite(im, ((4 + k * 18) * scale, y_icons + 18 * scale))
        sheet.save(preview)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
