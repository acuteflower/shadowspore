#!/usr/bin/env python3
"""Art for the plant-life additions (docs/plant_life.md), PIL only:
  assets/props/snapper.png        Fangblume: 3 variants x 3 rows (open, snapping half shut, closed bud), frames 40x34, feet (20, 31)
  assets/props/snapper_glow.png   only the emissive pixels (lure bulb, throat veins), drawn unshaded
  assets/props/snapper_stripped.png  the cut stalks (3 x 1)
  assets/items/{shimmer_beetle,leaf_caterpillar,leaf_snail}.png  icons 16x16 (lit from the top left, outline 1b1a2e)
`py -3 tools/art_plant_life.py [preview.png]`."""
import math
import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
FW, FH = 40, 34
INK = (0x1B, 0x1A, 0x2E, 255)


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


LEAF = [hexc(x) for x in ("12283a", "1c4a46", "2c6e54", "449a62", "6cc47a")]
VARIANTS = [  # height, jaw length, outer ramp (dark..light), lining, glow, lean
    {"h": 17, "j": 11, "ramp": [hexc(x) for x in ("2a0a3a", "5a1a6a", "8a2a98", "c050c0", "f0a0e8")], "lining": hexc("c01870"), "glow": hexc("ff4ad0"), "lean": 3},
    {"h": 12, "j": 8, "ramp": [hexc(x) for x in ("0a2a3a", "14506a", "2a8a98", "5ac8c0", "b0f4e8")], "lining": hexc("108a8a"), "glow": hexc("66f0d8"), "lean": -2},
    {"h": 14, "j": 13, "ramp": [hexc(x) for x in ("3a0a14", "7a1424", "b82a30", "e86040", "ffb078")], "lining": hexc("d02a40"), "glow": hexc("ff8a3a"), "lean": 0},
]
TOOTH = hexc("f4ecd8")


def poly_leaf(d, base, tip, width, fill):
    """A tapered blade from `base` to `tip` (widest a third of the way up)."""
    ax, ay = base
    bx, by = tip
    dx, dy = bx - ax, by - ay
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    pts = []
    for t, w in ((0.0, 0.25), (0.33, 1.0), (0.7, 0.7), (1.0, 0.0)):
        pts.append((ax + dx * t + nx * width * w * 0.5, ay + dy * t + ny * width * w * 0.5))
    for t, w in ((0.7, 0.7), (0.33, 1.0), (0.0, 0.25)):
        pts.append((ax + dx * t - nx * width * w * 0.5, ay + dy * t - ny * width * w * 0.5))
    d.polygon(pts, fill=fill)


def outline(img):
    px = img.load()
    w, h = img.size
    marks = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + ox, y + oy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 200 and px[nx, ny] != INK:
                        marks.append((x, y))
                        break
    for m in marks:
        px[m] = INK


def shade_pass(img):
    """A cheap top-left light: pixels with an empty neighbour to the top-left go lighter, to the bottom-right darker."""
    px = img.load()
    w, h = img.size
    out = img.copy()
    op = out.load()
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            c = px[x, y]
            if c[3] < 200 or c == INK:
                continue
            if px[x - 1, y - 1][3] == 0 or px[x, y - 1][3] == 0:
                op[x, y] = tuple(min(255, int(v * 1.22 + 10)) for v in c[:3]) + (255,)
            elif px[x + 1, y + 1][3] == 0 or px[x + 1, y][3] == 0:
                op[x, y] = tuple(int(v * 0.72) for v in c[:3]) + (255,)
    return out


