#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 5 — Die 3 Einmaligen Weltwunder (stdlib + gen_art.py only):
  1. assets/props/bell_spire.png & _glow.png (Der Glockenteich)
     - 2 cols x 1 row of 96x160 (192x160 total), waterline/base anchor at (48, 136):
       * Col 0 (Dormant / Day-Dusk): Sunken ancient stone & verdigris-copper belfry spire rising ~120 px above
                waterline (48, 136), irregular ashlar courses, dressed corner quoins, sloped buttresses, vaulted
                belfry shadow housing a cast-bronze & verdigris bell on heavy timber yoke, overlapping diamond/
                fish-scale slate & copper roof tiles with oxidized patina drips and ornate bronze crescent finial,
                and stepped plinth transitioning through wet algae-stained submerged stone + translucent aqua ripples!
       * Col 1 (Awakened / Midnight Toll): Warm turquoise-gold resonance runes awakened on archivolts, bell waist &
                sound-bow, finial, and luminous concentric harmonic water rings expanding at the waterline.
  2. assets/props/bell_stepping_stone.png & _glow.png
     - 3 cols x 1 row of 32x32 (96x32 total), center (16, 18):
       * Col 0: Refracted underwater octagonal stone silhouette with soft surface ripples (zero dark outline).
       * Col 1: Chiseled octagonal stone slab with chipped bevels, spiral rune carving & soft aqua water-lap skirt.
       * Col 2: Chiseled mossy octagonal slab with concentric bell-wave glyph & soft aqua water-lap skirt.
  3. assets/props/sleeping_guardian.png & _glow.png (Der Kreis der Schlafenden Wächter)
     - 3 cols x 1 row of 80x128 (240x128 total), ground/feet anchor at (40, 116):
       * Col 0: Towering chiseled robed monolithic guardian on multi-block chipped ashlar pedestal + meadow turf skirt,
                5-peak stone crown, planar facial facets, sculpted gauntlets & cracked runic tower-shield.
       * Col 1: Kneeling monolithic sentinel with 3-tier chiseled Gothic feather wings, diademed head, crossed stone
                forearms, pleated robe, creeping ivy & purple heather, and mossy meadow sod base.
       * Col 2: 7th Broken/Headless Guardian, jagged stepped planar neck fracture, diagonal collar crack, heavy moss
                cushions, fallen chiseled stone blocks & meadow turf skirt.
  4. assets/props/guardian_brazier.png & _glow.png (plus Fallen Headstone!)
     - 3 cols x 1 row of 40x48 (120x48 total), ground/feet anchor at (20, 40):
       * Col 0: Unlit chiseled fluted stone offering basin on octagonal stem & chipped plinth, cold ash & charred wood.
       * Col 1: Lit fluted stone basin burning with crisp multi-tongued turquoise-gold spirit flame & sparks.
       * Col 2: Fallen chiseled crowned Guardian Headstone resting half-buried in earthen sod, tall grass & wildflowers.
  5. assets/props/amphitheater_podium.png & _glow.png (Das Blumen-Amphitheater)
     - Single frame 128x96, center/ground anchor at (64, 52):
       Ancient 3/4 12-sided carved megalithic stage podium with 4 cardinal mossy stone stairways, chipped kerb blocks,
       fitted tesserae, crisp silver/turquoise/amethyst moonflower-and-chord mosaic inlays, and meadow turf skirt!
  6. docs/img/meadow_wonders_sheet.png — Visual QA contact sheet (daylight + night).

STRICTLY ZERO #000000 pure black pixels anywhere!
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "meadow_wonders_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# ---- Palettes (STRICTLY ZERO #000000) ----
OUT_STONE = hexc("1b1a2e")
OUT_LEAF = hexc("122422")
MORTAR = hexc("19162e")
SHADOW_RGB = (15, 16, 34)

# 9-step weathered blue-violet ancient stone ramp (cool-violet shadows -> warm-cool sunlit limestone bevels)
STONE = [
    hexc("1c1a32"),  # 0 deep interior crevice / undercut
    hexc("272444"),  # 1 dark cool-violet shadow
    hexc("373358"),  # 2 shaded ashlar plane
    hexc("4b4670"),  # 3 mid-shadow stone
    hexc("615b89"),  # 4 mid dressed stone
    hexc("7b74a4"),  # 5 lit stone facet
    hexc("9992bf"),  # 6 bright planar facet
    hexc("bab4da"),  # 7 sunlit chamfer bevel
    hexc("dad6f2"),  # 8 crisp top-left catch-edge
]

LICHEN = [hexc("56746a"), hexc("789c8e"), hexc("a4c8b6")]
EARTH = [hexc("231b2b"), hexc("35293d"), hexc("4b3b52"), hexc("655168")]
RIM_COOL = [hexc("2c6e8a"), hexc("58b6ce")]

# Verdigris-copper, tarnished cast-bronze, aged gold & weathered blue-slate roofing
VERDIGRIS = [hexc(c) for c in ("162a2c", "203d3c", "2b524d", "386960", "4a8274", "609c8b", "82bfa9", "b2e4cf")]
BRONZE = [hexc(c) for c in ("261c24", "3d2c30", "59413c", "7a5b48", "9e7954", "c49e68")]
GOLD_RIM = [hexc(c) for c in ("4c3618", "755626", "9c7636", "c49a4c", "e6c468", "fff0b0")]
SLATE_ROOF = [hexc(c) for c in ("191f34", "252f4b", "354364", "4a5b80", "65799e", "899ec0", "b2c4e0")]

# Submerged algae-stained stone & translucent turquoise-aqua water ripples
SUB_STONE = [hexc(c) for c in ("112634", "183746", "214b5a", "2e6472", "3f808c")]
WATER_LAP = [hexc("1f5f72"), hexc("2a8c94"), hexc("3cc0c6"), hexc("78f4e6"), hexc("d8fff9")]

