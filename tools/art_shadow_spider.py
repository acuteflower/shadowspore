#!/usr/bin/env python3
"""Shadowspore 2.0 — Vectorized 3D-Ellipsoid Pixel Generator for Shadow Spider Body.

Generates:
  - assets/enemies/shadow_spider_body.png       (320x216: 8 true facings E..NE x 6 rows of 40x36)
  - assets/enemies/shadow_spider_body_glow.png  (320x216: exact unlit bioluminescent vein & ocelli mask)

Rows (0..5):
  0..3 : 4-phase organic Opisthosoma breathing & spore-heart pulsation
  4    : Engorged / coiled strike-swell (SILK_GRAPPLE / VENOM_LUNGE windup)
  5    : Battle-cracked carapace (< 50% HP & EXPOSED weakpoint state)
"""

from __future__ import annotations

import math
import pathlib
import struct
import sys
import zlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT_BODY = ROOT / "assets" / "enemies" / "shadow_spider_body.png"
OUT_GLOW = ROOT / "assets" / "enemies" / "shadow_spider_body_glow.png"

CELL_W = 40
CELL_H = 36
COLS = 8  # E, SE, S, SW, W, NW, N, NE (never mirrored!)
ROWS = 6  # 0..3 breathe, 4 swell/coil, 5 cracked/exposed
SQUASH = 0.78  # 3/4 camera vertical foreshortening matching SpiderRig.SQUASH


def hex_rgba(code: str) -> tuple[int, int, int, int]:
    return (int(code[0:2], 16), int(code[2:4], 16), int(code[4:6], 16), 255)


COL_OUTLINE = hex_rgba("040208")
COL_FLESH_0 = hex_rgba("07040d")
COL_FLESH_1 = hex_rgba("0e0919")
COL_FLESH_2 = hex_rgba("1a1030")
COL_FLESH_3 = hex_rgba("221740")
COL_RIM = hex_rgba("5a36b8")

# Strictly ShadowEmission.COLORS so ShadowEmission.mask_for() extracts 100% of glow and 0% of flesh:
COL_VEIN_DIM = hex_rgba("5c2fb8")
COL_VEIN = hex_rgba("8a4dff")
COL_CORE = hex_rgba("ecd2ff")
COL_EYE = hex_rgba("ff4fd8")
COL_EYE_HOT = hex_rgba("ffe3fb")

EMISSIVE_SET = {COL_VEIN_DIM, COL_VEIN, COL_CORE, COL_EYE, COL_EYE_HOT}

BAYER4 = np.array(
    [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ],
    dtype=np.float32,
) / 16.0


