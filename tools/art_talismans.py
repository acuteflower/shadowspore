#!/usr/bin/env python3
"""Icons of the talismans (docs/talisman_konzept.md, 16x16 like every item icon): the Schlichte Silberkette, the Wuchtreif, the Schweigtropfen and the Rissfeder
(the black feather of Mornath, docs/rissfeder.md).
  assets/items/silver_chain.png, wuchtreif.png, schweigtropfen.png, rissfeder.png
Same rules as the other item icons (check_icon): inside the frame with a 1 px margin, one connected piece, ink outline 1b1a2e, lit from the top left,
jewellery hangs upright. Metals: silver (cool), gold (warm, like her hair pin), void steel (blackened, violet rim). Stones: blue (rare), violet (void).
The worn pieces (pendant, ear drops, wrist band) are a later step (rig points); this script only writes the icons.
Run: python3 tools/art_talismans.py [preview.png]   (preview = the three icons 8x on a dark ground)"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png  # noqa: E402

INK = hexc("1b1a2e")
SILVER = [hexc(c) for c in ("6b7392", "93a0bc", "d4dbec", "f6f9ff")]  # dark .. light
GOLD = [hexc(c) for c in ("6a4a2a", "a07a3a", "d8b45a", "f6e0a0")]
VOID = [hexc(c) for c in ("14092e", "261a4a", "35227a", "7d57e0")]
BLUE = [hexc(c) for c in ("2a4a9a", "5aa8ff", "9ad0ff", "e0f2ff")]
VIOLET = [hexc(c) for c in ("3a1f8a", "9a6bff", "c8aaff", "f4ecff")]
RAVEN = [hexc(c) for c in ("14102a", "2c2150", "5a4a9a", "a08cf0")]  # blue-black with a violet sheen (items.json metal "ravensteel", same as TalismanArt.METALS)


def canvas():
    return [[CLEAR] * 16 for _ in range(16)]


def put(px, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        px[y][x] = c


def check_icon(name, px):
    """Inside the frame with a 1 px margin (for the outline) and one connected piece."""
    pts = {(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]}
    xs, ys = [x for x, _ in pts], [y for _, y in pts]
    assert min(xs) >= 1 and max(xs) <= 14 and min(ys) >= 1 and max(ys) <= 14, "%s leaves the frame: x %d..%d y %d..%d" % (name, min(xs), max(xs), min(ys), max(ys))
    seen, stack = set(), [next(iter(pts))]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        stack += [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (p[0] + dx, p[1] + dy) in pts]
    assert len(seen) == len(pts), "%s has %d loose pixels" % (name, len(pts) - len(seen))
    return px


def silver_chain():
    """A fine chain in a hanging bow with a small polished drop."""
    px = canvas()
    last = None
    for x in range(3, 13):
        y = 3.0 + 6.5 * (1.0 - ((x - 7.5) / 4.9) ** 2)
        yi = round(y)
        tone = SILVER[2] if x % 2 == 0 else SILVER[1]
        put(px, x, yi, tone)
        put(px, x, yi + 1, SILVER[0] if x % 2 == 0 else SILVER[1])
        if last is not None:  # no gaps where the bow is steep
            for fill in range(min(last, yi) + 1, max(last, yi)):
                put(px, x if yi > last else x - 1, fill, SILVER[1])
        last = yi
    for (x, y, c) in [(7, 10, 3), (8, 10, 2), (6, 11, 2), (7, 11, 3), (8, 11, 1), (9, 11, 1), (6, 12, 1), (7, 12, 2), (8, 12, 1), (9, 12, 0), (7, 13, 1), (8, 13, 0)]:
        put(px, x, y, SILVER[c])
    return px


def wuchtreif():
    """An open gold bangle seen at three quarters, one faceted blue crystal on top."""
    px = canvas()
    cx, cy = 7.5, 9.0
    for y in range(16):
        for x in range(16):
            dx, dy = (x - cx) / 5.9, (y - cy) / 4.0
            outer = dx * dx + dy * dy
            inner = ((x - cx) / 3.6) ** 2 + ((y - cy) / 1.9) ** 2
            if outer <= 1.0 and inner >= 1.0:
                light = -(dx * 0.7 + dy * 0.7)  # lit from the top left
                put(px, x, y, GOLD[min(3, max(0, int((light + 1.0) * 2.0)))])
    for (x, y, c) in [(7, 3, 3), (6, 4, 2), (7, 4, 3), (8, 4, 2), (6, 5, 1), (7, 5, 2), (8, 5, 1), (7, 6, 0)]:
        put(px, x, y, BLUE[c])
    for x in (5, 9):  # the setting's prongs
        put(px, x, 5, GOLD[3])
    return px


def schweigtropfen():
    """A pair of blackened void-steel hooks on a thread, each with a long violet crystal drop."""
    px = canvas()
    for x, top in ((6, 2), (9, 4)):  # a pair, touching so the icon is one piece, the right one hanging lower
        put(px, x, top + 1, VOID[2])
        put(px, x, top + 2, VOID[3])  # the cap
        rows = [(top + 3, (-1, 0, 1)), (top + 4, (-1, 0, 1)), (top + 5, (-1, 0, 1)), (top + 6, (-1, 0, 1)), (top + 7, (0,)), (top + 8, (0,))]
        for i, (y, offs) in enumerate(rows):
            for o in offs:
                tone = 2 if o < 0 else (1 if o == 0 else 0)
                if i >= 4:
                    tone = 1
                put(px, x + o, y, VIOLET[tone])
        put(px, x - 1, top + 4, VIOLET[3])  # the glint
        put(px, x, top, VOID[2])  # the hook
    return px


def rissfeder():
    """A shallow chain bow and Mornath's black wing feather hanging from it, the spine cracked open by violet light (the pendant of the worn look, drawn larger)."""
    px = canvas()
    last = None
    for x in range(3, 13):
        yi = round(2.0 + 3.0 * (1.0 - ((x - 7.5) / 4.9) ** 2))
        put(px, x, yi, RAVEN[2] if x % 2 == 0 else RAVEN[1])
        if last is not None:  # no gaps where the bow is steep
            for fill in range(min(last, yi) + 1, max(last, yi)):
                put(px, x if yi > last else x - 1, fill, RAVEN[1])
        last = yi
    colours = {"d": RAVEN[0], "m": RAVEN[1], "l": RAVEN[2], "h": RAVEN[3], "s": VIOLET[0], "S": VIOLET[1], "T": VIOLET[2], "W": VIOLET[3]}
    feather = ["..lm..",
               ".dSmd.",
               "dmTlmd",
               "dSWmmd",
               "dmTSld",
               ".dmSmd",
               ".dmTd.",
               "..dm.."]
    for dy, row in enumerate(feather):
        for dx, letter in enumerate(row):
            if letter != ".":
                put(px, 5 + dx, 6 + dy, colours[letter])
    return px


ICONS = {"silver_chain": silver_chain, "wuchtreif": wuchtreif, "schweigtropfen": schweigtropfen, "rissfeder": rissfeder}


def main():
    out = {}
    for name, make in ICONS.items():
        px = outline_pass(check_icon(name, make()), INK)
        write_png(ROOT / "items" / (name + ".png"), 16, 16, px)
        out[name] = px
        print("wrote assets/items/%s.png" % name)
    if len(sys.argv) > 1:
        k = 8
        w = len(out) * 20 * k
        sheet = [[hexc("120d22")] * w for _ in range(20 * k)]
        for i, px in enumerate(out.values()):
            for y in range(16):
                for x in range(16):
                    if px[y][x][3]:
                        for yy in range(k):
                            for xx in range(k):
                                sheet[(2 + y) * k + yy][(2 + x + i * 20) * k + xx] = px[y][x]
        write_png(pathlib.Path(sys.argv[1]), w, 20 * k, sheet)


if __name__ == "__main__":
    main()
