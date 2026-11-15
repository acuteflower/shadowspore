#!/usr/bin/env python3
"""Jorun's dialogue portrait (103x153 RGBA, hard alpha, <=32 palette colours).

    py -3 tools/art_portrait_jorun.py [preview.png]

Writes `assets/ui/portrait_jorun.png` (and optional comparison preview sheet if a path is passed).
Matches `docs/dialogue_art.md`, `docs/design_guide.md`, and `tools/art_jorun.py`:
  * 103 x 153 px, three-quarter view facing right, eye level, cut cleanly at the hip (Y=152).
  * Hat/feather top ~Y 3-5, eyes ~Y 34-37, chin ~Y 59, broad shoulders ~Y 59-70 (~92% width).
  * Older, broad travelling merchant: wide-brimmed sun-faded brown felt hat with caravan-blue band
    and small charms (brass key, red glass bead, brass coin, grey feather); weathered sun-tanned
    face, bushy grey-brown brows, dark observant eyes, short full grey-brown beard & moustache;
    knotted caravan-blue (#3d5a8a) neckerchief; faded mustard waistcoat (#9a7c40) with brass buttons
    under open earth-brown travelling coat (#6e4c32); diagonal leather satchel strap across chest,
    belt with pouches, gnarled wooden walking staff with lantern hook & small brass road lantern.
  * Chunky planar pixel clusters, 30 colours total, 3-4 flat steps per material, crisp 1px #1f1d30 outline.
"""
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_PNG = ROOT / "assets/ui/portrait_jorun.png"
W, H = 103, 153


def hexc(s: str) -> tuple[int, int, int, int]:
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


# Unified 31-colour master palette derived from tools/art_jorun.py + #1f1d30 portrait outline
INK = hexc("1f1d30")         # 1  hard 1px outer contour & deepest cool-violet crease
UMBER = hexc("261a14")       # 2  shared deep warm-umber shadow (coat, leather, hat underside, dark iris)

SKIN0 = hexc("6a3e2c")       # 3  deep skin shadow (brim cast shadow, eye socket, neck shadow)
SKIN1 = hexc("9c6448")       # 4  warm mid-shadow skin (cheek furrow, nose underside, lip, fingers)
SKIN2 = hexc("c48a66")       # 5  weathered sun-tanned base skin
SKIN3 = hexc("e2b08a")       # 6  top-left sunlit skin highlight

HAIR0 = hexc("3a3028")       # 7  dark grey-brown beard / brow / hair shadow
HAIR1 = hexc("5e5044")       # 8  mid grey-brown beard & bushy brows
HAIR2 = hexc("857464")       # 9  lit grey-brown beard & moustache
HAIR3 = hexc("ad9c8a")       # 10 sunlit silver-taupe beard & hair highlight

HAT1 = hexc("3a2a1a")        # 11 felt hat shadow / dark lapel & cuff leather-brown
HAT2 = hexc("58422a")        # 12 sun-faded felt hat mid-tone
HAT3 = hexc("76603e")        # 13 sunlit felt crown & brim highlight

COAT1 = hexc("4a3222")       # 14 earth-brown coat shadow
COAT2 = hexc("6e4c32")       # 15 earth-brown travelling coat base (#6e4c32)
COAT3 = hexc("927048")       # 16 sunlit earth-brown coat shoulder & fold ridge

STRAP2 = hexc("5e3e28")      # 17 warm chestnut leather strap, belt, pouches & staff mid
STRAP3 = hexc("7e583a")      # 18 sunlit leather rim & carved staff crook highlight

VEST1 = hexc("74582a")       # 19 mustard waistcoat shadow & dark brass base
VEST2 = hexc("9a7c40")       # 20 faded mustard waistcoat base (#9a7c40)
VEST3 = hexc("bea25e")       # 21 sunlit mustard waistcoat highlight

BLUE0 = hexc("243556")       # 22 deep caravan-blue fold shadow
BLUE1 = hexc("3d5a8a")       # 23 caravan-blue neckerchief, hatband & coat hem trim (#3d5a8a)
BLUE2 = hexc("6f93c4")       # 24 sunlit caravan-blue highlight

BRASS1 = hexc("b4893a")      # 25 warm brass mid (buckles, buttons, key, coin, lantern cap)
BRASS2 = hexc("e6c468")      # 26 bright brass highlight & warm amber lantern glass
GLINT = hexc("fff0dc")       # 27 warm cream-white catchlight (eye glint, lantern core, feather tip)

RED1 = hexc("7a2f3c")        # 28 deep ruby glass charm & warm lip crease
RED2 = hexc("c85a58")        # 29 ruby glass glint

SLATE1 = hexc("464458")      # 30 cool violet-slate (trousers, feather shadow, right-rim bounce fill)
SLATE2 = hexc("9c9eac")      # 31 grey feather mid-light


