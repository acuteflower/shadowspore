#!/usr/bin/env python3
"""Generate hand-crafted pixel-art Skill Tree Medallions, Diamond Echo Crystals,
Center Veil Core, and 18x18 Ability Icons for Shadowspore's Feldcodex (CHARAKTER -> TALENTE).

Outputs:
  - assets/ui/skill_medallions.png (256x144 nearest-filtered sprite sheet)
  - docs/img/skill_medallions_4x.png (4x visual inspection sheet)

Palette & craft follow docs/design_guide.md & shadowspore-pixel-art skill:
  - Tinted obsidian outline (#0b0716), zero pure #000000
  - Top-left lighting, 3-4 tonal steps per material, clean intentional clusters
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEET_W = 256
SHEET_H = 144

CLEAR = (0, 0, 0, 0)
OUTLINE = (11, 7, 22, 255)       # #0b0716

# Obsidian & Iron (locked / dormant)
IRON_0 = (16, 13, 29, 255)
IRON_1 = (28, 23, 48, 255)
IRON_2 = (49, 42, 82, 255)
IRON_3 = (84, 74, 130, 255)
IRON_4 = (132, 122, 180, 255)

# Deep sanctum interiors
WELL_DARK = (14, 10, 28, 255)
WELL_COMBAT = (36, 22, 30, 255)
WELL_COMBAT_HI = (56, 36, 36, 255)
WELL_MOVE = (15, 36, 46, 255)
WELL_MOVE_HI = (24, 58, 68, 255)
WELL_SHADOW = (30, 16, 56, 255)
WELL_SHADOW_HI = (48, 26, 86, 255)
WELL_READY = (44, 34, 22, 255)

# Gold (Combat / Ready / Brass Filigree)
GOLD_0 = (96, 66, 24, 255)
GOLD_1 = (164, 122, 46, 255)
GOLD_2 = (230, 196, 104, 255)
GOLD_3 = (255, 242, 182, 255)

# Teal (Movement / Wind / Life)
TEAL_0 = (28, 98, 108, 255)
TEAL_1 = (54, 178, 188, 255)
TEAL_2 = (120, 244, 230, 255)
TEAL_3 = (218, 255, 248, 255)

# Violet (Void / Shadow)
VIO_0 = (54, 24, 98, 255)
VIO_1 = (106, 56, 180, 255)
VIO_2 = (176, 118, 252, 255)
VIO_3 = (234, 208, 255, 255)

# Rose/Crimson jewel accent
ROSE_1 = (182, 54, 94, 255)
ROSE_2 = (242, 118, 152, 255)

# Silver / Steel blade tones
STEEL_0 = (76, 78, 114, 255)
STEEL_1 = (126, 134, 176, 255)
STEEL_2 = (186, 198, 232, 255)
STEEL_3 = (240, 246, 255, 255)


def make_grid(w: int, h: int, fill=CLEAR):
    return [[fill for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, c):
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = c


def blit(dst, src, ox: int, oy: int):
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0 and 0 <= oy + y < len(dst) and 0 <= ox + x < len(dst[0]):
                dst[oy + y][ox + x] = c


def add_outline(px, col=OUTLINE):
    h, w = len(px), len(px[0])
    src = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if src[y][x][3] > 0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= ny < h and 0 <= nx < w and src[ny][nx][3] > 0:
                    px[y][x] = col
                    break
    return px


def write_png(path: Path, w: int, h: int, grid):
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = bytearray()
    for row in grid:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


# ----------------------------------------------------------------------------------------------------------------------
# 1. Ornate 36x36 Octagonal-Crested Major Ability Medallions (NOT squares!)
# ----------------------------------------------------------------------------------------------------------------------

def build_major_medallion(rim_ramp: tuple, well_lo: tuple, well_hi: tuple, gem_col: tuple, gem_hi: tuple, ornate_wings: bool = True) -> list:
    """36x36 chiseled octagonal astral medallion with N/S/E/W crown prongs & recessed enamel core."""
    w, h = 36, 36
    cx, cy = 17.5, 17.5
    c0, c1, c2, c3 = rim_ramp
    px = make_grid(w, h)

    for y in range(h):
        for x in range(w):
            dx = abs(x - cx)
            dy = abs(y - cy)
            # Octagonal metric (chamfered corners -> sculptural faceted medallion, zero boxy look!)
            oct_d = max(dx, dy, (dx + dy) * 0.72)
            # Cardinal pointed filigree spires at N, S, E, W
            in_spire = (dx <= 1.6 and dy <= 16.2) or (dy <= 1.6 and dx <= 16.2)
            in_spire_base = (dx <= 3.6 and dy <= 14.8) or (dy <= 3.6 and dx <= 14.8)

            if oct_d <= 14.0 or (ornate_wings and (in_spire or in_spire_base)):
                top_left = (x - cx) + (y - cy)
                if oct_d <= 10.4:
                    # Deep curved jewel bowl interior with subtle top-left radial depth
                    r_dist = math.hypot(dx, dy)
                    if r_dist <= 6.2 and (x - cx) <= 2.5 and (y - cy) <= 2.5:
                        px[y][x] = well_hi
                    elif oct_d >= 9.4:
                        px[y][x] = OUTLINE if top_left < 0 else c0
                    else:
                        px[y][x] = well_lo
                elif oct_d <= 11.6:
                    # Inner recessed bevel lip
                    px[y][x] = c0 if top_left < -1 else c2
                elif oct_d <= 13.4 or (ornate_wings and in_spire_base):
                    # Sculpted metallic filigree rim
                    if top_left < -7:
                        px[y][x] = c3
                    elif top_left < 3:
                        px[y][x] = c2
                    elif top_left < 11:
                        px[y][x] = c1
                    else:
                        px[y][x] = c0
                else:
                    # Outer spire tip
                    px[y][x] = c3 if top_left < 0 else c1

    # Highlighted diagonal corner clasps (NE, NW, SE, SW)
    for sx in (-1, 1):
        for sy in (-1, 1):
            qx = int(round(cx + sx * 9.5))
            qy = int(round(cy + sy * 9.5))
            put(px, qx, qy, gem_hi if (sx < 0 and sy < 0) else gem_col)
            put(px, qx + (1 if sx < 0 else -1), qy, c3 if sy < 0 else c1)

    # N / S / E / W inlaid crown gems inside cardinal spires
    if ornate_wings:
        for gx, gy in ((17, 2), (18, 2), (17, 33), (18, 33), (2, 17), (2, 18), (33, 17), (33, 18)):
            put(px, gx, gy, c3 if (gx < 18 or gy < 18) else c2)
        for gx, gy in ((17, 4), (18, 4), (17, 31), (18, 31), (4, 17), (4, 18), (31, 17), (31, 18)):
            put(px, gx, gy, gem_hi if (gx <= 18 and gy <= 18) else gem_col)

    return add_outline(px)


def build_selection_halo() -> list:
    """44x44 ornate open compass-filigree selection frame orbiting the active medallion."""
    w, h = 44, 44
    px = make_grid(w, h)
    # 4 sculpted gilded corner arcs + cardinal star ticks (transparent interior)
    for corner_x, sx in ((3, 1), (w - 4, -1)):
        for corner_y, sy in ((3, 1), (h - 4, -1)):
            for i in range(8):
                c = GOLD_3 if i < 3 else (GOLD_2 if i < 6 else GOLD_1)
                put(px, corner_x + sx * i, corner_y, c)
                put(px, corner_x, corner_y + sy * i, c)
            put(px, corner_x + sx, corner_y + sy, TEAL_2)
            put(px, corner_x + sx * 2, corner_y + sy, GOLD_3)
            put(px, corner_x + sx, corner_y + sy * 2, GOLD_3)
    # Cardinal needle ticks (N, S, E, W)
    for k in range(3):
        c = GOLD_3 if k == 0 else GOLD_2
        put(px, 21, 1 + k, c)
        put(px, 22, 1 + k, c)
        put(px, 21, h - 2 - k, c)
        put(px, 22, h - 2 - k, c)
        put(px, 1 + k, 21, c)
        put(px, 1 + k, 22, c)
        put(px, w - 2 - k, 21, c)
        put(px, w - 2 - k, 22, c)
    return add_outline(px)


# ----------------------------------------------------------------------------------------------------------------------
# 2. Faceted 24x24 Diamond Crystal Echo Nodes + 32x32 Sacred Center Veil Core
# ----------------------------------------------------------------------------------------------------------------------

def build_echo_diamond(ramp: tuple, core_lo: tuple, core_hi: tuple, spark: tuple | None = None) -> list:
    """24x24 true diamond/rhombus crystal shard (Raute) for Echo nodes."""
    w, h = 24, 24
    cx, cy = 11.5, 11.5
    c0, c1, c2, c3 = ramp
    px = make_grid(w, h)

    for y in range(h):
        for x in range(w):
            dx = abs(x - cx)
            dy = abs(y - cy)
            md = dx + dy  # pure Manhattan diamond!
            if md <= 10.2:
                tl = (x - cx) + (y - cy)
                if md <= 5.6:
                    # Inner luminous crystal chamber
                    px[y][x] = core_hi if (x <= cx and y <= cy) else core_lo
                elif md <= 7.0:
                    px[y][x] = c0 if tl < 0 else c2
                else:
                    # Beveled faceted diamond rim
                    if x < cx and y < cy:
                        px[y][x] = c3
                    elif x < cx or y < cy:
                        px[y][x] = c2
                    else:
                        px[y][x] = c1 if md < 9.2 else c0

    # Inner tiny star facet glint
    if spark is not None:
        put(px, 11, 11, spark)
        put(px, 12, 11, spark)
        put(px, 11, 12, spark)
        put(px, 12, 12, c2)
        put(px, 11, 9, c3)
        put(px, 12, 9, c3)
        put(px, 9, 11, c3)
        put(px, 9, 12, c3)

    return add_outline(px)


def build_hub_core() -> list:
    """32x32 Sacred Center Diamond Core (Schleierkern) sitting at the heart of the Raute."""
    w, h = 32, 32
    cx, cy = 15.5, 15.5
    px = make_grid(w, h)

    for y in range(h):
        for x in range(w):
            dx = abs(x - cx)
            dy = abs(y - cy)
            md = dx + dy
            # 4 long cardinal compass needles + faceted inner diamond
            in_needle = (dx <= 1.2 and dy <= 14.2) or (dy <= 1.2 and dx <= 14.2)
            if md <= 11.4 or in_needle:
                if md <= 4.6:
                    # Luminous bioluminescent veil-star heart
                    if md <= 2.2:
                        px[y][x] = TEAL_3
                    elif (x < cx and y < cy):
                        px[y][x] = TEAL_2
                    else:
                        px[y][x] = VIO_2
                elif md <= 6.2:
                    px[y][x] = WELL_SHADOW
                elif md <= 9.2:
                    # Brass astrolabe diamond ring
                    if x < cx and y < cy:
                        px[y][x] = GOLD_3
                    elif x < cx or y < cy:
                        px[y][x] = GOLD_2
                    else:
                        px[y][x] = GOLD_1
                elif in_needle:
                    # Cardinal energy needles pointing to KAMPF (W), BEWEGUNG (N), LEERE (E), SEAL (S)
                    if x < cx and dy <= 1.2:
                        px[y][x] = GOLD_3 if dx > 11 else GOLD_2
                    elif y < cy and dx <= 1.2:
                        px[y][x] = TEAL_3 if dy > 11 else TEAL_2
                    elif x > cx and dy <= 1.2:
                        px[y][x] = VIO_3 if dx > 11 else VIO_2
                    else:
                        px[y][x] = IRON_3 if dy > 11 else IRON_2
                else:
                    px[y][x] = GOLD_0

    return add_outline(px)


def build_south_seal() -> list:
    """24x24 dormant 4th cardinal vertex diamond finial (completes the symmetric center Raute)."""
    w, h = 24, 24
    cx, cy = 11.5, 11.5
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            dx = abs(x - cx)
            dy = abs(y - cy)
            md = dx + dy
            if md <= 8.6:
                if md <= 4.4:
                    px[y][x] = WELL_DARK
                elif x < cx and y < cy:
                    px[y][x] = IRON_3
                elif x < cx or y < cy:
                    px[y][x] = IRON_2
                else:
                    px[y][x] = IRON_1
    # Tiny antique brass seal keyhole in the center
    for ky in (10, 11):
        put(px, 11, ky, GOLD_2)
        put(px, 12, ky, GOLD_1)
    put(px, 11, 12, GOLD_1)
    put(px, 12, 12, GOLD_0)
    put(px, 11, 13, GOLD_0)
    put(px, 12, 13, GOLD_0)
    return add_outline(px)


# ----------------------------------------------------------------------------------------------------------------------
# 3. Hand-Crafted 18x18 High-Detail Pixel-Art Ability Icons (Zero crude sticks!)
# ----------------------------------------------------------------------------------------------------------------------

def build_icon_combo3() -> list:
    """DREIKLANG: Gilded blade cleaving through a luminous triple crescent arc."""
    px = make_grid(18, 18)
    # Sweeping outer golden triple slash crescent
    for x, y, c in (
        (3, 5, GOLD_1), (4, 4, GOLD_2), (6, 3, GOLD_3), (8, 3, GOLD_3), (10, 4, GOLD_2),
        (12, 5, GOLD_2), (13, 7, GOLD_1), (14, 9, GOLD_1),
        (2, 8, GOLD_1), (3, 7, GOLD_2), (5, 6, GOLD_2), (11, 12, GOLD_1), (12, 11, GOLD_2),
    ):
        put(px, x, y, c)
    # Gleaming steel-and-gold blade diagonally from bottom-left (4, 14) to top-right (14, 4)
    for i in range(9):
        bx, by = 6 + i, 12 - i
        put(px, bx, by, STEEL_3 if i >= 5 else STEEL_2)
        put(px, bx - 1, by, STEEL_1)
        put(px, bx, by + 1, STEEL_0)
    put(px, 15, 3, STEEL_3)
    # Ornate golden crossguard & pommel
    for gx, gy, c in (
        (4, 11, GOLD_3), (5, 12, GOLD_2), (6, 13, GOLD_2), (7, 14, GOLD_1),
        (4, 13, GOLD_1), (3, 14, GOLD_0), (2, 15, GOLD_2),
    ):
        put(px, gx, gy, c)
    return add_outline(px)


def build_icon_stride() -> list:
    """ANTRITT: Winged gale-dash comet / wind-plume crest in luminous sea-glass teal."""
    px = make_grid(18, 18)
    # 3 layered sweeping wind-wing plumes from top-right streaking left
    rows = [
        (4, range(6, 15), TEAL_3, TEAL_2),
        (5, range(8, 16), TEAL_2, TEAL_1),
        (7, range(4, 15), TEAL_3, TEAL_2),
        (8, range(5, 16), TEAL_2, TEAL_1),
        (9, range(7, 14), TEAL_1, TEAL_0),
        (11, range(3, 12), TEAL_2, TEAL_1),
        (12, range(5, 13), TEAL_1, TEAL_0),
        (14, range(7, 11), TEAL_0, TEAL_0),
    ]
    for y, xs, c_front, c_tail in rows:
        x_list = list(xs)
        for idx, x in enumerate(x_list):
            put(px, x, y, c_front if idx >= len(x_list) - 4 else c_tail)
    # Bright spearhead comet core on right
    for x, y in ((14, 7), (15, 8), (16, 8), (14, 8), (13, 7)):
        put(px, x, y, TEAL_3)
    # Speed sparks trailing left
    put(px, 2, 7, TEAL_2)
    put(px, 3, 4, TEAL_1)
    put(px, 2, 12, TEAL_1)
    return add_outline(px)


def build_icon_sneak() -> list:
    """SCHLEICHEN: Veiled nocturnal crescent-eye peering from beneath a shadow cowl."""
    px = make_grid(18, 18)
    # Hooded upper shadow brow
    for x in range(3, 15):
        dy = abs(x - 8.5)
        y_top = 4 + int(dy * 0.55)
        put(px, x, y_top, VIO_1 if dy > 3 else VIO_2)
        put(px, x, y_top + 1, VIO_0)
    # Almond luminous eye cavity
    for x in range(4, 14):
        dx = abs(x - 8.5)
        span = max(0, int(3.2 - dx * 0.55))
        for dy in range(-span, span + 1):
            y = 9 + dy
            if dx <= 1.6 and abs(dy) <= 1:
                put(px, x, y, TEAL_3 if (x == 8 and dy == 0) else TEAL_2)
            elif dx <= 2.6 and abs(dy) <= 1:
                put(px, x, y, TEAL_1)
            else:
                put(px, x, y, TEAL_0)
    # Lower twilight eyelash & stealth wisps
    for x in range(5, 13):
        put(px, x, 12, VIO_1 if 7 <= x <= 10 else VIO_0)
    put(px, 3, 13, TEAL_1)
    put(px, 14, 13, TEAL_1)
    put(px, 8, 14, VIO_2)
    put(px, 9, 14, VIO_2)
    return add_outline(px)


def build_icon_climb() -> list:
    """KLETTERN: Twin steel-teal climbing grappling claws cresting a stone ledge."""
    px = make_grid(18, 18)
    # Chiseled stepped stone ledge at bottom-right
    for y in range(11, 16):
        for x in range(4, 15):
            if y == 11 and x < 7:
                continue
            c = IRON_3 if y == 11 else (IRON_2 if (y == 12 or x == 7) else IRON_1)
            put(px, x, y, c)
    # Twin gripping teal/silver climbing claws hooking upward over the crag
    for ox in (0, 5):
        for dx, dy, c in (
            (3, 10, TEAL_1), (4, 9, TEAL_2), (5, 8, TEAL_2), (6, 7, TEAL_3),
            (7, 6, STEEL_3), (8, 6, STEEL_2), (9, 7, TEAL_2), (9, 8, TEAL_1),
        ):
            put(px, ox + dx, dy, c)
    # Upward ascent chevron spark at top-left
    put(px, 5, 4, TEAL_3)
    put(px, 4, 5, TEAL_2)
    put(px, 6, 5, TEAL_2)
    return add_outline(px)


def build_icon_rift() -> list:
    """SCHATTENSCHRITT: Fractured violet void-rift portal tear with twin leaping motes."""
    px = make_grid(18, 18)
    # Outer crackling void aura diamond
    for y in range(2, 16):
        dy = abs(y - 8.5)
        half_w = max(1, int(5.4 - dy * 0.72))
        for x in range(9 - half_w, 9 + half_w):
            dx = abs(x - 8.5)
            if dx <= 1.0 and dy <= 4.8:
                put(px, x, y, VIO_3 if dy <= 2.5 else TEAL_3)
            elif dx <= 2.2 and dy <= 5.5:
                put(px, x, y, VIO_2)
            elif dx <= 3.5:
                put(px, x, y, VIO_1)
            else:
                put(px, x, y, VIO_0)
    # Diagonal rift slash arcs + leaping shadow sparks
    for x, y, c in (
        (3, 7, VIO_2), (4, 6, VIO_3), (14, 10, VIO_2), (13, 11, VIO_3),
        (4, 12, ROSE_2), (13, 5, TEAL_2), (2, 10, VIO_1), (15, 7, VIO_1),
    ):
        put(px, x, y, c)
    return add_outline(px)


def build_icon_light_step() -> list:
    """LICHTSCHRITT: Radiant golden starlight portal burst."""
    px = make_grid(18, 18)
    for y in range(2, 16):
        for x in range(2, 16):
            dx = abs(x - 8.5)
            dy = abs(y - 8.5)
            if dx <= 1.0 and dy <= 6.5:
                put(px, x, y, GOLD_3 if dy < 3.5 else GOLD_2)
            elif dy <= 1.0 and dx <= 6.5:
                put(px, x, y, GOLD_3 if dx < 3.5 else GOLD_2)
            elif dx + dy <= 4.5:
                put(px, x, y, GOLD_3 if (dx + dy <= 2.2) else GOLD_2)
            elif abs(dx - dy) <= 0.6 and dx <= 4.5:
                put(px, x, y, GOLD_1)
    put(px, 8, 8, STEEL_3)
    put(px, 9, 8, STEEL_3)
    put(px, 8, 9, STEEL_3)
    put(px, 9, 9, STEEL_3)
    return add_outline(px)


def build_icon_combo4() -> list:
    """AUFWÄRTSHIEB: Rising golden uppercut moon-slash."""
    px = make_grid(18, 18)
    for x, y, c in (
        (5, 14, GOLD_0), (6, 13, GOLD_1), (7, 12, GOLD_1), (8, 10, GOLD_2),
        (9, 8, GOLD_2), (10, 6, GOLD_3), (11, 4, GOLD_3), (12, 3, STEEL_3),
        (11, 5, STEEL_3), (10, 7, STEEL_2), (9, 9, GOLD_3), (8, 11, GOLD_2),
        (7, 13, GOLD_1), (13, 5, GOLD_2), (13, 7, GOLD_1), (6, 9, GOLD_2),
    ):
        put(px, x, y, c)
    return add_outline(px)


def build_icon_combo5() -> list:
    """WIRBELKLINGE: Spinning golden whirlwind double-blade halo."""
    px = make_grid(18, 18)
    cx, cy = 8.5, 8.5
    for y in range(2, 16):
        for x in range(2, 16):
            r = math.hypot(x - cx, y - cy)
            ang = math.atan2(y - cy, x - cx)
            if 4.2 <= r <= 6.2:
                if abs(ang) < 2.2 or abs(ang) > 2.6:
                    c = GOLD_3 if (y < 8 and x < 11) else (GOLD_2 if y < 12 else GOLD_1)
                    put(px, x, y, c)
            elif r <= 2.0:
                put(px, x, y, STEEL_3 if r < 1.2 else GOLD_2)
    return add_outline(px)


def build_icon_echo_glyph() -> list:
    """ECHO: Luminous 4-point faceted astral star-seed."""
    px = make_grid(18, 18)
    cx, cy = 8.5, 8.5
    for y in range(3, 15):
        for x in range(3, 15):
            dx = abs(x - cx)
            dy = abs(y - cy)
            if (dx <= 1.0 and dy <= 5.0) or (dy <= 1.0 and dx <= 5.0) or (dx + dy <= 3.2):
                if dx + dy <= 1.6:
                    put(px, x, y, STEEL_3)
                elif dx + dy <= 3.0:
                    put(px, x, y, TEAL_2)
                else:
                    put(px, x, y, VIO_2)
    put(px, 5, 5, GOLD_2)
    put(px, 12, 12, GOLD_2)
    return add_outline(px)


def build_gem_pip(ramp: tuple) -> list:
    """8x8 faceted diamond upgrade gem pip."""
    px = make_grid(8, 8)
    c0, c1, c2, c3 = ramp
    for y in range(8):
        for x in range(8):
            md = abs(x - 3.5) + abs(y - 3.5)
            if md <= 2.6:
                if x <= 3 and y <= 3:
                    px[y][x] = c3
                elif x <= 3 or y <= 3:
                    px[y][x] = c2
                else:
                    px[y][x] = c1 if md < 2.1 else c0
    return add_outline(px)


def main() -> None:
    sheet = make_grid(SHEET_W, SHEET_H)

    # Row 0 (y=4): 5 Major 36x36 Medallions + 44x44 Selection Halo
    blit(sheet, build_major_medallion((IRON_0, IRON_1, IRON_2, IRON_3), WELL_DARK, IRON_1, IRON_2, IRON_3, True), 4, 4)
    blit(sheet, build_major_medallion((GOLD_0, GOLD_1, GOLD_2, GOLD_3), WELL_READY, GOLD_0, TEAL_1, TEAL_3, True), 44, 4)
    blit(sheet, build_major_medallion((GOLD_0, GOLD_1, GOLD_2, GOLD_3), WELL_COMBAT, WELL_COMBAT_HI, ROSE_1, ROSE_2, True), 84, 4)
    blit(sheet, build_major_medallion((TEAL_0, TEAL_1, TEAL_2, TEAL_3), WELL_MOVE, WELL_MOVE_HI, GOLD_1, GOLD_3, True), 124, 4)
    blit(sheet, build_major_medallion((VIO_0, VIO_1, VIO_2, VIO_3), WELL_SHADOW, WELL_SHADOW_HI, TEAL_1, TEAL_3, True), 164, 4)
    blit(sheet, build_selection_halo(), 204, 2)

    # Row 1 (y=50): 5 Diamond Echo Crystals (24x24) + Center Veil Core (32x32) + South Seal (24x24)
    blit(sheet, build_echo_diamond((IRON_0, IRON_1, IRON_2, IRON_3), WELL_DARK, IRON_1, None), 4, 50)
    blit(sheet, build_echo_diamond((TEAL_0, TEAL_1, TEAL_2, TEAL_3), WELL_MOVE, TEAL_1, GOLD_3), 32, 50)
    blit(sheet, build_echo_diamond((GOLD_0, GOLD_1, GOLD_2, GOLD_3), WELL_COMBAT, WELL_COMBAT_HI, GOLD_3), 60, 50)
    blit(sheet, build_echo_diamond((TEAL_0, TEAL_1, TEAL_2, TEAL_3), WELL_MOVE, WELL_MOVE_HI, TEAL_3), 88, 50)
    blit(sheet, build_echo_diamond((VIO_0, VIO_1, VIO_2, VIO_3), WELL_SHADOW, WELL_SHADOW_HI, VIO_3), 116, 50)
    blit(sheet, build_hub_core(), 148, 48)
    blit(sheet, build_south_seal(), 188, 50)

    # Row 2 (y=90): 9 Hand-Crafted 18x18 Ability Icons
    icons = [
        build_icon_combo3(),
        build_icon_stride(),
        build_icon_sneak(),
        build_icon_climb(),
        build_icon_rift(),
        build_icon_light_step(),
        build_icon_combo4(),
        build_icon_combo5(),
        build_icon_echo_glyph(),
    ]
    for i, ic in enumerate(icons):
        blit(sheet, ic, 4 + i * 22, 90)

    # Row 3 (y=118): 3 Faceted 8x8 Upgrade Gem Pips
    blit(sheet, build_gem_pip((IRON_0, IRON_1, IRON_2, IRON_3)), 4, 118)
    blit(sheet, build_gem_pip((GOLD_0, GOLD_1, GOLD_2, GOLD_3)), 16, 118)
    blit(sheet, build_gem_pip((TEAL_0, TEAL_1, TEAL_2, TEAL_3)), 28, 118)

    out_png = ROOT / "assets" / "ui" / "skill_medallions.png"
    write_png(out_png, SHEET_W, SHEET_H, sheet)

    # 4x visual inspection sheet on dark obsidian backdrop
    scale = 4
    preview = make_grid(SHEET_W * scale, SHEET_H * scale, (14, 11, 26, 255))
    for y in range(SHEET_H):
        for x in range(SHEET_W):
            c = sheet[y][x]
            if c[3] == 0:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    preview[y * scale + dy][x * scale + dx] = c
    preview_png = ROOT / "docs" / "img" / "skill_medallions_4x.png"
    write_png(preview_png, SHEET_W * scale, SHEET_H * scale, preview)
    print(f"Wrote {out_png} ({SHEET_W}x{SHEET_H}) and {preview_png}")


if __name__ == "__main__":
    main()
