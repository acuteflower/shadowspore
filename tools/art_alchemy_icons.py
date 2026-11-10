#!/usr/bin/env python3
"""Alchemy inventory icons, native 16x16 pixels (stdlib only).

Run: python tools/art_alchemy_icons.py
Uses the existing item paths in data/items.json. Light comes from top left;
All eleven icons share one slender witch-vial silhouette, including the empty
vial. Violet wax, a knotted cord and a hanging charm unite the set; only
liquid, rune light and binding colors change with brew type and tier.
"""
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png
from art_bush import check_icon


GLASS = [hexc(c) for c in ("25213d", "41465d", "69898e", "b9dfd7")]
CORK = [hexc(c) for c in ("493044", "88604f", "c39b70")]
GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
LIQUID = {
    "heal": [hexc(c) for c in ("522a49", "94445f", "d96b86", "ffd0dc")],
    "stamina": [hexc(c) for c in ("573347", "a66738", "eaa84f", "fff0b0")],
}


def bottle(kind, tier=0):
    px = [[CLEAR for _ in range(16)] for _ in range(16)]

    def row(y, left, right, color):
        for x in range(left, right + 1):
            px[y][x] = color

    # One silhouette for every item: narrow neck, long glass body, tapered foot.
    spans = {4: (7, 9), 5: (7, 9), 6: (6, 10),
             **{y: (5, 10) for y in range(7, 13)}, 13: (6, 9)}
    for y, (left, right) in spans.items():
        row(y, left, right, GLASS[0])
        px[y][left] = GLASS[2]
        px[y][right] = GLASS[1]
    row(13, 6, 9, GLASS[1])
    px[7][5] = GLASS[3]
    px[8][5] = GLASS[3]
    px[12][6] = GLASS[2]

    if tier:
        liquid = LIQUID[kind]
        surface = 9 if tier == 1 else 8
        for y in range(surface, 13):
            row(y, 6, 9, liquid[0])
            row(y, 6, 8, liquid[1])
            if tier >= 2:
                px[y][6] = liquid[2]
        row(surface, 6, 9, liquid[1 if tier == 1 else 2])
        if tier == 1:
            row(12, 6, 9, liquid[0])  # settled cloudy brew
        if tier >= 3:
            # Small curling light inside the glass, never a blurred outer aura.
            px[9][7] = liquid[3]
            px[10][8] = liquid[2]
            px[11][7] = liquid[2]
        if tier >= 4:
            px[11][7] = liquid[3]
        if tier == 5:
            px[10][8] = liquid[3]
            px[12][6] = liquid[2]
    else:
        # Recessed violet glass reads as empty, not as a third liquid.
        row(12, 7, 8, GLASS[1])
        px[9][6] = GLASS[1]

    # Uneven wooden stopper dipped in plum wax, like Esma's handmade bottles.
    row(2, 7, 9, CORK[1])
    px[2][7] = CORK[2]
    row(3, 6, 9, hexc("493052"))
    row(3, 6, 7, hexc("88618d"))
    px[4][9] = hexc("68416f")
    # A twisted cord around the neck and a tiny hanging bone/rune charm.
    row(5, 6, 10, GOLD[0])
    px[5][6] = GOLD[1]
    px[5][8] = GOLD[2]
    px[6][10] = GOLD[1]
    px[6][11] = GOLD[0]
    px[7][11] = hexc("bdb3c4")
    px[8][11] = hexc("796886")
    if tier >= 2:
        px[7][11] = hexc("cbaaff")
    if tier >= 3:
        px[7][11] = hexc("e9dcff")
    if tier >= 4:
        row(13, 6, 9, GOLD[0])
        px[13][6] = GOLD[2]
        px[13][7] = GOLD[1]
    if tier == 5:
        px[3][7] = hexc("cbaaff")
        px[4][9] = hexc("9468ee")
        px[8][11] = hexc("cbaaff")

    check_icon("%s_%d" % (kind, tier), px)
    return outline_pass(px, hexc("1b1a2e"))


def main():
    icons = {"vial_empty": bottle("empty")}
    for kind in LIQUID:
        for tier in range(1, 6):
            icons["potion_%s_%d" % (kind, tier)] = bottle(kind, tier)
    for name, px in icons.items():
        write_png(ROOT / "items" / (name + ".png"), 16, 16, px)
    print("Wrote %d alchemy icons (16x16 RGBA)." % len(icons))


if __name__ == "__main__":
    main()
