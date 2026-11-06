#!/usr/bin/env python3
"""The forest floor under groves and woods: assets/props/forestbed.png, 6 irregular patches (192x128 each, radii FOREST_BED_RX) that lie
under every tree of a wood, like the gravel of art_stone.py lies under rock formations (kind `forestbed` of PropGenerator).
Plum-brown humus, a litter of needles and short twigs, a few cones, cushions of dark moss (the land flora's green ramp), pale lichen
specks; the rim dissolves into the meadow in dither. Lit like everything else from the top left (needle strokes catch the light).
Run: python3 tools/art_forestbed.py [preview.png], then Godot --headless --import."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, MEADOW, blank  # noqa: E402
from gen_art import ROOT, hexc, noise, write_png  # noqa: E402

BW, BH = 192, 128
FOREST_BED_RX = [28, 36, 44, 52, 60, 70]  # keep in sync with PropGenerator.FOREST_BED_RX
HUMUS = [hexc(c) for c in ("2e2428", "40322f", "574436", "70594a")]
NEEDLE = [hexc(c) for c in ("6a503e", "866948", "a48660", "c4a67c")]
MOSS = [hexc(c) for c in ("1d3d34", "28503f", "346b49", "49865a")]
CONE = [hexc(c) for c in ("3e2a28", "5e4036", "80604a")]
LICHEN = hexc("9ccab4")


def forest_bed(index, seed):
    rng = random.Random(seed)
    rx = FOREST_BED_RX[index]
    ry = rx * 0.64
    cx, cy = BW / 2.0, BH / 2.0
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    px = blank(BW, BH)
    inside = {}
    for y in range(BH):
        for x in range(BW):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            ang = math.atan2(dy, dx)
            warp = 1.0 + 0.09 * math.sin(3 * ang + ph[0]) + 0.07 * math.sin(5 * ang + ph[1]) + 0.04 * math.sin(9 * ang + ph[2])
            d = math.hypot(dx, dy) / warp
            if d > 1.05:
                continue
            edge = (d - 0.62) / 0.38  # 0 inside .. 1 at the rim
            if edge > 0.0:
                keep = BAYER[y % 4][x % 4] / 16.0 * 0.65 + (noise(x, y, seed) / 255.0) * 0.35
                if keep < edge * 1.05:
                    continue
            tone = noise(x // 2, y // 2, seed + 1) / 255.0 + (noise(x, y, seed + 2) / 255.0 - 0.5) * 0.4 - 0.2 * edge
            px[y][x] = HUMUS[0 if tone < 0.2 else (1 if tone < 0.5 else (2 if tone < 0.85 else 3))]
            inside[(x, y)] = edge
    # moss cushions: a few noise blobs, lit on their upper left
    for _ in range(max(2, int(rx / 12))):
        a, r = rng.uniform(0, 6.28), math.sqrt(rng.random()) * 0.75
        mx, my, mr = cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r, rng.uniform(3.5, 7.0)
        for y in range(int(my - mr), int(my + mr) + 1):
            for x in range(int(mx - mr * 1.3), int(mx + mr * 1.3) + 1):
                if (x, y) not in inside:
                    continue
                dd = math.hypot((x - mx) / 1.3, y - my) / mr + (noise(x, y, seed + 7) / 255.0 - 0.5) * 0.5
                if dd < 1.0:
                    lit = (x - mx) * -0.4 + (y - my) * -0.7
                    px[y][x] = MOSS[1 if dd > 0.7 else (3 if lit > 1.2 else 2)]
    # litter: short needle strokes lying every which way, twigs, cones
    for _ in range(int(rx * 2.2)):
        a, r = rng.uniform(0, 6.28), math.sqrt(rng.random()) * 0.92
        x0, y0 = cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r
        ang = rng.choice((0.6, 0.9, 2.2, 2.5, 1.5)) + rng.uniform(-0.3, 0.3)
        length = rng.randrange(2, 5)
        for k in range(length):
            x, y = int(x0 + math.cos(ang) * k), int(y0 + math.sin(ang) * k * 0.6)
            if (x, y) in inside and inside[(x, y)] < 0.8:
                px[y][x] = NEEDLE[min(3, 1 + (k == 0) + (ang < 1.0))] if rng.random() > 0.12 else NEEDLE[0]
    for _ in range(max(1, int(rx / 22))):  # twigs
        a, r = rng.uniform(0, 6.28), math.sqrt(rng.random()) * 0.7
        x0, y0 = cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r
        ang = rng.uniform(0.2, 1.2) * rng.choice((1, -1))
        for k in range(rng.randrange(6, 11)):
            x, y = int(x0 + math.cos(ang) * k), int(y0 + math.sin(ang) * k * 0.55)
            if (x, y) in inside and inside[(x, y)] < 0.8:
                px[y][x] = CONE[1] if k % 3 else CONE[2]
    for _ in range(max(1, int(rx / 24))):  # cones: a 3x2 lump, lit on top
        a, r = rng.uniform(0, 6.28), math.sqrt(rng.random()) * 0.7
        x0, y0 = int(cx + math.cos(a) * rx * r), int(cy + math.sin(a) * ry * r)
        for dy, row in enumerate(((1, 2, 1), (0, 1, 1))):
            for dx, v in enumerate(row):
                if (x0 + dx, y0 + dy) in inside:
                    px[y0 + dy][x0 + dx] = CONE[2 if (dy == 0 and v) else (1 if v else 0)]
    for _ in range(int(rx / 8)):  # pale lichen specks
        x, y = int(cx + rng.uniform(-rx, rx) * 0.8), int(cy + rng.uniform(-ry, ry) * 0.8)
        if (x, y) in inside and inside[(x, y)] < 0.6 and noise(x, y, seed + 9) > 120:
            px[y][x] = LICHEN
    for (x, y), edge in inside.items():  # the meadow creeps in at the rim
        if edge > 0.45 and noise(x // 3, y // 3, seed + 4) > 140 and noise(x, y, seed + 5) > 90:
            px[y][x] = MEADOW[2] if noise(x, y, seed + 6) > 120 else MEADOW[3]
    return px


def sheet(frames):
    return [[frames[x // BW][y][x % BW] for x in range(BW * len(frames))] for y in range(BH)]


def main():
    beds = [forest_bed(i, 410 + i * 17) for i in range(len(FOREST_BED_RX))]
    write_png(ROOT / "props" / "forestbed.png", BW * len(beds), BH, sheet(beds))
    print("forestbed.png written", BW * len(beds), "x", BH)
    if len(sys.argv) > 1:
        from PIL import Image
        im = Image.open(ROOT / "props" / "forestbed.png").convert("RGBA")
        bg = Image.new("RGBA", im.size, (62, 125, 86, 255))
        bg.alpha_composite(im)
        bg.resize((im.width * 2, im.height * 2), Image.NEAREST).save(sys.argv[1])


if __name__ == "__main__":
    main()
