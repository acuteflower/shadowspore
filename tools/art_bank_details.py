"""River bank props: 32x32 frames, 6 variants per row, foot (16, 28).
Rows: 0 reeds with cattails, 1 mossy stones, 2 driftwood, 3 wet-grass tufts with blooms,
4 ferns/broad leaves, 5 waterline stones with foam, 6 glow reeds (shore), 7 glow lily blooms and
8 glow kelp (both in the water, drawn without outline).
`bank_details_glow.png` has only the glowing bloom pixels (same layout, drawn unlit at night).
Run: python3 tools/art_bank_details.py [preview.png]"""
import math
import sys
from pathlib import Path
from random import Random
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
W = H = 32
FOOT = (16, 28)
COLS = 6


def hexc(c: str) -> tuple:
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


GREEN = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c")]
STONE = [hexc(c) for c in ("1c1a34", "2e2a52", "47436f", "665f94", "8a83b8", "d0cbec")]
BARK = [hexc(c) for c in ("2a1f33", "43304a", "5f4562", "7d6079", "a08598")]
INK = hexc("1b1a2e")
CATTAIL, CATTAIL_L = hexc("6b4a3a"), hexc("94694c")
VIO, VIO_L, PINK, CREAM, GOLD = hexc("a98af0"), hexc("d0bcff"), hexc("e8a9d0"), hexc("f7f1de"), hexc("f0c862")
TEAL, TEAL_L = hexc("4fd0c0"), hexc("a4fff0")
FOAM = hexc("cfe9e0")
WET = hexc("23363a")


