#!/usr/bin/env python3
"""16x16 pixel-art item icons for Caelia's Star Hall gifts and milestone relics.
Follows tools/art_talismans.py & docs/design_guide.md (1 px #1b1a2e outline,
top-left lighting, single connected silhouette with >=1 px margin inside 16x16).
Writes:
  assets/items/stardust_elixir.png
  assets/items/astral_star_fruit.png
  assets/items/morningstar_pendant.png
  assets/items/crescent_earrings.png
  assets/items/caelia_sigil.png
Run: py -3 tools/art_star_gifts.py [preview.png]
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png  # noqa: E402

INK = hexc("1b1a2e")
GOLD = [hexc(c) for c in ("6a4a2a", "a07a3a", "d8b45a", "f6e0a0")]
TEAL = [hexc(c) for c in ("1f5f68", "2f9da6", "78f4e6", "d8fff9")]
GLASS = [hexc(c) for c in ("3b486c", "6a7ea6", "a9bede", "eef6ff")]
VIOLET = [hexc(c) for c in ("34185e", "6636ad", "9468ee", "cbaaff")]
SILVER = [hexc(c) for c in ("6b7392", "93a0bc", "d4dbec", "f6f9ff")]


def canvas():
    return [[CLEAR] * 16 for _ in range(16)]


def put(px, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        px[y][x] = c


def check_icon(name, px):
    pts = {(x, y) for y, row in enumerate(px) for x, c in enumerate(row) if c[3]}
    xs, ys = [x for x, _ in pts], [y for _, y in pts]
    assert min(xs) >= 1 and max(xs) <= 14 and min(ys) >= 1 and max(ys) <= 14, (
        "%s leaves the frame: x %d..%d y %d..%d" % (name, min(xs), max(xs), min(ys), max(ys))
    )
    seen, stack = set(), [next(iter(pts))]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        stack += [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (p[0] + dx, p[1] + dy) in pts]
    assert len(seen) == len(pts), "%s has %d loose pixels" % (name, len(pts) - len(seen))
    return px


def stardust_elixir():
    """Faceted starlight phial: cork/gold collar + round-bottomed crystal flask filled with glowing teal-gold stardust."""
    px = canvas()
    # Gold stopper & neck
    for x, y, c in [(7, 2, 3), (8, 2, 2), (6, 3, 2), (7, 3, 3), (8, 3, 2), (9, 3, 1), (7, 4, 2), (8, 4, 1)]:
        put(px, x, y, GOLD[c])
    # Glass shoulder
    for y, x0, x1 in [(5, 5, 10), (6, 4, 11)]:
        for x in range(x0, x1 + 1):
            t = 3 if x <= 6 else (2 if x <= 8 else 1)
            put(px, x, y, GLASS[t])
    # Luminous liquid body with starlight core & golden flecks
    rows = [(7, 4, 11), (8, 4, 11), (9, 4, 11), (10, 4, 11), (11, 5, 10), (12, 5, 10), (13, 6, 9)]
    for y, x0, x1 in rows:
        for x in range(x0, x1 + 1):
            is_rim = x == x0 or x == x1 or y == 13
            if is_rim:
                put(px, x, y, GLASS[2 if x < 8 else 0])
            else:
                d = math.hypot(x - 7.3, y - 9.4)
                if d < 1.3:
                    put(px, x, y, TEAL[3])
                elif d < 2.5:
                    put(px, x, y, TEAL[2] if x <= 7 else TEAL[1])
                else:
                    put(px, x, y, TEAL[1] if y < 11 else TEAL[0])
    # Top-left specular glint + golden stardust specs
    put(px, 5, 7, GLASS[3])
    put(px, 5, 8, GLASS[3])
    put(px, 9, 9, GOLD[3])
    put(px, 6, 11, GOLD[3])
    return px


def astral_star_fruit():
    """Five-pointed astral star-fruit glowing in celestial teal and sunlit gold, with a tiny golden stem."""
    px = canvas()
    cx, cy = 7.5, 8.2
    # Golden stem at top so silhouette is a crisp celestial fruit
    for x, y, c in [(7, 2, 3), (8, 2, 1), (7, 3, 2), (8, 3, 1)]:
        put(px, x, y, GOLD[c])
    for y in range(3, 15):
        for x in range(2, 14):
            dx, dy = x - cx, y - cy
            ang = math.atan2(dy, dx) + math.pi * 0.5
            r = math.hypot(dx, dy)
            star_r = 4.6 + 1.55 * math.cos(5.0 * ang)
            if r <= star_r:
                nw = dx + dy
                if r < 1.8:
                    put(px, x, y, GOLD[3])
                elif r < 3.0:
                    put(px, x, y, TEAL[3] if nw < 0 else TEAL[2])
                else:
                    put(px, x, y, TEAL[2] if nw < -1.0 else (TEAL[1] if nw < 2.0 else TEAL[0]))
    # Top-left ridge highlight
    put(px, 6, 5, TEAL[3])
    put(px, 5, 7, TEAL[3])
    return px


def morningstar_pendant():
    """Gold chain arc holding an eight-pointed morningstar brooch with a glowing turquoise star core."""
    px = canvas()
    # Gold chain bow (connected cleanly to pendant top)
    last = None
    for x in range(3, 13):
        y = 2.0 + 4.8 * (1.0 - ((x - 7.5) / 5.0) ** 2)
        yi = round(y)
        put(px, x, yi, GOLD[2 if x % 2 == 0 else 1])
        if last is not None:
            for fill in range(min(last, yi) + 1, max(last, yi)):
                put(px, x if yi > last else x - 1, fill, GOLD[1])
        last = yi
    # Star-shaped pendant frame + teal gemstone core
    for y in range(6, 15):
        for x in range(4, 12):
            dx, dy = abs(x - 7.5), abs(y - 10.0)
            if dx <= 0.6 and dy <= 4.1 or dy <= 0.6 and dx <= 3.6 or (dx + dy <= 3.1):
                if dx <= 1.5 and dy <= 1.5:
                    put(px, x, y, TEAL[3 if (x <= 7 and y <= 10) else 2])
                else:
                    put(px, x, y, GOLD[3 if (x <= 7 and y <= 10) else (2 if x <= 8 else 1)])
    return px


def crescent_earrings():
    """Pair of slender golden crescent drops with luminous teal star-pearls below."""
    px = canvas()
    for cx, top_y in ((5, 2), (10, 4)):
        # Hook
        put(px, cx, top_y, GOLD[3])
        put(px, cx, top_y + 1, GOLD[2])
        # Crescent arch
        for dy, xs in [(2, (-1, 0, 1)), (3, (-2, 2)), (4, (-2, -1, 1, 2)), (5, (-1, 0, 1))]:
            for ox in xs:
                put(px, cx + ox, top_y + dy, GOLD[3 if ox < 0 else (2 if ox == 0 else 1)])
        # Radiant teal drop pearl inside/under the crescent
        put(px, cx, top_y + 3, TEAL[3])
        put(px, cx, top_y + 6, TEAL[2])
        put(px, cx, top_y + 7, TEAL[1])
    # Single-pixel silver-gold filigree link between the pair so the 16x16 item silhouette stays connected
    put(px, 7, 5, GOLD[1])
    put(px, 8, 5, GOLD[2])
    return px


def caelia_sigil():
    """Legendary celestial cuff of Caelia: silver-gold open astrolabe bangle crowned with a radiant star-prism."""
    px = canvas()
    cx, cy = 7.5, 9.2
    for y in range(5, 15):
        for x in range(1, 15):
            dx, dy = (x - cx) / 5.7, (y - cy) / 3.9
            outer = dx * dx + dy * dy
            inner = ((x - cx) / 3.3) ** 2 + ((y - cy) / 1.7) ** 2
            if outer <= 1.0 and inner >= 1.0 and not (y >= 12 and 6 <= x <= 9):
                light = -(dx * 0.7 + dy * 0.7)
                ramp = GOLD if (x + y) % 3 == 0 else SILVER
                put(px, x, y, ramp[min(3, max(0, int((light + 1.0) * 2.0)))])
    # Crown starlight prism in gold bezel
    for (x, y, c) in [(7, 2, 3), (8, 2, 2), (6, 3, 3), (7, 3, 3), (8, 3, 2), (9, 3, 1), (6, 4, 2), (7, 4, 3), (8, 4, 2), (9, 4, 1), (7, 5, 2), (8, 5, 1)]:
        put(px, x, y, TEAL[c])
    for (x, y) in [(5, 4), (10, 4), (5, 5), (10, 5)]:
        put(px, x, y, GOLD[3 if x == 5 else 1])
    return px


ICONS = {
    "stardust_elixir": stardust_elixir,
    "astral_star_fruit": astral_star_fruit,
    "morningstar_pendant": morningstar_pendant,
    "crescent_earrings": crescent_earrings,
    "caelia_sigil": caelia_sigil,
}


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
        out_path = pathlib.Path(sys.argv[1])
        out_path.parent.mkdir(parents=True, exist_ok=True)
        write_png(out_path, w, 20 * k, sheet)


if __name__ == "__main__":
    main()
