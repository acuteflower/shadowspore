#!/usr/bin/env python3
"""Ellie's custom outfits for the modular customization pipeline (`res://data/hero_cosmetics.json`).

Currently provides:
  - `perlenbluete` ("Perlenblüte" — Legendary Seasonal Outfit, Spring 2027):
    Tailored pearl-ivory jacquard silk Qipao with champagne-gold Mandarin stand collar, diagonal overlap placket
    and Pankou frog-knot buttons, short gold-piped silk sleeves with bare porcelain forearms, cohesive diagonal
    rose-blush lotus & misty ice-blue peony embroidery on golden branches, straight-cut knee-length split silk
    panels with high champagne-gold side slits, and delicate pearl-silk ankle-strap slippers.

Preview usage:
  py -3 tools/art_hero_outfit.py preview <out_dir>
"""
import math
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

OUTFIT_IDS = ("perlenbluete",)

_MAT_IDS: dict[str, int] = {}


def ensure_ramps(hero_mod) -> dict[str, int]:
    """Registers custom silk & embroidery material ramps once on `hero_mod.RAMPS` (after plank/moon ramps)."""
    if _MAT_IDS and len(hero_mod.RAMPS) > max(_MAT_IDS.values()):
        return _MAT_IDS
    import hut_lib  # noqa: F401
    import art_hero_carry_stone  # noqa: F401

    hexc = hero_mod.hexc
    defs = [
        # Serene, luminous pearl-alabaster silk! Brighter Band 0 (`#b0a5b8`) & Band 1 (`#d8d0da`) ensure crease folds
        # read as soft warm pearl-silk drapery rather than dark grey spots; `r - b < 0.10` across all 4 shades so
        # Salon dyes tint the silk cleanly while `#ffffff` Original preserves pure warm alabaster-pearl luster!
        ("PEARL_SILK", ["b0a5b8", "d8d0da", "f2ecee", "fffcf6"], 1.0),
        # Champagne-gold piping, Pankou frog-knots & embroidered golden stems (`r - b > 0.20` -> preserved under dyes)
        ("CHAMPAGNE_GOLD", ["8a6428", "c89c46", "f0d07a", "fff5be"], 1.42),
        # Rose-blush & peach-lotus embroidery petals (`r - b > 0.11` -> preserved under dyes)
        ("BLUSH_LOTUS", ["a85c74", "d8869c", "f6bac6", "ffe0e4"], 1.52),
        # Signature misty ice-blue peony blossom & moonlit silk accent (`g - r > 0.14` -> preserved + night lume)
        ("ICE_BLOSSOM", ["3e728a", "62b0c8", "9ce6f2", "e4fdff"], 1.62),
        # Soft jade-celadon leaves & delicate blossom accents (`g - r > 0.14` -> preserved)
        ("CELADON_INK", ["38646c", "549298", "82c4c6", "c6eeea"], 1.42),
    ]
    _MAT_IDS.clear()
    existing = {tuple(tuple(c) for c in r): idx for idx, r in enumerate(hero_mod.RAMPS)}
    for name, hex_list, weight in defs:
        ramp = [hexc(c) for c in hex_list]
        key = tuple(tuple(c) for c in ramp)
        if key in existing:
            idx = existing[key]
        else:
            idx = len(hero_mod.RAMPS)
            hero_mod.RAMPS.append(ramp)
            existing[key] = idx
        _MAT_IDS[name] = idx
        if weight != 1.0:
            hero_mod.DECAL_WEIGHT[idx] = weight
    return _MAT_IDS


def _clip_qipao_panel(q: np.ndarray) -> np.ndarray:
    """Cuts a crisp tailored horizontal Qipao knee hem (`qy >= -0.66`) and clean vertical side slits (`|qx| <= 0.86`)."""
    return (q[..., 1] >= -0.66) & (np.abs(q[..., 0]) <= 0.86)


