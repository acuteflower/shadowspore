#!/usr/bin/env python3
"""The few things of the hallway (data/interiors.json "flur", written by tools/art_hallway.py, which calls `make()` here): a stone bench opposite every wall light, a blue glazed jar at each end, a wall torch between
every two doors and a small flag of the fortress (dark blue with the gold diamond of the carpet) half way between each torch and each door. Benches and jars are built like Ellie's furniture
(tools/servant_furniture.py); torch and flag are drawn pixel by pixel on the plane of the wall. Everything sits on the wall's foot or on its own feet row, so it sorts with the people.
    python3 tools/art_hallway_props.py [preview.png]"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import servant_furniture as furn  # noqa: E402
from hut_lib import BARK, BARK_D, CLAY, FIRE, GAP, IRON, PLANK_W, V, glow_of, grain, log, render, slab, to_array  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "assets" / "interior" / "flur"

WINE = [(8, 12, 30), (18, 28, 62), (30, 48, 98), (46, 72, 132)]  # the dark blue of the fortress
GOLD = [(88, 62, 30), (156, 120, 56), (214, 176, 96)]
INK = (6, 8, 20)


def save(name, arr):
    Image.fromarray(arr).save(OUT / name)


def bench():
    """A bench of the hallway's own cut stone: a thick slab on two blocks, lit on its top and left, a joint in the blocks, the dither of the walls."""
    import servant_wall
    pal = [tuple(int(v) for v in c[:3]) for c in servant_wall.PAL]
    fw, fh = 64, 30
    a = np.zeros((fh, fw, 4), np.uint8)
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0

    def px(x, y, c):
        a[y, x] = (*c, 255)

    def tone(x, y, base):
        return pal[max(0, min(5, base + (1 if bayer[y % 4, x % 4] > 0.62 else 0) - (1 if bayer[y % 4, x % 4] < 0.12 else 0)))]

    for sx in (9, 43):  # the two blocks
        for y in range(15, 25):
            for x in range(sx, sx + 12):
                px(x, y, INK if x in (sx, sx + 11) or y == 24 else tone(x, y, 2 if x < sx + 3 else 1))
    for y in range(3, 15):  # the slab: its top, then its front face
        for x in range(3, 61):
            if y in (3, 14) or x in (3, 60):
                px(x, y, INK)
            elif y < 10:
                px(x, y, tone(x, y, 4 if x < 6 or y == 4 else 3))
            else:
                px(x, y, tone(x, y, 2 if x < 6 else 1))
    for y in range(4, 10):
        px(31, y, pal[2])  # a joint across the top
    furn._ground(a, 24, 28, 3)
    return a, 24


def jar():
    """A tall clay jar with a gold band round its neck, dark inside."""
    m = h.Model()
    m.ell((0, 10.0, 0), (6.6, 9.5, 6.0), CLAY)
    m.ell((0, 3.0, 0), (4.6, 3.0, 4.2), CLAY)
    m.ell((0, 18.5, 0), (3.6, 3.2, 3.3), CLAY)
    m.ell((0, 21.2, 0), (4.8, 1.0, 4.4), CLAY)
    m.ell((0, 21.7, 0), (3.5, 0.5, 3.1), GAP)
    m.ell((0, 16.4, 0), (4.0, 0.7, 3.7), IRON)  # the band (iron: it is the tinted ramp; the gold line is drawn on below)
    arr = to_array(render(m, 24, 34, 28))
    ys, xs = np.nonzero(arr[:, :, 3])
    for x in range(arr.shape[1]):  # a thin gold line on the belly
        for y in range(arr.shape[0]):
            if arr[y, x, 3] and tuple(arr[y, x, :3]) in {tuple(c[:3]) for c in h.RAMPS[IRON]} and y in (16, 17):
                arr[y, x, :3] = GOLD[1 + (x % 2)]
    clay = {tuple(c[:3]): i for i, c in enumerate(h.RAMPS[CLAY])}
    for y in range(arr.shape[0]):  # glazed in the blue of the fortress
        for x in range(arr.shape[1]):
            if arr[y, x, 3] == 255 and tuple(int(v) for v in arr[y, x, :3]) in clay:
                arr[y, x, :3] = WINE[min(3, clay[tuple(int(v) for v in arr[y, x, :3])])]
    return furn._ground(arr, 28, 8, 2.5), 28


