#!/usr/bin/env python3
"""The mine's ground: one 16x16 tile atlas per zone style (docs/mine.md, section 12).

Writes assets/mine/tiles_<style>.png (8 columns x 12 rows) and data/mine_tiles.json (layout and the wall lookup the level reads):
  rows 0-1   16 floor variants (plain dirt/stone, then pebbles, cracks, scuffs)
  rows 2-7   47 wall tiles of the blob autotile (see BLOB below); drawn as seen from the south in the 3/4 view:
             a wall with floor to its SOUTH is a face (the rock front, 16 px), every other wall is the dark top of the rock mass,
             with a lit lip where floor lies north of it and thin lips along open sides
  rows 8-9   16 floor shade overlays (index = walls to the N=1 E=2 S=4 W=8 of the floor tile), drawn over the floor next to walls
Run `python3 tools/art_mine.py [preview.png]` then `Godot --headless --import`.
Neighbour bits of the blob (1 = the neighbour is WALL): N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128; corners only count when both edges next to them do.
"""
import json
import pathlib
import sys

from gen_art import ROOT, hexc, noise, write_png

COLS = 8
ROWS = 13
import math
INK = hexc("14101c")

# per style: rock (top of the mass), face (south fronts: dark, mid, light), rim (lit lip), floor (dark, mid, light, pebble), crack glow (void only)
STYLES = {
    "timber": {
        "rock": ("231d2a", "2c2434", "372d40"), "face": ("3b3040", "4e4150", "6a5866"), "rim": "a58f7c",
        "floor": ("40363e", "50444a", "62555a", "8a7a78"), "kind": "strata",
    },
    "masonry": {
        "rock": ("1f2230", "282b3c", "323649"), "face": ("33384e", "474e69", "646d8e"), "rim": "98a2c8",
        "floor": ("383c4e", "474b60", "5a5f77", "8088a8"), "kind": "bricks",
    },
    "cave": {
        "rock": ("17222f", "1f2d3d", "29394c"), "face": ("22364a", "2f4a61", "4a6e88"), "rim": "86c6e0",
        "floor": ("2c3c4e", "384c60", "4a6078", "78a0b8"), "kind": "smooth",
    },
    "void": {
        "rock": ("150f20", "1c1429", "261a35"), "face": ("2a1c3c", "3c2854", "5a3a7c"), "rim": "b070dc",
        "floor": ("2e2340", "3b2d52", "4d3c68", "7a62a0"), "kind": "cracked",
    },
}


def reduce_mask(m: int) -> int:
    if not (m & 1 and m & 4):
        m &= ~2
    if not (m & 4 and m & 16):
        m &= ~8
    if not (m & 16 and m & 64):
        m &= ~32
    if not (m & 64 and m & 1):
        m &= ~128
    return m & 255


