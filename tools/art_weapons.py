#!/usr/bin/env python3
"""One family of hand items: sword (basic, iron), axe, pickaxe, sickle. Needs numpy.
  assets/items/<id>.png           icon 16x16 (handle bottom left, head top right)
  assets/items/<id>_held.png      the item pointing right, pivot = the hand (PIVOTS)
  assets/items/<id>_held_rot.png  the held picture pre-rotated (ROT_ANGLES steps around the circle, rows =
                                  ROT_LENGTHS: foreshortening along the shaft), RotSprite style (EPX x8, majority
                                  vote), so the game never rotates or squashes pixel art at run time.
                                  Cells are square, odd, the pivot sits in the middle of the middle pixel.
Shared look: one geometry per item (polygons + strokes) rasterised at both sizes; every material is shaded by
the same bevel rule (light on the top-left rim, dark on the bottom-right rim), ink outline 1b1a2e like the
other items. Wood is the violet-plum wood of the trees, the grip is a violet leather wrap, steel is the blue
steel ramp of the stone art. Keep ROT_ANGLES / ROT_LENGTHS in sync with src/components/attack_component.gd.
Preview: python3 tools/art_weapons.py preview out.png"""
import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

ROT_ANGLES = 48
ROT_LENGTHS = (0.4, 0.52, 0.64, 0.76, 0.88, 1.0)
INK = hexc("1b1a2e")
RAMPS = {  # dark .. light; bevel: lit rim = last, shaded rim = first, inside = the one before the last
    "steel": [hexc(c) for c in ("343b58", "5b6684", "93a0bc", "d4dbec", "f6f9ff")],
    "wood": [hexc(c) for c in ("3a2442", "5c3d5c", "85607a", "aa8396")],
    "leather": [hexc(c) for c in ("2a1a4a", "46308a", "6a4bd0", "9a82f0")],
    "gold": [hexc(c) for c in ("6a4a2a", "a07a3a", "d8b45a", "f6e0a0")],
    "mint": [hexc(c) for c in ("2e4a46", "4f7f74", "8fc4b0", "dff6ec")],  # the forged sword
    "dark": [hexc(c) for c in ("1f1d38", "343b58", "4a5472", "77839f")],
}
GEM = {"sword_basic": hexc("b99bff"), "sword_iron": hexc("78f4e6")}


# ------------------------------------------------------------------ geometry (item frame: pointing right, y down)
def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / max(dx * dx + dy * dy, 1e-9)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy)), t


def stroke_mask(pts, width, w, h, tf):
    """Capsule / tapered stroke: pts = [(x, y)], width = f(t) or a number; tf maps item frame -> pixels."""
    mask = np.zeros((h, w), bool)
    q = [tf(p) for p in pts]
    scale = tf((1, 0))[0] - tf((0, 0))[0]
    scale = math.hypot(*(np.array(tf((1, 0))) - np.array(tf((0, 0)))))
    for y in range(h):
        for x in range(w):
            best = 9e9
            for i in range(len(q) - 1):
                d, t = seg_dist(x + 0.5, y + 0.5, q[i][0], q[i][1], q[i + 1][0], q[i + 1][1])
                u = (i + t) / (len(q) - 1)
                wd = (width(u) if callable(width) else width) * scale / 2.0
                best = min(best, d - wd)
            mask[y, x] = best <= 0.0
    return mask


def poly_mask(pts, w, h, tf):
    q = [tf(p) for p in pts]
    mask = np.zeros((h, w), bool)
    n = len(q)
    for y in range(h):
        for x in range(w):
            inside, j = False, n - 1
            for i in range(n):
                xi, yi = q[i]
                xj, yj = q[j]
                if (yi > y + 0.5) != (yj > y + 0.5) and (x + 0.5) < (xj - xi) * (y + 0.5 - yi) / (yj - yi) + xi:
                    inside = not inside
                j = i
            mask[y, x] = inside
    return mask


def bevel(mask, ramp, x_off=0, edge_light=None):
    """Pixels of a mask -> colours: light comes from the top left, so the shade runs from the lit rim
    (up / left) to the dark rim (down / right) across the thickness of the part, in as many steps as the ramp has."""
    h, w = mask.shape
    out = {}
    get = lambda x, y: bool(mask[y, x]) if 0 <= x < w and 0 <= y < h else False  # noqa: E731

    def run(x, y, dx, dy):
        n = 0
        while get(x + dx * n, y + dy * n):
            n += 1
        return n

    for y in range(h):
        for x in range(w):
            if not mask[y, x]:
                continue
            dl = min(run(x, y, 0, -1), run(x, y, -1, 0))
            dd = min(run(x, y, 0, 1), run(x, y, 1, 0))
            t = min(1.0, max(0.0, (dl - 1.0) / max(dl + dd - 2.0, 1.0))) if dl + dd > 2 else (0.0 if dl <= dd else 1.0)
            idx = int(round((1.0 - t) * (len(ramp) - 1)))
            if dl == 1 and t < 0.5:  # the lit rim is always the brightest step
                idx = len(ramp) - 1
            out[(x, y)] = ramp[idx]
    return out


