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


def _water_plant_outline(px):
    """Delicate directional contour for floating oasis plants: cool teal on sunlit NW rim, INK_LEAF on SE rim."""
    w, h = len(px[0]), len(px)
    marks = []
    for y in range(h):
        for x in range(w):
            if px[y][x][3] > 0:
                continue
            has_n = y + 1 < h and px[y + 1][x][3] >= 200
            has_w = x + 1 < w and px[y][x + 1][3] >= 200
            has_s = y - 1 >= 0 and px[y - 1][x][3] >= 200
            has_e = x - 1 >= 0 and px[y][x - 1][3] >= 200
            if has_n or has_w or has_s or has_e:
                # Top/left edges bordering sunlit leaves get soft deep-aqua contour instead of harsh black ring
                if (has_n or has_w) and not (has_s or has_e):
                    marks.append((x, y, (22, 66, 72, 225)))
                else:
                    marks.append((x, y, INK_LEAF))
    for x, y, c in marks:
        px[y][x] = c


def _rosette_leaf(px, ox: float, oy: float, ang: float, length: float, width: float, pal, lift: float = 0.0):
    """Crisp scalloped spoon-wedge Muschelblume leaf with dark overlap crease & sunlit mid-rib."""
    ca, sa = math.cos(ang), math.sin(ang)
    r_steps = max(7, int(round(length * 2.4)))
    w_steps = max(5, int(round(width * 2.4)))
    sun_dot = -0.58 * ca - 0.81 * sa
    for ri in range(1, r_steps + 1):
        t = ri / r_steps
        # Narrow stalked base -> broad spoon tip -> crisp rounded scallop (leaves V-notches between leaves!)
        flare = (t ** 0.72) * math.sin(min(1.0, t * 0.96) * (math.pi * 0.54)) * 1.18
        if t > 0.84:
            flare *= max(0.32, math.cos((t - 0.84) / 0.16 * (math.pi * 0.44)))
        half_w = width * flare
        for wi in range(-w_steps, w_steps + 1):
            frac = wi / w_steps
            u = frac * half_w
            lx = ox + ca * (t * length) - sa * u
            ly = oy + (sa * (t * length) + ca * u) * 0.68 - lift * t
            ix, iy = int(round(lx)), int(round(ly))
            if not (2 <= ix < CELL - 2 and 2 <= iy < CELL - 2):
                continue
            # Dark lateral leaf-margin crease on shaded edge so overlapping leaves stay crisply separated
            if frac > 0.72 and t < 0.85:
                px[iy][ix] = pal[0 if lift < 0.4 else 1]
                continue
            rib = 0.13 if (abs(frac) < 0.22 and 0.25 < t < 0.88) else 0.0
            lip = 0.12 if (t > 0.76 and sun_dot > -0.25) else 0.0
            lit = 0.22 + 0.44 * t + 0.24 * sun_dot + lift * 0.16 + rib + lip
            idx = int(clamp(lit * 5.5, 0, len(pal) - 1))
            px[iy][ix] = pal[idx]


