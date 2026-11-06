#!/usr/bin/env python3
"""The Schleierweide (weeping willow of the meadow), called by art_tree2.py (stdlib only). A knotted, leaning
trunk (the fir's trunk with its violet veins, shelf fungi and glowing hollow) carries a dome of dense leaf
clumps; from the dome's rim hang long curved strands of leaves and luminous moss down to the ground, so you
can walk in under the curtain. Some strands glow teal along their length, dew drops hang at the ends.

willow(spec, seed, extras=True) -> dict(trunk, crown, glow_crown, glow_trunk), the same layers as art_spruce."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
from art_spruce import CW, CH, FEET_X, FEET_Y, BAYER, BARK, TEAL, TEAL_L, VIO, VIO_L, TIP, RIM, Emitters, grid, put  # noqa: E402
from gen_art import hexc, noise  # noqa: E402

LEAF = [hexc(c) for c in ("101a36", "143640", "1c5a52", "2c8062", "54b07a", "9ae094")]  # shade .. sunlit tips (yellower than the firs)
STRAND = [hexc(c) for c in ("143640", "1c5a52", "2c8062", "54b07a", "9ae094")]
LICHEN = sp.LICHEN  # shade, body, tip of the luminous moss

VARIANTS = [
    dict(height=92, dome_w=54, dome_h=26, strands=30, trunk_hw=4.2, twist=1.0, lean=2, lanterns=1, fungi=0, veins=0, hollow=False, violet=0.08, dew=1),
    dict(height=130, dome_w=78, dome_h=34, strands=46, trunk_hw=5.8, twist=2.0, lean=3, lanterns=2, fungi=2, veins=1, hollow=False, violet=0.12, dew=2),
    dict(height=164, dome_w=98, dome_h=42, strands=62, trunk_hw=7.6, twist=3.0, lean=4, lanterns=3, fungi=3, veins=1, hollow=True, violet=0.18, dew=4),
    dict(height=190, dome_w=106, dome_h=48, strands=74, trunk_hw=8.4, twist=3.6, lean=5, lanterns=4, fungi=4, veins=2, hollow=True, violet=0.25, dew=6),
]
SAPLING = dict(height=40, dome_w=24, dome_h=14, strands=9, trunk_hw=1.6, twist=0.0, lean=1, lanterns=0, fungi=0, veins=0, hollow=False, violet=0.0, dew=0)
YOUNG = dict(height=84, dome_w=44, dome_h=22, strands=22, trunk_hw=3.4, twist=0.0, lean=2, lanterns=0, fungi=0, veins=0, hollow=False, violet=0.05, dew=0)


def lobes_shade(grid_px, lobes, ramp, seed, bias):
    """Shades the union of the lobes like spheres (lit from the top left, ordered dither); fills `grid_px`."""
    depth = [[-1e9] * CW for _ in range(CH)]
    normal = [[None] * CW for _ in range(CH)]
    for cx, cy, rx, ry, cz in lobes:
        for y in range(max(0, int(cy - ry) - 1), min(CH, int(cy + ry) + 2)):
            for x in range(max(0, int(cx - rx) - 1), min(CW, int(cx + rx) + 2)):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                z = math.sqrt(1.0 - d)
                zw = cz * 2.0 + z * max(rx, ry) * 0.8
                if zw > depth[y][x]:
                    depth[y][x] = zw
                    normal[y][x] = (dx, dy, z)
    for y in range(CH):
        for x in range(CW):
            n = normal[y][x]
            if n is None:
                continue
            light = (n[0] * -0.55 + n[1] * -0.75 + n[2] * 0.6 + 1.0) / 2.0 + bias
            light += (noise(x, y, seed) / 255.0 - 0.5) * 0.3
            v = light * (len(ramp) - 0.2) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.8
            grid_px[y][x] = ramp[int(max(0, min(len(ramp) - 1, v)))]
    return normal


def willow(spec, seed, extras=True):
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    height, w, h = spec["height"], spec["dome_w"], spec["dome_h"]
    top_y = FEET_Y - height
    cx = FEET_X + rng.choice((-1, 1)) * spec["lean"]
    rim_y = top_y + h  # where the dome ends and the strands begin
    ground_y = FEET_Y - 4

    # the trunk: the fir's (veins, fungi, hollow, roots) up to the dome, then limbs into it
    trunk_h = height - int(h * 0.6)
    sp._trunk(trunk, glow_t, lights_t, dict(clear=trunk_h - 16, trunk_hw=spec["trunk_hw"], twist=spec["twist"], veins=spec["veins"], fungi=spec["fungi"], hollow=spec["hollow"], violet=spec["violet"]), rng, seed, extras)
    top_cx = FEET_X + int(round(spec["twist"] * (math.sin(2.6 + 0.0) - 0.0)))
    for side in (-1, 1):  # two thick limbs fan out into the dome
        for k in range(int(h * 0.55)):
            t = k / max(h * 0.55, 1)
            x = top_cx + side * int(t * w * 0.34 + math.sin(t * 3.0 + side) * 2.0)
            y = FEET_Y - trunk_h + 2 - int(t * h * 0.5) + int(t * t * h * 0.1)
            thick = max(1, int(spec["trunk_hw"] * 0.55 * (1.0 - t * 0.8)))
            for dx in range(-thick, thick + 1):
                put(trunk, x + dx, y, BARK[2 if dx >= 0 else 3])
                put(trunk, x + dx, y + 1, BARK[1])

    # the dome: clumps of leaves, lit from the top left
    lobes = []
    for _ in range(int(w * h / 60)):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random())
        x = cx + math.cos(a) * r * w * 0.5
        y = top_y + h * 0.55 + math.sin(a) * r * h * 0.5 * (1.0 if math.sin(a) < 0 else 0.55)
        size = rng.uniform(3.6, 7.0) * (0.7 + 0.3 * w / 100.0 + 0.3)
        lobes.append((x, y, size, size * 0.86, y * 0.03))
    for i in range(int(w / 7)):  # a ragged rim of small clumps
        u = (i / max(w / 7 - 1, 1)) * 2.0 - 1.0
        lobes.append((cx + u * w * 0.46, rim_y - h * 0.08 + abs(u) ** 2 * h * 0.1, rng.uniform(3, 5), rng.uniform(2.5, 4), 5.0))
    normal = lobes_shade(crown, lobes, LEAF, seed + 1, -0.2)
    for y in range(1, CH):  # lit contour on top and left, cool light on the right
        for x in range(1, CW - 1):
            c = crown[y][x]
            if c is None or c not in LEAF:
                continue
            k = LEAF.index(c)
            if crown[y - 1][x] is None:
                crown[y][x] = LEAF[min(k + 2, 5)]
            elif crown[y][x - 1] is None and k < 5:
                crown[y][x] = LEAF[k + 1]
            elif crown[y][x + 1] is None and noise(x, y, seed + 9) > 90 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 150)]

    # the strands: each hangs from the dome's rim, swaying in a curve, down towards the ground
    strands = []
    for i in range(spec["strands"]):
        u = rng.uniform(-1.0, 1.0)
        reach = 0.55 + 0.45 * abs(u) ** 0.7  # the outer strands hang lowest, the middle ones are hidden by the trunk
        top = rim_y - h * 0.18 + abs(u) ** 2 * h * 0.12 + rng.uniform(-2, 2)
        length = (ground_y - top) * min(1.0, reach * rng.uniform(0.7, 1.0))
        strands.append((length, u, top, rng.uniform(0, math.tau), rng.uniform(1.0, 2.6), rng.random() < 0.3))
    strands.sort(key=lambda s: s[0])  # short ones first, the long ones in front
    dews = []
    for n, (length, u, top, phase, amp, glowing) in enumerate(strands):
        x_top = cx + u * w * 0.5
        flare = u * 0.05  # the curtain widens a little as it falls
        tone = int(max(0, min(3, rng.choice((0, 1, 1, 2)) + (1 if u < 0 else 0))))
        thick = rng.random() < 0.28
        last_x = int(x_top)
        for k in range(int(length)):
            xx = int(round(x_top + k * flare + math.sin(k * 0.1 + phase) * amp * min(k / 14.0, 1.0)))
            yy = int(top + k)
            if k < 8 or (thick and k % 2 == 0):
                put(crown, xx + 1, yy, STRAND[max(tone - 1, 0)])
            c = STRAND[min(4, tone + (1 if k > length * 0.9 else 0))]
            if glowing:
                c = hexc("1f5f60") if k % 5 else LICHEN[0]
            put(crown, xx, yy, c)
            if k % 3 == 1 and k > 4:  # leaves on the sides
                put(crown, xx + (1 if (k // 3 + n) % 2 else -1), yy, STRAND[min(4, tone + 1)])
            if glowing and extras and k % 9 == 4:
                lights_c.pixel(crown, xx, yy, LICHEN[1], LICHEN[2], 1)
            if rng.random() < spec["violet"] * 0.04 and k > length * 0.7:
                put(crown, xx, yy, TIP[int(rng.random() > 0.5)])
            last_x = xx
        if glowing and extras:
            lights_c.pixel(crown, last_x, int(top + length) - 1, LICHEN[1], LICHEN[2], 2)
        dews.append((last_x, int(top + length)))
    if extras:
        for n in range(spec["dew"]):  # dew drops hang at the ends of some strands
            x, y = dews[rng.randrange(len(dews) // 2, len(dews))]
            for k in range(3):
                put(crown, x, y + k, STRAND[1])
            color = (TEAL, TEAL_L) if n % 3 else (VIO, VIO_L)
            for dy in range(2):
                for dx in range(2):
                    put(crown, x + dx - 1, y + 3 + dy, color[0])
            lights_c.pixel(crown, x, y + 3, color[0], color[1], 3)
            put(glow_c, x - 1, y + 3, (*color[1][:3], 255))
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}
