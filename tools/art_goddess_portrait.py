#!/usr/bin/env python3
"""2D cel-shaded anime pixel-art bust portrait generator for the Goddess (`206x153`).

Matches the exact visual language, 3/4 torso foreshortening, S-waved hair locks, and pixel
density of `assets/ui/ellie_dialogue_v4.png` and `assets/ui/portrait_esma.png`, and strictly
honors `docs/dialogue_art.md`:
  - Exact `206 x 153` RGBA sheet (`2 x 1` cells of `103 x 153`: col 0 = open eyes, col 1 = blink)
  - True 3/4 view facing screen RIGHT (both head AND foreshortened torso/sweetheart bodice!)
  - Sculpted anime 3/4 face contour (eye-socket indent -> pert nose -> delicate V-chin -> crisp jawline)
  - Soulful `10x7` & `5x7` luminous turquoise-starlight anime eyes with winged lashes & catchlights
  - Feathered parted silver-gold bangs under a nestled filigree golden star-diadem, wavy cascading
    locks, visible floating golden halo arc + 7 faceted crystal rays, royal cosmos-indigo & pearl
    sweetheart gown, gossamer starry veil, and graceful hand cradling a floating starlight crystal.
  - Binary alpha (`0` or `255`), zero `#000000`, ~33 crisp Shadowspore palette colors.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_art import ROOT, write_png  # noqa: E402

CW, CH = 103, 153
SS = 4


def hexc(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


# ---------------------------------------------------------------------------
# Shadowspore Anime Portrait Palette (strict flat tones, cool-violet shadows)
# ---------------------------------------------------------------------------
INK_DARK = hexc("1c1030")      # Primary crisp dark-violet lineart
INK_PLUM = hexc("2e1d4c")      # Hair & silk internal lock lineart
INK_BRONZE = hexc("3c283e")    # Floating halo & gold trim outline
INK_BROW = hexc("6c5c94")      # Soft lavender-gold eyebrow

SKIN_CAST = hexc("b67890")     # Deep cool-rose cast shadow (under chin & bangs)
SKIN_SHAD = hexc("dc9eaa")     # Soft rose cheek & side-plane shadow
SKIN_BASE = hexc("f8dcd2")     # Main luminous porcelain face/shoulder tone
SKIN_HIGH = hexc("fff3ea")     # Crisp nose-bridge, collarbone & shoulder highlight

HAIR_DEEP = hexc("786cb4")     # Deep cool periwinkle-lavender hair valley
HAIR_SHAD = hexc("aba0de")     # Cool silver-lavender mid-shadow
HAIR_BASE = hexc("e4def6")     # Luminous moon-silver hair body
HAIR_HIGH = hexc("fffaf2")     # Pure starlight crown highlight
HAIR_GOLD_S = hexc("bfa678")   # Warm champagne-gold braid/strand midtone
HAIR_GOLD_H = hexc("f2e4be")   # Warm starlight-gold strand highlight

NIGHT_DEEP = hexc("15102e")    # Deep cosmos indigo shadow
NIGHT_BASE = hexc("282052")    # Midnight velvet bodice/skirt base
NIGHT_MID = hexc("463a84")     # Royal indigo lit fold
NIGHT_HIGH = hexc("7262b8")    # Amethyst satin pleat highlight

PEARL_MID = hexc("c8c0e2")     # Moon-ivory silk midtone
PEARL_BASE = hexc("eeeaf8")    # Luminous pearl-alabaster silk
PEARL_HIGH = hexc("fffdf8")    # Crisp silk highlight

VEIL_DEEP = hexc("1b2650")     # Starry sapphire-violet veil shadow
VEIL_MID = hexc("334c88")      # Starry veil midtone
VEIL_HIGH = hexc("6292cc")     # Starry veil lit edge

GOLD_DEEP = hexc("6f5020")     # Antique bronze-gold shadow
GOLD_MID = hexc("b48a38")      # Rich gold base
GOLD_BRIGHT = hexc("e6c468")   # Bright filigree gold
GOLD_GLEAM = hexc("fff0b0")    # Specular star-gold gleam

TEAL_DEEP = hexc("1c6472")     # Deep ocean-teal upper iris / gem shadow
TEAL_MID = hexc("3cc0c6")      # Signature luminous turquoise
TEAL_BRIGHT = hexc("78f4e6")   # Radiant starlight aqua
STAR_WHITE = hexc("f4ffff")    # Pure diamond-white catchlight / crystal tip

ROSE_DARK = hexc("9e4e6c")     # Serene upper lip line
ROSE_SOFT = hexc("dc8ea6")     # Soft rose-petal lower lip


# ---------------------------------------------------------------------------
# Supersampled 2D Polygon & Bezier Ribbon Canvas
# ---------------------------------------------------------------------------
class Canvas2D:
    def __init__(self, w: int = CW, h: int = CH) -> None:
        self.w = w
        self.h = h
        self.sw = w * SS
        self.sh = h * SS
        self.pal: list[tuple[int, int, int]] = [(0, 0, 0)]
        self.col_to_idx: dict[tuple[int, int, int], int] = {}
        self.buf = np.zeros((self.sh, self.sw), dtype=np.int16)

    def _idx(self, rgb: tuple[int, int, int]) -> int:
        i = self.col_to_idx.get(rgb)
        if i is None:
            i = len(self.pal)
            self.pal.append(rgb)
            self.col_to_idx[rgb] = i
        return i

    def poly(self, pts: list[tuple[float, float]], rgb: tuple[int, int, int]) -> None:
        if len(pts) < 3:
            return
        c_i = self._idx(rgb)
        arr = np.array([(x * SS, y * SS) for x, y in pts], dtype=np.float64)
        x0 = max(0, int(math.floor(arr[:, 0].min())))
        x1 = min(self.sw, int(math.ceil(arr[:, 0].max())) + 1)
        y0 = max(0, int(math.floor(arr[:, 1].min())))
        y1 = min(self.sh, int(math.ceil(arr[:, 1].max())) + 1)
        if x1 <= x0 or y1 <= y0:
            return

        yy = np.arange(y0, y1, dtype=np.float64)[:, None] + 0.5
        xx = np.arange(x0, x1, dtype=np.float64)[None, :] + 0.5
        inside = np.zeros((y1 - y0, x1 - x0), dtype=bool)
        n = len(arr)
        for i in range(n):
            x_a, y_a = arr[i]
            x_b, y_b = arr[(i + 1) % n]
            cond = (y_a > yy) != (y_b > yy)
            x_int = x_a + (yy - y_a) * (x_b - x_a) / ((y_b - y_a) if abs(y_b - y_a) > 1e-9 else 1e-9)
            inside ^= cond & (xx < x_int)
        self.buf[y0:y1, x0:x1][inside] = c_i

    def bezier_pts(self, ctrl: list[tuple[float, float]], steps: int = 36) -> list[tuple[float, float]]:
        out: list[tuple[float, float]] = []
        n = len(ctrl) - 1
        for s in range(steps + 1):
            t = s / steps
            pts = [(float(x), float(y)) for x, y in ctrl]
            for r in range(1, n + 1):
                pts = [
                    ((1.0 - t) * pts[i][0] + t * pts[i + 1][0], (1.0 - t) * pts[i][1] + t * pts[i + 1][1])
                    for i in range(n - r + 1)
                ]
            out.append(pts[0])
        return out

    def ribbon(
        self,
        ctrl: list[tuple[float, float]],
        widths: list[float],
        rgb_base: tuple[int, int, int],
        rgb_shad: tuple[int, int, int] | None = None,
        rgb_high: tuple[int, int, int] | None = None,
        shad_side: float = 1.0,
        steps: int = 40,
    ) -> list[tuple[float, float]]:
        spine = self.bezier_pts(ctrl, steps=steps)
        left_edge: list[tuple[float, float]] = []
        right_edge: list[tuple[float, float]] = []
        mid_shift: list[tuple[float, float]] = []
        hi_l: list[tuple[float, float]] = []
        hi_r: list[tuple[float, float]] = []

        for i, (px, py) in enumerate(spine):
            u = i / max(1, len(spine) - 1)
            p_prev = spine[max(0, i - 1)]
            p_next = spine[min(len(spine) - 1, i + 1)]
            tx, ty = p_next[0] - p_prev[0], p_next[1] - p_prev[1]
            ln = math.hypot(tx, ty) or 1.0
            nx, ny = -ty / ln, tx / ln

            wf = u * (len(widths) - 1)
            w0 = int(wf)
            w1 = min(len(widths) - 1, w0 + 1)
            w = widths[w0] * (1.0 - (wf - w0)) + widths[w1] * (wf - w0)

            left_edge.append((px - nx * w, py - ny * w))
            right_edge.append((px + nx * w, py + ny * w))
            mid_shift.append((px + nx * w * 0.22 * shad_side, py + ny * w * 0.22 * shad_side))
            hi_l.append((px - nx * w * 0.46, py - ny * w * 0.46))
            hi_r.append((px + nx * w * 0.04, py + ny * w * 0.04))

        full_poly = left_edge + right_edge[::-1]
        self.poly(full_poly, rgb_base)

        if rgb_shad is not None:
            shad_poly = (mid_shift + right_edge[::-1]) if shad_side > 0 else (left_edge + mid_shift[::-1])
            self.poly(shad_poly, rgb_shad)

        if rgb_high is not None:
            s0, s1 = int(steps * 0.08), int(steps * 0.44)
            if s1 > s0 + 2:
                self.poly(hi_l[s0:s1] + hi_r[s0:s1][::-1], rgb_high)

        return full_poly

    def resolve(self, min_cov: int = 7) -> np.ndarray:
        sub = self.buf.reshape(self.h, SS, self.w, SS).transpose(0, 2, 1, 3).reshape(self.h, self.w, SS * SS)
        cnt = (sub > 0).sum(-1)
        solid = cnt >= min_cov

        k = len(self.pal)
        best = np.zeros((self.h, self.w), dtype=np.int16)
        best_c = np.zeros((self.h, self.w), dtype=np.int16)
        for idx in range(1, k):
            c = (sub == idx).sum(-1)
            upd = c > best_c
            best = np.where(upd, idx, best)
            best_c = np.where(upd, c, best_c)
        best = np.where(solid, best, 0)

        out = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        pal_arr = np.array(self.pal, dtype=np.uint8)
        m = best > 0
        out[m, :3] = pal_arr[best[m]]
        out[m, 3] = 255
        return out


def outline_layer(img: np.ndarray, ink_rgb: tuple[int, int, int], skip_bottom: bool = True) -> np.ndarray:
    out = img.copy()
    solid = img[..., 3] == 255
    h, w, _ = img.shape
    for y in range(h):
        if skip_bottom and y >= h - 1:
            continue
        for x in range(w):
            if solid[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and solid[ny, nx]:
                    out[y, x] = (*ink_rgb, 255)
                    break
    return out


def paste_over(dst: np.ndarray, src: np.ndarray) -> None:
    m = src[..., 3] == 255
    dst[m] = src[m]


# ---------------------------------------------------------------------------
# Layer Builders
# ---------------------------------------------------------------------------
def build_halo_layer() -> np.ndarray:
    """Raised airy golden starlight halo (`cy = 25.5, r = 23.2`) so a crisp cosmos air-gap
    appears above her crown and all 7 slender faceted crystal rays shine clearly!"""
    c = Canvas2D()
    cx, cy, r = 49.5, 25.5, 23.2

    arc_outer = []
    arc_inner = []
    for i in range(49):
        ang = math.radians(-10.0 + 200.0 * (i / 48.0))
        arc_outer.append((cx + (r + 0.90) * math.cos(ang), cy - (r + 0.90) * math.sin(ang)))
        arc_inner.append((cx + (r - 0.80) * math.cos(ang), cy - (r - 0.80) * math.sin(ang)))
    c.poly(arc_outer + arc_inner[::-1], GOLD_BRIGHT)
    c.poly(arc_outer[16:36] + arc_inner[16:36][::-1], GOLD_GLEAM)

    for idx, deg in enumerate((-2.0, 28.0, 59.0, 90.0, 121.0, 152.0, 182.0)):
        ang = math.radians(deg)
        ux, uy = math.cos(ang), -math.sin(ang)
        nx, ny = -uy, ux
        is_top = idx == 3
        is_mid = idx in (1, 5)
        r0 = r + 1.8
        slen = 5.4 if is_top else (4.4 if is_mid else 3.6)
        hw = 1.45 if is_top else (1.20 if is_mid else 1.00)

        p_base = (cx + ux * r0, cy + uy * r0)
        p_mid_l = (cx + ux * (r0 + slen * 0.36) - nx * hw, cy + uy * (r0 + slen * 0.36) - ny * hw)
        p_mid_r = (cx + ux * (r0 + slen * 0.36) + nx * hw, cy + uy * (r0 + slen * 0.36) + ny * hw)
        p_tip = (cx + ux * (r0 + slen), cy + uy * (r0 + slen))
        p_ctr = (cx + ux * (r0 + slen * 0.38), cy + uy * (r0 + slen * 0.38))

        c.poly([p_base, p_mid_l, p_tip, p_ctr], STAR_WHITE if idx % 2 == 1 else GOLD_GLEAM)
        c.poly([p_base, p_ctr, p_tip, p_mid_r], TEAL_BRIGHT if idx % 2 == 1 else GOLD_MID)

    return outline_layer(c.resolve(min_cov=5), INK_BRONZE, skip_bottom=True)


def build_veil_and_back_hair() -> np.ndarray:
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    # 1. Gossamer Starry Astral Veil Streamers behind shoulders (`Y = 66..152`)
    cv = Canvas2D()
    cv.ribbon(
        [(28, 69), (14, 92), (6, 122), (9, 154)],
        [3.2, 6.0, 7.2, 5.2],
        VEIL_MID,
        rgb_shad=VEIL_DEEP,
        rgb_high=VEIL_HIGH,
        shad_side=1.0,
    )
    cv.ribbon(
        [(70, 70), (80, 96), (86, 124), (90, 154)],
        [2.8, 4.8, 5.8, 4.4],
        VEIL_DEEP,
        rgb_shad=NIGHT_DEEP,
        rgb_high=VEIL_MID,
        shad_side=-1.0,
    )
    cv.ribbon([(24, 74), (11, 98), (6, 128), (8, 152)], [0.6, 0.9, 1.0, 0.7], TEAL_BRIGHT)
    cv.ribbon([(73, 76), (82, 100), (87, 128), (90, 152)], [0.6, 0.8, 0.9, 0.7], TEAL_MID)
    paste_over(out, outline_layer(cv.resolve(min_cov=6), INK_DARK, skip_bottom=True))

    # 2. Organic S-Waved Cascading Silver-Gold Back Hair Plumes (matching `ellie_dialogue_v4.png`'s wavy left locks!)
    back_locks = [
        # Far-right lock behind neck/shoulder
        ([(65, 22), (79, 46), (76, 80), (84, 116), (80, 148)], [4.5, 5.8, 5.5, 4.2, 0.8], HAIR_SHAD, HAIR_DEEP, None, 1.0),
        # Deep shadow mass behind neck & shoulders
        ([(48, 18), (45, 54), (43, 96), (41, 140)], [15.5, 17.5, 16.5, 13.0], HAIR_DEEP, None, None, 1.0),
        # Outer S-waved feathered wisps on viewer's left (like Ellie's wavy outer hair tips!)
        ([(33, 22), (16, 46), (20, 74), (7, 104), (11, 134)], [4.8, 6.8, 6.2, 4.8, 0.6], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
        ([(36, 20), (22, 50), (13, 84), (18, 118), (10, 150)], [5.8, 7.6, 7.8, 6.0, 1.2], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
        ([(40, 25), (29, 56), (21, 92), (25, 126), (19, 153)], [5.5, 7.2, 7.2, 5.5, 1.6], HAIR_BASE, HAIR_SHAD, HAIR_GOLD_H, 1.0),
        ([(44, 30), (35, 62), (29, 98), (27, 134), (29, 154)], [4.8, 6.4, 6.5, 5.0, 2.0], HAIR_SHAD, HAIR_DEEP, HAIR_BASE, 1.0),
    ]
    for ctrl, wids, c_base, c_shad, c_hi, s_side in back_locks:
        cl = Canvas2D()
        cl.ribbon(ctrl, wids, c_base, rgb_shad=c_shad, rgb_high=c_hi, shad_side=s_side)
        paste_over(out, outline_layer(cl.resolve(min_cov=6), INK_PLUM, skip_bottom=True))

    return out


def build_torso_and_gown() -> np.ndarray:
    """True 3/4 right-angled bust & gown: center axis at `x = 58` (foreshortened right side, wider near left side!)."""
    c = Canvas2D()

    # 1. Slender Neck & Foreshortened 3/4 Bare Porcelain Shoulders (`Y = 51..84`)
    c.poly([(45, 50), (58, 51), (60, 68), (44, 68)], SKIN_BASE)
    c.poly([(45, 50), (58, 51), (57, 58), (50, 61), (44, 66)], SKIN_CAST)
    c.poly([(50, 60), (57, 58), (59, 65), (51, 66)], SKIN_SHAD)

    # 3/4 Shoulders: wider near left shoulder (`x = 27..45`), foreshortened far right shoulder (`x = 59..71`)!
    c.poly([(27, 70), (44, 65), (60, 65), (71, 69), (73, 85), (25, 85)], SKIN_BASE)
    c.poly([(27, 70), (37, 68), (38, 84), (25, 85)], SKIN_SHAD)
    c.ribbon([(40, 71), (49, 73), (56, 73)], [0.8, 0.9, 0.5], SKIN_HIGH)
    c.ribbon([(61, 73), (66, 71), (69, 70)], [0.5, 0.8, 0.5], SKIN_HIGH)

    # Bare far right arm (`x=68..79`); near left arm is drawn cleanly as one continuous piece in `build_front_arm_and_spark`
    c.ribbon([(70, 72), (74, 94), (78, 118), (81, 146)], [3.8, 3.5, 3.3, 3.0], SKIN_SHAD, rgb_shad=SKIN_CAST, shad_side=1.0)

    # Filigree Golden Starlight Choker (`y = 62..64`) + Turquoise Gem at 3/4 center `x = 55`!
    c.ribbon([(44, 62), (54, 64), (60, 62)], [1.1, 1.3, 1.0], GOLD_BRIGHT, rgb_shad=GOLD_MID)
    c.poly([(55, 64), (58, 66), (55, 70), (52, 66)], TEAL_BRIGHT)

    # 2. Fitted 3/4 Royal Cosmos-Indigo & Pearl-Ivory Sweetheart Gown (`center axis x = 58`)
    # Full pleated royal-indigo skirt flaring cleanly through `Y = 153`
    c.poly([(31, 113), (71, 113), (87, 155), (16, 155)], NIGHT_BASE)
    c.poly([(16, 155), (31, 113), (42, 114), (30, 155)], NIGHT_MID)
    c.poly([(22, 155), (34, 114), (38, 114), (27, 155)], NIGHT_HIGH)
    c.poly([(42, 114), (51, 115), (47, 155), (34, 155)], NIGHT_DEEP)
    c.poly([(65, 114), (71, 113), (85, 155), (73, 155)], NIGHT_DEEP)
    c.poly([(67, 114), (70, 114), (81, 155), (75, 155)], NIGHT_MID)
    c.ribbon([(36, 115), (30, 135), (25, 154)], [0.8, 0.9, 1.0], GOLD_MID)
    c.ribbon([(69, 115), (74, 135), (79, 154)], [0.8, 0.9, 1.0], GOLD_MID)

    # Embroidered Pearl-Ivory Center Stole (`3/4 center x = 51..66, y = 115..155`)
    c.poly([(50, 115), (65, 115), (71, 155), (48, 155)], PEARL_BASE)
    c.poly([(60, 115), (65, 115), (71, 155), (63, 155)], PEARL_MID)
    c.ribbon([(50, 115), (49, 135), (48, 155)], [1.0, 1.1, 1.1], GOLD_BRIGHT)
    c.ribbon([(65, 115), (68, 135), (71, 155)], [1.0, 1.1, 1.1], GOLD_MID)
    c.ribbon([(58, 118), (59, 136), (60, 154)], [0.9, 1.0, 1.0], TEAL_MID)
    c.poly([(59, 128), (63, 134), (60, 140), (55, 134)], GOLD_BRIGHT)
    c.poly([(59, 130), (61, 134), (60, 138), (57, 134)], TEAL_BRIGHT)

    # 3/4 Cinched Midnight-Indigo Corset & Sweetheart Bustier (`sweetheart dip at x = 58, y = 82`)
    c.poly([(33, 79), (47, 77), (58, 82), (66, 77), (72, 80), (69, 98), (69, 114), (34, 114), (32, 96)], NIGHT_BASE)
    c.poly([(33, 79), (48, 77), (49, 114), (34, 114), (32, 96)], NIGHT_MID)
    c.poly([(35, 80), (44, 78), (43, 95), (34, 95)], NIGHT_HIGH)
    c.poly([(64, 78), (72, 80), (69, 98), (69, 114), (63, 114)], NIGHT_DEEP)

    # 3/4 Pearl-Ivory Sweetheart Cameo Inset (`x = 48..65, y = 80..97`)
    c.poly([(48, 79), (58, 82), (66, 79), (63, 97), (50, 97)], PEARL_BASE)
    c.poly([(59, 81), (66, 79), (63, 97), (58, 97)], PEARL_MID)
    c.poly([(49, 80), (55, 82), (54, 94), (50, 94)], PEARL_HIGH)

    # Champagne-Gold Sweetheart Border, Corset Lacing & V-Girdle (`center V at x = 58`)!
    c.ribbon([(33, 79), (47, 77), (58, 82), (66, 77), (72, 80)], [1.2, 1.3, 1.4, 1.2, 1.0], GOLD_BRIGHT, rgb_shad=GOLD_MID)
    c.ribbon([(48, 79), (50, 97), (50, 114)], [0.9, 0.9, 0.8], GOLD_BRIGHT)
    c.ribbon([(66, 79), (63, 97), (63, 114)], [0.9, 0.9, 0.8], GOLD_MID)
    for ly in (99, 104, 109):
        c.ribbon([(51, ly), (62, ly)], [0.8, 0.8], GOLD_BRIGHT)

    c.ribbon([(33, 112), (47, 115), (58, 119), (66, 115), (70, 112)], [1.6, 1.8, 2.2, 1.7, 1.4], GOLD_BRIGHT, rgb_shad=GOLD_MID, rgb_high=GOLD_GLEAM)
    c.poly([(58, 115), (61, 118), (58, 122), (55, 118)], TEAL_BRIGHT)

    # Heart-Star Turquoise Brooch (`(58, 83)`)
    c.poly([(58, 79), (62, 83), (58, 88), (54, 83)], GOLD_GLEAM)
    c.poly([(58, 80), (61, 83), (58, 87), (55, 83)], TEAL_BRIGHT)
    c.poly([(57, 81), (59, 82), (58, 84), (56, 83)], STAR_WHITE)

    # Ornate Golden Winged Shoulder Clasps (`(28, 70)` & `(70, 70)`) + Upper-Arm Rings
    c.ribbon([(23, 72), (28, 68), (35, 69)], [1.6, 2.2, 1.4], GOLD_BRIGHT, rgb_shad=GOLD_MID, rgb_high=GOLD_GLEAM)
    c.poly([(28, 67), (31, 69), (28, 72), (25, 69)], TEAL_BRIGHT)

    c.ribbon([(65, 69), (70, 69), (74, 72)], [1.2, 1.8, 1.3], GOLD_MID, rgb_shad=GOLD_DEEP, rgb_high=GOLD_BRIGHT)
    c.poly([(70, 68), (72, 70), (70, 72), (68, 70)], TEAL_MID)

    c.ribbon([(70, 89), (74, 90), (77, 88)], [1.0, 1.1, 0.9], GOLD_MID)

    return outline_layer(c.resolve(min_cov=6), INK_DARK, skip_bottom=True)


def build_front_arm_and_spark() -> np.ndarray:
    """Smooth, continuous shoulder-to-elbow-to-cupped-hand stroke (zero seam across upper arm!)."""
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    ca = Canvas2D()
    # Continuous near arm from shoulder `(28, 72)` -> elbow `(21, 105)` -> wrist `(47, 105)`!
    ca.ribbon(
        [(28, 72), (22, 91), (21, 105), (34, 108), (47, 105)],
        [4.3, 3.8, 3.6, 3.1, 2.5],
        SKIN_BASE,
        rgb_shad=SKIN_SHAD,
        rgb_high=SKIN_HIGH,
        shad_side=1.0,
    )
    ca.poly([(46, 103), (55, 101), (61, 102), (59, 106), (52, 107), (46, 107)], SKIN_BASE)
    ca.poly([(46, 106), (53, 106), (59, 105), (57, 107), (47, 108)], SKIN_SHAD)
    ca.ribbon([(53, 102), (59, 100), (63, 99)], [1.2, 0.9, 0.5], SKIN_HIGH)
    ca.ribbon([(22, 87), (26, 89), (29, 88)], [1.1, 1.2, 1.0], GOLD_BRIGHT)
    ca.ribbon([(40, 104), (43, 107), (44, 109)], [1.4, 1.5, 1.3], GOLD_BRIGHT, rgb_shad=GOLD_MID)
    arm_raw = ca.resolve(min_cov=6)
    arm_out = outline_layer(arm_raw, INK_DARK, skip_bottom=True)
    # Suppress top-cap outline where upper arm merges seamlessly into bare shoulder (`y <= 75`)
    arm_out[:76, 23:32] = arm_raw[:76, 23:32]
    paste_over(out, arm_out)

    cs = Canvas2D()
    sx, sy = 60.0, 93.0
    cs.poly([(sx, sy - 6.2), (sx + 2.0, sy - 1.4), (sx + 5.2, sy), (sx + 2.0, sy + 1.4), (sx, sy + 6.2), (sx - 2.0, sy + 1.4), (sx - 5.2, sy), (sx - 2.0, sy - 1.4)], TEAL_BRIGHT)
    cs.poly([(sx, sy - 4.8), (sx + 1.3, sy - 0.9), (sx + 3.6, sy), (sx + 1.3, sy + 0.9), (sx, sy + 4.8), (sx - 1.3, sy + 0.9), (sx - 3.6, sy), (sx - 1.3, sy - 0.9)], STAR_WHITE)
    cs.poly([(sx, sy - 1.8), (sx + 1.6, sy), (sx, sy + 1.8), (sx - 1.6, sy)], GOLD_GLEAM)
    paste_over(out, outline_layer(cs.resolve(min_cov=4), INK_BRONZE, skip_bottom=True))

    return out


def build_face_head_base() -> np.ndarray:
    c = Canvas2D()

    c.poly([(36, 38), (41, 37), (42, 46), (38, 46), (36, 42)], SKIN_SHAD)
    c.poly([(37, 39), (40, 39), (40, 43), (38, 43)], SKIN_CAST)

    face_pts = c.bezier_pts([(40.5, 30.0), (47.0, 21.0), (63.0, 21.5), (68.5, 29.0)], 14)
    face_pts += [
        (69.0, 34.0),
        (67.6, 38.5),
        (68.5, 41.2),
        (70.2, 44.2),
        (67.6, 46.5),
        (67.8, 49.0),
        (66.5, 52.8),
        (62.8, 55.8),
        (58.5, 57.2),
        (52.5, 55.8),
        (46.0, 52.5),
        (41.2, 47.5),
        (40.2, 39.0),
    ]
    c.poly(face_pts, SKIN_BASE)

    c.poly([(40.2, 30.0), (46.0, 24.0), (67.5, 27.0), (68.5, 31.5), (54.0, 30.5), (44.5, 35.0), (44.0, 48.0), (48.0, 53.5), (41.2, 47.5)], SKIN_SHAD)
    c.poly([(40.2, 30.0), (46.0, 24.0), (66.0, 26.5), (67.0, 29.0), (45.0, 31.0), (42.5, 42.0)], SKIN_CAST)
    c.poly([(64.5, 39.5), (66.8, 40.5), (69.2, 44.0), (66.8, 44.8)], SKIN_HIGH)
    c.poly([(48.0, 43.5), (54.0, 43.5), (53.0, 46.2), (47.5, 45.8)], SKIN_HIGH)

    raw = c.resolve(min_cov=6)
    out = outline_layer(raw, INK_DARK, skip_bottom=True)

    out[46, 39] = (*GOLD_GLEAM, 255)
    out[47, 39] = (*TEAL_BRIGHT, 255)
    out[48, 39] = (*STAR_WHITE, 255)
    out[47, 38] = (*INK_DARK, 255)
    out[47, 40] = (*INK_DARK, 255)
    out[49, 39] = (*INK_DARK, 255)
    return out


def stamp_anime_features(img: np.ndarray, blink: bool) -> None:
    def px(x: int, y: int, rgb: tuple[int, int, int]) -> None:
        if 0 <= x < CW and 0 <= y < CH:
            img[y, x] = (*rgb, 255)

    for x, y in ((46, 34), (47, 33), (48, 32), (49, 32), (50, 32), (51, 32), (52, 32), (53, 33), (54, 33), (55, 34)):
        px(x, y, INK_BROW)
    for x, y in ((62, 33), (63, 32), (64, 32), (65, 32), (66, 33), (67, 34)):
        px(x, y, INK_BROW)

    if not blink:
        for x in range(48, 54):
            px(x, 34, SKIN_CAST)
        for y in range(37, 43):
            x_start = 47 if y < 41 else 48
            x_end = 55 if y < 42 else 54
            for x in range(x_start, x_end + 1):
                px(x, y, PEARL_HIGH if y <= 39 else PEARL_BASE)
        for y in range(37, 43):
            for x in range(49, 55):
                if y == 42 and x in (49, 54):
                    continue
                col = TEAL_DEEP if y <= 38 else (TEAL_MID if y <= 40 else (TEAL_BRIGHT if y == 41 else STAR_WHITE))
                px(x, y, col)
        for x in (51, 52):
            for y in (39, 40):
                px(x, y, NIGHT_DEEP)
        px(50, 41, TEAL_BRIGHT)
        px(53, 41, TEAL_BRIGHT)
        px(51, 42, STAR_WHITE)
        px(52, 42, STAR_WHITE)
        for x in (49, 50):
            for y in (37, 38):
                px(x, y, STAR_WHITE)
        px(53, 41, STAR_WHITE)
        for x, y in (
            (45, 36), (46, 36), (46, 37), (47, 36), (47, 37),
            (48, 36), (49, 36), (50, 36), (51, 36), (52, 36), (53, 36), (54, 36),
            (54, 37), (55, 37), (55, 38),
        ):
            px(x, y, INK_DARK)
        for x in (49, 50, 51, 52, 53):
            px(x, 43, SKIN_CAST if x in (49, 53) else INK_PLUM)

        # Far Eye (`x = 62..67`)
        for x in range(63, 67):
            px(x, 34, SKIN_CAST)
        for y in range(37, 43):
            for x in range(62, 67):
                if y == 42 and x in (62, 66):
                    continue
                px(x, y, PEARL_HIGH)
        for y in range(37, 43):
            for x in range(63, 67):
                if y == 42 and x == 66:
                    continue
                col = TEAL_DEEP if y <= 38 else (TEAL_MID if y <= 40 else (TEAL_BRIGHT if y == 41 else STAR_WHITE))
                px(x, y, col)
        px(64, 39, NIGHT_DEEP)
        px(65, 39, NIGHT_DEEP)
        px(64, 40, NIGHT_DEEP)
        px(63, 37, STAR_WHITE)
        px(63, 38, STAR_WHITE)
        px(64, 37, STAR_WHITE)
        for x, y in ((62, 37), (62, 36), (63, 36), (64, 36), (65, 36), (66, 36), (67, 37), (67, 38)):
            px(x, y, INK_DARK)
        for x in (63, 64, 65):
            px(x, 43, INK_PLUM if x == 64 else SKIN_CAST)
    else:
        for x in range(47, 55):
            px(x, 38, SKIN_SHAD)
            px(x, 39, SKIN_SHAD)
        for x, y in (
            (45, 39), (46, 40), (47, 40), (48, 41), (49, 41), (50, 41),
            (51, 41), (52, 41), (53, 41), (54, 40), (55, 39),
            (46, 41), (50, 42), (51, 42),
        ):
            px(x, y, INK_DARK)
        for x in range(62, 67):
            px(x, 38, SKIN_SHAD)
            px(x, 39, SKIN_SHAD)
        for x, y in ((62, 40), (63, 41), (64, 41), (65, 41), (66, 40), (67, 39), (64, 42)):
            px(x, y, INK_DARK)

    px(66, 44, SKIN_CAST)
    px(66, 45, SKIN_CAST)
    px(67, 45, SKIN_SHAD)

    px(57, 50, SKIN_CAST)
    px(58, 50, ROSE_DARK)
    px(59, 50, ROSE_DARK)
    px(60, 50, ROSE_DARK)
    px(61, 50, ROSE_DARK)
    px(62, 50, SKIN_CAST)
    px(59, 51, ROSE_SOFT)
    px(60, 51, ROSE_SOFT)
    px(61, 51, ROSE_SOFT)

    for x, y in ((46, 44), (47, 44), (48, 44), (47, 45), (65, 44), (66, 43)):
        px(x, y, SKIN_SHAD)


def build_front_hair_and_diadem() -> np.ndarray:
    """Graceful S-waved twin front shoulder locks (keeping far eye & 3/4 cheek 100% open!),
    feathered anime bangs dipping softly across forehead, twisted temple braid, and crown diadem!"""
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    # 1. S-Waved Front Shoulder Locks (`x = 71..76` on right so far eye/cheek/nose stay 100% unobstructed!)
    for ctrl, wids, sh_side in (
        ([(39, 28), (33, 52), (40, 78), (34, 102), (39, 124)], [3.2, 3.6, 3.0, 1.9, 0.4], 1.0),
        ([(69, 27), (75, 50), (71, 76), (75, 100), (72, 120)], [2.4, 2.8, 2.4, 1.6, 0.4], -1.0),
    ):
        cl = Canvas2D()
        cl.ribbon(ctrl, wids, HAIR_BASE, rgb_shad=HAIR_SHAD, rgb_high=HAIR_GOLD_H, shad_side=sh_side)
        paste_over(out, outline_layer(cl.resolve(min_cov=6), INK_PLUM, skip_bottom=True))

    cg = Canvas2D()
    for gx, gy in ((36.5, 92.0), (73.5, 90.0)):
        cg.ribbon([(gx - 2.0, gy - 1.5), (gx + 2.0, gy - 1.5)], [1.0, 1.0], GOLD_BRIGHT)
        cg.poly([(gx, gy - 0.4), (gx + 1.8, gy + 1.8), (gx, gy + 4.4), (gx - 1.8, gy + 1.8)], TEAL_BRIGHT)
        cg.poly([(gx, gy + 0.2), (gx + 0.8, gy + 1.6), (gx, gy + 2.8), (gx - 0.8, gy + 1.6)], STAR_WHITE)
    paste_over(out, outline_layer(cg.resolve(min_cov=4), INK_BRONZE, skip_bottom=True))

    # 2. Voluminous Crown & Feathered Anime Forehead Bangs (`Y = 12..38`, soft wisps between brows like Ellie!)
    cb = Canvas2D()
    # Left plush crown & sweeping temple bang
    cb.ribbon(
        [(57, 15), (44, 13), (33, 21), (36, 34), (41, 45)],
        [4.4, 6.8, 5.8, 3.2, 0.5],
        HAIR_BASE,
        rgb_shad=HAIR_SHAD,
        rgb_high=HAIR_HIGH,
        shad_side=1.0,
    )
    # Feathered anime forehead bangs (soft pointed wisps framing brows without touching irises!)
    cb.ribbon([(56, 17), (49, 22), (45, 29), (44, 35)], [2.8, 3.0, 2.0, 0.4], HAIR_HIGH, rgb_shad=HAIR_BASE, shad_side=1.0)
    cb.ribbon([(57, 18), (55, 24), (54, 30), (55, 35)], [2.1, 2.2, 1.4, 0.3], HAIR_BASE, rgb_shad=HAIR_SHAD, shad_side=1.0)
    # Delicate center-bridge wisp dipping gracefully to `y = 36` right between her two eyes!
    cb.ribbon([(58, 19), (59, 26), (59, 32), (58, 36)], [1.6, 1.7, 1.1, 0.3], HAIR_GOLD_H, rgb_shad=HAIR_BASE, shad_side=1.0)

    # Right plush crown & foreshortened 3/4 temple bang (`clears far eye x=62..67 cleanly!`)
    cb.ribbon(
        [(58, 15), (66, 15), (73, 23), (74, 34), (72, 42)],
        [3.8, 5.4, 4.2, 2.2, 0.4],
        HAIR_BASE,
        rgb_shad=HAIR_SHAD,
        rgb_high=HAIR_HIGH,
        shad_side=-1.0,
    )
    cb.ribbon([(59, 18), (64, 22), (67, 28), (68, 33)], [2.0, 2.1, 1.3, 0.3], HAIR_HIGH, rgb_shad=HAIR_SHAD, shad_side=-1.0)
    paste_over(out, outline_layer(cb.resolve(min_cov=5), INK_PLUM, skip_bottom=True))

    # 3. Sculpted Golden-Silver Twisted Temple Braid
    cbr = Canvas2D()
    for bx, by in ((49, 20), (44, 22), (39, 25), (35, 28), (31, 31)):
        cbr.poly([(bx - 2.1, by), (bx, by - 1.7), (bx + 2.1, by), (bx, by + 1.7)], HAIR_GOLD_H)
        cbr.poly([(bx, by - 1.7), (bx + 2.1, by), (bx, by + 1.7)], HAIR_GOLD_S)
    paste_over(out, outline_layer(cbr.resolve(min_cov=4), INK_PLUM, skip_bottom=True))

    # 4. Filigree Golden Starlight Crown Diadem nestled gracefully into upper bangs (`y = 19..27`)!
    cd = Canvas2D()
    cd.ribbon([(45, 22), (52, 24), (58, 25), (64, 24), (69, 22)], [0.9, 1.1, 1.3, 1.0, 0.8], GOLD_BRIGHT, rgb_shad=GOLD_MID, rgb_high=GOLD_GLEAM)
    cd.poly([(58, 19), (60.2, 23.5), (58, 27.8), (55.8, 23.5)], GOLD_GLEAM)
    cd.poly([(58, 21.2), (59.8, 24.2), (58, 27.2), (56.2, 24.2)], TEAL_BRIGHT)
    cd.poly([(58, 22.2), (59.0, 23.8), (58, 25.2), (57.0, 23.8)], STAR_WHITE)
    paste_over(out, outline_layer(cd.resolve(min_cov=4), INK_BRONZE, skip_bottom=True))

    return out


def render_portrait_sheet() -> np.ndarray:
    halo = build_halo_layer()
    back_hv = build_veil_and_back_hair()
    torso = build_torso_and_gown()
    face_base = build_face_head_base()
    front_hair = build_front_hair_and_diadem()
    front_arm = build_front_arm_and_spark()

    cells: list[np.ndarray] = []
    for is_blink in (False, True):
        cell = np.zeros((CH, CW, 4), dtype=np.uint8)
        paste_over(cell, halo)
        paste_over(cell, back_hv)
        paste_over(cell, torso)

        face_cell = face_base.copy()
        stamp_anime_features(face_cell, blink=is_blink)
        paste_over(cell, face_cell)

        paste_over(cell, front_hair)
        paste_over(cell, front_arm)

        cell[cell[..., 3] < 128] = (0, 0, 0, 0)
        cell[cell[..., 3] >= 128, 3] = 255
        cells.append(cell)

    sheet = np.zeros((CH, CW * 2, 4), dtype=np.uint8)
    sheet[:, :CW] = cells[0]
    sheet[:, CW:] = cells[1]
    return sheet


def main() -> None:
    sheet = render_portrait_sheet()
    out_path = ROOT / "ui" / "portrait_goddess.png"
    h, w, _ = sheet.shape
    rows = [[tuple(int(v) for v in sheet[y, x]) for x in range(w)] for y in range(h)]
    write_png(out_path, w, h, rows)
    n_cols = len({tuple(int(v) for v in px) for px in sheet[sheet[..., 3] == 255][:, :3]})
    print(f"Wrote {out_path} ({w}x{h}, {n_cols} exact palette colors)")


if __name__ == "__main__":
    main()