def _draw_water_rosette(variant: int, alt_row: bool):
    """Rows 0 & 1: Stationary scalloped Muschelblume rosette per variant; only water shimmer & glint breathe."""
    rng = random.Random(1100 + variant * 37)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx = 16 + rng.randint(-1, 1)
    cy = 24 + (variant % 2)
    pal = LEAF if variant % 2 == 0 else TEAL_LEAF
    n_outer = 6 + (variant % 2)
    r_main = 6.2 + (variant % 3) * 0.4
    rot0 = rng.uniform(0.0, math.tau)

    centers = [(cx, cy, r_main, n_outer, rot0)]
    if variant in (1, 3, 5):
        sx = cx + (-6 if variant != 3 else 6)
        sy = cy - 3
        centers.append((sx, sy, 3.8, 5, rot0 + 0.55))

    for idx_c, (ox, oy, rad, count, r_ang) in enumerate(centers):
        # 1. Outer scalloped spoon leaves (distinct V-clefts around perimeter)
        outer_angs = sorted([r_ang + li * math.tau / count for li in range(count)], key=math.sin)
        for ang in outer_angs:
            _rosette_leaf(px, ox, oy, ang, rad, rad * 0.36, pal, lift=0.0)

        # 2. Dark cupped rosette shadow ring before inner whorl so layers separate cleanly
        for dy in (-1, 0, 1):
            for dx in (-2, -1, 0, 1, 2):
                if dx * dx + dy * dy * 2 <= 4:
                    _put(px, ox + dx, oy + dy, pal[0])

        # 3. Inner cupped whorl (offset half-step, steeper & brighter)
        n_inner = max(4, count - 1)
        inner_angs = sorted(
            [r_ang + (math.pi / count) + li * math.tau / n_inner for li in range(n_inner)],
            key=math.sin,
        )
        for ang in inner_angs:
            _rosette_leaf(px, ox, oy, ang, rad * 0.56, rad * 0.28, pal, lift=0.85)

        # 4. Golden-dew heart nestled in cupped center (1px glint shifts gently on alt_row)
        _put(px, ox, oy + 1, pal[1])
        _put(px, ox + 1, oy, pal[1])
        _put(px, ox, oy, GOLD_DEW[2])
        if idx_c == 0:
            gx_hi = ox - 1 if not alt_row else ox
            gy_hi = oy if not alt_row else oy - 1
            _put(px, ox - 1, oy, GOLD_DEW[3 if not alt_row else 2])
            _put(px, ox, oy - 1, GOLD_DEW[2 if not alt_row else 3])
            glow.emit(px, gx_hi, gy_hi, GOLD_DEW[3], GLOW_GOLD_HOT, 1)
            glow.emit(px, ox, oy, GOLD_DEW[2], GLOW_GOLD, 0)
        else:
            glow.emit(px, ox, oy, GOLD_DEW[3 if alt_row else 2], GLOW_GOLD, 0)

    # Identical scalloped plant silhouette outlined first -> zero outline pop between row 0 and row 1
    _water_plant_outline(px)

    # 4. Subtle translucent water contact shadow & breathing shimmer arc AFTER outline (alpha < 160)
    phase = 1 if alt_row else 0
    for idx_c, (ox, oy, rad, _count, _r_ang) in enumerate(centers):
        rx_r = rad + (1.7 if idx_c == 0 else 1.3)
        ry_r = rad * 0.70 + 1.2
        # Soft cool water shadow tucked on SE underside
        for dx in range(-int(rad), int(rad) + 1):
            sy_sh = int(round(oy + ry_r + 0.4))
            sx_sh = ox + dx
            if 1 <= sx_sh < CELL - 1 and 1 <= sy_sh < CELL - 1 and px[sy_sh][sx_sh][3] == 0:
                if abs(dx) <= rad * 0.75:
                    px[sy_sh][sx_sh] = (14, 48, 56, 88)
        # Delicate water-surface ripple glints that shift 1 step along the rim between frames
        n_rip = 12 if idx_c == 0 else 8
        for a_i in range(n_rip):
            if (a_i + variant + phase) % 3 != 0:
                continue
            ang = (a_i + 0.35 * phase) * math.tau / n_rip
            rx = int(round(ox + math.cos(ang) * rx_r))
            ry = int(round(oy + math.sin(ang) * ry_r))
            if 1 <= rx < CELL - 1 and 1 <= ry < CELL - 1 and px[ry][rx][3] == 0:
                px[ry][rx] = (*FOAM[2 if a_i % 2 == phase else 1][:3], 132)

    return px, glow.done()


