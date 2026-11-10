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

MATERIALS = {
    "leaf": LEAFW, "carg": CARG, "carr": CARR, "beetl": BEETL, "beetr": BEETR, "stem": BEET_ST, "tub": TUB, "soil": SOIL, "spike": SPIKE,
    "paper": PAPER, "twine": TWINE,
}
ORDER = list(MATERIALS)


class Canvas:
    """A material-index image plus an emissive layer; `render()` shades it."""

    def __init__(self, w=FW, h=FH):
        self.w, self.h = w, h
        self.img = Image.new("L", (w, h), 0)
        self.draw = ImageDraw.Draw(self.img)
        self.glow = {}  # (x, y) -> (colour, strength)

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

    def emit(self, x, y, colour, dim_name=None):
        self.glow[(int(x), int(y))] = colour
        if dim_name:
            self.dot(x, y, dim_name)

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

    def render(self, outline=True):
        """-> (RGBA numpy array (h, w, 4) lit and outlined, RGBA glow array)."""
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
        for (x, y), colour in self.glow.items():
            out[y, x] = (*colour[:3], 255) if (out[y, x][3] == 0 or True) else out[y, x]
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
                            out[y, x] = INK
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


CROPS = {"tuber": tuber, "ember_carrot": ember_carrot, "night_beet": night_beet, "wound_leaf": wound_leaf}


def crop_sheet(fn, seed):
    rng = random.Random(seed)
    lit = np.zeros((FH, FW * STAGES, 4), np.uint8)
    glow = np.zeros((FH, FW * STAGES, 4), np.uint8)
    for stage in range(STAGES):
        a, g = fn(stage, rng).render()
        lit[:, stage * FW:(stage + 1) * FW] = a
        glow[:, stage * FW:(stage + 1) * FW] = g
    return lit, glow


# ------------------------------------------------------------------ seed packets
SEEDS = {
    "tuber_seed": {"band": TUB, "seed": hexc("d8c0d0"), "dark": hexc("6a4a80")},
    "ember_carrot_seed": {"band": CARR, "seed": hexc("ffa83a"), "dark": hexc("9a2e18")},
    "night_beet_seed": {"band": BEETL, "seed": hexc("a070c0"), "dark": hexc("3a1450")},
    "wound_leaf_seed": {"band": LEAFW, "seed": hexc("6cc47a"), "dark": hexc("1c4a46")},
}


def seed_icon(spec):
    c = Canvas(16, 16)
    c.poly([(4, 5), (11, 5), (12, 14), (3, 14)], "paper")  # the packet
    c.poly([(4, 5), (11, 5), (10, 3), (5, 3)], "paper")  # the folded top
    c.line([(4, 8), (11, 8)], "twine")
    out, _ = c.render()
    # the band colour on the packet's belly and the seeds spilling out at the top, painted after shading so the colours stay clean
    for y in (10, 11, 12):
        for x in range(4, 12):
            if out[y, x][3] and tuple(out[y, x][:3]) != tuple(INK[:3]):
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
                if 0 <= xx < 16 and 0 <= yy < 16 and src[yy, xx][3] and tuple(src[yy, xx][:3]) != tuple(INK[:3]):
                    out[y, x] = INK
                    break
    return out


def save(arr, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, "RGBA").save(path)


def main(preview=None):
    props = ROOT / "props" / "crops"
    items = ROOT / "items"
    tiles = []
    for i, (cid, fn) in enumerate(CROPS.items()):
        lit, glow = crop_sheet(fn, 100 + i * 13)
        save(lit, props / f"crop_{cid}.png")
        has_glow = bool(glow[..., 3].any())
        if has_glow:
            save(glow, props / f"crop_{cid}_glow.png")
        tiles.append(lit)
        print(cid, "glow" if has_glow else "")
    for sid, spec in SEEDS.items():
        save(seed_icon(spec), items / f"{sid}.png")
    if preview:
        scale = 6
        sheet = Image.new("RGBA", (FW * STAGES * scale, (FH * len(tiles) + 20) * scale), (58, 88, 60, 255))
        for r, lit in enumerate(tiles):
            im = Image.fromarray(lit, "RGBA").resize((lit.shape[1] * scale, lit.shape[0] * scale), Image.NEAREST)
            sheet.alpha_composite(im, (0, r * FH * scale))
        for k, sid in enumerate(SEEDS):
            im = Image.fromarray(seed_icon(SEEDS[sid]), "RGBA").resize((16 * scale, 16 * scale), Image.NEAREST)
            sheet.alpha_composite(im, (k * 18 * scale, FH * len(tiles) * scale + 4 * scale))
        sheet.save(preview)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
