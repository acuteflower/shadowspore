#!/usr/bin/env python3
"""Procedural pixel-art generator for Square -1 (Forest Brook) & Square -2 (Coastal Biome).

Two-tier aligned sprite sheet (192x164 px):
  - Rows 0..3: 24 cells of 32x32 px (6 cols x 4 rows)
  - Row 4:     4 hero cells of 48x36 px (4 cols x 1 row)
  `6 * 32 = 4 * 48 = 192 px` width alignment.

Rules enforced:
  - Strictly ZERO `#000000` (0, 0, 0, a>0) pixels across base, glow, and 4x atlas.
  - Top-left NW -> SE lighting (`-0.55*nx - 0.80*ny`), cool shadows, 4-connected pixel clusters.
  - Emergent props use 1 px `#1b1a2e` / dark material outlines; `submerged_pebbles_0` has NO dark outline.

Outputs:
  assets/tiles/coastal_props.png       192x164 RGBA8 sprite sheet
  assets/tiles/coastal_props_glow.png  192x164 unlit night glow mask
  docs/img/coastal_biome_atlas_4x.png  880x1504 (4x nearest) Day + Night QA atlas
"""
from __future__ import annotations

import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import TRAVERTINE, blend_over, h2, make_grid  # noqa: E402

SHEET_W = 192
SHEET_H = 164