def _draw_water_lotus(variant: int, is_bud_row: bool):
    """Rows 2 & 3: Stationary notched lotus pads around FOOT; row 2 open bloom, row 3 closed night bud."""
    rng = random.Random(2200 + variant * 53)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx = 16 + rng.randint(-1, 1)
    cy = 24 + (variant % 2)
    notch_ang = rng.uniform(-0.75, 0.75) + 0.55

    # Jade-turquoise floating lotus pad(s) — 100% identical across day (row 2) and night (row 3)
    pads = [(cx, cy, 7.0 + (variant % 3) * 0.5, 4.2)]
    if variant in (1, 3, 5):
        pads.append((cx + (-6 if variant != 3 else 6), cy - 3, 4.2, 2.7))

    for pi, (px0, py0, rx, ry) in enumerate(pads):
        for dy in range(-int(math.ceil(ry)) - 1, int(math.ceil(ry)) + 2):
            for dx in range(-int(math.ceil(rx)) - 1, int(math.ceil(rx)) + 2):
                u, v = dx / rx, dy / ry
                r2 = u * u + v * v
                if r2 > 1.0:
                    continue
                ang = math.atan2(v, u)
                diff = (ang - notch_ang + math.pi) % math.tau - math.pi
                if pi == 0 and abs(diff) < 0.30 and r2 > 0.05:
                    continue
                x, y = int(round(px0 + dx)), int(round(py0 + dy))
                if not (2 <= x < CELL - 2 and 2 <= y < CELL - 2):
                    continue
                dist = math.sqrt(r2)
                # Upturned sunlit NW rim + radial primary veins
                lit = 0.54 - 0.32 * u - 0.36 * v
                if dist > 0.78 and (u + v) < 0.15:
                    lit += 0.14
                vein = abs(math.sin(ang * 4.0)) < 0.16 and 0.22 < dist < 0.82
                if vein:
                    lit += 0.10 if (u + v) < 0 else -0.06
                idx = int(clamp(lit * 5.0 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.25, 0, 5))
                px[y][x] = TEAL_LEAF[idx]

    # Blossom anchored at heart of main pad (ONLY part changing between row 2 and row 3)
    bx, by = cx, cy - 1
    if is_bud_row:
        bud_pts = [(bx, by)] if variant % 2 == 0 else [(bx - 2, by), (bx + 3, by + 1)]
        for bi, (ux, uy) in enumerate(bud_pts):
            # Clasped dark-jade sepal base + pointed luminous cyan-pearl night bud
            _put(px, ux - 1, uy + 1, TEAL_LEAF[1])
            _put(px, ux, uy + 1, TEAL_LEAF[2])
            _put(px, ux + 1, uy + 1, TEAL_LEAF[0])
            if bi == 0:
                bud_shape = (
                    (0, -3, 4),
                    (-1, -2, 3), (0, -2, 4), (1, -2, 2),
                    (-2, -1, 2), (-1, -1, 3), (0, -1, 3), (1, -1, 1), (2, -1, 0),
                    (-1, 0, 2), (0, 0, 1), (1, 0, 0),
                )
            else:
                bud_shape = (
                    (0, -2, 4), (-1, -1, 3), (0, -1, 3), (1, -1, 1), (-1, 0, 1), (0, 0, 2), (1, 0, 0),
                )
            for dx, dy, sh in bud_shape:
                _put(px, ux + dx, uy + dy, LOTUS_PETAL[sh])
            glow.emit(px, ux, uy - (2 if bi == 0 else 1), LOTUS_PETAL[4], GLOW_CYAN_HOT, 1 if bi == 0 else 0)
            glow.emit(px, ux, uy - 1, LOTUS_PETAL[3], GLOW_CYAN, 0)
    else:
        # Layered 8-petal desert star-lotus cup + golden stamen crown
        outer_petals = (
            (0, -4, 3), (-3, -3, 3), (3, -3, 2),
            (-4, -1, 3), (4, -1, 1),
            (-3, 1, 2), (3, 1, 0), (0, 2, 1),
        )
        inner_cup = (
            (-1, -3, 4), (0, -3, 4), (1, -3, 3),
            (-2, -2, 4), (-1, -2, 4), (1, -2, 3), (2, -2, 2),
            (-3, -1, 3), (-2, -1, 4), (2, -1, 2), (3, -1, 1),
            (-2, 0, 3), (2, 0, 1),
            (-1, 1, 2), (0, 1, 2), (1, 1, 1),
        )
        for dx, dy, sh in outer_petals:
            _put(px, bx + dx, by + dy, LOTUS_PETAL[sh])
        for dx, dy, sh in inner_cup:
            _put(px, bx + dx, by + dy, LOTUS_PETAL[sh])
        # Warm golden oasis stamen heart
        _put(px, bx - 1, by - 1, GOLD_DEW[3])
        _put(px, bx, by - 1, GOLD_DEW[3])
        _put(px, bx + 1, by - 1, GOLD_DEW[2])
        _put(px, bx - 1, by, GOLD_DEW[2])
        _put(px, bx, by, GOLD_DEW[1])
        _put(px, bx + 1, by, GOLD_DEW[0])
        glow.emit(px, bx, by - 1, GOLD_DEW[3], GLOW_GOLD_HOT, 1)
        glow.emit(px, bx - 1, by - 1, GOLD_DEW[3], GLOW_GOLD, 0)
        glow.emit(px, bx, by - 2, LOTUS_PETAL[4], GLOW_CYAN, 0)

    _water_plant_outline(px)

    # Subtle stationary water shadow & surface ripple pixels under pads (alpha < 150)
    for px0, py0, rx, ry in pads:
        sy_sh = min(CELL - 2, int(round(py0 + ry + 1.0)))
        for dx in range(-int(rx * 0.7), int(rx * 0.7) + 1):
            sx_sh = int(round(px0 + dx))
            if 1 <= sx_sh < CELL - 1 and px[sy_sh][sx_sh][3] == 0:
                px[sy_sh][sx_sh] = (14, 48, 56, 92)
        for sx_r, sy_r in ((int(round(px0 - rx - 1.2)), int(round(py0 + 1))), (int(round(px0 + rx + 1.2)), int(round(py0 + 1)))):
            if 1 <= sx_r < CELL - 1 and 1 <= sy_r < CELL - 1 and px[sy_r][sx_r][3] == 0:
                px[sy_r][sx_r] = (*FOAM[1][:3], 128)

    return px, glow.done()


