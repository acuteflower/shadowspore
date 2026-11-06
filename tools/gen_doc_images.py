#!/usr/bin/env python3
"""Builds the reference images of docs/design_guide.md from the real assets (stdlib only).
Run after changing art:  python3 tools/gen_doc_images.py
  docs/img/palette.png         the colour families of the game
  docs/img/scale.png           everything side by side at one scale, on a tile ruler
  docs/img/hero_animation.png  facings, idle, walk, sprint, the three attacks, picking and eating of the heroine
  docs/img/items_ground.png    item icons with their rarity frames, and the meadow atlas
  docs/img/bushes.png          the meadow's bushes, their states and the things you get from them
"""
import pathlib
import struct
import zlib

from gen_art import ROOT, hexc, write_png

OUT = ROOT.parent / "docs" / "img"
BG = hexc("3e7d56")  # base meadow green
PANEL = hexc("2a2548")


def read_png(path: pathlib.Path):
    data = path.read_bytes()
    i, idat, w, h, ct = 8, b"", 0, 0, 6
    while i < len(data):
        n = struct.unpack(">I", data[i:i + 4])[0]
        tag = data[i + 4:i + 8]
        if tag == b"IHDR":
            w, h, _, ct = struct.unpack(">IIBB", data[i + 8:i + 18])
        elif tag == b"IDAT":
            idat += data[i + 8:i + 8 + n]
        i += 12 + n
    raw = zlib.decompress(idat)
    bpp = 4 if ct == 6 else 3
    stride = w * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line)
        prev = line
    return [[tuple(rows[y][x * bpp:(x + 1) * bpp]) + ((255,) if bpp == 3 else ()) for x in range(w)] for y in range(h)]


class Canvas:
    def __init__(self, w: int, h: int, bg=BG) -> None:
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]

    def rect(self, x: int, y: int, w: int, h: int, color) -> None:
        for yy in range(max(0, y), min(self.h, y + h)):
            row = self.px[yy]
            for xx in range(max(0, x), min(self.w, x + w)):
                row[xx] = color

    def blit(self, img, x: int, y: int, scale: int = 1, region=None) -> None:
        """Alpha-blends `img` (rows of RGBA) with its top-left at (x, y); `region` = (x0, y0, w, h) crops."""
        x0, y0, rw, rh = region or (0, 0, len(img[0]), len(img))
        for sy in range(rh):
            for sx in range(rw):
                r, g, b, a = img[y0 + sy][x0 + sx]
                if a == 0:
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        px, py = x + sx * scale + dx, y + sy * scale + dy
                        if 0 <= px < self.w and 0 <= py < self.h:
                            if a == 255:
                                self.px[py][px] = (r, g, b, 255)
                            else:
                                br, bg_, bb, _ = self.px[py][px]
                                k = a / 255
                                self.px[py][px] = (int(r * k + br * (1 - k)), int(g * k + bg_ * (1 - k)), int(b * k + bb * (1 - k)), 255)

    def save(self, name: str) -> None:
        write_png(OUT / name, self.w, self.h, self.px)


def swatch(canvas: Canvas, x: int, y: int, colors, size: int = 26) -> int:
    for i, c in enumerate(colors):
        canvas.rect(x + i * (size + 3) - 1, y - 1, size + 2, size + 2, hexc("120e1f"))
        canvas.rect(x + i * (size + 3), y, size, size, c)
    return x + len(colors) * (size + 3)


def palette() -> None:
    families = [
        ["22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c"],  # meadow
        ["8f84c2", "bdb3e4", "e9e3f7", "fffaf0"],  # hair
        ["d79a88", "efc0a8", "f9dcc6", "fff1e4"],  # skin
        ["09060f", "150f22", "2c2347", "6a5aa6"],  # black leather
        ["1e1626", "372a40", "574560", "7d6a86"],  # boots
        ["34185e", "6636ad", "9468ee", "cbaaff"],  # violet trim
        ["6f5020", "b48a38", "e6c468", "fff0b0"],  # gold
        ["2a8c94", "3cc0c6", "78f4e6", "d0fff8"],  # teal glow
        ["040208", "07040d", "0e0919", "1a1030", "221740", "5a36b8", "8a4dff", "b06bff", "ecd2ff"],  # void creatures
        ["ff4fd8", "c21f3b", "ff4a63", "ffd0d6"],  # eyes/warning magenta, danger zone reds
        ["b8b8c8", "6fd08c", "5aa8ff", "b47aff", "ffb347"],  # rarities
        ["1b1a2e", "171329", "1e1a36", "2a2548", "4a4180", "8a84ad", "e8e4f4", "7fe3da"],  # ui
    ]
    canvas = Canvas(9 * 29 + 20, len(families) * 34 + 14, hexc("1b1a2e"))
    for row, colors in enumerate(families):
        swatch(canvas, 10, 12 + row * 34, [hexc(c) for c in colors])
    canvas.save("palette.png")


def frame(sheet, col: int, row: int, w: int, h: int):
    return [r[col * w:(col + 1) * w] for r in sheet[row * h:(row + 1) * h]]


