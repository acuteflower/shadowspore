"""Shadowspore Icon Generator — Glowing Plant Consumed by the Void from Below.

Generates the Shadowspore plant icon across resolutions and targets:
  - 32x32 pixel-crafted master art (and 48x48 high-detail intermediate)
  - 16x16 hand-crafted micro-master for browser favicons & taskbar/tray icons
  - 64 / 128 / 256 nearest-neighbor upscales for Windows EXE & Tauri launcher
  - 180x180 Apple Touch Icon on #07040d with Bayer-dithered Void/Life aura
  - Crisp pixel SVG (`icon.svg` with shape-rendering="crispEdges")

Run:
  py -3 tools/art_icon.py --compare --preview-only
  py -3 tools/art_icon.py --variant A
"""
from __future__ import annotations

import argparse
import io
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_PREVIEW = ROOT / "docs" / "img" / "icon_preview.png"

BAYER = np.array(
    [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]],
    dtype=np.float32,
) / 16.0


def hex_rgb(s: str) -> tuple[int, int, int]:
    h = s.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def hex_rgba(s: str, a: int = 255) -> tuple[int, int, int, int]:
    return (*hex_rgb(s), a)


# Project palettes (docs/design_guide.md + adaptive material-tinted 1px outlines)
OUTLINE_VOID = hex_rgba("040208")
OUTLINE_LIFE = hex_rgba("112828")
OUTLINE_BLOOM_D = hex_rgba("0e3240")
OUTLINE_BLOOM_L = hex_rgba("184f5c")

VOID = [hex_rgba(c) for c in ("07040d", "0e0919", "18102e", "261846")]
VOID_STAIN = [hex_rgba(c) for c in ("18102c", "301950", "4d2880")]
VOID_RIM = hex_rgba("5a36b8")
VOID_RIM_LIT = hex_rgba("7448d8")
VEIN = hex_rgba("8a4dff")
VEIN_BRIGHT = hex_rgba("b474ff")
MAGENTA_DEEP = hex_rgba("a81888")
MAGENTA = hex_rgba("ff4fd8")
MAGENTA_HOT = hex_rgba("ff9ae8")

