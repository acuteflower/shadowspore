#!/usr/bin/env python3
"""Handcrafted pixel-art botanical atlas for LivingGrass (24 variants of 16x20 px, feet at y=18).

Outputs:
  assets/tiles/living_grass.png         24x1 strip (384x20) of lush, multi-blade meadow tufts,
                                        sweeping sedge ribbons, velvety moss cushions, woven white
                                        & pale-blue micro-blossom clusters, ferns and seed plumes.
  assets/tiles/living_grass_glow.png    Matching unlit subtle night dew-glint & twilight blossom tips.
  docs/img/living_grass_atlas_4x.png    4x nearest-scaled inspection sheet on meadow & night backdrop.
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

CELL_W, CELL_H = 16, 20
COUNT = 24
FOOT_Y = 18

# Harmonized Shadowspore woodland-meadow grass palette (cool-teal roots -> velvety emerald -> warm sunlit tips)
ROOT_AO = (20, 42, 46, 220)   # soft translucent root grounding tuck (never harsh black)
SHADOW_BASE = (14, 30, 34, 105)
G0 = hexc("1b3a36")  # deep cool-teal interior crease / shadow blade
G1 = hexc("254e42")  # rich shadowed woodland moss
G2 = hexc("336b4e")  # mid-dark lush blade base
G3 = hexc("458657")  # core meadow emerald
G4 = hexc("60a360")  # sunlit green blade body
G5 = hexc("87c46f")  # bright sunlit upper curve
G6 = hexc("b3e08f")  # crisp top-left catchlight tip

# Cool-blue-green shade variants for ferns, moss pillows & deep undergrowth
M0 = hexc("193638")
M1 = hexc("244c47")
M2 = hexc("326955")
M3 = hexc("488862")
M4 = hexc("6eb074")

# Delicate seed plume / warm dry meadow accents
SEED_D = hexc("8f8e58")
SEED_M = hexc("beb978")
SEED_L = hexc("e6dea0")

# Micro-blossoms (inspired by lush woodland white chamomile/starwort & pale-blue forget-me-nots)
WHITE_D = hexc("a4a2b6")
WHITE_M = hexc("dfd9cc")
WHITE_L = hexc("faf5e8")
GOLD_C  = hexc("e6be58")
GOLD_L  = hexc("fff0a8")

BLUE_D  = hexc("5979ac")
BLUE_M  = hexc("8db8e6")
BLUE_L  = hexc("d0ebff")

LILAC_D = hexc("745aa2")
LILAC_M = hexc("b094dc")
LILAC_L = hexc("e4d4fa")

# Unlit night dew / faint twilight glimmer (delicate pearl-cyan & soft blossom hearts rendered on unlit night pass)
DEW_DIM = (152, 232, 224, 96)
DEW_HI  = (188, 246, 238, 132)
BLOOM_G = (182, 222, 255, 138)
LILAC_G = (204, 174, 252, 142)


class Canvas:
    def __init__(self) -> None:
        self.px = [[CLEAR] * CELL_W for _ in range(CELL_H)]
        self.glow = [[CLEAR] * CELL_W for _ in range(CELL_H)]

    def put(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            self.px[y][x] = c

    def gput(self, x: int, y: int, c: tuple[int, int, int, int]) -> None:
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            self.glow[y][x] = c

    def root_tuck(self, x0: int, x1: int) -> None:
        """Ultra-soft broken root contact shadow so tufts grow seamlessly out of the velvet turf (zero dark bar)."""
        mid = (x0 + x1) * 0.5
        half = max(1.5, (x1 - x0) * 0.5)
        for x in range(max(1, x0), min(CELL_W - 1, x1 + 1)):
            edge = abs(x - mid) / half
            if edge < 0.55 and (x % 2 == 0):
                self.put(x, FOOT_Y + 1, (18, 38, 40, 42))
            if edge < 0.80:
                a = 128 if edge < 0.45 else 78
                self.put(x, FOOT_Y, (24, 50, 48, a))

    def blade(
        self,
        rx: float,
        height: int,
        curve: float,
        ramp: list[tuple[int, int, int, int]],
        thick_base: bool = False,
        tip_droop: int = 0,
        dew: bool = False,
    ) -> tuple[int, int]:
        """Draws a graceful, organically curved, unbroken tapered pixel-art grass blade from (rx, FOOT_Y)."""
        prev_x = int(round(rx))
        last_x, last_y = prev_x, FOOT_Y
        for step in range(height):
            t = step / max(1, height - 1)
            # Smooth quadratic arch: rooted straight at bottom, gently sweeping outward near tips
            bx = int(round(rx + curve * (t ** 1.48)))
            by = FOOT_Y - step
            ci = min(len(ramp) - 1, int(t * (len(ramp) - 0.12)))
            # Keep curve 4-connected if horizontal step jumped > 1 px so blades never detach into floating dots
            if step > 0 and abs(bx - prev_x) > 1:
                bridge_x = prev_x + (1 if bx > prev_x else -1)
                self.put(bridge_x, by + 1, ramp[max(0, ci - 1)])
            self.put(bx, by, ramp[ci])
            # Optional 2px width near the lower third so blades feel lush & painterly
            if thick_base and step <= max(1, height // 3):
                side = -1 if curve < 0 else 1
                sh_i = max(0, ci - 1)
                self.put(bx + side, by, ramp[sh_i])
            prev_x = bx
            last_x, last_y = bx, by
        if tip_droop != 0:
            # Connected overhanging ribbon tip (adjacent horizontally, never floating)
            side = -1 if curve < 0 else 1
            self.put(last_x + side, last_y, ramp[-1])
            self.put(last_x + side, last_y + 1, ramp[max(0, len(ramp) - 2)])
            last_x += side
        if dew:
            self.gput(last_x, last_y, DEW_DIM)
        return last_x, last_y

    def micro_blossom(self, cx: int, cy: int, hi, mid, sh, core, glow_c=None) -> None:
        """Crisp 3x3 top-left-lit micro-blossom cluster (never a blocky square)."""
        self.put(cx, cy - 1, hi)
        self.put(cx - 1, cy, hi)
        self.put(cx + 1, cy, sh)
        self.put(cx, cy + 1, sh)
        self.put(cx, cy, core)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)

    def mini_bud(self, cx: int, cy: int, hi, sh, glow_c=None) -> None:
        """Tiny 2px directional flower speck nestled among micro-blossoms."""
        self.put(cx, cy, hi)
        self.put(cx + 1, cy, sh)
        if glow_c is not None:
            self.gput(cx, cy, glow_c)


# Four distinct shade tiers for front/back layering inside each tuft
BACK_RAMP = [G0, G1, G2, G3]
MID_RAMP  = [G1, G2, G3, G4]
LIT_RAMP  = [G1, G2, G3, G4, G5]
SUN_RAMP  = [G2, G3, G4, G5, G6]
MOSS_RAMP = [M0, M1, M2, M3, M4]


def draw_variant(v: int) -> Canvas:
    c = Canvas()

    # ---------------- 0..7: LUSH SHORT & MID LIVING GRASS TUFTS ----------------
    if v == 0:
        # Balanced classic 6-blade lush meadow tuft fanning naturally
        c.root_tuck(4, 11)
        c.blade(6.0, 9, -2.6, BACK_RAMP, thick_base=True)
        c.blade(9.5, 8, 2.8, BACK_RAMP, thick_base=True)
        c.blade(7.5, 10, 0.8, MID_RAMP, thick_base=True)
        c.blade(5.0, 7, -3.2, LIT_RAMP, thick_base=False)
        c.blade(8.5, 11, -1.2, SUN_RAMP, thick_base=True, dew=True)
        c.blade(10.5, 7, 3.0, MID_RAMP, thick_base=False)

    elif v == 1:
        # Low, dense velvety clump leaning slightly right with soft tips
        c.root_tuck(3, 12)
        c.blade(5.0, 7, -2.0, BACK_RAMP, thick_base=True)
        c.blade(10.0, 8, 3.2, BACK_RAMP, thick_base=True)
        c.blade(6.5, 9, 1.4, LIT_RAMP, thick_base=True)
        c.blade(8.5, 8, 2.6, LIT_RAMP, thick_base=True)
        c.blade(4.2, 6, -2.4, SUN_RAMP)
        c.blade(7.5, 7, -0.5, SUN_RAMP)
        c.blade(11.0, 6, 2.8, MID_RAMP)

    elif v == 2:
        # Swept left-leaning breeze tuft with rich inner shadow
        c.root_tuck(4, 11)
        c.blade(9.0, 10, -1.6, BACK_RAMP, thick_base=True)
        c.blade(10.5, 8, 1.6, BACK_RAMP, thick_base=True)
        c.blade(7.5, 11, -3.4, LIT_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(6.0, 9, -3.8, SUN_RAMP, thick_base=True)
        c.blade(8.5, 8, -0.6, MID_RAMP, thick_base=True)
        c.blade(5.0, 6, -2.5, LIT_RAMP)

    elif v == 3:
        # Compact emerald crown tuft (fills the mid-turf thickly without height spikes)
        c.root_tuck(4, 11)
        c.blade(5.5, 6, -2.4, BACK_RAMP, thick_base=True)
        c.blade(10.0, 6, 2.4, BACK_RAMP, thick_base=True)
        c.blade(7.0, 8, -1.6, SUN_RAMP, thick_base=True)
        c.blade(8.5, 8, 1.5, LIT_RAMP, thick_base=True)
        c.blade(6.0, 6, -3.0, LIT_RAMP)
        c.blade(9.5, 5, 2.8, MID_RAMP)

    elif v == 4:
        # Wide twin-cluster tuft (looks like two interlocked tufts growing side by side)
        c.root_tuck(2, 13)
        c.blade(4.5, 8, -2.5, BACK_RAMP, thick_base=True)
        c.blade(11.0, 9, 2.8, BACK_RAMP, thick_base=True)
        c.blade(5.5, 9, -1.0, SUN_RAMP, thick_base=True)
        c.blade(7.0, 7, 1.4, MID_RAMP)
        c.blade(9.5, 10, -0.8, LIT_RAMP, thick_base=True, dew=True)
        c.blade(10.5, 7, 2.4, MID_RAMP)
        c.blade(3.5, 6, -2.2, LIT_RAMP)

    elif v == 5:
        # Cool-toned shady emerald tuft for mossy pockets
        c.root_tuck(4, 11)
        c.blade(6.0, 9, -2.4, MOSS_RAMP[:4], thick_base=True)
        c.blade(9.5, 9, 2.4, MOSS_RAMP[:4], thick_base=True)
        c.blade(7.5, 10, -0.8, MOSS_RAMP, thick_base=True)
        c.blade(8.5, 8, 1.8, MOSS_RAMP[1:], thick_base=True)
        c.blade(5.0, 6, -2.6, MOSS_RAMP[1:])

    elif v == 6:
        # Sun-tipped meadow crest tuft curving gracefully right
        c.root_tuck(4, 11)
        c.blade(5.5, 8, 0.8, BACK_RAMP, thick_base=True)
        c.blade(9.5, 9, 3.6, BACK_RAMP, thick_base=True)
        c.blade(7.0, 11, 2.8, SUN_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(8.2, 9, 3.8, LIT_RAMP, thick_base=True)
        c.blade(5.0, 7, -1.8, LIT_RAMP)
        c.blade(10.2, 6, 3.0, MID_RAMP)

    elif v == 7:
        # Soft low velvet turf blades (bridging short moss to taller grass)
        c.root_tuck(3, 12)
        c.blade(4.5, 5, -1.8, BACK_RAMP, thick_base=True)
        c.blade(7.5, 6, -0.4, BACK_RAMP, thick_base=True)
        c.blade(10.5, 5, 2.0, BACK_RAMP, thick_base=True)
        c.blade(5.8, 7, -1.8, SUN_RAMP, thick_base=True)
        c.blade(9.0, 7, 1.6, LIT_RAMP, thick_base=True)
        c.blade(7.2, 5, 0.8, MID_RAMP)

    # ---------------- 8..13: LUSH TALL MEADOW GRASS & ARCHING SEDGE RIBBONS ----------------
    elif v == 8:
        # Tall sweeping fountain tuft (14 px tall, iconic ankle-wrapping grass!)
        c.root_tuck(4, 11)
        c.blade(6.5, 13, -4.2, BACK_RAMP, thick_base=True, tip_droop=1)
        c.blade(9.5, 13, 4.0, BACK_RAMP, thick_base=True, tip_droop=1)
        c.blade(8.0, 14, 1.4, MID_RAMP, thick_base=True)
        c.blade(7.2, 15, -2.0, SUN_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(5.2, 10, -4.2, LIT_RAMP, thick_base=True)
        c.blade(10.2, 10, 3.8, MID_RAMP, thick_base=True)
        c.blade(8.2, 9, 2.2, LIT_RAMP)

    elif v == 9:
        # Tall wind-swept right-arching ribbon grass
        c.root_tuck(3, 11)
        c.blade(5.5, 12, 2.2, BACK_RAMP, thick_base=True)
        c.blade(8.5, 13, 4.8, BACK_RAMP, thick_base=True, tip_droop=1)
        c.blade(6.5, 15, 4.4, SUN_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(4.5, 10, -1.8, LIT_RAMP, thick_base=True)
        c.blade(7.8, 11, 4.5, LIT_RAMP, thick_base=True)
        c.blade(9.8, 8, 3.5, MID_RAMP)

    elif v == 10:
        # Tall wind-swept left-arching ribbon grass
        c.root_tuck(4, 12)
        c.blade(10.0, 12, -2.0, BACK_RAMP, thick_base=True)
        c.blade(7.5, 13, -4.6, BACK_RAMP, thick_base=True, tip_droop=1)
        c.blade(9.0, 15, -4.2, SUN_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(11.0, 10, 2.0, MID_RAMP, thick_base=True)
        c.blade(8.0, 11, -4.2, LIT_RAMP, thick_base=True)
        c.blade(6.0, 8, -3.4, LIT_RAMP)

    elif v == 11:
        # Dense overlapping sedge fan (full mid-height lushness)
        c.root_tuck(3, 12)
        c.blade(4.5, 10, -3.2, BACK_RAMP, thick_base=True)
        c.blade(11.0, 10, 3.2, BACK_RAMP, thick_base=True)
        c.blade(7.5, 12, -2.6, LIT_RAMP, thick_base=True)
        c.blade(8.5, 12, 2.8, MID_RAMP, thick_base=True)
        c.blade(6.2, 13, -1.2, SUN_RAMP, thick_base=True, dew=True)
        c.blade(9.5, 9, 3.6, LIT_RAMP)
        c.blade(5.5, 7, -3.0, SUN_RAMP)

    elif v == 12:
        # Cool deep-emerald tall woodland sedge
        c.root_tuck(4, 11)
        c.blade(6.0, 12, -3.6, MOSS_RAMP[:4], thick_base=True, tip_droop=1)
        c.blade(9.8, 12, 3.8, MOSS_RAMP[:4], thick_base=True, tip_droop=1)
        c.blade(7.8, 14, -1.0, MOSS_RAMP, thick_base=True, dew=True)
        c.blade(8.8, 11, 2.6, MOSS_RAMP[1:], thick_base=True)
        c.blade(5.2, 8, -3.0, MOSS_RAMP[1:])

    elif v == 13:
        # Wild tall sunlit meadow crest with golden tips
        c.root_tuck(4, 11)
        c.blade(6.0, 11, -3.2, BACK_RAMP, thick_base=True)
        c.blade(9.8, 11, 3.2, BACK_RAMP, thick_base=True)
        c.blade(7.2, 14, -2.2, SUN_RAMP, thick_base=True, tip_droop=1)
        c.blade(8.8, 13, 2.0, LIT_RAMP, thick_base=True, tip_droop=1, dew=True)
        c.blade(7.8, 10, 0.2, SUN_RAMP, thick_base=True)

    # ---------------- 14..15: VELVETY MOSS PILLOWS & FINE CLOVER MATS ----------------
    elif v == 14:
        # Plump mossy velvet pillow with 3 delicate shoots
        c.root_tuck(2, 13)
        for mx, my, rx, ry in ((5.5, 16.5, 3.8, 2.3), (10.2, 16.8, 3.4, 2.1), (8.0, 15.8, 3.8, 2.4)):
            for y in range(12, 19):
                for x in range(1, 15):
                    d = ((x - mx) / rx) ** 2 + ((y - my) / ry) ** 2
                    if d <= 1.0:
                        lit = -0.45 * (x - mx) / rx - 0.85 * (y - my) / ry
                        col = G5 if lit > 0.65 else (G4 if lit > 0.2 else (G3 if lit > -0.25 else (G2 if lit > -0.65 else G1)))
                        c.put(x, y, col)
        c.blade(4.0, 6, -1.5, SUN_RAMP)
        c.blade(9.0, 7, 1.2, LIT_RAMP)
        c.blade(11.5, 5, 1.8, MID_RAMP)

    elif v == 15:
        # Fine low shamrock / woodland clover cluster (3-leaf pads, delicate scale!)
        c.root_tuck(3, 12)
        c.blade(5.0, 6, -2.0, BACK_RAMP)
        c.blade(10.5, 6, 2.2, BACK_RAMP)
        for lx, ly, col_hi, col_mid, col_sh in (
            (5, 15, G5, G4, G2),
            (10, 15, G4, G3, G1),
            (7, 13, G6, G4, G2),
            (11, 13, G5, G3, G1),
            (4, 12, G5, G4, G2),
        ):
            c.put(lx, ly - 1, col_hi)
            c.put(lx - 1, ly, col_mid)
            c.put(lx + 1, ly, col_sh)
            c.put(lx, ly, col_mid)
            c.put(lx, ly + 1, col_sh)

    # ---------------- 16..18: WOVEN WHITE MICRO-BLOSSOM CUSHIONS (Reference Image DNA!) ----------------
    elif v == 16:
        # Dense starwort / chamomile white flower cushion nestled in fine blades
        c.root_tuck(2, 13)
        c.blade(4.5, 9, -2.8, BACK_RAMP, thick_base=True)
        c.blade(11.0, 9, 2.8, BACK_RAMP, thick_base=True)
        c.blade(7.5, 10, -0.8, MID_RAMP, thick_base=True)
        c.blade(9.0, 9, 1.6, LIT_RAMP, thick_base=True)
        c.blade(5.5, 7, -1.6, LIT_RAMP)
        c.micro_blossom(5, 11, WHITE_L, WHITE_M, WHITE_D, GOLD_C, BLOOM_G)
        c.micro_blossom(10, 10, WHITE_L, WHITE_M, WHITE_D, GOLD_C)
        c.micro_blossom(7, 8, WHITE_L, WHITE_M, WHITE_D, GOLD_L, BLOOM_G)
        c.mini_bud(3, 13, WHITE_L, WHITE_D)
        c.mini_bud(12, 12, WHITE_M, WHITE_D)
        c.mini_bud(8, 13, WHITE_L, WHITE_M)

    elif v == 17:
        # Low sprawling carpet of tiny white woodland blossoms (tight weaving!)
        c.root_tuck(2, 13)
        for bx, bh, bc in ((4, 6, -2.0), (7, 7, -0.5), (10, 7, 1.5), (12, 5, 2.2), (6, 5, -1.2)):
            c.blade(float(bx), bh, bc, MID_RAMP if bx % 2 else LIT_RAMP, thick_base=True)
        for cx, cy in ((4, 13), (8, 12), (11, 13), (6, 10), (10, 10)):
            c.mini_bud(cx, cy, WHITE_L, WHITE_M, BLOOM_G if cx == 6 else None)
            c.put(cx, cy + 1, WHITE_D)
        c.micro_blossom(7, 14, WHITE_L, WHITE_M, WHITE_D, GOLD_C)

    elif v == 18:
        # Delicate white + blush-lilac woodland meadow mix
        c.root_tuck(3, 12)
        c.blade(5.0, 10, -2.6, BACK_RAMP, thick_base=True)
        c.blade(10.2, 10, 2.6, BACK_RAMP, thick_base=True)
        c.blade(7.5, 11, 0.5, LIT_RAMP, thick_base=True)
        c.micro_blossom(6, 9, WHITE_L, WHITE_M, WHITE_D, GOLD_C, BLOOM_G)
        c.micro_blossom(10, 11, LILAC_L, LILAC_M, LILAC_D, GOLD_L, LILAC_G)
        c.mini_bud(4, 12, LILAC_L, LILAC_D)
        c.mini_bud(9, 7, WHITE_L, WHITE_D)

    # ---------------- 19..20: PALE-BLUE FORGET-ME-NOT & TWILIGHT POCKETS ----------------
    elif v == 19:
        # Dense pale-blue forget-me-not pocket (just like the lower-left edge of the reference!)
        c.root_tuck(2, 13)
        c.blade(4.5, 8, -2.4, MOSS_RAMP[:4], thick_base=True)
        c.blade(11.0, 8, 2.4, MOSS_RAMP[:4], thick_base=True)
        c.blade(7.5, 9, -0.6, MOSS_RAMP, thick_base=True)
        c.blade(9.2, 8, 1.8, LIT_RAMP, thick_base=True)
        c.micro_blossom(5, 11, BLUE_L, BLUE_M, BLUE_D, GOLD_L, BLOOM_G)
        c.micro_blossom(10, 11, BLUE_L, BLUE_M, BLUE_D, GOLD_L)
        c.micro_blossom(8, 9, BLUE_L, BLUE_M, BLUE_D, WHITE_L, BLOOM_G)
        c.mini_bud(3, 13, BLUE_L, BLUE_D)
        c.mini_bud(11, 14, BLUE_M, BLUE_D)

    elif v == 20:
        # Soft twilight-lilac & sky-blue low floral nest
        c.root_tuck(3, 12)
        c.blade(5.5, 8, -2.2, BACK_RAMP, thick_base=True)
        c.blade(10.0, 9, 2.2, MID_RAMP, thick_base=True)
        c.blade(7.8, 10, 0.2, LIT_RAMP, thick_base=True)
        c.micro_blossom(7, 10, LILAC_L, LILAC_M, LILAC_D, GOLD_L, LILAC_G)
        c.micro_blossom(11, 12, BLUE_L, BLUE_M, BLUE_D, WHITE_L)
        c.mini_bud(4, 12, BLUE_L, BLUE_D)
        c.mini_bud(9, 8, LILAC_L, LILAC_M)

    # ---------------- 21..23: WOODLAND FERNS & SWAYING SEED PLUMES ----------------
    elif v == 21:
        # Graceful outward-sweeping forest fern rosette (organic arched pinnae, no ladder look!)
        c.root_tuck(5, 10)
        fronds = [
            (7.5, 10, -5.8, MOSS_RAMP, -1),
            (8.5, 10, 5.8, MOSS_RAMP[:4], 1),
            (7.2, 12, -3.4, SUN_RAMP, -1),
            (8.6, 11, 3.6, LIT_RAMP, 1),
        ]
        for rx, h, curve, ramp, side in fronds:
            for step in range(h):
                t = step / max(1, h - 1)
                bx = int(round(rx + curve * (t ** 1.15)))
                by = FOOT_Y - int(round(step * (0.82 if abs(curve) > 4.5 else 0.94)))
                ci = min(len(ramp) - 1, int(t * (len(ramp) - 0.1)))
                c.put(bx, by, ramp[ci])
                if 2 <= step <= h - 2:
                    c.put(bx, by - 1, ramp[min(len(ramp) - 1, ci + 1)])
                    if step % 2 == 1:
                        c.put(bx + side, by, ramp[max(0, ci - 1)])

    elif v == 22:
        # Low lush spreading bracken fern
        c.root_tuck(4, 11)
        fronds = [
            (6.5, 8, -5.4, MOSS_RAMP[1:], -1),
            (9.5, 8, 5.4, MOSS_RAMP[:4], 1),
            (7.6, 9, -2.0, LIT_RAMP, -1),
            (8.4, 8, 2.5, MID_RAMP, 1),
        ]
        for rx, h, curve, ramp, side in fronds:
            for step in range(h):
                t = step / max(1, h - 1)
                bx = int(round(rx + curve * (t ** 1.1)))
                by = FOOT_Y - int(round(step * 0.85))
                ci = min(len(ramp) - 1, int(t * (len(ramp) - 0.1)))
                c.put(bx, by, ramp[ci])
                if 1 <= step <= h - 2:
                    c.put(bx + side, by - 1, ramp[min(len(ramp) - 1, ci + 1)])

    else:  # v == 23
        # Tall slender meadow grass with golden nodding seed plumes (catches wind & golden hour!)
        c.root_tuck(4, 11)
        c.blade(5.5, 10, -2.6, BACK_RAMP, thick_base=True)
        c.blade(10.0, 9, 2.8, BACK_RAMP, thick_base=True)
        c.blade(6.8, 12, -1.4, LIT_RAMP, thick_base=True)
        sx1, sy1 = c.blade(8.2, 15, 2.4, MID_RAMP, thick_base=False)
        sx2, sy2 = c.blade(6.2, 14, -2.8, LIT_RAMP, thick_base=False)
        # Sculpted golden-wheat seed plumes at the arching tips
        for sx, sy, sdir in ((sx1, sy1, 1), (sx2, sy2, -1)):
            c.put(sx, sy, SEED_L)
            c.put(sx + sdir, sy + 1, SEED_L)
            c.put(sx, sy + 1, SEED_M)
            c.put(sx - sdir, sy + 2, SEED_M)
            c.put(sx, sy + 2, SEED_D)
            c.put(sx + sdir, sy + 3, SEED_D)
            c.gput(sx, sy, DEW_DIM)

    return c


def build_preview(variants: list[Canvas]) -> list[list[tuple[int, int, int, int]]]:
    """4x zoomed inspection sheet: top row day meadow bg, bottom row twilight/night with glow."""
    cols = 8
    rows = 3
    pad = 4
    cw = CELL_W + pad
    ch = CELL_H + pad
    w = cols * cw + pad
    h = rows * ch * 2 + pad * 3
    bg_day = hexc("356b4d")
    bg_night = hexc("14192c")
    img = [[bg_day] * w for _ in range(h)]
    split_y = rows * ch + pad * 2
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
        gx = pad + (idx % cols) * cw
        gy = pad + (idx // cols) * ch
        ny = split_y + (idx // cols) * ch
        for y in range(CELL_H):
            for x in range(CELL_W):
                px = var.px[y][x]
                if px[3]:
                    img[gy + y][gx + x] = blend(img[gy + y][gx + x], px)
                    # Night-tinted copy + additive glow
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

    # Nearest 4x scale
    scale = 4
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
    variants = [draw_variant(v) for v in range(COUNT)]
    lit = [[CLEAR] * (CELL_W * COUNT) for _ in range(CELL_H)]
    glow = [[CLEAR] * (CELL_W * COUNT) for _ in range(CELL_H)]
    for v, var in enumerate(variants):
        ox = v * CELL_W
        for y in range(CELL_H):
            for x in range(CELL_W):
                lit[y][ox + x] = var.px[y][x]
                glow[y][ox + x] = var.glow[y][x]
    tiles_dir = ROOT / "tiles"
    write_png(tiles_dir / "living_grass.png", CELL_W * COUNT, CELL_H, lit)
    write_png(tiles_dir / "living_grass_glow.png", CELL_W * COUNT, CELL_H, glow)
    preview = build_preview(variants)
    preview_path = ROOT.parent / "docs" / "img" / "living_grass_atlas_4x.png"
    write_png(preview_path, len(preview[0]), len(preview), preview)
    print(f"Wrote {COUNT} living grass variants -> {tiles_dir / 'living_grass.png'} and {preview_path}")


if __name__ == "__main__":
    main()
