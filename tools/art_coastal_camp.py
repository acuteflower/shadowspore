#!/usr/bin/env python3
"""Procedural pixel-art generator for WINDKAP's Die Silberbucht Coastal Camp Props.

Outputs:
  assets/props/coastal_camp.png       256x192 aligned row sprite atlas
  assets/props/coastal_camp_glow.png  256x192 unlit emissive glow mask (embers, flames, chest & gem glints)
  data/coastal_camp_art.json          Exact regions, frames, ground anchors, colliders, seats
  docs/img/coastal_camp_atlas_4x.png  1152x1088 (4x nearest) Day raw sheet + Night diorama QA sheet
"""
from __future__ import annotations

import json
import math
import pathlib
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402
from art_ancient_stones import TRAVERTINE, blend_over, h2, make_grid  # noqa: E402

# ---------------------------------------------------------------------------
# Sheet Constants
# ---------------------------------------------------------------------------
SHEET_W = 256
SHEET_H = 192

# ---------------------------------------------------------------------------
# Palettes (Zero #000000)
# ---------------------------------------------------------------------------
INK = hexc("1b1a2e")
DRIFT_OUTLINE = hexc("342d38")
OUT_WARM = hexc("231729")
SHADOW_RGB = (15, 16, 34)

DRIFTWOOD = [hexc(c) for c in ("332834", "4f3f48", "725e62", "98827e", "bfab9d", "dcc8b0")]
WOOD_CRATE = [hexc(c) for c in ("2b1f27", "4b3741", "765862", "a6838a")]
RUST_BRONZE = [hexc(c) for c in ("1d1216", "3b2124", "6b3a2c", "a05c3a")]
COAST_STONE = [hexc(c) for c in ("262936", "3f4556", "5d6575", "7f8896", "a8b1bc")]
CHAR_ASH = [hexc(c) for c in ("120d16", "251d2e", "3f394f", "7f7893", "a8a2b8")]
CLOTH_CANVAS = [hexc(c) for c in ("2c283b", "3f3a51", "565069", "716b84", "908aa3", "b3adc4")]
SEA_KELP = [hexc(c) for c in ("1f5a5a", "2a7a74", "3f9a8c", "62bcac")]

# Weapons (matching tools/art_weapons.py)
STEEL = [hexc(c) for c in ("343b58", "5b6684", "93a0bc", "d4dbec", "f6f9ff")]
GOLD = [hexc(c) for c in ("6a4a2a", "a07a3a", "d8b45a", "f6e0a0")]
LEATHER = [hexc(c) for c in ("2a1a4a", "46308a", "6a4bd0", "9a82f0")]
SWORD_GEM = hexc("b99bff")
STONE_TOOL = [hexc(c) for c in ("363046", "524b64", "746d86", "9e98ae")]
TIMBER = [hexc(c) for c in ("382538", "5c4048", "82605c", "a68378")]
CORD = [hexc(c) for c in ("483844", "6e5a56", "967e6a", "baa288")]

# Glow & Fire ramps
FIRE = [hexc(c) for c in ("8a2410", "e0601a", "ffa63a", "ffeaa0")]
EMBER_GLOW = [hexc(c) for c in ("c23b4b", "ff8e47", "ffd89a")]
TEAL_GLINT = [hexc(c) for c in ("3cc0c6", "78f4e6")]
SWORD_GEM_GLOW = (185, 155, 255, 210)

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


