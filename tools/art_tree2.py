#!/usr/bin/env python3
"""Draws the Schleierweide and the Dämmerblüte with their stumps and young stages, and their items (stdlib only):
  assets/props/willow.png          4 willows (92, 130, 164, 190 px), 4 rows of 112x200 frames, feet (56, 196):
                                   0 trunk, 1 crown (dome and hanging strands), 2 crown glow, 3 trunk glow
  assets/props/willow_growth.png   stump (small), stump (large), sapling, young tree
  assets/props/blossom.png         4 blossom trees (70, 98, 126, 152 px), 6 rows: the same four, then 4 the crown with the
                                   blossoms picked, 5 its glow
  assets/props/blossom_growth.png  stump (small), stump (large), sapling, young tree
  assets/items/willow_wood.png, willow_thread.png, blossom_wood.png, dusk_blossom.png   icons 16x16
The glow rows hold only the emissive parts (the game draws them unshaded, bright at night). Sources: art_willow.py,
art_blossom.py (shared parts in art_spruce.py)."""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_blossom  # noqa: E402
import art_tree  # noqa: E402
import art_willow  # noqa: E402
from art_bush import bezier, blank, check_icon, stroke  # noqa: E402
from art_spruce import CH, CW  # noqa: E402
from art_stone import TEAL, TEAL_L, VIO  # noqa: E402
from art_tree import to_pixels  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png  # noqa: E402

ICON_OUT = hexc("1b1a2e")
WILLOW_BARK = [hexc(c) for c in ("2a2a3a", "4a4a58", "7a7a88", "b0b4bc", "dcdee4")]  # pale grey-lilac bark
WILLOW_CUT = [hexc(c) for c in ("5a6a60", "8aa090", "b8ccb4", "e0ecd8")]
BLOSSOM_BARK = [hexc(c) for c in ("2a1624", "4a2a38", "6e4452", "9a6a76", "c49a9a")]
BLOSSOM_CUT = [hexc(c) for c in ("7a4a48", "b08068", "d8aa88", "f4d4b0")]
STRAND = art_willow.STRAND


def sheet(rows):
    """rows: lists of 4 frames (CH rows of CW pixels each) -> one image, 4 columns."""
    out = [[CLEAR] * (CW * 4) for _ in range(CH * len(rows))]
    for r, frames in enumerate(rows):
        for i, f in enumerate(frames):
            for y in range(CH):
                out[r * CH + y][i * CW:(i + 1) * CW] = f[y]
    return out


def merged(layers):
    t, c = layers
    return [[c[y][x] if c[y][x][3] else t[y][x] for x in range(CW)] for y in range(CH)]


def growth(make, small, young, seeds):
    frames = []
    for radius in (5.0, 9.0):
        frames.append(art_tree.stump(radius, 3)[0])
    for spec, seed in ((small, seeds[0]), (young, seeds[1])):
        parts = make(spec, seed, extras=False)
        w = spec.get("dome_w", spec.get("w", 30))
        frames.append(merged(art_tree.finish(parts["trunk"], parts["crown"], w / 2 + 2)))
    return sheet([frames])


def icon_log(bark, cut):
    """A short log lying diagonally: bark side and a cut end with rings."""
    px = blank(16, 16)
    stroke(px, bezier((4.8, 11.6), (7.6, 8.6), (10.4, 5.4), n=24), 3.0, 3.0, bark[1:])
    for t in range(0, 24, 3):
        px[int(10.8 - t * 0.24)][int(5.5 + t * 0.24)] = bark[0]
    stroke(px, [(11.2, 4.6)], 3.0, 3.0, cut[1:])
    stroke(px, [(11.2, 4.6)], 1.5, 1.5, [cut[2], cut[2], cut[3]])
    px[4][11] = cut[0]
    check_icon("log", px)
    return outline_pass(px, ICON_OUT)


