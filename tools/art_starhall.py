#!/usr/bin/env python3
"""Procedural pixel-art generator for the Star Hall ("Der Sternensaal", docs/sternensaal_konzept.md).

Generates crisp, top-left lit pixel art with cool-violet marble shadows, antique gold filigree,
unlit turquoise starlight glow masks, Waystone-style Bayer-dithered translucent halos, and
floating 3D underside stone spikes:

  assets/interior/starhall/
    floor_base.png, floor_glow.png          (560 x 820)
    throne.png, throne_glow.png             (8 frames x 160 x 176 = 1280 x 176, foot (80, 148))
    pylon.png, pylon_glow.png               (8 frames x 48 x 96 = 384 x 96, foot (24, 84))
    balustrade.png, balustrade_glow.png     (48 x 36, foot (24, 32))
    return_seal.png, return_seal_glow.png   (8 frames x 64 x 44 = 512 x 44, center (32, 24))
    relic_plinth.png, relic_plinth_glow.png (8 frames x 36 x 52 = 288 x 52, foot (18, 44))
    cosmos_island_0..2.png + *_glow.png     (96x72, 64x52, 44x38)
    star_mote.png                           (4 frames x 8 x 8 = 32 x 8)

Usage:
    py -3 tools/art_starhall.py [optional_preview.png]
"""
from __future__ import annotations

import math
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent / "assets"
OUT = ROOT / "interior" / "starhall"


def rgb(h: str) -> tuple[int, int, int]:
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# ---------------------------------------------------------------------------
# Palettes (docs/sternensaal_konzept.md & docs/design_guide.md)
# ---------------------------------------------------------------------------
INK_MARBLE = rgb("17142a")
INK_ABYSS = rgb("0b0818")
INK_GOLD = rgb("3c2812")
INK_PLUM = rgb("120d22")
INK_TEAL = rgb("164b56")

# Pale moon-violet marble (dark -> bright)
MARBLE = [
    rgb("2f2d4b"),  # 0: deep cool-violet shadow
    rgb("504e7c"),  # 1: mid-shadow marble
    rgb("8583ae"),  # 2: base moon marble
    rgb("b4b2d6"),  # 3: lit marble face
    rgb("d4d2ea"),  # 4: polished top-left bevel
    rgb("e9e3f7"),  # 5: star-ivory specular glint
]

# Floating cliff / underside stone (dark -> light)
CLIFF = [
    rgb("141024"),  # 0: deep underside shadow
    rgb("221d3a"),  # 1: dark violet cliff
    rgb("3a365c"),  # 2: lit cliff facet
    rgb("504e7c"),  # 3: sharp upper-left ridge
]

# Antique gold filigree (dark -> light)
GOLD = [
    rgb("6f5020"),  # 0: deep bronze-gold shadow
    rgb("b48a38"),  # 1: rich antique gold
    rgb("e6c468"),  # 2: bright starlit gold
    rgb("fff0b0"),  # 3: gleaming pale-gold highlight
]

# Unlit turquoise starlight & leylines (dark -> core)
TEAL = [
    rgb("2a8c94"),  # 0: deep star-teal
    rgb("3cc0c6"),  # 1: glowing turquoise
    rgb("78f4e6"),  # 2: bright cyan glow
    rgb("d0fff8"),  # 3: pure starlight white-cyan core
]

# Night-plum velvet / tapestry & astral violet
PLUM = [
    rgb("130f26"),
    rgb("1e1a36"),
    rgb("34284e"),
    rgb("4a4180"),
]

ASTRAL = [
    rgb("34185e"),
    rgb("6636ad"),
    rgb("9468ee"),
    rgb("cbaaff"),
]

SAPPHIRE = [
    rgb("080716"),
    rgb("10132c"),
    rgb("192446"),
    rgb("243a5e"),
]

BAYER4 = (
    np.array(
        [
            [0, 8, 2, 10],
            [12, 4, 14, 6],
            [3, 11, 1, 9],
            [15, 7, 13, 5],
        ],
        dtype=np.float32,
    )
    / 16.0
)