# ---------------------------------------------------------------------------
# Exported Region Metadata (consumed by M5 grass_lab.gd)
# ---------------------------------------------------------------------------
COASTAL_PROPS_RECTS = {
    # Row 0 (y = 0, 32x32)
    "lily_cluster_0": {"id": 0, "biome": "sq-1", "rect": (0, 0, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "lily_cluster_1": {"id": 1, "biome": "sq-1", "rect": (32, 0, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "lily_cluster_2": {"id": 2, "biome": "sq-1", "rect": (64, 0, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "brook_reeds_0": {"id": 3, "biome": "sq-1", "rect": (96, 0, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "brook_reeds_1": {"id": 4, "biome": "sq-1", "rect": (128, 0, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "brook_reeds_2": {"id": 5, "biome": "sq-1", "rect": (160, 0, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    # Row 1 (y = 32, 32x32)
    "bank_root_0": {"id": 6, "biome": "sq-1", "rect": (0, 32, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "bank_root_1": {"id": 7, "biome": "sq-1", "rect": (32, 32, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "brook_boulder_0": {"id": 8, "biome": "sq-1", "rect": (64, 32, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "brook_boulder_1": {"id": 9, "biome": "sq-1", "rect": (96, 32, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "submerged_pebbles_0": {"id": 10, "biome": "sq-1", "rect": (128, 32, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "driftwood_0": {"id": 11, "biome": "sq-2", "rect": (160, 32, 32, 32), "anchor": "bottom_center", "foot": (16, 26), "offset": (-16, -26)},
    # Row 2 (y = 64, 32x32)
    "driftwood_1": {"id": 12, "biome": "sq-2", "rect": (0, 64, 32, 32), "anchor": "bottom_center", "foot": (16, 26), "offset": (-16, -26)},
    "spulsaum_shells_0": {"id": 13, "biome": "sq-2", "rect": (32, 64, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "spulsaum_shells_1": {"id": 14, "biome": "sq-2", "rect": (64, 64, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "spulsaum_starfish_0": {"id": 15, "biome": "sq-2", "rect": (96, 64, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "spulsaum_kelp_0": {"id": 16, "biome": "sq-2", "rect": (128, 64, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "spulsaum_kelp_1": {"id": 17, "biome": "sq-2", "rect": (160, 64, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    # Row 3 (y = 96, 32x32)
    "beach_pebbles_0": {"id": 18, "biome": "sq-2", "rect": (0, 96, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "beach_pebbles_1": {"id": 19, "biome": "sq-2", "rect": (32, 96, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    "dune_oats_0": {"id": 20, "biome": "sq-2", "rect": (64, 96, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "dune_oats_1": {"id": 21, "biome": "sq-2", "rect": (96, 96, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "dune_oats_2": {"id": 22, "biome": "sq-2", "rect": (128, 96, 32, 32), "anchor": "bottom_center", "foot": (16, 28), "offset": (-16, -28)},
    "spulsaum_mixed_0": {"id": 23, "biome": "sq-2", "rect": (160, 96, 32, 32), "anchor": "center", "foot": (16, 16), "offset": (-16, -16)},
    # Row 4 (y = 128, 48x36 hero props)
    "tidepool_rock_0": {"id": 24, "biome": "sq-2", "rect": (0, 128, 48, 36), "anchor": "bottom_center", "foot": (24, 31), "offset": (-24, -31)},
    "tidepool_rock_1": {"id": 25, "biome": "sq-2", "rect": (48, 128, 48, 36), "anchor": "bottom_center", "foot": (24, 31), "offset": (-24, -31)},
    "tidepool_rock_2": {"id": 26, "biome": "sq-2", "rect": (96, 128, 48, 36), "anchor": "bottom_center", "foot": (24, 31), "offset": (-24, -31)},
    "driftwood_hero_0": {"id": 27, "biome": "sq-2", "rect": (144, 128, 48, 36), "anchor": "bottom_center", "foot": (24, 30), "offset": (-24, -30)},
}

# ---------------------------------------------------------------------------
# Verified Palettes
# ---------------------------------------------------------------------------
INK = hexc("1b1a2e")
AO = (16, 14, 18, 120)
AO_SOFT = (16, 14, 18, 65)
WATER_DARK = (20, 40, 46, 120)
RIPPLE = (110, 214, 200, 110)

GREEN = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
G_EMERALD = [hexc(c) for c in ("1b3a36", "254e42", "336b4e", "458657", "60a360", "87c46f", "b3e08f")]
MOSS = [hexc(c) for c in ("193638", "244d45", "346e52", "4d8f5d", "76b86e", "a2d684")]
CATTAIL, CATTAIL_L = hexc("6b4a3a"), hexc("94694c")

BUD_SH = hexc("9c5c88")
BUD_MID = hexc("b876a2")
PINK = hexc("e8a9d0")
CREAM = hexc("f7f1de")
GOLD = hexc("f0c862")

SEED_D = hexc("8f8e58")
SEED_M = hexc("beb978")
SEED_L = hexc("e6dea0")

SEA = [hexc(c) for c in ("1f5a5a", "2a7a74", "3f9a8c", "62bcac", "a4fff0")]
BARK = [hexc(c) for c in ("221817", "382721", "523a2d", "6f523e", "8f6e52")]
DRIFTWOOD = [hexc(c) for c in ("302c3c", "4c4758", "6e6878", "96909e", "c0bac6", "d6c9ae")]
ROCK = [hexc(c) for c in ("262936", "3f4556", "5d6575", "7f8896", "a8b1bc")]
STONE = [hexc(c) for c in ("1e1c30", "2a283e", "393752", "4a4866", "5d5b7a", "727090", "908eac", "b8b5d2")]
WET_STONE = [hexc(c) for c in ("182034", "223048", "304560", "46607c")]

POOL_WATER = [hexc(c) for c in ("183848", "2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
FOAM = hexc("cfe9e0")
FOAM_L = hexc("e8fcfc")

SAND_PEBBLE = [hexc(c) for c in ("4e3834", "725242", "9c7656", "c49e72", "e4c898")]
SHELL = [hexc(c) for c in ("7a6868", "9e8c88", "cbbab0", "eadfd2", "fbf5ea")]
SHELL_OUTLINE = hexc("68524c")
SHELL_OUTLINE_TOP = hexc("8a7268")
STARFISH = [hexc(c) for c in ("6a3832", "8e4c3e", "b46a50", "d49278", "eab89c")]
MARRAM = [hexc(c) for c in ("3b453a", "53634f", "758565", "9fa676", "c8be8a", "e6dcab")]
DRIFT_OUTLINE = hexc("342d38")
REED_OUTLINE = hexc("193230")

# Night glow accents (alpha <= 165, 1 px soft halo added cleanly)
GLOW_BUD = (232, 169, 208, 138)
GLOW_BUD_CORE = (247, 241, 222, 160)
GLOW_TEAL = (60, 192, 198, 135)
GLOW_TEAL_HI = (120, 244, 230, 162)
GLOW_VIO = (148, 104, 238, 132)
GLOW_VIO_HI = (203, 170, 255, 155)
GLOW_DEW = (152, 232, 224, 96)


def verify_no_black(name: str, px: list[list[tuple[int, int, int, int]]]) -> None:
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} contains forbidden #000000 pixel at ({x}, {y})")


class SpriteCell:
    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.px = make_grid(w, h)
        self.gl = make_grid(w, h)
        self.under = make_grid(w, h)

    def put(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def uput(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.under[y][x] = blend_over(self.under[y][x], c)

    def gput(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.gl[y][x] = c

    def outline(
        self,
        color: tuple[int, int, int, int] = INK,
        top_color: tuple[int, int, int, int] | None = None,
        skip_bottom_from_y: int = 999,
    ) -> None:
        src = [row[:] for row in self.px]
        tcol = top_color if top_color is not None else color
        for y in range(self.h):
            if y >= skip_bottom_from_y:
                continue
            for x in range(self.w):
                if src[y][x][3] > 0:
                    continue
                hit = False
                has_below = 0 <= y + 1 < self.h and src[y + 1][x][3] >= 200
                has_right = 0 <= x + 1 < self.w and src[y][x + 1][3] >= 200
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx][3] >= 200:
                        hit = True
                        break
                if hit:
                    self.px[y][x] = tcol if (has_below or has_right) and not (y > 0 and src[y - 1][x][3] >= 200) else color

    def add_glow_halo(self) -> None:
        src = [row[:] for row in self.gl]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x][3] > 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx][3] > 0:
                        c = src[ny][nx]
                        self.gl[y][x] = (c[0], c[1], c[2], 62)
                        break

    def finish(self) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
        self.add_glow_halo()
        out = make_grid(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out[y][x] = blend_over(self.under[y][x], self.px[y][x])
        return out, self.gl


def _paint_waterline(c: SpriteCell, x0: int, x1: int, y: int) -> None:
    for x in range(x0, x1 + 1):
        c.uput(x, y, WATER_DARK)
    c.uput(x0 - 2, y + 1, RIPPLE)
    c.uput(x0 - 1, y + 1, RIPPLE)
    c.uput(x1 + 1, y + 1, RIPPLE)
    c.uput(x1 + 2, y + 1, RIPPLE)


def _draw_pad(c: SpriteCell, cx: int, cy: int, rx: float, ry: float, notch_right: bool = True) -> None:
    for x in range(int(cx - rx), int(cx + rx) + 1):
        c.uput(x, cy + int(round(ry)) + 1, WATER_DARK)
    c.uput(int(cx - rx) - 1, cy + int(round(ry)) + 1, RIPPLE)
    c.uput(int(cx + rx) + 1, cy + int(round(ry)) + 1, RIPPLE)
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            if nx * nx + ny * ny > 1.0:
                continue
            if notch_right and x > cx + rx * 0.25 and abs(y - cy) <= 1:
                continue
            if not notch_right and x < cx - rx * 0.25 and abs(y - cy) <= 1:
                continue
            lit = -0.55 * nx - 0.80 * ny
            idx = 2 + (1 if lit > 0.15 else 0) + (1 if lit > 0.58 else 0) - (1 if lit < -0.35 else 0)
            c.put(x, y, GREEN[max(1, min(4, idx))])
    # Crisp vein accent
    c.put(cx - 1, cy, GREEN[1])
    c.put(cx, cy, GREEN[1])


def _draw_pink_bud(c: SpriteCell, x: int, y: int, open_bloom: bool = False) -> None:
    if open_bloom:
        for dx in range(-2, 3):
            c.put(x + dx, y, BUD_MID if abs(dx) == 2 else PINK)
            c.gput(x + dx, y, GLOW_BUD)
        for dx in range(-2, 3):
            c.put(x + dx, y - 1, PINK if dx != 0 else CREAM)
            c.gput(x + dx, y - 1, GLOW_BUD_CORE if dx == 0 else GLOW_BUD)
        c.put(x - 1, y - 2, CREAM)
        c.put(x + 1, y - 2, PINK)
        c.put(x, y, GOLD)
        c.gput(x, y, GLOW_BUD_CORE)
    else:
        c.put(x, y + 1, GREEN[2])
        c.put(x - 1, y, BUD_MID)
        c.put(x, y, PINK)
        c.put(x + 1, y, BUD_SH)
        c.put(x, y - 1, CREAM)
        c.put(x - 1, y - 1, PINK)
        c.gput(x, y, GLOW_BUD)
        c.gput(x, y - 1, GLOW_BUD_CORE)


def _draw_blade_4conn(c: SpriteCell, x0: int, y_foot: int, h: int, lean: float, ramp: list[tuple[int, int, int, int]], thick: bool = False) -> tuple[int, int]:
    """Draws a smooth 4-connected curved blade (abs(bx - prev_x) <= 1)."""
    prev_x = x0
    tip = (x0, y_foot)
    for i in range(h + 1):
        t = i / max(1, h)
        target_x = int(round(x0 + lean * (t * t) * h * 0.45))
        if target_x > prev_x + 1:
            bx = prev_x + 1
        elif target_x < prev_x - 1:
            bx = prev_x - 1
        else:
            bx = target_x
        by = y_foot - i
        idx = min(len(ramp) - 1, int(t * len(ramp)))
        c.put(bx, by, ramp[idx])
        if thick and t < 0.72:
            c.put(bx + 1, by, ramp[max(0, idx - 1)])
        prev_x = bx
        tip = (bx, by)
    return tip


def _draw_ellipse_rock(
    c: SpriteCell,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    ramp: list[tuple[int, int, int, int]],
    moss_cap: bool = False,
    wet_bot: bool = False,
    alpha_limit: int = 255,
    ao_under: bool = True,
) -> None:
    for y in range(int(cy - ry) - 1, int(cy + ry) + 3):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            d = nx * nx + ny * ny
            if d <= 1.0:
                lit = -0.55 * nx - 0.80 * ny
                if moss_cap and ny < -0.10 and nx < 0.55 and d < 0.86:
                    col = MOSS[4] if lit > 0.45 else (MOSS[3] if lit > 0.05 else MOSS[2])
                elif wet_bot and ny > 0.40:
                    col = WET_STONE[2 if lit > 0.0 else 1]
                else:
                    idx = 2 + (1 if lit > 0.15 else 0) + (1 if lit > 0.58 else 0) - (1 if lit < -0.25 else 0) - (1 if lit < -0.62 else 0)
                    col = ramp[max(0, min(len(ramp) - 1, idx))]
                if alpha_limit < 255:
                    col = (col[0], col[1], col[2], alpha_limit)
                c.put(x, y, col)
            elif ao_under and d <= 1.32 and ny > 0.20:
                c.uput(x, y, AO_SOFT)


# ---------------------------------------------------------------------------
# All 28 Prop Generators
# ---------------------------------------------------------------------------
def build_prop(prop_id: int) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    if prop_id < 24:
        c = SpriteCell(32, 32)
    else:
        c = SpriteCell(48, 36)

    # ---- 0..2: Water Lilies (pink buds + glow) ----
    if prop_id == 0:
        _draw_pad(c, 15, 17, 7.2, 3.6, notch_right=True)
        _draw_pad(c, 22, 13, 4.5, 2.5, notch_right=False)
        _draw_pink_bud(c, 13, 14, open_bloom=False)
        c.outline(INK)

    elif prop_id == 1:
        _draw_pad(c, 16, 17, 7.8, 3.8, notch_right=True)
        _draw_pad(c, 9, 13, 4.4, 2.4, notch_right=True)
        _draw_pink_bud(c, 16, 14, open_bloom=True)
        _draw_pink_bud(c, 9, 11, open_bloom=False)
        c.outline(INK)

    elif prop_id == 2:
        _draw_pad(c, 12, 18, 6.2, 3.2, notch_right=True)
        _draw_pad(c, 21, 15, 5.5, 2.8, notch_right=False)
        _draw_pink_bud(c, 11, 15, open_bloom=False)
        _draw_pink_bud(c, 20, 12, open_bloom=False)
        c.gput(16, 17, GLOW_DEW)
        c.outline(INK)

    # ---- 3..5: Brook Reeds & Cattails (staggered natural water-entry stems, no flat bottom bar) ----
    elif prop_id in (3, 4, 5):
        stems = [
            [(10, 26, 12, -0.7, False), (13, 28, 18, -0.3, True), (16, 27, 15, 0.2, False), (19, 28, 19, 0.5, False), (22, 26, 11, 0.8, False)],
            [(9, 26, 14, -0.6, False), (12, 28, 20, -0.2, True), (16, 27, 13, 0.1, False), (19, 28, 19, 0.4, True), (23, 26, 12, 0.7, False)],
            [(10, 26, 11, -0.8, False), (13, 27, 16, -0.4, False), (16, 28, 18, 0.1, False), (19, 27, 14, 0.4, False), (22, 26, 11, 0.8, False)],
        ][prop_id - 3]
        for idx, (sx, y_foot, sh, ln, has_cat) in enumerate(stems):
            c.uput(sx - 1, y_foot + 1, WATER_DARK)
            c.uput(sx, y_foot + 1, WATER_DARK)
            c.uput(sx + 1, y_foot + 1, RIPPLE if idx % 2 == 0 else WATER_DARK)
            tx, ty = _draw_blade_4conn(c, sx, y_foot, sh, ln, GREEN[1:5], thick=(idx % 2 == 1))
            if has_cat:
                for ky in range(1, 5):
                    c.put(tx, ty + ky, CATTAIL)
                    c.put(tx + 1, ty + ky, CATTAIL_L if ky <= 2 else CATTAIL)
                c.put(tx, ty, GREEN[4])
        if prop_id == 4:
            c.gput(15, 11, GLOW_TEAL_HI)
            c.gput(21, 13, GLOW_TEAL)
        c.outline(REED_OUTLINE, GREEN[0], skip_bottom_from_y=28)

    # ---- 6..7: Moss-Draped Woodland Bank Roots (grounded into mossy bank, slender roots dipping into water) ----
    elif prop_id in (6, 7):
        dark_bark = [hexc("1f1818"), hexc("32241f"), hexc("463329"), hexc("5c4436"), hexc("735846")]
        moss_blobs = (
            [(10.0, 21.5, 5.2, 3.2), (14.5, 20.8, 4.0, 2.6)]
            if prop_id == 6
            else [(10.5, 21.0, 4.8, 3.0), (15.0, 22.0, 3.8, 2.5)]
        )
        tendrils = (
            [(9.0, 22.0, 20.0, 27.0, 2.2, 1.4), (13.0, 21.5, 24.0, 26.0, 2.6, 1.2), (11.0, 23.0, 16.0, 28.0, 1.2, 1.0)]
            if prop_id == 6
            else [(9.5, 21.5, 22.0, 27.0, 2.5, 1.4), (13.5, 22.0, 25.0, 25.5, 2.0, 1.1), (10.5, 23.0, 17.5, 28.0, 1.4, 1.0)]
        )
        for x0, y0, x1, y1, arch, thick in tendrils:
            steps = 22
            for i in range(steps + 1):
                t = i / steps
                px = x0 + (x1 - x0) * t
                py = y0 + (y1 - y0) * t - math.sin(t * math.pi) * arch
                r = thick * (1.0 - 0.42 * t)
                ix, iy = int(round(px)), int(round(py))
                for dy in range(-1, 2):
                    for dx in range(-1, 2):
                        if dx * dx + dy * dy <= max(0.65, r * r):
                            col = dark_bark[3] if dy < 0 else (dark_bark[2] if dy == 0 else dark_bark[1])
                            c.put(ix + dx, iy + dy, col)
        for mcx, mcy, mrx, mry in moss_blobs:
            for y in range(int(mcy - mry) - 1, int(mcy + mry) + 2):
                for x in range(int(mcx - mrx) - 1, int(mcx + mrx) + 2):
                    nx = (x - mcx) / mrx
                    ny = (y - mcy) / mry
                    if nx * nx + ny * ny <= 1.0:
                        lit = -0.55 * nx - 0.80 * ny
                        mc = MOSS[4] if lit > 0.38 else (MOSS[3] if lit > -0.08 else MOSS[2])
                        c.put(x, y, mc)
        c.outline(dark_bark[0], MOSS[1], skip_bottom_from_y=25)

    # ---- 8..9: Brook Boulders ----
    elif prop_id == 8:
        _draw_ellipse_rock(c, 15.0, 22.5, 7.5, 5.2, ROCK, moss_cap=True, wet_bot=True, ao_under=False)
        _draw_ellipse_rock(c, 22.0, 24.8, 3.6, 2.6, ROCK, moss_cap=False, wet_bot=True, ao_under=False)
        c.outline(INK, ROCK[1], skip_bottom_from_y=27)

    elif prop_id == 9:
        _draw_ellipse_rock(c, 12.0, 22.8, 6.2, 4.4, ROCK, moss_cap=True, wet_bot=True, ao_under=False)
        _draw_ellipse_rock(c, 21.0, 23.8, 5.2, 3.8, ROCK, moss_cap=True, wet_bot=True, ao_under=False)
        c.outline(INK, ROCK[1], skip_bottom_from_y=27)

    # ---- 10: Submerged Riverbed Pebbles (NO DARK OUTLINE!) ----
    elif prop_id == 10:
        for px_c, py_c, rx, ry, rmp in (
            (10.0, 14.0, 4.2, 2.6, SEA),
            (18.0, 12.5, 3.5, 2.2, SEA),
            (15.0, 18.0, 4.8, 2.8, [hexc("234a4a"), hexc("356662"), hexc("52887e"), hexc("78aba0"), hexc("a4ccc0")]),
            (22.0, 18.5, 3.0, 2.0, SEA),
            (8.5, 19.0, 2.8, 1.8, SEA),
        ):
            _draw_ellipse_rock(c, px_c, py_c, rx, ry, rmp, moss_cap=False, wet_bot=False, alpha_limit=218, ao_under=False)
        # No outline() call here intentionally!

    # ---- 11..12: Bleached Driftwood (curved sun-bleached log settled in sand) ----
    elif prop_id in (11, 12):
        length = 22 if prop_id == 11 else 19
        x0 = 16 - length // 2
        tilt = -0.18 if prop_id == 11 else 0.20
        for i in range(length):
            t = i / max(1, length - 1)
            x = x0 + i
            bend = math.sin(t * math.pi) * (-1.6 if prop_id == 11 else 1.3)
            yc = 23 + round(tilt * (i - length / 2) + bend)
            rad = 1.9 * math.sin(0.18 + t * (math.pi - 0.36)) + 0.55
            for dy in range(-2, 3):
                if abs(dy) > rad:
                    continue
                ny = dy / max(1.0, rad)
                tone = 5 if (ny < -0.40 and i % 4 in (1, 2)) else (4 if ny < 0.0 else (3 if ny < 0.45 else 2))
                if abs(ny) < 0.25 and i % 6 in (2, 3):
                    tone = 1  # longitudinal grain fissure
                c.put(x, yc + dy, DRIFTWOOD[tone])
            c.uput(x, yc + int(round(rad)) + 1, AO_SOFT)
        # Diagonal organic branch fork (never a 90-degree vertical peg!)
        bx = x0 + (6 if prop_id == 11 else 13)
        by = 22 + round(tilt * (bx - 16))
        dir_x = -1 if prop_id == 11 else 1
        for k in range(1, 5):
            sx = bx + dir_x * k
            sy = by - (k * 2) // 3
            c.put(sx, sy, DRIFTWOOD[4 if k >= 3 else 3])
            if k <= 2:
                c.put(sx, sy + 1, DRIFTWOOD[2])
        c.outline(DRIFT_OUTLINE, DRIFTWOOD[1])

    # ---- 13..14: Spülsaum Seashells (delicate natural scale + warm sel-out, no sticker border!) ----
    elif prop_id == 13:
        # Small fan-ribbed scallop shell (7x5 px, left) + tiny rosy spiral shell (4x4 px, right)
        for dy in range(4):
            y = 13 + dy
            hw = 2 if dy in (0, 1) else (1 if dy == 2 else 0)
            for dx in range(-hw, hw + 1):
                is_rib = (dy in (1, 2)) and (abs(dx) == 1)
                col = SHELL[4] if (dy == 0 and dx <= 0) else (SHELL[2] if is_rib else SHELL[3])
                if dy == 3:
                    col = SHELL[2]
                c.put(12 + dx, y, col)
                if dy >= 2:
                    c.uput(12 + dx, y + 1, AO_SOFT)
        # Tiny rosy spiral shell on right
        for dx, dy, col in (
            (0, 0, CREAM), (1, 0, PINK),
            (-1, 1, PINK), (0, 1, BUD_MID), (1, 1, BUD_SH),
            (0, 2, SHELL[1]),
        ):
            c.put(20 + dx, 16 + dy, col)
            c.uput(20 + dx, 17 + dy, AO_SOFT)
        c.outline(SHELL_OUTLINE, SHELL_OUTLINE_TOP)

    elif prop_id == 14:
        # Delicate clam shell (5x4 px, left) + slender spiral whelk (5x4 px, right) + tiny pearl chip
        for dy in range(4):
            y = 15 + dy
            hw = 2 if dy in (1, 2) else 1
            for dx in range(-hw, hw + 1):
                col = SHELL[4] if (dy <= 1 and dx <= 0) else (SHELL[3] if dy <= 2 else SHELL[2])
                c.put(11 + dx, y, col)
                if dy >= 2:
                    c.uput(11 + dx, y + 1, AO_SOFT)
        for dx, dy, col in (
            (2, -2, CREAM),
            (1, -1, SHELL[4]), (2, -1, SHELL[2]),
            (0, 0, PINK), (1, 0, BUD_MID),
            (-1, 1, SHELL[3]), (0, 1, BUD_SH),
        ):
            c.put(18 + dx, 15 + dy, col)
            c.uput(18 + dx, 16 + dy, AO_SOFT)
        c.put(23, 18, SHELL[4])
        c.put(24, 18, SHELL[2])
        c.outline(SHELL_OUTLINE, SHELL_OUTLINE_TOP)

    # ---- 15: Spülsaum Starfish (delicate 9x8 px warm terracotta sea star) ----
    elif prop_id == 15:
        cx, cy = 15.5, 16.0
        for y in range(11, 21):
            for x in range(10, 22):
                dx, dy = x - cx, (y - cy) * 1.18
                ang = math.atan2(dy, dx)
                r = math.hypot(dx, dy)
                arm = 1.7 + 2.7 * (max(0.0, math.cos(5.0 * (ang - 0.3))) ** 1.8)
                if r <= arm:
                    lit = -0.55 * (dx / 4.5) - 0.80 * (dy / 4.5)
                    col = STARFISH[4] if r < 1.2 else (STARFISH[3] if lit > 0.15 else (STARFISH[2] if lit > -0.25 else STARFISH[1]))
                    c.put(x, y, col)
                elif r <= arm + 1.1 and dy > 0:
                    c.uput(x, y, AO_SOFT)
        c.outline(STARFISH[0], STARFISH[1])

    # ---- 16..17: Spülsaum Kelp Wrack (soft wet edges + faint plankton glow) ----
    elif prop_id in (16, 17):
        strands = [
            (7, 15, 17, 1.2, 0.3),
            (9, 18, 15, -1.0, 1.4),
            (11, 13, 13, 0.9, 2.2),
        ] if prop_id == 16 else [
            (8, 17, 16, -1.1, 0.8),
            (10, 14, 15, 1.0, 1.9),
        ]
        for x0, y0, length, amp, ph in strands:
            for k in range(length):
                x = x0 + k
                y = y0 + int(round(math.sin(k * 0.45 + ph) * amp))
                c.put(x, y, SEA[1])
                c.put(x, y - 1, SEA[2] if k % 3 else SEA[3])
                c.uput(x, y + 1, AO_SOFT)
                if k in (4, 10):
                    c.put(x, y - 1, SEA[3])
                    if k == 4:
                        c.gput(x, y - 1, GLOW_TEAL_HI)
                if prop_id == 17 and k in (6, 12):
                    # Bladder-wrack kelp bulb
                    c.put(x, y - 2, SEA[3])
                    c.put(x + 1, y - 2, SEA[2])
                    if k == 12:
                        c.gput(x, y - 2, GLOW_TEAL)
        if prop_id == 16:
            c.gput(19, 17, GLOW_TEAL)

    # ---- 18..19: Beach Pebbles ----
    elif prop_id == 18:
        for px_c, py_c, rx, ry in ((11.5, 16.0, 3.0, 1.9), (17.5, 14.8, 2.3, 1.6), (18.5, 18.2, 2.7, 1.7), (13.0, 19.2, 1.9, 1.3)):
            _draw_ellipse_rock(c, px_c, py_c, rx, ry, SAND_PEBBLE, ao_under=True)
        c.outline(SAND_PEBBLE[0], SAND_PEBBLE[1])

    elif prop_id == 19:
        for px_c, py_c, rx, ry in ((12.5, 15.5, 3.1, 2.0), (18.5, 17.0, 2.8, 1.8), (15.0, 19.2, 2.1, 1.4)):
            _draw_ellipse_rock(c, px_c, py_c, rx, ry, TRAVERTINE[1:6], ao_under=True)
        c.outline(TRAVERTINE[0], TRAVERTINE[2])

    # ---- 20..22: Coastal Dune Oat Grass (`Strandhafer` in silvery sea-sage & sun-bleached wheat!) ----
    elif prop_id in (20, 21, 22):
        blades = [
            [(10, 26, 12, -1.0, False), (13, 28, 18, -0.45, True), (16, 28, 20, 0.30, True), (19, 27, 15, 0.75, False), (22, 26, 11, 1.05, False)],
            [(10, 26, 11, -0.35, False), (13, 27, 17, 0.30, True), (16, 28, 20, 0.70, True), (19, 28, 16, 1.00, True), (22, 26, 12, 1.20, False)],
            [(9, 26, 11, -0.85, False), (12, 27, 16, -0.40, True), (15, 28, 20, 0.15, True), (18, 27, 17, 0.55, True), (21, 26, 12, 0.85, False)],
        ][prop_id - 20]
        for idx, (sx, y_foot, sh, ln, has_plume) in enumerate(blades):
            tx, ty = _draw_blade_4conn(c, sx, y_foot, sh, ln, MARRAM[2:6], thick=True)
            if has_plume:
                d_sign = 1 if ln >= 0 else -1
                c.put(tx, ty - 1, MARRAM[5])
                c.put(tx + d_sign, ty, MARRAM[5])
                c.put(tx + d_sign, ty + 1, MARRAM[4])
                c.put(tx + 2 * d_sign, ty + 1, MARRAM[3])
        if prop_id == 20:
            c.gput(15, 7, GLOW_DEW)
            c.gput(19, 10, GLOW_DEW)
        elif prop_id == 21:
            c.gput(18, 9, GLOW_DEW)
        # Soft outline-free stalks (like LivingGrass!) so thin dune grass blades look airy and natural on bright sand!

    # ---- 23: Spülsaum Mixed (kelp + shell + pebbles) ----
    elif prop_id == 23:
        for k in range(14):
            x = 8 + k
            y = 16 + int(round(math.sin(k * 0.5) * 1.4))
            c.put(x, y, SEA[1])
            c.put(x, y - 1, SEA[2] if k % 3 else SEA[3])
            c.uput(x, y + 1, AO_SOFT)
        c.gput(13, 15, GLOW_TEAL)
        _draw_ellipse_rock(c, 20.5, 14.5, 2.3, 1.7, SHELL, ao_under=True)
        _draw_ellipse_rock(c, 11.5, 20.0, 2.2, 1.5, SAND_PEBBLE, ao_under=True)
        _draw_ellipse_rock(c, 17.5, 20.5, 2.0, 1.4, TRAVERTINE[1:6], ao_under=True)

    # ---- 24..26: Hero Coastal Tidepool Rocks (48x36 — angular faceted coastal slate + recessed dark-rimmed pools) ----
    elif prop_id in (24, 25, 26):
        pools = {
            24: [(23.5, 20.5, 8.2, 4.2)],
            25: [(21.5, 19.8, 9.0, 4.5)],
            26: [(16.5, 20.5, 5.5, 3.4), (31.0, 19.2, 5.2, 3.2)],
        }[prop_id]
        crags = {
            24: [(15.5, 17.5, 11.2, 8.8), (29.5, 18.5, 12.2, 8.4), (23.5, 22.5, 16.5, 7.2), (12.0, 23.0, 7.5, 5.2)],
            25: [(14.5, 16.8, 10.8, 8.6), (26.5, 16.2, 12.5, 8.8), (35.5, 21.2, 8.8, 6.6), (23.0, 22.8, 16.8, 7.0)],
            26: [(14.5, 18.2, 11.2, 8.6), (32.0, 17.8, 11.2, 8.4), (23.5, 22.5, 17.2, 7.4), (24.0, 15.5, 8.5, 6.0)],
        }[prop_id]

        for y in range(4, 32):
            for x in range(3, 45):
                best_d = 99.0
                best_nx = 0.0
                best_ny = 0.0
                for cx, cy, rx, ry in crags:
                    nx = (x - cx) / rx
                    ny = (y - cy) / ry
                    ang = math.atan2(ny, nx)
                    # Angular rock cleavage wobble (chiseled coastal strata, not smooth bean!)
                    wob = 0.11 * math.cos(ang * 3.0 + prop_id * 1.7) + 0.06 * math.sin(ang * 5.0 - prop_id)
                    d = (abs(nx) ** 2.3 + abs(ny) ** 2.3) ** (1.0 / 2.3) / (1.0 + wob)
                    if d < best_d:
                        best_d = d
                        best_nx = nx
                        best_ny = ny

                if best_d <= 1.0:
                    in_pool = False
                    for pcx, pcy, prx, pry in pools:
                        pnx = (x - pcx) / prx
                        pny = (y - pcy) / pry
                        pang = math.atan2(pny, pnx)
                        pwob = 0.12 * math.sin(pang * 3.0 + 1.2) + 0.07 * math.cos(pang * 5.0)
                        pd = (pnx * pnx + pny * pny) / ((1.0 + pwob) ** 2)
                        if pd <= 1.0:
                            in_pool = True
                            # Deep overhanging north rock wall inside the tidepool basin (3/4 perspective!)
                            if pny < -0.38:
                                c.put(x, y, STONE[0] if pny < -0.68 else WET_STONE[0])
                            elif pd > 0.72:
                                c.put(x, y, POOL_WATER[0])
                            else:
                                wlit = -0.35 * pnx + 0.55 * pny
                                c.put(x, y, POOL_WATER[2] if wlit > 0.18 else (POOL_WATER[1] if wlit > -0.15 else POOL_WATER[0]))
                            break
                        elif pd <= 1.30:
                            # Sculpted stone lip around basin: dark shaded north crease, lit south-east bevel rim
                            c.put(x, y, STONE[6] if (pny > 0.25 and pnx > -0.4) else WET_STONE[1])
                            in_pool = True
                            break
                    if not in_pool:
                        # Stepped horizontal slate strata + crisp planar facets
                        strata_step = ((y + (x // 5) + prop_id) % 5 == 0)
                        lit = -0.58 * best_nx - 0.80 * best_ny
                        if y >= 26:
                            wt = 2 if lit > 0.18 else (1 if lit > -0.30 else 0)
                            c.put(x, y, WET_STONE[wt])
                        else:
                            idx = 3 + int(round(lit * 2.7)) - (1 if strata_step else 0)
                            if best_d > 0.82 and lit > 0.28:
                                idx = min(7, idx + 1)
                            elif best_d > 0.84 and lit < -0.22:
                                idx = max(0, idx - 1)
                            c.put(x, y, STONE[max(0, min(7, idx))])
                elif best_d <= 1.16 and y >= 26:
                    c.uput(x, y, AO_SOFT)

        # Subtle crisp specular glint + tiny barnacle clusters & nocturnal pool glow (ZERO stray pixels under outline!)
        for idx_p, (pcx, pcy, prx, pry) in enumerate(pools):
            gx, gy = int(round(pcx - prx * 0.28)), int(round(pcy + 0.5))
            c.put(gx, gy, POOL_WATER[3])
            c.put(gx + 1, gy, POOL_WATER[2])
            ax, ay = int(round(pcx + prx * 0.25)), int(round(pcy + pry * 0.20))
            c.put(ax, ay, POOL_WATER[2])
            c.gput(ax, ay, GLOW_TEAL_HI)
            if prop_id in (24, 26) or idx_p == 0:
                vx, vy = int(round(pcx - prx * 0.10)), int(round(pcy + pry * 0.26))
                c.put(vx, vy, hexc("6c58b8"))
                c.gput(vx, vy, GLOW_VIO_HI)
                c.gput(vx + 1, vy, GLOW_VIO)
        if prop_id == 25:
            c.put(25, 20, POOL_WATER[2])
            c.gput(25, 20, GLOW_TEAL)
            c.gput(26, 20, GLOW_TEAL)
        # Tiny pale barnacles on wet lower rock face
        for bx_b, by_b in ((11, 25), (12, 26), (34, 25), (28, 27)):
            if c.px[by_b][bx_b][3] > 0:
                c.put(bx_b, by_b, STONE[6])

        c.outline(INK, STONE[1])

    # ---- 27: Hero Bleached Driftwood Log (48x36 — organic S-curved coastal trunk + diagonal fork) ----
    else:
        for i in range(36):
            x = 6 + i
            t = i / 35.0
            yc = 24.5 + 1.8 * math.sin(t * math.pi * 1.35 - 0.5) - 1.2 * t
            rad = 2.8 * (1.0 - 0.42 * t) + (1.2 * ((1.0 - t / 0.25) ** 2) if t < 0.25 else 0.0)
            for dy in range(-int(rad) - 1, int(rad) + 2):
                if abs(dy) > rad:
                    continue
                if i in (0, 35) and abs(dy) > rad * 0.55:
                    continue
                ny = dy / max(1.0, rad)
                tone = 5 if (ny < -0.45 and i % 5 in (1, 2, 3)) else (4 if ny < -0.10 else (3 if ny < 0.30 else (2 if ny < 0.70 else 1)))
                if abs(ny + 0.05 * math.sin(i * 0.4)) < 0.22 and i % 6 in (2, 3, 4):
                    tone = max(1, tone - 1)
                c.put(x, int(round(yc)) + dy, DRIFTWOOD[tone])
            c.uput(x, int(round(yc + rad)) + 1, AO_SOFT)
        # Sweeping diagonal weathered limb fork (curving up-right naturally, never 90° pegs!)
        for k in range(1, 9):
            fx = 25 + k
            fy = int(round(22.5 - k * 0.65))
            c.put(fx, fy, DRIFTWOOD[4 if k >= 5 else 3])
            if k <= 6:
                c.put(fx, fy + 1, DRIFTWOOD[2])
        # Natural tapered root flare on left
        for k in range(1, 6):
            rx_p = 9 - k
            ry_p = int(round(23.5 - k * 0.45))
            c.put(rx_p, ry_p, DRIFTWOOD[3 if k < 4 else 4])
            c.put(rx_p, ry_p + 1, DRIFTWOOD[2])
        c.outline(DRIFT_OUTLINE, DRIFTWOOD[1])

    return c.finish()


# ---------------------------------------------------------------------------
# 4x QA Atlas Preview Builder (880 x 1504 px)
# ---------------------------------------------------------------------------
def build_4x_atlas(sprites: list[tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]]) -> list[list[tuple[int, int, int, int]]]:
    lw, lh = 220, 376
    bg_gutter = hexc("1b1a2e")
    bg_night = hexc("14192c")
    img = [[bg_gutter] * lw for _ in range(lh)]

    def cell_day_bg(pid: int) -> tuple[int, int, int, int]:
        if pid in (0, 1, 2, 10):
            return hexc("28545a")  # brook water
        if 3 <= pid <= 9:
            return hexc("356b4d")  # mossy bank
        if 24 <= pid <= 26:
            return hexc("2c5b63")  # coastal surf-slate
        return hexc("c7ab7c")      # dry beach sand

    # Paint day section (`y = 0..187`) and night section (`y = 188..375`)
    for y in range(188, lh):
        for x in range(lw):
            img[y][x] = bg_night

    # Rows 0..3 (32x32)
    for pid in range(24):
        col = pid % 6
        row = pid // 6
        ox = 4 + col * 36
        oy_day = 4 + row * 36
        oy_night = 192 + row * 36
        dbg = cell_day_bg(pid)
        for y in range(32):
            for x in range(32):
                img[oy_day + y][ox + x] = dbg
        base, gl = sprites[pid]
        for y in range(32):
            for x in range(32):
                p = base[y][x]
                if p[3] > 0:
                    img[oy_day + y][ox + x] = blend_over(img[oy_day + y][ox + x], p)
                    dim = (max(6, int(p[0] * 0.42)), max(7, int(p[1] * 0.48)), max(14, int(p[2] * 0.68)), p[3])
                    img[oy_night + y][ox + x] = blend_over(img[oy_night + y][ox + x], dim)
                g = gl[y][x]
                if g[3] > 0:
                    dc = img[oy_night + y][ox + x]
                    f = g[3] / 255.0
                    img[oy_night + y][ox + x] = (
                        min(255, int(dc[0] + g[0] * f)),
                        min(255, int(dc[1] + g[1] * f)),
                        min(255, int(dc[2] + g[2] * f)),
                        255,
                    )

    # Row 4 (48x36 hero props)
    for pid in range(24, 28):
        col = pid - 24
        ox = 8 + col * 52
        oy_day = 148
        oy_night = 336
        dbg = cell_day_bg(pid)
        for y in range(36):
            for x in range(48):
                img[oy_day + y][ox + x] = dbg
        base, gl = sprites[pid]
        for y in range(36):
            for x in range(48):
                p = base[y][x]
                if p[3] > 0:
                    img[oy_day + y][ox + x] = blend_over(img[oy_day + y][ox + x], p)
                    dim = (max(6, int(p[0] * 0.42)), max(7, int(p[1] * 0.48)), max(14, int(p[2] * 0.68)), p[3])
                    img[oy_night + y][ox + x] = blend_over(img[oy_night + y][ox + x], dim)
                g = gl[y][x]
                if g[3] > 0:
                    dc = img[oy_night + y][ox + x]
                    f = g[3] / 255.0
                    img[oy_night + y][ox + x] = (
                        min(255, int(dc[0] + g[0] * f)),
                        min(255, int(dc[1] + g[1] * f)),
                        min(255, int(dc[2] + g[2] * f)),
                        255,
                    )

    scale = 4
    out = [[CLEAR] * (lw * scale) for _ in range(lh * scale)]
    for y in range(lh):
        for sy in range(scale):
            dst = out[y * scale + sy]
            for x in range(lw):
                c = img[y][x]
                bx = x * scale
                for sx in range(scale):
                    dst[bx + sx] = c
    return out


def main() -> None:
    sprites = [build_prop(pid) for pid in range(28)]

    sheet = make_grid(SHEET_W, SHEET_H)
    glow_sheet = make_grid(SHEET_W, SHEET_H)

    for info in COASTAL_PROPS_RECTS.values():
        pid = info["id"]
        rx, ry, rw, rh = info["rect"]
        base, gl = sprites[pid]
        assert len(base) == rh and len(base[0]) == rw
        for y in range(rh):
            for x in range(rw):
                sheet[ry + y][rx + x] = base[y][x]
                glow_sheet[ry + y][rx + x] = gl[y][x]

    # Assert submerged_pebbles_0 contains zero #1b1a2e dark outline pixels
    sub_rx, sub_ry, sub_rw, sub_rh = COASTAL_PROPS_RECTS["submerged_pebbles_0"]["rect"]
    for y in range(sub_ry, sub_ry + sub_rh):
        for x in range(sub_rx, sub_rx + sub_rw):
            assert sheet[y][x] != INK, f"submerged_pebbles_0 must not contain dark outline {INK} at ({x}, {y})"

    atlas = build_4x_atlas(sprites)

    verify_no_black("coastal_props.png", sheet)
    verify_no_black("coastal_props_glow.png", glow_sheet)
    verify_no_black("coastal_biome_atlas_4x.png", atlas)

    tiles_dir = ROOT / "tiles"
    atlas_path = ROOT.parent / "docs" / "img" / "coastal_biome_atlas_4x.png"
    write_png(tiles_dir / "coastal_props.png", SHEET_W, SHEET_H, sheet)
    write_png(tiles_dir / "coastal_props_glow.png", SHEET_W, SHEET_H, glow_sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    print(
        f"Wrote {tiles_dir / 'coastal_props.png'} ({SHEET_W}x{SHEET_H}), _glow.png, "
        f"and {atlas_path} ({len(atlas[0])}x{len(atlas)})"
    )


if __name__ == "__main__":
    main()
