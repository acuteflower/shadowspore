#!/usr/bin/env python3
"""Procedural 3D-ellipsoid pixel-art generator for the Goddess of the Star Hall.

Follows `tools/art_hero3d.py`, `tools/art_hero_outfit.py`, `tools/art_hero_hair.py`,
and `tools/hero_face.py` down to the exact subpixel shading & silhouette rules:
  - 4x4 orthographic local-space ellipsoid supersampling (`SS = 4`).
  - Outer 1px dark-violet silhouette outline ONLY against open air (`~all_solid`),
    NEVER cutting black lines across her cheeks, collarbones, bustier, or legs!
  - Material-tinted Band-0 soft internal depth creases (`art_hero3d._rows_from_best`).
  - Structured, noise-free pixel-art drapery & strand shading (4-tone silver-gold
    wavy hair & temple braids, golden starlight diadem, sweetheart pearl-silk bustier,
    gold-laced midnight-indigo corset, astrolabe-trimmed pearl stole, pleated royal
    night-blue split overskirt, gossamer starry shoulder veil, and delicate golden
    halo arc with 7 faceted crystal rays).

Outputs:
  - assets/characters/goddess.png       (26 cols x 3 rows, 96x112 frames, anchor (48, 94))
  - assets/characters/goddess_glow.png  (matching emissive-only sheet for Unlit overlay)
  - data/goddess_rig.json               (clip definitions, anchor, facings)
"""
from __future__ import annotations

import json
import math
import multiprocessing as mp
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_art import ROOT, write_png  # noqa: E402

# ---------------------------------------------------------------------------
# Frame & Camera Geometry (exact `art_hero3d.py` 26° 3/4 pitch + 4x SS)
# ---------------------------------------------------------------------------
FW, FH = 96, 112
SS = 4
PITCH = math.radians(26.0)
COSP, SINP = math.cos(PITCH), math.sin(PITCH)
SCALE = 1.38
GROUND_ROW = 94.0

XHAT = np.array([1.0, 0.0, 0.0], dtype=np.float64)
UHAT = np.array([0.0, COSP, -SINP], dtype=np.float64)
WHAT = np.array([0.0, SINP, COSP], dtype=np.float64)
LIGHT = np.array([-0.48, 0.72, 0.50], dtype=np.float64)
LIGHT /= np.linalg.norm(LIGHT)


def hexc(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


# ---------------------------------------------------------------------------
# Material Ramps (4 flat tones each, cool-violet shadows, zero pure black)
# Emissive ramps (8..10) have unique RGBs so `goddess_glow.png` is 100% pure.
# ---------------------------------------------------------------------------
SKIN = 0         # Ellie's exact luminous porcelain-rose skin ramp
HAIR_SILV = 1    # Rich 4-tone lavender-shadow to moon-silver hair
HAIR_GOLD = 2    # Warm champagne-starlight hair strands & temple braids
PEARL_SILK = 3   # Luminous moon-ivory jacquard silk (bustier & stole)
NIGHT_SILK = 4   # Deep cosmos midnight-indigo velvet-silk (corset & overskirt)
NIGHT_PLEAT = 5  # Rich royal-amethyst satin pleat highlights
ASTRAL_VEIL = 6  # Gossamer starry sapphire-violet shoulder veil
GOLD = 7         # Antique-to-champagne gold filigree, clasps & sandals
TEAL_EMIT = 8    # Emissive turquoise-starlight gems, veins & iris
HALO_EMIT = 9    # Emissive radiant star-gold halo & blessing core
STAR_EMIT = 10   # Emissive diamond-white / ice-cyan crystal facets

RAMPS: list[list[tuple[int, int, int]]] = [
    [hexc("dc9496"), hexc("f2b8b2"), hexc("fde0d2"), hexc("fff3e8")],  # 0 SKIN
    [hexc("5e5294"), hexc("9286ca"), hexc("d2cae8"), hexc("f8f2ec")],  # 1 HAIR_SILV (richer midtone depth against bright hall ambient!)
    [hexc("8c7250"), hexc("bfa476"), hexc("e6d4ae"), hexc("fbf4de")],  # 2 HAIR_GOLD
    [hexc("7c729e"), hexc("aea4d0"), hexc("dcd6ee"), hexc("f7f3ee")],  # 3 PEARL_SILK (sculpted silver-ivory folds!)
    [hexc("120d28"), hexc("221c4a"), hexc("3e347a"), hexc("685cae")],  # 4 NIGHT_SILK
    [hexc("281a4a"), hexc("48307c"), hexc("7252b4"), hexc("a488e2")],  # 5 NIGHT_PLEAT
    [hexc("1b244e"), hexc("2f447c"), hexc("547cb8"), hexc("96cef2")],  # 6 ASTRAL_VEIL
    [hexc("6f5020"), hexc("b48a38"), hexc("e6c468"), hexc("fff0b0")],  # 7 GOLD
    [hexc("268890"), hexc("3cc0c6"), hexc("78f4e6"), hexc("d0fff8")],  # 8 TEAL_EMIT
    [hexc("9c7226"), hexc("dca842"), hexc("f8d876"), hexc("fff6c4")],  # 9 HALO_EMIT
    [hexc("4aa4bc"), hexc("7ad6ec"), hexc("b8f4ff"), hexc("f4ffff")],  # 10 STAR_EMIT
]
EMIT_MATS = {TEAL_EMIT, HALO_EMIT, STAR_EMIT}

DECAL_WEIGHT: dict[int, float] = {
    GOLD: 1.36,
    TEAL_EMIT: 1.58,
    HALO_EMIT: 1.50,
    STAR_EMIT: 1.58,
}

SIL_INK = (18, 9, 28, 255)       # Crisp dark obsidian-violet outer silhouette (#12091c)
HALO_INK = (44, 30, 46, 255)     # Tinted warm plum-bronze outline for floating halo
EYE_LASH = (32, 18, 54, 255)     # Crisp dark-violet upper eyelash (#201236)


def mat_ink(mat: int) -> tuple[int, int, int, int]:
    """Soft material-tinted outer outline (`art_hero3d.ink_color`), keeping hair & halo airy while body stays crisp."""
    if mat in (HALO_EMIT, STAR_EMIT, TEAL_EMIT):
        return HALO_INK
    if mat in (HAIR_SILV, HAIR_GOLD):
        return (36, 26, 58, 255)
    return SIL_INK


# ---------------------------------------------------------------------------
# 3D Math & Primitives
# ---------------------------------------------------------------------------
def rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]], dtype=np.float64)


def rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]], dtype=np.float64)


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]], dtype=np.float64)


def frame_from(axis_y: np.ndarray | tuple[float, float, float], hint: np.ndarray | tuple[float, float, float] = (0.0, 0.0, 1.0)) -> np.ndarray:
    ty = np.asarray(axis_y, dtype=np.float64)
    ny = float(np.linalg.norm(ty))
    ty = ty / ny if ny > 1e-6 else np.array([0.0, 1.0, 0.0])
    tx = np.cross(ty, np.asarray(hint, dtype=np.float64))
    if float(np.linalg.norm(tx)) < 1e-6:
        tx = np.cross(ty, [1.0, 0.0, 0.0])
    tx /= float(np.linalg.norm(tx))
    tz = np.cross(tx, ty)
    return np.stack([tx, ty, tz], axis=1)


def panel_basis(right_vec: np.ndarray, up_vec: np.ndarray) -> np.ndarray:
    ux = np.asarray(right_vec, dtype=np.float64)
    nx = float(np.linalg.norm(ux))
    ux = ux / nx if nx > 1e-6 else np.array([1.0, 0.0, 0.0])
    uy = np.asarray(up_vec, dtype=np.float64)
    uy = uy - np.dot(uy, ux) * ux
    ny = float(np.linalg.norm(uy))
    uy = uy / ny if ny > 1e-6 else np.array([0.0, 1.0, 0.0])
    uz = np.cross(ux, uy)
    nz = float(np.linalg.norm(uz))
    uz = uz / nz if nz > 1e-6 else np.array([0.0, 0.0, 1.0])
    return np.stack([ux, uy, uz], axis=1)