def _draw_submerged_ribbon(variant: int, row_alt: bool):
    """Rows 4 & 5: Identical root positions, blade count & heights; smooth 1..2px upper wave sway (no outline)."""
    rng = random.Random(3300 + variant * 41)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    strands = 5 + (variant % 3)
    base_y = 28 + (variant % 2)
    phase_shift = 1.05 if row_alt else 0.0

    # Pre-sample all per-blade geometry from fixed RNG so row 4 and row 5 share exact roots & heights
    blade_specs = []
    for si in range(strands):
        ox = 8 + int(round((si / max(strands - 1, 1)) * 16)) + rng.randint(-1, 1)
        ox = int(clamp(ox, 6, 25))
        h = rng.randint(11, 18)
        lean = rng.uniform(-2.6, 2.6) + (0.9 if variant % 2 == 0 else -0.9)
        w_phase = rng.uniform(0.0, math.tau)
        blade_specs.append((si, ox, h, lean, w_phase))

    bub_x = int(clamp(14 + rng.randint(-3, 3), 6, 25))
    bub_y = 16 + rng.randint(-2, 2) - (2 if row_alt else 0)

    for si, ox, h, lean, w_phase in blade_specs:
        steps = h + 4
        tip_x, tip_y = ox, base_y
        for j in range(steps + 1):
            t = j / max(steps, 1)
            # Stationary at root (t=0), smooth 1..2 px current drift toward tip (t=1)
            sway_x = lean * (t ** 1.2) + math.sin(t * 2.5 + w_phase + phase_shift) * (1.35 * t)
            sx = ox + sway_x
            sy = base_y - h * t
            ix, iy = int(round(sx)), int(round(sy))
            ix = int(clamp(ix, 3, CELL - 4))
            iy = int(clamp(iy, 3, CELL - 3))
            c_idx = min(4, int(t * 4.6))
            c = SUB_GRASS[c_idx]
            a = int(172 + 44 * t)  # strictly <= 216 underwater translucency
            px[iy][ix] = (c[0], c[1], c[2], a)
            if t < 0.72 and ix + 1 < CELL - 3:
                c_sh = SUB_GRASS[max(0, c_idx - 1)]
                if px[iy][ix + 1][3] < a - 20:
                    px[iy][ix + 1] = (c_sh[0], c_sh[1], c_sh[2], a - 28)
            tip_x, tip_y = ix, iy
        if si % 2 == 0 and 3 <= tip_x < CELL - 3 and 3 <= tip_y < CELL - 3:
            glow.emit(px, tip_x, tip_y, (*SUB_GRASS[4][:3], 216), GLOW_CYAN, 0)

    # Tiny rising spring oxygen bubble shifting 2px up on row_alt
    if 3 <= bub_x < CELL - 3 and 3 <= bub_y < CELL - 3 and px[bub_y][bub_x][3] == 0:
        px[bub_y][bub_x] = (*FOAM[2][:3], 155)

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
        cx = 16 + rng.randint(-6, 6)
        cy = 25 + rng.randint(-2, 2)
        rx = rng.uniform(2.2, 4.0)
        ry = rng.uniform(1.5, 2.5)
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
    """Row 7: Quell-Kristallrose (no outline, translucent shallow-water star rosette + glow around FOOT)."""
    rng = random.Random(4800 + variant * 61)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx = 16 + rng.randint(-2, 2)
    cy = 24 + (variant % 2)
    alpha = 212
    # Soft water shimmer ring
    for dx, dy in ((-5, 0), (5, 0), (0, -3), (0, 3)):
        _put(px, cx + dx, cy + dy, (*FOAM[1][:3], 125))
    # Outer faceted crystal blades (3/4 foreshortened)
    outer_pts = (
        (0, -3, 3), (-3, -2, 3), (3, -2, 2),
        (-4, 0, 3), (4, 0, 1),
        (-3, 2, 2), (3, 2, 1), (0, 3, 1),
    )
    for dx, dy, qi in outer_pts:
        _put(px, cx + dx, cy + dy, (*QUARTZ[qi][:3], alpha - 28))
    # Inner bright sunlit quartz facets
    inner_pts = (
        (0, -2, 4), (-2, -1, 4), (2, -1, 3),
        (-2, 0, 4), (-1, -1, 4), (1, -1, 3), (2, 0, 2),
        (-1, 1, 3), (0, 1, 3), (1, 1, 2), (0, 2, 2),
    )
    for dx, dy, qi in inner_pts:
        _put(px, cx + dx, cy + dy, (*QUARTZ[qi][:3], alpha))
    _put(px, cx - 1, cy, (*QUARTZ[4][:3], 228))
    glow.emit(px, cx, cy, (*GOLD_DEW[3][:3], 232), GLOW_CYAN_HOT, 1)
    glow.emit(px, cx, cy - 1, (*LOTUS_PETAL[4][:3], 220), GLOW_CYAN, 0)
    return px, glow.done()