def frame(v, opening, glow=False, closed=False):
    """One snapper: stalk, leaves, jaws opened by `opening` (0 closed .. 1 wide)."""
    img = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = v["ramp"]
    hx, hy = 20 + v["lean"], 31 - v["h"]  # hinge of the jaws
    if not glow:
        d.ellipse((13, 29, 27, 33), fill=(0x1B, 0x1A, 0x2E, 90))
        poly_leaf(d, (19, 31), (9, 24), 7, LEAF[2])
        poly_leaf(d, (21, 31), (31, 25), 7, LEAF[3])
        poly_leaf(d, (20, 31), (14, 27), 5, LEAF[1])
        for i in range(0, 17):
            t = i / 16
            sx = 20 + v["lean"] * t * t
            sy = 31 - v["h"] * t
            d.rectangle((round(sx) - 1, round(sy), round(sx), round(sy) + 1), fill=LEAF[2] if i % 3 else LEAF[3])
    if closed:
        if not glow:
            d.ellipse((hx - 4, hy - 7, hx + 4, hy + 2), fill=r[2])
            d.polygon([(hx - 4, hy - 3), (hx, hy - 11), (hx + 4, hy - 3)], fill=r[2])
            d.line((hx, hy - 11, hx, hy), fill=r[1])
            d.ellipse((hx - 2, hy - 6, hx, hy - 3), fill=r[4])
        else:
            d.point((hx, hy - 11), fill=v["glow"])
        if glow:
            return img
        out = shade_pass(img)
        outline(out)
        return out
    ang = 0.15 + opening * 0.85  # radians from the head's axis (up, leaning with the stalk)
    axis = -math.pi / 2 + v["lean"] * 0.04
    for side in (-1, 1):
        a = axis + side * ang
        tip = (hx + math.cos(a) * v["j"], hy + math.sin(a) * v["j"])
        if not glow:
            poly_leaf(d, (hx, hy), tip, v["j"] * 0.62, r[2] if side < 0 else r[1])
            inner = (hx + math.cos(a - side * 0.35) * v["j"] * 0.8, hy + math.sin(a - side * 0.35) * v["j"] * 0.8)
            d.line((hx, hy, inner[0], inner[1]), fill=v["lining"], width=1)
            for k in range(1, 5):
                t = k / 5
                bx = hx + (tip[0] - hx) * t
                by = hy + (tip[1] - hy) * t
                ix = bx + math.cos(a - side * math.pi / 2) * 1.8
                iy = by + math.sin(a - side * math.pi / 2) * 1.8
                d.point((round(ix), round(iy)), fill=TOOTH)
        else:
            vx, vy = hx + math.cos(a - side * 0.35) * v["j"] * 0.55, hy + math.sin(a - side * 0.35) * v["j"] * 0.55
            d.point((round(vx), round(vy)), fill=v["glow"])
    bulb = (hx + 4, hy - 9 - int(v["j"] * 0.3))
    if not glow:
        d.line((hx, hy + 1, hx + 2, hy - 6, bulb[0], bulb[1] + 1), fill=r[1])
        d.ellipse((bulb[0] - 1, bulb[1] - 1, bulb[0] + 1, bulb[1] + 1), fill=v["glow"])
    else:
        d.ellipse((bulb[0] - 1, bulb[1] - 1, bulb[0] + 1, bulb[1] + 1), fill=v["glow"])
        d.point((bulb[0], bulb[1]), fill=hexc("fff4fa"))
    if glow:
        return img
    out = shade_pass(img)
    outline(out)
    return out


def sheet():
    out = Image.new("RGBA", (FW * 3, FH * 3), (0, 0, 0, 0))
    glow = Image.new("RGBA", (FW * 3, FH * 3), (0, 0, 0, 0))
    stripped = Image.new("RGBA", (FW * 3, FH), (0, 0, 0, 0))
    for i, v in enumerate(VARIANTS):
        for row, (opening, closed) in enumerate(((1.0, False), (0.38, False), (0.0, True))):
            out.paste(frame(v, opening, closed=closed), (i * FW, row * FH))
            glow.paste(frame(v, opening, glow=True, closed=closed), (i * FW, row * FH))
        s = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        sd = ImageDraw.Draw(s)
        sd.ellipse((13, 29, 27, 33), fill=(0x1B, 0x1A, 0x2E, 90))
        for dx in (-3, 0, 3):
            sd.rectangle((20 + dx, 27, 21 + dx, 31), fill=LEAF[2])
            sd.point((20 + dx, 26), fill=LEAF[3])
        poly_leaf(sd, (19, 31), (11, 27), 4, LEAF[1])
        s = shade_pass(s)
        outline(s)
        stripped.paste(s, (i * FW, 0))
    return out, glow, stripped


