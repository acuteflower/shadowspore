#!/usr/bin/env python3
"""Generates 22 crisp 16x16 pixel-art item icons for Shadowspore's Sanctuary & Meadow Flora 2.0.

Follows `docs/design_guide.md`:
  - 16x16 canvas, top-left lighting, 3-4 tonal steps per material, 1px dark tinted outline (never pure #000000)
  - Writes `assets/items/<id>.png` and `docs/img/sanctuary_items_4x.png` preview grid.
"""
from __future__ import annotations

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, hexc, write_png  # noqa: E402

PROJ_ROOT = pathlib.Path(__file__).resolve().parent.parent

LF = [hexc("162c28"), hexc("22483c"), hexc("3e7d56"), hexc("62a665"), hexc("9ad484")]
SG = [hexc("1d3034"), hexc("314c4c"), hexc("52756e"), hexc("7ba092"), hexc("b2cfc0")]
WD = [hexc("1e1726"), hexc("3b2b3d"), hexc("614852"), hexc("8c6c70")]
GD = [hexc("3d2a12"), hexc("6f5020"), hexc("b48a38"), hexc("e6c468"), hexc("fff0b0")]
TL = [hexc("143640"), hexc("2a8c94"), hexc("3cc0c6"), hexc("78f4e6"), hexc("d0fff8")]
VL = [hexc("21123b"), hexc("4c2982"), hexc("7b4ec2"), hexc("b58ef7"), hexc("e3d4ff")]
BL = [hexc("1d2d52"), hexc("3e629c"), hexc("6aa0dc"), hexc("aed4ff")]
CR = [hexc("383b4f"), hexc("8d92ab"), hexc("cbcde0"), hexc("f4f2fa")]
RH = [hexc("361120"), hexc("7a1e34"), hexc("bf364e"), hexc("f27988"), hexc("ffd0d8")]
EL = [hexc("140c24"), hexc("2b1947"), hexc("4e2e78"), hexc("8c6ec2"), hexc("cbb8f0")]
SL = [hexc("182038"), hexc("2c3e63"), hexc("4e6c99"), hexc("8cb0d9")]


def make16() -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR] * 16 for _ in range(16)]