MOSS = [hex_rgba(c) for c in ("1d4236", "2d5e4c", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
TEAL = [hex_rgba(c) for c in ("144c58", "248690", "3cc0c6", "78f4e6", "d0fff8", "eefffc")]
GOLD = [hex_rgba(c) for c in ("7a551c", "b48a38", "e6c468", "fff0b0", "fffbe2")]

MAT_NONE = 0
MAT_VOID = 1
MAT_LIFE = 2
MAT_BLOOM = 3


class PixelCanvas:
    """Material-aware pixel art canvas with top-left lighting, interior creases & adaptive outlines."""

    def __init__(self, size: int) -> None:
        self.size = size
        self.rgba = np.zeros((size, size, 4), dtype=np.uint8)
        self.mat = np.zeros((size, size), dtype=np.uint8)
        self.prio = np.zeros((size, size), dtype=np.int16)
        self.part = np.zeros((size, size), dtype=np.int16)

    def put(
        self,
        x: int,
        y: int,
        col: tuple[int, int, int, int],
        mat: int,
        prio: int = 10,
        part_id: int = 0,
    ) -> None:
        if 0 <= x < self.size and 0 <= y < self.size and prio >= self.prio[y, x]:
            self.rgba[y, x] = col
            self.mat[y, x] = mat
            self.prio[y, x] = prio
            self.part[y, x] = part_id

    def stroke_bezier(
        self,
        p0: tuple[float, float],
        p1: tuple[float, float],
        p2: tuple[float, float],
        r0: float,
        r1: float,
        ramp: list[tuple[int, int, int, int]],
        mat: int,
        prio: int = 10,
        part_id: int = 1,
        steps: int = 44,
    ) -> None:
        s = self.size / 32.0
        for i in range(steps + 1):
            t = i / steps
            mt = 1.0 - t
            cx = mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0]
            cy = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
            r = (r0 * (1.0 - t) + r1 * t) * s
            for py in range(int(math.floor(cy * s - r - 1)), int(math.ceil(cy * s + r + 1)) + 1):
                for px in range(int(math.floor(cx * s - r - 1)), int(math.ceil(cx * s + r + 1)) + 1):
                    dx = (px + 0.5) - cx * s
                    dy = (py + 0.5) - cy * s
                    d = math.hypot(dx, dy)
                    if d <= max(0.50, r):
                        lit = 0.54 - 0.36 * (dx / max(0.8, r)) - 0.28 * (dy / max(0.8, r))
                        idx = int(np.clip(round(lit * (len(ramp) - 1)), 0, len(ramp) - 1))
                        self.put(px, py, ramp[idx], mat, prio, part_id)

    def draw_petal(
        self,
        base: tuple[float, float],
        tip: tuple[float, float],
        width: float,
        ramp: list[tuple[int, int, int, int]],
        mat: int = MAT_BLOOM,
        prio: int = 20,
        part_id: int = 10,
        curve: float = 0.0,
        tip_glow: float = 0.34,
        crease_col: tuple[int, int, int, int] | None = None,
        midrib: bool = False,
    ) -> None:
        s = self.size / 32.0
        bx, by = base[0] * s, base[1] * s
        tx, ty = tip[0] * s, tip[1] * s
        vx, vy = tx - bx, ty - by
        ln = max(1.0, math.hypot(vx, vy))
        ux, uy = vx / ln, vy / ln
        nx, ny = -uy, ux

        pad = int(math.ceil(width * s + abs(curve) * s + 3))
        min_x = max(0, int(min(bx, tx)) - pad)
        max_x = min(self.size - 1, int(max(bx, tx)) + pad)
        min_y = max(0, int(min(by, ty)) - pad)
        max_y = min(self.size - 1, int(max(by, ty)) + pad)

        for py in range(min_y, max_y + 1):
            for px in range(min_x, max_x + 1):
                rx, ry = (px + 0.5) - bx, (py + 0.5) - by
                along = (rx * ux + ry * uy) / ln
                if along < -0.02 or along > 1.02:
                    continue
                t = float(np.clip(along, 0.0, 1.0))
                arch = curve * s * math.sin(math.pi * t)
                perp = (rx * nx + ry * ny) - arch
                half_w = width * s * (math.sin(math.pi * (t ** 0.72)) ** 0.80)
                if half_w < 0.35:
                    continue
                ap = abs(perp)
                if ap <= half_w:
                    if crease_col is not None and ap > half_w - 0.85 * s and self.mat[py, px] == mat and self.part[py, px] != part_id:
                        self.put(px, py, crease_col, mat, prio, part_id)
                        continue
                    side_norm = perp / half_w
                    lx, ly = -0.58, -0.78
                    light_dot = (nx * side_norm * lx + ny * side_norm * ly) * 0.34
                    v = 0.42 + light_dot + tip_glow * (t ** 1.1)
                    if midrib and ap < 0.55 * s and 0.15 < t < 0.85:
                        v += 0.22
                    idx = int(np.clip(round(v * (len(ramp) - 1)), 0, len(ramp) - 1))
                    self.put(px, py, ramp[idx], mat, prio, part_id)

    def draw_gold_core(self, cx: float, cy: float, radius: float, prio: int = 35, part_id: int = 90) -> None:
        s = self.size / 32.0
        gx, gy, r = cx * s, cy * s, radius * s
        for py in range(int(gy - r - 2), int(gy + r + 3)):
            for px in range(int(gx - r - 2), int(gx + r + 3)):
                if not (0 <= px < self.size and 0 <= py < self.size):
                    continue
                dx = (px + 0.5) - gx
                dy = (py + 0.5) - gy
                d = math.hypot(dx, dy) / max(0.5, r)
                if d <= 1.02:
                    if d < 0.36 and dx <= 0.25 * s and dy <= 0.25 * s:
                        col = GOLD[4]
                    elif d < 0.62:
                        col = GOLD[3]
                    elif d < 0.86:
                        col = GOLD[2]
                    else:
                        col = GOLD[1]
                    self.put(px, py, col, MAT_BLOOM, prio, part_id)
                elif d <= 1.25 and self.mat[py, px] == MAT_BLOOM:
                    self.put(px, py, TEAL[0], MAT_BLOOM, prio - 1, part_id)

    def apply_outlines(self) -> Image.Image:
        out = self.rgba.copy()
        s = self.size
        for y in range(s):
            for x in range(s):
                if self.mat[y, x] != MAT_NONE:
                    continue
                neighbors = []
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < s and 0 <= ny < s and self.mat[ny, nx] != MAT_NONE:
                        neighbors.append((self.mat[ny, nx], nx, ny))
                if not neighbors:
                    continue
                mats = [m for m, _, _ in neighbors]
                if MAT_VOID in mats:
                    out[y, x] = OUTLINE_VOID
                elif MAT_LIFE in mats:
                    out[y, x] = OUTLINE_LIFE
                else:
                    is_tl = any((nx > x or ny > y) for _, nx, ny in neighbors)
                    out[y, x] = OUTLINE_BLOOM_L if is_tl else OUTLINE_BLOOM_D
        return Image.fromarray(out, "RGBA")


def add_void_roots(
    cv: PixelCanvas,
    stem_base: tuple[float, float],
    roots: list[dict],
    chew_leaf: tuple[float, float, float] | None,
) -> None:
    """Organic gnarled Void roots & creeping tendrils eating up the stem & bitten leaf tip (never a solid shoe!)."""
    s = cv.size / 32.0
    bx, by = stem_base

    # Small knotted root collar at stem foot (NOT a bulky ellipse)
    for py in range(cv.size):
        for px in range(cv.size):
            x32 = (px + 0.5) / s
            y32 = (py + 0.5) / s
            d = math.hypot((x32 - bx) / 2.9, (y32 - by) / 2.2)
            if d < 1.0:
                col = VOID[0] if d < 0.5 else (VOID_RIM if y32 < by - 0.6 else VOID[1])
                cv.put(px, py, col, MAT_VOID, prio=38, part_id=200)

    # Individual tapering root & spiral creeping tentacles
    for idx, root in enumerate(roots):
        p0, p1, p2 = root["p0"], root["p1"], root["p2"]
        r0, r1 = root["r0"], root["r1"]
        prio = root.get("prio", 40 + idx)
        steps = 44
        vein_start = root.get("vein_from", 0.20)
        vein_end = root.get("vein_to", 0.86)
        hot_tip = root.get("hot_tip", False)

        for i in range(steps + 1):
            t = i / steps
            mt = 1.0 - t
            cx = mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0]
            cy = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
            r = (r0 * (1.0 - t) + r1 * t) * s
            for py in range(int(math.floor(cy * s - r - 1)), int(math.ceil(cy * s + r + 1)) + 1):
                for px in range(int(math.floor(cx * s - r - 1)), int(math.ceil(cx * s + r + 1)) + 1):
                    if not (0 <= px < cv.size and 0 <= py < cv.size):
                        continue
                    dx = (px + 0.5) - cx * s
                    dy = (py + 0.5) - cy * s
                    d = math.hypot(dx, dy)
                    if d <= max(0.48, r):
                        # Crisp separator where foreground Void crosses living green stem
                        cross_seam = (
                            root.get("wrap", False)
                            and d > max(0.38, r - 0.48 * s)
                            and cv.mat[py, px] == MAT_LIFE
                        )
                        if cross_seam:
                            col = OUTLINE_VOID
                        elif vein_start <= t <= vein_end and d <= max(0.45, r * 0.42):
                            if hot_tip and t > vein_end - 0.14:
                                col = MAGENTA if t > vein_end - 0.08 else VEIN_BRIGHT
                            else:
                                col = VEIN_BRIGHT if t > 0.65 else VEIN
                        elif dy < -0.15 * max(0.5, r) and r >= 0.55 * s:
                            # Crisp top violet rim so Void tendrils stay unmistakable on dark backgrounds
                            col = VOID_RIM_LIT if t > 0.45 else VOID_RIM
                        else:
                            col = VOID[0] if d < r * 0.48 else VOID[1]
                        cv.put(px, py, col, MAT_VOID, prio=prio, part_id=201 + idx)

    # Corrode the outer tip of the lower-left leaf: bruised violet gradient + jagged bite notch!
    if chew_leaf is not None:
        lx, ly, rad = chew_leaf
        for py in range(cv.size):
            for px in range(cv.size):
                if cv.mat[py, px] != MAT_LIFE:
                    continue
                x32, y32 = (px + 0.5) / s, (py + 0.5) / s
                d = math.hypot(x32 - lx, y32 - ly)
                if d < rad * 0.58 and y32 > ly - 0.8:
                    # Physical bite notch removed from leaf edge
                    cv.rgba[py, px] = (0, 0, 0, 0)
                    cv.mat[py, px] = MAT_NONE
                    cv.prio[py, px] = 0
                elif d < rad:
                    cv.rgba[py, px] = VOID[1] if d < rad * 0.78 else VOID_STAIN[1]
                    cv.mat[py, px] = MAT_VOID
                elif d < rad + 1.4:
                    cv.rgba[py, px] = VOID_STAIN[2]