def icon_thread():
    """A hank of luminous willow strands tied with a violet knot, the ends glowing teal."""
    px = blank(16, 16)
    for k, (a, b, c) in enumerate((((3.0, 2.5), (4.0, 8.0), (3.4, 13.4)), ((5.0, 2.0), (6.4, 8.2), (6.2, 13.8)), ((7.4, 2.0), (8.4, 8.0), (9.0, 13.6)), ((9.6, 2.4), (10.4, 8.4), (11.6, 13.2)), ((11.6, 2.8), (12.2, 8.0), (12.8, 12.6)))):
        stroke(px, bezier(a, b, c, n=20), 0.8, 0.7, [STRAND[1 + (k % 2)], STRAND[2], STRAND[3]])
    for x in range(3, 14):  # the knot
        px[6][x] = hexc("4a2c8a") if x % 2 else hexc("7048d0")
        px[7][x] = hexc("2a1a5a")
    for x, y in ((3, 13), (6, 13), (9, 13), (11, 12), (12, 12)):
        px[y][x] = TEAL_L if x % 2 else TEAL
    check_icon("willow_thread", px)
    return outline_pass(px, ICON_OUT)


def icon_blossom():
    """A dusk blossom: five petals around a warm heart, a short stem with a leaf."""
    px = blank(16, 16)
    stroke(px, bezier((8.0, 10.0), (8.4, 12.2), (7.6, 14.2), n=10), 0.7, 0.7, [art_willow.LEAF[2], art_willow.LEAF[3]])
    stroke(px, bezier((8.0, 12.6), (10.0, 12.0), (11.6, 12.8), n=10), 1.0, 0.5, art_willow.LEAF[3:])
    for k in range(5):
        a = -math.pi / 2 + k * math.tau / 5
        stroke(px, [(8.0 + math.cos(a) * 3.0, 6.4 + math.sin(a) * 3.0)], 2.6, 2.6, art_blossom.BLOOM[1:])
    stroke(px, [(8.0, 6.4)], 1.5, 1.5, [hexc("ffc060"), hexc("ffe8a0"), hexc("fff6d0")])
    check_icon("dusk_blossom", px)
    return outline_pass(px, ICON_OUT)


def main():
    props, items = ROOT / "props", ROOT / "items"
    willows = [art_willow.willow(s, 11 + i * 9) for i, s in enumerate(art_willow.VARIANTS)]
    lit = [art_tree.finish(p["trunk"], p["crown"], s["dome_w"] / 2.2) for p, s in zip(willows, art_willow.VARIANTS)]
    write_png(props / "willow.png", CW * 4, CH * 4, sheet([[t for t, c in lit], [c for t, c in lit], [to_pixels(p["glow_crown"]) for p in willows], [to_pixels(p["glow_trunk"]) for p in willows]]))
    write_png(props / "willow_growth.png", CW * 4, CH, growth(art_willow.willow, art_willow.SAPLING, art_willow.YOUNG, (70, 71)))
    blooms = [art_blossom.blossom(s, 21 + i * 7) for i, s in enumerate(art_blossom.VARIANTS)]
    picked = [art_blossom.blossom(s, 21 + i * 7, picked=True) for i, s in enumerate(art_blossom.VARIANTS)]
    lit = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(blooms, art_blossom.VARIANTS)]
    lit_picked = [art_tree.finish(p["trunk"], p["crown"], s["w"] / 2.2) for p, s in zip(picked, art_blossom.VARIANTS)]
    write_png(props / "blossom.png", CW * 4, CH * 6, sheet([[t for t, c in lit], [c for t, c in lit], [to_pixels(p["glow_crown"]) for p in blooms], [to_pixels(p["glow_trunk"]) for p in blooms], [c for t, c in lit_picked], [to_pixels(p["glow_crown"]) for p in picked]]))
    write_png(props / "blossom_growth.png", CW * 4, CH, growth(art_blossom.blossom, art_blossom.SAPLING, art_blossom.YOUNG, (80, 81)))
    for name, px in (("willow_wood", icon_log(WILLOW_BARK, WILLOW_CUT)), ("willow_thread", icon_thread()), ("blossom_wood", icon_log(BLOSSOM_BARK, BLOSSOM_CUT)), ("dusk_blossom", icon_blossom())):
        write_png(items / f"{name}.png", 16, 16, px)
    print("willow, blossom tree, their growth stages and items written")


if __name__ == "__main__":
    main()
