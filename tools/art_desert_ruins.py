#!/usr/bin/env python3
"""Procedural pixel-art generator for Sonnenquarz-Öde Ancient Ruins & Prismatic Quartz (stdlib + PIL for Ellie QA).

Outputs (top-left sunlight, 3-4+ cel steps + Bayer/Voronoi facets, 1px tinted outlines — ZERO #000000, separate *_glow.png):
  Items (16x16):
    - assets/items/prism_shard.png
    - assets/items/ruin_stone.png
  Mineable Ores (4 cols x 4 rows of 64x56 = 256x224, feet at (32, 52)):
    - assets/props/prism_vein.png        + assets/props/prism_vein_glow.png
    - assets/props/ruin_sandstone.png    + assets/props/ruin_sandstone_glow.png
  Active Scattered Ruin Props:
    - assets/props/quartz_arch.png       + assets/props/quartz_arch_glow.png       (3x1 of 96x88 = 288x88, feet (48, 82))
    - assets/props/resonance_obelisk.png + assets/props/resonance_obelisk_glow.png (4x1 of 48x72 = 192x72, feet (24, 66))
    - assets/props/light_conduit.png     + assets/props/light_conduit_glow.png     (4x1 of 32x24 = 128x24, center (16, 12))
    - assets/props/quartz_seal.png       + assets/props/quartz_seal_glow.png       (2x1 of 64x64 = 128x64, center (32, 32))
  Visual QA Contact Sheet:
    - docs/img/desert_ruins.png          (2x day + night with additive glow + Ellie 'sweat' standby strip)

Usage:
  py -3 tools/art_desert_ruins.py
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art_stone as S  # noqa: E402
from art_bush import BAYER, blank, check_icon, clamp  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, outline_pass, write_png  # noqa: E402


def ramp(*cols):
    return [hexc(c) for c in cols]


# Harmonized Sonnenquarz-Öde Ruin & Prismatic Palettes (ZERO #000000 anywhere!)
QUARTZ_W = ramp("5b698e", "8191b6", "a2b3d4", "bfcde7", "d6e2f5", "ffffff")
QUARTZ_DEEP = hexc("364262")
QUARTZ_INK = hexc("282238")

SANDSTONE_INK = hexc("2a1c28")
SANDSTONE = ramp("483038", "785042", "aa7a4e", "d8a868", "f2cf8e")
SAND_DRIFT = ramp("6e4934", "9c6c44", "c89658", "e6be78", "f7de9e")

GOLD_INK = hexc("34221e")
GOLD = ramp("6f5020", "b48a38", "e6c468", "fff0b0")

TURQ = ramp("2a8c94", "3cc0c6", "78f4e6", "d0fff8")
VIOLET = ramp("34185e", "6636ad", "9468ee", "cbaaff")
AMBER = ramp("9e5418", "dc8428", "ffb84a", "fff0aa")

ICON_OUT = hexc("1b1a2e")


# ==============================================================================
# SHARED GEOMETRY, VORONOI & OUTLINE HELPERS
# ==============================================================================
def _qhash(ix: int, iy: int, seed: int) -> float:
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _voronoi_grain(x: float, y: float, seed: int, sc: float = 5.2):
    gx, gy = x / sc, y / sc
    ix, iy = int(math.floor(gx)), int(math.floor(gy))
    d1, d2 = 99.0, 99.0
    c1, c2 = (0, 0), (0, 0)
    v1, v2 = (0.0, 0.0), (0.0, 0.0)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = ix + dx, iy + dy
            jx = cx + 0.16 + 0.68 * _qhash(cx, cy, seed)
            jy = cy + 0.16 + 0.68 * _qhash(cx + 97, cy + 53, seed + 17)
            d = math.hypot(gx - jx, gy - jy)
            if d < d1:
                d2, c2, v2 = d1, c1, v1
                d1, c1, v1 = d, (cx, cy), (jx, jy)
            elif d < d2:
                d2, c2, v2 = d, (cx, cy), (jx, jy)
    edge_px = (d2 - d1) * sc
    h1 = _qhash(c1[0] * 7, c1[1] * 13, seed + 31)
    h2 = _qhash(c2[0] * 7, c2[1] * 13, seed + 31)
    ang = _qhash(c1[0] + 211, c1[1] + 89, seed) * math.tau
    ton_tl = (v2[0] - v1[0]) * -0.7071 + (v2[1] - v1[1]) * -0.7071
    return edge_px, h1, h2, ang, ton_tl


def _bayer(x: int, y: int) -> float:
    return BAYER[y % 4][x % 4] / 16.0 - 0.5


def _stone_shade(lit: float, x: int, y: int, pal=SANDSTONE) -> tuple:
    idx = int(clamp(lit * (len(pal) - 0.15) + _bayer(x, y) * 0.42, 0, len(pal) - 1))
    return pal[idx]


def _fill_poly(px, pts, col_fn, w: int, h: int, margin: int = 2):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    y0 = max(margin, int(math.floor(min(ys))))
    y1 = min(h - 1 - margin, int(math.ceil(max(ys))))
    x0 = max(margin, int(math.floor(min(xs))))
    x1 = min(w - 1 - margin, int(math.ceil(max(xs))))
    n = len(pts)
    for y in range(y0, y1 + 1):
        py_c = y + 0.5
        for x in range(x0, x1 + 1):
            px_c = x + 0.5
            inside = False
            for i in range(n):
                ax, ay = pts[i]
                bx, by = pts[(i + 1) % n]
                if (ay > py_c) != (by > py_c):
                    xin = (bx - ax) * (py_c - ay) / (by - ay) + ax
                    if px_c < xin:
                        inside = not inside
            if inside:
                c = col_fn(x, y) if callable(col_fn) else col_fn
                if c is not None:
                    px[y][x] = c


def _draw_sand_drift(px, is_sand, cx: float, cy: float, rx: float, ry: float, w: int, h: int, seed: int, margin: int = 2):
    """Soft wind-rippled desert sand mound/collar that merges seamlessly into desert sand floor."""
    y0 = max(margin, int(cy - ry) - 1)
    y1 = min(h - 1 - margin, int(cy + ry) + 1)
    x0 = max(margin, int(cx - rx) - 1)
    x1 = min(w - 1 - margin, int(cx + rx) + 1)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x + 0.5 - cx) / max(rx, 1.0)
            ny = (y + 0.5 - cy) / max(ry, 1.0)
            wav = 0.08 * math.sin(x * 0.45 + seed)
            d = nx * nx + (ny + wav) ** 2
            if d <= 1.0:
                lit = 0.58 - 0.36 * nx - 0.32 * ny + 0.08 * math.sin((x + y * 2) * 0.6 + seed)
                c = _stone_shade(lit, x, y, SAND_DRIFT)
                if d > 0.82 and ny > 0.15:
                    c = SAND_DRIFT[1 if nx > 0 else 2]
                px[y][x] = c
                if is_sand is not None:
                    is_sand[y][x] = True


def _put_ground_shadow(out, cx: float, cy: float, rx: float, ry: float, w: int, h: int, tint=(58, 36, 48)):
    """Soft warm plum-umber ground contact shadow ellipse."""
    for y in range(max(1, int(cy - ry) - 1), min(h - 1, int(cy + ry) + 2)):
        for x in range(max(1, int(cx - rx) - 1), min(w - 1, int(cx + rx) + 2)):
            d = ((x + 0.5 - cx) / max(rx, 1.0)) ** 2 + ((y + 0.5 - cy) / max(ry, 1.0)) ** 2
            if d <= 1.0:
                alpha = int(clamp((1.0 - d) * 96, 24, 88))
                if out[y][x][3] < alpha:
                    out[y][x] = (*tint, alpha)


def _selective_outline(px, is_sand, w: int, h: int, foot_cut_y: int, ink_main=SANDSTONE_INK, ink_quartz=QUARTZ_DEEP):
    """1px adaptive dark tinted contour on upper structure; skips drifted sand bottom edges for seamless ground blend!"""
    shape = [[px[y][x][3] == 255 for x in range(w)] for y in range(h)]
    quartz_set = set(QUARTZ_W) | set(TURQ) | set(VIOLET)
    out = [row[:] for row in px]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if shape[y][x]:
                continue
            nb = []
            sand_nb = 0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if shape[ny][nx]:
                    nb.append(px[ny][nx])
                    if is_sand is not None and is_sand[ny][nx]:
                        sand_nb += 1
            if not nb:
                continue
            # Never outline wind-drifted sand pixels (merges seamlessly into desert sand floor at any y!)
            if sand_nb == len(nb):
                continue
            if y >= foot_cut_y + 2 and not shape[y - 1][x]:
                continue
            is_q = any(c in quartz_set for c in nb)
            out[y][x] = ink_quartz if is_q else ink_main
    return out


def _add_glow_halo(glow, px, w: int, h: int, max_y: int = 999, alpha_scale: float = 0.28):
    """Adds a crisp 1px soft unshaded aura right around bright rune/core pixels."""
    snap = [row[:] for row in glow]
    for y in range(2, min(h - 2, max_y)):
        for x in range(2, w - 2):
            c = snap[y][x]
            if c[3] < 140:
                continue
            ha = int(c[3] * alpha_scale)
            if ha < 22:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if glow[ny][nx][3] < ha:
                    glow[ny][nx] = (c[0], c[1], c[2], ha)


def _sheet_from_grid(frames, cols: int, rows: int, cw: int, ch: int):
    out = [[CLEAR] * (cw * cols) for _ in range(ch * rows)]
    for idx, fr in enumerate(frames):
        ox = (idx % cols) * cw
        oy = (idx // cols) * ch
        for y in range(ch):
            out[oy + y][ox : ox + cw] = fr[y]
    return out


def _verify_sheet(name: str, frames, cw: int, ch: int, margin: int = 1):
    for i, fr in enumerate(frames):
        xs, ys = [], []
        for y in range(ch):
            for x in range(cw):
                c = fr[y][x]
                if c[3] > 0:
                    assert c[:3] != (0, 0, 0), f"{name}[{i}] has pure #000000 at ({x},{y})!"
                    xs.append(x)
                    ys.append(y)
        if xs:
            assert min(xs) >= margin and max(xs) <= cw - 1 - margin and min(ys) >= margin and max(ys) <= ch - 1 - margin, (
                f"{name}[{i}] clipped border ({cw}x{ch}, margin={margin}): x={min(xs)}..{max(xs)}, y={min(ys)}..{max(ys)}"
            )


# ==============================================================================
# 1. ITEM ICONS (16x16: prism_shard.png, ruin_stone.png)
# ==============================================================================
def make_icon_prism_shard():
    px = blank(16, 16)
    # Multi-faceted diagonal hexagonal crystal shard refracting turquoise, violet & sun-gold bands
    W5 = QUARTZ_W[5]
    W4 = QUARTZ_W[4]
    W2 = QUARTZ_W[2]
    W0 = QUARTZ_W[0]
    T3, T2, T1 = TURQ[3], TURQ[2], TURQ[1]
    V3, V2, V1 = VIOLET[3], VIOLET[2], VIOLET[1]
    G3, G2 = AMBER[3], AMBER[2]

    palette = {
        "W": W5, "w": W4, "s": W2, "d": W0,
        "T": T3, "t": T2, "c": T1,
        "V": V3, "v": V2, "p": V1,
        "G": G3, "g": G2,
    }
    rows = (
        "................",
        "................",
        ".........W......",
        "........WTW.....",
        ".......WTtVc....",
        "......WTtWVpv...",
        ".....WTtWVVpvg..",
        ".....WtWVVpvGg..",
        "....WtWVvGggsd..",
        "....tWVvGgsdd...",
        "...tWVvGgsdd....",
        "...wVvGgsd......",
        "....wvgsdd......",
        "................",
        "................",
    )
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != ".":
                px[y][x] = palette[ch]
    check_icon("prism_shard", px)
    return outline_pass(px, ICON_OUT)


def make_icon_ruin_stone():
    px = blank(16, 16)
    # Chiseled ancient desert sandstone ashlar block + tarnished gold clasp + glowing turquoise sun-rune inlay
    S4, S3, S2, S1, S0 = SANDSTONE[4], SANDSTONE[3], SANDSTONE[2], SANDSTONE[1], SANDSTONE[0]
    G3, G2, G1, G0 = GOLD[3], GOLD[2], GOLD[1], GOLD[0]
    T3, T2, T1 = TURQ[3], TURQ[2], TURQ[1]
    pal = {
        "4": S4, "3": S3, "2": S2, "1": S1, "0": S0,
        "Y": G3, "G": G2, "g": G1, "b": G0,
        "T": T3, "t": T2, "c": T1,
    }
    rows = (
        "................",
        "................",
        ".....444433.....",
        "...44433322GG...",
        "..44333222YGg...",
        "..33222222Gg1...",
        "..322cTTc22110..",
        "..32tTYYTt2110..",
        "..32tYTTYt2100..",
        "..222cttc21100..",
        "..21122221100...",
        "..GG11111100....",
        "...gb110000.....",
        "................",
        "................",
        "................",
    )
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != ".":
                px[y][x] = pal[ch]
    check_icon("ruin_stone", px)
    return outline_pass(px, ICON_OUT)


# ==============================================================================
# 2A. PRISM VEIN (assets/props/prism_vein{,_glow}.png — 4x4 of 64x56, feet (32,52))
# ==============================================================================
PRISM_VEIN_SPECS = [
    {
        # Variant 0: Radiant fan of tall prismatic hexagonal spires over pure QUARTZ_W Voronoi shelf
        "foot_rx": 18.0,
        "plinth": [(32.0, 49.5, 16.5, 3.2, 0.0), (24.0, 50.2, 8.5, 2.4, 0.2), (40.5, 50.2, 8.5, 2.4, -0.15)],
        "splinters": [(16, 51), (47, 51)],
        # (bx, by, len, hw, angle_deg, z_layer, hue_shift, cl1, cl2, max_st)
        "spires": [
            (25.0, 48.0, 24.0, 3.4, -22, 1.8, 0.0, 0.72, None, 1),
            (39.5, 48.0, 23.0, 3.3, 24, 1.9, 0.35, None, 0.52, 2),
            (29.5, 48.5, 36.5, 4.5, -7, 2.8, 0.15, 0.78, 0.50, 2),
            (35.8, 49.0, 30.5, 3.9, 12, 3.2, 0.55, None, 0.56, 2),
            (21.5, 49.5, 14.5, 2.3, -38, 3.5, 0.75, None, None, 2),
            (43.0, 49.5, 14.0, 2.2, 39, 3.6, 0.20, 0.66, None, 1),
            (32.5, 50.2, 17.5, 3.1, 2, 4.0, 0.45, None, 0.62, 2),
        ],
    },
    {
        # Variant 1: Twin crossed cathedral prism monarchs + low star needles
        "foot_rx": 17.5,
        "plinth": [(32.0, 49.6, 15.8, 3.1, 0.05), (23.5, 50.3, 8.0, 2.3, 0.15), (41.0, 50.1, 8.2, 2.4, -0.15)],
        "splinters": [(17, 51), (46, 52)],
        "spires": [
            (27.5, 48.2, 34.5, 4.3, -16, 2.2, 0.25, None, 0.52, 2),
            (36.5, 48.2, 35.5, 4.4, 15, 2.6, 0.62, 0.74, 0.48, 2),
            (32.0, 48.6, 25.5, 3.5, -2, 3.3, 0.05, 0.80, None, 1),
            (22.5, 49.6, 17.5, 2.6, -34, 3.6, 0.48, None, 0.58, 2),
            (41.8, 49.6, 16.5, 2.5, 35, 3.7, 0.85, None, None, 2),
            (29.0, 50.3, 14.5, 2.7, -10, 4.1, 0.35, None, 0.65, 2),
        ],
    },
    {
        # Variant 2: Sweeping wind-cantilevered asymmetric prism cluster
        "foot_rx": 18.5,
        "plinth": [(31.5, 49.5, 17.0, 3.2, 0.0), (22.5, 50.2, 8.6, 2.4, 0.22), (41.5, 50.2, 8.4, 2.3, -0.2)],
        "splinters": [(15, 51), (48, 51)],
        "spires": [
            (24.5, 48.2, 21.0, 3.1, -30, 1.9, 0.55, 0.68, None, 1),
            (30.5, 48.4, 37.0, 4.6, 11, 2.7, 0.10, 0.78, 0.50, 2),
            (36.8, 48.8, 29.0, 3.8, 25, 3.1, 0.42, None, 0.54, 2),
            (42.0, 49.5, 18.5, 2.8, 42, 3.5, 0.78, None, 0.60, 2),
            (26.8, 49.8, 22.5, 3.3, -6, 3.8, 0.28, None, 0.55, 2),
            (34.5, 50.3, 15.0, 2.6, 16, 4.2, 0.90, None, None, 2),
        ],
    },
    {
        # Variant 3: Open prismatic geode crown with glowing violet-turquoise heart spires
        "foot_rx": 19.0,
        "plinth": [(32.0, 49.4, 17.5, 3.3, 0.0), (22.5, 50.1, 9.0, 2.5, 0.2), (41.5, 50.1, 9.0, 2.5, -0.2)],
        "splinters": [(15, 52), (48, 51)],
        "spires": [
            (22.5, 48.5, 25.5, 3.5, -28, 2.0, 0.68, 0.72, 0.48, 2),
            (41.5, 48.5, 24.5, 3.4, 29, 2.1, 0.18, None, 0.48, 2),
            (28.5, 48.4, 33.0, 4.1, -9, 2.8, 0.38, 0.80, 0.54, 2),
            (35.5, 48.4, 34.5, 4.2, 8, 3.0, 0.02, None, 0.52, 2),
            (32.0, 49.5, 24.0, 3.6, 0, 3.8, 0.52, None, 0.60, 2),
            (25.5, 50.2, 13.5, 2.2, -19, 4.1, 0.82, None, None, 1),
            (38.5, 50.2, 13.5, 2.2, 20, 4.2, 0.28, None, None, 2),
        ],
    },
]


def _draw_quartz_voronoi_plinth(px, z_buf, cid_buf, is_base, spec, w_scale: float, h_scale: float, seed: int):
    for y in range(37, S.GR + 1):
        for x in range(4, S.RW - 4):
            edge_px, h1, h2, ang, ton_tl = _voronoi_grain(x, y, seed, sc=5.2)
            grain_step = (h1 - 0.5) * 0.42
            best_d = 99.0
            best_bias = 0.0
            for cx0, cy0, rx0, ry0, l_bias in spec["plinth"]:
                cx = 32.0 + (cx0 - 32.0) * w_scale
                cy = (S.GR - 0.8) - (S.GR - cy0) * h_scale
                rx = rx0 * w_scale
                ry = max(2.1, ry0 * (0.85 + 0.15 * h_scale))
                dx = (x + 0.5 - cx) / max(rx, 1.0)
                dy = (y + 0.5 - cy) / max(ry, 1.0)
                toe_mod = 0.14 * math.cos((x - 32.0) * 0.42 + (seed % 11)) if dy > 0.15 else 0.0
                d = math.hypot(dx, dy) * 0.80 + max(abs(dx), abs(dy)) * 0.20 + grain_step + toe_mod
                if d < best_d:
                    best_d = d
                    best_bias = l_bias
            if best_d > 1.0:
                continue
            facet_lit = -(math.cos(ang) * 0.72 + math.sin(ang) * 0.69)
            slope_tl = -((x - 32.0) / max(spec["foot_rx"] * w_scale, 8.0)) * 0.62 - ((y - 48.5) / 4.5) * 0.45
            q_idx = int(clamp(math.floor(2.45 + facet_lit * 0.95 + slope_tl + best_bias), 1, 4))
            if abs(h1 - h2) > 0.17:
                if edge_px < 0.95 and h1 > h2 and ton_tl > 0.05:
                    q_idx = 5
                elif edge_px < 0.88 and h2 > h1:
                    q_idx = max(0, q_idx - 2)
            z_val = 1.15 + (y - 46.0) * 0.08
            if z_val >= z_buf[y][x]:
                z_buf[y][x] = z_val
                cid_buf[y][x] = 1
                is_base[y][x] = True
                px[y][x] = QUARTZ_W[q_idx]


def _prism_spectral_color(q_idx: int, u: float, eff_len: float, v: float, hw_u: float, hue_shift: float):
    """Refracts crisp diagonal bands of Turquoise, Arcane Violet, and Sun-Gold across hexagonal QUARTZ_W facets,
    keeping the basal root (u < 3.2) pure QUARTZ_W so spires grow organically from white ground quartz!"""
    if u < 2.8:
        return QUARTZ_W[q_idx], None
    if q_idx == 5:
        return QUARTZ_W[5], (235, 252, 255, 185)

    # Diagonal crystal dispersion phase along spire height + facet plane
    phase = (u / max(eff_len, 8.0)) * 1.65 + (v / max(hw_u, 1.0)) * 0.28 + hue_shift
    band = phase % 1.0
    strength = clamp((u - 2.8) / 4.5, 0.0, 1.0)
    if strength < 0.35:
        return QUARTZ_W[q_idx], None

    if band < 0.34:
        # Turquoise refraction band
        c = TURQ[3] if q_idx >= 4 else (TURQ[2] if q_idx == 3 else (TURQ[1] if q_idx == 2 else TURQ[0]))
        g = (*TURQ[2][:3], 175 if q_idx >= 3 else 115)
        return c, g
    elif band < 0.64:
        # Arcane Violet refraction band
        c = VIOLET[3] if q_idx >= 4 else (VIOLET[2] if q_idx in (2, 3) else VIOLET[1])
        g = (*VIOLET[3 if q_idx >= 3 else 2][:3], 170 if q_idx >= 3 else 110)
        return c, g
    elif band < 0.84:
        # Warm Sun-Amber / Gold refraction band (bright faces) or cool pearl-slate (deep shadow face)
        if q_idx <= 1:
            return QUARTZ_W[q_idx], (*TURQ[1][:3], 70)
        c = AMBER[3] if q_idx >= 4 else (AMBER[2] if q_idx == 3 else GOLD[2])
        g = (*AMBER[3 if q_idx >= 4 else 2][:3], 165)
        return c, g
    else:
        # Pure snow-pearl quartz bridge band between spectral Dispersions
        return QUARTZ_W[q_idx], (220, 244, 255, 110 if q_idx >= 3 else 60)


def _draw_prismatic_spire(px, glow, z_buf, cid_buf, is_base, tips, bx, by, length, hw, angle_deg, z_depth, cid, hue_shift, seed, cleave_frac=None):
    rad = math.radians(angle_deg)
    ax, ay = math.sin(rad), -math.cos(rad)
    nx, ny = math.cos(rad), math.sin(rad)

    eff_len = length if cleave_frac is None else length * cleave_frac
    if eff_len < 3.5:
        return

    asym = (_qhash(cid * 17, seed, seed) - 0.5) * 0.20
    apex_v = asym * hw * 0.60
    h_tip = max(3.2, min(length * 0.35, hw * 2.05))
    l_shaft = max(1.5, length - h_tip)
    cleave_slope = -0.22 if (cid + seed) % 2 == 0 else 0.19

    tip_u = eff_len - (0.8 if cleave_frac is None else 1.2)
    tx = bx + ax * tip_u + nx * (apex_v if cleave_frac is None else -hw * 0.25)
    ty = by + ay * tip_u + ny * (apex_v if cleave_frac is None else -hw * 0.25)
    if ty < 47.0 and hw >= 2.0:
        tips.append((tx, ty, 1.9 if cleave_frac is None else 1.3, hue_shift))

    end_x, end_y = bx + ax * (eff_len + 2.0), by + ay * (eff_len + 2.0)
    pad = hw + 2.5
    min_x = max(3, int(math.floor(min(bx, end_x) - pad)))
    max_x = min(S.RW - 4, int(math.ceil(max(bx, end_x) + pad)))
    min_y = max(3, int(math.floor(min(by, end_y) - pad)))
    max_y = min(S.GR, int(math.ceil(max(by, end_y) + 2.0)))

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            dx = x + 0.5 - bx
            dy = y + 0.5 - by
            u = dx * ax + dy * ay
            v = dx * nx + dy * ny
            if u < -1.2:
                continue

            hw_u = hw * (1.0 - 0.05 * clamp(u / max(length, 1.0), 0.0, 1.0))
            if u < 0.0:
                hw_u *= max(0.0, 1.0 + u / 1.3)
            s1 = (-0.30 + asym * 0.35) * hw_u
            s2 = (0.34 + asym * 0.35) * hw_u

            q_idx = None
            z_px = z_depth

            if hw < 2.15:
                if u > eff_len:
                    continue
                v_lim = hw_u * max(0.0, (eff_len - u) / max(eff_len * 0.36, 0.8)) if (cleave_frac is None and u > eff_len * 0.64) else hw_u
                if abs(v) > v_lim + 0.15:
                    continue
                if u > eff_len - 1.3:
                    q_idx = 5
                elif v < -0.12 * hw_u:
                    q_idx = 4
                elif v <= 0.38 * hw_u:
                    q_idx = 3
                else:
                    q_idx = 1 if u > 1.5 else 0
                z_px = z_depth + 0.06
            elif cleave_frac is not None:
                if abs(v) > hw_u:
                    continue
                step_jog = 1.05 if v > s1 else 0.0
                u_top = eff_len + cleave_slope * v - step_jog
                if u > u_top:
                    continue
                cap_h = max(2.1, hw_u * 0.62)
                u_front = u_top - cap_h + (0.65 if s1 <= v <= s2 else 0.0)
                if u >= u_front:
                    if u < u_front + 0.95 or (v <= s1 and u > u_top - 0.85):
                        q_idx = 5
                    elif v < s1:
                        q_idx = 4
                    elif v <= s2 + 0.25 * hw_u:
                        q_idx = 3
                    else:
                        q_idx = 2
                    z_px = z_depth + 0.22
                else:
                    u_sh = u_front
            else:
                if u > length:
                    continue
                u_s1 = l_shaft - 0.24 * h_tip
                u_s2 = l_shaft - 0.15 * h_tip
                u_r = l_shaft + 0.04 * h_tip
                if v <= s1:
                    u_sh = l_shaft + (u_s1 - l_shaft) * clamp((v + hw_u) / max(s1 + hw_u, 0.4), 0.0, 1.0)
                elif v <= s2:
                    u_sh = u_s1 + (u_s2 - u_s1) * clamp((v - s1) / max(s2 - s1, 0.4), 0.0, 1.0)
                else:
                    u_sh = u_s2 + (u_r - u_s2) * clamp((v - s2) / max(hw_u - s2, 0.4), 0.0, 1.0)

                v_min = -hw_u if u <= l_shaft else -hw_u + (apex_v + hw_u) * ((u - l_shaft) / max(length - l_shaft, 0.6))
                v_max = hw_u if u <= u_r else hw_u + (apex_v - hw_u) * ((u - u_r) / max(length - u_r, 0.6))
                if v < v_min or v > v_max:
                    continue
                if u >= u_sh:
                    r1 = s1 + (apex_v - s1) * clamp((u - u_s1) / max(length - u_s1, 0.6), 0.0, 1.0)
                    r2 = s2 + (apex_v - s2) * clamp((u - u_s2) / max(length - u_s2, 0.6), 0.0, 1.0)
                    if u > length - 1.55 or v < v_min + 0.92 or abs(v - r1) < 0.54:
                        q_idx = 5
                    elif v < r1:
                        q_idx = 4
                    elif v <= r2:
                        q_idx = 4 if u > l_shaft + 0.42 * h_tip else 3
                    else:
                        q_idx = 2 if v < r2 + (v_max - r2) * 0.58 else 1
                    z_px = z_depth + 0.20

            if q_idx is None:
                t_sh = clamp(u / max(l_shaft, 1.0), 0.0, 1.0)
                if abs(v - s1) <= 0.56 and u > 1.8:
                    q_idx = 5 if t_sh > 0.16 else 4
                elif v < s1:
                    q_idx = 5 if (v < -hw_u + 0.90 and t_sh > 0.28) else (3 if u < 2.0 else 4)
                elif v <= s2:
                    q_idx = 3 if t_sh > 0.36 else 2
                else:
                    q_idx = 0 if (v > hw_u - 0.92 or u < 1.8) else 1
                z_px = z_depth + (0.16 if s1 <= v <= s2 else 0.06)

            if z_px >= z_buf[y][x]:
                z_buf[y][x] = z_px
                cid_buf[y][x] = cid
                is_base[y][x] = False
                col_px, glow_px = _prism_spectral_color(q_idx, u, eff_len, v, hw_u, hue_shift)
                px[y][x] = col_px
                glow[y][x] = glow_px if glow_px is not None else CLEAR


def _finish_prism_vein(px, glow, is_base, tips, stage: int, splinters=()):
    """Seamless QUARTZ_W foot (y >= 48, zero dark bottom outline!) + crisp QUARTZ_DEEP upper contour."""
    out = blank(S.RW, S.RH)
    shape = [[px[y][x][3] == 255 for x in range(S.RW)] for y in range(S.RH)]
    body = [row[:] for row in px]

    foot_y_start = 42 if stage == 3 else 48
    for y in range(foot_y_start, S.RH - 2):
        for x in range(2, S.RW - 2):
            if not shape[y][x]:
                continue
            if stage < 3 and not is_base[y][x] and y < 49:
                continue
            e_l = not shape[y][x - 1]
            e_u = not shape[y - 1][x]
            e_r = not shape[y][x + 1]
            e_d = not shape[y + 1][x]
            edge_tl = e_l or e_u
            edge_br = e_r or e_d
            if edge_br and not edge_tl:
                is_se = e_r or x >= 31 or ((x // 3 + y) % 2 == 0)
                body[y][x] = QUARTZ_W[0] if is_se else QUARTZ_W[1]
                if e_d and shape[y - 1][x] and (stage == 3 or is_base[y - 1][x] or y - 1 >= 49):
                    if body[y - 1][x] != QUARTZ_W[5]:
                        body[y - 1][x] = QUARTZ_W[1] if is_se else QUARTZ_W[2]
            elif edge_tl and (stage == 3 or is_base[y][x] or e_l):
                body[y][x] = QUARTZ_W[5] if (x + y) % 3 != 0 else QUARTZ_W[4]

    for sx, sy in splinters:
        if 3 <= sx <= S.RW - 5 and 48 <= sy <= S.RH - 3:
            body[sy][sx] = QUARTZ_W[5]
            body[sy][sx + 1] = QUARTZ_W[1]
            shape[sy][sx] = True
            shape[sy][sx + 1] = True

    # Cool slate-indigo translucent SE contact shadow on white ground quartz (never brown/black!)
    for y in range(48 if stage < 3 else 46, S.RH - 2):
        for x in range(2, S.RW - 3):
            if shape[y][x] and (not shape[y + 1][x] or not shape[y][x + 1]) and x >= 27:
                for dx, dy, alpha in ((1, 1, 74), (0, 1, 56), (2, 1, 34)):
                    sx, sy = x + dx, y + dy
                    if 2 <= sx <= S.RW - 3 and 49 <= sy <= S.RH - 2 and not shape[sy][sx]:
                        if out[sy][sx][3] < alpha:
                            out[sy][sx] = (68, 82, 118, alpha)

    for y in range(S.RH):
        for x in range(S.RW):
            if shape[y][x]:
                out[y][x] = body[y][x]

    if stage < 3:
        for y in range(2, 48):
            for x in range(2, S.RW - 2):
                if shape[y][x]:
                    continue
                has_r = x + 1 < S.RW and shape[y][x + 1]
                has_l = x - 1 >= 0 and shape[y][x - 1]
                has_d = y + 1 < S.RH and shape[y + 1][x]
                has_u = y - 1 >= 0 and shape[y - 1][x]
                if not (has_r or has_l or has_d or has_u):
                    continue
                if y == 47 and has_d and not (has_l or has_r or has_u) and is_base[48][x]:
                    continue
                shaded = has_l or has_u
                out[y][x] = QUARTZ_INK if shaded else QUARTZ_DEEP

        # Soft 1px prismatic tip aura in glow sheet
        for tx, ty, rad, hsh in tips:
            ir = int(math.ceil(rad + 1.8))
            cx, cy = int(round(tx)), int(round(ty))
            aura_rgb = TURQ[2][:3] if (hsh % 1.0) < 0.45 else VIOLET[3][:3]
            for y in range(max(2, cy - ir), min(47, cy + ir + 1)):
                for x in range(max(2, cx - ir), min(S.RW - 2, cx + ir + 1)):
                    if glow[y][x][3] > 0 or out[y][x][3] > 0:
                        continue
                    if math.hypot(x - tx, y - ty) <= rad + 1.5:
                        near = any(shape[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy)
                        if near:
                            glow[y][x] = (*aura_rgb, 58)

    return out, glow


def render_prism_vein(idx: int, stage: int):
    spec = PRISM_VEIN_SPECS[idx]
    seed = 7100 + idx * 137 + stage * 19
    px = blank(S.RW, S.RH)
    glow = blank(S.RW, S.RH)
    z_buf = [[-1e9] * S.RW for _ in range(S.RH)]
    cid_buf = [[0] * S.RW for _ in range(S.RH)]

    if stage == 3:
        is_base = [[True] * S.RW for _ in range(S.RH)]
        rx = spec["foot_rx"]
        rubble_spec = {
            "foot_rx": rx,
            "plinth": [
                (32.0 - rx * 0.40, 49.8, 4.5, 1.9, 0.2),
                (32.0 + rx * 0.08, 50.3, 5.2, 2.0, 0.0),
                (32.0 + rx * 0.44, 49.6, 4.3, 1.8, -0.2),
            ],
        }
        _draw_quartz_voronoi_plinth(px, z_buf, cid_buf, is_base, rubble_spec, 1.0, 1.0, seed + 51)
        tips = []
        for bx, by, ln, hw, ang, zv, cid, hs in (
            (32.0 - rx * 0.22, 49.6, 8.8, 2.2, -68, 2.4, 11, 0.15),
            (32.0 + rx * 0.18, 49.8, 9.2, 2.4, 72, 2.8, 12, 0.52),
            (32.0 - rx * 0.02, 48.8, 6.8, 1.9, 55, 3.2, 13, 0.80),
        ):
            _draw_prismatic_spire(px, glow, z_buf, cid_buf, is_base, tips, bx, by, ln, hw, ang, zv, cid, hs, seed + cid * 13)
        # Keep rubble glow subtle
        for y in range(S.RH):
            for x in range(S.RW):
                if glow[y][x][3] > 0:
                    c = glow[y][x]
                    glow[y][x] = (c[0], c[1], c[2], min(85, c[3] // 2))
        return _finish_prism_vein(px, glow, is_base, [], 3, splinters=spec["splinters"])

    is_base = [[False] * S.RW for _ in range(S.RH)]
    tips = []
    w_scale = (1.0, 0.94, 0.82)[stage]
    h_scale = (1.0, 0.88, 0.64)[stage]
    _draw_quartz_voronoi_plinth(px, z_buf, cid_buf, is_base, spec, w_scale, h_scale, seed)

    for si, (bx0, by0, length, hw, ang, z_layer, hsh, cl1, cl2, max_st) in enumerate(spec["spires"]):
        if stage > max_st:
            continue
        bx = 32.0 + (bx0 - 32.0) * w_scale
        by = S.GR - (S.GR - by0) * (0.92 if stage == 1 else (0.76 if stage == 2 else 1.0))
        if stage == 0:
            ln, pw, cleave = length, hw, None
        elif stage == 1:
            ln, pw, cleave = (length, hw * 0.97, cl1) if cl1 is not None else (length * 0.84, hw * 0.94, None)
        else:
            ln, pw, cleave = (length, hw * 0.91, cl2) if cl2 is not None else (length * 0.54, hw * 0.84, None)
        _draw_prismatic_spire(px, glow, z_buf, cid_buf, is_base, tips, bx, by, ln, pw, ang, z_layer, 10 + si, hsh, seed + si * 29, cleave_frac=cleave)

    if stage in (1, 2):
        rx = spec["foot_rx"] * w_scale
        for ci, (ox, ang, hs) in enumerate(((-rx * 0.50, -64, 0.2), (rx * 0.48, 66, 0.6))):
            _draw_prismatic_spire(px, glow, z_buf, cid_buf, is_base, tips, 32.0 + ox, 50.2, 5.8, 1.8, ang, 4.3 + ci * 0.1, 40 + ci, hs, seed + 99 + ci)

    # Carve crisp internal overlap creases between adjacent spires
    snap_z = [row[:] for row in z_buf]
    snap_id = [row[:] for row in cid_buf]
    for y in range(3, S.GR):
        for x in range(3, S.RW - 3):
            cid = snap_id[y][x]
            if cid <= 1 or is_base[y][x]:
                continue
            my_z = snap_z[y][x]
            hits = sum(
                1 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
                if snap_id[y + dy][x + dx] > 1 and snap_id[y + dy][x + dx] != cid and snap_z[y + dy][x + dx] - my_z >= 0.42
            )
            if hits:
                px[y][x] = QUARTZ_DEEP if hits >= 2 else QUARTZ_W[0]
                glow[y][x] = CLEAR

    splinters = [(int(round(32.0 + (sx - 32.0) * w_scale)), sy) for sx, sy in spec["splinters"]]
    return _finish_prism_vein(px, glow, is_base, tips, stage, splinters=splinters)


# ==============================================================================
# 2B. RUIN SANDSTONE (assets/props/ruin_sandstone{,_glow}.png — 4x4 of 64x56)
# ==============================================================================
def _draw_ashlar_box(px, is_sand, x0: int, y0: int, x1: int, y1: int, top_depth: int, side_split: int, seed: int, gold_band_y=None):
    """Draws a 3/4 isometric-perspective chiseled desert sandstone block with top bevel, sunlit left face & shaded right face."""
    # Top sky-facing plane (y0 .. y0 + top_depth)
    for y in range(y0, y0 + top_depth + 1):
        indent = int((y0 + top_depth - y) * 0.6)
        for x in range(x0 + indent, x1 - indent + 1):
            lit = 0.88 - 0.18 * ((x - x0) / max(1, x1 - x0)) - 0.08 * ((y - y0) / max(1, top_depth))
            px[y][x] = _stone_shade(lit, x, y, SANDSTONE)
            if is_sand is not None:
                is_sand[y][x] = False

    # Front-left sunlit face & front-right shaded face
    for y in range(y0 + top_depth + 1, y1 + 1):
        vt = (y - (y0 + top_depth)) / max(1, y1 - (y0 + top_depth))
        for x in range(x0, x1 + 1):
            if x <= side_split:
                lit = 0.66 - 0.14 * ((x - x0) / max(1, side_split - x0)) - 0.16 * vt
            else:
                lit = 0.34 - 0.18 * ((x - side_split) / max(1, x1 - side_split)) - 0.12 * vt
            # Subtle weathered sandstone pitting / strata
            if (y - y0) % 6 == 0 and noise(x, y, seed) > 125:
                lit -= 0.14
            c = _stone_shade(lit, x, y, SANDSTONE)
            if y == y0 + top_depth + 1 and x <= side_split:
                c = SANDSTONE[4]
            if x == side_split:
                c = SANDSTONE[3 if vt < 0.5 else 2]
            px[y][x] = c
            if is_sand is not None:
                is_sand[y][x] = False

    # Optional tarnished gold frieze band wrapping both faces
    if gold_band_y is not None:
        gy = gold_band_y
        for dy in range(3):
            yy = gy + dy
            if y0 + top_depth < yy <= y1:
                for x in range(x0, x1 + 1):
                    if dy == 0:
                        px[yy][x] = GOLD[3 if x <= side_split else 2]
                    elif dy == 1:
                        px[yy][x] = GOLD[2 if x <= side_split else 1]
                    else:
                        px[yy][x] = GOLD[1 if x <= side_split else 0]


def _carve_glow_seam(px, glow, pts, bright=True):
    """Carves a recessed turquoise-quartz mortar seam or rune glyph into sandstone + unlit glow."""
    for i, (x, y) in enumerate(pts):
        ix, iy = int(round(x)), int(round(y))
        if 3 <= ix < S.RW - 3 and 3 <= iy < S.RH - 3:
            hot = bright and (i % 3 == 1)
            px[iy][ix] = TURQ[3 if hot else 2]
            glow[iy][ix] = (*TURQ[3 if hot else 2][:3], 210 if hot else 165)
            # Dark chiseled recess bevel just above/left of the rune
            if px[iy - 1][ix][3] == 255 and px[iy - 1][ix] not in TURQ:
                px[iy - 1][ix] = SANDSTONE[0]


def render_ruin_sandstone(idx: int, stage: int):
    seed = 7400 + idx * 113 + stage * 23
    px = blank(S.RW, S.RH)
    glow = blank(S.RW, S.RH)
    is_sand = [[False] * S.RW for _ in range(S.RH)]

    if stage == 3:
        # Walkable sand-drifted masonry rubble: chiseled stone chunks, gold clasp shard, tiny faint spark
        out = blank(S.RW, S.RH)
        _put_ground_shadow(out, 32.0, 50.0, 17.5, 3.8, S.RW, S.RH)
        _draw_sand_drift(px, is_sand, 32.0, 49.8, 17.5, 3.6, S.RW, S.RH, seed)
        chunks = [
            (21, 46, 28, 50, 2, 25, None),
            (31, 47, 39, 51, 2, 35, 49),
            (41, 46, 46, 50, 1, 43, None),
        ]
        for x0, y0, x1, y1, td, sp, gb in chunks:
            _draw_ashlar_box(px, is_sand, x0, y0, x1, y1, td, sp, seed + x0, gold_band_y=gb)
        # Tiny residual turquoise quartz glint on central fragment
        px[49][34] = TURQ[2]
        glow[49][34] = (*TURQ[2][:3], 75)
        outlined = _selective_outline(px, is_sand, S.RW, S.RH, foot_cut_y=48)
        for y in range(S.RH):
            for x in range(S.RW):
                if outlined[y][x][3] == 255:
                    out[y][x] = outlined[y][x]
        return out, glow

    h_drop = (0, 6, 14)[stage]
    out = blank(S.RW, S.RH)
    _put_ground_shadow(out, 33.0, 50.2, 20.0 - stage * 1.5, 4.2, S.RW, S.RH)

    # Base drifted sand collar around all masonry variants
    _draw_sand_drift(px, is_sand, 32.0, 49.6, 19.5 - stage * 1.4, 3.9, S.RW, S.RH, seed)

    if idx == 0:
        # Variant 0: Overhanging T-shaped carved temple cornice capital with dentil reliefs & gold trim!
        top_y = 17 + h_drop
        _draw_ashlar_box(px, is_sand, 19, top_y + 8, 45, 49, 3, 33, seed, gold_band_y=top_y + 15 if stage < 2 else None)
        if stage < 2:
            # Wide overhanging cornice crown + carved dentil teeth underneath!
            _draw_ashlar_box(px, is_sand, 13 if stage == 0 else 16, top_y, 50 if stage == 0 else 44, top_y + 9, 4, 33, seed + 7, gold_band_y=top_y + 5)
            for dx_d in range(16, 46 if stage == 0 else 41, 4):
                px[top_y + 9][dx_d] = GOLD[2 if dx_d < 33 else 1]
                px[top_y + 10][dx_d] = SANDSTONE[0]
        # Weathered diagonal corner fracture in stages 1..2
        if stage >= 1:
            for y in range(top_y, top_y + 7):
                for x in range(39, 51):
                    if (x - 39) + (top_y + 7 - y) > 5:
                        px[y][x] = CLEAR
        ry = min(44, top_y + 20)
        rune = [(x, ry) for x in range(22, 31)] + [(26, ry - 2), (26, ry - 1), (26, ry + 1), (26, ry + 2), (24, ry - 1), (28, ry - 1)]
        if stage < 2:
            rune += [(x, top_y + 7) for x in range(21, 31)]
        _carve_glow_seam(px, glow, rune)

    elif idx == 1:
        # Variant 1: Tilted cracked fluted sandstone pillar drum half-sunken in sand with gold collar
        top_y = 17 + h_drop
        cx_top, cx_bot = 29.0, 33.5
        rx_d = 12.5 - stage * 0.8
        for y in range(top_y + 4, 50):
            t = (y - (top_y + 4)) / max(1.0, 50 - (top_y + 4))
            cx_y = cx_top * (1.0 - t) + cx_bot * t
            for x in range(int(cx_y - rx_d) - 1, int(cx_y + rx_d) + 2):
                u = (x + 0.5 - cx_y) / rx_d
                if abs(u) <= 1.0:
                    flute = 0.14 * math.cos(u * math.pi * 4.5)
                    lit = 0.54 - 0.42 * u + flute - 0.08 * t
                    c = _stone_shade(lit, x, y, SANDSTONE)
                    if abs(y - (top_y + 11)) <= 1 and stage < 2:
                        c = GOLD[3 if u < -0.2 else (2 if u < 0.35 else 1)]
                    px[y][x] = c
                    is_sand[y][x] = False
        for y in range(top_y, top_y + 8):
            for x in range(int(cx_top - rx_d) - 1, int(cx_top + rx_d) + 2):
                d = ((x + 0.5 - cx_top) / rx_d) ** 2 + ((y + 0.5 - (top_y + 4)) / 3.8) ** 2
                if d <= 1.0:
                    if stage >= 1 and x > cx_top + 4 and y < top_y + 4:
                        continue
                    px[y][x] = SANDSTONE[4 if d > 0.55 and x < cx_top else (3 if d < 0.45 else 2)]
                    is_sand[y][x] = False
        crack = [(int(round(28 + k * 0.35)), top_y + 6 + k) for k in range(min(24, 45 - top_y))]
        if stage == 0:
            crack += [(int(round(cx_top + dx)), top_y + 4) for dx in range( -3, 4)]
        _carve_glow_seam(px, glow, crack)

    elif idx == 2:
        # Variant 2: Fractured tapered obelisk-pedestal cornerstone with protruding QUARTZ_W crystal spire!
        top_y = 20 + h_drop
        for y in range(top_y + 4, 50):
            t = (y - (top_y + 4)) / max(1.0, 50 - (top_y + 4))
            x0 = int(round(18 - 3.5 * t))
            x1 = int(round(45 + 3.5 * t))
            sp = 31
            # Jagged broken upper-right slant
            if y < top_y + 11 and x1 > 38 + (y - top_y):
                x1 = 38 + (y - top_y)
            for x in range(x0, x1 + 1):
                if y in (top_y + 9, top_y + 10) and stage < 2:
                    c = GOLD[3 if x <= sp else 1]
                elif x in (x0, x0 + 1) and y % 6 < 3:
                    c = GOLD[3 if x == x0 else 2]
                else:
                    lit = (0.68 - 0.14 * ((x - x0) / max(1, sp - x0))) if x <= sp else (0.32 - 0.14 * ((x - sp) / max(1, x1 - sp)))
                    c = _stone_shade(lit, x, y, SANDSTONE)
                px[y][x] = c
                is_sand[y][x] = False
        # Top chiseled slant bevel on left half
        for y in range(top_y, top_y + 5):
            for x in range(19 + (top_y + 4 - y), 39):
                px[y][x] = SANDSTONE[4 if x < 31 else 3]
                is_sand[y][x] = False
        # Protruding white QUARTZ_W crystal point erupting out of the fractured right shoulder!
        qy_top = top_y - (4 if stage == 0 else 1)
        for y in range(qy_top, min(46, top_y + 15)):
            qt = (y - qy_top) / max(1.0, min(46, top_y + 15) - qy_top)
            qhw = max(0.8, 4.2 * math.sin(qt * math.pi * 0.78))
            qcx = 39.5 + (1.0 - qt) * 2.2
            for x in range(int(qcx - qhw) - 1, int(qcx + qhw) + 2):
                qv = (x + 0.5 - qcx) / max(qhw, 0.8)
                if abs(qv) <= 1.0:
                    px[y][x] = QUARTZ_W[5 if (qv < -0.25 or y < qy_top + 2) else (4 if qv < 0.2 else 2)]
                    is_sand[y][x] = False
        seam = [(25, y) for y in range(top_y + 12, min(46, top_y + 24))] + [(x, min(44, top_y + 17)) for x in range(22, 29)]
        seam += [(39, top_y + 6), (40, top_y + 5)]
        _carve_glow_seam(px, glow, seam)

    else:
        # Variant 3: Twin stacked rune-carved ashlar blocks with stepped offset & glowing mortar joint
        top_y = 17 + h_drop
        _draw_ashlar_box(px, is_sand, 14, min(34, top_y + 12), 49, 49, 4, 34, seed, gold_band_y=42)
        if stage < 2:
            _draw_ashlar_box(px, is_sand, 18, top_y, 44, top_y + 15, 4, 32, seed + 31, gold_band_y=top_y + 6)
            # Glowing turquoise mortar seam between upper & lower blocks + carved diamond glyph
            seam = [(x, top_y + 15) for x in range(19, 43)]
            cy_r = top_y + 10
            seam += [(25, cy_r - 2), (24, cy_r - 1), (26, cy_r - 1), (25, cy_r)]
        else:
            seam = [(x, min(44, top_y + 18)) for x in range(18, 33)]
        _carve_glow_seam(px, glow, seam)

    # Re-drape tiny sand tongue over very bottom edge (y = 48..51) so stone sits IN the desert sand!
    _draw_sand_drift(px, is_sand, 27.0, 50.2, 11.5, 2.2, S.RW, S.RH, seed + 77)
    _draw_sand_drift(px, is_sand, 38.0, 50.4, 10.5, 2.1, S.RW, S.RH, seed + 91)

    if stage in (1, 2):
        # Small fallen sandstone chip on sand skirt
        _draw_ashlar_box(px, is_sand, 13, 46, 18, 50, 1, 16, seed + 55)

    _add_glow_halo(glow, px, S.RW, S.RH, max_y=48, alpha_scale=0.26)
    outlined = _selective_outline(px, is_sand, S.RW, S.RH, foot_cut_y=47)
    for y in range(S.RH):
        for x in range(S.RW):
            if outlined[y][x][3] == 255:
                out[y][x] = outlined[y][x]
    return out, glow


# ==============================================================================
# 3A. QUARTZ ARCH (assets/props/quartz_arch{,_glow}.png — 3x1 of 96x88, feet (48,82))
# ==============================================================================
AW, AH, AGR = 96, 88, 82


def _draw_arch_pier(px, is_sand, xc: int, y_top: int, y_bot: int, hw: int, seed: int, gold_ys=(), quartz_inlay=False):
    """3/4 sandstone ruin pillar with plinth base, sunlit left/front planes, shaded right thickness wall & gold collars."""
    # Stepped wider stone plinth foot
    for y in range(y_bot - 6, y_bot + 1):
        pw = hw + 2
        sp = xc + 1
        for x in range(xc - pw, xc + pw + 1):
            lit = 0.65 - 0.25 * ((x - (xc - pw)) / max(1, 2 * pw))
            px[y][x] = _stone_shade(lit if x <= sp else lit * 0.55, x, y, SANDSTONE)
            is_sand[y][x] = False

    sp = xc + 1
    for y in range(y_top, y_bot - 5):
        for x in range(xc - hw, xc + hw + 1):
            if quartz_inlay and abs(x - (xc - 1)) <= 1 and (y_top + 5 < y < y_bot - 9):
                px[y][x] = QUARTZ_W[4 if x < xc else 3]
                is_sand[y][x] = False
                continue
            lit = (0.68 - 0.14 * ((x - (xc - hw)) / max(1, hw + 1))) if x <= sp else (0.30 - 0.12 * ((x - sp) / max(1, hw)))
            if (y - y_top) % 8 == 0:
                lit -= 0.14
            c = _stone_shade(lit, x, y, SANDSTONE)
            if x == xc - hw:
                c = SANDSTONE[4]
            elif x == sp:
                c = SANDSTONE[3]
            px[y][x] = c
            is_sand[y][x] = False

    for gy in gold_ys:
        for dy in range(3):
            yy = gy + dy
            if y_top <= yy <= y_bot - 5:
                for x in range(xc - hw - 1, xc + hw + 2):
                    if 3 <= x < AW - 3:
                        px[yy][x] = GOLD[3 if (dy == 0 and x <= sp) else (2 if x <= sp else (1 if dy < 2 else 0))]
                        is_sand[yy][x] = False


def render_quartz_arch(variant: int):
    seed = 8100 + variant * 97
    px = blank(AW, AH)
    glow = blank(AW, AH)
    is_sand = [[False] * AW for _ in range(AH)]
    out = blank(AW, AH)

    # Ground shadows under left & right piers + faint arch bridge shadow
    _put_ground_shadow(out, 24.0, 81.5, 14.5, 3.8, AW, AH)
    _put_ground_shadow(out, 72.0, 81.5, 14.5, 3.8, AW, AH)
    if variant != 1:
        _put_ground_shadow(out, 48.0, 82.0, 22.0, 2.5, AW, AH, tint=(68, 44, 54))

    if variant == 0:
        # Variant 0: Grand weathered sandstone-and-quartz archway (intact curved arch + chipped crown + gold keystone)
        _draw_arch_pier(px, is_sand, 24, 34, 81, 7, seed, gold_ys=(40, 64), quartz_inlay=True)
        _draw_arch_pier(px, is_sand, 72, 34, 81, 7, seed + 19, gold_ys=(40, 64), quartz_inlay=True)

        # Curved semicircular/elliptical stone & QUARTZ_W arch ring spanning x=16..80 over y=8..36
        cx, cy = 48.0, 36.0
        for y in range(7, 38):
            for x in range(15, 82):
                dx = (x + 0.5 - cx) / 31.5
                dy = (y + 0.5 - cy) / 27.5
                if dy > 0.06:
                    continue
                r = math.hypot(dx, dy)
                if 0.60 <= r <= 1.0:
                    # Weathered chipped notch on upper-right arch extrados
                    if 57 <= x <= 64 and y <= 14 and (x - 57) + (15 - y) > 5:
                        continue
                    ang = math.atan2(-dy, dx)
                    voussoir = int(ang / (math.pi / 11.0))
                    is_keystone = abs(x - 48) <= 4
                    lit = 0.78 - 0.35 * ((x - 16) / 64.0) - 0.25 * max(0.0, r - 0.72) * 2.0
                    if r < 0.68:
                        # Underside intrados soffit in cool shadow!
                        c = SANDSTONE[0 if dx < 0.1 else 1]
                    elif is_keystone:
                        c = GOLD[3 if (y < 12 or x < 48) else (2 if x <= 50 else 1)]
                    elif voussoir % 2 == 1 and 0.72 <= r <= 0.92:
                        # Inlaid faceted QUARTZ_W crystal voussoir plates!
                        c = QUARTZ_W[5 if (dx < -0.15 and r > 0.82) else (4 if dx < 0.2 else 2)]
                    else:
                        c = _stone_shade(lit, x, y, SANDSTONE)
                    # Radial mortar joints
                    if abs((ang / (math.pi / 11.0)) - round(ang / (math.pi / 11.0))) < 0.045 and not is_keystone:
                        c = SANDSTONE[1]
                    px[y][x] = c
                    is_sand[y][x] = False

        # Geometric turquoise & sun-gold rune channels up both piers & along the arch ring + keystone diamond!
        for side_x in (23, 71):
            for ry in range(44, 63):
                if ry % 5 != 0:
                    px[ry][side_x] = TURQ[2]
                    glow[ry][side_x] = (*TURQ[2][:3], 185)
        for deg in range(22, 159, 4):
            rad = math.radians(deg)
            rx = int(round(cx + math.cos(rad) * 25.2))
            ry = int(round(cy - math.sin(rad) * 22.0))
            if 45 <= rx <= 51:
                px[ry][rx] = AMBER[3]
                glow[ry][rx] = (*AMBER[3][:3], 225)
            else:
                px[ry][rx] = TURQ[3 if deg > 95 else 2]
                glow[ry][rx] = (*TURQ[3 if deg > 95 else 2][:3], 195)
        for dy in (-2, -1, 0, 1, 2):
            px[14 + dy][48] = AMBER[3]
            glow[14 + dy][48] = (*AMBER[3][:3], 235)

    elif variant == 1:
        # Variant 1: Half-collapsed twin-pillar ruin gate (left pillar + overhanging cantilevered arch, right broken w/ QUARTZ_W spire core!)
        _draw_arch_pier(px, is_sand, 24, 30, 81, 7, seed, gold_ys=(36, 62), quartz_inlay=True)
        _draw_arch_pier(px, is_sand, 72, 54, 81, 7, seed + 29, gold_ys=(66,), quartz_inlay=False)

        # Cantilevered broken left arch overhang (x=15..55, y=10..34) with jagged fracture face
        cx, cy = 48.0, 34.0
        for y in range(9, 35):
            for x in range(15, 56):
                dx = (x + 0.5 - cx) / 31.5
                dy = (y + 0.5 - cy) / 25.0
                r = math.hypot(dx, dy)
                jag = 52 + int(3.0 * math.sin(y * 0.55))
                if 0.58 <= r <= 1.0 and x <= jag and dy <= 0.08:
                    if x >= jag - 2:
                        px[y][x] = QUARTZ_W[4 if y % 2 == 0 else 2]
                    elif r < 0.67:
                        px[y][x] = SANDSTONE[0]
                    elif abs(x - 45) <= 2:
                        px[y][x] = GOLD[2 if x < 45 else 1]
                    else:
                        lit = 0.78 - 0.28 * ((x - 15) / 40.0)
                        px[y][x] = _stone_shade(lit, x, y, SANDSTONE)
                    is_sand[y][x] = False

        # Exposed snow-white QUARTZ_W crystal spire erupting out of the broken right pier shaft!
        for y in range(37, 57):
            t = (57 - y) / 20.0
            hw_q = max(0.8, 4.8 * (1.0 - 0.78 * t))
            qcx = 71.5 + 1.2 * t
            for x in range(int(qcx - hw_q) - 1, int(qcx + hw_q) + 2):
                v = (x + 0.5 - qcx) / max(hw_q, 0.8)
                if abs(v) <= 1.0:
                    qi = 5 if (v < -0.25 or y < 40) else (4 if v < 0.15 else (3 if v < 0.55 else 1))
                    px[y][x] = QUARTZ_W[qi]
                    is_sand[y][x] = False

        # Fallen carved keystone block resting in the sand between the piers
        _draw_ashlar_box(px, is_sand, 52, 72, 62, 80, 3, 57, seed + 41, gold_band_y=76)

        # Glowing rune channels on intact left pier, cantilever & faint pulse in broken right core
        for ry in range(41, 60):
            if ry % 4 != 0:
                px[ry][23] = TURQ[2]
                glow[ry][23] = (*TURQ[2][:3], 185)
        for deg in range(88, 158, 4):
            rad = math.radians(deg)
            rx = int(round(cx + math.cos(rad) * 25.0))
            ry = int(round(cy - math.sin(rad) * 20.0))
            px[ry][rx] = TURQ[3]
            glow[ry][rx] = (*TURQ[3][:3], 195)
        for ry in range(43, 54, 2):
            px[ry][71] = TURQ[3]
            glow[ry][71] = (*TURQ[2][:3], 165)

    else:
        # Variant 2: Ancient curved horseshoe Sun-Portal Arch inlaid with faceted QUARTZ_W plates & gold sun-rays!
        cx, cy = 48.0, 44.0
        # Stepped portal plinth bases at left & right feet (x ~ 18..34 and 62..78, y ~ 72..81)
        _draw_arch_pier(px, is_sand, 25, 68, 81, 8, seed, gold_ys=(71,))
        _draw_arch_pier(px, is_sand, 71, 68, 81, 8, seed + 17, gold_ys=(71,))

        # Sweeping horseshoe sun-ring (y = 7..71)
        for y in range(6, 72):
            for x in range(11, 85):
                dx = (x + 0.5 - cx) / 34.5
                dy = (y + 0.5 - cy) / 35.5
                r = math.hypot(dx, dy)
                # Open bottom portal doorway between the two plinths
                if dy > 0.68 and abs(dx) < 0.56:
                    continue
                if 0.62 <= r <= 0.98 and dy <= 0.78:
                    ang = math.atan2(-dy, dx)
                    seg = int((ang + math.pi) / (math.pi / 10.0))
                    if r < 0.69:
                        c = GOLD[2 if dx < 0 else 1] if seg % 2 == 0 else SANDSTONE[0]
                    elif r > 0.92:
                        c = GOLD[3 if (dx < 0 and dy < 0) else (2 if dx < 0.3 else 1)]
                    elif seg % 2 == 0 and 0.73 <= r <= 0.89:
                        # Faceted snow-white QUARTZ_W sun-plates!
                        c = QUARTZ_W[5 if (dx < -0.1 and dy < 0.1) else (4 if dx < 0.25 else 2)]
                    else:
                        lit = 0.76 - 0.32 * ((x - 12) / 72.0) - 0.18 * ((y - 8) / 62.0)
                        c = _stone_shade(lit, x, y, SANDSTONE)
                    px[y][x] = c
                    is_sand[y][x] = False

        # Ornate gold sun-crest keystone at apex (48, 8..18)
        for dy in range(-4, 6):
            for dx in range(-4, 5):
                if abs(dx) + abs(dy) <= 5:
                    px[11 + dy][48 + dx] = QUARTZ_W[5] if abs(dx) + abs(dy) <= 2 else GOLD[3 if dx <= 0 else 2]
                    is_sand[11 + dy][48 + dx] = False

        # Continuous glowing turquoise-and-gold sun-circuit ring!
        for deg in range(-38, 219, 4):
            rad = math.radians(deg)
            rx = int(round(cx + math.cos(rad) * 27.8))
            ry = int(round(cy - math.sin(rad) * 28.6))
            if 4 <= rx < AW - 4 and 4 <= ry < 72:
                is_card = abs(deg - 90) <= 8 or abs(deg - 15) <= 6 or abs(deg - 165) <= 6
                col_g = AMBER[3] if is_card else TURQ[3 if deg > 70 else 2]
                px[ry][rx] = col_g
                glow[ry][rx] = (*col_g[:3], 220 if is_card else 185)
        glow[11][48] = (*AMBER[3][:3], 245)

    # Drifted golden desert sand mounds embracing both pillar bases (seamless bottom at y=80..83)
    _draw_sand_drift(px, is_sand, 24.0, 80.5, 13.5, 3.2, AW, AH, seed + 51, margin=3)
    _draw_sand_drift(px, is_sand, 72.0, 80.5, 13.5, 3.2, AW, AH, seed + 67, margin=3)

    _add_glow_halo(glow, px, AW, AH, max_y=78, alpha_scale=0.28)
    outlined = _selective_outline(px, is_sand, AW, AH, foot_cut_y=78)
    for y in range(AH):
        for x in range(AW):
            if outlined[y][x][3] == 255:
                out[y][x] = outlined[y][x]
    return out, glow


# ==============================================================================
# 3B. RESONANCE OBELISK (4x1 of 48x72 = 192x72, feet (24, 66))
# ==============================================================================
OW, OH, OGR = 48, 72, 66


def render_resonance_obelisk(variant: int):
    """Cols 0,1: Harmonic Obelisks (calm turquoise-white core).
    Cols 2,3: Overcharged Obelisks (levitating/cracked tip + dramatic violet-amber-turquoise core & crackling seams)."""
    overcharged = variant >= 2
    seed = 8400 + variant * 83
    px = blank(OW, OH)
    glow = blank(OW, OH)
    is_sand = [[False] * OW for _ in range(OH)]
    out = blank(OW, OH)

    _put_ground_shadow(out, 24.5, 65.5, 13.0, 3.5, OW, OH)

    # Stepped carved sandstone pedestal base (y = 55..65)
    _draw_ashlar_box(px, is_sand, 13, 56, 35, 65, 3, 25, seed, gold_band_y=60)

    tilt = (-0.06, 0.07, -0.04, 0.05)[variant]
    lev_gap = 4 if variant == 2 else (3 if variant == 3 else 0)
    y_apex = 7 if not overcharged else 6
    y_shaft_bot = 57

    for y in range(y_apex, y_shaft_bot + 1):
        # Levitation air gap right below the floating pyramidion on overcharged obelisks!
        if overcharged and 22 <= y < 22 + lev_gap:
            # Glowing arcane energy filament bridging the levitation gap!
            for dx, gc, a_v in ((-1, VIOLET[3], 210), (0, AMBER[3], 245), (1, TURQ[3], 210)):
                px[y][24 + dx] = gc
                glow[y][24 + dx] = (*gc[:3], a_v)
            continue

        eff_y = y + (lev_gap if (overcharged and y < 22) else 0)
        t = (y_shaft_bot - eff_y) / max(1.0, y_shaft_bot - (y_apex + lev_gap))
        xc = 24.0 + (y_shaft_bot - y) * tilt
        if y < y_apex + 11:
            # Sharp 3D pyramidion tip!
            pt = (y - y_apex) / 11.0
            hw = max(0.6, 5.4 * pt)
        else:
            hw = 7.4 * (1.0 - 0.28 * t)

        sp = xc + 0.6
        for x in range(max(4, int(xc - hw) - 1), min(OW - 4, int(xc + hw) + 2)):
            if abs(x + 0.5 - xc) > hw + 0.2:
                continue
            rel = (x + 0.5 - xc) / max(hw, 0.8)

            # Central recessed crystal resonance channel (y = 20..52)
            in_core = (y >= y_apex + 12 and y <= 51 and abs(x + 0.5 - xc) <= (1.65 if overcharged else 1.25))
            if in_core:
                if not overcharged:
                    hot = abs(x + 0.5 - xc) < 0.65 or y % 5 == 0
                    c = TURQ[3] if hot else TURQ[2]
                    px[y][x] = c
                    glow[y][x] = (*c[:3], 225 if hot else 175)
                else:
                    # Dramatic violet-amber-turquoise overcharged prism core!
                    band = ((y + variant * 3) // 3) % 3
                    c = AMBER[3] if band == 0 else (VIOLET[3] if band == 1 else TURQ[3])
                    px[y][x] = c
                    glow[y][x] = (*c[:3], 235)
                is_sand[y][x] = False
                continue

            # Tarnished gold collar rings
            if y in (18, 19, 36, 37, 52, 53) and not (overcharged and 20 <= y <= 26):
                px[y][x] = GOLD[3 if rel < -0.15 else (2 if rel < 0.35 else 1)]
                is_sand[y][x] = False
                continue

            # Pyramidion & upper quartz-clad faces vs lower carved sandstone shaft
            use_quartz = (y < y_apex + 11) or (variant in (1, 3) and y < 36)
            if use_quartz:
                if y < y_apex + 3:
                    c = GOLD[3] if variant in (0, 1) else QUARTZ_W[5]
                else:
                    qi = 5 if rel < -0.45 else (4 if rel < 0.10 else (3 if rel < 0.45 else 1))
                    c = QUARTZ_W[qi]
            else:
                lit = (0.72 - 0.18 * (rel + 1.0)) if (x + 0.5 <= sp) else (0.30 - 0.14 * rel)
                c = _stone_shade(lit, x, y, SANDSTONE)
            px[y][x] = c
            is_sand[y][x] = False

    # Overcharged crackling diagonal rune seams & floating side crystal splinters (Cols 2 & 3)!
    if overcharged:
        crack_pts = [
            (21, 29), (22, 30), (20, 31), (26, 33), (27, 34), (28, 35),
            (21, 41), (20, 42), (26, 45), (27, 46), (28, 47),
        ]
        for i, (cx_p, cy_p) in enumerate(crack_pts):
            gc = VIOLET[3] if i % 2 == 0 else AMBER[3]
            px[cy_p][cx_p] = gc
            glow[cy_p][cx_p] = (*gc[:3], 215)
        # Small levitating prism splinters flanking the overcharged obelisk!
        spl = [(11, 22, VIOLET[3]), (36, 20, TURQ[3])] if variant == 2 else [(10, 18, AMBER[3]), (37, 24, VIOLET[3]), (11, 34, TURQ[3])]
        for sx, sy, sc in spl:
            px[sy][sx] = QUARTZ_W[5]
            px[sy + 1][sx] = sc
            is_sand[sy][sx] = False
            is_sand[sy + 1][sx] = False
            glow[sy][sx] = (*sc[:3], 220)
            glow[sy + 1][sx] = (*sc[:3], 185)
    else:
        # Serene harmonic side-rune pips on Cols 0 & 1
        for ry in (26, 31, 42, 47):
            for sx in (21, 27):
                px[ry][sx] = TURQ[2]
                glow[ry][sx] = (*TURQ[2][:3], 170)

    # Drifted golden sand skirt at base (y = 62..67)
    _draw_sand_drift(px, is_sand, 24.0, 64.8, 12.8, 2.8, OW, OH, seed + 41)

    _add_glow_halo(glow, px, OW, OH, max_y=63, alpha_scale=0.30)
    outlined = _selective_outline(px, is_sand, OW, OH, foot_cut_y=62)
    for y in range(OH):
        for x in range(OW):
            if outlined[y][x][3] == 255:
                out[y][x] = outlined[y][x]
    return out, glow


# ==============================================================================
# 3C. LIGHT CONDUIT (4x1 of 32x24 = 128x24, center (16, 12))
# ==============================================================================
LCW, LCH = 32, 24


def render_light_conduit(variant: int):
    """Flat sunken sandstone floor channels half-drifted with sand + 2px luminous turquoise-gold QUARTZ_W core!
    Col 0: E-W horizontal, Col 1: N-S vertical, Col 2: NW-SE diagonal, Col 3: Octagonal junction hub."""
    seed = 8700 + variant * 61
    px = blank(LCW, LCH)
    glow = blank(LCW, LCH)
    is_sand = [[False] * LCW for _ in range(LCH)]

    if variant == 0:
        # Col 0: Horizontal E-W chiseled sandstone gutter (x=2..29, y=6..17), 2px QUARTZ_W strip at y=11..12
        for y in range(6, 18):
            for x in range(2, 30):
                if (x in (2, 29)) and (y in (6, 17)):
                    continue
                if y in (6, 7):
                    c = SANDSTONE[4 if y == 6 else 3]
                elif y in (8, 9):
                    c = SANDSTONE[1]  # inner recessed shadow wall above channel!
                elif y in (10, 13):
                    c = GOLD[2 if x % 8 in (4, 5) else 1] if x % 8 in (4, 5) else SANDSTONE[0]
                elif y in (11, 12):
                    c = QUARTZ_W[5 if y == 11 else 3]
                    gc = AMBER[3] if x in (8, 16, 24) else TURQ[3 if y == 11 else 2]
                    glow[y][x] = (*gc[:3], 225 if y == 11 else 190)
                elif y in (14, 15):
                    c = SANDSTONE[3 if y == 14 else 2]
                else:
                    c = SANDSTONE[1 if y == 16 else 0]
                if x in (5, 6, 25, 26) and y in (7, 8, 14, 15):
                    c = GOLD[3 if y < 11 else 2]
                px[y][x] = c
        _draw_sand_drift(px, is_sand, 7.0, 6.8, 4.5, 2.0, LCW, LCH, seed, margin=1)
        _draw_sand_drift(px, is_sand, 24.5, 16.8, 5.0, 2.1, LCW, LCH, seed + 19, margin=1)

    elif variant == 1:
        # Col 1: Vertical N-S chiseled sandstone gutter (x=9..22, y=2..21), 2px QUARTZ_W strip at x=15..16
        for y in range(2, 22):
            for x in range(9, 23):
                if (y in (2, 21)) and (x in (9, 22)):
                    continue
                if x in (9, 10):
                    c = SANDSTONE[4 if x == 9 else 3]
                elif x in (11, 12):
                    c = SANDSTONE[2]
                elif x in (13, 14):
                    c = GOLD[2] if y in (6, 7, 15, 16) else SANDSTONE[0]
                elif x in (15, 16):
                    c = QUARTZ_W[5 if x == 15 else 3]
                    gc = AMBER[3] if y in (6, 12, 18) else TURQ[3 if x == 15 else 2]
                    glow[y][x] = (*gc[:3], 225 if x == 15 else 190)
                elif x == 17:
                    c = GOLD[1] if y in (6, 7, 15, 16) else SANDSTONE[1]
                elif x in (18, 19, 20):
                    c = SANDSTONE[3 if x == 18 else 2]
                else:
                    c = SANDSTONE[1 if x == 21 else 0]
                px[y][x] = c
        _draw_sand_drift(px, is_sand, 9.5, 16.5, 3.5, 3.2, LCW, LCH, seed + 7, margin=1)
        _draw_sand_drift(px, is_sand, 22.0, 7.5, 3.5, 3.0, LCW, LCH, seed + 23, margin=1)

    elif variant == 2:
        # Col 2: Diagonal NW-SE sunken rune stone channel ((5, 4) -> (26, 19))
        ax, ay = 5.0, 4.0
        bx, by = 26.0, 19.0
        vx, vy = bx - ax, by - ay
        ln2 = vx * vx + vy * vy
        ln = math.sqrt(ln2)
        nx, ny = -vy / ln, vx / ln
        for y in range(2, LCH - 2):
            for x in range(2, LCW - 2):
                dx, dy = x + 0.5 - ax, y + 0.5 - ay
                u = (dx * vx + dy * vy) / ln2
                if u < -0.04 or u > 1.04:
                    continue
                sd = dx * nx + dy * ny
                if abs(sd) <= 5.4:
                    if abs(sd) <= 1.15 and 0.0 <= u <= 1.0:
                        px[y][x] = QUARTZ_W[5 if sd < 0 else 3]
                        hot = abs((u * 3.0) - round(u * 3.0)) < 0.14
                        gc = AMBER[3] if hot else TURQ[3 if sd < 0 else 2]
                        glow[y][x] = (*gc[:3], 225 if hot else 190)
                    elif abs(sd) <= 2.15:
                        px[y][x] = GOLD[2] if abs(u - 0.5) < 0.10 else SANDSTONE[0]
                    elif sd < -2.15:
                        px[y][x] = SANDSTONE[1 if sd > -3.4 else 3]
                    else:
                        px[y][x] = SANDSTONE[4 if sd < 3.6 else (2 if sd < 4.6 else 0)]
        _draw_sand_drift(px, is_sand, 9.0, 15.0, 4.2, 2.2, LCW, LCH, seed + 11, margin=1)
        _draw_sand_drift(px, is_sand, 22.5, 8.5, 4.2, 2.2, LCW, LCH, seed + 31, margin=1)

    else:
        # Col 3: Octagonal conduit junction hub stone centered at (16, 12) with 4 cardinal ports & central prism lens!
        cx, cy = 16.0, 12.0
        for y in range(2, LCH - 2):
            for x in range(3, LCW - 3):
                dx = (x + 0.5 - cx) / 11.5
                dy = (y + 0.5 - cy) / 9.2
                oct_d = max(abs(dx), abs(dy), (abs(dx) + abs(dy)) * 0.73)
                if oct_d <= 1.0:
                    in_cross = (abs(y + 0.5 - cy) <= 1.1 and abs(dx) <= 0.96) or (abs(x + 0.5 - cx) <= 1.1 and abs(dy) <= 0.96)
                    r_c = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 1.15)
                    if r_c <= 2.9:
                        px[y][x] = QUARTZ_W[5 if (dx + dy < 0) else 3]
                        gc = AMBER[3] if r_c <= 1.5 else TURQ[3]
                        glow[y][x] = (*gc[:3], 240 if r_c <= 1.5 else 205)
                    elif r_c <= 4.3:
                        px[y][x] = GOLD[3 if (dx + dy < -0.1) else (2 if dx < 0.2 else 1)]
                    elif in_cross:
                        px[y][x] = QUARTZ_W[4]
                        glow[y][x] = (*TURQ[2][:3], 195)
                    elif oct_d > 0.86:
                        px[y][x] = SANDSTONE[4 if (dx + dy < -0.15) else (1 if dx + dy > 0.25 else 2)]
                    else:
                        lit = 0.66 - 0.26 * dx - 0.24 * dy
                        px[y][x] = _stone_shade(lit, x, y, SANDSTONE)
        _draw_sand_drift(px, is_sand, 7.0, 17.5, 4.0, 1.9, LCW, LCH, seed + 43, margin=1)
        _draw_sand_drift(px, is_sand, 25.0, 6.5, 3.8, 1.8, LCW, LCH, seed + 59, margin=1)

    _add_glow_halo(glow, px, LCW, LCH, max_y=LCH - 1, alpha_scale=0.25)
    # Soft selective contour around stone rims (skipping sand drifts so conduits sit flush in ground sand!)
    return _selective_outline(px, is_sand, LCW, LCH, foot_cut_y=16), glow


# ==============================================================================
# 3D. QUARTZ SEAL (2x1 of 64x64 = 128x64, center (32, 32))
# ==============================================================================
QSW, QSH = 64, 64


def render_quartz_seal(variant: int):
    """Flat circular ancient floor seal centered at (32, 32), half-rimmed by drifted golden sand.
    Col 0: Concentric sun-compass seal with 4 cardinal gold rune sockets.
    Col 1: Star-prism seal plate with interlocking geometric quartz triangles & gold inlay."""
    seed = 9100 + variant * 101
    px = blank(QSW, QSH)
    glow = blank(QSW, QSH)
    is_sand = [[False] * QSW for _ in range(QSH)]

    cx, cy = 32.0, 32.0
    R_max = 26.5

    for y in range(4, QSH - 4):
        for x in range(4, QSW - 4):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            r = math.hypot(dx, dy)
            if r > R_max:
                continue
            ang = math.atan2(dy, dx)
            lit_base = 0.64 - 0.22 * (dx / R_max) - 0.22 * (dy / R_max)

            if variant == 0:
                # Col 0: Concentric Sun-Compass Seal + 4 Cardinal Gold Rune Sockets
                is_card = min(abs(dx), abs(dy)) <= 1.35 and 12.5 <= r <= 23.5
                is_diag_ray = abs(abs(dx) - abs(dy)) <= 1.05 and 8.5 <= r <= 18.5
                if r >= 24.2:
                    c = SANDSTONE[4 if (dx + dy < -6) else (0 if (dx + dy > 8) else 2)]
                elif 21.8 <= r <= 23.2:
                    # Outer glowing turquoise-gold sun-ring channel!
                    c = TURQ[3 if (dx + dy < 0) else 2]
                    glow[y][x] = (*c[:3], 195)
                elif is_card and 16.5 <= r <= 21.5:
                    # 4 Cardinal tarnished GOLD rune sockets with glowing amber-turquoise cores!
                    sock_core = min(abs(dx), abs(dy)) <= 0.6 and 18.0 <= r <= 20.2
                    if sock_core:
                        c = AMBER[3]
                        glow[y][x] = (*AMBER[3][:3], 240)
                    else:
                        c = GOLD[3 if (dx + dy < 0) else 2]
                elif 13.2 <= r <= 15.6:
                    # Faceted QUARTZ_W compass ring
                    seg = int((ang + math.pi) / (math.pi / 8.0))
                    c = GOLD[2] if seg % 2 == 0 and r > 14.6 else QUARTZ_W[5 if (dx + dy < -4) else (4 if dx + dy < 4 else 2)]
                elif 11.4 <= r < 13.2:
                    c = TURQ[2]
                    glow[y][x] = (*TURQ[2][:3], 180)
                elif r <= 5.2:
                    # Central blazing sun-quartz compass medallion!
                    if r <= 2.3:
                        c = AMBER[3]
                        glow[y][x] = (*AMBER[3][:3], 245)
                    elif r <= 3.8:
                        c = GOLD[3 if dx + dy < 0 else 2]
                    else:
                        c = QUARTZ_W[5]
                        glow[y][x] = (*TURQ[3][:3], 200)
                elif is_diag_ray or is_card:
                    c = GOLD[2 if dx + dy < 0 else 1]
                else:
                    # Radial ashlar stone paving joints
                    seg_a = abs((ang / (math.pi / 6.0)) - round(ang / (math.pi / 6.0)))
                    c = SANDSTONE[0] if seg_a < 0.04 else _stone_shade(lit_base, x, y, SANDSTONE)
                px[y][x] = c

            else:
                # Col 1: Star-Prism Seal Plate (interlocking 6-pointed hexagram of QUARTZ_W triangles + violet-gold-turq runes!)
                # Signed distances to two equilateral triangles (radius ~ 21)
                def tri_ring(rot_off: float) -> float:
                    vals = []
                    for k in range(3):
                        a_k = rot_off + k * (math.tau / 3.0)
                        vals.append(dx * math.cos(a_k) + dy * math.sin(a_k))
                    d_tri = max(vals)  # inside triangle when d_tri <= 10.5
                    return abs(d_tri - 10.2) if d_tri <= 11.4 else 99.0

                t1 = tri_ring(-math.pi / 2.0)
                t2 = tri_ring(math.pi / 2.0)
                on_star = min(t1, t2) <= 1.45 and r <= 22.8
                on_star_gold = (1.45 < min(t1, t2) <= 2.35) and r <= 23.2

                if r >= 24.2:
                    c = SANDSTONE[4 if (dx + dy < -6) else (0 if (dx + dy > 8) else 2)]
                elif 22.4 <= r < 24.2:
                    c = GOLD[2 if dx + dy < 0 else 1]
                elif 20.8 <= r < 22.4:
                    c = VIOLET[3] if int((ang + math.pi) * 6 / math.pi) % 2 == 0 else TURQ[2]
                    glow[y][x] = (*c[:3], 185)
                elif r <= 4.8:
                    # Central prismatic star core!
                    if r <= 2.2:
                        c = VIOLET[3]
                        glow[y][x] = (*VIOLET[3][:3], 245)
                    elif r <= 3.6:
                        c = AMBER[3]
                        glow[y][x] = (*AMBER[3][:3], 220)
                    else:
                        c = QUARTZ_W[5]
                elif on_star:
                    # Interlocking geometric QUARTZ_W crystal star bars with glowing prism center vein!
                    if min(t1, t2) <= 0.58:
                        c = TURQ[3] if t1 < t2 else VIOLET[3]
                        glow[y][x] = (*c[:3], 215)
                    else:
                        c = QUARTZ_W[5 if (dx + dy < -2) else 3]
                elif on_star_gold:
                    c = GOLD[3 if (dx + dy < 0) else 2]
                else:
                    # Recessed inner hexagonal quartz/stone facets
                    c = QUARTZ_W[2 if (dx + dy < 0) else 1] if r < 10.2 else _stone_shade(lit_base * 0.92, x, y, SANDSTONE)
                px[y][x] = c

    # Half-rim the circular floor seal with organic crescent wind-blown desert sand along the outer stone bezel!
    for y in range(3, QSH - 3):
        for x in range(3, QSW - 3):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            # Asymmetric wind-drifted crescent sand encroaching on NW & SE outer rims (sparing cardinal sockets & glow!)
            wave_r = 24.4 + 2.6 * math.sin(ang * 2.0 + (0.6 if variant == 0 else -0.8)) + 1.1 * math.cos(ang * 3.0 + seed)
            if glow[y][x][3] == 0 and wave_r <= r <= R_max + 1.4:
                if math.sin(ang * 2.0 + (0.6 if variant == 0 else -0.8)) < -0.05:
                    lit = 0.62 - 0.24 * (dx / R_max) - 0.24 * (dy / R_max)
                    px[y][x] = _stone_shade(lit, x, y, SAND_DRIFT)
                    is_sand[y][x] = True

    _add_glow_halo(glow, px, QSW, QSH, max_y=QSH - 2, alpha_scale=0.26)
    return _selective_outline(px, is_sand, QSW, QSH, foot_cut_y=48), glow


# ==============================================================================
# 4. VISUAL QA CONTACT SHEET (docs/img/desert_ruins.png — 2x Day + Night + Ellie 'sweat')
# ==============================================================================
def write_qa_preview(
    icons,
    prism_frames,
    sand_frames,
    arch_frames,
    obelisk_frames,
    conduit_frames,
    seal_frames,
    out_path: pathlib.Path,
):
    from PIL import Image

    z = 2
    w = 600
    h1 = 432
    day_bg = hexc("d8a25e")
    quartz_patch = hexc("d6e2f5")
    night_bg = hexc("161c32")

    img = [[day_bg if (y // z) < h1 else night_bg for _ in range(w * z)] for y in range(h1 * 2 * z)]

    def fill_rect_logical(x0: int, y0: int, rw: int, rh: int, col: tuple):
        for y in range(y0 * z, (y0 + rh) * z):
            if 0 <= y < len(img):
                for x in range(x0 * z, (x0 + rw) * z):
                    if 0 <= x < w * z:
                        img[y][x] = col

    def paste(layer, ox: int, oy: int, dim: float = 1.0, k: int = z, additive: bool = False):
        for y, row in enumerate(layer):
            for x, c in enumerate(row):
                if c is None or not c[3]:
                    continue
                a = c[3] / 255.0
                for dy in range(k):
                    for dx in range(k):
                        X, Y = ox * z + x * k + dx, oy * z + y * k + dy
                        if 0 <= X < w * z and 0 <= Y < len(img):
                            b = img[Y][X]
                            if additive:
                                img[Y][X] = tuple(min(255, int(b[i] + c[i] * a)) for i in range(3)) + (255,)
                            else:
                                img[Y][X] = tuple(int(b[i] * (1.0 - a) + c[i] * dim * a) for i in range(3)) + (255,)

    # Load Ellie's standby sheet to showcase her new 4th gesture ('sweat': cols 72..95) in S & SE facings!
    standby_path = ROOT / "characters" / "player_standby.png"
    ellie_sweat_tiles = []
    if standby_path.exists():
        st_im = Image.open(standby_path).convert("RGBA")
        if st_im.width >= 96 * 48:
            for sector in (2, 1):  # S (front) and SE (3/4)
                for f_idx in (0, 5, 9, 11, 14, 18, 22):
                    col = 3 * 24 + f_idx
                    crop = st_im.crop((col * 48, sector * 56, (col + 1) * 48, (sector + 1) * 56))
                    tile = [[crop.getpixel((x, y)) for x in range(48)] for y in range(56)]
                    ellie_sweat_tiles.append((sector, tile))

    for night in (0, 1):
        oy = night * h1
        dim = 0.42 if night else 1.0

        # Ground quartz outcrop patch under prism_vein (top-left) so seamless QUARTZ_W foot is verified!
        if not night:
            fill_rect_logical(6, oy + 6, S.RW * 4 + 4, S.RH * 4 + 4, quartz_patch)

        # 1. Left: prism_vein 4x4 (256x224) | Right: ruin_sandstone 4x4 (256x224)
        for fi, (lit, gl) in enumerate(prism_frames):
            fx = 8 + (fi % 4) * S.RW
            fy = oy + 8 + (fi // 4) * S.RH
            paste(lit, fx, fy, dim)
            if night:
                paste(gl, fx, fy, 1.0, additive=True)

        for fi, (lit, gl) in enumerate(sand_frames):
            fx = 280 + (fi % 4) * S.RW
            fy = oy + 8 + (fi // 4) * S.RH
            paste(lit, fx, fy, dim)
            if night:
                paste(gl, fx, fy, 1.0, additive=True)

        # 2. Middle row (y = oy + 238): quartz_arch 3x1 (288x88) + resonance_obelisk 4x1 (192x72) + 2 icons (2x zoomed)
        ay0 = oy + 238
        for i, (lit, gl) in enumerate(arch_frames):
            paste(lit, 8 + i * AW, ay0, dim)
            if night:
                paste(gl, 8 + i * AW, ay0, 1.0, additive=True)

        for i, (lit, gl) in enumerate(obelisk_frames):
            paste(lit, 304 + i * OW, ay0 + 14, dim)
            if night:
                paste(gl, 304 + i * OW, ay0 + 14, 1.0, additive=True)

        for ii, ic_px in enumerate(icons.values()):
            paste(ic_px, 512 + ii * 40, ay0 + 28, 1.0, k=z * 2)

        # 3. Bottom row (y = oy + 334): quartz_seal 2x1 (128x64) + light_conduit 4x1 (128x24) + Ellie 'sweat' strip!
        by0 = oy + 334
        for i, (lit, gl) in enumerate(seal_frames):
            paste(lit, 8 + i * QSW, by0 + 12, dim)
            if night:
                paste(gl, 8 + i * QSW, by0 + 12, 1.0, additive=True)

        for i, (lit, gl) in enumerate(conduit_frames):
            cx_i = 144 + (i % 2) * (LCW + 6)
            cy_i = by0 + 16 + (i // 2) * (LCH + 8)
            paste(lit, cx_i, cy_i, dim)
            if night:
                paste(gl, cx_i, cy_i, 1.0, additive=True)

        # Ellie 'sweat' frames (S facing on Day half, SE facing on Night half so both facings are showcased!)
        want_sec = 2 if not night else 1
        sec_tiles = [t for sec, t in ellie_sweat_tiles if sec == want_sec]
        for ti, tile in enumerate(sec_tiles):
            paste(tile, 232 + ti * 50, by0 + 20, dim)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(out_path, w * z, len(img), img)
    print(f"Saved QA contact sheet: {out_path} ({w * z}x{len(img)})")


def main():
    props = ROOT / "props"
    items = ROOT / "items"
    props.mkdir(parents=True, exist_ok=True)
    items.mkdir(parents=True, exist_ok=True)

    # 1. Item Icons (16x16)
    icons = {
        "prism_shard": make_icon_prism_shard(),
        "ruin_stone": make_icon_ruin_stone(),
    }
    for name, px in icons.items():
        _verify_sheet(name, [px], 16, 16, margin=1)
        write_png(items / f"{name}.png", 16, 16, px)

    # 2. Mineable Ores (4 cols x 4 rows of 64x56 = 256x224)
    prism_frames = [render_prism_vein(i, st) for st in range(4) for i in range(4)]
    _verify_sheet("prism_vein", [f[0] for f in prism_frames], S.RW, S.RH, margin=2)
    _verify_sheet("prism_vein_glow", [f[1] for f in prism_frames], S.RW, S.RH, margin=1)
    write_png(props / "prism_vein.png", S.RW * 4, S.RH * 4, _sheet_from_grid([f[0] for f in prism_frames], 4, 4, S.RW, S.RH))
    write_png(props / "prism_vein_glow.png", S.RW * 4, S.RH * 4, _sheet_from_grid([f[1] for f in prism_frames], 4, 4, S.RW, S.RH))

    sand_frames = [render_ruin_sandstone(i, st) for st in range(4) for i in range(4)]
    _verify_sheet("ruin_sandstone", [f[0] for f in sand_frames], S.RW, S.RH, margin=2)
    _verify_sheet("ruin_sandstone_glow", [f[1] for f in sand_frames], S.RW, S.RH, margin=1)
    write_png(props / "ruin_sandstone.png", S.RW * 4, S.RH * 4, _sheet_from_grid([f[0] for f in sand_frames], 4, 4, S.RW, S.RH))
    write_png(props / "ruin_sandstone_glow.png", S.RW * 4, S.RH * 4, _sheet_from_grid([f[1] for f in sand_frames], 4, 4, S.RW, S.RH))

    # 3. Active Scattered Ruin Props
    arch_frames = [render_quartz_arch(i) for i in range(3)]
    _verify_sheet("quartz_arch", [f[0] for f in arch_frames], AW, AH, margin=2)
    _verify_sheet("quartz_arch_glow", [f[1] for f in arch_frames], AW, AH, margin=1)
    write_png(props / "quartz_arch.png", AW * 3, AH, _sheet_from_grid([f[0] for f in arch_frames], 3, 1, AW, AH))
    write_png(props / "quartz_arch_glow.png", AW * 3, AH, _sheet_from_grid([f[1] for f in arch_frames], 3, 1, AW, AH))

    obelisk_frames = [render_resonance_obelisk(i) for i in range(4)]
    _verify_sheet("resonance_obelisk", [f[0] for f in obelisk_frames], OW, OH, margin=2)
    _verify_sheet("resonance_obelisk_glow", [f[1] for f in obelisk_frames], OW, OH, margin=1)
    write_png(props / "resonance_obelisk.png", OW * 4, OH, _sheet_from_grid([f[0] for f in obelisk_frames], 4, 1, OW, OH))
    write_png(props / "resonance_obelisk_glow.png", OW * 4, OH, _sheet_from_grid([f[1] for f in obelisk_frames], 4, 1, OW, OH))

    conduit_frames = [render_light_conduit(i) for i in range(4)]
    _verify_sheet("light_conduit", [f[0] for f in conduit_frames], LCW, LCH, margin=1)
    _verify_sheet("light_conduit_glow", [f[1] for f in conduit_frames], LCW, LCH, margin=1)
    write_png(props / "light_conduit.png", LCW * 4, LCH, _sheet_from_grid([f[0] for f in conduit_frames], 4, 1, LCW, LCH))
    write_png(props / "light_conduit_glow.png", LCW * 4, LCH, _sheet_from_grid([f[1] for f in conduit_frames], 4, 1, LCW, LCH))

    seal_frames = [render_quartz_seal(i) for i in range(2)]
    _verify_sheet("quartz_seal", [f[0] for f in seal_frames], QSW, QSH, margin=2)
    _verify_sheet("quartz_seal_glow", [f[1] for f in seal_frames], QSW, QSH, margin=1)
    write_png(props / "quartz_seal.png", QSW * 2, QSH, _sheet_from_grid([f[0] for f in seal_frames], 2, 1, QSW, QSH))
    write_png(props / "quartz_seal_glow.png", QSW * 2, QSH, _sheet_from_grid([f[1] for f in seal_frames], 2, 1, QSW, QSH))

    print("Generated 2 icons + 6 ruin/prism prop & glow sheet pairs cleanly (zero #000000, zero border clipping).")
    write_qa_preview(
        icons,
        prism_frames,
        sand_frames,
        arch_frames,
        obelisk_frames,
        conduit_frames,
        seal_frames,
        ROOT.parent / "docs" / "img" / "desert_ruins.png",
    )


if __name__ == "__main__":
    main()