# ---------------------------------------------------------------------------
# VARIANT A: Sporen-Kelch (Cupped Lotus Blossom + Void-wrapped Roots & Stem)
# ---------------------------------------------------------------------------
def build_variant_a(size: int = 32) -> Image.Image:
    cv = PixelCanvas(size)

    # S-curved living green stem visible clearly between ground roots & crown
    cv.stroke_bezier((15.4, 26.2), (14.4, 20.6), (16.5, 13.8), 1.35, 1.15, MOSS[1:5], MAT_LIFE, prio=12, part_id=1)

    # Upper-right healthy meadow leaf + lower-left leaf whose tip gets eaten
    cv.draw_petal((16.0, 18.6), (25.4, 15.2), 2.45, MOSS[1:], MAT_LIFE, prio=16, part_id=2, curve=-0.8, midrib=True)
    cv.draw_petal((14.6, 20.4), (7.2, 18.6), 2.35, MOSS[1:], MAT_LIFE, prio=15, part_id=3, curve=-0.6, midrib=True)

    # Upper back crown petals
    cv.draw_petal((16.7, 11.8), (16.7, 2.6), 3.1, TEAL[1:], MAT_BLOOM, prio=18, part_id=10, crease_col=TEAL[0])
    cv.draw_petal((15.5, 12.0), (10.5, 4.2), 2.7, TEAL[1:], MAT_BLOOM, prio=19, part_id=11, curve=-0.8, crease_col=TEAL[0])
    cv.draw_petal((17.8, 12.0), (22.8, 4.4), 2.7, TEAL[1:], MAT_BLOOM, prio=19, part_id=12, curve=0.8, crease_col=TEAL[0])

    # Radiant warm gold center
    cv.draw_gold_core(16.6, 8.6, 2.75, prio=24, part_id=20)

    # Front sculpted cup petals
    cv.draw_petal((15.4, 13.6), (8.8, 7.6), 2.55, TEAL[0:5], MAT_BLOOM, prio=27, part_id=13, curve=-1.1, crease_col=TEAL[0])
    cv.draw_petal((17.9, 13.6), (24.4, 7.5), 2.55, TEAL[0:5], MAT_BLOOM, prio=27, part_id=14, curve=1.1, crease_col=TEAL[0])
    cv.draw_petal((16.6, 14.0), (16.6, 10.6), 3.0, TEAL[0:5], MAT_BLOOM, prio=28, part_id=15, crease_col=TEAL[0])

    # Green calyx cradling flower cup
    cv.draw_petal((16.3, 14.6), (13.2, 13.0), 1.2, MOSS[2:], MAT_LIFE, prio=31, part_id=4)
    cv.draw_petal((16.9, 14.6), (20.0, 12.9), 1.2, MOSS[2:], MAT_LIFE, prio=31, part_id=5)

    add_void_roots(
        cv,
        stem_base=(15.4, 26.8),
        roots=[
            # Left creeping root spreading onto earth + fork biting up toward left leaf tip
            {"p0": (14.4, 27.0), "p1": (11.2, 28.4), "p2": (8.2, 26.8), "r0": 1.35, "r1": 0.55, "prio": 36, "vein_to": 0.72},
            {"p0": (13.4, 26.2), "p1": (11.2, 23.8), "p2": (9.2, 20.6), "r0": 1.25, "r1": 0.55, "prio": 42, "hot_tip": True},
            # Twisting dark Void tendril coiling diagonally around lower stem!
            {"p0": (14.4, 26.6), "p1": (17.2, 23.6), "p2": (13.9, 18.8), "r0": 1.30, "r1": 0.55, "prio": 45, "wrap": True, "hot_tip": True},
            # Right spreading root hugging ground low (leaving right leaf untouched!)
            {"p0": (16.4, 27.0), "p1": (19.4, 28.2), "p2": (22.8, 26.6), "r0": 1.30, "r1": 0.55, "prio": 36, "vein_to": 0.70},
            # Center taproot prong pointing down
            {"p0": (15.4, 27.4), "p1": (15.8, 28.8), "p2": (14.6, 29.6), "r0": 1.15, "r1": 0.45, "prio": 35, "vein_to": 0.65},
        ],
        chew_leaf=(8.4, 20.2, 2.0),
    )
    return cv.apply_outlines()