def icon_canvas():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))


def finish_icon(img):
    img = shade_pass(img)
    outline(img)
    return img


def beetle_icon():
    img = icon_canvas()
    d = ImageDraw.Draw(img)
    shell = [hexc(x) for x in ("14506a", "2a8a98", "5ac8c0", "b0f4e8")]
    d.ellipse((4, 5, 11, 12), fill=shell[1])
    d.line((7, 5, 7, 12), fill=shell[0])
    d.ellipse((5, 6, 7, 8), fill=shell[3])
    d.ellipse((6, 2, 9, 5), fill=shell[0])
    d.point((5, 2), fill=shell[0])
    d.point((10, 2), fill=shell[0])
    for y in (7, 9, 11):
        d.point((3, y), fill=shell[0])
        d.point((12, y), fill=shell[0])
    return finish_icon(img)


def caterpillar_icon():
    img = icon_canvas()
    d = ImageDraw.Draw(img)
    body = [hexc(x) for x in ("2c6e54", "449a62", "8ad87a", "d4f8a0")]
    for i, (x, y) in enumerate([(3, 10), (5, 8), (7, 7), (9, 7), (11, 8)]):
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=body[1] if i % 2 else body[2])
    d.ellipse((11, 6, 13, 8), fill=body[0])
    d.point((12, 7), fill=hexc("f4ecd8"))
    d.point((11, 4), fill=body[0])
    for x in (3, 5, 7, 9):
        d.point((x, 11), fill=body[0])
    return finish_icon(img)


def snail_icon():
    img = icon_canvas()
    d = ImageDraw.Draw(img)
    shell = [hexc(x) for x in ("5a3248", "9a5a6a", "d08a7a", "f4c8a8")]
    body = [hexc(x) for x in ("6a6a8a", "a0a0c0")]
    d.rectangle((2, 10, 12, 12), fill=body[0])
    d.rectangle((2, 10, 11, 10), fill=body[1])
    d.ellipse((4, 3, 11, 10), fill=shell[1])
    d.arc((5, 4, 10, 9), 0, 300, fill=shell[0])
    d.point((7, 6), fill=shell[0])
    d.ellipse((5, 4, 7, 5), fill=shell[3])
    d.line((12, 10, 13, 6), fill=body[0])
    d.line((11, 10, 11, 7), fill=body[0])
    d.point((13, 5), fill=hexc("f4ecd8"))
    return finish_icon(img)


def main():
    out, glow, stripped = sheet()
    props = ROOT / "assets" / "props"
    out.save(props / "snapper.png")
    glow.save(props / "snapper_glow.png")
    stripped.save(props / "snapper_stripped.png")
    items = ROOT / "assets" / "items"
    beetle_icon().save(items / "shimmer_beetle.png")
    caterpillar_icon().save(items / "leaf_caterpillar.png")
    snail_icon().save(items / "leaf_snail.png")
    if len(sys.argv) > 1:
        sheet_img = Image.new("RGBA", (FW * 3 * 4 + 64 * 3, FH * 3 * 4), (40, 60, 40, 255))
        sheet_img.alpha_composite(out.resize((out.width * 4, out.height * 4), Image.NEAREST), (0, 0))
        sheet_img.alpha_composite(glow.resize((glow.width * 4, glow.height * 4), Image.NEAREST), (0, 0))
        for k, ic in enumerate((beetle_icon(), caterpillar_icon(), snail_icon())):
            sheet_img.alpha_composite(ic.resize((64, 64), Image.NEAREST), (FW * 3 * 4 + k * 64, 0))
        sheet_img.save(sys.argv[1])
    print("snapper sheets and critter icons written")


if __name__ == "__main__":
    main()