# ------------------------------------------------------------------ the five items
# each: pivot (the hand, item frame), size, and a builder that returns layers [(material mask, ramp name, options)]
def sword(blade, gem_key, steel):
    def build(w, h, tf):
        ax = 6.0  # axis y
        end = 11.0 + blade
        layers = []
        grip = stroke_mask([(2.0, ax), (8.0, ax)], 2.0, w, h, tf)
        layers.append(("grip", grip, "leather"))
        pommel = poly_mask([(0.0, ax - 1.6), (2.2, ax - 2.0), (2.6, ax), (2.2, ax + 2.0), (0.0, ax + 1.6)], w, h, tf)
        layers.append(("pommel", pommel, "gold"))
        guard = poly_mask([(8.0, ax - 4.6), (9.6, ax - 4.0), (9.6, ax + 4.0), (8.0, ax + 4.6), (7.0, ax + 2.0), (7.0, ax - 2.0)], w, h, tf)
        layers.append(("guard", guard, "gold"))
        blade_m = poly_mask([(9.6, ax - 2.0), (end - 5.0, ax - 2.0), (end, ax), (end - 5.0, ax + 2.0), (9.6, ax + 2.0)], w, h, tf)
        layers.append(("blade", blade_m, steel))
        fuller = stroke_mask([(11.0, ax), (end - 6.0, ax)], 0.7, w, h, tf)
        layers.append(("fuller", fuller & blade_m, "fuller"))
        gem = poly_mask([(0.8, ax - 0.6), (1.6, ax - 0.6), (1.6, ax + 0.6), (0.8, ax + 0.6)], w, h, tf)
        layers.append(("gem", gem, "gem:" + gem_key))
        return layers
    return build


def axe(w, h, tf):
    ax = 12.0
    layers = [("handle", stroke_mask([(1.5, ax), (27.0, ax)], 2.0, w, h, tf), "wood")]
    layers.append(("wrap", stroke_mask([(2.0, ax), (9.0, ax)], 2.0, w, h, tf), "wrap"))
    blade = poly_mask([(22.4, 11.2), (21.2, 8.2), (19.6, 5.0), (19.4, 2.4), (21.4, 0.8), (25.6, 0.4), (29.4, 1.2), (31.2, 3.0), (30.2, 6.0), (28.4, 9.0), (27.8, 11.2)], w, h, tf)
    poll = poly_mask([(22.4, 13.0), (27.8, 13.0), (27.4, 16.4), (23.0, 16.6)], w, h, tf)
    layers.append(("poll", poll, "steel_dark"))
    layers.append(("eye", poly_mask([(22.2, 10.6), (28.2, 10.6), (28.2, 13.4), (22.2, 13.4)], w, h, tf), "steel_dark"))
    layers.append(("blade", blade, "steel"))
    return layers


def pickaxe(w, h, tf):
    ax = 11.0
    layers = [("handle", stroke_mask([(1.5, ax), (27.0, ax)], 2.0, w, h, tf), "wood")]
    layers.append(("wrap", stroke_mask([(2.0, ax), (9.0, ax)], 2.0, w, h, tf), "wrap"))
    pts = [(27.0 - 5.4 * (1 - math.cos(a)), ax + 10.2 * math.sin(a)) for a in [(i / 40.0 - 0.5) * math.pi * 0.98 for i in range(41)]]
    head = stroke_mask(pts, lambda t: 0.9 + 2.9 * math.sin(math.pi * t) ** 0.8, w, h, tf)
    layers.append(("collar", poly_mask([(23.4, ax - 2.2), (27.4, ax - 2.2), (27.4, ax + 2.2), (23.4, ax + 2.2)], w, h, tf), "steel_dark"))
    layers.append(("head", head, "steel"))
    return layers