# ---------------------------------------------------------------------------
# VARIANT B: Stern-Spore (Radiant 5-Petal Shadowspore Star Flower, Title-Inspired)
# ---------------------------------------------------------------------------
def build_variant_b(size: int = 32) -> Image.Image:
    cv = PixelCanvas(size)

    cv.stroke_bezier((15.4, 26.4), (14.2, 21.0), (16.4, 14.5), 1.35, 1.15, MOSS[1:5], MAT_LIFE, prio=12, part_id=1)

    cv.draw_petal((15.9, 19.0), (25.2, 16.0), 2.45, MOSS[1:], MAT_LIFE, prio=16, part_id=2, curve=-0.7, midrib=True)
    cv.draw_petal((14.4, 20.8), (7.0, 19.6), 2.35, MOSS[1:], MAT_LIFE, prio=15, part_id=3, curve=-0.5, midrib=True)

    # Tilted 5-petal star blossom with dark teal crevices separating petals
    cx, cy = 16.5, 9.0
    tilt = 0.14
    petals = [
        (0.0 + tilt, 7.6, 3.0, 18, 10),
        (-1.20 + tilt, 8.2, 2.9, 19, 11),
        (1.20 + tilt, 8.2, 2.9, 19, 12),
        (-2.35 + tilt, 7.5, 2.8, 21, 13),
        (2.35 + tilt, 7.5, 2.8, 21, 14),
    ]
    for ang_off, length, pw, pr, pid in petals:
        ang = -math.pi / 2 + ang_off
        tx = cx + math.cos(ang) * length
        ty = cy + math.sin(ang) * length * 0.92
        bx = cx + math.cos(ang) * 1.2
        by = cy + math.sin(ang) * 1.2
        cv.draw_petal((bx, by), (tx, ty), pw, TEAL[0:], MAT_BLOOM, prio=pr, part_id=pid, tip_glow=0.35, crease_col=TEAL[0])

    cv.draw_gold_core(cx, cy, 3.1, prio=30, part_id=20)

    cv.draw_petal((16.1, 15.0), (13.4, 13.6), 1.2, MOSS[2:], MAT_LIFE, prio=25, part_id=4)
    cv.draw_petal((16.7, 15.0), (19.6, 13.6), 1.2, MOSS[2:], MAT_LIFE, prio=25, part_id=5)

    add_void_roots(
        cv,
        stem_base=(15.4, 26.8),
        roots=[
            {"p0": (14.4, 27.0), "p1": (11.2, 28.6), "p2": (7.8, 26.8), "r0": 1.35, "r1": 0.50, "prio": 36},
            {"p0": (13.4, 26.2), "p1": (10.8, 24.2), "p2": (8.6, 21.0), "r0": 1.25, "r1": 0.55, "prio": 42, "hot_tip": True},
            {"p0": (14.4, 26.6), "p1": (17.2, 23.6), "p2": (13.8, 18.8), "r0": 1.30, "r1": 0.55, "prio": 45, "wrap": True, "hot_tip": True},
            {"p0": (16.4, 27.0), "p1": (19.6, 28.4), "p2": (23.4, 26.6), "r0": 1.30, "r1": 0.50, "prio": 36},
            {"p0": (15.4, 27.4), "p1": (15.8, 28.8), "p2": (14.6, 29.6), "r0": 1.15, "r1": 0.45, "prio": 35},
        ],
        chew_leaf=(7.8, 20.2, 2.3),
    )
    return cv.apply_outlines()


