#!/usr/bin/env python3
"""Procedural pixel-art generator for WINDKAP's 3 Physically Blocked Inland Thresholds.

Outputs:
  assets/props/threshold_blockers.png       288x128 (3 cols x 2 rows of 96x64), anchor (48, 54)
  assets/props/threshold_blockers_glow.png  288x128 unlit emissive mask
  data/threshold_blockers_art.json          Regions, ground rows, anchors, colliders
  docs/img/threshold_blockers_atlas_4x.png  1248x864 (4x nearest) Day Blocked / Day Open / Night QA sheet

Grid (96x64 per cell):
  Row 0: mossy_rockfall, collapsed_arch, bramble_wall
  Row 1: mossy_rockfall_open, collapsed_arch_open, bramble_wall_open
"""
from __future__ import annotations

import json
import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import (  # noqa: E402
    GOLD_0,
    GOLD_1,
    GOLD_2,
    GOLD_3,
    IVY_0,
    IVY_1,
    IVY_2,
    IVY_3,
    LICHEN_GOLD,
    LICHEN_SILVER,
    LIMESTONE,
    MOSS_0,
    MOSS_1,
    MOSS_2,
    MOSS_3,
    MOSS_4,
    SLATE,
    TRAVERTINE,
    blend_over,
    h2,
    make_grid,
)

# ---------------------------------------------------------------------------
# Sheet & Cell Constants
# ---------------------------------------------------------------------------
CELL_W = 96
CELL_H = 64
COLS = 3
ROWS = 2
SHEET_W = CELL_W * COLS
SHEET_H = CELL_H * ROWS
ANCHOR_X = 48
GROUND_Y = 54

# ---------------------------------------------------------------------------
# Palettes (Zero #000000)
# ---------------------------------------------------------------------------
OUT_STONE = hexc("1b1a2e")
OUT_LEAF = hexc("122228")
OUT_WARM = hexc("231729")
MORTAR_DEEP = hexc("171528")
SHADOW_RGB = (15, 16, 34)

GOLD = [GOLD_0, GOLD_1, GOLD_2, GOLD_3]
MOSS = [MOSS_0, MOSS_1, MOSS_2, MOSS_3, MOSS_4]
IVY = [IVY_0, IVY_1, IVY_2, IVY_3]
EARTH_LOAM = [hexc(c) for c in ("1c1524", "2a1f31", "3c2d3f", "523e4f", "6b5261")]
BRAMBLE_LEAF = [hexc(c) for c in ("12223a", "1b3844", "26544e", "387858", "54a068")]
BRAMBLE_CANE = [hexc(c) for c in ("1d1222", "341e32", "523044", "764a5c", "a87c86")]

RUNE_DIM = (42, 140, 148, 255)
RUNE_LIT = (120, 244, 230, 255)
RUNE_CORE = (208, 255, 248, 255)
GOLD_GLOW = (230, 196, 104, 180)
THORN_VIO_DIM = (102, 54, 173, 255)
THORN_VIO_HI = (203, 170, 255, 255)
EMBER_GLOW = (255, 138, 58, 255)
EMBER_CORE = (255, 240, 176, 255)

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def clamp_idx(i: int, n: int) -> int:
    return 0 if i < 0 else (n - 1 if i >= n else i)


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


