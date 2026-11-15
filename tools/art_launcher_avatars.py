"""Profile pictures for the launcher: Ellie's bust from her in-game portrait on two backgrounds.

Source: assets/ui/sources/ellie_ingame_portrait_1x.png (121 x 181, the new 1x portrait).
Writes launcher/src/art/avatar_<id>.png (64 x 64, 1 px per art pixel) and, with an argument,
a 6x contact sheet:  py -3 tools/art_launcher_avatars.py [preview.png]

  lichtung  - the glade at golden hour: warm sky, green hills, drifting pollen.
  leere     - the void at night: deep violet, stars, a magenta halo behind her and a cold rim light.
"""
import random
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/ui/sources/ellie_ingame_portrait_1x.png"
OUT = ROOT / "launcher/src/art"
SIZE = 64
CROP = (30, 4, 30 + SIZE, 4 + SIZE)  # her head sits in x 39..84, chin about y 56

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ramp(stops, t):
    """Picks one colour of a ramp: whole steps only, no blending (pixel-art palette)."""
    t = max(0.0, min(0.999, t))
    return stops[int(t * len(stops))]


def dither_ramp(stops, t, x, y):
    t = max(0.0, min(1.0, t)) * (len(stops) - 1)
    i = int(t)
    frac = t - i
    if i >= len(stops) - 1:
        return stops[-1]
    return stops[i + 1] if frac * 16 > BAYER[y % 4][x % 4] + 0.5 else stops[i]


def bust():
    im = Image.open(SRC).convert("RGBA").crop(CROP)
    return im


def lichtung():
    sky = [hexc(c) for c in ("#f6d58a", "#f2c36b", "#e3a36a", "#b97a78", "#7d5a86")]
    hill_far = hexc("#5f8a6e")
    hill_near = hexc("#3f6b55")
    grass = hexc("#2c4f42")
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = dither_ramp(sky, (y - 4) / 44.0, x, y) + (255,)
    # a low sun behind her right shoulder
    sx, sy = 50, 30
    for y in range(SIZE):
        for x in range(SIZE):
            d = ((x - sx) ** 2 + (y - sy) ** 2) ** 0.5
            if d < 7:
                px[x, y] = hexc("#fff1c2") + (255,)
            elif d < 10 and BAYER[y % 4][x % 4] < 9:
                px[x, y] = hexc("#fde3a0") + (255,)
    # two rolling hills
    import math
    for x in range(SIZE):
        far = int(40 + 3 * math.sin(x * 0.13 + 1.0) + 2 * math.sin(x * 0.31))
        near = int(48 + 4 * math.sin(x * 0.09 + 3.0) + 1.5 * math.sin(x * 0.4))
        for y in range(far, SIZE):
            px[x, y] = hill_far + (255,)
        for y in range(near, SIZE):
            px[x, y] = (hill_near if y < near + 6 else grass) + (255,)
        if BAYER[(x * 3) % 4][x % 4] < 5:
            px[x, far] = hexc("#8fb37a") + (255,)
    rng = random.Random(7)
    for _ in range(14):
        x, y = rng.randrange(SIZE), rng.randrange(6, 46)
        px[x, y] = hexc("#fff6d6") + (255,)
    return img


def leere():
    void = [hexc(c) for c in ("#07040d", "#120a24", "#1d1238", "#2a1a4a")]
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = dither_ramp(void, y / 63.0, x, y) + (255,)
    # magenta halo behind her head
    cx, cy = 32, 28
    for y in range(SIZE):
        for x in range(SIZE):
            d = (((x - cx) / 1.0) ** 2 + ((y - cy) / 1.15) ** 2) ** 0.5
            if 21 <= d < 23:
                px[x, y] = hexc("#c04aa8") + (255,)
            elif 23 <= d < 26 and BAYER[y % 4][x % 4] < 6:
                px[x, y] = hexc("#5b2a6e") + (255,)
            elif d < 21 and BAYER[y % 4][x % 4] < 3:
                px[x, y] = hexc("#3a1f5c") + (255,)
    rng = random.Random(11)
    for _ in range(22):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        px[x, y] = (hexc("#c9a6ff") if rng.random() < 0.6 else hexc("#ffffff")) + (255,)
    return img


def cool(b):
    """Moonlit version of the bust: hair and skin lean blue-violet, eyes stay."""
    out = b.copy()
    px = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, bl, a = px[x, y]
            if a == 0:
                continue
            r2 = int(r * 0.86)
            g2 = int(g * 0.86)
            b2 = min(255, int(bl * 0.98 + 10))
            px[x, y] = (r2, g2, b2, a)
    # violet rim light on the left edge of the silhouette
    src = b.load()
    for y in range(SIZE):
        for x in range(1, SIZE):
            if src[x, y][3] > 0 and src[x - 1, y][3] == 0:
                px[x, y] = hexc("#b48cff") + (255,)
    return out


def compose(bg, b):
    bg = bg.copy()
    bg.alpha_composite(b)
    return bg


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    b = bust()
    pics = {"lichtung": compose(lichtung(), b), "leere": compose(leere(), cool(b))}
    for name, im in pics.items():
        im.save(OUT / f"avatar_{name}.png")
        print("wrote", OUT / f"avatar_{name}.png")
    if len(sys.argv) > 1:
        sheet = Image.new("RGBA", (SIZE * 6 * 2 + 12, SIZE * 6), (20, 14, 30, 255))
        for i, im in enumerate(pics.values()):
            sheet.paste(im.resize((SIZE * 6, SIZE * 6), Image.NEAREST), (i * (SIZE * 6 + 12), 0))
        sheet.save(sys.argv[1])
        print("preview", sys.argv[1])


if __name__ == "__main__":
    main()
