#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 3 — Spuren des Roten Ordens (stdlib + gen_art.py only):
  1. assets/props/order_watchtower.png & _glow.png
     - 2 cols x 1 row of 128x144 (256x144 total), ground/feet anchor at (64, 130):
       * Col 0: Half-collapsed ancient cliffside stone watchtower (~112 px tall, ~90 px wide at base),
                irregular weathered slate & warm sandstone-violet ashlar + rubble-core masonry,
                flaky aged wine-red plaster/frieze bands, deep recessed arched sally-port with radiating
                voussoirs & riveted rusted portcullis, carved Red Order sun-shield escutcheon, wrought-iron
                lantern cage niche, branching ivy vines, moss cushions, and sunken loam/rubble/turf apron.
       * Col 1: Octagonal/curved bastion ruin with collapsed curtain wall, deeply recessed vaulted spiral
                staircase & broken corbels, splayed lancet arrow-slit, forged iron brazier sconce, fallen
                voussoir blocks, branching ivy, and sunken meadow earth/gravel/grass apron.
  2. assets/props/order_patrol_camp.png & _glow.png
     - 2 cols x 1 row of 96x64 (192x64 total), ground/feet anchor at (48, 52):
       * Col 0: Cold ash pit with white/grey wood-ash clusters, charred split billets & varied faceted
                river-stones; buckled leather pack & oak-grained battered Crimson-Order heater shield;
                rusted knight's greatsword with fuller runes, corded leather grip & winged crossguard
                planted in sod, leaving x ~ 68..84 clear on right for the separate swaying banner pole!
       * Col 1: Collapsed folded canvas shelter/bedroll with stitched seams & mud smudges, faceted mossy
                patrol cairn, planted rusted Order halberd with wood grain & collar rune, dented cast-iron
                kettle, and parchment scroll dispatch with glowing crimson wax seal on rich loam/moss base.
  3. assets/props/order_banner.png (no glow)
     - Single frame 32x64, ground/pole-foot anchor at (16, 58):
       Forged steel spearhead & crossbar, wood-grained lance shaft with brass rings & iron spike shoe,
       deeply pleated battle-torn wine-red cloth banner with stitched seams, dirt-smudged swallowtails,
       and embroidered gold Red Order sun-greatsword emblem.
       KEEP x = 0..4 and x = 27..31 STRICTLY TRANSPARENT for sway_rows.gdshader!
  4. assets/props/order_boundary_stone.png & _glow.png
     - 3 cols x 1 row of 48x56 (144x56 total), ground/feet anchor at (24, 48):
       * Col 0: Chiseled angular beveled obelisk stele with corner chips, deeply incised sun-sword crest &
                ancient rune rows, mottled lichen, moss cap, and sunken earth/pebble/grass collar.
       * Col 1: Faceted tilted waystone tablet with fracture crack, folded crimson cloth sash & fluttering
                tails, incised star-rune glyph, climbing ivy, and earth/pebble/grass collar.
       * Col 2: Twin-horned beveled pass monolith with sunken bronze-rimmed Order medallion, flaky crimson
                plaster band, crustose lichen rosettes, moss cushions, and earth/pebble/grass collar.
  5. docs/img/red_order_sheet.png — 2x upscaled Visual QA contact sheet (daylight + night + composited banner).

STRICTLY ZERO #000000 pure black pixels anywhere! Ordered directional clusters — zero random salt-and-pepper noise.
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "red_order_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# Material-Tinted Dark Outlines & Cool-Violet Shadows (NEVER #000000)
OUT = hexc("1b1a2e")
OUT_WARM = hexc("231729")
OUT_LEAF = hexc("132228")
MORTAR_DEEP = hexc("171528")
MORTAR_MID = hexc("232038")
SHADOW_RGB = (15, 16, 34)

# Cool Slate-Violet Ashlar Masonry (9 steps: deep crevice -> sunlit catch-edge)
STONE = [
    hexc("1d1b30"),  # 0 deep crevice / inner shadow
    hexc("29263f"),  # 1 dark shadow ashlar
    hexc("383452"),  # 2 cool slate shadow
    hexc("494466"),  # 3 mid-shadow stone
    hexc("5c567b"),  # 4 mid slate-violet
    hexc("726b90"),  # 5 lit stone face
    hexc("8b84a6"),  # 6 bright stone plane
    hexc("a8a1c2"),  # 7 sunlit bevel
    hexc("d0cae6"),  # 8 crisp top-left catch-edge
]

# Warm Weathered Sandstone-Violet / Taupe-Plum Accent Blocks (~25% of masonry)
WARM_STONE = [
    hexc("21192b"),  # 0 deep warm crevice
    hexc("30253b"),  # 1 dark plum-taupe
    hexc("42334d"),  # 2 shadow warm stone
    hexc("564460"),  # 3 mid-shadow sandstone-violet
    hexc("6c5774"),  # 4 mid warm ashlar
    hexc("846d89"),  # 5 lit warm stone
    hexc("9e87a1"),  # 6 bright warm facet
    hexc("bca5bc"),  # 7 sunlit warm bevel
    hexc("dfd0de"),  # 8 crisp warm catch-edge
]

# Aged Flaky Wine-Red Plaster / Red Order Masonry & Cloth Banner Ramps
CRIMSON_STONE = [
    hexc("28101d"),  # 0 deep wine crevice
    hexc("3d1627"),  # 1 dark crimson shadow
    hexc("541e32"),  # 2 shaded wine plaster
    hexc("6d263e"),  # 3 mid wine-crimson
    hexc("87314a"),  # 4 lit crimson plaster
    hexc("a23e57"),  # 5 bright crimson face
    hexc("bf566e"),  # 6 sunlit flaky edge
    hexc("dc7a8e"),  # 7 crisp rose-plaster rim
]
BANNER_RED = [
    hexc("240e1a"),  # 0 deep fold trough / dirt-stained hem
    hexc("381424"),  # 1 dark wine pleat
    hexc("4e1b2f"),  # 2 shadow cloth
    hexc("66233a"),  # 3 mid crimson weave
    hexc("802d46"),  # 4 lit crimson cloth
    hexc("9a3852"),  # 5 sunlit fold crest
    hexc("ba5068"),  # 6 bright cloth catch
    hexc("d67286"),  # 7 frayed highlight thread
]
ORDER_GOLD = [
    hexc("3a2612"),  # 0 deep tarnished bronze crevice
    hexc("583d1a"),  # 1 dark aged gold
    hexc("7a5824"),  # 2 shadow gold
    hexc("9c7430"),  # 3 mid antique gold
    hexc("be923e"),  # 4 lit gold relief
    hexc("deb456"),  # 5 bright gold bevel
    hexc("f0cf78"),  # 6 sunlit gold highlight
    hexc("fff0b0"),  # 7 specular glint
]

# Forest Loam / Damp Earth, Steel, Rust, Wrought Iron, Wood, Leather, Canvas, Parchment & Ash
EARTH = [
    hexc("1c1524"),  # 0 wet dark soil crevice
    hexc("2a1f31"),  # 1 deep plum-loam
    hexc("3c2d3f"),  # 2 shaded earth clod
    hexc("523e4f"),  # 3 mid forest loam
    hexc("6b5261"),  # 4 dry sunlit soil / pebble
    hexc("876b77"),  # 5 pale grit highlight
]
STEEL = [hexc(c) for c in ("1f1c31", "312d46", "45405d", "5a5474", "726c8d", "8d87a8", "b0abc9", "d8d4ec")]
RUST = [hexc(c) for c in ("35181b", "4c2223", "652d2a", "7f3a32", "99493b", "b8664e")]
IRON = [hexc(c) for c in ("1a182a", "28253c", "3b3753", "534e6e", "726d8d", "9690b0")]
WOOD = [hexc(c) for c in ("211624", "342331", "4c3442", "684955", "88646d", "aa868b", "cbb0af")]
LEATHER = [hexc(c) for c in ("23141f", "3a212a", "563336", "764a45", "996758", "bc8a74")]
CANVAS = [hexc(c) for c in ("2c283b", "3f3a51", "565069", "716b84", "908aa3", "b3adc4", "d4cfe2")]
PARCHMENT = [hexc(c) for c in ("54403c", "7d6254", "ab8d73", "d4ba98", "f2e2c4")]
ASH = [hexc(c) for c in ("1e1c2e", "312f44", "49465e", "67647d", "8f8ca4", "c2bed4", "e2dfee")]

# Meadow Foliage (exact design_guide.md Meadow 6 tones + deep shadow), Lichen & Clover Blossoms
MOSS = [
    hexc("18332c"),  # 0 deep foliage shadow
    hexc("22483c"),  # 1 Meadow 0
    hexc("2f624e"),  # 2 Meadow 1
    hexc("3e7d56"),  # 3 Meadow 2 (base)
    hexc("55985f"),  # 4 Meadow 3
    hexc("7cb96d"),  # 5 Meadow 4
    hexc("a8dc8c"),  # 6 Meadow 5 (sunlit tip)
]
LICHEN = [hexc("466660"), hexc("6d968a"), hexc("a4ccb9")]
CLOVER_FL = [hexc("8f3b5e"), hexc("cf7096"), hexc("f6d4e2")]

# Unlit Glow Palettes (`*_glow.png`)
EMBER_D = hexc("8c2438")
EMBER_R = hexc("c23b4b")
EMBER_O = hexc("ff8e47")
EMBER_H = hexc("ffd89a")

RUNE_D = hexc("a8324a")
RUNE_M = hexc("ff6a7a")
RUNE_G = hexc("ff8c68")
RUNE_H = hexc("ffe0a8")


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        px[y][x] = col


def get_px(px, x: int, y: int):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        return px[y][x]
    return CLEAR


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
    return 0.58 * vnoise(x, y, s) + 0.28 * vnoise(x * 2.05, y * 2.05, s + 11) + 0.14 * vnoise(x * 4.1, y * 4.1, s + 23)


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
# Shared Rich Material, Masonry, Foliage & Ground-Integration Helpers
# ==============================================================================
_LEAF_SET = set(MOSS + LICHEN + CLOVER_FL)
_WARM_SET = set(CRIMSON_STONE + BANNER_RED + EARTH + WOOD + LEATHER + RUST)


def outline_material(body):
    """Applies a 1px material-tinted dark outline around opaque pixels (foliage->OUT_LEAF, warm->OUT_WARM, stone->OUT)."""
    h, w = len(body), len(body[0])
    out = [row[:] for row in body]
    dirs = ((-1, 0), (1, 0), (0, -1), (0, 1))
    for y in range(h):
        for x in range(w):
            if body[y][x][3] > 0:
                continue
            nbrs = []
            for dx, dy in dirs:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and body[ny][nx][3] == 255:
                    nbrs.append(body[ny][nx])
            if nbrs:
                c = nbrs[0]
                if all(n in _LEAF_SET for n in nbrs):
                    out[y][x] = OUT_LEAF
                elif c in _WARM_SET:
                    out[y][x] = OUT_WARM
                else:
                    out[y][x] = OUT
    return out


def shade_stone_cluster(
    x: int,
    y: int,
    lit: float,
    seed: int,
    warm: bool = False,
    crimson_amt: float = 0.0,
    catch_top: float = 0.0,
    catch_left: float = 0.0,
    recess_br: float = 0.0,
):
    """Shades stone using smooth horizontal sedimentary clusters (never single-pixel noise)."""
    # Stretched horizontal grain gives authentic layered stone strata strokes (3-5px wide clusters)
    strata = (vnoise(x * 0.24, y * 0.68, seed) - 0.5) * 1.05
    broad = (vnoise(x * 0.13, y * 0.16, seed + 17) - 0.5) * 0.65
    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.34
    bevel = catch_top * 0.92 + catch_left * 0.58 - recess_br * 0.52

    # Clustered shallow stone pit (2-3px wide pocket, never isolated salt-and-pepper)
    pit_f = vnoise(x * 0.42, y * 0.52, seed + 41)
    pit = -0.85 if pit_f < 0.16 else 0.0

    if crimson_amt > 0.0:
        v = (lit + 0.06) * 5.8 + strata * 0.75 + broad * 0.5 + dith + bevel * 0.85 + pit * 0.55
        idx = int(clamp(round(v), 0, len(CRIMSON_STONE) - 1))
        return CRIMSON_STONE[idx]

    pal = WARM_STONE if warm else STONE
    v = lit * 7.1 + strata + broad + dith + bevel + pit
    idx = int(clamp(round(v), 0, len(pal) - 1))
    return pal[idx]


def darken_stone_px(col, steps: int = 1):
    """Darkens an existing stone/plaster pixel by `steps` along its own ramp for damp streaks & ambient occlusion."""
    for pal in (STONE, WARM_STONE, CRIMSON_STONE):
        if col in pal:
            i = pal.index(col)
            return pal[max(0, i - steps)]
    return col


def brighten_stone_px(col, steps: int = 1):
    for pal in (STONE, WARM_STONE, CRIMSON_STONE):
        if col in pal:
            i = pal.index(col)
            return pal[min(len(pal) - 1, i + steps)]
    return col


def apply_weathering_streak(px, x_center: int, y_start: int, length: int, width: int, seed: int):
    """Paints a tapering vertical damp/mineral stain streak downward across stone courses."""
    for dy in range(length):
        u = dy / max(1.0, float(length))
        drift = int(round((vnoise(x_center * 0.2, dy * 0.25, seed) - 0.5) * 1.6))
        hw = max(0, int(round(width * 0.5 * (1.0 - u * 0.75))))
        yy = y_start + dy
        for dx in range(-hw, hw + 1):
            xx = x_center + drift + dx
            cur = get_px(px, xx, yy)
            if cur[3] == 255:
                st = 2 if (dy < length * 0.45 and dx == 0) else 1
                put(px, xx, yy, darken_stone_px(cur, st))


def draw_rubble_pocket(px, cx: float, cy: float, rx: float, ry: float, lit_base: float, seed: int):
    """Draws exposed rough rubble-core cobbles inside collapsed wall breaches so ruins never look cleanly sliced."""
    rng = random.Random(seed)
    # Dark mortar matrix first
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            d = ((x - cx) / max(1.0, rx)) ** 2 + ((y - cy) / max(1.0, ry)) ** 2
            if d <= 1.0 + 0.25 * (hsh(x, y, seed) - 0.5):
                put(px, x, y, MORTAR_DEEP if (x + y) % 3 == 0 else STONE[0])
    # Pack small angular cobbles into the mortar core
    count = max(4, int((rx * ry) / 5.5))
    for i in range(count):
        ang = rng.uniform(0, math.tau)
        dist = math.sqrt(rng.random()) * 0.78
        sx = cx + math.cos(ang) * rx * dist
        sy = cy + math.sin(ang) * ry * dist
        srx = rng.uniform(1.8, 3.2)
        sry = rng.uniform(1.3, 2.3)
        warm = rng.random() < 0.30
        pal = WARM_STONE if warm else STONE
        for y in range(int(sy - sry - 1), int(sy + sry + 2)):
            for x in range(int(sx - srx - 1), int(sx + srx + 2)):
                u = (x - sx) / srx
                v = (y - sy) / sry
                if abs(u) ** 2.2 + abs(v) ** 2.2 <= 1.0:
                    l_c = lit_base - 0.18 * u - 0.24 * v
                    idx = int(clamp(round(l_c * 6.5), 1, 6))
                    put(px, x, y, pal[idx])


