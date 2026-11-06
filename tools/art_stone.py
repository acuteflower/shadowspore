#!/usr/bin/env python3
"""Draws the tools (sickle, pickaxe), the stone item, the little stones and the big rocks (stdlib only):
  assets/items/sickle_basic.png, pickaxe_basic.png, stone.png       icons 16x16
  assets/items/sickle_basic_held.png (26x15), pickaxe_basic_held.png (30x9)   pivot at the grip (4, 4)
  assets/props/pebbles.png   5 little stones, 16x12 frames, feet at (8, 10)
  assets/props/stonebed.png  6 gravel patches (176x120) that lie under rock formations, ragged dithered edges
  assets/props/rock.png      8 rocks (boulders, a rune stele, a slab, spires, a mossy and a crystal rock) x 4 states
                             (whole, chipped, small, rubble), 64x56 frames, feet (32, 52)
  assets/props/rock_glow.png the same layout, only the emissive parts (crystals, glowing cracks, runes, shelf
                             fungi, lichen tips; the game draws it unshaded, bright at night)
Stone is deep blue-violet, lit from the top left with a cool rim light from the right, shade leans violet,
moss on top and glowing things growing from it: veins of crystal in the cracks, shelf fungi, luminous
lichen, runes (teal and violet, like the flora and the trees)."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, FH, FW, GROUND, MEADOW, TWIG, add_outline, bezier, blank, check_icon, clamp, put_shadow, render_body, stroke  # noqa: E402
import art_bush  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

STONE = [hexc(c) for c in ("1c1a34", "2e2a52", "47436f", "665f94", "8a83b8", "d0cbec")]  # shade .. glint
STEEL = [hexc(c) for c in ("4a5472", "77839f", "b8c1d6", "eef2fb")]
OUT = hexc("1b1a2e")
TEAL, TEAL_L = hexc("3cc0c6"), hexc("78f4e6")
VIO, VIO_L = hexc("8a4dff"), hexc("d9c8ff")
STONE5 = STONE[:5]
art_bush.LEAF_HI[id(STONE5)] = STONE[5]


# ------------------------------------------------------------------ tools
def wrap(px, pts):
    """Violet grip wrap: alternating light and dark pixels along the handle."""
    for i, (x, y) in enumerate(pts):
        px[int(y)][int(x)] = hexc("8a5cf0") if i % 2 == 0 else hexc("4a2aa0")


def icon_sickle():
    px = blank(16, 16)
    stroke(px, bezier((2.6, 13.2), (4.6, 11.2), (6.8, 9.0), n=20), 1.3, 1.2, TWIG)  # handle
    wrap(px, [(3 + i * 0.9, 12.6 - i * 0.9) for i in range(3)])
    stroke(px, bezier((6.6, 9.4), (7.4, 8.6), (8.0, 8.0), n=6), 1.7, 1.7, STEEL)  # ferrule
    stroke(px, bezier((7.6, 8.2), (6.4, 3.4), (11.6, 1.9), (13.6, 5.9), n=40), lambda t: 2.0 * (1 - t) + 0.5 * t, 0.5, STEEL)  # blade
    check_icon("sickle", px)
    return outline_pass(px, OUT)


def icon_pickaxe():
    px = blank(16, 16)
    stroke(px, bezier((2.6, 13.2), (6.4, 9.4), (10.2, 5.6), n=24), 1.25, 1.25, TWIG)  # handle
    wrap(px, [(3 + i * 0.9, 12.6 - i * 0.9) for i in range(3)])
    stroke(px, bezier((6.0, 2.4), (13.2, 2.4), (13.6, 10.0), n=40), lambda t: 0.6 + 1.5 * math.sin(math.pi * t), 0.5, STEEL)  # head
    stroke(px, bezier((9.4, 6.4), (10.0, 5.8), (10.6, 5.2), n=6), 1.6, 1.6, [STEEL[0], STEEL[0], STEEL[1]])  # collar
    check_icon("pickaxe", px)
    return outline_pass(px, OUT)


def held_sickle():
    px = blank(27, 15)
    stroke(px, bezier((2.8, 4.0), (9.0, 4.0), (15.0, 4.0), n=30), 1.3, 1.3, TWIG)  # handle
    wrap(px, [(3 + i, 4.0 + (-1 if i % 2 else 1)) for i in range(7)])
    stroke(px, bezier((14.2, 4.0), (15.2, 4.0), (16.8, 4.0), n=6), 1.8, 1.8, STEEL)  # ferrule
    stroke(px, bezier((16.8, 4.4), (24.5, 3.4), (26.2, 9.4), (20.6, 13.2), n=60), lambda t: 2.1 * (1 - t) + 0.5 * t, 0.5, STEEL)  # blade
    check_icon("held sickle", px)
    return outline_pass(px, OUT)


def held_pickaxe():
    """34x19, grip at (4, 9): a long wooden handle and a curved steel head that bulges forward, its two
    tips drawn back toward the hand (the pick), so it reads as a pickaxe and not as a hammer."""
    px = blank(34, 19)
    stroke(px, bezier((3.0, 9.0), (14.0, 9.0), (26.0, 9.0), n=50), 1.3, 1.3, TWIG)  # handle
    wrap(px, [(4 + i, 9.0 + (-1 if i % 2 else 1)) for i in range(7)])
    stroke(px, bezier((21.2, 1.7), (31.5, 9.0), (21.2, 16.3), n=60), lambda t: 0.6 + 1.9 * math.sin(math.pi * t) ** 0.8, 0.6, STEEL[1:])  # head
    stroke(px, bezier((24.0, 9.0), (25.0, 9.0), (26.4, 9.0), n=8), 2.1, 2.1, [STEEL[0], STEEL[0], STEEL[1]])  # collar
    check_icon("held pickaxe", px)
    return outline_pass(px, OUT)


# ------------------------------------------------------------------ stones
def art_bush_render(lobes, seed, w, h, ground, rock=False):
    old = (art_bush.FW, art_bush.FH, art_bush.GROUND)
    art_bush.FW, art_bush.FH, art_bush.GROUND = w, h, ground
    try:
        px, band = render_body(lobes, STONE5, seed, *((0.1, 0.35, False) if rock else (0.34, 0.85, True)))
    finally:
        art_bush.FW, art_bush.FH, art_bush.GROUND = old
    return px, band


def icon_stone():
    lobes = [(7.5, 8.5, 5.0, 4.0, 0), (4.5, 9.5, 3.0, 2.6, -1), (11.0, 9.5, 3.4, 2.8, -1)]
    px, band = art_bush_render(lobes, 5, 16, 16, 15)
    for y in range(16):  # hard facets: a light edge along the upper left, a dark crack
        for x in range(16):
            if px[y][x][3] and (y < 6 or x < 5) and band[y][x] >= 3 and noise(x, y, 8) > 150:
                px[y][x] = STONE[5]
    for x, y in [(8, 8), (9, 9), (9, 10), (10, 11)]:
        px[y][x] = STONE[0]
    check_icon("stone", px)
    return outline_pass(px, OUT)


def pebble_frame(kind, seed):
    w, h, ground = 16, 12, 10
    shapes = {
        0: [(8.0, 7.0, 3.6, 2.6, 0)],
        1: [(6.0, 7.0, 3.0, 2.3, 0), (11.0, 7.5, 2.4, 1.9, -1)],
        2: [(5.0, 7.5, 2.6, 2.0, 0), (9.5, 6.5, 3.0, 2.4, 0), (12.5, 8.0, 1.8, 1.5, -1)],
        3: [(8.0, 8.0, 5.6, 1.9, 0), (6.5, 6.6, 3.0, 1.6, 1)],  # a flat stone
        4: [(8.0, 7.0, 3.8, 2.7, 0), (5.0, 8.0, 2.0, 1.6, -1)],  # with moss
    }[kind]
    lobes = []
    for cx, cy, rx, ry, cz in shapes:
        lobes.append((cx, cy, rx, ry, cz))
    px, band = art_bush_render(lobes, seed, w, h, ground)
    if kind == 4:
        for y in range(4, 8):
            for x in range(4, 12):
                if px[y][x][3] and noise(x, y, 3) > 110:
                    px[y][x] = MEADOW[3] if noise(x, y, 4) > 120 else MEADOW[4]
    for y in range(h):
        for x in range(w):
            if px[y][x][3] and band[y][x] >= 4 and y < 8 and noise(x, y, 9) > 130:
                px[y][x] = STONE[5]
    out = blank(w, h)
    for y in range(h):  # soft ground shadow, then the stones, then the outline
        for x in range(w):
            d = ((x + 0.5 - 8.5) / 7.0) ** 2 + ((y + 0.5 - 9.6) / 1.7) ** 2
            if d < 1.0:
                out[y][x] = (10, 18, 30, 110 if d < 0.5 else 60)
    for y in range(h):
        for x in range(w):
            if px[y][x][3] == 255:
                out[y][x] = px[y][x]
    src = [row[:] for row in out]
    for y in range(h):
        for x in range(w):
            if src[y][x][3] == 255:
                continue
            near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            hit = [(a, b) for a, b in near if 0 <= a < w and 0 <= b < h and src[b][a][3] == 255]
            if hit:
                out[y][x] = hexc("1a1633") if any(b > y for a, b in hit) else hexc("12261f")
    return out


RW, RH, GR = 64, 56, 52  # rock frames: 64x56, feet at (32, 52)
LIGHT = (-0.5, -0.7, 0.5)
LN = math.sqrt(sum(c * c for c in LIGHT))
LIGHT = tuple(c / LN for c in LIGHT)
MOSS = [hexc(c) for c in ("2f624e", "3e7d56", "55985f", "7cb96d")]
LICHEN_ROCK = [hexc(c) for c in ("6a8a78", "9ab8a0")]
SHELF = [hexc(c) for c in ("1a4a52", "2f8a8c", "6ae0d2")]  # shelf fungus: underside, body, lit top
GLOWMOSS = [hexc(c) for c in ("2a7a78", "4cc0b4", "9af0dc")]  # luminous lichen: shade, body, tip
RIM_COOL = [hexc(c) for c in ("2a6a88", "58b8d0")]
VEIN = [hexc(c) for c in ("4a2c8a", "7048d0")]  # a glowing crack, dim
RUNE = hexc("b06bff")

# Every rock is built from the same faceted blocks (a lit cap, a mid left face, a dark right face, chipped
# corners), so they all belong together: ("block", cx, width at the foot, width at the top, height, lean, depth)
ROCKS = [
    {"prims": [("block", 32, 24, 18, 15, 1, 0)], "moss": 0.3, "shards": [(24, 40, 0.7)], "fungi": 0},
    {"prims": [("block", 28, 30, 22, 21, -1, 0), ("block", 44, 18, 13, 12, 1, -1)], "moss": 0.45, "crack": 3, "veins": 1, "fungi": 1},
    {"prims": [("block", 30, 42, 30, 31, 0, 0), ("block", 14, 16, 11, 16, -1, -1), ("block", 49, 18, 12, 18, 1, -1)], "moss": 0.55, "crack": 4, "lichen": True, "veins": 2, "fungi": 2, "glowmoss": 5, "shards": [(44, 33, 0.8)]},
    {"prims": [("block", 32, 22, 15, 47, 2, 0), ("block", 45, 11, 7, 18, -2, -1)], "moss": 0.12, "rune": True, "crack": 3, "veins": 1},
    {"prims": [("block", 32, 50, 44, 15, 1, 0), ("block", 28, 34, 26, 11, -1, 1)], "moss": 0.45, "strata": 5, "lichen": True, "fungi": 2, "glowmoss": 3, "veins": 1},
    {"prims": [("block", 26, 17, 9, 38, -2, 0), ("block", 40, 15, 8, 29, 2, 0), ("block", 16, 11, 6, 20, -2, -1), ("block", 50, 11, 6, 15, 2, -1)], "moss": 0.1, "crack": 2, "veins": 1, "shards": [(25, 14, 1.0), (41, 22, 0.8)]},
    {"prims": [("block", 30, 38, 28, 26, 0, 0), ("block", 14, 16, 11, 14, -1, -1), ("block", 48, 18, 12, 15, 1, -1)], "moss": 0.9, "crack": 2, "fungi": 3, "glowmoss": 6, "buds": 6},
    {"prims": [("block", 28, 30, 22, 22, -1, 0), ("block", 45, 16, 12, 11, 1, -1)], "moss": 0.25, "crystal": (36, 36), "crack": 2, "veins": 2, "shards": [(18, 30, 0.7), (50, 40, 0.8)]},
]


class Glow:
    """Emissive pixels: the dim colour goes into the lit art, the bright one into the glow layer (with a soft halo)."""

    def __init__(self):
        self.px = blank(RW, RH)
        self.items = []

    def emit(self, px, x, y, dim, bright, halo=1):
        if 0 <= x < RW and 0 <= y < RH:
            if dim is not None:
                px[y][x] = dim
            self.px[y][x] = bright
            self.items.append((x, y, bright, halo))

    def done(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    xx, yy = x + dx, y + dy
                    if 0 < d <= radius + 0.5 and 0 <= xx < RW and 0 <= yy < RH and self.px[yy][xx][3] == 0:
                        self.px[yy][xx] = (*color[:3], 110 if d < 1.6 else 52)
        return self.px


def rock_scene(spec, f):
    """normals of the rock's blocks, scaled by f around the foot (nearest block wins)."""
    depth = [[-1e9] * RW for _ in range(RH)]
    normal = [[None] * RW for _ in range(RH)]
    for _, cx, wb, wt, h, tilt, dz in spec["prims"]:
        cx, wb, wt, h, tilt = 32 + (cx - 32) * f, wb * f, wt * f, h * f, tilt * f
        cap = max(3.0, wb * 0.2)
        for y in range(max(0, int(GR - h) - 1), GR + 1):
            t = (GR - y) / max(h, 1.0)
            half = (wb * (1 - t) + wt * t) / 2.0
            half *= 1.0 - 0.28 * max(0.0, (0.14 - t) / 0.14)  # the foot's corners are chipped
            half *= 1.0 - 0.34 * max(0.0, (t - 0.82) / 0.18)  # and so are the top corners
            xc = cx + tilt * t
            for x in range(max(0, int(xc - half) - 2), min(RW, int(xc + half) + 3)):
                edge = (noise(x, y, 31) / 255.0 - 0.5) * 2.2
                if abs(x + 0.5 - xc) > half + edge or t > 1.0:
                    continue
                left = x + 0.5 < xc + half * 0.12
                if (GR - y) > h - cap:
                    n = (0.0, -0.88, 0.48)  # the lit cap
                else:
                    n = (-0.55, 0.15, 0.82) if left else (0.6, 0.05, 0.8)
                zw = dz * 3.0 + 6.0 - abs(x + 0.5 - xc) * 0.1
                if zw > depth[y][x]:
                    depth[y][x] = zw
                    normal[y][x] = n
    return normal


