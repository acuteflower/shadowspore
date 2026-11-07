#!/usr/bin/env python3
"""Shadowspore cursor art: designs every cursor glyph as a pixel map, writes them into src/ui/cursor_art.gd
(between the `generated glyphs` markers) and renders a contact sheet.

    python3 tools/art_cursor.py                 # rewrite cursor_art.gd + docs/img/cursor.png
    python3 tools/art_cursor.py preview out.png # only the contact sheet

Palette slots (the same ones cursor_art.gd bakes at run time, so day, dusk and night come for free):
  #  +  -   petal white, lilac, deep lilac (the body; shifts violet at night)
  g  h      leaf, leaf light (greens by day, void violets at night)
  k  c  C   accent dark, mid, light (gold by day -> void violet at night; teal / red / magenta / gold when a state asks)
  '.'       transparent. The 1 px outline is added automatically (4-neighbourhood), never drawn by hand.
Needs Pillow only for the contact sheet.
"""
import os
import re
import sys

S = 11      # square glyph canvas
C0 = 5      # its centre pixel

# ---------------------------------------------------------------- palettes (mirror CursorArt in cursor_art.gd)
DAY = {'#': 'f1e6ff', '+': 'bdb3e4', '-': '8f84c2', 'g': '55985f', 'h': 'a8dc8c',
       'k': 'b48a38', 'c': 'e6c468', 'C': 'fff0b0', 'x': '120c1c'}
NIGHT = {'#': 'd8c4ff', '+': '9468ee', '-': '6636ad', 'g': '6a35c8', 'h': 'c9a0ff',
         'k': '6636ad', 'c': '9b5cff', 'C': 'ecd2ff', 'x': '07040d'}
ACCENTS = {
    'teal': {'k': '2a8c94', 'c': '3cc0c6', 'C': 'd0fff8'},
    'red': {'k': '8a1230', 'c': 'ff4a63', 'C': 'ffd0d6'},
    'magenta': {'k': '7a1b78', 'c': 'ff4fd8', 'C': 'ffd6f6'},
    'gold': {'k': 'b48a38', 'c': 'e6c468', 'C': 'fff0b0'},
}


