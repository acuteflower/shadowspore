"""Three new water plants, 32x32 frames, foot (16, 28), 6 variants per row, no outline (they float or stand under the surface):
rows 0/1 Linsenteppich (duckweed mat, two shimmer frames), 2/3 Goldmummel (floating heart leaves with golden cup blooms: open by day,
closed glowing buds by night), 4/5 Federkraut (submerged feathery hornwort with bubbles, two sway frames).
assets/water/water_flora.png and water_flora_glow.png (only the luminous pixels, drawn unlit at night).
Run: python3 tools/art_water_plants.py [preview.png]"""
import math
import sys
from pathlib import Path
from random import Random
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_bank_details import CREAM, FOOT, GOLD, GREEN, PINK, TEAL, TEAL_L, VIO, VIO_L, Frame, H, W, hexc  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
COLS = 6
LIME = hexc("b4e890")
DEEP = hexc("1f5a5a")
SEAGREEN = [hexc(c) for c in ("1f5a5a", "2a7a74", "3f9a8c", "62bcac", "a4fff0")]
LEAF = GREEN[:5]  # the same ramp as the sedges, pads and the land flora (art_river_details.py, art_bank_details.py)
SEA = [hexc(c) for c in ("1f5a5a", "2a7a74", "3f9a8c", "62bcac", "a4fff0")]  # the submerged family: grasses, hornwort
WATER_DARK, RIPPLE = (20, 40, 46, 120), (110, 214, 200, 110)
BLOOMS = [(hexc("f0c862"), hexc("ffe9a0"), hexc("e0902a")), (hexc("f0a040"), hexc("ffd080"), hexc("c05820")),
          (hexc("f6e69a"), hexc("fffbd8"), hexc("d0b040")), (hexc("f0b4a0"), hexc("ffe0d0"), hexc("c86a58")),
          (hexc("e8d070"), hexc("fff2b0"), hexc("a07820")), (hexc("ffdc8a"), hexc("fff6d0"), hexc("e8a040"))]


def duckweed(f: Frame, r: Random, v: int, alt: int) -> None:
    """A loose mat of tiny round leaves in a squashed ellipse, with gaps of water, a few violet-tinged and luminous ones."""
    tones = [GREEN[3:], [LIME, GREEN[4], GREEN[3]], [hexc("6cc89c"), hexc("8edcb0"), hexc("48a888")], GREEN[2:5], [LIME, hexc("d4f4a8"), GREEN[4]], GREEN[3:]][v]
    n = 70 + v * 10
    cx, cy, rx, ry = FOOT[0], FOOT[1] - 4, 12 + (v % 3), 5 + (v % 2)
    pts = []
    for _ in range(n):
        a = r.uniform(0, math.tau)
        d = math.sqrt(r.random())
        pts.append((round(cx + math.cos(a) * rx * d), round(cy + math.sin(a) * ry * d)))
    for i, (x, y) in enumerate(pts):
        x += (1 if alt and i % 3 == 0 else 0)  # the second frame nudges a few leaves: the mat breathes
        c = tones[i % len(tones)]
        f.px(x, y, c)
        f.px(x + 1, y, tones[(i + 1) % len(tones)])  # a small round leaf: two pixels wide, shaded below
        f.px(x, y + 1, tones[-1] if i % 3 else DEEP)
        if i % 4 == 0:
            f.px(x + 1, y + 1, DEEP)
        if v in (1, 5) and i % 15 == 0:
            f.px(x, y, hexc("a898e0"))
        if i % 19 == (3 if alt else 11):  # a glint on a leaf
            f.px(x, y, hexc("e8fff4"))
        if i % 10 == 5:
            f.px(x, y, TEAL_L, glow=True)  # luminous plankton clinging to the mat


