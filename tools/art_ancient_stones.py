#!/usr/bin/env python3
"""Handcrafted next-gen planar pixel-art Ancient Sanctuary Stonework 2.0 & Standing Ruin Companions.

Upgrades in v2.0:
  - Subtle stonecutter chisel strokes & pale calcite veins (calm clusters, zero salt-and-pepper noise!)
  - Crustose lichen rosettes in silver-sage, muted Xanthoria-gold & slate-teal (harmonized with LivingRock)
  - Weathered antique bronze/gold filigree inlays (Design Guide Row 7: #6f5020 -> #b48a38 -> #e6c468 -> #fff0b0)
    on relic slabs, blossom seals & the central Sanctuary Plaza medallion + tucked fracture leaf specks
  - 4 Y-sorted 3/4 Standing Ruin Companion Props (8 cells of 48x40 px -> assets/props/sanctuary_ruins.png + _glow.png):
      0..1  sanctuary_waymarker  (tilted runic milestone stele with moss cap & night rune)
      2..3  fallen_column_drum   (half-sunken fluted limestone column drum with creeping ivy)
      4..5  sanctuary_parapet    (moss-capped coursed ashlar shrine parapet — intact & weathered stepped)
      6..7  ancient_dew_basin    (carved pedestal dew basin — dry stone & filled with shimmering Star-Dew!)
"""
from __future__ import annotations

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, hexc, write_png  # noqa: E402

PROJ_ROOT = pathlib.Path(__file__).resolve().parent.parent


def save_grid(path: pathlib.Path, grid: list[list[tuple[int, int, int, int]]]) -> None:
    write_png(path, len(grid[0]), len(grid), grid)

CELL_W, CELL_H = 32, 24
COUNT = 16

RUIN_W, RUIN_H = 48, 40
RUIN_COUNT = 8

# Primary Sanctuary Limestone (cool slate-teal shadow -> crisp pale silver-limestone sunlit plane)
LIMESTONE = [
    hexc("25343e"),  # 0 deep cool slate joint / undercut crease
    hexc("3c4e59"),  # 1 shaded SE lip / deep bevel
    hexc("596c75"),  # 2 cool weathered stone shadow plane
    hexc("7d8e93"),  # 3 calm mid limestone face
    hexc("a1afb0"),  # 4 main sunlit upper stone plane
    hexc("c3ccca"),  # 5 pale sunlit limestone highlight
    hexc("e2e7e2"),  # 6 crisp 1px NW sunlit rim catchlight
]

# Secondary Cool Sanctuary Slate
SLATE = [
    hexc("202f3b"),
    hexc("344656"),
    hexc("4d6272"),
    hexc("6d828f"),
    hexc("8fa3ad"),
    hexc("b3c2c7"),
    hexc("d6e1e2"),
]

# Warm Sun-Weathered Travertine-Ivory
TRAVERTINE = [
    hexc("2a353d"),
    hexc("445056"),
    hexc("657072"),
    hexc("8a918e"),
    hexc("aead9f"),
    hexc("ceccb9"),
    hexc("eae7d4"),
]

# Official Shadowspore Gold Family (Design Guide Row 7 — oxidized antique bronze -> sunlit gold inlay)
GOLD_0 = hexc("6f5020")
GOLD_1 = hexc("b48a38")
GOLD_2 = hexc("e6c468")
GOLD_3 = hexc("fff0b0")

# Living Sanctuary Moss, Ivy & Crustose Lichens (harmonized with Meadow & LivingRock!)
MOSS_0 = hexc("1d4036")
MOSS_1 = hexc("2d5e49")
MOSS_2 = hexc("448256")
MOSS_3 = hexc("66a660")
MOSS_4 = hexc("92cc72")

IVY_0 = hexc("193632")
IVY_1 = hexc("255246")
IVY_2 = hexc("387357")
IVY_3 = hexc("5da16d")

LICHEN_SILVER = (hexc("7c8f8c"), hexc("aebfbd"))
LICHEN_GOLD = (hexc("9e7f3e"), hexc("d4b464"))
LICHEN_TEAL = (hexc("457274"), hexc("72a8a2"))

LEAF_SPECK_0 = hexc("6e422e")
LEAF_SPECK_1 = hexc("9e643a")

# Star-Dew Water Tones (Design Guide Row 8 Turquoise Glow family)
DEW_DEEP = hexc("245c68")
DEW_MID = hexc("2a8c94")
DEW_LIT = hexc("3cc0c6")
DEW_SPARK = hexc("d0fff8")

SE_SHADOW = (18, 34, 34, 92)
FOOT_SHADOW = (14, 22, 30, 74)
MORTAR_SOIL = (30, 48, 46, 220)

# Delicate twilight rune inlay glow
RUNE_DIM = (118, 222, 214, 92)
RUNE_HI = (182, 248, 238, 148)
GOLD_GLOW = (242, 206, 120, 78)


def make_grid(w: int, h: int) -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR] * w for _ in range(h)]


