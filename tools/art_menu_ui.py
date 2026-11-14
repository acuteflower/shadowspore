#!/usr/bin/env python3
"""Deterministic pixel-art generator for Shadowspore main menu & multiplayer UI icons.

Outputs:
  - assets/ui/menu_icons.png      (168x12 RGBA strip, 14 frames of 12x12 px)
  - assets/ui/menu_icons_glow.png (168x12 RGBA additive/unlit glow strip)
  - scratch preview PNG           (6x + 1x contact sheet on dark tiles with labels 0..13)
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

FRAME_SIZE = 12
NUM_FRAMES = 14
STRIP_W = FRAME_SIZE * NUM_FRAMES
STRIP_H = FRAME_SIZE

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_BASE = REPO_ROOT / "assets" / "ui" / "menu_icons.png"
OUT_GLOW = REPO_ROOT / "assets" / "ui" / "menu_icons_glow.png"
OUT_PREVIEW = Path(
    r"C:\Users\levin\.gemini\antigravity\brain\9d349126-08bf-4186-b20b-b9d860c1c4dc\scratch\menu_icons_preview.png"
)


def hex_rgba(hex_code: str, alpha: int = 255) -> tuple[int, int, int, int]:
    h = hex_code.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


TRANSPARENT = (0, 0, 0, 0)
OUTLINE_VOID = hex_rgba("#1b1a2e")
OUTLINE_UMBER = hex_rgba("#2d211b")

# Frame definitions: (label, palette_map, base_grid_12x12, glow_points [(x, y, hex, alpha), ...])
FRAMES: list[tuple[str, dict[str, tuple[int, int, int, int]], list[str], list[tuple[int, int, str, int]]]] = [
    # 0: Audio horn/chime (TON) — warm brass/gold #ffd98a + bronze #8c5a3c
    (
        "0 TON",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_UMBER,
            "H": hex_rgba("#fff0b0"),
            "L": hex_rgba("#ffd98a"),
            "G": hex_rgba("#d49a4a"),
            "B": hex_rgba("#8c5a3c"),
            "D": hex_rgba("#5e3924"),
        },
        [
            "....OO......",
            "...OHLO.OO..",
            "..OHLLOOHLO.",
            ".OOLLLOOOHO.",
            "OHLGGLO..OLO",
            "OLGGBBO..OLO",
            "OBBDBBO.OOGO",
            ".OODBBOOLGO.",
            "..ODBBO.OO..",
            "...ODBO.....",
            "....OO......",
            "............",
        ],
        [],
    ),
    # 1: Moonlit lens (BILD) — cool silver-lavender #dcd0ff + cyan glint #7fe3da
    (
        "1 BILD",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "H": hex_rgba("#f5eeff"),
            "S": hex_rgba("#dcd0ff"),
            "L": hex_rgba("#b1a1de"),
            "M": hex_rgba("#8070b3"),
            "D": hex_rgba("#554785"),
            "W": hex_rgba("#d0fff8"),
            "C": hex_rgba("#7fe3da"),
            "c": hex_rgba("#3cc0c6"),
            "n": hex_rgba("#342e66"),
            "B": hex_rgba("#221d47"),
        },
        [
            "....OOOO....",
            "..OOHSSLOO..",
            ".OHSccccLMO.",
            ".OSWCCccnMO.",
            "OHSCCccnnnDO",
            "OSLcccnnnBDO",
            "OSLccnnnBBDO",
            "OLMcnnnBCcDO",
            ".OMnnnBCcDO.",
            ".OOMnBBDDOO.",
            "..OODDDDOO..",
            "....OOOO....",
        ],
        [
            (3, 3, "#d0fff8", 220),
            (4, 3, "#7fe3da", 180),
            (3, 4, "#7fe3da", 180),
        ],
    ),
    # 2: Sprout seed compass (SPIEL) — leaf green #a6e68f / #4e8f4d + gold center #ffd98a
    (
        "2 SPIEL",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "H": hex_rgba("#d2f7be"),
            "L": hex_rgba("#a6e68f"),
            "G": hex_rgba("#67b35d"),
            "D": hex_rgba("#4e8f4d"),
            "M": hex_rgba("#2f624e"),
            "W": hex_rgba("#fff0b0"),
            "Y": hex_rgba("#ffd98a"),
            "y": hex_rgba("#c99242"),
            "b": hex_rgba("#8c5a3c"),
        },
        [
            ".....OO.....",
            "....OHLO....",
            "...OHLLGO...",
            "...OLLGGO...",
            "OOOHLbYGDOOO",
            "OHLLWWYGDDMO",
            "OLLGYYyGDDMO",
            "OOOGGybDMOOO",
            "...OGDDMO...",
            "...OGDDMO...",
            "....ODMO....",
            ".....OO.....",
        ],
        [
            (5, 5, "#fff0b0", 210),
            (6, 5, "#ffd98a", 180),
            (5, 6, "#ffd98a", 180),
            (6, 6, "#ffd98a", 140),
        ],
    ),
    # 3: Stone keycap (TASTEN) — slate #4a4180, ivory face #e8e4f4, tiny green moss pixel
    (
        "3 TASTEN",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "W": hex_rgba("#ffffff"),
            "I": hex_rgba("#e8e4f4"),
            "J": hex_rgba("#cbc4e0"),
            "K": hex_rgba("#afa6cc"),
            "L": hex_rgba("#766bb0"),
            "S": hex_rgba("#4a4180"),
            "D": hex_rgba("#322b5c"),
            "R": hex_rgba("#5e5399"),
            "r": hex_rgba("#7d72b8"),
            "M": hex_rgba("#a6e68f"),
            "m": hex_rgba("#67b35d"),
            "G": hex_rgba("#4e8f4d"),
        },
        [
            "............",
            "..OOOOOOOO..",
            ".OLWIIIIJSO.",
            ".OLIIrIIJSO.",
            ".OLIrRrIJSO.",
            ".OLIIIIJJSO.",
            ".OLJJJJKKSO.",
            ".OMmSSSSSSO.",
            ".OGmSDDDDDO.",
            "..OOOOOOOO..",
            "............",
            "............",
        ],
        [],
    ),
    # 4: Glowing ember lantern (HOST / ONLINE) — bronze frame #8c5a3c, bright amber flame #ffd98a (flame in glow)
    (
        "4 HOST",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_UMBER,
            "H": hex_rgba("#e0ab58"),
            "B": hex_rgba("#8c5a3c"),
            "M": hex_rgba("#5c3824"),
            "c": hex_rgba("#4a291e"),
            "W": hex_rgba("#fff0b0"),
            "F": hex_rgba("#ffd98a"),
            "f": hex_rgba("#e89c52"),
            "d": hex_rgba("#b86435"),
        },
        [
            "....OOOO....",
            "...OOHBOO...",
            "..OOHBBMOO..",
            ".OOHBBBBMOO.",
            "..OBcFFcMO..",
            "..OBfWWfMO..",
            "..OBFWWFMO..",
            "..OBfFFdMO..",
            ".OOHBBBBMOO.",
            "..OOMMMMOO..",
            "....OOOO....",
            "............",
        ],
        [
            (5, 4, "#ffd98a", 210),
            (6, 4, "#e89c52", 180),
            (4, 5, "#e89c52", 180),
            (5, 5, "#fff0b0", 255),
            (6, 5, "#fff0b0", 240),
            (7, 5, "#e89c52", 180),
            (4, 6, "#ffd98a", 210),
            (5, 6, "#fff0b0", 255),
            (6, 6, "#fff0b0", 255),
            (7, 6, "#ffd98a", 210),
            (4, 7, "#e89c52", 170),
            (5, 7, "#ffd98a", 220),
            (6, 7, "#ffd98a", 220),
            (7, 7, "#e89c52", 160),
        ],
    ),
    # 5: Shared coop hearth/camp tent (KOOP-WELT) — warm oak/terracotta #9c6340, glowing amber entrance #ffd98a
    (
        "5 KOOP",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_UMBER,
            "H": hex_rgba("#d99b6c"),
            "T": hex_rgba("#9c6340"),
            "S": hex_rgba("#78482d"),
            "M": hex_rgba("#57321e"),
            "B": hex_rgba("#633922"),
            "W": hex_rgba("#fff0b0"),
            "F": hex_rgba("#ffd98a"),
            "f": hex_rgba("#e89c52"),
        },
        [
            "...OO..OO...",
            "...OHOOTO...",
            "....OHTO....",
            "...OHTTTO...",
            "..OHTTTTSO..",
            ".OHTTFWFSSO.",
            "OHTTFWWFSSMO",
            "OTTTWWWWSSMO",
            "OTTTWWFFSSMO",
            "OBBBfFFfMMMO",
            "OOOOOOOOOOOO",
            "............",
        ],
        [
            (5, 5, "#ffd98a", 190),
            (6, 5, "#fff0b0", 220),
            (4, 6, "#e89c52", 180),
            (5, 6, "#fff0b0", 250),
            (6, 6, "#fff0b0", 250),
            (7, 6, "#e89c52", 180),
            (4, 7, "#ffd98a", 220),
            (5, 7, "#fff0b0", 255),
            (6, 7, "#fff0b0", 255),
            (7, 7, "#ffd98a", 220),
            (4, 8, "#ffd98a", 210),
            (5, 8, "#fff0b0", 240),
            (6, 8, "#ffd98a", 220),
            (7, 8, "#e89c52", 190),
            (5, 9, "#ffd98a", 190),
            (6, 9, "#ffd98a", 190),
        ],
    ),
    # 6: Ancient rune key (CODE) — gold #ffd98a, glowing teal crystal tooth #7fe3da (tooth in glow)
    (
        "6 CODE",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "H": hex_rgba("#fff0b0"),
            "L": hex_rgba("#ffd98a"),
            "G": hex_rgba("#d49a4a"),
            "B": hex_rgba("#8c5a3c"),
            "W": hex_rgba("#d0fff8"),
            "C": hex_rgba("#7fe3da"),
            "c": hex_rgba("#3cc0c6"),
        },
        [
            "............",
            "............",
            ".OOOO.......",
            "OHHHLO......",
            "OHOLGLOOOOO.",
            "OHOLHHHHHHLO",
            "OLGGGGGGWCcO",
            "OGBBBOOWOCcO",
            ".OOOO..OOCCO",
            "........OOOO",
            "............",
            "............",
        ],
        [
            (8, 6, "#d0fff8", 240),
            (9, 6, "#7fe3da", 220),
            (10, 6, "#3cc0c6", 200),
            (7, 7, "#d0fff8", 255),
            (9, 7, "#7fe3da", 240),
            (10, 7, "#3cc0c6", 210),
            (9, 8, "#7fe3da", 230),
            (10, 8, "#7fe3da", 230),
        ],
    ),
    # 7: Twin parchment scrolls (KOPIEREN) — cream #e6dcc8 + warm shadow #a69b8d
    (
        "7 KOPIEREN",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_UMBER,
            "W": hex_rgba("#fff9eb"),
            "H": hex_rgba("#f2ead8"),
            "C": hex_rgba("#e6dcc8"),
            "S": hex_rgba("#c2b6a5"),
            "M": hex_rgba("#a69b8d"),
            "D": hex_rgba("#877c6f"),
            "l": hex_rgba("#948779"),
        },
        [
            ".OOOOOO.....",
            "OWHHHCSO....",
            "OClllCSO....",
            "OCCCCOOOOOO.",
            "OCllOWHHHCSO",
            "OCCCOClllCSO",
            "OMMMOCCCCCSO",
            ".OOOOCllCCSO",
            "....OCCCCCSO",
            "....OMMMMMDO",
            ".....OOOOOO.",
            "............",
        ],
        [],
    ),
    # 8: Host crown (HOST) — 3-peak gold #ffd98a + bright core #fff0b0
    (
        "8 KRONE",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_UMBER,
            "W": hex_rgba("#fff0b0"),
            "H": hex_rgba("#ffe79e"),
            "L": hex_rgba("#ffd98a"),
            "G": hex_rgba("#d49a4a"),
            "B": hex_rgba("#9c6839"),
        },
        [
            "............",
            "....OOOO....",
            "OOO.OWLO.OOO",
            "OWO.OWLO.OLO",
            "OWLOOWWOOLGO",
            "OWLLWWWWLGGO",
            "OLLGWWWWGGBO",
            "OGGGGGGGGGBO",
            ".OBBBBBBBBO.",
            "..OOOOOOOO..",
            "............",
            "............",
        ],
        [
            (5, 5, "#fff0b0", 210),
            (6, 5, "#fff0b0", 210),
            (5, 6, "#ffd98a", 190),
            (6, 6, "#ffd98a", 190),
        ],
    ),
    # 9: Neutral pale spore diamond (SPIELER) — pure pale/white/cool-silver (#ffffff, #dcd8f0, #9aa0bc)
    (
        "9 SPIELER",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "W": hex_rgba("#ffffff"),
            "P": hex_rgba("#eeeefa"),
            "L": hex_rgba("#dcd8f0"),
            "S": hex_rgba("#b8bdd6"),
            "M": hex_rgba("#9aa0bc"),
        },
        [
            ".....OO.....",
            "....OWWO....",
            "...OWWWLO...",
            "..OWWWPLSO..",
            ".OWWWWLSSMO.",
            ".OWPWWLSSMO.",
            ".OLLWWSSMMO.",
            ".OLLLLSMMMO.",
            "..OLLSMMMO..",
            "...OSMMMO...",
            "....OMMO....",
            ".....OO.....",
        ],
        [],
    ),
    # 10: Wilted crimson thorn X (LÖSCHEN) — ember crimson #e86c7a + bright coral highlight #ffb4a8
    (
        "10 DEL",
        {
            ".": TRANSPARENT,
            "O": hex_rgba("#291522"),
            "H": hex_rgba("#ffb4a8"),
            "R": hex_rgba("#e86c7a"),
            "C": hex_rgba("#bf4359"),
            "D": hex_rgba("#872940"),
        },
        [
            ".OO......OO.",
            "OHRO....OHRO",
            "ORHRO..ORCRO",
            ".ORHROORCRO.",
            "..ORHRRCRO..",
            "...OHRRCO...",
            "...ORRCDO...",
            "..ORCRRCDO..",
            ".ORCROORCDO.",
            "ORCRO..ORCDO",
            "OCDO....OCDO",
            ".OO......OO.",
        ],
        [],
    ),
    # 11: Sprout + spark (NEUE WELT) — spring emerald #a6e68f sprout + cyan dew spark #7fe3da (spark in glow)
    (
        "11 NEU",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "H": hex_rgba("#d4f7c1"),
            "L": hex_rgba("#a6e68f"),
            "G": hex_rgba("#63b058"),
            "D": hex_rgba("#3e7d56"),
            "W": hex_rgba("#d0fff8"),
            "C": hex_rgba("#7fe3da"),
            "c": hex_rgba("#3cc0c6"),
        },
        [
            "........O...",
            ".......OCO..",
            ".OOO..OCWCO.",
            "OHHLO..OcO..",
            "OHLLGO..O...",
            ".OLLGGO.OOO.",
            "..OOOLGOHLLO",
            "....OLGGLLGO",
            "....OGDOGGDO",
            "....OGDOOOO.",
            "...OOGDO....",
            "...OOOO.....",
        ],
        [
            (8, 1, "#7fe3da", 220),
            (7, 2, "#7fe3da", 220),
            (8, 2, "#d0fff8", 255),
            (9, 2, "#7fe3da", 220),
            (8, 3, "#3cc0c6", 200),
        ],
    ),
    # 12: Reroll curved arrows (NEUER CODE) — bright cyan #7fe3da / #b9f3ee
    (
        "12 REROLL",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "W": hex_rgba("#d0fff8"),
            "H": hex_rgba("#b9f3ee"),
            "C": hex_rgba("#7fe3da"),
            "c": hex_rgba("#3cc0c6"),
        },
        [
            ".......OOO..",
            "..OOOOOOWOO.",
            ".OWWHHHHCCO.",
            ".OHCOOOOCOO.",
            ".OCO....OO..",
            ".OcO....OOO.",
            ".OOO....OHO.",
            "..OO....OCO.",
            ".OOWOOOOCcO.",
            ".OWWHCCCCcO.",
            ".OOcOOOOOO..",
            "..OOO.......",
        ],
        [],
    ),
    # 13: Join portal arch + entering arrow (BEITRETEN) — violet arch #8b6bd6, cyan arrow #7fe3da (core in glow)
    (
        "13 JOIN",
        {
            ".": TRANSPARENT,
            "O": OUTLINE_VOID,
            "H": hex_rgba("#cbaaff"),
            "V": hex_rgba("#8b6bd6"),
            "S": hex_rgba("#6636ad"),
            "D": hex_rgba("#462380"),
            "p": hex_rgba("#2b1652"),
            "u": hex_rgba("#9468ee"),
            "W": hex_rgba("#d0fff8"),
            "C": hex_rgba("#7fe3da"),
            "c": hex_rgba("#3cc0c6"),
        },
        [
            ".....OOOOO..",
            "....OHVVVSO.",
            "...OHVpppVSO",
            "...OWOpuuVSO",
            "OOOOWCOuCVSO",
            "OWCCCWWOWCSO",
            "OOOOcCOuCVSO",
            "...OcOpuuVSO",
            "...OVSpupVSO",
            "...OVSpppVSO",
            "..OOVSSSSDOO",
            "..OOOOOOOOOO",
        ],
        [
            (5, 5, "#7fe3da", 200),
            (6, 5, "#d0fff8", 245),
            (7, 4, "#9468ee", 190),
            (8, 4, "#7fe3da", 230),
            (8, 5, "#d0fff8", 255),
            (9, 5, "#7fe3da", 230),
            (7, 6, "#9468ee", 190),
            (8, 6, "#7fe3da", 230),
            (7, 3, "#9468ee", 150),
            (7, 7, "#9468ee", 150),
        ],
    ),
]


# Crisp 3x5 bitmap font for preview labels (zero anti-aliasing)
MINI_FONT_3X5: dict[str, list[str]] = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "010", "010"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
    "A": ["111", "101", "111", "101", "101"],
    "B": ["110", "101", "110", "101", "110"],
    "C": ["111", "100", "100", "100", "111"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"],
    "G": ["111", "100", "101", "101", "111"],
    "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "J": ["001", "001", "001", "101", "111"],
    "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"],
    "M": ["101", "111", "111", "101", "101"],
    "N": ["111", "101", "101", "101", "101"],
    "O": ["111", "101", "101", "101", "111"],
    "P": ["111", "101", "111", "100", "100"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["111", "100", "111", "001", "111"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "W": ["101", "101", "111", "111", "101"],
    "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"],
    "+": ["000", "010", "111", "010", "000"],
    " ": ["000", "000", "000", "000", "000"],
}


def draw_pixel_text(
    img: Image.Image,
    text: str,
    x: int,
    y: int,
    color: tuple[int, int, int, int],
    scale: int = 2,
) -> None:
    px = img.load()
    cx = x
    for ch in text.upper():
        glyph = MINI_FONT_3X5.get(ch, MINI_FONT_3X5[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            tx = cx + gx * scale + sx
                            ty = y + gy * scale + sy
                            if 0 <= tx < img.width and 0 <= ty < img.height:
                                px[tx, ty] = color
        cx += 4 * scale


def additive_composite(base: Image.Image, glow: Image.Image) -> Image.Image:
    out = base.copy()
    bp = out.load()
    gp = glow.load()
    for y in range(out.height):
        for x in range(out.width):
            br, bg, bb, ba = bp[x, y]
            gr, gg, gb, ga = gp[x, y]
            if ga == 0:
                continue
            af = ga / 255.0
            nr = min(255, int(round(br + gr * af * 0.75)))
            ng = min(255, int(round(bg + gg * af * 0.75)))
            nb = min(255, int(round(bb + gb * af * 0.75)))
            na = max(ba, ga)
            bp[x, y] = (nr, ng, nb, na)
    return out


def build_strips() -> tuple[Image.Image, Image.Image]:
    assert len(FRAMES) == NUM_FRAMES, f"Expected {NUM_FRAMES} frames, got {len(FRAMES)}"
    base_img = Image.new("RGBA", (STRIP_W, STRIP_H), TRANSPARENT)
    glow_img = Image.new("RGBA", (STRIP_W, STRIP_H), TRANSPARENT)
    base_px = base_img.load()
    glow_px = glow_img.load()

    for idx, (label, pal, grid, glow_pts) in enumerate(FRAMES):
        assert len(grid) == FRAME_SIZE, f"Frame {idx} ({label}) height != {FRAME_SIZE}"
        ox = idx * FRAME_SIZE
        for y, row in enumerate(grid):
            assert len(row) == FRAME_SIZE, f"Frame {idx} ({label}) row {y} width {len(row)} != {FRAME_SIZE}"
            for x, ch in enumerate(row):
                assert ch in pal, f"Frame {idx} ({label}) unknown symbol {ch!r}"
                c = pal[ch]
                if c[3] > 0:
                    base_px[ox + x, y] = c
        for gx, gy, ghex, galpha in glow_pts:
            assert 0 <= gx < FRAME_SIZE and 0 <= gy < FRAME_SIZE
            glow_px[ox + gx, gy] = hex_rgba(ghex, galpha)

    return base_img, glow_img


def build_preview(base_img: Image.Image, glow_img: Image.Image) -> Image.Image:
    scale = 6
    tile_px = FRAME_SIZE * scale  # 72x72
    pad = 12
    cols = 7
    rows = 2
    cell_w = tile_px + 20
    cell_h = tile_px + 34

    header_h = 30
    section_gap = 20
    comp_img = additive_composite(base_img, glow_img)

    # Preview layout:
    # Section 1: 6x Composite (Base + Glow) on alternating #1b1a2e / #241e3a tiles with frame numbers 0..13
    # Section 2: 6x Glow Mask Only on #121020 tiles
    # Section 3: True 1x pixel-exact strip + runtime modulate tint test for Frame 9
    width = pad * 2 + cols * cell_w
    height = (
        pad
        + header_h
        + rows * cell_h
        + section_gap
        + header_h
        + rows * (tile_px + 22)
        + section_gap
        + 54
        + pad
    )

    bg_dark = hex_rgba("#141224")
    tile_a = hex_rgba("#1b1a2e")
    tile_b = hex_rgba("#241e3a")
    tile_glow = hex_rgba("#100e1c")
    border_col = hex_rgba("#3d3560")
    label_col = hex_rgba("#ffd98a")
    sub_col = hex_rgba("#b8b2d6")

    sheet = Image.new("RGBA", (width, height), bg_dark)
    draw = ImageDraw.Draw(sheet)

    draw_pixel_text(sheet, "MENU ICONS 6X BASE+GLOW", pad, pad + 4, label_col, scale=2)

    y_sec1 = pad + header_h
    for idx in range(NUM_FRAMES):
        r = idx // cols
        c = idx % cols
        cx = pad + c * cell_w
        cy = y_sec1 + r * cell_h
        tcol = tile_a if (r + c) % 2 == 0 else tile_b
        draw.rectangle([cx, cy, cx + tile_px + 7, cy + tile_px + 7], fill=tcol, outline=border_col)

        crop = comp_img.crop((idx * FRAME_SIZE, 0, (idx + 1) * FRAME_SIZE, FRAME_SIZE))
        up = crop.resize((tile_px, tile_px), resample=Image.Resampling.NEAREST)
        sheet.alpha_composite(up, (cx + 4, cy + 4))

        short_label = FRAMES[idx][0]
        draw_pixel_text(sheet, short_label, cx + 2, cy + tile_px + 12, label_col if idx < 10 else sub_col, scale=2)

    y_sec2_title = y_sec1 + rows * cell_h + section_gap
    draw_pixel_text(sheet, "GLOW MASK ONLY 6X", pad, y_sec2_title, hex_rgba("#7fe3da"), scale=2)
    y_sec2 = y_sec2_title + header_h
    for idx in range(NUM_FRAMES):
        r = idx // cols
        c = idx % cols
        cx = pad + c * cell_w
        cy = y_sec2 + r * (tile_px + 22)
        draw.rectangle([cx, cy, cx + tile_px + 7, cy + tile_px + 7], fill=tile_glow, outline=border_col)

        crop = glow_img.crop((idx * FRAME_SIZE, 0, (idx + 1) * FRAME_SIZE, FRAME_SIZE))
        up = crop.resize((tile_px, tile_px), resample=Image.Resampling.NEAREST)
        sheet.alpha_composite(up, (cx + 4, cy + 4))
        draw_pixel_text(sheet, str(idx), cx + 4, cy + tile_px + 10, sub_col, scale=2)

    # Bottom bar: 1x pixel-exact strip + 2x strip + Frame 9 modulate tint test
    y_sec3 = y_sec2 + rows * (tile_px + 22) + section_gap
    draw_pixel_text(sheet, "1X STRIP", pad, y_sec3 + 4, label_col, scale=2)
    strip_box_x = pad + 84
    draw.rectangle(
        [strip_box_x, y_sec3, strip_box_x + STRIP_W + 15, y_sec3 + STRIP_H + 15],
        fill=tile_a,
        outline=border_col,
    )
    sheet.alpha_composite(comp_img, (strip_box_x + 8, y_sec3 + 8))

    # 2x strip right next to 1x strip for viewport comparison
    strip2_x = strip_box_x + STRIP_W + 28
    draw.rectangle(
        [strip2_x, y_sec3, strip2_x + STRIP_W * 2 + 11, y_sec3 + STRIP_H * 2 + 11],
        fill=tile_b,
        outline=border_col,
    )
    up2 = comp_img.resize((STRIP_W * 2, STRIP_H * 2), resample=Image.Resampling.NEAREST)
    sheet.alpha_composite(up2, (strip2_x + 6, y_sec3 + 6))

    return sheet


def main() -> None:
    OUT_BASE.parent.mkdir(parents=True, exist_ok=True)
    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)

    base_img, glow_img = build_strips()
    base_img.save(OUT_BASE)
    glow_img.save(OUT_GLOW)

    preview_img = build_preview(base_img, glow_img)
    preview_img.save(OUT_PREVIEW)

    print(f"Wrote {OUT_BASE} ({base_img.width}x{base_img.height} {base_img.mode})")
    print(f"Wrote {OUT_GLOW} ({glow_img.width}x{glow_img.height} {glow_img.mode})")
    print(f"Wrote {OUT_PREVIEW} ({preview_img.width}x{preview_img.height} {preview_img.mode})")


if __name__ == "__main__":
    main()
