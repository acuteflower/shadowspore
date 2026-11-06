#!/usr/bin/env python3
"""Draws the Glimmkappe, the mushroom you pick with E (stdlib only):
  assets/props/mushrooms.png        4 clusters of 1, 2, 3 and 5 mushrooms, 28x22 frames, feet at (14, 19)
  assets/props/mushrooms_glow.png   the same layout, only the emissive parts (the cap's glowing freckles, the gills, a few
                                    spores; the game draws it unshaded, bright at night)
  assets/items/glow_cap.png         icon 16x16
Violet caps (like the void-touched needles and the berries) with teal freckles that glow, pale lilac stems, dark gills
that give off a little light, lit from the top left, a cool rim light from the right, moss at the foot."""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, SHADOW, bezier, blank, check_icon, clamp, stroke  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

FW, FH = 28, 22
FEET_X, FEET_Y = 14, 19
CAP = [hexc(c) for c in ("1e0f4a", "34208a", "5236b8", "7650e0", "a082ff", "d4c4ff")]  # violet shade .. lit
STEM = [hexc(c) for c in ("4a3f7a", "7468a8", "a99ed4", "d8d0f4")]
GILL = [hexc(c) for c in ("140a30", "2a1a5a", "4a3a88")]
MOSS = [hexc(c) for c in ("2f624e", "3e7d56", "55985f", "7cb96d")]
RIM = [hexc("22707e"), hexc("4cc0c4")]  # cool light from the right
TEAL, TEAL_L = hexc("3cc0c6"), hexc("78f4e6")
VIO_L = hexc("d9c8ff")
INK, INK_LOW = hexc("12182a"), hexc("0c1020")

# (x, foot y, cap half width, cap height, stem height, lean) of every mushroom, back to front
CLUSTERS = [
    [(14, 19, 5, 4, 7, 0.0)],
    [(11, 18, 5, 4, 7, -1.0), (19, 20, 3, 2.6, 4, 1.0)],
    [(13, 18, 4.6, 3.6, 6, 0.5), (7, 20, 3, 2.6, 4, -1.0), (20, 20, 2.4, 2.2, 3, 1.0)],
    [(14, 17, 5, 4, 8, 0.0), (7, 19, 4, 3.2, 5, -1.5), (21, 19, 4, 3.2, 5, 1.5), (11, 21, 3, 2.5, 3, -0.5), (18, 21, 2.4, 2.2, 3, 1.0)],
]


class Glow:
    """Emissive pixels: a dim colour goes into the lit art, the bright one (with a soft halo) into the glow layer."""

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
                        self.px[yy][xx] = (*color[:3], 110 if d < 1.6 else 52)
        return self.px