def _draw_boulder(
    px: list[list[tuple[int, int, int, int]]],
    kind: list[list[str]],
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    ramp: list[tuple[int, int, int, int]],
    seed: int,
    angularity: float = 0.22,
) -> None:
    """Draws an angular fractured boulder with NW->SE lighting, facet steps & 4-connected clusters."""
    mask: set[tuple[int, int]] = set()
    x0 = max(1, int(cx - rx - 2))
    x1 = min(CELL_W - 2, int(cx + rx + 2))
    y0 = max(1, int(cy - ry - 2))
    y1 = min(CELL_H - 2, int(cy + ry + 2))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x - cx) / max(1.0, rx)
            ny = (y - cy) / max(1.0, ry)
            ang = math.atan2(ny, nx)
            facet = angularity * (math.sin(ang * 3.0 + seed) * 0.6 + math.cos(ang * 5.0 - seed * 1.4) * 0.4)
            d = (abs(nx) ** 2.6 + abs(ny) ** 2.6) ** (1.0 / 2.6)
            if d <= 1.0 + facet:
                mask.add((x, y))
    # Prune orphan 1-neighbor pixels
    clean = {
        (x, y)
        for (x, y) in mask
        if sum((x + dx, y + dy) in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 2
    }
    for x, y in clean:
        nx = (x - cx) / max(1.0, rx)
        ny = (y - cy) / max(1.0, ry)
        lit = -0.55 * nx - 0.80 * ny
        # Facet bevel edge detection
        is_nw_edge = (x - 1, y) not in clean or (x, y - 1) not in clean
        is_se_edge = (x + 1, y) not in clean or (x, y + 1) not in clean
        b = (BAYER[y & 3][x & 3] / 15.0 - 0.5) * 0.16
        t = clamp(0.48 + lit * 0.48 + b, 0.0, 1.0)
        idx = clamp_idx(int(round(t * (len(ramp) - 2))) + 1, len(ramp))
        if is_nw_edge and lit > -0.1:
            idx = min(len(ramp) - 1, idx + 1)
        if is_se_edge:
            idx = max(0, idx - 1)
        px[y][x] = ramp[idx]
        kind[y][x] = "stone"


def _draw_stone_slab(
    px: list[list[tuple[int, int, int, int]]],
    kind: list[list[str]],
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    ramp: list[tuple[int, int, int, int]],
    seed: int,
) -> None:
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)
    bias = (h2(x0, y0, seed) - 0.5) * 0.16
    for y in range(max(1, y0), min(CELL_H - 1, y1 + 1)):
        for x in range(max(1, x0), min(CELL_W - 1, x1 + 1)):
            nx = ((x - x0) / w) * 2.0 - 1.0
            ny = ((y - y0) / h) * 2.0 - 1.0
            lit = -0.55 * nx - 0.80 * ny + bias
            b = (BAYER[y & 3][x & 3] / 15.0 - 0.5) * 0.14
            t = clamp(0.48 + lit * 0.45 + b, 0.0, 1.0)
            idx = clamp_idx(int(round(t * (len(ramp) - 2))) + 1, len(ramp))
            if y == y0 or x == x0:
                idx = min(len(ramp) - 1, idx + 1)
            if y == y1 or x == x1:
                idx = max(0, idx - 1)
            px[y][x] = ramp[idx]
            kind[y][x] = "stone"