# ---------------------------------------------------------------------------
# VARIANT C: Sporen-Krone (Signature Title-Flower Starburst + S-Stem & Void Roots)
# ---------------------------------------------------------------------------
def build_variant_c(size: int = 32) -> Image.Image:
    cv = PixelCanvas(size)
    s = size / 32.0

    # Tall S-curved meadow stalk inspired directly by title_plants.png big_plant!
    cv.stroke_bezier((15.0, 26.4), (17.6, 20.6), (15.8, 14.5), 1.35, 1.05, MOSS[1:5], MAT_LIFE, prio=12, part_id=1)

    # Staggered foliage pairs: right leaf tucked slightly lower so radial crown glows freely above
    cv.draw_petal((16.2, 19.0), (25.2, 16.4), 2.35, MOSS[1:], MAT_LIFE, prio=16, part_id=2, curve=-0.8, midrib=True)
    cv.draw_petal((15.4, 21.0), (7.4, 19.2), 2.25, MOSS[1:], MAT_LIFE, prio=15, part_id=3, curve=-0.6, midrib=True)

    # Radial glowing filament crown (8 bright tapered spore-rays fanning round a gold heart)
    cx, cy = 15.8, 9.2
    for i in range(8):
        ang = -math.pi / 2 + i * (2 * math.pi / 8) + 0.12
        length = 7.2 if i % 2 == 0 else 6.5
        tx = cx + math.cos(ang) * length
        ty = cy + math.sin(ang) * length * 0.90
        bx = cx + math.cos(ang) * 1.1
        by = cy + math.sin(ang) * 1.0
        cv.draw_petal((bx, by), (tx, ty), 2.1, TEAL[1:], MAT_BLOOM, prio=18 + (i % 2) * 2, part_id=10 + i, tip_glow=0.38, crease_col=TEAL[0])

    cv.draw_gold_core(cx, cy, 2.85, prio=30, part_id=25)

    add_void_roots(
        cv,
        stem_base=(15.0, 26.8),
        roots=[
            {"p0": (14.0, 27.0), "p1": (10.8, 28.6), "p2": (7.6, 26.8), "r0": 1.35, "r1": 0.50, "prio": 36},
            {"p0": (13.4, 26.2), "p1": (10.6, 24.0), "p2": (8.6, 20.6), "r0": 1.25, "r1": 0.55, "prio": 42, "hot_tip": True},
            {"p0": (14.4, 26.6), "p1": (17.2, 23.6), "p2": (15.8, 19.0), "r0": 1.30, "r1": 0.55, "prio": 45, "wrap": True, "hot_tip": True},
            {"p0": (16.0, 27.0), "p1": (19.6, 28.4), "p2": (23.2, 26.6), "r0": 1.30, "r1": 0.50, "prio": 36},
            {"p0": (15.0, 27.4), "p1": (15.4, 28.8), "p2": (14.2, 29.6), "r0": 1.15, "r1": 0.45, "prio": 35},
        ],
        chew_leaf=(7.8, 19.6, 2.3),
    )
    return cv.apply_outlines()


