"""The 2D animated and soft things of the hut: flames (6 frames), sunbeams (3 frames), cobwebs, a water drip and its splash. Painted with the same ramps."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *


def fire_frames(W=34, H=28):
    """6 frames of W x H (34 x 28 in the hearth, a smaller one for the yard's fire pit): flames licking up from the embers, a hot core, ragged tips, flying sparks. Unlit."""
    out = np.zeros((H, W * 6, 4), np.uint8)
    for f in range(6):
        for x in range(W):
            c = abs(x - (W - 1) / 2.0) / (W / 2.0)
            base = max(0.0, 1.0 - c ** 1.5)
            wob = fbm(x * 0.2 + f * 0.9, f * 0.7, 3) * 0.9 + 0.35 * math.sin(f * 1.05 + x * 0.4)
            top = int((H - 4) * base * (0.35 + 0.65 * wob))
            for y in range(H):
                depth = H - 1 - y
                if depth > top:
                    continue
                k = depth / max(top, 1)
                core = 1.0 - c * 1.3
                tone = 3 if (k < 0.4 and core > 0.55) else (2 if k < 0.65 or core > 0.4 else (1 if k < 0.9 else 0))
                tone = int(max(0, min(3, tone + (1 if bayer(x, y) < 0.12 and k < 0.8 else 0) - (1 if bayer(x, y) > 0.9 and k > 0.5 else 0))))
                if k > 0.93 and hsh(x, y, f) > 0.5:
                    continue
                out[y, f * W + x] = (*h.RAMPS[FIRE][tone][:3], 255)
        for s in range(4):
            sx = int(6 + hsh(s, f, 1) * (W - 12))
            sy = int(H - 4 - hsh(s, f, 2) * (H - 6))
            if out[sy, f * W + sx, 3] == 0:
                out[sy, f * W + sx] = (*h.RAMPS[FIRE][3][:3], 255)
    return out


def rays_arr():
    """Sunbeams falling through the windows: soft slanted bands of light with dust, 3 frames of 64 x 96, additive."""
    frames = []
    for f in range(3):
        img = np.zeros((96, 64, 4), np.uint8)
        for y in range(96):
            for x in range(64):
                u = (x - y * 0.5 - 6) / 30.0
                if 0.0 < u < 1.0:
                    edge = min(u, 1.0 - u) * 4.0
                    a = min(edge, 1.0) * (0.5 + 0.5 * (1.0 - y / 96.0)) * (0.75 + 0.25 * fbm(x * 0.08 + f * 0.9, y * 0.1, 9))
                    a *= 0.5 + 0.5 * (bayer(x, y) < a * 1.4)
                    if a > 0.15:
                        img[y, x] = (255, 244, 214, int(70 * a))
        frames.append(img)
    return np.concatenate(frames, axis=1)


def web(img, x0, y0, size, flip=False):
    cx = x0 + size if flip else x0
    for a in np.linspace(0.05, math.pi / 2 - 0.05, 5):
        for r in range(size):
            px = cx + (-1 if flip else 1) * int(r * math.cos(a))
            py = y0 + int(r * math.sin(a))
            if 0 <= px < img.shape[1] and 0 <= py < img.shape[0]:
                img[py, px] = (200, 196, 220, 150)
    for r in (size * 0.4, size * 0.65, size * 0.9):
        for a in np.linspace(0.05, math.pi / 2 - 0.05, int(r * 2)):
            sag = math.sin(a * 6) * 0.8
            px = cx + (-1 if flip else 1) * int((r - sag) * math.cos(a))
            py = y0 + int((r - sag) * math.sin(a))
            if 0 <= px < img.shape[1] and 0 <= py < img.shape[0]:
                img[py, px] = (210, 206, 228, 120)


def webs_arr():
    out = np.zeros((26, 28, 4), np.uint8)
    web(out, 0, 0, 24, False)
    return out


def drip_arr():
    """Water dripping from the roof: 4 frames of 8 x 14 (a drop forms, stretches, falls, falls) and 5 frames of 18 x 8 for the splash on the floor."""
    d = np.zeros((14, 8 * 4, 4), np.uint8)
    water = [(120, 150, 200, 255), (190, 215, 245, 255), (230, 245, 255, 255)]
    shapes = [[(3, 2), (4, 2), (3, 3), (4, 3)], [(3, 2), (4, 2), (3, 3), (4, 3), (3, 4), (4, 4)], [(3, 5), (4, 5), (3, 6), (4, 6), (3, 7), (4, 7), (3, 8), (4, 8)], [(3, 9), (4, 9), (3, 10), (4, 10), (3, 11), (4, 11)]]
    for f, px in enumerate(shapes):
        for i, (x, y) in enumerate(px):
            d[y, f * 8 + x] = water[2 if i < 2 else (1 if i < 5 else 0)]
    s = np.zeros((8, 18 * 5, 4), np.uint8)
    for f in range(5):
        r = 2 + f * 2
        for a in np.linspace(0, math.pi, 24):
            x = int(9 + math.cos(a) * r)
            y = int(6 - math.sin(a) * (r * 0.5 + (2 if f < 3 else 0)))
            if 0 <= x < 18 and 0 <= y < 8:
                s[y, f * 18 + x] = (*water[1][:3], max(0, 255 - f * 52))
    return d, s
