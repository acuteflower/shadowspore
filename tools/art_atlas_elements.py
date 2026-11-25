#!/usr/bin/env python3
"""Procedural pixel-art generator for Atlas Book & AtlasView UI Ornaments & Rewards.

Outputs:
  assets/ui/atlas_elements.png      256x160 modular UI sprite atlas (NO _glow.png)
  data/atlas_elements_art.json      Exact region rects, anchors, reward tiers, tileable & 9-patch metadata
  docs/img/atlas_elements_atlas_4x.png  1280x1056 (4x nearest) UI/Parchment mockups + full sheet inspection
"""
from __future__ import annotations

import json
import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import blend_over, make_grid  # noqa: E402

SHEET_W = 256
SHEET_H = 160

# ---------------------------------------------------------------------------
# Palettes (Zero #000000)
# ---------------------------------------------------------------------------
OUTLINE = hexc("1b1a2e")
PANEL_DARK = hexc("1e1a36")
PANEL = hexc("2a2548")
SLOT_BG = hexc("171329")
RIM = hexc("4a4180")
TEXT_DIM = hexc("8a84ad")
TEXT = hexc("e8e4f4")
ACCENT = hexc("7fe3da")

GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
TEAL = [hexc(c) for c in ("2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
VIOLET = [hexc(c) for c in ("34185e", "6636ad", "9468ee", "cbaaff")]
SILVER = [hexc(c) for c in ("6b7392", "93a0bc", "d4dbec", "f6f9ff")]
SLATE = [hexc(c) for c in ("202f3b", "344656", "4d6272", "6d828f", "8fa3ad", "b3c2c7")]

BARK_OUT = hexc("120c1c")
BARK_D = hexc("3b2c40")
BARK_L = hexc("65506b")
LEAF_D = hexc("2f624e")
LEAF_M = hexc("4f9a62")
LEAF_L = hexc("a6e68f")
PETAL = hexc("f1e6ff")

WAX_OUT = hexc("291522")
WAX_D = hexc("5e1f38")
WAX_M = hexc("9e3550")
WAX_L = hexc("d96277")
WAX_HI = hexc("ffb4a8")

INK_DARK = hexc("1e3a4c")
INK_MID = hexc("2a8c94")
INK_LIT = hexc("3cc0c6")
INK_PLUM = hexc("362535")
INK_RIM = hexc("d4dbec")

DANGER_D = hexc("c21f3b")
DANGER_L = hexc("ff4a63")


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def verify_no_black(name: str, px: list[list[tuple[int, int, int, int]]]) -> None:
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} contains forbidden #000000 pixel at ({x}, {y})")


def _outline(px: list[list[tuple[int, int, int, int]]], col: tuple[int, int, int, int] = OUTLINE) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    out = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if px[y][x][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= 200:
                        out[y][x] = col
                        break
    return out


def _put(px: list[list[tuple[int, int, int, int]]], x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = c


# ---------------------------------------------------------------------------
# 1. Coast Stamps (30% Reward) & Compass & Completion Flower
# ---------------------------------------------------------------------------
def build_coast_stamp_wax() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 32
    px = make_grid(w, h)
    cx, cy = 15.5, 15.5
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            ang = math.atan2(y - cy, x - cx)
            r = math.hypot(x - cx, y - cy)
            wob = 0.8 * math.sin(ang * 5.0) + 0.5 * math.cos(ang * 7.0 + 1.0)
            if r <= 13.0 + wob:
                nx = (x - cx) / 13.0
                ny = (y - cy) / 13.0
                lit = -0.55 * nx - 0.80 * ny
                if r >= 10.6:
                    # Raised wax lip
                    c = WAX_HI if lit > 0.38 else (WAX_L if lit > -0.1 else (WAX_M if lit > -0.5 else WAX_D))
                elif r >= 9.6:
                    c = WAX_D  # recessed inner ring groove
                else:
                    c = WAX_L if lit > 0.30 else (WAX_M if lit > -0.35 else WAX_D)
                px[y][x] = c
    # Embossed lighthouse & cliff silhouette + triple coastal waves
    # Lighthouse tower
    for y in range(9, 18):
        for x in (14, 15, 16):
            px[y][x] = GOLD[2] if x == 14 or y < 12 else GOLD[1]
    px[8][15] = GOLD[3]
    px[10][15] = TEAL[3]
    # Cliff shoulder
    for x in range(10, 17):
        px[18][x] = WAX_HI if x < 14 else WAX_M
    # Triple waves (lower half)
    for wy, wx0, wx1 in ((19, 10, 21), (21, 11, 20), (23, 12, 19)):
        for x in range(wx0, wx1 + 1):
            wave_hi = ((x + wy) % 3 != 0)
            px[wy][x] = WAX_HI if wave_hi else WAX_D
    # Gold wax rim flecks
    for gx, gy in ((6, 12), (7, 10), (23, 21), (24, 19)):
        px[gy][gx] = GOLD[2]
    return _outline(px, WAX_OUT)


def build_coast_stamp_ink() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 32
    px = make_grid(w, h)
    cx, cy = 15.5, 15.5
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            r = math.hypot(x - cx, y - cy)
            ang = math.atan2(y - cy, x - cx)
            # Broken double ring
            if 11.4 <= r <= 12.6 and (math.sin(ang * 6.0) > -0.65):
                px[y][x] = INK_MID
            elif 9.2 <= r <= 10.1 and (math.cos(ang * 4.0) > -0.75):
                px[y][x] = INK_PLUM
    # Crisp lighthouse & cape silhouette inside ring
    for y in range(9, 18):
        px[y][14] = INK_LIT if y < 13 else INK_DARK
        px[y][15] = INK_DARK
        px[y][16] = INK_MID
    px[8][15] = TEAL[2]
    for x in range(10, 17):
        px[18][x] = INK_DARK
    for wy, wx0, wx1 in ((20, 10, 21), (22, 11, 20)):
        for x in range(wx0, wx1 + 1):
            if (x + wy) % 4 != 0:
                px[wy][x] = INK_MID if wy == 20 else INK_LIT
    # Compass tick notches around ring
    for tx, ty in ((15, 3), (16, 3), (15, 28), (16, 28), (3, 15), (3, 16), (28, 15), (28, 16)):
        px[ty][tx] = INK_DARK
    return px


def build_coast_stamp_mini() -> list[list[tuple[int, int, int, int]]]:
    w, h = 16, 16
    px = make_grid(w, h)
    cx, cy = 7.5, 7.5
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r = math.hypot(x - cx, y - cy)
            if r <= 6.2:
                lit = -0.55 * (x - cx) / 6.0 - 0.80 * (y - cy) / 6.0
                px[y][x] = WAX_L if lit > 0.2 else (WAX_M if lit > -0.35 else WAX_D)
    # Mini gold lighthouse + wave bar
    for y in range(4, 9):
        px[y][7] = px[y][8] = GOLD[2]
    px[4][7] = GOLD[3]
    for x in range(5, 11):
        px[10][x] = GOLD[2] if x % 2 == 1 else WAX_HI
    return _outline(px, WAX_OUT)


def build_compass_rose() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 32
    px = make_grid(w, h)
    cx, cy = 15.5, 15.5
    # Inner gold collar
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if 5.2 <= r <= 6.4:
                lit = -0.55 * dx / 6.0 - 0.80 * dy / 6.0
                px[y][x] = GOLD[3 if lit > 0.35 else (2 if lit > -0.2 else 1)]
    # 4 Intercardinal points (NE, SE, SW, NW)
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        for k in range(1, 8):
            px_x = int(round(cx + sx * k))
            px_y = int(round(cy + sy * k))
            px[px_y][px_x] = SLATE[4 if sx < 0 or sy < 0 else 2]
            if k <= 4:
                px[px_y][px_x - sx] = SLATE[2]
    # 4 Cardinal arms
    # North arm (glowing turquoise!)
    for y in range(2, 14):
        half = max(0, (y - 2) // 4)
        for dx in range(-half, half + 1):
            col = TEAL[3] if dx < 0 or y < 6 else (TEAL[2] if dx == 0 else TEAL[1])
            px[y][int(round(cx + dx))] = col
    # South arm
    for y in range(18, 30):
        half = max(0, (29 - y) // 4)
        for dx in range(-half, half + 1):
            px[y][int(round(cx + dx))] = SLATE[4 if dx < 0 else 1]
    # West arm
    for x in range(2, 14):
        half = max(0, (x - 2) // 4)
        for dy in range(-half, half + 1):
            px[int(round(cy + dy))][x] = GOLD[3 if dy <= 0 else 1]
    # East arm
    for x in range(18, 30):
        half = max(0, (29 - x) // 4)
        for dy in range(-half, half + 1):
            px[int(round(cy + dy))][x] = GOLD[2 if dy < 0 else 0]
    # Center jewel hub
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            px[int(round(cy + dy))][int(round(cx + dx))] = TEAL[3] if (dx == 0 and dy == 0) else GOLD[2]
    return _outline(px, OUTLINE)


def build_compass_ring_outer() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 32
    px = make_grid(w, h)
    cx, cy = 15.5, 15.5
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            if 12.2 <= r <= 14.5:
                lit = -0.55 * dx / 14.0 - 0.80 * dy / 14.0
                if 13.0 <= r <= 13.7:
                    px[y][x] = GOLD[2 if lit > 0 else 1]
                else:
                    px[y][x] = SLATE[4 if lit > 0.3 else (3 if lit > -0.2 else 1)]
    # 4 cardinal studs
    for sx, sy in ((15, 2), (16, 2), (15, 29), (16, 29), (2, 15), (2, 16), (29, 15), (29, 16)):
        px[sy][sx] = GOLD[3] if sx < 16 or sy < 16 else GOLD[1]
    return _outline(px, OUTLINE)


def build_flower(stage: int) -> list[list[tuple[int, int, int, int]]]:
    w, h = 16, 16
    px = make_grid(w, h)
    # Base small stem & pair of leaves
    for y in range(11, 14):
        px[y][7] = px[y][8] = LEAF_M if y < 13 else LEAF_D
    px[12][5] = px[12][6] = LEAF_L
    px[13][6] = LEAF_D
    px[12][9] = px[12][10] = LEAF_M
    px[13][9] = LEAF_D

    if stage == 0:
        # Closed violet-bark bud
        for y in range(6, 11):
            for x in (7, 8):
                px[y][x] = VIOLET[2 if y < 8 else 1]
        px[5][7] = px[5][8] = VIOLET[3]
    elif stage == 1:
        # 30% half-open teal-rimmed bud
        for y in range(6, 11):
            for x in range(6, 10):
                if y == 6 and x in (6, 9):
                    continue
                px[y][x] = TEAL[2 if y < 8 else 1]
        px[5][7] = px[5][8] = TEAL[3]
        px[7][7] = px[7][8] = PETAL
    elif stage == 2:
        # 60% blooming silver-petal & leaf rosette
        for ox, oy, c in (
            (0, -3, SILVER[3]), (0, -2, SILVER[2]),
            (-3, -1, SILVER[3]), (-2, -1, SILVER[2]), (2, -1, SILVER[2]), (3, -1, SILVER[1]),
            (-2, 1, SILVER[2]), (2, 1, SILVER[1]), (0, 2, SILVER[1]),
        ):
            px[8 + oy][8 + ox] = c
            px[8 + oy][7 + ox] = c
        px[7][7] = px[7][8] = TEAL[3]
        px[8][7] = px[8][8] = TEAL[2]
    else:
        # 100% radiant full 6-petal silver/turquoise/gold blossom
        cx, cy = 7.5, 7.5
        for i in range(6):
            ang = i * math.tau / 6.0 - math.pi / 2.0
            px_c = int(round(cx + math.cos(ang) * 3.8))
            py_c = int(round(cy + math.sin(ang) * 3.8))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if abs(dx) + abs(dy) <= 1:
                        lit = -0.55 * ((px_c + dx) - cx) / 4.0 - 0.80 * ((py_c + dy) - cy) / 4.0
                        col = SILVER[3 if lit > 0.25 else (2 if lit > -0.2 else 1)]
                        _put(px, px_c + dx, py_c + dy, col)
        # Turquoise & gold core
        for y in (6, 7, 8, 9):
            for x in (6, 7, 8, 9):
                if abs(x - 7.5) + abs(y - 7.5) <= 2.2:
                    px[y][x] = TEAL[2]
        px[7][7] = GOLD[3]
        px[7][8] = px[8][7] = GOLD[2]
        px[8][8] = GOLD[1]
    return _outline(px, OUTLINE)


# ---------------------------------------------------------------------------
# 2. Silberküsten-Rahmenranke (60% Reward) — 4 Independent NW->SE Corners + Tileable Strips
# ---------------------------------------------------------------------------
def _draw_vine_leaf(px: list[list[tuple[int, int, int, int]]], x: int, y: int, silver: bool = True) -> None:
    cols = (SILVER[3], SILVER[2], SILVER[1]) if silver else (LEAF_L, LEAF_M, LEAF_D)
    _put(px, x, y, cols[0])
    _put(px, x + 1, y, cols[1])
    _put(px, x, y + 1, cols[1])
    _put(px, x + 1, y + 1, cols[2])


def build_vine_corner(quad: str) -> list[list[tuple[int, int, int, int]]]:
    """Renders NW, NE, SW, or SE 24x24 corner INDIVIDUALLY with consistent NW->SE lighting."""
    w, h = 24, 24
    px = make_grid(w, h)
    # Determine which horizontal & vertical edge the frame runs along so tiled strips meet at x=0/23, y=0/23
    # Standard border thickness runs around line 4..7 from the outer frame edge
    # NW: top edge y=4..7 (x=4..23), left edge x=4..7 (y=4..23)
    # NE: top edge y=4..7 (x=0..19), right edge x=16..19 (y=4..23)
    # SW: bottom edge y=16..19 (x=4..23), left edge x=4..7 (y=0..19)
    # SE: bottom edge y=16..19 (x=0..19), right edge x=16..19 (y=0..19)
    has_top = quad in ("nw", "ne")
    has_left = quad in ("nw", "sw")
    hy = 5 if has_top else 18
    vx = 5 if has_left else 18
    hx0, hx1 = (5, 23) if has_left else (0, 18)
    vy0, vy1 = (5, 23) if has_top else (0, 18)

    # Horizontal bark stem with consistent NW->SE lighting (top=lit, bottom=dark)
    for x in range(hx0, hx1 + 1):
        wave = int(round(math.sin(x * 0.4)))
        yy = hy + (wave if 6 < x < 17 else 0)
        _put(px, x, yy - 1, BARK_L)
        _put(px, x, yy, BARK_D)
        _put(px, x, yy + 1, BARK_D)
    # Vertical bark stem with consistent NW->SE lighting (left=lit, right=dark)
    for y in range(vy0, vy1 + 1):
        wave = int(round(math.sin(y * 0.4)))
        xx = vx + (wave if 6 < y < 17 else 0)
        _put(px, xx - 1, y, BARK_L)
        _put(px, xx, y, BARK_D)
        _put(px, xx + 1, y, BARK_D)

    # Corner blossom medallion + asymmetric silver leaves (always NW->SE shaded)
    cx, cy = vx, hy
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if abs(dx) + abs(dy) <= 2:
                lit = -0.55 * dx - 0.80 * dy
                c = TEAL[3] if (dx == 0 and dy == 0) else (SILVER[3] if lit > 0.2 else (PETAL if lit > -0.3 else SILVER[1]))
                _put(px, cx + dx, cy + dy, c)
    # Distinct corner leaf flourishes per quadrant
    if quad == "nw":
        _draw_vine_leaf(px, 11, 2, silver=True)
        _draw_vine_leaf(px, 17, 7, silver=False)
        _draw_vine_leaf(px, 2, 11, silver=True)
        _draw_vine_leaf(px, 7, 17, silver=False)
        _put(px, 9, 9, ACCENT)
    elif quad == "ne":
        _draw_vine_leaf(px, 10, 2, silver=False)
        _draw_vine_leaf(px, 4, 7, silver=True)
        _draw_vine_leaf(px, 20, 11, silver=True)
        _draw_vine_leaf(px, 15, 17, silver=False)
        _put(px, 14, 9, ACCENT)
    elif quad == "sw":
        _draw_vine_leaf(px, 2, 10, silver=False)
        _draw_vine_leaf(px, 7, 4, silver=True)
        _draw_vine_leaf(px, 11, 20, silver=True)
        _draw_vine_leaf(px, 17, 15, silver=False)
        _put(px, 9, 14, PETAL)
    else:  # se
        _draw_vine_leaf(px, 20, 10, silver=False)
        _draw_vine_leaf(px, 15, 4, silver=True)
        _draw_vine_leaf(px, 10, 20, silver=True)
        _draw_vine_leaf(px, 4, 15, silver=False)
        _put(px, 14, 14, GOLD[2])

    return _outline(px, BARK_OUT)


def build_vine_border_h() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 12
    px = make_grid(w, h)
    for x in range(w):
        # Periodic sinusoid with period 32 so x=0 matches x=31 seamlessly
        yy = 5 + int(round(math.sin(x * math.tau / 32.0)))
        _put(px, x, yy - 1, BARK_L)
        _put(px, x, yy, BARK_D)
        _put(px, x, yy + 1, BARK_D)
    _draw_vine_leaf(px, 7, 2, silver=True)
    _draw_vine_leaf(px, 15, 7, silver=False)
    _draw_vine_leaf(px, 23, 2, silver=True)
    _put(px, 16, 4, ACCENT)
    return _outline(px, BARK_OUT)


def build_vine_border_v() -> list[list[tuple[int, int, int, int]]]:
    w, h = 12, 32
    px = make_grid(w, h)
    for y in range(h):
        xx = 5 + int(round(math.sin(y * math.tau / 32.0)))
        _put(px, xx - 1, y, BARK_L)
        _put(px, xx, y, BARK_D)
        _put(px, xx + 1, y, BARK_D)
    _draw_vine_leaf(px, 2, 7, silver=True)
    _draw_vine_leaf(px, 7, 15, silver=False)
    _draw_vine_leaf(px, 2, 23, silver=True)
    _put(px, 4, 16, ACCENT)
    return _outline(px, BARK_OUT)


def build_vine_divider() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 12
    px = make_grid(w, h)
    for x in range(3, 29):
        _put(px, x, 5, BARK_L if x < 16 else BARK_D)
        _put(px, x, 6, BARK_D)
    for lx in (6, 10, 20, 24):
        _draw_vine_leaf(px, lx, 3 if lx in (10, 20) else 7, silver=(lx in (6, 24)))
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if abs(dx) + abs(dy) <= 2:
                _put(px, 15 + dx, 5 + dy, TEAL[3] if (dx == 0 and dy == 0) else SILVER[3 if dx + dy <= 0 else 1])
    return _outline(px, BARK_OUT)


# ---------------------------------------------------------------------------
# 3. Stone-Setter Engraving Frame (4 Independent NW->SE Corners + Tileable Strips)
# ---------------------------------------------------------------------------
def build_engrave_corner(quad: str) -> list[list[tuple[int, int, int, int]]]:
    w, h = 16, 16
    px = make_grid(w, h)
    has_top = quad in ("nw", "ne")
    has_left = quad in ("nw", "sw")
    hy = 3 if has_top else 12
    vx = 3 if has_left else 12
    hx0, hx1 = (2, 15) if has_left else (0, 13)
    vy0, vy1 = (2, 15) if has_top else (0, 13)

    # Stone double-bevel bar (top/left highlight, bottom/right shadow)
    for x in range(hx0, hx1 + 1):
        _put(px, x, hy - 1, TEXT)
        _put(px, x, hy, TEXT_DIM)
        _put(px, x, hy + 1, RIM)
    for y in range(vy0, vy1 + 1):
        _put(px, vx - 1, y, TEXT)
        _put(px, vx, y, TEXT_DIM)
        _put(px, vx + 1, y, RIM)

    # Carved corner square + gold inlaid corner notch
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            lit = -0.55 * dx - 0.80 * dy
            c = TEXT if lit > 0.4 else (TEXT_DIM if lit > -0.3 else RIM)
            _put(px, vx + dx, hy + dy, c)
    _put(px, vx, hy, GOLD[2] if has_top or has_left else GOLD[1])
    _put(px, vx - 1 if has_left else vx + 1, hy - 1 if has_top else hy + 1, GOLD[3] if quad == "nw" else GOLD[1])
    return _outline(px, OUTLINE)


def build_engrave_border_h() -> list[list[tuple[int, int, int, int]]]:
    w, h = 32, 8
    px = make_grid(w, h)
    for x in range(w):
        is_notch = (x % 8 == 4)
        _put(px, x, 2, TEXT if not is_notch else GOLD[2])
        _put(px, x, 3, TEXT_DIM)
        _put(px, x, 4, RIM)
    return _outline(px, OUTLINE)


def build_engrave_border_v() -> list[list[tuple[int, int, int, int]]]:
    w, h = 8, 32
    px = make_grid(w, h)
    for y in range(h):
        is_notch = (y % 8 == 4)
        _put(px, 2, y, TEXT if not is_notch else GOLD[2])
        _put(px, 3, y, TEXT_DIM)
        _put(px, 4, y, RIM)
    return _outline(px, OUTLINE)


def build_engrave_divider() -> list[list[tuple[int, int, int, int]]]:
    w, h = 48, 12
    px = make_grid(w, h)
    for x in range(3, 45):
        _put(px, x, 5, TEXT if x % 6 != 0 else GOLD[2])
        _put(px, x, 6, RIM)
    for dy in range(-3, 4):
        for dx in range(-4, 5):
            if abs(dx) * 0.75 + abs(dy) <= 3.2:
                c = TEAL[3] if abs(dx) + abs(dy) <= 1 else (GOLD[2] if abs(dx) + abs(dy) == 2 else SLATE[4 if dx + dy <= 0 else 2])
                _put(px, 23 + dx, 5 + dy, c)
    return _outline(px, OUTLINE)


# ---------------------------------------------------------------------------
# 4. Seals, Badges & Title Ribbon
# ---------------------------------------------------------------------------
def build_seal(unlocked: bool) -> list[list[tuple[int, int, int, int]]]:
    w, h = 16, 16
    px = make_grid(w, h)
    cx, cy = 7.5, 7.5
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r = math.hypot(x - cx, y - cy)
            if 4.8 <= r <= 6.4:
                lit = -0.55 * (x - cx) / 6.0 - 0.80 * (y - cy) / 6.0
                if unlocked:
                    px[y][x] = GOLD[3 if lit > 0.3 else (2 if lit > -0.2 else 1)]
                else:
                    px[y][x] = RIM if lit > 0 else VIOLET[0]
            elif r < 4.8:
                px[y][x] = TEAL[0] if unlocked else SLOT_BG
    if unlocked:
        for y in range(4, 11):
            px[y][7] = px[y][8] = TEAL[3]
        for x in range(5, 11):
            px[7][x] = TEAL[2]
    else:
        for y in range(5, 11):
            for x in range(6, 10):
                px[y][x] = VIOLET[2 if y < 8 else 1]
        px[7][7] = px[7][8] = DANGER_L
        px[8][7] = px[8][8] = DANGER_D
    return _outline(px, OUTLINE)


def build_veil_thread_icon() -> list[list[tuple[int, int, int, int]]]:
    # 12x12 glowing obsidian-violet Schattenfrucht badge with emerald leaf crown & turquoise spore gleam
    w, h = 12, 12
    px = make_grid(w, h)
    # Plump fruit bulb (rows 4..9, cols 3..8)
    for y in range(4, 10):
        for x in range(3, 9):
            dx = (x - 5.5) / 2.7
            dy = (y - 6.6) / 2.9
            if dx * dx + dy * dy <= 1.0:
                if dx < -0.15 and dy < -0.1:
                    px[y][x] = VIOLET[2]
                elif dy < 0.35:
                    px[y][x] = VIOLET[1]
                else:
                    px[y][x] = VIOLET[0]
    # Luminous spore eyes / bioluminescent gleam on the fruit belly
    _put(px, 4, 6, TEAL[3])
    _put(px, 7, 6, TEAL[3])
    _put(px, 5, 8, TEAL[2])
    # Curled 3-leaf crown at top
    _put(px, 5, 3, TEAL[1])
    _put(px, 6, 3, TEAL[1])
    _put(px, 4, 2, TEAL[2])
    _put(px, 6, 2, TEAL[2])
    _put(px, 8, 2, TEAL[2])
    _put(px, 6, 1, TEAL[3])
    return _outline(px, OUTLINE)


def build_badge(kind_name: str) -> list[list[tuple[int, int, int, int]]]:
    w, h = 12, 12
    px = make_grid(w, h)
    if kind_name == "waystone":
        for y in range(2, 10):
            for x in range(4, 8):
                if y == 2 and x in (4, 7):
                    continue
                px[y][x] = SLATE[4 if x < 6 else 2]
        px[4][5] = px[5][5] = px[5][6] = TEAL[3]
    elif kind_name == "vista":
        # Horizon + golden sun + teal eye glint
        for x in range(2, 10):
            px[8][x] = SLATE[3]
        for y in range(4, 8):
            for x in range(4, 8):
                if abs(x - 5.5) + abs(y - 5.5) <= 2.2:
                    px[y][x] = GOLD[2 if y < 6 else 1]
        px[5][5] = ACCENT
    elif kind_name == "chest":
        for y in range(4, 10):
            for x in range(2, 10):
                px[y][x] = GOLD[2 if y < 6 else 1] if (y == 6 or x in (3, 8)) else BARK_L if y < 6 else BARK_D
        px[6][5] = px[6][6] = GOLD[3]
    elif kind_name == "puzzle":
        for y in range(3, 10):
            for x in range(3, 9):
                px[y][x] = SLATE[4 if x < 6 and y < 6 else 2]
        px[5][5] = px[6][6] = TEAL[3]
        px[5][6] = px[6][5] = TEAL[2]
    elif kind_name == "flora":
        for y in range(5, 10):
            px[y][5] = LEAF_M
        for lx, ly in ((3, 4), (4, 4), (4, 5), (6, 3), (7, 3), (7, 4)):
            px[ly][lx] = LEAF_L if ly <= 4 else LEAF_M
        px[2][5] = TEAL[3]
    else:  # secret
        for y in range(2, 10):
            px[y][5] = VIOLET[3 if y < 6 else 2]
        for x in range(2, 9):
            px[5][x] = VIOLET[3 if x < 5 else 2]
        px[5][5] = GOLD[3]
    return _outline(px, OUTLINE)


def build_title_ribbon() -> list[list[tuple[int, int, int, int]]]:
    w, h = 64, 16
    px = make_grid(w, h)
    # Swallowtail end caps (x=1..11, x=52..62) + central banner (x=12..51)
    for y in range(2, 14):
        for x in range(1, 63):
            # Swallowtail notch
            dist_from_mid = abs(y - 7.5)
            if x < 5 and dist_from_mid < (5 - x) * 0.9:
                continue
            if x > 58 and dist_from_mid < (x - 58) * 0.9:
                continue
            if y in (2, 13):
                c = GOLD[2 if y == 2 else 1]
            elif y in (3, 12):
                c = GOLD[1]
            elif x in (11, 52):
                c = GOLD[2]
            else:
                c = PANEL if y < 8 else PANEL_DARK
            px[y][x] = c
    # Gold corner studs inside caps
    px[7][7] = px[8][7] = GOLD[3]
    px[7][56] = px[8][56] = GOLD[2]
    return _outline(px, OUTLINE)


# ---------------------------------------------------------------------------
# Sheet Assembly, Assertions & 4x QA Atlas
# ---------------------------------------------------------------------------
def _blit(
    dst: list[list[tuple[int, int, int, int]]],
    src: list[list[tuple[int, int, int, int]]],
    ox: int,
    oy: int,
    alpha_blend: bool = True,
) -> None:
    dh, dw = len(dst), len(dst[0])
    for y, row in enumerate(src):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x, c in enumerate(row):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            dst[dy][dx] = blend_over(dst[dy][dx], c) if alpha_blend else c


def _crop(src: list[list[tuple[int, int, int, int]]], rect: list[int]) -> list[list[tuple[int, int, int, int]]]:
    rx, ry, rw, rh = rect
    return [src[ry + y][rx : rx + rw] for y in range(rh)]


def _flip_h(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    return [row[::-1] for row in src]


def _flip_v(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    return src[::-1]


def build_metadata() -> dict:
    return {
        "sheet": "res://assets/ui/atlas_elements.png",
        "size": [SHEET_W, SHEET_H],
        "regions": {
            "coast_stamp_wax": {"rect": [4, 4, 32, 32], "anchor": [16, 16], "category": "reward_stamp", "reward_tier": 30},
            "coast_stamp_ink": {"rect": [40, 4, 32, 32], "anchor": [16, 16], "category": "reward_stamp", "reward_tier": 30},
            "coast_stamp_mini": {"rect": [76, 4, 16, 16], "anchor": [8, 8], "category": "reward_stamp", "reward_tier": 30},
            "compass_rose": {"rect": [96, 4, 32, 32], "anchor": [16, 16], "category": "compass"},
            "compass_ring_outer": {"rect": [132, 4, 32, 32], "anchor": [16, 16], "category": "compass"},
            "flower_0": {"rect": [168, 4, 16, 16], "anchor": [8, 8], "category": "completion_flower", "stage": 0},
            "flower_1": {"rect": [188, 4, 16, 16], "anchor": [8, 8], "category": "completion_flower", "stage": 1},
            "flower_2": {"rect": [208, 4, 16, 16], "anchor": [8, 8], "category": "completion_flower", "stage": 2},
            "flower_3": {"rect": [228, 4, 16, 16], "anchor": [8, 8], "category": "completion_flower", "stage": 3},
            "vine_corner_nw": {"rect": [4, 44, 24, 24], "anchor": [4, 4], "category": "reward_frame", "reward_tier": 60},
            "vine_corner_ne": {"rect": [32, 44, 24, 24], "anchor": [20, 4], "category": "reward_frame", "reward_tier": 60},
            "vine_corner_sw": {"rect": [60, 44, 24, 24], "anchor": [4, 20], "category": "reward_frame", "reward_tier": 60},
            "vine_corner_se": {"rect": [88, 44, 24, 24], "anchor": [20, 20], "category": "reward_frame", "reward_tier": 60},
            "vine_border_h": {"rect": [116, 44, 32, 12], "anchor": [16, 6], "category": "reward_frame", "reward_tier": 60, "tileable": "horizontal"},
            "vine_border_v": {"rect": [152, 44, 12, 32], "anchor": [6, 16], "category": "reward_frame", "reward_tier": 60, "tileable": "vertical"},
            "vine_divider": {"rect": [168, 44, 32, 12], "anchor": [16, 6], "category": "reward_frame", "reward_tier": 60},
            "engrave_corner_nw": {"rect": [4, 80, 16, 16], "anchor": [2, 2], "category": "engraving_border"},
            "engrave_corner_ne": {"rect": [24, 80, 16, 16], "anchor": [14, 2], "category": "engraving_border"},
            "engrave_corner_sw": {"rect": [44, 80, 16, 16], "anchor": [2, 14], "category": "engraving_border"},
            "engrave_corner_se": {"rect": [64, 80, 16, 16], "anchor": [14, 14], "category": "engraving_border"},
            "engrave_border_h": {"rect": [84, 80, 32, 8], "anchor": [16, 4], "category": "engraving_border", "tileable": "horizontal"},
            "engrave_border_v": {"rect": [120, 80, 8, 32], "anchor": [4, 16], "category": "engraving_border", "tileable": "vertical"},
            "engrave_divider": {"rect": [132, 80, 48, 12], "anchor": [24, 6], "category": "engraving_border"},
            "seal_locked": {"rect": [184, 80, 16, 16], "anchor": [8, 8], "category": "seal"},
            "seal_unlocked": {"rect": [204, 80, 16, 16], "anchor": [8, 8], "category": "seal"},
            "veil_thread_icon": {"rect": [224, 80, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_waystone": {"rect": [4, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_vista": {"rect": [20, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_chest": {"rect": [36, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_puzzle": {"rect": [52, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_flora": {"rect": [68, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "badge_secret": {"rect": [84, 116, 12, 12], "anchor": [6, 6], "category": "chronicle_badge"},
            "title_ribbon": {"rect": [100, 116, 64, 16], "anchor": [32, 8], "category": "reward_title", "reward_tier": 100, "nine_patch": [12, 4, 12, 4]},
        },
        "sets": {
            "completion_flower": ["flower_0", "flower_1", "flower_2", "flower_3"],
            "silvercoast_frame": {
                "corners": ["vine_corner_nw", "vine_corner_ne", "vine_corner_sw", "vine_corner_se"],
                "h": "vine_border_h",
                "v": "vine_border_v",
                "divider": "vine_divider",
            },
            "stonesetter_frame": {
                "corners": ["engrave_corner_nw", "engrave_corner_ne", "engrave_corner_sw", "engrave_corner_se"],
                "h": "engrave_border_h",
                "v": "engrave_border_v",
                "divider": "engrave_divider",
            },
        },
    }


def _verify_regions(meta: dict, parts: dict[str, list[list[tuple[int, int, int, int]]]]) -> None:
    rects: list[tuple[str, int, int, int, int]] = []
    for key, info in meta["regions"].items():
        rx, ry, rw, rh = info["rect"]
        assert 0 <= rx and 0 <= ry and rx + rw <= SHEET_W and ry + rh <= SHEET_H, f"{key} out of bounds"
        assert len(parts[key]) == rh and len(parts[key][0]) == rw, f"{key} dimension mismatch"
        for okey, ox, oy, ow, oh in rects:
            overlap = not (rx + rw <= ox or ox + ow <= rx or ry + rh <= oy or oy + oh <= ry)
            assert not overlap, f"Region overlap between {key} and {okey}"
        rects.append((key, rx, ry, rw, rh))

    # Verify individual NW->SE lighting (never mirrored/flipped)
    assert parts["vine_corner_ne"] != _flip_h(parts["vine_corner_nw"]), "vine_corner_ne must not be horizontal flip of nw"
    assert parts["vine_corner_sw"] != _flip_v(parts["vine_corner_nw"]), "vine_corner_sw must not be vertical flip of nw"
    assert parts["engrave_corner_ne"] != _flip_h(parts["engrave_corner_nw"]), "engrave_corner_ne must not be horizontal flip"
    assert parts["engrave_corner_sw"] != _flip_v(parts["engrave_corner_nw"]), "engrave_corner_sw must not be vertical flip"

    # Verify tileable seam continuity (horizontal & vertical strips)
    for hkey in ("vine_border_h", "engrave_border_h"):
        grid = parts[hkey]
        # Every row that has non-empty stem at x=0 must match x=w-1 (continuous across wrap)
        y_left = [y for y in range(len(grid)) if grid[y][0][3] > 0]
        y_right = [y for y in range(len(grid)) if grid[y][-1][3] > 0]
        assert y_left == y_right and len(y_left) >= 3, f"{hkey} horizontal seam mismatch: {y_left} vs {y_right}"
    for vkey in ("vine_border_v", "engrave_border_v"):
        grid = parts[vkey]
        x_top = [x for x in range(len(grid[0])) if grid[0][x][3] > 0]
        x_bot = [x for x in range(len(grid[0])) if grid[-1][x][3] > 0]
        assert x_top == x_bot and len(x_top) >= 3, f"{vkey} vertical seam mismatch: {x_top} vs {x_bot}"


def build_4x_atlas(sheet: list[list[tuple[int, int, int, int]]], meta: dict) -> list[list[tuple[int, int, int, int]]]:
    """320 x 264 1x -> 1280 x 1056 4x nearest."""
    lw, lh = 320, 264
    img = [[OUTLINE] * lw for _ in range(lh)]
    regs = meta["regions"]

    # Top-Left Panel (x=4..157, y=4..95): Dark UI #1e1a36 + Silberküsten-Rahmenranke mockup
    for y in range(4, 96):
        for x in range(4, 158):
            img[y][x] = PANEL_DARK
    # Draw assembled Silberküsten frame (exact seamless tiling: corners 24x24, 3x32px H strips, 1x32px V strip -> 144x80)
    fx, fy = 8, 8
    _blit(img, _crop(sheet, regs["vine_corner_nw"]["rect"]), fx, fy)
    _blit(img, _crop(sheet, regs["vine_corner_ne"]["rect"]), fx + 120, fy)
    _blit(img, _crop(sheet, regs["vine_corner_sw"]["rect"]), fx, fy + 56)
    _blit(img, _crop(sheet, regs["vine_corner_se"]["rect"]), fx + 120, fy + 56)
    for tx in range(3):
        _blit(img, _crop(sheet, regs["vine_border_h"]["rect"]), fx + 24 + tx * 32, fy)
        _blit(img, _crop(sheet, regs["vine_border_h"]["rect"]), fx + 24 + tx * 32, fy + 69)
    _blit(img, _crop(sheet, regs["vine_border_v"]["rect"]), fx, fy + 24)
    _blit(img, _crop(sheet, regs["vine_border_v"]["rect"]), fx + 133, fy + 24)
    # Contents inside Dark UI frame
    _blit(img, _crop(sheet, regs["coast_stamp_wax"]["rect"]), 20, 20)
    _blit(img, _crop(sheet, regs["compass_ring_outer"]["rect"]), 56, 20)
    _blit(img, _crop(sheet, regs["compass_rose"]["rect"]), 56, 20)
    _blit(img, _crop(sheet, regs["seal_locked"]["rect"]), 94, 26)
    _blit(img, _crop(sheet, regs["seal_unlocked"]["rect"]), 116, 26)
    _blit(img, _crop(sheet, regs["flower_0"]["rect"]), 18, 54)
    _blit(img, _crop(sheet, regs["flower_1"]["rect"]), 30, 54)
    _blit(img, _crop(sheet, regs["flower_2"]["rect"]), 43, 54)
    _blit(img, _crop(sheet, regs["flower_3"]["rect"]), 57, 54)
    _blit(img, _crop(sheet, regs["title_ribbon"]["rect"]), 75, 55)

    # Top-Right Panel (x=162..315, y=4..95): Parchment #c1a48b + Stone-Setter engraving frame
    parch_a = hexc("c1a48b")
    parch_b = hexc("cdb198")
    for y in range(4, 96):
        for x in range(162, 316):
            img[y][x] = parch_b if ((x // 3 + y // 3) % 4 == 0) else parch_a
    # Exact seamless tiling: corners 16x16, 3x32px H strips, 2x32px V strips (clipped cleanly to 48px) -> 128x80
    ex, ey = 174, 8
    _blit(img, _crop(sheet, regs["engrave_corner_nw"]["rect"]), ex, ey)
    _blit(img, _crop(sheet, regs["engrave_corner_ne"]["rect"]), ex + 112, ey)
    _blit(img, _crop(sheet, regs["engrave_corner_sw"]["rect"]), ex, ey + 64)
    _blit(img, _crop(sheet, regs["engrave_corner_se"]["rect"]), ex + 112, ey + 64)
    for tx in range(3):
        _blit(img, _crop(sheet, regs["engrave_border_h"]["rect"]), ex + 16 + tx * 32, ey)
        _blit(img, _crop(sheet, regs["engrave_border_h"]["rect"]), ex + 16 + tx * 32, ey + 73)
    # Two vertical strips spanning y = ey+16 .. ey+64 (48 px)
    v_strip = _crop(sheet, regs["engrave_border_v"]["rect"])
    _blit(img, v_strip, ex, ey + 16)
    _blit(img, v_strip[:16], ex, ey + 48)
    _blit(img, v_strip, ex + 121, ey + 16)
    _blit(img, v_strip[:16], ex + 121, ey + 48)
    _blit(img, _crop(sheet, regs["coast_stamp_ink"]["rect"]), 196, 16)
    _blit(img, _crop(sheet, regs["coast_stamp_wax"]["rect"]), 244, 16)
    _blit(img, _crop(sheet, regs["engrave_divider"]["rect"]), 214, 49)
    for bi, bkey in enumerate(("veil_thread_icon", "badge_waystone", "badge_vista", "badge_chest", "badge_puzzle", "badge_flora", "badge_secret")):
        _blit(img, _crop(sheet, regs[bkey]["rect"]), 188 + bi * 15, 63)

    # Bottom Panel (y=100..259, x=32..287): Full 256x160 sheet over #171329 with #2a2548 region boxes
    bx, by = 32, 100
    for y in range(SHEET_H):
        for x in range(SHEET_W):
            img[by + y][bx + x] = SLOT_BG
    for info in regs.values():
        rx, ry, rw, rh = info["rect"]
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                if x == rx or x == rx + rw - 1 or y == ry or y == ry + rh - 1:
                    img[by + y][bx + x] = PANEL
    _blit(img, sheet, bx, by, alpha_blend=True)

    scale = 4
    out = [[CLEAR] * (lw * scale) for _ in range(lh * scale)]
    for y in range(lh):
        for sy in range(scale):
            dst_row = out[y * scale + sy]
            for x in range(lw):
                c = img[y][x]
                px_x = x * scale
                for sx in range(scale):
                    dst_row[px_x + sx] = c
    return out


def main() -> None:
    parts: dict[str, list[list[tuple[int, int, int, int]]]] = {
        "coast_stamp_wax": build_coast_stamp_wax(),
        "coast_stamp_ink": build_coast_stamp_ink(),
        "coast_stamp_mini": build_coast_stamp_mini(),
        "compass_rose": build_compass_rose(),
        "compass_ring_outer": build_compass_ring_outer(),
        "flower_0": build_flower(0),
        "flower_1": build_flower(1),
        "flower_2": build_flower(2),
        "flower_3": build_flower(3),
        "vine_corner_nw": build_vine_corner("nw"),
        "vine_corner_ne": build_vine_corner("ne"),
        "vine_corner_sw": build_vine_corner("sw"),
        "vine_corner_se": build_vine_corner("se"),
        "vine_border_h": build_vine_border_h(),
        "vine_border_v": build_vine_border_v(),
        "vine_divider": build_vine_divider(),
        "engrave_corner_nw": build_engrave_corner("nw"),
        "engrave_corner_ne": build_engrave_corner("ne"),
        "engrave_corner_sw": build_engrave_corner("sw"),
        "engrave_corner_se": build_engrave_corner("se"),
        "engrave_border_h": build_engrave_border_h(),
        "engrave_border_v": build_engrave_border_v(),
        "engrave_divider": build_engrave_divider(),
        "seal_locked": build_seal(unlocked=False),
        "seal_unlocked": build_seal(unlocked=True),
        "veil_thread_icon": build_veil_thread_icon(),
        "badge_waystone": build_badge("waystone"),
        "badge_vista": build_badge("vista"),
        "badge_chest": build_badge("chest"),
        "badge_puzzle": build_badge("puzzle"),
        "badge_flora": build_badge("flora"),
        "badge_secret": build_badge("secret"),
        "title_ribbon": build_title_ribbon(),
    }

    meta = build_metadata()
    _verify_regions(meta, parts)

    sheet = make_grid(SHEET_W, SHEET_H)
    for key, info in meta["regions"].items():
        rx, ry, _, _ = info["rect"]
        _blit(sheet, parts[key], rx, ry, alpha_blend=False)

    atlas = build_4x_atlas(sheet, meta)

    verify_no_black("atlas_elements.png", sheet)
    verify_no_black("atlas_elements_atlas_4x.png", atlas)

    ui_dir = ROOT / "ui"
    data_path = ROOT.parent / "data" / "atlas_elements_art.json"
    atlas_path = ROOT.parent / "docs" / "img" / "atlas_elements_atlas_4x.png"
    write_png(ui_dir / "atlas_elements.png", SHEET_W, SHEET_H, sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    data_path.write_text(json.dumps(meta, indent="\t") + "\n", encoding="utf-8")
    print(f"Wrote {ui_dir / 'atlas_elements.png'} ({SHEET_W}x{SHEET_H}), {data_path.name}, and {atlas_path} ({len(atlas[0])}x{len(atlas)})")


if __name__ == "__main__":
    main()
