"""The old wool blanket of the hut's bed, as ellipsoids in bed space (x along the bed, west -> east, y up from the floor, z towards the viewer; the mattress top
is 13 units up). `s` 0 = spread over her legs from the hips to the foot end, humps for the knees and feet, a hem hanging over the near side; 1 = a heap
bunched near the middle (the bed's frame 1 shows it for good). In between it is pulled up into her lap and shoved aside."""
import math
import numpy as np

import art_hero3d as h
from hut_lib import *

BED_TOP = 13.0


def cloth(m, s, seed=7):
    rng = rng_for(seed)
    start = 3.0 + (-9.0 - 3.0) * s
    end = 36.0 + (3.0 - 36.0) * s
    length = end - start
    n = max(6, int(length / 1.5))
    for i in range(n + 1):
        t = i / n
        x = start + length * t
        profile = math.sqrt(max(0.0, 1.0 - (2.0 * t - 1.0) ** 2)) ** 0.55  # rounded ends: the cloth is a sheet, not a box
        legs = (1.0 - s) * (1.7 * math.exp(-((x - 12.0) / 5.5) ** 2) + 2.1 * math.exp(-((x - 27.0) / 4.8) ** 2))
        wrinkle = (0.4 + 1.6 * s) * (fbm(x * 0.45, seed, 3) - 0.5)
        ry = 1.3 + 3.4 * s * profile + legs + wrinkle
        rz = (12.4 - 4.0 * s) * (0.45 + 0.55 * profile) + 0.5 * math.sin(x * 0.7)
        step = length / n * 1.3
        mat = CLAY if (t < 0.06 or t > 0.94) and s < 0.5 else WOOL  # the hem is striped
        m.ell((x, BED_TOP + ry * 0.6, 0.0), (step, ry, rz), mat)
        if i % 2 == 0:  # the near edge falls in folds over the rail
            drop = (2.4 + 2.4 * math.sin(x * 0.9 + 1.0) ** 2) * (1.0 - 0.55 * s) * (0.5 + 0.5 * profile)
            m.ell((x, BED_TOP - drop * 0.55, rz * 0.96), (step * 0.8, drop, 0.9), WOOL if i % 4 else CLAY)
    for _ in range(int(5 + 8 * s)):  # folds on top
        x = rng.uniform(start + 2, end - 2)
        R = h.rot_x(rng.uniform(-0.5, 0.5)) @ h.rot_y(rng.uniform(-0.6, 0.6))
        m.ell((x, BED_TOP + 2.8 + 3.2 * s, rng.uniform(-4, 4)), (rng.uniform(2, 4.5), 0.5, rng.uniform(2.5, 6.0) * (1 - 0.3 * s)), WOOL, R=R)
    for _ in range(int(1 + 3 * s)):  # a corner turned over, lighter lining
        x = rng.uniform(start + 3, end - 3)
        m.ell((x, BED_TOP + 3.2 + 2.6 * s, rng.uniform(2, 6)), (rng.uniform(1.8, 3), 0.45, rng.uniform(1.5, 3)), CLAY)
    return m
