#!/usr/bin/env python3
"""Handcrafted next-gen pixel-art woodland floor detail atlas (16 variants of 24x20 px).

Outputs:
  assets/tiles/forest_floor_details.png       16x1 strip (384x20 px):
                                              0..2  Fallen woodland leaf-litter clusters (russet, ochre, chestnut)
                                              3..5  Knotted mossy creeping tree roots emerging from humus
                                              6..8  Sunken mossy woodland stones & damp pebbles
                                              9..10 Fallen mossy twigs, pine needles, bark & pinecones
                                              11..13 Woodland mushroom clusters (porcini, twilight violet, pale teal)
                                              14..15 Lush damp woodland moss pillows & clover tufts
  assets/tiles/forest_floor_details_glow.png  Subtle unlit night glow on twilight/teal forest mushrooms
  docs/img/forest_details_atlas_4x.png        4x visual QA sheet on forest humus & twilight backdrop
"""
from __future__ import annotations

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

CELL_W, CELL_H = 24, 20
COUNT = 16

# Woodland bark & root ramp (cool umber shadow -> warm weathered bark -> lichen highlight)
BARK_0 = hexc("221817")
BARK_1 = hexc("382721")
BARK_2 = hexc("523a2d")
BARK_3 = hexc("6f523e")
BARK_4 = hexc("8f6e52")

# Fallen leaf-litter tones (natural muted forest russet, amber, chestnut & dry olive)
LEAF_D1 = hexc("4a2a1e")
LEAF_M1 = hexc("784429")
LEAF_L1 = hexc("a46537")
LEAF_D2 = hexc("593f22")
LEAF_M2 = hexc("8c6631")
LEAF_L2 = hexc("b88b46")
LEAF_OL = hexc("5a5d32")

# Moss & fern ramp (harmonized with Shadowspore woodland emerald)
M0 = hexc("193638")
M1 = hexc("244d45")
M2 = hexc("346e52")
M3 = hexc("4d8f5d")
M4 = hexc("76b86e")
M5 = hexc("a2d684")

# Damp woodland rock ramp
R0 = hexc("262936")
R1 = hexc("3f4556")
R2 = hexc("5d6575")
R3 = hexc("7f8896")
R4 = hexc("a8b1bc")

# Mushrooms
MUSH_STEM = hexc("cfc3aa")
MUSH_STEM_D = hexc("8e8070")
MUSH_BR_D = hexc("593424")
MUSH_BR_M = hexc("8c5534")
MUSH_BR_L = hexc("ba7d4c")
MUSH_V_D = hexc("46316e")
MUSH_V_M = hexc("7c5bb5")
MUSH_V_L = hexc("bfa6f0")
MUSH_T_D = hexc("22595e")
MUSH_T_M = hexc("45a39c")
MUSH_T_L = hexc("8ce6d8")

AO = (16, 14, 18, 120)
AO_SOFT = (16, 14, 18, 65)
GLOW_V = (176, 134, 250, 145)
GLOW_T = (118, 240, 224, 145)