def draw_faceted_stone(
    px,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    tilt: float,
    seed: int,
    warm: bool = False,
    crimson: bool = False,
    lit_bias: float = 0.52,
):
    """Draws an angular chiseled fallen ashlar block or faceted river-cobble with planar bevels & mortar crease."""
    ca, sa = math.cos(tilt), math.sin(tilt)
    for y in range(int(cy - ry - 3), int(cy + ry + 4)):
        for x in range(int(cx - rx - 3), int(cx + rx + 4)):
            dx0, dy0 = x + 0.5 - cx, y + 0.5 - cy
            u = (dx0 * ca + dy0 * sa) / max(1.0, rx)
            v = (-dx0 * sa + dy0 * ca) / max(1.0, ry)
            # Polygonal chamfered metric + slight edge chip distortion
            chip = 0.12 * (vnoise(x * 0.45, y * 0.45, seed + 5) - 0.5)
            d = max(abs(u) * 0.88 + abs(v) * 0.42, abs(v) * 0.92 + abs(u) * 0.34, (abs(u) ** 3 + abs(v) ** 3) ** (1.0 / 3.0)) + chip
            if d <= 1.0:
                if d > 0.86 and (u > 0.15 or v > 0.20):
                    put(px, x, y, MORTAR_DEEP)
                else:
                    # 3 planar facets: sunlit top-left bevel, mid face, shadowed bottom-right facet
                    f_lit = lit_bias - 0.24 * u - 0.30 * v
                    if u < -0.35 and v < 0.25:
                        f_lit += 0.14
                    elif u > 0.35 or v > 0.42:
                        f_lit -= 0.14
                    ct = 1.0 if (v < -0.52 and d > 0.68) else 0.0
                    cl = 1.0 if (u < -0.55 and d > 0.68) else 0.0
                    col = shade_stone_cluster(
                        x, y, f_lit, seed, warm=warm,
                        crimson_amt=(1.0 if crimson else 0.0), catch_top=ct, catch_left=cl,
                    )
                    put(px, x, y, col)


def draw_moss_cushion(px, x0: int, x1: int, y_top: int, thick: int, hang: int, seed: int):
    """Paints plump, velvety multi-lobed moss cushions over stone ledges with damp darkened stone underneath."""
    w, h = len(px[0]), len(px)
    for x in range(max(2, x0), min(w - 2, x1 + 1)):
        u_span = (x - x0) / max(1.0, float(x1 - x0))
        envelope = math.sin(u_span * math.pi) ** 0.55
        lobe = 0.55 * math.sin(x * 0.48 + seed) + 0.45 * vnoise(x * 0.35, y_top * 0.35, seed + 5)
        drop = int(round(hang * envelope * max(0.0, lobe)))
        crown_lift = -1 if (envelope > 0.45 and vnoise(x * 0.4, 1.0, seed + 9) > 0.52) else 0
        yt = y_top + crown_lift
        yb = y_top + thick + drop
        for y in range(yt, yb + 1):
            if not (2 <= y < h - 2):
                continue
            if y > y_top + 1 and px[y][x][3] == 0:
                continue
            v_pos = (y - yt) / max(1.0, float(yb - yt + 1))
            # Directional cluster shading: sunlit top-left moss tufts, rich mid green, deep underside
            cl = (vnoise(x * 0.38, y * 0.42, seed + 13) - 0.5) * 0.55
            lit = (1.0 - v_pos) * 0.78 + (0.18 if u_span < 0.55 else 0.02) + cl
            if y == yt and u_span < 0.72:
                lit += 0.22
            idx = int(clamp(round(lit * 5.8), 0, len(MOSS) - 1))
            put(px, x, y, MOSS[idx])
        # Damp darkened stone fringe directly under hanging moss
        for dy_s in (1, 2):
            fy = yb + dy_s
            if 2 <= fy < h - 2 and px[fy][x][3] == 255 and px[fy][x] not in MOSS:
                px[fy][x] = darken_stone_px(px[fy][x], 2 if dy_s == 1 else 1)


