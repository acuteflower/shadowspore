#!/usr/bin/env python3
"""The Dämmerblüte (dusk blossom tree), called by art_tree2.py (stdlib only).
An ancient, windswept twilight Prunus / orchard tree — never a round pink lollipop:
  - A sinuous, curving main trunk that meanders up into the crown and sends out crooked limbs at
    staggered heights (a low side shelf, mid-crown boughs, and an asymmetric billowing crest).
  - Overlapping, terraced horizontal blossom clouds with deep indigo-plum & meadow-teal foliage
    crevices between the tiers, glimpses of dark bark elbows, and delicate trailing petal strands.
  - Three restrained twilight palettes: Dämmerrose, Mondblüte (lilac-ivory), Abendglut (peach-rose).
  - Picked state shows a full, lush meadow-teal leafy tree with a few lingering buds.

blossom(spec, seed, picked=False, extras=True) -> dict(trunk, crown, glow_crown, glow_trunk)."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
from art_bush import bezier  # noqa: E402
from art_spruce import CW, CH, FEET_X, FEET_Y, RIM, SHELF, TEAL, TEAL_L, VIO, VIO_L, Emitters, grid, put  # noqa: E402
from art_willow import lobes_shade  # noqa: E402
from gen_art import hexc, noise  # noqa: E402

BLOSSOM_BARK = [hexc(c) for c in ("191226", "31203a", "523652", "7c5870", "aa8694")]
BLOSSOM_LEAF = [hexc(c) for c in ("111c38", "173c42", "235e50", "38845c", "5eb070", "96da88")]

BLOOM_PALS = [
    # 0: Dämmerrose — deep indigo-plum shade -> muted dusk rose -> warm cream-blush sunlit petals
    [hexc(c) for c in ("22163c", "3f2454", "6c3a74", "9c5c8e", "cc8cae", "efc0d0", "fff0ec")],
    # 1: Mondblüte — twilight violet shade -> misty lilac-rose -> silvery ivory-blush
    [hexc(c) for c in ("1f183e", "3a2a5c", "604684", "8e6ea8", "be9ece", "e6cee8", "fbf2fa")],
    # 2: Abendglut — plum-umber shade -> dusty coral-rose -> warm sunset-cream
    [hexc(c) for c in ("261638", "482448", "783a5c", "aa5e76", "d68e96", "f2c2b6", "fff2de")],
]
BLOOM = BLOOM_PALS[0][1:]
PETAL_GLOW = [hexc("ffe6f0"), hexc("f4e8ff"), hexc("ffecd0")]
POLLEN = hexc("ffe89e")

# boughs: (attach_t along trunk 0..1, dx_frac, y_frac_in_crown 0=top..1=bottom, w_frac, h_frac)
VARIANTS = [
    # v0: Young windswept leaning sapling-tree (asymmetric low left shelf + higher right crest)
    dict(
        height=72, w=50, h=44, clear=14, trunk_hw=3.5, lean=2.8, twist=1.5, twin=False, pal=0,
        fungi=0, veins=0, hollow=False, violet=0.05, racemes=7,
        boughs=[
            (0.48, -0.30, 0.66, 0.62, 0.48),
            (0.74, 0.24, 0.36, 0.68, 0.54),
            (0.95, -0.06, 0.20, 0.58, 0.46),
        ],
    ),
    # v1: Graceful S-curved meadow blossom tree (low sweeping right bough, airy stepped crown)
    dict(
        height=98, w=68, h=58, clear=20, trunk_hw=4.8, lean=-3.2, twist=2.2, twin=False, pal=1,
        fungi=1, veins=1, hollow=False, violet=0.08, racemes=11,
        boughs=[
            (0.44, 0.34, 0.72, 0.54, 0.42),
            (0.64, -0.30, 0.50, 0.62, 0.46),
            (0.82, 0.16, 0.30, 0.64, 0.48),
            (0.96, -0.10, 0.16, 0.54, 0.42),
        ],
    ),
    # v2: Spreading orchard Dämmerblüte (wide terraced boughs, sunset peach-rose)
    dict(
        height=124, w=86, h=72, clear=26, trunk_hw=6.0, lean=2.5, twist=2.8, twin=False, pal=2,
        fungi=2, veins=1, hollow=False, violet=0.10, racemes=15,
        boughs=[
            (0.42, -0.36, 0.72, 0.52, 0.40),
            (0.56, 0.36, 0.60, 0.54, 0.42),
            (0.74, -0.20, 0.38, 0.60, 0.46),
            (0.88, 0.20, 0.24, 0.58, 0.44),
            (0.98, -0.02, 0.14, 0.50, 0.38),
        ],
    ),
    # v3: Twin-stemmed crooked twilight tree (two trunks diverging into staggered cloud tiers)
    dict(
        height=142, w=92, h=82, clear=32, trunk_hw=4.5, lean=-2.0, twist=2.4, twin=True, pal=0,
        fungi=2, veins=2, hollow=True, violet=0.14, racemes=18,
        boughs=[
            (0.45, -0.36, 0.72, 0.52, 0.40),
            (0.52, 0.35, 0.58, 0.54, 0.42),
            (0.72, -0.24, 0.42, 0.56, 0.44),
            (0.80, 0.22, 0.28, 0.58, 0.44),
            (0.94, -0.08, 0.16, 0.54, 0.40),
            (0.66, 0.02, 0.48, 0.48, 0.38),
        ],
    ),
    # v4: Windswept cascading moon-blossom (dramatic leaning trunk, low trailing shelf + high crest)
    dict(
        height=154, w=96, h=88, clear=36, trunk_hw=6.8, lean=5.5, twist=3.2, twin=False, pal=1,
        fungi=3, veins=2, hollow=True, violet=0.16, racemes=20,
        boughs=[
            (0.40, 0.38, 0.76, 0.52, 0.38),
            (0.56, -0.34, 0.58, 0.52, 0.40),
            (0.70, 0.26, 0.44, 0.58, 0.44),
            (0.84, -0.16, 0.28, 0.60, 0.44),
            (0.96, 0.10, 0.15, 0.54, 0.40),
            (0.64, 0.00, 0.50, 0.48, 0.38),
        ],
    ),
    # v5: Ancient gnarled matriarch Dämmerblüte (massive twisted trunk, broad multi-tiered canopy)
    dict(
        height=168, w=100, h=96, clear=40, trunk_hw=8.0, lean=-3.8, twist=3.6, twin=False, pal=2,
        fungi=4, veins=3, hollow=True, violet=0.20, racemes=24,
        boughs=[
            (0.40, -0.38, 0.76, 0.50, 0.38),
            (0.50, 0.38, 0.66, 0.52, 0.40),
            (0.65, -0.28, 0.48, 0.56, 0.42),
            (0.75, 0.26, 0.38, 0.56, 0.42),
            (0.88, -0.12, 0.22, 0.58, 0.42),
            (0.97, 0.10, 0.14, 0.52, 0.38),
            (0.60, 0.02, 0.54, 0.50, 0.40),
        ],
    ),
]
SAPLING = dict(
    height=38, w=24, h=20, clear=8, trunk_hw=1.6, lean=1.5, twist=0.6, twin=False, pal=0,
    fungi=0, veins=0, hollow=False, violet=0.0, racemes=0,
    boughs=[(0.55, -0.22, 0.60, 0.64, 0.52), (0.92, 0.20, 0.26, 0.68, 0.54)],
)
YOUNG = dict(
    height=68, w=44, h=38, clear=12, trunk_hw=2.8, lean=-2.0, twist=1.2, twin=False, pal=0,
    fungi=0, veins=0, hollow=False, violet=0.0, racemes=4,
    boughs=[(0.48, -0.28, 0.64, 0.60, 0.48), (0.76, 0.24, 0.34, 0.66, 0.52), (0.95, -0.04, 0.18, 0.54, 0.44)],
)


def _draw_branch_curve(target_grid, pts, r0, r1, bark):
    n = max(len(pts) - 1, 1)
    for i, (fx, fy) in enumerate(pts):
        t = i / n
        rad = r0 + (r1 - r0) * t
        cx, cy = int(round(fx)), int(round(fy))
        ir = int(math.ceil(rad))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= (rad + 0.25) ** 2:
                    lit = -0.55 * dx - 0.75 * dy
                    tone = 3 if lit > 0.45 else (2 if lit > -0.25 else 1)
                    if dy >= ir and rad >= 1.1:
                        tone = 0
                    put(target_grid, cx + dx, cy + dy, bark[tone])


def blossom(spec, seed, picked=False, extras=True):
    rng = random.Random(seed)
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)

    pal_idx = spec.get("pal", 0)
    bloom_ramp = BLOOM_PALS[pal_idx]
    height, w, h = spec["height"], min(spec["w"], 100), spec["h"]
    clear = spec["clear"]
    hw = spec["trunk_hw"]
    lean = spec.get("lean", 0.0)
    top_y = max(5, FEET_Y - height)
    leader_top = int(top_y + h * 0.24)  # trunk climbs all the way into the heart of the crown!

    # ---- 1. Sinuous, gnarled main trunk(s) climbing up into the crown
    stems = [(-1, -2.2), (1, 2.2)] if spec.get("twin") else [(0, 0.0)]
    stem_spines = []
    centers = {}
    for si, (sd, x_base_off) in enumerate(stems):
        phase = rng.uniform(0.0, 5.0)
        stem_hw = hw * (0.76 if spec.get("twin") else 1.0)
        spine = {}
        for y in range(leader_top, FEET_Y + 1):
            t_up = (FEET_Y - y) / max(FEET_Y - leader_top, 1)
            curve = lean * (t_up ** 1.15) * (0.65 if spec.get("twin") else 1.0)
            curve += spec["twist"] * math.sin(t_up * 3.1 + phase) * 0.75
            if spec.get("twin"):
                curve += sd * (1.4 + 9.5 * (t_up ** 0.85))
            cx_f = FEET_X + x_base_off + curve
            flare = max(0.0, (y - (FEET_Y - 10)) * 0.72)
            cur_hw = stem_hw * ((1.0 - 0.72 * (t_up ** 1.08))) + flare
            spine[y] = (cx_f, cur_hw)
            if si == 0 or y not in centers:
                centers[y] = (int(round(cx_f)), cur_hw)
            # Below crown hem goes to trunk; inside upper crown goes to crown so canopy fade works cleanly!
            dest = trunk if y > FEET_Y - clear - int(h * 0.34) else crown
            for dx in range(-int(cur_hw) - 1, int(cur_hw) + 2):
                if abs(dx) > cur_hw:
                    continue
                x = int(round(cx_f)) + dx
                if not 3 <= x < CW - 3:
                    continue
                lit = 0.56 - 0.52 * dx / max(cur_hw, 1.0)
                ridge = (dx + int(noise(y // 5, si, seed + 2) % 3)) % 3 == 0
                v = lit * 4.1 + (noise(x, y, seed + 3) / 255.0 - 0.5) * 0.78 - (0.85 if ridge else 0.0)
                put(dest, x, y, BLOSSOM_BARK[int(max(0, min(4, v)))])
                if y > FEET_Y - 13 and dx < 1 and noise(x, y, seed + 8) > 158:
                    put(dest, x, y, sp.MOSS[1 if lit > 0.5 else 0])
        stem_spines.append(spine)

    sp._roots(trunk, BLOSSOM_BARK, hw, lights_t, spec, extras)
    if extras:
        for v in range(spec["veins"]):
            y0 = FEET_Y - int(clear * rng.uniform(0.18, 0.50))
            for k in range(int(clear * 0.55)):
                yy = y0 - k
                if yy not in centers or yy <= FEET_Y - clear - 4:
                    break
                cx_t, chw = centers[yy]
                xx = cx_t + int(round(math.sin(k * 0.42 + v * 1.9) * 1.2))
                if abs(xx - cx_t) < chw - 0.6 and trunk[yy][xx] is not None:
                    lights_t.pixel(trunk, xx, yy, VIO, VIO_L, 1)
        for f in range(spec["fungi"]):
            yy = FEET_Y - int(clear * rng.uniform(0.22, 0.85))
            if yy in centers:
                cx_t, chw = centers[yy]
                side = -1 if f % 2 else 1
                for i in range(4):
                    x = cx_t + side * (int(chw) + i)
                    put(trunk, x, yy + (1 if i > 2 else 0), SHELF[1])
                    put(trunk, x, yy + 1 + (1 if i > 2 else 0), SHELF[0])
                    lights_t.pixel(trunk, x, yy - (1 if 0 < i < 3 else 0), SHELF[2], TEAL_L, 1)
        if spec["hollow"] and (FEET_Y - int(clear * 0.52)) in centers:
            hy = FEET_Y - int(clear * 0.52)
            cx_t, _chw = centers[hy]
            for dy in range(-3, 4):
                for dx in range(-2, 3):
                    d = (dx / 2.1) ** 2 + (dy / 3.2) ** 2
                    if d <= 1.0:
                        put(trunk, cx_t + dx, hy + dy, BLOSSOM_BARK[0] if d < 0.58 else BLOSSOM_BARK[2])
            lights_t.pixel(trunk, cx_t, hy, POLLEN, POLLEN, 2)

    # ---- 2. Crooked side boughs branching at staggered heights along the trunk
    crown_cx = max(int(w * 0.5) + 5, min(CW - int(w * 0.5) - 5, FEET_X + int(round(lean * 0.65))))
    bough_pads = []
    exposed_elbows = []
    for bi, (att_t, dx_f, y_f, wf, hf) in enumerate(spec["boughs"]):
        bx = max(10.0, min(CW - 11.0, crown_cx + dx_f * w * 0.90))
        by = max(9.0, top_y + y_f * h)
        pw = max(10.5, w * wf * 0.5)
        ph = max(7.5, h * hf * 0.5)
        bough_pads.append((bx, by, pw, ph, bi))

        spine = stem_spines[(0 if dx_f < 0 else 1) if spec.get("twin") else 0]
        ay = int(round(FEET_Y - att_t * (FEET_Y - leader_top)))
        ay = max(leader_top + 2, min(FEET_Y - max(10, int(clear * 0.72)), ay))
        ax, ahw = spine.get(ay, (float(FEET_X), hw * 0.5))
        # Gnarled S-elbow: arches slightly outward & up, then settles onto the bough shelf
        ctrl_x = ax + (bx - ax) * 0.58 + rng.uniform(-2.5, 2.5)
        ctrl_y = min(ay, by) - rng.uniform(1.5, 5.0) if by < ay else (ay + by) * 0.5 - 3.0
        pts = bezier((ax, ay), (ctrl_x, ctrl_y), (bx, by + ph * 0.12), n=26)
        r_start = max(1.1, min(ahw * 0.72, hw * 0.44))
        _draw_branch_curve(trunk, pts[:7], r_start, max(0.9, r_start * 0.72), BLOSSOM_BARK)
        _draw_branch_curve(crown, pts[5:], max(1.0, r_start * 0.75), 0.65, BLOSSOM_BARK)
        exposed_elbows.append(pts[6:16])

    # ---- 3. Rich meadow-teal foliage clusters framing every bough (full & lush when picked!)
    leaf_lobes = []
    for bx, by, pw, ph, bi in bough_pads:
        n_leaf = max(7 if picked else 5, int(pw * ph / (14 if picked else 22)))
        for _ in range(n_leaf):
            a = rng.uniform(0.0, math.tau)
            r = rng.random() ** 0.65
            lx = max(6.0, min(CW - 7.0, bx + math.cos(a) * pw * r * (0.96 if picked else 0.90)))
            ly = max(6.0, by + (0.04 if picked else 0.14) * ph + math.sin(a) * ph * r * 0.82)
            sz = rng.uniform(2.8, 5.0) * (1.12 if picked else 0.94)
            leaf_lobes.append((lx, ly, sz * 1.20, sz * 0.86, -4.0 - bi * 0.4))
    leaf_grid = grid()
    lobes_shade(leaf_grid, leaf_lobes, BLOSSOM_LEAF, seed + 5, -0.14 if picked else -0.24)
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            if leaf_grid[y][x] is not None:
                crown[y][x] = leaf_grid[y][x]

    # ---- 4. Sculpted, terraced blossom clouds with layered depth & glimpsed dark wood
    if not picked:
        bloom_lobes = []
        for bx, by, pw, ph, bi in bough_pads:
            # Soft core cushion per shelf so each bough reads as a unified cloud-tier (not scattered dots)
            bloom_lobes.append((bx, by, pw * 0.68, ph * 0.56, -8.0 - bi * 1.1))
            n_clumps = max(9, int(pw * ph / 12))
            for k in range(n_clumps):
                a = rng.uniform(0.0, math.tau)
                r = rng.random() ** 0.62
                lx = max(6.0, min(CW - 7.0, bx + math.cos(a) * pw * r))
                ly = max(6.0, by + math.sin(a) * ph * r * (0.90 if math.sin(a) < 0 else 0.72))
                sz = rng.uniform(2.8, 5.6) * (0.78 + 0.22 * w / 100.0)
                depth_bias = -bi * 1.1 + (2.6 if math.sin(a) < -0.12 else -0.8) + (k % 3) * 0.35
                bloom_lobes.append((lx, ly, sz * 1.24, sz * 0.86, depth_bias))
            for side in (-1, 1):
                ox = max(6.0, min(CW - 7.0, bx + side * (pw * 0.94 + rng.uniform(0.5, 2.2))))
                oy = max(6.0, by + rng.uniform(-1.0, 2.5))
                bloom_lobes.append((ox, oy, rng.uniform(2.4, 3.6), rng.uniform(1.9, 2.8), 2.5))

        bloom_grid = grid()
        lobes_shade(bloom_grid, bloom_lobes, bloom_ramp, seed + 1, -0.17)
        for y in range(2, CH - 2):
            for x in range(2, CW - 2):
                if bloom_grid[y][x] is not None:
                    crown[y][x] = bloom_grid[y][x]

        # Subtle glimpses of dark crooked branch elbows peeking between shadow pockets
        for seg in exposed_elbows:
            for k, (fx, fy) in enumerate(seg[:6]):
                ix, iy = int(round(fx)), int(round(fy))
                if 5 <= ix < CW - 5 and 5 <= iy < CH - 5 and crown[iy][ix] in (None, bloom_ramp[0], bloom_ramp[1], BLOSSOM_LEAF[0], BLOSSOM_LEAF[1]):
                    put(crown, ix, iy, BLOSSOM_BARK[2 if k % 2 else 1])
                    put(crown, ix, iy + 1, BLOSSOM_BARK[0])
    else:
        # Picked state: lush leafy crooked boughs with small clusters of shy unpicked buds
        shy_lobes = []
        for bx, by, pw, ph, _bi in bough_pads:
            for _ in range(2):
                lx = max(6.0, min(CW - 7.0, bx + rng.uniform(-pw * 0.55, pw * 0.55)))
                ly = max(6.0, by + rng.uniform(-ph * 0.38, ph * 0.25))
                shy_lobes.append((lx, ly, rng.uniform(1.9, 2.8), rng.uniform(1.6, 2.3), 4.0))
        shy_grid = grid()
        lobes_shade(shy_grid, shy_lobes, bloom_ramp, seed + 19, -0.08)
        for y in range(2, CH - 2):
            for x in range(2, CW - 2):
                if shy_grid[y][x] is not None:
                    crown[y][x] = shy_grid[y][x]

    # ---- 5. Top-left sunlit contours & cool twilight bounce on right shadow edges
    active_ramps = (bloom_ramp, BLOSSOM_LEAF)
    for y in range(2, CH - 2):
        for x in range(2, CW - 2):
            c = crown[y][x]
            if c is None:
                continue
            for rmp in active_ramps:
                if c in rmp:
                    k = rmp.index(c)
                    top_idx = len(rmp) - 1
                    if crown[y - 1][x] is None and k < top_idx:
                        crown[y][x] = rmp[min(k + 2, top_idx)]
                    elif crown[y][x - 1] is None and k < top_idx - 1:
                        crown[y][x] = rmp[k + 1]
                    elif crown[y][x + 1] is None and rmp is BLOSSOM_LEAF and noise(x, y, seed + 9) > 95 and 1 <= k <= 3:
                        crown[y][x] = RIM[int(noise(x, y, seed + 10) > 155)]
                    elif crown[y][x + 1] is None and rmp is bloom_ramp and noise(x, y, seed + 11) > 150 and 1 <= k <= 2:
                        crown[y][x] = hexc("5a588e")
                    break

    # ---- 6. Hanging blossom racemes / leaf tassels & gentle night bioluminescence
    if not picked:
        bloom_pts = [(x, y) for y in range(4, CH - 6) for x in range(4, CW - 4) if crown[y][x] in bloom_ramp[2:6]]
        for _ in range(max(5, len(bloom_pts) // 26)):
            if not bloom_pts:
                break
            px_x, px_y = bloom_pts[rng.randrange(len(bloom_pts))]
            idx = bloom_ramp.index(crown[px_y][px_x])
            crown[px_y][px_x] = bloom_ramp[min(idx + 2, 6)]
            if crown[px_y][px_x + 1] in bloom_ramp:
                crown[px_y][px_x + 1] = bloom_ramp[min(idx + 1, 5)]

        hems = [
            (x, y)
            for y in range(8, FEET_Y - 10)
            for x in range(6, CW - 6)
            if crown[y][x] in bloom_ramp[:5] and crown[y + 1][x] is None and trunk[y + 1][x] is None
        ]
        if hems and spec.get("racemes", 0) > 0:
            for r_i in range(spec["racemes"]):
                hx, hy = hems[rng.randrange(len(hems))]
                ln = rng.randint(2, 6)
                for k in range(1, ln + 1):
                    if hy + k >= FEET_Y - 6:
                        break
                    tone = bloom_ramp[4 if k == ln else (3 if k % 2 else 2)]
                    put(crown, hx + (1 if k > 3 and r_i % 2 else 0), hy + k, tone, over=False)
                if extras and r_i % 3 == 0 and hy + ln < FEET_Y - 6:
                    lights_c.pixel(crown, hx, hy + ln, bloom_ramp[5], PETAL_GLOW[pal_idx], 1)

        if extras:
            all_pts = [(x, y) for y in range(3, CH - 3) for x in range(3, CW - 3) if crown[y][x] in bloom_ramp[3:]]
            for x, y in all_pts:
                k = bloom_ramp.index(crown[y][x])
                glow_c[y][x] = (*bloom_ramp[min(k + 1, 6)][:3], 78 if k >= 5 else (48 if k == 4 else 24))
            for _ in range(5 + int(w / 9)):
                if not all_pts:
                    break
                x, y = all_pts[rng.randrange(len(all_pts))]
                lights_c.pixel(crown, x, y, bloom_ramp[6], PETAL_GLOW[pal_idx], 1)
            for _ in range(3 + int(w / 20)):
                if not all_pts:
                    break
                x, y = all_pts[rng.randrange(len(all_pts))]
                lights_c.pixel(crown, x, y, POLLEN, POLLEN, 1)
    else:
        # Hanging leafy shoots on picked boughs so the picked canopy feels organic too
        leaf_hems = [
            (x, y)
            for y in range(8, FEET_Y - 10)
            for x in range(6, CW - 6)
            if crown[y][x] in BLOSSOM_LEAF[:4] and crown[y + 1][x] is None and trunk[y + 1][x] is None
        ]
        for r_i in range(min(len(leaf_hems), spec.get("racemes", 0) // 2)):
            hx, hy = leaf_hems[rng.randrange(len(leaf_hems))]
            for k in range(1, rng.randint(2, 4) + 1):
                if hy + k < FEET_Y - 6:
                    put(crown, hx, hy + k, BLOSSOM_LEAF[3 if k == 3 else 2], over=False)
        if extras:
            leaf_pts = [(x, y) for y in range(4, CH - 4) for x in range(4, CW - 4) if crown[y][x] in BLOSSOM_LEAF[2:]]
            for _ in range(4):
                if leaf_pts:
                    x, y = leaf_pts[rng.randrange(len(leaf_pts))]
                    lights_c.pixel(crown, x, y, TEAL, TEAL_L, 1)

    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}
