#!/usr/bin/env python3
"""Shadowspore skill icons (Schleiergeflecht, F): six 13x13 pixel icons, one per ability, in the ramp of their branch.

    py -3 tools/art_skill_icons.py            # rewrite src/ui/skill_icon_art.gd + docs/img/skill_icons.png
    py -3 tools/art_skill_icons.py preview out.png

The icons are drawn here with a few primitives (lines, polygons, ellipses) onto an index grid, so diagonals stay clean, and
every pixel is then fixed by hand where it matters. Slots (SkillIcons bakes them at run time from the branch colour, so one map
serves gold combat, teal movement and violet shadow):
  =  -  o  +  #   darkest, dark, base, light, bright of the branch colour
  g  G  w         warm gold, light gold, white
  .               transparent. A 1 px ink outline is added when the icon is baked, never drawn by hand.
Needs Pillow only for the contact sheet.
"""
import math
import re
import sys
from pathlib import Path

N = 13
ROOT = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------- palette (mirrors SkillIcons in skill_icons.gd)
BRANCHES = {"combat": "e6c468", "movement": "78f4e6", "shadow": "b06bff"}
FIXED = {"g": "e6c468", "G": "fff0b0", "w": "f4eeff", "x": "08050f"}


def hex_rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def darkened(c, k):
    return tuple(round(v * (1 - k)) for v in c)


def lightened(c, k):
    return tuple(round(v + (255 - v) * k) for v in c)


def ramp(tone):
    base = hex_rgb(tone)
    return {"=": darkened(base, 0.8), "-": darkened(base, 0.52), "o": darkened(base, 0.12), "+": lightened(base, 0.38), "#": lightened(base, 0.78),
            **{k: hex_rgb(v) for k, v in FIXED.items()}}


# ---------------------------------------------------------------- primitives
def blank():
    return [["."] * N for _ in range(N)]


def put(g, x, y, ch):
    if 0 <= x < N and 0 <= y < N:
        g[y][x] = ch


def line(g, x0, y0, x1, y1, ch):
    steps = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(steps + 1):
        t = i / steps if steps else 0
        put(g, round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), ch)


def poly(g, pts, ch):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            inside = False
            for i in range(len(pts)):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % len(pts)]
                if (y1 > y + 0.5) != (y2 > y + 0.5) and x + 0.5 < (x2 - x1) * (y + 0.5 - y1) / (y2 - y1) + x1:
                    inside = not inside
            if inside:
                put(g, x, y, ch)


def ring(g, cx, cy, r0, r1, a0, a1, ch):
    """Pixels between radii r0 and r1 whose angle (degrees, 0 = right, 90 = down) lies in [a0, a1]."""
    for y in range(N):
        for x in range(N):
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            a = math.degrees(math.atan2(dy, dx)) % 360
            lo, hi = a0 % 360, a1 % 360
            inside = lo <= a <= hi if lo <= hi else (a >= lo or a <= hi)
            if r0 <= d <= r1 and inside:
                put(g, x, y, ch)


def pips(g, count):
    start = 6 - (count - 1)
    for i in range(count):
        put(g, start + i * 2, 12, "g")


def bevel(g, ch="+"):
    """Light from the upper left: a `ch` pixel with nothing up-left of it is lit, one with nothing down-right of it is in shade."""
    snap = [row[:] for row in g]

    def at(x, y):
        return snap[y][x] if 0 <= x < N and 0 <= y < N else "."

    for y in range(N):
        for x in range(N):
            if snap[y][x] == ch:
                if at(x - 1, y) == "." or at(x, y - 1) == ".":
                    g[y][x] = "#"
                elif at(x + 1, y) == "." or at(x, y + 1) == ".":
                    g[y][x] = "o"


def rows(g):
    return ["".join(r) for r in g]