def mushroom(px, glow, cx, foot, rx, ry, stem_h, lean, seed):
    """One mushroom: a curved pale stem, a dark gill rim, a domed cap lit from the top left with glowing freckles."""
    W, H = len(px[0]), len(px)
    cap_y = foot - stem_h  # where the cap sits on the stem
    for y in range(int(cap_y), int(foot) + 1):  # stem
        t = (foot - y) / max(stem_h, 1.0)
        xc = cx + lean * t * t
        hw = 1.05 + 0.4 * rx / 5.0 + 0.5 * max(0.0, 0.25 - t) * 4.0 * 0.5 - 0.25 * t
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = int(round(xc + dx))
            lit = 0.5 - 0.5 * dx / max(hw, 0.8) - (0.35 if t > 0.82 else 0.0)  # shaded right under the cap
            v = lit * 3.2 + (noise(x, y, seed) / 255.0 - 0.5) * 0.5
            if 0 <= x < W and 0 <= y < H:
                px[y][x] = STEM[int(clamp(v, 0, 3))]
    for y in range(int(cap_y - ry) - 1, int(cap_y) + 3):  # cap: a dome on top, a flatter underside
        for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
            dx = (x + 0.5 - (cx + lean * 0.9)) / rx
            dy = (y + 0.5 - cap_y) / (ry if y < cap_y else ry * 0.3)
            d = dx * dx + dy * dy
            if d >= 1.0 or not (0 <= x < W and 0 <= y < H):
                continue
            z = math.sqrt(1.0 - d)
            light = (-dx * 0.6 - dy * 0.7 + z * 0.55 + 1.0) / 2.0
            light += (noise(x, y, seed + 1) / 255.0 - 0.5) * 0.18 - 0.17
            v = light * 5.4 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.7
            px[y][x] = CAP[int(clamp(v, 0, 5))]
            if y >= cap_y + 1 and dy > 0.25:  # the dark gills under the rim, lighter ribs
                px[y][x] = GILL[2] if (x + int(seed)) % 2 == 0 else GILL[0]
    for y in range(int(cap_y - ry) - 1, int(cap_y) + 3):  # lit contour on top, cool light on the right
        for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
            if not (1 <= x < W - 1 and 1 <= y < H - 1) or px[y][x][3] == 0 or px[y][x] not in CAP:
                continue
            if px[y - 1][x][3] == 0:
                px[y][x] = CAP[min(CAP.index(px[y][x]) + 2, 5)]
            elif px[y][x + 1][3] == 0 and noise(x, y, seed + 5) > 80:
                px[y][x] = RIM[int(noise(x, y, seed + 6) > 150)]
    rng = random.Random(seed)
    for _ in range(1 + int(rx / 3)):  # glowing freckles on the cap
        for _t in range(20):
            x, y = int(cx + rng.uniform(-rx * 0.7, rx * 0.7)), int(cap_y - rng.uniform(0.5, ry * 0.8))
            if 0 <= x < W and 0 <= y < H and px[y][x] in CAP[1:5]:
                glow.emit(px, x, y, hexc("2a9aa0"), TEAL_L, 1)
                break
    gx = int(cx + rx * 0.3)  # the gills glow faintly along the rim
    for x in range(int(cx - rx * 0.6), int(cx + rx * 0.7)):
        y = int(cap_y + 1)
        if 0 <= x < W and px[y][x] in GILL and (x + gx) % 4 == 0:
            glow.emit(px, x, y, hexc("2a9aa0"), TEAL_L, 0)
    if rx >= 4:  # a spore or two drifts up
        glow.emit(px, int(cx + rng.randrange(-2, 3)), int(cap_y - ry) - 2, None, VIO_L, 0)


def moss_tufts(px, rng, left, right, foot):
    for _ in range(int((right - left) / 2.5)):
        x = int(rng.uniform(left, right))
        for k in range(rng.randrange(1, 4)):
            y = foot - k
            if 0 <= x < FW and 0 <= y < FH and px[y][x][3] == 0:
                px[y][x] = MOSS[min(1 + k, 3)] if rng.random() < 0.8 else MOSS[0]


def outline(px, w, h):
    src = [row[:] for row in px]
    for y in range(h):
        for x in range(w):
            if src[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < w and 0 <= b < h and src[b][a][3] == 255]
            if hit:
                px[y][x] = INK_LOW if any(b > y for a, b in hit) else INK


def cluster(index, seed):
    """(lit pixels, glow pixels) of cluster `index`."""
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow(FW, FH)
    shapes = CLUSTERS[index]
    left, right = min(s[0] - s[2] for s in shapes), max(s[0] + s[2] for s in shapes)
    for i, (cx, foot, rx, ry, stem_h, lean) in enumerate(shapes):
        mushroom(px, glow, cx, foot, rx, ry, stem_h, lean, seed + i * 7)
    moss_tufts(px, rng, left - 1, right + 1, FEET_Y + 2)
    base = [[CLEAR] * FW for _ in range(FH)]
    mid, half = (left + right) / 2.0, (right - left) / 2.0 + 3
    for y in range(FH):  # soft ground shadow
        for x in range(FW):
            d = ((x + 0.5 - mid) / half) ** 2 + ((y + 0.5 - (FEET_Y + 2.2)) / 2.4) ** 2
            if d < 1.0:
                base[y][x] = (*SHADOW, 120 if d < 0.5 else 70)
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    outline(base, FW, FH)
    return base, glow.done()


def icon():
    px, glow = blank(16, 16), Glow(16, 16)
    mushroom(px, glow, 8, 14, 5.5, 4.4, 6, 0.8, 5)
    for y, x in ((14, 6), (14, 7), (14, 9), (14, 10), (13, 6), (13, 10)):  # a bit of moss around the foot
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
    write_png(props / "mushrooms.png", FW * len(frames), FH, sheet([f[0] for f in frames]))
    write_png(props / "mushrooms_glow.png", FW * len(frames), FH, sheet([f[1] for f in frames]))
    write_png(items / "glow_cap.png", 16, 16, icon())
    print("mushrooms, their glow and the glow cap icon written")


if __name__ == "__main__":
    main()
