"""Luminous river jellies: 24x32 frames, 8 pulse frames per row, bell centre (12, 10).
Rows: colour (teal, violet, pink) x size (small, large) -> 6 rows. Drawn with additive blend + unlit.
Run: python3 tools/art_river_jelly.py [preview.png]"""
import math
import sys
from pathlib import Path
from random import Random
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
W, H, COLS = 24, 32, 8
CX, CY = 12, 10


def hexc(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# (body, rim, core) per colour: the same teal/violet/pink glow palette as the world's luminous plants
COLORS = [("2a8c94", "4fd0c0", "d8fff6"), ("6a4bb8", "a98af0", "f0e6ff"), ("b8609c", "e8a9d0", "fff0f8")]
SIZES = [(5.0, 4.0, 9), (7.0, 5.0, 13)]  # half width, bell height, tentacle length


def jelly(color: int, size: int, frame: int) -> Image.Image:
    body, rim, core = (hexc(c) for c in COLORS[color])
    bw, bh, length = SIZES[size]
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    s = math.sin(frame / COLS * 2 * math.pi)
    w = bw * (1.0 - 0.22 * s)       # the bell squeezes in on the push ...
    h = bh * (1.0 + 0.25 * s)       # ... and gets taller
    top = CY - int(h)

    def put(x: int, y: int, c: tuple, a: int) -> None:
        if 0 <= x < W and 0 <= y < H:
            old = im.getpixel((x, y))
            if a >= old[3]:
                im.putpixel((x, y), c + (a,))

    # soft halo round the bell: the jelly lights the water about it
    for y in range(top - 3, CY + 5):
        for x in range(CX - int(w) - 3, CX + int(w) + 4):
            r = math.hypot((x - CX) / (w + 3.0), (y - (CY - h / 2)) / (h + 4.5))
            if r < 1.0:
                put(x, y, body, int(45 * (1.0 - r)))
    # tentacles trail behind the pulse, fading out
    rng = Random(900 + color * 13 + size)
    strands = 4 + size * 2
    for i in range(strands):
        x0 = CX + (i - (strands - 1) / 2) * (2 * w * 0.8 / (strands - 1))
        amp = rng.uniform(0.8, 1.8)
        ph = rng.uniform(0, 6.28)
        ln = int(length * rng.uniform(0.7, 1.1))
        for j in range(ln):
            x = x0 + amp * math.sin(ph - frame / COLS * 6.28 + j * 0.55) * (j / ln)
            put(round(x), CY + 1 + j, rim if j % 3 else body, int(190 * (1 - j / ln) ** 1.3) + 25)
    # bell: translucent dome, bright rim, glowing core
    for y in range(top, CY + 1):
        t = (CY - y) / max(h, 1)
        hw = w * math.sqrt(max(0.0, 1.0 - t * t)) if t < 1 else 0
        for x in range(int(CX - hw), int(CX + hw) + 1):
            edge = abs(x - CX) >= hw - 0.8 or y == top
            put(x, y, rim if edge else body, 235 if edge else 150)
    for x in range(int(CX - w), int(CX + w) + 1):  # frilly skirt
        put(x, CY + 1, rim, 200 if x % 2 else 120)
    for dx in (-1, 0, 1):
        put(CX + dx, CY - 2, core, 255 if dx == 0 else 200)
    put(CX, CY - 3, core, 230)
    for k, dx in enumerate((-2, 2)):  # little speckles in the dome
        put(CX + dx, CY - 1 - k, core, 150)
    return im


def build() -> Image.Image:
    sheet = Image.new('RGBA', (W * COLS, H * 6), (0, 0, 0, 0))
    for row in range(6):
        for f in range(COLS):
            sheet.paste(jelly(row // 2, row % 2, f), (f * W, row * H))
    return sheet


if __name__ == '__main__':
    sheet = build()
    sheet.save(ROOT / 'assets/water/river_jelly.png')
    if len(sys.argv) > 1:
        bg = Image.new('RGBA', sheet.size, (12, 28, 40, 255))
        bg.alpha_composite(sheet)
        bg.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(sys.argv[1])
    print('river_jelly:', sheet.size)
