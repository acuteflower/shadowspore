"""The meadow: a 16x16 grass atlas, the TileSet that uses it and the tile table the level reads.

Writes assets/tiles/grass.png (8 x 5 tiles), src/world/tileset.tres and data/grass_tiles.json
(category -> atlas coords). Also assets/tiles/grass_glow.png + src/world/glow_tileset.tres: the same
glowing tiles (blooms, mushrooms, glyph) with ONLY their glowing pixels; the level draws them on an
unshaded layer above the ground so the plants shine at night instead of taking on the night tint. The ground shader (assets/shaders/ground_tone.gdshader) re-lights the
six greens below over large areas, so keep RAMP in sync with it.
"""
import json
import pathlib

from gen_art import CLEAR, ROOT, hexc, noise, write_png

COLS, ROWS = 8, 5
RAMP = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
D, M, B, L, H, HH = RAMP  # deep, shade, base, light, highlight, bright
WHITE, CREAM, GOLD, GOLD_D = hexc("f7f1de"), hexc("efe2b8"), hexc("f0c862"), hexc("c8923a")
VIO, VIO_L, VIO_D = hexc("a98af0"), hexc("d0bcff"), hexc("6a4bb8")
PINK = hexc("e8a9d0")
TEAL, TEAL_L, TEAL_D = hexc("4fd0c0"), hexc("a4fff0"), hexc("2a8c94")
CAP, CAP_L, CAP_D = hexc("8a58d6"), hexc("b996ff"), hexc("55308f")
STONE = [hexc("4c4b68"), hexc("6e6d8e"), hexc("9a98b8"), hexc("c4c2da")]