# ---------------------------------------------------------------------------
# Hand-crafted, tall & proportional 16x16 micro-masters (no flat pancakes!)
# ---------------------------------------------------------------------------
MICRO_CMAP = {
    ".": (0, 0, 0, 0),
    "O": OUTLINE_VOID,
    "L": OUTLINE_LIFE,
    "T": OUTLINE_BLOOM_D,
    "1": VOID[0],
    "d": VOID[1],
    "s": VOID[2],
    "r": VOID_STAIN[1],
    "R": VOID_RIM,
    "V": VEIN,
    "v": VEIN_BRIGHT,
    "M": MAGENTA,
    "h": MAGENTA_HOT,
    "k": MOSS[1],
    "m": MOSS[2],
    "n": MOSS[3],
    "N": MOSS[4],
    "H": MOSS[5],
    "b": TEAL[1],
    "c": TEAL[2],
    "t": TEAL[3],
    "e": TEAL[4],
    "g": GOLD[1],
    "G": GOLD[2],
    "W": GOLD[3],
}


def micro_from_rows(rows: list[str]) -> Image.Image:
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(rows):
        assert len(row) == 16, f"Row {y} width {len(row)}"
        for x, ch in enumerate(row):
            px[x, y] = MICRO_CMAP[ch]
    return im


def make_16x16(variant: str) -> Image.Image:
    if variant == "B":
        # Variant B 16x16: crisp 5-petal star bloom, green leaf + chewed diagonal Void vine
        rows = [
            "......TTTT......",
            "....TTteetTT....",
            "..TTtccWWcctTT..",
            ".TtecGWWWWGcetT.",
            ".TtbccWWWWccbtT.",
            "..TtbccGGccbtT..",
            "...TtbccbbctT...",
            "....TTTmmTTT....",
            "......LmNL.LLL..",
            "...LLLmnnLNHnL..",
            "..OrsMLMnLmnLL..",
            "..O1VsdV1dRO....",
            "...O1dVdd1dRRO..",
            "...OOd111dd1OO..",
            "....OOOOOOOOO...",
            "................",
        ]
    elif variant == "C":
        # Variant C 16x16: crisp 8-ray starburst bloom + diagonal Void corruption below
        rows = [
            ".....TT..TT.....",
            "...TTteTTetTT...",
            "..TtcctWWtcctT..",
            ".TtecGWWWWGcetT.",
            "..TtcGWWWWGctT..",
            "..TtbccGGccbtT..",
            "...TTtcbbctTT...",
            "....TT.mm.TT....",
            "......LmNL.LLL..",
            "...LLLmnnLNHnL..",
            "..OrsMLMnLmnLL..",
            "..O1VsdV1dRO....",
            "...O1dVdd1dRRO..",
            "...OOd111dd1OO..",
            "....OOOOOOOOO...",
            "................",
        ]
    else:
        # Variant A 16x16: Sculpted 3-peak lotus crown matching 32x32 + asymmetrical Void tendrils
        rows = [
            "......TTTT......",
            "..TT.TteetT.TT..",
            ".TteTtcWWctTetT.",
            ".TtcceWWWWecctT.",
            ".TtbccGGGGccbtT.",
            "..TbbcbbbbccbT..",
            "...TTbccccbTT...",
            "....TTmmmmTT....",
            "......LmNL.LLL..",
            "...LLLmnnLNHHnL.",
            "..OrsMLMnLmnLL..",
            "..O1VsdV1dRO....",
            "...O1dVdd1dRRO..",
            "...OOd111dd1OO..",
            "....OOOOOOOOO...",
            "................",
        ]
    return micro_from_rows(rows)


def build_variant(variant: str, size: int = 32) -> Image.Image:
    if variant == "B":
        return build_variant_b(size)
    if variant == "C":
        return build_variant_c(size)
    return build_variant_a(size)


def make_apple_touch_icon(master32: Image.Image, out_size: int = 180) -> Image.Image:
    """180x180 iOS/web icon: 5x nearest-neighbor 32x32 plant centered on #07040d with dual Bayer aura."""
    grid = 36
    scale = out_size // grid
    low = np.zeros((grid, grid, 3), dtype=np.uint8)
    base_col = np.array(VOID[0][:3], dtype=np.float32)

    for y in range(grid):
        for x in range(grid):
            d_top = np.hypot(x - 18.0, y - 11.0)
            d_bot = np.hypot(x - 17.5, y - 26.5)
            t_l = max(0.0, 1.0 - d_top / 16.0) * 0.34
            t_v = max(0.0, 1.0 - d_bot / 14.0) * 0.32
            b = BAYER[y % 4, x % 4]
            col = base_col.copy()
            if t_l >= t_v and t_l > b * 0.25:
                col = TEAL[1][:3] if t_l > 0.20 else (14, 34, 42)
            elif t_v > t_l and t_v > b * 0.25:
                col = VOID[3][:3] if t_v > 0.19 else VOID[1][:3]
            low[y, x] = np.clip(col, 0, 255).astype(np.uint8)

    bg_rgba = Image.fromarray(low, "RGB").resize((grid * scale, grid * scale), Image.Resampling.NEAREST).convert("RGBA")
    fg = master32.resize((32 * scale, 32 * scale), Image.Resampling.NEAREST)
    offset = (out_size - fg.width) // 2
    bg_rgba.alpha_composite(fg, (offset, offset))
    return bg_rgba