class Frame:
    def __init__(self) -> None:
        self.im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        self.glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))

    def px(self, x: int, y: int, c: tuple, glow: bool = False) -> None:
        if 0 <= x < W and 0 <= y < H:
            self.im.putpixel((x, y), c)
            if glow:
                self.glow.putpixel((x, y), c)

    def line(self, a: tuple, b: tuple, c: tuple) -> None:
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
        for i in range(n + 1):
            t = i / max(n, 1)
            self.px(round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), c)

    def outline(self) -> None:
        """One ink pixel round the silhouette, except below it (a soft contact shadow instead)."""
        src = self.im.copy()
        for y in range(H):
            for x in range(W):
                if src.getpixel((x, y))[3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and src.getpixel((nx, ny))[3]:
                        self.im.putpixel((x, y), INK)
                        break

    def halo(self) -> None:
        """A faint one-pixel bloom round every glowing pixel, so the light reads at night."""
        src = self.glow.copy()
        for y in range(H):
            for x in range(W):
                if src.getpixel((x, y))[3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and src.getpixel((nx, ny))[3]:
                        c = src.getpixel((nx, ny))
                        self.glow.putpixel((x, y), c[:3] + (70,))
                        break

    def shadow(self, w: int) -> None:
        self.shadow_w = w

    def paint_shadow(self) -> None:
        w = getattr(self, 'shadow_w', 0)
        for x in range(FOOT[0] - w, FOOT[0] + w + 1):
            for y in (FOOT[1] + 1, FOOT[1] + 2):
                if y == FOOT[1] + 2 and abs(x - FOOT[0]) > w - 2:
                    continue
                if self.im.getpixel((x, y))[3] == 0:
                    self.im.putpixel((x, y), (20, 30, 40, 70))


def blade(f: Frame, x0: int, h: int, lean: float, ramp: list, thick: bool = False) -> list:
    pts = []
    for i in range(h + 1):
        t = i / h
        pts.append((round(x0 + lean * t * t * h * 0.5), FOOT[1] - i))
    for i, (x, y) in enumerate(pts):
        t = i / h
        c = ramp[min(len(ramp) - 1, int(t * len(ramp)))]
        f.px(x, y, c)
        if thick and t < 0.7:
            f.px(x + 1, y, ramp[max(0, int(t * len(ramp)) - 1)])
    return pts


def reeds(f: Frame, r: Random, v: int) -> None:
    n = 5 + v % 3 * 2
    for i in range(n):
        x = FOOT[0] - 7 + int(i * 14 / (n - 1)) + r.randint(-1, 1)
        h = r.randint(10, 14) + (6 if i % 3 == 1 else 0)
        pts = blade(f, x, h, r.choice((-1.2, -0.6, 0.6, 1.2)) * (1 if x >= FOOT[0] else -1) * 0.5, GREEN[1:5], thick=r.random() < 0.4)
        if v in (1, 2, 4) and i % 3 == 1:  # cattail head on the tallest stems
            hx, hy = pts[-1]
            for k in range(4):
                f.px(hx, hy + k + 1, CATTAIL)
                f.px(hx + 1, hy + k + 1, CATTAIL_L if k < 2 else CATTAIL)
            f.px(hx, hy, GREEN[4])
    for x in range(FOOT[0] - 6, FOOT[0] + 7):
        if r.random() < 0.6:
            f.px(x, FOOT[1], GREEN[0 if r.random() < 0.5 else 1])
    f.shadow(5)


def stone(f: Frame, cx: int, cy: int, rx: float, ry: float, moss: bool, wet: bool = False) -> None:
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            nx, ny = (x - cx) / rx, (y - cy) / ry
            if nx * nx + ny * ny > 1.0:
                continue
            light = -0.65 * nx - 0.75 * ny  # lit from the top left
            idx = 2 + (1 if light > 0.1 else 0) + (1 if light > 0.5 else 0) - (1 if light < -0.25 else 0) - (1 if light < -0.6 else 0)
            c = STONE[max(1, min(4, idx))]
            if moss and ny < -0.1 + 0.4 * math.sin(x * 1.7):
                c = GREEN[max(1, min(4, idx - 1))]
            if wet and ny > 0.35:
                c = WET
            f.px(x, y, c)
    f.px(int(cx - rx * 0.3), int(cy - ry * 0.7), STONE[5])


def stones(f: Frame, r: Random, v: int) -> None:
    n = 2 + v % 3
    spots = [(FOOT[0] - 6, FOOT[1] - 3), (FOOT[0] + 4, FOOT[1] - 2), (FOOT[0] - 1, FOOT[1] - 5), (FOOT[0] + 8, FOOT[1] - 1)]
    r.shuffle(spots)
    for i in range(n):
        x, y = spots[i]
        stone(f, x + r.randint(-1, 1), y, r.uniform(3.2, 6.2), r.uniform(2.6, 4.2), moss=r.random() < 0.55)
    f.shadow(9)


def driftwood(f: Frame, r: Random, v: int) -> None:
    length = r.randint(14, 24)
    tilt = r.uniform(-0.25, 0.25)
    x0 = FOOT[0] - length // 2
    for i in range(length):
        x = x0 + i
        yc = FOOT[1] - 3 + round(tilt * (i - length / 2)) + (1 if i % 7 == 3 else 0)
        for dy in range(-1, 3):
            c = BARK[3] if dy == -1 else (BARK[2] if dy == 0 else (BARK[1] if dy == 1 else BARK[0]))
            if i in (0, length - 1) and dy in (-1, 2):
                continue
            f.px(x, yc + dy, c)
        if i % 5 == 2:
            f.px(x, yc, BARK[4])  # bleached grain
    for end in (0, length - 1):  # cut ends with a pale ring
        f.px(x0 + end, FOOT[1] - 3 + round(tilt * (end - length / 2)) + 1, BARK[4])
    if v % 2 == 0:  # a stub of a branch
        bx = x0 + r.randint(4, length - 5)
        by = FOOT[1] - 4 + round(tilt * (bx - x0 - length / 2))
        f.line((bx, by), (bx + r.choice((-2, 2)), by - 3), BARK[2])
        f.px(bx, by - 3, BARK[3])
    if v % 3 == 1:  # moss patch on top
        for i in range(r.randint(3, 6)):
            f.px(x0 + 3 + i, FOOT[1] - 4 + round(tilt * (3 + i - length / 2)), GREEN[2 + i % 2])
    f.shadow(length // 2)


def flower(f: Frame, x: int, y: int, color: tuple, glow: tuple, big: bool) -> None:
    f.px(x, y, color, glow=True)
    if big:
        for dx, dy in ((-1, 0), (1, 0), (0, -1)):
            f.px(x + dx, y + dy, glow, glow=True)
        f.px(x, y, GOLD if color != GOLD else CREAM)
    else:
        f.px(x, y - 1, glow, glow=True)


def tufts(f: Frame, r: Random, v: int) -> None:
    palette = [(VIO, VIO_L), (PINK, CREAM), (TEAL, TEAL_L), (VIO, PINK), (CREAM, GOLD), (VIO_L, TEAL_L)][v]
    for i in range(6):
        x = FOOT[0] - 6 + i * 2 + r.randint(-1, 1)
        h = r.randint(7, 12)
        pts = blade(f, x, h, r.choice((-0.8, 0, 0.8)), GREEN[1:5])
        if i % 2 == 0 or v == 3:
            flower(f, pts[-1][0], pts[-1][1] - 1, palette[i % 2], palette[(i + 1) % 2], big=(i % 2 == 0))
    for x in range(FOOT[0] - 7, FOOT[0] + 8):
        if r.random() < 0.5:
            f.px(x, FOOT[1], GREEN[0])
        if r.random() < 0.4:
            f.px(x, FOOT[1] - 1, GREEN[1])
    f.shadow(5)


def ferns(f: Frame, r: Random, v: int) -> None:
    count = 5 + v % 3
    for i in range(count):
        ang = -math.pi / 2 + (i - (count - 1) / 2) * 0.46
        length = r.randint(12, 17)
        px, py = FOOT[0] + (i - count / 2) * 0.6, FOOT[1]
        for k in range(length):
            t = k / length
            x = px + math.cos(ang) * k + (t * t * 6 * math.cos(ang + 1.57) * 0.5 if v % 2 else t * t * 3)
            y = py + math.sin(ang) * k * 1.1 + t * t * 3
            ramp = GREEN[1 + min(3, int(t * 4))]
            f.px(round(x), round(y), ramp)
            if k % 2 == 1 and 0.15 < t < 0.95:  # leaflets
                s = 1 + int((1 - t) * 2)
                f.px(round(x) - s, round(y) + 1, GREEN[2])
                f.px(round(x) + s, round(y) + 1, GREEN[3 if k % 4 == 1 else 2])
    f.shadow(8)


def foam_stones(f: Frame, r: Random, v: int) -> None:
    for i in range(1 + v % 3):
        x = FOOT[0] - 5 + i * 6 + r.randint(-1, 1)
        stone(f, x, FOOT[1] - 2, r.uniform(4, 7), r.uniform(2.4, 3.6), moss=r.random() < 0.35, wet=True)
        for dx in range(-5, 6):  # foam rim lapping the waterline
            if r.random() < 0.65:
                f.px(x + dx, FOOT[1] + 1 + (dx % 2), FOAM)


def glow_reeds(f: Frame, r: Random, v: int) -> None:
    pod, spark = [(TEAL, TEAL_L), (VIO, VIO_L), (TEAL, VIO_L), (PINK, CREAM), (TEAL_L, CREAM), (VIO_L, TEAL_L)][v]
    for i in range(6):
        x = FOOT[0] - 6 + i * 2 + r.randint(-1, 1)
        h = r.randint(11, 18)
        pts = blade(f, x, h, r.choice((-1.0, -0.5, 0.5, 1.0)), [hexc("1f4a4a"), GREEN[1], GREEN[2], hexc("3e8a78")])
        hx, hy = pts[-1]
        if i % 2 == 1 or v % 3 == 0:  # luminous seed pods (hanging bulbs) near the tips
            for k in range(3):
                f.px(hx, hy + 1 + k, pod, glow=True)
            f.px(hx, hy, spark, glow=True)
            f.px(hx + 1, hy + 2, spark, glow=True)
        if h > 14:
            f.px(pts[h // 2][0], pts[h // 2][1], spark, glow=True)
    for x in range(FOOT[0] - 6, FOOT[0] + 7):
        if r.random() < 0.6:
            f.px(x, FOOT[1], GREEN[0])
    f.shadow(5)


def lily(f: Frame, r: Random, v: int) -> None:
    petal, tip = [(PINK, CREAM), (VIO_L, VIO), (TEAL_L, CREAM), (CREAM, GOLD), (VIO, PINK), (TEAL, TEAL_L)][v]
    for dx, dy, rx in ((0, 0, 8), (-7, 2, 4)) if v % 2 == 0 else ((0, 0, 8), (6, 2, 4)):
        for y in range(-2, 3):
            for x in range(-rx, rx + 1):
                if (x / rx) ** 2 + (y / 2.4) ** 2 <= 1.0 and not (x > 0 and y == 0 and x > rx - 3 and dx == 0):
                    f.px(FOOT[0] + dx + x, FOOT[1] + dy + y, GREEN[2 if y < 1 else 1] if (x + y) % 5 else GREEN[3])
    for x in range(-3, 4):  # the bloom: layered petals above the pad, glowing
        f.px(FOOT[0] + x, FOOT[1] - 2 - (1 if abs(x) < 3 else 0), petal, glow=True)
    for dx, dy in ((0, -6), (-1, -5), (1, -5), (-2, -4), (2, -4), (0, -5), (0, -4), (-1, -4), (1, -4)):
        f.px(FOOT[0] + dx, FOOT[1] + dy, tip if dy <= -5 else petal, glow=True)
    f.px(FOOT[0], FOOT[1] - 4, GOLD, glow=True)
    f.shadow(0)


def kelp(f: Frame, r: Random, v: int) -> None:
    bulb, spark = [(TEAL, TEAL_L), (VIO, VIO_L), (TEAL_L, CREAM), (PINK, CREAM), (TEAL, VIO_L), (VIO_L, TEAL_L)][v]
    for i in range(4 + v % 3):
        x0 = FOOT[0] - 6 + i * 3 + r.randint(-1, 1)
        h = r.randint(12, 22)
        ph = r.uniform(0, 6.28)
        prev = x0
        for j in range(h):
            x = x0 + round(math.sin(ph + j * 0.38) * (1 + j * 0.06))
            for xx in range(min(prev, x), max(prev, x) + 1):  # no gaps between rows
                f.px(xx, FOOT[1] - j, hexc("1f5a5a") if j % 4 else hexc("2f8a82"))
            prev = x
            if j > 4 and j % 5 == 0:  # luminous nodes
                f.px(x, FOOT[1] - j, bulb, glow=True)
                f.px(x + 1, FOOT[1] - j, spark, glow=True)
        f.px(x, FOOT[1] - h, spark, glow=True)
    f.shadow(0)


ROWS = [reeds, stones, driftwood, tufts, ferns, foam_stones, glow_reeds, lily, kelp]
NO_OUTLINE = (7, 8)


def build() -> tuple:
    sheet = Image.new('RGBA', (W * COLS, H * len(ROWS)), (0, 0, 0, 0))
    glow = Image.new('RGBA', sheet.size, (0, 0, 0, 0))
    for row, draw in enumerate(ROWS):
        for v in range(COLS):
            f = Frame()
            draw(f, Random(7100 + row * 31 + v * 7), v)
            if row not in NO_OUTLINE:
                f.outline()
            f.paint_shadow()
            f.halo()
            sheet.paste(f.im, (v * W, row * H))
            glow.paste(f.glow, (v * W, row * H))
    return sheet, glow


if __name__ == '__main__':
    sheet, glow = build()
    out = ROOT / 'assets/water'
    sheet.save(out / 'bank_details.png')
    glow.save(out / 'bank_details_glow.png')
    if len(sys.argv) > 1:
        bg = Image.new('RGBA', sheet.size, hexc('3e7d56'))
        bg.alpha_composite(sheet)
        bg.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(sys.argv[1])
    print('bank_details:', sheet.size)