def torch():
    """An iron bracket on a plate with a bowl and a flame. Returns the picture and its glow (only the flame)."""
    fw, fh = 14, 26
    a = np.zeros((fh, fw, 4), np.uint8)
    iron = [tuple(c[:3]) for c in h.RAMPS[IRON]]
    fire = [tuple(c[:3]) for c in h.RAMPS[FIRE]]

    def px(x, y, c):
        a[y, x] = (*c, 255)

    for y in range(10, 22):  # the plate on the wall, lit on its left
        for x in range(4, 10):
            px(x, y, INK if x in (4, 9) or y in (10, 21) else iron[1 + (x < 6)])
    for (x, y) in ((5, 12), (8, 19)):
        px(x, y, iron[3])  # rivets
    for x in range(3, 11):  # the arm and the bowl: a short horizontal lip with a cup above it
        px(x, 15, INK)
        px(x, 16, iron[2] if x < 7 else iron[1])
    for x in range(3, 11):
        px(x, 13, INK) if x in (3, 10) else px(x, 13, iron[2])
    for y in (11, 12):
        px(3, y, INK)
        px(10, y, INK)
    for x in range(4, 10):
        px(x, 11, GOLD[0])  # a glowing coal bed in the cup
    for y, w in ((10, 4), (9, 4), (8, 4), (7, 3), (6, 3), (5, 2), (4, 1), (3, 1)):  # the flame, pointing up and swaying a little to the right
        x0 = 7 - w // 2 + (1 if y < 7 else 0)
        for x in range(x0, x0 + w):
            inner = x0 < x < x0 + w - 1 or w < 3
            px(x, y, fire[min(len(fire) - 1, (1 if inner else 0) + (10 - y) // 3 + 1)])
    glow = glow_of(a)
    return a, glow, fh


def flag():
    """A small flag of the fortress, hung from an iron rod: dark blue cloth, a thin gold border, the gold diamond with its stud, a swallow tail."""
    fw, fh = 16, 28
    a = np.zeros((fh, fw, 4), np.uint8)
    iron = [tuple(c[:3]) for c in h.RAMPS[IRON]]

    def px(x, y, c):
        a[y, x] = (*c, 255)

    for x in range(0, 16):  # the rod with its two knobs
        px(x, 2, INK)
        px(x, 3, iron[3] if x % 4 else iron[2])
        px(x, 4, INK)
    for y in (2, 3, 4):
        px(0, y, GOLD[2] if y == 3 else INK)
        px(15, y, GOLD[2] if y == 3 else INK)
    top, bottom = 5, 26
    for y in range(top, bottom):
        notch = max(0, y - (bottom - 6))  # the swallow tail
        for x in range(2, 14):
            if notch and abs(x - 7.5) < notch * 0.9:
                continue
            edge = x in (2, 13) or y == bottom - 1 - (0 if notch == 0 else 0)
            if edge:
                px(x, y, INK)
                continue
            shade = 3 if x < 5 else (2 if x < 9 else (1 if x < 12 else 0))
            if (x + y) % 5 == 0 and shade > 0:
                shade -= 1
            px(x, y, WINE[shade])
            if x in (3, 12) or y == top:
                px(x, y, GOLD[1] if (x + y) % 2 else GOLD[0])  # the border
    cx, cy = 7.5, 13.0
    for y in range(7, 21):  # the diamond
        for x in range(3, 13):
            d = abs(x - cx) + abs(y - cy) * 0.9
            if abs(d - 4.4) < 0.7:
                px(x, y, GOLD[2] if x < 8 else GOLD[1])
            elif d < 1.6:
                px(x, y, GOLD[1])
    for y in range(bottom - 6, bottom):  # clean the cut-out of the tail's inside edge
        pass
    return a, fh


def make(ox=0):
    """Writes the pictures and returns {name: (frame height)} for the JSON."""
    OUT.mkdir(parents=True, exist_ok=True)
    b, bfeet = bench()
    save("bench.png", b)
    j, jfeet = jar()
    save("jar.png", j)
    t, tglow, th = torch()
    save("torch.png", t)
    save("torch_glow.png", tglow)
    f, fh = flag()
    save("flag.png", f)
    return {"bench": (b.shape[0], bfeet), "jar": (j.shape[0], jfeet), "torch": th, "flag": fh}


if __name__ == "__main__":
    info = make()
    print(info)
    if len(sys.argv) > 1:
        canvas = Image.new("RGBA", (200, 60), (60, 56, 90, 255))
        x = 4
        for name in ("bench", "jar", "torch", "flag"):
            im = Image.open(OUT / (name + ".png")).convert("RGBA")
            canvas.alpha_composite(im, (x, 8))
            x += im.width + 8
        canvas.resize((800, 240), Image.NEAREST).save(sys.argv[1])