# ---------------------------------------------------------------- helpers
def inpoly(px, py, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def grid():
    return [['.'] * S for _ in range(S)]


def put(g, x, y, ch):
    if 0 <= x < S and 0 <= y < S:
        g[y][x] = ch


def fin(g):
    return [''.join(r) for r in g]


CARD = ((0, -1), (1, 0), (0, 1), (-1, 0))
DIAG = ((1, 1), (1, -1), (-1, 1), (-1, -1))


def diamond(g, cx, cy):
    """A tiny diamond petal: light on the upper left, shaded on the lower right."""
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        put(g, cx + dx, cy + dy, '#' if (dx <= 0 and dy <= 0) else '+')


def core(g):
    put(g, C0, C0, 'C')
    for dx, dy in CARD:
        put(g, C0 + dx, C0 + dy, 'c')


# ---------------------------------------------------------------- glyphs
def arrow():
    poly = [(0, 0), (0, 9.6), (2.5, 7.3), (4.0, 10.9), (5.7, 10.1), (4.3, 6.6), (7.2, 6.6)]
    w, h = 7, 11
    fill = [[inpoly(x + .5, y + .5, poly) for x in range(w)] for y in range(h)]

    def f(x, y):
        return 0 <= x < w and 0 <= y < h and fill[y][x]

    rows = []
    for y in range(h):
        r = ''
        for x in range(w):
            if not fill[y][x]:
                r += '.'
                continue
            edge_r = not f(x + 1, y)
            edge_b = not f(x, y + 1)
            if y == 0:
                ch = 'C'
            elif y == 1 and x == 0:
                ch = 'c'
            elif edge_r and y >= 2 and x > 0:
                ch = '+'
            elif edge_b and y >= 6:
                ch = '+'
            else:
                ch = '#'
            if ch == '+' and y >= 8 and not f(x + 1, y):
                ch = '-'
            r += ch
        rows.append(r)
    # a tiny sprout on the tail: the pointer is alive
    out = [list(r) for r in rows]
    out[9][4] = 'h'
    return [''.join(r) for r in out]


HAND_OPEN = [
    "....#......",
    "..#.#.#....",
    "..#.#.#.#..",
    "..#.#.#.#..",
    ".#########.",
    "##########+",
    ".#########+",
    "..########+",
    "..#######+-",
    "...#####+-.",
]
HAND_CLOSED = [
    "..#.#.#.#..",
    ".#########.",
    ".##########",
    ".##########",
    ".#########+",
    "..########+",
    "..#######+-",
    "...#####+-.",
]


def bloom(d, folded=False):
    g = grid()
    for dx, dy in CARD:
        if folded:
            put(g, C0 + dx * d, C0 + dy * d, '#' if (dx + dy) < 0 else '+')
        else:
            diamond(g, C0 + dx * d, C0 + dy * d)
    core(g)
    return fin(g)


def bud():
    g = grid()
    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        put(g, C0 + dx, C0 + dy, '+' if (dx > 0 or dy > 0) else '#')
    put(g, C0, C0, 'C')
    return fin(g)


def seed(d):
    g = grid()
    for dx, dy in DIAG:
        diamond(g, C0 + dx * d, C0 + dy * d)
    core(g)
    return fin(g)


def fang(d, long_):
    g = grid()
    for dx, dy in CARD:
        spec = [(d + 2, 1, 'c'), (d + 1, 0, 'c'), (d, 0, 'C')]
        if long_:
            spec = [(d + 3, 0, 'c'), (d + 2, 1, 'c'), (d + 1, 0, 'c'), (d, 0, 'C')]
        for dist, w, ch in spec:
            for k in range(-w, w + 1):
                c2 = 'k' if (k != 0 and dist == d + 2 and ch == 'c') else ch
                put(g, C0 + dx * dist + (-dy) * k, C0 + dy * dist + dx * k, c2)
    for p, ch in (((0, 0), 'C'), ((1, 0), 'c'), ((-1, 0), 'c'), ((0, 1), 'c'), ((0, -1), 'c')):
        put(g, C0 + p[0], C0 + p[1], ch)
    return fin(g)


def bracket(d, arm=3):
    g = grid()
    for sx in (-1, 1):
        for sy in (-1, 1):
            for i in range(arm):
                put(g, C0 + sx * d - sx * i, C0 + sy * d, 'C' if i == 0 else 'c')
                put(g, C0 + sx * d, C0 + sy * d - sy * i, 'C' if i == 0 else 'c')
    put(g, C0, C0, 'C')
    return fin(g)


def cross():
    g = grid()
    for i in range(-3, 4):
        edge = 'C' if abs(i) >= 3 else 'c'
        put(g, C0 + i, C0 + i, edge)
        put(g, C0 + i, C0 - i, edge)
    for i in range(-2, 3):
        put(g, C0 + i + 1, C0 + i, 'k')
        put(g, C0 + i + 1, C0 - i, 'k')
    return fin(g)


RING = [(0, -4), (3, -3), (4, 0), (3, 3), (0, 4), (-3, 3), (-4, 0), (-3, -3)]
RING5 = [(0, -3), (2, -2), (3, 0), (2, 2), (0, 3), (-2, 2), (-3, 0), (-2, -2)]
RING4 = [(0, -2), (2, 0), (0, 2), (-2, 0), (1, -1), (1, 1), (-1, 1), (-1, -1)]


def fish(ring, valid):
    g = grid()
    for i, (x, y) in enumerate(ring):
        put(g, C0 + x, C0 + y, 'c' if (valid or i % 2 == 0) else 'k')
    if valid:
        body = (((-1, 0), 'c'), ((0, 0), 'C'), ((1, 0), 'c')) if ring is not RING4 else (((0, 0), 'C'),)
        for p, ch in body:
            put(g, C0 + p[0], C0 + p[1], ch)
    else:
        for p in ((-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)):
            put(g, C0 + p[0], C0 + p[1], 'C')
    return fin(g)


def bite(long_):
    g = grid()
    reach = 4 if long_ else 3
    for k in range(2, reach + 1):
        for dx, dy in CARD:
            put(g, C0 + dx * k, C0 + dy * k, 'C' if k == reach else 'c')
    if long_:
        for dx, dy in DIAG:
            put(g, C0 + dx * 2, C0 + dy * 2, 'c')
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            put(g, C0 + dx, C0 + dy, 'C' if dx == 0 and dy == 0 else 'c')
    return fin(g)


# name -> (rows, hotspot in the glyph's own pixels, preview accent)
GLYPHS = [
    ("arrow",       arrow(),            (0, 0),   None),
    ("hand",        HAND_OPEN,          (5, 4),   None),
    ("fist",        HAND_CLOSED,        (5, 3),   None),
    ("bloom_3",     bloom(2, True),           (C0, C0), None),
    ("bloom_4",     bloom(2),           (C0, C0), None),
    ("bloom_5",     bloom(3),           (C0, C0), None),
    ("bud",         bud(),              (C0, C0), None),
    ("seed_3",      seed(2),            (C0, C0), 'teal'),
    ("seed_4",      seed(3),            (C0, C0), 'teal'),
    ("fang_open",   fang(2, True),      (C0, C0), 'red'),
    ("fang_shut",   fang(2, False),     (C0, C0), 'red'),
    ("bracket_5",   bracket(4, 2),         (C0, C0), 'teal'),
    ("bracket_4",   bracket(3, 2),         (C0, C0), 'teal'),
    ("cross",       cross(),            (C0, C0), 'red'),
    ("fish_6",      fish(RING, True),   (C0, C0), 'teal'),
    ("fish_5",      fish(RING5, True),  (C0, C0), 'teal'),
    ("fish_4",      fish(RING4, True),  (C0, C0), 'teal'),
    ("fish_bad",    fish(RING, False),  (C0, C0), 'red'),
    ("bite_long",   bite(True),         (C0, C0), 'gold'),
    ("bite_short",  bite(False),        (C0, C0), 'gold'),
]

BEGIN = "# ---- generated glyphs (tools/art_cursor.py) ----"
END = "# ---- end of generated glyphs ----"


def gd_name(name):
    return name.upper()


def gd_block():
    out = [BEGIN, ""]
    for name, rows, _hot, _acc in GLYPHS:
        out.append("const %s: Array[String] = [" % gd_name(name))
        out += ['\t"%s",' % r for r in rows]
        out.append("]")
    out.append("")
    out.append("## name -> rows and the pixel that is the mouse position (before the outline's 1 px margin)")
    out.append("const GLYPHS: Dictionary = {")
    for name, rows, hot, _acc in GLYPHS:
        out.append('\t&"%s": {"rows": %s, "hot": Vector2i(%d, %d)},' % (name, gd_name(name), hot[0], hot[1]))
    out.append("}")
    out.append("")
    out.append(END)
    return "\n".join(out)


# ---------------------------------------------------------------- contact sheet
def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp_hex(a, b, t):
    ca, cb = rgb(a), rgb(b)
    return tuple(int(round(ca[i] + (cb[i] - ca[i]) * t)) for i in range(3))


def bake(rows, night, accent):
    from PIL import Image
    h, w = len(rows), max(len(r) for r in rows)
    pal = {k: lerp_hex(DAY[k], NIGHT[k], night) for k in DAY}
    if accent:
        pal.update({k: rgb(v) for k, v in ACCENTS[accent].items()})
    img = [[None] * (w + 2) for _ in range(h + 2)]
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in pal:
                img[y + 1][x + 1] = pal[ch]
    out = [row[:] for row in img]
    for y in range(h + 2):
        for x in range(w + 2):
            if img[y][x] is None:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w + 2 and 0 <= ny < h + 2 and img[ny][nx] is not None:
                        out[y][x] = pal['x']
                        break
    im = Image.new('RGBA', (w + 2, h + 2), (0, 0, 0, 0))
    for y in range(h + 2):
        for x in range(w + 2):
            if out[y][x] is not None:
                im.putpixel((x, y), out[y][x] + (255,))
    return im


def sheet(path, scale=7):
    from PIL import Image
    cell = 16
    nights = (0.0, 0.55, 1.0)
    backs = ('2f624e', '07040d')
    cols = len(GLYPHS)
    out = Image.new('RGBA', (cols * cell * scale, cell * scale * len(nights) * len(backs)), (0, 0, 0, 255))
    row = 0
    for back in backs:
        for night in nights:
            for i, (_n, rows, _hot, acc) in enumerate(GLYPHS):
                tile = Image.new('RGBA', (cell, cell), rgb(back) + (255,))
                im = bake(rows, night, acc)
                tile.alpha_composite(im, ((cell - im.width) // 2, (cell - im.height) // 2))
                tile = tile.resize((cell * scale, cell * scale), Image.NEAREST)
                out.alpha_composite(tile, (i * cell * scale, row * cell * scale))
            row += 1
    out.save(path)


def main():
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    if len(sys.argv) >= 3 and sys.argv[1] == "preview":
        sheet(sys.argv[2])
        return
    path = os.path.join(root, "src", "ui", "cursor_art.gd")
    text = open(path, encoding="utf-8").read()
    pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.S)
    if not pattern.search(text):
        sys.exit("markers not found in " + path)
    text = pattern.sub(lambda _m: gd_block(), text)
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    img_dir = os.path.join(root, "docs", "img")
    os.makedirs(img_dir, exist_ok=True)
    try:
        sheet(os.path.join(img_dir, "cursor.png"))
    except ImportError:
        print("Pillow missing: contact sheet skipped")
    print("cursor art written (%d glyphs)" % len(GLYPHS))


if __name__ == "__main__":
    main()
