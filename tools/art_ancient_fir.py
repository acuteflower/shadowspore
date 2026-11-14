#!/usr/bin/env python3
"""High-detail procedural pixel-art generator for Stage 2 Habitat 1 — Der Tiefe Urforst / Dunkeltannen-Dom (stdlib only):
  assets/props/ancient_fir.png         3 cols x 4 rows of 192x224 (576x896), feet at (96, 216):
                                       Row 0: trunk + mossy buttress roots + ground shadow + bracket shelf fungi + glowing veins
                                       Row 1: massive cathedral conifer crowns (crown_half_width=[64, 72, 80],
                                              height=[178, 196, 210], clear=[26, 30, 34]) built from layered multi-cushion
                                              drooping needle pads with exposed crooked bough elbows, cones, and beard-moss
                                       Row 2: crown glow (bioluminescent turquoise/amber resin lanterns & spore-moss tips)
                                       Row 3: trunk glow (glowing shelf fungi, hollow heart & root moss veins)
  assets/props/ancient_fir_growth.png  4 cols x 1 row of 192x224 (768x224), feet at (96, 216):
                                       0 = medium mossy stump, 1 = giant buttress stump, 2 = sapling, 3 = young ancient fir
  assets/props/moss_carpet.png         4 cols x 1 row of 160x108 (640x108): rich dark forest humus, creeping root veins,
                                       needle litter, fallen cones, velvety emerald/teal moss cushions & fern fronds
  assets/props/forest_shrine.png       3 cols x 2 rows of 64x72 (192x144), feet at (32, 64):
                                       Row 0 = dormant/unblessed, Row 1 = blessed/awakened (dressed ashlar masonry,
                                       mortar joints, chipped corners, hairline cracks, damp moss stains & root coils)
  assets/props/forest_shrine_glow.png  3 cols x 2 rows of 64x72 (192x144), unlit emissive pixels
  docs/img/ancient_fir_sheet.png       Visual QA contact sheet (daylight + night + shrines + growth strip)

Zero #000000 pixels anywhere; stdlib + gen_art.py only.
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, noise, write_png  # noqa: E402

DOC_IMG = ROOT.parent / "docs" / "img" / "ancient_fir_sheet.png"

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

OUT = hexc("14182c")
OUT_LEAF = hexc("122228")
OUT_SHRINE = hexc("1b1a2e")
SHADOW_RGB = (14, 16, 34)

# Deep spruce-emerald & blue-pine needles (6 rich cel bands)
FIR_PALS = [
    [hexc(c) for c in ("131e36", "18363c", "22524a", "337258", "4f966a", "7cc286")],
    [hexc(c) for c in ("121c34", "16333e", "1f4e4c", "2e6f5c", "49936e", "76c08a")],
    [hexc(c) for c in ("141f38", "1a393e", "26564c", "38765a", "54996c", "80c588")],
]
FIR_RIM = [hexc("226e7c"), hexc("4cc0c4")]
VOID_TIP = [hexc("4a2c8a"), hexc("7048d0"), hexc("b89cff")]
MOSS_BEARD = [hexc(c) for c in ("193a36", "26584a", "3c7e5c", "64b278", "96dc9a")]

# Ancient dark reddish-slate / plum-fir bark (6 steps) & heartwood
BARK = [hexc(c) for c in ("181022", "2a1c30", "432c42", "634458", "896474", "b49098")]
HEARTWOOD = [hexc(c) for c in ("462c2c", "6e483e", "9c6f56", "c89c78", "ead0aa")]
ROOT_MOSS = [hexc(c) for c in ("183632", "245244", "387654", "589e68", "82c882")]
LICHEN_CRUST = [hexc("5e8076"), hexc("92b8a8")]
SHELF_FUNGI = [hexc(c) for c in ("18424c", "2a787e", "5cc4bc", "a6f2e4")]
CONE = [hexc(c) for c in ("341c1e", "5c362c", "8c5c40", "b6845c")]

# Shrine dressed stone (8 steps like art_arena_pillars.py)
STONE = [hexc(c) for c in ("1c1a34", "282548", "3a365f", "4e4978", "665f94", "827ab0", "a69fd0", "d4cfee")]
MORTAR = hexc("17142b")
ANTLER = [hexc(c) for c in ("2e283e", "4e4662", "786f88", "a8a0b6", "dad4e2")]

# Emissive glow & dim base colors
TEAL_DIM = hexc("2a8c94")
TEAL = hexc("3cc0c6")
TEAL_L = hexc("78f4e6")
TEAL_HOT = hexc("d0fff8")

AMBER_DIM = hexc("6f5020")
AMBER_MID = hexc("b48a38")
AMBER = hexc("e6c468")
AMBER_HOT = hexc("fff0b0")

VIO_DIM = hexc("5c2fb8")
VIO = hexc("8a4dff")
VIO_L = hexc("d9c8ff")


def blank(w: int, h: int):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(px, x: int, y: int, col):
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        px[y][x] = col


def get_a(px, x: int, y: int) -> int:
    if 0 <= x < len(px[0]) and 0 <= y < len(px):
        return px[y][x][3]
    return 0


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


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
    return 0.56 * vnoise(x, y, s) + 0.30 * vnoise(x * 2.1, y * 2.1, s + 11) + 0.14 * vnoise(x * 4.3, y * 4.3, s + 23)


class GlowMap:
    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.px = blank(w, h)
        self.pts = []

    def emit(self, base, x: int, y: int, dim_col, bright_col, halo: int = 1):
        if 0 <= x < self.w and 0 <= y < self.h:
            if dim_col is not None and base is not None:
                base[y][x] = dim_col
            self.px[y][x] = bright_col
            if halo > 0:
                self.pts.append((x, y, bright_col, halo))

    def finish(self):
        out = [row[:] for row in self.px]
        for cx, cy, col, rad in self.pts:
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    if dx == 0 and dy == 0:
                        continue
                    xx, yy = cx + dx, cy + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h):
                        continue
                    d = math.hypot(dx, dy)
                    if d <= rad + 0.45 and out[yy][xx][3] < 255:
                        a = 104 if d <= 1.2 else (50 if d <= 1.95 else 24)
                        if a > out[yy][xx][3]:
                            out[yy][xx] = (col[0], col[1], col[2], a)
        return out


# ==============================================================================
# 1. Ancient Fir (`ancient_fir.png` 3x4 of 192x224 & `ancient_fir_growth.png` 4x1)
# ==============================================================================
TW, TH = 192, 224
FX, FY = 96, 216

FIR_SPECS = [
    dict(height=178, crown_hw=64, clear=26, trunk_hw=13.0, tiers=11, lean=2.8, pal=0, twin=False, hollow=True, fungi=6, lanterns=5, beards=18, veins=2),
    dict(height=196, crown_hw=72, clear=30, trunk_hw=15.0, tiers=12, lean=-3.4, pal=1, twin=False, hollow=True, fungi=8, lanterns=6, beards=22, veins=3),
    dict(height=210, crown_hw=80, clear=34, trunk_hw=17.0, tiers=13, lean=2.2, pal=2, twin=True, hollow=True, fungi=9, lanterns=8, beards=26, veins=3),
]

SAPLING_SPEC = dict(height=60, crown_hw=25, clear=9, trunk_hw=3.4, tiers=5, lean=1.4, pal=0, twin=False, hollow=False, fungi=0, lanterns=0, beards=3, veins=0)
YOUNG_SPEC = dict(height=116, crown_hw=46, clear=17, trunk_hw=7.6, tiers=8, lean=-2.0, pal=1, twin=False, hollow=False, fungi=2, lanterns=1, beards=7, veins=1)


def outline_tree_layers(trunk_px, crown_px, shadow_rx: float):
    t_out = [row[:] for row in trunk_px]
    c_out = [row[:] for row in crown_px]
    for y in range(FY - 5, TH):
        for x in range(TW):
            d = ((x + 0.5 - FX) / shadow_rx) ** 2 + ((y + 0.5 - (FY + 0.8)) / 4.8) ** 2
            if d < 1.0 and t_out[y][x][3] == 0 and c_out[y][x][3] == 0:
                t_out[y][x] = (*SHADOW_RGB, 118 if d < 0.48 else 64)

    for y in range(1, TH - 1):
        for x in range(1, TW - 1):
            if trunk_px[y][x][3] == 255 or crown_px[y][x][3] == 255:
                continue
            hit_c = any(crown_px[y + dy][x + dx][3] == 255 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            hit_t = any(trunk_px[y + dy][x + dx][3] == 255 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if hit_c:
                c_out[y][x] = OUT_LEAF
            elif hit_t:
                t_out[y][x] = OUT
    return t_out, c_out


def draw_branch_curve(px, pts, r0: float, r1: float, seed: int):
    n = max(1, len(pts) - 1)
    for i, (fx, fy) in enumerate(pts):
        t = i / float(n)
        rad = r0 + (r1 - r0) * t
        ir = int(math.ceil(rad + 0.4))
        cx, cy = int(round(fx)), int(round(fy))
        for dy in range(-ir, ir + 1):
            for dx in range(-ir, ir + 1):
                if dx * dx + dy * dy <= (rad + 0.2) ** 2:
                    lit = (-0.52 * dx - 0.76 * dy) / max(1.0, rad) + (hsh(cx + dx, cy + dy, seed) - 0.5) * 0.45
                    idx = 4 if lit > 0.55 else (3 if lit > 0.1 else (2 if lit > -0.35 else 1))
                    if dy >= ir and rad >= 1.2:
                        idx = 0
                    put(px, cx + dx, cy + dy, BARK[idx])


def sample_quad(p0, p1, p2, steps: int = 24):
    pts = []
    for i in range(steps + 1):
        t = i / float(steps)
        u = 1.0 - t
        pts.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return pts


def build_ancient_fir(spec: dict, seed: int, extras: bool = True):
    rng = random.Random(seed)
    pal = FIR_PALS[spec["pal"]]
    trunk = blank(TW, TH)
    crown = blank(TW, TH)
    glow_c = GlowMap(TW, TH)
    glow_t = GlowMap(TW, TH)

    height = spec["height"]
    crown_hw = spec["crown_hw"]
    clear = spec["clear"]
    trunk_hw = spec["trunk_hw"]
    tiers = spec["tiers"]
    lean = spec["lean"]

    top_y = max(4, FY - height)
    hem_y = FY - clear
    trunk_top = int(top_y + (hem_y - top_y) * 0.22)  # Trunk climbs high into crown interior!

    # ---- 1. Ancient Fluted Cathedral Trunk + Gnarled Buttress Roots (Row 0 & peeking through Row 1)
    centers = {}
    for y in range(trunk_top, FY + 1):
        u_up = (FY - y) / max(1.0, float(FY - trunk_top))
        cx = FX + lean * (u_up ** 1.18) + 2.2 * math.sin(u_up * 2.9 + seed)
        buttress = max(0.0, (y - (FY - 20)) / 20.0) ** 1.72 * (trunk_hw * 0.95)
        hw = trunk_hw * (1.0 - 0.58 * (u_up ** 1.1)) + buttress
        centers[y] = (cx, hw)

        # Below hem_y - 12 goes to trunk; above goes into crown so glimpses of dark wood show between bough tiers!
        dest = trunk if y >= hem_y - 12 else crown
        for dx in range(-int(hw) - 1, int(hw) + 2):
            if abs(dx) > hw:
                continue
            x = int(round(cx + dx))
            if not (4 <= x < TW - 4):
                continue
            rel = dx / max(1.0, hw)
            # Winding ancient bark plates + pixel-scale bark grain + horizontal growth scars
            plate_wave = math.sin(dx * 0.92 + 0.7 * math.sin(y * 0.13 + seed))
            grain = (fbm(x * 0.55, y * 0.24, seed + 3) - 0.5) * 1.15
            scar = -0.55 if (int(y + 1.5 * math.sin(dx * 0.5)) % 13 == 0 and abs(rel) < 0.7) else 0.0
            dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.62
            val = (0.54 - 0.52 * rel) * 4.8 + 0.55 * plate_wave + grain + scar + dith
            if plate_wave < -0.74 and (y + dx) % 4 != 0:
                val -= 1.25  # Deep vertical bark fissure
            if rel > 0.84:
                val = min(val, 0.8)
            col = BARK[int(clamp(val, 0, 5))]

            # Rich multi-tone moss creeping up the lower trunk flutes & buttresses
            if y > FY - 24 and rel < 0.48:
                m_score = ((y - (FY - 24)) / 24.0) * 1.15 - max(0.0, rel) * 0.7 + (fbm(x * 0.4, y * 0.4, seed + 11) - 0.45)
                if m_score > 0.42 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.35:
                    m_idx = int(clamp((0.6 - 0.5 * rel) * 4.2 + (hsh(x, y, seed + 13) - 0.5), 0, 4))
                    col = ROOT_MOSS[m_idx]
            put(dest, x, y, col)
            # Duplicate overlap band into trunk so trunk chopped/faded seam is seamless
            if hem_y - 20 <= y < hem_y - 12:
                put(trunk, x, y, col)

    # Multi-pronged gnarled buttress roots gripping the soil (`y = FY-14..FY+2`)
    root_defs = [
        (-1, 1.65, -9, 1, 4.4),
        (-1, 1.05, -5, 2, 3.4),
        (1, 1.58, -9, 1, 4.2),
        (1, 0.98, -5, 2, 3.2),
        (-0.35, 0.62, -6, 3, 3.0),
        (0.38, 0.58, -6, 3, 2.8),
    ]
    for side_f, reach_m, y_start_off, y_end_off, r0 in root_defs:
        sx0 = FX + side_f * trunk_hw * 0.58
        sy0 = FY + y_start_off
        sx2 = FX + (1 if side_f >= 0 else -1) * (abs(side_f) * trunk_hw * 0.5 + trunk_hw * reach_m + 5)
        sy2 = FY + y_end_off
        ctrl_x = (sx0 + sx2) * 0.5
        ctrl_y = min(sy0, sy2) - 2.2
        pts = sample_quad((sx0, sy0), (ctrl_x, ctrl_y), (sx2, sy2), steps=22)
        draw_branch_curve(trunk, pts, r0, 1.1, seed + int(abs(side_f) * 30))
        # Moss ridge along upper sunlit side of left/center buttress roots
        if side_f <= 0.4:
            for k_p, (rx_p, ry_p) in enumerate(pts[:15]):
                if k_p % 2 == 0 or side_f < 0:
                    put(trunk, int(round(rx_p)), int(round(ry_p - r0 * 0.55)), ROOT_MOSS[3 if side_f < 0 else 2])

    if extras:
        # Pale crust lichen patches on trunk
        for _ in range(10):
            ly = FY - rng.randrange(6, clear + 8)
            if ly in centers:
                cx_t, hw_t = centers[ly]
                lx = int(round(cx_t + rng.uniform(-hw_t * 0.72, hw_t * 0.15)))
                put(trunk, lx, ly, LICHEN_CRUST[1])
                put(trunk, lx + 1, ly, LICHEN_CRUST[0])

        # Hollow heart cavity on old cathedral trunk (`y ≈ FY - clear*0.52`) with warm amber/teal glow inside
        if spec["hollow"]:
            hy = FY - int(clear * 0.50)
            if hy in centers:
                cx_t, _ = centers[hy]
                hcx = int(round(cx_t - 1))
                for dy in range(-4, 5):
                    for dx in range(-3, 4):
                        d = (dx / 2.8) ** 2 + (dy / 4.2) ** 2
                        if d <= 1.1:
                            put(trunk, hcx + dx, hy + dy, BARK[0] if d < 0.68 else BARK[4 if dx < 0 else 2])
                glow_t.emit(trunk, hcx, hy, AMBER, AMBER_HOT, halo=2)
                glow_t.emit(trunk, hcx, hy + 1, TEAL, TEAL_L, halo=1)

        # Winding glowing root/bark veins (`Row 3` trunk glow)
        for v_i in range(spec["veins"]):
            vy0 = FY - int(clear * rng.uniform(0.12, 0.35))
            vx_off = rng.uniform(-0.45, 0.25) * trunk_hw
            for k in range(int(clear * 0.55)):
                yy = vy0 - k
                if yy not in centers:
                    break
                cx_t, hw_t = centers[yy]
                xx = int(round(cx_t + vx_off + 1.6 * math.sin(k * 0.42 + v_i * 2.1)))
                if abs(xx - cx_t) < hw_t - 1.2 and get_a(trunk, xx, yy) == 255:
                    if (k + v_i) % 3 == 0:
                        glow_t.emit(trunk, xx, yy, TEAL_DIM, TEAL, halo=1)
                    else:
                        glow_t.emit(trunk, xx, yy, VIO_DIM, VIO_L if k % 4 == 0 else VIO, halo=1)

        # Tiered bracket shelf fungi clusters on trunk sides
        for f_i in range(spec["fungi"]):
            fy = FY - int(5 + (clear + 6) * ((f_i * 0.29 + 0.11) % 0.92))
            if fy in centers:
                cx_t, hw_t = centers[fy]
                side = -1 if f_i % 2 == 0 else 1
                fx0 = int(round(cx_t + side * (hw_t * rng.uniform(0.55, 0.95))))
                fw = rng.randrange(4, 7)
                for dx in range(fw):
                    xx = fx0 + side * dx
                    put(trunk, xx, fy, SHELF_FUNGI[3 if dx < fw - 2 else 2])
                    put(trunk, xx, fy + 1, SHELF_FUNGI[1 if dx == 0 else 0])
                glow_t.emit(trunk, fx0 + side, fy, SHELF_FUNGI[2], TEAL_L, halo=1)

    # ---- 2. Sweeping Cathedral Conifer Crown (`Row 1`): Deep-Tiered Drooping Bough Skirts & Ragged Needle Fingers
    # Deep indigo-pine shadow core behind the bough tiers so inter-tier gaps read as primordial forest shadow
    step = (hem_y - top_y) / float(tiers)
    for y in range(int(top_y + 5), int(hem_y - step * 0.48)):
        u = (y - top_y) / max(1.0, float(hem_y - top_y))
        core_hw = crown_hw * (0.09 + 0.50 * (u ** 0.88))
        cx_c = FX + lean * (1.0 - u * 0.45)
        for dx in range(-int(core_hw) - 1, int(core_hw) + 2):
            if abs(dx) <= core_hw + (hsh(dx, y, seed + 5) - 0.5) * 2.5:
                put(crown, int(round(cx_c + dx)), y, pal[0 if noise(dx // 2, y // 2, seed + 6) < 175 else 1])

    # Build crooked cathedral bough tiers (`art_spruce.py` ragged drooping needle-skirt architecture scaled to 192x224
    # with multi-lobed sub-bough undulations, deep indigo-emerald under-skirts all the way across left-to-right,
    # and exposed crooked bark elbows!)
    bough_tips_for_extras = []
    for t_idx in range(tiers):
        grow = (t_idx + 1) / float(tiers)
        ti = top_y + step * t_idx * 0.94
        bi = ti + step * 1.38
        env = 0.14 + 0.86 * (grow ** 0.84)
        l_span = min(crown_hw + 2.0, crown_hw * env * (0.84 + 0.28 * rng.random()))
        r_span = min(crown_hw + 2.0, crown_hw * env * (0.84 + 0.28 * rng.random()))
        shift = lean * math.sin(t_idx * 0.82 + seed) * min(1.0, grow * 1.2) + rng.uniform(-1.4, 1.4)
        cx_tier = FX + shift

        # Crooked wooden bough arms underneath this tier so glimpses of dark wood peek out in deep shadow pockets
        if t_idx >= 2:
            for side, span in ((-1, l_span), (1, r_span)):
                b_pts = sample_quad(
                    (cx_tier, ti + 1.0),
                    (cx_tier + side * span * 0.52, ti + step * 0.35),
                    (cx_tier + side * span * 0.86, bi + step * 0.22),
                    steps=20,
                )
                draw_branch_curve(crown, b_pts, max(1.4, 3.2 * grow), 0.9, seed + t_idx * 11 + (0 if side < 0 else 5))
                bough_tips_for_extras.append((cx_tier + side * span * 0.62, bi, span * 0.32, step * 0.45, t_idx, side * 0.75))

        phase = rng.uniform(0.0, 11.0)
        period = 4.4 + rng.random() * 2.6
        sub_phase = rng.uniform(0.0, 6.28)
        lowest = (t_idx == tiers - 1)

        y_lo = max(3, int(ti))
        y_hi = min(TH - 7, int(bi + step * 0.85 + 12))
        max_s = int(max(l_span, r_span)) + 8
        for y in range(y_lo, y_hi):
            u = clamp((y - ti) / max(1.0, bi - ti), 0.0, 1.0)
            for dx in range(-max_s, max_s + 1):
                x = int(round(cx_tier)) + dx
                if not (4 <= x < TW - 4):
                    continue
                ext = l_span if dx < 0 else r_span
                rel_x = abs(dx) / max(1.0, ext)
                # Bell-shaped conifer tier width with subtle organic edge jitter
                hw = ext * (0.18 + 0.82 * (u ** 0.80)) + (noise(x, y, seed + 3 + t_idx) / 255.0 - 0.5) * 2.2
                # Multi-cushion arch + ragged drooping needle fingers along the entire skirt hem!
                slot = int((dx + phase) // period)
                local = ((dx + phase) % period) / period
                sub_arch = 2.6 * math.sin(dx * 0.19 + sub_phase) * (0.4 + 0.6 * rel_x)
                spike = (2.8 + 6.4 * (noise(slot, t_idx, seed + 7) / 255.0)) * (1.0 + 0.88 * (rel_x ** 1.28)) * (1.35 if lowest else 1.0)
                finger = spike * (max(0.0, 1.0 - abs(local - 0.5) * 2.0) ** 1.15)
                droop = (rel_x ** 1.68) * step * 0.72
                edge_y = bi - 1.2 + droop + sub_arch + finger
                if abs(dx) > hw or y > edge_y:
                    continue

                # Top-left directional light, restrained on left so pal[5] only hits true sunlit ridges/tips!
                light = 0.37 - 0.44 * (dx / max(1.0, hw)) + 0.22 * (1.0 - u)
                if u < 0.28 + 0.16 * (noise(x // 3, t_idx, seed + 31) / 255.0 - 0.5):
                    light += 0.27 if dx < ext * 0.22 else 0.10
                # Deep indigo-spruce shadow band along the lower skirt of EVERY tier (even on the sunlit left!)
                dist_hem = edge_y - y
                if dist_hem < 6.4:
                    light -= 0.68 if dist_hem < 3.4 else 0.38
                # Irregular central trunk-cleft & sub-bough pocket shadows (wavy, never a straight vertical bar!)
                cleft_center = 3.8 * math.sin(t_idx * 1.9 + y * 0.14 + seed)
                cleft_dist = abs(dx - cleft_center) / max(1.0, max(l_span, r_span) * 0.13)
                if cleft_dist < 1.0 and u > 0.32 + 0.14 * hsh(t_idx, y // 3, seed + 19):
                    light -= 0.28 * (1.0 - cleft_dist)
                if math.cos(dx * 0.19 + sub_phase) < -0.58 and u > 0.30:
                    light -= 0.24
                # Fine diagonal conifer needle-spray ribbing + 2px cluster grain (never flat blobs!)
                stripe = (abs(dx) * 0.92 + (y - ti) * 1.85 + t_idx * 3.0) % 6.2
                light += -0.25 if stripe < 1.15 else (0.18 if stripe < 2.25 else 0.0)
                light -= 0.06 * (t_idx / float(max(1, tiers)))
                light += (noise(x // 2, y // 2, seed + 5) / 255.0 - 0.5) * 0.34
                v = light * 5.25 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.62
                put(crown, x, y, pal[int(clamp(v, 0, 5))])

    # Sunlit upper-left needle contour, cool twilight teal right-rim bounce & occasional void-violet tips
    snap_c = [row[:] for row in crown]
    for y in range(3, TH - 6):
        for x in range(4, TW - 4):
            c = snap_c[y][x]
            if c[3] == 0 or c not in pal:
                continue
            k = pal.index(c)
            if snap_c[y - 1][x][3] == 0:
                crown[y][x] = pal[min(5, k + 2)]
            elif snap_c[y][x - 1][3] == 0 and k < 5:
                crown[y][x] = pal[k + 1]
            elif snap_c[y][x + 1][3] == 0 and 1 <= k <= 3 and hsh(x, y, seed + 53) > 0.34:
                crown[y][x] = FIR_RIM[1 if hsh(x, y, seed + 54) > 0.58 else 0]
            elif snap_c[y + 1][x][3] == 0 and k <= 1 and hsh(x, y, seed + 55) < 0.09:
                crown[y][x] = VOID_TIP[1]

    # Crooked weathered deadwood stubs poking out from deep bough pockets
    if extras:
        for st_i in range(5):
            px_c, py_c, prx, pry, t_i, u_p = bough_tips_for_extras[(st_i * 7 + 3) % len(bough_tips_for_extras)]
            if abs(u_p) < 0.45 or t_i < 2:
                continue
            side = -1 if u_p < 0 else 1
            sx0 = int(round(px_c + side * prx * 0.72))
            sy0 = int(round(py_c + pry * 0.25))
            for k in range(rng.randrange(5, 10)):
                xx = sx0 + side * k
                yy = sy0 + (k // 3) - (1 if k == 7 else 0)
                if 4 <= xx < TW - 4:
                    put(crown, xx, yy, BARK[4 if side < 0 and k < 4 else 3])
                    put(crown, xx, yy + 1, BARK[1])

    # Spire leader(s) at the top of the cathedral fir
    leaders = [(-1, 10, -2), (1, 7, 3)] if spec["twin"] else [(1 if lean >= 0 else -1, 10, 0)]
    for b_dir, l_len, x_off in leaders:
        lx = float(FX + lean + x_off)
        ly0 = int(top_y + 5)
        for k in range(l_len):
            yy = ly0 - k
            if yy < 3:
                break
            lx += b_dir * 0.16 * (k / float(l_len))
            put(crown, int(round(lx)), yy, BARK[4 if k % 2 == 0 else 2])
            if k in (2, 4, 6):
                put(crown, int(round(lx)) - b_dir, yy + 1, pal[4])
                put(crown, int(round(lx)) + b_dir, yy + 1, pal[2])

    if extras:
        # Hanging cones tucked under sunlit upper/mid pads
        for c_i in range(12):
            px_c, py_c, prx, pry, t_i, u_p = bough_tips_for_extras[(c_i * 5 + 2) % len(bough_tips_for_extras)]
            if t_i >= tiers - 1:
                continue
            cx_cone = int(round(px_c + rng.uniform(-prx * 0.45, prx * 0.45)))
            cy_cone = int(round(py_c + pry * 0.55))
            if 8 <= cx_cone < TW - 8 and 8 <= cy_cone < TH - 18 and get_a(crown, cx_cone, cy_cone - 1) == 255:
                put(crown, cx_cone, cy_cone, CONE[3 if u_p < 0 else 2])
                put(crown, cx_cone + 1, cy_cone + 1, CONE[1])
                put(crown, cx_cone, cy_cone + 1, CONE[2])
                put(crown, cx_cone, cy_cone + 2, CONE[0])

        # Swaying Usnea beard-moss tassels & glowing resin/spore-lantern drops (`Row 2` crown glow)
        hem_pts = [
            (x, y)
            for y in range(int(top_y + 26), int(hem_y + 18))
            for x in range(10, TW - 10)
            if crown[y][x][3] == 255 and crown[y + 1][x][3] == 0 and trunk[y + 1][x][3] == 0
        ]
        rng.shuffle(hem_pts)
        chosen = []
        for hx, hy in hem_pts:
            if len(chosen) >= spec["beards"]:
                break
            if any(abs(hx - ux) < 6 and abs(hy - uy) < 9 for ux, uy in chosen):
                continue
            chosen.append((hx, hy))
            b_len = rng.randrange(5, 12)
            for k in range(b_len):
                yy = hy + 1 + k
                if yy >= FY - 7:
                    break
                sway = 1 if (k > 3 and (hx + k) % 4 == 0) else 0
                tone = 4 if (hx < FX and k < 2) else (3 if k < b_len // 2 else (2 if k < b_len - 2 else 1))
                put(crown, hx + sway, yy, MOSS_BEARD[tone])
                if k in (1, 2) and b_len >= 7:
                    put(crown, hx - 1, yy, MOSS_BEARD[max(1, tone - 1)])

            tip_y = min(FY - 8, hy + b_len)
            idx_b = len(chosen) - 1
            if idx_b < spec["lanterns"]:
                # Glowing resin lantern drop or turquoise spore-lantern cluster!
                is_amber = (idx_b % 3 == 0)
                c_dim, c_hot = (AMBER, AMBER_HOT) if is_amber else (TEAL, TEAL_HOT)
                c_mid = AMBER_MID if is_amber else TEAL_DIM
                for dy_l in (-1, 0, 1):
                    for dx_l in (-1, 0, 1):
                        if abs(dx_l) + abs(dy_l) <= 1:
                            put(crown, hx + dx_l, tip_y + dy_l, c_mid)
                glow_c.emit(crown, hx, tip_y, c_dim, c_hot, halo=2)
                glow_c.emit(crown, hx, tip_y - 1, c_mid, AMBER if is_amber else TEAL_L, halo=1)
            elif idx_b < spec["lanterns"] + 6:
                glow_c.emit(crown, hx, tip_y, TEAL_DIM, TEAL_L, halo=1)

    t_fin, c_fin = outline_tree_layers(trunk, crown, shadow_rx=crown_hw * 0.72 + 8.0)
    return t_fin, c_fin, glow_c.finish(), glow_t.finish()


def build_ancient_stump(radius: float, giant: bool, seed: int):
    trunk = blank(TW, TH)
    crown = blank(TW, TH)
    h_stump = int(radius * (1.30 if giant else 1.18))
    top_y = FY - h_stump
    rx_top = radius * 1.06
    ry_top = max(4.0, radius * 0.40)

    # Fluted bark + sprawling mossy buttress roots
    for y in range(top_y, FY + 2):
        flare = max(0.0, (y - (FY - 13)) / 13.0) ** 1.65 * (radius * (0.95 if giant else 0.62))
        hw = radius + flare
        for dx in range(-int(hw) - 2, int(hw) + 3):
            if abs(dx) > hw:
                continue
            x = FX + dx
            rel = dx / max(1.0, hw)
            plate = math.sin(dx * 0.85 + 0.4 * math.sin(y * 0.2))
            grain = (fbm(x * 0.6, y * 0.35, seed) - 0.5) * 1.1
            val = (0.52 - 0.50 * rel) * 4.8 + 0.5 * plate + grain + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.6
            col = BARK[int(clamp(val, 0, 5))]
            if y > FY - 12 and (rel < 0.42 or (giant and abs(dx) % 6 < 2)):
                if fbm(x * 0.4, y * 0.4, seed + 9) > 0.44:
                    col = ROOT_MOSS[int(clamp((0.6 - 0.45 * rel) * 4.2, 1, 4))]
            put(trunk, x, y, col)

    # Splintered bark crown & detailed concentric heartwood growth rings + radial cracks
    for y in range(int(top_y - ry_top - 2), int(top_y + ry_top + 3)):
        for dx in range(-int(rx_top) - 2, int(rx_top) + 3):
            ang = math.atan2((y - top_y) / ry_top, dx / rx_top)
            warp = 1.0 + 0.06 * math.sin(ang * 5.0 + seed)
            d = ((dx / rx_top) ** 2 + ((y - top_y) / ry_top) ** 2) / (warp * warp)
            if d <= 1.16:
                if d > 0.90:
                    put(trunk, FX + dx, y, BARK[4 if dx < 0 and y < top_y else 1])
                else:
                    ring = math.sin(math.sqrt(d) * (10.0 + radius * 0.55)) > 0.15
                    radial_crack = abs(math.sin(ang * 2.0 + 0.7)) < 0.08 and d > 0.22
                    if radial_crack:
                        col = HEARTWOOD[0]
                    elif d < 0.10:
                        col = HEARTWOOD[1]
                    else:
                        lit_c = 2.5 - 0.5 * (dx / rx_top) - 0.4 * ((y - top_y) / ry_top) + (0.65 if ring else -0.45)
                        col = HEARTWOOD[int(clamp(lit_c, 0, 4))]
                    put(trunk, FX + dx, y, col)

    if giant:
        # Velvety moss cushion & tiered shelf fungi on the giant stump
        for dx in range(-int(rx_top * 0.88), -int(rx_top * 0.18)):
            put(trunk, FX + dx, int(top_y - ry_top + 1), ROOT_MOSS[4 if dx < -rx_top * 0.5 else 3])
            put(trunk, FX + dx, int(top_y - ry_top + 2), ROOT_MOSS[2])
        for fx, fy, fw in [(FX + int(radius * 0.65), FY - 8, 5), (FX - int(radius * 0.85), FY - 5, 4), (FX + int(radius * 0.35), FY - 4, 4)]:
            for k in range(fw):
                put(trunk, fx + k, fy, SHELF_FUNGI[3 if k < fw - 2 else 2])
                put(trunk, fx + k, fy + 1, SHELF_FUNGI[1 if k == 0 else 0])

    t_fin, _ = outline_tree_layers(trunk, crown, shadow_rx=radius * 1.65 + 8.0)
    return t_fin


# ==============================================================================
# 2. Moss Carpet (`moss_carpet.png` 4x1 of 160x108, matching `art_forestbed.py` richness)
# ==============================================================================
MC_W, MC_H = 160, 108
MC_RADII = [46, 54, 62, 70]
UR_HUMUS = [hexc(c) for c in ("1e1824", "2c2330", "3d313c", "52424a", "685558")]
UR_MOSS = [hexc(c) for c in ("142e30", "1d463f", "2b6652", "3f8a64", "62b47c", "8ed898")]
UR_TEAL_MOSS = [hexc(c) for c in ("14343c", "1f5054", "2f7672", "4da494", "7ed4bc")]
UR_NEEDLE = [hexc(c) for c in ("523c34", "705442", "927256", "b29270")]
UR_FERN = [hexc(c) for c in ("1a443a", "2c6a50", "4a9668", "76c486", "a8e6a8")]


def build_moss_carpet(idx: int, seed: int):
    rng = random.Random(seed)
    rx = MC_RADII[idx]
    ry = rx * 0.65
    cx, cy = MC_W / 2.0, MC_H / 2.0
    ph = [rng.uniform(0, math.tau) for _ in range(4)]
    px = blank(MC_W, MC_H)
    inside = {}

    # 1. Warped organic humus patch with multi-octave grain & ordered Bayer dithered edge
    for y in range(MC_H):
        for x in range(MC_W):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            ang = math.atan2(dy, dx)
            warp = 1.0 + 0.11 * math.sin(3 * ang + ph[0]) + 0.08 * math.sin(5 * ang + ph[1]) + 0.05 * math.sin(9 * ang + ph[2])
            d = math.hypot(dx, dy) / warp
            if d > 1.05:
                continue
            edge = (d - 0.56) / 0.44
            if edge > 0.0:
                keep = BAYER[y % 4][x % 4] / 16.0 * 0.65 + (noise(x, y, seed) / 255.0) * 0.35
                if keep < edge * 1.05:
                    continue
            tone = fbm(x * 0.35, y * 0.35, seed + 1) + (hsh(x, y, seed + 2) - 0.5) * 0.32 - 0.24 * max(0.0, edge)
            px[y][x] = UR_HUMUS[int(clamp(tone * 4.8, 0, 4))]
            inside[(x, y)] = edge

    # 2. Snaking dark surface rootlets radiating out from center
    for _ in range(3 + idx):
        a = rng.uniform(0, math.tau)
        rx_p, ry_p = cx + math.cos(a) * rx * 0.12, cy + math.sin(a) * ry * 0.12
        hd = a
        for k in range(int(rx * rng.uniform(0.45, 0.78))):
            hd += rng.uniform(-0.28, 0.28)
            rx_p += math.cos(hd)
            ry_p += math.sin(hd) * 0.64
            xi, yi = int(rx_p), int(ry_p)
            if (xi, yi) not in inside or inside[(xi, yi)] > 0.78:
                break
            px[yi][xi] = BARK[2]
            if k < rx * 0.35 and (xi, yi - 1) in inside:
                px[yi - 1][xi] = BARK[3]
            if (xi, yi + 1) in inside:
                px[yi + 1][xi] = BARK[0]

    # 3. Rich needle litter, fallen twigs & cones
    for _ in range(int(rx * 2.6)):
        a, r = rng.uniform(0, math.tau), math.sqrt(rng.random()) * 0.92
        x0, y0 = cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r
        ang = rng.choice((0.5, 0.95, 2.15, 2.65, 1.55)) + rng.uniform(-0.25, 0.25)
        for k in range(rng.randrange(2, 5)):
            xi, yi = int(x0 + math.cos(ang) * k), int(y0 + math.sin(ang) * k * 0.6)
            if (xi, yi) in inside and inside[(xi, yi)] < 0.84:
                px[yi][xi] = UR_NEEDLE[min(3, 1 + (k == 0) + (ang < 1.1))]

    # 4. Sculpted overlapping emerald & sea-teal moss cushions with Bayer micro-relief!
    n_cushions = 13 + idx * 4
    for c_i in range(n_cushions):
        a, r = rng.uniform(0, math.tau), (rng.random() ** 0.68) * 0.80
        mx = cx + math.cos(a) * rx * r
        my = cy + math.sin(a) * ry * r
        mr = rng.uniform(5.0, 11.5)
        pal = UR_TEAL_MOSS if c_i % 4 == 0 else UR_MOSS
        top_i = len(pal) - 1
        for y in range(int(my - mr), int(my + mr) + 1):
            for x in range(int(mx - mr * 1.38), int(mx + mr * 1.38) + 1):
                if (x, y) not in inside:
                    continue
                dd = math.hypot((x - mx) / 1.38, y - my) / mr + (fbm(x * 0.5, y * 0.5, seed + 20 + c_i) - 0.5) * 0.42
                if dd < 1.0:
                    lit = ((mx - x) * 0.38 + (my - y) * 0.68) / mr + 0.52 + (hsh(x, y, seed + 40) - 0.5) * 0.35
                    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
                    if dd > 0.78 and y > my:
                        col = pal[0]
                    else:
                        col = pal[int(clamp(lit * top_i + dith, 1, top_i))]
                    px[y][x] = col

    # 5. Fallen spruce cones, pale lichen dots & pinnate woodland fern rosettes
    for _ in range(3 + idx):
        a, r = rng.uniform(0, math.tau), math.sqrt(rng.random()) * 0.72
        x0, y0 = int(cx + math.cos(a) * rx * r), int(cy + math.sin(a) * ry * r)
        for dy_c, row_c in enumerate(((2, 3, 2), (0, 1, 1))):
            for dx_c, v_c in enumerate(row_c):
                if (x0 + dx_c, y0 + dy_c) in inside:
                    px[y0 + dy_c][x0 + dx_c] = CONE[v_c]

    for _ in range(int(rx / 5)):
        lx, ly = int(cx + rng.uniform(-rx, rx) * 0.78), int(cy + rng.uniform(-ry, ry) * 0.78)
        if (lx, ly) in inside and inside[(lx, ly)] < 0.65 and hsh(lx, ly, seed + 61) > 0.55:
            px[ly][lx] = LICHEN_CRUST[1]

    for _ in range(4 + idx):
        a, r = rng.uniform(0, math.tau), math.sqrt(rng.random()) * 0.65
        fx0, fy0 = int(cx + math.cos(a) * rx * r), int(cy + math.sin(a) * ry * r)
        if (fx0, fy0) not in inside or inside[(fx0, fy0)] > 0.58:
            continue
        n_fronds = rng.randrange(5, 7)
        for fr in range(n_fronds):
            fa = fr * (math.tau / n_fronds) + rng.uniform(-0.22, 0.22)
            flen = rng.randrange(5, 8)
            perp_x, perp_y = -math.sin(fa), math.cos(fa) * 0.68
            for k in range(flen):
                xx = int(round(fx0 + math.cos(fa) * k))
                yy = int(round(fy0 + math.sin(fa) * k * 0.68))
                if (xx, yy) in inside:
                    sun = math.sin(fa) < 0.1 and math.cos(fa) < 0.3
                    px[yy][xx] = UR_FERN[4 if (k >= flen - 2 and sun) else (3 if k > 1 else 1)]
                    if 1 <= k <= flen - 2:
                        for side_p in (-1, 1):
                            px_l = int(round(xx + perp_x * side_p))
                            py_l = int(round(yy + perp_y * side_p))
                            if (px_l, py_l) in inside:
                                px[py_l][px_l] = UR_FERN[3 if sun and side_p < 0 else 2]

    # Meadow grass edge blend at outer dithered rim
    for (x, y), edge in inside.items():
        if edge > 0.46 and hsh(x // 3, y // 3, seed + 81) > 0.55 and hsh(x, y, seed + 82) > 0.35:
            px[y][x] = ROOT_MOSS[2 if hsh(x, y, seed + 83) > 0.5 else 1]
    return px


# ==============================================================================
# 3. Forest Shrine (`forest_shrine.png` & `_glow.png`: 3x2 of 64x72, feet (32, 64))
#    Built with full `art_arena_pillars.py` dressed ashlar masonry, mortar, cracks & moss!
# ==============================================================================
SW, SH = 64, 72
SFX, SFY = 32, 64


def finish_shrine(body_px, rx_shadow: float = 22.5):
    out = blank(SW, SH)
    for y in range(SFY - 3, SH):
        for x in range(SW):
            d = ((x + 0.5 - SFX) / rx_shadow) ** 2 + ((y + 0.5 - (SFY + 1.0)) / 3.5) ** 2
            if d < 1.0:
                out[y][x] = (*SHADOW_RGB, 118 if d < 0.5 else 64)

    moss_cols = set(ROOT_MOSS + MOSS_BEARD)
    for y in range(1, SH - 1):
        for x in range(1, SW - 1):
            if body_px[y][x][3] == 255:
                continue
            nbs = [body_px[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if body_px[y + dy][x + dx][3] == 255]
            if nbs:
                out[y][x] = OUT_LEAF if nbs[0] in moss_cols and y < SFY - 4 else OUT_SHRINE
    for y in range(SH):
        for x in range(SW):
            if body_px[y][x][3] == 255:
                out[y][x] = body_px[y][x]
    return out


def shade_ashlar_stone(px, x0: int, y0: int, x1: int, y1: int, seed: int, course_h: int = 5, top_ledge: bool = True):
    """Dressed ancient masonry courses with staggered mortar joints, Bayer grain, pitting & sunlit lips."""
    for y in range(y0, y1 + 1):
        ry_in = y - y0
        course = ry_in // max(2, course_h)
        is_h_joint = (ry_in > 0 and ry_in % course_h == 0 and y < y1)
        stagger = (course * 5 + seed) % 7
        for x in range(x0, x1 + 1):
            u = (x - x0) / max(1.0, float(x1 - x0))
            is_v_joint = ((x - x0 + stagger) % 8 == 0) and (x0 + 1 < x < x1 - 1) and not (top_ledge and ry_in == 0)
            if is_h_joint or is_v_joint or y == y1:
                col = MORTAR if hsh(x, y, seed + 3) < 0.88 else STONE[1]
            else:
                grain = (fbm(x * 0.75, y * 0.65, seed) - 0.5) * 1.05
                dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.58
                val = 4.9 - u * 2.55 + grain + dith
                if top_ledge and ry_in == 0:
                    val += 1.55  # Sunlit ledge top
                elif ry_in % course_h == 1:
                    val += 0.55  # Catch-edge below mortar joint
                if u < 0.14:
                    val += 0.65
                if hsh(x // 2, y, seed + 17) > 0.94:
                    val -= 1.1  # Weathering pit
                col = STONE[int(clamp(val, 1, 7))]
            put(px, x, y, col)


def carve_crack(px, pts, seed: int):
    for i, (cx, cy) in enumerate(pts):
        if get_a(px, cx, cy) == 255:
            put(px, cx, cy, MORTAR)
            if get_a(px, cx + 1, cy) == 255 and px[cy][cx + 1] in STONE[1:6] and hsh(cx, cy, seed + i) > 0.35:
                k = STONE.index(px[cy][cx + 1])
                put(px, cx + 1, cy, STONE[min(7, k + 1)])


def apply_shrine_moss(px, zones, seed: int, blessed: bool):
    snap = [row[:] for row in px]
    for y in range(2, SH - 2):
        for x in range(2, SW - 2):
            if snap[y][x][3] != 255:
                continue
            w_p = 0.0
            for mx, my, mrx, mry in zones:
                d = ((x - mx) / mrx) ** 2 + ((y - my) / mry) ** 2
                if d < 1.0:
                    w_p = max(w_p, 1.28 - d * 0.75)
            if w_p <= 0.0:
                continue
            n = fbm(x * 0.38, y * 0.38, seed) * 0.8 + hsh(x, y, seed + 5) * 0.2
            thr = 0.55 + (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.42
            score = w_p * (0.56 + n)
            if score > thr:
                lit = 0.58 - 0.015 * (x - SFX) - 0.012 * (y - 30) + (hsh(x, y, seed + 9) - 0.5) * 0.5
                idx = int(clamp(lit * 4.2 + (BAYER[(y + 1) % 4][x % 4] / 16.0 - 0.5) * 0.65, 0, 4))
                if blessed and idx == 4 and (x + y) % 3 == 0:
                    put(px, x, y, MOSS_BEARD[4])
                else:
                    put(px, x, y, ROOT_MOSS[idx])
            elif score > thr - 0.16 and snap[y][x] in STONE[2:]:
                k = STONE.index(snap[y][x])
                put(px, x, y, STONE[max(1, k - 1)])


def build_forest_shrine(variant: int, blessed: bool):
    px = blank(SW, SH)
    glow = GlowMap(SW, SH)
    seed = 601 + variant * 29

    if variant == 0:
        # Variant 0: Peaked lantern-niche shrine with stepped ashlar plinth, carved cornice & embracing fir roots
        shade_ashlar_stone(px, 15, 59, 49, 64, seed + 1, course_h=3, top_ledge=True)
        shade_ashlar_stone(px, 18, 54, 46, 59, seed + 2, course_h=3, top_ledge=True)
        shade_ashlar_stone(px, 20, 32, 44, 54, seed + 3, course_h=6, top_ledge=False)

        # Carved overhanging gable roof with overlapping stone roof-slates (`y = 15..32`)
        for y in range(15, 33):
            t = (y - 15) / 17.0
            hw = 1.8 + t * 16.2
            x0, x1 = int(round(SFX - hw)), int(round(SFX + hw))
            slate_row = (y - 15) % 4 == 0 and y > 16
            for x in range(x0, x1 + 1):
                # Chipped right roof eave corner
                if y in (30, 31) and x >= x1 - 1:
                    continue
                u = (x - x0) / max(1.0, float(x1 - x0))
                grain = (fbm(x * 0.7, y * 0.7, seed + 7) - 0.5) * 0.9
                if y == 32 or slate_row:
                    col = MORTAR if u > 0.35 else STONE[2]
                else:
                    val = 5.8 - u * 3.1 + grain + (1.0 if x <= x0 + 2 else 0.0)
                    col = STONE[int(clamp(val, 1, 7))]
                put(px, x, y, col)

        # Recessed arched lantern niche (`x = 26..38, y = 36..50`) with molded stone arch surround
        for y in range(35, 51):
            for x in range(25, 40):
                dx, dy = x - 32.0, y - 41.0
                d_arch = (dx / 6.2) ** 2 + (dy / 5.5) ** 2 if y < 41 else (abs(dx) / 6.2) ** 2
                d_inner = (dx / 4.8) ** 2 + (dy / 4.2) ** 2 if y < 41 else (abs(dx) / 4.8) ** 2
                if d_inner <= 1.0 and y <= 49:
                    put(px, x, y, MORTAR if y < 48 else STONE[1])
                elif d_arch <= 1.05 and y <= 50:
                    put(px, x, y, STONE[5 if (dx < 0 and y < 44) else (3 if dx < 3 else 1)])

        carve_crack(px, [(39, 34), (39, 35), (40, 36), (40, 37), (41, 38), (41, 39)], seed + 11)
        draw_branch_curve(px, sample_quad((20, 33), (16, 48), (10, 63), 24), 2.2, 1.0, seed + 13)
        draw_branch_curve(px, sample_quad((44, 39), (48, 52), (54, 63), 22), 2.0, 1.0, seed + 15)
        draw_branch_curve(px, sample_quad((24, 53), (29, 58), (27, 64), 14), 1.6, 0.9, seed + 17)
        apply_shrine_moss(px, [(26, 22, 7.5, 4.2), (39, 28, 5.8, 3.2), (18, 58, 5.2, 2.8), (45, 58, 4.5, 2.4)], seed + 19, blessed)

        # Tiny shelf fungi on right root & fallen stone chunk at left foot
        put(px, 47, 50, SHELF_FUNGI[3])
        put(px, 48, 50, SHELF_FUNGI[2])
        put(px, 47, 51, SHELF_FUNGI[0])

        if blessed:
            for dx, dy, gc in [(0, 0, AMBER_HOT), (0, -1, AMBER_HOT), (-1, 0, AMBER), (1, 0, AMBER), (0, -2, TEAL_HOT), (-1, -1, TEAL_L), (1, -1, TEAL_L), (0, -3, TEAL_L), (0, 1, AMBER_MID)]:
                glow.emit(px, 32 + dx, 46 + dy, gc, gc, halo=2 if dy in (0, -1) and dx == 0 else 1)
            for gx, gy in [(24, 21), (40, 27), (17, 57), (47, 50), (32, 19)]:
                glow.emit(px, gx, gy, TEAL_DIM, TEAL_L, halo=1)

    elif variant == 1:
        # Variant 1: Twin-antler carved monolith stele with dressed plinth, knotwork band & stone offering basin
        shade_ashlar_stone(px, 16, 58, 48, 64, seed + 1, course_h=3, top_ledge=True)

        # Tapered monolith stele (`y = 17..58`) with chipped top-right crown & carved horizontal frieze at y=42..44
        for y in range(17, 59):
            t = (y - 17) / 41.0
            hw = 6.8 + 3.8 * t
            if y < 21:
                hw *= 0.62 + 0.38 * ((y - 17) / 4.0)
            x0, x1 = int(round(SFX - hw)), int(round(SFX + hw))
            for x in range(x0, x1 + 1):
                if y < 21 and x > SFX + 2 + (y - 17):
                    continue  # Weathered chipped upper-right corner!
                u = (x - x0) / max(1.0, float(x1 - x0))
                grain = (fbm(x * 0.7, y * 0.55, seed + 5) - 0.5) * 1.05
                dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
                if y in (42, 44):
                    col = MORTAR if u > 0.3 else STONE[2]
                elif y == 43:
                    col = STONE[5 if (x % 2 == 0 and u < 0.65) else 2]  # Carved bead molding
                else:
                    val = 5.2 - u * 2.7 + grain + dith + (1.1 if y == 17 else 0.0)
                    col = STONE[int(clamp(val, 1, 7))]
                put(px, x, y, col)

        # Sculpted bone/stone stag antlers with shaded cylindrical tines
        for side in (-1, 1):
            pts_main = sample_quad((SFX + side * 6, 30), (SFX + side * 16, 25), (SFX + side * 19, 12), 26)
            for i, (ax, ay) in enumerate(pts_main):
                ix, iy = int(round(ax)), int(round(ay))
                put(px, ix, iy, ANTLER[4 if (side < 0 or i > 16) else 3])
                put(px, ix, iy + 1, ANTLER[2 if side < 0 else 1])
            for tx0, ty0, tx1, ty1 in [(SFX + side * 11, 26, SFX + side * 10, 18), (SFX + side * 15, 22, SFX + side * 14, 14), (SFX + side * 17, 18, SFX + side * 20, 15)]:
                for k in range(8):
                    u = k / 7.0
                    put(px, int(round(tx0 + (tx1 - tx0) * u)), int(round(ty0 + (ty1 - ty0) * u)), ANTLER[4 if k > 4 else 2])

        # Deep incised elder-tree rune on stele face (`y = 24..39`)
        rune_pts = [(32, y) for y in range(24, 40)] + [(30, 27), (31, 28), (34, 27), (33, 28), (29, 32), (30, 33), (35, 32), (34, 33), (30, 36), (34, 36)]
        for rx, ry in rune_pts:
            put(px, rx, ry, MORTAR)
            if get_a(px, rx + 1, ry) == 255 and (rx + 1, ry) not in rune_pts:
                put(px, rx + 1, ry, STONE[5])

        # Fluted stone offering basin at base (`x = 22..42, y = 48..58`)
        for y in range(48, 59):
            hw = 10.0 if y <= 51 else (8.0 if y <= 54 else 6.2)
            for x in range(int(SFX - hw), int(SFX + hw) + 1):
                u = (x - (SFX - hw)) / max(1.0, 2.0 * hw)
                if y in (48, 49) and abs(x - SFX) <= 7:
                    put(px, x, y, MORTAR)
                elif y == 52:
                    put(px, x, y, MORTAR)
                else:
                    flute = 0.45 * math.sin((x - SFX) * 1.2) if y <= 51 else 0.0
                    put(px, x, y, STONE[int(clamp(5.2 - u * 2.6 + flute, 1, 6))])

        carve_crack(px, [(27, 21), (27, 22), (28, 23), (28, 24), (28, 25)], seed + 21)
        draw_branch_curve(px, sample_quad((23, 45), (17, 54), (11, 63), 20), 2.0, 1.0, seed + 23)
        draw_branch_curve(px, sample_quad((41, 45), (47, 54), (53, 63), 20), 2.0, 1.0, seed + 25)
        apply_shrine_moss(px, [(29, 19, 5.0, 2.8), (19, 57, 5.2, 2.5), (45, 57, 4.8, 2.5), (25, 48, 3.2, 1.8)], seed + 27, blessed)

        if blessed:
            for rx, ry in rune_pts:
                glow.emit(px, rx, ry, TEAL, TEAL_HOT if rx == 32 and 29 <= ry <= 34 else TEAL_L, halo=1)
            for bx in range(25, 40):
                glow.emit(px, bx, 49, TEAL_L, TEAL_HOT if 30 <= bx <= 34 else TEAL_L, halo=1)
            for dx, dy, gc in [(0, -1, AMBER_HOT), (-1, -1, AMBER), (1, -1, AMBER), (0, -2, AMBER_HOT), (0, -3, TEAL_L)]:
                glow.emit(px, 32 + dx, 48 + dy, gc, gc, halo=2 if dx == 0 and dy == -1 else 1)

    else:
        # Variant 2: Hollow radial-voussoir stone arch shrine with hanging spirit-moss & carved altar
        shade_ashlar_stone(px, 13, 58, 51, 64, seed + 1, course_h=3, top_ledge=True)

        # Radial voussoir arch (`y = 17..58`)
        for y in range(17, 59):
            for x in range(14, 51):
                dx, dy = x - 32.0, y - 40.0
                if y < 40:
                    d_out = (dx / 17.0) ** 2 + (dy / 22.8) ** 2
                    d_in = (dx / 8.5) ** 2 + (dy / 14.2) ** 2
                    if d_out > 1.0 or d_in < 1.0:
                        continue
                    ang = math.atan2(dy, dx)
                    # Radial voussoir mortar joints every ~26 deg!
                    v_joint = abs(((ang + math.pi) / 0.44) % 1.0 - 0.5) < 0.065
                    ring_joint = 0.46 < d_out < 0.53 and hsh(x, y, seed + 4) < 0.85
                    joint = v_joint or ring_joint
                else:
                    if abs(dx) > 16.5 or abs(dx) < 8.5:
                        continue
                    joint = (y in (45, 51, 57)) or (y % 12 < 6 and abs(int(dx)) == 12)

                if joint:
                    col = MORTAR
                else:
                    u = (x - 14.0) / 36.0
                    grain = (fbm(x * 0.7, y * 0.65, seed + 9) - 0.5) * 1.05
                    dith = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 0.55
                    val = 5.4 - u * 2.8 - max(0.0, (y - 36) / 22.0) * 0.8 + grain + dith
                    if y < 22 and dx < 2:
                        val += 1.0
                    col = STONE[int(clamp(val, 1, 7))]
                put(px, x, y, col)

        # Dressed stone altar inside arch (`x = 26..38, y = 50..58`)
        shade_ashlar_stone(px, 26, 50, 38, 58, seed + 12, course_h=4, top_ledge=True)
        carve_crack(px, [(18, 35), (19, 36), (19, 37), (20, 38), (20, 39), (44, 46), (45, 47), (45, 48)], seed + 14)

        draw_branch_curve(px, sample_quad((15, 36), (12, 50), (9, 63), 22), 2.1, 1.0, seed + 16)
        draw_branch_curve(px, sample_quad((49, 40), (52, 52), (55, 63), 20), 2.0, 1.0, seed + 18)
        apply_shrine_moss(px, [(27, 19, 8.5, 4.0), (39, 22, 6.8, 3.4), (17, 57, 5.0, 2.5), (47, 57, 4.8, 2.4)], seed + 21, blessed)

        # Hanging spirit-moss curtains inside upper arch soffit
        for hx, hlen in [(26, 6), (28, 4), (30, 8), (32, 5), (35, 7), (37, 5)]:
            hy0 = 26 if abs(hx - 32) <= 3 else 29
            for k in range(hlen):
                put(px, hx, hy0 + k, MOSS_BEARD[4 if k < 2 else (3 if k < hlen - 2 else 1)])

        if blessed:
            for dx, dy, gc in [(0, 0, AMBER_HOT), (0, -1, AMBER_HOT), (-1, 0, AMBER), (1, 0, AMBER), (0, 1, AMBER_MID), (-2, 0, TEAL_L), (2, 0, TEAL_L), (0, -2, TEAL_HOT), (0, 2, TEAL)]:
                glow.emit(px, 32 + dx, 45 + dy, gc, gc, halo=2 if dx == 0 and dy == 0 else 1)
            for gx, gy in [(26, 34), (30, 33), (35, 35), (25, 18), (40, 21), (32, 52)]:
                glow.emit(px, gx, gy, TEAL_DIM, TEAL_L, halo=1)

    return finish_shrine(px), glow.finish()


# ==============================================================================
# Verification & QA Sheet (`docs/img/ancient_fir_sheet.png`)
# ==============================================================================
def verify_no_black(name: str, px):
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if c[3] > 0 and c[0] == 0 and c[1] == 0 and c[2] == 0:
                raise AssertionError(f"{name} has forbidden pure #000000 pixel at ({x}, {y})")


def alpha_over(dst, src, ox: int, oy: int):
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
            sc = src[y][x]
            sa = sc[3]
            if sa == 0:
                continue
            if sa == 255:
                dst[dy][dx] = sc
            else:
                dc = dst[dy][dx]
                inv = 255 - sa
                dst[dy][dx] = (
                    (sc[0] * sa + dc[0] * inv) // 255,
                    (sc[1] * sa + dc[1] * inv) // 255,
                    (sc[2] * sa + dc[2] * inv) // 255,
                    255,
                )


def add_glow_over(dst, glow, ox: int, oy: int):
    gh, gw = len(glow), len(glow[0])
    dh, dw = len(dst), len(dst[0])
    for y in range(gh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(gw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            gc = glow[y][x]
            ga = gc[3]
            if ga == 0:
                continue
            dc = dst[dy][dx]
            f = ga / 255.0
            dst[dy][dx] = (
                min(255, int(dc[0] * (1.0 - 0.55 * f) + gc[0] * f * 1.28)),
                min(255, int(dc[1] * (1.0 - 0.55 * f) + gc[1] * f * 1.28)),
                min(255, int(dc[2] * (1.0 - 0.55 * f) + gc[2] * f * 1.28)),
                255,
            )


def tint_night_px(src):
    out = blank(len(src[0]), len(src))
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                out[y][x] = (max(4, int(c[0] * 0.44)), max(6, int(c[1] * 0.48)), max(12, int(c[2] * 0.66)), c[3])
    return out


def render_qa_sheet(firs, growths, carpets, shrines):
    cw, ch = 640, 540
    canvas = blank(cw, ch)
    for y in range(ch):
        night = y >= 270
        for x in range(cw):
            n = noise(x // 4, y // 3, 71)
            if not night:
                canvas[y][x] = (47, 98, 78, 255) if n < 85 else ((62, 125, 86, 255) if n < 185 else (52, 110, 82, 255))
            else:
                canvas[y][x] = (18, 26, 46, 255) if n < 90 else ((23, 33, 56, 255) if n < 190 else (27, 40, 64, 255))

    for i in range(3):
        tx = 6 + i * 186
        alpha_over(canvas, carpets[i], tx + 16, 150)
        t, c, _gc, _gt = firs[i]
        alpha_over(canvas, t, tx, 20)
        alpha_over(canvas, c, tx, 20)

    for i in range(3):
        s_px, _ = shrines[0][i]
        alpha_over(canvas, s_px, 568, 12 + i * 84)

    for i in range(3):
        tx = 6 + i * 186
        alpha_over(canvas, tint_night_px(carpets[(i + 1) % 4]), tx + 16, 420)
        t, c, gc, gt = firs[i]
        alpha_over(canvas, tint_night_px(t), tx, 290)
        add_glow_over(canvas, gt, tx, 290)
        alpha_over(canvas, tint_night_px(c), tx, 290)
        add_glow_over(canvas, gc, tx, 290)

    for i in range(3):
        s_px, s_gl = shrines[1][i]
        alpha_over(canvas, tint_night_px(s_px), 568, 282 + i * 84)
        add_glow_over(canvas, s_gl, 568, 282 + i * 84)

    DOC_IMG.parent.mkdir(parents=True, exist_ok=True)
    write_png(DOC_IMG, cw, ch, canvas)


def main():
    props = ROOT / "props"

    firs = [build_ancient_fir(spec, 101 + i * 17, extras=True) for i, spec in enumerate(FIR_SPECS)]
    fir_sheet = blank(TW * 3, TH * 4)
    for col, (t, c, gc, gt) in enumerate(firs):
        for r_idx, layer in enumerate((t, c, gc, gt)):
            verify_no_black(f"ancient_fir_c{col}_r{r_idx}", layer)
            for y in range(TH):
                fir_sheet[r_idx * TH + y][col * TW:(col + 1) * TW] = layer[y]
    write_png(props / "ancient_fir.png", TW * 3, TH * 4, fir_sheet)

    stump_med = build_ancient_stump(11.5, giant=False, seed=201)
    stump_giant = build_ancient_stump(16.5, giant=True, seed=202)
    sap_t, sap_c, _, _ = build_ancient_fir(SAPLING_SPEC, 203, extras=False)
    yng_t, yng_c, _, _ = build_ancient_fir(YOUNG_SPEC, 204, extras=False)
    sap_merged = [[sap_c[y][x] if sap_c[y][x][3] else sap_t[y][x] for x in range(TW)] for y in range(TH)]
    yng_merged = [[yng_c[y][x] if yng_c[y][x][3] else yng_t[y][x] for x in range(TW)] for y in range(TH)]
    growth_frames = [stump_med, stump_giant, sap_merged, yng_merged]
    growth_sheet = blank(TW * 4, TH)
    for col, g_fr in enumerate(growth_frames):
        verify_no_black(f"ancient_fir_growth_{col}", g_fr)
        for y in range(TH):
            growth_sheet[y][col * TW:(col + 1) * TW] = g_fr[y]
    write_png(props / "ancient_fir_growth.png", TW * 4, TH, growth_sheet)

    carpets = [build_moss_carpet(i, 301 + i * 19) for i in range(4)]
    carpet_sheet = blank(MC_W * 4, MC_H)
    for col, cp in enumerate(carpets):
        verify_no_black(f"moss_carpet_{col}", cp)
        for y in range(MC_H):
            carpet_sheet[y][col * MC_W:(col + 1) * MC_W] = cp[y]
    write_png(props / "moss_carpet.png", MC_W * 4, MC_H, carpet_sheet)

    shrine_rows = [
        [build_forest_shrine(v, blessed=False) for v in range(3)],
        [build_forest_shrine(v, blessed=True) for v in range(3)],
    ]
    shrine_sheet = blank(SW * 3, SH * 2)
    shrine_glow_sheet = blank(SW * 3, SH * 2)
    for r_idx in range(2):
        for col in range(3):
            s_px, s_gl = shrine_rows[r_idx][col]
            verify_no_black(f"forest_shrine_r{r_idx}_c{col}", s_px)
            verify_no_black(f"forest_shrine_glow_r{r_idx}_c{col}", s_gl)
            for y in range(SH):
                shrine_sheet[r_idx * SH + y][col * SW:(col + 1) * SW] = s_px[y]
                shrine_glow_sheet[r_idx * SH + y][col * SW:(col + 1) * SW] = s_gl[y]
    write_png(props / "forest_shrine.png", SW * 3, SH * 2, shrine_sheet)
    write_png(props / "forest_shrine_glow.png", SW * 3, SH * 2, shrine_glow_sheet)

    render_qa_sheet(firs, growth_frames, carpets, shrine_rows)
    print("Regenerated high-detail ancient_fir.png, ancient_fir_growth.png, moss_carpet.png, forest_shrine.png, forest_shrine_glow.png, and docs/img/ancient_fir_sheet.png")


if __name__ == "__main__":
    main()