class Tile:
    def __init__(self, seed: int) -> None:
        self.px = [[B] * 16 for _ in range(16)]
        self.seed = seed
        for y in range(16):  # short painted dashes, not per-pixel noise
            for x in range(16):
                r = noise(x, y, seed) / 255
                if r < 0.05:
                    self.put(x, y, M)
                    if noise(x, y, seed + 3) < 120:
                        self.put(x + 1, y, M)
                elif r > 0.945:
                    self.put(x, y, L)
                    if noise(x, y, seed + 5) < 120:
                        self.put(x + 1, y, L)

    def put(self, x: int, y: int, c) -> None:
        if 0 <= x < 16 and 0 <= y < 16:
            self.px[y][x] = c

    def blade(self, x: int, y: int, h: int = 3, lean: int = 0) -> None:
        self.put(x, y, D)
        for i in range(1, h):
            c = L if i < h - 1 else H
            self.put(x + (lean if i >= 2 else 0), y - i, c)
        if h >= 4:
            self.put(x + lean, y - h + 1, HH if lean else H)

    def tuft(self, x: int, y: int, h: int = 3) -> None:
        for dx, lean in ((-2, -1), (0, 0), (2, 1)):
            self.blade(x + dx, y, h - (1 if dx else 0) + (1 if dx == 0 else 0), lean)
        for dx in range(-2, 3):
            self.put(x + dx, y + 1, M)

    def clump(self, x: int, y: int) -> None:
        for dx in range(-4, 5):
            self.put(x + dx, y + 1, M)
        for i, (dx, h, lean) in enumerate(((-4, 3, -1), (-3, 4, -1), (-1, 5, -1), (0, 4, 0), (1, 5, 1), (3, 4, 1), (4, 3, 1))):
            self.blade(x + dx, y, h, lean)

    def stem(self, x: int, y: int, h: int = 3) -> None:
        for i in range(h):
            self.put(x, y - i, M if i == 0 else L)

    def moon_flower(self, x: int, y: int, h: int = 4, petal=WHITE, heart=GOLD) -> None:
        self.stem(x, y, h)
        top = y - h
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            self.put(x + dx, top + dy, petal)
        self.put(x, top, heart)
        self.put(x - 1, top - 1, petal if petal != WHITE else CREAM)

    def star_flower(self, x: int, y: int, h: int = 3) -> None:
        self.stem(x, y, h)
        top = y - h
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1), (-1, -1), (1, 1)):
            self.put(x + dx, top + dy, VIO)
        self.put(x, top, VIO_L)
        self.put(x + 1, top - 1, VIO_D)

    def glow_bloom(self, x: int, y: int) -> None:
        for dx in range(-3, 4):  # soft glow on the grass around it
            for dy in range(-6, 1):
                if (dx * dx) / 9 + ((dy + 3) ** 2) / 12 <= 1 and noise(x + dx, y + dy, self.seed) < 150:
                    self.put(x + dx, y + dy, H)
        self.stem(x, y, 4)
        top = y - 4
        for dx, dy in ((0, -2), (-1, -1), (1, -1), (-2, 0), (2, 0), (0, 0)):
            self.put(x + dx, top + dy, TEAL)
        self.put(x, top - 1, TEAL_L)
        self.put(x - 1, top - 1, TEAL_L)
        for dx, dy in ((-4, -3), (3, -5), (4, -1), (-3, 1)):  # drifting motes
            self.put(x + dx, top + dy, TEAL_L)

    def mushroom(self, x: int, y: int, cap=(CAP, CAP_L, CAP_D), glow: bool = False, big: bool = True) -> None:
        c, cl, cd = cap
        self.put(x, y, M)
        self.put(x, y - 1, CREAM)
        self.put(x, y - 2, CREAM)
        w = 3 if big else 2
        for dx in range(-w, w + 1):
            self.put(x + dx, y - 3, cd if abs(dx) == w else c)
        for dx in range(-w + 1, w):
            self.put(x + dx, y - 4, cl if dx < 1 else c)
        self.put(x - 1, y - 4, WHITE if not glow else TEAL_L)
        self.put(x + 1, y - 3, WHITE if not glow else TEAL_L)
        for dx in (-w - 1, w + 1):
            self.put(x + dx, y, M)
        self.put(x + 2, y, L)

    def stone(self, x: int, y: int, size: int = 2) -> None:
        for dx in range(-size - 1, size + 2):
            self.put(x + dx, y + 1, M)
        rows = [(-size, size), (-size - 1, size + 1), (-size - 1, size + 1)][: 2 + (size > 1)]
        for i, (a, b) in enumerate(rows):
            for dx in range(a, b + 1):
                tone = 3 if (i == 0 and dx < 1) else (2 if i < len(rows) - 1 else 1)
                self.put(x + dx, y - len(rows) + 1 + i, STONE[tone] if dx < size else STONE[max(tone - 1, 0)])
        self.put(x - size, y - len(rows) + 1, STONE[3])
        self.put(x + 1, y - len(rows), H)  # moss on top
        self.put(x + 2, y - len(rows), L)
        self.put(x - 1, y - len(rows) + 1, L)

    def fern(self, x: int, y: int) -> None:
        for dx in range(-3, 4):
            self.put(x + dx, y + 1, M)
        fronds = (((0, 0), (-1, -1), (-2, -2), (-3, -2), (-4, -1)), ((0, 0), (0, -1), (0, -2), (-1, -3), (-1, -4)),
                  ((0, 0), (1, -1), (2, -2), (3, -2), (4, -1)), ((0, 0), (0, -1), (1, -2), (1, -3)))
        for k, pts in enumerate(fronds):
            for i, (dx, dy) in enumerate(pts):
                self.put(x + dx, y + dy, H if i == len(pts) - 1 else (L if i else D))
                if i >= 2:
                    self.put(x + dx, y + dy + 1, M)

    def clover(self, x: int, y: int) -> None:
        for ox, oy in ((0, 0), (3, 1), (1, 3)):
            for dx in (0, 1):
                for dy in (0, 1):
                    self.put(x + ox + dx, y + oy + dy, L)
            self.put(x + ox, y + oy, H)

    def petals(self, spots) -> None:
        for x, y, c in spots:
            self.put(x, y, c)
            if noise(x, y, self.seed) < 110:
                self.put(x + 1, y, c)

    def glyph(self, x: int, y: int) -> None:
        """A faint ring of glowing dots, as if something old sleeps under the meadow."""
        for i in range(8):
            a = i * 0.7854
            px = x + round(5.5 * __import__("math").cos(a))
            py = y + round(3.2 * __import__("math").sin(a))
            self.put(px, py, TEAL_D if i % 2 else TEAL)
        self.put(x, y, TEAL_L)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            self.put(x + dx, y + dy, TEAL_D)


