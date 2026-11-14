#!/usr/bin/env python3
"""Procedural pixel-art generator for Stage 6 Night Wonders & Explorer Treasures (stdlib + gen_art.py only).

Generates:
1. assets/wildlife/spirit_stag.png & spirit_stag_glow.png
   - 6 cols x 2 rows of 64x64 (384x128 total), hooves/ground anchor at (32, 56).
   - Row 0 = Facing East (right), Row 1 = Facing West (left) with consistent top-left lighting (NOT a blind horizontal flip!).
   - Col 0: Peaceful grazing / serene idle breath A
   - Col 1: Serene idle breath B (tail/ear twitch)
   - Col 2: Alert head-raised pose (ears perked, neck tall, looking watchfully)
   - Col 3: Foreleg raised — pawing the mossy earth A
   - Col 4: Foreleg striking down — pawing the mossy earth B (uncovering hidden relic!)
   - Col 5: Graceful upward mist-leap / bow pose (dissolving into silver-turquoise starlight)
2. assets/props/star_crater.png & star_crater_glow.png
   - 3 cols x 1 row of 64x48 (192x48 total), center/ground anchor at (32, 28).
   - Col 0: Active Warm Star Crater | Col 1: Harvested / Mined Crater | Col 2: Cooled Dawn Stone.
3. 4 New 16x16 Item & Explorer Talisman Icons (assets/items/):
   - star_shard.png (Sternerz)
   - antler_talisman.png (Kronenhirsch-Reif — bracelet)
   - bell_chime_talisman.png (Glockenteich-Gehänge — earrings)
   - order_signet.png (Ordenssiegel der Wacht — necklace)
4. docs/img/night_wonders_sheet.png — QA preview sheet (Daylight + Night glow composite + 3x upscaled icons).
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from art_bush import check_icon  # noqa: E402
from gen_art import CLEAR, ROOT, hexc, outline_pass, write_png  # noqa: E402


def vnoise(x: float, y: float, s: int) -> float:
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def fbm(x: float, y: float, seed: int, octaves: int = 2) -> float:
    val, amp, freq, tot = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        val += amp * vnoise(x * freq, y * freq, seed + o * 131)
        tot += amp
        amp *= 0.5
        freq *= 2.0
    return val / max(1e-5, tot)

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# ---- Palettes (Strictly ZERO #000000 anywhere!) ----
STAG_OUT = hexc("1d1c32")   # Dark slate-indigo outline for Spirit Stag
ICON_OUT = hexc("1b1a2e")   # Standard Shadowspore dark plum-violet outline
SHADOW_RGB = (14, 16, 34)   # Cool translucent indigo-violet ground shadow

# Pearl-ivory & moonlight-silver coat ramp (`#565878 -> #888eb0 -> #c0c8e6 -> #eef4ff` with deep shadow base)
COAT = [hexc(c) for c in ("3b3d5c", "565878", "6f7496", "888eb0", "a4accb", "c0c8e6", "d8e0f5", "eef4ff")]
HOOF = [hexc(c) for c in ("262846", "3e466c", "64769e", "94b0cf")]
EYE_DARK = hexc("1e1d38")
MUZZLE_TIP = hexc("42466a")

# Crown antlers (`#6e9cb8 -> #a8dce8 -> #e8ffff`)
ANTLER = [hexc(c) for c in ("4d7492", "6e9cb8", "8cbcd4", "a8dce8", "cbf0f7", "e8ffff")]

# Spirit Stag & Wonder Glow palette (`#3cc0c6 -> #78f4e6 -> #eefbff`)
SPIRIT_DIM = hexc("2a8c94")
SPIRIT_MID = hexc("3cc0c6")
SPIRIT_BRIGHT = hexc("78f4e6")
SPIRIT_HOT = hexc("eefbff")

# Star Crater scorched violet earth + meadow turf + golden-violet meteorite core
SCORCH = [hexc(c) for c in ("18142b", "241c3c", "362954", "4e3b72", "6c5594", "9078b8")]
GRASS = [hexc(c) for c in ("19263c", "22483c", "31664c", "45865a", "64a868", "8cd07c")]
STAR_ORE = [hexc(c) for c in ("34185e", "522888", "6636ad", "9848b8", "d6723e", "ffb347", "ffd884", "fff2cc")]
SLAG = [hexc(c) for c in ("222038", "343150", "4c486c", "6a658c", "8d88ae", "b4afd2")]
STAR_VIO_GLOW = hexc("9468ee")
STAR_GOLD_MID = hexc("ffb347")
STAR_GOLD_HOT = hexc("fff4d2")

# Item icon ramps
BRONZE_VERD = [hexc(c) for c in ("1e3836", "2c544e", "427a6e", "64a694", "94d4be")]
GOLD_RAMP = [hexc(c) for c in ("5c4224", "8c6830", "bc9244", "e4bd64", "fff0a8")]
CRIMSON_RAMP = [hexc(c) for c in ("3e1628", "682238", "96324c", "c44a64", "ea788e")]
IRON_CHAIN = [hexc(c) for c in ("28263e", "464464", "6e6c90", "9e9cc0")]


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if col is None or col[3] == 0:
        return
    h = len(px)
    w = len(px[0])
    if 0 <= x < w and 0 <= y < h:
        if col[3] >= 255 or px[y][x][3] == 0:
            px[y][x] = col
        else:
             dst = px[y][x]
             sa = col[3] / 255.0
             da = dst[3] / 255.0
             oa = sa + da * (1.0 - sa)
             if oa > 1e-5:
                 r = int(round((col[0] * sa + dst[0] * da * (1.0 - sa)) / oa))
                 g = int(round((col[1] * sa + dst[1] * da * (1.0 - sa)) / oa))
                 b = int(round((col[2] * sa + dst[2] * da * (1.0 - sa)) / oa))
                 px[y][x] = (max(1, r), max(1, g), max(1, b), int(round(oa * 255)))


def hsh(x: int, y: int, seed: int) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


class GlowMap:
    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.buf = [[(0.0, 0.0, 0.0, 0.0) for _ in range(w)] for _ in range(h)]

    def add_px(self, x: int, y: int, col, alpha_scale: float = 1.0):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        a = clamp((col[3] / 255.0) * alpha_scale, 0.0, 1.0)
        if a <= 0.01:
            return
        cr, cg, cb, ca = self.buf[y][x]
        na = max(ca, a)
        w_new = a / max(1e-5, ca + a)
        nr = cr * (1.0 - w_new) + col[0] * w_new
        ng = cg * (1.0 - w_new) + col[1] * w_new
        nb = cb * (1.0 - w_new) + col[2] * w_new
        self.buf[y][x] = (nr, ng, nb, na)

    def emit(self, base_px, x: int, y: int, base_col, glow_col, halo: int = 1, halo_alpha: float = 0.28):
        if base_px is not None and base_col is not None:
            put(base_px, x, y, base_col)
        self.add_px(x, y, glow_col, 1.0)
        if halo > 0:
            for dy in range(-halo, halo + 1):
                for dx in range(-halo, halo + 1):
                    if dx == 0 and dy == 0:
                        continue
                    dist = math.hypot(dx, dy)
                    if dist <= halo + 0.35:
                        fall = halo_alpha * ((1.0 - dist / (halo + 0.65)) ** 1.45)
                        self.add_px(x + dx, y + dy, glow_col, fall)

    def finish(self):
        out = blank(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                r, g, b, a = self.buf[y][x]
                ia = int(round(a * 255))
                if ia >= 6:
                    out[y][x] = (max(6, int(round(r))), max(6, int(round(g))), max(8, int(round(b))), min(255, ia))
        return out


def compose_sheet(frames, cols: int, rows: int, fw: int, fh: int):
    out = blank(cols * fw, rows * fh)
    for idx, fr in enumerate(frames):
        c = idx % cols
        r = idx // cols
        ox, oy = c * fw, r * fh
        for y in range(fh):
            for x in range(fw):
                out[oy + y][ox + x] = fr[y][x]
    return out


# ==============================================================================
# 1. Der Weiße Kronenhirsch (`spirit_stag.png` & `spirit_stag_glow.png`)
#    6 cols x 2 rows of 64x64 (384x128 total), hooves/ground anchor at (32, 56)
# ==============================================================================
def render_stag_frame(col: int, facing: int):
    """Render one 64x64 frame of the White Crown Stag.
    `facing = +1` -> Row 0 (East / right)
    `facing = -1` -> Row 1 (West / left)
    Uses an articulated 3D ellipsoid/capsule anatomical rig mirrored in world X *before*
    evaluating top-left 3D surface normals (`L = (-0.54, -0.74, +0.40)`), ensuring true
    consistent top-left illumination in both directions!
    """
    W, H = 64, 64
    FX, FY = 32, 56
    body = blank(W, H)
    glow = GlowMap(W, H)
    seed = 5100 + col * 37 + (0 if facing > 0 else 500)

    def wx(dx: float) -> float:
        return FX + facing * dx

    # ---- Pose parameters in stag-local coordinates (+dx = forward toward chest/head, -dx = rump/tail) ----
    body_lift = 0.0
    pitch = 0.0  # positive = chest rises above rump (leap/rear)
    mist_dissolve = False
    uncover_spark = False

    if col == 0:
        # Col 0: Peaceful grazing / serene low-bowed breath A
        chest = (6.8, 39.2)
        rump = (-8.2, 38.6)
        head = (16.5, 45.5)
        muzzle = (21.2, 49.5)
        ear_back = (-3.6, -3.5)
        antler_tilt = 0.42  # tilted forward with bowed grazing head
        tail_dy = 1.5
        # Legs: (hip_dx, hip_y, knee_dx, knee_y, hoof_dx, hoof_y)
        legs_back = [
            (-9.2, 41.0, -10.5, 48.5, -9.8, 55.0),   # far hind
            (5.5, 41.5, 4.8, 48.5, 4.5, 55.0),       # far fore
        ]
        legs_front = [
            (-6.8, 41.5, -8.2, 48.8, -7.2, 55.5),    # near hind
            (8.0, 41.5, 8.8, 48.8, 9.2, 55.5),       # near fore
        ]
    elif col == 1:
        # Col 1: Serene idle breath B (graceful calm standing pose, ear & tail twitch!)
        chest = (6.8, 38.0)
        rump = (-8.2, 38.2)
        head = (12.8, 28.0)
        muzzle = (18.2, 29.5)
        ear_back = (-4.5, -3.2)  # ear twitched slightly back-up
        antler_tilt = 0.04
        tail_dy = -1.8  # tail flicked up!
        legs_back = [
            (-9.0, 40.8, -10.2, 48.2, -9.5, 55.0),
            (5.5, 40.8, 5.0, 48.2, 4.8, 55.0),
        ]
        legs_front = [
            (-6.6, 41.2, -7.8, 48.6, -6.8, 55.5),
            (7.8, 41.2, 7.8, 48.6, 8.0, 55.5),
        ]
    elif col == 2:
        # Col 2: Alert head-raised pose (neck tall & proud, ears perked forward-up, looking watchfully!)
        chest = (7.2, 37.2)
        rump = (-8.0, 38.4)
        head = (11.6, 24.5)
        muzzle = (17.2, 25.2)
        ear_back = (-2.4, -4.6)  # sharply perked upright!
        antler_tilt = -0.10
        tail_dy = -0.6
        legs_back = [
            (-9.2, 40.8, -10.4, 48.2, -9.8, 55.0),
            (5.8, 40.5, 5.5, 48.0, 5.5, 55.0),
        ]
        legs_front = [
            (-6.6, 41.2, -7.6, 48.6, -6.8, 55.5),
            (8.2, 40.8, 8.6, 48.4, 9.0, 55.5),
        ]
    elif col == 3:
        # Col 3: Foreleg raised — pawing the mossy earth A (high arched fore-knee!)
        chest = (6.8, 37.6)
        rump = (-8.2, 38.4)
        head = (13.4, 30.2)
        muzzle = (18.4, 32.8)
        ear_back = (-3.2, -3.8)
        antler_tilt = 0.14
        tail_dy = 0.4
        legs_back = [
            (-9.2, 40.8, -10.2, 48.2, -9.5, 55.0),
            (5.4, 40.8, 4.8, 48.2, 4.6, 55.2),
        ]
        legs_front = [
            (-6.6, 41.2, -7.8, 48.6, -6.8, 55.5),
            (8.0, 40.6, 13.8, 44.2, 11.4, 49.8),  # raised curled foreleg!
        ]
    elif col == 4:
        # Col 4: Foreleg striking down — pawing the mossy earth B (uncovering the hidden relic spark!)
        chest = (7.2, 38.8)
        rump = (-8.0, 38.2)
        head = (14.4, 33.0)
        muzzle = (19.0, 36.2)
        ear_back = (-2.8, -3.6)
        antler_tilt = 0.22
        tail_dy = -1.0
        uncover_spark = True
        legs_back = [
            (-9.2, 40.8, -10.4, 48.2, -9.6, 55.0),
            (5.2, 41.2, 4.2, 48.4, 3.8, 55.2),
        ]
        legs_front = [
            (-6.6, 41.0, -7.8, 48.6, -6.8, 55.5),
            (8.2, 41.2, 12.2, 48.2, 15.2, 55.5),  # striking mossy ground forward!
        ]
    else:
        # Col 5: Graceful upward mist-leap / bow pose (dissolving into silver-turquoise starlight!)
        chest = (7.4, 31.8)
        rump = (-8.2, 37.5)
        head = (12.2, 20.8)
        muzzle = (17.6, 21.8)
        ear_back = (-3.8, -4.0)
        antler_tilt = -0.16
        tail_dy = -2.2
        mist_dissolve = True
        legs_back = [
            (-9.2, 39.8, -13.0, 45.8, -15.5, 51.5),
            (6.2, 34.8, 11.2, 38.8, 9.2, 43.8),
        ]
        legs_front = [
            (-7.0, 40.2, -10.8, 46.5, -13.2, 52.5),
            (8.4, 35.0, 14.5, 38.2, 13.0, 44.2),
        ]

    # Z-buffer + 3D normal buffer + material tag (`0=coat`, `1=far_leg`, `2=hoof`, `3=antler`)
    zbuf = [[-1e9 for _ in range(W)] for _ in range(H)]
    nbuf = [[None for _ in range(W)] for _ in range(H)]
    mbuf = [[-1 for _ in range(W)] for _ in range(H)]

    def add_ellipsoid(cx: float, cy: float, rx: float, ry: float, z_base: float, mat: int, rot: float = 0.0):
        ca, sa = math.cos(rot), math.sin(rot)
        pad = int(max(rx, ry)) + 2
        for y in range(max(1, int(cy) - pad), min(H - 1, int(cy) + pad + 1)):
            for x in range(max(1, int(cx) - pad), min(W - 1, int(cx) + pad + 1)):
                dx0 = x + 0.5 - cx
                dy0 = y + 0.5 - cy
                lx = (dx0 * ca + dy0 * sa) / max(0.45, rx)
                ly = (-dx0 * sa + dy0 * ca) / max(0.45, ry)
                r2 = lx * lx + ly * ly
                if r2 <= 1.0:
                    lz = math.sqrt(max(0.0, 1.0 - r2))
                    z = z_base + lz * min(rx, ry)
                    if z >= zbuf[y][x]:
                        # Rotate normal back to screen space
                        nx = lx * ca - ly * sa
                        ny = lx * sa + ly * ca
                        nlen = math.hypot(nx, ny, lz)
                        zbuf[y][x] = z
                        nbuf[y][x] = (nx / nlen, ny / nlen, lz / nlen)
                        mbuf[y][x] = mat

    def add_capsule(x0: float, y0: float, r0: float, x1: float, y1: float, r1: float, z_base: float, mat: int, steps: int = 16):
        for i in range(steps + 1):
            t = i / float(steps)
            cx = x0 + (x1 - x0) * t
            cy = y0 + (y1 - y0) * t
            rr = r0 + (r1 - r0) * t
            add_ellipsoid(cx, cy, rr, rr, z_base, mat)

    # 1) Far-side legs (`mat = 1`, slightly darker cool shade behind torso)
    for hx0, hy0, kx, ky, fx0, fy0 in legs_back:
        add_capsule(wx(hx0), hy0, 2.3, wx(kx), ky, 1.4, -4.0, 1, steps=12)
        add_capsule(wx(kx), ky, 1.35, wx(fx0), fy0 - 1.0, 1.05, -4.0, 1, steps=12)
        add_ellipsoid(wx(fx0 + 0.4), fy0 - 0.3, 1.5, 1.1, -3.8, 2)

    # 2) Smooth Sculpted Stag Torso Capsule (eliminates segmented seams across chest, flank & hindquarters!)
    for i in range(17):
        t = i / 16.0  # 0 at rump -> 1 at chest
        bx = rump[0] + (chest[0] - rump[0]) * t
        # Slight natural topline dip across saddle (`t ~ 0.45`) and deep proud brisket at chest (`t > 0.72`)
        by = rump[1] + (chest[1] - rump[1]) * t + 0.55 * math.sin(t * math.pi)
        rx_b = 5.4 + 0.6 * math.sin(t * math.pi)
        ry_b = 4.65 - 0.35 * math.sin(t * math.pi) + (0.85 * ((t - 0.55) / 0.45) if t > 0.55 else 0.0)
        add_ellipsoid(wx(bx), by, rx_b, ry_b, 0.3 + 0.3 * t, 0)
    # Graceful S-curved neck from chest to head (`13` dense capsules)
    for i in range(13):
        t = i / 12.0
        arch_dx = chest[0] + (head[0] - chest[0]) * t - 0.8 * math.sin(t * math.pi)
        arch_dy = chest[1] + (head[1] - chest[1]) * t + 0.6 * math.sin(t * math.pi)
        r_neck = 4.25 * (1.0 - 0.44 * t)
        add_ellipsoid(wx(arch_dx), arch_dy, r_neck, r_neck * 1.05, 0.8, 0)
    # Dewlap / proud chest mane fluff blended seamlessly into lower chest
    add_ellipsoid(wx(chest[0] + 2.0), chest[1] + 1.2, 3.8, 4.1, 0.75, 0)

    # Fluffy white stag tail
    tx0, ty0 = rump[0] - 4.6, rump[1] - 1.6
    add_capsule(wx(tx0), ty0, 1.8, wx(tx0 - 3.2), ty0 + tail_dy, 1.2, 0.2, 0, steps=6)

    # 3) Sculpted Noble Stag Head, Tapered Muzzle & Perked Ears
    add_ellipsoid(wx(head[0]), head[1], 3.5, 2.9, 1.5, 0)
    add_capsule(wx(head[0] + 1.2), head[1] + 0.3, 2.5, wx(muzzle[0]), muzzle[1], 1.45, 1.6, 0, steps=8)
    # Far ear & Near ear
    add_capsule(wx(head[0] - 0.6), head[1] - 1.8, 1.2, wx(head[0] + ear_back[0] + 1.4), head[1] + ear_back[1] - 0.6, 0.7, -1.0, 1, steps=6)
    add_capsule(wx(head[0] - 1.2), head[1] - 1.5, 1.35, wx(head[0] + ear_back[0]), head[1] + ear_back[1], 0.75, 2.2, 0, steps=6)

    # 4) Near-side legs (`mat = 0` + `mat = 2` hooves)
    for hx0, hy0, kx, ky, fx0, fy0 in legs_front:
        add_capsule(wx(hx0), hy0, 2.6, wx(kx), ky, 1.5, 2.0, 0, steps=12)
        add_capsule(wx(kx), ky, 1.4, wx(fx0), fy0 - 1.0, 1.1, 2.0, 0, steps=12)
        add_ellipsoid(wx(fx0 + 0.4), fy0 - 0.3, 1.65, 1.15, 2.3, 2)

    # 5) Grand 6-Point Crown Antlers (`mat = 3`, sweeping back-and-up with curving royal tines!)
    ct, st = math.cos(antler_tilt), math.sin(antler_tilt)

    def ant_pt(adx: float, ady: float):
        rx_a = adx * ct - ady * st
        ry_a = adx * st + ady * ct
        return wx(head[0] + rx_a), head[1] - 2.2 + ry_a

    # Far antler beam (slightly offset forward/up for rich 3/4 depth) + Near royal crown beam
    tine_tips = []
    for is_near in (False, True):
        z_a = 3.2 if is_near else -2.0
        ox = 0.0 if is_near else 2.2
        oy = 0.0 if is_near else -1.0
        b0 = ant_pt(-0.4 + ox, 0.0 + oy)
        b1 = ant_pt(-3.8 + ox, -4.8 + oy)
        b2 = ant_pt(-7.2 + ox, -9.2 + oy)
        b3 = ant_pt(-4.8 + ox, -13.6 + oy)  # sweeping royal crown tip!
        add_capsule(b0[0], b0[1], 1.1, b1[0], b1[1], 0.95, z_a, 3, steps=8)
        add_capsule(b1[0], b1[1], 0.95, b2[0], b2[1], 0.85, z_a, 3, steps=8)
        add_capsule(b2[0], b2[1], 0.85, b3[0], b3[1], 0.72, z_a, 3, steps=8)
        # Brow tine (curving forward), bez tine (up-forward), royal rear tine (up-back)
        t1 = ant_pt(2.4 + ox, -5.8 + oy)
        t2 = ant_pt(-1.0 + ox, -10.8 + oy)
        t3 = ant_pt(-9.6 + ox, -12.4 + oy)
        add_capsule(b1[0], b1[1], 0.8, t1[0], t1[1], 0.65, z_a, 3, steps=6)
        add_capsule(b2[0], b2[1], 0.8, t2[0], t2[1], 0.65, z_a, 3, steps=6)
        add_capsule(b2[0], b2[1], 0.75, t3[0], t3[1], 0.65, z_a, 3, steps=6)
        tine_tips.extend([b3, t1, t2, t3])

    # ---- Shade Z-buffer with true Top-Left 3D Illumination (`L = (-0.54, -0.74, 0.40)`) ----
    Lx, Ly, Lz = -0.54, -0.74, 0.40
    for y in range(H):
        for x in range(W):
            mat = mbuf[y][x]
            if mat < 0:
                continue
            # Col 5 mist-leap: dithered upward starlight dissolution along the lower legs & trailing tail!
            if mist_dissolve:
                trail_factor = ((y - 36.0) / 17.0) + 0.25 * ((FX - x) * facing / 16.0)
                if trail_factor > 0.35:
                    b_thr = BAYER[y % 4][x % 4] / 16.0
                    if trail_factor - 0.35 > b_thr * 0.78:
                        if hsh(x, y, seed + 99) > 0.62:
                            glow.emit(body, x, y, SPIRIT_BRIGHT, SPIRIT_HOT, halo=0)
                        continue

            nx, ny, nz = nbuf[y][x]
            ndotl = nx * Lx + ny * Ly + nz * Lz
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
            fur_tex = (fbm(x * 0.25, y * 0.25, seed, octaves=2) - 0.5) * 0.16

            if mat == 3:
                # Radiant silver-turquoise crown antlers
                idx = int(clamp((ndotl + 0.48 + fur_tex) * 4.5 + dith, 0, len(ANTLER) - 1))
                put(body, x, y, ANTLER[idx])
            elif mat == 2:
                # Slate-silver hooves
                idx = int(clamp((ndotl + 0.45) * 3.0 + dith, 0, len(HOOF) - 1))
                put(body, x, y, HOOF[idx])
            else:
                # Pearl-ivory coat (far legs darkened by 1.5 steps for clean leg separation!)
                bias = -0.24 if mat == 1 else 0.04
                idx = int(clamp((ndotl + 0.50 + bias + fur_tex) * 5.8 + dith, 0, len(COAT) - 1))
                put(body, x, y, COAT[idx])

    # Crisp facial details: dark slate-indigo serene eye + luminous turquoise eye spark + nose tip
    ex = int(round(wx(head[0] + 1.4)))
    ey = int(round(head[1] - 0.2))
    put(body, ex, ey, EYE_DARK)
    put(body, ex - facing, ey, EYE_DARK)
    glow.emit(body, ex, ey - 1, SPIRIT_BRIGHT, SPIRIT_HOT, halo=1, halo_alpha=0.22)
    mx = int(round(wx(muzzle[0])))
    my = int(round(muzzle[1]))
    put(body, mx, my, MUZZLE_TIP)

    # Ethereal glow on all 6+ crown antler tips & suspended starlight dew-motes!
    for idx_t, (tx, ty) in enumerate(tine_tips):
        ix, iy = int(round(tx)), int(round(ty))
        glow.emit(body, ix, iy, ANTLER[5], SPIRIT_HOT if idx_t % 2 == 0 else SPIRIT_BRIGHT, halo=1, halo_alpha=0.30)

    # Floating starlight dew-motes around the crown antlers & spirit aura
    mote_offsets = [(-11.0, -14.5), (3.5, -12.0), (-4.0, -16.5)]
    if mist_dissolve:
        mote_offsets.extend([(-13.5, 16.0), (-9.0, 21.0), (4.0, 18.0), (11.0, 14.0), (-2.0, 15.0)])
    for mdx, mdy in mote_offsets:
        if mdy < 0:
            mx_p, my_p = ant_pt(mdx, mdy)
        else:
            mx_p, my_p = wx(mdx), 30.0 + mdy
        ix, iy = int(round(mx_p)), int(round(my_p))
        if 2 <= ix < W - 2 and 2 <= iy < H - 2:
            glow.emit(body, ix, iy, SPIRIT_BRIGHT, SPIRIT_HOT, halo=1, halo_alpha=0.26)

    # Col 4 special: uncovering the hidden relic spark under the striking forehoof!
    if uncover_spark:
        sx = int(round(wx(16.2)))
        sy = 55
        glow.emit(body, sx, sy, STAR_ORE[7], SPIRIT_HOT, halo=2, halo_alpha=0.35)
        glow.emit(body, sx + facing * 2, sy - 2, SPIRIT_BRIGHT, SPIRIT_BRIGHT, halo=1, halo_alpha=0.25)

    # 1px dark slate-indigo outline (`#1d1c32`) + soft ground shadow ellipse at `(32, 56)`
    outlined = outline_pass(body, STAG_OUT)
    out = blank(W, H)
    sh_rx = 14.5 if mist_dissolve else 18.5
    sh_alpha = 72 if mist_dissolve else 112
    for y in range(FY - 5, min(H, FY + 6)):
        for x in range(FX - 22, FX + 23):
            if 0 <= x < W and 0 <= y < H:
                d = ((x - FX) / sh_rx) ** 2 + ((y - FY) / 4.2) ** 2
                if d <= 1.0:
                    out[y][x] = (*SHADOW_RGB, int(sh_alpha * ((1.0 - d) ** 1.35)))

    for y in range(H):
        for x in range(W):
            if outlined[y][x][3] > 0:
                put(out, x, y, outlined[y][x])

    return out, glow.finish()


# ==============================================================================
# 2. Sternschnuppen-Krater (`star_crater.png` & `star_crater_glow.png`)
#    3 cols x 1 row of 64x48 (192x48 total), center/ground anchor at (32, 28)
# ==============================================================================
def build_star_crater_col(col: int):
    """Col 0 = Active Warm Star Crater; Col 1 = Harvested/Mined Crater; Col 2 = Cooled Dawn Stone."""
    W, H = 64, 48
    CX, CY = 32, 28
    seed = 6200 + col * 41
    body = blank(W, H)
    glow = GlowMap(W, H)

    # 1) Scorched Violet-Earth Ejecta Rim & Bowl (`~48x28 px` 3/4 oval centered at `(32, 28)`)
    RX, RY = 23.5, 13.5
    for y in range(CY - 16, CY + 17):
        for x in range(CX - 26, CX + 27):
            if not (1 <= x < W - 1 and 1 <= y < H - 1):
                continue
            dx = (x + 0.5 - CX) / RX
            dy = (y + 0.5 - CY) / RY
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            # Jagged ejecta scalloping around outer lip
            jag = 0.08 * math.sin(ang * 7.0 + 0.8) + 0.05 * math.cos(ang * 11.0 - 0.4)
            r_eff = r + jag
            if r_eff > 1.04:
                continue

            n = fbm(x * 0.22, y * 0.22, seed, octaves=2) - 0.5
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.48

            if r_eff >= 0.70:
                # Raised crater lip! Outer slope lit on top-left; inner bowl wall lit on bottom-right!
                lip_t = (r_eff - 0.70) / 0.34  # 0 at inner crest -> 1 at outer skirt
                if lip_t > 0.45:
                    # Outer ejecta slope + singed meadow sod tufts at skirt edge
                    if r_eff > 0.90 and hsh(x, y, seed + 5) > 0.45:
                        g_idx = int(clamp((0.55 - 0.28 * dx - 0.28 * dy + n * 0.4) * 5.2 + dith, 0, 5))
                        put(body, x, y, GRASS[g_idx])
                        continue
                    lit = 0.62 - 0.30 * dx - 0.32 * dy + n * 0.35
                else:
                    # Crest ridge catch-light!
                    lit = 0.76 - 0.20 * dx - 0.22 * dy + n * 0.30
                idx = int(clamp(lit * 5.6 + dith, 0, 5))
                put(body, x, y, SCORCH[idx])
            else:
                # Concave crater pit interior (`r_eff < 0.70`): top-left inner wall is in shadow, bottom-right catches sky light, deepest pit at center!
                pit_t = max(0.0, r_eff / 0.70)
                lit = 0.16 + 0.28 * (pit_t ** 1.3) + 0.16 * dx + 0.18 * dy + n * 0.28
                # Radial impact fracture grooves inside bowl
                if abs(math.sin(ang * 5.0 + 0.3)) < 0.12 and pit_t > 0.28:
                    lit -= 0.16
                # Warm inner core bounce-light in Col 0!
                if col == 0 and pit_t < 0.58:
                    lit += (0.58 - pit_t) * 0.55
                idx = int(clamp(lit * 5.5 + dith, 0, 5))
                put(body, x, y, SCORCH[idx])

    # 2) Centerpiece per State (`Col 0` = Active Star-Ore Core, `Col 1` = Mined Hollow, `Col 2` = Cooled Dawn Slag)
    if col == 0:
        # Jagged, multi-faceted golden-violet celestial meteorite core (`~16x12 px` centered at `(32, 27)`)
        for y in range(CY - 8, CY + 6):
            for x in range(CX - 9, CX + 10):
                dx_m = (x - CX) / 8.2
                dy_m = (y - (CY - 1.2)) / 5.8
                ang_m = math.atan2(dy_m, dx_m)
                crystal = 0.84 + 0.18 * math.cos(ang_m * 3.0 - 0.7) + 0.10 * math.sin(ang_m * 5.0)
                rm = math.hypot(dx_m, dy_m) / crystal
                if rm <= 1.0:
                    # Faceted crystal planes: crisp angular facets + glowing molten-starlight heart!
                    facet = (0.22 if dx_m < -0.15 and dy_m < 0.1 else (-0.15 if dx_m > 0.25 else 0.04))
                    core_heat = max(0.0, 1.0 - rm * 1.18)
                    val = clamp(core_heat * 0.78 + facet + 0.16, 0.0, 1.0)
                    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.35
                    idx = int(clamp(val * 7.6 + dith, 0, 7))
                    put(body, x, y, STAR_ORE[idx])
                    # Unlit glow map: violet outer veins + radiant amber-gold starlight core!
                    if rm < 0.48:
                        glow.emit(None, x, y, None, STAR_GOLD_HOT if rm < 0.24 else STAR_GOLD_MID, halo=1 if rm < 0.22 else 0, halo_alpha=0.30)
                    elif rm < 0.82 and (x + y) % 2 == 0:
                        glow.emit(None, x, y, None, STAR_VIO_GLOW, halo=0)

        # Glowing violet-gold impact veins & warm grass embers around the active crater!
        ember_pts = [
            (CX - 11, CY - 2, True), (CX + 11, CY + 1, True), (CX - 6, CY + 6, False),
            (CX + 7, CY - 6, False), (CX - 16, CY + 4, True), (CX + 15, CY - 4, True),
            (CX - 3, CY - 8, True), (CX + 4, CY + 7, True),
        ]
        for ex, ey, is_gold in ember_pts:
            b_col = STAR_ORE[6] if is_gold else STAR_ORE[3]
            g_col = STAR_GOLD_MID if is_gold else STAR_VIO_GLOW
            glow.emit(body, ex, ey, b_col, g_col, halo=1, halo_alpha=0.25)

    elif col == 1:
        # Col 1 (Harvested / Mined Crater): Empty fractured socket where the core was pried free + faint residual shimmer specks!
        for y in range(CY - 4, CY + 5):
            for x in range(CX - 6, CX + 7):
                d_s = ((x - CX) / 6.0) ** 2 + ((y - CY) / 3.8) ** 2
                if d_s <= 1.0:
                    put(body, x, y, SCORCH[0 if d_s < 0.55 else 1])
        # Small chipped rock fragments + 4 faint shimmer dust specks
        for fx_p, fy_p in [(CX - 7, CY + 1), (CX + 6, CY + 2), (CX - 2, CY - 4)]:
            put(body, fx_p, fy_p, SLAG[3])
        for gx_p, gy_p, is_g in [(CX - 3, CY, True), (CX + 2, CY + 1, False), (CX + 4, CY - 2, True), (CX - 5, CY + 2, False)]:
            glow.emit(body, gx_p, gy_p, STAR_ORE[5] if is_g else STAR_ORE[3], STAR_GOLD_MID if is_g else STAR_VIO_GLOW, halo=0)

    else:
        # Col 2 (Cooled Dawn Stone): Porous grey-violet meteoritic slag lump at dawn, zero glow!
        for y in range(CY - 7, CY + 5):
            for x in range(CX - 8, CX + 9):
                dx_s = (x - CX) / 7.5
                dy_s = (y - (CY - 1.0)) / 5.2
                ang_s = math.atan2(dy_s, dx_s)
                lump = 0.86 + 0.14 * math.cos(ang_s * 3.0 - 0.5)
                rs = math.hypot(dx_s, dy_s) / lump
                if rs <= 1.0:
                    # Porous meteorite regmaglypt pits + top-left morning stone lighting
                    pit = ((x * 3 + y * 5) % 11 == 0 and rs < 0.78)
                    lit = 0.18 if pit else (0.62 - 0.32 * dx_s - 0.30 * dy_s)
                    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42
                    put(body, x, y, SLAG[int(clamp(lit * 5.4 + dith, 0, 5))])
        # Fresh morning grass shoots around cooled crater rim
        for gx, gy in [(CX - 18, CY + 5), (CX + 17, CY + 4), (CX - 12, CY - 9)]:
            put(body, gx, gy, GRASS[4])
            put(body, gx, gy - 1, GRASS[5])

    framed = outline_pass(body, ICON_OUT)
    return framed, glow.finish()


# ==============================================================================
# 3. 4 New 16x16 Item & Explorer Talisman Icons (`assets/items/`)
#    Interior kept strictly within [2..13] so 1px `#1b1a2e` outline stays crisp in [1..14]!
# ==============================================================================
def build_icon_star_shard():
    """`star_shard.png` (Sternerz): Faceted warm gold-and-violet meteorite crystal shard with tiny starlight spark."""
    px = blank(16, 16)
    # Diagonal faceted celestial crystal (`(4, 12)` -> `(11, 4)`)
    for y in range(2, 14):
        for x in range(2, 14):
            u = (x - 7.5) * 0.68 + (y - 8.2) * (-0.73)
            v = (x - 7.5) * 0.73 + (y - 8.2) * 0.68
            max_w = 3.8 * (1.0 - abs(u) / 6.2)
            if max_w > 0.35 and abs(v) <= max_w:
                if abs(u) < 2.2 and abs(v) < 1.15:
                    col = STAR_ORE[7] if v <= 0 else STAR_ORE[6]
                elif v < -0.25:
                    col = STAR_ORE[6] if u > -1.0 else STAR_ORE[5]
                elif v < 0.75:
                    col = STAR_ORE[4] if u > 0 else STAR_ORE[3]
                else:
                    col = STAR_ORE[2] if u < 1.5 else STAR_ORE[1]
                px[y][x] = col
    # Connected starlight glint on the upper-right crystal tip (`(11, 3)` touching `(10, 4)`)
    px[4][10] = STAR_ORE[7]
    px[3][11] = SPIRIT_HOT
    px[3][10] = SPIRIT_BRIGHT
    px[4][11] = SPIRIT_BRIGHT
    check_icon("star_shard", px)
    return outline_pass(px, ICON_OUT)


def build_icon_antler_talisman():
    """`antler_talisman.png` (Kronenhirsch-Reif): Silver-ivory antler-branch bracelet cradling a glowing turquoise dew-gem."""
    px = blank(16, 16)
    cx, cy = 7.5, 8.5
    for y in range(3, 14):
        for x in range(2, 14):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            # Open C-cuff bracelet (`r in 3.1..5.1`), open crown gap at top (`-2.05 < ang < -1.10`)
            if 3.1 <= r <= 5.15 and not (-2.05 < ang < -1.08):
                lit = -0.55 * (dx / 5.0) - 0.65 * (dy / 5.0)
                idx = int(clamp((lit + 0.55) * 4.8, 1, 5))
                px[y][x] = ANTLER[idx]
    # Branching silver antler tines bridging inward from both cuff tips (`x=5..6` & `x=9..10`) to cradle the dew-gem!
    for tx, ty, ci in [(4, 3, 5), (5, 4, 4), (6, 4, 5), (3, 5, 4), (11, 3, 4), (10, 4, 5), (9, 4, 4), (12, 5, 3)]:
        px[ty][tx] = ANTLER[ci]
    # Radiant turquoise dew-gem cradled directly between the antler prongs (`x=7..8, y=3..5`)!
    px[4][7] = SPIRIT_HOT
    px[4][8] = SPIRIT_BRIGHT
    px[3][7] = SPIRIT_BRIGHT
    px[5][7] = SPIRIT_MID
    px[5][8] = SPIRIT_DIM
    check_icon("antler_talisman", px)
    return outline_pass(px, ICON_OUT)


def build_icon_bell_chime_talisman():
    """`bell_chime_talisman.png` (Glockenteich-Gehänge): Pair of miniature verdigris-bronze & moon-gold bell earrings with teal glint."""
    px = blank(16, 16)

    def draw_mini_bell(bx: int, by: int):
        # Gold ear-hook loop (`by - 3 .. by - 1`)
        px[by - 3][bx] = GOLD_RAMP[3]
        px[by - 2][bx - 1] = GOLD_RAMP[4]
        px[by - 1][bx] = GOLD_RAMP[2]
        # Verdigris-bronze bell dome (`by .. by + 2`, 3 px wide) + flared gold sound-bow (`by + 3`, 5 px wide)
        for dy in range(0, 3):
            for dx in (-1, 0, 1):
                px[by + dy][bx + dx] = BRONZE_VERD[4 if dx < 0 and dy < 2 else (3 if dx == 0 else 1)]
        for dx in (-2, -1, 0, 1, 2):
            px[by + 3][bx + dx] = GOLD_RAMP[4 if dx < 0 else (3 if dx == 0 else 1)]
        # Glowing teal clapper pearl underneath (`by + 4`)
        px[by + 4][bx] = SPIRIT_HOT
        px[by + 1][bx - 1] = SPIRIT_BRIGHT

    # Staggered pair of miniature belfry earrings (`left at (5, 5)`, `right at (10, 7)` — rims meet via outline, linked by fine gold clasp hook!)
    draw_mini_bell(5, 5)
    draw_mini_bell(10, 7)
    # Fine moon-gold jewellery ring connecting the pair at `(7, 4) -> (9, 4)` so `check_icon` sees one cohesive talisman cluster!
    px[3][6] = GOLD_RAMP[3]
    px[3][7] = GOLD_RAMP[4]
    px[4][8] = GOLD_RAMP[2]
    check_icon("bell_chime_talisman", px)
    return outline_pass(px, ICON_OUT)


def build_icon_order_signet():
    """`order_signet.png` (Ordenssiegel der Wacht): Weathered crimson-enamel & gold Red Order sun-shield pendant on an iron chain."""
    px = blank(16, 16)
    # Iron neck-chain loop at top (`y = 2..6, x = 4..11`)
    chain_pts = [(5, 2), (10, 2), (4, 3), (11, 3), (4, 4), (11, 4), (5, 5), (10, 5), (6, 6), (9, 6)]
    for cx_p, cy_p in chain_pts:
        px[cy_p][cx_p] = IRON_CHAIN[3 if cx_p < 8 else 1]

    # Heater-shield pendant (`x = 4..11, y = 6..13`) with gold bezel, crimson enamel field & radiant gold sun-core!
    for y in range(6, 14):
        t = (y - 6) / 7.0
        hw = 3.6 if t < 0.45 else 3.6 * (1.0 - 0.78 * ((t - 0.45) / 0.55))
        for x in range(int(round(7.5 - hw)), int(round(7.5 + hw)) + 1):
            dx = x - 7.5
            is_rim = (y == 6) or (abs(dx) >= hw - 0.85)
            if is_rim:
                px[y][x] = GOLD_RAMP[4 if dx < 0 and y < 10 else (3 if dx < 0.5 else 1)]
            else:
                px[y][x] = CRIMSON_RAMP[3 if dx < 0 else 1]

    # Red Order Sun-Cross / Sunburst emblem in the heart of the crimson shield (`x=6..9, y=8..11`)
    px[9][7] = GOLD_RAMP[4]
    px[9][8] = GOLD_RAMP[4]
    px[8][7] = GOLD_RAMP[3]
    px[10][8] = GOLD_RAMP[2]
    check_icon("order_signet", px)
    return outline_pass(px, ICON_OUT)


# ==============================================================================
# 4. QA Contact Sheet (`docs/img/night_wonders_sheet.png`)
# ==============================================================================
def blit(dst, src, ox: int, oy: int, scale: int = 1):
    sh = len(src)
    sw = len(src[0])
    for y in range(sh):
        for x in range(sw):
            c = src[y][x]
            if c[3] == 0:
                continue
            for sy in range(scale):
                for sx in range(scale):
                    put(dst, ox + x * scale + sx, oy + y * scale + sy, c)


def blit_night(dst, base, glow, ox: int, oy: int):
    sh = len(base)
    sw = len(base[0])
    for y in range(sh):
        for x in range(sw):
            c = base[y][x]
            if c[3] > 0:
                nr = max(6, int(c[0] * 0.42))
                ng = max(8, int(c[1] * 0.46))
                nb = max(16, min(255, int(c[2] * 0.64 + 10)))
                put(dst, ox + x, oy + y, (nr, ng, nb, c[3]))
            if glow is not None:
                g = glow[y][x]
                if g[3] > 0:
                    put(dst, ox + x, oy + y, g)


def build_qa_sheet(stag_frames, stag_glows, crater_frames, crater_glows, icons):
    W, H = 560, 420
    qa = blank(W, H)
    # Top half (`y = 0..209`): Daylight meadow turf; Bottom half (`y = 210..419`): Starlit Night meadow turf!
    for y in range(H):
        is_night = y >= 210
        for x in range(W):
            n = hsh(x // 3, y // 3, 9101)
            if not is_night:
                qa[y][x] = GRASS[2] if n < 0.35 else (GRASS[3] if n < 0.78 else GRASS[4])
            else:
                qa[y][x] = hexc("13182e") if n < 0.45 else (hexc("18223a") if n < 0.82 else hexc("1e2c48"))

    # Stamp all 12 Spirit Stag frames (`6 cols x 2 rows` on left `x = 8..400`)
    for r in range(2):
        for c in range(6):
            idx = r * 6 + c
            ox = 8 + c * 65
            oy_day = 10 + r * 92
            oy_night = 220 + r * 92
            blit(qa, stag_frames[idx], ox, oy_day)
            blit_night(qa, stag_frames[idx], stag_glows[idx], ox, oy_night)

    # Stamp all 3 Star Crater states on right (`x = 408..552`, stacked vertically)
    for c in range(3):
        ox = 414
        oy_day = 8 + c * 52
        oy_night = 218 + c * 52
        blit(qa, crater_frames[c], ox, oy_day)
        blit_night(qa, crater_frames[c], crater_glows[c], ox, oy_night)

    # Stamp 4 new `16x16` Icons at `2x` & `3x` upscale along the bottom-right showcase bar (`x = 406..554`)
    for idx_i, ic in enumerate(icons):
        ox = 404 + idx_i * 38
        # Dark slate showcase backing pad
        for py in range(164, 206):
            for px_i in range(ox - 2, ox + 34):
                put(qa, px_i, py, hexc("1c1b30"))
        for py in range(374, 416):
            for px_i in range(ox - 2, ox + 34):
                put(qa, px_i, py, hexc("161528"))
        blit(qa, ic, ox, 169, scale=2)
        blit(qa, ic, ox, 379, scale=2)

    return qa


def main():
    wildlife_dir = ROOT / "wildlife"
    props_dir = ROOT / "props"
    items_dir = ROOT / "items"
    docs_dir = ROOT.parent / "docs" / "img"
    wildlife_dir.mkdir(parents=True, exist_ok=True)
    props_dir.mkdir(parents=True, exist_ok=True)
    items_dir.mkdir(parents=True, exist_ok=True)
    docs_dir.mkdir(parents=True, exist_ok=True)

    # 1. Spirit Stag (`6 cols x 2 rows` of `64x64` = `384x128`)
    stag_frames, stag_glows = [], []
    for facing in (+1, -1):  # Row 0 = East (+1), Row 1 = West (-1)
        for col in range(6):
            fr, gl = render_stag_frame(col, facing)
            stag_frames.append(fr)
            stag_glows.append(gl)
    write_png(wildlife_dir / "spirit_stag.png", 384, 128, compose_sheet(stag_frames, 6, 2, 64, 64))
    write_png(wildlife_dir / "spirit_stag_glow.png", 384, 128, compose_sheet(stag_glows, 6, 2, 64, 64))

    # 2. Star Crater (`3 cols x 1 row` of `64x48` = `192x48`)
    crater_pairs = [build_star_crater_col(c) for c in range(3)]
    crater_frames = [p[0] for p in crater_pairs]
    crater_glows = [p[1] for p in crater_pairs]
    write_png(props_dir / "star_crater.png", 192, 48, compose_sheet(crater_frames, 3, 1, 64, 48))
    write_png(props_dir / "star_crater_glow.png", 192, 48, compose_sheet(crater_glows, 3, 1, 64, 48))

    # 3. 4 New 16x16 Item & Explorer Talisman Icons
    ic_shard = build_icon_star_shard()
    ic_antler = build_icon_antler_talisman()
    ic_bell = build_icon_bell_chime_talisman()
    ic_signet = build_icon_order_signet()
    write_png(items_dir / "star_shard.png", 16, 16, ic_shard)
    write_png(items_dir / "antler_talisman.png", 16, 16, ic_antler)
    write_png(items_dir / "bell_chime_talisman.png", 16, 16, ic_bell)
    write_png(items_dir / "order_signet.png", 16, 16, ic_signet)

    # 4. QA Sheet
    qa = build_qa_sheet(stag_frames, stag_glows, crater_frames, crater_glows, [ic_shard, ic_antler, ic_bell, ic_signet])
    write_png(docs_dir / "night_wonders_sheet.png", len(qa[0]), len(qa), qa)
    print("Wrote 8 Night Wonders PNGs and docs/img/night_wonders_sheet.png")


if __name__ == "__main__":
    main()
