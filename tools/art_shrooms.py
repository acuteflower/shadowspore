#!/usr/bin/env python3
"""Two woodland mushrooms for the meadow's shade (stdlib only), frames 40x34 (feet at (20, 31)):
  assets/props/ember_morel.png      Glutmorchel: 5 stands of honeycomb-capped morels x 2 rows (whole, picked)
  assets/props/moon_parasol.png     Mondschirm: 5 stands of tall pleated parasol mushrooms x 2 rows (whole, picked)
  every sheet has a `_glow` twin with only the emissive pixels
  assets/items/ember_morel.png, moon_parasol.png   icons 16x16
Harmonized with Shadowspore's structured cel + Bayer shading, cool indigo-violet deep shadows,
and adaptive material-tinted 1px outlines (never harsh pure black around pale parasol caps)."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, Glow, blade, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, check_icon, clamp  # noqa: E402
from art_flora import LEAFW, finish, ramp  # noqa: E402
from gen_art import ROOT, hexc, outline_pass, write_png  # noqa: E402

COLS = 5
MOREL = ramp("261214", "52261c", "864826", "bc7636", "e6a85a", "ffd68c")
MSTEM = ramp("584c44", "928472", "c8ba9c", "efe6cc")
EMBER_PIT, EMBER_HOT = hexc("ff8a38"), hexc("ffd478")

PARA = ramp("342e62", "5c5698", "908ac4", "c6c2e8", "f2f0fc")
PGILL = ramp("24204c", "444076", "7472aa")
PSTEM = ramp("4c487c", "7c78ae", "b4b0d8", "e6e4f6")
PGLOW = hexc("9af0e4")
PLILAC = hexc("d8ccff")

MORELS = [
    {"caps": [(20, 10, 6.2, 0.0)], "spread": 6},
    {"caps": [(15, 12, 6.8, -0.8), (25, 8, 5.2, 1.0)], "spread": 10},
    {"caps": [(13, 9, 5.4, -1.0), (20, 13, 7.0, 0.3), (27, 8, 5.0, 1.0)], "spread": 12},
    {"caps": [(17, 14, 5.8, -0.9), (24, 11, 5.2, 1.1)], "spread": 9},  # tall slender torch-morels
    {"caps": [(10, 8, 4.8, -1.2), (17, 13, 6.8, -0.3), (24, 10, 5.8, 0.8), (30, 7, 4.4, 1.2)], "spread": 14},
]

PARASOLS = [
    {"caps": [(20, 21, 14, 0.4)], "spread": 7},
    {"caps": [(15, 20, 13, -1.2), (26, 13, 9, 1.2)], "spread": 10},
    {"caps": [(11, 14, 10, -1.3), (20, 22, 13, 0.3), (29, 11, 8, 1.2)], "spread": 13},
    {"caps": [(17, 21, 14, -1.5), (26, 11, 5, 0.8)], "spread": 10, "bud": True},  # sweeping parasol + young drumstick bud
    {"caps": [(10, 12, 8, -1.3), (17, 21, 12, -0.5), (24, 17, 11, 0.8), (30, 10, 7, 1.2)], "spread": 14},
]


def stem_curved(px, cx, y_top, y_bot, w_base, lean, pal):
    h = max(1, y_bot - y_top)
    for y in range(int(y_bot), int(y_top) - 1, -1):
        t = (y_bot - y) / h
        xc = cx + lean * (t * t)
        hw = w_base * (1.12 - 0.28 * t)
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            lit = 0.58 - 0.50 * dx / max(hw, 0.75) - (0.25 if t > 0.82 else 0.0)
            lit += (BAYER[y % 4][int(abs(xc + dx)) % 4] / 16.0 - 0.5) * 0.22
            put(px, int(round(xc + dx)), y, pal[int(clamp(lit * len(pal), 0, len(pal) - 1))])


def morel(px, glow, cx, h, cap_w, lean, seed):
    total_h = h + 9
    cap_h = int(total_h * 0.60)
    stem_top = GROUND - int(total_h * 0.44)
    stem_curved(px, cx, stem_top, GROUND, 1.75 if h >= 10 else 1.35, lean * 0.6, MSTEM)
    cap_cx = cx + lean * 0.8
    cap_top = max(3, stem_top - cap_h + 2)
    # Tapered ovoid-conical honeycomb cap with staggered organic pits & sculpted 3D ridges
    for y in range(cap_top, stem_top + 2):
        t = (y - cap_top) / max(cap_h, 1)
        # Ovoid-conical profile: narrow rounded apex, widest at t=0.68, tucked rim at t=1.0
        profile = math.sin(min(1.0, max(0.05, t ** 0.78)) * math.pi * 0.86)
        half = (cap_w + 1.6) * 0.5 * (0.18 + 0.86 * profile)
        for x in range(int(cap_cx - half) - 1, int(cap_cx + half) + 2):
            dx = (x + 0.5 - cap_cx) / max(half, 0.9)
            if abs(dx) > 1.0 or not (2 <= x < FW - 2):
                continue
            lit = 0.56 - 0.46 * dx - 0.22 * (t - 0.35)
            # Staggered cellular honeycomb pattern (offset rows + subtle wave so it never looks like a stiff grid)
            row_id = (y - cap_top) // 2
            cell_x = (x + (row_id % 2) * 2 + seed) % 3
            cell_y = (y - cap_top + (x % 2)) % 3
            is_pit = (cell_x == 1 and cell_y == 1 and 0.14 < t < 0.92 and abs(dx) < 0.82)
            if is_pit:
                put(px, x, y, MOREL[0])
                if (x + y + seed) % 2 == 0:
                    glow.emit(px, x, y, MOREL[1], EMBER_PIT, 0)
            else:
                ridge = 0.32 if (cell_x == 0 or cell_y == 0) else -0.08
                idx = int(clamp((lit + ridge) * 5.2 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.5, 1, 5))
                put(px, x, y, MOREL[idx])
    glow.emit(px, int(round(cap_cx)), cap_top + 1, MOREL[5], EMBER_HOT, 1)


def make_morel(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(5 + len(spec["caps"])):
        blade(px, 20 + rng.uniform(-spec["spread"] * 0.85, spec["spread"] * 0.85), GROUND, rng.uniform(1.5, 4.2), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2, 3)), seed)
    for cx, h, w, lean in sorted(spec["caps"], key=lambda c: c[1]):
        if picked:
            stem_curved(px, cx, GROUND - 3, GROUND, 1.25, lean * 0.2, MSTEM)
            put(px, int(round(cx)), GROUND - 4, MSTEM[3])
        else:
            morel(px, glow, cx, h, w, lean, seed + int(cx))
    return finish(px, spec["spread"], seed), glow.done()


def parasol(px, glow, cx, h, w, lean, is_bud=False):
    top = max(5, GROUND - h)
    # Graceful S-curved slender stem + skirt annulus ring
    pts = bezier((cx, GROUND), (cx - lean * 0.8, GROUND - h * 0.48), (cx + lean * 1.5, top + 1), n=max(12, h * 2))
    for x, y in pts:
        xi, yi = int(clamp(round(x), 3, FW - 4)), int(clamp(round(y), 3, GROUND))
        put(px, xi - 1, yi, PSTEM[3])
        put(px, xi, yi, PSTEM[2])
        put(px, xi + 1, yi, PSTEM[0])
    ring_pt = pts[int(len(pts) * 0.62)]
    rx_i, ry_i = int(round(ring_pt[0])), int(round(ring_pt[1]))
    for dx in (-2, -1, 0, 1, 2):
        put(px, clamp(rx_i + dx, 3, FW - 4), ry_i + (1 if abs(dx) == 2 else 0), PSTEM[3 if dx <= 0 else 1])

    ccx = clamp(pts[-1][0], 4 + w * 0.5, FW - 5 - w * 0.5)
    if is_bud:
        # Unopened ovoid drumstick parasol bud
        for dy in range(-4, 3):
            hw = 2.6 * math.sin(max(0.1, (dy + 4.5) / 7.5) * math.pi)
            for dx in range(-int(hw) - 1, int(hw) + 2):
                if abs(dx) <= hw:
                    tone = 4 if dx < -0.5 and dy < 0 else (3 if dx <= 0 else (2 if dx < 1 else 1))
                    put(px, int(round(ccx + dx)), top + dy, PARA[tone])
        glow.emit(px, int(round(ccx)), top - 3, PARA[4], PLILAC, 1)
        return

    # Bioluminescent pleated gill underside
    half_w = w * 0.5
    for dx in range(-int(half_w), int(half_w) + 1):
        edge = math.sqrt(max(0.0, 1.0 - (dx / max(half_w, 1.0)) ** 2))
        y1 = top + int(w * 0.14 * edge) + 1
        put(px, int(round(ccx)) + dx, y1, PGILL[(abs(dx)) % 3])
        if abs(dx) < half_w - 1:
            put(px, int(round(ccx)) + dx, y1 + 1, PGILL[(abs(dx) + 1) % 2])

    # Wide shallow conical-bell cap with clean radial pleats & prominent central umbo
    cap_ry = max(2.8, w * 0.27)
    for y in range(int(top - cap_ry) - 1, int(top + w * 0.18) + 2):
        for x in range(int(ccx - half_w) - 1, int(ccx + half_w) + 2):
            dx = (x + 0.5 - ccx) / max(half_w, 1.0)
            dy = (y + 0.5 - top) / cap_ry
            d = dx * dx + dy * dy
            if d > 1.0 or dy > 0.72 - 0.38 * dx * dx or not (2 <= x < FW - 2 and 2 <= y < GROUND - 2):
                continue
            ang = math.atan2(dy + 0.3, dx)
            pleat = 0.10 * math.cos(ang * 12.0)
            lit = 0.58 - 0.40 * dx - 0.45 * (dy + 0.32) + pleat + (1.0 - d) * 0.18
            lit += (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.22
            put(px, x, y, PARA[int(clamp(lit * len(PARA), 0, len(PARA) - 1))])
    # Sculpted darker lilac umbo crown at apex with crisp top-left gleam
    umbo_y = max(2, int(round(top - cap_ry * 0.72)))
    put(px, int(round(ccx)), umbo_y, PARA[1])
    put(px, int(round(ccx)) + 1, umbo_y, PARA[0])
    put(px, int(round(ccx)) - 1, umbo_y, PARA[4])
    # Aqua-teal spore glow along gill rim + soft apex gleam
    for k in range(3):
        gx = int(clamp(round(ccx - half_w + 1.5 + k * (w - 3) / 2.0), 3, FW - 4))
        gy = min(GROUND - 4, top + 2)
        glow.emit(px, gx, gy, None, PGLOW, 0)
    glow.emit(px, int(round(ccx)) - 1, umbo_y, PARA[4], PLILAC, 1)


def make_parasol(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(4 + len(spec["caps"])):
        blade(px, 20 + rng.uniform(-spec["spread"] * 0.85, spec["spread"] * 0.85), GROUND, rng.uniform(1.5, 4.2), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2, 3)), seed)
    caps_sorted = sorted(enumerate(spec["caps"]), key=lambda item: item[1][1])
    for idx, (cx, h, w, lean) in caps_sorted:
        if picked:
            stem_curved(px, cx, GROUND - 4, GROUND, 1.1, lean * 0.2, PSTEM)
            put(px, int(round(cx)) - 1, GROUND - 3, PSTEM[3])
            put(px, int(round(cx)) + 1, GROUND - 3, PSTEM[2])
        else:
            is_bud = bool(spec.get("bud") and idx == 1)
            parasol(px, glow, cx, h, w, lean, is_bud=is_bud)
    return finish(px, spec["spread"], seed), glow.done()


def i_morel(px, g):
    for y in range(9, 14):
        for dx in (-1, 0, 1):
            px[y][8 + dx] = MSTEM[3 if dx < 0 else (2 if dx == 0 else 1)]
    for y in range(2, 10):
        t = (y - 2) / 7.0
        half = int(2.6 * (0.4 + 0.6 * math.sin(min(1, t) * 2.0)))
        for dx in range(-half, half + 1):
            lx, ly = (dx + 8 + (1 if (y // 2) % 2 else 0)) % 3, y % 3
            px[y][8 + dx] = MOREL[0] if (lx == 1 and ly == 1) else MOREL[4 if dx < 0 else 2]
    px[3][8] = EMBER_HOT


def i_parasol(px, g):
    for y in range(6, 14):
        px[y][8] = PSTEM[2]
    px[9][7], px[9][9] = PSTEM[3], PSTEM[3]
    for y in range(2, 7):
        half = {2: 2, 3: 4, 4: 5, 5: 6, 6: 6}[y]
        for dx in range(-half, half + 1):
            px[y][8 + dx] = PARA[3 if dx < 0 else (2 if dx == 0 else 1)] if y < 6 else PGILL[(dx + 8) % 3]
    px[3][7], px[2][8] = PARA[4], PARA[4]


def main():
    props, items = ROOT / "props", ROOT / "items"
    sheets = {
        "ember_morel": [make_morel(s, 1800 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(MORELS)],
        "moon_parasol": [make_parasol(s, 1900 + i * 19, picked=r) for r in (False, True) for i, s in enumerate(PARASOLS)],
    }
    bad = []
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            for layer in (base, glow):
                pts = [(x, y) for y, row in enumerate(layer) for x, c in enumerate(row) if c[3]]
                if pts and not (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2):
                    bad.append("%s frame %d: top %d, x %d..%d" % (name, i, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))
    assert not bad, "cut off at the frame edge:\n" + "\n".join(bad)
    for name, frames in sheets.items():
        write_png(props / (name + ".png"), FW * COLS, FH * 2, sheet([f[0] for f in frames], COLS, 2))
        write_png(props / (name + "_glow.png"), FW * COLS, FH * 2, sheet([f[1] for f in frames], COLS, 2))
    for name, draw in (("ember_morel", i_morel), ("moon_parasol", i_parasol)):
        px = blank(16, 16)
        draw(px, None)
        check_icon(name, px)
        write_png(items / (name + ".png"), 16, 16, outline_pass(px, hexc("1b1a2e")))
    print("morel and parasol (5 variants each) written")


if __name__ == "__main__":
    main()
