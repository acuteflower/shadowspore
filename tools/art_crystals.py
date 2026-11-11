#!/usr/bin/env python3
"""The magic stones (docs/magie_konzept.md): two sets in five tiers each, drawn from geometry. Needs numpy + PIL (py -3).

  SPELL CRYSTALS (grown): upright, pointed, uneven, clear and strong in their school's colour, lit from inside. The sign of the spell floats
  INSIDE as a glowing inclusion: it is broken by a pixel at every facet edge (refraction), partly hidden behind the facets' glints, brighter
  in the middle and swallowed by the cloudiness of the low tiers.
      I SPLITTER   one small shard, broken off slanted, cloudy
      II SCHERBE   a bigger shard with a small second point beside it
      III KRISTALL a clean six-sided prism with its point
      IV HERZSTEIN double-pointed, two small side crystals, a glowing heart
      V STERNSTEIN a star cluster of points round a middle crystal, burning
  GEMS (cut): round, flat, symmetric, milky like moonstone with the sheen of their family. The sign is CUT INTO the stone: a groove whose upper
  edge lies in shadow and whose lower edge catches the light, glowing silver-white from the third tier.
      I ROHSCHLIFF a roughly rounded pebble, matt, the sign scratched in
      II TROPFEN   a polished drop with one glint
      III LINSE    a round lens with a set-off rim
      IV FACETTE   an octagonal cut, colour playing in its facets
      V KRONE      a rose cut with a crown, full play of colour

  assets/magic/crystals/<id>.png       16x16 icon (lit from the top left, ink outline 1b1a2e, one piece with a 1 px margin)
  assets/magic/crystals/<id>_big.png   32x32 for the item card (the sign reads well here; tier V gets sparkles)
  assets/magic/staff_stones.png        the little stones on the held staff: 7x10 cells, column = `mini` in data/spells.json, row 0 lit, row 1 empty
  docs/img/crystals.png                contact sheet: both sets, every tier, big and as icons

  py -3 tools/art_crystals.py            writes everything
"""
import math
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "magic"
INK = (0x1B, 0x1A, 0x2E)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


# ---------------------------------------------------------------- palettes
# Each spell crystal has its own ramp (dark .. light, six steps) inside its school: Bannlicht a sunlit teal, Wurzelgrund a deep moss green.
SPELLS = {
    "banish": {"ramp": ["0d2b33", "134f57", "1d8282", "3fbcad", "8de9d4", "e4fff5"], "glow": "f6fffa", "glow_edge": "9ff5e4", "glyph": "banish"},
    "roots": {"ramp": ["132b16", "21491c", "387626", "66aa38", "a8e374", "eefcd0"], "glow": "f6ffd8", "glow_edge": "b8ff7a", "glyph": "roots"},
    # Glutschwarm: a coal crystal, deep ember red at the foot, burning orange, a yellow-white heart
    "embers": {"ramp": ["2e0f0a", "5c1a0c", "9c3412", "e0661e", "ffad4a", "fff0c0"], "glow": "fff6d8", "glow_edge": "ffc65a", "glyph": "embers"},
    # Nebelschleier: milky moonstone lilac, cold and pale, the sign a veiled eye
    "veil": {"ramp": ["1f1a3a", "363064", "5a5598", "8e8aca", "c6c3ee", "f6f4ff"], "glow": "fbfaff", "glow_edge": "c8bfff", "glyph": "veil"},
    # Leerenschlund: black void glass, violet at the edges, a magenta glow from inside
    "maw": {"ramp": ["06030c", "170a2a", "2e1450", "5a2496", "a64ce0", "f0b8ff"], "glow": "ffd6fb", "glow_edge": "ff4fd8", "glyph": "maw"},
}
# Gems: one milky body for both, the family's sheen over it (Brennglas warm gold with a rose second fire, Wildwuchs pearl green with lilac).
MILK = ["3e3a52", "6a6584", "9a94b4", "c6c1da", "e6e3f2", "fbfaff"]
GEMS = {
    "lens": {"sheen": "5fe0cc", "fire": "fff0b8", "glyph": "lens"},  # Licht: lantern teal, a warm white fire in the facets
    "wild": {"sheen": "8fe05a", "fire": "f0ffb0", "glyph": "wild"},  # Natur: witch green, a pale spring fire
    "tinder": {"sheen": "ff8a3c", "fire": "ffe6a0", "glyph": "tinder"},  # Glut: ember orange, a yellow fire in the facets
    "haze": {"sheen": "a99cff", "fire": "f6f2ff", "glyph": "haze"},  # Nebel: pale lilac, a white mist fire
    "hunger": {"sheen": "a24ce0", "fire": "ff4fd8", "glyph": "hunger"},  # Leere: void violet, a magenta fire
}