def make_pixel_svg(img: Image.Image, display_scale: int = 8) -> str:
    w, h = img.size
    px = img.load()
    rects = []
    for y in range(h):
        x = 0
        while x < w:
            r, g, b, a = px[x, y]
            if a == 0:
                x += 1
                continue
            x0 = x
            while x < w and px[x, y] == (r, g, b, a):
                x += 1
            col = f"#{r:02x}{g:02x}{b:02x}"
            opacity = f' fill-opacity="{a / 255:.3f}"' if a < 255 else ""
            rects.append(f'<rect x="{x0}" y="{y}" width="{x - x0}" height="1" fill="{col}"{opacity}/>')
    body = "".join(rects)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w * display_scale}" height="{h * display_scale}" shape-rendering="crispEdges">{body}</svg>\n'
    )


def save_multi_ico(path: Path, images: list[Image.Image]) -> None:
    frames: list[tuple[int, int, bytes]] = []
    for im in images:
        rgba = im.convert("RGBA")
        w, h = rgba.size
        buf = io.BytesIO()
        rgba.save(buf, format="PNG")
        frames.append((w, h, buf.getvalue()))

    header = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries = []
    blobs = []
    for w, h, data in frames:
        wb = 0 if w >= 256 else w
        hb = 0 if h >= 256 else h
        entries.append(struct.pack("<BBBBHHII", wb, hb, 0, 0, 1, 32, len(data), offset))
        blobs.append(data)
        offset += len(data)
    path.write_bytes(header + b"".join(entries) + b"".join(blobs))


def draw_pixel_tag(img: Image.Image, x: int, y: int, label: str, col: tuple[int, int, int, int]) -> None:
    glyphs = {
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    }
    px = img.load()
    g = glyphs[label]
    for gy, row in enumerate(g):
        for gx, bit in enumerate(row):
            if bit == "1":
                for dy in (0, 1):
                    for dx in (0, 1):
                        px[x + gx * 2 + dx, y + gy * 2 + dy] = col


def build_compare_preview() -> None:
    """Compare all 3 plant variants (A, B, C) at zoomed & 1:1 taskbar/beige/dark sizes."""
    W, H = 820, 520
    sheet = Image.new("RGBA", (W, H), (14, 11, 24, 255))
    bgs = [
        (232, 222, 210, 255),  # Exact warm beige from user screenshot
        (16, 24, 23, 255),     # Dark website header
        (10, 7, 18, 255),      # Launcher void night
        (244, 245, 248, 255),  # Windows light taskbar
    ]

    for idx, v in enumerate(("A", "B", "C")):
        x0 = 24 + idx * 262
        draw_pixel_tag(sheet, x0 + 4, 8, v, TEAL[3])
        im32 = build_variant(v, 32)
        im16 = make_16x16(v)
        im24 = im32.resize((24, 24), Image.Resampling.NEAREST)

        p1 = Image.new("RGBA", (120, 148), bgs[0])
        up1 = im32.resize((128, 128), Image.Resampling.NEAREST)
        p1.alpha_composite(up1, (-4, 10))
        sheet.alpha_composite(p1, (x0, 32))

        p2 = Image.new("RGBA", (120, 148), bgs[1])
        p2.alpha_composite(up1, (-4, 10))
        sheet.alpha_composite(p2, (x0 + 126, 32))

        p3 = Image.new("RGBA", (120, 116), bgs[0])
        up16 = im16.resize((96, 96), Image.Resampling.NEAREST)
        p3.alpha_composite(up16, (12, 10))
        sheet.alpha_composite(p3, (x0, 192))

        p4 = Image.new("RGBA", (120, 116), bgs[2])
        p4.alpha_composite(up16, (12, 10))
        sheet.alpha_composite(p4, (x0 + 126, 192))

        im48 = build_variant(v, 48)
        s_beige = Image.new("RGBA", (246, 68), bgs[0])
        s_beige.alpha_composite(im16, (14, 26))
        s_beige.alpha_composite(im24, (44, 22))
        s_beige.alpha_composite(im32, (82, 18))
        s_beige.alpha_composite(im48, (132, 10))
        sheet.alpha_composite(s_beige, (x0, 324))

        s_dark = Image.new("RGBA", (246, 68), bgs[2])
        s_dark.alpha_composite(im16, (14, 26))
        s_dark.alpha_composite(im24, (44, 22))
        s_dark.alpha_composite(im32, (82, 18))
        s_dark.alpha_composite(im48, (132, 10))
        sheet.alpha_composite(s_dark, (x0, 404))

    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_PREVIEW)
    print(f"Compare preview written to {OUT_PREVIEW}")