def crystal(px, glow, cx, cy, scale, seed, big=False):
    """A cluster of crystals growing out of the stone; lit, with the bright core in the glow layer."""
    for k, (dx, h) in enumerate([(-3, 9), (0, 13), (3, 8), (6, 5)] if big else [(-1, 6), (1, 8), (3, 4)]):
        for yy in range(int(h * scale)):
            w = 1 if yy > h * scale * 0.45 else 0
            for xx in range(-w, w + 1):
                x, y = int(cx + dx * scale + xx), int(cy - yy)
                if 0 <= x < RW and 0 <= y < RH:
                    dark, light = (TEAL, TEAL_L) if k % 2 == 0 else (VIO, VIO_L)
                    px[y][x] = light if xx < 0 or yy > h * scale * 0.8 else dark
                    if xx == 0 and 1 < yy < h * scale - 1:
                        glow.emit(px, x, y, None, (*light[:3], 255), 0)
        glow.emit(px, int(cx + dx * scale), int(cy - h * scale + 1), None, VIO_L if k % 2 else TEAL_L, 2)


def render_rock(index, state, seed):
    """(lit pixels, glow pixels) of rock `index` in `state` (0 whole .. 3 rubble)."""
    spec = ROCKS[index]
    rng = random.Random(seed)
    px = blank(RW, RH)
    glow = Glow()
    if state == 3:  # rubble: a low scatter of chips, a few crystal shards still glinting
        width = max(abs(p[1] - 32) + p[2] / 2 for p in spec["prims"])
        for _ in range(8 + int(width / 4)):
            cx, cy, r = 32 + rng.uniform(-width * 0.8, width * 0.8), GR - 1 - rng.uniform(0, 2.4), rng.uniform(1.3, 2.5)
            stroke(px, [(cx, cy)], r, r, STONE[1:5])
        for x in range(int(32 - width), int(32 + width)):
            if rng.random() < 0.3:
                px[GR][x] = STONE[rng.choice((1, 2))]
        if spec.get("veins") or spec.get("shards") or spec.get("crystal"):
            for k in range(2):
                x = int(32 + rng.uniform(-width * 0.6, width * 0.6))
                glow.emit(px, x, GR - 2 - k, TEAL if k else VIO, TEAL_L if k else VIO_L, 2)
        return finish_rock(px), glow.done()
    f = (1.0, 0.8, 0.58)[state]
    normal = rock_scene(spec, f)
    for y in range(RH):
        for x in range(RW):
            n = normal[y][x]
            if n is None:
                continue
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
            lit = (n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]) / ln
            lit += (noise(x // 2, y // 2, seed) / 255.0 - 0.5) * 0.2 + (noise(x, y, seed + 1) / 255.0 - 0.5) * 0.1
            lit -= 0.22 * max(0.0, (y - (GR - 9)) / 9.0)  # a little darker toward the ground
            if "strata" in spec:  # layered rock: alternating pale and dark bands that wave a little
                band = int((y + 3 * math.sin(x * 0.22 + seed)) // spec["strata"])
                lit += 0.14 if band % 2 else -0.1
            v = (lit + 0.5) / 1.5 * 5.99
            px[y][x] = STONE[int(max(0, min(5, v + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5)))]
    body = [row[:] for row in px]
    for y in range(RH):  # a crisp rim light on the upper left, cool light on the right, deep chips low on the right
        for x in range(RW):
            if not body[y][x][3]:
                continue
            if (y == 0 or not body[y - 1][x][3]) or (x == 0 or not body[y][x - 1][3]):
                px[y][x] = STONE[5] if (x + y) % 3 else STONE[4]
            elif x + 1 < RW and not body[y][x + 1][3] and noise(x, y, seed + 12) > 90:
                px[y][x] = RIM_COOL[int(noise(x, y, seed + 13) > 150)]
    paths = []  # the cracks (also where the glowing veins run)
    for _ in range(spec.get("crack", 0) + spec.get("veins", 0)):
        x, y = rng.randrange(20, 44), rng.randrange(GR - 36, GR - 10)
        path = []
        for k in range(rng.randrange(5, 11)):
            xx, yy = x + int(math.sin(k * 0.9 + seed + len(paths)) * 1.5), y + k
            if 0 <= xx < RW and 0 <= yy < RH and px[yy][xx][3]:
                path.append((xx, yy))
        paths.append(path)
    for i, path in enumerate(paths):
        glowing = i >= spec.get("crack", 0) and state < 3
        for k, (xx, yy) in enumerate(path):
            if glowing:
                glow.emit(px, xx, yy, VEIN[k % 2], VIO if k % 3 else VIO_L, 1)
            else:
                px[yy][xx] = STONE[0]
    if spec.get("lichen") and state < 3:  # pale lichen spots on the sides
        for _ in range(22):
            x, y = rng.randrange(14, 50), rng.randrange(GR - 34, GR - 6)
            if px[y][x][3] and noise(x, y, seed + 7) > 120:
                px[y][x] = LICHEN_ROCK[rng.randrange(2)]
                if px[y][x + 1][3]:
                    px[y][x + 1] = LICHEN_ROCK[0]
    top = min([y for y in range(RH) for x in range(RW) if px[y][x][3]] or [GR])
    if spec["moss"] > 0 and state < 3:  # moss in clumps on top and draped over the shoulders
        reach = int((GR - top) * (0.22 + 0.4 * spec["moss"]) * (1.0 if state < 2 else 0.6))
        for y in range(top, top + reach):
            for x in range(RW):
                n = normal[y][x]
                if px[y][x][3] and n is not None and n[1] < 0.05 and noise(x // 2, y // 2, seed + 9) > 255 - 190 * spec["moss"]:
                    px[y][x] = MOSS[3 if noise(x, y, seed + 2) > 200 else (2 if noise(x, y, seed + 3) > 110 else 1)]
                    if y + 1 < RH and not px[y + 1][x][3] and noise(x, y, seed + 5) > 170:
                        px[y + 1][x] = MOSS[0]  # a drip of moss
    edge_of = lambda y, side: next((x for x in (range(RW) if side < 0 else range(RW - 1, -1, -1)) if px[y][x][3]), None)  # noqa: E731
    if state < 3:
        for k in range(spec.get("glowmoss", 0)):  # luminous lichen hangs from the shoulders
            y = top + rng.randrange(3, max(4, int((GR - top) * 0.5)))
            x = edge_of(y, -1 if k % 2 else 1)
            if x is None:
                continue
            for j in range(rng.randrange(3, 7)):
                put = (x + (1 if k % 2 else -1) * (0 if j < 2 else 1), y + j)
                if 0 <= put[0] < RW and not px[put[1]][put[0]][3]:
                    px[put[1]][put[0]] = GLOWMOSS[0]
            glow.emit(px, put[0], put[1], GLOWMOSS[1], GLOWMOSS[2], 1)
        for k in range(spec.get("buds", 0)):  # tiny glowing buds in the moss
            for _ in range(20):
                x, y = rng.randrange(14, 50), rng.randrange(top, top + 14)
                if px[y][x][3] and px[y][x] in MOSS:
                    glow.emit(px, x, y - 1, TEAL if k % 2 else VIO, TEAL_L if k % 2 else VIO_L, 1)
                    break
        for k in range(spec.get("fungi", 0)):  # shelf fungi growing from the foot on the shaded side
            y = GR - 4 - 6 * (k // 2) - rng.randrange(0, 3)
            x = edge_of(y, 1 if k % 2 == 0 else -1)
            if x is None:
                continue
            side = 1 if k % 2 == 0 else -1
            for i in range(5):
                xx, yy = x + side * (i + 1), y + (1 if i > 2 else 0)
                px[yy][xx] = SHELF[1]
                px[yy + 1][xx] = SHELF[0]
                glow.emit(px, xx, yy - (1 if 0 < i < 4 else 0), SHELF[2], TEAL_L, 1)
    if spec.get("rune") and state < 2:  # runes carved into the stone, glowing
        for rx0, ry0 in ((31, GR - 38), (31, GR - 27), (31, GR - 16)):
            for dx, dy in [(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 0), (-1, 2), (2, 3), (-1, 0)]:
                if 0 <= ry0 + dy < RH and px[ry0 + dy][rx0 + dx][3]:
                    glow.emit(px, rx0 + dx, ry0 + dy, VIO if (dx + dy) % 2 else RUNE, VIO_L if (dx + dy) % 2 == 0 else VIO, 1)
            glow.emit(px, rx0, ry0 + 1, VIO_L, VIO_L, 2)
    if spec.get("crystal") and state < 2:  # a cluster of glowing crystals growing out of the rock
        cx, cy = spec["crystal"]
        crystal(px, glow, cx, cy, f, seed, big=True)
    if state < 2:
        for cx, cy, sc in spec.get("shards", []):  # small crystal sprigs
            crystal(px, glow, int(32 + (cx - 32) * f), int(GR - (GR - cy) * f), sc * f, seed + cx)
    return finish_rock(px), glow.done()


def finish_rock(px):
    out = blank(RW, RH)
    shape = [[px[y][x][3] == 255 for x in range(RW)] for y in range(RH)]
    xs = [x for y in range(RH) for x in range(RW) if shape[y][x]]
    if xs:  # soft ground shadow
        mid, half = (min(xs) + max(xs)) / 2.0, (max(xs) - min(xs)) / 2.0 + 3
        for y in range(RH):
            for x in range(RW):
                d = ((x + 0.5 - mid) / half) ** 2 + ((y + 0.5 - (GR + 1.5)) / 3.0) ** 2
                if d < 1.0:
                    out[y][x] = (10, 18, 30, 120 if d < 0.5 else 70)
    for y in range(RH):
        for x in range(RW):
            if shape[y][x]:
                out[y][x] = px[y][x]
    src = [row[:] for row in out]
    for y in range(RH):
        for x in range(RW):
            if src[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < RW and 0 <= b < RH and src[b][a][3] == 255]
            if hit:
                out[y][x] = hexc("1a1633") if any(b > y for a, b in hit) else hexc("12261f")
    return out


# ------------------------------------------------------------------ stone beds
BW, BH = 176, 120
BED_RX = [40, 48, 56, 64, 72, 80]
GRAVEL = [hexc(c) for c in ("3a3952", "4a4966", "5c5b7a", "706f94")]


def stone_bed(index, seed):
    """The gravelly ground under a rock formation: an irregular patch (a warped ellipse) whose rim dissolves
    into the meadow in dither, with flecks, small stones, cracks, moss at the edge and a few teal glints."""
    rng = random.Random(seed)
    rx = BED_RX[index]
    ry = rx * 0.64
    cx, cy = BW / 2.0, BH / 2.0
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    px = blank(BW, BH)
    stones = []
    for _ in range(int(rx * 0.55)):  # small stones lying on the bed
        a, r = rng.uniform(0, 6.28), math.sqrt(rng.random()) * 0.8
        stones.append((cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r, rng.randrange(2, 5)))
    for y in range(BH):
        for x in range(BW):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            ang = math.atan2(dy, dx)
            warp = 1.0 + 0.16 * math.sin(3 * ang + ph[0]) + 0.1 * math.sin(5 * ang + ph[1]) + 0.06 * math.sin(9 * ang + ph[2])
            d = math.hypot(dx, dy) / warp
            if d > 1.04:
                continue
            edge = (d - 0.7) / 0.3  # 0 inside .. 1 at the rim
            if edge > 0.0:
                keep = BAYER[y % 4][x % 4] / 16.0 * 0.7 + (noise(x, y, seed) / 255.0) * 0.3
                if keep < edge * 1.05:
                    continue
            tone = noise(x // 2, y // 2, seed + 1) / 255.0 + (noise(x, y, seed + 2) / 255.0 - 0.5) * 0.35 - 0.25 * edge
            col = GRAVEL[0] if tone < 0.22 else (GRAVEL[1] if tone < 0.5 else (GRAVEL[2] if tone < 0.84 else GRAVEL[3]))
            n = noise(x, y, seed + 3)
            if n > 247:
                col = STONE[3]
            elif n > 236:
                col = STONE[2]
            if edge > 0.35 and noise(x // 3, y // 3, seed + 4) > 150 and noise(x, y, seed + 5) > 90:
                col = MEADOW[1] if noise(x, y, seed + 6) > 120 else MEADOW[2]  # the meadow creeps in
            px[y][x] = col
    for x0, y0, size in stones:  # stones with a lit top and a dark foot
        for dy in range(size - 1):
            for dx in range(size):
                x, y = int(x0) + dx, int(y0) + dy
                if 0 <= x < BW and 0 <= y < BH and px[y][x][3]:
                    px[y][x] = STONE[3] if dy == 0 else (STONE[2] if dx < size - 1 else STONE[1])
        x, y = int(x0) + 1, int(y0) + size - 1
        if 0 <= x < BW - size and 0 <= y < BH and px[y][x][3]:
            for dx in range(size):
                px[y][int(x0) + dx] = GRAVEL[0]
    for _ in range(int(rx / 12)):  # cracks
        x, y = int(cx + rng.uniform(-rx * 0.5, rx * 0.5)), int(cy + rng.uniform(-ry * 0.4, ry * 0.4))
        for k in range(rng.randrange(5, 12)):
            xx, yy = x + k, y + int(math.sin(k * 0.8 + seed) * 1.5)
            if 0 <= xx < BW and 0 <= yy < BH and px[yy][xx][3]:
                px[yy][xx] = GRAVEL[0]
    for _ in range(3):  # a few teal glints like the flora
        x, y = int(cx + rng.uniform(-rx * 0.6, rx * 0.6)), int(cy + rng.uniform(-ry * 0.5, ry * 0.5))
        if px[y][x][3]:
            px[y][x] = TEAL_L if rng.random() < 0.6 else VIO_L
    return px


def add_outline_alpha(px):
    add_outline(px)
    return px


def sheet(frames, cols, rows, fw, fh):
    return [[frames[(y // fh) * cols + x // fw][y % fh][x % fw] if (y // fh) * cols + x // fw < len(frames) else CLEAR for x in range(fw * cols)] for y in range(fh * rows)]


def main():
    items, props = ROOT / "items", ROOT / "props"
    for name, px in (("stone", icon_stone()),):  # sickle and pickaxe: tools/art_weapons.py
        write_png(items / f"{name}.png", 16, 16, px)
    pebbles = [pebble_frame(k, 30 + k * 7) for k in range(5)]
    write_png(props / "pebbles.png", 16 * 5, 12, sheet(pebbles, 5, 1, 16, 12))
    rocks = [render_rock(i, st, 50 + i * 13 + st) for st in range(4) for i in range(len(ROCKS))]  # rows = states
    write_png(props / "rock.png", RW * len(ROCKS), RH * 4, sheet([r[0] for r in rocks], len(ROCKS), 4, RW, RH))
    write_png(props / "rock_glow.png", RW * len(ROCKS), RH * 4, sheet([r[1] for r in rocks], len(ROCKS), 4, RW, RH))
    beds = [stone_bed(i, 80 + i * 11) for i in range(len(BED_RX))]
    write_png(props / "stonebed.png", BW * len(BED_RX), BH, sheet(beds, len(BED_RX), 1, BW, BH))
    print("tools, stone item, pebbles, rocks and stone beds written")


if __name__ == "__main__":
    main()