# ---------------------------------------------------------------- the signs (small for the icons, big for the cards)
GLYPHS = {
    "tinder": (
        ["..#..",
         ".##..",
         ".#.#.",
         "#...#",
         ".###."],
        ["....#....",
         "...##....",
         "...#.#...",
         "..#..#...",
         "..#...#..",
         ".#..#..#.",
         ".#.#.#.#.",
         "..#...#..",
         "...###..."]),
    "haze": (
        ["#.#..",
         ".#.#.",
         ".....",
         "..#.#",
         ".#.#."],
        [".##......",
         "#..#..##.",
         "....##..#",
         ".........",
         "..##.....",
         ".#..#..##",
         "#....##..",
         ".........",
         "..#.##.#."]),
    "hunger": (
        [".###.",
         "#.#.#",
         "#...#",
         "#.#.#",
         ".###."],
        ["..#####..",
         ".#.#.#.#.",
         "#.......#",
         "#..###..#",
         "#..#.#..#",
         "#..###..#",
         "#.......#",
         ".#.#.#.#.",
         "..#####.."]),
    "embers": (
        ["..#..",
         ".#.#.",
         "#.#.#",
         "#.#.#",
         ".###."],
        ["....#....",
         "...##..#.",
         "..#.#....",
         ".#..##.#.",
         ".#.#..#..",
         "#..#.#.#.",
         "#.#...#.#",
         ".#.....#.",
         "..#####.."]),
    "veil": (
        [".###.",
         "#.#.#",
         ".###.",
         ".....",
         "#.#.#"],
        ["..#####..",
         ".#.....#.",
         "#..###..#",
         ".#.....#.",
         "..#####..",
         ".........",
         "##.##.##.",
         ".........",
         ".##.##.##"]),
    "maw": (
        ["#.#.#",
         ".#.#.",
         "#...#",
         ".#.#.",
         "#.#.#"],
        ["..#####..",
         ".#.....#.",
         "#.#.#.#.#",
         "#..#.#..#",
         "#...#...#",
         "#..#.#..#",
         "#.#.#.#.#",
         ".#.....#.",
         "..#####.."]),
    "banish": (
        [".###.",
         "#...#",
         "#.#.#",
         "#...#",
         ".###."],
        ["....#....",
         "..#####..",
         ".#.....#.",
         ".#..#..#.",
         "##.###.##",
         ".#..#..#.",
         ".#.....#.",
         "..#####..",
         "....#...."]),
    "roots": (
        ["#.#.#",
         ".###.",
         "#####",
         ".#.#.",
         "#...#"],
        [".##...##.",
         "..##.##..",
         "...###...",
         "....#....",
         "#########",
         "...#.#...",
         "..#..#.#.",
         ".#...#..#",
         ".#..#...."]),
    "lens": (
        ["#.#.#",
         ".###.",
         "..#..",
         ".....",
         "..#.."],
        ["#...#...#",
         ".#..#..#.",
         "..#.#.#..",
         "...###...",
         "....#....",
         ".........",
         "...#.#...",
         "....#....",
         "...#.#..."]),
    "wild": (
        [".###.",
         "#...#",
         "#.#.#",
         "#..#.",
         ".#..."],
        ["...###...",
         "..#...#..",
         ".#..#..#.",
         ".#.#.#.#.",
         ".#.#..#..",
         ".#..##...",
         "..#......",
         "...#...##",
         "....####."]),
}


def glyph(name, big):
    rows = GLYPHS[name][1 if big else 0]
    return np.array([[c == "#" for c in row] for row in rows], bool)


def hash2(x, y, s=0):
    v = math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
    return v - math.floor(v)