def _outline_and_shadow(
    px: list[list[tuple[int, int, int, int]]],
    outline_col: tuple[int, int, int, int],
    shadows: list[tuple[float, float, float, float]],
    skip_bottom_from_y: int = 999,
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    out = [row[:] for row in px]
    for y in range(h):
        if y >= skip_bottom_from_y:
            continue
        for x in range(w):
            if px[y][x][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= 200:
                    out[y][x] = outline_col
                    break
    final_px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            sh = CLEAR
            for cx, cy, rx, ry in shadows:
                d = math.hypot((x - cx) / rx, (y - cy) / ry)
                if d <= 1.0:
                    a = 104 if d < 0.52 else (72 if d < 0.80 else 42)
                    if a > sh[3]:
                        sh = (SHADOW_RGB[0], SHADOW_RGB[1], SHADOW_RGB[2], a)
            final_px[y][x] = blend_over(sh, out[y][x])
    return final_px


def _draw_ellipse_shaded(
    px: list[list[tuple[int, int, int, int]]],
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    ramp: list[tuple[int, int, int, int]],
    seed: int,
) -> None:
    h, w = len(px), len(px[0])
    for y in range(max(1, int(cy - ry - 1)), min(h - 1, int(cy + ry + 2))):
        for x in range(max(1, int(cx - rx - 1)), min(w - 1, int(cx + rx + 2))):
            nx = (x - cx) / max(0.8, rx)
            ny = (y - cy) / max(0.8, ry)
            if nx * nx + ny * ny <= 1.0:
                lit = -0.55 * nx - 0.80 * ny + (h2(x // 2, y // 2, seed) - 0.5) * 0.14
                b = (BAYER[y & 3][x & 3] / 15.0 - 0.5) * 0.16
                t = clamp(0.48 + lit * 0.48 + b, 0.0, 1.0)
                idx = clamp_idx(int(round(t * (len(ramp) - 1))), len(ramp))
                px[y][x] = ramp[idx]


def _draw_box_shaded(
    px: list[list[tuple[int, int, int, int]]],
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    ramp: list[tuple[int, int, int, int]],
    seed: int = 1,
) -> None:
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= y < len(px) and 0 <= x < len(px[0]):
                nx = ((x - x0) / w) * 2.0 - 1.0
                ny = ((y - y0) / h) * 2.0 - 1.0
                lit = -0.55 * nx - 0.80 * ny + (h2(x // 2, y // 2, seed) - 0.5) * 0.12
                t = clamp(0.48 + lit * 0.44, 0.0, 1.0)
                idx = clamp_idx(int(round(t * (len(ramp) - 2))) + 1, len(ramp))
                if y == y0 or x == x0:
                    idx = min(len(ramp) - 1, idx + 1)
                if y == y1 or x == x1:
                    idx = max(0, idx - 1)
                px[y][x] = ramp[idx]


def build_campfire(lit_state: bool) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 64, 48
    px = make_grid(w, h)
    glow = GlowMap(w, h)
    cx, cy = 32.0, 30.0
    # Sunken ash bed inside ring
    for y in range(20, 39):
        for x in range(14, 51):
            d = math.hypot((x - cx) / 17.5, (y - cy) / 8.5)
            if d <= 1.0:
                idx = 0 if d > 0.72 else (1 if (x + y) % 3 == 0 else 2)
                px[y][x] = CHAR_ASH[idx]

    # Crossed charred driftwood billets in center
    for i in range(-9, 10):
        bx = int(round(cx + i))
        by1 = int(round(cy - 1 + i * 0.28))
        by2 = int(round(cy + 1 - i * 0.25))
        for yy in (by1, by1 + 1):
            if 0 <= yy < h:
                px[yy][bx] = CHAR_ASH[1] if abs(i) < 4 else DRIFTWOOD[1]
        for yy in (by2, by2 + 1):
            if 0 <= yy < h:
                px[yy][bx] = CHAR_ASH[0] if abs(i) < 4 else DRIFTWOOD[2]

    if lit_state:
        # Glowing ember bed & billet seams
        embers = [
            (28, 29, 1), (29, 29, 2), (30, 30, 2), (31, 30, 2), (32, 29, 2),
            (33, 29, 1), (34, 30, 2), (35, 30, 1), (27, 31, 0), (31, 31, 1),
            (32, 31, 2), (33, 31, 1), (36, 31, 0), (30, 28, 1), (34, 28, 1),
        ]
        for ex, ey, lvl in embers:
            glow.emit(px, ex, ey, EMBER_GLOW[lvl], EMBER_GLOW[lvl], halo=1)
    else:
        # Faint cold white ash flecks
        for ax, ay in ((29, 29), (33, 30), (31, 31)):
            px[ay][ax] = CHAR_ASH[4]

    # Ring of 13 rounded coastal cobbles (back half then front half)
    cobbles = []
    n = 13
    for k in range(n):
        ang = k / n * math.tau + 0.15
        sx = cx + math.cos(ang) * 18.5
        sy = cy + math.sin(ang) * 9.5
        cobbles.append((sy, sx, k))
    cobbles.sort()
    for _, sx, k in cobbles:
        ang = k / n * math.tau + 0.15
        sy = cy + math.sin(ang) * 9.5
        ramp = TRAVERTINE if k % 3 == 0 else COAST_STONE
        _draw_ellipse_shaded(px, sx, sy, 4.4, 3.3, ramp, k + 10)

    return _outline_and_shadow(px, INK, [(32.0, 36.0, 22.0, 7.5)]), glow.finish()


def build_campfire_flames() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """8 seamless looping frames of 32x32 flames, anchor (16, 26)."""
    fw, fh, n = 32, 32, 8
    sheet = make_grid(fw * n, fh)
    base = fh - 6  # 26
    tongues = []
    for i in range(7):
        u = (i - 3) / 3.0
        tongues.append((
            u * 6.8 + 0.7 * math.sin(i * 2.3),
            4.2 * (1.0 - 0.35 * abs(u)),
            (fh - 10) * (1.0 - 0.38 * abs(u)) * (0.82 + 0.18 * h2(i, 1, 9)),
            1 + (i % 3),
            i * 1.7,
        ))
    for f in range(n):
        ph = f / n * math.tau
        field = [[0.0] * fw for _ in range(fh)]
        for ox, w0, ht, beats, p0 in tongues:
            hh = ht * (0.72 + 0.28 * math.sin(ph * beats + p0)) * (0.9 + 0.1 * math.sin(ph * 2 + p0 * 2))
            sway = math.sin(ph * beats + p0 + 1.2) * 2.3
            for y in range(fh):
                yy = base - y
                if yy < -3 or yy > hh:
                    continue
                u = max(yy, 0) / max(1.0, hh)
                width = w0 * ((1.0 - u) ** 0.75) * (1.0 + 0.28 * math.sin(u * 6.0 + ph))
                if yy < 0:
                    width *= 1.0 + yy / 4.0
                cx = fw / 2.0 + ox * (1.0 - 0.25 * u) + sway * (u ** 1.4)
                for x in range(fw):
                    d = abs(x + 0.5 - cx)
                    if d < width:
                        val = (1.0 - d / max(width, 0.1)) * (1.0 - 0.55 * u) + 0.12 * (1.0 - u)
                        if val > field[y][x]:
                            field[y][x] = val
        for y in range(fh):
            for x in range(fw):
                v = field[y][x]
                if v <= 0.03:
                    continue
                u = (base - y) / (fh - 10)
                v += (h2(x, y, f + 3) - 0.5) * 0.12 * (0.3 + u) + (BAYER[y & 3][x & 3] / 15.0 - 0.5) * 0.08
                if v > 0.78:
                    tone = 3
                elif v > 0.48:
                    tone = 2
                elif v > 0.20:
                    tone = 1
                elif v > 0.06:
                    tone = 0
                else:
                    continue
                sheet[y][f * fw + x] = FIRE[tone]
        # Breathing ember bed under flame
        for y in range(base - 1, min(fh, base + 4)):
            for x in range(fw):
                e = ((x + 0.5 - fw / 2.0) / 10.5) ** 2 + ((y + 0.5 - base - 1.0) / 2.8) ** 2
                if e < 1.0 and sheet[y][f * fw + x][3] == 0 and h2(x, y, 5 + (f % 3)) < 0.68 - e * 0.5:
                    sheet[y][f * fw + x] = FIRE[0 if e > 0.55 else 1]
        # Rising sparks
        for k in range(3):
            sx = int(fw / 2.0 + (h2(k, 3, 2) - 0.5) * 14.0 + math.sin(ph + k) * 2.0)
            t = (f / n + k / 3.0) % 1.0
            sy = int(base - 7 - t * 15.0)
            if 0 <= sy < fh and 0 <= sx < fw and sheet[sy][f * fw + sx][3] == 0:
                sheet[sy][f * fw + sx] = FIRE[3 if t < 0.5 else 2]

    # Put flames in both base and glow (glow adds soft 1px halo)
    glow = GlowMap(fw * n, fh)
    for y in range(fh):
        for x in range(fw * n):
            c = sheet[y][x]
            if c[3] > 0:
                glow.emit(None, x, y, None, c, halo=1 if c == FIRE[3] or c == FIRE[2] else 0)
    return sheet, glow.finish()


def build_driftwood_bench() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 48, 32
    px = make_grid(w, h)
    # Two small chock blocks beneath log
    _draw_box_shaded(px, 11, 21, 15, 25, DRIFTWOOD, 1)
    _draw_box_shaded(px, 33, 21, 37, 25, DRIFTWOOD, 2)
    # Horizontal sun-bleached driftwood log with flattened seat top
    for x in range(7, 41):
        for y in range(13, 23):
            # Tapered ends
            if (x in (7, 40) and y in (13, 22)) or (x in (8, 39) and y == 13):
                continue
            nx = (x - 24.0) / 17.0
            ny = (y - 17.5) / 4.5
            if y == 14 and 11 <= x <= 36:
                px[y][x] = DRIFTWOOD[5]  # worn flat sunlit seat
            elif y == 15 and 11 <= x <= 36:
                px[y][x] = DRIFTWOOD[4]
            else:
                lit = -0.55 * nx - 0.80 * ny
                grain = 0.14 if (y in (17, 19) and (x + y) % 5 != 0) else 0.0
                idx = clamp_idx(int(round(clamp(0.45 + lit * 0.42 + grain, 0.0, 1.0) * 4)) + 1, len(DRIFTWOOD))
                px[y][x] = DRIFTWOOD[idx]
    # Cut log ends (left & right)
    for ex in (7, 8, 39, 40):
        for y in range(15, 21):
            px[y][ex] = TRAVERTINE[4 if ex < 20 else 2]
    # Sea-kelp / moss speck on left end
    px[18][10] = px[19][10] = px[19][11] = SEA_KELP[2]
    px[18][11] = SEA_KELP[3]
    return _outline_and_shadow(px, DRIFT_OUTLINE, [(24.0, 24.5, 19.0, 4.5)]), make_grid(w, h)


def build_driftwood_stump() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 32, 32
    px = make_grid(w, h)
    # Root flares at base
    _draw_box_shaded(px, 8, 21, 23, 25, DRIFTWOOD, 4)
    # Main cylindrical weathered stump
    for y in range(13, 25):
        for x in range(10, 22):
            nx = (x - 16.0) / 6.0
            lit = -0.55 * nx + 0.35 * math.sqrt(max(0.0, 1.0 - nx * nx))
            idx = clamp_idx(int(round(clamp(0.45 + lit * 0.45, 0.0, 1.0) * 4)), len(DRIFTWOOD))
            if x in (13, 18) and y > 16:
                idx = max(0, idx - 1)  # bark fissure
            px[y][x] = DRIFTWOOD[idx]
    # Flat cut top oval (y=11..15)
    _draw_ellipse_shaded(px, 16.0, 13.0, 6.0, 2.5, TRAVERTINE, 9)
    px[13][15] = px[13][16] = TRAVERTINE[3]  # growth ring center
    return _outline_and_shadow(px, DRIFT_OUTLINE, [(16.0, 24.5, 9.5, 4.0)]), make_grid(w, h)


def build_beach_pack() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 48, 32
    px = make_grid(w, h)
    glow = GlowMap(w, h)
    # Rolled canvas bedroll (x=10..31, y=15..24)
    _draw_box_shaded(px, 11, 16, 31, 24, CLOTH_CANVAS, 12)
    for sx in (15, 27):
        for y in range(16, 25):
            px[y][sx] = LEATHER[1 if y > 20 else 2]
    # Spiral end of bedroll
    _draw_ellipse_shaded(px, 11.0, 20.0, 2.5, 3.8, CLOTH_CANVAS, 13)
    # Leather traveler's satchel beside it (x=25..36, y=13..24)
    _draw_box_shaded(px, 26, 13, 35, 23, TIMBER, 14)
    for x in range(27, 35):
        px[16][x] = TIMBER[3]
    px[18][30] = GOLD[2]  # brass buckle
    # Small tin camp lantern perched right (x=36..40, y=17..24)
    _draw_box_shaded(px, 36, 18, 40, 24, COAST_STONE, 15)
    glow.emit(px, 38, 20, FIRE[2], FIRE[3], halo=1)
    glow.emit(px, 38, 21, FIRE[1], FIRE[2], halo=1)
    return _outline_and_shadow(px, INK, [(25.0, 24.5, 16.5, 4.5)]), glow.finish()


def build_supply_chest_strip() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """3 frames x 56x48 (closed, unlocked/ajar, open), anchor (28, 39)."""
    fw, fh = 56, 48
    sheet = make_grid(fw * 3, fh)
    glow_sheet = make_grid(fw * 3, fh)

    for state in range(3):
        px = make_grid(fw, fh)
        glow = GlowMap(fw, fh)
        # Chest body (x=15..41, y=24..39)
        _draw_box_shaded(px, 16, 26, 40, 39, WOOD_CRATE, 20)
        for y in (30, 35):
            for x in range(16, 41):
                px[y][x] = WOOD_CRATE[0]  # plank seams
        # Corroded sea-bronze/iron corner & center straps
        for bx in (17, 18, 38, 39):
            for y in range(26, 40):
                px[y][bx] = RUST_BRONZE[2 if bx < 25 else 1]
        # Kelp & barnacle cluster at base left
        for kx, ky, ci in ((14, 37, 1), (15, 37, 2), (15, 38, 1), (16, 38, 2), (17, 39, 3)):
            px[ky][kx] = SEA_KELP[ci]

        if state == 0:
            # Closed lid (x=15..41, y=18..26)
            _draw_box_shaded(px, 15, 19, 41, 26, DRIFTWOOD, 21)
            for bx in (17, 18, 38, 39):
                for y in range(19, 27):
                    px[y][bx] = RUST_BRONZE[3 if y < 22 else 2]
            # Sea-glass latch
            for lx in (27, 28, 29):
                for ly in (25, 26, 27, 28):
                    px[ly][lx] = RUST_BRONZE[3 if ly < 27 else 1]
            glow.emit(px, 28, 26, TEAL_GLINT[0], TEAL_GLINT[1], halo=1)
        elif state == 1:
            # Unlocked / lid cracked slightly ajar (raised 2px on left/front)
            _draw_box_shaded(px, 15, 17, 41, 24, DRIFTWOOD, 22)
            for bx in (17, 18, 38, 39):
                for y in range(17, 25):
                    px[y][bx] = RUST_BRONZE[3 if y < 20 else 2]
            for x in range(16, 41):
                px[25][x] = CHAR_ASH[1]  # dark gap inside
            # Popped hanging latch
            px[27][28] = px[28][28] = RUST_BRONZE[2]
            glow.emit(px, 28, 25, TEAL_GLINT[1], TEAL_GLINT[1], halo=1)
        else:
            # Open chest (lid tilted back y=12..21, dark interior y=22..28 with folded cloth & glint)
            _draw_box_shaded(px, 15, 12, 41, 20, DRIFTWOOD, 23)
            for bx in (17, 18, 38, 39):
                for y in range(12, 21):
                    px[y][bx] = RUST_BRONZE[2]
            for y in range(21, 27):
                for x in range(17, 40):
                    px[y][x] = CHAR_ASH[0]
            # Folded linen cloth & rope inside
            _draw_box_shaded(px, 19, 22, 28, 26, CLOTH_CANVAS, 24)
            _draw_box_shaded(px, 30, 23, 36, 26, CORD, 25)
            glow.emit(px, 29, 24, TEAL_GLINT[0], TEAL_GLINT[1], halo=1)
            glow.emit(px, 33, 24, GOLD[2], FIRE[3], halo=1)

        final_cell = _outline_and_shadow(px, INK, [(28.0, 39.5, 14.5, 5.0)])
        gl_cell = glow.finish()
        for y in range(fh):
            for x in range(fw):
                sheet[y][state * fw + x] = final_cell[y][x]
                glow_sheet[y][state * fw + x] = gl_cell[y][x]

    return sheet, glow_sheet


def build_weapon_rack() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 48, 48
    px = make_grid(w, h)
    # Left & right A-frame driftwood posts + base feet
    _draw_box_shaded(px, 10, 20, 13, 39, DRIFTWOOD, 1)
    _draw_box_shaded(px, 35, 20, 38, 39, DRIFTWOOD, 2)
    _draw_box_shaded(px, 8, 37, 15, 40, DRIFTWOOD, 3)
    _draw_box_shaded(px, 33, 37, 40, 40, DRIFTWOOD, 4)
    # Crossbars with carved weapon notches
    _draw_box_shaded(px, 9, 23, 39, 26, DRIFTWOOD, 5)
    _draw_box_shaded(px, 11, 33, 37, 35, DRIFTWOOD, 6)
    for nx in (17, 30):
        px[23][nx] = px[23][nx + 1] = DRIFTWOOD[0]
    # Rope lashings at joints
    for lx in (10, 11, 12, 35, 36, 37):
        px[24][lx] = px[25][lx] = CORD[2]
    return _outline_and_shadow(px, DRIFT_OUTLINE, [(24.0, 40.0, 17.5, 4.5)]), make_grid(w, h)


def build_chopping_stump() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 40, 48
    px = make_grid(w, h)
    # Root flare & driftwood chopping block
    _draw_box_shaded(px, 11, 35, 29, 39, DRIFTWOOD, 7)
    for y in range(25, 39):
        for x in range(13, 27):
            nx = (x - 20.0) / 7.0
            lit = -0.55 * nx + 0.35 * math.sqrt(max(0.0, 1.0 - nx * nx))
            idx = clamp_idx(int(round(clamp(0.45 + lit * 0.45, 0.0, 1.0) * 4)), len(DRIFTWOOD))
            px[y][x] = DRIFTWOOD[idx]
    _draw_ellipse_shaded(px, 20.0, 25.0, 7.0, 3.0, TRAVERTINE, 8)
    # Axe notch on top face
    px[25][19] = px[25][20] = px[25][21] = CHAR_ASH[1]
    return _outline_and_shadow(px, DRIFT_OUTLINE, [(20.0, 40.0, 11.0, 4.5)]), make_grid(w, h)


def build_starter_sword_ground() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 32, 24
    px = make_grid(w, h)
    glow = GlowMap(w, h)
    # Small driftwood cradle under hilt
    _draw_box_shaded(px, 6, 15, 13, 18, DRIFTWOOD, 3)
    # Diagonal sword resting bottom-left -> top-right (3/4 foreshortened)
    for i in range(13):
        bx = 11 + i
        by = 15 - (i * 8) // 12
        px[by][bx] = STEEL[4 if i < 11 else 3]
        px[by + 1][bx] = STEEL[2 if 2 <= i <= 8 else 1]
    # Crossguard
    for k in (-2, -1, 0, 1, 2):
        px[15 + k][10 + k] = GOLD[2 if k <= 0 else 1]
    # Leather grip + gold pommel + violet gem
    px[16][9] = LEATHER[2]
    px[17][8] = LEATHER[1]
    px[18][7] = GOLD[2]
    glow.emit(px, 6, 18, SWORD_GEM, SWORD_GEM_GLOW, halo=1)
    return _outline_and_shadow(px, INK, [(16.0, 19.0, 11.0, 3.0)]), glow.finish()


def build_starter_axe_ground() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 32, 24
    px = make_grid(w, h)
    # Timber haft resting diagonally
    for i in range(16):
        hx = 6 + i
        hy = 17 - (i * 8) // 15
        px[hy][hx] = TIMBER[2]
        px[hy + 1][hx] = TIMBER[1]
    # Knapped matte stone axe blade (curved sharp edge + narrow poll)
    blade_pts = [
        (19, 6, 3), (20, 6, 3), (21, 6, 2),
        (18, 7, 3), (19, 7, 2), (20, 7, 2), (21, 7, 1), (22, 7, 2),
        (18, 8, 3), (19, 8, 2), (20, 8, 1), (21, 8, 1), (22, 8, 2), (23, 8, 3),
        (19, 9, 2), (20, 9, 1), (21, 9, 1), (22, 9, 2), (23, 9, 3), (24, 9, 3),
        (20, 10, 1), (21, 10, 1), (22, 10, 2), (23, 10, 2), (24, 10, 3),
        (21, 11, 0), (22, 11, 1), (23, 11, 2),
        (22, 12, 0), (23, 12, 1),
    ]
    for bx, by, si in blade_pts:
        px[by][bx] = STONE_TOOL[si]
    # Fiber cord cross-lashing around haft-head join
    for lx, ly in ((19, 9), (20, 9), (19, 10), (20, 10), (21, 10)):
        px[ly][lx] = CORD[2 if lx == 19 else 1]
    return _outline_and_shadow(px, INK, [(16.0, 19.0, 10.5, 3.0)]), make_grid(w, h)


def build_starter_sword_planted() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 24, 32
    px = make_grid(w, h)
    glow = GlowMap(w, h)
    # Small sand/driftwood mound at base
    _draw_ellipse_shaded(px, 12.0, 27.0, 5.0, 2.0, TRAVERTINE, 5)
    # Blade planted point-down slightly tilted (y=12..26)
    for y in range(13, 27):
        bx = 12 + (20 - y) // 5
        px[y][bx - 1] = STEEL[4]
        px[y][bx] = STEEL[2]
        px[y][bx + 1] = STEEL[1]
    # Gold crossguard at y=11..12
    for gx in range(9, 18):
        px[12][gx] = GOLD[2 if gx < 14 else 1]
    px[11][9] = px[11][17] = GOLD[3]
    # Grip + pommel + gem
    for y in range(7, 12):
        px[y][13] = LEATHER[2 if y % 2 == 0 else 1]
    px[6][12] = px[6][14] = GOLD[2]
    px[5][13] = GOLD[3]
    glow.emit(px, 13, 6, SWORD_GEM, SWORD_GEM_GLOW, halo=1)
    return _outline_and_shadow(px, INK, [(12.0, 27.5, 6.0, 2.2)]), glow.finish()


def build_starter_axe_planted() -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 24, 32
    px = make_grid(w, h)
    _draw_ellipse_shaded(px, 12.0, 27.0, 5.5, 2.2, DRIFTWOOD, 6)
    # Knapped stone head wedged into base (y=19..26)
    for y in range(19, 27):
        for x in range(8, 15):
            if y == 19 and x < 10:
                continue
            px[y][x] = STONE_TOOL[3 if x <= 10 else (2 if x <= 12 else 1)]
    # Cord lashing
    for y in range(18, 22):
        px[y][13] = px[y][14] = CORD[2 if y < 20 else 1]
    # Timber haft angling up-right
    for i in range(15):
        hx = 13 + i // 3
        hy = 20 - i
        px[hy][hx] = TIMBER[2]
        px[hy][hx + 1] = TIMBER[1]
    return _outline_and_shadow(px, INK, [(12.0, 27.5, 6.5, 2.4)]), make_grid(w, h)


def build_icon_16(kind_name: str) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 16, 16
    px = make_grid(w, h)
    glow = GlowMap(w, h)
    if kind_name == "sword":
        for i in range(7):
            x, y = 7 + i, 8 - i
            px[y][x] = STEEL[4]
            if i < 6:
                px[y][x + 1] = STEEL[2 if 1 <= i <= 4 else 1]
        for k in range(-2, 3):
            px[9 + k][6 + k] = GOLD[2]
        px[10][5] = LEATHER[2]
        px[11][4] = LEATHER[1]
        px[12][3] = GOLD[2]
        glow.emit(px, 2, 13, SWORD_GEM, SWORD_GEM_GLOW, halo=0)
    else:
        for i in range(9):
            x, y = 3 + i, 12 - i
            px[y][x] = TIMBER[2]
        for y in range(2, 8):
            for x in range(9, 14):
                if (y == 2 and x > 11) or (y == 7 and x < 12) or (x == 9 and y > 4):
                    continue
                px[y][x] = STONE_TOOL[3 if x >= 12 or y <= 3 else 1]
        px[4][10] = px[5][10] = px[5][11] = CORD[2]
    # 1px INK outline
    out = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if px[y][x][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= 200:
                        out[y][x] = INK
                        break
    return out, glow.finish()


def build_clutter(variant: str) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    w, h = 24, 16
    px = make_grid(w, h)
    if variant == "rope":
        _draw_ellipse_shaded(px, 12.0, 10.0, 7.0, 3.2, CORD, 40)
        _draw_ellipse_shaded(px, 12.0, 8.0, 5.0, 2.2, CORD, 41)
        px[8][11] = px[8][12] = px[8][13] = CHAR_ASH[2]
    elif variant == "kindling":
        for dy, dx0, dx1 in ((9, 5, 17), (10, 6, 19), (7, 7, 16)):
            _draw_box_shaded(px, dx0, dy, dx1, dy + 2, DRIFTWOOD, dy)
    else:
        _draw_ellipse_shaded(px, 9.0, 10.0, 3.2, 2.2, COAST_STONE, 50)
        _draw_ellipse_shaded(px, 14.5, 11.0, 2.8, 1.8, TRAVERTINE, 51)
        _draw_ellipse_shaded(px, 12.0, 8.5, 2.2, 1.6, COAST_STONE, 52)
    return _outline_and_shadow(px, DRIFT_OUTLINE, [(12.0, 12.5, 8.0, 2.5)]), make_grid(w, h)


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
                min(255, int(dc[0] * (1.0 - 0.40 * f) + gc[0] * f * 1.35)),
                min(255, int(dc[1] * (1.0 - 0.40 * f) + gc[1] * f * 1.35)),
                min(255, int(dc[2] * (1.0 - 0.40 * f) + gc[2] * f * 1.35)),
                255,
            )


def _crop(src: list[list[tuple[int, int, int, int]]], rx: int, ry: int, rw: int, rh: int) -> list[list[tuple[int, int, int, int]]]:
    return [src[ry + y][rx : rx + rw] for y in range(rh)]


def build_4x_atlas(sheet: list[list[tuple[int, int, int, int]]], glow_sheet: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    """288 x 272 1x -> 1152 x 1088 4x nearest (Top: Day raw atlas on beach sand; Bottom: Night Diorama + Night raw items)."""
    lw, lh = 288, 272
    img = [[INK] * lw for _ in range(lh)]
    sand_a = hexc("c7ab7c")
    sand_b = hexc("d6bc8e")
    night_bg = hexc("14192c")

    # Top Day band: y = 4..147 (shows top 144px or full scaled layout cleanly; let's render full 256x192? Wait: 192 > 144!)
    # Let's pack all items cleanly inside top band y=4..115 (112px tall) and bottom Night diorama + strip y=120..267!
    for y in range(4, 116):
        for x in range(4, 284):
            img[y][x] = sand_b if ((x // 4 + y // 3) % 7 == 0) else sand_a

    # Row A (Day): Row 0 & Row 1 & Row 2 & Row 3 items neatly arranged inside 280x112
    # y=4..51: campfire_unlit, campfire_lit, bench, stump, pack
    _blit(img, _crop(sheet, 0, 0, 256, 48), 8, 4, alpha_blend=True)
    # y=54..101: supply_chest (3 frames), weapon_rack, chopping_stump
    _blit(img, _crop(sheet, 0, 80, 256, 48), 8, 54, alpha_blend=True)
    # y=102..115? Let's place small items at x=8..280? Better: flame strip + weapons at bottom right night & top right!
    # Wait: let's place flame frames 0,3,6 + weapons in bottom right Night & top right if needed, or adjust band heights cleanly within 288x272:
    # Top Day band: y = 4..142 (138px):
    #   y=4..51 (48px): sheet y=0..47 (campfire unlit/lit, bench, stump, pack)
    #   y=54..101 (48px): sheet y=80..127 (chest 0..2, rack, stump)
    #   y=104..135 (32px): sheet y=128..159 (sword/axe ground, planted, 16px icons, clutter) + 3 flame samples at x=224? Wait: let's expand y=144..267 (124px) for Night Diorama + Flame strip!
    for y in range(4, 140):
        for x in range(4, 284):
            img[y][x] = sand_b if ((x // 4 + y // 3) % 7 == 0) else sand_a
    _blit(img, _crop(sheet, 0, 0, 256, 48), 8, 4, alpha_blend=True)
    _blit(img, _crop(sheet, 0, 80, 256, 48), 8, 54, alpha_blend=True)
    _blit(img, _crop(sheet, 0, 128, 216, 32), 8, 104, alpha_blend=True)
    # Show 2 Day flame samples at right
    _blit(img, _crop(sheet, 0, 48, 32, 32), 226, 104, alpha_blend=True)
    _blit(img, _crop(sheet, 96, 48, 32, 32), 252, 104, alpha_blend=True)

    # Bottom Night Diorama (left 160x124) + Night Items (right 116x124) at y=144..267
    for y in range(144, 268):
        for x in range(4, 284):
            if x == 164 or x == 165:
                continue
            img[y][x] = night_bg

    # Warm radial firelight floor wash in Night Diorama (center at x=84, y=206)
    fcx, fcy = 84.0, 206.0
    for y in range(144, 268):
        for x in range(4, 164):
            d = math.hypot((x - fcx) / 48.0, (y - fcy) / 34.0)
            if d < 1.0:
                w_lit = (1.0 - d) ** 1.6 * 0.38
                bg = img[y][x]
                img[y][x] = (
                    min(255, int(bg[0] + 150 * w_lit)),
                    min(255, int(bg[1] + 82 * w_lit)),
                    min(255, int(bg[2] + 30 * w_lit)),
                    255,
                )

    def place_night(rx: int, ry: int, rw: int, rh: int, ax: int, ay: int, wx: int, wy: int, glow_only: bool = False) -> None:
        sub_b = _crop(sheet, rx, ry, rw, rh)
        sub_g = _crop(glow_sheet, rx, ry, rw, rh)
        dx, dy = wx - ax, wy - ay
        if not glow_only:
            _blit(img, _tint_night(sub_b), dx, dy, alpha_blend=True)
        _add_glow(img, sub_g, dx, dy)

    # Assembled Coastal Camp Night Diorama (y-sorted order back to front):
    place_night(208, 0, 48, 32, 24, 24, 38, 186)   # beach_pack_prop
    place_night(0, 80, 56, 48, 28, 39, 124, 190)   # supply_chest (closed)
    place_night(168, 80, 48, 48, 24, 40, 42, 212)  # weapon_rack
    place_night(0, 128, 32, 24, 16, 19, 36, 214)   # starter_sword_ground near rack
    place_night(216, 80, 40, 48, 20, 40, 130, 224) # chopping_stump
    place_night(88, 128, 24, 32, 12, 27, 131, 211) # starter_axe_planted on chopping stump
    place_night(64, 0, 64, 48, 32, 36, 84, 212)    # campfire_lit
    place_night(0, 48, 32, 32, 16, 26, 84, 206, glow_only=True)  # animated flame unlit
    place_night(176, 0, 32, 32, 16, 24, 114, 210)  # driftwood_stump (east seat)
    place_night(128, 0, 48, 32, 24, 24, 84, 236)   # driftwood_bench_h (south seat)
    place_night(144, 128, 24, 16, 12, 13, 56, 242) # camp_rope_coil
    place_night(168, 128, 24, 16, 12, 13, 114, 244)# camp_kindling

    # Right Night panel (x=166..283): Flame animation frames 0..5 + Night chest + planted sword
    for fi in range(3):
        place_night(fi * 32, 48, 32, 32, 0, 0, 172 + fi * 34, 150, glow_only=True)
        place_night((fi + 3) * 32, 48, 32, 32, 0, 0, 172 + fi * 34, 184, glow_only=True)
    place_night(112, 80, 56, 48, 0, 0, 170, 218)   # supply_chest open at night
    place_night(64, 128, 24, 32, 0, 0, 232, 226)   # starter_sword_planted at night
    place_night(88, 128, 24, 32, 0, 0, 256, 226)   # starter_axe_planted at night

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
        "sheet": "res://assets/props/coastal_camp.png",
        "glow_sheet": "res://assets/props/coastal_camp_glow.png",
        "sheet_size": [SHEET_W, SHEET_H],
        "campfire_unlit": {
            "rect": [0, 0, 64, 48],
            "frame": [64, 48],
            "ground": 36,
            "anchor": [32, 36],
            "offset": [-32, -36],
            "foot": [38, 16],
            "colliders": [[-19, -11, 38, 16]],
            "fire_at": [0, -6],
            "seats": [
                {"id": "east", "offset": [34, -2], "facing_sector": 4},
                {"id": "south", "offset": [0, 22], "facing_sector": 6},
            ],
        },
        "campfire_lit": {
            "rect": [64, 0, 64, 48],
            "frame": [64, 48],
            "ground": 36,
            "anchor": [32, 36],
            "offset": [-32, -36],
            "foot": [38, 16],
            "colliders": [[-19, -11, 38, 16]],
            "fire_at": [0, -6],
            "light": {"color": "ff9448", "radius": 96, "squash": 0.7, "energy": 1.35, "at": [0, -6], "flicker": 0.35},
        },
        "campfire_flame": {
            "rect": [0, 48, 256, 32],
            "frame": [32, 32],
            "ground": 26,
            "anchor": [16, 26],
            "offset": [-16, -26],
            "cols": 8,
            "fps": 11,
        },
        "driftwood_bench_h": {
            "rect": [128, 0, 48, 32],
            "frame": [48, 32],
            "ground": 24,
            "anchor": [24, 24],
            "offset": [-24, -24],
            "foot": [36, 10],
            "colliders": [[-18, -8, 36, 10]],
            "seat_pos": [0, -4],
        },
        "driftwood_stump": {
            "rect": [176, 0, 32, 32],
            "frame": [32, 32],
            "ground": 24,
            "anchor": [16, 24],
            "offset": [-16, -24],
            "foot": [16, 10],
            "colliders": [[-8, -8, 16, 10]],
            "seat_pos": [0, -4],
        },
        "beach_pack_prop": {
            "rect": [208, 0, 48, 32],
            "frame": [48, 32],
            "ground": 24,
            "anchor": [24, 24],
            "offset": [-24, -24],
            "foot": [28, 10],
            "colliders": [[-14, -8, 28, 10]],
        },
        "supply_chest": {
            "rect": [0, 80, 168, 48],
            "frame": [56, 48],
            "ground": 39,
            "anchor": [28, 39],
            "offset": [-28, -39],
            "cols": 3,
            "states": {"closed": 0, "unlocked": 1, "open": 2},
            "foot": [26, 9],
            "colliders": [[-13, -7, 26, 9]],
            "mouth": [0.0, -10.0],
            "lock": [-2.0, -3.0],
            "lid_top": [0.0, -14.0],
        },
        "weapon_rack": {
            "rect": [168, 80, 48, 48],
            "frame": [48, 48],
            "ground": 40,
            "anchor": [24, 40],
            "offset": [-24, -40],
            "foot": [32, 10],
            "colliders": [[-16, -8, 32, 10]],
            "sword_slot": [-7, -8],
            "axe_slot": [7, -8],
        },
        "chopping_stump": {
            "rect": [216, 80, 40, 48],
            "frame": [40, 48],
            "ground": 40,
            "anchor": [20, 40],
            "offset": [-20, -40],
            "foot": [20, 10],
            "colliders": [[-10, -8, 20, 10]],
            "axe_slot": [1, -13],
        },
        "starter_sword_ground": {
            "rect": [0, 128, 32, 24],
            "frame": [32, 24],
            "ground": 19,
            "anchor": [16, 19],
            "offset": [-16, -19],
            "item_id": "sword_basic",
            "foot": [18, 6],
            "prompt_anchor": [0, -16],
        },
        "starter_axe_ground": {
            "rect": [32, 128, 32, 24],
            "frame": [32, 24],
            "ground": 19,
            "anchor": [16, 19],
            "offset": [-16, -19],
            "item_id": "axe_basic",
            "foot": [18, 6],
            "prompt_anchor": [0, -16],
        },
        "starter_sword_planted": {
            "rect": [64, 128, 24, 32],
            "frame": [24, 32],
            "ground": 27,
            "anchor": [12, 27],
            "offset": [-12, -27],
            "item_id": "sword_basic",
            "foot": [10, 6],
            "prompt_anchor": [0, -28],
        },
        "starter_axe_planted": {
            "rect": [88, 128, 24, 32],
            "frame": [24, 32],
            "ground": 27,
            "anchor": [12, 27],
            "offset": [-12, -27],
            "item_id": "axe_basic",
            "foot": [12, 6],
            "prompt_anchor": [0, -26],
        },
        "starter_sword_icon_16": {
            "rect": [112, 128, 16, 16],
            "frame": [16, 16],
            "ground": 14,
            "anchor": [8, 14],
            "offset": [-8, -14],
            "item_id": "sword_basic",
        },
        "starter_axe_icon_16": {
            "rect": [128, 128, 16, 16],
            "frame": [16, 16],
            "ground": 14,
            "anchor": [8, 14],
            "offset": [-8, -14],
            "item_id": "axe_basic",
        },
        "camp_rope_coil": {
            "rect": [144, 128, 24, 16],
            "frame": [24, 16],
            "ground": 13,
            "anchor": [12, 13],
            "offset": [-12, -13],
        },
        "camp_kindling": {
            "rect": [168, 128, 24, 16],
            "frame": [24, 16],
            "ground": 13,
            "anchor": [12, 13],
            "offset": [-12, -13],
        },
        "camp_pebbles": {
            "rect": [192, 128, 24, 16],
            "frame": [24, 16],
            "ground": 13,
            "anchor": [12, 13],
            "offset": [-12, -13],
        },
    }


def main() -> None:
    sheet = make_grid(SHEET_W, SHEET_H)
    glow_sheet = make_grid(SHEET_W, SHEET_H)

    placements = [
        (0, 0, build_campfire(lit_state=False)),
        (64, 0, build_campfire(lit_state=True)),
        (128, 0, build_driftwood_bench()),
        (176, 0, build_driftwood_stump()),
        (208, 0, build_beach_pack()),
        (0, 48, build_campfire_flames()),
        (0, 80, build_supply_chest_strip()),
        (168, 80, build_weapon_rack()),
        (216, 80, build_chopping_stump()),
        (0, 128, build_starter_sword_ground()),
        (32, 128, build_starter_axe_ground()),
        (64, 128, build_starter_sword_planted()),
        (88, 128, build_starter_axe_planted()),
        (112, 128, build_icon_16("sword")),
        (128, 128, build_icon_16("axe")),
        (144, 128, build_clutter("rope")),
        (168, 128, build_clutter("kindling")),
        (192, 128, build_clutter("pebbles")),
    ]
    for ox, oy, (b, g) in placements:
        _blit(sheet, b, ox, oy, alpha_blend=False)
        _blit(glow_sheet, g, ox, oy, alpha_blend=False)

    atlas = build_4x_atlas(sheet, glow_sheet)

    verify_no_black("coastal_camp.png", sheet)
    verify_no_black("coastal_camp_glow.png", glow_sheet)
    verify_no_black("coastal_camp_atlas_4x.png", atlas)

    props_dir = ROOT / "props"
    data_path = ROOT.parent / "data" / "coastal_camp_art.json"
    atlas_path = ROOT.parent / "docs" / "img" / "coastal_camp_atlas_4x.png"
    write_png(props_dir / "coastal_camp.png", SHEET_W, SHEET_H, sheet)
    write_png(props_dir / "coastal_camp_glow.png", SHEET_W, SHEET_H, glow_sheet)
    write_png(atlas_path, len(atlas[0]), len(atlas), atlas)
    data_path.write_text(json.dumps(build_metadata(), indent="\t") + "\n", encoding="utf-8")
    print(f"Wrote {props_dir / 'coastal_camp.png'} ({SHEET_W}x{SHEET_H}), _glow.png, {data_path.name}, and {atlas_path} ({len(atlas[0])}x{len(atlas)})")


if __name__ == "__main__":
    main()
