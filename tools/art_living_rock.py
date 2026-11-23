#!/usr/bin/env python3
"""Handcrafted 2.0 Geological Pixel-Art Generator for Shadowspore's LivingRock ('Glimmtal-Fels'):
  1. assets/tiles/rock_ground_details.png (384x20, 16 cells of 24x20 px) + *_glow.png
  2. assets/props/valley_stone/{s0_a..s4_b}.png (15-col modular rig strips) + *_glow.png
  3. data/valley_stone_rig.json
  4. docs/img/valley_stone_sheet.png (2x QA showcase + 3x detail zoom strip, Day + Night)

Visual DNA (matching oak_botany.py, silver_birch, and ancient_stones.py):
  - Harmonized Glimmtal World Palette: cool woodland-teal/slate shadows (#1a2630 -> #273844 -> #3b4f5c)
    locked into Shadowspore's meadow/forest shadow ramp (#22483c), shifting into warm-weathered
    limestone, moss-slate, and feldspar-greywacke sunlit stone (#788a8e -> #9aa8a6 -> #bcc6be -> #dce2d6).
  - Organic Weathered 3D Rock Volumes: compound rounded-craggy boulders, tabular sedimentary benches,
    undercut overhangs, and frost-split clefts (ZERO low-poly 45-deg origami pyramids!).
  - Multi-Scale Craggy Stone Relief: 4-8 px warped interlocking stone plates, recessed weathered fissures
    with 1px sunlit bevels, stepped strata ledges, concave spall pockets, rare hairline quartz veins,
    and ordered Bayer 4x4 + 2px mineral cluster texture (ZERO flat bucket-fill polygons, ZERO noisy static!).
  - Ground-Sunk Bases & Botanical Befall: open/softened basal toes with humus, turf blades & root-moss,
    velvety 3D cushion moss with hanging fringes, lacy crustose lichen rosettes, woody creeping rock-ivy,
    pinnate crevice ferns, Sempervivum rosettes, and shaded bracket fungi with subtle night spore glimmer.
  - Strictly zero #000000 pixels anywhere; stdlib + gen_art.py only.
"""
from __future__ import annotations

import json
import math
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

OUT_ROCKS = ROOT / "props" / "valley_stone"
OUT_DETAILS = ROOT / "tiles" / "rock_ground_details.png"
OUT_DETAILS_GLOW = ROOT / "tiles" / "rock_ground_details_glow.png"
OUT_RIG = ROOT.parent / "data" / "valley_stone_rig.json"
OUT_SHEET = ROOT.parent / "docs" / "img" / "valley_stone_sheet.png"

# ---------------------------------------------------------------------------
# Harmonized Glimmtal Palettes (zero #000000!)
# Shadows lock into Shadowspore's cool woodland-teal/slate shadow family (#1a2630..#3b4f5c)
# ---------------------------------------------------------------------------
OUT_SHADE = hexc("17222c")      # Deep cool woodland-slate outline on shadowed sides
OUT_TOP_STONE = hexc("2c3e47")  # Soft selective outline on sunlit NW stone edges
OUT_TOP_MOSS = hexc("1f3c31")   # Soft selective outline on sunlit moss/flora edges
OUT_GROUND_TOP = hexc("354750") # Extra-soft sel-out for flush ground scatter stones
OUT_GROUND_BOT = hexc("21303a")

# 8-step Weathered Glimmtal Limestone (primary sunlit highland/glade stone)
RAMP_LIMESTONE = [
    hexc("192530"),  # 0: Deep cleft / undercut crevice
    hexc("263643"),  # 1: Core cool-teal slate shadow
    hexc("3a4d5a"),  # 2: Shaded rock plane
    hexc("556872"),  # 3: Cool weathered shadow-mid
    hexc("75878c"),  # 4: Calm weathered mid stone
    hexc("96a5a3"),  # 5: Sunlit limestone plane
    hexc("b8c3bb"),  # 6: Warm sunlit upper ledge
    hexc("dae0d4"),  # 7: Crisp 1px NW mineral catchlight
]

# 8-step Woodland Moss-Slate / Greywacke (cooler blue-green slate sub-boulders)
RAMP_SLATE = [
    hexc("18232f"),
    hexc("243444"),
    hexc("374a5b"),
    hexc("506475"),
    hexc("6e8390"),
    hexc("8fa2ab"),
    hexc("b2c1c4"),
    hexc("d4dfdd"),
]

# 8-step Warm Feldspar / Travertine Erratic (subtle warm parchment-grey stone variety)
RAMP_FELDSPAR = [
    hexc("1d2630"),
    hexc("2d3943"),
    hexc("445159"),
    hexc("616d71"),
    hexc("828c89"),
    hexc("a4aba2"),
    hexc("c4c8ba"),
    hexc("e2e3d3"),
]

RAMPS = [RAMP_LIMESTONE, RAMP_SLATE, RAMP_FELDSPAR]

# 8-step Freshly Split Interior Greywacke/Flint (exposed on `chipped` col 2 & `rubble` col 5)
RAMP_FRESH = [
    hexc("1a2533"),
    hexc("2b3b4d"),
    hexc("415468"),
    hexc("5d7285"),
    hexc("7d92a2"),
    hexc("a1b3bf"),
    hexc("c4d2d9"),
    hexc("e1ebee"),
]

QUARTZ_VEIN = [hexc("8ea1a8"), hexc("bdd0d4"), hexc("e4efe9")]

# Botanical Befall Palettes (locked directly to oak_botany.py & LivingGrass!)
MOSS = [
    hexc("19362f"),  # 0: Deep moss crevice / overhang shadow
    hexc("265240"),  # 1: Shaded cushion moss
    hexc("3b7652"),  # 2: Rich woodland moss
    hexc("599b60"),  # 3: Sunlit velvety moss
    hexc("83c272"),  # 4: Crisp NW moss highlight
    hexc("addc88"),  # 5: Rare spore-tip / dew highlight
]

# Subtle, realistic crustose rock-lichen rosettes (NO bright orange fried-egg blobs!)
LICHEN_SAGE = [hexc("4e6b62"), hexc("759689"), hexc("a2bfb0"), hexc("c7ddd0")]
LICHEN_OCHRE = [hexc("5c4f34"), hexc("857349"), hexc("ab9663"), hexc("cab782")]

IVY_STEM = [hexc("2c222b"), hexc("473842")]
IVY_LEAF = [hexc("1a382f"), hexc("2b5946"), hexc("468257"), hexc("6bab68"), hexc("94cf7e")]

FERN = [hexc("1b3b31"), hexc("2c5e47"), hexc("468558"), hexc("6cb068"), hexc("9ad47e")]
HOUSELEEK = [hexc("23443b"), hexc("376455"), hexc("588b70"), hexc("82b38a")]
HOUSELEEK_TIP = hexc("7d4852")
SEDGE = [hexc("4f4935"), hexc("756a49"), hexc("9c8d63"), hexc("bfb080")]
SOIL_CRUMB = [hexc("2d2926"), hexc("453d35"), hexc("5e5347")]

FUNGI_DAY = [hexc("282238"), hexc("3d3552"), hexc("5c5275"), hexc("7d7496"), hexc("4c8b86")]
GLOW_TEAL_DIM = hexc("2a8c94")
GLOW_TEAL_MID = hexc("3cc0c6")
GLOW_TEAL_HI = hexc("78f4e6")

CONTACT_RGB = (18, 34, 36)
SUN = (-0.62, -0.55, 0.56)
BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)


def blank(w: int, h: int) -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def clampi(v: int, lo: int, hi: int) -> int:
    return lo if v < lo else (hi if v > hi else v)


def clampf(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def put(px: list[list[tuple[int, int, int, int]]], x: int, y: int, col: tuple[int, int, int, int]) -> None:
    if 0 <= y < len(px) and 0 <= x < len(px[0]) and col[3] > 0:
        if col[0] == 0 and col[1] == 0 and col[2] == 0:
            col = (23, 34, 44, col[3])
        px[y][x] = col


def put_shadow(px: list[list[tuple[int, int, int, int]]], x: int, y: int, alpha: int) -> None:
    if 0 <= y < len(px) and 0 <= x < len(px[0]) and alpha > 0:
        a = clampi(alpha, 1, 115)
        cur = px[y][x]
        if cur[3] == 0:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], a)
        elif cur[:3] == CONTACT_RGB:
            px[y][x] = (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], max(cur[3], a))


