#!/usr/bin/env python3
"""Generates the meadow tile atlas (assets/tiles/grass.png, 8x5 tiles of 16x16),
assets/tiles/grass_glow.png (only the emissive pixels, transparent elsewhere),
src/world/tileset.tres, src/world/glow_tileset.tres and data/grass_tiles.json.

Every tile carries a dense, painterly woven carpet of overlapping grass tufts and
curved blades (lit from top-left, matching the pixel-art detail density of bushes,
trees and rocks) using a shared toroidal border field so blades flow seamlessly
across every 16x16 tile edge without grid seams."""
import json
import math
import random
from gen_art import CLEAR, ROOT, hexc, write_png

# Canonical 6-step meadow ramp recognized by ground_tone.gdshader (dark -> sunlit tip)
RAMP = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
D, M, B, L, H, T = RAMP

# Emissive glow palettes (outside RAMP; exported to grass_glow.png)
TEAL_D, TEAL, TEAL_L = hexc("2a8c94"), hexc("3cc0c6"), hexc("8ef8ea")
CAP_D, CAP, CAP_L = hexc("52309e"), hexc("8656dc"), hexc("d2baff")

# Harmonized non-emissive detail palettes (outside RAMP; top-left lit, cool twilight shade)
CREAM_L, CREAM, CREAM_D = hexc("f6f0dc"), hexc("dad1be"), hexc("9e948c")
VIO_L, VIO, VIO_D = hexc("d6c2fa"), hexc("9c7ee2"), hexc("6649b0")
ROSE_L, ROSE, ROSE_D = hexc("f2d2e4"), hexc("ce96b8"), hexc("8e5880")
GOLD_L, GOLD, GOLD_D = hexc("f8e290"), hexc("dda84b"), hexc("9c6c2c")
STEM_L, STEM_D = hexc("ebe2cc"), hexc("a49894")

# Canonical Shadowspore twilight-slate stone ramp (matches tools/art_stone.py)
STONE = [hexc(c) for c in ("1c1a34", "2e2a52", "47436f", "665f94", "8a83b8", "cac4e6")]

BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)

COLS, ROWS = 8, 5

# Shared toroidal border cushions so any two random tiles interlock seamlessly across 16x16 edges
SHARED_BORDER_TUFTS = [
    (0.5, 3.0, 5.2, 3.8, 0.14),
    (7.5, 0.4, 5.6, 3.6, -0.10),
    (14.8, 1.5, 5.0, 3.8, 0.10),
    (15.4, 9.2, 5.2, 4.0, -0.12),
    (1.2, 11.5, 5.0, 3.8, 0.08),
    (8.6, 15.3, 5.6, 3.6, 0.12),
]


def _torus_delta(a: float, b: float) -> float:
    return (a - b + 8.0) % 16.0 - 8.0


def _eval_tuft_field(x: int, y: int, tufts: list[tuple[float, float, float, float, float]]) -> float:
    """Returns clean cel-shaded top-left lighting of broad grassy cushions on a 16x16 torus (no noisy grain)."""
    best_h = -1.0
    second_h = -1.0
    best_lit = 0.0
    px, py = x + 0.5, y + 0.5
    for cx, cy, rx, ry, bias in tufts:
        dx = _torus_delta(px, cx)
        dy = _torus_delta(py, cy)
        r2 = (dx / rx) ** 2 + (dy / ry) ** 2
        if r2 >= 1.35:
            continue
        h = max(0.0, 1.0 - r2) + bias * 0.16
        lit = (-0.42 * (dx / rx) - 0.66 * (dy / ry)) + bias * 0.22
        if h > best_h:
            second_h = best_h
            best_h = h
            best_lit = lit
        elif h > second_h:
            second_h = h
    crevice = max(0.0, 0.18 - (best_h - second_h)) / 0.18 if second_h > 0.04 else 0.0
    return best_lit - crevice * 0.34


# Canonical shared border frame so tile edges match seamlessly with zero 1px orphans
_SHARED_FULL = list(SHARED_BORDER_TUFTS) + [
    (4.8, 5.4, 5.2, 3.9, 0.04),
    (11.4, 5.8, 5.0, 3.8, -0.04),
    (8.0, 10.6, 5.4, 4.0, 0.06),
]