def build_preview(im16: Image.Image, im32: Image.Image, im48: Image.Image, im_apple: Image.Image) -> None:
    W, H = 760, 440
    sheet = Image.new("RGBA", (W, H), (14, 11, 24, 255))

    def paste_bg(x: int, y: int, bw: int, bh: int, col: tuple[int, int, int, int], im: Image.Image, scale: int) -> None:
        panel = Image.new("RGBA", (bw, bh), col)
        up = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        panel.alpha_composite(up, ((bw - up.width) // 2, (bh - up.height) // 2))
        sheet.alpha_composite(panel, (x, y))

    bgs = [
        (10, 7, 18, 255),
        (16, 24, 23, 255),
        (232, 222, 210, 255),
        (244, 245, 248, 255),
    ]
    for i, bgc in enumerate(bgs):
        paste_bg(24 + i * 178, 24, 160, 160, bgc, im32, 4)

    paste_bg(24, 210, 124, 124, bgs[0], im16, 6)
    paste_bg(158, 210, 124, 124, bgs[2], im16, 6)
    paste_bg(296, 210, 160, 160, bgs[1], im48, 3)

    strip_d = Image.new("RGBA", (150, 70), bgs[0])
    strip_d.alpha_composite(im16, (14, 27))
    strip_d.alpha_composite(im32, (44, 19))
    strip_d.alpha_composite(im48, (90, 11))
    sheet.alpha_composite(strip_d, (24, 346))

    strip_l = Image.new("RGBA", (150, 70), bgs[2])
    strip_l.alpha_composite(im16, (14, 27))
    strip_l.alpha_composite(im32, (44, 19))
    strip_l.alpha_composite(im48, (90, 11))
    sheet.alpha_composite(strip_l, (184, 346))

    sheet.alpha_composite(im_apple, (520, 220))

    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_PREVIEW)
    print(f"Preview written to {OUT_PREVIEW}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("A", "B", "C"), default="A")
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("--preview-only", action="store_true")
    parser.add_argument("--print-inline-svg", action="store_true")
    args = parser.parse_args()

    if args.compare:
        build_compare_preview()
        if args.preview_only:
            return

    im16 = make_16x16(args.variant)
    im32 = build_variant(args.variant, 32)
    im48 = build_variant(args.variant, 48)
    im_apple = make_apple_touch_icon(im32, 180)
    if not args.compare:
        build_preview(im16, im32, im48, im_apple)

    if args.print_inline_svg:
        print("=== 16x16 ===")
        print(make_pixel_svg(im16, display_scale=1).strip())
        print("=== 32x32 ===")
        print(make_pixel_svg(im32, display_scale=1).strip())

    if args.preview_only:
        return

    im64 = im32.resize((64, 64), Image.Resampling.NEAREST)
    im128 = im32.resize((128, 128), Image.Resampling.NEAREST)
    im256 = im32.resize((256, 256), Image.Resampling.NEAREST)

    (ROOT / "icon.svg").write_text(make_pixel_svg(im32, display_scale=8), encoding="utf-8")
    godot_ico = ROOT / "assets" / "ui" / "shadowspore_icon.ico"
    godot_ico.parent.mkdir(parents=True, exist_ok=True)
    save_multi_ico(godot_ico, [im16, im32, im48, im64, im128, im256])

    t_icons = ROOT / "launcher" / "src-tauri" / "icons"
    t_icons.mkdir(parents=True, exist_ok=True)
    im32.save(t_icons / "32x32.png")
    im128.save(t_icons / "128x128.png")
    save_multi_ico(t_icons / "icon.ico", [im16, im32, im48, im64, im128, im256])

    fb_pub = ROOT / "firebase" / "public"
    im32.save(fb_pub / "favicon.png")
    im16.save(fb_pub / "favicon-16.png")
    save_multi_ico(fb_pub / "favicon.ico", [im16, im32])
    im_apple.save(fb_pub / "apple-touch-icon.png")
    spore_mark = fb_pub / "img" / "spore-mark.svg"
    spore_mark.parent.mkdir(parents=True, exist_ok=True)
    spore_mark.write_text(make_pixel_svg(im16, display_scale=1), encoding="utf-8")
    print(f"All plant ({args.variant}) icons written successfully.")


if __name__ == "__main__":
    main()
