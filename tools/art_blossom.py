#!/usr/bin/env python3
"""The Dämmerblüte (dusk blossom tree), called by art_tree2.py (stdlib only). A short, twisted trunk (the fir's trunk
with its violet veins and shelf fungi) forks into limbs under a low, round crown of violet-pink blossom clumps with
green leaves peeking out of the shade; small petal clusters hang from the underside. At night the whole crown glows
softly (a translucent wash in the glow layer, brighter on the lighter blossoms) and the hearts of some blossoms shine. The picked state shows the same crown in green with only a few blossoms left.

blossom(spec, seed, picked=False, extras=True) -> dict(trunk, crown, glow_crown, glow_trunk)."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
from art_spruce import CW, CH, FEET_X, FEET_Y, BARK, RIM, Emitters, grid, put  # noqa: E402
from art_willow import LEAF, lobes_shade  # noqa: E402
from gen_art import hexc, noise  # noqa: E402

BLOOM = [hexc(c) for c in ("2a1450", "54287e", "8a3eae", "c25cc8", "ea92dc", "fcd0f2")]  # violet shade .. pale pink light
PETAL = hexc("fff0fa")
POLLEN = hexc("ffe8a0")

VARIANTS = [
    dict(height=70, w=50, h=34, clear=12, trunk_hw=3.6, twist=1.0, fungi=0, veins=0, hollow=False, violet=0.0),
    dict(height=98, w=70, h=46, clear=18, trunk_hw=5.0, twist=2.0, fungi=1, veins=1, hollow=False, violet=0.0),
    dict(height=126, w=90, h=58, clear=26, trunk_hw=6.6, twist=2.8, fungi=2, veins=1, hollow=True, violet=0.0),
    dict(height=152, w=106, h=70, clear=34, trunk_hw=8.0, twist=3.4, fungi=3, veins=2, hollow=True, violet=0.0),
]
SAPLING = dict(height=36, w=20, h=14, clear=8, trunk_hw=1.5, twist=0.0, fungi=0, veins=0, hollow=False, violet=0.0)
YOUNG = dict(height=66, w=40, h=28, clear=10, trunk_hw=3.0, twist=0.0, fungi=0, veins=0, hollow=False, violet=0.0)


def blossom(spec, seed, picked=False, extras=True):
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    height, w, h = spec["height"], spec["w"], spec["h"]
    top_y = FEET_Y - height
    cx = FEET_X + int(round(spec["twist"] * 0.7))
    cy = top_y + h * 0.5

    trunk_h = height - int(h * 0.5)
    sp._trunk(trunk, glow_t, lights_t, dict(clear=trunk_h - 16, trunk_hw=spec["trunk_hw"], twist=spec["twist"], veins=spec["veins"], fungi=spec["fungi"], hollow=spec["hollow"], violet=spec["violet"]), rng, seed, extras)
    base_x = FEET_X + int(round(spec["twist"] * (math.sin(2.6) - math.sin(0.0))))
    for side in (-1, 0, 1):  # limbs fork into the crown
        for k in range(int(h * 0.5)):
            t = k / max(h * 0.5, 1)
            x = base_x + side * int(t * w * 0.3 + math.sin(t * 3.0 + side) * 1.5)
            y = FEET_Y - trunk_h + 3 - int(t * h * (0.4 if side else 0.5))
            thick = max(1, int(spec["trunk_hw"] * 0.5 * (1.0 - t * 0.7)))
            for dx in range(-thick, thick + 1):
                put(trunk, x + dx, y, BARK[2 if dx >= 0 else 3])
                put(trunk, x + dx, y + 1, BARK[1])

    lobes = []
    for _ in range(int(w * h / 56)):  # big clumps of blossom, more toward the top
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random())
        x = cx + math.cos(a) * r * w * 0.5
        y = cy + math.sin(a) * r * h * 0.5 * (1.0 if math.sin(a) < 0 else 0.8)
        size = rng.uniform(4.5, 8.5) * (0.65 + 0.35 * w / 100.0 + 0.2)
        lobes.append((x, y, size, size * 0.9, y * 0.03))
    for gu in (-0.3, 0.0, 0.3):  # a few big lobes underneath, so the clumps leave no holes
        lobes.append((cx + gu * w * 0.5, cy + 0.05 * h, w * 0.3, h * 0.36, -40.0))
    for i in range(int(w / 6)):  # small petal clusters along the underside
        u = (i / max(w / 6 - 1, 1)) * 2.0 - 1.0
        lobes.append((cx + u * w * 0.44 + rng.uniform(-2, 2), cy + h * 0.5 * (0.7 + 0.2 * (1 - u * u)) + rng.uniform(-1, 3), rng.uniform(2, 3.5), rng.uniform(2, 3.5), 6.0))
    ramp = LEAF if picked else BLOOM
    lobes_shade(crown, lobes, ramp, seed + 1, -0.12 if picked else -0.27)
    pixels = [(x, y) for y in range(CH) for x in range(CW) if crown[y][x] is not None]
    for x, y in pixels:
        k = ramp.index(crown[y][x])
        if not picked and k <= 1 and noise(x, y, seed + 6) > 150:  # green leaves peek out of the shade
            crown[y][x] = LEAF[1 + int(noise(x, y, seed + 7) > 160)]
        elif picked and k >= 3 and noise(x, y, seed + 8) > 238:  # a last blossom or two
            crown[y][x] = BLOOM[3 + int(noise(x, y, seed + 9) > 247)]
    for y in range(1, CH):  # lit contour on top and left, cool light on the right
        for x in range(1, CW - 1):
            c = crown[y][x]
            if c is None or c not in ramp:
                continue
            k = ramp.index(c)
            if crown[y - 1][x] is None:
                crown[y][x] = ramp[min(k + 2, 5)]
            elif crown[y][x - 1] is None and k < 5:
                crown[y][x] = ramp[k + 1]
            elif crown[y][x + 1] is None and noise(x, y, seed + 9) > 90 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 150)]
    if not picked:
        for _ in range(int(len(pixels) / 26)):  # single petals catch the light
            x, y = pixels[rng.randrange(len(pixels))]
            if crown[y][x] in BLOOM[2:5]:
                crown[y][x] = BLOOM[min(BLOOM.index(crown[y][x]) + 2, 5)]
                put(crown, x + 1, y, BLOOM[3])
        if extras:
            for x, y in pixels:  # at night the whole crown glows softly: the lighter the blossom, the brighter
                if crown[y][x] in BLOOM[2:]:
                    k = BLOOM.index(crown[y][x])
                    glow_c[y][x] = (*BLOOM[min(k + 1, 5)][:3], 115 if k >= 4 else (80 if k == 3 else 40))
            for _ in range(6 + int(w / 8)):  # the hearts of some blossoms glow
                for _try in range(30):
                    x, y = pixels[rng.randrange(len(pixels))]
                    if crown[y][x] in BLOOM[3:6]:
                        lights_c.pixel(crown, x, y, PETAL, PETAL, 1)
                        break
            for _ in range(2 + int(w / 30)):  # a speck of pollen
                x, y = pixels[rng.randrange(len(pixels))]
                lights_c.pixel(crown, x, y, POLLEN, POLLEN, 1)
    elif extras:
        for _ in range(3):  # a few leaf buds glow teal
            x, y = pixels[rng.randrange(len(pixels))]
            lights_c.pixel(crown, x, y, sp.TEAL, sp.TEAL_L, 1)
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}