# ---------------------------------------------------------------- spell crystals: prisms
class Prism:
    """A crystal standing on `base` along `axis` (unit, y up negative), shaft `length` long and `half` wide, then a point `point` long.
    `cut` > 0: broken off slanted instead of pointed (that much rise across the width). `under` > 0: a point below too (double-terminated)."""

    def __init__(self, base, angle, length, half, point, cut=0.0, under=0.0, depth=0):
        self.bx, self.by = base
        self.ax, self.ay = math.sin(angle), -math.cos(angle)
        self.length, self.half, self.point, self.cut, self.under, self.depth = length, half, point, cut, under, depth

    def local(self, x, y):
        dx, dy = x - self.bx, y - self.by
        v = dx * self.ax + dy * self.ay  # along the axis
        u = dx * -self.ay + dy * self.ax  # across (+ = right)
        return u / self.half, v / self.length

    def inside(self, u, v):
        if abs(u) > 1.0:
            return False
        if self.under > 0.0 and v < 0.0:
            return v >= -self.under / self.length * (1.0 - abs(u))
        if v < -0.04 * (1.0 - u * u):
            return False
        if v <= 1.0:
            return True
        if self.cut > 0.0:
            return v <= 1.0 + self.cut * (u + 1.0) * 0.5 / self.length
        return v <= 1.0 + self.point / self.length * (1.0 - abs(u))


def spell_shapes(tier, s):
    """The prisms of a tier, drawn back to front (later ones in front); `s` = 1 for the icon, 2 for the card."""
    def P(x, y, ang, length, half, point, **kw):
        kw = {k: v * s for k, v in kw.items()}
        return Prism((x * s, y * s), math.radians(ang), length * s, half * s, point * s, **kw)
    if tier == 1:
        return [P(8.0, 13.6, 12, 7.2, 2.4, 0, cut=2.6)]
    if tier == 2:
        return [P(5.0, 13.6, -26, 4.2, 1.5, 1.8), P(8.6, 13.8, 8, 7.0, 2.6, 3.2)]
    if tier == 3:
        return [P(8.0, 13.8, 0, 6.6, 3.1, 3.6)]
    if tier == 4:
        return [P(5.6, 12.4, -32, 3.0, 1.4, 1.6), P(10.4, 12.4, 32, 2.8, 1.4, 1.6), P(8.0, 10.6, 0, 3.4, 3.0, 3.4, under=2.6)]
    return [P(7.4, 9.4, -58, 4.2, 1.3, 2.0), P(8.6, 9.4, 58, 4.2, 1.3, 2.0), P(7.6, 10.6, -118, 3.4, 1.2, 1.6), P(8.4, 10.6, 118, 3.4, 1.2, 1.6),
            P(8.0, 12.2, 0, 5.0, 2.5, 3.6, under=1.6)]


