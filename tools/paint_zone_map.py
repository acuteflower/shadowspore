#!/usr/bin/env python3
"""Offline v2 Atlas & Zone Map Baker for Shadowspore (Steps 6-8).

Generates:
  Per-Zone (`data/world/zones/<zone_id>/baked/`):
    - map.png         (w*4 x h*4 RGBA8, muted cartographic palette, zero #000000)
    - map_light.png   (w*4 x h*4 RGBA8, R=nx, G=ny, B=elev, A=feature_mask)
    - far.png         (w x h RGBA8, 1 px/tile desaturated blue-shifted aerial view)
    - meta.json       (origin, size, px_per_tile, light_alpha_bits, campfires, settlements)

  Per-Continent (`data/world/continents/baked/<continent_id>/`):
    - continent_map.png    (1 px/tile RGBA8 composite + borderlands + wide ocean + optional Great Rift)
    - continent_light.png  (1 px/tile RGBA8 normals/elevation/feature_mask)
    - engraving.png        (1 px/tile RGBA8 monochrome Stone-Setter slate relief + PixelText old names)
    - continent_meta.json  (continent_id, size, px_per_tile, rift_pos, rift_radius, ocean_currents, old_names)

Uses ONLY Python 3 stdlib + PIL (Pillow) + numpy.
"""
from __future__ import annotations

import argparse
import bisect
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
import json
import math
import os
import pathlib
import sys
import time
from typing import Any

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR = ROOT / "data"
DEFAULT_WORLD_DIR = DEFAULT_DATA_DIR / "world"

PX_PER_TILE = 4
CONTINENT_PX_PER_TILE = 1

# Atlas & Landscape constants (exact parity with src/world/atlas.gd & src/world/v2/landscape.gd)
CURVE_STEP = 1.5
BELT_SPACING = 4.8
BELT_OUT = 3.4
WAY_GAP = 2.6
MOUTH = 7.0
MOUTH_CLEAR = 2.2
GLADE_EDGE = 1.4
PLAN_GRID = 8.0
BORDER_TILES = 6.0
ZONE_BAKE_MARGIN = 8.0
WATER_BAKE_MARGIN = 24.0
VOID_BAKE_MARGIN = 3.5
SEAMLESS_KINDS = {"path", "pass", "ford", "bridge", "jump"}
HARD_KINDS = {"tunnel", "ferry", "ship"}
DEFAULT_BELT_MIX = [
    {"species": "valley_oak", "w": 0.6, "stages": [3, 4, 5]},
    {"species": "silver_birch", "w": 0.4, "stages": [2, 3, 4]},
]

# Light alpha bitmask (Contract B)
BIT_WATER = 1
BIT_MEADOW = 2
BIT_CANOPY = 4
BIT_GLOW_WARM = 8
BIT_GLOW_ARCANE = 16
BIT_INK_CLIFF = 32
BIT_SAND_WAY = 64
BIT_VALID = 128

LIGHT_ALPHA_BITS = {
    "WATER": BIT_WATER,
    "MEADOW": BIT_MEADOW,
    "CANOPY": BIT_CANOPY,
    "GLOW_WARM": BIT_GLOW_WARM,
    "GLOW_ARCANE": BIT_GLOW_ARCANE,
    "INK_CLIFF": BIT_INK_CLIFF,
    "SAND_WAY": BIT_SAND_WAY,
    "VALID": BIT_VALID,
}

# Crisp Pixel-Art Cartographer Palettes (exact parity with firebase/public/map.mjs & docs/design_guide.md, ZERO #000000)
INK_PIXEL = np.array([17.0, 11.0, 28.0], dtype=np.float32)  # #110b1c (map.mjs INK)
INK_DARK = (17, 11, 28)       # #110b1c
INK_STRUCT = (24, 20, 40)     # #181428
INK_DEEP = (13, 8, 24)        # #0d0818
INK_SHORE = (17, 11, 28)      # #110b1c

# 4x4 Ordered Bayer Dither Matrix (map.mjs BAYER[16] / 16.0)
BAYER_4X4 = np.array([
    [0.0, 8.0, 2.0, 10.0],
    [12.0, 4.0, 14.0, 6.0],
    [3.0, 11.0, 1.0, 9.0],
    [15.0, 7.0, 13.0, 5.0],
], dtype=np.float32) * (1.0 / 16.0)

# 3-Tone Curated Biome Palettes [shadow, mid, highlight] (exact map.mjs look!)
# 0: Gruenland / Wiesenlande / Suedwestkueste ("DIE LICHTUNG": #22483c, #387654, #6cb46a)
# 1: Glaskamm / Hallgrat (W/NW cool pine-slate teal with pale klangstein highlights)
# 2: Hexenwald / Schattenwald (SO deep indigo-slate: #1b1d34, #34415e, #617496)
# 3: Leerenbluehen / Herrschaft Varn (East muted plum-slate olive-grey leading into Great Rift)
# 4: Suedwestkueste warm sunlit coastal meadow (subtle emerald-sage lift matching Gruenland)
# 5: Kristallgrat / Zinnen (cool high alpine slate-blue with crystalline rock)
# 6: Sonnenquarz / Steppe fallback (map.mjs quartz_desert: #422926, #97613e, #e2b36c)
BIOME_PALETTES = np.array([
    [[34, 72, 60], [56, 118, 84], [108, 180, 106]],     # 0: meadow / gruenland
    [[26, 52, 64], [46, 92, 100], [98, 156, 152]],      # 1: glaskamm / hallgrat
    [[27, 29, 52], [52, 65, 94], [97, 116, 150]],       # 2: hexenwald
    [[37, 30, 52], [70, 64, 86], [124, 114, 130]],      # 3: leerenbluehen / varn
    [[36, 76, 62], [61, 125, 86], [116, 186, 110]],     # 4: suedwestkueste
    [[34, 48, 68], [64, 90, 114], [126, 162, 178]],     # 5: kristallgrat / zinnen
    [[66, 41, 38], [151, 97, 62], [226, 179, 108]],     # 6: quartz / steppe
], dtype=np.float32)

# Cohesive 3-tone woodland canopy carpets per biome [deep_shadow, mid_canopy, sunlit_crown]
CANOPY_PALETTES = np.array([
    [[22, 48, 44], [34, 78, 58], [62, 122, 74]],        # 0: meadow woods (rich deep emerald)
    [[18, 36, 48], [30, 64, 74], [56, 108, 110]],       # 1: glaskamm pine
    [[18, 19, 38], [32, 42, 66], [56, 72, 104]],        # 2: hexenwald dark indigo-spruce
    [[25, 20, 38], [46, 40, 60], [78, 68, 88]],         # 3: leerenbluehen blighted cypress
    [[24, 52, 46], [38, 84, 62], [68, 130, 80]],        # 4: coastal grove
    [[22, 34, 50], [38, 62, 82], [70, 104, 122]],       # 5: alpine pine
    [[44, 30, 28], [86, 62, 44], [134, 102, 64]],       # 6: dry scrub
], dtype=np.float32)

# High-plateau rock / klangstein highlights for Glaskamm / Kristallgrat peaks
KLANGSTEIN_PAL = np.array([
    [40, 62, 74],
    [68, 98, 108],
    [114, 148, 152],
], dtype=np.float32)

# 5x5 hand-inked cartographer symbols per biome (exact bitmasks from map.mjs / world_map.gdshader)
GLYPHS_5X5 = [
    (146080, 135620),      # 0: meadow tufts / clover
    (32969156, 163268),    # 1: glaskamm / conifer & stone
    (17978692, 476608),    # 2: hexenwald gnarled boughs
    (4543812, 18157905),   # 3: leerenbluehen arcane spores
    (146080, 135620),      # 4: suedwestkueste meadow sprigs
    (33073280, 145860),    # 5: kristallgrat crystal spires
    (19285440, 32986244),  # 6: steppe / quartz
]
GLYPH_DENSITY = [0.34, 0.42, 0.38, 0.40, 0.34, 0.42, 0.36]

# Shared 5-Tone Bayer-Dithered Pixel-Art Ocean Palette (locked with atlas_continent/world.gdshader!)
OCEAN0 = np.array([7.0, 15.0, 29.0], dtype=np.float32)       # #070f1d abyssal trench
OCEAN1 = np.array([11.0, 25.0, 45.0], dtype=np.float32)      # #0b192d deep pelagic
OCEAN2 = np.array([16.0, 36.0, 61.0], dtype=np.float32)      # #10243d mid sapphire
OCEAN3 = np.array([22.0, 50.0, 80.0], dtype=np.float32)      # #163250 ocean swell
OCEAN4 = np.array([30.0, 66.0, 96.0], dtype=np.float32)      # #1e4260 coastal shelf
OCEAN_PAL = np.stack([OCEAN0, OCEAN1, OCEAN2, OCEAN3, OCEAN4], axis=0)
OCEAN_RIDGE = np.array([43.0, 96.0, 120.0], dtype=np.float32)  # #2b6078 deep swell ridge
RIPPLE_TINT = np.array([62.0, 136.0, 154.0], dtype=np.float32) # #3e889a 3 undulating shore ripples
SHORE_HALO = np.array([72.0, 166.0, 176.0], dtype=np.float32)  # #48a6b0 coastal cyan aura
COAST_RIM = np.array([150.0, 235.0, 224.0], dtype=np.float32)  # #96ebe0 luminous surf coastline rim

# Ocean-Harmonized Cartographer Lake & River Palette (unified sapphire-turquoise liquid family with OCEAN0..4 & SURF_*)
LAKE_DEEP = np.array([13.0, 30.0, 52.0], dtype=np.float32)       # #0d1e34 (bridges OCEAN1 #0b192d & OCEAN2 #10243d)
LAKE_MIDDEEP = OCEAN3.copy()                                     # #163250 (exact OCEAN3 pelagic swell)
LAKE_MID = OCEAN4.copy()                                         # #1e4260 (exact OCEAN4 coastal shelf)
LAKE_SHELF = np.array([44.0, 110.0, 126.0], dtype=np.float32)    # #2c6e7e (bridges OCEAN_RIDGE #2b6078 & SURF_LAGOON #2c7c86)
LAKE_SHALLOW = np.array([66.0, 156.0, 162.0], dtype=np.float32)  # #429ca2 (bridges RIPPLE_TINT #3e889a & SURF_SWASH #4caeac)
LAKE_LIGHT = np.array([140.0, 226.0, 218.0], dtype=np.float32)   # #8ce2da (matches COAST_RIM #96ebe0 sunlit shimmer)
LAKE_PAL = np.stack([LAKE_SHALLOW, LAKE_SHELF, LAKE_MID, LAKE_MIDDEEP, LAKE_DEEP], axis=0)

# Zone-level Bayer-dithered material palettes (harmonized with BIOME_PALETTES)
MEADOW_RAMP = np.array([
    [34, 72, 60],
    [56, 118, 84],
    [108, 180, 106],
], dtype=np.float32)

HEX_RAMP = np.array([
    [27, 29, 52],
    [52, 65, 94],
    [97, 116, 150],
], dtype=np.float32)

STEPPE_RAMP = np.array([
    [66, 41, 38],
    [151, 97, 62],
    [226, 179, 108],
], dtype=np.float32)

HUMUS_RAMP = np.array([
    [26, 40, 38],
    [38, 64, 52],
    [54, 92, 66],
], dtype=np.float32)

MOSS_RAMP = np.array([
    [28, 58, 52],
    [46, 94, 70],
    [82, 146, 88],
], dtype=np.float32)

BEDROCK_RAMP = np.array([
    [40, 52, 68],
    [68, 86, 102],
    [108, 128, 138],
    [154, 170, 172],
], dtype=np.float32)

BEACH_DRY = np.array([
    [154, 130, 92],
    [192, 166, 118],
    [224, 200, 148],
], dtype=np.float32)
BEACH_WET = np.array([102.0, 88.0, 72.0], dtype=np.float32)
HOLLOW_DAMP = np.array([32.0, 62.0, 50.0], dtype=np.float32)
HOLLOW_MUD = np.array([24.0, 46.0, 44.0], dtype=np.float32)

# Legacy alias constants kept for compatibility
OCEAN_ABYSS = OCEAN0
OCEAN_DEEP = OCEAN1
OCEAN_MID = OCEAN2
OCEAN_SHELF = OCEAN4
OCEAN_CURRENT = RIPPLE_TINT

SURF_OUTER = np.array([30.0, 82.0, 102.0], dtype=np.float32)
SURF_LAGOON = np.array([44.0, 124.0, 134.0], dtype=np.float32)
SURF_SWASH = np.array([76.0, 174.0, 172.0], dtype=np.float32)
SURF_FOAM = (150, 235, 224)

BROOK_DEEP = LAKE_DEEP
BROOK_MID = LAKE_MID
BROOK_SHALLOW = LAKE_SHELF
FORD_SHINGLE = np.array([138.0, 142.0, 124.0], dtype=np.float32)
RIPARIAN_COLLAR = np.array([30.0, 62.0, 52.0], dtype=np.float32)

# Way palettes
WAY_STYLES = {
    "trail": {"half_px": 1.4, "core": (162, 140, 110), "mid": (126, 108, 86), "edge": (68, 56, 52), "dashed": True},
    "quarry_trail": {"half_px": 1.3, "core": (132, 140, 142), "mid": (98, 108, 114), "edge": (52, 56, 70), "dashed": True},
    "footpath": {"half_px": 1.5, "core": (166, 144, 112), "mid": (128, 110, 86), "edge": (66, 54, 52), "dashed": False},
    "path": {"half_px": 2.1, "core": (182, 160, 124), "mid": (146, 126, 98), "edge": (62, 50, 48), "dashed": False},
    "cart": {"half_px": 2.8, "core": (196, 174, 138), "mid": (158, 138, 108), "edge": (52, 42, 46), "rut": (112, 96, 78)},
    "road": {"half_px": 2.9, "core": (196, 174, 138), "mid": (158, 138, 108), "edge": (48, 38, 44), "rut": (112, 96, 78)},
    "cobble": {"half_px": 3.0, "core": (138, 148, 156), "mid": (106, 116, 126), "edge": (34, 32, 50), "rut": (84, 92, 104)},
    "stone_road": {"half_px": 3.0, "core": (138, 148, 156), "mid": (106, 116, 126), "edge": (34, 32, 50), "rut": (84, 92, 104)},
}

# Fallback tree palettes (se, mid, nw, hi, rim) and crown radii (world px)
DEFAULT_TREE_PALETTES = {
    "valley_oak": {
        "shades": [(26, 56, 50), (42, 92, 66), (76, 142, 86), (124, 188, 108)],
        "rim": (17, 15, 32),
        "flecks": [],
        "crown_half_px": [6, 13, 26, 46, 76, 102, 48],
    },
    "silver_birch": {
        "shades": [(30, 64, 54), (58, 122, 80), (108, 174, 102), (160, 218, 132)],
        "rim": (17, 22, 34),
        "flecks": [(220, 216, 236)],
        "crown_half_px": [5, 10, 22, 40, 58, 80, 48],
    },
    "wild_apple": {
        "shades": [(28, 60, 48), (52, 108, 68), (94, 154, 84), (144, 198, 110)],
        "rim": (17, 20, 32),
        "flecks": [(236, 142, 174), (255, 224, 236)],
        "crown_half_px": [5, 11, 28, 44, 68, 86, 46],
    },
    "fir": {
        "shades": [(18, 36, 48), (28, 64, 68), (44, 102, 88), (74, 142, 108)],
        "rim": (16, 14, 34),
        "flecks": [(98, 166, 146)],
        "crown_half_px": [11, 16, 22, 31, 40, 43, 24],
    },
}
SPECIES_ALIASES = {
    "spruce": "fir",
    "pine": "fir",
    "ancient_fir": "fir",
    "tree": "fir",
    "oak": "valley_oak",
    "birch": "silver_birch",
    "apple": "wild_apple",
}

# Stone-Setter Engraving Palette (monochrome carved slate-silver #100c1c .. #b6acd2, zero #000000)
ENG_ABYSS = np.array([16.0, 12.0, 28.0], dtype=np.float32)    # #100c1c chiseled shadow / deep sea
ENG_BASE = (16, 12, 28)       # #100c1c
ENG_SEA0 = np.array([20.0, 16.0, 34.0], dtype=np.float32)     # #141022
ENG_SEA1 = np.array([28.0, 24.0, 46.0], dtype=np.float32)     # #1c182e
ENG_SEA2 = np.array([38.0, 33.0, 60.0], dtype=np.float32)     # #26213c
ENG_SEA = (24, 20, 40)        # #181428
ENG_WAVE = (68, 62, 98)       # #443e62
ENG_LAND0 = np.array([36.0, 32.0, 56.0], dtype=np.float32)    # #242038
ENG_LAND1 = np.array([54.0, 48.0, 80.0], dtype=np.float32)    # #363050
ENG_LAND2 = np.array([78.0, 71.0, 110.0], dtype=np.float32)   # #4e476e
ENG_LAND = (44, 39, 68)       # #2c2744
ENG_MID = (64, 58, 94)        # #403a5e
ENG_HATCH = (106, 98, 142)    # #6a628e
ENG_RIDGE = (146, 138, 182)   # #928ab6
ENG_COAST = (182, 172, 210)   # #b6acd2
ENG_TEXT = (206, 198, 232)    # #cec6e8
ENG_BRIGHT = (218, 212, 238)  # #dad4ee

# PixelText 3x5 canonical glyphs (from src/ui/pixel_text.gd)
PIXEL_FONT_ADVANCE = 4
PIXEL_FONT_HEIGHT = 7
PIXEL_FONT_ACCENTS = {"Ä": "A", "Ö": "O", "Ü": "U"}
PIXEL_FONT_GLYPHS = {
    "A": [".X.", "X.X", "XXX", "X.X", "X.X"],
    "B": ["XX.", "X.X", "XX.", "X.X", "XX."],
    "C": [".XX", "X..", "X..", "X..", ".XX"],
    "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"],
    "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "G": [".XX", "X..", "X.X", "X.X", ".XX"],
    "H": ["X.X", "X.X", "XXX", "X.X", "X.X"],
    "I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
    "J": ["..X", "..X", "..X", "X.X", ".X."],
    "K": ["X.X", "X.X", "XX.", "X.X", "X.X"],
    "L": ["X..", "X..", "X..", "X..", "XXX"],
    "M": ["X.X", "XXX", "XXX", "X.X", "X.X"],
    "N": ["XX.", "X.X", "X.X", "X.X", "X.X"],
    "O": [".X.", "X.X", "X.X", "X.X", ".X."],
    "P": ["XX.", "X.X", "XX.", "X..", "X.."],
    "Q": [".X.", "X.X", "X.X", "XX.", ".XX"],
    "R": ["XX.", "X.X", "XX.", "X.X", "X.X"],
    "S": [".XX", "X..", ".X.", "..X", "XX."],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
    "U": ["X.X", "X.X", "X.X", "X.X", "XXX"],
    "V": ["X.X", "X.X", "X.X", "X.X", ".X."],
    "W": ["X.X", "X.X", "XXX", "XXX", "X.X"],
    "X": ["X.X", "X.X", ".X.", "X.X", "X.X"],
    "Y": ["X.X", "X.X", ".X.", ".X.", ".X."],
    "Z": ["XXX", "..X", ".X.", "X..", "XXX"],
    "0": ["XXX", "X.X", "X.X", "X.X", "XXX"],
    "1": [".X.", "XX.", ".X.", ".X.", "XXX"],
    "2": ["XXX", "..X", "XXX", "X..", "XXX"],
    "3": ["XXX", "..X", "XXX", "..X", "XXX"],
    "4": ["X.X", "X.X", "XXX", "..X", "..X"],
    "5": ["XXX", "X..", "XXX", "..X", "XXX"],
    "6": ["XXX", "X..", "XXX", "X.X", "XXX"],
    "7": ["XXX", "..X", "..X", ".X.", ".X."],
    "8": ["XXX", "X.X", "XXX", "X.X", "XXX"],
    "9": ["XXX", "X.X", "XXX", "..X", "XXX"],
    ".": ["...", "...", "...", "...", ".X."],
    ",": ["...", "...", "...", ".X.", "X.."],
    ":": ["...", ".X.", "...", ".X.", "..."],
    "-": ["...", "...", "XXX", "...", "..."],
    "+": ["...", ".X.", "XXX", ".X.", "..."],
    "/": ["..X", "..X", ".X.", "X..", "X.."],
    ">": ["X..", ".X.", "..X", ".X.", "X.."],
    "%": ["X.X", "..X", ".X.", "X..", "X.X"],
    "!": [".X.", ".X.", ".X.", "...", ".X."],
    "?": ["XX.", "..X", ".X.", "...", ".X."],
    "&": [".X.", "X.X", ".X.", "X.X", ".XX"],
    "@": [".XX", "X.X", "XXX", "X..", ".XX"],
    "_": ["...", "...", "...", "...", "XXX"],
    "*": ["X.X", ".X.", "XXX", ".X.", "X.X"],
    "#": ["X.X", "XXX", "X.X", "XXX", "X.X"],
    "(": [".X.", "X..", "X..", "X..", ".X."],
    ")": [".X.", "..X", "..X", "..X", ".X."],
    "<": ["..X", ".X.", "X..", ".X.", "..X"],
    "=": ["...", "XXX", "...", "XXX", "..."],
    " ": ["...", "...", "...", "...", "..."],
}


# ---------------------------------------------------------------------------
# Godot 4 PRNG (PCG32) & hash() Equivalents
# ---------------------------------------------------------------------------

MASK32 = 0xFFFFFFFF
MASK64 = 0xFFFFFFFFFFFFFFFF
PCG_MULT = 6364136223846793005
PCG_INC = 1442695040888963407


class PCG32:
    """Pure-Python equivalent of Godot 4's RandomNumberGenerator (PCG32)."""

    def __init__(self, seed_val: int = 0) -> None:
        self.state = 0
        self.inc = PCG_INC
        self.seed(seed_val)

    def seed(self, seed_val: int) -> None:
        self.state = 0
        self._step()
        self.state = (self.state + (seed_val & MASK64)) & MASK64
        self._step()

    def _step(self) -> int:
        old = self.state
        self.state = (old * PCG_MULT + self.inc) & MASK64
        xorshifted = (((old >> 18) ^ old) >> 27) & MASK32
        rot = (old >> 59) & 31
        return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32

    def randf(self) -> float:
        return self._step() / 4294967296.0

    def randf_range(self, a: float, b: float) -> float:
        return a + self.randf() * (b - a)

    def randi_range(self, lo: int, hi: int) -> int:
        if lo >= hi:
            return lo
        span = hi - lo + 1
        threshold = (-span) & MASK32
        threshold %= span
        while True:
            r = self._step()
            if r >= threshold:
                return lo + (r % span)


def _rotl32(x: int, r: int) -> int:
    return ((x << r) | (x >> (32 - r))) & MASK32


def _murmur3_one_32(p_in: int, p_seed: int) -> int:
    k = (p_in & MASK32)
    k = (k * 0xCC9E2D51) & MASK32
    k = _rotl32(k, 15)
    k = (k * 0x1B873593) & MASK32
    h = p_seed ^ k
    h = _rotl32(h, 13)
    h = (h * 5 + 0xE6546B64) & MASK32
    return h


def _fmix32(h: int) -> int:
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & MASK32
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & MASK32
    h ^= h >> 16
    return h


def _hash_one_uint64(x: int) -> int:
    v = x & MASK64
    v = ((~v) + (v << 18)) & MASK64
    v = v ^ (v >> 31)
    v = (v * 21) & MASK64
    v = v ^ (v >> 11)
    v = (v + (v << 6)) & MASK64
    v = v ^ (v >> 22)
    return v & MASK32


def _godot_string_hash(s: str) -> int:
    h = 5381
    for ch in s:
        h = (((h << 5) + h) + ord(ch)) & MASK32
    return h


def godot_hash_array(items: list[Any]) -> int:
    """Godot 4 Variant::recursive_hash approximation for Array[int|str]."""
    VARIANT_ARRAY = 28
    VARIANT_INT = 2
    VARIANT_STRING = 4
    h = _murmur3_one_32(VARIANT_ARRAY, 0x7F07C65)
    for item in items:
        if isinstance(item, str):
            eh = _murmur3_one_32(_godot_string_hash(item), VARIANT_STRING)
        else:
            eh = _murmur3_one_32(_hash_one_uint64(int(item)), VARIANT_INT)
        h = _murmur3_one_32(_fmix32(eh), h)
    return _fmix32(h)


# ---------------------------------------------------------------------------
# Vectorized Math & Geometry Helpers
# ---------------------------------------------------------------------------

def hex_to_rgb(h: str) -> tuple[int, int, int]:
    s = h.strip().lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def clampf(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def lerpf(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smoothstep_scalar(a: float, b: float, x: float) -> float:
    if abs(b - a) < 1e-8:
        return 1.0 if x >= b else 0.0
    t = clampf((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smoothstep_np(a: float | np.ndarray, b: float | np.ndarray, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / np.maximum(b - a, 1e-8), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _vnoise2d(x: np.ndarray, y: np.ndarray, seed: int) -> np.ndarray:
    """Fast vectorized 2D smooth value noise in [0, 1] using uint32 arithmetic."""
    xi = np.floor(x).astype(np.int32)
    yi = np.floor(y).astype(np.int32)
    xf = (x - xi).astype(np.float32)
    yf = (y - yi).astype(np.float32)
    u = xf * xf * (3.0 - 2.0 * xf)
    v = yf * yf * (3.0 - 2.0 * yf)

    x0 = xi.astype(np.uint32)
    y0 = yi.astype(np.uint32)
    x1 = x0 + np.uint32(1)
    y1 = y0 + np.uint32(1)
    c1 = np.uint32(374761393)
    c2 = np.uint32(668265263)
    c4 = np.uint32(1274126177)
    s_term = np.uint32((1442695041 * (seed & 0xFFFFFFFF)) & 0xFFFFFFFF)

    with np.errstate(over="ignore"):
        hx0 = x0 * c1 + s_term
        hx1 = x1 * c1 + s_term
        hy0 = y0 * c2
        hy1 = y1 * c2

    def h2(hx: np.ndarray, hy: np.ndarray) -> np.ndarray:
        with np.errstate(over="ignore"):
            n = hx + hy
            n = (n ^ (n >> np.uint32(13))) * c4
            n = n ^ (n >> np.uint32(16))
        return (n & np.uint32(0xFFFF)).astype(np.float32) * (1.0 / 65535.0)

    n00 = h2(hx0, hy0)
    n10 = h2(hx1, hy0)
    n01 = h2(hx0, hy1)
    n11 = h2(hx1, hy1)
    nx0 = n00 + (n10 - n00) * u
    nx1 = n01 + (n11 - n01) * u
    return nx0 + (nx1 - nx0) * v


def fbm2d(x: np.ndarray, y: np.ndarray, seed: int, freq: float = 0.05, octaves: int = 2) -> np.ndarray:
    acc = np.zeros(np.broadcast_shapes(x.shape, y.shape), dtype=np.float32)
    amp = 0.5
    norm = 0.0
    f = freq
    for i in range(octaves):
        acc += amp * _vnoise2d(x * f, y * f, seed + i * 1013)
        norm += amp
        amp *= 0.5
        f *= 2.0
    return acc / max(norm, 1e-6)


def fbm2d_grid(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    seed: int,
    freq: float = 0.05,
    octaves: int = 2,
    sub: int = 1,
) -> np.ndarray:
    """Evaluates fbm2d on a downsampled sub-grid with 1D axis broadcasting and bilinearly upsamples."""
    if sub <= 1 or W < 16 or H < 16:
        cx = ox + (np.arange(W, dtype=np.float32)[None, :] + 0.5) / scale
        cy = oy + (np.arange(H, dtype=np.float32)[:, None] + 0.5) / scale
        return fbm2d(cx, cy, seed, freq, octaves)
    cW = max(4, (W + sub - 1) // sub)
    cH = max(4, (H + sub - 1) // sub)
    cx = ox + ((np.arange(cW, dtype=np.float32)[None, :] + 0.5) * (W / float(cW))) / scale
    cy = oy + ((np.arange(cH, dtype=np.float32)[:, None] + 0.5) * (H / float(cH))) / scale
    coarse = fbm2d(cx, cy, seed, freq, octaves)
    return _upsample_f32(coarse, W, H)


def _upsample_f32(arr: np.ndarray, W: int, H: int) -> np.ndarray:
    """Lossless float32 bilinear upsampling via PIL mode='F'."""
    if arr.shape == (H, W):
        return arr.astype(np.float32, copy=False)
    im = Image.fromarray(arr.astype(np.float32, copy=False), mode="F")
    return np.asarray(im.resize((W, H), Image.Resampling.BILINEAR), dtype=np.float32)


def bayer_grid(H: int, W: int, cell: int = 1, ox: int = 0, oy: int = 0) -> np.ndarray:
    """Returns an HxW float32 4x4 ordered Bayer threshold grid in [0, 15/16]."""
    c = max(1, int(cell))
    ys = ((np.arange(H, dtype=np.int32) + oy) // c) & 3
    xs = ((np.arange(W, dtype=np.int32) + ox) // c) & 3
    return BAYER_4X4[ys[:, None], xs[None, :]]


def bayer_quantize_ramp(
    ramp: np.ndarray,
    val: np.ndarray,
    bayer: np.ndarray,
    spread: float = 0.88,
) -> np.ndarray:
    """Quantizes a scalar field val in [0, 1] into discrete palette tones using 4x4 Bayer dithering."""
    n = len(ramp)
    idx = np.clip(np.floor(val * float(n) + (bayer - 0.5) * spread), 0, n - 1).astype(np.int32)
    return ramp[idx]


def box_blur_3x3(arr: np.ndarray, passes: int = 2) -> np.ndarray:
    out = arr.astype(np.float32, copy=True)
    for _ in range(passes):
        p = np.pad(out, 1, mode="edge")
        out = (p[1:-1, :-2] + p[1:-1, 1:-1] + p[1:-1, 2:]) / 3.0
        p = np.pad(out, 1, mode="edge")
        out = (p[:-2, 1:-1] + p[1:-1, 1:-1] + p[2:, 1:-1]) / 3.0
    return out


def box_blur_sep(arr: np.ndarray, r: int, passes: int = 3) -> np.ndarray:
    """Separable O(N) box blur matching bake_relief.py export_smooth."""
    out = arr.astype(np.float32, copy=True)
    if r <= 0:
        return out
    d = float(2 * r + 1)
    for _ in range(passes):
        p = np.pad(out, ((0, 0), (r, r)), mode="edge")
        cs = np.cumsum(p, axis=1, dtype=np.float64)
        cs = np.concatenate([np.zeros((out.shape[0], 1), dtype=np.float64), cs], axis=1)
        out = ((cs[:, 2 * r + 1:] - cs[:, :-2 * r - 1]) / d).astype(np.float32)
        p = np.pad(out, ((r, r), (0, 0)), mode="edge")
        cs = np.cumsum(p, axis=0, dtype=np.float64)
        cs = np.concatenate([np.zeros((1, out.shape[1]), dtype=np.float64), cs], axis=0)
        out = ((cs[2 * r + 1:, :] - cs[:-2 * r - 1, :]) / d).astype(np.float32)
    return out


def _morph_erode(m: np.ndarray, n: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        r = out.copy()
        r[1:] &= out[:-1]; r[0] = False
        r[:-1] &= out[1:]; r[-1] = False
        r[:, 1:] &= out[:, :-1]; r[:, 0] = False
        r[:, :-1] &= out[:, 1:]; r[:, -1] = False
        out = r
    return out


def _morph_dilate(m: np.ndarray, n: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        r = out.copy()
        r[1:] |= out[:-1]
        r[:-1] |= out[1:]
        r[:, 1:] |= out[:, :-1]
        r[:, :-1] |= out[:, 1:]
        out = r
    return out


def _fast_mask_boundary_distance(mask: np.ndarray, factor: int = 4) -> np.ndarray:
    """Fast Euclidean distance (in pixels) from pixels where `mask` is True to the nearest ~mask edge (or vice versa)."""
    H, W = mask.shape
    pad = np.pad(mask, 1, mode="edge")
    edge = mask & ((~pad[:-2, 1:-1]) | (~pad[2:, 1:-1]) | (~pad[1:-1, :-2]) | (~pad[1:-1, 2:]))
    if not np.any(edge):
        return np.full((H, W), 1e4, dtype=np.float32)
    f = max(1, int(factor))
    cH = max(4, (H + f - 1) // f)
    cW = max(4, (W + f - 1) // f)
    cgy, cgx = np.mgrid[0:cH, 0:cW].astype(np.float32)
    cgx = (cgx + 0.5) * (W / float(cW))
    cgy = (cgy + 0.5) * (H / float(cH))
    csx = np.full((cH, cW), 1e9, dtype=np.float32)
    csy = np.full((cH, cW), 1e9, dtype=np.float32)
    cd2 = np.full((cH, cW), 1e12, dtype=np.float32)

    ey, ex = np.nonzero(edge)
    ex_f = ex.astype(np.float32) + 0.5
    ey_f = ey.astype(np.float32) + 0.5
    cix = np.clip((ex * cW) // W, 0, cW - 1)
    ciy = np.clip((ey * cH) // H, 0, cH - 1)
    d2 = (cgx[ciy, cix] - ex_f) ** 2 + (cgy[ciy, cix] - ey_f) ** 2
    order = np.argsort(d2)[::-1]
    cix_o, ciy_o = cix[order], ciy[order]
    cd2[ciy_o, cix_o] = d2[order]
    csx[ciy_o, cix_o] = ex_f[order]
    csy[ciy_o, cix_o] = ey_f[order]

    max_dim = max(cW, cH)
    steps: list[int] = []
    s = 1
    while s < max_dim:
        steps.append(s)
        s *= 2
    steps = list(reversed(steps)) + [1]
    _jfa_pass(cgx, cgy, csx, csy, None, cd2, steps)
    return _upsample_f32(np.sqrt(cd2), W, H)


def as_vec2(raw: Any, default: tuple[float, float] | None = None) -> tuple[float, float] | None:
    if isinstance(raw, (list, tuple)) and len(raw) >= 2:
        try:
            return (float(raw[0]), float(raw[1]))
        except (TypeError, ValueError):
            return default
    if isinstance(raw, dict) and "x" in raw and "y" in raw:
        try:
            return (float(raw["x"]), float(raw["y"]))
        except (TypeError, ValueError):
            return default
    return default


def as_poly(raw: Any, shift: tuple[float, float] = (0.0, 0.0)) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    if not isinstance(raw, list):
        return out
    sx, sy = shift
    for item in raw:
        v = as_vec2(item)
        if v is not None:
            out.append((v[0] + sx, v[1] + sy))
    return out


def dist_pts(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def polyline_length(line: list[tuple[float, float]]) -> float:
    total = 0.0
    for i in range(len(line) - 1):
        total += dist_pts(line[i], line[i + 1])
    return total


def point_along(line: list[tuple[float, float]], share: float) -> tuple[float, float]:
    if not line:
        return (0.0, 0.0)
    if len(line) == 1:
        return line[0]
    want = clampf(share, 0.0, 1.0) * polyline_length(line)
    for i in range(len(line) - 1):
        part = dist_pts(line[i], line[i + 1])
        if want <= part or i == len(line) - 2:
            t = clampf(want / max(part, 1e-4), 0.0, 1.0)
            return (lerpf(line[i][0], line[i + 1][0], t), lerpf(line[i][1], line[i + 1][1], t))
        want -= part
    return line[-1]


def sub_polyline(line: list[tuple[float, float]], fr: float, to: float) -> list[tuple[float, float]]:
    if len(line) < 2:
        return []
    total = max(polyline_length(line), 1e-4)
    lo = clampf(min(fr, to), 0.0, 1.0) * total
    hi = clampf(max(fr, to), 0.0, 1.0) * total
    out = [point_along(line, lo / total)]
    walked = 0.0
    for i in range(len(line) - 1):
        walked += dist_pts(line[i], line[i + 1])
        if lo < walked < hi:
            out.append(line[i + 1])
    out.append(point_along(line, hi / total))
    return out


def _curve_piece(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    step: float,
    out: list[tuple[float, float]],
) -> None:
    d = dist_pts(p1, p2)
    count = max(1, math.ceil(d / max(step, 0.1)))
    for k in range(count):
        t = k / float(count)
        t2 = t * t
        t3 = t2 * t
        x = 0.5 * (
            2.0 * p1[0]
            + (p2[0] - p0[0]) * t
            + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2
            + (3.0 * p1[0] - p0[0] - 3.0 * p2[0] + p3[0]) * t3
        )
        y = 0.5 * (
            2.0 * p1[1]
            + (p2[1] - p0[1]) * t
            + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2
            + (3.0 * p1[1] - p0[1] - 3.0 * p2[1] + p3[1]) * t3
        )
        out.append((x, y))


def smooth_closed(points: list[tuple[float, float]], step: float = CURVE_STEP) -> list[tuple[float, float]]:
    n = len(points)
    if n < 3:
        return list(points)
    out: list[tuple[float, float]] = []
    for i in range(n):
        _curve_piece(points[(i - 1 + n) % n], points[i], points[(i + 1) % n], points[(i + 2) % n], step, out)
    return out


def smooth_open(points: list[tuple[float, float]], step: float = CURVE_STEP) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for i in range(1, len(points) - 2):
        _curve_piece(points[i - 1], points[i], points[i + 1], points[i + 2], step, out)
    return out


def subdivide_catmull(pts: list[tuple[float, float]], subdiv: int = 5) -> list[tuple[float, float]]:
    """GroundSurfaces._subdivide_catmull equivalent (clamped endpoints)."""
    n = len(pts)
    if n < 2:
        return list(pts)
    out: list[tuple[float, float]] = []
    for i in range(n - 1):
        p0 = pts[max(0, i - 1)]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[min(n - 1, i + 2)]
        steps = subdiv + (1 if i == n - 2 else 0)
        for k in range(steps):
            t = k / float(subdiv)
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * (
                2.0 * p1[0]
                + (p2[0] - p0[0]) * t
                + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3.0 * p1[0] - 3.0 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                2.0 * p1[1]
                + (p2[1] - p0[1]) * t
                + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * t3
            )
            out.append((x, y))
    return out


def point_in_polygon(pt: tuple[float, float], poly: list[tuple[float, float]]) -> bool:
    n = len(poly)
    if n < 3:
        return False
    x, y = pt
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) if abs(yj - yi) > 1e-12 else 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def points_in_polygon_grid(gx: np.ndarray, gy: np.ndarray, poly: list[tuple[float, float]]) -> np.ndarray:
    """Vectorized ray-casting point-in-polygon over arbitrary coordinate arrays (float64 exact)."""
    n = len(poly)
    if n < 3:
        return np.zeros(gx.shape, dtype=bool)
    inside = np.zeros(gx.shape, dtype=bool)
    px = np.array([p[0] for p in poly], dtype=np.float64)
    py = np.array([p[1] for p in poly], dtype=np.float64)
    j = n - 1
    for i in range(n):
        yi = float(py[i])
        yj = float(py[j])
        xi = float(px[i])
        xj = float(px[j])
        cond = (yi > gy) != (yj > gy)
        if np.any(cond):
            denom = (yj - yi) if abs(yj - yi) > 1e-12 else 1e-12
            x_int = (xj - xi) * (gy - yi) / denom + xi
            inside ^= cond & (gx < x_int)
        j = i
    return inside


def dist_point_to_seg(pt: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    vx, vy = b[0] - a[0], b[1] - a[1]
    l2 = vx * vx + vy * vy
    if l2 <= 1e-12:
        return dist_pts(pt, a)
    t = clampf(((pt[0] - a[0]) * vx + (pt[1] - a[1]) * vy) / l2, 0.0, 1.0)
    return math.hypot(pt[0] - (a[0] + t * vx), pt[1] - (a[1] + t * vy))


def rim_distance(pt: tuple[float, float], poly: list[tuple[float, float]]) -> float:
    n = len(poly)
    if n == 0:
        return 1e9
    if n == 1:
        return dist_pts(pt, poly[0])
    best = 1e9
    for i in range(n):
        d = dist_point_to_seg(pt, poly[i], poly[(i + 1) % n])
        if d < best:
            best = d
    return best


def edge_distance(pt: tuple[float, float], poly: list[tuple[float, float]]) -> float:
    if point_in_polygon(pt, poly):
        return 0.0
    return rim_distance(pt, poly)


def polyline_distance(pt: tuple[float, float], line: list[tuple[float, float]]) -> float:
    n = len(line)
    if n == 0:
        return 1e9
    if n == 1:
        return dist_pts(pt, line[0])
    best = 1e9
    for i in range(n - 1):
        d = dist_point_to_seg(pt, line[i], line[i + 1])
        if d < best:
            best = d
    return best


def min_dist_to_segments_grid(
    gx: np.ndarray,
    gy: np.ndarray,
    segs_a: np.ndarray,
    segs_b: np.ndarray,
    seg_shares: np.ndarray | None = None,
    chunk: int = 32,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Vectorized squared-distance -> Euclidean min distance to line segments + optional share."""
    best_d2 = np.full(gx.shape, 1e12, dtype=np.float32)
    best_share = np.zeros(gx.shape, dtype=np.float32) if seg_shares is not None else None
    n = len(segs_a)
    if n == 0:
        return np.sqrt(best_d2), best_share
    for s in range(0, n, chunk):
        e = min(n, s + chunk)
        ax = segs_a[s:e, 0][:, None, None]
        ay = segs_a[s:e, 1][:, None, None]
        bx = segs_b[s:e, 0][:, None, None]
        by = segs_b[s:e, 1][:, None, None]
        vx = bx - ax
        vy = by - ay
        l2 = np.maximum(vx * vx + vy * vy, 1e-12)
        t = np.clip(((gx[None, :, :] - ax) * vx + (gy[None, :, :] - ay) * vy) / l2, 0.0, 1.0)
        dx = gx[None, :, :] - (ax + t * vx)
        dy = gy[None, :, :] - (ay + t * vy)
        d2 = dx * dx + dy * dy
        idx = np.argmin(d2, axis=0)
        local_min = np.take_along_axis(d2, idx[None, :, :], axis=0)[0]
        better = local_min < best_d2
        best_d2 = np.where(better, local_min, best_d2)
        if best_share is not None and seg_shares is not None:
            t_pick = np.take_along_axis(t, idx[None, :, :], axis=0)[0]
            s0 = seg_shares[s:e, 0][idx]
            s1 = seg_shares[s:e, 1][idx]
            sh = s0 + (s1 - s0) * t_pick
            best_share = np.where(better, sh, best_share)
    return np.sqrt(best_d2), best_share


def rasterize_polygon_mask(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    poly: list[tuple[float, float]],
) -> np.ndarray:
    """Exact, ultra-fast vectorized scanline ray-casting rasterizer (0-mismatch with point_in_polygon)."""
    if len(poly) < 3 or W <= 0 or H <= 0:
        return np.zeros((max(0, H), max(0, W)), dtype=bool)
    diff = np.zeros((H, W + 1), dtype=np.uint8)
    gy = oy + (np.arange(H, dtype=np.float64) + 0.5) / scale
    n = len(poly)
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[i - 1]
        if yi == yj:
            continue
        ylo, yhi = (yi, yj) if yi < yj else (yj, yi)
        r0 = max(0, int(math.floor((ylo - oy) * scale - 0.5)))
        r1 = min(H, int(math.ceil((yhi - oy) * scale - 0.5)) + 1)
        if r1 <= r0:
            continue
        gy_s = gy[r0:r1]
        mask = (yi > gy_s) != (yj > gy_s)
        if not np.any(mask):
            continue
        rs = np.arange(r0, r1)[mask]
        xint = (xj - xi) * (gy[rs] - yi) / (yj - yi) + xi
        cx = np.clip(np.ceil((xint - ox) * scale - 0.5).astype(np.int32), 0, W)
        np.bitwise_xor.at(diff, (rs, 0), 1)
        m_c = cx < W
        if np.any(m_c):
            np.bitwise_xor.at(diff, (rs[m_c], cx[m_c]), 1)
    return np.bitwise_xor.accumulate(diff[:, :W], axis=1).astype(bool)


def _jfa_pass(
    gx: np.ndarray,
    gy: np.ndarray,
    sx: np.ndarray,
    sy: np.ndarray,
    sh: np.ndarray | None,
    best_d2: np.ndarray,
    steps: list[int],
) -> None:
    """In-place Jump Flooding step over 8 neighbors using slice views (no wraparound)."""
    H, W = gx.shape
    for step in steps:
        for dy in (-step, 0, step):
            if dy >= H or dy <= -H:
                continue
            y0_dst = max(0, dy)
            y1_dst = min(H, H + dy)
            y0_src = y0_dst - dy
            y1_src = y1_dst - dy
            for dx in (-step, 0, step):
                if dx == 0 and dy == 0:
                    continue
                if dx >= W or dx <= -W:
                    continue
                x0_dst = max(0, dx)
                x1_dst = min(W, W + dx)
                x0_src = x0_dst - dx
                x1_src = x1_dst - dx

                nsx = sx[y0_src:y1_src, x0_src:x1_src]
                nsy = sy[y0_src:y1_src, x0_src:x1_src]
                ddx = gx[y0_dst:y1_dst, x0_dst:x1_dst] - nsx
                ddy = gy[y0_dst:y1_dst, x0_dst:x1_dst] - nsy
                nd2 = ddx * ddx + ddy * ddy
                cur_d2 = best_d2[y0_dst:y1_dst, x0_dst:x1_dst]
                better = nd2 < cur_d2
                if np.any(better):
                    cur_d2[better] = nd2[better]
                    sx[y0_dst:y1_dst, x0_dst:x1_dst][better] = nsx[better]
                    sy[y0_dst:y1_dst, x0_dst:x1_dst][better] = nsy[better]
                    if sh is not None:
                        sh[y0_dst:y1_dst, x0_dst:x1_dst][better] = sh[y0_src:y1_src, x0_src:x1_src][better]


def _stamp_segments_seeds(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    segs_a: np.ndarray,
    segs_b: np.ndarray,
    seg_shares: np.ndarray | None,
    sx: np.ndarray,
    sy: np.ndarray,
    sh: np.ndarray | None,
    best_d2: np.ndarray,
) -> None:
    """Vectorized dense sampling of segment endpoints onto JFA seed grids."""
    if len(segs_a) == 0:
        return
    dx = segs_b[:, 0] - segs_a[:, 0]
    dy = segs_b[:, 1] - segs_a[:, 1]
    lens = np.hypot(dx, dy)
    # Sample at <= 0.35 / scale tile spacing
    n_samples_per_seg = np.maximum(2, np.ceil(lens * scale * 2.8).astype(np.int32))
    max_k = int(np.max(n_samples_per_seg))
    # Build sample arrays in a single vectorized pass
    pt_xs: list[np.ndarray] = []
    pt_ys: list[np.ndarray] = []
    pt_sh: list[np.ndarray] = []
    for k in range(max_k):
        mask = k < n_samples_per_seg
        if not np.any(mask):
            break
        denom = np.maximum(1, n_samples_per_seg[mask] - 1).astype(np.float32)
        t = (k / denom).astype(np.float32)
        pt_xs.append(segs_a[mask, 0] + dx[mask] * t)
        pt_ys.append(segs_a[mask, 1] + dy[mask] * t)
        if seg_shares is not None:
            s0 = seg_shares[mask, 0]
            s1 = seg_shares[mask, 1]
            pt_sh.append(s0 + (s1 - s0) * t)

    all_x = np.concatenate(pt_xs)
    all_y = np.concatenate(pt_ys)
    all_s = np.concatenate(pt_sh) if seg_shares is not None else None

    ix = np.floor((all_x - ox) * scale).astype(np.int32)
    iy = np.floor((all_y - oy) * scale).astype(np.int32)
    inb = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    if not np.any(inb):
        # Clamp closest edge samples if polygon lies partially outside grid
        ix = np.clip(ix, 0, W - 1)
        iy = np.clip(iy, 0, H - 1)
    else:
        ix = ix[inb]
        iy = iy[inb]
        all_x = all_x[inb]
        all_y = all_y[inb]
        if all_s is not None:
            all_s = all_s[inb]

    cx = ox + (ix.astype(np.float32) + 0.5) / scale
    cy = oy + (iy.astype(np.float32) + 0.5) / scale
    d2 = (cx - all_x) ** 2 + (cy - all_y) ** 2
    order = np.argsort(d2)[::-1]  # smallest d2 wins last write
    ix_o = ix[order]
    iy_o = iy[order]
    cur = best_d2[iy_o, ix_o]
    better = d2[order] < cur
    # Direct write in descending order ensures minimum d2 stays
    best_d2[iy_o, ix_o] = np.minimum(cur, d2[order])
    sx[iy_o, ix_o] = np.where(better, all_x[order], sx[iy_o, ix_o])
    sy[iy_o, ix_o] = np.where(better, all_y[order], sy[iy_o, ix_o])
    if sh is not None and all_s is not None:
        sh[iy_o, ix_o] = np.where(better, all_s[order], sh[iy_o, ix_o])


def fast_segments_distance_grid(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    segs_a: np.ndarray,
    segs_b: np.ndarray,
    seg_shares: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Coarse-to-fine Jump Flooding Euclidean distance & share field over a uniform grid."""
    if len(segs_a) == 0:
        sh_empty = np.zeros((H, W), dtype=np.float32) if seg_shares is not None else None
        return np.full((H, W), 1e6, dtype=np.float32), sh_empty

    # Run JFA at <= 1 px/tile (or <= 0.25 px/tile for huge continent grids) and upsample smoothly
    if scale > 1.5 and W >= 32 and H >= 32:
        factor = int(round(scale))
        cW = max(1, (W + factor - 1) // factor)
        cH = max(1, (H + factor - 1) // factor)
        c_scale = scale / float(factor)
        cgy, cgx = np.mgrid[0:cH, 0:cW].astype(np.float32)
        cgx = ox + (cgx + 0.5) / c_scale
        cgy = oy + (cgy + 0.5) / c_scale
        csx = np.full((cH, cW), 1e9, dtype=np.float32)
        csy = np.full((cH, cW), 1e9, dtype=np.float32)
        csh = np.zeros((cH, cW), dtype=np.float32) if seg_shares is not None else None
        cd2 = np.full((cH, cW), 1e12, dtype=np.float32)
        _stamp_segments_seeds(cW, cH, ox, oy, c_scale, segs_a, segs_b, seg_shares, csx, csy, csh, cd2)
        if np.all(cd2 >= 1e11):
            gy, gx = np.mgrid[0:H, 0:W].astype(np.float32)
            return min_dist_to_segments_grid(ox + (gx + 0.5) / scale, oy + (gy + 0.5) / scale, segs_a, segs_b, seg_shares)
        max_dim = max(cW, cH)
        steps: list[int] = []
        s = 1
        while s < max_dim:
            steps.append(s)
            s *= 2
        steps = list(reversed(steps)) + [1]
        _jfa_pass(cgx, cgy, csx, csy, csh, cd2, steps)

        cd_dist = np.sqrt(cd2)
        dist_up = np.asarray(
            Image.fromarray(cd_dist.astype(np.float32), mode="F").resize((W, H), Image.Resampling.BILINEAR),
            dtype=np.float32,
        )
        if csh is not None:
            ang = csh * (2.0 * math.pi)
            cos_up = np.asarray(
                Image.fromarray(np.cos(ang).astype(np.float32), mode="F").resize((W, H), Image.Resampling.BILINEAR),
                dtype=np.float32,
            )
            sin_up = np.asarray(
                Image.fromarray(np.sin(ang).astype(np.float32), mode="F").resize((W, H), Image.Resampling.BILINEAR),
                dtype=np.float32,
            )
            sh_up = (np.arctan2(sin_up, cos_up) * (1.0 / (2.0 * math.pi))) % 1.0
        else:
            sh_up = None
        return dist_up, sh_up

    if W * H >= 1_500_000 and seg_shares is None:
        factor = 4
        cW = max(4, (W + factor - 1) // factor)
        cH = max(4, (H + factor - 1) // factor)
        c_scale = scale / float(factor)
        cgy, cgx = np.mgrid[0:cH, 0:cW].astype(np.float32)
        cgx = ox + (cgx + 0.5) / c_scale
        cgy = oy + (cgy + 0.5) / c_scale
        csx = np.full((cH, cW), 1e9, dtype=np.float32)
        csy = np.full((cH, cW), 1e9, dtype=np.float32)
        cd2 = np.full((cH, cW), 1e12, dtype=np.float32)
        _stamp_segments_seeds(cW, cH, ox, oy, c_scale, segs_a, segs_b, None, csx, csy, None, cd2)
        max_dim = max(cW, cH)
        steps = []
        s = 1
        while s < max_dim:
            steps.append(s)
            s *= 2
        steps = list(reversed(steps)) + [1]
        _jfa_pass(cgx, cgy, csx, csy, None, cd2, steps)
        cd_dist = np.sqrt(cd2)
        dist_up = np.asarray(
            Image.fromarray(cd_dist.astype(np.float32), mode="F").resize((W, H), Image.Resampling.BILINEAR),
            dtype=np.float32,
        )
        return dist_up, None

    gy, gx = np.mgrid[0:H, 0:W].astype(np.float32)
    gx = ox + (gx + 0.5) / scale
    gy = oy + (gy + 0.5) / scale
    sx = np.full((H, W), 1e9, dtype=np.float32)
    sy = np.full((H, W), 1e9, dtype=np.float32)
    sh = np.zeros((H, W), dtype=np.float32) if seg_shares is not None else None
    best_d2 = np.full((H, W), 1e12, dtype=np.float32)
    _stamp_segments_seeds(W, H, ox, oy, scale, segs_a, segs_b, seg_shares, sx, sy, sh, best_d2)
    if np.all(best_d2 >= 1e11):
        return min_dist_to_segments_grid(gx, gy, segs_a, segs_b, seg_shares)
    max_dim = max(W, H)
    steps = []
    s = 1
    while s < max_dim:
        steps.append(s)
        s *= 2
    steps = list(reversed(steps)) + [1]
    _jfa_pass(gx, gy, sx, sy, sh, best_d2, steps)
    return np.sqrt(best_d2), sh


def fast_narrowband_segments_distance(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    segs_a: np.ndarray,
    segs_b: np.ndarray,
    max_dist_tiles: float,
    seg_radii: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Exact segment distance within tight per-segment bounding boxes (for ways, seams, brooks)."""
    best_d2 = np.full((H, W), (max_dist_tiles + 1.0) ** 2, dtype=np.float32)
    best_r = np.ones((H, W), dtype=np.float32) if seg_radii is not None else None
    best_sdf = np.full((H, W), max_dist_tiles + 1.0, dtype=np.float32) if seg_radii is not None else None
    pad_px = int(math.ceil(max_dist_tiles * scale)) + 2
    for i in range(len(segs_a)):
        ax, ay = float(segs_a[i, 0]), float(segs_a[i, 1])
        bx, by = float(segs_b[i, 0]), float(segs_b[i, 1])
        x0 = max(0, int(math.floor((min(ax, bx) - ox) * scale)) - pad_px)
        x1 = min(W, int(math.ceil((max(ax, bx) - ox) * scale)) + pad_px + 1)
        y0 = max(0, int(math.floor((min(ay, by) - oy) * scale)) + (-pad_px))
        y1 = min(H, int(math.ceil((max(ay, by) - oy) * scale)) + pad_px + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        cx = ox + (np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5) / scale
        cy = oy + (np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5) / scale
        vx, vy = bx - ax, by - ay
        l2 = max(vx * vx + vy * vy, 1e-12)
        t = np.clip(((cx - ax) * vx + (cy - ay) * vy) / l2, 0.0, 1.0)
        d2 = (cx - (ax + t * vx)) ** 2 + (cy - (ay + t * vy)) ** 2
        if seg_radii is not None and best_sdf is not None and best_r is not None:
            r0, r1 = float(seg_radii[i, 0]), float(seg_radii[i, 1])
            rr = r0 + (r1 - r0) * t
            sdf = np.sqrt(d2) - rr
            sub_s = best_sdf[y0:y1, x0:x1]
            m = sdf < sub_s
            if np.any(m):
                sub_s[m] = sdf[m]
                best_r[y0:y1, x0:x1][m] = rr[m]
                best_d2[y0:y1, x0:x1][m] = d2[m]
        else:
            sub = best_d2[y0:y1, x0:x1]
            m = d2 < sub
            if np.any(m):
                sub[m] = d2[m]
    if seg_radii is not None:
        return best_sdf, best_r  # type: ignore[return-value]
    return np.sqrt(best_d2), None


def bbox_of(pts: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    if not pts:
        return (0.0, 0.0, 0.0, 0.0)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


# ---------------------------------------------------------------------------
# Atlas & Landscape Data Model
# ---------------------------------------------------------------------------

class ZoneData:
    def __init__(self, raw: dict[str, Any], continent_data: ContinentData) -> None:
        self.raw = raw
        self.id = str(raw.get("id", ""))
        self.name = str(raw.get("name", self.id.upper()))
        self.old_name = str(raw.get("old_name", self.name))
        self.subtitle = str(raw.get("subtitle", ""))
        self.continent_id = str(raw.get("continent", continent_data.id))
        self.region_id = str(raw.get("region", ""))
        self.kind = str(raw.get("kind", "field"))
        self.danger = str(raw.get("danger", "ruhig"))
        org = as_vec2(raw.get("origin"), (0.0, 0.0)) or (0.0, 0.0)
        sz = as_vec2(raw.get("size"), (128.0, 128.0)) or (128.0, 128.0)
        self.origin = (int(round(org[0])), int(round(org[1])))
        self.size = (max(1, int(round(sz[0]))), max(1, int(round(sz[1]))))
        self.biomes = [str(b) for b in (raw.get("biomes") or [])]
        self.mood = str(raw.get("mood", ""))
        self.borders = [b for b in (raw.get("borders") or []) if isinstance(b, dict)]
        self.curve = bool(raw.get("curve", False))
        shift = (float(self.origin[0]), float(self.origin[1]))
        self.seams_used: list[str] = []
        self.footprint, self.seam_segments = self._build_outline(
            raw.get("footprint", []), shift, self.curve, continent_data
        )
        if len(self.footprint) < 3:
            ox, oy = shift
            w, h = float(self.size[0]), float(self.size[1])
            self.footprint = [(ox, oy), (ox + w, oy), (ox + w, oy + h), (ox, oy + h)]
        self.bbox = bbox_of(self.footprint)
        self.places = raw.get("places") or []
        self.landmarks = raw.get("landmarks") or []
        self.nature = raw.get("nature") if isinstance(raw.get("nature"), dict) else {}

    def _build_outline(
        self,
        raw: Any,
        shift: tuple[float, float],
        curve: bool,
        continent_data: ContinentData,
    ) -> tuple[list[tuple[float, float]], list[tuple[list[tuple[float, float]], str]]]:
        runs: list[dict[str, Any]] = []
        if isinstance(raw, list):
            for entry in raw:
                if isinstance(entry, dict) and "seam" in entry:
                    sid = str(entry.get("seam", ""))
                    cut = continent_data.seams.get(sid)
                    if cut is None:
                        continue
                    self.seams_used.append(sid)
                    runs.append({"seam": True, "id": sid, "kind": cut["kind"], "pts": list(cut["pts"])})
                else:
                    v = as_vec2(entry)
                    if v is None:
                        continue
                    if not runs or runs[-1]["seam"]:
                        runs.append({"seam": False, "id": "", "kind": "", "pts": []})
                    runs[-1]["pts"].append((v[0] + shift[0], v[1] + shift[1]))

        # Flip seam runs to match preceding endpoint (exact Atlas._outline parity)
        for i, run in enumerate(runs):
            if not run["seam"] or not run["pts"]:
                continue
            pts = run["pts"]
            before: tuple[float, float] | None = None
            if i > 0 and runs[i - 1]["pts"]:
                before = runs[i - 1]["pts"][-1]
            elif len(runs) > 1 and runs[-1]["pts"]:
                before = runs[-1]["pts"][-1]
            if before is not None and dist_pts(before, pts[-1]) < dist_pts(before, pts[0]):
                run["pts"] = list(reversed(pts))

        plan: list[tuple[float, float]] = []
        for run in runs:
            plan.extend(run["pts"])

        seam_segs: list[tuple[list[tuple[float, float]], str]] = []
        for run in runs:
            if run["seam"] and len(run["pts"]) >= 2:
                seam_segs.append((run["pts"], str(run.get("kind", "forest_sea"))))

        if not curve:
            return plan, seam_segs
        has_seam = any(r["seam"] for r in runs)
        if not has_seam:
            return smooth_closed(plan, CURVE_STEP), seam_segs

        out: list[tuple[float, float]] = []
        count = len(runs)
        for i, run in enumerate(runs):
            pts = run["pts"]
            if not pts:
                continue
            if run["seam"]:
                out.extend(pts)
                continue
            prev_pts = runs[(i - 1 + count) % count]["pts"]
            next_pts = runs[(i + 1) % count]["pts"]
            if not prev_pts or not next_pts:
                out.extend(pts)
                continue
            chain = [
                prev_pts[max(0, len(prev_pts) - 2)],
                prev_pts[-1],
                *pts,
                next_pts[0],
                next_pts[min(1, len(next_pts) - 1)],
            ]
            cpts = smooth_open(chain, CURVE_STEP)
            if cpts:
                cpts.pop(0)
            out.extend(cpts)
        return out, seam_segs

    def contains(self, tile: tuple[float, float]) -> bool:
        x0, y0, x1, y1 = self.bbox
        if tile[0] < x0 or tile[0] > x1 or tile[1] < y0 or tile[1] > y1:
            return False
        return point_in_polygon(tile, self.footprint)

    def border_at_share(self, share: float) -> dict[str, Any]:
        if not self.borders:
            return {"kind": "forest_sea", "depth": 5.0}
        # Ranged borders have "from" / "to"
        ranged = [b for b in self.borders if "from" in b or "to" in b]
        if ranged:
            s = share % 1.0
            for b in ranged:
                fr = float(b.get("from", 0.0))
                to = float(b.get("to", 1.0))
                if fr <= to:
                    if fr <= s <= to:
                        return b
                else:
                    if s >= fr or s <= to:
                        return b
            return ranged[0]
        return self.borders[0]


class ContinentData:
    def __init__(self, world_dir: pathlib.Path, data_dir: pathlib.Path, entry: dict[str, Any]) -> None:
        self.world_dir = world_dir
        self.data_dir = data_dir
        self.id = str(entry.get("id", "main"))
        self.chart = entry.get("chart", [0.32, 0.30, 0.36, 0.30])
        cpath = resolve_data_path(str(entry.get("file", "")), world_dir, data_dir)
        self.raw: dict[str, Any] = load_json(cpath)
        self.name = str(self.raw.get("name", self.id.upper()))
        sz = as_vec2(self.raw.get("size"), (2400.0, 1800.0)) or (2400.0, 1800.0)
        self.size = (max(1, int(round(sz[0]))), max(1, int(round(sz[1]))))
        self.regions = [r for r in (self.raw.get("regions") or []) if isinstance(r, dict)]
        self.seams: dict[str, dict[str, Any]] = {}
        for s in self.raw.get("seams") or []:
            if isinstance(s, dict) and s.get("id"):
                pts = as_poly(s.get("pts", []))
                if len(pts) >= 2:
                    self.seams[str(s["id"])] = {
                        "id": str(s["id"]),
                        "a": str(s.get("a", "")),
                        "b": str(s.get("b", "")),
                        "kind": str(s.get("kind", "forest_sea")),
                        "pts": pts,
                    }

        self.zones: dict[str, ZoneData] = {}
        self.zone_order: list[str] = []
        for zid in self.raw.get("zones") or []:
            zid_s = str(zid)
            zpath = world_dir / "zones" / zid_s / "zone.json"
            if not zpath.exists():
                raise FileNotFoundError(f"Missing zone.json for '{zid_s}' at {zpath}")
            zraw = load_json(zpath)
            z = ZoneData(zraw, self)
            self.zones[zid_s] = z
            self.zone_order.append(zid_s)

        self.thresholds: list[dict[str, Any]] = []
        trel = str(self.raw.get("thresholds", ""))
        if trel:
            tpath = resolve_data_path(trel, world_dir, data_dir)
            if tpath.exists():
                tdata = load_json(tpath)
                for th in tdata.get("thresholds") or []:
                    if isinstance(th, dict):
                        self._add_threshold(th)

        self.landscape_raw: dict[str, Any] = {}
        lrel = str(self.raw.get("landscape", ""))
        if lrel:
            lpath = resolve_data_path(lrel, world_dir, data_dir)
            if lpath.exists():
                self.landscape_raw = load_json(lpath)

        raw_hull = self.raw.get("landmass") or self.raw.get("coastline")
        self.has_explicit_coastline = isinstance(raw_hull, list) and len(raw_hull) >= 3
        self.has_explicit_rift = isinstance(
            self.raw.get("rift") or self.raw.get("great_rift")
            or self.landscape_raw.get("rift") or self.landscape_raw.get("great_rift"),
            (dict, list, tuple),
        )
        self.islets: list[dict[str, Any]] = []
        for isl in self.raw.get("islets") or []:
            if isinstance(isl, dict):
                ipoly = as_poly(isl.get("poly", isl.get("outline", [])))
                if len(ipoly) >= 3:
                    sm_i = smooth_closed(ipoly, 1.5) if len(ipoly) < 32 else ipoly
                    self.islets.append({
                        "id": str(isl.get("id", f"islet_{len(self.islets)}")),
                        "name": str(isl.get("name", "")),
                        "poly": sm_i,
                    })

        # Fast 1 px/tile spatial zone lookup with 2-tile boundary fallback for O(1) queries
        W, H = self.size
        self._zone_grid = np.full((H, W), -1, dtype=np.int16)
        self._zone_edge_band = np.zeros((H, W), dtype=bool)
        for idx, zid in enumerate(self.zone_order):
            z = self.zones[zid]
            zm = rasterize_polygon_mask(W, H, 0.0, 0.0, 1.0, z.footprint)
            self._zone_grid[zm] = idx
            # Detect edges (within ~2 tiles of polygon rim)
            im_edge = Image.new("L", (W, H), 0)
            draw = ImageDraw.Draw(im_edge)
            if len(z.footprint) >= 2:
                pts_e = [(p[0] - 0.5, p[1] - 0.5) for p in z.footprint] + [(z.footprint[0][0] - 0.5, z.footprint[0][1] - 0.5)]
                draw.line(pts_e, fill=255, width=5)
            self._zone_edge_band |= np.asarray(im_edge, dtype=np.uint8) > 0

    def _add_threshold(self, raw: dict[str, Any]) -> None:
        th = dict(raw)
        line = as_poly(raw.get("line", []))
        sid = str(raw.get("seam", ""))
        if sid and sid in self.seams:
            sp = as_vec2(raw.get("span"), (0.0, 1.0)) or (0.0, 1.0)
            line = sub_polyline(self.seams[sid]["pts"], sp[0], sp[1])
        th["_line"] = line
        self.thresholds.append(th)

    def zone_at_tile(self, tile: tuple[float, float]) -> str:
        ix = int(math.floor(tile[0]))
        iy = int(math.floor(tile[1]))
        W, H = self.size
        if 0 <= ix < W and 0 <= iy < H and not self._zone_edge_band[iy, ix]:
            idx = int(self._zone_grid[iy, ix])
            return self.zone_order[idx] if idx >= 0 else ""
        for zid in self.zone_order:
            if self.zones[zid].contains(tile):
                return zid
        return ""


def load_json(path: pathlib.Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def load_json_any(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def resolve_data_path(rel: str, world_dir: pathlib.Path, data_dir: pathlib.Path) -> pathlib.Path:
    clean = rel.strip()
    if clean.startswith("res://data/"):
        clean = clean[len("res://data/"):]
    elif clean.startswith("res://"):
        clean = clean[len("res://"):]
    if clean.startswith("world/"):
        return world_dir / clean[len("world/"):]
    return data_dir / clean


def load_atlas(world_dir: pathlib.Path, data_dir: pathlib.Path) -> dict[str, ContinentData]:
    atlas_path = world_dir / "atlas.json"
    if not atlas_path.exists():
        raise FileNotFoundError(f"atlas.json not found at {atlas_path}")
    adata = load_json(atlas_path)
    continents: dict[str, ContinentData] = {}
    for entry in adata.get("continents") or []:
        if isinstance(entry, dict) and entry.get("id"):
            c = ContinentData(world_dir, data_dir, entry)
            continents[c.id] = c
    return continents


def load_tree_catalog(data_dir: pathlib.Path) -> dict[str, dict[str, Any]]:
    cat: dict[str, dict[str, Any]] = {
        k: {
            "shades": list(v["shades"]),
            "rim": v["rim"],
            "flecks": list(v["flecks"]),
            "crown_half_px": list(v["crown_half_px"]),
        }
        for k, v in DEFAULT_TREE_PALETTES.items()
    }
    trees_path = data_dir / "trees.json"
    if trees_path.exists():
        tdata = load_json(trees_path)
        for sp, entry in tdata.items():
            if not isinstance(entry, dict):
                continue
            rc = entry.get("rain_colors") or []
            shades = cat.get(sp, cat["valley_oak"])["shades"]
            if len(rc) >= 3:
                c_mid = hex_to_rgb(rc[0])
                c_lit = hex_to_rgb(rc[1])
                c_se = hex_to_rgb(rc[2])
                c_hi = tuple(min(255, int(c_lit[i] * 1.12 + 10)) for i in range(3))
                shades = [c_se, c_mid, c_lit, c_hi]
            rim = tuple(max(8, int(shades[0][i] * 0.55)) for i in range(3))
            rig_name = str(entry.get("rig", ""))
            crowns = list(cat.get(sp, cat["valley_oak"])["crown_half_px"])
            if rig_name:
                rig_path = data_dir / f"{rig_name}.json"
                if rig_path.exists():
                    rdata = load_json(rig_path)
                    for idx, key in enumerate(["s0", "s1", "s2", "s3", "s4", "s5", "s6_log"]):
                        if isinstance(rdata.get(key), dict) and "crown_half_px" in rdata[key]:
                            crowns[idx] = int(rdata[key]["crown_half_px"])
            flecks = []
            if sp == "silver_birch":
                flecks = [(216, 210, 230)]
            elif sp == "wild_apple":
                bl = entry.get("blossom_colors") or []
                if len(bl) >= 3:
                    flecks = [hex_to_rgb(bl[2]), hex_to_rgb(bl[1])]
                else:
                    flecks = [(232, 138, 168)]
            cat[sp] = {"shades": shades, "rim": rim, "flecks": flecks, "crown_half_px": crowns}
    return cat


# ---------------------------------------------------------------------------
# Landscape Deterministic Tree Planning (matches src/world/v2/landscape.gd)
# ---------------------------------------------------------------------------

class PlannedLandscape:
    def __init__(
        self,
        cont: ContinentData,
        trees_override: list[dict[str, Any]] | None = None,
        target_zone_id: str | None = None,
    ) -> None:
        self.cont = cont
        raw = cont.landscape_raw
        self.stands: list[dict[str, Any]] = []
        self.ways: list[dict[str, Any]] = []
        self._way_lines: list[list[tuple[float, float]]] = []
        self._mouths: list[list[tuple[float, float]]] = []
        self.moss: list[tuple[float, float, float, float]] = []
        self.hollows: list[tuple[float, float, float, float]] = []
        self.trees: list[dict[str, Any]] = []
        self._grid: dict[tuple[int, int], list[tuple[float, float]]] = {}

        for entry in raw.get("stands") or []:
            if not isinstance(entry, dict):
                continue
            rpoly = as_poly(entry.get("outline", []))
            if len(rpoly) < 3:
                continue
            outline = smooth_closed(rpoly, CURVE_STEP)
            glades = [smooth_closed(as_poly(g), CURVE_STEP) for g in (entry.get("glades") or []) if len(as_poly(g)) >= 3]
            mix = [m for m in (entry.get("mix") or []) if isinstance(m, dict)] or list(DEFAULT_BELT_MIX)
            self.stands.append({
                "id": str(entry.get("id", "")),
                "name": str(entry.get("name", "")),
                "outline": outline,
                "glades": glades,
                "bbox": bbox_of(outline),
                "soil": bool(entry.get("soil", True)),
                "spacing": max(2.5, float(entry.get("spacing", 6.0))),
                "edge": max(0.0, float(entry.get("edge", 5.0))),
                "seed": int(entry.get("seed", 1)),
                "mix": mix,
            })

        for entry in raw.get("ways") or []:
            if not isinstance(entry, dict):
                continue
            pts = as_poly(entry.get("pts", []))
            if len(pts) < 2:
                continue
            self.ways.append({
                "kind": str(entry.get("kind", "trail")),
                "pts": pts,
                "seed": int(entry.get("seed", 263)),
                "damp": float(entry.get("damp", 0.0)),
                "bbox": bbox_of(pts),
            })
            self._way_lines.append(smooth_open(pts, 1.0))

        for m in raw.get("moss") or []:
            if isinstance(m, list) and len(m) >= 4:
                self.moss.append((float(m[0]), float(m[1]), float(m[2]), float(m[3])))
        for h in raw.get("hollows") or []:
            if isinstance(h, list) and len(h) >= 4:
                self.hollows.append((float(h[0]), float(h[1]), float(h[2]), float(h[3])))

        for th in cont.thresholds:
            if str(th.get("kind", "")) in SEAMLESS_KINDS and len(th.get("_line", [])) >= 2:
                self._mouths.append(th["_line"])

        # Fast 1 px/tile spatial masks for O(1) reject in _near_ways / _in_mouth / _stand_at / _owner_of
        W, H = cont.size
        im_ways = Image.new("L", (W, H), 0)
        dw = ImageDraw.Draw(im_ways)
        for line in self._way_lines:
            if len(line) >= 2:
                dw.line([(p[0] - 0.5, p[1] - 0.5) for p in line], fill=255, width=int(math.ceil(WAY_GAP * 2 + 5)))
        self._way_near_mask = np.asarray(im_ways, dtype=np.uint8) > 0

        im_mouths = Image.new("L", (W, H), 0)
        dm = ImageDraw.Draw(im_mouths)
        for line in self._mouths:
            if len(line) >= 2:
                dm.line([(p[0] - 0.5, p[1] - 0.5) for p in line], fill=255, width=int(math.ceil(MOUTH * 2 + 5)))
        self._mouth_near_mask = np.asarray(im_mouths, dtype=np.uint8) > 0

        # Per-stand fast interior/edge masks for _stand_at O(1) lookup
        self._stand_grid = np.full((H, W), -1, dtype=np.int16)
        self._stand_edge_band = np.zeros((H, W), dtype=bool)
        for s_idx, st in enumerate(self.stands):
            x0, y0, x1, y1 = st["bbox"]
            sx0 = max(0, int(math.floor(x0)) - 4)
            sy0 = max(0, int(math.floor(y0)) - 4)
            sx1 = min(W, int(math.ceil(x1)) + 4)
            sy1 = min(H, int(math.ceil(y1)) + 4)
            sw, sh = sx1 - sx0, sy1 - sy0
            if sw <= 0 or sh <= 0:
                continue
            sm = rasterize_polygon_mask(sw, sh, float(sx0), float(sy0), 1.0, st["outline"])
            for gl in st["glades"]:
                sm &= ~rasterize_polygon_mask(sw, sh, float(sx0), float(sy0), 1.0, gl)
            self._stand_grid[sy0:sy1, sx0:sx1][sm] = s_idx
            im_se = Image.new("L", (sw, sh), 0)
            dse = ImageDraw.Draw(im_se)
            pts_o = [(p[0] - sx0 - 0.5, p[1] - sy0 - 0.5) for p in st["outline"]]
            dse.line(pts_o + [pts_o[0]], fill=255, width=9)
            for gl in st["glades"]:
                pts_g = [(p[0] - sx0 - 0.5, p[1] - sy0 - 0.5) for p in gl]
                dse.line(pts_g + [pts_g[0]], fill=255, width=9)
            self._stand_edge_band[sy0:sy1, sx0:sx1] |= np.asarray(im_se, dtype=np.uint8) > 0

        if trees_override is not None:
            for t in trees_override:
                pos = as_vec2(t.get("pos"))
                if pos is None:
                    continue
                owner = str(t.get("owner", "")) or self._owner_of(pos)
                if owner:
                    self.trees.append({
                        "species": str(t.get("species", "valley_oak")),
                        "pos": pos,
                        "stage": int(clampf(float(t.get("stage", 4)), 0, 6)),
                        "seed": int(t.get("seed", 1)),
                        "kind": str(t.get("kind", "hand")),
                        "owner": owner,
                    })
        else:
            t_bbox: tuple[float, float, float, float] | None = None
            if target_zone_id and target_zone_id in cont.zones:
                tx0, ty0, tx1, ty1 = cont.zones[target_zone_id].bbox
                t_bbox = (tx0 - 16.0, ty0 - 16.0, tx1 + 16.0, ty1 + 16.0)
            self._plan_hand_trees(raw)
            for stand in self.stands:
                if t_bbox is not None:
                    sx0, sy0, sx1, sy1 = stand["bbox"]
                    if sx1 < t_bbox[0] or sx0 > t_bbox[2] or sy1 < t_bbox[1] or sy0 > t_bbox[3]:
                        continue
                self._plan_stand(stand)
            for zid in cont.zone_order:
                if t_bbox is not None:
                    zx0, zy0, zx1, zy1 = cont.zones[zid].bbox
                    if zx1 < t_bbox[0] or zx0 > t_bbox[2] or zy1 < t_bbox[1] or zy0 > t_bbox[3]:
                        continue
                self._plan_belt(cont.zones[zid])

    def _stand_contains(self, stand: dict[str, Any], tile: tuple[float, float]) -> bool:
        x0, y0, x1, y1 = stand["bbox"]
        if tile[0] < x0 or tile[0] > x1 or tile[1] < y0 or tile[1] > y1:
            return False
        if not point_in_polygon(tile, stand["outline"]):
            return False
        for g in stand["glades"]:
            if point_in_polygon(tile, g):
                return False
        return True

    def _stand_at(self, tile: tuple[float, float]) -> dict[str, Any] | None:
        ix = int(math.floor(tile[0]))
        iy = int(math.floor(tile[1]))
        W, H = self.cont.size
        if 0 <= ix < W and 0 <= iy < H and not self._stand_edge_band[iy, ix]:
            idx = int(self._stand_grid[iy, ix])
            return self.stands[idx] if idx >= 0 else None
        for s in self.stands:
            if self._stand_contains(s, tile):
                return s
        return None

    def _crowded(self, tile: tuple[float, float], gap: float) -> bool:
        cx = math.floor(tile[0] / PLAN_GRID)
        cy = math.floor(tile[1] / PLAN_GRID)
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                for other in self._grid.get((cx + ox, cy + oy), ()):
                    if dist_pts(tile, other) < gap:
                        return True
        return False

    def _in_mouth(self, tile: tuple[float, float]) -> bool:
        ix = int(math.floor(tile[0]))
        iy = int(math.floor(tile[1]))
        W, H = self.cont.size
        if 0 <= ix < W and 0 <= iy < H and not self._mouth_near_mask[iy, ix]:
            return False
        for line in self._mouths:
            if polyline_distance(tile, line) < MOUTH_CLEAR:
                return True
        return False

    def _near_ways(self, tile: tuple[float, float], gap: float) -> bool:
        ix = int(math.floor(tile[0]))
        iy = int(math.floor(tile[1]))
        W, H = self.cont.size
        if gap <= WAY_GAP + 0.1 and 0 <= ix < W and 0 <= iy < H and not self._way_near_mask[iy, ix]:
            return False
        for line in self._way_lines:
            if polyline_distance(tile, line) < gap:
                return True
        return False

    def _owner_of(self, tile: tuple[float, float]) -> str:
        inside = self.cont.zone_at_tile(tile)
        if inside:
            return inside
        best = ""
        best_d = BELT_OUT + 0.6
        for zid in self.cont.zone_order:
            z = self.cont.zones[zid]
            x0, y0, x1, y1 = z.bbox
            if tile[0] < x0 - best_d or tile[0] > x1 + best_d or tile[1] < y0 - best_d or tile[1] > y1 + best_d:
                continue
            d = edge_distance(tile, z.footprint)
            if d < best_d or (abs(d - best_d) < 1e-5 and zid < best):
                best_d = d
                best = zid
        return best

    def _add_tree(self, species: str, tile: tuple[float, float], stage: int, seed: int, kind: str) -> None:
        owner = self._owner_of(tile)
        if not owner:
            return
        self.trees.append({
            "species": species,
            "pos": tile,
            "stage": max(0, min(6, int(stage))),
            "seed": int(seed),
            "kind": kind,
            "owner": owner,
        })
        cell = (math.floor(tile[0] / PLAN_GRID), math.floor(tile[1] / PLAN_GRID))
        self._grid.setdefault(cell, []).append(tile)

    @staticmethod
    def _pick_mix(mix: list[dict[str, Any]], roll: float) -> dict[str, Any]:
        total = sum(max(0.0, float(e.get("w", 1.0))) for e in mix)
        at = roll * total
        for e in mix:
            at -= max(0.0, float(e.get("w", 1.0)))
            if at <= 0.0:
                return e
        return mix[-1] if mix else {}

    def _plan_hand_trees(self, raw: dict[str, Any]) -> None:
        for entry in raw.get("trees") or []:
            if not isinstance(entry, dict):
                continue
            pos = as_vec2(entry.get("pos"))
            if pos is None:
                continue
            self._add_tree(
                str(entry.get("species", "valley_oak")),
                pos,
                int(entry.get("stage", 4)),
                int(entry.get("seed", 0)),
                "hand",
            )
        # Also pick up any zone-local hand trees in zone.nature.trees or zone.trees
        for zid in self.cont.zone_order:
            z = self.cont.zones[zid]
            ox, oy = z.origin
            extra = list(z.raw.get("trees") or []) + list(z.nature.get("trees") or [])
            for entry in extra:
                if not isinstance(entry, dict):
                    continue
                pos = as_vec2(entry.get("pos"))
                if pos is None:
                    continue
                if not bool(entry.get("abs", False)):
                    pos = (pos[0] + ox, pos[1] + oy)
                self._add_tree(
                    str(entry.get("species", "valley_oak")),
                    pos,
                    int(entry.get("stage", 4)),
                    int(entry.get("seed", 0)),
                    "hand",
                )

    def _plan_stand(self, stand: dict[str, Any]) -> None:
        sp = stand["spacing"]
        x0, y0, x1, y1 = stand["bbox"]
        fx, fy = math.floor(x0 / sp), math.floor(y0 / sp)
        tx, ty = math.ceil(x1 / sp), math.ceil(y1 / sp)
        rng = PCG32()
        cand_x: list[float] = []
        cand_y: list[float] = []
        cand_keep: list[float] = []
        cand_pick: list[float] = []
        cand_age: list[float] = []
        cand_seed: list[int] = []
        s_seed = stand["seed"]
        for gy in range(fy, ty + 1):
            for gx in range(fx, tx + 1):
                rng.seed(godot_hash_array([s_seed, gx, gy]))
                tx_c = (gx + 0.12 + rng.randf() * 0.76) * sp
                ty_c = (gy + 0.12 + rng.randf() * 0.76) * sp
                keep = rng.randf()
                pick = rng.randf()
                age = rng.randf()
                tree_seed = rng.randi_range(1, 99999)
                if x0 <= tx_c <= x1 and y0 <= ty_c <= y1:
                    cand_x.append(tx_c)
                    cand_y.append(ty_c)
                    cand_keep.append(keep)
                    cand_pick.append(pick)
                    cand_age.append(age)
                    cand_seed.append(tree_seed)
        if not cand_x:
            return

        cx = np.array(cand_x, dtype=np.float64)
        cy = np.array(cand_y, dtype=np.float64)
        in_out = points_in_polygon_grid(cx, cy, stand["outline"])
        if not np.any(in_out):
            return

        idx_in = np.flatnonzero(in_out)
        ix = cx[idx_in]
        iy = cy[idx_in]

        # Vectorized exact glade check & distance
        glade_d = np.full(len(idx_in), 1e9, dtype=np.float64)
        for g in stand["glades"]:
            in_g = points_in_polygon_grid(ix, iy, g)
            ga = np.array(g, dtype=np.float64)
            gb = np.roll(ga, -1, axis=0)
            vx = (gb[:, 0] - ga[:, 0])[:, None]
            vy = (gb[:, 1] - ga[:, 1])[:, None]
            l2 = np.maximum(vx * vx + vy * vy, 1e-12)
            t = np.clip(((ix[None, :] - ga[:, 0:1]) * vx + (iy[None, :] - ga[:, 1:2]) * vy) / l2, 0.0, 1.0)
            d2 = (ix[None, :] - (ga[:, 0:1] + t * vx)) ** 2 + (iy[None, :] - (ga[:, 1:2] + t * vy)) ** 2
            gd = np.where(in_g, -1.0, np.sqrt(np.min(d2, axis=0)))
            glade_d = np.minimum(glade_d, gd)

        # Organic deterministic wobble on glade & stand rims so forests never read as stacked circular donuts
        ph_g = (s_seed % 360) * 0.0174533
        wob_gl = (
            np.sin(ix * 0.065 + ph_g) * np.cos(iy * 0.055 - ph_g * 0.7) * 5.2
            + np.sin((ix + iy) * 0.14 + ph_g * 1.9) * 2.6
        )
        eff_glade_d = glade_d + wob_gl
        ok_glade = eff_glade_d >= GLADE_EDGE
        if not np.any(ok_glade):
            return
        idx_in = idx_in[ok_glade]
        ix = ix[ok_glade]
        iy = iy[ok_glade]
        glade_d = eff_glade_d[ok_glade]

        edge_v = stand["edge"]
        if edge_v > 0.0:
            oa = np.array(stand["outline"], dtype=np.float64)
            ob = np.roll(oa, -1, axis=0)
            # Chunked exact rim_distance over surviving points
            best_d2 = np.full(len(idx_in), 1e18, dtype=np.float64)
            n_seg = len(oa)
            for s in range(0, n_seg, 64):
                e = min(n_seg, s + 64)
                vx = (ob[s:e, 0] - oa[s:e, 0])[:, None]
                vy = (ob[s:e, 1] - oa[s:e, 1])[:, None]
                l2 = np.maximum(vx * vx + vy * vy, 1e-12)
                t = np.clip(((ix[None, :] - oa[s:e, 0:1]) * vx + (iy[None, :] - oa[s:e, 1:2]) * vy) / l2, 0.0, 1.0)
                d2 = (ix[None, :] - (oa[s:e, 0:1] + t * vx)) ** 2 + (iy[None, :] - (oa[s:e, 1:2] + t * vy)) ** 2
                best_d2 = np.minimum(best_d2, np.min(d2, axis=0))
            wob_out = np.sin(ix * 0.052 - ph_g * 1.3) * np.cos(iy * 0.048 + ph_g) * 3.2
            d_out = np.maximum(0.0, np.sqrt(best_d2) + wob_out) / edge_v
            d_gl = (glade_d - GLADE_EDGE) / max(edge_v * 0.65, 1.0)
            thin_arr = np.clip(np.minimum(d_out, d_gl), 0.0, 1.0)
        else:
            thin_arr = np.ones(len(idx_in), dtype=np.float64)

        for k_idx, orig_i in enumerate(idx_in):
            thin = float(thin_arr[k_idx])
            if cand_keep[orig_i] > lerpf(0.38, 1.0, thin):
                continue
            tile = (cand_x[orig_i], cand_y[orig_i])
            if self._near_ways(tile, WAY_GAP) or self._in_mouth(tile) or self._crowded(tile, sp * 0.8):
                continue
            entry = self._pick_mix(stand["mix"], cand_pick[orig_i])
            stages = entry.get("stages") or [4]
            idx = int(clampf(int(cand_age[orig_i] * len(stages) * lerpf(0.55, 1.0, thin)), 0, len(stages) - 1))
            self._add_tree(str(entry.get("species", "valley_oak")), tile, int(stages[idx]), cand_seed[orig_i], "stand")

    def _plan_belt(self, z: ZoneData) -> None:
        if len(z.footprint) < 3:
            return
        has_forest_border = any(str(b.get("kind", "forest_sea")) == "forest_sea" for b in z.borders) or not z.borders
        if not has_forest_border:
            return
        ring = list(z.footprint) + [z.footprint[0]]
        seg_cum = [0.0]
        for k in range(len(ring) - 1):
            seg_cum.append(seg_cum[-1] + dist_pts(ring[k], ring[k + 1]))
        total = seg_cum[-1]
        if total < 1.0:
            return

        def fast_point_along(share_v: float) -> tuple[float, float]:
            want = clampf(share_v, 0.0, 1.0) * total
            idx = bisect.bisect_right(seg_cum, want) - 1
            idx = max(0, min(len(ring) - 2, idx))
            part = seg_cum[idx + 1] - seg_cum[idx]
            t = clampf((want - seg_cum[idx]) / max(part, 1e-4), 0.0, 1.0)
            return (lerpf(ring[idx][0], ring[idx + 1][0], t), lerpf(ring[idx][1], ring[idx + 1][1], t))

        W, H = self.cont.size
        rng = PCG32()
        steps = max(1, int(total / BELT_SPACING))
        for i in range(steps):
            share = i / float(steps)
            border = z.border_at_share(share)
            if str(border.get("kind", "forest_sea")) != "forest_sea":
                continue
            depth = max(1.0, float(border.get("depth", 5.0)))
            mix = [m for m in (border.get("mix") or []) if isinstance(m, dict)] or list(DEFAULT_BELT_MIX)
            rows: list[float] = []
            d = -depth
            while d <= BELT_OUT + 0.01:
                rows.append(d)
                d += BELT_SPACING * 0.78

            p = fast_point_along(share)
            ahead = fast_point_along(min(1.0, share + 0.5 / total))
            behind = fast_point_along(max(0.0, share - 0.5 / total))
            tx, ty = ahead[0] - behind[0], ahead[1] - behind[1]
            tl = math.hypot(tx, ty)
            if tl <= 1e-8:
                continue
            tx, ty = tx / tl, ty / tl
            nx, ny = -ty, tx  # orthogonal
            if z.contains((p[0] + nx * 0.6, p[1] + ny * 0.6)):
                nx, ny = -nx, -ny

            for r, row_d in enumerate(rows):
                rng.seed(godot_hash_array([z.id, i, r]))
                q_n = row_d + rng.randf_range(-0.45, 0.45)
                q_t = rng.randf_range(-0.38, 0.38) * BELT_SPACING
                q = (p[0] + nx * q_n + tx * q_t, p[1] + ny * q_n + ty * q_t)
                keep = rng.randf()
                pick = rng.randf()
                age = rng.randf()
                tree_seed = rng.randi_range(1, 99999)
                chance = 1.0 if row_d >= 0.0 else lerpf(1.0, 0.28, -row_d / depth)
                ix, iy = int(math.floor(q[0])), int(math.floor(q[1]))
                if 0 <= ix < W and 0 <= iy < H and not self._mouth_near_mask[iy, ix]:
                    mouth_d = 1e9
                else:
                    mouth_d = min((polyline_distance(q, line) for line in self._mouths), default=1e9)
                if mouth_d < MOUTH_CLEAR:
                    continue
                chance *= smoothstep_scalar(MOUTH_CLEAR, MOUTH, mouth_d)
                if keep > chance:
                    continue
                inside = self.cont.zone_at_tile(q)
                if inside and inside != z.id:
                    continue
                if self._stand_at(q) is not None or self._near_ways(q, WAY_GAP) or self._crowded(q, BELT_SPACING * 0.74):
                    continue
                entry = self._pick_mix(mix, pick)
                stages = entry.get("stages") or [4]
                old = clampf((row_d + depth) / (depth + BELT_OUT), 0.0, 1.0)
                idx = int(clampf(round(lerpf(0.0, float(len(stages) - 1), old) + (age - 0.5) * 1.2), 0, len(stages) - 1))
                self._add_tree(str(entry.get("species", "valley_oak")), q, int(stages[idx]), tree_seed, "belt")

    def trees_of(self, zone_id: str) -> list[dict[str, Any]]:
        return [t for t in self.trees if t["owner"] == zone_id]


# ---------------------------------------------------------------------------
# Schema-Tolerant Feature Extraction (Water, Cliffs, Props, Landmarks, Rift)
# ---------------------------------------------------------------------------

def _collect_zone_features(cont: ContinentData, z: ZoneData) -> dict[str, Any]:
    """Extracts water, cliffs/rocky, ways, roofs, ruins, rocks, campfires, settlements, blockers, arcane points."""
    ox, oy = z.origin
    lraw = cont.landscape_raw
    zraw = z.raw

    def shift_pt(raw_pt: Any, abs_flag: bool) -> tuple[float, float] | None:
        v = as_vec2(raw_pt)
        if v is None:
            return None
        return v if abs_flag else (v[0] + ox, v[1] + oy)

    def shift_poly(raw_pts: Any, abs_flag: bool) -> list[tuple[float, float]]:
        return as_poly(raw_pts, (0.0, 0.0) if abs_flag else (float(ox), float(oy)))

    # Optional baked/ inputs (from bake_zone.py if present)
    baked_dir = cont.world_dir / "zones" / z.id / "baked"
    baked_paths: dict[str, Any] = {}
    if (baked_dir / "paths.json").exists():
        bp_raw = load_json_any(baked_dir / "paths.json")
        if isinstance(bp_raw, dict):
            baked_paths = bp_raw
        elif isinstance(bp_raw, list):
            baked_paths = {"paths": bp_raw}
    baked_props = load_json(baked_dir / "props.json") if (baked_dir / "props.json").exists() else {}

    # Ways: continent-wide + zone-local + baked/paths.json
    ways: list[dict[str, Any]] = []
    for w in lraw.get("ways") or []:
        if isinstance(w, dict) and len(as_poly(w.get("pts", []))) >= 2:
            ways.append({"kind": str(w.get("kind", "trail")), "pts": as_poly(w["pts"]), "seed": int(w.get("seed", 263))})
    for src in (z.nature.get("ways") or [], zraw.get("ways") or [], baked_paths.get("ways") or baked_paths.get("paths") or []):
        for w in src:
            if isinstance(w, dict):
                pts = shift_poly(w.get("pts", w.get("line", [])), bool(w.get("abs", False)))
                if len(pts) >= 2:
                    ways.append({"kind": str(w.get("kind", "trail")), "pts": pts, "seed": int(w.get("seed", 263))})

    # Water features: brooks/rivers, lakes/ponds, puddles, coastline, fords, bridges, reefs
    brooks: list[dict[str, Any]] = []
    lakes: list[dict[str, Any]] = []
    puddles: list[dict[str, Any]] = []
    fords: list[tuple[float, float, float]] = []
    bridges: list[dict[str, Any]] = []
    coasts: list[dict[str, Any]] = []
    reefs: list[dict[str, float]] = []

    def add_brook_entry(item: dict[str, Any], abs_f: bool, is_cont_river: bool = False) -> None:
        pts_raw = item.get("pts") or item.get("line") or item.get("points") or []
        raw_rs: list[float] = []
        raw_xy: list[tuple[float, float]] = []
        default_r = float(item.get("radius", item.get("width", 4.0) * 0.5))
        sx, sy = (0.0, 0.0) if abs_f else (float(ox), float(oy))
        for p in pts_raw:
            if isinstance(p, (list, tuple)) and len(p) >= 2:
                r = float(p[2]) if len(p) >= 3 else default_r
                raw_xy.append((float(p[0]) + sx, float(p[1]) + sy))
                raw_rs.append(r)
            elif isinstance(p, dict):
                pv = shift_pt(p.get("pos", p), abs_f)
                if pv:
                    raw_xy.append(pv)
                    raw_rs.append(float(p.get("r", p.get("radius", default_r))))
        if len(raw_xy) < 2:
            return
        # Detect world-px radii (e.g. windkap water.brooks: [246, 70, 26..54]) vs continent river elevations (16 -> 0)
        max_r = max(raw_rs) if raw_rs else 0.0
        scale_r = (1.0 / 16.0) if (not is_cont_river and max_r > 12.0) else 1.0
        pts_r: list[tuple[float, float, float]] = []
        if is_cont_river:
            r_seed = int(item.get("seed", godot_hash_array([str(item.get("id", ""))]) & 0xFFFF))
            pts_r = _shape_continent_river(raw_xy, raw_rs, r_seed)
        else:
            for (px, py), r in zip(raw_xy, raw_rs):
                rt = max(1.2, r * scale_r)
                pts_r.append((px, py, rt))
        pools_parsed: list[tuple[float, float, float]] = []
        for pl in item.get("pools") or []:
            if isinstance(pl, dict):
                ppos = shift_pt(pl.get("pos", pl.get("tile")), abs_f)
                if ppos:
                    pr = float(pl.get("radius", 6.0))
                    pools_parsed.append((ppos[0], ppos[1], pr))
        fords_parsed: list[tuple[float, float, float]] = []
        for fd in item.get("fords") or []:
            if isinstance(fd, dict):
                fpos = shift_pt(fd.get("pos", fd.get("tile")), abs_f)
                if fpos:
                    fr = float(fd.get("radius", 4.5))
                    fords_parsed.append((fpos[0], fpos[1], fr))
                    fords.append((fpos[0], fpos[1], fr))
        brooks.append({
            "pts": pts_r,
            "pools": pools_parsed,
            "fords": fords_parsed,
            "seed": int(item.get("seed", 17)),
            "is_cont_river": is_cont_river,
        })

    def parse_bridge_entry(item: dict[str, Any], abs_f: bool) -> None:
        pos = shift_pt(item.get("pos", item.get("tile")), abs_f)
        if pos is None:
            return
        # Deduplicate against already added bridges within 3 tiles
        for ex in bridges:
            if dist_pts(ex["pos"], pos) < 3.0:
                return
        ang = float(item.get("angle", 0.0))
        axis = str(item.get("axis", "")).lower()
        if axis == "ns":
            ang = math.pi * 0.5
        elif axis == "ew":
            ang = 0.0
        bridges.append({
            "pos": pos,
            "angle": ang,
            "length": float(item.get("length", 8.2)),
            "width": float(item.get("width", 2.2)),
        })

    def parse_water_list(items: Any, default_abs: bool, is_cont_river: bool = False) -> None:
        if not isinstance(items, list):
            return
        for item in items:
            if isinstance(item, list) and len(item) >= 4:
                sx, sy = (0.0, 0.0) if default_abs else (float(ox), float(oy))
                lakes.append({"cx": float(item[0]) + sx, "cy": float(item[1]) + sy, "rx": float(item[2]), "ry": float(item[3])})
            elif isinstance(item, dict):
                abs_f = bool(item.get("abs", default_abs))
                kind = str(item.get("kind", "lake")).lower()
                if kind in ("brook", "river", "stream", "creek"):
                    add_brook_entry(item, abs_f, is_cont_river=is_cont_river)
                elif kind in ("ford",):
                    pos = shift_pt(item.get("pos", item.get("tile")), abs_f)
                    if pos:
                        fords.append((pos[0], pos[1], float(item.get("radius", 3.5))))
                elif kind in ("bridge",):
                    parse_bridge_entry(item, abs_f)
                elif kind in ("puddle", "pool"):
                    pos = shift_pt(item.get("pos", item.get("center")), abs_f)
                    if pos:
                        puddles.append({"cx": pos[0], "cy": pos[1], "rx": float(item.get("rx", item.get("radius", 3.0))), "ry": float(item.get("ry", item.get("radius", 2.5)))})
                elif kind in ("coast", "coastline", "surf"):
                    pts = shift_poly(item.get("pts", item.get("shore_pts", [])), abs_f)
                    if len(pts) >= 2:
                        coasts.append({
                            "pts": pts,
                            "sea_side": item.get("sea_side", "south_west"),
                            "dry_sand_width": float(item.get("dry_sand_width", 6.5)),
                            "headlands": item.get("headlands") or [],
                            "reefs": item.get("reefs") or [],
                            "abs": abs_f,
                        })
                else:
                    poly = shift_poly(item.get("poly", item.get("pts", [])), abs_f)
                    if len(poly) >= 3:
                        lakes.append({"poly": poly})
                    else:
                        pos = shift_pt(item.get("pos", item.get("center")), abs_f)
                        if pos:
                            lakes.append({"cx": pos[0], "cy": pos[1], "rx": float(item.get("rx", item.get("radius", 6.0))), "ry": float(item.get("ry", item.get("radius", 5.0)))})

    for src, is_abs in ((lraw, True), (zraw, False), (z.nature, False)):
        w_val = src.get("water")
        if isinstance(w_val, list):
            parse_water_list(w_val, is_abs)
        elif isinstance(w_val, dict):
            # Zone structured water dict (windkap schema: coast, brooks, lakes, puddles, fords, bridges)
            coast_obj = w_val.get("coast")
            if isinstance(coast_obj, dict):
                abs_c = bool(coast_obj.get("abs", is_abs))
                spts = shift_poly(coast_obj.get("shore_pts", coast_obj.get("pts", [])), abs_c)
                if len(spts) >= 2:
                    sx_c, sy_c = (0.0, 0.0) if abs_c else (float(ox), float(oy))
                    hlands = []
                    for hl in coast_obj.get("headlands") or []:
                        if isinstance(hl, dict):
                            hc = as_vec2(hl.get("center"))
                            hr = as_vec2(hl.get("radii"), (18.0, 16.0))
                            if hc and hr:
                                hlands.append((hc[0] + sx_c, hc[1] + sy_c, hr[0], hr[1]))
                    for rf in coast_obj.get("reefs") or []:
                        if isinstance(rf, dict):
                            rc = as_vec2(rf.get("center"))
                            rr = as_vec2(rf.get("radii"), (8.0, 5.0))
                            if rc and rr:
                                reefs.append({"cx": rc[0] + sx_c, "cy": rc[1] + sy_c, "rx": rr[0], "ry": rr[1]})
                    coasts.append({
                        "pts": spts,
                        "sea_side": coast_obj.get("sea_side", -1),
                        "dry_sand_width": float(coast_obj.get("dry_sand_width", 6.5)),
                        "headlands": hlands,
                    })
            for br in w_val.get("brooks") or []:
                if isinstance(br, dict):
                    add_brook_entry(br, bool(br.get("abs", is_abs)), is_cont_river=False)
            for lk in w_val.get("lakes") or []:
                parse_water_list([lk], is_abs)
            for pd in w_val.get("puddles") or []:
                parse_water_list([pd], is_abs)
            for brg in w_val.get("bridges") or []:
                if isinstance(brg, dict):
                    parse_bridge_entry(brg, bool(brg.get("abs", is_abs)))
            for fd in w_val.get("fords") or []:
                if isinstance(fd, dict):
                    fpos = shift_pt(fd.get("pos", fd.get("tile")), bool(fd.get("abs", is_abs)))
                    if fpos:
                        fords.append((fpos[0], fpos[1], float(fd.get("radius", 3.5))))

        for key, def_kind in (("brooks", "brook"), ("rivers", "brook"), ("lakes", "lake"), ("puddles", "puddle"), ("bridges", "bridge")):
            items = src.get(key)
            if isinstance(items, list):
                wrapped = []
                for it in items:
                    if isinstance(it, dict) and "kind" not in it:
                        d = dict(it)
                        d["kind"] = def_kind
                        wrapped.append(d)
                    else:
                        wrapped.append(it)
                parse_water_list(wrapped, is_abs, is_cont_river=(key == "rivers" and is_abs))
        for f in src.get("fords") or []:
            if isinstance(f, (list, tuple)) and len(f) >= 2:
                sx, sy = (0.0, 0.0) if is_abs else (float(ox), float(oy))
                fords.append((float(f[0]) + sx, float(f[1]) + sy, float(f[2]) if len(f) >= 3 else 3.5))
            elif isinstance(f, dict):
                pos = shift_pt(f.get("pos", f.get("tile")), bool(f.get("abs", is_abs)))
                if pos:
                    fords.append((pos[0], pos[1], float(f.get("radius", 3.5))))
        if isinstance(src.get("coastline"), list):
            pts = shift_poly(src.get("coastline"), is_abs)
            if len(pts) >= 2:
                coasts.append({"pts": pts, "sea_side": src.get("sea_side", "south_west"), "dry_sand_width": 6.5, "headlands": []})

    # If zone defines local brooks, drop continent rivers that overlap the same zone to avoid double-drawing
    local_brooks = [b for b in brooks if not b.get("is_cont_river")]
    if local_brooks:
        brooks = local_brooks

    # Cliffs / Rocky / Elevation regions (supports both list and dict schema like windkap.cliffs)
    cliffs: list[dict[str, Any]] = []
    scree_fans: list[dict[str, Any]] = []
    moss_pockets: list[tuple[float, float, float, float]] = []
    rocks: list[dict[str, Any]] = []

    for src, is_abs in ((lraw, True), (zraw, False), (z.nature, False)):
        sx_def, sy_def = (0.0, 0.0) if is_abs else (float(ox), float(oy))
        for key in ("cliffs", "rocky", "ridges", "relief", "plateaus"):
            val = src.get(key)
            if isinstance(val, dict):
                # windkap.cliffs structured dict
                for hr in val.get("highland_rects") or []:
                    if isinstance(hr, list) and len(hr) >= 4:
                        hx, hy, hw, hh = float(hr[0]) + sx_def, float(hr[1]) + sy_def, float(hr[2]), float(hr[3])
                        cliffs.append({"poly": _organic_rect_poly(hx, hy, hw, hh, seed=int(abs(hx * 7 + hy * 13)) + 313), "height": 0.34, "terrace": True})
                existing_polys = {tuple((round(p[0], 2), round(p[1], 2)) for p in c["poly"]) for c in cliffs if "poly" in c}
                for hp in val.get("highland_polys") or []:
                    hpoly = shift_poly(hp, is_abs)
                    if len(hpoly) >= 3:
                        sig = tuple((round(p[0], 2), round(p[1], 2)) for p in hpoly)
                        if sig not in existing_polys:
                            existing_polys.add(sig)
                            cliffs.append({"poly": hpoly, "height": 0.32, "terrace": True})
                for bs in val.get("bedrock_shelves") or []:
                    if isinstance(bs, dict):
                        c = as_vec2(bs.get("center"))
                        r = as_vec2(bs.get("radii"), (14.0, 10.0))
                        if c and r:
                            cliffs.append({"cx": c[0] + sx_def, "cy": c[1] + sy_def, "rx": r[0], "ry": r[1], "height": 0.36 * float(bs.get("strength", 0.9))})
                for sf in val.get("scree_fans") or []:
                    if isinstance(sf, dict):
                        c = as_vec2(sf.get("center"))
                        r = as_vec2(sf.get("radii"), (12.0, 10.0))
                        if c and r:
                            scree_fans.append({"cx": c[0] + sx_def, "cy": c[1] + sy_def, "rx": r[0], "ry": r[1], "strength": float(sf.get("strength", 0.8))})
                for qt in val.get("quarry_trails") or []:
                    qpts = shift_poly(qt, is_abs)
                    if len(qpts) >= 2:
                        ways.append({"kind": "quarry_trail", "pts": qpts, "seed": 411})
                for mp in val.get("moss_pockets") or []:
                    if isinstance(mp, dict):
                        c = as_vec2(mp.get("center"))
                        r = as_vec2(mp.get("radii"), (8.0, 6.0))
                        if c and r:
                            moss_pockets.append((c[0] + sx_def, c[1] + sy_def, r[0], r[1]))
                for rk in val.get("rocks") or []:
                    if isinstance(rk, dict):
                        rpos = shift_pt(rk.get("tile", rk.get("pos")), is_abs)
                        if rpos:
                            st = int(rk.get("stage", 2))
                            rocks.append({"pos": rpos, "r": 1.1 + st * 0.35})
            elif isinstance(val, list):
                for item in val:
                    if isinstance(item, list) and len(item) >= 4 and all(isinstance(v, (int, float)) for v in item[:4]):
                        cliffs.append({"cx": float(item[0]) + sx_def, "cy": float(item[1]) + sy_def, "rx": float(item[2]), "ry": float(item[3]), "height": 0.45})
                    elif isinstance(item, dict):
                        abs_f = bool(item.get("abs", is_abs))
                        h = float(item.get("height", item.get("level", 0.45)))
                        if h > 1.0:
                            h = clampf(h * 0.18, 0.15, 0.75)
                        poly = shift_poly(item.get("poly", item.get("outline", [])), abs_f)
                        pts = shift_poly(item.get("pts", item.get("line", [])), abs_f)
                        if len(poly) >= 3:
                            cliffs.append({"poly": poly, "height": h})
                        elif len(pts) >= 2:
                            cliffs.append({"line": pts, "width": float(item.get("width", 5.0)), "height": h})
                        else:
                            pos = shift_pt(item.get("pos", item.get("center")), abs_f)
                            if pos:
                                cliffs.append({"cx": pos[0], "cy": pos[1], "rx": float(item.get("rx", 8.0)), "ry": float(item.get("ry", 6.0)), "height": h})

    # Landmarks, Campfires, Settlements, Roofs, Ruins, Rocks, Blockers
    campfires: list[tuple[float, float]] = []
    camps: list[dict[str, Any]] = []
    settlements: list[tuple[float, float, float]] = []
    roofs: list[dict[str, Any]] = []
    ruins: list[dict[str, Any]] = []
    arcane_pts: list[tuple[float, float]] = []
    blockers: list[dict[str, Any]] = []

    def add_unique_pt(lst: list[tuple[float, float]], pt: tuple[float, float], min_d: float = 2.0) -> None:
        if all(dist_pts(p, pt) >= min_d for p in lst):
            lst.append(pt)

    def add_camp(pos: tuple[float, float], seat: tuple[float, float] | None = None, chest: tuple[float, float] | None = None, rack: tuple[float, float] | None = None) -> None:
        add_unique_pt(campfires, pos)
        if all(dist_pts(c["pos"], pos) >= 3.0 for c in camps):
            camps.append({
                "pos": pos,
                "seat": seat or (pos[0] + 2.0, pos[1] + 0.9),
                "chest": chest or (pos[0] - 4.8, pos[1] - 1.2),
                "rack": rack or (pos[0] + 3.4, pos[1] - 1.4),
                "tent": (pos[0] - 2.6, pos[1] - 2.2),
            })

    def classify_item(item: dict[str, Any], abs_f: bool) -> None:
        pos = shift_pt(item.get("pos", item.get("center", item.get("tile"))), abs_f)
        if pos is None:
            return
        kind = str(item.get("kind", "")).lower()
        iid = str(item.get("id", "")).lower()
        name = str(item.get("name", "")).lower()
        if kind in ("bridge",) or "bridge" in iid or "bruecke" in iid:
            parse_bridge_entry(item, abs_f)
        elif kind in ("campfire", "camp", "hearth", "coastal_camp", "bonfire") or (
            any(k in iid or k in name for k in ("camp", "lager", "feuer")) and "ruin" not in kind
        ):
            add_camp(pos)
        elif kind in ("settlement", "town", "village", "outpost", "house", "cabin", "hut", "building", "roof"):
            w = float(item.get("w", item.get("width", 5.0)))
            h = float(item.get("h", item.get("height", 4.0)))
            roofs.append({"pos": pos, "w": w, "h": h, "style": str(item.get("roof_style", "wood"))})
            if kind in ("settlement", "town", "village", "outpost"):
                settlements.append((pos[0], pos[1], float(item.get("radius", 16.0))))
        elif kind in ("ruin", "ruins", "lighthouse", "tower", "tablet", "map_tablet", "stone_setter", "parapet"):
            ruins.append({"pos": pos, "r": float(item.get("radius", 4.5)), "kind": kind})
            if kind in ("lighthouse", "tablet", "map_tablet", "stone_setter"):
                add_unique_pt(arcane_pts, pos, 1.5)
        elif kind in ("waystone", "veil_thread", "shrine", "crystal", "vista"):
            add_unique_pt(arcane_pts, pos, 1.5)
            if kind in ("waystone", "vista"):
                ruins.append({"pos": pos, "r": 2.4 if kind == "waystone" else 2.2, "kind": kind})
        elif kind in ("rock", "boulder", "stone", "rocks"):
            rocks.append({"pos": pos, "r": float(item.get("radius", 1.8))})

    for lm in z.landmarks:
        if isinstance(lm, dict):
            classify_item(lm, False)

    # Parse windkap-style top-level camp, ruin (+tablet), waystones, vistas, blockers
    camp_obj = zraw.get("camp")
    if isinstance(camp_obj, dict):
        cf_pt = shift_pt(camp_obj.get("campfire_tile", camp_obj.get("tile")), False)
        if cf_pt:
            seat_pt = shift_pt(camp_obj.get("seat_tile"), False)
            chest_obj = camp_obj.get("chest")
            chest_pt = shift_pt(chest_obj.get("tile") if isinstance(chest_obj, dict) else None, False)
            starters = camp_obj.get("starter_items") or []
            rack_pt = shift_pt(starters[0].get("tile") if starters and isinstance(starters[0], dict) else None, False)
            add_camp(cf_pt, seat=seat_pt, chest=chest_pt, rack=rack_pt)

    ruin_obj = zraw.get("ruin")
    if isinstance(ruin_obj, dict):
        rpt = shift_pt(ruin_obj.get("lighthouse_tile", ruin_obj.get("tile")), False)
        if rpt and all(dist_pts(r["pos"], rpt) >= 2.0 for r in ruins):
            ruins.append({"pos": rpt, "r": 4.8, "kind": "lighthouse"})
            add_unique_pt(arcane_pts, rpt, 1.5)
        tab_obj = ruin_obj.get("tablet")
        if isinstance(tab_obj, dict):
            tpt = shift_pt(tab_obj.get("tile", tab_obj.get("pos")), False)
            if tpt:
                ruins.append({"pos": tpt, "r": 2.1, "kind": "map_tablet"})
                add_unique_pt(arcane_pts, tpt, 1.5)

    for ws in zraw.get("waystones") or []:
        if isinstance(ws, dict):
            wpt = shift_pt(ws.get("tile", ws.get("pos")), False)
            if wpt:
                add_unique_pt(arcane_pts, wpt, 1.5)
                if all(dist_pts(r["pos"], wpt) >= 2.0 for r in ruins):
                    ruins.append({"pos": wpt, "r": 2.4, "kind": "waystone"})

    for vs in zraw.get("vistas") or []:
        if isinstance(vs, dict):
            vpt = shift_pt(vs.get("tile", vs.get("pos")), False)
            if vpt:
                add_unique_pt(arcane_pts, vpt, 1.5)
                if all(dist_pts(r["pos"], vpt) >= 2.0 for r in ruins):
                    ruins.append({"pos": vpt, "r": 2.2, "kind": "vista"})

    for blk in zraw.get("blockers") or []:
        if isinstance(blk, dict):
            bpt = shift_pt(blk.get("tile", blk.get("pos")), False)
            if bpt:
                blockers.append({"pos": bpt, "kind": str(blk.get("kind", "rockfall"))})

    for src, is_abs in ((lraw, True), (zraw, False), (z.nature, False), (baked_props, False)):
        for key, def_kind in (
            ("landmarks", ""), ("camps", "campfire"), ("campfires", "campfire"),
            ("buildings", "house"), ("roofs", "house"), ("structures", "house"),
            ("settlements", "settlement"), ("ruins", "ruin"), ("rocks", "rock"),
        ):
            for it in src.get(key) or []:
                if isinstance(it, dict):
                    d = dict(it)
                    if def_kind and not d.get("kind"):
                        d["kind"] = def_kind
                    classify_item(d, bool(d.get("abs", is_abs)))
                elif isinstance(it, (list, tuple)) and len(it) >= 2:
                    sx, sy = (0.0, 0.0) if is_abs else (float(ox), float(oy))
                    pt = (float(it[0]) + sx, float(it[1]) + sy)
                    if key in ("camps", "campfires"):
                        add_unique_pt(campfires, pt)
                    elif key == "rocks":
                        rocks.append({"pos": pt, "r": float(it[2]) if len(it) >= 3 else 1.8})

    for pl in z.places:
        if isinstance(pl, dict):
            pk = str(pl.get("kind", "")).lower()
            pid = str(pl.get("id", "")).lower()
            if pk in ("settlement", "town", "village") or "stadt" in pid or "dorf" in pid or "glimmrast" in pid:
                poly = shift_poly(pl.get("poly", []), False)
                if poly:
                    cx = sum(p[0] for p in poly) / len(poly)
                    cy = sum(p[1] for p in poly) / len(poly)
                    settlements.append((cx, cy, 18.0))
            if pk in ("camp", "coastal_camp") and not campfires:
                poly = shift_poly(pl.get("poly", []), False)
                if poly:
                    cx = sum(p[0] for p in poly) / len(poly)
                    cy = sum(p[1] for p in poly) / len(poly)
                    add_unique_pt(campfires, (cx, cy))

    if z.kind in ("home", "settlement") and not settlements:
        x0, y0, x1, y1 = z.bbox
        settlements.append(((x0 + x1) * 0.5, (y0 + y1) * 0.5, 22.0))

    return {
        "ways": ways,
        "brooks": brooks,
        "lakes": lakes,
        "puddles": puddles,
        "fords": fords,
        "bridges": bridges,
        "coasts": coasts,
        "reefs": reefs,
        "cliffs": cliffs,
        "scree_fans": scree_fans,
        "moss_pockets": moss_pockets,
        "campfires": campfires,
        "camps": camps,
        "settlements": settlements,
        "roofs": roofs,
        "ruins": ruins,
        "rocks": rocks,
        "blockers": blockers,
        "arcane_pts": arcane_pts,
        "baked_dir": baked_dir,
    }


def _meander_polyline(
    pts: list[tuple[float, float]],
    seed: int,
    amp: float,
    freq: float,
    subdiv: int = 12,
) -> list[tuple[float, float]]:
    """Subdivides a polyline with Catmull-Rom and applies smooth endpoint-tapered perpendicular meander."""
    sm = subdivide_catmull(pts, subdiv=subdiv)
    n = len(sm)
    if n < 3 or amp <= 0.0:
        return sm
    cum = [0.0]
    for i in range(1, n):
        cum.append(cum[-1] + math.hypot(sm[i][0] - sm[i - 1][0], sm[i][1] - sm[i - 1][1]))
    total = max(cum[-1], 1e-6)
    p1 = (seed % 360) * 0.0174533
    p2 = ((seed * 13 + 71) % 360) * 0.0174533
    out: list[tuple[float, float]] = [sm[0]]
    for i in range(1, n - 1):
        u = cum[i] / total
        taper = math.sin(math.pi * u) ** 0.85
        tx_v = sm[i + 1][0] - sm[i - 1][0]
        ty_v = sm[i + 1][1] - sm[i - 1][1]
        tl = max(math.hypot(tx_v, ty_v), 1e-6)
        nx_v, ny_v = -ty_v / tl, tx_v / tl
        disp = amp * taper * (0.65 * math.sin(cum[i] * freq + p1) + 0.35 * math.cos(cum[i] * freq * 2.15 + p2))
        out.append((sm[i][0] + nx_v * disp, sm[i][1] + ny_v * disp))
    out.append(sm[-1])
    return out


def _organic_rect_poly(hx: float, hy: float, hw: float, hh: float, seed: int = 313) -> list[tuple[float, float]]:
    """Converts a blocky highland rectangle into an organically warped multi-vertex crag polygon."""
    cx = hx + hw * 0.5
    cy = hy + hh * 0.5
    rx = hw * 0.52
    ry = hh * 0.52
    p1 = (seed % 360) * 0.0174533
    p2 = ((seed * 11) % 360) * 0.0174533
    pts: list[tuple[float, float]] = []
    n_pts = 28
    for i in range(n_pts):
        ang = (2.0 * math.pi * i) / n_pts
        # Squircle base + natural crag lobes (never a boxy rectangle)
        sq = (abs(math.cos(ang)) ** 2.4 + abs(math.sin(ang)) ** 2.4) ** (-1.0 / 2.4)
        lobe = 1.0 + 0.16 * math.sin(3.0 * ang + p1) + 0.10 * math.cos(5.0 * ang + p2) + 0.05 * math.sin(9.0 * ang + p1 * 2.0)
        r_scale = sq * lobe
        pts.append((cx + math.cos(ang) * rx * r_scale, cy + math.sin(ang) * ry * r_scale))
    return pts


def _shape_continent_river(
    raw_xy: list[tuple[float, float]],
    raw_rs: list[float],
    seed: int,
) -> list[tuple[float, float, float]]:
    """Meanders a continent river and tapers width narrow-upstream -> wide-downstream + estuary mouth."""
    if len(raw_xy) < 2:
        return []
    # Check if 3rd coordinate represents elevation (decreasing downstream) vs explicit radius
    is_elev_desc = len(raw_rs) >= 2 and raw_rs[0] > raw_rs[-1] + 0.5
    ends_at_sea = len(raw_rs) >= 1 and raw_rs[-1] <= 0.55
    sm = _meander_polyline(raw_xy, seed=seed, amp=9.5, freq=0.022, subdiv=12)
    n = len(sm)
    cum = [0.0]
    for i in range(1, n):
        cum.append(cum[-1] + math.hypot(sm[i][0] - sm[i - 1][0], sm[i][1] - sm[i - 1][1]))
    total = max(cum[-1], 1e-6)
    out: list[tuple[float, float, float]] = []
    for i, (px, py) in enumerate(sm):
        u = cum[i] / total
        if is_elev_desc:
            base_w = lerpf(1.05, 2.55, u ** 0.75)
            if ends_at_sea and u > 0.85:
                est_t = smoothstep_scalar(0.85, 1.0, u)
                base_w = lerpf(base_w, 5.2, est_t)
        else:
            base_w = clampf(lerpf(1.2, 2.6, u), 1.0, 4.2)
        # Slight natural riffle/pool width undulation
        undul = 1.0 + 0.14 * math.sin(cum[i] * 0.08 + seed * 0.17)
        out.append((px, py, base_w * undul))
    return out


def _cyclic_arc_inside_weight(s: np.ndarray, fr: float, to: float, half_blend: float) -> np.ndarray:
    """Smooth membership weight in [0, 1] for cyclic share s in [0, 1) within arc [fr, to]."""
    fr_m = fr % 1.0
    to_m = to % 1.0
    span = (to_m - fr_m) if fr_m <= to_m else ((1.0 - fr_m) + to_m)
    if span >= 0.999 or (abs(to - fr) >= 0.999):
        return np.ones_like(s, dtype=np.float32)
    if span <= 1e-6:
        return np.zeros_like(s, dtype=np.float32)
    mid = (fr_m + span * 0.5) % 1.0
    d_mid = np.abs(((s - mid + 0.5) % 1.0) - 0.5)
    signed_in = span * 0.5 - d_mid
    return smoothstep_np(-half_blend, half_blend, signed_in)


def _apply_craggy_ridge(
    W: int,
    H: int,
    ox: float,
    oy: float,
    scale: float,
    pts: list[tuple[float, float]],
    cw: float,
    h_add: float,
    elev: np.ndarray,
    rock_blend: np.ndarray,
    ridge_seed: int,
    n_spur: np.ndarray,
    n_crag: np.ndarray,
) -> None:
    """Sculpts a mountain ridge with peaked crest, saddles, endpoint taper, and lateral spurs."""
    if len(pts) < 2:
        return
    spine = _meander_polyline(pts, seed=ridge_seed, amp=min(7.5, cw * 0.24), freq=0.032, subdiv=10)
    if len(spine) < 2:
        return
    cum = [0.0]
    for i in range(1, len(spine)):
        cum.append(cum[-1] + math.hypot(spine[i][0] - spine[i - 1][0], spine[i][1] - spine[i - 1][1]))
    total_len = max(cum[-1], 1.0)

    # Taper width & add peak/saddle swells along spine
    radii: list[float] = []
    p1 = (ridge_seed % 360) * 0.0174533
    for i in range(len(spine)):
        u = cum[i] / total_len
        taper = 0.26 + 0.74 * (math.sin(math.pi * u) ** 0.52)
        peak_swell = 0.80 + 0.26 * math.sin(cum[i] * 0.055 + p1) + 0.14 * math.cos(cum[i] * 0.13 - p1 * 1.7)
        radii.append(max(2.2, cw * taper * peak_swell))

    sa = np.array(spine[:-1], dtype=np.float32)
    sb = np.array(spine[1:], dtype=np.float32)
    seg_r = np.stack([radii[:-1], radii[1:]], axis=1).astype(np.float32)
    max_r = float(max(radii)) * 1.45 + 3.0
    sdf, rr = fast_narrowband_segments_distance(W, H, ox, oy, scale, sa, sb, max_r, seg_radii=seg_r)
    assert rr is not None
    raw_d = sdf + rr

    # Lateral rocky spurs branching off the main mountain spine
    spur_sa: list[tuple[float, float]] = []
    spur_sb: list[tuple[float, float]] = []
    spur_sr: list[tuple[float, float]] = []
    step_sp = max(22.0, cw * 1.45)
    next_sp = step_sp * 0.65
    sp_idx = 0
    for i in range(1, len(spine) - 1):
        if cum[i] < next_sp:
            continue
        next_sp += step_sp
        u = cum[i] / total_len
        if u < 0.10 or u > 0.90:
            continue
        tx_v = spine[i + 1][0] - spine[i - 1][0]
        ty_v = spine[i + 1][1] - spine[i - 1][1]
        tl = max(math.hypot(tx_v, ty_v), 1e-6)
        tx_v, ty_v = tx_v / tl, ty_v / tl
        side = 1.0 if (sp_idx % 2 == 0) else -1.0
        ang_sp = math.atan2(ty_v, tx_v) + side * (0.85 + 0.35 * math.sin(sp_idx * 2.3 + p1))
        sp_len = cw * (0.95 + 0.45 * abs(math.cos(sp_idx * 1.7 + p1)))
        mid_pt = (
            spine[i][0] + math.cos(ang_sp) * sp_len * 0.52 + tx_v * 3.0 * side,
            spine[i][1] + math.sin(ang_sp) * sp_len * 0.52 + ty_v * 3.0 * side,
        )
        tip_pt = (
            spine[i][0] + math.cos(ang_sp + side * 0.18) * sp_len,
            spine[i][1] + math.sin(ang_sp + side * 0.18) * sp_len,
        )
        r_root = radii[i] * 0.52
        r_mid = radii[i] * 0.34
        r_tip = max(1.5, cw * 0.12)
        spur_sa.extend([spine[i], mid_pt])
        spur_sb.extend([mid_pt, tip_pt])
        spur_sr.extend([(r_root, r_mid), (r_mid, r_tip)])
        sp_idx += 1

    eff_w = rr * (0.58 + 0.72 * n_spur + 0.28 * n_crag)
    d_norm = np.clip(raw_d / np.maximum(eff_w, 1.5), 0.0, 1.0)
    # Sharp ridged peak profile (not a flat-topped sausage)
    crest = np.power(1.0 - d_norm, 1.38) * (0.76 + 0.32 * n_spur + 0.16 * (n_crag - 0.5))

    if spur_sa:
        sdf_sp, rr_sp = fast_narrowband_segments_distance(
            W, H, ox, oy, scale,
            np.array(spur_sa, dtype=np.float32),
            np.array(spur_sb, dtype=np.float32),
            cw * 1.2 + 2.0,
            seg_radii=np.array(spur_sr, dtype=np.float32),
        )
        assert rr_sp is not None
        raw_d_sp = sdf_sp + rr_sp
        eff_w_sp = rr_sp * (0.62 + 0.68 * n_spur + 0.26 * n_crag)
        d_norm_sp = np.clip(raw_d_sp / np.maximum(eff_w_sp, 1.2), 0.0, 1.0)
        crest_sp = np.power(1.0 - d_norm_sp, 1.42) * 0.68 * (0.80 + 0.28 * n_spur)
        crest = np.maximum(crest, crest_sp)

    cm = crest > 0.02
    if np.any(cm):
        # Add craggy elevation relief & strong rock blend
        crag_elev = crest[cm] * h_add * (0.88 + 0.24 * n_crag[cm])
        elev[cm] = np.maximum(elev[cm], 0.25 + crag_elev)
        rock_w = smoothstep_np(0.06, 0.36, crest[cm])
        rock_blend[cm] = np.maximum(rock_blend[cm], rock_w)


# ---------------------------------------------------------------------------
# Zone Painter (4 px/tile map.png, map_light.png, 1 px/tile far.png, meta.json)
# ---------------------------------------------------------------------------

def _apply_ramp_vec(ramp: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Fast 256-entry LUT interpolation of Nx3 RGB ramp for normalized field t in [0, 1]."""
    n_stops = len(ramp)
    x = np.linspace(0.0, float(n_stops - 1), 256, dtype=np.float32)
    i0 = np.floor(x).astype(np.int32)
    i1 = np.minimum(i0 + 1, n_stops - 1)
    f = (x - i0)[:, None]
    lut = (ramp[i0] * (1.0 - f) + ramp[i1] * f).astype(np.float32)
    idx = np.clip((t * 255.0).astype(np.int32), 0, 255)
    return lut[idx]


def _draw_tree_crown(
    rgb: np.ndarray,
    elev: np.ndarray,
    alpha_mask: np.ndarray,
    nx_arr: np.ndarray,
    ny_arr: np.ndarray,
    cx: float,
    cy: float,
    radius: float,
    species: str,
    seed: int,
    tree_cat: dict[str, dict[str, Any]],
    biome_idx: int = 0,
) -> None:
    """Paint one crisp pixel-art tree crown with Bayer-dithered SE shadow, 1px INK rim, and Bayer-quantized foliage clusters."""
    sp_key = SPECIES_ALIASES.get(species, species)
    spec = tree_cat.get(sp_key, tree_cat["valley_oak"])
    if biome_idx in (1, 2, 3, 5):
        cp = CANOPY_PALETTES[biome_idx]
        bp_hi = BIOME_PALETTES[biome_idx, 2]
        # Preserve species luminance nuance (brighter silver_birch, deeper fir) inside the biome palette
        l_mul = 1.12 if sp_key == "silver_birch" else (0.86 if sp_key == "fir" else 1.0)
        shades = np.clip(
            np.stack([
                cp[0] * 0.85 + INK_PIXEL * 0.15,
                cp[0] * l_mul,
                cp[1] * l_mul,
                (cp[2] * 0.72 + bp_hi * 0.28) * l_mul,
            ], axis=0),
            12.0,
            245.0,
        ).astype(np.float32)
        rim = INK_PIXEL * 0.78 + cp[0] * 0.22
        flecks = [] if biome_idx in (2, 3) else spec["flecks"]
    else:
        shades = np.array(spec["shades"], dtype=np.float32)
        rim = INK_PIXEL * 0.65 + np.array(spec["rim"], dtype=np.float32) * 0.35
        flecks = spec["flecks"]

    H, W = rgb.shape[:2]
    r = max(1.6, radius)
    ir = int(math.ceil(r + 5.0))
    x0 = max(0, int(math.floor(cx)) - ir)
    x1 = min(W, int(math.ceil(cx)) + ir + 1)
    y0 = max(0, int(math.floor(cy)) - ir)
    y1 = min(H, int(math.ceil(cy)) + ir + 1)
    if x1 <= x0 or y1 <= y0:
        return

    xs = np.arange(x0, x1, dtype=np.float32)[None, :]
    ys = np.arange(y0, y1, dtype=np.float32)[:, None]
    dx = (xs + 0.5) - cx
    dy = (ys + 0.5) - cy
    xx_i = np.arange(x0, x1, dtype=np.int32)[None, :]
    yy_i = np.arange(y0, y1, dtype=np.int32)[:, None]
    bayer_loc = BAYER_4X4[yy_i & 3, xx_i & 3]

    # Organic scalloped multi-lobe silhouette per tree seed
    ang = np.arctan2(dy, dx)
    p1 = (seed % 360) * 0.0174533
    p2 = ((seed * 7) % 360) * 0.0174533
    if sp_key == "fir":
        wobble = 1.0 + 0.20 * np.cos(5.0 * ang + p1) + 0.09 * np.sin(3.0 * ang + p2)
    else:
        wobble = 1.0 + 0.13 * np.sin(4.0 * ang + p1) + 0.08 * np.cos(7.0 * ang + p2)
    eff_r = r * wobble
    dist = np.hypot(dx, dy)

    # 1. Crisp Bayer-dithered SE drop shadow (+2.0..3.6 px offset)
    sh_off = max(1.8, r * 0.28)
    sh_dist = np.hypot(dx - sh_off, dy - sh_off)
    shadow_m = (sh_dist <= eff_r * 0.98) & (dist > eff_r) & (bayer_loc < 0.78)
    if np.any(shadow_m):
        sub_rgb = rgb[y0:y1, x0:x1]
        sub_rgb[shadow_m] = sub_rgb[shadow_m] * 0.44 + INK_PIXEL * 0.56

    # 2. Crown body + crisp 1px pixel-art INK outline (4-connected morphological rim)
    crown_m = dist <= eff_r
    if not np.any(crown_m):
        return
    pad_c = np.pad(crown_m, 1, mode="constant", constant_values=False)
    rim_m = crown_m & (
        (~pad_c[:-2, 1:-1]) | (~pad_c[2:, 1:-1]) | (~pad_c[1:-1, :-2]) | (~pad_c[1:-1, 2:])
    )
    inner_m = crown_m & (~rim_m)

    # NW->SE dome normal + sub-lobe foliage cluster relief -> 4x4 Bayer quantized into 4 shades
    inv_r = 1.0 / max(r, 1.0)
    cnx = np.broadcast_to(np.clip(dx * inv_r, -0.95, 0.95), dist.shape)
    cny = np.broadcast_to(np.clip(dy * inv_r, -0.95, 0.95), dist.shape)
    lobe_mod = 0.12 * np.sin(dx * (2.6 * inv_r) + p1) * np.cos(dy * (2.6 * inv_r) - p2)
    lit = np.clip(-(cnx * 0.707 + cny * 0.707) * 0.52 + 0.52 + lobe_mod, 0.0, 1.0)
    tone = bayer_quantize_ramp(shades, lit, bayer_loc, spread=0.72)

    # Interior dark crevice pixel between SE underside lobes on large crowns
    if r >= 4.0:
        crev = inner_m & (lit < 0.24) & (lobe_mod < -0.04) & (bayer_loc < 0.45)
        if np.any(crev):
            tone[crev] = rim

    # Birch silver flecks / wild-apple blossom flecks (clean clustered pixel accents)
    if flecks and r >= 3.0:
        s_mix = np.int32(((seed * 83492791) & 0x7FFFFFFF))
        with np.errstate(over="ignore"):
            cell_h = (((xx_i * np.int32(73856093)) ^ (yy_i * np.int32(19349663)) ^ s_mix) & np.int32(31))
        f_mask = inner_m & (cell_h == 0) & (lit > 0.48)
        if np.any(f_mask):
            tone[f_mask] = flecks[seed % len(flecks)]

    sub_rgb = rgb[y0:y1, x0:x1]
    sub_rgb[inner_m] = tone[inner_m]
    sub_rgb[rim_m] = rim

    # Update map_light channels (crown dome elevation & normals + CANOPY bit)
    sub_el = elev[y0:y1, x0:x1]
    dome_h = np.clip(1.0 - (dist / max(r, 1.0)) ** 2, 0.0, 1.0) * min(0.16, 0.04 + r * 0.008)
    sub_el[crown_m] = np.minimum(1.0, np.maximum(sub_el[crown_m], sub_el[crown_m] * 0.35 + 0.25 * 0.65 + dome_h[crown_m]))
    nx_arr[y0:y1, x0:x1][crown_m] = np.clip(nx_arr[y0:y1, x0:x1][crown_m] * 0.3 + cnx[crown_m] * 0.7, -1.0, 1.0)
    ny_arr[y0:y1, x0:x1][crown_m] = np.clip(ny_arr[y0:y1, x0:x1][crown_m] * 0.3 + cny[crown_m] * 0.7, -1.0, 1.0)
    sub_a = alpha_mask[y0:y1, x0:x1]
    sub_a[crown_m] = (sub_a[crown_m] & np.uint8(255 ^ (BIT_MEADOW | BIT_WATER))) | np.uint8(BIT_CANOPY)


def _sanitize_zero_black(rgba: np.ndarray) -> np.ndarray:
    """Guarantees ZERO (0, 0, 0, a>0) pixels in any output image."""
    bad = (rgba[..., 3] > 0) & (rgba[..., 0] == 0) & (rgba[..., 1] == 0) & (rgba[..., 2] == 0)
    if np.any(bad):
        rgba[bad, 0] = 14
        rgba[bad, 1] = 9
        rgba[bad, 2] = 25
    return rgba


def _assert_zero_black(rgba: np.ndarray, label: str) -> None:
    bad = (rgba[..., 3] > 0) & (rgba[..., 0] == 0) & (rgba[..., 1] == 0) & (rgba[..., 2] == 0)
    if np.any(bad):
        raise AssertionError(f"{label} contains {int(np.sum(bad))} opaque #000000 pixels")


def paint_zone(
    cont: ContinentData,
    land: PlannedLandscape,
    z: ZoneData,
    tree_cat: dict[str, dict[str, Any]],
    write_outputs: bool = True,
) -> dict[str, Any]:
    """Bakes 4 px/tile map.png & map_light.png + 1 px/tile far.png + meta.json for one zone."""
    ox, oy = z.origin
    tw, th = z.size
    W, H = tw * PX_PER_TILE, th * PX_PER_TILE
    feats = _collect_zone_features(cont, z)

    # Coordinate grids in continent tiles at pixel centers
    py_idx, px_idx = np.mgrid[0:H, 0:W].astype(np.float32)
    tx = ox + (px_idx + 0.5) / PX_PER_TILE
    ty = oy + (py_idx + 0.5) / PX_PER_TILE

    # 1. Zone footprint & neighboring ownership masks (fast PIL scanline rasterization)
    inside = rasterize_polygon_mask(W, H, float(ox), float(oy), float(PX_PER_TILE), z.footprint)
    other_inside = np.zeros((H, W), dtype=bool)
    for ozid in cont.zone_order:
        if ozid == z.id:
            continue
        oz = cont.zones[ozid]
        bx0, by0, bx1, by1 = oz.bbox
        if bx1 < ox or bx0 > ox + tw or by1 < oy or by0 > oy + th:
            continue
        other_inside |= rasterize_polygon_mask(W, H, float(ox), float(oy), float(PX_PER_TILE), oz.footprint)

    # Optional baked/mask.png override if present
    mask_png = feats["baked_dir"] / "mask.png"
    if mask_png.exists():
        mim = Image.open(mask_png).convert("RGBA").resize((W, H), Image.Resampling.NEAREST)
        marr = np.asarray(mim, dtype=np.uint8)
        if np.any(marr[..., 0] > 127):
            inside = marr[..., 0] > 127

    # Distance & perimeter share to own footprint via coarse-to-fine JFA
    fp = z.footprint
    segs_a = np.array(fp, dtype=np.float32)
    segs_b = np.roll(segs_a, -1, axis=0)
    seg_lens = np.hypot(segs_b[:, 0] - segs_a[:, 0], segs_b[:, 1] - segs_a[:, 1])
    total_len = max(float(np.sum(seg_lens)), 1e-4)
    cum = np.concatenate(([0.0], np.cumsum(seg_lens))) / total_len
    seg_shares = np.stack([cum[:-1], cum[1:]], axis=1).astype(np.float32)

    rim_d, rim_share = fast_segments_distance_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), segs_a, segs_b, seg_shares)
    ext_d = np.where(inside, 0.0, rim_d)

    # Precompute world-continuous terrain noise fields (100% deterministic, zero hash(z.id) variance)
    n_ground = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=313, freq=0.09, octaves=3, sub=4)
    n_detail = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=719, freq=0.35, octaves=2, sub=2)

    # Map perimeter share -> smooth border weights (no 4x4 stair-steps, ~3-tile organic blends)
    # 0=forest_sea, 1=water, 2=cliff/mountain, 3=abyss, 4=void_edge, 5=building
    KIND_MAP = {
        "forest_sea": 0, "meadow": 0, "water": 1, "coast": 1, "ocean": 1,
        "cliff": 2, "mountain": 2, "ridge": 2, "abyss": 3, "void_edge": 4, "building": 5,
    }
    border_weights = np.zeros((6, H, W), dtype=np.float32)
    ranged_borders = [b for b in z.borders if "from" in b or "to" in b]
    if not z.borders:
        border_weights[0] = 1.0
    elif not ranged_borders:
        k0 = KIND_MAP.get(str(z.borders[0].get("kind", "forest_sea")), 0)
        border_weights[k0] = 1.0
    else:
        blend_arc = min(0.024, 2.8 / max(total_len, 1.0))
        share_jit = (rim_share + (n_ground - 0.5) * min(0.014, 1.6 / max(total_len, 1.0))) % 1.0
        for b in ranged_borders:
            k_id = KIND_MAP.get(str(b.get("kind", "forest_sea")), 0)
            w_b = _cyclic_arc_inside_weight(share_jit, float(b.get("from", 0.0)), float(b.get("to", 1.0)), blend_arc)
            border_weights[k_id] = np.maximum(border_weights[k_id], w_b)
        w_sum = np.sum(border_weights, axis=0)
        fallback = w_sum < 1e-4
        if np.any(fallback):
            border_weights[0][fallback] = 1.0
            w_sum = np.sum(border_weights, axis=0)
        border_weights /= np.maximum(w_sum, 1e-6)[None, ...]

    # Override border weights smoothly along seam edges using seam.kind
    for spts, skind in z.seam_segments:
        sa = np.array(spts[:-1], dtype=np.float32)
        sb = np.array(spts[1:], dtype=np.float32)
        sd, _ = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), sa, sb, 7.5)
        sw = 1.0 - smoothstep_np(4.0, 7.0, sd)
        k_s = KIND_MAP.get(skind, 0)
        border_weights *= (1.0 - sw)[None, ...]
        border_weights[k_s] += sw

    border_kind_grid = np.argmax(border_weights, axis=0).astype(np.int32)
    w_water = border_weights[1]
    w_cliff = border_weights[2]
    w_abyss = border_weights[3]
    w_void = border_weights[4]

    # Nearest other zone distance for borderland ownership
    nearest_other = np.full((H, W), 1e6, dtype=np.float32)
    other_wins_tie = np.zeros((H, W), dtype=bool)
    for ozid in cont.zone_order:
        if ozid == z.id:
            continue
        oz = cont.zones[ozid]
        bx0, by0, bx1, by1 = oz.bbox
        if bx1 < ox - 16 or bx0 > ox + tw + 16 or by1 < oy - 16 or by0 > oy + th + 16:
            continue
        oa = np.array(oz.footprint, dtype=np.float32)
        ob = np.roll(oa, -1, axis=0)
        od, _ = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), oa, ob, ZONE_BAKE_MARGIN + 4.0)
        closer = od < nearest_other
        nearest_other = np.where(closer, od, nearest_other)
        other_wins_tie = np.where(closer, ozid < z.id, other_wins_tie)

    # Explicit coastline curves (compute ext_start/ext_end BEFORE coast_dist so SE coast has full sand + surf)
    coast_sea_mask = np.zeros((H, W), dtype=bool)
    coast_dist = np.full((H, W), 1e6, dtype=np.float32)
    coast_sand_width = 6.5
    headland_mask = np.zeros((H, W), dtype=bool)
    for co in feats["coasts"]:
        pts = subdivide_catmull(co["pts"], subdiv=8)
        if len(pts) < 2:
            continue
        coast_sand_width = max(coast_sand_width, float(co.get("dry_sand_width", 6.5)))

        side_raw = co.get("sea_side", "south_west")
        if isinstance(side_raw, (int, float)):
            p0, p1 = pts[0], pts[min(1, len(pts) - 1)]
            p_prev, p_last = pts[max(0, len(pts) - 2)], pts[-1]
            # Extend start along blended incoming shore tangent toward W/NW so no flat horizontal cut appears
            tx_s, ty_s = (p0[0] - p1[0]), (p0[1] - p1[1])
            el_s = max(math.hypot(tx_s, ty_s), 1.0)
            ux_s = (tx_s / el_s) * 0.45 - 0.89
            uy_s = (ty_s / el_s) * 0.55 - 0.25
            ext_start = (p0[0] + ux_s * 120.0, p0[1] + uy_s * 120.0)
            # Extend end smoothly east/southeast along outgoing tangent
            tx_e, ty_e = p_last[0] - p_prev[0], p_last[1] - p_prev[1]
            el_e = max(math.hypot(tx_e, ty_e), 1.0)
            ext_end = (p_last[0] + (tx_e / el_e) * 140.0, p_last[1] + (ty_e / el_e) * 140.0)
            pts_ext = [ext_start] + list(pts) + [ext_end]
            poly_sea = pts_ext + [(ox + tw + 90.0, ext_end[1]), (ox + tw + 90.0, oy + th + 90.0), (ox - 90.0, oy + th + 90.0), (ox - 90.0, ext_start[1])]
            sea_m_co = rasterize_polygon_mask(W, H, float(ox), float(oy), float(PX_PER_TILE), poly_sea)
        else:
            pts_ext = list(pts)
            side = str(side_raw).lower()
            cx_c = sum(p[0] for p in pts) / len(pts)
            cy_c = sum(p[1] for p in pts) / len(pts)
            sea_m_co = np.zeros((H, W), dtype=bool)
            if "west" in side:
                sea_m_co |= tx < cx_c
            if "east" in side:
                sea_m_co |= tx > cx_c
            if "south" in side:
                sea_m_co |= ty > cy_c
            if "north" in side:
                sea_m_co |= ty < cy_c
        sa = np.array(pts_ext[:-1], dtype=np.float32)
        sb = np.array(pts_ext[1:], dtype=np.float32)
        cd, _ = fast_segments_distance_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), sa, sb, None)
        coast_dist = np.minimum(coast_dist, cd)
        coast_sea_mask |= sea_m_co
        n_hl_wob = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=673, freq=0.18, octaves=2, sub=4)
        for hl in co.get("headlands") or []:
            if isinstance(hl, tuple) and len(hl) == 4:
                hcx, hcy, hrx, hry = hl
                headland_mask |= (np.hypot((tx - hcx) / max(hrx, 1.0), (ty - hcy) / max(hry, 1.0)) + (n_hl_wob - 0.5) * 0.28) <= 0.96

    # Capped & smoothly tapered coastal water extent (never shoots unbounded diagonal rays to bbox edges)
    water_reach = WATER_BAKE_MARGIN * smoothstep_np(0.06, 0.58, w_water) + (n_ground - 0.5) * 2.4
    if feats["coasts"]:
        is_water_border = (
            ((w_water > 0.08) & (coast_sea_mask | (ty > oy + th * 0.72)) & (ext_d <= np.maximum(ZONE_BAKE_MARGIN, water_reach)))
            | (coast_sea_mask & (~inside) & (ext_d <= ZONE_BAKE_MARGIN + 4.0) & (w_water > 0.04))
        )
    else:
        is_water_border = (w_water > 0.12) & (ext_d <= water_reach)

    w_va = w_abyss + w_void
    ext_cap = np.where(w_va > 0.35, VOID_BAKE_MARGIN, ZONE_BAKE_MARGIN)
    owned_border = (~inside) & (~other_inside) & (
        ((ext_d <= ext_cap) & ((ext_d < nearest_other) | ((np.abs(ext_d - nearest_other) < 1e-4) & (~other_wins_tie))))
        | (is_water_border & (w_va <= 0.45))
    )
    owned_domain = inside | owned_border

    # 2. Forest floor mask (1 px/tile -> 2x box blur -> 4 px/tile wobble, matching ZoneStage)
    # Note: np.mgrid[0:th, 0:tw] returns (row=Y, col=X)!
    t_gy, t_gx = np.mgrid[0:th, 0:tw].astype(np.float32)
    ttx = ox + t_gx + 0.5
    tty = oy + t_gy + 0.5
    cover_1 = np.zeros((th, tw), dtype=np.float32)
    for stand in land.stands:
        if not stand["soil"]:
            continue
        bx0, by0, bx1, by1 = stand["bbox"]
        if bx1 < ox or bx0 > ox + tw or by1 < oy or by0 > oy + th:
            continue
        sm = rasterize_polygon_mask(tw, th, float(ox), float(oy), 1.0, stand["outline"])
        gl_union = np.zeros((th, tw), dtype=bool)
        for gl in stand["glades"]:
            gl_union |= rasterize_polygon_mask(tw, th, float(ox), float(oy), 1.0, gl)
        cover_1[sm & (~gl_union)] = 1.0
        cover_1[sm & gl_union] = np.maximum(cover_1[sm & gl_union], 0.22)
    for tr in land.trees:
        if tr["kind"] != "belt":
            continue
        px_t, py_t = tr["pos"]
        if px_t < ox - 5 or px_t > ox + tw + 5 or py_t < oy - 5 or py_t > oy + th + 5:
            continue
        ix0, ix1 = max(0, int(math.floor(px_t - ox - 4))), min(tw, int(math.ceil(px_t - ox + 5)))
        iy0, iy1 = max(0, int(math.floor(py_t - oy - 4))), min(th, int(math.ceil(py_t - oy + 5)))
        if ix1 <= ix0 or iy1 <= iy0:
            continue
        d = np.hypot(ttx[iy0:iy1, ix0:ix1] - px_t, tty[iy0:iy1, ix0:ix1] - py_t)
        w = 1.0 - smoothstep_np(1.8, 3.4, d)
        cover_1[iy0:iy1, ix0:ix1] = np.maximum(cover_1[iy0:iy1, ix0:ix1], w)
    cover_blur = box_blur_3x3(cover_1, passes=2)
    cover_4 = np.asarray(
        Image.fromarray((np.clip(cover_blur, 0.0, 1.0) * 255.0).astype(np.uint8), mode="L").resize((W, H), Image.Resampling.BILINEAR),
        dtype=np.float32,
    ) * (1.0 / 255.0)
    n_forest = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=101, freq=0.14, octaves=2, sub=4)
    n_forest_macro = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=197, freq=0.032, octaves=2, sub=4)
    forest_w = smoothstep_np(0.40, 0.78, cover_4 + (n_forest * 2.0 - 1.0) * 0.22 + (n_forest_macro * 2.0 - 1.0) * 0.16)

    # 3. Crisp 4x4 Bayer-Dithered Base Biome Terrain (exact map.mjs palette continuity with continent_map.png!)
    bayer_z = bayer_grid(H, W, cell=2, ox=ox * PX_PER_TILE, oy=oy * PX_PER_TILE)
    bayer_z1 = bayer_grid(H, W, cell=1, ox=ox * PX_PER_TILE, oy=oy * PX_PER_TILE)
    z_biome_idx = _biome_index_for_name(f"{z.id} {z.region_id} {' '.join(z.biomes)}")
    base_pal = BIOME_PALETTES[z_biome_idx]
    n_macro = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=277, freq=0.028, octaves=3, sub=4)
    ground_v = np.clip(0.38 + 0.34 * n_macro + 0.24 * n_ground + 0.12 * n_detail - 0.12, 0.0, 1.0)
    rgb = bayer_quantize_ramp(base_pal, ground_v, bayer_z, spread=0.88).copy()

    # Optional baked/surface.png blend if present
    surface_png = feats["baked_dir"] / "surface.png"
    if surface_png.exists():
        sim = Image.open(surface_png).convert("RGBA").resize((W, H), Image.Resampling.BILINEAR)
        sarr = np.asarray(sim, dtype=np.float32) / 255.0
        forest_w = np.clip(np.maximum(forest_w, sarr[..., 1] * 0.65), 0.0, 1.0)

    # Crisp Bayer-dithered biome-aware forest humus & mossy understory (NO blurry gradient smudges)
    moss_noise = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=509, freq=0.22, octaves=2, sub=4)
    if z_biome_idx in (1, 2, 3, 5):
        cp_u = CANOPY_PALETTES[z_biome_idx]
        humus_ramp_z = np.stack([cp_u[0] * 0.78 + INK_PIXEL * 0.22, cp_u[0], cp_u[1] * 0.90], axis=0)
        moss_ramp_z = np.stack([cp_u[0], cp_u[1], cp_u[2] * 0.92], axis=0)
    else:
        humus_ramp_z = HUMUS_RAMP
        moss_ramp_z = MOSS_RAMP
    humus_col = bayer_quantize_ramp(humus_ramp_z, np.clip(0.28 + 0.56 * n_detail, 0.0, 1.0), bayer_z, spread=0.82)
    moss_col = bayer_quantize_ramp(moss_ramp_z, np.clip(0.26 + 0.58 * moss_noise, 0.0, 1.0), bayer_z, spread=0.82)
    forest_floor_m = bayer_z < (forest_w * 0.90)
    if np.any(forest_floor_m):
        pick_moss = bayer_z1[forest_floor_m] < np.clip(0.42 + moss_noise[forest_floor_m] * 0.48, 0.0, 1.0)
        rgb[forest_floor_m] = np.where(pick_moss[..., None], moss_col[forest_floor_m], humus_col[forest_floor_m])

    # Explicit moss ellipses + cliff moss_pockets (Bayer-dithered edge)
    for mx, my, rx, ry in list(land.moss) + list(feats["moss_pockets"]):
        d = np.hypot((tx - mx) / max(rx, 0.5), (ty - my) / max(ry, 0.5)) + (moss_noise - 0.5) * 0.34
        mw = (1.0 - smoothstep_np(0.28, 1.10, d)) * 0.92
        m_hit = bayer_z < mw
        if np.any(m_hit):
            rgb[m_hit] = moss_col[m_hit]

    # Hollows (Bayer-dithered damp earth & dark mud)
    hollow_mask = np.zeros((H, W), dtype=np.float32)
    if land.hollows:
        n_hol = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=887, freq=0.20, octaves=2, sub=4)
        for hx, hy, rx, ry in land.hollows:
            d = np.hypot((tx - hx) / max(rx, 0.5), (ty - hy) / max(ry, 0.5)) + (n_hol - 0.5) * 0.32
            hw = (1.0 - smoothstep_np(0.18, 1.18, d)) * 0.94
            hollow_mask = np.maximum(hollow_mask, hw)
        damp_m = bayer_z < (smoothstep_np(0.36, 0.64, hollow_mask) * 0.85)
        mud_m = bayer_z < (smoothstep_np(0.62, 0.86, hollow_mask) * 0.88)
        rgb[damp_m] = HOLLOW_DAMP
        rgb[mud_m] = HOLLOW_MUD

    # Crisp deterministic pixel-art meadow grass sprigs & wildflowers on sunny grass
    px_i = px_idx.astype(np.int32)
    py_i = py_idx.astype(np.int32)
    m_hash = ((px_i * 73856093) ^ (py_i * 19349663) ^ ((px_i >> 1) * 83492791)) & 0xFF
    sunny_meadow = (forest_w < 0.22) & (hollow_mask < 0.25) & (n_ground > 0.32)
    fl_gold = sunny_meadow & (m_hash == 17) & (n_detail > 0.62) & ((px_i & 1) == 0)
    fl_lav = sunny_meadow & (m_hash == 18) & (n_detail < 0.38) & ((py_i & 1) == 0)
    rgb[fl_gold] = (232.0, 214.0, 142.0)
    rgb[fl_lav] = (198.0, 174.0, 224.0)

    # Elevation field (0..1)
    elev = np.full((H, W), 0.25, dtype=np.float32)
    elev += (n_ground - 0.5) * 0.045
    elev -= hollow_mask * 0.05

    # Optional baked/height.png
    height_png = feats["baked_dir"] / "height.png"
    if height_png.exists():
        him = Image.open(height_png).convert("L").resize((W, H), Image.Resampling.BILINEAR)
        elev = np.clip(0.18 + (np.asarray(him, dtype=np.float32) / 255.0) * 0.65, 0.0, 1.0)

    # Beach sand along explicit shore_pts OR inside "water" borders (Bayer-dithered dry & wet sand lip!)
    shore_wobble = (fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=401, freq=0.18, octaves=2, sub=4) - 0.5) * 2.2
    if feats["coasts"]:
        se_taper = np.where(tx > ox + tw * 0.72, smoothstep_np(0.02, 0.35, w_water), 1.0)
        eff_sand_w = coast_sand_width * se_taper
        d_beach = coast_dist + shore_wobble
        sand_prob = np.where((~coast_sea_mask) & (~headland_mask) & (eff_sand_w > 0.5), 1.0 - smoothstep_np(np.maximum(0.5, eff_sand_w - 2.2), eff_sand_w + 0.6, d_beach), 0.0)
        beach_m = bayer_z < sand_prob
        wet_prob = np.where((~coast_sea_mask) & (~headland_mask) & (se_taper > 0.2), 1.0 - smoothstep_np(0.5, 2.2 * se_taper, d_beach), 0.0)
        wet_beach_m = beach_m & (bayer_z1 < wet_prob)
    else:
        beach_depth = 6.2 * smoothstep_np(0.10, 0.55, w_water)
        d_beach = rim_d + shore_wobble
        sand_prob = np.where(inside & (w_water > 0.15), 1.0 - smoothstep_np(np.maximum(0.5, beach_depth - 2.0), beach_depth + 0.5, d_beach), 0.0)
        beach_m = bayer_z < sand_prob
        wet_prob = np.where(inside & (w_water > 0.20), 1.0 - smoothstep_np(0.5, 2.1 * smoothstep_np(0.15, 0.60, w_water), d_beach), 0.0)
        wet_beach_m = beach_m & (bayer_z1 < wet_prob)
    sand_col = bayer_quantize_ramp(BEACH_DRY, np.clip(0.32 + 0.52 * n_detail + (n_ground - 0.5) * 0.22, 0.0, 1.0), bayer_z, spread=0.84)
    rgb[beach_m] = sand_col[beach_m]
    rgb[wet_beach_m] = BEACH_WET
    elev[beach_m] = np.minimum(elev[beach_m], 0.22 + np.clip(coast_dist[beach_m] / 12.0 if feats["coasts"] else rim_d[beach_m] / 12.0, 0.0, 0.04))

    # Alpha feature mask
    alpha_mask = np.zeros((H, W), dtype=np.uint8)
    alpha_mask[beach_m] |= BIT_SAND_WAY

    # 4. Crisp 3-Tier Pixel-Art Plateaus & Cliffs (exact map.mjs INK contour + NW rim + Bayer SE shadow — ZERO diagonal stripe bugs!)
    rock_blend = np.zeros((H, W), dtype=np.float32)
    cliff_h = np.zeros((H, W), dtype=np.float32)

    if np.any(headland_mask & (~coast_sea_mask)):
        hm = headland_mask & (~coast_sea_mask)
        cliff_h[hm] = np.maximum(cliff_h[hm], 0.36)
        rock_blend[hm] = np.maximum(rock_blend[hm], 0.85)

    # Organic craggy cliff borders (stepped coastal/highland escarpment, never a flat grey ribbon)
    cliff_depth = np.clip(
        5.0 + (n_ground - 0.5) * 7.0 + (n_detail - 0.5) * 3.2 + np.sin(rim_share * 32.0 + n_ground * 4.0) * 1.8,
        2.2,
        12.5,
    )
    cliff_w = smoothstep_np(0.08, 0.68, w_cliff)
    cliff_border_m = (cliff_w > 0.04) & ((inside & (rim_d <= cliff_depth)) | (~inside & (ext_d <= 8.5)))
    if np.any(cliff_border_m):
        rise = np.where(inside, 1.0 - smoothstep_np(0.0, cliff_depth, rim_d), 1.0) * cliff_w
        cliff_h[cliff_border_m] = np.maximum(cliff_h[cliff_border_m], 0.44 * rise[cliff_border_m])
        rock_blend[cliff_border_m] = np.maximum(rock_blend[cliff_border_m], np.clip(rise[cliff_border_m] * 1.15, 0.0, 1.0))

    n_spur_zone: np.ndarray | None = None
    for idx_cl, cl in enumerate(feats["cliffs"]):
        h_add = float(cl.get("height", 0.4))
        if "poly" in cl:
            cm = rasterize_polygon_mask(W, H, float(ox), float(oy), float(PX_PER_TILE), cl["poly"])
            ca = np.array(cl["poly"], dtype=np.float32)
            cb = np.roll(ca, -1, axis=0)
            cd, _ = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), ca, cb, 12.0)
            sd_poly = np.where(cm, cd, -cd) + (n_ground - 0.5) * 8.5 + (n_detail - 0.5) * 2.8
            w_p = smoothstep_np(-1.0, 4.5, sd_poly)
            cliff_h = np.maximum(cliff_h, h_add * 1.35 * w_p)
            rock_blend = np.maximum(rock_blend, smoothstep_np(-0.8, 2.2, sd_poly))
        elif "line" in cl:
            if n_spur_zone is None:
                n_spur_zone = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=701, freq=0.075, octaves=3, sub=2)
            tmp_e = np.full((H, W), 0.25, dtype=np.float32)
            _apply_craggy_ridge(
                W, H, float(ox), float(oy), float(PX_PER_TILE),
                cl["line"], float(cl.get("width", 5.0)), h_add,
                tmp_e, rock_blend, ridge_seed=701 + idx_cl * 53,
                n_spur=n_spur_zone, n_crag=n_detail,
            )
            cliff_h = np.maximum(cliff_h, np.maximum(0.0, tmp_e - 0.25) * 1.45)
        elif "cx" in cl:
            d = (np.abs((tx - cl["cx"]) / max(cl["rx"], 0.5)) ** 2.3 + np.abs((ty - cl["cy"]) / max(cl["ry"], 0.5)) ** 2.3) ** (1.0 / 2.3)
            d += (n_ground - 0.5) * 0.22 + (n_detail - 0.5) * 0.14
            cm = d <= 1.12
            w_c = 1.0 - smoothstep_np(0.15, 1.12, d[cm])
            cliff_h[cm] = np.maximum(cliff_h[cm], h_add * 1.35 * w_c)
            rock_blend[cm] = np.maximum(rock_blend[cm], np.clip(w_c * 1.35, 0.0, 1.0))

    for sf in feats["scree_fans"]:
        d = np.hypot((tx - sf["cx"]) / max(sf["rx"], 0.5), (ty - sf["cy"]) / max(sf["ry"], 0.5)) + (n_detail - 0.5) * 0.24
        sm_f = d <= 1.08
        w_s = 1.0 - smoothstep_np(0.2, 1.08, d[sm_f])
        cliff_h[sm_f] = np.maximum(cliff_h[sm_f], 0.22 * sf["strength"] * w_s)
        rock_blend[sm_f] = np.maximum(rock_blend[sm_f], w_s * 0.72)

    # Build clean 3-channel blurred plateau field `z_field` (H, W, 3) from local cliffs AND/OR continental_field.png
    z_field = np.zeros((H, W, 3), dtype=np.float32)
    has_local_cliffs = bool(np.any(cliff_h > 0.14))
    if has_local_cliffs:
        for k, th_v in enumerate((0.18, 0.36, 0.56)):
            m_k = cliff_h >= th_v
            if np.any(m_k):
                z_field[..., k] = box_blur_sep(m_k.astype(np.float32), r=3, passes=3)
    if not feats["cliffs"]:
        # Always inherit true continental plateaus seamlessly for zones without hand-authored interior cliff polygons!
        c_fld_path = cont.world_dir / "continents" / "baked" / cont.id / "continental_field.png"
        if c_fld_path.exists():
            cf_im = Image.open(c_fld_path).convert("RGB")
            cw_f, ch_f = cf_im.size
            cx0 = max(0, min(cw_f - 1, ox))
            cy0 = max(0, min(ch_f - 1, oy))
            cx1 = max(cx0 + 1, min(cw_f, ox + tw))
            cy1 = max(cy0 + 1, min(ch_f, oy + th))
            crop = cf_im.crop((cx0, cy0, cx1, cy1)).resize((W, H), Image.Resampling.BILINEAR)
            c_field = np.asarray(crop, dtype=np.float32) * (1.0 / 255.0)
            z_field = np.maximum(z_field, c_field)
    z_lvl = ((z_field[..., 0] > 0.5).astype(np.uint8) + (z_field[..., 1] > 0.5).astype(np.uint8) + (z_field[..., 2] > 0.5).astype(np.uint8))

    if np.any(z_field > 0.02) or np.any(rock_blend > 0.08):
        zh = z_field[..., 0] + z_field[..., 1] + z_field[..., 2]
        elev = np.clip(elev + zh * 0.16, 0.0, 0.98)

        # Bayer-dithered bedrock slate on rocky plateau tops & crags (tier 1 mixes coastal moss turf + stone; tier 2-3 rugged slate)
        rock_t = np.clip(0.14 + zh * 0.28 + (n_detail - 0.5) * 0.24 + (n_ground - 0.5) * 0.16, 0.0, 1.0)
        rock_col = bayer_quantize_ramp(BEDROCK_RAMP, rock_t, bayer_z, spread=0.84)
        # Wind-scoured moss pockets & turf patches on rocky lower shelves so plateaus look hand-crafted, not flat grey slabs
        crevice_m = (rock_blend > 0.20) & (zh < 1.85) & ((n_detail * 0.55 + n_ground * 0.45) > 0.58)
        if np.any(crevice_m):
            rock_col[crevice_m] = moss_col[crevice_m]
        # Darken outer cliff-border frame slightly so zone boundaries read as rugged shaded highland rim
        outer_crag = (~inside) & cliff_border_m
        if np.any(outer_crag):
            rock_col[outer_crag] = rock_col[outer_crag] * 0.66 + INK_PIXEL * 0.34
        # Blend bedrock onto plateau / rocky pixels via crisp Bayer transition (no grey airbrush fringe)
        eff_rock = np.maximum(rock_blend, np.where((z_biome_idx in (1, 5)) & (zh > 1.4), smoothstep_np(1.3, 2.2, zh), 0.0))
        rock_hit = (eff_rock > 0.08) & (bayer_z < eff_rock * 0.94)
        if np.any(rock_hit):
            rgb[rock_hit] = rock_col[rock_hit]
            alpha_mask[rock_hit] |= BIT_SAND_WAY

        # Exact map.mjs razor-sharp INK cliff contours, NW sunlit lip, Bayer SE cast shadow & 2-tile south cliff faces!
        ps_z = 2
        fp_x = np.pad(z_field, ((0, 0), (1, ps_z - 1), (0, 0)), mode="edge")
        fp_y = np.pad(z_field, ((1, ps_z - 1), (0, 0), (0, 0)), mode="edge")
        dz_x = fp_x[:, ps_z:, :] - fp_x[:, :-ps_z, :]
        dz_y = fp_y[ps_z:, :, :] - fp_y[:-ps_z, :, :]
        best_zc = np.full((H, W), 99.0, dtype=np.float32)
        side_zc = np.zeros((H, W), dtype=np.float32)
        for k in range(3):
            c_v = z_field[..., k] - 0.5 + (n_detail - 0.5) * 0.08
            g_k = np.maximum(np.hypot(dz_x[..., k], dz_y[..., k]), 0.0045)
            d_k = np.abs(c_v) / g_k
            bt = d_k < best_zc
            best_zc = np.where(bt, d_k, best_zc)
            side_zc = np.where(bt, c_v, side_zc)

        # South-facing 2-tile (8px) vertical cliff face beneath southern plateau ledges
        south_face = np.zeros((H, W), dtype=bool)
        for dy_f in range(1, 8):
            ab = np.zeros_like(z_lvl)
            ab[dy_f:] = z_lvl[:-dy_f]
            south_face |= ab > z_lvl
        if np.any(south_face):
            # Shaded vertical slate wall face with crisp Bayer rock texture (ZERO diagonal stripe bug!)
            face_col = bayer_quantize_ramp(BEDROCK_RAMP[:2], np.clip(0.25 + n_detail * 0.55, 0.0, 1.0), bayer_z1, spread=0.80)
            rgb[south_face] = face_col[south_face] * 0.72 + INK_PIXEL * 0.28
            alpha_mask[south_face] |= BIT_INK_CLIFF

        z_band = 5.2
        z_sh = (side_zc < 0.0) & (best_zc < z_band) & (bayer_z < (1.0 - best_zc / z_band) * 0.86)
        z_hi = (side_zc > 0.0) & (best_zc < 2.0) & (~south_face)
        z_ink = best_zc < 0.86
        rgb[z_sh] = rgb[z_sh] * 0.34 + INK_PIXEL * 0.66
        rgb[z_hi] = rgb[z_hi] * 0.45 + np.where(rock_hit[z_hi, None], np.array([186.0, 198.0, 194.0], dtype=np.float32), base_pal[2]) * 0.55
        rgb[z_ink] = INK_PIXEL
        alpha_mask[z_ink] |= BIT_INK_CLIFF

    # 5. Water Rendering (ocean, surf, reefs, brooks, pools, lakes, puddles, fords, bridges)
    water_depth = np.zeros((H, W), dtype=np.float32)
    water_regime = np.zeros((H, W), dtype=np.uint8)  # 0=none, 1=brook, 2=lake, 3=surf, 4=ocean, 5=puddle

    # Optional baked/water.png
    water_png = feats["baked_dir"] / "water.png"
    if water_png.exists():
        wim = Image.open(water_png).convert("RGBA").resize((W, H), Image.Resampling.BILINEAR)
        warr = np.asarray(wim, dtype=np.float32) / 255.0
        has_w = warr[..., 0] > 0.03
        water_depth[has_w] = warr[has_w, 0]
        water_regime[has_w] = 2

    # Coastal ocean + surf from explicit coastline OR "water" borders
    if feats["coasts"]:
        sd = coast_dist + shore_wobble * 0.65
        surf_m = coast_sea_mask & (sd <= 14.0)
        ocean_m = coast_sea_mask & (sd > 14.0)
        water_regime[surf_m] = 3
        water_depth[surf_m] = np.maximum(water_depth[surf_m], np.clip(0.06 + smoothstep_np(0.0, 14.0, sd[surf_m]) * 0.40, 0.05, 0.46))
        water_regime[ocean_m] = 4
        water_depth[ocean_m] = np.maximum(water_depth[ocean_m], np.clip(0.47 + smoothstep_np(14.0, 42.0, sd[ocean_m]) * 0.53, 0.47, 1.0))
    else:
        sea_ext = (~inside) & is_water_border
        if np.any(sea_ext):
            sd = ext_d + shore_wobble * 0.85
            surf_m = sea_ext & (sd <= 14.0)
            ocean_m = sea_ext & (sd > 14.0)
            water_regime[surf_m] = 3
            water_depth[surf_m] = np.clip(0.08 + smoothstep_np(0.0, 14.0, sd[surf_m]) * 0.38, 0.05, 0.46)
            water_regime[ocean_m] = 4
            water_depth[ocean_m] = np.clip(0.47 + smoothstep_np(14.0, 42.0, sd[ocean_m]) * 0.53, 0.47, 1.0)

    # Broken submerged coastal reef shoals & wave foam streaks (never smooth ovals)
    reef_shoal_m = np.zeros((H, W), dtype=bool)
    reef_foam_m = np.zeros((H, W), dtype=bool)
    if feats["reefs"]:
        n_reef = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=733, freq=0.35, octaves=3, sub=2)
        wave_streak = np.sin(tx * 0.42 + ty * 0.85 + n_reef * 5.2) * 0.5 + 0.5
        for rf in feats["reefs"]:
            rel = np.hypot((tx - rf["cx"]) / max(rf["rx"], 0.5), (ty - rf["cy"]) / max(rf["ry"], 0.5))
            rel_wob = rel + (n_reef - 0.5) * 0.68 + (n_detail - 0.5) * 0.24
            shoal = (rel_wob <= 0.92) & (n_reef > 0.48) & (water_regime >= 3) & (water_depth < 0.66)
            water_depth[shoal] = np.maximum(0.22, water_depth[shoal] - 0.14 * (1.0 - np.clip(rel_wob[shoal], 0.0, 1.0)))
            reef_shoal_m |= shoal & (n_reef > 0.54)
            reef_foam_m |= shoal & (wave_streak > 0.78) & (n_reef > 0.60)

    # Brooks / Rivers (dense Catmull-Rom + biome-matched riparian collar, pebbles & seamless sea estuaries)
    sea_mask_any = coast_sea_mask if feats["coasts"] else ((~inside) & is_water_border)
    sea_dist_t = coast_dist if feats["coasts"] else np.where(w_water > 0.12, rim_d, 999.0)
    rip_collar = (
        CANOPY_PALETTES[z_biome_idx, 0] * 0.72 + INK_PIXEL * 0.28
        if z_biome_idx in (1, 2, 3, 5)
        else RIPARIAN_COLLAR
    )
    brook_bank_pebbles = np.zeros((H, W), dtype=bool)
    brook_min_sdf = np.full((H, W), 99.0, dtype=np.float32)
    for br in feats["brooks"]:
        pts3 = br["pts"]
        sm_xy = subdivide_catmull([(p[0], p[1]) for p in pts3], subdiv=12)
        radii_ctrl = [p[2] for p in pts3]
        sm_r = np.interp(np.linspace(0, len(radii_ctrl) - 1, len(sm_xy)), np.arange(len(radii_ctrl)), radii_ctrl)
        sa = np.array(sm_xy[:-1], dtype=np.float32)
        sb = np.array(sm_xy[1:], dtype=np.float32)
        seg_r = np.stack([sm_r[:-1], sm_r[1:]], axis=1).astype(np.float32)
        max_r = float(np.max(sm_r)) + 2.2
        best_sdf, best_r = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), sa, sb, max_r, seg_radii=seg_r)
        assert best_r is not None
        wob = (fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=br["seed"], freq=0.45, octaves=2, sub=1) - 0.5) * 0.85
        sdf_w = best_sdf + wob
        brook_min_sdf = np.minimum(brook_min_sdf, sdf_w)
        not_mouth = sea_dist_t >= 4.2
        bank_m = (sdf_w > 0.0) & (sdf_w <= 1.25) & (water_regime == 0) & not_mouth & (~beach_m)
        rgb[bank_m] = rgb[bank_m] * 0.48 + rip_collar * 0.52
        peb_m = (sdf_w > 0.0) & (sdf_w <= 0.85) & (water_regime == 0) & not_mouth & (~beach_m) & ((m_hash % 11) < 2)
        brook_bank_pebbles |= peb_m
        in_b = (sdf_w <= 0.0) & (~sea_mask_any)
        bd = np.power(np.clip(-sdf_w / np.maximum(best_r, 0.5), 0.0, 1.0), 0.72) * 0.76
        water_depth[in_b] = np.maximum(water_depth[in_b], bd[in_b])
        water_regime[in_b] = np.where(water_regime[in_b] == 0, 1, water_regime[in_b])
        for px_p, py_p, pr_p in br.get("pools") or []:
            wob_p = (n_detail - 0.5) * 2.4 + (n_ground - 0.5) * 1.8
            d_p = np.hypot(tx - px_p, ty - py_p) + wob_p
            bank_p = (d_p > pr_p) & (d_p <= pr_p + 1.4) & (water_regime == 0)
            rgb[bank_p] = rgb[bank_p] * 0.48 + rip_collar * 0.52
            pm = (d_p <= pr_p) & (~sea_mask_any)
            pd_v = 0.42 + (1.0 - np.clip(d_p / max(pr_p, 0.5), 0.0, 1.0)) * 0.30
            water_depth[pm] = np.maximum(water_depth[pm], pd_v[pm])
            water_regime[pm] = np.where(water_regime[pm] == 0, 1, water_regime[pm])
    if np.any(brook_bank_pebbles):
        rgb[brook_bank_pebbles] = (126.0, 140.0, 144.0)

    # Lakes & Puddles (lakes always win over brooks so rivers never slice across dark lake basins!)
    for lk in feats["lakes"]:
        if "poly" in lk:
            lm = rasterize_polygon_mask(W, H, float(ox), float(oy), float(PX_PER_TILE), lk["poly"])
            la = np.array(lk["poly"], dtype=np.float32)
            lb = np.roll(la, -1, axis=0)
            ld, _ = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), la, lb, 6.5)
            d_norm = np.clip(ld / 6.0, 0.0, 1.0)
            water_depth[lm] = np.maximum(water_depth[lm], 0.25 + d_norm[lm] * 0.65)
            water_regime[lm] = np.where((water_regime[lm] == 0) | (water_regime[lm] == 1), 2, water_regime[lm])
        else:
            rel = np.hypot((tx - lk["cx"]) / max(lk["rx"], 0.5), (ty - lk["cy"]) / max(lk["ry"], 0.5))
            rel += (n_detail - 0.5) * 0.14
            lm = rel <= 1.0
            water_depth[lm] = np.maximum(water_depth[lm], np.power(np.clip(1.0 - rel[lm], 0.0, 1.0), 0.7) * 0.88)
            water_regime[lm] = np.where((water_regime[lm] == 0) | (water_regime[lm] == 1), 2, water_regime[lm])

    for pd in feats["puddles"]:
        rel = np.hypot((tx - pd["cx"]) / max(pd["rx"], 0.5), (ty - pd["cy"]) / max(pd["ry"], 0.5))
        rel += (n_detail - 0.5) * 0.34 + (n_ground - 0.5) * 0.18
        pm = rel <= 1.0
        water_depth[pm] = np.maximum(water_depth[pm], 0.24)
        water_regime[pm] = np.where(water_regime[pm] == 0, 5, water_regime[pm])
    # Small hollow central puddles (organic damp pools, no hard circular discs)
    hol_puddle = (hollow_mask + (n_detail - 0.5) * 0.14) > 0.86
    water_depth[hol_puddle] = np.maximum(water_depth[hol_puddle], 0.22)
    water_regime[hol_puddle] = np.where(water_regime[hol_puddle] == 0, 5, water_regime[hol_puddle])

    # Color water regimes in unified ocean-matched crisp Bayer pixel art (NO thick lake rims, NO hard estuary seams!)
    any_water = water_regime > 0
    if np.any(any_water):
        m_ocean = water_regime == 4
        m_surf = water_regime == 3
        m_lake = water_regime == 2
        m_brook = (water_regime == 1) | (water_regime == 5)
        m_sea_all = m_ocean | m_surf
        # Shared ocean-matched Bayer water ramps (lakes & brooks use the EXACT same deep sapphire-teal water as the sea!)
        sea_pal_z = np.stack([SURF_SWASH, SURF_LAGOON, OCEAN4, OCEAN3, OCEAN2, OCEAN1], axis=0)
        zone_lake_pal = np.stack([OCEAN_RIDGE, OCEAN4, OCEAN3, OCEAN2, OCEAN1], axis=0)
        zone_brook_pal = np.stack([RIPPLE_TINT, OCEAN_RIDGE, OCEAN4, OCEAN3, OCEAN2], axis=0)

        # Unified distance from ANY water pixel to dry land -> stays high across river-lake & river-sea junctions!
        water_to_dry_px = _fast_mask_boundary_distance(~any_water, factor=2)
        water_to_dry_t = water_to_dry_px / float(PX_PER_TILE)

        # Gentle estuarine shallow plume where a brook opens into the coastal surf
        mouth_open = (brook_min_sdf <= 1.25) & (sea_dist_t < 4.8)
        if np.any(m_sea_all):
            t_sea = np.clip(water_depth + (n_ground - 0.5) * 0.08, 0.0, 1.0)
            estuary_sea = m_sea_all & (brook_min_sdf <= 2.8) & (sea_dist_t < 6.0)
            if np.any(estuary_sea):
                e_pull = (1.0 - smoothstep_np(0.0, 6.0, sea_dist_t[estuary_sea])) * (1.0 - smoothstep_np(0.0, 2.8, np.maximum(0.0, brook_min_sdf[estuary_sea])))
                t_sea[estuary_sea] = np.maximum(0.06, t_sea[estuary_sea] * (1.0 - e_pull * 0.30))
            rgb[m_sea_all] = bayer_quantize_ramp(sea_pal_z, t_sea[m_sea_all], bayer_z[m_sea_all], spread=0.86)
            # Three delicate undulating cartographer shore wave ripples in coastal surf
            sd_z = coast_dist if feats["coasts"] else ext_d
            w_ph = np.sin(tx * 0.32 + ty * 0.24) * 0.45
            rip_z = np.abs(((sd_z - 2.4 + w_ph) / 4.2 + 0.5) % 1.0 - 0.5) * 4.2
            rip_zm = m_sea_all & (sd_z > 1.8) & (sd_z < 16.5) & (rip_z < 0.48) & ((((px_i // 2) + (py_i // 2)) % 3) < 2)
            if np.any(rip_zm):
                rw_z = (0.58 * (1.0 - (sd_z[rip_zm] - 1.8) / 15.0))[..., None]
                rgb[rip_zm] = rgb[rip_zm] * (1.0 - rw_z) + COAST_RIM * rw_z

        if np.any(m_lake):
            # Deep ocean-matched Bayer bathymetry + organic warped ocean swell + subtle currents + crisp wave crests (NO bright sticker ring!)
            n_lsw = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=317, freq=0.048, octaves=3, sub=4)
            n_lrdg = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=331, freq=0.10, octaves=2, sub=4)
            bath_l = smoothstep_np(0.4, 14.0, water_to_dry_t)
            t_l = np.clip(0.14 + bath_l * 0.78 + (n_lsw - 0.5) * 0.34 + (n_detail - 0.5) * 0.08, 0.0, 1.0)
            water_depth[m_lake] = np.clip(0.16 + bath_l[m_lake] * 0.74, 0.16, 0.90)
            rgb[m_lake] = bayer_quantize_ramp(zone_lake_pal, t_l[m_lake], bayer_z[m_lake], spread=0.86)
            # Subtle Bayer ocean-ridge swell filaments inside open lake water
            l_rdg = m_lake & (water_to_dry_t > 3.5) & (np.abs(n_lrdg - 0.5) < 0.040) & (n_lsw > 0.44) & (bayer_z1 < 0.54)
            if np.any(l_rdg):
                rgb[l_rdg] = rgb[l_rdg] * 0.66 + OCEAN_RIDGE * 0.34
            # Crisp 2px pixel wave crests on open lake basins (restrained RIPPLE_TINT matching ocean!)
            _stamp_wave_marks(
                rgb,
                m_lake,
                water_to_dry_px,
                W,
                H,
                spacing=48,
                min_inset=5.5 * float(PX_PER_TILE),
                light_col=RIPPLE_TINT,
                alpha_crest=0.42,
                alpha_echo=0.20,
                px_size=2,
                seed=241,
            )

        if np.any(m_brook):
            # Deep ocean-matched Bayer sapphire-teal flowing streams with current threads & seamless estuaries!
            n_flow = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=607, freq=0.16, octaves=2, sub=2)
            # Smoothly lighten only right where the estuary merges into sandy beach surf
            mouth_pull = np.where(water_regime == 1, 1.0 - smoothstep_np(0.0, 5.5, sea_dist_t), 0.0)
            t_b = np.clip(
                0.24 + (water_depth / 0.76) * 0.68 + (n_flow - 0.5) * 0.22 + (n_detail - 0.5) * 0.08 - mouth_pull * 0.42,
                0.0,
                1.0,
            )
            rgb[m_brook] = bayer_quantize_ramp(zone_brook_pal, t_b[m_brook], bayer_z[m_brook], spread=0.84)
            # Subtle turquoise current streaks along channel center & crisp 1px pixel riffles
            curr_m = (water_regime == 1) & (np.abs(n_flow - 0.5) < 0.048) & (bayer_z1 < 0.48)
            if np.any(curr_m):
                rgb[curr_m] = rgb[curr_m] * 0.66 + RIPPLE_TINT * 0.34
            riffle = m_brook & (water_depth < 0.40) & ((m_hash % 29) == 0)
            rgb[riffle] = rgb[riffle] * 0.52 + LAKE_LIGHT * 0.48

        if np.any(reef_shoal_m):
            rgb[reef_shoal_m] = rgb[reef_shoal_m] * 0.72 + np.array((26.0, 68.0, 74.0), dtype=np.float32) * 0.28
        if np.any(reef_foam_m):
            rgb[reef_foam_m] = rgb[reef_foam_m] * 0.45 + COAST_RIM * 0.55

        # Natural stepping-stone fords (Bayer-dithered shallow gravel riffle + discrete stone steppers, NO flat grey patch!)
        for fx_p, fy_p, fr_p in feats["fords"]:
            fd = np.hypot(tx - fx_p, ty - fy_p) + (n_detail - 0.5) * 1.6
            f_prob = np.where(any_water, 1.0 - smoothstep_np(fr_p * 0.25, fr_p * 0.95, fd), 0.0)
            fm = any_water & (bayer_z1 < f_prob * 0.72)
            rgb[fm] = rgb[fm] * 0.52 + LAKE_SHELF * 0.48
            # Stepping stones across the ford
            step_st = any_water & (fd <= fr_p * 0.80) & (((px_i % 6) < 2) & ((py_i % 5) < 2)) & (n_detail > 0.48)
            rgb[step_st] = FORD_SHINGLE
            water_depth[fm] = np.minimum(water_depth[fm], 0.24)

        elev[any_water] = np.clip(0.22 - water_depth[any_water] * 0.18, 0.02, 0.22)
        alpha_mask[any_water] |= np.uint8(BIT_WATER)
        alpha_mask[any_water] &= np.uint8(255 ^ BIT_SAND_WAY)

        # Crisp luminous surf foam on ocean beach + delicate 1px recessed NW shadow / whisper-thin SE lip on lakes & brooks!
        padded_w = np.pad(any_water, 1, mode="edge")
        edge_n = any_water & (~padded_w[:-2, 1:-1])
        edge_s = any_water & (~padded_w[2:, 1:-1])
        edge_w = any_water & (~padded_w[1:-1, :-2])
        edge_e = any_water & (~padded_w[1:-1, 2:])
        shore_edge = edge_n | edge_s | edge_w | edge_e
        padded_w2 = np.pad(any_water, 2, mode="edge")
        rim_2px = any_water & (
            (~padded_w2[:-4, 2:-2]) | (~padded_w2[4:, 2:-2]) | (~padded_w2[2:-2, :-4]) | (~padded_w2[2:-2, 4:])
        )
        # Luminous coastal surf foam (breaks open seamlessly across river mouths!)
        surf_foam = (water_regime == 3) & rim_2px & (shore_edge | (bayer_z1 < 0.55)) & (~mouth_open)
        # Fine 1px natural bank on lakes & brooks (automatically absent across river-lake & river-sea junctions!)
        inland_edge = shore_edge & (water_regime != 3) & (water_regime != 4) & (water_regime != 5) & (~mouth_open)
        nw_recess_z = inland_edge & (edge_n | edge_w)
        se_lip_z = inland_edge & (edge_s | edge_e) & (~nw_recess_z)
        rgb[surf_foam] = COAST_RIM
        rgb[nw_recess_z] = rgb[nw_recess_z] * 0.45 + INK_PIXEL * 0.55
        rgb[se_lip_z] = rgb[se_lip_z] * 0.58 + RIPPLE_TINT * 0.42

    # 6. Ranked Ways (curved pixel-art footpaths with Bayer-dithered verges & warm worn earth center)
    for w_idx, w in enumerate(feats["ways"]):
        wkind = w["kind"].lower()
        style = WAY_STYLES.get(wkind, WAY_STYLES["trail"])
        amp_w = 1.65 if wkind == "quarry_trail" else (1.28 if wkind in ("trail", "footpath", "path") else 0.65)
        freq_w = 0.085 if wkind == "quarry_trail" else 0.055
        subdiv_w = 14
        if len(w["pts"]) == 2:
            seg_len = math.hypot(w["pts"][1][0] - w["pts"][0][0], w["pts"][1][1] - w["pts"][0][1])
            if seg_len > 60.0:
                amp_w = max(amp_w, min(14.0, seg_len * 0.045))
                freq_w = 5.2 / max(seg_len, 80.0)
                subdiv_w = max(20, min(64, int(seg_len / 6.0)))
        sm = _meander_polyline(w["pts"], seed=int(w.get("seed", 17)) + w_idx * 31, amp=amp_w, freq=freq_w, subdiv=subdiv_w)
        if len(sm) < 2:
            continue
        wx0, wy0, wx1, wy1 = bbox_of(sm)
        if wx1 < ox - 4 or wx0 > ox + tw + 4 or wy1 < oy - 4 or wy0 > oy + th + 4:
            continue
        sa = np.array(sm[:-1], dtype=np.float32)
        sb = np.array(sm[1:], dtype=np.float32)
        half = style["half_px"]
        wd_tiles, _ = fast_narrowband_segments_distance(
            W, H, float(ox), float(oy), float(PX_PER_TILE), sa, sb, (half + 3.0) / float(PX_PER_TILE)
        )
        wd_px = wd_tiles * PX_PER_TILE
        half_v = half * (0.86 + 0.26 * n_detail)
        verge_m = (wd_px <= half_v + 1.8) & (wd_px > half_v + 0.4) & (~any_water) & (bayer_z1 < 0.45)
        edge_m = (wd_px <= half_v + 0.5) & (wd_px > half_v * 0.74) & (~any_water)
        core_m = (wd_px <= half_v * 0.86) & (~any_water)
        if style.get("dashed"):
            dash_wave = (((px_i * 3 + py_i * 5) // 4) & 1) == 0
            stip = (n_detail > 0.42) & (n_ground > 0.20) & (dash_wave | (n_detail > 0.60))
            core_m &= stip
            edge_m &= (n_detail > 0.50) & dash_wave
            verge_m &= n_detail > 0.55
        mid_c = np.array(style.get("mid", style["core"]), dtype=np.float32)
        core_c = np.array(style["core"], dtype=np.float32)
        edge_c = np.array(style["edge"], dtype=np.float32)
        if wkind == "quarry_trail":
            rgb[core_m] = core_c
            rgb[edge_m] = edge_c
        else:
            rgb[verge_m] = rgb[verge_m] * 0.48 + edge_c * 0.52
            rgb[edge_m] = edge_c
            rgb[core_m] = np.where((bayer_z1[core_m] < (0.45 + 0.40 * n_detail[core_m]))[..., None], core_c, mid_c)
        if "rut" in style:
            rut_m = (np.abs(wd_px - half_v * 0.50) <= 0.45) & (~any_water)
            rgb[rut_m] = style["rut"]
        way_all = core_m | edge_m
        alpha_mask[way_all] |= np.uint8(BIT_SAND_WAY)
        alpha_mask[way_all] &= np.uint8(255 ^ BIT_MEADOW)

    # 7. Hand-Crafted Top-Down Pixel-Art Stone Arch Bridges (cambered arch, flared wing-walls, voussoirs, parapets, Bayer water shadow)
    for brg in feats["bridges"]:
        bx, by = (brg["pos"][0] - ox) * PX_PER_TILE, (brg["pos"][1] - oy) * PX_PER_TILE
        bl = max(brg["length"], 10.0) * PX_PER_TILE * 0.5
        bw = max(brg["width"], 3.0) * PX_PER_TILE * 0.5
        ang = brg["angle"]
        ca, sa_ang = math.cos(ang), math.sin(ang)
        dx_b = (px_idx + 0.5) - bx
        dy_b = (py_idx + 0.5) - by
        u = dx_b * ca + dy_b * sa_ang
        v = -dx_b * sa_ang + dy_b * ca
        u_norm = np.clip(u / max(bl * 0.72, 1.0), -1.0, 1.0)
        camber = -1.85 * np.maximum(0.0, 1.0 - u_norm * u_norm)
        vc = v - camber
        end_flare = np.clip((np.abs(u) - bl * 0.66) / max(bl * 0.34, 1.0), 0.0, 1.0)
        eff_bw = bw * (1.0 + 0.52 * end_flare)
        deck_all = (np.abs(u) <= bl) & (np.abs(vc) <= eff_bw)
        abut = deck_all & (np.abs(u) >= bl * 0.66)
        span = deck_all & (~abut)
        parapet = deck_all & (np.abs(vc) >= eff_bw - 1.55)
        parapet_nw = parapet & (vc < 0.0)
        parapet_se = parapet & (vc >= 0.0)
        arch_face = (np.abs(u) <= bl * 0.66) & (vc > eff_bw - 0.1) & (vc <= eff_bw + 1.85)
        pier = deck_all & (
            ((np.abs(np.abs(u) - bl * 0.66) <= 1.35) | (np.abs(np.abs(u) - bl * 0.96) <= 1.15))
            & (np.abs(vc) >= eff_bw - 2.3)
        )
        # Crisp Bayer-dithered curved arch shadow cast SE over brook water beneath the span
        shad = (np.abs(u - 2.0) <= bl * 0.88) & (np.abs((v - camber * 0.6) - 3.2) <= eff_bw * 0.96) & (~deck_all) & (~arch_face) & (bayer_z1 < 0.82)
        rgb[shad] = rgb[shad] * 0.34 + INK_PIXEL * 0.66
        stone_tile = ((np.floor(u / 3.0).astype(np.int32) + np.floor(vc / 2.2).astype(np.int32)) & 1) == 0
        joint_line = ((np.abs(u % 3.0) < 0.45) | (np.abs(vc) < 0.35)) & span & (~parapet)
        rgb[span] = np.where(stone_tile[span, None], (158.0, 166.0, 168.0), (134.0, 144.0, 150.0))
        rgb[abut] = (112.0, 122.0, 130.0)
        rgb[span & (np.abs(vc) <= bw * 0.38)] = (182.0, 188.0, 186.0)
        rgb[joint_line] = (86.0, 96.0, 106.0)
        rgb[parapet_nw] = (194.0, 202.0, 198.0)
        rgb[parapet_se] = (78.0, 86.0, 102.0)
        voussoir_alt = (np.floor(u / 2.2).astype(np.int32) & 1) == 0
        rgb[arch_face] = np.where(voussoir_alt[arch_face, None], (112.0, 120.0, 130.0), (70.0, 78.0, 96.0))
        rgb[pier] = (204.0, 210.0, 204.0)
        br_body = deck_all | arch_face
        pad_br = np.pad(br_body, 1, mode="constant", constant_values=False)
        br_rim = br_body & ((~pad_br[:-2, 1:-1]) | (~pad_br[2:, 1:-1]) | (~pad_br[1:-1, :-2]) | (~pad_br[1:-1, 2:]))
        rgb[br_rim] = INK_PIXEL
        alpha_mask[br_body] &= np.uint8(255 ^ BIT_WATER)
        alpha_mask[br_body] |= np.uint8(BIT_SAND_WAY)
        alpha_mask[parapet | pier | br_rim | abut | arch_face] |= np.uint8(BIT_INK_CLIFF)
        elev[br_body] = np.maximum(elev[br_body], 0.42 + np.maximum(0.0, 1.0 - u_norm * u_norm)[br_body] * 0.08)

    # 8. Compute Terrain Normals for live SunShadows in map_light.png (keep baked Bayer colors crisp!)
    elev_smooth = box_blur_3x3(elev, passes=1)
    gy, gx = np.gradient(elev_smooth)
    strength = 18.0
    nx_f = -gx * strength
    ny_f = -gy * strength
    n_len = np.sqrt(nx_f * nx_f + ny_f * ny_f + 1.0)
    nx_arr = nx_f / n_len
    ny_arr = ny_f / n_len

    # Abyss / void_edge borders (strictly no green BIT_MEADOW outside void_edge/abyss; rift fissures restricted when explicit great_rift exists)
    abyss_m = ((border_kind_grid == 3) | (w_abyss > 0.42)) & (~inside) & (ext_d <= VOID_BAKE_MARGIN)
    rgb[abyss_m] = INK_DEEP
    alpha_mask[abyss_m] |= BIT_INK_CLIFF
    alpha_mask[abyss_m] &= np.uint8(255 ^ BIT_MEADOW)

    void_base_m = ((border_kind_grid == 4) | (w_void > 0.42)) & (
        ((~inside) & (ext_d <= VOID_BAKE_MARGIN)) | (inside & (rim_d <= 3.2))
    )
    if np.any(void_base_m):
        if cont.has_explicit_rift:
            rift_pos_c, rift_rad_c, rift_edge_c = _detect_great_rift(cont)
            near_rift = np.zeros((H, W), dtype=bool)
            if rift_pos_c is not None:
                near_rift |= np.hypot(tx - rift_pos_c[0], ty - rift_pos_c[1]) <= max(rift_rad_c * 1.45, 95.0)
            if len(rift_edge_c) >= 2:
                rx0, ry0, rx1, ry1 = bbox_of(rift_edge_c)
                if not (rx1 < ox - 45 or rx0 > ox + tw + 45 or ry1 < oy - 45 or ry0 > oy + th + 45):
                    sa_r = np.array(rift_edge_c[:-1], dtype=np.float32)
                    sb_r = np.array(rift_edge_c[1:], dtype=np.float32)
                    rd_r, _ = fast_narrowband_segments_distance(W, H, float(ox), float(oy), float(PX_PER_TILE), sa_r, sb_r, 42.0)
                    near_rift |= rd_r <= 36.0
            void_m = void_base_m & near_rift & (~other_inside)
        else:
            void_m = void_base_m & (~other_inside)
        if np.any(void_m):
            n_void = fbm2d_grid(W, H, float(ox), float(oy), float(PX_PER_TILE), seed=991, freq=0.65, octaves=2, sub=2)
            cracks = void_m & (n_void > 0.56)
            rgb[void_m] = (52, 24, 94)
            rgb[cracks] = (255, 79, 216)
            alpha_mask[void_m] |= BIT_INK_CLIFF
            alpha_mask[void_m] &= np.uint8(255 ^ BIT_MEADOW)
            alpha_mask[cracks] |= BIT_GLOW_ARCANE

    # Pre-stamp Bayer-dithered coastal camp clearing into rgb before crisp PIL pixel-art props
    for cp in feats["camps"]:
        cx_c = (cp["pos"][0] - ox) * PX_PER_TILE
        cy_c = (cp["pos"][1] - oy) * PX_PER_TILE
        d_cl = np.hypot((px_idx - cx_c) / 17.0, (py_idx - cy_c) / 13.5) + (n_detail - 0.5) * 0.25
        cl_out = (d_cl <= 1.05) & (~any_water) & (bayer_z1 < (1.0 - smoothstep_np(0.55, 1.05, d_cl)) * 0.92)
        cl_in = (d_cl <= 0.62) & (~any_water) & (bayer_z1 < 0.85)
        rgb[cl_out] = (146.0, 126.0, 96.0)
        rgb[cl_in] = (174.0, 152.0, 114.0)
        alpha_mask[cl_out] |= np.uint8(BIT_SAND_WAY)

    # 9. Detailed Landmarks: Faceted Rocks, Blockers, Ruins/Lighthouse/Tablet/Waystone/Vista, Coastal Camps, Roofs
    pil_rgb = Image.fromarray(np.clip(rgb, 1, 255).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(pil_rgb)

    def _stamp_elev_ink(x_c: float, y_c: float, rx_i: float, ry_i: float, h_v: float = 0.44, glow_bit: int = 0) -> None:
        ix0, iy0 = max(0, int(math.floor(x_c - rx_i))), max(0, int(math.floor(y_c - ry_i)))
        ix1, iy1 = min(W, int(math.ceil(x_c + rx_i)) + 1), min(H, int(math.ceil(y_c + ry_i)) + 1)
        if ix1 > ix0 and iy1 > iy0:
            elev[iy0:iy1, ix0:ix1] = np.maximum(elev[iy0:iy1, ix0:ix1], h_v)
            alpha_mask[iy0:iy1, ix0:ix1] |= np.uint8(BIT_INK_CLIFF | glow_bit)

    # Faceted boulder clusters (angular crag polygon + SE shadow + NW highlight facet)
    for idx_rk, rk in enumerate(feats["rocks"]):
        rx_p = (rk["pos"][0] - ox) * PX_PER_TILE
        ry_p = (rk["pos"][1] - oy) * PX_PER_TILE
        rr = max(2.4, rk["r"] * 1.65)
        ang_r = ((idx_rk * 47) % 360) * 0.0174533
        pts_b = [
            (rx_p + math.cos(ang_r + a) * rr * s, ry_p + math.sin(ang_r + a) * rr * s * 0.85)
            for a, s in ((0.0, 1.0), (1.05, 0.88), (2.1, 1.05), (3.15, 0.86), (4.2, 1.02), (5.25, 0.90))
        ]
        draw.polygon([(px + 1.8, py + 1.8) for px, py in pts_b], fill=INK_DARK)
        draw.polygon(pts_b, fill=(108, 124, 132), outline=INK_STRUCT)
        # NW sunlit facet + smaller satellite pebble
        draw.polygon([(rx_p - rr * 0.65, ry_p - rr * 0.2), (rx_p - rr * 0.15, ry_p - rr * 0.72), (rx_p + rr * 0.25, ry_p - rr * 0.15), (rx_p - rr * 0.2, ry_p + rr * 0.15)], fill=(172, 184, 182))
        draw.ellipse([rx_p + rr * 0.55, ry_p + rr * 0.35, rx_p + rr * 1.15, ry_p + rr * 0.95], fill=(92, 108, 116), outline=INK_STRUCT)
        _stamp_elev_ink(rx_p, ry_p, rr, rr, 0.38)

    # Detailed Threshold Blockers
    for blk in feats["blockers"]:
        bx_p = (blk["pos"][0] - ox) * PX_PER_TILE
        by_p = (blk["pos"][1] - oy) * PX_PER_TILE
        bk = blk["kind"]
        if bk == "bramble_wall":
            # Dense thorny hedge barricade with intertwined dark boughs & subtle void-purple thorns
            draw.ellipse([bx_p - 7 + 1.5, by_p - 4.5 + 1.5, bx_p + 7 + 1.5, by_p + 4.5 + 1.5], fill=INK_DARK)
            for ox_b, oy_b, rbx, rby, col_b in (
                (-4.0, -1.0, 4.0, 3.2, (46, 66, 52)),
                (3.5, -1.0, 3.8, 3.0, (54, 40, 66)),
                (0.0, 0.5, 4.8, 3.5, (42, 26, 48)),
                (-1.5, -1.5, 2.8, 2.2, (74, 46, 84)),
            ):
                draw.ellipse([bx_p + ox_b - rbx, by_p + oy_b - rby, bx_p + ox_b + rbx, by_p + oy_b + rby], fill=col_b, outline=INK_DARK)
            for tx_o, ty_o in ((-5, -2), (-2, 1), (1, -2), (4, 1), (0, 2)):
                draw.line([(bx_p + tx_o - 1, by_p + ty_o - 1), (bx_p + tx_o + 2, by_p + ty_o + 1)], fill=(144, 86, 158), width=1)
            _stamp_elev_ink(bx_p, by_p, 7.5, 5.0, 0.42)
        elif bk == "collapsed_gate":
            # Twin ruined masonry gate pillars + shattered fallen lintel & rubble across the path
            draw.rectangle([bx_p - 8, by_p - 4, bx_p + 8, by_p + 5], fill=(82, 86, 94), outline=INK_DARK)
            draw.rectangle([bx_p - 8, by_p - 5, bx_p - 3.5, by_p + 4], fill=(128, 138, 142), outline=INK_STRUCT)
            draw.rectangle([bx_p + 3.5, by_p - 5, bx_p + 8, by_p + 4], fill=(116, 126, 132), outline=INK_STRUCT)
            draw.polygon([(bx_p - 4, by_p - 2), (bx_p + 4, by_p + 0.5), (bx_p + 3, by_p + 3.5), (bx_p - 5, by_p + 1)], fill=(156, 162, 164), outline=INK_STRUCT)
            draw.line([(bx_p - 5, by_p + 2), (bx_p + 4, by_p - 2)], fill=(108, 78, 56), width=1)
            _stamp_elev_ink(bx_p, by_p, 8.5, 5.5, 0.45)
        else:  # rockfall
            # Multi-boulder scree pile + gravel dust apron
            draw.ellipse([bx_p - 7.5, by_p - 5.0, bx_p + 7.5, by_p + 5.5], fill=(88, 92, 96))
            for ox_r, oy_r, rr_b, col_r in (
                (-3.5, -1.2, 3.2, (112, 126, 134)),
                (3.0, -1.0, 2.8, (102, 116, 124)),
                (-0.5, 1.8, 3.0, (124, 136, 142)),
                (1.2, -2.4, 2.3, (148, 158, 160)),
            ):
                draw.ellipse([bx_p + ox_r - rr_b + 1, by_p + oy_r - rr_b + 1, bx_p + ox_r + rr_b + 1, by_p + oy_r + rr_b + 1], fill=INK_DARK)
                draw.ellipse([bx_p + ox_r - rr_b, by_p + oy_r - rr_b, bx_p + ox_r + rr_b, by_p + oy_r + rr_b], fill=col_r, outline=INK_STRUCT)
                draw.point((int(bx_p + ox_r - rr_b * 0.4), int(by_p + oy_r - rr_b * 0.4)), fill=(184, 195, 187))
            _stamp_elev_ink(bx_p, by_p, 7.5, 5.5, 0.44)

    # Detailed Stone-Setter Ruins, Lighthouse, Map Tablet, Waystone, Vista
    for rn in feats["ruins"]:
        rx_p = (rn["pos"][0] - ox) * PX_PER_TILE
        ry_p = (rn["pos"][1] - oy) * PX_PER_TILE
        rk_kind = rn["kind"]
        if rk_kind in ("lighthouse", "tower"):
            # Broken courtyard walls + octagonal/circular ruined lighthouse tower + beacon core + SE cast shadow
            rr = max(10.0, rn["r"] * 2.4)
            # Flagstone courtyard apron
            draw.polygon([
                (rx_p - rr, ry_p - rr * 0.6), (rx_p + rr * 0.85, ry_p - rr * 0.8),
                (rx_p + rr, ry_p + rr * 0.7), (rx_p - rr * 0.75, ry_p + rr * 0.85),
            ], fill=(96, 108, 112), outline=INK_DARK)
            # Broken perimeter masonry segments (NW, NE, SW walls with ruin gaps)
            draw.rectangle([rx_p - rr, ry_p - rr * 0.8, rx_p - rr + 3.0, ry_p + rr * 0.3], fill=(138, 148, 152), outline=INK_STRUCT)
            draw.rectangle([rx_p - rr, ry_p - rr * 0.8, rx_p + rr * 0.4, ry_p - rr * 0.8 + 3.0], fill=(162, 172, 174), outline=INK_STRUCT)
            draw.rectangle([rx_p + rr - 3.5, ry_p - rr * 0.2, rx_p + rr, ry_p + rr * 0.65], fill=(116, 128, 134), outline=INK_STRUCT)
            # Long SE tower shadow + circular stone tower masonry ring
            tr_p = 7.2
            draw.ellipse([rx_p - tr_p + 3.5, ry_p - tr_p + 3.5, rx_p + tr_p + 3.5, ry_p + tr_p + 3.5], fill=INK_DARK)
            draw.ellipse([rx_p - tr_p, ry_p - tr_p, rx_p + tr_p, ry_p + tr_p], fill=(132, 146, 152), outline=INK_STRUCT)
            draw.arc([rx_p - tr_p + 1, ry_p - tr_p + 1, rx_p + tr_p - 1, ry_p + tr_p - 1], start=180, end=315, fill=(186, 196, 194), width=2)
            draw.ellipse([rx_p - 3.8, ry_p - 3.8, rx_p + 3.8, ry_p + 3.8], fill=(34, 42, 58), outline=INK_STRUCT)
            draw.ellipse([rx_p - 2.6, ry_p - 2.6, rx_p + 2.6, ry_p + 2.6], fill=(96, 232, 222))
            draw.ellipse([rx_p - 1.2, ry_p - 1.2, rx_p + 1.2, ry_p + 1.2], fill=(224, 255, 248))
            _stamp_elev_ink(rx_p, ry_p, rr + 2.0, rr + 2.0, 0.56, BIT_GLOW_ARCANE)
        elif rk_kind in ("tablet", "map_tablet", "stone_setter"):
            # Stepped circular Stone-Setter dais with glowing rune slab
            draw.ellipse([rx_p - 5.5 + 1.5, ry_p - 5.5 + 1.5, rx_p + 5.5 + 1.5, ry_p + 5.5 + 1.5], fill=INK_DARK)
            draw.ellipse([rx_p - 5.5, ry_p - 5.5, rx_p + 5.5, ry_p + 5.5], fill=(116, 128, 136), outline=INK_STRUCT)
            draw.rectangle([rx_p - 3.0, ry_p - 2.2, rx_p + 3.0, ry_p + 2.2], fill=(54, 62, 78), outline=(172, 184, 184))
            draw.line([(rx_p - 1.8, ry_p), (rx_p + 1.8, ry_p)], fill=(120, 244, 230), width=1)
            draw.point((int(rx_p), int(ry_p - 1)), fill=(220, 255, 248))
            _stamp_elev_ink(rx_p, ry_p, 6.0, 6.0, 0.48, BIT_GLOW_ARCANE)
        elif rk_kind == "waystone":
            # Mossy circular flagstone plinth + tall SE monolith shadow + standing rune obelisk
            draw.ellipse([rx_p - 7.0, ry_p - 7.0, rx_p + 7.0, ry_p + 7.0], fill=(98, 114, 108), outline=INK_STRUCT)
            draw.ellipse([rx_p - 5.2, ry_p - 5.2, rx_p + 5.2, ry_p + 5.2], fill=(128, 142, 144), outline=(74, 88, 92))
            draw.polygon([(rx_p, ry_p - 1), (rx_p + 6.5, ry_p + 5.0), (rx_p + 4.0, ry_p + 6.8), (rx_p - 1.5, ry_p + 1.5)], fill=INK_DARK)
            draw.polygon([(rx_p - 2.4, ry_p + 1.5), (rx_p - 1.5, ry_p - 3.2), (rx_p + 1.8, ry_p - 2.6), (rx_p + 2.4, ry_p + 1.5)], fill=(142, 162, 174), outline=INK_STRUCT)
            draw.ellipse([rx_p - 1.5, ry_p - 1.8, rx_p + 1.5, ry_p + 1.2], fill=(120, 244, 230))
            _stamp_elev_ink(rx_p, ry_p, 7.5, 7.5, 0.52, BIT_GLOW_ARCANE)
        elif rk_kind == "vista":
            # Overlook semicircle parapet terrace
            draw.ellipse([rx_p - 5.0 + 1.2, ry_p - 5.0 + 1.2, rx_p + 5.0 + 1.2, ry_p + 5.0 + 1.2], fill=INK_DARK)
            draw.ellipse([rx_p - 5.0, ry_p - 5.0, rx_p + 5.0, ry_p + 5.0], fill=(134, 144, 148), outline=INK_STRUCT)
            draw.arc([rx_p - 4.2, ry_p - 4.2, rx_p + 4.2, ry_p + 4.2], start=35, end=215, fill=(184, 194, 192), width=2)
            draw.ellipse([rx_p - 1.4, ry_p - 1.4, rx_p + 1.4, ry_p + 1.4], fill=(120, 244, 230))
            _stamp_elev_ink(rx_p, ry_p, 5.5, 5.5, 0.46, BIT_GLOW_ARCANE)
        else:
            # Generic ruined wall compound
            rr = max(5.5, rn["r"] * 1.8)
            draw.rectangle([rx_p - rr + 2, ry_p - rr + 2, rx_p + rr + 2, ry_p + rr + 2], outline=INK_DARK, width=2)
            draw.rectangle([rx_p - rr, ry_p - rr, rx_p + rr, ry_p + rr], outline=INK_STRUCT, width=3)
            draw.rectangle([rx_p - rr + 1, ry_p - rr + 1, rx_p + rr - 1, ry_p + rr - 1], outline=(146, 158, 162), width=1)
            _stamp_elev_ink(rx_p, ry_p, rr + 1.0, rr + 1.0, 0.46)

    # Detailed Top-Down Coastal Camps (Bayer clearing already stamped -> pitched tarp tent + stone hearth + log seat + chest + rack)
    for cp in feats["camps"]:
        cx_c = (cp["pos"][0] - ox) * PX_PER_TILE
        cy_c = (cp["pos"][1] - oy) * PX_PER_TILE
        # Pitched canvas shelter tent
        tx_p = (cp["tent"][0] - ox) * PX_PER_TILE
        ty_p = (cp["tent"][1] - oy) * PX_PER_TILE
        draw.rectangle([tx_p - 5.0 + 2.0, ty_p - 3.8 + 2.0, tx_p + 5.5 + 2.0, ty_p + 4.2 + 2.0], fill=INK_DARK)
        draw.rectangle([tx_p - 5.0, ty_p - 3.8, tx_p + 5.5, ty_p + 4.2], fill=(112, 86, 66), outline=INK_STRUCT)
        draw.rectangle([tx_p - 4.0, ty_p - 2.8, tx_p + 4.5, ty_p + 0.2], fill=(176, 148, 108))
        draw.line([(tx_p - 4.5, ty_p), (tx_p + 5.0, ty_p)], fill=(218, 194, 146), width=1)
        _stamp_elev_ink(tx_p, ty_p, 6.0, 4.5, 0.44)
        # Wooden supply chest
        chx = (cp["chest"][0] - ox) * PX_PER_TILE
        chy = (cp["chest"][1] - oy) * PX_PER_TILE
        draw.rectangle([chx - 2.5 + 1, chy - 1.8 + 1, chx + 2.5 + 1, chy + 1.8 + 1], fill=INK_DARK)
        draw.rectangle([chx - 2.5, chy - 1.8, chx + 2.5, chy + 1.8], fill=(138, 92, 54), outline=INK_STRUCT)
        draw.line([(chx - 1.5, chy), (chx + 1.5, chy)], fill=(214, 178, 94), width=1)
        _stamp_elev_ink(chx, chy, 3.0, 2.2, 0.40)
        # Log bench seat & weapon rack silhouette
        sx_p = (cp["seat"][0] - ox) * PX_PER_TILE
        sy_p = (cp["seat"][1] - oy) * PX_PER_TILE
        draw.rectangle([sx_p - 3.0, sy_p - 1.2, sx_p + 3.0, sy_p + 1.2], fill=(124, 88, 60), outline=INK_STRUCT)
        rkx = (cp["rack"][0] - ox) * PX_PER_TILE
        rky = (cp["rack"][1] - oy) * PX_PER_TILE
        draw.line([(rkx - 2.2, rky - 1.8), (rkx + 2.2, rky + 1.8)], fill=(166, 174, 182), width=1)
        draw.line([(rkx - 2.2, rky + 1.8), (rkx + 2.2, rky - 1.8)], fill=(122, 86, 58), width=1)
        # Stone campfire ring around hearth
        for a_deg in range(0, 360, 45):
            ang_s = a_deg * 0.0174533
            draw.ellipse([cx_c + math.cos(ang_s) * 2.8 - 1.1, cy_c + math.sin(ang_s) * 2.8 - 1.1, cx_c + math.cos(ang_s) * 2.8 + 1.1, cy_c + math.sin(ang_s) * 2.8 + 1.1], fill=(122, 132, 138), outline=INK_STRUCT)

    for rf in feats["roofs"]:
        cx_p = (rf["pos"][0] - ox) * PX_PER_TILE
        cy_p = (rf["pos"][1] - oy) * PX_PER_TILE
        hw = max(3.5, rf["w"] * PX_PER_TILE * 0.5)
        hh = max(2.8, rf["h"] * PX_PER_TILE * 0.5)
        draw.rectangle([cx_p - hw + 2, cy_p - hh + 2, cx_p + hw + 2, cy_p + hh + 2], fill=INK_DARK)
        if rf["style"] == "slate":
            c_nw, c_se, c_rd = (110, 102, 150), (44, 40, 72), (168, 160, 206)
        elif rf["style"] == "tent":
            c_nw, c_se, c_rd = (168, 142, 102), (102, 78, 60), (214, 190, 144)
        else:
            c_nw, c_se, c_rd = (138, 106, 120), (58, 42, 62), (186, 154, 162)
        draw.rectangle([cx_p - hw, cy_p - hh, cx_p + hw, cy_p + hh], fill=c_se, outline=INK_STRUCT)
        draw.rectangle([cx_p - hw + 1, cy_p - hh + 1, cx_p + hw - 1, cy_p], fill=c_nw)
        draw.line([(cx_p - hw + 1, cy_p), (cx_p + hw - 1, cy_p)], fill=c_rd, width=1)
        _stamp_elev_ink(cx_p, cy_p, hw, hh, 0.45)

    rgb = np.array(pil_rgb, dtype=np.float32)

    # 10. Individual Tree Crowns (sorted by Y, stage)
    zone_trees = sorted(land.trees_of(z.id), key=lambda t: (t["pos"][1], t["stage"]))
    for tr in zone_trees:
        sp = SPECIES_ALIASES.get(tr["species"], tr["species"])
        spec = tree_cat.get(sp, tree_cat["valley_oak"])
        st = max(0, min(len(spec["crown_half_px"]) - 1, int(tr["stage"])))
        crown_r = (spec["crown_half_px"][st] / float(PX_PER_TILE)) * 0.68
        mcx = (tr["pos"][0] - ox) * PX_PER_TILE
        mcy = (tr["pos"][1] - oy) * PX_PER_TILE
        _draw_tree_crown(rgb, elev, alpha_mask, nx_arr, ny_arr, mcx, mcy, crown_r, sp, int(tr["seed"]), tree_cat, biome_idx=z_biome_idx)

    # 11. Campfires & Arcane Glow Spots (painted above canopy/roofs so night embers/beacons stay crisp)
    for cfx, cfy in feats["campfires"]:
        mx = int(round((cfx - ox) * PX_PER_TILE))
        my = int(round((cfy - oy) * PX_PER_TILE))
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                xx_c, yy_c = mx + dx, my + dy
                if 0 <= xx_c < W and 0 <= yy_c < H:
                    d = math.hypot(dx, dy)
                    if d <= 1.1:
                        rgb[yy_c, xx_c] = (255, 212, 120)
                        alpha_mask[yy_c, xx_c] |= BIT_GLOW_WARM
                    elif d <= 2.2:
                        rgb[yy_c, xx_c] = rgb[yy_c, xx_c] * 0.45 + np.array((194, 108, 52), dtype=np.float32) * 0.55
                        alpha_mask[yy_c, xx_c] |= BIT_GLOW_WARM

    for ax, ay in feats["arcane_pts"]:
        mx = int(round((ax - ox) * PX_PER_TILE))
        my = int(round((ay - oy) * PX_PER_TILE))
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                xx_a, yy_a = mx + dx, my + dy
                if 0 <= xx_a < W and 0 <= yy_a < H and math.hypot(dx, dy) <= 1.6:
                    if math.hypot(dx, dy) <= 0.8:
                        rgb[yy_a, xx_a] = (120, 244, 230)
                    alpha_mask[yy_a, xx_a] |= BIT_GLOW_ARCANE

    # Settlements warm hearth bits
    for sx, sy, sr in feats["settlements"]:
        dist_s = np.hypot(tx - sx, ty - sy)
        s_mask = (dist_s <= sr * 0.65) & ((alpha_mask & BIT_INK_CLIFF) != 0)
        alpha_mask[s_mask] |= BIT_GLOW_WARM

    # 12. Finalize MEADOW & VALID bits + RGBA8 images
    meadow_m = owned_domain & (~any_water) & ((alpha_mask & (BIT_CANOPY | BIT_SAND_WAY | BIT_INK_CLIFF)) == 0)
    alpha_mask[meadow_m] |= BIT_MEADOW
    alpha_mask[owned_domain] |= BIT_VALID
    alpha_mask[~owned_domain] = 0

    map_rgba = np.zeros((H, W, 4), dtype=np.uint8)
    map_rgba[..., :3] = np.clip(np.round(rgb), 1, 255).astype(np.uint8)
    map_rgba[..., 3] = np.where(owned_domain, 255, 0).astype(np.uint8)
    map_rgba = _sanitize_zero_black(map_rgba)
    _assert_zero_black(map_rgba, f"{z.id}/map.png")

    light_rgba = np.zeros((H, W, 4), dtype=np.uint8)
    light_rgba[..., 0] = np.where(owned_domain, np.clip(np.round((nx_arr * 0.5 + 0.5) * 255.0), 0, 255), 128).astype(np.uint8)
    light_rgba[..., 1] = np.where(owned_domain, np.clip(np.round((ny_arr * 0.5 + 0.5) * 255.0), 0, 255), 128).astype(np.uint8)
    light_rgba[..., 2] = np.where(owned_domain, np.clip(np.round(np.clip(elev, 0.0, 1.0) * 255.0), 0, 255), 64).astype(np.uint8)
    light_rgba[..., 3] = alpha_mask
    light_rgba = _sanitize_zero_black(light_rgba)
    _assert_zero_black(light_rgba, f"{z.id}/map_light.png")

    # 13. far.png (1 px/tile aerial perspective, full w x h opaque backdrop)
    # Build full-frame RGB before masking so corners outside owned_domain carry seamless canopy/water haze
    full_rgb_1x = np.clip(np.round(rgb), 1, 255).reshape(th, PX_PER_TILE, tw, PX_PER_TILE, 3).mean(axis=(1, 3)).astype(np.float32)
    lum = full_rgb_1x[..., 0] * 0.299 + full_rgb_1x[..., 1] * 0.587 + full_rgb_1x[..., 2] * 0.114
    mean_lum = float(np.mean(lum))
    desat = full_rgb_1x * 0.48 + lum[..., None] * 0.52
    soft = desat * 0.58 + mean_lum * 0.42
    haze_col = np.array([46.0, 66.0, 94.0], dtype=np.float32)  # #2e425e aerial blue-indigo
    far_rgb = np.clip(np.round(soft * 0.60 + haze_col * 0.40), 8, 255).astype(np.uint8)
    far_rgba = np.zeros((th, tw, 4), dtype=np.uint8)
    far_rgba[..., :3] = far_rgb
    far_rgba[..., 3] = 255
    _assert_zero_black(far_rgba, f"{z.id}/far.png")

    meta = {
        "zone_id": z.id,
        "origin": [ox, oy],
        "size": [tw, th],
        "px_per_tile": PX_PER_TILE,
        "light_alpha_bits": LIGHT_ALPHA_BITS,
        "campfires": [[round(c[0] - ox, 2), round(c[1] - oy, 2)] for c in feats["campfires"]],
        "settlements": [[round(s[0] - ox, 2), round(s[1] - oy, 2), round(s[2], 2)] for s in feats["settlements"]],
    }

    if write_outputs:
        out_dir = cont.world_dir / "zones" / z.id / "baked"
        out_dir.mkdir(parents=True, exist_ok=True)
        Image.fromarray(map_rgba, mode="RGBA").save(out_dir / "map.png", compress_level=1)
        Image.fromarray(light_rgba, mode="RGBA").save(out_dir / "map_light.png", compress_level=1)
        Image.fromarray(far_rgba, mode="RGBA").save(out_dir / "far.png", compress_level=1)
        with (out_dir / "meta.json").open("w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)

    return {"map": map_rgba, "light": light_rgba, "far": far_rgba, "meta": meta}


# ---------------------------------------------------------------------------
# PixelText 3x5 Rasterizer (for Stone-Setter Engraving)
# ---------------------------------------------------------------------------

def draw_pixel_text(
    img: Image.Image,
    text: str,
    center_xy: tuple[int, int],
    color: tuple[int, int, int],
    outline: tuple[int, int, int] | None = None,
    scale: int = 2,
) -> tuple[int, int]:
    norm = text.replace("ß", "SS").upper()
    if not norm:
        return center_xy
    tw = max(0, len(norm) * PIXEL_FONT_ADVANCE - 1) * scale
    th = PIXEL_FONT_HEIGHT * scale
    x0 = int(round(center_xy[0] - tw * 0.5))
    y0 = int(round(center_xy[1] - th * 0.5))
    draw = ImageDraw.Draw(img)

    def stamp(ox: int, oy: int, col: tuple[int, int, int]) -> None:
        cx = x0 + ox
        for ch in norm:
            base = PIXEL_FONT_ACCENTS.get(ch, ch)
            rows = PIXEL_FONT_GLYPHS.get(base)
            if rows is not None:
                for r_idx, row_str in enumerate(rows):
                    for c_idx, px_ch in enumerate(row_str):
                        if px_ch == "X":
                            px = cx + c_idx * scale
                            py = y0 + oy + (2 + r_idx) * scale
                            draw.rectangle([px, py, px + scale - 1, py + scale - 1], fill=col)
                if ch in PIXEL_FONT_ACCENTS:
                    for ux in (0, 2):
                        px = cx + ux * scale
                        py = y0 + oy
                        draw.rectangle([px, py, px + scale - 1, py + scale - 1], fill=col)
            elif ch == "·":
                px = cx + scale
                py = y0 + oy + 4 * scale
                draw.rectangle([px, py, px + scale - 1, py + scale - 1], fill=col)
            cx += PIXEL_FONT_ADVANCE * scale

    if outline is not None:
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            stamp(dx, dy, outline)
    stamp(0, 0, color)
    return (x0, y0)


# ---------------------------------------------------------------------------
# Continent Composite & Stone-Setter Engraving (1 px/tile)
# ---------------------------------------------------------------------------

def _detect_great_rift(cont: ContinentData) -> tuple[tuple[float, float] | None, float, list[tuple[float, float]]]:
    """Detects Great Rift position, radius, and void_edge polyline ONLY when rift or void/Varnholm data exists."""
    for src in (cont.raw, cont.landscape_raw):
        rift = src.get("rift") or src.get("great_rift")
        if isinstance(rift, dict):
            pos = as_vec2(rift.get("epicenter", rift.get("pos", rift.get("center"))))
            edge_pts = as_poly(rift.get("void_edge", []))
            if pos is not None:
                return pos, float(rift.get("radius", 72.0)), edge_pts
        elif isinstance(rift, (list, tuple)) and len(rift) >= 2:
            r = float(rift[2]) if len(rift) >= 3 else 65.0
            return (float(rift[0]), float(rift[1])), r, []

    # Check void zones / Leerenblühen / Varnholm / void_edge borders
    for zid in cont.zone_order:
        z = cont.zones[zid]
        ztext = f"{z.id} {z.name} {z.region_id}".lower()
        has_void_border = any(str(b.get("kind", "")) == "void_edge" for b in z.borders)
        if z.kind == "void" or has_void_border or any(k in ztext for k in ("leeren", "varnholm", "rift", "riss")):
            x0, y0, x1, y1 = z.bbox
            return ((x0 * 0.35 + x1 * 0.65), (y0 + y1) * 0.5), 62.0, []

    return None, 0.0, []


def _rasterize_islets(cont: ContinentData, W: int, H: int) -> np.ndarray:
    """Rasterizes offshore skerries/islets from cont.islets with subtle craggy rock modulation."""
    islet_m = np.zeros((H, W), dtype=bool)
    if not cont.islets:
        return islet_m
    n_isl = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=557, freq=0.18, octaves=2, sub=2)
    for isl in cont.islets:
        poly = isl["poly"]
        x0, y0, x1, y1 = bbox_of(poly)
        ix0 = max(0, int(math.floor(x0)) - 8)
        iy0 = max(0, int(math.floor(y0)) - 8)
        ix1 = min(W, int(math.ceil(x1)) + 8)
        iy1 = min(H, int(math.ceil(y1)) + 8)
        iw, ih = ix1 - ix0, iy1 - iy0
        if iw <= 0 or ih <= 0:
            continue
        im_base = rasterize_polygon_mask(iw, ih, float(ix0), float(iy0), 1.0, poly)
        pa = np.array(poly, dtype=np.float32)
        pb = np.roll(pa, -1, axis=0)
        d_isl, _ = fast_narrowband_segments_distance(iw, ih, float(ix0), float(iy0), 1.0, pa, pb, 6.0)
        sd_isl = np.where(im_base, d_isl, -d_isl) + (n_isl[iy0:iy1, ix0:ix1] - 0.5) * 4.2
        islet_m[iy0:iy1, ix0:ix1] |= sd_isl > -0.4
    return islet_m


def _build_continent_landmass(cont: ContinentData, gx: np.ndarray, gy: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Returns (land_mask, coast_dist) at continent resolution."""
    H, W = gx.shape
    islet_m = _rasterize_islets(cont, W, H)
    raw_hull = cont.raw.get("landmass") or cont.raw.get("coastline")
    if isinstance(raw_hull, list) and len(raw_hull) >= 3:
        raw_poly = as_poly(raw_hull)
        poly = smooth_closed(raw_poly, 4.0) if len(raw_poly) < 80 else raw_poly
        land_m = rasterize_polygon_mask(W, H, 0.0, 0.0, 1.0, poly)
        # Ensure all zone interiors stay inside landmass, and add offshore islets
        for zid in cont.zone_order:
            land_m |= rasterize_polygon_mask(W, H, 0.0, 0.0, 1.0, cont.zones[zid].footprint)
        land_m |= islet_m
        seg_a_list = [np.array(poly, dtype=np.float32)]
        seg_b_list = [np.roll(seg_a_list[0], -1, axis=0)]
        for isl in cont.islets:
            ia = np.array(isl["poly"], dtype=np.float32)
            seg_a_list.append(ia)
            seg_b_list.append(np.roll(ia, -1, axis=0))
        pa = np.concatenate(seg_a_list, axis=0)
        pb = np.concatenate(seg_b_list, axis=0)
        d, _ = fast_segments_distance_grid(W, H, 0.0, 0.0, 1.0, pa, pb, None)
        return land_m, np.where(land_m, -d, d)

    # Synthesize island hull organically from zones, honoring "water" borders on coastal zones
    zone_union = np.zeros((H, W), dtype=bool)
    min_dist = np.full((H, W), 1e6, dtype=np.float32)
    water_cut = np.zeros((H, W), dtype=bool)

    for zid in cont.zone_order:
        z = cont.zones[zid]
        zm = rasterize_polygon_mask(W, H, 0.0, 0.0, 1.0, z.footprint)
        zone_union |= zm

        fp = z.footprint
        sa = np.array(fp, dtype=np.float32)
        sb = np.roll(sa, -1, axis=0)
        sl = np.hypot(sb[:, 0] - sa[:, 0], sb[:, 1] - sa[:, 1])
        tot = max(float(np.sum(sl)), 1e-4)
        cum = np.concatenate(([0.0], np.cumsum(sl))) / tot
        sh_arr = np.stack([cum[:-1], cum[1:]], axis=1).astype(np.float32)

        bx0, by0, bx1, by1 = z.bbox
        pad = 320
        ix0, iy0 = max(0, int(bx0 - pad)), max(0, int(by0 - pad))
        ix1, iy1 = min(W, int(bx1 + pad)), min(H, int(by1 + pad))
        if ix1 <= ix0 or iy1 <= iy0:
            continue
        zd, zsh = fast_segments_distance_grid(ix1 - ix0, iy1 - iy0, float(ix0), float(iy0), 1.0, sa, sb, sh_arr)
        min_dist[iy0:iy1, ix0:ix1] = np.minimum(min_dist[iy0:iy1, ix0:ix1], zd)

        for b in z.borders:
            if str(b.get("kind", "")) in ("water", "coast", "ocean"):
                fr = float(b.get("from", 0.0))
                to = float(b.get("to", 1.0))
                if fr <= to:
                    bm = (zsh >= fr) & (zsh <= to)
                else:
                    bm = (zsh >= fr) | (zsh <= to)
                water_cut[iy0:iy1, ix0:ix1] |= bm & (~zm[iy0:iy1, ix0:ix1])

    n_zones = len(cont.zone_order)
    base_buf = 78.0 if n_zones >= 4 else min(72.0, max(24.0, min(W, H) * 0.11))
    coast_noise = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=613, freq=0.012, octaves=3, sub=4) - 0.5) * 65.0
    coast_fine = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=907, freq=0.045, octaves=2, sub=2) - 0.5) * 18.0
    edge_d = np.minimum(np.minimum(gx, W - 1.0 - gx), np.minimum(gy, H - 1.0 - gy))
    # Smooth noise-modulated edge repulsion instead of a hard rectangular box clip
    margin = min(46.0, min(W, H) * 0.085)
    edge_pen = np.maximum(0.0, margin - edge_d) * 2.4
    land_m = zone_union | ((min_dist + coast_noise + coast_fine + edge_pen <= base_buf) & (~water_cut)) | islet_m

    sea_m = ~land_m
    p = land_m.astype(np.float32)
    blur_wide = box_blur_3x3(np.asarray(Image.fromarray((p * 255).astype(np.uint8)).resize((max(4, W // 4), max(4, H // 4)), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0, passes=8)
    blur_wide_up = np.asarray(Image.fromarray((np.clip(blur_wide, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
    signed_d = np.where(sea_m, np.maximum(1.0, (1.0 - blur_wide_up) * 160.0), -np.maximum(1.0, blur_wide_up * 120.0))
    return land_m, signed_d


# ---------------------------------------------------------------------------
# Website-Style Pixel-Art Cartographer Primitives (map.mjs / world_map.gdshader)
# ---------------------------------------------------------------------------

CONT_BAYER_CELL = 3   # 3x3-tile macro pixel grid on 2400x1800 -> zero aliasing at 0.24-0.55 px/tile!
CONT_PIX_STEP = 3     # 3-tile contour & stitch step -> razor-sharp ink lines at overview & 1:1


def _biome_index_for_name(text: str) -> int:
    s = text.lower()
    if any(k in s for k in ("hex", "schatten", "witch", "gloom", "dornen", "eiben")):
        return 2
    if any(k in s for k in ("leeren", "varn", "void", "riss", "rift", "oestlich", "östlich")):
        return 3
    if "kristall" in s:
        return 5
    if any(k in s for k in ("glas", "hallgrat", "highland")):
        return 1
    if any(k in s for k in ("suedwest", "südwest", "windkap", "suedkap", "südkap", "klippenstieg", "kuesten", "küsten")):
        return 4
    if any(k in s for k in ("gruen", "grün", "wiese", "lichtung", "meadow", "erlen", "muehle", "mühle", "glimm")):
        return 0
    if any(k in s for k in ("quartz", "sonnen", "steppe", "arid", "desert")):
        return 6
    return 0


def _map_areas_to_biome_lut(
    cont: ContinentData,
    areas_raw: np.ndarray,
    relief_a: np.ndarray | None,
) -> np.ndarray:
    """Builds a 256-entry LUT mapping continental_areas.png values (1..N) -> BIOME_PALETTES index (0..6)."""
    lut = np.zeros(256, dtype=np.uint8)
    # 1. Explicit legend in continent JSON if provided by build_altmark_world.py
    explicit = cont.raw.get("area_biomes") or cont.raw.get("area_legend")
    if isinstance(explicit, dict):
        for k, v in explicit.items():
            try:
                ki = int(k)
            except (TypeError, ValueError):
                continue
            if 0 <= ki < 256:
                lut[ki] = int(v) if isinstance(v, int) else _biome_index_for_name(str(v))
        return lut
    if isinstance(explicit, list):
        for idx, v in enumerate(explicit):
            if idx + 1 < 256:
                lut[idx + 1] = int(v) if isinstance(v, int) else _biome_index_for_name(str(v))
        return lut

    max_id = int(np.max(areas_raw)) if areas_raw.size else 0
    # 2. Match against regions list (1..len(regions))
    if cont.regions and 1 <= max_id <= len(cont.regions):
        for i, reg in enumerate(cont.regions):
            label = f"{reg.get('id', '')} {reg.get('name', '')} {reg.get('old_name', '')}"
            lut[i + 1] = _biome_index_for_name(label)
        return lut
    # 3. Match against zone list (1..len(zones))
    if cont.zone_order and 1 <= max_id <= len(cont.zone_order):
        for i, zid in enumerate(cont.zone_order):
            z = cont.zones[zid]
            label = f"{z.id} {z.region_id} {' '.join(z.biomes)}"
            lut[i + 1] = _biome_index_for_name(label)
        return lut
    # 4. Fallback: infer per-area biome from overlapping zone regions
    for aid in range(1, min(max_id + 1, 256)):
        ys, xs = np.nonzero(areas_raw == aid)
        if len(xs) == 0:
            continue
        cx, cy = float(np.median(xs)), float(np.median(ys))
        zid = cont.zone_at_tile((cx, cy))
        if zid and zid in cont.zones:
            z = cont.zones[zid]
            lut[aid] = _biome_index_for_name(f"{z.id} {z.region_id} {' '.join(z.biomes)}")
        elif relief_a is not None:
            med_a = int(np.median(relief_a[ys, xs]))
            if med_a >= 200:
                lut[aid] = min(6, med_a - 200)
    return lut


def _load_or_synth_continental_fields(
    cont: ContinentData,
    gx: np.ndarray,
    gy: np.ndarray,
) -> dict[str, Any]:
    """Loads pre-baked continental_*.png geodata (from build_altmark_world.py) or synthesizes exact equivalents from JSON."""
    H, W = gx.shape
    baked_dir = cont.world_dir / "continents" / "baked" / cont.id
    p_sdf = baked_dir / "continental_sdf.png"
    p_rel = baked_dir / "continental_relief.png"
    p_fld = baked_dir / "continental_field.png"
    p_wat = baked_dir / "continental_water.png"
    p_lks = baked_dir / "continental_lakes_sdf.png"
    p_ars = baked_dir / "continental_areas.png"

    n_cw1 = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=617, freq=0.22, octaves=1, sub=2)
    n_cw2 = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=941, freq=0.72, octaves=1, sub=1)

    has_baked = p_sdf.exists() and p_fld.exists()
    if has_baked:
        sdf_im = Image.open(p_sdf).convert("L")
        if sdf_im.size != (W, H):
            sdf_im = sdf_im.resize((W, H), Image.Resampling.BILINEAR)
        sdf_u8 = np.asarray(sdf_im, dtype=np.float32)
        coast_raw = (sdf_u8 - 128.0) / 8.0
        coast = coast_raw + (n_cw1 - 0.5) * 0.75 + (n_cw2 - 0.5) * 0.28
        land_m = coast > 0.0

        # Exact far ocean distance beyond +-16 tile SDF saturation
        far_sea = _fast_mask_boundary_distance(land_m, factor=4)
        near_sea = np.maximum(0.0, -coast)
        blend_far = smoothstep_np(6.0, 13.0, near_sea)
        outside_dist = np.where(land_m, 0.0, near_sea * (1.0 - blend_far) + far_sea * blend_far)

        fld_im = Image.open(p_fld).convert("RGB")
        if fld_im.size != (W, H):
            fld_im = fld_im.resize((W, H), Image.Resampling.BILINEAR)
        field = np.asarray(fld_im, dtype=np.float32) * (1.0 / 255.0)

        if p_rel.exists():
            rel_im = Image.open(p_rel).convert("RGBA")
            if rel_im.size != (W, H):
                rel_im = rel_im.resize((W, H), Image.Resampling.NEAREST)
            rel_arr = np.asarray(rel_im, dtype=np.uint8)
            relief_level = rel_arr[..., 0]
            relief_kind = rel_arr[..., 1] & np.uint8(15)
            relief_style = (rel_arr[..., 1] >> np.uint8(4)) & np.uint8(15)
            relief_a = rel_arr[..., 3]
        else:
            relief_level = np.clip(np.round(field[..., 0] + field[..., 1] + field[..., 2]), 0, 3).astype(np.uint8)
            relief_kind = np.zeros((H, W), dtype=np.uint8)
            relief_style = np.zeros((H, W), dtype=np.uint8)
            relief_a = None

        if p_wat.exists():
            wat_im = Image.open(p_wat).convert("RGB")
            if wat_im.size != (W, H):
                wat_im = wat_im.resize((W, H), Image.Resampling.BILINEAR)
            water_rgb = np.asarray(wat_im, dtype=np.float32) * (1.0 / 255.0)
        else:
            water_rgb = np.zeros((H, W, 3), dtype=np.float32)

        if p_lks.exists():
            lks_im = Image.open(p_lks).convert("L")
            if lks_im.size != (W, H):
                lks_im = lks_im.resize((W, H), Image.Resampling.BILINEAR)
            lake_sdf_u8 = np.asarray(lks_im, dtype=np.float32)
        else:
            lake_sdf_u8 = np.full((H, W), 255.0, dtype=np.float32)
        lake_inset = (128.0 - lake_sdf_u8) / 8.0

        zones_raw: np.ndarray | None = None
        islet_raw = np.zeros((H, W), dtype=bool)
        areas_biome_raw = np.zeros((H, W), dtype=np.uint8)
        if p_ars.exists():
            ars_im = Image.open(p_ars).convert("RGB")
            if ars_im.size != (W, H):
                ars_im = ars_im.resize((W, H), Image.Resampling.NEAREST)
            ars_rgb = np.asarray(ars_im, dtype=np.uint8)
            areas_raw = ars_rgb[..., 0].copy()
            zones_raw = ars_rgb[..., 1].copy()
            areas_biome_raw = ars_rgb[..., 2].copy()
            max_z = len(cont.zone_order)
            islet_raw = zones_raw > max_z
            # Propagate exact region & islet flags onto 1-3px noise-wobbled coast edges so no islet pixel falls back to 0!
            for _ in range(4):
                miss = land_m & (areas_raw == 0)
                if not np.any(miss):
                    break
                pa_a = np.pad(areas_raw, 1, mode="edge")
                pi_i = np.pad(islet_raw, 1, mode="edge")
                for sy, sx in ((0, 1), (2, 1), (1, 0), (1, 2)):
                    nb = pa_a[sy:sy + H, sx:sx + W]
                    take = miss & (nb > 0)
                    if np.any(take):
                        areas_raw[take] = nb[take]
                        islet_raw[take] |= pi_i[sy:sy + H, sx:sx + W][take]
                        miss = land_m & (areas_raw == 0)
        else:
            areas_raw = _synth_areas_from_zones(cont, W, H)

        area_lut = _map_areas_to_biome_lut(cont, areas_raw, relief_a)
        if zones_raw is not None and "kristallgrat" in cont.zone_order:
            kg_zid = cont.zone_order.index("kristallgrat") + 1
            kg_aid = max(6, len(cont.regions) + 1)
            # Include Kristallgrat mainland AND NW Glaskamm islets directly fronting Kristallgrat
            kg_mask = (zones_raw == kg_zid) | (
                islet_raw & (areas_raw == 3) & ((relief_style == 3) | ((gx < 1060.0) & (gy < 680.0)))
            )
            areas_raw = np.where(kg_mask, np.uint8(kg_aid), areas_raw)
            area_lut[kg_aid] = 5  # Kristallgrat cool alpine crystal slate-blue
        return {
            "coast": coast,
            "land_m": land_m,
            "outside_dist": outside_dist,
            "field": field,
            "relief_level": relief_level,
            "relief_kind": relief_kind,
            "relief_style": relief_style,
            "water_rgb": water_rgb,
            "lake_sdf_u8": lake_sdf_u8,
            "lake_inset": lake_inset,
            "areas_raw": areas_raw,
            "areas_biome_raw": areas_biome_raw,
            "zones_raw": zones_raw,
            "islet_raw": islet_raw,
            "area_lut": area_lut,
            "using_baked_fields": True,
        }

    # --- JSON fallback (e.g. lab continent or when continental_*.png are absent) ---
    land_m, _ = _build_continent_landmass(cont, gx, gy)
    dist_out = _fast_mask_boundary_distance(land_m, factor=2)
    dist_in = _fast_mask_boundary_distance(~land_m, factor=2)
    coast = np.where(land_m, dist_in, -dist_out) + (n_cw1 - 0.5) * 1.1 + (n_cw2 - 0.5) * 0.35
    land_m = coast > 0.0
    outside_dist = np.where(land_m, 0.0, np.maximum(0.0, -coast))

    # Synthesize morphological 4-level plateaus (bake_relief.py style)
    wx = gx + (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1101, freq=0.015, octaves=2, sub=4) - 0.5) * 60.0
    wy = gy + (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1102, freq=0.015, octaves=2, sub=4) - 0.5) * 60.0
    cW, cH = max(8, W // 4), max(8, H // 4)
    wxc = wx[::4, ::4][:cH, :cW]
    wyc = wy[::4, ::4][:cH, :cW]
    nf = _upsample_f32(fbm2d(wxc, wyc, seed=1103, freq=0.012, octaves=3), W, H)
    # Boost elevation along explicit ridges from landscape JSON
    ridge_boost = np.zeros((H, W), dtype=np.float32)
    for rg in cont.landscape_raw.get("ridges") or []:
        if isinstance(rg, dict):
            rpts = as_poly(rg.get("pts", rg.get("line", [])))
            if len(rpts) >= 2:
                sm_r = subdivide_catmull(rpts, subdiv=6)
                sa = np.array(sm_r[:-1], dtype=np.float32)
                sb = np.array(sm_r[1:], dtype=np.float32)
                rw = float(rg.get("width", 24.0)) * 2.2
                rd, _ = fast_narrowband_segments_distance(W, H, 0.0, 0.0, 1.0, sa, sb, rw)
                ridge_boost = np.maximum(ridge_boost, (1.0 - smoothstep_np(0.0, rw, rd)) * 0.42)
    flat_coast = smoothstep_np(8.0, 26.0, np.maximum(0.0, coast))
    h_raw = np.clip((nf + ridge_boost) * flat_coast, 0.0, 1.2)
    # Quantize into 3 morphological nested plateau tiers
    lvl = np.zeros((H, W), dtype=np.uint8)
    prev = land_m.copy()
    for k, thresh in ((1, 0.56), (2, 0.72), (3, 0.86)):
        m = (h_raw > thresh) & prev
        if np.any(m):
            m = _morph_dilate(_morph_erode(m, 3), 3)
            m = _morph_erode(_morph_dilate(m, 3), 3)
            m &= prev
            if k > 1:
                m &= _morph_erode(prev, 5)
            lvl += m.astype(np.uint8)
            prev = m
    fields_ch = [box_blur_sep((lvl >= k).astype(np.float32), r=2, passes=3) for k in (1, 2, 3)]
    field = np.stack(fields_ch, axis=-1)

    # 2-tile south-facing cliff walls (FACE = 1)
    relief_kind = np.zeros((H, W), dtype=np.uint8)
    for dy_w in (1, 2):
        above = np.zeros_like(lvl)
        above[dy_w:] = lvl[:-dy_w]
        relief_kind[(above > lvl) & land_m] = 1
    relief_style = np.zeros((H, W), dtype=np.uint8)

    # Synthesize rivers & lakes from landscape_raw
    water_rgb = np.zeros((H, W, 3), dtype=np.float32)
    lake_mask = np.zeros((H, W), dtype=bool)
    for r_idx, rv in enumerate(cont.landscape_raw.get("rivers") or []):
        if isinstance(rv, dict) and len(rv.get("pts") or []) >= 2:
            rpts_raw = rv["pts"]
            raw_xy = [(float(p[0]), float(p[1])) for p in rpts_raw]
            raw_rs = [float(p[2]) if len(p) >= 3 else 1.5 for p in rpts_raw]
            r_seed = int(rv.get("seed", godot_hash_array([str(rv.get("id", f"riv_{r_idx}"))]) & 0xFFFF))
            shaped = _shape_continent_river(raw_xy, raw_rs, r_seed)
            sa = np.array([(p[0], p[1]) for p in shaped[:-1]], dtype=np.float32)
            sb = np.array([(p[0], p[1]) for p in shaped[1:]], dtype=np.float32)
            seg_r = np.stack([[p[2] for p in shaped[:-1]], [p[2] for p in shaped[1:]]], axis=1).astype(np.float32)
            max_rr = float(max(p[2] for p in shaped)) + 3.0
            rd_sdf, rd_r = fast_narrowband_segments_distance(W, H, 0.0, 0.0, 1.0, sa, sb, max_rr, seg_radii=seg_r)
            assert rd_r is not None
            cov = np.clip(1.0 - smoothstep_np(-0.8, 1.2, rd_sdf), 0.0, 1.0) * land_m
            dep = np.clip(-rd_sdf / np.maximum(rd_r, 0.8), 0.0, 1.0) * land_m
            water_rgb[..., 0] = np.maximum(water_rgb[..., 0], cov)
            water_rgb[..., 1] = np.maximum(water_rgb[..., 1], dep)

    for lk in cont.landscape_raw.get("lakes") or []:
        if isinstance(lk, dict):
            poly = as_poly(lk.get("poly", lk.get("pts", [])))
            if len(poly) >= 3:
                lake_mask |= rasterize_polygon_mask(W, H, 0.0, 0.0, 1.0, poly) & land_m
            else:
                pos = as_vec2(lk.get("pos", lk.get("center")))
                if pos:
                    rx = float(lk.get("rx", lk.get("radius", 18.0)))
                    ry = float(lk.get("ry", lk.get("radius", 14.0)))
                    lake_mask |= (np.hypot((gx - pos[0]) / max(rx, 1.0), (gy - pos[1]) / max(ry, 1.0)) <= 1.0) & land_m
    if np.any(lake_mask):
        lin = _fast_mask_boundary_distance(~lake_mask, factor=2)
        lout = _fast_mask_boundary_distance(lake_mask, factor=2)
        lake_inset = np.where(lake_mask, lin, -lout)
        lake_sdf_u8 = np.clip(128.0 - lake_inset * 8.0, 0.0, 255.0)
        max_lin = max(float(np.max(lin[lake_mask])), 1.0)
        water_rgb[..., 2] = np.where(lake_mask, 0.12 + 0.88 * np.power(np.clip(lin / max_lin, 0.0, 1.0), 0.72), 0.0)
        water_rgb[..., 0] = np.where(lake_mask, 1.0, water_rgb[..., 0])
    else:
        lake_inset = np.full((H, W), -32.0, dtype=np.float32)
        lake_sdf_u8 = np.full((H, W), 255.0, dtype=np.float32)

    areas_raw = _synth_areas_from_zones(cont, W, H)
    area_lut = _map_areas_to_biome_lut(cont, areas_raw, None)
    return {
        "coast": coast,
        "land_m": land_m,
        "outside_dist": outside_dist,
        "field": field,
        "relief_level": lvl,
        "relief_kind": relief_kind,
        "relief_style": relief_style,
        "water_rgb": water_rgb,
        "lake_sdf_u8": lake_sdf_u8,
        "lake_inset": lake_inset,
        "areas_raw": areas_raw,
        "area_lut": area_lut,
        "using_baked_fields": False,
    }


def _synth_areas_from_zones(cont: ContinentData, W: int, H: int) -> np.ndarray:
    """Synthesizes continental_areas.png (1..len(regions)) from zone footprints."""
    areas = np.zeros((H, W), dtype=np.uint8)
    reg_idx = {str(r.get("id", "")): i + 1 for i, r in enumerate(cont.regions)}
    for i, zid in enumerate(cont.zone_order):
        z = cont.zones[zid]
        aid = reg_idx.get(z.region_id, (i % 6) + 1)
        x0, y0, x1, y1 = [int(v) for v in z.bbox]
        x0c, y0c, x1c, y1c = max(0, x0), max(0, y0), min(W, x1 + 1), min(H, y1 + 1)
        if x1c > x0c and y1c > y0c:
            zm = rasterize_polygon_mask(x1c - x0c, y1c - y0c, float(x0c), float(y0c), 1.0, z.footprint)
            areas[y0c:y1c, x0c:x1c][zm] = aid
    return areas


def _render_pixel_ocean(
    W: int,
    H: int,
    gx: np.ndarray,
    gy: np.ndarray,
    outside_dist: np.ndarray,
    bayer_c: np.ndarray,
    bayer_shift: np.ndarray,
    cell_px: int = CONT_BAYER_CELL,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """5-tone Bayer-dithered deep pixel-art ocean (adapted from map.mjs voidSmoke) + 3 undulating shore wave ripples.
    Returns (ocean_rgb, ocean_a_swell, ocean_b_ridge) so estuaries, rivers & lakes share the EXACT same water swell!"""
    cW, cH = max(8, W // 4), max(8, H // 4)
    cx = (np.arange(cW, dtype=np.float32)[None, :] + 0.5) * (W / float(cW))
    cy = (np.arange(cH, dtype=np.float32)[:, None] + 0.5) * (H / float(cH))
    qx = cx * 0.0085
    qy = cy * 0.0085
    w1 = fbm2d(qx * 0.6, qy * 0.6, seed=211, freq=1.0, octaves=3)
    w2 = fbm2d(qx * 0.6 + 3.0, qy * 0.6 + 3.0, seed=223, freq=1.0, octaves=3)
    a_c = fbm2d(qx + 2.2 * w1, qy + 2.2 * w2, seed=229, freq=1.0, octaves=4)
    b_c = fbm2d(qx * 1.55 + 9.0, qy * 1.55 + 9.0, seed=239, freq=1.0, octaves=4)
    a = _upsample_f32(a_c, W, H)
    b = _upsample_f32(b_c, W, H)

    ocean_depth = smoothstep_np(8.0, 125.0, outside_dist)
    t = a * 4.9 - 0.95 + (1.0 - ocean_depth) * 1.45 + (bayer_c - 0.5) * 0.86
    k = np.clip(np.floor(t), 0, 4).astype(np.int32)
    col = OCEAN_PAL[k].copy()

    # Subtle Bayer-dithered deep ocean swell ridges (only along sunlit swell crests, never busy spiderwebs!)
    ridge = 1.0 - smoothstep_np(0.0, 0.017, np.abs(b - 0.5))
    ridge_m = (ridge > 0.52) & (a > 0.48) & (bayer_shift < 0.56)
    if np.any(ridge_m):
        w_r = (0.24 + 0.14 * (1.0 - ocean_depth[ridge_m]))[..., None]
        col[ridge_m] = col[ridge_m] * (1.0 - w_r) + OCEAN_RIDGE * w_r

    # Sparse hand-inked pixel wave crests far out at sea (restrained so ocean stays calm and majestic)
    _stamp_wave_marks(
        col,
        outside_dist > 72.0,
        outside_dist,
        W,
        H,
        spacing=128,
        min_inset=76.0,
        light_col=OCEAN_RIDGE,
        alpha_crest=0.34,
        alpha_echo=0.16,
        px_size=cell_px,
        seed=409,
    )

    # Soft coastal turquoise-cyan halo right outside the coast
    halo = 1.0 - smoothstep_np(0.0, 16.0, outside_dist)
    halo_m = (outside_dist > 0.0) & (outside_dist < 16.0)
    if np.any(halo_m):
        hw = (halo[halo_m] * 0.34)[..., None]
        col[halo_m] = col[halo_m] * (1.0 - hw) + SHORE_HALO * hw

    # Three gentle undulating cartographer shore wave ripples following every bay, fjord, headland & skerry
    cell_x = (np.arange(W, dtype=np.int32)[None, :] // max(1, cell_px))
    cell_y = (np.arange(H, dtype=np.int32)[:, None] // max(1, cell_px))
    wave_phase = np.sin(gx * 0.042 + gy * 0.031) * 1.15
    rip_period = 12.5
    rip_d = np.abs(((outside_dist - 6.0 + wave_phase) / rip_period + 0.5) % 1.0 - 0.5) * rip_period
    rip_stitch = ((cell_x + cell_y) % 3) < 2
    rip_m = (outside_dist > 4.2) & (outside_dist < 44.0) & (rip_d < 1.35) & rip_stitch
    if np.any(rip_m):
        rw = (0.64 * (1.0 - (outside_dist[rip_m] - 4.2) / 40.0))[..., None]
        col[rip_m] = col[rip_m] * (1.0 - rw) + RIPPLE_TINT * rw

    return col, a, b


def _stamp_wave_marks(
    rgb: np.ndarray,
    valid_mask: np.ndarray,
    inset_arr: np.ndarray,
    W: int,
    H: int,
    spacing: int,
    min_inset: float,
    light_col: np.ndarray,
    alpha_crest: float = 0.42,
    alpha_echo: float = 0.22,
    px_size: int = 2,
    seed: int = 81,
) -> None:
    """Stamps crisp hand-inked 3+3 pixel wave crests (exact port of map.mjs drawLakeWaves)."""
    ps = max(1, int(px_size))
    nx = W // spacing
    ny = H // spacing
    for cy in range(ny):
        for cx in range(nx):
            h = ((cx * 73856093) ^ (cy * 19349663) ^ (seed * 83492791)) & 0xFFFF
            if (h / 65535.0) < 0.52:
                continue
            hx = (((cx * 374761393) ^ (cy * 668265263) ^ ((seed + 32) * 1274126177)) & 0xFFFF) / 65535.0
            hy = (((cx * 668265263) ^ (cy * 374761393) ^ ((seed + 67) * 1274126177)) & 0xFFFF) / 65535.0
            px = int((cx + 0.24 + hx * 0.52) * spacing)
            py = int((cy + 0.24 + hy * 0.52) * spacing)
            if px < 4 * ps or px >= W - 4 * ps or py < 3 * ps or py >= H - 4 * ps:
                continue
            if not valid_mask[py, px] or inset_arr[py, px] < min_inset:
                continue
            # Crest: (-3..-1, 0) and (0..2, -1) in macro pixels
            for lx, ly, a in (
                (-3, 0, alpha_crest), (-2, 0, alpha_crest), (-1, 0, alpha_crest),
                (0, -1, alpha_crest), (1, -1, alpha_crest), (2, -1, alpha_crest),
                (0, 2, alpha_echo), (1, 2, alpha_echo), (2, 2, alpha_echo),
            ):
                x0 = px + lx * ps
                y0 = py + ly * ps
                rgb[y0:y0 + ps, x0:x0 + ps] = (
                    rgb[y0:y0 + ps, x0:x0 + ps] * (1.0 - a) + light_col * a
                )


def _render_lake_ink(
    W: int,
    H: int,
    gx: np.ndarray,
    gy: np.ndarray,
    in_lake: np.ndarray,
    basin: np.ndarray,
    lake_inset: np.ndarray,
    lake_sdf_u8: np.ndarray,
    bayer_c: np.ndarray,
    bayer_shift: np.ndarray,
    cell_px: int = CONT_BAYER_CELL,
) -> np.ndarray:
    """Ocean-harmonized 5-tone Bayer-dithered cartographer lakes with full bathymetry, swell, shore ripples & crisp rim."""
    # True full-basin inset distance (blends exact near-shore SDF with deep EDT so large lakes don't saturate at 12px!)
    near_in = np.maximum(lake_inset, 0.0)
    far_in = _fast_mask_boundary_distance(~in_lake, factor=2)
    b_far = smoothstep_np(5.0, 12.0, near_in)
    full_inset = np.where(in_lake, near_in * (1.0 - b_far) + far_in * b_far, 0.0)

    # Warped FBM lake swell matching _render_pixel_ocean's sapphire-turquoise liquid character
    cW, cH = max(8, W // 4), max(8, H // 4)
    cx = (np.arange(cW, dtype=np.float32)[None, :] + 0.5) * (W / float(cW))
    cy = (np.arange(cH, dtype=np.float32)[:, None] + 0.5) * (H / float(cH))
    qx, qy = cx * 0.015, cy * 0.015
    w1 = fbm2d(qx * 0.7, qy * 0.7, seed=317, freq=1.0, octaves=2)
    w2 = fbm2d(qx * 0.7 + 4.1, qy * 0.7 + 2.7, seed=331, freq=1.0, octaves=2)
    swell = _upsample_f32(fbm2d(qx + 1.6 * w1, qy + 1.6 * w2, seed=347, freq=1.0, octaves=3), W, H)
    ridge_f = _upsample_f32(fbm2d(qx * 1.65 + 7.0, qy * 1.65 + 7.0, seed=353, freq=1.0, octaves=3), W, H)

    bath = smoothstep_np(0.5, 22.0, full_inset)
    depth = np.clip(0.04 + bath * 0.84 + (basin - 0.5) * 0.08 + (swell - 0.5) * 0.32, 0.0, 1.0)
    cont_lake_pal = np.stack([LAKE_SHELF, OCEAN4, OCEAN3, OCEAN2, LAKE_DEEP], axis=0)
    ink = bayer_quantize_ramp(cont_lake_pal, depth, bayer_c, spread=0.86).copy()

    # Subtle coastal turquoise-cyan inner halo matching ocean SHORE_HALO right along shore
    l_halo = (1.0 - smoothstep_np(0.0, 7.0, full_inset)) * 0.30
    l_halo_m = in_lake & (full_inset > 1.8) & (full_inset < 7.0)
    if np.any(l_halo_m):
        hw_l = l_halo[l_halo_m][..., None]
        ink[l_halo_m] = ink[l_halo_m] * (1.0 - hw_l) + SHORE_HALO * hw_l

    # Subtle Bayer-dithered swell ridges inside deep lake interiors (matches OCEAN_RIDGE currents!)
    rdg = 1.0 - smoothstep_np(0.0, 0.022, np.abs(ridge_f - 0.5))
    rdg_m = in_lake & (full_inset > 8.0) & (rdg > 0.48) & (swell > 0.44) & (bayer_shift < 0.56)
    if np.any(rdg_m):
        ink[rdg_m] = ink[rdg_m] * 0.64 + OCEAN_RIDGE * 0.36

    # Two delicate undulating concentric shore ripples inside lakes (EXACT RIPPLE_TINT twin of ocean shore ripples!)
    cell_x = np.arange(W, dtype=np.int32)[None, :] // max(1, cell_px)
    cell_y = np.arange(H, dtype=np.int32)[:, None] // max(1, cell_px)
    w_ph = np.sin(gx * 0.052 + gy * 0.038) * 1.0
    rip_p = 9.0
    rip_d = np.abs(((full_inset - 5.0 + w_ph) / rip_p + 0.5) % 1.0 - 0.5) * rip_p
    rip_m = in_lake & (full_inset > 3.2) & (full_inset < 21.0) & (rip_d < 1.15) & (((cell_x + cell_y) % 3) < 2)
    if np.any(rip_m):
        rw = (0.60 * (1.0 - (full_inset[rip_m] - 3.2) / 18.5))[..., None]
        ink[rip_m] = ink[rip_m] * (1.0 - rw) + RIPPLE_TINT * rw

    # Smooth-gradient crisp pixel-art shore rim (delicate sunlit COAST_RIM on NW shore, shaded RIPPLE/OCEAN4 on SE, zero blocky flips!)
    sdf_sm = box_blur_3x3(lake_sdf_u8, passes=2)
    step_g = 2
    sp = np.pad(sdf_sm, step_g, mode="edge")
    grad_x = sp[step_g:-step_g, 2 * step_g:] - sp[step_g:-step_g, :-2 * step_g]
    grad_y = sp[2 * step_g:, step_g:-step_g] - sp[:-2 * step_g, step_g:-step_g]
    glen = np.maximum(np.hypot(grad_x, grad_y), 1e-4)
    light = np.clip(0.5 + 0.5 * ((grad_x / glen) * (-0.6) + (grad_y / glen) * (-0.8)), 0.0, 1.0)
    rim_outer = in_lake & (full_inset < 2.2)
    if np.any(rim_outer):
        # Smooth continuous sunlit rim matching the ocean's delicate COAST_RIM
        l_w = smoothstep_np(0.22, 0.78, light[rim_outer])[..., None]
        col_se = OCEAN4 * 0.55 + RIPPLE_TINT * 0.45
        col_nw = COAST_RIM * 0.80 + SHORE_HALO * 0.20
        ink[rim_outer] = col_se * (1.0 - l_w) + col_nw * l_w

    _stamp_wave_marks(
        ink,
        in_lake & (full_inset > 10.0),
        full_inset,
        W,
        H,
        spacing=52,
        min_inset=11.0,
        light_col=LAKE_LIGHT,
        alpha_crest=0.46,
        alpha_echo=0.22,
        px_size=max(2, cell_px - 1),
        seed=181,
    )
    return ink


def _stamp_cartographer_glyphs(
    rgb: np.ndarray,
    land_m: np.ndarray,
    coast: np.ndarray,
    best_cliff: np.ndarray,
    in_water: np.ndarray,
    forest_m: np.ndarray,
    path_m: np.ndarray,
    rift_m: np.ndarray,
    biome_idx: np.ndarray,
    W: int,
    H: int,
    spacing: int = 44,
    px_size: int = 2,
) -> None:
    """Stamps crisp 5x5 hand-inked cartographer symbols (exact map.mjs GLYPHS) onto flat open plateaus."""
    ps = max(1, int(px_size))
    nx = W // spacing
    ny = H // spacing
    for cy in range(ny):
        for cx in range(nx):
            h = (((cx * 73856093) ^ (cy * 19349663) ^ 0x5A17) & 0xFFFF) / 65535.0
            hx = (((cx * 374761393) ^ (cy * 668265263) ^ 5011) & 0xFFFF) / 65535.0
            hy = (((cx * 668265263) ^ (cy * 374761393) ^ 9029) & 0xFFFF) / 65535.0
            px = int((cx + 0.22 + hx * 0.56) * spacing)
            py = int((cy + 0.22 + hy * 0.56) * spacing)
            if px < 4 * ps or px >= W - 4 * ps or py < 4 * ps or py >= H - 4 * ps:
                continue
            if not land_m[py, px] or coast[py, px] < 9.0 or best_cliff[py, px] < 1.9:
                continue
            if in_water[py, px] or forest_m[py, px] or path_m[py, px] or rift_m[py, px]:
                continue
            ab = int(biome_idx[py, px])
            if h > GLYPH_DENSITY[ab]:
                continue
            pick = 1 if ((((cx * 19349663) ^ (cy * 83492791) ^ 31) & 255) > 127) else 0
            g = GLYPHS_5X5[ab][pick]
            hi_col = BIOME_PALETTES[ab, 2]
            ox0 = px - 2 * ps
            oy0 = py - 2 * ps
            # Shadow pass (+1 macro-px SE)
            for ly in range(5):
                for lx in range(5):
                    if (g >> (ly * 5 + lx)) & 1:
                        sx = ox0 + (lx + 1) * ps
                        sy = oy0 + (ly + 1) * ps
                        rgb[sy:sy + ps, sx:sx + ps] = rgb[sy:sy + ps, sx:sx + ps] * 0.72 + INK_PIXEL * 0.28
            # Foreground glyph pass
            for ly in range(5):
                for lx in range(5):
                    if (g >> (ly * 5 + lx)) & 1:
                        fx = ox0 + lx * ps
                        fy = oy0 + ly * ps
                        rgb[fy:fy + ps, fx:fx + ps] = rgb[fy:fy + ps, fx:fx + ps] * 0.62 + hi_col * 0.38


def _build_forest_carpet(
    cont: ContinentData,
    land_m: np.ndarray,
    coast: np.ndarray,
    best_cliff: np.ndarray,
    relief_kind: np.ndarray,
    in_water: np.ndarray,
    path_m: np.ndarray,
    W: int,
    H: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Builds organic scalloped woodland canopy carpet masks (NO cauliflower dots, NO zone hedge rings!)."""
    stand_base = np.zeros((H, W), dtype=bool)
    glade_mask = np.zeros((H, W), dtype=bool)
    for st in cont.landscape_raw.get("stands") or []:
        if not isinstance(st, dict):
            continue
        rpoly = as_poly(st.get("outline", st.get("poly", [])))
        if len(rpoly) < 3:
            continue
        poly = smooth_closed(rpoly, 3.0) if len(rpoly) < 40 else rpoly
        x0, y0, x1, y1 = bbox_of(poly)
        ix0, iy0 = max(0, int(x0) - 2), max(0, int(y0) - 2)
        ix1, iy1 = min(W, int(x1) + 3), min(H, int(y1) + 3)
        if ix1 <= ix0 or iy1 <= iy0:
            continue
        sm = rasterize_polygon_mask(ix1 - ix0, iy1 - iy0, float(ix0), float(iy0), 1.0, poly)
        stand_base[iy0:iy1, ix0:ix1] |= sm
        for gl in st.get("glades") or []:
            gpoly = as_poly(gl)
            if len(gpoly) >= 3:
                gpoly_s = smooth_closed(gpoly, 3.0) if len(gpoly) < 32 else gpoly
                gm = rasterize_polygon_mask(ix1 - ix0, iy1 - iy0, float(ix0), float(iy0), 1.0, gpoly_s)
                glade_mask[iy0:iy1, ix0:ix1] |= gm

    stand_base &= ~glade_mask
    if not np.any(stand_base):
        empty_b = np.zeros((H, W), dtype=bool)
        empty_f = np.zeros((H, W), dtype=np.float32)
        return empty_b, empty_f, empty_f, empty_b, empty_b

    # Organic scalloped treeline wobble (multi-scale FBM breaks any rounded polygon silhouette)
    d_in = _fast_mask_boundary_distance(~stand_base, factor=2)
    d_out = _fast_mask_boundary_distance(stand_base, factor=2)
    sd_f = np.where(stand_base, d_in, -d_out)
    n_edge = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=521, freq=0.048, octaves=3, sub=2)
    n_crown = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=547, freq=0.145, octaves=2, sub=2)
    n_micro = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=563, freq=0.28, octaves=1, sub=1)
    sd_wob = sd_f + (n_edge - 0.5) * 16.0 + (n_crown - 0.5) * 6.5

    # Respect coastlines, water, steep cliff ink/faces, and roads
    forest_m = (
        (sd_wob > 0.0)
        & land_m
        & (coast > 6.5)
        & (~in_water)
        & (best_cliff > 0.95)
        & (relief_kind != 1)
        & (~path_m)
    )
    if not np.any(forest_m):
        empty_b = np.zeros((H, W), dtype=bool)
        empty_f = np.zeros((H, W), dtype=np.float32)
        return empty_b, empty_f, empty_f, empty_b, empty_b

    # Billowing NW-lit tree-crown canopy relief inside forest_m
    inset_f = smoothstep_np(0.0, 10.0, np.maximum(0.0, sd_wob))
    canopy_h = np.clip((n_crown * 0.65 + n_micro * 0.35) * (0.62 + 0.38 * inset_f), 0.0, 1.0)
    ch_pad = np.pad(canopy_h, 2, mode="edge")
    canopy_lit = ch_pad[4:, 4:] - ch_pad[:-4, :-4]

    # Crisp 2-tile INK canopy perimeter rim (stronger on SE)
    pf = np.pad(forest_m, 2, mode="constant", constant_values=False)
    forest_rim = forest_m & (
        (~pf[:-4, 2:-2]) | (~pf[4:, 2:-2]) | (~pf[2:-2, :-4]) | (~pf[2:-2, 4:])
    )
    # SE cast shadow (+4, +4 tiles outside forest_m)
    pf_sh = np.pad(forest_m, 4, mode="constant", constant_values=False)
    forest_shadow = (~forest_m) & land_m & (~in_water) & (
        pf_sh[:-8, :-8] | pf_sh[1:-7, 1:-7] | pf_sh[2:-6, 2:-6]
    )
    return forest_m, canopy_h, canopy_lit, forest_rim, forest_shadow


def _render_great_rift_pixel_art(
    cmap_rgb: np.ndarray,
    eng_rgb: np.ndarray,
    alpha_mask: np.ndarray,
    land_m: np.ndarray,
    outside_dist: np.ndarray,
    W: int,
    H: int,
    gx: np.ndarray,
    gy: np.ndarray,
    bayer_c: np.ndarray,
    rift_pos: tuple[float, float],
    rift_radius: float,
    rift_edge: list[tuple[float, float]],
) -> tuple[np.ndarray, np.ndarray]:
    """Renders the Great Rift jagged crystalline violet-magenta tear on eastern Varnholm land (zero round disc over sea!)."""
    rx, ry = rift_pos
    n_rift = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1337, freq=0.055, octaves=3, sub=2)
    n_vein = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1451, freq=0.088, octaves=3, sub=2)
    n_jagg = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1489, freq=0.032, octaves=3, sub=2)

    # Only affect continent land + frayed <= 10-tile shoreline distortion (NEVER a round black disc in the ocean!)
    rift_domain = land_m | (outside_dist < 8.0)

    dx_r = gx - rx
    dy_r = gy - ry
    ang = np.arctan2(dy_r, dx_r)
    jagged = 1.0 + 0.34 * np.sin(3.0 * ang + 0.7) + 0.22 * np.cos(7.0 * ang - 1.2) + (n_jagg - 0.5) * 0.55
    eff_r = np.maximum(rift_radius * jagged, 18.0)
    dist_r = np.hypot(dx_r * 1.22, dy_r * 0.68) / eff_r + (n_rift - 0.5) * 0.42

    # Tapered jagged fracture spine (tapers cleanly to splintering crystal cracks at N/S tips — NEVER a thick uniform tube!)
    if len(rift_edge) >= 2:
        sm_re = _meander_polyline(rift_edge, seed=1399, amp=7.5, freq=0.045, subdiv=8)
        n_s = len(sm_re)
        radii_e = [max(3.5, 16.0 * (math.sin(math.pi * (i / max(1, n_s - 1))) ** 0.75)) for i in range(n_s)]
        sa = np.array(sm_re[:-1], dtype=np.float32)
        sb = np.array(sm_re[1:], dtype=np.float32)
        sr = np.stack([radii_e[:-1], radii_e[1:]], axis=1).astype(np.float32)
        ed_sdf, ed_rr = fast_narrowband_segments_distance(W, H, 0.0, 0.0, 1.0, sa, sb, 34.0, seg_radii=sr)
        assert ed_rr is not None
        ed_norm = np.clip((ed_sdf + ed_rr + (n_rift - 0.5) * 12.0) / np.maximum(ed_rr * 2.1, 8.0), 0.0, 9.0)
        dist_r = np.minimum(dist_r, np.where(np.hypot(dx_r, dy_r) <= max(rift_radius * 1.9, 175.0), ed_norm, 9.0))

    scorched = rift_domain & (dist_r <= 1.24)
    chasm = rift_domain & (dist_r <= 0.64)
    core = land_m & (dist_r <= 0.22) & ((n_vein > 0.36) & (n_vein < 0.64))
    vein_ridge = np.abs(n_vein - 0.5)
    fissure = rift_domain & (dist_r <= 1.06) & ((vein_ridge < 0.024) | ((dist_r <= 0.52) & (vein_ridge < 0.042)))
    vein_halo = rift_domain & (dist_r <= 1.14) & (vein_ridge < 0.068) & (~fissure)

    # Bayer-dithered outer scorched blight -> jagged void chasm -> crystalline violet/magenta fracture veins
    u_sc = np.clip((1.24 - dist_r) / 0.60, 0.0, 1.0)
    blight_dith = scorched & (~chasm) & (bayer_c < u_sc * 0.90)
    cmap_rgb[blight_dith] = cmap_rgb[blight_dith] * 0.30 + np.array([22.0, 11.0, 42.0], dtype=np.float32) * 0.70
    cmap_rgb[chasm] = np.where(
        (bayer_c[chasm] < np.clip((0.64 - dist_r[chasm]) / 0.42, 0.0, 1.0))[..., None],
        np.array([10.0, 6.0, 22.0], dtype=np.float32),
        np.array([34.0, 18.0, 66.0], dtype=np.float32),
    )
    halo_dith = vein_halo & (bayer_c < 0.60)
    cmap_rgb[halo_dith] = np.array([104.0, 56.0, 186.0], dtype=np.float32)
    cmap_rgb[fissure] = np.where(
        (bayer_c[fissure] < 0.55)[..., None],
        np.array([255.0, 79.0, 216.0], dtype=np.float32),
        np.array([176.0, 108.0, 255.0], dtype=np.float32),
    )
    cmap_rgb[core] = np.where(
        (dist_r[core] < 0.12)[..., None],
        np.array([236.0, 210.0, 255.0], dtype=np.float32),
        np.array([255.0, 79.0, 216.0], dtype=np.float32),
    )
    alpha_mask[fissure | core] |= np.uint8(BIT_GLOW_ARCANE)
    alpha_mask[chasm] &= np.uint8(255 ^ (BIT_MEADOW | BIT_CANOPY))

    # Return organic Bayer-frayed scar mask for engraving.png (ZERO solid black circle!)
    engr_scar = (blight_dith | chasm) & land_m
    eng_rgb[engr_scar] = ENG_ABYSS
    eng_rgb[(fissure | core) & land_m] = ENG_BRIGHT
    return engr_scar, ((fissure | core) & land_m)


def _render_stone_setter_engraving(
    cont: ContinentData,
    W: int,
    H: int,
    gx: np.ndarray,
    gy: np.ndarray,
    fields: dict[str, Any],
    bayer_c: np.ndarray,
    bayer_shift: np.ndarray,
    h_field: np.ndarray,
    lit_field: np.ndarray,
    best_cliff: np.ndarray,
    side_cliff: np.ndarray,
    forest_m: np.ndarray,
    forest_rim: np.ndarray,
    forest_shadow: np.ndarray,
    in_lake: np.ndarray,
    river_cov: np.ndarray,
    in_water: np.ndarray,
    zone_frontier: np.ndarray,
    rift_pos: tuple[float, float] | None,
    rift_radius: float,
    rift_scorched: np.ndarray,
    rift_fissure: np.ndarray,
    cell_px: int = CONT_BAYER_CELL,
) -> tuple[np.ndarray, list[dict[str, Any]]]:
    """Monochrome slate-silver carved stone engraving using the EXACT same plateau/coast/water geometry."""
    land_m = fields["land_m"]
    coast = fields["coast"]
    outside_dist = fields["outside_dist"]
    relief_kind = fields["relief_kind"]
    lake_inset = fields["lake_inset"]

    # 1. Carved dark slate sea with subtle Bayer ocean swell + 3 exact coastal ripple lines
    cW, cH = max(8, W // 4), max(8, H // 4)
    cx = (np.arange(cW, dtype=np.float32)[None, :] + 0.5) * (W / float(cW))
    cy = (np.arange(cH, dtype=np.float32)[:, None] + 0.5) * (H / float(cH))
    sea_sw = _upsample_f32(fbm2d(cx * 0.0085, cy * 0.0085, seed=211, freq=1.0, octaves=3), W, H)
    sea_t = np.clip(sea_sw * 2.4 + (1.0 - smoothstep_np(10.0, 120.0, outside_dist)) * 0.8 + (bayer_c - 0.5) * 0.85, 0.0, 2.99)
    eng_sea_pal = np.stack([ENG_ABYSS, ENG_SEA0, ENG_SEA1], axis=0)
    eng = eng_sea_pal[np.floor(sea_t).astype(np.int32)].copy()

    # Exact same 3 undulating coastal ripple lines
    cell_x = np.arange(W, dtype=np.int32)[None, :] // max(1, cell_px)
    cell_y = np.arange(H, dtype=np.int32)[:, None] // max(1, cell_px)
    wave_phase = np.sin(gx * 0.042 + gy * 0.031) * 1.15
    rip_period = 12.5
    rip_d = np.abs(((outside_dist - 6.0 + wave_phase) / rip_period + 0.5) % 1.0 - 0.5) * rip_period
    rip_m = (~land_m) & (outside_dist > 4.2) & (outside_dist < 44.0) & (rip_d < 1.35) & (((cell_x + cell_y) % 3) < 2)
    if np.any(rip_m):
        rw = (0.68 * (1.0 - (outside_dist[rip_m] - 4.2) / 40.0))[..., None]
        eng[rip_m] = eng[rip_m] * (1.0 - rw) + np.array(ENG_HATCH, dtype=np.float32) * rw

    # 2. Carved 3-tone Bayer slate land relief
    n_grain = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=733, freq=0.032, octaves=3, sub=4)
    v_land = 0.42 + 0.13 * h_field + lit_field * 0.56 + (n_grain - 0.5) * 0.30
    eng_land_pal = np.stack([ENG_LAND0, ENG_LAND1, ENG_LAND2], axis=0)
    t_land = np.clip(np.floor(v_land * 3.0 + (bayer_c - 0.5) * 0.85), 0, 2).astype(np.int32)
    eng[land_m] = eng_land_pal[t_land[land_m]]

    # 3. Exact same razor-sharp plateau cliffs, Bayer cast shadows, sunlit NW carved edge & south wall faces
    band = 2.4
    sh_m = land_m & (side_cliff < 0.0) & (best_cliff < band) & (bayer_c < (1.0 - best_cliff / band) * 0.85)
    hi_m = land_m & (side_cliff > 0.0) & (best_cliff < 1.45)
    ink_m = land_m & (best_cliff < 0.74)
    face_m = land_m & (relief_kind == 1)
    eng[sh_m] = eng[sh_m] * 0.45 + ENG_ABYSS * 0.55
    eng[hi_m] = eng[hi_m] * 0.35 + np.array(ENG_RIDGE, dtype=np.float32) * 0.65
    eng[face_m] = eng[face_m] * 0.50 + ENG_ABYSS * 0.50
    eng[ink_m] = ENG_ABYSS

    # 4. Etched woodland canopies (stippled Bayer forest hatch + dark SE shadow + chiseled rim)
    f_sh = forest_shadow & (bayer_c < 0.75)
    eng[f_sh] = eng[f_sh] * 0.55 + ENG_ABYSS * 0.45
    f_stip = forest_m & (((cell_x ^ cell_y) & 1) == 0) & (bayer_shift < 0.55)
    eng[forest_m] = eng[forest_m] * 0.72 + ENG_LAND0 * 0.28
    eng[f_stip] = eng[f_stip] * 0.45 + np.array(ENG_HATCH, dtype=np.float32) * 0.55
    eng[forest_rim] = ENG_ABYSS

    # 5. Unified carved lakes & tributary rivers (single continuous hydraulic network, open at estuaries!)
    if np.any(in_water):
        dry_eng = land_m & (~in_water)
        w2d_e = _fast_mask_boundary_distance(dry_eng, factor=2)
        l_tone = np.clip(np.floor((1.0 - smoothstep_np(0.5, 18.0, w2d_e)) * 2.0 + (bayer_c - 0.5) * 0.7), 0, 2).astype(np.int32)
        eng[in_water] = eng_sea_pal[l_tone[in_water]]
        de_p = np.pad(dry_eng, 1, mode="edge")
        eng_nw = in_water & (de_p[:-2, 1:-1] | de_p[1:-1, :-2])
        eng_se = in_water & (de_p[2:, 1:-1] | de_p[1:-1, 2:]) & (~eng_nw)
        eng[eng_nw] = ENG_ABYSS
        eng[eng_se] = np.array(ENG_HATCH, dtype=np.float32)

    # 6. Fine dotted region/zone stitch ticks
    stitch_m = zone_frontier & (coast > 6.5) & (~in_water) & (((cell_x + cell_y) % 6) < 2)
    eng[stitch_m] = eng[stitch_m] * 0.45 + np.array(ENG_RIDGE, dtype=np.float32) * 0.55

    # 7. Crisp double carved coastline rim (opens cleanly at river estuaries!)
    mouth_eng = (in_water | (river_cov > 0.30)) & (coast < 12.0)
    if np.any(mouth_eng):
        me_p = np.pad(mouth_eng, 2, mode="constant", constant_values=False)
        mouth_eng = me_p[:-4, 2:-2] | me_p[4:, 2:-2] | me_p[2:-2, :-4] | me_p[2:-2, 4:] | mouth_eng
    coast_outer = land_m & (coast < 3.0) & (~mouth_eng)
    coast_inner = land_m & (coast >= 3.0) & (coast < 6.0) & (bayer_c < 0.78) & (~mouth_eng)
    eng[coast_inner] = ENG_ABYSS
    eng[coast_outer] = np.array(ENG_COAST, dtype=np.float32)

    # 8. Great Rift carved scar (ONLY if rift_pos is present)
    if rift_pos is not None:
        eng[rift_scorched] = ENG_ABYSS
        eng[rift_fissure] = np.array(ENG_BRIGHT, dtype=np.float32)

    # 9. Historical Stone-Setter old names metadata (collision-free positions exported to continent_meta.json;
    #    rendered in crisp 1:1 screen-space by AtlasView so filter_nearest downsampling never turns baked text into pixel crumbs!)
    eng_img = Image.fromarray(np.clip(np.round(eng), 1, 255).astype(np.uint8), mode="RGB").convert("RGBA")
    old_names: list[dict[str, Any]] = []
    placed_boxes: list[tuple[int, int, int, int]] = []

    def _place_engraved_label(text: str, cx_in: int, cy_in: int, col: tuple[int, int, int], scale: int) -> tuple[int, int]:
        norm = text.replace("ß", "SS").upper()
        tw_p = max(4, len(norm) * PIXEL_FONT_ADVANCE - 1) * scale + 10
        th_p = PIXEL_FONT_HEIGHT * scale + 8
        best_x, best_y = cx_in, cy_in
        for dy_try in (0, -24, 24, -48, 48, -72, 72, -96, 96):
            for dx_try in (0, -32, 32):
                tx_p = max(tw_p // 2 + 8, min(W - tw_p // 2 - 8, cx_in + dx_try))
                ty_p = max(th_p // 2 + 8, min(H - th_p // 2 - 8, cy_in + dy_try))
                bx0, by0, bx1, by1 = tx_p - tw_p // 2, ty_p - th_p // 2, tx_p + tw_p // 2, ty_p + th_p // 2
                hit_box = any(not (bx1 < ax0 or bx0 > ax1 or by1 < ay0 or by0 > ay1) for ax0, ay0, ax1, ay1 in placed_boxes)
                hit_rift = rift_pos is not None and math.hypot(tx_p - rift_pos[0], ty_p - rift_pos[1]) < max(48.0, rift_radius * 0.95)
                ix0, iy0, ix1, iy1 = max(0, bx0), max(0, by0), min(W, bx1), min(H, by1)
                hit_water = bool(np.any(in_water[iy0:iy1, ix0:ix1])) if (ix1 > ix0 and iy1 > iy0) else False
                on_land = bool(land_m[ty_p, tx_p])
                if on_land and not hit_box and not hit_rift and not hit_water:
                    best_x, best_y = tx_p, ty_p
                    break
            else:
                continue
            break
        placed_boxes.append((best_x - tw_p // 2, best_y - th_p // 2, best_x + tw_p // 2, best_y + th_p // 2))
        return (best_x, best_y)

    explicit_names = cont.raw.get("old_names") or []
    if explicit_names:
        for entry in explicit_names:
            if isinstance(entry, dict) and entry.get("text"):
                pos = as_vec2(entry.get("pos"))
                if pos is not None:
                    px_l, py_l = _place_engraved_label(str(entry["text"]), int(pos[0]), int(pos[1]), ENG_TEXT, 4)
                    old_names.append({"text": str(entry["text"]), "pos": [px_l, py_l]})
    else:
        for reg in cont.regions:
            rid = str(reg.get("id", ""))
            rname = str(reg.get("old_name", reg.get("name", ""))).strip()
            pts_r_list = []
            for zid in cont.zone_order:
                z = cont.zones[zid]
                if z.region_id == rid:
                    x0, y0, x1, y1 = z.bbox
                    pts_r_list.append(((x0 + x1) * 0.5, (y0 + y1) * 0.5))
            if rname and pts_r_list:
                rcx = int(round(sum(p[0] for p in pts_r_list) / len(pts_r_list)))
                rcy = int(round(sum(p[1] for p in pts_r_list) / len(pts_r_list))) - 36
                px_r, py_r = _place_engraved_label(rname, rcx, rcy, ENG_BRIGHT, 4)
                old_names.append({"text": rname, "pos": [px_r, py_r]})
        for zid in cont.zone_order:
            z = cont.zones[zid]
            x0, y0, x1, y1 = z.bbox
            zcx, zcy = int(round((x0 + x1) * 0.5)), int(round((y0 + y1) * 0.5))
            label = z.old_name or z.name
            px_z, py_z = _place_engraved_label(label, zcx, zcy, ENG_TEXT, 3)
            old_names.append({"text": label, "pos": [px_z, py_z]})

    eng_rgba = np.array(eng_img, dtype=np.uint8)
    eng_rgba = _sanitize_zero_black(eng_rgba)
    _assert_zero_black(eng_rgba, f"{cont.id}/engraving.png")
    return eng_rgba, old_names


def paint_continent(
    cont: ContinentData,
    land: PlannedLandscape,
    tree_cat: dict[str, dict[str, Any]],
    zone_bakes: dict[str, dict[str, Any]] | None = None,
) -> None:
    """Bakes continent_map.png, continent_light.png, engraving.png, and continent_meta.json in crisp Bayer pixel art."""
    W, H = cont.size
    gy, gx = np.mgrid[0:H, 0:W].astype(np.float32)
    gx += 0.5
    gy += 0.5

    fields = _load_or_synth_continental_fields(cont, gx, gy)
    coast = fields["coast"]
    land_m = fields["land_m"]
    sea_m = ~land_m
    outside_dist = fields["outside_dist"]
    field = fields["field"]
    relief_kind = fields["relief_kind"]
    relief_style = fields["relief_style"]
    water_rgb = fields["water_rgb"]
    lake_sdf_u8 = fields["lake_sdf_u8"]
    lake_inset = fields["lake_inset"]
    areas_raw = fields["areas_raw"]
    area_lut = fields["area_lut"]
    islet_raw = fields.get("islet_raw", np.zeros((H, W), dtype=bool))

    cell_px = CONT_BAYER_CELL
    bayer_c = bayer_grid(H, W, cell=cell_px, ox=0, oy=0)
    bayer_shift = bayer_grid(H, W, cell=cell_px, ox=cell_px, oy=cell_px)

    # 1. 5-Tone Bayer-Dithered Deep Pixel-Art Ocean + 3 Undulating Coastal Ripples (returns swell fields shared with lakes & rivers!)
    cmap_rgb, ocean_a, ocean_b = _render_pixel_ocean(W, H, gx, gy, outside_dist, bayer_c, bayer_shift, cell_px=cell_px)

    # 2. Organic Domain-Warped Biome Lookup + 3-Tone Bayer-Dithered Land (exact map.mjs lines 163-184 & 371-398)
    wx_slow = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=164, freq=0.0065, octaves=3, sub=4) - 0.5) * 96.0
    wy_slow = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=179, freq=0.0065, octaves=3, sub=4) - 0.5) * 96.0
    wx_mid = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=191, freq=0.042, octaves=1, sub=2) - 0.5) * 26.0
    wy_mid = (fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=199, freq=0.042, octaves=1, sub=2) - 0.5) * 26.0
    awx = np.clip(np.rint(gx - 0.5 + wx_slow + wx_mid).astype(np.int32), 0, W - 1)
    awy = np.clip(np.rint(gy - 0.5 + wy_slow + wy_mid).astype(np.int32), 0, H - 1)

    def _sample_area_at(ix: np.ndarray, iy: np.ndarray) -> np.ndarray:
        a = areas_raw[iy, ix].copy()
        zero = a == 0
        if np.any(zero):
            orig_y = np.arange(H, dtype=np.int32)[:, None]
            orig_x = np.arange(W, dtype=np.int32)[None, :]
            a = np.where(a == 0, areas_raw[orig_y, orig_x], a)
            for off in (10, 24, 48):
                z2 = (a == 0) & land_m
                if not np.any(z2):
                    break
                for ox_s, oy_s in ((off, 0), (-off, 0), (0, off), (0, -off)):
                    a = np.where(a == 0, areas_raw[np.clip(iy + oy_s, 0, H - 1), np.clip(ix + ox_s, 0, W - 1)], a)
        return a

    # Offshore islets keep their EXACT inherited coastal biome from continental_areas.png (no mainland warp bleed!)
    area_id = np.where(islet_raw & (areas_raw > 0), areas_raw, _sample_area_at(awx, awy))
    biome_idx = area_lut[area_id]

    # Wide organic ecotone Bayer blend across warped mainland region borders (suppressed on islets)
    aN = area_lut[_sample_area_at(awx, np.clip(awy - 14, 0, H - 1))]
    aS = area_lut[_sample_area_at(awx, np.clip(awy + 14, 0, H - 1))]
    aW = area_lut[_sample_area_at(np.clip(awx - 14, 0, W - 1), awy)]
    aE = area_lut[_sample_area_at(np.clip(awx + 14, 0, W - 1), awy)]
    border_hits = (
        (aN != biome_idx).astype(np.float32)
        + (aS != biome_idx).astype(np.float32)
        + (aW != biome_idx).astype(np.float32)
        + (aE != biome_idx).astype(np.float32)
    )
    blend_biome = np.where(aN != biome_idx, aN, np.where(aS != biome_idx, aS, np.where(aW != biome_idx, aW, aE)))

    # Directional hillshade & organic pixel grain (exact map.mjs lines 388-398)
    h_field = field[..., 0] + field[..., 1] + field[..., 2]
    e_lit = 3
    h_pad = np.pad(h_field, e_lit, mode="edge")
    lit_field = h_pad[2 * e_lit:, 2 * e_lit:] - h_pad[:-2 * e_lit, :-2 * e_lit]
    n_grain_lo = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=389, freq=0.032, octaves=3, sub=4)
    n_grain_hi = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=397, freq=0.28, octaves=1, sub=2)
    grain = (n_grain_lo - 0.5) * 0.36 + (n_grain_hi - 0.5) * 0.12
    v_val = 0.42 + 0.11 * h_field + lit_field * 0.58 + grain + np.where(islet_raw, 0.07, 0.0)
    tone = np.clip(np.floor(v_val * 3.0 + (bayer_c - 0.5) * 0.88), 0, 2).astype(np.int32)

    land_rgb = BIOME_PALETTES[biome_idx, tone]
    ecotone_m = (~islet_raw) & (blend_biome != biome_idx) & (bayer_c < border_hits * 0.22)
    if np.any(ecotone_m):
        land_rgb[ecotone_m] = BIOME_PALETTES[blend_biome[ecotone_m], tone[ecotone_m]]

    # High-plateau pale rock / Klangstein accents on Glaskamm & Kristallgrat summit ridges ONLY
    klang_m = land_m & ((biome_idx == 1) | (biome_idx == 5)) & (
        (h_field > 1.95) | (relief_style == 3)
    )
    if np.any(klang_m):
        kt = np.clip(
            0.34 + (h_field[klang_m] - 2.05) * 0.24 + lit_field[klang_m] * 0.58 + (n_grain_lo[klang_m] - 0.5) * 0.52 + (n_grain_hi[klang_m] - 0.5) * 0.18,
            0.0,
            1.0,
        )
        klang_c = bayer_quantize_ramp(KLANGSTEIN_PAL, kt, bayer_c[klang_m], spread=0.88)
        k_blend = smoothstep_np(1.85, 2.55, h_field[klang_m])
        k_take = bayer_shift[klang_m] < np.maximum(k_blend, np.where((relief_style[klang_m] == 3), 0.72, 0.35))
        if np.any(k_take):
            ky, kx = np.nonzero(klang_m)
            land_rgb[ky[k_take], kx[k_take]] = klang_c[k_take]

    cmap_rgb[land_m] = land_rgb[land_m]

    # Subtle coastal dry sand crescent inside explicit beach zones (e.g. Windkap Silberbucht)
    for zid in cont.zone_order:
        z = cont.zones[zid]
        w_dict = z.raw.get("water") if isinstance(z.raw.get("water"), dict) else {}
        if isinstance(w_dict.get("coast"), dict):
            x0, y0, x1, y1 = [int(v) for v in z.bbox]
            x0c, y0c, x1c, y1c = max(0, x0 - 4), max(0, y0 - 4), min(W, x1 + 5), min(H, y1 + 5)
            if x1c > x0c and y1c > y0c:
                sub_c = coast[y0c:y1c, x0c:x1c]
                sub_h = h_field[y0c:y1c, x0c:x1c]
                sub_g = n_grain_hi[y0c:y1c, x0c:x1c]
                sub_b = bayer_c[y0c:y1c, x0c:x1c]
                beach_c = (sub_c >= 3.0) & (sub_c <= 8.5) & (sub_h < 0.35)
                if np.any(beach_c):
                    s_col = bayer_quantize_ramp(BEACH_DRY, np.clip(0.35 + sub_g * 0.5, 0.0, 1.0), sub_b, spread=0.82)
                    cmap_rgb[y0c:y1c, x0c:x1c][beach_c] = s_col[beach_c]

    # 3. Razor-Sharp Inked Plateau Contours, Lit NW Rim, Bayer Cast Shadows & South Wall Faces (map.mjs lines 400-433!)
    ps = CONT_PIX_STEP
    f_pad_x = np.pad(field, ((0, 0), (1, ps - 1), (0, 0)), mode="edge")
    f_pad_y = np.pad(field, ((1, ps - 1), (0, 0), (0, 0)), mode="edge")
    df_x = f_pad_x[:, ps:, :] - f_pad_x[:, :-ps, :]
    df_y = f_pad_y[ps:, :, :] - f_pad_y[:-ps, :, :]

    best_cliff = np.full((H, W), 99.0, dtype=np.float32)
    side_cliff = np.zeros((H, W), dtype=np.float32)
    for k in range(3):
        n_ck = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=411 + k * 37, freq=0.24, octaves=1, sub=2)
        c_val = field[..., k] - 0.5 + (n_ck - 0.5) * 0.10
        g_k = np.maximum(np.hypot(df_x[..., k], df_y[..., k]), 0.0045)
        d_k = np.abs(c_val) / g_k
        better = d_k < best_cliff
        best_cliff = np.where(better, d_k, best_cliff)
        side_cliff = np.where(better, c_val, side_cliff)

    alpha_mask = np.full((H, W), BIT_VALID, dtype=np.uint8)
    alpha_mask[sea_m] |= np.uint8(BIT_WATER)

    band = 2.4
    tone0_rgb = BIOME_PALETTES[biome_idx, 0]
    tone2_rgb = BIOME_PALETTES[biome_idx, 2]
    shad_m = land_m & (side_cliff < 0.0) & (best_cliff < band) & (bayer_c < (1.0 - best_cliff / band) * 0.85)
    rim_hi_m = land_m & (side_cliff > 0.0) & (best_cliff < 1.45) & (~shad_m)
    ink_cliff_m = land_m & (best_cliff < 0.74)

    cmap_rgb[shad_m] = cmap_rgb[shad_m] * 0.24 + (tone0_rgb[shad_m] * 0.68) * 0.76
    cmap_rgb[rim_hi_m] = cmap_rgb[rim_hi_m] * 0.66 + tone2_rgb[rim_hi_m] * 0.34
    cmap_rgb[ink_cliff_m] = INK_PIXEL * 0.80 + tone0_rgb[ink_cliff_m] * 0.20
    alpha_mask[ink_cliff_m] |= np.uint8(BIT_INK_CLIFF)

    # 2-tile south wall faces (kind == 1) & dashed ramps/stairs (kind 2..4)
    face_m = land_m & (relief_kind == 1)
    cmap_rgb[face_m] = cmap_rgb[face_m] * 0.66 + INK_PIXEL * 0.34
    alpha_mask[face_m] |= np.uint8(BIT_INK_CLIFF)

    cell_x = np.arange(W, dtype=np.int32)[None, :] // max(1, cell_px)
    cell_y = np.arange(H, dtype=np.int32)[:, None] // max(1, cell_px)
    conn_m = land_m & (relief_kind >= 2) & (relief_kind <= 4) & (((cell_y + (cell_x >> 1)) % 3) < 2)
    if np.any(conn_m):
        cmap_rgb[conn_m] = cmap_rgb[conn_m] * 0.28 + np.array([214.0, 189.0, 153.0], dtype=np.float32) * 0.72
        alpha_mask[conn_m] |= np.uint8(BIT_SAND_WAY)

    # Precompute inland water mask & road mask for clean layering
    river_cov = water_rgb[..., 0]
    river_dep = water_rgb[..., 1]
    lake_dep = water_rgb[..., 2]
    in_lake = land_m & ((lake_inset > 0.0) | (lake_dep > 0.10))
    in_river = land_m & (~in_lake) & (river_cov > 0.08)
    in_water = in_lake | in_river

    # Ancient caravan ways across continent (organically meandered, respecting steep cliffs & water!)
    path_cov = np.zeros((H, W), dtype=np.float32)
    for w_i, w in enumerate(cont.landscape_raw.get("ways") or []):
        if isinstance(w, dict) and len(as_poly(w.get("pts", []))) >= 2:
            raw_wp = as_poly(w["pts"])
            sm_w = _meander_polyline(raw_wp, seed=int(w.get("seed", 263)) + w_i * 41, amp=7.5, freq=0.022, subdiv=10)
            sa = np.array(sm_w[:-1], dtype=np.float32)
            sb = np.array(sm_w[1:], dtype=np.float32)
            wd, _ = fast_narrowband_segments_distance(W, H, 0.0, 0.0, 1.0, sa, sb, 3.0)
            path_cov = np.maximum(path_cov, 1.0 - smoothstep_np(0.8, 2.2, wd))
    path_m = land_m & (~in_water) & (best_cliff > 0.90) & (relief_kind != 1) & (path_cov > 0.18)

    # 4. Cohesive Pixel-Art Woodland Canopy Carpets (NO cauliflower polka dots, NO zone hedge rings!)
    forest_m, canopy_h, canopy_lit, forest_rim, forest_shadow = _build_forest_carpet(
        cont, land_m, coast, best_cliff, relief_kind, in_water, path_m, W, H
    )
    if np.any(forest_m):
        f_sh_m = forest_shadow & (bayer_c < 0.78)
        cmap_rgb[f_sh_m] = cmap_rgb[f_sh_m] * 0.42 + INK_PIXEL * 0.58
        canopy_v = np.clip(0.42 + 0.34 * canopy_h + 0.92 * canopy_lit, 0.0, 1.0)
        c_tone = np.clip(np.floor(canopy_v * 3.0 + (bayer_c - 0.5) * 0.86), 0, 2).astype(np.int32)
        cmap_rgb[forest_m] = CANOPY_PALETTES[biome_idx[forest_m], c_tone[forest_m]]
        crevice = forest_m & (canopy_h < 0.25) & (canopy_lit < -0.04) & (bayer_shift < 0.65)
        cmap_rgb[crevice] = cmap_rgb[crevice] * 0.40 + INK_PIXEL * 0.60
        cmap_rgb[forest_rim] = INK_PIXEL * 0.68 + CANOPY_PALETTES[biome_idx[forest_rim], 0] * 0.32
        alpha_mask[forest_m] |= np.uint8(BIT_CANOPY)

    # 5. Subtle Ancient Trails & Caravan Paths (softly inked earthy parchment)
    if np.any(path_m):
        road_col = np.where((biome_idx == 6)[..., None], np.array([224.0, 189.0, 128.0], dtype=np.float32), np.array([186.0, 162.0, 126.0], dtype=np.float32))
        pm = (smoothstep_np(0.15, 0.72, path_cov[path_m]) * 0.44)[..., None]
        cmap_rgb[path_m] = cmap_rgb[path_m] * (1.0 - pm) + road_col[path_m] * pm
        alpha_mask[path_m] |= np.uint8(BIT_SAND_WAY)

    # 6. Subtle Dotted Cartographer Zone/Territory Borders (2px stitch, map.mjs line 453 — NEVER hedge rings!)
    zones_raw = fields.get("zones_raw")
    max_zid = len(cont.zone_order)
    if zones_raw is not None:
        zone_id_grid = np.where((zones_raw >= 1) & (zones_raw <= max_zid), zones_raw, 0).astype(np.int16)
    else:
        zone_id_grid = np.zeros((H, W), dtype=np.int16)
        for z_idx, zid in enumerate(cont.zone_order):
            z = cont.zones[zid]
            x0, y0, x1, y1 = [int(v) for v in z.bbox]
            x0c, y0c, x1c, y1c = max(0, x0), max(0, y0), min(W, x1 + 1), min(H, y1 + 1)
            if x1c > x0c and y1c > y0c:
                zm = rasterize_polygon_mask(x1c - x0c, y1c - y0c, float(x0c), float(y0c), 1.0, z.footprint)
                zone_id_grid[y0c:y1c, x0c:x1c][zm] = z_idx + 1
    zp = np.pad(zone_id_grid, ((0, ps), (0, ps)), mode="edge")
    zr = zp[:-ps, ps:]
    zd = zp[ps:, :-ps]
    zone_frontier = land_m & (zone_id_grid > 0) & (
        ((zr > 0) & (zr != zone_id_grid)) | ((zd > 0) & (zd != zone_id_grid))
    )
    stitch_m = zone_frontier & (coast > 7.5) & (~in_water) & (((cell_x + cell_y) % 6) < 2)
    if np.any(stitch_m):
        dash_col = np.array([228.0, 212.0, 246.0], dtype=np.float32)
        cmap_rgb[stitch_m] = cmap_rgb[stitch_m] * 0.62 + dash_col * 0.38

    # 7. Unified Ocean-Style Inland Water (Lakes & Rivers = EXACT same deep Bayer ocean water, ZERO thick cyan sticker rings!)
    in_river_draw = land_m & (~in_lake) & (river_cov > 0.12)
    in_water_draw = in_lake | in_river_draw
    dry_land = land_m & (~in_water_draw)
    if np.any(in_water_draw):
        # Continuous distance from ANY water pixel (sea, estuary, river, lake) to dry land!
        # Stays HIGH right across river-lake confluences AND sea estuary openings -> 100% seamless connected waterways!
        water_to_land = _fast_mask_boundary_distance(dry_land, factor=2)
        bath_geom = smoothstep_np(0.5, 22.0, water_to_land)
        bath_w = np.clip(bath_geom * 0.65 + np.clip(river_dep, 0.0, 1.0) * 0.35, 0.0, 1.0)

        # Shared ocean swell (ocean_a, ocean_b) + OCEAN1..4 + OCEAN_RIDGE shallow shelf — exact match to surrounding sea!
        inland_ocean_pal = np.stack([OCEAN1, OCEAN2, OCEAN3, OCEAN4, OCEAN_RIDGE], axis=0)
        t_w = ocean_a * 2.45 - 0.35 + (1.0 - bath_w) * 1.95 + (bayer_c - 0.5) * 0.86
        kw = np.clip(np.floor(t_w), 0, 4).astype(np.int32)
        w_rgb = inland_ocean_pal[kw].copy()

        # Subtle Bayer ocean-ridge swell streaks inside open lakes & wide estuaries
        w_ridge = 1.0 - smoothstep_np(0.0, 0.017, np.abs(ocean_b - 0.5))
        w_rdg_m = in_water_draw & (water_to_land > 3.5) & (w_ridge > 0.50) & (ocean_a > 0.45) & (bayer_shift < 0.54)
        if np.any(w_rdg_m):
            w_rgb[w_rdg_m] = w_rgb[w_rdg_m] * 0.68 + OCEAN_RIDGE * 0.32

        # Sparse hand-inked 1px wave crests on open lakes & wide estuaries (exact ocean language!)
        _stamp_wave_marks(
            w_rgb,
            in_water_draw & (water_to_land > 7.5),
            water_to_land,
            W,
            H,
            spacing=54,
            min_inset=8.5,
            light_col=RIPPLE_TINT,
            alpha_crest=0.40,
            alpha_echo=0.18,
            px_size=max(2, cell_px - 1),
            seed=181,
        )

        # Delicate 1px natural shoreline ONLY where inland water touches dry land (NO thick cyan ring, NO black sausage!)
        # Concave basin lighting (matching reference DIE LICHTUNG lakes):
        #   - NW shore drops into shadow (1px recessed INK/OCEAN0 edge inside water)
        #   - SE shore catches soft NW light (whisper-thin 1px RIPPLE_TINT edge inside water)
        dp = np.pad(dry_land, 1, mode="edge")
        touch_nw = in_water_draw & (dp[:-2, 1:-1] | dp[1:-1, :-2])
        touch_se = in_water_draw & (dp[2:, 1:-1] | dp[1:-1, 2:]) & (~touch_nw)
        w_rgb[touch_nw] = w_rgb[touch_nw] * 0.46 + INK_PIXEL * 0.54
        w_rgb[touch_se] = w_rgb[touch_se] * 0.62 + RIPPLE_TINT * 0.38

        # Whisper-soft 1px dry-land lip only on NW-shaded banks so water sits recessed naturally in the grass/earth
        wp_d = np.pad(in_water_draw, 1, mode="constant", constant_values=False)
        land_lip = dry_land & (wp_d[2:, 1:-1] | wp_d[1:-1, 2:]) & (coast >= 5.0)
        cmap_rgb[land_lip] = cmap_rgb[land_lip] * 0.78 + INK_PIXEL * 0.22
        cmap_rgb[in_water_draw] = w_rgb[in_water_draw]

    # Miniature biome-matched shrub/grove tufts on larger offshore islets so skerries feel alive
    islet_grove_n = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=577, freq=0.16, octaves=2, sub=2)
    islet_grove = (
        islet_raw
        & land_m
        & (coast > 5.0)
        & (~in_water_draw)
        & ((biome_idx == 0) | (biome_idx == 1) | (biome_idx == 2) | (biome_idx == 4))
        & (islet_grove_n > 0.55)
    )
    if np.any(islet_grove):
        ig_t = np.clip(np.floor((islet_grove_n[islet_grove] - 0.55) * 6.5 + (bayer_c[islet_grove] - 0.5) * 0.8), 0, 2).astype(np.int32)
        cmap_rgb[islet_grove] = CANOPY_PALETTES[biome_idx[islet_grove], ig_t]
        pig = np.pad(islet_grove, 1, mode="constant", constant_values=False)
        ig_sh = islet_raw & (~islet_grove) & pig[:-2, :-2]
        cmap_rgb[ig_sh] = cmap_rgb[ig_sh] * 0.55 + INK_PIXEL * 0.45
        alpha_mask[islet_grove] |= np.uint8(BIT_CANOPY)

    in_water = in_water_draw
    alpha_mask[in_water] = (alpha_mask[in_water] & np.uint8(255 ^ (BIT_MEADOW | BIT_CANOPY))) | np.uint8(BIT_WATER | BIT_VALID)

    # 8. Great Rift Crystalline Wound (Eastern Varnholm / Leerenblühen + subtle rift splinter traces on nearby east islets!)
    rift_pos, rift_radius, rift_edge = _detect_great_rift(cont)
    rift_scorched = np.zeros((H, W), dtype=bool)
    rift_fissure = np.zeros((H, W), dtype=bool)
    eng_dummy = np.zeros((H, W, 3), dtype=np.float32)
    if rift_pos is not None:
        rift_scorched, rift_fissure = _render_great_rift_pixel_art(
            cmap_rgb, eng_dummy, alpha_mask, land_m, outside_dist, W, H, gx, gy, bayer_c, rift_pos, rift_radius, rift_edge
        )
        # Subtle restrained crystalline rift-corruption traces on offshore Leerenblühen islets facing the Great Rift
        dist_to_rift = np.hypot(gx - rift_pos[0], gy - rift_pos[1])
        rift_islet_reach = max(rift_radius * 3.0, 265.0)
        east_rift_islet = islet_raw & land_m & (biome_idx == 3) & (
            (dist_to_rift <= rift_islet_reach) | (relief_style == 3)
        )
        if np.any(east_rift_islet):
            n_iv = fbm2d_grid(W, H, 0.0, 0.0, 1.0, seed=1451, freq=0.095, octaves=3, sub=2)
            prox_r = np.clip(1.0 - dist_to_rift / rift_islet_reach, 0.25, 1.0)
            i_scorch = east_rift_islet & (bayer_c < prox_r * 0.55) & (n_iv < 0.52)
            i_vein = east_rift_islet & (np.abs(n_iv - 0.5) < (0.018 + 0.024 * prox_r))
            cmap_rgb[i_scorch] = cmap_rgb[i_scorch] * 0.42 + np.array([28.0, 14.0, 52.0], dtype=np.float32) * 0.58
            cmap_rgb[i_vein] = np.where(
                (bayer_c[i_vein] < 0.50)[..., None],
                np.array([242.0, 84.0, 214.0], dtype=np.float32),
                np.array([154.0, 92.0, 236.0], dtype=np.float32),
            )
            alpha_mask[i_vein] |= np.uint8(BIT_GLOW_ARCANE)
            rift_fissure |= i_vein

    # 9. Etched 5x5 Cartographer GLYPHS on flat open plateaus (map.mjs lines 204-234!)
    _stamp_cartographer_glyphs(
        cmap_rgb, land_m, coast, best_cliff, in_water, forest_m, path_m, rift_scorched, biome_idx,
        W, H, spacing=44, px_size=2,
    )

    # 10. Illuminated Turquoise-Silver Coastline Rim & Inner INK Bank (opens cleanly at river estuaries; tighter on islets!)
    mouth_gap = (in_water | (river_cov > 0.30)) & (coast < 12.0)
    if np.any(mouth_gap):
        mg_p = np.pad(mouth_gap, 3, mode="constant", constant_values=False)
        mouth_gap = mg_p[:-6, 3:-3] | mg_p[6:, 3:-3] | mg_p[3:-3, :-6] | mg_p[3:-3, 6:] | mouth_gap
    rim_w = np.where(islet_raw, 2.0, 3.0)
    ink_w = np.where(islet_raw, 3.8, 6.2)
    coast_rim_m = land_m & (coast < rim_w) & (~rift_scorched) & (~mouth_gap) & (~in_water)
    coast_ink_m = land_m & (coast >= rim_w) & (coast < ink_w) & (bayer_c < 0.72) & (~rift_scorched) & (~mouth_gap) & (~in_water)
    cmap_rgb[coast_ink_m] = cmap_rgb[coast_ink_m] * 0.34 + INK_PIXEL * 0.66
    cmap_rgb[coast_rim_m] = COAST_RIM
    alpha_mask[coast_ink_m] |= np.uint8(BIT_INK_CLIFF)

    # Finalize MEADOW bit on dry open land
    meadow_land = land_m & (~in_water) & ((alpha_mask & (BIT_CANOPY | BIT_SAND_WAY | BIT_INK_CLIFF | BIT_GLOW_ARCANE)) == 0)
    alpha_mask[meadow_land] |= np.uint8(BIT_MEADOW)

    # 11. Continent Light Map (`continent_light.png` — exact contract locked with @atlas-shader-artist!)
    #   - Deep open sea (outside_dist > 54 or outer 24px margin): B = 0 (< 0.012)
    #   - Coastal surf/ripple sea (0 < outside_dist <= 54): B in [0.016..0.094] (in [0.012, 0.16))
    #   - Inland lakes & rivers: B in [0.195..0.230] (>= 0.16, BIT_WATER set)
    #   - Land: B in [0.28..0.98] (>= 0.25, BIT_WATER unset)
    edge_margin = np.minimum(np.minimum(gx, W - gx), np.minimum(gy, H - gy))
    elev_sea = np.where(
        (outside_dist <= 54.0) & (edge_margin > 24.0),
        0.016 + 0.078 * (1.0 - smoothstep_np(0.0, 54.0, outside_dist)),
        0.0,
    )
    elev_inland_w = np.clip(0.230 - np.maximum(lake_dep, river_dep) * 0.035, 0.195, 0.230)
    elev_land = np.clip(0.28 + h_field * 0.21 + (n_grain_lo - 0.5) * 0.04, 0.26, 0.98)
    elev = np.where(sea_m, elev_sea, np.where(in_water, elev_inland_w, elev_land))

    # Smooth terrain normals on land, neutral (0, 0) on water
    elev_n = box_blur_3x3(np.where(land_m, elev_land, 0.24), passes=1)
    gy_e, gx_e = np.gradient(elev_n)
    nx_f = -gx_e * 18.0
    ny_f = -gy_e * 18.0
    nl = np.sqrt(nx_f * nx_f + ny_f * ny_f + 1.0)
    nx_arr = np.where(land_m & (~in_water), nx_f / nl, 0.0)
    ny_arr = np.where(land_m & (~in_water), ny_f / nl, 0.0)

    cmap_rgba = np.zeros((H, W, 4), dtype=np.uint8)
    cmap_rgba[..., :3] = np.clip(np.round(cmap_rgb), 1, 255).astype(np.uint8)
    cmap_rgba[..., 3] = 255
    cmap_rgba = _sanitize_zero_black(cmap_rgba)
    _assert_zero_black(cmap_rgba, f"{cont.id}/continent_map.png")

    clight_rgba = np.zeros((H, W, 4), dtype=np.uint8)
    clight_rgba[..., 0] = np.clip(np.round((nx_arr * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)
    clight_rgba[..., 1] = np.clip(np.round((ny_arr * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)
    clight_rgba[..., 2] = np.clip(np.round(np.clip(elev, 0.0, 1.0) * 255.0), 0, 255).astype(np.uint8)
    clight_rgba[..., 3] = alpha_mask
    clight_rgba = _sanitize_zero_black(clight_rgba)
    _assert_zero_black(clight_rgba, f"{cont.id}/continent_light.png")

    # 12. Monochrome Stone-Setter Engraving (`engraving.png`)
    eng_rgba, old_names = _render_stone_setter_engraving(
        cont, W, H, gx, gy, fields, bayer_c, bayer_shift,
        h_field, lit_field, best_cliff, side_cliff,
        forest_m, forest_rim, forest_shadow,
        in_lake, river_cov, in_water, zone_frontier,
        rift_pos, rift_radius, rift_scorched, rift_fissure,
        cell_px=cell_px,
    )

    # Preserve ocean_currents metadata schema in continent_meta.json
    ocean_currents: list[list[list[int]]] = []
    ocean_obj = cont.raw.get("ocean")
    if isinstance(ocean_obj, dict) and isinstance(ocean_obj.get("currents"), list):
        for cur in ocean_obj["currents"]:
            if isinstance(cur, dict) and cur.get("pts"):
                pts_c = [[int(round(p[0])), int(round(p[1]))] for p in as_poly(cur["pts"])]
                if len(pts_c) >= 2:
                    ocean_currents.append(pts_c)
            elif isinstance(cur, list) and len(cur) >= 2:
                pts_c = [[int(round(p[0])), int(round(p[1]))] for p in as_poly(cur)]
                if len(pts_c) >= 2:
                    ocean_currents.append(pts_c)

    cmeta = {
        "continent_id": cont.id,
        "size": [W, H],
        "px_per_tile": CONTINENT_PX_PER_TILE,
        "light_alpha_bits": LIGHT_ALPHA_BITS,
        "rift_pos": [round(rift_pos[0], 1), round(rift_pos[1], 1)] if rift_pos is not None else None,
        "rift_radius": round(rift_radius, 1) if rift_pos is not None else 0.0,
        "ocean_currents": ocean_currents,
        "old_names": old_names,
    }

    out_dir = cont.world_dir / "continents" / "baked" / cont.id
    out_dir.mkdir(parents=True, exist_ok=True)
    Image.fromarray(cmap_rgba, mode="RGBA").save(out_dir / "continent_map.png", compress_level=1)
    Image.fromarray(clight_rgba, mode="RGBA").save(out_dir / "continent_light.png", compress_level=1)
    Image.fromarray(eng_rgba, mode="RGBA").save(out_dir / "engraving.png", compress_level=1)
    with (out_dir / "continent_meta.json").open("w", encoding="utf-8") as f:
        json.dump(cmeta, f, indent=2)



# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------

def _load_trees_override(path: pathlib.Path) -> dict[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        return {"*": data}
    if isinstance(data, dict) and "trees" in data and isinstance(data["trees"], list):
        return {"*": data["trees"]}
    if isinstance(data, dict):
        return {str(k): v for k, v in data.items() if isinstance(v, list)}
    raise ValueError(f"Unsupported --trees-json format in {path}")


_MP_CONT: ContinentData | None = None
_MP_LAND: PlannedLandscape | None = None
_MP_CAT: dict[str, dict[str, Any]] | None = None


def _mp_init(world_dir_s: str, data_dir_s: str, cid: str, trees_list: list[dict[str, Any]]) -> None:
    global _MP_CONT, _MP_LAND, _MP_CAT
    wdir = pathlib.Path(world_dir_s)
    ddir = pathlib.Path(data_dir_s)
    _MP_CONT = load_atlas(wdir, ddir)[cid]
    _MP_LAND = PlannedLandscape(_MP_CONT, trees_override=trees_list)
    _MP_CAT = load_tree_catalog(ddir)


def _mp_bake_zone(zid: str) -> str:
    assert _MP_CONT is not None and _MP_LAND is not None and _MP_CAT is not None
    paint_zone(_MP_CONT, _MP_LAND, _MP_CONT.zones[zid], _MP_CAT, write_outputs=True)
    return zid


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Shadowspore v2 Zone & Continent Map Painter")
    parser.add_argument("zone_id", nargs="?", help="Single zone ID to bake")
    parser.add_argument("--all", action="store_true", help="Bake all zones (and continent composite/engraving)")
    parser.add_argument("--continent", type=str, default=None, help="Continent ID to bake or restrict --all to")
    parser.add_argument("--trees-json", type=str, default=None, help="Optional JSON file overriding/comparing planned trees")
    parser.add_argument("--world-dir", type=str, default=None, help="Override data/world directory (for isolated tests)")
    args = parser.parse_args(argv)

    if not args.all and not args.continent and not args.zone_id:
        parser.error("Provide <zone_id>, --continent <id>, or --all")

    world_dir = pathlib.Path(args.world_dir).resolve() if args.world_dir else DEFAULT_WORLD_DIR
    data_dir = DEFAULT_DATA_DIR
    continents = load_atlas(world_dir, data_dir)
    tree_cat = load_tree_catalog(data_dir)

    trees_ov_map: dict[str, list[dict[str, Any]]] | None = None
    if args.trees_json:
        tpath = pathlib.Path(args.trees_json)
        if not tpath.exists():
            print(f"Error: --trees-json file not found: {tpath}", file=sys.stderr)
            return 2
        trees_ov_map = _load_trees_override(tpath)

    def trees_for_continent(cid: str) -> list[dict[str, Any]] | None:
        if trees_ov_map is None:
            return None
        if "*" in trees_ov_map:
            return trees_ov_map["*"]
        return trees_ov_map.get(cid)

    # Single zone mode
    if args.zone_id and not args.all and not args.continent:
        target_cont: ContinentData | None = None
        for c in continents.values():
            if args.zone_id in c.zones:
                target_cont = c
                break
        if target_cont is None:
            print(f"Error: zone '{args.zone_id}' not found in any continent in {world_dir / 'atlas.json'}", file=sys.stderr)
            return 1
        t0 = time.perf_counter()
        land = PlannedLandscape(
            target_cont,
            trees_override=trees_for_continent(target_cont.id),
            target_zone_id=args.zone_id,
        )
        z = target_cont.zones[args.zone_id]
        paint_zone(target_cont, land, z, tree_cat, write_outputs=True)
        dt = time.perf_counter() - t0
        print(f"[paint_zone_map] Baked zone '{z.id}' ({z.size[0]*PX_PER_TILE}x{z.size[1]*PX_PER_TILE}) in {dt:.2f}s")
        return 0

    # Continent validation if specified
    if args.continent and args.continent not in continents:
        print(f"Error: continent '{args.continent}' not found in {world_dir / 'atlas.json'}", file=sys.stderr)
        return 1

    target_cids = [args.continent] if args.continent else list(continents.keys())
    n_workers = min(6, max(1, os.cpu_count() or 1))
    for cid in target_cids:
        cont = continents[cid]
        t0 = time.perf_counter()
        t_ov = trees_for_continent(cid)
        needs_land = args.all or any(
            not ((cont.world_dir / "zones" / zid / "baked" / "map.png").exists() and (cont.world_dir / "zones" / zid / "baked" / "map_light.png").exists())
            for zid in cont.zone_order
        )
        land = PlannedLandscape(cont, trees_override=t_ov) if needs_land else None
        bakes: dict[str, dict[str, Any]] = {}
        if args.all:
            assert land is not None
            if n_workers > 1 and len(cont.zone_order) > 1:
                ordered = sorted(cont.zone_order, key=lambda zid: cont.zones[zid].size[0] * cont.zones[zid].size[1], reverse=True)
                with ThreadPoolExecutor(max_workers=min(4, n_workers, len(cont.zone_order))) as pool:
                    futs = {
                        zid: pool.submit(paint_zone, cont, land, cont.zones[zid], tree_cat, True)
                        for zid in ordered
                    }
                    for zid in cont.zone_order:
                        bakes[zid] = futs[zid].result()
                        z = cont.zones[zid]
                        print(f"[paint_zone_map] Baked zone '{zid}' ({z.size[0]*PX_PER_TILE}x{z.size[1]*PX_PER_TILE})")
            else:
                for zid in cont.zone_order:
                    z = cont.zones[zid]
                    bakes[zid] = paint_zone(cont, land, z, tree_cat, write_outputs=True)
                    print(f"[paint_zone_map] Baked zone '{zid}' ({z.size[0]*PX_PER_TILE}x{z.size[1]*PX_PER_TILE})")
        paint_continent(cont, land, tree_cat, zone_bakes=bakes if bakes else None)  # type: ignore[arg-type]
        dt = time.perf_counter() - t0
        print(f"[paint_zone_map] Baked continent '{cid}' ({cont.size[0]}x{cont.size[1]}) in {dt:.2f}s")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
