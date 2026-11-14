#!/usr/bin/env python3
"""Etappe 2 Market Day plaza bunting overlay (`plaza_market.png` & `plaza_market_glow.png`, 208x136).
Aligns pixel-for-pixel with `plaza_2.png` and `plaza_3.png` (`W=208, H=136, CX=104, CY=70, RX=98, RY=60, feet row=78`).

Features:
- 4 small carved oak corner posts with warm gold caps set along the northern & southern stone curb arcs:
  - NW & NE posts along the top-northern rim (with a graceful festive bunting arc spanning overhead above `y=20`)
  - SW & SE posts along the bottom-southern rim (with a low festive bunting garland arcing along the front rim)
- Festive cloth pennant strings in warm marigold (`#e6c468`/`#ffb852`), berry crimson (`#b8465a`/`#d0384e`),
  and turquoise (`#3cc0c6`), interspersed with tiny hanging warm-amber lanterns (`WARM_GLOW`) and subtle teal
  ribbon/runic charms (`RUNE_GLOW`).
- Two tiny floral market crates/baskets tucked ONLY at the northern top rim and bottom rim corner of the stone oval.
- Keeps the center fountain (`x=76..132, y=20..88`), the inner walkway, and both left/right caravan slots
  (`x < 56` and `x > 152` near `y=45..95`) 100% clear!

Run:
  py -3 tools/art_market.py [optional_preview_contact.png]
"""
from pathlib import Path
import math
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets" / "town"

# Exact geometry & palettes matching tools/art_plaza.py and docs/design_guide.md
W, H = 208, 136
CX, CY = 104.0, 70.0
RX, RY = 98.0, 60.0
FEET_ROW = 78


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.int32)


INK = hexc("1b1a2e")
ROPE = [hexc("4a3828"), hexc("7c6244"), hexc("b29268")]

# Carved warm plum-oak post wood (4 tonal steps, top-left lit, cool-violet shadow)
OAK = [hexc("2c1e2e"), hexc("4f3646"), hexc("7c575c"), hexc("ad837c")]
CRATE_WOOD = [hexc("33222e"), hexc("5c3e44"), hexc("8c645c"), hexc("ba907e")]
WICKER = [hexc("463322"), hexc("765836"), hexc("a8844e"), hexc("d6b474")]

# Exact art_plaza.py metallic & emissive palettes
GOLD_TRIM = [hexc("583e1c"), hexc("8e692c"), hexc("c89c4c"), hexc("f0cf7e")]
RUNE_GLOW = [hexc("2a8c94"), hexc("3cc0c6"), hexc("78f4e6"), hexc("d0fff8")]
WARM_GLOW = [hexc("9a4418"), hexc("e07c28"), hexc("ffb852"), hexc("fff0b0")]

# Festive cloth pennant ramps (shadow -> mid -> lit -> highlight)
PENNANT_MARIGOLD = [hexc("8e5c24"), hexc("c98c38"), hexc("e6c468"), hexc("ffb852")]
PENNANT_CRIMSON = [hexc("682238"), hexc("923148"), hexc("b8465a"), hexc("d0384e")]
PENNANT_TURQUOISE = [hexc("1c5866"), hexc("2a8c94"), hexc("3cc0c6"), hexc("78f4e6")]

# Foliage & blossoms for the two tiny floral market crates/baskets
LEAF = [hexc("22483c"), hexc("2f624e"), hexc("55985f"), hexc("7cb96d")]
BLOOM_ROSE = [hexc("8e3252"), hexc("cc5a78"), hexc("f2a0c8")]
BLOOM_GOLD = [hexc("b47828"), hexc("e6b44c"), hexc("fff0b0")]
BLOOM_LILAC = [hexc("583c8c"), hexc("8e6ec8"), hexc("cbaaff")]


def bayer(x, y):
    m = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    return m[y % 4][x % 4] / 16.0


class Canvas:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.arr = np.zeros((h, w, 4), np.uint8)
        self.glow = np.zeros((h, w, 4), np.uint8)

    def put(self, x, y, col, a=255):
        ix, iy = int(x), int(y)
        if 0 <= ix < self.w and 0 <= iy < self.h and a > 0:
            if a == 255 or self.arr[iy, ix, 3] == 0:
                self.arr[iy, ix] = (int(col[0]), int(col[1]), int(col[2]), int(a))
            else:
                # Alpha blend over existing pixel (e.g. contact shadow)
                sa = a / 255.0
                da = self.arr[iy, ix, 3] / 255.0
                oa = sa + da * (1.0 - sa)
                if oa > 0:
                    rgb = (np.array(col[:3], float) * sa + self.arr[iy, ix, :3].astype(float) * da * (1.0 - sa)) / oa
                    self.arr[iy, ix] = (int(rgb[0]), int(rgb[1]), int(rgb[2]), int(round(oa * 255)))

    def put_outline_if_empty(self, x, y, col=INK):
        ix, iy = int(x), int(y)
        if 0 <= ix < self.w and 0 <= iy < self.h:
            if self.arr[iy, ix, 3] < 140:
                self.arr[iy, ix] = (int(col[0]), int(col[1]), int(col[2]), 255)

    def shine(self, x, y, col, a=255):
        ix, iy = int(x), int(y)
        if 0 <= ix < self.w and 0 <= iy < self.h and a > 0:
            if a >= self.glow[iy, ix, 3]:
                self.glow[iy, ix] = (int(col[0]), int(col[1]), int(col[2]), int(min(255, a)))

    def clear_shine(self, x, y):
        ix, iy = int(x), int(y)
        if 0 <= ix < self.w and 0 <= iy < self.h:
            self.glow[iy, ix] = (0, 0, 0, 0)