def _draw_moss(
    px: list[list[tuple[int, int, int, int]]],
    kind: list[list[str]],
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    seed: int,
    ramp: list[tuple[int, int, int, int]] = MOSS,
    tag: str = "leaf",
) -> None:
    mask: set[tuple[int, int]] = set()
    for y in range(max(1, int(cy - ry - 1)), min(CELL_H - 1, int(cy + ry + 2))):
        for x in range(max(1, int(cx - rx - 1)), min(CELL_W - 1, int(cx + rx + 2))):
            nx = (x - cx) / max(0.8, rx)
            ny = (y - cy) / max(0.8, ry)
            wob = 0.22 * math.sin(x * 0.8 + seed) + 0.14 * math.cos(y * 0.9 - seed)
            if nx * nx + ny * ny <= 1.0 + wob:
                mask.add((x, y))
    clean = {
        (x, y)
        for (x, y) in mask
        if sum((x + dx, y + dy) in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 2
    }
    for x, y in clean:
        nx = (x - cx) / max(0.8, rx)
        ny = (y - cy) / max(0.8, ry)
        lit = -0.55 * nx - 0.80 * ny
        b = (BAYER[y & 3][x & 3] / 15.0 - 0.5) * 0.20
        t = clamp(0.46 + lit * 0.46 + b, 0.0, 1.0)
        idx = clamp_idx(int(round(t * (len(ramp) - 1))), len(ramp))
        px[y][x] = ramp[idx]
        kind[y][x] = tag


def _draw_4conn_cane(
    px: list[list[tuple[int, int, int, int]]],
    kind: list[list[str]],
    pts: list[tuple[float, float]],
    thickness: float = 1.1,
    thorns: bool = True,
    seed: int = 1,
) -> None:
    """Draws a 4-connected thorny bramble cane along a polyline with pale thorns."""
    prev_ix, prev_iy = int(round(pts[0][0])), int(round(pts[0][1]))
    steps_drawn = 0
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        n = max(2, int(math.hypot(bx - ax, by - ay) * 2))
        for k in range(n + 1):
            t = k / n
            fx = ax + (bx - ax) * t
            fy = ay + (by - ay) * t
            ix, iy = int(round(fx)), int(round(fy))
            # Bridge any diagonal step cleanly for strict 4-connectivity
            if ix != prev_ix and iy != prev_iy:
                if 1 <= prev_iy < CELL_H - 1 and 1 <= ix < CELL_W - 1:
                    px[prev_iy][ix] = BRAMBLE_CANE[1]
                    kind[prev_iy][ix] = "warm"
            if 2 <= iy < CELL_H - 2 and 2 <= ix < CELL_W - 2:
                # Top-left highlight, bottom-right dark cane core
                px[iy][ix] = BRAMBLE_CANE[2]
                kind[iy][ix] = "warm"
                if thickness >= 1.0:
                    px[iy - 1][ix] = BRAMBLE_CANE[3]
                    px[iy + 1][ix] = BRAMBLE_CANE[0]
                    kind[iy - 1][ix] = kind[iy + 1][ix] = "warm"
                if thorns and steps_drawn % 6 == 3:
                    # Short 2px thorn perpendicular-upward
                    tx = ix + (1 if (steps_drawn + seed) % 2 == 0 else -1)
                    ty = iy - 2 if iy > 3 else iy + 2
                    px[iy - 1][tx] = BRAMBLE_CANE[3]
                    px[ty][tx] = BRAMBLE_CANE[4]
                    kind[iy - 1][tx] = kind[ty][tx] = "warm"
            prev_ix, prev_iy = ix, iy
            steps_drawn += 1


def _finalize_cell(
    px: list[list[tuple[int, int, int, int]]],
    kind: list[list[str]],
    no_outline: list[list[bool]],
    shadow_ellipses: list[tuple[float, float, float, float]],
) -> list[list[tuple[int, int, int, int]]]:
    out = [row[:] for row in px]
    for y in range(CELL_H):
        for x in range(CELL_W):
            if px[y][x][3] > 0 or no_outline[y][x]:
                continue
            counts = {"stone": 0, "leaf": 0, "warm": 0}
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < CELL_W and 0 <= ny < CELL_H and px[ny][nx][3] >= 200 and not no_outline[ny][nx]:
                    t = kind[ny][nx]
                    if t in counts:
                        counts[t] += 1
            tot = sum(counts.values())
            if tot > 0:
                dom = max(counts, key=lambda k: counts[k])
                out[y][x] = OUT_LEAF if dom == "leaf" else (OUT_WARM if dom == "warm" else OUT_STONE)

    final_px = make_grid(CELL_W, CELL_H)
    for y in range(CELL_H):
        for x in range(CELL_W):
            sh = CLEAR
            for cx, cy, rx, ry in shadow_ellipses:
                d = math.hypot((x - cx) / rx, (y - cy) / ry)
                if d <= 1.0:
                    a = 110 if d < 0.55 else (76 if d < 0.80 else 44)
                    if a > sh[3]:
                        sh = (SHADOW_RGB[0], SHADOW_RGB[1], SHADOW_RGB[2], a)
            final_px[y][x] = blend_over(sh, out[y][x])
    return final_px


def build_mossy_rockfall(open_state: bool) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(CELL_W, CELL_H)
    kind = [["none"] * CELL_W for _ in range(CELL_H)]
    no_out = [[False] * CELL_W for _ in range(CELL_H)]
    glow = GlowMap(CELL_W, CELL_H)

    if not open_state:
        # Earth loam scree apron
        _draw_moss(px, kind, 48, 51, 38, 6.0, 11, EARTH_LOAM, "warm")
        # Massive interlocked angular boulder wedge (back -> front)
        _draw_boulder(px, kind, 34, 34, 14, 12, SLATE, 1)
        _draw_boulder(px, kind, 60, 35, 15, 12, LIMESTONE, 2)
        _draw_boulder(px, kind, 48, 28, 17, 15, TRAVERTINE, 3)
        _draw_boulder(px, kind, 21, 44, 13, 10, LIMESTONE, 4)
        _draw_boulder(px, kind, 75, 45, 13, 10, SLATE, 5)
        _draw_boulder(px, kind, 38, 45, 14, 10, TRAVERTINE, 6)
        _draw_boulder(px, kind, 57, 46, 14, 10, SLATE, 7)
        # Smaller foreground scree stones
        _draw_boulder(px, kind, 11, 51, 5, 3.5, LIMESTONE, 8)
        _draw_boulder(px, kind, 85, 51, 5, 3.5, TRAVERTINE, 9)
        _draw_boulder(px, kind, 48, 52, 6, 3.5, SLATE, 10)
        # Overhanging moss cushions
        _draw_moss(px, kind, 44, 21, 9, 4, 20)
        _draw_moss(px, kind, 28, 30, 7, 3.5, 21)
        _draw_moss(px, kind, 64, 31, 6, 3, 22)
        _draw_moss(px, kind, 20, 41, 6, 3, 23)
        _draw_moss(px, kind, 74, 42, 5, 2.5, 24)
        # Lichen rosettes
        for lx, ly, pair in ((49, 27, LICHEN_SILVER), (36, 42, LICHEN_GOLD), (60, 42, LICHEN_SILVER)):
            px[ly][lx] = pair[1]
            px[ly][lx + 1] = pair[1]
            px[ly + 1][lx] = pair[0]
        # 3 trapped glowing turquoise crystal/spore fissures in lower crevices
        for cx, cy in ((31, 46), (51, 43), (66, 47)):
            glow.emit(px, cx, cy, RUNE_DIM, RUNE_LIT, halo=1)
            glow.emit(px, cx + 1, cy, RUNE_LIT, RUNE_CORE, halo=1)
            glow.emit(px, cx, cy + 1, RUNE_DIM, RUNE_DIM, halo=1)
        shadows = [(48.0, 54.0, 43.0, 8.0)]
    else:
        # Cleared center path with gravel/stepping slabs & parted flank boulders
        for sx, sy, w, h, sd in ((34, 47, 10, 5, 1), (45, 49, 11, 5, 2), (55, 46, 9, 5, 3)):
            _draw_stone_slab(px, kind, sx, sy, sx + w, sy + h, LIMESTONE, sd)
            for y in range(sy, sy + h + 1):
                for x in range(sx, sx + w + 1):
                    no_out[y][x] = True
        _draw_boulder(px, kind, 15, 39, 11, 10, SLATE, 31)
        _draw_boulder(px, kind, 21, 47, 9, 7, LIMESTONE, 32)
        _draw_boulder(px, kind, 81, 40, 11, 10, LIMESTONE, 33)
        _draw_boulder(px, kind, 75, 48, 9, 7, SLATE, 34)
        _draw_moss(px, kind, 14, 34, 6, 3, 35)
        _draw_moss(px, kind, 80, 35, 6, 3, 36)
        shadows = [(18.0, 54.0, 14.0, 5.5), (78.0, 54.0, 14.0, 5.5)]

    final_px = _finalize_cell(px, kind, no_out, shadows)
    return final_px, glow.finish()


def build_collapsed_arch(open_state: bool) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(CELL_W, CELL_H)
    kind = [["none"] * CELL_W for _ in range(CELL_H)]
    no_out = [[False] * CELL_W for _ in range(CELL_H)]
    glow = GlowMap(CELL_W, CELL_H)

    # Left and right Stone-Setter gate piers (present in both blocked and open states)
    for x0, y0, x1, y1, rmp, sd in (
        (9, 44, 27, 53, SLATE, 1),
        (11, 32, 26, 43, LIMESTONE, 2),
        (12, 20, 25, 31, TRAVERTINE, 3),
        (11, 14, 26, 19, LIMESTONE, 4),
        (69, 44, 87, 53, SLATE, 5),
        (70, 32, 85, 43, LIMESTONE, 6),
        (71, 20, 84, 31, TRAVERTINE, 7),
        (70, 14, 85, 19, LIMESTONE, 8),
    ):
        _draw_stone_slab(px, kind, x0, y0, x1, y1, rmp, sd)

    # Mortar courses on piers
    for y in (19, 31, 43):
        for x in range(11, 27):
            px[y][x] = MORTAR_DEEP
        for x in range(70, 86):
            px[y][x] = MORTAR_DEEP

    if not open_state:
        # Fallen carved voussoir & keystone jammed across the threshold
        _draw_stone_slab(px, kind, 25, 37, 43, 52, LIMESTONE, 11)
        _draw_stone_slab(px, kind, 52, 36, 71, 52, SLATE, 12)
        # Tilted keystone arch block resting in center (x=37..59, y=26..48)
        _draw_boulder(px, kind, 48, 38, 12, 11, TRAVERTINE, 13, angularity=0.14)
        # Exposed rubble pocket inside broken upper piers
        _draw_boulder(px, kind, 24, 21, 5, 4, SLATE, 14)
        _draw_boulder(px, kind, 71, 22, 5, 4, SLATE, 15)
        # Gold filigree inlay on keystone
        for gx, gy in ((46, 34), (47, 33), (48, 33), (49, 34), (48, 35), (47, 35)):
            px[gy][gx] = GOLD[2] if gy <= 34 else GOLD[1]
            glow.emit(px, gx, gy, GOLD[2], GOLD_GLOW, halo=1)
        # Turquoise fractured rune lines on fallen keystone & piers
        for rx, ry in ((18, 25), (18, 26), (18, 27), (77, 25), (77, 26), (77, 27), (44, 39), (45, 40), (51, 39), (52, 40)):
            glow.emit(px, rx, ry, RUNE_DIM, RUNE_LIT, halo=1)
        glow.emit(px, 48, 34, RUNE_LIT, RUNE_CORE, halo=2)
        # Moss & creeping ivy
        _draw_moss(px, kind, 18, 14, 7, 3, 41)
        _draw_moss(px, kind, 78, 14, 7, 3, 42)
        _draw_moss(px, kind, 40, 30, 5, 2.5, 43)
        _draw_moss(px, kind, 59, 46, 5, 2.5, 44)
        shadows = [(48.0, 54.0, 44.0, 8.0)]
    else:
        # Flat stone paving slabs across open 40px center passage
        for sx, sy, w, h, sd in ((28, 48, 12, 5, 21), (41, 47, 14, 6, 22), (56, 48, 12, 5, 23)):
            _draw_stone_slab(px, kind, sx, sy, sx + w, sy + h, TRAVERTINE, sd)
            for y in range(sy, sy + h + 1):
                for x in range(sx, sx + w + 1):
                    no_out[y][x] = True
        # Awakened glowing turquoise wayfarer runes on both intact piers
        for ry in range(22, 30):
            glow.emit(px, 18, ry, RUNE_LIT, RUNE_CORE if ry in (24, 25) else RUNE_LIT, halo=1)
            glow.emit(px, 77, ry, RUNE_LIT, RUNE_CORE if ry in (24, 25) else RUNE_LIT, halo=1)
        _draw_moss(px, kind, 18, 14, 6, 2.5, 45)
        _draw_moss(px, kind, 78, 14, 6, 2.5, 46)
        shadows = [(18.0, 54.0, 12.0, 5.0), (78.0, 54.0, 12.0, 5.0)]

    final_px = _finalize_cell(px, kind, no_out, shadows)
    return final_px, glow.finish()


def build_bramble_wall(open_state: bool) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    px = make_grid(CELL_W, CELL_H)
    kind = [["none"] * CELL_W for _ in range(CELL_H)]
    no_out = [[False] * CELL_W for _ in range(CELL_H)]
    glow = GlowMap(CELL_W, CELL_H)

    if not open_state:
        # Dense dark-emerald interior thicket cushion
        for cx, cy, rx, ry, sd in (
            (48, 36, 37, 16, 1),
            (25, 41, 18, 12, 2),
            (71, 41, 18, 12, 3),
            (48, 25, 23, 12, 4),
        ):
            _draw_moss(px, kind, cx, cy, rx, ry, sd, BRAMBLE_LEAF, "leaf")
        # Interlocking 4-connected thorny plum-bark canes forming an arched barricade
        canes = [
            [(8, 52), (18, 35), (34, 22), (52, 19), (70, 26), (86, 44)],
            [(12, 47), (26, 48), (44, 34), (62, 24), (80, 32), (89, 51)],
            [(14, 36), (30, 29), (48, 38), (66, 46), (84, 48)],
            [(22, 53), (38, 41), (56, 30), (74, 37), (87, 46)],
        ]
        for idx, cpts in enumerate(canes):
            _draw_4conn_cane(px, kind, cpts, thickness=1.1, thorns=True, seed=idx + 1)
        # Glowing violet & amber void-ember briar buds
        buds = [
            (24, 33, THORN_VIO_DIM, THORN_VIO_HI),
            (39, 25, EMBER_GLOW, EMBER_CORE),
            (50, 33, THORN_VIO_DIM, THORN_VIO_HI),
            (63, 27, EMBER_GLOW, EMBER_CORE),
            (74, 38, THORN_VIO_DIM, THORN_VIO_HI),
            (32, 44, EMBER_GLOW, EMBER_CORE),
        ]
        for bx, by, dim_c, hi_c in buds:
            glow.emit(px, bx, by, dim_c, hi_c, halo=2)
            glow.emit(px, bx + 1, by, dim_c, dim_c, halo=1)
        shadows = [(48.0, 54.0, 44.0, 8.0)]
    else:
        # Cut-back thorny briar flanking mounds left & right with severed cane stubs
        _draw_moss(px, kind, 16, 43, 12, 10, 11, BRAMBLE_LEAF, "leaf")
        _draw_moss(px, kind, 80, 43, 12, 10, 12, BRAMBLE_LEAF, "leaf")
        _draw_4conn_cane(px, kind, [(6, 51), (14, 39), (26, 35)], thickness=1.0, thorns=True, seed=7)
        _draw_4conn_cane(px, kind, [(90, 51), (82, 39), (70, 36)], thickness=1.0, thorns=True, seed=8)
        # Severed woody twig stubs in cleared middle (clean 3x2 clusters, no isolated 1px dots)
        for sx, sy in ((35, 51), (47, 50), (60, 51)):
            px[sy][sx] = BRAMBLE_CANE[1]
            px[sy][sx + 1] = BRAMBLE_CANE[2]
            px[sy - 1][sx + 1] = BRAMBLE_CANE[3]
            px[sy - 1][sx + 2] = BRAMBLE_CANE[4]
            for tx, ty in ((sx, sy), (sx + 1, sy), (sx + 1, sy - 1), (sx + 2, sy - 1)):
                kind[ty][tx] = "warm"
                no_out[ty][tx] = True
        glow.emit(px, 15, 38, THORN_VIO_DIM, THORN_VIO_HI, halo=1)
        glow.emit(px, 81, 38, THORN_VIO_DIM, THORN_VIO_HI, halo=1)
        shadows = [(16.0, 54.0, 13.0, 5.5), (80.0, 54.0, 13.0, 5.5)]

    final_px = _finalize_cell(px, kind, no_out, shadows)
    return final_px, glow.finish()


def _tint_night(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    out = make_grid(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(6, int(c[0] * 0.42)), max(7, int(c[1] * 0.48)), max(14, int(c[2] * 0.68)), c[3])
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
                min(255, int(dc[0] * (1.0 - 0.45 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.45 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.45 * f) + gc[2] * f * 1.35)),
                255,
            )


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


def build_4x_atlas(cells: dict[tuple[int, int], tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]]) -> list[list[tuple[int, int, int, int]]]:
    """312 x 216 1x (3 cols x 3 rows of 96x64 with 6 px #1b1a2e gutters) -> 1248 x 864 4x nearest."""
    gutter = 6
    lw = gutter * 4 + CELL_W * 3
    lh = gutter * 4 + CELL_H * 3
    img = [[OUT_STONE] * lw for _ in range(lh)]

    for r_idx, (src_row, night) in enumerate(((0, False), (1, False), (0, True))):
        oy = gutter + r_idx * (CELL_H + gutter)
        for col in range(3):
            ox = gutter + col * (CELL_W + gutter)
            bg_a = hexc("14192c") if night else hexc("356b4d")
            bg_b = hexc("182036") if night else hexc("3e7d56")
            for y in range(CELL_H):
                for x in range(CELL_W):
                    stripe = ((x // 4 + y // 3) % 5 == 0)
                    img[oy + y][ox + x] = bg_b if stripe else bg_a
            base, gl = cells[(col, src_row)]
            _blit(img, _tint_night(base) if night else base, ox, oy, alpha_blend=True)
            if night:
                _add_glow(img, gl, ox, oy)

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


def build_metadata() -> dict:
    return {
        "sheet": "res://assets/props/threshold_blockers.png",
        "glow_sheet": "res://assets/props/threshold_blockers_glow.png",
        "sheet_size": [SHEET_W, SHEET_H],
        "mossy_rockfall": {
            "rect": [0, 0, 96, 64],
            "open_rect": [0, 64, 96, 64],
            "frame": [96, 64],
            "ground": GROUND_Y,
            "anchor": [ANCHOR_X, GROUND_Y],
            "offset": [-ANCHOR_X, -GROUND_Y],
            "cols": COLS,
            "rows": ROWS,
            "col": 0,
            "row": 0,
            "foot": [80, 18],
            "colliders": [[-40, -16, 80, 18]],
            "open_colliders": [[-44, -14, 24, 16], [20, -14, 24, 16]],
            "prompt_anchor": [0, -44],
            "light_pos": [0, -12],
            "light_color": "78f4e6",
        },
        "collapsed_arch": {
            "rect": [96, 0, 96, 64],
            "open_rect": [96, 64, 96, 64],
            "frame": [96, 64],
            "ground": GROUND_Y,
            "anchor": [ANCHOR_X, GROUND_Y],
            "offset": [-ANCHOR_X, -GROUND_Y],
            "cols": COLS,
            "rows": ROWS,
            "col": 1,
            "row": 0,
            "foot": [82, 18],
            "colliders": [[-41, -16, 82, 18]],
            "open_colliders": [[-41, -16, 20, 18], [21, -16, 20, 18]],
            "prompt_anchor": [0, -50],
            "light_pos": [0, -14],
            "light_color": "78f4e6",
        },
        "bramble_wall": {
            "rect": [192, 0, 96, 64],
            "open_rect": [192, 64, 96, 64],
            "frame": [96, 64],
            "ground": GROUND_Y,
            "anchor": [ANCHOR_X, GROUND_Y],
            "offset": [-ANCHOR_X, -GROUND_Y],
            "cols": COLS,
            "rows": ROWS,
            "col": 2,
            "row": 0,
            "foot": [84, 16],
            "colliders": [[-42, -14, 84, 16]],
            "open_colliders": [[-44, -13, 24, 14], [20, -13, 24, 14]],
            "prompt_anchor": [0, -46],
            "light_pos": [0, -12],
            "light_color": "cbaaff",
        },
    }


def main() -> None:
    cells = {
        (0, 0): build_mossy_rockfall(open_state=False),
        (1, 0): build_collapsed_arch(open_state=False),
        (2, 0): build_bramble_wall(open_state=False),
        (0, 1): build_mossy_rockfall(open_state=True),
        (1, 1): build_collapsed_arch(open_state=True),
        (2, 1): build_bramble_wall(open_state=True),
    }

    sheet = make_grid(SHEET_W, SHEET_H)
    glow_sheet = make_grid(SHEET_W, SHEET_H)
    for (col, row), (base, gl) in cells.items():
        assert len(base) == CELL_H and len(base[0]) == CELL_W
        assert len(gl) == CELL_H and len(gl[0]) == CELL_W
        _blit(sheet, base, col * CELL_W, row * CELL_H, alpha_blend=False)
        _blit(glow_sheet, gl, col * CELL_W, row * CELL_H, alpha_blend=False)

    atlas = build_4x_atlas(cells)

    verify_no_black("threshold_blockers.png", sheet)
    verify_no_black("threshold_blockers_glow.png", glow_sheet)
    verify_no_black("threshold_blockers_atlas_4x.png", atlas)

    props_dir = ROOT / "props"
    data_path = ROOT.parent / "data" / "threshold_blockers_art.json"
    atlas_path = ROOT.parent / "docs" / "img" / "threshold_blockers_atlas_4x.png"
    write_png(props_dir / "threshold_blockers.png", SHEET_W, SHEET_H, sheet)
    write_png(props_dir / "threshold_blockers_glow.png", SHEET_W, SHEET_H, glow_sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    data_path.write_text(json.dumps(build_metadata(), indent="\t") + "\n", encoding="utf-8")
    print(f"Wrote {props_dir / 'threshold_blockers.png'} ({SHEET_W}x{SHEET_H}), _glow.png, {data_path.name}, and {atlas_path} ({len(atlas[0])}x{len(atlas)})")


if __name__ == "__main__":
    main()