class Painter:
    def __init__(self) -> None:
        self.img = np.zeros((H, W, 4), dtype=np.uint8)

    def poly(self, pts: list[tuple[float, float]], col: tuple[int, int, int, int]) -> np.ndarray:
        mask = np.zeros((H, W), dtype=bool)
        arr = np.asarray(pts, dtype=float)
        n = len(arr)
        y0 = max(0, int(math.floor(arr[:, 1].min())))
        y1 = min(H - 1, int(math.ceil(arr[:, 1].max())))
        for y in range(y0, y1 + 1):
            yc = y + 0.5
            xs: list[float] = []
            for i in range(n):
                x_a, y_a = arr[i]
                x_b, y_b = arr[(i + 1) % n]
                if (y_a <= yc < y_b) or (y_b <= yc < y_a):
                    xs.append(x_a + (yc - y_a) / (y_b - y_a) * (x_b - x_a))
            xs.sort()
            for a, b in zip(xs[0::2], xs[1::2]):
                xa = max(0, int(math.floor(a + 0.5)))
                xb = min(W, int(math.floor(b + 0.5)))
                if xb > xa:
                    mask[y, xa:xb] = True
        self.img[mask] = col
        return mask

    def cpoly(self, pts: list[tuple[float, float]], col: tuple[int, int, int, int], subdiv: int = 6) -> np.ndarray:
        arr = [np.asarray(p, dtype=float) for p in pts]
        n = len(arr)
        dense: list[tuple[float, float]] = []
        for i in range(n):
            p0, p1, p2, p3 = arr[(i - 1) % n], arr[i], arr[(i + 1) % n], arr[(i + 2) % n]
            for k in range(subdiv):
                t = k / subdiv
                v = 0.5 * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
                )
                dense.append((float(v[0]), float(v[1])))
        return self.poly(dense, col)

    def line(self, pts: list[tuple[float, float]], col: tuple[int, int, int, int], width: int = 1) -> None:
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            steps = max(1, int(round(max(abs(x1 - x0), abs(y1 - y0)) * 2)))
            for i in range(steps + 1):
                t = i / steps
                x = int(round(x0 + (x1 - x0) * t))
                y = int(round(y0 + (y1 - y0) * t))
                if width <= 1:
                    self.px(x, y, col)
                else:
                    r = width // 2
                    for dy in range(-r, width - r):
                        for dx in range(-r, width - r):
                            self.px(x + dx, y + dy, col)

    def rect(self, x0: int, y0: int, x1: int, y1: int, col: tuple[int, int, int, int]) -> None:
        xa, xb = max(0, x0), min(W, x1 + 1)
        ya, yb = max(0, y0), min(H, y1 + 1)
        if xb > xa and yb > ya:
            self.img[ya:yb, xa:xb] = col

    def px(self, x: int, y: int, col: tuple[int, int, int, int]) -> None:
        if 0 <= x < W and 0 <= y < H:
            self.img[y, x] = col

    def pixels(self, coords: list[tuple[int, int]], col: tuple[int, int, int, int]) -> None:
        for x, y in coords:
            self.px(x, y, col)

    def erase(self, coords: list[tuple[int, int]]) -> None:
        for x, y in coords:
            if 0 <= x < W and 0 <= y < H:
                self.img[y, x] = (0, 0, 0, 0)

    def add_outer_outline(self, col: tuple[int, int, int, int] = INK) -> None:
        """Add a crisp 1px 4-connected outer silhouette outline around non-transparent pixels."""
        fg = self.img[..., 3] > 0
        p = np.pad(fg, 1, mode="constant", constant_values=False)
        dil4 = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        ring = dil4 & ~fg
        # Keep bottom row Y=152 open inside the hip cut (only outline left/right sides at Y=152)
        ring[H - 1, :] = False
        for x in range(W):
            if not fg[H - 1, x] and ((x > 0 and fg[H - 1, x - 1]) or (x + 1 < W and fg[H - 1, x + 1])):
                ring[H - 1, x] = True
        self.img[ring] = col


