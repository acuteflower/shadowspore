#!/usr/bin/env python3
"""Draws the old manhole cover where the story starts (needs numpy):
  assets/props/manhole.png       64x52, centre of the cover at (32, 26): a round cast-iron lid in a collar of old cut stones,
                                 pushed a little aside so a dark crescent of the shaft shows, rust, moss, tufts of grass.
  assets/props/manhole_glow.png  same layout, only the emissive parts (a violet crack, the bloom on the lid, luminous moss,
                                 a cold glimmer deep in the shaft); the game draws it unshaded, bright at night.
Iron is the dark rusty plum of the grate and the tools, stone the blue-violet of the rocks, lit from the top left; the 3/4 view
flattens circles to 78 % of their height."""
import math
import pathlib
import random
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BUSH  # noqa: E402
from art_mushroom import MOSS  # noqa: E402
from art_stone import STONE, TEAL, TEAL_L, VIO, VIO_L  # noqa: E402
from gen_art import ROOT, hexc, noise, write_png  # noqa: E402

W, H = 64, 52
CX, CY = 32, 26
SQ = 0.78
IRON = [hexc(c) for c in ("1a1220", "2e2230", "4a3a40", "6e5654", "94786a", "b89886")]
RUST = [hexc(c) for c in ("2a1822", "55303a", "8a5240", "b8784c")]
VOID_DARK = [hexc(c) for c in ("04020a", "0a0618", "120e26", "1c1a34")]
INK, INK_LOW = hexc("12102a"), hexc("0a0818")
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
LID_R = 21.0
SHIFT = (0.0, 0.0)  # the lid lies over the shaft in its own picture; the game moves it


def clampi(v, lo, hi):
    return max(lo, min(hi, v))


def ell(x, y, cx, cy, rx):
    """Normalised distance from the centre of a flattened circle (1 at the edge)."""
    return math.hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / (rx * SQ))