def put(grid: list[list[tuple[int, int, int, int]]], x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = c


def blend_over(dst: tuple[int, int, int, int], src: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    sa = src[3] / 255.0
    if sa <= 0.0:
        return dst
    if sa >= 0.999 or dst[3] == 0:
        return src
    da = dst[3] / 255.0
    oa = sa + da * (1.0 - sa)
    if oa <= 0.001:
        return CLEAR
    return (
        int((src[0] * sa + dst[0] * da * (1.0 - sa)) / oa),
        int((src[1] * sa + dst[1] * da * (1.0 - sa)) / oa),
        int((src[2] * sa + dst[2] * da * (1.0 - sa)) / oa),
        int(oa * 255.0),
    )


def h2(x: int, y: int, seed: int) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / 16777216.0


def stone_shape(
    w: int,
    h: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    seed: int,
    round_r: float = 2.2,
    wobble: float = 0.55,
    chip: tuple[float, float, float] | None = None,
) -> list[list[bool]]:
    """Clean chiselled rectangular/rounded stone block mask with calm edges (zero jagged hooks)."""
    m = [[False] * w for _ in range(h)]
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    rx = max(2.0, (x1 - x0) * 0.5)
    ry = max(2.0, (y1 - y0) * 0.5)
    power = max(2.0, 6.5 - round_r * 1.1)
    for y in range(max(1, y0 - 1), min(h - 2, y1 + 2)):
        for x in range(max(1, x0 - 1), min(w - 1, x1 + 2)):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            ang = math.atan2(ny, nx)
            wob = (0.045 * math.sin(ang * 3.0 + seed * 1.3) + 0.03 * math.cos(ang * 4.0 - seed * 0.7)) * wobble
            d = (abs(nx) ** power + abs(ny) ** power) ** (1.0 / power)
            if d <= 1.0 + wob:
                if chip is not None and (x - chip[0]) ** 2 + (y - chip[1]) ** 2 < chip[2] ** 2:
                    continue
                m[y][x] = True
    out = [r[:] for r in m]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if m[y][x]:
                nb = int(m[y - 1][x]) + int(m[y + 1][x]) + int(m[y][x - 1]) + int(m[y][x + 1])
                if nb <= 1:
                    out[y][x] = False
    return out


def stamp_lichen(
    px: list[list[tuple[int, int, int, int]]],
    mask: list[list[bool]],
    cx: int,
    cy: int,
    pair: tuple[tuple[int, int, int, int], tuple[int, int, int, int]],
) -> None:
    """Places a crisp 2x2 / 3x2 crustose lichen rosette strictly inside a stone plane."""
    h, w = len(mask), len(mask[0])
    offsets = [(0, 0, pair[1]), (1, 0, pair[1]), (0, 1, pair[0]), (1, 1, pair[0]), (-1, 0, pair[0])]
    for ox, oy, col in offsets:
        x, y = cx + ox, cy + oy
        if 1 <= y < h - 1 and 1 <= x < w - 1 and mask[y][x] and mask[y - 1][x] and mask[y + 1][x]:
            px[y][x] = col


def shade_planar_stone(
    px: list[list[tuple[int, int, int, int]]],
    mask: list[list[bool]],
    ramp: list[tuple[int, int, int, int]],
    seed: int,
    lip_px: int = 1,
    moss_amt: float = 0.28,
    cracks: list[list[tuple[int, int]]] | None = None,
    carve: list[tuple[int, int]] | None = None,
    gold_pts: list[tuple[int, int]] | None = None,
    lichen_spots: list[tuple[int, int, tuple[tuple[int, int, int, int], tuple[int, int, int, int]]]] | None = None,
    glow: list[list[tuple[int, int, int, int]]] | None = None,
    glow_carve: bool = False,
) -> None:
    """Shades a stone with planar NW lighting, subtle 2px chisel strokes, calcite vein, lichens & gold inlays."""
    h = len(mask)
    w = len(mask[0])

    xs = [x for y in range(h) for x in range(w) if mask[y][x]]
    ys = [y for y in range(h) for x in range(w) if mask[y][x]]
    if not xs:
        return
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(1.0, float(max_x - min_x))
    span_y = max(1.0, float(max_y - min_y))

    # 1. Subtle SE contact shadow ONLY below south/east lip
    if lip_px > 0:
        for y in range(h):
            for x in range(w):
                if mask[y][x]:
                    continue
                if (y - lip_px - 1 >= 0 and mask[y - lip_px - 1][x]) or (x > 0 and y > 0 and mask[y - 1][x - 1] and not mask[y][x - 1]):
                    px[y][x] = blend_over(px[y][x], SE_SHADOW)

    # 2. Clean 1-2 px south bevel lip
    for dy in range(1, lip_px + 1):
        for y in range(dy, h):
            for x in range(w):
                if not mask[y][x] and mask[y - dy][x]:
                    right_end = x + 1 >= w or not mask[y - dy][x + 1]
                    px[y][x] = ramp[0] if (dy == lip_px and right_end) else ramp[1]

    # Optional subtle diagonal calcite vein on ~40% of larger stones
    has_vein = (span_x >= 10 and h2(seed, 19, 401) > 0.58)
    vein_c = min_x + int(span_x * (0.35 + 0.30 * h2(seed, 23, 409))) + min_y

    # 3. Broad chiselled stone top face + calm 2px horizontal stonecutter tool marks
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            u = (x - min_x) / span_x
            v = (y - min_y) / span_y
            up_out = y == 0 or not mask[y - 1][x]
            left_out = x == 0 or not mask[y][x - 1]
            down_out = y + 1 >= h or not mask[y + 1][x]
            right_out = x + 1 >= w or not mask[y][x + 1]

            diag = 1.0 - (u * 0.52 + v * 0.48)
            macro_patch = h2(x // 5, y // 4, seed + 31)
            tone = 4 if diag > 0.46 else 3
            if diag > 0.74 and macro_patch > 0.34:
                tone = 5
            elif diag < 0.25 and macro_patch < 0.62:
                tone = 2

            # Subtle 2px horizontal stonecutter chisel stroke inside interior plane (calm, scarce!)
            is_edge = up_out or left_out or down_out or right_out
            if not is_edge:
                chisel = h2(x // 3, y, seed + 93)
                if chisel > 0.90 and (x % 3) < 2:
                    tone = min(5, tone + 1)
                elif chisel < 0.06 and (x % 3) < 2:
                    tone = max(2, tone - 1)
                if has_vein and abs((x + y) - vein_c) == 0 and h2(x // 2, y // 2, seed + 77) > 0.35:
                    tone = min(5, tone + 1)

            # Clean chiselled bevels (1px sunlit NW rim, 1px soft shaded SE inner bevel)
            if (up_out or left_out) and not (down_out or right_out):
                tone = 6 if (up_out and left_out) or diag > 0.52 else 5
            elif down_out or right_out:
                tone = 2 if not (down_out and right_out) else 1

            px[y][x] = ramp[tone]

    # 4. Crustose lichen rosettes on weathered interior faces
    if lichen_spots:
        for lx, ly, lpair in lichen_spots:
            stamp_lichen(px, mask, lx, ly, lpair)

    # 5. Crisp weathered fracture line + occasional tiny trapped dry leaf speck
    if cracks:
        for path in cracks:
            pset = set(path)
            for idx_c, (cx, cy) in enumerate(path):
                if 0 <= cy < h and 0 <= cx < w and mask[cy][cx]:
                    px[cy][cx] = ramp[1]
                    if cy + 1 < h and mask[cy + 1][cx] and (cx, cy + 1) not in pset:
                        px[cy + 1][cx] = ramp[5]
                    if idx_c == len(path) - 1 and h2(cx, cy, seed + 333) > 0.55:
                        px[cy][cx] = LEAF_SPECK_1 if (cx + cy) % 2 == 0 else LEAF_SPECK_0

    # 6. Chiselled recessed groove / ancient sanctuary emblem
    if carve:
        cset = set(carve)
        for cx, cy in carve:
            if 0 <= cy < h and 0 <= cx < w and mask[cy][cx]:
                px[cy][cx] = ramp[1] if (cx + cy + seed) % 4 == 0 else ramp[2]
                if cy + 1 < h and mask[cy + 1][cx] and (cx, cy + 1) not in cset:
                    px[cy + 1][cx] = ramp[5]
                if glow is not None and glow_carve:
                    g = h2(cx, cy, seed + 505)
                    glow[cy][cx] = RUNE_HI if g > 0.58 else RUNE_DIM

    # 7. Oxidized antique bronze / gold filigree inlays at sacred keypoints!
    if gold_pts:
        for gx, gy in gold_pts:
            if 0 <= gy < h and 0 <= gx < w and mask[gy][gx]:
                lit_g = h2(gx, gy, seed + 613) > 0.42
                px[gy][gx] = GOLD_2 if lit_g else GOLD_1
                if glow is not None and glow_carve:
                    glow[gy][gx] = GOLD_GLOW

    # 8. Clustered velvety moss cushions hugging sunken stone edges
    if moss_amt > 0.01:
        for y in range(h):
            for x in range(w):
                if not mask[y][x]:
                    continue
                edge_dist = 0
                if y == 0 or not mask[y - 1][x] or x == 0 or not mask[y][x - 1] or y + 1 >= h or not mask[y + 1][x] or x + 1 >= w or not mask[y][x + 1]:
                    edge_dist = 1
                elif y <= 1 or not mask[y - 2][x] or x <= 1 or not mask[y][x - 2] or y + 2 >= h or not mask[y + 2][x] or x + 2 >= w or not mask[y][x + 2]:
                    edge_dist = 2
                if edge_dist == 0:
                    continue
                cluster = h2(x // 4, y // 4, seed + 211)
                detail = h2(x // 2, y // 2, seed + 277)
                thr = moss_amt if edge_dist == 1 else moss_amt * 0.58
                if cluster < thr and detail < 0.78:
                    lit_top = y == 0 or not mask[y - 1][x] or x == 0 or not mask[y][x - 1]
                    px[y][x] = MOSS_4 if (lit_top and detail < 0.35) else (MOSS_3 if lit_top else (MOSS_2 if edge_dist == 1 else MOSS_1))


def draw_slab_variant(v: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(CELL_W, CELL_H)
    glow = make_grid(CELL_W, CELL_H)

    # ---------------- 0..3: FITTED COURSED SANCTUARY PAVING SLABS ----------------
    if v == 0:
        m1 = stone_shape(CELL_W, CELL_H, 2, 4, 17, 19, seed=11, round_r=1.2, wobble=0.16)
        m2 = stone_shape(CELL_W, CELL_H, 19, 4, 29, 19, seed=12, round_r=1.2, wobble=0.16, chip=(28, 5, 2.8))
        for x in range(16, 20):
            for y in range(5, 19):
                put(px, x, y, MOSS_1 if (x + y) % 5 == 0 else MORTAR_SOIL)
        shade_planar_stone(
            px, m1, LIMESTONE, seed=11, lip_px=1, moss_amt=0.20,
            cracks=[[(9, 6), (10, 7), (10, 8)]],
            lichen_spots=[(6, 13, LICHEN_SILVER)],
        )
        shade_planar_stone(px, m2, SLATE, seed=12, lip_px=1, moss_amt=0.24, lichen_spots=[(23, 14, LICHEN_GOLD)])

    elif v == 1:
        blocks_v1 = [
            (2, 4, 19, 11, LIMESTONE, 21, 0.16, [(7, 7, LICHEN_SILVER)]),
            (21, 4, 29, 11, TRAVERTINE, 22, 0.20, None),
            (2, 13, 12, 19, SLATE, 23, 0.22, None),
            (14, 13, 29, 19, LIMESTONE, 24, 0.20, [(23, 16, LICHEN_GOLD)]),
        ]
        for y in range(5, 19):
            for x in range(3, 29):
                put(px, x, y, MOSS_1 if h2(x, y, 25) < 0.30 else MORTAR_SOIL)
        for bx0, by0, bx1, by1, rmp, sd, ms, lich in blocks_v1:
            bm = stone_shape(CELL_W, CELL_H, bx0, by0, bx1, by1, seed=sd, round_r=1.1, wobble=0.14)
            shade_planar_stone(px, bm, rmp, seed=sd, lip_px=1, moss_amt=ms, lichen_spots=lich)

    elif v == 2:
        # Wide dressed sanctuary threshold stone with carved border groove & bronze corner studs!
        m = stone_shape(CELL_W, CELL_H, 2, 5, 29, 18, seed=37, round_r=1.2, wobble=0.15)
        carve = [(x, 7) for x in range(6, 26)] + [(x, 16) for x in range(6, 26)]
        gold = [(6, 7), (25, 7), (15, 7), (16, 7)]
        shade_planar_stone(
            px, m, LIMESTONE, seed=37, lip_px=1, moss_amt=0.18,
            carve=carve, gold_pts=gold, lichen_spots=[(10, 12, LICHEN_SILVER)],
        )

    elif v == 3:
        m1 = stone_shape(CELL_W, CELL_H, 2, 4, 15, 19, seed=41, round_r=1.2, wobble=0.15)
        m2 = stone_shape(CELL_W, CELL_H, 17, 4, 29, 19, seed=43, round_r=1.2, wobble=0.15)
        for y in range(5, 19):
            put(px, 16, y, MOSS_2 if y % 4 == 0 else MORTAR_SOIL)
        shade_planar_stone(px, m1, SLATE, seed=41, lip_px=1, moss_amt=0.22, lichen_spots=[(6, 8, LICHEN_TEAL)])
        shade_planar_stone(
            px, m2, LIMESTONE, seed=43, lip_px=1, moss_amt=0.22,
            cracks=[[(22, 12), (23, 13), (24, 13)]],
        )

    # ---------------- 4..6: CRACKED & RECLAIMED RUIN SLABS ----------------
    elif v == 4:
        m1 = stone_shape(CELL_W, CELL_H, 3, 4, 15, 19, seed=64, round_r=2.0, wobble=0.45)
        m2 = stone_shape(CELL_W, CELL_H, 18, 5, 28, 19, seed=65, round_r=2.2, wobble=0.45)
        shade_planar_stone(px, m1, LIMESTONE, seed=64, lip_px=2, moss_amt=0.44, lichen_spots=[(8, 10, LICHEN_GOLD)])
        shade_planar_stone(px, m2, LIMESTONE, seed=65, lip_px=2, moss_amt=0.40, lichen_spots=[(22, 13, LICHEN_SILVER)])
        for mx, my, mc in ((16, 8, MOSS_3), (17, 9, MOSS_2), (16, 12, MOSS_4), (17, 13, MOSS_1), (16, 15, MOSS_2)):
            put(px, mx, my, mc)

    elif v == 5:
        m1 = stone_shape(CELL_W, CELL_H, 3, 4, 17, 11, seed=71, round_r=1.6, wobble=0.30)
        m2 = stone_shape(CELL_W, CELL_H, 19, 4, 28, 12, seed=72, round_r=1.6, wobble=0.30)
        m3 = stone_shape(CELL_W, CELL_H, 6, 13, 26, 19, seed=73, round_r=1.6, wobble=0.30)
        shade_planar_stone(px, m1, TRAVERTINE, seed=71, lip_px=1, moss_amt=0.32, lichen_spots=[(9, 7, LICHEN_GOLD)])
        shade_planar_stone(px, m2, SLATE, seed=72, lip_px=1, moss_amt=0.28)
        shade_planar_stone(px, m3, LIMESTONE, seed=73, lip_px=2, moss_amt=0.36, cracks=[[(15, 15), (16, 16)]])

    elif v == 6:
        m = stone_shape(CELL_W, CELL_H, 4, 4, 27, 19, seed=83, round_r=2.4, wobble=0.45)
        cracks = [[(10, 9), (11, 10), (12, 10), (13, 11), (14, 12)]]
        shade_planar_stone(
            px, m, SLATE, seed=83, lip_px=1, moss_amt=0.64,
            cracks=cracks, lichen_spots=[(19, 9, LICHEN_TEAL), (9, 14, LICHEN_SILVER)],
        )

    # ---------------- 7..9: CARVED ANTIQUE KERB & RELIC BORDER SLABS ----------------
    elif v == 7:
        m = stone_shape(CELL_W, CELL_H, 3, 4, 28, 19, seed=97, round_r=1.4, wobble=0.20, chip=(27, 4, 3.0))
        carve = [(x, 6) for x in range(6, 25)] + [(x, 16) for x in range(6, 26)] + [(6, y) for y in range(6, 17)] + [(25, y) for y in range(7, 17)]
        gold = [(6, 6), (24, 6), (6, 16), (25, 16), (15, 11), (16, 11)]
        shade_planar_stone(
            px, m, SLATE, seed=97, lip_px=2, moss_amt=0.22,
            carve=carve, gold_pts=gold, lichen_spots=[(11, 12, LICHEN_SILVER)],
        )

    elif v == 8:
        m1 = stone_shape(CELL_W, CELL_H, 2, 7, 15, 16, seed=103, round_r=1.4, wobble=0.22)
        m2 = stone_shape(CELL_W, CELL_H, 17, 7, 29, 16, seed=104, round_r=1.4, wobble=0.22)
        carve1 = [(x, 10) for x in range(5, 13)]
        carve2 = [(x, 10) for x in range(20, 27)]
        shade_planar_stone(px, m1, LIMESTONE, seed=103, lip_px=2, moss_amt=0.28, carve=carve1, lichen_spots=[(7, 13, LICHEN_GOLD)])
        shade_planar_stone(px, m2, LIMESTONE, seed=104, lip_px=2, moss_amt=0.28, carve=carve2)

    elif v == 9:
        # Carved ancient crescent-spore relic stone with gold star-core & twilight rune glow!
        m = stone_shape(CELL_W, CELL_H, 3, 4, 28, 19, seed=163, round_r=1.8, wobble=0.30)
        carve = []
        for deg in range(-120, 121, 14):
            rad = math.radians(deg)
            carve.append((int(round(15.5 + math.cos(rad) * 5.2)), int(round(11.2 + math.sin(rad) * 3.5))))
        carve += [(15, 11), (16, 11), (15, 9), (15, 13), (8, 7), (23, 7), (8, 15), (23, 15)]
        gold = [(15, 11), (16, 11), (8, 7), (23, 15)]
        shade_planar_stone(
            px, m, SLATE, seed=163, lip_px=2, moss_amt=0.26,
            carve=carve, gold_pts=gold, glow=glow, glow_carve=True,
        )

    # ---------------- 10..13: FLUSH LOW-PROFILE NATURAL STEPPING STONES ----------------
    elif v == 10:
        m = stone_shape(CELL_W, CELL_H, 5, 6, 26, 18, seed=127, round_r=4.6, wobble=0.42)
        shade_planar_stone(
            px, m, LIMESTONE, seed=127, lip_px=1, moss_amt=0.30,
            cracks=[[(18, 10), (19, 11)]], lichen_spots=[(11, 12, LICHEN_SILVER)],
        )

    elif v == 11:
        m1 = stone_shape(CELL_W, CELL_H, 4, 6, 19, 17, seed=139, round_r=4.5, wobble=0.45)
        m2 = stone_shape(CELL_W, CELL_H, 20, 9, 28, 18, seed=141, round_r=4.5, wobble=0.40)
        shade_planar_stone(px, m1, TRAVERTINE, seed=139, lip_px=1, moss_amt=0.28, lichen_spots=[(10, 11, LICHEN_GOLD)])
        shade_planar_stone(px, m2, LIMESTONE, seed=141, lip_px=1, moss_amt=0.34)

    elif v == 12:
        m = stone_shape(CELL_W, CELL_H, 4, 7, 27, 17, seed=151, round_r=4.2, wobble=0.38)
        cracks = [[(15, 8), (15, 9), (16, 10), (16, 11)]]
        shade_planar_stone(px, m, SLATE, seed=151, lip_px=1, moss_amt=0.32, cracks=cracks, lichen_spots=[(20, 12, LICHEN_TEAL)])

    elif v == 13:
        m = stone_shape(CELL_W, CELL_H, 4, 5, 27, 18, seed=179, round_r=3.2, wobble=0.32)
        carve = [
            (15, 7), (16, 7), (13, 8), (18, 8), (11, 9), (20, 9),
            (11, 12), (20, 12), (13, 13), (18, 13), (15, 14), (16, 14),
            (15, 10), (16, 10), (15, 11), (16, 11),
        ]
        gold = [(15, 10), (16, 11)]
        shade_planar_stone(
            px, m, LIMESTONE, seed=179, lip_px=1, moss_amt=0.26,
            carve=carve, gold_pts=gold, glow=glow, glow_carve=True,
        )

    # ---------------- 14..15: WEATHERED TAIL-OFF FRAGMENTS ----------------
    elif v == 14:
        for x0, y0, x1, y1, rmp, sd in (
            (5, 6, 16, 14, LIMESTONE, 191),
            (18, 8, 26, 16, SLATE, 193),
            (10, 15, 18, 20, TRAVERTINE, 195),
        ):
            sm = stone_shape(CELL_W, CELL_H, x0, y0, x1, y1, seed=sd, round_r=3.8, wobble=0.40)
            shade_planar_stone(px, sm, rmp, seed=sd, lip_px=1, moss_amt=0.36)

    else:
        for x0, y0, x1, y1, rmp, sd in (
            (6, 8, 13, 14, TRAVERTINE, 201),
            (15, 6, 23, 12, LIMESTONE, 203),
            (16, 13, 25, 19, SLATE, 205),
        ):
            sm = stone_shape(CELL_W, CELL_H, x0, y0, x1, y1, seed=sd, round_r=4.2, wobble=0.40)
            shade_planar_stone(px, sm, rmp, seed=sd, lip_px=1, moss_amt=0.40)

    return px, glow


def draw_ancient_courtyard() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """112x80 px Cohesive Ancient Sanctuary Crossroads Plaza 2.0:
    Flush 1px mortar bed, stonecutter chisel texture, lichen rosettes, cardinal threshold carvings,
    and an antique bronze-and-rune sanctuary medallion at the crossroads center!"""
    w, h = 112, 80
    px = make_grid(w, h)
    glow = make_grid(w, h)

    # (x0, y0, x1, y1, ramp, seed, moss, chip, crack, lich, carve)
    blocks = [
        # North Gateway Threshold
        (34, 4, 55, 16, LIMESTONE, 10, 0.24, None, [[(44, 6), (44, 7), (45, 8)]], [(39, 10, LICHEN_SILVER)], [(x, 8) for x in range(38, 52)]),
        (56, 4, 78, 16, SLATE, 11, 0.24, (77, 5, 2.5), None, [(68, 10, LICHEN_GOLD)], [(x, 8) for x in range(60, 74)]),

        # Upper Courtyard Course
        (16, 17, 35, 30, SLATE, 20, 0.28, (17, 18, 2.8), None, [(23, 23, LICHEN_TEAL)], None),
        (36, 17, 55, 27, LIMESTONE, 21, 0.16, None, None, None, None),
        (56, 17, 75, 27, TRAVERTINE, 22, 0.16, None, [[(63, 19), (64, 20)]], [(68, 21, LICHEN_GOLD)], None),
        (76, 17, 96, 30, LIMESTONE, 23, 0.28, (95, 18, 2.8), [[(86, 22), (87, 23)]], [(82, 24, LICHEN_SILVER)], None),

        # West & East Road Threshold Wings
        (6, 31, 30, 48, LIMESTONE, 30, 0.22, None, [[(15, 36), (16, 37), (16, 38)]], [(11, 41, LICHEN_GOLD)], [(10, y) for y in range(34, 45)]),
        (81, 31, 105, 48, SLATE, 31, 0.22, None, [[(94, 38), (95, 39)]], [(98, 42, LICHEN_TEAL)], [(101, y) for y in range(34, 45)]),

        # Lower Courtyard Course
        (16, 49, 35, 62, TRAVERTINE, 40, 0.30, (17, 61, 2.8), None, [(24, 55, LICHEN_GOLD)], None),
        (36, 52, 55, 62, SLATE, 41, 0.18, None, None, [(43, 57, LICHEN_SILVER)], None),
        (56, 52, 75, 62, LIMESTONE, 42, 0.18, None, [[(66, 56), (66, 57)]], None, None),
        (76, 49, 96, 62, TRAVERTINE, 43, 0.30, (95, 61, 3.0), None, [(85, 55, LICHEN_GOLD)], None),

        # South Gateway Steps
        (34, 63, 55, 75, LIMESTONE, 50, 0.28, None, None, [(41, 69, LICHEN_SILVER)], [(x, 71) for x in range(38, 52)]),
        (56, 63, 78, 75, SLATE, 51, 0.30, (77, 74, 2.5), [[(65, 66), (66, 67)]], [(70, 69, LICHEN_TEAL)], [(x, 71) for x in range(60, 74)]),
    ]

    block_masks = []
    any_stone = [[False] * w for _ in range(h)]
    for x0, y0, x1, y1, rmp, sd, ms, ch, cr, lich, cv in blocks:
        bm = stone_shape(w, h, x0, y0, x1, y1, seed=sd, round_r=0.9, wobble=0.10, chip=ch)
        block_masks.append((bm, rmp, sd, ms, cr, lich, cv))
        for y in range(h):
            for x in range(w):
                if bm[y][x]:
                    any_stone[y][x] = True

    cm = [[False] * w for _ in range(h)]
    cx, cy, rx, ry = 56.0, 39.5, 25.5, 13.5
    for y in range(24, 56):
        for x in range(29, 83):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            if nx * nx + ny * ny <= 1.0:
                if (x - 76) ** 2 + (y - 31) ** 2 < 7:
                    continue
                cm[y][x] = True
                any_stone[y][x] = True

    plaza_bed = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            in_core = (17 <= x <= 95 and 18 <= y <= 61)
            in_ns = (35 <= x <= 77 and 5 <= y <= 74)
            in_ew = (7 <= x <= 104 and 32 <= y <= 47)
            if any_stone[y][x] or in_core or in_ns or in_ew:
                plaza_bed[y][x] = True

    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if plaza_bed[y][x]:
                continue
            if plaza_bed[y - 1][x]:
                px[y][x] = LIMESTONE[1]
            elif y >= 2 and plaza_bed[y - 2][x]:
                px[y][x] = SE_SHADOW

    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if plaza_bed[y][x] and not any_stone[y][x]:
                hv = h2(x // 2, y // 2, 999)
                px[y][x] = MOSS_2 if hv < 0.14 else (MOSS_1 if hv < 0.34 else (LIMESTONE[0] if hv < 0.68 else MORTAR_SOIL))

    for bm, rmp, sd, ms, cr, lich, cv in block_masks:
        shade_planar_stone(px, bm, rmp, seed=sd, lip_px=0, moss_amt=ms, cracks=cr, lichen_spots=lich, carve=cv)

    carve: list[tuple[int, int]] = []
    for deg in range(0, 360, 4):
        rad = math.radians(deg)
        carve.append((int(round(cx + math.cos(rad) * 19.0)), int(round(cy + math.sin(rad) * 9.8))))
        if -125 <= ((deg + 180) % 360 - 180) <= 125:
            carve.append((int(round(cx + math.cos(rad) * 10.2)), int(round(cy + math.sin(rad) * 5.4))))
    for d in range(-6, 7):
        carve.append((int(cx) + d, int(cy)))
    for d in range(-3, 4):
        carve.append((int(cx), int(cy) + d))

    # Cardinal & central oxidized gold filigree studs in the medallion!
    gold_medallion = [
        (56, 39), (56, 40), (55, 39),
        (37, 39), (75, 39), (56, 30), (56, 49),
        (46, 39), (66, 39),
    ]
    cracks = [
        [(69, 31), (68, 32), (67, 33), (66, 34)],
        [(42, 47), (43, 46), (44, 46)],
    ]
    shade_planar_stone(
        px, cm, SLATE, seed=777, lip_px=0, moss_amt=0.22,
        cracks=cracks, carve=carve, gold_pts=gold_medallion,
        lichen_spots=[(35, 36, LICHEN_SILVER), (72, 43, LICHEN_GOLD)],
        glow=glow, glow_carve=True,
    )
    return px, glow


# ==============================================================================
# Standing 3/4 Ruin Companion Props (48x40 px per cell, pivot at foot (24, 34))
# ==============================================================================

def stamp_foot_shadow(px: list[list[tuple[int, int, int, int]]], cx: float, cy: float, rx: float, ry: float) -> None:
    h, w = len(px), len(px[0])
    for y in range(max(0, int(cy - ry - 1)), min(h, int(cy + ry + 2))):
        for x in range(max(0, int(cx - rx - 1)), min(w, int(cx + rx + 2))):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                px[y][x] = blend_over(px[y][x], FOOT_SHADOW)


def stamp_ivy_vine(
    px: list[list[tuple[int, int, int, int]]],
    pts: list[tuple[int, int]],
    seed: int,
) -> None:
    """Draws crisp 3x2 / 2x2 dark-emerald ivy leaf clusters climbing over ruin stone."""
    for idx, (ix, iy) in enumerate(pts):
        lit = idx % 2 == 0
        c_hi = IVY_3 if lit else IVY_2
        c_mid = IVY_2 if lit else IVY_1
        c_dk = IVY_0
        put(px, ix, iy, c_hi)
        put(px, ix + 1, iy, c_mid)
        put(px, ix, iy + 1, c_mid)
        put(px, ix + 1, iy + 1, c_dk)
        if h2(ix, iy, seed) > 0.45:
            put(px, ix - 1, iy + 1, IVY_1)


def draw_ruin_companion(idx: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """Generates the 8 cells (48x40, foot at (24, 34)) of assets/props/sanctuary_ruins.png."""
    px = make_grid(RUIN_W, RUIN_H)
    glow = make_grid(RUIN_W, RUIN_H)

    # 0 & 1: sanctuary_waymarker — Tilted Runic Sanctuary Waystone Stele (~20x30 px)
    if idx in (0, 1):
        tilt = -0.14 if idx == 0 else 0.13
        stamp_foot_shadow(px, 24.0, 34.5, 9.5, 3.2)
        # Base plinth stone sunk in earth
        plinth = stone_shape(RUIN_W, RUIN_H, 16, 29, 32, 35, seed=301 + idx, round_r=1.4, wobble=0.22)
        shade_planar_stone(px, plinth, SLATE, seed=301 + idx, lip_px=1, moss_amt=0.45)

        # Standing tapered & slightly tilted stele shaft (y = 7..32)
        shaft = [[False] * RUIN_W for _ in range(RUIN_H)]
        for y in range(7, 33):
            prog = (33 - y) / 26.0
            cx_y = 24.0 + (y - 31) * (-tilt * 2.2)
            half_w = 6.6 - prog * 1.4
            for x in range(12, 36):
                if abs(x - cx_y) <= half_w:
                    # Weathered top bevel & chip
                    if y == 7 and abs(x - cx_y) > half_w - 1.8:
                        continue
                    if idx == 0 and (x - 28) ** 2 + (y - 9) ** 2 < 4.5:
                        continue
                    shaft[y][x] = True

        # Shade 3D standing stele: left/NW face lit (LIMESTONE 4..6), right/SE side plane shaded (LIMESTONE 1..2), dark outline!
        for y in range(6, 34):
            for x in range(11, 37):
                if not shaft[y][x]:
                    continue
                up_o = not shaft[y - 1][x]
                dn_o = not shaft[y + 1][x]
                lf_o = not shaft[y][x - 1]
                rt_o = not shaft[y][x + 1]
                cx_y = 24.0 + (y - 31) * (-tilt * 2.2)
                rel_x = x - cx_y
                if up_o and not rt_o:
                    col = LIMESTONE[6] if rel_x < 1.5 else LIMESTONE[5]
                elif lf_o:
                    col = LIMESTONE[5] if y < 22 else LIMESTONE[4]
                elif rt_o or dn_o:
                    col = LIMESTONE[0]
                elif rel_x > 2.6:
                    col = LIMESTONE[2] if y < 20 else LIMESTONE[1]  # 3/4 right side bevel plane!
                else:
                    col = LIMESTONE[4] if (y < 18 and rel_x < 0.8) else LIMESTONE[3]
                px[y][x] = col

        # Carved vertical directional rune + antique gold star stud + moss cap + lichen!
        rune_x = 23 if idx == 0 else 24
        rune_pts = [(rune_x, y) for y in range(13, 25)] + [
            (rune_x - 2, 16), (rune_x - 1, 15), (rune_x + 1, 15), (rune_x + 2, 16),
            (rune_x - 2, 20), (rune_x + 2, 20),
        ]
        for rx_p, ry_p in rune_pts:
            if shaft[ry_p][rx_p]:
                px[ry_p][rx_p] = SLATE[1]
                if shaft[ry_p][rx_p + 1]:
                    px[ry_p][rx_p + 1] = LIMESTONE[5]
                glow[ry_p][rx_p] = RUNE_HI if ry_p in (15, 18, 21) else RUNE_DIM
        # Gold center boss
        put(px, rune_x, 18, GOLD_2)
        put(glow, rune_x, 18, GOLD_GLOW)
        stamp_lichen(px, shaft, rune_x - 3, 25, LICHEN_GOLD)
        # Plush moss cap on top shoulder & base (tracks stele tilt!)
        top_x = int(round(24.0 + (8 - 31) * (-tilt * 2.2)))
        for mx, my, mc in ((top_x - 2, 7, MOSS_4), (top_x - 1, 7, MOSS_3), (top_x, 8, MOSS_2), (18, 31, MOSS_3), (19, 32, MOSS_2), (28, 32, MOSS_1)):
            if 0 <= my < RUIN_H and 0 <= mx < RUIN_W:
                put(px, mx, my, mc)
        if idx == 1:
            stamp_ivy_vine(px, [(26, 28), (25, 25), (26, 22)], seed=311)

    # 2 & 3: fallen_column_drum — Half-Sunken Fluted Sanctuary Column Drum (~32x22 px)
    elif idx in (2, 3):
        stamp_foot_shadow(px, 24.0, 34.0, 15.5, 4.0)
        drum = [[False] * RUIN_W for _ in range(RUIN_H)]
        for y in range(15, 35):
            for x in range(9, 39):
                nx = (x - 24.0) / 14.2
                ny = (y - 25.0) / 8.8
                if nx * nx + ny * ny <= 1.0:
                    if idx == 3 and (x - 35) ** 2 + (y - 18) ** 2 < 9.0:
                        continue
                    drum[y][x] = True

        # Top elliptical cross-section face vs curved fluted cylindrical side!
        for y in range(14, 36):
            for x in range(8, 40):
                if not drum[y][x]:
                    continue
                up_o = not drum[y - 1][x]
                dn_o = not drum[y + 1][x]
                lf_o = not drum[y][x - 1]
                rt_o = not drum[y][x + 1]
                in_top_face = ((x - 23.5) / 12.2) ** 2 + ((y - 20.2) / 4.5) ** 2 <= 1.0
                if dn_o or rt_o:
                    px[y][x] = TRAVERTINE[0] if dn_o and y >= 33 else TRAVERTINE[1]
                elif up_o or lf_o:
                    px[y][x] = TRAVERTINE[6] if x < 26 else TRAVERTINE[5]
                elif in_top_face:
                    # Carved ring + dowel socket in the broken column top!
                    ring_d = math.hypot((x - 23.5) / 9.0, (y - 20.2) / 3.2)
                    if abs(x - 23.5) <= 1.2 and abs(y - 20.2) <= 1.0:
                        px[y][x] = TRAVERTINE[1]
                    elif 0.85 <= ring_d <= 1.02:
                        px[y][x] = TRAVERTINE[2]
                    else:
                        px[y][x] = TRAVERTINE[5] if x + y < 44 else TRAVERTINE[4]
                else:
                    # Vertical classical fluting ribs along the drum cylinder!
                    flute = (x - 10) % 4
                    base_t = 4 if x < 20 else (3 if x < 29 else 2)
                    if flute == 0:
                        base_t = max(1, base_t - 1)
                    elif flute == 1:
                        base_t = min(5, base_t + 1)
                    px[y][x] = TRAVERTINE[base_t]

        stamp_lichen(px, drum, 15, 26, LICHEN_SILVER)
        stamp_ivy_vine(
            px,
            [(30, 31), (28, 28), (29, 25), (31, 22)] if idx == 2 else [(13, 31), (15, 28), (17, 25)],
            seed=330 + idx,
        )
        for mx, my, mc in ((12, 32, MOSS_2), (13, 33, MOSS_3), (14, 33, MOSS_1), (33, 32, MOSS_1)):
            put(px, mx, my, mc)

    # 4 & 5: sanctuary_parapet — Low Coursed Ashlar Shrine Parapet Wall (~38x22 px)
    elif idx in (4, 5):
        max_x = 42 if idx == 4 else 37
        stamp_foot_shadow(px, 24.0, 34.5, 18.5 if idx == 4 else 15.5, 3.6)
        # Lower ashlar course (y = 23..34)
        courses = [
            (6, 24, 18, 34, SLATE, 401),
            (19, 24, 31, 34, LIMESTONE, 402),
        ]
        if idx == 4:
            courses.append((32, 24, 42, 34, SLATE, 403))
        else:
            courses.append((32, 27, 39, 34, TRAVERTINE, 404))

        for y in range(24, 35):
            for x in range(7, max_x):
                put(px, x, y, MORTAR_SOIL)
        for x0, y0, x1, y1, rmp, sd in courses:
            bm = stone_shape(RUIN_W, RUIN_H, x0, y0, x1, y1, seed=sd, round_r=0.8, wobble=0.10)
            shade_planar_stone(px, bm, rmp, seed=sd, lip_px=1, moss_amt=0.25)

        # Overhanging dressed coping cap slab on top (y = 16..24)!
        cap_end = 43 if idx == 4 else 33
        cap = stone_shape(RUIN_W, RUIN_H, 5, 16, cap_end, 24, seed=410 + idx, round_r=1.0, wobble=0.12)
        carve_cap = [(x, 20) for x in range(9, cap_end - 3)]
        gold_cap = [(9, 20), ((9 + cap_end - 4) // 2, 20), (cap_end - 4, 20)]
        shade_planar_stone(
            px, cap, LIMESTONE, seed=410 + idx, lip_px=1, moss_amt=0.34,
            carve=carve_cap, gold_pts=gold_cap,
            lichen_spots=[(14, 18, LICHEN_GOLD), (28, 19, LICHEN_SILVER)],
        )
        stamp_ivy_vine(px, [(8, 31), (9, 28), (10, 24)] if idx == 4 else [(29, 31), (31, 28), (33, 25)], seed=420 + idx)

    # 6 & 7: ancient_dew_basin — Carved Sanctuary Pedestal Dew Basin (6 = Dry, 7 = Star-Dew Filled!)
    else:
        filled = (idx == 7)
        stamp_foot_shadow(px, 24.0, 34.5, 12.5, 3.6)
        # Short carved pedestal foot (y = 26..34)
        ped = stone_shape(RUIN_W, RUIN_H, 15, 26, 33, 34, seed=501, round_r=1.5, wobble=0.15)
        shade_planar_stone(px, ped, SLATE, seed=501, lip_px=1, moss_amt=0.36)

        # Wide carved stone basin bowl above pedestal (y = 15..28, x = 10..38)
        bowl = stone_shape(RUIN_W, RUIN_H, 10, 15, 38, 28, seed=505, round_r=3.2, wobble=0.18)
        carve_rim = [(13, 21), (35, 21), (24, 26)]
        gold_rim = [(12, 21), (36, 21), (24, 16), (24, 27)]
        shade_planar_stone(
            px, bowl, LIMESTONE, seed=505, lip_px=2, moss_amt=0.24,
            carve=carve_rim, gold_pts=gold_rim,
            lichen_spots=[(14, 24, LICHEN_SILVER)],
            glow=glow, glow_carve=filled,
        )

        # Recessed interior bowl cavity (cx=24, cy=21, rx=10.5, ry=4.2)
        for y in range(16, 26):
            for x in range(13, 36):
                nx = (x - 24.0) / 10.2
                ny = (y - 21.0) / 4.0
                d2 = nx * nx + ny * ny
                if d2 <= 1.0:
                    if not filled:
                        # Dry recessed carved stone hollow with north inner wall shadow!
                        px[y][x] = SLATE[0] if ny < -0.45 else (SLATE[1] if ny < 0.15 else SLATE[2])
                    else:
                        # Crystal-clear Star-Dew mirror pool with luminous turquoise-white surface catchlights!
                        if ny < -0.52:
                            px[y][x] = DEW_DEEP
                        elif d2 < 0.38:
                            px[y][x] = DEW_LIT
                            glow[y][x] = RUNE_HI
                        else:
                            px[y][x] = DEW_MID
                            glow[y][x] = RUNE_DIM
        if filled:
            for sx, sy in ((20, 19), (21, 19), (22, 19), (27, 22), (28, 22)):
                put(px, sx, sy, DEW_SPARK)
                put(glow, sx, sy, (216, 255, 250, 195))

    return px, glow


def build_preview(
    slabs: list[tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]],
    courtyard: tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]],
) -> list[list[tuple[int, int, int, int]]]:
    cols, rows, pad = 4, 4, 4
    cw, ch = CELL_W + pad, CELL_H + pad
    left_w = cols * cw + pad
    w = left_w + 122
    h = max(rows * ch + pad * 2, 174)
    bg_meadow = hexc("3e7d56")
    bg_path = hexc("736456")
    img = [[bg_meadow] * w for _ in range(h)]
    for y in range(h // 2, h):
        for x in range(left_w):
            img[y][x] = bg_path

    for idx, (sp, _sg) in enumerate(slabs):
        gx = pad + (idx % cols) * cw
        gy = pad + (idx // cols) * ch
        for y in range(CELL_H):
            for x in range(CELL_W):
                img[gy + y][gx + x] = blend_over(img[gy + y][gx + x], sp[y][x])

    rx = left_w + 5
    cp, cg = courtyard
    for y in range(len(cp)):
        for x in range(len(cp[0])):
            img[pad + y][rx + x] = blend_over(img[pad + y][rx + x], cp[y][x])

    ny = pad + 86
    for y in range(len(cp)):
        for x in range(len(cp[0])):
            if ny + y >= h:
                continue
            img[ny + y][rx + x] = hexc("141d29")
            p = cp[y][x]
            if p[3]:
                dim = (int(p[0] * 0.42), int(p[1] * 0.48), int(p[2] * 0.66), p[3])
                img[ny + y][rx + x] = blend_over(img[ny + y][rx + x], dim)
            g = cg[y][x]
            if g[3]:
                img[ny + y][rx + x] = blend_over(img[ny + y][rx + x], g)

    return img


def build_ruins_preview(
    ruins: list[tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]],
) -> list[list[tuple[int, int, int, int]]]:
    pad = 6
    cols = 4
    w = cols * (RUIN_W + pad) + pad
    h = 3 * (RUIN_H + pad) + pad
    bg_meadow = hexc("3e7d56")
    bg_night = hexc("141d29")
    img = [[bg_meadow] * w for _ in range(h)]
    # Bottom row shows night glow on cells 0, 1, 6, 7!
    y_night0 = 2 * (RUIN_H + pad)
    for y in range(y_night0, h):
        for x in range(w):
            img[y][x] = bg_night

    for idx, (rp, _rg) in enumerate(ruins):
        gx = pad + (idx % cols) * (RUIN_W + pad)
        gy = pad + (idx // cols) * (RUIN_H + pad)
        for y in range(RUIN_H):
            for x in range(RUIN_W):
                img[gy + y][gx + x] = blend_over(img[gy + y][gx + x], rp[y][x])

    for col_i, r_idx in enumerate((0, 1, 6, 7)):
        rp, rg = ruins[r_idx]
        gx = pad + col_i * (RUIN_W + pad)
        gy = pad + 2 * (RUIN_H + pad)
        for y in range(RUIN_H):
            for x in range(RUIN_W):
                p = rp[y][x]
                if p[3]:
                    dim = (int(p[0] * 0.42), int(p[1] * 0.48), int(p[2] * 0.66), p[3])
                    img[gy + y][gx + x] = blend_over(img[gy + y][gx + x], dim)
                g = rg[y][x]
                if g[3]:
                    img[gy + y][gx + x] = blend_over(img[gy + y][gx + x], g)
    return img


def scale_nearest(grid: list[list[tuple[int, int, int, int]]], factor: int) -> list[list[tuple[int, int, int, int]]]:
    out: list[list[tuple[int, int, int, int]]] = []
    for row in grid:
        scaled_row: list[tuple[int, int, int, int]] = []
        for p in row:
            scaled_row.extend([p] * factor)
        for _ in range(factor):
            out.append(list(scaled_row))
    return out


def main() -> None:
    strip = make_grid(CELL_W * COUNT, CELL_H)
    strip_glow = make_grid(CELL_W * COUNT, CELL_H)
    slabs = []
    for v in range(COUNT):
        sp, sg = draw_slab_variant(v)
        slabs.append((sp, sg))
        x0 = v * CELL_W
        for y in range(CELL_H):
            for x in range(CELL_W):
                strip[y][x0 + x] = sp[y][x]
                strip_glow[y][x0 + x] = sg[y][x]

    tiles_dir = PROJ_ROOT / "assets" / "tiles"
    save_grid(tiles_dir / "ancient_stones.png", strip)
    save_grid(tiles_dir / "ancient_stones_glow.png", strip_glow)

    courtyard_px, courtyard_glow = draw_ancient_courtyard()
    save_grid(tiles_dir / "ancient_courtyard.png", courtyard_px)
    save_grid(tiles_dir / "ancient_courtyard_glow.png", courtyard_glow)
    save_grid(tiles_dir / "ancient_rondell.png", courtyard_px)
    save_grid(tiles_dir / "ancient_rondell_glow.png", courtyard_glow)

    # Standing 3/4 Ruin Companion Props Sheet (8 cells x 48x40 = 384x40)
    ruin_strip = make_grid(RUIN_W * RUIN_COUNT, RUIN_H)
    ruin_glow_strip = make_grid(RUIN_W * RUIN_COUNT, RUIN_H)
    ruins = []
    for r_i in range(RUIN_COUNT):
        rp, rg = draw_ruin_companion(r_i)
        ruins.append((rp, rg))
        rx0 = r_i * RUIN_W
        for y in range(RUIN_H):
            for x in range(RUIN_W):
                ruin_strip[y][rx0 + x] = rp[y][x]
                ruin_glow_strip[y][rx0 + x] = rg[y][x]

    props_dir = PROJ_ROOT / "assets" / "props"
    save_grid(props_dir / "sanctuary_ruins.png", ruin_strip)
    save_grid(props_dir / "sanctuary_ruins_glow.png", ruin_glow_strip)

    preview = scale_nearest(build_preview(slabs, (courtyard_px, courtyard_glow)), 4)
    out_preview = PROJ_ROOT / "docs" / "img" / "ancient_stones_atlas_4x.png"
    save_grid(out_preview, preview)

    ruin_prev = scale_nearest(build_ruins_preview(ruins), 4)
    out_ruin_prev = PROJ_ROOT / "docs" / "img" / "sanctuary_ruins_preview_4x.png"
    save_grid(out_ruin_prev, ruin_prev)
    print(f"Wrote Ancient Stones 2.0 -> {out_preview} and Standing Ruins -> {out_ruin_prev}")


if __name__ == "__main__":
    main()
