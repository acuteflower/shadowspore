#!/usr/bin/env python3
"""The mine's own rocks (docs/mine.md section 8): hewn and fallen rock in the colours of the mine's walls (warm plum-grey, a pale lit edge, dust), no crystals, runes or
glowing moss. Same layout as the world's assets/props/rock.png (8 rocks x 4 states: whole, chipped, small, rubble; 64x56 frames, feet (32, 52)), drawn by the same
renderer (tools/art_stone.py) with the palette and the shapes swapped:
  assets/mine/props/mine_rocks.png   the sheet (data/plants.json mine_rock / mine_collapse)
  assets/mine/props/rubble_a|b|c.png the rubble state of three of them, cropped, as floor decoration (MineClutter)
`python3 tools/art_mine_rocks.py`, then `Godot --headless --import`."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_stone as a  # noqa: E402
from gen_art import ROOT, hexc, noise, write_png  # noqa: E402

a.STONE = [hexc(c) for c in ("15101a", "2a2230", "453a42", "66575f", "8a7a80", "c4b4b0")]  # shade .. glint, warm
a.MOSS = [hexc(c) for c in ("1e2c24", "2c4032", "42603a", "62843f")]  # damp, dim
a.RIM_COOL = [hexc(c) for c in ("5a4a5a", "8a7280")]
a.LICHEN_ROCK = [hexc(c) for c in ("8a7c78", "b4a49a")]
OUTLINE = hexc("0e0a12")

# ("block", cx, width at the foot, width at the top, height, lean, depth); heights fit data/plants.json (36..48 px tall pillars, low slabs)
a.ROCKS = [
    {"prims": [("block", 32, 22, 14, 14, 1, 0)], "moss": 0.0, "crack": 2, "strata": 4},
    {"prims": [("block", 26, 28, 20, 22, -1, 0), ("block", 44, 20, 12, 14, 2, -1)], "moss": 0.1, "crack": 3, "strata": 5},
    {"prims": [("block", 30, 44, 30, 30, 0, 0), ("block", 12, 16, 10, 18, -2, -1), ("block", 50, 18, 12, 20, 2, -1), ("block", 40, 14, 8, 12, 0, 1)], "moss": 0.25, "crack": 4, "strata": 6},
    {"prims": [("block", 32, 20, 10, 47, 1, 0), ("block", 44, 10, 6, 16, -2, -1)], "moss": 0.0, "crack": 3, "strata": 7},
    {"prims": [("block", 32, 52, 46, 15, 0, 0), ("block", 22, 30, 22, 9, -1, 1)], "moss": 0.2, "crack": 2, "strata": 5, "lichen": True},
    {"prims": [("block", 26, 17, 9, 38, -2, 0), ("block", 40, 15, 8, 29, 2, 0), ("block", 16, 11, 6, 20, -2, -1), ("block", 50, 11, 6, 15, 2, -1)], "moss": 0.0, "crack": 3, "strata": 6},
    {"prims": [("block", 30, 38, 26, 28, 0, 0), ("block", 14, 16, 11, 14, -1, -1), ("block", 48, 18, 12, 15, 1, -1)], "moss": 0.5, "crack": 3, "strata": 5, "lichen": True},
    {"prims": [("block", 24, 26, 18, 20, -1, 0), ("block", 40, 24, 16, 16, 1, 0), ("block", 32, 18, 9, 30, 0, -1)], "moss": 0.1, "crack": 4, "strata": 6},
]


def recolour(px):
    """The renderer's outlines are blue-violet and green: make them the mine's ink."""
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] and tuple(c[:3]) in ((0x1a, 0x16, 0x33), (0x12, 0x26, 0x1f)):
                px[y][x] = (*OUTLINE[:3], c[3])
    return px


def crop(px, pad=2):
    ys = [y for y in range(a.RH) for x in range(a.RW) if px[y][x][3] > 200]
    xs = [x for y in range(a.RH) for x in range(a.RW) if px[y][x][3] > 200]
    x0, x1, y0, y1 = max(min(xs) - pad, 0), min(max(xs) + pad + 1, a.RW), max(min(ys) - pad, 0), min(max(ys) + pad + 1, a.RH)
    return [row[x0:x1] for row in px[y0:y1]], a.GR - y0


def main():
    out = ROOT / "mine" / "props"
    out.mkdir(parents=True, exist_ok=True)
    n = len(a.ROCKS)
    frames = [recolour(a.render_rock(i, st, 150 + i * 13 + st)[0]) for st in range(4) for i in range(n)]
    write_png(out / "mine_rocks.png", a.RW * n, a.RH * 4, a.sheet(frames, n, 4, a.RW, a.RH))
    for name, index in (("a", 0), ("b", 1), ("c", 2)):
        px, feet = crop(frames[3 * n + index])
        write_png(out / f"rubble_{name}.png", len(px[0]), len(px), px)
        print("rubble", name, len(px[0]), "x", len(px), "feet", feet)
    print("mine rocks written")


if __name__ == "__main__":
    main()
