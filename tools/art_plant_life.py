#!/usr/bin/env python3
"""Art for the plant-life additions (docs/plant_life.md):
  assets/props/snapper.png           Fangblume: 5 variants x 3 rows (open, snapping half shut, closed pod), frames 40x34, feet (20, 31)
  assets/props/snapper_glow.png      only the emissive pixels (lure bulb, throat veins), drawn unshaded
  assets/props/snapper_stripped.png  the cut stalks (5 x 1)
  assets/items/{shimmer_beetle,leaf_caterpillar,leaf_snail}.png  icons 16x16 (lit from top left, outline 1b1a2e)
Harmonized with Shadowspore's cel + Bayer pixel-art shading, cool indigo-violet shadows, meadow-teal rosettes,
and adaptive material-tinted 1px outlines.
`python3 tools/art_plant_life.py [preview.png]`."""
import math
import pathlib
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, Glow, outline, put, sheet  # noqa: E402
from art_bush import BAYER, FH, FW, GROUND, bezier, blank, clamp  # noqa: E402
from art_flora import LEAFW, LIGHT, blob, finish, leaf, ramp  # noqa: E402
from gen_art import ROOT as ASSETS_ROOT, hexc, write_png  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
INK = (0x1B, 0x1A, 0x2E, 255)
COLS = 5
TOOTH = hexc("f2ead8")
TOOTH_SHADE = hexc("b8aeaa")

PLUM = ramp("1c0c34", "3a1858", "662a84", "9a4cae", "d488dc")
ABYSS = ramp("0e2038", "18425a", "2a7282", "52b0ae", "9ee4dc")
EMBER = ramp("2c0c1e", "5c1828", "962c34", "ce5a3e", "f49c6c")
INDIGO = ramp("161240", "2e246c", "5442a2", "8672d2", "c4b4f4")

VARIANTS = [
    # v0: Classic twilight-plum S-necked snapper
    {"heads": [(20, 15, 9.5, 2.5, PLUM, hexc("a81c68"), hexc("ff54d4"))], "leaves": 5, "spread": 9},
    # v1: Compact abyssal-teal snapper leaning left
    {"heads": [(20, 12, 8.2, -2.5, ABYSS, hexc("147a7e"), hexc("66f2dc"))], "leaves": 5, "spread": 8},
    # v2: Tall muscular crimson-ember snapper
    {"heads": [(20, 16, 10.2, 0.6, EMBER, hexc("b8283c"), hexc("ff8e3c"))], "leaves": 6, "spread": 10},
    # v3: Twin-headed hunter (plum main jaw + young teal-indigo side trap)
    {"heads": [(16, 15, 8.8, -2.2, PLUM, hexc("a81c68"), hexc("ff54d4")),
               (25, 10, 6.6, 2.6, ABYSS, hexc("147a7e"), hexc("66f2dc"))], "leaves": 7, "spread": 11},
    # v4: Sweeping royal-indigo matriarch trap
    {"heads": [(19, 16, 10.4, 3.4, INDIGO, hexc("7c2894"), hexc("e878ff"))], "leaves": 7, "spread": 11},
]


def draw_stalk(px, x0, hx, hy, seed):
    """Curved S-shaped fleshy stalk with tiny marginal thorns."""
    lean = hx - x0
    pts = bezier((x0, GROUND), (x0 - lean * 0.55, GROUND - (GROUND - hy) * 0.45),
                 (hx + lean * 0.25, hy + (GROUND - hy) * 0.25), (hx, hy + 1), n=30)
    for i, (x, y) in enumerate(pts):
        xi, yi = int(round(x)), int(round(y))
        put(px, xi - 1, yi, LEAFW[3])
        put(px, xi, yi, LEAFW[2])
        put(px, xi + 1, yi, LEAFW[1])
        if i in (8, 16, 23):
            side = -1 if (i + seed) % 2 == 0 else 1
            put(px, xi + side * 2, yi, TOOTH_SHADE if side > 0 else LEAFW[4])


