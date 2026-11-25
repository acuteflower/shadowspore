#!/usr/bin/env python3
"""Handcrafted pixel-art botanical atlases for LivingGrass v4.

Outputs:
  assets/tiles/living_grass.png             8x5 grid (160x120) of 40 standard 20x24 px variants (feet at y=22)
  assets/tiles/living_grass_glow.png        Matching unlit subtle night dew-glints & twilight blossom hearts
  assets/tiles/living_grass_tall.png        8x3 grid (192x108) of 24 tall-species 24x36 px variants (feet at y=34)
  assets/tiles/living_grass_tall_glow.png   Matching unlit night dew-pearls, silver plumes & blossom shimmer
  docs/img/living_grass_atlas_4x.png        4x nearest inspection sheet (day + night) for standard 40 variants
  docs/img/living_grass_tall_atlas_4x.png   4x nearest inspection sheet (day + night) for tall 24 variants

Standard 20x24 Atlas (40 variants, rows 0..4):
  Row 0 ( 0.. 7): Fine meadow fescue, wind-combed turf, twin horsts, dew-bent grass & baby shoots
  Row 1 ( 8..15): Arching meadow sedges, broadleaf plantain, golden rye, olive grass, moss cushions & clover
  Row 2 (16..23): 8 wildflower species: chamomile, daisy, buttercup, forget-me-not, clover-rose, harebell, yarrow, dandelion
  Row 3 (24..31): Woodland undergrowth: lady-fern, bracken, fiddleheads, bilberry, fallen-leaf sedge, stone thyme, pin-shrooms, hart's-tongue
  Row 4 (32..39): Seed plumes & biomes: wild oats, foxtail, quaking grass, brook sedge, water-mint rush, red sorrel, strandhafer, sheep's fescue

Tall 24x36 Atlas (24 variants, rows 0..2, 21..33 px tall — knee to hip height vs 42 px Ellie!):
  Row 0 ( 0.. 7): Tall wild meadow grass fountain, wind waves, dense thickets, fescue plumes, wild oats, silver feather-grass, wild brome
  Row 1 ( 8..15): Tall flowering wildmeadow: meadowsweet, oxeye daisies, wild sage/lupine, knapweed, goldenrod, cow-parsley, red sorrel, dew-pearl moon-grass
  Row 2 (16..23): Biome tall species: brook reed, cattails (Rohrkolben), plumed common reed, yellow flag iris, woodland eagle-fern, horsetail/sedge, tall Strandhafer, steppe feather-grass
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

# Atlas layout contracts (shared with src/world/living_grass.gd & living_grass.gdshader)
STD_W, STD_H = 20, 24
STD_COLS, STD_ROWS = 8, 5
STD_COUNT = STD_COLS * STD_ROWS  # 40
STD_FOOT_Y = 22

TALL_W, TALL_H = 24, 36
TALL_COLS, TALL_ROWS = 8, 3
TALL_COUNT = TALL_COLS * TALL_ROWS  # 24
TALL_FOOT_Y = 34

# ---------------- HARMONIZED SHADOWSPORE BOTANICAL PALETTES ----------------
# Core woodland-meadow grass (cool-teal roots -> velvety emerald -> sunlit yellow-green tips)
G0 = hexc("193633")  # deep cool-teal interior shadow
G1 = hexc("234b3f")  # rich shadowed woodland green
G2 = hexc("30664b")  # mid-dark lush blade base
G3 = hexc("438356")  # core meadow emerald
G4 = hexc("5ea05e")  # sunlit green blade body
G5 = hexc("84c06c")  # bright sunlit upper arch
G6 = hexc("b2de8d")  # crisp top-left catchlight tip

# Cool shade / woodland moss & fern tones
M0 = hexc("162f33")
M1 = hexc("204442")
M2 = hexc("2d6152")
M3 = hexc("427e5e")
M4 = hexc("63a36e")
M5 = hexc("8ac385")

# Warm olive-straw / aged basal blades & upland dry fescue (breaks uniform plastic green!)
O0 = hexc("344332")
O1 = hexc("4f5d3e")
O2 = hexc("737d4d")
O3 = hexc("9b9d63")
O4 = hexc("c7c282")

# Riparian moist teal-emerald reeds & sedges
R0 = hexc("163739")
R1 = hexc("21514d")
R2 = hexc("2f7162")
R3 = hexc("449173")
R4 = hexc("68b288")
R5 = hexc("95d09e")

# Coastal Strandhafer / marram grass (native sea-sage to sun-bleached wheat-straw)
D0 = hexc("525d45")
D1 = hexc("727b58")
D2 = hexc("98996c")
D3 = hexc("c0ba86")
D4 = hexc("e4dcab")

# Seed plumes & silver feather-grass
SEED_D = hexc("8a8754")
SEED_M = hexc("bab475")
SEED_L = hexc("e4dc9e")
SILV_D = hexc("8f9486")
SILV_M = hexc("c2c4b4")
SILV_L = hexc("ece9d8")

# Cattail velvet-brown spikes & russet sorrel / autumn oak leaves
CAT_D = hexc("3e261f")
CAT_M = hexc("653f2d")
CAT_L = hexc("8d5c3f")
CAT_HI = hexc("b8865e")

SOR_D = hexc("5c3235")
SOR_M = hexc("8b4a46")
SOR_L = hexc("ba6d5f")

LEAF_D = hexc("66422c")
LEAF_M = hexc("94603c")
LEAF_L = hexc("bf8652")

# Wildflower palettes (natural muted European meadow harmony)
WHITE_D = hexc("9fa0b4")
WHITE_M = hexc("ddd8cc")
WHITE_L = hexc("faf6ea")
CREAM_D = hexc("aea98e")
CREAM_M = hexc("dcd6b8")
CREAM_L = hexc("f5f0da")

GOLD_D = hexc("b6822c")
GOLD_C = hexc("e4b848")
GOLD_L = hexc("ffea8a")

BLUE_D = hexc("5575a8")
BLUE_M = hexc("8ab5e4")
BLUE_L = hexc("d0ebff")

ROSE_D = hexc("824a68")
ROSE_M = hexc("ba7698")
ROSE_L = hexc("e8b6cc")

LILAC_D = hexc("66549c")
LILAC_M = hexc("9d88d6")
LILAC_L = hexc("dcd0fa")

# Unlit night dew / whisper-delicate twilight blossom shimmer
DEW_DIM = (146, 228, 220, 88)
DEW_HI = (188, 246, 238, 132)
PEARL_G = (130, 242, 230, 152)
BLOOM_G = (186, 224, 255, 130)
GOLD_G = (242, 224, 150, 118)
LILAC_G = (204, 178, 252, 134)
ROSE_G = (238, 186, 214, 122)

# Standard blade ramps
BACK_RAMP = [G0, G1, G2, G3]
MID_RAMP = [G1, G2, G3, G4]
LIT_RAMP = [G1, G2, G3, G4, G5]
SUN_RAMP = [G2, G3, G4, G5, G6]
MOSS_RAMP = [M0, M1, M2, M3, M4]
MOSS_LIT = [M1, M2, M3, M4, M5]
OLIVE_RAMP = [O0, O1, O2, O3, O4]
REED_DARK = [R0, R1, R2, R3]
REED_RAMP = [R1, R2, R3, R4, R5]
DUNE_DARK = [D0, D1, D2, D3]
DUNE_RAMP = [D1, D2, D3, D4]


class Canvas:
    def __init__(self, w: int, h: int, foot_y: int) -> None:
        self.w = w
        self.h = h
        self.foot_y = foot_y
        self.px = [[CLEAR] * w for _ in range(h)]
        self.glow = [[CLEAR] * w for _ in range(h)]

    def put(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def put_blend(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        """Soft alpha-blend onto canvas (great for translucent root shadows without overwriting solid stems)."""
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        dst = self.px[y][x]
        if dst[3] == 0:
            self.px[y][x] = c
            return
        if dst[3] >= 250:
            return
        sa = c[3] / 255.0
        da = dst[3] / 255.0
        oa = sa + da * (1.0 - sa)
        if oa <= 0.001:
            return
        self.px[y][x] = (
            int((c[0] * sa + dst[0] * da * (1.0 - sa)) / oa),
            int((c[1] * sa + dst[1] * da * (1.0 - sa)) / oa),
            int((c[2] * sa + dst[2] * da * (1.0 - sa)) / oa),
            int(min(255, oa * 255)),
        )

    def gput(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.glow[y][x] = c

    def root_tuck(self, x0: int, x1: int, strength: float = 1.0) -> None:
        """Organic rounded-footprint root contact shadow (staggered 3/4 oval, zero flat horizontal cut!)."""
        mid = (x0 + x1) * 0.5
        half = max(1.8, (x1 - x0) * 0.5)
        for x in range(max(1, x0), min(self.w - 1, x1 + 1)):
            edge = abs(x - mid) / half
            if edge < 0.48:
                self.put_blend(x, self.foot_y + 1, (16, 36, 38, int(54 * strength)))
            if edge < 0.78:
                a = int((118 if edge < 0.42 else 66) * strength)
                self.put_blend(x, self.foot_y, (22, 46, 44, a))
            if edge < 0.62 and strength > 0.95:
                self.put_blend(x, self.foot_y - 1, (18, 40, 38, int(52 * strength)))

    def blade(
        self,
        rx: float,
        height: int,
        curve: float,
        ramp: list[tuple[int, int, int, int]],
        base_w: int = 1,
        droop: float = 0.0,
        curve_pow: float = 1.55,
        dew: bool = False,
        dew_col: tuple[int, int, int, int] = DEW_DIM,
        root_y_off: int = 0,
    ) -> tuple[int, int]:
        """Draws an organically arched, directionally top-left-lit tapered pixel-art grass ribbon.

        - `base_w`: 1 (slender), 2 (lush mid-blade), or 3 (broad tall sedge/reed leaf)
        - `droop`: > 0 causes the upper tip to curl gracefully downward like real overhanging wild grass!
        - Top-left sun normal shading: left edge of thick blades gets lit tone, right edge gets cool shadow.
        """
        fy = self.foot_y + root_y_off
        n_steps = max(height * 2, 4)
        prev_x = int(round(rx))
        prev_y = fy
        last_x, last_y = prev_x, prev_y
        n_ramp = len(ramp)
        for i in range(n_steps + 1):
            t = i / n_steps
            # Horizontal parabolic sweep
            fx = rx + curve * (t ** curve_pow)
            # Vertical rise with optional graceful upper overhang droop (real wild grass fold!)
            if droop > 0.0 and t > 0.62:
                dt = (t - 0.62) / 0.38
                fy_cur = fy - height * t + droop * (dt ** 2.1)
                fx += math.copysign(droop * 0.55 * (dt ** 1.6), curve if abs(curve) > 0.1 else 1.0)
            else:
                fy_cur = fy - height * t
            bx = int(round(fx))
            by = int(round(fy_cur))

            # Directional top-left light bonus: blades bending left expose their convex upper back to top-left sun!
            bend_lit = 0.25 if (curve < -1.5 and 0.35 < t < 0.88) else (-0.18 if (curve > 2.8 and t > 0.65) else 0.0)
            # Drooping underside tip cools slightly at the very downward curl
            if droop > 1.2 and t > 0.88:
                bend_lit -= 0.28
            tf = max(0.0, min(0.999, t * 0.96 + bend_lit * 0.28))
            ci = min(n_ramp - 1, max(0, int(tf * (n_ramp - 0.05))))

            # Keep ribbon strictly 4-connected (never detached floating pixels!)
            if i > 0 and (abs(bx - prev_x) > 1 or abs(by - prev_y) > 1):
                mx = prev_x + (1 if bx > prev_x else (-1 if bx < prev_x else 0))
                my = prev_y + (1 if by > prev_y else (-1 if by < prev_y else 0))
                self.put(mx, my, ramp[max(0, ci - 1)])

            self.put(bx, by, ramp[ci])

            # Tapered width with genuine top-left light-to-shadow cross-section
            if base_w >= 2 and t <= 0.52:
                sh_side = 1 if curve >= -0.5 else -1
                if sh_side > 0:
                    # Main pixel is left (lit), shadow pixel is right (darker)
                    self.put(bx + 1, by, ramp[max(0, ci - 1)])
                else:
                    # Left-leaning blade: left pixel catches extra top-left light!
                    self.put(bx - 1, by, ramp[min(n_ramp - 1, ci + 1)] if t > 0.16 else ramp[ci])
            if base_w >= 3 and t <= 0.26:
                self.put(bx - 1, by, ramp[ci])
                self.put(bx + 1, by, ramp[max(0, ci - 1)])

            prev_x, prev_y = bx, by
            last_x, last_y = bx, by

        if dew:
            self.gput(last_x, last_y, dew_col)
        return last_x, last_y

    def broad_leaf(
        self,
        rx: float,
        height: int,
        curve: float,
        max_half_w: float,
        ramp: list[tuple[int, int, int, int]],
        root_y_off: int = 0,
    ) -> tuple[int, int]:
        """Sculpted lanceolate broadleaf (plantain, iris base, hart's-tongue) with lit left edge & cool shadow edge."""
        fy = self.foot_y + root_y_off
        n_ramp = len(ramp)
        last_x, last_y = int(round(rx)), fy
        for s in range(height + 1):
            t = s / max(1, height)
            cx = rx + curve * (t ** 1.35)
            by = fy - s
            # Pointed leaf silhouette: narrow base -> plump belly at t=0.45 -> crisp tapered tip
            hw = max_half_w * math.sin(t * math.pi) ** 0.72
            ix0 = int(round(cx - hw))
            ix1 = int(round(cx + hw))
            base_ci = min(n_ramp - 1, int(t * (n_ramp - 0.1)))
            for x in range(ix0, ix1 + 1):
                rel = (x - cx) / max(0.6, hw) if hw > 0.35 else 0.0
                # Top-left sun: left half brighter, center vein crisp, right half cool-shaded
                delta = 1 if rel < -0.35 else (-1 if rel > 0.35 else 0)
                ci = max(0, min(n_ramp - 1, base_ci + delta))
                self.put(x, by, ramp[ci])
            last_x, last_y = int(round(cx)), by
        return last_x, last_y

    def fern_frond(
        self,
        rx: float,
        length: int,
        curve: float,
        ramp: list[tuple[int, int, int, int]],
        y_slope: float = 0.88,
        pinna_span: int = 2,
        droop: float = 0.0,
    ) -> None:
        """Organic feathered woodland fern frond with angled asymmetric pinnae (no stiff ladder bars)."""
        n_ramp = len(ramp)
        side = -1 if curve < 0 else 1
        for step in range(length):
            t = step / max(1, length - 1)
            bx = int(round(rx + curve * (t ** 1.18)))
            drop = droop * ((max(0.0, t - 0.55) / 0.45) ** 2.0)
            by = self.foot_y - int(round(step * y_slope - drop))
            ci = min(n_ramp - 1, int(t * (n_ramp - 0.05)))
            self.put(bx, by, ramp[max(0, ci - 1)])  # darker central rachis
            if 1 <= step <= length - 2:
                # Tapered feathered pinnae widest in middle, tapering toward tip
                span = max(1, int(round(pinna_span * math.sin(t * math.pi) ** 0.65)))
                hi = ramp[min(n_ramp - 1, ci + 1)]
                mid = ramp[ci]
                sh = ramp[max(0, ci - 1)]
                for p in range(1, span + 1):
                    # Upper/outer pinna catches light
                    self.put(bx - side * (p // 2), by - p, hi if p == span else mid)
                    if step % 2 == 1 or p == 1:
                        self.put(bx + side * p, by - (p - 1), mid if p == 1 else sh)
            elif step == length - 1:
                self.put(bx, by, ramp[-1])

    def moss_cushion(
        self,
        lobes: list[tuple[float, float, float, float]],
        ramp: list[tuple[int, int, int, int]],
    ) -> None:
        """Multi-lobed 3D velvety moss pillow lit from top-left."""
        n = len(ramp)
        for mx, my, rx, ry in lobes:
            for y in range(int(my - ry - 1), int(my + ry + 2)):
                for x in range(int(mx - rx - 1), int(mx + rx + 2)):
                    d = ((x - mx) / rx) ** 2 + ((y - my) / ry) ** 2
                    if d <= 1.0:
                        lit = -0.48 * (x - mx) / rx - 0.86 * (y - my) / ry
                        # Subtle organic dither on cushion texture
                        lit += 0.14 if ((x * 3 + y * 5) % 4 == 0) else (-0.08 if ((x + y) % 3 == 0) else 0.0)
                        idx = int((lit * 0.5 + 0.5) * (n - 0.05))
                        self.put(x, y, ramp[max(0, min(n - 1, idx))])

    def micro_blossom(self, cx: int, cy: int, hi, mid, sh, core, glow_c=None) -> None:
        """Crisp 3x3 top-left-lit flower head."""
        self.put(cx, cy - 1, hi)
        self.put(cx - 1, cy, hi)
        self.put(cx + 1, cy, sh)
        self.put(cx, cy + 1, sh)
        self.put(cx, cy, core)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)

    def daisy_head(self, cx: int, cy: int, hi, mid, sh, core, glow_c=None) -> None:
        """Larger 5x4 sculpted oxeye daisy / wildflower blossom for tall meadow stalks."""
        self.put(cx - 1, cy - 1, hi)
        self.put(cx, cy - 1, hi)
        self.put(cx + 1, cy - 1, mid)
        self.put(cx - 2, cy, hi)
        self.put(cx - 1, cy, mid)
        self.put(cx + 1, cy, mid)
        self.put(cx + 2, cy, sh)
        self.put(cx - 1, cy + 1, mid)
        self.put(cx, cy + 1, sh)
        self.put(cx + 1, cy + 1, sh)
        self.put(cx, cy, core)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)
            self.gput(cx, cy - 1, (glow_c[0], glow_c[1], glow_c[2], glow_c[3] // 2))

    def mini_bud(self, cx: int, cy: int, hi, sh, glow_c=None) -> None:
        self.put(cx, cy, hi)
        self.put(cx + 1, cy, sh)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)

    def umbel_lace(self, cx: int, cy: int, w_half: int, hi, mid, sh, glow_c=None) -> None:
        """Airy flat-topped lace umbel (yarrow / Queen Anne's lace / cow-parsley)."""
        for dx in range(-w_half, w_half + 1):
            dy = 0 if abs(dx) <= 1 else 1
            col = hi if dx <= 0 else (mid if dx == 1 else sh)
            self.put(cx + dx, cy + dy, col)
            if abs(dx) % 2 == 0:
                self.put(cx + dx, cy + dy - 1, hi if dx <= 0 else mid)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)
            self.gput(cx - 1, cy, (glow_c[0], glow_c[1], glow_c[2], glow_c[3] // 2))

    def seed_panicle(self, sx: int, sy: int, sdir: int, hi, mid, sh, length: int = 4, glow_c=None) -> None:
        """Nodding feathered seed spikelet / oat plume."""
        self.put(sx, sy, hi)
        for k in range(1, length):
            ox = sdir if (k % 2 == 1) else -sdir
            self.put(sx, sy + k, mid if k < length - 1 else sh)
            self.put(sx + ox, sy + k, hi if k == 1 else (mid if k < length - 1 else sh))
        if glow_c is not None:
            self.gput(sx, sy, glow_c)


# ==============================================================================
# STANDARD 20x24 ATLAS (40 HANDCRAFTED VARIANTS)
# ==============================================================================

def draw_standard_variant(v: int) -> Canvas:
    c = Canvas(STD_W, STD_H, STD_FOOT_Y)

    # ================ ROW 0 (0..7): LUSH MEADOW FESCUE & TURF ================
    if v == 0:
        # Classic rich asymmetric meadow clump with subtle warm-olive basal blade
        c.root_tuck(4, 15)
        c.blade(7.5, 11, -3.6, BACK_RAMP, base_w=2, droop=1.0)
        c.blade(12.0, 10, 3.8, BACK_RAMP, base_w=2)
        c.blade(10.0, 12, 1.4, MID_RAMP, base_w=2)
        c.blade(6.0, 8, -3.5, OLIVE_RAMP[:4], base_w=1)
        c.blade(8.8, 13, -2.0, SUN_RAMP, base_w=2, droop=1.2, dew=True)
        c.blade(11.5, 11, 2.8, LIT_RAMP, base_w=2, droop=0.8)
        c.blade(13.5, 8, 3.6, MID_RAMP, base_w=1)
        c.blade(5.2, 7, -2.8, LIT_RAMP, base_w=1)

    elif v == 1:
        # Wide wind-combed meadow carpet sweeping gently right
        c.root_tuck(3, 16)
        c.blade(5.5, 8, 1.8, BACK_RAMP, base_w=2)
        c.blade(9.5, 10, 4.2, BACK_RAMP, base_w=2, droop=0.9)
        c.blade(13.0, 9, 4.0, BACK_RAMP, base_w=2)
        c.blade(7.0, 11, 3.6, SUN_RAMP, base_w=2, droop=1.2)
        c.blade(11.0, 10, 4.4, LIT_RAMP, base_w=2, droop=1.0)
        c.blade(4.5, 7, -1.8, LIT_RAMP, base_w=1)
        c.blade(8.5, 8, 2.6, SUN_RAMP, base_w=1)
        c.blade(14.5, 6, 3.2, OLIVE_RAMP[:4], base_w=1)

    elif v == 2:
        # Wide wind-combed meadow carpet sweeping gracefully left with curled tip
        c.root_tuck(4, 16)
        c.blade(14.0, 9, -2.2, BACK_RAMP, base_w=2)
        c.blade(10.5, 11, -4.4, BACK_RAMP, base_w=2, droop=1.0)
        c.blade(12.2, 12, -3.8, LIT_RAMP, base_w=2, droop=1.4, dew=True)
        c.blade(8.5, 11, -4.5, SUN_RAMP, base_w=2, droop=1.2)
        c.blade(6.5, 8, -3.4, LIT_RAMP, base_w=1)
        c.blade(11.0, 8, -1.2, MID_RAMP, base_w=2)
        c.blade(15.0, 7, 2.4, OLIVE_RAMP[:4], base_w=1)

    elif v == 3:
        # Low velvety short turf cushion (smooth transition between clearings & lush grass)
        c.root_tuck(4, 15, 0.85)
        c.blade(6.0, 6, -2.2, BACK_RAMP, base_w=2)
        c.blade(9.5, 7, -0.4, BACK_RAMP, base_w=2)
        c.blade(13.0, 6, 2.5, BACK_RAMP, base_w=2)
        c.blade(7.5, 8, -2.0, SUN_RAMP, base_w=2)
        c.blade(11.2, 8, 1.8, LIT_RAMP, base_w=2)
        c.blade(5.0, 5, -2.6, LIT_RAMP, base_w=1)
        c.blade(14.0, 5, 2.6, MID_RAMP, base_w=1)

    elif v == 4:
        # Wide interlocked twin-horst meadow clump with natural shadow pocket between crowns
        c.root_tuck(2, 17)
        c.blade(5.2, 10, -3.2, BACK_RAMP, base_w=2)
        c.blade(14.0, 10, 3.4, BACK_RAMP, base_w=2)
        c.blade(6.6, 11, -1.2, SUN_RAMP, base_w=2, droop=1.0)
        c.blade(8.2, 8, 1.6, MID_RAMP, base_w=1)
        c.blade(12.2, 12, -1.4, LIT_RAMP, base_w=2, droop=1.0, dew=True)
        c.blade(13.5, 9, 3.2, MID_RAMP, base_w=2)
        c.blade(4.0, 7, -2.8, LIT_RAMP, base_w=1)
        c.blade(10.2, 7, 0.6, OLIVE_RAMP[:4], base_w=1)

    elif v == 5:
        # Dew-bent fine morning fescue (delicate thin arching fountain, pearl dew tips)
        c.root_tuck(5, 14, 0.9)
        c.blade(8.5, 12, -4.8, BACK_RAMP, base_w=1, droop=1.8)
        c.blade(11.5, 12, 4.8, BACK_RAMP, base_w=1, droop=1.8)
        c.blade(9.2, 13, -3.2, SUN_RAMP, base_w=1, droop=1.6, dew=True, dew_col=DEW_HI)
        c.blade(10.8, 13, 3.0, LIT_RAMP, base_w=1, droop=1.6, dew=True)
        c.blade(7.2, 9, -4.2, LIT_RAMP, base_w=1, droop=1.0)
        c.blade(12.8, 9, 4.0, MID_RAMP, base_w=1, droop=1.0)
        c.blade(10.0, 10, -0.5, SUN_RAMP, base_w=1)

    elif v == 6:
        # Sun-drenched crest tuft catching warm top-left light on broad folded arches
        c.root_tuck(4, 15)
        c.blade(7.0, 10, 1.0, BACK_RAMP, base_w=2)
        c.blade(12.2, 11, 4.2, BACK_RAMP, base_w=2, droop=1.2)
        c.blade(8.5, 13, 3.0, SUN_RAMP, base_w=2, droop=1.6, dew=True)
        c.blade(10.5, 11, 4.4, LIT_RAMP, base_w=2, droop=1.2)
        c.blade(6.2, 9, -2.6, SUN_RAMP, base_w=2)
        c.blade(13.5, 7, 3.4, MID_RAMP, base_w=1)

    elif v == 7:
        # Sparse delicate low shoots (natural frayed path edges & moss clearings)
        c.root_tuck(5, 14, 0.65)
        c.blade(6.5, 6, -2.4, MID_RAMP, base_w=1)
        c.blade(9.5, 7, -0.8, SUN_RAMP, base_w=1)
        c.blade(11.8, 6, 2.2, LIT_RAMP, base_w=1)
        c.blade(8.2, 5, 1.4, BACK_RAMP, base_w=1)
        c.blade(13.2, 4, 2.0, OLIVE_RAMP[:4], base_w=1)

    # ================ ROW 1 (8..15): MID SEDGE, BROADLEAF, GOLDEN, MOSS & CLOVER ================
    elif v == 8:
        # Sweeping overarching meadow sedge (16-18 px tall, iconic ribbon-fold blades!)
        c.root_tuck(4, 15, 1.05)
        c.blade(8.0, 16, -5.6, BACK_RAMP, base_w=2, droop=2.2)
        c.blade(12.0, 15, 5.4, BACK_RAMP, base_w=2, droop=2.0)
        c.blade(9.8, 17, 1.6, MID_RAMP, base_w=2, droop=1.2)
        c.blade(8.8, 18, -3.0, SUN_RAMP, base_w=2, droop=2.2, dew=True)
        c.blade(6.5, 12, -5.0, LIT_RAMP, base_w=2, droop=1.4)
        c.blade(12.8, 12, 4.6, MID_RAMP, base_w=2, droop=1.2)
        c.blade(10.5, 10, 2.5, OLIVE_RAMP[:4], base_w=1)

    elif v == 9:
        # Wind-swept right-leaning golden-tipped meadow ryegrass
        c.root_tuck(4, 15)
        c.blade(6.5, 14, 3.0, BACK_RAMP, base_w=2)
        c.blade(10.2, 16, 5.8, BACK_RAMP, base_w=2, droop=2.0)
        c.blade(8.0, 18, 5.2, SUN_RAMP, base_w=2, droop=2.2, dew=True)
        c.blade(5.5, 11, -2.4, LIT_RAMP, base_w=2)
        c.blade(9.8, 13, 5.4, LIT_RAMP, base_w=2, droop=1.4)
        sx, sy = c.blade(11.5, 15, 4.2, OLIVE_RAMP, base_w=1)
        c.put(sx, sy, SEED_L)
        c.put(sx + 1, sy + 1, SEED_M)

    elif v == 10:
        # Wind-swept left-leaning lush meadow grass with crossed ribbon blades
        c.root_tuck(5, 16)
        c.blade(13.2, 14, -2.8, BACK_RAMP, base_w=2)
        c.blade(9.5, 16, -5.6, BACK_RAMP, base_w=2, droop=2.0)
        c.blade(11.2, 18, -5.0, SUN_RAMP, base_w=2, droop=2.2, dew=True)
        c.blade(14.2, 11, 2.4, MID_RAMP, base_w=2)
        c.blade(10.2, 13, -5.2, LIT_RAMP, base_w=2, droop=1.5)
        c.blade(7.8, 9, -3.8, LIT_RAMP, base_w=1)

    elif v == 11:
        # Broadleaf ribwort plantain & grass rosette (Spitzwegerich — authentic meadow herb!)
        c.root_tuck(3, 16)
        c.broad_leaf(7.5, 10, -4.5, 2.0, MOSS_RAMP)
        c.broad_leaf(12.2, 10, 4.5, 2.0, MOSS_RAMP[:4])
        c.broad_leaf(9.6, 12, -1.2, 1.8, SUN_RAMP)
        c.blade(6.0, 9, -3.6, LIT_RAMP, base_w=1)
        c.blade(13.5, 8, 3.4, MID_RAMP, base_w=1)
        # Characteristic tall dark-brown/cream plantain flower spike!
        sx, sy = c.blade(10.8, 15, 1.2, MID_RAMP, base_w=1)
        c.put(sx, sy - 1, SEED_L)
        c.put(sx, sy, SEED_M)
        c.put(sx + 1, sy, CAT_M)
        c.put(sx, sy + 1, CAT_D)

    elif v == 12:
        # Deep cool blue-emerald moist hollow sedge
        c.root_tuck(4, 15, 1.1)
        c.blade(7.5, 15, -4.6, MOSS_RAMP[:4], base_w=2, droop=1.8)
        c.blade(12.2, 15, 4.6, MOSS_RAMP[:4], base_w=2, droop=1.8)
        c.blade(9.8, 17, -1.2, MOSS_LIT, base_w=2, droop=1.4, dew=True)
        c.blade(11.0, 13, 3.4, MOSS_RAMP[1:], base_w=2, droop=1.0)
        c.blade(6.5, 10, -3.8, MOSS_LIT, base_w=1)

    elif v == 13:
        # Sun-warmed olive-gold late-summer wild meadow horst
        c.root_tuck(4, 15)
        c.blade(7.2, 13, -3.8, BACK_RAMP, base_w=2)
        c.blade(12.5, 13, 3.8, BACK_RAMP, base_w=2)
        c.blade(8.8, 16, -2.6, OLIVE_RAMP, base_w=2, droop=1.8)
        c.blade(11.2, 15, 2.8, SUN_RAMP, base_w=2, droop=1.6, dew=True)
        c.blade(10.0, 12, 0.4, OLIVE_RAMP[1:], base_w=2)
        c.blade(6.0, 9, -3.2, LIT_RAMP, base_w=1)

    elif v == 14:
        # Plush multi-lobed velvety moss pillow with tiny leaning sporophyte filaments & fine shoots
        c.root_tuck(2, 17, 0.95)
        c.moss_cushion(
            [(6.2, 20.0, 4.4, 2.5), (13.4, 20.5, 4.0, 2.3), (9.8, 19.3, 4.6, 2.8)],
            [G1, G2, G3, G4, G5],
        )
        c.blade(4.5, 7, -2.4, SUN_RAMP, base_w=1, root_y_off=-1)
        c.blade(14.5, 6, 2.6, LIT_RAMP, base_w=1, root_y_off=-1)
        # Delicate asymmetric moss sporophyte filaments (leaning gently, never straight candles)
        c.put(7, 17, O2)
        c.put(7, 16, O3)
        c.put(6, 15, SEED_L)
        c.put(11, 16, O2)
        c.put(12, 15, SEED_M)
        c.put(12, 14, SEED_L)

    elif v == 15:
        # Delicate sprawling woodland clover & shamrock mat + tiny white clover tuft
        c.root_tuck(3, 16, 0.85)
        c.blade(5.5, 8, -2.6, BACK_RAMP, base_w=1)
        c.blade(14.0, 8, 2.6, BACK_RAMP, base_w=1)
        c.blade(9.5, 7, -0.5, MID_RAMP, base_w=1)
        for lx, ly, hi, mid, sh in (
            (5, 19, G5, G4, G2),
            (10, 19, G4, G3, G1),
            (14, 19, G4, G3, G1),
            (7, 16, G6, G4, G2),
            (12, 16, G5, G4, G2),
            (4, 15, G5, G3, G1),
            (15, 15, G4, G3, G1),
            (9, 14, G6, G5, G3),
        ):
            c.put(lx, ly - 1, hi)
            c.put(lx - 1, ly, mid)
            c.put(lx + 1, ly, sh)
            c.put(lx, ly, mid)
            c.put(lx, ly + 1, sh)
        c.mini_bud(11, 13, WHITE_L, WHITE_M, BLOOM_G)

    # ================ ROW 2 (16..23): 8 DISTINCT WILDFLOWER SPECIES ================
    elif v == 16:
        # White Chamomile / Starwort cushion (Kamille)
        c.root_tuck(3, 16)
        c.blade(5.5, 11, -3.4, BACK_RAMP, base_w=2)
        c.blade(14.0, 11, 3.4, BACK_RAMP, base_w=2)
        c.blade(9.2, 12, -1.0, MID_RAMP, base_w=2)
        c.blade(11.4, 11, 2.2, LIT_RAMP, base_w=2)
        c.blade(7.2, 9, -2.0, LIT_RAMP, base_w=1)
        c.micro_blossom(6, 13, WHITE_L, WHITE_M, WHITE_D, GOLD_C, BLOOM_G)
        c.micro_blossom(13, 13, WHITE_L, WHITE_M, WHITE_D, GOLD_C)
        c.micro_blossom(9, 10, WHITE_L, WHITE_M, WHITE_D, GOLD_L, BLOOM_G)
        c.mini_bud(3, 16, WHITE_L, WHITE_D)
        c.mini_bud(15, 15, WHITE_M, WHITE_D)
        c.mini_bud(10, 16, WHITE_L, WHITE_M)

    elif v == 17:
        # Low sprawling meadow daisy carpet (Gänseblümchen)
        c.root_tuck(2, 17, 0.9)
        for bx, bh, bc in ((4, 7, -2.4), (7, 8, -0.8), (11, 8, 1.4), (15, 6, 2.6), (9, 6, -0.2)):
            c.blade(float(bx), bh, bc, MID_RAMP if bx % 2 else LIT_RAMP, base_w=2)
        for cx, cy in ((5, 16), (9, 15), (14, 16), (7, 13), (12, 13)):
            c.mini_bud(cx, cy, WHITE_L, WHITE_M, BLOOM_G if cx == 7 else None)
            c.put(cx, cy + 1, WHITE_D)
        c.micro_blossom(10, 17, WHITE_L, WHITE_M, WHITE_D, GOLD_C)
        c.put(15, 14, ROSE_L)  # delicate pink daisy bud tip

    elif v == 18:
        # Sunlit meadow Buttercup cluster (Hahnenfuß — warm golden cups!)
        c.root_tuck(3, 16)
        c.blade(6.0, 11, -3.2, BACK_RAMP, base_w=2)
        c.blade(13.5, 11, 3.2, BACK_RAMP, base_w=2)
        c.blade(9.5, 13, 0.4, LIT_RAMP, base_w=2)
        c.blade(11.5, 10, 2.6, MID_RAMP, base_w=1)
        c.micro_blossom(7, 12, GOLD_L, GOLD_C, GOLD_D, WHITE_L, GOLD_G)
        c.micro_blossom(13, 13, GOLD_L, GOLD_C, GOLD_D, GOLD_C)
        c.micro_blossom(10, 9, GOLD_L, GOLD_C, GOLD_D, WHITE_L, GOLD_G)
        c.mini_bud(4, 15, GOLD_L, GOLD_D)
        c.mini_bud(14, 16, GOLD_C, GOLD_D)

    elif v == 19:
        # Pale-blue Forget-me-not pocket (Vergissmeinnicht)
        c.root_tuck(3, 16)
        c.blade(5.5, 10, -2.8, MOSS_RAMP[:4], base_w=2)
        c.blade(14.0, 10, 2.8, MOSS_RAMP[:4], base_w=2)
        c.blade(9.5, 11, -0.8, MOSS_RAMP, base_w=2)
        c.blade(11.5, 10, 2.0, LIT_RAMP, base_w=2)
        c.micro_blossom(6, 14, BLUE_L, BLUE_M, BLUE_D, GOLD_L, BLOOM_G)
        c.micro_blossom(13, 14, BLUE_L, BLUE_M, BLUE_D, GOLD_L)
        c.micro_blossom(9, 11, BLUE_L, BLUE_M, BLUE_D, WHITE_L, BLOOM_G)
        c.mini_bud(4, 16, BLUE_L, BLUE_D)
        c.mini_bud(14, 17, BLUE_M, BLUE_D)
        c.mini_bud(11, 15, BLUE_L, BLUE_M)

    elif v == 20:
        # Wild Red-Clover & Meadow-Rose tuft (Wiesenklee — dusty rose flower domes!)
        c.root_tuck(3, 16)
        c.blade(6.0, 10, -3.0, BACK_RAMP, base_w=2)
        c.blade(13.5, 10, 3.0, BACK_RAMP, base_w=2)
        c.blade(9.8, 12, 0.5, LIT_RAMP, base_w=2)
        c.blade(8.0, 9, -1.8, MID_RAMP, base_w=1)
        # Round fluffy rose clover heads (3x3 dome with bright top-left highlight)
        for rx, ry, gl in ((7, 12, ROSE_G), (13, 14, None), (10, 10, ROSE_G)):
            c.put(rx, ry - 1, ROSE_L)
            c.put(rx - 1, ry, ROSE_L)
            c.put(rx, ry, ROSE_M)
            c.put(rx + 1, ry, ROSE_D)
            c.put(rx, ry + 1, ROSE_D)
            if gl:
                c.gput(rx, ry, gl)
        c.mini_bud(4, 16, ROSE_L, ROSE_D)

    elif v == 21:
        # Delicate nodding Harebell / Meadow Bellflower (Glockenblume)
        c.root_tuck(4, 15)
        c.blade(6.5, 10, -3.0, BACK_RAMP, base_w=2)
        c.blade(13.0, 10, 3.0, BACK_RAMP, base_w=2)
        c.blade(9.5, 11, 0.8, LIT_RAMP, base_w=1)
        # Slender arched bellflower stems with drooping lilac-blue bells
        bx1, by1 = c.blade(8.0, 14, -3.2, MID_RAMP, base_w=1, droop=1.5)
        bx2, by2 = c.blade(11.2, 13, 3.4, MID_RAMP, base_w=1, droop=1.5)
        for bx, by in ((bx1, by1), (bx2, by2)):
            c.put(bx, by, LILAC_L)
            c.put(bx - 1, by + 1, LILAC_M)
            c.put(bx, by + 1, LILAC_L)
            c.put(bx + 1, by + 1, LILAC_D)
            c.put(bx, by + 2, LILAC_D)
            c.gput(bx, by + 1, LILAC_G)

    elif v == 22:
        # White Yarrow umbel tuft (Schafgarbe — crisp flat cream-white umbrellas)
        c.root_tuck(4, 15)
        c.blade(6.0, 10, -3.0, MOSS_RAMP[:4], base_w=2)
        c.blade(13.5, 10, 3.2, MOSS_RAMP[:4], base_w=2)
        c.blade(10.0, 11, -0.5, LIT_RAMP, base_w=2)
        ux1, uy1 = c.blade(8.0, 14, -1.6, MID_RAMP, base_w=1)
        ux2, uy2 = c.blade(12.2, 12, 2.0, MID_RAMP, base_w=1)
        c.umbel_lace(ux1, uy1, 2, CREAM_L, CREAM_M, CREAM_D, BLOOM_G)
        c.umbel_lace(ux2, uy2, 2, WHITE_L, CREAM_M, CREAM_D)

    elif v == 23:
        # Dandelion + fluffy silver seed-puff tuft (Löwenzahn & Pusteblume!)
        c.root_tuck(4, 15)
        c.broad_leaf(7.5, 7, -3.5, 1.5, MID_RAMP)
        c.broad_leaf(12.0, 7, 3.5, 1.5, BACK_RAMP)
        c.blade(9.5, 9, 0.5, LIT_RAMP, base_w=1)
        dx1, dy1 = c.blade(7.5, 12, -2.0, MID_RAMP, base_w=1)
        dx2, dy2 = c.blade(11.8, 14, 2.2, MID_RAMP, base_w=1)
        # Golden dandelion blossom
        c.micro_blossom(dx1, dy1, GOLD_L, GOLD_C, GOLD_D, GOLD_L, GOLD_G)
        # Delicate translucent silver-white puffball!
        c.put(dx2, dy2 - 1, SILV_L)
        c.put(dx2 - 1, dy2, SILV_L)
        c.put(dx2 + 1, dy2, SILV_M)
        c.put(dx2, dy2 + 1, SILV_D)
        c.put(dx2, dy2, WHITE_L)
        c.gput(dx2, dy2, DEW_HI)

    # ================ ROW 3 (24..31): WOODLAND FERNS, MOSS & CREVICE FLORA ================
    elif v == 24:
        # Graceful symmetrical woodland lady-fern rosette (Frauenfarn)
        c.root_tuck(5, 14, 1.1)
        c.fern_frond(9.2, 13, -7.2, MOSS_RAMP, y_slope=0.80, pinna_span=2, droop=2.0)
        c.fern_frond(10.8, 13, 7.2, MOSS_RAMP[:4], y_slope=0.80, pinna_span=2, droop=2.0)
        c.fern_frond(9.0, 15, -4.0, MOSS_LIT, y_slope=0.92, pinna_span=2, droop=1.4)
        c.fern_frond(11.0, 14, 4.2, MOSS_RAMP, y_slope=0.90, pinna_span=2, droop=1.4)
        c.fern_frond(10.0, 12, -0.6, SUN_RAMP, y_slope=0.95, pinna_span=1, droop=0.5)

    elif v == 25:
        # Low spreading bracken fern (Adlerfarn)
        c.root_tuck(4, 15, 1.0)
        c.fern_frond(8.2, 10, -6.8, MOSS_LIT, y_slope=0.72, pinna_span=2, droop=1.2)
        c.fern_frond(11.8, 10, 6.8, MOSS_RAMP[:4], y_slope=0.72, pinna_span=2, droop=1.2)
        c.fern_frond(9.4, 11, -2.6, LIT_RAMP, y_slope=0.84, pinna_span=2, droop=0.8)
        c.fern_frond(10.6, 10, 3.0, MID_RAMP, y_slope=0.84, pinna_span=2, droop=0.8)

    elif v == 26:
        # Curled young fern fiddleheads nested inside low woodland moss & flank fronds!
        c.root_tuck(4, 15, 1.0)
        c.moss_cushion([(7.0, 20.4, 3.8, 2.1), (12.8, 20.5, 3.8, 2.1), (9.8, 19.9, 4.0, 2.3)], MOSS_RAMP)
        c.fern_frond(7.0, 8, -4.8, MOSS_RAMP[:4], y_slope=0.72, pinna_span=1, droop=0.8)
        c.fern_frond(13.2, 8, 4.8, MOSS_RAMP[:4], y_slope=0.72, pinna_span=1, droop=0.8)
        for rx, h, curve, sdir, ramp in ((8.4, 10, -1.6, -1, MOSS_LIT), (11.2, 12, 1.8, 1, SUN_RAMP)):
            tx, ty = c.blade(rx, h, curve, ramp, base_w=2 if h > 10 else 1, root_y_off=-1)
            # Tight botanical spiral fiddlehead curl
            c.put(tx, ty - 1, ramp[-1])
            c.put(tx + sdir, ty - 1, ramp[-1])
            c.put(tx + sdir, ty, ramp[-2])
            c.put(tx, ty + 1, ramp[max(0, len(ramp) - 3)])
            c.gput(tx, ty - 1, DEW_DIM)

    elif v == 27:
        # Woodland bilberry & wood-sorrel subshrub sprigs (Heidelbeerkraut)
        c.root_tuck(4, 15, 1.0)
        c.blade(7.5, 10, -3.5, MOSS_RAMP[:4], base_w=1)
        c.blade(12.2, 10, 3.5, MOSS_RAMP[:4], base_w=1)
        c.blade(9.8, 11, -0.6, MOSS_RAMP, base_w=1)
        for lx, ly, hi, sh in (
            (5, 15, M4, M2), (7, 13, M5, M3), (10, 12, M5, M3),
            (13, 13, M4, M2), (14, 16, M3, M1), (8, 17, M4, M2), (12, 17, M4, M2),
        ):
            c.put(lx, ly - 1, hi)
            c.put(lx - 1, ly, hi)
            c.put(lx, ly, M3)
            c.put(lx + 1, ly, sh)
        # Tiny dusky-blue woodland bilberries tucked under leaves
        c.put(7, 15, BLUE_D)
        c.put(12, 15, BLUE_D)

    elif v == 28:
        # Shaded forest sedge emerging through fallen russet oak leaves!
        c.root_tuck(3, 16, 1.05)
        c.blade(7.8, 12, -4.0, MOSS_RAMP[:4], base_w=2, droop=1.4)
        c.blade(12.0, 11, 3.8, MOSS_RAMP[:4], base_w=2, droop=1.2)
        c.blade(9.8, 13, -1.2, MOSS_LIT, base_w=2, droop=1.2)
        c.blade(11.0, 9, 2.6, OLIVE_RAMP[:4], base_w=1)
        # Sculpted fallen autumn-oak leaves resting around the root base
        for lx, ly in ((5, 20), (13, 20), (9, 21)):
            c.put(lx - 1, ly, LEAF_L)
            c.put(lx, ly, LEAF_M)
            c.put(lx + 1, ly, LEAF_D)
            c.put(lx, ly - 1, LEAF_L)

    elif v == 29:
        # Stone-crevice wild thyme & hardy compact rock tuft (Mauer-Thymian)
        c.root_tuck(3, 16, 0.8)
        c.moss_cushion([(6.8, 20.6, 3.6, 1.9), (12.6, 20.8, 3.5, 1.8), (9.8, 20.0, 3.8, 2.0)], MOSS_RAMP)
        c.blade(5.5, 6, -2.4, MOSS_LIT, base_w=1)
        c.blade(13.8, 6, 2.4, MOSS_RAMP, base_w=1)
        c.blade(9.5, 7, -0.4, LIT_RAMP, base_w=1)
        # Tiny lilac-pink wild thyme flower specks
        for tx, ty in ((6, 18), (10, 17), (13, 18)):
            c.put(tx, ty, ROSE_L)
            c.put(tx + 1, ty, ROSE_M)

    elif v == 30:
        # Velvet forest moss pillow with 2 tiny 3px glowing woodland pin-mushrooms!
        c.root_tuck(3, 16, 1.0)
        c.moss_cushion([(7.0, 20.4, 4.2, 2.2), (12.8, 20.5, 4.0, 2.1), (10.0, 19.6, 4.4, 2.5)], MOSS_RAMP)
        c.blade(4.8, 6, -1.8, MOSS_LIT, base_w=1)
        c.blade(14.5, 6, 2.0, MOSS_RAMP, base_w=1)
        # Two miniature pin-mushrooms
        for mx, my in ((8, 17), (12, 18)):
            c.put(mx, my + 1, CREAM_D)
            c.put(mx, my, CREAM_M)
            c.put(mx - 1, my - 1, CREAM_L)
            c.put(mx, my - 1, CREAM_L)
            c.put(mx + 1, my - 1, CREAM_M)
            c.gput(mx, my - 1, PEARL_G)

    elif v == 31:
        # Broad glossy damp-hollow hart's-tongue fern (Hirschzungenfarn)
        c.root_tuck(4, 15, 1.1)
        c.broad_leaf(8.2, 12, -5.2, 2.1, MOSS_RAMP)
        c.broad_leaf(11.8, 12, 5.2, 2.1, MOSS_RAMP[:4])
        c.broad_leaf(9.6, 14, -1.8, 2.0, MOSS_LIT)
        c.broad_leaf(10.8, 11, 2.4, 1.8, MOSS_RAMP[1:])

    # ================ ROW 4 (32..39): SEED PLUMES, RIPARIAN & COASTAL ================
    elif v == 32:
        # Slender meadow grass with nodding golden oat panicles (Wiesenhafer)
        c.root_tuck(4, 15)
        c.blade(6.5, 12, -3.2, BACK_RAMP, base_w=2)
        c.blade(13.0, 11, 3.4, BACK_RAMP, base_w=2)
        c.blade(8.5, 13, -1.6, LIT_RAMP, base_w=2)
        sx1, sy1 = c.blade(10.5, 18, 2.8, MID_RAMP, base_w=1, droop=1.0)
        sx2, sy2 = c.blade(7.8, 17, -3.2, LIT_RAMP, base_w=1, droop=1.0)
        c.seed_panicle(sx1, sy1, 1, SEED_L, SEED_M, SEED_D, 4, DEW_DIM)
        c.seed_panicle(sx2, sy2, -1, SEED_L, SEED_M, SEED_D, 4, DEW_DIM)

    elif v == 33:
        # Meadow Foxtail / Timothy grass with cylindrical plush golden spikes (Wiesen-Fuchsschwanz)
        c.root_tuck(4, 15)
        c.blade(6.2, 11, -3.0, BACK_RAMP, base_w=2)
        c.blade(13.2, 11, 3.0, BACK_RAMP, base_w=2)
        c.blade(9.5, 12, 0.5, LIT_RAMP, base_w=2)
        for rx, h, cv in ((8.0, 17, -2.0), (11.5, 18, 2.2)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1)
            for k in range(5):
                c.put(tx, ty + k, SEED_L if k < 2 else SEED_M)
                c.put(tx + 1, ty + k, SEED_M if k < 3 else SEED_D)
            c.gput(tx, ty, DEW_DIM)

    elif v == 34:
        # Quaking grass (Zittergras — tiny suspended heart spikelets on airy stems)
        c.root_tuck(5, 14, 0.9)
        c.blade(7.0, 10, -3.0, BACK_RAMP, base_w=1)
        c.blade(12.5, 10, 3.0, BACK_RAMP, base_w=1)
        c.blade(9.5, 11, -0.5, SUN_RAMP, base_w=1)
        for rx, h, cv, sd in ((7.5, 16, -3.8, -1), (10.5, 18, 1.5, 1), (12.0, 15, 3.6, 1)):
            tx, ty = c.blade(rx, h, cv, LIT_RAMP, base_w=1)
            # Dangling heart-shaped seed head
            c.put(tx, ty, SEED_L)
            c.put(tx + sd, ty + 1, SEED_L)
            c.put(tx, ty + 1, SEED_M)
            c.put(tx + sd, ty + 2, SEED_D)
            c.gput(tx, ty, DEW_DIM)

    elif v == 35:
        # Lush Riparian Brook Sedge (Ufer-Segge — teal-green moisture-loving arch!)
        c.root_tuck(4, 15, 1.1)
        c.blade(7.5, 15, -5.2, REED_DARK, base_w=2, droop=2.0)
        c.blade(12.5, 15, 5.2, REED_DARK, base_w=2, droop=2.0)
        c.blade(9.0, 17, -2.5, REED_RAMP, base_w=2, droop=1.8, dew=True)
        c.blade(11.2, 16, 3.2, REED_RAMP, base_w=2, droop=1.6)
        c.blade(6.2, 11, -4.2, REED_RAMP[1:], base_w=1)

    elif v == 36:
        # Brook-edge rush & lilac water-mint tuft (Binsen & Bachminze)
        c.root_tuck(4, 15, 1.0)
        c.blade(6.8, 16, -2.2, REED_DARK, base_w=1)
        c.blade(8.8, 18, -0.8, REED_RAMP, base_w=1, dew=True)
        c.blade(11.2, 17, 1.5, REED_RAMP, base_w=1)
        c.blade(13.2, 14, 3.2, REED_DARK, base_w=1)
        # Water-mint sprig with tiny lilac blossom buds
        mx, my = c.blade(10.0, 12, 0.2, MOSS_LIT, base_w=2)
        c.micro_blossom(mx, my, LILAC_L, LILAC_M, LILAC_D, WHITE_L, LILAC_G)
        c.mini_bud(mx - 2, my + 2, LILAC_L, LILAC_D)

    elif v == 37:
        # Wild Red-Sorrel meadow tuft (Sauerampfer — rustic russet-rose seed spires!)
        c.root_tuck(4, 15)
        c.blade(6.5, 11, -3.2, BACK_RAMP, base_w=2)
        c.blade(13.2, 11, 3.2, BACK_RAMP, base_w=2)
        c.blade(9.5, 12, -1.0, LIT_RAMP, base_w=2)
        for rx, h, cv in ((8.2, 17, -2.2), (11.5, 16, 2.4)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1)
            for k in range(5):
                c.put(tx, ty + k, SOR_L if k < 2 else (SOR_M if k < 4 else SOR_D))
                if k in (1, 3):
                    c.put(tx + (1 if cv > 0 else -1), ty + k, SOR_M)

    elif v == 38:
        # Coastal marram / Strandhafer clump (airy open sand-friendly root, wind-whipped!)
        c.blade(7.5, 14, -4.6, DUNE_DARK, base_w=1, droop=1.6)
        c.blade(12.2, 15, 4.8, DUNE_DARK, base_w=1, droop=1.6)
        c.blade(9.2, 17, -2.4, DUNE_RAMP, base_w=2, droop=1.8)
        c.blade(10.8, 16, 3.2, DUNE_RAMP, base_w=1, droop=1.6)
        c.blade(6.0, 10, -4.0, DUNE_RAMP, base_w=1)
        c.blade(13.6, 10, 4.2, DUNE_DARK, base_w=1)

    else:  # v == 39
        # Dry upland sheep's fescue (Schafschwingel — wiry fine olive-sage rocky slope tuft)
        c.root_tuck(5, 14, 0.7)
        c.blade(6.8, 10, -4.2, OLIVE_RAMP[:4], base_w=1)
        c.blade(13.0, 10, 4.2, OLIVE_RAMP[:4], base_w=1)
        c.blade(8.4, 12, -2.6, OLIVE_RAMP, base_w=1)
        c.blade(11.4, 12, 2.8, OLIVE_RAMP, base_w=1)
        c.blade(9.8, 13, 0.4, OLIVE_RAMP[1:], base_w=1)
        c.blade(5.5, 7, -3.4, O2 and OLIVE_RAMP[:4], base_w=1)
        c.blade(14.2, 7, 3.2, OLIVE_RAMP[:4], base_w=1)

    return c


# ==============================================================================
# TALL 24x36 ATLAS (24 HANDCRAFTED TALL-GRASS & BIOME SPECIES VARIANTS)
# ==============================================================================

def draw_tall_variant(v: int) -> Canvas:
    c = Canvas(TALL_W, TALL_H, TALL_FOOT_Y)

    # ================ ROW 0 (0..7): TALL WILD MEADOW GRASS & PRAIRIE HORSTS ================
    if v == 0:
        # Majestic asymmetric fountain horst of waist-high wild meadow grass (26-31 px!)
        c.root_tuck(5, 18, 1.2)
        c.blade(7.8, 24, -6.8, BACK_RAMP, base_w=3, droop=3.6, root_y_off=-1)
        c.blade(15.8, 26, 7.0, BACK_RAMP, base_w=3, droop=3.8, root_y_off=-1)
        c.blade(10.6, 29, -4.8, BACK_RAMP, base_w=2, droop=3.2)
        c.blade(13.8, 25, 5.2, MID_RAMP, base_w=2, droop=2.8)
        c.blade(6.5, 18, -5.8, OLIVE_RAMP[:4], base_w=2, droop=2.2, root_y_off=-2)
        c.blade(16.8, 19, 5.6, MID_RAMP, base_w=2, droop=2.0, root_y_off=-2)
        c.blade(9.6, 31, -3.6, SUN_RAMP, base_w=2, droop=3.8, dew=True)
        c.blade(13.2, 28, 4.4, LIT_RAMP, base_w=2, droop=3.4, dew=True, root_y_off=1)
        c.blade(11.6, 25, -1.2, SUN_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(8.6, 16, -4.5, LIT_RAMP, base_w=2, droop=1.4, root_y_off=-1)
        c.blade(14.8, 17, 4.2, LIT_RAMP, base_w=2, droop=1.5)

    elif v == 1:
        # Wind-swept right-flowing tall wild meadow wave (sweeping 29 px ribbons!)
        c.root_tuck(4, 17, 1.15)
        c.blade(6.8, 21, 4.8, BACK_RAMP, base_w=3, droop=2.6, root_y_off=-1)
        c.blade(10.8, 26, 8.0, BACK_RAMP, base_w=2, droop=3.8)
        c.blade(14.5, 22, 7.0, BACK_RAMP, base_w=2, droop=3.0, root_y_off=-1)
        c.blade(8.6, 30, 7.6, SUN_RAMP, base_w=2, droop=4.0, dew=True)
        c.blade(12.2, 27, 8.2, LIT_RAMP, base_w=2, droop=3.6, root_y_off=1)
        c.blade(5.8, 16, -2.4, LIT_RAMP, base_w=2, droop=1.2, root_y_off=-2)
        c.blade(10.0, 22, 6.4, SUN_RAMP, base_w=2, droop=2.4, root_y_off=1)
        c.blade(15.0, 15, 5.6, OLIVE_RAMP[:4], base_w=1, droop=1.4, root_y_off=-2)
        c.blade(8.0, 14, 3.6, MID_RAMP, base_w=2)

    elif v == 2:
        # Wind-swept left-flowing tall wild meadow wave (organic asymmetric sweep!)
        c.root_tuck(6, 19, 1.15)
        c.blade(16.6, 21, -4.6, BACK_RAMP, base_w=3, droop=2.6, root_y_off=-1)
        c.blade(12.8, 27, -8.0, BACK_RAMP, base_w=2, droop=3.8)
        c.blade(9.4, 22, -7.2, BACK_RAMP, base_w=2, droop=3.0, root_y_off=-1)
        c.blade(14.8, 30, -7.8, SUN_RAMP, base_w=2, droop=4.0, dew=True)
        c.blade(11.4, 26, -7.6, LIT_RAMP, base_w=2, droop=3.4, root_y_off=1)
        c.blade(17.5, 16, 2.6, MID_RAMP, base_w=2, droop=1.2, root_y_off=-2)
        c.blade(13.4, 21, -6.2, SUN_RAMP, base_w=2, droop=2.4, root_y_off=1)
        c.blade(8.4, 15, -5.2, OLIVE_RAMP[:4], base_w=1, droop=1.5, root_y_off=-2)

    elif v == 3:
        # Broad dense twin-horst tall grass thicket (irregular layered wall!)
        c.root_tuck(3, 20, 1.25)
        c.blade(6.2, 22, -5.4, BACK_RAMP, base_w=3, droop=2.8, root_y_off=-2)
        c.blade(17.6, 24, 5.2, BACK_RAMP, base_w=3, droop=2.8, root_y_off=-2)
        c.blade(9.2, 27, -3.2, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(14.8, 25, 3.0, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(7.8, 28, -4.2, SUN_RAMP, base_w=2, droop=3.2, dew=True)
        c.blade(16.0, 27, 4.6, LIT_RAMP, base_w=2, droop=3.0)
        c.blade(11.0, 25, -1.6, LIT_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(13.2, 23, 2.6, SUN_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(4.8, 15, -4.0, MID_RAMP, base_w=2, root_y_off=-2)
        c.blade(18.8, 16, 4.0, OLIVE_RAMP[:4], base_w=1, root_y_off=-2)
        c.blade(12.2, 16, -0.4, MID_RAMP, base_w=2, root_y_off=1)

    elif v == 4:
        # Tall sunlit meadow fescue with asymmetric feathered golden panicles (31 px!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.8, 21, -5.8, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(15.8, 23, 5.8, BACK_RAMP, base_w=2, droop=2.8, root_y_off=-1)
        c.blade(10.2, 25, -3.4, LIT_RAMP, base_w=2, droop=2.4)
        c.blade(13.8, 22, 3.8, MID_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(11.6, 20, -0.8, SUN_RAMP, base_w=2, root_y_off=1)
        for rx, h, cv, sd, ry in ((9.0, 29, -4.6, -1, 0), (12.2, 32, 1.8, 1, 0), (14.6, 26, 5.4, 1, -1)):
            tx, ty = c.blade(rx, h, cv, OLIVE_RAMP[:4], base_w=1, droop=1.8, root_y_off=ry)
            c.seed_panicle(tx, ty, sd, SEED_L, SEED_M, SEED_D, 5, DEW_DIM)

    elif v == 5:
        # Tall wild oat & nodding golden wheat-plume horst (asymmetric golden breeze sweep!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 22, -5.2, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.0, 20, 5.6, BACK_RAMP, base_w=2, droop=2.2, root_y_off=-2)
        c.blade(9.8, 25, -2.0, SUN_RAMP, base_w=2, droop=2.2)
        c.blade(13.6, 23, 3.8, LIT_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(8.6, 17, -4.0, OLIVE_RAMP, base_w=2, root_y_off=-1)
        for rx, h, cv, sd, ry in ((10.2, 32, -2.4, -1, 0), (13.4, 28, 5.2, 1, 0), (15.0, 24, 5.6, 1, -1)):
            tx, ty = c.blade(rx, h, cv, OLIVE_RAMP, base_w=1, droop=2.6, root_y_off=ry)
            for k in range(5):
                ox = sd * (1 if k >= 2 else 0)
                c.put(tx + ox, ty + k, SEED_L if k < 2 else SEED_M)
                c.put(tx + ox - sd, ty + k + 1, SEED_M if k < 3 else SEED_D)
            c.gput(tx, ty, GOLD_G)

    elif v == 6:
        # Tall silver-plumed feather-grass / Reitgras (staggered airy plumes leaning gently!)
        c.root_tuck(5, 18, 1.15)
        c.blade(8.0, 22, -5.8, BACK_RAMP, base_w=2, droop=2.8, root_y_off=-1)
        c.blade(15.6, 23, 5.4, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(11.2, 25, -2.2, LIT_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(13.8, 20, 3.6, SUN_RAMP, base_w=2, droop=1.8)
        for rx, h, cv, sd, ry in ((9.0, 32, -4.0, -1, 0), (12.6, 29, 2.8, 1, 1), (14.8, 25, 5.2, 1, -1)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1, droop=2.2, root_y_off=ry)
            c.put(tx, ty, SILV_L)
            c.put(tx + sd, ty, SILV_L)
            c.put(tx, ty + 1, SILV_L)
            c.put(tx + sd, ty + 1, SILV_M)
            c.put(tx - sd, ty + 2, SILV_L)
            c.put(tx, ty + 2, SILV_M)
            c.put(tx + sd, ty + 3, SILV_D)
            c.put(tx, ty + 3, SILV_M)
            c.put(tx, ty + 4, SILV_D)
            c.gput(tx, ty, DEW_HI)

    elif v == 7:
        # Wild tall brome & olive-tipped meadow horst (lush organic sweep)
        c.root_tuck(4, 19, 1.15)
        c.blade(6.6, 21, -5.8, BACK_RAMP, base_w=2, droop=2.8, root_y_off=-2)
        c.blade(17.0, 23, 5.6, BACK_RAMP, base_w=2, droop=2.8, root_y_off=-1)
        c.blade(9.8, 27, -3.8, OLIVE_RAMP, base_w=2, droop=3.2)
        c.blade(14.0, 26, 4.4, SUN_RAMP, base_w=2, droop=3.0, dew=True, root_y_off=1)
        c.blade(11.8, 24, -0.8, LIT_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(8.0, 17, -4.5, SUN_RAMP, base_w=2, droop=1.6, root_y_off=-1)
        c.blade(15.6, 16, 4.6, OLIVE_RAMP[:4], base_w=2, droop=1.5, root_y_off=-2)
        sx, sy = c.blade(11.2, 30, 2.8, OLIVE_RAMP, base_w=1, droop=2.0)
        c.seed_panicle(sx, sy, 1, SEED_L, SEED_M, SEED_D, 4)

    # ================ ROW 1 (8..15): TALL FLOWERING WILDMEADOW ================
    elif v == 8:
        # Tall Meadowsweet & grass horst (Mädesüß — staggered creamy foamy flower plumes!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 21, -5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.2, 23, 5.4, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(10.2, 24, -2.8, LIT_RAMP, base_w=2, droop=2.2)
        c.blade(13.8, 21, 3.2, MID_RAMP, base_w=2, droop=1.8, root_y_off=1)
        for rx, h, cv, ry in ((9.0, 30, -3.2, 0), (13.2, 26, 3.0, 1), (11.2, 24, 0.2, 0)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1, root_y_off=ry)
            c.put(tx, ty - 1, CREAM_L)
            c.put(tx - 1, ty, CREAM_L)
            c.put(tx, ty, CREAM_L)
            c.put(tx + 1, ty, CREAM_M)
            c.put(tx - 2, ty + 1, CREAM_L)
            c.put(tx - 1, ty + 1, CREAM_M)
            c.put(tx, ty + 1, CREAM_M)
            c.put(tx + 1, ty + 1, CREAM_D)
            c.put(tx, ty + 2, CREAM_D)
            c.gput(tx, ty, BLOOM_G)

    elif v == 9:
        # Tall Oxeye Daisies bobbing at staggered heights in waist-high grass!
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 22, -5.8, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(16.5, 23, 5.6, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(10.0, 25, -2.6, SUN_RAMP, base_w=2, droop=2.2)
        c.blade(13.8, 24, 3.4, LIT_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(11.8, 19, 0.5, MID_RAMP, base_w=2, root_y_off=1)
        d1x, d1y = c.blade(8.4, 26, -3.6, MID_RAMP, base_w=1)
        d2x, d2y = c.blade(14.2, 23, 3.8, MID_RAMP, base_w=1, root_y_off=-1)
        d3x, d3y = c.blade(11.2, 30, 0.8, LIT_RAMP, base_w=1)
        c.daisy_head(d1x, d1y, WHITE_L, WHITE_M, WHITE_D, GOLD_C, BLOOM_G)
        c.daisy_head(d2x, d2y, WHITE_L, WHITE_M, WHITE_D, GOLD_C)
        c.daisy_head(d3x, d3y, WHITE_L, WHITE_M, WHITE_D, GOLD_L, BLOOM_G)

    elif v == 10:
        # Tall Wild Meadow-Sage / Lupine spires (1 grand spire + 1 smaller leaning side spire!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 21, -5.4, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.4, 22, 5.4, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(11.6, 23, -1.5, LIT_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(9.2, 18, -3.4, SUN_RAMP, base_w=2)
        for rx, h, cv, sp_len in ((9.6, 31, -2.2, 7), (14.0, 25, 3.6, 5)):
            tx, ty = c.blade(rx, h, cv, MOSS_RAMP[:4], base_w=1)
            c.put(tx, ty - 1, LILAC_L)
            for k in range(sp_len):
                w = 1 if 1 <= k <= sp_len - 2 else 0
                c.put(tx, ty + k, LILAC_L if k < 2 else (LILAC_M if k < sp_len - 2 else LILAC_D))
                if w:
                    c.put(tx - 1, ty + k, LILAC_L if k % 2 == 0 else BLUE_M)
                    c.put(tx + 1, ty + k, LILAC_D if k % 2 == 0 else BLUE_D)
            c.gput(tx, ty + 1, LILAC_G)
            if sp_len >= 6:
                c.gput(tx, ty + 3, LILAC_G)

    elif v == 11:
        # Tall Meadow Knapweed & Clover-Rose wild grass (staggered heights!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 22, -5.6, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(16.4, 23, 5.6, BACK_RAMP, base_w=2, droop=2.6, root_y_off=-1)
        c.blade(11.4, 25, -1.6, SUN_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(14.0, 21, 3.2, LIT_RAMP, base_w=2, droop=2.0)
        for rx, h, cv, gl in ((8.4, 27, -3.4, ROSE_G), (12.4, 30, 1.4, ROSE_G), (14.8, 22, 4.4, None)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1)
            c.put(tx, ty - 1, ROSE_L)
            c.put(tx - 1, ty, ROSE_L)
            c.put(tx, ty, ROSE_M)
            c.put(tx + 1, ty, ROSE_D)
            c.put(tx, ty + 1, G2)
            if gl:
                c.gput(tx, ty, gl)

    elif v == 12:
        # Tall Goldenrod sunlit high grass (asymmetric arched golden sprays!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 21, -5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.4, 22, 5.4, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(10.0, 24, -2.5, LIT_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(14.0, 22, 2.8, SUN_RAMP, base_w=2, droop=2.0)
        for rx, h, cv, sd in ((9.2, 30, -3.8, -1), (13.4, 26, 4.4, 1)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1, droop=2.0)
            for k in range(5):
                c.put(tx, ty + k, GOLD_L if k < 2 else GOLD_C)
                c.put(tx + sd, ty + k, GOLD_L if k == 0 else (GOLD_C if k < 3 else GOLD_D))
                if k in (1, 2):
                    c.put(tx - sd, ty + k, GOLD_C)
            c.gput(tx, ty + 1, GOLD_G)

    elif v == 13:
        # Tall Wild Cow-Parsley / Queen Anne's Lace (airy lacy white umbels!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 21, -5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.4, 22, 5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(11.8, 24, 0.8, LIT_RAMP, base_w=2, droop=2.0, root_y_off=1)
        c.blade(9.4, 19, -3.0, SUN_RAMP, base_w=2)
        u1x, u1y = c.blade(8.6, 27, -3.4, MID_RAMP, base_w=1)
        u2x, u2y = c.blade(13.6, 30, 3.0, MID_RAMP, base_w=1)
        u3x, u3y = c.blade(11.0, 23, 0.4, MID_RAMP, base_w=1, root_y_off=1)
        c.umbel_lace(u1x, u1y, 3, WHITE_L, WHITE_M, WHITE_D, BLOOM_G)
        c.umbel_lace(u2x, u2y, 3, WHITE_L, CREAM_M, WHITE_D, BLOOM_G)
        c.umbel_lace(u3x, u3y, 2, WHITE_L, WHITE_M, WHITE_D)

    elif v == 14:
        # Tall Red-Sorrel & Wild Meadow Horst (staggered russet spires!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 22, -5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(16.4, 23, 5.6, BACK_RAMP, base_w=2, droop=2.4, root_y_off=-1)
        c.blade(10.4, 25, -2.4, LIT_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(13.8, 22, 3.2, OLIVE_RAMP, base_w=2, droop=2.0)
        for rx, h, cv, sd in ((9.0, 31, -3.4, -1), (13.2, 27, 3.2, 1)):
            tx, ty = c.blade(rx, h, cv, MID_RAMP, base_w=1)
            for k in range(7):
                c.put(tx, ty + k, SOR_L if k < 2 else (SOR_M if k < 5 else SOR_D))
                if k % 2 == 1:
                    c.put(tx + sd, ty + k, SOR_L if k < 3 else SOR_M)
                if k in (2, 4):
                    c.put(tx - sd, ty + k, SOR_D)

    elif v == 15:
        # Tall Dew-Pearl Moon-Grass (natural dark-emerald by day, delicate pearl-cyan dew pearls at night!)
        c.root_tuck(5, 18, 1.2)
        c.blade(7.8, 24, -6.6, MOSS_RAMP[:4], base_w=2, droop=3.2, root_y_off=-1)
        c.blade(16.0, 25, 6.2, MOSS_RAMP[:4], base_w=2, droop=3.2, root_y_off=-1)
        c.blade(10.0, 30, -3.8, MOSS_LIT, base_w=2, droop=3.6, dew=True, dew_col=PEARL_G)
        c.blade(13.8, 27, 4.2, MOSS_LIT, base_w=2, droop=3.2, dew=True, dew_col=PEARL_G, root_y_off=1)
        tx, ty = c.blade(11.8, 31, -1.2, REED_RAMP, base_w=2, droop=2.6, dew=True, dew_col=PEARL_G)
        c.put(tx, ty, R5)
        c.gput(tx, ty + 1, DEW_DIM)
        c.blade(7.0, 17, -4.8, MOSS_RAMP, base_w=2, droop=1.6, root_y_off=-2)
        c.blade(16.6, 18, 4.8, MOSS_RAMP, base_w=2, droop=1.6, root_y_off=-2)

    # ================ ROW 2 (16..23): BIOME TALL SPECIES (REEDS, CATTAILS, FERNS, STRANDHAFER) ================
    elif v == 16:
        # Tall Riparian Brook Reed Clump (asymmetric arching teal-green reeds!)
        c.root_tuck(5, 18, 1.2)
        c.blade(7.5, 26, -6.4, REED_DARK, base_w=3, droop=3.6, root_y_off=-1)
        c.blade(16.2, 27, 6.0, REED_DARK, base_w=3, droop=3.4, root_y_off=-1)
        c.blade(9.8, 31, -4.0, REED_RAMP, base_w=2, droop=3.4, dew=True)
        c.blade(14.0, 29, 4.4, REED_RAMP, base_w=2, droop=3.0, dew=True, root_y_off=1)
        c.blade(11.8, 28, -0.6, REED_RAMP, base_w=2, droop=2.2, root_y_off=1)
        c.blade(6.2, 19, -5.0, REED_RAMP[:4], base_w=2, droop=1.8, root_y_off=-2)
        c.blade(17.4, 18, 5.2, REED_DARK, base_w=2, droop=1.8, root_y_off=-2)

    elif v == 17:
        # Tall Cattails / Bulrushes (Rohrkolben — natural staggered heights + sweeping leaves!)
        c.root_tuck(5, 18, 1.2)
        c.blade(7.2, 25, -5.8, REED_DARK, base_w=3, droop=3.0, root_y_off=-1)
        c.blade(16.6, 24, 5.8, REED_DARK, base_w=3, droop=2.8, root_y_off=-1)
        c.blade(9.0, 29, -3.6, REED_RAMP, base_w=2, droop=2.6)
        c.blade(15.0, 27, 4.0, REED_RAMP, base_w=2, droop=2.6, root_y_off=1)
        for rx, h, cv, ry in ((10.2, 32, -2.0, 0), (13.8, 27, 2.4, 1)):
            tx, ty = c.blade(rx, h, cv, REED_RAMP[:4], base_w=1, root_y_off=ry)
            c.put(tx, ty - 1, SEED_M)
            c.put(tx, ty, SEED_D)
            for k in range(1, 7):
                c.put(tx - 1, ty + k, CAT_HI if k <= 2 else CAT_L)
                c.put(tx, ty + k, CAT_M)
                c.put(tx + 1, ty + k, CAT_D)
            c.gput(tx - 1, ty + 1, DEW_DIM)

    elif v == 18:
        # Tall Plumed Common Reed (Schilfrohr — staggered river tassels leaning in breeze!)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.2, 24, -5.6, REED_DARK, base_w=2, droop=2.8, root_y_off=-1)
        c.blade(16.4, 24, 5.6, REED_DARK, base_w=2, droop=2.8, root_y_off=-1)
        c.blade(10.0, 27, -2.6, REED_RAMP, base_w=2, droop=2.2)
        c.blade(14.0, 25, 3.0, REED_RAMP, base_w=2, droop=2.2, root_y_off=1)
        for rx, h, cv, sd in ((9.4, 33, -2.8, -1), (13.8, 29, 4.4, 1)):
            tx, ty = c.blade(rx, h, cv, REED_RAMP[:4], base_w=1, droop=1.8)
            c.put(tx, ty, SILV_L)
            c.put(tx + sd, ty + 1, SILV_L)
            c.put(tx, ty + 1, SILV_M)
            c.put(tx - sd, ty + 2, SILV_M)
            c.put(tx, ty + 2, SILV_M)
            c.put(tx + sd, ty + 2, CAT_HI)
            c.put(tx, ty + 3, CAT_L)
            c.put(tx + sd, ty + 3, CAT_M)
            c.put(tx, ty + 4, CAT_M)
            c.gput(tx, ty, DEW_DIM)

    elif v == 19:
        # Tall Yellow Flag Iris & Bank Sedge (asymmetric golden iris pair!)
        c.root_tuck(5, 18, 1.15)
        c.broad_leaf(8.0, 22, -5.4, 1.8, REED_DARK, root_y_off=-1)
        c.broad_leaf(15.8, 23, 5.2, 1.8, REED_DARK, root_y_off=-1)
        c.broad_leaf(10.4, 26, -2.6, 1.8, REED_RAMP)
        c.broad_leaf(13.6, 24, 3.0, 1.8, REED_RAMP, root_y_off=1)
        for rx, h, cv in ((9.4, 29, -2.4), (14.4, 25, 3.0)):
            tx, ty = c.blade(rx, h, cv, REED_RAMP[:4], base_w=1)
            c.put(tx, ty - 1, GOLD_L)
            c.put(tx - 1, ty, GOLD_L)
            c.put(tx, ty, GOLD_C)
            c.put(tx + 1, ty, GOLD_C)
            c.put(tx - 2, ty + 1, GOLD_C)
            c.put(tx, ty + 1, GOLD_D)
            c.put(tx + 2, ty + 1, GOLD_D)
            c.gput(tx, ty, GOLD_G)

    elif v == 20:
        # Tall Woodland Eagle-Fern (Großer Adlerfarn — tiered shaded forest fronds, 26-29 px!)
        c.root_tuck(6, 17, 1.2)
        c.fern_frond(10.6, 23, -9.4, MOSS_RAMP, y_slope=0.84, pinna_span=3, droop=4.4)
        c.fern_frond(13.4, 21, 9.0, MOSS_RAMP[:4], y_slope=0.82, pinna_span=3, droop=4.0)
        c.fern_frond(10.8, 27, -5.6, MOSS_LIT, y_slope=0.92, pinna_span=3, droop=3.2)
        c.fern_frond(13.2, 25, 6.0, MOSS_RAMP, y_slope=0.90, pinna_span=3, droop=3.2)
        c.fern_frond(12.0, 24, -1.2, SUN_RAMP, y_slope=0.96, pinna_span=2, droop=1.6)

    elif v == 21:
        # Tall Woodland Shaded Sedge & Clean Horsetail (Wald-Segge & Schachtelhalm)
        c.root_tuck(5, 18, 1.15)
        c.blade(7.5, 24, -6.8, MOSS_RAMP[:4], base_w=2, droop=3.8, root_y_off=-1)
        c.blade(16.2, 25, 6.6, MOSS_RAMP[:4], base_w=2, droop=3.8, root_y_off=-1)
        c.blade(9.6, 27, -4.0, MOSS_LIT, base_w=2, droop=3.4)
        c.blade(14.2, 25, 4.2, MOSS_RAMP, base_w=2, droop=3.0, root_y_off=1)
        # Clean spaced woodland horsetail stems (crisp V-whorls every 5 px, zero noise!)
        for rx, h, cv in ((11.2, 30, -1.4), (13.4, 26, 1.8)):
            tx, ty = c.blade(rx, h, cv, MOSS_LIT, base_w=1)
            for node_y in range(ty + 4, TALL_FOOT_Y - 7, 5):
                t_n = (TALL_FOOT_Y - node_y) / max(1, h)
                nx = int(round(rx + cv * (t_n ** 1.45)))
                c.put(nx, node_y, M1)
                c.put(nx - 1, node_y - 1, M4)
                c.put(nx - 2, node_y - 2, M5)
                c.put(nx + 1, node_y - 1, M3)
                c.put(nx + 2, node_y - 2, M2)
            c.gput(tx, ty, DEW_DIM)

    elif v == 22:
        # Tall Coastal Strandhafer / Sea-Oat Horst (staggered airy sand base, wind-whipped!)
        c.blade(7.8, 23, -6.8, DUNE_DARK, base_w=2, droop=3.4, root_y_off=-2)
        c.blade(15.8, 25, 6.6, DUNE_DARK, base_w=2, droop=3.4, root_y_off=-1)
        c.blade(10.0, 29, -4.2, DUNE_RAMP, base_w=2, droop=3.6)
        c.blade(13.8, 27, 4.6, DUNE_RAMP, base_w=2, droop=3.2, root_y_off=1)
        c.blade(6.5, 17, -5.6, DUNE_RAMP, base_w=1, droop=2.0, root_y_off=-2)
        c.blade(17.2, 18, 5.8, DUNE_DARK, base_w=1, droop=2.0, root_y_off=-2)
        for rx, h, cv in ((11.0, 31, -2.4), (13.4, 28, 3.4)):
            tx, ty = c.blade(rx, h, cv, DUNE_RAMP, base_w=1, droop=1.6)
            for k in range(5):
                c.put(tx, ty + k, D4 if k < 2 else D3)
                c.put(tx + 1, ty + k, D3 if k < 3 else D2)
            c.gput(tx, ty, DEW_DIM)

    else:  # v == 23
        # Tall Upland Steppe Feather-Grass (asymmetric sweeping olive-gold & silver plumes!)
        c.root_tuck(5, 18, 0.85)
        c.blade(7.8, 22, -6.8, OLIVE_RAMP[:4], base_w=1, droop=3.6, root_y_off=-1)
        c.blade(16.0, 24, 6.4, OLIVE_RAMP[:4], base_w=1, droop=3.6, root_y_off=-1)
        c.blade(9.6, 28, -4.8, OLIVE_RAMP, base_w=2, droop=4.0)
        c.blade(14.2, 26, 5.0, OLIVE_RAMP, base_w=2, droop=3.6, root_y_off=1)
        for rx, h, cv, sd in ((10.8, 32, -3.6, -1), (13.4, 28, 4.2, 1)):
            tx, ty = c.blade(rx, h, cv, OLIVE_RAMP[1:], base_w=1, droop=3.0)
            c.put(tx, ty, SILV_L)
            c.put(tx + sd, ty + 1, SILV_L)
            c.put(tx + sd * 2, ty + 2, SILV_M)
            c.put(tx, ty + 1, SILV_M)
            c.gput(tx, ty, DEW_DIM)

    return c


def pack_grid(variants: list[Canvas], cols: int, rows: int, cw: int, ch: int):
    w = cols * cw
    h = rows * ch
    lit = [[CLEAR] * w for _ in range(h)]
    glow = [[CLEAR] * w for _ in range(h)]
    for idx, var in enumerate(variants):
        ox = (idx % cols) * cw
        oy = (idx // cols) * ch
        for y in range(ch):
            for x in range(cw):
                lit[oy + y][ox + x] = var.px[y][x]
                glow[oy + y][ox + x] = var.glow[y][x]
    return w, h, lit, glow


def build_preview(variants: list[Canvas], cols: int, rows: int, cw: int, ch: int, scale: int = 4):
    """Zoomed inspection sheet: top half on day meadow backdrop, bottom half on night backdrop with additive glow."""
    pad = 4
    sw = cw + pad
    sh = ch + pad
    w = cols * sw + pad
    h = rows * sh * 2 + pad * 3
    bg_day = hexc("356b4d")
    bg_night = hexc("14192c")
    img = [[bg_day] * w for _ in range(h)]
    split_y = rows * sh + pad * 2
    for y in range(split_y, h):
        for x in range(w):
            img[y][x] = bg_night

    def blend(dst, src):
        sa = src[3] / 255.0
        if sa <= 0.0:
            return dst
        if sa >= 0.999:
            return src
        return (
            int(dst[0] * (1.0 - sa) + src[0] * sa),
            int(dst[1] * (1.0 - sa) + src[1] * sa),
            int(dst[2] * (1.0 - sa) + src[2] * sa),
            255,
        )

    for idx, var in enumerate(variants):
        gx = pad + (idx % cols) * sw
        gy = pad + (idx // cols) * sh
        ny = split_y + (idx // cols) * sh
        for y in range(ch):
            for x in range(cw):
                px = var.px[y][x]
                if px[3]:
                    img[gy + y][gx + x] = blend(img[gy + y][gx + x], px)
                    dim = (int(px[0] * 0.42), int(px[1] * 0.48), int(px[2] * 0.68), px[3])
                    img[ny + y][gx + x] = blend(img[ny + y][gx + x], dim)
                gl = var.glow[y][x]
                if gl[3]:
                    cur = img[ny + y][gx + x]
                    a = gl[3] / 255.0
                    img[ny + y][gx + x] = (
                        min(255, int(cur[0] + gl[0] * a)),
                        min(255, int(cur[1] + gl[1] * a)),
                        min(255, int(cur[2] + gl[2] * a)),
                        255,
                    )

    out = [[CLEAR] * (w * scale) for _ in range(h * scale)]
    for y in range(h):
        row_src = img[y]
        for sy in range(scale):
            row_dst = out[y * scale + sy]
            for x in range(w):
                px = row_src[x]
                base = x * scale
                for sx in range(scale):
                    row_dst[base + sx] = px
    return out


def main() -> None:
    tiles_dir = ROOT / "tiles"
    img_dir = ROOT.parent / "docs" / "img"

    std_vars = [draw_standard_variant(v) for v in range(STD_COUNT)]
    sw, sh, std_lit, std_glow = pack_grid(std_vars, STD_COLS, STD_ROWS, STD_W, STD_H)
    write_png(tiles_dir / "living_grass.png", sw, sh, std_lit)
    write_png(tiles_dir / "living_grass_glow.png", sw, sh, std_glow)
    std_prev = build_preview(std_vars, STD_COLS, STD_ROWS, STD_W, STD_H, scale=4)
    write_png(img_dir / "living_grass_atlas_4x.png", len(std_prev[0]), len(std_prev), std_prev)

    tall_vars = [draw_tall_variant(v) for v in range(TALL_COUNT)]
    tw, th, tall_lit, tall_glow = pack_grid(tall_vars, TALL_COLS, TALL_ROWS, TALL_W, TALL_H)
    write_png(tiles_dir / "living_grass_tall.png", tw, th, tall_lit)
    write_png(tiles_dir / "living_grass_tall_glow.png", tw, th, tall_glow)
    tall_prev = build_preview(tall_vars, TALL_COLS, TALL_ROWS, TALL_W, TALL_H, scale=4)
    write_png(img_dir / "living_grass_tall_atlas_4x.png", len(tall_prev[0]), len(tall_prev), tall_prev)

    print(
        f"Wrote {STD_COUNT} standard ({sw}x{sh}) + {TALL_COUNT} tall ({tw}x{th}) LivingGrass v4 variants "
        f"-> {tiles_dir / 'living_grass.png'} & {tiles_dir / 'living_grass_tall.png'}"
    )


if __name__ == "__main__":
    main()