def blend_over(dst: tuple[int, int, int, int], src: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    if src[3] == 0:
        return dst
    if src[3] == 255 or dst[3] == 0:
        if src[0] == 0 and src[1] == 0 and src[2] == 0:
            return (23, 34, 44, src[3])
        return src
    sa = src[3] / 255.0
    da = dst[3] / 255.0
    oa = sa + da * (1.0 - sa)
    if oa <= 0.001:
        return CLEAR
    r = max(1, int(round((src[0] * sa + dst[0] * da * (1.0 - sa)) / oa)))
    g = max(1, int(round((src[1] * sa + dst[1] * da * (1.0 - sa)) / oa)))
    b = max(1, int(round((src[2] * sa + dst[2] * da * (1.0 - sa)) / oa)))
    return (r, g, b, min(255, int(round(oa * 255.0))))


def blit(dst: list[list[tuple[int, int, int, int]]], src: list[list[tuple[int, int, int, int]]], ox: int = 0, oy: int = 0) -> None:
    dh, dw = len(dst), len(dst[0])
    sh, sw = len(src), len(src[0])
    for y in range(sh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(sw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            sc = src[y][x]
            if sc[3] > 0:
                dst[dy][dx] = blend_over(dst[dy][dx], sc)


def hsh(x: int, y: int, s: int) -> float:
    n = (int(x) * 374761393 + int(y) * 668265263 + int(s) * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x: float, y: float, s: int) -> float:
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a, b = hsh(xi, yi, s), hsh(xi + 1, yi, s)
    c, d = hsh(xi, yi + 1, s), hsh(xi + 1, yi + 1, s)
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def fbm(x: float, y: float, s: int) -> float:
    return (
        0.55 * vnoise(x, y, s)
        + 0.30 * vnoise(x * 2.07, y * 2.07, s + 17)
        + 0.15 * vnoise(x * 4.19, y * 4.19, s + 37)
    )


def normalize3(nx: float, ny: float, nz: float) -> tuple[float, float, float]:
    ln = math.sqrt(nx * nx + ny * ny + nz * nz)
    if ln < 1e-6:
        return (0.0, 0.0, 1.0)
    return (nx / ln, ny / ln, nz / ln)


# ---------------------------------------------------------------------------
# Organic Craggy 3D Geological Volume Engine (RockLobe + Multi-Scale Relief)
# ---------------------------------------------------------------------------
class RockLobe:
    """An asymmetric, weathered 3/4 boulder / sedimentary bench sub-mass.
    Never produces pointed 45-degree origami pyramids — instead sculpts rounded-craggy
    stone shoulders, tabular strata shelves, spalled notches, and embedded bases!
    """

    def __init__(
        self,
        cx: float,
        cy: float,
        rx: float,
        ry_north: float,
        ry_south: float,
        zh: float,
        seed: int,
        lobe_id: int = 0,
        ramp_idx: int = 0,
        power: float = 2.6,
        tilt_x: float = 0.0,
        tilt_y: float = -0.08,
        flat_crown: float = 0.72,
        cragginess: float = 0.18,
        strata_angle: float = 0.08,
        strata_period: float = 6.0,
        strata_step: float = 0.0,
        plate_scale: float = 5.6,
        vein: bool = False,
    ) -> None:
        self.cx = cx
        self.cy = cy
        self.rx = max(2.0, rx)
        self.ry_north = max(2.0, ry_north)
        self.ry_south = max(1.8, ry_south)
        self.zh = zh
        self.seed = seed
        self.lobe_id = lobe_id
        self.ramp_idx = ramp_idx % len(RAMPS)
        self.power = power
        self.tilt_x = tilt_x
        self.tilt_y = tilt_y
        self.flat_crown = flat_crown
        self.cragginess = cragginess
        self.strata_angle = strata_angle
        self.strata_period = max(3.2, strata_period)
        self.strata_step = strata_step
        self.plate_scale = max(3.4, plate_scale)
        self.vein = vein

    def eval_height(self, x: float, y: float) -> float:
        # Spatial domain warp so silhouettes have organic craggy stone shoulders & notches
        wx = x + (fbm(x * 0.11, y * 0.11, self.seed + 5) - 0.5) * self.rx * self.cragginess * 1.9
        wy = y + (fbm(x * 0.11 + 9.3, y * 0.11 + 4.7, self.seed + 13) - 0.5) * self.ry_north * self.cragginess * 1.6

        dx = wx - self.cx
        dy = wy - self.cy
        ry = self.ry_south if dy > 0.0 else self.ry_north

        nx = dx / self.rx
        ny = dy / ry
        ang = math.atan2(ny, nx)

        # Low-order harmonic asymmetry (weathered rock corners, NEVER high-freq spikes)
        harm = (
            0.08 * math.sin(ang * 2.0 + self.seed * 0.7)
            + 0.06 * math.cos(ang * 3.0 - self.seed * 1.1)
            + 0.04 * math.sin(ang * 5.0 + self.seed * 1.9)
        ) * (0.65 + self.cragginess * 1.8)

        p = self.power
        r_norm = ((abs(nx) ** p + abs(ny) ** p) ** (1.0 / p)) / max(0.55, 1.0 + harm)
        if r_norm >= 1.0:
            return -1.0

        # Smooth-steep 3D rock dome/bench profile: steep rock walls at perimeter, broad weathered crown!
        wall = max(0.0, 1.0 - r_norm * r_norm)
        dome = wall ** 0.54
        # Flatten upper crown organically into a weathered caprock / plateau shoulder
        cap = self.flat_crown
        if dome > cap:
            dome = cap + (dome - cap) * 0.34
        z = (dome / (cap + (1.0 - cap) * 0.34)) * self.zh

        # Tilted crown slope (gives directional geological dip)
        z -= (nx * self.tilt_x + ny * self.tilt_y) * self.zh * 0.28

        # Undercut / basal tuck on south/lower edge so boulders overhang their base slightly in 3/4 view!
        if dy > ry * 0.45:
            tuck = (dy / ry - 0.45) / 0.55
            z -= tuck * tuck * min(3.2, self.zh * 0.14)

        # Real 3D sedimentary strata shelves & stepped rock benches!
        ca, sa = math.cos(self.strata_angle), math.sin(self.strata_angle)
        s_coord = (
            dx * sa
            + dy * ca
            - z * 0.24
            + (fbm(x * 0.13, y * 0.13, self.seed + 29) - 0.5) * 2.8
        )
        if self.strata_step > 0.05:
            bed_f = s_coord / self.strata_period
            bed_i = math.floor(bed_f)
            frac = bed_f - bed_i
            # Smooth-stepped riser lip + gently inclined bench tread + recessed seam groove
            riser = clampf((frac - 0.68) / 0.24, 0.0, 1.0)
            step_wave = (frac - riser * 0.82) * self.strata_step
            seam = -0.85 * self.strata_step if 0.90 <= frac <= 0.99 else 0.0
            z += step_wave + seam

        # Multi-scale craggy rock-plate relief (spalled stone scales & concave weathered pockets)
        plate_relief = (fbm(x / self.plate_scale, y / (self.plate_scale * 0.85), self.seed + 43) - 0.5) * min(3.4, 0.8 + self.zh * 0.075)
        z += plate_relief

        return max(0.15, z)


def eval_meso_plate(x: int, y: int, lobe: RockLobe) -> tuple[bool, bool, float, float, float, int, int]:
    """Computes interlocking craggy stone scales/plates (adapted from oak_botany.py's craggy rhytidome engine
    for sedimentary & metamorphic rock!) along the lobe's bedding tangent:
      returns (is_fissure, is_bevel, plate_tone, tilt_x, tilt_y, pc, pr)
    """
    ca, sa = math.cos(lobe.strata_angle), math.sin(lobe.strata_angle)
    dx, dy = x - lobe.cx, y - lobe.cy
    along = dx * ca - dy * sa
    across = dx * sa + dy * ca

    ps_x = lobe.plate_scale * 1.28
    ps_y = lobe.plate_scale * 0.86

    warp_l = along + (fbm(x * 0.19, y * 0.19, lobe.seed + 61) - 0.5) * (ps_x * 0.62)
    warp_a = across + (fbm(x * 0.21 + 5.1, y * 0.21 + 2.7, lobe.seed + 73) - 0.5) * (ps_y * 0.58)

    pr = int(math.floor(warp_a / ps_y))
    stagger = (pr & 1) * (ps_x * 0.47) + (hsh(0, pr, lobe.seed + 79) - 0.5) * (ps_x * 0.25)
    pc = int(math.floor((warp_l + stagger) / ps_x))

    fx = ((warp_l + stagger) / ps_x) - pc
    fy = (warp_a / ps_y) - pr

    # Meandering, intermittent geological joints (NOT a continuous brick wall!)
    h_prob = 0.42 + (0.34 if lobe.strata_step > 0.1 else 0.0)
    v_prob = 0.34
    h_joint = (fy < 0.19) and (hsh(pc, pr, lobe.seed + 83) < h_prob)
    v_joint = (fx < 0.17) and (hsh(pc, pr, lobe.seed + 89) < v_prob)

    is_fissure = h_joint or v_joint
    # Crisp 1px sunlit upper/NW catchlight bevel immediately below/right of a joint or on upper-left of a plate!
    is_bevel = (not is_fissure) and (
        (0.19 <= fy < 0.37 and hsh(pc, pr, lobe.seed + 83) < h_prob)
        or (0.17 <= fx < 0.34 and fy < 0.62 and hsh(pc, pr, lobe.seed + 89) < v_prob)
    )

    plate_tone = (hsh(pc, pr, lobe.seed + 97) - 0.5) * 0.28
    # Occasional spalled concave pocket on weathered boulders
    if hsh(pc, pr, lobe.seed + 101) < 0.14 and 0.28 < fx < 0.78 and 0.28 < fy < 0.78:
        plate_tone -= 0.22

    tilt_x = (hsh(pc, pr, lobe.seed + 107) - 0.5) * 0.26
    tilt_y = (hsh(pc, pr, lobe.seed + 113) - 0.5) * 0.24
    return is_fissure, is_bevel, plate_tone, tilt_x, tilt_y, pc, pr


def evaluate_formation(
    fw: int,
    fh: int,
    lobes: list[RockLobe],
    cleave_planes: list[tuple[float, float, float, float, float, float]] | None = None,
) -> dict[str, list[list]]:
    """Evaluates compound 3D rock formation onto (fw x fh) height/normal/occlusion buffers.
    `cleave_planes`: list of (px0, py0, nx, ny, nz, offset_d) cutting fresh split facets for `chipped` (col 2)!
    """
    mask = [[False for _ in range(fw)] for _ in range(fh)]
    zbuf = [[0.0 for _ in range(fw)] for _ in range(fh)]
    lobe_idx = [[-1 for _ in range(fw)] for _ in range(fh)]
    cleft_ao = [[0.0 for _ in range(fw)] for _ in range(fh)]
    fresh = [[False for _ in range(fw)] for _ in range(fh)]
    nrm = [[(0.0, 0.0, 1.0) for _ in range(fw)] for _ in range(fh)]

    norm_cleaves: list[tuple[float, float, float, float, float, float]] = []
    if cleave_planes:
        for px0, py0, nx, ny, nz, d in cleave_planes:
            ux, uy, uz = normalize3(nx, ny, nz)
            norm_cleaves.append((px0, py0, ux, uy, uz, d))

    for y in range(1, fh - 1):
        for x in range(1, fw - 1):
            best_z = -1.0
            second_z = -1.0
            best_li = -1
            for li, lb in enumerate(lobes):
                zv = lb.eval_height(float(x), float(y))
                if zv > best_z:
                    second_z = best_z
                    best_z = zv
                    best_li = li
                elif zv > second_z:
                    second_z = zv

            if best_z <= 0.0 or best_li < 0:
                continue

            is_fr = False
            # Apply craggy stepped quarry-ledge cleavage for `chipped` (col 2) — NEVER a smooth flat ramp!
            if norm_cleaves:
                discard = False
                for px0, py0, ux, uy, uz, d in norm_cleaves:
                    # Multi-scale craggy rock-step fracture (quantized 3.5 px quarry ledges + rough domain warp!)
                    wob = (fbm(x * 0.14, y * 0.14, 907) - 0.5) * 3.8
                    ledge_q = math.floor((y * 0.34 + x * 0.14 + wob * 0.5) / 1.6) * 1.35
                    raw_rhs = d + wob - ux * (x - px0) - uy * (y - py0)
                    if abs(uz) < 0.05:
                        if raw_rhs < 0.0:
                            discard = True
                            break
                    elif uz > 0.0:
                        z_raw = raw_rhs / uz
                        if z_raw <= 0.65:
                            discard = True
                            break
                        # Quantize cut height into stepped 3.2px rough quarry benches so normals have real vertical risers & flat treads!
                        z_stepped = math.floor(z_raw / 3.2) * 3.2 + (z_raw % 3.2) * 0.28 + (ledge_q % 1.8) * 0.35
                        if z_stepped < best_z:
                            best_z = max(0.55, z_stepped)
                            is_fr = True
                if discard or best_z <= 0.50:
                    continue

            mask[y][x] = True
            zbuf[y][x] = best_z
            lobe_idx[y][x] = best_li
            fresh[y][x] = is_fr
            # Deep cleft occlusion where two distinct boulder lobes meet in a V-seam!
            if second_z > 0.0 and (best_z - second_z) < 4.2:
                cleft_ao[y][x] = clampf((4.2 - (best_z - second_z)) / 4.2, 0.0, 1.0) * 0.52

    # Clean isolated 1-pixel silhouette burrs so pixel edges read hand-crafted
    for _pass in range(2):
        for y in range(1, fh - 1):
            for x in range(1, fw - 1):
                if mask[y][x]:
                    nb = int(mask[y - 1][x]) + int(mask[y + 1][x]) + int(mask[y][x - 1]) + int(mask[y][x + 1])
                    if nb <= 1:
                        mask[y][x] = False
                        zbuf[y][x] = 0.0

    # Compute crisp 3D surface normals via finite differences of the sculpted heightfield
    for y in range(1, fh - 1):
        for x in range(1, fw - 1):
            if not mask[y][x]:
                continue
            zc = zbuf[y][x]
            zl = zbuf[y][x - 1] if mask[y][x - 1] else max(0.0, zc - 2.6)
            zr = zbuf[y][x + 1] if mask[y][x + 1] else max(0.0, zc - 2.6)
            zu = zbuf[y - 1][x] if mask[y - 1][x] else max(0.0, zc - 2.6)
            zd = zbuf[y + 1][x] if mask[y + 1][x] else max(0.0, zc - 3.0)
            dzdx = (zr - zl) * 0.5
            dzdy = (zd - zu) * 0.5
            nrm[y][x] = normalize3(-dzdx * 0.72, -dzdy * 0.72, 1.0)

    return {
        "mask": mask,
        "z": zbuf,
        "lobe": lobe_idx,
        "ao": cleft_ao,
        "fresh": fresh,
        "nrm": nrm,
    }


def render_craggy_rock(
    fw: int,
    fh: int,
    lobes: list[RockLobe],
    field: dict[str, list[list]],
    feet_y: int,
    seed: int,
    ground_soft: bool = False,
) -> list[list[tuple[int, int, int, int]]]:
    """Renders richly textured, weathered Glimmtal pixel-art stone from the sculpted 3D field."""
    px = blank(fw, fh)
    mask = field["mask"]
    zbuf = field["z"]
    lobe_idx = field["lobe"]
    cleft_ao = field["ao"]
    fresh = field["fresh"]
    nrm = field["nrm"]

    for y in range(1, fh - 1):
        for x in range(1, fw - 1):
            if not mask[y][x]:
                continue
            li = lobe_idx[y][x]
            lb = lobes[li]
            nx, ny, nz = nrm[y][x]
            ao = cleft_ao[y][x]
            is_fr = fresh[y][x]
            z = zbuf[y][x]

            up_in = mask[y - 1][x]
            dn_in = mask[y + 1][x]
            lf_in = mask[y][x - 1]
            rt_in = mask[y][x + 1]

            if is_fr:
                # Freshly cleaved interior greywacke/flint: craggy stepped quarry benches & fracture plates!
                is_fiss, is_bev, p_tone, ptx, pty, _pc, _pr = eval_meso_plate(x, y, lb)
                nnx, nny, nnz = normalize3(nx + ptx * 1.15, ny + pty * 1.15, nz)
                dot = nnx * SUN[0] + nny * SUN[1] + nnz * SUN[2]
                stroke = (hsh(x // 3, y // 2, seed + 311) - 0.5) * 0.14
                s = dot - ao * 0.75 + p_tone * 0.85 + stroke - 0.14
                if is_fiss:
                    s -= 0.34
                elif is_bev and dot > 0.0:
                    s += 0.18
                # Sharp fresh fracture arris ONLY on the 1px rim where fresh cut meets weathered crust!
                crust_border = (
                    (up_in and not fresh[y - 1][x])
                    or (lf_in and not fresh[y][x - 1])
                    or (not up_in and dn_in)
                )
                ti = clampi(int((s + 0.36) * 4.9), 1, 5)
                if nnx > 0.36 or nny > 0.42:
                    ti = min(ti, 2)
                if crust_border and dot > 0.12:
                    ti = 6 if dot > 0.45 else 5
                put(px, x, y, RAMP_FRESH[ti])
                continue

            # Meso craggy rock-plate evaluation (interlocking weathered stone scales & joints!)
            is_fiss, is_bev, p_tone, ptx, pty, _pc, _pr = eval_meso_plate(x, y, lb)
            nnx, nny, nnz = normalize3(nx + ptx * 0.85, ny + pty * 0.85, nz)
            dot = nnx * SUN[0] + nny * SUN[1] + nnz * SUN[2]

            # Clean directional 3x2 stone-stroke cluster (ZERO per-pixel checkerboard noise!)
            stroke = (hsh(x // 3, y // 2, seed + 131) - 0.5) * 0.12

            # Basal grounding: cool damp earth-shadow creeping up the bottom 3 px of embedded boulders
            base_damp = 0.0
            if y >= feet_y - 2:
                base_damp = clampf((y - (feet_y - 3)) * 0.15, 0.0, 0.38)

            # Deep inter-lobe seam cleft
            lobe_seam = False
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                if mask[y + dy][x + dx] and lobe_idx[y + dy][x + dx] != li:
                    if z <= zbuf[y + dy][x + dx] + 1.5:
                        lobe_seam = True
                        break

            s = dot - ao - base_damp + p_tone * 0.88 + stroke
            if lobe_seam:
                s -= 0.50
            elif is_fiss:
                s -= 0.42
            elif is_bev and dot > -0.02:
                s += 0.22

            # Crisp 1px sunlit NW outer rim bevel (1px inside selective outline)
            nw_rim = (not up_in or not lf_in) and dn_in and rt_in and dot > 0.22 and y < feet_y - 2
            # Shadowed SE undercut lip & strong right-hand boulder shadow volume!
            se_lip = (not dn_in or not rt_in) and dot < 0.04

            ramp = RAMPS[lb.ramp_idx]
            ti = clampi(int((s + 0.40) * 5.2), 0, 6)

            if nnx > 0.44 and not is_bev:
                ti = min(ti, 2)
            if lobe_seam and z < zbuf[y][x] + 0.5:
                ti = min(ti, 1)
            elif se_lip:
                ti = min(ti, 1 if y >= feet_y - 1 else 2)
            elif nw_rim and not is_fiss:
                ti = 7 if (dot > 0.58 and (x + y) % 3 != 0) else 6
            elif ti == 6 and is_bev and dot > 0.58 and nnx < -0.14:
                ti = 7

            col = ramp[ti]

            # Subtle meandering quartz / calcite mineral vein on select boulders
            if lb.vein and not is_fiss and not lobe_seam and y < feet_y - 2:
                v_coord = (x - lb.cx) * 0.62 + (y - lb.cy) * 0.78 + (fbm(x * 0.18, y * 0.18, lb.seed + 199) - 0.5) * 5.5
                if abs(v_coord - 1.5) < 0.58 and hsh(x, y, lb.seed + 211) > 0.22:
                    qi = 2 if dot > 0.45 else (1 if dot > 0.05 else 0)
                    col = QUARTZ_VEIN[qi]

            put(px, x, y, col)

    apply_stone_outline(px, mask, nrm, feet_y, ground_soft=ground_soft)
    return px


def apply_stone_outline(
    px: list[list[tuple[int, int, int, int]]],
    mask: list[list[bool]],
    nrm: list[list[tuple[float, float, float]]],
    feet_y: int,
    ground_soft: bool = False,
) -> None:
    """Selective pixel-art outline that OPENS / softens along the ground-embedded base (`y >= feet_y`)
    so boulders sink into turf, soil, and moss instead of sitting on top like dark-ringed stickers!
    """
    h, w = len(px), len(px[0])
    top_col = OUT_GROUND_TOP if ground_soft else OUT_TOP_STONE
    bot_col = OUT_GROUND_BOT if ground_soft else OUT_SHADE
    pts: list[tuple[int, int, tuple[int, int, int, int]]] = []

    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                continue
            nbs = []
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and mask[ny][nx]:
                    nbs.append((dx, dy, nrm[ny][nx]))
            if not nbs:
                continue

            has_below_or_right = any(dx > 0 or dy > 0 for dx, dy, _ in nbs)
            has_above_or_left = any(dx < 0 or dy < 0 for dx, dy, _ in nbs)
            only_above = all(dy < 0 and dx == 0 for dx, dy, _ in nbs)

            # For flush ground details & rubble (`ground_soft=True`), skip top/left sticker outlines completely
            # (like ancient_stones.py!) and use only a subtle SE bevel/contact shadow so chips sit flush in soil/scree!
            if ground_soft:
                if has_above_or_left and not has_below_or_right:
                    pts.append((x, y, (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], 96)))
                continue

            # At the ground-embedded bottom edge (below rock feet), skip hard opaque outline and use soft contact shadow!
            if only_above and y >= feet_y - 1:
                pts.append((x, y, (CONTACT_RGB[0], CONTACT_RGB[1], CONTACT_RGB[2], 125)))
                continue

            avg_dot = sum(n[0] * SUN[0] + n[1] * SUN[1] + n[2] * SUN[2] for _, _, n in nbs) / len(nbs)
            if has_below_or_right and not has_above_or_left and avg_dot > 0.02 and y < feet_y:
                pts.append((x, y, top_col))
            else:
                pts.append((x, y, bot_col))

    for x, y, col in pts:
        if col[3] < 255:
            put_shadow(px, x, y, col[3])
        else:
            put(px, x, y, col)


# ---------------------------------------------------------------------------
# Base Skirt (col 0), Cleavage Cracks (cols 3, 4), and Shattered Rubble (col 5)
# ---------------------------------------------------------------------------
def build_base_skirt(
    fw: int,
    fh: int,
    feet_x: int,
    feet_y: int,
    half_w: int,
    body_half_h: int,
    intact_mask: list[list[bool]],
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Col 0: Harmonized woodland-teal ground contact shadow + nestled basal stone chips,
    humus crumbs, root-moss cushions & tiny 2-3 px turf blades hugging the embedded stone base!
    """
    px = blank(fw, fh)
    rx = half_w + 4.0
    ry = body_half_h + 3.0
    cx = feet_x + 1.2
    cy = feet_y - body_half_h * 0.14 + 1.0

    for y in range(max(1, int(cy - ry - 2)), min(fh - 1, int(cy + ry + 3))):
        for x in range(max(1, int(cx - rx - 2)), min(fw - 1, int(cx + rx + 3))):
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            wob = (vnoise(x * 0.24, y * 0.32, seed + 3) - 0.5) * 0.18
            if d + wob < 1.0:
                a = int(98 * ((1.0 - max(0.0, d + wob)) ** 1.4))
                put_shadow(px, x, y, a)

    # Tight contact shadow + damp humus & root-moss toes directly along the bottom rock contour
    for y in range(2, fh - 2):
        for x in range(2, fw - 2):
            if not intact_mask[y][x] and intact_mask[y - 1][x] and y >= feet_y - body_half_h:
                put_shadow(px, x, y, 108)
                if y + 1 < fh:
                    put_shadow(px, x + 1, y + 1, 64)
                # Occasional nestled moss toe or damp soil crumb hugging the base seam
                r = hsh(x, y, seed + 19)
                if r < 0.22:
                    put(px, x, y, MOSS[2 if x < feet_x else 1])
                    if r < 0.09 and y - 1 >= 1:
                        put(px, x, y - 1, MOSS[3 if x < feet_x else 2])
                elif r < 0.34:
                    put(px, x, y, SOIL_CRUMB[1 if x < feet_x else 0])

    # Small nestled talus chips & 2px grass/sedge wisps at outer left/right toes
    n_toes = clampi(half_w // 5 + 2, 2, 8)
    for i in range(n_toes):
        ang = math.pi * (0.06 + 0.88 * (i / max(1, n_toes - 1)))
        tx = int(round(feet_x + math.cos(ang) * (half_w * 0.84 + (hsh(i, 1, seed + 31) - 0.5) * 3.0)))
        ty = int(round(feet_y + math.sin(ang) * (body_half_h * 0.42) + 0.5))
        if 2 <= tx < fw - 3 and 2 <= ty < fh - 2:
            if hsh(i, 2, seed + 37) < 0.58:
                # Tiny 3x2 embedded stone flake
                put(px, tx, ty, RAMP_LIMESTONE[4 if tx < feet_x else 3])
                put(px, tx - 1, ty, RAMP_LIMESTONE[5 if tx < feet_x else 4])
                put(px, tx + 1, ty, RAMP_LIMESTONE[2])
                put_shadow(px, tx, ty + 1, 76)
            else:
                # Tiny hardy seam turf tuft
                put(px, tx, ty, MOSS[1])
                put(px, tx, ty - 1, MOSS[3])
                if hsh(i, 3, seed + 41) > 0.45:
                    put(px, tx + (1 if tx < feet_x else -1), ty - 2, MOSS[4])

    return px


def draw_fracture_network(
    fw: int,
    fh: int,
    mask: list[list[bool]],
    nrm: list[list[tuple[float, float, float]]],
    starts: list[tuple[int, int, float, int]],
    deep: bool,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Draws jagged branching pickaxe cleavage fissures strictly inside `mask`."""
    px = blank(fw, fh)
    carved: set[tuple[int, int]] = set()

    def trace(sx: float, sy: float, ang: float, steps: int, branch_gen: int) -> None:
        cx, cy = sx, sy
        cur_a = ang
        for st in range(steps):
            ix, iy = int(round(cx)), int(round(cy))
            if not (2 <= ix < fw - 2 and 2 <= iy < fh - 2):
                break
            if mask[iy][ix] and mask[iy + 1][ix] and mask[iy][ix - 1] and mask[iy][ix + 1]:
                carved.add((ix, iy))
                if deep and st < steps * 0.65 and branch_gen == 0:
                    if mask[iy + 1][ix]:
                        carved.add((ix, iy + 1))
                if branch_gen == 0 and st == steps // 2 and steps >= 6:
                    b_ang = cur_a + (0.68 if hsh(ix, iy, seed + 7) > 0.5 else -0.68)
                    trace(cx, cy, b_ang, max(3, steps // 2), 1)
            cur_a += (hsh(st, branch_gen * 19 + int(sx), seed + 13) - 0.5) * 0.62
            cx += math.cos(cur_a) * 0.92
            cy += math.sin(cur_a) * 0.92

    for sx, sy, ang, ln in starts:
        trace(float(sx), float(sy), ang, ln, 0)

    for ix, iy in carved:
        put(px, ix, iy, RAMP_FRESH[0] if deep else RAMP_LIMESTONE[0])
        # Crisp fresh splinter catchlight on lower/SE lip of the opened crack!
        for dx, dy in ((0, 1), (1, 0)):
            nx, ny = ix + dx, iy + dy
            if (nx, ny) not in carved and mask[ny][nx]:
                dot = nrm[ny][nx][0] * SUN[0] + nrm[ny][nx][1] * SUN[1] + nrm[ny][nx][2] * SUN[2]
                put(px, nx, ny, RAMP_FRESH[6 if dot > 0.15 else 4])
                break
    return px


def build_rubble(
    fw: int,
    fh: int,
    feet_x: int,
    feet_y: int,
    half_w: int,
    body_half_h: int,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Col 5: Low-profile walkable shattered stone scar with broken fresh & weathered rock chunks."""
    n_chunks = clampi(half_w // 4 + 3, 4, 13)
    lobes: list[RockLobe] = []
    for i in range(n_chunks):
        t = i / max(1, n_chunks - 1)
        ang = t * math.tau + (hsh(i, 1, seed) - 0.5) * 0.55
        dist = (0.18 + 0.68 * hsh(i, 2, seed + 5)) * half_w * 0.86
        cx = feet_x + math.cos(ang) * dist
        cy = (feet_y - body_half_h * 0.25) + math.sin(ang) * (body_half_h * 0.68)
        rx = 2.4 + hsh(i, 3, seed + 11) * min(5.4, half_w * 0.24)
        ry = rx * (0.58 + 0.20 * hsh(i, 4, seed + 17))
        zh = 2.6 + hsh(i, 5, seed + 23) * 4.2
        lobes.append(RockLobe(
            cx=cx, cy=cy, rx=rx, ry_north=ry, ry_south=ry * 0.85, zh=zh,
            seed=seed + i * 29, lobe_id=i, ramp_idx=i % 3, power=2.8,
            flat_crown=0.64, cragginess=0.22, plate_scale=3.8,
        ))
    fld = evaluate_formation(fw, fh, lobes)
    # Mark half the chunks as fresh broken interior stone
    for y in range(fh):
        for x in range(fw):
            if fld["mask"][y][x] and (fld["lobe"][y][x] % 2 == 0):
                fld["fresh"][y][x] = True
    px = render_craggy_rock(fw, fh, lobes, fld, feet_y + 2, seed + 71, ground_soft=True)
    return px


# ---------------------------------------------------------------------------
# Botanical Befall & Crevice Props (Cols 6..14 + Glow)
# ---------------------------------------------------------------------------
def build_moss_overlay(
    fw: int,
    fh: int,
    field: dict[str, list[list]],
    lobes: list[RockLobe],
    feet_x: int,
    feet_y: int,
    half_w: int,
    variant: int,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Cols 6, 7: Velvety 3D woodland moss cushions hugging rock crevices, strata shelves & NW shoulders,
    with 1-2 px hanging moss fringes and dark underside contact shadow onto bare stone!
    """
    px = blank(fw, fh)
    mask = field["mask"]
    nrm = field["nrm"]
    cleft_ao = field["ao"]
    lobe_idx = field["lobe"]
    moss_mask = [[False for _ in range(fw)] for _ in range(fh)]

    bias_x = -0.35 if variant == 0 else 0.25
    for y in range(2, fh - 2):
        for x in range(2, fw - 2):
            if not mask[y][x]:
                continue
            nx, ny, nz = nrm[y][x]

            # Cohesive broad moss blankets (low-freq 0.095 FBM!) on NW shelves, deep clefts & damp collars
            # Keeps 75%+ of the sculpted stone masonry/strata proudly visible!
            shelf_affinity = max(0.0, nz - 0.62) * 0.85 + max(0.0, -ny) * 0.34 + max(0.0, -nx * (0.5 - bias_x)) * 0.30
            crevice_bonus = cleft_ao[y][x] * 0.72
            basal_bonus = clampf((y - (feet_y - 4)) * 0.09, 0.0, 0.28) if variant == 1 else 0.0

            colony = fbm(x * 0.095, y * 0.105, seed) * 0.82 + vnoise(x * 0.24, y * 0.24, seed + 13) * 0.18
            score = colony * 0.86 + shelf_affinity * 0.48 + crevice_bonus + basal_bonus
            thresh = 0.745 if variant == 0 else 0.765
            if score > thresh:
                moss_mask[y][x] = True

    # Prune tiny 1-2 px scattered moss freckles BEFORE growing hanging fringes so cushions are bold & plush!
    for _clean in range(2):
        cleaned = [row[:] for row in moss_mask]
        for y in range(2, fh - 2):
            for x in range(2, fw - 2):
                if moss_mask[y][x]:
                    nb = int(moss_mask[y - 1][x]) + int(moss_mask[y + 1][x]) + int(moss_mask[y][x - 1]) + int(moss_mask[y][x + 1])
                    if nb <= 1:
                        cleaned[y][x] = False
        moss_mask = cleaned

    # Grow 1-2 px hanging moss fringes draping down from plush moss cushions over rock ledges
    fringe_pts: list[tuple[int, int]] = []
    for y in range(2, fh - 4):
        for x in range(2, fw - 2):
            if moss_mask[y][x] and not moss_mask[y + 1][x] and mask[y + 1][x]:
                if hsh(x, y, seed + 29) < 0.44:
                    fringe_pts.append((x, y + 1))
                    if y + 2 < fh - 2 and mask[y + 2][x] and not moss_mask[y + 2][x] and hsh(x, y, seed + 31) < 0.20:
                        fringe_pts.append((x, y + 2))
    for fx_p, fy_p in fringe_pts:
        moss_mask[fy_p][fx_p] = True

    # Shade 3D velvety moss cushions + 1px dark underside shadow onto bare rock below!
    for y in range(2, fh - 2):
        for x in range(2, fw - 2):
            if not moss_mask[y][x]:
                if mask[y][x] and moss_mask[y - 1][x]:
                    put_shadow(px, x, y, 72)
                continue

            nx, ny, nz = nrm[y][x]
            up_m = moss_mask[y - 1][x]
            dn_m = moss_mask[y + 1][x]
            lf_m = moss_mask[y][x - 1]
            # Local 3D cushion puff normal!
            puff = (0.18 if not up_m else 0.0) + (0.12 if not lf_m else 0.0) - (0.24 if not dn_m else 0.0)
            dot = nx * SUN[0] + ny * SUN[1] + nz * SUN[2] + puff
            tex = (BAYER4[y & 3][x & 3] / 16.0 - 0.5) * 0.16 + (hsh(x, y, seed + 47) - 0.5) * 0.12
            mi = clampi(int((dot + tex + 0.30) * 4.4), 0, 4)
            if not up_m and dot > 0.45 and (x + y) % 4 == 0:
                mi = 5
            if not dn_m and dot < 0.15:
                mi = min(mi, 1)
            put(px, x, y, MOSS[mi])

            # Soft moss crown sel-out if moss touches outer rock silhouette
            if y - 1 >= 1 and not mask[y - 1][x]:
                put(px, x, y - 1, OUT_TOP_MOSS)

    return px


def build_lichen_overlay(
    fw: int,
    fh: int,
    field: dict[str, list[list]],
    lobes: list[RockLobe],
    feet_y: int,
    variant: int,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Cols 8, 9: Delicate crustose rock-lichen ring-rosettes (Parmelia sea-sage & muted Rhizocarpon ochre).
    Small scalloped 3-5 px thalli with darker spore centers & pale rims — NEVER flat orange blobs!
    """
    px = blank(fw, fh)
    mask = field["mask"]
    nrm = field["nrm"]
    lobe_idx = field["lobe"]

    # Pick natural colony centers on sunlit upper/mid stone plates
    n_colonies = clampi((fw * fh) // 360, 2, 14)
    centers: list[tuple[int, int, float, list]] = []
    attempts = 0
    while len(centers) < n_colonies and attempts < n_colonies * 14:
        attempts += 1
        cx = int(3 + hsh(attempts, 1, seed) * (fw - 6))
        cy = int(3 + hsh(attempts, 2, seed + 7) * max(4, feet_y - 6))
        if not (2 <= cx < fw - 2 and 2 <= cy < fh - 2) or not mask[cy][cx]:
            continue
        nx, ny, nz = nrm[cy][cx]
        dot = nx * SUN[0] + ny * SUN[1] + nz * SUN[2]
        if dot < 0.08:
            continue
        if any(math.hypot(cx - ox, cy - oy) < 6.5 for ox, oy, _, _ in centers):
            continue
        # Sea-sage Parmelia dominates (75%); muted dusty-ochre Rhizocarpon is a subtle 25% accent!
        use_ochre = hsh(attempts, 3, seed + 19) > (0.76 if variant == 0 else 0.66)
        pal = LICHEN_OCHRE if use_ochre else LICHEN_SAGE
        rad = 1.4 + hsh(attempts, 4, seed + 23) * (1.8 if fw >= 68 else 1.1)
        centers.append((cx, cy, rad, pal))

    for cx, cy, rad, pal in centers:
        r_int = int(math.ceil(rad + 1.0))
        for dy in range(-r_int, r_int + 1):
            for dx in range(-r_int, r_int + 1):
                x, y = cx + dx, cy + dy
                if not (2 <= x < fw - 2 and 2 <= y < fh - 2) or not mask[y][x]:
                    continue
                lb = lobes[lobe_idx[y][x]]
                is_fiss, _, _, _, _, _, _ = eval_meso_plate(x, y, lb)
                if is_fiss:
                    continue
                d = math.hypot(dx, dy * 1.15)
                ang = math.atan2(dy, dx)
                scallop = 0.25 * math.sin(ang * 5.0 + seed)
                if d > rad + scallop:
                    continue
                # Ring-rosette structure: darker apothecia center, bright scalloped outer lobe rim!
                nx, ny, nz = nrm[y][x]
                dot = nx * SUN[0] + ny * SUN[1] + nz * SUN[2]
                if d < 0.85 and rad >= 1.9:
                    put(px, x, y, pal[0])
                elif d > rad + scallop - 0.85:
                    if hsh(x, y, seed + 41) > 0.18:
                        put(px, x, y, pal[3 if dot > 0.35 and dy <= 0 else 2])
                else:
                    put(px, x, y, pal[2 if dot > 0.28 else 1])

    return px


def draw_ivy_leaf(px: list[list[tuple[int, int, int, int]]], mask: list[list[bool]], x: int, y: int, bright: bool) -> None:
    """Draws a crisp 3-4 px trilobed rock-ivy leaf with 1px drop shadow onto the stone."""
    h, w = len(px), len(px[0])
    if not (2 <= x < w - 2 and 2 <= y < h - 2) or not mask[y][x]:
        return
    put(px, x, y, IVY_LEAF[3 if bright else 2])
    if mask[y][x - 1]:
        put(px, x - 1, y, IVY_LEAF[4 if bright else 3])
    if mask[y - 1][x]:
        put(px, x, y - 1, IVY_LEAF[3 if bright else 2])
    if mask[y][x + 1]:
        put(px, x + 1, y, IVY_LEAF[1])
    if y + 1 < h - 1 and mask[y + 1][x]:
        put_shadow(px, x, y + 1, 68)


def build_ivy_overlay(
    fw: int,
    fh: int,
    field: dict[str, list[list]],
    feet_x: int,
    feet_y: int,
    half_w: int,
    height_px: int,
    variant: int,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Cols 10, 11: Woody creeping rock-ivy climbing up rock crevices with shaded trilobed leaves."""
    px = blank(fw, fh)
    mask = field["mask"]
    nrm = field["nrm"]
    if half_w < 10:
        return px

    n_vines = 1 if half_w < 18 else (2 if half_w < 32 else 3)
    for vi in range(n_vines):
        side = (-1.0 if variant == 0 else 1.0) * (1.0 if vi % 2 == 0 else -0.65)
        vx = float(feet_x + side * half_w * (0.36 + 0.18 * vi))
        vy = float(feet_y - 1)
        steps = clampi(int(height_px * (0.58 + 0.14 * hsh(vi, 1, seed))), 8, 38)
        ang = -math.pi * 0.5 + (-side) * 0.24

        stem_pts: list[tuple[int, int]] = []
        for st in range(steps):
            ix, iy = int(round(vx)), int(round(vy))
            if 2 <= ix < fw - 2 and 2 <= iy < fh - 2 and mask[iy][ix]:
                stem_pts.append((ix, iy))
                put(px, ix, iy, IVY_STEM[1 if st % 3 == 0 else 0])
            ang += (hsh(st, vi, seed + 17) - 0.5) * 0.52
            ang = clampf(ang, -math.pi * 0.85, -math.pi * 0.15)
            vx += math.cos(ang) * 0.95
            vy += math.sin(ang) * 0.95

        for idx, (sx, sy) in enumerate(stem_pts):
            if idx % 3 == 1:
                off = -1 if (idx // 3) % 2 == 0 else 1
                lx, ly = sx + off, sy
                if 2 <= lx < fw - 2 and 2 <= ly < fh - 2 and mask[ly][lx]:
                    dot = nrm[ly][lx][0] * SUN[0] + nrm[ly][lx][1] * SUN[1] + nrm[ly][lx][2] * SUN[2]
                    draw_ivy_leaf(px, mask, lx, ly, dot > 0.18)

    return px


def draw_fern_tuft(px: list[list[tuple[int, int, int, int]]], cx: int, cy: int, scale: float, seed: int) -> None:
    """Draws an arching pinnate spleenwort rock-fern tuft rooted in a stone crevice."""
    h, w = len(px), len(px[0])
    fronds = [(-0.92, 5.2), (-0.42, 6.2), (0.28, 5.8), (0.85, 4.8)]
    put_shadow(px, cx, cy + 1, 78)
    for fi, (dir_x, base_len) in enumerate(fronds):
        ln = max(3, int(round(base_len * scale)))
        fx_p, fy_p = float(cx), float(cy)
        for s in range(ln):
            t = s / float(max(1, ln - 1))
            fx_p += dir_x * (0.72 + 0.35 * t)
            fy_p += -0.88 + 0.68 * t * t  # graceful botanical arch!
            ix, iy = int(round(fx_p)), int(round(fy_p))
            if 1 <= ix < w - 1 and 1 <= iy < h - 1:
                tone = clampi(int(1 + t * 3.2 - (0.6 if dir_x > 0.2 else 0.0)), 1, 4)
                put(px, ix, iy, FERN[tone])
                if s % 2 == 1 and s < ln - 1:
                    py_p = iy + (1 if t > 0.5 else 0)
                    px_p = ix + (-1 if dir_x < 0 else 1)
                    if 1 <= px_p < w - 1 and 1 <= py_p < h - 1:
                        put(px, px_p, py_p, FERN[max(0, tone - 1)])
    put(px, cx, cy, FERN[0])


def draw_houseleek_rosette(px: list[list[tuple[int, int, int, int]]], cx: int, cy: int, rad: int) -> None:
    """Draws a compact mountain houseleek (Sempervivum) succulent rosette with crimson leaf tips."""
    h, w = len(px), len(px[0])
    if not (rad + 1 <= cx < w - rad - 1 and rad + 1 <= cy < h - rad - 1):
        return
    put_shadow(px, cx, cy + rad, 72)
    for dy in range(-rad, rad + 1):
        for dx in range(-rad, rad + 1):
            d = math.hypot(dx, dy * 1.15)
            if d > rad + 0.25:
                continue
            if d < 0.85:
                put(px, cx + dx, cy + dy, HOUSELEEK[3])
            elif d > rad - 0.55 and (abs(dx) + abs(dy)) % 2 == 1:
                put(px, cx + dx, cy + dy, HOUSELEEK_TIP if dy >= 0 else HOUSELEEK[2])
            else:
                tone = 3 if (dx <= 0 and dy <= 0) else (2 if dy <= 0 else 1)
                put(px, cx + dx, cy + dy, HOUSELEEK[tone])


def build_fern_or_succulent_overlay(
    fw: int,
    fh: int,
    field: dict[str, list[list]],
    feet_x: int,
    feet_y: int,
    half_w: int,
    height_px: int,
    variant: int,
    seed: int,
) -> list[list[tuple[int, int, int, int]]]:
    """Cols 12, 13: Crevice spleenwort ferns (variant 0) & Sempervivum succulent rosettes (variant 1)."""
    px = blank(fw, fh)
    mask = field["mask"]
    cleft_ao = field["ao"]
    if half_w < 10:
        return px

    # Find genuine clefts / ledges inside the rock mask
    anchors: list[tuple[int, int]] = []
    for _att in range(60):
        ax = int(feet_x + (hsh(_att, 1, seed) - 0.5) * half_w * 1.35)
        ay = int(feet_y - 2 - hsh(_att, 2, seed + 9) * height_px * 0.62)
        if not (4 <= ax < fw - 4 and 4 <= ay < fh - 4) or not mask[ay][ax]:
            continue
        if cleft_ao[ay][ax] > 0.08 or ay >= feet_y - 5:
            if all(math.hypot(ax - ox, ay - oy) > 9.0 for ox, oy in anchors):
                anchors.append((ax, ay))
                if len(anchors) >= (1 if half_w < 22 else 2):
                    break

    if not anchors:
        anchors.append((feet_x + (-half_w // 3 if variant == 0 else half_w // 3), feet_y - 3))

    for idx, (ax, ay) in enumerate(anchors):
        if variant == 0:
            sc = 0.72 if half_w < 18 else (0.92 if half_w < 32 else 1.08)
            draw_fern_tuft(px, ax, ay, sc, seed + idx * 19)
        else:
            draw_houseleek_rosette(px, ax, ay, 3 if half_w >= 20 else 2)
            if half_w >= 18:
                draw_houseleek_rosette(px, ax + 4, ay + 1, 2)

    return px


def build_fungi_and_glow(
    fw: int,
    fh: int,
    field: dict[str, list[list]],
    feet_x: int,
    feet_y: int,
    half_w: int,
    seed: int,
) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
    """Col 14 + Glow Col 0: Damp shaded crevice shelf-fungi + whisper-subtle nocturnal teal spore glints."""
    px = blank(fw, fh)
    glow = blank(fw, fh)
    mask = field["mask"]
    if half_w < 8:
        return px, glow

    n_brackets = 1 if half_w < 20 else (2 if half_w < 34 else 3)
    for bi in range(n_brackets):
        bx = int(feet_x + (bi - (n_brackets - 1) * 0.5) * (half_w * 0.58) + (hsh(bi, 1, seed) - 0.5) * 4.0)
        by = int(feet_y - 2 - hsh(bi, 2, seed + 11) * min(10.0, half_w * 0.32))
        if not (3 <= bx < fw - 4 and 3 <= by < fh - 3) or not mask[by][bx]:
            continue
        # Tiered woodland bracket cap + dark gill underside
        put_shadow(px, bx, by + 2, 74)
        for dx in (-2, -1, 0, 1, 2):
            if abs(dx) <= 2 and mask[by][bx + dx]:
                put(px, bx + dx, by, FUNGI_DAY[3 if dx <= 0 else 2])
            if abs(dx) <= 1 and mask[by + 1][bx + dx]:
                put(px, bx + dx, by + 1, FUNGI_DAY[1])
        put(px, bx - 1, by, FUNGI_DAY[4])
        # Whisper-subtle 1-2 px unlit nocturnal spore glimmer
        put(glow, bx - 1, by, GLOW_TEAL_HI)
        if bi == 0 and mask[by][bx + 1]:
            put(glow, bx + 1, by + 1, GLOW_TEAL_MID)

    return px, glow


# ---------------------------------------------------------------------------
# 12 Geological Archetype Definitions (s0_a .. s4_b)
# Preserves exact frame_w, frame_h, feet_x, feet_y, height_px, half_w_px, body_half_h_px!
# ---------------------------------------------------------------------------
ARCHETYPES: list[dict] = [
    {"key": "s0_a", "fw": 32, "fh": 28, "fx": 16, "fy": 22, "h": 11, "hw": 8, "bhh": 4, "seed": 101},
    {"key": "s0_b", "fw": 32, "fh": 28, "fx": 16, "fy": 22, "h": 11, "hw": 8, "bhh": 4, "seed": 137},
    {"key": "s1_a", "fw": 48, "fh": 42, "fx": 24, "fy": 34, "h": 20, "hw": 14, "bhh": 6, "seed": 211},
    {"key": "s1_b", "fw": 48, "fh": 42, "fx": 24, "fy": 34, "h": 20, "hw": 14, "bhh": 6, "seed": 257},
    {"key": "s2_a", "fw": 68, "fh": 56, "fx": 34, "fy": 46, "h": 32, "hw": 21, "bhh": 8, "seed": 307},
    {"key": "s2_b", "fw": 68, "fh": 56, "fx": 34, "fy": 46, "h": 32, "hw": 21, "bhh": 8, "seed": 349},
    {"key": "s2_c", "fw": 68, "fh": 56, "fx": 34, "fy": 46, "h": 32, "hw": 21, "bhh": 8, "seed": 389},
    {"key": "s3_a", "fw": 92, "fh": 76, "fx": 46, "fy": 64, "h": 48, "hw": 30, "bhh": 11, "seed": 419},
    {"key": "s3_b", "fw": 92, "fh": 76, "fx": 46, "fy": 64, "h": 48, "hw": 30, "bhh": 11, "seed": 461},
    {"key": "s3_c", "fw": 92, "fh": 76, "fx": 46, "fy": 64, "h": 48, "hw": 30, "bhh": 11, "seed": 499},
    {"key": "s4_a", "fw": 124, "fh": 96, "fx": 62, "fy": 82, "h": 64, "hw": 44, "bhh": 14, "seed": 523},
    {"key": "s4_b", "fw": 124, "fh": 96, "fx": 62, "fy": 82, "h": 64, "hw": 44, "bhh": 14, "seed": 577},
]


def build_archetype_lobes(spec: dict) -> tuple[list[RockLobe], list[tuple[float, float, float, float, float, float]]]:
    """Builds natural weathered 3D boulder/outcrop lobes + cleavage fracture planes for each archetype."""
    key = spec["key"]
    fx, fy = spec["fx"], spec["fy"]
    bhh = spec["bhh"]
    sd = spec["seed"]
    lobes: list[RockLobe] = []
    cleaves: list[tuple[float, float, float, float, float, float]] = []

    if key == "s0_a":
        # Weathered craggy limestone fieldstone + nestled side chip
        lobes.append(RockLobe(fx - 0.5, fy - 2.5, rx=7.8, ry_north=7.2, ry_south=3.2, zh=9.5, seed=sd, ramp_idx=0, power=2.5, flat_crown=0.68, cragginess=0.20, plate_scale=4.0))
        lobes.append(RockLobe(fx + 4.2, fy - 1.2, rx=4.0, ry_north=3.8, ry_south=2.2, zh=5.2, seed=sd + 11, lobe_id=1, ramp_idx=1, power=2.6, cragginess=0.18, plate_scale=3.6))
        cleaves.append((fx + 1.5, fy - 4.0, 0.58, -0.46, 0.67, 2.8))

    elif key == "s0_b":
        # Tabular stepped slate cobble slab
        lobes.append(RockLobe(fx - 0.8, fy - 2.0, rx=8.4, ry_north=6.4, ry_south=3.0, zh=7.8, seed=sd, ramp_idx=1, power=3.0, flat_crown=0.62, cragginess=0.18, strata_angle=0.06, strata_period=3.4, strata_step=1.4, plate_scale=4.2))
        lobes.append(RockLobe(fx + 3.6, fy - 1.0, rx=4.8, ry_north=4.0, ry_south=2.2, zh=4.8, seed=sd + 17, lobe_id=1, ramp_idx=2, power=2.8, flat_crown=0.64, plate_scale=3.8))
        cleaves.append((fx - 1.5, fy - 3.0, -0.56, -0.42, 0.71, 2.6))

    elif key == "s1_a":
        # Gnarled woodland erratic boulder with flanking shoulder & quartz hairline
        lobes.append(RockLobe(fx - 2.0, fy - 4.5, rx=12.2, ry_north=13.5, ry_south=4.8, zh=17.5, seed=sd, ramp_idx=0, power=2.5, tilt_x=-0.12, flat_crown=0.70, cragginess=0.22, strata_angle=0.14, strata_period=5.0, strata_step=1.2, plate_scale=4.8, vein=True))
        lobes.append(RockLobe(fx + 6.8, fy - 3.0, rx=7.6, ry_north=7.8, ry_south=3.6, zh=11.0, seed=sd + 19, lobe_id=1, ramp_idx=2, power=2.6, tilt_x=0.15, flat_crown=0.68, cragginess=0.20, plate_scale=4.2))
        cleaves.append((fx - 2.5, fy - 8.5, -0.58, -0.48, 0.66, 5.2))

    elif key == "s1_b":
        # Tilted stratified shale/limestone bench (crisp dipping rock beds!)
        lobes.append(RockLobe(fx - 1.5, fy - 4.2, rx=13.0, ry_north=12.6, ry_south=4.6, zh=16.5, seed=sd, ramp_idx=1, power=3.0, tilt_x=0.20, tilt_y=-0.14, flat_crown=0.64, cragginess=0.19, strata_angle=-0.28, strata_period=4.2, strata_step=2.1, plate_scale=4.6))
        lobes.append(RockLobe(fx + 6.0, fy - 2.5, rx=8.2, ry_north=8.0, ry_south=3.6, zh=11.2, seed=sd + 23, lobe_id=1, ramp_idx=0, power=2.9, strata_angle=-0.28, strata_period=4.2, strata_step=1.8, plate_scale=4.2))
        cleaves.append((fx + 2.5, fy - 7.5, 0.56, -0.50, 0.66, 4.8))

    elif key == "s2_a":
        # Classic weathered Glimmtal boulder group (broad rounded-craggy dome + shoulder block + embedded toe)
        cy = fy - bhh * 0.72
        lobes.append(RockLobe(fx - 3.0, cy - 1.5, rx=16.8, ry_north=20.5, ry_south=6.6, zh=25.5, seed=sd, ramp_idx=0, power=2.55, tilt_x=-0.10, flat_crown=0.69, cragginess=0.22, strata_angle=0.11, strata_period=5.8, strata_step=1.6, plate_scale=5.4, vein=True))
        lobes.append(RockLobe(fx + 9.8, cy + 1.5, rx=11.4, ry_north=13.5, ry_south=5.2, zh=17.5, seed=sd + 17, lobe_id=1, ramp_idx=1, power=2.7, tilt_x=0.16, flat_crown=0.68, cragginess=0.20, strata_angle=0.11, strata_period=5.8, strata_step=1.4, plate_scale=4.8))
        lobes.append(RockLobe(fx - 11.5, fy - 3.5, rx=8.2, ry_north=8.2, ry_south=3.6, zh=11.0, seed=sd + 31, lobe_id=2, ramp_idx=2, power=2.6, cragginess=0.20, plate_scale=4.2))
        cleaves.append((fx - 4.0, cy - 7.5, -0.56, -0.48, 0.67, 7.2))

    elif key == "s2_b":
        # Horizontally terraced limestone/greywacke stack (stacked weathered rock benches!)
        cy = fy - bhh * 0.72
        lobes.append(RockLobe(fx, cy + 2.0, rx=19.8, ry_north=14.2, ry_south=6.8, zh=15.5, seed=sd, ramp_idx=2, power=3.1, flat_crown=0.58, cragginess=0.18, strata_angle=0.04, strata_period=4.6, strata_step=2.4, plate_scale=5.4))
        lobes.append(RockLobe(fx - 2.2, cy - 3.0, rx=15.4, ry_north=15.5, ry_south=6.0, zh=23.0, seed=sd + 19, lobe_id=1, ramp_idx=0, power=3.0, flat_crown=0.60, cragginess=0.19, strata_angle=0.04, strata_period=4.6, strata_step=2.4, plate_scale=5.0))
        lobes.append(RockLobe(fx + 3.0, cy - 7.5, rx=10.6, ry_north=10.5, ry_south=4.8, zh=27.5, seed=sd + 37, lobe_id=2, ramp_idx=1, power=2.9, flat_crown=0.62, cragginess=0.18, strata_angle=0.04, strata_period=4.6, strata_step=2.0, plate_scale=4.6))
        cleaves.append((fx + 5.0, cy - 8.0, 0.54, -0.50, 0.68, 6.8))

    elif key == "s2_c":
        # Frost-wedged twin boulder with deep shadowed V-cleft between halves!
        cy = fy - bhh * 0.72
        lobes.append(RockLobe(fx - 9.2, cy - 1.0, rx=11.5, ry_north=19.5, ry_south=6.2, zh=24.5, seed=sd, ramp_idx=1, power=2.65, tilt_x=-0.18, flat_crown=0.68, cragginess=0.22, strata_angle=0.18, strata_period=5.4, strata_step=1.6, plate_scale=4.8))
        lobes.append(RockLobe(fx + 9.4, cy + 0.5, rx=11.2, ry_north=17.2, ry_south=6.0, zh=21.5, seed=sd + 23, lobe_id=1, ramp_idx=0, power=2.65, tilt_x=0.18, flat_crown=0.68, cragginess=0.22, strata_angle=0.18, strata_period=5.4, strata_step=1.6, plate_scale=4.8, vein=True))
        lobes.append(RockLobe(fx, fy - 2.8, rx=6.8, ry_north=6.2, ry_south=3.4, zh=8.5, seed=sd + 41, lobe_id=2, ramp_idx=2, power=2.5, cragginess=0.20, plate_scale=4.0))
        cleaves.append((fx + 9.0, cy - 6.0, 0.58, -0.46, 0.67, 6.2))

    elif key == "s3_a":
        # Craggy woodland-edge boulder tor (rounded-fractured caprock + mossy ledges + flanking boulders — ZERO pointy pyramid!)
        cy = fy - bhh * 0.80
        lobes.append(RockLobe(fx - 4.0, cy - 3.5, rx=21.5, ry_north=31.0, ry_south=8.8, zh=39.0, seed=sd, ramp_idx=0, power=2.65, tilt_x=-0.08, flat_crown=0.64, cragginess=0.23, strata_angle=0.09, strata_period=6.2, strata_step=2.2, plate_scale=5.8, vein=True))
        lobes.append(RockLobe(fx + 14.0, cy + 1.0, rx=15.5, ry_north=22.0, ry_south=7.6, zh=28.0, seed=sd + 19, lobe_id=1, ramp_idx=1, power=2.7, tilt_x=0.14, flat_crown=0.66, cragginess=0.21, strata_angle=0.09, strata_period=6.2, strata_step=2.0, plate_scale=5.4))
        lobes.append(RockLobe(fx - 17.5, cy + 4.5, rx=13.0, ry_north=15.5, ry_south=6.2, zh=20.0, seed=sd + 37, lobe_id=2, ramp_idx=2, power=2.6, tilt_x=-0.16, flat_crown=0.68, cragginess=0.20, plate_scale=4.8))
        lobes.append(RockLobe(fx + 4.5, fy - 4.0, rx=11.5, ry_north=10.5, ry_south=4.8, zh=14.0, seed=sd + 53, lobe_id=3, ramp_idx=0, power=2.7, cragginess=0.20, plate_scale=4.5))
        cleaves.append((fx - 6.0, cy - 12.0, -0.56, -0.48, 0.67, 10.5))

    elif key == "s3_b":
        # Stepped overhanging limestone shelf outcrop (cantilevered tabular strata benches!)
        cy = fy - bhh * 0.80
        lobes.append(RockLobe(fx + 1.0, cy + 2.5, rx=28.0, ry_north=19.5, ry_south=9.0, zh=21.5, seed=sd, ramp_idx=1, power=3.15, flat_crown=0.56, cragginess=0.18, strata_angle=0.05, strata_period=5.2, strata_step=2.6, plate_scale=6.0))
        lobes.append(RockLobe(fx - 4.5, cy - 5.5, rx=22.5, ry_north=23.0, ry_south=8.2, zh=33.5, seed=sd + 23, lobe_id=1, ramp_idx=0, power=3.05, tilt_x=-0.08, flat_crown=0.58, cragginess=0.19, strata_angle=0.05, strata_period=5.2, strata_step=2.6, plate_scale=5.6))
        lobes.append(RockLobe(fx - 8.0, cy - 12.0, rx=14.5, ry_north=14.5, ry_south=6.2, zh=40.0, seed=sd + 41, lobe_id=2, ramp_idx=2, power=2.95, flat_crown=0.60, cragginess=0.18, strata_angle=0.05, strata_period=5.2, strata_step=2.2, plate_scale=5.0))
        lobes.append(RockLobe(fx + 18.0, fy - 4.5, rx=10.5, ry_north=10.0, ry_south=4.6, zh=14.5, seed=sd + 59, lobe_id=3, ramp_idx=0, power=2.7, cragginess=0.20, plate_scale=4.5))
        cleaves.append((fx - 8.0, cy - 13.0, -0.56, -0.48, 0.67, 10.2))

    elif key == "s3_c":
        # Tilted hogback greywacke outcrop (3 weathered dipping rock ribs — organic, craggy, zero diamond crystal!)
        cy = fy - bhh * 0.80
        lobes.append(RockLobe(fx - 9.0, cy - 3.0, rx=19.5, ry_north=29.0, ry_south=8.2, zh=37.5, seed=sd, ramp_idx=1, power=2.85, tilt_x=0.22, tilt_y=-0.12, flat_crown=0.64, cragginess=0.22, strata_angle=-0.34, strata_period=5.0, strata_step=2.5, plate_scale=5.5))
        lobes.append(RockLobe(fx + 8.5, cy + 0.5, rx=18.0, ry_north=24.5, ry_south=7.8, zh=30.5, seed=sd + 19, lobe_id=1, ramp_idx=0, power=2.85, tilt_x=0.22, tilt_y=-0.12, flat_crown=0.65, cragginess=0.21, strata_angle=-0.34, strata_period=5.0, strata_step=2.4, plate_scale=5.2, vein=True))
        lobes.append(RockLobe(fx + 19.5, fy - 4.5, rx=10.5, ry_north=12.5, ry_south=4.8, zh=17.0, seed=sd + 37, lobe_id=2, ramp_idx=2, power=2.75, tilt_x=0.20, strata_angle=-0.34, strata_period=4.8, strata_step=2.0, plate_scale=4.5))
        cleaves.append((fx - 6.0, cy - 11.0, 0.54, -0.50, 0.68, 9.8))

    elif key == "s4_a":
        # Massive multi-tiered Glimmtal Highland Tor (broad tabular caprock + stepped boulders + embedded talus toes!)
        cy = fy - bhh * 0.86
        # Broad weathered bedrock plinth
        lobes.append(RockLobe(fx, cy + 4.5, rx=40.5, ry_north=22.5, ry_south=11.0, zh=23.0, seed=sd, ramp_idx=1, power=3.0, flat_crown=0.58, cragginess=0.20, strata_angle=0.07, strata_period=6.0, strata_step=2.5, plate_scale=6.2))
        # Flanking mid-tier craggy shoulders
        lobes.append(RockLobe(fx - 17.5, cy - 2.5, rx=23.5, ry_north=28.5, ry_south=9.2, zh=38.5, seed=sd + 17, lobe_id=1, ramp_idx=0, power=2.85, tilt_x=-0.10, flat_crown=0.62, cragginess=0.22, strata_angle=0.07, strata_period=6.0, strata_step=2.6, plate_scale=5.8))
        lobes.append(RockLobe(fx + 18.0, cy + 0.0, rx=22.5, ry_north=24.5, ry_south=9.0, zh=33.0, seed=sd + 31, lobe_id=2, ramp_idx=2, power=2.85, tilt_x=0.12, flat_crown=0.63, cragginess=0.21, strata_angle=0.07, strata_period=6.0, strata_step=2.4, plate_scale=5.6, vein=True))
        # Broad tabular weathered caprock summit (rounded-rectangular highland tor crown, NEVER a sharp pyramid point!)
        lobes.append(RockLobe(fx - 3.0, cy - 10.5, rx=22.0, ry_north=36.0, ry_south=10.0, zh=51.0, seed=sd + 47, lobe_id=3, ramp_idx=0, power=2.95, tilt_x=-0.06, flat_crown=0.60, cragginess=0.21, strata_angle=0.07, strata_period=6.2, strata_step=2.6, plate_scale=5.8))
        # Nestled outer foot boulders
        lobes.append(RockLobe(fx - 31.5, fy - 5.0, rx=11.5, ry_north=11.5, ry_south=4.8, zh=16.5, seed=sd + 61, lobe_id=4, ramp_idx=2, power=2.6, cragginess=0.22, plate_scale=4.6))
        lobes.append(RockLobe(fx + 31.0, fy - 4.5, rx=12.0, ry_north=11.0, ry_south=4.8, zh=15.5, seed=sd + 73, lobe_id=5, ramp_idx=1, power=2.6, cragginess=0.22, plate_scale=4.6))
        cleaves.append((fx - 5.0, cy - 19.0, -0.54, -0.50, 0.68, 13.5))

    elif key == "s4_b":
        # Ancient frost-split erratic massif (two gnarled rounded-tabular stone domes divided by a deep mossy ravine!)
        cy = fy - bhh * 0.86
        lobes.append(RockLobe(fx - 17.5, cy - 5.0, rx=23.5, ry_north=38.5, ry_south=10.2, zh=49.5, seed=sd, ramp_idx=0, power=2.75, tilt_x=-0.12, flat_crown=0.62, cragginess=0.23, strata_angle=0.14, strata_period=6.2, strata_step=2.4, plate_scale=5.8, vein=True))
        lobes.append(RockLobe(fx + 17.5, cy - 2.5, rx=22.8, ry_north=34.5, ry_south=10.0, zh=44.0, seed=sd + 23, lobe_id=1, ramp_idx=1, power=2.75, tilt_x=0.14, flat_crown=0.63, cragginess=0.23, strata_angle=0.14, strata_period=6.2, strata_step=2.4, plate_scale=5.8))
        # Deep central ravine threshold saddle & nested boulders (solidly grounded into earth at fy!)
        lobes.append(RockLobe(fx - 2.0, fy - 4.2, rx=24.5, ry_north=20.0, ry_south=6.2, zh=24.0, seed=sd + 41, lobe_id=2, ramp_idx=2, power=2.8, flat_crown=0.64, cragginess=0.16, strata_angle=0.14, strata_period=5.8, strata_step=1.8, plate_scale=5.0))
        lobes.append(RockLobe(fx - 31.0, fy - 5.0, rx=11.8, ry_north=13.5, ry_south=5.0, zh=19.0, seed=sd + 59, lobe_id=3, ramp_idx=1, power=2.65, cragginess=0.21, plate_scale=4.6))
        lobes.append(RockLobe(fx + 31.0, fy - 4.8, rx=11.8, ry_north=12.0, ry_south=4.8, zh=17.0, seed=sd + 71, lobe_id=4, ramp_idx=0, power=2.65, cragginess=0.21, plate_scale=4.6))
        cleaves.append((fx - 17.0, cy - 15.0, -0.54, -0.48, 0.69, 12.5))
        cleaves.append((fx + 17.0, cy - 13.0, 0.52, -0.50, 0.69, 11.8))

    return lobes, cleaves


def calibrate_chipped_field(
    fw: int,
    fh: int,
    lobes: list[RockLobe],
    intact_count: int,
    cleaves: list[tuple[float, float, float, float, float, float]],
) -> dict[str, list[list]]:
    """Tunes cleavage offset so `chipped` (col 2) retains ~73% of `intact` area with crisp split facets."""
    best_field = None
    best_err = 1e9
    for scale in (0.62, 0.76, 0.90, 1.04, 1.18, 1.35, 1.55):
        c_scaled = [(a, b, nx, ny, nz, d * scale) for (a, b, nx, ny, nz, d) in cleaves]
        fld = evaluate_formation(fw, fh, lobes, cleave_planes=c_scaled)
        cnt = sum(sum(1 for v in row if v) for row in fld["mask"])
        ratio = cnt / float(max(1, intact_count))
        err = abs(ratio - 0.73)
        if err < best_err:
            best_err = err
            best_field = fld
    assert best_field is not None
    return best_field


def pack_strip(frames: list[list[list[tuple[int, int, int, int]]]], fw: int, fh: int) -> list[list[tuple[int, int, int, int]]]:
    strip = blank(fw * len(frames), fh)
    for idx, fr in enumerate(frames):
        for y in range(fh):
            strip[y][idx * fw:(idx + 1) * fw] = fr[y][:]
    return strip


def build_single_archetype(spec: dict) -> dict:
    key = spec["key"]
    fw, fh = spec["fw"], spec["fh"]
    fx, fy = spec["fx"], spec["fy"]
    h, hw, bhh = spec["h"], spec["hw"], spec["bhh"]
    sd = spec["seed"]

    lobes, cleaves = build_archetype_lobes(spec)
    intact_field = evaluate_formation(fw, fh, lobes)
    intact_count = sum(sum(1 for v in row if v) for row in intact_field["mask"])
    chipped_field = calibrate_chipped_field(fw, fh, lobes, intact_count, cleaves)

    col_skirt = build_base_skirt(fw, fh, fx, fy, hw, bhh, intact_field["mask"], sd)
    col_intact = render_craggy_rock(fw, fh, lobes, intact_field, fy, sd)
    col_chipped = render_craggy_rock(fw, fh, lobes, chipped_field, fy, sd + 7)

    c1_len = clampi(int(h * 0.42), 4, 24)
    c1_starts = [
        (fx - int(hw * 0.22), fy - int(h * 0.56), 0.95, c1_len),
        (fx + int(hw * 0.24), fy - int(h * 0.40), 2.15, max(4, int(c1_len * 0.75))),
    ]
    col_cracked1 = draw_fracture_network(fw, fh, intact_field["mask"], intact_field["nrm"], c1_starts, deep=False, seed=sd + 13)

    c2_len = clampi(int(h * 0.48), 5, 26)
    c2_starts = [
        (fx - int(hw * 0.15), fy - int(h * 0.44), 1.05, c2_len),
        (fx + int(hw * 0.18), fy - int(h * 0.35), 2.08, int(c2_len * 0.88)),
    ]
    if hw >= 20:
        c2_starts.append((fx, fy - int(h * 0.28), 1.52, int(c2_len * 0.70)))
    col_cracked2 = draw_fracture_network(fw, fh, chipped_field["mask"], chipped_field["nrm"], c2_starts, deep=True, seed=sd + 29)

    col_rubble = build_rubble(fw, fh, fx, fy, hw, bhh, sd + 43)

    col_moss0 = build_moss_overlay(fw, fh, intact_field, lobes, fx, fy, hw, variant=0, seed=sd + 61)
    col_moss1 = build_moss_overlay(fw, fh, intact_field, lobes, fx, fy, hw, variant=1, seed=sd + 73)
    col_lich0 = build_lichen_overlay(fw, fh, intact_field, lobes, fy, variant=0, seed=sd + 89)
    col_lich1 = build_lichen_overlay(fw, fh, intact_field, lobes, fy, variant=1, seed=sd + 97)
    col_ivy0 = build_ivy_overlay(fw, fh, intact_field, fx, fy, hw, h, variant=0, seed=sd + 109)
    col_ivy1 = build_ivy_overlay(fw, fh, intact_field, fx, fy, hw, h, variant=1, seed=sd + 127)
    col_fern0 = build_fern_or_succulent_overlay(fw, fh, intact_field, fx, fy, hw, h, variant=0, seed=sd + 139)
    col_fern1 = build_fern_or_succulent_overlay(fw, fh, intact_field, fx, fy, hw, h, variant=1, seed=sd + 151)
    col_fungi, col_glow = build_fungi_and_glow(fw, fh, intact_field, fx, fy, hw, seed=sd + 167)

    cols = [
        col_skirt, col_intact, col_chipped, col_cracked1, col_cracked2, col_rubble,
        col_moss0, col_moss1, col_lich0, col_lich1, col_ivy0, col_ivy1, col_fern0, col_fern1, col_fungi,
    ]
    assert len(cols) == 15

    write_png(OUT_ROCKS / f"{key}.png", fw * 15, fh, pack_strip(cols, fw, fh))
    write_png(OUT_ROCKS / f"{key}_glow.png", fw * 1, fh, col_glow)

    return {
        "frame_w": fw,
        "frame_h": fh,
        "feet_x": fx,
        "feet_y": fy,
        "height_px": h,
        "half_w_px": hw,
        "body_half_h_px": bhh,
        "sheet": f"res://assets/props/valley_stone/{key}.png",
        "glow_sheet": f"res://assets/props/valley_stone/{key}_glow.png",
        "num_cols": 15,
        "glow_cols": 1,
        "layers": {
            "base_skirt": 0,
            "intact": 1,
            "chipped": 2,
            "cracked_1": 3,
            "cracked_2": 4,
            "rubble": 5,
        },
        "traits": {
            "moss": [6, 7],
            "lichen": [8, 9],
            "ivy": [10, 11],
            "fern": [12, 13],
            "fungi": [14],
        },
        "fungi_glow_col": 0,
    }


# ---------------------------------------------------------------------------
# Ground Details Atlas (assets/tiles/rock_ground_details.png + _glow.png, 384x20)
# Flush, ground-sunk stone plates, weathered chips, mossy cobbles, ferns & Sempervivum
# ---------------------------------------------------------------------------
def draw_mini_stone(
    px: list[list[tuple[int, int, int, int]]],
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    zh: float,
    seed: int,
    ramp_idx: int = 0,
    flat_slab: bool = False,
) -> list[list[bool]]:
    w, h = len(px[0]), len(px)
    lb = RockLobe(
        cx=cx, cy=cy, rx=rx, ry_north=ry, ry_south=ry * 0.80, zh=zh,
        seed=seed, ramp_idx=ramp_idx, power=3.0 if flat_slab else 2.6,
        flat_crown=0.58 if flat_slab else 0.68, cragginess=0.18,
        strata_step=1.1 if flat_slab else 0.0, strata_period=3.2, plate_scale=3.8,
    )
    fld = evaluate_formation(w, h, [lb])
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not fld["mask"][y][x] and fld["mask"][y - 1][x]:
                put_shadow(px, x, y, 64)
                if x + 1 < w and not fld["mask"][y][x + 1]:
                    put_shadow(px, x + 1, y, 42)
    sub = render_craggy_rock(w, h, [lb], fld, int(cy + ry + 1), seed + 5, ground_soft=True)
    blit(px, sub, 0, 0)
    return fld["mask"]


def build_rock_ground_details() -> None:
    cw, ch, n_cells = 24, 20, 16
    cells = [blank(cw, ch) for _ in range(n_cells)]
    glows = [blank(cw, ch) for _ in range(n_cells)]

    # 0..2: Weathered limestone/slate chips & loose scree flakes
    draw_mini_stone(cells[0], 9.5, 11.0, 4.2, 2.8, 4.2, 801, ramp_idx=0)
    draw_mini_stone(cells[0], 16.5, 13.0, 2.8, 2.0, 3.2, 803, ramp_idx=1)

    draw_mini_stone(cells[1], 12.0, 10.5, 4.8, 2.6, 4.0, 811, ramp_idx=2)
    draw_mini_stone(cells[1], 6.5, 13.5, 2.6, 1.8, 3.0, 813, ramp_idx=0)

    for sx, sy, r, sd, ri in ((7.5, 10.2, 3.0, 821, 1), (13.5, 12.5, 3.4, 823, 0), (17.5, 9.6, 2.4, 827, 2)):
        draw_mini_stone(cells[2], sx, sy, r, r * 0.72, 3.4, sd, ramp_idx=ri)

    # 3..5: Sunken weathered limestone plates (matching Square 2 stepping stones!)
    draw_mini_stone(cells[3], 12.0, 11.2, 7.4, 4.0, 3.6, 831, ramp_idx=0, flat_slab=True)
    draw_mini_stone(cells[4], 10.0, 11.5, 6.0, 3.5, 3.5, 841, ramp_idx=2, flat_slab=True)
    draw_mini_stone(cells[4], 17.2, 12.8, 3.6, 2.4, 3.0, 843, ramp_idx=1, flat_slab=True)
    draw_mini_stone(cells[5], 12.5, 11.5, 6.8, 3.8, 3.5, 851, ramp_idx=1, flat_slab=True)
    for k in range(5):
        put(cells[5], 10 + k, 9 + k // 2, RAMP_SLATE[1])
        put(cells[5], 10 + k, 10 + k // 2, RAMP_SLATE[6])

    # 6..8: Moss-cushioned cobble clusters
    for idx, layout in enumerate([
        [(10.5, 11.0, 4.8, 3.3, 4.8, 0), (16.5, 12.5, 3.0, 2.2, 3.6, 1)],
        [(13.5, 10.8, 4.6, 3.2, 4.6, 2), (7.5, 12.2, 3.4, 2.4, 3.8, 0)],
        [(11.5, 10.5, 4.2, 3.0, 4.4, 1), (16.8, 11.8, 3.0, 2.2, 3.4, 0), (7.2, 12.8, 2.6, 1.9, 3.0, 2)],
    ]):
        ci = 6 + idx
        for bi, (cx, cy, rx, ry, zh, ri) in enumerate(layout):
            m = draw_mini_stone(cells[ci], cx, cy, rx, ry, zh, 860 + ci * 13 + bi * 5, ramp_idx=ri)
            if bi == 0:
                for y in range(4, 15):
                    for x in range(4, 20):
                        if m[y][x] and y <= cy and x <= cx + 1:
                            put(cells[ci], x, y, MOSS[3 if (x + y) % 2 == 0 else 2])
                            if y - 1 >= 1 and not m[y - 1][x]:
                                put(cells[ci], x, y - 1, OUT_TOP_MOSS)
        put(cells[ci], 12, 14, MOSS[2])
        put(cells[ci], 13, 14, MOSS[1])

    # 9..10: Lichen-rosette flat slab + highland sedge wisps
    for ci, sd in ((9, 901), (10, 919)):
        m = draw_mini_stone(cells[ci], 11.5 if ci == 9 else 12.5, 12.0, 6.6, 3.7, 3.6, sd, ramp_idx=0 if ci == 9 else 2, flat_slab=True)
        pal = LICHEN_SAGE if ci == 9 else LICHEN_OCHRE
        lx, ly = (10, 11) if ci == 9 else (13, 11)
        for dx, dy, tone in ((0, 0, 0), (-1, 0, 2), (0, -1, 3), (1, 0, 1)):
            if m[ly + dy][lx + dx]:
                put(cells[ci], lx + dx, ly + dy, pal[tone])
        sx = 17 if ci == 9 else 6
        dir_x = 1 if ci == 9 else -1
        for h_i in range(5):
            put(cells[ci], sx + (h_i // 2) * dir_x, 12 - h_i, SEDGE[min(3, h_i // 2 + 1)])
        for h_i in range(4):
            put(cells[ci], sx - dir_x + (h_i // 3) * dir_x, 13 - h_i, SEDGE[min(2, (h_i + 1) // 2)])

    # 11..12: Crevice spleenwort fern tufts
    draw_mini_stone(cells[11], 12.5, 13.5, 4.5, 2.5, 3.6, 931, ramp_idx=1)
    draw_fern_tuft(cells[11], 11, 12, 0.86, 933)

    draw_mini_stone(cells[12], 12.0, 13.5, 4.8, 2.6, 3.8, 941, ramp_idx=0)
    draw_fern_tuft(cells[12], 12, 12, 0.94, 943)
    put(cells[12], 9, 9, GLOW_TEAL_MID)
    put(cells[12], 15, 10, GLOW_TEAL_DIM)
    put(glows[12], 9, 9, GLOW_TEAL_HI)
    put(glows[12], 15, 10, GLOW_TEAL_MID)

    # 13..14: Mountain houseleek (Sempervivum) rosettes
    draw_mini_stone(cells[13], 13.5, 12.5, 4.2, 2.6, 3.6, 951, ramp_idx=2)
    draw_houseleek_rosette(cells[13], 10, 11, 3)
    draw_houseleek_rosette(cells[13], 14, 13, 2)

    draw_houseleek_rosette(cells[14], 11, 10, 3)
    draw_houseleek_rosette(cells[14], 7, 12, 2)
    draw_houseleek_rosette(cells[14], 15, 12, 2)

    # 15: Crevice quartz crystal & twilight spore cluster
    draw_mini_stone(cells[15], 10.5, 12.0, 4.5, 2.8, 4.0, 971, ramp_idx=1)
    for dx, dy, qc in ((0, 0, QUARTZ_VEIN[1]), (-1, 0, QUARTZ_VEIN[2]), (0, -1, QUARTZ_VEIN[2]), (1, 0, QUARTZ_VEIN[0]), (0, 1, OUT_GROUND_BOT)):
        put(cells[15], 14 + dx, 11 + dy, qc)
    put(cells[15], 8, 13, FUNGI_DAY[4])
    put(cells[15], 9, 13, FUNGI_DAY[2])
    put(cells[15], 15, 13, FUNGI_DAY[4])
    put(glows[15], 8, 13, GLOW_TEAL_HI)
    put(glows[15], 15, 13, GLOW_TEAL_MID)

    write_png(OUT_DETAILS, cw * n_cells, ch, pack_strip(cells, cw, ch))
    write_png(OUT_DETAILS_GLOW, cw * n_cells, ch, pack_strip(glows, cw, ch))


# ---------------------------------------------------------------------------
# Disk Verification & 2x QA Showcase Sheet (docs/img/valley_stone_sheet.png)
# ---------------------------------------------------------------------------
def read_png_frames(path: pathlib.Path, fw: int, fh: int, ncols: int) -> list[list[list[tuple[int, int, int, int]]]]:
    raw = path.read_bytes()
    pos = 8
    idat = bytearray()
    ihdr_w, ihdr_h = 0, 0
    while pos < len(raw):
        ln = struct.unpack(">I", raw[pos:pos + 4])[0]
        tag = raw[pos + 4:pos + 8]
        chunk_data = raw[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            ihdr_w, ihdr_h = struct.unpack(">II", chunk_data[:8])
        elif tag == b"IDAT":
            idat.extend(chunk_data)
        pos += 12 + ln
    assert ihdr_w == fw * ncols and ihdr_h == fh, f"Dimension mismatch in {path}"
    dec = zlib.decompress(bytes(idat))
    stride = 1 + ihdr_w * 4
    frames = [blank(fw, fh) for _ in range(ncols)]
    for y in range(fh):
        assert dec[y * stride] == 0
        row = dec[y * stride + 1:(y + 1) * stride]
        for x in range(ihdr_w):
            p = x * 4
            rgba = (row[p], row[p + 1], row[p + 2], row[p + 3])
            if rgba[3] > 0 and rgba[0] == 0 and rgba[1] == 0 and rgba[2] == 0:
                raise RuntimeError(f"Forbidden pure #000000 pixel in {path} at ({x}, {y})!")
            frames[x // fw][y][x % fw] = rgba
    return frames


def tint_night(fr: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    out = blank(len(fr[0]), len(fr))
    for y in range(len(fr)):
        for x in range(len(fr[0])):
            p = fr[y][x]
            if p[3] > 0:
                if p[:3] == CONTACT_RGB:
                    out[y][x] = (12, 18, 26, min(120, int(p[3] * 1.1)))
                else:
                    out[y][x] = (
                        max(10, int(p[0] * 0.34)),
                        max(14, int(p[1] * 0.40)),
                        max(24, int(p[2] * 0.54)),
                        p[3],
                    )
    return out


def composite_rock(dst: list, ox: int, oy: int, frames: list, glows: list, state: str = "intact", trait_cols: list[int] | None = None, night: bool = False) -> None:
    if state == "intact":
        order = [0, 1] + (trait_cols or [])
    elif state == "cracked_1":
        order = [0, 1, 3] + (trait_cols or [])
    elif state == "chipped":
        order = [0, 2]
    elif state == "cracked_2":
        order = [0, 2, 4]
    else:
        order = [0, 5]
    for ci in order:
        blit(dst, tint_night(frames[ci]) if night else frames[ci], ox, oy)
    if night and trait_cols and 14 in trait_cols and glows:
        blit(dst, glows[0], ox, oy)


def scale_nearest_2x(src: list[list[tuple[int, int, int, int]]]) -> list[list[tuple[int, int, int, int]]]:
    sh, sw = len(src), len(src[0])
    dst = blank(sw * 2, sh * 2)
    for y in range(sh):
        r0, r1 = dst[y * 2], dst[y * 2 + 1]
        srow = src[y]
        for x in range(sw):
            c = srow[x]
            r0[x * 2] = c
            r0[x * 2 + 1] = c
            r1[x * 2] = c
            r1[x * 2 + 1] = c
    return dst


def build_qa_showcase(rig: dict) -> None:
    lw, lh = 760, 436
    canvas = blank(lw, lh)
    day_bg = [hexc("25493b"), hexc("2d5643"), hexc("36654c"), hexc("407354")]
    night_bg = [hexc("101725"), hexc("131c2c"), hexc("172234")]
    split_y = 244

    for y in range(lh):
        for x in range(lw):
            v = 0.65 * vnoise(x * 0.09, y * 0.11, 777) + 0.35 * vnoise(x * 0.24, y * 0.24, 911)
            if y < split_y:
                canvas[y][x] = day_bg[clampi(int(v * 4.1), 0, 3)]
            elif y == split_y:
                canvas[y][x] = hexc("1b2434")
            else:
                canvas[y][x] = night_bg[clampi(int(v * 3.1), 0, 2)]

    loaded: dict[str, tuple[list, list]] = {}
    for key, r in rig.items():
        fw, fh = r["frame_w"], r["frame_h"]
        loaded[key] = (
            read_png_frames(OUT_ROCKS / f"{key}.png", fw, fh, 15),
            read_png_frames(OUT_ROCKS / f"{key}_glow.png", fw, fh, 1),
        )
    det_frames = read_png_frames(OUT_DETAILS, 24, 20, 16)
    det_glows = read_png_frames(OUT_DETAILS_GLOW, 24, 20, 16)

    for ci in range(16):
        dx = 18 + ci * 45
        blit(canvas, det_frames[ci], dx, 8)
        blit(canvas, tint_night(det_frames[ci]), dx, split_y + 8)
        blit(canvas, det_glows[ci], dx, split_y + 8)

    row1 = [
        ("s0_a", 24, "intact", [6, 8]),
        ("s0_b", 66, "intact", [7, 9]),
        ("s1_a", 112, "intact", [6, 8, 14]),
        ("s1_b", 168, "intact", [7, 9, 13]),
        ("s2_a", 228, "intact", [6, 8, 10, 12, 14]),
        ("s2_b", 304, "intact", [7, 9, 13, 14]),
        ("s2_c", 380, "intact", [6, 8, 11, 12]),
        ("s2_a", 462, "cracked_1", [6, 8]),
        ("s2_a", 538, "chipped", []),
        ("s2_a", 614, "cracked_2", []),
        ("s2_a", 688, "rubble", []),
    ]
    for key, ox, st, tr in row1:
        fr, gl = loaded[key]
        fy = rig[key]["feet_y"]
        composite_rock(canvas, ox, 92 - fy, fr, gl, state=st, trait_cols=tr, night=False)

    row2 = [
        ("s3_a", 20, "intact", [6, 8, 10, 12, 14]),
        ("s3_b", 122, "intact", [7, 9, 13, 14]),
        ("s3_c", 224, "intact", [6, 9, 11, 12]),
        ("s4_a", 328, "intact", [6, 8, 10, 12, 14]),
        ("s4_b", 462, "intact", [7, 8, 11, 13, 14]),
        ("s3_a", 596, "chipped", []),
        ("s3_a", 680, "rubble", []),
    ]
    for key, ox, st, tr in row2:
        fr, gl = loaded[key]
        fy = rig[key]["feet_y"]
        composite_rock(canvas, ox, 228 - fy, fr, gl, state=st, trait_cols=tr, night=False)

    night_row = [
        ("s0_a", 18, [6]),
        ("s1_a", 64, [6, 14]),
        ("s1_b", 124, [7, 13, 14]),
        ("s2_b", 188, [7, 9, 14]),
        ("s2_c", 268, [6, 11, 14]),
        ("s3_a", 352, [6, 8, 10, 12, 14]),
        ("s3_b", 456, [7, 9, 13, 14]),
        ("s4_a", 556, [6, 8, 10, 12, 14]),
    ]
    for key, ox, tr in night_row:
        fr, gl = loaded[key]
        fy = rig[key]["feet_y"]
        composite_rock(canvas, ox, 424 - fy, fr, gl, state="intact", trait_cols=tr, night=True)

    write_png(OUT_SHEET, lw * 2, lh * 2, scale_nearest_2x(canvas))


def main() -> None:
    OUT_ROCKS.mkdir(parents=True, exist_ok=True)
    OUT_DETAILS.parent.mkdir(parents=True, exist_ok=True)
    OUT_RIG.parent.mkdir(parents=True, exist_ok=True)
    OUT_SHEET.parent.mkdir(parents=True, exist_ok=True)

    build_rock_ground_details()
    rig: dict[str, dict] = {}
    for spec in ARCHETYPES:
        rig[spec["key"]] = build_single_archetype(spec)

    OUT_RIG.write_text(json.dumps(rig, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    build_qa_showcase(rig)
    print(f"Generated {len(rig)} Glimmtal-Fels 2.0 archetypes, 16 ground details, rig JSON, and 2x QA sheet.")


if __name__ == "__main__":
    main()