def draw_jaw_lobe(px, hx, hy, ang, length, width, pal, lining, is_upper):
    """Sculpted 3D fleshy trap lobe with shaded outer shell and ribbed inner throat."""
    steps = max(8, int(length * 3))
    curve = -0.32 if is_upper else 0.32
    x, y, a = float(hx), float(hy), ang
    for i in range(steps + 1):
        t = i / steps
        dx, dy = math.cos(a), math.sin(a)
        # Plump shell profile widest around t=0.42
        w = width * math.sin(math.pi * min(1.0, t ** 0.68))
        nx, ny = -dy, dx  # points toward inner mouth for upper lobe if ang ~ -pi/2 - open
        if not is_upper:
            nx, ny = -nx, -ny
        s = -w * 0.85
        while s <= w * 0.65 + 0.01:
            px_x = int(clamp(round(x + nx * s), 2, FW - 3))
            px_y = int(clamp(round(y + ny * s), 2, GROUND - 2))
            if s > w * 0.22:
                # Glossy crimson/teal inner throat lining
                put(px, px_x, px_y, lining if (i // 2) % 2 == 0 else pal[1])
            else:
                # 3D cel + Bayer shaded outer fleshy shell
                ux, uy = (px_x - hx) / max(length, 1.0), (px_y - hy) / max(length, 1.0)
                lit = 0.52 + 0.36 * (ux * LIGHT[0] + uy * LIGHT[1]) - 0.18 * (s / max(w, 0.5))
                lit += (BAYER[px_y % 4][px_x % 4] / 16.0 - 0.5) * 0.20
                put(px, px_x, px_y, pal[int(clamp(lit * len(pal), 0, len(pal) - 1))])
            s += 0.45
        x += dx / 3.0
        y += dy / 3.0
        a += curve / steps
    return x, y


def draw_head(px, glow, x0, h, jlen, lean, pal, lining, gcol, opening, closed, seed):
    hx = clamp(x0 + lean, 9, FW - 10)
    hy = clamp(GROUND - h, 10, GROUND - 6)
    draw_stalk(px, x0, hx, hy, seed)
    # Calyx base cup under jaw hinge
    blob(px, hx, hy + 1.0, 2.5, 1.8, LEAFW[1:5], dither=False)

    if closed:
        # Plump clamped-shut pod with ribbed outer shell, interlocked teeth seam, and tucked glowing lure
        pod_rx, pod_ry = max(3.6, jlen * 0.44), max(4.6, jlen * 0.56)
        cy = max(6.5, hy - pod_ry * 0.68)
        blob(px, hx, cy, pod_rx, pod_ry, pal)
        # Longitudinal seam with interlocked ivory marginal teeth
        for dy in range(-int(pod_ry) + 1, int(pod_ry)):
            yy = int(clamp(round(cy + dy), 3, GROUND - 3))
            sx = int(round(hx + 0.5 * math.sin(dy * 0.6)))
            put(px, sx, yy, pal[0])
            if dy % 2 == 0:
                put(px, sx + (1 if (dy // 2) % 2 else -1), yy, TOOTH if dy < 0 else TOOTH_SHADE)
        put(px, int(round(hx - pod_rx * 0.42)), int(round(cy - pod_ry * 0.35)), pal[4])
        # Lure tendril peeking from the pod apex
        lx, ly = int(clamp(round(hx + (1 if lean >= 0 else -1) * 2), 4, FW - 5)), max(3, int(round(cy - pod_ry - 1)))
        put(px, int(round(hx)), max(3, int(round(cy - pod_ry))), pal[2])
        glow.emit(px, lx, ly, gcol, hexc("fff2fc"), 1)
        return

    axis = -math.pi / 2 + lean * 0.05
    spread_ang = 0.22 + opening * 0.72
    w_lobe = max(2.4, jlen * 0.30)
    # Draw shaded right/lower jaw first, then lit left/upper jaw
    tips = []
    for side in (1, -1):
        a = axis + side * spread_ang
        tx, ty = draw_jaw_lobe(px, hx, hy, a, jlen, w_lobe, pal, lining, is_upper=(side < 0))
        tips.append((side, a, tx, ty))

    # Glowing digestive veins inside throat
    for side, a, _tx, _ty in tips:
        vx = int(clamp(round(hx + math.cos(a - side * 0.22) * jlen * 0.48), 3, FW - 4))
        vy = int(clamp(round(hy + math.sin(a - side * 0.22) * jlen * 0.48), 3, GROUND - 4))
        glow.emit(px, vx, vy, lining, gcol, 0)

    # Marginal ivory teeth along inner jaw rims
    n_teeth = 4 if jlen >= 8.0 else 3
    for side, a, tx, ty in tips:
        for k in range(1, n_teeth + 1):
            t = k / (n_teeth + 0.6)
            bx = hx + (tx - hx) * t
            by = hy + (ty - hy) * t
            inward = a - side * (math.pi * 0.44)
            ix = int(clamp(round(bx + math.cos(inward) * 1.5), 3, FW - 4))
            iy = int(clamp(round(by + math.sin(inward) * 1.5), 3, GROUND - 4))
            put(px, ix, iy, TOOTH if side < 0 else TOOTH_SHADE)

    # Arching lure filament rising from the jaw hinge with a radiant nectar droplet
    lure_side = 1 if lean >= 0 else -1
    bx = clamp(hx + lure_side * (3.2 + opening * 1.2), 5, FW - 6)
    by = clamp(hy - jlen * (0.72 + 0.15 * opening), 4, GROUND - 8)
    f_pts = bezier((hx, hy - 1), (hx + lure_side * 0.8, by - 1.8), (bx, by), n=14)
    for fx, fy in f_pts[:-1]:
        put(px, int(clamp(round(fx), 3, FW - 4)), int(clamp(round(fy), 3, GROUND - 4)), pal[2])
    ibx, iby = int(round(bx)), int(round(by))
    for dx, dy in ((0, 0), (-1, 0), (0, 1)):
        put(px, clamp(ibx + dx, 3, FW - 4), clamp(iby + dy, 3, GROUND - 4), gcol)
    glow.emit(px, ibx, iby, hexc("fff6fc"), gcol, 2)


def make_snapper_frame(spec, v_idx, opening, closed=False, stripped=False):
    seed = 3100 + v_idx * 23 + int(opening * 10) + (5 if closed else 0)
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    # Broad toothed basal rosette in Shadowspore meadow-teal
    n_leaves = spec["leaves"] if not stripped else max(3, spec["leaves"] - 2)
    for i in range(n_leaves):
        a = -math.pi / 2 + (i / max(n_leaves - 1, 1) - 0.5) * 2.55 + rng.uniform(-0.10, 0.10)
        ln = rng.uniform(6.5, 10.5) * (0.58 if stripped else 1.0)
        leaf(px, 20 + math.cos(a) * 1.8, GROUND - 1, a, ln, 2.2 if not stripped else 1.5, LEAFW, curve=-(a + math.pi / 2) * 0.48, tone=3)
    if stripped:
        for hx0, _h, _j, lean, _pal, _lin, _g in spec["heads"]:
            pts = bezier((hx0, GROUND), (hx0 + lean * 0.2, GROUND - 3), (hx0 + lean * 0.4, GROUND - 5), n=8)
            for x, y in pts:
                put(px, int(round(x)) - 1, int(round(y)), LEAFW[3])
                put(px, int(round(x)), int(round(y)), LEAFW[1])
            put(px, int(round(pts[-1][0])), int(round(pts[-1][1])) - 1, LEAFW[4])
    else:
        for h_idx, (hx0, h, jlen, lean, pal, lining, gcol) in enumerate(spec["heads"]):
            draw_head(px, glow, hx0, h, jlen, lean, pal, lining, gcol, opening, closed, seed + h_idx * 7)
    return finish(px, spec["spread"], seed), glow.done()


# ------------------------------------------------------------------ Critter 16x16 item icons (preserved)
def hexc_pil(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def outline_pil(img):
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


def finish_icon(img):
    img = shade_pass(img)
    outline_pil(img)
    return img


def beetle_icon():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shell = [hexc_pil(x) for x in ("14506a", "2a8a98", "5ac8c0", "b0f4e8")]
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
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body = [hexc_pil(x) for x in ("2c6e54", "449a62", "8ad87a", "d4f8a0")]
    for i, (x, y) in enumerate([(3, 10), (5, 8), (7, 7), (9, 7), (11, 8)]):
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=body[1] if i % 2 else body[2])
    d.ellipse((11, 6, 13, 8), fill=body[0])
    d.point((12, 7), fill=hexc_pil("f4ecd8"))
    d.point((11, 4), fill=body[0])
    for x in (3, 5, 7, 9):
        d.point((x, 11), fill=body[0])
    return finish_icon(img)


def snail_icon():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shell = [hexc_pil(x) for x in ("5a3248", "9a5a6a", "d08a7a", "f4c8a8")]
    body = [hexc_pil(x) for x in ("6a6a8a", "a0a0c0")]
    d.rectangle((2, 10, 12, 12), fill=body[0])
    d.rectangle((2, 10, 11, 10), fill=body[1])
    d.ellipse((4, 3, 11, 10), fill=shell[1])
    d.arc((5, 4, 10, 9), 0, 300, fill=shell[0])
    d.point((7, 6), fill=shell[0])
    d.ellipse((5, 4, 7, 5), fill=shell[3])
    d.line((12, 10, 13, 6), fill=body[0])
    d.line((11, 10, 11, 7), fill=body[0])
    d.point((13, 5), fill=hexc_pil("f4ecd8"))
    return finish_icon(img)


def check_fit(name, idx, px):
    pts = [(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]]
    assert not pts or (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2), (
        f"{name} frame {idx} touches border!"
    )


def main():
    frames = []
    for row_idx, (opening, closed) in enumerate(((1.0, False), (0.38, False), (0.0, True))):
        for i, v in enumerate(VARIANTS):
            b, g = make_snapper_frame(v, i, opening, closed=closed, stripped=False)
            check_fit("snapper", row_idx * COLS + i, b)
            check_fit("snapper_glow", row_idx * COLS + i, g)
            frames.append((b, g))
    stripped_frames = []
    for i, v in enumerate(VARIANTS):
        sb, _ = make_snapper_frame(v, i, 0.0, stripped=True)
        check_fit("snapper_stripped", i, sb)
        stripped_frames.append(sb)

    props = ASSETS_ROOT / "props"
    write_png(props / "snapper.png", FW * COLS, FH * 3, sheet([f[0] for f in frames], COLS, 3))
    write_png(props / "snapper_glow.png", FW * COLS, FH * 3, sheet([f[1] for f in frames], COLS, 3))
    write_png(props / "snapper_stripped.png", FW * COLS, FH, sheet(stripped_frames, COLS, 1))

    items = ROOT / "assets" / "items"
    beetle_icon().save(items / "shimmer_beetle.png")
    caterpillar_icon().save(items / "leaf_caterpillar.png")
    snail_icon().save(items / "leaf_snail.png")
    print("snapper (5 variants) sheets and critter icons written")


if __name__ == "__main__":
    main()