def build() -> tuple[list[Tile], dict[str, list[int]]]:
    tiles: list[Tile] = []
    cats: dict[str, list[int]] = {}

    def add(cat: str, t: Tile) -> None:
        cats.setdefault(cat, []).append(len(tiles))
        tiles.append(t)

    for i in range(8):
        add("plain", Tile(10 + i))
    for i, (x, y) in enumerate(((7, 11), (4, 6), (11, 12), (9, 5))):
        t = Tile(30 + i)
        t.tuft(x, y, 3)
        if i % 2:
            t.blade(x + 5 if x < 9 else x - 5, y - 3, 3, 1)
        add("tuft", t)
    for i, (x, y) in enumerate(((8, 11), (6, 9), (10, 12))):
        t = Tile(40 + i)
        t.clump(x, y)
        add("clump", t)
    flowers = [
        lambda t: t.moon_flower(5, 12, 4) or t.moon_flower(10, 9, 3),
        lambda t: t.moon_flower(8, 12, 5, WHITE, GOLD) or t.tuft(3, 6, 3),
        lambda t: t.star_flower(11, 11, 3) or t.star_flower(5, 7, 4) or t.moon_flower(7, 13, 3, WHITE, GOLD),
        lambda t: t.star_flower(7, 12, 4) or t.tuft(12, 6, 3),
        lambda t: t.moon_flower(4, 7, 3, hexc("f6d9e8"), PINK) or t.moon_flower(10, 12, 4, hexc("f6d9e8"), PINK) or t.moon_flower(13, 6, 3, WHITE, GOLD),
        lambda t: t.moon_flower(7, 12, 3, GOLD, GOLD_D) or t.moon_flower(11, 7, 4, GOLD, GOLD_D),
    ]
    for i, draw in enumerate(flowers):
        t = Tile(50 + i)
        draw(t)
        add("flower", t)
    for i, (x, y) in enumerate(((6, 11), (10, 12), (8, 10))):
        t = Tile(60 + i)
        t.glow_bloom(x, y)
        if i == 1:
            t.tuft(3, 6, 3)
        add("bloom", t)
    shrooms = [
        lambda t: t.mushroom(7, 12) or t.mushroom(11, 13, big=False),
        lambda t: t.mushroom(5, 11, big=False) or t.mushroom(10, 12),
        lambda t: t.mushroom(8, 12, cap=(TEAL, TEAL_L, TEAL_D), glow=True, big=False) or t.tuft(12, 6, 3),
    ]
    for i, draw in enumerate(shrooms):
        t = Tile(70 + i)
        draw(t)
        add("mushroom", t)
    for i, (x, y, s) in enumerate(((8, 11, 2), (5, 10, 1), (10, 12, 2))):
        t = Tile(80 + i)
        t.stone(x, y, s)
        if i == 1:
            t.stone(12, 6, 1)
        add("stone", t)
    for i, (x, y) in enumerate(((8, 12), (7, 11))):
        t = Tile(90 + i)
        t.fern(x, y)
        add("fern", t)
    for i in range(2):
        t = Tile(100 + i)
        t.petals([(3, 5, VIO_L), (9, 9, WHITE), (12, 3, PINK), (6, 13, VIO_L)] if i == 0 else [(5, 4, WHITE), (11, 8, VIO_L), (2, 11, PINK), (13, 13, WHITE)])
        add("petal", t)
    for i, (x, y) in enumerate(((5, 5), (9, 8))):
        t = Tile(110 + i)
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
    for i in range(len(tiles), COLS * ROWS):  # pad unused slots with plain grass so none is ever empty
        ox, oy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                atlas[oy + y][ox + x] = B
    write_png(ROOT / "tiles" / "grass.png", COLS * 16, ROWS * 16, atlas)

    lines = ['[gd_resource type="TileSet" format=3]', '',
             '[ext_resource type="Texture2D" path="res://assets/tiles/grass.png" id="1_grass"]', '',
             '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_grass"]',
             'texture = ExtResource("1_grass")', 'texture_region_size = Vector2i(16, 16)']
    for i in range(len(tiles)):
        lines += [f"{i % COLS}:{i // COLS}/0 = 0", f'{i % COLS}:{i // COLS}/0/custom_data_0 = "grass"']
    lines += ['', '[resource]', 'tile_size = Vector2i(16, 16)', 'custom_data_layer_0/name = "surface"',
              'custom_data_layer_0/type = 4', 'sources/0 = SubResource("TileSetAtlasSource_grass")', '']
    (ROOT.parent / "src" / "world" / "tileset.tres").write_text("\n".join(lines))

    emissive = {TEAL, TEAL_L, TEAL_D, CAP, CAP_L}
    glow_ids = [i for cat in ("bloom", "mushroom", "glyph") for i in cats.get(cat, [])]
    glow = [[CLEAR] * (COLS * 16) for _ in range(ROWS * 16)]
    for i in glow_ids:
        ox, oy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                if tiles[i].px[y][x] in emissive:
                    glow[oy + y][ox + x] = tiles[i].px[y][x]
    write_png(ROOT / "tiles" / "grass_glow.png", COLS * 16, ROWS * 16, glow)
    glow_lines = ['[gd_resource type="TileSet" format=3]', '',
                  '[ext_resource type="Texture2D" path="res://assets/tiles/grass_glow.png" id="1_glow"]', '',
                  '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_glow"]',
                  'texture = ExtResource("1_glow")', 'texture_region_size = Vector2i(16, 16)']
    for i in glow_ids:
        glow_lines.append(f"{i % COLS}:{i // COLS}/0 = 0")
    glow_lines += ['', '[resource]', 'tile_size = Vector2i(16, 16)', 'sources/0 = SubResource("TileSetAtlasSource_glow")', '']
    (ROOT.parent / "src" / "world" / "glow_tileset.tres").write_text("\n".join(glow_lines))
    table = {cat: [[i % COLS, i // COLS] for i in ids] for cat, ids in cats.items()}
    (ROOT.parent / "data" / "grass_tiles.json").write_text(json.dumps(table, indent=1) + "\n")


if __name__ == "__main__":
    write_all()
    print("ok")
