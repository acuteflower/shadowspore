#!/usr/bin/env python3
"""Draws the Glimmkappe, the mushroom you pick with E (stdlib only):
  assets/props/mushrooms.png        6 clusters of 1..5 mushrooms, 28x22 frames, feet at (14, 19)
  assets/props/mushrooms_glow.png   the same layout, only the emissive parts (cap freckles, gills, spores)
  assets/items/glow_cap.png         icon 16x16
Harmonized with Shadowspore's structured cel + Bayer shading, cool indigo-violet deep shadows, cool teal right rim,
mossy foot grounding, and adaptive violet-slate 1px outlines (never harsh pure black)."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, SHADOW, blank, check_icon, clamp  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

FW, FH = 28, 22
FEET_X, FEET_Y = 14, 19
CAP = [hexc(c) for c in ("1c1046", "322082", "5036b2", "7450dc", "9e82fa", "d4c6ff")]
CAP_AMETHYST = [hexc(c) for c in ("221048", "3e1e82", "6234b2", "8a50dc", "b484fa", "e0c8ff")]
STEM = [hexc(c) for c in ("423a72", "6c62a2", "a298d0", "d6d0f2")]
GILL = [hexc(c) for c in ("140c30", "281a58", "483886")]
MOSS = [hexc(c) for c in ("245448", "347454", "4e9460", "76b870")]  # exported for art_manhole & bake_ground
RIM = [hexc("22707e"), hexc("4cc0c4")]
TEAL_L = hexc("78f4e6")
VIO_L = hexc("d9c8ff")
INK_CAP = hexc("1b1636")
INK_MOSS = hexc("122327")
INK_LOW = hexc("16142c")

# (x, foot y, cap half width, cap height, stem height, lean, amethyst_tint) back to front
# Note: index 3 remains the grand 5-cap centerpiece used at the heart of fairy rings!
CLUSTERS = [
    # v0: Solitary classic Glimmkappe
    [(14, 19, 5.0, 4.0, 7, 0.0, False)],
    # v1: Leaning big + small pair
    [(11, 18, 5.0, 4.0, 7, -1.0, False), (19, 20, 3.2, 2.7, 4, 1.1, True)],
    # v2: Woodland trio
    [(13, 18, 4.6, 3.7, 6, 0.4, False), (7, 20, 3.1, 2.6, 4, -1.0, True), (20, 20, 2.6, 2.2, 3, 1.0, False)],
    # v3: Lush 5-cap fairy-ring centerpiece
    [(14, 17, 5.0, 4.0, 8, 0.0, False), (7, 19, 4.0, 3.2, 5, -1.4, True), (21, 19, 4.0, 3.2, 5, 1.4, False),
     (11, 20, 3.0, 2.5, 3, -0.5, False), (18, 20, 2.5, 2.2, 3, 0.9, True)],
    # v4: Tall twin lantern-bells + tiny button pin
    [(11, 19, 4.2, 4.6, 8, -1.2, True), (18, 19, 3.8, 4.2, 7, 1.3, False), (14, 20, 2.2, 2.0, 2, 0.0, False)],
    # v5: Cascading 4-cap mossy shelf cluster
    [(9, 18, 4.6, 3.8, 7, -1.1, False), (16, 18, 4.2, 3.5, 6, 0.6, True),
     (21, 20, 3.2, 2.7, 4, 1.2, False), (12, 20, 2.8, 2.3, 3, -0.4, True)],
]


class Glow:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = blank(w, h)
        self.items = []

    def emit(self, px, x, y, dim, bright, halo=1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim is not None:
                px[y][x] = dim
            self.px[y][x] = (*bright[:3], 255)
            self.items.append((x, y, bright, halo))

    def done(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    xx, yy = x + dx, y + dy
                    if 0 < d <= radius + 0.5 and 0 <= xx < self.w and 0 <= yy < self.h and self.px[yy][xx][3] == 0:
                        self.px[yy][xx] = (*color[:3], 108 if d < 1.6 else 50)
        return self.px


def mushroom(px, glow, cx, foot, rx, ry, stem_h, lean, seed, amethyst=False):
    W, H = len(px[0]), len(px)
    pal = CAP_AMETHYST if amethyst else CAP
    cap_y = foot - stem_h
    for y in range(int(cap_y), int(foot) + 1):
        t = (foot - y) / max(stem_h, 1.0)
        xc = cx + lean * t * t
        hw = 1.05 + 0.38 * rx / 5.0 + 0.45 * max(0.0, 0.28 - t) * 2.0 - 0.22 * t
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = int(round(xc + dx))
            lit = 0.55 - 0.48 * dx / max(hw, 0.8) - (0.35 if t > 0.80 else 0.0)
            v = lit * 3.2 + (BAYER[y % 4][max(0, x) % 4] / 16.0 - 0.5) * 0.45
            if 1 <= x < W - 1 and 1 <= y < H - 1:
                px[y][x] = STEM[int(clamp(v, 0, 3))]
    for y in range(int(cap_y - ry) - 1, int(cap_y) + 3):
        for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
            dx = (x + 0.5 - (cx + lean * 0.85)) / rx
            dy = (y + 0.5 - cap_y) / (ry if y < cap_y else ry * 0.32)
            d = dx * dx + dy * dy
            if d >= 1.0 or not (1 <= x < W - 1 and 1 <= y < H - 1):
                continue
            z = math.sqrt(1.0 - d)
            light = (-dx * 0.58 - dy * 0.68 + z * 0.55 + 0.92) / 2.0 - 0.12
            v = light * 5.4 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.65
            px[y][x] = pal[int(clamp(v, 0, 5))]
            if y >= cap_y + 1 and dy > 0.24:
                px[y][x] = GILL[2] if (x + int(seed)) % 2 == 0 else GILL[0]
    for y in range(int(cap_y - ry) - 1, int(cap_y) + 3):
        for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
            if not (1 <= x < W - 1 and 1 <= y < H - 1) or px[y][x][3] == 0 or px[y][x] not in pal:
                continue
            if px[y - 1][x][3] == 0 and x <= cx + lean:
                px[y][x] = pal[min(pal.index(px[y][x]) + 1, 5)]
            elif px[y][x + 1][3] == 0 and noise(x, y, seed + 5) > 95:
                px[y][x] = RIM[int(noise(x, y, seed + 6) > 155)]
    rng = random.Random(seed)
    for _ in range(1 + int(rx / 2.8)):
        for _t in range(20):
            x = int(cx + lean * 0.7 + rng.uniform(-rx * 0.65, rx * 0.65))
            y = int(cap_y - rng.uniform(0.6, ry * 0.78))
            if 1 <= x < W - 1 and 1 <= y < H - 1 and px[y][x] in pal[1:5]:
                glow.emit(px, x, y, hexc("2a9aa0"), TEAL_L, 1)
                break
    gx = int(cx + rx * 0.3)
    for x in range(int(cx - rx * 0.6), int(cx + rx * 0.7)):
        y = int(cap_y + 1)
        if 1 <= x < W - 1 and 1 <= y < H - 1 and px[y][x] in GILL and (x + gx) % 4 == 0:
            glow.emit(px, x, y, hexc("2a9aa0"), TEAL_L, 0)
    if rx >= 4.0:
        sx = int(clamp(cx + rng.randrange(-2, 3), 2, W - 3))
        sy = max(2, int(cap_y - ry) - 2)
        glow.emit(px, sx, sy, None, VIO_L, 0)


def moss_tufts(px, rng, left, right, foot):
    for _ in range(max(2, int((right - left) / 2.2))):
        x = int(clamp(rng.uniform(left, right), 2, FW - 3))
        for k in range(rng.randrange(1, 3)):
            y = foot - k
            if 1 <= x < FW - 1 and 1 <= y < FH - 1 and px[y][x][3] == 0:
                px[y][x] = MOSS[min(1 + k, 3)] if rng.random() < 0.8 else MOSS[0]


def outline(px, w, h):
    src = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if src[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < w and 0 <= b < h and src[b][a][3] == 255]
            if hit:
                if y >= FEET_Y or any(b > y and y >= FEET_Y - 1 for _a, b in hit):
                    px[y][x] = INK_LOW
                elif any(src[b][a] in MOSS for a, b in hit):
                    px[y][x] = INK_MOSS
                else:
                    px[y][x] = INK_CAP


def cluster(index, seed):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow(FW, FH)
    shapes = CLUSTERS[index]
    left = max(2.0, min(s[0] - s[2] for s in shapes))
    right = min(FW - 3.0, max(s[0] + s[2] for s in shapes))
    for i, (cx, foot, rx, ry, stem_h, lean, amethyst) in enumerate(shapes):
        mushroom(px, glow, cx, foot, rx, ry, stem_h, lean, seed + i * 7, amethyst=amethyst)
    moss_tufts(px, rng, left, right, FEET_Y + 1)
    base = [[CLEAR] * FW for _ in range(FH)]
    mid, half = (left + right) / 2.0, min(12.5, (right - left) / 2.0 + 2.8)
    for y in range(FH):
        for x in range(FW):
            d = ((x + 0.5 - mid) / half) ** 2 + ((y + 0.5 - (FEET_Y + 1.6)) / 2.2) ** 2
            if d < 1.0:
                base[y][x] = (*SHADOW, 115 if d < 0.5 else 65)
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base, FW, FH)
    return base, glow.done()


def icon():
    px, glow = blank(16, 16), Glow(16, 16)
    mushroom(px, glow, 8, 14, 5.4, 4.3, 6, 0.7, 5)
    for y, x in ((14, 6), (14, 7), (14, 9), (14, 10), (13, 6), (13, 10)):
        px[y][x] = MOSS[1 + (x % 2)]
    check_icon("glow_cap", px)
    return outline_pass(px, hexc("1b1a2e"))


def sheet(frames):
    out = [[CLEAR] * (FW * len(frames)) for _ in range(FH)]
    for i, f in enumerate(frames):
        for y in range(FH):
            out[y][i * FW:(i + 1) * FW] = f[y]
    return out


def main():
    props, items = ROOT / "props", ROOT / "items"
    frames = [cluster(i, 30 + i * 11) for i in range(len(CLUSTERS))]
    for i, (b, g) in enumerate(frames):
        for layer_name, layer in (("mushrooms", b), ("mushrooms_glow", g)):
            pts = [(x, y) for y, row in enumerate(layer) for x, c in enumerate(row) if c[3]]
            assert not pts or (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2), (
                f"{layer_name} frame {i} touches border!"
            )
    write_png(props / "mushrooms.png", FW * len(frames), FH, sheet([f[0] for f in frames]))
    write_png(props / "mushrooms_glow.png", FW * len(frames), FH, sheet([f[1] for f in frames]))
    write_png(items / "glow_cap.png", 16, 16, icon())
    print("mushrooms (6 variants), glow and glow_cap icon written")


if __name__ == "__main__":
    main()
