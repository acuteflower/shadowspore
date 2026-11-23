#!/usr/bin/env python3
"""Procedural pixel-art generator for the Ancient Stone Arch Bridge (R3 / V9).

Directly harmonized with `tools/art_ancient_stones.py` and `docs/img/ancient_stones_atlas_4x.png`:
  - Uses `LIMESTONE`, `SLATE`, `TRAVERTINE`, `MOSS_0..4`, `SE_SHADOW`, `MORTAR_SOIL`, `RUNE_DIM`, `RUNE_HI`
    plus `WET_STONE`, `IRON`, `AMBER_*`, `BRIDGE_TEAL*`, and `BRIDGE_AQUA_*` for wet piers, lantern & water-lap.
  - Strictly ZERO `#000000` pixels across base, glow, and 4x atlas outputs.
  - `pier_left` and `pier_right` are independently shaded with consistent NW->SE lighting (never mirrored).
  - `1 px` `#1b1a2e` outline on structural masonry, suppressed (`no_outline`) on feathered shore aprons,
    pier waterline laps, and open arch water throat.

Outputs:
  assets/props/water_bridge.png        160x160 modular RGBA8 sprite sheet
  assets/props/water_bridge_glow.png   160x160 unlit night glow mask (keystones, rune plaques, lantern)
  docs/img/water_bridge_atlas_4x.png   1448x992 (4x nearest) Day + Night assembled & modular QA atlas
"""
from __future__ import annotations

import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import (  # noqa: E402
    LIMESTONE,
    MOSS_0,
    MOSS_1,
    MOSS_2,
    MOSS_3,
    MOSS_4,
    MORTAR_SOIL,
    RUNE_DIM,
    RUNE_HI,
    SE_SHADOW,
    SLATE,
    TRAVERTINE,
    blend_over,
    h2,
    make_grid,
    put,
    shade_planar_stone,
    stone_shape,
)

# ---------------------------------------------------------------------------
# Exported Geometry, Collider, Obstacle & Sheet Region Constants (consumed by M3 WaterBridge)
# ---------------------------------------------------------------------------
SHEET_W = 160
SHEET_H = 160

# Local to WaterBridge.global_position (center of walkable bridge deck):
WALKABLE_DECK_RECT = (-66.0, -14.0, 132.0, 28.0)
NORTH_PARAPET_COLLIDER = (-62.0, -21.0, 124.0, 5.0)
SOUTH_PARAPET_COLLIDER = (-62.0, 14.0, 124.0, 5.0)
PIER_LEFT_OBSTACLE = {"pos": (-26.0, 26.0), "radius_px": 9.0, "strength": 1.0}
PIER_RIGHT_OBSTACLE = {"pos": (26.0, 26.0), "radius_px": 9.0, "strength": 1.0}
ARCH_SHADOW_RECT = (-56.0, -14.0, 112.0, 48.0)

BRIDGE_RECTS = {
    "deck_base": {
        "rect": (8, 8, 144, 56),
        "anchor": (72, 20),
        "mount_offset": (0, 0),
        "z_index": -3,
    },
    "pier_left": {
        "rect": (8, 72, 20, 28),
        "anchor": (10, 24),
        "mount_offset": (-26, 36),
        "z_index": -3,
    },
    "pier_right": {
        "rect": (34, 72, 20, 28),
        "anchor": (10, 24),
        "mount_offset": (26, 36),
        "z_index": -3,
    },
    "lantern_post": {
        "rect": (64, 72, 16, 24),
        "anchor": (8, 21),
        "mount_offset": (-32, -13),
        "parapet_child_offset": (-32, -11),
        "z_index": 0,
    },
    "parapet_north": {
        "rect": (8, 108, 128, 18),
        "anchor": (64, 16),
        "mount_offset": (0, -13),
        "z_index": 0,
    },
    "parapet_south": {
        "rect": (8, 132, 128, 18),
        "anchor": (64, 14),
        "mount_offset": (0, 16),
        "z_index": 0,
    },
}

# ---------------------------------------------------------------------------
# Palettes (harmonized with art_ancient_stones.py + art_water_pois.py, zero #000000)
# ---------------------------------------------------------------------------
OUT = hexc("1b1a2e")
MORTAR = hexc("18162a")
WET_STONE = [hexc(c) for c in ("182034", "223048", "304560", "46607c")]
IRON = [hexc(c) for c in ("1d1b2d", "2e2b42", "46435e", "64607e", "8a86a6")]
AMBER_D = hexc("c87828")
AMBER_M = hexc("ffb84d")
AMBER_H = hexc("fff0b0")
BRIDGE_GOLD = hexc("ffcb6b")
BRIDGE_TEAL = hexc("3cc0c6")
BRIDGE_TEAL_L = hexc("78f4e6")
BRIDGE_RUNE_DIM = hexc("1f6874")
BRIDGE_RUNE_HOT = hexc("d0fff8")
BRIDGE_WATER_SH_RGB = (16, 38, 58)
BRIDGE_AQUA_MID_RGB = (64, 162, 178)
BRIDGE_AQUA_HI_RGB = (144, 232, 228)
BRIDGE_AQUA_FOAM_RGB = (210, 252, 246)
BRIDGE_IVY = [hexc(c) for c in ("142c34", "1e4c44", "2e7254", "4c9a66", "74be7c")]
BRIDGE_TURF = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
BRIDGE_EARTH = [hexc(c) for c in ("262030", "372f3e", "4b3f4e", "63535f", "7d6a70", "988482")]

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def verify_no_black(name: str, px: list[list[tuple[int, int, int, int]]]) -> None:
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} contains forbidden #000000 pixel at ({x}, {y})")