def draw_shadow_ellipse(c: Canvas, cx: float, cy: float, rx: float, ry: float):
    """Subtle cool-dark contact shadow under a post or crate on the stone curb."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if 0 <= x < c.w and 0 <= y < c.h and c.arr[y, x, 3] == 0:
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                if d < 1.0:
                    alpha = 105 if d < 0.55 else (65 if bayer(x, y) < (1.0 - d) * 1.8 else 0)
                    if alpha > 0:
                        c.put(x, y, INK, alpha)


def draw_carved_oak_post(c: Canvas, bx: int, by: int, height: int = 16, lantern_dir: int = 0):
    """Draws a crisp 3/4 carved oak corner post anchored at feet `(bx, by)`, with:
    - octagonal stone/oak plinth base
    - carved oak shaft with warm gold collar ring & teal runic tie-ribbon
    - warm gold finial cap (`GOLD_TRIM`)
    - optional small iron hook & warm amber lantern (`lantern_dir` = -1 left, +1 right, 0 none)
    Returns `(top_x, tie_y)` where the pennant rope attaches.
    """
    draw_shadow_ellipse(c, bx + 0.5, by + 0.6, 4.6, 1.9)

    top_y = by - height

    # 1. Carved oak plinth base (rows by-2 .. by), 5px wide + 1px INK outline -> x in bx-3..bx+3
    for dy, hw in ((0, 2), (-1, 2), (-2, 2)):
        y = by + dy
        c.put(bx - hw - 1, y, INK)
        c.put(bx + hw + 1, y, INK)
        for dx in range(-hw, hw + 1):
            if dy == 0:
                col = OAK[1] if dx >= 0 else OAK[2]
            elif dy == -2:
                col = GOLD_TRIM[3 if dx < 0 else (2 if dx == 0 else 1)]  # brass base molding
            else:
                col = OAK[3 if dx < 0 else (2 if dx == 0 else 1)]
            c.put(bx + dx, y, col)
    # Bottom ink edge under plinth
    for dx in range(-2, 3):
        c.put(bx + dx, by + 1, INK)

    # 2. Carved oak shaft (rows top_y+3 .. by-3), 3px wide (bx-1, bx, bx+1) + 1px INK outline at bx-2, bx+2
    ribbon_y = top_y + 6
    collar_y = top_y + 3
    for y in range(top_y + 3, by - 2):
        c.put(bx - 2, y, INK)
        c.put(bx + 2, y, INK)
        if y == collar_y:
            # Warm gold neck collar under finial
            c.put(bx - 1, y, GOLD_TRIM[3])
            c.put(bx, y, GOLD_TRIM[2])
            c.put(bx + 1, y, GOLD_TRIM[1])
        elif y == ribbon_y:
            # Festive turquoise runic ribbon band wrapped around post
            c.put(bx - 1, y, PENNANT_TURQUOISE[3])
            c.put(bx, y, PENNANT_TURQUOISE[2])
            c.put(bx + 1, y, PENNANT_TURQUOISE[1])
            c.shine(bx - 1, y, RUNE_GLOW[2], 175)
            c.shine(bx, y, RUNE_GLOW[1], 125)
        elif y == by - 6:
            # Subtle carved notch ring in oak
            c.put(bx - 1, y, OAK[2])
            c.put(bx, y, OAK[1])
            c.put(bx + 1, y, OAK[0])
        else:
            # Crisp cylindrical top-left lighting (left highlight, mid center, cool shadow right)
            c.put(bx - 1, y, OAK[3 if y < top_y + 8 else 2])
            c.put(bx, y, OAK[2])
            c.put(bx + 1, y, OAK[1 if y < by - 5 else 0])

    # Small fluttering teal ribbon knot on the outer side of the post
    rib_side = -1 if bx < CX else 1
    rx_k = bx + rib_side * 2
    c.put(rx_k, ribbon_y + 1, PENNANT_TURQUOISE[2 if rib_side < 0 else 1])
    c.shine(rx_k, ribbon_y + 1, RUNE_GLOW[2], 160)
    for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        c.put_outline_if_empty(rx_k + ox, ribbon_y + 1 + oy, INK)

    # 3. Warm gold cap & acorn finial (rows top_y .. top_y+2)
    # Wide cap eaves at top_y + 2 (5px wide: bx-2..bx+2, INK at bx-3, bx+3)
    c.put(bx - 3, top_y + 2, INK)
    c.put(bx + 3, top_y + 2, INK)
    c.put(bx - 2, top_y + 2, GOLD_TRIM[3])
    c.put(bx - 1, top_y + 2, GOLD_TRIM[3])
    c.put(bx, top_y + 2, GOLD_TRIM[2])
    c.put(bx + 1, top_y + 2, GOLD_TRIM[1])
    c.put(bx + 2, top_y + 2, GOLD_TRIM[0])
    # Cap dome at top_y + 1 (3px wide: bx-1..bx+1, INK at bx-2, bx+2)
    c.put(bx - 2, top_y + 1, INK)
    c.put(bx + 2, top_y + 1, INK)
    c.put(bx - 1, top_y + 1, WARM_GLOW[3])  # gleaming top-left specular!
    c.put(bx, top_y + 1, GOLD_TRIM[3])
    c.put(bx + 1, top_y + 1, GOLD_TRIM[2])
    # Finial tip at top_y (1px at bx, INK around)
    c.put(bx - 1, top_y, INK)
    c.put(bx + 1, top_y, INK)
    c.put(bx, top_y, GOLD_TRIM[3])
    c.put(bx, top_y - 1, INK)

    # 4. Optional small side bracket lantern hung from the post
    if lantern_dir != 0:
        arm_y = top_y + 4
        lx = bx + lantern_dir * 4
        # Iron bracket arm from post out to lx
        for sx in range(1, 5):
            ax = bx + lantern_dir * sx
            c.put(ax, arm_y, INK)
            c.put_outline_if_empty(ax, arm_y - 1, GOLD_TRIM[1] if sx == 2 else INK)
        draw_mini_lantern(c, lx, arm_y + 1, warm=True)

    return bx, top_y + 4


def draw_mini_lantern(c: Canvas, lx: int, top_y: int, warm: bool = True):
    """Draws a crisp 3x4 hanging market lantern with 1px `#1b1a2e` outline and emissive glow."""
    # Cap at top_y
    c.put(lx, top_y, GOLD_TRIM[2])
    c.put_outline_if_empty(lx - 1, top_y, INK)
    c.put_outline_if_empty(lx + 1, top_y, INK)
    c.put_outline_if_empty(lx, top_y - 1, INK)

    # Glowing glass body (2 rows: top_y+1, top_y+2, 2px or 3px wide)
    pal = WARM_GLOW if warm else RUNE_GLOW
    for dy in (1, 2):
        y = top_y + dy
        c.put(lx - 2, y, INK)
        c.put(lx + 2, y, INK)
        c.put(lx - 1, y, pal[3 if dy == 1 else 2])
        c.put(lx, y, pal[3])
        c.put(lx + 1, y, pal[2 if dy == 1 else 1])
        # Emissive glow core
        c.shine(lx - 1, y, pal[3 if dy == 1 else 2], 235)
        c.shine(lx, y, pal[3], 255)
        c.shine(lx + 1, y, pal[2], 220)

    # Bottom brass base & outline
    c.put(lx - 1, top_y + 3, INK)
    c.put(lx, top_y + 3, GOLD_TRIM[1])
    c.put(lx + 1, top_y + 3, INK)
    c.put(lx, top_y + 4, INK)

    # Soft dithered halo in _glow.png around lantern center (lx, top_y + 1.5)
    for hy in range(top_y - 2, top_y + 6):
        for hx in range(lx - 4, lx + 5):
            hd = math.hypot((hx - lx) / 4.2, (hy - (top_y + 1.5)) / 4.2)
            if 0.42 < hd < 1.0 and bayer(hx, hy) < (1.0 - hd) * 0.75:
                c.shine(hx, hy, pal[1], 80)


def draw_teal_rune_charm(c: Canvas, cx_i: int, top_y: int):
    """Tiny glowing turquoise ribbon/crystal charm hanging between pennants."""
    # Gold clasp at rope
    c.put(cx_i, top_y, GOLD_TRIM[3])
    # 2px glowing teal crystal drop + crisp dark outline
    c.put(cx_i, top_y + 1, RUNE_GLOW[3])
    c.put(cx_i, top_y + 2, RUNE_GLOW[2])
    for ox, oy in ((-1, 0), (1, 0), (-1, 1), (1, 1), (-1, 2), (1, 2), (0, 3)):
        c.put_outline_if_empty(cx_i + ox, top_y + oy, INK)
    c.shine(cx_i, top_y + 1, RUNE_GLOW[3], 245)
    c.shine(cx_i, top_y + 2, RUNE_GLOW[2], 215)
    for ox, oy in ((-1, 1), (1, 1), (0, 0), (0, 3)):
        c.shine(cx_i + ox, top_y + oy, RUNE_GLOW[1], 75)


def draw_pennant_flag(c: Canvas, cx_f: int, rope_y: int, pal, style: int = 0):
    """Draws a crisp cloth pennant hanging from `(cx_f, rope_y)` with 1px `#1b1a2e` outline.
    `style == 0`: classic triangular bunting pennant (width 5 -> 3 -> 1, height 5px).
    `style == 1`: swallow-tail / notched royal pennant with gold header trim.
    """
    if style == 0:
        # Row 1: 5px wide (cx_f-2 .. cx_f+2)
        rows = [
            (1, -2, 2),
            (2, -2, 2),
            (3, -1, 1),
            (4, -1, 1),
            (5, 0, 0),
        ]
        # Outline pass first
        for dy, x0, x1 in rows:
            y = rope_y + dy
            c.put_outline_if_empty(cx_f + x0 - 1, y, INK)
            c.put_outline_if_empty(cx_f + x1 + 1, y, INK)
            for dx in range(x0, x1 + 1):
                c.put_outline_if_empty(cx_f + dx, y + 1, INK)
                c.put_outline_if_empty(cx_f + dx, y - 1, INK)
        # Fill cloth with directional top-left shading
        for dy, x0, x1 in rows:
            y = rope_y + dy
            for dx in range(x0, x1 + 1):
                if dy == 1 and dx <= 0:
                    col = pal[3]  # warm top-left sunlit cloth edge
                elif dx < 0 or (dx == 0 and dy <= 2):
                    col = pal[2]
                elif dx == 0 or dy <= 3:
                    col = pal[1]
                else:
                    col = pal[0]
                c.put(cx_f + dx, y, col)
    else:
        # Swallow-tail festive bannerette with warm gold header stitch
        rows = [
            (1, [-1, 0, 1]),
            (2, [-1, 0, 1]),
            (3, [-1, 0, 1]),
            (4, [-1, 1]),
        ]
        for dy, dxs in rows:
            y = rope_y + dy
            for dx in dxs:
                for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    c.put_outline_if_empty(cx_f + dx + ox, y + oy, INK)
        for dy, dxs in rows:
            y = rope_y + dy
            for dx in dxs:
                if dy == 1:
                    col = GOLD_TRIM[3 if dx <= 0 else 2]
                elif dx < 0:
                    col = pal[3 if dy == 2 else 2]
                elif dx == 0:
                    col = pal[2]
                else:
                    col = pal[1 if dy == 2 else 0]
                c.put(cx_f + dx, y, col)

    # Subtle turquoise silk glint if this is a turquoise pennant
    if pal is PENNANT_TURQUOISE:
        c.shine(cx_f - 1, rope_y + 2, RUNE_GLOW[2], 125)
        c.shine(cx_f, rope_y + 2, RUNE_GLOW[1], 95)


def draw_bunting_span(c: Canvas, x0: int, y0: int, x1: int, y1: int, sag: float, items: list):
    """Draws a catenary/parabolic rope from `(x0, y0)` to `(x1, y1)` with vertical sag `sag`
    (positive sags downward, negative arches upward/less sag), outlined cleanly in `INK`,
    then hangs pennants, warm lanterns, and teal runic charms at specified `u` positions.
    """
    def rope_pos(u: float):
        rx = x0 + (x1 - x0) * u
        ry = y0 + (y1 - y0) * u + sag * 4.0 * u * (1.0 - u)
        return rx, ry

    steps = max(abs(x1 - x0) * 3, 24)
    rope_pts = []
    seen = set()
    for s in range(steps + 1):
        u = s / float(steps)
        rx, ry = rope_pos(u)
        ix, iy = int(round(rx)), int(round(ry))
        if (ix, iy) not in seen:
            seen.add((ix, iy))
            rope_pts.append((ix, iy, u))

    # 1. Crisp dark 1px backing under/above rope so cord reads cleanly over bright stone or grass
    for ix, iy, _ in rope_pts:
        c.put_outline_if_empty(ix, iy + 1, INK)
        c.put_outline_if_empty(ix, iy - 1, INK)

    # 2. Braided warm hemp/gold cord pixels
    for idx, (ix, iy, u) in enumerate(rope_pts):
        col = GOLD_TRIM[2] if idx % 4 == 0 else (ROPE[2] if u < 0.5 else ROPE[1])
        c.put(ix, iy, col)

    # 3. Hang festive pennants, warm amber lanterns, and teal rune charms along the rope
    for u, kind, arg in items:
        rx, ry = rope_pos(u)
        ix, iy = int(round(rx)), int(round(ry))
        if kind == "pennant":
            pal, style = arg
            draw_pennant_flag(c, ix, iy, pal, style=style)
        elif kind == "lantern":
            draw_mini_lantern(c, ix, iy + 1, warm=arg)
        elif kind == "charm":
            draw_teal_rune_charm(c, ix, iy + 1)


def draw_floral_crate(c: Canvas, bx: int, by: int):
    """Draws a tiny carved wooden floral market crate (`~11x9` px) anchored at bottom `(bx, by)`,
    overflowing with meadow leaves, marigold/rose/lilac blossoms, and a tiny glowing teal dew-bud.
    """
    draw_shadow_ellipse(c, bx + 0.5, by + 0.5, 6.0, 2.1)

    # Wooden slatted crate box: x in bx-4..bx+4 (9px wide + INK at bx-5, bx+5), y in by-4..by
    for dy in range(-4, 1):
        y = by + dy
        for dx in range(-5, 6):
            c.clear_shine(bx + dx, y)
        c.put(bx - 5, y, INK)
        c.put(bx + 5, y, INK)
        for dx in range(-4, 5):
            # Corner posts at dx in (-4, 4)
            if dx in (-4, 4):
                col = OAK[3 if dx < 0 else 1]
            elif dy == -2:
                # Dark slat seam with subtle gold corner nail
                col = GOLD_TRIM[2] if dx in (-3, 3) else OAK[0]
            elif dy == -4:
                col = CRATE_WOOD[3 if dx < 1 else 2]
            elif dy == 0:
                col = CRATE_WOOD[1 if dx < 0 else 0]
            else:
                col = CRATE_WOOD[3 if dx < -1 else (2 if dx < 2 else 1)]
            c.put(bx + dx, y, col)
    # Bottom INK outline
    for dx in range(-4, 5):
        c.put(bx + dx, by + 1, INK)

    # Lush foliage cushion spilling over crate rim (y in by-7 .. by-4)
    foliage_clusters = [
        (-4, -5, LEAF[2]), (-3, -5, LEAF[3]), (-2, -5, LEAF[2]), (-1, -5, LEAF[1]),
        (0, -5, LEAF[2]), (1, -5, LEAF[3]), (2, -5, LEAF[2]), (3, -5, LEAF[1]), (4, -5, LEAF[0]),
        (-3, -6, LEAF[3]), (-2, -6, LEAF[2]), (-1, -6, LEAF[3]), (0, -6, LEAF[2]),
        (1, -6, LEAF[1]), (2, -6, LEAF[2]), (3, -6, LEAF[1]),
        (-2, -7, LEAF[2]), (0, -7, LEAF[3]), (1, -7, LEAF[2]),
    ]
    for dx, dy, _ in foliage_clusters:
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            c.put_outline_if_empty(bx + dx + ox, by + dy + oy, INK)
    for dx, dy, col in foliage_clusters:
        c.clear_shine(bx + dx, by + dy)
        c.put(bx + dx, by + dy, col)

    # Crisp colourful flower heads (2-3px clusters, never noisy single dots)
    # Left marigold cluster
    c.put(bx - 3, by - 6, BLOOM_GOLD[2])
    c.put(bx - 2, by - 6, BLOOM_GOLD[1])
    c.put(bx - 3, by - 5, BLOOM_GOLD[1])
    # Center-right berry-rose blossom cluster
    c.put(bx + 1, by - 7, BLOOM_ROSE[2])
    c.put(bx + 2, by - 7, BLOOM_ROSE[1])
    c.put(bx + 2, by - 6, BLOOM_ROSE[0])
    c.put_outline_if_empty(bx + 1, by - 8, INK)
    c.put_outline_if_empty(bx + 2, by - 8, INK)
    c.put_outline_if_empty(bx + 3, by - 7, INK)
    # Tiny glowing turquoise moon-bud nestled in center
    c.put(bx - 1, by - 7, RUNE_GLOW[3])
    c.put(bx, by - 7, RUNE_GLOW[2])
    c.put_outline_if_empty(bx - 1, by - 8, INK)
    c.put_outline_if_empty(bx, by - 8, INK)
    c.shine(bx - 1, by - 7, RUNE_GLOW[3], 220)
    c.shine(bx, by - 7, RUNE_GLOW[2], 180)


def draw_floral_basket(c: Canvas, bx: int, by: int):
    """Draws a tiny woven wicker market basket (`~10x9` px) anchored at `(bx, by)`,
    with a braided handle and warm crimson/lilac/marigold market blooms + 1 teal glow-bud.
    """
    draw_shadow_ellipse(c, bx + 0.5, by + 0.5, 5.4, 2.0)

    # Woven tapered basket body: rows by-3..by
    widths = {0: (-3, 3), -1: (-4, 4), -2: (-4, 4), -3: (-4, 4)}
    for dy, (x0, x1) in widths.items():
        y = by + dy
        for dx in range(x0 - 1, x1 + 2):
            c.clear_shine(bx + dx, y)
        c.put(bx + x0 - 1, y, INK)
        c.put(bx + x1 + 1, y, INK)
        for dx in range(x0, x1 + 1):
            if dy == -3:
                # Braided rim lip
                col = WICKER[3 if dx < 0 else (2 if dx < 2 else 1)]
            else:
                weave = (dx + dy) % 2 == 0
                base_t = 3 if dx < -1 else (2 if dx < 2 else 1)
                if not weave:
                    base_t = max(0, base_t - 1)
                col = WICKER[base_t]
            c.put(bx + dx, y, col)
    for dx in range(-3, 4):
        c.put(bx + dx, by + 1, INK)

    # Lush floral bouquet in basket (y in by-6 .. by-4)
    leaves = [
        (-3, -4, LEAF[3]), (-2, -4, LEAF[2]), (-1, -4, LEAF[3]), (0, -4, LEAF[2]),
        (1, -4, LEAF[3]), (2, -4, LEAF[1]), (3, -4, LEAF[1]),
        (-3, -5, LEAF[2]), (-1, -5, LEAF[2]), (1, -5, LEAF[2]), (2, -5, LEAF[1]),
    ]
    for dx, dy, _ in leaves:
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            c.put_outline_if_empty(bx + dx + ox, by + dy + oy, INK)
    for dx, dy, col in leaves:
        c.clear_shine(bx + dx, by + dy)
        c.put(bx + dx, by + dy, col)

    # Arched wicker handle rising over the flowers (by-8 .. by-5)
    handle_pts = [(-3, -6, WICKER[2]), (-2, -7, WICKER[3]), (-1, -8, WICKER[3]), (0, -8, WICKER[2]), (1, -7, WICKER[2]), (2, -6, WICKER[1])]
    for dx, dy, _ in handle_pts:
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            c.put_outline_if_empty(bx + dx + ox, by + dy + oy, INK)
    for dx, dy, col in handle_pts:
        c.clear_shine(bx + dx, by + dy)
        c.put(bx + dx, by + dy, col)

    # Flowers tucked inside basket
    # Left lilac cluster
    c.put(bx - 2, by - 5, BLOOM_LILAC[2])
    c.put(bx - 2, by - 6, BLOOM_LILAC[1])
    c.put_outline_if_empty(bx - 2, by - 7, INK)
    # Right marigold cluster
    c.put(bx + 1, by - 6, BLOOM_GOLD[2])
    c.put(bx + 2, by - 6, BLOOM_GOLD[1])
    c.put_outline_if_empty(bx + 1, by - 7, INK)
    c.put_outline_if_empty(bx + 3, by - 6, INK)
    # Center crimson rose + glowing teal nectar bud
    c.put(bx, by - 5, BLOOM_ROSE[2])
    c.put(bx - 1, by - 6, RUNE_GLOW[3])
    c.shine(bx - 1, by - 6, RUNE_GLOW[3], 215)
    c.shine(bx, by - 6, RUNE_GLOW[1], 110)


def build_plaza_market():
    """Generates `(arr, glow)` (`208x136` RGBA uint8) for the Etappe 2 Market Day plaza bunting overlay."""
    c = Canvas(W, H)

    # ------------------------------------------------------------------
    # Spatial Layout Verification:
    # - Plaza center: CX=104, CY=70, RX=98, RY=60 (feet row = 78)
    # - Keep center fountain (`x=76..132, y=20..88`) 100% clear!
    # - Keep inner walkway (`r < 0.78`) 100% clear!
    # - Keep left/right caravan slots (`x < 56` and `x > 152` near `y=45..95`) 100% clear!
    #
    # Corner Post Positions on the northern & southern stone curb (`r ~ 0.92`):
    # - NW Post: feet at (68, 23), height 15 -> x=65..71, y=7..24  (x >= 65, y <= 24: clear of caravan & fountain!)
    # - NE Post: feet at (140, 23), height 15 -> x=137..143, y=7..24 (x <= 143, y <= 24: clear of caravan & fountain!)
    # - SW Post: feet at (68, 118), height 15 -> x=65..71, y=102..119 (y >= 102: clear of caravan & fountain!)
    # - SE Post: feet at (140, 118), height 15 -> x=137..143, y=102..119 (y >= 102: clear of caravan & fountain!)
    # ------------------------------------------------------------------

    # 1. Northern Top Rim Bunting Span (drawn BEFORE the northern posts so rope caps cleanly into post collars)
    # Rope runs from NW tie (68, 10) to NE tie (140, 10) with gentle 2.2px sag -> rope y=10..12,
    # pennants/lanterns hang down to at most y=17 (strictly < y=20 above Stage 3 fountain spire!)
    # Note: NW floral crate sits at x=60..69 (OUTSIDE the NW post), so the entire inner span x=71..137 is unobstructed!
    north_items = [
        (0.11, "pennant", (PENNANT_MARIGOLD, 0)),
        (0.20, "pennant", (PENNANT_CRIMSON, 1)),
        (0.29, "lantern", True),
        (0.38, "pennant", (PENNANT_TURQUOISE, 0)),
        (0.46, "pennant", (PENNANT_MARIGOLD, 1)),
        (0.50, "charm", None),
        (0.54, "pennant", (PENNANT_MARIGOLD, 1)),
        (0.62, "pennant", (PENNANT_TURQUOISE, 0)),
        (0.71, "lantern", True),
        (0.80, "pennant", (PENNANT_CRIMSON, 1)),
        (0.89, "pennant", (PENNANT_MARIGOLD, 0)),
    ]
    draw_bunting_span(c, 68, 10, 140, 10, sag=2.0, items=north_items)

    # Side wing garlands from NW/NE posts curving gracefully down to stone curb anchors at (57, 23) and (151, 23)
    # (stays strictly in x=56..68, y=10..27 and x=140..152, y=10..27 — well clear of x<56 / x>152 and y=45..95!)
    nw_wing = [
        (0.34, "pennant", (PENNANT_TURQUOISE, 0)),
        (0.68, "pennant", (PENNANT_CRIMSON, 0)),
    ]
    ne_wing = [
        (0.32, "pennant", (PENNANT_CRIMSON, 0)),
        (0.66, "pennant", (PENNANT_TURQUOISE, 0)),
    ]
    draw_bunting_span(c, 57, 22, 68, 11, sag=1.4, items=nw_wing)
    draw_bunting_span(c, 140, 11, 151, 22, sag=1.4, items=ne_wing)
    # Small brass curb tie-pins at outer ends (57, 23) & (151, 23)
    for px_pin in (57, 151):
        c.put(px_pin, 22, GOLD_TRIM[3])
        c.put(px_pin, 23, GOLD_TRIM[1])
        for ox, oy in ((-1, 22), (1, 22), (-1, 23), (1, 23), (0, 21), (0, 24)):
            c.put_outline_if_empty(px_pin + ox, oy, INK)

    # Draw the two Northern Carved Oak Posts (feet at y=22, height=15 -> top_y=7)
    draw_carved_oak_post(c, 68, 22, height=15, lantern_dir=-1)
    draw_carved_oak_post(c, 140, 22, height=15, lantern_dir=1)

    # 2. Southern Bottom Rim Bunting Span (follows the curved southern curb from SW (68, 107) to SE (140, 107))
    # Sag = 11.0 curves the garland along the bottom oval rim (`y = 107..118`, pennants reach `y = 113..123`,
    # leaving the entire inner plaza & southern walkway `y < 106` open and clear!)
    south_items = [
        (0.11, "pennant", (PENNANT_TURQUOISE, 0)),
        (0.20, "pennant", (PENNANT_MARIGOLD, 1)),
        (0.29, "lantern", True),
        (0.38, "pennant", (PENNANT_CRIMSON, 0)),
        (0.45, "charm", None),
        (0.50, "pennant", (PENNANT_TURQUOISE, 1)),
        (0.55, "charm", None),
        (0.62, "pennant", (PENNANT_CRIMSON, 0)),
        (0.71, "lantern", True),
        (0.80, "pennant", (PENNANT_MARIGOLD, 1)),
        (0.89, "pennant", (PENNANT_TURQUOISE, 0)),
    ]
    draw_bunting_span(c, 68, 107, 140, 107, sag=11.0, items=south_items)

    # Short southern outer wing swags anchoring to curb pins at (57, 113) and (151, 113) (y > 105, clear of caravan!)
    sw_wing = [
        (0.35, "pennant", (PENNANT_MARIGOLD, 0)),
        (0.68, "pennant", (PENNANT_CRIMSON, 0)),
    ]
    se_wing = [
        (0.32, "pennant", (PENNANT_CRIMSON, 0)),
        (0.65, "pennant", (PENNANT_MARIGOLD, 0)),
    ]
    draw_bunting_span(c, 57, 112, 68, 107, sag=1.5, items=sw_wing)
    draw_bunting_span(c, 140, 107, 151, 112, sag=1.5, items=se_wing)
    for px_pin in (57, 151):
        c.put(px_pin, 112, GOLD_TRIM[3])
        c.put(px_pin, 113, GOLD_TRIM[1])
        for ox, oy in ((-1, 112), (1, 112), (-1, 113), (1, 113), (0, 111), (0, 114)):
            c.put_outline_if_empty(px_pin + ox, oy, INK)

    # Draw the two Southern Carved Oak Posts (feet at y=118, height=15)
    draw_carved_oak_post(c, 68, 118, height=15, lantern_dir=-1)
    draw_carved_oak_post(c, 140, 118, height=15, lantern_dir=1)

    # 3. Two tiny floral market crates/baskets ONLY along the northern top rim and bottom rim corners:
    # Placed cleanly in the foreground of the NW & SE posts on the stone curb so zero pennants are occluded!
    # - Northern top-left rim corner crate nestled just in front-right of the NW post foot at (73, 24) -> x=68..78, y=16..25
    #   Wait: keep x=76..132, y=20..88 100% clear! So place the northern crate on the outer-left curb beside NW post at (62, 26) -> x=57..67, y=18..27!
    draw_floral_crate(c, 62, 26)
    # - Southern bottom-right rim corner woven floral basket nestled on the outer-right curb beside SE post at (146, 119) -> x=141..151, y=111..120!
    draw_floral_basket(c, 146, 119)

    # Sanity assertions on clear zones!
    # 1) Center fountain box (x=76..132, y=20..88) must have zero pixels
    fountain_box = c.arr[20:89, 76:133, 3]
    assert not np.any(fountain_box), f"Fountain clear box violated! Nonzero count: {np.count_nonzero(fountain_box)}"
    fountain_glow = c.glow[20:89, 76:133, 3]
    assert not np.any(fountain_glow), "Fountain glow box violated!"

    # 2) Left & right caravan slots (x < 56 and x > 152 for y=45..95) — in fact keep ALL y=30..100 completely clear!
    assert not np.any(c.arr[30:101, :, 3]), "Middle walkway / caravan band (y=30..100) has unexpected pixels!"
    assert not np.any(c.glow[30:101, :, 3]), "Middle walkway / caravan glow band (y=30..100) has unexpected pixels!"

    return c.arr, c.glow


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    arr, glow = build_plaza_market()

    out_main = ROOT / "plaza_market.png"
    out_glow = ROOT / "plaza_market_glow.png"
    Image.fromarray(arr, "RGBA").save(out_main)
    Image.fromarray(glow, "RGBA").save(out_glow)

    if len(sys.argv) > 1:
        # Build a clean 2x2 inspection sheet over plaza_2 and plaza_3 (Day & Night)
        scale = 3
        pad = 8
        cw = (W * 2 + pad * 3) * scale
        ch = (H * 2 + pad * 3) * scale
        sheet = Image.new("RGBA", (cw, ch), (56, 98, 62, 255))
        night_bg = Image.new("RGBA", (cw, H * scale + pad * 2 * scale), (16, 18, 34, 255))
        sheet.paste(night_bg, (0, H * scale + pad * scale))

        mkt_im = Image.fromarray(arr, "RGBA")
        mkt_gl = Image.fromarray(glow, "RGBA")
        mkt_gl_day = mkt_gl.copy()
        mkt_gl_day.putalpha(mkt_gl_day.getchannel("A").point(lambda v: int(v * 0.30)))

        configs = [
            ("plaza_2", None, "plaza_fountain_2", 56, 56, (28, 49)),
            ("plaza_3", "plaza_3_glow", "plaza_fountain_3", 56, 64, (28, 57)),
        ]
        for idx, (fl_n, flg_n, fn_n, fw, fh, foot) in enumerate(configs):
            ox = (pad + idx * (W + pad)) * scale
            # Day composite
            day_im = Image.open(ROOT / f"{fl_n}.png").convert("RGBA")
            if flg_n:
                fg = Image.open(ROOT / f"{flg_n}.png").convert("RGBA")
                fg.putalpha(fg.getchannel("A").point(lambda v: int(v * 0.30)))
                day_im.alpha_composite(fg)
            day_im.alpha_composite(mkt_im)
            day_im.alpha_composite(mkt_gl_day)
            fount_im = Image.open(ROOT / f"{fn_n}.png").convert("RGBA").crop((0, 0, fw, fh))
            day_im.alpha_composite(fount_im, (int(CX) - foot[0], FEET_ROW - foot[1]))
            sheet.alpha_composite(day_im.resize((W * scale, H * scale), Image.NEAREST), (ox, pad * scale))

            # Night composite
            fl_raw = np.array(Image.open(ROOT / f"{fl_n}.png").convert("RGBA"), np.float32)
            fl_raw[..., 0] *= 0.32
            fl_raw[..., 1] *= 0.34
            fl_raw[..., 2] *= 0.52
            night_im = Image.fromarray(fl_raw.astype(np.uint8), "RGBA")
            if flg_n:
                night_im.alpha_composite(Image.open(ROOT / f"{flg_n}.png").convert("RGBA"))
            mk_raw = arr.astype(np.float32)
            mk_raw[..., 0] *= 0.36
            mk_raw[..., 1] *= 0.38
            mk_raw[..., 2] *= 0.55
            night_im.alpha_composite(Image.fromarray(mk_raw.astype(np.uint8), "RGBA"))
            night_im.alpha_composite(mkt_gl)
            fn_raw = np.array(fount_im, np.float32)
            fn_raw[..., 0] *= 0.35
            fn_raw[..., 1] *= 0.37
            fn_raw[..., 2] *= 0.55
            night_im.alpha_composite(Image.fromarray(fn_raw.astype(np.uint8), "RGBA"), (int(CX) - foot[0], FEET_ROW - foot[1]))
            fn_gl = Image.open(ROOT / f"{fn_n}_glow.png").convert("RGBA").crop((0, 0, fw, fh))
            night_im.alpha_composite(fn_gl, (int(CX) - foot[0], FEET_ROW - foot[1]))
            sheet.alpha_composite(night_im.resize((W * scale, H * scale), Image.NEAREST), (ox, (H + pad * 2) * scale))

        sheet.save(sys.argv[1])

    print(f"plaza_market written: {out_main.name} ({W}x{H}, {int(np.count_nonzero(arr[..., 3]))} opaque/semi px), "
          f"{out_glow.name} ({W}x{H}, {int(np.count_nonzero(glow[..., 3]))} emissive px)")


if __name__ == "__main__":
    main()