def _draw_bank_sun_filament(variant: int):
    """Row 8: Sonnen-Quellfaden (no outline, delicate floating golden-cyan oasis filaments + glow around FOOT)."""
    rng = random.Random(4900 + variant * 67)
    px, glow = blank(CELL, CELL), Glow(CELL, CELL)
    cx = 16 + rng.randint(-1, 1)
    cy = 24 + (variant % 2)
    for fi in range(3):
        ang = rng.uniform(0.0, math.tau) + fi * 2.05
        r = 4.6 + rng.uniform(0.8, 2.2)
        pts = bezier(
            (cx + math.cos(ang) * 1.6, cy + math.sin(ang) * 1.1),
            (cx + math.cos(ang + 0.65) * r * 0.62, cy + math.sin(ang + 0.65) * r * 0.42),
            (cx + math.cos(ang + 1.15) * r, cy + math.sin(ang + 1.15) * r * 0.58),
            n=10,
        )
        for j, (sx, sy) in enumerate(pts):
            c = TEAL_LEAF[4] if j < 3 else (LOTUS_PETAL[2] if j < 7 else GOLD_DEW[3])
            ix = int(clamp(round(sx), 3, CELL - 4))
            iy = int(clamp(round(sy), 3, CELL - 4))
            px[iy][ix] = (c[0], c[1], c[2], 190)
        tx = int(clamp(round(pts[-1][0]), 3, CELL - 4))
        ty = int(clamp(round(pts[-1][1]), 3, CELL - 4))
        glow.emit(px, tx, ty, (*GOLD_DEW[3][:3], 222), GLOW_GOLD_HOT if fi == 0 else GLOW_GOLD, 1 if fi == 0 else 0)
    return px, glow.done()