class Tile:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        inner_tufts: list[tuple[float, float, float, float, float]] = list(SHARED_BORDER_TUFTS)
        anchors = [(4.6, 4.8), (11.2, 4.6), (5.2, 10.8), (11.4, 10.6), (8.0, 7.8)]
        for ax, ay in anchors:
            jx = (ax + self.rng.uniform(-1.5, 1.5)) % 16.0
            jy = (ay + self.rng.uniform(-1.3, 1.3)) % 16.0
            rx = self.rng.uniform(4.5, 5.7)
            ry = self.rng.uniform(3.4, 4.3)
            bias = self.rng.uniform(-0.20, 0.22)
            inner_tufts.append((jx, jy, rx, ry, bias))

        steps = [[2] * 16 for _ in range(16)]
        for y in range(16):
            wy = math.sin(math.pi * (y + 0.5) / 16.0) ** 0.85
            for x in range(16):
                wx = math.sin(math.pi * (x + 0.5) / 16.0) ** 0.85
                w_in = max(0.0, min(1.0, (wx * wy) * 1.40))
                lit = _eval_tuft_field(x, y, inner_tufts) * w_in + _eval_tuft_field(x, y, _SHARED_FULL) * (1.0 - w_in)
                # Clean cel-band cushions (M=1, B=2, L=3) without Bayer static
                if lit < -0.26:
                    steps[y][x] = 1
                elif lit > 0.30:
                    steps[y][x] = 3
                else:
                    steps[y][x] = 2

        # Clean up isolated 1px interior cushion specks so every shape reads as a smooth pixel-art cluster
        cleaned = [row[:] for row in steps]
        for y in range(1, 15):
            for x in range(1, 15):
                cur = steps[y][x]
                nb = [steps[y - 1][x], steps[y + 1][x], steps[y][x - 1], steps[y][x + 1]]
                if nb.count(cur) == 0:
                    cleaned[y][x] = max(set(nb), key=nb.count)
        self.px = [[RAMP[cleaned[y][x]] for x in range(16)] for y in range(16)]

        # Place 4 well-spaced, crisp pixel-art mini grass-blade / clover clusters inside the tile
        placed: list[tuple[int, int]] = []
        target = 4 + (seed % 2)
        for attempt in range(40):
            if len(placed) >= target:
                break
            bx = self.rng.randint(2, 13)
            by = self.rng.randint(3, 13)
            if any((bx - px0) ** 2 + (by - py0) ** 2 < 18 for px0, py0 in placed):
                continue
            placed.append((bx, by))
            kind = (seed + len(placed) + attempt) % 3
            lean = -1 if (bx + by + seed) % 2 == 0 else 1
            if kind == 0:
                # Crisp V-blade pair with root tuck
                self.put(bx, by, D)
                self.put(bx + 1, by, M)
                self.put(bx, by - 1, L)
                self.put(bx - 1, by - 2, H)
                self.put(bx + 1, by - 1, L)
            elif kind == 1:
                # Curved twin grass blades sweeping with the breeze
                self.put(bx, by, D)
                self.put(bx + 1, by, D if lean < 0 else M)
                self.put(bx, by - 1, L)
                self.put(bx + lean, by - 2, H)
                self.put(bx + 1, by - 1, M)
                self.put(bx + 1 + lean, by - 2, L)
            else:
                # Scalloped 3-leaf turf cluster (matches bush leaf facets)
                self.put(bx - 1, by, M)
                self.put(bx, by, D)
                self.put(bx + 1, by, D)
                self.put(bx - 1, by - 1, H)
                self.put(bx, by - 1, L)
                self.put(bx + 1, by - 1, M)
                self.put(bx, by - 2, H)

    def wput(self, x: int, y: int, c) -> None:
        self.px[y % 16][x % 16] = c

    def put(self, x: int, y: int, c) -> None:
        if 0 <= x < 16 and 0 <= y < 16:
            self.px[y][x] = c

    def arc_blade(self, x: int, y: int, h: int, lean: int, base_c, mid_c, tip_c) -> None:
        """Draws a gently curved, tapered grass blade from (x, y) upward."""
        for j in range(h):
            t = j / max(1, h - 1)
            dx = int(round(lean * (t ** 1.35)))
            c = base_c if j == 0 else (tip_c if j == h - 1 else mid_c)
            self.put(x + dx, y - j, c)

    def tuft(self, x: int, y: int, h: int = 4) -> None:
        """Organic fanning 4-5 blade meadow tuft with sculpted shadow pocket."""
        self.put(x - 2, y, M)
        self.put(x - 1, y, D)
        self.put(x, y, D)
        self.put(x + 1, y, D)
        self.put(x + 2, y, M)
        self.arc_blade(x - 1, y - 1, max(3, h - 1), -2, M, L, H)
        self.arc_blade(x, y - 1, h + 1, -1, L, H, T)
        self.arc_blade(x + 1, y - 1, h, 1, M, L, H)
        self.arc_blade(x + 2, y, max(2, h - 1), 2, D, M, L)

    def clump(self, x: int, y: int) -> None:
        """Lush layered cushion of curved overlapping meadow blades."""
        for dx in range(-3, 4):
            self.put(x + dx, y, D if -2 <= dx <= 2 else M)
        for dx in range(-3, 3):
            self.put(x + dx, y - 1, D if dx >= 1 else M)
        specs = [
            (-3, 0, 4, -2, M, L, H),
            (-2, -1, 5, -2, L, H, T),
            (-1, -1, 6, -1, L, H, T),
            (0, -1, 5, 1, M, L, H),
            (1, -1, 5, 2, M, L, H),
            (2, 0, 4, 2, D, M, L),
        ]
        for dx, dy, bh, lean, c0, c1, c2 in specs:
            self.arc_blade(x + dx, y + dy, bh, lean, c0, c1, c2)

    def stem_with_leaves(self, x: int, y: int, h: int, lean: int = 0) -> tuple[int, int]:
        """Curved slender plant stem with basal leaves; returns flower head (hx, hy)."""
        self.put(x, y, D)
        self.put(x - 1, y, D)
        self.put(x + 1, y, D)
        self.put(x - 1, y - 1, L)
        self.put(x + 1, y - 1, M)
        hx = x
        for j in range(1, h + 1):
            hx = x + (lean if j >= (h + 1) // 2 else 0)
            self.put(hx, y - j, M if j == 1 else L)
        return hx, y - h

    def moon_flower(self, x: int, y: int, h: int = 4, kind: str = "cream") -> None:
        """Shaded cup/daisy meadow blossom with top-left petal highlights."""
        palettes = {
            "cream": (CREAM_L, CREAM, CREAM_D, GOLD),
            "rose": (ROSE_L, ROSE, ROSE_D, GOLD_L),
            "gold": (GOLD_L, GOLD, GOLD_D, CREAM_L),
            "violet": (VIO_L, VIO, VIO_D, GOLD_L),
        }
        hi, mid, sh, center = palettes[kind]
        lean = -1 if (x + y) % 2 == 0 else 1
        hx, hy = self.stem_with_leaves(x, y, h, lean)
        self.put(hx, hy - 1, hi)
        self.put(hx - 1, hy - 1, hi)
        self.put(hx - 1, hy, mid)
        self.put(hx + 1, hy, sh)
        self.put(hx, hy + 1, sh)
        self.put(hx, hy, center)

    def star_flower(self, x: int, y: int, h: int = 4) -> None:
        """Nodding twilight-violet bell / star blossom."""
        lean = 1 if x % 2 == 0 else -1
        hx, hy = self.stem_with_leaves(x, y, h, lean)
        self.put(hx - 1, hy - 1, VIO_L)
        self.put(hx, hy - 1, VIO_L)
        self.put(hx - 1, hy, VIO)
        self.put(hx, hy, VIO)
        self.put(hx + 1, hy, VIO_D)
        self.put(hx, hy + 1, GOLD_L)

    def glow_bloom(self, x: int, y: int, variant: int = 0) -> None:
        """Luminous teal night-chalice cradled in curved calyx leaves + subtle spore motes."""
        self.put(x - 1, y + 1, D)
        self.put(x, y + 1, D)
        self.put(x + 1, y + 1, D)
        self.arc_blade(x - 1, y, 3, -2, M, L, H)
        self.arc_blade(x + 1, y, 3, 2, D, M, L)
        self.put(x, y, D)
        cy = y - 2
        self.put(x - 1, cy, TEAL)
        self.put(x + 1, cy, TEAL_D)
        self.put(x, cy + 1, TEAL_D)
        self.put(x - 1, cy - 1, TEAL_L)
        self.put(x, cy - 1, TEAL_L)
        self.put(x + 1, cy - 1, TEAL)
        self.put(x, cy, TEAL_L)
        motes = [(-2, -3), (2, -4)] if variant % 2 == 0 else [(-3, -2), (2, -3)]
        for dx, dy in motes:
            self.put(x + dx, cy + dy, TEAL_L if dy < -2 else TEAL)

    def mushroom(self, x: int, y: int, teal: bool = False, big: bool = True) -> None:
        """Rounded, domed luminous mushroom cap on a 2-tone curved stem nestled in moss."""
        c_hi, c_mid, c_sh = (TEAL_L, TEAL, TEAL_D) if teal else (CAP_L, CAP, CAP_D)
        self.put(x - 1, y, D)
        self.put(x, y, D)
        self.put(x + 1, y, D)
        if big:
            self.put(x, y - 1, STEM_L)
            self.put(x + 1, y - 1, STEM_D)
            self.put(x, y - 2, STEM_L)
            self.put(x + 1, y - 2, STEM_D)
            for dx in (-1, 0, 1):
                self.put(x + dx, y - 5, c_hi if dx <= 0 else c_mid)
            for dx in (-2, -1, 0, 1, 2):
                self.put(x + dx, y - 4, c_hi if dx < 0 else (c_mid if dx <= 1 else c_sh))
            self.put(x - 2, y - 3, c_mid)
            self.put(x - 1, y - 3, c_mid)
            self.put(x + 2, y - 3, c_sh)
        else:
            self.put(x, y - 1, STEM_L)
            self.put(x - 1, y - 3, c_hi)
            self.put(x, y - 3, c_hi)
            self.put(x + 1, y - 3, c_mid)
            self.put(x - 1, y - 2, c_mid)
            self.put(x, y - 2, c_mid)
            self.put(x + 1, y - 2, c_sh)

    def stone(self, x: int, y: int, size: int = 2) -> None:
        """Faceted twilight-slate pebble embedded in turf with top-left plane lighting."""
        if size >= 2:
            for dx in range(-3, 4):
                self.put(x + dx, y + 1, D if -2 <= dx <= 2 else M)
            rows = [
                (-3, [None, STONE[5], STONE[4], STONE[3], None, None]),
                (-2, [STONE[4], STONE[5], STONE[4], STONE[3], STONE[2], None]),
                (-1, [STONE[3], STONE[3], STONE[2], STONE[2], STONE[1], STONE[1]]),
                (0, [None, STONE[1], STONE[1], STONE[0], STONE[0], None]),
            ]
            for dy, cols in rows:
                for i, c in enumerate(cols):
                    if c is not None:
                        self.put(x - 2 + i, y + dy, c)
            self.put(x + 1, y - 2, L)
            self.put(x + 2, y - 1, M)
            self.put(x - 2, y, D)
        else:
            self.put(x - 1, y + 1, D)
            self.put(x, y + 1, D)
            self.put(x + 1, y + 1, D)
            self.put(x - 1, y - 1, STONE[4])
            self.put(x, y - 1, STONE[3])
            self.put(x - 1, y, STONE[2])
            self.put(x, y, STONE[1])
            self.put(x + 1, y, STONE[0])

    def fern(self, x: int, y: int, flip: bool = False) -> None:
        """Radiating woodland fern rosette with 5 feathery curved fronds."""
        s = -1 if flip else 1
        for dy in (-1, 0, 1):
            for dx in range(-2, 3):
                if abs(dx) + abs(dy) <= 2:
                    self.put(x + dx, y + dy, D)
        fronds = [
            [(-1 * s, -1, L), (-2 * s, -2, H), (-3 * s, -2, T), (-2 * s, -1, L)],
            [(0, -1, L), (-1 * s, -2, H), (-1 * s, -3, T), (0, -2, H)],
            [(1 * s, -1, M), (2 * s, -2, L), (3 * s, -2, H), (2 * s, -1, M)],
            [(-2 * s, 0, L), (-3 * s, 0, H), (-4 * s, 1, L)],
            [(1 * s, 0, M), (2 * s, 0, L), (3 * s, 1, M)],
        ]
        for pts in fronds:
            for dx, dy, c in pts:
                self.put(x + dx, y + dy, c)

    def petals(self, spots: list[tuple[int, int, tuple, tuple]]) -> None:
        """Soft wind-drifted 2-pixel blossom petals nestled in the grass."""
        for x, y, hi, sh in spots:
            self.put(x, y + 1, D)
            self.put(x + 1, y + 1, M)
            self.put(x, y, hi)
            self.put(x + 1, y, sh)

    def clover(self, x: int, y: int) -> None:
        """Readable patch of 3-leaf shamrock trefoils with a tiny pale clover bud."""
        trefoils = [(x, y, True), (x + 3, y + 2, False), (x - 2, y + 3, False), (x + 1, y + 5, True)]
        for cx, cy, bright in trefoils:
            self.put(cx, cy + 1, D)
            self.put(cx + 1, cy + 1, D)
            self.put(cx - 1, cy, H if bright else L)
            self.put(cx, cy - 1, T if bright else H)
            self.put(cx + 1, cy, L if bright else M)
            self.put(cx, cy, D)
        self.put(x + 2, y - 1, CREAM_L)
        self.put(x + 3, y - 1, ROSE_L)

    def glyph(self, x: int, y: int) -> None:
        """Ancient sunken fae-ring of moss and luminous teal rune arcs."""
        for a_deg in range(0, 360, 25):
            rad = math.radians(a_deg)
            rx = int(round(x + math.cos(rad) * 4.2))
            ry = int(round(y + math.sin(rad) * 2.8))
            self.put(rx, ry, D)
        for dx, dy, c in [
            (-4, 0, TEAL), (-3, -2, TEAL_L), (0, -3, TEAL),
            (3, -2, TEAL_D), (4, 0, TEAL), (3, 2, TEAL_D),
            (0, 3, TEAL_L), (-3, 2, TEAL), (0, 0, TEAL_L),
        ]:
            self.put(x + dx, y + dy, c)
        self.put(x, y + 1, D)


def build() -> tuple[list[Tile], dict[str, list[int]]]:
    tiles: list[Tile] = []
    cats: dict[str, list[int]] = {}

    def add(cat: str, t: Tile) -> None:
        cats.setdefault(cat, []).append(len(tiles))
        tiles.append(t)

    for i in range(8):
        add("plain", Tile(10 + i * 7))
    for i, (x, y, h) in enumerate(((5, 12, 4), (10, 9, 3), (7, 13, 4), (11, 8, 3))):
        t = Tile(30 + i * 5)
        t.tuft(x, y, h)
        add("tuft", t)
    for i, (x, y) in enumerate(((8, 12), (6, 10), (10, 13))):
        t = Tile(40 + i * 5)
        t.clump(x, y)
        add("clump", t)
    flowers = [
        lambda t: t.moon_flower(5, 12, 4, "violet") or t.moon_flower(11, 9, 3, "cream"),
        lambda t: t.moon_flower(8, 12, 4, "cream") or t.tuft(3, 7, 3),
        lambda t: t.star_flower(11, 11, 3) or t.star_flower(5, 8, 4) or t.moon_flower(7, 13, 3, "cream"),
        lambda t: t.star_flower(7, 12, 4) or t.tuft(12, 7, 3),
        lambda t: t.moon_flower(4, 8, 3, "rose") or t.moon_flower(10, 12, 4, "rose") or t.moon_flower(13, 7, 3, "cream"),
        lambda t: t.moon_flower(6, 12, 3, "gold") or t.moon_flower(11, 8, 4, "gold"),
    ]
    for i, draw in enumerate(flowers):
        t = Tile(50 + i * 5)
        draw(t)
        add("flower", t)
    for i, (x, y) in enumerate(((6, 11), (10, 12), (8, 10))):
        t = Tile(60 + i * 5)
        t.glow_bloom(x, y, i)
        if i == 1:
            t.tuft(3, 7, 3)
        add("bloom", t)
    shrooms = [
        lambda t: t.mushroom(6, 12, teal=False, big=True) or t.mushroom(11, 13, teal=False, big=False),
        lambda t: t.mushroom(5, 11, teal=False, big=False) or t.mushroom(10, 12, teal=False, big=True),
        lambda t: t.mushroom(8, 12, teal=True, big=False) or t.tuft(12, 7, 3),
    ]
    for i, draw in enumerate(shrooms):
        t = Tile(70 + i * 5)
        draw(t)
        add("mushroom", t)
    for i, (x, y, s) in enumerate(((8, 11, 2), (5, 10, 1), (10, 12, 2))):
        t = Tile(80 + i * 5)
        t.stone(x, y, s)
        if i == 1:
            t.stone(12, 6, 1)
        add("stone", t)
    for i, (x, y) in enumerate(((8, 11), (7, 10))):
        t = Tile(90 + i * 5)
        t.fern(x, y, flip=(i == 1))
        add("fern", t)
    for i in range(2):
        t = Tile(100 + i * 5)
        spots = (
            [(3, 5, VIO_L, VIO), (9, 9, CREAM_L, CREAM), (12, 4, ROSE_L, ROSE), (6, 13, VIO_L, VIO)]
            if i == 0
            else [(4, 4, CREAM_L, CREAM), (11, 8, VIO_L, VIO), (3, 11, ROSE_L, ROSE), (12, 13, CREAM_L, CREAM)]
        )
        t.petals(spots)
        add("petal", t)
    for i, (x, y) in enumerate(((6, 5), (8, 6))):
        t = Tile(110 + i * 5)
        t.clover(x, y)
        add("clover", t)
    t = Tile(120)
    t.glyph(8, 8)
    add("glyph", t)
    return tiles, cats


def write_all() -> None:
    tiles, cats = build()
    assert len(tiles) <= COLS * ROWS, len(tiles)
    atlas = [[CLEAR] * (COLS * 16) for _ in range(ROWS * 16)]
    for i, t in enumerate(tiles):
        ox, oy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                atlas[oy + y][ox + x] = t.px[y][x]
    # Pad unused slots with woven plain turf so no slot is ever flat
    pad_tile = Tile(999)
    for i in range(len(tiles), COLS * ROWS):
        ox, oy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                atlas[oy + y][ox + x] = pad_tile.px[y][x]
    write_png(ROOT / "tiles" / "grass.png", COLS * 16, ROWS * 16, atlas)

    lines = [
        '[gd_resource type="TileSet" format=3 uid="uid://b5g6cx28s5x2j"]',
        "",
        '[ext_resource type="Texture2D" uid="uid://ct1t4f7w8clec" path="res://assets/tiles/grass.png" id="1_grass"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_grass"]',
        'texture = ExtResource("1_grass")',
    ]
    for i in range(len(tiles)):
        lines += [f"{i % COLS}:{i // COLS}/0 = 0", f'{i % COLS}:{i // COLS}/0/custom_data_0 = "grass"']
    lines += [
        "",
        "[resource]",
        'custom_data_layer_0/name = "surface"',
        "custom_data_layer_0/type = 4",
        'sources/0 = SubResource("TileSetAtlasSource_grass")',
        "",
    ]
    (ROOT.parent / "src" / "world" / "tileset.tres").write_text("\n".join(lines), newline="\n")

    emissive = {TEAL_D, TEAL, TEAL_L, CAP_D, CAP, CAP_L}
    glow_ids = [i for cat in ("bloom", "mushroom", "glyph") for i in cats.get(cat, [])]
    glow = [[CLEAR] * (COLS * 16) for _ in range(ROWS * 16)]
    for i in glow_ids:
        ox, oy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                if tiles[i].px[y][x] in emissive:
                    glow[oy + y][ox + x] = tiles[i].px[y][x]
    write_png(ROOT / "tiles" / "grass_glow.png", COLS * 16, ROWS * 16, glow)
    glow_lines = [
        '[gd_resource type="TileSet" format=3 uid="uid://rybu0whxuyiw"]',
        "",
        '[ext_resource type="Texture2D" uid="uid://c6gnadejlyto1" path="res://assets/tiles/grass_glow.png" id="1_glow"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_glow"]',
        'texture = ExtResource("1_glow")',
    ]
    for i in glow_ids:
        glow_lines.append(f"{i % COLS}:{i // COLS}/0 = 0")
    glow_lines += [
        "",
        "[resource]",
        'sources/0 = SubResource("TileSetAtlasSource_glow")',
        "",
    ]
    (ROOT.parent / "src" / "world" / "glow_tileset.tres").write_text("\n".join(glow_lines), newline="\n")
    table = {cat: [[i % COLS, i // COLS] for i in ids] for cat, ids in cats.items()}
    (ROOT.parent / "data" / "grass_tiles.json").write_text(json.dumps(table, indent=1) + "\n", newline="\n")


if __name__ == "__main__":
    write_all()
    print("ok")
