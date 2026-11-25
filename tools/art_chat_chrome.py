#!/usr/bin/env python3
"""Generate hand-crafted pixel-art UI chrome & seamless 1:1 tiles for Shadowspore's Whisper Vine Chat.

Outputs:
  - assets/ui/chat_chrome.png (256x192 nearest-filtered sprite sheet)
  - docs/img/chat_chrome_4x.png (4x visual inspection sheet, behind docs/.gdignore)

Palette & craft follow docs/design_guide.md & shadowspore-pixel-art:
  - Tinted obsidian outline (#0b0716), zero pure #000000
  - Top-left light source, 3-4 tonal steps per material, clean directional clusters
  - Seamless 1:1 organic bark-vellum & recessed obsidian-well tiles (never stretched)
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_SHEET = ROOT / "assets" / "ui" / "chat_chrome.png"
OUT_PREVIEW = ROOT / "docs" / "img" / "chat_chrome_4x.png"

SHEET_W = 256
SHEET_H = 192

CLEAR = (0, 0, 0, 0)
OUTLINE = (11, 7, 22, 255)       # #0b0716 tinted obsidian

# Bark-vellum obsidian (warm smoky night-parchment)
VELLUM_0 = (16, 12, 29, 255)     # #100c1d deep crease
VELLUM_1 = (21, 16, 37, 255)     # #151025 base smoked vellum
VELLUM_2 = (28, 22, 48, 255)     # #1c1630 fiber cluster
VELLUM_3 = (37, 29, 62, 255)     # #251d3e subtle highlight grain

# Night-void vellum (cooler, deeper abyssal tone with faint violet sheen)
VOID_0 = (11, 8, 22, 255)        # #0b0816
VOID_1 = (15, 11, 30, 255)       # #0f0b1e
VOID_2 = (22, 16, 44, 255)       # #16102c
VOID_3 = (34, 23, 66, 255)       # #221742

# Recessed input trough
WELL_0 = (10, 8, 20, 255)        # #0a0814 deep shadow lip
WELL_1 = (14, 11, 27, 255)       # #0e0b1b base recess
WELL_2 = (19, 15, 35, 255)       # #130f23 soft grain
WELL_RIM = (56, 46, 92, 255)     # #382e5c recessed rim
WELL_LIT = (86, 72, 134, 255)    # #564886 subtle glint

# Living Bark frame tones (matching VineStyle)
BARK_0 = (26, 18, 36, 255)       # #1a1224
BARK_1 = (46, 34, 56, 255)       # #2e2238
BARK_2 = (74, 56, 86, 255)       # #4a3856
BARK_3 = (110, 86, 122, 255)     # #6e567a catchlight

# Brass / Gold accents
GOLD_0 = (96, 68, 28, 255)       # #60441c
GOLD_1 = (164, 122, 50, 255)     # #a47a32
GOLD_2 = (230, 196, 104, 255)    # #e6c468
GOLD_3 = (255, 240, 176, 255)    # #fff0b0

# Turquoise Life / Spiel glow
TEAL_0 = (32, 110, 118, 255)     # #206e76
TEAL_1 = (60, 192, 198, 255)     # #3cc0c6
TEAL_2 = (120, 244, 230, 255)    # #78f4e6
TEAL_3 = (212, 255, 248, 255)    # #d4fff8

# Violet Void / Whisper glow
VIO_0 = (56, 26, 102, 255)       # #381a66
VIO_1 = (114, 64, 186, 255)      # #7240ba
VIO_2 = (176, 130, 248, 255)     # #b082f8
VIO_3 = (228, 206, 255, 255)     # #e4ceff

# Moss / Leaf
LEAF_0 = (32, 74, 54, 255)       # #204a36
LEAF_1 = (58, 122, 82, 255)      # #3a7a52
LEAF_2 = (104, 180, 114, 255)    # #68b472
LEAF_3 = (166, 230, 143, 255)    # #a6e68f

# Rose / Close / Alert
ROSE_0 = (118, 34, 62, 255)      # #76223e
ROSE_1 = (184, 64, 102, 255)     # #b84066
ROSE_2 = (238, 122, 156, 255)    # #ee7a9c
ROSE_3 = (255, 204, 220, 255)    # #ffccdc

# Muted slate for idle glyphs
DIM_0 = (52, 46, 78, 255)
DIM_1 = (90, 82, 124, 255)
DIM_2 = (142, 134, 178, 255)
DIM_3 = (198, 192, 224, 255)


def make_grid(w: int, h: int, fill=CLEAR):
    return [[fill for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, c) -> None:
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = c


def fill_rect(px, x: int, y: int, w: int, h: int, c) -> None:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(px, xx, yy, c)


def blit(dst, src, ox: int, oy: int) -> None:
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                put(dst, ox + x, oy + y, c)


def add_outline(px, col=OUTLINE):
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


def write_png(path: Path, w: int, h: int, grid) -> None:
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


def scale_grid(grid, factor: int):
    h, w = len(grid), len(grid[0])
    out = make_grid(w * factor, h * factor, (18, 15, 30, 255))
    # Subtle dark checker for transparent inspection
    for y in range(h * factor):
        for x in range(w * factor):
            if ((x // 8) + (y // 8)) % 2 == 0:
                out[y][x] = (24, 20, 40, 255)
    for y in range(h):
        for x in range(w):
            c = grid[y][x]
            if c[3] == 0:
                continue
            for dy in range(factor):
                for dx in range(factor):
                    # Alpha blend onto checker
                    bg = out[y * factor + dy][x * factor + dx]
                    a = c[3] / 255.0
                    out[y * factor + dy][x * factor + dx] = (
                        int(c[0] * a + bg[0] * (1 - a)),
                        int(c[1] * a + bg[1] * (1 - a)),
                        int(c[2] * a + bg[2] * (1 - a)),
                        255,
                    )
    return out


# ------------------------------------------------------------------ 9-slice frames

def build_card_frame() -> list:
    """24x24 organic beveled bark-vellum 9-slice frame (margins 6,6,6,6)."""
    g = make_grid(24, 24)
    for y in range(24):
        for x in range(24):
            corner = (x in (0, 23) and y in (0, 23)) or (x in (0, 23) and y in (1, 22)) or (x in (1, 22) and y in (0, 23))
            if corner:
                continue
            edge_dist = min(x, 23 - x, y, 23 - y)
            if edge_dist == 0 or (x in (1, 22) and y in (1, 22)):
                g[y][x] = OUTLINE
            elif edge_dist == 1:
                # Top & left lit bark rim; bottom & right shadowed
                if y == 1 or x == 1:
                    g[y][x] = BARK_3 if (x + y) % 4 != 0 else BARK_2
                else:
                    g[y][x] = BARK_1 if (x + y) % 3 != 0 else BARK_0
            elif edge_dist == 2:
                if y == 2 or x == 2:
                    g[y][x] = BARK_2 if (x % 3 != 0) else BARK_1
                else:
                    g[y][x] = VELLUM_0
            else:
                g[y][x] = VELLUM_1
    # Corner brass-bark studs
    for cx, cy in ((2, 2), (21, 2), (2, 21), (21, 21)):
        put(g, cx, cy, GOLD_1 if cy < 12 else BARK_2)
    put(g, 3, 2, GOLD_2)
    put(g, 2, 3, GOLD_1)
    return g


def build_input_frame() -> list:
    """20x16 recessed obsidian bark input well (margins 5,4,5,4)."""
    g = make_grid(20, 16)
    for y in range(16):
        for x in range(20):
            if (x in (0, 19)) and (y in (0, 15)):
                continue
            if x == 0 or x == 19 or y == 0 or y == 15:
                g[y][x] = OUTLINE
            elif y == 1:
                g[y][x] = WELL_0
            elif y == 14:
                g[y][x] = WELL_RIM if 2 <= x <= 17 else WELL_0
            elif x == 1:
                g[y][x] = WELL_0
            elif x == 18:
                g[y][x] = WELL_RIM if 2 <= y <= 13 else WELL_0
            elif y == 2:
                g[y][x] = WELL_0 if (x % 4 == 0) else WELL_1
            else:
                g[y][x] = WELL_1
    # Corner inner bevels
    put(g, 1, 1, OUTLINE)
    put(g, 18, 1, OUTLINE)
    put(g, 1, 14, OUTLINE)
    put(g, 18, 14, OUTLINE)
    return g


def build_suggest_frame() -> list:
    """20x20 floating suggestion leaf frame (margins 5,5,5,5)."""
    g = make_grid(20, 20)
    for y in range(20):
        for x in range(20):
            if (x in (0, 19)) and (y in (0, 19)):
                continue
            if x == 0 or x == 19 or y == 0 or y == 19:
                g[y][x] = OUTLINE
            elif y == 1 or x == 1:
                g[y][x] = WELL_LIT if (y == 1 and 2 <= x <= 17) else WELL_RIM
            elif y == 18 or x == 18:
                g[y][x] = BARK_0
            elif y == 2:
                g[y][x] = VELLUM_3
            else:
                g[y][x] = VELLUM_1
    put(g, 2, 2, GOLD_2)
    put(g, 17, 2, GOLD_1)
    return g


def build_tab_pill(active: bool) -> list:
    """24x16 channel tab pill (margins 5,4,5,4)."""
    g = make_grid(24, 16)
    for y in range(16):
        for x in range(24):
            if (x in (0, 23)) and (y in (0, 15)):
                continue
            if x in (0, 23) or y in (0, 15):
                g[y][x] = OUTLINE
            elif active:
                if y == 1:
                    g[y][x] = BARK_3 if 2 <= x <= 21 else BARK_2
                elif y == 2:
                    g[y][x] = VELLUM_3
                elif y == 14:
                    g[y][x] = VELLUM_0
                elif x == 1:
                    g[y][x] = BARK_2
                elif x == 22:
                    g[y][x] = BARK_1
                else:
                    g[y][x] = VELLUM_2 if y < 8 else VELLUM_1
            else:
                if y == 1:
                    g[y][x] = BARK_1 if 2 <= x <= 21 else BARK_0
                elif y == 14 or x in (1, 22):
                    g[y][x] = WELL_0
                else:
                    g[y][x] = WELL_1 if y < 9 else WELL_0
    return g


# ------------------------------------------------------------------ 1:1 Seamless Surface Tiles

def build_vellum_tile(night: bool = False) -> list:
    """48x48 seamless organic bark-vellum 1:1 texture with directional fiber clusters (no random noise)."""
    c0, c1, c2, c3 = (VOID_0, VOID_1, VOID_2, VOID_3) if night else (VELLUM_0, VELLUM_1, VELLUM_2, VELLUM_3)
    g = make_grid(48, 48, c1)

    # Soft horizontal fibrous weave strokes (ordered directional clusters)
    strokes = [
        (3, 4, 7, c2), (18, 6, 9, c0), (34, 3, 8, c2),
        (8, 12, 10, c0), (26, 11, 6, c2), (40, 14, 7, c0),
        (1, 20, 8, c2), (15, 22, 11, c2), (33, 19, 9, c0),
        (5, 29, 9, c0), (22, 31, 8, c2), (37, 28, 7, c2),
        (11, 38, 10, c2), (29, 36, 7, c0), (42, 41, 6, c2),
        (2, 44, 8, c0), (19, 45, 9, c2),
    ]
    for sx, sy, length, col in strokes:
        for i in range(length):
            px = (sx + i) % 48
            py = (sy + (1 if i >= length // 2 and length > 7 else 0)) % 48
            g[py][px] = col

    # Delicate diagonal bark-grain catchlights (3-4 px clusters)
    glints = [(6, 5), (27, 12), (17, 23), (39, 29), (13, 39), (21, 45)]
    for gx, gy in glints:
        g[gy % 48][gx % 48] = c3
        g[gy % 48][(gx + 1) % 48] = c3
        g[(gy + 1) % 48][(gx + 2) % 48] = c2

    # Tiny woven organic vein knots
    knots = [(12, 16), (36, 9), (24, 34), (4, 36)]
    for kx, ky in knots:
        g[ky % 48][kx % 48] = c0
        g[ky % 48][(kx + 1) % 48] = c0
        g[(ky + 1) % 48][(kx + 1) % 48] = c2
        if night:
            # Faint void filament hint in deep night vellum
            g[(ky - 1) % 48][kx % 48] = (38, 24, 76, 255)
    return g


def build_input_well_tile() -> list:
    """32x16 seamless recessed obsidian well interior."""
    g = make_grid(32, 16, WELL_1)
    for x in range(32):
        if x % 8 in (1, 2, 3):
            g[2][x] = WELL_0
        if x % 10 in (4, 5, 6):
            g[6][x] = WELL_2
        if x % 12 in (2, 3, 4, 5):
            g[10][x] = WELL_0
        if x % 9 in (6, 7):
            g[13][x] = WELL_2
    return g


# ------------------------------------------------------------------ Ornate Vine Corner Clasps (12x12)

def build_corner_nw() -> list:
    """12x12 organic curled bark clasp with brass bud & moss leaves (NW corner)."""
    art = [
        "............",
        "..ooo.......",
        ".oBBbooo....",
        ".oBGGbBBoo..",
        ".oBG3BBbLLo.",
        ".oBBb..oLlo.",
        "..ob....oo..",
        "..ob........",
        "..oBo.......",
        "..oLlo......",
        "...oo.......",
        "............",
    ]
    pal = {
        ".": CLEAR,
        "o": OUTLINE,
        "b": BARK_1,
        "B": BARK_2,
        "G": GOLD_2,
        "3": GOLD_3,
        "L": LEAF_1,
        "l": LEAF_3,
    }
    return [[pal[ch] for ch in row] for row in art]


def flip_h(grid):
    return [list(reversed(row)) for row in grid]


def flip_v(grid):
    return list(reversed([row[:] for row in grid]))


# ------------------------------------------------------------------ Pixel-Art Channel Emblems & Micro-Icons (11x11)

def glyph_from_ascii(art: list[str], pal: dict[str, tuple[int, int, int, int]]) -> list:
    return [[pal.get(ch, CLEAR) for ch in row] for row in art]


def build_icon_spiel(lit: bool) -> list:
    """11x11 World/Game Spore Blossom (turquoise when lit, muted slate when idle)."""
    c0, c1, c2, c3 = (TEAL_0, TEAL_1, TEAL_2, TEAL_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "....ooo....",
        "...o232o...",
        "..o12321o..",
        ".o1o121o1o.",
        "o231232132o",
        "o122333221o",
        "o011232110o",
        ".o0o010o0o.",
        "..o01210o..",
        "...o010o...",
        "....ooo....",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_gruppe(lit: bool) -> list:
    """11x11 Co-op Hearth / Twin-Spore Crest (golden when lit)."""
    c0, c1, c2, c3 = (GOLD_0, GOLD_1, GOLD_2, GOLD_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "....ooo....",
        "...o232o...",
        "..o12321o..",
        ".oo01210oo.",
        "o23o121o32o",
        "o121232121o",
        "o011121110o",
        ".oo01210oo.",
        "..o00100o..",
        "...ooooo...",
        "...........",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_direkt(lit: bool) -> list:
    """11x11 Whisper Moon-Moth / Sealed Letter (lilac-violet when lit)."""
    c0, c1, c2, c3 = (VIO_0, VIO_1, VIO_2, VIO_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "...........",
        ".ooooooooo.",
        "o322222221o",
        "o2o32223o1o",
        "o21o232o10o",
        "o111o3o110o",
        "o11o121o00o",
        "o1o11111o0o",
        "o000000000o",
        ".ooooooooo.",
        "...........",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_plus(lit: bool) -> list:
    """11x11 New Whisper '+' bud."""
    c0, c1, c2, c3 = (VIO_0, VIO_1, VIO_2, VIO_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "...........",
        "....ooo....",
        "....o3o....",
        "....o2o....",
        ".oooo2oooo.",
        ".o3223221o.",
        ".oooo1oooo.",
        "....o1o....",
        "....o0o....",
        "....ooo....",
        "...........",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_send(lit: bool) -> list:
    """11x11 Bioluminescent Send Arrow / Spore Dart."""
    c0, c1, c2, c3 = (TEAL_0, TEAL_1, TEAL_2, TEAL_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "...........",
        "..ooo......",
        ".o322oo....",
        ".o22322oo..",
        "..o123332o.",
        "..o0123332o",
        "..o122221o.",
        ".o11111oo..",
        ".o000oo....",
        "..ooo......",
        "...........",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_expand(expanded: bool) -> list:
    """11x11 Expand / Compact chevron."""
    if not expanded:
        art = [
            "...........",
            "...........",
            "....ooo....",
            "...o232o...",
            "..o12o21o..",
            ".o12o.o21o.",
            ".o0o...o0o.",
            "..o.....o..",
            "...........",
            "...........",
            "...........",
        ]
    else:
        art = [
            "...........",
            "...........",
            "..o.....o..",
            ".o2o...o2o.",
            ".o12o.o21o.",
            "..o01o10o..",
            "...o010o...",
            "....ooo....",
            "...........",
            "...........",
            "...........",
        ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": DIM_0, "1": DIM_1, "2": DIM_2, "3": GOLD_3})


def build_icon_close(lit: bool) -> list:
    """11x11 Close blossom 'x'."""
    c0, c1, c2, c3 = (ROSE_0, ROSE_1, ROSE_2, ROSE_3) if lit else (DIM_0, DIM_1, DIM_2, DIM_3)
    art = [
        "...........",
        ".oo.....oo.",
        "o32o...o21o",
        "o221o.o110o",
        ".o123o210o.",
        "..o13320o..",
        ".o122o110o.",
        "o210o.o010o",
        "o10o...o00o",
        ".oo.....oo.",
        "...........",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": c0, "1": c1, "2": c2, "3": c3})


def build_icon_pin() -> list:
    """11x11 Location / Waystone pin glyph for /ort."""
    art = [
        "...ooooo...",
        "..o23321o..",
        ".o23ooo21o.",
        ".o2o321o1o.",
        ".o1o210o0o.",
        "..o1ooo0o..",
        "..o01210o..",
        "...o010o...",
        "....o1o....",
        "....o0o....",
        ".....o.....",
    ]
    return glyph_from_ascii(art, {".": CLEAR, "o": OUTLINE, "0": TEAL_0, "1": TEAL_1, "2": TEAL_2, "3": TEAL_3})


def build_icon_bud_unread() -> list:
    """11x11 Bioluminescent Unread Whisper Spore Bud."""
    art = [
        "....ooo....",
        "...o232o...",
        "..o23332o..",
        ".o1233321o.",
        ".o1233321o.",
        "..o01210o..",
        "...o010o...",
        "..oLo0oLo..",
        ".oLlLoLlLo.",
        "..ooo.ooo..",
        "...........",
    ]
    return glyph_from_ascii(art, {
        ".": CLEAR, "o": OUTLINE,
        "0": GOLD_0, "1": GOLD_1, "2": GOLD_2, "3": GOLD_3,
        "L": LEAF_1, "l": LEAF_3,
    })


def build_bloom_slider() -> list:
    """24x7 glowing sliding channel bloom indicator."""
    art = [
        "..........oooo..........",
        ".......ooo2332ooo.......",
        "..ooooo1223333221ooooo..",
        ".o01122333333333322110o.",
        "..ooooo0112332110ooooo..",
        ".......ooo0110ooo.......",
        "..........oooo..........",
    ]
    # White-neutral so Godot can tint it cleanly to TEAL / GOLD / LILAC!
    return glyph_from_ascii(art, {
        ".": CLEAR,
        "o": (11, 7, 22, 190),
        "0": (128, 128, 148, 220),
        "1": (184, 184, 206, 240),
        "2": (230, 230, 244, 255),
        "3": (255, 255, 255, 255),
    })


def build_scroll_rail() -> list:
    """5x16 carved bark scrollbar track."""
    g = make_grid(5, 16)
    for y in range(16):
        g[y][1] = OUTLINE
        g[y][2] = WELL_0
        g[y][3] = (34, 28, 56, 180)
    return g


def build_scroll_thumb(lit: bool) -> list:
    """5x14 obsidian-gold scrollbar thumb."""
    c_body = GOLD_2 if lit else BARK_2
    c_hi = GOLD_3 if lit else BARK_3
    c_lo = GOLD_0 if lit else BARK_1
    g = make_grid(5, 14)
    for y in range(14):
        for x in range(5):
            if (x in (0, 4)) and (y in (0, 13)):
                continue
            if x in (0, 4) or y in (0, 13):
                g[y][x] = OUTLINE
            elif x == 1:
                g[y][x] = c_hi if y < 11 else c_body
            elif x == 2:
                g[y][x] = c_body if y not in (5, 8) else c_hi
            else:
                g[y][x] = c_lo
    return g


def main() -> None:
    sheet = make_grid(SHEET_W, SHEET_H, CLEAR)

    # Row 0 (y=4): 9-slice frames
    blit(sheet, build_card_frame(), 4, 4)          # (4, 4, 24, 24)
    blit(sheet, build_input_frame(), 32, 4)        # (32, 4, 20, 16)
    blit(sheet, build_suggest_frame(), 56, 4)      # (56, 4, 20, 20)
    blit(sheet, build_tab_pill(False), 80, 4)      # (80, 4, 24, 16)
    blit(sheet, build_tab_pill(True), 108, 4)      # (108, 4, 24, 16)

    # Corner clasps (y=4, x=136..196)
    nw = build_corner_nw()
    blit(sheet, nw, 136, 4)                        # (136, 4, 12, 12) NW
    blit(sheet, flip_h(nw), 152, 4)                # (152, 4, 12, 12) NE
    blit(sheet, flip_v(nw), 168, 4)                # (168, 4, 12, 12) SW
    blit(sheet, flip_v(flip_h(nw)), 184, 4)        # (184, 4, 12, 12) SE

    # Bloom slider & scrollbars (y=4, x=200..252)
    blit(sheet, build_bloom_slider(), 200, 4)      # (200, 4, 24, 7)
    blit(sheet, build_scroll_rail(), 228, 4)       # (228, 4, 5, 16)
    blit(sheet, build_scroll_thumb(False), 236, 4) # (236, 4, 5, 14)
    blit(sheet, build_scroll_thumb(True), 244, 4)  # (244, 4, 5, 14)

    # Row 1 (y=36): Idle icons (11x11 at 16px stride)
    # Row 2 (y=52): Lit/active icons (11x11 at 16px stride)
    icons_idle = [
        build_icon_spiel(False),
        build_icon_gruppe(False),
        build_icon_direkt(False),
        build_icon_plus(False),
        build_icon_send(False),
        build_icon_expand(False),
        build_icon_close(False),
        build_icon_pin(),
        build_icon_bud_unread(),
    ]
    icons_lit = [
        build_icon_spiel(True),
        build_icon_gruppe(True),
        build_icon_direkt(True),
        build_icon_plus(True),
        build_icon_send(True),
        build_icon_expand(True),
        build_icon_close(True),
        build_icon_pin(),
        build_icon_bud_unread(),
    ]
    for idx, ic in enumerate(icons_idle):
        blit(sheet, ic, 4 + idx * 16, 36)
    for idx, ic in enumerate(icons_lit):
        blit(sheet, ic, 4 + idx * 16, 52)

    # Row 3 (y=72): 1:1 Seamless Surface Tiles
    blit(sheet, build_vellum_tile(False), 4, 72)   # (4, 72, 48, 48) Day Bark-Vellum
    blit(sheet, build_vellum_tile(True), 56, 72)   # (56, 72, 48, 48) Night Void-Vellum
    blit(sheet, build_input_well_tile(), 108, 72)  # (108, 72, 32, 16) Recessed Input Well

    write_png(OUT_SHEET, SHEET_W, SHEET_H, sheet)
    write_png(OUT_PREVIEW, SHEET_W * 4, SHEET_H * 4, scale_grid(sheet, 4))
    print(f"Wrote {OUT_SHEET} and {OUT_PREVIEW}")


if __name__ == "__main__":
    main()