def draw_ivy_vine(px, x_base: int, y_base: int, height: int, sway_dir: float, seed: int):
    """Draws a branching woody ivy vine with clustered 3-4px heart-shaped foliage pads and stone drop-shadow."""
    rng = random.Random(seed)
    stem_pts = []
    for k in range(height):
        u = k / max(1.0, float(height))
        vx = x_base + int(round(sway_dir * 3.2 * math.sin(u * 4.2 + seed * 0.3) + sway_dir * u * 2.5))
        vy = y_base - k
        if get_px(px, vx, vy)[3] == 255:
            stem_pts.append((vx, vy, u))
            # Woody climbing stem + subtle shadow pixel on right
            put(px, vx, vy, WOOD[2 if k % 3 != 0 else 3])
            if get_px(px, vx + 1, vy)[3] == 255:
                px[vy][vx + 1] = darken_stone_px(px[vy][vx + 1], 1)

    # Branch shoots & directional leaf clusters along the stem
    for idx_p, (vx, vy, u) in enumerate(stem_pts):
        if idx_p % 4 == 2:
            side = -1 if (idx_p // 4) % 2 == 0 else 1
            # Short woody side twig (2-4px)
            twig_len = 2 + (idx_p % 3)
            for tk in range(1, twig_len + 1):
                tx, ty = vx + side * tk, vy - tk // 2
                if get_px(px, tx, ty)[3] == 255:
                    put(px, tx, ty, WOOD[2])
            lx, ly = vx + side * twig_len, vy - twig_len // 2
            # Clustered 3x3 / 4x3 ivy leaf pad (top-left lit, bottom-right shaded)
            leaf_offsets = [
                (-1, -1, 5), (0, -1, 6 if side <= 0 else 5),
                (-1, 0, 4), (0, 0, 4), (1, 0, 3),
                (0, 1, 2), (1, 1, 1),
            ]
            for dx, dy, mi in leaf_offsets:
                if get_px(px, lx + dx, ly + dy)[3] == 255:
                    put(px, lx + dx, ly + dy, MOSS[max(1, mi - (1 if u > 0.75 else 0))])
        elif idx_p % 4 == 0 and idx_p > 1:
            for dx, dy, mi in [(-1, 0, 5), (0, 0, 4), (0, 1, 2), (1, 0, 3)]:
                if get_px(px, vx + dx, vy + dy)[3] == 255:
                    put(px, vx + dx, vy + dy, MOSS[mi])
    # Small terminal shoot leaves
    if stem_pts:
        tx, ty, _ = stem_pts[-1]
        for dx, dy, mi in [(0, -1, 5), (-1, 0, 6), (0, 0, 4), (1, 0, 2)]:
            if get_px(px, tx + dx, ty + dy)[3] == 255:
                put(px, tx + dx, ty + dy, MOSS[mi])


def draw_lichen_rosettes(px, boxes, count: int, seed: int):
    """Places multi-pixel crustose lichen rosettes on stone surfaces (never isolated 1px dots)."""
    rng = random.Random(seed)
    valid_stone = set(STONE[2:7] + WARM_STONE[2:7])
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 12:
        attempts += 1
        x0, y0, x1, y1 = boxes[rng.randrange(len(boxes))]
        lx = rng.randrange(x0, max(x0 + 1, x1))
        ly = rng.randrange(y0, max(y0 + 1, y1))
        if get_px(px, lx, ly) not in valid_stone:
            continue
        pattern = [(-1, 0, 2), (0, -1, 2), (0, 0, 1), (1, 0, 1), (0, 1, 0)] if placed % 2 == 0 else [(0, 0, 2), (1, 0, 1), (0, 1, 0)]
        for dx, dy, li in pattern:
            if get_px(px, lx + dx, ly + dy) in valid_stone:
                put(px, lx + dx, ly + dy, LICHEN[li])
        placed += 1


def paint_earth_shadow_skirt(out_px, cx: float, fy: float, rx: float, ry: float, seed: int):
    """Paints a clean cluster-lobed cool-violet shadow + damp forest-loam skirt (zero checkerboard noise)."""
    h, w = len(out_px), len(out_px[0])
    for y in range(max(0, int(fy - ry - 3)), min(h, int(fy + ry + 5))):
        for x in range(max(0, int(cx - rx - 5)), min(w, int(cx + rx + 6))):
            if out_px[y][x][3] == 255:
                continue
            u = (x + 0.5 - cx) / max(1.0, rx)
            v = (y + 0.5 - (fy + 0.6)) / max(1.0, ry)
            lobe = (fbm(x * 0.22, y * 0.38, seed) - 0.5) * 0.38
            d = math.sqrt(u * u + v * v) + lobe
            if d < 0.56:
                c_soil = EARTH[1 if vnoise(x * 0.4, y * 0.5, seed + 7) < 0.55 else 2]
                out_px[y][x] = (c_soil[0], c_soil[1], c_soil[2], 184)
            elif d < 0.78:
                out_px[y][x] = (24, 20, 36, 120)
            elif d < 0.98:
                out_px[y][x] = (*SHADOW_RGB, 60)


def draw_loam_and_pebbles(body, cx: float, fy: int, half_span: int, depth: int, seed: int):
    """Draws opaque clustered dark-earth clods & gravel pebbles along the foundation foot before outlining."""
    rng = random.Random(seed)
    for x in range(int(cx - half_span), int(cx + half_span) + 1):
        u = abs(x - cx) / max(1.0, float(half_span))
        if u > 1.0:
            continue
        wave = vnoise(x * 0.26, fy * 0.2, seed + 3)
        if wave < 0.28 + 0.35 * (u ** 1.6):
            continue
        top_y = fy - 1 - int((1.0 - u) * 1.5 * wave)
        bot_y = fy + int(round(depth * (1.0 - u * 0.65) * (0.55 + 0.6 * wave)))
        for y in range(top_y, bot_y + 1):
            cl = vnoise(x * 0.45, y * 0.55, seed + 9)
            e_idx = int(clamp(round((0.68 - 0.28 * (y - top_y) + (cl - 0.5) * 0.6) * 4.2), 0, 4))
            put(body, x, y, EARTH[e_idx])
    # Scatter small 2x2 / 3x2 crushed gravel pebbles into the loam
    p_cnt = max(3, half_span // 5)
    for i in range(p_cnt):
        px_c = int(cx + rng.uniform(-0.92, 0.92) * half_span)
        py_c = fy + rng.randint(-1, max(1, depth))
        pal = WARM_STONE if i % 3 == 0 else STONE
        put(body, px_c, py_c, pal[5])
        put(body, px_c + 1, py_c, pal[3])
        put(body, px_c, py_c + 1, pal[2])
        if i % 2 == 0:
            put(body, px_c - 1, py_c + 1, pal[4])


def plant_foreground_turf(out_px, tufts, clovers=()):
    """Plants crisp meadow grass tufts & clover clusters OVER the bottom stone outline so plinths sit IN the grass."""
    for tx, ty, size in tufts:
        if size >= 2:
            blades = [
                (-3, 0, 1), (-3, -1, 3), (-4, -2, 4),
                (-2, 0, 1), (-2, -1, 2), (-2, -2, 4), (-2, -3, 5),
                (-1, 0, 0), (-1, -1, 2), (-1, -2, 3),
                (0, 0, 1), (0, -1, 3), (0, -2, 5), (0, -3, 6), (0, -4, 6),
                (1, 0, 0), (1, -1, 2), (1, -2, 4), (1, -3, 5),
                (2, 0, 1), (2, -1, 3), (3, -2, 4),
            ]
        else:
            blades = [
                (-2, 0, 1), (-2, -1, 4),
                (-1, 0, 1), (-1, -1, 3), (-1, -2, 5),
                (0, 0, 0), (0, -1, 2), (0, -2, 4), (0, -3, 6),
                (1, 0, 1), (1, -1, 3), (2, -2, 4),
            ]
        # Subtle dark leaf-ink root pixels at bottom so tuft separates cleanly without boxy outline
        for dx_o in (-2, -1, 0, 1):
            if get_px(out_px, tx + dx_o, ty + 1)[3] < 200:
                put(out_px, tx + dx_o, ty + 1, OUT_LEAF)
        for dx, dy, mi in blades:
            put(out_px, tx + dx, ty + dy, MOSS[mi])

    for cx, cy in clovers:
        leaves = [(-2, 0, 3), (-1, -1, 5), (0, 0, 2), (1, -1, 4), (2, 0, 3), (-1, 0, 4), (1, 0, 2)]
        for dx, dy, mi in leaves:
            put(out_px, cx + dx, cy + dy, MOSS[mi])
        put(out_px, cx, cy - 2, CLOVER_FL[2])
        put(out_px, cx + 1, cy - 2, CLOVER_FL[1])
        put(out_px, cx, cy - 1, CLOVER_FL[0])


# ==============================================================================
# Irregular Weathered Castle Masonry Engine (Watchtower & Bastion)
# ==============================================================================
def paint_irregular_fortress_wall(
    body,
    fx: int,
    y_top: int,
    y_bot: int,
    hw_fn,
    span_fn,
    lit_fn,
    crimson_bands,
    curve_sag: float,
    seed: int,
):
    """Builds multi-course irregular ashlar masonry with varied heights, jumper blocks, snecks,
    ~25% warm sandstone-violet accents, damp blocks, chipped corners, and flaky crimson plaster bands."""
    rng = random.Random(seed)
    course_heights = [6, 8, 5, 9, 6, 7, 9, 5, 8, 7, 6, 9, 8, 6, 8, 7, 9, 6]
    courses = []
    yc = y_top
    ci = 0
    while yc <= y_bot:
        ch = course_heights[ci % len(course_heights)]
        courses.append((yc, min(y_bot + 2, yc + ch - 1), ch))
        yc += ch
        ci += 1

    # Pre-generate irregular block partitions + jumper/sneck flags per course
    jumper_occupied = set()  # (ci, x_int) covered by a 2-course jumper block from ci-1
    blocks = []  # (x0, x1, yt, yb, b_seed, warm, damp_bias, sneck)
    for c_idx, (yt, yb, ch) in enumerate(courses):
        hw_est = int(hw_fn((yt + yb) * 0.5)) + 6
        x_cur = fx - hw_est - rng.randint(0, 6)
        x_end = fx + hw_est + 6
        b_i = 0
        while x_cur <= x_end:
            bw = rng.choice((7, 8, 9, 11, 12, 14, 16, 10, 13))
            bx0 = x_cur
            bx1 = x_cur + bw - 1
            b_seed = seed + c_idx * 131 + b_i * 37

            # Skip columns already claimed by a tall jumper stone from the course above
            while bx0 <= bx1 and (c_idx, bx0) in jumper_occupied:
                bx0 += 1
            if bx1 - bx0 >= 3:
                # Truncate if hitting another jumper stone mid-span
                actual_x1 = bx0
                while actual_x1 < bx1 and (c_idx, actual_x1 + 1) not in jumper_occupied:
                    actual_x1 += 1
                if actual_x1 - bx0 >= 3:
                    r_mat = hsh(bx0, yt, b_seed)
                    warm = r_mat < 0.27
                    damp = -0.11 if r_mat > 0.85 else ((hsh(bx0, yb, b_seed + 3) - 0.5) * 0.12)
                    can_jump = (
                        c_idx + 1 < len(courses)
                        and (actual_x1 - bx0) >= 8
                        and hsh(c_idx, b_i, seed + 19) < 0.20
                    )
                    if can_jump:
                        _, yb_next, _ = courses[c_idx + 1]
                        for xx in range(bx0, actual_x1 + 1):
                            jumper_occupied.add((c_idx + 1, xx))
                        blocks.append((bx0, actual_x1, yt, yb_next, b_seed, warm, damp, False))
                    else:
                        is_sneck = (ch >= 8 and (actual_x1 - bx0) >= 9 and hsh(c_idx, b_i, seed + 29) < 0.18)
                        blocks.append((bx0, actual_x1, yt, yb, b_seed, warm, damp, is_sneck))
            x_cur += bw
            b_i += 1

    # Rasterize every stone block with perspective sag, broken mortar, corner chips & flaky crimson plaster
    for bx0, bx1, yt, yb, b_seed, warm, damp_bias, is_sneck in blocks:
        sneck_mid = (yt + yb) // 2
        chip_tl = hsh(bx0, yt, b_seed + 7) < 0.24
        chip_br = hsh(bx1, yb, b_seed + 11) < 0.28
        for x in range(bx0, bx1 + 1):
            hw = hw_fn(yt)
            rel_est = clamp((x - fx) / max(1.0, hw), -1.0, 1.0)
            sag = int(round(curve_sag * (1.0 - rel_est * rel_est)))
            for y_raw in range(yt, yb + 1):
                y = y_raw + sag
                if not (y_top - 2 <= y <= y_bot + 2):
                    continue
                hw_y = hw_fn(y)
                spans = span_fn(x, y, hw_y)
                if not spans:
                    continue

                # Determine sub-block bounds if split into two thin levelling sneck stones
                sub_yt = yt if (not is_sneck or y_raw < sneck_mid) else (sneck_mid + 1)
                sub_yb = (sneck_mid - 1) if (is_sneck and y_raw < sneck_mid) else yb
                sub_warm = (not warm) if (is_sneck and y_raw > sneck_mid) else warm

                is_h_joint = (y_raw == yb) or (is_sneck and y_raw == sneck_mid)
                is_v_joint = (x == bx1)
                in_chip_tl = chip_tl and (x - bx0) + (y_raw - sub_yt) <= 1
                in_chip_br = chip_br and (bx1 - x) + (sub_yb - y_raw) <= 1

                base_lit = clamp(lit_fn(x, y, hw_y) + damp_bias, 0.08, 0.94)

                # Check if pixel falls in a weathered crimson Order plaster/frieze band
                crimson_amt = 0.0
                plaster_rim = False
                gold_fleck = False
                for cb_y0, cb_y1 in crimson_bands:
                    if cb_y0 <= y_raw <= cb_y1:
                        # Clustered plaster survival mask: peels away in organic patches showing stone & joints!
                        p_mask = fbm(x * 0.20, y * 0.26, seed + 91) - 0.10 * (abs(y_raw - (cb_y0 + cb_y1) * 0.5) / 3.5)
                        if p_mask > 0.39:
                            crimson_amt = 1.0
                            p_above = fbm(x * 0.20, (y - 1) * 0.26, seed + 91)
                            p_left = fbm((x - 1) * 0.20, y * 0.26, seed + 91)
                            if y_raw == cb_y0 or p_above <= 0.39 or p_left <= 0.39:
                                plaster_rim = True
                            if y_raw in (cb_y0, cb_y0 + 1) and (x // 2 + y_raw) % 5 == 0 and p_mask > 0.48:
                                gold_fleck = True

                if is_h_joint or is_v_joint or in_chip_tl or in_chip_br:
                    # Irregular weathered mortar: varies between deep crevice, mid mortar, and flush stone shadow
                    m_n = vnoise(x * 0.45, y * 0.45, seed + 53)
                    if crimson_amt > 0.0 and m_n > 0.58 and not in_chip_tl and not in_chip_br:
                        # Plaster bridges partway over shallow mortar joint with a dark hairline crease
                        put(body, x, y, CRIMSON_STONE[1 if base_lit > 0.45 else 0])
                    elif m_n < 0.42 or in_chip_tl or in_chip_br:
                        put(body, x, y, MORTAR_DEEP)
                    elif m_n < 0.78:
                        put(body, x, y, MORTAR_MID)
                    else:
                        put(body, x, y, (WARM_STONE if sub_warm else STONE)[1 if base_lit < 0.5 else 2])
                    continue

                if gold_fleck:
                    put(body, x, y, ORDER_GOLD[4 if base_lit > 0.5 else 2])
                    continue

                ct = 1.0 if (y_raw == sub_yt and vnoise(x * 0.35, sub_yt, b_seed + 13) > 0.24) else 0.0
                cl = 1.0 if (x == bx0 and vnoise(bx0, y * 0.35, b_seed + 17) > 0.28) else 0.0
                if in_chip_tl or (chip_tl and (x - bx0) + (y_raw - sub_yt) == 2):
                    ct = 1.15
                if plaster_rim:
                    ct = max(ct, 0.95)
                rb = 1.0 if (y_raw == sub_yb or x == bx1 - 1) else 0.0

                col = shade_stone_cluster(
                    x, y, base_lit, b_seed, warm=sub_warm,
                    crimson_amt=crimson_amt, catch_top=ct, catch_left=cl, recess_br=rb,
                )
                put(body, x, y, col)


# ==============================================================================
# 1. Order Watchtower (`order_watchtower.png` & `_glow.png`, 2x1 of 128x144, feet (64, 130))
# ==============================================================================
def build_watchtower_variant(variant: int):
    W, H = 128, 144
    FX, FY = 64, 130
    seed = 1301 + variant * 59
    body = blank(W, H)
    glow = GlowMap(W, H)

    if variant == 0:
        # ---- Col 0: Half-collapsed cliffside rectangular/battered stone watchtower (~114px tall, ~90px wide at plinth)
        def hw_v0(y: int) -> float:
            u = clamp((y - 16) / float(FY - 16), 0.0, 1.0)
            base_hw = 33.5 + 8.0 * (u ** 1.35)
            if y < 27:
                base_hw += 2.5  # Corbelled parapet overhang on surviving upper-left crown
            elif y >= 117:
                base_hw += 3.5 + (1.5 if y >= 124 else 0.0)  # Stepped battered foundation plinth
            return base_hw

        def collapse_right_x(y: int, hw: float) -> int:
            if y < 23:
                # Two surviving crenellated merlons on left/center-left with embrasure gap between them
                return FX - 1 + int(2.5 * math.sin(y * 0.7))
            if y < 36:
                return FX + 8 + int((y - 23) * 0.95 + 2.0 * math.sin(y * 0.5))
            if y < 56:
                return FX + 20 + int((y - 36) * 0.52 + 1.8 * math.cos(y * 0.4))
            if y < 74:
                return FX + 30 + int((y - 56) * 0.38)
            return int(round(FX + hw))

        def span_v0(x: int, y: int, hw: float) -> bool:
            left_x = int(round(FX - hw))
            right_x = collapse_right_x(y, hw)
            if not (left_x <= x <= right_x):
                return False
            # Surviving parapet merlon embrasure notch (`y = 16..22, x = FX-22..FX-13`)
            if y < 23 and (FX - 22 <= x <= FX - 13):
                return False
            # Uneven sunken stone baseline at very bottom (`y = 129..131`) so bottom isn't ruler-flat
            if y >= FY:
                dip = vnoise(x * 0.22, 7.0, seed + 5)
                if dip < 0.42:
                    return False
            return True

        def lit_v0(x: int, y: int, hw: float) -> float:
            u_down = clamp((y - 16) / float(FY - 16), 0.0, 1.0)
            rel = (x - FX) / max(1.0, hw)
            # 3/4 battered tower planes: bright sunlit left flank (`rel < -0.52`), mid front wall, cool shadowed right flank (`rel > 0.46`)
            lit = 0.63 - 0.28 * rel - 0.06 * u_down
            if rel < -0.52:
                lit += 0.16
            elif rel > 0.46:
                lit -= 0.18
            # Overhang shadow under machicolation corbels (`y = 27..32`) and plinth step (`y = 117..119`)
            if 27 <= y <= 31 and x < FX + 4:
                lit -= 0.18 * (1.0 - (y - 27) / 5.0)
            return lit

        # 1) Dark hollow ruined interior wall + exposed rubble-core behind the upper-right collapse (`y = 23..68`)
        for y in range(23, 70):
            hw = hw_v0(y)
            cx_r = collapse_right_x(y, hw)
            back_right = min(int(round(FX + hw)) - 2, cx_r + 16 - max(0, (34 - y) // 2))
            for x in range(max(FX - 5, cx_r - 3), back_right + 1):
                if y < 25 + (x - max(FX - 4, cx_r)) // 3:
                    continue
                in_row = (y - 23) % 6
                if in_row == 5 or (x + (y // 6) * 5) % 11 == 0:
                    put(body, x, y, MORTAR_DEEP)
                else:
                    put(body, x, y, STONE[1 if (x + y) % 5 != 0 else 2])

        # 2) Build main irregular weathered ashlar & flaky crimson plaster masonry (`y = 16..131`)
        paint_irregular_fortress_wall(
            body, FX, 16, FY + 1, hw_v0, span_v0, lit_v0,
            crimson_bands=[(43, 51), (105, 113)],
            curve_sag=0.5, seed=seed,
        )

        # Expose rough rubble-core pockets along the jagged fractured right wall edge!
        for rcx, rcy, rrx, rry in [(65, 25, 4.2, 2.8), (74, 34, 4.8, 3.2), (84, 46, 4.5, 3.5), (92, 60, 3.8, 3.2)]:
            draw_rubble_pocket(body, rcx, rcy, rrx, rry, 0.42, seed + rcx * 3)

        # 3) Dressed stone coping slabs on surviving merlons + carved machicolation corbel brackets (`y = 26..33`)
        for mx0, mx1 in [(28, 41), (51, 63)]:
            for x in range(mx0, mx1 + 1):
                put(body, x, 16, STONE[8 if x < mx0 + 8 else 6])
                put(body, x, 17, STONE[6 if x < mx0 + 8 else 4])
                put(body, x, 18, MORTAR_DEEP)
        # 4 stepped stone corbels supporting left parapet overhang (+ broken 5th corbel stub on right!)
        for ci_x in (31, 41, 51, 61, 70):
            broken = ci_x == 70
            h_corb = 4 if broken else 6
            for dy in range(h_corb):
                w_c = 2 if dy < 3 else 1
                for dx in range(-w_c, w_c + 1):
                    col = STONE[7 if dx < 0 and dy < 2 else (5 if dx <= 0 else 2)]
                    if dy == h_corb - 1:
                        col = MORTAR_DEEP
                    put(body, ci_x + dx, 27 + dy, col)
                # Deep cast shadow right beside each corbel bracket
                if get_px(body, ci_x + w_c + 1, 28 + dy)[3] == 255:
                    body[28 + dy][ci_x + w_c + 1] = STONE[0]

        # 4) Recessed Upper-Right Gallery / Lancet Arch (`cx = 76, cy = 61`, `y = 50..75`) with radiating voussoirs
        acx, acy = 76, 61
        for ay in range(49, 76):
            for ax in range(67, 86):
                dx_a = (ax - acx) / 6.2
                dy_a = (ay - acy) / 9.2
                r2 = dx_a * dx_a + dy_a * dy_a
                in_open = (ay <= acy and r2 <= 0.86) or (ay > acy and abs(dx_a) <= 0.86 and ay <= 73)
                in_voussoir = (ay <= acy + 1 and 0.86 < r2 <= 1.52) or (ay > acy and 0.86 < abs(dx_a) <= 1.24 and ay <= 73)
                if in_open:
                    # Deep vaulted interior shadow on left/top + sunlit inner stone reveal on right jamb (`ax >= acx+3`)
                    if ax >= acx + 3 and ay > acy - 5:
                        put(body, ax, ay, WARM_STONE[5 if (ay // 4) % 2 == 0 else 4])
                    elif ax == acx + 2 and ay > acy - 5:
                        put(body, ax, ay, STONE[2])
                    else:
                        put(body, ax, ay, MORTAR_DEEP if ay < acy - 2 or ax < acx - 1 else STONE[0])
                elif in_voussoir:
                    # Missing broken voussoirs on upper-right edge
                    if ax >= 82 and ay <= 57:
                        continue
                    if ay <= acy + 1:
                        ang = math.atan2(dy_a, dx_a)
                        wedge = (ang + math.pi) * 3.5
                        if abs(wedge - round(wedge)) < 0.13:
                            put(body, ax, ay, MORTAR_DEEP)
                        else:
                            w_i = int(wedge)
                            pal = CRIMSON_STONE if w_i % 3 == 1 else (WARM_STONE if w_i % 2 == 0 else STONE)
                            put(body, ax, ay, pal[6 if dx_a < 0 else 3])
                    else:
                        if (ay - acy) % 5 == 0:
                            put(body, ax, ay, MORTAR_DEEP)
                        else:
                            put(body, ax, ay, STONE[6 if ax < acx else 3])
        # Chamfered weathered window sill (`y = 74..75, x = 67..84`)
        for ax in range(67, 84):
            put(body, ax, 74, STONE[7 if ax < 76 else 5])
            put(body, ax, 75, MORTAR_DEEP)

        # 5) Deep Recessed Arched Gateway (`cx = 52, y = 93..130`) with Radiating Voussoirs & Riveted Rusted Portcullis!
        dcx, dcy = 52, 106
        for ay in range(93, FY + 1):
            for ax in range(39, 66):
                dx_d = (ax - dcx) / 9.2
                dy_d = (ay - dcy) / 10.5
                r2 = dx_d * dx_d + dy_d * dy_d
                in_portal = (ay <= dcy and r2 <= 0.72) or (ay > dcy and abs(dx_d) <= 0.76)
                in_recess = (ay <= dcy and 0.72 < r2 <= 0.94) or (ay > dcy and 0.76 < abs(dx_d) <= 0.92)
                in_voussoir = (ay <= dcy + 1 and 0.94 < r2 <= 1.48) or (ay > dcy and 0.92 < abs(dx_d) <= 1.28)
                in_hood = ay <= dcy and 1.48 < r2 <= 1.68

                if in_portal:
                    # Deep dark oak/vault interior behind the iron portcullis
                    bg = WOOD[0] if (ax + ay) % 5 == 0 else MORTAR_DEEP
                    put(body, ax, ay, bg)
                    # Heavy vertical spiked portcullis bars (`ax in (46, 50, 54, 58)`) + riveted horizontal cross-straps (`ay in (103, 112, 121)`)
                    on_vbar = ax in (46, 50, 54, 58) and ay <= 127
                    on_hbar = ay in (103, 112, 121)
                    if on_vbar and on_hbar:
                        # Raised brass/steel rivet stud at strap intersection!
                        put(body, ax, ay, ORDER_GOLD[4] if (ax + ay) % 2 == 0 else STEEL[6])
                    elif on_hbar:
                        put(body, ax, ay, RUST[3] if (ax * 3 + ay) % 7 == 0 else IRON[3 if ax < dcx else 2])
                        if ay + 1 < FY:
                            put(body, ax, ay + 1, IRON[0])
                    elif on_vbar:
                        put(body, ax, ay, RUST[4 if ax < dcx else 2] if (ay * 3 + ax) % 8 < 2 else IRON[4 if ax < dcx else 2])
                        put(body, ax + 1, ay, IRON[1])
                elif in_recess:
                    # Deep 2px architectural reveal: shadowed on left/arch soffit, sunlit dressed reveal on right!
                    if ax > dcx + 2 and ay > dcy - 4:
                        put(body, ax, ay, WARM_STONE[6 if (ay // 5) % 2 == 0 else 5])
                    else:
                        put(body, ax, ay, MORTAR_DEEP)
                elif in_voussoir:
                    if ay <= dcy + 1:
                        ang = math.atan2(dy_d, dx_d)
                        wedge = (ang + math.pi) * 4.2
                        is_j = abs(wedge - round(wedge)) < 0.11
                        if is_j:
                            put(body, ax, ay, MORTAR_DEEP)
                        else:
                            w_i = int(wedge)
                            # Prominent tall keystone at top center (`abs(dx_d) < 0.20`)
                            if abs(dx_d) < 0.19 and dy_d < -0.7:
                                put(body, ax, ay, ORDER_GOLD[4 if dx_d <= 0 else 2] if dy_d < -1.05 else WARM_STONE[7 if dx_d <= 0 else 5])
                            else:
                                pal = CRIMSON_STONE if w_i % 2 == 0 else (WARM_STONE if w_i % 3 == 0 else STONE)
                                put(body, ax, ay, pal[6 if dx_d < 0 else (4 if dx_d < 0.4 else 2)])
                    else:
                        j_row = (ay - dcy) % 6 == 0
                        if j_row:
                            put(body, ax, ay, MORTAR_DEEP)
                        else:
                            q_i = (ay - dcy) // 6
                            pal = CRIMSON_STONE if q_i % 2 == 0 else WARM_STONE
                            put(body, ax, ay, pal[6 if ax < dcx else 3])
                elif in_hood:
                    put(body, ax, ay, STONE[7 if dx_d < 0 else 3])

        # Worn stone threshold slabs stepping out from the gateway (`x = 41..63, y = 127..131`)
        for sy_t, sx0, sx1, l_t in [(127, 43, 61, 6), (129, 41, 63, 5)]:
            for sx in range(sx0, sx1 + 1):
                put(body, sx, sy_t, STONE[l_t if sx < dcx else l_t - 2] if sx not in (49, 56) else MORTAR_MID)
                put(body, sx, sy_t + 1, STONE[2] if sx != 49 else MORTAR_DEEP)

        # 6) Multi-Toned Carved Red Order Sun-Shield Crest (`cx = 51, cy = 46`) in Sunken Relief Panel
        scx, scy = 51, 46
        # Cast drop-shadow below/right of raised stone shield escutcheon
        for dy in range(-8, 10):
            hw_s = 7.0 if dy < -1 else max(0.5, 7.0 * (1.0 - ((dy + 1) / 10.5) ** 1.35))
            for dx in range(-8, 9):
                if abs(dx - 1) <= hw_s and dy >= -7:
                    if get_px(body, scx + dx, scy + dy)[3] == 255:
                        body[scy + dy][scx + dx] = darken_stone_px(body[scy + dy][scx + dx], 2)
        for dy in range(-8, 9):
            hw_s = 7.0 if dy < -1 else max(0.6, 7.0 * (1.0 - ((dy + 1) / 9.8) ** 1.35))
            for dx in range(-7, 8):
                if abs(dx) <= hw_s:
                    # Chipped upper-right shield corner
                    if dx >= 5 and dy <= -6:
                        put(body, scx + dx, scy + dy, MORTAR_DEEP)
                        continue
                    rim = (abs(dx) >= hw_s - 1.2) or (dy == -8)
                    if rim:
                        g_idx = 6 if (dx < 0 and dy < 0) else (4 if dx <= 0 or dy == -8 else 2)
                        put(body, scx + dx, scy + dy, ORDER_GOLD[g_idx])
                    else:
                        # Quartered sculpted crimson-and-stone shield field
                        c_idx = 5 if (dx < 0 and dy < 0) else (4 if dx <= 0 else (2 if dy < 2 else 1))
                        put(body, scx + dx, scy + dy, CRIMSON_STONE[c_idx])
        # Raised Sun-Ring + Vertical Greatsword Relief inside escutcheon
        for dx, dy in [(-3, -2), (-2, -3), (2, -3), (3, -2), (-3, 0), (3, 0), (-2, 2), (2, 2)]:
            put(body, scx + dx, scy + dy, ORDER_GOLD[5 if dx < 0 else 3])
        for dy in range(-6, 7):
            put(body, scx, scy + dy, ORDER_GOLD[6 if dy <= -1 else 4])
        for dx in (-4, -3, -2, 2, 3, 4):
            put(body, scx + dx, scy - 2, ORDER_GOLD[5 if dx < 0 else 3])
        glow.emit(body, scx, scy - 2, ORDER_GOLD[6], EMBER_O, halo=1)
        glow.emit(body, scx, scy - 1, CRIMSON_STONE[6], EMBER_R, halo=1)

        # 7) Intricate Wrought-Iron Wall-Sconce Cage Niche (`cx = 72, cy = 97`)
        lcx, lcy = 72, 97
        # Sunken arched niche with warm lantern light bounce on inner stones + soot hood above
        for dy in range(-9, 8):
            for dx in range(-6, 7):
                if dy == -9 and abs(dx) <= 2:
                    put(body, lcx + dx, lcy + dy, ASH[0])  # Soot smudge above niche
                elif abs(dx) <= 4 and -6 <= dy <= 4 and not (dy == -6 and abs(dx) >= 3):
                    d_l = math.hypot(dx, dy)
                    put(body, lcx + dx, lcy + dy, WARM_STONE[3] if d_l < 2.8 else (CRIMSON_STONE[1] if d_l < 4.0 else MORTAR_DEEP))
                elif abs(dx) == 5 and -5 <= dy <= 5:
                    put(body, lcx + dx, lcy + dy, WARM_STONE[6 if dx > 0 else 2])
                elif dy == 5 and abs(dx) <= 5:
                    put(body, lcx + dx, lcy + dy, WARM_STONE[7 if dx < 0 else 4])
                elif dy == 6 and abs(dx) <= 5:
                    put(body, lcx + dx, lcy + dy, MORTAR_DEEP)
        # Forged iron bracket hood, finial spike, bottom tray & 3D cage ribs
        put(body, lcx, lcy - 7, IRON[5])
        put(body, lcx, lcy - 6, IRON[4])
        for dx in (-4, -3, -2, -1, 0, 1, 2, 3, 4):
            put(body, lcx + dx, lcy - 4, IRON[5 if dx < 0 else (3 if dx <= 1 else 2)])
            put(body, lcx + dx, lcy + 3, IRON[4 if dx <= 0 else 2])
        for dy in (-3, -2, -1, 0, 1, 2):
            put(body, lcx - 3, lcy + dy, IRON[4])
            put(body, lcx + 3, lcy + dy, IRON[1])
            if dy in (-3, 2):
                put(body, lcx, lcy + dy, IRON[3])
        put(body, lcx, lcy + 4, IRON[3])
        # Glowing warm crimson-amber Order lantern flame
        glow.emit(body, lcx, lcy - 1, ORDER_GOLD[7], EMBER_H, halo=2)
        glow.emit(body, lcx, lcy, ORDER_GOLD[7], EMBER_H, halo=2)
        glow.emit(body, lcx - 1, lcy, ORDER_GOLD[5], EMBER_O, halo=2)
        glow.emit(body, lcx + 1, lcy, EMBER_R, EMBER_O, halo=1)
        glow.emit(body, lcx, lcy + 1, EMBER_R, EMBER_R, halo=2)

        # 8) Deep structural fracture cracks + vertical weathering streaks
        for k in range(28):
            cy_c = 54 + k
            cx_c = 63 + int(round(2.4 * math.sin(k * 0.31) + k * 0.08))
            put(body, cx_c, cy_c, MORTAR_DEEP)
            if k % 3 != 0:
                put(body, cx_c + 1, cy_c, STONE[7 if k < 16 else 6])
        for sx_w, sy_w, slen, sw in [(36, 23, 18, 3), (51, 56, 15, 3), (73, 76, 12, 4), (81, 76, 19, 3), (33, 80, 22, 3)]:
            apply_weathering_streak(body, sx_w, sy_w, slen, sw, seed + sx_w)

        # 9) Fallen ashlar & crimson rubble blocks + loam/pebbles + branching ivy & moss cushions!
        draw_loam_and_pebbles(body, FX + 1, FY, 49, 4, seed + 201)
        # Worn flagstone & cobble threshold path stepping out from the arched gateway (`x = 43..61, y = 130..133`)
        for sy_p, sx0, sx1, wi in [(130, 44, 60, 5), (132, 46, 58, 4)]:
            for sx in range(sx0, sx1 + 1):
                if sx not in (50, 55):
                    put(body, sx, sy_p, WARM_STONE[wi if sx < 52 else wi - 1])
                    put(body, sx, sy_p + 1, STONE[2])

        for fx_b, fy_b, rx_b, ry_b, tilt, wrm, cr in [
            (92, 126, 7.6, 4.2, 0.22, False, False),
            (103, 128, 6.4, 3.6, -0.18, False, True),
            (82, 128, 5.6, 3.3, 0.14, True, False),
            (111, 130, 4.2, 2.5, 0.28, False, False),
            (23, 128, 6.0, 3.4, -0.16, True, False),
            (32, 130, 4.4, 2.5, 0.10, False, False),
        ]:
            draw_faceted_stone(body, fx_b, fy_b, rx_b, ry_b, tilt, seed + int(fx_b), warm=wrm, crimson=cr)

        draw_ivy_vine(body, 31, FY - 2, 38, 0.85, seed + 301)
        draw_ivy_vine(body, 88, FY - 3, 27, -0.75, seed + 307)
        draw_lichen_rosettes(body, [(26, 34, 42, 90), (62, 76, 96, 122)], 16, seed + 401)

        draw_moss_cushion(body, 28, 42, 16, 2, 5, seed + 1)
        draw_moss_cushion(body, 53, 63, 16, 2, 4, seed + 2)
        draw_moss_cushion(body, 63, 76, 31, 2, 4, seed + 3)
        draw_moss_cushion(body, 24, 43, 77, 2, 5, seed + 5)
        draw_moss_cushion(body, 27, 40, 43, 2, 3, seed + 6)   # Moss creep across left crimson band (keeping crest clear!)
        draw_moss_cushion(body, 84, 96, 46, 2, 3, seed + 10)  # Moss creep across right crimson band!
        draw_moss_cushion(body, 64, 77, 106, 2, 3, seed + 8)  # Moss creep across lower crimson band below sconce!
        draw_moss_cushion(body, 19, 38, 117, 2, 4, seed + 7)
        draw_moss_cushion(body, 86, 106, 123, 2, 3, seed + 9)

        framed = outline_material(body)
        paint_earth_shadow_skirt(framed, FX + 2, FY + 1, rx=55.0, ry=6.8, seed=seed + 501)
        # Organic asymmetric meadow grass & clover groupings (leaving gateway threshold path x=44..60 open!)
        plant_foreground_turf(
            framed,
            tufts=[
                (16, 130, 2), (21, 131, 1), (29, 131, 2), (38, 131, 2),
                (64, 131, 2), (69, 132, 1), (78, 131, 2), (87, 131, 1),
                (94, 131, 2), (106, 131, 2), (112, 130, 1),
            ],
            clovers=[(25, 132), (73, 132), (99, 132)],
        )
        return framed, glow.finish()

    else:
        # ---- Col 1: Octagonal/Round Bastion Ruin with Vaulted Spiral Staircase, Broken Corbels & Iron Brazier Sconce!
        def hw_v1(y: int) -> float:
            u = clamp((y - 22) / float(FY - 22), 0.0, 1.0)
            base_hw = 36.0 + 7.5 * (u ** 1.38)
            if y >= 117:
                base_hw += 3.5 + (1.5 if y >= 124 else 0.0)
            return base_hw

        def is_curtain_breach(x: int, y: int, hw: float) -> bool:
            if y < 28 and x > FX - 15 + int(3 * math.sin(x * 0.4)):
                return True
            if 28 <= y < 56:
                bx0 = FX - 5 + (y - 28) * 0.42 + 1.5 * math.sin(y * 0.5)
                bx1 = FX + hw - 5 - (10 if y < 37 else (4 if y < 47 else 0))
                if bx0 < x < bx1:
                    return True
            if 56 <= y < 74:
                bx0 = FX + 7 + (y - 56) * 0.56
                bx1 = FX + hw - 8
                if bx0 < x < bx1:
                    return True
            return False

        def span_v1(x: int, y: int, hw: float) -> bool:
            if abs(x - FX) > hw:
                return False
            # Fractured stepped top on the surviving right wall pier (`x > FX + 18, y < 31`)
            if x > FX + 18 and y < 27 + (x - (FX + 18)) // 3 + (2 if x > FX + 29 else 0):
                return False
            if is_curtain_breach(x, y, hw):
                return False
            if y < 25 and (FX - 29 <= x <= FX - 22):
                return False  # Left parapet embrasure notch
            if y >= FY and vnoise(x * 0.24, 11.0, seed + 5) < 0.42:
                return False
            return True

        def lit_v1(x: int, y: int, hw: float) -> float:
            u_down = clamp((y - 22) / float(FY - 22), 0.0, 1.0)
            rel = (x - FX) / max(1.0, hw)
            # 3 octagonal faces: bright sunlit left face (`rel < -0.36`), mid front face, cool dark right face (`rel > 0.36`)
            if rel < -0.36:
                facet_lit = 0.78 - 0.14 * (rel + 0.68)
            elif rel < 0.36:
                facet_lit = 0.54 - 0.20 * rel
            else:
                facet_lit = 0.28 - 0.18 * (rel - 0.36)
            # Crisp sunlit ridge catch along left octagonal quoin seam (`abs(rel + 0.36) < 0.04`)
            if abs(rel + 0.36) < 0.045:
                facet_lit += 0.12
            return facet_lit - 0.05 * u_down

        # 1) Deep Cavernous Interior Curved Back-Wall + Central Cylindrical Newel Pillar (`y = 26..75`)
        for y in range(26, 76):
            hw = hw_v1(y)
            for x in range(int(FX - hw + 3), int(FX + hw - 3)):
                if not is_curtain_breach(x, y, hw):
                    continue
                top_back_y = 27 + max(0, (x - (FX - 10)) // 4) * 2 + int(2.2 * math.sin(x * 0.45))
                if y < top_back_y:
                    continue
                # Stout central spiral-stair newel column (`x = FX-2 .. FX+5, y >= 32`)
                if FX - 2 <= x <= FX + 5 and y >= 32:
                    u_n = (x - (FX + 1.5)) / 4.0
                    n_lit = 0.62 - 0.34 * u_n
                    if (y - 32) % 7 == 6:
                        put(body, x, y, MORTAR_DEEP)
                    else:
                        put(body, x, y, shade_stone_cluster(x, y, n_lit, seed + 21, warm=(y // 7) % 3 == 0, catch_left=(1.0 if x == FX - 2 else 0.0)))
                else:
                    # Deep vaulted interior concave ashlar wall with crimson plaster remnant & small rear slit
                    rel = (x - FX) / hw
                    in_lit = 0.11 + 0.12 * max(0.0, rel)
                    # Small dark rear gallery slit (`x = 76..78, y = 41..49`)
                    if 76 <= x <= 78 and 41 <= y <= 49:
                        put(body, x, y, MORTAR_DEEP)
                        continue
                    c_row = (y - int(round(1.6 * (1.0 - rel * rel)))) % 7
                    if c_row == 6 or (x + (y // 7) * 5) % 10 == 0:
                        put(body, x, y, MORTAR_DEEP)
                    else:
                        cr_in = 1.0 if (51 <= y <= 57 and fbm(x * 0.25, y * 0.25, seed + 33) > 0.44) else 0.0
                        put(body, x, y, shade_stone_cluster(x, y, in_lit, seed + 23, crimson_amt=cr_in))

        # 2) Build outer octagonal/curved irregular ashlar wall (`curve_sag = 2.4` gives authentic 3/4 drum curvature!)
        paint_irregular_fortress_wall(
            body, FX, 22, FY + 1, hw_v1, span_v1, lit_v1,
            crimson_bands=[(51, 58), (107, 114)],
            curve_sag=2.4, seed=seed + 17,
        )

        # Exposed rubble-core pockets & broken corbel stubs along the breached upper curtain wall!
        for rcx, rcy, rrx, rry in [(50, 27, 4.0, 2.6), (59, 36, 4.2, 3.0), (66, 51, 4.0, 3.0), (96, 42, 3.8, 3.2), (98, 58, 3.6, 3.0)]:
            draw_rubble_pocket(body, rcx, rcy, rrx, rry, 0.38, seed + rcx * 5)

        # 3) Deeply Recessed Ascending Spiral Staircase Steps + Cantilevered Corbels (`y = 38..71`)
        for st_i in range(8):
            sy = 69 - st_i * 4
            # Steps fan & wrap around the central newel post `(FX+1)`
            sx0 = FX + 2 + (st_i % 4) * 3 - (7 if st_i >= 4 else 0)
            sx1 = sx0 + (14 if st_i < 5 else 11)
            for xx in range(sx0, sx1 + 1):
                # Chipped step nose on outer end
                if xx >= sx1 - 1 and st_i % 2 == 1:
                    continue
                # Sunlit top tread (`sy`), dressed riser (`sy+1`), deep under-step corbel shadow (`sy+2, sy+3`)
                put(body, xx, sy, WARM_STONE[7 if xx < sx0 + 7 else 6] if st_i % 3 == 0 else STONE[7 if xx < sx0 + 7 else 5])
                put(body, xx, sy + 1, STONE[4 if xx < sx0 + 6 else 3])
                put(body, xx, sy + 2, STONE[1])
                if get_px(body, xx, sy + 3)[3] == 255:
                    put(body, xx, sy + 3, MORTAR_DEEP)
            # Broken corbel bracket stub under every other step!
            put(body, sx0 + 2, sy + 3, STONE[3])
            put(body, sx0 + 3, sy + 3, STONE[2])

        # 4) Deeply Splayed Lancet Arrow-Slit on Sunlit Left Octagonal Face (`x = 38..46, y = 63..89`)
        for yy in range(63, 90):
            # Outer chamfered stone surround
            if yy in (63, 64, 89):
                for xx in range(38, 47):
                    put(body, xx, yy, CRIMSON_STONE[5 if xx < 43 else 3] if yy == 63 else WARM_STONE[7 if xx < 43 else 5])
            else:
                put(body, 39, yy, STONE[4])   # Left shadowed outer splay
                put(body, 40, yy, STONE[1])
                put(body, 41, yy, MORTAR_DEEP)  # Narrow dark arrow-slit aperture
                put(body, 42, yy, MORTAR_DEEP)
                put(body, 43, yy, WARM_STONE[7])  # Bright sunlit right inner splay bevel!
                put(body, 44, yy, WARM_STONE[6])
                if yy in (73, 81):  # Cross-let / stirrup widening of medieval arrow loop
                    put(body, 40, yy, MORTAR_DEEP)
                    put(body, 43, yy, MORTAR_DEEP)
                    put(body, 44, yy, WARM_STONE[7])

        # Sculpted Red Order Relief Escutcheon below arrow-slit (`cx = 42, cy = 99`)
        for dy in range(-5, 6):
            hw_p = 4 if dy < 0 else max(0, 5 - dy)
            for dx in range(-hw_p, hw_p + 1):
                if abs(dx) == hw_p or dy == -5:
                    put(body, 42 + dx, 99 + dy, ORDER_GOLD[5 if dx <= 0 else 2])
                else:
                    put(body, 42 + dx, 99 + dy, CRIMSON_STONE[5 if dx < 0 else 2])
        for dy in (-3, -2, -1, 0, 1, 2):
            put(body, 42, 99 + dy, ORDER_GOLD[6 if dy <= 0 else 4])
        glow.emit(body, 42, 98, ORDER_GOLD[6], EMBER_O, halo=1)
        glow.emit(body, 42, 99, CRIMSON_STONE[6], EMBER_R, halo=1)

        # 5) Ornate Forged-Iron Brazier Sconce on Front Bastion Pier (`cx = 74, cy = 88`)
        bcx, bcy = 74, 88
        # Soot stain + warm ember glow bounce on stone pier behind brazier
        for dy in range(-9, -3):
            for dx in range(-3, 4):
                if get_px(body, bcx + dx, bcy + dy)[3] == 255:
                    body[bcy + dy][bcx + dx] = darken_stone_px(body[bcy + dy][bcx + dx], 2 if abs(dx) <= 1 else 1)
        # Wall mounting plate + diagonal scroll strut (`x = bcx-6 .. bcx, y = bcy .. bcy+8`)
        for dy in range(-1, 9):
            put(body, bcx - 5, bcy + dy, IRON[4 if dy < 3 else 2])
            put(body, bcx - 4, bcy + dy, IRON[1])
        for k in range(6):
            put(body, bcx - 4 + k, bcy + 6 - k, IRON[3])
            put(body, bcx - 4 + k, bcy + 7 - k, IRON[1])
        # Fluted iron fire-basket with top spikes & riveted iron rings (`x = bcx-6..bcx+6, y = bcy-3..bcy+3`)
        for dx in (-6, -3, 0, 3, 6):
            put(body, bcx + dx, bcy - 4, IRON[5 if dx <= 0 else 3])
        for dy in range(-3, 4):
            hw_b = 6 - max(0, (dy + 1) // 2)
            for dx in range(-hw_b, hw_b + 1):
                if dy in (-3, 0, 3):
                    col = ORDER_GOLD[4] if (dy == 0 and dx in (-4, 0, 4)) else IRON[4 if dx < 0 else 2]
                    put(body, bcx + dx, bcy + dy, col)
                elif dx % 2 == 0:
                    put(body, bcx + dx, bcy + dy, IRON[3 if dx < 0 else 1])
                else:
                    put(body, bcx + dx, bcy + dy, EMBER_R if dy < 0 else (EMBER_D if dy == 1 else IRON[0]))
        # Glowing crimson-gold coals in `order_watchtower_glow.png`
        for gx, gy, d_c, b_c, hl in [
            (bcx, bcy - 4, ORDER_GOLD[7], EMBER_H, 2),
            (bcx - 2, bcy - 3, ORDER_GOLD[5], EMBER_H, 2),
            (bcx + 1, bcy - 3, EMBER_O, EMBER_O, 2),
            (bcx - 1, bcy - 2, EMBER_R, EMBER_H, 2),
            (bcx + 3, bcy - 3, EMBER_R, EMBER_O, 1),
            (bcx - 3, bcy - 2, EMBER_D, EMBER_R, 1),
            (bcx + 1, bcy - 1, EMBER_D, EMBER_R, 1),
        ]:
            glow.emit(body, gx, gy, d_c, b_c, halo=hl)

        # Weathering streaks + structural hairline crack on front pier
        for k in range(22):
            cy_c = 73 + k
            cx_c = 58 + int(round(1.8 * math.sin(k * 0.34)))
            put(body, cx_c, cy_c, MORTAR_DEEP)
            put(body, cx_c + 1, cy_c, STONE[6])
        for sx_w, sy_w, slen, sw in [(34, 29, 20, 3), (42, 90, 8, 3), (88, 76, 22, 4), (64, 72, 18, 3)]:
            apply_weathering_streak(body, sx_w, sy_w, slen, sw, seed + sx_w)

        # Fallen curved voussoirs, loam & gravel, branching ivy & moss cushions!
        draw_loam_and_pebbles(body, FX + 1, FY, 50, 4, seed + 211)
        for fx_b, fy_b, rx_b, ry_b, tilt, wrm, cr in [
            (85, 126, 7.8, 4.1, 0.30, False, True),
            (97, 128, 7.2, 3.8, -0.24, True, False),
            (108, 129, 5.5, 3.0, 0.18, False, False),
            (22, 128, 6.4, 3.5, -0.20, False, False),
            (32, 130, 4.8, 2.7, 0.14, True, False),
        ]:
            draw_faceted_stone(body, fx_b, fy_b, rx_b, ry_b, tilt, seed + int(fx_b), warm=wrm, crimson=cr)

        draw_ivy_vine(body, 33, FY - 2, 36, 1.0, seed + 311)
        draw_ivy_vine(body, 89, FY - 3, 32, -1.0, seed + 317)
        draw_lichen_rosettes(body, [(25, 34, 98, 122)], 18, seed + 411)

        draw_moss_cushion(body, 28, 49, 22, 3, 5, seed + 31)
        draw_moss_cushion(body, 86, 96, 28, 2, 3, seed + 32)  # Moss tuft on fractured right pier crown!
        draw_moss_cushion(body, 83, 101, 73, 2, 4, seed + 33)
        draw_moss_cushion(body, 48, 62, 54, 2, 3, seed + 34)  # Moss creep over upper crimson band!
        draw_moss_cushion(body, 63, 78, 108, 2, 3, seed + 36)  # Moss creep over lower crimson band!
        draw_moss_cushion(body, 20, 44, 117, 2, 4, seed + 35)
        draw_moss_cushion(body, 82, 106, 123, 2, 3, seed + 37)

        framed = outline_material(body)
        paint_earth_shadow_skirt(framed, FX + 2, FY + 1, rx=56.0, ry=6.8, seed=seed + 511)
        plant_foreground_turf(
            framed,
            tufts=[
                (16, 130, 2), (24, 131, 1), (34, 131, 2), (49, 131, 2),
                (56, 132, 1), (68, 131, 2), (80, 131, 1), (88, 131, 2),
                (99, 131, 2), (110, 130, 2),
            ],
            clovers=[(20, 132), (43, 132), (74, 132), (104, 132)],
        )
        return framed, glow.finish()


# ==============================================================================
# 2. Order Patrol Camp (`order_patrol_camp.png` & `_glow.png`, 2x1 of 96x64, feet (48, 52))
# ==============================================================================
def build_patrol_camp_variant(variant: int):
    W, H = 96, 64
    FX, FY = 48, 52
    seed = 1511 + variant * 43
    body = blank(W, H)
    glow = GlowMap(W, H)

    if variant == 0:
        # ---- Col 0: Cold Hearth, Greatsword, Pack & Heater Shield (keeping x ~ 68..84 clear on right for banner!)
        # 1) Trodden loam, pebbles & mossy turf contact patch (`x = 11..66, y = 45..52`)
        draw_loam_and_pebbles(body, 38, 49, 27, 3, seed + 1)

        # 2) Weathered Buckled Leather Pack (`x = 11..25, y = 35..48`) with stitched flap & bedroll roll on top
        for y in range(36, 49):
            for x in range(11, 25):
                dx, dy = (x - 17.5) / 6.5, (y - 42.5) / 6.0
                if dx * dx + dy * dy <= 1.0:
                    flap_edge = abs(y - (40 + int(abs(x - 17.5) * 0.35))) == 0
                    lit = 0.62 - 0.32 * dx - 0.34 * dy + (0.14 if y < 40 else 0.0)
                    col = LEATHER[int(clamp(round(lit * 5.0), 0, 5))]
                    if flap_edge:
                        col = LEATHER[5] if x % 2 == 0 else LEATHER[1]  # Stitched leather flap seam!
                    if x in (15, 20) and y >= 38:
                        col = ORDER_GOLD[5] if y == 42 else (ORDER_GOLD[3] if y == 43 else LEATHER[1])
                    put(body, x, y, col)

        # 3) Tilted Red Order Heater Shield (`cx = 26, cy = 42`) with Oak Plank Grain & Battered Notched Iron Rim!
        for dy in range(-7, 8):
            hw_sh = 6.2 if dy < -1 else max(0.7, 6.2 * (1.0 - ((dy + 1) / 9.2) ** 1.32))
            for dx in range(-6, 7):
                sx = int(round(26.5 + dx - dy * 0.22))
                sy = 42 + dy
                if abs(dx) <= hw_sh:
                    # Battle notch chopped into right iron rim (`dy in (-2, -1)`)
                    if dy in (-2, -1) and dx >= hw_sh - 1.3:
                        continue
                    is_rim = (abs(dx) >= hw_sh - 1.15) or (dy == -7)
                    if is_rim:
                        # Battered iron & tarnished brass shield rim with rivets
                        if (dx + dy) % 4 == 0:
                            put(body, sx, sy, ORDER_GOLD[4 if dx <= 0 else 2])
                        else:
                            put(body, sx, sy, IRON[5 if (dx < 0 and dy < 0) else (3 if dx <= 0 else 1)])
                    else:
                        # Flaked crimson paint exposing vertical oak wood planks (`dx in (1, 2)` or lower scar)!
                        scar = (dx in (1, 2) and -4 <= dy <= 3) or (dx == -2 and dy >= 2)
                        if scar:
                            plank_seam = (dx == 1 and dy % 2 == 0)
                            put(body, sx, sy, WOOD[1] if plank_seam else WOOD[4 if dy < 0 else 2])
                        else:
                            c_idx = 5 if (dx < 0 and dy < 0) else (4 if dx <= 0 else 2)
                            put(body, sx, sy, CRIMSON_STONE[c_idx])
        # Faded gold Red Order sun-cross blazon on shield center
        for bdx, bdy, gi in [(0, -3, 5), (0, -2, 6), (0, -1, 5), (0, 0, 4), (0, 1, 3), (-2, -2, 5), (-1, -2, 6), (1, -2, 3)]:
            put(body, int(round(26.5 + bdx - bdy * 0.22)), 42 + bdy, ORDER_GOLD[gi])

        # 4) Cold Ash Pit (`cx = 52, cy = 46`, safely left of x=68!) with White/Grey Wood-Ash Clusters, Charred Wood Grain & Varied River-Stones
        fcx, fcy = 52, 46
        # Sunken soot pit + clustered white/pale-grey wood-ash mounds
        for y in range(fcy - 5, fcy + 5):
            for x in range(fcx - 10, fcx + 11):
                d = ((x - fcx) / 9.5) ** 2 + ((y - fcy) / 4.6) ** 2
                if d <= 0.72:
                    cl = vnoise(x * 0.55, y * 0.65, seed + 11)
                    if d > 0.52:
                        col = ASH[0 if y < fcy else 1]  # Blackened soot ring inside stones
                    elif cl > 0.66 and d < 0.32:
                        col = ASH[6 if x <= fcx else 5]  # Crisp white/pale-silver ash cluster!
                    elif cl > 0.45:
                        col = ASH[4 if x <= fcx else 3]
                    else:
                        col = ASH[2]
                    put(body, x, y, col)

        # Crossed charred split firewood billets showing wood-grain checks & charcoal ends
        for k in range(-6, 6):
            # Billet 1 (bottom-left to top-right)
            bx1, by1 = fcx + k, fcy + 1 - k // 3
            put(body, bx1, by1 - 1, WOOD[3 if (k < 0 and k % 2 == 0) else 2] if abs(k) < 4 else ASH[0])
            put(body, bx1, by1, WOOD[1] if abs(k) < 3 else ASH[0])
            # Billet 2 (top-left to bottom-right)
            if abs(k) <= 5:
                bx2, by2 = fcx + k, fcy - 1 + k // 3
                put(body, bx2, by2, WOOD[4 if (k < -1 and k % 2 == 0) else 2] if k < 2 else ASH[1])
                put(body, bx2, by2 + 1, ASH[0])
        # Small white-ash dusting on billet crossing
        put(body, fcx, fcy - 1, ASH[6])
        put(body, fcx - 1, fcy, ASH[5])

        # 10 Varied Faceted River-Stones around the hearth (varied sizes, tilts, slate & warm river-cobble tones!)
        hearth_stones = [
            (fcx - 9.8, fcy - 0.5, 3.0, 2.0, -0.25, False),
            (fcx - 7.5, fcy - 3.6, 3.4, 2.1, 0.18, True),
            (fcx - 2.5, fcy - 4.8, 3.1, 1.8, -0.10, False),
            (fcx + 3.0, fcy - 4.7, 3.5, 1.9, 0.14, True),
            (fcx + 8.0, fcy - 3.2, 2.9, 1.9, -0.22, False),
            (fcx + 10.0, fcy + 0.2, 3.2, 2.1, 0.20, False),
            (fcx + 7.6, fcy + 3.5, 3.6, 2.2, -0.15, True),
            (fcx + 2.2, fcy + 4.7, 3.3, 2.0, 0.08, False),
            (fcx - 3.4, fcy + 4.6, 3.7, 2.2, -0.12, False),
            (fcx - 8.2, fcy + 3.0, 3.1, 2.0, 0.24, True),
        ]
        for idx_h, (rx_c, ry_c, rrx, rry, tl, wrm) in enumerate(hearth_stones):
            draw_faceted_stone(body, rx_c, ry_c, rrx, rry, tl, seed + idx_h * 13, warm=wrm, lit_bias=0.50)
            if idx_h in (1, 2, 8, 9):
                put(body, int(round(rx_c - 1)), int(round(ry_c - 1)), MOSS[4 if idx_h % 2 else 5])
                put(body, int(round(rx_c)), int(round(ry_c - 1)), MOSS[3])

        # 5) Prominent Rusted Knight's Greatsword (`x ~ 33..41, y = 8..49`) with Fuller Groove, Rust Pitting & Corded Grip!
        # Turned-up dark sod mound around embedded blade entry (`(39, 48)`)
        for dx in range(-5, 6):
            put(body, 39 + dx, 48, EARTH[3 if dx < 0 else 1])
            put(body, 39 + dx, 49, EARTH[2 if dx < 0 else 0])
            if dx in (-4, -3, -2, 2, 3):
                put(body, 39 + dx, 47, MOSS[5 if dx < 0 else 3])

        # Broad two-handed steel blade (`y = 22..48`, heroic slight lean from `x = 36` to `x = 39`)
        steps_b = 27
        for i in range(steps_b):
            t = i / float(steps_b - 1)
            bx = 36.0 + 3.0 * t
            by = 22 + i
            ix = int(round(bx))
            # Ricasso collar with leather/steel bolster right below guard (`i in (0, 1, 2)`)
            if i < 3:
                put(body, ix - 2, by, STEEL[6])
                put(body, ix - 1, by, ORDER_GOLD[4] if i == 1 else STEEL[4])
                put(body, ix, by, STEEL[1])
                put(body, ix + 1, by, STEEL[3])
                put(body, ix + 2, by, STEEL[1])
                continue

            # Left sunlit bevel (with battle-nick at `i == 11` and subtle brown-rust pitting near lower turf)
            if i != 11:
                put(body, ix - 2, by, RUST[3] if i in (19, 23) else STEEL[7 if i < 14 else 6])
            put(body, ix - 1, by, RUST[2] if i in (7, 18, 19, 23) else STEEL[5])

            # Deep central fuller groove (`ix`) with glowing crimson Order runes!
            if i in (5, 8, 11, 14, 17, 20):
                glow.emit(body, ix, by, RUNE_D, RUNE_H if i == 8 else (RUNE_M if i % 2 == 0 else RUNE_G), halo=1)
            else:
                put(body, ix, by, STEEL[0])

            # Right shadowed bevel with clustered brown-rust pitting
            put(body, ix + 1, by, RUST[2] if i in (4, 5, 10, 15, 16, 21, 22) else STEEL[3])
            put(body, ix + 2, by, RUST[1] if i in (5, 10, 16, 21, 22) else STEEL[1])

        # Swept Winged Cruciform Crossguard (`y = 20..22, x = 28..44`) with Quillions & Gold Sun-Ecusson
        for dx in range(-8, 9):
            gy = 21 + (1 if dx > 4 else (-1 if dx < -5 else 0))
            if abs(dx) >= 7:
                # Upturned/downturned flared quillon finials
                put(body, 36 + dx, gy - (1 if dx < 0 else 0), ORDER_GOLD[5 if dx < 0 else 3])
                put(body, 36 + dx, gy, ORDER_GOLD[3 if dx < 0 else 1])
            else:
                col_g = RUST[4] if dx in (-3, 4) else STEEL[6 if dx < 0 else 3]
                put(body, 36 + dx, gy, col_g)
                put(body, 36 + dx, gy + 1, STEEL[1 if dx >= 0 else 2])
        # Central raised gold Order sun-boss on crossguard
        for bdx, bdy, gi in [(-1, 0, 6), (0, 0, 7), (1, 0, 4), (0, 1, 5), (0, 2, 3)]:
            put(body, 36 + bdx, 21 + bdy, ORDER_GOLD[gi])

        # Corded Diagonal Leather Grip (`y = 11..20`) + Wire Spacer Ring + Faceted Wheel Pommel (`y = 8..11`)
        for k in range(10):
            gy = 20 - k
            gx = int(round(36.0 - k * 0.22))
            if k == 5:
                # Central gilt-wire waist ring on two-handed grip
                put(body, gx - 1, gy, ORDER_GOLD[5])
                put(body, gx, gy, ORDER_GOLD[3])
                put(body, gx + 1, gy, ORDER_GOLD[1])
            else:
                rib = k % 2 == 0
                put(body, gx - 1, gy, LEATHER[5 if rib else 3])
                put(body, gx, gy, LEATHER[3 if rib else 2])
                put(body, gx + 1, gy, LEATHER[1 if rib else 0])

        # Heavy faceted octagonal wheel pommel with sunken crimson-gold Order center
        px_m, py_m = 34, 9
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if abs(dx) + abs(dy) <= 3:
                    if dx == 0 and dy == 0:
                        put(body, px_m, py_m, CRIMSON_STONE[6])
                    elif abs(dx) <= 1 and abs(dy) <= 1:
                        put(body, px_m + dx, py_m + dy, ORDER_GOLD[6 if (dx <= 0 and dy <= 0) else 3])
                    else:
                        put(body, px_m + dx, py_m + dy, ORDER_GOLD[5 if (dx < 0 or dy < 0) else 2])

        # Folded crimson cloth sword-knot sash fluttering from left quillon (`x = 30..35, y = 22..29`)
        for rx_k, ry_k, ci in [
            (34, 22, 6), (33, 23, 5), (34, 23, 3), (32, 24, 6), (33, 25, 4),
            (31, 25, 5), (32, 26, 3), (31, 27, 4), (30, 28, 2),
        ]:
            put(body, rx_k, ry_k, BANNER_RED[ci])

        framed = outline_material(body)
        # Extend subtle earth shadow slightly right (`cx = 41, rx = 33`) so composited banner pole at x~68 sits naturally too!
        paint_earth_shadow_skirt(framed, 40, FY - 1, rx=33.0, ry=5.8, seed=seed + 51)
        plant_foreground_turf(
            framed,
            tufts=[(12, 49, 2), (22, 50, 1), (31, 50, 2), (41, 50, 1), (63, 49, 2)],
            clovers=[(18, 50), (35, 50), (59, 51)],
        )
        return framed, glow.finish()

    else:
        # ---- Col 1: Folded Canvas Bedroll, Faceted Cairn, Rusted Order Halberd, Cast-Iron Kettle & Wax-Sealed Scroll!
        draw_loam_and_pebbles(body, 46, 49, 35, 3, seed + 2)

        # 1) Collapsed Folded Canvas Shelter / Bedroll (`x = 12..42, y = 34..49`) with Creases, Stitches & Dirt Smudges!
        for y in range(35, 49):
            u_y = (y - 35) / 13.0
            x0_t = int(round(15.0 - 2.5 * u_y))
            x1_t = int(round(39.0 + 3.0 * u_y))
            for x in range(x0_t, x1_t + 1):
                # Sculptural diagonal cloth folds & sagging ridge troughs
                pleat = math.sin((x - x0_t) * 0.42 + (y - 35) * 0.35)
                crease2 = 0.45 * math.cos((x - 22) * 0.7 - (y - 35) * 0.25)
                lit = 0.58 - 0.28 * u_y - 0.16 * ((x - 27) / 15.0) + 0.22 * pleat + 0.10 * crease2
                c_idx = int(clamp(round(lit * 5.8), 0, len(CANVAS) - 1))
                col = CANVAS[c_idx]

                # Weathered crimson Order border stripe (`x0_t+3 .. x0_t+5`)
                if x0_t + 3 <= x <= x0_t + 5 and u_y < 0.86:
                    col = CRIMSON_STONE[5 if lit > 0.52 else (3 if lit > 0.34 else 1)]
                # Curved stitched canvas seam + square repair patch (`x_seam` and patch at `x = 29..34, y = 39..43`)
                elif x == int(round(x0_t + 11 + u_y * 2.2)) and y < 47:
                    col = CANVAS[2] if y % 2 == 0 else CANVAS[5]
                elif 29 <= x <= 34 and 39 <= y <= 43 and (x in (29, 34) or y in (39, 43)):
                    col = CANVAS[2] if (x + y) % 2 == 0 else CANVAS[4]

                # Damp mud/dirt smudges along the lower ground-contact hem (`y >= 45`)!
                if y >= 45 and vnoise(x * 0.42, y * 0.5, seed + 19) > 0.44:
                    col = EARTH[2 if y >= 47 else 3]
                put(body, x, y, col)

        # Rolled wool blanket end peeking from left opening (`x = 12..17, y = 42..48`)
        for dy in range(-3, 4):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 6:
                    spiral = (dx + dy) % 2 == 0
                    put(body, 14 + dx, 45 + dy, BANNER_RED[4 if spiral and dx <= 0 else 2])

        # Splintered ash-wood ridge pole diagonal across tarp (`(13, 47) -> (43, 34)`) with wood grain
        for i in range(31):
            t = i / 30.0
            px_w = int(round(13.0 + 30.0 * t))
            py_w = int(round(47.0 - 13.0 * t))
            put(body, px_w, py_w - 1, WOOD[5 if i % 4 != 0 else 3])
            put(body, px_w, py_w, WOOD[3 if i % 5 != 0 else 1])
            put(body, px_w, py_w + 1, WOOD[0])
        draw_moss_cushion(body, 18, 32, 45, 2, 2, seed + 5)

        # 2) Faceted Mossy Patrol Stone Cairn (`x = 61..80, y = 30..49`)
        cairn_stones = [
            (65, 47, 5.6, 2.9, -0.12, False, False),
            (74, 47, 5.4, 2.8, 0.15, True, True),
            (69.5, 42, 6.0, 3.0, 0.06, False, False),
            (69, 37, 4.8, 2.6, -0.09, True, False),
            (69.5, 32.5, 3.6, 2.2, 0.05, False, False),
        ]
        for ci, (cx_s, cy_s, rx_s, ry_s, tl, wrm, cr) in enumerate(cairn_stones):
            draw_faceted_stone(body, cx_s, cy_s, rx_s, ry_s, tl, seed + ci * 13, warm=wrm, crimson=cr)
        draw_moss_cushion(body, 65, 74, 31, 2, 3, seed + 17)
        draw_moss_cushion(body, 61, 69, 44, 2, 2, seed + 23)
        draw_lichen_rosettes(body, [(62, 34, 78, 48)], 4, seed + 29)

        # 3) Planted Rusted Order Halberd (`x ~ 42..55, y = 6..49`) with Wood Grain, Riveted Langets & Rust Pitting
        for y in range(14, 50):
            sx = int(round(49.0 + (y - 14) * 0.06))
            if y < 25:
                # Steel socket & riveted side langets reinforcing upper shaft
                put(body, sx - 1, y, ORDER_GOLD[4] if y in (17, 22) else STEEL[5])
                put(body, sx, y, STEEL[2])
                put(body, sx + 1, y, STEEL[0])
            elif 30 <= y <= 37:
                # Corded leather grip wrap mid-shaft
                rib = y % 2 == 0
                put(body, sx - 1, y, LEATHER[4 if rib else 2])
                put(body, sx, y, LEATHER[2 if rib else 1])
                put(body, sx + 1, y, LEATHER[0])
            else:
                put(body, sx - 1, y, WOOD[5 if (y % 6) < 4 else 3])
                put(body, sx, y, WOOD[3 if (y % 5) != 0 else 2])
                put(body, sx + 1, y, WOOD[1])
        # Diamond-section steel spearhead (`y = 6..14`)
        for y in range(6, 15):
            hw_tip = max(0, (y - 6) // 2)
            for dx in range(-hw_tip, hw_tip + 1):
                col = STEEL[7 if dx < 0 else (4 if dx == 0 else 1)]
                if y == 11 and dx == 1:
                    col = RUST[3]
                put(body, 49 + dx, y, col)
        # Crescent halberd axe-blade (`x = 41..48, y = 13..25`) with bright honed cutting bevel, nick & rust clusters
        for y in range(13, 26):
            dy_h = (y - 19.0) / 5.8
            x_edge = int(round(41.2 + 2.5 * (dy_h * dy_h)))
            if y == 18:
                x_edge += 1  # Battle nick in crescent blade!
            for x in range(x_edge, 49):
                if x == x_edge:
                    col = STEEL[7]
                elif x == x_edge + 1:
                    col = STEEL[5]
                elif (x in (44, 45) and y in (16, 17, 22)) or (x == 46 and y in (15, 21, 22)):
                    col = RUST[4 if x < 46 else 2]
                else:
                    col = STEEL[4 if x < 46 else 2]
                put(body, x, y, col)
        # Rear armour-piercing fluke beak (`x = 50..55, y = 17..21`)
        for dx in range(1, 6):
            by_f = 17 + dx // 2
            put(body, 49 + dx, by_f, STEEL[5 if dx < 3 else 3])
            put(body, 49 + dx, by_f + 1, RUST[2] if dx == 2 else STEEL[1])
        # Glowing crimson Order rune on halberd socket collar + tattered wine-red tassel pennant
        glow.emit(body, 47, 19, RUNE_D, RUNE_H, halo=1)
        glow.emit(body, 47, 20, RUNE_D, RUNE_M, halo=1)
        for px_t, py_t, ci in [(50, 22, 6), (51, 23, 5), (52, 24, 5), (51, 25, 3), (52, 26, 4), (53, 27, 2), (51, 27, 1)]:
            put(body, px_t, py_t, BANNER_RED[ci])

        # 4) Dented Cast-Iron Kettle (`x = 39..47, y = 42..50`) & Tied Parchment Scroll with Glowing Wax Seal (`x = 53..63, y = 47..51`)
        for y in range(44, 50):
            for x in range(39, 47):
                dx, dy = (x - 42.5) / 3.8, (y - 47.0) / 3.1
                if dx * dx + dy * dy <= 1.0:
                    if y == 44:
                        col = IRON[5 if dx < 0 else 3]  # Rolled kettle lip
                    elif y >= 48:
                        col = ASH[0]  # Fire-blackened soot bottom
                    elif x in (43, 44) and y == 46:
                        col = RUST[3]  # Rust dent
                    else:
                        col = IRON[4 if dx < -0.25 else (3 if dx < 0.25 else 1)]
                    put(body, x, y, col)
        for bx_k, by_k in [(40, 43), (41, 42), (42, 42), (43, 42), (44, 43)]:
            put(body, bx_k, by_k, IRON[4 if bx_k <= 42 else 2])

        # Rolled parchment scroll tube with dark leather cord & glowing crimson Order wax seal
        for i_p in range(9):
            px_s = 53 + i_p
            py_s = 49 + (1 if i_p >= 5 else 0)
            is_cord = i_p == 4
            put(body, px_s, py_s - 1, LEATHER[2] if is_cord else PARCHMENT[4 if i_p < 5 else 3])
            put(body, px_s, py_s, LEATHER[0] if is_cord else PARCHMENT[2 if i_p < 5 else 1])
        put(body, 53, 48, WOOD[1])  # Hollow rolled scroll end
        glow.emit(body, 57, 49, CRIMSON_STONE[6], RUNE_M, halo=2)
        glow.emit(body, 58, 49, ORDER_GOLD[6], RUNE_H, halo=1)

        framed = outline_material(body)
        paint_earth_shadow_skirt(framed, 46, FY - 1, rx=38.0, ry=5.8, seed=seed + 61)
        plant_foreground_turf(
            framed,
            tufts=[(12, 49, 2), (24, 50, 1), (36, 50, 2), (49, 50, 1), (62, 50, 2), (77, 49, 2)],
            clovers=[(20, 50), (45, 51), (71, 50)],
        )
        return framed, glow.finish()


# ==============================================================================
# 3. Swaying Red Order Banner (`order_banner.png`, 32x64, ground/pole-foot anchor (16, 58))
#    CRITICAL: Keep x = 0..4 and x = 27..31 STRICTLY TRANSPARENT for sway_rows.gdshader!
# ==============================================================================
def build_order_banner():
    W, H = 32, 64
    body = blank(W, H)

    # 1) Forged Steel Leaf-Spearhead Finial at y = 2..6 (`x = 9..11`, outline stays >= 8!)
    for y, row_cols in [
        (2, [(10, STEEL[7])]),
        (3, [(9, STEEL[7]), (10, STEEL[5]), (11, STEEL[2])]),
        (4, [(9, STEEL[6]), (10, STEEL[1]), (11, STEEL[3])]),  # Fuller groove at (10, 4)
        (5, [(9, STEEL[5]), (10, STEEL[3]), (11, STEEL[1])]),
        (6, [(9, ORDER_GOLD[5]), (10, ORDER_GOLD[3]), (11, ORDER_GOLD[1])]),  # Gilt socket collar
    ]:
        for x, col in row_cols:
            put(body, x, y, col)

    # 2) Forged Iron Crossbar (`y = 7..8, x = 7..25` -> with 1px outline `x = 6..26`, leaving `0..5` & `27..31` 100% clear!)
    for x in range(7, 26):
        is_lashing = x in (13, 17, 21, 24)
        put(body, x, 7, LEATHER[4] if is_lashing else IRON[5 if x < 16 else 3])
        put(body, x, 8, LEATHER[2] if is_lashing else IRON[1])
    # Gilded acorn crossbar finials at x = 7 and x = 25
    put(body, 7, 7, ORDER_GOLD[6])
    put(body, 7, 8, ORDER_GOLD[3])
    put(body, 25, 7, ORDER_GOLD[5])
    put(body, 25, 8, ORDER_GOLD[2])

    # 3) Ash-Wood Lance Shaft (`x = 9..11, y = 7..58`) with Wood Grain, Corded Grip, Brass Rings & Iron Ground-Shoe
    for y in range(7, 58):
        if y >= 52:
            # Tapered iron ground-spike shoe
            put(body, 9, y, RUST[3] if y == 54 else STEEL[5])
            put(body, 10, y, STEEL[2])
            if y < 56:
                put(body, 11, y, STEEL[0])
        elif y in (12, 20, 28, 36):
            # Brass/leather luff rings tying banner cloth to pole
            put(body, 9, y, ORDER_GOLD[5])
            put(body, 10, y, ORDER_GOLD[3])
            put(body, 11, y, ORDER_GOLD[1])
        elif 41 <= y <= 46:
            # Leather carrying grip wrap
            rib = y % 2 == 0
            put(body, 9, y, LEATHER[4 if rib else 2])
            put(body, 10, y, LEATHER[2 if rib else 1])
            put(body, 11, y, LEATHER[0])
        else:
            # Subtle vertical wood grain streaks
            grain = (y % 7) in (0, 1)
            put(body, 9, y, WOOD[5 if not grain else 4])
            put(body, 10, y, WOOD[3 if not grain else 2])
            put(body, 11, y, WOOD[1])

    # Tight mossy earth/grass tuft around pole foot (`x = 8..13, y = 56..58`, outline stays >= 7!)
    for dx, dy, col in [
        (-2, 1, EARTH[2]), (-1, 1, EARTH[3]), (0, 1, EARTH[1]), (1, 1, EARTH[2]),
        (-2, 0, MOSS[3]), (-1, -1, MOSS[5]), (0, 0, MOSS[2]), (1, -1, MOSS[4]), (2, 0, MOSS[3]),
    ]:
        put(body, 10 + dx, 57 + dy, col)

    # 4) Deeply Pleated, Stitched & Weather-Smudged Wine-Red Banner Cloth (`x = 12..25, y = 9..49`)
    for y in range(9, 50):
        u_y = (y - 9) / 40.0
        for x in range(12, 26):
            # Battle-slashed fly notches on right edge (`x = 24..25`)
            if x == 25 and (15 <= y <= 19 or 28 <= y <= 33 or y >= 40):
                continue
            if x == 24 and (17 <= y <= 18 or 30 <= y <= 31 or y >= 43):
                continue
            # Ragged 3-tail swallowtail cuts at bottom (`y >= 38`)
            if y >= 38:
                td = y - 37
                if x in (15, 16) and td >= 3:
                    continue
                if x in (20, 21) and td >= 2:
                    continue
                if x in (12, 13, 14) and y >= 48 - (14 - x):
                    continue
                if x in (17, 18, 19) and y >= 49 - abs(x - 18):
                    continue
                if x >= 22 and y >= 46 - (x - 22):
                    continue

            # Sculptural vertical/diagonal cloth folds + weave cluster
            pleat = math.sin((x - 12) * 0.68 + y * 0.09) + 0.35 * math.cos((x - 15) * 1.1 - y * 0.05)
            lit = 0.54 - 0.22 * u_y - 0.14 * ((x - 12) / 13.0) + 0.22 * pleat
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.28
            col = BANNER_RED[int(clamp(round(lit * 6.4 + dith), 0, len(BANNER_RED) - 1))]

            # Gold brocade top header (`y == 10`) & broken weathered gold border trim (`x == 13` / `x == 23`)
            if y == 10 and x % 2 == 0:
                col = ORDER_GOLD[5 if x < 19 else 3]
            elif (x == 13 and 11 <= y <= 37 and y % 4 != 0) or (x == 23 and 11 <= y <= 35 and y % 4 != 1):
                col = ORDER_GOLD[4 if pleat > 0 else 2]
            # Subtle vertical stitched center-panel seam at `x == 18` outside emblem (`y >= 32`)
            elif x == 18 and 32 <= y <= 44:
                col = BANNER_RED[4 if y % 2 == 0 else 1]

            # Soot & damp mud smudges darkening tattered bottom tails (`y >= 40`)!
            if y >= 40 and (y >= 44 or (x + y) % 3 == 0):
                col = EARTH[1] if y >= 46 else BANNER_RED[0]

            put(body, x, y, col)

    # 5) Embroidered Gold Red Order Sun-Greatsword Emblem (`cx = 18, cy = 22`) with Dark Wine Relief Shadow
    ecx, ecy = 18, 22
    # Subtle dark crimson stitch shadow 1px bottom-right so gold embroidery pops crisply!
    for dy in range(-7, 9):
        if get_px(body, ecx + 1, ecy + dy + 1)[3] == 255:
            put(body, ecx + 1, ecy + dy + 1, BANNER_RED[0])
    # Radiant sun-ring + 4 diagonal flame rays
    for dy in range(-5, 6):
        for dx in range(-4, 5):
            r = math.hypot(dx, dy * 0.92)
            if 2.7 <= r <= 3.75 and not (dx == 3 and dy == 2):
                put(body, ecx + dx, ecy + dy, ORDER_GOLD[5 if (dx <= 0 and dy <= 0) else 3])
    for dx, dy in [(-4, -4), (4, -4), (-4, 4), (4, 4)]:
        put(body, ecx + dx, ecy + dy, ORDER_GOLD[3 if dx > 0 else 4])
    # Raised vertical Order greatsword + winged crossguard + sunburst core
    for dy in range(-7, 9):
        if dy != 5:  # Tiny weathered gap in gold thread
            put(body, ecx, ecy + dy, ORDER_GOLD[6 if dy <= 0 else 4])
    for dx in (-3, -2, -1, 1, 2, 3):
        put(body, ecx + dx, ecy - 3, ORDER_GOLD[5 if dx < 0 else 3])
    put(body, ecx, ecy - 7, ORDER_GOLD[7])  # Pommel glint
    put(body, ecx, ecy, ORDER_GOLD[7])      # Sun-heart glint

    framed = outline_material(body)

    # Subtle ground shadow strictly within `x = 6..15, y = 57..61`
    for y in range(57, 62):
        for x in range(6, 16):
            if framed[y][x][3] == 0:
                d = ((x - 10.0) / 4.8) ** 2 + ((y - 58.5) / 2.2) ** 2
                if d < 1.0:
                    framed[y][x] = (*SHADOW_RGB, 108 if d < 0.5 else 52)

    # Hard shader safety guarantee: x = 0..4 and x = 27..31 strictly CLEAR on every single row!
    for y in range(H):
        for x in (0, 1, 2, 3, 4, 27, 28, 29, 30, 31):
            framed[y][x] = CLEAR

    return framed


# ==============================================================================
# 4. Order Boundary Stones (`order_boundary_stone.png` & `_glow.png`, 3x1 of 48x56, feet (24, 48))
# ==============================================================================
def incise_glyph_px(body, glow: GlowMap, x: int, y: int, emit_col=None, dim_col=None, halo: int = 1):
    """Carves a deep chiseled stone groove with dark top-left shadow & subtle sunlit bottom-right catch-rim!"""
    if get_px(body, x, y - 1)[3] == 255 and get_px(body, x, y - 1) in STONE + WARM_STONE:
        body[y - 1][x] = darken_stone_px(body[y - 1][x], 1)
    if get_px(body, x, y + 1)[3] == 255 and get_px(body, x, y + 1) in STONE + WARM_STONE:
        body[y + 1][x] = brighten_stone_px(body[y + 1][x], 1)
    if get_px(body, x + 1, y)[3] == 255 and get_px(body, x + 1, y) in STONE + WARM_STONE:
        body[y][x + 1] = brighten_stone_px(body[y][x + 1], 1)
    if emit_col is not None:
        glow.emit(body, x, y, dim_col or CRIMSON_STONE[5], emit_col, halo=halo)
    else:
        put(body, x, y, MORTAR_DEEP)


def build_boundary_stone(variant: int):
    W, H = 48, 56
    FX, FY = 24, 48
    seed = 1723 + variant * 37
    body = blank(W, H)
    glow = GlowMap(W, H)

    # Shared sunken earth & pebble foundation bed (`y = 45..49`)
    draw_loam_and_pebbles(body, FX, FY, 14, 2, seed + 101)

    if variant == 0:
        # ---- Col 0: Chiseled Angular Beveled Obelisk Stele with Corner Chips, Incised Crest & Rune Rows!
        # Two-tier stepped ashlar pedestal (`y = 39..48`) with vertical mortar joint & flaky crimson dado
        for y in range(43, 49):
            for x in range(12, 37):
                if y == 48 and vnoise(x * 0.3, 1.0, seed) < 0.35:
                    continue
                if x == 26 or y == 43 and x >= 34:
                    put(body, x, y, MORTAR_DEEP)
                else:
                    wrm = x > 26
                    lit = 0.68 if x < 16 else (0.24 if x > 32 else 0.52)
                    put(body, x, y, shade_stone_cluster(x, y, lit, seed + 1, warm=wrm, catch_top=(1.0 if y == 43 else 0.0)))
        for y in range(39, 43):
            for x in range(14, 35):
                cr = 1.0 if fbm(x * 0.28, y * 0.3, seed + 2) > 0.38 else 0.0
                lit = 0.72 if x < 18 else (0.25 if x > 30 else 0.56)
                put(body, x, y, shade_stone_cluster(x, y, lit, seed + 2, crimson_amt=cr, catch_top=(1.0 if y == 39 else 0.0)))
        put(body, 14, 42, MORTAR_MID)
        for x in range(14, 35):
            if x % 3 != 0:
                put(body, x, 42, MORTAR_DEEP)

        # Angular polygonal beveled obelisk shaft (`y = 7..38`) with sharp pyramid apex & chipped right shoulder!
        for y in range(7, 39):
            if y < 14:
                hw = 1.2 + (y - 7) * 1.18
            else:
                hw = 9.2 + (y - 14) * 0.06
            x0, x1 = int(round(FX - hw)), int(round(FX + hw))
            # Chiseled missing corner chip on upper-right shoulder (`y = 13..16, x >= 31`) & mid-left nick (`y = 26..27`)
            if 13 <= y <= 16:
                x1 -= (3 if y in (14, 15) else 2)
            if y in (26, 27):
                x0 += 1
            for x in range(x0, x1 + 1):
                rel = (x - FX) / max(1.0, hw)
                # Crisp planar stone facets: bright sunlit left chamfer, flat front inscription plane, deep dark right chamfer!
                if y < 14:
                    lit = 0.86 if rel < -0.15 else (0.58 if rel < 0.35 else 0.24)
                elif rel < -0.56:
                    lit = 0.84
                elif rel > 0.56:
                    lit = 0.20
                else:
                    lit = 0.54 - 0.10 * rel
                # Crisp facet ridge highlight along left chamfer crease (`abs(rel + 0.56) < 0.08`)
                ct = 1.0 if (y == 14 and abs(rel) < 0.55) or (y in (16, 17) and x >= x1 - 1) else 0.0
                cl = 1.0 if abs(rel + 0.56) < 0.09 or x == x0 else 0.0
                warm_vein = vnoise(x * 0.16 + y * 0.11, y * 0.14, seed + 9) > 0.62
                put(body, x, y, shade_stone_cluster(x, y, lit, seed + 5, warm=warm_vein, catch_top=ct, catch_left=cl))

        # Deeply incised Red Order Sun-Sword Crest (`cy = 20`) with shadow/highlight bevel rims!
        for dy in range(-5, 6):
            incise_glyph_px(body, glow, FX, 20 + dy, emit_col=(RUNE_H if dy in (-2, 0) else (RUNE_G if abs(dy) <= 3 else None)), dim_col=ORDER_GOLD[5] if abs(dy) <= 1 else CRIMSON_STONE[5])
        for dx in (-3, -2, -1, 1, 2, 3):
            incise_glyph_px(body, glow, FX + dx, 18, emit_col=(RUNE_G if abs(dx) == 2 else None), dim_col=ORDER_GOLD[4])
        for dx, dy in [(-2, -1), (2, -1), (-2, 1), (2, 1)]:
            put(body, FX + dx, 20 + dy, ORDER_GOLD[4 if dx < 0 else 2])

        # 2 Crisp Chiseled Angular Rune Bands (`y = 28..29` and `y = 33..34`)
        for rx_g, ry_g, em in [
            (-4, 28, RUNE_G), (-4, 29, None), (-2, 28, None), (-1, 29, RUNE_M), (1, 28, RUNE_G), (1, 29, None), (3, 28, None), (4, 29, RUNE_G),
            (-3, 33, None), (-3, 34, RUNE_M), (0, 33, RUNE_G), (0, 34, None), (3, 33, RUNE_M), (4, 33, None),
        ]:
            incise_glyph_px(body, glow, FX + rx_g, ry_g, emit_col=em, dim_col=CRIMSON_STONE[4])

        apply_weathering_streak(body, 21, 14, 14, 2, seed + 31)
        draw_lichen_rosettes(body, [(16, 15, 31, 38)], 4, seed + 41)
        draw_moss_cushion(body, 16, 26, 8, 2, 4, seed + 11)
        draw_moss_cushion(body, 12, 21, 42, 2, 2, seed + 13)

    elif variant == 1:
        # ---- Col 1: Faceted Gable-Shouldered Tilted Waystone Tablet with Tied Crimson Cloth Sash!
        for y in range(9, 49):
            u = (y - 9) / 39.0
            cx = FX - 2.0 * (1.0 - u)  # Slight ancient lean to the left
            # Angular chiseled gable-crowned head (`y = 9..15`), waist notches (`y = 20..23`), battered plinth (`y >= 43`)
            if y < 15:
                hw = 3.2 + (y - 9) * 1.15
            elif 19 <= y <= 23:
                hw = 8.4  # Chiseled neck notches holding the crimson sash
            elif y >= 43:
                hw = 11.8
            else:
                hw = 9.6 + u * 1.3
            x0, x1 = int(round(cx - hw)), int(round(cx + hw))
            # Chipped upper-left corner (`y = 13..16`) & chipped right edge (`y = 35..37`)
            if 13 <= y <= 15:
                x0 += 2
            if 35 <= y <= 37:
                x1 -= 1
            if y == 48 and vnoise(cx, y, seed) < 0.3:
                continue
            for x in range(x0, x1 + 1):
                if y == 43 and x % 4 != 0:
                    put(body, x, y, MORTAR_DEEP)
                    continue
                rel = (x - cx) / max(1.0, hw)
                # Crisp planar facets instead of smooth capsule shading!
                if rel < -0.58:
                    lit = 0.82
                elif rel > 0.58:
                    lit = 0.19
                elif y < 13:
                    lit = 0.72 - 0.18 * rel
                else:
                    lit = 0.53 - 0.12 * rel
                # Shadow cast onto stone directly beneath the tied crimson sash (`y = 23..24`)
                if y in (23, 24):
                    lit -= 0.18
                ct = 1.0 if (y <= 11 or y == 44) else 0.0
                cl = 1.0 if (abs(rel + 0.58) < 0.09 or x == x0) else 0.0
                put(body, x, y, shade_stone_cluster(x, y, lit, seed + 7, warm=(y >= 43 or (x > 24 and y < 20)), catch_top=ct, catch_left=cl))

        # Deep diagonal fracture crack splitting the tablet (`y = 27..31`) with bright sunlit lower lip!
        for dx in range(-8, 9):
            cy_c = 28 + dx // 3
            cx_c = int(round(FX - 1 + dx))
            if get_px(body, cx_c, cy_c)[3] == 255:
                put(body, cx_c, cy_c, MORTAR_DEEP)
                if get_px(body, cx_c, cy_c + 1)[3] == 255:
                    put(body, cx_c, cy_c + 1, STONE[8 if dx < 2 else 7])

        # Folded Crimson Order Cloth Sash (`y = 19..23`) with Crease Ridges, Gold Hem Dots, Knot & Fluttering Tails!
        for x in range(14, 32):
            if get_px(body, x, 21)[3] == 255:
                fold = 1 if (x % 4) < 2 else 0
                put(body, x, 19, ORDER_GOLD[4] if x % 3 == 0 else BANNER_RED[6 if x < 23 else 4])
                put(body, x, 20, BANNER_RED[(6 if x < 23 else 4) - fold])
                put(body, x, 21, BANNER_RED[4 if x < 23 else 3])
                put(body, x, 22, BANNER_RED[1 if x > 22 else 2])
        # Sculptural tied cloth knot (`x = 29..32, y = 20..23`) + two layered ragged fluttering tails (`x = 30..37, y = 22..31`)
        for rx_t, ry_t, ci in [
            (29, 20, 6), (30, 20, 7), (31, 21, 5), (29, 21, 4), (30, 21, 6), (30, 22, 2),
            # Upper tail
            (32, 22, 6), (33, 23, 5), (34, 23, 6), (34, 24, 4), (35, 24, 5), (36, 25, 4), (37, 26, 2),
            # Lower tail
            (31, 23, 4), (31, 24, 5), (32, 25, 4), (32, 26, 3), (33, 27, 4), (33, 28, 2), (32, 29, 1),
        ]:
            put(body, rx_t, ry_t, BANNER_RED[ci])

        # Deeply incised star-sword crest above sash (`cy = 15`) + glowing rune glyphs below crack (`y = 34`)
        for dx, dy, em in [(0, -3, None), (0, -2, RUNE_H), (0, -1, RUNE_G), (0, 0, RUNE_M), (-2, -1, RUNE_G), (2, -1, RUNE_G), (-1, 1, None), (1, 1, None)]:
            incise_glyph_px(body, glow, FX - 2 + dx, 16 + dy, emit_col=em, dim_col=ORDER_GOLD[5] if em == RUNE_H else CRIMSON_STONE[5])
        for sx in (17, 19, 22, 24, 27):
            incise_glyph_px(body, glow, sx, 34, emit_col=RUNE_M, dim_col=CRIMSON_STONE[4])

        draw_ivy_vine(body, 29, 46, 21, -0.7, seed + 19)
        draw_lichen_rosettes(body, [(14, 24, 27, 42)], 4, seed + 29)
        draw_moss_cushion(body, 15, 22, 10, 2, 3, seed + 37)

    else:
        # ---- Col 2: Chiseled Twin-Horned Pass Monolith with Sunken Bronze-Rimmed Medallion & Flaky Crimson Band!
        # Heavy dressed plinth (`y = 43..48, x = 10..38`) with block joint
        for y in range(43, 49):
            for x in range(10, 39):
                if y == 48 and vnoise(x * 0.3, 3.0, seed) < 0.35:
                    continue
                if x in (20, 31) or (y == 43 and x <= 11):
                    put(body, x, y, MORTAR_DEEP)
                else:
                    lit = 0.72 if x < 15 else (0.22 if x > 33 else 0.52)
                    put(body, x, y, shade_stone_cluster(x, y, lit, seed + 17, warm=(20 < x < 31), catch_top=(1.0 if y == 43 else 0.0)))

        # Angular twin-horned monolith shaft (`y = 8..42`) with sharp inner/outer horn bevels & stepped side notches!
        for y in range(8, 43):
            u = (y - 8) / 34.0
            hw = 10.4 + u * 1.7
            if 18 <= y <= 21:
                hw -= 1.6  # Chiseled side shoulder notches
            x0, x1 = int(round(FX - hw)), int(round(FX + hw))
            for x in range(x0, x1 + 1):
                # Sharp V-saddle notch between left horn (`x ~ 17`, apex `y = 8`) and chipped right horn (`x ~ 31`, apex `y = 10`)
                dx_c = x - FX
                if abs(dx_c) <= 5:
                    horn_top = 13 - abs(dx_c)  # Sharp chiseled V-notch from y=13 at center up to y=8 at +-5!
                elif dx_c < -5:
                    horn_top = 8 + (-dx_c - 5) // 2
                else:
                    horn_top = 10 + (dx_c - 5) // 2  # Right horn weathered/chipped 2px lower!
                if y < horn_top:
                    continue
                if y == 42 and x % 3 != 0:
                    put(body, x, y, MORTAR_DEEP)
                    continue

                rel = (x - FX) / max(1.0, hw)
                if rel < -0.58:
                    lit = 0.84
                elif rel > 0.58:
                    lit = 0.20
                elif abs(dx_c) <= 4 and y < 15:
                    # Inner V-notch facets: left inner slope is in shadow (`dx_c < 0`), right inner slope catches top-left sun (`dx_c > 0`)!
                    lit = 0.30 if dx_c < 0 else 0.78
                else:
                    lit = 0.55 - 0.12 * rel

                # Flaky crimson plaster band (`y = 36..40`) showing underlying stone joints!
                cr_amt = 0.0
                p_rim = False
                if 36 <= y <= 40:
                    pm = fbm(x * 0.25, y * 0.3, seed + 61)
                    if pm > 0.38 and x != 27:
                        cr_amt = 1.0
                        p_rim = (y == 36) or (fbm(x * 0.25, (y - 1) * 0.3, seed + 61) <= 0.38)

                ct = 1.0 if (y == horn_top or y == 22 or p_rim) else 0.0
                cl = 1.0 if (abs(rel + 0.58) < 0.09 or x == x0) else 0.0
                put(body, x, y, shade_stone_cluster(x, y, lit, seed + 19, crimson_amt=cr_amt, catch_top=ct, catch_left=cl))

        # Deeply Sunken Bronze-Rimmed Order Medallion (`cx = 24, cy = 26`) with Inner Cavity Shadow & Sunlit Lip!
        mcx, mcy = FX, 26
        for dy in range(-6, 7):
            for dx in range(-6, 7):
                r = math.hypot(dx, dy)
                if r <= 3.9:
                    # Sunken cavity: deep shadow at top-left, lit crimson stone at bottom-right
                    put(body, mcx + dx, mcy + dy, MORTAR_DEEP if (dx + dy < -1) else CRIMSON_STONE[2 if dx + dy > 1 else 1])
                elif r <= 5.2:
                    # Tarnished bronze/gold octagonal bezel rim
                    put(body, mcx + dx, mcy + dy, ORDER_GOLD[6 if (dx < 0 and dy < 0) else (4 if dx <= 0 or dy <= 0 else 2)])
                elif r <= 6.2:
                    # Chiseled outer stone recess bevel (dark top-left shadow, bright bottom-right catch-rim!)
                    put(body, mcx + dx, mcy + dy, STONE[1 if (dx + dy < 0) else 7])

        # Glowing crimson-gold Order cross-sun relief inside sunken medallion!
        glow.emit(body, mcx, mcy, ORDER_GOLD[7], RUNE_H, halo=2)
        for dx, dy in [(-2, 0), (-1, 0), (1, 0), (2, 0), (0, -2), (0, -1), (0, 1), (0, 2)]:
            glow.emit(body, mcx + dx, mcy + dy, ORDER_GOLD[5], RUNE_G if abs(dx + dy) == 1 else RUNE_M, halo=1)

        # Chiseled mileage/warding notches along left chamfer (`x = 13..15, y = 25, 28, 31`)
        for ny in (25, 28, 31):
            put(body, 14, ny, MORTAR_DEEP)
            put(body, 15, ny, MORTAR_DEEP)
            put(body, 14, ny + 1, STONE[8])

        apply_weathering_streak(body, 24, 14, 6, 2, seed + 71)
        draw_lichen_rosettes(body, [(15, 14, 33, 35)], 5, seed + 81)
        draw_moss_cushion(body, 15, 20, 9, 2, 3, seed + 23)
        draw_moss_cushion(body, 22, 26, 13, 2, 2, seed + 24)
        draw_moss_cushion(body, 29, 34, 41, 2, 2, seed + 25)

    framed = outline_material(body)
    paint_earth_shadow_skirt(framed, FX, FY + 1, rx=18.5, ry=4.6, seed=seed + 201)
    tuft_sets = [
        [(10, 48, 2), (16, 49, 1), (30, 49, 2), (37, 48, 1)],
        [(11, 48, 1), (19, 49, 2), (31, 49, 2), (38, 48, 2)],
        [(9, 48, 2), (17, 49, 2), (28, 49, 1), (36, 49, 2)],
    ]
    clover_sets = [
        [(13, 49), (34, 49)],
        [(15, 49), (35, 50)],
        [(14, 50), (32, 49)],
    ]
    plant_foreground_turf(framed, tufts=tuft_sets[variant], clovers=clover_sets[variant])
    return framed, glow.finish()


# ==============================================================================
# Verification & Visual QA Contact Sheet (`docs/img/red_order_sheet.png`)
# ==============================================================================
def verify_no_black(name: str, px):
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} has forbidden pure #000000 pixel at ({x}, {y})")


def verify_banner_padding(px):
    for y, row in enumerate(px):
        for x in (0, 1, 2, 3, 4, 27, 28, 29, 30, 31):
            if row[x][3] != 0:
                raise AssertionError(f"order_banner.png violated sway padding at ({x}, {y}): {row[x]}")


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
                    (sc[0] * sa + dc[0] * inv) // 255,
                    (sc[1] * sa + dc[1] * inv) // 255,
                    (sc[2] * sa + dc[2] * inv) // 255,
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
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.46)), max(14, int(c[2] * 0.66)), c[3])
    return out


def scale_nn(src, factor: int):
    h, w = len(src), len(src[0])
    out = blank(w * factor, h * factor)
    for y in range(h):
        for x in range(w):
            c = src[y][x]
            for dy in range(factor):
                for dx in range(factor):
                    out[y * factor + dy][x * factor + dx] = c
    return out


def render_qa_sheet(towers, camps, banner, steles):
    cw, ch = 500, 340
    canvas = blank(cw, ch)
    half = 170
    for y in range(ch):
        night = y >= half
        for x in range(cw):
            n = noise(x // 4, y // 3, 131)
            if not night:
                canvas[y][x] = (62, 125, 86, 255) if n < 110 else ((85, 152, 95, 255) if n < 205 else (112, 174, 102, 255))
            else:
                canvas[y][x] = (20, 28, 48, 255) if n < 115 else ((25, 36, 58, 255) if n < 205 else (31, 44, 68, 255))

    for p_i in range(2):
        night = p_i == 1
        yo = 0 if not night else half

        # 2 Watchtowers on left (`x = 8` and `x = 140`)
        for i in range(2):
            t_px, t_gl = towers[i]
            ox, oy = 8 + i * 132, yo + 12
            alpha_over(canvas, tint_night_px(t_px) if night else t_px, ox, oy)
            if night:
                add_glow_over(canvas, t_gl, ox, oy)

        # 2 Patrol Camps on upper right (`x = 278` and `x = 384`), with `order_banner.png` composited in Col 0's right slot (`x ~ 74`)
        for i in range(2):
            c_px, c_gl = camps[i]
            ox, oy = 278 + i * 106, yo + 26
            alpha_over(canvas, tint_night_px(c_px) if night else c_px, ox, oy)
            if night:
                add_glow_over(canvas, c_gl, ox, oy)
            if i == 0:
                alpha_over(canvas, tint_night_px(banner) if night else banner, ox + 58, oy - 8)

        # Standalone `order_banner.png` + 3 `order_boundary_stone.png` steles on lower right
        alpha_over(canvas, tint_night_px(banner) if night else banner, 282, yo + 98)
        for i in range(3):
            s_px, s_gl = steles[i]
            ox, oy = 326 + i * 54, yo + 104
            alpha_over(canvas, tint_night_px(s_px) if night else s_px, ox, oy)
            if night:
                add_glow_over(canvas, s_gl, ox, oy)

    big = scale_nn(canvas, 2)
    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, len(big[0]), len(big), big)


def pack_row(frames, fw: int, fh: int):
    out = blank(fw * len(frames), fh)
    for col, f in enumerate(frames):
        for y in range(fh):
            out[y][col * fw:(col + 1) * fw] = f[y]
    return out


def main():
    props = ROOT / "props"

    towers = [build_watchtower_variant(0), build_watchtower_variant(1)]
    wt_sheet = pack_row([t for t, _ in towers], 128, 144)
    wt_glow = pack_row([g for _, g in towers], 128, 144)

    camps = [build_patrol_camp_variant(0), build_patrol_camp_variant(1)]
    cp_sheet = pack_row([c for c, _ in camps], 96, 64)
    cp_glow = pack_row([g for _, g in camps], 96, 64)

    banner = build_order_banner()
    verify_banner_padding(banner)

    steles = [build_boundary_stone(0), build_boundary_stone(1), build_boundary_stone(2)]
    bs_sheet = pack_row([s for s, _ in steles], 48, 56)
    bs_glow = pack_row([g for _, g in steles], 48, 56)

    outputs = [
        ("order_watchtower.png", wt_sheet, 256, 144),
        ("order_watchtower_glow.png", wt_glow, 256, 144),
        ("order_patrol_camp.png", cp_sheet, 192, 64),
        ("order_patrol_camp_glow.png", cp_glow, 192, 64),
        ("order_banner.png", banner, 32, 64),
        ("order_boundary_stone.png", bs_sheet, 144, 56),
        ("order_boundary_stone_glow.png", bs_glow, 144, 56),
    ]
    for name, px, ew, eh in outputs:
        assert (len(px[0]), len(px)) == (ew, eh), f"{name} size mismatch"
        verify_no_black(name, px)
        write_png(props / name, ew, eh, px)

    render_qa_sheet(towers, camps, banner, steles)
    print("Wrote 7 Red Order PNGs and docs/img/red_order_sheet.png")


if __name__ == "__main__":
    main()