class GlowMap:
    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.px = make_grid(w, h)
        self.pts: list[tuple[int, int, tuple[int, int, int, int], int]] = []

    def emit(
        self,
        base: list[list[tuple[int, int, int, int]]] | None,
        x: int,
        y: int,
        dim_col: tuple[int, int, int, int] | None,
        bright_col: tuple[int, int, int, int],
        halo: int = 1,
    ) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim_col is not None and base is not None:
                base[y][x] = dim_col
            self.px[y][x] = bright_col
            if halo > 0:
                self.pts.append((x, y, bright_col, halo))

    def finish(self) -> list[list[tuple[int, int, int, int]]]:
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


def _outline_masked(
    px: list[list[tuple[int, int, int, int]]],
    no_outline: list[list[bool]],
    color: tuple[int, int, int, int] = OUT,
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    out = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if px[y][x][3] > 0 or no_outline[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= 200 and not no_outline[ny][nx]:
                    out[y][x] = color
                    break
    return out


def _draw_dressed_block(
    px: list[list[tuple[int, int, int, int]]],
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    ramp: list[tuple[int, int, int, int]],
    seed: int,
    lip_top: bool = True,
    lip_bot: bool = True,
    mortar_r: bool = True,
    mortar_b: bool = True,
    base_bias: int = 0,
) -> None:
    """Draws a calm, planar sanctuary ashlar block with NW catchlight and clean mortar."""
    if x1 < x0 or y1 < y0:
        return
    h, w = len(px), len(px[0])
    chip_tr = (x1 - x0 >= 5 and y1 - y0 >= 3 and h2(x0, y0, seed + 7) < 0.22)
    for y in range(max(0, y0), min(h, y1 + 1)):
        for x in range(max(0, x0), min(w, x1 + 1)):
            if (mortar_r and x == x1) or (mortar_b and y == y1):
                px[y][x] = MORTAR_SOIL
                continue
            if chip_tr and x == x1 - 1 and y == y0:
                px[y][x] = MORTAR_SOIL
                continue
            u = (x - x0) / max(1.0, float(x1 - x0))
            v = (y - y0) / max(1.0, float(y1 - y0))
            diag = 1.0 - (u * 0.50 + v * 0.50)
            macro = h2(x // 4, y // 3, seed + 19)
            tone = 4 if diag > 0.45 else 3
            if diag > 0.78 and macro > 0.35:
                tone = 5
            elif diag < 0.22 and macro < 0.55:
                tone = 2
            tone += base_bias
            if lip_top and y == y0:
                tone = max(tone, 5 if x > x0 else 6)
            elif x == x0 and not (lip_bot and y == y1):
                tone = max(tone, 5)
            elif lip_bot and ((mortar_b and y == y1 - 1) or (not mortar_b and y == y1)):
                tone = min(tone, 1)
            px[y][x] = ramp[int(clamp(tone, 0, len(ramp) - 1))]


def _camber_dy(x_local: int) -> int:
    """Gentle 1 px crown camber across the central deck span."""
    d = abs(x_local - 71.5)
    return -1 if d < 30.0 else 0


def _paint_water_lap(
    under_px: list[list[tuple[int, int, int, int]]],
    over_px: list[list[tuple[int, int, int, int]]],
    x0: int,
    x1: int,
    y_water: int,
    seed: int,
) -> None:
    """2-3 px feathered cool water reflection & pale-aqua ripple wisps (no outline)."""
    for x in range(x0, x1 + 1):
        fade = min(1.0, min(x - x0 + 1, x1 - x + 1) / 3.0)
        for dy, base_a in ((0, 124), (1, 78), (2, 34)):
            a = int(base_a * fade)
            if a > 8:
                under_px[y_water + dy][x] = blend_over(under_px[y_water + dy][x], (*BRIDGE_WATER_SH_RGB, a))
        wave = math.sin(x * 0.55 + seed * 0.8) * 0.5 + 0.5
        if wave > 0.35:
            rgb = BRIDGE_AQUA_FOAM_RGB if wave > 0.74 else BRIDGE_AQUA_HI_RGB
            a = int((145 if wave > 0.74 else 92) * fade)
            over_px[y_water][x] = blend_over(over_px[y_water][x], (*rgb, a))
        else:
            over_px[y_water][x] = blend_over(over_px[y_water][x], (*BRIDGE_AQUA_MID_RGB, int(72 * fade)))
        if math.sin(x * 0.41 - seed * 1.1) > 0.42:
            over_px[y_water + 1][x] = blend_over(over_px[y_water + 1][x], (*BRIDGE_AQUA_HI_RGB, int(76 * fade)))


def _draw_ivy(
    px: list[list[tuple[int, int, int, int]]],
    x0: int,
    y0: int,
    length: int,
    sway: float,
    seed: int,
) -> None:
    for k in range(length):
        xx = x0 + int(round(sway * (k * 0.25) + 0.9 * math.sin(k * 0.7 + seed)))
        yy = y0 + k
        tone = 4 if k == 0 else (3 if k < length * 0.5 else (2 if k < length - 1 else 1))
        put(px, xx, yy, BRIDGE_IVY[tone])
        if k % 2 == 1 and k < length - 1:
            side = -1 if (k // 2 + seed) % 2 == 0 else 1
            put(px, xx + side, yy, BRIDGE_IVY[min(4, tone + 1) if side < 0 else max(0, tone - 1)])


def _moss_cluster(
    px: list[list[tuple[int, int, int, int]]],
    x0: int,
    x1: int,
    y_top: int,
    thick: int,
    seed: int,
) -> None:
    h, w = len(px), len(px[0])
    moss_pal = [MOSS_0, MOSS_1, MOSS_2, MOSS_3, MOSS_4]
    for x in range(max(0, x0), min(w, x1 + 1)):
        if h2(x // 3, y_top // 3, seed) > 0.62:
            continue
        drop = int(thick * (0.4 + 0.6 * h2(x // 2, y_top, seed + 5)))
        for dy in range(drop + 1):
            y = y_top + dy
            if not (0 <= y < h) or px[y][x][3] == 0:
                continue
            tone = 4 if dy == 0 and h2(x, y, seed + 11) > 0.45 else (3 if dy == 0 else (2 if dy == 1 else 1))
            px[y][x] = moss_pal[tone]


# ---------------------------------------------------------------------------
# Region Builders
# ---------------------------------------------------------------------------
def build_deck_base() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """144x56 arched flagstone deck + feathered shore aprons + voussoir arch + barrel vault."""
    w, h = 144, 56
    px = make_grid(w, h)
    glow = make_grid(w, h)
    under = make_grid(w, h)
    no_out = [[False] * w for _ in range(h)]

    # 1) Feathered W/E shore approach aprons (`x_local = 0..23` and `120..143`), outside outline_pass
    for y in range(4, 37):
        for x in range(w):
            d = x if x < 24 else ((w - 1 - x) if x >= 120 else 999)
            if d > 23:
                continue
            no_out[y][x] = True
            rel_y = abs(y - 20.0) / 15.0
            n_val = h2(x // 2, y // 2, 401)
            wob = 0.14 * math.sin(y * 0.42) + 0.16 * (n_val - 0.5)
            if rel_y > 0.96 + wob * 0.4:
                continue
            u_in = (d + wob * 4.5) / 13.0 - rel_y * 0.28
            if u_in <= 0.18:
                continue
            alpha = 255 if (d >= 12 and rel_y < 0.82) else (196 if u_in > 0.58 else 112)
            turf = rel_y > 0.68 - 0.22 * (1.0 - min(1.0, d / 16.0)) + wob * 0.28
            if turf:
                col = BRIDGE_TURF[1 if n_val < 0.45 else (2 if n_val < 0.8 else 3)]
            else:
                col = BRIDGE_EARTH[1 if n_val < 0.35 else (2 if n_val < 0.72 else 3)]
            under[y][x] = (col[0], col[1], col[2], alpha)

    # Sunken threshold stepping stones at both approaches (harmonized with art_ancient_stones.py!)
    threshold_stones = [
        (4, 15, 13, 24, LIMESTONE, 501),
        (10, 8, 19, 15, TRAVERTINE, 502),
        (10, 25, 20, 32, SLATE, 503),
        (130, 15, 139, 24, LIMESTONE, 504),
        (124, 8, 133, 15, SLATE, 505),
        (123, 25, 133, 32, TRAVERTINE, 506),
    ]
    for x0, y0, x1, y1, rmp, sd in threshold_stones:
        m = stone_shape(w, h, x0, y0, x1, y1, seed=sd, round_r=2.8, wobble=0.38)
        shade_planar_stone(under, m, rmp, seed=sd, lip_px=1, moss_amt=0.35)
        for yy in range(y0 - 1, y1 + 3):
            for xx in range(x0 - 1, x1 + 2):
                if 0 <= yy < h and 0 <= xx < w:
                    no_out[yy][xx] = True

    # 2) Walkable dressed flagstone deck (`x_local = 14..129`, `y_local = 6..34` + camber)
    # Four neat staggered stone courses across the 28 px deck height
    ramps = [LIMESTONE, SLATE, TRAVERTINE]
    course_bands = [(7, 13), (14, 20), (21, 26), (27, 33)]
    # Soft mortar bed only inside interior deck (`x = 20..123`) so outer approaches stay flush with turf
    for x in range(20, 124):
        cy = _camber_dy(x)
        for y in range(8 + cy, 34 + cy):
            px[y][x] = MORTAR_SOIL

    for r_i, (y0_b, y1_b) in enumerate(course_bands):
        xc = 16 + (5 if r_i % 2 else 0)
        c_idx = 0
        while xc < 126:
            sw = 10 + int(h2(c_idx, r_i, 610) * 5)
            bx0 = max(16, xc)
            bx1 = min(127, xc + sw)
            # Fit cleanly around central medallion (`x = 58..85, y = 11..26`)
            in_medallion_band = (r_i in (1, 2) and bx1 >= 59 and bx0 <= 84)
            if in_medallion_band:
                if bx0 < 58:
                    bx1 = 58
                elif bx1 > 85:
                    bx0 = 85
                else:
                    xc += sw + 1
                    c_idx += 1
                    continue
            if bx1 - bx0 >= 5:
                cy_mid = _camber_dy((bx0 + bx1) // 2)
                if (bx0 < 22 or bx1 > 121) and r_i in (0, 3):
                    xc += sw + 1
                    c_idx += 1
                    continue
                rmp = ramps[(c_idx + r_i * 2) % 3]
                m = stone_shape(
                    w, h,
                    bx0, y0_b + cy_mid, bx1, y1_b + cy_mid,
                    seed=700 + r_i * 40 + c_idx,
                    round_r=1.5, wobble=0.22,
                )
                cracks = None
                if (c_idx + r_i) % 5 == 2:
                    mx = (bx0 + bx1) // 2
                    my = (y0_b + y1_b) // 2 + cy_mid
                    cracks = [[(mx - 1, my - 1), (mx, my), (mx + 1, my + 1)]]
                shade_planar_stone(
                    px, m, rmp,
                    seed=700 + r_i * 40 + c_idx,
                    lip_px=1, moss_amt=0.24 if r_i in (0, 3) else 0.10,
                    cracks=cracks,
                )
            xc += sw + 1
            c_idx += 1

    # Central Carved Lunar-Arch Keystone Medallion (`cx=71.5, cy=18.5`, rx=12, ry=7)
    mcx, mcy, mrx, mry = 71.5, 18.5, 11.5, 6.8
    c_mask = [[False] * w for _ in range(h)]
    for y in range(11, 27):
        for x in range(59, 85):
            nx = (x - mcx) / mrx
            ny = (y - mcy) / mry
            if nx * nx + ny * ny <= 1.0:
                c_mask[y][x] = True
                px[y][x] = MORTAR_SOIL
    carve: list[tuple[int, int]] = []
    for deg in range(-125, 126, 12):
        rad = math.radians(deg)
        carve.append((int(round(mcx + math.cos(rad) * 6.4)), int(round(mcy + math.sin(rad) * 3.8))))
    for d in range(-2, 3):
        carve.append((int(round(mcx)) + d, int(round(mcy))))
        carve.append((int(round(mcx)), int(round(mcy)) + d))
    shade_planar_stone(
        px, c_mask, SLATE, seed=901, lip_px=1, moss_amt=0.16,
        carve=carve, glow=glow, glow_carve=True,
    )

    # 3) Bridge Spandrel Masonry, Radial Voussoirs & Recessed Dark Barrel Vault
    # Keep bank abutments low (`y <= 37` on banks `x < 33` or `x > 110`) so masonry never forms
    # blocky stairs over meadow grass, dropping full depth ONLY across the river channel (`x = 34..109`).
    arch_cx = 71.5
    arch_cy = 55.5
    rx_in, ry_in = 20.0, 14.0
    rx_out, ry_out = 26.0, 19.0

    spandrel_rows = [(33, 37), (38, 43), (44, 50)]
    for sr_i, (sy0, sy1) in enumerate(spandrel_rows):
        x_min = 24 if sr_i == 0 else (33 if sr_i == 1 else 36)
        x_max = 119 if sr_i == 0 else (110 if sr_i == 1 else 107)
        xc = x_min + (4 if sr_i % 2 else 0)
        b_i = 0
        while xc < x_max:
            bw = 10 + int(h2(b_i, sr_i, 811) * 5)
            bx0, bx1 = max(x_min, xc), min(x_max, xc + bw)
            if bx1 - bx0 >= 4:
                rmp = SLATE if (b_i + sr_i) % 3 == 0 else (TRAVERTINE if (b_i + sr_i) % 3 == 1 else LIMESTONE)
                bias = -1 if sr_i == 2 else 0
                _draw_dressed_block(
                    px, bx0, sy0, bx1, sy1, rmp,
                    seed=820 + sr_i * 30 + b_i,
                    lip_top=(sr_i == 0), lip_bot=True,
                    mortar_r=True, mortar_b=(sr_i < 2),
                    base_bias=bias,
                )
            xc += bw
            b_i += 1

    # Carve arch throat, dark wet barrel-vault soffit & radial voussoir stones
    for y in range(34, h):
        for x in range(18, 126):
            dx_i = (x + 0.5 - arch_cx) / rx_in
            dy_i = (arch_cy - (y + 0.5)) / ry_in
            r_in = math.hypot(dx_i, dy_i)

            dx_o = (x + 0.5 - arch_cx) / rx_out
            dy_o = (arch_cy - (y + 0.5)) / ry_out
            r_out = math.hypot(dx_o, dy_o)

            if r_in < 1.0:
                # Open arch water throat at bottom center (`y = 46..55`, inside inner arch)
                if y >= 47:
                    px[y][x] = CLEAR
                    no_out[y][x] = True
                    if y <= 49:
                        # Subtle cool arch shadow lip over water throat without dark outline
                        under[y][x] = blend_over(under[y][x], (*BRIDGE_WATER_SH_RGB, 108 - (y - 47) * 32))
                else:
                    # Wet dark barrel-vault ceiling (soffit) recessed in cool shadow
                    vault_seam = (y + int(abs(x - arch_cx) * 0.28)) % 4 == 0
                    if r_in > 0.87 or vault_seam:
                        px[y][x] = SLATE[0]
                    elif y >= 44 and (x + y) % 5 == 0:
                        px[y][x] = WET_STONE[2]
                    else:
                        px[y][x] = WET_STONE[0 if r_in > 0.55 else 1]
                    if y == 46:
                        no_out[y][x] = True
            elif r_out <= 1.02 and y <= 54:
                # Radial voussoir ring + slightly proud keystone at crown (`ang ~ pi/2`)
                ang = math.atan2(max(0.01, dy_i), dx_i)
                wedge_f = (ang / math.pi) * 11.0
                w_idx = int(wedge_f)
                frac = wedge_f - w_idx
                is_keystone = abs(ang - math.pi * 0.5) < 0.16
                if abs(frac) < 0.10 or abs(1.0 - frac) < 0.10 or r_out > 0.96:
                    px[y][x] = MORTAR_SOIL
                else:
                    rmp = TRAVERTINE if (is_keystone or w_idx % 3 == 1) else (SLATE if w_idx % 3 == 2 else LIMESTONE)
                    lit = 5 if is_keystone else (4 if y < 44 else 3)
                    if r_in < 1.15 and dx_i < 0.25:
                        lit = min(6, lit + 1)
                    if y >= 50:
                        lit = max(1, lit - 1)
                    px[y][x] = rmp[lit]
                if is_keystone and 39 <= y <= 40 and abs(x - arch_cx) < 1.2:
                    # Subtle carved rune pip on the bridge keystone
                    px[y][x] = SLATE[1]
                    glow[y][x] = RUNE_HI if y == 39 else RUNE_DIM

    # Suppress outline along flush deck edges (`y < 34`) so flagstones match `ancient_stones_atlas_4x.png`
    # and along arch bottom throat & pier sockets (`y >= 46`)
    for y in range(0, 34):
        for x in range(w):
            no_out[y][x] = True
    for y in range(46, h):
        for x in range(42, 102):
            no_out[y][x] = True

    # Subtle moss clusters along damp spandrel joints & abutment shoulders
    _moss_cluster(px, 34, 48, 48, 2, 931)
    _moss_cluster(px, 95, 109, 48, 2, 932)

    # Composite stone body over feathered shore aprons & run masked outline
    out = _outline_masked(px, no_out, OUT)
    final = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            c = blend_over(under[y][x], out[y][x])
            final[y][x] = c

    # Ensure stone body overrides approach dirt cleanly where opaque
    for y in range(h):
        for x in range(w):
            if out[y][x][3] >= 220:
                final[y][x] = out[y][x]

    return final, glow


def build_river_pier(is_left: bool) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """20x28 splayed wet river pier with triangular 3/4 cutwater buttress.

    Both `pier_left` and `pier_right` are independently lit from NW -> SE (NEVER mirrored!).
    Top drip-cap starts at `y = 5` (`y_rel = +17`, cleanly visible right below `parapet_south`).
    Waterline lap at `y = 24..27` has `no_outline`.
    """
    w, h = 20, 28
    px = make_grid(w, h)
    under = make_grid(w, h)
    over = make_grid(w, h)
    glow = make_grid(w, h)
    no_out = [[False] * w for _ in range(h)]

    seed = 1103 if is_left else 1207
    cx = 10

    # Pier masonry body (`y = 5..24`) with splayed stepped base (`y = 17..24`)
    for y in range(5, 25):
        if y <= 7:
            hw = 5
        elif y <= 15:
            hw = 5
        elif y <= 20:
            hw = 6
        else:
            hw = 7
        # Slight hand-laid asymmetry between left & right piers
        x_shift = -1 if (is_left and y > 17) else (1 if (not is_left and y > 19) else 0)
        x0 = max(2, cx - hw + (0 if is_left else x_shift))
        x1 = min(w - 3, cx + hw + (x_shift if is_left else 0))

        for x in range(x0, x1 + 1):
            # Strict NW -> SE lighting across BOTH piers
            u = (x - x0) / max(1.0, float(x1 - x0))
            if y <= 7:
                # Sloped travertine drip-cap hoodstone right under parapet_south!
                rmp = TRAVERTINE
                tone = 6 if (y == 5 and u < 0.65) else (5 if u < 0.55 else (3 if u < 0.85 else 2))
                px[y][x] = rmp[tone]
            elif y == 8:
                px[y][x] = MORTAR_SOIL
            elif y <= 15:
                # Upper dry/damp pier shaft with 3/4 cutwater arris near center
                rmp = LIMESTONE
                cut_offset = x - cx
                if y == 12 or (is_left and x == x0 + 3 and y < 12) or (not is_left and x == x1 - 3 and y >= 12):
                    px[y][x] = MORTAR_SOIL
                else:
                    lit = 5 if cut_offset < 0 else (6 if cut_offset == 0 else (3 if cut_offset <= 2 else 2))
                    if y == 9:
                        lit = min(6, lit + 1)
                    if not is_left and cut_offset > 1:
                        lit = max(1, lit - 1)
                    px[y][x] = rmp[lit]
            else:
                # Wet submerged splash zone (`y = 16..24`) using WET_STONE
                cut_offset = x - cx
                if y == 20 or (x == cx - 3 and y < 20):
                    px[y][x] = WET_STONE[0]
                else:
                    wt = 3 if (cut_offset <= 0 and y < 21) else (2 if cut_offset <= 1 else (1 if y < 23 else 0))
                    px[y][x] = WET_STONE[wt]

    # Moss splash band along `y = 14..18`
    _moss_cluster(px, 3, w - 4, 15, 2, seed + 41)

    # Suppress dark outline on bottom waterline (`y >= 22`) so it laps smoothly into water
    for y in range(22, h):
        for x in range(w):
            no_out[y][x] = True

    out = _outline_masked(px, no_out, OUT)
    _paint_water_lap(under, over, 2, w - 3, 24, seed + 77)

    final = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            c = blend_over(under[y][x], out[y][x])
            c = blend_over(c, over[y][x])
            final[y][x] = c

    return final, glow


def build_parapet_north() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """128x18 north (rear) stone parapet with corner bollards, coping slabs & lunar-rune plaque."""
    w, h = 128, 18
    px = make_grid(w, h)
    glow = make_grid(w, h)
    no_out = [[False] * w for _ in range(h)]

    # Main wall coping & rear cheek (`x = 9..118`, gentle 1-2 px crown camber)
    xc = 9
    idx = 0
    while xc < 119:
        bw = 10 + int(h2(idx, 1, 1401) * 4)
        bx0, bx1 = xc, min(118, xc + bw - 1)
        cam = -1 if abs((bx0 + bx1) * 0.5 - 64.0) < 36.0 else 0
        rmp = LIMESTONE if idx % 3 == 0 else (SLATE if idx % 3 == 1 else TRAVERTINE)
        # Coping course (`y = 6..9`) + inner cheek face (`y = 10..15`)
        _draw_dressed_block(px, bx0, 6 + cam, bx1, 9 + cam, rmp, seed=1410 + idx, lip_top=True, lip_bot=True, mortar_b=False)
        _draw_dressed_block(px, bx0, 10 + cam, bx1, 15, SLATE, seed=1450 + idx, lip_top=False, lip_bot=True, mortar_b=False, base_bias=-1)
        xc += bw
        idx += 1

    # Recessed central lunar-rune plaque (`x = 58..69, y = 4..14`)
    _draw_dressed_block(px, 57, 4, 70, 14, TRAVERTINE, seed=1499, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
    for y in range(6, 13):
        for x in range(60, 68):
            px[y][x] = SLATE[2]
    # Crisp carved crescent moon + star spark
    glyph = [
        (64, 7, True), (63, 7, False), (62, 8, True), (62, 9, True),
        (62, 10, True), (63, 11, False), (64, 11, True), (65, 9, True),
    ]
    for gx, gy, is_hi in glyph:
        px[gy][gx] = SLATE[0]
        glow[gy][gx] = RUNE_HI if is_hi else RUNE_DIM

    # Sculpted terminal corner bollards (`x = 2..8` left, `119..125` right)
    for bx0, bx1, sd in ((2, 8, 1501), (119, 125, 1502)):
        _draw_dressed_block(px, bx0, 6, bx1, 16, LIMESTONE, seed=sd, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
        _draw_dressed_block(px, bx0 - 1, 3, bx1 + 1, 5, TRAVERTINE, seed=sd + 5, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
        for x in range(bx0, bx1 + 1):
            px[2][x] = TRAVERTINE[6 if x <= (bx0 + bx1) // 2 else 4]

    _moss_cluster(px, 12, 42, 6, 2, 1520)
    _moss_cluster(px, 86, 115, 6, 2, 1521)

    # Bottom contact edge (`y = 16`) gets soft SE shadow instead of harsh line
    for x in range(2, 126):
        if px[15][x][3] > 0:
            px[16][x] = SE_SHADOW
            no_out[16][x] = True
            no_out[15][x] = True

    out = _outline_masked(px, no_out, OUT)
    return out, glow


def build_parapet_south() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """128x18 south (front) stone parapet with coping, 3/4 vertical masonry face, ivy & rune plaque."""
    w, h = 128, 18
    px = make_grid(w, h)
    glow = make_grid(w, h)
    no_out = [[False] * w for _ in range(h)]

    # Coping (`y = 4..7`) + 3/4 vertical masonry face (`y = 8..14`)
    xc = 9
    idx = 0
    while xc < 119:
        bw = 10 + int(h2(idx, 2, 1601) * 4)
        bx0, bx1 = xc, min(118, xc + bw - 1)
        cam = -1 if abs((bx0 + bx1) * 0.5 - 64.0) < 36.0 else 0
        rmp = LIMESTONE if idx % 3 == 0 else (TRAVERTINE if idx % 3 == 1 else SLATE)
        _draw_dressed_block(px, bx0, 4 + cam, bx1, 7 + cam, rmp, seed=1610 + idx, lip_top=True, lip_bot=True, mortar_b=False)
        _draw_dressed_block(px, bx0, 8 + cam, bx1, 11, LIMESTONE if idx % 2 == 0 else SLATE, seed=1640 + idx, lip_top=False, lip_bot=True, mortar_b=True, base_bias=-1)
        _draw_dressed_block(px, bx0, 12, bx1, 14, SLATE, seed=1670 + idx, lip_top=False, lip_bot=True, mortar_b=False, base_bias=-1)
        xc += bw
        idx += 1

    # Central carved lunar-rune plaque on the front coping/face (`x = 59..68, y = 3..12`)
    _draw_dressed_block(px, 58, 3, 69, 12, TRAVERTINE, seed=1699, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
    for y in range(5, 11):
        for x in range(61, 67):
            px[y][x] = SLATE[2]
    for gx, gy, hi in (
        (64, 6, True), (63, 6, False), (62, 7, True), (62, 8, True),
        (63, 9, False), (64, 9, True), (65, 8, True),
    ):
        px[gy][gx] = SLATE[0]
        glow[gy][gx] = RUNE_HI if hi else RUNE_DIM

    # Terminal corner bollards (`x = 2..8` left, `119..125` right)
    for bx0, bx1, sd in ((2, 8, 1701), (119, 125, 1702)):
        _draw_dressed_block(px, bx0, 5, bx1, 15, LIMESTONE, seed=sd, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
        _draw_dressed_block(px, bx0 - 1, 2, bx1 + 1, 4, TRAVERTINE, seed=sd + 5, lip_top=True, lip_bot=True, mortar_r=False, mortar_b=False)
        for x in range(bx0, bx1 + 1):
            px[1][x] = TRAVERTINE[6 if x <= (bx0 + bx1) // 2 else 4]

    _moss_cluster(px, 16, 48, 4, 2, 1720)
    _moss_cluster(px, 80, 112, 4, 2, 1721)
    _draw_ivy(px, 24, 7, 8, 0.35, 1731)
    _draw_ivy(px, 46, 8, 7, -0.25, 1732)
    _draw_ivy(px, 82, 7, 8, 0.25, 1733)
    _draw_ivy(px, 102, 8, 7, -0.35, 1734)

    out = _outline_masked(px, no_out, OUT)
    return out, glow


def build_lantern_post() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """16x24 carved stone wayfarer lantern post with iron cage & amber/turquoise flame."""
    w, h = 16, 24
    px = make_grid(w, h)
    gm = GlowMap(w, h)
    cx, cy = 8, 20

    # Stepped carved stone plinth (`y = 18..21`)
    _draw_dressed_block(px, cx - 4, cy, cx + 4, cy + 1, TRAVERTINE, seed=1801, mortar_r=False, mortar_b=False)
    _draw_dressed_block(px, cx - 3, cy - 2, cx + 3, cy - 1, LIMESTONE, seed=1802, mortar_r=False, mortar_b=False)

    # Chamfered stone shaft (`y = 14..17`) + collar (`y = 13`)
    for y in range(cy - 6, cy - 2):
        px[y][cx - 2] = SLATE[5]
        px[y][cx - 1] = SLATE[4]
        px[y][cx] = SLATE[3]
        px[y][cx + 1] = SLATE[2]
        px[y][cx + 2] = SLATE[1]
    for dx in range(-3, 4):
        px[cy - 7][cx + dx] = TRAVERTINE[6 if dx < 0 else (4 if dx <= 1 else 2)]

    # Wrought-iron cage (`y = 8..12`) + pagoda cap & finial (`y = 5..7`)
    for dx in range(-3, 4):
        px[cy - 8][cx + dx] = IRON[3 if dx <= 0 else 1]
    for y in (cy - 11, cy - 10, cy - 9):
        px[y][cx - 2] = IRON[3]
        px[y][cx + 2] = IRON[1]
        for dx in (-1, 0, 1):
            px[y][cx + dx] = SLATE[0]
    for dx in range(-3, 4):
        px[cy - 12][cx + dx] = IRON[4 if dx < 0 else (3 if dx <= 1 else 1)]
    for dx in range(-2, 3):
        px[cy - 13][cx + dx] = IRON[4 if dx <= 0 else 2]
    px[cy - 14][cx] = IRON[4]

    # Warm-amber + turquoise wayfarer flame + inlaid plinth rune
    gm.emit(px, cx, cy - 9, AMBER_H, AMBER_H, halo=2)
    gm.emit(px, cx, cy - 10, BRIDGE_GOLD, BRIDGE_GOLD, halo=2)
    gm.emit(px, cx + 1, cy - 9, AMBER_M, AMBER_M, halo=1)
    gm.emit(px, cx - 1, cy - 10, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=2)
    gm.emit(px, cx - 1, cy - 11, BRIDGE_RUNE_DIM, BRIDGE_RUNE_HOT, halo=1)
    px[cy - 1][cx] = SLATE[0]
    gm.emit(px, cx, cy - 1, BRIDGE_TEAL, BRIDGE_TEAL_L, halo=1)

    no_out = [[False] * w for _ in range(h)]
    out = _outline_masked(px, no_out, OUT)
    return out, gm.finish()


# ---------------------------------------------------------------------------
# Atlas Assembly & 4x QA Preview
# ---------------------------------------------------------------------------
def _blit(
    dst: list[list[tuple[int, int, int, int]]],
    src: list[list[tuple[int, int, int, int]]],
    ox: int,
    oy: int,
    alpha_blend: bool = False,
) -> None:
    dh, dw = len(dst), len(dst[0])
    for y, row in enumerate(src):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x, c in enumerate(row):
            dx = ox + x
            if not (0 <= dx < dw) or c[3] == 0:
                continue
            dst[dy][dx] = blend_over(dst[dy][dx], c) if alpha_blend else c


def _tint_night(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    out = make_grid(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(6, int(c[0] * 0.44)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
    return out


def _add_glow(
    dst: list[list[tuple[int, int, int, int]]],
    glow: list[list[tuple[int, int, int, int]]],
    ox: int,
    oy: int,
) -> None:
    dh, dw = len(dst), len(dst[0])
    for y, row in enumerate(glow):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x, gc in enumerate(row):
            dx = ox + x
            if not (0 <= dx < dw) or gc[3] == 0:
                continue
            dc = dst[dy][dx]
            f = gc[3] / 255.0
            dst[dy][dx] = (
                min(255, int(dc[0] * (1.0 - 0.50 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.50 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.50 * f) + gc[2] * f * 1.35)),
                255,
            )


def build_4x_atlas(regions: dict[str, tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]]) -> list[list[tuple[int, int, int, int]]]:
    """Builds 362x248 1x QA sheet (2x2 panels: Assembled Day/Night + Modular Day/Night) -> 1448x992 (4x)."""
    lw, lh = 362, 248
    img = [[OUT] * lw for _ in range(lh)]

    # Panel bounds: TL (0..175, 0..121), BL (0..175, 126..247), TR (180..361, 0..121), BR (180..361, 126..247)
    def paint_assembled_bg(ox: int, oy: int, pw: int, ph: int, night: bool) -> None:
        meadow_a = hexc("172830") if night else hexc("3e7d56")
        meadow_b = hexc("1c3138") if night else hexc("55985f")
        bank = hexc("1e2c38") if night else hexc("9b8e76")
        water_a = hexc("102236") if night else hexc("2a6e68")
        water_b = hexc("142c42") if night else hexc("34847a")
        for y in range(ph):
            for x in range(pw):
                if 48 <= x < 128:
                    ripple = ((x // 3 + y * 2) % 11 == 0) and (y % 4 == 0)
                    img[oy + y][ox + x] = water_b if ripple else water_a
                elif 45 <= x < 48 or 128 <= x < 131:
                    img[oy + y][ox + x] = bank
                else:
                    stripe = ((x // 4 + y // 3) % 5 == 0)
                    img[oy + y][ox + x] = meadow_b if stripe else meadow_a

    def composite_assembled(ox: int, oy: int, night: bool) -> None:
        cx, cy = ox + 88, oy + 52
        order = [
            ("deck_base", 0, 0),
            ("pier_left", -26, 36),
            ("pier_right", 26, 36),
            ("parapet_north", 0, -13),
            ("lantern_post", -32, -13),
            ("parapet_south", 0, 16),
        ]
        for key, mx, my in order:
            base, gl = regions[key]
            ax, ay = BRIDGE_RECTS[key]["anchor"]
            px_draw = _tint_night(base) if night else base
            _blit(img, px_draw, cx + mx - ax, cy + my - ay, alpha_blend=True)
            if night:
                _add_glow(img, gl, cx + mx - ax, cy + my - ay)

    # Top-Left & Bottom-Left: Assembled Day & Night
    paint_assembled_bg(0, 0, 176, 122, night=False)
    composite_assembled(0, 0, night=False)
    paint_assembled_bg(0, 126, 176, 122, night=True)
    composite_assembled(0, 126, night=True)

    # Top-Right & Bottom-Right: Modular Regions Day & Night
    for night, oy in ((False, 0), (True, 126)):
        bg_meadow = hexc("14192c") if night else hexc("3e7d56")
        bg_water = hexc("14192c") if night else hexc("28545c")
        for y in range(122):
            for x in range(182):
                in_pier = (x >= 132 and y >= 60)
                img[oy + y][180 + x] = bg_water if in_pier else bg_meadow
        placements = [
            ("deck_base", 184, oy + 4),
            ("parapet_north", 184, oy + 64),
            ("parapet_south", 184, oy + 86),
            ("pier_left", 316, oy + 64),
            ("pier_right", 338, oy + 64),
            ("lantern_post", 316, oy + 94),
        ]
        for key, px_x, px_y in placements:
            base, gl = regions[key]
            _blit(img, _tint_night(base) if night else base, px_x, px_y, alpha_blend=True)
            if night:
                _add_glow(img, gl, px_x, px_y)

    scale = 4
    out = [[CLEAR] * (lw * scale) for _ in range(lh * scale)]
    for y in range(lh):
        for sy in range(scale):
            dst_row = out[y * scale + sy]
            for x in range(lw):
                c = img[y][x]
                bx = x * scale
                for sx in range(scale):
                    dst_row[bx + sx] = c
    return out


def main() -> None:
    regions = {
        "deck_base": build_deck_base(),
        "pier_left": build_river_pier(is_left=True),
        "pier_right": build_river_pier(is_left=False),
        "parapet_north": build_parapet_north(),
        "parapet_south": build_parapet_south(),
        "lantern_post": build_lantern_post(),
    }

    sheet = make_grid(SHEET_W, SHEET_H)
    glow_sheet = make_grid(SHEET_W, SHEET_H)
    for key, (base, gl) in regions.items():
        rx, ry, rw, rh = BRIDGE_RECTS[key]["rect"]
        assert len(base) == rh and len(base[0]) == rw, f"{key} size mismatch"
        assert len(gl) == rh and len(gl[0]) == rw, f"{key} glow size mismatch"
        _blit(sheet, base, rx, ry, alpha_blend=False)
        _blit(glow_sheet, gl, rx, ry, alpha_blend=False)

    atlas = build_4x_atlas(regions)

    verify_no_black("water_bridge.png", sheet)
    verify_no_black("water_bridge_glow.png", glow_sheet)
    verify_no_black("water_bridge_atlas_4x.png", atlas)

    props_dir = ROOT / "props"
    atlas_path = ROOT.parent / "docs" / "img" / "water_bridge_atlas_4x.png"
    write_png(props_dir / "water_bridge.png", SHEET_W, SHEET_H, sheet)
    write_png(props_dir / "water_bridge_glow.png", SHEET_W, SHEET_H, glow_sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    print(f"Wrote {props_dir / 'water_bridge.png'} ({SHEET_W}x{SHEET_H}), _glow.png, and {atlas_path} ({len(atlas[0])}x{len(atlas)})")


if __name__ == "__main__":
    main()
