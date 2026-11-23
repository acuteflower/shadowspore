#!/usr/bin/env python3
"""Handcrafted 2.0 botanical pixel-art engine for Glimmtal-Stieleiche (Quercus glimmensis):
  1. Unified Smooth-Union (smin) Y-Forked Oak Skeleton + Craggy Multi-Scale Rhytidome Bark Scales
     (seamless Y-forks with zero pasted-on branch tubes, craggy 3-5 px bark plates, flush root-to-turf toes)
  2. Painter's-Shingled Handcrafted Pixel-Art Oak Leaf-Bouquet Engine
     (discrete 11x8..13x9 lobed oak-leaf fan stamps with veins & tucked leaf-crevices; zero sphere/cotton-candy blobs!)
  3. 5 crisp 16x16 item icons (oak_wood, oak_bark, oak_amber, valley_acorn, oak_polypore)
Zero #000000 pixels anywhere; stdlib + gen_art.py only.
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

# Exact Palettes (strictly zero #000000)
CANOPY = [hexc(c) for c in ("142232", "1d3538", "22483c", "2f624e", "3e7d56", "55985f", "7cb96d", "a8dc8c", "d2ee9c")]
OUT_TOP, OUT_SHADE, OUT_BARK, OUT_ICON = hexc("223c30"), hexc("122226"), hexc("181226"), hexc("1b1a2e")
BARK = [hexc(c) for c in ("1d1526", "2f2236", "4b394f", "6f5869", "977f8b", "c2b0b5")]
MOSS = [hexc(c) for c in ("1c3c34", "2a5c46", "3e7d56", "5e9e64", "86c478")]
LICHEN = [hexc("628478"), hexc("96bca8")]
WOOD = [hexc(c) for c in ("5a3b2e", "8c5e42", "be8e5c", "e6c494")]
AMBER = [hexc(c) for c in ("6f4a18", "b48a38", "e6c468", "fff0b0")]
GLOW = [hexc(c) for c in ("2a8c94", "3cc0c6", "78f4e6", "d0fff8")]
GLOW_VIO = hexc("8a5cf0")
CLOVER = [hexc("c8b2f0"), hexc("f2eaff"), hexc("e6c468")]
CONTACT_RGB = (18, 34, 36)
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def clampi(v: int, lo: int, hi: int) -> int:
    return lo if v < lo else (hi if v > hi else v)


def clampf(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def put(px, x: int, y: int, col) -> None:
    if 0 <= x < len(px[0]) and 0 <= y < len(px) and col[3] > 0:
        if col[0] == 0 and col[1] == 0 and col[2] == 0:
            col = (18, 22, 36, col[3])
        px[y][x] = col


def put_contact_shadow(px, x: int, y: int, alpha: int) -> None:
    if 0 <= x < len(px[0]) and 0 <= y < len(px) and alpha > 0:
        cur = px[y][x]
        if cur[3] == 0:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], min(165, alpha))
        elif cur[:3] == CONTACT_RGB:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], min(175, max(cur[3], alpha)))


def blit(dst, src, ox: int = 0, oy: int = 0) -> None:
    sh, sw = len(src), len(src[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(sh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(sw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            c = src[y][x]
            if c[3] == 0:
                continue
            bg = dst[dy][dx]
            if c[3] == 255 or bg[3] == 0:
                put(dst, dx, dy, c)
            else:
                a = c[3] / 255.0
                ia = 1.0 - a
                dst[dy][dx] = (
                    max(1, int(c[0] * a + bg[0] * ia)),
                    max(1, int(c[1] * a + bg[1] * ia)),
                    max(1, int(c[2] * a + bg[2] * ia)),
                    min(255, int(c[3] + bg[3] * ia)),
                )


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


def fbm(x: float, y: float, s: int) -> float:
    return 0.56 * vnoise(x, y, s) + 0.30 * vnoise(x * 2.1, y * 2.1, s + 13) + 0.14 * vnoise(x * 4.3, y * 4.3, s + 29)


def sample_spline(pts: list, steps: int = 40) -> list:
    if len(pts) == 2:
        return [(pts[0][0] + (pts[1][0] - pts[0][0]) * i / steps, pts[0][1] + (pts[1][1] - pts[0][1]) * i / steps) for i in range(steps + 1)]
    out = []
    ext = [pts[0]] + list(pts) + [pts[-1]]
    segs = len(pts) - 1
    for i in range(steps + 1):
        gf = min(segs - 1e-6, (i / float(steps)) * segs)
        si = int(gf)
        t = gf - si
        p0, p1, p2, p3 = ext[si], ext[si + 1], ext[si + 2], ext[si + 3]
        t2, t3 = t * t, t * t * t
        x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
        y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
        out.append((x, y))
    return out


def shade_craggy_bark(x: int, y: int, across: float, along: float, nx: float, ny: float, nz: float, occ: float, seed: int, moss_w: float = 0.0, lichen_w: float = 0.0, stag: bool = False):
    """Rich multi-scale craggy oak rhytidome bark: 2-4 px interlocking rough scales, deep fissures, zero flat strips!"""
    light = -0.60 * nx - 0.50 * ny + 0.56 * nz
    if stag:
        g = (vnoise(along * 0.45, across * 1.2, seed) - 0.5) * 0.35
        s = light - occ * 0.3 + g
        return WOOD[3] if s > 0.56 else BARK[clampi(int((s + 0.38) * 4.5), 2, 5)]

    # Fine 2.6 px wide x 6.5 px long craggy interlocking oak bark scales flowing ALONG the local limb/root tangent!
    warp_a = across + (fbm(x * 0.22, y * 0.16, seed) - 0.5) * 1.65
    warp_l = along + (vnoise(x * 0.18, y * 0.18, seed + 7) - 0.5) * 2.8
    sc_col = math.floor(warp_a / 2.4)
    sc_row = math.floor((warp_l + (sc_col & 1) * 3.2) / 6.2)
    fx = (warp_a / 2.4) - sc_col
    fy = ((warp_l + (sc_col & 1) * 3.2) / 6.2) - sc_row

    # Deep craggy vertical fissure + staggered diagonal scale-break + micro bark grain (eliminates flat strips!)
    v_fiss = fx < (0.28 + 0.10 * hsh(sc_col, sc_row, seed + 11))
    h_fiss = (fy < 0.18) and (hsh(sc_col, sc_row, seed + 17) > 0.32)
    scale_bevel = (not v_fiss and not h_fiss) and (fx < 0.56 and fy < 0.58)
    plate_tone = (hsh(sc_col, sc_row, seed + 23) - 0.5) * 0.28
    micro = (hsh(x, y, seed + 29) - 0.5) * 0.14 + (BAYER4[y & 3][x & 3] / 16.0 - 0.5) * 0.16

    s = light - occ + plate_tone + micro
    if v_fiss or h_fiss:
        s -= 0.44
    elif scale_bevel:
        s += 0.18

    # Restrain BARK[5] strictly to rare crisp NW scale catchlights (never wide pastel bands!)
    bi = clampi(int((s + 0.42) * 4.35), 0, 4)
    if s > 0.66 and scale_bevel and fx < 0.42 and fy < 0.38 and nx < -0.15:
        bi = 5
    if nx > 0.72:
        bi = min(bi, 1)  # rich dark core shadow on SE side

    # Textured 3D moss cushions hugging bark crevices & root shoulders
    if moss_w > 0.08:
        mv = fbm(x * 0.26, y * 0.26, seed + 37) * 0.72 + moss_w * 0.68 + (0.14 if v_fiss else 0.0)
        if mv > 0.74:
            ms = clampf(light - occ * 0.5 + (mv - 0.74) * 1.5 + micro * 0.8, -0.2, 0.95)
            return MOSS[clampi(int((ms + 0.24) * 4.3), 0, 4)]
    if lichen_w > 0.06 and not v_fiss and not h_fiss and light - occ > 0.10:
        if hsh(sc_col, sc_row, seed + 53) > (1.0 - lichen_w * 0.32) and 0.25 < fy < 0.75:
            return LICHEN[1 if (fx < 0.5 and light > 0.35) else 0]
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


def _prep_chains(specs: list) -> list:
    chains = []
    for pts, r0, r1, moss, lich, stag, z_lay in specs:
        sp = sample_spline(pts, max(12, len(pts) * 10))
        segs = []
        s_acc = 0.0
        tot = sum(math.hypot(sp[i + 1][0] - sp[i][0], sp[i + 1][1] - sp[i][1]) for i in range(len(sp) - 1)) or 1.0
        for i in range(len(sp) - 1):
            ax, ay = sp[i]
            bx, by = sp[i + 1]
            dx, dy = bx - ax, by - ay
            ln = max(1e-4, math.hypot(dx, dy))
            t0, t1 = s_acc / tot, (s_acc + ln) / tot
            ra = r0 + (r1 - r0) * (t0 ** 0.82)
            rb = r0 + (r1 - r0) * (t1 ** 0.82)
            segs.append((ax, ay, dx, dy, ln * ln, ln, ra, rb, s_acc, t0))
            s_acc += ln
        xs = [p[0] for p in sp]
        ys = [p[1] for p in sp]
        rmax = max(r0, r1) + 3.0
        chains.append((min(xs) - rmax, max(xs) + rmax, min(ys) - rmax, max(ys) + rmax, segs, moss, lich, stag, z_lay))
    return chains


def eval_skeleton_pixel(x: int, y: int, chains: list, occ_y: int, seed: int):
    """Smooth-union (smin) SDF across connected trunk, Y-fork boughs & root buttresses (zero pasted tube seams!)."""
    best_by_z = {}
    for x0, x1, y0, y1, segs, moss, lich, stag, z_lay in chains:
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            continue
        bd, bdata = 999.0, None
        for ax, ay, dx, dy, l2, ln, ra, rb, s0, t0 in segs:
            t = clampf(((x - ax) * dx + (y - ay) * dy) / l2, 0.0, 1.0)
            px_c, py_c = ax + dx * t, ay + dy * t
            rad = max(0.75, ra + (rb - ra) * t)
            vx, vy = x - px_c, y - py_c
            dist = math.hypot(vx, vy)
            sd = dist - rad
            if sd < bd:
                tx, ty = dx / ln, dy / ln
                nx_p, ny_p = -ty, tx
                across = vx * nx_p + vy * ny_p
                along = s0 + t * ln
                bd = sd
                bdata = (sd, rad, vx, vy, across, along, moss * max(0.0, 1.0 - t0 * 0.9), lich, stag)
        if bdata is not None and bd < 2.6:
            if z_lay not in best_by_z:
                best_by_z[z_lay] = [bdata]
            else:
                best_by_z[z_lay].append(bdata)

    for z_lay in sorted(best_by_z.keys(), reverse=True):
        hits = best_by_z[z_lay]
        # Polynomial smooth-min (k=2.4 px organic bark collar fillet at every Y-fork & root crotch!)
        hits.sort(key=lambda it: it[0])
        sd0, r0, vx0, vy0, ac0, al0, m0, l0, st0 = hits[0]
        sd_blend = sd0
        if len(hits) > 1 and not st0 and not hits[1][8]:
            sd1, r1, vx1, vy1, ac1, al1, m1, l1, _ = hits[1]
            k = 2.5
            h = clampf(0.5 + 0.5 * (sd1 - sd0) / k, 0.0, 1.0)
            sd_blend = sd1 * (1.0 - h) + sd0 * h - k * h * (1.0 - h)
            w1 = 1.0 - h
            vx0, vy0 = vx0 * h + vx1 * w1, vy0 * h + vy1 * w1
            r0 = r0 * h + r1 * w1
            ac0 = ac0 * h + ac1 * w1
            al0 = al0 * h + al1 * w1
            m0 = max(m0, m1)
        if sd_blend <= 0.0:
            nx = clampf(vx0 / max(0.9, r0), -0.98, 0.98)
            ny = clampf(vy0 / max(0.9, r0), -0.98, 0.98)
            nz = math.sqrt(max(0.05, 1.0 - min(0.95, nx * nx + ny * ny * 0.45)))
            occ = clampf((occ_y - y) / 26.0, 0.0, 0.54) if occ_y > -900 else 0.0
            if z_lay < 0:
                occ += 0.24  # recessed back-bough sits deeper in canopy shadow!
            mw = m0 * max(0.0, -nx * 0.45 - ny * 0.35 + 0.45)
            return shade_craggy_bark(x, y, ac0, al0, nx, ny, nz, occ, seed + z_lay * 7, mw, l0, st0)
    return None


def draw_limb(px, pts, r0: float, r1: float, seed: int = 1, moss: float = 0.25, lichen: float = 0.12, stag: bool = False, pad_x: int = 6, occ_y: int = -999) -> None:
    h, w = len(px), len(px[0])
    chains = _prep_chains([(pts, r0, r1, moss, lichen, stag, 0)])
    x0 = max(pad_x, int(chains[0][0]))
    x1 = min(w - pad_x, int(chains[0][1]) + 1)
    y0 = max(2, int(chains[0][2]))
    y1 = min(h - 2, int(chains[0][3]) + 1)
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = eval_skeleton_pixel(x, y, chains, occ_y, seed)
            if c is not None:
                put(px, x, y, c)


def build_unified_oak_skeleton(fw: int, fh: int, fx: int, fy: int, cut_y: int, fork_y: int, th_px: int, boughs: list, seed: int, n_roots: int = 5, clover=None, glow_root=None, pad_x: int = 10, bole_pts=None):
    """Renders pure craggy-bark trunk + compact staggered inner crown boughs + 3/4 root buttresses (zero baked clutter!)."""
    skirt, tbase, tupper = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    rx_sh, ry_sh = th_px * 2.5 + 8.0, max(4.5, th_px * 0.78 + 3.5)
    scx, scy = fx + th_px * 0.30 + 1.5, fy + 1.5
    for y in range(int(scy - ry_sh - 2), int(scy + ry_sh + 3)):
        for x in range(int(scx - rx_sh - 2), int(scx + rx_sh + 3)):
            d = math.hypot((x - scx) / rx_sh, (y - scy) / ry_sh) + (vnoise(x * 0.18, y * 0.22, seed) - 0.5) * 0.20
            if d < 1.0:
                put_contact_shadow(skirt, x, y, int(122 * ((1.0 - d) ** 1.5)))

    mid_y = (fy + fork_y) // 2
    if bole_pts is None:
        bole_pts = [(fx + 1, fy + 1), (fx, cut_y), (fx - max(1, th_px // 4), mid_y), (fx + 1, fork_y)]
    # Pure craggy bark on base bole & roots (moss=0.0 so moss/ivy/fungi/hollows come cleanly from modular traits!)
    trunk_specs = [(bole_pts, th_px * 1.12, th_px * 0.70, 0.0, 0.14 if th_px >= 8 else 0.0, False, 0)]

    root_defs = [
        (-1.0, 1.50, -1, 0.50),
        (-0.42, 1.00, 3, 0.55),
        (0.40, 1.05, 2, 0.48),
        (0.95, 1.38, -1, 0.42),
        (-0.72, 1.18, 1, 0.38),
    ][:max(2, n_roots)]
    root_specs = []
    for ri, (udir, reach_m, dy_end, rm) in enumerate(root_defs):
        reach = reach_m * th_px + 3.5
        p0 = (fx + udir * th_px * 0.42, fy - max(5, int(th_px * 1.15)))
        p1 = (fx + udir * (th_px * 0.90 + reach * 0.42), fy - 1 + dy_end // 2)
        p2 = (fx + udir * (th_px * 0.85 + reach), fy + 1 + dy_end)
        rspec = ([p0, p1, p2], max(1.8, th_px * rm), 1.1, 0.0, 0.0, False, 0)
        root_specs.append((rspec, p1, p2, udir))
        trunk_specs.append(rspec)

    upper_chains = _prep_chains(trunk_specs + boughs)
    base_chains = _prep_chains(trunk_specs)
    occ_y = fork_y + int(th_px * 2.2)
    spans = {}

    for y in range(2, fy + 8):
        xl, xr = 9999, -9999
        for x in range(max(4, pad_x), fw - max(4, pad_x)):
            hit = False
            if y <= cut_y + max(2, int(th_px * 0.36)):
                cu = eval_skeleton_pixel(x, y, upper_chains, occ_y, seed)
                if cu is not None:
                    put(tupper, x, y, cu)
                    hit = True
            if y >= cut_y - max(2, int(th_px * 0.32)):
                cb = eval_skeleton_pixel(x, y, base_chains, occ_y, seed)
                if cb is not None:
                    hit = True
                    if y >= fy - 2:
                        put(skirt, x, y, cb)
                    if abs(x - fx) <= int(th_px * 1.65 + 3) and y <= fy + 2 - int(abs(x - fx) * 0.08):
                        put(tbase, x, y, cb)
                    else:
                        put(skirt, x, y, cb)
            if hit:
                if x < xl:
                    xl = x
                if x > xr:
                    xr = x
        if xl <= xr:
            spans[y] = (xl, xr)

    if glow_root is not None and th_px >= 8:
        put(glow_root, fx - th_px // 2, fy, GLOW[0])
    selout_bark(tbase, pad_x=4, stop_y=fy - 3)
    selout_bark(tupper, pad_x=pad_x, stop_y=fy - 3, skip_bottom_y=cut_y - 2)
    draw_cut_rings(tbase, fx, cut_y, max(2, int(th_px * 0.96)), max(2, int(th_px * 0.36)))
    draw_moss_and_litter(skirt, tbase, fx, fy, th_px, seed + 3, clover_at=clover)
    return skirt, tbase, tupper, spans


def draw_moss_and_litter(skirt, tbase, cx: int, fy: int, th_px: int, seed: int, clover_at=None) -> None:
    rx = int(th_px * 2.3 + 7)
    # Individual ragged 3-5 px meadow grass blades & moss tufts overlapping root toes from below
    n_tufts = max(6, int(th_px * 1.6) + 4)
    for i in range(n_tufts):
        u = (i / float(max(1, n_tufts - 1))) * 2.0 - 1.0
        tx = cx + int(u * (th_px * 1.55 + 3) + (hsh(i, seed, 5) - 0.5) * 2.5)
        ty = fy + 1 + int((1.0 - u * u) * 2.2 + (hsh(i, seed, 8) - 0.5) * 1.5)
        target = tbase if (abs(tx - cx) <= th_px + 3 and ty <= fy + 3) else skirt
        bh = 2 + (i % 3)
        lean_x = -1 if (i % 2 == 0) else 1
        for h_i in range(bh):
            bx_p = tx + (lean_x if h_i == bh - 1 else 0)
            by_p = ty - h_i
            c = CANOPY[4 if (u < 0.1 and h_i == bh - 1) else (3 if h_i > 0 else 2)] if i % 2 == 0 else MOSS[min(4, 1 + h_i)]
            put(target, bx_p, by_p, c)
    for i in range(int(th_px * 0.9) + 2):
        ang = hsh(i, seed, 11) * math.tau
        dist = (0.40 + 0.56 * hsh(i, seed, 17)) * rx
        mx, my = int(cx + math.cos(ang) * dist), int(fy + math.sin(ang) * dist * 0.28) + 1
        c = WOOD[2 if i % 2 == 0 else 1] if i % 3 == 0 else MOSS[clampi(int(hsh(i, seed, 23) * 4.0), 1, 3)]
        put(skirt, mx, my, c)
        put(skirt, mx + 1, my, WOOD[0] if i % 3 == 0 else MOSS[1])
    for i in range(max(1, th_px // 3)):
        ax = cx + int((hsh(i, seed, 31) - 0.45) * rx * 1.1)
        ay = fy + int((hsh(i, seed, 37) - 0.1) * rx * 0.24) + 2
        put(skirt, ax, ay, BARK[2])
        put(skirt, ax + 1, ay, AMBER[2])
        put(skirt, ax + 1, ay + 1, AMBER[1])
    if clover_at is not None:
        rx0, ry0 = cx + clover_at[0], fy + clover_at[1]
        for dy in range(-5, 6):
            for dx in range(-10, 11):
                d = math.hypot(dx / 10.0, dy / 5.0) + (vnoise((rx0 + dx) * 0.3, (ry0 + dy) * 0.3, seed) - 0.5) * 0.2
                if d <= 1.0:
                    put(skirt, rx0 + dx, ry0 + dy, MOSS[clampi(int((1.15 - d - dx * 0.03) * 3.6), 0, 4)])
        for ox, oy in ((-5, -1), (1, -2), (5, 1), (-1, 2)):
            put(skirt, rx0 + ox, ry0 + oy, CLOVER[1])
            put(skirt, rx0 + ox + 1, ry0 + oy, CLOVER[0])
        put(skirt, rx0 - 2, ry0, CLOVER[2])


def draw_cut_rings(px, cx: int, cy: int, rx: int, ry: int) -> None:
    for y in range(cy - ry - 1, cy + ry + 2):
        for x in range(cx - rx - 1, cx + rx + 2):
            d = math.hypot((x - cx) / max(1.0, rx), (y - cy) / max(1.0, ry))
            if d <= 1.06:
                if d > 0.88:
                    put(px, x, y, OUT_BARK if d > 0.98 else BARK[1])
                elif d > 0.68:
                    put(px, x, y, WOOD[3] if (x - cx + y - cy) < 0 else WOOD[2])
                else:
                    ring = int(d * max(3.0, rx * 0.65)) % 2
                    put(px, x, y, WOOD[2 if ring == 0 else 1] if d > 0.24 else WOOD[0])


def draw_hollow(px, cx: int, cy: int, rx: int, ry: int) -> None:
    """Asymmetric gnarled callus-rimmed Dendrotelm bark cavity (no symmetrical green hat!)."""
    for y in range(cy - ry - 2, cy + ry + 3):
        for x in range(cx - rx - 2, cx + rx + 3):
            nx = (x - cx + 0.3 * math.sin(y * 0.5)) / max(1.0, rx)
            ny = (y - cy) / max(1.0, ry)
            # Pointed vertical almond scar shape like a real oak branch-tear hollow
            taper = 1.0 - 0.35 * abs(ny)
            d = math.hypot(nx / max(0.35, taper), ny)
            if d <= 1.32:
                if d > 0.76:
                    if ny > 0.55 and nx < 0.2:
                        col = MOSS[2 if nx < -0.2 else 1]
                    else:
                        col = BARK[4 if (nx < -0.25 and ny < 0.2) else (3 if nx < 0.1 else (2 if ny < 0 else 1))]
                    put(px, x, y, col)
                else:
                    put(px, x, y, OUT_BARK if d < 0.52 else BARK[0])


def draw_kerf(px, cx: int, cut_y: int, r_trunk: int, deep: bool = False) -> None:
    depth = max(3, int(r_trunk * (0.92 if deep else 0.52)))
    h_notch = max(3, int(r_trunk * (0.60 if deep else 0.40)))
    x_right = cx + r_trunk
    for dy in range(-h_notch, 2):
        span = int(depth * (1.0 - abs(dy + h_notch * 0.35) / (h_notch + 1.5)))
        for k in range(max(1, span)):
            x = x_right - k
            col = BARK[0] if dy >= 0 else (WOOD[0] if k > span * 0.65 else (WOOD[3] if dy < -h_notch * 0.4 else WOOD[2]))
            put(px, x, cut_y + dy, col)


def draw_amber_polypore(px, glow_px, cx: int, cy: int, r_t: int, seed: int = 5) -> None:
    """Used on s6_log nurse log: natural amber resin drops + bracket fungi."""
    for ox, oy, rh in ((-max(1, r_t // 4), -2, 3), (max(1, r_t // 5), 5, 4)):
        ax, ay = cx + ox, cy + oy
        put(px, ax, ay - rh, BARK[0])
        for dy in range(-rh + 1, rh):
            put(px, ax, ay + dy, AMBER[3 if dy == 0 else (2 if dy < 0 else 1)])
            if 0 <= dy < rh - 1:
                put(px, ax - 1, ay + dy, AMBER[2])
                put(px, ax + 1, ay + dy, AMBER[0])
        if glow_px is not None:
            put(glow_px, ax, ay, AMBER[3])
            put(glow_px, ax - 1, ay, AMBER[2])
    brackets = [
        (cx - max(2, int(r_t * 0.48)), cy - 6, ["..ss..", ".sWWq.", "bBttqb", "..bb.."]),
        (cx + max(1, int(r_t * 0.22)), cy + 1, [".sss..", "sWWWq.", "bBttqb", "..bbb."]),
    ]
    bpal = {"s": WOOD[3], "W": WOOD[2], "q": GLOW[1], "t": MOSS[1], "B": BARK[1], "b": BARK[0]}
    for bx, by, rows in brackets:
        for ry, rstr in enumerate(rows):
            for rx, ch in enumerate(rstr):
                if ch in bpal:
                    put(px, bx + rx - 2, by + ry - 1, bpal[ch])
                    if glow_px is not None and ch == "q":
                        put(glow_px, bx + rx - 2, by + ry - 1, GLOW[2])


def draw_harvest_amber_only(px, glow_px, spans: dict, y_mid: int, seed: int = 11) -> None:
    """Pure golden Wundharz resin drops on bark (so harvesting removes ONLY resin, keeping tree traits intact!)."""
    for idx, dy_off in enumerate((-5, 3, 9)):
        ay = y_mid + dy_off
        if ay not in spans:
            continue
        xl, xr = spans[ay]
        if xr - xl < 6:
            continue
        u = -0.22 if idx == 0 else (0.18 if idx == 1 else -0.05)
        ax = int((xl + xr) * 0.5 + u * (xr - xl) * 0.5)
        rh = 3 if idx != 1 else 4
        put(px, ax, ay - rh, BARK[0])
        for dy in range(-rh + 1, rh):
            put(px, ax, ay + dy, AMBER[3 if dy == 0 else (2 if dy < 0 else 1)])
            if 0 <= dy < rh - 1:
                put(px, ax - 1, ay + dy, AMBER[2])
                put(px, ax + 1, ay + dy, AMBER[0])
        if glow_px is not None:
            put(glow_px, ax, ay, AMBER[3])
            put(glow_px, ax - 1, ay, AMBER[2])


def build_modular_traits(fw: int, fh: int, fx: int, fy: int, cut_y: int, fork_y: int, th_px: int, spans: dict, seed: int, base_col: int, glow_col: int, dendro_at=None, pad_x: int = 10):
    """Generates 11 modular trait overlay frames + 1 fungi_glow frame + traits JSON dict."""
    ivy_dark = hexc("162c28")
    # 1. Moss traits: [north_roots, fork_coat]
    m_roots, m_fork = blank(fw, fh), blank(fw, fh)
    for y, (xl, xr) in spans.items():
        w_s = max(1, xr - xl)
        for x in range(xl + 1, xr):
            u = (x - xl) / float(w_s) * 2.0 - 1.0
            n1 = fbm(x * 0.22, y * 0.22, seed + 101)
            if y >= fy - int(th_px * 2.5) and n1 + (y - (fy - th_px * 2.5)) / max(6.0, th_px * 2.5) * 0.45 - u * 0.25 > 0.72:
                mi = clampi(int((0.55 - 0.45 * u + (n1 - 0.65)) * 3.6), 0, 3)
                put(m_roots, x, y, MOSS[mi])
            n2 = fbm(x * 0.24, y * 0.20, seed + 131)
            if fork_y - 2 <= y <= cut_y - 3 and n2 + (1.0 - (y - fork_y) / max(8.0, float(cut_y - fork_y))) * 0.35 - abs(u + 0.15) * 0.28 > 0.76:
                mi = clampi(int((0.48 - 0.40 * u + (n2 - 0.70)) * 3.5), 0, 3)
                put(m_fork, x, y, MOSS[mi])

    # 2. Dark woodland ivy traits: [left_ivy, right_ivy] (2-3 px clustered dark heart-leaves, NEVER neon zig-zag!)
    ivy_l, ivy_r = blank(fw, fh), blank(fw, fh)
    for side, target, s_off in ((-1, ivy_l, 201), (1, ivy_r, 233)):
        y_top = fork_y + max(3, int((fy - fork_y) * 0.14))
        for y in range(y_top, fy + 1):
            if y not in spans:
                continue
            xl, xr = spans[y]
            if xr - xl < 5:
                continue
            t_climb = (fy - y) / max(1.0, float(fy - y_top))
            anchor_x = (xl + 2 + (xr - xl) * 0.24) if side < 0 else (xr - 2 - (xr - xl) * 0.24)
            vx = int(round(anchor_x + math.sin(y * 0.21 + s_off) * max(1.2, th_px * 0.18)))
            vx = clampi(vx, xl + 1, xr - 1)
            put(target, vx, y, BARK[1] if (y & 1) else ivy_dark)
            # Clustered 2-3 px dark woodland ivy leaves (denser near base, trailing near top)
            density = 0.78 - 0.38 * t_climb
            if hsh(vx, y, seed + s_off) < density:
                for cl_dx in (-2, 0, 2) if t_climb < 0.55 else (-1, 1):
                    lx = clampi(vx + cl_dx + int((hsh(y, cl_dx, seed + s_off + 5) - 0.5) * 2.5), xl + 1, xr - 1)
                    put(target, lx, y + 1, ivy_dark)
                    put(target, lx, y, CANOPY[2 if (side > 0 or cl_dx > 0) else 4])
                    if lx - 1 >= xl + 1:
                        put(target, lx - 1, y, CANOPY[4 if side < 0 else 2])
                    if side < 0 and cl_dx <= 0 and hsh(lx, y, seed + s_off + 9) > 0.62 and y - 1 >= y_top:
                        put(target, lx - 1, y - 1, CANOPY[5])

    # 3. Hollow traits: [woodpecker_hole, fork_dendrotelm, root_burrow_or_scar]
    h_peck, h_fork, h_root = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    yp = fork_y + max(6, int((fy - fork_y) * 0.28))
    if yp in spans:
        xl, xr = spans[yp]
        px_c = int((xl + xr) * 0.5 + (xr - xl) * 0.10)
        for dy in range(-3, 4):
            for dx in range(-2, 3):
                d = math.hypot(dx / 2.1, dy / 3.0)
                if d <= 1.15:
                    put(h_peck, px_c + dx, yp + dy, OUT_BARK if d < 0.68 else (WOOD[2] if dx <= 0 and dy >= 0 else BARK[2]))
    if dendro_at is not None:
        draw_hollow(h_fork, dendro_at[0], dendro_at[1], max(3, th_px // 3), max(4, int(th_px * 0.44)))
    else:
        yd = fork_y + max(5, int((fy - fork_y) * 0.20))
        if yd in spans:
            xl, xr = spans[yd]
            draw_hollow(h_fork, int((xl + xr) * 0.5 - 1), yd, max(3, th_px // 3), max(4, int(th_px * 0.42)))
    yr = fy - max(5, int(th_px * 0.62))
    if yr in spans:
        xl, xr = spans[yr]
        rcx = int((xl + xr) * 0.5 - 1)
        draw_hollow(h_root, rcx, yr, max(3, int(th_px * 0.34)), max(4, int(th_px * 0.46)))
        for sy in range(yr - int(th_px * 0.85), yr - 3):
            if sy in spans:
                sx = rcx + int(round(math.sin(sy * 0.45) * 1.6))
                put(h_root, sx, sy, BARK[0])
                if (sy & 1) == 0:
                    put(h_root, sx - 1, sy, BARK[3])

    # 4. Fungi traits: [ochre_brackets (unlit), teal_polypores (night-glowing)]
    f_ochre, f_teal, fg_teal = blank(fw, fh), blank(fw, fh), blank(fw, fh)
    ochre_pal = {"s": AMBER[2], "W": AMBER[1], "q": WOOD[2], "t": AMBER[0], "B": WOOD[0], "b": BARK[0]}
    teal_pal = {"s": MOSS[2], "W": GLOW[0], "q": GLOW[1], "t": MOSS[0], "B": BARK[1], "b": BARK[0]}
    shelf_rows = [("..sss.", ".sWWWq", "bBttqb", "..bbb."), ("..ss..", ".sWWq.", "bBttqb", "..bb..")]
    y_f0 = fork_y + int((fy - fork_y) * 0.52)
    for idx, (dy_o, u_pos) in enumerate(((-5, -0.28), (2, 0.14), (7, -0.10))):
        yy = y_f0 + dy_o
        if yy in spans:
            xl, xr = spans[yy]
            bx = int((xl + xr) * 0.5 + u_pos * (xr - xl) * 0.45)
            rows = shelf_rows[idx % 2]
            for ry, rstr in enumerate(rows):
                for rx, ch in enumerate(rstr):
                    if ch in ochre_pal:
                        put(f_ochre, bx + rx - 3, yy + ry - 1, ochre_pal[ch])
    for idx, (dy_o, u_pos) in enumerate(((-3, 0.22), (4, -0.18))):
        yy = y_f0 + dy_o
        if yy in spans:
            xl, xr = spans[yy]
            bx = int((xl + xr) * 0.5 + u_pos * (xr - xl) * 0.45)
            rows = shelf_rows[idx % 2]
            for ry, rstr in enumerate(rows):
                for rx, ch in enumerate(rstr):
                    if ch in teal_pal:
                        put(f_teal, bx + rx - 3, yy + ry - 1, teal_pal[ch])
                        if ch in ("q", "W"):
                            put(fg_teal, bx + rx - 3, yy + ry - 1, GLOW[2 if ch == "q" else 0])

    # 5. Epicormic sprig traits: [left_leaf_twig, right_leaf_twig]
    sp_l, sp_r = blank(fw, fh), blank(fw, fh)
    ys = fork_y + int((fy - fork_y) * 0.46)
    if ys in spans:
        xl, xr = spans[ys]
        for side, target in ((-1, sp_l), (1, sp_r)):
            sx0 = (xl + 1) if side < 0 else (xr - 1)
            tx1, ty1 = sx0 + side * max(5, int(th_px * 0.55)), ys - 4
            draw_limb(target, [(sx0, ys), (sx0 + side * 3, ys - 2), (tx1, ty1)], 1.3, 0.8, seed + 301 + side, moss=0.0, pad_x=pad_x)
            selout_bark(target, pad_x=pad_x, stop_y=fy - 4)
            leaf_frame = blank(fw, fh)
            for la, ll in ((-2.35, 5.2), (-1.75, 5.6), (-1.15, 4.8)) if side < 0 else ((-1.95, 4.8), (-1.35, 5.6), (-0.75, 5.2)):
                c_v = CANOPY[2 if side > 0 else 3]
                c_m = CANOPY[3 if side > 0 else 4]
                c_l = CANOPY[5 if side > 0 else 6]
                draw_oak_leaf(leaf_frame, tx1, ty1, math.cos(la), math.sin(la), ll, c_v, c_m, c_l, pad_x=pad_x)
            finish_foliage(leaf_frame, pad_x=pad_x)
            blit(target, leaf_frame, 0, 0)

    frames = [m_roots, m_fork, ivy_l, ivy_r, h_peck, h_fork, h_root, f_ochre, f_teal, sp_l, sp_r]
    traits_meta = {
        "moss": [base_col + 0, base_col + 1],
        "ivy": [base_col + 2, base_col + 3],
        "hollow": [base_col + 4, base_col + 5, base_col + 6],
        "fungi": [base_col + 7, base_col + 8],
        "fungi_glow": [-1, glow_col],
        "sprig": [base_col + 9, base_col + 10],
    }
    return frames, fg_teal, traits_meta


def draw_oak_leaf(px, x0: float, y0: float, dx: float, dy: float, length: float, c_vein, c_mid, c_lit, c_peak=None, c_crev=None, pad_x: int = 10) -> None:
    """Draws a crisp, cel-shaded 3-lobed botanical oak leaf blade (6-10 px) with midrib vein & cast undercut shadow."""
    w_img, h_img = len(px[0]), len(px)
    nx, ny = -dy, dx
    steps = max(6, int(length * 2.1))
    # Pass 1: Crisp 1.5 px downward/SE cast leaf-shadow ONLY onto existing underlying foliage!
    if c_crev is not None:
        for i in range(2, steps + 1):
            t = i / float(steps)
            env = math.sin(t * math.pi) ** 0.72
            lobes = 0.68 + 0.36 * abs(math.sin(t * math.pi * 2.85))
            hw = max(0.6, length * 0.26 * env * lobes)
            cx, cy = x0 + dx * length * t + 0.6, y0 + dy * length * t + 1.5
            iw = int(math.ceil(hw))
            for k in range(-iw, iw + 1):
                if abs(k) <= hw:
                    sx, sy = int(round(cx + nx * k)), int(round(cy + ny * k))
                    if pad_x <= sx < w_img - pad_x and 3 <= sy < h_img - 3 and px[sy][sx][3] > 0:
                        put(px, sx, sy, c_crev)

    # Pass 2: Crisp solid cel-shaded lobed oak leaf blade (midrib vein + shaded SE half + sunlit NW lobes)
    sun_side = 1.0 if (nx * -0.60 + ny * -0.72) >= 0.0 else -1.0
    for i in range(steps + 1):
        t = i / float(steps)
        if t < 0.16:
            hw = 0.55
        else:
            env = math.sin(((t - 0.08) / 0.92) * math.pi) ** 0.68
            lobes = 0.64 + 0.42 * abs(math.sin(t * math.pi * 2.85 - 0.25))
            hw = max(0.65, length * 0.27 * env * lobes)
        cx, cy = x0 + dx * length * t, y0 + dy * length * t
        iw = int(math.ceil(hw + 0.3))
        for k_i in range(-iw * 2, iw * 2 + 1):
            k = k_i * 0.5
            if abs(k) > hw:
                continue
            px_x, px_y = int(round(cx + nx * k)), int(round(cy + ny * k))
            if not (pad_x <= px_x < w_img - pad_x and 3 <= px_y < h_img - 3):
                continue
            if abs(k) < 0.48 and t < 0.64 and length >= 5.5:
                col = c_vein
            elif c_peak is not None and t > 0.76 and (k * sun_side) >= -0.2:
                col = c_peak
            elif (k * sun_side) > 0.15 or t > 0.68:
                col = c_lit
            else:
                col = c_mid
            put(px, px_x, px_y, col)


def render_oak_cluster_volume(px, glow_px, bolsters: list, tree_cx: int, crown_cy: int, crown_span: float, seed: int, pad_x: int = 10, acorns: int = 0, glows: int = 0) -> None:
    """Golden-angle phyllotaxis oak-leaf fan renderer: zero grid lines, zero cotton-candy, bold 7-9 px lobed oak leaves!"""
    h, w = len(px), len(px[0])
    # 1. Arched dark interior foliage core (62% radius) so deep crevices between leaf fans read as rich woodland shadow
    for bi, (bx, by, rx, ry, bz, bias) in enumerate(bolsters):
        irx, iry = max(3.0, rx * 0.64), max(2.5, ry * 0.60)
        for y in range(max(4, int(by - iry)), min(h - 4, int(by + iry + 1))):
            for x in range(max(pad_x + 2, int(bx - irx)), min(w - pad_x - 2, int(bx + irx + 1))):
                d = math.hypot((x - bx) / irx, (y - by) / iry) + (vnoise(x * 0.22, y * 0.22, seed + bi) - 0.5) * 0.25
                if d <= 0.95:
                    put(px, x, y, CANOPY[0 if (bz < -1.0 or y > by) else 1])

    # 2. Golden-angle spiral (137.5 deg phyllotaxis!) twig-fans across every arched bough bolster -> ZERO grid lines!
    fans = []
    golden = 2.39996323
    for bi, (bx, by, rx, ry, bz, bias) in enumerate(bolsters):
        area = rx * ry
        n_fans = max(10, int(area / 13.5))
        l_len = clampf(4.8 + min(rx, ry) * 0.21, 5.0, 8.6)
        for k in range(n_fans):
            rr = ((k + 0.45) / float(n_fans)) ** 0.56
            ang = k * golden + (seed * 0.17 + bi * 1.13)
            jx = bx + math.cos(ang) * rx * 0.88 * rr
            # Gentle arched dome curve (center slightly higher, lateral tips drooping naturally with gravity!)
            arch_droop = (abs(math.cos(ang)) * rr) ** 1.5 * (ry * 0.20)
            jy = by + math.sin(ang) * ry * 0.84 * rr + arch_droop
            nx, ny = (jx - bx) / max(1.0, rx), (jy - by) / max(1.0, ry)
            gx_t = (jx - tree_cx) / max(12.0, crown_span)
            gy_t = (jy - crown_cy) / max(10.0, crown_span * 0.72)

            lit = (-0.48 * nx - 0.62 * ny) + (-0.28 * gx_t - 0.34 * gy_t) + bias * 0.20 + (0.10 if bz > 1.5 else (-0.26 if bz < -1.5 else 0.0))
            # Cast shadow where an upper/front bolster overhangs a lower bolster
            for obi, (obx, oby, orx, ory, obz, _) in enumerate(bolsters):
                if obi != bi and obz > bz + 0.15 and oby < jy < oby + ory + 7 and abs(jx - obx) < orx * 0.88:
                    lit -= 0.40
                    break
            # Outward + gravity-drooping branch-fan direction
            out_ang = math.atan2(ny * 0.82 + 0.26, nx if abs(nx) > 0.10 else (0.15 if (k & 1) else -0.15))
            fans.append((bz, -jy + lit * 2.5, jx, jy, out_ang, lit, bias, l_len, k + bi * 31))

    fans.sort(key=lambda it: (it[0], it[1]))
    for _, _, jx, jy, out_ang, lit, bias, l_len, fseed in fans:
        ti = clampi(int((lit + 0.76) * 3.85), 1 if lit > -0.55 else 0, 6)
        c_crev = CANOPY[max(0, ti - 2)]
        c_vein = CANOPY[max(0, ti - 1)]
        c_mid = CANOPY[ti]
        c_lit = CANOPY[min(7, ti + 1)]
        c_peak = CANOPY[8] if (bias >= 1 and lit > 0.56 and ti >= 6) else (CANOPY[min(7, ti + 2)] if lit > 0.32 else None)
        # 3-leaf botanical oak spray fanning from twig node (jx, jy)
        n_lv = 3 if l_len >= 5.8 else 2
        spread = 1.18 if n_lv == 3 else 0.85
        for li in range(n_lv):
            u = (li / float(n_lv - 1) - 0.5) if n_lv > 1 else 0.0
            la = out_ang + u * spread + (hsh(fseed, li, seed) - 0.5) * 0.22
            dx, dy = math.cos(la), math.sin(la)
            leaf_l = l_len * (1.06 if abs(u) < 0.2 else 0.90)
            draw_oak_leaf(px, jx - dx * 1.2, jy - dy * 1.2, dx, dy, leaf_l, c_vein, c_mid, c_lit, c_peak if abs(u) < 0.2 else None, c_crev, pad_x)

    # 3. Tucked golden acorns strictly along lower/mid bough skirts + subtle nocturnal dew gleams
    for i in range(acorns):
        bx, by, rx, ry, _, _ = bolsters[i % len(bolsters)]
        ang = 0.35 + (i % 3) * 0.95 + hsh(i, seed, 91) * 0.35
        ax = clampi(int(bx + math.cos(ang) * rx * 0.52), pad_x + 3, w - pad_x - 4)
        ay = clampi(int(by + max(0.35, math.sin(ang)) * ry * 0.65 + 2), 10, h - 5)
        if px[ay][ax][3] > 0:
            for k in (-1, 0, 1):
                put(px, ax + k, ay - 1, WOOD[1 if k <= 0 else 0])
                put(px, ax + k, ay, AMBER[2 if k <= 0 else 1])
            put(px, ax, ay + 1, AMBER[1])
            put(px, ax - 1, ay, AMBER[3])
    if glow_px is not None:
        for i in range(glows):
            bx, by, rx, ry, _, _ = bolsters[i % len(bolsters)]
            gx = clampi(int(bx + (hsh(i, seed, 51) - 0.5) * rx * 1.0), pad_x + 3, w - pad_x - 4)
            gy = clampi(int(by + (hsh(i, seed, 63) - 0.25) * ry * 0.8), 6, h - 5)
            if px[gy][gx][3] > 0:
                put(glow_px, gx, gy, GLOW[2])
                put(glow_px, gx + 1, gy, GLOW[0])


def finish_foliage(px, pad_x: int = 10) -> None:
    h, w = len(px), len(px[0])
    rim = []
    for y in range(2, h - 2):
        for x in range(pad_x, w - pad_x):
            if px[y][x][3] == 0:
                nb = [(dx, dy) for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)) if px[y + dy][x + dx][3] > 200]
                if nb:
                    sun = any(dy > 0 or dx > 0 for dx, dy in nb) and not any(dy < 0 and dx < 0 for dx, dy in nb)
                    rim.append((x, y, OUT_TOP if sun else OUT_SHADE))
    for x, y, col in rim:
        put(px, x, y, col)


ICON_PAL = {
    "b": BARK[0], "B": BARK[1], "k": BARK[2], "K": BARK[3], "l": BARK[4],
    "w": WOOD[0], "W": WOOD[1], "s": WOOD[2], "S": WOOD[3],
    "m": MOSS[1], "M": MOSS[3], "L": MOSS[4], "c": LICHEN[1],
    "a": AMBER[0], "A": AMBER[1], "g": AMBER[2], "G": AMBER[3],
    "f": CANOPY[3], "F": CANOPY[5], "Y": CANOPY[7],
    "t": GLOW[0], "T": GLOW[1], "q": GLOW[2], "Q": GLOW[3],
}

ICONS = {
    "oak_wood": [
        "..............", "........SSS...", "......SSsssK..", ".....SssWWsKB.",
        "....SwsWwsKKb.", "...SWwWWsKMBb.", "..SsWWsKKlMBb.", "..SswsKklKbBb.",
        "..SSsKKbKKBb..", "...SKKbBKBb...", "....bBBBBb....", "..............",
    ],
    "oak_bark": [
        "..............", "......KKl.....", "....KKlMMK....", "...KbKMLcKb...",
        "..KbBkMMKlBb..", "..KbkKllKbBb..", "...bKKbKBBb...", "...sKbBBBB....",
        "....ssBBb.....", ".....ssb......", "..............", "..............",
    ],
    "oak_amber": [
        "..............", ".......g......", "......gGg.....", ".....gGGGg....",
        "....AgGGggA...", "...AAgggggAA..", "...AAggAggAA..", "...aAAAAAaAa..",
        "...kBaaaaBBk..", "....kBBBBBk...", ".....kbbbk....", "..............",
    ],
    "valley_acorn": [
        ".......k......", "......kkFF....", "....kKKkFYf...", "...kKlKkFFf...",
        "...BkbkKBff...", "...GGGGggA....", "...GGgggAA....", "...AggggAA....",
        "....AAgAAa....", ".....AAAa.....", "......aa......", "..............",
    ],
    "oak_polypore": [
        "..............", ".....qqQQqq...", "...qqTTttTTqq.", "..qTTmmMMmmTTq",
        "..TmmkKKKKmmTq", "..mkWWqqQQqqm.", "...kWqqTTttTTq", "...BWqTTmmMMTq",
        "....BBmmkKKmm.", ".....bBBBBbb..", "..............", "..............",
    ],
}


def build_oak_icons() -> list:
    out_paths = []
    for name, rows in ICONS.items():
        px = blank(16, 16)
        for ry, row in enumerate(rows):
            for rx, ch in enumerate(row):
                if ch in ICON_PAL:
                    put(px, rx + 1, ry + 2, ICON_PAL[ch])
        rim = [(x, y) for y in range(16) for x in range(16) if px[y][x][3] == 0 and any(0 <= x + dx < 16 and 0 <= y + dy < 16 and px[y + dy][x + dx][3] > 0 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)))]
        for x, y in rim:
            put(px, x, y, OUT_ICON)
        p = ROOT / "items" / f"{name}.png"
        write_png(p, 16, 16, px)
        out_paths.append(p)
    return out_paths