def draw_jorun() -> Image.Image:
    cv = Painter()

    # =========================================================================
    # 1. BACK COLLAR & TORSO BASE (3/4 TURN TO RIGHT: CHEST CENTER ~ X=63)
    # =========================================================================
    # High coat back-collar rising behind the nape/ear
    cv.cpoly([(25, 53), (36, 50), (62, 55), (65, 65), (23, 66)], HAT1)
    cv.poly([(25, 53), (34, 51), (36, 61), (24, 62)], COAT2)
    cv.line([(25, 53), (33, 51)], COAT3, 1)

    # Dark slate-violet trousers visible at hip cut (X 36..78, Y 132..152)
    cv.poly([(36, 132), (78, 132), (78, 153), (36, 153)], UMBER)
    cv.poly([(46, 134), (69, 134), (68, 153), (45, 153)], SLATE1)
    cv.line([(62, 135), (63, 145), (62, 153)], INK, 1)
    cv.line([(52, 136), (50, 153)], UMBER, 1)

    # Faded mustard waistcoat (#9a7c40) — broad, stout 3/4 chest curving out to X=75
    cv.cpoly([(38, 68), (72, 68), (77, 94), (76, 127), (63, 132), (40, 128), (37, 98)], COAT1)
    cv.cpoly([(40, 70), (71, 70), (76, 95), (74, 126), (63, 130), (42, 127)], VEST1)
    cv.cpoly([(41, 72), (68, 73), (71, 98), (68, 125), (61, 128), (43, 125)], VEST2)
    # Sunlit upper-left & mid-rib planes (#bea25e)
    cv.poly([(44, 75), (60, 77), (61, 91), (46, 93)], VEST3)
    cv.poly([(46, 97), (59, 98), (60, 111), (46, 112)], VEST3)
    cv.poly([(46, 115), (57, 116), (56, 124), (47, 123)], VEST3)
    # Cloth tension creases across stout waistcoat
    cv.line([(48, 94), (60, 96), (70, 94)], VEST1, 1)
    cv.line([(48, 113), (61, 114), (71, 112)], VEST1, 1)
    cv.line([(49, 124), (62, 126), (70, 123)], COAT1, 1)
    # Waistcoat center button placket along 3/4 curve + 4 brass buttons
    cv.line([(63, 79), (66, 98), (65, 116), (64, 128)], COAT1, 1)
    for bx, by in ((62, 83), (64, 95), (64, 107), (63, 119)):
        cv.rect(bx, by, bx + 2, by + 2, COAT1)
        cv.rect(bx, by, bx + 1, by + 1, BRASS1)
        cv.px(bx, by, BRASS2)

    # =========================================================================
    # 2. DIAGONAL LEATHER SATCHEL STRAP ACROSS CHEST + BRASS BUCKLE
    # =========================================================================
    cv.poly([(37, 67), (44, 65), (76, 121), (70, 125)], COAT1)
    cv.poly([(36, 65), (43, 63), (75, 119), (69, 123)], HAT1)
    cv.poly([(37, 65), (42, 64), (74, 118), (70, 121)], STRAP2)
    cv.line([(38, 65), (53, 89)], STRAP3, 2)
    cv.line([(59, 98), (72, 119)], STRAP3, 1)
    # Chunky brass chest buckle (X 51..60, Y 87..97)
    cv.poly([(50, 89), (57, 86), (61, 93), (54, 97)], INK)
    cv.poly([(51, 89), (57, 87), (60, 93), (54, 96)], BRASS1)
    cv.line([(51, 89), (56, 87), (58, 90)], BRASS2, 1)
    cv.rect(53, 90, 56, 93, HAT1)
    cv.px(55, 91, BRASS2)

    # =========================================================================
    # 3. THICK WEATHERED NECK & SCULPTED CARAVAN-BLUE NECKERCHIEF (#3d5a8a)
    # =========================================================================
    cv.poly([(33, 48), (58, 52), (60, 65), (32, 63)], SKIN0)
    cv.poly([(34, 49), (47, 53), (47, 63), (33, 61)], SKIN1)
    cv.poly([(35, 50), (42, 52), (41, 60), (34, 59)], SKIN2)

    # Caravan-blue neckerchief: rolled folds around neck + knotted drape in open collar
    cv.cpoly([(29, 57), (44, 60), (63, 58), (67, 65), (64, 76), (59, 85), (50, 76), (35, 69), (28, 62)], BLUE0)
    cv.line([(29, 63), (44, 72), (59, 85), (65, 75), (67, 65)], INK, 1)
    cv.cpoly([(30, 58), (48, 61), (51, 69), (36, 67), (30, 62)], BLUE1)
    cv.poly([(31, 58), (44, 61), (43, 65), (31, 62)], BLUE2)
    cv.line([(34, 64), (48, 67)], BLUE0, 1)
    # Front knot & hanging tail
    cv.cpoly([(50, 63), (61, 62), (63, 70), (52, 71)], BLUE1)
    cv.poly([(51, 64), (58, 63), (57, 68), (51, 68)], BLUE2)
    cv.line([(50, 70), (62, 70)], BLUE0, 1)
    cv.cpoly([(52, 71), (63, 70), (63, 76), (59, 83), (53, 76)], BLUE1)
    cv.poly([(53, 72), (58, 72), (58, 79), (54, 76)], BLUE2)
    cv.line([(59, 72), (59, 81)], BLUE0, 1)

    # =========================================================================
    # 4. OPEN EARTH-BROWN TRAVELLING COAT (#6e4c32) — 3/4 DRAPE, COLLAR & LAPELS
    # =========================================================================
    cv.cpoly([(24, 56), (36, 59), (47, 76), (45, 108), (41, 153), (10, 153), (8, 118), (9, 72), (17, 60)], COAT1)
    cv.cpoly([(15, 61), (34, 60), (42, 77), (40, 114), (37, 153), (12, 153), (10, 116), (11, 72)], COAT2)
    cv.cpoly([(14, 62), (31, 59), (36, 70), (24, 78), (10, 74)], COAT3)
    cv.line([(10, 75), (23, 79), (36, 73)], HAT1, 1)
    cv.line([(11, 76), (23, 80), (35, 74)], COAT3, 1)

    # Near coat skirt below waist (clean earth-brown wool folds meeting belt & pouch)
    cv.poly([(11, 122), (39, 125), (41, 153), (10, 153)], COAT2)
    cv.poly([(11, 123), (22, 126), (20, 153), (11, 153)], COAT3)
    cv.poly([(22, 128), (26, 128), (25, 153), (21, 153)], COAT1)
    cv.poly([(34, 126), (39, 126), (41, 153), (35, 153)], COAT1)
    cv.line([(39, 125), (41, 153)], INK, 1)

    # Sculpted curved near lapel & notched collar
    cv.cpoly([(25, 55), (34, 58), (47, 77), (45, 116), (38, 113), (36, 82), (26, 65)], HAT1)
    cv.line([(36, 60), (48, 77), (46, 116)], INK, 1)
    cv.cpoly([(26, 56), (33, 59), (44, 77), (41, 98), (36, 82), (27, 65)], COAT1)
    cv.poly([(26, 56), (33, 60), (36, 69), (28, 66)], COAT2)
    cv.line([(26, 56), (34, 61), (44, 76)], COAT3, 1)
    cv.line([(33, 70), (42, 73)], INK, 1)

    # Far (viewer's right) foreshortened coat shoulder, lapel & skirt
    cv.cpoly([(64, 59), (79, 63), (90, 72), (94, 96), (91, 153), (74, 153), (72, 116), (69, 76)], UMBER)
    cv.cpoly([(68, 62), (79, 64), (89, 73), (92, 96), (89, 153), (75, 153), (73, 115)], COAT1)
    cv.poly([(69, 63), (81, 67), (85, 81), (74, 83)], COAT2)
    cv.cpoly([(65, 60), (73, 66), (78, 82), (77, 116), (72, 114), (71, 82), (65, 68)], HAT1)
    cv.line([(65, 61), (71, 76), (72, 114)], INK, 1)
    cv.line([(67, 62), (73, 74)], COAT2, 1)
    cv.line([(72, 72), (77, 74)], INK, 1)

    # =========================================================================
    # 5. HEAVY LEATHER BELT, BRASS BUCKLE & MERCHANT POUCHES (Y 124..152)
    # =========================================================================
    cv.poly([(38, 124), (76, 124), (76, 133), (38, 133)], INK)
    cv.poly([(39, 125), (75, 125), (75, 132), (39, 132)], HAT1)
    cv.poly([(40, 126), (73, 126), (73, 130), (40, 130)], STRAP2)
    cv.line([(41, 126), (58, 126)], STRAP3, 1)

    # Center-right brass belt buckle (X 59..68, Y 124..133)
    cv.rect(59, 124, 68, 133, INK)
    cv.rect(60, 125, 67, 132, VEST1)
    cv.rect(60, 125, 66, 131, BRASS1)
    cv.line([(60, 125), (66, 125)], BRASS2, 1)
    cv.line([(60, 125), (60, 130)], BRASS2, 1)
    cv.rect(62, 127, 65, 130, HAT1)
    cv.line([(63, 128), (66, 128)], BRASS2, 1)

    # Plump leather pouch 1 (front-left of belt: X 38..54, Y 129..149)
    cv.cpoly([(39, 129), (53, 129), (55, 141), (52, 149), (40, 149), (38, 140)], INK)
    cv.cpoly([(40, 130), (52, 130), (53, 141), (51, 148), (41, 148), (39, 140)], HAT1)
    cv.poly([(40, 135), (51, 135), (52, 146), (41, 147)], STRAP2)
    cv.poly([(40, 136), (47, 136), (46, 145), (41, 145)], STRAP3)
    cv.poly([(39, 130), (53, 130), (52, 137), (46, 139), (40, 137)], HAT1)
    cv.poly([(40, 131), (51, 131), (50, 136), (46, 138), (41, 136)], STRAP2)
    cv.line([(41, 131), (49, 131)], STRAP3, 1)
    cv.rect(45, 136, 47, 138, BRASS1)
    cv.px(45, 136, BRASS2)

    # Hip satchel & pouch 2 (viewer's right hip: X 69..88, Y 127..152)
    cv.cpoly([(70, 128), (86, 127), (89, 139), (87, 153), (71, 153), (69, 139)], INK)
    cv.poly([(71, 129), (85, 128), (87, 139), (85, 153), (72, 153)], UMBER)
    cv.poly([(72, 130), (83, 129), (85, 140), (83, 153), (73, 153)], HAT1)
    cv.poly([(72, 136), (80, 136), (81, 150), (73, 150)], STRAP2)
    cv.poly([(71, 129), (85, 128), (84, 137), (77, 139), (71, 136)], COAT1)
    cv.line([(72, 130), (81, 129)], STRAP2, 1)
    cv.rect(76, 136, 78, 139, BRASS1)
    cv.px(76, 136, BRASS2)

    # =========================================================================
    # 6. FAR ARM (VIEWER'S RIGHT: X 75..98, Y 68..139) — BENT WITH HAND ON HIP
    # =========================================================================
    cv.cpoly([(79, 68), (91, 74), (98, 92), (98, 108), (92, 122), (80, 118), (82, 102), (78, 86)], UMBER)
    cv.cpoly([(80, 70), (90, 75), (96, 92), (96, 107), (90, 119), (82, 116), (83, 101), (79, 86)], COAT1)
    cv.poly([(80, 71), (88, 76), (91, 90), (83, 93)], COAT2)
    cv.line([(95, 86), (97, 100), (95, 112), (91, 119)], SLATE1, 1)
    cv.line([(83, 98), (92, 102)], UMBER, 2)
    cv.line([(84, 104), (92, 107)], COAT2, 1)

    # Angled dark turned-back cuff at wrist
    cv.poly([(80, 112), (93, 117), (90, 126), (77, 120)], INK)
    cv.poly([(81, 113), (92, 118), (89, 124), (78, 119)], HAT1)
    cv.line([(81, 113), (89, 117)], COAT2, 1)

    # Weathered left hand resting on hip satchel/belt
    cv.cpoly([(76, 120), (87, 122), (89, 130), (84, 137), (76, 135), (74, 127)], INK)
    cv.cpoly([(77, 121), (86, 123), (87, 130), (83, 135), (77, 134), (75, 127)], SKIN0)
    cv.poly([(77, 121), (84, 123), (85, 129), (78, 132), (76, 127)], SKIN1)
    cv.poly([(77, 122), (82, 123), (82, 128), (77, 128)], SKIN2)
    cv.line([(75, 124), (78, 122)], SKIN3, 1)
    cv.line([(79, 130), (85, 131)], SKIN0, 1)
    cv.line([(78, 133), (83, 134)], UMBER, 1)

    # =========================================================================
    # 7. NEAR ARM (VIEWER'S LEFT: X 3..34, Y 63..125) — ORGANIC ELBOW & FOLDS
    # =========================================================================
    cv.cpoly([(17, 62), (31, 67), (30, 92), (27, 117), (12, 125), (4, 115), (3, 95), (9, 73)], COAT1)
    cv.line([(29, 74), (30, 96), (27, 116), (13, 125)], INK, 1)
    cv.cpoly([(10, 73), (27, 68), (27, 95), (23, 116), (10, 121), (5, 112), (5, 94)], COAT2)
    cv.poly([(11, 71), (23, 66), (22, 83), (11, 89), (7, 81)], COAT3)
    cv.poly([(5, 93), (17, 89), (19, 103), (9, 110), (4, 102)], COAT3)
    cv.poly([(6, 111), (13, 108), (15, 118), (8, 119)], COAT2)
    cv.poly([(11, 88), (25, 83), (26, 88), (12, 92)], COAT1)
    cv.line([(15, 87), (25, 83)], HAT1, 1)
    cv.poly([(9, 107), (22, 100), (23, 106), (11, 113)], COAT1)
    # Wide turned-back dark-brown coat cuff around right wrist
    cv.poly([(13, 105), (26, 100), (32, 116), (18, 123)], INK)
    cv.poly([(15, 106), (25, 102), (30, 115), (19, 121)], HAT1)
    cv.poly([(15, 106), (22, 103), (24, 110), (17, 113)], COAT2)

    # =========================================================================
    # 8. GNARLED WALKING STAFF, LANTERN HOOK, BRASS ROAD LANTERN & ANATOMICAL HAND
    # =========================================================================
    cv.poly([(26, 86), (32, 86), (36, 153), (30, 153)], UMBER)

    # Angled wooden staff shaft
    cv.poly([(22, 64), (28, 64), (32, 153), (26, 153)], INK)
    cv.poly([(23, 64), (27, 64), (31, 153), (27, 153)], HAT1)
    cv.poly([(23, 64), (25, 64), (29, 153), (27, 153)], STRAP2)
    cv.line([(23, 65), (25, 101)], STRAP3, 1)
    cv.line([(26, 121), (27, 153)], STRAP3, 1)

    # Carved wooden shepherd/merchant crook arching left at shoulder height
    cv.cpoly([(6, 68), (6, 61), (12, 57), (21, 58), (27, 64), (26, 71), (22, 66), (18, 62), (12, 62), (10, 68)], INK)
    cv.cpoly([(7, 67), (7, 61), (13, 58), (21, 59), (26, 65), (24, 68), (19, 61), (12, 61), (9, 67)], STRAP2)
    cv.line([(8, 61), (13, 58), (20, 59), (24, 63)], STRAP3, 1)
    # Brass ferrule band just above grip
    cv.poly([(24, 96), (29, 96), (29, 98), (24, 98)], BRASS1)
    cv.pixels([(24, 96), (25, 96)], BRASS2)

    # Small brass & warm-glowing road lantern suspended from hook tip
    cv.rect(7, 68, 10, 71, INK)
    cv.pixels([(8, 69), (9, 69), (8, 70)], BRASS2)
    cv.poly([(3, 75), (8, 71), (14, 75), (14, 77), (3, 77)], INK)
    cv.poly([(4, 75), (8, 72), (13, 75)], BRASS1)
    cv.line([(4, 75), (8, 72)], BRASS2, 1)
    cv.rect(4, 77, 13, 86, INK)
    cv.rect(5, 77, 12, 85, VEST1)
    cv.rect(6, 78, 11, 84, BRASS1)
    cv.rect(6, 78, 10, 83, BRASS2)
    cv.rect(7, 79, 9, 82, GLINT)
    cv.poly([(3, 85), (14, 85), (12, 89), (5, 89)], INK)
    cv.line([(4, 86), (13, 86)], BRASS1, 1)
    cv.line([(5, 86), (9, 86)], BRASS2, 1)

    # Anatomical right hand gripping staff (smooth sunlit dorsum flowing into 4 rounded fingers)
    cv.cpoly([(18, 106), (25, 101), (33, 103), (34, 116), (28, 120), (19, 118)], INK)
    cv.cpoly([(19, 106), (25, 102), (32, 104), (33, 115), (28, 119), (20, 117)], SKIN1)
    # Sunlit back-of-hand plane (X 19..27, Y 104..116)
    cv.poly([(19, 106), (27, 103), (28, 114), (20, 116)], SKIN2)
    cv.poly([(20, 106), (25, 104), (25, 110), (20, 112)], SKIN3)
    # Thumb wrapping over top index finger (X 23..31, Y 101..105)
    cv.poly([(23, 102), (30, 101), (32, 104), (25, 105)], SKIN2)
    cv.line([(24, 102), (29, 102)], SKIN3, 1)
    cv.line([(26, 105), (32, 105)], SKIN0, 1)
    # 4 rounded curled fingers on front-right of grip (X 25..33)
    for fy, lit in ((106, SKIN3), (109, SKIN2), (112, SKIN2), (115, SKIN1)):
        cv.rect(25, fy, 31, fy + 1, lit)
        if lit == SKIN3:
            cv.pixels([(30, fy), (31, fy), (31, fy + 1)], SKIN2)
        cv.pixels([(32, fy), (32, fy + 1)], SKIN0)
        if fy < 115:
            cv.line([(27, fy + 2), (32, fy + 2)], SKIN0, 1)
    cv.line([(22, 117), (30, 118)], SKIN0, 1)

    # =========================================================================
    # 9. SCULPTED 3/4 HEAD, SHAGGY NAPE HAIR, PROPORTIONED NOSE & TUFTED BEARD
    # =========================================================================
    # Shaggy grey-brown hair locks under hat behind ear (feathered tufts, NOT a round ball!)
    cv.poly([
        (27, 27), (39, 26), (40, 48), (34, 51),
        (29, 50), (31, 47), (26, 46), (29, 42),
        (24, 40), (28, 36), (25, 33)
    ], HAIR0)
    cv.poly([(27, 29), (36, 28), (36, 45), (28, 45), (30, 41), (26, 39)], HAIR1)
    cv.poly([(27, 31), (33, 30), (33, 39), (26, 39)], HAIR2)
    cv.pixels([(28, 33), (29, 34), (28, 35), (29, 42)], HAIR3)

    # 3/4 Face base (refined silhouette: brow X=66, eye indent X=64, rounded nose X=66!)
    cv.poly([
        (39, 25), (64, 25),
        (66, 29), (66, 33),
        (64, 35), (64, 37),
        (66, 40), (66, 42),
        (64, 44), (64, 53),
        (40, 52), (38, 40)
    ], SKIN1)
    cv.poly([(42, 27), (60, 27), (61, 34), (60, 43), (43, 46)], SKIN2)
    cv.poly([(45, 28), (55, 27), (57, 29), (53, 31), (46, 30)], SKIN3)
    cv.poly([(44, 38), (53, 38), (55, 40), (52, 42), (45, 42)], SKIN3)
    cv.poly([(38, 24), (65, 24), (65, 28), (54, 26), (44, 27), (38, 29)], SKIN0)
    cv.poly([(61, 28), (65, 30), (64, 37), (61, 37)], SKIN0)

    # Plump rounded anatomical ear (X 32..39, Y 34..45, matching Gustav & Torben's ear proportion!)
    cv.poly([(34, 34), (38, 34), (39, 36), (39, 43), (36, 45), (33, 43), (32, 39), (33, 35)], SKIN1)
    cv.pixels([(31, 36), (31, 37), (31, 38), (31, 39), (31, 40), (32, 42), (33, 44), (35, 45)], HAIR0)
    cv.pixels([(34, 34), (35, 34), (36, 34), (37, 35), (33, 35)], SKIN3)
    cv.pixels([(32, 36), (32, 37), (32, 38), (32, 39), (32, 40), (33, 41), (34, 43), (35, 44)], SKIN2)
    cv.pixels([(35, 37), (36, 37), (37, 38), (37, 39), (36, 40), (36, 41)], SKIN0)

    # Slender organic sideburn (only 2-3 px wide, tapering smoothly into beard: X 39..42, Y 29..45)
    cv.poly([(39, 29), (43, 30), (42, 44), (39, 45)], HAIR1)
    cv.pixels([(40, 31), (41, 32), (41, 33), (40, 34), (41, 36), (40, 37), (40, 39)], HAIR2)
    cv.pixels([(40, 32), (40, 35)], HAIR3)
    cv.pixels([(39, 30), (39, 31), (39, 42), (39, 43)], HAIR0)

    # Expressive, warm, shrewd merchant eyes (Y 33..37)
    # Near eye (X 47..54, Y 33..37) — open cheek X 55..59 stays clean skin!
    cv.rect(47, 33, 54, 36, SKIN0)
    cv.pixels([(47, 35), (48, 34), (49, 34), (50, 34), (51, 34), (52, 34), (53, 34), (54, 35)], INK)  # arched upper lash
    cv.pixels([(49, 35), (53, 35)], SKIN3)              # subtle warm sclera corners
    cv.rect(50, 35, 52, 36, UMBER)                      # rich 3x2 dark brown iris
    cv.px(52, 36, SKIN0)                                # warm brown lower iris tint
    cv.px(50, 35, GLINT)                                # crisp top-left catchlight!
    cv.line([(48, 37), (53, 37)], SKIN1, 1)             # lower eyelid crease
    # Crow's feet & weathered laugh crinkles at outer eye corner
    cv.pixels([(44, 35), (45, 35), (46, 36), (44, 37), (45, 37)], SKIN1)
    cv.line([(48, 38), (52, 38)], SKIN1, 1)

    # Far eye (X 61..64, Y 34..36, nestled into 3/4 eye indent)
    cv.pixels([(61, 34), (62, 34), (63, 34), (64, 35)], INK)
    cv.rect(62, 35, 63, 36, UMBER)
    cv.px(62, 35, SKIN3)
    cv.px(61, 35, SKIN0)

    # Bushy grey-brown eyebrows (no dark outline on top-left so they blend naturally into forehead!)
    cv.poly([(46, 32), (49, 30), (54, 29), (56, 31), (56, 33), (47, 33)], HAIR0)
    cv.poly([(45, 32), (48, 29), (54, 29), (56, 31), (48, 32)], HAIR1)
    cv.pixels([(47, 30), (48, 30), (49, 29), (50, 29), (51, 29), (52, 29), (53, 30), (54, 30)], HAIR2)
    cv.pixels([(50, 29), (51, 29), (52, 30)], HAIR3)
    # Far brow (X 60..66, Y 29..32)
    cv.poly([(60, 31), (62, 29), (66, 30), (66, 32), (61, 32)], HAIR0)
    cv.pixels([(61, 30), (62, 29), (63, 29), (64, 30), (65, 30)], HAIR1)
    cv.pixels([(62, 29), (63, 30)], HAIR2)

    # Smoothly blended, compact weathered nose (X 59..66, Y 34..43)
    cv.poly([(61, 34), (62, 35), (66, 40), (65, 43), (59, 43), (60, 39)], SKIN1)
    cv.poly([(60, 35), (62, 36), (65, 40), (64, 42), (59, 42)], SKIN2)
    cv.pixels([(60, 35), (61, 36), (62, 37), (62, 38), (63, 39), (63, 40), (64, 40), (63, 41), (64, 41), (62, 41)], SKIN3)
    cv.line([(59, 43), (64, 43)], SKIN0, 1)
    cv.px(60, 43, UMBER)
    cv.pixels([(57, 42), (56, 43), (55, 44)], SKIN1)

    # Short, full, sculpted grey-brown beard & drooping moustache (X 38..68, Y 44..59)
    # Outer tufted jaw-beard shape (natural notched beard tufts along chin Y=57..59!)
    cv.poly([
        (39, 43), (44, 46), (53, 45), (66, 45),
        (68, 49), (67, 54), (64, 58), (60, 59),
        (57, 58), (53, 59), (49, 58), (45, 57), (40, 52), (38, 47)
    ], HAIR0)
    # Sculpted mid & sunlit directional beard tufts (left jaw lit -> right chin shaded)
    cv.poly([(40, 44), (46, 47), (58, 51), (63, 55), (59, 58), (48, 57), (41, 52)], HAIR1)
    # Left cheek beard tuft
    cv.poly([(40, 44), (46, 47), (51, 52), (48, 56), (42, 52)], HAIR2)
    # Front chin beard tuft
    cv.poly([(51, 52), (58, 52), (57, 57), (51, 57)], HAIR2)
    # Crisp silver-taupe beard highlights on upper-left tufts
    cv.pixels([(41, 45), (42, 46), (43, 47), (42, 48), (45, 50), (46, 51), (52, 53), (53, 53)], HAIR3)
    # Dark tuft separation notches along lower beard
    cv.pixels([(48, 55), (49, 56), (49, 57), (56, 56), (57, 57), (61, 55), (62, 56)], HAIR0)
    # Crisp dark jaw shadow separating beard cleanly from neck & neckerchief
    cv.line([(40, 53), (46, 58), (53, 60), (61, 60), (66, 57), (68, 52)], INK, 1)

    # Sweeping grey-brown moustache curving down at both ends (like Gustav's moustache!)
    cv.poly([(48, 49), (51, 46), (56, 44), (62, 44), (67, 46), (68, 49), (66, 50), (61, 48), (56, 48), (50, 50)], HAIR0)
    cv.poly([(49, 48), (52, 46), (56, 44), (62, 44), (66, 46), (67, 48), (61, 47), (55, 48)], HAIR1)
    # Sunlit left wing of moustache + subtle center philtrum dip
    cv.poly([(50, 48), (53, 45), (59, 45), (58, 47), (51, 49)], HAIR2)
    cv.pixels([(53, 45), (54, 45), (55, 45), (56, 46), (52, 46)], HAIR3)
    cv.px(60, 45, HAIR1)  # center notch under nose
    # Relaxed lower lip shadow & subtle warm lip ridge under moustache
    cv.line([(56, 49), (62, 49)], SKIN1, 1)
    cv.pixels([(57, 49), (58, 49), (59, 49)], SKIN2)
    cv.line([(55, 50), (63, 50)], HAIR0, 1)
    cv.pixels([(57, 51), (58, 51), (59, 51)], HAIR0)  # soul-patch shadow crease under lip

    # =========================================================================
    # 10. FULLER 3/4 WIDE-BRIMMED FELT HAT, CARAVAN-BLUE BAND & CURVED FEATHER
    # =========================================================================
    # Deep 3D curved brim underside wrapping behind head/ear on viewer's left (X 8..39, Y 20..34)
    cv.cpoly([(9, 27), (15, 21), (29, 19), (39, 22), (37, 30), (24, 34), (12, 31)], UMBER)
    cv.line([(12, 29), (23, 31), (33, 29)], HAT1, 1)

    # Graceful grey feather tucked into hatband, sweeping up-left to Y=3..4 with notched barbs
    cv.cpoly([(19, 4), (23, 4), (30, 8), (35, 16), (31, 18), (25, 13), (20, 7)], SLATE1)
    cv.cpoly([(20, 4), (23, 5), (29, 9), (33, 15), (30, 16), (25, 12)], SLATE2)
    cv.line([(20, 4), (24, 7), (28, 11), (32, 15)], HAIR3, 1)
    cv.pixels([(19, 4), (20, 4), (21, 5), (22, 5)], GLINT)
    cv.pixels([(25, 6), (28, 9)], SLATE1)  # subtle feather barb texture

    # Fuller pinched sun-faded felt hat crown (X 24..67, Y 4..20)
    cv.cpoly([(24, 19), (27, 10), (36, 4), (46, 6), (56, 5), (64, 11), (67, 19), (46, 20)], HAT1)
    cv.cpoly([(25, 18), (28, 10), (36, 5), (46, 7), (56, 6), (61, 12), (58, 19), (30, 19)], HAT2)
    # Broad sunlit top-left crown dome & front pinch highlight
    cv.poly([(26, 17), (29, 9), (37, 5), (44, 7), (43, 16), (29, 18)], HAT3)
    cv.poly([(48, 8), (55, 6), (56, 12), (49, 13)], HAT3)
    # Sculpted side dent / pinch crease in crown
    cv.poly([(43, 7), (49, 7), (50, 15), (43, 15)], HAT1)

    # Caravan-blue hatband around base of crown (X 24..67, Y 16..20) + brass ring clasp
    cv.poly([(24, 18), (46, 16), (67, 18), (67, 20), (46, 18), (24, 20)], BLUE0)
    cv.poly([(25, 18), (49, 16), (58, 17), (58, 19), (47, 18), (25, 20)], BLUE1)
    cv.line([(27, 18), (43, 17)], BLUE2, 1)
    cv.rect(37, 16, 40, 19, BRASS1)
    cv.pixels([(37, 16), (38, 16)], BRASS2)
    cv.px(38, 18, HAT1)

    # Wide road-worn felt brim with dynamic 3/4 tilt (sweeps from X=9,Y=28 up over brow Y=19..23 to X=81,Y=26)
    cv.cpoly([(9, 27), (18, 21), (36, 18), (58, 18), (75, 21), (81, 25), (77, 27), (65, 24), (46, 22), (25, 25), (13, 29)], HAT1)
    cv.poly([(65, 23), (80, 25), (77, 27), (67, 25)], UMBER)
    cv.poly([(10, 26), (21, 20), (46, 18), (68, 20), (74, 22), (58, 22), (34, 22), (15, 27)], HAT2)
    cv.poly([(10, 26), (21, 20), (46, 18), (55, 19), (42, 21), (22, 24), (12, 27)], HAT3)
    cv.line([(12, 29), (25, 25), (46, 23), (65, 24), (77, 27)], INK, 1)

    # =========================================================================
    # 11. LUCKY CHARMS UNDER HAT BRIM (BRASS KEY, RED GLASS, BRASS COIN, FEATHER)
    # =========================================================================
    # Charm 1 (Left brim X 12..15, Y 30..40): Tiny Brass Key
    cv.px(13, 30, STRAP2)
    cv.rect(12, 31, 14, 33, BRASS1)
    cv.px(12, 31, BRASS2)
    cv.px(13, 32, INK)                           # key ring hole
    cv.line([(13, 34), (13, 39)], BRASS1, 1)     # key stem
    cv.px(13, 35, BRASS2)
    cv.pixels([(14, 37), (14, 39)], BRASS2)      # two tiny key teeth

    # Charm 2 (Left brim X 18..20, Y 31..37): Faceted Red Glass Bead
    cv.px(19, 31, STRAP2)
    cv.rect(18, 32, 20, 36, RED1)
    cv.pixels([(18, 32), (19, 32), (18, 33)], RED2)
    cv.px(18, 32, GLINT)

    # Charm 3 (Inner-left brim over dark underside X 23..25, Y 31..35): Brass Coin Charm
    cv.px(24, 30, INK)
    cv.rect(23, 32, 25, 34, INK)
    cv.rect(23, 32, 24, 33, BRASS1)
    cv.px(23, 32, BRASS2)

    # =========================================================================
    # 12. CRISP 1PX #1f1d30 SILHOUETTE OUTLINE & HARD ALPHA
    # =========================================================================
    cv.add_outer_outline(INK)

    # Strict hard alpha (0 or 255)
    cv.img[..., 3] = np.where(cv.img[..., 3] >= 128, 255, 0).astype(np.uint8)
    cv.img[cv.img[..., 3] == 0] = 0
    return Image.fromarray(cv.img, "RGBA")


