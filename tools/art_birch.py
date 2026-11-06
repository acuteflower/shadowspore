#!/usr/bin/env python3
"""The Mondbirke (moon birch), stdlib only: a slender white tree of the open meadow and its edges, the gentle counterpart of the
dark firs. Pale, violet-tinged bark with dark lenticels and black chevron scars where limbs once grew, a rough dark foot, limbs that
arch up and out, and from them long, fine twigs that hang down in soft tufts of small leaves, so the crown is airy and swings in the
wind. At night the tips of some leaves glow like little lanterns and the old trees' scars glow violet. Leaves come in three
palettes (fresh green, autumn gold, silver teal); the six variants differ in size, lean, twin trunks and age.

  assets/props/birch.png          6 trees (88 .. 194 px), 6 rows of 112x200 frames, feet (56, 196):
                                  0 trunk, 1 crown, 2 crown glow, 3 trunk glow, 4 crown with the leaves picked, 5 its glow
  assets/props/birch_growth.png   stump (small), stump (large), sapling, young birch (padded to 6 columns)
  assets/items/birch_wood.png, birch_bark.png, birch_leaf.png   icons 16x16
`python3 tools/art_birch.py [preview.png]` (preview needs Pillow)"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_spruce as sp  # noqa: E402
import art_tree  # noqa: E402
from art_bush import bezier, blank, check_icon, stroke  # noqa: E402
from art_spruce import BARK, CH, CW, FEET_X, FEET_Y, RIM, SHELF, TEAL, TEAL_L, VIO, VIO_L, Emitters, grid, put  # noqa: E402
from art_tree import to_pixels  # noqa: E402
from art_willow import lobes_shade  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402

BIRCH = [hexc(c) for c in ("2a2438", "5a5472", "9a96b6", "d2d0e4", "f2f0fa")]  # violet-white bark, shade .. lit
PALETTES = [
    [hexc(c) for c in ("0e1c36", "16383e", "28644e", "4a9858", "88c868", "c8f29c")],  # fresh green
    [hexc(c) for c in ("241634", "46263e", "8a5436", "c88a34", "f0c458", "fff2a8")],  # autumn gold
    [hexc(c) for c in ("0e1a34", "183c4c", "2a6a70", "58a2a2", "96d2c2", "d6f6ea")],  # silver teal
]
GLOWS = [hexc("d8ff90"), hexc("ffe27a"), hexc("bff4ff")]
SEEDS = [hexc("f0e6b0"), hexc("ffe9a0"), hexc("e6f6ff")]

# height; clear: the crown's lowest edge; hw: trunk half width; crown_w/h; limbs; twigs per limb; twig length range; pal: palette;
# lean: the trunk's sway in px; twin: two stems; scars: glowing violet chevrons; hollow, fungi; glow: lit leaf tips; w: ground shadow
VARIANTS = [
    dict(height=88, clear=30, hw=2.6, crown_w=44, crown_h=52, limbs=4, twigs=6, tw=(8, 15), pal=0, lean=1.5, twin=False, scars=0, hollow=False, fungi=0, glow=9, w=36),
    dict(height=116, clear=42, hw=3.4, crown_w=62, crown_h=64, limbs=5, twigs=8, tw=(10, 19), pal=0, lean=2.5, twin=False, scars=0, hollow=False, fungi=0, glow=14, w=48),
    dict(height=134, clear=46, hw=3.8, crown_w=72, crown_h=76, limbs=6, twigs=9, tw=(10, 21), pal=1, lean=-3.0, twin=False, scars=0, hollow=False, fungi=0, glow=18, w=54),
    dict(height=158, clear=56, hw=3.2, crown_w=90, crown_h=84, limbs=7, twigs=9, tw=(11, 23), pal=2, lean=1.0, twin=True, scars=1, hollow=False, fungi=1, glow=22, w=70),
    dict(height=178, clear=64, hw=5.0, crown_w=98, crown_h=94, limbs=8, twigs=10, tw=(12, 25), pal=1, lean=5.0, twin=False, scars=2, hollow=False, fungi=2, glow=26, w=76),
    dict(height=194, clear=70, hw=6.8, crown_w=106, crown_h=102, limbs=9, twigs=11, tw=(12, 27), pal=2, lean=-4.0, twin=False, scars=3, hollow=True, fungi=3, glow=32, w=84),
]
SAPLING = dict(height=40, clear=14, hw=1.2, crown_w=18, crown_h=20, limbs=2, twigs=3, tw=(4, 8), pal=0, lean=0.5, twin=False, scars=0, hollow=False, fungi=0, glow=0, w=14)
YOUNG = dict(height=84, clear=28, hw=2.4, crown_w=38, crown_h=46, limbs=4, twigs=5, tw=(7, 13), pal=0, lean=1.0, twin=False, scars=0, hollow=False, fungi=0, glow=3, w=32)


def birch(spec, seed, picked=False, extras=True):
    rng = random.Random(seed)
    lrng = random.Random(seed + 11)  # which leaves are picked: its own stream, so the whole and the picked crown share every twig
    trunk, crown, glow_c, glow_t = grid(), grid(), grid(), grid()
    lights_c, lights_t = Emitters(glow_c), Emitters(glow_t)
    pal = PALETTES[spec["pal"]]
    height, clear, hw = spec["height"], spec["clear"], spec["hw"]
    cw, chh = spec["crown_w"], spec["crown_h"]
    top_y = FEET_Y - height
    cy = top_y + chh * 0.5
    stems = [(-1, 0.0), (1, 0.0)] if spec["twin"] else [(0, 0.0)]

    # ---- the trunk(s)
    leader_top = top_y + chh * 0.25
    stem_pts = []
    for si, (sd, _x) in enumerate(stems):
        pts = []
        phase = rng.uniform(0, 6.0)
        for y in range(int(leader_top), FEET_Y + 1):
            t = (FEET_Y - y) / max(FEET_Y - leader_top, 1)
            x = FEET_X + spec["lean"] * math.sin(t * 2.2) * (1 if not spec["twin"] else 0.6) + math.sin(t * 5.0 + phase) * 0.8
            if spec["twin"]:
                x += sd * (2.0 + 9.0 * t ** 0.8 * (1.0 if y < FEET_Y - 8 else 0.3))
            pts.append((y, x, hw * (1.0 - 0.6 * t ** 1.1) + max(0.0, (y - (FEET_Y - 8)) * 0.5)))
        stem_pts.append(pts)
        for y, x, w in pts:
            for dx in range(-int(w) - 1, int(w) + 2):
                if abs(dx) > w:
                    continue
                lit = 0.55 - 0.5 * dx / max(w, 1.0)
                v = lit * 4.2 + (noise(int(x) + dx, y, seed + 2) / 255.0 - 0.5) * 0.8
                put(trunk, int(round(x)) + dx, y, BIRCH[int(max(1, min(4, v)))])
        for y, x, w in pts:  # dark lenticels: short horizontal dashes
            if y < FEET_Y - 12 and noise(y // 2, si, seed + 3) > 215:
                ln = 1 + int(noise(y, 5, seed + 4) % max(2, int(w * 1.3)))
                off = int(noise(y, 7, seed + 5) % max(1, int(w))) - int(w / 2)
                for dx in range(ln):
                    put(trunk, int(round(x)) + off + dx, y, BIRCH[1 if dx % 2 else 0])
        for y, x, w in pts:  # the dark, rough foot of the old bark
            foot = 13 + int(noise(int(x) // 2, 3, seed + 6) % 5)
            if y > FEET_Y - foot:
                for dx in range(-int(w) - 1, int(w) + 2):
                    if abs(dx) <= w and noise(int(x) + dx, y, seed + 7) > 70:
                        lit = 0.5 - 0.5 * dx / max(w, 1.0)
                        put(trunk, int(round(x)) + dx, y, BARK[int(max(0, min(3, lit * 3.0 + (noise(int(x) + dx, y, seed + 8) / 255.0 - 0.6))))])
    ground = {y: (x, w) for pts in stem_pts[:1] for y, x, w in pts}

    # ---- limbs: arch up and out from the trunk, drooping at the end; twigs hang from them
    limbs = []
    n = spec["limbs"]
    for i in range(n):
        side = -1 if i % 2 == 0 else 1
        t0 = 0.45 + 0.55 * (i / max(n - 1, 1))  # height of the fork on the trunk, 0 foot .. 1 top
        yb = int(FEET_Y - t0 * (FEET_Y - leader_top))
        yb = max(yb, int(leader_top) + 2)
        bx = ground.get(yb, (FEET_X, hw))[0]
        if spec["twin"]:
            bx = stem_pts[i % 2][max(0, min(len(stem_pts[0]) - 1, yb - int(leader_top)))][1]
        reach = cw * 0.5 * (0.45 + 0.55 * (1.0 - t0 * 0.55)) * rng.uniform(0.8, 1.0)
        central = i % 3 == 2  # every third limb stays close to the trunk and climbs: no hole in the middle of the crown
        if central:
            reach *= 0.3
        up = (yb - top_y) * rng.uniform(0.25, 0.5) * (2.2 if central else 1.0)
        tip = (bx + side * reach, yb - up * 0.3 + (reach * 0.1))
        ctrl = (bx + side * reach * 0.35, yb - up)
        pts = bezier((bx, yb), ctrl, tip, n=32)
        limbs.append((side, pts))
        for k, (x, y) in enumerate(pts):
            if k < 26:
                put(trunk if False else crown, int(round(x)), int(round(y)), BIRCH[2 if side < 0 else 1])
                if k < 10:
                    put(crown, int(round(x)) + 1, int(round(y)), BIRCH[1])
        if extras:  # the black chevron scar where the limb leaves the trunk
            for d in range(3):
                put(trunk, int(bx) + side * (d + 1), yb + 1 + d // 2, BIRCH[0])
                put(trunk, int(bx) + side * (d + 1), yb + 2 + d // 2, BIRCH[1])

    # ---- the airy volume of the crown: a few shaded clumps at the limb tips and between
    lobes = []
    for side, pts in limbs:
        for k in range(14, len(pts), 5):
            r = rng.uniform(3.4, 6.0) * (0.75 + 0.25 * cw / 100.0)
            lobes.append((pts[k][0] + rng.uniform(-3, 3), pts[k][1] + rng.uniform(0, 5), r, r * 0.85, 0.0))
    for _ in range(int(cw / 12)):  # leaves round the leader, so the trunk does not poke out of an empty middle
        lobes.append((FEET_X + spec['lean'] * 0.6 + rng.uniform(-cw * 0.18, cw * 0.18), top_y + chh * rng.uniform(0.32, 0.6), rng.uniform(3.4, 5.5), rng.uniform(3.0, 4.8), 0.0))
    shaded = grid()
    lobes_shade(shaded, lobes, pal, seed + 1, -0.35)
    for y in range(CH):
        for x in range(CW):
            if shaded[y][x] is not None:
                crown[y][x] = shaded[y][x]

    # ---- hanging twigs with leaves
    tips = []
    for side, pts in limbs:
        for _ in range(spec["twigs"]):
            k = int(rng.uniform(0.28, 1.0) * (len(pts) - 1))
            x, y = pts[k]
            length = int(rng.uniform(*spec["tw"]) * (0.7 + 0.5 * (k / len(pts))))
            vx, vy = rng.uniform(-0.5, 0.5) + side * 0.25, rng.uniform(0.3, 0.9)
            xs, ys = x, y
            for i in range(length):
                xi, yi = int(round(xs)), int(round(ys))
                if i > 0:
                    put(crown, xi, yi, BIRCH[1 if i < length * 0.6 else 2])
                if i > 1 and i % 2 == 0:  # a pair of small leaves
                    keep = not (picked and lrng.random() < 0.5)
                    for s2 in (-1, 1):
                        if keep and 4 <= xi + s2 * 2 < CW - 4:
                            tone = int(max(1, min(5, 3 + (1 if (xi + s2 < FEET_X) else 0) + (1 if (yi < cy) else -1 if yi > cy + chh * 0.3 else 0) + rng.choice((-1, 0, 0, 1)))))
                            put(crown, xi + s2, yi, pal[tone])
                            put(crown, xi + s2 * 2, yi + 1, pal[max(1, tone - 1)])
                xs += vx
                ys += vy
                vy += 0.09
                vx *= 0.96
            tips.append((int(round(xs)), int(round(ys))))
            if not (picked and lrng.random() < 0.5):  # a tuft at the end
                for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (1, 1), (-1, 1), (0, 2)):
                    put(crown, int(round(xs)) + dx, int(round(ys)) + dy, pal[int(max(1, min(5, 3 + (1 if dx <= 0 else 0) + rng.choice((0, 1)))))])
    for y in range(1, CH):  # lit contour on top and left, cool light on the right
        for x in range(1, CW - 1):
            c = crown[y][x]
            if c is None or c not in pal:
                continue
            k = pal.index(c)
            if crown[y - 1][x] is None and k < 5:
                crown[y][x] = pal[min(k + 2, 5)]
            elif crown[y][x - 1] is None and k < 5:
                crown[y][x] = pal[k + 1]
            elif crown[y][x + 1] is None and noise(x, y, seed + 9) > 100 and 1 <= k <= 3:
                crown[y][x] = RIM[int(noise(x, y, seed + 10) > 150)]

    # ---- the magic: lantern leaves at twig tips and hanging seed glints; violet scars and a hollow on the old ones
    if extras:
        glow_color, seed_color = GLOWS[spec["pal"]], SEEDS[spec["pal"]]
        want = max(0, spec["glow"] - (spec["glow"] // 2 if picked else 0))
        for j in range(want):
            x, y = tips[(j * 7 + 3) % len(tips)] if tips else (FEET_X, int(cy))
            lights_c.pixel(crown, x, y + 1, pal[5], glow_color, 2 if j % 4 == 0 else 1)
        for j in range(spec["glow"] // 4):
            x, y = tips[(j * 11 + 1) % len(tips)] if tips else (FEET_X, int(cy))
            for k in range(3):
                put(crown, x + 1, y + 3 + k, BIRCH[2])
            lights_c.pixel(crown, x + 1, y + 6, seed_color, seed_color, 1)
        base_x = ground.get(FEET_Y - 20, (FEET_X, hw))
        for sc in range(spec["scars"]):
            y = FEET_Y - int(clear * rng.uniform(0.25, 0.8))
            if y in ground:
                cx, w = ground[y]
                for d in range(4):
                    lights_t.pixel(trunk, int(cx) - int(w) + 1 + d, y + d // 2, VIO if d % 2 else BIRCH[0], VIO_L if d % 2 else VIO, 1)
                    lights_t.pixel(trunk, int(cx) + int(w) - 1 - d, y + d // 2 + 4, VIO if d % 2 else BIRCH[0], VIO_L if d % 2 else VIO, 1)
        for f in range(spec["fungi"]):
            y = FEET_Y - int(clear * rng.uniform(0.15, 0.75))
            if y in ground:
                cx, w = ground[y]
                side = -1 if f % 2 else 1
                for i in range(4):
                    x = int(cx) + side * (int(w) + i)
                    yy = y + (1 if i > 1 else 0)
                    put(trunk, x, yy, SHELF[1])
                    put(trunk, x, yy + 1, SHELF[0])
                    lights_t.pixel(trunk, x, yy - (1 if 0 < i < 3 else 0), SHELF[2], TEAL_L, 1)
        if spec["hollow"]:
            y = FEET_Y - int(clear * 0.4)
            cx, w = ground[y]
            for dy in range(-4, 5):
                for dx in range(-2, 3):
                    d = (dx / 2.4) ** 2 + (dy / 4.0) ** 2
                    if d <= 1.0:
                        put(trunk, int(cx) + dx - 1, y + dy, BIRCH[0] if d < 0.6 else BIRCH[1])
            lights_t.pixel(trunk, int(cx) - 1, y, TEAL, TEAL_L, 2)
        del base_x
    lights_c.halos()
    lights_t.halos()
    return {"trunk": trunk, "crown": crown, "glow_crown": glow_c, "glow_trunk": glow_t}


# ------------------------------------------------------------------ items
def icon_wood():
    """A short pale log, the cut end with fine rings and the white bark with dark dashes."""
    px = blank(16, 16)
    stroke(px, bezier((4.8, 11.6), (7.6, 8.6), (10.4, 5.4), n=24), 3.0, 3.0, BIRCH[1:])
    for t in range(0, 24, 4):
        px[int(11.0 - t * 0.24)][int(5.2 + t * 0.24)] = BIRCH[0]
    cut = [hexc("a88a5a"), hexc("d8b87a"), hexc("f0d8a0"), hexc("fff0c8")]
    stroke(px, [(11.2, 4.6)], 3.0, 3.0, cut[:3])
    stroke(px, [(11.2, 4.6)], 1.5, 1.5, [cut[1], cut[2], cut[3]])
    check_icon("birch_wood", px)
    return outline_pass(px, hexc("1b1a2e"))


def icon_bark():
    """A curl of white birch bark, rolled at one end, with dark dashes."""
    px = blank(16, 16)
    stroke(px, bezier((3.0, 12.0), (6.0, 3.0), (13.0, 5.0), n=24), 2.2, 2.2, BIRCH[1:])
    stroke(px, bezier((4.0, 12.5), (7.0, 4.5), (12.0, 6.5), n=24), 1.0, 1.0, [BIRCH[3], BIRCH[4]])
    for x, y in ((6, 7), (8, 6), (10, 7), (7, 9)):
        px[y][x] = BIRCH[0]
    stroke(px, [(12.5, 6.5)], 1.6, 1.6, [BIRCH[2], BIRCH[3]])
    check_icon("birch_bark", px)
    return outline_pass(px, hexc("1b1a2e"))


def icon_leaf():
    """Three small serrated birch leaves on a twig, golden-green."""
    px = blank(16, 16)
    pal = PALETTES[1]
    pts = bezier((3.0, 13.0), (6.0, 9.0), (11.0, 3.0), n=20)
    stroke(px, pts, 0.7, 0.7, BIRCH[1:3])
    for k, off in ((7, -2), (12, 2), (17, -2)):
        cx, cy = int(round(pts[k][0])) + off, int(round(pts[k][1]))
        for dx, dy, t in ((0, 0, 4), (1, 0, 3), (-1, 0, 4), (0, 1, 3), (0, -1, 5), (1, 1, 2), (-1, 1, 3)):
            px[cy + dy][cx + dx] = pal[t]
        px[cy][cx] = pal[5]
        px[cy][cx - off // 2] = pal[3]
    check_icon("birch_leaf", px)
    return outline_pass(px, hexc("1b1a2e"))


# ------------------------------------------------------------------ main
def sheet_n(rows, cols):
    out = [[CLEAR] * (CW * cols) for _ in range(CH * len(rows))]
    for r, frames in enumerate(rows):
        for i, f in enumerate(frames):
            for y in range(CH):
                out[r * CH + y][i * CW:(i + 1) * CW] = f[y]
    return out


def merged(layers):
    t, c = layers
    return [[c[y][x] if c[y][x][3] else t[y][x] for x in range(CW)] for y in range(CH)]


def main():
    props, items = ROOT / "props", ROOT / "items"
    n = len(VARIANTS)
    whole = [birch(s, 41 + i * 13) for i, s in enumerate(VARIANTS)]
    picked = [birch(s, 41 + i * 13, picked=True) for i, s in enumerate(VARIANTS)]
    lit = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(whole, VARIANTS)]
    lit_picked = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(picked, VARIANTS)]
    bad = []
    for i, (t, c) in enumerate(lit):  # nothing may touch the frame's edge: it would be cut off
        for name, layer in (("trunk", t), ("crown", c)):
            pts = [(x, y) for y, row in enumerate(layer) for x, px in enumerate(row) if px[3]]
            if pts and (min(y for x, y in pts) < 1 or min(x for x, y in pts) < 1 or max(x for x, y in pts) > CW - 2):
                bad.append("variant %d %s: top %d, x %d..%d" % (i, name, min(y for x, y in pts), min(x for x, y in pts), max(x for x, y in pts)))
    assert not bad, "cut off at the frame edge:\n" + "\n".join(bad)
    write_png(props / "birch.png", CW * n, CH * 6, sheet_n([[t for t, c in lit], [c for t, c in lit], [to_pixels(p["glow_crown"]) for p in whole], [to_pixels(p["glow_trunk"]) for p in whole], [c for t, c in lit_picked], [to_pixels(p["glow_crown"]) for p in picked]], n))
    growth = [art_tree.stump(r, 3)[0] for r in (4.0, 7.0)]
    for spec, seed in ((SAPLING, 70), (YOUNG, 71)):
        parts = birch(spec, seed, extras=False)
        growth.append(merged(art_tree.finish(parts["trunk"], parts["crown"], spec["w"] / 2.0 + 2)))
    growth += [[[CLEAR] * CW for _ in range(CH)]] * (n - 4)
    write_png(props / "birch_growth.png", CW * n, CH, sheet_n([growth], n))
    for name, px in (("birch_wood", icon_wood()), ("birch_bark", icon_bark()), ("birch_leaf", icon_leaf())):
        write_png(items / f"{name}.png", 16, 16, px)
    print("moon birch, its growth stages and items written")
    if len(sys.argv) > 1:
        from PIL import Image  # preview only
        img = Image.new("RGBA", (CW * n, CH), (30, 50, 40, 255))
        for i, (t, c) in enumerate(lit):
            for layer in (t, c, to_pixels(whole[i]["glow_crown"])):
                tile = Image.new("RGBA", (CW, CH))
                tile.putdata([px for row in layer for px in row])
                img.alpha_composite(tile, (i * CW, 0))
        img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(sys.argv[1])


if __name__ == "__main__":
    main()