class Cell:
    def __init__(self) -> None:
        self.px = [[CLEAR] * CELL_W for _ in range(CELL_H)]
        self.gl = [[CLEAR] * CELL_W for _ in range(CELL_H)]

    def put(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            self.px[y][x] = c

    def gput(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            self.gl[y][x] = c

    def leaf(self, cx: int, cy: int, hi, mid, sh, flip: bool = False) -> None:
        """Handcrafted 3x2 / 4x2 fallen woodland leaf with top-left catchlight & soft shadow."""
        self.put(cx, cy + 1, AO_SOFT)
        if not flip:
            self.put(cx - 1, cy, hi)
            self.put(cx, cy, mid)
            self.put(cx + 1, cy, sh)
            self.put(cx, cy - 1, hi)
            self.put(cx + 1, cy + 1, sh)
        else:
            self.put(cx, cy - 1, hi)
            self.put(cx - 1, cy, mid)
            self.put(cx, cy, mid)
            self.put(cx + 1, cy, sh)
            self.put(cx - 1, cy + 1, sh)

    def root_arc(self, x0: float, y0: float, x1: float, y1: float, arch: float, thick: float = 1.6, moss: bool = True) -> None:
        """Draws a knotted creeping tree root rising gently from forest humus and dipping back under."""
        steps = 22
        for i in range(steps + 1):
            t = i / steps
            px = x0 + (x1 - x0) * t
            py = y0 + (y1 - y0) * t - math.sin(t * math.pi) * arch
            r = thick * (0.45 + 0.55 * math.sin(t * math.pi))
            ix, iy = int(round(px)), int(round(py))
            # Soft shadow tucked right beneath the arched root
            self.put(ix, iy + int(round(r)) + 1, AO)
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if dx * dx + dy * dy <= r * r:
                        col = BARK_4 if dy < 0 else (BARK_3 if dy == 0 and dx <= 0 else (BARK_2 if dy == 0 else BARK_1))
                        if t < 0.16 or t > 0.84:
                            col = BARK_1 if dy >= 0 else BARK_2
                        self.put(ix + dx, iy + dy, col)
            if moss and 0.25 < t < 0.72 and i % 3 == 0:
                self.put(ix, iy - int(round(r)), M4 if i % 6 == 0 else M3)
                self.put(ix + 1, iy - int(round(r)) + 1, M2)

    def mossy_rock(self, cx: float, cy: float, rx: float, ry: float, moss_cap: bool = True) -> None:
        for y in range(2, CELL_H - 1):
            for x in range(2, CELL_W - 2):
                nx = (x - cx) / rx
                ny = (y - cy) / ry
                d = nx * nx + ny * ny
                if d <= 1.0:
                    lit = -0.55 * nx - 0.80 * ny
                    if moss_cap and ny < -0.15 and nx < 0.55 and d < 0.88:
                        col = M4 if lit > 0.45 else (M3 if lit > 0.05 else M2)
                    else:
                        col = R4 if lit > 0.65 else (R3 if lit > 0.22 else (R2 if lit > -0.25 else (R1 if lit > -0.62 else R0)))
                    self.put(x, y, col)
                elif d <= 1.38 and ny > 0.15:
                    self.put(x, y, AO)

    def mushroom(self, x: int, y: int, cap_hi, cap_mid, cap_sh, big: bool = False, glow_c=None) -> None:
        """Crisp 3/4 miniature woodland mushroom tucked into soil."""
        self.put(x, y + 1, AO)
        self.put(x, y, MUSH_STEM_D)
        self.put(x, y - 1, MUSH_STEM)
        if big:
            self.put(x, y - 2, MUSH_STEM)
            self.put(x - 2, y - 3, cap_hi)
            self.put(x - 1, y - 3, cap_hi)
            self.put(x, y - 3, cap_mid)
            self.put(x + 1, y - 3, cap_sh)
            self.put(x + 2, y - 3, cap_sh)
            self.put(x - 1, y - 4, cap_hi)
            self.put(x, y - 4, cap_hi)
            self.put(x + 1, y - 4, cap_mid)
            if glow_c is not None:
                self.gput(x - 1, y - 4, glow_c)
                self.gput(x, y - 3, glow_c)
        else:
            self.put(x - 1, y - 2, cap_hi)
            self.put(x, y - 2, cap_mid)
            self.put(x + 1, y - 2, cap_sh)
            self.put(x, y - 3, cap_hi)
            if glow_c is not None:
                self.gput(x, y - 3, glow_c)


def draw_variant(v: int) -> Cell:
    c = Cell()

    # ---------------- 0..2: FALLEN LEAF-LITTER CLUSTERS ----------------
    if v == 0:
        c.leaf(7, 9, LEAF_L1, LEAF_M1, LEAF_D1, False)
        c.leaf(14, 7, LEAF_L2, LEAF_M2, LEAF_D2, True)
        c.leaf(11, 13, LEAF_L2, LEAF_M2, LEAF_D2, False)
        c.leaf(17, 12, LEAF_L1, LEAF_M1, LEAF_D1, True)
        c.leaf(6, 14, LEAF_M2, LEAF_OL, LEAF_D2, False)

    elif v == 1:
        c.leaf(9, 8, LEAF_L2, LEAF_M2, LEAF_D2, True)
        c.leaf(15, 10, LEAF_L1, LEAF_M1, LEAF_D1, False)
        c.leaf(12, 14, LEAF_L1, LEAF_M1, LEAF_D1, True)
        c.leaf(18, 8, LEAF_M2, LEAF_OL, LEAF_D2, False)
        # Delicate fallen pine needles
        for nx, ny in ((5, 11), (6, 11), (7, 12), (16, 15), (17, 15)):
            c.put(nx, ny, LEAF_D2 if nx % 2 == 0 else LEAF_M2)

    elif v == 2:
        # Sparse damp dark leaf drift for wet humus hollows
        c.leaf(8, 11, LEAF_M1, LEAF_D1, BARK_1, False)
        c.leaf(14, 9, LEAF_M2, LEAF_D2, BARK_1, True)
        c.leaf(16, 14, LEAF_L1, LEAF_M1, LEAF_D1, False)

    # ---------------- 3..5: CREEPING MOSSY TREE ROOTS ----------------
    elif v == 3:
        c.root_arc(2.0, 14.0, 21.0, 10.0, arch=3.0, thick=1.7, moss=True)
        c.root_arc(11.0, 11.0, 19.0, 16.0, arch=1.6, thick=1.1, moss=False)

    elif v == 4:
        c.root_arc(3.0, 9.0, 20.0, 15.0, arch=2.8, thick=1.6, moss=True)
        c.leaf(8, 15, LEAF_L1, LEAF_M1, LEAF_D1)

    elif v == 5:
        c.root_arc(4.0, 15.0, 21.0, 12.0, arch=2.4, thick=1.4, moss=True)
        c.root_arc(7.0, 12.0, 15.0, 7.0, arch=1.8, thick=1.0, moss=True)

    # ---------------- 6..8: SUNKEN MOSSY WOODLAND STONES ----------------
    elif v == 6:
        c.mossy_rock(11.5, 12.0, 6.2, 4.2, moss_cap=True)
        c.mossy_rock(17.5, 14.5, 2.8, 2.0, moss_cap=False)

    elif v == 7:
        c.mossy_rock(9.0, 11.5, 4.5, 3.2, moss_cap=True)
        c.mossy_rock(15.5, 13.0, 4.0, 2.8, moss_cap=True)
        c.leaf(12, 16, LEAF_L2, LEAF_M2, LEAF_D2)

    elif v == 8:
        # Wet dark forest cobbles embedded in damp earth
        c.mossy_rock(8.0, 10.5, 3.2, 2.2, moss_cap=False)
        c.mossy_rock(14.5, 12.5, 3.6, 2.4, moss_cap=True)
        c.mossy_rock(18.5, 9.5, 2.4, 1.8, moss_cap=False)

    # ---------------- 9..10: TWIGS, BARK & PINECONES ----------------
    elif v == 9:
        # Fallen forked mossy twig
        for i in range(13):
            tx = 4 + i
            ty = 13 - i // 3
            c.put(tx, ty + 1, AO_SOFT)
            c.put(tx, ty, BARK_3 if i % 3 == 0 else BARK_2)
            if i == 5 or i == 6:
                c.put(tx, ty - 1, M3)
        for j in range(5):
            c.put(10 + j, 12 + j // 2, BARK_2 if j < 3 else BARK_1)
        c.leaf(16, 13, LEAF_L2, LEAF_M2, LEAF_D2)

    elif v == 10:
        # Mossy bark shard + tiny pinecone
        for y in range(10, 15):
            for x in range(6, 15):
                if (x - 10.5) ** 2 / 20.0 + (y - 12.0) ** 2 / 6.0 <= 1.0:
                    c.put(x, y, BARK_4 if y == 10 else (BARK_3 if y == 11 else (BARK_2 if y == 12 else BARK_1)))
        c.put(8, 10, M3)
        c.put(9, 10, M4)
        c.put(10, 11, M2)
        # Tiny sculpted pinecone on right
        for px, py, pc in ((17, 12, BARK_4), (18, 12, BARK_3), (17, 13, BARK_2), (18, 13, BARK_1), (19, 13, BARK_0)):
            c.put(px, py, pc)

    # ---------------- 11..13: WOODLAND MUSHROOMS ----------------
    elif v == 11:
        # Warm forest porcini / brown cap cluster
        c.mossy_rock(12.0, 15.0, 5.5, 2.5, moss_cap=True)
        c.mushroom(10, 14, MUSH_BR_L, MUSH_BR_M, MUSH_BR_D, big=True)
        c.mushroom(15, 15, MUSH_BR_L, MUSH_BR_M, MUSH_BR_D, big=False)
        c.mushroom(7, 15, MUSH_BR_L, MUSH_BR_M, MUSH_BR_D, big=False)

    elif v == 12:
        # Delicate Shadowspore twilight-violet woodland caps (soft night glow!)
        c.mushroom(10, 14, MUSH_V_L, MUSH_V_M, MUSH_V_D, big=True, glow_c=GLOW_V)
        c.mushroom(15, 15, MUSH_V_L, MUSH_V_M, MUSH_V_D, big=False, glow_c=GLOW_V)
        c.mushroom(13, 13, MUSH_V_L, MUSH_V_M, MUSH_V_D, big=False)
        c.leaf(7, 15, LEAF_M1, LEAF_D1, BARK_1)

    elif v == 13:
        # Pale-teal damp moss bonnets (delicate night bioluminescence near puddles!)
        c.mushroom(11, 14, MUSH_T_L, MUSH_T_M, MUSH_T_D, big=True, glow_c=GLOW_T)
        c.mushroom(16, 15, MUSH_T_L, MUSH_T_M, MUSH_T_D, big=False, glow_c=GLOW_T)
        c.mushroom(8, 15, MUSH_T_L, MUSH_T_M, MUSH_T_D, big=False)

    # ---------------- 14..15: PLUSH DAMP MOSS PILLOWS ----------------
    elif v == 14:
        for mx, my, rx, ry in ((9.0, 13.0, 5.2, 3.2), (15.0, 13.5, 4.6, 2.8), (12.0, 11.5, 4.8, 3.0)):
            for y in range(7, 18):
                for x in range(2, 22):
                    d = ((x - mx) / rx) ** 2 + ((y - my) / ry) ** 2
                    if d <= 1.0:
                        lit = -0.45 * (x - mx) / rx - 0.85 * (y - my) / ry
                        c.put(x, y, M5 if lit > 0.65 else (M4 if lit > 0.2 else (M3 if lit > -0.25 else (M2 if lit > -0.6 else M1))))
        c.leaf(17, 15, LEAF_L1, LEAF_M1, LEAF_D1)

    else:
        for mx, my, rx, ry in ((10.0, 13.0, 4.5, 2.6), (14.5, 12.2, 4.0, 2.4)):
            for y in range(8, 17):
                for x in range(3, 21):
                    d = ((x - mx) / rx) ** 2 + ((y - my) / ry) ** 2
                    if d <= 1.0:
                        lit = -0.45 * (x - mx) / rx - 0.85 * (y - my) / ry
                        c.put(x, y, M4 if lit > 0.45 else (M3 if lit > 0.0 else (M2 if lit > -0.45 else M1)))
        # Tiny bright clover leaves tucked on moss
        for lx, ly in ((8, 11), (13, 10), (16, 12)):
            c.put(lx, ly - 1, M5)
            c.put(lx - 1, ly, M4)
            c.put(lx + 1, ly, M2)

    return c


def build_preview(cells: list[Cell]) -> list[list[tuple[int, int, int, int]]]:
    cols = 4
    rows = 4
    pad = 4
    cw = CELL_W + pad
    ch = CELL_H + pad
    w = cols * cw + pad
    h = rows * ch * 2 + pad * 3
    bg_day = hexc("473328")
    bg_night = hexc("14182a")
    img = [[bg_day] * w for _ in range(h)]
    split_y = rows * ch + pad * 2
    for y in range(split_y, h):
        for x in range(w):
            img[y][x] = bg_night

    def blend(dst, src):
        sa = src[3] / 255.0
        if sa <= 0.0:
            return dst
        if sa >= 0.999:
            return src
        return (
            int(dst[0] * (1.0 - sa) + src[0] * sa),
            int(dst[1] * (1.0 - sa) + src[1] * sa),
            int(dst[2] * (1.0 - sa) + src[2] * sa),
            255,
        )

    for idx, cell in enumerate(cells):
        gx = pad + (idx % cols) * cw
        gy = pad + (idx // cols) * ch
        ny = split_y + (idx // cols) * ch
        for y in range(CELL_H):
            for x in range(CELL_W):
                p = cell.px[y][x]
                if p[3]:
                    img[gy + y][gx + x] = blend(img[gy + y][gx + x], p)
                    dim = (int(p[0] * 0.40), int(p[1] * 0.44), int(p[2] * 0.64), p[3])
                    img[ny + y][gx + x] = blend(img[ny + y][gx + x], dim)
                g = cell.gl[y][x]
                if g[3]:
                    img[ny + y][gx + x] = blend(img[ny + y][gx + x], g)

    scale = 4
    out = [[CLEAR] * (w * scale) for _ in range(h * scale)]
    for y in range(h):
        for sy in range(scale):
            dst = out[y * scale + sy]
            for x in range(w):
                px_c = img[y][x]
                bx = x * scale
                for sx in range(scale):
                    dst[bx + sx] = px_c
    return out


def main() -> None:
    cells = [draw_variant(v) for v in range(COUNT)]
    lit = [[CLEAR] * (CELL_W * COUNT) for _ in range(CELL_H)]
    glow = [[CLEAR] * (CELL_W * COUNT) for _ in range(CELL_H)]
    for idx, cell in enumerate(cells):
        ox = idx * CELL_W
        for y in range(CELL_H):
            for x in range(CELL_W):
                lit[y][ox + x] = cell.px[y][x]
                glow[y][ox + x] = cell.gl[y][x]
    tiles_dir = ROOT / "tiles"
    write_png(tiles_dir / "forest_floor_details.png", CELL_W * COUNT, CELL_H, lit)
    write_png(tiles_dir / "forest_floor_details_glow.png", CELL_W * COUNT, CELL_H, glow)
    preview = build_preview(cells)
    preview_path = ROOT.parent / "docs" / "img" / "forest_details_atlas_4x.png"
    write_png(preview_path, len(preview[0]), len(preview), preview)
    print(f"Wrote {COUNT} woodland floor details -> {tiles_dir / 'forest_floor_details.png'} and {preview_path}")


if __name__ == "__main__":
    main()