def put(g: list[list[tuple[int, int, int, int]]], x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= x < 16 and 0 <= y < 16:
        g[y][x] = c


def outline16(g: list[list[tuple[int, int, int, int]]], oc: tuple[int, int, int, int]) -> None:
    orig = [row[:] for row in g]
    for y in range(16):
        for x in range(16):
            if orig[y][x][3] > 0:
                continue
            for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + ox, y + oy
                if 0 <= nx < 16 and 0 <= ny < 16 and orig[ny][nx][3] > 200:
                    g[y][x] = oc
                    break


def disc(g: list[list[tuple[int, int, int, int]]], cx: float, cy: float, r: float, ramp: list[tuple[int, int, int, int]]) -> None:
    for y in range(16):
        for x in range(16):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                d = (x - cx) + (y - cy)
                tone = 4 if (len(ramp) > 4 and d < -r * 0.55) else (3 if d < -0.2 else (2 if d < r * 0.55 else 1))
                put(g, x, y, ramp[min(len(ramp) - 1, tone)])


def line_px(g: list[list[tuple[int, int, int, int]]], x0: int, y0: int, x1: int, y1: int, c: tuple[int, int, int, int]) -> None:
    steps = max(1, max(abs(x1 - x0), abs(y1 - y0)))
    for i in range(steps + 1):
        put(g, int(round(x0 + (x1 - x0) * i / steps)), int(round(y0 + (y1 - y0) * i / steps)), c)


def draw_icon(item_id: str) -> list[list[tuple[int, int, int, int]]]:
    g = make16()

    if item_id == "waybread_leaf":
        # Ribbed oval plantain leaf + short petiole
        for y in range(3, 13):
            for x in range(4, 13):
                nx = (x - 8.2) / 3.8
                ny = (y - 7.5) / 4.6
                if nx * nx + ny * ny <= 1.0:
                    rib = abs((x - 8) + (y - 8) * 0.4) < 0.7 or (y in (6, 9) and abs(x - 8) <= 2)
                    put(g, x, y, LF[4 if (rib and x <= 8) else (3 if x + y < 16 else 2)])
        line_px(g, 5, 11, 3, 13, LF[2])
        outline16(g, LF[0])

    elif item_id == "stonecrop_gold":
        # Plump succulent sprig crowned with golden 5-star blooms
        line_px(g, 4, 12, 8, 8, LF[2])
        for bx, by in ((5, 10), (7, 11), (9, 9), (6, 8)):
            put(g, bx, by, LF[3])
        for sx, sy in ((7, 5), (10, 6), (5, 6)):
            for ox, oy, tn in ((0, 0, 4), (-1, 0, 3), (1, 0, 2), (0, -1, 3), (0, 1, 2)):
                put(g, sx + ox, sy + oy, GD[tn])
        outline16(g, GD[0])

    elif item_id == "silver_yarrow":
        # Feathery yarrow stalk + flat cream-silver umbel cluster
        line_px(g, 6, 13, 8, 6, LF[2])
        line_px(g, 5, 10, 8, 9, LF[3])
        line_px(g, 10, 10, 8, 8, LF[3])
        for ox in range(-4, 5):
            uy = 5 - (1 if abs(ox) <= 2 else 0)
            put(g, 8 + ox, uy, CR[3 if ox <= 0 else 2])
            put(g, 8 + ox, uy + 1, CR[2 if ox <= 0 else 1])
        outline16(g, LF[0])

    elif item_id == "chicory_petal":
        # Radiant sky-blue chicory blossom head
        for ox, oy, tn in (
            (-2, -2, 3), (0, -3, 3), (2, -2, 2), (-3, 0, 3), (3, 0, 2),
            (-2, 2, 2), (0, 3, 1), (2, 2, 1), (-1, -2, 3), (1, -2, 3),
            (-2, -1, 3), (2, -1, 2), (-1, 1, 2), (1, 1, 2), (-1, 0, 3), (1, 0, 2), (0, -1, 3), (0, 1, 2),
        ):
            put(g, 8 + ox, 8 + oy, BL[tn])
        put(g, 8, 8, BL[1])
        outline16(g, BL[0])

    elif item_id == "wild_thyme":
        # Tied sprig of woody thyme with rich violet blossom tips
        line_px(g, 4, 13, 9, 7, WD[2])
        line_px(g, 6, 13, 11, 8, WD[2])
        for lx, ly in ((6, 10), (8, 10), (9, 9)):
            put(g, lx, ly, LF[3])
        for vx, vy in ((9, 5), (8, 6), (10, 6), (11, 7), (7, 5)):
            put(g, vx, vy, VL[4 if vx <= 9 and vy <= 5 else 3])
        put(g, 5, 12, GD[3])
        outline16(g, VL[0])

    elif item_id == "rune_blossom":
        # Glowing starry turquoise sanctuary saxifrage panicle
        line_px(g, 7, 13, 8, 6, WD[2])
        for sx, sy in ((8, 4), (5, 7), (11, 7)):
            line_px(g, 8, 9, sx, sy, WD[2])
            for ox, oy, tn in ((0, 0, 4), (-1, 0, 3), (1, 0, 2), (0, -1, 4), (0, 1, 2)):
                put(g, sx + ox, sy + oy, TL[tn])
        outline16(g, TL[0])

    elif item_id == "mullein_torch_head":
        # Golden sentinel mullein flower spike with silver-sage calyx leaves
        line_px(g, 8, 14, 8, 11, SG[2])
        line_px(g, 5, 12, 8, 11, SG[3])
        line_px(g, 11, 12, 8, 11, SG[2])
        for y in range(3, 11):
            w_m = 1 if y < 5 else 2
            for ox in range(-w_m + 1, w_m + 1):
                put(g, 7 + ox, y, GD[4 if (ox <= 0 and y < 8) else (3 if ox <= 0 else 2)])
        outline16(g, GD[0])

    elif item_id == "star_dew_drop":
        # Luminous teardrop of pure turquoise-white Star-Dew cupped on a tiny leaf!
        line_px(g, 4, 12, 12, 11, LF[3])
        line_px(g, 5, 13, 11, 12, LF[2])
        for y in range(3, 11):
            hw = max(0.4, (y - 2.5) * 0.52) if y <= 8 else math.sqrt(max(0.0, 9.5 - (y - 8.2) ** 2 * 2.2))
            for x in range(4, 13):
                if abs(x - 8.0) <= hw:
                    put(g, x, y, TL[4 if (x <= 7 and y <= 7) else (3 if x <= 8 else 2)])
        put(g, 7, 5, (255, 255, 255, 255))
        outline16(g, TL[0])

    elif item_id == "dusk_spur":
        # Hooked dark-plum columbine bell with luminous violet-gold core
        line_px(g, 8, 3, 8, 5, WD[2])
        put(g, 6, 4, VL[2])
        put(g, 10, 4, VL[2])
        for y in range(5, 11):
            for x in range(5, 12):
                if abs(x - 8) <= (1 if y == 5 else (3 if y >= 8 else 2)):
                    put(g, x, y, VL[3 if x <= 7 else (2 if x <= 9 else 1)])
        put(g, 8, 11, GD[4])
        put(g, 7, 11, VL[4])
        outline16(g, VL[0])

    elif item_id == "ivy_tendril":
        # Coiled dark-emerald ivy vine ring with 3 veined leaves
        for deg in range(0, 360, 15):
            rad = math.radians(deg)
            put(g, int(round(8 + math.cos(rad) * 4.0)), int(round(8 + math.sin(rad) * 3.5)), LF[2])
        for lx, ly in ((5, 5), (11, 6), (8, 11)):
            for ox, oy, tn in ((0, 0, 4), (-1, 0, 3), (1, 0, 2), (0, 1, 2)):
                put(g, lx + ox, ly + oy, LF[tn])
        outline16(g, LF[0])

    elif item_id == "sorrel_leaf":
        # Trifoliate heart-shaped wood sorrel clover + tiny white bell
        line_px(g, 8, 13, 8, 8, LF[2])
        for cx_s, cy_s in ((5, 7), (8, 5), (11, 7)):
            disc(g, cx_s, cy_s, 2.0, LF)
        put(g, 11, 4, CR[3])
        put(g, 10, 5, LF[3])
        outline16(g, LF[0])

    elif item_id == "nettle_fiber":
        # Combed skein of silky pale sage-green nettle bast fiber bound with gold thread
        for offset in (-1, 0, 1):
            line_px(g, 4 + offset, 12, 11 + offset, 4, SG[4 if offset <= 0 else 3])
            line_px(g, 4, 11 + offset, 12, 5 + offset, SG[3 if offset <= 0 else 2])
        line_px(g, 7, 7, 9, 9, GD[3])
        outline16(g, SG[0])

    elif item_id == "meadowsweet_sprig":
        # Foamy cream meadowsweet blossom plume on reddish stem
        line_px(g, 5, 13, 8, 8, RH[2])
        line_px(g, 4, 11, 7, 10, LF[3])
        disc(g, 9.0, 6.0, 3.0, CR)
        disc(g, 6.5, 7.5, 2.1, CR)
        outline16(g, LF[0])

    elif item_id == "rosehip":
        # Pair of glossy carmine-ruby rosehips with green leafy calyx tails
        line_px(g, 5, 4, 8, 6, LF[3])
        line_px(g, 4, 5, 6, 5, LF[2])
        disc(g, 6.5, 9.5, 2.5, RH)
        disc(g, 10.5, 8.0, 2.4, RH)
        put(g, 6, 12, WD[1])
        put(g, 11, 10, WD[1])
        outline16(g, RH[0])

    elif item_id == "elder_blossom":
        # Broad lacy cream elderflower umbel plate with golden pollen dots
        line_px(g, 8, 13, 8, 9, LF[3])
        line_px(g, 5, 9, 11, 9, LF[2])
        for y in range(4, 9):
            hw = 4 if y in (6, 7) else 3
            for x in range(8 - hw, 8 + hw + 1):
                put(g, x, y, GD[4] if (x + y) % 4 == 0 else CR[3 if x + y < 14 else 2])
        outline16(g, LF[0])

    elif item_id == "elderberry":
        # Drooping cluster of glossy plum-violet elderberries on red stemlets
        line_px(g, 8, 3, 8, 6, RH[2])
        line_px(g, 5, 6, 11, 6, RH[2])
        for bx, by in ((5, 8), (8, 8), (11, 8), (6, 10), (9, 10), (8, 12)):
            disc(g, bx, by, 1.5, EL)
        outline16(g, EL[0])

    elif item_id == "sloe_berry":
        # Twinned pruinose slate-blue sloe berries hanging directly from thorny twig
        line_px(g, 3, 6, 12, 5, WD[2])
        put(g, 11, 4, WD[3])
        line_px(g, 6, 6, 6, 8, LF[2])
        line_px(g, 10, 5, 10, 7, LF[2])
        disc(g, 6.2, 9.5, 2.5, SL)
        disc(g, 10.2, 8.8, 2.5, SL)
        outline16(g, SL[0])

    elif item_id == "wild_blackberry":
        # Plump multi-drupelet glossy dark-purple blackberry + green sepal crown
        for dx, dy in ((-1.2, -1.0), (1.2, -1.0), (-1.6, 0.8), (0.0, 0.5), (1.6, 0.8), (-0.8, 2.3), (0.8, 2.3)):
            disc(g, 8.0 + dx, 8.5 + dy, 1.4, EL)
        for lx in range(6, 11):
            put(g, lx, 5, LF[3 if lx <= 8 else 2])
        put(g, 8, 4, LF[4])
        outline16(g, EL[0])

    elif item_id == "rose_briar_cutting":
        # Rooted woody wild-rose cutting with fresh green shoot & blush rosebud
        line_px(g, 6, 13, 9, 5, WD[2])
        line_px(g, 5, 13, 8, 12, WD[3])
        line_px(g, 9, 8, 12, 7, LF[3])
        disc(g, 9.5, 4.5, 1.7, RH)
        outline16(g, WD[0])

    elif item_id == "waybread_poultice":
        # Rolled herbal leaf bandage tied with golden-sage fiber cord
        for y in range(5, 12):
            for x in range(4, 13):
                if abs((x - 8) * 0.8 + (y - 8) * 0.4) <= 3.6:
                    put(g, x, y, LF[4 if x + y < 14 else (3 if x + y < 17 else 2)])
        line_px(g, 7, 5, 9, 11, SG[4])
        line_px(g, 6, 8, 10, 8, GD[3])
        outline16(g, LF[0])

    elif item_id == "elder_rosehip_tea":
        # Steaming stoneware herbal cup filled with ruby-violet elder-rosehip infusion!
        for y in range(7, 13):
            for x in range(4, 12):
                if (x - 7.5) ** 2 / 14.0 + (y - 9.5) ** 2 / 9.0 <= 1.0:
                    put(g, x, y, CR[3 if x <= 7 else 2])
        put(g, 12, 9, CR[2])
        put(g, 12, 10, CR[1])
        for x in range(5, 11):
            put(g, x, 7, RH[3 if x <= 7 else 2])
        # Delicate steam wisps
        put(g, 6, 4, CR[3])
        put(g, 7, 3, CR[3])
        put(g, 9, 4, CR[2])
        outline16(g, WD[0])

    else:  # nettle_linen
        # Folded bolt of fine pale sage-ivory woven nettle cloth with violet selvedge stripe
        for y in range(5, 12):
            for x in range(3, 13):
                put(g, x, y, SG[4 if y <= 6 or x <= 5 else (3 if y <= 9 else 2)])
        line_px(g, 4, 10, 11, 10, VL[3])
        outline16(g, SG[0])

    return g


ITEM_IDS = [
    "waybread_leaf",
    "stonecrop_gold",
    "silver_yarrow",
    "chicory_petal",
    "wild_thyme",
    "rune_blossom",
    "mullein_torch_head",
    "star_dew_drop",
    "dusk_spur",
    "ivy_tendril",
    "sorrel_leaf",
    "nettle_fiber",
    "meadowsweet_sprig",
    "rosehip",
    "elder_blossom",
    "elderberry",
    "sloe_berry",
    "wild_blackberry",
    "rose_briar_cutting",
    "waybread_poultice",
    "elder_rosehip_tea",
    "nettle_linen",
]


def scale_nearest(grid: list[list[tuple[int, int, int, int]]], factor: int) -> list[list[tuple[int, int, int, int]]]:
    out = []
    for row in grid:
        sr = []
        for p in row:
            sr.extend([p] * factor)
        for _ in range(factor):
            out.append(list(sr))
    return out


def main() -> None:
    items_dir = PROJ_ROOT / "assets" / "items"
    icons = []
    for iid in ITEM_IDS:
        ic = draw_icon(iid)
        icons.append(ic)
        write_png(items_dir / f"{iid}.png", 16, 16, ic)

    cols = 6
    rows = math.ceil(len(icons) / cols)
    pad = 4
    w = cols * (16 + pad) + pad
    h = rows * (16 + pad) + pad
    bg = hexc("1e1a36")  # Official UI panel dark (#1e1a36 from Design Guide Row 12!)
    sheet = [[bg] * w for _ in range(h)]
    for idx, ic in enumerate(icons):
        gx = pad + (idx % cols) * (16 + pad)
        gy = pad + (idx // cols) * (16 + pad)
        for y in range(16):
            for x in range(16):
                if ic[y][x][3] > 0:
                    sheet[gy + y][gx + x] = ic[y][x]

    qa_out = PROJ_ROOT / "docs" / "img" / "sanctuary_items_4x.png"
    scaled = scale_nearest(sheet, 4)
    write_png(qa_out, len(scaled[0]), len(scaled), scaled)
    print(f"Wrote {len(ITEM_IDS)} 16x16 botanical item icons + {qa_out}")


if __name__ == "__main__":
    main()