def make_preview(jorun: Image.Image, path: Path) -> None:
    refs = ["gustav", "torben", "maren"]
    imgs = [Image.open(ROOT / f"assets/ui/portrait_{r}.png").convert("RGBA") for r in refs] + [jorun]
    scale = 3
    pad = 12
    arr = np.asarray(jorun).astype(np.float32) / 255.0
    lum = arr[..., 0] * 0.3 + arr[..., 1] * 0.59 + arr[..., 2] * 0.11
    unk = np.zeros((H, W, 4), dtype=np.uint8)
    m = arr[..., 3] > 0.5
    hi = m & (lum > 0.35)
    lo = m & ~hi
    unk[hi] = (int(0.065 * 255), int(0.047 * 255), int(0.095 * 255), 255)
    unk[lo] = (int(0.035 * 255), int(0.024 * 255), int(0.055 * 255), 255)
    imgs.append(Image.fromarray(unk, "RGBA"))

    cw = len(imgs) * (W * scale) + (len(imgs) + 1) * pad
    ch = H * scale + 2 * pad
    sheet = Image.new("RGBA", (cw, ch), (34, 28, 48, 255))
    for i, im in enumerate(imgs):
        up = im.resize((W * scale, H * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(up, (pad + i * (W * scale + pad), pad))
    sheet.convert("RGB").save(path)


def main() -> None:
    img = draw_jorun()
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PNG)

    a = np.asarray(img)
    m = a[..., 3] > 0
    ys, xs = np.where(m)
    cols = len({tuple(p[:3]) for p in a[m].tolist()})
    alphas = sorted(set(a[..., 3].flatten().tolist()))
    print(
        f"portrait_jorun.png: size={img.size}, colors={cols}, alphas={alphas}, "
        f"y=[{ys.min()}..{ys.max()}], x=[{xs.min()}..{xs.max()}], "
        f"shoulder_w@75={int(m[75].sum())}, max_w={int(m.sum(1).max())}, bottom_filled={bool(m[-1].any())}"
    )

    if len(sys.argv) > 1:
        prev = Path(sys.argv[1])
        prev.parent.mkdir(parents=True, exist_ok=True)
        make_preview(img, prev)
        print(f"preview -> {prev}")


if __name__ == "__main__":
    main()
