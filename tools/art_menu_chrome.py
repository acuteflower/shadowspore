#!/usr/bin/env python3
"""Generate hand-crafted pixel-art UI chrome & 1:1 seamless surface tiles for Shadowspore's Feldcodex.

Outputs:
  - assets/ui/menu_chrome.png (256x256 nearest-filtered sprite sheet: 9-slice frames, 1:1 tiles, icons & crests)
  - data/menu_chrome_art.json (region rects, 9-slice margins & tile metadata)
  - docs/img/menu_chrome_atlas_4x.png (4x visual inspection sheet)

Palette & craft strictly adhere to docs/design_guide.md:
  - Tinted obsidian outline (#0b0716), zero pure #000000
  - Top-left light source, 3-4 tonal steps per material, clean clusters (zero random noise)
  - Seamless 48x48 / 64x34 surface tiles rendered at true 1:1 pixel resolution (never stretched!)
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "assets"
SHEET_W = 256
SHEET_H = 256

CLEAR = (0, 0, 0, 0)
OUTLINE = (11, 7, 22, 255)        # #0b0716
DEEP_0 = (12, 9, 25, 255)         # #0c0919 cosmos abyss
SLATE_0 = (16, 13, 31, 255)       # #100d1f deepest recessed well
SLATE_1 = (21, 17, 39, 255)       # #151127 base obsidian slate
SLATE_2 = (28, 23, 50, 255)       # #1c1732 mid stone cluster
SLATE_2B = (34, 28, 59, 255)      # #221c3b subtle mortar glint
SLATE_3 = (45, 38, 76, 255)       # #2d264c lit slate bevel
SLATE_4 = (74, 65, 128, 255)      # #4a4180 crisp bevel rim
SLATE_5 = (112, 100, 172, 255)    # #7064ac top-left catchlight

COSMOS_0 = (13, 10, 27, 255)      # #0d0a1b
COSMOS_1 = (18, 13, 36, 255)      # #120d24
COSMOS_2 = (25, 19, 49, 255)      # #191331
COSMOS_3 = (38, 28, 72, 255)      # #261c48

VELLUM_0 = (26, 20, 41, 255)      # #1a1429 smoked vellum shadow
VELLUM_1 = (32, 25, 49, 255)      # #201931 smoked vellum base
VELLUM_2 = (39, 31, 59, 255)      # #271f3b smoked vellum fiber
VELLUM_3 = (52, 41, 76, 255)      # #34294c smoked vellum catchlight

BARK_0 = (24, 17, 34, 255)        # #181122
BARK_1 = (36, 27, 48, 255)        # #241b30
BARK_2 = (52, 40, 66, 255)        # #342842
BARK_3 = (76, 59, 92, 255)        # #4c3b5c

GOLD_0 = (96, 68, 28, 255)        # #60441c
GOLD_1 = (158, 118, 48, 255)      # #9e7630
GOLD_2 = (224, 188, 96, 255)      # #e0bc60
GOLD_3 = (255, 240, 176, 255)     # #fff0b0

TEAL_0 = (32, 110, 118, 255)      # #206e76
TEAL_1 = (60, 192, 198, 255)      # #3cc0c6
TEAL_2 = (120, 244, 230, 255)     # #78f4e6
TEAL_3 = (212, 255, 248, 255)     # #d4fff8

VIO_0 = (52, 24, 94, 255)         # #34185e
VIO_1 = (102, 54, 173, 255)       # #6636ad
VIO_2 = (162, 116, 242, 255)      # #a274f2
VIO_3 = (218, 194, 255, 255)      # #dac2ff

LEAF_0 = (28, 66, 52, 255)        # #1c4234
LEAF_1 = (48, 108, 76, 255)       # #306c4c
LEAF_2 = (86, 162, 106, 255)      # #56a26a
LEAF_3 = (156, 224, 146, 255)     # #9ce092

ROSE_0 = (118, 34, 62, 255)       # #76223e
ROSE_1 = (178, 58, 96, 255)       # #b23a60
ROSE_2 = (232, 112, 148, 255)     # #e87094
ROSE_3 = (255, 192, 212, 255)     # #ffc0d4

DIM_0 = (78, 70, 110, 255)
DIM_1 = (124, 115, 162, 255)
DIM_2 = (176, 168, 212, 255)


def make_grid(w: int, h: int, fill=CLEAR):
    return [[fill for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, c):
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = c


def outline(px, col=OUTLINE):
    h, w = len(px), len(px[0])
    src = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if src[y][x][3] > 0:
                continue
            if any(
                0 <= y + dy < h and 0 <= x + dx < w and src[y + dy][x + dx][3] > 0
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
            ):
                px[y][x] = col
    return px


def blit(dst, src, ox: int, oy: int):
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0 and 0 <= oy + y < len(dst) and 0 <= ox + x < len(dst[0]):
                dst[oy + y][ox + x] = c


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


def _rounded_mask(x: int, y: int, w: int, h: int, cut: int = 1) -> bool:
    dx = min(x, w - 1 - x)
    dy = min(y, h - 1 - y)
    return (dx + dy) >= cut


# ----------------------------------------------------------------------------------------------------------------------
# Clean 9-slice border frames (ZERO center grain so stretching never creates blocky artifacts;
# MenuChrome composites 1:1 tiled textures cleanly inside the interior!)
# ----------------------------------------------------------------------------------------------------------------------

def build_slate_panel() -> list:
    w, h = 24, 24
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 1):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0 or (ex == 1 and ey == 1):
                px[y][x] = OUTLINE
            elif ex == 1 or ey == 1:
                px[y][x] = SLATE_5 if (y == 1 or x == 1) else SLATE_3
            elif y == 2 and 2 <= x <= w - 3:
                px[y][x] = SLATE_4
            elif y == h - 3 and 2 <= x <= w - 3:
                px[y][x] = SLATE_0
            elif x == 2 and 2 <= y <= h - 3:
                px[y][x] = SLATE_3
            elif x == w - 3 and 2 <= y <= h - 3:
                px[y][x] = SLATE_0
            else:
                px[y][x] = SLATE_1
    for cx, cy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
        px[cy][cx] = GOLD_2 if (cx == 3 and cy == 3) else GOLD_1
    return px


def build_slate_inset() -> list:
    w, h = 24, 24
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 1):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0:
                px[y][x] = OUTLINE
            elif y == 1 or x == 1:
                px[y][x] = DEEP_0
            elif y == h - 2 or x == w - 2:
                px[y][x] = SLATE_3
            else:
                px[y][x] = SLATE_0
    return px


def build_parchment_panel() -> list:
    w, h = 24, 24
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 1):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0 or (ex == 1 and ey == 1):
                px[y][x] = OUTLINE
            elif ex == 1 or ey == 1:
                px[y][x] = GOLD_2 if (y == 1 or x == 1) else GOLD_0
            elif ex == 2 or ey == 2:
                px[y][x] = VELLUM_3 if (y == 2 or x == 2) else VELLUM_0
            else:
                px[y][x] = VELLUM_1
    for cx, cy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
        px[cy][cx] = GOLD_2
    return px


def build_gold_frame() -> list:
    w, h = 24, 24
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 1):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0 or (ex == 1 and ey == 1):
                px[y][x] = OUTLINE
            elif ex == 1 or ey == 1:
                px[y][x] = GOLD_3 if (y == 1 and x < w // 2 + 4) else (GOLD_2 if (y == 1 or x == 1) else GOLD_1)
            elif ex == 2 or ey == 2:
                px[y][x] = GOLD_0
            else:
                px[y][x] = SLATE_1
    for cx, cy in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)):
        px[cy][cx] = GOLD_3
    return px


def build_tab_pill(active: bool) -> list:
    w, h = 32, 22
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 2):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0 or (ex + ey == 2):
                px[y][x] = OUTLINE
            elif ex == 1 or ey == 1:
                if active:
                    px[y][x] = GOLD_3 if (y == 1 and x < w - 5) else (GOLD_2 if (y == 1 or x == 1) else GOLD_1)
                else:
                    px[y][x] = SLATE_4 if (y == 1 or x == 1) else SLATE_2
            elif y == 2:
                px[y][x] = GOLD_0 if active else SLATE_2
            else:
                # Smooth vertical shading (zero horizontal grain so width stretches cleanly!)
                if active:
                    px[y][x] = SLATE_3 if y < 8 else (SLATE_2B if y < 14 else SLATE_2)
                else:
                    px[y][x] = SLATE_2 if y < 7 else (SLATE_1 if y < 15 else SLATE_0)
    if active:
        put(px, 3, 2, TEAL_2)
        put(px, w - 4, 2, TEAL_2)
        put(px, 3, h - 3, GOLD_1)
        put(px, w - 4, h - 3, GOLD_1)
    return px


def build_moss_niche() -> list:
    """28x28 recessed obsidian-cosmos specimen vitrine niche (no bright green checkerboard bar)."""
    w, h = 28, 28
    px = make_grid(w, h)
    for y in range(h):
        for x in range(w):
            if not _rounded_mask(x, y, w, h, 2):
                continue
            ex = min(x, w - 1 - x)
            ey = min(y, h - 1 - y)
            if ex == 0 or ey == 0 or (ex + ey == 2):
                px[y][x] = OUTLINE
            elif ex == 1 or ey == 1:
                px[y][x] = SLATE_4 if (y == 1 or x == 1) else SLATE_2
            elif y == 2 and 3 <= x <= w - 4:
                px[y][x] = SLATE_0
            elif y == h - 3 and 3 <= x <= w - 4:
                px[y][x] = SLATE_2
            else:
                # Calm vertical nocturnal velvet depth inside the specimen vitrine
                if y < 9:
                    px[y][x] = COSMOS_0
                elif y < h - 7:
                    px[y][x] = SLATE_0
                else:
                    px[y][x] = COSMOS_1
    # Delicate antique brass corner pin studs inside the vitrine frame
    for cx, cy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
        put(px, cx, cy, GOLD_1 if (cx == 3 and cy == 3) else SLATE_3)
    return px


# ----------------------------------------------------------------------------------------------------------------------
# Seamless 1:1 Pixel-Art Surface Tiles (48x48 & 64x34/20 — NEVER stretched!)
# ----------------------------------------------------------------------------------------------------------------------

def build_tile_slate() -> list:
    """48x48 seamless quiet dressed obsidian slate — whisper-soft tonal relief so UI text pops effortlessly."""
    w, h = 48, 48
    t_bg = (20, 16, 37, 255)      # #141025 calm velvet obsidian
    t_seam = (16, 13, 30, 255)    # #100d1e whisper-soft hairline joint
    t_hi = (23, 19, 43, 255)      # #17132b gentle stone bevel
    t_glint = (27, 22, 49, 255)   # #1b1631 delicate mineral fleck
    px = make_grid(w, h, t_bg)
    # 2 tall staggered dressed ashlar courses (24px each) with ultra-quiet mortar seams
    courses = [
        (0, 24, [0, 26, 48]),
        (24, 48, [0, 14, 40, 48]),
    ]
    for y0, y1, cuts in courses:
        for bi in range(len(cuts) - 1):
            x0, x1 = cuts[bi], cuts[bi + 1]
            slightly_warm = ((bi + y0 // 24) % 2 == 0)
            for y in range(y0, y1):
                for x in range(x0, x1):
                    lx = x - x0
                    ly = y - y0
                    if y == y0 and (x % 3 != 0):
                        px[y][x] = t_seam
                    elif x == x0 and (y % 2 == 0):
                        px[y][x] = t_seam
                    elif y == y0 + 1 and 2 <= lx <= (x1 - x0) - 3 and (x % 4 != 0):
                        px[y][x] = t_hi
                    elif ly in (7, 16) and 4 <= lx <= 9 and slightly_warm:
                        px[y][x] = t_hi
                    elif ly == 12 and 12 <= lx <= 16 and not slightly_warm:
                        px[y][x] = t_seam
                    else:
                        px[y][x] = t_hi if (slightly_warm and ly < 10 and (lx + ly) % 7 == 0) else t_bg
    # Sparse antique mica flecks (calm, subtle depth)
    for mx, my in ((9, 8), (34, 15), (20, 31), (42, 39)):
        put(px, mx, my, t_glint)
        put(px, (mx + 1) % w, my, t_hi)
    return px


def build_tile_inset() -> list:
    """48x48 seamless deep recessed twilight woven linen/velvet surface."""
    w, h = 48, 48
    t_deep = (15, 12, 29, 255)    # #0f0c1d
    t_base = (17, 14, 33, 255)    # #110e21
    t_thread = (21, 17, 40, 255)  # #151128
    t_knot = (25, 20, 46, 255)    # #19142e
    px = make_grid(w, h, t_base)
    for y in range(h):
        for x in range(w):
            diag = (x + y) % 8
            anti = (x - y) % 8
            if diag == 0 and (y % 2 == 0):
                px[y][x] = t_thread
            elif anti == 4 and (y % 4 == 1) and (x % 3 != 0):
                px[y][x] = t_deep
            elif y % 16 == 0 and (x % 8 in (2, 3, 4)):
                px[y][x] = t_thread
    # Whisper-soft stitched diamond motif every 24px
    for cy in (12, 36):
        for cx in (12, 36):
            for d in range(-2, 3):
                put(px, (cx + d) % w, (cy - (2 - abs(d))) % h, t_thread)
                put(px, (cx + d) % w, (cy + (2 - abs(d))) % h, t_thread)
            put(px, cx, cy, t_knot)
    return px


def build_tile_cosmos() -> list:
    """48x48 seamless infinite nocturnal Schleier-Samt with subtle astrolabe ticks & fine stardust."""
    w, h = 48, 48
    c0 = (13, 10, 26, 255)        # #0d0a1a deep night velvet
    c1 = (15, 11, 30, 255)        # #0f0b1e whisper-soft nebula veil
    c2 = (17, 13, 34, 255)        # #110d22 ultra-subtle violet shimmer
    c_line = (23, 18, 44, 255)    # #17122c whisper astrolabe tick
    c_star1 = (35, 27, 64, 255)   # #231b40 faint dust
    c_star2 = (54, 44, 94, 255)   # #362c5e crisp pinpoint star
    px = make_grid(w, h, c0)
    for y in range(h):
        for x in range(w):
            # Gentle low-contrast dual-harmonic veil (no repeating oval blobs!)
            ax = x * (2.0 * math.pi / w)
            ay = y * (2.0 * math.pi / h)
            v = math.sin(ax + ay) * 0.45 + math.sin(ax * 2.0 - ay) * 0.30 + math.cos(ay * 2.0) * 0.25
            if v > 0.55:
                px[y][x] = c2
            elif v > -0.10:
                px[y][x] = c1
            else:
                px[y][x] = c0
    # Ultra-delicate dotted astrolabe hairlines on 24px meridian
    for i in range(0, w, 4):
        put(px, i, 24, c_line)
        put(px, 24, i, c_line)
    # Center astrolabe crosshair spark
    put(px, 24, 24, c_star2)
    put(px, 23, 24, c_line)
    put(px, 25, 24, c_line)
    put(px, 24, 23, c_line)
    put(px, 24, 25, c_line)
    # Irregularly spaced multi-magnitude stardust (non-grid feel)
    for sx, sy, col in (
        (6, 9, c_star1),
        (17, 5, c_star2),
        (37, 13, c_star1),
        (11, 33, c_star2),
        (31, 29, c_star1),
        (43, 41, c_star1),
        (29, 44, c_star2),
    ):
        put(px, sx, sy, col)
    return px


def build_tile_vellum() -> list:
    """48x48 seamless handmade smoked dark-plum parchment with calm laid-paper grain & fine rag fibers."""
    w, h = 48, 48
    v0 = (27, 21, 42, 255)        # #1b152a subtle laid groove
    v1 = (31, 25, 48, 255)        # #1f1930 rich smoked vellum base
    v2 = (35, 28, 54, 255)        # #231c36 soft cotton rag tone
    v3 = (41, 33, 62, 255)        # #29213e fine fiber highlight
    px = make_grid(w, h, v1)
    for y in range(h):
        for x in range(w):
            # Subtle horizontal laid-paper deckle rhythm every 8px (zero polka dots!)
            if y % 8 == 0:
                px[y][x] = v0 if (x % 4 != 0) else v1
            elif y % 8 == 1 and ((x + y * 3) % 9 in (0, 1, 2, 3)):
                px[y][x] = v2
            elif ((x * 3 + y * 7) % 29 == 0):
                px[y][x] = v2
            elif ((x * 5 + y * 11) % 37 == 0):
                px[y][x] = v0
    # Short organic rag-paper fibers & delicate pulp flecks
    for fx, fy, flen in (
        (4, 5, 5),
        (26, 11, 6),
        (11, 19, 4),
        (35, 22, 5),
        (7, 29, 6),
        (29, 35, 5),
        (16, 43, 6),
        (41, 45, 4),
    ):
        for dx in range(flen):
            put(px, (fx + dx) % w, fy, v3 if dx == flen // 2 else v2)
    return px


def build_tile_canopy() -> list:
    """64x34 seamless horizontally tileable Canopy Rail (carved obsidian cedar + repeating brass filigree)."""
    w, h = 64, 34
    px = make_grid(w, h, SLATE_1)
    for y in range(h):
        for x in range(w):
            if y == 0:
                px[y][x] = OUTLINE
            elif y == 1:
                px[y][x] = BARK_3 if (x % 8 in (2, 3, 4, 5)) else BARK_2
            elif y in (2, 3, 4):
                # Chiseled dark wood molding with repeating 16px carved flute
                flute = x % 16
                if y == 2:
                    px[y][x] = BARK_2 if 2 <= flute <= 13 else BARK_0
                elif y == 3:
                    px[y][x] = BARK_1 if 1 <= flute <= 14 else BARK_0
                else:
                    px[y][x] = BARK_0
            elif y == 5:
                px[y][x] = SLATE_3 if (x % 16 in (4, 5, 6, 7, 8, 9, 10, 11)) else SLATE_0
            elif y == h - 1:
                px[y][x] = OUTLINE
            elif y == h - 2:
                px[y][x] = GOLD_0 if (x % 16 != 8) else GOLD_2
            elif y == h - 3:
                # Gleaming antique brass rim with periodic bright catchlight
                m = x % 32
                px[y][x] = GOLD_3 if m in (7, 8, 9) else (GOLD_2 if m % 4 != 0 else GOLD_1)
            elif y == h - 4:
                px[y][x] = OUTLINE
            elif y == h - 5:
                px[y][x] = SLATE_0
            else:
                # Main recessed obsidian fascia with subtle 16px architectural paneling
                seg = x % 32
                if seg == 0:
                    px[y][x] = SLATE_0
                elif seg == 1:
                    px[y][x] = SLATE_2
                elif y < 12:
                    px[y][x] = SLATE_2 if (seg in (6, 7, 8, 22, 23, 24) and y in (8, 9)) else SLATE_1
                elif y > h - 10:
                    px[y][x] = SLATE_0 if (y == h - 6) else SLATE_1
                else:
                    px[y][x] = SLATE_1
    # Repeating subtle botanical filigree studs every 32px along top groove
    for sx in (16, 48):
        put(px, sx, 3, GOLD_1)
        put(px, sx - 1, 3, GOLD_0)
        put(px, sx + 1, 3, GOLD_0)
        put(px, sx, h - 3, TEAL_2)
    return px


def build_tile_footer() -> list:
    """64x20 seamless horizontally tileable Footer Rail."""
    w, h = 64, 20
    px = make_grid(w, h, SLATE_0)
    for y in range(h):
        for x in range(w):
            if y == 0:
                px[y][x] = OUTLINE
            elif y == 1:
                m = x % 32
                px[y][x] = GOLD_2 if m in (15, 16) else (SLATE_4 if m % 4 != 0 else SLATE_3)
            elif y == 2:
                px[y][x] = SLATE_0
            elif y == h - 1:
                px[y][x] = OUTLINE
            elif y == h - 2:
                px[y][x] = DEEP_0
            else:
                seg = x % 32
                if seg == 0:
                    px[y][x] = DEEP_0
                elif seg == 1:
                    px[y][x] = SLATE_1
                else:
                    px[y][x] = SLATE_1 if y < 6 else SLATE_0
    return px


# Legacy tiny fallbacks kept at original coordinates so no existing reference breaks
def build_canopy_rail_compat() -> list:
    return [row[:48] for row in build_tile_canopy()]


def build_footer_rail_compat() -> list:
    return [row[:48] for row in build_tile_footer()]


# ----------------------------------------------------------------------------------------------------------------------
# Ornaments, Icons & Emblems
# ----------------------------------------------------------------------------------------------------------------------

def build_bloom_slider() -> list:
    w, h = 28, 8
    px = make_grid(w, h)
    for x in range(3, w - 3):
        put(px, x, 4, TEAL_1 if abs(x - 13.5) < 7 else TEAL_0)
        put(px, x, 3, TEAL_2 if abs(x - 13.5) < 5 else CLEAR)
    for lx, dx in ((7, -1), (20, 1)):
        put(px, lx, 4, LEAF_2)
        put(px, lx + dx, 3, LEAF_3)
        put(px, lx + dx * 2, 4, LEAF_1)
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if abs(dx) + abs(dy) <= 2:
                c = GOLD_3 if (dx == 0 and dy == 0) else (GOLD_2 if abs(dx) + abs(dy) == 1 else GOLD_1)
                put(px, 14 + dx, 4 + dy, c)
    return outline(px, OUTLINE)


def build_corner_filigree(flip_x: bool, flip_y: bool) -> list:
    w, h = 14, 14
    px = make_grid(w, h)
    for i in range(1, 12):
        put(px, i, 1, GOLD_2 if i < 7 else GOLD_1)
        put(px, 1, i, GOLD_2 if i < 7 else GOLD_1)
    put(px, 2, 2, GOLD_3)
    put(px, 3, 2, GOLD_2)
    put(px, 2, 3, GOLD_2)
    put(px, 4, 4, TEAL_2)
    put(px, 6, 3, LEAF_1)
    put(px, 7, 3, LEAF_2)
    put(px, 3, 6, LEAF_1)
    put(px, 3, 7, LEAF_2)
    px = outline(px, OUTLINE)
    if flip_x:
        px = [list(reversed(r)) for r in px]
    if flip_y:
        px = list(reversed(px))
    return px


def build_divider_brass() -> list:
    w, h = 48, 7
    px = make_grid(w, h)
    for x in range(2, w - 2):
        c = GOLD_1 if abs(x - 24) > 10 else GOLD_2
        put(px, x, 3, c)
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if abs(dx) + abs(dy) <= 2:
                put(px, 24 + dx, 3 + dy, TEAL_3 if (dx == 0 and dy == 0) else (TEAL_2 if abs(dx) + abs(dy) == 1 else GOLD_2))
    return outline(px, OUTLINE)


def build_badge_bud() -> list:
    w, h = 9, 9
    px = make_grid(w, h)
    for y in range(1, 8):
        for x in range(1, 8):
            d = abs(x - 4) + abs(y - 4)
            if d <= 2:
                px[y][x] = GOLD_3 if d == 0 else (GOLD_2 if d == 1 else GOLD_1)
    return outline(px, OUTLINE)


def build_tab_icon(kind: str, lit: bool) -> list:
    w, h = 12, 12
    px = make_grid(w, h)
    c0 = GOLD_0 if lit else DIM_0
    c1 = GOLD_1 if lit else DIM_1
    c2 = GOLD_2 if lit else DIM_2
    c3 = GOLD_3 if lit else DIM_2
    t1 = TEAL_1 if lit else DIM_1
    t2 = TEAL_2 if lit else DIM_2
    t3 = TEAL_3 if lit else DIM_2
    v1 = VIO_1 if lit else DIM_0
    v2 = VIO_2 if lit else DIM_1
    l1 = LEAF_1 if lit else DIM_0
    l2 = LEAF_2 if lit else DIM_1

    if kind == "bag":
        for y in range(4, 10):
            for x in range(3, 9):
                if y == 4 and x in (3, 8):
                    continue
                px[y][x] = c2 if (x < 6 and y < 7) else (c1 if y < 9 else c0)
        for x in range(4, 8):
            put(px, x, 3, c0)
        put(px, 5, 2, c1)
        put(px, 6, 2, c1)
        put(px, 5, 6, t3)
        put(px, 6, 6, t2)
    elif kind == "atlas":
        for i in range(2, 10):
            put(px, 6, i, t2 if i < 6 else c1)
            put(px, i, 6, c2 if i < 6 else c1)
        for dx, dy in ((-2, -2), (2, -2), (-2, 2), (2, 2)):
            put(px, 6 + dx, 6 + dy, c0)
        put(px, 6, 6, c3)
        put(px, 6, 2, t3)
    elif kind == "quests":
        for y in range(2, 10):
            for x in range(3, 9):
                px[y][x] = c2 if (x < 6 and y < 6) else c1
        for x in range(4, 8):
            put(px, x, 4, c0)
            put(px, x, 6, c0)
        put(px, 7, 8, ROSE_2 if lit else DIM_2)
        put(px, 8, 8, ROSE_1 if lit else DIM_1)
        put(px, 7, 9, ROSE_1 if lit else DIM_1)
    elif kind == "path":
        for y in range(2, 10):
            hw = 1 if y in (2, 9) else (2 if y in (3, 8) else 3)
            for x in range(6 - hw, 6 + hw):
                px[y][x] = t3 if (x < 6 and y < 6) else (t2 if x < 6 else v2)
        put(px, 5, 4, c3)
    elif kind == "fruits":
        for y in range(4, 10):
            for x in range(3, 9):
                dx = (x - 5.5) / 2.7
                dy = (y - 6.7) / 2.8
                if dx * dx + dy * dy <= 1.0:
                    px[y][x] = v2 if (dx < 0 and dy < 0) else v1
        put(px, 4, 6, t3)
        put(px, 7, 6, t3)
        put(px, 5, 8, t2)
        put(px, 6, 8, t2)
        put(px, 5, 3, l1)
        put(px, 6, 3, l1)
        put(px, 4, 2, l2)
        put(px, 6, 2, l2)
        put(px, 8, 2, l2)
        put(px, 6, 1, t2)
    elif kind == "world":
        for y in range(3, 10):
            for x in range(2, 10):
                if x == 5 or x == 6:
                    px[y][x] = c0
                else:
                    px[y][x] = c2 if (y < 6) else c1
        put(px, 8, 2, t2)
        put(px, 8, 3, t3)
        put(px, 3, 5, c0)
        put(px, 4, 5, c0)
        put(px, 8, 6, c0)
    elif kind == "system":
        for y in range(3, 9):
            for x in range(3, 9):
                d = math.hypot(x - 5.5, y - 5.5)
                if 1.1 <= d <= 2.9:
                    px[y][x] = c2 if (x < 6 and y < 6) else c1
        for tx, ty in ((5, 2), (6, 2), (5, 9), (6, 9), (2, 5), (2, 6), (9, 5), (9, 6)):
            put(px, tx, ty, c1)
        put(px, 5, 5, t2)
        put(px, 6, 6, t1)
    return outline(px, OUTLINE)


def build_lock_crest() -> list:
    w, h = 12, 12
    px = make_grid(w, h)
    for y in range(5, 10):
        for x in range(3, 9):
            px[y][x] = SLATE_4 if (x < 6 and y < 7) else SLATE_3
    for x in range(4, 8):
        put(px, x, 2, SLATE_4)
    put(px, 4, 3, SLATE_4)
    put(px, 7, 3, SLATE_3)
    put(px, 4, 4, SLATE_4)
    put(px, 7, 4, SLATE_3)
    put(px, 5, 7, VIO_2)
    put(px, 6, 7, VIO_2)
    put(px, 5, 8, VIO_1)
    return outline(px, OUTLINE)


def build_wax_seal() -> list:
    """14x14 crimson wax seal with golden star crest."""
    w, h = 14, 14
    px = make_grid(w, h)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            d = math.hypot(x - 6.5, y - 6.5)
            wob = 0.35 * math.sin(math.atan2(y - 6.5, x - 6.5) * 5.0)
            if d <= 5.0 + wob:
                if d > 3.7:
                    px[y][x] = ROSE_2 if (x < 7 and y < 7) else ROSE_0
                else:
                    px[y][x] = ROSE_1 if (x + y < 13) else ROSE_0
    # Embossed 4-point gold star in center
    put(px, 6, 6, GOLD_3)
    put(px, 7, 6, GOLD_2)
    put(px, 6, 7, GOLD_2)
    put(px, 7, 7, GOLD_1)
    for ox, oy in ((6, 4), (7, 4), (6, 9), (7, 9), (4, 6), (4, 7), (9, 6), (9, 7)):
        put(px, ox, oy, GOLD_2 if (ox <= 6 and oy <= 6) else GOLD_1)
    return outline(px, OUTLINE)


def build_crown_gold() -> list:
    """12x10 miniature gilded milestone crown."""
    w, h = 12, 10
    px = make_grid(w, h)
    for x in range(2, 10):
        put(px, x, 7, GOLD_0)
        put(px, x, 6, GOLD_2 if x < 6 else GOLD_1)
        put(px, x, 5, GOLD_2 if x % 2 == 0 else GOLD_1)
    # 3 prongs
    for px_i, py_top in ((2, 3), (5, 2), (6, 2), (9, 3)):
        for y in range(py_top, 6):
            put(px, px_i, y, GOLD_3 if y == py_top else GOLD_2)
    put(px, 5, 6, TEAL_2)
    put(px, 6, 6, TEAL_3)
    return outline(px, OUTLINE)


def build_sun_glyph() -> list:
    w, h = 10, 10
    px = make_grid(w, h)
    for y in range(3, 7):
        for x in range(3, 7):
            px[y][x] = GOLD_3 if (x < 5 and y < 5) else GOLD_2
    for rx, ry in ((4, 1), (5, 1), (4, 8), (5, 8), (1, 4), (1, 5), (8, 4), (8, 5), (2, 2), (7, 2), (2, 7), (7, 7)):
        put(px, rx, ry, GOLD_1)
    return outline(px, OUTLINE)


def build_moon_glyph() -> list:
    w, h = 10, 10
    px = make_grid(w, h)
    for y in range(1, 9):
        for x in range(1, 9):
            d1 = math.hypot(x - 4.8, y - 4.5)
            d2 = math.hypot(x - 6.6, y - 3.8)
            if d1 <= 3.3 and d2 >= 2.6:
                px[y][x] = VIO_3 if (x < 5 and y < 5) else VIO_2
    put(px, 7, 2, TEAL_2)
    return outline(px, OUTLINE)


def build_home_beacon() -> list:
    """12x12 luminous compass crystal for Atlas 'ZURÜCK ZU MIR'."""
    w, h = 12, 12
    px = make_grid(w, h)
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            ad = abs(dx) + abs(dy)
            if ad <= 3:
                c = TEAL_3 if ad == 0 else (TEAL_2 if ad == 1 else (TEAL_1 if dx <= 0 else GOLD_2))
                put(px, 6 + dx, 6 + dy, c)
    for cx, cy in ((6, 1), (6, 10), (1, 6), (10, 6)):
        put(px, cx, cy, GOLD_2)
    return outline(px, OUTLINE)


def build_hearth_crest() -> list:
    """18x18 stylized village hearth / lantern house emblem for WELT -> STADT."""
    w, h = 18, 18
    px = make_grid(w, h)
    # Pitched timber roof
    for row in range(6):
        hw = 2 + row
        for x in range(9 - hw, 9 + hw):
            put(px, x, 3 + row, GOLD_2 if (row <= 1 or x < 9) else GOLD_1)
    # Stone walls
    for y in range(9, 15):
        for x in range(4, 14):
            put(px, x, y, SLATE_4 if x < 9 else SLATE_3)
    # Warm glowing hearth doorway
    for y in range(11, 15):
        for x in range(7, 11):
            put(px, x, y, GOLD_3 if (y == 12 and x in (8, 9)) else GOLD_2)
    # Little curling emerald leaf at eaves
    put(px, 3, 9, LEAF_2)
    put(px, 14, 9, LEAF_2)
    return outline(px, OUTLINE)


def build_raven_crest() -> list:
    """18x18 silhouette perched twilight raven crest for WELT -> VÖGEL."""
    w, h = 18, 18
    px = make_grid(w, h)
    # Crescent moon halo behind bird
    for y in range(2, 15):
        for x in range(2, 15):
            d = math.hypot(x - 8.5, y - 8.5)
            if 5.2 <= d <= 6.2:
                put(px, x, y, GOLD_1 if y < 9 else GOLD_0)
    # Raven head + torso + tail
    for y in range(4, 8):
        for x in range(7, 11):
            put(px, x, y, VIO_2 if (x == 8 and y == 5) else VIO_1)
    put(px, 11, 5, GOLD_2)
    put(px, 12, 6, GOLD_1)
    put(px, 9, 5, TEAL_3)  # bright eye
    for y in range(8, 13):
        for x in range(5, 11):
            if y - x < 6:
                put(px, x, y, VIO_1 if x < 8 else VIO_0)
    for i in range(3):
        put(px, 4 - i, 12 + i, VIO_0)
        put(px, 5 - i, 12 + i, VIO_1)
    # Perch twig
    for x in range(4, 14):
        put(px, x, 14, GOLD_1 if x % 2 == 0 else GOLD_0)
    return outline(px, OUTLINE)


def main() -> None:
    regions = {
        "slate_panel":      {"rect": [4, 4, 24, 24],   "nine_patch": [6, 6, 6, 6]},
        "slate_inset":      {"rect": [32, 4, 24, 24],  "nine_patch": [5, 5, 5, 5]},
        "parchment_panel":  {"rect": [60, 4, 24, 24],  "nine_patch": [6, 6, 6, 6]},
        "gold_frame":       {"rect": [88, 4, 24, 24],  "nine_patch": [6, 6, 6, 6]},
        "tab_pill_idle":    {"rect": [116, 4, 32, 22], "nine_patch": [6, 5, 6, 5]},
        "tab_pill_active":  {"rect": [152, 4, 32, 22], "nine_patch": [6, 5, 6, 5]},
        "moss_niche":       {"rect": [188, 4, 28, 28], "nine_patch": [6, 6, 6, 6]},
        "bloom_slider":     {"rect": [220, 4, 28, 8]},
        "badge_bud":        {"rect": [220, 16, 9, 9]},
        "lock_crest":       {"rect": [234, 16, 12, 12]},

        "canopy_rail":      {"rect": [4, 36, 48, 34],  "nine_patch": [12, 6, 12, 6]},
        "footer_rail":      {"rect": [56, 36, 48, 20], "nine_patch": [10, 4, 10, 4]},
        "divider_brass":    {"rect": [56, 60, 48, 7]},
        "corner_nw":        {"rect": [110, 36, 14, 14]},
        "corner_ne":        {"rect": [128, 36, 14, 14]},
        "corner_sw":        {"rect": [146, 36, 14, 14]},
        "corner_se":        {"rect": [164, 36, 14, 14]},

        # Seamless 1:1 pixel-art surface tiles (y = 116..216)
        "tile_slate":       {"rect": [4, 116, 48, 48],   "tile": True},
        "tile_inset":       {"rect": [56, 116, 48, 48],  "tile": True},
        "tile_cosmos":      {"rect": [108, 116, 48, 48], "tile": True},
        "tile_vellum":      {"rect": [160, 116, 48, 48], "tile": True},
        "tile_canopy":      {"rect": [4, 170, 64, 34],   "tile": True},
        "tile_footer":      {"rect": [72, 170, 64, 20],  "tile": True},

        # New emblems & micro-icons (y = 212..248)
        "wax_seal":         {"rect": [4, 212, 14, 14]},
        "crown_gold":       {"rect": [22, 214, 12, 10]},
        "sun_glyph":        {"rect": [38, 214, 10, 10]},
        "moon_glyph":       {"rect": [52, 214, 10, 10]},
        "home_beacon":      {"rect": [66, 213, 12, 12]},
        "hearth_crest":     {"rect": [84, 210, 18, 18]},
        "raven_crest":      {"rect": [106, 210, 18, 18]},
    }

    parts = {
        "slate_panel": build_slate_panel(),
        "slate_inset": build_slate_inset(),
        "parchment_panel": build_parchment_panel(),
        "gold_frame": build_gold_frame(),
        "tab_pill_idle": build_tab_pill(False),
        "tab_pill_active": build_tab_pill(True),
        "moss_niche": build_moss_niche(),
        "bloom_slider": build_bloom_slider(),
        "badge_bud": build_badge_bud(),
        "lock_crest": build_lock_crest(),
        "canopy_rail": build_canopy_rail_compat(),
        "footer_rail": build_footer_rail_compat(),
        "divider_brass": build_divider_brass(),
        "corner_nw": build_corner_filigree(False, False),
        "corner_ne": build_corner_filigree(True, False),
        "corner_sw": build_corner_filigree(False, True),
        "corner_se": build_corner_filigree(True, True),
        "tile_slate": build_tile_slate(),
        "tile_inset": build_tile_inset(),
        "tile_cosmos": build_tile_cosmos(),
        "tile_vellum": build_tile_vellum(),
        "tile_canopy": build_tile_canopy(),
        "tile_footer": build_tile_footer(),
        "wax_seal": build_wax_seal(),
        "crown_gold": build_crown_gold(),
        "sun_glyph": build_sun_glyph(),
        "moon_glyph": build_moon_glyph(),
        "home_beacon": build_home_beacon(),
        "hearth_crest": build_hearth_crest(),
        "raven_crest": build_raven_crest(),
    }

    icon_names = ["bag", "atlas", "quests", "path", "fruits", "world", "system"]
    for idx, name in enumerate(icon_names):
        rx = 4 + idx * 16
        regions[f"icon_{name}_dim"] = {"rect": [rx, 80, 12, 12]}
        regions[f"icon_{name}_lit"] = {"rect": [rx, 96, 12, 12]}
        parts[f"icon_{name}_dim"] = build_tab_icon(name, False)
        parts[f"icon_{name}_lit"] = build_tab_icon(name, True)

    sheet = make_grid(SHEET_W, SHEET_H)
    for k, info in regions.items():
        rx, ry, rw, rh = info["rect"]
        p = parts[k]
        assert len(p) == rh and len(p[0]) == rw, f"{k} size mismatch"
        blit(sheet, p, rx, ry)

    for y in range(SHEET_H):
        for x in range(SHEET_W):
            r, g, b, a = sheet[y][x]
            assert not (a > 0 and r == 0 and g == 0 and b == 0), f"Pure black at {x},{y}"

    out_png = ROOT / "ui" / "menu_chrome.png"
    out_json = ROOT.parent / "data" / "menu_chrome_art.json"
    out_4x = ROOT.parent / "docs" / "img" / "menu_chrome_atlas_4x.png"

    write_png(out_png, SHEET_W, SHEET_H, sheet)
    meta = {"sheet": "res://assets/ui/menu_chrome.png", "size": [SHEET_W, SHEET_H], "regions": regions}
    out_json.write_text(json.dumps(meta, indent="\t") + "\n", encoding="utf-8")

    scale = 4
    preview = make_grid(SHEET_W * scale, SHEET_H * scale, (14, 11, 26, 255))
    for y in range(SHEET_H):
        for x in range(SHEET_W):
            c = sheet[y][x]
            if c[3] == 0:
                continue
            for sy in range(scale):
                for sx in range(scale):
                    preview[y * scale + sy][x * scale + sx] = c
    write_png(out_4x, SHEET_W * scale, SHEET_H * scale, preview)
    print(f"Wrote {out_png} ({SHEET_W}x{SHEET_H}), {out_json.name}, and {out_4x}")


if __name__ == "__main__":
    main()