def _check_bounds(tag: str, frames):
    errs = []
    for idx, (base, glow) in enumerate(frames):
        for sub, layer in (("base", base), ("glow", glow)):
            pts = [(x, y) for y, row in enumerate(layer) for x, c in enumerate(row) if c is not None and c[3] > 0]
            if not pts:
                continue
            xs = [x for x, _ in pts]
            ys = [y for _, y in pts]
            if min(xs) < 1 or max(xs) > CELL - 2 or min(ys) < 1 or max(ys) > CELL - 2:
                errs.append(f"{tag}[{idx}] {sub}: x={min(xs)}..{max(xs)}, y={min(ys)}..{max(ys)}")
    assert not errs, "Cell border clipping detected:\n" + "\n".join(errs)


def _write_preview(out_path: pathlib.Path, water_frames, bank_frames):
    z = 3
    gap = 12
    w_cells = COLS * CELL
    h_half = 6 * CELL + gap + 9 * CELL + 16
    w_total = w_cells * 2 + gap * 3
    day_bg = (42, 122, 134, 255)
    night_bg = (14, 22, 42, 255)
    img = [[day_bg if (x // z) < (w_cells + gap * 2) else night_bg for x in range(w_total * z)] for y in range(h_half * z)]

    def draw_cell_guides(ox, oy, is_night):
        grid_c = (26, 38, 66, 255) if is_night else (32, 102, 114, 255)
        foot_c = (68, 92, 132, 255) if is_night else (74, 152, 162, 255)
        for x in range(CELL * z):
            img[oy * z][ox * z + x] = grid_c
        for y in range(CELL * z):
            img[oy * z + y][ox * z] = grid_c
        # Faint tick at FOOT = (16, 28)
        fx, fy = (ox + 16) * z, (oy + 28) * z
        for d in (-1, 0, 1):
            img[fy][fx + d] = foot_c
            img[fy + d][fx] = foot_c

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
            draw_cell_guides(fx, fy, bool(night))
            paste(base, fx, fy, dim)
            if night:
                paste(glow, fx, fy, 1.0, additive=True)
        by0 = 8 + 6 * CELL + gap
        for fi, (base, glow) in enumerate(bank_frames):
            fx = ox0 + (fi % COLS) * CELL
            fy = by0 + (fi // COLS) * CELL
            draw_cell_guides(fx, fy, bool(night))
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

    _check_bounds("oasis_water_flora", water_frames)
    _check_bounds("oasis_bank_details", bank_frames)

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
