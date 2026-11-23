#!/usr/bin/env python3
"""Botanical pixel-art engine for Glimmtal-Wildapfel (Malus sylvestris glimmensis):
  1. Spiral Drehwuchs Scaly Bark (#241724..#b89188) winding ~35 deg up muscular, low-vaulted orchard trunks,
     plus warm rosy-salmon heartwood (#9e4e48, #c97868) & cream sapwood (#f0d4b4).
  2. Cohesive 4x4..6x5 Cupped Oval Apple-Leaf Rosettes (#1c3b2e..#b4e286, zero 1x1 speckle noise) +
     Dual Phenology Overlays: lush 5-petaled pink/white Blossom Corymbs & plump crimson-gold Crab-Apples.
  3. Orchard Traits (Golden Xanthoria lichen, Sacred Mistletoe Ball with glowing pearl berries, Wild Rose vine,
     spiral bee-clefts, Pholiota clusters, thorny blossom spurs) + 5 crisp 16x16 icons (#201424 outline).
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

# Palettes (strictly zero #000000)
LEAF = [hexc(c) for c in ("142b22", "1c3b2e", "316444", "549250", "82bf64", "b4e286")]
OUT_BARK, OUT_ICON = hexc("241724"), hexc("201424")
OUT_LEAF_SUN, OUT_LEAF_SHADE = hexc("264632"), hexc("132820")

# Spiral Drehwuchs scaly cinnamon-terracotta bark & salmon-rose apple heartwood
BARK = [hexc(c) for c in ("2b1b28", "3c2736", "684850", "8f696b", "b89188")]
THORN_BARK = [hexc(c) for c in ("2b1824", "4c2838", "7a4452", "a86a72")]
HEARTWOOD = [hexc(c) for c in ("733434", "9e4e48", "c97868", "f0d4b4")]

# Dual Phenology: Spring Apple Blossoms & Autumn Wild Crab-Apples
BLOSSOM = [hexc(c) for c in ("7a2648", "a83e62", "e88aa8", "ffdce8", "fff6fa")]
STAMEN = hexc("ffd866")
BLOSSOM_GLOW = hexc("d8f8ff")
FRUIT = [hexc(c) for c in ("5c1628", "8c2030", "cc363e", "f27e3a", "ffd868")]

# Lichens, Mistletoe, Moss & Glows
MOSS = [hexc(c) for c in ("1c3c34", "2d5e46", "468252", "68a862")]
XANTHORIA = [hexc(c) for c in ("8c5818", "b87c28", "e6b448")]
PARMELIA = [hexc("6e8882"), hexc("a4c2b8"), hexc("d6ebe2")]
MISTLE = [hexc(c) for c in ("1d4234", "2d5e46", "5ca062", "92cf7e")]
PEARL = [hexc("b8dcd8"), hexc("d6f5ef"), hexc("ffffff"), hexc("9ef8ee")]
GLOW = [hexc(c) for c in ("2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
PHOLIOTA = [hexc(c) for c in ("5c3014", "8f521c", "cc882c", "f4c458")]
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
            col = (24, 18, 32, col[3])
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


def shade_apple_bark(x: int, y: int, u: float, along: float, fy: int, occ: float, seed: int, thorny_whip: bool = False):
    """Spiral ~35 deg Drehwuchs helical grooves + warm scaly cinnamon-terracotta apple bark plates."""
    nz = math.sqrt(max(0.06, 1.0 - u * u))
    light = -0.60 * u + 0.54 * nz - occ
    if thorny_whip:
        return THORN_BARK[clampi(int((light + 0.42) * 3.6), 0, 3)]
    # ~35 deg helical torsion winding diagonally up the bole + curved scaly plates!
    helix = u * 2.5 + (fy - y) * 0.082 + (vnoise(x * 0.14, y * 0.12, seed) - 0.5) * 0.55
    h_frac = helix - math.floor(helix)
    sc_row = math.floor((along + math.floor(helix) * 4.0) / 6.5)
    s_frac = ((along + math.floor(helix) * 4.0) / 6.5) - sc_row
    groove = (h_frac < 0.22) or (h_frac < 0.40 and s_frac < 0.16 and hsh(math.floor(helix), sc_row, seed + 9) > 0.42)
    flake_edge = (not groove) and (0.22 <= h_frac < 0.44) and (s_frac < 0.65) and (u < 0.28)
    s = light + (-0.38 if groove else (0.18 if flake_edge else math.sin(h_frac * math.pi) * 0.08))
    bi = clampi(int((s + 0.40) * 4.2), 0, 4)
    if u > 0.76:
        bi = min(bi, 1)
    return BARK[bi]


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


def draw_apple_cut_rings(px, cx: int, cy: int, rx: int, ry: int) -> None:
    for y in range(cy - ry - 1, cy + ry + 2):
        for x in range(cx - rx - 1, cx + rx + 2):
            d = math.hypot((x - cx) / max(1.0, rx), (y - cy) / max(1.0, ry))
            if d <= 1.06:
                if d > 0.88:
                    put(px, x, y, OUT_BARK if d > 0.98 else BARK[1])
                elif d > 0.66:
                    put(px, x, y, HEARTWOOD[3])
                else:
                    ring = int(d * max(2.8, rx * 0.65)) % 2
                    put(px, x, y, HEARTWOOD[2 if ring == 0 else 1] if d > 0.24 else HEARTWOOD[0])


def draw_apple_kerf(px, cx: int, cut_y: int, r_trunk: int, deep: bool = False) -> None:
    depth = max(3, int(r_trunk * (0.92 if deep else 0.54)))
    h_n = max(3, int(r_trunk * (0.60 if deep else 0.40)))
    xr = cx + r_trunk
    for dy in range(-h_n, 2):
        span = int(depth * (1.0 - abs(dy + h_n * 0.35) / (h_n + 1.5)))
        for k in range(max(1, span)):
            col = BARK[0] if dy >= 0 else (HEARTWOOD[0] if k > span * 0.68 else (HEARTWOOD[3] if k < 2 else HEARTWOOD[2]))
            put(px, xr - k, cut_y + dy, col)


def draw_apple_limb(px, pts: list, r0: float, r1: float, fy: int, occ_y: int, seed: int, pad_x: int = 8, thorny: bool = False) -> None:
    w, h = len(px[0]), len(px)
    sp = sample_spline(pts, max(16, len(pts) * 14))
    n = len(sp) - 1
    s_acc = 0.0
    for i, (cx, cy) in enumerate(sp):
        if i > 0:
            s_acc += math.hypot(cx - sp[i - 1][0], cy - sp[i - 1][1])
        t = i / float(max(1, n))
        rad = max(0.8, r0 + (r1 - r0) * (t ** 0.82) + 0.28 * math.sin(t * 9.0 + seed))
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
                occ = clampf((occ_y - px_y) / 18.0, 0.0, 0.72) if occ_y > -900 else 0.0
                put(px, px_x, px_y, shade_apple_bark(px_x, px_y, u, s_acc, fy, occ, seed, thorny))


def build_apple_skeleton(fw: int, fh: int, fx: int, fy: int, cut_y: int, occ_y: int, th_px: int, stems: list, boughs: list, seed: int, n_roots: int = 4, sorrel=None, glow_root=None, pad_x: int = 12, thorny: bool = False, split_hollow: bool = False, petals: bool = False):
    """Builds gnarled Drehwuchs apple trunk(s), muscular root flare & compact vaulted orchard scaffold."""
    skirt, tbase, tupper = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    rx_sh, ry_sh = th_px * 2.4 + 7.0, max(4.0, th_px * 0.76 + 3.0)
    scx, scy = fx + th_px * 0.28 + 1.5, fy + 1.5
    for y in range(int(scy - ry_sh - 2), int(scy + ry_sh + 3)):
        for x in range(int(scx - rx_sh - 2), int(scx + rx_sh + 3)):
            d = math.hypot((x - scx) / rx_sh, (y - scy) / ry_sh) + (vnoise(x * 0.2, y * 0.24, seed) - 0.5) * 0.2
            if d < 1.0:
                put_contact_shadow(skirt, x, y, int(115 * ((1.0 - d) ** 1.5)))

    full, stem_mask = blank(fw, fh), blank(fw, fh)
    r_defs = [(-0.92, 1.05, 0, 0.48), (-0.38, 0.80, 2, 0.54), (0.40, 0.84, 2, 0.48), (0.90, 1.00, 0, 0.42)][:max(2, n_roots)]
    for ri, (udir, rm_len, dy_e, rm_r) in enumerate(r_defs):
        reach = rm_len * th_px + 2.5
        p0 = (fx + udir * th_px * 0.42, fy - max(4, int(th_px * 1.0)))
        p1 = (fx + udir * (th_px * 0.78 + reach * 0.42), fy + dy_e // 2)
        p2 = (fx + udir * (th_px * 0.74 + reach), fy + 1 + dy_e)
        draw_apple_limb(full, [p0, p1, p2], max(1.5, th_px * rm_r), 1.1, fy, occ_y, seed + 11 + ri * 5, pad_x=6, thorny=thorny)
        tx_e, ty_e = int(round(p2[0])), int(round(p2[1]))
        for dx_m in (-2, -1, 0, 1, 2):
            put(skirt, tx_e + dx_m, ty_e, MOSS[2 if (udir < 0 and dx_m <= 0) else 1])
        if glow_root is not None and ri < 2 and th_px >= 7:
            gx, gy = int((p1[0] + p2[0]) * 0.5), int(p1[1]) + 1
            put(glow_root, gx, gy, GLOW[2])
            put(glow_root, gx + (1 if udir > 0 else -1), gy, GLOW[0])

    for bi, (bpts, br0, br1) in enumerate(boughs):
        draw_apple_limb(full, bpts, br0, br1, fy, occ_y, seed + 41 + bi * 7, pad_x=pad_x, thorny=thorny)
    for si, (spts, sr0, sr1) in enumerate(stems):
        draw_apple_limb(full, spts, sr0, sr1, fy, occ_y, seed + 71 + si * 13, pad_x=6, thorny=thorny)
        draw_apple_limb(stem_mask, spts, sr0, sr1, fy, occ_y, seed + 71 + si * 13, pad_x=6, thorny=thorny)

    if split_hollow:
        # Ancient hollowed veteran heart bridged diagonally by a living twisted Drehwuchs bark rib!
        hcy = fy - 44
        for dy in range(-12, 13):
            for dx in range(-5, 6):
                if math.hypot(dx / 4.8, dy / 12.0) <= 1.0:
                    put(full, fx - 2 + dx, hcy + dy, OUT_BARK if abs(dx) < 3 else BARK[0])
        draw_apple_limb(full, [(fx - 8, hcy + 11), (fx - 1, hcy), (fx + 5, hcy - 10)], 2.6, 2.2, fy, occ_y, seed + 99, pad_x=12)

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
                if abs(x - fx) <= int(th_px * 1.48 + 3) and y <= fy + 2 - int(abs(x - fx) * 0.08):
                    put(tbase, x, y, c)
                else:
                    put(skirt, x, y, c)

    selout_bark(tbase, pad_x=4, stop_y=fy - 3)
    selout_bark(tupper, pad_x=pad_x, stop_y=fy - 3, skip_bottom_y=cut_y - 2)
    draw_apple_cut_rings(tbase, fx, cut_y, max(2, int(th_px * 0.92)), max(2, int(th_px * 0.34)))
    for i in range(max(6, int(th_px * 1.5) + 3)):
        u = (i / float(max(1, int(th_px * 1.5) + 2))) * 2.0 - 1.0
        tx = fx + int(u * (th_px * 1.35 + 3) + (hsh(i, seed, 5) - 0.5) * 2.0)
        ty = fy + 1 + int((1.0 - u * u) * 1.8)
        tgt = tbase if abs(tx - fx) <= th_px + 2 else skirt
        for h_i in range(2 + (i % 2)):
            put(tgt, tx, ty - h_i, LEAF[3 if (u < 0 and h_i > 0) else 2] if i % 2 == 0 else MOSS[1 + h_i])
    if petals:
        for i in range(16):
            ang, dist = hsh(i, seed, 17) * math.tau, (0.35 + 0.62 * hsh(i, seed, 23)) * (th_px * 2.2 + 8)
            px_p, py_p = int(fx + math.cos(ang) * dist), int(fy + math.sin(ang) * dist * 0.28) + 1
            put(skirt, px_p, py_p, BLOSSOM[4 if i % 3 == 0 else 2])
            if i % 2 == 0:
                put(skirt, px_p + 1, py_p, BLOSSOM[3])
    if sorrel is not None:
        rx0, ry0 = fx + sorrel[0], fy + sorrel[1]
        for dy in range(-4, 5):
            for dx in range(-9, 10):
                d = math.hypot(dx / 9.0, dy / 4.5)
                if d <= 1.0:
                    put(skirt, rx0 + dx, ry0 + dy, MOSS[clampi(int((1.15 - d) * 3.2), 0, 3)])
        for ox, oy in ((-4, -1), (1, -2), (4, 1), (-1, 1)):
            put(skirt, rx0 + ox, ry0 + oy, BLOSSOM[4])
            put(skirt, rx0 + ox + 1, ry0 + oy, BLOSSOM[2])
        put(skirt, rx0 - 1, ry0, STAMEN)
    return skirt, tbase, tupper, stem_mask


def draw_apple_rosette(px, cx: int, cy: int, c_crev, c_shd, c_mid, c_lit, pad_x: int = 12) -> None:
    """Cohesive 6x5 cupped oval apple-leaf rosette puff (zero 1x1 confetti!)."""
    w, h = len(px[0]), len(px)
    if not (pad_x + 3 <= cx < w - pad_x - 3 and 4 <= cy < h - 4):
        return
    if c_crev is not None:
        for dx, dy in ((-1, 2), (0, 2), (1, 2), (2, 1)):
            if px[cy + dy][cx + dx][3] > 0:
                put(px, cx + dx, cy + dy, c_crev)
    for dx, dy, col in (
        (-1, -2, c_lit), (0, -2, c_lit), (1, -2, c_mid),
        (-2, -1, c_lit), (-1, -1, c_lit), (0, -1, c_lit), (1, -1, c_mid), (2, -1, c_mid),
        (-2, 0, c_lit), (-1, 0, c_mid), (0, 0, c_shd), (1, 0, c_mid), (2, 0, c_shd),
        (-1, 1, c_mid), (0, 1, c_shd), (1, 1, c_shd),
    ):
        put(px, cx + dx, cy + dy, col)


def draw_blossom_corymb(px, glow_px, cx: int, cy: int, size_kind: int, bright: bool, emit_glow: bool, pad_x: int = 12) -> None:
    """Varied organic apple-blossom corymbs (0=small rosebud, 1=5-petal flower, 2=lush double corymb) without sticker rings!"""
    w, h = len(px[0]), len(px)
    if not (pad_x + 4 <= cx < w - pad_x - 4 and 5 <= cy < h - 5):
        return
    p_hi = BLOSSOM[4] if bright else BLOSSOM[3]
    p_mid = BLOSSOM[3] if bright else BLOSSOM[2]
    p_blush = BLOSSOM[2] if bright else BLOSSOM[1]
    if size_kind == 0:
        # Unopened carmine-pink blossom bud pair
        for dx, dy, col in ((0, -1, p_mid), (-1, 0, p_blush), (0, 0, BLOSSOM[1]), (1, 0, BLOSSOM[0]), (0, 1, LEAF[1])):
            put(px, cx + dx, cy + dy, col)
    elif size_kind == 1:
        # Classic 5-petaled open apple flower
        for dx, dy, col in (
            (-1, -2, p_hi), (1, -2, p_mid),
            (-2, -1, p_hi), (-1, -1, p_hi), (0, -1, p_mid), (1, -1, p_hi),
            (-2, 0, p_mid), (-1, 0, STAMEN), (0, 0, p_hi), (1, 0, p_blush),
            (-1, 1, p_blush), (0, 1, BLOSSOM[1]), (1, 1, BLOSSOM[0]),
        ):
            put(px, cx + dx, cy + dy, col)
    else:
        # Lush multi-blossom corymb garland (2 overlapping flowers + carmine bud)
        for dx, dy, col in (
            (-2, -2, p_hi), (0, -2, p_hi), (2, -2, p_mid),
            (-3, -1, p_hi), (-2, -1, p_hi), (-1, -1, STAMEN), (0, -1, p_hi), (1, -1, p_mid), (2, -1, p_hi), (3, -1, BLOSSOM[1]),
            (-3, 0, p_mid), (-2, 0, p_mid), (-1, 0, p_hi), (0, 0, p_blush), (1, 0, STAMEN), (2, 0, p_mid), (3, 0, BLOSSOM[0]),
            (-2, 1, p_blush), (-1, 1, BLOSSOM[1]), (1, 1, p_blush), (2, 1, BLOSSOM[1]),
        ):
            put(px, cx + dx, cy + dy, col)
    if glow_px is not None and emit_glow and size_kind >= 1:
        put(glow_px, cx - 1, cy - 1, BLOSSOM_GLOW)


def draw_crab_apple(px, cx: int, cy: int, tucked: bool = False, pad_x: int = 12) -> None:
    """Plump 4x4 crimson-and-apricot-gold wild crab-apple nestled under an overhanging leaf cap."""
    w, h = len(px[0]), len(px)
    if not (pad_x + 3 <= cx < w - pad_x - 3 and 5 <= cy < h - 5):
        return
    put(px, cx, cy - 2, BARK[1])
    for dx, dy, col in (
        (-1, -1, FRUIT[4]), (0, -1, FRUIT[3]), (1, -1, FRUIT[2]),
        (-1, 0, FRUIT[3]), (0, 0, FRUIT[2]), (1, 0, FRUIT[1]),
        (-1, 1, FRUIT[1]), (0, 1, FRUIT[0]), (1, 1, FRUIT[0]),
    ):
        put(px, cx + dx, cy + dy, col)
    if tucked:
        put(px, cx - 1, cy - 2, LEAF[3])
        put(px, cx + 1, cy - 2, LEAF[2])


def selout_against_sky_only(overlay_px, leaf_px, pad_x: int, out_sun, out_shade) -> None:
    """Outlines blossoms/fruits ONLY where they protrude past leaf_px into open sky (zero sticker rings on leaves!)."""
    h, w = len(overlay_px), len(overlay_px[0])
    rim = []
    for y in range(2, h - 2):
        for x in range(pad_x, w - pad_x):
            if overlay_px[y][x][3] == 0 and leaf_px[y][x][3] == 0:
                nb = [(dx, dy) for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)) if overlay_px[y + dy][x + dx][3] > 200]
                if nb:
                    sun = any(dy > 0 or dx > 0 for dx, dy in nb) and not any(dy < 0 and dx < 0 for dx, dy in nb)
                    rim.append((x, y, out_sun if sun else out_shade))
    for x, y, col in rim:
        put(overlay_px, x, y, col)


def finish_apple_foliage(px, pad_x: int = 12, outline_top=None, outline_shade=None) -> None:
    h, w = len(px), len(px[0])
    ot = outline_top or OUT_LEAF_SUN
    os = outline_shade or OUT_LEAF_SHADE
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
                    rim.append((x, y, ot if sun else os))
    for x, y, col in rim:
        put(px, x, y, col)


def render_apple_cluster_and_phenology(fw: int, fh: int, bolsters: list, tree_cx: int, crown_cy: int, crown_span: float, seed: int, pad_x: int = 12, make_pheno: bool = True, glows: int = 2):
    """Renders cupped oval leaf-rosette cluster + 1-to-1 matched blossom_col, blossom_glow, and fruit_col!"""
    leaf_px, leaf_glow = blank(fw, fh), blank(fw, fh)
    blos_px, blos_glow, fruit_px = blank(fw, fh), blank(fw, fh), blank(fw, fh)

    for bi, (bx, by, rx, ry, bz, bias) in enumerate(bolsters):
        irx, iry = max(3.5, rx * 0.72), max(3.0, ry * 0.68)
        for y in range(max(4, int(by - iry)), min(fh - 4, int(by + iry + 1))):
            for x in range(max(pad_x + 2, int(bx - irx)), min(fw - pad_x - 2, int(bx + irx + 1))):
                d = math.hypot((x - bx) / irx, (y - by) / iry) + (vnoise(x * 0.22, y * 0.22, seed + bi * 7) - 0.5) * 0.24
                if d <= 0.96:
                    put(leaf_px, x, y, LEAF[0 if (bz < -1.0 or y > by + 1) else 1])

    rosettes = []
    golden = 2.39996323
    for bi, (bx, by, rx, ry, bz, bias) in enumerate(bolsters):
        n_ros = max(10, int((rx * ry) / 11.0))
        for k in range(n_ros):
            rr = ((k + 0.42) / float(n_ros)) ** 0.56
            ang = k * golden + seed * 0.17 + bi * 1.1
            jx = int(round(bx + math.cos(ang) * rx * 0.88 * rr))
            arch_drop = (abs(math.cos(ang)) * rr) ** 1.4 * (ry * 0.18)
            jy = int(round(by + math.sin(ang) * ry * 0.84 * rr + arch_drop))
            nx, ny = (jx - bx) / max(1.0, rx), (jy - by) / max(1.0, ry)
            gx_t, gy_t = (jx - tree_cx) / max(12.0, crown_span), (jy - crown_cy) / max(10.0, crown_span * 0.72)
            lit = (-0.46 * nx - 0.60 * ny) + (-0.26 * gx_t - 0.30 * gy_t) + bias * 0.20 + (0.10 if bz > 1.2 else (-0.26 if bz < -1.2 else 0.0))
            for obi, (obx, oby, orx, ory, obz, _) in enumerate(bolsters):
                if obi != bi and obz > bz + 0.15 and oby < jy < oby + ory + 6 and abs(jx - obx) < orx * 0.86:
                    lit -= 0.38
                    break
            rosettes.append((bz, -jy + lit * 2.0, jx, jy, nx, ny, lit, bias, k + bi * 37))

    rosettes.sort(key=lambda it: (it[0], it[1]))
    blos_candidates, fruit_candidates, glow_candidates = [], [], []
    for bz, _, jx, jy, nx, ny, lit, bias, rid in rosettes:
        ti = clampi(int((lit + 0.74) * 2.85), 1 if lit > -0.52 else 0, 4)
        c_crev = LEAF[max(0, ti - 2)]
        c_shd = LEAF[max(0, ti - 1)]
        c_mid = LEAF[ti]
        c_lit = LEAF[min(5, ti + 1)] if (lit > 0.02 or bias >= 1) else LEAF[ti]
        draw_apple_rosette(leaf_px, jx, jy, c_crev, c_shd, c_mid, c_lit, pad_x)
        if bz > -1.5 and lit > -0.10:
            blos_candidates.append((hsh(rid, seed, 61) + lit * 0.35, jx, jy, lit > 0.28))
        if bz > -1.8 and ny > -0.25 and lit > -0.30:
            fruit_candidates.append((hsh(rid, seed, 79), jx, jy))
        glow_candidates.append((hsh(rid, seed, 93), jx, jy))

    finish_apple_foliage(leaf_px, pad_x)
    glow_candidates.sort(key=lambda it: it[0], reverse=True)
    for _, gx, gy in glow_candidates[:glows]:
        if pad_x + 2 <= gx < fw - pad_x - 2 and 5 <= gy < fh - 5 and leaf_px[gy][gx][3] > 0:
            put(leaf_glow, gx, gy, GLOW[2])
            put(leaf_glow, gx + 1, gy, GLOW[0])

    if make_pheno:
        # Varied organic garlands of double-corymbs, single flowers & carmine buds (zero sticker outlines on leaves!)
        blos_candidates.sort(key=lambda it: it[0], reverse=True)
        chosen_b = []
        target_b = max(4, int(len(rosettes) * 0.36))
        for idx_b, (_, bx_p, by_p, is_br) in enumerate(blos_candidates):
            if len(chosen_b) >= target_b:
                break
            if all(math.hypot(bx_p - ux, by_p - uy) >= 5.2 for ux, uy in chosen_b):
                chosen_b.append((bx_p, by_p))
                sk = 2 if (is_br and idx_b % 3 == 0) else (0 if idx_b % 4 == 3 else 1)
                draw_blossom_corymb(blos_px, blos_glow, bx_p, by_p, sk, is_br, len(chosen_b) <= 3, pad_x)
        selout_against_sky_only(blos_px, leaf_px, pad_x, hexc("5c2038"), hexc("381426"))

        fruit_candidates.sort(key=lambda it: it[0], reverse=True)
        chosen_f = []
        target_f = max(2, int(len(rosettes) * 0.14))
        for idx_f, (_, fx_p, fy_p) in enumerate(fruit_candidates):
            if len(chosen_f) >= target_f:
                break
            if all(math.hypot(fx_p - ux, fy_p - uy) >= 10.0 for ux, uy in chosen_f):
                chosen_f.append((fx_p, fy_p))
                draw_crab_apple(fruit_px, fx_p, fy_p + 1, tucked=(idx_f % 2 == 0), pad_x=pad_x)
                if len(chosen_f) % 2 == 1:
                    draw_crab_apple(fruit_px, fx_p + 3, fy_p + 2, tucked=False, pad_x=pad_x)
        selout_against_sky_only(fruit_px, leaf_px, pad_x, hexc("3c1420"), hexc("260e18"))

    return leaf_px, leaf_glow, blos_px, blos_glow, fruit_px


def _stem_runs_at(stem_mask, y: int) -> list:
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


def build_apple_traits(fw: int, fh: int, fx: int, fy: int, cut_y: int, fork_y: int, th_px: int, stem_mask, seed: int, base_col: int, mistle_glow_col: int, fungi_glow_col: int, pad_x: int = 12):
    """Generates 11 orchard-authentic modular trait overlays + Mistletoe & Nectar-Cup glow frames."""
    # 1. Moss & Lichen: [golden_xanthoria_lichen_and_moss, silver_parmelia_bark_lichen]
    m_xan, m_par = blank(fw, fh), blank(fw, fh)
    for y in range(fork_y, fy + 2):
        for xl, xr in _stem_runs_at(stem_mask, y):
            ws = max(1, xr - xl)
            for x in range(xl + 1, xr):
                u = (x - xl) / float(ws) * 2.0 - 1.0
                nv = vnoise(x * 0.25, y * 0.25, seed + 101)
                if y >= fy - int(th_px * 2.2) and nv + (y - (fy - th_px * 2.2)) / max(6.0, th_px * 2.2) * 0.45 - u * 0.20 > 0.72:
                    put(m_xan, x, y, MOSS[clampi(int((0.55 - 0.35 * u + nv - 0.65) * 3.2), 0, 3)])
                elif fork_y + 3 <= y <= cut_y - 2 and vnoise(x * 0.32, y * 0.30, seed + 113) > 0.76 and u < 0.35:
                    put(m_xan, x, y, XANTHORIA[2 if u < -0.15 else (1 if u < 0.15 else 0)])
                pv = vnoise(x * 0.28, y * 0.28, seed + 131)
                if fork_y + 3 <= y <= cut_y - 2 and pv > 0.77 and abs(u + 0.1) < 0.72:
                    put(m_par, x, y, PARMELIA[2 if (u < 0 and pv > 0.84) else (1 if u < 0.25 else 0)])

    # 2. Ivy / Epiphytes: [sacred_mistletoe_ball_in_fork, hedgerow_wild_rose_vine]
    mistle, rose, ig_mistle = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    ym = fork_y + max(6, int((fy - fork_y) * 0.20))
    runs_m = _stem_runs_at(stem_mask, ym)
    if runs_m:
        xl, xr = runs_m[0]
        mcx = clampi((xl + xr) // 2 - 2, pad_x + 6, fw - pad_x - 7)
        for dy in range(-4, 5):
            for dx in range(-5, 6):
                d = math.hypot(dx / 5.2, dy / 4.2) + (hsh(dx, dy, seed + 151) - 0.5) * 0.25
                if d <= 1.0:
                    mi = clampi(int((1.15 - d - dx * 0.08 - dy * 0.10) * 3.0), 0, 3)
                    put(mistle, mcx + dx, ym + dy, MISTLE[mi])
        finish_apple_foliage(mistle, pad_x, OUT_LEAF_SUN, OUT_LEAF_SHADE)
        for bx_o, by_o in ((-2, -1), (1, -2), (-1, 1), (2, 1)):
            put(mistle, mcx + bx_o, ym + by_o, PEARL[2])
            put(mistle, mcx + bx_o + 1, ym + by_o, PEARL[0])
            put(ig_mistle, mcx + bx_o, ym + by_o, PEARL[3])
    y_rtop = fork_y + int((fy - fork_y) * 0.22)
    for y in range(y_rtop, fy + 1):
        runs_r = _stem_runs_at(stem_mask, y)
        if runs_r:
            xl, xr = runs_r[0]
            if xr - xl >= 5:
                # Follows the ~35 deg Drehwuchs spiral up the bark!
                u_sp = ((fy - y) * 0.065) % 1.0
                vx = clampi(int(xl + 1 + u_sp * (xr - xl - 2)), xl + 1, xr - 1)
                put(rose, vx, y, LEAF[0])
                if (fy - y) % 4 == 0 and vx + 1 <= xr - 1:
                    put(rose, vx + 1, y, LEAF[2])
                    put(rose, vx, y - 1, LEAF[3])
                if (fy - y) in (10, 22, 34) and vx - 1 >= xl + 1:
                    put(rose, vx - 1, y, BLOSSOM[2])
                    put(rose, vx, y - 1, BLOSSOM[4])
                    put(rose, vx - 1, y - 1, BLOSSOM[1])

    # 3. Hollows strictly backed by stem pixels: [knothole_cavity, honeybee_spiral_cleft, hollow_heart_base]
    h_knot, h_cleft, h_base = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    yk = fork_y + max(9, int((fy - fork_y) * 0.34))
    runs_k = _stem_runs_at(stem_mask, yk)
    if runs_k:
        xl, xr = runs_k[0]
        kcx = clampi((xl + xr) // 2, xl + 3, xr - 3)
        if xr - xl >= 7 and _has_stem_box(stem_mask, kcx, yk, 3, 3):
            for dy in range(-3, 4):
                for dx in range(-2, 3):
                    d = math.hypot(dx / 2.2, dy / 3.0)
                    if d <= 1.2 and stem_mask[yk + dy][kcx + dx][3] > 0:
                        put(h_knot, kcx + dx, yk + dy, OUT_BARK if d < 0.65 else (BARK[0] if d < 0.90 else BARK[4]))
    yc0 = fork_y + int((fy - fork_y) * 0.32)
    for step_y in range(-6, 7):
        yy = yc0 + step_y
        runs_cl = _stem_runs_at(stem_mask, yy)
        if runs_cl:
            xl, xr = runs_cl[0]
            if xr - xl >= 7:
                cx_s = clampi((xl + xr) // 2 - step_y // 3, xl + 2, xr - 2)
                hw_s = 2 if abs(step_y) < 4 else 1
                for dx in range(-hw_s, hw_s + 1):
                    if stem_mask[yy][cx_s + dx][3] > 0:
                        put(h_cleft, cx_s + dx, yy, OUT_BARK if abs(dx) < hw_s else BARK[3 if dx < 0 else 1])
    yb = fy - max(5, int(th_px * 0.58))
    runs_b = _stem_runs_at(stem_mask, yb)
    if runs_b:
        xl, xr = runs_b[0]
        bcx = (xl + xr) // 2
        for dy in range(-4, 4):
            for dx in range(-3, 4):
                d = math.hypot(dx / 2.8, dy / 3.8)
                if d <= 1.15 and 0 <= yb + dy < fh and stem_mask[yb + dy][clampi(bcx + dx, xl, xr)][3] > 0:
                    put(h_base, clampi(bcx + dx, xl + 1, xr - 1), yb + dy, OUT_BARK if d < 0.68 else BARK[1 if dx > 0 else 3])

    # 4. Fungi: [golden_apple_pholiota_cluster, nectar_glimmer_cups]
    f_phol, f_nect, fg_nect = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    yf = fork_y + int((fy - fork_y) * 0.58)
    runs_f = _stem_runs_at(stem_mask, yf)
    if runs_f:
        xl, xr = runs_f[0]
        if xr - xl >= 6:
            bx = clampi((xl + xr) // 2 - 1, xl + 2, xr - 2)
            for ox, oy in ((-2, 0), (1, -2), (2, 2)):
                for dx in (-2, -1, 0, 1, 2):
                    put(f_phol, bx + ox + dx, yf + oy, PHOLIOTA[3 if dx < 0 else (2 if dx == 0 else 1)])
                for dx in (-1, 0, 1):
                    put(f_phol, bx + ox + dx, yf + oy - 1, PHOLIOTA[3 if dx <= 0 else 2])
                    put(f_phol, bx + ox + dx, yf + oy + 1, PHOLIOTA[0])
            for ox, oy in ((-2, -2), (1, 1), (-1, 3)):
                put(f_nect, bx + ox, yf + oy, GLOW[2])
                put(f_nect, bx + ox + 1, yf + oy, GLOW[1])
                put(f_nect, bx + ox, yf + oy + 1, BARK[0])
                put(fg_nect, bx + ox, yf + oy, GLOW[3])
                put(fg_nect, bx + ox + 1, yf + oy, GLOW[2])

    # 5. Thorny Blossom Spurs: [left_spur, right_spur]
    sp_l, sp_r = blank(fw, fh), blank(fw, fh)
    ys = fork_y + int((fy - fork_y) * 0.46)
    runs_s = _stem_runs_at(stem_mask, ys)
    if runs_s:
        all_xl, all_xr = min(r[0] for r in runs_s), max(r[1] for r in runs_s)
        for side, sx0, tgt in ((-1, all_xl, sp_l), (1, all_xr, sp_r)):
            tx1, ty1 = sx0 + side * 6, ys - 2
            draw_apple_limb(tgt, [(sx0, ys), (sx0 + side * 3, ys - 1), (tx1, ty1)], 1.2, 0.8, fy, -999, seed + 301, pad_x=pad_x, thorny=True)
            put(tgt, sx0 + side * 3, ys - 3, THORN_BARK[1])  # crisp wild-apple thorn!
            selout_bark(tgt, pad_x=pad_x, stop_y=fy - 4)
            lf = blank(fw, fh)
            for dx_l, dy_l, c_l in ((-1, 0, LEAF[4]), (0, 0, LEAF[3]), (0, 1, LEAF[2]), (side, -1, BLOSSOM[4]), (side, 0, BLOSSOM[2]), (side * 2, -1, BLOSSOM[1])):
                put(lf, tx1 + dx_l, ty1 + dy_l, c_l)
            finish_apple_foliage(lf, pad_x)
            blit(tgt, lf, 0, 0)

    frames = [m_xan, m_par, mistle, rose, h_knot, h_cleft, h_base, f_phol, f_nect, sp_l, sp_r]
    traits_meta = {
        "moss": [base_col + 0, base_col + 1],
        "ivy": [base_col + 2, base_col + 3],
        "ivy_glow": [mistle_glow_col, -1],
        "hollow": [base_col + 4, base_col + 5, base_col + 6],
        "fungi": [base_col + 7, base_col + 8],
        "fungi_glow": [-1, fungi_glow_col],
        "sprig": [base_col + 9, base_col + 10],
    }
    return frames, ig_mistle, fg_nect, traits_meta


ICON_PAL = {
    "b": BARK[0], "B": BARK[1], "k": BARK[2], "K": BARK[3], "t": BARK[4],
    "S": HEARTWOOD[3], "h": HEARTWOOD[2], "H": HEARTWOOD[1], "d": HEARTWOOD[0],
    "Y": FRUIT[4], "o": FRUIT[3], "R": FRUIT[2], "r": FRUIT[1], "c": FRUIT[0],
    "W": BLOSSOM[4], "p": BLOSSOM[3], "P": BLOSSOM[2], "m": BLOSSOM[1], "g": STAMEN,
    "L": LEAF[4], "l": LEAF[3], "f": LEAF[2],
    "M": MISTLE[3], "v": MISTLE[2], "V": MISTLE[1], "Q": PEARL[2], "q": PEARL[1],
}

# 12x12 interiors at (2..13, 2..13) + 1px #201424 outline => >=1px margin, 1 component, 0 #000000!
ICONS = {
    "apple_wood": [
        "......SSS...", "....SShhhK..", "...ShHdhSKB.", "..ShHdHhSKkb",
        "..SShHhStKkb", "..ktSShKtkBb", "..KktSSkbKBb", "...kKtkbKBb.",
        "....kBBBBb..", ".....bbbb...", "............", "............",
    ],
    "wild_apple_fruit": [
        ".....bLL....", "....bbLlf...", "..YYooRRff..", ".YYoooRRRrc.",
        ".YoooRRRRrc.", ".oooRRRRrrc.", ".ooRRRRrrcc.", "..rRRRRrrc..",
        "...rrcrrc...", "....cbcc....", "............", "............",
    ],
    "apple_blossom": [
        "....WW.WW...", "...WWpWpWW..", "..WWpppppPm.", "..WppggpppP.",
        "...ppggpPPm.", "..WWppppPP..", "...WWpPPfl..", "....mPPkLl..",
        "......kkff..", ".....kb.....", "............", "............",
    ],
    "wild_mistletoe": [
        "...MM...MM..", "..MMvQ.qMMv.", "..MvVQqqvVM.", "...vvVVvVV..",
        "...QqvVVvv..", "..MMvvVvvMM.", ".MMvVVvQqvMM", "..vvV..qvvV.",
        "....VV..VV..", ".....VVVV...", "......VV....", "............",
    ],
    "apple_seed": [
        ".....RRR....", "...RRSSSRR..", "..RRSdSSSRR.", "..RSdbSSdSR.",
        "..RSdbbSdbR.", "...SSbbdbS..", "...dbB.dbB..", "..ddBbddBb..",
        "..dBBbdBBb..", "...bb..bb...", "............", "............",
    ],
}


def build_apple_icons() -> list:
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