def scale_lineup() -> None:
    hero = read_png(ROOT / "characters" / "player.png")
    spider = read_png(ROOT / "enemies" / "shadow_spider_body.png")
    dummy = read_png(ROOT / "props" / "training_dummy.png")
    grass = read_png(ROOT / "tiles" / "grass.png")
    icons = [read_png(ROOT / "items" / f"{n}.png") for n in ("sword_basic", "sword_iron", "void_splinter", "shadow_core")]
    held = read_png(ROOT / "items" / "sword_basic_held.png")
    k = 4
    width, height = 860, 330
    c = Canvas(width, height, hexc("3e7d56"))
    ground = height - 40
    for ty in range(0, 5):  # tile ruler: each band is 16 px
        for tx in range(0, width // (16 * k) + 1):
            tile = (tx * 7 + ty * 3) % 3
            c.blit(grass, tx * 16 * k, ground - (ty + 1) * 16 * k, k, region=(tile * 16, 0, 16, 16))
    for ty in range(1, 5):
        c.rect(0, ground - ty * 16 * k, width, 1, hexc("22483c"))
    c.rect(0, ground, width, 1, hexc("22483c"))
    c.blit(frame(hero, 12, 2, 48, 56), 100 - 24 * k, ground - 51 * k, k)  # feet at (24, 51)
    c.blit(frame(spider, 2, 0, 32, 26), 220, ground - 22 * k, k)
    c.blit(dummy, 380, ground - 30 * k, k)
    x = 520
    for icon in icons:
        c.blit(icon, x, ground - 16 * k - 8, k)
        x += 16 * k + 6
    c.blit(held, 520, ground - 16 * k - 8 - 12 * k, k)
    c.save("scale.png")


def hero_animation() -> None:
    hero = read_png(ROOT / "characters" / "player.png")
    attack = read_png(ROOT / "characters" / "player_attack.png")
    pick = read_png(ROOT / "characters" / "player_pick.png")
    eat = read_png(ROOT / "characters" / "player_eat.png")
    k = 2
    fw, fh = 48, 56
    cell_w, cell_h = fw * k, fh * k
    rows = [
        [(hero, c, r) for r in range(8) for c in (12,)],  # the eight facings
        [(hero, c, 2) for c in range(12, 16)] + [(hero, c, 4) for c in range(12, 16)],  # idle: south, west
        [(hero, c, 4) for c in range(0, 6)],  # walk, facing west
        [(hero, c, 4) for c in range(6, 12)],  # sprint, facing west
        [(attack, (0 * 7 + 0) * 6 + c, 0) for c in range(6)],  # forehand, facing east, planted legs
        [(attack, (1 * 7 + 0) * 6 + c, 0) for c in range(6)],  # backhand
        [(attack, (2 * 7 + 0) * 6 + c, 0) for c in range(6)],  # thrust
        [(pick, c, 4) for c in range(12)],  # picking, facing west (one second)
        [(eat, c, 4) for c in range(12)],  # eating a berry, facing west (one second)
    ]
    width = max(len(r) for r in rows) * cell_w
    canvas = Canvas(width, len(rows) * cell_h, hexc("3e7d56"))
    for ri, row in enumerate(rows):
        for ci, (sheet, col, r) in enumerate(row):
            canvas.blit(frame(sheet, col, r, fw, fh), ci * cell_w, ri * cell_h, k)
    canvas.save("hero_animation.png")


def items_and_ground() -> None:
    rarity = {"sword_basic": "b8b8c8", "sword_iron": "6fd08c", "void_splinter": "b8b8c8", "shadow_core": "5aa8ff"}
    k = 5
    atlas = read_png(ROOT / "tiles" / "grass.png")
    width = 8 * 16 * 3 + 20
    canvas = Canvas(width, 16 * k + 34 + 5 * 16 * 3 + 20, hexc("1b1a2e"))
    for i, name in enumerate(rarity):
        x = 10 + i * (16 * k + 30)
        col = hexc(rarity[name])
        canvas.rect(x - 4, 8, 16 * k + 8, 16 * k + 8, col)
        canvas.rect(x - 2, 10, 16 * k + 4, 16 * k + 4, hexc("171329"))
        canvas.blit(read_png(ROOT / "items" / f"{name}.png"), x, 12, k)
    canvas.blit(atlas, 10, 16 * k + 30, 3)
    canvas.save("items_ground.png")


def bushes() -> None:
    k = 3
    c = Canvas(40 * 6 * k + 20, 34 * k * 3 + 16 * k + 34 + 34 * 4 * 2 + 70, hexc("3e7d56"))
    c.blit(read_png(ROOT / "props" / "bush.png"), 10, 8, k)
    berry = read_png(ROOT / "props" / "bush_berry.png")
    c.blit(berry, 10, 8 + 34 * k, k)  # ripe row, then the picked row
    c.blit(read_png(ROOT / "props" / "bush_stripped.png"), 10, 8 + 34 * k * 2 + 4 * k, k)
    x = 10
    for name in ("plant_fiber", "stick", "leaf", "dusk_berry", "stone", "sickle_basic", "pickaxe_basic"):
        c.blit(read_png(ROOT / "items" / f"{name}.png"), x, 20 + 34 * k * 3, k)
        x += 16 * k + 6
    c.blit(read_png(ROOT / "items" / "sickle_basic_held.png"), x + 6, 20 + 34 * k * 3, k)
    c.blit(read_png(ROOT / "items" / "pickaxe_basic_held.png"), x + 6, 60 + 34 * k * 3, k)
    c.blit(read_png(ROOT / "props" / "rock.png"), 10, 70 + 34 * k * 3, 2)
    c.blit(read_png(ROOT / "props" / "pebbles.png"), 10, 70 + 34 * k * 3 + 34 * 4 * 2, 3)
    c.save("bushes.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    palette()
    scale_lineup()
    hero_animation()
    items_and_ground()
    bushes()
    print("docs/img written")
