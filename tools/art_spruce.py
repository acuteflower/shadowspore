#!/usr/bin/env python3
"""The game's firs (stdlib only), called by art_tree.py. Crooked, layered boughs of uneven width that droop
into ragged fingers with deep indigo-violet undersides, gaps between the tiers, dead branch stubs, hanging moss
and glowing lanterns. Six distinct silhouettes: young meadow fir, sturdy woodland fir, tall old-growth fir,
slender spire giant, wind-swept mountain fir, and broad twin-crowned forest matriarch."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import hexc, noise  # noqa: E402

CW, CH = 112, 200
FEET_X, FEET_Y = 56, 196
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

FIR_PALS = [
    [hexc(c) for c in ("121838", "14303c", "1b4a48", "286b5a", "3e8e6a", "68b886")],  # classic blue-spruce
    [hexc(c) for c in ("131a3a", "163540", "20504a", "30745c", "4c986e", "78c48a")],  # sunlit meadow fir
    [hexc(c) for c in ("101634", "132c3c", "18464c", "246864", "3a8c7c", "64b89c")],  # glaucous silver-spruce
]
FIR = FIR_PALS[0]
RIM = [hexc(c) for c in ("22707e", "4cc0c4")]  # cool twilight bounce from the right
TIP = [hexc(c) for c in ("4a2c8a", "7048d0", "b89cff")]  # void-touched needle tips
BARK = [hexc(c) for c in ("1b1326", "34283e", "56445c", "866a7c", "b29892")]
MOSS = [hexc(c) for c in ("2c6250", "3e7e5a", "589a64")]
LICHEN = [hexc(c) for c in ("2a7a78", "4cc0b4", "9af0dc")]
CONE = [hexc(c) for c in ("3c241c", "6e4628", "9e7240")]
RESIN = [hexc(c) for c in ("b87828", "f2bd54", "fff0a8")]
TEAL, TEAL_L = hexc("3cc0c6"), hexc("78f4e6")
VIO, VIO_L = hexc("8a4dff"), hexc("d9c8ff")
SHELF = [hexc(c) for c in ("1a4a52", "2f8a8c", "6ae0d2")]

VARIANTS = [
    dict(height=84, width=44, tiers=7, clear=14, trunk_hw=4.0, leader=4, lean=2, twist=0.0, bias=0.0, pal=0, twin=False, lanterns=1, moss=2, fungi=0, veins=0, hollow=False, violet=0.10, stubs=1, cones=2),
    dict(height=124, width=62, tiers=10, clear=38, trunk_hw=5.8, leader=5, lean=3, twist=1.6, bias=0.0, pal=1, twin=False, lanterns=3, moss=5, fungi=2, veins=1, hollow=False, violet=0.14, stubs=2, cones=4),
    dict(height=164, width=80, tiers=13, clear=62, trunk_hw=7.6, leader=6, lean=4, twist=2.6, bias=0.0, pal=0, twin=False, lanterns=5, moss=8, fungi=4, veins=2, hollow=True, violet=0.18, stubs=3, cones=6),
    dict(height=190, width=68, tiers=15, clear=72, trunk_hw=6.8, leader=7, lean=5, twist=3.2, bias=0.0, pal=2, twin=False, lanterns=7, moss=10, fungi=5, veins=3, hollow=True, violet=0.26, stubs=4, cones=5),
    dict(height=148, width=72, tiers=11, clear=50, trunk_hw=6.2, leader=6, lean=5, twist=2.8, bias=0.20, pal=2, twin=False, lanterns=4, moss=7, fungi=3, veins=1, hollow=False, violet=0.16, stubs=4, cones=5),
    dict(height=180, width=86, tiers=14, clear=66, trunk_hw=8.2, leader=6, lean=3, twist=2.4, bias=-0.10, pal=1, twin=True, lanterns=6, moss=9, fungi=4, veins=2, hollow=True, violet=0.22, stubs=4, cones=7),
]
SAPLING = dict(height=38, width=22, tiers=4, clear=6, trunk_hw=1.6, leader=3, lean=1, twist=0.0, bias=0.0, pal=0, twin=False, lanterns=0, moss=0, fungi=0, veins=0, hollow=False, violet=0.0, stubs=0, cones=0)
YOUNG = dict(height=84, width=42, tiers=6, clear=10, trunk_hw=3.4, leader=4, lean=2, twist=0.0, bias=0.0, pal=1, twin=False, lanterns=0, moss=0, fungi=0, veins=0, hollow=False, violet=0.05, stubs=1, cones=0)


def grid():
    return [[None] * CW for _ in range(CH)]


def put(g, x, y, c, over=True):
    if 2 <= x < CW - 2 and 2 <= y < CH and (over or g[y][x] is None):
        g[y][x] = c


class Emitters:
    """Glowing pixels: a dim colour goes into the lit art, the bright one (with a soft halo) into the glow layer."""

    def __init__(self, glow):
        self.glow = glow
        self.items = []

    def pixel(self, base_grid, x, y, dim, bright, halo=1):
        if not (2 <= x < CW - 2 and 2 <= y < CH):
            return
        put(base_grid, x, y, dim)
        put(self.glow, x, y, bright)
        self.items.append((x, y, bright, halo))

    def halos(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    if 0 < d <= radius + 0.5 and 1 <= x + dx < CW - 1 and 1 <= y + dy < CH and self.glow[y + dy][x + dx] is None:
                        self.glow[y + dy][x + dx] = (*color[:3], 106 if d < 1.6 else 48)


def spruce(spec, seed, extras=True):
    rng = random.Random(seed)
    pal = FIR_PALS[spec.get("pal", 0)]
    crown, trunk, glow_crown, glow_trunk = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_crown), Emitters(glow_trunk)
    height, width, tiers, clear = spec["height"], spec["width"], spec["tiers"], spec["clear"]
    bias = spec.get("bias", 0.0)
    top_y = max(5, FEET_Y - height + spec["leader"])
    bottom_y = FEET_Y - clear
    step = (bottom_y - top_y) / tiers
    half = min(width / 2.0, 46.0)

    # deep indigo-pine core behind the tiers so bough gaps read as rich forest shadow, never flat holes
    for y in range(int(top_y + 2), int(bottom_y - step * 0.55)):
        u = (y - top_y) / max(bottom_y - top_y, 1)
        drift = int(round(bias * half * 0.45 * (1.0 - u * 0.4)))
        hw = half * (0.09 + 0.48 * u ** 0.92)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) <= hw + (noise(dx, y, seed) / 255.0 - 0.5) * 1.5:
                put(crown, FEET_X + drift + dx, y, pal[(0, 1)[noise(dx // 2, y // 2, seed + 1) > 172]])

    tier_info = []
    for i in range(tiers):
        grow = (i + 1) / tiers
        ti = top_y + step * i * 0.95
        bi = ti + step * 1.45
        w = width * (0.14 + 0.86 * grow ** 0.88) * (0.86 + 0.26 * rng.random())
        shift = spec["lean"] * math.sin(i * 0.85 + seed) * min(1.0, grow * 1.25) + bias * half * 0.45 + rng.uniform(-0.7, 0.7)
        left = w * (0.46 - bias * 0.16 + 0.08 * rng.random())
        right = w * (0.46 + bias * 0.16 + 0.08 * rng.random())
        left = min(left, half + 2.0 + shift)
        right = min(right, half + 2.0 - shift)
        tier_info.append((ti, bi, shift, left, right, rng.random() * 9.0, 4.0 + rng.random() * 2.5))
        _tier(crown, pal, i, ti, bi, shift, left, right, tier_info[-1][5], tier_info[-1][6], step, spec, seed, i == tiers - 1)

    for k in range(spec.get("stubs", 0)):
        if len(tier_info) > 2:
            _stub(crown, pal, tier_info, k, rng)

    for y in range(2, CH):  # sunlit needle contour along upper and left edges
        for x in range(2, CW - 2):
            c = crown[y][x]
            if c is not None and c in pal:
                k = pal.index(c)
                if crown[y - 1][x] is None:
                    crown[y][x] = pal[min(k + 2, 5)]
                elif crown[y][x - 1] is None and k < 5:
                    crown[y][x] = pal[k + 1]
    _leader(crown, spec, top_y, rng, lights_c)
    _rim_and_tips(crown, pal, spec, bottom_y, seed)
    if extras:
        _cones(crown, pal, tier_info, spec.get("cones", 0), rng)
        _hanging(crown, lights_c, spec, rng)
    _trunk(trunk, glow_trunk, lights_t, spec, rng, seed, extras)
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_crown, "glow_trunk": glow_trunk}


def _tier(crown, pal, i, ti, bi, shift, left, right, phase, period, step, spec, seed, lowest):
    """One drooping skirt of boughs: bell-shaped, lit from top-left, ending in ragged needle fingers."""
    for y in range(max(int(ti), 2), min(int(bi + step * 0.8 + 10), CH - 2)):
        u = max(0.0, min(1.0, (y - ti) / max(bi - ti, 1.0)))
        for dx in range(-int(max(left, right)) - 6, int(max(left, right)) + 7):
            x = FEET_X + int(round(shift)) + dx
            if not 3 <= x < CW - 3:
                continue
            ext = left if dx < 0 else right
            hw = ext * (0.2 + 0.8 * u ** 0.82) + (noise(x, y, seed + 3) / 255.0 - 0.5) * 1.6
            slot = int((dx + phase) // period)
            local = ((dx + phase) % period) / period
            spike = (2.4 + 5.2 * (noise(slot, i, seed + 7) / 255.0)) * (1.0 + 0.85 * (abs(dx) / max(ext, 1.0)) ** 1.3) * (1.4 if lowest else 1.0)
            finger = spike * max(0.0, 1.0 - abs(local - 0.5) * 2.0) ** 1.15
            droop = (abs(dx) / max(ext, 1.0)) ** 1.7 * step * 0.68
            edge_y = bi - 1.0 + droop + finger
            if abs(dx) > hw or y > edge_y:
                continue
            light = 0.45 - 0.50 * (dx / max(hw, 1.0)) + 0.23 * (1.0 - u)
            if u < 0.30 + 0.18 * (noise(x // 3, i, seed + 31) / 255.0 - 0.5):
                light += 0.34 if dx < ext * 0.25 else 0.12
            if y > edge_y - 5.2:
                light -= 0.65
            if abs(dx) < max(left, right) * 0.14 and u > 0.3:
                light -= 0.26
            stripe = (abs(dx) * 0.95 + (y - ti) * 1.9 + i * 3) % 6.5
            light += -0.24 if stripe < 1.1 else (0.19 if stripe < 2.2 else 0.0)
            light -= 0.065 * i / max(spec["tiers"], 1)
            light += (noise(x // 2, y // 2, seed + 5) / 255.0 - 0.5) * 0.34
            v = light * 5.4 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.62
            crown[y][x] = pal[int(max(0, min(5, v)))]


def _leader(crown, spec, top_y, rng, lights):
    """Crooked bare spire tip (and a shorter fork on ancient twin-leader spruces)."""
    leaders = [(-1, spec["leader"] + 4, 0), (1, max(3, spec["leader"] + 1), 3)] if spec.get("twin") else [(rng.choice((-1, 1)), spec["leader"] + 4, 0)]
    for idx, (bend, length, x0) in enumerate(leaders):
        x = float(FEET_X + x0)
        y = int(top_y) + 2 + idx * 2
        for k in range(length):
            x += bend * 0.18 * (k / max(length, 1)) * 1.9
            yy = y - k
            if yy < 3:
                break
            put(crown, int(round(x)), yy, BARK[3] if k % 2 == 0 else BARK[2])
            if k > 2 and k % 3 == 0:
                put(crown, int(round(x)) + bend * (1 + k % 2), yy + 1, BARK[2])
        tipx, tipy = int(round(x)), max(y - length, 3)
        if idx == 0 and spec["height"] >= 180:
            lights.pixel(crown, tipx, tipy, VIO, VIO_L, 2)
        elif spec["tiers"] >= 10:
            put(crown, tipx, tipy, TIP[1])


def _stub(crown, pal, tiers, _k, rng):
    """A weathered dead branch poking out between two bough skirts."""
    _ti, bi, shift, left, right, _p, _per = tiers[rng.randrange(1, len(tiers) - 1)]
    side = rng.choice((-1, 1))
    y = int(bi - 2 + rng.random() * 3)
    reach = min(46, int((left if side < 0 else right)) + rng.randrange(2, 5))
    for i in range(int(reach * 0.58), reach):
        x = FEET_X + int(round(shift)) + side * i
        yy = y + (1 if i > reach * 0.78 else 0)
        if 4 <= x < CW - 4:
            put(crown, x, yy, BARK[3 if side < 0 else 2])
            put(crown, x, yy + 1, BARK[1])
    for d in range(3):
        x = FEET_X + int(round(shift)) + side * (reach - 1 - d)
        if 4 <= x < CW - 4:
            put(crown, x, y + 2, pal[2 + d % 2])


def _cones(crown, pal, tiers, count, rng):
    """Small hanging warm-brown spruce cones tucked under upper/mid bough rims."""
    if not tiers or count <= 0:
        return
    for _ in range(count):
        _ti, bi, shift, left, right, _p, _per = tiers[rng.randrange(0, max(1, len(tiers) - 2))]
        side = rng.choice((-1, 1))
        ext = left if side < 0 else right
        x = FEET_X + int(round(shift + side * ext * rng.uniform(0.35, 0.78)))
        y = int(bi + rng.uniform(-1.0, 2.0))
        if 5 <= x < CW - 5 and 6 <= y < CH - 12 and crown[y - 1][x] in pal:
            put(crown, x, y, CONE[2 if side < 0 else 1])
            put(crown, x, y + 1, CONE[1])
            put(crown, x, y + 2, CONE[0])


def _rim_and_tips(crown, pal, spec, bottom_y, seed):
    edges = []
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            c = crown[y][x]
            if c is None or c not in pal:
                continue
            if crown[y][x + 1] is None and noise(x, y, seed + 21) > 72 and c in pal[1:4]:
                crown[y][x] = RIM[0] if noise(x, y, seed + 22) > 95 else RIM[1]
            if crown[y + 1][x] is None and y > bottom_y - spec["height"] * 0.75:
                edges.append((x, y))
    for x, y in edges:
        roll = noise(x, y, seed + 23) / 255.0
        if roll < spec["violet"]:
            crown[y][x] = TIP[int(noise(x, y, seed + 24) > 150) + (1 if roll < spec["violet"] * 0.25 else 0)]
            if crown[y - 1][x] is not None and roll < spec["violet"] * 0.5:
                crown[y - 1][x] = TIP[0]


def _hanging(crown, lights, spec, rng):
    hem = []
    for y in range(6, CH - 10):
        for x in range(5, CW - 5):
            if crown[y][x] is not None and crown[y + 1][x] is None and y > FEET_Y - spec["clear"] - spec["height"] * 0.7:
                hem.append((x, y))
    if not hem:
        return
    for _ in range(spec["moss"]):
        x, y = hem[rng.randrange(len(hem))]
        for k in range(rng.randrange(3, 8)):
            c = LICHEN[0] if k < 2 else (LICHEN[1] if k < 5 else LICHEN[0])
            sway = (1 if (k // 3) % 2 else 0) if k > 3 else 0
            put(crown, x + sway, y + 1 + k, c, over=False)
        end = [yy for yy in range(y + 1, min(CH - 2, y + 9)) if crown[yy][x] is not None and crown[yy][x] in LICHEN]
        if end:
            lights.pixel(crown, x, end[-1], LICHEN[1], LICHEN[2], 1)
    for n in range(spec["lanterns"]):
        x, y = hem[rng.randrange(len(hem))]
        thread = rng.randrange(2, 5)
        for k in range(thread):
            put(crown, x, y + 1 + k, BARK[2], over=False)
        cy = y + thread + 2
        if cy >= CH - 4:
            continue
        color = (TEAL, TEAL_L) if n % 3 else (VIO, VIO_L)
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                if abs(dx) + abs(dy) <= 1 or (dx, dy) == (-1, -1):
                    base = (color[0][0] // 2, color[0][1] // 2, color[0][2] // 2, 255) if abs(dx) + abs(dy) else color[0]
                    put(crown, x + dx, cy + dy, base)
        lights.pixel(crown, x, cy, color[0], color[1], 3)
        put(lights.glow, x - 1, cy - 1, (*color[1][:3], 255))
        lights.items.append((x - 1, cy - 1, color[1], 1))


def _trunk(trunk, glow, lights, spec, rng, seed, extras, bark=None):
    bark = bark or BARK
    clear, trunk_hw = spec["clear"], spec["trunk_hw"]
    twist = spec["twist"]
    phase = rng.random() * 6.0
    top = max(6, FEET_Y - clear - 16)
    centers = {}

    def cx_at(y):
        t = (FEET_Y - y) / max(clear + 16, 1)
        return FEET_X + int(round(twist * (math.sin(t * 2.6 + phase) - math.sin(phase))))

    for y in range(top, FEET_Y + 1):
        t_up = (FEET_Y - y) / max(clear + 16, 1)
        flare = max(0.0, (y - (FEET_Y - 10)) * 0.78)
        hw = trunk_hw * (1.0 - 0.3 * t_up) + flare
        centers[y] = (cx_at(y), hw)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = cx_at(y) + dx
            if not 2 <= x < CW - 2:
                continue
            lit = 0.56 - 0.55 * dx / max(hw, 1.0)
            ridge = (dx + int(noise(y // 6, 0, seed) % 3)) % 3 == 0
            band = 0.20 if (y // 5) % 4 == 0 else 0.0
            v = lit * 4.0 + (noise(x, y, seed + 2) / 255.0 - 0.5) * 0.82 - (0.85 if ridge else 0.0) + (0.45 if (dx + 1) % 3 == 0 and lit > 0.4 else 0.0) - band
            trunk[y][x] = bark[int(max(0, min(4, v)))]
            if y > FEET_Y - 15 and dx < 1 and noise(x, y, seed + 8) > 152 and noise(x // 2, y // 2, seed + 9) > 102:
                trunk[y][x] = MOSS[int(noise(x, y, seed + 4) > 150) + (1 if lit > 0.6 else 0)]
    if clear > 20:
        for f in (0.3, 0.5, 0.72, 0.9):
            y = FEET_Y - int(clear * f)
            if y not in centers:
                continue
            side, length = rng.choice((-1, 1)), rng.randrange(3, 6)
            cx, hw = centers[y]
            for k in range(length):
                put(trunk, cx + side * (int(hw) + k), y + (1 if k > length // 2 else 0), bark[2])
                put(trunk, cx + side * (int(hw) + k), y + 1 + (1 if k > length // 2 else 0), bark[1])
    if not extras:
        _roots(trunk, bark, trunk_hw, lights, spec, False)
        return
    for v in range(spec["veins"]):
        y = FEET_Y - int(clear * rng.uniform(0.15, 0.4))
        x_off = rng.uniform(-0.45, 0.2) * trunk_hw
        for k in range(int(clear * rng.uniform(0.35, 0.6))):
            yy = y - k
            if yy not in centers:
                break
            cx, hw = centers[yy]
            xx = cx + int(round(x_off + 1.4 * math.sin(k * 0.45 + v * 2.0)))
            if abs(xx - cx) < hw - 0.5 and 2 <= xx < CW - 2 and trunk[yy][xx] is not None:
                lights.pixel(trunk, xx, yy, VIO if k % 3 else TIP[1], VIO_L if k % 3 else VIO, 1)
    for f in range(spec["fungi"]):
        y = FEET_Y - int(clear * rng.uniform(0.12, 0.92))
        if y not in centers:
            continue
        cx, hw = centers[y]
        side = -1 if f % 2 else 1
        for i in range(5):
            x = cx + side * (int(hw) + i)
            top_y = y + (1 if i > 2 else 0)
            put(trunk, x, top_y, SHELF[1])
            put(trunk, x, top_y + 1, SHELF[0])
            lights.pixel(trunk, x, top_y - (1 if 0 < i < 4 else 0), SHELF[2], TEAL_L, 1)
        put(trunk, cx + side * (int(hw) + 1), y + 2, SHELF[0])
    if spec["hollow"]:
        y = FEET_Y - int(clear * 0.5)
        if y in centers:
            cx, _hw = centers[y]
            for dy in range(-3, 4):
                for dx in range(-2, 3):
                    d = (dx / 2.2) ** 2 + (dy / 3.4) ** 2
                    if d <= 1.0:
                        put(trunk, cx + dx - 1, y + dy, bark[0] if d < 0.6 else bark[3])
            lights.pixel(trunk, cx - 1, y, TEAL, TEAL_L, 2)
            put(glow, cx - 1, y + 1, (*TEAL_L[:3], 255))
            put(trunk, cx - 1, y + 1, TEAL)
    _roots(trunk, bark, trunk_hw, lights, spec, True)


def _roots(trunk, bark, trunk_hw, lights, spec, glow_tips):
    for side in (-1, 1):
        length = int(trunk_hw * 1.55) + 6
        for k in range(length):
            x = FEET_X + side * (int(trunk_hw) + k)
            y = FEET_Y - max(0, 4 - k // 3) + (1 if k > 6 else 0) + (1 if k > length - 4 else 0)
            thick = 3 if k < length // 2 else (2 if k < length - 3 else 1)
            for yy in range(y, min(y + thick, FEET_Y + 2)):
                tone = int(max(1, 3 - k // 3)) if side == -1 else int(max(0, 2 - k // 3))
                put(trunk, x, yy, bark[tone])
            if k % 3 == 1 and k > 1:
                put(trunk, x, y, MOSS[1])
        if glow_tips and spec["violet"] > 0.2 and side == 1:
            lights.pixel(trunk, FEET_X + side * (int(trunk_hw) + length - 1), FEET_Y + 1, VIO, VIO_L, 1)
