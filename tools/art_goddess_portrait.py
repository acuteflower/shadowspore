#!/usr/bin/env python3
"""2D pixel-art dialogue portrait generator for the redesigned floating interstellar Goddess Caelia (`206x153`).

Strictly honors `docs/dialogue_art.md` and matches Caelia v2 (`tools/art_goddess.py`):
  - Exact `206 x 153` RGBA sheet (`2 x 1` cells of `103 x 153`: col 0 = open eyes, col 1 = blink)
  - True eye-level 3/4 view facing screen RIGHT toward the dialogue box
  - Two tilted delicate antique-gold astrolabe light rings behind her head & shoulders with glowing
    turquoise & diamond-white starlight nodes (replaces the old spiky crown halo!)
  - Weightless Living Nebula Hair billowing outward in zero-G waves: moon-silver at crown transitioning
    through twilight lavender-indigo into starry deep cosmos-indigo tips speckled with 1px stars
  - Flowing asymmetrical moon-ivory silk draped gown (left shoulder draped with gold clasp, bare moonlit
    right collarbone/shoulder with a subtle antique-gold Kintsugi light seam; NO corset, NO heavy diadem!)
  - Wide sweeping midnight-sapphire Hagoromo celestial stole behind her shoulders traced with gold rim &
    turquoise constellation dots
  - Serene mature moonlit face, minimalist golden forehead star mark, expressive luminous turquoise eyes,
    and graceful raised hand holding delicate drifting turquoise-gold Veil light threads.
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
# Shadowspore Cosmic Portrait Palette (strict flat tones, cool-violet shadows)
# ---------------------------------------------------------------------------
INK_DARK = hexc("1a102e")      # Crisp dark-violet outer lineart
INK_PLUM = hexc("2c1e4a")      # Hair & silk internal strand lineart
INK_BRONZE = hexc("3e2a3c")    # Floating astrolabe & gold trim lineart
INK_BROW = hexc("6c5c94")      # Soft lavender eyebrow

SKIN_CAST = hexc("b47890")     # Cool-rose cast shadow under chin & bangs
SKIN_SHAD = hexc("dc9eaa")     # Soft rose cheek & side-plane shadow
SKIN_BASE = hexc("f8dcd2")     # Luminous moonlit porcelain skin
SKIN_HIGH = hexc("fff3ea")     # Crisp nose, collarbone & shoulder highlight

HAIR_DEEP = hexc("7468b0")     # Moon-silver shadow valley
HAIR_SHAD = hexc("a89edc")     # Moon-silver midtone
HAIR_BASE = hexc("e2dcf6")     # Luminous moon-silver hair body
HAIR_HIGH = hexc("fffaf4")     # Starlight crown highlight
HAIR_TWIL = hexc("4a408a")     # Twilight lavender-indigo nebula bridge
HAIR_NEB_M = hexc("261e5e")    # Starry cosmos-indigo lower lock midtone
HAIR_NEB_D = hexc("110c30")    # Deep interstellar indigo tip shadow

PEARL_SHAD = hexc("9c94c2")    # Moon-ivory deep drapery fold
PEARL_MID = hexc("cac4e4")     # Moon-ivory midtone
PEARL_BASE = hexc("eeeaf8")    # Luminous moon-ivory silk
PEARL_HIGH = hexc("fffdf8")    # Crisp silk highlight

STOLE_DEEP = hexc("0e102c")    # Midnight-sapphire Hagoromo shadow
STOLE_BASE = hexc("1e2558")    # Midnight-sapphire base
STOLE_HIGH = hexc("3a4a94")    # Astral sapphire lit edge

GOLD_DEEP = hexc("6f5020")
GOLD_MID = hexc("b48a38")
GOLD_BRIGHT = hexc("e6c468")
GOLD_GLEAM = hexc("fff0b0")

TEAL_DEEP = hexc("1c6472")
TEAL_MID = hexc("3cc0c6")
TEAL_BRIGHT = hexc("78f4e6")
STAR_WHITE = hexc("f4ffff")

ROSE_DARK = hexc("9e4e6c")
ROSE_SOFT = hexc("dc8ea6")


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
            x_int = (x_b - x_a) * (yy - y_a) / (y_b - y_a + 1e-12) + x_a
            inside ^= cond & (xx < x_int)
        self.buf[y0:y1, x0:x1][inside] = c_i

    @staticmethod
    def bezier_pts(ctrl: list[tuple[float, float]], steps: int = 36) -> list[tuple[float, float]]:
        pts: list[tuple[float, float]] = []
        n = len(ctrl) - 1
        for s in range(steps + 1):
            t = s / max(steps, 1)
            q = list(ctrl)
            for _ in range(n):
                q = [((1.0 - t) * q[i][0] + t * q[i + 1][0], (1.0 - t) * q[i][1] + t * q[i + 1][1]) for i in range(len(q) - 1)]
            pts.append(q[0])
        return pts

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
        left_e, right_e, mid_e, hi_l, hi_r = [], [], [], [], []
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
            left_e.append((px - nx * w, py - ny * w))
            right_e.append((px + nx * w, py + ny * w))
            mid_e.append((px + nx * w * 0.22 * shad_side, py + ny * w * 0.22 * shad_side))
            hi_l.append((px - nx * w * 0.46, py - ny * w * 0.46))
            hi_r.append((px + nx * w * 0.04, py + ny * w * 0.04))
        full = left_e + right_e[::-1]
        self.poly(full, rgb_base)
        if rgb_shad is not None:
            self.poly((mid_e + right_e[::-1]) if shad_side > 0 else (left_e + mid_e[::-1]), rgb_shad)
        if rgb_high is not None:
            s0, s1 = int(steps * 0.08), int(steps * 0.48)
            if s1 > s0 + 2:
                self.poly(hi_l[s0:s1] + hi_r[s0:s1][::-1], rgb_high)
        return full

    def ellipse_ring(
        self,
        cx: float,
        cy: float,
        rx: float,
        ry: float,
        tilt_deg: float,
        thickness: float,
        rgb: tuple[int, int, int],
        rgb_hi: tuple[int, int, int] | None = None,
        steps: int = 64,
    ) -> None:
        ang_t = math.radians(tilt_deg)
        ct, st = math.cos(ang_t), math.sin(ang_t)
        outer, inner = [], []
        for i in range(steps + 1):
            a = 2.0 * math.pi * (i / steps)
            ca, sa = math.cos(a), math.sin(a)
            ox, oy = (rx + thickness) * ca, (ry + thickness) * sa
            ix, iy = max(1.0, rx - thickness) * ca, max(1.0, ry - thickness) * sa
            outer.append((cx + ox * ct - oy * st, cy + ox * st + oy * ct))
            inner.append((cx + ix * ct - iy * st, cy + ix * st + iy * ct))
        for i in range(steps):
            self.poly([outer[i], outer[i + 1], inner[i + 1], inner[i]], rgb_hi if (rgb_hi and 8 <= i <= 28) else rgb)

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
# Redesigned Caelia v2 Portrait Layers
# ---------------------------------------------------------------------------
def build_astrolabe_back() -> np.ndarray:
    """Two delicate tilted antique-gold astrolabe rings orbiting visibly around BOTH sides of her crown
    with luminous turquoise & diamond-white starlight nodes."""
    c = Canvas2D()
    cx, cy = 51.5, 22.5
    c.ellipse_ring(cx, cy, 37.5, 19.0, -14.0, 0.85, GOLD_BRIGHT, GOLD_GLEAM)
    c.ellipse_ring(cx, cy + 1.5, 32.0, 15.5, 17.0, 0.78, GOLD_MID, GOLD_BRIGHT)

    nodes = [
        (16.0, 29.0, True),
        (25.0, 11.5, False),
        (52.0, 4.5, True),
        (78.0, 11.0, False),
        (87.0, 19.5, True),
        (81.0, 32.0, True),
        (21.0, 17.0, False),
    ]
    for nx, ny, bright in nodes:
        r_n = 2.4 if bright else 1.8
        c.poly([(nx, ny - r_n), (nx + r_n, ny), (nx, ny + r_n), (nx - r_n, ny)], TEAL_BRIGHT if bright else GOLD_GLEAM)
        c.poly([(nx, ny - r_n * 0.52), (nx + r_n * 0.52, ny), (nx, ny + r_n * 0.52), (nx - r_n * 0.52, ny)], STAR_WHITE)

    return outline_layer(c.resolve(min_cov=5), INK_BRONZE, skip_bottom=True)


def build_stole_and_nebula_hair() -> np.ndarray:
    """Wide floating midnight-sapphire Hagoromo celestial stole + billowing Living Nebula hair
    (moon-silver crown flowing into twilight lavender-indigo & starry deep cosmos tips!)."""
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    # 1. Sweeping Midnight-Sapphire Celestial Stole arching behind shoulders & billowing outward
    cs = Canvas2D()
    cs.ribbon(
        [(5, 118), (11, 86), (26, 68), (54, 62), (76, 68), (91, 88), (96, 122)],
        [5.2, 6.8, 6.4, 5.2, 5.8, 6.4, 4.8],
        STOLE_BASE,
        rgb_shad=STOLE_DEEP,
        rgb_high=STOLE_HIGH,
        shad_side=1.0,
    )
    # Antique-gold top trim & fine constellation lines along the floating stole
    cs.ribbon([(7, 114), (13, 83), (27, 65), (54, 59), (77, 65), (90, 86), (94, 118)], [0.75, 0.85, 0.85, 0.75, 0.85, 0.85, 0.7], GOLD_BRIGHT)
    cs.ribbon([(10, 108), (16, 86), (29, 71)], [0.55, 0.65, 0.55], TEAL_MID)
    cs.ribbon([(77, 71), (86, 90), (92, 114)], [0.55, 0.65, 0.55], TEAL_MID)
    stole_img = outline_layer(cs.resolve(min_cov=6), INK_DARK, skip_bottom=True)
    # Crisp 1px constellation stars on the stole
    for sx, sy, col in ((13, 94, STAR_WHITE), (21, 76, TEAL_BRIGHT), (83, 82, TEAL_BRIGHT), (90, 102, STAR_WHITE), (10, 112, TEAL_BRIGHT)):
        stole_img[sy, sx] = (*col, 255)
    paste_over(out, stole_img)

    # 2. Voluminous Weightless Living Nebula Back Hair (billowing wider in zero-G!)
    back_locks = [
        ([(66, 22), (83, 44), (80, 78), (90, 114), (84, 150)], [5.0, 6.6, 6.4, 5.2, 1.4], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
        ([(48, 18), (44, 54), (40, 96), (38, 146)], [16.5, 19.0, 18.0, 14.5], HAIR_DEEP, None, None, 1.0),
        ([(33, 21), (13, 44), (17, 74), (4, 106), (9, 142)], [5.2, 7.6, 7.2, 5.8, 1.0], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
        ([(37, 20), (20, 50), (11, 86), (17, 120), (8, 153)], [6.0, 8.0, 8.2, 6.6, 1.8], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
        ([(42, 26), (29, 58), (21, 94), (26, 128), (20, 153)], [5.6, 7.4, 7.6, 6.2, 2.2], HAIR_BASE, HAIR_SHAD, HAIR_HIGH, 1.0),
    ]
    hair_img = np.zeros((CH, CW, 4), dtype=np.uint8)
    for ctrl, wids, c_base, c_shad, c_hi, s_side in back_locks:
        cl = Canvas2D()
        cl.ribbon(ctrl, wids, c_base, rgb_shad=c_shad, rgb_high=c_hi, shad_side=s_side)
        paste_over(hair_img, outline_layer(cl.resolve(min_cov=6), INK_PLUM, skip_bottom=True))

    # Apply the signature Living Nebula gradient to lower cascading hair strands (`y >= 94`)!
    # Smoothly steps Moon-Silver -> Twilight Lavender-Indigo -> Starry Midnight Cosmos-Indigo with Bayer dither!
    bayer4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0
    solid_h = hair_img[..., 3] == 255
    for y in range(88, CH):
        for x in range(CW):
            if not solid_h[y, x]:
                continue
            px = tuple(int(v) for v in hair_img[y, x, :3])
            if px == INK_PLUM:
                continue
            wave_y = y + 6.0 * math.sin(x * 0.14)
            t = (wave_y - 90.0) / 46.0
            d = bayer4[y % 4, x % 4]
            if t > 0.85 + d * 0.25:
                hair_img[y, x, :3] = HAIR_NEB_D if px in (HAIR_DEEP, HAIR_SHAD) else HAIR_NEB_M
            elif t > 0.42 + d * 0.35:
                hair_img[y, x, :3] = HAIR_NEB_M if px == HAIR_DEEP else HAIR_TWIL

    # Crisp 1px unlit starlight points embedded inside the dark cosmic lower hair tips!
    for sx, sy, col in (
        (11, 118, STAR_WHITE), (19, 132, TEAL_BRIGHT), (7, 136, TEAL_BRIGHT),
        (24, 142, STAR_WHITE), (14, 146, GOLD_GLEAM), (84, 122, STAR_WHITE),
        (88, 138, TEAL_BRIGHT), (82, 145, GOLD_GLEAM), (28, 116, TEAL_BRIGHT),
    ):
        if 0 <= sx < CW and 0 <= sy < CH and solid_h[sy, sx]:
            hair_img[sy, sx] = (*col, 255)

    paste_over(out, hair_img)
    return out


def build_torso_and_flowing_gown() -> np.ndarray:
    """Flowing asymmetrical moon-ivory silk draped gown (left shoulder draped with antique gold clasp,
    bare moonlit right shoulder & collarbone with a subtle golden Kintsugi light seam; NO corset!)."""
    c = Canvas2D()

    # Slender neck & moonlit collarbones
    c.poly([(45, 50), (58, 51), (60, 69), (44, 69)], SKIN_BASE)
    c.poly([(45, 50), (58, 51), (57, 58), (50, 61), (44, 66)], SKIN_CAST)
    c.poly([(50, 60), (57, 58), (59, 65), (51, 66)], SKIN_SHAD)

    # 3/4 Shoulders & bare chest/collarbone (`x = 26..72`)
    c.poly([(26, 70), (44, 65), (60, 65), (72, 69), (74, 88), (24, 88)], SKIN_BASE)
    c.poly([(26, 70), (37, 68), (38, 86), (24, 86)], SKIN_SHAD)
    c.ribbon([(39, 71), (49, 73), (57, 73)], [0.8, 0.9, 0.5], SKIN_HIGH)
    c.ribbon([(61, 73), (67, 71), (70, 70)], [0.5, 0.8, 0.5], SKIN_HIGH)

    # Far right arm (`x = 70..81`)
    c.ribbon([(70, 72), (75, 95), (79, 120), (82, 148)], [3.8, 3.5, 3.3, 3.0], SKIN_SHAD, rgb_shad=SKIN_CAST, shad_side=1.0)

    # Subtle glowing antique-gold Kintsugi seam along her bare right shoulder / collarbone!
    c.ribbon([(60, 74), (65, 71), (70, 72)], [0.65, 0.78, 0.55], GOLD_GLEAM, rgb_shad=GOLD_BRIGHT)
    c.ribbon([(64, 72), (66, 76)], [0.5, 0.4], GOLD_BRIGHT)

    # Flowing Asymmetrical Moon-Ivory Silk Veil Gown (draped cleanly over viewer-left shoulder, sweeping across bust & flowing down!)
    c.poly([(24, 67), (44, 66), (55, 79), (71, 83), (71, 114), (86, 155), (16, 155), (32, 112), (26, 86)], PEARL_BASE)
    # Soft vertical & diagonal Grecian silk drapery folds (cool-violet shadows, zero corset rigidity!)
    c.poly([(16, 155), (32, 112), (43, 112), (31, 155)], PEARL_HIGH)
    c.poly([(28, 70), (41, 70), (47, 94), (32, 96)], PEARL_HIGH)
    c.poly([(44, 113), (53, 114), (48, 155), (36, 155)], PEARL_MID)
    c.poly([(58, 83), (71, 83), (70, 114), (58, 114)], PEARL_MID)
    c.poly([(64, 113), (71, 113), (85, 155), (71, 155)], PEARL_SHAD)
    c.poly([(48, 114), (58, 115), (62, 155), (50, 155)], PEARL_HIGH)
    c.ribbon([(34, 76), (48, 87), (64, 92)], [1.0, 1.2, 1.0], PEARL_MID)
    c.ribbon([(34, 88), (50, 96), (67, 98)], [0.9, 1.0, 0.8], PEARL_MID)

    # Delicate antique-gold clasp on the draped left shoulder + slender braided golden under-bust sash cord
    c.poly([(36, 66), (40, 69), (36, 73), (32, 69)], GOLD_GLEAM)
    c.poly([(36, 67.5), (38.2, 69), (36, 71), (33.8, 69)], TEAL_BRIGHT)

    c.ribbon([(32, 108), (48, 111), (62, 112), (71, 109)], [1.2, 1.4, 1.4, 1.1], GOLD_BRIGHT, rgb_shad=GOLD_MID, rgb_high=GOLD_GLEAM)
    c.ribbon([(58, 112), (61, 128), (64, 146)], [0.8, 0.9, 0.7], GOLD_BRIGHT)
    c.ribbon([(55, 112), (56, 126), (55, 142)], [0.65, 0.75, 0.55], TEAL_MID)

    return outline_layer(c.resolve(min_cov=6), INK_DARK, skip_bottom=True)


def build_front_arm_and_veil_threads() -> np.ndarray:
    """Graceful floating left arm & palm holding luminous drifting turquoise-gold Veil threads."""
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    ca = Canvas2D()
    ca.ribbon(
        [(28, 74), (21, 93), (20, 106), (34, 109), (48, 105)],
        [4.2, 3.7, 3.5, 3.0, 2.4],
        SKIN_BASE,
        rgb_shad=SKIN_SHAD,
        rgb_high=SKIN_HIGH,
        shad_side=1.0,
    )
    ca.poly([(47, 103), (56, 100), (63, 101), (61, 105), (53, 107), (47, 107)], SKIN_BASE)
    ca.poly([(47, 106), (54, 106), (60, 104), (58, 107), (48, 108)], SKIN_SHAD)
    ca.ribbon([(54, 101), (61, 99), (65, 98)], [1.1, 0.85, 0.45], SKIN_HIGH)
    ca.ribbon([(41, 104), (44, 107), (45, 109)], [1.2, 1.3, 1.1], GOLD_BRIGHT, rgb_shad=GOLD_MID)
    arm_raw = ca.resolve(min_cov=6)
    arm_out = outline_layer(arm_raw, INK_DARK, skip_bottom=True)
    arm_out[:78, 22:33] = arm_raw[:78, 22:33]
    paste_over(out, arm_out)

    # Delicate luminous turquoise-gold Veil threads drifting airily above her open palm (no heavy dark borders!)
    ct = Canvas2D()
    ct.ribbon([(49, 98), (57, 92), (66, 95), (75, 87)], [0.55, 0.70, 0.62, 0.42], TEAL_BRIGHT, rgb_high=STAR_WHITE)
    ct.ribbon([(53, 100), (62, 97), (70, 91), (78, 92)], [0.45, 0.55, 0.50, 0.35], GOLD_GLEAM)
    sx, sy = 59.5, 90.0
    ct.poly([(sx, sy - 4.2), (sx + 1.2, sy - 1.0), (sx + 3.8, sy), (sx + 1.2, sy + 1.0), (sx, sy + 4.2), (sx - 1.2, sy + 1.0), (sx - 3.8, sy), (sx - 1.2, sy - 1.0)], TEAL_BRIGHT)
    ct.poly([(sx, sy - 2.4), (sx + 0.8, sy - 0.5), (sx + 2.2, sy), (sx + 0.8, sy + 0.5), (sx, sy + 2.4), (sx - 0.8, sy + 0.5), (sx - 2.2, sy), (sx - 0.8, sy - 0.5)], STAR_WHITE)
    t_img = ct.resolve(min_cov=4)
    # Soft delicate teal spark accents instead of thick dark outline
    for spx, spy, scol in ((53, 91, STAR_WHITE), (68, 87, GOLD_GLEAM), (73, 95, TEAL_BRIGHT), (63, 84, TEAL_BRIGHT)):
        t_img[spy, spx] = (*scol, 255)
    paste_over(out, t_img)

    return out


def build_face_head_base() -> np.ndarray:
    c = Canvas2D()
    c.poly([(36, 38), (41, 37), (42, 46), (38, 46), (36, 42)], SKIN_SHAD)
    c.poly([(37, 39), (40, 39), (40, 43), (38, 43)], SKIN_CAST)

    face_pts = c.bezier_pts([(40.5, 30.0), (47.0, 21.0), (63.0, 21.5), (68.5, 29.0)], 14)
    face_pts += [
        (69.0, 34.0), (67.6, 38.5), (68.5, 41.2), (70.2, 44.2), (67.6, 46.5),
        (67.8, 49.0), (66.5, 52.8), (62.8, 55.8), (58.5, 57.2), (52.5, 55.8),
        (46.0, 52.5), (41.2, 47.5), (40.2, 39.0),
    ]
    c.poly(face_pts, SKIN_BASE)
    c.poly([(40.2, 30.0), (45.0, 24.0), (50.0, 26.0), (44.5, 35.0), (44.0, 48.0), (48.0, 53.5), (41.2, 47.5)], SKIN_SHAD)
    c.poly([(40.2, 27.0), (46.0, 22.0), (66.0, 23.0), (67.0, 25.2), (45.0, 26.5), (42.5, 38.0)], SKIN_CAST)
    c.poly([(64.5, 39.5), (66.8, 40.5), (69.2, 44.0), (66.8, 44.8)], SKIN_HIGH)
    c.poly([(48.0, 43.5), (54.0, 43.5), (53.0, 46.2), (47.5, 45.8)], SKIN_HIGH)

    raw = c.resolve(min_cov=6)
    return outline_layer(raw, INK_DARK, skip_bottom=True)


def stamp_face_features(img: np.ndarray, blink: bool) -> None:
    def px(x: int, y: int, rgb: tuple[int, int, int]) -> None:
        if 0 <= x < CW and 0 <= y < CH:
            img[y, x] = (*rgb, 255)

    # Minimalist golden starlight mark on forehead (`(59, 28)`)
    px(59, 26, GOLD_GLEAM)
    px(59, 27, STAR_WHITE)
    px(59, 28, GOLD_BRIGHT)
    px(58, 27, GOLD_BRIGHT)
    px(60, 27, GOLD_BRIGHT)

    # Serene soft brows
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
                px(x, y, STOLE_DEEP)
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
        px(64, 39, STOLE_DEEP)
        px(65, 39, STOLE_DEEP)
        px(64, 40, STOLE_DEEP)
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

    # Warm serene slight smile
    px(57, 50, SKIN_CAST)
    px(58, 50, ROSE_DARK)
    px(59, 50, ROSE_DARK)
    px(60, 50, ROSE_DARK)
    px(61, 50, ROSE_DARK)
    px(62, 49, SKIN_CAST)
    px(59, 51, ROSE_SOFT)
    px(60, 51, ROSE_SOFT)
    px(61, 51, ROSE_SOFT)


def build_front_weightless_hair() -> np.ndarray:
    """Airy weightless moon-silver parted crown & softly billowing temple locks (NO heavy diadem!)."""
    out = np.zeros((CH, CW, 4), dtype=np.uint8)

    # Weightless gently curving side shoulder locks leaving face & bare Kintsugi shoulder clear
    for ctrl, wids, sh_side in (
        ([(38, 28), (30, 50), (35, 76), (28, 102), (33, 126)], [3.0, 3.4, 2.8, 1.9, 0.4], 1.0),
        ([(70, 27), (78, 48), (74, 72), (80, 96), (76, 118)], [2.3, 2.7, 2.2, 1.5, 0.4], -1.0),
    ):
        cl = Canvas2D()
        cl.ribbon(ctrl, wids, HAIR_BASE, rgb_shad=HAIR_SHAD, rgb_high=HAIR_HIGH, shad_side=sh_side)
        paste_over(out, outline_layer(cl.resolve(min_cov=6), INK_PLUM, skip_bottom=True))

    # Airy center-parted weightless crown & lifted feathered temple bangs (clear forehead star!)
    cb = Canvas2D()
    cb.ribbon([(57, 15), (43, 12), (31, 21), (34, 34), (39, 45)], [4.2, 6.6, 5.6, 3.0, 0.5], HAIR_BASE, rgb_shad=HAIR_SHAD, rgb_high=HAIR_HIGH, shad_side=1.0)
    cb.ribbon([(56, 17), (48, 21), (44, 28), (43, 34)], [2.6, 2.8, 1.8, 0.35], HAIR_HIGH, rgb_shad=HAIR_BASE, shad_side=1.0)
    cb.ribbon([(58, 15), (67, 14), (75, 22), (76, 33), (74, 41)], [3.6, 5.2, 4.0, 2.1, 0.4], HAIR_BASE, rgb_shad=HAIR_SHAD, rgb_high=HAIR_HIGH, shad_side=-1.0)
    cb.ribbon([(60, 17), (65, 21), (69, 27), (70, 32)], [1.9, 2.0, 1.2, 0.3], HAIR_HIGH, rgb_shad=HAIR_SHAD, shad_side=-1.0)
    paste_over(out, outline_layer(cb.resolve(min_cov=5), INK_PLUM, skip_bottom=True))

    return out


def render_portrait_sheet() -> np.ndarray:
    astro = build_astrolabe_back()
    back_hv = build_stole_and_nebula_hair()
    torso = build_torso_and_flowing_gown()
    face_base = build_face_head_base()
    front_hair = build_front_weightless_hair()
    front_arm = build_front_arm_and_veil_threads()

    cells: list[np.ndarray] = []
    for is_blink in (False, True):
        cell = np.zeros((CH, CW, 4), dtype=np.uint8)
        paste_over(cell, astro)
        paste_over(cell, back_hv)
        paste_over(cell, torso)

        face_cell = face_base.copy()
        stamp_face_features(face_cell, blink=is_blink)
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
