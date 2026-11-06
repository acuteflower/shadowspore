#!/usr/bin/env python3
"""Two more mushrooms for the meadow's shade (stdlib only), frames 40x34 like the other plants (feet at (20, 31)):
  assets/props/ember_morel.png      Glutmorchel: 3 stands of honeycomb-capped morels x 2 rows (whole, picked); warm ochre caps whose
                                    dark pits glow like embers at night, cream stems
  assets/props/moon_parasol.png     Mondschirm: 3 stands of tall parasol mushrooms x 2 rows (whole, picked); a wide pale-lilac cap with
                                    fine radial fibres, a delicate ring on the stem and a rim of light; sheds spores when brushed
  every sheet has a `_glow` twin with only the emissive pixels
  assets/items/ember_morel.png, moon_parasol.png   icons 16x16
`python3 tools/art_shrooms.py [preview.png]`"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_brush import GRASS, Glow, blade, outline, put, sheet  # noqa: E402
from art_bush import FH, FW, GROUND, blank, check_icon, clamp  # noqa: E402
from art_flora import blob, finish, ramp  # noqa: E402
from gen_art import ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

MOREL = ramp("2a1410", "5a2a18", "8a4a22", "c07a34", "e8aa58", "ffd68a")
MSTEM = ramp("6a5a40", "a89870", "d8c898", "f4e8c0")
EMBER_PIT, EMBER_HOT = hexc("ff8a38"), hexc("ffd070")
PARA = ramp("3a3468", "6a64a4", "9c96cc", "cdc8ea", "f2f0fc")
PGILL = ramp("2a2650", "4c467c", "7c76b0")
PSTEM = ramp("5a5486", "8a84b8", "bcb6dc", "e6e2f6")
PGLOW = hexc("d8ccff")
SPORE = hexc("9af0e4")

MORELS = [
    {"caps": [(20, 9, 6)], "spread": 6},
    {"caps": [(15, 12, 7), (25, 8, 5)], "spread": 10},
    {"caps": [(11, 8, 5), (18, 13, 7), (26, 9, 6), (31, 6, 4)], "spread": 14},
]
PARASOLS = [
    {"caps": [(20, 22, 15)], "spread": 6},
    {"caps": [(15, 20, 14), (27, 13, 9)], "spread": 10},
    {"caps": [(11, 14, 10), (20, 21, 13), (29, 11, 8)], "spread": 14},
]


def stem_px(px, cx, y0, y1, w, ramp_, rng, seed):
    for y in range(int(y1), int(y0) - 1, -1):
        for dx in range(-int(w), int(w) + 1):
            if abs(dx) > w:
                continue
            lit = 0.6 - 0.55 * dx / max(w, 0.8)
            v = lit * (len(ramp_) - 1) + (noise(int(cx) + dx, y, seed) / 255.0 - 0.5) * 0.7
            put(px, int(round(cx)) + dx, y, ramp_[int(clamp(v, 0, len(ramp_) - 1))])


def morel(px, glow, cx, h, cap_w, rng, seed):
    cap_h = int(h * 0.62)
    stem_top = GROUND - int(h * 0.42)
    stem_px(px, cx, stem_top, GROUND, 1.8 if h > 8 else 1.4, MSTEM, rng, seed)
    cy = stem_top - cap_h * 0.5 + 1
    for y in range(int(cy - cap_h * 0.5) - 1, stem_top + 3):
        t = (y - (cy - cap_h * 0.5)) / max(cap_h, 1)
        half = cap_w * (0.22 + 0.78 * math.sin(min(1.0, max(t, 0.0)) * math.pi * 0.62 + 0.25)) * 0.5 if t >= 0 else 0
        for x in range(int(cx - half) - 1, int(cx + half) + 2):
            dx = (x + 0.5 - cx) / max(half, 1.0)
            if abs(dx) > 1.0 or t < 0 or t > 1.1:
                continue
            lit = 0.55 - 0.5 * dx - 0.25 * (t - 0.3)
            lx = (x + (1 if (y // 3) % 2 else 0)) % 3
            ly = y % 3
            base = lit * 4.2 + 0.6
            if lx == 1 and ly == 1:  # the pit
                put(px, x, y, MOREL[0])
                if noise(x, y, seed + 3) > 150:
                    glow.emit(px, x, y, MOREL[1], EMBER_PIT, 0)
            elif lx == 1 or ly == 1:
                put(px, x, y, MOREL[int(clamp(base - 1.2, 0, 5))])
            else:
                put(px, x, y, MOREL[int(clamp(base + 0.4 + (noise(x, y, seed + 2) / 255.0 - 0.5) * 0.8, 0, 5))])
    glow.emit(px, int(cx), int(cy - cap_h * 0.5), MOREL[4], EMBER_HOT, 1)  # the warm tip of the cap


def make_morel(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(4 + len(spec["caps"])):  # moss and short blades round the feet
        blade(px, 20 + rng.uniform(-spec["spread"], spec["spread"]), GROUND, rng.uniform(1, 4), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2)), seed)
    for cx, h, w in sorted(spec["caps"], key=lambda c: c[1]):
        if picked:
            stem_px(px, cx, GROUND - 3, GROUND, 1.2, MSTEM, rng, seed)
            put(px, cx, GROUND - 4, MSTEM[1])
        else:
            morel(px, glow, cx, h + 10, w + 2, rng, seed + cx)
    return finish(px, spec["spread"], seed), glow.done()


def parasol(px, glow, cx, h, w, rng, seed, lean):
    top = GROUND - h
    # stem with a slight bow and the delicate ring
    for y in range(GROUND, top, -1):
        t = (GROUND - y) / max(h, 1)
        x = cx + lean * math.sin(t * 2.0)
        for dx in (-1, 0, 1):
            if abs(dx) == 1 and (y % 3 == 0 and t > 0.5):
                continue
            put(px, int(round(x)) + dx, y, PSTEM[3 if dx < 0 else (2 if dx == 0 else 1)])
    ry_ = GROUND - int(h * 0.62)
    for dx in range(-3, 4):
        put(px, int(round(cx + lean * 1.2)) + dx, ry_ + (1 if abs(dx) > 1 else 0), PSTEM[3 if dx <= 0 else 2])
    ccx = cx + lean * 2.0
    # the gills under the cap's edge: fine alternating ribs
    for dx in range(-int(w * 0.5), int(w * 0.5) + 1):
        edge = (1.0 - (dx / (w * 0.5)) ** 2) ** 0.5
        y1 = top + int(w * 0.16 * edge) + 1
        for k in range(2):
            put(px, int(ccx) + dx, y1 + k, PGILL[(abs(dx) + k) % 3])
    # the cap: a wide, shallow cone, lit top left, with radial fibres
    for y in range(int(top - w * 0.3), int(top + w * 0.22) + 1):
        for x in range(int(ccx - w * 0.5) - 1, int(ccx + w * 0.5) + 2):
            dx, dy = (x + 0.5 - ccx) / (w * 0.5), (y + 0.5 - top) / (w * 0.26)
            d = dx * dx + dy * dy
            if d > 1.0 or dy > 0.85 - 0.5 * dx * dx:
                continue
            ang = math.atan2(dy, dx)
            fibre = 0.28 if int((ang + math.pi) * 9.0) % 2 == 0 else 0.0
            lit = 0.55 - 0.42 * dx - 0.5 * (dy + 0.4) - fibre * 0.3 + (1.0 - d) * 0.25
            put(px, x, y, PARA[int(clamp(lit * 4.2 + (noise(x, y, seed) / 255.0 - 0.5) * 0.6, 0, 4))])
    put(px, int(ccx), int(top - w * 0.2), hexc("c8a8e0"))  # the soft umbo
    put(px, int(ccx) + 1, int(top - w * 0.2), PARA[1])
    for k in range(4):
        glow.emit(px, int(ccx - w * 0.5 + 1 + k * (w - 2) / 3.0), int(top + 1 + (1 if 0 < k < 3 else 0)), None, PGLOW, 0)  # the rim of light
    glow.emit(px, int(ccx), int(top - w * 0.12), PARA[3], hexc("ffffff"), 1)


def make_parasol(spec, seed, picked=False):
    rng = random.Random(seed)
    px, glow = blank(FW, FH), Glow()
    for _ in range(3 + len(spec["caps"])):
        blade(px, 20 + rng.uniform(-spec["spread"], spec["spread"]), GROUND, rng.uniform(1, 4), rng.uniform(-0.5, 0.5), 0.4, rng.choice((1, 2)), seed)
    for cx, h, w in sorted(spec["caps"], key=lambda c: c[1]):
        if picked:
            stem_px(px, cx, GROUND - 4, GROUND, 1.0, PSTEM, rng, seed)
            put(px, cx - 1, GROUND - 3, PSTEM[3])
            put(px, cx + 1, GROUND - 3, PSTEM[3])
        else:
            parasol(px, glow, cx, h, w, rng, seed + cx, rng.uniform(-1.5, 1.5))
    return finish(px, spec["spread"], seed), glow.done()


def i_morel(px, g):
    for y in range(9, 14):
        for dx in (-1, 0, 1):
            px[y][8 + dx] = MSTEM[3 if dx < 0 else (2 if dx == 0 else 1)]
    for y in range(2, 10):
        t = (y - 2) / 7.0
        half = int(2.6 * (0.4 + 0.6 * math.sin(min(1, t) * 2.0)))
        for dx in range(-half, half + 1):
            lx, ly = (dx + 8 + (1 if (y // 3) % 2 else 0)) % 3, y % 3
            px[y][8 + dx] = MOREL[0] if (lx == 1 and ly == 1) else MOREL[3 if dx < 0 else 2]
    px[3][8] = EMBER_HOT


def i_parasol(px, g):
    for y in range(6, 14):
        px[y][8] = PSTEM[2]
    px[9][7], px[9][9] = PSTEM[3], PSTEM[3]
    for y in range(2, 7):
        half = {2: 2, 3: 4, 4: 5, 5: 6, 6: 6}[y]
        for dx in range(-half, half + 1):
            px[y][8 + dx] = PARA[3 if dx < 0 else (2 if dx == 0 else 1)] if y < 6 else PGILL[(dx + 8) % 3]
    px[3][7], px[2][8] = PARA[4], PARA[4]


def main():
    props, items = ROOT / "props", ROOT / "items"
    sheets = {"ember_morel": [make_morel(s, 1800 + i * 17, picked=r) for r in (False, True) for i, s in enumerate(MORELS)],
              "moon_parasol": [make_parasol(s, 1900 + i * 19, picked=r) for r in (False, True) for i, s in enumerate(PARASOLS)]}
    bad = []
    for name, frames in sheets.items():
        for i, (base, glow) in enumerate(frames):
            for layer in (base, glow):
                pts = [(x, y) for y, row in enumerate(layer) for x, c in enumerate(row) if c[3]]
                if pts and not (min(y for x, y in pts) >= 1 and min(x for x, y in pts) >= 1 and max(x for x, y in pts) <= FW - 2):
                    bad.append("%s frame %d: top %d, x %d..%d" % (name, i, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))
    assert not bad, "cut off at the frame edge:\n" + "\n".join(bad)
    for name, frames in sheets.items():
        write_png(props / (name + ".png"), FW * 3, FH * 2, sheet([f[0] for f in frames], 3, 2))
        write_png(props / (name + "_glow.png"), FW * 3, FH * 2, sheet([f[1] for f in frames], 3, 2))
    for name, draw in (("ember_morel", i_morel), ("moon_parasol", i_parasol)):
        px = blank(16, 16)
        draw(px, None)
        check_icon(name, px)
        write_png(items / (name + ".png"), 16, 16, outline_pass(px, hexc("1b1a2e")))
    print("morel and parasol written")
    if len(sys.argv) > 1:
        from PIL import Image
        img = Image.new("RGBA", (FW * 3, FH * 4), (30, 50, 40, 255))
        for r, (name, frames) in enumerate(sheets.items()):
            for i, (b, g) in enumerate(frames):
                for layer in (b, g):
                    tile = Image.new("RGBA", (FW, FH))
                    tile.putdata([c for row in layer for c in row])
                    img.alpha_composite(tile, ((i % 3) * FW, (r * 2 + i // 3) * FH))
        img.resize((img.width * 4, img.height * 4), Image.NEAREST).save(sys.argv[1])


if __name__ == "__main__":
    main()