def sickle(w, h, tf):
    ax = 5.0
    layers = [("handle", stroke_mask([(1.5, ax), (14.0, ax)], 2.0, w, h, tf), "wood")]
    layers.append(("wrap", stroke_mask([(2.0, ax), (8.0, ax)], 2.0, w, h, tf), "wrap"))
    pts = [(14.0 + 8.0 * math.sin(a), ax + 8.0 * (1 - math.cos(a))) for a in [i / 40.0 * 2.25 for i in range(41)]]
    blade = stroke_mask(pts, lambda t: 3.8 * (1 - t) ** 0.8 + 0.9 * t, w, h, tf)
    layers.append(("ferrule", poly_mask([(13.0, ax - 1.6), (16.0, ax - 1.6), (16.0, ax + 1.6), (13.0, ax + 1.6)], w, h, tf), "steel_dark"))
    layers.append(("blade", blade, "steel"))
    return layers


def rod(w, h, tf):
    ax = 4.0
    layers = [("shaft", stroke_mask([(6.0, ax), (46.0, ax - 0.3)], lambda u: 1.7 - 0.8 * u, w, h, tf), "wood")]
    layers.append(("grip", stroke_mask([(1.0, ax), (9.0, ax)], 2.4, w, h, tf), "wrap"))
    layers.append(("reel", poly_mask([(9.4, ax + 0.4), (12.4, ax + 0.4), (12.4, ax + 3.2), (9.4, ax + 3.2)], w, h, tf), "gold"))
    layers.append(("ring", stroke_mask([(26.0, ax - 0.2), (26.0, ax + 1.2)], 0.9, w, h, tf), "gold"))
    layers.append(("tip", stroke_mask([(45.0, ax - 0.4), (47.0, ax - 0.5)], 0.9, w, h, tf), "gold"))
    return layers


ITEMS = {  # id: (size, pivot in the item frame, builder, steel ramp, icon fit: (rotation, scale, offset))
    "sword_basic": ((34, 12), (4.5, 6.0), sword(21, "sword_basic", "steel"), "steel", (-45.0, 0.46, (1.6, 14.4))),
    "sword_iron": ((36, 12), (4.5, 6.0), sword(23, "sword_iron", "mint"), "mint", (-45.0, 0.44, (1.6, 14.4))),
    "axe_basic": ((34, 18), (5.0, 12.0), axe, "steel", (-45.0, 0.5, (1.0, 15.2))),
    "pickaxe_basic": ((34, 22), (5.0, 11.0), pickaxe, "steel", (-45.0, 0.5, (1.0, 12.4))),
    "sickle_basic": ((26, 20), (5.0, 5.0), sickle, "steel", (-45.0, 0.6, (1.0, 12.6))),
    "rod_basic": ((49, 9), (4.0, 4.0), rod, "steel", (-45.0, 0.3, (2.4, 13.6))),
}


# ------------------------------------------------------------------ rasterising
def compose(item, w, h, tf, material_map=None):
    """Layers -> pixel dict {(x, y): colour}."""
    _, _, builder, steel, _ = ITEMS[item]
    layers = builder(w, h, tf) if callable(builder) else builder
    img = {}
    for name, mask, mat in layers:
        if mat.startswith("gem:"):
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                img[(int(x), int(y))] = GEM[mat[4:]]
            continue
        if mat == "steel":
            mat = steel
        if mat == "fuller":
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                img[(int(x), int(y))] = RAMPS[steel][1]
            continue
        if mat == "wrap":
            for (x, y), c in bevel(mask, RAMPS["leather"]).items():
                img[(x, y)] = c if (x + y) % 3 else RAMPS["leather"][1]
            continue
        if mat == "steel_dark":
            mat = "dark"
        for (x, y), c in bevel(mask, RAMPS[mat]).items():
            img[(x, y)] = c
    return img


def outline(img, w, h):
    out = dict(img)
    for y in range(h):
        for x in range(w):
            if (x, y) in img:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if (x + dx, y + dy) in img:
                    out[(x, y)] = INK
                    break
    return out


def to_rows(img, w, h):
    return [[img.get((x, y), CLEAR) for x in range(w)] for y in range(h)]


def held(item):
    (w, h), _, _, _, _ = ITEMS[item]
    w, h = w + 2, h + 2  # one pixel of room all round for the outline
    img = compose(item, w, h, lambda p: (p[0] + 1.0, p[1] + 1.0))
    return outline(img, w, h), w, h


def icon(item):
    _, _, _, _, (rot, scale, off) = ITEMS[item]
    (w0, h0), pivot, *_ = ITEMS[item]
    r = math.radians(rot)
    c, s = math.cos(r), math.sin(r)

    def tf(p):
        x, y = (p[0] - pivot[0]) * scale, (p[1] - pivot[1]) * scale
        return (x * c - y * s + off[0], x * s + y * c + off[1])

    img = compose(item, 16, 16, tf)
    return outline(img, 16, 16)


