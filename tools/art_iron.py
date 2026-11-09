#!/usr/bin/env python3
"""Iron ore veins for the open world, and the three iron items (stdlib only, builds on tools/art_stone.py):
  assets/props/iron_rock.png       6 ore rocks x 4 states (whole, chipped, small, rubble), 64x56 frames, feet (32, 52): the same faceted
                                   blocks, light and shade as the world's rocks (they must belong together), but rust-orange ore nodules
                                   sit in the stone, some bulging out of it, seams of ore run through cracks, steel glints, rust runs
                                   down the face; chipping the rock takes the nodules away one by one
  assets/props/iron_rock_glow.png  the same layout, only the emissive parts (just the void-touched variant has a few violet veins and shards)
  assets/items/iron_ore.png, iron_ingot.png, iron_plate.png   icons 16x16

  python3 tools/art_iron.py            writes everything
  python3 tools/art_iron.py preview    also writes docs/img/iron_rocks.png (rocks next to the stone rocks, icons) for a look
Palette: the stone's blue-violet ramp (art_stone.STONE), the ore in a warm rust ramp whose shade leans violet (like the rest of the shade
in this world), steel in the cool ramp of the tools."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_stone as S  # noqa: E402
from art_bush import BAYER, MEADOW, ascii_art, blank, check_icon  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

STONE, RW, RH, GR, LIGHT = S.STONE, S.RW, S.RH, S.GR, S.LIGHT
ORE = [hexc(c) for c in ("100d18", "211c2e", "352f44", "4f4960", "746d88", "bdb8d0")]  # raw iron: dark gunmetal with a steel sheen (NOT orange: that reads as copper)
RUST = [hexc(c) for c in ("3a1a20", "5e2a28", "86402e", "a8573a")]  # dull oxide red-brown, only on the shaded faces, rims and stains
METAL = [hexc(c) for c in ("4a5472", "77839f", "b8c1d6", "eef2fb")]
IRON = [hexc(c) for c in ("1f2238", "343a58", "4f5878", "7683a2", "aab5cf", "e4ebf8")]  # worked iron: darker than the tools' steel
STAIN = [hexc(c) for c in ("3a2230", "5a3034", "7c4238")]  # rust running down the stone
RUST_AMOUNT = 1.0  # how much of the ore is oxidised (0 none .. 1 a lot)
PALETTES = {  # name: (ore ramp, rust ramp, stain ramp, amount)
    "alt": (("100d18", "211c2e", "352f44", "4f4960", "746d88", "bdb8d0"), ("3a1a20", "5e2a28", "86402e", "a8573a"), ("3a2230", "5a3034", "7c4238"), 1.0),
    "gunmetal": (("0e0c16", "1c1a2a", "2e3046", "4a5070", "7a88aa", "c4d0e8"), ("2c1a22", "46262a", "603432", "7a4438"), ("30222e", "46303a", "5c3c40"), 0.42),
    "altrost": (("100d18", "211c2e", "352f44", "4f4960", "746d88", "bdb8d0"), ("34242a", "54383a", "76504a", "98685a"), ("342830", "4c3a40", "644c4c"), 0.9),
    "leere": (("0b0911", "181322", "261d3a", "3a2e58", "5a4b86", "a79ad4"), ("2a1a2e", "40243a", "5a3042", "743c48"), ("2c2036", "40304a", "58405a"), 0.25),
}


def use(name):
    """Switch the ore palette (for comparing looks): the module-level ramps are what every drawing function reads."""
    global ORE, RUST, STAIN, RUST_AMOUNT
    ore, rust, stain_, amount = PALETTES[name]
    ORE, RUST, STAIN, RUST_AMOUNT = [hexc(c) for c in ore], [hexc(c) for c in rust], [hexc(c) for c in stain_], amount


use("gunmetal")  # the look of the game; "alt", "altrost" and "leere" are the other candidates (python3 tools/art_iron.py palettes)
OUT = hexc("1b1a2e")

# Same blocks as art_stone.ROCKS (so they stand next to the stone rocks without a break), plus the ore:
#   nodules (x, y, rx, ry) in whole-state frame pixels, bulging out when they sit on the silhouette; seams: polylines (x, y) with a width;
#   bands: y of a rust layer in layered rock. Everything scales with the rock when it is chipped.
IRON_ROCKS = [
    {"prims": [("block", 32, 24, 18, 15, 1, 0)], "moss": 0.18, "crack": 1, "auto": 4,
     "nodules": [(25, 43, 3.0, 2.5), (37, 39, 2.4, 2.0, 1)]},
    {"prims": [("block", 28, 30, 22, 21, -1, 0), ("block", 44, 18, 13, 12, 1, -1)], "moss": 0.3, "crack": 1, "lichen": True, "auto": 5,
     "nodules": [(19, 42, 3.2, 2.7), (42, 42, 2.6, 2.2), (30, 34, 2.2, 1.8)],
     "seams": [([(21, 36), (26, 38), (30, 43), (37, 45)], 2.2)]},
    {"prims": [("block", 30, 42, 30, 31, 0, 0), ("block", 14, 16, 11, 16, -1, -1), ("block", 49, 18, 12, 18, 1, -1)], "moss": 0.4, "crack": 2, "lichen": True, "fungi": 1, "auto": 8,
     "nodules": [(46, 25, 3.6, 3.0, 1), (14, 38, 3.0, 2.5), (24, 31, 2.6, 2.2), (34, 44, 2.8, 2.3), (45, 44, 2.2, 1.9)],
     "seams": [([(18, 30), (23, 34), (27, 41), (34, 44), (42, 42)], 2.6), ([(32, 22), (36, 27), (38, 33)], 1.8)]},
    {"prims": [("block", 32, 22, 15, 47, 2, 0), ("block", 45, 11, 7, 18, -2, -1)], "moss": 0.1, "crack": 1, "auto": 6,
     "nodules": [(28, 47, 2.8, 2.3), (26, 18, 2.2, 1.9), (46, 41, 2.2, 1.9)],
     "seams": [([(31, 11), (30, 18), (33, 25), (31, 32), (34, 39), (32, 45)], 2.4)]},
    {"prims": [("block", 32, 50, 44, 15, 1, 0), ("block", 28, 34, 26, 11, -1, 1)], "moss": 0.3, "strata": 5, "lichen": True, "fungi": 1, "auto": 6,
     "nodules": [(14, 47, 2.8, 2.3), (24, 36, 3.0, 2.5, 1), (52, 46, 2.2, 1.9)],
     "bands": [40, 45]},
    {"prims": [("block", 28, 30, 22, 22, -1, 0), ("block", 45, 16, 12, 11, 1, -1)], "moss": 0.15, "crack": 1, "veins": 2, "auto": 5,
     "nodules": [(20, 42, 3.2, 2.7), (36, 40, 2.6, 2.2), (45, 45, 2.4, 2.0)],
     "seams": [([(18, 34), (24, 37), (28, 43)], 2.0)],
     "shards": [(48, 38, 0.8), (14, 40, 0.7)]},
]


def auto_seams(spec, index):
    """Extra seams of ore wandering through the stone (drawn in whole-state coordinates, so a chipped rock keeps the same veins): a random
    walk across the body, here and there with a thinner branch."""
    rng = random.Random(7000 + index)
    x0 = min(p[1] - p[2] / 2.0 for p in spec["prims"])
    x1 = max(p[1] + p[2] / 2.0 for p in spec["prims"])
    top = GR - max(p[4] for p in spec["prims"])
    tall = (GR - top) > (x1 - x0) * 1.2
    out = []
    for _ in range(spec.get("auto", 0)):
        x, y = rng.uniform(x0 + 3, x1 - 3), rng.uniform(top + 4, GR - 5)
        ang = rng.uniform(1.1, 2.0) if tall else rng.uniform(-0.6, 0.9) + (math.pi if rng.random() < 0.5 else 0.0)
        pts = [(x, y)]
        for _k in range(rng.randrange(4, 8)):
            ang += rng.uniform(-0.8, 0.8)
            x += math.cos(ang) * rng.uniform(3.0, 5.0)
            y += math.sin(ang) * rng.uniform(2.5, 4.0)
            pts.append((x, y))
        out.append((pts, rng.uniform(1.8, 2.7)))
        if rng.random() < 0.55 and len(pts) > 3:  # a branch off the middle
            bx, by = pts[len(pts) // 2]
            bang = ang + rng.choice((-1.0, 1.0)) * rng.uniform(0.7, 1.3)
            branch = [(bx, by)]
            for _k in range(rng.randrange(2, 4)):
                bang += rng.uniform(-0.5, 0.5)
                bx += math.cos(bang) * rng.uniform(2.5, 4.0)
                by += math.sin(bang) * rng.uniform(2.0, 3.2)
                branch.append((bx, by))
            out.append((branch, rng.uniform(1.3, 1.9)))
    return out


def flecks(px, solid, seams, f, seed):
    """Small flush specks of ore sprinkled along the seams: the stone is shot through with it."""
    rng = random.Random(seed)
    for pts, _w in seams:
        for (x, y) in pts:
            for _ in range(2):
                fx, fy = 32 + (x - 32) * f + rng.uniform(-4, 4), GR - (GR - y) * f + rng.uniform(-3, 3)
                ix, iy = int(fx), int(fy)
                if 0 <= ix < RW - 1 and 0 <= iy < RH - 1 and px[iy][ix][3] and (ix, iy) not in solid:
                    r = rng.random()
                    px[iy][ix] = ORE[2] if r < 0.4 else (RUST[2] if r < 0.4 + 0.4 * RUST_AMOUNT else ORE[3])
                    solid.add((ix, iy))
                    if r < 0.35 and px[iy][ix + 1][3] and (ix + 1, iy) not in solid:
                        px[iy][ix + 1] = ORE[1]
                        solid.add((ix + 1, iy))


def nodule(px, solid, cx, cy, rx, ry, seed, w=RW, h=RH, flush=False):
    """A rounded lump of ore, lit from the upper left like the rocks: rust-orange with a gleam of raw metal; `solid` collects its pixels."""
    mine = set()
    for y in range(int(cy - ry - 2), int(cy + ry + 3)):
        for x in range(int(cx - rx - 2), int(cx + rx + 3)):
            if not (0 <= x < w and 0 <= y < h) or (flush and not px[y][x][3]):
                continue
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            d = 0.62 * math.hypot(dx, dy) + 0.38 * (abs(dx) + abs(dy)) / 1.25  # between an ellipse and a diamond: chunky, angular lumps
            if d > 1.0 + (noise(x, y, seed) / 255.0 - 0.5) * 0.45:
                continue
            if d < 0.3:  # a flat top facet in the middle, then the sides as flat facets (every 60 degrees), like broken ore
                n = (0.0, -0.25, 0.97)
            else:
                a = (math.floor((math.atan2(dy, dx) + math.pi + seed * 0.7) / (math.pi / 3.0)) + 0.5) * (math.pi / 3.0) - math.pi - seed * 0.7
                n = (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.72)
            ln = math.sqrt(sum(c * c for c in n))
            lit = sum(a_ * b_ for a_, b_ in zip(n, LIGHT)) / ln
            lit += (noise(x, y, seed + 3) / 255.0 - 0.5) * 0.18
            v = (lit + 0.55) / 1.5 * 5.99
            i = int(max(0, min(5, v + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.7)))
            if (lit < 0.5 and noise(x, y, seed + 6) < 255 * 0.8 * RUST_AMOUNT + 1) or noise(x, y, seed + 7) < 255 * 0.28 * RUST_AMOUNT:  # oxide on the shaded facets, a few spots elsewhere
                px[y][x] = RUST[int(max(0, min(3, (lit + 0.2) * 3.6)))]
            else:
                px[y][x] = ORE[5 if (i == 5 and noise(x, y, seed + 8) > 200) else min(i, 4)]
            mine.add((x, y))
    for x, y in mine:  # a dark rim on the lower right, so the lump stands out of the stone
        if (x + 1, y) not in mine or (x, y + 1) not in mine:
            px[y][x] = ORE[0] if (x + 1, y) not in mine and (x, y + 1) not in mine else ORE[1]
    gx, gy = int(cx - rx * 0.35), int(cy - ry * 0.4)  # steel glint on the lit shoulder
    for ox, oy, c in ((0, 0, 3), (1, 0, 2), (0, 1, 2)):
        if (gx + ox, gy + oy) in mine and noise(gx, gy, seed + 9) > 40:
            px[gy + oy][gx + ox] = METAL[c]
    solid |= mine
    return mine


def seam(px, solid, pts, width, seed):
    """A seam of ore in the stone: a ragged band along the polyline, lit along its upper edge, flecked with metal."""
    mine = set()
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])) or 1.0
    run = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        n = max(2, int(seg * 2))
        for i in range(n + 1):
            t = i / n
            cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            u = (run + seg * t) / total
            wd = width * 1.15 * (0.75 + 0.5 * noise(int(cx), int(cy), seed) / 255.0) * (0.5 + 0.5 * math.sin(math.pi * u))
            for oy in range(-int(wd) - 1, int(wd) + 2):
                for ox in range(-int(wd) - 1, int(wd) + 2):
                    x, y = int(cx) + ox, int(cy) + oy
                    if math.hypot(ox, oy) <= wd / 2.0 + 0.3 and 0 <= x < RW and 0 <= y < RH and px[y][x][3]:
                        mine.add((x, y))
        run += seg
    for x, y in mine:
        up = (x, y - 1) not in mine
        down = (x, y + 1) not in mine
        if noise(x, y, seed + 2) > 240:
            px[y][x] = METAL[2]
        elif up:
            px[y][x] = RUST[3] if noise(x, y, seed + 1) < 255 * 0.4 * RUST_AMOUNT else (ORE[5] if noise(x, y, seed + 3) > 200 else ORE[4])  # the lit edge of a seam gleams like steel
        elif down:
            px[y][x] = ORE[0]
        else:
            px[y][x] = RUST[1 + int(noise(x, y, seed + 1) > 150)] if noise(x, y, seed + 5) < 255 * 0.33 * RUST_AMOUNT else ORE[2 - int(noise(x, y, seed + 1) > 150)]
    solid |= mine
    return mine


def stain(px, solid, cx, cy, ry, seed, f):
    """Rust that ran down the stone under a lump."""
    for k in range(3):
        x = int(cx + (k - 1) * 2 + (noise(int(cx), k, seed) / 255.0 - 0.5) * 3)
        y0 = int(cy + ry * 0.6)
        for j in range(int((2 + noise(x, k, seed + 1) / 255.0 * 4) * f + 1)):
            y = y0 + j
            if 0 <= x < RW and 0 <= y < RH and px[y][x][3] and (x, y) not in solid and noise(x, y, seed + 4) > 70:
                px[y][x] = STAIN[min(2, j // 2 + (1 if k == 1 else 0))]


def render_iron(index, state, seed):
    """(lit pixels, glow pixels) of ore rock `index` in `state` (0 whole .. 3 rubble)."""
    spec = IRON_ROCKS[index]
    rng = random.Random(seed)
    px = blank(RW, RH)
    glow = S.Glow()
    if state == 3:  # rubble: chips of stone, a few bits of ore among them
        width = max(abs(p[1] - 32) + p[2] / 2 for p in spec["prims"])
        for _ in range(8 + int(width / 4)):
            cx, cy, r = 32 + rng.uniform(-width * 0.8, width * 0.8), GR - 1 - rng.uniform(0, 2.4), rng.uniform(1.3, 2.5)
            S.stroke(px, [(cx, cy)], r, r, STONE[1:5])
        for x in range(int(32 - width), int(32 + width)):
            if rng.random() < 0.3:
                px[GR][x] = STONE[rng.choice((1, 2))]
        for k in range(3):
            nodule(px, set(), 32 + rng.uniform(-width * 0.55, width * 0.55), GR - 2.0 - k * 0.4, rng.uniform(1.5, 2.2), rng.uniform(1.2, 1.7), seed + 40 + k)
        if spec.get("veins") or spec.get("shards"):
            glow.emit(px, int(32 + rng.uniform(-width * 0.5, width * 0.5)), GR - 2, S.VIO, S.VIO_L, 2)
        return S.finish_rock(px), glow.done()
    f = (1.0, 0.8, 0.58)[state]
    normal = S.rock_scene(spec, f)
    for y in range(RH):  # the stone: exactly the rocks' shading
        for x in range(RW):
            n = normal[y][x]
            if n is None:
                continue
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
            lit = (n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]) / ln
            lit += (noise(x // 2, y // 2, seed) / 255.0 - 0.5) * 0.2 + (noise(x, y, seed + 1) / 255.0 - 0.5) * 0.1
            lit -= 0.22 * max(0.0, (y - (GR - 9)) / 9.0)
            if "strata" in spec:
                band = int((y + 3 * math.sin(x * 0.22 + seed)) // spec["strata"])
                lit += 0.14 if band % 2 else -0.1
            v = (lit + 0.5) / 1.5 * 5.99
            px[y][x] = STONE[int(max(0, min(5, v + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5)))]
    body = [row[:] for row in px]
    for y in range(RH):
        for x in range(RW):
            if not body[y][x][3]:
                continue
            if (y == 0 or not body[y - 1][x][3]) or (x == 0 or not body[y][x - 1][3]):
                px[y][x] = STONE[5] if (x + y) % 3 else STONE[4]
            elif x + 1 < RW and not body[y][x + 1][3] and noise(x, y, seed + 12) > 90:
                px[y][x] = S.RIM_COOL[int(noise(x, y, seed + 13) > 150)]
    paths = []
    for _ in range(spec.get("crack", 0) + spec.get("veins", 0)):
        x, y = rng.randrange(20, 44), rng.randrange(GR - 36, GR - 10)
        path = []
        for k in range(rng.randrange(5, 11)):
            xx, yy = x + int(math.sin(k * 0.9 + seed + len(paths)) * 1.5), y + k
            if 0 <= xx < RW and 0 <= yy < RH and px[yy][xx][3]:
                path.append((xx, yy))
        paths.append(path)
    for i, path in enumerate(paths):
        glowing = i >= spec.get("crack", 0)
        for k, (xx, yy) in enumerate(path):
            if glowing:
                glow.emit(px, xx, yy, S.VEIN[k % 2], S.VIO if k % 3 else S.VIO_L, 1)
            else:
                px[yy][xx] = STONE[0]
    if spec.get("lichen"):
        for _ in range(16):
            x, y = rng.randrange(14, 50), rng.randrange(GR - 34, GR - 6)
            if px[y][x][3] and noise(x, y, seed + 7) > 120:
                px[y][x] = S.LICHEN_ROCK[rng.randrange(2)]
    top = min([y for y in range(RH) for x in range(RW) if px[y][x][3]] or [GR])
    if spec["moss"] > 0:  # a little moss on top: the ore is bare where it shows
        reach = int((GR - top) * (0.22 + 0.4 * spec["moss"]) * (1.0 if state < 2 else 0.6))
        for y in range(top, top + reach):
            for x in range(RW):
                n = normal[y][x]
                if px[y][x][3] and n is not None and n[1] < 0.05 and noise(x // 2, y // 2, seed + 9) > 255 - 190 * spec["moss"]:
                    px[y][x] = S.MOSS[3 if noise(x, y, seed + 2) > 200 else (2 if noise(x, y, seed + 3) > 110 else 1)]
                    if y + 1 < RH and not px[y + 1][x][3] and noise(x, y, seed + 5) > 170:
                        px[y + 1][x] = S.MOSS[0]
    edge_of = lambda y, side: next((x for x in (range(RW) if side < 0 else range(RW - 1, -1, -1)) if px[y][x][3]), None)  # noqa: E731
    for k in range(spec.get("fungi", 0) if state < 2 else 0):  # shelf fungi on the shaded foot
        y = GR - 4 - 6 * (k // 2) - rng.randrange(0, 3)
        x = edge_of(y, 1 if k % 2 == 0 else -1)
        if x is None:
            continue
        side = 1 if k % 2 == 0 else -1
        for i in range(4):
            xx, yy = x + side * (i + 1), y + (1 if i > 2 else 0)
            if 0 <= xx < RW:
                px[yy][xx] = S.SHELF[1]
                px[yy + 1][xx] = S.SHELF[0]
                glow.emit(px, xx, yy - (1 if 0 < i < 3 else 0), S.SHELF[2], S.TEAL_L, 1)
    # ---- the ore: layered rust, seams, then the lumps (they stand on top and may bulge past the silhouette)
    solid = set()
    for yb in spec.get("bands", []):
        yb = GR - (GR - yb) * f
        for x in range(RW):
            y = int(yb + 2.2 * math.sin(x * 0.2 + seed))
            for j in range(2):
                if 0 <= y + j < RH and px[y + j][x][3] and noise(x, y + j, seed + 21) > 70:
                    px[y + j][x] = (ORE[3] if j == 0 else ORE[1]) if noise(x, y, seed + 22) > 100 else RUST[2 if j == 0 else 1]
                    solid.add((x, y + j))
    place = lambda p: (32 + (p[0] - 32) * f, GR - (GR - p[1]) * f)  # noqa: E731
    all_seams = list(spec.get("seams", [])) + auto_seams(spec, index)
    for si, (pts, width) in enumerate(all_seams):
        keep = pts if state == 0 else pts[: max(2, int(len(pts) * (0.8 if state == 1 else 0.6)))]
        seam(px, solid, [place(p) for p in keep], width * (0.6 + 0.4 * f), 5000 + index * 10 + si)
    pocket = random.Random(9000 + index)  # ore pockets: flush lumps of ore on the seams (the same ones in every state)
    for pts, width in all_seams:
        for _ in range(1 if width > 2.0 else 0):
            qx, qy = pts[pocket.randrange(len(pts))]
            r = pocket.uniform(2.0, 2.8)
            if state < 3 and not (state == 2 and pocket.random() < 0.5):
                cx, cy = place((qx, qy))
                nodule(px, solid, cx, cy, max(1.6, r * (1.0 if f > 0.7 else f * 1.15)), max(1.4, r * 0.8 * (1.0 if f > 0.7 else f * 1.15)), 9500 + index + int(qx), flush=True)
    flecks(px, solid, all_seams, f, 8000 + index)
    lumps = []
    for k, node in enumerate(spec["nodules"]):
        x, y, rx, ry = node[:4]
        if (state == 1 and k % 4 == 3) or (state == 2 and k % 2 == 1):
            continue
        cx, cy = place((x, y))
        s = 1.0 if f > 0.7 else f * 1.15
        nodule(px, solid, cx, cy, max(1.8, rx * 1.1 * s), max(1.5, ry * 1.1 * s), seed + 50 + k, flush=len(node) < 5)  # a fifth value lets one lump bulge out of the stone
        lumps.append((cx, cy, ry * s))
    for cx, cy, ry in lumps:
        stain(px, solid, cx, cy, ry, seed + 60, f)
    if state < 2:
        for cx, cy, sc in spec.get("shards", []):  # small void crystal sprigs
            S.crystal(px, glow, int(32 + (cx - 32) * f), int(GR - (GR - cy) * f), sc * f, seed + cx)
    return S.finish_rock(px), glow.done()


# ------------------------------------------------------------------ items
def icon_ore():
    """Raw iron ore: a chip of the blue-violet stone with rust-orange ore pushing out of it, steel glints."""
    lobes = [(7.5, 9.0, 4.8, 3.8, 0), (4.8, 10.0, 2.8, 2.4, -1), (11.0, 10.0, 3.0, 2.6, -1)]
    px, band = S.art_bush_render(lobes, 11, 16, 16, 15)
    solid = set()
    for x, y, rx, ry, sd in ((5.6, 8.2, 2.8, 2.5, 3), (10.2, 6.4, 2.6, 2.3, 5), (9.2, 11.2, 2.4, 2.0, 8), (7.0, 5.0, 1.7, 1.5, 12)):
        nodule(px, solid, x, y, rx, ry, sd, 16, 16)
    check_icon("iron ore", px)
    return outline_pass(px, OUT)


def icon_ingot():
    """An iron bar (a trapezoid ingot, top face lit from the upper left), cool steel with a warm cast of forge scale at the ends."""
    palette = {".": CLEAR, "a": IRON[4], "b": IRON[3], "c": IRON[2], "d": IRON[1], "e": IRON[0], "w": RUST[3], "x": RUST[2]}
    rows = [
        "................",
        "................",
        "................",
        "....bbbbbbbbb...",
        "...baaaaaaabbc..",
        "..baabbbbbbbccd.",
        ".bbbbbbbbbbccdd.",
        ".bccccccccccddd.",
        ".bccccccccccdde.",
        ".wxcccccccccdde.",
        ".xxddddddddddee.",
        "..eeeeeeeeeeee..",
        "................",
        "................",
        "................",
        "................",
    ]
    px = ascii_art(rows, palette)
    check_icon("iron ingot", px)
    return outline_pass(px, OUT)


def icon_plate():
    """A hammered iron plate with four rivets: a flat slab seen from above and in front."""
    palette = {".": CLEAR, "a": IRON[4], "b": IRON[3], "c": IRON[2], "d": IRON[1], "e": IRON[0]}
    rows = [
        "................",
        "................",
        "................",
        "..bbbbbbbbbbbb..",
        ".baaaaaaaaaabbc.",
        ".bacbbbbbbbbacd.",
        ".bbbbbcbbbcbbcd.",
        ".bbbcbbbbbbbbcd.",
        ".bbbbbbbbcbbbcd.",
        ".bacbbbbbbbbacd.",
        ".bccccccccccccd.",
        ".cdddddddddddde.",
        "..eeeeeeeeeeee..",
        "................",
        "................",
        "................",
    ]
    px = ascii_art(rows, palette)
    for x, y in ((3, 5), (12, 5), (3, 9), (12, 9)):  # the rivets: a bright head with a dark foot
        px[y][x] = IRON[5]
        px[y + 1][x] = IRON[0]
    check_icon("iron plate", px)
    return outline_pass(px, OUT)


# ------------------------------------------------------------------ run
def main():
    props, items = ROOT / "props", ROOT / "items"
    n = len(IRON_ROCKS)
    frames = [render_iron(i, st, 200 + i * 17 + st) for st in range(4) for i in range(n)]
    write_png(props / "iron_rock.png", RW * n, RH * 4, S.sheet([f[0] for f in frames], n, 4, RW, RH))
    write_png(props / "iron_rock_glow.png", RW * n, RH * 4, S.sheet([f[1] for f in frames], n, 4, RW, RH))
    for name, px in (("iron_ore", icon_ore()), ("iron_ingot", icon_ingot()), ("iron_plate", icon_plate())):
        write_png(items / f"{name}.png", 16, 16, px)
    print("iron rocks (%d x 4), glow sheet and the iron icons written" % n)
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(frames)


def preview(frames):
    """Contact sheet: the stone rocks above, the ore rocks below (all four states), the icons at 8x."""
    n, k = len(IRON_ROCKS), 3
    stone = [S.render_rock(i, st, 50 + i * 13 + st) for st in range(4) for i in range(len(S.ROCKS))]
    w = RW * max(n, len(S.ROCKS)) * k
    h = (RH * 8 + 30) * k + 16 * 8 + 40
    img = [[MEADOW[2] for _ in range(w)] for _ in range(h)]

    def put(frame, ox, oy):
        for y in range(RH):
            for x in range(RW):
                c = frame[y][x]
                if c[3] == 0:
                    continue
                a = c[3] / 255.0
                for dy in range(k):
                    for dx in range(k):
                        X, Y = ox + x * k + dx, oy + y * k + dy
                        if 0 <= X < w and 0 <= Y < h:
                            b = img[Y][X]
                            img[Y][X] = (int(b[0] * (1 - a) + c[0] * a), int(b[1] * (1 - a) + c[1] * a), int(b[2] * (1 - a) + c[2] * a), 255)

    for st in range(4):
        for i in range(len(S.ROCKS)):
            put(stone[st * len(S.ROCKS) + i][0], i * RW * k, st * RH * k)
        for i in range(n):
            put(frames[st * n + i][0], i * RW * k, (4 + st) * RH * k + 30)
    y0 = 8 * RH * k + 50
    for j, f in enumerate((icon_ore, icon_ingot, icon_plate)):
        icon = f()
        for yy in range(16):
            for xx in range(16):
                c = icon[yy][xx]
                if c[3]:
                    for dy in range(8):
                        for dx in range(8):
                            img[y0 + yy * 8 + dy][20 + j * 160 + xx * 8 + dx] = c
    write_png(ROOT.parent / "docs" / "img" / "iron_rocks.png", w, h, img)
    print("preview written: docs/img/iron_rocks.png")


def compare():
    """docs/img/iron_palettes.png: whole rocks 1, 2, 3, 4 and the ore icon for every palette (rows), at 3x on the meadow."""
    k, names = 3, list(PALETTES)
    cols = [1, 2, 3, 4]
    w, h = (RW * len(cols) + 40) * k, (RH * len(names)) * k
    img = [[MEADOW[2] for _ in range(w)] for _ in range(h)]

    def put(frame, ox, oy, scale):
        for y in range(len(frame)):
            for x in range(len(frame[0])):
                c = frame[y][x]
                if not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(scale):
                    for dx in range(scale):
                        X, Y = ox + x * scale + dx, oy + y * scale + dy
                        if 0 <= X < w and 0 <= Y < h:
                            b = img[Y][X]
                            img[Y][X] = (int(b[0] * (1 - a) + c[0] * a), int(b[1] * (1 - a) + c[1] * a), int(b[2] * (1 - a) + c[2] * a), 255)

    for r, name in enumerate(names):
        use(name)
        for c, i in enumerate(cols):
            put(render_iron(i, 0, 200 + i * 17)[0], c * RW * k, r * RH * k, k)
        put(icon_ore(), len(cols) * RW * k + 6, r * RH * k + 20, 5)
    use("gunmetal")
    write_png(ROOT.parent / "docs" / "img" / "iron_palettes.png", w, h, img)
    print("palettes (top to bottom): " + ", ".join(names))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "palettes":
        compare()
    else:
        main()