def paint_surface(p, q: np.ndarray, lam: np.ndarray, mat: np.ndarray, band: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Painterly 3D surface shader for `perlenbluete`: smooth jacquard silk luster, crisp gold collar/placket/slit
    piping, and one cohesive diagonal floral motif (leaving ~80% of the dress serene, luminous pearl silk)."""
    import art_hero3d as hero_mod
    mats = ensure_ramps(hero_mod)
    SILK = mats["PEARL_SILK"]
    GOLD = mats["CHAMPAGNE_GOLD"]
    BLUSH = mats["BLUSH_LOTUS"]
    ICE = mats["ICE_BLOSSOM"]
    CELA = mats["CELADON_INK"]

    qx, qy, qz = q[..., 0], q[..., 1], q[..., 2]
    kind = p.kind

    # Smooth, broad woven silk sheen (gentle low-frequency satin wave — zero noisy checkerboard speckle!)
    sheen = 0.055 * np.sin(qx * 3.2 + qy * 2.4)
    silk_band = np.digitize(lam + sheen, (-0.26, 0.04, 0.44)).astype(np.int16)
    band = np.where(mat == SILK, silk_band, band)

    if kind == "qipao_collar":
        # Crisp champagne-gold top & bottom collar trim + front center Pankou clasp
        rim = (qy > 0.52) | (qy < -0.56)
        clasp = (qz > 0.65) & (np.abs(qx) < 0.38) & (np.abs(qy) < 0.22)
        gold_m = rim | clasp
        mat = np.where(gold_m, GOLD, mat)
        band = np.where(gold_m, np.maximum(band, 2), band)

    elif kind == "qipao_yoke_f":
        # Clean diagonal Qipao overlap placket sweeping from center throat to right underarm (`-qx`)
        front = qz > 0.22
        diag_d = np.abs(qy - (0.58 + 1.15 * qx))
        placket = front & (qx <= 0.08) & (qx >= -0.92) & (diag_d < 0.13)
        mat = np.where(placket, GOLD, mat)
        band = np.where(placket, np.maximum(band, 2), band)

    elif kind == "qipao_chest":
        # Delicate golden stem tip & single celadon bud reaching up toward left rib (+qx), keeping upper chest serene!
        front = qz > 0.34
        stem = front & (qy > -0.68) & (qy < -0.05) & (np.abs(qx - (0.14 + 0.45 * (qy + 0.55))) < 0.08)
        leaf = front & (np.hypot(qx - 0.36, qy + 0.02) < 0.16)
        mat = np.where(leaf, CELA, mat)
        mat = np.where(stem, GOLD, mat)
        band = np.where(leaf | stem, np.maximum(band, 2), band)

    elif kind == "qipao_waist":
        # Focal waist embroidery: Misty Ice-Blue Peony on left waist (`+qx`) + golden branch sweeping down-right (`-qx`)
        front = qz > 0.28
        branch = front & (np.abs(qx - (0.04 + 0.58 * qy)) < 0.10)
        ice_peony = front & (np.hypot(qx - 0.46, qy - 0.06) < 0.34)
        ice_core = front & (np.hypot(qx - 0.46, qy - 0.06) < 0.13)
        leaf_l = front & (np.hypot(qx + 0.28, qy + 0.18) < 0.19)
        mat = np.where(leaf_l, CELA, mat)
        mat = np.where(branch, GOLD, mat)
        mat = np.where(ice_peony, ICE, mat)
        mat = np.where(ice_core, SILK, mat)
        band = np.where(leaf_l | branch | ice_peony, np.maximum(band, 2), band)
        band = np.where(ice_core, 3, band)

    elif kind == "qipao_back_top":
        # Subtle, poetic back-collar blossom motif between her shoulder blades (`qz < -0.36`)
        back = qz < -0.36
        b_stem = back & (np.abs(qx) < 0.07) & (qy > 0.02) & (qy < 0.56)
        b_flw = back & (np.hypot(qx, qy - 0.22) < 0.18)
        b_ice = back & (np.hypot(qx - 0.20, qy + 0.02) < 0.13)
        mat = np.where(b_stem, GOLD, mat)
        mat = np.where(b_flw, BLUSH, mat)
        mat = np.where(b_ice, ICE, mat)
        band = np.where(b_stem | b_flw | b_ice, np.maximum(band, 2), band)

    elif kind == "qipao_sleeve_l":
        # Delicate celadon blossom accent on outer left sleeve (Photos 1 & 2)
        outer = qx > 0.35
        flw = outer & (np.hypot(qy + 0.05, qz - 0.08) < 0.24)
        mat = np.where(flw, CELA, mat)
        band = np.where(flw, np.maximum(band, 2), band)

    elif kind == "qipao_hip":
        # Blooming Rose-Blush Lotus/Peony at right-upper hip (`qx < 0`, Photos 1 & 2) — painted flush on the silk
        # so it NEVER casts dark crease shadows onto the white pearl fabric!
        front = qz > 0.26
        lotus_d = np.hypot(qx + 0.26, qy - 0.10)
        lotus_outer = front & (lotus_d < 0.34)
        lotus_inner = front & (lotus_d < 0.18)
        lotus_gold = front & (lotus_d < 0.09)
        swallow = (qx < -0.62) & (qz > -0.10) & (np.hypot(qy + 0.12, qz - 0.32) < 0.20)
        mat = np.where(swallow, CELA, mat)
        mat = np.where(lotus_outer, BLUSH, mat)
        mat = np.where(lotus_inner, SILK, mat)
        mat = np.where(lotus_gold, GOLD, mat)
        band = np.where(swallow | lotus_outer, np.maximum(band, 2), band)
        band = np.where(lotus_inner | lotus_gold, 3, band)

    elif kind in ("qipao_front", "qipao_back"):
        # Clean, unbroken pearl-ivory skirt with razor-sharp Champagne-Gold bottom hem (`qy <= -0.54` above `-0.66` clip)
        # and high Champagne-Gold side-slit borders (`|qx| >= 0.74` inside `0.86` clip)!
        hem_gold = qy <= -0.53
        slit_gold = (np.abs(qx) >= 0.73) & (qy < 0.62)
        border = hem_gold | slit_gold

        if kind == "qipao_front":
            # Whisper-soft peach-blush & celadon petal accent near lower-left hem (Photos 1 & 3), keeping skirt airy & pure!
            petal_blush = (np.hypot(qx - 0.28, qy + 0.26) < 0.18)
            petal_cela = (np.hypot(qx + 0.30, qy + 0.32) < 0.15)
            mat = np.where(petal_blush, BLUSH, mat)
            mat = np.where(petal_cela, CELA, mat)
            band = np.where(petal_blush | petal_cela, np.maximum(band, 2), band)

        mat = np.where(border, GOLD, mat)
        band = np.where(border, np.maximum(band, 2), band)

    return mat.astype(np.int16), band.astype(np.int16)


def _panel_basis(right_vec: np.ndarray, up_vec: np.ndarray) -> np.ndarray:
    """Orthonormal 3x3 basis `[x_right, y_up, z_normal]` for a draped silk apron panel."""
    ux = np.asarray(right_vec, float)
    nx = np.linalg.norm(ux)
    ux = ux / nx if nx > 1e-6 else np.array([1.0, 0.0, 0.0])
    uy = np.asarray(up_vec, float)
    uy = uy - np.dot(uy, ux) * ux
    ny = np.linalg.norm(uy)
    uy = uy / ny if ny > 1e-6 else np.array([0.0, 1.0, 0.0])
    uz = np.cross(ux, uy)
    nz = np.linalg.norm(uz)
    uz = uz / nz if nz > 1e-6 else np.array([0.0, 0.0, 1.0])
    return np.stack([ux, uy, uz], axis=1)


def _build_perlenbluete(m, hero_mod, ctx: dict) -> None:
    mats = ensure_ramps(hero_mod)
    SILK = mats["PEARL_SILK"]
    GOLD = mats["CHAMPAGNE_GOLD"]
    BLUSH = mats["BLUSH_LOTUS"]
    ICE = mats["ICE_BLOSSOM"]

    body_off = ctx["body_off"]
    leg_off = ctx["leg_off"]
    foot_poses = ctx["foot_poses"]
    arm_joints = ctx["arm_joints"]
    T, TR, tor = ctx["T"], ctx["TR"], ctx["tor"]
    breath, sway_x = ctx["breath"], ctx["sway_x"]
    w, mi, gk = ctx["w"], ctx["mi"], ctx["gk"]
    walking, running, sprint, pose = (
        ctx["walking"], ctx["running"], ctx["sprint"], ctx["pose"]
    )

    m.layer = "outfit"

    # ------------------------------------------------------------------ 1. Tailored Qipao Bodice, Collar & Placket
    m.off = body_off
    m.ell(T((0.0, 29.4 + breath * 0.05, 0.0)), (2.72, 3.15, 2.32), SILK, kind="qipao_waist", R=TR)
    m.ell(T((0.0, 33.8 + breath * 0.12, 0.0)), (3.38 + breath * 0.06, 3.40, 2.60 + breath * 0.05), SILK, kind="qipao_chest", R=TR)
    for sx in (-1, 1):
        m.ell(T((sx * 1.62, 33.78 + breath * 0.15, 2.08)), (1.72, 1.72, 1.58), SILK, R=TR)
        m.ell(T((sx * 2.35, 36.85 + breath * 0.12, 0.45)), (1.26, 1.88, 1.34), SILK, R=TR)
        m.ell(T((sx * 2.48, 36.80 + breath * 0.12, -0.58)), (1.26, 1.84, 1.30), SILK, R=TR)
    # High silk chest yoke & upper back yoke (seals open neckline cleanly into Mandarin stand collar)
    m.ell(T((0.0, 36.95 + breath * 0.10, 0.94)), (2.62, 2.10, 1.80), SILK, kind="qipao_yoke_f", R=TR)
    m.ell(T((0.0, 36.05, -0.94)), (3.20, 3.18, 1.86), SILK, kind="qipao_back_top", R=TR)

    # Mandarin Stand Collar (`Stehkragen`) + subtle flush golden clasp
    m.ell(T((0.0, 39.26, 0.30)), (1.52, 1.08, 1.52), SILK, kind="qipao_collar", R=TR)

    # Subtle flush Pankou frog-buttons along right side contour (`-x` = Ellie's right side, Photos 3 & 4)
    for bx, by, bz in (
        (-1.45, 37.15, 1.88),
        (-2.98, 33.00, 0.55),
        (-2.68, 29.60, 0.48),
    ):
        m.ell(T((bx, by + breath * 0.08, bz)), (0.36, 0.24, 0.32), GOLD, kind="emit", R=TR)

    # Soft flush 3D petal accents (kept within `< 0.6` depth of bodice so zero dark crease rings appear!)
    m.ell(T((1.35, 29.55 + breath * 0.06, 2.18)), (0.68, 0.62, 0.36), ICE, kind="emit", R=TR)

    # ------------------------------------------------------------------ 2. Short Silk Sleeves + Gold Cuffs (Bare Forearms!)
    for side, sh, elbow, _wrist, drawn in arm_joints:
        m.ell(sh, (1.62, 1.58, 1.58), SILK)
        if not drawn:
            continue
        sl_end = sh + (elbow - sh) * 0.45
        cuff_a = sh + (elbow - sh) * 0.41
        cuff_b = sh + (elbow - sh) * 0.47
        m.limb(sh, sl_end, 1.42, 1.22, SILK, kind="qipao_sleeve_l" if side == 1 else "qipao_sleeve_r", step=0.45)
        m.limb(cuff_a, cuff_b, 1.25, 1.24, GOLD, kind="emit", step=0.35)

    # ------------------------------------------------------------------ 3. Hip Sheath + Straight-Cut Split-Slit Silk Skirt
    waist_anchor = T((0.0, 28.6, 0.0))
    hip_anchor = np.array([sway_x * 0.45, 23.35, 0.04])
    mid_bridge = 0.5 * (waist_anchor + hip_anchor)
    m.ell(mid_bridge, (3.72, 2.65, 3.05), SILK, kind="qipao_hip")
    m.ell(hip_anchor, (4.06, 2.95, 3.30), SILK, kind="qipao_hip")
    # Flush rose-blush lotus accent on right-front hip (`z` flush with `hip_anchor` + `3.30`)
    m.ell((sway_x * 0.40 - 0.95, 25.45, 3.12), (0.76, 0.68, 0.38), BLUSH, kind="emit")

    if len(foot_poses) == 2:
        rel_off = leg_off - body_off
        hl = foot_poses[0][1] + rel_off
        kl = foot_poses[0][2] + rel_off
        hr = foot_poses[1][1] + rel_off
        kr = foot_poses[1][2] + rel_off

        hem_reach = 0.78
        pl = hl + (kl - hl) * hem_reach
        pr = hr + (kr - hr) * hem_reach

        dz_l, dz_r = kl[2] - hl[2], kr[2] - hr[2]
        dy_l, dy_r = hl[1] - kl[1], hr[1] - kr[1]
        seated = (dz_l > 5.2 and dz_r > 5.2 and dy_l < 7.5 and dy_r < 7.5)

        breeze = (0.28 * math.sin(2.0 * w - 0.5) if walking else 0.14 * math.sin(w - 0.4)) * (1.35 if running else 1.0)
        flare = float(pose.get("flare", 0.0)) if pose else 0.0

        # --- FRONT SILK APRON (`qipao_front`, straight horizontal hem via `_clip_qipao_panel`!)
        top_f_l = np.array([hl[0] * 0.94 + 0.75, hl[1] - 0.45, hl[2] + 1.98])
        top_f_r = np.array([hr[0] * 0.94 - 0.75, hr[1] - 0.45, hr[2] + 1.98])
        avg_z = 0.5 * (pl[2] + pr[2])
        if seated:
            # Smooth lap bridge sealing waist-to-lap crease completely in seated poses (Photo 2!)
            lap_mid = 0.5 * (hl + hr) + np.array([0.0, 2.15, 3.25])
            m.ell(lap_mid, (3.85, 2.35, 3.45), SILK, kind="qipao_hip")
            bot_f_l = np.array([pl[0] * 0.96 + 0.85, pl[1] + 1.75, pl[2] + 0.55])
            bot_f_r = np.array([pr[0] * 0.96 - 0.85, pr[1] + 1.75, pr[2] + 0.55])
        else:
            zf_l = max(pl[2], avg_z * 0.65) + 1.86 + 0.18 * breeze + 0.45 * flare
            zf_r = max(pr[2], avg_z * 0.65) + 1.86 - 0.18 * breeze + 0.45 * flare
            bot_f_l = np.array([pl[0] * 0.88 + 0.85, pl[1] + 0.20, zf_l])
            bot_f_r = np.array([pr[0] * 0.88 - 0.85, pr[1] + 0.20, zf_r])

        top_f_mid = 0.5 * (top_f_l + top_f_r)
        bot_f_mid = 0.5 * (bot_f_l + bot_f_r)
        # Shift center slightly so `qy = -0.66` clip lands right at `bot_f_mid` with a crisp horizontal hem!
        vec_f_up = top_f_mid - bot_f_mid
        len_f = max(float(np.linalg.norm(vec_f_up)), 4.0)
        ry_f = len_f / 1.56
        cen_f = bot_f_mid + (vec_f_up / len_f) * (0.66 * ry_f)
        rx_f = max(float(np.linalg.norm(bot_f_l - bot_f_r)) * 0.58, 4.15)
        Rf_pan = _panel_basis(bot_f_l - bot_f_r, vec_f_up)
        m.ell(cen_f, (rx_f, ry_f, 1.05), SILK, R=Rf_pan, kind="qipao_front", clip=_clip_qipao_panel)

        # --- BACK SILK APRON (`qipao_back`, straight horizontal hem via `_clip_qipao_panel`!)
        top_b_l = np.array([hl[0] * 0.94 + 0.75, hl[1] - 0.45, hl[2] - 2.05])
        top_b_r = np.array([hr[0] * 0.94 - 0.75, hr[1] - 0.45, hr[2] - 2.05])
        if seated:
            bot_b_l = np.array([hl[0] * 0.94 + 0.80, hl[1] - 5.2, hl[2] - 2.45])
            bot_b_r = np.array([hr[0] * 0.94 - 0.80, hr[1] - 5.2, hr[2] - 2.45])
        else:
            wind_z = (2.35 * gk + 0.65 * math.sin(2.0 * w - 0.9)) if sprint else ((0.85 if running else (0.35 if walking else 0.08)) + 0.22 * breeze + 0.95 * max(0.0, flare))
            wind_y = (1.45 * gk + 0.45 * math.sin(2.0 * w - 0.6)) if sprint else (0.35 * mi + 0.45 * max(0.0, flare))
            zb_l = min(pl[2], avg_z * 0.65) - 1.92 - wind_z
            zb_r = min(pr[2], avg_z * 0.65) - 1.92 - wind_z
            bot_b_l = np.array([pl[0] * 0.88 + 0.85, pl[1] + 0.20 + wind_y, zb_l])
            bot_b_r = np.array([pr[0] * 0.88 - 0.85, pr[1] + 0.20 + wind_y, zb_r])

        top_b_mid = 0.5 * (top_b_l + top_b_r)
        bot_b_mid = 0.5 * (bot_b_l + bot_b_r)
        vec_b_up = top_b_mid - bot_b_mid
        len_b = max(float(np.linalg.norm(vec_b_up)), 4.0)
        ry_b = len_b / 1.56
        cen_b = bot_b_mid + (vec_b_up / len_b) * (0.66 * ry_b)
        rx_b = max(float(np.linalg.norm(bot_b_l - bot_b_r)) * 0.58, 4.15)
        Rb_pan = _panel_basis(bot_b_l - bot_b_r, vec_b_up)
        m.ell(cen_b, (rx_b, ry_b, 1.05), SILK, R=Rb_pan, kind="qipao_back", clip=_clip_qipao_panel)

    # ------------------------------------------------------------------ 4. Pearl-Silk Ankle-Strap Slippers (Bare Calves!)
    m.off = leg_off
    for _side, _hip, _knee, ankle, heel, Rf, anim in foot_poses:
        if anim and Rf is not None:
            m.ell(heel + Rf @ np.array([0.0, 0.58, 2.22]), (1.30, 0.84, 2.22), SILK, R=Rf, kind="qipao_shoe")
            m.ell(heel + np.array([0.0, 0.08, 0.05]), (1.22, 0.78, 0.94), SILK)
            m.ell(heel + np.array([0.0, -0.32, -0.05]), (0.92, 0.44, 0.76), GOLD, kind="emit")
            m.ell(heel + Rf @ np.array([0.0, 2.18, 1.35]), (1.22, 0.26, 1.06), GOLD, kind="emit", R=Rf)
        else:
            m.ell(ankle + np.array([0.0, -1.55, 1.42]), (1.30, 0.84, 2.22), SILK, kind="qipao_shoe")
            m.ell(ankle + np.array([0.0, -2.08, -0.88]), (1.22, 0.78, 0.94), SILK)
            m.ell(ankle + np.array([0.0, -2.42, -0.92]), (0.92, 0.44, 0.76), GOLD, kind="emit")
            m.ell(ankle + np.array([0.0, 0.16, 0.52]), (1.22, 0.26, 1.06), GOLD, kind="emit")

    m.off = body_off


BUILDERS = {
    "perlenbluete": _build_perlenbluete,
}


def build_outfit(m, outfit_id: str, hero_mod, ctx: dict) -> None:
    fn = BUILDERS.get(outfit_id)
    if fn is None:
        raise ValueError(f"Unknown custom outfit_id: {outfit_id!r}")
    fn(m, hero_mod, ctx)


# ------------------------------------------------------------------ visual preview contact-sheet generator
def _write_png_array(path: Path, pixels: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    hh, ww, _ = pixels.shape
    raw = b"".join(b"\0" + pixels[y].tobytes() for y in range(hh))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", ww, hh, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def _dye_outfit_preview(arr: np.ndarray, tint_rgb: tuple[int, int, int]) -> np.ndarray:
    """Matches updated `cosmetic_dye(..., is_hair=false)` in `hit_flash.gdshader`."""
    out = arr.copy()
    rgb = out[..., :3].astype(np.float32) / 255.0
    a = out[..., 3] > 2
    lum = rgb[..., 0] * 0.30 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11
    keep = (lum < 0.055) | (rgb[..., 0] > rgb[..., 2] + 0.10) | (rgb[..., 1] > rgb[..., 0] + 0.12)
    mask = a & ~keep
    if not mask.any():
        return out
    t_col = np.array(tint_rgb, dtype=np.float32) / 255.0
    t = np.where(
        lum <= 0.50,
        np.clip((lum - 0.055) / 0.445, 0.0, 1.0) * 0.78,
        0.78 + np.clip((lum - 0.50) / 0.48, 0.0, 1.0) * 0.22,
    )[..., None]
    dark = t_col * 0.22
    hi_mix = (0.38 + 0.36 * np.clip((lum - 0.52) / 0.46, 0.0, 1.0))[..., None]
    light = t_col * (1.0 - hi_mix) + np.array([0.98, 0.96, 0.99], dtype=np.float32) * hi_mix
    dyed = np.clip((dark + (light - dark) * t) * 255.0, 0.0, 255.0).astype(np.uint8)
    out[mask, :3] = dyed[mask]
    return out


def _render_preview(out_dir: Path) -> None:
    import art_hero3d as hero
    import art_hero_sit as sit_mod
    import art_hero_swim as swim_mod
    import art_hero_standby as sb_mod

    ensure_ramps(hero)
    out_dir.mkdir(parents=True, exist_ok=True)
    bg = np.array([30, 24, 42, 255], dtype=np.uint8)
    bg_alt = np.array([38, 31, 52, 255], dtype=np.uint8)

    def compose(layers: dict, outfit_dye=None) -> np.ndarray:
        canvas = np.asarray(layers["body"], dtype=np.uint8).copy()
        hb = np.asarray(layers["hair_back"], dtype=np.uint8)
        of_arr = np.asarray(layers["outfit"], dtype=np.uint8)
        if outfit_dye is not None:
            of_arr = _dye_outfit_preview(of_arr, outfit_dye)
        hf = np.asarray(layers["hair_front"], dtype=np.uint8)
        hb_m = (hb[..., 3] > 2) & ((canvas[..., 3] < 3) | ((canvas[..., 3] < 80) & (canvas[..., :3].sum(-1) < 8)))
        canvas[hb_m] = hb[hb_m]
        of_m = of_arr[..., 3] > 2
        canvas[of_m] = of_arr[of_m]
        hf_m = hf[..., 3] > 2
        canvas[hf_m] = hf[hf_m]
        return canvas

    def upscale(img: np.ndarray, scale: int = 4) -> np.ndarray:
        return np.repeat(np.repeat(img, scale, axis=0), scale, axis=1)

    fw, fh = 48, 56
    hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, 51.0
    hairs = ("night_bun", "moon_knot", "blade_bob", "default")
    turnaround = np.zeros((len(hairs) * fh, 8 * fw, 4), dtype=np.uint8)
    for r_i, h_id in enumerate(hairs):
        for s in range(8):
            yaw = math.pi / 2 - s * math.pi / 4
            model = hero.build(0.0, "idle", False, None, outfit_id="perlenbluete", hair_id=h_id)
            layers = hero.render_layers(model.transform(yaw, model.bob), shadow=True)
            comp = compose(layers)
            cell = (bg if (r_i + s) % 2 == 0 else bg_alt)[None, None, :].repeat(fh, 0).repeat(fw, 1)
            a = comp[..., 3:4].astype(np.float32) / 255.0
            rgb = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
            turnaround[r_i * fh:(r_i + 1) * fh, s * fw:(s + 1) * fw] = np.concatenate(
                [rgb, np.full((fh, fw, 1), 255, dtype=np.uint8)], axis=-1
            )
    _write_png_array(out_dir / "perlenbluete_turnaround_4x.png", upscale(turnaround, 4))

    dyes = [
        (0xA8, 0x4C, 0x78),  # Dornenrosé
        (0x4A, 0x3B, 0x8C),  # Nachtseide
        (0x38, 0x94, 0x9C),  # Prismentief
        (0x34, 0x2C, 0x44),  # Schattengarn
    ]
    motion = np.zeros((3 * fh, 8 * fw, 4), dtype=np.uint8)
    row0 = []
    for ph in range(6):
        sec = 0 if ph < 3 else 1
        yaw = math.pi / 2 - sec * math.pi / 4
        m0 = hero.build(ph / 6.0, "walk", False, None, outfit_id="perlenbluete", hair_id="night_bun")
        row0.append(compose(hero.render_layers(m0.transform(yaw, m0.bob), shadow=True)))
    for ph, sec in ((0.15, 1), (0.65, 3)):
        yaw = math.pi / 2 - sec * math.pi / 4
        m0 = hero.build(ph, "walk", True, None, outfit_id="perlenbluete", hair_id="storm_tail")
        row0.append(compose(hero.render_layers(m0.transform(yaw, m0.bob), shadow=True)))

    row1 = []
    for ph in range(6):
        sec = 4 if ph < 3 else 5
        yaw = math.pi / 2 - sec * math.pi / 4
        m1 = hero.build(ph / 6.0, "run", False, None, outfit_id="perlenbluete", hair_id="moon_knot")
        row1.append(compose(hero.render_layers(m1.transform(yaw, m1.bob), shadow=True)))
    for k_idx, sec in ((2, 1), (3, 3)):
        yaw = math.pi / 2 - sec * math.pi / 4
        m1 = hero.build(0.0, "attack", False, hero.ATTACK_POSES[0][k_idx], outfit_id="perlenbluete", hair_id="blade_bob")
        row1.append(compose(hero.render_layers(m1.transform(yaw, m1.bob), shadow=True)))

    row2 = []
    for sec in (1, 2, 3, 6):
        yaw = math.pi / 2 - sec * math.pi / 4
        m2 = hero.build(0.08, "walk", False, None, outfit_id="perlenbluete", hair_id="dusk_braids")
        row2.append(compose(hero.render_layers(m2.transform(yaw, m2.bob), shadow=True)))
    for sec, d_rgb in zip((2, 1, 3, 2), dyes):
        yaw = math.pi / 2 - sec * math.pi / 4
        m2 = hero.build(0.0, "idle", False, None, outfit_id="perlenbluete", hair_id="night_bun")
        row2.append(compose(hero.render_layers(m2.transform(yaw, m2.bob), shadow=True), outfit_dye=d_rgb))

    for r_i, r_cells in enumerate((row0, row1, row2)):
        for c_i, comp in enumerate(r_cells):
            cell = (bg if (r_i + c_i) % 2 == 0 else bg_alt)[None, None, :].repeat(fh, 0).repeat(fw, 1)
            a = comp[..., 3:4].astype(np.float32) / 255.0
            rgb = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
            motion[r_i * fh:(r_i + 1) * fh, c_i * fw:(c_i + 1) * fw] = np.concatenate(
                [rgb, np.full((fh, fw, 1), 255, dtype=np.uint8)], axis=-1
            )
    _write_png_array(out_dir / "perlenbluete_motion_dyes_4x.png", upscale(motion, 4))

    cw, ch = 72, 76
    sit_poses = sit_mod.poses()
    poses_img = np.zeros((ch, 6 * cw, 4), dtype=np.uint8)
    p_cells = []
    for sec_s, h_s in ((2, "night_bun"), (1, "moon_knot"), (3, "blade_bob"), (5, "dusk_braids")):
        hero.FW, hero.FH, hero.GROUND_ROW = 72, 76, 51.0
        yaw = math.pi / 2 - sec_s * math.pi / 4
        ms = hero.build(0.0, "attack", False, sit_poses[sit_mod.DOWN], outfit_id="perlenbluete", hair_id=h_s)
        p_cells.append(compose(hero.render_layers(ms.transform(yaw, 0.0), shadow=True)))

    hero.FW, hero.FH, hero.GROUND_ROW = 64, 72, float(swim_mod.WATER_ROW)
    yaw = math.pi / 2 - 4 * math.pi / 4
    msw = hero.build(0.0, "attack", False, swim_mod.FUNCS["breast"](2), outfit_id="perlenbluete", hair_id="night_bun")
    prims_sw = msw.transform(yaw, 0.0)
    swim_mod._cut(prims_sw, True)
    pad_sw = np.zeros((ch, cw, 4), dtype=np.uint8)
    pad_sw[2:74, 4:68] = compose(hero.render_layers(prims_sw, shadow=False))
    p_cells.append(pad_sw)

    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    yaw = math.pi / 2 - 2 * math.pi / 4
    p_sb = dict(hero.timeline_pose(sb_mod.KEYS[1], 0.45), standby=True)
    msb = hero.build(0.0, "idle", False, p_sb, outfit_id="perlenbluete", hair_id="night_bun")
    pad_sb = np.zeros((ch, cw, 4), dtype=np.uint8)
    pad_sb[10:66, 12:60] = compose(hero.render_layers(msb.transform(yaw, msb.bob), shadow=True))
    p_cells.append(pad_sb)

    for c_i, comp in enumerate(p_cells):
        cell = (bg if c_i % 2 == 0 else bg_alt)[None, None, :].repeat(ch, 0).repeat(cw, 1)
        a = comp[..., 3:4].astype(np.float32) / 255.0
        rgb = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
        poses_img[:, c_i * cw:(c_i + 1) * cw] = np.concatenate(
            [rgb, np.full((ch, cw, 1), 255, dtype=np.uint8)], axis=-1
        )
    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    _write_png_array(out_dir / "perlenbluete_poses_4x.png", upscale(poses_img, 4))
    print(f"Wrote Perlenbluete previews to {out_dir}")


if __name__ == "__main__":
    TOOLS_DIR = Path(__file__).resolve().parent
    sys.path.insert(0, str(TOOLS_DIR))
    if len(sys.argv) >= 3 and sys.argv[1] == "preview":
        _render_preview(Path(sys.argv[2]))
    else:
        print("Usage: py -3 tools/art_hero_outfit.py preview <out_dir>")