def write_png(path: pathlib.Path, rgba: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    h, w, _ = rgba.shape
    raw_rows = [b"\x00" + rgba[y].tobytes() for y in range(h)]
    raw = b"".join(raw_rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def build_ellipsoids(row: int) -> list[tuple[float, float, float, float, float, float, float, int]]:
    """Part codes: 1=abdomen, 2=abdomen_crest, 3=spinneret, 4=waist, 5=prosoma, 6=brow, 7=chelicera, 8=coxa."""
    breathe = 0.0
    swell = 0.0
    if row < 4:
        breathe = math.sin(row * (math.pi * 0.5))
    elif row == 4:
        swell = 1.0
    elif row == 5:
        breathe = 0.35

    ab_ru = 5.55 + 0.34 * breathe + 0.65 * swell
    ab_rv = 4.75 + 0.30 * breathe + 0.55 * swell
    ab_rz = 4.30 + 0.28 * breathe + 0.55 * swell
    ab_u = -4.60 - 0.22 * swell
    ab_z = 1.50 + 0.20 * breathe + 0.55 * swell
    ab_pitch = -0.19 - 0.08 * swell

    pro_u = 3.70 + 0.22 * swell
    pro_z = 0.20 + 0.24 * swell

    return [
        (ab_u, 0.0, ab_z, ab_ru, ab_rv, ab_rz, ab_pitch, 1),
        (ab_u + 0.4, 0.0, ab_z + ab_rz * 0.58, ab_ru * 0.68, ab_rv * 0.50, 1.55, ab_pitch, 2),
        (ab_u - ab_ru * 0.88, -1.35, ab_z - 0.45, 1.70, 0.92, 0.95, -0.12, 3),
        (ab_u - ab_ru * 0.88, +1.35, ab_z - 0.45, 1.70, 0.92, 0.95, -0.12, 3),
        (-0.15, 0.0, 0.25, 1.50, 1.68, 1.40, 0.0, 4),
        (pro_u, 0.0, pro_z, 4.20, 3.75, 2.60, 0.08, 5),
        (pro_u + 2.25, 0.0, pro_z + 1.10, 1.95, 2.75, 1.55, 0.10, 6),
        (pro_u + 3.65, -1.35, pro_z - 0.65, 1.55, 1.05, 1.35, 0.26, 7),
        (pro_u + 3.65, +1.35, pro_z - 0.65, 1.55, 1.05, 1.35, 0.26, 7),
        (pro_u + 1.45, -3.45, pro_z - 0.45, 1.35, 1.15, 1.10, 0.0, 8),
        (pro_u + 1.45, +3.45, pro_z - 0.45, 1.35, 1.15, 1.10, 0.0, 8),
        (pro_u - 1.10, -3.65, pro_z - 0.45, 1.35, 1.15, 1.10, 0.0, 8),
        (pro_u - 1.10, +3.65, pro_z - 0.45, 1.35, 1.15, 1.10, 0.0, 8),
    ]


def render_cell(sector: int, row: int) -> np.ndarray:
    img = np.zeros((CELL_H, CELL_W, 4), dtype=np.uint8)

    ang = sector * (math.pi / 4.0)
    ca, sa = math.cos(ang), math.sin(ang)
    fx, fy = ca, sa
    rx, ry = -sa, ca

    cx = CELL_W * 0.5
    cy = CELL_H * 0.5 + 1.5

    lx, ly, lz = -0.50, -0.52, 0.69
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ln, ly / ln, lz / ln

    # Vectorized (H, W, Z) grid
    ys = (np.arange(CELL_H, dtype=np.float32) + 0.5 - cy)[:, None, None]
    xs = (np.arange(CELL_W, dtype=np.float32) + 0.5 - cx)[None, :, None]
    zs = np.linspace(10.5, -4.5, 96, dtype=np.float32)[None, None, :]

    gx = np.broadcast_to(xs, (CELL_H, CELL_W, 96))
    gy = (ys + zs * 0.82) / SQUASH
    u_grid = gx * fx + gy * fy
    v_grid = gx * rx + gy * ry
    z_grid = np.broadcast_to(zs, (CELL_H, CELL_W, 96))

    best_z_idx = np.full((CELL_H, CELL_W), 999, dtype=np.int32)
    part_id = np.zeros((CELL_H, CELL_W), dtype=np.int32)
    nl_buf = np.zeros((CELL_H, CELL_W), dtype=np.float32)
    nz_buf = np.zeros((CELL_H, CELL_W), dtype=np.float32)

    for cu, cv, cz, ru, rv, rz, pitch, pcode in build_ellipsoids(row):
        du = u_grid - cu
        dv = v_grid - cv
        dz = z_grid - cz
        if abs(pitch) > 1e-4:
            cp, sp = math.cos(pitch), math.sin(pitch)
            du_r = du * cp + dz * sp
            dz_r = -du * sp + dz * cp
        else:
            du_r = du
            dz_r = dz

        rib = (1.0 - 0.052 * np.cos(du_r * 1.75)) if pcode == 1 else 1.0
        d2 = (du_r / (ru * rib)) ** 2 + (dv / rv) ** 2 + (dz_r / rz) ** 2
        inside = d2 <= 1.0
        any_hit = np.any(inside, axis=2)
        first_idx = np.where(any_hit, np.argmax(inside, axis=2), 999)
        closer = first_idx < best_z_idx
        if not np.any(closer):
            continue

        yy, xx = np.nonzero(closer)
        zz = first_idx[yy, xx]
        best_z_idx[yy, xx] = zz
        part_id[yy, xx] = pcode

        nu_l = du_r[yy, xx, zz] / (ru * ru)
        nv_l = dv[yy, xx, zz] / (rv * rv)
        nz_l = dz_r[yy, xx, zz] / (rz * rz)
        if abs(pitch) > 1e-4:
            cp, sp = math.cos(pitch), math.sin(pitch)
            nu = nu_l * cp - nz_l * sp
            nz = nu_l * sp + nz_l * cp
        else:
            nu = nu_l
            nz = nz_l
        wx = nu * fx + nv_l * rx
        wy = nu * fy + nv_l * ry
        wz = nz
        wn = np.maximum(1e-5, np.sqrt(wx * wx + wy * wy + wz * wz))
        wx, wy, wz = wx / wn, wy / wn, wz / wn
        nl_buf[yy, xx] = np.maximum(0.0, wx * lx + wy * ly + wz * lz)
        nz_buf[yy, xx] = wz

    # Enforce 1-px border margin for clean 1-px outline
    best_z_idx[0, :] = 999
    best_z_idx[-1, :] = 999
    best_z_idx[:, 0] = 999
    best_z_idx[:, -1] = 999
    hit_mask = best_z_idx < 999

    yy_all, xx_all = np.nonzero(hit_mask)
    zz_all = best_z_idx[yy_all, xx_all]
    u_buf = np.zeros((CELL_H, CELL_W), dtype=np.float32)
    v_buf = np.zeros((CELL_H, CELL_W), dtype=np.float32)
    z_buf = np.zeros((CELL_H, CELL_W), dtype=np.float32)
    u_buf[yy_all, xx_all] = u_grid[yy_all, xx_all, zz_all]
    v_buf[yy_all, xx_all] = v_grid[yy_all, xx_all, zz_all]
    z_buf[yy_all, xx_all] = z_grid[yy_all, xx_all, zz_all]

    # 1. Shade lit Void-chitin carapace
    for py, px in zip(yy_all.tolist(), xx_all.tolist()):
        u = float(u_buf[py, px])
        z = float(z_buf[py, px])
        nl = float(nl_buf[py, px])
        pcode = int(part_id[py, px])
        bayer = float(BAYER4[py & 3, px & 3])

        if pcode in (4, 8):
            nl *= 0.58
        elif pcode == 5:
            nl *= 1.08

        # Subtle transverse chitin tergite ridge lines on Opisthosoma
        if pcode == 1 and math.cos(u * 1.75) < -0.72:
            nl *= 0.78

        shade_v = nl + (bayer - 0.5) * 0.10
        if shade_v < 0.32:
            col = COL_FLESH_0
        elif shade_v < 0.54:
            col = COL_FLESH_1
        elif shade_v < 0.75:
            col = COL_FLESH_2
        else:
            col = COL_FLESH_3

        top_left_edge = (not hit_mask[py - 1, px]) or (not hit_mask[py, px - 1])
        if top_left_edge and nl > 0.44 and pcode in (1, 2, 5, 6):
            col = COL_RIM

        if -0.85 <= u <= 0.65 and z < 2.2:
            col = COL_FLESH_0

        img[py, px] = col

    # 2. Bioluminescent Mycelium Veins & Pulsing Opisthosoma Spore-Core
    pulse_boost = (0.5 + 0.5 * math.sin(row * math.pi * 0.5)) if row < 4 else 1.0
    for py, px in zip(yy_all.tolist(), xx_all.tolist()):
        if not (hit_mask[py - 1, px] and hit_mask[py + 1, px] and hit_mask[py, px - 1] and hit_mask[py, px + 1]):
            continue
        u = float(u_buf[py, px])
        v = float(v_buf[py, px])
        nz = float(nz_buf[py, px])
        if nz < 0.12:
            continue

        du_c = (u - (-4.35)) / (1.85 if row >= 4 else 1.45)
        dv_c = v / (1.55 if row >= 4 else 1.15)
        dc2 = du_c * du_c + dv_c * dv_c
        if dc2 <= 0.36:
            img[py, px] = COL_CORE if (pulse_boost > 0.35 or row >= 4) else COL_VEIN
            continue
        elif dc2 <= 0.95:
            img[py, px] = COL_VEIN if pulse_boost > 0.2 else COL_VEIN_DIM
            continue

        if -8.3 <= u <= -1.3:
            spine_d = abs(v)
            rib_1 = abs(abs(v) - (1.2 + (u + 3.0) * -0.55)) if -5.8 <= u <= -1.8 else 99.0
            rib_2 = abs(abs(v) - (1.1 + (u + 5.6) * -0.60)) if -8.2 <= u <= -4.6 else 99.0
            if spine_d < 0.50 and -7.4 <= u <= -1.5:
                img[py, px] = COL_VEIN if (u > -5.5 or row >= 4) else COL_VEIN_DIM
            elif min(rib_1, rib_2) < 0.50:
                img[py, px] = COL_VEIN if row >= 4 else COL_VEIN_DIM

            if row == 5:
                crack_a = abs((u + 4.4) * 0.72 + v * 0.68)
                crack_b = abs((u + 5.8) * 0.65 - v * 0.75)
                if min(crack_a, crack_b) < 0.68 and abs(v) < 3.6:
                    img[py, px] = COL_CORE if min(crack_a, crack_b) < 0.30 else COL_VEIN

        if 2.0 <= u <= 4.5 and abs(v) < 0.48:
            img[py, px] = COL_VEIN if row == 4 else COL_VEIN_DIM

    # 3. Fierce, distinctly separated Arachnid Ocelli Cluster!
    #    - Never merges across midline (dark chitin nasal bridge kept clear!)
    #    - Strictly hidden when head faces away from camera (North / NW / NE back-of-head)
    pro_u = 3.70 + (0.22 if row == 4 else 0.0)
    pro_z = 0.20 + (0.24 if row == 4 else 0.0)
    ocelli = [
        # Two sharp primary hunter eyes separated cleanly by ~3.3 units across midline:
        (pro_u + 3.65, -1.65, pro_z + 1.15, 0.90, -0.43, True),
        (pro_u + 3.65, +1.65, pro_z + 1.15, 0.90, +0.43, True),
        # Upper-outer lateral ocelli (distinctly stepped back & higher so they form an arachnid V-crown, never a smile!):
        (pro_u + 2.15, -2.95, pro_z + 1.75, 0.38, -0.92, False),
        (pro_u + 2.15, +2.95, pro_z + 1.75, 0.38, +0.92, False),
    ]
    stamped_eyes: list[tuple[int, int]] = []
    for eu, ev, ez, fu, fv, primary in ocelli:
        # Ground-plane normal dot south-facing camera (+y in screen = +1.0):
        wy_f = fu * fy + fv * ry
        if wy_f < (-0.05 if not primary else 0.08):
            continue
        gx_e = eu * fx + ev * rx
        gy_e = eu * fy + ev * ry
        ex = int(round(cx + gx_e - 0.5))
        ey = int(round(cy + gy_e * SQUASH - ez * 0.82 - 0.5))
        if not (1 <= ex < CELL_W - 1 and 1 <= ey < CELL_H - 1):
            continue
        # Ensure at least 1 dark chitin pixel separates left & right eyes so they never fuse into a curve!
        if any(abs(ex - ox) + abs(ey - oy) <= 1 for ox, oy in stamped_eyes):
            continue
        stamped_eyes.append((ex, ey))
        img[ey, ex] = COL_EYE_HOT if (primary and wy_f > 0.45) else COL_EYE
        hit_mask[ey, ex] = True
        if primary and wy_f > 0.32 and 1 <= ey - 1 < CELL_H - 1 and hit_mask[ey - 1, ex]:
            img[ey - 1, ex] = COL_EYE  # Vertical fierce slit/brow accent rather than horizontal smile!

    # 4. Crisp 1-px #040208 Outline Pass
    outlined = img.copy()
    for py in range(CELL_H):
        for px in range(CELL_W):
            if hit_mask[py, px]:
                continue
            if (
                (py > 0 and hit_mask[py - 1, px])
                or (py + 1 < CELL_H and hit_mask[py + 1, px])
                or (px > 0 and hit_mask[py, px - 1])
                or (px + 1 < CELL_W and hit_mask[py, px + 1])
            ):
                outlined[py, px] = COL_OUTLINE

    return outlined


def extract_glow_sheet(sheet: np.ndarray) -> np.ndarray:
    glow = np.zeros_like(sheet)
    h, w, _ = sheet.shape
    for y in range(h):
        for x in range(w):
            px = tuple(int(v) for v in sheet[y, x])
            if px in EMISSIVE_SET:
                glow[y, x] = px
    return glow


def render_preview_contact(sheet: np.ndarray, glow: np.ndarray, out_path: pathlib.Path, scale: int = 4) -> None:
    h, w, _ = sheet.shape
    pad = 8
    pw = (w * scale) + pad * 3
    ph = (h * scale) * 2 + pad * 3
    canvas = np.zeros((ph, pw, 4), dtype=np.uint8)
    canvas[:, :] = hex_rgba("141122")

    up_body = np.repeat(np.repeat(sheet, scale, axis=0), scale, axis=1)
    up_glow = np.repeat(np.repeat(glow, scale, axis=0), scale, axis=1)

    top_y = pad
    alpha_b = up_body[:, :, 3:4].astype(np.float32) / 255.0
    bg_top = np.empty_like(up_body)
    bg_top[:, :] = hex_rgba("2f5746")
    canvas[top_y : top_y + h * scale, pad : pad + w * scale, :3] = (
        up_body[:, :, :3] * alpha_b + bg_top[:, :, :3] * (1.0 - alpha_b)
    ).astype(np.uint8)
    canvas[top_y : top_y + h * scale, pad : pad + w * scale, 3] = 255

    bot_y = pad * 2 + h * scale
    bg_bot = np.empty_like(up_glow)
    bg_bot[:, :] = hex_rgba("080612")
    body_dim = (up_body[:, :, :3].astype(np.float32) * 0.35).astype(np.uint8)
    base_night = (body_dim * alpha_b + bg_bot[:, :, :3] * (1.0 - alpha_b)).astype(np.uint8)
    alpha_g = up_glow[:, :, 3:4].astype(np.float32) / 255.0
    canvas[bot_y : bot_y + h * scale, pad : pad + w * scale, :3] = (
        up_glow[:, :, :3] * alpha_g + base_night * (1.0 - alpha_g)
    ).astype(np.uint8)
    canvas[bot_y : bot_y + h * scale, pad : pad + w * scale, 3] = 255

    write_png(out_path, canvas)


def main() -> None:
    sheet = np.zeros((CELL_H * ROWS, CELL_W * COLS, 4), dtype=np.uint8)
    for r in range(ROWS):
        for c in range(COLS):
            sheet[r * CELL_H : (r + 1) * CELL_H, c * CELL_W : (c + 1) * CELL_W] = render_cell(c, r)

    glow = extract_glow_sheet(sheet)
    write_png(OUT_BODY, sheet)
    write_png(OUT_GLOW, glow)
    print(f"Wrote {OUT_BODY} ({sheet.shape[1]}x{sheet.shape[0]}) and {OUT_GLOW}")

    for arg in sys.argv[1:]:
        if arg.startswith("--preview="):
            prev = pathlib.Path(arg.split("=", 1)[1])
            render_preview_contact(sheet, glow, prev)
            print(f"Wrote preview {prev}")


if __name__ == "__main__":
    main()
