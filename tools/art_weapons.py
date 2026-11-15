#!/usr/bin/env python3
"""One family of hand items: sword (basic, iron, void, rift), axe, pickaxe, sickle. Needs numpy.
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
    "void": [hexc(c) for c in ("14092e", "35227a", "7d57e0", "e8dcff")],  # the void-forged blade of the boss fight
    "dark": [hexc(c) for c in ("1f1d38", "343b58", "4a5472", "77839f")],
    "raven": [hexc(c) for c in ("0e0a1e", "1a1334", "2c2150", "4a3d8a", "7a68d0")],  # Himmelsriss: blue-black feather steel with a violet sheen (same hues as the Rissfeder's ravensteel)
    "crack": [hexc(c) for c in ("6a3fd0", "9a6bff", "c8aaff", "f4ecff")],  # the rift of light along the blade
    "hagwood": [hexc(c) for c in ("2b1a38", "4c2f5e", "73508a", "a07cb8")],
    "silver": [hexc(c) for c in ("3a4260", "6d7898", "a3adc8", "d6dcef")],
    "bone": [hexc(c) for c in ("4a4560", "8a8698", "b8b4b8", "dedacc", "f6f2e0")],  # Bleichbaum: bleached wood with a violet shade (art_hexenwald.py BONE)  # Fluchsilber of the staff's head  # Hexenulme: nearly black violet bark (docs/magie_konzept.md)
    "stone": [hexc(c) for c in ("363046", "524b64", "746d86", "9e98ae")],  # matte chipped stone with cool-violet shadows (basic tier-1 tools)
    "timber": [hexc(c) for c in ("382538", "5c4048", "82605c", "a68378")],  # plain, humble wooden shaft for basic tools
    "cord": [hexc(c) for c in ("483844", "6e5a56", "967e6a", "baa288")],  # simple fiber/cord lashing
    "starlight": [hexc(c) for c in ("1b4f5c", "2e8892", "6ee8dc", "dcfff8")],  # celestial starlight blade from Caelia's altar
}
GEM = {"sword_basic": hexc("b99bff"), "sword_iron": hexc("78f4e6"), "sword_void": hexc("ff4fd8"), "sword_rift": hexc("c07bff"), "blade_starlight": hexc("fff0b0")}


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


def starlight_sword(w, h, tf):
    """Sternenfall-Klinge: Caelia's celestial blade — golden crescent pommel cradling a bright aqua star gem,
    winged gold moon-crescent crossguard curving round an astral star core, and a sleek tapered starlight blade
    with a glowing golden constellation vein along its fuller."""
    ax = 8.0
    start, end = 11.2, 43.0
    n = 40
    top, low = [], []
    for i in range(n + 1):
        t = i / n
        x = start + (end - start) * t
        half = 2.35 * (1.0 - 0.74 * (t ** 1.15)) + 0.28 * math.sin(math.pi * t)
        notch = -0.3 if abs(t - 0.13) < 0.04 else 0.0
        top.append((x, ax - (half + notch)))
        low.append((x, ax + (half + notch)))
    tip = (end + 3.2, ax)
    layers = [
        ("grip", stroke_mask([(3.2, ax), (9.2, ax)], 1.9, w, h, tf), "wrap"),
        ("pommel_arc", poly_mask([
            (0.9, ax - 2.6), (2.7, ax - 2.3), (3.4, ax - 1.1), (2.2, ax),
            (3.4, ax + 1.1), (2.7, ax + 2.3), (0.9, ax + 2.6), (1.7, ax)
        ], w, h, tf), "gold"),
        ("pommel_star", poly_mask([(0.5, ax - 0.7), (1.7, ax - 0.7), (1.7, ax + 0.7), (0.5, ax + 0.7)], w, h, tf), "starcore"),
        ("guard_up", poly_mask([
            (8.2, ax - 0.9), (10.6, ax - 1.4), (12.8, ax - 4.2), (13.4, ax - 6.6),
            (10.8, ax - 5.5), (9.0, ax - 3.4), (7.8, ax - 2.0)
        ], w, h, tf), "gold"),
        ("guard_dn", poly_mask([
            (8.2, ax + 0.9), (10.6, ax + 1.4), (12.8, ax + 4.2), (13.4, ax + 6.6),
            (10.8, ax + 5.5), (9.0, ax + 3.4), (7.8, ax + 2.0)
        ], w, h, tf), "gold"),
        ("collar", poly_mask([(8.6, ax - 1.8), (11.2, ax - 1.8), (11.2, ax + 1.8), (8.6, ax + 1.8)], w, h, tf), "gold"),
        ("blade", poly_mask(top + [tip] + list(reversed(low)), w, h, tf), "starlight_ridge"),
        ("guard_gem", poly_mask([(9.4, ax - 0.9), (11.2, ax - 0.9), (11.2, ax + 0.9), (9.4, ax + 0.9)], w, h, tf), "starcore"),
    ]
    return layers


def rift_sword(w, h, tf):
    """Himmelsriss (docs/rissklinge.md): a long, slightly bowed blade shaped like a black wing feather: a barbed lower edge, a rift of violet light running along its
    spine, a guard of two swept feathers and a pommel that ends in a feather tip. Deliberately not the plain cross of the other swords."""
    ax = 7.0
    start, end = 10.5, 43.0
    n = 40

    def bow(t):  # the spine bows up in the middle and comes back to the axis at the point
        return -0.9 * math.sin(math.pi * min(t, 1.0))

    top, low = [], []
    for i in range(n + 1):
        t = i / n
        x = start + (end - start) * t
        half = 2.7 * (1.0 - t) ** 0.85 + 0.2
        barb = 1.0 if (i % 7 == 5 and 5 <= i <= n - 9) else 0.0  # the barbs of the vane along the cutting edge
        top.append((x, ax + bow(t) - half * 0.8))
        low.append((x, ax + bow(t) + half + barb))
    tip = (end + 2.4, ax - 0.2)
    layers = [("grip", stroke_mask([(2.0, ax), (8.6, ax)], 2.0, w, h, tf), "wrap")]
    layers.append(("pommel", poly_mask([(0.2, ax + 0.3), (1.2, ax - 1.5), (2.8, ax - 1.9), (3.0, ax + 1.9), (1.4, ax + 1.7)], w, h, tf), "raven"))
    wing_up = [(8.2, ax - 1.1), (10.8, ax - 1.5), (11.4, ax - 3.6), (9.6, ax - 6.0), (7.2, ax - 6.6), (7.0, ax - 4.2)]
    wing_dn = [(8.2, ax + 1.1), (10.8, ax + 1.5), (11.4, ax + 3.2), (9.8, ax + 5.4), (7.6, ax + 6.0), (7.2, ax + 4.0)]
    layers.append(("wing_up", poly_mask(wing_up, w, h, tf), "raven"))
    layers.append(("wing_dn", poly_mask(wing_dn, w, h, tf), "raven"))
    blade = poly_mask(top + [tip] + list(reversed(low)), w, h, tf)
    layers.append(("blade", blade, "ridge"))
    layers.append(("gem", poly_mask([(8.6, ax - 0.7), (10.0, ax - 0.7), (10.0, ax + 0.7), (8.6, ax + 0.7)], w, h, tf), "gem:sword_rift"))
    return layers


def axe(w, h, tf):
    """Basic stone axe: humble wooden haft, knapped stone wedge head, fiber lashing."""
    ax = 12.0
    layers = [("handle", stroke_mask([(1.5, ax), (28.5, ax)], 2.2, w, h, tf), "timber")]
    blade = poly_mask([
        (22.0, 11.4), (21.2, 8.0), (20.4, 4.4), (21.2, 2.0),
        (24.0, 0.9), (27.6, 1.3), (29.8, 3.2), (29.4, 6.2),
        (28.0, 9.0), (26.8, 11.4),
    ], w, h, tf)
    butt = poly_mask([(22.2, 12.8), (26.8, 12.8), (26.2, 15.6), (22.8, 15.6)], w, h, tf)
    layers.append(("butt", butt, "stone"))
    layers.append(("blade", blade, "stone"))
    layers.append(("lashing", poly_mask([(21.4, 9.8), (27.4, 9.8), (27.4, 13.6), (21.4, 13.6)], w, h, tf), "lashing"))
    return layers


def pickaxe(w, h, tf):
    """Basic stone pickaxe: humble wooden haft, angular knapped stone pick head, fiber lashing."""
    ax = 11.0
    layers = [("handle", stroke_mask([(1.5, ax), (28.0, ax)], 2.2, w, h, tf), "timber")]
    pts = [(26.5 - 5.2 * (1 - math.cos(a)), ax + 10.0 * math.sin(a)) for a in [(i / 40.0 - 0.5) * math.pi * 0.96 for i in range(41)]]
    head = stroke_mask(pts, lambda t: 1.3 + 3.2 * math.sin(math.pi * t) ** 0.75, w, h, tf)
    layers.append(("head", head, "stone"))
    layers.append(("lashing", poly_mask([(22.6, ax - 2.6), (27.4, ax - 2.6), (27.4, ax + 2.6), (22.6, ax + 2.6)], w, h, tf), "lashing"))
    return layers


def sickle(w, h, tf):
    """Basic stone sickle: humble wooden handle, curved knapped stone blade, fiber lashing."""
    ax = 5.0
    layers = [("handle", stroke_mask([(1.5, ax), (14.5, ax)], 2.2, w, h, tf), "timber")]
    pts = [(13.8 + 8.0 * math.sin(a), ax + 8.0 * (1 - math.cos(a))) for a in [i / 40.0 * 2.22 for i in range(41)]]
    blade = stroke_mask(pts, lambda t: 4.0 * (1 - t) ** 0.75 + 1.2 * t, w, h, tf)
    layers.append(("blade", blade, "stone"))
    layers.append(("lashing", poly_mask([(11.4, ax - 1.9), (15.6, ax - 1.9), (15.6, ax + 1.9), (11.4, ax + 1.9)], w, h, tf), "lashing"))
    return layers


def hoe(w, h, tf):
    """Basic stone hoe: humble wooden haft, broad chipped stone blade, fiber lashing."""
    ax = 6.0
    layers = [("handle", stroke_mask([(1.5, ax), (27.5, ax)], 2.2, w, h, tf), "timber")]
    blade = poly_mask([
        (23.6, ax + 1.4), (27.0, ax + 1.0), (29.8, ax + 8.6),
        (29.4, ax + 11.0), (24.0, ax + 10.6), (23.0, ax + 7.8),
    ], w, h, tf)
    layers.append(("blade", blade, "stone"))
    layers.append(("lashing", poly_mask([(22.4, ax - 2.2), (27.2, ax - 2.2), (27.2, ax + 2.4), (22.4, ax + 2.4)], w, h, tf), "lashing"))
    return layers


def can(w, h, tf):
    """The watering can: a tin drum with a lid band, a wooden handle loop at the back (where the hand is) and a long spout with a rose that points the way she aims."""
    ax = 9.0
    body = poly_mask([(5.4, ax - 3.6), (14.6, ax - 3.6), (15.6, ax - 2.4), (15.6, ax + 4.4), (14.6, ax + 5.6), (5.4, ax + 5.6), (4.4, ax + 4.4), (4.4, ax - 2.4)], w, h, tf)
    layers = [("handle", stroke_mask([(6.0, ax - 4.2), (2.6, ax - 3.4), (1.6, ax + 0.4), (2.6, ax + 4.2), (6.0, ax + 5.0)], 1.8, w, h, tf), "wood")]
    layers.append(("spout", stroke_mask([(14.6, ax + 3.4), (20.0, ax - 0.6), (26.0, ax - 4.4)], lambda u: 2.4 - 1.0 * u, w, h, tf), "steel"))
    layers.append(("body", body, "steel"))
    layers.append(("band", poly_mask([(4.4, ax - 3.6), (15.6, ax - 3.6), (15.6, ax - 1.6), (4.4, ax - 1.6)], w, h, tf), "steel_dark"))
    layers.append(("rose", poly_mask([(25.4, ax - 7.4), (28.6, ax - 6.0), (28.2, ax - 2.6), (25.2, ax - 3.4)], w, h, tf), "steel_dark"))
    return layers


def rod(w, h, tf):
    ax = 4.0
    layers = [("shaft", stroke_mask([(6.0, ax), (46.0, ax - 0.3)], lambda u: 1.7 - 0.8 * u, w, h, tf), "wood")]
    layers.append(("grip", stroke_mask([(1.0, ax), (9.0, ax)], 2.4, w, h, tf), "wrap"))
    layers.append(("reel", poly_mask([(9.4, ax + 0.4), (12.4, ax + 0.4), (12.4, ax + 3.2), (9.4, ax + 3.2)], w, h, tf), "gold"))
    layers.append(("ring", stroke_mask([(26.0, ax - 0.2), (26.0, ax + 1.2)], 0.9, w, h, tf), "gold"))
    layers.append(("tip", stroke_mask([(45.0, ax - 0.4), (47.0, ax - 0.5)], 0.9, w, h, tf), "gold"))
    return layers


def staff(w, h, tf):
    """Hexenulmenstab (docs/magie_konzept.md), short and stout: a twisted branch of the Hexenulme with a knobbed root end and a leather wrap,
    a band of Fluchsilber where the head begins, a silver bezel for the gem (KNOT_PX = 16 from the grip) and a cradle of two gnarled prongs
    that close round the spell crystal (CROWN_PX = 23). The stones are drawn by the game into the open cradle and bezel (StaffCrystals),
    which also lays the silver clasp over the crystal so it sits IN the head. Short witch-green veins wander along the bark."""
    ax = 4.5
    pts = [(1.6 + i * 1.0, ax + 0.45 * math.sin(i * 0.7)) for i in range(21)]
    layers = [("shaft", stroke_mask(pts, lambda u: 3.2 - 0.5 * u, w, h, tf), "hagwood")]
    layers.append(("root", poly_mask([(0.0, ax - 1.8), (1.6, ax - 2.6), (3.6, ax - 1.8), (3.8, ax + 2.0), (1.6, ax + 2.6), (0.0, ax + 1.6)], w, h, tf), "hagwood"))
    layers.append(("wrap", stroke_mask([(5.4, ax), (10.6, ax)], 3.6, w, h, tf), "wrap"))
    head = poly_mask([(19.6, ax - 2.2), (22.0, ax - 3.6), (25.6, ax - 3.4), (26.4, ax), (25.6, ax + 3.4), (22.0, ax + 3.6), (19.6, ax + 2.2)], w, h, tf)
    layers.append(("head", head, "hagwood"))
    layers.append(("band", poly_mask([(18.6, ax - 2.0), (20.0, ax - 2.2), (20.0, ax + 2.2), (18.6, ax + 2.0)], w, h, tf), "silver"))
    bezel = stroke_mask([(16.0 + 2.0 * math.cos(a), ax + 2.0 * math.sin(a)) for a in [i / 12.0 * 2 * math.pi for i in range(13)]], 1.0, w, h, tf)
    layers.append(("bezel_hole", poly_mask([(14.6, ax - 1.4), (17.4, ax - 1.4), (17.4, ax + 1.4), (14.6, ax + 1.4)], w, h, tf), "hollow"))
    layers.append(("bezel", bezel, "silver"))
    up = [(25.0, ax - 2.6), (27.6, ax - 4.4), (30.6, ax - 4.6), (33.0, ax - 3.0), (33.6, ax - 1.0)]
    dn = [(25.0, ax + 2.6), (27.6, ax + 4.4), (30.6, ax + 4.6), (33.0, ax + 3.0), (33.6, ax + 1.0)]
    layers.append(("prong_up", stroke_mask(up, lambda u: 2.2 - 0.9 * u, w, h, tf), "hagwood"))
    layers.append(("prong_dn", stroke_mask(dn, lambda u: 2.2 - 0.9 * u, w, h, tf), "hagwood"))
    layers.append(("cradle", poly_mask([(26.0, ax - 1.6), (27.4, ax - 2.0), (27.4, ax + 2.0), (26.0, ax + 1.6)], w, h, tf), "hollow"))
    for a, b in (((4.0, ax - 0.8), (5.0, ax + 0.6)), ((12.0, ax + 0.8), (14.0, ax - 0.6)), ((21.4, ax - 1.6), (23.6, ax + 0.4)), ((28.6, ax - 3.6), (30.4, ax - 4.0))):
        layers.append(("vein", stroke_mask([a, b], 0.7, w, h, tf), "vein"))
    return layers


def bone_fork(w, h, tf):
    """Bleichgabel (docs/magie_konzept.md 17): a branch of the Bleichbaum that splits into a narrow, uneven Y, as it grew: the upper prong
    (prong 0, left mouse button) runs on longer, the lower one (prong 1, right mouse button) stops short. Bleached, bone-white wood with
    dark violet cracks along it, a knuckled root end, a leather wrap on the grip, a band of Fluchsilber just below the split and in the
    crotch a shadow core that glows. Each prong carries a silver bezel for its gem and ends in a claw of two bony fingers that cradle its
    spell crystal. The places (px from the grip along the staff, px across, + = down in this picture) are `crowns`/`knots` of
    `staff_bone_fork` in data/spells.json: long prong crown (31.5, -4.8), knot (20.8, -3.4); short prong crown (26.1, 4.2), knot (18.0, 2.6).
    StaffCrystals draws the stones into bezels and claws."""
    ax = 8.5
    pts = [(1.8 + i * 1.0, ax + 0.35 * math.sin(i * 0.55)) for i in range(23)]
    layers = [("shaft", stroke_mask(pts, lambda u: 3.0 - 0.4 * u, w, h, tf), "bone")]
    layers.append(("root", poly_mask([(0.0, ax - 1.6), (1.2, ax - 2.6), (3.0, ax - 2.4), (4.0, ax - 1.0), (4.0, ax + 1.2), (3.0, ax + 2.6), (1.2, ax + 2.4), (0.0, ax + 1.4)], w, h, tf), "bone"))
    layers.append(("wrap", stroke_mask([(5.6, ax), (11.6, ax)], 3.6, w, h, tf), "wrap"))
    prongs = (  # side, the arm, where its claw sits (end x, y), its knot (x, y)
        (-1.0, [(22.6, -0.6), (25.0, -1.9), (27.8, -3.1), (30.8, -3.9), (34.0, -4.4), (37.0, -4.7)], (37.2, -4.8), (28.8, -3.4)),
        (1.0, [(22.6, 0.6), (24.8, 1.8), (27.0, 2.9), (29.4, 3.6), (31.6, 4.0)], (31.8, 4.2), (26.0, 2.6)),
    )
    for side, arm, _end, _knot in prongs:
        layers.append(("prong", stroke_mask([(x, ax + y) for x, y in arm], lambda u: 2.5 - 0.8 * u, w, h, tf), "bone"))
    layers.append(("band", poly_mask([(20.4, ax - 2.0), (21.9, ax - 2.2), (21.9, ax + 2.2), (20.4, ax + 2.0)], w, h, tf), "silver"))
    layers.append(("crotch", poly_mask([(23.6, ax - 0.9), (25.0, ax - 1.3), (25.4, ax), (25.0, ax + 1.3), (23.6, ax + 0.9)], w, h, tf), "hollow"))
    layers.append(("core", stroke_mask([(24.5, ax), (24.6, ax)], 1.2, w, h, tf), "core"))
    for side, _arm, (ex, ey0), (kx, ky0) in prongs:
        ky = ax + ky0
        ring = [(kx + 1.6 * math.cos(a), ky + 1.6 * math.sin(a)) for a in [i / 12.0 * 2 * math.pi for i in range(13)]]
        layers.append(("bezel_hole", poly_mask([(kx - 0.9, ky - 0.9), (kx + 0.9, ky - 0.9), (kx + 0.9, ky + 0.9), (kx - 0.9, ky + 0.9)], w, h, tf), "hollow"))
        layers.append(("bezel", stroke_mask(ring, 0.9, w, h, tf), "silver"))
        ey = ax + ey0
        outer = [(ex, ey), (ex + 1.6, ey + side * 1.9), (ex + 3.8, ey + side * 2.4), (ex + 5.2, ey + side * 1.6)]
        inner = [(ex, ey), (ex + 1.6, ey - side * 1.8), (ex + 3.8, ey - side * 2.2), (ex + 5.0, ey - side * 1.4)]
        layers.append(("claw_out", stroke_mask(outer, lambda u: 1.7 - 0.8 * u, w, h, tf), "bone"))
        layers.append(("claw_in", stroke_mask(inner, lambda u: 1.7 - 0.8 * u, w, h, tf), "bone"))
        layers.append(("cradle", poly_mask([(ex + 1.4, ey - 1.1), (ex + 3.2, ey - 1.3), (ex + 3.2, ey + 1.3), (ex + 1.4, ey + 1.1)], w, h, tf), "hollow"))
    for a, b in (((13.0, ax - 0.9), (16.4, ax - 0.3)), ((17.4, ax + 0.9), (19.6, ax + 0.4)), ((31.4, ax - 4.0), (33.6, ax - 4.4)), ((27.6, ax + 3.1), (28.8, ax + 3.5)), ((2.0, ax + 1.0), (3.4, ax + 1.8))):
        layers.append(("crack", stroke_mask([a, b], 0.6, w, h, tf), "bonecrack"))
    return layers


ITEMS = {  # id: (size, pivot in the item frame, builder, steel ramp, icon fit: (rotation, scale, offset))
    "sword_basic": ((34, 12), (4.5, 6.0), sword(21, "sword_basic", "steel"), "steel", (-45.0, 0.46, (1.6, 14.4))),
    "sword_iron": ((36, 12), (4.5, 6.0), sword(23, "sword_iron", "mint"), "mint", (-45.0, 0.44, (1.6, 14.4))),
    "blade_starlight": ((48, 16), (5.0, 8.0), starlight_sword, "starlight", (-45.0, 0.33, (2.9, 13.1))),
    "sword_void": ((42, 12), (4.5, 6.0), sword(29, "sword_void", "void"), "void", (-45.0, 0.4, (1.6, 14.4))),
    "sword_rift": ((50, 16), (4.5, 7.0), rift_sword, "raven", (-45.0, 0.4, (1.4, 14.4))),
    "axe_basic": ((34, 18), (5.0, 12.0), axe, "steel", (-45.0, 0.5, (1.0, 15.2))),
    "pickaxe_basic": ((34, 22), (5.0, 11.0), pickaxe, "steel", (-45.0, 0.5, (1.0, 12.4))),
    "sickle_basic": ((26, 20), (5.0, 5.0), sickle, "steel", (-45.0, 0.6, (1.0, 12.6))),
    "rod_basic": ((49, 9), (4.0, 4.0), rod, "steel", (-45.0, 0.3, (2.4, 13.6))),
    "hoe_basic": ((34, 20), (5.0, 6.0), hoe, "steel", (-45.0, 0.5, (1.0, 13.0))),
    "watering_can": ((32, 20), (3.0, 9.0), can, "steel", (0.0, 0.43, (3.0, 8.8))),
    "staff_hag_elm": ((35, 10), (8.0, 4.5), staff, "steel", (-45.0, 0.46, (4.2, 11.8))),
    "staff_bone_fork": ((44, 17), (8.0, 8.5), bone_fork, "steel", (-45.0, 0.34, (3.8, 12.2))),
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
        if mat == "crack":  # flat violet light, a bright spark now and then
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                img[(int(x), int(y))] = RAMPS["crack"][2 if (int(x) * 7 + int(y) * 3) % 5 == 0 else 1]
            continue
        if mat == "starcore":  # bright celestial gold-aqua core
            ys = np.nonzero(mask)
            cx = float(np.mean(ys[1])) if len(ys[1]) else 0.0
            cy = float(np.mean(ys[0])) if len(ys[0]) else 0.0
            for yy, xx in zip(*ys):
                d = math.hypot(float(xx) - cx, float(yy) - cy)
                img[(int(xx), int(yy))] = hexc("fffbe6") if d < 0.75 else (hexc("78f4e6") if d < 1.35 else hexc("fff0b0"))
            continue
        if mat == "starlight_ridge":  # celestial blade: luminous aqua top bevel, cyan astral body, dark cosmic shadow, golden constellation fuller spine
            ys = np.nonzero(mask)
            cols = {}
            for yy, xx in zip(*ys):
                lo, hi = cols.get(int(xx), (int(yy), int(yy)))
                cols[int(xx)] = (min(lo, int(yy)), max(hi, int(yy)))
            ramp = RAMPS["starlight"]
            xs_sorted = sorted(cols.keys())
            x_min = xs_sorted[0] if xs_sorted else 0
            x_max = xs_sorted[-1] if xs_sorted else 1
            for yy, xx in zip(*ys):
                x, y = int(xx), int(yy)
                lo, hi = cols[x]
                span = hi - lo
                if span == 0:
                    img[(x, y)] = ramp[3]
                    continue
                u = (x - x_min) / max(x_max - x_min, 1)
                mid_y = (lo + hi) // 2
                if y == lo:
                    c = ramp[3]
                elif y == mid_y and u < 0.85 and span >= 2:
                    c = hexc("fffbe8") if (x - x_min) % 4 == 0 else hexc("e6c468")
                elif y < mid_y:
                    c = ramp[2]
                elif y == hi:
                    c = ramp[0]
                else:
                    c = ramp[1]
                img[(x, y)] = c
            continue
        if mat == "ridge":  # a feather blade: lit upper half, a rift of light along the spine, shaded lower half (per column, so any scale works)
            ys = np.nonzero(mask)
            cols = {}
            for yy, xx in zip(*ys):
                lo, hi = cols.get(int(xx), (int(yy), int(yy)))
                cols[int(xx)] = (min(lo, int(yy)), max(hi, int(yy)))
            for yy, xx in zip(*ys):
                x, y = int(xx), int(yy)
                lo, hi = cols[x]
                span = hi - lo
                if span == 0:
                    img[(x, y)] = RAMPS["raven"][3]
                    continue
                t = (y - lo) / span
                spine = 0.5 + (0.0 if (x // 2) % 2 else 0.12)  # the rift zigzags a little
                if t < 0.001:
                    c = RAMPS["raven"][3]
                elif abs(t - spine) <= 0.5 / span + 0.001 and span >= 2:
                    c = RAMPS["crack"][2 if (x * 7 + y * 3) % 5 == 0 else 1]
                elif t < spine:
                    c = RAMPS["raven"][2]
                elif y == hi:
                    c = RAMPS["raven"][0]
                else:
                    c = RAMPS["raven"][1]
                img[(x, y)] = c
            continue
        if mat == "hagwood":  # the bevel, and a twisted grain: dark grooves winding round the branch
            for (x, y), c in bevel(mask, RAMPS["hagwood"]).items():
                img[(x, y)] = RAMPS["hagwood"][0] if (x * 2 + y) % 7 == 0 and c != RAMPS["hagwood"][-1] else c
            continue
        if mat == "hollow":  # the knot's hollow: a dark socket with a lit lower lip
            ys = np.nonzero(mask)
            lowest = int(max(ys[0])) if len(ys[0]) else 0
            for yy, xx in zip(*ys):
                img[(int(xx), int(yy))] = hexc("8a6a9a") if int(yy) == lowest else hexc("0c0812")
            continue
        if mat == "bone":  # bleached wood: the bevel, and fine grain lines running along it
            for (x, y), c in bevel(mask, RAMPS["bone"]).items():
                img[(x, y)] = RAMPS["bone"][1] if (x * 3 + y * 7) % 11 == 0 and c != RAMPS["bone"][-1] else c
            continue
        if mat == "bonecrack":  # dark violet cracks in the bleached wood
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                if (int(x), int(y)) in img:
                    img[(int(x), int(y))] = hexc("2e2a44") if (int(x) + int(y)) % 4 else hexc("6a3fa0")
            continue
        if mat == "core":  # the shadow core in the crotch: a magenta heart in violet
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                img[(int(x), int(y))] = hexc("ff4fd8") if (int(x) + int(y)) % 2 == 0 else hexc("8a3fd0")
            continue
        if mat == "vein":  # short witch-green veins (the Hexenwald's trees)
            for (x, y) in zip(*np.nonzero(mask)[::-1]):
                if (int(x), int(y)) in img:
                    img[(int(x), int(y))] = hexc("7fd65a") if (int(x) + int(y)) % 3 else hexc("c4ff9a")
            continue
        if mat == "steel_dark":
            mat = "dark"
        if mat == "stone":  # matte knapped stone: bevel + subtle directional chip facets (no shiny speculars)
            ramp = RAMPS["stone"]
            for (x, y), c in bevel(mask, ramp).items():
                if c == ramp[2] and ((x // 2 + y) % 5 == 0):
                    img[(x, y)] = ramp[1]
                elif c == ramp[3] and ((x + y * 2) % 7 == 0):
                    img[(x, y)] = ramp[2]
                else:
                    img[(x, y)] = c
            continue
        if mat == "lashing":  # wrapped fiber/cord lashing around the stone-to-wood joint
            ramp = RAMPS["cord"]
            for (x, y), c in bevel(mask, ramp).items():
                if (x + y) % 3 == 0 and c != ramp[0]:
                    idx = max(0, ramp.index(c) - 1)
                    img[(x, y)] = ramp[idx]
                else:
                    img[(x, y)] = c
            continue
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
    elif len(sys.argv) > 2 and sys.argv[1] == "only":  # build just these ids: art_weapons.py only hoe_basic watering_can
        for name in sys.argv[2:]:
            print(name, "cell", build(name))
    else:
        for name in ITEMS:
            print(name, "cell", build(name))
