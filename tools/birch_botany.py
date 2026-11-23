#!/usr/bin/env python3
"""Botanical pixel-art engine for Glimmtal-Hängebirke / Silberbirke (Betula pendula glimmensis):
  1. Authentic Two-Zone Birch Bark: craggy diamond-fissured dark Borkenfuß boot clawing upward into
     chalk-white silver paper bark (#f6f2fa..#6e6285) with horizontal lenticel dashes & chevron Astaugen,
     plus coppery-bronze juvenile/twig bark (#4a2830..#cfa088).
  2. Airy Pendulous Weeping Canopy: arching upper sprays spilling into 8-20 px vertical chains of
     tiny 2x2..2x3 diamond birch leaves (#1a3b34..#cff2a6) & golden hanging Birkenkätzchen catkins.
  3. Modular Birch Traits (Rollrinde peeling curls, Birkenporling shelves, Funken-Chaga, dark ivy, lichen, sprigs)
     + 5 crisp 16x16 birch item icons (#1e162b outline, >=1px margin, single component, zero #000000).
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

# Palettes (strictly zero #000000)
LEAF = [hexc(c) for c in ("142c28", "1a3b34", "2b5e4a", "488e5c", "72bc6a", "a6df86", "cff2a6")]
CATKIN = [hexc(c) for c in ("6e5018", "9e7828", "d8b244", "f2dc78")]
OUT_BARK, OUT_ICON = hexc("221930"), hexc("1e162b")
OUT_LEAF_SUN, OUT_LEAF_SHADE = hexc("244434"), hexc("122824")

WHITE_BARK = [hexc(c) for c in ("4b3f63", "6e6285", "988cb2", "c2b9d6", "dfd8ea", "f6f2fa")]
CINNAMON = [hexc("7c3e32"), hexc("b2644a"), hexc("df9676")]
BORKEN = [hexc(c) for c in ("1b1426", "2c2138", "483a58", "68587a")]
COPPER = [hexc(c) for c in ("2e1824", "4a2830", "784440", "a86a5c", "cfa088")]
BIRCH_WOOD = [hexc(c) for c in ("96704c", "caa678", "eedab8", "fff8ea")]
MOSS = [hexc(c) for c in ("1c3c34", "2a5c46", "3e7d56", "5e9e64", "86c478")]
LICHEN = [hexc("6c9488"), hexc("a8d2c0"), hexc("d8f0e2")]
SAP = [hexc(c) for c in ("6c8c9e", "9ad0d4", "d8f6f2", "fffef4")]
GLOW = [hexc(c) for c in ("2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
CHAGA_FIRE = [hexc("9e4418"), hexc("d87428"), hexc("ffb84a"), hexc("fff0b0")]
SORREL = [hexc("d4c2f2"), hexc("f8f2ff"), hexc("f2dc78")]
CONTACT_RGB = (18, 34, 36)


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def clampi(v: int, lo: int, hi: int) -> int:
    return lo if v < lo else (hi if v > hi else v)


def clampf(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def put(px, x: int, y: int, col) -> None:
    if 0 <= x < len(px[0]) and 0 <= y < len(px) and col[3] > 0:
        if col[0] == 0 and col[1] == 0 and col[2] == 0:
            col = (20, 18, 36, col[3])
        px[y][x] = col


def put_contact_shadow(px, x: int, y: int, alpha: int) -> None:
    if 0 <= x < len(px[0]) and 0 <= y < len(px) and alpha > 0:
        cur = px[y][x]
        if cur[3] == 0:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], min(155, alpha))
        elif cur[:3] == CONTACT_RGB:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], min(165, max(cur[3], alpha)))


def blit(dst, src, ox: int = 0, oy: int = 0) -> None:
    sh, sw, dh, dw = len(src), len(src[0]), len(dst), len(dst[0])
    for y in range(sh):
        dy = oy + y
        if 0 <= dy < dh:
            for x in range(sw):
                dx = ox + x
                if 0 <= dx < dw and src[y][x][3] > 0:
                    c, bg = src[y][x], dst[dy][dx]
                    if c[3] == 255 or bg[3] == 0:
                        put(dst, dx, dy, c)
                    else:
                        a = c[3] / 255.0
                        ia = 1.0 - a
                        dst[dy][dx] = (max(1, int(c[0] * a + bg[0] * ia)), max(1, int(c[1] * a + bg[1] * ia)), max(1, int(c[2] * a + bg[2] * ia)), min(255, int(c[3] + bg[3] * ia)))


def hsh(x: int, y: int, s: int) -> float:
    n = (int(x) * 374761393 + int(y) * 668265263 + int(s) * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x: float, y: float, s: int) -> float:
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def sample_spline(pts: list, steps: int = 36) -> list:
    if len(pts) == 2:
        return [(pts[0][0] + (pts[1][0] - pts[0][0]) * i / steps, pts[0][1] + (pts[1][1] - pts[0][1]) * i / steps) for i in range(steps + 1)]
    out, ext, segs = [], [pts[0]] + list(pts) + [pts[-1]], len(pts) - 1
    for i in range(steps + 1):
        gf = min(segs - 1e-6, (i / float(steps)) * segs)
        si = int(gf)
        t = gf - si
        p0, p1, p2, p3 = ext[si], ext[si + 1], ext[si + 2], ext[si + 3]
        t2, t3 = t * t, t * t * t
        x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
        y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
        out.append((x, y))
    return out


def shade_birch_bark(x: int, y: int, u: float, rad: float, fy: int, borken_h: int, occ: float, seed: int, juvenile: bool = False, force_borken: bool = False):
    """Two-zone Betula pendula bark: diamond-fissured basal Borkenfuß + chalk-white lenticel paper bark (or copper whip)."""
    nz = math.sqrt(max(0.06, 1.0 - u * u))
    light = -0.62 * u + 0.54 * nz - occ
    if juvenile:
        if hsh(x, y // 2, seed + 5) > 0.90 and abs(u) < 0.65:
            return WHITE_BARK[4]
        return COPPER[clampi(int((light + 0.42) * 4.2), 0, 4)]
    # Jagged vertical Borkenfuß diamond-wedges clawing up into the chalk-white stem (and 100% dark Borkenfuß on roots!)
    wedge = abs(math.sin(u * 4.2 + seed * 0.3)) ** 1.6 * borken_h * 0.65 + (vnoise(x * 0.28, y * 0.18, seed) - 0.5) * 5.0
    if force_borken or (borken_h > 0 and y >= fy - (borken_h * 0.62 + wedge)):
        fiss = abs(math.sin(u * 4.6 + (y - fy) * 0.14)) < 0.28
        bi = 0 if fiss else clampi(int((light + 0.42) * 3.2), 0, 2 if force_borken else 3)
        return BORKEN[bi]
    # Crisp horizontal dark lenticel Ringstreifen + occasional chevron Astauge
    ring_y = y + (1 if abs(u) > 0.62 else 0)
    rh = hsh(ring_y, seed, 19)
    if rh > 0.72:
        c_u = (hsh(ring_y, seed, 23) - 0.5) * 1.10
        span = 0.15 + 0.26 * hsh(ring_y, seed, 29)
        if abs(u - c_u) <= span:
            if rh > 0.93 and abs(u - c_u) < 0.14:
                return BORKEN[0]
            return BORKEN[1 if abs(u - c_u) < span * 0.6 else 2]
    if rh > 0.95 and y + 1 < fy and abs(abs(u - (hsh(ring_y, seed, 23) - 0.5) * 0.8) - 0.16) < 0.09:
        return BORKEN[1]
    wi = clampi(int((light + 0.44) * 5.2), 0, 5)
    if u > 0.78:
        wi = min(wi, 1)
    return WHITE_BARK[wi]


def selout_bark(px, pad_x: int = 4, stop_y: int = 9999, skip_bottom_y: int = 9999) -> None:
    h, w = len(px), len(px[0])
    pts = []
    for y in range(1, min(h - 1, stop_y)):
        for x in range(max(1, pad_x), min(w - 1, w - pad_x)):
            if px[y][x][3] == 0:
                nb = ((x - 1, y), (x + 1, y)) if y >= skip_bottom_y else ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                if any(px[ny][nx][3] > 220 for nx, ny in nb):
                    pts.append((x, y))
    for x, y in pts:
        put(px, x, y, OUT_BARK)


def draw_birch_cut_rings(px, cx: int, cy: int, rx: int, ry: int) -> None:
    for y in range(cy - ry - 1, cy + ry + 2):
        for x in range(cx - rx - 1, cx + rx + 2):
            d = math.hypot((x - cx) / max(1.0, rx), (y - cy) / max(1.0, ry))
            if d <= 1.06:
                if d > 0.86:
                    put(px, x, y, OUT_BARK if d > 0.97 else WHITE_BARK[4])
                elif d > 0.68:
                    put(px, x, y, BIRCH_WOOD[3] if (x - cx + y - cy) < 0 else BIRCH_WOOD[2])
                else:
                    ring = int(d * max(2.8, rx * 0.6)) % 2
                    put(px, x, y, BIRCH_WOOD[2 if ring == 0 else 1] if d > 0.22 else BIRCH_WOOD[0])


def draw_birch_kerf(px, cx: int, cut_y: int, r_trunk: int, deep: bool = False) -> None:
    depth = max(2, int(r_trunk * (0.92 if deep else 0.54)))
    h_n = max(2, int(r_trunk * (0.62 if deep else 0.42)))
    xr = cx + r_trunk
    for dy in range(-h_n, 2):
        span = int(depth * (1.0 - abs(dy + h_n * 0.35) / (h_n + 1.5)))
        for k in range(max(1, span)):
            col = BORKEN[0] if dy >= 0 else (BIRCH_WOOD[0] if k > span * 0.68 else (BIRCH_WOOD[3] if dy < -h_n * 0.35 else BIRCH_WOOD[2]))
            put(px, xr - k, cut_y + dy, col)


def draw_birch_limb(px, pts: list, r0: float, r1: float, fy: int, borken_h: int, occ_y: int, seed: int, pad_x: int = 8, juvenile: bool = False, force_borken: bool = False) -> None:
    w, h = len(px[0]), len(px)
    sp = sample_spline(pts, max(16, len(pts) * 14))
    n = len(sp) - 1
    for i, (cx, cy) in enumerate(sp):
        t = i / float(max(1, n))
        rad = max(0.75, r0 + (r1 - r0) * (t ** 0.85))
        tx = sp[min(n, i + 1)][0] - sp[max(0, i - 1)][0]
        ty = sp[min(n, i + 1)][1] - sp[max(0, i - 1)][1]
        tl = max(1e-4, math.hypot(tx, ty))
        nx, ny = -ty / tl, tx / tl
        ir = int(math.ceil(rad + 0.8))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                px_x, px_y = int(round(cx + dx)), int(round(cy + dy))
                if px_x < pad_x or px_x >= w - pad_x or px_y < 2 or px_y >= h - 1 or math.hypot(dx, dy) > rad:
                    continue
                u = clampf((dx * nx + dy * ny) / max(0.85, rad), -1.0, 1.0)
                occ = clampf((occ_y - px_y) / 18.0, 0.0, 0.92) if occ_y > -900 else 0.0
                col = shade_birch_bark(px_x, px_y, u, rad, fy, borken_h, occ, seed, juvenile, force_borken)
                put(px, px_x, px_y, col)


def build_birch_skeleton(fw: int, fh: int, fx: int, fy: int, cut_y: int, occ_y: int, th_px: int, stems: list, boughs: list, borken_h: int, seed: int, n_roots: int = 4, sorrel=None, glow_root=None, pad_x: int = 12, juvenile: bool = False):
    """Builds slender Betula pendula trunk(s), dark Borkenfuß root flare & emerald root-moss (zero salmon toes!)."""
    skirt, tbase, tupper = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    rx_sh, ry_sh = th_px * 2.3 + 6.0, max(4.0, th_px * 0.72 + 3.0)
    scx, scy = fx + th_px * 0.28 + 1.5, fy + 1.5
    for y in range(int(scy - ry_sh - 2), int(scy + ry_sh + 3)):
        for x in range(int(scx - rx_sh - 2), int(scx + rx_sh + 3)):
            d = math.hypot((x - scx) / rx_sh, (y - scy) / ry_sh) + (vnoise(x * 0.2, y * 0.24, seed) - 0.5) * 0.2
            if d < 1.0:
                put_contact_shadow(skirt, x, y, int(115 * ((1.0 - d) ** 1.5)))

    full, stem_mask = blank(fw, fh), blank(fw, fh)
    # Compact dark Borkenfuß root flare sinking directly into emerald root-moss & dark soil (no tan side toes!)
    r_defs = [(-0.88, 0.95, 0, 0.48), (-0.36, 0.75, 2, 0.54), (0.38, 0.80, 2, 0.48), (0.86, 0.92, 0, 0.42)][:max(2, n_roots)]
    for ri, (udir, rm_len, dy_e, rm_r) in enumerate(r_defs):
        reach = rm_len * th_px + 2.0
        p0 = (fx + udir * th_px * 0.42, fy - max(4, int(th_px * 1.05)))
        p1 = (fx + udir * (th_px * 0.78 + reach * 0.42), fy + dy_e // 2)
        p2 = (fx + udir * (th_px * 0.72 + reach), fy + 1 + dy_e)
        draw_birch_limb(full, [p0, p1, p2], max(1.5, th_px * rm_r), 1.1, fy, max(10, borken_h), occ_y, seed + 11 + ri * 5, pad_x=6, juvenile=juvenile, force_borken=not juvenile)
        # Cushion of emerald moss & dark soil wrapping the root toe
        tx_end, ty_end = int(round(p2[0])), int(round(p2[1]))
        for dx_m in (-2, -1, 0, 1, 2):
            put(skirt, tx_end + dx_m, ty_end, MOSS[2 if (udir < 0 and dx_m <= 0) else 1])
            if abs(dx_m) <= 1:
                put(skirt, tx_end + dx_m, ty_end - 1, MOSS[3 if udir < 0 else 2])
        if glow_root is not None and ri < 2 and th_px >= 6:
            gx, gy = int((p1[0] + p2[0]) * 0.5), int(p1[1]) + 1
            put(glow_root, gx, gy, GLOW[2])
            put(glow_root, gx + (1 if udir > 0 else -1), gy, GLOW[1])

    for bi, (bpts, br0, br1, bjuv) in enumerate(boughs):
        draw_birch_limb(full, bpts, br0, br1, fy, borken_h, occ_y, seed + 41 + bi * 7, pad_x=pad_x, juvenile=bjuv)
    for si, (spts, sr0, sr1) in enumerate(stems):
        draw_birch_limb(full, spts, sr0, sr1, fy, borken_h, occ_y, seed + 71 + si * 13, pad_x=6, juvenile=juvenile)
        draw_birch_limb(stem_mask, spts, sr0, sr1, fy, borken_h, occ_y, seed + 71 + si * 13, pad_x=6, juvenile=juvenile)

    for y in range(2, fh - 1):
        for x in range(4, fw - 4):
            c = full[y][x]
            if c[3] == 0:
                continue
            if y <= cut_y + max(2, int(th_px * 0.34)):
                put(tupper, x, y, c)
            if y >= cut_y - max(2, int(th_px * 0.30)):
                if y >= fy - 2:
                    put(skirt, x, y, c)
                if abs(x - fx) <= int(th_px * 1.45 + 3) and y <= fy + 2 - int(abs(x - fx) * 0.08):
                    put(tbase, x, y, c)
                else:
                    put(skirt, x, y, c)

    selout_bark(tbase, pad_x=4, stop_y=fy - 3)
    selout_bark(tupper, pad_x=pad_x, stop_y=fy - 3, skip_bottom_y=cut_y - 2)
    draw_birch_cut_rings(tbase, fx, cut_y, max(2, int(th_px * 0.90)), max(2, int(th_px * 0.34)))
    for i in range(max(6, int(th_px * 1.5) + 3)):
        u = (i / float(max(1, int(th_px * 1.5) + 2))) * 2.0 - 1.0
        tx = fx + int(u * (th_px * 1.35 + 3) + (hsh(i, seed, 5) - 0.5) * 2.0)
        ty = fy + 1 + int((1.0 - u * u) * 1.8)
        tgt = tbase if abs(tx - fx) <= th_px + 2 else skirt
        for h_i in range(2 + (i % 2)):
            put(tgt, tx, ty - h_i, LEAF[3 if (u < 0 and h_i > 0) else 2] if i % 2 == 0 else MOSS[1 + h_i])
    for i in range(th_px + 2):
        ang, dist = hsh(i, seed, 17) * math.tau, (0.45 + 0.50 * hsh(i, seed, 23)) * (th_px * 2.0 + 5)
        lx, ly = int(fx + math.cos(ang) * dist), int(fy + math.sin(ang) * dist * 0.26) + 1
        put(skirt, lx, ly, CATKIN[2 if i % 2 == 0 else 1] if i % 3 == 0 else MOSS[2])
    if sorrel is not None:
        rx0, ry0 = fx + sorrel[0], fy + sorrel[1]
        for dy in range(-4, 5):
            for dx in range(-9, 10):
                d = math.hypot(dx / 9.0, dy / 4.5)
                if d <= 1.0:
                    put(skirt, rx0 + dx, ry0 + dy, MOSS[clampi(int((1.15 - d) * 3.6), 0, 4)])
        for ox, oy in ((-4, -1), (1, -2), (4, 1), (-1, 1)):
            put(skirt, rx0 + ox, ry0 + oy, SORREL[1])
            put(skirt, rx0 + ox + 1, ry0 + oy, SORREL[0])
        put(skirt, rx0 - 1, ry0, SORREL[2])
    return skirt, tbase, tupper, stem_mask


def draw_diamond_leaf(px, cx: int, cy: int, c_crev, c_shd, c_lit, c_spk, pad_x: int = 12) -> None:
    """Cohesive 4x5 pointed teardrop/diamond birch leaf cluster (zero 1x1 confetti!)."""
    w, h = len(px[0]), len(px)
    if not (pad_x + 2 <= cx < w - pad_x - 2 and 4 <= cy < h - 5):
        return
    if c_crev is not None:
        for dx, dy in ((0, 3), (1, 3), (-1, 2)):
            if px[cy + dy][cx + dx][3] > 0:
                put(px, cx + dx, cy + dy, c_crev)
    top_c = c_spk if c_spk is not None else c_lit
    for dx, dy, col in (
        (0, -2, top_c), (-1, -1, top_c), (0, -1, c_lit), (1, -1, c_shd),
        (-1, 0, c_lit), (0, 0, c_lit), (1, 0, c_shd), (2, 0, c_shd),
        (-1, 1, c_lit), (0, 1, c_shd), (1, 1, c_shd),
        (0, 2, c_shd),
    ):
        put(px, cx + dx, cy + dy, col)


def render_weeping_birch_cluster(px, glow_px, veils: list, tree_cx: int, crown_cy: int, crown_span: float, seed: int, pad_x: int = 12, catkins: int = 3, glows: int = 2) -> None:
    """Cohesive Betula pendula weeping canopy: 4x5 teardrop leaf clusters + 2-3 px wide weeping curtains (zero 1x1 noise!)."""
    h, w = len(px), len(px[0])
    # 1. Smooth dark-emerald upper dome core so upper boughs connect richly with zero donut holes
    for vi, (bx, by, rx, ry, drape, bz, bias) in enumerate(veils):
        irx, iry = max(3.5, rx * 0.72), max(3.0, ry * 0.66)
        for y in range(max(4, int(by - iry)), min(h - 4, int(by + iry * 0.85 + 1))):
            for x in range(max(pad_x + 2, int(bx - irx)), min(w - pad_x - 2, int(bx + irx + 1))):
                d = math.hypot((x - bx) / irx, (y - by) / iry) + (vnoise(x * 0.22, y * 0.22, seed + vi * 7) - 0.5) * 0.22
                if d <= 0.96:
                    put(px, x, y, LEAF[0 if (bz < -1.0 or y > by + 1) else 1])

    # 2. Upper arching teardrop leaf clusters + cohesive 2-3 px wide pendulous weeping ribbons (NO red dots!)
    items = []
    golden = 2.39996323
    for vi, (bx, by, rx, ry, drape, bz, bias) in enumerate(veils):
        n_arch = max(10, int((rx * ry) / 10.5))
        for k in range(n_arch):
            rr = ((k + 0.45) / float(n_arch)) ** 0.56
            ang = k * golden + seed * 0.13 + vi
            lx = int(round(bx + math.cos(ang) * rx * 0.88 * rr))
            ly = int(round(by + math.sin(ang) * ry * 0.80 * rr))
            nx, ny = (lx - bx) / max(1.0, rx), (ly - by) / max(1.0, ry)
            gx_t, gy_t = (lx - tree_cx) / max(12.0, crown_span), (ly - crown_cy) / max(10.0, crown_span * 0.75)
            lit = (-0.46 * nx - 0.58 * ny) + (-0.26 * gx_t - 0.30 * gy_t) + bias * 0.20 + (0.10 if bz > 1.2 else (-0.24 if bz < -1.2 else 0.0))
            items.append((bz, -ly, 0, lx, ly, 0, lit, bias, k + vi * 29))

        x_start, x_end = int(bx - rx * 0.90), int(bx + rx * 0.90)
        idx_s = 0
        for sx in range(x_start, x_end + 1, 4):
            idx_s += 1
            jx = sx + int((hsh(sx, vi, seed + 11) - 0.5) * 2.0)
            rel_x = clampf((jx - bx) / max(1.0, rx), -1.0, 1.0)
            arch_y = by + int((rel_x * rel_x) * ry * 0.42 + (hsh(sx, vi, seed + 19) - 0.30) * ry * 0.52)
            s_len = max(6, int(drape * (0.64 + 0.54 * hsh(sx, vi, seed + 29)) * (1.08 - 0.26 * abs(rel_x))))
            gx_t, gy_t = (jx - tree_cx) / max(12.0, crown_span), (arch_y - crown_cy) / max(10.0, crown_span * 0.75)
            lit = (-0.42 * rel_x + 0.06) + (-0.26 * gx_t - 0.28 * gy_t) + bias * 0.20 + (0.08 if bz > 1.2 else (-0.24 if bz < -1.2 else 0.0))
            items.append((bz + 0.05, -arch_y, 1, jx, arch_y, s_len, lit, bias, idx_s + vi * 53))

    items.sort(key=lambda it: (it[0], it[1], it[2]))
    catkin_slots, glow_slots = [], []
    for _, _, kind, sx, sy, s_len, lit, bias, s_id in items:
        ti = clampi(int((lit + 0.74) * 3.3), 1 if lit > -0.52 else 0, 5)
        c_crev = LEAF[max(0, ti - 2)]
        c_shd = LEAF[max(0, ti - 1)]
        c_lit = LEAF[min(5, ti + (1 if lit > 0.08 else 0))]
        c_spk = LEAF[6] if (bias >= 1 and lit > 0.54 and ti >= 4) else None
        if kind == 0:
            draw_diamond_leaf(px, sx, sy, c_crev, c_shd, c_lit, c_spk, pad_x)
        else:
            # Cohesive 2-3 px wide weeping ribbon of overlapping birch leaf droplets (zero red dots!)
            sway = (hsh(s_id, seed, 41) - 0.45) * 1.8
            tip_x, tip_y = sx, sy
            for dy in range(s_len + 1):
                t = dy / float(max(1, s_len))
                cx = clampi(int(round(sx + sway * (t ** 1.3))), pad_x + 2, w - pad_x - 3)
                cy = sy + dy
                if not (4 <= cy < h - 4):
                    break
                tip_x, tip_y = cx, cy
                t_drop = max(1, ti - int(t * 1.5))
                dl_crev = LEAF[max(0, t_drop - 2)]
                dl_shd = LEAF[max(0, t_drop - 1)]
                dl_lit = LEAF[min(5, t_drop + (1 if t < 0.48 and lit > 0.12 else 0))]
                ph = (dy + (s_id & 3)) % 4
                if dy == 0 and px[cy - 1][cx][3] > 0:
                    put(px, cx, cy - 1, dl_crev)
                if t < 0.78:
                    if ph < 3:
                        off_l = -1 if ((dy // 4 + s_id) & 1) == 0 else 0
                        put(px, cx + off_l - (0 if off_l == -1 else 1), cy, dl_lit)
                        put(px, cx, cy, dl_lit if ph == 1 else dl_shd)
                        put(px, cx + 1, cy, dl_shd)
                        if dy <= 2 and c_spk is not None:
                            put(px, cx - 1, cy, c_spk)
                    else:
                        # Scalloped petiole waist between hanging leaf droplets (prevents rigid vertical stripes!)
                        put(px, cx, cy, dl_crev if t > 0.35 else dl_shd)
                        put(px, cx + 1, cy, dl_shd)
                elif t < 0.92:
                    put(px, cx, cy, dl_lit)
                    put(px, cx + 1, cy, dl_shd)
                else:
                    put(px, cx, cy, dl_shd)
            if s_len >= 8 and 6 <= tip_y < h - 6:
                catkin_slots.append((hsh(s_id, seed, 73), tip_x, tip_y))
                glow_slots.append((hsh(s_id, seed, 89), tip_x, tip_y))

    catkin_slots.sort(key=lambda it: it[0], reverse=True)
    for _, cx, cy in catkin_slots[:catkins]:
        if pad_x + 2 <= cx < w - pad_x - 2 and cy + 3 < h - 3:
            put(px, cx, cy, CATKIN[1])
            put(px, cx, cy + 1, CATKIN[3])
            put(px, cx + 1, cy + 1, CATKIN[2])
            put(px, cx, cy + 2, CATKIN[3])
            put(px, cx + 1, cy + 2, CATKIN[1])
            put(px, cx, cy + 3, CATKIN[0])
    if glow_px is not None:
        glow_slots.sort(key=lambda it: it[0], reverse=True)
        for _, gx, gy in glow_slots[:glows]:
            if pad_x + 2 <= gx < w - pad_x - 2 and 5 <= gy < h - 4:
                put(glow_px, gx, gy, GLOW[3])
                put(glow_px, gx, gy + 1, GLOW[2])


def finish_birch_foliage(px, pad_x: int = 12) -> None:
    h, w = len(px), len(px[0])
    # Anti-confetti pass: merge any isolated 1x1 leaf pixel into its cardinal neighbor cluster!
    leaf_set = set(LEAF)
    snap = [row[:] for row in px]
    for y in range(3, h - 3):
        for x in range(pad_x + 1, w - pad_x - 1):
            c = snap[y][x]
            if c in leaf_set:
                nbs = [snap[y + dy][x + dx] for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)) if snap[y + dy][x + dx] in leaf_set]
                if len(nbs) >= 3 and c not in nbs:
                    px[y][x] = nbs[0]
    rim = []
    for y in range(2, h - 2):
        for x in range(pad_x, w - pad_x):
            if px[y][x][3] == 0:
                nb = [(dx, dy) for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)) if px[y + dy][x + dx][3] > 200]
                if nb:
                    sun = any(dy > 0 or dx > 0 for dx, dy in nb) and not any(dy < 0 and dx < 0 for dx, dy in nb)
                    rim.append((x, y, OUT_LEAF_SUN if sun else OUT_LEAF_SHADE))
    for x, y, col in rim:
        put(px, x, y, col)


def _stem_runs_at(stem_mask, y: int) -> list:
    """Returns contiguous horizontal runs (xl, xr) of actual opaque stem pixels at row y (never bridges multi-stem gaps!)."""
    if not (0 <= y < len(stem_mask)):
        return []
    row, w = stem_mask[y], len(stem_mask[0])
    runs, x = [], 0
    while x < w:
        if row[x][3] > 0:
            xl = x
            while x + 1 < w and row[x + 1][3] > 0:
                x += 1
            runs.append((xl, x))
        x += 1
    runs.sort(key=lambda r: r[1] - r[0], reverse=True)
    return runs


def _has_stem_box(stem_mask, cx: int, cy: int, rx: int = 3, ry: int = 3) -> bool:
    h, w = len(stem_mask), len(stem_mask[0])
    if not (ry <= cy < h - ry and rx <= cx < w - rx):
        return False
    return all(stem_mask[cy + dy][cx + dx][3] > 0 for dy in (-ry, 0, ry) for dx in range(-rx, rx + 1))


def draw_birch_sap_only(px, glow_px, stem_mask, y_mid: int) -> None:
    """Crystalline moon-silver / champagne Birkensaft droplets strictly on actual stem pixels."""
    for idx, dy_off in enumerate((-5, 3, 9)):
        ay = y_mid + dy_off
        runs = _stem_runs_at(stem_mask, ay)
        if not runs:
            continue
        xl, xr = runs[min(idx % 2, len(runs) - 1)]
        if xr - xl < 5:
            continue
        u = -0.18 if idx == 0 else (0.16 if idx == 1 else 0.0)
        ax = clampi(int((xl + xr) * 0.5 + u * (xr - xl) * 0.4), xl + 2, xr - 2)
        put(px, ax, ay - 2, BORKEN[1])
        put(px, ax, ay - 1, SAP[2])
        put(px, ax - 1, ay, SAP[3])
        put(px, ax, ay, SAP[1])
        put(px, ax, ay + 1, SAP[0])
        if glow_px is not None:
            put(glow_px, ax - 1, ay, GLOW[3])
            put(glow_px, ax, ay, CHAGA_FIRE[3])


def build_birch_traits(fw: int, fh: int, fx: int, fy: int, cut_y: int, fork_y: int, th_px: int, stem_mask, seed: int, base_col: int, glow_col: int, hollow_at=None, pad_x: int = 12):
    """Generates 11 birch-authentic modular trait overlays strictly clamped to actual stem pixels (zero gap bridging!)."""
    ivy_dark = hexc("162c28")
    # 1. Moss & Lichen strictly on opaque stem pixels (never bridges twin/triple-stem air gaps!)
    m_base, m_lich = blank(fw, fh), blank(fw, fh)
    for y in range(fork_y, fy + 2):
        for xl, xr in _stem_runs_at(stem_mask, y):
            ws = max(1, xr - xl)
            for x in range(xl + 1, xr):
                u = (x - xl) / float(ws) * 2.0 - 1.0
                nv = vnoise(x * 0.24, y * 0.24, seed + 101)
                if y >= fy - int(th_px * 2.5) and nv + (y - (fy - th_px * 2.5)) / max(6.0, th_px * 2.5) * 0.48 - u * 0.22 > 0.72:
                    put(m_base, x, y, MOSS[clampi(int((0.55 - 0.4 * u + nv - 0.65) * 3.6), 0, 3)])
                lv = vnoise(x * 0.30, y * 0.28, seed + 131)
                if fork_y + 4 <= y <= cut_y - 4 and lv > 0.78 and abs(u + 0.1) < 0.72:
                    put(m_lich, x, y, LICHEN[2 if (u < 0 and lv > 0.85) else (1 if u < 0.3 else 0)])

    # 2. Ivy / Peeling Bark: [curled_peeling_paper_bark (Rollrinde), dark_basal_woodland_ivy]
    p_curl, ivy_b = blank(fw, fh), blank(fw, fh)
    for idx, frac in enumerate((0.30, 0.50, 0.68)):
        cy = fork_y + int((cut_y - fork_y) * frac)
        runs = _stem_runs_at(stem_mask, cy)
        if runs:
            xl, xr = runs[0]
            if xr - xl >= 6:
                side = -1 if idx % 2 == 0 else 1
                bx = xl if side < 0 else xr
                for dy in (-2, -1, 0, 1):
                    if stem_mask[cy + dy][bx - side][3] > 0:
                        put(p_curl, bx - side, cy + dy, CINNAMON[2 if dy < 0 else 1])
                        put(p_curl, bx, cy + dy, CINNAMON[1 if dy < 0 else 0])
                put(p_curl, bx + side, cy - 1, WHITE_BARK[5])
                put(p_curl, bx + side * 2, cy, WHITE_BARK[4])
                put(p_curl, bx + side * 2, cy + 1, OUT_BARK)
                put(p_curl, bx + side, cy + 1, CINNAMON[2])
    y_ivy_top = fork_y + int((fy - fork_y) * 0.36)
    for y in range(y_ivy_top, fy + 1):
        runs = _stem_runs_at(stem_mask, y)
        if runs:
            xl, xr = runs[0]
            if xr - xl >= 5:
                t_c = (fy - y) / max(1.0, float(fy - y_ivy_top))
                vx = clampi(int(xl + 1 + (xr - xl) * 0.34 + math.sin(y * 0.22 + seed) * 1.4), xl + 1, xr - 1)
                put(ivy_b, vx, y, ivy_dark)
                if hsh(vx, y, seed + 211) < (0.80 - 0.35 * t_c):
                    for ox in (-1, 1):
                        lx = clampi(vx + ox, xl + 1, xr - 1)
                        if stem_mask[y][lx][3] > 0:
                            put(ivy_b, lx, y + 1, ivy_dark)
                            put(ivy_b, lx, y, LEAF[2 if ox > 0 else 3])

    # 3. Hollows strictly backed by solid stem pixels across [x-3..x+3]!
    h_peck, h_chev, h_root = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    yp = hollow_at[1] if hollow_at is not None else (fork_y + max(10, int((fy - fork_y) * 0.34)))
    runs_p = _stem_runs_at(stem_mask, yp)
    if runs_p:
        xl, xr = runs_p[0]
        px_c = clampi((xl + xr) // 2, xl + 3, xr - 3)
        if xr - xl >= 7 and _has_stem_box(stem_mask, px_c, yp, 3, 3):
            for dy in range(-3, 4):
                for dx in range(-2, 3):
                    d = math.hypot(dx / 2.1, dy / 3.0)
                    if d <= 1.2 and stem_mask[yp + dy][px_c + dx][3] > 0:
                        put(h_peck, px_c + dx, yp + dy, OUT_BARK if d < 0.65 else (BORKEN[0] if d < 0.92 else BIRCH_WOOD[2]))
    yc = fork_y + max(10, int((fy - fork_y) * 0.42))
    runs_c = _stem_runs_at(stem_mask, yc)
    if runs_c:
        xl, xr = runs_c[0]
        ccx = (xl + xr) // 2
        hw_c = min(max(2, (xr - xl) // 3), 4)
        for dx in range(-hw_c, hw_c + 1):
            yy = yc + abs(dx) // 2
            if stem_mask[yy][ccx + dx][3] > 0:
                put(h_chev, ccx + dx, yy, BORKEN[0])
                put(h_chev, ccx + dx, yy + 1, BORKEN[1])
    yr = fy - max(5, int(th_px * 0.62))
    runs_r = _stem_runs_at(stem_mask, yr)
    if runs_r:
        xl, xr = runs_r[0]
        rcx = (xl + xr) // 2
        for dy in range(-4, 4):
            for dx in range(-3, 4):
                d = math.hypot(dx / 2.6, dy / 3.6)
                if d <= 1.15 and 0 <= yr + dy < fh and stem_mask[yr + dy][clampi(rcx + dx, xl, xr)][3] > 0:
                    put(h_root, clampi(rcx + dx, xl + 1, xr - 1), yr + dy, OUT_BARK if d < 0.65 else BORKEN[1 if dx > 0 else 2])

    # 4. Fungi strictly anchored on actual stem runs: [cream Birkenporling, charred Funken-Chaga]
    f_poly, f_chaga, fg_chaga = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    poly_pal = {"s": BIRCH_WOOD[3], "W": BIRCH_WOOD[2], "t": BIRCH_WOOD[1], "b": BIRCH_WOOD[0]}
    yf = fork_y + int((fy - fork_y) * 0.54)
    for idx, dy_o in enumerate((-4, 4)):
        yy = yf + dy_o
        runs_f = _stem_runs_at(stem_mask, yy)
        if runs_f:
            xl, xr = runs_f[min(idx, len(runs_f) - 1)]
            if xr - xl >= 6:
                bx = (xl + xr) // 2
                for ry, rstr in enumerate((".ssss.", "sWWWWs", ".ttbb.")):
                    for rx, ch in enumerate(rstr):
                        if ch in poly_pal:
                            put(f_poly, bx + rx - 3, yy + ry - 1, poly_pal[ch])
    runs_ch = _stem_runs_at(stem_mask, yf)
    if runs_ch:
        xl, xr = runs_ch[-1]
        if xr - xl >= 6:
            cx_g = xr - 2
            chaga_rows = [".bbb..", "bBfFb.", "bFTqBb", "bfFbb.", ".bbb.."]
            cpal = {"b": BORKEN[0], "B": BORKEN[1], "f": CHAGA_FIRE[1], "F": CHAGA_FIRE[2], "T": CHAGA_FIRE[3], "q": GLOW[2]}
            for ry, rstr in enumerate(chaga_rows):
                for rx, ch in enumerate(rstr):
                    if ch in cpal:
                        put(f_chaga, cx_g + rx - 2, yf + ry - 2, cpal[ch])
                        if ch in ("f", "F", "T", "q"):
                            put(fg_chaga, cx_g + rx - 2, yf + ry - 2, GLOW[2] if ch == "q" else CHAGA_FIRE[3 if ch == "T" else 2])

    # 5. Weeping Sprigs anchored to outermost left/right stem edges
    sp_l, sp_r = blank(fw, fh), blank(fw, fh)
    ys = fork_y + int((fy - fork_y) * 0.46)
    runs_s = _stem_runs_at(stem_mask, ys)
    if runs_s:
        all_xl = min(r[0] for r in runs_s)
        all_xr = max(r[1] for r in runs_s)
        for side, sx0, tgt in ((-1, all_xl, sp_l), (1, all_xr, sp_r)):
            tx1, ty1 = sx0 + side * 5, ys - 2
            draw_birch_limb(tgt, [(sx0, ys), (sx0 + side * 3, ys - 2), (tx1, ty1)], 1.1, 0.8, fy, 0, -999, seed + 301, pad_x=pad_x, juvenile=True)
            lf = blank(fw, fh)
            draw_diamond_leaf(lf, tx1, ty1 + 1, LEAF[1], LEAF[3], LEAF[5], LEAF[6], pad_x)
            draw_diamond_leaf(lf, tx1 + side, ty1 + 4, LEAF[1], LEAF[2], LEAF[4], None, pad_x)
            put(lf, tx1 + side, ty1 + 7, CATKIN[2])
            put(lf, tx1 + side, ty1 + 8, CATKIN[3])
            finish_birch_foliage(lf, pad_x=pad_x)
            blit(tgt, lf, 0, 0)

    frames = [m_base, m_lich, p_curl, ivy_b, h_peck, h_chev, h_root, f_poly, f_chaga, sp_l, sp_r]
    traits_meta = {
        "moss": [base_col + 0, base_col + 1],
        "ivy": [base_col + 2, base_col + 3],
        "hollow": [base_col + 4, base_col + 5, base_col + 6],
        "fungi": [base_col + 7, base_col + 8],
        "fungi_glow": [-1, glow_col],
        "sprig": [base_col + 9, base_col + 10],
    }
    return frames, fg_chaga, traits_meta


ICON_PAL = {
    "W": WHITE_BARK[5], "w": WHITE_BARK[4], "l": WHITE_BARK[3], "s": WHITE_BARK[1], "d": BORKEN[0], "D": BORKEN[1],
    "I": BIRCH_WOOD[3], "i": BIRCH_WOOD[2], "u": BIRCH_WOOD[1], "U": BIRCH_WOOD[0],
    "c": CINNAMON[2], "C": CINNAMON[1], "r": CINNAMON[0],
    "S": SAP[3], "p": SAP[2], "P": SAP[1], "a": SAP[0],
    "k": COPPER[2], "L": LEAF[5], "g": LEAF[4], "G": LEAF[2],
    "Y": CATKIN[3], "y": CATKIN[2], "o": CATKIN[1], "O": CATKIN[0],
    "F": CHAGA_FIRE[3], "f": CHAGA_FIRE[2], "e": CHAGA_FIRE[1], "q": GLOW[2], "Q": GLOW[3],
}

# 12x12 interiors placed at (2..13, 2..13) + 1px #1e162b outline => >= 1px transparent border on all 4 sides!
ICONS = {
    "birch_wood": [
        "......III...", "....IIiiWW..", "...IiuuiWWd.", "..IiuUuiwWw.",
        "..IiuuiWWls.", ".WWiuuiwdls.", ".WdwIIwlDls.", "..Wwllwlls..",
        "...Wwddls...", "....ssss....", "............", "............",
    ],
    "birch_bark": [
        "....WWWW....", "..WWwwdWW...", ".WWwlccCWW..", ".WdwccrCcls.",
        ".WwccCrclls.", "..WccrCCwdl.", "..wlCCCWwls.", "...wlcWWls..",
        "....wwdls...", ".....sss....", "............", "............",
    ],
    "birch_sap": [
        ".....p......", "....pSp.....", "...pSSpp....", "..pSSpppP...",
        "..pSppppP...", "..PppppPP...", "..PpppPPP...", "...PPaPP....",
        "....aaa.....", "............", "............", "............",
    ],
    "birch_catkin": [
        ".....kk.....", "....kLLg....", "...kkLgG....", "..oYkok.....",
        "..YyooYk....", "..yYoYyY....", "..yoyyYo....", "..oO.yYo....",
        "..O..oOo....", "......O.....", "............", "............",
    ],
    "birch_chaga": [
        "....ddDD....", "..ddDfeDdd..", ".dDdfFFqDdd.", ".dDefFqQdDd.",
        ".ddDfefDddd.", "..dDDfeDdWw.", "..ddDDDDWdw.", "...ddddWWls.",
        ".....swwss..", "............", "............", "............",
    ],
}


def build_birch_icons() -> list:
    out_paths = []
    for name, rows in ICONS.items():
        px = blank(16, 16)
        for ry, row in enumerate(rows):
            for rx, ch in enumerate(row):
                if ch in ICON_PAL:
                    put(px, rx + 2, ry + 2, ICON_PAL[ch])
        rim = [(x, y) for y in range(16) for x in range(16) if px[y][x][3] == 0 and any(0 <= x + dx < 16 and 0 <= y + dy < 16 and px[y + dy][x + dx][3] > 0 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)))]
        for x, y in rim:
            put(px, x, y, OUT_ICON)
        p = ROOT / "items" / f"{name}.png"
        write_png(p, 16, 16, px)
        out_paths.append(p)
    return out_paths