def ik2(
    root: np.ndarray,
    target: np.ndarray,
    l1: float,
    l2: float,
    pole: tuple[float, float, float] | np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    root_a = np.asarray(root, dtype=np.float64)
    targ_a = np.asarray(target, dtype=np.float64)
    d = targ_a - root_a
    dist = float(np.linalg.norm(d))
    reach = l1 + l2 - 0.04
    if dist > reach:
        d = d * (reach / max(dist, 1e-6))
        dist = reach
    if dist < abs(l1 - l2) + 0.04:
        dist = abs(l1 - l2) + 0.04
    u = d / max(float(np.linalg.norm(d)), 1e-6)
    p = np.asarray(pole, dtype=np.float64)
    p = p - np.dot(p, u) * u
    np_len = float(np.linalg.norm(p))
    p = p / np_len if np_len > 1e-6 else np.array([0.0, 0.0, 1.0])
    cos_a = max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    mid = root_a + l1 * (cos_a * u + sin_a * p)
    return mid, root_a + d


class Prim:
    __slots__ = ("c", "r", "R", "mat", "kind", "tag", "clip", "layer")

    def __init__(
        self,
        c: np.ndarray,
        r: np.ndarray,
        R: np.ndarray,
        mat: int,
        kind: str = "",
        tag: float = 0.0,
        clip=None,
        layer: str = "body",
    ) -> None:
        self.c = c
        self.r = r
        self.R = R
        self.mat = mat
        self.kind = kind
        self.tag = tag
        self.clip = clip
        self.layer = layer


class Model:
    def __init__(self) -> None:
        self.prims: list[Prim] = []
        self.layer: str = "body"
        self.eyes: list[tuple[np.ndarray, np.ndarray, bool]] = []

    def ell(
        self,
        c,
        r,
        mat: int,
        R: np.ndarray | None = None,
        kind: str = "",
        tag: float = 0.0,
        clip=None,
        layer: str | None = None,
    ) -> None:
        ca = np.asarray(c, dtype=np.float64)
        ra = np.asarray(r, dtype=np.float64)
        if ra.ndim == 0:
            ra = np.array([float(ra)] * 3, dtype=np.float64)
        rot_m = np.eye(3, dtype=np.float64) if R is None else R
        self.prims.append(Prim(ca, ra, rot_m, mat, kind, tag, clip, self.layer if layer is None else layer))

    def limb(
        self,
        p0,
        p1,
        r0: float,
        r1: float,
        mat: int,
        kind: str = "",
        step: float = 0.45,
        layer: str | None = None,
    ) -> None:
        a = np.asarray(p0, dtype=np.float64)
        b = np.asarray(p1, dtype=np.float64)
        n = max(2, int(float(np.linalg.norm(b - a)) / step))
        for i in range(n + 1):
            t = i / n
            r = r0 + (r1 - r0) * t
            self.ell(a + (b - a) * t, (r, r, r), mat, kind=kind, layer=layer)

    def ribbon(
        self,
        pts: list,
        widths: list[float],
        thick: float,
        mat: int,
        hint: tuple[float, float, float] = (0.0, 0.0, -1.0),
        tag: float = 0.0,
        kind: str = "hair",
        layer: str | None = None,
    ) -> None:
        arr = [np.asarray(p, dtype=np.float64) for p in pts]
        for i in range(len(arr) - 1):
            seg = arr[i + 1] - arr[i]
            ln = float(np.linalg.norm(seg))
            if ln < 1e-5:
                continue
            R = frame_from(seg, hint)
            n = max(2, int(ln / 0.50))
            for k in range(n + 1):
                t = k / n
                u = (i + t) / (len(arr) - 1)
                wi = u * (len(widths) - 1)
                w0 = int(wi)
                w1 = min(len(widths) - 1, w0 + 1)
                w = widths[w0] * (1.0 - (wi - w0)) + widths[w1] * (wi - w0)
                self.ell(arr[i] + seg * t, (w, max(0.55, ln / n * 1.18), thick), mat, R=R, kind=kind, tag=tag, layer=layer)

    def transform(self, yaw: float) -> list[Prim]:
        Ry = rot_y(yaw)
        return [
            Prim((Ry @ p.c) * SCALE, p.r * SCALE, Ry @ p.R, p.mat, p.kind, p.tag, p.clip, p.layer)
            for p in self.prims
        ]


# ---------------------------------------------------------------------------
# Clip Masks & Structured Pixel-Art Surface Shading
# ---------------------------------------------------------------------------
def clip_hair_cap(q: np.ndarray) -> np.ndarray:
    return ~((q[..., 2] > 0.24) & (q[..., 1] < 0.24) & (np.abs(q[..., 0]) < 0.78))


def clip_stole_panel(q: np.ndarray) -> np.ndarray:
    return (q[..., 1] >= -0.68) & (np.abs(q[..., 0]) <= 0.85)


def shade_surface(
    p: Prim,
    q: np.ndarray,
    lam: np.ndarray,
    bless_k: float,
) -> tuple[np.ndarray, np.ndarray]:
    qx, qy, qz = q[..., 0], q[..., 1], q[..., 2]
    mat = np.full(qx.shape, p.mat, dtype=np.int16)
    kind = p.kind

    if kind == "head":
        band = np.digitize(lam + 0.10, (-0.16, 0.10, 0.46)).astype(np.int16)
        return mat, band

    if kind == "hair":
        # Rich, sculpted longitudinal strand shading: deep lavender valleys, silver silk body, warm gold-kissed crests!
        wave = 0.14 * np.sin(qx * 3.6 + p.tag * 1.1)
        band = np.digitize(lam + wave, (-0.12, 0.16, 0.48)).astype(np.int16)
        groove = ((qx * 1.75 + p.tag * 0.61) % 1.0) < 0.25
        band = np.where(groove, np.maximum(band - 1, 0), band)
        gold_crest = (((qx * 1.25 + p.tag * 0.41) % 1.0) > 0.66) & (band >= 2)
        mat = np.where(gold_crest, HAIR_GOLD, mat)
        return mat, band

    if kind == "braid":
        # Alternating woven braid plait shading (`HAIR_GOLD` + `HAIR_SILV`)
        weave = 0.22 * np.sin(qy * 5.6 + qx * 2.8 + p.tag)
        band = np.digitize(lam + weave + 0.06, (-0.14, 0.14, 0.46)).astype(np.int16)
        mat = np.where(weave > 0.02, HAIR_GOLD, HAIR_SILV).astype(np.int16)
        return mat, band

    if kind == "emit":
        band = np.digitize(lam + 0.28 + 0.20 * bless_k, (-0.04, 0.28, 0.60)).astype(np.int16)
        band = np.maximum(band, 1)
        return mat, band

    if kind == "crystal_ray":
        ridge = 1.0 - np.minimum(1.0, np.abs(qx) * 1.15)
        tip_boost = np.clip((qy + 0.5) * 0.65, 0.0, 0.75)
        val = ridge * 0.55 + tip_boost + 0.20 * bless_k
        band = np.digitize(val, (0.38, 0.62, 0.88)).astype(np.int16)
        mat = np.where(qy > 0.18, STAR_EMIT, TEAL_EMIT).astype(np.int16)
        if int(round(p.tag)) % 2 == 0:
            mat = np.where(qy <= -0.18, HALO_EMIT, mat)
        return mat, band

    if kind == "bustier":
        # Rich royal night-blue outer bodice framing a central pearl-ivory cameo panel & golden sweetheart rim,
        # giving crisp dark-vs-porcelain contrast at her bare collarbones (matching Ellie's dark bodice contrast!)
        sheen = 0.09 * np.sin(qx * 3.4 + qy * 2.4)
        band = np.digitize(lam + sheen + 0.04, (-0.18, 0.10, 0.46)).astype(np.int16)
        outer_night = (np.abs(qx) > 0.46) | (qz <= 0.15)
        gold_rim = (qz > 0.22) & ((qy > 0.54) | (np.abs(np.abs(qx) - 0.46) < 0.10))
        mat = np.where(outer_night, NIGHT_SILK, PEARL_SILK).astype(np.int16)
        mat = np.where( outer_night & (band >= 2), NIGHT_PLEAT, mat)
        mat = np.where(gold_rim, GOLD, mat)
        band = np.where(gold_rim, np.maximum(band, 2), band)
        return mat, band

    if kind == "corset":
        fold = 0.10 * np.sin(qx * 4.8)
        band = np.digitize(lam + fold, (-0.14, 0.14, 0.48)).astype(np.int16)
        front = qz > 0.32
        lace = front & (np.abs(qx) < 0.11) & ((np.floor((qy + 1.0) * 3.8) % 2) == 0)
        boning = front & (np.abs(np.abs(qx) - 0.50) < 0.08)
        trim = lace | boning
        mat = np.where(trim, GOLD, mat)
        band = np.where(trim, np.maximum(band, 2), band)
        return mat, band

    if kind == "stole_front":
        # Structured pearl-ivory jacquard stole: lavender-silk shadow folds, gold slit piping,
        # central golden astrolabe diamond, and clean turquoise starlight leyline!
        drape = 0.11 * np.cos(qx * 3.8)
        band = np.digitize(lam + drape + 0.02, (-0.18, 0.10, 0.46)).astype(np.int16)
        border_gold = (qy <= -0.55) | (np.abs(qx) >= 0.69)
        astro_d = np.abs(qx) * 1.35 + np.abs(qy + 0.02) * 1.9
        astro_gold = (astro_d > 0.24) & (astro_d < 0.44)
        vein_teal = ((np.abs(qx) < 0.12) & (qy > -0.44) & (qy < 0.52) & (~astro_gold)) | (astro_d <= 0.22)

        mat = np.where(border_gold | astro_gold, GOLD, mat)
        band = np.where(border_gold | astro_gold, np.maximum(band, 2), band)
        mat = np.where(vein_teal, TEAL_EMIT, mat)
        band = np.where(vein_teal, 2 if bless_k < 0.35 else 3, band)
        return mat, band

    if kind == "overskirt":
        # Structured cathedral pleats (deep indigo valleys, royal-violet flutes, crisp gold hem & slit trim,
        # and clean symmetrical turquoise leyline diamond near the lower hem — zero random pixel noise!)
        pleat_wave = np.sin(qx * 5.8 + p.tag * 1.2)
        band = np.digitize(lam + 0.16 * pleat_wave, (-0.14, 0.12, 0.46)).astype(np.int16)
        flute_hi = (pleat_wave > 0.36) & (band >= 2)
        mat = np.where(flute_hi, NIGHT_PLEAT, mat)

        hem_gold = qy <= -0.60
        slit_gold = (qx * p.tag < -0.58) & (qy < 0.62)
        # Clean diamond star-rune above the hem + subtle upper star pip
        rune_d = np.abs(qx) * 1.5 + np.abs(qy + 0.34) * 2.2
        rune_teal = (rune_d < 0.32) | ((np.abs(qx) < 0.12) & (np.abs(qy - 0.12) < 0.10))

        mat = np.where(hem_gold | slit_gold, GOLD, mat)
        band = np.where(hem_gold | slit_gold, np.maximum(band, 2), band)
        mat = np.where(rune_teal, TEAL_EMIT, mat)
        band = np.where(rune_teal, 2 if bless_k < 0.35 else 3, band)
        return mat, band

    if kind == "veil":
        ripple = 0.14 * np.sin(qx * 4.6 + qy * 3.2 + p.tag)
        band = np.digitize(lam + ripple + 0.06, (-0.18, 0.10, 0.46)).astype(np.int16)
        vein_edge = (np.abs(qx) > 0.56) & (qy < 0.25)
        tip_glow = qy < -0.36
        mat = np.where(vein_edge | tip_glow, TEAL_EMIT, mat)
        band = np.where(vein_edge | tip_glow, 2 if bless_k < 0.35 else 3, band)
        return mat, band

    band = np.digitize(lam, (-0.16, 0.14, 0.50)).astype(np.int16)
    return mat, band


# ---------------------------------------------------------------------------
# Subpixel Rasterizer & `art_hero3d.render_layers`-Style Clean Compositor
# ---------------------------------------------------------------------------
def raster_subset(
    prims: list[Prim],
    bless_k: float,
    init_depth: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    hs, ws = FH * SS, FW * SS
    depth = np.full((hs, ws), -1e9, dtype=np.float64) if init_depth is None else init_depth.copy()
    code = np.full((hs, ws), -1, dtype=np.int16)
    only_depth = np.full((hs, ws), -1e9, dtype=np.float64)

    for p in prims:
        cx = FW * 0.5 + p.c[0]
        cy = GROUND_ROW - (p.c[1] * COSP - p.c[2] * SINP)
        rr = float(p.r.max()) + 0.5
        x0 = max(0, int((cx - rr) * SS))
        x1 = min(ws, int((cx + rr) * SS) + 1)
        y0 = max(0, int((cy - rr) * SS))
        y1 = min(hs, int((cy + rr) * SS) + 1)
        if x1 <= x0 or y1 <= y0:
            continue

        a = (np.arange(x0, x1, dtype=np.float64) + 0.5) / SS - FW * 0.5
        b = GROUND_ROW - (np.arange(y0, y1, dtype=np.float64) + 0.5) / SS
        A, B = np.meshgrid(a, b)
        o = A[..., None] * XHAT + B[..., None] * UHAT

        M = np.diag(1.0 / p.r) @ p.R.T
        q0 = (o - p.c) @ M.T
        qd = M @ WHAT
        aa = float(qd @ qd)
        if aa <= 1e-12:
            continue
        bb = q0 @ qd
        cc = (q0 * q0).sum(-1) - 1.0
        disc = bb * bb - aa * cc
        ok = disc >= 0.0
        if not ok.any():
            continue

        t = (-bb + np.sqrt(np.where(ok, disc, 0.0))) / aa
        q = q0 + t[..., None] * qd
        if p.clip is not None:
            ok &= p.clip(q)
        sub = depth[y0:y1, x0:x1]
        ok &= t > sub
        if not ok.any():
            continue

        n = (q / p.r) @ p.R.T
        n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        lam = 0.78 * (n @ LIGHT) + 0.22 * (0.5 + 0.5 * n[..., 1]) - 0.06

        mat_arr, band_arr = shade_surface(p, q, lam, bless_k)
        codes = (mat_arr * 4 + np.clip(band_arr, 0, 3)).astype(np.int16)

        sub[ok] = t[ok]
        code[y0:y1, x0:x1][ok] = codes[ok]
        only_depth[y0:y1, x0:x1][ok] = t[ok]

    return depth, code, only_depth


def best_codes(csub: np.ndarray, k: int) -> tuple[np.ndarray, np.ndarray]:
    best = np.full((FH, FW), -1, dtype=np.int16)
    best_w = np.zeros((FH, FW), dtype=np.float64)
    for v in range(k):
        w = (csub == v).sum(-1) * DECAL_WEIGHT.get(v // 4, 1.0)
        better = w > best_w
        best = np.where(better, v, best)
        best_w = np.where(better, w, best_w)
    return best, best_w


def resolve_layer_raw(
    depth: np.ndarray,
    code: np.ndarray,
    min_cov: int = 6,
    crease_thresh: float = 2.6,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Returns `(best_code, solid_mask, band0_crease_mask)` WITHOUT painting premature interior black outlines!"""
    k = len(RAMPS) * 4
    csub = code.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    dsub = depth.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)

    cnt = (csub >= 0).sum(-1)
    solid = cnt >= min_cov
    dmean = np.where(csub >= 0, dsub, 0.0).sum(-1) / np.maximum(cnt, 1)

    best, _ = best_codes(csub, k)
    best = np.where(solid, best, -1)

    crease = np.zeros((FH, FW), dtype=bool)
    if crease_thresh > 0.0:
        for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            nb = np.roll(np.roll(dmean, dy, 0), dx, 1)
            nbs = np.roll(np.roll(solid, dy, 0), dx, 1)
            crease |= solid & nbs & (nb > dmean + crease_thresh)
        crease[0, :] = crease[-1, :] = crease[:, 0] = crease[:, -1] = False

    return best, solid, crease


def stamp_goddess_eyes(
    color: np.ndarray,
    emit: np.ndarray,
    eye_pts_2d: list[tuple[float, float, float, bool]],
    pulse: float,
) -> None:
    """Ellie-cohesive (`hero_face.py`) precision face stamp: smooth luminous porcelain cheeks/chin
    (zero noisy mouth/nose dots!) + expressive 2x2 glowing turquoise-starlight anime eyes under dark-violet lashes."""
    vis = [e for e in eye_pts_2d if e[2] > 0.15]
    if not vis:
        return

    h, w, _ = color.shape
    vis.sort(key=lambda item: item[0])
    ey = int(round(sum(item[1] for item in vis) / len(vis)))
    closed = any(item[3] for item in vis)

    if len(vis) == 2:
        cx_mid = 0.5 * (vis[0][0] + vis[1][0])
        sep = vis[1][0] - vis[0][0]
        if sep >= 2.6:
            # 2px left eye + 2px porcelain nose-bridge + 2px right eye = 6px across a 9px porcelain face!
            c_int = int(round(cx_mid))
            xs = [c_int - 3, c_int + 1]
            eye_w = 2
        else:
            xs = [int(round(vis[0][0])), int(round(vis[1][0]))]
            eye_w = 1
    else:
        xs = [int(round(vis[0][0]))]
        eye_w = 2

    iris_spark = RAMPS[TEAL_EMIT][3] if pulse > 0.45 else RAMPS[TEAL_EMIT][2]
    iris_deep = RAMPS[TEAL_EMIT][1]

    for idx_e, ex in enumerate(xs):
        if ey < 2 or ey + 2 >= h or ex < 2 or ex + eye_w >= w:
            continue
        if closed:
            for dx in range(eye_w):
                px = ex + dx
                color[ey + 1, px] = EYE_LASH
                emit[ey + 1, px] = False
            continue

        for dx in range(eye_w):
            px = ex + dx
            color[ey, px] = EYE_LASH
            emit[ey, px] = False
            is_hi = (dx == 0) if idx_e == 0 else (dx == eye_w - 1)
            col_i = iris_spark if (is_hi or eye_w == 1) else iris_deep
            color[ey + 1, px] = (*col_i, 255)
            emit[ey + 1, px] = True


# ---------------------------------------------------------------------------
# Rig & Pose Builder (Graceful, Relaxed Arms + Voluminous Hair + Detailed Gown)
# ---------------------------------------------------------------------------
def build_goddess(clip: str, frame_idx: int, n_frames: int) -> tuple[Model, float, float]:
    m = Model()
    phase = 2.0 * math.pi * (frame_idx / n_frames)
    breath = math.sin(phase)
    bless_k = 0.0
    eye_pulse = 0.5 + 0.5 * math.sin(phase)
    eyes_closed = False

    seated = clip.startswith("sit_")
    lean = 0.0
    twist = 0.0
    head_yaw = 0.0
    head_tilt = 0.0
    head_nod = 0.0
    wind_lift = 0.0
    u = frame_idx / max(1, n_frames - 1)

    if clip == "sit_idle":
        # Natural, feminine relaxed elbows (elbows drop softly down & back, NEVER chicken-wing akimbo!)
        seat_dy = -9.6
        lean = 0.04 + 0.015 * breath
        head_tilt = 0.025 * math.sin(phase - 0.6)
        hand_l = np.array([4.35, 19.6 + 0.16 * breath, 5.8])
        hand_r = np.array([-3.55, 23.6 + 0.35 * breath, 7.2])
        pole_l = (1.3, -3.2, -2.2)
        pole_r = (-1.4, -3.0, -2.2)
        spark_pos = hand_r + np.array([-0.15, 2.35 + 0.42 * math.sin(phase + 0.8), 0.9])
        spark_r = 0.66 + 0.12 * math.sin(phase)
    elif clip == "sit_talk":
        seat_dy = -9.6
        lean = 0.075 + 0.025 * math.sin(phase)
        twist = 0.04 * math.sin(phase)
        head_tilt = 0.05 * math.sin(phase + 0.4)
        head_yaw = 0.05 * math.sin(phase - 0.3)
        eye_pulse = 0.65 + 0.35 * math.sin(phase)
        open_k = 0.5 + 0.5 * math.sin(phase - 0.3)
        hand_l = np.array([4.35 + 0.45 * open_k, 20.2 + 0.6 * open_k, 6.0 + 0.4 * open_k])
        hand_r = np.array([-3.95 - 1.35 * open_k, 24.4 + 1.4 * open_k, 7.5 + 0.7 * open_k])
        pole_l = (1.4, -3.0, -2.0)
        pole_r = (-1.6, -2.8, -2.0)
        spark_pos = hand_r + np.array([0.1, 2.25 + 0.32 * open_k, 0.85])
        spark_r = 0.70 + 0.15 * open_k
    elif clip == "sit_bless":
        seat_dy = -9.6
        bless_k = math.sin(math.pi * u) ** 1.15
        eyes_closed = 2 <= frame_idx <= 5
        lean = 0.03 - 0.04 * bless_k
        head_nod = 0.06 * bless_k if frame_idx <= 4 else -0.02 * bless_k
        wind_lift = bless_k
        eye_pulse = 0.45 + 0.55 * bless_k
        hand_l = np.array([4.35 - 1.65 * bless_k, 20.0 + 7.8 * bless_k, 5.8 + 2.6 * bless_k])
        hand_r = np.array([-3.65 + 0.95 * bless_k, 23.4 + 4.8 * bless_k, 6.8 + 1.6 * bless_k])
        pole_l = (1.5 + 0.6 * bless_k, -2.8, -1.8)
        pole_r = (-1.5 - 0.6 * bless_k, -2.8, -1.8)
        spark_pos = np.array([0.0, 29.2 + 1.6 * bless_k, 9.2])
        spark_r = 0.72 + 1.25 * bless_k
    else:
        # stand_idle: majestic ~66 px contrapposto pose with graceful relaxed arms (clear waist gap, no akimbo!)
        seat_dy = 0.0
        lean = 0.015 * breath
        twist = -0.04 + 0.02 * math.sin(phase)
        head_tilt = 0.025 * math.sin(phase - 0.5)
        hand_l = np.array([4.85, 25.2 + 0.20 * breath, 1.4])
        hand_r = np.array([-4.15, 29.2 + 0.35 * breath, 5.4])
        pole_l = (1.2, -3.0, -2.2)
        pole_r = (-1.4, -2.8, -2.0)
        spark_pos = hand_r + np.array([-0.15, 2.45 + 0.38 * math.sin(phase + 0.7), 0.9])
        spark_r = 0.70 + 0.12 * math.sin(phase)

    # ------------------------------------------------------------------
    # 1. Pelvis, Slender Shapely Legs & Criss-Cross Golden Sandals
    # ------------------------------------------------------------------
    pelvis_y = 28.0 + seat_dy + (0.12 * breath if not seated else 0.05 * breath)
    pelvis_z = -1.6 if seated else 0.0

    if seated:
        hip_l = np.array([2.10, pelvis_y - 0.6, pelvis_z + 0.6])
        knee_l = np.array([2.25, 13.8, 7.6])
        ankle_l = np.array([2.10, 2.6, 8.2])

        hip_r = np.array([-2.10, pelvis_y - 0.6, pelvis_z + 0.4])
        knee_r = np.array([-2.30, 14.8, 6.8])
        ankle_r = np.array([-2.15, 5.2, 6.8])
    else:
        hip_l = np.array([2.05, pelvis_y - 0.8, 0.0])
        knee_l = np.array([2.05, 14.8, 0.35])
        ankle_l = np.array([2.00, 2.3, -0.15])

        hip_r = np.array([-2.15, pelvis_y - 0.9, 0.15])
        knee_r = np.array([-2.35, 14.6, 1.05])
        ankle_r = np.array([-2.25, 2.5, 0.45])

    for _side, hip_a, knee_a, ankle_a in ((1, hip_l, knee_l, ankle_l), (-1, hip_r, knee_r, ankle_r)):
        th_v = knee_a - hip_a
        R_th = frame_from(-th_v, (0.0, 0.0, 1.0))
        for i_t in range(11):
            t_f = i_t / 10.0
            rx_t = 1.66 - 0.44 * (t_f ** 0.85)
            rz_t = 1.86 - 0.54 * (t_f ** 0.85)
            m.ell(hip_a + th_v * t_f, (rx_t, 1.42, rz_t), SKIN, R=R_th, layer="body_under" if t_f < 0.36 else "body")

        sh_v = ankle_a - knee_a
        R_sh = frame_from(-sh_v, (0.0, 0.0, 1.0))
        for i_s in range(11):
            t_s = i_s / 10.0
            swell = 0.18 * math.exp(-((t_s - 0.28) / 0.24) ** 2)
            rx_s = 1.16 + swell * 0.46 - 0.30 * (t_s ** 1.08)
            rz_s = 1.22 + swell - 0.32 * (t_s ** 1.08)
            m.ell(knee_a + sh_v * t_s, (rx_s, 1.16, rz_s), SKIN, R=R_sh, layer="body")
            if i_s in (4, 7):
                m.ell(knee_a + sh_v * t_s, (rx_s + 0.08, 0.24, rz_s + 0.08), GOLD, R=R_sh @ rot_z(0.25 if i_s == 4 else -0.25), layer="outfit")

        foot_c = ankle_a + np.array([0.0, -1.45, 1.18])
        m.ell(foot_c, (0.94, 0.68, 1.82), SKIN, layer="body")
        m.ell(foot_c + np.array([0.0, -0.34, 0.05]), (1.02, 0.36, 1.90), NIGHT_PLEAT, layer="outfit")
        m.ell(ankle_a + np.array([0.0, 0.20, 0.32]), (1.04, 0.25, 1.02), GOLD, layer="outfit")
        m.ell(foot_c + np.array([0.0, 0.22, 0.58]), (1.00, 0.22, 0.80), GOLD, layer="outfit")

    # ------------------------------------------------------------------
    # 2. Cinched Hourglass Torso, Collarbones & Slender Relaxed Arms
    # ------------------------------------------------------------------
    tor = rot_x(lean) @ rot_y(twist)
    waist_base = np.array([0.0, pelvis_y + 1.2, pelvis_z])

    def T(pt: tuple[float, float, float] | np.ndarray) -> np.ndarray:
        return waist_base + tor @ np.asarray(pt, dtype=np.float64)

    m.ell(T((0.0, 0.0, 0.10)), (2.64, 2.05, 2.08), SKIN, R=tor, layer="body_under")
    m.ell(T((0.0, 2.95 + 0.05 * breath, 0.05)), (1.90, 2.35, 1.88), SKIN, R=tor, layer="body_under")
    m.ell(T((0.0, 5.45 + 0.08 * breath, 0.08)), (2.26, 2.15, 2.08), SKIN, R=tor, layer="body_under")

    m.ell(T((0.0, 9.25 + 0.12 * breath, 0.35)), (2.62, 1.80, 1.74), SKIN, R=tor, layer="body")
    m.ell(T((0.0, 9.00 + 0.10 * breath, -0.35)), (2.82, 1.80, 1.82), SKIN, R=tor, layer="body")
    for sx in (-1.0, 1.0):
        m.limb(
            T((sx * 0.90, 10.65 + 0.10 * breath, 0.12)),
            T((sx * 3.45, 9.95 + 0.14 * breath, -0.05)),
            1.12,
            0.96,
            SKIN,
            layer="body",
        )

    m.limb(T((0.0, 9.8, 0.16)), T((0.0, 15.3, 0.36)), 1.08, 0.94, SKIN, layer="body")

    shoulders: dict[int, np.ndarray] = {}
    for side, hand_t, pole_v in ((1, hand_l, pole_l), (-1, hand_r, pole_r)):
        sh = T((side * 3.62, 9.85 + 0.14 * breath, -0.08))
        shoulders[side] = sh
        elb, wri = ik2(sh, hand_t, 6.7, 6.2, pole_v)
        d_fore = wri - elb
        d_fore /= max(float(np.linalg.norm(d_fore)), 1e-6)

        m.limb(sh, elb, 0.90, 0.76, SKIN, layer="body")
        m.limb(elb, wri, 0.76, 0.62, SKIN, layer="body")
        m.ell(wri + 0.68 * d_fore, (0.66, 0.76, 0.66), SKIN, layer="body")

        # Golden winged shoulder clasp + turquoise gem + upper-arm ring + wrist cuff
        m.ell(sh + np.array([side * 0.16, 0.50, 0.15]), (1.18, 0.48, 1.14), GOLD, layer="outfit")
        m.ell(sh + np.array([side * 0.36, 0.68, 0.40]), (0.42, 0.42, 0.38), TEAL_EMIT, kind="emit", layer="outfit")
        m.ell(sh + (elb - sh) * 0.42, (0.94, 0.25, 0.94), GOLD, layer="outfit")
        m.ell(elb + (wri - elb) * 0.76, (0.80, 0.28, 0.80), GOLD, layer="outfit")

    # ------------------------------------------------------------------
    # 3. Richly Textured High-Waisted Divine Gown (`outfit` layer)
    # ------------------------------------------------------------------
    m.ell(T((0.0, 2.85 + 0.05 * breath, 0.08)), (2.30, 2.85, 2.06), NIGHT_SILK, R=tor, kind="corset", layer="outfit")
    m.ell(T((0.0, 6.35 + 0.12 * breath, 0.10)), (2.82, 2.50, 2.28), PEARL_SILK, R=tor, kind="bustier", layer="outfit")
    for sx in (-1.0, 1.0):
        m.ell(T((sx * 1.32, 6.55 + 0.15 * breath, 1.52)), (1.45, 1.42, 1.42), PEARL_SILK, R=tor, kind="bustier", layer="outfit")

    # Heart-star turquoise brooch + delicate golden collarbone necklace
    m.ell(T((0.0, 7.60 + 0.14 * breath, 1.92)), (0.64, 0.72, 0.48), GOLD, R=tor, layer="outfit")
    m.ell(T((0.0, 7.60 + 0.14 * breath, 2.10)), (0.44, 0.52, 0.38), TEAL_EMIT, R=tor, kind="emit", layer="outfit")
    m.ell(T((0.0, 10.65, 1.22)), (1.20, 0.22, 1.10), GOLD, R=tor, layer="outfit")

    # Sculpted golden V-girdle belt + hip chain loops
    m.ell(T((0.0, 4.35 + 0.08 * breath, 0.12)), (2.50, 0.40, 2.18), GOLD, R=tor, layer="outfit")
    m.ell(T((0.0, 3.80 + 0.08 * breath, 2.10)), (0.72, 0.78, 0.38), GOLD, R=tor, layer="outfit")
    m.ell(T((0.0, 3.80 + 0.08 * breath, 2.26)), (0.40, 0.46, 0.32), TEAL_EMIT, R=tor, kind="emit", layer="outfit")
    for sx in (-1.0, 1.0):
        m.ell(T((sx * 1.82, 3.35 + 0.06 * breath, 1.82)), (0.56, 0.24, 0.34), GOLD, R=tor @ rot_z(sx * 0.45), layer="outfit")

    hip_mid = np.array([0.0, pelvis_y - 0.2, pelvis_z + 0.1])
    m.ell(hip_mid + np.array([0.0, 1.3, 0.0]), (3.12, 2.10, 2.45), NIGHT_SILK, layer="outfit")
    if seated:
        lap_c = 0.5 * (hip_l + hip_r) + np.array([0.0, 0.4, 2.15])
        m.ell(lap_c, (3.20, 1.80, 2.72), NIGHT_SILK, layer="outfit")

    # A) Astrolabe-Embroidered Pearl-Ivory Center Stole (`stole_front`)
    breeze_x = 0.28 * math.sin(phase - 0.7)
    if seated:
        stole_top = np.array([0.0, pelvis_y + 1.4, pelvis_z + 2.35])
        stole_knee = np.array([0.0, 15.2, 7.85])
        stole_bot = np.array([0.15 * breeze_x, 5.0, 8.65 + 0.25 * wind_lift])

        v_up1 = stole_top - stole_knee
        l1 = float(np.linalg.norm(v_up1))
        ry1 = l1 / 1.56
        c1 = stole_knee + (v_up1 / l1) * (0.68 * ry1)
        m.ell(c1, (1.82, ry1, 0.80), PEARL_SILK, R=panel_basis(np.array([1.0, 0.0, 0.0]), v_up1), kind="stole_front", clip=clip_stole_panel, layer="outfit")

        v_up2 = stole_knee - stole_bot
        l2 = float(np.linalg.norm(v_up2))
        ry2 = l2 / 1.56
        c2 = stole_bot + (v_up2 / l2) * (0.68 * ry2)
        m.ell(c2, (1.65, ry2, 0.78), PEARL_SILK, R=panel_basis(np.array([1.0, 0.0, 0.0]), v_up2), kind="stole_front", clip=clip_stole_panel, layer="outfit")
    else:
        stole_top = np.array([0.0, pelvis_y + 1.2, 2.20])
        stole_bot = np.array([0.22 * breeze_x, 5.2, 2.10 + 0.22 * math.sin(phase)])
        v_up = stole_top - stole_bot
        ln = float(np.linalg.norm(v_up))
        ry_s = ln / 1.56
        c_s = stole_bot + (v_up / ln) * (0.68 * ry_s)
        m.ell(c_s, (1.85, ry_s, 0.82), PEARL_SILK, R=panel_basis(np.array([1.0, 0.0, 0.0]), v_up), kind="stole_front", clip=clip_stole_panel, layer="outfit")

    # B) Pleated Royal Night-Blue Overskirt Wings (`overskirt`)
    for side in (-1.0, 1.0):
        sway_s = (0.32 + 0.52 * wind_lift) * side + 0.25 * math.sin(phase + side * 0.8)
        if seated:
            top_w = np.array([side * 2.90, pelvis_y + 0.8, pelvis_z + 0.8])
            mid_w = np.array([side * (4.15 + 0.25 * wind_lift), 13.6, 5.8])
            bot_w = np.array([side * (4.55 + 0.45 * wind_lift) + 0.2 * sway_s, 3.8 + 0.5 * wind_lift, 6.4])
            m.ribbon(
                [top_w, mid_w, bot_w],
                [1.55, 1.95, 1.32],
                0.78,
                NIGHT_SILK,
                hint=(side * 0.65, 0.0, 0.75),
                kind="overskirt",
                tag=side,
                layer="outfit",
            )
        else:
            top_w = np.array([side * 2.75, pelvis_y + 0.8, 0.2])
            mid_w = np.array([side * 3.65 + 0.15 * sway_s, 15.2, -0.30])
            bot_w = np.array([side * 4.08 + 0.28 * sway_s, 3.5, -0.85])
            m.ribbon(
                [top_w, mid_w, bot_w],
                [1.55, 2.02, 1.46],
                0.80,
                NIGHT_SILK,
                hint=(side * 0.72, 0.0, 0.68),
                kind="overskirt",
                tag=side,
                layer="outfit",
            )
            m.ribbon(
                [
                    np.array([side * 1.75, pelvis_y + 0.4, -1.80]),
                    np.array([side * 2.25 + 0.15 * sway_s, 14.5, -3.05]),
                    np.array([side * 2.55 + 0.28 * sway_s, 2.8, -4.05]),
                ],
                [1.75, 2.15, 1.55],
                0.75,
                NIGHT_SILK,
                hint=(0.0, 0.0, -1.0),
                kind="overskirt",
                tag=side * 2.0,
                layer="hair_back",
            )

    # ------------------------------------------------------------------
    # 4. Twin Gossamer Starry Astral Ribbon-Veils (`veil_back`)
    # ------------------------------------------------------------------
    for side in (-1.0, 1.0):
        sh = shoulders[side]
        v_pts = []
        for lv in np.linspace(0.0, 1.0, 6):
            wave_v = math.sin(phase - 1.8 * lv + side * 0.6)
            vx = sh[0] + side * (1.15 + (3.45 + 1.80 * wind_lift) * (lv ** 0.92)) + 0.38 * lv * wave_v
            vy = sh[1] + 0.80 * math.sin(math.pi * min(lv, 0.45)) - (12.6 - 3.5 * wind_lift) * (lv ** 1.08)
            vz = sh[2] - 1.35 - 1.65 * lv + 0.40 * lv * math.cos(phase - 1.4 * lv)
            v_pts.append(np.array([vx, vy, vz]))
        m.ribbon(
            v_pts,
            [0.65, 1.08, 1.20, 1.02, 0.68, 0.24],
            0.46,
            ASTRAL_VEIL,
            hint=(0.0, 0.0, 1.0),
            kind="veil",
            tag=side * 1.5,
            layer="veil_back",
        )

    # ------------------------------------------------------------------
    # 5. Sleek Sculpted Head, Voluminous Wavy Silver-Gold Hair, Braids & Diadem
    # ------------------------------------------------------------------
    head_R = tor @ rot_y(head_yaw) @ rot_z(head_tilt) @ rot_x(head_nod)
    head_piv = np.array([0.0, 18.2 + 0.14 * breath, 0.45])
    hc = T(head_piv)

    def H(pt: tuple[float, float, float] | np.ndarray) -> np.ndarray:
        return hc + head_R @ np.asarray(pt, dtype=np.float64)

    m.ell(hc, (3.55, 4.15, 3.65), SKIN, R=head_R, kind="head", layer="body")
    m.ell(H((0.0, -1.48, 0.68)), (2.22, 2.05, 2.45), SKIN, R=head_R, kind="head", layer="body")

    ez = math.sqrt(1.0 - 0.36 * 0.36 - 0.05 * 0.05)
    for sx in (-1.0, 1.0):
        ep = H((sx * 0.37 * 3.55, -0.22, ez * 3.65))
        en = head_R @ np.array([sx * 0.34, 0.0, ez])
        m.eyes.append((ep, en, eyes_closed))

    # Rounded, voluminous anime hair crown & side-waves (`hair_back` + `hair_front`)
    m.ell(H((0.0, 0.55, -0.28)), (4.18, 4.58, 4.12), HAIR_SILV, R=head_R, kind="hair", tag=2.5, clip=clip_hair_cap, layer="hair_back")
    for sx in (-1.0, 1.0):
        m.ell(H((sx * 1.25, 3.35, 0.35)), (2.18, 1.55, 2.55), HAIR_SILV, R=head_R @ rot_z(-sx * 0.18), kind="hair", tag=10.2 + sx, layer="hair_front")

    # Sweeping parted curtain bangs + sculpted temple braids + collarbone locks!
    for side in (-1.0, 1.0):
        sway_b = 0.24 * math.sin(phase + side * 0.7)
        m.ribbon(
            [
                H((side * 0.32, 4.05, 1.95)),
                H((side * 1.85, 2.65, 3.48)),
                H((side * 3.15, 0.72, 2.95)),
                H((side * 3.72 + 0.12 * sway_b, -1.25 + 0.25 * wind_lift, 1.88)),
            ],
            [0.92, 1.06, 0.84, 0.32],
            0.54,
            HAIR_SILV,
            hint=(0.0, 0.0, 1.0),
            kind="hair",
            tag=10.5 + side,
            layer="hair_front",
        )

        # Twisted half-up golden-silver temple braid
        for k_b in range(5):
            ub = k_b / 4.0
            ang_b = 0.32 - ub * 1.15
            bx = side * 4.15 * math.cos(ang_b)
            by = 1.95 - 0.55 * math.sin(math.pi * ub * 0.8) + 0.18 * ((-1) ** k_b)
            bz = 4.15 * math.sin(ang_b) - 0.20
            b_R = head_R @ rot_y(side * ang_b) @ rot_x(0.38 * ((-1) ** k_b))
            m.ell(H((bx, by, bz)), (0.66, 0.80, 0.70), HAIR_GOLD, R=b_R, kind="braid", tag=k_b * 0.9, layer="hair_front")

        # Slender front collarbone braid/lock with gold ring & turquoise star-gem!
        lock_pts = []
        gem_pt = None
        for idx_l, ll in enumerate(np.linspace(0.0, 1.0, 7)):
            w_l = math.sin(phase - 1.6 * ll + side * 0.5)
            lx = side * (3.78 - 0.32 * ll + 0.68 * wind_lift * ll) + 0.26 * (ll ** 1.1) * w_l
            ly = 0.65 - (10.5 - 2.2 * wind_lift) * ll
            lz = 1.12 + 1.48 * math.sin(math.pi * min(ll * 0.75, 0.88))
            pt_w = H((lx, ly, lz)) if ll < 0.25 else (
                (1.0 - min(1.0, (ll - 0.25) * 1.3)) * H((lx, ly, lz))
                + min(1.0, (ll - 0.25) * 1.3) * (hc + np.array([lx, ly, lz]))
            )
            lock_pts.append(pt_w)
            if idx_l == 4:
                gem_pt = pt_w
        m.ribbon(
            lock_pts,
            [0.72, 0.82, 0.76, 0.66, 0.52, 0.34, 0.15],
            0.48,
            HAIR_SILV,
            hint=(0.0, 0.0, 1.0),
            kind="braid",
            tag=6.0 + side,
            layer="hair_front",
        )
        if gem_pt is not None:
            m.ell(gem_pt + np.array([0.0, 0.36, 0.26]), (0.42, 0.28, 0.38), GOLD, layer="hair_front")
            m.ell(gem_pt + np.array([0.0, -0.08, 0.30]), (0.44, 0.52, 0.42), TEAL_EMIT, kind="emit", layer="hair_front")

    # Filigree Golden Starlight Forehead Diadem + Central Turquoise Gem
    m.ell(H((0.0, 2.72, 3.55)), (0.48, 0.56, 0.42), TEAL_EMIT, R=head_R, kind="emit", layer="hair_front")
    m.ell(H((0.0, 3.38, 3.38)), (0.34, 0.42, 0.34), HALO_EMIT, R=head_R, kind="emit", layer="hair_front")
    for side in (-1.0, 1.0):
        m.ell(H((side * 0.92, 2.88, 3.38)), (0.56, 0.26, 0.38), GOLD, R=head_R @ rot_y(-side * 0.25), layer="hair_front")
        m.ell(H((side * 1.98, 2.62, 2.86)), (0.52, 0.26, 0.38), GOLD, R=head_R @ rot_y(-side * 0.52), layer="hair_front")
        m.ell(H((side * 2.88, 2.30, 2.02)), (0.42, 0.25, 0.36), GOLD, R=head_R @ rot_y(-side * 0.78), layer="hair_front")

    # Voluminous Flowing Silver-Light-Gold Back Waves (fans gracefully past shoulders so silhouette reads lush from front & 3/4!)
    back_plumes = [
        (-3.85, 20.8, [1.05, 1.32, 1.38, 1.24, 0.98, 0.65, 0.28]),
        (-2.15, 24.0, [1.22, 1.48, 1.52, 1.35, 1.08, 0.72, 0.32]),
        (0.0,   25.8, [1.35, 1.62, 1.64, 1.45, 1.18, 0.80, 0.36]),
        (2.15,  24.0, [1.22, 1.48, 1.52, 1.35, 1.08, 0.72, 0.32]),
        (3.85,  20.8, [1.05, 1.32, 1.38, 1.24, 0.98, 0.65, 0.28]),
    ]
    for p_i, (bx, drop_len, widths) in enumerate(back_plumes):
        pts_b = []
        for lb in np.linspace(0.0, 1.0, len(widths)):
            wb = math.sin(phase - 1.9 * lb + p_i * 0.65)
            wave_s = 0.42 * math.sin(3.4 * lb + p_i * 0.8) * lb
            px = bx * (0.88 + (0.48 + 0.36 * wind_lift) * lb) + wave_s + 0.48 * (lb ** 1.15) * wb
            py = 1.4 - (drop_len - 3.8 * wind_lift) * lb
            pz = -2.45 - 1.55 * math.sin(math.pi * min(lb * 0.85, 0.9)) - 0.80 * lb
            pts_b.append(hc + np.array([px, py, pz]))
        m.ribbon(
            pts_b,
            widths,
            0.82,
            HAIR_SILV,
            hint=(0.0, 0.0, -1.0),
            kind="hair",
            tag=p_i * 1.9 + 1.2,
            layer="hair_back",
        )

    # ------------------------------------------------------------------
    # 6. Delicate Filigree Golden Halo Arc + 7 Slender Faceted Crystal Rays (`halo_back`)
    # ------------------------------------------------------------------
    halo_c = hc + np.array([0.0, 2.25 + 0.22 * math.sin(phase + 0.5) + 0.45 * wind_lift, -3.5])
    halo_r = 6.45 + 0.25 * wind_lift

    n_arc = 34
    for i_a in range(n_arc):
        ang = math.radians(-18.0 + 216.0 * (i_a / (n_arc - 1)))
        ac = halo_c + np.array([halo_r * math.cos(ang), halo_r * math.sin(ang), 0.0])
        m.ell(ac, (0.30, 0.48, 0.28), HALO_EMIT, R=rot_z(ang), kind="emit", layer="halo_back")

    ray_angles = (-10.0, 23.0, 56.5, 90.0, 123.5, 157.0, 190.0)
    for r_idx, deg in enumerate(ray_angles):
        ang = math.radians(deg)
        is_top = r_idx == 3
        is_mid = r_idx in (1, 5)
        gap_r = halo_r + (1.30 if is_top else 1.15) + 0.18 * math.sin(phase + r_idx)
        shard_len = (2.60 if is_top else (2.00 if is_mid else 1.50)) + 0.45 * wind_lift
        shard_w = 0.50 if is_top else (0.42 if is_mid else 0.35)
        sc = halo_c + np.array([(gap_r + shard_len * 0.48) * math.cos(ang), (gap_r + shard_len * 0.48) * math.sin(ang), 0.0])
        R_shd = rot_z(ang - math.pi * 0.5)
        m.ell(sc, (shard_w, shard_len * 0.55, 0.32), STAR_EMIT, R=R_shd, kind="crystal_ray", tag=float(r_idx), layer="halo_back")

    # ------------------------------------------------------------------
    # 7. Floating Starlight Spark / Blooming Blessing Star (`fx_front`)
    # ------------------------------------------------------------------
    if clip == "sit_bless" and bless_k > 0.12:
        star_spin = 0.32 * u
        b_rad = spark_r * 1.35
        m.ell(spark_pos, (b_rad * 0.58, b_rad * 0.58, b_rad * 0.58), HALO_EMIT, kind="emit", layer="fx_front")
        for k_ray in range(4):
            ra = star_spin + k_ray * (math.pi * 0.25)
            r_len = b_rad * (2.05 if k_ray % 2 == 0 else 1.32)
            r_wid = 0.46 if k_ray % 2 == 0 else 0.34
            r_mat = HALO_EMIT if k_ray % 2 == 0 else STAR_EMIT
            m.ell(spark_pos, (r_wid, r_len, 0.34), r_mat, R=rot_z(ra), kind="crystal_ray", tag=float(k_ray), layer="fx_front")
        for m_i in range(4):
            ma = phase + m_i * (2.0 * math.pi / 4.0)
            mp_c = spark_pos + np.array([math.cos(ma) * (3.2 + 1.6 * bless_k), math.sin(ma) * (2.4 + 1.1 * bless_k), 0.6])
            m.ell(mp_c, (0.42, 0.42, 0.42), TEAL_EMIT, kind="emit", layer="fx_front")
    else:
        m.ell(spark_pos, (0.38, spark_r * 1.20, 0.38), STAR_EMIT, kind="crystal_ray", tag=1.0, layer="fx_front")
        m.ell(spark_pos, (spark_r * 0.94, 0.34, 0.34), TEAL_EMIT, kind="emit", layer="fx_front")

    return m, bless_k, eye_pulse


# ---------------------------------------------------------------------------
# Frame Renderer (`art_hero3d.render_layers` outer-air-only silhouette ink!)
# ---------------------------------------------------------------------------
def render_frame(clip: str, frame_idx: int, n_frames: int, yaw_deg: float) -> tuple[np.ndarray, np.ndarray]:
    yaw = math.radians(yaw_deg)
    model, bless_k, eye_pulse = build_goddess(clip, frame_idx, n_frames)
    tprims = model.transform(yaw)
    Ry = rot_y(yaw)

    def by_layer(*names: str) -> list[Prim]:
        s = set(names)
        return [p for p in tprims if p.layer in s]

    d_halo, c_halo, _ = raster_subset(by_layer("halo_back"), bless_k)
    b_halo, s_halo, _ = resolve_layer_raw(d_halo, c_halo, min_cov=4, crease_thresh=-1.0)

    d_veil, c_veil, _ = raster_subset(by_layer("veil_back"), bless_k)
    b_veil, s_veil, cr_veil = resolve_layer_raw(d_veil, c_veil, min_cov=5, crease_thresh=2.8)

    d_hb, c_hb, _ = raster_subset(by_layer("hair_back"), bless_k)
    b_hb, s_hb, cr_hb = resolve_layer_raw(d_hb, c_hb, min_cov=6, crease_thresh=2.6)

    d_body, c_body, _ = raster_subset(by_layer("body", "body_under"), bless_k)
    d_occ, _, _ = raster_subset(by_layer("body"), bless_k)
    b_body, s_body, cr_body = resolve_layer_raw(d_body, c_body, min_cov=6, crease_thresh=2.6)

    d_out, c_out, _ = raster_subset(by_layer("outfit"), bless_k, init_depth=d_occ)
    b_out, s_out, cr_out = resolve_layer_raw(d_out, c_out, min_cov=5, crease_thresh=2.6)

    d_mid = np.maximum(d_body, d_out)
    d_hf, c_hf, _ = raster_subset(by_layer("hair_front"), bless_k, init_depth=d_mid - 0.16)
    b_hf, s_hf, cr_hf = resolve_layer_raw(d_hf, c_hf, min_cov=5, crease_thresh=2.8)

    d_fx, c_fx, _ = raster_subset(by_layer("fx_front"), bless_k)
    b_fx, s_fx, _ = resolve_layer_raw(d_fx, c_fx, min_cov=4, crease_thresh=-1.0)

    # Merge solid pixel codes back-to-front WITHOUT interior black lines!
    # Instead, transitions between hair_front -> face, bustier -> chest, stole -> legs use
    # natural 1px Band-0 material shadow creases (`art_hero3d.py` exact technique!).
    final_code = np.full((FH, FW), -1, dtype=np.int16)
    final_crease = np.zeros((FH, FW), dtype=bool)
    char_solid = s_veil | s_hb | s_body | s_out | s_hf

    # Halo sits behind everything and gets its warm outline in open air around the character
    canvas = np.zeros((FH, FW, 4), dtype=np.uint8)
    emit_mask = np.zeros((FH, FW), dtype=bool)

    if clip == "stand_idle":
        yy, xx = np.ogrid[:FH, :FW]
        sh_m = ((xx - FW * 0.5) / 8.5) ** 2 + ((yy - (GROUND_ROW + 1.0)) / 2.6) ** 2 <= 1.0
        canvas[sh_m] = (14, 10, 26, 110)

    # Paint floating halo first (with 1px warm outline in open air)
    for y in range(FH):
        for x in range(FW):
            vh = int(b_halo[y, x])
            if vh >= 0:
                mh, bh = divmod(vh, 4)
                r, g, b = RAMPS[mh][bh]
                canvas[y, x] = (r, g, b, 255)
                if mh in EMIT_MATS:
                    emit_mask[y, x] = True
            elif not char_solid[y, x]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < FW and 0 <= ny < FH and b_halo[ny, nx] >= 0:
                        canvas[y, x] = HALO_INK
                        break

    # Stack character layers cleanly (`veil_back` -> `hair_back` -> `body` -> `outfit` -> `hair_front`)
    for b_lyr, s_lyr, cr_lyr, add_shadow_under in (
        (b_veil, s_veil, cr_veil, False),
        (b_hb, s_hb, cr_hb, False),
        (b_body, s_body, cr_body, True),
        (b_out, s_out, cr_out, False),
        (b_hf, s_hf, cr_hf, False),
    ):
        # Soft 1px Band-0 shadow on back hair right around neck/body silhouette for crisp depth separation!
        if add_shadow_under:
            dil_b = np.zeros_like(s_lyr)
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                dil_b |= np.roll(np.roll(s_lyr, dy, 0), dx, 1)
            final_crease |= dil_b & (~s_lyr) & (final_code >= 0)
        final_code = np.where(s_lyr, b_lyr, final_code)
        final_crease = np.where(s_lyr, cr_lyr, final_crease)

    # Resolve character pixels + 1px outer silhouette outline ONLY into open air (`~char_solid`)!
    for y in range(FH):
        for x in range(FW):
            v = int(final_code[y, x])
            if v >= 0:
                m_i, b_i = divmod(v, 4)
                if final_crease[y, x] and m_i not in EMIT_MATS and m_i != SKIN:
                    b_i = 0
                r, g, b = RAMPS[m_i][b_i]
                canvas[y, x] = (r, g, b, 255)
                emit_mask[y, x] = m_i in EMIT_MATS
            else:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < FW and 0 <= ny < FH and final_code[ny, nx] >= 0:
                        nb_mat = int(final_code[ny, nx]) // 4
                        canvas[y, x] = mat_ink(nb_mat)
                        emit_mask[y, x] = False
                        break

    # Precision pixel-art glowing turquoise eyes (`stamp_goddess_eyes`)
    eye_pts_2d: list[tuple[float, float, float, bool]] = []
    for ep, en, closed in model.eyes:
        pr = Ry @ ep * SCALE
        sx = FW * 0.5 + float(pr[0])
        sy = GROUND_ROW - float(pr[1] * COSP - pr[2] * SINP)
        facing = float((Ry @ en) @ WHAT)
        eye_pts_2d.append((sx, sy, facing, closed))
    stamp_goddess_eyes(canvas, emit_mask, eye_pts_2d, eye_pulse)

    # Re-apply solid front bangs over outer eye corners so bangs drape naturally over upper lashes
    for y in range(FH):
        for x in range(FW):
            vhf = int(b_hf[y, x])
            if vhf >= 0:
                m_i, b_i = divmod(vhf, 4)
                if cr_hf[y, x] and m_i not in EMIT_MATS:
                    b_i = 0
                r, g, b = RAMPS[m_i][b_i]
                canvas[y, x] = (r, g, b, 255)
                emit_mask[y, x] = m_i in EMIT_MATS

    # Paint floating palm spark / blooming blessing star (`fx_front`)
    for y in range(FH):
        for x in range(FW):
            vfx = int(b_fx[y, x])
            if vfx >= 0:
                m_i, b_i = divmod(vfx, 4)
                r, g, b = RAMPS[m_i][b_i]
                canvas[y, x] = (r, g, b, 255)
                emit_mask[y, x] = m_i in EMIT_MATS

    # Build crisp `goddess_glow.png`
    glow = np.zeros((FH, FW, 4), dtype=np.uint8)
    glow[emit_mask] = canvas[emit_mask]

    air = canvas[..., 3] == 0
    if emit_mask.any():
        aura = np.zeros((FH, FW), dtype=bool)
        aura_col = np.zeros((FH, FW, 3), dtype=np.uint8)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            dist = abs(dy) + abs(dx)
            if dist > (3 if bless_k > 0.35 else 2):
                continue
            nb_em = np.zeros_like(emit_mask)
            nb_c = np.zeros((FH, FW, 3), dtype=np.uint8)
            sy0, sy1 = max(0, -dy), FH - max(0, dy)
            dy0, dy1 = max(0, dy), FH - max(0, -dy)
            sx0, sx1 = max(0, -dx), FW - max(0, dx)
            dx0, dx1 = max(0, dx), FW - max(0, -dx)
            nb_em[dy0:dy1, dx0:dx1] = emit_mask[sy0:sy1, sx0:sx1]
            nb_c[dy0:dy1, dx0:dx1] = canvas[sy0:sy1, sx0:sx1, :3]
            bayer_ok = ((np.arange(FH)[:, None] + np.arange(FW)[None, :]) % 2 == 0) if dist == 1 else (
                (np.arange(FH)[:, None] % 2 == 0) & (np.arange(FW)[None, :] % 2 == 0)
            )
            hit_a = air & nb_em & (~aura) & bayer_ok
            aura |= hit_a
            aura_col[hit_a] = nb_c[hit_a]
        glow[aura, :3] = aura_col[aura]
        glow[aura, 3] = 150 if bless_k > 0.35 else 105

    return canvas, glow


# ---------------------------------------------------------------------------
# Sheet Assembly & Multiprocessing Entrypoint
# ---------------------------------------------------------------------------
CLIPS: list[tuple[str, int, int, bool]] = [
    ("sit_idle", 6, 6, True),
    ("sit_talk", 6, 7, True),
    ("sit_bless", 8, 8, False),
    ("stand_idle", 6, 6, True),
]
FACINGS: list[tuple[str, float]] = [
    ("S", 0.0),
    ("SE", -32.0),
    ("SW", 32.0),
]


def _worker(job: tuple[int, int, str, int, int, float]) -> tuple[int, int, bytes, bytes]:
    row_i, col_i, clip_name, f_i, n_f, yaw_deg = job
    col_arr, glow_arr = render_frame(clip_name, f_i, n_f, yaw_deg)
    return row_i, col_i, col_arr.tobytes(), glow_arr.tobytes()


def write_rgba_sheet(path: Path, arr: np.ndarray) -> None:
    h, w, _ = arr.shape
    rows = [[tuple(int(v) for v in arr[y, x]) for x in range(w)] for y in range(h)]
    write_png(path, w, h, rows)


def main() -> None:
    total_cols = sum(cnt for _, cnt, _, _ in CLIPS)
    total_rows = len(FACINGS)
    sheet_c = np.zeros((total_rows * FH, total_cols * FW, 4), dtype=np.uint8)
    sheet_g = np.zeros((total_rows * FH, total_cols * FW, 4), dtype=np.uint8)

    jobs: list[tuple[int, int, str, int, int, float]] = []
    for r_i, (_f_name, yaw_deg) in enumerate(FACINGS):
        col_cursor = 0
        for c_name, cnt, _fps, _loop in CLIPS:
            for f_i in range(cnt):
                jobs.append((r_i, col_cursor + f_i, c_name, f_i, cnt, yaw_deg))
            col_cursor += cnt

    workers = min(6, os.cpu_count() or 1)
    with mp.Pool(workers) as pool:
        for r_i, col_i, cb, gb in pool.imap_unordered(_worker, jobs, chunksize=2):
            y0, y1 = r_i * FH, (r_i + 1) * FH
            x0, x1 = col_i * FW, (col_i + 1) * FW
            sheet_c[y0:y1, x0:x1] = np.frombuffer(cb, dtype=np.uint8).reshape(FH, FW, 4)
            sheet_g[y0:y1, x0:x1] = np.frombuffer(gb, dtype=np.uint8).reshape(FH, FW, 4)

    out_c = ROOT / "characters" / "goddess.png"
    out_g = ROOT / "characters" / "goddess_glow.png"
    write_rgba_sheet(out_c, sheet_c)
    write_rgba_sheet(out_g, sheet_g)

    clips_meta: dict[str, dict[str, int | bool]] = {}
    col_cursor = 0
    for c_name, cnt, fps, loop in CLIPS:
        clips_meta[c_name] = {"start": col_cursor, "count": cnt, "fps": fps, "loop": loop}
        col_cursor += cnt

    rig_data = {
        "texture": "res://assets/characters/goddess.png",
        "glow_texture": "res://assets/characters/goddess_glow.png",
        "frame_size": [FW, FH],
        "feet": [FW // 2, int(GROUND_ROW)],
        "standing_height_px": 66,
        "columns": total_cols,
        "rows": total_rows,
        "default_row": 0,
        "facings": [name for name, _ in FACINGS],
        "row_by_facing": {name: idx for idx, (name, _) in enumerate(FACINGS)},
        "clips": clips_meta,
    }
    rig_path = ROOT.parent / "data" / "goddess_rig.json"
    rig_path.write_text(json.dumps(rig_data, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_c} ({total_cols * FW}x{total_rows * FH}), {out_g}, and {rig_path}")


if __name__ == "__main__":
    main()