def mummel(f: Frame, r: Random, v: int, closed: int) -> None:
    petal, light, deep = BLOOMS[v]
    pads = [(0, 0, 8), (-8, 2, 5), (7, 3, 5)][: 2 + (v % 2)]
    for dx, dy, rx in pads:  # the dark contact shadow of every pad and a bright ripple dash at its sides
        for x in range(-rx, rx + 1):
            f.px(FOOT[0] + dx + x, FOOT[1] + 2 + dy, WATER_DARK)
        f.px(FOOT[0] + dx - rx - 1, FOOT[1] + 2 + dy, RIPPLE)
        f.px(FOOT[0] + dx + rx + 1, FOOT[1] + 2 + dy, RIPPLE)
    for dx, dy, rx in pads:
        for y in range(-3, 4):
            for x in range(-rx, rx + 1):
                nx, ny = x / rx, y / 3.2
                if nx * nx + ny * ny > 1.0:
                    continue
                if x > 0 and abs(y) <= 1 and x > rx - 3 and dx >= 0:  # the notch of a heart-shaped leaf
                    continue
                lit = -0.5 * nx - 0.8 * ny
                c = LEAF[max(1, min(4, 2 + (1 if lit > 0.2 else 0) + (1 if lit > 0.6 else 0) - (1 if lit < -0.4 else 0)))]
                f.px(FOOT[0] + dx + x, FOOT[1] - 1 + dy + y, c)
        for k in range(-rx + 2, rx - 2):  # the vein
            if k % 2 == 0:
                f.px(FOOT[0] + dx + k, FOOT[1] - 1 + dy, LEAF[1])
    for i in range(1 + v % 3):  # stems and blooms, rising from the middle pad
        bx = FOOT[0] + (i - 1) * 5 + r.randint(-1, 1)
        h = 7 + r.randint(0, 3) + i
        for j in range(h):
            f.px(bx, FOOT[1] - 2 - j, LEAF[3] if j % 2 else LEAF[2])
        top = FOOT[1] - 2 - h
        if not closed:
            for dx in range(-3, 4):  # an open cup of golden petals
                f.px(bx + dx, top + (1 if abs(dx) == 3 else 0), petal if abs(dx) < 3 else deep, glow=abs(dx) < 2)
            for dx in range(-2, 3):
                f.px(bx + dx, top - 1, light if dx < 1 else petal, glow=True)
            f.px(bx - 1, top - 2, light)
            f.px(bx + 1, top - 2, petal)
            f.px(bx, top, deep, glow=True)
        else:  # shut for the night: a green-gold bud on a drooping neck, its tip glowing
            for dy in range(0, 4):
                f.px(bx + 1, top + dy, LEAF[3])
                f.px(bx + 2, top + dy, LEAF[2])
            f.px(bx + 1, top - 1, petal, glow=True)
            f.px(bx + 2, top - 1, deep)
            f.px(bx + 1, top - 2, light, glow=True)


def feather(f: Frame, r: Random, v: int, sway: int) -> None:
    """Hornwort: a few thick stems with clean, sparse whorls of needles, translucent under the surface, pale glowing tips, rising bubbles.
    Same sea-green ramp as the submerged grasses of art_river_details.py; no outline (nothing of it reaches above the water)."""
    for i in range(3 + v % 2):
        x0 = FOOT[0] - 7 + i * 5 + r.randint(-1, 1)
        h = r.randint(14, 22)
        ph = r.uniform(0, math.tau)
        top_x = x0
        for j in range(h):
            drift = round(math.sin(ph + j * 0.28 + (1.2 if sway else 0.0)) * (0.5 + j * 0.06))
            x = x0 + drift
            y = FOOT[1] - j
            f.px(x, y, SEA[1])
            f.px(x - 1, y, SEA[2])  # lit side
            if j % 4 == 2:  # a whorl: two needles up and out, a pale tip
                ln = max(2, 4 - j // 9)
                for k in range(1, ln + 1):
                    c = SEA[3] if k == ln else SEA[2]
                    f.px(x - k - 1, y - k // 2, c)
                    f.px(x + k, y - k // 2, SEA[1] if k < ln else SEA[3])
            top_x = x
        f.px(top_x, FOOT[1] - h, SEA[4], glow=True)
        f.px(top_x - 1, FOOT[1] - h, SEA[3])
        if i % 2 == 1:  # a bubble on its way to the surface
            f.px(top_x + 1 + sway, FOOT[1] - h - 3 - 2 * sway, hexc("e8fff4"))
    for y in range(H):  # the translucent look of things under water
        for x in range(W):
            px = f.im.getpixel((x, y))
            if px[3]:
                f.im.putpixel((x, y), px[:3] + (228,))


ROWS = [(duckweed, 0), (duckweed, 1), (mummel, 0), (mummel, 1), (feather, 0), (feather, 1)]


def build() -> tuple:
    sheet = Image.new('RGBA', (W * COLS, H * len(ROWS)), (0, 0, 0, 0))
    glow = Image.new('RGBA', sheet.size, (0, 0, 0, 0))
    for row, (draw, state) in enumerate(ROWS):
        for v in range(COLS):
            f = Frame()
            draw(f, Random(9100 + (row // 2) * 53 + v * 7), v, state)  # both rows of a pair share the random stream: same plant, other state
            if row in (2, 3):  # floating leaves get the same ink outline as the land plants; hornwort lives under water and the duckweed film is single pixels: none
                f.outline()
            f.halo()
            sheet.paste(f.im, (v * W, row * H))
            glow.paste(f.glow, (v * W, row * H))
    return sheet, glow


if __name__ == '__main__':
    sheet, glow = build()
    out = ROOT / 'assets/water'
    sheet.save(out / 'water_flora.png')
    glow.save(out / 'water_flora_glow.png')
    if len(sys.argv) > 1:
        bg = Image.new('RGBA', sheet.size, hexc('3a7a84'))
        bg.alpha_composite(sheet)
        bg.alpha_composite(glow)
        bg.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(sys.argv[1])
    print('water_flora:', sheet.size)