class Canvas:
    def __init__(self):
        self.img = np.zeros((H, W, 4), dtype=np.uint8)
        self.glow = np.zeros((H, W, 4), dtype=np.uint8)
        self.items = []

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.img[y, x] = c

    def emit(self, x, y, dim, bright, halo=1):
        if not (0 <= x < W and 0 <= y < H):
            return
        if dim is not None:
            self.img[y, x] = dim
        self.glow[y, x] = (*bright[:3], 255)
        self.items.append((x, y, bright, halo))

    def halos(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    xx, yy = x + dx, y + dy
                    if 0 < d <= radius + 0.5 and 0 <= xx < W and 0 <= yy < H and self.glow[yy, xx, 3] == 0:
                        self.glow[yy, xx] = (*color[:3], 110 if d < 1.6 else 52)


def tuft(cv, x, y, h, rng):
    for k in range(rng.randrange(3, 5)):
        lean = rng.choice((-2, -1, 0, 1, 2))
        for j in range(h - rng.randrange(0, 2)):
            cv.put(x + int(lean * j / h * 2) + k - 1, y - j, BUSH[clampi(2 + j * 3 // max(h, 1), 1, 5)])


def new_canvas():
    return Canvas(), random.Random(5), CX + SHIFT[0], CY + SHIFT[1]


def outline(cv):
    src = cv.img.copy()
    for y in range(H):
        for x in range(W):
            if src[y, x, 3] != 0:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= a < W and 0 <= b < H and src[b, a, 3] == 255]
            if hit:
                cv.img[y, x] = INK_LOW if any(b > y for a, b in hit) else INK


def build_base():
    """The collar and the shaft (no lid): the shaft is dark and shows its far wall, a cold glimmer far down."""
    cv, rng, lx, ly = new_canvas()
    # the collar: a ring of cut stones, flush with the ground, a short front face on the south side
    for y in range(CY - 24, CY + 25):
        for x in range(0, W):
            d = ell(x, y, CX, CY, 27.0)
            face = ell(x, y - 2, CX, CY, 27.0)
            if d <= 1.0 or (face <= 1.0 and y > CY):
                ang = (math.degrees(math.atan2((y + 0.5 - CY) / SQ, x + 0.5 - CX)) + 360.0) % 360.0
                seg = int(ang // 24)
                inside = ang % 24
                tone = 2 + int(noise(seg, 3, 5) / 110)
                c = STONE[clampi(tone + (1 if ang > 180 and ang < 300 else 0) - (1 if ang < 90 or ang > 340 else 0), 1, 4)]
                if inside < 1.4:
                    c = STONE[0]
                elif d > 0.93 and d <= 1.0:
                    c = STONE[5] if 180 < ang < 300 else STONE[3]
                elif d > 1.0:
                    c = STONE[1]  # the front face
                elif noise(x, y, 6) > 215:
                    c = STONE[clampi(tone - 1, 0, 5)]
                cv.put(x, y, c)
    # the shaft: dark; the far (north) wall of cut stones shows for a few rows and falls into black, a cold glimmer far down
    for y in range(CY - 20, CY + 21):
        for x in range(8, 56):
            d = ell(x, y, CX, CY, 22.0)
            if d <= 1.0:
                v = 0.15 + 0.25 * (d ** 2) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.15
                c = VOID_DARK[clampi(int(v * 4), 0, 3)]
                top = CY - 22.0 * SQ * math.sqrt(max(0.0, 1.0 - ((x + 0.5 - CX) / 22.0) ** 2))  # the hole's northern edge at this column
                depth = y - top
                if y < CY and depth < 9.0:
                    k = 1.0 - depth / 9.0
                    row = int((y - top) // 3)
                    shade = STONE[1] if ((x // 6 + row) % 2 == 0) else STONE[0]
                    if BAYER[y % 4][x % 4] / 16.0 < k * 0.9:
                        c = shade if depth > 1.0 else STONE[2]
                cv.put(x, y, c)
    for (dx, dy) in [(5, 6), (7, 7), (4, 8)]:
        cv.emit(CX + dx, CY + dy, hexc("0f3040"), TEAL, 2)

    # moss and tufts on the collar and the lid's edge, luminous moss here and there
    for y in range(0, H):
        for x in range(0, W):
            if cv.img[y, x, 3] == 0:
                continue
            d = ell(x, y, CX, CY, 27.0)
            near_edge = 0.9 < d <= 1.0
            if near_edge and noise(x // 2, y // 2, 21) > 175 and noise(x, y, 23) > 70:
                cv.put(x, y, MOSS[clampi(1 + noise(x, y, 22) // 90, 0, 3)])
    for (x, y) in [(CX - 24, CY + 6), (CX + 22, CY - 9), (CX - 6, CY + 21), (CX + 15, CY + 17), (CX - 21, CY - 14)]:
        tuft(cv, x, y, rng.randrange(4, 7), rng)
    for _ in range(5):
        x, y = rng.randrange(8, 56), rng.randrange(6, 46)
        if cv.img[y, x, 3] and 0.9 < ell(x, y, CX, CY, 27.0) <= 1.0:
            cv.emit(x, y, hexc("2a9aa0"), TEAL_L, 1)

    outline(cv)
    for y in range(H):  # a soft shadow to the lower right
        for x in range(W):
            d = ell(x, y, CX + 2, CY + 3, 30.0)
            if d < 1.0 and cv.img[y, x, 3] == 0:
                cv.img[y, x] = (10, 14, 28, 90 if d > 0.6 else 130)
    cv.halos()
    return cv


def build_lid():
    """The lid on its own, lying exactly over the shaft."""
    cv, rng, lx, ly = new_canvas()
    # the lid: a thick cast-iron disc (its edge shows below it), top plate lit from the top left
    for y in range(0, H):
        for x in range(0, W):
            if ell(x, y - 3, lx, ly, LID_R) <= 1.0 and ell(x, y, lx, ly, LID_R) > 1.0:
                cv.put(x, y, IRON[1] if (x + y) % 5 else IRON[0])
    for y in range(0, H):
        for x in range(0, W):
            d = ell(x, y, lx, ly, LID_R)
            if d > 1.0:
                continue
            u, v = (x + 0.5 - lx) / LID_R, (y + 0.5 - ly) / (LID_R * SQ)
            lit = 0.5 - 0.3 * (u + v) + (noise(x // 2, y // 2, 7) / 255.0 - 0.5) * 0.22 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.12
            if d > 0.86:  # the raised rim
                lit += 0.3 if (u + v) < 0 else -0.2
            c = IRON[clampi(int(lit * 5.0), 1, 5)]
            if abs(d - 0.62) < 0.035 or abs(d - 0.34) < 0.03:  # grooves
                c = IRON[0]
            ang = math.degrees(math.atan2(v, u)) % 45.0
            if 0.34 < d < 0.86 and (ang < 2.2 or ang > 43.0) and d > 0.4:  # ribs
                c = IRON[1] if (u + v) > 0 else IRON[4]
            cv.put(x, y, c)
    # rust, thickest at the rim, and streaks running down
    for y in range(0, H):
        for x in range(0, W):
            d = ell(x, y, lx, ly, LID_R)
            if d > 1.0:
                continue
            n = noise(x // 2, y // 2, 11) / 255.0
            if n * 0.7 + d * 0.7 > 1.0 and noise(x, y, 12) > 120:
                cv.put(x, y, RUST[clampi(int((n + d * 0.3) * 3.0) - 1, 0, 3)])
    # the central boss with the bloom, and an iron ring lying on the lid
    for y in range(int(ly) - 5, int(ly) + 6):
        for x in range(int(lx) - 6, int(lx) + 7):
            d = ell(x, y, lx, ly, 6.0)
            if d <= 1.0:
                cv.put(x, y, IRON[4] if (x + y) % 3 else IRON[3] if d < 0.6 else IRON[2])
    for (dx, dy) in [(0, -2), (-2, 0), (2, 0), (0, 2)]:
        cv.put(int(lx) + dx, int(ly) + dy, IRON[1])
    cv.emit(int(lx), int(ly), IRON[1], TEAL, 1)
    # a violet crack across the lid and the collar, the void has been at it
    x, y = lx + 2, ly - 12.0
    for k in range(24):
        xi, yi = int(x), int(y)
        if ell(xi, yi, lx, ly, LID_R) < 0.98:
            lit = k % 5 == 0
            cv.emit(xi, yi, hexc("b89cff") if lit else VIO, VIO_L if lit else hexc("b06bff"), 1 if lit else 0)
        x += rng.choice((0, 1, 1, 0, -1)) * 0.8
        y += 1.0 if k % 2 else 0.6
    rx, ry = int(lx) - 9, int(ly) - 5  # an iron ring handle lies on the lid near the rim
    for k in range(20):
        a = k / 20.0 * math.tau
        cv.put(rx + int(round(math.cos(a) * 4.0)), ry + int(round(math.sin(a) * 3.0)), IRON[5] if k < 9 else IRON[0])
    cv.put(rx - 1, ry + 3, IRON[4])
    outline(cv)
    cv.halos()
    return cv


def save(path, arr):
    h, w = arr.shape[:2]
    write_png(path, w, h, [[tuple(int(v) for v in arr[y, x]) for x in range(w)] for y in range(h)])


def main():
    base, lid = build_base(), build_lid()
    save(ROOT / "props" / "manhole.png", base.img)
    save(ROOT / "props" / "manhole_glow.png", base.glow)
    save(ROOT / "props" / "manhole_lid.png", lid.img)
    save(ROOT / "props" / "manhole_lid_glow.png", lid.glow)
    cv = base
    cv = Canvas()
    cv.img = base.img.copy()
    for y in range(H):  # preview: the lid slid aside
        for x in range(W):
            if lid.img[y, x, 3]:
                nx, ny = x - 4, y - 3
                if 0 <= nx < W and 0 <= ny < H:
                    cv.img[ny, nx] = lid.img[y, x]
    if len(sys.argv) > 1:
        big = np.kron(cv.img, np.ones((8, 8, 1), dtype=np.uint8))
        bg = np.zeros_like(big)
        bg[:, :] = (62, 125, 86, 255)
        a = big[:, :, 3:4] / 255.0
        out = (bg[:, :, :3] * (1 - a) + big[:, :, :3] * a).astype(np.uint8)
        save(pathlib.Path(sys.argv[1]), np.concatenate([out, np.full(out.shape[:2] + (1,), 255, dtype=np.uint8)], axis=2))
    print("manhole cover and its glow written")


if __name__ == "__main__":
    main()
