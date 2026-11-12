#!/usr/bin/env python3
"""The Schleierweide (weeping willow of the meadow), called by art_tree2.py (stdlib only).
Six organic silhouettes: leaning waterside trunks that fork into parted, multi-cushioned upper bough domes
(with dark crooked branches peeking between leaf clusters) and graceful curtains of swaying willow strands,
luminous moss catkins and twilight dew drops."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
from art_spruce import CW, CH, FEET_X, FEET_Y, BAYER, TEAL, TEAL_L, VIO, VIO_L, TIP, RIM, Emitters, grid, put  # noqa: E402
from gen_art import hexc, noise  # noqa: E402

WILLOW_BARK = [hexc(c) for c in ("1e1c30", "38364c", "5c5a70", "8c8a9e", "bcbece")]
LEAF_PALS = [
    [hexc(c) for c in ("111b38", "153842", "1e5c54", "2f8264", "58b27c", "9ae096")],  # classic sea-jade willow
    [hexc(c) for c in ("111b38", "163a48", "226068", "3c8c8a", "6cbeb2", "aeeedc")],  # silver-seafoam shore willow
    [hexc(c) for c in ("141a38", "1a3a40", "2a5e4e", "46865e", "76b672", "b6e696")],  # sunlit meadow-sage willow
]
LEAF = LEAF_PALS[0]
STRAND = LEAF[1:]
LICHEN = sp.LICHEN

VARIANTS = [
    dict(height=92, dome_w=54, dome_h=26, strands=32, trunk_hw=4.2, twist=1.2, lean=2, asym=0.0, pal=0, sub_domes=2, lanterns=1, fungi=0, veins=0, hollow=False, violet=0.08, dew=1),
    dict(height=130, dome_w=78, dome_h=34, strands=48, trunk_hw=5.8, twist=2.1, lean=3, asym=0.08, pal=0, sub_domes=3, lanterns=2, fungi=2, veins=1, hollow=False, violet=0.12, dew=2),
    dict(height=164, dome_w=96, dome_h=42, strands=64, trunk_hw=7.4, twist=3.0, lean=4, asym=-0.06, pal=2, sub_domes=4, lanterns=3, fungi=3, veins=1, hollow=True, violet=0.18, dew=4),
    dict(height=188, dome_w=102, dome_h=48, strands=74, trunk_hw=8.2, twist=3.5, lean=5, asym=0.05, pal=0, sub_domes=4, lanterns=4, fungi=4, veins=2, hollow=True, violet=0.25, dew=6),
    dict(height=116, dome_w=68, dome_h=30, strands=42, trunk_hw=5.0, twist=2.6, lean=5, asym=0.22, pal=1, sub_domes=3, lanterns=2, fungi=1, veins=1, hollow=False, violet=0.14, dew=3),
    dict(height=176, dome_w=100, dome_h=44, strands=70, trunk_hw=8.0, twist=3.2, lean=-4, asym=-0.12, pal=1, sub_domes=5, lanterns=4, fungi=3, veins=2, hollow=True, violet=0.22, dew=5),
]
SAPLING = dict(height=40, dome_w=24, dome_h=14, strands=10, trunk_hw=1.6, twist=0.0, lean=1, asym=0.0, pal=0, sub_domes=2, lanterns=0, fungi=0, veins=0, hollow=False, violet=0.0, dew=0)
YOUNG = dict(height=84, dome_w=44, dome_h=22, strands=24, trunk_hw=3.4, twist=0.5, lean=2, asym=0.0, pal=0, sub_domes=2, lanterns=0, fungi=0, veins=0, hollow=False, violet=0.05, dew=0)


def lobes_shade(grid_px, lobes, ramp, seed, bias):
    """Shades the union of 3D ellipsoid lobes (lit from top-left, smooth Bayer dither, structured foliage grain)."""
    depth = [[-1e9] * CW for _ in range(CH)]
    normal = [[None] * CW for _ in range(CH)]
    for cx, cy, rx, ry, cz in lobes:
        for y in range(max(2, int(cy - ry) - 1), min(CH - 2, int(cy + ry) + 2)):
            for x in range(max(2, int(cx - rx) - 1), min(CW - 2, int(cx + rx) + 2)):
                dx, dy = (x + 0.5 - cx) / max(rx, 0.5), (y + 0.5 - cy) / max(ry, 0.5)
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                z = math.sqrt(1.0 - d)
                zw = cz * 2.0 + z * max(rx, ry) * 0.8
                if zw > depth[y][x]:
                    depth[y][x] = zw
                    normal[y][x] = (dx, dy, z)
    n_tones = len(ramp)
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            n = normal[y][x]
            if n is None:
                continue
            light = (n[0] * -0.56 + n[1] * -0.76 + n[2] * 0.58 + 1.0) / 2.0 + bias
            light += (noise(x // 2, y // 2, seed) / 255.0 - 0.5) * 0.24
            v = light * (n_tones - 0.18) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.72
            grid_px[y][x] = ramp[int(max(0, min(n_tones - 1, v)))]
    return normal


def willow(spec, seed, extras=True):
    rng = random.Random(seed)
    pal = LEAF_PALS[spec.get("pal", 0)]
    strand_pal = pal[1:]
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    height, w, h = spec["height"], min(spec["dome_w"], 100), spec["dome_h"]
    asym = spec.get("asym", 0.0)
    top_y = max(4, FEET_Y - height)
    cx = max(int(w * 0.5) + 4, min(CW - int(w * 0.5) - 4, FEET_X + int(round(spec["lean"] + asym * 8))))
    rim_y = top_y + h
    ground_y = FEET_Y - 4

    trunk_h = height - int(h * 0.58)
    sp._trunk(trunk, glow_t, lights_t, dict(clear=max(8, trunk_h - 16), trunk_hw=spec["trunk_hw"], twist=spec["twist"], veins=spec["veins"], fungi=spec["fungi"], hollow=spec["hollow"], violet=spec["violet"]), rng, seed, extras, bark=WILLOW_BARK)
    top_cx = FEET_X + int(round(spec["twist"] * math.sin(2.6)))

    # crooked spreading limbs fan out into parted dome cushions
    n_sub = spec.get("sub_domes", 3)
    bough_tips = []
    for bi in range(n_sub):
        u = -0.72 + 1.44 * (bi / max(n_sub - 1, 1)) if n_sub > 1 else 0.0
        target_x = cx + u * w * 0.34
        target_y = top_y + h * (0.36 + 0.18 * abs(u) + (0.08 if bi % 2 else -0.04))
        bough_tips.append((target_x, target_y, u))
        steps = max(8, int(h * 0.65))
        for k in range(steps):
            t = k / max(steps - 1, 1)
            bx = int(round((1 - t) * top_cx + t * target_x + math.sin(t * 3.1 + bi) * 1.8))
            by = int(round((1 - t) * (FEET_Y - trunk_h + 3) + t * target_y - math.sin(t * math.pi) * h * 0.14))
            thick = max(1, int(spec["trunk_hw"] * 0.48 * (1.0 - t * 0.72)))
            for dx in range(-thick, thick + 1):
                put(trunk, bx + dx, by, WILLOW_BARK[3 if dx < 0 else 2])
                put(trunk, bx + dx, by + 1, WILLOW_BARK[1])
                if t > 0.45 and k % 2 == 0:
                    put(crown, bx + dx, by, WILLOW_BARK[2 if dx <= 0 else 1])

    # parted, cushioned dome clusters around each bough (not a single egg)
    lobes = []
    for bx, by, u in bough_tips:
        sub_w = w * (0.44 if n_sub >= 4 else 0.54)
        sub_h = h * 0.56
        count = max(6, int(sub_w * sub_h / 34))
        for _ in range(count):
            a = rng.uniform(0, math.tau)
            r = math.sqrt(rng.random())
            lx = max(6, min(CW - 7, bx + math.cos(a) * r * sub_w * 0.52))
            ly = max(5, by + math.sin(a) * r * sub_h * 0.5 * (1.0 if math.sin(a) < 0 else 0.65))
            sz = rng.uniform(3.4, 6.4) * (0.72 + 0.28 * w / 100.0 + 0.22)
            lobes.append((lx, ly, sz * 1.08, sz * 0.82, ly * 0.03 - abs(u) * 1.5))
    for i in range(int(w / 6)):
        u = (i / max(w / 6 - 1, 1)) * 2.0 - 1.0
        lx = max(6, min(CW - 7, cx + u * w * 0.45))
        lobes.append((lx, rim_y - h * 0.10 + abs(u) ** 1.8 * h * 0.12 + rng.uniform(-1.5, 1.5), rng.uniform(3.0, 5.0), rng.uniform(2.4, 3.8), 5.0))
    lobes_shade(crown, lobes, pal, seed + 1, -0.18)

    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            c = crown[y][x]
            if c is None or c not in pal:
                continue
            k = pal.index(c)
            if crown[y - 1][x] is None:
                crown[y][x] = pal[min(k + 2, 5)]
            elif crown[y][x - 1] is None and k < 5:
                crown[y][x] = pal[k + 1]
            elif crown[y][x + 1] is None and noise(x, y, seed + 9) > 92 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 150)]

    # weeping strands hanging in layered curtains
    strands = []
    for _i in range(spec["strands"]):
        u = rng.uniform(-1.0, 1.0)
        bias_mul = 1.0 + asym * u * 0.45
        reach = (0.52 + 0.48 * abs(u) ** 0.72) * bias_mul
        top = rim_y - h * 0.20 + abs(u) ** 2 * h * 0.12 + rng.uniform(-2.0, 2.0)
        length = (ground_y - top) * min(1.0, reach * rng.uniform(0.66, 1.0))
        strands.append((max(6.0, length), u, top, rng.uniform(0, math.tau), rng.uniform(0.9, 2.4), rng.random() < 0.28))
    strands.sort(key=lambda s: s[0])
    dews = []
    for n, (length, u, top, phase, amp, glowing) in enumerate(strands):
        x_top = cx + u * w * 0.48
        flare = u * 0.045 + asym * 0.03
        tone = int(max(0, min(3, rng.choice((0, 1, 1, 2)) + (1 if u < -0.1 else 0))))
        thick = rng.random() < 0.26
        last_x = int(round(x_top))
        for k in range(int(length)):
            xx = max(4, min(CW - 5, int(round(x_top + k * flare + math.sin(k * 0.1 + phase) * amp * min(k / 14.0, 1.0)))))
            yy = int(top + k)
            if yy >= ground_y + 2:
                break
            if k < 7 or (thick and k % 2 == 0):
                put(crown, xx + 1, yy, strand_pal[max(tone - 1, 0)])
            c = strand_pal[min(4, tone + (1 if k > length * 0.88 else 0))]
            if glowing:
                c = hexc("1f5f60") if k % 5 else LICHEN[0]
            put(crown, xx, yy, c)
            if k % 3 == 1 and k > 4:
                put(crown, xx + (1 if (k // 3 + n) % 2 else -1), yy, strand_pal[min(4, tone + 1)])
            if glowing and extras and k % 9 == 4:
                lights_c.pixel(crown, xx, yy, LICHEN[1], LICHEN[2], 1)
            if rng.random() < spec["violet"] * 0.04 and k > length * 0.7:
                put(crown, xx, yy, TIP[int(rng.random() > 0.5)])
            last_x = xx
        end_y = min(ground_y + 1, int(top + length))
        if glowing and extras:
            lights_c.pixel(crown, last_x, end_y - 1, LICHEN[1], LICHEN[2], 2)
        dews.append((last_x, end_y))
    if extras and dews:
        for n in range(spec["dew"]):
            x, y = dews[rng.randrange(len(dews) // 2, len(dews))]
            if y + 4 >= FEET_Y:
                continue
            for k in range(3):
                put(crown, x, y + k, strand_pal[1])
            color = (TEAL, TEAL_L) if n % 3 else (VIO, VIO_L)
            for dy in range(2):
                for dx in range(2):
                    put(crown, x + dx - 1, y + 3 + dy, color[0])
            lights_c.pixel(crown, x, y + 3, color[0], color[1], 3)
            if 2 <= x - 1 < CW - 2:
                put(glow_c, x - 1, y + 3, (*color[1][:3], 255))
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}
