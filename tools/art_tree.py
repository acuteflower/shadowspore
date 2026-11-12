#!/usr/bin/env python3
"""Draws the fir trees (art_spruce.py), their stump and young stages, wood and resin (stdlib only):
  assets/props/tree.png          6 firs (small 84 px .. ancient matriarch 180 px, giant 192 px), 4 rows of 112x200 frames,
                                 feet at (56, 196), the rows lie exactly on top of each other: 0 trunk + roots + shadow,
                                 1 crown, 2 crown glow, 3 trunk glow.
  assets/props/tree_growth.png   stump (small), stump (large), sapling, young tree (padded to 6 columns)
  assets/items/wood.png, resin.png   icons 16x16"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import TWIG, bezier, blank, check_icon, stroke  # noqa: E402
from art_stone import STEEL, VIO_L, wrap  # noqa: E402
import art_spruce  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

CW, CH = 112, 200
FEET_X, FEET_Y = 56, 196
OUT = hexc("14182c")
OUT_LEAF = hexc("122228")
OUT_WARM = hexc("241836")
OUT_PALE = hexc("1e1c36")
ICON_OUT = hexc("1b1a2e")
BARK = [hexc(c) for c in ("1c1428", "362840", "58445a", "886c7c", "b69a94")]
SHADOW = (10, 14, 28)
WOOD = [hexc(c) for c in ("6a4a3a", "9a6f50", "c79a68", "e6c494")]  # cut wood: shade .. light
AMBER = [hexc(c) for c in ("6f4a10", "b48a38", "e6c468", "fff0b0")]
MOSS = [hexc(c) for c in ("2c6250", "3e7e5a", "589a64")]


def to_pixels(layer):
    return [[c if c is not None else CLEAR for c in row] for row in layer]


def _outline_for(px, y):
    """Material-tinted 1px dark outline: cool slate-teal on foliage, soft plum-indigo on warm/pale blossoms, deep violet-ink on bark/base."""
    r, g, b, _a = px
    if y >= FEET_Y - 6:
        return hexc("16132c")
    if r > g + 22 and r > 110:
        return OUT_WARM
    if r > 175 and g > 155 and b > 170:
        return OUT_PALE
    if g > r + 10:
        return OUT_LEAF
    return OUT


def finish(trunk, crown, shadow_w):
    """Adds the ground shadow to the trunk layer and a material-tinted dark outline around the whole tree."""
    t, c = to_pixels(trunk), to_pixels(crown)
    for y in range(CH):
        for x in range(CW):
            d = ((x + 0.5 - FEET_X) / shadow_w) ** 2 + ((y + 0.5 - (FEET_Y + 1.0)) / 3.3) ** 2
            if d < 1.0 and t[y][x][3] == 0 and c[y][x][3] == 0:
                t[y][x] = (*SHADOW, 116 if d < 0.48 else 64)
    cs, ts = [row[:] for row in c], [row[:] for row in t]
    solid = lambda x, y: 0 <= x < CW and 0 <= y < CH and (cs[y][x][3] == 255 or ts[y][x][3] == 255)  # noqa: E731
    for y in range(CH):
        for x in range(CW):
            if cs[y][x][3] == 255 or ts[y][x][3] == 255:
                continue
            hit = [(a, b) for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if solid(a, b)]
            if hit:
                a, b = hit[0]
                src_px = cs[b][a] if cs[b][a][3] == 255 else ts[b][a]
                (c if cs[b][a][3] == 255 else t)[y][x] = _outline_for(src_px, y)
    return t, c


def sheet(frames):
    return [[CLEAR] * (CW * len(frames)) for _ in range(CH)], frames


def stump(radius, seed):
    t = [[None] * CW for _ in range(CH)]
    top_y = FEET_Y - int(radius * 1.4)
    for y in range(top_y - 4, FEET_Y + 2):
        for dx in range(-int(radius) - 3, int(radius) + 4):
            x = FEET_X + dx
            if y < top_y + 4:  # the cut top: an ellipse with rings
                d = (dx / (radius + 0.4)) ** 2 + ((y - top_y) / (radius * 0.42)) ** 2
                if d <= 1.0:
                    ring = int(math.sqrt(d) * (3.0 + radius * 0.5)) % 2
                    t[y][x] = WOOD[3] if d < 0.12 else (WOOD[2] if ring else WOOD[1])
            else:  # the side, flaring into roots
                hw = radius + max(0.0, (y - (FEET_Y - 4)) * 0.9)
                if abs(dx) <= hw:
                    lit = 0.5 - 0.5 * dx / max(hw, 1.0)
                    t[y][x] = BARK[int(max(0, min(4, lit * 4.0 + (noise(x, y, seed) / 255.0 - 0.5) * 0.9)))]
                    if y > FEET_Y - 5 and dx < 1 and noise(x, y, seed + 17) > 155:
                        t[y][x] = MOSS[1 if lit > 0.45 else 0]
    return finish(t, [[None] * CW for _ in range(CH)], radius + 6)


# ------------------------------------------------------------------ items
def polygon(px, pts, shade):
    n = len(pts)
    for y in range(len(px)):
        for x in range(len(px[0])):
            inside = False
            j = n - 1
            for i in range(n):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > y + 0.5) != (yj > y + 0.5) and (x + 0.5) < (xj - xi) * (y + 0.5 - yi) / (yj - yi) + xi:
                    inside = not inside
                j = i
            if inside:
                px[y][x] = shade(x, y)


AXE_HEAD = [(21.0, 10.6), (25.2, 10.6), (26.4, 8.0), (28.8, 4.2), (27.0, 2.0), (24.0, 1.2), (21.0, 2.0), (19.2, 4.4), (21.8, 8.0)]
AXE_POLL = [(21.0, 10.4), (25.0, 10.4), (25.0, 12.8), (21.0, 12.8)]


def axe_shade(x, y):
    k = (x - 24.0) * -0.45 + (y - 5.0) * -0.75
    return STEEL[3] if k > 3.6 else (STEEL[2] if k > 0.4 else (STEEL[1] if k > -2.6 else STEEL[0]))


def draw_axe(px, rot=0.0, scale=1.0, origin=(0.0, 0.0)):
    c, s_ = math.cos(rot), math.sin(rot)
    tr = lambda p: (origin[0] + scale * ((p[0]) * c - (p[1] - 9.0) * s_), origin[1] + scale * ((p[0]) * s_ + (p[1] - 9.0) * c))  # noqa: E731
    stroke(px, [tr((t * 25.0, 9.0)) for t in [k / 50 for k in range(51)]], 1.3 * scale, 1.3 * scale, TWIG)
    inv = lambda x, y: ((x + 0.5 - origin[0]) / scale * c + (y + 0.5 - origin[1]) / scale * s_, -(x + 0.5 - origin[0]) / scale * s_ + (y + 0.5 - origin[1]) / scale * c + 9.0)  # noqa: E731
    polygon(px, [tr(p) for p in AXE_HEAD], lambda x, y: axe_shade(*inv(x, y)))
    polygon(px, [tr(p) for p in AXE_POLL], lambda x, y: STEEL[1] if inv(x, y)[0] < 23 else STEEL[0])
    for x in range(len(px[0])):
        for y in range(len(px)):
            if px[y][x][3] and px[y][x][:3] in [tuple(c_[:3]) for c_ in STEEL]:
                q = inv(x, y)
                if q[1] < 4.0 and q[0] > 20.5 and (q[0] - 24.0) ** 2 / 20.0 + (q[1] - 3.0) ** 2 / 4.0 > 0.6:
                    px[y][x] = STEEL[3]
    stroke(px, [tr((22.4 + k * 0.4, 9.0)) for k in range(5)], 1.8 * scale, 1.8 * scale, [STEEL[0], STEEL[0], STEEL[1]])


def held_axe():
    px = blank(34, 19)
    draw_axe(px, 0.0, 1.0, (3.0, 9.0))
    wrap(px, [(4 + i, 9.0 + (-1 if i % 2 else 1)) for i in range(7)])
    check_icon("held axe", px)
    return outline_pass(px, ICON_OUT)


def icon_axe():
    px = blank(16, 16)
    draw_axe(px, math.radians(-45), 0.5, (3.4, 13.0))
    wrap(px, [(3 + i * 0.9, 12.6 - i * 0.9) for i in range(3)])
    check_icon("axe", px)
    return outline_pass(px, ICON_OUT)


def icon_wood():
    px = blank(16, 16)
    stroke(px, bezier((4.8, 11.6), (7.6, 8.6), (10.4, 5.4), n=24), 3.0, 3.0, BARK[1:])
    for t in range(0, 24, 3):
        x, y = 5.5 + t * 0.24, 10.8 - t * 0.24
        px[int(y)][int(x)] = BARK[0]
    stroke(px, [(11.2, 4.6)], 3.0, 3.0, WOOD[1:])
    stroke(px, [(11.2, 4.6)], 1.5, 1.5, [WOOD[2], WOOD[2], WOOD[3]])
    px[4][11] = WOOD[0]
    check_icon("wood", px)
    return outline_pass(px, ICON_OUT)


def icon_resin():
    px = blank(16, 16)
    stroke(px, [(8.0, 9.8)], 4.3, 4.3, AMBER[:3])
    stroke(px, bezier((8.0, 5.6), (8.0, 4.2), (8.0, 2.8), n=8), 2.1, 0.5, AMBER[:3])
    px[7][6], px[6][6], px[7][7] = AMBER[3], AMBER[3], AMBER[3]
    px[11][10] = hexc("8a4a10")
    px[12][9] = VIO_L
    check_icon("resin", px)
    return outline_pass(px, ICON_OUT)


def lit_layers(parts, shadow_w):
    return finish(parts["trunk"], parts["crown"], shadow_w)


def check_bounds(label, lit):
    bad = []
    for i, (t, c) in enumerate(lit):
        for name, layer in (("trunk", t), ("crown", c)):
            pts = [(x, y) for y, row in enumerate(layer) for x, px in enumerate(row) if px[3]]
            if pts and (min(y for x, y in pts) < 1 or min(x for x, y in pts) < 1 or max(x for x, y in pts) > CW - 2):
                bad.append(f"{label} variant {i} {name}: top {min(y for x, y in pts)}, x {min(x for x, y in pts)}..{max(x for x, y in pts)}")
    assert not bad, "cut off at frame edge:\n" + "\n".join(bad)


def main():
    props, items = ROOT / "props", ROOT / "items"
    n = len(art_spruce.VARIANTS)
    out = [[CLEAR] * (CW * n) for _ in range(CH * 4)]
    lit_all = []
    for i, spec in enumerate(art_spruce.VARIANTS):
        parts = art_spruce.spruce(spec, 11 + i * 9)
        t, c = lit_layers(parts, spec["width"] / 2.3 + 4)
        lit_all.append((t, c))
        for y in range(CH):
            out[y][i * CW:(i + 1) * CW] = t[y]
            out[CH + y][i * CW:(i + 1) * CW] = c[y]
            out[CH * 2 + y][i * CW:(i + 1) * CW] = to_pixels(parts["glow_crown"])[y]
            out[CH * 3 + y][i * CW:(i + 1) * CW] = to_pixels(parts["glow_trunk"])[y]
    check_bounds("spruce", lit_all)
    write_png(props / "tree.png", CW * n, CH * 4, out)

    growth = []
    for radius in (5.0, 9.0):
        t, _c = stump(radius, 3)
        growth.append(t)
    for spec, seed in ((art_spruce.SAPLING, 70), (art_spruce.YOUNG, 71)):
        t, c = lit_layers(art_spruce.spruce(spec, seed, extras=False), spec["width"] / 2 + 2)
        growth.append([[c[y][x] if c[y][x][3] else t[y][x] for x in range(CW)] for y in range(CH)])
    growth += [[[CLEAR] * CW for _ in range(CH)]] * max(0, n - 4)
    out = [[CLEAR] * (CW * len(growth)) for _ in range(CH)]
    for i, g in enumerate(growth):
        for y in range(CH):
            out[y][i * CW:(i + 1) * CW] = g[y]
    write_png(props / "tree_growth.png", CW * len(growth), CH, out)
    for name, px in (("wood", icon_wood()), ("resin", icon_resin())):
        write_png(items / f"{name}.png", 16, 16, px)
    print(f"firs ({n} variants), stump and growth stages, wood and resin written")


if __name__ == "__main__":
    main()