def save_png(path: pathlib.Path, arr: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(path)


def vhash(x: np.ndarray | int, y: np.ndarray | int, seed: int = 0) -> np.ndarray:
    xa = np.asarray(x, dtype=np.int64)
    ya = np.asarray(y, dtype=np.int64)
    n = (xa * 73856093) ^ (ya * 19349663) ^ (seed * 83492791)
    n = ((n ^ (n >> 13)) & 0xFFFFFFFF) * 1274126177
    return (((n ^ (n >> 16)) & 0xFFFF) / 65536.0).astype(np.float32)


def ihhash(a: int, b: int, seed: int = 0) -> float:
    n = (a * 73856093) ^ (b * 19349663) ^ (seed * 83492791)
    n = ((n ^ (n >> 13)) & 0xFFFFFFFF) * 1274126177
    return float(((n ^ (n >> 16)) & 0xFFFF) / 65536.0)


def put_px(
    img: np.ndarray,
    x: int,
    y: int,
    col: tuple[int, int, int],
    alpha: int = 255,
) -> None:
    h, w = img.shape[:2]
    if 0 <= x < w and 0 <= y < h:
        if alpha >= 255 or img[y, x, 3] == 0:
            img[y, x] = (col[0], col[1], col[2], alpha)
        else:
            a = alpha / 255.0
            img[y, x, :3] = (img[y, x, :3] * (1.0 - a) + np.array(col) * a).astype(np.uint8)
            img[y, x, 3] = max(int(img[y, x, 3]), alpha)


def draw_line(
    img: np.ndarray,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    col: tuple[int, int, int],
    thick: int = 1,
) -> None:
    steps = max(1, int(round(max(abs(x1 - x0), abs(y1 - y0)))))
    for i in range(steps + 1):
        t = i / steps
        px = int(round(x0 + (x1 - x0) * t))
        py = int(round(y0 + (y1 - y0) * t))
        if thick <= 1:
            put_px(img, px, py, col)
        else:
            r = thick // 2
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if abs(dx) + abs(dy) <= r + (1 if thick >= 3 else 0):
                        put_px(img, px + dx, py + dy, col)


def add_waystone_halo(
    glow: np.ndarray,
    body_mask: np.ndarray | None = None,
    radius: int = 5,
    max_alpha: int = 165,
) -> None:
    """Adds a tight Waystone-style Bayer-dithered translucent halo around emissive core pixels."""
    h, w = glow.shape[:2]
    core = glow[..., 3] >= 220
    if not np.any(core):
        return
    near = np.zeros((h, w), dtype=np.float32)
    r_f = float(radius) + 0.4
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx == 0 and dy == 0:
                continue
            d = math.hypot(dx, dy)
            if d <= r_f:
                # Zero-padded shift (no wrap-around across frame edges!)
                shifted = np.zeros_like(core)
                sy0, sy1 = max(0, dy), min(h, h + dy)
                dy0, dy1 = max(0, -dy), min(h, h - dy)
                sx0, sx1 = max(0, dx), min(w, w + dx)
                dx0, dx1 = max(0, -dx), min(w, w - dx)
                shifted[dy0:dy1, dx0:dx1] = core[sy0:sy1, sx0:sx1]
                near = np.maximum(near, shifted.astype(np.float32) * (1.0 - d / (r_f + 0.35)))

    ys, xs = np.mgrid[0:h, 0:w]
    b = BAYER4[ys % 4, xs % 4]
    allowed = ~core
    if body_mask is not None:
        allowed &= ~body_mask
    hit = allowed & (near > b * 0.88 + 0.06)
    alphas = np.clip((55.0 + (max_alpha - 55.0) * near), 0, max_alpha).astype(np.uint8)
    warm_mix = ((xs * 3 + ys) % 6) == 0
    glow[hit & ~warm_mix, 0] = 96
    glow[hit & ~warm_mix, 1] = 216
    glow[hit & ~warm_mix, 2] = 232
    glow[hit & warm_mix, 0] = 210
    glow[hit & warm_mix, 1] = 192
    glow[hit & warm_mix, 2] = 255
    glow[hit, 3] = np.maximum(glow[hit, 3], alphas[hit])


def add_soft_floor_bloom(
    glow: np.ndarray,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    max_alpha: int = 95,
) -> None:
    """Subtle Bayer-dithered translucent floor glow pool around runes/sockets."""
    h, w = glow.shape[:2]
    x0, x1 = max(0, int(cx - rx - 1)), min(w, int(cx + rx + 2))
    y0, y1 = max(0, int(cy - ry - 1)), min(h, int(cy + ry + 2))
    if x0 >= x1 or y0 >= y1:
        return
    ys, xs = np.mgrid[y0:y1, x0:x1]
    d = np.hypot((xs - cx) / max(rx, 1.0), (ys - cy) / max(ry, 1.0))
    fall = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
    b = BAYER4[ys % 4, xs % 4]
    sub = glow[y0:y1, x0:x1]
    hit = (d <= 1.0) & (fall > b * 0.9 + 0.08) & (sub[..., 3] < 200)
    alphas = np.clip(fall * max_alpha, 28, max_alpha).astype(np.uint8)
    sub[hit, 0] = TEAL[1][0]
    sub[hit, 1] = TEAL[1][1]
    sub[hit, 2] = TEAL[1][2]
    sub[hit, 3] = np.maximum(sub[hit, 3], alphas[hit])


def apply_tinted_outline(
    img: np.ndarray,
    ink: tuple[int, int, int] = INK_MARBLE,
) -> None:
    """Adds a 1 px tinted outline outside opaque pixels without touching interior pixels."""
    opaque = img[..., 3] >= 200
    pad = np.pad(opaque, 1, mode="constant", constant_values=False)
    nbr = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    rim = nbr & (img[..., 3] == 0)
    img[rim] = (*ink, 255)


def draw_star_spark(
    img: np.ndarray,
    cx: int,
    cy: int,
    size: int,
    core: tuple[int, int, int],
    arm: tuple[int, int, int],
    tip: tuple[int, int, int] | None = None,
) -> None:
    """Crisp pixel star (size 0 = 1x1, 1 = 3x3 cross, 2 = 5x5 cross, 3 = 7x7 radiant star)."""
    put_px(img, cx, cy, core)
    if size >= 1:
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            put_px(img, cx + dx, cy + dy, arm)
    if size >= 2:
        tcol = tip if tip is not None else arm
        for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
            put_px(img, cx + dx, cy + dy, tcol)
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            put_px(img, cx + dx, cy + dy, tcol)
    if size >= 3:
        tcol = tip if tip is not None else arm
        for dx, dy in ((-3, 0), (3, 0), (0, -3), (0, 3)):
            put_px(img, cx + dx, cy + dy, tcol)


def cylindrical_marble_shade(
    ox: int,
    hw: int,
    flutes: int = 3,
    overhang_ao: float = 0.0,
    y_var: float = 0.0,
) -> tuple[int, int, int]:
    """5-tone cylindrical wrap-around top-left marble shading with carved vertical Kanneluren & bounce light."""
    nx = max(-1.0, min(1.0, ox / max(1.0, float(hw))))
    nz = math.sqrt(max(0.05, 1.0 - nx * nx))
    # Top-left primary light + subtle cool-indigo sky bounce on the right rim
    lam = -0.74 * nx + 0.62 * nz + 0.14
    bounce = 0.22 * max(0.0, nx - 0.55)
    flute_wave = 0.0
    if flutes > 0 and abs(nx) < 0.88:
        flute_wave = -0.78 * math.sin(nx * math.pi * flutes - 0.35)
    score = 2.05 + (lam * 1.95) + bounce + flute_wave - overhang_ao + y_var
    if abs(ox) == hw and nx > 0.45:
        score -= 0.75
    return MARBLE[max(0, min(5, int(round(score))))]


def cylindrical_gold_shade(
    ox: int,
    hw: int,
    overhang_ao: float = 0.0,
    band_hi: float = 0.0,
) -> tuple[int, int, int]:
    """4-tone metallic gold shading with sharp specular highlight ridge and warm bronze core shadow."""
    nx = max(-1.0, min(1.0, ox / max(1.0, float(hw))))
    nz = math.sqrt(max(0.05, 1.0 - nx * nx))
    spec = math.exp(-((nx + 0.38) / 0.26) ** 2) * 1.15
    lam = -0.68 * nx + 0.55 * nz
    score = 1.15 + lam * 1.25 + spec + band_hi - overhang_ao
    return GOLD[max(0, min(3, int(round(score))))]


def draw_floor_shadow_ellipse(
    base: np.ndarray,
    top_mask: np.ndarray,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    strength: float = 0.38,
) -> None:
    """Darkens existing marble floor pixels in a soft Bayer-dithered contact shadow ellipse."""
    H, W = base.shape[:2]
    x0, x1 = max(0, int(cx - rx - 1)), min(W, int(cx + rx + 2))
    y0, y1 = max(0, int(cy - ry - 1)), min(H, int(cy + ry + 2))
    for py in range(y0, y1):
        for px in range(x0, x1):
            if not top_mask[py, px]:
                continue
            d = math.hypot((px - cx) / max(rx, 1.0), (py - cy) / max(ry, 1.0))
            if d > 1.0:
                continue
            fall = (1.0 - d) ** 1.35
            if fall * strength > BAYER4[py % 4, px % 4] * 0.55 + 0.08:
                r, g, b, a = base[py, px]
                if a > 0:
                    k = max(0.45, 1.0 - strength * (0.55 + 0.45 * fall))
                    base[py, px] = (int(r * k * 0.92), int(g * k * 0.90), int(b * k * 1.04), int(a))


# ---------------------------------------------------------------------------
# 1. FLOOR BASE & FLOOR GLOW (560 x 820)
# ---------------------------------------------------------------------------
def build_floor() -> tuple[np.ndarray, np.ndarray]:
    W, H = 560, 820
    CX = 280
    ys, xs = np.mgrid[0:H, 0:W]
    dx = xs - CX

    # --- Zone masks (exact coordinates from docs/sternensaal_konzept.md) ---
    # 3. Northern Throne Dais (rx=140, ry=88 around (280, 168), plus royal apse behind throne)
    dais_ell = np.hypot(dx / 140.0, (ys - 168.0) / 88.0) <= 1.0
    apse = (np.hypot(dx / 56.0, (ys - 96.0) / 28.0) <= 1.0) & (ys >= 68)
    dais_ears = (np.abs(dx) <= 146) & (ys >= 156) & (ys <= 202) & (
        np.abs(dx) + np.abs(ys - 179) * 1.1 <= 165
    )
    dais = (dais_ell | apse | dais_ears) & (ys <= 252)

    # 3 broad illuminated steps from Bridge to Dais (Y = 248..272)
    step3 = (ys >= 248) & (ys < 256) & (np.abs(dx) <= 94 - (ys - 248) * 0.5)
    step2 = (ys >= 256) & (ys < 264) & (np.abs(dx) <= 88 - (ys - 256) * 0.5)
    step1 = (ys >= 264) & (ys <= 272) & (np.abs(dx) <= 82 - (ys - 264) * 0.4)
    north_steps = step1 | step2 | step3

    # 2. Open Star Bridge (X = 202..358 => |dx| <= 78, Y = 268..646)
    bridge_walk = (ys >= 268) & (ys <= 646) & (np.abs(dx) <= 78)

    # Sculpted octagonal candelabra buttresses at North (Y=344) & South (Y=612), plus lateral ribs
    piers = np.zeros((H, W), dtype=bool)
    for py, pw in ((310, 83), (344, 92), (612, 92)):
        pier = (
            (np.abs(ys - py) <= 16)
            & (np.abs(dx) <= pw)
            & ((np.abs(dx) - (pw - 14)) + np.abs(ys - py) * 0.85 <= 18)
        )
        piers |= pier

    # Two outswept Side Balconies (Y = 376..584, X = 144..416 => |dx| <= 136)
    # Leaves a graceful 22 px outer marble promenade (144..166 & 394..416) beside the Mirror Basins!
    balc_chamfer = (
        (ys >= 376)
        & (ys <= 584)
        & (np.abs(dx) <= 136)
        & ((np.abs(dx) - 120) + np.maximum(0, 392 - ys) <= 16)
        & ((np.abs(dx) - 120) + np.maximum(0, ys - 568) <= 16)
    )
    # Central balcony buttress ribs at Y = 480 jutting out to |dx| <= 142
    balc_mid_rib = (
        (np.abs(ys - 480) <= 14)
        & (np.abs(dx) <= 142)
        & ((np.abs(dx) - 132) + np.abs(ys - 480) <= 14)
    )

    # 1. Southern Arrival Circle (Y = 640..770, rx=98, ry=58 around (280, 708))
    south_steps = (ys >= 638) & (ys <= 652) & (np.abs(dx) <= 84)
    arrival_ell = np.hypot(dx / 98.0, (ys - 708.0) / 58.0) <= 1.0
    arrival_pads = (
        (np.hypot((np.abs(dx) - 78.0) / 18.0, (ys - 682.0) / 13.0) <= 1.0)
        | (np.hypot((np.abs(dx) - 74.0) / 16.0, (ys - 734.0) / 12.0) <= 1.0)
    )
    arrival = arrival_ell | arrival_pads | south_steps

    top_mask = dais | north_steps | bridge_walk | piers | balc_chamfer | balc_mid_rib | arrival

    base = np.zeros((H, W, 4), dtype=np.uint8)
    glow = np.zeros((H, W, 4), dtype=np.uint8)

    # -----------------------------------------------------------------------
    # A. 3D Floating Underside Cliffs, Side Buttresses & Stalactite Spikes
    # -----------------------------------------------------------------------
    # 1) Add small carved lateral stone ribs along vertical East/West bridge & balcony flanks
    # so even straight N-S edges visibly float on 3D stone!
    for side in (-1, 1):
        for ry_c, rx_edge, rib_w, rib_h in (
            (290, 78, 5, 18),
            (366, 78, 5, 16),
            (426, 136, 5, 22),
            (534, 136, 5, 22),
            (592, 78, 5, 16),
            (630, 78, 5, 16),
        ):
            for oy in range(-rib_h // 2, rib_h):
                t_y = (oy + rib_h // 2) / (1.5 * rib_h)
                w_cur = int(round(rib_w * (1.0 - abs(t_y - 0.32) * 1.35)))
                for ox in range(1, max(1, w_cur) + 1):
                    px = CX + side * (rx_edge + ox)
                    py = ry_c + oy
                    if 0 <= px < W and 0 <= py < H and not top_mask[py, px]:
                        c_idx = 2 if (side == -1 and oy < 2) else (1 if side == -1 else 0)
                        base[py, px] = (*CLIFF[c_idx], 255)

    # 2) Extrude dramatic multi-faceted stalactite spikes under every southern lip
    top_pad = np.pad(top_mask, ((1, 1), (0, 0)), mode="constant", constant_values=False)
    south_lips = top_pad[1:-1, :] & ~top_pad[2:, :]
    lip_ys, lip_xs = np.where(south_lips)

    for ly, lx in zip(lip_ys.tolist(), lip_xs.tolist()):
        rel_x = lx - CX
        abs_rx = abs(rel_x)

        spike_w1 = math.sin(lx * 0.15 + 0.7) * 0.5 + 0.5
        spike_w2 = abs(math.sin(lx * 0.072 - 0.3)) ** 1.4
        spike_ridge = 1.0 - abs(((lx * 0.105 + 0.35) % 1.0) - 0.5) * 2.0

        if ly > 720:
            center_keel = max(0.0, 1.0 - (abs_rx / 98.0) ** 1.32)
            depth = int(round(13 + 35 * center_keel + 12 * spike_ridge * (0.4 + 0.6 * center_keel) + 5 * spike_w1))
        elif 550 <= ly <= 605 and abs_rx > 78:
            balc_keel = max(0.0, 1.0 - abs(abs_rx - 108.0) / 34.0)
            depth = int(round(12 + 24 * balc_keel + 10 * spike_ridge + 4 * spike_w2))
        elif ly < 265 and abs_rx > 78:
            dais_keel = max(0.0, 1.0 - abs(abs_rx - 112.0) / 38.0)
            depth = int(round(12 + 24 * dais_keel + 9 * spike_ridge + 3 * spike_w1))
        else:
            depth = int(round(9 + 8 * spike_ridge + 3 * spike_w1))

        depth = max(7, min(depth, H - 2 - ly))

        ly_l = ly
        if lx > 0:
            col_l = np.where(top_mask[max(0, ly - 8) : min(H, ly + 9), lx - 1])[0]
            if len(col_l) > 0:
                ly_l = max(0, ly - 8) + int(col_l[-1])
        ly_r = ly
        if lx < W - 1:
            col_r = np.where(top_mask[max(0, ly - 8) : min(H, ly + 9), lx + 1])[0]
            if len(col_r) > 0:
                ly_r = max(0, ly - 8) + int(col_r[-1])

        slope = ly_r - ly_l
        facet_turn = math.sin(lx * 0.22 + 0.4)

        for dy in range(1, depth + 1):
            yy = ly + dy
            if yy >= H or top_mask[yy, lx]:
                break
            frac = dy / max(depth, 1)

            if dy <= 2:
                col = MARBLE[1] if (rel_x < 0 or slope > 0) else MARBLE[0]
            elif dy == 3:
                if (lx + ly) % 6 in (0, 1) and frac < 0.5:
                    col = GOLD[0] if rel_x > 10 else GOLD[1]
                else:
                    col = INK_MARBLE
            elif dy == depth:
                col = INK_ABYSS
            else:
                shade = 1.38
                if rel_x < -12 or slope > 0:
                    shade += 0.65
                elif rel_x > 16 or slope < 0:
                    shade -= 0.65
                shade += 0.55 * facet_turn - frac * 0.95
                idx = max(0, min(3, int(round(shade))))
                col = CLIFF[idx]

            base[yy, lx] = (*col, 255)

    # Organic diagonal glowing turquoise crystal fissures in key underside cliffs (no regular stripes!)
    fissures = [
        (246, 774, 252, 792),
        (278, 776, 275, 798),
        (312, 773, 306, 789),
        (168, 588, 173, 601),
        (392, 588, 387, 601),
        (166, 240, 171, 254),
        (394, 240, 389, 254),
    ]
    for fx0, fy0, fx1, fy1 in fissures:
        steps = max(1, abs(fy1 - fy0))
        for s in range(steps + 1):
            t = s / steps
            px = int(round(fx0 + (fx1 - fx0) * t + math.sin(t * math.pi * 2.0) * 0.8))
            py = int(round(fy0 + (fy1 - fy0) * t))
            if 0 <= px < W and 0 <= py < H and base[py, px, 3] > 0 and not top_mask[py, px]:
                c = TEAL[3] if 0.3 < t < 0.7 else TEAL[1]
                base[py, px] = (*c, 255)
                glow[py, px] = (*c, 255)

    apply_tinted_outline(base, INK_ABYSS)

    # Detached hovering rock shards below stalactite tips
    hover_shards = [
        (228, 796, 4, 7),
        (256, 807, 5, 8),
        (280, 812, 6, 9),
        (305, 806, 4, 7),
        (332, 795, 4, 6),
        (166, 613, 5, 7),
        (394, 614, 5, 7),
        (158, 266, 4, 7),
        (402, 268, 4, 7),
    ]
    for sx, sy, sw, sh in hover_shards:
        for yy in range(-sh // 2, sh // 2 + 1):
            w_row = max(1, int(round((1.0 - abs(yy) / (sh / 2 + 0.6)) * (sw / 2))))
            for xx in range(-w_row, w_row + 1):
                px, py = sx + xx, sy + yy
                if 0 <= px < W and 0 <= py < H and not top_mask[py, px]:
                    c = CLIFF[3] if (xx < 0 and yy <= 0) else (CLIFF[2] if xx <= 0 else CLIFF[0])
                    base[py, px] = (*c, 255)
                    if xx == 0 and yy == 0 and sw >= 5:
                        base[py, px] = (*TEAL[2], 255)
                        glow[py, px] = (*TEAL[2], 255)
    apply_tinted_outline(base, INK_ABYSS)

    # -----------------------------------------------------------------------
    # B. Hand-Laid Moon-Violet Marble Masonry on Top Walkable Surface
    # -----------------------------------------------------------------------
    b_row = ys // 14
    b_col = (xs + (b_row % 2) * 10) // 20
    cid_bridge = 1000 + b_row * 60 + b_col

    nd_dx, nd_dy = xs - CX, (ys - 178.0) * 1.42
    nd_r = np.hypot(nd_dx, nd_dy)
    nd_ang = np.arctan2(nd_dy, nd_dx)
    nd_ring = (nd_r // 16.0).astype(np.int32)
    nd_sec_n = np.maximum(8, 8 + nd_ring * 4)
    nd_sec = np.floor((nd_ang + math.pi) / math.tau * nd_sec_n + (nd_ring % 2) * 0.5).astype(np.int32)
    cid_dais = 10000 + nd_ring * 100 + (nd_sec % nd_sec_n)

    sa_dx, sa_dy = xs - CX, (ys - 715.0) * 1.62
    sa_r = np.hypot(sa_dx, sa_dy)
    sa_ang = np.arctan2(sa_dy, sa_dx)
    sa_ring = (sa_r // 15.0).astype(np.int32)
    sa_sec = np.floor((sa_ang + math.pi) / math.tau * 16.0 + (sa_ring % 2) * 0.25).astype(np.int32) % 16
    cid_arrival = 20000 + sa_ring * 40 + sa_sec

    cid = np.where(ys < 252, cid_dais, np.where(ys > 648, cid_arrival, cid_bridge))

    slab_rnd = vhash(cid, cid // 37, 19)
    slab_tint_idx = (vhash(cid, 7, 43) * 3.0).astype(np.int32)
    tints = np.array([[-6, -2, 8], [0, 0, 0], [6, 3, -4]], dtype=np.int16)

    # Rich clustered marble mottling + directional brushed mineral grain (never dotty noise!)
    grain_u = xs * 0.35 + ys * 0.72 + slab_rnd * 19.0
    mottle_coarse = np.sin(grain_u * 0.24) * np.cos((xs * 0.42 - ys * 0.28) * 0.19)
    mottle_fine = vhash(xs // 3, ys // 2, 131)
    tone = np.full((H, W), 2, dtype=np.int32)
    tone += (slab_rnd > 0.60).astype(np.int32) - (slab_rnd < 0.22).astype(np.int32)
    tone += ((mottle_coarse > 0.44) & (mottle_fine > 0.45)).astype(np.int32)
    tone -= ((mottle_coarse < -0.42) & (mottle_fine < 0.55)).astype(np.int32)
    tone = np.where(ys < 252, np.minimum(4, tone + (nd_r < 84).astype(np.int32)), tone)

    # Natural wavy mineral veins + hairline fractures near block corners
    vein_warp = (np.sin(xs * 0.16 + slab_rnd * 9.0) * 2.5 + np.cos(ys * 0.19) * 1.5).astype(np.int32)
    vein_phase = (xs + ys * 2 + vein_warp + (slab_rnd * 17.0).astype(np.int32)) % 27
    vein_band = (vein_phase == 0) & (vhash(xs // 4, ys // 3, 91) > 0.56)
    vein_dark = (vein_phase == 13) & (vhash(xs // 5, ys // 3, 107) > 0.62)
    tone = np.clip(tone + vein_band.astype(np.int32) - vein_dark.astype(np.int32), 1, 4)

    # 3D beveled block joints: dark recessed mortar (`joint`), inner underside shadow (`bevel_br`),
    # and bright upper-left highlight catchlight (`bevel_tl`) for genuine tactile masonry depth!
    cid_n = np.roll(cid, 1, axis=0)
    cid_s = np.roll(cid, -1, axis=0)
    cid_w = np.roll(cid, 1, axis=1)
    cid_e = np.roll(cid, -1, axis=1)
    cid_s2 = np.roll(cid, -2, axis=0)
    cid_e2 = np.roll(cid, -2, axis=1)

    joint = ((cid != cid_s) | (cid != cid_e)) & top_mask
    bevel_tl = ((cid != cid_n) | (cid != cid_w)) & top_mask & ~joint
    bevel_br = (((cid != cid_s2) | (cid != cid_e2)) & top_mask & ~joint & ~bevel_tl)

    tone = np.where(bevel_tl, np.minimum(5, tone + 1), tone)
    tone = np.where(bevel_br, np.maximum(1, tone - 1), tone)

    marble_arr = np.array(MARBLE, dtype=np.int16)
    surf_rgb = np.clip(marble_arr[tone] + tints[slab_tint_idx], 0, 255).astype(np.uint8)

    # Crisp corner AO chips & recessed mortar variation
    joint_deep = joint & (vhash(xs // 2, ys // 2, 55) > 0.35)
    surf_rgb[joint] = MARBLE[1]
    surf_rgb[joint_deep] = MARBLE[0]
    tl_corner_glint = (cid != cid_n) & (cid != cid_w) & top_mask & ~joint
    surf_rgb[tl_corner_glint] = MARBLE[5]
    # Tiny antique brass intersection studs sparsely placed along bridge/dais stone corners
    brass_rivets = tl_corner_glint & (ys >= 268) & (ys <= 646) & (np.abs(dx) >= 34) & (vhash(xs, ys, 313) > 0.72)
    surf_rgb[brass_rivets] = GOLD[1]

    base[top_mask, :3] = surf_rgb[top_mask]
    base[top_mask, 3] = 255

    # -----------------------------------------------------------------------
    # C. Molded Platform Perimeter Rim (raised moon-marble & gold trim)
    # -----------------------------------------------------------------------
    in1 = (
        np.pad(top_mask, 1, constant_values=False)[:-2, 1:-1]
        & np.pad(top_mask, 1, constant_values=False)[2:, 1:-1]
        & np.pad(top_mask, 1, constant_values=False)[1:-1, :-2]
        & np.pad(top_mask, 1, constant_values=False)[1:-1, 2:]
    )
    in2 = (
        np.pad(in1, 1, constant_values=False)[:-2, 1:-1]
        & np.pad(in1, 1, constant_values=False)[2:, 1:-1]
        & np.pad(in1, 1, constant_values=False)[1:-1, :-2]
        & np.pad(in1, 1, constant_values=False)[1:-1, 2:]
    )
    in3 = (
        np.pad(in2, 1, constant_values=False)[:-2, 1:-1]
        & np.pad(in2, 1, constant_values=False)[2:, 1:-1]
        & np.pad(in2, 1, constant_values=False)[1:-1, :-2]
        & np.pad(in2, 1, constant_values=False)[1:-1, 2:]
    )
    rim_band1 = top_mask & ~in1
    rim_band2 = in1 & ~in2
    rim_band3 = in2 & ~in3

    tl_exposed = (~np.pad(top_mask, 1, constant_values=False)[:-2, 1:-1]) | (
        ~np.pad(top_mask, 1, constant_values=False)[1:-1, :-2]
    )
    base[rim_band1 & tl_exposed] = (*MARBLE[5], 255)
    base[rim_band1 & ~tl_exposed] = (*MARBLE[3], 255)
    base[rim_band2 & tl_exposed] = (*MARBLE[4], 255)
    base[rim_band2 & ~tl_exposed] = (*MARBLE[2], 255)
    base[rim_band3] = (*MARBLE[0], 255)

    empty_outside = base[..., 3] == 0
    top_dil = (
        np.pad(top_mask, 1, constant_values=False)[:-2, 1:-1]
        | np.pad(top_mask, 1, constant_values=False)[2:, 1:-1]
        | np.pad(top_mask, 1, constant_values=False)[1:-1, :-2]
        | np.pad(top_mask, 1, constant_values=False)[1:-1, 2:]
    )
    base[top_dil & empty_outside] = (*INK_MARBLE, 255)

    # -----------------------------------------------------------------------
    # D. 3 Illuminated Marble Steps to Throne Dais (Y = 248..272) & South Steps
    # -----------------------------------------------------------------------
    for s_idx, (sy_top, sy_bot, half_w) in enumerate(((248, 255, 92), (256, 263, 86), (264, 271, 80))):
        x0, x1 = CX - half_w, CX + half_w
        # Segmented carved marble step blocks + fluted vertical risers + deep cast step AO
        block_w = 22
        offset = (s_idx * 11) % block_w
        for px in range(x0, x1 + 1):
            rel = px - CX
            bx = (px + offset) // block_w
            bx_pos = (px + offset) % block_w
            is_seam = bx_pos == 0 and abs(rel) < half_w - 4
            is_cheeks = abs(rel) >= half_w - 5
            lit = rel < 10
            var = 1 if (bx * 3 + s_idx) % 5 == 0 else (-1 if (bx * 7 + s_idx) % 6 == 0 else 0)
            for py in range(sy_top, sy_bot + 2):
                if py == sy_bot + 1:
                    col = INK_MARBLE
                elif is_seam:
                    col = INK_MARBLE if py >= sy_bot - 1 else (MARBLE[0] if py > sy_top + 1 else MARBLE[1])
                elif py == sy_top:
                    col = GOLD[3] if is_cheeks and rel < 0 else (GOLD[1] if is_cheeks else (MARBLE[5] if bx_pos < 4 or lit else MARBLE[4]))
                elif py == sy_top + 1:
                    col = MARBLE[4] if bx_pos == 1 or lit else MARBLE[3]
                elif py == sy_top + 2:
                    # Gold tread fillet with deep bronze undercut
                    if abs(rel) <= half_w - 6:
                        col = GOLD[3] if (rel % 12 == 0 and lit) else (GOLD[2] if lit else GOLD[1])
                    else:
                        col = MARBLE[3] if lit else MARBLE[1]
                elif py == sy_top + 3:
                    col = GOLD[0] if abs(rel) <= half_w - 6 else (MARBLE[2] if lit else MARBLE[1])
                elif py < sy_bot:
                    # Vertical carved riser with shallow Kanneluren fluting every 4 px!
                    flute = ((px + s_idx * 2) % 4) == 0
                    idx = 2 + var + (-1 if flute else 0) + (0 if lit else -1)
                    col = MARBLE[max(0, min(3, idx))]
                else:
                    # Deep cast shadow directly onto step below
                    col = INK_MARBLE if not lit else MARBLE[0]
                put_px(base, px, py, col)
        # Celestial royal-plum runner center cloth cascading down the steps (|dx| <= 18)
        for px in range(CX - 18, CX + 19):
            are_trim = abs(px - CX) in (17, 18)
            for py in range(sy_top, sy_bot + 1):
                if abs(px - CX) <= 1 and py == sy_top + 1:
                    continue
                if are_trim:
                    put_px(base, px, py, GOLD[2] if py <= sy_top + 2 else GOLD[0])
                elif py <= sy_top + 2:
                    put_px(base, px, py, PLUM[3] if (px - CX) % 4 == 0 else PLUM[2])
                elif py == sy_bot:
                    put_px(base, px, py, INK_PLUM)
                else:
                    put_px(base, px, py, PLUM[1] if (px + py) % 3 == 0 else PLUM[0])
        for rx in (-56, -40, -24, 24, 40, 56):
            px = CX + rx
            put_px(base, px - 2, sy_bot - 1, INK_MARBLE)
            put_px(base, px + 2, sy_bot - 1, GOLD[0])
            base[sy_bot - 1, px - 1 : px + 2] = (*TEAL[1], 255)
            glow[sy_bot - 1, px - 1 : px + 2] = (*TEAL[2], 255)
            glow[sy_bot - 1, px] = (*TEAL[3], 255)

    for s_i, (sy_top, half_w) in enumerate(((640, 80), (645, 84))):
        x0, x1 = CX - half_w, CX + half_w
        for px in range(x0, x1 + 1):
            is_seam = ((px + s_i * 9) % 20) == 0 and abs(px - CX) < half_w - 4
            lit = px < CX + 10
            put_px(base, px, sy_top, MARBLE[1] if is_seam else (MARBLE[5] if lit else MARBLE[4]))
            put_px(base, px, sy_top + 1, MARBLE[0] if is_seam else (MARBLE[3] if lit else MARBLE[2]))
            put_px(base, px, sy_top + 2, GOLD[1] if abs(px - CX) < half_w - 6 and px % 8 < 6 else (MARBLE[2] if lit else MARBLE[1]))
            put_px(base, px, sy_top + 3, INK_MARBLE if not lit else MARBLE[0])
            put_px(base, px, sy_top + 4, INK_MARBLE)

    # -----------------------------------------------------------------------
    # E. Royal Celestial Runner Carpet, Sculpted Rails, Leylines & Candelabra Sockets
    # -----------------------------------------------------------------------
    # Central celestial night-plum runner carpet between twin leylines (X = 260..300), stopping cleanly before stairs!
    for y in range(274, 638):
        ym = (y - 274) % 24
        for x in range(261, 300):
            ax = abs(x - CX)
            if ax >= 18:
                put_px(base, x, y, GOLD[2] if (y % 4 != 0) else GOLD[0])
            elif ax == 17:
                put_px(base, x, y, PLUM[0])
            elif ax >= 14:
                put_px(base, x, y, PLUM[2] if (ym % 6 < 4) else GOLD[1])
            elif y in (274, 637):
                put_px(base, x, y, GOLD[2] if ax < 14 else GOLD[3])
            else:
                # Quilted astral diamond weave across center cloth
                d_dia = abs((ax % 8) - 4) + abs((ym % 12) - 6)
                if d_dia == 4:
                    put_px(base, x, y, PLUM[3] if x < CX else PLUM[2])
                elif d_dia < 2:
                    put_px(base, x, y, PLUM[2] if y % 12 == 6 else PLUM[1])
                else:
                    put_px(base, x, y, PLUM[1] if (x + y) % 5 == 0 else PLUM[0])

    # Flanking carved indigo-and-gold fretwork inlays along Bridge Walk (X = 228..255 & 305..332)
    for y in range(275, 637):
        if 334 <= y <= 354 or 470 <= y <= 490 or 602 <= y <= 622:
            continue
        ym = y % 16
        for x0_b, x1_b in ((228, 254), (306, 332)):
            for x in (x0_b, x1_b):
                put_px(base, x, y, MARBLE[0])
            if ym in (0, 15):
                for x in range(x0_b + 2, x1_b - 1):
                    put_px(base, x, y, GOLD[1] if ym == 0 else MARBLE[0])
            elif ym == 8:
                mid_x = (x0_b + x1_b) // 2
                put_px(base, mid_x, y, GOLD[2])

    # Golden rails along X = 224 and X = 336 — terminate cleanly before North (272) & South (640) stairs
    for rx in (224, 336):
        for y in range(274, 638):
            base[y, rx - 2] = (*MARBLE[0], 255)
            base[y, rx - 1] = (*GOLD[2], 255)
            base[y, rx] = (*(GOLD[3] if y % 16 == 0 else GOLD[1]), 255)
            base[y, rx + 1] = (*GOLD[0], 255)
            base[y, rx + 2] = (*INK_MARBLE, 255)
        # Sculpted bronze-gold finial end-caps just before the stairs
        for cy_cap in (274, 637):
            base[cy_cap, rx - 2 : rx + 3] = (*GOLD[0], 255)
            base[cy_cap, rx - 1 : rx + 2] = (*GOLD[3], 255)

    # Twin main leyline channels at X = 258 and X = 302 + central diamond star spine (stop cleanly at 637, BEFORE y=640 south stairs!)
    for y in range(274, 638):
        for lx in (258, 302):
            tcol = TEAL[2] if y % 8 != 0 else TEAL[3]
            gcol = TEAL[2] if y % 6 != 0 else TEAL[3]
            base[y, lx - 2] = (*MARBLE[0], 255)
            base[y, lx - 1] = (*GOLD[0], 255)
            base[y, lx] = (*tcol, 255)
            base[y, lx + 1] = (*GOLD[1], 255)
            base[y, lx + 2] = (*INK_MARBLE, 255)
            glow[y, lx] = (*gcol, 255)
        if y % 16 in (0, 1, 2):
            put_px(base, CX, y, GOLD[2])
        elif y % 16 == 8:
            draw_star_spark(base, CX, y, 1, TEAL[3], GOLD[2])
            draw_star_spark(glow, CX, y, 1, TEAL[3], TEAL[1])
    for lx in (258, 302):
        for cy_cap in (274, 637):
            for oy_c in (-1, 0, 1):
                for ox_c in (-2, -1, 0, 1, 2):
                    if 273 <= cy_cap + oy_c <= 638:
                        put_px(base, lx + ox_c, cy_cap + oy_c, GOLD[3] if ox_c <= 0 and oy_c <= 0 else GOLD[0])
            put_px(base, lx, cy_cap, TEAL[3])
            put_px(glow, lx, cy_cap, TEAL[3])

    # 3 Pairs of Candelabra Sockets (all on solid marble, zero overlap with mirror basins!):
    candelabra_pairs = [
        (344, 204, 356, 204, 356),
        (480, 228, 332, 218, 342),  # leyline stops cleanly at basin curbs 218 & 342!
        (612, 204, 356, 204, 356),
    ]
    for py, sx_l, sx_r, lx_min, lx_max in candelabra_pairs:
        for x in range(lx_min, lx_max + 1):
            base[py - 2, x] = (*MARBLE[0], 255)
            base[py - 1, x] = (*GOLD[2], 255)
            base[py, x] = (*TEAL[1], 255)
            base[py + 1, x] = (*GOLD[0], 255)
            base[py + 2, x] = (*INK_MARBLE, 255)
            glow[py, x] = (*TEAL[2], 255)

        # Central diamond constellation medallion with recessed frame
        for oy in range(-8, 9):
            hw = 8 - abs(oy)
            for ox in range(-hw, hw + 1):
                d_edge = abs(ox) + abs(oy)
                if d_edge == 8:
                    put_px(base, CX + ox, py + oy, MARBLE[0] if ox + oy > 0 else MARBLE[4])
                elif d_edge == 7:
                    put_px(base, CX + ox, py + oy, GOLD[2] if ox + oy < 0 else GOLD[0])
                elif d_edge == 5:
                    put_px(base, CX + ox, py + oy, TEAL[1])
                    put_px(glow, CX + ox, py + oy, TEAL[2])
                elif d_edge <= 2:
                    put_px(base, CX + ox, py + oy, TEAL[3] if d_edge == 0 else GOLD[3])
                    put_px(glow, CX + ox, py + oy, TEAL[3] if d_edge == 0 else TEAL[1])

        # Wide 3/4 elliptical collar inlays encircling Pylon footprints (never poking awkwardly below center!)
        for sx in (sx_l, sx_r):
            cy_s = py - 2
            add_soft_floor_bloom(glow, sx, cy_s, 17, 8, 70)
            for oy in range(-7, 8):
                for ox in range(-16, 17):
                    r = math.hypot(ox / 15.2, oy / 6.2)
                    if 0.88 <= r <= 1.0:
                        put_px(base, sx + ox, cy_s + oy, MARBLE[0] if ox + oy > 2 else MARBLE[4])
                    elif 0.74 <= r < 0.88:
                        put_px(base, sx + ox, cy_s + oy, GOLD[3] if ox + oy < -2 else (GOLD[2] if ox + oy < 2 else GOLD[0]))
                    elif 0.56 <= r < 0.74:
                        put_px(base, sx + ox, cy_s + oy, TEAL[1])
                        put_px(glow, sx + ox, cy_s + oy, TEAL[2])
            draw_floor_shadow_ellipse(base, top_mask, sx + 2, py + 1, 15, 6, 0.45)

    # -----------------------------------------------------------------------
    # F. Two Recessed Mirror Basins (exact spec: X=166..218 & X=342..394, Y=395..565)
    # Drawn AFTER bridge leylines so basin curbs and starry water stay 100% pristine!
    # -----------------------------------------------------------------------
    for bx0, bx1 in ((166, 218), (342, 394)):
        by0, by1 = 395, 565
        # Clear any floor glow inside the basin first
        glow[by0:by1, bx0:bx1] = 0

        # Outer 4px carved gold-and-marble curb
        base[by0:by1, bx0:bx1] = (*MARBLE[2], 255)
        base[by0, bx0:bx1] = (*INK_MARBLE, 255)
        base[by1 - 1, bx0:bx1] = (*MARBLE[4], 255)
        base[by0:by1, bx0] = (*INK_MARBLE, 255)
        base[by0:by1, bx1 - 1] = (*MARBLE[4], 255)

        base[by0 + 1, bx0 + 1 : bx1 - 1] = (*GOLD[2], 255)
        base[by0 + 1 : by1 - 1, bx0 + 1] = (*GOLD[2], 255)
        base[by1 - 2, bx0 + 1 : bx1 - 1] = (*GOLD[0], 255)
        base[by0 + 1 : by1 - 1, bx1 - 2] = (*GOLD[0], 255)

        wx0, wx1, wy0, wy1 = bx0 + 4, bx1 - 4, by0 + 4, by1 - 4  # 44 x 162 water rect
        base[wy0 - 1, wx0 - 1 : wx1 + 1] = (*INK_MARBLE, 255)
        base[wy0 - 1 : wy1 + 1, wx0 - 1] = (*INK_MARBLE, 255)
        base[wy1, wx0 - 1 : wx1 + 1] = (*GOLD[2], 255)
        base[wy0 - 1 : wy1 + 1, wx1] = (*GOLD[1], 255)

        # Static starry night-sapphire water + horizontal pixel ripples
        for wy in range(wy0, wy1):
            for wx in range(wx0, wx1):
                if wy < wy0 + 3 or wx < wx0 + 2:
                    base[wy, wx] = (*SAPPHIRE[0], 255)
                else:
                    grad = ((wy - wy0) / (wy1 - wy0)) * 1.6 + ((wx - wx0) / (wx1 - wx0)) * 0.7
                    b_val = BAYER4[wy % 4, wx % 4]
                    s_idx = min(3, max(0, int(grad + b_val * 0.7)))
                    base[wy, wx] = (*SAPPHIRE[s_idx], 255)
                    # Subtle turquoise rim reflection along right/bottom inner edge
                    if (wx >= wx1 - 2 or wy >= wy1 - 2) and (wx + wy) % 2 == 0:
                        base[wy, wx] = (*TEAL[0], 255)
                        glow[wy, wx] = (*TEAL[0], 130)
                    sh = ihhash(wx, wy, 311)
                    if sh > 0.993:
                        base[wy, wx] = (*GOLD[3], 255)
                        glow[wy, wx] = (*GOLD[2], 220)
                    elif sh > 0.983:
                        base[wy, wx] = (*TEAL[2], 255)
                        glow[wy, wx] = (*TEAL[1], 200)

        # Crisp horizontal pixel water-ripple streaks in static water
        for ry_r, rx_off, rw_r in ((422, 8, 9), (456, 22, 11), (492, 11, 8), (528, 20, 10), (548, 9, 7)):
            for ox in range(rw_r):
                c = TEAL[2] if 2 <= ox <= rw_r - 3 else TEAL[0]
                put_px(base, wx0 + rx_off + ox, ry_r, c)
                put_px(glow, wx0 + rx_off + ox, ry_r, c, 160)

        # Corner gold fleurons + mid-basin leyline clasp on inner wall
        for cx_c, cy_c in (
            (bx0 + 2, by0 + 2),
            (bx1 - 3, by0 + 2),
            (bx0 + 2, by1 - 3),
            (bx1 - 3, by1 - 3),
            (bx1 - 2 if bx0 < CX else bx0 + 1, 480),
        ):
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    put_px(base, cx_c + ox, cy_c + oy, GOLD[2] if ox + oy <= 0 else GOLD[0])
            put_px(base, cx_c, cy_c, TEAL[3])
            put_px(glow, cx_c, cy_c, TEAL[3])

    # -----------------------------------------------------------------------
    # G. Grand Astrolabe Star-Rosette on Northern Throne Dais (center 280, 178)
    # -----------------------------------------------------------------------
    acx, acy = 280, 178
    add_soft_floor_bloom(glow, acx, acy, 88, 55, 75)
    for oy in range(-60, 61):
        for ox in range(-95, 96):
            px, py = acx + ox, acy + oy
            if not (0 <= px < W and 0 <= py < H and top_mask[py, px]):
                continue
            rx_n = ox / 84.0
            ry_n = oy / 52.0
            r = math.hypot(rx_n, ry_n)
            if r > 1.07:
                continue
            ang = math.atan2(ry_n, rx_n)
            lit = (ox * -0.6 + oy * -0.8) > 0

            # Outer carved stone trough shadow around Astrolabe Bronze Ring
            if 1.02 < r <= 1.07:
                put_px(base, px, py, MARBLE[0] if not lit else MARBLE[1])
            elif 0.96 <= r <= 1.02:
                put_px(base, px, py, GOLD[3] if (lit and r > 0.985) else (GOLD[2] if lit else GOLD[0]))
            elif 0.91 <= r < 0.96:
                put_px(base, px, py, TEAL[2])
                put_px(glow, px, py, TEAL[2])
            elif 0.86 <= r < 0.91:
                put_px(base, px, py, GOLD[1] if lit else GOLD[0])
            elif 0.83 <= r < 0.86:
                put_px(base, px, py, MARBLE[0])
            elif 0.67 <= r < 0.83:
                # Radial beveled astrolabe wedge stones with antique brass dial ticks
                tick16 = abs(((ang / (math.pi / 8.0) + 16.5) % 1.0) - 0.5) * 2.0
                if tick16 < 0.09:
                    put_px(base, px, py, GOLD[2] if lit else GOLD[0])
                elif tick16 > 0.93:
                    put_px(base, px, py, MARBLE[0])
                elif 0.74 < r < 0.76 and abs(tick16 - 0.5) < 0.12:
                    put_px(base, px, py, GOLD[1])
            elif 0.62 <= r <= 0.67:
                put_px(base, px, py, GOLD[2] if lit else GOLD[0])
            elif 0.58 <= r < 0.62:
                put_px(base, px, py, TEAL[1])
                put_px(glow, px, py, TEAL[2])
            elif 0.32 <= r <= 0.36:
                put_px(base, px, py, GOLD[3] if lit else GOLD[1])
            elif 0.29 <= r < 0.32:
                put_px(base, px, py, MARBLE[0])
            elif r < 0.12:
                put_px(base, px, py, TEAL[3] if r < 0.06 else GOLD[3])
                put_px(glow, px, py, TEAL[3] if r < 0.08 else TEAL[2])
            elif 0.12 <= r < 0.58:
                ray8 = abs(((ang / (math.pi / 4.0) + 8.5) % 1.0) - 0.5) * 2.0
                taper = max(0.0, 0.24 * (1.0 - r / 0.88))
                if ray8 < taper:
                    if ray8 < taper * 0.38:
                        put_px(base, px, py, TEAL[2] if r > 0.45 else TEAL[3])
                        put_px(glow, px, py, TEAL[2] if r > 0.45 else TEAL[3])
                    else:
                        put_px(base, px, py, GOLD[2] if lit else GOLD[0])
                elif ray8 < taper + 0.06:
                    put_px(base, px, py, MARBLE[0])

    for k in range(8):
        a = k * math.pi / 4.0
        nx = int(round(acx + math.cos(a) * 84.0))
        ny = int(round(acy + math.sin(a) * 52.0))
        draw_star_spark(base, nx, ny, 1, TEAL[3], GOLD[2])
        draw_star_spark(glow, nx, ny, 1, TEAL[3], TEAL[1])

    # Grounded contact shadows beneath Throne base, 3 Relic Plinths & 4 Balustrades
    draw_floor_shadow_ellipse(base, top_mask, 281.0, 162.0, 52.0, 14.0, 0.46)
    for rpx, rpy in ((174, 180), (386, 180), (204, 224)):
        draw_line(base, acx + (1 if rpx > acx else -1) * 64, acy + (12 if rpy > 200 else 2), rpx, rpy - 1, GOLD[1], 1)
        draw_line(glow, acx + (1 if rpx > acx else -1) * 68, acy + (14 if rpy > 200 else 2), rpx, rpy - 1, TEAL[0], 1)
        add_soft_floor_bloom(glow, rpx, rpy - 1, 14, 7, 70)
        for oy in range(-6, 7):
            for ox in range(-14, 15):
                rr = math.hypot(ox / 13.5, oy / 5.2)
                if 0.86 <= rr <= 1.0:
                    put_px(base, rpx + ox, rpy - 1 + oy, MARBLE[0] if ox + oy > 2 else MARBLE[4])
                elif 0.68 <= rr < 0.86:
                    put_px(base, rpx + ox, rpy - 1 + oy, GOLD[2] if ox + oy < 0 else GOLD[0])
                elif 0.50 <= rr < 0.68:
                    put_px(base, rpx + ox, rpy - 1 + oy, TEAL[1])
                    put_px(glow, rpx + ox, rpy - 1 + oy, TEAL[2])
        draw_floor_shadow_ellipse(base, top_mask, rpx + 2, rpy + 1, 14.0, 5.5, 0.48)
    for bx_s, by_s in ((174, 381), (386, 381), (174, 581), (386, 581)):
        draw_floor_shadow_ellipse(base, top_mask, bx_s + 1, by_s + 2, 23.0, 5.0, 0.36)

    # -----------------------------------------------------------------------
    # H. Southern Arrival Circle: 16-Tile Rune Ring & Return Anchor (280, 715)
    # -----------------------------------------------------------------------
    scx, scy = 280, 715
    add_soft_floor_bloom(glow, scx, scy, 64, 40, 85)
    for oy in range(-44, 45):
        for ox in range(-71, 72):
            px, py = scx + ox, scy + oy
            if not (0 <= px < W and 0 <= py < H and top_mask[py, px]):
                continue
            rx_n = ox / 62.0
            ry_n = oy / 38.0
            r = math.hypot(rx_n, ry_n)
            if r > 1.06:
                continue
            ang = math.atan2(ry_n, rx_n)
            lit = (ox * -0.6 + oy * -0.8) > 0
            sec16 = abs(((ang / (math.tau / 16.0) + 16.0) % 1.0) - 0.5) * 2.0

            if 1.02 < r <= 1.06:
                put_px(base, px, py, MARBLE[0] if not lit else MARBLE[1])
            elif 0.95 <= r <= 1.02:
                put_px(base, px, py, GOLD[3] if (lit and r > 0.98) else (GOLD[2] if lit else GOLD[0]))
            elif 0.64 <= r < 0.95:
                if sec16 > 0.88:
                    put_px(base, px, py, INK_MARBLE)
                elif sec16 > 0.78:
                    put_px(base, px, py, GOLD[1] if lit else GOLD[0])
                elif r > 0.91 or r < 0.67:
                    put_px(base, px, py, MARBLE[4] if lit else MARBLE[0])
                else:
                    sec_i = int((ang + math.pi) / (math.tau / 16.0))
                    c_idx = (2 if sec_i % 2 == 0 else 1) + (1 if lit else 0)
                    put_px(base, px, py, MARBLE[c_idx])
            elif 0.58 <= r < 0.64:
                put_px(base, px, py, TEAL[2])
                put_px(glow, px, py, TEAL[2])
            elif 0.52 <= r < 0.58:
                put_px(base, px, py, GOLD[2] if lit else GOLD[0])
            elif 0.48 <= r < 0.52:
                put_px(base, px, py, MARBLE[0])
            elif r < 0.22:
                put_px(base, px, py, TEAL[3] if r < 0.09 else GOLD[2])
                put_px(glow, px, py, TEAL[3] if r < 0.11 else TEAL[1])

    rune_patterns = [
        [(0, -1), (0, 0), (0, 1), (-1, 0)],
        [(-1, -1), (0, 0), (1, 1), (1, -1)],
        [(0, -1), (-1, 0), (1, 0), (0, 1)],
        [(-1, -1), (-1, 1), (0, 0), (1, 0)],
    ]
    for k in range(16):
        a = (k + 0.5) * math.tau / 16.0 - math.pi
        rx_c = int(round(scx + math.cos(a) * 49.0))
        ry_c = int(round(scy + math.sin(a) * 30.0))
        for dx_r, dy_r in rune_patterns[k % 4]:
            put_px(base, rx_c + dx_r, ry_c + dy_r, TEAL[2])
            put_px(glow, rx_c + dx_r, ry_c + dy_r, TEAL[3] if (dx_r == 0 and dy_r == 0) else TEAL[2])

    for ax in (202, 358):
        ay = 682
        add_soft_floor_bloom(glow, ax, ay, 10, 7, 75)
        for oy in range(-6, 7):
            for ox in range(-9, 10):
                rr = math.hypot(ox / 8.5, oy / 6.0)
                if 0.7 <= rr <= 1.0:
                    put_px(base, ax + ox, ay + oy, GOLD[2] if ox + oy < 0 else GOLD[0])
                elif 0.4 <= rr < 0.7:
                    put_px(base, ax + ox, ay + oy, TEAL[1])
                    put_px(glow, ax + ox, ay + oy, TEAL[2])

    return base, glow


# ---------------------------------------------------------------------------
# 2. THRONE & THRONE GLOW (8 frames x 160 x 176 = 1280 x 176, foot (80, 148))
# ---------------------------------------------------------------------------
def draw_faceted_crystal_ray(
    base: np.ndarray,
    glow: np.ndarray,
    cx: float,
    cy: float,
    angle: float,
    r_start: float,
    length: float,
    half_w: float,
    shimmer: float,
) -> None:
    """Draws a crisp hexagonal crystal spire + golden clasp along `angle` onto integer pixels."""
    ux, uy = math.cos(angle), math.sin(angle)
    px_n, py_n = -uy, ux

    x_min = max(0, int(cx + min(0.0, ux * (r_start + length + 3)) - half_w - 4))
    x_max = min(base.shape[1], int(cx + max(0.0, ux * (r_start + length + 3)) + half_w + 5))
    y_min = max(0, int(cy + min(0.0, uy * (r_start + length + 3)) - half_w - 4))
    y_max = min(base.shape[0], int(cy + max(0.0, uy * (r_start + length + 3)) + half_w + 5))

    for py in range(y_min, y_max):
        for px in range(x_min, x_max):
            vx, vy = px - cx, py - cy
            along = vx * ux + vy * uy - r_start
            if along < -2.0 or along > length:
                continue
            perp = vx * px_n + vy * py_n

            if along < 2.2:
                w_here = half_w * 1.15
                if abs(perp) <= w_here:
                    lit = (px - cx) * -0.6 + (py - cy) * -0.8 > 0
                    c = GOLD[3] if (abs(perp) < 0.9 and lit) else (GOLD[2] if lit else GOLD[0])
                    put_px(base, px, py, c)
                continue

            t = along / max(length, 1.0)
            w_here = half_w * (1.0 if t < 0.45 else max(0.0, 1.0 - (t - 0.45) / 0.55))
            if abs(perp) <= w_here + 0.35:
                if abs(perp) > w_here - 0.55 or t > 0.93:
                    put_px(base, px, py, INK_TEAL)
                else:
                    top_left_side = perp < 0
                    bright_core = abs(perp) < max(0.8, w_here * 0.38) and (0.15 < t < 0.84)
                    if bright_core or (shimmer > 0.55 and 0.25 < t < 0.72 and top_left_side):
                        col = TEAL[3]
                    elif top_left_side:
                        col = TEAL[2]
                    else:
                        col = TEAL[1] if t < 0.65 else TEAL[0]
                    put_px(base, px, py, col)
                    put_px(glow, px, py, col)


def draw_golden_sun_spike(
    base: np.ndarray,
    cx: float,
    cy: float,
    angle: float,
    r_start: float,
    length: float,
) -> None:
    """Draws a slender antique-gold sun-ray spike between crystal spires."""
    ux, uy = math.cos(angle), math.sin(angle)
    px_n, py_n = -uy, ux
    steps = int(round(length * 2))
    for i in range(steps + 1):
        t = i / max(1, steps)
        along = r_start + t * length
        hw = (1.0 - t) * 1.6
        bx, by = cx + ux * along, cy + uy * along
        for off in (-1.0, -0.3, 0.3, 1.0):
            if abs(off) <= hw + 0.25:
                px = int(round(bx + px_n * off))
                py = int(round(by + py_n * off))
                lit = off <= 0
                col = GOLD[3] if (t > 0.65 and lit) else (GOLD[2] if lit else GOLD[0])
                put_px(base, px, py, col)


def build_throne() -> tuple[np.ndarray, np.ndarray]:
    FW, FH, NF = 160, 176, 8
    sheet_b = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    sheet_g = np.zeros((FH, FW * NF, 4), dtype=np.uint8)

    throne_body = np.zeros((FH, FW, 4), dtype=np.uint8)
    throne_body_glow = np.zeros((FH, FW, 4), dtype=np.uint8)
    cx = 80

    # 1. Sweeping Layered Golden Wing Ornaments flanking the high backrest
    # Draw lower/backmost feathers first (feather 4 -> 0) so upper feathers cast crisp overlap shadows!
    for side in (-1, 1):
        for feather in range(4, -1, -1):
            ang = (-0.62 + feather * 0.27) if side == 1 else (math.pi + 0.62 - feather * 0.27)
            r0 = 18.0
            r1 = 54.0 - feather * 4.5
            x0, y0 = cx + side * 14, 86 + feather * 4
            steps_n = int(r1 * 2)
            for step in range(steps_n):
                t = step / max(1.0, steps_n - 1)
                rr = r0 * (1 - t) + r1 * t
                curve_y = -math.sin(t * math.pi) * (8.0 - feather * 1.2)
                fx = x0 + math.cos(ang) * rr * 0.92
                fy = y0 + math.sin(ang) * rr * 0.65 + curve_y
                thick = max(1, int(round((1.0 - t * 0.72) * 3.6)))
                for oy in range(-thick, thick + 1):
                    for ox in range(-thick, thick + 1):
                        if ox * ox + oy * oy <= thick * thick + 1:
                            px, py = int(round(fx + ox)), int(round(fy + oy))
                            if 0 <= px < FW and 0 <= py < FH:
                                # Feathery barb notch every 6 steps along outer blade
                                if oy >= thick and step % 6 == 2 and t > 0.35:
                                    continue
                                # Back feathers sit deeper in cool bronze shadow; upper crest highlights quill spine
                                if feather >= 3 and t < 0.55 and oy >= 0:
                                    c = GOLD[0]
                                elif oy == -thick + 1 or (oy == 0 and t < 0.78):
                                    # Carved central quill rib highlight
                                    c = GOLD[3] if (t < 0.75 and (side == -1 or feather <= 2)) else GOLD[2]
                                elif oy <= -thick + 1:
                                    c = GOLD[2] if side == -1 else GOLD[1]
                                elif oy >= thick - 1:
                                    # Deep bronze underside & cast shadow from feather above
                                    c = (72, 48, 22) if feather > 0 else GOLD[0]
                                else:
                                    c = GOLD[2] if (side == -1 and oy < 0) else GOLD[1]
                                put_px(throne_body, px, py, c)
            # Wing shoulder bronze-gold filigree collar + inlaid star-gem on alternating feathers
            if feather in (1, 3):
                jx = int(round(x0 + math.cos(ang) * (r1 * 0.58)))
                jy = int(round(y0 + math.sin(ang) * (r1 * 0.42) - 4))
                for oy in (-2, -1, 0, 1, 2):
                    for ox in (-2, -1, 0, 1, 2):
                        if abs(ox) + abs(oy) == 2:
                            put_px(throne_body, jx + ox, jy + oy, GOLD[0] if ox > 0 else GOLD[2])
                for oy in (-1, 0, 1):
                    for ox in (-1, 0, 1):
                        if abs(ox) + abs(oy) <= 1:
                            c = TEAL[3] if (ox == 0 and oy == 0) else TEAL[1]
                            put_px(throne_body, jx + ox, jy + oy, c)
                            put_px(throne_body_glow, jx + ox, jy + oy, c)
        # Sculpted bronze/gold wing-root shoulder mount hugging the marble piers
        for sy in range(82, 108):
            sw = 3 if (86 <= sy <= 102) else 2
            for dx_w in range(sw):
                px = cx + side * (29 + dx_w)
                c = GOLD[3] if (sy % 5 == 0 and dx_w == 0) else (GOLD[1] if (sy % 5 in (1, 2)) else GOLD[0])
                put_px(throne_body, px, sy, c)

    apply_tinted_outline(throne_body, INK_GOLD)

    # 2. High Gothic-Celestial Moon-Marble Backrest (y = 32..130)
    back_img = np.zeros((FH, FW, 4), dtype=np.uint8)
    for y in range(32, 132):
        if y < 68:
            t = (y - 32) / 36.0
            hw = int(round(2.0 + 28.0 * (t**0.74)))
        else:
            hw = int(round(29.0 + 2.5 * math.sin((y - 68) / 60.0 * math.pi)))

        for ox in range(-hw, hw + 1):
            px = cx + ox
            dist_edge = hw - abs(ox)
            lit = ox < 0 or y < 48
            if dist_edge == 0:
                col = MARBLE[4] if ox < 0 else MARBLE[0]
            elif dist_edge <= 4:
                # Carved 3D rounded marble pier with central concave flute & gold-capped cornice shadow
                col_ox = ox - (hw - 2) if ox > 0 else ox + (hw - 2)
                oh = 0.9 if (68 <= y <= 73 or (dist_edge == 4)) else 0.0
                if y >= 74 and (y % 12 == 0):
                    oh += 0.55  # carved ashlar block mortar ring around the side piers
                col = cylindrical_marble_shade(col_ox, 2, flutes=1, overhang_ao=oh)
            elif dist_edge <= 6:
                # Beveled golden inner arch frame molding with shadow drop onto velvet cove
                col = cylindrical_gold_shade(1 if ox > 0 else -1, 2, overhang_ao=0.35 if dist_edge == 6 else 0.0)
            else:
                # Recessed Gothic night-plum velvet alcove with cast cornice shadow along arch & sides!
                edge_cove = max(0.0, 1.0 - max(0, dist_edge - 6) / 6.0)
                top_cove = max(0.0, 1.0 - max(0, y - 38) / 14.0) if y < 64 else 0.0
                cove_shadow = max(edge_cove, top_cove)
                arch_glow = max(0.0, 1.0 - math.hypot(ox / 14.0, (y - 52.0) / 16.0)) * (1.0 - cove_shadow * 0.8)
                if cove_shadow > 0.55:
                    col = INK_ABYSS
                elif arch_glow > BAYER4[y % 4, px % 4] * 0.78 + 0.18:
                    col = PLUM[1]
                else:
                    col = PLUM[0]
                if y < 80:
                    # Pointed gothic gold tracery ribs inside the upper arch
                    rib_r = math.hypot(ox / 18.0, (y - 64.0) / 22.0)
                    if 0.88 <= rib_r <= 0.96 and y < 70:
                        col = GOLD[0] if ox > 0 else GOLD[1]
                    elif abs(abs(ox) - (y - 42) * 0.42) < 0.75 and 42 <= y <= 74:
                        col = GOLD[0]
                elif dist_edge <= 9 and y < 118 and y % 8 == 0:
                    # Subtle gold velvet-border studding along the inner alcove jambs (clear of Caelia!)
                    col = GOLD[0]
                # Central star-crest high in the arch (y = 48..58, above seated head height ~88..104)
                if ox == 0 and 42 <= y <= 66:
                    col = GOLD[1]
            put_px(back_img, px, y, col)

    # Small glowing star-emblem high inside the gothic arch (cx, 52)
    draw_star_spark(back_img, cx, 52, 2, TEAL[3], GOLD[2], GOLD[1])
    draw_star_spark(throne_body_glow, cx, 52, 1, TEAL[3], TEAL[1])

    # Golden finial crest at apex of backrest (cx, 30)
    for oy in range(-5, 4):
        w_f = max(0, 3 - abs(oy) // 2)
        for ox in range(-w_f, w_f + 1):
            put_px(back_img, cx + ox, 31 + oy, cylindrical_gold_shade(ox, max(1, w_f), overhang_ao=0.4 if oy >= 2 else 0.0))
    draw_star_spark(back_img, cx, 28, 1, TEAL[3], GOLD[3])
    draw_star_spark(throne_body_glow, cx, 28, 1, TEAL[3], TEAL[2])

    # Side marble pinnacles on backrest shoulders (cx +- 30, y = 58..76)
    for sx in (cx - 30, cx + 30):
        for oy in range(-10, 8):
            w_p = max(1, 3 - max(0, -oy) // 3)
            for ox in range(-w_p, w_p + 1):
                if oy < -5:
                    c = cylindrical_gold_shade(ox, w_p)
                else:
                    c = cylindrical_marble_shade(ox, w_p, flutes=1, overhang_ao=0.8 if oy == -5 else 0.0)
                put_px(back_img, sx + ox, 66 + oy, c)
        put_px(back_img, sx, 54, TEAL[3])
        put_px(throne_body_glow, sx, 54, TEAL[3])

    apply_tinted_outline(back_img, INK_MARBLE)
    mask_b = back_img[..., 3] > 0
    throne_body[mask_b] = back_img[mask_b]

    # 3. Plush Diamond-Tufted Seat Cushion, Fluted S-Volute Armrests & Carved Marble Steps (y = 104..148)
    seat_img = np.zeros((FH, FW, 4), dtype=np.uint8)
    for y in range(120, 135):
        for ox in range(-24, 25):
            px = cx + ox
            if y == 120:
                col = cylindrical_gold_shade(ox, 24)
            elif y <= 122:
                # Overhang shadow beneath seat molding onto plush velvet cushion
                col = PLUM[0] if y == 121 else (PLUM[2] if ox < 4 else PLUM[1])
            elif y >= 132:
                # Heavy woven golden tassel trim along lower cushion edge
                fringe = (ox % 2 == 0)
                if y == 132:
                    col = GOLD[3] if ox < -4 else (GOLD[2] if ox < 8 else GOLD[1])
                elif y == 133:
                    col = GOLD[2] if fringe else GOLD[0]
                else:
                    col = GOLD[1] if fringe else (72, 48, 22)
            else:
                # Diamond-quilted button tufting with puffed plum silk ridges and sunken creases
                dy_t = y - 126.5
                qx = ((ox + 100) % 8) - 4
                diamond = abs(qx) * 0.75 + abs(dy_t)
                if abs(qx) <= 0.5 and abs(dy_t) <= 0.8:
                    col = GOLD[2]
                elif diamond < 1.3:
                    col = PLUM[0]
                elif diamond > 3.1:
                    col = PLUM[3] if ox < 8 else PLUM[2]
                else:
                    col = PLUM[2] if ox < 6 else PLUM[1]
                # Cast shadow beside armrest piers
                if abs(ox) >= 21:
                    col = PLUM[0]
            put_px(seat_img, px, y, col)

    # Sculpted Fluted Marble & Gold Volute Armrests + Pleated Brocade Flanks
    for side in (-1, 1):
        ax = cx + side * 29
        for y in range(105, 141):
            flare = 1 if (y < 112 or y > 134) else 0
            scroll_shift = side * (1 if y < 111 else 0)
            hw = 5 + flare
            # Strong overhang cast shadow directly beneath gold scroll cap (y=111..114) and neck collar (y=135..137)
            if 111 <= y <= 114:
                oh = 1.65 - (y - 111) * 0.38
            elif 135 <= y <= 137:
                oh = 1.0 - (y - 135) * 0.3
            else:
                oh = 0.0
            for ox in range(-hw, hw + 1):
                px = ax + scroll_shift + ox
                if y <= 109:
                    # Sculpted golden S-volute scroll with carved curl crease
                    curl = (y == 107 and abs(ox) in (2, 3))
                    col = GOLD[0] if curl else cylindrical_gold_shade(ox, hw, overhang_ao=0.55 if y == 109 else 0.0)
                elif y == 110:
                    col = (76, 50, 22)
                elif y in (133, 134):
                    col = cylindrical_gold_shade(ox, hw, overhang_ao=0.3 if y == 134 else 0.0)
                elif ox == 0 and 116 <= y <= 131:
                    col = GOLD[2] if y % 4 != 0 else GOLD[0]  # recessed gold beaded fluting inlay
                else:
                    col = cylindrical_marble_shade(ox, hw, flutes=2, overhang_ao=oh)
                put_px(seat_img, px, y, col)

        # Pleated Royal Night-Plum & Gold Brocade Side-Drape cascading outside the armrest (y = 114..136)
        for dy in range(22):
            y = 114 + dy
            dw = max(1, 4 - dy // 6)
            for dx_d in range(dw):
                px = ax + side * (6 + dx_d)
                if dy >= 19:
                    col = GOLD[2] if dx_d == 0 else GOLD[0]
                elif dx_d == dw - 1:
                    col = GOLD[1]
                elif (dx_d + dy // 7) % 2 == 0:
                    col = PLUM[3] if (side == -1 and dy < 14) else PLUM[2]
                else:
                    col = PLUM[0]
                put_px(seat_img, px, y, col)

        # Glowing turquoise star-cabochon set inside gold bezel on armrest scroll front
        jx = ax + side * 1
        put_px(seat_img, jx - 1, 113, GOLD[2])
        put_px(seat_img, jx + 1, 113, GOLD[0])
        put_px(seat_img, jx, 113, TEAL[3])
        put_px(seat_img, jx, 114, TEAL[1])
        put_px(throne_body_glow, jx, 113, TEAL[3])
        put_px(throne_body_glow, jx, 114, TEAL[2])

    # Two Carved Segmented Moon-Marble Throne Steps with Ashlar Block Joints & Overhang Shadows
    for step_idx, (y_top, y_bot, hw) in enumerate(((135, 141, 34), (142, 148, 43))):
        joint_stride = 11 if step_idx == 0 else 13
        joint_off = 5 if step_idx == 0 else 0
        for y in range(y_top, y_bot + 1):
            cur_hw = hw - max(0, (y_top + 2 - y))
            for ox in range(-cur_hw, cur_hw + 1):
                px = cx + ox
                lit = ox < 8
                is_joint = ((ox + joint_off) % joint_stride == 0) and (abs(ox) < cur_hw - 3)
                is_bevel_l = ((ox + joint_off) % joint_stride == 1) and (abs(ox) < cur_hw - 3)
                # Horizontal top lip highlights, gold trim band, overhang shadow directly under previous step
                if y == y_top:
                    if is_joint:
                        col = MARBLE[1]
                    else:
                        col = MARBLE[5] if ox < 4 else MARBLE[4]
                elif y == y_top + 1:
                    # Cast shadow from upper step onto lower step's bullnose lip + recessed mortar
                    if step_idx == 1 and abs(ox) <= 34:
                        col = GOLD[0] if ox >= -8 else GOLD[1]
                    else:
                        col = cylindrical_gold_shade(ox, cur_hw)
                elif y == y_top + 2:
                    # Deep 1px undercut shadow right below the gold bullnose molding!
                    col = INK_MARBLE if step_idx == 1 else MARBLE[0]
                elif y >= y_bot:
                    col = MARBLE[0]
                else:
                    # Riser face: segmented carved ashlar blocks + subtle vertical flute notches
                    if is_joint:
                        col = MARBLE[0]
                    elif is_bevel_l:
                        col = MARBLE[4] if lit else MARBLE[3]
                    elif (ox + 100) % 4 == 0 and y in (y_top + 3, y_top + 4):
                        col = MARBLE[1] if lit else MARBLE[0]  # miniature riser flute shadow
                    else:
                        col = MARBLE[3] if lit else (MARBLE[2] if ox < cur_hw - 10 else MARBLE[1])
                put_px(seat_img, px, y, col)
        for rx in (-20, 0, 20):
            put_px(seat_img, cx + rx - 1, y_bot - 2, GOLD[1])
            put_px(seat_img, cx + rx + 1, y_bot - 2, GOLD[0])
            put_px(seat_img, cx + rx, y_bot - 2, TEAL[3])
            put_px(throne_body_glow, cx + rx, y_bot - 2, TEAL[3])

    apply_tinted_outline(seat_img, INK_MARBLE)
    mask_s = seat_img[..., 3] > 0
    throne_body[mask_s] = seat_img[mask_s]

    ys_f, xs_f = np.mgrid[0:FH, 0:FW]
    sh_d = np.hypot((xs_f - cx) / 50.0, (ys_f - 149.0) / 6.2)
    sh_mask = (sh_d <= 1.0) & (throne_body[..., 3] == 0)

    # 4. Render 8 Animated Frames: Rotating Astrolabe Ring + 9 Crystal Spires + 8 Golden Sun-Rays
    halo_cx, halo_cy = 80.0, 76.0
    # 9 symmetrical crystal spire angles including straight up (-pi/2) at k = 0!
    ray_angles = [-math.pi / 2 + k * (math.pi * 0.84 / 4.0) for k in range(-4, 5)]
    sun_angles = [
        -math.pi / 2 + (k + 0.5) * (math.pi * 0.84 / 4.0) for k in range(-4, 4)
    ]

    for f in range(NF):
        fb = np.zeros((FH, FW, 4), dtype=np.uint8)
        fg = np.zeros((FH, FW, 4), dtype=np.uint8)
        phase = f / NF * math.tau
        rot_step = (f / NF) * (math.tau / 8.0)

        # Rotating Double Golden Astrolabe Ring (r = 45 & r = 53) + Golden Sun-Rays
        ring_layer = np.zeros((FH, FW, 4), dtype=np.uint8)
        for s_idx, sang in enumerate(sun_angles):
            s_len = 9.5 + 1.2 * math.sin(phase + s_idx * 1.1)
            draw_golden_sun_spike(ring_layer, halo_cx, halo_cy, sang, 53.5, s_len)

        for py in range(10, 138):
            for px in range(14, 146):
                vx, vy = px - halo_cx, py - halo_cy
                if vy > 48:
                    continue
                r = math.hypot(vx, vy)
                if 43.5 <= r <= 54.5:
                    ang = math.atan2(vy, vx) + rot_step
                    lit = (vx * -0.6 + vy * -0.8) > 0
                    if 44.0 <= r <= 46.2 or 52.0 <= r <= 54.2:
                        put_px(
                            ring_layer,
                            px,
                            py,
                            GOLD[3] if lit and abs(r - 45.1) < 0.6 else (GOLD[2] if lit else GOLD[0]),
                        )
                    else:
                        spoke16 = abs(((ang / (math.tau / 16.0) + 16.0) % 1.0) - 0.5) * 2.0
                        if spoke16 < 0.14:
                            put_px(ring_layer, px, py, GOLD[2] if lit else GOLD[1])
                        elif spoke16 > 0.88 and 48.0 <= r <= 50.2:
                            put_px(ring_layer, px, py, TEAL[2])
                            put_px(fg, px, py, TEAL[2])

        for k in range(8):
            ba = k * (math.tau / 8.0) + rot_step - math.pi / 2
            bx = int(round(halo_cx + math.cos(ba) * 49.0))
            by = int(round(halo_cy + math.sin(ba) * 49.0))
            if by <= halo_cy + 46:
                draw_star_spark(ring_layer, bx, by, 1, TEAL[3], GOLD[3])
                draw_star_spark(fg, bx, by, 1, TEAL[3], TEAL[2])

        apply_tinted_outline(ring_layer, INK_GOLD)
        rm = ring_layer[..., 3] > 0
        fb[rm] = ring_layer[rm]

        # 9 Faceted Floating Crystal Spires around the Crown
        cryst_layer = np.zeros((FH, FW, 4), dtype=np.uint8)
        for idx, ang in enumerate(ray_angles):
            bob = math.sin(phase + idx * 0.85) * 1.5
            shimmer = 0.5 + 0.5 * math.sin(phase - idx * 0.8)
            is_apex = idx == 4
            is_major = idx in (2, 4, 6)
            r_s = 54.5 + bob
            c_len = (20.5 if is_apex else (17.5 if is_major else 14.0)) + 1.0 * math.cos(phase + idx)
            c_hw = 4.2 if is_apex else (3.7 if is_major else 3.0)
            draw_faceted_crystal_ray(cryst_layer, fg, halo_cx, halo_cy, ang, r_s, c_len, c_hw, shimmer)

        cm = cryst_layer[..., 3] > 0
        fb[cm] = cryst_layer[cm]

        fb[sh_mask] = (12, 8, 24, 155)

        # Composite Throne body in front of animated halo
        tm = throne_body[..., 3] > 0
        fb[tm] = throne_body[tm]
        fg[tm & (throne_body_glow[..., 3] == 0)] = 0
        tgm = throne_body_glow[..., 3] > 0
        fg[tgm] = throne_body_glow[tgm]

        # Waystone-style tight translucent Bayer halo around all emissive pixels (never over body!)
        solid_non_emit = (fb[..., 3] >= 200) & (fg[..., 3] == 0)
        add_waystone_halo(fg, solid_non_emit, radius=6, max_alpha=155)

        sheet_b[:, f * FW : (f + 1) * FW] = fb
        sheet_g[:, f * FW : (f + 1) * FW] = fg

    return sheet_b, sheet_g


# ---------------------------------------------------------------------------
# 3. PYLON & PYLON GLOW (8 frames x 48 x 96 = 384 x 96, foot (24, 84))
# ---------------------------------------------------------------------------
def build_pylon() -> tuple[np.ndarray, np.ndarray]:
    FW, FH, NF = 48, 96, 8
    sheet_b = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    sheet_g = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    cx = 24

    ped = np.zeros((FH, FW, 4), dtype=np.uint8)
    ped_g = np.zeros((FH, FW, 4), dtype=np.uint8)

    # Render cylindrical column from top to bottom with genuine 3/4 elliptical tier curvature + crisp Kanneluren flutes!
    for y in range(44, 86):
        if y >= 81:
            hw = 11
            oh = 0.85 if y == 81 else 0.0
        elif y >= 76:
            hw = 9
            oh = 0.9 if y == 76 else 0.0
        elif y >= 54:
            hw = 5 if y > 58 else 6
            if y == 54:
                oh = 1.65
            elif y in (55, 56):
                oh = 1.0
            elif y == 57:
                oh = 0.5
            else:
                oh = 0.0
        else:
            hw = int(round(6 + (54 - y) * 0.45))
            oh = 0.45 if y == 45 else 0.0

        for ox in range(-hw, hw + 1):
            px = cx + ox
            # 3/4 circular perspective downward arc: middle of cylinder wraps lower by +2 px than outer edges!
            nx = abs(ox) / max(1.0, float(hw))
            drop = int(round(2.2 * math.sqrt(max(0.0, 1.0 - nx * nx)))) if y >= 52 else 0
            py = min(FH - 2, y + drop)

            if y in (81, 76):
                joint = abs(ox) == 4
                col = MARBLE[1] if joint else cylindrical_marble_shade(ox, hw, flutes=0, y_var=0.8)
            elif y in (85, 80):
                col = MARBLE[0]
            elif y < 52:
                # Fluted sculpted gold chalice with top-left specular arc & carved vertical bronze ribs
                rib = 0.45 if (ox % 3 == 0) else 0.0
                oh_g = (0.85 if y >= 50 else 0.0) + rib
                col = cylindrical_gold_shade(ox, hw, overhang_ao=oh_g, band_hi=0.35 if y <= 46 else 0.0)
            elif y in (52, 53, 74, 75):
                oh_g = 0.6 if y in (53, 75) else 0.0
                col = cylindrical_gold_shade(ox, hw, overhang_ao=oh_g)
            else:
                if ox == 0 and 56 <= y <= 72:
                    col = TEAL[3] if y % 3 == 0 else TEAL[2]
                    put_px(ped_g, px, py, col)
                else:
                    joint = (y in (82, 83, 84) and abs(ox) == 5)
                    if joint:
                        col = MARBLE[0]
                    elif 56 <= y <= 73:
                        # Crisp carved Kanneluren flutes + cylindrical wrap on 11px shaft!
                        if ox in (-3, 2, 4):
                            col = MARBLE[1] if ox < 0 else MARBLE[0]
                        elif ox in (-4, -2):
                            col = MARBLE[5] if oh < 0.3 else MARBLE[3]
                        elif ox == -1:
                            col = MARBLE[3] if oh < 0.3 else MARBLE[1]
                        elif ox == 1:
                            col = MARBLE[3] if oh < 0.3 else MARBLE[2]
                        elif ox == 3:
                            col = MARBLE[2] if oh < 0.3 else MARBLE[1]
                        else:
                            col = cylindrical_marble_shade(ox, hw, flutes=3, overhang_ao=oh)
                        if oh >= 0.9:
                            col = MARBLE[0] if ox >= 0 else MARBLE[1]
                    else:
                        col = cylindrical_marble_shade(ox, hw, flutes=0, overhang_ao=oh)
            put_px(ped, px, py, col)

    # Sculpted curved golden cradle horns holding the levitating crystal
    for side in (-1, 1):
        for dy in range(16):
            y = 45 - dy
            curve = math.sin(dy / 15.0 * math.pi * 0.85) * 3.5
            px = int(round(cx + side * (7.5 + curve)))
            w_p = 1 if dy > 11 else 2
            for ox in range(-w_p + 1, w_p):
                if dy > 12:
                    c = GOLD[3] if side == -1 else GOLD[2]
                else:
                    c = cylindrical_gold_shade(ox if side == -1 else ox + 1, 2, overhang_ao=0.25 if dy < 3 else 0.0)
                put_px(ped, px + ox, y, c)

    apply_tinted_outline(ped, INK_MARBLE)

    ys_f, xs_f = np.mgrid[0:FH, 0:FW]
    sh_mask = (np.hypot((xs_f - (cx + 1.0)) / 14.0, (ys_f - 87.5) / 4.2) <= 1.0) & (ped[..., 3] == 0)

    for f in range(NF):
        fb = np.zeros((FH, FW, 4), dtype=np.uint8)
        fg = np.zeros((FH, FW, 4), dtype=np.uint8)
        phase = f / NF * math.tau
        bob = int(round(math.sin(phase) * 2.0))
        cy_cryst = 26 + bob

        cap_y = 11 - int(round(math.sin(phase) * 1.0))
        cap_img = np.zeros((FH, FW, 4), dtype=np.uint8)
        for oy in range(-3, 3):
            hw = 5 - abs(oy)
            for ox in range(-hw, hw + 1):
                put_px(cap_img, cx + ox, cap_y + oy, cylindrical_gold_shade(ox, max(1, hw), overhang_ao=0.5 if oy >= 1 else 0.0))
        apply_tinted_outline(cap_img, INK_GOLD)

        cryst_img = np.zeros((FH, FW, 4), dtype=np.uint8)
        rot_f = (f % 4) / 4.0
        ridge_x = int(round((rot_f - 0.5) * 3.0))
        for oy in range(-10, 11):
            hw = int(round((1.0 - abs(oy) / 10.5) * 6.2))
            for ox in range(-hw, hw + 1):
                if abs(ox) == hw or abs(oy) == 10:
                    put_px(cryst_img, cx + ox, cy_cryst + oy, INK_TEAL)
                else:
                    # Sharp vertical triangular prism facets rotating across the crystal
                    if abs(ox - ridge_x) <= 1 and abs(oy) <= 7:
                        col = TEAL[3]
                    elif ox < ridge_x:
                        col = TEAL[2] if oy <= 2 else TEAL[1]
                    elif oy <= 0:
                        col = TEAL[1]
                    else:
                        col = TEAL[0]
                    put_px(cryst_img, cx + ox, cy_cryst + oy, col)
                    put_px(fg, cx + ox, cy_cryst + oy, col)

        # Equatorial golden gyroscope bezel around the floating crystal
        for ox in range(-5, 6):
            gy_o = cy_cryst + (1 if abs(ox) < 3 else 0)
            put_px(cryst_img, cx + ox, gy_o, cylindrical_gold_shade(ox, 5))

        for s_idx, (sx_off, s_base_y) in enumerate(((-8, 34), (8, 30), (-5, 19), (6, 22))):
            prog = ((f / NF) + s_idx * 0.25) % 1.0
            sy = int(round(s_base_y - prog * 14.0))
            sx = cx + sx_off + int(round(math.sin(prog * math.tau + s_idx) * 1.0))
            scol = GOLD[3] if s_idx % 2 == 0 else TEAL[3]
            if prog < 0.82:
                put_px(cryst_img, sx, sy, scol)
                put_px(fg, sx, sy, scol)

        fb[sh_mask] = (12, 8, 24, 145)
        pm = ped[..., 3] > 0
        fb[pm] = ped[pm]
        pgm = ped_g[..., 3] > 0
        fg[pgm] = ped_g[pgm]
        cm = cryst_img[..., 3] > 0
        fb[cm] = cryst_img[cm]
        km = cap_img[..., 3] > 0
        fb[km] = cap_img[km]

        solid_non_emit = (fb[..., 3] >= 200) & (fg[..., 3] == 0)
        add_waystone_halo(fg, solid_non_emit, radius=6, max_alpha=165)

        sheet_b[:, f * FW : (f + 1) * FW] = fb
        sheet_g[:, f * FW : (f + 1) * FW] = fg

    return sheet_b, sheet_g


# ---------------------------------------------------------------------------
# 4. BALUSTRADE & BALUSTRADE GLOW (48 x 36, foot (24, 32))
# ---------------------------------------------------------------------------
def build_balustrade() -> tuple[np.ndarray, np.ndarray]:
    W, H = 48, 36
    base = np.zeros((H, W, 4), dtype=np.uint8)
    glow = np.zeros((H, W, 4), dtype=np.uint8)

    # Segmented sculpted marble base sill with ashlar mortar joints & top bevel
    for y in range(28, 33):
        for x in range(2, W - 2):
            joint = (x in (15, 24, 33)) and y >= 29
            if joint:
                col = MARBLE[0]
            elif y == 28:
                col = MARBLE[5] if x < W // 2 else MARBLE[4]
            elif y == 29:
                col = MARBLE[3] if x < 30 else MARBLE[2]
            elif y <= 31:
                col = MARBLE[2] if x < 24 else MARBLE[1]
            else:
                col = MARBLE[0]
            put_px(base, x, y, col)

    # Turned cylindrical balusters with neck collars & top cast shadow from handrail
    for px_c in (15, 24, 33):
        for y in range(13, 28):
            oh = 1.15 if y in (13, 14) else (0.5 if y == 15 else 0.0)
            # Subtle amphora belly swell in middle (y=19..23)
            belly = 1 if (19 <= y <= 23) else 0
            for ox in range(-1 - belly, 2 + belly):
                if y in (15, 26):
                    col = cylindrical_gold_shade(ox, 1 + belly)
                elif y == 27:
                    col = MARBLE[0]
                else:
                    col = cylindrical_marble_shade(ox, 1 + belly, flutes=0, overhang_ao=oh)
                put_px(base, px_c + ox, y, col)
        put_px(base, px_c, 21, TEAL[3])
        put_px(glow, px_c, 21, TEAL[3])

    # Carved gothic arch spandrels between balusters with gold extrados rim
    for ax0, ax1 in ((6, 15), (15, 24), (24, 33), (33, 42)):
        mid = (ax0 + ax1) / 2.0
        for x in range(ax0 + 1, ax1):
            arch_y = 13 + int(round(((x - mid) / 4.2) ** 2 * 3.0))
            put_px(base, x, arch_y + 1, INK_MARBLE)
            put_px(base, x, arch_y, GOLD[2] if x < mid else GOLD[0])
            put_px(base, x, arch_y - 1, MARBLE[3] if x < mid else MARBLE[1])

    # Carved handrail cornice with deep 1px undercut cove shadow
    for y in range(9, 14):
        for x in range(2, W - 2):
            joint = (x == 24) and y in (11, 12)
            if y == 9:
                col = GOLD[3] if x < W // 2 else GOLD[2]
            elif y == 10:
                col = GOLD[1] if x < 30 else GOLD[0]
            elif y == 11:
                col = MARBLE[5] if x < 18 else MARBLE[4]
            elif y == 12:
                col = MARBLE[0] if joint else (MARBLE[2] if x < 24 else MARBLE[1])
            else:
                col = MARBLE[0]
            put_px(base, x, y, col)

    # Fluted cylindrical newel end posts with overhanging golden caps & cast shadow
    for px0 in (2, 40):
        for y in range(6, 33):
            oh = 1.45 if y in (9, 10) else (0.7 if y == 11 else 0.0)
            for dx in range(6):
                x = px0 + dx
                ox = dx - 2
                if y in (6, 7):
                    col = cylindrical_gold_shade(ox, 3, overhang_ao=0.35 if y == 7 else 0.0)
                elif y == 8:
                    col = (72, 48, 22)
                elif y in (29, 30):
                    col = cylindrical_gold_shade(ox, 3, overhang_ao=0.25 if y == 30 else 0.0)
                elif y == 32:
                    col = MARBLE[0]
                else:
                    col = cylindrical_marble_shade(ox, 3, flutes=2, overhang_ao=oh)
                put_px(base, x, y, col)
        gx = px0 + 2
        put_px(base, gx, 18, TEAL[3])
        put_px(base, gx + 1, 18, TEAL[1])
        put_px(base, gx, 19, TEAL[1])
        put_px(glow, gx, 18, TEAL[3])
        put_px(glow, gx + 1, 18, TEAL[2])
        put_px(glow, gx, 19, TEAL[2])

    apply_tinted_outline(base, INK_MARBLE)
    # Crisp 2px contact shadow beneath sill on floor
    for x in range(3, W - 3):
        if base[33, x, 3] == 0:
            base[33, x] = (14, 10, 28, 120)
        if base[34, x, 3] == 0 and (x % 2 == 0):
            base[34, x] = (14, 10, 28, 70)
    solid_non_emit = (base[..., 3] >= 200) & (glow[..., 3] == 0)
    add_waystone_halo(glow, solid_non_emit, radius=4, max_alpha=135)
    return base, glow


# ---------------------------------------------------------------------------
# 5. RETURN SEAL & RETURN SEAL GLOW (8 frames x 64 x 44 = 512 x 44)
# ---------------------------------------------------------------------------
def build_return_seal() -> tuple[np.ndarray, np.ndarray]:
    FW, FH, NF = 64, 44, 8
    sheet_b = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    sheet_g = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    cx, cy = 32.0, 24.0

    for f in range(NF):
        fb = np.zeros((FH, FW, 4), dtype=np.uint8)
        fg = np.zeros((FH, FW, 4), dtype=np.uint8)
        phase = f / NF * math.tau
        cy_f = cy + math.sin(phase) * 1.0
        rot = (f / NF) * (math.tau / 8.0)

        # Crisp airy perspective rune ring (rx = 26, ry = 13) with open center!
        for py in range(FH):
            for px in range(FW):
                rx_n = (px - cx) / 26.0
                ry_n = (py - cy_f) / 13.0
                r = math.hypot(rx_n, ry_n)
                ang = math.atan2(ry_n, rx_n) + rot
                if 0.90 <= r <= 1.03:
                    col = GOLD[3] if (px < cx and py < cy_f) else GOLD[1]
                    put_px(fb, px, py, col)
                    put_px(fg, px, py, TEAL[0])
                elif 0.78 <= r < 0.90:
                    put_px(fb, px, py, TEAL[3] if r > 0.83 else TEAL[2])
                    put_px(fg, px, py, TEAL[3] if r > 0.83 else TEAL[2])
                elif 0.50 <= r <= 0.58:
                    # Delicate inner golden ring broken into 8 rotating celestial arcs
                    seg = abs(((ang / (math.tau / 8.0) + 8.0) % 1.0) - 0.5) * 2.0
                    if seg < 0.58:
                        put_px(fb, px, py, GOLD[2])
                        put_px(fg, px, py, TEAL[1])

        # 8 orbiting star-glyphs on the ring
        for k in range(8):
            a = k * (math.tau / 8.0) + rot
            gx = int(round(cx + math.cos(a) * 22.0))
            gy = int(round(cy_f + math.sin(a) * 11.0))
            put_px(fb, gx, gy, TEAL[3])
            put_px(fg, gx, gy, TEAL[3])
            if k % 2 == 0:
                draw_star_spark(fb, gx, gy, 1, TEAL[3], GOLD[3])
                draw_star_spark(fg, gx, gy, 1, TEAL[3], TEAL[2])

        # Central floating 4-pointed compass star
        icx, icy = int(round(cx)), int(round(cy_f))
        draw_star_spark(fb, icx, icy, 2, TEAL[3], GOLD[3], TEAL[2])
        draw_star_spark(fg, icx, icy, 2, TEAL[3], TEAL[2], TEAL[1])

        # Rising rune sparks above the seal
        for s_idx, sx_off in enumerate((-16, -7, 5, 15, -1, 11)):
            prog = ((f / NF) + s_idx * (1.0 / 6.0)) % 1.0
            sy = int(round(cy_f + 3 - prog * 20.0))
            sx = int(round(cx + sx_off + math.sin(prog * math.tau + s_idx) * 1.5))
            if prog < 0.85 and 0 <= sy < FH:
                c = TEAL[3] if s_idx % 2 == 0 else GOLD[3]
                put_px(fb, sx, sy, c)
                put_px(fg, sx, sy, c)

        add_waystone_halo(fg, None, radius=4, max_alpha=135)

        sheet_b[:, f * FW : (f + 1) * FW] = fb
        sheet_g[:, f * FW : (f + 1) * FW] = fg

    return sheet_b, sheet_g


# ---------------------------------------------------------------------------
# 6. RELIC PLINTH & RELIC PLINTH GLOW (8 frames x 36 x 52 = 288 x 52, foot (18, 44))
# ---------------------------------------------------------------------------
def build_relic_plinth() -> tuple[np.ndarray, np.ndarray]:
    FW, FH, NF = 36, 52, 8
    sheet_b = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    sheet_g = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    cx = 18

    ped = np.zeros((FH, FW, 4), dtype=np.uint8)
    ped_g = np.zeros((FH, FW, 4), dtype=np.uint8)
    for y in range(27, 46):
        if y >= 42:
            hw = 10
            oh = 0.85 if y == 42 else 0.0
        elif y >= 38:
            hw = 8
            oh = 0.9 if y == 38 else 0.0
        elif y >= 30:
            hw = 5
            oh = 1.65 if y == 30 else (1.0 if y == 31 else (0.5 if y == 32 else 0.0))
        else:
            hw = 7
            oh = 0.35 if y == 29 else 0.0
        for ox in range(-hw, hw + 1):
            px = cx + ox
            nx = abs(ox) / max(1.0, float(hw))
            drop = int(round(2.0 * math.sqrt(max(0.0, 1.0 - nx * nx)))) if y >= 29 else 0
            py = min(FH - 2, y + drop)
            if y in (42, 38):
                joint = abs(ox) == 4
                col = MARBLE[1] if joint else cylindrical_marble_shade(ox, hw, flutes=0, y_var=0.8)
            elif y in (45, 41):
                col = MARBLE[0]
            elif y in (27, 28, 29):
                col = cylindrical_gold_shade(ox, hw, overhang_ao=0.8 if y == 29 else 0.0, band_hi=0.3 if y == 27 else 0.0)
            elif y == 37:
                col = cylindrical_gold_shade(ox, 6, overhang_ao=0.45)
            else:
                if ox == 0 and 31 <= y <= 36:
                    col = TEAL[3] if y % 2 == 1 else TEAL[2]
                    put_px(ped_g, px, py, col)
                else:
                    joint = (y >= 43 and abs(ox) == 5)
                    if joint:
                        col = MARBLE[0]
                    elif 31 <= y <= 36:
                        if ox in (-3, 2, 4):
                            col = MARBLE[1] if ox < 0 else MARBLE[0]
                        elif ox in (-4, -2):
                            col = MARBLE[5] if oh < 0.3 else MARBLE[3]
                        elif ox == -1:
                            col = MARBLE[3] if oh < 0.3 else MARBLE[1]
                        elif ox == 1:
                            col = MARBLE[3] if oh < 0.3 else MARBLE[2]
                        elif ox == 3:
                            col = MARBLE[2] if oh < 0.3 else MARBLE[1]
                        else:
                            col = cylindrical_marble_shade(ox, hw, flutes=3, overhang_ao=oh)
                        if oh >= 0.9:
                            col = MARBLE[0] if ox >= 0 else MARBLE[1]
                    else:
                        col = cylindrical_marble_shade(ox, hw, flutes=0, overhang_ao=oh)
            put_px(ped, px, py, col)
    apply_tinted_outline(ped, INK_MARBLE)

    ys_f, xs_f = np.mgrid[0:FH, 0:FW]
    sh_mask = (np.hypot((xs_f - (cx + 1.0)) / 12.5, (ys_f - 47.0) / 3.8) <= 1.0) & (ped[..., 3] == 0)

    for f in range(NF):
        fb = np.zeros((FH, FW, 4), dtype=np.uint8)
        fg = np.zeros((FH, FW, 4), dtype=np.uint8)
        phase = f / NF * math.tau
        dish_y = 19 + int(round(math.sin(phase) * 1.4))

        dish = np.zeros((FH, FW, 4), dtype=np.uint8)
        for oy in range(-2, 4):
            hw = 8 - max(0, oy * 2)
            for ox in range(-hw, hw + 1):
                if oy == -2:
                    col = cylindrical_gold_shade(ox, hw, band_hi=0.25)
                elif oy == -1:
                    col = (TEAL[3] if abs(ox) <= 2 else TEAL[2]) if abs(ox) < 5 else cylindrical_gold_shade(ox, hw)
                    if abs(ox) < 5:
                        put_px(fg, cx + ox, dish_y + oy, col)
                else:
                    # Faceted conical marble bowl underside with stronger bottom shadow & vertical ribs
                    rib = (ox % 3 == 0)
                    oh_d = 0.5 + oy * 0.45 + (0.35 if rib else 0.0)
                    col = cylindrical_marble_shade(ox, max(1, hw), flutes=0, overhang_ao=oh_d)
                put_px(dish, cx + ox, dish_y + oy, col)
        apply_tinted_outline(dish, INK_MARBLE)

        seed_y = dish_y - 6 - int(round(math.cos(phase) * 1.0))
        draw_star_spark(dish, cx, seed_y, 1 if f % 2 == 0 else 2, TEAL[3], GOLD[3], TEAL[1])
        draw_star_spark(fg, cx, seed_y, 1 if f % 2 == 0 else 2, TEAL[3], TEAL[2], TEAL[1])

        fb[sh_mask] = (12, 8, 24, 150)
        pm = ped[..., 3] > 0
        fb[pm] = ped[pm]
        pgm = ped_g[..., 3] > 0
        fg[pgm] = ped_g[pgm]
        dm = dish[..., 3] > 0
        fb[dm] = dish[dm]

        solid_non_emit = (fb[..., 3] >= 200) & (fg[..., 3] == 0)
        add_waystone_halo(fg, solid_non_emit, radius=5, max_alpha=145)

        sheet_b[:, f * FW : (f + 1) * FW] = fb
        sheet_g[:, f * FW : (f + 1) * FW] = fg

    return sheet_b, sheet_g


# ---------------------------------------------------------------------------
# 7. COSMOS ISLANDS 0..2 + GLOW (floating outer marble & crystal fragments)
# ---------------------------------------------------------------------------
def build_cosmos_island(variant: int) -> tuple[np.ndarray, np.ndarray]:
    specs = [
        (96, 72, 34, 16, 24, 5),
        (64, 52, 22, 11, 18, 17),
        (44, 38, 13, 7, 13, 31),
    ]
    W, H, rx, ry, top_cy, seed = specs[variant]
    base = np.zeros((H, W, 4), dtype=np.uint8)
    glow = np.zeros((H, W, 4), dtype=np.uint8)
    cx = W // 2

    ys, xs = np.mgrid[0:H, 0:W]
    ang = np.arctan2((ys - top_cy) / ry, (xs - cx) / rx)
    wob = (
        0.14 * np.sin(ang * 3.0 + seed)
        + 0.09 * np.cos(ang * 5.0 - seed * 0.7)
        + 0.05 * np.sin(ang * 7.0 + 1.1)
    )
    ell = np.hypot((xs - cx) / rx, (ys - top_cy) / ry) + wob
    top = ell <= 1.0
    if variant == 2:
        top |= np.hypot((xs - (cx + 12)) / 6.5, (ys - (top_cy + 10)) / 4.0) <= 1.0

    top_pad = np.pad(top, ((1, 1), (0, 0)), constant_values=False)
    lips = top_pad[1:-1, :] & ~top_pad[2:, :]
    ly_arr, lx_arr = np.where(lips)
    for ly, lx in zip(ly_arr.tolist(), lx_arr.tolist()):
        keel = max(0.0, 1.0 - abs(lx - cx) / (rx * 1.05))
        ridge = 1.0 - abs(((lx * 0.16 + seed * 0.1) % 1.0) - 0.5) * 2.0
        max_d = H - 3 - ly
        depth = min(
            max_d,
            max(5, int(round(6 + (22 if variant == 0 else (15 if variant == 1 else 10)) * keel + 6 * ridge))),
        )
        for dy in range(1, depth + 1):
            yy = ly + dy
            if yy >= H or top[yy, lx]:
                break
            frac = dy / max(depth, 1)
            crease = ((lx + seed) % 6 == 0)
            strata = (dy % 5 == 0)
            if dy <= 2:
                col = MARBLE[1] if lx < cx else MARBLE[0]
            elif dy == 3 and variant < 2 and lx % 4 < 2:
                col = GOLD[0]
            else:
                idx = max(0, min(3, int(round(1.6 + (0.7 if lx < cx else -0.6) - frac * 1.15 - (0.7 if crease else 0.0) - (0.35 if strata else 0.0)))))
                col = CLIFF[idx]
            base[yy, lx] = (*col, 255)
            if dy == depth // 2 and abs(lx - cx) in (3, 9) and variant < 2:
                base[yy, lx] = (*TEAL[1], 255)
                glow[yy, lx] = (*TEAL[2], 255)

    apply_tinted_outline(base, INK_ABYSS)

    b_row = ys // 10
    b_col = (xs + (b_row % 2) * 6) // 14
    cid = b_row * 20 + b_col
    joint = ((cid != np.roll(cid, -1, 0)) | (cid != np.roll(cid, -1, 1))) & top
    bevel = (((cid != np.roll(cid, 1, 0)) | (cid != np.roll(cid, 1, 1))) & top) & ~joint
    bevel_br = (((cid != np.roll(cid, -2, 0)) | (cid != np.roll(cid, -2, 1))) & top) & ~joint
    for py in range(H):
        for px in range(W):
            if not top[py, px]:
                continue
            b_tone = int(cid[py, px] % 3)
            vein = ((px + py * 2 + seed) % 13 == 0) and not joint[py, px]
            if joint[py, px]:
                col = MARBLE[0]
            elif bevel[py, px]:
                col = MARBLE[5] if px < cx else MARBLE[4]
            elif bevel_br[py, px]:
                col = MARBLE[1]
            else:
                base_m = (3 if (px < cx + 4 and py < top_cy + 3) else 2) + (1 if b_tone == 0 and px < cx else (-1 if b_tone == 2 else 0))
                col = MARBLE[max(1, min(4, base_m - (1 if vein else 0)))]
            r_in = math.hypot((px - cx) / (rx * 0.65), (py - top_cy) / (ry * 0.65))
            if variant < 2 and 0.82 <= r_in <= 0.98:
                col = cylindrical_gold_shade(px - cx, int(rx * 0.65))
            elif variant == 0 and 0.72 <= r_in < 0.82 and px < cx + 8:
                col = TEAL[2]
                put_px(glow, px, py, TEAL[2])
            base[py, px] = (*col, 255)

    empty = base[..., 3] == 0
    tdil = (
        np.pad(top, 1, constant_values=False)[:-2, 1:-1]
        | np.pad(top, 1, constant_values=False)[2:, 1:-1]
        | np.pad(top, 1, constant_values=False)[1:-1, :-2]
        | np.pad(top, 1, constant_values=False)[1:-1, 2:]
    )
    base[tdil & empty] = (*INK_MARBLE, 255)

    cryst_layer = np.zeros((H, W, 4), dtype=np.uint8)
    if variant == 0:
        draw_faceted_crystal_ray(cryst_layer, glow, cx - 10, top_cy, -math.pi * 0.56, 0.0, 17.0, 3.6, 0.8)
        draw_faceted_crystal_ray(cryst_layer, glow, cx - 5, top_cy + 1, -math.pi * 0.36, 0.0, 12.0, 2.8, 0.4)
        for oy in range(-9, 3):
            for ox in range(-5, 6):
                if abs(ox) <= (4 if oy < -2 else 5):
                    c = GOLD[2] if oy == -3 else (MARBLE[4] if ox < 0 else MARBLE[1])
                    put_px(cryst_layer, cx + 14 + ox, top_cy - 1 + oy, c)
        apply_tinted_outline(cryst_layer, INK_MARBLE)
    elif variant == 1:
        draw_faceted_crystal_ray(cryst_layer, glow, cx + 4, top_cy, -math.pi * 0.45, 0.0, 13.5, 3.0, 0.7)
    else:
        draw_faceted_crystal_ray(cryst_layer, glow, cx - 2, top_cy, -math.pi * 0.52, 0.0, 9.5, 2.4, 0.7)

    cm = cryst_layer[..., 3] > 0
    base[cm] = cryst_layer[cm]

    solid_non_emit = (base[..., 3] >= 200) & (glow[..., 3] == 0)
    add_waystone_halo(glow, solid_non_emit, radius=5, max_alpha=150)

    return base, glow


# ---------------------------------------------------------------------------
# 8. STAR MOTE (4 frames x 8 x 8 = 32 x 8)
# ---------------------------------------------------------------------------
def build_star_mote() -> np.ndarray:
    FW, FH, NF = 8, 8, 4
    sheet = np.zeros((FH, FW * NF, 4), dtype=np.uint8)
    cx, cy = 3, 3

    f0 = sheet[:, 0:8]
    put_px(f0, cx, cy, TEAL[3])
    put_px(f0, cx + 1, cy, TEAL[1])
    put_px(f0, cx, cy + 1, GOLD[2])

    f1 = sheet[:, 8:16]
    draw_star_spark(f1, cx, cy, 1, TEAL[3], TEAL[2])

    f2 = sheet[:, 16:24]
    draw_star_spark(f2, cx, cy, 2, TEAL[3], TEAL[2], GOLD[3])
    for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
        put_px(f2, cx + dx, cy + dy, TEAL[1])

    f3 = sheet[:, 24:32]
    draw_star_spark(f3, cx, cy, 1, GOLD[3], TEAL[1])

    return sheet


# ---------------------------------------------------------------------------
# PYTHON VISUAL VERIFICATION CONTACT SHEET
# ---------------------------------------------------------------------------
def build_contact_preview(
    out_path: pathlib.Path,
    floor_b: np.ndarray,
    floor_g: np.ndarray,
    throne_b: np.ndarray,
    throne_g: np.ndarray,
    pylon_b: np.ndarray,
    pylon_g: np.ndarray,
    bal_b: np.ndarray,
    bal_g: np.ndarray,
    seal_b: np.ndarray,
    seal_g: np.ndarray,
    relic_b: np.ndarray,
    relic_g: np.ndarray,
    islands: list[tuple[np.ndarray, np.ndarray]],
    mote: np.ndarray,
) -> None:
    """Composes a full Star Hall scene + 2x sprite close-ups with accurate alpha blending."""
    PW, PH = 1180, 900
    canvas = np.zeros((PH, PW, 4), dtype=np.uint8)

    ys, xs = np.mgrid[0:PH, 0:PW]
    neb = np.sin(xs * 0.014 + ys * 0.009) * 0.5 + np.cos(xs * 0.008 - ys * 0.015) * 0.5
    b = BAYER4[ys % 4, xs % 4]
    c_idx = np.clip(((neb + 1.0) * 1.4 + b * 0.8).astype(np.int32), 0, 3)
    cosmos_pal = np.array([rgb("040208"), rgb("09060f"), rgb("120b24"), rgb("172838")], dtype=np.uint8)
    canvas[..., :3] = cosmos_pal[c_idx]
    canvas[..., 3] = 255

    sh = vhash(xs, ys, 777)
    canvas[sh > 0.9965, :3] = MARBLE[4]
    canvas[sh > 0.9990, :3] = TEAL[3]
    for sx, sy in ((64, 90), (590, 120), (88, 420), (610, 510), (72, 740), (585, 780)):
        draw_star_spark(canvas, sx, sy, 2, GOLD[3] if sx % 2 == 0 else TEAL[3], TEAL[1], GOLD[2])

    def blit(dst: np.ndarray, src: np.ndarray, x0: int, y0: int) -> None:
        sh_h, sh_w = src.shape[:2]
        dx0, dy0 = max(0, x0), max(0, y0)
        dx1, dy1 = min(dst.shape[1], x0 + sh_w), min(dst.shape[0], y0 + sh_h)
        if dx0 >= dx1 or dy0 >= dy1:
            return
        sub_s = src[dy0 - y0 : dy1 - y0, dx0 - x0 : dx1 - x0]
        sub_d = dst[dy0:dy1, dx0:dx1]
        a = sub_s[..., 3:4].astype(np.float32) / 255.0
        sub_d[..., :3] = (sub_d[..., :3] * (1.0 - a) + sub_s[..., :3] * a).astype(np.uint8)

    ox, oy = 60, 40
    island_spots = [
        (0, ox - 42, oy + 110),
        (1, ox + 518, oy + 135),
        (1, ox - 32, oy + 455),
        (0, ox + 504, oy + 465),
        (2, ox + 46, oy + 690),
        (2, ox + 478, oy + 705),
    ]
    for iv, ix, iy in island_spots:
        blit(canvas, islands[iv][0], ix, iy)
        blit(canvas, islands[iv][1], ix, iy)

    blit(canvas, floor_b, ox, oy)
    blit(canvas, floor_g, ox, oy)

    for bx in (ox + 150, ox + 362):
        blit(canvas, bal_b, bx, oy + 378 - 32)
        blit(canvas, bal_g, bx, oy + 378 - 32)

    tf0_b, tf0_g = throne_b[:, 0:160], throne_g[:, 0:160]
    blit(canvas, tf0_b, ox + 280 - 80, oy + 162 - 148)
    blit(canvas, tf0_g, ox + 280 - 80, oy + 162 - 148)

    rf0_b, rf0_g = relic_b[:, 0:36], relic_g[:, 0:36]
    for rpx, rpy in ((174, 180), (386, 180), (204, 224)):
        blit(canvas, rf0_b, ox + rpx - 18, oy + rpy - 44)
        blit(canvas, rf0_g, ox + rpx - 18, oy + rpy - 44)

    pylon_spots = [
        (204, 344, 0),
        (356, 344, 2),
        (228, 480, 4),
        (332, 480, 6),
        (204, 612, 1),
        (356, 612, 5),
    ]
    for px, py, fr in pylon_spots:
        pf_b = pylon_b[:, fr * 48 : (fr + 1) * 48]
        pf_g = pylon_g[:, fr * 48 : (fr + 1) * 48]
        blit(canvas, pf_b, ox + px - 24, oy + py - 84)
        blit(canvas, pf_g, ox + px - 24, oy + py - 84)

    sf0_b, sf0_g = seal_b[:, 0:64], seal_g[:, 0:64]
    blit(canvas, sf0_b, ox + 280 - 32, oy + 715 - 24)
    blit(canvas, sf0_g, ox + 280 - 32, oy + 715 - 24)

    def upscale2x(arr: np.ndarray) -> np.ndarray:
        return np.repeat(np.repeat(arr, 2, axis=0), 2, axis=1)

    rx0 = 670
    for k, fr in enumerate((0, 4)):
        tb = upscale2x(throne_b[:, fr * 160 : (fr + 1) * 160])
        tg = upscale2x(throne_g[:, fr * 160 : (fr + 1) * 160])
        blit(canvas, tb, rx0 + k * 252, 20)
        blit(canvas, tg, rx0 + k * 252, 20)

    for k, fr in enumerate((0, 2, 4, 6)):
        pb = upscale2x(pylon_b[:, fr * 48 : (fr + 1) * 48])
        pg = upscale2x(pylon_g[:, fr * 48 : (fr + 1) * 48])
        blit(canvas, pb, rx0 + k * 116, 392)
        blit(canvas, pg, rx0 + k * 116, 392)

    for k, fr in enumerate((0, 3)):
        sb = upscale2x(seal_b[:, fr * 64 : (fr + 1) * 64])
        sg = upscale2x(seal_g[:, fr * 64 : (fr + 1) * 64])
        blit(canvas, sb, rx0 + k * 145, 602)
        blit(canvas, sg, rx0 + k * 145, 602)

    blit(canvas, upscale2x(bal_b), rx0 + 300, 612)
    blit(canvas, upscale2x(bal_g), rx0 + 300, 612)

    blit(canvas, upscale2x(relic_b[:, 0:36]), rx0 + 412, 592)
    blit(canvas, upscale2x(relic_g[:, 0:36]), rx0 + 412, 592)

    ix_cur = rx0
    for iv in range(3):
        ib = upscale2x(islands[iv][0])
        ig = upscale2x(islands[iv][1])
        blit(canvas, ib, ix_cur, 725)
        blit(canvas, ig, ix_cur, 725)
        ix_cur += ib.shape[1] + 16

    mote4x = np.repeat(np.repeat(mote, 4, axis=0), 4, axis=1)
    blit(canvas, mote4x, rx0 + 340, 845)

    save_png(out_path, canvas)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    floor_b, floor_g = build_floor()
    save_png(OUT / "floor_base.png", floor_b)
    save_png(OUT / "floor_glow.png", floor_g)

    throne_b, throne_g = build_throne()
    save_png(OUT / "throne.png", throne_b)
    save_png(OUT / "throne_glow.png", throne_g)

    pylon_b, pylon_g = build_pylon()
    save_png(OUT / "pylon.png", pylon_b)
    save_png(OUT / "pylon_glow.png", pylon_g)

    bal_b, bal_g = build_balustrade()
    save_png(OUT / "balustrade.png", bal_b)
    save_png(OUT / "balustrade_glow.png", bal_g)

    seal_b, seal_g = build_return_seal()
    save_png(OUT / "return_seal.png", seal_b)
    save_png(OUT / "return_seal_glow.png", seal_g)

    relic_b, relic_g = build_relic_plinth()
    save_png(OUT / "relic_plinth.png", relic_b)
    save_png(OUT / "relic_plinth_glow.png", relic_g)

    islands: list[tuple[np.ndarray, np.ndarray]] = []
    for idx in range(3):
        ib, ig = build_cosmos_island(idx)
        save_png(OUT / f"cosmos_island_{idx}.png", ib)
        save_png(OUT / f"cosmos_island_{idx}_glow.png", ig)
        islands.append((ib, ig))

    mote = build_star_mote()
    save_png(OUT / "star_mote.png", mote)

    print(f"Generated 17 Star Hall PNG assets in {OUT}")

    if len(sys.argv) > 1:
        preview_path = pathlib.Path(sys.argv[1])
        build_contact_preview(
            preview_path,
            floor_b,
            floor_g,
            throne_b,
            throne_g,
            pylon_b,
            pylon_g,
            bal_b,
            bal_g,
            seal_b,
            seal_g,
            relic_b,
            relic_g,
            islands,
            mote,
        )
        print(f"Saved contact preview to {preview_path}")


if __name__ == "__main__":
    main()