# ------------------------------------------------------------------ rotation sheet (RotSprite style)
def epx(a):
    """Scale2x on an id image (EPX)."""
    h, w = a.shape
    p = np.pad(a, 1, mode="edge")
    A, B, C, D = p[:-2, 1:-1], p[1:-1, 2:], p[1:-1, :-2], p[2:, 1:-1]
    P = a
    n1 = np.where((C == A) & (C != D) & (A != B), A, P)
    n2 = np.where((A == B) & (A != C) & (B != D), B, P)
    n3 = np.where((D == C) & (D != B) & (C != A), C, P)
    n4 = np.where((B == D) & (B != A) & (D != C), D, P)
    out = np.empty((h * 2, w * 2), a.dtype)
    out[0::2, 0::2], out[0::2, 1::2], out[1::2, 0::2], out[1::2, 1::2] = n1, n2, n3, n4
    return out


def rot_sheet(item, img, w, h, pivot):
    colors = {}
    ids = np.zeros((h, w), np.int32)
    for (x, y), c in img.items():
        ids[y, x] = colors.setdefault(c, len(colors) + 1)
    palette = {v: k for k, v in colors.items()}
    big = ids
    for _ in range(3):
        big = epx(big)
    K = 8
    rad = max(math.hypot(x + 0.5 - pivot[0], y + 0.5 - pivot[1]) for (x, y) in img) + 1.5
    cell = int(math.ceil(rad)) * 2 + 1
    mid = cell // 2
    sheet = [[CLEAR] * (cell * ROT_ANGLES) for _ in range(cell * len(ROT_LENGTHS))]
    sub = [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25), (0.0, 0.0)]
    for li, length in enumerate(ROT_LENGTHS):
        for ai in range(ROT_ANGLES):
            ang = ai * 2.0 * math.pi / ROT_ANGLES
            ca, sa = math.cos(ang), math.sin(ang)
            for oy in range(cell):
                for ox in range(cell):
                    votes = {}
                    for sx, sy in sub:
                        dx, dy = ox + 0.5 + sx - (mid + 0.5), oy + 0.5 + sy - (mid + 0.5)
                        lx, ly = (dx * ca + dy * sa) / length, (-dx * sa + dy * ca)
                        ix, iy = int(math.floor((lx + pivot[0]) * K)), int(math.floor((ly + pivot[1]) * K))
                        v = int(big[iy, ix]) if 0 <= ix < w * K and 0 <= iy < h * K else 0
                        votes[v] = votes.get(v, 0) + (1.4 if (sx, sy) == (0.0, 0.0) else 1.0)
                    best = max(votes, key=votes.get)
                    if best:
                        sheet[li * cell + oy][ai * cell + ox] = palette[best]
    return sheet, cell


def build(item):
    img, w, h = held(item)
    (_, _), pivot, *_ = ITEMS[item]
    pivot = (pivot[0] + 1.0, pivot[1] + 1.0)
    items = ROOT / "items"
    write_png(items / f"{item}_held.png", w, h, to_rows(img, w, h))
    write_png(items / f"{item}.png", 16, 16, to_rows(icon(item), 16, 16))
    sheet, cell = rot_sheet(item, img, w, h, pivot)
    write_png(items / f"{item}_held_rot.png", cell * ROT_ANGLES, cell * len(ROT_LENGTHS), sheet)
    return cell


def preview(out):
    from PIL import Image
    names = list(ITEMS)
    tiles = []
    for n in names:
        img, w, h = held(n)
        held_im = Image.new("RGBA", (w, h))
        for (x, y), c in img.items():
            held_im.putpixel((x, y), c)
        ic = Image.new("RGBA", (16, 16))
        for (x, y), c in icon(n).items():
            ic.putpixel((x, y), c)
        tiles.append((held_im, ic))
    sheet = Image.new("RGBA", (420, 150 * len(names)), (60, 90, 60, 255))
    for i, (h_, ic) in enumerate(tiles):
        sheet.alpha_composite(h_.resize((h_.width * 8, h_.height * 8), Image.NEAREST), (4, 4 + i * 150)) if h_.width * 8 < 420 else sheet.alpha_composite(h_.resize((h_.width * 6, h_.height * 6), Image.NEAREST), (4, 4 + i * 150))
        sheet.alpha_composite(ic.resize((96, 96), Image.NEAREST), (316, 4 + i * 150))
    sheet.save(out)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "preview":
        preview(sys.argv[2])
    else:
        for name in ITEMS:
            print(name, "cell", build(name))