# ---------------------------------------------------------------- the icons
def sword(g, x0, y0, x1, y1, half=1.25):
    """A diagonal blade from the pommel (x0, y0) to the tip (x1, y1) with a gold guard."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    gx, gy = x0 + ux * 3.6, y0 + uy * 3.6
    a = (gx + px * half, gy + py * half)
    b = (gx - px * half, gy - py * half)
    poly(g, [a, (x1 + px * 0.2, y1 + py * 0.2), (x1 - px * 0.2, y1 - py * 0.2), b], "+")
    bevel(g, "+")
    line(g, round(gx + ux * 0.2), round(gy + uy * 0.2), x1, y1, "w")  # the keen edge down the middle
    line(g, x0, y0, round(gx - ux * 0.6), round(gy - uy * 0.6), "-")
    line(g, round(gx + px * 3.0), round(gy + py * 3.0), round(gx - px * 3.0), round(gy - py * 3.0), "g")
    put(g, round(gx + px * 3.0), round(gy + py * 3.0), "G")
    put(g, x0, y0, "G")


def icon_combo3():
    g = blank()
    sword(g, 1, 10, 11, 0)
    line(g, 0, 4, 3, 1, "-")  # the swing behind it
    line(g, 4, 11, 9, 6, "-")
    pips(g, 3)
    return g


def icon_combo4():
    g = blank()
    # a steep rising crescent: thin at both ends, thick in the middle, lit from the upper left
    cres = [(0.0, 11.0), (1.2, 8.2), (3.0, 5.4), (5.4, 3.0), (8.2, 1.2), (11.4, 0.0), (9.0, 3.2), (7.0, 5.4), (5.2, 7.8), (3.6, 10.0), (1.8, 11.8)]
    poly(g, cres, "+")
    bevel(g, "+")
    line(g, 2, 8, 5, 4, "w")
    line(g, 5, 4, 9, 1, "w")
    put(g, 12, 0, "G")  # sparks at the end of the cut
    put(g, 12, 2, "g")
    put(g, 10, 0, "g")
    pips(g, 4)
    return g


def icon_combo5():
    g = blank()
    # a whirl: two curved strokes chasing round a bright core, each ending in an arrowhead
    ring(g, 6, 5, 3.6, 5.4, 200, 340, "+")
    ring(g, 6, 5, 3.6, 5.4, 20, 160, "+")
    bevel(g, "+")
    for x, y, ch in ((12, 6, "w"), (11, 7, "+"), (12, 8, "+"), (0, 4, "w"), (1, 3, "+"), (0, 2, "+")):  # arrowheads
        put(g, x, y, ch)
    for x, y, ch in ((6, 4, "G"), (5, 5, "g"), (6, 5, "w"), (7, 5, "g"), (6, 6, "g")):  # the bright core
        put(g, x, y, ch)
    pips(g, 5)
    return g


def icon_stride():
    g = blank()
    # a boot running right, with a cuff, a toe, a heel and three speed lines
    poly(g, [(5, 1), (9, 1), (9, 6), (12, 8), (12, 10), (5, 10), (4, 7)], "+")
    bevel(g, "+")
    poly(g, [(5, 1), (9, 1), (9, 2.4), (5, 2.4)], "g")
    line(g, 5, 10, 12, 10, "=")
    line(g, 5, 9, 12, 9, "-")
    for y, length in ((3, 3), (5, 4), (7, 3)):
        line(g, 0, y, length - 1, y, "#" if y == 5 else "+")
    return g


def icon_sneak():
    g = blank()
    # one bare footprint on tiptoe (ball and toes only, no heel) and the fading trail behind it
    poly(g, [(7, 3), (10, 3), (11, 6), (10, 9), (7, 9), (6, 6)], "+")  # the ball of the foot
    for x, y in ((6, 1), (8, 0), (10, 1), (11, 3)):  # toes
        put(g, x, y, "+")
    bevel(g, "+")
    put(g, 7, 4, "w")
    for x, y, ch in ((3, 10, "-"), (4, 10, "-"), (1, 11, "o"), (0, 11, "o")):  # the trail
        put(g, x, y, ch)
    put(g, 3, 8, "g")
    put(g, 12, 9, "G")
    return g


def icon_rift():
    g = blank()
    # a rip in the dark: a bright core with a violet halo, sparks on both sides
    zig = [(7, 0), (5, 3), (7, 5), (4, 8), (6, 12)]
    for (x0, y0), (x1, y1) in zip(zig, zig[1:]):
        line(g, x0 - 2, y0, x1 - 2, y1, "-")
        line(g, x0 + 2, y0, x1 + 2, y1, "-")
    for (x0, y0), (x1, y1) in zip(zig, zig[1:]):
        line(g, x0 - 1, y0, x1 - 1, y1, "o")
        line(g, x0 + 1, y0, x1 + 1, y1, "o")
        line(g, x0, y0, x1, y1, "#")
    put(g, 7, 0, "w")
    put(g, 6, 12, "w")
    for x, y, ch in ((10, 3, "w"), (11, 8, "+"), (1, 5, "w"), (1, 10, "+"), (11, 11, "-")):
        put(g, x, y, ch)
    return g


ICONS = {"combo3": icon_combo3, "combo4": icon_combo4, "combo5": icon_combo5, "stride": icon_stride, "sneak": icon_sneak, "rift": icon_rift}
BRANCH_OF = {"combo3": "combat", "combo4": "combat", "combo5": "combat", "stride": "movement", "sneak": "movement", "rift": "shadow"}


# ---------------------------------------------------------------- output
def render(name, scale, bg=(26, 17, 44)):
    from PIL import Image
    palette = ramp(BRANCHES[BRANCH_OF[name]])
    g = ICONS[name]()
    size = N + 2
    img = Image.new("RGB", (size, size), bg)
    for y in range(N):
        for x in range(N):
            if g[y][x] != ".":
                img.putpixel((x + 1, y + 1), palette[g[y][x]])
    # outline
    for y in range(N):
        for x in range(N):
            if g[y][x] == ".":
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < N and 0 <= ny < N and g[ny][nx] != ".":
                        img.putpixel((x + 1, y + 1), palette["x"])
                        break
    return img.resize((size * scale, size * scale), Image.NEAREST)


def sheet(out, scale=8):
    from PIL import Image
    names = list(ICONS)
    one = (N + 2) * scale
    img = Image.new("RGB", (len(names) * (one + 8) + 8, one + 16), (26, 17, 44))
    for i, name in enumerate(names):
        img.paste(render(name, scale), (8 + i * (one + 8), 8))
    img.save(out)


def write_gd():
    path = ROOT / "src" / "ui" / "skill_icon_art.gd"
    body = "\n".join("\t%s: %s," % ('"%s"' % n, str(rows(f()))) for n, f in ICONS.items())
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    marker = re.compile(r"(# --- generated icons ---\n).*?(# --- end generated ---)", re.S)
    block = "const ICONS: Dictionary = {\n%s\n}\n" % body
    if marker.search(text):
        text = marker.sub(lambda m: m.group(1) + block + m.group(2), text)
    else:
        text = ("class_name SkillIconArt\nextends RefCounted\n## The skill icons as 13x13 maps (tools/art_skill_icons.py writes the block between the markers; SkillIcons bakes them).\n"
                "## Slots: = - o + # darkest .. bright of the branch colour, g G warm gold, w white, . transparent.\n\n# --- generated icons ---\n" + block + "# --- end generated ---\n")
    path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "preview":
        sheet(sys.argv[2])
    else:
        write_gd()
        out = ROOT / "docs" / "img" / "skill_icons.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet(out)
        print("skill icons written", file=sys.stderr)
