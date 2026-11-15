#!/usr/bin/env python3
"""Deterministic procedural pixel-art generator for `Aurelith, Herz des Sonnenquarzes` (`boss_aurelith`) FX.

Outputs (top-left sunlight, 3-6 cel steps + 2D Voronoi rock/crystal grain + 4x4 Bayer dithering,
1px tinted dark outlines — ZERO #000000 anywhere, separate unlit `*_glow.png` pairs):
  1. assets/enemies/aurelith_fx/monolith_pillars{,_glow}.png       (4x2 of 64x84  = 256x168, feet (32, 72))
  2. assets/enemies/aurelith_fx/sintered_plates{,_glow}.png        (4x1 of 80x58  = 320x58,  center (40, 29))
  3. assets/enemies/aurelith_fx/quicksand_vortex{,_glow}.png       (4x1 of 128x92 = 512x92,  center (64, 46))
  4. assets/enemies/aurelith_fx/buried_gauntlet{,_glow}.png        (2x1 of 80x72  = 160x72,  pivot (40, 54))
  5. assets/enemies/aurelith_fx/chain_links{,_glow}.png            (4x1 of 28x28  = 112x28,  center (14, 14))
  6. assets/enemies/aurelith_fx/temple_walls{,_glow}.png           (2x1 of 120x68 = 240x68,  feet (60, 56))
  7. assets/enemies/aurelith_fx/resonance_core{,_glow}.png         (4x2 of 44x48  = 176x96,  center (22, 24))
  8. assets/enemies/aurelith_fx/tsunami_rollers{,_glow}.png        (4x1 of 72x60  = 288x60,  base (36, 48))
  9. assets/enemies/aurelith_fx/slash_and_seams{,_glow}.png        (4x1 of 112x84 = 448x84,  center (56, 42))
 10. assets/enemies/aurelith_fx/prism_spike_and_shards{,_glow}.png (4x2 of 56x64  = 224x128, r0 (28,52), r1 (28,32))
  Visual QA Contact Sheet:
  - docs/img/aurelith_fx_sheet.png (2x nearest-neighbor upscaled Day + Night w/ additive glow)

Usage:
  py -3 tools/art_aurelith_fx.py
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import BAYER, blank, clamp  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402


def ramp(*cols):
    return [hexc(c) for c in cols]


# ==============================================================================
# HARMONIZED SONNENQUARZ-ÖDE & AURELITH PALETTES (STRICTLY ZERO #000000!)
# ==============================================================================
SANDSTONE_INK = hexc("241626")
SANDSTONE = ramp("483038", "785042", "aa7a4e", "d8a868", "f2cf8e")
SAND_DRIFT = ramp("472c38", "6e4934", "9c6c44", "c89658", "e6be78", "f7de9e")

GOLD_INK = hexc("34221e")
GOLD = ramp("6f5020", "b48a38", "e6c468", "fff0b0")

QUARTZ_INK = hexc("282238")
QUARTZ_DEEP = hexc("364262")
QUARTZ_CAV = ramp("1d1530", "2b2044")
QUARTZ_W = ramp("5b698e", "8191b6", "a2b3d4", "bfcde7", "d6e2f5", "ffffff")

TURQ = ramp("2a8c94", "3cc0c6", "78f4e6", "d0fff8")
VIOLET = ramp("34185e", "6636ad", "9468ee", "cbaaff")
AMBER = ramp("9e5418", "dc8428", "ffb84a", "fff0aa")

SQUASH = 0.72


# ==============================================================================
# SHARED VORONOI, BAYER, SHADING, SPIRE & OUTLINE HELPERS
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


def _voronoi_stone(x: int, y: int, lit: float, seed: int, sc: float = 5.4, pal=SANDSTONE, strata: bool = True, scorch: float = 0.0) -> tuple:
    """Chiseled Voronoi rock-block grain + top-left bevels + optional sedimentary strata."""
    edge_px, h1, h2, _ang, ton_tl = _voronoi_grain(x, y, seed, sc=sc)
    val = lit + (h1 - 0.5) * 0.19
    if strata:
        val += 0.07 * math.sin(x * 0.22 + y * 0.78 + (seed % 19))
    if abs(h1 - h2) > 0.13:
        if edge_px < 0.72:
            val -= 0.22
        elif edge_px < 1.38 and ton_tl > 0.06:
            val += 0.16
    if scorch > 0.0:
        # Superheated sandstone picks up dark charred crevices and hot amber-gold rims
        if edge_px < 0.85 and abs(h1 - h2) > 0.16:
            return AMBER[2 if h1 > 0.5 else 1]
        val -= 0.06 * scorch
    return _stone_shade(val, x, y, pal)


def _with_alpha(col: tuple, alpha: int) -> tuple:
    a = int(clamp(alpha, 0, 255))
    if a == 0:
        return CLEAR
    return (col[0], col[1], col[2], a)


def _blend_px(dst: tuple, src: tuple) -> tuple:
    if src is None or src[3] == 0:
        return dst
    if src[3] == 255 or dst is None or dst[3] == 0:
        return src
    sa = src[3] / 255.0
    da = dst[3] / 255.0
    oa = sa + da * (1.0 - sa)
    if oa <= 1e-5:
        return CLEAR
    r = int(clamp((src[0] * sa + dst[0] * da * (1.0 - sa)) / oa, 1, 255))
    g = int(clamp((src[1] * sa + dst[1] * da * (1.0 - sa)) / oa, 1, 255))
    b = int(clamp((src[2] * sa + dst[2] * da * (1.0 - sa)) / oa, 1, 255))
    return (r, g, b, int(clamp(oa * 255.0, 1, 255)))


def _put_ground_shadow(out, cx: float, cy: float, rx: float, ry: float, w: int, h: int, tint=(58, 36, 48), margin: int = 2):
    for y in range(max(margin, int(cy - ry) - 1), min(h - margin, int(cy + ry) + 2)):
        for x in range(max(margin, int(cx - rx) - 1), min(w - margin, int(cx + rx) + 2)):
            d = ((x + 0.5 - cx) / max(rx, 1.0)) ** 2 + ((y + 0.5 - cy) / max(ry, 1.0)) ** 2
            if d <= 1.0:
                alpha = int(clamp((1.0 - d) * 96, 22, 88))
                if out[y][x][3] < alpha:
                    out[y][x] = (*tint, alpha)


def _draw_sand_drift(px, is_sand, cx: float, cy: float, rx: float, ry: float, w: int, h: int, seed: int, margin: int = 2):
    """Wind-rippled desert sand mound/collar that merges seamlessly into desert sand floor (zero bottom outline!)."""
    y0 = max(margin, int(cy - ry) - 1)
    y1 = min(h - 1 - margin, int(cy + ry) + 1)
    x0 = max(margin, int(cx - rx) - 1)
    x1 = min(w - 1 - margin, int(cx + rx) + 1)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x + 0.5 - cx) / max(rx, 1.0)
            ny = (y + 0.5 - cy) / max(ry, 1.0)
            wav = 0.09 * math.sin(x * 0.45 + seed) + 0.05 * math.cos(y * 0.7 - seed)
            d = nx * nx + (ny + wav) ** 2
            if d <= 1.0:
                lit = 0.62 - 0.34 * nx - 0.28 * ny + 0.08 * math.sin((x + y * 2) * 0.55 + seed)
                c = _stone_shade(lit, x, y, SAND_DRIFT)
                if d > 0.82 and ny > 0.15:
                    c = SAND_DRIFT[2 if nx > 0.1 else 3]
                px[y][x] = c
                if is_sand is not None:
                    is_sand[y][x] = True


def _selective_outline(
    px,
    is_sand,
    w: int,
    h: int,
    foot_cut_y: int,
    ink_main=SANDSTONE_INK,
    ink_quartz=QUARTZ_INK,
    ink_gold=GOLD_INK,
    margin: int = 2,
):
    """1px adaptive dark tinted contour; skips drifted sand edges so collars/waves blend seamlessly into sand!"""
    shape = [[px[y][x][3] >= 220 for x in range(w)] for y in range(h)]
    quartz_set = set(QUARTZ_W) | set(TURQ) | set(VIOLET) | {QUARTZ_DEEP}
    gold_set = set(GOLD) | set(AMBER)
    out = [row[:] for row in px]
    for y in range(margin, h - margin):
        for x in range(margin, w - margin):
            if shape[y][x] or px[y][x][3] > 0:
                continue
            nb = []
            sand_nb = 0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and shape[ny][nx]:
                    nb.append(px[ny][nx])
                    if is_sand is not None and is_sand[ny][nx]:
                        sand_nb += 1
            if not nb:
                continue
            if sand_nb == len(nb):
                continue
            if y >= foot_cut_y + 2 and (y - 1 < 0 or not shape[y - 1][x]):
                continue
            if any(c in quartz_set for c in nb):
                out[y][x] = ink_quartz
            elif all(c in gold_set for c in nb):
                out[y][x] = ink_gold
            else:
                out[y][x] = ink_main
    return out


def _add_glow_halo(glow, w: int, h: int, max_y: int = 999, alpha_scale: float = 0.30, margin: int = 2):
    """Adds a crisp 1px unshaded aura around bright glow pixels while strictly respecting cell margin."""
    snap = [row[:] for row in glow]
    y_lim = min(h - margin, max_y)
    for y in range(margin, y_lim):
        for x in range(margin, w - margin):
            c = snap[y][x]
            if c[3] < 130:
                continue
            ha = int(c[3] * alpha_scale)
            if ha < 22:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if margin <= nx < w - margin and margin <= ny < y_lim:
                    if glow[ny][nx][3] < ha:
                        glow[ny][nx] = (c[0], c[1], c[2], ha)


def _prism_spectral_color(q_idx: int, u: float, eff_len: float, v: float, hw_u: float, hue_shift: float, molten: bool = False):
    """Refracts diagonal bands of Turquoise, Arcane Violet, and Sun-Gold across hexagonal QUARTZ_W facets."""
    if molten:
        # Superheated sun-quartz: molten amber/gold/violet heart with blazing white-gold arrises!
        if u < 2.2:
            return (AMBER[2] if q_idx >= 3 else SANDSTONE[1]), (*AMBER[2][:3], 165)
        if q_idx == 5:
            return AMBER[3], (*AMBER[3][:3], 235)
        phase = (u / max(eff_len, 7.0)) * 1.85 + (v / max(hw_u, 1.0)) * 0.32 + hue_shift
        band = phase % 1.0
        if band < 0.42:
            c = AMBER[3] if q_idx >= 4 else (AMBER[2] if q_idx >= 2 else AMBER[0])
            return c, (*AMBER[3 if q_idx >= 3 else 2][:3], 210 if q_idx >= 3 else 145)
        elif band < 0.72:
            c = VIOLET[3] if q_idx >= 4 else (VIOLET[2] if q_idx >= 2 else VIOLET[0])
            return c, (*VIOLET[3 if q_idx >= 3 else 2][:3], 195)
        else:
            c = QUARTZ_W[q_idx] if q_idx >= 3 else GOLD[1]
            return c, (*GOLD[3][:3], 150)

    if u < 2.6:
        return QUARTZ_W[q_idx], None
    if q_idx == 5:
        return QUARTZ_W[5], (235, 252, 255, 185)

    phase = (u / max(eff_len, 8.0)) * 1.65 + (v / max(hw_u, 1.0)) * 0.28 + hue_shift
    band = phase % 1.0
    strength = clamp((u - 2.6) / 4.2, 0.0, 1.0)
    if strength < 0.35:
        return QUARTZ_W[q_idx], None

    if band < 0.34:
        c = TURQ[3] if q_idx >= 4 else (TURQ[2] if q_idx == 3 else (TURQ[1] if q_idx == 2 else TURQ[0]))
        return c, (*TURQ[2][:3], 175 if q_idx >= 3 else 115)
    elif band < 0.64:
        c = VIOLET[3] if q_idx >= 4 else (VIOLET[2] if q_idx in (2, 3) else VIOLET[1])
        return c, (*VIOLET[3 if q_idx >= 3 else 2][:3], 170 if q_idx >= 3 else 110)
    elif band < 0.84:
        if q_idx <= 1:
            return QUARTZ_W[q_idx], (*TURQ[1][:3], 70)
        c = AMBER[3] if q_idx >= 4 else (AMBER[2] if q_idx == 3 else GOLD[2])
        return c, (*AMBER[3 if q_idx >= 4 else 2][:3], 165)
    else:
        return QUARTZ_W[q_idx], (220, 244, 255, 110 if q_idx >= 3 else 60)


def _draw_spire(
    px,
    glow,
    z_buf,
    cid_buf,
    w: int,
    h: int,
    bx: float,
    by: float,
    length: float,
    hw: float,
    angle_deg: float,
    z_depth: float,
    cid: int,
    hue_shift: float,
    seed: int,
    cleave_frac=None,
    notched: bool = False,
    molten: bool = False,
    max_y: int = 999,
    margin: int = 3,
):
    """Generalized 3D hexagonal/cleaved/notched sun-quartz prism renderer for arbitrary canvas sizes."""
    rad = math.radians(angle_deg)
    ax, ay = math.sin(rad), -math.cos(rad)
    nx, ny = math.cos(rad), math.sin(rad)

    eff_len = length if cleave_frac is None else length * cleave_frac
    if eff_len < 3.0:
        return

    asym = (_qhash(cid * 17, seed, seed) - 0.5) * 0.22
    apex_v = asym * hw * 0.60
    h_tip = max(3.0, min(length * 0.36, hw * 2.05))
    l_shaft = max(1.4, length - h_tip)
    cleave_slope = -0.22 if (cid + seed) % 2 == 0 else 0.19

    end_x, end_y = bx + ax * (eff_len + 2.0), by + ay * (eff_len + 2.0)
    pad = hw + 2.5
    min_x = max(margin, int(math.floor(min(bx, end_x) - pad)))
    max_x = min(w - 1 - margin, int(math.ceil(max(bx, end_x) + pad)))
    min_y = max(margin, int(math.floor(min(by, end_y) - pad)))
    lim_y = min(h - 1 - margin, max_y, int(math.ceil(max(by, end_y) + 2.0)))

    for y in range(min_y, lim_y + 1):
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
            # Optional battle-notched chip along one edge
            if notched and abs(u - eff_len * 0.52) < 2.2 and v < -hw_u * 0.25:
                hw_u_left = hw_u * 0.58
            else:
                hw_u_left = hw_u

            s1 = (-0.30 + asym * 0.35) * hw_u
            s2 = (0.34 + asym * 0.35) * hw_u

            q_idx = None
            z_px = z_depth

            if hw < 2.15:
                if u > eff_len:
                    continue
                v_lim = hw_u * max(0.0, (eff_len - u) / max(eff_len * 0.38, 0.8)) if (cleave_frac is None and u > eff_len * 0.62) else hw_u
                if v < -v_lim - 0.15 or v > v_lim + 0.15:
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
                if v < -hw_u_left or v > hw_u:
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
                if u > length:
                    continue
                u_s1 = l_shaft - 0.24 * h_tip
                u_s2 = l_shaft - 0.15 * h_tip
                u_r = l_shaft + 0.04 * h_tip
                if v <= s1:
                    u_sh = l_shaft + (u_s1 - l_shaft) * clamp((v + hw_u_left) / max(s1 + hw_u_left, 0.4), 0.0, 1.0)
                elif v <= s2:
                    u_sh = u_s1 + (u_s2 - u_s1) * clamp((v - s1) / max(s2 - s1, 0.4), 0.0, 1.0)
                else:
                    u_sh = u_s2 + (u_r - u_s2) * clamp((v - s2) / max(hw_u - s2, 0.4), 0.0, 1.0)

                v_min = -hw_u_left if u <= l_shaft else -hw_u_left + (apex_v + hw_u_left) * ((u - l_shaft) / max(length - l_shaft, 0.6))
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
                # Subtle horizontal crystal growth striation every ~6px
                stri = -1 if (int(u) % 6 == 0 and v > s1 and not molten) else 0
                if abs(v - s1) <= 0.56 and u > 1.8:
                    q_idx = 5 if t_sh > 0.16 else 4
                elif v < s1:
                    q_idx = 5 if (v < -hw_u_left + 0.90 and t_sh > 0.28) else (3 if u < 2.0 else 4)
                elif v <= s2:
                    q_idx = max(2, (3 if t_sh > 0.36 else 2) + stri)
                else:
                    q_idx = 0 if (v > hw_u - 0.92 or u < 1.8) else 1
                z_px = z_depth + (0.16 if s1 <= v <= s2 else 0.06)

            if z_buf is None or z_px >= z_buf[y][x]:
                if z_buf is not None:
                    z_buf[y][x] = z_px
                if cid_buf is not None:
                    cid_buf[y][x] = cid
                col_px, glow_px = _prism_spectral_color(q_idx, u, eff_len, v, hw_u, hue_shift, molten=molten)
                px[y][x] = col_px
                if glow is not None:
                    glow[y][x] = glow_px if glow_px is not None else CLEAR


def _carve_spire_creases(px, glow, z_buf, cid_buf, w: int, h: int, molten: bool = False):
    snap_z = [row[:] for row in z_buf]
    snap_id = [row[:] for row in cid_buf]
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            cid = snap_id[y][x]
            if cid <= 1:
                continue
            my_z = snap_z[y][x]
            hits = sum(
                1
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
                if snap_id[y + dy][x + dx] > 1 and snap_id[y + dy][x + dx] != cid and snap_z[y + dy][x + dx] - my_z >= 0.38
            )
            if hits:
                if molten:
                    px[y][x] = AMBER[3] if hits == 1 else VIOLET[2]
                    glow[y][x] = (*AMBER[3][:3], 225)
                else:
                    px[y][x] = QUARTZ_DEEP if hits >= 2 else QUARTZ_W[0]
                    glow[y][x] = CLEAR


def _draw_voronoi_pedestal(
    px,
    is_sand,
    w: int,
    h: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    top_depth: int,
    side_split: int,
    seed: int,
    gold_ys=(),
    taper: float = 0.0,
    scorch: float = 0.0,
):
    """3/4 isometric Voronoi sandstone block/pylon with top bevel, sunlit left plane, shaded right plane & gold collars."""
    for y in range(max(3, y0), min(h - 3, y0 + top_depth + 1)):
        indent = int((y0 + top_depth - y) * 0.65 + abs(taper))
        for x in range(max(3, x0 + indent), min(w - 3, x1 - indent + 1)):
            lit = 0.88 - 0.18 * ((x - x0) / max(1, x1 - x0)) - 0.08 * ((y - y0) / max(1, top_depth))
            px[y][x] = _voronoi_stone(x, y, lit, seed, sc=4.8, scorch=scorch)
            if is_sand is not None:
                is_sand[y][x] = False

    body_h = max(1, y1 - (y0 + top_depth))
    for y in range(max(3, y0 + top_depth + 1), min(h - 3, y1 + 1)):
        vt = (y - (y0 + top_depth)) / body_h
        tap = int(round((1.0 - vt) * taper))
        lx0 = max(3, x0 + tap)
        rx1 = min(w - 4, x1 - tap)
        for x in range(lx0, rx1 + 1):
            if x <= side_split:
                lit = 0.68 - 0.15 * ((x - lx0) / max(1, side_split - lx0)) - 0.14 * vt
            else:
                lit = 0.33 - 0.16 * ((x - side_split) / max(1, rx1 - side_split)) - 0.10 * vt
            c = _voronoi_stone(x, y, lit, seed, sc=5.2, scorch=scorch)
            if y == y0 + top_depth + 1 and x <= side_split:
                c = SANDSTONE[4]
            elif x == side_split:
                c = SANDSTONE[3 if vt < 0.55 else 2]
            px[y][x] = c
            if is_sand is not None:
                is_sand[y][x] = False

    for gy in gold_ys:
        for dy in range(3):
            yy = gy + dy
            if y0 + top_depth < yy <= y1 and 3 <= yy < h - 3:
                vt = (yy - (y0 + top_depth)) / body_h
                tap = int(round((1.0 - vt) * taper))
                lx0 = max(3, x0 + tap - 1)
                rx1 = min(w - 4, x1 - tap + 1)
                for x in range(lx0, rx1 + 1):
                    if dy == 0:
                        px[yy][x] = GOLD[3 if x <= side_split else 2]
                    elif dy == 1:
                        px[yy][x] = GOLD[2 if x <= side_split else 1]
                    else:
                        px[yy][x] = GOLD[1 if x <= side_split else 0]
                    if is_sand is not None:
                        is_sand[yy][x] = False


def _stamp_molten_fissures(px, glow, w: int, h: int, paths, margin: int = 3):
    """Carves spiderwebbing molten amber-gold & violet magma cracks across existing solid stone/crystal pixels."""
    for path_idx, pts in enumerate(paths):
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            steps = max(1, int(math.ceil(math.hypot(bx - ax, by - ay) * 1.6)))
            for s in range(steps + 1):
                t = s / steps
                ix = int(round(ax + (bx - ax) * t))
                iy = int(round(ay + (by - ay) * t))
                if margin <= ix < w - margin and margin <= iy < h - margin:
                    if px[iy][ix][3] >= 200:
                        hot = (s + path_idx) % 4 != 0
                        c = AMBER[3] if (hot and (s % 3 != 0)) else (VIOLET[3] if s % 5 == 0 else AMBER[2])
                        px[iy][ix] = c
                        glow[iy][ix] = (*c[:3], 240 if hot else 195)
                        # Scorched dark rim on upper/left neighbor
                        if iy - 1 >= margin and px[iy - 1][ix][3] >= 200 and glow[iy - 1][ix][3] < 180:
                            px[iy - 1][ix] = SANDSTONE[0]


def _sheet_from_grid(frames, cols: int, rows: int, cw: int, ch: int):
    out = [[CLEAR] * (cw * cols) for _ in range(ch * rows)]
    for idx, fr in enumerate(frames):
        ox = (idx % cols) * cw
        oy = (idx // cols) * ch
        for y in range(ch):
            out[oy + y][ox : ox + cw] = fr[y]
    return out


def _verify_sheet(name: str, frames, cw: int, ch: int, margin: int = 2):
    for i, fr in enumerate(frames):
        xs, ys = [], []
        for y in range(ch):
            for x in range(cw):
                c = fr[y][x]
                if c[3] > 0:
                    assert c[:3] != (0, 0, 0), f"{name}[{i}] has pure #000000 at ({x},{y})!"
                    xs.append(x)
                    ys.append(y)
        assert xs, f"{name}[{i}] is completely empty!"
        assert (
            min(xs) >= margin
            and max(xs) <= cw - 1 - margin
            and min(ys) >= margin
            and max(ys) <= ch - 1 - margin
        ), f"{name}[{i}] clipped border ({cw}x{ch}, margin={margin}): x={min(xs)}..{max(xs)}, y={min(ys)}..{max(ys)}"


# ==============================================================================
# 1. MONOLITH PILLARS (4x2 of 64x84 = 256x168, feet/ground anchor at (32, 72))
# ==============================================================================
MPW, MPH, MP_FY = 64, 84, 72


def render_monolith_pillar(col: int, row: int):
    molten = row == 1
    scorch = 1.0 if molten else 0.0
    seed = 4100 + col * 131 + row * 17
    px = blank(MPW, MPH)
    glow = blank(MPW, MPH)
    is_sand = [[False] * MPW for _ in range(MPH)]
    z_buf = [[-1e9] * MPW for _ in range(MPH)]
    cid_buf = [[0] * MPW for _ in range(MPH)]
    out = blank(MPW, MPH)

    _put_ground_shadow(out, 32.0, MP_FY + 0.5, 22.0, 5.2, MPW, MPH)

    if col == 0:
        # Variant 0: Cathedral Sun-Obelisk — stepped gold-relief sandstone pedestal + sun-disc cartouche + tall hex monarch
        _draw_voronoi_pedestal(px, is_sand, MPW, MPH, 14, 62, 50, 72, 2, 34, seed, gold_ys=(65,), scorch=scorch)
        _draw_voronoi_pedestal(px, is_sand, MPW, MPH, 17, 49, 47, 63, 3, 33, seed + 19, gold_ys=(53,), scorch=scorch)
        for y in range(49, 73):
            for x in range(14, 51):
                if px[y][x][3] > 0:
                    z_buf[y][x] = 3.2

        # Sunken sun-disc cartouche on front-left pedestal face (x=22..30, y=56..64)
        cx_c, cy_c = 26, 60
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                d = math.hypot(dx, dy)
                if d <= 3.3:
                    if d <= 1.4:
                        rc = AMBER[3] if molten else TURQ[3]
                        px[cy_c + dy][cx_c + dx] = rc
                        glow[cy_c + dy][cx_c + dx] = (*rc[:3], 235)
                    elif d <= 2.5:
                        px[cy_c + dy][cx_c + dx] = GOLD[3 if dx + dy <= 0 else 1]
                    else:
                        px[cy_c + dy][cx_c + dx] = SANDSTONE[0]

        # Towering hexagonal central sun-quartz spire + asymmetric cleaved side spurs
        spires = [
            (24.0, 51.0, 27.0, 3.8, -22.0, 2.2, 0.15, 0.72, False),
            (40.0, 51.0, 31.0, 4.1, 19.0, 2.4, 0.52, None, True),
            (31.5, 51.5, 45.0, 5.8, -2.5, 3.5, 0.05, None, False),
            (19.5, 53.0, 15.5, 2.5, -36.0, 3.8, 0.68, None, False),
            (44.0, 53.5, 16.5, 2.7, 33.0, 3.9, 0.34, 0.68, False),
            (33.5, 53.0, 21.0, 3.3, 7.0, 4.2, 0.82, None, False),
        ]
        for si, (bx, by, ln, hw, ang, zv, hs, clv, ntc) in enumerate(spires):
            _draw_spire(
                px, glow, z_buf, cid_buf, MPW, MPH, bx, by, ln, hw, ang, zv, 10 + si, hs,
                seed + si * 29, cleave_frac=clv, notched=ntc, molten=molten, max_y=70,
            )
        _carve_spire_creases(px, glow, z_buf, cid_buf, MPW, MPH, molten=molten)
        _draw_sand_drift(px, is_sand, 32.0, 71.8, 21.5, 4.4, MPW, MPH, seed + 71)

        if molten:
            _stamp_molten_fissures(px, glow, MPW, MPH, [
                [(31, 14), (30, 26), (33, 38), (29, 51), (24, 62), (20, 69)],
                [(33, 32), (39, 41), (42, 55), (45, 67)],
                [(22, 38), (26, 47), (35, 58), (38, 68)],
            ])

    elif col == 1:
        # Variant 1: Split Twin-Crag Monolith — V-shaped twin sun-quartz monarchs (-15° & +17°) + blazing plasma fissure
        # Left & right tilted stratified sandstone slabs split apart
        for side, (cx_b, tilt_s) in enumerate(((21.5, -0.24), (42.5, 0.26))):
            for y in range(51, 73):
                vt = (y - 51) / 22.0
                xc = cx_b + (y - 62) * tilt_s
                hw_s = 8.5 + 2.2 * vt
                for x in range(max(4, int(xc - hw_s)), min(MPW - 4, int(xc + hw_s) + 1)):
                    rel = (x - xc) / max(hw_s, 1.0)
                    lit = (0.72 - 0.22 * rel - 0.12 * vt) if side == 0 else (0.54 - 0.26 * rel - 0.12 * vt)
                    if y in (57, 58):
                        c = GOLD[3 if rel < 0 else 1]
                    else:
                        c = _voronoi_stone(x, y, lit, seed + side * 37, sc=4.6, scorch=scorch)
                    px[y][x] = c
                    is_sand[y][x] = False
                    z_buf[y][x] = 3.6

        # Twin V-monarchs + basal druse needles
        spires = [
            (28.5, 56.0, 46.5, 5.3, -15.0, 2.8, 0.12, None, True),
            (35.5, 55.5, 44.5, 5.1, 17.0, 3.0, 0.48, None, False),
            (21.0, 56.5, 22.0, 3.2, -33.0, 3.4, 0.72, 0.74, False),
            (43.5, 56.5, 20.5, 3.0, 35.0, 3.5, 0.25, None, False),
            (16.5, 61.0, 12.5, 2.0, -48.0, 4.0, 0.55, None, False),
            (47.5, 61.0, 12.0, 2.0, 49.0, 4.1, 0.88, None, False),
            (32.0, 62.0, 16.0, 2.6, 2.0, 4.2, 0.35, None, False),
        ]
        for si, (bx, by, ln, hw, ang, zv, hs, clv, ntc) in enumerate(spires):
            _draw_spire(
                px, glow, z_buf, cid_buf, MPW, MPH, bx, by, ln, hw, ang, zv, 10 + si, hs,
                seed + si * 31, cleave_frac=clv, notched=ntc, molten=molten, max_y=71,
            )
        _carve_spire_creases(px, glow, z_buf, cid_buf, MPW, MPH, molten=molten)

        # Blazing turquoise-gold (or amber-violet molten) plasma fissure crackling up the V-cleft!
        for y in range(25, 66):
            t_f = (y - 25) / 40.0
            fx = 32.0 + 1.6 * math.sin(y * 0.48 + seed)
            hw_f = 0.8 + 1.4 * math.sin(t_f * math.pi)
            for x in range(int(fx - hw_f) - 1, int(fx + hw_f) + 2):
                d_f = abs(x + 0.5 - fx)
                if d_f <= hw_f:
                    core_hot = d_f < 0.75
                    if molten:
                        fc = AMBER[3] if core_hot else (VIOLET[3] if y % 3 == 0 else AMBER[2])
                    else:
                        fc = AMBER[3] if (core_hot and y % 4 == 0) else (TURQ[3] if core_hot else TURQ[2])
                    px[y][x] = fc
                    glow[y][x] = (*fc[:3], 245 if core_hot else 195)
                    is_sand[y][x] = False
            # Horizontal plasma arcs bridging the twin spires!
            if y in (30, 38, 46) and not (y == 30 and not molten):
                span = int(4 + (48 - y) * 0.22)
                for bx_a in range(32 - span, 32 + span + 1):
                    if 6 <= bx_a < MPW - 6 and (bx_a + y) % 2 == 0:
                        ac = AMBER[3] if molten else TURQ[3]
                        px[y][bx_a] = ac
                        glow[y][bx_a] = (*ac[:3], 210)

        _draw_sand_drift(px, is_sand, 24.0, 72.0, 14.5, 4.0, MPW, MPH, seed + 61)
        _draw_sand_drift(px, is_sand, 40.0, 72.0, 14.5, 4.0, MPW, MPH, seed + 83)

        if molten:
            _stamp_molten_fissures(px, glow, MPW, MPH, [
                [(21, 20), (24, 34), (26, 48), (20, 62)],
                [(44, 22), (40, 36), (38, 50), (44, 64)],
            ])

    elif col == 2:
        # Variant 2: Pharaonic Astrolabe Breakwater — broad tapered pylon + angled golden armillary band + cleaved crest
        # Back half of angled golden armillary ring (drawn before pylon)
        cx_a, cy_a, rx_a, ry_a = 32.0, 44.0, 23.5, 8.8
        tilt_rad = math.radians(-19.0)
        ca, sa = math.cos(tilt_rad), math.sin(tilt_rad)
        for y in range(26, 62):
            for x in range(5, MPW - 5):
                dx, dy = x + 0.5 - cx_a, y + 0.5 - cy_a
                ux = (dx * ca + dy * sa) / rx_a
                uy = (-dx * sa + dy * ca) / ry_a
                r = math.hypot(ux, uy)
                if 0.80 <= r <= 1.04 and uy < 0.0:
                    px[y][x] = GOLD[2 if ux < 0 else 0]
                    z_buf[y][x] = 1.2

        # Heavy cleaved-table prism crest + notched shoulder blades at top of pylon
        spires = [
            (32.0, 31.0, 25.5, 6.8, 1.0, 2.5, 0.22, 0.88, False),
            (20.5, 34.0, 21.0, 3.6, -29.0, 2.3, 0.58, None, True),
            (43.5, 34.0, 20.0, 3.5, 28.0, 2.4, 0.08, 0.76, False),
        ]
        for si, (bx, by, ln, hw, ang, zv, hs, clv, ntc) in enumerate(spires):
            _draw_spire(
                px, glow, z_buf, cid_buf, MPW, MPH, bx, by, ln, hw, ang, zv, 10 + si, hs,
                seed + si * 23, cleave_frac=clv, notched=ntc, molten=molten, max_y=68,
            )

        # Broad weathered battered pharaonic sandstone pylon (y=26..72, tapering upward)
        _draw_voronoi_pedestal(
            px, is_sand, MPW, MPH, 13, 25, 51, 72, 4, 34, seed + 11,
            gold_ys=(31, 63), taper=5.0, scorch=scorch,
        )
        for y in range(25, 73):
            for x in range(12, 52):
                if px[y][x][3] > 0 and cid_buf[y][x] == 0:
                    z_buf[y][x] = 3.2

        # Carved sunken hieroglyphic grooves on front-left & right pylon faces
        for gy_h in range(36, 61, 5):
            rc = AMBER[3] if molten else TURQ[3 if gy_h % 10 == 6 else 2]
            for gx_h in (23, 24, 25, 28, 39, 40):
                if gy_h % 10 == 1 and gx_h in (24, 39):
                    continue
                px[gy_h][gx_h] = rc
                glow[gy_h][gx_h] = (*rc[:3], 220)
                px[gy_h - 1][gx_h] = SANDSTONE[0]

        # Front half of angled golden armillary band wrapping in front of the pylon + 1px shadow bevel + degree ticks + cabochon!
        for y in range(26, 63):
            for x in range(4, MPW - 4):
                dx, dy = x + 0.5 - cx_a, y + 0.5 - cy_a
                ux = (dx * ca + dy * sa) / rx_a
                uy = (-dx * sa + dy * ca) / ry_a
                r = math.hypot(ux, uy)
                if 1.06 < r <= 1.15 and uy >= 0.05 and px[y][x][3] >= 200:
                    # Cast crisp 1px dark bevel shadow on the sandstone pylon right below the ring!
                    px[y][x] = SANDSTONE[0]
                elif 0.75 <= r <= 1.06 and uy >= -0.05:
                    ang_ring = math.atan2(uy, ux)
                    tick = int(round(ang_ring * 14.0 / math.pi)) % 2 == 0 and r > 0.94
                    if abs(ux + 0.08) < 0.14 and abs(uy - 0.90) < 0.19:
                        jc = AMBER[3] if molten else TURQ[3]
                        px[y][x] = jc
                        glow[y][x] = (*jc[:3], 245)
                    elif r < 0.81 or r > 1.01:
                        px[y][x] = GOLD_INK if r > 1.01 else GOLD[3 if ux < 0.1 else 2]
                    elif tick:
                        px[y][x] = GOLD[0]
                    else:
                        px[y][x] = GOLD[3 if (ux < -0.15 and r < 0.92) else (2 if ux < 0.35 else 1)]
                    is_sand[y][x] = False

        _draw_sand_drift(px, is_sand, 32.0, 71.8, 22.0, 4.3, MPW, MPH, seed + 97)

        if molten:
            _stamp_molten_fissures(px, glow, MPW, MPH, [
                [(29, 10), (32, 22), (27, 35), (31, 49), (25, 65)],
                [(40, 28), (37, 42), (43, 56), (41, 69)],
            ])

    else:
        # Variant 3: Geode-Maw Fang Pillar — jagged asymmetric Voronoi crag shell ripped open w/ dark amethyst cavity & crystal teeth!
        cx_g = 32.5
        for y in range(8, 73):
            vt = (y - 8) / 64.0
            _, h1_s, _, _, _ = _voronoi_grain(18, y, seed + 5, sc=6.5)
            _, h2_s, _, _, _ = _voronoi_grain(46, y, seed + 19, sc=6.5)
            # Jagged stepped crag silhouette instead of smooth oval!
            crag_l = (15.5 + 3.5 * math.sin(vt * math.pi * 0.92)) + (h1_s - 0.5) * 4.2 - (5.5 * (1.0 - vt * 3.2) if vt < 0.31 else 0.0)
            crag_r = (16.5 + 4.0 * math.sin(vt * math.pi * 0.88)) + (h2_s - 0.5) * 4.4 - (7.0 * (1.0 - vt * 2.8) if vt < 0.35 else 0.0)
            xc = cx_g - 1.6 * math.sin(vt * math.pi * 1.4)
            x_min = max(5, int(round(xc - max(2.5, crag_l))))
            x_max = min(MPW - 6, int(round(xc + max(2.5, crag_r))))
            for x in range(x_min, x_max + 1):
                rel = (x + 0.5 - xc) / max(1.0, (crag_r if x >= xc else crag_l))
                # Irregular ripped-open front concave maw (y=18..64)
                _, hc, _, _, _ = _voronoi_grain(x, y, seed + 71, sc=5.0)
                cav_dx = (x + 0.5 - (xc - 1.0)) / max(1.0, (crag_l + crag_r) * 0.33)
                cav_dy = (y + 0.5 - 42.0) / 22.5
                cav_d = math.hypot(cav_dx, cav_dy) + (hc - 0.5) * 0.18
                if cav_d < 0.80 and 17 <= y <= 65:
                    px[y][x] = QUARTZ_CAV[0] if cav_d < 0.48 else (QUARTZ_CAV[1] if cav_d < 0.66 else VIOLET[0])
                    z_buf[y][x] = 1.5
                elif cav_d < 0.96 and 16 <= y <= 66:
                    if (x + y) % 5 == 0:
                        px[y][x] = GOLD[3 if rel < 0 else 2]
                    else:
                        px[y][x] = VIOLET[2 if rel < -0.1 else 1]
                    z_buf[y][x] = 3.4
                else:
                    lit = 0.76 - 0.38 * rel - 0.14 * vt
                    if y in (59, 60):
                        px[y][x] = GOLD[3 if rel < -0.1 else (2 if rel < 0.35 else 1)]
                    else:
                        px[y][x] = _voronoi_stone(x, y, lit, seed + 43, sc=5.0, scorch=scorch)
                    z_buf[y][x] = 3.5

        # External jagged amethyst-quartz crown & shoulder spurs bursting out of the crag shell!
        outer_spurs = [
            (29.0, 18.0, 12.5, 3.0, -14.0, 3.6, 0.60),
            (35.5, 20.0, 10.5, 2.6, 21.0, 3.6, 0.25),
            (16.5, 39.0, 10.0, 2.3, -42.0, 3.6, 0.75),
        ]
        for oi, (bx, by, ln, hw, ang, zv, hs) in enumerate(outer_spurs):
            _draw_spire(px, glow, z_buf, cid_buf, MPW, MPH, bx, by, ln, hw, ang, zv, 40 + oi, hs, seed + 200 + oi, molten=molten, max_y=70)

        # Golden-turquoise (or molten amber-violet) core veins branching inside the dark geode cavity!
        vein_pts = [
            [(30, 22), (28, 32), (31, 43), (29, 55), (32, 62)],
            [(24, 36), (28, 32), (35, 38), (37, 49)],
            [(25, 48), (31, 43), (36, 54)],
        ]
        for vpath in vein_pts:
            for i in range(len(vpath) - 1):
                ax, ay = vpath[i]
                bx, by = vpath[i + 1]
                st = max(1, int(math.hypot(bx - ax, by - ay) * 1.5))
                for s in range(st + 1):
                    vx = int(round(ax + (bx - ax) * (s / st)))
                    vy = int(round(ay + (by - ay) * (s / st)))
                    vc = AMBER[3] if (molten or s % 4 == 0) else TURQ[3 if s % 2 == 0 else 2]
                    px[vy][vx] = vc
                    glow[vy][vx] = (*vc[:3], 235)

        # Bristling sun-quartz crystal fang teeth jutting inward from the geode jaw & rim!
        fangs = [
            (20.5, 30.0, 13.0, 2.5, 114.0, 3.8, 0.10),
            (19.5, 43.5, 14.0, 2.7, 80.0, 3.9, 0.45),
            (22.0, 56.5, 13.5, 2.6, 50.0, 4.0, 0.75),
            (41.5, 29.5, 12.5, 2.4, -112.0, 3.8, 0.30),
            (42.5, 43.0, 14.0, 2.7, -82.0, 3.9, 0.62),
            (40.0, 56.5, 13.0, 2.5, -48.0, 4.0, 0.18),
            (30.5, 63.0, 15.5, 3.1, 4.0, 4.2, 0.50),
            (31.0, 19.0, 11.5, 2.5, 175.0, 4.1, 0.85),
        ]
        for fi, (bx, by, ln, hw, ang, zv, hs) in enumerate(fangs):
            _draw_spire(
                px, glow, z_buf, cid_buf, MPW, MPH, bx, by, ln, hw, ang, zv, 20 + fi, hs,
                seed + fi * 19, molten=molten, max_y=70,
            )

        _draw_sand_drift(px, is_sand, 32.0, 71.8, 21.5, 4.3, MPW, MPH, seed + 109)

        if molten:
            _stamp_molten_fissures(px, glow, MPW, MPH, [
                [(26, 14), (20, 26), (15, 41), (18, 58), (22, 69)],
                [(39, 17), (45, 30), (47, 47), (43, 66)],
            ])

    _add_glow_halo(glow, MPW, MPH, max_y=76, alpha_scale=0.30)
    outlined = _selective_outline(px, is_sand, MPW, MPH, foot_cut_y=70)
    for y in range(MPH):
        for x in range(MPW):
            if outlined[y][x][3] > 0:
                out[y][x] = _blend_px(out[y][x], outlined[y][x])
    return out, glow


# ==============================================================================
# 2. SINTERED PLATES (4x1 of 80x58 = 320x58, center (40, 29))
# ==============================================================================
SPW, SPH = 80, 58


def render_sintered_plate(variant: int):
    seed = 4600 + variant * 157
    px = blank(SPW, SPH)
    glow = blank(SPW, SPH)
    cx, cy = 40.0, 29.0
    rx_max, ry_max = 34.5, 24.5

    # Variant-specific lobe harmonics + aspect skews so each crust has a completely distinct organic silhouette (ZERO octagons!)
    lobe_cfg = [
        (3, 0.4, 5, -0.7, 0.19, 0.10, 0.0),
        (2, -0.6, 5, 1.2, 0.25, 0.11, 0.22),
        (4, 0.9, 3, -0.3, 0.16, 0.13, -0.15),
        (5, -0.2, 3, 0.8, 0.24, 0.10, 0.08),
    ][variant]
    k1, p1, k2, p2, a1, a2, skew_x = lobe_cfg

    q_mask = [[False] * SPW for _ in range(SPH)]

    for y in range(3, SPH - 3):
        for x in range(3, SPW - 3):
            dy = (y + 0.5 - cy) / ry_max
            dx = (x + 0.5 - cx - dy * skew_x * 14.0) / rx_max
            ang = math.atan2(dy, dx)
            r_raw = math.hypot(dx, dy)
            edge_px, h1, h2, v_ang, ton_tl = _voronoi_grain(x, y * 1.25, seed, sc=5.6)

            mod = 1.0 + a1 * math.sin(ang * k1 + p1) + a2 * math.cos(ang * k2 + p2)
            r_sand = r_raw / max(0.55, mod)
            r_quartz = r_sand + (h1 - 0.5) * 0.14

            if r_sand > 1.02:
                continue

            # Variant 2 has an asymmetric scorched-sand central hollow (broken atoll quartz crust!)
            in_hollow = variant == 2 and math.hypot(dx + 0.08, dy - 0.05) + (h1 - 0.5) * 0.12 < 0.22

            if r_quartz <= 0.74 and not in_hollow:
                q_mask[y][x] = True
                facet_lit = -(math.cos(v_ang) * 0.72 + math.sin(v_ang) * 0.69)
                slope_tl = -0.36 * dx - 0.34 * dy
                q_idx = int(clamp(math.floor(3.15 + facet_lit * 0.95 + slope_tl + _bayer(x, y) * 0.35), 1, 4))
                if abs(h1 - h2) > 0.15:
                    if edge_px < 0.90 and h1 > h2 and ton_tl > 0.04:
                        q_idx = 5
                    elif edge_px < 0.82 and h2 > h1:
                        q_idx = max(0, q_idx - 2)
                px[y][x] = QUARTZ_W[q_idx]
            else:
                rip = 0.09 * math.sin(x * 0.52 + y * 0.35 + seed)
                lit = 0.62 - 0.28 * dx - 0.26 * dy + rip
                if in_hollow or r_quartz < 0.81:
                    c = SANDSTONE[1 if (dx + dy > 0) else 2]
                else:
                    c = _stone_shade(lit, x, y, SAND_DRIFT)
                alpha = 255 if r_sand <= 0.84 else int(clamp((1.02 - r_sand) / 0.18 * 245.0, 0, 245))
                px[y][x] = _with_alpha(c, alpha)

    # Crisp 2px SE shelf thickness bevel on glassy quartz crust
    for y in range(4, SPH - 4):
        for x in range(4, SPW - 4):
            if q_mask[y][x]:
                if not q_mask[y + 1][x] or not q_mask[y][x + 1]:
                    px[y][x] = QUARTZ_W[0] if (x + y >= 68) else QUARTZ_W[1]
                    if y + 1 < SPH - 3 and not q_mask[y + 1][x]:
                        px[y + 1][x] = QUARTZ_DEEP
                elif not q_mask[y - 1][x] or not q_mask[y][x - 1]:
                    px[y][x] = QUARTZ_W[5]

    # Branching golden-turquoise fulgurite lightning veins fused across the crust!
    branch_angles = [
        (-2.55, -0.95, 0.42, 1.95),
        (-2.85, -0.35, 0.28, 2.65, 1.35),
        (-2.15, -0.65, 0.85, 2.25, 3.05),
        (-2.75, -1.45, -0.15, 1.05, 2.15),
    ][variant]
    for bi, bang in enumerate(branch_angles):
        vx = cx + (6.0 * math.cos(bang) if variant == 2 else 0.0)
        vy = cy + (4.5 * math.sin(bang) if variant == 2 else 0.0)
        steps = 22
        for s in range(steps):
            wob = 0.32 * math.sin(s * 0.85 + bi * 2.1 + variant)
            vx += math.cos(bang + wob) * 1.18
            vy += math.sin(bang + wob) * 1.18 * SQUASH
            ix, iy = int(round(vx)), int(round(vy))
            if 4 <= ix < SPW - 4 and 4 <= iy < SPH - 4 and q_mask[iy][ix]:
                hot = s < 7 or s % 4 == 0
                vc = AMBER[3] if (s < 4 or (bi + s) % 5 == 0) else TURQ[3 if hot else 2]
                px[iy][ix] = vc
                glow[iy][ix] = (*vc[:3], 225 if hot else 175)
                if s == 9:
                    fx_b, fy_b = vx, vy
                    f_ang = bang + (0.68 if bi % 2 == 0 else -0.68)
                    for _fs in range(7):
                        fx_b += math.cos(f_ang) * 1.1
                        fy_b += math.sin(f_ang) * 1.1 * SQUASH
                        fix, fiy = int(round(fx_b)), int(round(fy_b))
                        if 4 <= fix < SPW - 4 and 4 <= fiy < SPH - 4 and q_mask[fiy][fix]:
                            px[fiy][fix] = TURQ[2]
                            glow[fiy][fix] = (*TURQ[2][:3], 170)

    # 4 protruding crystal druse buds catching top-left light (with crisp 3D dark base collar so they pop off the shelf!)
    druse_specs = [
        [(26.0, 24.0, 10.2, 2.5, -24.0, 0.12), (52.0, 27.0, 9.5, 2.3, 28.0, 0.50), (35.0, 36.0, 8.8, 2.2, -10.0, 0.82), (44.0, 19.0, 8.5, 2.2, 16.0, 0.34)],
        [(22.0, 28.0, 10.5, 2.5, -32.0, 0.18), (39.0, 25.0, 11.0, 2.6, 8.0, 0.58), (55.0, 31.0, 9.2, 2.3, 34.0, 0.88), (31.0, 36.0, 8.2, 2.1, -18.0, 0.42)],
        [(27.0, 21.0, 9.8, 2.4, -22.0, 0.28), (53.0, 22.0, 10.0, 2.4, 25.0, 0.68), (26.0, 36.0, 9.2, 2.3, -28.0, 0.10), (52.0, 36.0, 9.0, 2.3, 26.0, 0.52)],
        [(24.0, 24.0, 10.2, 2.5, -28.0, 0.40), (40.0, 21.0, 10.8, 2.6, -3.0, 0.12), (55.0, 27.0, 9.6, 2.4, 30.0, 0.62), (37.0, 38.0, 8.5, 2.1, 14.0, 0.84)],
    ][variant]
    z_buf = [[-1e9] * SPW for _ in range(SPH)]
    cid_buf = [[0] * SPW for _ in range(SPH)]
    for di, (bx, by, ln, hw, ang, hs) in enumerate(druse_specs):
        _draw_spire(px, glow, z_buf, cid_buf, SPW, SPH, bx, by, ln, hw, ang, 2.0 + di * 0.1, 10 + di, hs, seed + di * 19, max_y=SPH - 4)
    snap_px = [row[:] for row in px]
    for y in range(3, SPH - 3):
        for x in range(3, SPW - 3):
            if cid_buf[y][x] >= 10:
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if cid_buf[ny][nx] == 0:
                        snap_px[ny][nx] = QUARTZ_DEEP if q_mask[ny][nx] else QUARTZ_INK
    px = snap_px

    _add_glow_halo(glow, SPW, SPH, alpha_scale=0.26)
    return px, glow


# ==============================================================================
# 3. QUICKSAND VORTEX (4x1 of 128x92 = 512x92, center (64, 46))
# ==============================================================================
QVW, QVH = 128, 92


def render_quicksand_vortex(frame: int):
    """4 animated rotation frames (phase shifted 90° per frame) with fixed world top-left sunlight!"""
    px = blank(QVW, QVH)
    glow = blank(QVW, QVH)
    cx, cy = 64.0, 46.0
    rx_max, ry_max = 58.0, 41.8  # 41.8 / 58.0 ~= 0.72 SQUASH, leaves >= 4px margin!
    rot_shift = frame * (math.tau / 4.0)

    for y in range(3, QVH - 3):
        for x in range(3, QVW - 3):
            dx = (x + 0.5 - cx) / rx_max
            dy = (y + 0.5 - cy) / ry_max
            r_base = math.hypot(dx, dy)
            if r_base > 1.03:
                continue

            theta = math.atan2(dy, dx)
            theta_rot = theta - rot_shift
            # Organic rotating outer ripple
            r_norm = r_base / (1.0 + 0.03 * math.sin(theta_rot * 4.0) + 0.02 * math.cos(theta_rot * 3.0))
            if r_norm > 1.0:
                continue

            if r_norm < 0.21:
                # Deep dark plum-violet abyss throat (ZERO #000000!)
                swirl = math.sin(theta_rot * 2.0 + (0.21 - r_norm) * 28.0)
                if r_norm < 0.10:
                    px[y][x] = QUARTZ_CAV[0]
                elif swirl > 0.25:
                    px[y][x] = VIOLET[0]
                else:
                    px[y][x] = SANDSTONE_INK
                continue

            # Funnel slope lighting: inside a pit, NW wall (dx<0, dy<0) faces SE (SHADOWED!),
            # while SE far inner slope (dx>0, dy>0) faces NW directly into top-left sunlight!
            inv_r = 1.0 / max(r_norm, 0.15)
            nx_in, ny_in = dx * inv_r, dy * inv_r
            if r_norm < 0.84:
                slope_sun = 0.50 + 0.36 * (nx_in * 0.70 + ny_in * 0.71)
            else:
                # Outer raised rim curls back to normal convex mound lighting
                rim_t = (r_norm - 0.84) / 0.16
                inward_l = 0.50 + 0.36 * (nx_in * 0.70 + ny_in * 0.71)
                outward_l = 0.56 - 0.28 * (nx_in * 0.70 + ny_in * 0.71)
                slope_sun = inward_l * (1.0 - rim_t) + outward_l * rim_t

            # 4-armed logarithmic spiral sand terraces (rotates cleanly by 90° every frame!)
            spiral_arg = 4.0 * theta_rot + 15.5 * ((1.0 - r_norm) ** 1.18)
            terrace_saw = (spiral_arg / math.tau) % 1.0
            # Crisp terrace step crest + trough shadow
            ridge_bump = 0.18 if terrace_saw < 0.22 else (-0.15 if terrace_saw > 0.82 else (0.06 * math.sin(terrace_saw * math.tau)))
            depth_darken = -0.24 * clamp((0.55 - r_norm) / 0.35, 0.0, 1.0)

            lit = slope_sun + ridge_bump + depth_darken
            if r_norm < 0.31 and lit < 0.28:
                c = SANDSTONE[0] if terrace_saw > 0.5 else SAND_DRIFT[0]
            else:
                c = _stone_shade(lit, x, y, SAND_DRIFT)

            # Soft translucent outer sand rim so it blends seamlessly into desert floor
            alpha = 255 if r_norm <= 0.85 else int(clamp((1.0 - r_norm) / 0.15 * 245.0, 0, 245))
            px[y][x] = _with_alpha(c, alpha)

    # Broken antique-gold pharaonic seal-ring arcs spiraling inward (orbiting 90° per frame!)
    for arc_i, (r_arc, a_start, a_span) in enumerate(((0.66, 0.25, 0.62), (0.48, 2.35, 0.70), (0.35, 4.45, 0.58))):
        steps = 26
        for s in range(steps + 1):
            tf = s / steps
            ang = a_start + rot_shift + tf * a_span
            rr = r_arc - 0.04 * tf
            ax_p = cx + math.cos(ang) * rr * rx_max
            ay_p = cy + math.sin(ang) * rr * ry_max
            for bw in (-1, 0, 1):
                ix = int(round(ax_p + math.cos(ang) * bw))
                iy = int(round(ay_p + math.sin(ang) * bw * SQUASH))
                if 5 <= ix < QVW - 5 and 5 <= iy < QVH - 5:
                    # World-space top-left highlight on gold arc
                    sun_g = (ix - cx) < 0 or (iy - cy) < 0
                    if bw == 0 and s in (6, 13, 20):
                        px[iy][ix] = TURQ[3]
                        glow[iy][ix] = (*TURQ[2][:3], 185)
                    else:
                        px[iy][ix] = GOLD[3 if (bw == -1 and sun_g) else (2 if sun_g else (1 if bw <= 0 else 0))]

    # 3 tumbling half-buried Voronoi sandstone masonry blocks spiraling down the slope!
    for bi, (r_blk, a_blk, bsz) in enumerate(((0.62, 1.35, 4.6), (0.45, 3.65, 4.0), (0.56, 5.15, 4.2))):
        ang = a_blk + rot_shift
        bx = cx + math.cos(ang) * r_blk * rx_max
        by = cy + math.sin(ang) * r_blk * ry_max
        tilt_b = ang + 0.55
        cb, sb = math.cos(tilt_b), math.sin(tilt_b)
        ir = int(bsz + 3)
        for y in range(max(5, int(by) - ir), min(QVH - 5, int(by) + ir + 1)):
            for x in range(max(5, int(bx) - ir), min(QVW - 5, int(bx) + ir + 1)):
                dx, dy = x + 0.5 - bx, (y + 0.5 - by) / 0.85
                ux = dx * cb + dy * sb
                uy = -dx * sb + dy * cb
                if abs(ux) <= bsz and abs(uy) <= bsz * 0.72:
                    # Half-buried lower edge under sand!
                    if dy > bsz * 0.38:
                        px[y][x] = SAND_DRIFT[4 if dx > 0 else 2]
                    elif max(abs(ux) / bsz, abs(uy) / (bsz * 0.72)) > 0.84:
                        px[y][x] = SANDSTONE_INK
                    else:
                        # World top-left lighting!
                        lit = 0.74 - 0.12 * (x - bx) - 0.12 * (y - by)
                        px[y][x] = GOLD[2] if abs(uy) < 0.7 else _voronoi_stone(x, y, lit, 5100 + bi * 29, sc=4.0)

    # Sunken turquoise & solar-gold arcane sparks glinting inside the abyss throat!
    for sp_i, (r_sp, a_sp, is_gold) in enumerate((
        (0.08, 0.4, True), (0.14, 1.9, False), (0.16, 3.5, True), (0.12, 5.0, False), (0.19, 2.7, False)
    )):
        ang = a_sp + rot_shift
        sx = int(round(cx + math.cos(ang) * r_sp * rx_max))
        sy = int(round(cy + math.sin(ang) * r_sp * ry_max))
        sc = AMBER[3] if is_gold else TURQ[3]
        px[sy][sx] = sc
        glow[sy][sx] = (*sc[:3], 235)
        if sp_i < 2:
            px[sy][sx + 1] = TURQ[2] if is_gold else VIOLET[3]
            glow[sy][sx + 1] = (*px[sy][sx + 1][:3], 180)

    _add_glow_halo(glow, QVW, QVH, alpha_scale=0.30)
    return px, glow


# ==============================================================================
# 4. BURIED GAUNTLET (2x1 of 80x72 = 160x72, impact ground pivot at (40, 54))
# ==============================================================================
BGW, BGH, BG_PY = 80, 72, 54


def _draw_rotated_box_2d(px, is_sand, w: int, h: int, cx: float, cy: float, hw: float, hh: float, angle_deg: float, seed: int, gold_trim: bool = False):
    rad = math.radians(angle_deg)
    ca, sa = math.cos(rad), math.sin(rad)
    pad = int(math.hypot(hw, hh) + 2)
    for y in range(max(3, int(cy) - pad), min(h - 3, int(cy) + pad + 1)):
        for x in range(max(3, int(cx) - pad), min(w - 3, int(cx) + pad + 1)):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            ux = dx * ca + dy * sa
            uy = -dx * sa + dy * ca
            if abs(ux) <= hw and abs(uy) <= hh:
                # Top-left world lighting combined with 3D knuckle curvature across ux
                world_tl = -(dx * 0.70 + dy * 0.70) / max(hw + hh, 4.0)
                arch = -0.26 * (ux / max(hw, 1.0))
                lit = 0.58 + world_tl * 0.42 + arch
                if gold_trim and (abs(uy) > hh - 2.1 or abs(ux) > hw - 1.8):
                    c = GOLD[3 if (dx + dy < -2) else (2 if dx < 4 else 1)]
                else:
                    c = _voronoi_stone(x, y, lit, seed, sc=4.8)
                px[y][x] = c
                if is_sand is not None:
                    is_sand[y][x] = False


def render_buried_gauntlet(col: int):
    """Col 0: Anchored Anvil Fist (~52x46 colossal stone-gold-quartz gauntlet slammed knuckles-deep at (40,54)).
    Col 1: Yanking Plough Fist (tilted back ~22° in high-tension drag posture, ploughing sand spray + blazing wrist flare!)."""
    yanking = col == 1
    seed = 5400 + col * 97
    px = blank(BGW, BGH)
    glow = blank(BGW, BGH)
    is_sand = [[False] * BGW for _ in range(BGH)]
    z_buf = [[-1e9] * BGW for _ in range(BGH)]
    cid_buf = [[0] * BGW for _ in range(BGH)]
    out = blank(BGW, BGH)

    _put_ground_shadow(out, 40.0, BG_PY + 2.0, 32.0, 8.0, BGW, BGH)

    # Raised churned sand crater berm around impact pivot (40, 54)
    _draw_sand_drift(px, is_sand, 40.0, 55.0, 31.5, 8.5, BGW, BGH, seed)
    _draw_sand_drift(px, is_sand, 19.5, 53.5, 13.0, 5.5, BGW, BGH, seed + 17)
    _draw_sand_drift(px, is_sand, 60.5, 54.0, 13.0, 5.5, BGW, BGH, seed + 31)
    for y in range(47, 58):
        for x in range(21, 60):
            d = ((x - 40.0) / 18.5) ** 2 + ((y - 52.5) / 5.2) ** 2
            if d <= 1.0:
                px[y][x] = SAND_DRIFT[0 if d < 0.55 else 1]
                is_sand[y][x] = True

    tilt = -22.0 if yanking else 0.0
    rad = math.radians(tilt)
    ca, sa = math.cos(rad), math.sin(rad)
    piv_x, piv_y = (37.5, 37.5) if yanking else (40.5, 38.0)

    def to_local(wx: float, wy: float):
        dx, dy = wx - piv_x, wy - piv_y
        return dx * ca + dy * sa, -dx * sa + dy * ca

    def to_world(lx: float, ly: float):
        return piv_x + lx * ca - ly * sa, piv_y + lx * sa + ly * ca

    # Sculpted gauntlet silhouette in local gauntlet coords (lx, ly) so every armor plate, bevel & finger groove is razor-crisp!
    for y in range(6, 62):
        for x in range(8, BGW - 8):
            lx, ly = to_local(x + 0.5, y + 0.5)
            world_tl = -((x - piv_x) * 0.65 + (y - piv_y) * 0.65) / 28.0

            # A) Forged Golden Wrist Chain-Shackle & Crown (ly in -28..-19)
            if -27.5 <= ly < -18.5:
                hw_w = 8.5 + (ly + 27.5) * 0.45
                if abs(lx) <= hw_w:
                    if ly < -24.5 and abs(lx) <= 4.8:
                        # Sunken dark chain-socket well + glowing anchor core
                        hot = abs(lx) <= 2.2
                        sc = AMBER[3] if (yanking and hot) else (TURQ[3] if hot else QUARTZ_CAV[1])
                        px[y][x] = sc
                        if hot:
                            glow[y][x] = (*sc[:3], 245)
                    elif ly > -20.5:
                        px[y][x] = SANDSTONE_INK  # deep chiseled neck groove under wrist crown
                    else:
                        px[y][x] = GOLD[3 if lx < -1.5 else (2 if lx < 3.5 else 1)]
                    is_sand[y][x] = False
                    continue

            # B) Winged Pharaonic Vambrace Cuff (ly in -18.5..-10.0)
            if -18.5 <= ly < -9.8:
                flare = ( -9.8 - ly) * 0.35
                hw_v = 16.5 + flare
                if abs(lx) <= hw_v:
                    if ly > -11.0:
                        px[y][x] = SANDSTONE_INK  # crisp armor articulation crease!
                    elif abs(lx) > hw_v - 3.2 or ly < -16.6:
                        px[y][x] = GOLD[3 if lx < 0 else (2 if lx < 8 else 1)]
                    elif abs(abs(lx) - 9.5) <= 1.0:
                        px[y][x] = TURQ[3 if abs(ly + 14.2) < 1.5 else 2]
                        glow[y][x] = (*TURQ[2][:3], 205)
                    else:
                        lit = 0.66 + world_tl * 0.32 - 0.22 * (lx / hw_v)
                        px[y][x] = _voronoi_stone(x, y, lit, seed + 19, sc=4.6)
                    is_sand[y][x] = False
                    continue

            # C) Massive Polygonal 3D Dorsal Hand Carapace + Heavy Left Thumb Plate (ly in -9.8..+5.5)
            if -9.8 <= ly <= 5.5:
                # Asymmetric thumb shoulder jutting out on the left (-23.5.. -17.5)
                in_thumb = (-23.5 <= lx < -17.2) and (-4.5 <= ly <= 8.5)
                hw_d = 19.5 - max(0.0, (ly - 1.5) * 0.6)
                if abs(lx) <= hw_d or in_thumb:
                    if in_thumb:
                        if lx > -18.4:
                            px[y][x] = SANDSTONE_INK  # thumb separation crease!
                        elif ly < -2.2 or ly > 6.5:
                            px[y][x] = GOLD[3 if ly < 0 else 2]
                        else:
                            px[y][x] = _voronoi_stone(x, y, 0.76 + world_tl * 0.2, seed + 31, sc=4.2)
                        is_sand[y][x] = False
                        continue

                    # Dorsal Golden Sun-Eye Seal centered at (lx=0, ly=-2.5)!
                    edx, edy = lx * 0.78, (ly + 2.5) * 1.15
                    ed = math.hypot(edx, edy)
                    if ed <= 6.2:
                        if ed <= 2.2:
                            ec = QUARTZ_W[5] if (yanking and ed < 1.2) else TURQ[3]
                            px[y][x] = ec
                            glow[y][x] = (*TURQ[3][:3], 250)
                        elif ed <= 3.6:
                            ec2 = AMBER[3] if yanking else TURQ[2]
                            px[y][x] = ec2
                            glow[y][x] = (*ec2[:3], 210)
                        elif ed <= 5.1:
                            px[y][x] = GOLD[3 if (lx + ly < -2) else 2]
                        else:
                            px[y][x] = SANDSTONE_INK
                    elif abs(lx) > hw_d - 2.2 or ly > 3.8:
                        # Stepped golden knuckle-arch border!
                        px[y][x] = GOLD[3 if lx < -2 else (2 if lx < 6 else 1)]
                    else:
                        # 3-plane 3D faceted carapace (bright left plane, mid center plane, shaded right plane)
                        plane_lit = 0.78 if lx < -6.5 else (0.58 if lx <= 7.0 else 0.34)
                        if abs(lx + 6.5) < 0.7 or abs(lx - 7.0) < 0.7:
                            px[y][x] = GOLD[2 if lx < 0 else 1]
                        else:
                            px[y][x] = _voronoi_stone(x, y, plane_lit + world_tl * 0.18, seed + 37, sc=5.0)
                    is_sand[y][x] = False
                    continue

            # D) 4 Articulated Armored Finger/Knuckle Columns (ly in 5.5..15.5) with crisp dark finger grooves!
            if 5.5 < ly <= (14.5 if not yanking else 16.5) and abs(lx) <= 19.2:
                # Finger centers at lx = -14.2, -4.7, +4.7, +14.2 (width ~ 8.0 each, 1.5px dark gap between fingers!)
                f_idx = min(3, max(0, int(math.floor((lx + 19.0) / 9.5))))
                fcx = -14.25 + f_idx * 9.5
                fd = abs(lx - fcx)
                if fd <= 3.9:
                    if ly < 7.8:
                        # Golden knuckle guard cap on each finger!
                        px[y][x] = GOLD[3 if lx < fcx else (2 if f_idx < 3 else 1)]
                    else:
                        flit = (0.72 if lx < fcx else 0.42) - f_idx * 0.06
                        px[y][x] = _voronoi_stone(x, y, flit, seed + 60 + f_idx * 11, sc=4.0)
                    is_sand[y][x] = False
                elif fd <= 4.8 and ly < 13.5:
                    px[y][x] = SANDSTONE_INK
                    is_sand[y][x] = False

    # 3 Jutting Sun-Quartz Knuckle/Shoulder Spurs + Thumb & Finger Quartz Claws!
    spurs = [
        (-19.5, -10.5, 14.0, 3.0, -52.0 + tilt, 0.12),
        (0.0, -14.5, 11.5, 2.7, -4.0 + tilt, 0.48),
        (19.5, -10.0, 13.5, 2.9, 50.0 + tilt, 0.78),
    ]
    for si, (slx, sly, ln, hw, ang, hs) in enumerate(spurs):
        wx, wy = to_world(slx, sly)
        _draw_spire(px, glow, z_buf, cid_buf, BGW, BGH, wx, wy, ln, hw, ang, 4.0 + si * 0.1, 10 + si, hs, seed + si * 19, max_y=56)

    # Curved snow-quartz claw tips gripping crater rim (or raking forward in col 1!)
    claw_defs = [(-21.0, 6.5, 9.0, 2.4, -155.0), (-14.2, 13.5, 9.5, 2.5, -168.0), (-4.7, 14.0, 10.0, 2.6, 178.0), (4.7, 14.0, 10.0, 2.6, 170.0), (14.2, 13.5, 9.5, 2.5, 158.0)]
    for ci, (clx, cly, cln, chw, cang) in enumerate(claw_defs):
        wx, wy = to_world(clx, cly)
        ang_w = cang + (28.0 if yanking else 0.0)
        _draw_spire(px, glow, z_buf, cid_buf, BGW, BGH, wx, wy, cln, chw, ang_w, 5.0, 30 + ci, ci * 0.22, seed + 90 + ci, max_y=59)
        for y in range(36, 61):
            for x in range(8, BGW - 8):
                if cid_buf[y][x] >= 10:
                    is_sand[y][x] = False

    if not yanking:
        # Anchored Anvil Fist: raised berm of thrown sand & Voronoi rock rubble overlapping buried claw tips!
        _draw_sand_drift(px, is_sand, 25.0, 56.2, 13.5, 3.6, BGW, BGH, seed + 101)
        _draw_sand_drift(px, is_sand, 55.0, 56.5, 13.5, 3.6, BGW, BGH, seed + 113)
        _draw_sand_drift(px, is_sand, 40.0, 57.5, 14.0, 3.2, BGW, BGH, seed + 127)
        _draw_voronoi_pedestal(px, is_sand, BGW, BGH, 10, 50, 17, 56, 2, 14, seed + 131)
        _draw_voronoi_pedestal(px, is_sand, BGW, BGH, 63, 49, 70, 55, 2, 66, seed + 149)
        for cr_pts in ([(30, 55), (23, 58), (18, 60)], [(50, 55), (57, 58), (62, 60)], [(40, 56), (40, 61)]):
            _stamp_molten_fissures(px, glow, BGW, BGH, [cr_pts])
    else:
        # Yanking Plough Fist: wide cohesive ploughed sand bow-wave + dark raked furrow trench + kicking spray plumes!
        _draw_sand_drift(px, is_sand, 45.0, 56.5, 24.5, 5.2, BGW, BGH, seed + 151)
        for fy in range(51, 58):
            for fx in range(28, 56):
                if (fx - 28) % 9 in (2, 3, 4) and fy < 56:
                    px[fy][fx] = SAND_DRIFT[0]
                    is_sand[fy][fx] = True
        spray_blobs = [(16.5, 48.5, 8.5, 5.2), (11.5, 41.5, 5.5, 4.2), (63.5, 50.5, 9.0, 5.5), (68.0, 43.5, 5.5, 4.2)]
        for bi, (sx_b, sy_b, rx_b, ry_b) in enumerate(spray_blobs):
            _draw_sand_drift(px, is_sand, sx_b, sy_b, rx_b, ry_b, BGW, BGH, seed + 160 + bi * 13)
        _draw_voronoi_pedestal(px, is_sand, BGW, BGH, 60, 52, 67, 58, 2, 63, seed + 181)
        for spx, spy in ((9, 36), (14, 33), (66, 36), (71, 38), (55, 61), (25, 60)):
            px[spy][spx] = SAND_DRIFT[5]
            px[spy + 1][spx] = SAND_DRIFT[3]
            is_sand[spy][spx] = True
            is_sand[spy + 1][spx] = True

        # Blazing golden-turquoise wrist-chain socket flare!
        fl_x, fl_y = to_world(0.0, -27.5)
        for ray_a in (-152, -126, -102, -78, -52):
            rr = math.radians(ray_a)
            rlen = 9 if ray_a in (-126, -102, -78) else 6
            for s in range(1, rlen + 1):
                rx_f = int(round(fl_x + math.cos(rr) * s))
                ry_f = int(round(fl_y + math.sin(rr) * s))
                if 3 <= rx_f < BGW - 3 and 3 <= ry_f < BGH - 3:
                    fc = QUARTZ_W[5] if s <= 2 else (AMBER[3] if ray_a % 2 == 0 else TURQ[3])
                    px[ry_f][rx_f] = fc
                    glow[ry_f][rx_f] = (*fc[:3], 245 if s <= 4 else 195)

    _add_glow_halo(glow, BGW, BGH, max_y=65, alpha_scale=0.30)
    outlined = _selective_outline(px, is_sand, BGW, BGH, foot_cut_y=52)
    for y in range(BGH):
        for x in range(BGW):
            if outlined[y][x][3] > 0:
                out[y][x] = _blend_px(out[y][x], outlined[y][x])
    return out, glow


# ==============================================================================
# 5. CHAIN LINKS & GEODE PODS (4x1 of 28x28 = 112x28, center at (14, 14))
# ==============================================================================
CLW, CLH = 28, 28


def render_chain_or_pod(col: int):
    seed = 5800 + col * 73
    px = blank(CLW, CLH)
    glow = blank(CLW, CLH)
    cx, cy = 14.0, 14.0

    if col == 0:
        # Col 0: Carved sandstone & antique-gold chain link (broad face) w/ glowing turquoise rune-core
        for y in range(6, 22):
            for x in range(4, 24):
                dx = (x + 0.5 - cx) / 9.6
                dy = (y + 0.5 - cy) / 7.2
                r_out = math.hypot(max(0.0, abs(dx) - 0.35), dy)
                if r_out > 0.72:
                    continue
                in_hole = abs(dx) < 0.48 and abs(dy) < 0.34 and abs(x + 0.5 - cx) > 1.4
                if in_hole:
                    continue
                # Central glowing turquoise rune-core bridge at x ~ 13..14!
                if abs(x + 0.5 - cx) <= 1.4 and abs(dy) <= 0.45:
                    hot = abs(y + 0.5 - cy) < 1.5
                    c = TURQ[3 if hot else 2]
                    px[y][x] = c
                    glow[y][x] = (*c[:3], 235 if hot else 185)
                elif abs(dx) > 0.62:
                    # Stepped antique-gold end-clasps!
                    px[y][x] = GOLD[3 if (dx + dy < -0.2) else (2 if dy < 0.2 else 1)]
                else:
                    lit = 0.72 - 0.26 * dx - 0.28 * dy
                    px[y][x] = _voronoi_stone(x, y, lit, seed, sc=3.8)
        out = _selective_outline(px, None, CLW, CLH, foot_cut_y=99)

    elif col == 1:
        # Col 1: Edge-on / 45° interlocking profile w/ golden-violet spark
        for y in range(8, 20):
            for x in range(4, 24):
                dx = (x + 0.5 - cx) / 9.4
                dy = (y + 0.5 - cy) / 4.6
                d = abs(dx) * 0.55 + dy * dy * 0.75
                if abs(dx) > 0.98 or abs(dy) > 0.98 or d > 0.96:
                    continue
                r_pin = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if r_pin <= 2.3:
                    c = AMBER[3] if r_pin <= 1.2 else VIOLET[3]
                    px[y][x] = c
                    glow[y][x] = (*c[:3], 240 if r_pin <= 1.2 else 200)
                elif abs(y + 0.5 - cy) <= 1.4 or abs(dx) > 0.68:
                    px[y][x] = GOLD[3 if (dx + dy < -0.15) else (2 if dy < 0.25 else 1)]
                else:
                    lit = 0.70 - 0.28 * dx - 0.30 * dy
                    px[y][x] = _voronoi_stone(x, y, lit, seed, sc=3.6)
        out = _selective_outline(px, None, CLW, CLH, foot_cut_y=99)

    elif col == 2:
        # Col 2: Thrown Ancient Geode Pod (intact rough Voronoi sandstone & gold-banded boulder ~22x20 w/ cracks)
        for y in range(4, 24):
            for x in range(3, 25):
                dx = (x + 0.5 - cx) / 10.2
                dy = (y + 0.5 - cy) / 9.2
                ang = math.atan2(dy, dx)
                edge_px, h1, _h2, _va, _tl = _voronoi_grain(x, y, seed, sc=4.2)
                r = math.hypot(dx, dy) + (h1 - 0.5) * 0.14 + 0.06 * math.sin(ang * 5.0 + seed)
                if r > 0.96:
                    continue
                #Tilted antique-gold equatorial clasp band
                band_d = abs(dx * 0.35 + dy * 0.92)
                if band_d <= 0.18:
                    px[y][x] = GOLD[3 if (dx + dy < -0.2) else (2 if dx < 0.3 else 1)]
                else:
                    lit = 0.72 - 0.34 * dx - 0.32 * dy
                    px[y][x] = _voronoi_stone(x, y, lit, seed, sc=4.2)
        # Pressurized glowing turquoise & amber cracks!
        cracks = [(10, 9, TURQ[3]), (11, 10, TURQ[2]), (12, 11, AMBER[3]), (13, 12, AMBER[3]), (15, 13, TURQ[3]),
                  (16, 15, TURQ[2]), (12, 14, AMBER[2]), (11, 16, TURQ[3]), (17, 10, AMBER[3]), (16, 11, TURQ[2])]
        for gx, gy, gc in cracks:
            px[gy][gx] = gc
            glow[gy][gx] = (*gc[:3], 225)
        out = _selective_outline(px, None, CLW, CLH, foot_cut_y=99)

    else:
        # Col 3: Cracking-Open Geode Pod (shell splitting apart w/ blinding turquoise/violet sun-quartz tips emerging!)
        # Dark amethyst inner core exposed in the center
        for y in range(6, 22):
            for x in range(6, 22):
                if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= 6.2:
                    px[y][x] = VIOLET[1] if (x + y) % 3 == 0 else QUARTZ_CAV[1]

        # 3 separating Voronoi sandstone/gold shell chunks pushed outward!
        shell_lobes = [(9.2, 10.2, 5.2), (18.8, 10.6, 5.0), (13.8, 19.2, 5.4)]
        for li, (lx, ly, lr) in enumerate(shell_lobes):
            for y in range(3, CLH - 3):
                for x in range(3, CLW - 3):
                    d = math.hypot(x + 0.5 - lx, y + 0.5 - ly)
                    # Carve jagged central cleft so core & crystals burst through!
                    cleft = math.hypot(x + 0.5 - cx, y + 0.5 - cy) < 4.2
                    if d <= lr and not cleft:
                        lit = 0.74 - 0.08 * (x - lx) - 0.08 * (y - ly)
                        if abs(d - lr + 1.2) < 0.65 and (x + y + li) % 3 == 0:
                            px[y][x] = GOLD[2]
                        else:
                            px[y][x] = _voronoi_stone(x, y, lit, seed + li * 19, sc=3.8)

        # Blinding emerging sun-quartz crystal tips bursting from center!
        z_buf = [[-1e9] * CLW for _ in range(CLH)]
        cid_buf = [[0] * CLW for _ in range(CLH)]
        burst_spires = [
            (14.0, 14.5, 10.2, 2.3, -18.0, 0.10),
            (14.0, 14.0, 9.6, 2.2, 48.0, 0.45),
            (13.5, 14.0, 9.2, 2.1, -115.0, 0.72),
            (14.5, 14.5, 8.5, 2.0, 142.0, 0.30),
        ]
        for si, (bx, by, ln, hw, ang, hs) in enumerate(burst_spires):
            _draw_spire(px, glow, z_buf, cid_buf, CLW, CLH, bx, by, ln, hw, ang, 3.0 + si * 0.1, 10 + si, hs, seed + si * 13, margin=3)
        px[14][14] = QUARTZ_W[5]
        glow[14][14] = (*AMBER[3][:3], 250)
        out = _selective_outline(px, None, CLW, CLH, foot_cut_y=99)

    _add_glow_halo(glow, CLW, CLH, alpha_scale=0.28)
    return out, glow


# ==============================================================================
# 6. TEMPLE WALLS (2x1 of 120x68 = 240x68, bottom-center anchor at (60, 56))
# ==============================================================================
TWW, TWH, TW_FY = 120, 68, 56


def render_temple_wall(variant: int):
    seed = 6200 + variant * 139
    px = blank(TWW, TWH)
    glow = blank(TWW, TWH)
    is_sand = [[False] * TWW for _ in range(TWH)]
    z_buf = [[-1e9] * TWW for _ in range(TWH)]
    cid_buf = [[0] * TWW for _ in range(TWH)]
    out = blank(TWW, TWH)

    _put_ground_shadow(out, 61.0, TW_FY + 1.5, 53.0, 5.5, TWW, TWH)

    # Massive 3/4 sandstone slab (~106x44 stone mass: x=7..113, y=12..56, front face x=7..105, right thickness x=106..113)
    _draw_voronoi_pedestal(px, is_sand, TWW, TWH, 9, 20, 112, 55, 5, 104, seed, gold_ys=(50,))
    # Overhanging stepped antique-gold & sandstone pharaonic cornice crown (y=11..21)
    _draw_voronoi_pedestal(px, is_sand, TWW, TWH, 6, 11, 114, 21, 5, 105, seed + 23, gold_ys=(16,))
    # Carved golden dentil teeth under cornice overhang!
    for dx_d in range(11, 103, 5):
        px[21][dx_d] = GOLD[2]
        px[21][dx_d + 1] = GOLD[1]
        px[22][dx_d] = SANDSTONE[0]

    # Varied ancient ashlar vertical mortar fractures & weathered cornice chips per variant!
    joints_x = (28, 54, 80) if variant == 0 else (24, 46, 69, 91)
    for jx in joints_x:
        for jy in range(23, 50):
            wob = 1 if (jy // 6 + jx) % 2 == 0 else 0
            px[jy][jx + wob] = SANDSTONE[0]
            px[jy][jx + wob + 1] = SANDSTONE[3]

    if variant == 0:
        # Weathered diagonal chip on upper-right cornice & mid-left notch
        for y in range(11, 19):
            for x in range(96, 115):
                if (x - 96) + (19 - y) > 12:
                    px[y][x] = CLEAR
        # Central recessed Winged Sun-Disc Cartouche (x=34..78, y=26..42)
        for y in range(26, 42):
            for x in range(34, 79):
                if x in (34, 78) or y in (26, 41):
                    px[y][x] = GOLD[2 if (x < 56 and y < 34) else 1]
                else:
                    px[y][x] = SANDSTONE[0 if y < 29 else 1]
        # Blazing golden sun-disc at (56, 34) + turquoise/gold stepped relief wings!
        for dy in range(-5, 6):
            for dx in range(-5, 6):
                d = math.hypot(dx, dy)
                if d <= 5.0:
                    if d <= 2.2:
                        px[34 + dy][56 + dx] = AMBER[3]
                        glow[34 + dy][56 + dx] = (*AMBER[3][:3], 245)
                    elif d <= 3.8:
                        px[34 + dy][56 + dx] = GOLD[3 if dx + dy <= 0 else 2]
                    else:
                        px[34 + dy][56 + dx] = TURQ[3]
                        glow[34 + dy][56 + dx] = (*TURQ[3][:3], 210)
        for wing_row, span in ((-3, 18), (0, 15), (3, 11)):
            wy = 34 + wing_row
            for sgn in (-1, 1):
                for k in range(7, span + 1):
                    wx = 56 + sgn * k
                    wc = TURQ[3 if k % 3 == 0 else 2] if wing_row != 0 else GOLD[3 if sgn < 0 else 2]
                    px[wy][wx] = wc
                    if wc in TURQ:
                        glow[wy][wx] = (*wc[:3], 205)
        # Side hieroglyph columns at x=18..22 and x=88..92
        for sx_c in (19, 90):
            for hy in range(27, 45, 3):
                for dx_h in (-1, 0, 1):
                    if hy % 6 == 0 and dx_h == 0:
                        px[hy][sx_c] = AMBER[3]
                        glow[hy][sx_c] = (*AMBER[3][:3], 225)
                    else:
                        px[hy][sx_c + dx_h] = TURQ[2]
                        glow[hy][sx_c + dx_h] = (*TURQ[2][:3], 185)

        # 5 jagged forward/downward sun-quartz crushing-fangs jutting along the lower/front face!
        fangs = [
            (21.0, 46.0, 13.5, 3.0, -148.0, 0.12),
            (39.0, 45.0, 15.0, 3.3, -166.0, 0.42),
            (56.5, 45.0, 16.5, 3.6, 178.0, 0.72),
            (74.0, 45.5, 14.5, 3.2, 164.0, 0.28),
            (92.0, 46.0, 13.0, 2.9, 146.0, 0.58),
        ]
    else:
        # Variant 1: Fractured upper-left corner & central cornice V-crack + 3 Pharaonic Eye/Astrolabe Cartouches!
        for y in range(11, 18):
            for x in range(6, 20):
                if (20 - x) + (18 - y) > 10:
                    px[y][x] = CLEAR
        for y in range(11, 17):
            for x in range(57 - (17 - y) // 2, 59 + (17 - y) // 2):
                px[y][x] = CLEAR

        # 3 recessed vertical pharaonic cartouches (x=16..36, 45..67, 76..96)
        for ci, (cx0, cx1) in enumerate(((16, 36), (45, 67), (76, 96))):
            mid_x = (cx0 + cx1) // 2
            for y in range(25, 43):
                for x in range(cx0, cx1 + 1):
                    if x in (cx0, cx1) or y in (25, 42):
                        px[y][x] = GOLD[2 if x <= mid_x else 1]
                    else:
                        px[y][x] = SANDSTONE[1]
            # Diamond solar-eye / star prism inside each cartouche!
            for dy in range(-5, 6):
                for dx in range(-6, 7):
                    md = abs(dx) * 0.8 + abs(dy)
                    if md <= 5.2:
                        if md <= 1.8:
                            gc = VIOLET[3] if ci == 1 else TURQ[3]
                            px[34 + dy][mid_x + dx] = gc
                            glow[34 + dy][mid_x + dx] = (*gc[:3], 240)
                        elif md <= 3.2:
                            px[34 + dy][mid_x + dx] = AMBER[3]
                            glow[34 + dy][mid_x + dx] = (*AMBER[3][:3], 210)
                        else:
                            px[34 + dy][mid_x + dx] = GOLD[3 if dx + dy <= 0 else 2]
        # Glowing turquoise circuit bar linking the three cartouches
        for lx in range(37, 45):
            px[34][lx] = TURQ[3]
            glow[34][lx] = (*TURQ[3][:3], 205)
        for lx in range(68, 76):
            px[34][lx] = TURQ[3]
            glow[34][lx] = (*TURQ[3][:3], 205)

        # 6 asymmetric cleaved & cathedral sun-quartz crushing-fangs!
        fangs = [
            (16.0, 46.0, 12.5, 2.8, -142.0, 0.20),
            (32.0, 45.5, 15.5, 3.4, -162.0, 0.55),
            (48.5, 45.0, 14.5, 3.2, -174.0, 0.85),
            (64.5, 45.0, 16.0, 3.5, 172.0, 0.15),
            (81.0, 45.5, 14.5, 3.2, 160.0, 0.48),
            (96.0, 46.0, 12.5, 2.8, 144.0, 0.78),
        ]

    # Wind-drifted sand rubble along base BEFORE fangs so fangs jut fiercely over the sand!
    for sx_d, rx_d in ((24.0, 18.0), (58.0, 22.0), (92.0, 18.5)):
        _draw_sand_drift(px, is_sand, sx_d, 55.2, rx_d, 3.8, TWW, TWH, seed + int(sx_d))

    for fi, (bx, by, ln, hw, ang, hs) in enumerate(fangs):
        _draw_spire(
            px, glow, z_buf, cid_buf, TWW, TWH, bx, by, ln, hw, ang, 4.0 + fi * 0.1, 10 + fi, hs,
            seed + fi * 23, cleave_frac=(0.82 if (fi + variant) % 3 == 1 else None), max_y=62,
        )
        for y in range(42, 63):
            for x in range(6, TWW - 6):
                if cid_buf[y][x] >= 10:
                    is_sand[y][x] = False

    _add_glow_halo(glow, TWW, TWH, max_y=62, alpha_scale=0.28)
    outlined = _selective_outline(px, is_sand, TWW, TWH, foot_cut_y=54)
    for y in range(TWH):
        for x in range(TWW):
            if outlined[y][x][3] > 0:
                out[y][x] = _blend_px(out[y][x], outlined[y][x])
    return out, glow


# ==============================================================================
# 7. RESONANCE CORE (4x2 of 44x48 = 176x96, center at (22, 24))
# ==============================================================================
RCW, RCH = 44, 48


def _draw_3d_astrolabe_ring(px, glow, z_buf, cx: float, cy: float, radius: float, tilt_x: float, tilt_z: float, thick: float, jewel_phase: float, blazing: bool):
    cz, sz = math.cos(tilt_z), math.sin(tilt_z)
    cx_t, sx_t = math.cos(tilt_x), math.sin(tilt_x)
    steps = 120
    for s in range(steps):
        a = (s / steps) * math.tau
        rx0 = math.cos(a) * radius
        ry0 = math.sin(a) * radius * cx_t
        rz = math.sin(a) * radius * sx_t
        sx = cx + rx0 * cz - ry0 * sz
        sy = cy + rx0 * sz + ry0 * cz
        is_jewel = abs(((a - jewel_phase + math.pi) % math.pi) - math.pi * 0.5) < 0.12
        for dy_w in (-1, 0, 1):
            for dx_w in (-1, 0, 1):
                if abs(dx_w) + abs(dy_w) > (2 if thick > 1.3 else 1):
                    continue
                ix, iy = int(round(sx + dx_w * 0.65)), int(round(sy + dy_w * 0.65))
                if 3 <= ix < RCW - 3 and 3 <= iy < RCH - 3 and rz >= z_buf[iy][ix]:
                    z_buf[iy][ix] = rz
                    if is_jewel and dx_w == 0 and dy_w == 0:
                        jc = AMBER[3] if blazing else TURQ[3]
                        px[iy][ix] = jc
                        glow[iy][ix] = (*jc[:3], 240)
                    else:
                        sun = (ix - cx) + (iy - cy) < 0
                        if blazing:
                            gc = GOLD[3] if sun else GOLD[2]
                            px[iy][ix] = gc
                            glow[iy][ix] = (*AMBER[2][:3], 150)
                        else:
                            px[iy][ix] = GOLD[3 if (sun and rz > 0) else (2 if rz >= -2 else 1)]


def render_resonance_core(col: int, row: int):
    blazing = row == 1
    px = blank(RCW, RCH)
    glow = blank(RCW, RCH)
    z_buf = [[-1e9] * RCW for _ in range(RCH)]
    cx, cy = 22.0, 24.0
    phase = col * (math.tau / 4.0)

    if not blazing:
        # Row 0: Hovering Counter-Core — rose-cut sun-quartz prism heart + 2 counter-tilted gold astrolabe rings + micro-shards
        _draw_3d_astrolabe_ring(px, glow, z_buf, cx, cy, 14.8, 0.92, 0.55 + phase * 0.5, 1.2, phase, blazing=False)
        _draw_3d_astrolabe_ring(px, glow, z_buf, cx, cy, 12.6, 0.88, -0.62 - phase * 0.5, 1.1, -phase, blazing=False)

        # Multi-faceted rose-cut sun-quartz prism heart at z=0 (occludes back ring arcs, occluded by front ring arcs!)
        rx_h, ry_h = 7.4, 9.6
        for y in range(int(cy - ry_h) - 1, int(cy + ry_h) + 2):
            for x in range(int(cx - rx_h) - 1, int(cx + rx_h) + 2):
                dx = (x + 0.5 - cx) / rx_h
                dy = (y + 0.5 - cy) / ry_h
                # Octagonal/diamond rose-cut silhouette
                d = max(abs(dx) + abs(dy) * 0.68, abs(dy) + abs(dx) * 0.42, math.hypot(dx, dy) * 0.96)
                if d > 1.0 or 0.0 < z_buf[y][x]:
                    continue
                z_buf[y][x] = 0.0
                # Rotating rose-cut crystal facet planes!
                ang_f = math.atan2(dy, dx) + phase
                sec = int((ang_f + math.tau) / (math.tau / 6.0)) % 6
                if d < 0.34:
                    c = QUARTZ_W[5] if (dx + dy < 0) else TURQ[3]
                    glow[y][x] = (*TURQ[3][:3], 235)
                elif abs(d - 0.36) < 0.09 or abs(((ang_f + math.tau) % (math.tau / 6.0)) - 0.05) < 0.09:
                    # Crisp white facet arrises!
                    c = QUARTZ_W[5] if (dx + dy < 0.2) else QUARTZ_W[3]
                    glow[y][x] = (*QUARTZ_W[4][:3], 150)
                else:
                    sun_f = -(dx * 0.72 + dy * 0.69)
                    if sec in (0, 3):
                        c = TURQ[3 if sun_f > 0.1 else 2]
                        glow[y][x] = (*TURQ[2][:3], 185)
                    elif sec in (1, 4):
                        c = VIOLET[3 if sun_f > 0.05 else 2]
                        glow[y][x] = (*VIOLET[2][:3], 180)
                    else:
                        c = QUARTZ_W[4 if sun_f > 0 else 2]
                        glow[y][x] = (*AMBER[2][:3], 130)
                px[y][x] = c

        out = _selective_outline(px, None, RCW, RCH, foot_cut_y=99, ink_main=GOLD_INK, ink_quartz=QUARTZ_INK)

        # 4 orbiting pixel micro-shards outside the astrolabe!
        for mi in range(4):
            ma = phase + mi * (math.tau / 4.0) + 0.35
            mx = int(round(cx + math.cos(ma) * 17.5))
            my = int(round(cy + math.sin(ma) * 18.2 * 0.88))
            if 3 <= mx < RCW - 4 and 3 <= my < RCH - 4:
                mc = TURQ[3] if mi % 2 == 0 else VIOLET[3]
                out[my][mx] = QUARTZ_W[5]
                out[my + 1][mx] = mc
                glow[my][mx] = (*mc[:3], 225)
                glow[my + 1][mx] = (*mc[:3], 180)
    else:
        # Row 1: Reflected Homing Solar-Comet — flared golden astrolabe wings + supercharged golden-white/turquoise core + radiant corona!
        flap = math.sin(phase) * 2.2
        # Swept flared astrolabe wings on left & right (x=4..40, y=7..41)
        for sgn in (-1, 1):
            for feather_i, (ang_base, wlen, wthick) in enumerate(((0.38, 17.5, 2.2), (0.02, 16.5, 1.9), (-0.36, 14.8, 1.7))):
                ang = (0.0 if sgn > 0 else math.pi) - sgn * (ang_base + flap * 0.05)
                for s in range(4, int(wlen) + 1):
                    tf = s / wlen
                    wx = cx + math.cos(ang) * s
                    wy = cy + math.sin(ang) * s - (tf ** 1.6) * (3.5 - feather_i * 1.6)
                    ix, iy = int(round(wx)), int(round(wy))
                    if 3 <= ix < RCW - 3 and 3 <= iy < RCH - 3:
                        is_tip = tf > 0.78
                        wc = TURQ[3] if is_tip else (GOLD[3] if feather_i == 0 or iy < cy else GOLD[2])
                        px[iy][ix] = wc
                        glow[iy][ix] = (*(TURQ[3] if is_tip else AMBER[3])[:3], 225 if is_tip else 175)
                        if wthick > 1.8 and iy + 1 < RCH - 3:
                            px[iy + 1][ix] = GOLD[1]

        # Inner tilted golden halo ring
        _draw_3d_astrolabe_ring(px, glow, z_buf, cx, cy, 11.2, 0.65, phase * 0.5, 1.2, phase, blazing=True)

        # Blazing supercharged solar-comet heart (multi-faceted rose-cut diamond heart inside golden plasma corona!)
        rx_c, ry_c = 8.4, 10.4
        for y in range(int(cy - ry_c) - 1, int(cy + ry_c) + 2):
            for x in range(int(cx - rx_c) - 1, int(cx + rx_c) + 2):
                dx = (x + 0.5 - cx) / rx_c
                dy = (y + 0.5 - cy) / ry_c
                d = max(abs(dx) + abs(dy) * 0.65, math.hypot(dx, dy * 0.94) * 0.96)
                if d <= 1.0:
                    ang_c = math.atan2(dy, dx) + phase
                    sec_c = int((ang_c + math.tau) / (math.tau / 6.0)) % 6
                    if d <= 0.30 or abs(dx) < 0.11 or abs(dy) < 0.09:
                        c = QUARTZ_W[5]
                        glow[y][x] = (*QUARTZ_W[5][:3], 255)
                    elif d <= 0.66:
                        c = TURQ[3] if sec_c % 2 == 0 else AMBER[3]
                        glow[y][x] = (*c[:3], 245)
                    else:
                        c = GOLD[3] if (dx + dy < 0.1) else AMBER[2]
                        glow[y][x] = (*AMBER[3][:3], 215)
                    px[y][x] = c

        out = _selective_outline(px, None, RCW, RCH, foot_cut_y=99, ink_main=GOLD_INK, ink_quartz=QUARTZ_INK)

        # Pulsing 4-point solar star-cross corona spikes (unoutlined pure energy + intense glow!)
        spike_v = 19 if col % 2 == 0 else 17
        spike_h = 17 if col % 2 == 1 else 15
        for dy_s in range(-spike_v, spike_v + 1):
            yy = int(cy) + dy_s
            if 3 <= yy < RCH - 3:
                hot = abs(dy_s) < 9
                sc = QUARTZ_W[5] if abs(dy_s) < 5 else (AMBER[3] if hot else TURQ[3])
                if abs(dy_s) >= 8:
                    out[yy][int(cx)] = sc
                glow[yy][int(cx)] = (*sc[:3], 245 if hot else 190)
        for dx_s in range(-spike_h, spike_h + 1):
            xx = int(cx) + dx_s
            if 3 <= xx < RCW - 3:
                hot = abs(dx_s) < 8
                sc = QUARTZ_W[5] if abs(dx_s) < 5 else (TURQ[3] if hot else AMBER[3])
                if abs(dx_s) >= 7:
                    out[int(cy)][xx] = sc
                glow[int(cy)][xx] = (*sc[:3], 245 if hot else 190)

    _add_glow_halo(glow, RCW, RCH, alpha_scale=0.34 if blazing else 0.28)
    return out, glow


# ==============================================================================
# 8. TSUNAMI ROLLERS (4x1 of 72x60 = 288x60, base center at (36, 48))
# ==============================================================================
TRW, TRH, TR_BY = 72, 60, 48


def render_tsunami_roller(variant: int):
    """Organic billowing 3/4 desert sand-wave barrel segment (rounded billowing sides so overlapping segments fuse seamlessly!)."""
    seed = 6800 + variant * 107
    px = blank(TRW, TRH)
    glow = blank(TRW, TRH)
    is_sand = [[False] * TRW for _ in range(TRH)]
    z_buf = [[-1e9] * TRW for _ in range(TRH)]
    cid_buf = [[0] * TRW for _ in range(TRH)]
    out = blank(TRW, TRH)

    _put_ground_shadow(out, 36.0, TR_BY + 2.5, 31.0, 5.5, TRW, TRH)

    # Billowing basal & side sand-dust clouds FIRST so left/right sides have organic rounded silhouettes (never flat vertical brick cuts!)
    base_puffs = [
        (14.5, 38.0, 10.5, 12.5),
        (57.5, 38.5, 10.5, 12.0),
        (22.0, 46.5, 15.0, 6.8),
        (36.5, 47.5, 18.0, 7.2),
        (50.5, 46.5, 15.0, 6.8),
    ]
    for pi, (pcx, pcy, prx, pry) in enumerate(base_puffs):
        _draw_sand_drift(px, is_sand, pcx, pcy, prx, pry, TRW, TRH, seed + pi * 17)

    # Curled C-shaped 3/4 sand-wave barrel over x ~ 6..66, y ~ 9..51
    for y in range(6, TRH - 4):
        for x in range(5, TRW - 5):
            # Rounded horizontal envelope that tapers organically at top & bottom (no straight vertical walls!)
            vt_global = clamp((y - 9.0) / 41.0, 0.0, 1.0)
            half_span = 29.5 * math.sin(vt_global * math.pi * 0.82 + 0.22) + 2.2 * math.sin(y * 0.38 + variant * 1.9)
            dx = x + 0.5 - 36.0
            if abs(dx) > half_span:
                continue
            nx = dx / max(half_span, 1.0)
            env = math.sqrt(max(0.0, 1.0 - nx * nx * 0.78))

            crest_y = 10.5 + 5.0 * (1.0 - env) + 1.8 * math.sin(x * 0.23 + variant * 1.6)
            lip_hang = crest_y + 9.5 * env + 2.2 * math.sin(x * 0.48 + seed)
            barrel_bot = crest_y + 25.5 * env
            bot_y = 50.5 + 2.6 * math.sin(x * 0.34 + variant * 2.1) - 3.5 * (nx * nx)

            if y < crest_y or y > bot_y:
                continue

            if y <= lip_hang:
                # Sunlit curling sand-foam crest (#f7de9e / #e6be78) with 4x4 Bayer dithering!
                curl_t = (y - crest_y) / max(1.0, lip_hang - crest_y)
                lit = 0.98 - 0.22 * (curl_t ** 1.4) - 0.14 * nx
                c = _stone_shade(lit, x, y, SAND_DRIFT)
                if y <= crest_y + 2.0 and (x + y) % 2 == 0:
                    c = SAND_DRIFT[5]
                elif y >= lip_hang - 1.3 and env > 0.45:
                    # Crisp bright foam lip rim overhanging the dark hollow barrel!
                    c = SAND_DRIFT[4 if nx > 0.2 else 5]
                px[y][x] = c
                is_sand[y][x] = abs(nx) > 0.84  # Tinted upper crest outline; soft seamless side dust!
            elif y <= barrel_bot:
                # Deep C-curved concave churning wave barrel shadow trough!
                bar_t = (y - lip_hang) / max(1.0, barrel_bot - lip_hang)
                # Curved C-shaped vortex streaks (bowing inward at mid-barrel!)
                c_shift = 5.5 * math.sin(bar_t * math.pi)
                streak = 0.15 * math.sin((x + c_shift) * 0.38 + variant * 2.3)
                # Deepest shadow right under overhanging lip, brightening smoothly into rolling base surge
                lit = 0.08 + 0.38 * (bar_t ** 1.45) - 0.10 * nx + streak
                c = SANDSTONE[0] if lit < 0.18 else _stone_shade(lit, x, y, SAND_DRIFT)
                px[y][x] = c
                is_sand[y][x] = True
            else:
                # Rolling basal sand-foam surge around (36, 48)
                surge_t = (y - barrel_bot) / max(1.0, bot_y - barrel_bot)
                lit = 0.54 + 0.14 * math.sin(surge_t * math.pi) - 0.18 * nx + 0.08 * math.cos(x * 0.5 + y * 0.4)
                px[y][x] = _stone_shade(lit, x, y, SAND_DRIFT)
                is_sand[y][x] = True

    # Wind-whipped pixel sand-foam spray droplets above the curling crest
    for sx_p in range(13, 60, 7):
        sy_p = int(7 + 2 * ((sx_p + variant * 3) % 3))
        px[sy_p][sx_p] = SAND_DRIFT[5]
        px[sy_p + 1][sx_p + 1] = SAND_DRIFT[4]
        is_sand[sy_p][sx_p] = True
        is_sand[sy_p + 1][sx_p + 1] = True

    # Tumbling carved sandstone masonry chunks & varied sun-quartz crags per variant
    # (Variants 0 & 2 are pure churning sand + masonry rollers so stacked wave walls never repeat identical 3-spike crowns!)
    if variant == 0:
        _draw_rotated_box_2d(px, is_sand, TRW, TRH, 44.0, 33.5, 6.2, 4.4, 22.0, seed + 11, gold_trim=True)
        _draw_sand_drift(px, is_sand, 31.0, 17.5, 14.5, 5.2, TRW, TRH, seed + 61)
        blades = []
    elif variant == 1:
        _draw_rotated_box_2d(px, is_sand, TRW, TRH, 25.5, 34.0, 6.0, 4.2, -19.0, seed + 23, gold_trim=True)
        blades = [(41.5, 22.0, 17.5, 3.6, 26.0, 0.18), (23.5, 26.5, 10.5, 2.3, -34.0, 0.68)]
    elif variant == 2:
        _draw_rotated_box_2d(px, is_sand, TRW, TRH, 27.0, 35.5, 5.4, 3.9, -24.0, seed + 37, gold_trim=False)
        _draw_rotated_box_2d(px, is_sand, TRW, TRH, 47.5, 32.5, 6.0, 4.2, 17.0, seed + 43, gold_trim=True)
        _draw_sand_drift(px, is_sand, 38.5, 16.8, 16.0, 5.5, TRW, TRH, seed + 71)
        blades = []
    else:
        _draw_rotated_box_2d(px, is_sand, TRW, TRH, 23.0, 35.5, 5.2, 3.8, -28.0, seed + 41, gold_trim=True)
        blades = [(32.5, 20.5, 17.5, 3.6, -15.0, 0.14), (44.5, 21.5, 15.0, 3.1, 23.0, 0.74)]

    for bi, (bx, by, ln, hw, ang, hs) in enumerate(blades):
        _draw_spire(px, glow, z_buf, cid_buf, TRW, TRH, bx, by, ln, hw, ang, 4.0 + bi * 0.1, 10 + bi, hs, seed + bi * 19, max_y=46)
        for y in range(4, 48):
            for x in range(4, TRW - 4):
                if cid_buf[y][x] >= 10:
                    is_sand[y][x] = False

    # Crackling turquoise & solar-amber static sparks along the curling wave lip!
    for sp_k in range(6):
        sx_g = 15 + sp_k * 8 + (variant * 3) % 5
        sy_g = 20 + (sp_k * 2 + variant) % 7
        gc = AMBER[3] if sp_k == 2 else TURQ[3 if sp_k % 2 == 0 else 2]
        px[sy_g][sx_g] = gc
        glow[sy_g][sx_g] = (*gc[:3], 230)

    _add_glow_halo(glow, TRW, TRH, max_y=52, alpha_scale=0.28)
    outlined = _selective_outline(px, is_sand, TRW, TRH, foot_cut_y=42)
    for y in range(TRH):
        for x in range(TRW):
            if outlined[y][x][3] > 0:
                out[y][x] = _blend_px(out[y][x], outlined[y][x])
    return out, glow


# ==============================================================================
# 9. SLASH AND SEAMS (4x1 of 112x84 = 448x84, center at (56, 42))
# ==============================================================================
SSW, SSH = 112, 84


def render_slash_or_seam(col: int):
    seed = 7300 + col * 109
    px = blank(SSW, SSH)
    glow = blank(SSW, SSH)
    z_buf = [[-1e9] * SSW for _ in range(SSH)]
    cid_buf = [[0] * SSW for _ in range(SSH)]

    if col == 0:
        # Col 0: Crystal Crescent Cleave Arc (Main) — sweeping crescent (+X forward, ~96x74 span)
        # Broad dynamic crescent blade (outer +X apex at x~103, horns sweeping back to x~12, y~6..78)!
        for y in range(4, SSH - 4):
            ny = (y + 0.5 - 42.0) / 37.0
            if abs(ny) > 1.0:
                continue
            # Outer razor curve & inner trailing curve -> lush 34px belly tapering to needle horns!
            x_outer = 12.0 + 90.0 * max(0.0, 1.0 - ny * ny)
            taper = max(0.0, 1.0 - (ny * ny) ** 0.88)
            # Swept crystalline serrations along outer edge (angled along the slash curve, NOT gear teeth!)
            ang_c = math.atan2(ny, 0.65)
            serr = 2.8 * taper * ((ang_c * 5.5) % 1.0)
            x_lead = x_outer + serr
            thick = 35.0 * (taper ** 0.82)
            x_in = x_lead - thick

            x_start = max(6, int(math.floor(x_in - 6.0)))
            x_end = min(SSW - 4, int(math.ceil(x_lead + 1.0)))
            for x in range(x_start, x_end + 1):
                if x + 0.5 > x_lead or thick < 1.2:
                    continue
                u = (x + 0.5 - x_in) / thick  # 0 at trailing -X wake -> 1 at +X crystal razor edge!
                if u < 0.0:
                    continue

                # Twin engraved antique-gold astrolabe arc lines sweeping inside the crescent!
                on_gold_1 = taper > 0.14 and abs(x + 0.5 - (x_outer - 8.5 * taper - 1.5)) <= 0.95
                on_gold_2 = taper > 0.36 and abs(x + 0.5 - (x_outer - 16.5 * taper - 1.5)) <= 0.85

                if u >= 0.74:
                    # Razor-sharp faceted sun-quartz leading blade!
                    facet_step = int((ny + 1.2) * 7.5)
                    if u >= 0.90 or abs(((ny + 1.2) * 7.5) - facet_step) < 0.11:
                        c = QUARTZ_W[5]
                    elif facet_step % 2 == 0:
                        c = QUARTZ_W[4 if ny < 0.15 else 3]
                    else:
                        c = TURQ[3] if facet_step % 4 == 1 else QUARTZ_W[3]
                    px[y][x] = c
                    glow[y][x] = (*QUARTZ_W[5][:3], 235 if u >= 0.88 else 185)
                elif on_gold_1 or on_gold_2:
                    tick = int(round(ny * 22.0)) % 3 == 0
                    px[y][x] = GOLD[3 if (not tick and ny < 0.2) else (2 if not tick else 0)]
                    glow[y][x] = (*AMBER[3][:3], 205)
                elif u >= 0.44:
                    # Rich Bayer-dithered turquoise prismatic core wake!
                    c = _stone_shade((u - 0.35) * 1.45, x, y, TURQ)
                    px[y][x] = c
                    glow[y][x] = (*TURQ[2][:3], int(clamp(u * 240, 110, 225)))
                else:
                    # Sweeping trailing violet & solar-amber dispersing wake ribbons!
                    rib = math.sin(ny * 34.0 + x * 0.18)
                    if u + 0.18 * rib < 0.16:
                        continue
                    pal_w = VIOLET if int((ny + 1.5) * 8.0) % 2 == 0 else AMBER
                    c = _stone_shade(u * 1.9, x, y, pal_w)
                    alpha = int(clamp(u * 520, 85, 255))
                    px[y][x] = _with_alpha(c, alpha)
                    glow[y][x] = (*pal_w[3][:3], int(alpha * 0.82))

        # 7 swept-forward faceted sun-quartz blade shards integrated along the slash velocity!
        shard_nys = (-0.72, -0.46, -0.22, 0.0, 0.24, 0.48, 0.72)
        for si, sny in enumerate(shard_nys):
            by = 42.0 + sny * 36.0
            bx = 12.0 + 90.0 * (1.0 - sny * sny) - 6.0
            # Swept forward (+X = 90°) tilted smoothly along crescent tangent!
            tang_deg = 90.0 + sny * 48.0
            ln = 13.5 - abs(sny) * 4.5
            hw = 3.0 - abs(sny) * 0.8
            _draw_spire(px, glow, z_buf, cid_buf, SSW, SSH, bx, by, ln, hw, tang_deg, 3.0 + si * 0.1, 10 + si, si * 0.16, seed + si * 19, margin=3)

        out = _selective_outline(px, None, SSW, SSH, foot_cut_y=99, ink_main=GOLD_INK, ink_quartz=QUARTZ_INK)

    elif col == 1:
        # Col 1: Crystal Crescent Cleave Arc (Follow/Shatter) — shattering crescent trail of swept splinters & golden sparks!
        for y in range(5, SSH - 5):
            ny = (y + 0.5 - 42.0) / 36.0
            if abs(ny) > 1.0:
                continue
            x_arc = 14.0 + 84.0 * max(0.0, 1.0 - ny * ny)
            seg = int((ny + 1.5) * 9.0)
            for x in range(max(8, int(x_arc - 22)), min(SSW - 5, int(x_arc + 4))):
                d_arc = x + 0.5 - x_arc
                if seg % 2 == 0 and abs(d_arc + 4.0) <= 1.1:
                    px[y][x] = GOLD[3 if seg % 4 == 0 else 2]
                    glow[y][x] = (*AMBER[3][:3], 215)
                elif -18.0 * (1.0 - ny * ny) <= d_arc <= -2.0:
                    rib = math.sin(ny * 28.0 - x * 0.32)
                    if rib > 0.35 and (x + y) % 2 == 0:
                        vc = TURQ[3] if seg % 2 == 0 else VIOLET[3]
                        px[y][x] = _with_alpha(vc, 180)
                        glow[y][x] = (*vc[:3], 195)

        # 15 dispersing faceted crystal splinters swept dynamically forward (+X) along the shattering arc!
        for si in range(15):
            sny = (si - 7) / 7.5
            by = 42.0 + sny * 34.5
            bx = 14.0 + 84.0 * (1.0 - sny * sny) + ((si * 7) % 11 - 6) * 1.6 - 5.0
            ln = 11.5 - abs(sny) * 3.5 + (si % 3) * 1.4
            hw = 2.5 - abs(sny) * 0.45
            sp_ang = 90.0 + sny * 46.0 + ((si % 3) - 1) * 9.0
            _draw_spire(
                px, glow, z_buf, cid_buf, SSW, SSH, bx, by, ln, hw, sp_ang, 3.0 + si * 0.05, 10 + si,
                si * 0.19, seed + si * 23, cleave_frac=(0.78 if si % 4 == 1 else None), margin=4,
            )

        out = _selective_outline(px, None, SSW, SSH, foot_cut_y=99, ink_main=GOLD_INK, ink_quartz=QUARTZ_INK)

        # Scattering golden & turquoise pixel sparks in the shatter wake!
        for ki in range(26):
            kny = ((ki - 12.5) / 13.0) * 0.94
            kx = int(round(14.0 + 84.0 * (1.0 - kny * kny) - 22.0 + ((ki * 13) % 23)))
            ky = int(round(42.0 + kny * 34.0))
            if 4 <= kx < SSW - 4 and 4 <= ky < SSH - 4:
                kc = AMBER[3] if ki % 2 == 0 else (TURQ[3] if ki % 3 == 0 else VIOLET[3])
                out[ky][kx] = kc
                glow[ky][kx] = (*kc[:3], 240)

    elif col == 2:
        # Col 2: Erupting Sun-Quartz Fault Seam — horizontal (96x34 centered cleanly at (56, 42))!
        is_sand = [[False] * SSW for _ in range(SSH)]
        for y in range(36, 58):
            for x in range(8, 105):
                nx = (x - 56.0) / 48.0
                if abs(nx) > 1.0:
                    continue
                taper_x = math.sqrt(max(0.0, 1.0 - nx * nx * 0.85))
                jag_y = 48.5 + 2.0 * math.sin(x * 0.35 + seed)
                dy = y - jag_y
                if abs(dy) > 8.2 * taper_x:
                    continue
                if abs(dy) <= 2.4 * taper_x:
                    hot = abs(dy) < 1.15
                    fc = AMBER[3] if (hot and x % 5 != 0) else (TURQ[3] if x % 5 == 0 else AMBER[2])
                    px[y][x] = fc
                    glow[y][x] = (*fc[:3], 245 if hot else 195)
                elif abs(dy) <= 5.2 * taper_x:
                    lit = 0.74 if dy < 0 else 0.32
                    px[y][x] = _voronoi_stone(x, y, lit, seed, sc=4.4, scorch=0.7)
                else:
                    px[y][x] = _stone_shade(0.58 - 0.15 * nx, x, y, SAND_DRIFT)
                    is_sand[y][x] = True

        # 11 crossed sun-quartz crystal teeth erupting out of the fissure (spanning y ~ 25..57, centered at y=42!)
        teeth = [
            (15.0, 47.5, 13.5, 2.5, -24.0, 0.10),
            (23.0, 48.5, 18.0, 3.1, 16.0, 0.42),
            (31.5, 48.0, 21.0, 3.5, -14.0, 0.75),
            (40.0, 48.5, 19.0, 3.2, 21.0, 0.20),
            (48.5, 48.0, 23.5, 3.9, -9.0, 0.55),
            (56.5, 48.5, 24.5, 4.1, 7.0, 0.88),
            (64.5, 48.0, 22.5, 3.8, -17.0, 0.32),
            (73.0, 48.5, 19.5, 3.3, 19.0, 0.65),
            (81.5, 48.0, 20.5, 3.4, -13.0, 0.05),
            (89.5, 48.5, 17.0, 3.0, 22.0, 0.48),
            (97.0, 47.5, 13.0, 2.4, 26.0, 0.80),
        ]
        for ti, (bx, by, ln, hw, ang, hs) in enumerate(teeth):
            _draw_spire(
                px, glow, z_buf, cid_buf, SSW, SSH, bx, by, ln, hw, ang, 3.0 + (ti % 3) * 0.2, 10 + ti, hs,
                seed + ti * 19, cleave_frac=(0.80 if ti in (2, 7) else None), max_y=55,
            )
            for y in range(22, 56):
                for x in range(8, SSW - 8):
                    if cid_buf[y][x] >= 10:
                        is_sand[y][x] = False
        _carve_spire_creases(px, glow, z_buf, cid_buf, SSW, SSH, molten=False)
        out = _selective_outline(px, is_sand, SSW, SSH, foot_cut_y=51)

    else:
        # Col 3: Solar Astrolabe Muzzle Mandala — ornate circular (76x76 centered at (56, 42)) golden ring + 8 sun-rays + 4 cabochons!
        cx_m, cy_m = 56.0, 42.0
        for y in range(3, SSH - 3):
            for x in range(16, SSW - 16):
                dx, dy = x + 0.5 - cx_m, y + 0.5 - cy_m
                r = math.hypot(dx, dy)
                if r > 38.2:
                    continue
                ang = math.atan2(dy, dx)
                sun_tl = (dx + dy) < 0

                is_card_ray = min(abs(dx), abs(dy)) <= max(0.7, 3.6 * (1.0 - (r - 21.0) / 17.5)) and 21.0 <= r <= 38.0
                is_diag_ray = abs(abs(dx) - abs(dy)) * 0.7071 <= max(0.6, 2.9 * (1.0 - (r - 21.0) / 15.5)) and 21.0 <= r <= 36.2

                def hex_bar(rot_o: float) -> float:
                    d_t = max(dx * math.cos(rot_o + k * (math.tau / 3.0)) + dy * math.sin(rot_o + k * (math.tau / 3.0)) for k in range(3))
                    return abs(d_t - 9.8) if d_t <= 11.2 else 99.0

                hb = min(hex_bar(0.0), hex_bar(math.pi))

                if r <= 8.2:
                    if r <= 3.6:
                        px[y][x] = QUARTZ_W[5]
                        glow[y][x] = (*QUARTZ_W[5][:3], 255)
                    elif r <= 6.0:
                        px[y][x] = AMBER[3] if sun_tl else TURQ[3]
                        glow[y][x] = (*(AMBER[3] if sun_tl else TURQ[3])[:3], 240)
                    else:
                        px[y][x] = GOLD[3 if sun_tl else 2]
                elif 26.2 <= r <= 31.4:
                    deg_tick = abs((ang / (math.pi / 12.0)) - round(ang / (math.pi / 12.0))) < 0.09 and 27.6 <= r <= 30.4
                    if deg_tick:
                        px[y][x] = TURQ[3] if int(round(ang / (math.pi / 12.0))) % 3 == 0 else GOLD[0]
                        if px[y][x] == TURQ[3]:
                            glow[y][x] = (*TURQ[2][:3], 190)
                    else:
                        px[y][x] = GOLD[3 if (sun_tl and r < 29.4) else (2 if sun_tl or r < 28.8 else 1)]
                elif 18.8 <= r <= 21.6:
                    px[y][x] = GOLD[3 if sun_tl else 1]
                elif hb <= 1.35 and r <= 20.5:
                    px[y][x] = QUARTZ_W[5 if sun_tl else 3]
                    glow[y][x] = (*TURQ[2][:3], 185)
                elif is_card_ray:
                    core_r = min(abs(dx), abs(dy)) < 1.05 and r < 35.5
                    px[y][x] = AMBER[3] if core_r else GOLD[3 if sun_tl else 2]
                    if core_r:
                        glow[y][x] = (*AMBER[3][:3], 225)
                elif is_diag_ray:
                    core_d = abs(abs(dx) - abs(dy)) * 0.7071 < 0.95 and r < 33.8
                    px[y][x] = QUARTZ_W[5] if core_d else GOLD[2 if sun_tl else 1]
                    if core_d:
                        glow[y][x] = (*VIOLET[3][:3], 210)

        # 4 Faceted Turquoise/Violet Prism Cabochons nestled cleanly on the 45° diagonals at r=28.8 on the astrolabe ring!
        for ca_deg, pal_c in ((45.0, TURQ), (135.0, VIOLET), (225.0, TURQ), (315.0, VIOLET)):
            cr = math.radians(ca_deg)
            jx = cx_m + math.cos(cr) * 28.8
            jy = cy_m + math.sin(cr) * 28.8
            for dy_j in range(-4, 5):
                for dx_j in range(-4, 5):
                    jd = math.hypot(dx_j, dy_j)
                    ix, iy = int(round(jx + dx_j)), int(round(jy + dy_j))
                    if jd <= 4.2:
                        if jd <= 1.6:
                            px[iy][ix] = QUARTZ_W[5]
                            glow[iy][ix] = (*pal_c[3][:3], 250)
                        elif jd <= 3.0:
                            px[iy][ix] = pal_c[3 if dx_j + dy_j <= 0 else 2]
                            glow[iy][ix] = (*pal_c[3][:3], 230)
                        else:
                            px[iy][ix] = GOLD[3 if dx_j + dy_j <= 0 else 1]

        out = _selective_outline(px, None, SSW, SSH, foot_cut_y=99, ink_main=GOLD_INK, ink_quartz=QUARTZ_INK)

    _add_glow_halo(glow, SSW, SSH, alpha_scale=0.30)
    return out, glow


# ==============================================================================
# 10. PRISM SPIKE & SHARDS (4x2 of 56x64 = 224x128; r0 pivot (28,52), r1 center (28,32))
# ==============================================================================
PSW, PSH = 56, 64


def render_prism_spike_or_shard(col: int, row: int):
    seed = 7900 + row * 211 + col * 89
    px = blank(PSW, PSH)
    glow = blank(PSW, PSH)
    z_buf = [[-1e9] * PSW for _ in range(PSH)]
    cid_buf = [[0] * PSW for _ in range(PSH)]

    if row == 0:
        # Row 0: 4 Growth & Charge Stages of `PRISMENBRUCH` Sun-Quartz Cluster (ground pivot at (28, 52))
        is_sand = [[False] * PSW for _ in range(PSH)]
        out = blank(PSW, PSH)
        _put_ground_shadow(out, 28.0, 52.5, 16.5 + col * 1.4, 4.4, PSW, PSH)

        # Ornate gold-inlaid Voronoi sandstone sun-seal collar around (28, 52)
        rx_c = 14.5 + min(col, 2) * 2.0
        ry_c = 5.0 + min(col, 2) * 0.6
        for y in range(44, 58):
            for x in range(6, PSW - 6):
                dx = (x + 0.5 - 28.0) / rx_c
                dy = (y + 0.5 - 52.0) / ry_c
                d = math.hypot(dx, dy)
                if d <= 1.0:
                    if 0.68 <= d <= 0.86:
                        px[y][x] = GOLD[3 if (dx + dy < -0.1) else (2 if dx < 0.3 else 1)]
                    else:
                        lit = 0.68 - 0.28 * dx - 0.24 * dy
                        px[y][x] = _voronoi_stone(x, y, lit, seed, sc=4.2, scorch=(0.6 if col == 3 else 0.0))
                    z_buf[y][x] = 1.8

        _draw_sand_drift(px, is_sand, 16.0, 53.5, 7.5, 2.5, PSW, PSH, seed + 13)
        _draw_sand_drift(px, is_sand, 40.0, 53.5, 7.5, 2.5, PSW, PSH, seed + 29)

        if col == 0:
            # Stage 0: Cracking golden sun-seal collar + budding crystal point
            for cr in ([(28, 51), (20, 52), (15, 53)], [(28, 51), (36, 52), (41, 51)], [(28, 51), (28, 56)]):
                _stamp_molten_fissures(px, glow, PSW, PSH, [cr])
            spires = [(28.0, 51.0, 14.5, 3.2, -2.0, 3.0, 0.15), (24.0, 52.0, 7.5, 1.9, -24.0, 3.2, 0.55)]
        elif col == 1:
            # Stage 1: Rising twin prism spires
            spires = [
                (25.5, 50.5, 26.5, 3.9, -12.0, 2.8, 0.12),
                (31.0, 50.5, 23.0, 3.6, 15.0, 3.1, 0.48),
                (20.5, 52.0, 11.5, 2.2, -32.0, 3.4, 0.78),
                (35.5, 52.0, 10.5, 2.1, 34.0, 3.5, 0.30),
            ]
        else:
            # Stage 2 & Stage 3: Full 5-crystal cathedral sun-quartz cluster!
            spires = [
                (21.5, 50.0, 25.5, 3.5, -23.0, 2.2, 0.62),
                (34.5, 50.0, 24.5, 3.4, 24.0, 2.4, 0.25),
                (27.8, 50.5, 41.5, 5.0, -2.0, 3.2, 0.08),
                (17.5, 51.5, 15.5, 2.5, -40.0, 3.6, 0.85),
                (38.5, 51.5, 15.0, 2.4, 41.0, 3.7, 0.42),
            ]

        for si, (bx, by, ln, hw, ang, zv, hs) in enumerate(spires):
            _draw_spire(
                px, glow, z_buf, cid_buf, PSW, PSH, bx, by, ln, hw, ang, zv, 10 + si, hs,
                seed + si * 23, molten=False, max_y=55,
            )
            for y in range(4, 56):
                for x in range(4, PSW - 4):
                    if cid_buf[y][x] >= 10:
                        is_sand[y][x] = False
        _carve_spire_creases(px, glow, z_buf, cid_buf, PSW, PSH, molten=False)

        if col == 3:
            # Stage 3: Blindingly supercharged cluster w/ blazing turquoise/gold fissures & levitating splinters!
            fiss = [
                [(27, 14), (28, 25), (26, 36), (28, 48), (22, 54)],
                [(18, 32), (22, 41), (28, 48), (35, 53)],
                [(39, 31), (34, 41), (28, 48)],
            ]
            for fpath in fiss:
                for i in range(len(fpath) - 1):
                    ax, ay = fpath[i]
                    bx, by = fpath[i + 1]
                    st = max(1, int(math.hypot(bx - ax, by - ay) * 1.5))
                    for s in range(st + 1):
                        fx = int(round(ax + (bx - ax) * (s / st)))
                        fy = int(round(ay + (by - ay) * (s / st)))
                        if px[fy][fx][3] >= 200:
                            fc = AMBER[3] if s % 3 == 0 else TURQ[3]
                            px[fy][fx] = fc
                            glow[fy][fx] = (*fc[:3], 245)

        outlined = _selective_outline(px, is_sand, PSW, PSH, foot_cut_y=51)
        if col == 3:
            # 5 levitating crystal splinters hovering around the supercharged crown!
            lev_pts = [(11, 20, TURQ[3]), (44, 18, AMBER[3]), (9, 34, VIOLET[3]), (46, 33, TURQ[3]), (19, 11, AMBER[3])]
            for lx, ly, lc in lev_pts:
                outlined[ly][lx] = QUARTZ_W[5]
                outlined[ly + 1][lx] = lc
                outlined[ly + 1][lx + 1] = QUARTZ_INK
                glow[ly][lx] = (*lc[:3], 240)
                glow[ly + 1][lx] = (*lc[:3], 200)

        _add_glow_halo(glow, PSW, PSH, max_y=58, alpha_scale=0.32 if col == 3 else 0.26)
        for y in range(PSH):
            for x in range(PSW):
                if outlined[y][x][3] > 0:
                    out[y][x] = _blend_px(out[y][x], outlined[y][x])
        return out, glow

    else:
        # Row 1: 4 Distinct Faceted Shrapnel Chunks (~18x18 to 22x22 centered cleanly at (28, 32)!)
        cx, cy = 28.0, 32.0
        if col == 0:
            # Shrapnel 0: Hexagonal turquoise-refracting sun-quartz spire tip (~20x18 centered at (28, 32))
            _draw_spire(px, glow, z_buf, cid_buf, PSW, PSH, cx - 5.5, cy + 5.5, 16.5, 4.5, 46.0, 2.0, 10, 0.08, seed)
            # Jagged fractured base bevel across bottom-left of tip
            for dy in range(-2, 4):
                for dx in range(-3, 3):
                    ix, iy = int(cx - 5 + dx), int(cy + 5 + dy)
                    if px[iy][ix][3] > 0 and dx + dy > 1:
                        px[iy][ix] = TURQ[3] if (dx + dy == 2) else QUARTZ_W[1]
            out = _selective_outline(px, None, PSW, PSH, foot_cut_y=99, ink_main=QUARTZ_INK, ink_quartz=QUARTZ_INK)

        elif col == 1:
            # Shrapnel 1: Chiseled sandstone & antique-gold relief fragment (~20x18 centered at (28, 32))
            for y in range(23, 41):
                for x in range(19, 38):
                    dx = (x + 0.5 - cx) / 8.8
                    dy = (y + 0.5 - cy) / 8.2
                    _, h1, _, _, _ = _voronoi_grain(x, y, seed, sc=4.5)
                    d = max(abs(dx), abs(dy)) * 0.65 + math.hypot(dx, dy) * 0.45 + (h1 - 0.5) * 0.16
                    if d <= 0.96:
                        if dy < -0.35 or dx > 0.42:
                            px[y][x] = GOLD[3 if (dx + dy < -0.1) else (2 if dy < 0.2 else 1)]
                        else:
                            lit = 0.72 - 0.30 * dx - 0.28 * dy
                            px[y][x] = _voronoi_stone(x, y, lit, seed, sc=4.0)
            for rx_r, ry_r in ((26, 32), (27, 32), (28, 32), (27, 31), (27, 33)):
                rc = AMBER[3] if (rx_r == 27 and ry_r == 32) else TURQ[3]
                px[ry_r][rx_r] = rc
                glow[ry_r][rx_r] = (*rc[:3], 235)
            out = _selective_outline(px, None, PSW, PSH, foot_cut_y=99)

        elif col == 2:
            # Shrapnel 2: Cleaved violet-amber prismatic crystal wedge (~20x18 centered at (28, 32))
            for y in range(23, 42):
                for x in range(18, 39):
                    dx = x + 0.5 - cx
                    dy = y + 0.5 - cy
                    # Sharp rhomboid cleaved crystal blade!
                    u = (dx * 0.82 - dy * 0.57) / 9.2
                    v = (dx * 0.57 + dy * 0.82) / 6.2
                    if abs(u) + abs(v) * 0.68 <= 1.08 and abs(v) <= 0.95:
                        if abs(v) < 0.18 or u < -0.62:
                            c = QUARTZ_W[5]
                            glow[y][x] = (*QUARTZ_W[5][:3], 200)
                        elif v < 0:
                            c = VIOLET[3 if u < 0.15 else 2]
                            glow[y][x] = (*VIOLET[3][:3], 210)
                        else:
                            c = AMBER[3 if u < 0.0 else 2] if u < 0.45 else VIOLET[1]
                            glow[y][x] = (*AMBER[2][:3], 185)
                        px[y][x] = c
            out = _selective_outline(px, None, PSW, PSH, foot_cut_y=99, ink_main=QUARTZ_INK, ink_quartz=QUARTZ_INK)

        else:
            # Shrapnel 3: Radiant snow-quartz star-splinter cluster (~22x22 centered at (28, 32))
            star_spires = [
                (cx, cy + 1.0, 10.2, 2.5, -15.0, 0.15),
                (cx - 1.0, cy, 9.8, 2.4, 78.0, 0.48),
                (cx, cy - 1.0, 9.6, 2.4, 165.0, 0.75),
                (cx + 1.0, cy, 9.5, 2.3, -98.0, 0.32),
            ]
            for si, (bx, by, ln, hw, ang, hs) in enumerate(star_spires):
                _draw_spire(px, glow, z_buf, cid_buf, PSW, PSH, bx, by, ln, hw, ang, 2.0 + si * 0.1, 10 + si, hs, seed + si * 17)
            for dy_c in (-1, 0, 1):
                for dx_c in (-1, 0, 1):
                    hc = QUARTZ_W[5] if (dx_c == 0 and dy_c == 0) else TURQ[3]
                    px[int(cy) + dy_c][int(cx) + dx_c] = hc
                    glow[int(cy) + dy_c][int(cx) + dx_c] = (*TURQ[3][:3], 245)
            out = _selective_outline(px, None, PSW, PSH, foot_cut_y=99, ink_main=QUARTZ_INK, ink_quartz=QUARTZ_INK)

        _add_glow_halo(glow, PSW, PSH, alpha_scale=0.28)
        return out, glow


# ==============================================================================
# VISUAL QA CONTACT SHEET (docs/img/aurelith_fx_sheet.png — 2x Day + Night)
# ==============================================================================
def write_qa_sheet(sheets: dict, out_path: pathlib.Path):
    from PIL import Image, ImageDraw

    z = 2
    w_log = 784
    h_half = 540
    day_bg = (216, 162, 94, 255)    # #d8a25e warm Sonnenquarz desert sand
    night_bg = (22, 28, 50, 255)    # #161c32 night desert backdrop

    canvas = Image.new("RGBA", (w_log * z, h_half * 2 * z), day_bg)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, h_half * z, w_log * z, h_half * 2 * z], fill=night_bg)
    draw.line([(0, h_half * z), (w_log * z, h_half * z)], fill=(52, 34, 30, 255), width=2)

    def to_pil(px_grid):
        gh = len(px_grid)
        gw = len(px_grid[0])
        im = Image.new("RGBA", (gw, gh))
        im.putdata([c for row in px_grid for c in row])
        return im

    pil_pairs = {name: (to_pil(b_px), to_pil(g_px)) for name, (b_px, g_px) in sheets.items()}

    def paste_sheet(name: str, lx: int, ly: int, night: bool):
        base_im, glow_im = pil_pairs[name]
        bw, bh = base_im.size
        # Composite at 1x logical first for crisp pixel accuracy, then 2x NEAREST upscale!
        bg_c = night_bg if night else day_bg
        sub = canvas.crop((lx * z, ly * z, (lx + bw) * z, (ly + bh) * z)).resize((bw, bh), Image.Resampling.NEAREST)
        sub_px = list(sub.getdata())
        b_px = list(base_im.getdata())
        g_px = list(glow_im.getdata())
        dim = 0.42 if night else 1.0
        comp = []
        for i in range(len(sub_px)):
            bg = sub_px[i]
            bc = b_px[i]
            if bc[3] > 0:
                a = bc[3] / 255.0
                r = int(bg[0] * (1.0 - a) + bc[0] * dim * a)
                g = int(bg[1] * (1.0 - a) + bc[1] * dim * a)
                b = int(bg[2] * (1.0 - a) + bc[2] * dim * a)
            else:
                r, g, b = bg[0], bg[1], bg[2]
            if night:
                gc = g_px[i]
                if gc[3] > 0:
                    ga = gc[3] / 255.0
                    r = min(255, int(r + gc[0] * ga))
                    g = min(255, int(g + gc[1] * ga))
                    b = min(255, int(b + gc[2] * ga))
            comp.append((max(1, r), max(1, g), max(1, b), 255))
        _ = bg_c
        out_im = Image.new("RGBA", (bw, bh))
        out_im.putdata(comp)
        canvas.paste(out_im.resize((bw * z, bh * z), Image.Resampling.NEAREST), (lx * z, ly * z))

    layout = [
        # Row band A (y=14): monolith_pillars (256x168) | quicksand_vortex (512x92) + sintered_plates (320x58) + buried_gauntlet (160x72)
        ("monolith_pillars", 8, 14),
        ("quicksand_vortex", 268, 10),
        ("sintered_plates", 268, 112),
        ("buried_gauntlet", 604, 108),
        # Row band B (y=194): temple_walls (240x68) | tsunami_rollers (288x60) | resonance_core (176x96) | chain_links (112x28)
        ("temple_walls", 8, 198),
        ("tsunami_rollers", 260, 202),
        ("resonance_core", 564, 192),
        ("chain_links", 8, 282),
        # Row band C (y=320): slash_and_seams (448x84) | prism_spike_and_shards (224x128)
        ("slash_and_seams", 8, 336),
        ("prism_spike_and_shards", 488, 316),
    ]

    for night_idx in (0, 1):
        oy = night_idx * h_half
        lbl_col = (52, 34, 30, 255) if not night_idx else (214, 226, 245, 255)
        for name, lx, ly in layout:
            paste_sheet(name, lx, oy + ly, bool(night_idx))
            draw.text((lx * z + 2, (oy + ly - 7) * z), name, fill=lbl_col)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "PNG")
    print(f"Saved 2x Day + Night QA contact sheet: {out_path} ({canvas.width}x{canvas.height})")


# ==============================================================================
# MAIN BUILDER & STRICT VERIFICATION
# ==============================================================================
def main():
    fx_dir = ROOT / "enemies" / "aurelith_fx"
    fx_dir.mkdir(parents=True, exist_ok=True)

    specs = [
        ("monolith_pillars", 4, 2, MPW, MPH, [render_monolith_pillar(c, r) for r in range(2) for c in range(4)]),
        ("sintered_plates", 4, 1, SPW, SPH, [render_sintered_plate(c) for c in range(4)]),
        ("quicksand_vortex", 4, 1, QVW, QVH, [render_quicksand_vortex(c) for c in range(4)]),
        ("buried_gauntlet", 2, 1, BGW, BGH, [render_buried_gauntlet(c) for c in range(2)]),
        ("chain_links", 4, 1, CLW, CLH, [render_chain_or_pod(c) for c in range(4)]),
        ("temple_walls", 2, 1, TWW, TWH, [render_temple_wall(c) for c in range(2)]),
        ("resonance_core", 4, 2, RCW, RCH, [render_resonance_core(c, r) for r in range(2) for c in range(4)]),
        ("tsunami_rollers", 4, 1, TRW, TRH, [render_tsunami_roller(c) for c in range(4)]),
        ("slash_and_seams", 4, 1, SSW, SSH, [render_slash_or_seam(c) for c in range(4)]),
        ("prism_spike_and_shards", 4, 2, PSW, PSH, [render_prism_spike_or_shard(c, r) for r in range(2) for c in range(4)]),
    ]

    built_sheets = {}
    for name, cols, rows, cw, ch, pairs in specs:
        base_frames = [p[0] for p in pairs]
        glow_frames = [p[1] for p in pairs]
        _verify_sheet(name, base_frames, cw, ch, margin=2)
        _verify_sheet(f"{name}_glow", glow_frames, cw, ch, margin=2)

        base_sheet = _sheet_from_grid(base_frames, cols, rows, cw, ch)
        glow_sheet = _sheet_from_grid(glow_frames, cols, rows, cw, ch)
        write_png(fx_dir / f"{name}.png", cw * cols, ch * rows, base_sheet)
        write_png(fx_dir / f"{name}_glow.png", cw * cols, ch * rows, glow_sheet)
        built_sheets[name] = (base_sheet, glow_sheet)
        print(f"  [OK] {name}{{,_glow}}.png -> {cw * cols}x{ch * rows} ({cols}x{rows} of {cw}x{ch})")

    qa_path = ROOT.parent / "docs" / "img" / "aurelith_fx_sheet.png"
    write_qa_sheet(built_sheets, qa_path)


if __name__ == "__main__":
    main()