def render_spell(spell, tier, big):
    s = 2 if big else 1
    n = 16 * s
    pal = SPELLS[spell]
    ramp = [hexc(c) for c in pal["ramp"]]
    glow, glow_edge = hexc(pal["glow"]), hexc(pal["glow_edge"])
    shapes = spell_shapes(tier, s)
    img = np.zeros((n, n, 4), np.uint8)
    owner = np.full((n, n), -1, int)
    face = np.zeros((n, n), int)  # 0 left (lit), 1 front, 2 right (dark), 3 lit point facet, 4 shaded point facet
    lv = np.zeros((n, n))
    for k, pr in enumerate(shapes):
        for y in range(n):
            for x in range(n):
                u, v = pr.local(x + 0.5, y + 0.5)
                if not pr.inside(u, v):
                    continue
                owner[y, x] = k
                lv[y, x] = v
                if v > 1.0 or (pr.under > 0.0 and v < 0.0):
                    face[y, x] = 3 if u < 0.05 else 4
                else:
                    face[y, x] = 0 if u < -0.42 else (1 if u < 0.38 else 2)
    main = len(shapes) - 1
    cloud = {1: 0.42, 2: 0.22}.get(tier, 0.0)
    core_strength = {1: 0.0, 2: 0.15, 3: 0.35, 4: 0.75, 5: 1.0}[tier]
    pr = shapes[main]
    cx, cy = pr.bx + pr.ax * pr.length * 0.45, pr.by + pr.ay * pr.length * 0.45
    for y in range(n):
        for x in range(n):
            k = owner[y, x]
            if k < 0:
                continue
            f = face[y, x]
            idx = {0: 3, 1: 2, 2: 1, 3: 4, 4: 2}[f]
            if k != main:
                idx = max(idx - 1, 0)  # the side crystals stand a little in shadow
            # the heart: light from inside, strongest at the middle of the main crystal
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / (pr.half * 1.6)
            heart = core_strength * max(0.0, 1.0 - d)
            if heart > 0.55 or (heart > 0.25 and (x + y) % 2 == 0):
                idx = min(idx + 1, 5)
            # the foot sits in shade
            if lv[y, x] < 0.12 and pr.under == 0.0 and f in (1, 2):
                idx = max(idx - 1, 0)
            colour = ramp[idx]
            if cloud > 0.0 and hash2(x // s, y // s, 3) < cloud:
                colour = mix(colour, (0xE8, 0xEC, 0xF4), 0.35)
            img[y, x, :3] = colour
            img[y, x, 3] = 255
    # facet edges: a bright line on the lit edge of the front face, a darker one before the shaded side
    for y in range(n):
        for x in range(n):
            if owner[y, x] < 0:
                continue
            if face[y, x] == 1 and x > 0 and owner[y, x - 1] == owner[y, x] and face[y, x - 1] == 0:
                img[y, x, :3] = ramp[4] if owner[y, x] == main else ramp[3]
            if face[y, x] == 2 and x > 0 and owner[y, x - 1] == owner[y, x] and face[y, x - 1] == 1 and big:
                img[y, x, :3] = ramp[1]
    # seams: where a crystal stands in front of another, the one behind gets a dark edge, so every point reads on its own
    for y in range(n):
        for x in range(n):
            k = owner[y, x]
            if k < 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < n and 0 <= yy < n and owner[yy, xx] > k:
                    img[y, x, :3] = ramp[0]
                    break
    # the shoulder where the shaft turns into the point: a lit line on the left, a shaded one on the right
    for y in range(1, n):
        for x in range(n):
            if owner[y, x] >= 0 and owner[y - 1, x] == owner[y, x] and face[y, x] in (0, 1, 2) and face[y - 1, x] in (3, 4):
                img[y - 1, x, :3] = ramp[5] if face[y - 1, x] == 3 else ramp[3]
    # the sign inside: on the main crystal, broken by a pixel at each facet edge (refraction), dim where it is cloudy
    g = glyph(SPELLS[spell]["glyph"], big)
    gh, gw = g.shape
    gx0 = int(round(cx - gw / 2.0))
    gy0 = int(round(cy - gh / 2.0)) + (1 if not big else 1)
    shift = {0: 1, 1: 0, 2: -1, 3: 0, 4: 0}
    strength = {1: 0.45, 2: 0.7, 3: 0.9, 4: 1.0, 5: 1.0}[tier]
    for y in range(n):
        for x in range(n):
            if owner[y, x] != main:
                continue
            gx = x - gx0 + shift[face[y, x]]
            gy = y - gy0
            if 0 <= gx < gw and 0 <= gy < gh and g[gy, gx]:
                if cloud > 0.0 and hash2(x, y, 9) < cloud * 0.9:
                    continue  # swallowed by the cloud
                mid = math.hypot(gx - (gw - 1) / 2.0, gy - (gh - 1) / 2.0) / (gw / 2.0)
                tone = mix(glow_edge, glow, max(0.0, 1.0 - mid) * 0.9)
                img[y, x, :3] = mix(tuple(int(c) for c in img[y, x, :3]), tone, strength)
    # glints over the sign: a short streak on the upper left of the front face hides a part of it
    for i in range(3 if big else 2):
        t = 0.62 + 0.08 * i
        x = int(pr.bx + pr.ax * pr.length * t - pr.half * 0.35 + i * 0.4)
        y = int(pr.by + pr.ay * pr.length * t)
        if 0 <= x < n and 0 <= y < n and owner[y, x] == main and face[y, x] in (0, 1):
            img[y, x, :3] = ramp[5]
    return img, owner >= 0


def outline(img, mask):
    n = img.shape[0]
    out = img.copy()
    for y in range(n):
        for x in range(n):
            if mask[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < n and 0 <= yy < n and mask[yy, xx]:
                    out[y, x, :3] = INK
                    out[y, x, 3] = 255
                    break
    return out


def sparkles(img, colour, count, seed):
    """Tier V on the card: little four-pointed stars round the stone (loose pixels are fine on the card)."""
    n = img.shape[0]
    spots = [(3, 4), (27, 6), (5, 25), (28, 23), (16, 2)]
    for k in range(count):
        x, y = spots[(k + seed) % len(spots)]
        for dx, dy, a in ((0, 0, 255), (1, 0, 140), (-1, 0, 140), (0, 1, 140), (0, -1, 140)):
            xx, yy = x + dx, y + dy
            if 0 <= xx < n and 0 <= yy < n and img[yy, xx, 3] == 0:
                img[yy, xx, :3] = colour if (dx, dy) == (0, 0) else mix(colour, (0, 0, 0), 0.2)
                img[yy, xx, 3] = a
    return img


# ---------------------------------------------------------------- gems: cut stones seen from the front
def gem_shape(tier, s, x, y):
    """(inside, girdle): is this pixel (centre coords) part of the stone, and does it belong to the lower band that shows its thickness."""
    cx, cy = 8.0 * s, 7.6 * s
    px, py = (x - cx) / s, (y - cy) / s
    if tier == 1:
        r = 4.6 + 0.55 * math.sin(math.atan2(py, px) * 3.0 + 1.0) + 0.35 * math.sin(math.atan2(py, px) * 5.0)
        return math.hypot(px / 1.12, py) <= r, False
    if tier == 2:
        body = math.hypot(px, py - 1.2) <= 4.2
        top = py < 1.2 and abs(px) <= (py + 5.6) * 0.62 and py >= -5.6
        return body or top, False
    if tier == 3:
        inside = math.hypot(px, py) <= 4.9 or (math.hypot(px, py - 1.0) <= 4.9 and py > 0)
        return inside, inside and math.hypot(px, py) > 4.9
    if tier == 4:
        a = math.atan2(py, px)
        rr = 5.4 / math.cos(((a + math.pi / 8) % (math.pi / 4)) - math.pi / 8)
        inside = math.hypot(px, py) <= rr or (math.hypot(px, py - 1.0) <= rr and py > 0)
        return inside, inside and math.hypot(px, py) > rr
    rr = 5.8
    inside = math.hypot(px, py) <= rr or (math.hypot(px, py - 1.0) <= rr and py > 0)
    return inside, inside and math.hypot(px, py) > rr


def render_gem(gem, tier, big):
    s = 2 if big else 1
    n = 16 * s
    pal = GEMS[gem]
    sheen, fire = hexc(pal["sheen"]), hexc(pal["fire"])
    milk = [mix(hexc(c), sheen, 0.5 if i < 3 else 0.38) for i, c in enumerate(MILK)]  # a milky body in the colour of its school
    img = np.zeros((n, n, 4), np.uint8)
    mask = np.zeros((n, n), bool)
    girdle = np.zeros((n, n), bool)
    cx, cy = 8.0 * s, 7.6 * s
    for y in range(n):
        for x in range(n):
            ins, gird = gem_shape(tier, s, x + 0.5, y + 0.5)
            mask[y, x] = ins
            girdle[y, x] = gird
    radius = {1: 4.8, 2: 4.6, 3: 4.9, 4: 5.4, 5: 5.8}[tier] * s
    for y in range(n):
        for x in range(n):
            if not mask[y, x]:
                continue
            px, py = (x + 0.5 - cx) / radius, (y + 0.5 - cy) / radius
            if girdle[y, x]:  # the stone's thickness under its face
                colour = mix(milk[1], sheen, 0.25) if (x // s) % 2 else mix(milk[2], sheen, 0.2)
                img[y, x, :3] = colour
                img[y, x, 3] = 255
                continue
            light = 0.55 - 0.35 * px - 0.45 * py  # lit from the top left
            if tier == 1:
                light = 0.5 - 0.25 * px - 0.3 * py + 0.12 * (hash2(x // s, y // s, 5) - 0.5)  # matt: soft and blotchy
                idx = 1 + int(np.clip(light * 3.0, 0, 2.99))
            else:
                dome = 1.0 - min(1.0, math.hypot(px, py))
                idx = int(np.clip((light + dome * 0.5) * 4.2, 0, 5))
            colour = milk[idx]
            sheen_k = 0.18 + 0.1 * tier
            band = math.sin((px * 2.0 - py * 1.4) * (2.5 + tier * 0.6)) * 0.5 + 0.5  # the sheen drifts across in a soft band
            colour = mix(colour, sheen, sheen_k * band)
            if tier >= 3:  # the set-off rim of a lens and the cuts beyond it
                rim = math.hypot(px, py)
                if rim > 0.78:
                    colour = mix(milk[4], sheen, 0.3) if (px + py) < 0 else mix(milk[1], sheen, 0.2)
            if tier >= 4:  # facets: wedges round a table, alternating light and shade, some burning in the second colour
                a = math.atan2(py, px)
                wedges = 8 if tier == 4 else 16
                w = int(((a + math.pi) / (2 * math.pi)) * wedges) % wedges
                rim = math.hypot(px, py)
                table = 0.42 if tier == 4 else 0.34
                if rim > table and rim <= 0.78:
                    lit_side = math.cos(a + math.pi * 0.75) > 0  # facing the light at the top left
                    colour = mix(milk[4] if lit_side else milk[2], sheen if (w % 2 == 0) else fire, 0.35 if (w + tier) % 3 else 0.6)
                elif rim <= table:
                    colour = mix(milk[5], sheen, 0.2)
            img[y, x, :3] = colour
            img[y, x, 3] = 255
    # glints: the polished ones get a bright spot at the top left
    if tier >= 2:
        gx, gy = int(cx - radius * 0.45), int(cy - radius * 0.5)
        for dx, dy in ((0, 0), (1, 0), (0, 1)) if big else ((0, 0),):
            if mask[gy + dy, gx + dx]:
                img[gy + dy, gx + dx, :3] = (255, 255, 255)
    # the sign cut in: a groove (dark upper edge, lit lower edge), glowing silver-white from tier III
    g = glyph(pal["glyph"], big)
    gh, gw = g.shape
    gx0, gy0 = int(round(cx - gw / 2.0)), int(round(cy - gh / 2.0))
    cut = np.zeros((n, n), bool)
    for gy in range(gh):
        for gx in range(gw):
            if g[gy, gx]:
                x, y = gx0 + gx, gy0 + gy
                if 0 <= x < n and 0 <= y < n and mask[y, x] and not girdle[y, x]:
                    cut[y, x] = True
    for y in range(n):
        for x in range(n):
            if not cut[y, x]:
                continue
            here = tuple(int(c) for c in img[y, x, :3])
            if tier <= 2:
                img[y, x, :3] = mix(here, milk[0], 0.55 if tier == 1 else 0.7)
            else:
                img[y, x, :3] = mix((0xF4, 0xF6, 0xFF), sheen, 0.12 if tier == 3 else 0.06)
            if big or tier >= 3:
                if y > 0 and mask[y - 1, x] and not cut[y - 1, x] and not girdle[y - 1, x]:
                    img[y - 1, x, :3] = mix(tuple(int(c) for c in img[y - 1, x, :3]), milk[0], 0.45)
                if y + 1 < n and mask[y + 1, x] and not cut[y + 1, x] and not girdle[y + 1, x]:
                    img[y + 1, x, :3] = mix(tuple(int(c) for c in img[y + 1, x, :3]), (255, 255, 255), 0.35)
    return img, mask


def check_icon(name, img):
    pts = {(x, y) for y in range(16) for x in range(16) if img[y, x, 3]}
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    assert min(xs) >= 1 and max(xs) <= 14 and min(ys) >= 1 and max(ys) <= 14, "%s leaves the frame: x %d..%d y %d..%d" % (name, min(xs), max(xs), min(ys), max(ys))
    seen, stack = set(), [next(iter(pts))]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        stack += [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (x + dx, y + dy) in pts]
    assert len(seen) == len(pts), "%s has %d loose pixels" % (name, len(pts) - len(seen))


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, "RGBA").save(path)


# ---------------------------------------------------------------- the staff's little stones
def staff_stones():
    """7x10 cells: column 0 Bannlicht, 1 Wurzelgrund, 2 Brennglas, 3 Wildwuchs, 4 Glutschwarm, 5 Nebelschleier, 6 Leerenschlund, 7 Zunder, 8 Dunst, 9 Hunger (`mini` in
    data/spells.json); row 0 lit, row 1 empty (dark, dull)."""
    w, h = 7, 10
    sheet = np.zeros((h * 2, w * 10, 4), np.uint8)
    for col, spell in ((0, "banish"), (1, "roots"), (4, "embers"), (5, "veil"), (6, "maw")):
        ramp = [hexc(c) for c in SPELLS[spell]["ramp"]]
        glow = hexc(SPELLS[spell]["glow"])
        pr = Prism((3.5, 9.6), 0.0, 4.2, 2.3, 3.6)
        for row in range(2):
            for y in range(h):
                for x in range(w):
                    u, v = pr.local(x + 0.5, y + 0.5)
                    if not pr.inside(u, v):
                        continue
                    if v > 1.0:
                        idx = 4 if u < 0.05 else 2
                    else:
                        idx = 3 if u < -0.42 else (2 if u < 0.38 else 1)
                    colour = ramp[idx] if row == 0 else mix(ramp[max(idx - 2, 0)], (0x2A, 0x26, 0x3A), 0.45)
                    if row == 0 and -0.5 < u < 0.38 and 0.3 < v < 0.7:
                        colour = ramp[3]  # a faint heart of light inside the front face, no brighter than the lit side
                    if row == 0 and u < -0.42 and 0.35 < v < 0.95:
                        colour = ramp[4]  # the lit left face catches the light along its edge
                    sheet[row * h + y, col * w + x, :3] = colour
                    sheet[row * h + y, col * w + x, 3] = 255
            if row == 0:  # one glint at the top left of the point
                sheet[row * h + 3, col * w + 2, :3] = glow
            # ink round it
            cell = sheet[row * h:(row + 1) * h, col * w:(col + 1) * w]
            m = cell[:, :, 3] > 0
            for y in range(h):
                for x in range(w):
                    if not m[y, x] and any(0 <= x + dx < w and 0 <= y + dy < h and m[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        cell[y, x, :3] = INK
                        cell[y, x, 3] = 255
    for col, gem in ((2, "lens"), (3, "wild"), (7, "tinder"), (8, "haze"), (9, "hunger")):
        sheen = hexc(GEMS[gem]["sheen"])
        milk = [mix(hexc(c), sheen, 0.5) for c in MILK]
        for row in range(2):
            for y in range(5):
                for x in range(5):
                    px, py = x - 2.0, y - 2.0
                    if px * px + py * py > 5.0:
                        continue
                    lit = 0.6 - 0.25 * px - 0.3 * py
                    colour = mix(milk[2 + int(np.clip(lit * 3, 0, 3))], sheen, 0.45)
                    if (x, y) == (1, 1):
                        colour = (255, 255, 255)
                    if row == 1:
                        colour = mix(colour, (0x2A, 0x26, 0x3A), 0.55)
                    sheet[row * h + 5 + y, col * w + 1 + x, :3] = colour
                    sheet[row * h + 5 + y, col * w + 1 + x, 3] = 255
    save(sheet, OUT / "staff_stones.png")



def staff_stones_small():
    """The Bleichgabel's claws are small: 5x7 cells in the same columns (`mini`), a slim crystal with its ink outline, a gem as a 3x3 pearl in
    the lower middle of its cell; row 0 lit, row 1 empty (dark, dull). assets/magic/staff_stones_small.png"""
    w, h = 5, 7
    sheet = np.zeros((h * 2, w * 10, 4), np.uint8)
    for col, spell in ((0, "banish"), (1, "roots"), (4, "embers"), (5, "veil"), (6, "maw")):
        ramp = [hexc(c) for c in SPELLS[spell]["ramp"]]
        glow = hexc(SPELLS[spell]["glow"])
        pr = Prism((2.5, 6.4), 0.0, 2.4, 1.5, 2.4)
        for row in range(2):
            for y in range(h):
                for x in range(w):
                    u, v = pr.local(x + 0.5, y + 0.5)
                    if not pr.inside(u, v):
                        continue
                    if v > 1.0:
                        idx = 4 if u < 0.05 else 2
                    else:
                        idx = 4 if u < -0.3 else (2 if u < 0.3 else 1)
                    colour = ramp[idx] if row == 0 else mix(ramp[max(idx - 2, 0)], (0x2A, 0x26, 0x3A), 0.45)
                    sheet[row * h + y, col * w + x, :3] = colour
                    sheet[row * h + y, col * w + x, 3] = 255
            if row == 0:
                sheet[row * h + 2, col * w + 2, :3] = glow  # the glint at the point
            cell = sheet[row * h:(row + 1) * h, col * w:(col + 1) * w]
            m = cell[:, :, 3] > 0
            for y in range(h):
                for x in range(w):
                    if not m[y, x] and any(0 <= x + dx < w and 0 <= y + dy < h and m[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        cell[y, x, :3] = INK
                        cell[y, x, 3] = 255
    for col, gem in ((2, "lens"), (3, "wild"), (7, "tinder"), (8, "haze"), (9, "hunger")):
        sheen = hexc(GEMS[gem]["sheen"])
        milk = [mix(hexc(c), sheen, 0.5) for c in MILK]
        for row in range(2):
            for y in range(3):
                for x in range(3):
                    corner = (x != 1 and y != 1)
                    colour = mix(milk[2 if corner else 3], sheen, 0.45)
                    if (x, y) == (0, 0):
                        colour = mix(milk[1], sheen, 0.4)  # the corners round it off
                    if (x, y) == (2, 2):
                        colour = mix(milk[0], sheen, 0.4)
                    if (x, y) == (1, 0) or (x, y) == (0, 1):
                        colour = mix(milk[4], sheen, 0.3)
                    if (x, y) == (1, 1):
                        colour = (255, 255, 255) if row == 0 else mix(milk[4], sheen, 0.3)
                    if row == 1:
                        colour = mix(colour, (0x2A, 0x26, 0x3A), 0.55)
                    sheet[row * h + 4 + y, col * w + 1 + x, :3] = colour
                    sheet[row * h + 4 + y, col * w + 1 + x, 3] = 255
    save(sheet, OUT / "staff_stones_small.png")

# ---------------------------------------------------------------- everything
def main():
    pictures = {}
    for spell in SPELLS:
        for tier in range(1, 6):
            base = "crystal_%s_%d" % (spell, tier)
            icon, mask = render_spell(spell, tier, False)
            icon = outline(icon, mask)
            check_icon(base, icon)
            big, bmask = render_spell(spell, tier, True)
            big = outline(big, bmask)
            if tier == 5:
                big = sparkles(big, hexc(SPELLS[spell]["glow"]), 4, 0)
            save(icon, OUT / "crystals" / (base + ".png"))
            save(big, OUT / "crystals" / (base + "_big.png"))
            pictures[base] = (icon, big)
    for gem in GEMS:
        for tier in range(1, 6):
            base = "gem_%s_%d" % (gem, tier)
            icon, mask = render_gem(gem, tier, False)
            icon = outline(icon, mask)
            check_icon(base, icon)
            big, bmask = render_gem(gem, tier, True)
            big = outline(big, bmask)
            if tier == 5:
                big = sparkles(big, hexc(GEMS[gem]["sheen"]), 4, 2)
            save(icon, OUT / "crystals" / (base + ".png"))
            save(big, OUT / "crystals" / (base + "_big.png"))
            pictures[base] = (icon, big)
    staff_stones()
    staff_stones_small()
    contact(pictures)
    print("crystals written", file=sys.stderr)


def contact(pictures):
    """docs/img/crystals.png: one row per stone kind, the five tiers side by side, each big (x4) with its icon (x4) under it."""
    rows = ["crystal_banish", "crystal_roots", "crystal_embers", "crystal_veil", "crystal_maw", "gem_lens", "gem_wild", "gem_tinder", "gem_haze", "gem_hunger"]
    cell_w, cell_h = 32 * 4 + 16, 32 * 4 + 16 * 4 + 24
    sheet = Image.new("RGBA", (cell_w * 5 + 16, cell_h * len(rows) + 16), (18, 13, 34, 255))
    for r, base in enumerate(rows):
        for t in range(5):
            icon, big = pictures["%s_%d" % (base, t + 1)]
            b = Image.fromarray(big, "RGBA").resize((128, 128), Image.NEAREST)
            i = Image.fromarray(icon, "RGBA").resize((64, 64), Image.NEAREST)
            x0, y0 = 8 + t * cell_w, 8 + r * cell_h
            sheet.alpha_composite(b, (x0 + 8, y0 + 4))
            sheet.alpha_composite(i, (x0 + 8 + 32, y0 + 4 + 136))
    (ROOT / "docs" / "img").mkdir(parents=True, exist_ok=True)
    sheet.save(ROOT / "docs" / "img" / "crystals.png")


if __name__ == "__main__":
    main()
