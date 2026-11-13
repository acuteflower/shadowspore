#!/usr/bin/env python3
"""Procedural oasis water & shore detail sheets for Sonnenquarz-Öde (stdlib only).

Outputs (6 cols x N rows of 32x32 cells):
  assets/water/oasis_water_flora.png       (192x192, 6x6):
    row 0, 1: Sonnen-Schwimmrosetten (desert floating water-lettuce rosettes, turquoise-gold heart)
    row 2, 3: Sternen-Wasserlotus (starry turquoise-cream oasis lotus pads + open blooms / buds)
    row 4, 5: Türkis-Quellbandgras (submerged oasis ribbon-grass, alpha <= 228)
  assets/water/oasis_water_flora_glow.png  (192x192, 6x6, unlit night glow overlay)

  assets/water/oasis_bank_details.png      (192x288, 6x9):
    row 0: Zwerg-Papyrus (miniature feathery umbel stalks)
    row 1: Sonnenquarz-Uferkiesel (warm sandstone & turquoise quartz shore pebbles)
    row 2: Salzquarz-Uferkruste (crystalline salt-quartz shore slabs — ZERO driftwood)
    row 3: Oasen-Goldtau (golden-dew shore succulents with warm night glow)
    row 4: Fächerpalmen-Schössling (young sprouting fan-palm tufts on bank)
    row 5: Quellquarz im Uferschaum (translucent crystal clusters in shallow shore foam)
    row 6: Sternen-Binsen (slender star-tipped shore rushes with cyan night glow)
    row 7: Quell-Kristallrose (no outline, glowing crystal water-rosette)
    row 8: Sonnen-Quellfaden (no outline, glowing golden-teal floating filament)
  assets/water/oasis_bank_details_glow.png (192x288, 6x9, unlit night glow overlay)

Usage:
  python3 tools/art_oasis_water.py [optional_preview_path.png]
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import Glow  # noqa: E402
from art_bush import BAYER, bezier, blank, clamp  # noqa: E402
from gen_art import ROOT, hexc, noise, write_png  # noqa: E402

CELL = 32
COLS = 6


def _put(px, x, y, c):
    if 0 <= x < CELL and 0 <= y < CELL:
        px[y][x] = c


def _pack_sheet(frames, cols, rows):
    out = blank(cols * CELL, rows * CELL)
    for idx, frame in enumerate(frames):
        ox = (idx % cols) * CELL
        oy = (idx // cols) * CELL
        for y in range(CELL):
            for x in range(CELL):
                c = frame[y][x]
                if c[3] > 0:
                    out[oy + y][ox + x] = c
    return out

# Harmonized desert-oasis palettes (3/4 top-left light, cool indigo-teal & warm terracotta shadows, never #000000)
INK_LEAF = hexc("132628")
INK_STONE = hexc("241b2a")
INK_SALT = hexc("26344a")

LEAF = [hexc(c) for c in ("163632", "24584c", "3a8264", "62b47c", "94dc98", "caf2b8")]
TEAL_LEAF = [hexc(c) for c in ("142f36", "1e4c52", "2e7474", "4ea89e", "86dcd0", "c8f8f0")]
SUB_GRASS = [hexc(c) for c in ("14444a", "1e666a", "2e9492", "54c8bc", "94ede0")]

LOTUS_PETAL = [hexc(c) for c in ("347e8a", "5cc2c2", "96ece8", "d6fcf8", "ffffff")]
GOLD_DEW = [hexc(c) for c in ("a4601e", "dc8c2c", "ffc44c", "fff0a8")]

SAND_PEBBLE = [hexc(c) for c in ("462c32", "72483c", "a2704c", "cfa068", "eed29c")]
SALT_CRUST = [hexc(c) for c in ("587492", "84acc4", "b4dae6", "def4fa", "f8feff")]
QUARTZ = [hexc(c) for c in ("365070", "5684a4", "86c0d8", "beeff8", "ebffff")]
FOAM = [hexc(c) for c in ("78bec4", "b4eaec", "e8fcfc")]

GLOW_GOLD = hexc("ffc858")
GLOW_GOLD_HOT = hexc("fff4ba")
GLOW_CYAN = hexc("7cf0ec")
GLOW_CYAN_HOT = hexc("ecffff")


def _cell_outline(px, ink):
    """1px tinted outline inside a 32x32 frame without clobbering existing opaque pixels."""
    w, h = len(px[0]), len(px)
    marks = []
    for y in range(h):
        for x in range(w):
            if px[y][x][3] > 0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= 200:
                    marks.append((x, y))
                    break
    for x, y in marks:
        px[y][x] = ink


def _disk(px, cx, cy, rx, ry, pal, seed, flip_light=False, alpha=255):
    for dy in range(-int(math.ceil(ry)) - 1, int(math.ceil(ry)) + 2):
        for dx in range(-int(math.ceil(rx)) - 1, int(math.ceil(rx)) + 2):
            u = dx / max(rx, 0.5)
            v = dy / max(ry, 0.5)
            if u * u + v * v > 1.0:
                continue
            x, y = int(round(cx + dx)), int(round(cy + dy))
            if not (0 <= x < CELL and 0 <= y < CELL):
                continue
            lit = 0.56 - 0.36 * u - 0.38 * v
            if flip_light:
                lit = 0.48 - 0.30 * u - 0.30 * v
            dither = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.36
            idx = int(clamp(lit * (len(pal) - 0.35) + dither, 0, len(pal) - 1))
            c = pal[idx]
            px[y][x] = (c[0], c[1], c[2], alpha)


def _draw_water_rosette(variant: int, alt_row: bool):
    rng = random.Random(1100 + variant * 37 + (99 if alt_row else 0))
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx, cy = 16 + rng.randint(-1, 1), 16 + rng.randint(-1, 1)
    n_leaves = 6 if not alt_row else 7
    r_main = 6.2 + (variant % 3) * 0.9

    # Optional smaller satellite rosette on odd variants
    centers = [(cx, cy, r_main, n_leaves)]
    if variant % 2 == 1:
        sx = cx + (-7 if variant < 3 else 7)
        sy = cy + (4 if alt_row else -4)
        centers.append((sx, sy, 3.6, 5))

    for idx_c, (ox, oy, rad, count) in enumerate(centers):
        # Soft turquoise water ripple under floating rosette
        for a_i in range(14):
            ang = a_i * math.tau / 14.0
            rx = int(round(ox + math.cos(ang) * (rad + 2.2)))
            ry = int(round(oy + math.sin(ang) * (rad * 0.72 + 1.5)))
            if 1 <= rx < CELL - 1 and 1 <= ry < CELL - 1 and (a_i + variant) % 3 != 0:
                px[ry][rx] = (*FOAM[0][:3], 150)

        rot0 = rng.uniform(0.0, math.tau)
        for li in range(count):
            ang = rot0 + li * math.tau / count
            lx = ox + math.cos(ang) * (rad * 0.56)
            ly = oy + math.sin(ang) * (rad * 0.42)
            _disk(px, lx, ly, rad * 0.44, rad * 0.36, LEAF if not alt_row else TEAL_LEAF, 200 + li + idx_c)
        # Central bright golden-turquoise water heart
        _put(px, ox, oy, GOLD_DEW[2])
        if idx_c == 0:
            _put(px, ox - 1, oy, GOLD_DEW[3])
            glow.emit(px, ox, oy, GOLD_DEW[3], GLOW_GOLD_HOT, 1)
            glow.emit(px, ox + 1, oy, GOLD_DEW[2], GLOW_GOLD, 0)
        else:
            glow.emit(px, ox, oy, GOLD_DEW[2], GLOW_GOLD, 0)

    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_water_lotus(variant: int, is_bud_row: bool):
    rng = random.Random(2200 + variant * 53 + (131 if is_bud_row else 0))
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx, cy = 16 + rng.randint(-1, 1), 16 + rng.randint(-1, 1)

    # Jade lotus pad(s) with notched cleft
    pads = [(cx, cy + 1, 7.6 + (variant % 3) * 0.8, 5.4)]
    if variant in (1, 3, 5):
        pads.append((cx + (-6 if variant != 3 else 6), cy - 4, 4.4, 3.2))

    notch_ang = rng.uniform(-0.8, 0.8) + 0.6
    for pi, (px0, py0, rx, ry) in enumerate(pads):
        for dy in range(-int(ry) - 1, int(ry) + 2):
            for dx in range(-int(rx) - 1, int(rx) + 2):
                u, v = dx / rx, dy / ry
                if u * u + v * v > 1.0:
                    continue
                ang = math.atan2(v, u)
                if pi == 0 and abs(ang - notch_ang) < 0.28 and math.hypot(u, v) > 0.25:
                    continue
                x, y = int(round(px0 + dx)), int(round(py0 + dy))
                if 1 <= x < CELL - 1 and 1 <= y < CELL - 1:
                    lit = 0.56 - 0.34 * u - 0.38 * v
                    idx = int(clamp(lit * 4.8 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.4, 0, 5))
                    px[y][x] = TEAL_LEAF[idx]

    # Blossom (row 2 open star-lotus, row 3 closed bud / twin buds)
    bx, by = cx, cy - 1
    if is_bud_row:
        bud_pts = [(bx, by)] if variant % 2 == 0 else [(bx - 3, by), (bx + 4, by + 1)]
        for bi, (ux, uy) in enumerate(bud_pts):
            for dx, dy, sh in ((0, -2, 3), (-1, -1, 2), (1, -1, 1), (0, -1, 4), (-1, 0, 1), (0, 0, 2), (1, 0, 0)):
                _put(px, ux + dx, uy + dy, LOTUS_PETAL[sh])
            glow.emit(px, ux, uy - 1, LOTUS_PETAL[4], GLOW_CYAN_HOT, 1 if bi == 0 else 0)
    else:
        # 8-pointed desert water-star lotus
        for dx, dy, sh in (
            (0, -3, 3), (-3, -1, 2), (3, -1, 1), (-3, 1, 1), (3, 1, 0), (0, 3, 1),
            (-2, -2, 3), (2, -2, 2), (-2, 2, 1), (2, 2, 0),
            (-1, -1, 4), (1, -1, 3), (-1, 1, 2), (1, 1, 1),
            (0, -2, 4), (-2, 0, 3), (2, 0, 2), (0, 2, 2),
        ):
            _put(px, bx + dx, by + dy, LOTUS_PETAL[sh])
        _put(px, bx - 1, by, GOLD_DEW[3])
        _put(px, bx, by, GOLD_DEW[2])
        glow.emit(px, bx, by - 1, GOLD_DEW[3], GLOW_GOLD_HOT, 1)
        glow.emit(px, bx, by, GOLD_DEW[2], GLOW_GOLD, 0)
        glow.emit(px, bx - 1, by - 1, LOTUS_PETAL[4], GLOW_CYAN, 0)

    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_submerged_ribbon(variant: int, row_alt: bool):
    rng = random.Random(3300 + variant * 41 + (77 if row_alt else 0))
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    strands = 4 + (variant % 3)
    base_y = 24 + (variant % 2)
    alpha = 224  # submerged translucency

    for si in range(strands):
        ox = 9 + int(round((si / max(strands - 1, 1)) * 14)) + rng.randint(-1, 1)
        h = rng.randint(10, 17)
        sway = rng.uniform(-5.5, 5.5) + (1.8 if variant % 2 == 0 else -1.8)
        pts = bezier((ox, base_y), (ox + sway * 0.45, base_y - h * 0.52), (ox + sway, max(5, base_y - h)), n=16)
        for j, (sx, sy) in enumerate(pts):
            t = j / max(len(pts) - 1, 1)
            c = SUB_GRASS[min(4, int(t * 4.2))]
            ix, iy = int(round(sx)), int(round(sy))
            if 1 <= ix < CELL - 1 and 1 <= iy < CELL - 1:
                px[iy][ix] = (c[0], c[1], c[2], alpha)
                if t < 0.65 and j % 2 == 0 and 1 <= ix - 1:
                    c2 = SUB_GRASS[max(0, int(t * 3.0))]
                    px[iy][ix - 1] = (c2[0], c2[1], c2[2], alpha - 24)
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        if si % 2 == 0 and 2 <= tx < CELL - 2 and 2 <= ty < CELL - 2:
            glow.emit(px, tx, ty, (*SUB_GRASS[4][:3], alpha), GLOW_CYAN, 0)

    return px, glow.done()


def _draw_bank_papyrus(variant: int):
    rng = random.Random(4100 + variant * 29)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    stalks = 3 + (variant % 2)
    gy = 28
    for si in range(stalks):
        ox = 11 + int(round(si * (10.0 / max(stalks - 1, 1)))) + rng.randint(-1, 1)
        h = rng.randint(13, 19)
        lean = rng.uniform(-4.0, 4.0)
        pts = bezier((ox, gy), (ox + lean * 0.4, gy - h * 0.5), (ox + lean, max(5, gy - h)), n=14)
        for j, (sx, sy) in enumerate(pts):
            c = LEAF[min(4, 1 + (j * 3) // max(len(pts), 1))]
            _put(px, int(round(sx)), int(round(sy)), c)
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        # Feathery turquoise-jade papyrus umbel rays
        for rx, ry, ci in ((0, -2, 5), (-2, -1, 4), (2, -1, 3), (-3, 1, 3), (3, 1, 2), (0, -1, 4)):
            _put(px, tx + rx, ty + ry, TEAL_LEAF[ci])
        _put(px, tx, ty - 2, GLOW_CYAN)
    # Basal blades
    for dx in (-3, -1, 2, 4):
        _put(px, 16 + dx, gy, LEAF[2])
        _put(px, 16 + dx + (1 if dx > 0 else -1), gy - 2, LEAF[3])
    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_bank_pebbles(variant: int):
    rng = random.Random(4200 + variant * 31)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    count = 3 + (variant % 3)
    for pi in range(count):
        cx = 16 + rng.randint(-7, 7)
        cy = 23 + rng.randint(-3, 4)
        rx = rng.uniform(2.2, 4.2)
        ry = rng.uniform(1.6, 2.8)
        pal = QUARTZ if (pi == count - 1 and variant % 2 == 0) else SAND_PEBBLE
        _disk(px, cx, cy, rx, ry, pal, 500 + variant * 13 + pi)
        if pal is QUARTZ:
            _put(px, cx - 1, cy - 1, QUARTZ[4])
    _cell_outline(px, INK_STONE)
    return px, glow.done()


def _draw_bank_salt_quartz(variant: int):
    """Row 2: Crystalline Salzquarz-Uferkruste — mineral salt-quartz crust plates, ZERO wood."""
    rng = random.Random(4300 + variant * 37)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    # Flat stepped mineral crust shelf hugging shoreline
    slabs = [(16 + rng.randint(-2, 2), 25, 8.2, 3.0), (12 + rng.randint(-2, 1), 23, 4.4, 2.2)]
    if variant % 2 == 1:
        slabs.append((21, 23, 4.2, 2.1))
    for si, (cx, cy, rx, ry) in enumerate(slabs):
        _disk(px, cx, cy, rx, ry, SALT_CRUST, 700 + si + variant * 7)
    # Crisp protruding quartz-salt teeth catching top-left sun
    spires = 2 + (variant % 3)
    for sp in range(spires):
        sx = 12 + sp * 4 + rng.randint(-1, 1)
        sh = rng.randint(4, 7)
        for yy in range(sh):
            w = 1 if yy > sh - 3 else 2
            for dx in range(w):
                _put(px, sx + dx, 23 - yy, SALT_CRUST[min(4, 2 + yy // 2 + (1 if dx == 0 else 0))])
        _put(px, sx, 23 - sh + 1, SALT_CRUST[4])
    _cell_outline(px, INK_SALT)
    return px, glow.done()


def _draw_bank_golddew(variant: int):
    """Row 3: Oasen-Goldtau — desert succulent rosettes tipped with warm amber nectar dew (glow)."""
    rng = random.Random(4400 + variant * 43)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    tufts = 4 + (variant % 3)
    gy = 27
    for ti in range(tufts):
        ang = -1.2 + (ti / max(tufts - 1, 1)) * 2.4
        ox = 16 + int(round(math.sin(ang) * 5))
        dx = math.sin(ang) * 5.0
        dy = -rng.randint(7, 13)
        pts = bezier((ox, gy), (ox + dx * 0.4, gy + dy * 0.5), (ox + dx, gy + dy), n=12)
        for j, (sx, sy) in enumerate(pts):
            _put(px, int(round(sx)), int(round(sy)), TEAL_LEAF[min(4, 1 + j // 3)])
            if j < 7:
                _put(px, int(round(sx)) + 1, int(round(sy)), TEAL_LEAF[max(0, j // 3)])
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        _put(px, tx, ty, GOLD_DEW[2])
        glow.emit(px, tx, ty - 1, GOLD_DEW[3], GLOW_GOLD_HOT if ti % 2 == 0 else GLOW_GOLD, 1 if ti == tufts // 2 else 0)
    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_bank_palm_sprout(variant: int):
    """Row 4: Fächerpalmen-Schössling — miniature desert palm-frond sprout anchored on bank."""
    rng = random.Random(4500 + variant * 47)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    gy = 28
    # Short warm bark heel
    for yy in range(4):
        _put(px, 16, gy - yy, SAND_PEBBLE[1 if yy % 2 == 0 else 2])
        _put(px, 15, gy - yy, SAND_PEBBLE[2])
    fronds = [(-8, -7), (-5, -11), (0, -13), (5, -11), (8, -7)]
    if variant % 2 == 1:
        fronds.append((-3, -8))
    for fx, fy in fronds:
        ox, oy = 16, gy - 3
        tx, ty = ox + fx + rng.randint(-1, 1), oy + fy + rng.randint(-1, 1)
        pts = bezier((ox, oy), ((ox + tx) * 0.5, oy + fy * 0.85 - 2), (tx, ty), n=12)
        for j, (sx, sy) in enumerate(pts):
            c = LEAF[min(5, 2 + j // 3)]
            _put(px, int(round(sx)), int(round(sy)), c)
            if 3 <= j <= 9:
                _put(px, int(round(sx)), int(round(sy)) + 1, LEAF[max(1, 1 + j // 4)])
    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_bank_foam_quartz(variant: int):
    """Row 5: Quellquarz im Uferschaum — quartz crystals emerging in shallow oasis water foam."""
    rng = random.Random(4600 + variant * 53)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    # Translucent shore foam oval
    _disk(px, 16, 25, 8.0, 2.8, FOAM, 800 + variant, alpha=185)
    crystals = 3 + (variant % 2)
    for ci in range(crystals):
        cx = 11 + ci * 4 + rng.randint(-1, 1)
        h = rng.randint(6, 11)
        lean = -1 if ci == 0 else (1 if ci == crystals - 1 else 0)
        for yy in range(h):
            w = 3 if yy < h - 3 else (2 if yy < h - 1 else 1)
            for dx in range(w):
                col_i = min(4, 1 + yy // 2 + (1 if dx == 0 else 0))
                _put(px, cx + dx + (lean * yy) // 4, 24 - yy, QUARTZ[col_i])
    _cell_outline(px, INK_SALT)
    return px, glow.done()


def _draw_bank_star_rushes(variant: int):
    """Row 6: Sternen-Binsen — slender oasis shoreline rushes with bioluminescent cyan-gold tips."""
    rng = random.Random(4700 + variant * 59)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    gy = 28
    culms = 5 + (variant % 3)
    for ci in range(culms):
        ox = 10 + int(round(ci * (12.0 / max(culms - 1, 1)))) + rng.randint(-1, 1)
        h = rng.randint(12, 20)
        lean = rng.uniform(-3.5, 3.5)
        pts = bezier((ox, gy), (ox + lean * 0.4, gy - h * 0.5), (ox + lean, max(4, gy - h)), n=14)
        for j, (sx, sy) in enumerate(pts):
            _put(px, int(round(sx)), int(round(sy)), TEAL_LEAF[min(4, 1 + j // 3)])
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        if ci % 2 == 0:
            glow.emit(px, tx, ty, LOTUS_PETAL[3], GLOW_CYAN_HOT if ci == culms // 2 else GLOW_CYAN, 1 if ci == culms // 2 else 0)
            _put(px, tx, ty + 1, LOTUS_PETAL[2])
    _cell_outline(px, INK_LEAF)
    return px, glow.done()


def _draw_bank_crystal_rose(variant: int):
    """Row 7: Quell-Kristallrose (no outline, translucent shallow-water star rosette + glow)."""
    rng = random.Random(4800 + variant * 61)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx, cy = 16 + rng.randint(-2, 2), 18 + rng.randint(-2, 2)
    alpha = 210
    for dx, dy in ((0, -4), (-3, -2), (3, -2), (-4, 0), (4, 0), (-3, 2), (3, 2), (0, 4)):
        _put(px, cx + dx, cy + dy, (*QUARTZ[2][:3], alpha - 40))
    for dx, dy in ((0, -2), (-2, -1), (2, -1), (-2, 1), (2, 1), (0, 2), (-1, 0), (1, 0)):
        _put(px, cx + dx, cy + dy, (*QUARTZ[4][:3], alpha))
    glow.emit(px, cx, cy, (*GOLD_DEW[3][:3], 235), GLOW_CYAN_HOT, 1)
    glow.emit(px, cx, cy - 1, (*LOTUS_PETAL[4][:3], 225), GLOW_CYAN, 0)
    return px, glow.done()


def _draw_bank_sun_filament(variant: int):
    """Row 8: Sonnen-Quellfaden (no outline, delicate floating golden-cyan oasis filaments + glow)."""
    rng = random.Random(4900 + variant * 67)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx, cy = 16, 18
    for fi in range(3):
        ang = rng.uniform(0.0, math.tau) + fi * 1.9
        r = 5.0 + rng.uniform(1.0, 3.0)
        pts = bezier(
            (cx + math.cos(ang) * 2.0, cy + math.sin(ang) * 1.4),
            (cx + math.cos(ang + 0.7) * r * 0.6, cy + math.sin(ang + 0.7) * r * 0.4),
            (cx + math.cos(ang + 1.2) * r, cy + math.sin(ang + 1.2) * r * 0.65),
            n=10,
        )
        for j, (sx, sy) in enumerate(pts):
            c = LOTUS_PETAL[2] if j < 6 else GOLD_DEW[3]
            ix, iy = int(round(sx)), int(round(sy))
            if 1 <= ix < CELL - 1 and 1 <= iy < CELL - 1:
                px[iy][ix] = (c[0], c[1], c[2], 185)
        tx, ty = int(round(pts[-1][0])), int(round(pts[-1][1]))
        glow.emit(px, tx, ty, (*GOLD_DEW[3][:3], 220), GLOW_GOLD_HOT if fi == 0 else GLOW_GOLD, 1 if fi == 0 else 0)
    return px, glow.done()


def _write_preview(out_path: pathlib.Path, water_frames, bank_frames):
    z = 2
    gap = 12
    w_cells = COLS * CELL
    h_half = 6 * CELL + gap + 9 * CELL + 16
    w_total = w_cells * 2 + gap * 3
    day_bg = (42, 122, 134, 255)
    night_bg = (14, 22, 42, 255)
    img = [[day_bg if (x // z) < (w_cells + gap * 2) else night_bg for x in range(w_total * z)] for y in range(h_half * z)]

    def paste(layer, ox, oy, dim=1.0, additive=False):
        for y, row in enumerate(layer):
            for x, c in enumerate(row):
                if c is None or not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(z):
                    for dx in range(z):
                        X, Y = (ox + x) * z + dx, (oy + y) * z + dy
                        if 0 <= X < w_total * z and 0 <= Y < h_half * z:
                            b = img[Y][X]
                            if additive:
                                img[Y][X] = tuple(min(255, int(b[i] + c[i] * a)) for i in range(3)) + (255,)
                            else:
                                img[Y][X] = tuple(int(b[i] * (1.0 - a) + c[i] * dim * a) for i in range(3)) + (255,)

    for night in (0, 1):
        ox0 = gap + night * (w_cells + gap)
        dim = 0.42 if night else 1.0
        for fi, (base, glow) in enumerate(water_frames):
            fx = ox0 + (fi % COLS) * CELL
            fy = 8 + (fi // COLS) * CELL
            paste(base, fx, fy, dim)
            if night:
                paste(glow, fx, fy, 1.0, additive=True)
        by0 = 8 + 6 * CELL + gap
        for fi, (base, glow) in enumerate(bank_frames):
            fx = ox0 + (fi % COLS) * CELL
            fy = by0 + (fi // COLS) * CELL
            paste(base, fx, fy, dim)
            if night:
                paste(glow, fx, fy, 1.0, additive=True)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(out_path, w_total * z, h_half * z, img)
    print(f"wrote preview {out_path}")


def main():
    water_rows = [
        [_draw_water_rosette(v, False) for v in range(COLS)],
        [_draw_water_rosette(v, True) for v in range(COLS)],
        [_draw_water_lotus(v, False) for v in range(COLS)],
        [_draw_water_lotus(v, True) for v in range(COLS)],
        [_draw_submerged_ribbon(v, False) for v in range(COLS)],
        [_draw_submerged_ribbon(v, True) for v in range(COLS)],
    ]
    water_frames = [cell for row in water_rows for cell in row]

    bank_builders = [
        _draw_bank_papyrus,
        _draw_bank_pebbles,
        _draw_bank_salt_quartz,
        _draw_bank_golddew,
        _draw_bank_palm_sprout,
        _draw_bank_foam_quartz,
        _draw_bank_star_rushes,
        _draw_bank_crystal_rose,
        _draw_bank_sun_filament,
    ]
    bank_rows = [[fn(v) for v in range(COLS)] for fn in bank_builders]
    bank_frames = [cell for row in bank_rows for cell in row]

    out_dir = ROOT.parent / "assets" / "water"
    out_dir.mkdir(parents=True, exist_ok=True)

    w_base = _pack_sheet([f[0] for f in water_frames], COLS, 6)
    w_glow = _pack_sheet([f[1] for f in water_frames], COLS, 6)
    write_png(out_dir / "oasis_water_flora.png", COLS * CELL, 6 * CELL, w_base)
    write_png(out_dir / "oasis_water_flora_glow.png", COLS * CELL, 6 * CELL, w_glow)
    print(f"wrote {out_dir / 'oasis_water_flora.png'} (+ _glow.png)")

    b_base = _pack_sheet([f[0] for f in bank_frames], COLS, 9)
    b_glow = _pack_sheet([f[1] for f in bank_frames], COLS, 9)
    write_png(out_dir / "oasis_bank_details.png", COLS * CELL, 9 * CELL, b_base)
    write_png(out_dir / "oasis_bank_details_glow.png", COLS * CELL, 9 * CELL, b_glow)
    print(f"wrote {out_dir / 'oasis_bank_details.png'} (+ _glow.png)")

    if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
        _write_preview(pathlib.Path(sys.argv[1]), water_frames, bank_frames)


if __name__ == "__main__":
    main()