# Meadow moss, teal moss, wildflowers & brazier ash
MOSS = [hexc(c) for c in ("16302c", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
TEAL_MOSS = [hexc(c) for c in ("15353b", "215052", "327870", "52a892", "86dcb8")]
HEATHER = [hexc("5e3884"), hexc("8e5cc2"), hexc("caa4f2"), hexc("f0dcfb")]
BLOSSOM_GOLD = [hexc("9c722c"), hexc("e6c468"), hexc("fff0b0")]
ASH = [hexc(c) for c in ("1e1b2e", "2e2b42", "434059", "5d5a75", "7c7894")]

# Mosaic inlays & unlit emissive glow colors
MOSAIC_SILVER = [hexc("4a5674"), hexc("7282a4"), hexc("a4b4d2"), hexc("dce6fa"), hexc("f4f8ff")]
MOSAIC_VIO = [hexc("34185e"), hexc("563098"), hexc("8054dc"), hexc("ac88f8"), hexc("dec8ff")]
TEAL_DIM = hexc("2a8c94")
TEAL = hexc("3cc0c6")
TEAL_L = hexc("78f4e6")
TEAL_HOT = hexc("d8fff9")
GOLD_GLOW = hexc("ffd88a")
GOLD_HOT = hexc("fff6d6")
VIO_GLOW = hexc("9468ee")
VIO_HOT = hexc("d6baff")

FOLIAGE_SET = set(MOSS + TEAL_MOSS + EARTH)


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        px[y][x] = col


def put_alpha(px, x: int, y: int, rgb_or_rgba, alpha: int = 255):
    """Alpha-composites onto `px` (handles both empty transparent pixels and opaque pixels)."""
    if not (0 <= x < len(px[0]) and 0 <= y < len(px)):
        return
    a = clamp(int(alpha if len(rgb_or_rgba) == 3 else rgb_or_rgba[3]), 0, 255)
    if a <= 0:
        return
    sr, sg, sb = rgb_or_rgba[0], rgb_or_rgba[1], rgb_or_rgba[2]
    dst = px[y][x]
    da = dst[3]
    if da == 0 or a == 255:
        px[y][x] = (sr, sg, sb, a if da == 0 else 255)
        return
    out_a = a + (da * (255 - a)) // 255
    if out_a <= 0:
        return
    nr = (sr * a + dst[0] * da * (255 - a) // 255) // out_a
    ng = (sg * a + dst[1] * da * (255 - a) // 255) // out_a
    nb = (sb * a + dst[2] * da * (255 - a) // 255) // out_a
    px[y][x] = (max(4, nr), max(4, ng), max(8, nb), out_a)


def get_a(px, x: int, y: int) -> int:
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        return px[y][x][3]
    return 0


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def hsh(x: int, y: int, s: int) -> float:
    n = (int(x) * 374761393 + int(y) * 668265263 + int(s) * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x: float, y: float, s: int) -> float:
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def fbm(x: float, y: float, s: int) -> float:
    return 0.56 * vnoise(x, y, s) + 0.30 * vnoise(x * 2.1, y * 2.1, s + 11) + 0.14 * vnoise(x * 4.2, y * 4.2, s + 23)


class GlowMap:
    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.px = blank(w, h)
        self.pts = []

    def emit(self, base, x: int, y: int, dim_col, bright_col, halo: int = 1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim_col is not None and base is not None:
                base[y][x] = dim_col
            self.px[y][x] = bright_col
            if halo > 0:
                self.pts.append((x, y, bright_col, halo))

    def finish(self):
        out = [row[:] for row in self.px]
        for cx, cy, col, rad in self.pts:
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    if dx == 0 and dy == 0:
                        continue
                    xx, yy = cx + dx, cy + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h):
                        continue
                    d = math.hypot(dx, dy)
                    if d <= rad + 0.45 and out[yy][xx][3] < 255:
                        a = 104 if d <= 1.25 else (48 if d <= 2.05 else 22)
                        if a > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], a)
        return out


# ==============================================================================
# Shared Chiseled Stone, Weathering, Foliage & Outline Primitives
# ==============================================================================
def stone_tone(x: int, y: int, val: float, seed: int, damp: bool = True) -> tuple:
    """Computes chiseled stone pixel color using directional 2px horizontal grain, vertical damp streaks, and Bayer dithering."""
    # Directional horizontal stone bedding grain (2px cluster strokes, ZERO single-pixel white noise)
    grain = (fbm(x * 0.42, y * 0.78, seed) - 0.5) * 0.92
    stroke = (hsh(x // 2, y, seed + 17) - 0.5) * 0.42
    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.52
    v = val + grain + stroke + dith
    # Occasional 2px stone pit cluster
    if hsh(x // 2, y, seed + 31) > 0.955:
        v -= 1.05
    # Vertical damp weathering streaks running down ancient masonry
    if damp:
        streak = vnoise(x * 0.85, y * 0.09, seed + 47)
        if streak > 0.66 and (BAYER[y % 4][x % 4] / 16.0) < (streak - 0.60) * 3.8:
            v -= 0.85
    return STONE[int(clamp(round(v), 0, len(STONE) - 1))]


def build_course_map(y0: int, y1: int, x_min: int, x_max: int, heights, widths, seed: int):
    """Precomputes irregular ashlar course rows and staggered irregular vertical block joints."""
    rows = {}
    cy = y0
    ci = 0
    while cy <= y1:
        ch = heights[ci % len(heights)]
        # Build irregular vertical joints across [x_min..x_max]
        jx = x_min + 3 + int(hsh(ci, 0, seed) * 5.0)
        joints = []
        ji = 0
        while jx < x_max - 2:
            joints.append(jx)
            w_step = widths[(ci * 3 + ji) % len(widths)] + int(hsh(ci, ji + 1, seed + 5) * 3.0)
            jx += max(5, w_step)
            ji += 1
        for ry in range(cy, min(y1 + 1, cy + ch)):
            rows[ry] = (ci, ry - cy, min(y1 + 1, cy + ch) - cy, joints)
        cy += ch
        ci += 1
    return rows


def ashlar_pixel(x: int, y: int, base_val: float, cmap, seed: int) -> tuple:
    """Samples an irregular ashlar stone wall with block bias, crumbled mortar joints & chamfered catch-edges."""
    ci, r_in, ch, joints = cmap[y]
    # Find block index along course
    bi = 0
    prev_j = -999
    next_j = 999
    for j in joints:
        if x >= j:
            bi += 1
            prev_j = j
        else:
            next_j = j
            break

    # Mortar joint test (bottom row of course or at joint X, with occasional natural stone bridge)
    is_h_joint = (r_in == ch - 1) and (hsh(x // 3, y, seed + 61) < 0.90)
    is_v_joint = (x == prev_j) and (hsh(x, y // 2, seed + 67) < 0.92)
    # Chipped block corner at T-junctions
    corner_chip = (r_in in (0, ch - 2)) and (abs(x - prev_j) == 1 or abs(x - next_j) == 1) and hsh(x, y, seed + 71) > 0.84

    if is_h_joint or is_v_joint:
        return MORTAR if hsh(x, y, seed + 73) < 0.78 else STONE[1]
    if corner_chip:
        return STONE[1] if r_in == ch - 2 else STONE[2]

    # Per-block value variation + top-left chamfered catch-edges
    blk_bias = (hsh(bi + ci * 13, ci, seed + 79) - 0.5) * 0.85
    bevel = 0.0
    if r_in == 0:
        bevel += 0.95  # Sunlit upper block edge below horizontal joint
    elif r_in == ch - 2:
        bevel -= 0.40  # Subtle lower lip shadow
    if x == prev_j + 1:
        bevel += 0.65  # Sunlit left block edge right of vertical joint
    elif x == next_j - 1:
        bevel -= 0.35

    return stone_tone(x, y, base_val + blk_bias + bevel, seed)


def carve_crack(px, pts, seed: int = 101, lit_side: int = 1):
    """Carves a dark structural crack with a crisp sunlit catch-edge on the lit side."""
    pt_set = set(pts)
    for i, (cx, cy) in enumerate(pts):
        if get_a(px, cx, cy) == 255:
            deep = (i < len(pts) - 1) and (hsh(cx, cy, seed) < 0.80)
            put(px, cx, cy, MORTAR if deep else STONE[1])
            nx = cx + lit_side
            if (nx, cy) not in pt_set and get_a(px, nx, cy) == 255 and px[cy][nx] in STONE[:7]:
                idx = STONE.index(px[cy][nx])
                put(px, nx, cy, STONE[min(7, idx + 1)])


def chip_silhouette(px, cx: int, cy: int, rad: int, is_left: bool):
    """Cuts an authentic weathered chip notch into a stone edge and lights the exposed fracture shelf."""
    for dy in range(-1, rad + 2):
        for dx in range(0, rad + 2):
            xx = cx + (dx if is_left else -dx)
            yy = cy + dy
            if not (0 <= xx < len(px[0]) and 0 <= yy < len(px)):
                continue
            if abs(dy) + dx <= rad:
                px[yy][xx] = CLEAR
            elif dy == rad and dx <= rad and get_a(px, xx, yy) == 255:
                # Exposed upward-facing chipped fracture plane catches top-left light!
                put(px, xx, yy, STONE[7 if is_left else 5])
            elif abs(dy) + dx == rad + 1 and get_a(px, xx, yy) == 255:
                put(px, xx, yy, STONE[6 if is_left else 2])


def sprinkle_lichen(px, clusters, seed: int):
    """Places crisp 2-4 px pale-sage crust lichen colonies on dry stone surfaces."""
    offsets = [(0, 0), (1, 0), (0, 1), (-1, 0)]
    for i, (lx, ly, sz) in enumerate(clusters):
        for k in range(min(sz, len(offsets))):
            xx, yy = lx + offsets[k][0], ly + offsets[k][1]
            if get_a(px, xx, yy) == 255 and px[yy][xx] in STONE[1:7]:
                tone = 2 if (k == 0 and sz >= 3) else (1 if (k + i) % 2 == 0 else 0)
                put(px, xx, yy, LICHEN[tone])


def apply_organic_moss(px, mask_fn, seed: int, pal=MOSS, teal_accents: bool = True):
    """Applies painterly multi-tone moss cushions with Bayer cluster edges, sunlit leaf flecks & damp stone stain."""
    h, w = len(px), len(px[0])
    snap = [row[:] for row in px]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            prob = mask_fn(x, y)
            if prob <= 0.0:
                continue
            n = fbm(x * 0.36, y * 0.44, seed) * 0.78 + hsh(x // 2, y, seed + 5) * 0.22
            thr = 0.55 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42
            score = prob * (0.56 + n)
            if score > thr:
                # Top-left lit moss clusters
                lit = 0.62 - 0.22 * (x / float(w)) + (0.18 if mask_fn(x, y - 1) < prob * 0.6 else 0.0)
                lit += (hsh(x // 2, y, seed + 9) - 0.5) * 0.36
                idx = int(clamp(lit * (len(pal) - 1.1) + (BAYER[(y + 1) % 4][x % 4] / 16.0 - 0.5) * 0.65, 1, len(pal) - 1))
                if mask_fn(x, y + 1) < prob * 0.45 and hsh(x, y, seed + 13) > 0.35:
                    idx = max(0, idx - 2)
                if teal_accents and idx >= 3 and hsh(x // 2, y // 2, seed + 19) > 0.82:
                    put(px, x, y, TEAL_MOSS[min(4, idx - 1)])
                else:
                    put(px, x, y, pal[idx])
            elif score > thr - 0.18 and snap[y][x][3] == 255 and snap[y][x] in STONE[2:]:
                # Damp darkened weathering halo around moss cushion
                k = STONE.index(snap[y][x])
                put(px, x, y, STONE[max(1, k - 1)])


def drape_moss(px, x0: int, x1: int, y_top: int, thick: int, hang: int, seed: int):
    """Drapes clustered, trailing meadow moss cushions hugging true stone contours with damp undercut stains."""
    w, h = len(px[0]), len(px)
    snap = [row[:] for row in px]
    for x in range(max(2, x0), min(w - 2, x1 + 1)):
        # Locate actual topmost opaque stone surface near `y_top` so moss never floats in mid-air!
        y_surf = None
        for sy in range(max(1, y_top - 3), min(h - 2, y_top + 9)):
            if snap[sy][x][3] == 255:
                y_surf = sy
                break
        if y_surf is None:
            continue
        wave = 0.62 * math.sin(x * 0.48 + seed) + 0.38 * hsh(x // 2, y_surf, seed + 5)
        drop = int(round(hang * max(0.0, wave)))
        tj = -1 if hsh(x // 2, 0, seed + 7) > 0.54 else 0
        y_start = max(1, y_surf + tj)
        y_end = min(h - 2, y_surf + thick + drop)
        for y in range(y_start, y_end + 1):
            if y > y_surf and snap[y][x][3] == 0:
                break
            u = (y - y_start) / max(1.0, float(y_end - y_start))
            lit = (1.0 - u * 0.78) * 0.76 + (0.18 if x < w // 2 else 0.02)
            lit += (fbm(x * 0.45, y * 0.55, seed + 11) - 0.5) * 0.35
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.48
            idx = int(clamp(lit * 6.2 + dith, 0, len(MOSS) - 1))
            if y == y_end and drop >= 1:
                idx = min(idx, 2)
            if idx >= 4 and hsh(x // 2, y, seed + 23) > 0.80:
                put(px, x, y, TEAL_MOSS[min(4, idx - 1)])
            else:
                put(px, x, y, MOSS[idx])
        fy = y_end + 1
        if 1 <= fy < h - 1 and px[fy][x] in STONE[2:]:
            px[fy][x] = STONE[max(1, STONE.index(px[fy][x]) - 2)]


def draw_detailed_pebble(px, cx: float, cy: float, rx: float, ry: float, seed: int):
    """Draws a crisp chiseled stone chip/pebble with top-left facet highlight and dark base."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            d = abs(dx) ** 1.85 + abs(dy) ** 1.85
            if d > 1.0:
                continue
            val = 4.2 - 1.8 * dx - 2.1 * dy + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.6
            if dy < -0.35 and dx < 0.25:
                val += 1.2
            elif dy > 0.45:
                val -= 1.2
            put(px, x, y, STONE[int(clamp(round(val), 1, 7))])


def draw_grass_tuft(px, bx: int, by: int, flip: int = 1, tall: bool = True, blossom=None):
    """Draws crisp directional meadow grass blades with dark earthen root and sunlit tips."""
    if tall:
        blades = [
            [(0, 0, MOSS[0]), (-1 * flip, -1, MOSS[2]), (-2 * flip, -2, MOSS[4]), (-3 * flip, -3, MOSS[5]), (-3 * flip, -4, MOSS[6])],
            [(1 * flip, 0, MOSS[1]), (1 * flip, -1, MOSS[3]), (2 * flip, -2, MOSS[4]), (2 * flip, -3, MOSS[5])],
            [(0, -1, MOSS[2]), (0, -2, MOSS[4]), (-1 * flip, -3, MOSS[5])],
        ]
    else:
        blades = [
            [(0, 0, MOSS[1]), (-1 * flip, -1, MOSS[3]), (-2 * flip, -2, MOSS[5])],
            [(1 * flip, 0, MOSS[1]), (1 * flip, -1, MOSS[4]), (2 * flip, -2, MOSS[6])],
            [(0, -1, MOSS[2]), (0, -2, MOSS[4])],
        ]
    for b in blades:
        for dx, dy, c in b:
            put(px, bx + dx, by + dy, c)
    if blossom is not None:
        put(px, bx + 2 * flip, by - 3, blossom[0])
        put(px, bx + 2 * flip, by - 4, blossom[2])
        put(px, bx + 1 * flip, by - 4, blossom[1])


def draw_sod_pocket(px, x0: int, x1: int, y_base: int, seed: int):
    """Paints an irregular earthen-and-moss sod cushion rooting a stone plinth into the meadow."""
    for x in range(x0, x1 + 1):
        u = (x - x0) / max(1.0, float(x1 - x0))
        arch = math.sin(u * math.pi)
        h_sod = int(round(1.2 + 2.2 * arch * (0.65 + 0.35 * hsh(x // 2, y_base, seed))))
        for dy in range(h_sod + 1):
            y = y_base - dy
            if dy == 0:
                put(px, x, y, EARTH[1 if hsh(x, y, seed + 3) < 0.6 else 2])
            elif dy == h_sod:
                put(px, x, y, MOSS[4 if x < (x0 + x1) // 2 else 3])
            else:
                put(px, x, y, MOSS[2 if dy == 1 else 3])


def finish_prop(body, cx: float, fy: float, rx: float, ry: float, max_outline_y: int = 9999, draw_shadow: bool = True):
    """Composites cool-violet ground shadow, material-tinted 1px dark outline (`OUT_STONE`/`OUT_LEAF`), and body."""
    w, h = len(body[0]), len(body)
    out = blank(w, h)
    if draw_shadow and rx > 0 and ry > 0:
        for y in range(max(0, int(fy - ry - 2)), min(h, int(fy + ry + 4))):
            for x in range(w):
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - (fy + 1.0)) / ry) ** 2
                if d < 1.0:
                    out[y][x] = (*SHADOW_RGB, 114 if d < 0.48 else 58)

    for y in range(min(h, max_outline_y + 1)):
        for x in range(w):
            if body[y][x][3] == 255:
                continue
            nbs = []
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny <= min(h - 1, max_outline_y) and body[ny][nx][3] == 255:
                    nbs.append(body[ny][nx])
            if nbs:
                is_leaf = any(nb in FOLIAGE_SET for nb in nbs)
                out[y][x] = OUT_LEAF if is_leaf else OUT_STONE

    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c[3] == 255:
                out[y][x] = c
            elif c[3] > 0:
                put_alpha(out, x, y, c, c[3])
    return out


# ==============================================================================
# 1. Bell Spire (`bell_spire.png` & `_glow.png`, 2x1 of 96x160, waterline anchor (48, 136))
# ==============================================================================
def build_bell_spire_variant(awakened: bool):
    W, H = 96, 160
    CX, WY = 48, 136  # Waterline anchor
    seed = 3407
    body = blank(W, H)
    glow = GlowMap(W, H)

    # Precompute irregular ashlar course maps (NO flat mechanical %8/%6 grids!)
    lower_cmap = build_course_map(98, WY, 16, 80, [6, 5, 7, 5, 6, 7, 5], [9, 13, 8, 11, 10, 14], seed + 11)
    upper_cmap = build_course_map(48, 94, 20, 76, [5, 7, 6, 5, 6, 7, 5, 6], [8, 12, 9, 11, 13], seed + 29)

    # 1) Lower Flooded Stone Arcade, Corner Quoins, Sloped Buttresses & Stepped Plinth (`y = 98..135`)
    for y in range(98, WY):
        u = (y - 98) / float(WY - 98)
        # Main masonry shaft half-width + stepped plinth at `y >= 126` + side buttresses stepping out at `y = 110, 122`
        hw_shaft = 22 + (1 if y >= 114 else 0) + (2 if y >= 126 else 0) + (2 if y >= 131 else 0)
        butt_w = 2 if 104 <= y < 118 else (4 if 118 <= y < 129 else (5 if y >= 129 else 0))
        hw_tot = hw_shaft + butt_w

        for x in range(CX - hw_tot, CX + hw_tot + 1):
            dx_c = x - CX
            adx = abs(dx_c)

            # Pointed Gothic flooded water-arch (`cx = 48, apex at y = 105, half-width = 10.5` at waterline)
            dx_a = adx / 10.5
            dy_a = max(0.0, (124.0 - y) / 19.0)
            arch_d = dx_a + 0.56 * (dy_a ** 1.45)

            if y >= 105 and arch_d < 1.0:
                # Deep vaulted flooded undercroft interior visible through arch!
                if adx >= 6:
                    # Inner recessed wet arch jamb/pier (`x < CX` is shadowed inside left reveal; `x > CX` catches angled light!)
                    lit_in = 1.6 if dx_c < 0 else 2.8
                    if y >= 129:
                        put(body, x, y, SUB_STONE[2 if dx_c > 0 else 1])
                    else:
                        put(body, x, y, stone_tone(x, y, lit_in, seed + 3))
                elif y <= 113:
                    # Deep vaulted arch soffit shadow at top of flooded opening
                    put(body, x, y, STONE[0] if y <= 109 else STONE[1])
                continue

            # Carved wedge voussoir stone ring framing the flooded Gothic arch
            arch_outer = (adx / 13.8) + 0.56 * (max(0.0, (126.5 - y) / 21.5) ** 1.45)
            if y >= 101 and arch_outer < 1.06:
                ang_v = math.atan2(y - 125.0, dx_c)
                v_idx = int((ang_v + math.pi) * 9.5)
                v_frac = abs(((ang_v + math.pi) * 9.5) % 1.0)
                if v_frac < 0.13 or abs(arch_outer - 1.03) < 0.045:
                    put(body, x, y, MORTAR)
                else:
                    # Chamfered inner bevel on right jamb catches top-left light
                    chamfer = 1.1 if (arch_d < 1.15 and dx_c > 0) else (0.7 if dy_a > 0.55 and dx_c <= 2 else 0.0)
                    v_val = (5.2 if dx_c < 0 else 3.8) + chamfer + ((v_idx % 2) * 0.45 - 0.2)
                    put(body, x, y, stone_tone(x, y, v_val, seed + 5, damp=False))
                continue

            # Outer sloped buttress wings (`adx > hw_shaft`)
            if adx > hw_shaft:
                is_weathering = y in (104, 105, 118, 119, 129, 130)
                if is_weathering:
                    # Sloped stone water-table set-off catching bright top-left sky light!
                    put(body, x, y, STONE[7 if dx_c < 0 else 5] if y in (104, 118, 129) else STONE[5 if dx_c < 0 else 3])
                elif y in (106, 120, 131):
                    put(body, x, y, STONE[1])  # Overhang shadow beneath weathering slope
                else:
                    b_val = 5.4 if dx_c < 0 else 2.2
                    if y >= 132:
                        put(body, x, y, TEAL_MOSS[1 if dx_c < 0 else 0])
                    else:
                        put(body, x, y, ashlar_pixel(x, y, b_val, lower_cmap, seed + 13))
                continue

            # Dressed alternating long-and-short Corner Quoins along shaft edges!
            q_course = (y - 98) // 5
            q_width = 6 if (q_course % 2 == 0) else 4
            in_quoin = adx >= hw_shaft - q_width + 1 and y < 126
            if in_quoin:
                q_row = (y - 98) % 5
                if q_row == 4 or adx == hw_shaft - q_width + 1:
                    put(body, x, y, MORTAR)
                else:
                    q_val = (5.9 if dx_c < 0 else 3.1) + (0.9 if q_row == 0 else 0.0) + (0.6 if dx_c < 0 and adx == hw_shaft else 0.0)
                    put(body, x, y, stone_tone(x, y, q_val, seed + 17))
                continue

            # Stepped plinth ledge catch-edges (`y = 126, 131`) & wet algae-stained waterline masonry (`y >= 129`)
            if y in (126, 131):
                put(body, x, y, STONE[6 if dx_c < 0 else 4])
            elif y >= 131 and (fbm(x * 0.45, y * 0.55, seed + 19) > 0.36 or y >= 134):
                # Wet dark-emerald & teal algae band right above Lake Glockenteich!
                m_idx = 2 if (dx_c < 0 and y <= 133) else (1 if y <= 134 else 0)
                put(body, x, y, TEAL_MOSS[m_idx] if (x + y) % 3 == 0 else MOSS[m_idx])
            else:
                rel = dx_c / float(max(1, hw_shaft))
                base_v = 4.7 - 1.65 * rel - 0.35 * u
                put(body, x, y, ashlar_pixel(x, y, base_v, lower_cmap, seed + 11))

    # 2) Carved Stringcourse Cornice (`y = 93..98, x = 18..78`) with Waterspout Corbels!
    for y in range(93, 98):
        hw_c = 28 if y in (94, 95) else (26 if y in (93, 96) else 24)
        for x in range(CX - hw_c, CX + hw_c + 1):
            dx_c = x - CX
            if y == 93:
                put(body, x, y, STONE[7 if dx_c < 4 else 5])
            elif y == 94:
                # Staggered cornice block joints
                if (x - 20) % 11 == 0:
                    put(body, x, y, MORTAR)
                else:
                    put(body, x, y, stone_tone(x, y, 5.8 - 1.5 * (dx_c / 28.0), seed + 21, damp=False))
            elif y == 95:
                # Carved dentil molding row!
                dentil = (abs(dx_c) < 25) and (x % 3 == 0)
                put(body, x, y, MORTAR if dentil else STONE[4 if dx_c < 0 else 2])
            elif y == 96:
                put(body, x, y, STONE[1])
            else:
                put(body, x, y, MORTAR if abs(dx_c) < 23 else CLEAR)

    # Projecting chiseled waterspout/gargoyle corbels at `x = 17..20` & `x = 76..79, y = 94..96`
    for sx, is_l in [(18, True), (77, False)]:
        put(body, sx, 94, STONE[7 if is_l else 5])
        put(body, sx + (1 if is_l else -1), 94, STONE[6 if is_l else 4])
        put(body, sx, 95, STONE[3 if is_l else 2])
        put(body, sx + (1 if is_l else -1), 96, STONE[1])

    # 3) Upper Open Arched Belfry Chamber (`y = 48..93`) + Deep Vaulted Interior + Bronze Bell!
    # 3a) Deep vaulted belfry interior with recessed stone rib & dimly lit right inner wall (`x = 32..64, y = 51..91`)
    for y in range(51, 92):
        for x in range(32, 65):
            dx_b = abs(x - CX) / 15.5
            dy_b = max(0.0, (70.0 - y) / 19.0)
            if dx_b + 0.65 * (dy_b ** 1.5) < 1.02:
                # Inner vaulted ceiling at top (`y < 60`), dark back wall, recessed inner stone pier on right (`x >= 56`)
                if y < 58:
                    put(body, x, y, MORTAR if y < 55 else STONE[0])
                elif x >= 57:
                    # Inner right belfry wall catching diagonal top-left sunlight through the open window!
                    in_j = ((y - 52) % 6 == 0)
                    put(body, x, y, MORTAR if in_j else STONE[2 if x >= 59 else 1])
                else:
                    # Subtle vaulted inner arch rib in deep shadow
                    rib = abs(math.hypot((x - CX) * 1.0, (y - 72) * 0.72) - 11.5) < 0.8 and y < 74
                    put(body, x, y, STONE[1] if rib else STONE[0])

    # 3b) Heavy Carved Oak & Bronze Bell Yoke (`y = 54..59, x = 35..61`) + Iron Straps
    for y in range(55, 59):
        for x in range(36, 61):
            if y == 55 and 38 <= x <= 58:
                put(body, x, y, BRONZE[4 if x < CX else 2])
            elif y in (56, 57):
                # Iron suspension straps at `x in (42, 48, 54)`
                if x in (42, 48, 54):
                    put(body, x, y, GOLD_RIM[4 if y == 56 and x <= 48 else 2])
                else:
                    put(body, x, y, BRONZE[2 if y == 56 and x < CX else 1])
            elif y == 58 and 40 <= x <= 56:
                put(body, x, y, OUT_STONE)  # Cast shadow under yoke beam
    # Bell crown canons (`y = 58..60, x = 45..51`)
    for x in (45, 46, 48, 50, 51):
        put(body, x, 59, GOLD_RIM[3 if x <= 48 else 1])

    # 3c) Sculpted Verdigris-Bronze Ancient Bell (`y = 60..84`, flaring sound-bow `x = 35..61` at `y = 80..83`)!
    for y in range(60, 84):
        u_b = (y - 60) / 23.0
        hw_bell = 5.4 + 3.1 * (u_b ** 0.68) + 5.2 * max(0.0, (u_b - 0.56) / 0.44) ** 1.85
        x0_b, x1_b = int(round(CX - hw_bell)), int(round(CX + hw_bell))
        for x in range(x0_b, x1_b + 1):
            rel_b = (x - CX) / max(1.0, hw_bell)
            # Crisp cylindrical + flared specular highlight at `rel_b ≈ -0.45`, core shadow at `rel_b ≈ +0.55`, weak rim bounce at `+0.9`
            spec = math.exp(-((rel_b + 0.45) ** 2) / 0.14)
            core_sh = math.exp(-((rel_b - 0.52) ** 2) / 0.22)
            bounce = 0.22 * max(0.0, rel_b - 0.65) / 0.35
            lit_b = 0.36 + 0.58 * spec - 0.34 * core_sh + bounce - 0.10 * u_b
            if y == 60:
                lit_b -= 0.22  # Yoke shadow across crown
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.36

            if y == 83:
                # Dark hollow underside of bell mouth with aged-gold front lip!
                col_b = GOLD_RIM[3 if abs(rel_b) > 0.72 else 0] if abs(rel_b) > 0.55 else BRONZE[0]
            elif y in (80, 81, 82):
                # Burnished aged-gold sound-bow rim + casting fillet!
                rim_boost = 0.22 if y == 80 else (-0.12 if y == 82 else 0.05)
                col_b = GOLD_RIM[int(clamp((lit_b + rim_boost) * 5.6 + dith, 0, 5))]
            elif y in (64, 67):
                # Raised cast-bronze horizontal inscription fillets
                col_b = GOLD_RIM[int(clamp((lit_b + 0.10) * 5.0 + dith, 0, 4))]
            elif y in (65, 66):
                # Embossed relief chevron/rune frieze band!
                emboss = ((x + y) % 3 == 0)
                col_b = GOLD_RIM[int(clamp((lit_b + (0.20 if emboss else -0.18)) * 4.8, 0, 5))]
            else:
                # Weathered verdigris-patinated bronze waist with vertical patina streaks & tarnished bronze shadow!
                patina = fbm(x * 0.65, y * 0.18, seed + 33) + (0.22 if rel_b < 0.15 else -0.15)
                if patina > 0.44:
                    col_b = VERDIGRIS[int(clamp(lit_b * 7.6 + dith, 1, 7))]
                else:
                    col_b = BRONZE[int(clamp(lit_b * 5.8 + dith, 1, 5))]
            put(body, x, y, col_b)

    # Incised harmonic glyph on bell waist (dark bronze recess in Col 0; awakened radiant glyph in Col 1)
    bell_glyph = [(0, -2), (0, -1), (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (0, 1), (-1, 2), (1, 2)]
    for gx, gy in bell_glyph:
        put(body, CX + gx, 73 + gy, BRONZE[1] if not awakened else TEAL_L)

    # Heavy bronze clapper sphere peeking below bell mouth at `(48, 83..86)`
    for dy in range(0, 4):
        for dx in range(-2, 3):
            if dx * dx + (dy - 1.2) ** 2 <= 4.6:
                put(body, CX + dx, 83 + dy, GOLD_RIM[5 if (dx <= 0 and dy <= 1) else (3 if dx <= 1 else 1)])

    # 3d) Outer Belfry Masonry Shaft, Corner Quoins, Impost Capitals, Balustrade Sill & Pointed Archivolt (`y = 48..92`)
    for y in range(48, 93):
        hw_ch = 23 + (1 if y <= 51 or y >= 88 else 0)
        q_course = (y - 48) // 5
        q_width = 6 if (q_course % 2 == 1) else 4

        for x in range(CX - hw_ch, CX + hw_ch + 1):
            dx_c = x - CX
            adx = abs(dx_c)

            # Open pointed Gothic bell window (`y = 53..88`, `adx < 13.8` at jambs)
            dx_o = adx / 13.8
            dy_o = max(0.0, (69.0 - y) / 16.5)
            arch_val = dx_o + 0.65 * (dy_o ** 1.5)
            arch_outer = (adx / 17.2) + 0.65 * (max(0.0, (71.5 - y) / 19.0) ** 1.5)

            if 53 <= y <= 88 and arch_val < 0.98:
                continue  # Keep open window clear so vaulted interior & bell show cleanly!

            # Moulded stone balustrade sill at bottom of bell opening (`y = 89..92, adx <= 15`)
            if 89 <= y <= 92 and adx <= 15:
                if y == 89:
                    put(body, x, y, STONE[7 if dx_c < 2 else 5])
                elif y in (90, 91):
                    baluster = (adx % 4 == 0)
                    put(body, x, y, MORTAR if baluster else STONE[4 if dx_c < 0 else 2])
                else:
                    put(body, x, y, STONE[2])
                continue

            # Carved impost capitals at `y = 68..70` where pointed arch springs from jamb piers!
            if 68 <= y <= 70 and 13 <= adx <= 18:
                put(body, x, y, STONE[7 if (y == 68 and dx_c < 0) else (5 if y == 68 else (3 if y == 69 else 1))])
                continue

            # Pointed Gothic voussoir archivolt (`y = 49..68`) + chamfered jamb blocks (`y = 71..88, 13 <= adx <= 16`)
            if (49 <= y <= 68 and arch_outer < 1.04) or (71 <= y <= 88 and adx <= 16):
                if y <= 68:
                    ang_a = math.atan2(y - 70.0, dx_c)
                    v_i = int((ang_a + math.pi) * 10.5)
                    v_f = abs(((ang_a + math.pi) * 10.5) % 1.0)
                    is_j = v_f < 0.13 or abs(arch_outer - 1.01) < 0.04
                    chamfer = 1.0 if (arch_val < 1.12 and dx_c > 0) else (0.75 if y <= 52 and dx_c <= 2 else 0.0)
                    put(body, x, y, MORTAR if is_j else stone_tone(x, y, (5.5 if dx_c < 0 else 4.0) + chamfer + (v_i % 2) * 0.4, seed + 25, damp=False))
                else:
                    j_row = (y - 71) % 6
                    chamfer = 1.0 if (adx <= 14 and dx_c > 0) else (-0.6 if adx <= 14 and dx_c < 0 else 0.0)
                    put(body, x, y, MORTAR if j_row == 5 else stone_tone(x, y, (5.2 if dx_c < 0 else 3.8) + chamfer + (0.6 if j_row == 0 else 0.0), seed + 27))
                continue

            # Corner Quoins on upper belfry piers
            if adx >= hw_ch - q_width + 1 and 50 <= y <= 88:
                q_row = (y - 48) % 5
                if q_row == 4 or adx == hw_ch - q_width + 1:
                    put(body, x, y, MORTAR)
                else:
                    qv = (6.0 if dx_c < 0 else 3.2) + (0.85 if q_row == 0 else 0.0) + (0.55 if dx_c < 0 and adx == hw_ch else 0.0)
                    put(body, x, y, stone_tone(x, y, qv, seed + 31))
                continue

            # Under-eaves shadow at `y = 48..49` + irregular ashlar masonry
            rel = dx_c / float(max(1, hw_ch))
            base_v = 4.9 - 1.75 * rel - (1.2 if y == 48 else (0.5 if y == 49 else 0.0))
            put(body, x, y, ashlar_pixel(x, y, base_v, upper_cmap, seed + 29))

    # Structural masonry cracks & weathered corner chips on belfry shaft!
    carve_crack(body, [(28, 72), (28, 73), (29, 74), (29, 75), (30, 76), (30, 77), (29, 78)], seed + 41, lit_side=1)
    carve_crack(body, [(64, 102), (65, 103), (65, 104), (66, 105), (66, 106), (67, 107)], seed + 43, lit_side=-1)
    carve_crack(body, [(26, 111), (27, 112), (27, 113), (28, 114), (28, 115)], seed + 45, lit_side=1)
    chip_silhouette(body, 25, 62, 1, is_left=True)
    chip_silhouette(body, 71, 77, 1, is_left=False)
    chip_silhouette(body, 26, 108, 1, is_left=True)

    # Pale-sage crust lichen colonies on masonry piers
    sprinkle_lichen(body, [(27, 65, 3), (66, 83, 3), (28, 119, 4), (67, 115, 3), (30, 86, 2)], seed + 49)

    # 4) Overlapping Weathered Diamond / Fish-Scale Slate & Verdigris-Copper Spire Roof (`y = 13..47`)!
    # Moulded stone & verdigris-copper flaring eaves gutter (`y = 46..47, x = 19..77`)
    for x in range(19, 78):
        dx_e = x - CX
        put(body, x, 46, VERDIGRIS[6 if dx_e < -4 else (5 if dx_e < 10 else 3)])
        put(body, x, 47, STONE[3 if dx_e < 0 else 1] if x % 4 != 0 else MORTAR)

    # Build shingle course boundaries top -> bottom (`3 px` tall near apex, `4 px` tall on mid/lower slopes)
    sh_courses = []
    sy = 13
    sci = 0
    while sy < 46:
        sh_h = 3 if sy < 25 else 4
        sh_courses.append((sci, sy, min(46, sy + sh_h)))
        sy += sh_h
        sci += 1

    for sci, sy0, sy1 in sh_courses:
        ch_s = max(1, sy1 - sy0)
        for y in range(sy0, sy1):
            t_s = (y - 13) / 33.0
            # Concave flaring witch-hat / belfry spire silhouette (`x = 47..49` at apex -> `x = 19..77` at eaves)
            hw_sp = 1.1 + 21.0 * (t_s ** 1.08) + 6.8 * (max(0.0, (t_s - 0.68) / 0.32) ** 1.85)
            r_in = y - sy0
            # Scale width adapts smoothly with cone width so diamond/fish-scale tiles converge toward apex
            tile_w = 3.2 if sy0 < 22 else (4.2 if sy0 < 33 else 5.2)
            stagger = (sci % 2) * 0.5

            x0_s, x1_s = int(round(CX - hw_sp)), int(round(CX + hw_sp))
            for x in range(x0_s, x1_s + 1):
                dx_s = x - CX
                rel_s = dx_s / max(1.0, hw_sp)

                # Octagonal spire facets: sunlit left (`rel_s < -0.34`), lit front-left (`-0.34..0.0`),
                # mid-shaded front-right (`0.0..0.38`), deep cool right (`> 0.38`) + octagonal hip ridges!
                on_hip = abs(abs(rel_s) - 0.36) < (0.06 if hw_sp > 8 else 0.0)
                if rel_s < -0.36:
                    f_lit = 0.80
                elif rel_s < 0.0:
                    f_lit = 0.64
                elif rel_s < 0.36:
                    f_lit = 0.44
                else:
                    f_lit = 0.24

                # Staggered fish-scale / diamond shingle cell coordinates
                u_tile = (dx_s / tile_w) + stagger
                ti = math.floor(u_tile)
                tf = u_tile - ti  # 0.0 -> 1.0 across single shingle width
                center_dist = abs(tf - 0.5) * 2.0  # 0 at scale center, 1 at side seam

                # Diamond / curved fish-scale bottom lip & side overlap seam!
                is_seam = (center_dist > 0.78 and r_in < ch_s - 1) or (r_in == ch_s - 1 and center_dist > 0.48)
                is_under_shadow = (r_in == 0 and center_dist < 0.65 and sci > 0)
                is_top_bevel = (r_in == 1 and tf < 0.58) or (r_in == ch_s - 1 and center_dist <= 0.45 and rel_s < 0.25)

                sh_mod = (hsh(ti, sci, seed + 53) - 0.5) * 0.14
                if is_seam:
                    lit = f_lit - 0.26
                elif is_under_shadow:
                    lit = f_lit - 0.20
                elif is_top_bevel:
                    lit = f_lit + (0.16 if rel_s < 0.15 else 0.08)
                else:
                    lit = f_lit + sh_mod
                if on_hip:
                    lit += 0.14 if dx_s < 0 else -0.06

                # Copper courses (apex cap `sci <= 2`, mid decorative band `sci == 5`, eaves band `sci == len-1`)
                # + individual replaced copper shingles + vertical oxidized turquoise patina drips!
                is_copper_tile = (sci <= 2) or (sci == 5) or (sci == len(sh_courses) - 1) or (hsh(ti, sci, seed + 59) > 0.76)
                drip_src = hsh(int(round(dx_s / 3.0)), 0, seed + 61)
                in_patina_drip = (drip_src > 0.66) and (y < 24 + int((drip_src - 0.66) * 62.0)) and ((y + x) % 5 != 0)

                dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.32
                if is_copper_tile or in_patina_drip:
                    v_idx = int(clamp(lit * 7.6 + (0.7 if in_patina_drip and not is_seam else 0.0) + dith, 0, 7))
                    col_r = VERDIGRIS[v_idx]
                else:
                    s_idx = int(clamp(lit * 6.6 + dith, 0, 6))
                    # Subtle cool sky rim bounce on far-right slate edge
                    if x == x1_s and s_idx <= 2 and y > 22 and y % 2 == 0:
                        col_r = RIM_COOL[0]
                    else:
                        col_r = SLATE_ROOF[s_idx]
                put(body, x, y, col_r)

    # Ornate Miniature Carved Gablet / Lucarne at front center of eaves (`x = 42..54, y = 37..47`)!
    for y in range(37, 48):
        hw_g = int((y - 37) * 0.62)
        for x in range(CX - hw_g, CX + hw_g + 1):
            dx_g = x - CX
            if abs(dx_g) >= hw_g - 1 or y <= 39:
                # Chiseled stone gablet coping
                put(body, x, y, STONE[7 if dx_g <= 0 else 4])
            elif y >= 42 and abs(dx_g) <= 2:
                # Tiny trefoil/lancet vent niche inside gablet
                put(body, x, y, MORTAR if y < 47 else STONE[2])
            else:
                put(body, x, y, STONE[5 if dx_g < 0 else 3])

    # Lush moss tufts & hanging tendrils on spire eaves & lower stringcourse cornice!
    drape_moss(body, 21, 37, 45, 2, 3, seed + 71)
    drape_moss(body, 58, 74, 45, 2, 3, seed + 73)
    drape_moss(body, 20, 39, 93, 2, 5, seed + 75)
    drape_moss(body, 58, 76, 93, 2, 4, seed + 77)

    # 5) Crisp Ornate Cast-Bronze Crescent Finial (`y = 3..13, cx = 48`)!
    # Molded base collar (`y = 12..13`) + faceted bronze orb (`y = 9..11`)
    for dx in (-2, -1, 0, 1, 2):
        if abs(dx) <= 2:
            put(body, CX + dx, 13, BRONZE[4 if dx < 0 else 2])
        if abs(dx) <= 1:
            put(body, CX + dx, 12, GOLD_RIM[4 if dx <= 0 else 2])
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if abs(dx) + abs(dy) <= 2:
                put(body, CX + dx, 10 + dy, GOLD_RIM[5 if (dx <= 0 and dy <= 0) else 2])
    # Sculpted upward-sweeping bronze crescent moon (`y = 3..9, x = 43..53`)
    for y in range(3, 10):
        for x in range(43, 54):
            dx, dy = x - CX, y - 6.5
            ro = math.hypot(dx, dy)
            ri = math.hypot(dx - 1.15, dy + 1.45)
            if ro <= 4.35 and ri >= 2.65:
                is_spec = (dx <= 0 and dy <= 0.5) or (ro >= 3.4 and dx < 1)
                put(body, x, y, GOLD_RIM[5 if is_spec else (4 if dx <= 1 else 2)])

    # Apply crisp 1px dark outline ONLY down to the waterline (`max_outline_y = WY - 1 = 135`)!
    # Everything at/below `y = 136` dissolves softly into Lake Glockenteich with ZERO dark outline!
    framed = finish_prop(body, cx=CX, fy=WY, rx=0.0, ry=0.0, max_outline_y=WY - 1, draw_shadow=False)

    # 6) Submerged Algae-Stained Stone Piers & Organic Refracted Dissolution (`y = 135..152`, ZERO outline!)
    for y in range(WY - 1, 153):
        refract = 0.9 * math.sin(y * 1.3 + 0.4)
        for x in range(CX - 31, CX + 32):
            dx_w = (x - CX) - refract
            adx_w = abs(dx_w)
            # Keep central flooded archway channel open underwater; taper outer buttresses sooner than main piers!
            if adx_w < 8.8 or adx_w > 30.0:
                if 7.2 <= adx_w < 8.8 and y < WY + 8:
                    put_alpha(framed, x, y, SUB_STONE[1], int(120 * (1.0 - (y - WY) / 9.0)))
                continue
            # Column-specific underwater fade depth: deepest (`15 px`) under core piers (`adx ~ 16`), shorter at outer toes
            pier_profile = 1.0 - min(1.0, abs(adx_w - 17.5) / 13.5) ** 1.5
            max_d = 6.5 + 9.0 * pier_profile + 1.5 * math.sin(x * 0.55)
            d_rows = y - (WY - 1)
            if d_rows > max_d:
                continue
            u_sub = d_rows / max(1.0, max_d)
            alpha_sub = int(clamp((1.0 - u_sub ** 1.15) * 238, 0, 238))
            joint_u = ((y - WY) % 4 == 3) or (int(round(x + refract)) % 9 == 0)
            s_idx = 0 if joint_u else int(clamp((1.0 - u_sub) * 3.9 + (0.65 if dx_w < 0 else -0.25), 0, 4))
            put_alpha(framed, x, y, SUB_STONE[s_idx], alpha_sub)

    # 7) Curved 3/4 Turquoise-Aqua Water-Lap Ripples (`y = 134..151`) + Dormant vs Awakened Glow!
    # Continuous curved meniscus hugging each submerged pier (`cx = 30.5` left pier & `cx = 65.5` right pier)
    for pier_cx in (30.5, 65.5):
        for deg in range(-15, 195, 5):
            th = math.radians(deg)
            wx = int(round(pier_cx + math.cos(th) * 11.8))
            wy = int(round((WY + 0.4) + math.sin(th) * 2.8))
            is_foam = (deg % 25 == 0) and (15 <= deg <= 165)
            put_alpha(framed, wx, wy, WATER_LAP[4 if is_foam else 3], 215 if 10 <= deg <= 170 else 135)
            put_alpha(framed, wx, wy + 1, WATER_LAP[1], 130)
    # Gentle inner wavelet inside the flooded arch (`x = 40..56`)
    for x in range(40, 57):
        wy_in = WY + (1 if abs(x - CX) < 5 else 0)
        put_alpha(framed, x, wy_in, WATER_LAP[2 if x % 2 == 0 else 1], 145)

    if not awakened:
        # Col 0 (Dormant): curved 3/4 elliptical lapping wave arcs around the sunken belfry!
        for ring_rx, ring_ry, base_a, step_d in [(32.5, 5.2, 175, 3), (38.5, 7.8, 120, 4)]:
            for deg in range(10, 171, step_d):
                th = math.radians(deg)
                # Leave calm natural breaks along the elliptical wavelets so they read as gentle lapping arcs
                if (deg // 18) % 3 == 1:
                    continue
                wx = int(round(CX + math.cos(th) * ring_rx))
                wy = int(round(WY + 1.6 + math.sin(th) * ring_ry))
                put_alpha(framed, wx, wy, WATER_LAP[3 if deg % 12 == 0 else 2], base_a)
                put_alpha(framed, wx, wy + 1, WATER_LAP[0], base_a // 2)

        # Subtle moonlight glints on dormant bell & crescent finial
        glow.emit(framed, CX - 4, 71, VERDIGRIS[6], TEAL_L, halo=1)
        glow.emit(framed, CX - 3, 80, GOLD_RIM[5], GOLD_RIM[5], halo=1)
        glow.emit(framed, 46, 5, GOLD_RIM[5], GOLD_RIM[5], halo=1)
    else:
        # Col 1 (Awakened Midnight Toll): Luminous concentric harmonic water rings + awakened belfry & bell runes!
        for ring_i, (ring_rx, ring_ry) in enumerate([(33.5, 5.8), (42.5, 9.2)]):
            for deg in range(0, 360, 2):
                th = math.radians(deg)
                if math.sin(th) < -0.20:
                    continue  # Wrap naturally around front & sides of sunken spire
                wx = int(round(CX + math.cos(th) * ring_rx))
                wy = int(round(WY + 2.0 + math.sin(th) * ring_ry))
                if 2 <= wx < W - 2 and 2 <= wy < H - 2:
                    put_alpha(framed, wx, wy + 1, WATER_LAP[1], 140)
                    if deg % 10 != 0:
                        is_node = (deg % 30 == 0)
                        c_base = GOLD_GLOW if (is_node and ring_i == 0) else WATER_LAP[3]
                        c_glow = GOLD_HOT if (is_node and ring_i == 0) else (TEAL_HOT if deg % 20 == 0 else TEAL_L)
                        glow.emit(framed, wx, wy, c_base, c_glow, halo=1)

        # Awakened harmonic runes along upper Gothic archivolt, gablet & lower water-arch!
        rune_arch_pts = [
            (32, 82), (32, 74), (33, 65), (36, 57), (41, 51), (48, 43),
            (55, 51), (60, 57), (63, 65), (64, 74), (64, 82),
            (35, 118), (37, 109), (48, 103), (59, 109), (61, 118),
        ]
        for i_r, (rx_p, ry_p) in enumerate(rune_arch_pts):
            is_g = (i_r in (0, 5, 10, 13))
            glow.emit(framed, rx_p, ry_p, GOLD_GLOW if is_g else TEAL_L, GOLD_HOT if is_g else TEAL_HOT, halo=2 if i_r == 5 else 1)

        # Radiant harmonic glyph on bell waist, embossed inscription band, sound-bow rim, clapper & crescent finial!
        for gx, gy in bell_glyph:
            is_core = (gx == 0 and gy == 0)
            glow.emit(framed, CX + gx, 73 + gy, GOLD_HOT if is_core else TEAL_L, GOLD_HOT if is_core else TEAL_HOT, halo=2 if is_core else 1)
        for bx_r in range(38, 59, 3):
            glow.emit(framed, bx_r, 81, GOLD_GLOW, GOLD_HOT if abs(bx_r - CX) <= 4 else TEAL_L, halo=1)
        for bx_r in range(42, 55, 3):
            glow.emit(framed, bx_r, 65, TEAL_L, TEAL_HOT, halo=1)
        glow.emit(framed, CX, 85, GOLD_HOT, GOLD_HOT, halo=2)
        glow.emit(framed, CX, 84, GOLD_GLOW, GOLD_HOT, halo=1)
        glow.emit(framed, 46, 5, GOLD_HOT, GOLD_HOT, halo=2)
        glow.emit(framed, 48, 10, GOLD_GLOW, GOLD_HOT, halo=1)

    return framed, glow.finish()


# ==============================================================================
# 2. Bell Stepping Stones (`bell_stepping_stone.png` & `_glow.png`, 3x1 of 32x32, center (16, 18))
# ==============================================================================
def build_bell_stepping_stones():
    FW, FH = 32, 32
    CX, CY = 16, 18
    frames = []
    glows = []

    # Col 0: Refracted octagonal carved stone silhouette beneath the lake surface (translucent, ZERO dark outline!)
    sub = blank(FW, FH)
    sub_gl = GlowMap(FW, FH)
    for y in range(10, 26):
        refract = 0.55 * math.sin(y * 1.2)
        for x in range(4, 28):
            dx = abs(x + 0.5 - (CX + refract)) / 10.6
            dy = abs(y + 0.5 - CY) / 6.8
            oct_d = max(dx, dy, (dx + dy) * 0.74)
            if oct_d <= 1.0:
                # Underwater octagonal bevel + faint sunken spiral groove
                in_groove = abs(math.hypot((x - CX) * 0.8, (y - CY) * 1.2) - 3.2) < 0.75
                s_idx = 0 if in_groove else (3 if (oct_d > 0.72 and x < CX and y < CY) else (2 if oct_d < 0.72 else 1))
                alpha = 188 if oct_d < 0.68 else (142 if oct_d < 0.88 else 88)
                put_alpha(sub, x, y, SUB_STONE[s_idx], alpha)
    # Delicate surface water glints above submerged slab
    for rx, ry, c_i, al in [(11, 14, 2, 130), (12, 14, 3, 155), (13, 14, 2, 120), (19, 20, 2, 125), (20, 20, 3, 145)]:
        put_alpha(sub, rx, ry, WATER_LAP[c_i], al)
    frames.append(sub)
    glows.append(sub_gl.finish())

    # Cols 1 & 2: Chiseled Octagonal Stepping Slabs with Incised Runes & Soft Water-Lap Skirt!
    for var_idx in (1, 2):
        seed = 3611 + var_idx * 37
        body = blank(FW, FH)
        gl = GlowMap(FW, FH)

        # 8-sided chiseled stone plateau (`cy = 16.0, rx = 10.8, ry = 5.8`) + 3/4 stone thickness (`y = 17..23`)
        for y in range(9, 24):
            for x in range(4, 28):
                dx = (x + 0.5 - CX) / 10.8
                dy_t = (y + 0.5 - 16.0) / 5.8
                oct_t = max(abs(dx), abs(dy_t), (abs(dx) + abs(dy_t)) * 0.73)

                dy_b = (y + 0.5 - 19.8) / 5.8
                oct_b = max(abs(dx), abs(dy_b), (abs(dx) + abs(dy_b)) * 0.73)

                if oct_t <= 1.0:
                    # Raised outer octagonal bevel rim (`0.78 <= oct_t <= 1.0`) + recessed rune dish (`oct_t < 0.78`)
                    if oct_t >= 0.78:
                        val = 5.8 - 1.4 * dx - 1.5 * dy_t + (0.9 if (dx < 0.2 and dy_t < 0.1) else 0.0)
                    else:
                        # Subtle inner recessed ring shadow on top-left (`oct_t > 0.68` and `dx + dy_t < 0`)
                        rim_sh = -1.1 if (oct_t > 0.66 and (dx + dy_t) < -0.15) else 0.0
                        val = 4.6 - 1.0 * dx - 1.1 * dy_t + rim_sh
                    put(body, x, y, stone_tone(x, y, val, seed, damp=False))
                elif y >= 16 and oct_b <= 1.0:
                    # Planar 3/4 octagonal vertical kerb facets (left facet lit, center mid, right dark) + wet algae at bottom!
                    if y >= 21:
                        put(body, x, y, TEAL_MOSS[1 if dx < -0.2 else 0] if y == 21 else SUB_STONE[2 if dx < 0 else 1])
                    else:
                        f_v = 4.4 if dx < -0.35 else (3.1 if dx < 0.35 else 1.8)
                        # Block joint on front octagonal corner
                        if abs(abs(dx) - 0.36) < 0.08:
                            put(body, x, y, MORTAR)
                        else:
                            put(body, x, y, stone_tone(x, y, f_v, seed + 3, damp=False))

        # Chipped bevel corners & hairline radial crack
        if var_idx == 1:
            chip_silhouette(body, 25, 13, 1, is_left=False)
            chip_silhouette(body, 7, 18, 1, is_left=True)
            carve_crack(body, [(21, 15), (22, 16), (23, 17), (23, 18)], seed + 7, lit_side=-1)
        else:
            chip_silhouette(body, 7, 13, 1, is_left=True)
            chip_silhouette(body, 25, 18, 1, is_left=False)
            carve_crack(body, [(9, 16), (10, 17), (10, 18), (11, 19)], seed + 9, lit_side=1)

        # Moss cushions on upper-left & side corners
        drape_moss(body, 7, 13, 11, 2, 1, seed + 13)
        if var_idx == 2:
            drape_moss(body, 19, 24, 12, 2, 1, seed + 17)
        sprinkle_lichen(body, [(22, 14, 2) if var_idx == 1 else (10, 18, 2)], seed + 19)

        # Deeply incised ancient rune (dark chisel shadow + bright catch bevel + luminous core!)
        if var_idx == 1:
            spiral_pts = [(0, 0), (1, 0), (1, -1), (0, -2), (-1, -2), (-2, -1), (-3, 0), (-2, 1), (0, 2), (2, 2), (3, 1)]
            for dx, dy in spiral_pts:
                if get_a(body, CX + dx + 1, 16 + dy + 1) == 255:
                    put(body, CX + dx + 1, 16 + dy + 1, STONE[7])
                if get_a(body, CX + dx - 1, 16 + dy) == 255:
                    put(body, CX + dx - 1, 16 + dy, MORTAR)
            for i_p, (dx, dy) in enumerate(spiral_pts):
                gl.emit(body, CX + dx, 16 + dy, TEAL_L if i_p < 4 else TEAL, TEAL_HOT if i_p == 0 else TEAL_L, halo=1)
        else:
            wave_pts = [(-2, 0), (2, 0), (-1, -1), (0, -1), (1, -1), (-3, 1), (0, 2), (3, 1), (-4, 0), (4, 0)]
            for dx, dy in [(0, 0)] + wave_pts:
                if get_a(body, CX + dx, 16 + dy + 1) == 255:
                    put(body, CX + dx, 16 + dy + 1, STONE[7])
                if get_a(body, CX + dx, 16 + dy - 1) == 255:
                    put(body, CX + dx, 16 + dy - 1, MORTAR)
            gl.emit(body, CX, 16, GOLD_HOT, GOLD_HOT, halo=1)
            for dx, dy in wave_pts:
                gl.emit(body, CX + dx, 16 + dy, TEAL_L, TEAL_HOT if dy == -1 else TEAL_L, halo=1)

        # Outline ONLY dry upper stone (`max_outline_y = 20`); below `y = 20` transitions softly into water!
        framed = finish_prop(body, cx=CX, fy=21, rx=0.0, ry=0.0, max_outline_y=20, draw_shadow=False)

        # Underwater refracted stone foot (`y = 21..25`) + tight translucent aqua water-lap skirt (`y = 19..26`)
        for y in range(21, 26):
            u_d = (y - 21) / 4.0
            hw_u = int(round(10.0 - u_d * 3.0))
            for x in range(CX - hw_u, CX + hw_u + 1):
                put_alpha(framed, x, y, SUB_STONE[2 if abs(x - CX) < 5 else 1], int(155 * (1.0 - u_d * 0.72)))

        for deg in range(-12, 193, 4):
            th = math.radians(deg)
            wx = int(round(CX + math.cos(th) * 11.2))
            wy = int(round(19.4 + math.sin(th) * 4.8))
            is_crest = deg in (32, 88, 144)
            put_alpha(framed, wx, wy, WATER_LAP[4 if is_crest else 3], 215 if 12 <= deg <= 168 else 125)
            put_alpha(framed, wx, wy + 1, WATER_LAP[1], 115)
            if is_crest:
                gl.emit(None, wx, wy, None, TEAL_L, halo=0)
        # Soft outer secondary ripple arc
        for deg in range(24, 157, 6):
            if 72 <= deg <= 108:
                continue
            th = math.radians(deg)
            put_alpha(framed, int(round(CX + math.cos(th) * 12.6)), int(round(20.4 + math.sin(th) * 5.6)), WATER_LAP[2], 92)

        frames.append(framed)
        glows.append(gl.finish())

    return frames, glows


# ==============================================================================
# 3. Sleeping Guardians (`sleeping_guardian.png` & `_glow.png`, 3x1 of 80x128, feet (40, 116))
# ==============================================================================
def build_guardian_plinth(body, glow: GlowMap, FX: int, FY: int, variant: int, seed: int):
    """Builds a chiseled two-tier multi-block ashlar pedestal (`y = 98..116`) with chipped corners & runes."""
    # Upper tier (`y = 98..106, x = 18..62`) & Lower tier (`y = 106..116, x = 14..66`)
    upper_joints = {0: [29, 44, 54], 1: [27, 40, 52], 2: [31, 46]}[variant]
    lower_joints = {0: [24, 37, 50, 59], 1: [23, 35, 48, 58], 2: [26, 39, 53]}[variant]

    for y in range(98, 117):
        in_upper = y < 106
        x0, x1 = (18, 62) if in_upper else (14, 66)
        joints = upper_joints if in_upper else lower_joints
        y_top = 98 if in_upper else 106

        for x in range(x0, x1 + 1):
            dx_c = x - FX
            rel = dx_c / float(max(1, (x1 - x0) // 2))
            bi = sum(1 for j in joints if x >= j)
            prev_j = max([j for j in joints if x >= j], default=-999)

            if y == 105 and in_upper:
                put(body, x, y, MORTAR)
            elif x in joints and y > y_top:
                put(body, x, y, MORTAR if hsh(x, y, seed + 3) < 0.85 else STONE[1])
            elif y == y_top:
                # Chamfered sunlit horizontal plinth ledge!
                put(body, x, y, STONE[7 if dx_c < 4 else (6 if dx_c < 16 else 4)])
            elif y == y_top + 1:
                put(body, x, y, STONE[6 if dx_c < -2 else (5 if dx_c < 12 else 3)])
            else:
                # Planar stone block face with incised geometric dado recess in center of blocks
                blk_bias = (hsh(bi, 1 if in_upper else 2, seed + 5) - 0.5) * 0.75
                catch_l = 0.65 if x == prev_j + 1 else 0.0
                ao_bot = -0.85 if y >= 115 else 0.0
                val = (4.6 if in_upper else 4.2) - 1.55 * rel + blk_bias + catch_l + ao_bot
                put(body, x, y, stone_tone(x, y, val, seed + 7))

    # Incised dark rune sockets on upper plinth blocks + glowing violet/teal plinth runes
    rune_xs = [24, 56] if variant == 0 else ([33, 47] if variant == 1 else [34])
    for rx in rune_xs:
        put(body, rx - 1, 102, MORTAR)
        put(body, rx + 1, 103, STONE[6])
        glow.emit(body, rx, 102, MOSAIC_VIO[2], VIO_GLOW if variant != 2 else TEAL, halo=1)

    # Distinct weathered corner chips on each pedestal
    if variant == 0:
        chip_silhouette(body, 62, 98, 2, is_left=False)
        chip_silhouette(body, 14, 107, 1, is_left=True)
    elif variant == 1:
        chip_silhouette(body, 18, 98, 2, is_left=True)
        chip_silhouette(body, 66, 107, 2, is_left=False)
    else:
        chip_silhouette(body, 62, 99, 3, is_left=False)
        chip_silhouette(body, 18, 99, 2, is_left=True)
        chip_silhouette(body, 66, 107, 2, is_left=False)


def planar_robe_val(rel: float) -> float:
    """Quantizes cylindrical horizontal coordinate `rel in [-1..1]` into crisp chiseled monolithic stone facets."""
    if rel < -0.62:
        return 5.8
    if rel < -0.22:
        return 5.1
    if rel < 0.20:
        return 4.1
    if rel < 0.60:
        return 3.0
    return 1.9


def build_sleeping_guardian(variant: int):
    W, H = 80, 128
    FX, FY = 40, 116
    seed = 3809 + variant * 53
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Chiseled Multi-Block Pedestal (`y = 98..116`)
    build_guardian_plinth(body, glow, FX, FY, variant, seed)

    if variant == 0:
        # ---- Col 0: Towering Chiseled Robed Guardian (~99 px tall: y = 17..116) with 5-Peak Crown, Mantle & Tower-Shield!
        # A) Planar Fluted Monolith Robes & Chamfered Shoulder Pauldrons (`y = 41..97`)
        pleat_xs = (-15, -10, -5, 5, 10, 15)
        for y in range(41, 98):
            u = (y - 41) / 56.0
            in_mantle = y <= 55
            if in_mantle:
                # Chamfered stone pauldron top slope (`y = 41..45`) rather than boxy rectangle!
                hw = (15.5 + (y - 41) * 1.8) if y < 44 else (21.5 - 0.22 * max(0, y - 48))
            else:
                hw = 17.2 + 1.8 * u
            x0, x1 = int(round(FX - hw)), int(round(FX + hw))

            for x in range(x0, x1 + 1):
                dx = x - FX
                rel = dx / max(1.0, hw)

                # Staggered megalithic block drum seams at `y = 69` and `y = 84`
                if y in (69, 84) and abs(dx) > 9 and hsh(x // 3, y, seed + 9) < 0.78:
                    put(body, x, y, MORTAR if dx > 0 else STONE[2])
                    continue

                if in_mantle:
                    if y == 55 and abs(dx) > 7:
                        put(body, x, y, MORTAR)  # Deep undercut shadow below mantle hem
                    elif y == 54 and abs(dx) > 7:
                        notch = (x % 3 == 0)
                        put(body, x, y, STONE[2 if notch else (6 if dx < 0 else 4)])
                    else:
                        f_v = planar_robe_val(rel) + (1.05 if y <= 44 and abs(dx) > 9 and dx < 0 else 0.0)
                        if abs(abs(dx) - (11 + (y - 41) * 0.4)) < 0.65:
                            f_v += 0.85 if dx < 0 else -0.75
                        put(body, x, y, stone_tone(x, y, f_v, seed + 11))
                else:
                    f_v = planar_robe_val(rel) + (0.65 if y in (70, 85) and dx < 6 else 0.0)
                    if y == 56 and abs(dx) > 7:
                        f_v -= 1.25
                    if dx in pleat_xs:
                        put(body, x, y, STONE[1] if dx > 0 else STONE[2])
                    elif (dx - 1) in pleat_xs:
                        put(body, x, y, stone_tone(x, y, f_v + 0.85, seed + 13))
                    else:
                        if x == x1 and 60 <= y <= 92 and y % 2 == 0:
                            put(body, x, y, RIM_COOL[0])
                        else:
                            put(body, x, y, stone_tone(x, y, f_v, seed + 13))

        # B) Chiseled Stone Forearms Sweeping Inward From Pauldrons (`y = 51..62`) to Clasped Gauntlets!
        for y in range(51, 63):
            for x in range(21, 60):
                dx = x - FX
                adx = abs(dx)
                if adx < 7 or adx > 18:
                    continue
                # Forearm band angling slightly upward toward center (`y_arm_center = 59.5 - 0.28 * (18 - adx)`)
                yc_arm = 59.5 - 0.28 * (18.0 - adx)
                d_arm = y - yc_arm
                if abs(d_arm) <= 2.8:
                    if d_arm > 1.8:
                        put(body, x, y, MORTAR)  # Deep elbow/forearm undercut shadow
                    elif d_arm < -1.7:
                        put(body, x, y, STONE[7 if dx < 0 else 5])  # Sunlit upper forearm ridge
                    else:
                        put(body, x, y, stone_tone(x, y, 5.6 if dx < 0 else 3.4, seed + 14, damp=False))

        # B) Chiseled Grounded Kite / Tower Shield (`y = 60..97, x = 30..50`) with Raised Rim, Central Spine & Battle Crack!
        for y in range(60, 98):
            u_s = (y - 60) / 37.0
            hw_sh = 9.2 * (1.0 - 0.36 * (u_s ** 1.75))
            sx0, sx1 = int(round(FX - hw_sh)), int(round(FX + hw_sh))
            for x in range(sx0, sx1 + 1):
                dx = x - FX
                adx = abs(dx)
                on_rim = (adx >= hw_sh - 1.6) or (y <= 61)
                on_inner_groove = (hw_sh - 2.6 <= adx < hw_sh - 1.6) or (y == 62 and adx < hw_sh - 1.6)
                on_spine = adx <= 1

                # Cast shadow around outer sides of shield onto the robe
                if adx == int(round(hw_sh)) and dx > 0 and x + 1 < W and get_a(body, x + 1, y) == 255:
                    put(body, x + 1, y, MORTAR)

                if on_rim:
                    sv = 6.4 if (dx < 0 or y == 60) else 3.4
                    put(body, x, y, stone_tone(x, y, sv, seed + 15, damp=False))
                elif on_inner_groove:
                    put(body, x, y, STONE[1] if dx < 0 else STONE[2])
                elif on_spine:
                    put(body, x, y, STONE[6 if dx <= 0 else 3])
                else:
                    # Crisp bipartite planar shield field (lit left half `STONE[5]`, shaded right half `STONE[2..3]`)
                    put(body, x, y, stone_tone(x, y, 4.9 if dx < 0 else 2.7, seed + 17))

        # C) Articulated Chiseled Stone Gauntlets Clasped Atop Shield (`y = 53..61, x = 32..48`)
        for y in range(53, 62):
            for x in range(32, 49):
                dx = x - FX
                if (dx / 8.2) ** 2 + ((y - 57.2) / 4.2) ** 2 <= 1.0:
                    # Gauntlet cuff ridge (`y = 54`) + carved finger divisions (`x in (-4, -1, 2, 5)` at `y >= 57`)
                    if y >= 57 and dx in (-4, -1, 2, 5):
                        put(body, x, y, MORTAR)
                    elif y <= 54:
                        put(body, x, y, STONE[7 if dx < 2 else 5])
                    elif y == 61:
                        put(body, x, y, MORTAR)
                    else:
                        put(body, x, y, stone_tone(x, y, 5.8 - 1.4 * (dx / 8.0), seed + 19, damp=False))

        # D) Serene Bowed Chiseled Head, 5-Peak Ancient Crown & Faceted Stone Beard (`y = 17..48, x = 29..51`)!
        for y in range(17, 49):
            if y < 25:
                hw_h = 10.5 - 0.12 * (25 - y)
            elif y <= 36:
                hw_h = 9.8
            else:
                hw_h = 9.6 * (1.0 - 0.42 * ((y - 36) / 12.0) ** 1.3)

            hx0, hx1 = int(round(FX - hw_h)), int(round(FX + hw_h))
            for x in range(hx0, hx1 + 1):
                dx = x - FX
                adx = abs(dx)
                # 5-point angular crown crenellations (`y = 17..22`), right peak slightly chipped!
                if y < 22 and adx in (3, 4, 7, 8):
                    continue
                if y < 19 and (adx in (2, 6, 9) or dx >= 8):
                    continue

                if y in (24, 25):
                    # Carved crown circlet brow band
                    put(body, x, y, STONE[7 if (y == 24 and dx < 3) else (5 if dx < 0 else 3)])
                elif y < 24:
                    # Faceted crown peaks (each peak has sunlit left edge & shaded right edge)
                    pk_left = dx in (-10, -6, -1, 5, 9)
                    cv = (6.6 if pk_left else (5.6 if dx < 0 else 3.6))
                    put(body, x, y, stone_tone(x, y, cv, seed + 21, damp=False))
                elif y >= 36:
                    # Chiseled long stone beard divided into 5 angular faceted locks!
                    if dx in (-6, -2, 2, 6) and y < 47:
                        put(body, x, y, STONE[1] if dx > 0 else STONE[2])
                    elif y == 48:
                        put(body, x, y, MORTAR)
                    else:
                        bv = 5.4 if dx < -2 else (4.5 if dx <= 2 else 2.8)
                        if (dx - 1) in (-6, -2, 2):
                            bv += 0.7
                        put(body, x, y, stone_tone(x, y, bv, seed + 23, damp=False))
                else:
                    # Planar chiseled face (`y = 26..35`): flat cheekbones, recessed eye sockets, sharp nose bridge!
                    if y == 26:
                        put(body, x, y, STONE[1])  # Undercut shadow beneath crown band
                    elif y == 30 and 2 <= adx <= 6:
                        put(body, x, y, STONE[2 if dx < 0 else 1])  # Recessed orbital socket
                    elif y == 31 and 2 <= adx <= 6:
                        put(body, x, y, MORTAR)  # Serene closed stone eyelid crease
                    elif y == 32 and 2 <= adx <= 6:
                        put(body, x, y, STONE[6 if dx < 0 else 4])  # Lower lid catch-edge
                    elif adx <= 1 and 28 <= y <= 35:
                        put(body, x, y, STONE[7 if dx <= 0 else 3])  # Sharp planar nose bridge!
                    else:
                        fv = 5.9 if dx < -3 else (5.0 if dx < 0 else (3.6 if dx < 5 else 2.3))
                        put(body, x, y, stone_tone(x, y, fv, seed + 25, damp=False))

        # Cracks, chips, pale sage lichen & painterly organic moss cushions!
        chip_silhouette(body, 20, 46, 2, is_left=True)
        chip_silhouette(body, 58, 72, 2, is_left=False)
        carve_crack(body, [(24, 48), (25, 49), (25, 50), (26, 51), (26, 52), (27, 53)], seed + 27, lit_side=1)
        carve_crack(body, [(43, 75), (44, 76), (45, 77), (45, 78), (46, 79), (47, 80)], seed + 29, lit_side=-1)
        carve_crack(body, [(28, 82), (28, 83), (29, 84), (30, 84), (30, 85), (30, 86)], seed + 31, lit_side=1)
        sprinkle_lichen(body, [(25, 63, 3), (52, 66, 4), (26, 90, 3), (53, 88, 3), (46, 38, 2)], seed + 33)

        drape_moss(body, 30, 42, 18, 2, 4, seed + 35)
        drape_moss(body, 19, 33, 42, 3, 6, seed + 37)
        drape_moss(body, 48, 60, 43, 2, 5, seed + 39)
        drape_moss(body, 15, 31, 106, 2, 4, seed + 41)

        # Awakened glowing runes on crown star, collar mantle & shield spine
        glow.emit(body, FX, 23, TEAL_L, TEAL_HOT, halo=2)
        for ry_s in range(65, 92, 4):
            is_v = (ry_s % 8 == 1)
            glow.emit(body, FX, ry_s, MOSAIC_VIO[2] if is_v else TEAL, VIO_HOT if is_v else TEAL_L, halo=1)
        for rx_c, ry_c in [(30, 50), (34, 51), (50, 50), (46, 51)]:
            glow.emit(body, rx_c, ry_c, MOSAIC_VIO[2], VIO_GLOW, halo=1)

    elif variant == 1:
        # ---- Col 1: Kneeling Monolithic Sentinel (`y = 20..116`) with 3-Tier Chiseled Feather Wings & Crossed Forearms!
        # A) Sweeping Gothic Stone Wings Carved into 3 Overlapping Tiers of Planar Feather Blades (`y = 20..97, x = 13..67`)
        for y in range(20, 98):
            u = (y - 20) / 77.0
            hw_w = 25.0 * math.sin(min(1.0, (u + 0.08) * 1.02) * math.pi * 0.86) + 3.2
            wx0, wx1 = int(round(FX - hw_w)), int(round(FX + hw_w))
            for x in range(wx0, wx1 + 1):
                dx = x - FX
                adx = abs(dx)
                wing_top_y = 20.0 + 0.23 * ((adx - 15.5) ** 2)
                if adx < 9.5 and y < 34:
                    continue
                if y < wing_top_y:
                    continue

                # 3 distinct overlapping feather tiers (`coverts -> secondaries -> primaries`)
                y_rel = y - wing_top_y
                tier = 0 if y_rel < 17 else (1 if y_rel < 38 else 2)
                tier_lip = abs(y_rel - 17.0) < 0.85 or abs(y_rel - 38.0) < 0.85

                # Outer arched stone wing spine rim (`adx >= hw_w - 2.2` or `y_rel < 2.2`)
                if y_rel < 2.0 or adx >= hw_w - 1.8:
                    rv = 6.8 if (dx < 0 and y_rel < 2.2) else (5.6 if dx < 0 else 3.2)
                    if x == wx1 and y > 40 and y % 2 == 0:
                        put(body, x, y, RIM_COOL[0])
                    else:
                        put(body, x, y, stone_tone(x, y, rv, seed + 43, damp=False))
                    continue

                # Individual chiseled stone feather blades (`4 px` wide, staggered per tier!)
                blade_coord = (adx - 7.5 + tier * 1.8 - y * 0.14) / 4.0
                bi = math.floor(blade_coord)
                bf = blade_coord - bi

                if tier_lip:
                    # Dark undercut step shadow beneath overlapping upper feather tier!
                    put(body, x, y, MORTAR if y_rel in (17, 38) else STONE[1])
                elif bf < 0.24:
                    # Crisp dark chisel groove between adjacent stone feather blades
                    put(body, x, y, STONE[1] if dx < 0 else MORTAR)
                elif bf < 0.48:
                    # Sunlit beveled leading edge of stone feather blade!
                    fv = (6.4 if dx < 0 else 4.5) - tier * 0.25
                    put(body, x, y, stone_tone(x, y, fv, seed + 45, damp=False))
                else:
                    # Planar chiseled stone feather face
                    fv = (5.1 if dx < 0 else 3.1) - tier * 0.25 + ((bi % 2) * 0.35)
                    put(body, x, y, stone_tone(x, y, fv, seed + 45))

        # Chipped outer wing-feather notches
        chip_silhouette(body, 64, 46, 2, is_left=False)
        chip_silhouette(body, 15, 62, 2, is_left=True)

        # B) Kneeling Pleated Robe Torso Recessed Between Wings (`y = 44..97, x = 27..53`)
        for y in range(44, 98):
            u_t = (y - 44) / 53.0
            hw_t = 10.5 + 3.4 * u_t
            tx0, tx1 = int(round(FX - hw_t)), int(round(FX + hw_t))
            for x in range(tx0, tx1 + 1):
                dx = x - FX
                adx = abs(dx)
                if adx >= hw_t - 1.2:
                    put(body, x, y, MORTAR)  # Deep shadow channel separating torso from wings
                elif y == 82 and adx > 3:
                    put(body, x, y, MORTAR)  # Monolith drum joint
                elif adx <= 2 and y >= 66:
                    # Raised central carved rune-stole hanging down front of robe!
                    put(body, x, y, STONE[6 if dx <= 0 else 4] if adx < 2 else STONE[1])
                elif dx in (-7, -4, 4, 7) and y >= 65:
                    put(body, x, y, STONE[1])  # Chiseled vertical robe pleat creases
                else:
                    rv = planar_robe_val(dx / max(1.0, hw_t)) - 0.35
                    put(body, x, y, stone_tone(x, y, rv, seed + 47))

        # C) Bowed Diademed Sentinel Head Framed by Carved Stone Hair/Hood (`y = 24..46, x = 31..49`)
        for y in range(24, 47):
            u_h = (y - 24) / 22.0
            hw_h = 9.0 * math.sin(min(1.0, (u_h + 0.16) * 0.92) * math.pi)
            for x in range(int(round(FX - hw_h)), int(round(FX + hw_h)) + 1):
                dx = x - FX
                adx = abs(dx)
                if adx >= hw_h - 1.6 and y >= 28:
                    # Carved stone hair locks / hood cowl framing cheeks
                    put(body, x, y, STONE[5 if dx < 0 else 2] if adx < hw_h - 0.6 else STONE[1])
                elif y == 29 + (1 if adx <= 2 else 0):
                    # Pointed V-shaped chiseled brow diadem!
                    put(body, x, y, STONE[7 if dx <= 1 else 5])
                elif y == 35 and 2 <= adx <= 5:
                    put(body, x, y, MORTAR)  # Closed serene eyelids
                elif y == 36 and 2 <= adx <= 5:
                    put(body, x, y, STONE[6 if dx < 0 else 4])
                elif adx <= 1 and 31 <= y <= 39:
                    put(body, x, y, STONE[7 if dx <= 0 else 3])  # Planar nose bridge
                else:
                    hv = 6.2 if (y <= 26 and dx < 2) else (5.6 if dx < -2 else (4.8 if dx <= 2 else 3.2))
                    put(body, x, y, stone_tone(x, y, hv, seed + 49, damp=False))

        # D) Crossed Chiseled Stone Forearms, Bracer Cuffs & Hands Over Chest (`y = 49..66, x = 28..52`)
        for y in range(49, 67):
            for x in range(28, 53):
                dx = x - FX
                d1 = (y - 57.5) - dx * 0.42
                d2 = (y - 57.5) + dx * 0.42
                if abs(d1) <= 3.3:
                    is_cuff = abs(dx + 5) <= 1.2 or abs(dx - 6) <= 1.0
                    if d1 > 2.2:
                        put(body, x, y, MORTAR)
                    elif d1 < -1.9:
                        put(body, x, y, STONE[7 if dx < 4 else 5])
                    else:
                        av = (6.0 if is_cuff else 5.2) - 1.2 * (dx / 12.0)
                        put(body, x, y, stone_tone(x, y, av, seed + 51, damp=False))
                elif abs(d2) <= 3.3:
                    if d2 > 2.2:
                        put(body, x, y, MORTAR)
                    elif d2 < -1.9:
                        put(body, x, y, STONE[6 if dx < 2 else 4])
                    else:
                        put(body, x, y, stone_tone(x, y, 4.4 - 1.1 * (dx / 12.0), seed + 53, damp=False))

        # Cracks, crust lichen, wing-arch moss cushions & climbing ivy + purple heather!
        carve_crack(body, [(22, 42), (23, 43), (23, 44), (24, 45), (24, 46)], seed + 55, lit_side=1)
        carve_crack(body, [(54, 58), (55, 59), (55, 60), (56, 61), (56, 62)], seed + 57, lit_side=-1)
        sprinkle_lichen(body, [(21, 55, 3), (57, 48, 3), (24, 78, 3), (35, 88, 2)], seed + 59)

        drape_moss(body, 20, 29, 25, 3, 5, seed + 61)
        drape_moss(body, 35, 43, 24, 2, 3, seed + 63)
        drape_moss(body, 49, 61, 98, 2, 4, seed + 65)

        # Creeping woody ivy vine with alternating sunlit leaves & heather blossoms climbing right wing!
        for k in range(28):
            ix = 52 + int(round(2.8 * math.sin(k * 0.42)))
            iy = 113 - k
            put(body, ix, iy, MOSS[1 if k % 2 else 2])
            side = -1 if (k // 2) % 2 == 0 else 1
            if k % 2 == 0:
                put(body, ix + side, iy, MOSS[5 if side < 0 else 4])
                put(body, ix + side, iy + 1, MOSS[2])
            if k in (4, 11, 18, 24):
                put(body, ix + 1, iy - 1, HEATHER[3])
                put(body, ix + 2, iy, HEATHER[2])
                put(body, ix + 1, iy, HEATHER[1])

        # Glowing diadem star, crossed-bracer runes, stole runes & wing-arch glyphs!
        glow.emit(body, FX, 30, TEAL_L, TEAL_HOT, halo=2)
        for gx, gy, is_v in [(FX - 6, 55, False), (FX, 58, True), (FX + 6, 55, False), (FX, 71, False), (FX, 79, True), (FX, 87, False), (25, 35, True), (55, 35, True)]:
            glow.emit(body, gx, gy, MOSAIC_VIO[2] if is_v else TEAL, VIO_HOT if is_v else TEAL_L, halo=1)

    else:
        # ---- Col 2: 7th Broken / Headless Monolith (`y = 43..116`), Stepped Planar Fracture + Fallen Blocks!
        pleat_xs = (-15, -10, -5, 5, 10, 15)
        for y in range(43, 98):
            u = (y - 43) / 54.0
            in_mantle = y <= 56
            if in_mantle:
                hw = (16.5 + (y - 43) * 1.6) if y < 46 else (21.2 - 0.22 * max(0, y - 49))
            else:
                hw = 17.2 + 1.8 * u
            x0, x1 = int(round(FX - hw)), int(round(FX + hw))

            for x in range(x0, x1 + 1):
                dx = x - FX
                adx = abs(dx)
                rel = dx / max(1.0, hw)

                # Jagged stepped planar stone break profile across severed neck & shattered right shoulder!
                if dx < -12:
                    frac_top = 46
                elif dx < -4:
                    frac_top = 43
                elif dx <= 3:
                    frac_top = 48  # Deep hollowed neck socket!
                elif dx <= 10:
                    frac_top = 45
                else:
                    frac_top = 48 + int((dx - 10) * 0.65)

                if y < frac_top:
                    continue

                if y <= frac_top + 2:
                    if -4 <= dx <= 3:
                        put(body, x, y, MORTAR if y == frac_top + 1 else STONE[1])
                    else:
                        put(body, x, y, STONE[8 if (y == frac_top and dx < 0) else (7 if dx < 6 else 5)])
                    continue

                if y in (70, 85) and adx > 9 and hsh(x // 3, y, seed + 71) < 0.78:
                    put(body, x, y, MORTAR if dx > 0 else STONE[2])
                    continue

                if in_mantle:
                    if y == 56 and adx > 7:
                        put(body, x, y, MORTAR)
                    elif y == 55 and adx > 7:
                        put(body, x, y, STONE[2 if x % 3 == 0 else (6 if dx < 0 else 4)])
                    else:
                        put(body, x, y, stone_tone(x, y, planar_robe_val(rel), seed + 73))
                else:
                    f_v = planar_robe_val(rel) + (0.65 if y in (71, 86) and dx < 6 else 0.0)
                    if y == 57 and adx > 7:
                        f_v -= 1.25
                    if dx in pleat_xs:
                        put(body, x, y, STONE[1] if dx > 0 else STONE[2])
                    elif (dx - 1) in pleat_xs:
                        put(body, x, y, stone_tone(x, y, f_v + 0.85, seed + 75))
                    else:
                        put(body, x, y, stone_tone(x, y, f_v, seed + 75))

        # Chiseled Stone Forearms Connecting Pauldrons to Clasped Gauntlets (`y = 52..63`)
        for y in range(52, 64):
            for x in range(21, 59):
                dx = x - FX
                adx = abs(dx)
                if adx < 7 or adx > 18:
                    continue
                yc_arm = 60.0 - 0.26 * (18.0 - adx)
                d_arm = y - yc_arm
                if abs(d_arm) <= 2.7:
                    if d_arm > 1.7:
                        put(body, x, y, MORTAR)
                    elif d_arm < -1.6:
                        put(body, x, y, STONE[7 if dx < 0 else 5])
                    else:
                        put(body, x, y, stone_tone(x, y, 5.4 if dx < 0 else 3.2, seed + 76, damp=False))

        # Grounded Chiseled Tower-Shield (with shattered upper-right corner!) & Gauntlets
        for y in range(60, 98):
            u_s = (y - 60) / 37.0
            hw_sh = 9.0 * (1.0 - 0.36 * (u_s ** 1.75))
            for x in range(int(round(FX - hw_sh)), int(round(FX + hw_sh)) + 1):
                dx = x - FX
                if y < 65 and dx > 5 - (65 - y):
                    continue  # Shattered upper-right shield corner
                adx = abs(dx)
                on_rim = (adx >= hw_sh - 1.6) or (y <= 61) or (y == 65 and dx > 3)
                if on_rim:
                    put(body, x, y, stone_tone(x, y, 6.3 if dx < 0 else 3.5, seed + 77, damp=False))
                elif adx <= 1:
                    put(body, x, y, STONE[6 if dx <= 0 else 3])
                else:
                    put(body, x, y, stone_tone(x, y, 4.8 if dx < 0 else 2.6, seed + 79))
        for y in range(55, 62):
            for x in range(33, 47):
                dx = x - FX
                if (dx / 7.5) ** 2 + ((y - 58.2) / 3.6) ** 2 <= 1.0:
                    put(body, x, y, MORTAR if (y >= 58 and dx in (-3, 0, 3)) else stone_tone(x, y, 5.6 - 1.4 * (dx / 7.5), seed + 81, damp=False))

        # Deep branching structural fracture crack from shattered neck socket down across left mantle & chest!
        carve_crack(
            body,
            [(36, 48), (35, 49), (35, 50), (34, 51), (33, 52), (33, 53), (32, 54), (31, 55), (31, 56), (30, 57), (30, 58), (29, 59), (29, 60), (28, 61), (28, 62)],
            seed + 83,
            lit_side=1,
        )
        carve_crack(body, [(48, 68), (49, 69), (49, 70), (50, 71), (51, 72), (51, 73), (52, 74)], seed + 85, lit_side=-1)
        chip_silhouette(body, 21, 74, 2, is_left=True)
        sprinkle_lichen(body, [(25, 66, 4), (52, 62, 3), (26, 88, 3), (51, 83, 4)], seed + 87)

        # Angular chiseled fallen stone blocks & rubble chunks at plinth base (`y = 110..118`)!
        for bx0, by0, bw, bh, b_lit in [(11, 112, 7, 5, 5.4), (21, 114, 6, 4, 5.0), (55, 112, 8, 5, 4.4), (65, 113, 6, 4, 3.8)]:
            for yy in range(by0, by0 + bh):
                for xx in range(bx0, bx0 + bw):
                    if (xx == bx0 and yy == by0) or (xx == bx0 + bw - 1 and yy == by0):
                        continue
                    v = b_lit + (1.1 if yy == by0 else (-1.0 if yy == by0 + bh - 1 else 0.0)) - 0.25 * (xx - bx0)
                    put(body, xx, yy, stone_tone(xx, yy, v, seed + bx0, damp=False))

        drape_moss(body, 21, 35, 44, 3, 6, seed + 89)
        drape_moss(body, 44, 56, 45, 3, 5, seed + 91)
        drape_moss(body, 14, 31, 106, 2, 4, seed + 93)
        drape_moss(body, 55, 62, 112, 2, 2, seed + 95)

        # Flickering interrupted violet rune spark in severed neck conduit + dim chest spine runes!
        glow.emit(body, FX, 48, MOSAIC_VIO[3], VIO_HOT, halo=2)
        glow.emit(body, FX - 1, 49, MOSAIC_VIO[2], VIO_GLOW, halo=1)
        for ry_s in range(66, 91, 5):
            glow.emit(body, FX, ry_s, TEAL, TEAL_L, halo=1)

    # 2) Lush Earthen / Mossy Meadow Grass-Tuft Skirt Rooting All 3 Statues Into the Meadow (`y = 112..118`)!
    draw_sod_pocket(body, 12, 30, FY + 1, seed + 101)
    draw_sod_pocket(body, 33, 47, FY + 1, seed + 103)
    draw_sod_pocket(body, 50, 68, FY + 1, seed + 105)
    draw_detailed_pebble(body, 11.5, 115.5, 2.4, 1.5, seed + 107)
    draw_detailed_pebble(body, 68.5, 115.5, 2.2, 1.4, seed + 109)

    tuft_specs = [
        (13, FY + 1, -1, True, BLOSSOM_GOLD if variant == 0 else None),
        (22, FY + 1, 1, True, HEATHER[1:] if variant != 2 else None),
        (31, FY + 1, -1, False, None),
        (40, FY + 1, 1, False, None),
        (49, FY + 1, 1, False, None),
        (58, FY + 1, -1, True, HEATHER[1:]),
        (67, FY + 1, 1, True, BLOSSOM_GOLD if variant == 1 else None),
    ]
    for tx, ty, fl, tl, bl in tuft_specs:
        draw_grass_tuft(body, tx, ty, flip=fl, tall=tl, blossom=bl)

    out = finish_prop(body, FX, FY, rx=32.5, ry=5.5)
    return out, glow.finish()


# ==============================================================================
# 4. Guardian Brazier & Fallen Headstone (`guardian_brazier.png` & `_glow.png`, 3x1 of 40x48, feet (20, 40))
# ==============================================================================
def build_guardian_brazier_col(col: int):
    W, H = 40, 48
    FX, FY = 20, 40
    seed = 4111 + col * 37
    body = blank(W, H)
    glow = GlowMap(W, H)

    if col in (0, 1):
        # ---- Col 0 (Unlit Chiseled Fluted Brazier) & Col 1 (Lit Spirit-Flame Brazier)
        # 1) Chipped Two-Block Ashlar Plinth (`y = 34..40, x = 9..31`)
        for y in range(34, 41):
            x0, x1 = (10, 30) if y == 34 else (9, 31)
            for x in range(x0, x1 + 1):
                if y == 34 and x >= 29:
                    continue  # Chipped right plinth corner
                dx = x - FX
                if x == 21 and y >= 35:
                    put(body, x, y, MORTAR)
                elif y == 34:
                    put(body, x, y, STONE[7 if dx < 3 else 5])
                else:
                    v = 4.6 - 1.6 * (dx / 11.0) + (0.6 if x == 22 else 0.0) - (0.7 if y == 40 else 0.0)
                    put(body, x, y, stone_tone(x, y, v, seed + 1, damp=False))

        # 2) Octagonal Carved Stem with Projecting Astragal Collar (`y = 28..33, x = 13..27`)
        for y in range(28, 34):
            hw_st = 7 if y == 30 else 6
            for x in range(FX - hw_st, FX + hw_st + 1):
                dx = x - FX
                if y == 28:
                    put(body, x, y, MORTAR)  # Overhang shadow beneath bowl
                elif y == 30:
                    put(body, x, y, STONE[6 if dx < 0 else (4 if dx < 4 else 2)])  # Moulded collar ring
                elif y == 31:
                    put(body, x, y, STONE[1])
                else:
                    # 3 planar octagonal stem facets
                    fv = 5.4 if dx < -2 else (4.1 if dx <= 2 else 2.3)
                    put(body, x, y, stone_tone(x, y, fv, seed + 3, damp=False))

        # 3) Chiseled Overhanging Rim & Gadrooned / Fluted Stone Offering Basin (`y = 17..27, x = 7..33`)
        for y in range(17, 28):
            u_b = (y - 17) / 10.0
            hw_b = 13.0 if y in (17, 18) else (12.0 * math.sqrt(max(0.22, 1.0 - 0.58 * (u_b ** 1.55))))
            bx0, bx1 = int(round(FX - hw_b)), int(round(FX + hw_b))
            for x in range(bx0, bx1 + 1):
                dx = x - FX
                rel = dx / max(1.0, hw_b)
                if y == 17 and x in (29, 30):
                    continue  # Chipped rim notch

                if y in (18, 19) and abs(dx) <= 9:
                    # Basin interior: cold ash + charred wood splinters (Col 0) vs glowing spirit coals (Col 1)!
                    if col == 0:
                        is_char = (x in (15, 16, 22, 23) and y == 19) or (x == 19 and y == 18)
                        put(body, x, y, EARTH[0] if is_char else ASH[3 if (dx < 0 and y == 18) else (2 if dx < 3 else 1)])
                    else:
                        put(body, x, y, GOLD_GLOW if abs(dx) <= 4 else TEAL)
                elif y == 17:
                    # Sunlit top-left chamfered basin rim (warmly lit in Col 1!)
                    put(body, x, y, GOLD_RIM[4] if (col == 1 and abs(dx) <= 7) else STONE[7 if dx < 3 else 5])
                elif y == 19:
                    put(body, x, y, STONE[5 if dx < 0 else 3])
                elif y == 20:
                    put(body, x, y, STONE[1])  # Crisp undercut shadow below overhanging lip!
                else:
                    # Crisp carved vertical gadroons / flutes (`4 px` wide lobes, dark groove + sunlit left ridge!)
                    fl_m = (dx + 12) % 4
                    if fl_m == 0 and abs(rel) < 0.88:
                        fv = 1.6
                    elif fl_m == 1:
                        fv = 5.8 - 1.4 * rel
                    else:
                        fv = 4.4 - 1.6 * rel
                    put(body, x, y, stone_tone(x, y, fv, seed + 5, damp=False))

        sprinkle_lichen(body, [(26, 24, 2), (13, 36, 2)], seed + 7)
        drape_moss(body, 8, 15, 18, 2, 3, seed + 9)
        drape_moss(body, 10, 19, 34, 2, 2, seed + 11)

        if col == 0:
            glow.emit(body, FX, 32, TEAL_DIM, TEAL, halo=1)
        else:
            glow.emit(body, FX, 32, TEAL_L, TEAL_HOT, halo=1)

    else:
        # ---- Col 2: Fallen Chiseled Crowned Guardian Headstone (`x = 7..33, y = 17..40`) Half-Buried in Meadow Sod!
        # Tilted ~20 deg right so the 5-peak stone crown sits clearly at top (`y = 17..23`), serene closed eyes & nose
        # across the middle, and chiseled beard / broken neck resting half-sunk in meadow grass!
        ca, sa = math.cos(0.34), math.sin(0.34)
        cx_h, cy_h = 20.2, 29.5
        for y in range(16, 41):
            for x in range(7, 34):
                dx0, dy0 = x - cx_h, y - cy_h
                lx = dx0 * ca + dy0 * sa
                ly = -dx0 * sa + dy0 * ca
                if not (-10.4 <= lx <= 10.4 and -11.2 <= ly <= 10.2):
                    continue
                # 5-point angular crown crenellations along top (`ly < -7.6`)
                if ly < -7.6 and int(round(abs(lx))) in (3, 4, 7, 8):
                    continue
                if ly < -9.5 and lx > 6.5:
                    continue  # Chipped right crown spire
                # Jagged fractured neck plane at base (`ly > 8.0`)
                if ly > 8.2 + 1.2 * math.sin(lx * 0.7):
                    continue
                max_lx = 10.2 if ly < 2.2 else 10.2 * (1.0 - 0.28 * ((ly - 2.2) / 8.0))
                if abs(lx) > max_lx:
                    continue

                if -5.8 <= ly <= -4.4:
                    val = 6.5 if lx < 2 else 4.5  # Carved crown circlet band
                elif abs(ly + 0.8) < 0.75 and 2.0 <= abs(lx) <= 6.2:
                    put(body, x, y, MORTAR)  # Serene closed stone eyelids
                    continue
                elif abs(ly - 0.3) < 0.75 and 2.0 <= abs(lx) <= 6.2:
                    val = 6.0 if lx < 0 else 4.2  # Lower lid bevel
                elif abs(lx) <= 1.15 and -3.8 <= ly <= 3.2:
                    val = 6.9 if lx <= 0 else 3.1  # Sharp planar nose bridge!
                elif ly > 3.4 and int(round(lx)) in (-5, -2, 2, 5):
                    put(body, x, y, STONE[1])  # Chiseled beard lock grooves
                    continue
                elif ly > 7.2:
                    val = 2.2 if abs(lx) < 3.5 else 5.2
                else:
                    val = (6.1 if lx < -2.5 else (5.0 if lx < 2.5 else 2.9)) - 0.12 * dy0
                put(body, x, y, stone_tone(x, y, val, seed + 17, damp=False))

        carve_crack(body, [(24, 24), (24, 25), (25, 26), (25, 27), (26, 28)], seed + 19, lit_side=-1)
        sprinkle_lichen(body, [(25, 31, 3), (12, 28, 2)], seed + 21)
        drape_moss(body, 11, 24, 17, 2, 4, seed + 23)

        # Pulsing turquoise brow rune centered on tilted crown circlet (`lx = 0, ly = -5.1`)
        glow.emit(body, 22, 24, TEAL_L, TEAL_HOT, halo=2)
        glow.emit(body, 21, 24, TEAL, TEAL_L, halo=1)

    # Lush Earthen / Mossy Meadow Turf Skirt & Wildflowers Around All 3 Frames (`y = 36..41`)!
    draw_sod_pocket(body, 8, 32, FY + 1, seed + 31)
    draw_detailed_pebble(body, 8.2, 39.6, 1.9, 1.2, seed + 33)
    draw_detailed_pebble(body, 31.8, 39.6, 1.8, 1.2, seed + 35)
    draw_grass_tuft(body, 9, FY + 1, flip=-1, tall=True, blossom=BLOSSOM_GOLD if col == 1 else None)
    draw_grass_tuft(body, 16, FY + 1, flip=1, tall=(col == 2), blossom=HEATHER[1:] if col == 2 else None)
    draw_grass_tuft(body, 24, FY + 1, flip=-1, tall=(col == 2), blossom=BLOSSOM_GOLD if col == 2 else None)
    draw_grass_tuft(body, 31, FY + 1, flip=1, tall=True, blossom=HEATHER[1:] if col == 0 else None)

    out = finish_prop(body, FX, FY, rx=16.5, ry=3.8)

    if col == 1:
        # Paint luminous Spirit Flame & floating sparks AFTER `finish_prop` so fire has ZERO dark stone outline!
        for y in range(5, 20):
            u_f = (19 - y) / 14.0
            cx_m = FX + 1.15 * math.sin(u_f * 4.2)
            hw_m = 6.2 * ((1.0 - u_f) ** 0.78)
            hw_l = 2.6 * (1.0 - (19 - y) / 9.5) if y >= 10 else 0.0
            hw_r = 2.4 * (1.0 - (19 - y) / 8.5) if y >= 11 else 0.0

            for x in range(10, 31):
                d_main = abs(x - cx_m) / max(0.65, hw_m) if hw_m > 0.25 else 9.0
                d_left = abs(x - (FX - 4.8 - (19 - y) * 0.15)) / max(0.6, hw_l) if hw_l > 0.25 else 9.0
                d_right = abs(x - (FX + 4.8 + (19 - y) * 0.12)) / max(0.6, hw_r) if hw_r > 0.25 else 9.0
                d = min(d_main, d_left * 1.12, d_right * 1.15)
                if d > 1.05:
                    continue
                if d_main < 0.38 and u_f < 0.65:
                    c_f, c_g = GOLD_HOT, GOLD_HOT
                elif d < 0.58 and u_f < 0.80:
                    c_f, c_g = GOLD_GLOW, GOLD_HOT
                elif d < 0.80:
                    c_f, c_g = TEAL_L, TEAL_HOT
                elif d < 0.94:
                    c_f, c_g = TEAL, TEAL_L
                else:
                    c_f, c_g = TEAL_DIM, TEAL
                glow.emit(out, x, y, c_f, c_g, halo=1 if (x == int(round(cx_m)) and y in (8, 13, 17)) else 0)
        glow.emit(out, FX - 3, 4, TEAL_L, TEAL_HOT, halo=1)
        glow.emit(out, FX + 3, 6, GOLD_GLOW, GOLD_HOT, halo=1)

    return out, glow.finish()


# ==============================================================================
# 5. Amphitheater Podium (`amphitheater_podium.png` & `_glow.png`, 128x96, anchor (64, 52))
# ==============================================================================
def build_amphitheater_podium():
    W, H = 128, 96
    CX, CY = 64, 46     # Top mosaic ellipse center -> ground anchor (64, 52) sits right in the stage heart!
    RX, RY = 52.0, 30.0
    RIM_DROP = 9
    seed = 4409
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Cardinal Chiseled Stone Stairways: West (`x = 4..16, y = 39..57`), East (`x = 112..124, y = 39..57`), North (`x = 51..77, y = 11..18`)
    for sx0, sx1, is_left in [(4, 16, True), (112, 124, False)]:
        for y in range(39, 58):
            is_lower_tread = (x_lim := (sx0 + 5 if is_left else sx1 - 5)) >= 0
            for x in range(sx0, sx1 + 1):
                outer_step = (x <= sx0 + 4) if is_left else (x >= sx1 - 4)
                if outer_step and y < 42:
                    continue
                y_nosing = 42 if outer_step else 39
                if (x == sx0 and y == 42 and is_left) or (x == sx1 and y == 42 and not is_left):
                    continue  # Chipped outer step corner
                if y == 47 and not outer_step:
                    put(body, x, y, MORTAR)
                elif y >= 53:
                    # Step riser vertical block face
                    put(body, x, y, MORTAR if x == (sx0 + 6) else stone_tone(x, y, 3.4 if is_left else 2.0, seed + sx0))
                elif y == y_nosing or (is_left and x in (sx0, sx0 + 5) and y <= 50):
                    put(body, x, y, STONE[7 if is_left else 5])
                else:
                    put(body, x, y, stone_tone(x, y, 5.2 if is_left else 3.8, seed + sx0 + 3, damp=False))

    # North stairway (`x = 51..77, y = 11..18`) with block joints & sunlit top tread nosing
    for y in range(11, 19):
        nx0, nx1 = (53, 75) if y < 14 else (51, 77)
        for x in range(nx0, nx1 + 1):
            if y == 11 and x in (74, 75):
                continue
            if x in (59, 68) and y > 11:
                put(body, x, y, MORTAR)
            elif y in (11, 14):
                put(body, x, y, STONE[7 if x < CX + 4 else 5])
            elif y == 13:
                put(body, x, y, STONE[2])
            else:
                put(body, x, y, stone_tone(x, y, 5.5 - 1.0 * ((x - CX) / 14.0), seed + 11, damp=False))

    # 2) Raised 12-Sided Megalithic Stage Drum Wall (`RIM_DROP = 9 px` tall) with Overhanging Lip & Carved Frieze!
    for y in range(int(CY - RY), int(CY + RY + RIM_DROP + 2)):
        for x in range(int(CX - RX - 2), int(CX + RX + 3)):
            dx = (x + 0.5 - CX) / RX
            dy_top = (y + 0.5 - CY) / RY
            dy_bot = (y + 0.5 - (CY + RIM_DROP)) / RY
            ang_b = math.atan2(dy_bot, dx)
            # Crisp 12-sided polygonal temple-stage facets
            poly_b = 1.0 - 0.032 * math.cos(ang_b * 12.0)
            r_top = math.hypot(dx, dy_top)
            r_bot = math.hypot(dx, dy_bot)

            if y > CY - 2 and r_top > poly_b and r_bot <= poly_b:
                # Vertical height coordinate down the 9px drum wall (`0` right under kerb lip -> `RIM_DROP` at soil)
                y_surf = CY + math.sin(math.atan2(dy_bot, dx)) * RY * poly_b
                d_wall = clamp(y - y_surf, 0.0, float(RIM_DROP))
                # Facet index (quantized 12-sided stone plane lighting!)
                f_idx = int(round((ang_b / math.pi) * 6.0))
                blk_id = int((ang_b + math.pi) * 8.5)
                blk_frac = abs(((ang_b + math.pi) * 8.5) % 1.0)

                if d_wall < 1.3:
                    put(body, x, y, MORTAR)  # Crisp overhang shadow directly beneath kerb cornice!
                elif abs(d_wall - 4.5) < 0.65:
                    # Horizontal ashlar course seam / recessed molding groove
                    put(body, x, y, MORTAR if blk_frac < 0.75 else STONE[1])
                elif blk_frac < 0.11:
                    put(body, x, y, MORTAR)  # Vertical ashlar drum block joint
                else:
                    # Carved dentil/flute accent in upper drum course (`1.5 <= d_wall <= 3.6`)
                    flute = (1.6 <= d_wall <= 3.6) and (int((ang_b + math.pi) * 34.0) % 2 == 0)
                    f_lit = 4.9 - 2.1 * dx - (0.75 if flute else 0.0) - (0.7 if d_wall > 7.5 else 0.0)
                    f_lit += ((blk_id % 3) - 1) * 0.35 + (0.55 if abs(d_wall - 5.4) < 0.6 and dx < 0.3 else 0.0)
                    if dx > 0.84 and 2.0 <= d_wall <= 6.5 and y % 2 == 0:
                        put(body, x, y, RIM_COOL[0])
                    else:
                        put(body, x, y, stone_tone(x, y, f_lit, seed + 21))

    # 3) Megalithic Chiseled Kerb Stones & Grand Moonflower-and-Chord Mosaic Floor!
    for y in range(int(CY - RY - 1), int(CY + RY + 2)):
        for x in range(int(CX - RX - 1), int(CX + RX + 2)):
            dx = (x + 0.5 - CX) / RX
            dy = (y + 0.5 - CY) / RY
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            poly = 1.0 - 0.030 * math.cos(ang * 12.0)
            if r > poly:
                continue

            # A) Chiseled 16-Block Megalithic Kerb Ring (`0.84 * poly <= r <= poly`)
            if r >= 0.84 * poly:
                sec_f = ((ang + math.pi) * 8.0 / math.pi)
                sec_id = int(sec_f)
                spoke_j = abs(sec_f % 1.0) < 0.075
                inner_lip = abs(r - 0.84 * poly) < 0.026
                outer_bevel = r > 0.94 * poly

                # Chipped outer kerb notches at 3 ancient weathered spots!
                if outer_bevel and ((24 <= x <= 26 and y <= 25) or (101 <= x <= 103 and 27 <= y <= 29) or (31 <= x <= 33 and y >= 68)):
                    continue

                if spoke_j:
                    put(body, x, y, MORTAR if hsh(x, y, seed + 29) < 0.86 else STONE[2])
                elif inner_lip:
                    # Inner kerb rim: dark step shadow on top-left (`dx + dy < 0`), sunlit catch-bevel on bottom-right!
                    put(body, x, y, MORTAR if (dx + dy) < -0.1 else STONE[7 if dx < 0.2 else 5])
                else:
                    blk_bias = (hsh(sec_id, 7, seed + 31) - 0.5) * 0.75
                    kv = 5.4 - 1.25 * dx - 1.35 * dy + blk_bias
                    if outer_bevel:
                        kv += 1.15 if (dy < 0.15 and dx < 0.35) else -0.45
                    put(body, x, y, stone_tone(x, y, kv, seed + 33, damp=False))
                continue

            # B) Artisanal Concentric Moonflower-and-Chord Mosaic (`r < 0.84 * poly`, ZERO checkerboard glow noise!)
            petal_main = 0.19 + 0.40 * abs(math.cos(4.0 * ang))
            petal_sec = 0.17 + 0.31 * abs(math.sin(4.0 * ang))

            d_outer_r = abs(r - 0.745)
            d_inner_r = abs(r - 0.415)
            d_cent_r = abs(r - 0.155)
            d_mpet = abs(r - petal_main) if r > 0.155 else 9.0
            d_spet = abs(r - petal_sec) if r > 0.155 else 9.0
            # Inscribed harmonic octagram chords
            d_chord_sq = min(abs((abs(dx) + abs(dy)) - 0.73), abs(max(abs(dx), abs(dy)) - 0.525)) if r < 0.74 else 9.0
            d_axis = min(abs(dx), abs(dy) * 0.62) if 0.16 < r < 0.73 else 9.0

            if r < 0.14:
                # Central faceted Moon-Pearl Medallion (`r < 0.14`)
                star = abs(math.cos(4.0 * ang))
                if r < 0.065:
                    glow.emit(body, x, y, GOLD_HOT, GOLD_HOT if r < 0.035 else TEAL_HOT, halo=2 if (x == CX and y == CY) else 0)
                elif r < 0.095 + 0.03 * star:
                    glow.emit(body, x, y, MOSAIC_SILVER[4], TEAL_HOT, halo=0)
                else:
                    put(body, x, y, MOSAIC_SILVER[2 if dx < 0 else 1])
            elif d_cent_r <= 0.024:
                put(body, x, y, MORTAR if d_cent_r > 0.015 else MOSAIC_SILVER[3])
            elif d_outer_r <= 0.034:
                # Outer Harmonic Ring with 16 jewel rune nodes + crisp inlaid silver-teal channel!
                if d_outer_r > 0.022:
                    put(body, x, y, MORTAR)  # Crisp dark incised stone channel border
                else:
                    node_f = abs(((ang + math.pi) * 8.0 / math.pi) % 1.0 - 0.5)
                    if node_f > 0.41:
                        glow.emit(body, x, y, GOLD_GLOW, GOLD_HOT, halo=1)
                    elif d_outer_r < 0.013:
                        glow.emit(body, x, y, TEAL_L, TEAL_L, halo=0)
                    else:
                        put(body, x, y, MOSAIC_SILVER[3 if dy < 0 else 2])
            elif d_mpet <= 0.044:
                # Primary 8-Petal Silver-Turquoise Moonflower Rosette (solid silver edge + smooth glowing core vein!)
                if d_mpet > 0.031:
                    put(body, x, y, MORTAR)
                elif d_mpet < 0.016:
                    is_tip = r > 0.52
                    glow.emit(body, x, y, MOSAIC_SILVER[4] if is_tip else TEAL_L, TEAL_HOT if is_tip else TEAL_L, halo=1 if (is_tip and abs(math.cos(4.0 * ang)) > 0.96) else 0)
                else:
                    put(body, x, y, MOSAIC_SILVER[3 if (dx + dy) < 0 else 2])
            elif d_spet <= 0.038 or d_inner_r <= 0.024:
                # Secondary 8-Petal Amethyst-Violet Interlace & Inner Resonance Ring
                d_v = min(d_spet, d_inner_r)
                if d_v > 0.025:
                    put(body, x, y, MORTAR)
                elif d_v < 0.013:
                    glow.emit(body, x, y, MOSAIC_VIO[3], VIO_HOT if d_spet < d_inner_r else VIO_GLOW, halo=0)
                else:
                    put(body, x, y, MOSAIC_VIO[2 if dy < 0 else 1])
            elif d_chord_sq <= 0.020 or d_axis <= 0.016:
                # Crisp inlaid silver harmonic chord lines (glowing gently at intersections)
                near_cross = (d_chord_sq <= 0.022 and d_axis <= 0.022)
                if near_cross:
                    glow.emit(body, x, y, TEAL_L, TEAL_HOT, halo=1)
                else:
                    put(body, x, y, MOSAIC_SILVER[2 if (dx + dy) < 0 else 1])
            else:
                # Fitted concentric radial slate-violet stone tesserae with individual block bias & catch-edges!
                r_scaled = r * 9.5
                ring_id = int(r_scaled)
                ring_f = r_scaled % 1.0
                n_spokes = 12 if ring_id < 3 else (20 if ring_id < 6 else 28)
                sp_scaled = ((ang + math.pi) * n_spokes / (2.0 * math.pi))
                sp_id = int(sp_scaled)
                sp_f = sp_scaled % 1.0

                if ring_f < 0.11 or (sp_f < 0.085 and r > 0.20):
                    if r > 0.56 and fbm(x * 0.38, y * 0.38, seed + 41) > 0.58:
                        put(body, x, y, MOSS[4 if dy < 0 else 2])
                    else:
                        put(body, x, y, MORTAR)
                else:
                    t_bias = (hsh(ring_id * 31 + sp_id, ring_id, seed + 43) - 0.5) * 0.95
                    catch = 0.55 if (ring_f < 0.24 and dy > -0.2) else 0.0
                    tv = 4.1 - 0.95 * dx - 1.05 * dy + t_bias + catch
                    put(body, x, y, stone_tone(x, y, tv, seed + 47, damp=False))

    # 4) South (Front) Chiseled Two-Tread Mossy Stone Stairway (`x = 48..80, y = 73..87`)!
    for tier_i, (tx0, tx1, ty0, ty1) in enumerate([(50, 78, 73, 80), (48, 80, 80, 87)]):
        joints_s = [59, 69] if tier_i == 0 else [57, 65, 73]
        for y in range(ty0, ty1):
            for x in range(tx0, tx1 + 1):
                if tier_i == 1 and y == 80 and x in (48, 80):
                    continue  # Chipped lower tread corners
                dx = x - CX
                if x in joints_s and y > ty0:
                    put(body, x, y, MORTAR)
                elif y == ty0:
                    put(body, x, y, STONE[7 if dx < 4 else 5])  # Sunlit tread nosing!
                elif y == ty0 + 1:
                    put(body, x, y, STONE[6 if dx < 0 else 4])
                elif y == ty1 - 1:
                    put(body, x, y, MORTAR if tier_i == 0 else STONE[1])
                else:
                    sv = 4.5 - 1.3 * (dx / 16.0) + (0.55 if (x - 1) in joints_s else 0.0)
                    put(body, x, y, stone_tone(x, y, sv, seed + 51 + tier_i, damp=False))

    # Radial cracks, crust lichen & painterly organic moss cushions across kerb & stair corners!
    carve_crack(body, [(28, 26), (29, 27), (30, 28), (30, 29)], seed + 55, lit_side=1)
    carve_crack(body, [(96, 62), (97, 63), (98, 64), (98, 65), (99, 66)], seed + 57, lit_side=-1)
    sprinkle_lichen(body, [(21, 36, 3), (41, 19, 3), (92, 23, 3), (104, 57, 4), (36, 72, 3)], seed + 59)

    def podium_moss_mask(x: int, y: int) -> float:
        if get_a(body, x, y) != 255:
            return 0.0
        patches = [
            (27.0, 23.5, 8.5, 3.6),
            (95.0, 66.5, 8.0, 3.8),
            (53.0, 81.5, 5.5, 2.8),
            (13.0, 41.5, 4.2, 2.5),
            (74.0, 14.0, 4.5, 2.2),
        ]
        best = 0.0
        for mx, my, mrx, mry in patches:
            d = ((x - mx) / mrx) ** 2 + ((y - my) / mry) ** 2
            if d < 1.0:
                best = max(best, 1.25 - d * 0.72)
        return best

    apply_organic_moss(body, podium_moss_mask, seed + 61, pal=MOSS)

    # Soft Meadow Turf, Sod Pockets, Pebbles & Wildflower Skirt Grounding the Podium Perimeter!
    draw_sod_pocket(body, 46, 56, 87, seed + 71)
    draw_sod_pocket(body, 72, 82, 87, seed + 73)
    draw_detailed_pebble(body, 43.5, 85.2, 2.5, 1.5, seed + 75)
    draw_detailed_pebble(body, 84.5, 85.2, 2.3, 1.4, seed + 77)
    draw_detailed_pebble(body, 15.5, 61.5, 2.1, 1.3, seed + 79)
    draw_detailed_pebble(body, 112.5, 60.5, 2.1, 1.3, seed + 81)

    perimeter_tufts = [
        (6, 57, -1, True, BLOSSOM_GOLD),
        (18, 64, 1, True, None),
        (30, 75, -1, True, HEATHER[1:]),
        (46, 87, -1, True, BLOSSOM_GOLD),
        (82, 87, 1, True, HEATHER[1:]),
        (98, 74, 1, True, None),
        (111, 63, -1, True, BLOSSOM_GOLD),
        (122, 57, 1, True, HEATHER[1:]),
        (49, 17, -1, False, None),
        (79, 17, 1, False, None),
    ]
    for tx, ty, fl, tl, bl in perimeter_tufts:
        draw_grass_tuft(body, tx, ty, flip=fl, tall=tl, blossom=bl)

    out = finish_prop(body, CX, CY + 8, rx=53.5, ry=30.5)
    return out, glow.finish()


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/meadow_wonders_sheet.png`)
# ==============================================================================
def verify_no_black(name: str, px):
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} has forbidden pure #000000 pixel at ({x}, {y})")


def alpha_over(dst, src, ox: int, oy: int):
    sh, sw = len(src), len(src[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(sh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(sw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            sc = src[y][x]
            sa = sc[3]
            if sa == 0:
                continue
            if sa == 255:
                dst[dy][dx] = sc
            else:
                dc = dst[dy][dx]
                inv = 255 - sa
                dst[dy][dx] = (
                    max(4, (sc[0] * sa + dc[0] * inv) // 255),
                    max(4, (sc[1] * sa + dc[1] * inv) // 255),
                    max(8, (sc[2] * sa + dc[2] * inv) // 255),
                    255,
                )


def add_glow_over(dst, glow, ox: int, oy: int):
    gh, gw = len(glow), len(glow[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(gh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(gw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            gc = glow[y][x]
            ga = gc[3]
            if ga == 0:
                continue
            dc = dst[dy][dx]
            f = ga / 255.0
            dst[dy][dx] = (
                min(255, int(dc[0] * (1.0 - 0.55 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.55 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.55 * f) + gc[2] * f * 1.35)),
                255,
            )


def tint_night_px(src):
    out = blank(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def pack_row(frames, fw: int, fh: int):
    out = blank(fw * len(frames), fh)
    for col, f in enumerate(frames):
        for y in range(fh):
            out[y][col * fw:(col + 1) * fw] = f[y]
    return out


def render_qa_sheet(spires, step_frames, step_glows, guardians, braziers, podium_px, podium_gl):
    cw, ch = 620, 440
    canvas = blank(cw, ch)
    half = 220

    for y in range(ch):
        night = y >= half
        for x in range(cw):
            # Lake Glockenteich water basin on left (`x < 210`) + lush meadow on right (`x >= 210`)
            in_lake = x < 210
            n = noise(x // 4, y // 3, 173)
            if in_lake:
                if not night:
                    canvas[y][x] = (34, 96, 120, 255) if n < 120 else ((44, 116, 138, 255) if n < 210 else (76, 162, 176, 255))
                else:
                    canvas[y][x] = (16, 38, 62, 255) if n < 120 else ((22, 48, 74, 255) if n < 210 else (36, 78, 102, 255))
            else:
                if not night:
                    canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
                else:
                    canvas[y][x] = (20, 28, 48, 255) if n < 115 else ((25, 36, 58, 255) if n < 205 else (31, 44, 68, 255))

    for p_i in range(2):
        night = p_i == 1
        yo = 0 if not night else half

        # 1) 2 Bell Spires in Lake Glockenteich (`x = 6` Dormant, `x = 106` Awakened) + 3 Stepping Stones below!
        for i in range(2):
            sp_px, sp_gl = spires[i]
            ox, oy = 6 + i * 100, yo + 8
            alpha_over(canvas, tint_night_px(sp_px) if night else sp_px, ox, oy)
            if night or i == 1:
                add_glow_over(canvas, sp_gl, ox, oy)
        for i in range(3):
            ox, oy = 22 + i * 58, yo + 178
            alpha_over(canvas, tint_night_px(step_frames[i]) if night else step_frames[i], ox, oy)
            if night:
                add_glow_over(canvas, step_glows[i], ox, oy)

        # 2) 3 Sleeping Guardians (`x = 216, 298, 380`) + 3 Guardian Braziers/Headstone below them!
        for i in range(3):
            g_px, g_gl = guardians[i]
            ox, oy = 216 + i * 82, yo + 6
            alpha_over(canvas, tint_night_px(g_px) if night else g_px, ox, oy)
            if night:
                add_glow_over(canvas, g_gl, ox, oy)
        for i in range(3):
            b_px, b_gl = braziers[i]
            ox, oy = 234 + i * 74, yo + 152
            alpha_over(canvas, tint_night_px(b_px) if night else b_px, ox, oy)
            if night or i == 1:
                add_glow_over(canvas, b_gl, ox, oy)

        # 3) Amphitheater Podium on far right (`x = 474, yo + 62`)
        px_pos, py_pos = 474, yo + 62
        alpha_over(canvas, tint_night_px(podium_px) if night else podium_px, px_pos, py_pos)
        if night:
            add_glow_over(canvas, podium_gl, px_pos, py_pos)

    verify_no_black("meadow_wonders_sheet.png", canvas)
    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"

    spires = [build_bell_spire_variant(False), build_bell_spire_variant(True)]
    sp_sheet = pack_row([s for s, _ in spires], 96, 160)
    sp_glow = pack_row([g for _, g in spires], 96, 160)

    step_frames, step_glows = build_bell_stepping_stones()
    st_sheet = pack_row(step_frames, 32, 32)
    st_glow = pack_row(step_glows, 32, 32)

    guardians = [build_sleeping_guardian(i) for i in range(3)]
    gd_sheet = pack_row([g for g, _ in guardians], 80, 128)
    gd_glow = pack_row([gl for _, gl in guardians], 80, 128)

    braziers = [build_guardian_brazier_col(i) for i in range(3)]
    br_sheet = pack_row([b for b, _ in braziers], 40, 48)
    br_glow = pack_row([gl for _, gl in braziers], 40, 48)

    podium_px, podium_gl = build_amphitheater_podium()

    outputs = [
        ("bell_spire.png", sp_sheet, 192, 160),
        ("bell_spire_glow.png", sp_glow, 192, 160),
        ("bell_stepping_stone.png", st_sheet, 96, 32),
        ("bell_stepping_stone_glow.png", st_glow, 96, 32),
        ("sleeping_guardian.png", gd_sheet, 240, 128),
        ("sleeping_guardian_glow.png", gd_glow, 240, 128),
        ("guardian_brazier.png", br_sheet, 120, 48),
        ("guardian_brazier_glow.png", br_glow, 120, 48),
        ("amphitheater_podium.png", podium_px, 128, 96),
        ("amphitheater_podium_glow.png", podium_gl, 128, 96),
    ]
    for name, px, ew, eh in outputs:
        assert (len(px[0]), len(px)) == (ew, eh), f"{name}: got {(len(px[0]), len(px))} != {(ew, eh)}"
        verify_no_black(name, px)
        write_png(props / name, ew, eh, px)

    render_qa_sheet(spires, step_frames, step_glows, guardians, braziers, podium_px, podium_gl)
    print("Wrote 10 Meadow Wonders PNGs and docs/img/meadow_wonders_sheet.png")


if __name__ == "__main__":
    main()
