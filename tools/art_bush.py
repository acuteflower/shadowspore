#!/usr/bin/env python3
"""Draws the meadow's bushes and the things you get from them (stdlib only). Re-run to regenerate:
  assets/props/bush.png                 8 plain bushes, 40x34 frames side by side, feet at (20, 31)
  assets/props/bush_berry.png           5 dusk-berry bushes x 2 rows (ripe, picked)
  assets/props/bush_stripped.png        the plucked twig stubs of the 8 plain bushes
  assets/props/bush_berry_stripped.png  the same for the 5 berry bushes
  assets/props/bush_glow.png, bush_berry_glow.png   only the emissive parts, drawn unshaded at night
  assets/items/plant_fiber.png, stick.png, leaf.png, dusk_berry.png   icons 16x16"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

FW, FH = 40, 34
GROUND = 30  # last row of the bush body; the feet are at (20, 31)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# foliage ramps, darkest (violet shade) to lightest — kept exact for bake_ground.py compatibility
MEADOW = [hexc(c) for c in ("1d2748", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d")]
TWILIGHT = [hexc(c) for c in ("141a40", "1a3a48", "245a60", "347a78", "50a090", "86d0b0")]
BUSH = [hexc(c) for c in ("12183a", "153a3a", "1c5645", "2a7656", "3f9a64", "76cc86")]
SAGE = [hexc(c) for c in ("141c3c", "1a4042", "266052", "3a845e", "5eae70", "98da8c")]
LEAF_HI = {
    id(MEADOW): hexc("a8dc8c"),
    id(TWILIGHT): hexc("a6f0d0"),
    id(BUSH): hexc("b0f0c4"),
    id(SAGE): hexc("c0f2ac"),
}
RIM = [hexc("22707e"), hexc("4cc0c4")]
TIP = [hexc(c) for c in ("4a2c8a", "7048d0", "b89cff")]
BUD = (hexc("2a9aa0"), hexc("78f4e6"))
INK = hexc("122424")
INK_LOW = hexc("181632")
INK_WARM = hexc("251b38")
SHADOW = (10, 16, 30)
BERRY = [hexc(c) for c in ("281462", "48289c", "6c42dc", "946cf2")]
BERRY_SPEC = hexc("e0d2ff")
GLINT = hexc("78f4e6")
PINK, LILAC, PETAL_C = hexc("dc9ac4"), hexc("b6ace0"), hexc("fff0e4")
ELDER, ELDER_C = hexc("d8dec8"), hexc("fff6d6")
TWIG = [hexc(c) for c in ("281d34", "523e52", "826876", "b29690")]

# 8 plain bush silhouettes: (lobes, ramp, blossoms_mode)
PLAIN = [
    [(20, 24, 8, 7, 0), (14, 25, 5, 5, -1), (26, 25, 5, 5, -1)],  # 0 small compact cushion
    [(20, 21, 10, 9, 0), (12, 24, 6, 6, -1), (28, 24, 6, 6, -1), (20, 26, 9, 5, 1)],  # 1 rounded medium
    [(20, 18, 12, 11, 0), (10, 23, 7, 7, -1), (30, 23, 7, 7, -1), (20, 26, 12, 6, 1), (15, 13, 6, 6, 1), (26, 13, 6, 6, 1)],  # 2 large tiered
    [(20, 25, 14, 6, 0), (9, 26, 7, 5, -1), (31, 26, 7, 5, -1), (20, 22, 9, 5, 1)],  # 3 wide & low
    [(20, 16, 7, 12, 0), (15, 22, 5, 8, -1), (25, 22, 5, 8, -1), (20, 25, 8, 5, 1)],  # 4 tall spire
    [(20, 21, 10, 9, 0), (11, 24, 6, 6, -1), (29, 24, 6, 6, -1), (20, 26, 10, 5, 1)],  # 5 rose-lilac flowering
    [(16, 20, 9, 9, 0), (25, 23, 9, 7, 1), (9, 25, 6, 5, -1), (31, 26, 6, 4, 0), (19, 15, 7, 6, 1)],  # 6 windswept cascading drift
    [(14, 20, 8, 9, 0), (26, 19, 8, 10, 0), (20, 24, 10, 6, 1), (9, 25, 5, 5, -1), (31, 25, 5, 5, -1)],  # 7 twin-mound elder shrub
]
PLAIN_RAMPS = [BUSH, BUSH, BUSH, SAGE, BUSH, BUSH, MEADOW, SAGE]

# 5 dusk-berry bush silhouettes
BERRIES = [
    PLAIN[1],  # 0 medium rounded
    PLAIN[2],  # 1 large abundant
    PLAIN[3],  # 2 wide sprawling
    [(19, 16, 8, 11, 0), (13, 22, 6, 7, -1), (26, 21, 7, 8, 0), (20, 25, 9, 5, 1)],  # 3 upright woodland berry
    [(14, 21, 8, 8, 0), (25, 19, 9, 9, 1), (20, 25, 11, 5, 1), (8, 25, 5, 5, -1), (32, 24, 5, 5, -1)],  # 4 twin-cushion thicket
]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def lobes_with_tufts(lobes, seed):
    """Small leaf clusters on the rim make the silhouette organic and scalloped."""
    rng = random.Random(seed)
    out = list(lobes)
    for cx, cy, rx, ry, cz in lobes:
        for _ in range(3 + int(rx / 4)):
            a = rng.uniform(math.pi * 1.05, math.pi * 1.95) if rng.random() < 0.7 else rng.uniform(0, math.pi * 2)
            r = rng.uniform(1.9, 3.0)
            nx = clamp(cx + math.cos(a) * rx * 0.90, 4.0, FW - 5.0)
            ny = clamp(cy + math.sin(a) * ry * 0.90, 4.0, GROUND - 1.5)
            out.append((nx, ny, r, r * 0.9, cz + 1))
    return out


def render_body(lobes, ramp, seed, noise_amp=0.28, dither=0.76, leaf_marks=True, bias=0.0):
    """Shades the union of the lobes like spheres (cel bands with ordered dither), adds crisp directional leaf clusters."""
    hi = LEAF_HI.get(id(ramp), ramp[-1])
    h = [[-1e9] * FW for _ in range(FH)]
    nrm = [[None] * FW for _ in range(FH)]
    for cx, cy, rx, ry, cz in lobes:
        for y in range(max(1, int(cy - ry) - 1), min(GROUND + 1, int(cy + ry) + 2)):
            for x in range(max(1, int(cx - rx) - 1), min(FW - 1, int(cx + rx) + 2)):
                dx, dy = (x + 0.5 - cx) / max(rx, 0.5), (y + 0.5 - cy) / max(ry, 0.5)
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                z = math.sqrt(1.0 - d)
                zw = cz * 2.0 + z * max(rx, ry) * 0.8
                if zw > h[y][x]:
                    h[y][x] = zw
                    nrm[y][x] = (dx, dy, z)
    px = [[CLEAR] * FW for _ in range(FH)]
    band = [[-1] * FW for _ in range(FH)]
    for y in range(FH):
        for x in range(FW):
            n = nrm[y][x]
            if n is None:
                continue
            light = (n[0] * -0.56 + n[1] * -0.76 + n[2] * 0.58 + 1.0) / 2.0
            light += (noise(x // 2, y // 2, seed) / 255.0 - 0.5) * noise_amp + bias
            light -= 0.24 * clamp((y - (GROUND - 9)) / 9.0, 0.0, 1.0)
            v = light * (len(ramp) - 0.18) + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * dither
            b = int(clamp(v, 0, len(ramp) - 1))
            band[y][x] = b
            px[y][x] = ramp[b]
    # 2-pixel directional leaf facets: sunlit upper-left leaf with cool crevice shadow below-right
    rng = random.Random(seed + 7)
    area = sum(1 for row in band for b in row if b >= 0)
    for _ in range(area // 13 if leaf_marks else 0):
        x, y = rng.randrange(2, FW - 3), rng.randrange(2, GROUND - 1)
        if band[y][x] >= 2 and band[y + 1][x + 1] >= 0:
            c_hi = ramp[min(band[y][x] + 2, len(ramp) - 1)] if rng.random() < 0.72 else hi
            px[y][x] = c_hi
            if band[y][x - 1] >= 2 and rng.random() < 0.45:
                px[y][x - 1] = ramp[min(band[y][x] + 1, len(ramp) - 1)]
            px[y + 1][x + 1] = ramp[max(band[y + 1][x + 1] - 1, 0)]
    return px, band


def add_outline(px):
    src = [row[:] for row in px]
    for y in range(FH):
        for x in range(FW):
            if src[y][x][3] == 255:
                continue
            near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            hit = [(a, b) for a, b in near if 0 <= a < FW and 0 <= b < FH and src[b][a][3] == 255]
            if hit:
                if any(b > y for _a, b in hit) or y >= GROUND + 1:
                    px[y][x] = INK_LOW
                else:
                    r, g, _b, _al = src[hit[0][1]][hit[0][0]]
                    px[y][x] = INK_WARM if (r > g + 16 and r > 120) else INK


def put_shadow(px, lobes):
    left = min(cx - rx for cx, cy, rx, ry, cz in lobes)
    right = max(cx + rx for cx, cy, rx, ry, cz in lobes)
    mid, half = (left + right) / 2.0, (right - left) / 2.0 + 2
    for y in range(GROUND - 1, min(FH, GROUND + 4)):
        for x in range(FW):
            d = ((x + 0.5 - mid) / half) ** 2 + ((y + 0.5 - (GROUND + 1.2)) / 2.6) ** 2
            if d < 1.0 and px[y][x][3] == 0:
                px[y][x] = (*SHADOW, 118 if d < 0.54 else 66)


def draw_root_twigs(px, lobes, seed):
    """Small glimpses of dark woody stems under the bush skirt so it sits rooted in the soil."""
    rng = random.Random(seed + 91)
    left = int(min(cx - rx * 0.5 for cx, cy, rx, ry, cz in lobes))
    right = int(max(cx + rx * 0.5 for cx, cy, rx, ry, cz in lobes))
    for i in range(2 + (right - left) // 10):
        bx = int(clamp(left + 3 + i * max(3, (right - left - 4) // max(1, 1 + (right - left) // 10)) + rng.randint(-1, 1), 6, FW - 7))
        px[GROUND][bx] = TWIG[1]
        px[GROUND - 1][bx] = TWIG[2 if bx < 20 else 1]
        if px[GROUND][bx + 1][3] == 255:
            px[GROUND][bx + 1] = TWIG[0]


def draw_berries(px, band, lobes, seed, count, glow=None):
    """Dusk berries: plump 3D indigo-violet clusters with soft plum crevice, top-left specular and rare teal glint."""
    rng = random.Random(seed)
    spots = []
    tries = 0
    while len(spots) < count and tries < 700:
        tries += 1
        x, y = rng.randrange(5, FW - 5), rng.randrange(6, GROUND - 3)
        if band[y][x] < 1 or any(band[y + dy][x + dx] < 0 for dx in (-2, 2) for dy in (-2, 2)):
            continue
        if all(abs(x - a) + abs(y - b) >= 5 for a, b in spots):
            spots.append((x, y))
    for x, y in spots:
        # dark leaf socket under berry
        if y + 2 <= GROUND and px[y + 2][x][3] == 255:
            px[y + 2][x] = TWILIGHT[0]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (dx, dy) in ((1, -1), (-1, 1)):
                    continue
                lit = -dx - dy
                px[y + dy][x + dx] = BERRY[2] if lit > 0 else (BERRY[0] if lit < 0 else BERRY[1])
        px[y - 1][x - 1] = BERRY[3] if rng.random() < 0.55 else BERRY_SPEC
        if rng.random() < 0.28 and x + 2 < FW - 2:
            px[y][x + 2] = GLINT
        if glow is not None:
            glow.emit(px, x, y, None, BERRY[3], 2)
            glow.emit(px, x - 1, y - 1, None, BERRY_SPEC, 1)


def draw_blossoms(px, band, seed, glow=None, elder=False):
    rng = random.Random(seed)
    spots = []
    want = 7 if elder else 9
    for _ in range(350):
        x, y = rng.randrange(6, FW - 6), rng.randrange(5, GROUND - 4)
        if band[y][x] >= 2 and all(abs(x - a) + abs(y - b) >= 5 for a, b in spots):
            spots.append((x, y))
        if len(spots) >= want:
            break
    for i, (x, y) in enumerate(spots):
        if elder:
            # Tiny umbel of creamy-sage elderflower florets
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (-2, 0), (1, -1)]:
                if 2 <= x + dx < FW - 2 and 2 <= y + dy < GROUND:
                    px[y + dy][x + dx] = ELDER
            px[y][x] = ELDER_C
            if glow is not None and i % 2 == 0:
                glow.emit(px, x, y, None, ELDER_C, 1)
        else:
            petal = PINK if i % 2 == 0 else LILAC
            shade_p = hexc("96588c") if i % 2 == 0 else hexc("786ca8")
            px[y - 1][x] = petal
            px[y][x - 1] = petal
            px[y][x + 1] = shade_p
            px[y + 1][x] = shade_p
            px[y][x] = PETAL_C
            if glow is not None:
                glow.emit(px, x, y, None, PETAL_C if i % 2 else LILAC, 2)


class GlowLayer:
    def __init__(self):
        self.px = [[CLEAR] * FW for _ in range(FH)]
        self.items = []

    def emit(self, px, x, y, dim, bright, halo=1):
        if 0 <= x < FW and 0 <= y < FH:
            if dim is not None:
                px[y][x] = dim
            self.px[y][x] = (*bright[:3], 255)
            self.items.append((x, y, bright, halo))

    def items_xy(self):
        return [(x, y) for x, y, _c, _r in self.items]

    def done(self):
        for x, y, color, radius in self.items:
            for dy in range(-radius - 1, radius + 2):
                for dx in range(-radius - 1, radius + 2):
                    d = math.hypot(dx, dy)
                    xx, yy = x + dx, y + dy
                    if 0 < d <= radius + 0.5 and 0 <= xx < FW and 0 <= yy < FH and self.px[yy][xx][3] == 0:
                        self.px[yy][xx] = (*color[:3], 106 if d < 1.6 else 48)
        return self.px


def ragged(px, band, ramp, seed, glow, violet):
    """Leaf blades fan out of the silhouette, cool rim light on the right, lit contour on top, glowing buds inside."""
    rng = random.Random(seed + 31)
    solid = lambda x, y: 0 <= x < FW and 0 <= y < FH and px[y][x][3] == 255  # noqa: E731
    rim = []
    for y in range(2, GROUND - 1):
        for x in range(2, FW - 2):
            if not solid(x, y):
                continue
            right, left, up = not solid(x + 1, y), not solid(x - 1, y), not solid(x, y - 1)
            if right or left or up:
                rim.append((x, y, right, left, up))
    for x, y, right, left, up in rim:
        if up and band[y][x] >= 0:
            px[y][x] = ramp[min(band[y][x] + 2, len(ramp) - 1)]
        elif left and band[y][x] >= 0 and band[y][x] < len(ramp) - 1:
            px[y][x] = ramp[band[y][x] + 1]
        elif right and noise(x, y, seed + 12) > 82 and band[y][x] in (1, 2, 3):
            px[y][x] = RIM[int(noise(x, y, seed + 13) > 152)]
    for x, y, right, left, up in rim:
        if noise(x, y, seed + 40) > 84 or y > GROUND - 5:
            continue
        dx = (1 if right else 0) - (1 if left else 0)
        dy = -1 if up else 0
        if dx == 0 and dy == 0:
            continue
        length = rng.randrange(1, 3) if (up and dx == 0) else rng.randrange(2, 4)
        cx, cy = float(x), float(y)
        tone = band[y][x] if band[y][x] >= 0 else 2
        xi, yi = x, y
        for k in range(length):
            cx += dx * 0.8 + rng.uniform(-0.22, 0.22)
            cy += dy * 0.6 + (0.48 * k if dx != 0 else 0.0)
            xi, yi = int(round(cx)), int(round(cy))
            if not (1 < xi < FW - 2 and 1 < yi < GROUND):
                break
            if px[yi][xi][3] == 0:
                light = 2 if (dy < 0 or dx < 0) else 0
                px[yi][xi] = ramp[max(0, min(len(ramp) - 1, tone + light - (1 if k > 1 else 0)))]
        if 1 < xi < FW - 2 and 1 < yi < GROUND and rng.random() < violet and px[yi][xi][3] == 255:
            px[yi][xi] = TIP[int(rng.random() > 0.5)]
    buds = 0
    for _ in range(90):
        x, y = rng.randrange(6, FW - 6), rng.randrange(6, GROUND - 5)
        if px[y][x][3] == 255 and band[y][x] >= 2 and buds < 3 and all(abs(x - a) + abs(y - b) > 9 for a, b in glow.items_xy()):
            glow.emit(px, x, y, BUD[0], BUD[1], 1)
            buds += 1


def make_bush(lobes, ramp, seed, berries=0, blossoms=False, elder=False):
    full = lobes_with_tufts(lobes, seed)
    px, band = render_body(full, ramp, seed, bias=-0.10)
    glow = GlowLayer()
    ragged(px, band, ramp, seed, glow, 0.16)
    draw_root_twigs(px, lobes, seed)
    if berries:
        draw_berries(px, band, full, seed + 3, berries, glow)
    if blossoms or elder:
        draw_blossoms(px, band, seed + 5, glow, elder=elder)
    base = [[CLEAR] * FW for _ in range(FH)]
    put_shadow(base, full)
    for y in range(FH):
        for x in range(FW):
            if px[y][x][3] == 255:
                base[y][x] = px[y][x]
    add_outline(base)
    return base, glow.done()


def make_stripped(lobes, ramp, seed):
    rng = random.Random(seed)
    top = min(cy - ry for cx, cy, rx, ry, cz in lobes)
    left = min(cx - rx for cx, cy, rx, ry, cz in lobes)
    right = max(cx + rx for cx, cy, rx, ry, cz in lobes)
    px = [[CLEAR] * FW for _ in range(FH)]
    put_shadow(px, [(20, GROUND - 2, (right - left) / 2.6, 3, 0)])
    reach = (GROUND - top) * 0.5
    for i in range(5 + int((right - left) / 9)):
        x = 20 + (i - 2.5) * (right - left) / 12.0 + rng.uniform(-1, 1)
        lean = rng.uniform(-0.9, 0.9)
        length = reach * rng.uniform(0.55, 1.0)
        for s in range(int(length)):
            xi, yi = int(round(x + lean * s * 0.55 + math.sin(s * 0.8 + i) * 0.7)), int(GROUND - s)
            if 1 <= xi < FW - 2 and yi > 1:
                px[yi][xi] = TWIG[2] if s % 3 else TWIG[1]
                if s > 1:
                    px[yi][xi + 1] = TWIG[1]
            if s == int(length) - 1 and rng.random() < 0.5 and 1 <= xi < FW - 2 and yi > 2:
                px[yi - 1][xi] = ramp[3]
        if rng.random() < 0.6:
            ty = int(GROUND - length * rng.uniform(0.4, 0.7))
            tx = int(round(x + lean * (GROUND - ty) * 0.55))
            for k in range(1, 4):
                if 1 < tx + k < FW - 1 and ty - k > 1:
                    px[ty - k][tx + k] = TWIG[2]
    for x in range(max(2, int(left) + 4), min(FW - 2, int(right) - 3)):
        if rng.random() < 0.55:
            px[GROUND][x] = ramp[rng.choice((1, 2, 3))]
            px[GROUND - 1][x] = ramp[rng.choice((2, 3, 4))] if rng.random() < 0.5 else px[GROUND - 1][x]
    add_outline(px)
    return px


# ------------------------------------------------------------------ items
def blank(w, h):
    return [[CLEAR] * w for _ in range(h)]


def stroke(px, pts, r0, r1, colors, light=(-0.6, -0.8)):
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        r = r0(i / max(n - 1, 1)) if callable(r0) else r0 + (r1 - r0) * i / max(n - 1, 1)
        for yy in range(int(y - r - 1), int(y + r + 2)):
            for xx in range(int(x - r - 1), int(x + r + 2)):
                d = math.hypot(xx + 0.5 - x, yy + 0.5 - y)
                if d <= r and 0 <= yy < len(px) and 0 <= xx < len(px[0]):
                    k = ((xx + 0.5 - x) * light[0] + (yy + 0.5 - y) * light[1]) / max(r, 0.5)
                    px[yy][xx] = colors[min(int((k + 1.0) / 2.0 * len(colors) * 0.999), len(colors) - 1)]


def bezier(*p, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        if len(p) == 3:
            w = [(1 - t) ** 2, 2 * t * (1 - t), t * t]
        else:
            w = [(1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3]
        out.append((sum(a * q[0] for a, q in zip(w, p)), sum(a * q[1] for a, q in zip(w, p))))
    return out


def ascii_art(rows, palette):
    assert len({len(r) for r in rows}) == 1, "rows differ in length"
    return [[palette[c] if c != "." else CLEAR for c in r] for r in rows]


def check_icon(name, px):
    pts = {(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]}
    xs, ys = [x for x, y in pts], [y for x, y in pts]
    assert min(xs) >= 1 and max(xs) <= len(px[0]) - 2 and min(ys) >= 1 and max(ys) <= len(px) - 2, "%s leaves the frame: x %d..%d y %d..%d" % (name, min(xs), max(xs), min(ys), max(ys))
    seen, stack = set(), [next(iter(pts))]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        stack += [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (x + dx, y + dy) in pts]
    assert len(seen) == len(pts), "%s has %d loose pixels" % (name, len(pts) - len(seen))
    return px


FIBER = ascii_art([
    "................",
    "...c..d..c.d....",
    "..cbd.cb.dbc.c..",
    "..cbbcdbcbcbbc..",
    "..bbcbbcbdbcbb..",
    "..bcbbcbbcbbcb..",
    "...bbcbbbcbbb...",
    "...abbcbbbcba...",
    "....vvvvvvvv....",
    "....wxxyxxxw....",
    "....vvvvvvvv....",
    "...abbcbbbcba...",
    "..bbcbbcbbcbbc..",
    "..bcbbcbbbcbbb..",
    "...cbb.cb.bbc...",
    "................",
], {"a": hexc("8fb36e"), "b": hexc("b9d08a"), "c": hexc("d9e6a8"), "d": hexc("eef4c4"), "v": hexc("2a1568"), "w": hexc("4a2aa0"), "x": hexc("6a3ee0"), "y": hexc("b06bff")})


def icon_fiber():
    check_icon("plant_fiber", FIBER)
    return outline_pass(FIBER, hexc("1b1a2e"))


def icon_stick():
    px = blank(16, 16)
    stroke(px, bezier((2.5, 13.2), (7.5, 8.5), (12.3, 3.8), n=30), 1.5, 1.0, TWIG)
    stroke(px, bezier((6.8, 9.3), (10.5, 9.6), (13.4, 8.8), n=16), 1.0, 0.55, TWIG)
    stroke(px, bezier((5.0, 11.2), (3.8, 8.4), (3.2, 6.2), n=12), 0.9, 0.5, TWIG)
    for x, y in [(9, 7), (6, 10), (11, 5)]:
        px[y][x] = TWIG[0]
    for x, y in [(13, 2), (14, 2), (13, 3), (14, 3)]:
        px[y][x] = MEADOW[5] if (x, y) == (13, 2) else MEADOW[4]
    check_icon("stick", px)
    return outline_pass(px, hexc("1b1a2e"))


def icon_leaf():
    px = blank(16, 16)
    x0, y0, x1, y1 = 4.0, 12.0, 13.2, 2.8
    ln = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / ln, (y1 - y0) / ln
    vx, vy = -uy, ux
    for y in range(16):
        for x in range(16):
            t = ((x + 0.5 - x0) * ux + (y + 0.5 - y0) * uy) / ln
            d = (x + 0.5 - x0) * vx + (y + 0.5 - y0) * vy
            if 0.0 < t < 1.0:
                half = 3.9 * math.sin(math.pi * t ** 0.8) ** 0.8
                if abs(d) < half:
                    lit = -d / max(half, 0.1)
                    px[y][x] = MEADOW[5] if lit > 0.4 else (MEADOW[4] if lit > -0.1 else (MEADOW[3] if lit > -0.6 else MEADOW[2]))
                    if abs(d) < 0.5:
                        px[y][x] = MEADOW[2]
                    elif 0.3 < t < 0.85 and abs(abs(d) - (t - 0.2) * 3.4) < 0.45:
                        px[y][x] = MEADOW[2]
    stroke(px, bezier((2.4, 13.6), (3.2, 12.8), (4.3, 11.8), n=8), 0.7, 0.7, [TWIG[1], TWIG[2], TWIG[2]])
    px[3][12] = hexc("a6f0d0")
    check_icon("leaf", px)
    return outline_pass(px, hexc("1b1a2e"))


def icon_berry():
    px = blank(16, 16)
    for cx, cy in [(5.2, 10.5), (10.2, 10.5), (7.7, 6.0)]:
        stroke(px, [(cx, cy)], 3.1, 3.1, BERRY[:3])
        px[int(cy - 1.5)][int(cx - 1.5)] = BERRY_SPEC
    px[9][12] = GLINT
    for x, y in [(7, 3), (8, 2), (8, 1)]:
        px[y][x] = hexc("5a4556")
    px[2][9], px[2][10], px[1][10] = MEADOW[4], MEADOW[5], MEADOW[3]
    return outline_pass(px, hexc("1b1a2e"))


def main():
    props = ROOT / "props"
    items = ROOT / "items"
    np = len(PLAIN)
    nb = len(BERRIES)
    plain = [make_bush(l, PLAIN_RAMPS[i], 10 + i * 17, blossoms=(i == 5), elder=(i == 7)) for i, l in enumerate(PLAIN)]
    berry_n = [9, 13, 10, 11, 12]
    ripe = [make_bush(l, TWILIGHT, 90 + i * 13, berries=berry_n[i]) for i, l in enumerate(BERRIES)]
    bare = [make_bush(l, TWILIGHT, 90 + i * 13) for i, l in enumerate(BERRIES)]
    sheet = lambda frames, cols, rows: [[frames[(y // FH) * cols + x // FW][y % FH][x % FW] if (y // FH) * cols + x // FW < len(frames) else CLEAR for x in range(FW * cols)] for y in range(FH * rows)]  # noqa: E731
    write_png(props / "bush.png", FW * np, FH, sheet([b[0] for b in plain], np, 1))
    write_png(props / "bush_glow.png", FW * np, FH, sheet([b[1] for b in plain], np, 1))
    write_png(props / "bush_berry.png", FW * nb, FH * 2, sheet([b[0] for b in ripe + bare], nb, 2))
    write_png(props / "bush_berry_glow.png", FW * nb, FH * 2, sheet([b[1] for b in ripe + bare], nb, 2))
    write_png(props / "bush_stripped.png", FW * np, FH, sheet([make_stripped(l, PLAIN_RAMPS[i], 5 + i) for i, l in enumerate(PLAIN)], np, 1))
    write_png(props / "bush_berry_stripped.png", FW * nb, FH, sheet([make_stripped(l, TWILIGHT, 40 + i) for i, l in enumerate(BERRIES)], nb, 1))
    for name, fn in [("plant_fiber", icon_fiber), ("stick", icon_stick), ("leaf", icon_leaf), ("dusk_berry", icon_berry)]:
        write_png(items / f"{name}.png", 16, 16, fn())
    print(f"bushes ({np} plain, {nb} berry), stripped bushes and plant item icons written")


if __name__ == "__main__":
    main()