UNIQUE = sorted({reduce_mask(m) for m in range(256)})
INDEX = {r: i for i, r in enumerate(UNIQUE)}
LOOKUP = [INDEX[reduce_mask(m)] for m in range(256)]
assert len(UNIQUE) == 47


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def floor_tile(style: dict, variant: int, seed: int):
    d, m, l, p = (hexc(c) for c in style["floor"])
    px = [[m] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            r = noise(x, y, seed + variant) / 255
            if r < 0.10:
                px[y][x] = d
            elif r > 0.93:
                px[y][x] = l
    if variant >= 4:
        kind = variant % 4
        n = noise(variant, 1, seed)
        cx, cy = 3 + n % 10, 4 + noise(variant, 2, seed) % 8
        if kind == 0:  # pebbles
            for k in range(3):
                x, y = (cx + k * 3 + noise(k, variant, seed) % 3) % 14 + 1, (cy + k * 2 + noise(k, 5, seed) % 3) % 13 + 1
                px[y][x] = p
                px[y + 1][x] = d
                if k == 1:
                    px[y][x + 1] = l
        elif kind == 1:  # a crack
            x, y = cx, 2
            for _ in range(11):
                px[y][x] = d
                y += 1
                x += noise(y, variant, seed) % 3 - 1
                x = max(1, min(14, x))
        elif kind == 2:  # a scuffed patch
            for k in range(14):
                x = (cx + noise(k, variant, seed) % 7) % 15
                y = (cy + noise(k, variant + 9, seed) % 5) % 15
                px[y][x] = l if k % 2 else d
        else:  # a dark damp patch
            for y in range(cy - 2, cy + 2):
                for x in range(cx - 3, cx + 3):
                    if 0 <= x < 16 and 0 <= y < 16 and noise(x, y, seed + 7) < 190:
                        px[y][x] = d
    return px


def wall_tile(style: dict, r: int, seed: int):
    open_n, open_e, open_s, open_w = not r & 1, not r & 4, not r & 16, not r & 64
    notch = {  # an inner corner: the diagonal neighbour is floor while both edges next to it are wall
        "ne": bool(r & 1 and r & 4 and not r & 2), "se": bool(r & 4 and r & 16 and not r & 8),
        "sw": bool(r & 16 and r & 64 and not r & 32), "nw": bool(r & 64 and r & 1 and not r & 128),
    }
    rock = [hexc(c) for c in style["rock"]]
    fd, fm, fl = (hexc(c) for c in style["face"])
    rim = hexc(style["rim"])
    kind = style["kind"]
    px = [[rock[1]] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            n = noise(x, y, seed + r) / 255
            if open_s:  # the face of the rock
                t = y / 15.0
                c = mix(fd, fm, min(1.0, t * 1.4))
                if kind == "strata":
                    if (y + noise(x // 5, 3, seed)) % 5 == 0 and n < 0.8:
                        c = fd
                    elif n > 0.93:
                        c = fl
                elif kind == "bricks":
                    row = y // 5
                    off = 4 if row % 2 else 0
                    if y % 5 == 4 or (x + off) % 8 == 0:
                        c = fd
                    elif n > 0.9:
                        c = fl
                elif kind == "smooth":
                    if n > 0.95:
                        c = fl
                    elif n < 0.05:
                        c = fd
                else:  # cracked: a dark seam
                    if abs(x - (6 + 3 * ((y // 4) % 2))) == 0 and y > 2:
                        c = INK
                    elif n > 0.94:
                        c = fl
                if y == 0 and not open_n:
                    c = rim if n < 0.7 else fl  # the top edge of the face: lit
                elif y == 1 and not open_n:
                    c = fl
                if y >= 14:
                    c = INK if y == 15 else fd
                px[y][x] = c
            else:  # the top of the mass
                c = rock[0] if n < 0.35 else (rock[2] if n > 0.9 else rock[1])
                if open_n:
                    if y == 0:
                        c = INK
                    elif y <= 2:
                        c = rim if y == 1 else fl
                px[y][x] = c
            if open_w and x == 0:
                px[y][x] = INK
            elif open_w and x == 1 and not open_s:
                px[y][x] = fl
            if open_e and x == 15:
                px[y][x] = INK
            elif open_e and x == 14 and not open_s:
                px[y][x] = fd
    for name, (cx, cy) in {"ne": (15, 0), "se": (15, 15), "sw": (0, 15), "nw": (0, 0)}.items():
        if notch[name]:  # a little floor corner pokes in: round it off
            for dy in range(3):
                for dx in range(3):
                    x = cx - dx if cx else dx
                    y = cy - dy if cy else dy
                    if dx + dy < 3:
                        px[y][x] = INK if dx + dy == 2 else fd
    return px


def shade_tile(mask: int):
    """Darkness a floor tile gets from the walls around it (N=1 E=2 S=4 W=8)."""
    px = [[(0, 0, 0, 0)] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            a = 0.0
            if mask & 1:
                a = max(a, 0.62 * max(0.0, 1.0 - y / 7.0))
            if mask & 4:
                a = max(a, 0.30 * max(0.0, 1.0 - (15 - y) / 4.0))
            if mask & 2:
                a = max(a, 0.36 * max(0.0, 1.0 - (15 - x) / 5.0))
            if mask & 8:
                a = max(a, 0.32 * max(0.0, 1.0 - x / 5.0))
            if a > 0.0:
                a = round(a * 4) / 4  # stepped: pixel art, no smooth gradient
                px[y][x] = (10, 6, 18, int(255 * a))
    return px


RAILS_ROW = 12


def rails_tiles():
    """Rails as 16 x 16 floor tiles seen from above: 0 horizontal, 1 vertical, 2 curve N-E, 3 curve S-E, 4 curve S-W, 5 curve N-W, 6 buffer stop (end, rail runs west), 7 buffer stop (rail runs north)."""
    SLEEPER, SLEEPER_L, RAIL, RAIL_L, INK = hexc("2a1c22"), hexc("4c3433"), hexc("55556f"), hexc("a9a9c8"), hexc("14101c")
    tiles = []

    def blank():
        return [[(0, 0, 0, 0)] * 16 for _ in range(16)]

    def put(t, x, y, c):
        if 0 <= x < 16 and 0 <= y < 16:
            t[y][x] = c

    def horizontal(t, y0=0, x0=0, x1=15):
        for x in range(x0, x1 + 1):
            if (x // 2) % 2 == 0 or x % 4 == 1:
                pass
        for sx in range(x0 + 1, x1 + 1, 5):  # sleepers
            for y in range(y0 + 3, y0 + 13):
                put(t, sx, y, SLEEPER)
                put(t, sx + 1, y, SLEEPER_L)
        for y, c in ((y0 + 5, RAIL_L), (y0 + 6, RAIL), (y0 + 10, RAIL_L), (y0 + 11, RAIL)):
            for x in range(x0, x1 + 1):
                put(t, x, y, c)

    def vertical(t):
        for sy in range(1, 16, 5):
            for x in range(3, 13):
                put(t, x, sy, SLEEPER)
                put(t, x, sy + 1, SLEEPER_L)
        for x, c in ((5, RAIL_L), (6, RAIL), (9, RAIL_L), (10, RAIL)):
            for y in range(16):
                put(t, x, y, c)

    t = blank()
    horizontal(t)
    tiles.append(t)
    t = blank()
    vertical(t)
    tiles.append(t)
    for corner in ("ne", "se", "sw", "nw"):  # quarter turns: two rails on arcs
        t = blank()
        for step in range(16):
            for r0, c in ((4.5, RAIL), (9.5, RAIL_L)):
                a = step / 15 * (math.pi / 2)
                for rr in (r0, r0 + 1.0):
                    x, y = rr * math.sin(a) + 0, rr * math.cos(a) + 0
                    put(t, int(round(x)), int(round(y)), c)
        # rotate the NE-origin arcs into place
        arcs = t
        t = blank()
        for y in range(16):
            for x in range(16):
                if arcs[y][x] != (0, 0, 0, 0):
                    nx, ny = {"ne": (x, 15 - y), "se": (x, y), "sw": (15 - x, y), "nw": (15 - x, 15 - y)}[corner]
                    t[ny][nx] = arcs[y][x]
        tiles.append(t)
    t = blank()
    horizontal(t, x1=11)
    for y in range(3, 13):
        put(t, 12, y, INK)
        put(t, 13, y, hexc("6a3426"))
    tiles.append(t)
    t = blank()
    vertical(t)
    for y in range(0, 16):
        pass
    for x in range(3, 13):
        put(t, x, 2, INK)
        put(t, x, 3, hexc("6a3426"))
    for y in range(0, 2):
        for x in range(16):
            t[y][x] = (0, 0, 0, 0)
    tiles.append(t)
    return tiles



def atlas(style: dict, seed: int):
    px = [[(0, 0, 0, 0)] * (COLS * 16) for _ in range(ROWS * 16)]

    def put(tile, col, row):
        for y in range(16):
            for x in range(16):
                px[row * 16 + y][col * 16 + x] = tile[y][x]

    for v in range(16):
        put(floor_tile(style, v, seed), v % COLS, v // COLS)
    for i, r in enumerate(UNIQUE):
        put(wall_tile(style, r, seed), i % COLS, 2 + i // COLS)
    for m in range(16):
        put(shade_tile(m), m % COLS, 8 + m // COLS)
    for i, t in enumerate(rails_tiles()):
        put(t, i, RAILS_ROW)
    return px


def main() -> None:
    out = ROOT / "mine"
    for i, (name, style) in enumerate(STYLES.items()):
        write_png(out / f"tiles_{name}.png", COLS * 16, ROWS * 16, atlas(style, 40 + i * 11))
    table = {"tile": 16, "cols": COLS, "floor_row": 0, "floor_count": 16, "wall_row": 2, "wall_count": 47, "shade_row": 8, "rails_row": RAILS_ROW, "blob": LOOKUP,
             "full": INDEX[255], "styles": {name: f"res://assets/mine/tiles_{name}.png" for name in STYLES},
             "backdrops": {name: "#" + style["rock"][1] for name, style in STYLES.items()}}
    (ROOT.parent / "data" / "mine_tiles.json").write_text(json.dumps(table, separators=(",", ":")) + "\n")
    print("wrote", out, "and data/mine_tiles.json; full wall tile index", INDEX[255])
    if len(sys.argv) > 1:  # a preview: every style's atlas on a lighter ground, enlarged 3x
        import struct
        import zlib
        rows = []
        for name in STYLES:
            rows.extend(atlas(STYLES[name], 40 + list(STYLES).index(name) * 11))
        scale = 3
        w, h = COLS * 16 * scale, len(rows) * scale
        raw = b"".join(
            b"\x00" + b"".join(bytes((90, 90, 100) if rows[y // scale][x // scale][3] == 0 else rows[y // scale][x // scale][:3]) if rows[y // scale][x // scale][3] == 255 else bytes(
                (int(90 + (rows[y // scale][x // scale][0] - 90) * rows[y // scale][x // scale][3] / 255),
                 int(90 + (rows[y // scale][x // scale][1] - 90) * rows[y // scale][x // scale][3] / 255),
                 int(100 + (rows[y // scale][x // scale][2] - 100) * rows[y // scale][x // scale][3] / 255))) for x in range(w))
            for y in range(h)
        )

        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

        pathlib.Path(sys.argv[1]).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    main()
