#!/usr/bin/env python3
"""Procedural pixel-art generator for Die Zenitwarte (Sonnenquarz-Öde Abandoned Desert Observatory).

Generates 11 paired sprite/glow sheets in assets/props/observatory/, exact anchor & feature
metadata in data/desert_observatory_art.json, and 2x day/night QA contact sheet in
docs/img/desert_observatory_qa.png.

Strict Shadowspore Art Pipeline Rules:
  - Top-left sunlight (-0.5, -0.7, 0.5), crisp cel bands, ashlar courses, crystal facets (NO random noise).
  - 1 px material-tinted outlines (#2a1c28 sandstone, #120e22 indigo, #34221e brass, #282238 quartz) — ZERO #000000!
  - Emissive pixels strictly isolated to matching *_glow.png sheets (modest/crisp alpha).
  - Minimum 2 px safe frame padding on all sprites (plus strict pool & gate-span checks).

Usage:
  py -3 tools/art_desert_observatory.py
"""
from __future__ import annotations

import json
import math
import pathlib
import sys
from typing import Callable, Optional

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

OBS_DIR = ROOT / "props" / "observatory"
DATA_PATH = ROOT.parent / "data" / "desert_observatory_art.json"
QA_PATH = ROOT.parent / "docs" / "img" / "desert_observatory_qa.png"


# ==============================================================================
# 1. PALETTES, OUTLINES & 3/4 PROJECTION CONSTANTS (ZERO #000000 ANYWHERE!)
# ==============================================================================
def ramp(*hexes: str) -> list[tuple[int, int, int, int]]:
    return [hexc(h) for h in hexes]


# Material Palettes (dark -> light)
SANDSTONE = ramp("483038", "785042", "aa7a4e", "d8a868", "f2cf8e")
SAND_DRIFT = ramp("6e4934", "9c6c44", "c89658", "e6be78", "f7de9e")
INDIGO = ramp("171329", "2a2548", "4a4180", "7a70b8")
GOLD = ramp("4a3318", "6f5020", "b48a38", "e6c468", "fff0b0")
VERDIGRIS = hexc("2a8c94")
VERDIGRIS_SHADE = hexc("1e626c")
QUARTZ_W = ramp("5b698e", "8191b6", "a2b3d4", "bfcde7", "d6e2f5", "ffffff")

# Glow Palettes (for *_glow.png + base bright core)
TURQ = ramp("2a8c94", "3cc0c6", "78f4e6", "d0fff8")
SOLAR = ramp("ffb84a", "ffe48a", "fff0b0")
ASTRAL = ramp("9468ee", "cbaaff")

# Material-tinted 1px Outline Inks (ZERO #000000!)
INK_SANDSTONE = hexc("2a1c28")
INK_INDIGO = hexc("120e22")
INK_GOLD = hexc("34221e")
INK_QUARTZ = hexc("282238")
SHADOW_TINT = (58, 36, 48)  # Warm plum-umber translucent ground shadow

# Material IDs for Pixel Buffer Tracking
MAT_NONE = 0
MAT_SANDSTONE = 1
MAT_SAND = 2
MAT_INDIGO = 3
MAT_GOLD = 4
MAT_QUARTZ = 5

INK_BY_MAT = {
    MAT_SANDSTONE: INK_SANDSTONE,
    MAT_SAND: None,  # Wind-drifted sand never gets a hard dark rim against desert ground
    MAT_INDIGO: INK_INDIGO,
    MAT_GOLD: INK_GOLD,
    MAT_QUARTZ: INK_QUARTZ,
}

PAL_BY_MAT = {
    MAT_SANDSTONE: SANDSTONE,
    MAT_SAND: SAND_DRIFT,
    MAT_INDIGO: INDIGO,
    MAT_GOLD: GOLD,
    MAT_QUARTZ: QUARTZ_W,
}

# Top-Left Sunlight & 3/4 Projection Basis
# Screen-space: +x right, +y down, +z toward viewer -> L_2D = norm(-0.5, -0.7, +0.5)
# World-space: +X right, +Y up, +Z toward viewer -> L_3D = norm(-0.5, +0.7, +0.5)
_L3_RAW = np.array([-0.5, 0.7, 0.5], dtype=np.float64)
L_3D = _L3_RAW / np.linalg.norm(_L3_RAW)
_L2_RAW = np.array([-0.5, -0.7, 0.5], dtype=np.float64)
L_2D = _L2_RAW / np.linalg.norm(_L2_RAW)

PITCH = math.radians(33.0)
COSP = math.cos(PITCH)
SINP = math.sin(PITCH)
XHAT = np.array([1.0, 0.0, 0.0])
UHAT = np.array([0.0, COSP, -SINP])   # Screen UP in world space
WHAT = np.array([0.0, SINP, COSP])    # Toward viewer in world space


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]], dtype=np.float64)


def rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]], dtype=np.float64)


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]], dtype=np.float64)


def basis_from_normal(nz: np.ndarray, up_hint: np.ndarray = np.array([0.0, 1.0, 0.0])) -> np.ndarray:
    """Returns 3x3 rotation matrix whose local Z axis aligns with nz."""
    z = np.asarray(nz, dtype=np.float64)
    z = z / max(float(np.linalg.norm(z)), 1e-9)
    h = np.asarray(up_hint, dtype=np.float64)
    if abs(float(np.dot(z, h))) > 0.94:
        h = np.array([1.0, 0.0, 0.0])
    x = np.cross(h, z)
    x = x / max(float(np.linalg.norm(x)), 1e-9)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def project_pt(p: tuple[float, float, float] | np.ndarray, ax: float, ay: float) -> tuple[float, float]:
    X, Y, Z = float(p[0]), float(p[1]), float(p[2])
    return ax + X, ay - (Y * COSP - Z * SINP)


def shade_band_np(lit: np.ndarray, n_tones: int) -> np.ndarray:
    """Maps illumination (-1..1) crisply to palette indices (0..n_tones-1) without noise."""
    t = np.clip((lit + 0.58) / 1.46, 0.0, 0.9999)
    return np.floor(t * n_tones).astype(np.int32)


def shade_color(mat: int, lit: float) -> tuple[int, int, int, int]:
    pal = PAL_BY_MAT[mat]
    t = clamp((lit + 0.58) / 1.46, 0.0, 0.9999)
    idx = int(t * len(pal))
    return pal[idx]


# ==============================================================================
# 2. VECTORIZED 2D + 3D CANVAS & Z-BUFFER RASTERIZER
# ==============================================================================
class Canvas:
    """RGBA + Glow + Depth + Material + ObjectID raster buffer."""

    def __init__(self, w: int, h: int, ax: float = 0.0, ay: float = 0.0) -> None:
        self.w = w
        self.h = h
        self.ax = ax
        self.ay = ay
        self.px = np.zeros((h, w, 4), dtype=np.uint8)
        self.glow = np.zeros((h, w, 4), dtype=np.uint8)
        self.z = np.full((h, w), -1e9, dtype=np.float32)
        self.mat = np.zeros((h, w), dtype=np.int16)
        self.obj = np.zeros((h, w), dtype=np.int32)
        self.shadow = np.zeros((h, w), dtype=np.uint8)
        self._next_obj = 1

    def new_obj(self) -> int:
        oid = self._next_obj
        self._next_obj += 1
        return oid

    def put_px(
        self,
        x: int,
        y: int,
        col: tuple[int, int, int, int],
        mat: int = MAT_SANDSTONE,
        z: Optional[float] = None,
        oid: int = 0,
        glow_col: Optional[tuple[int, int, int, int]] = None,
    ) -> None:
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        if z is not None and z < float(self.z[y, x]):
            return
        self.px[y, x] = col
        self.mat[y, x] = mat
        if z is not None:
            self.z[y, x] = z
        if oid:
            self.obj[y, x] = oid
        if glow_col is not None and glow_col[3] > 0:
            if glow_col[3] >= int(self.glow[y, x, 3]):
                self.glow[y, x] = glow_col

    def put_glow(self, x: int, y: int, col: tuple[int, int, int], alpha: int) -> None:
        if 0 <= x < self.w and 0 <= y < self.h and alpha > 0:
            if alpha >= int(self.glow[y, x, 3]):
                self.glow[y, x] = (col[0], col[1], col[2], alpha)

    def draw_ground_shadow(self, cx: float, cy: float, rx: float, ry: float, max_alpha: int = 76) -> None:
        x0 = max(1, int(cx - rx) - 1)
        x1 = min(self.w - 1, int(cx + rx) + 2)
        y0 = max(1, int(cy - ry) - 1)
        y1 = min(self.h - 1, int(cy + ry) + 2)
        if x1 <= x0 or y1 <= y0:
            return
        xs = np.arange(x0, x1, dtype=np.float32)[None, :] + 0.5 - cx
        ys = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5 - cy
        d = (xs / max(rx, 1.0)) ** 2 + (ys / max(ry, 1.0)) ** 2
        inside = d <= 1.0
        al = np.clip((1.0 - d) * (max_alpha * 1.15), 24, max_alpha).astype(np.uint8)
        cur = self.shadow[y0:y1, x0:x1]
        self.shadow[y0:y1, x0:x1] = np.where(inside & (al > cur), al, cur)

    def _ray_grid(self, x0: int, x1: int, y0: int, y1: int, ss: int):
        """Returns screen offsets and ray origin world coords o (H*ss, W*ss, 3) for tight bounding box."""
        nx = (x1 - x0) * ss
        ny = (y1 - y0) * ss
        sx = x0 + (np.arange(nx, dtype=np.float64) + 0.5) / ss - self.ax
        sy = self.ay - (y0 + (np.arange(ny, dtype=np.float64) + 0.5) / ss)
        U_g, V_g = np.meshgrid(sx, sy)
        o = U_g[..., None] * XHAT + V_g[..., None] * UHAT
        return o, ny, nx

    def _commit_ss(
        self,
        x0: int,
        x1: int,
        y0: int,
        y1: int,
        ss: int,
        ok: np.ndarray,
        depth: np.ndarray,
        rgba: np.ndarray,
        mat_id: np.ndarray,
        glow_rgba: np.ndarray,
        oid: int,
        min_cov: int,
    ) -> None:
        H_sub = y1 - y0
        W_sub = x1 - x0
        if ss == 1:
            cur_z = self.z[y0:y1, x0:x1]
            win = ok & (depth >= cur_z)
            if not win.any():
                return
            self.z[y0:y1, x0:x1] = np.where(win, depth, cur_z)
            self.px[y0:y1, x0:x1] = np.where(win[..., None], rgba, self.px[y0:y1, x0:x1])
            self.mat[y0:y1, x0:x1] = np.where(win, mat_id, self.mat[y0:y1, x0:x1])
            self.obj[y0:y1, x0:x1] = np.where(win, oid, self.obj[y0:y1, x0:x1])
            g_win = win & (glow_rgba[..., 3] > self.glow[y0:y1, x0:x1, 3])
            self.glow[y0:y1, x0:x1] = np.where(g_win[..., None], glow_rgba, self.glow[y0:y1, x0:x1])
            return

        # SS > 1: reshape to (H_sub, W_sub, ss*ss) and pick crisp representative subpixel
        ok_b = ok.reshape(H_sub, ss, W_sub, ss).transpose(0, 2, 1, 3).reshape(H_sub, W_sub, ss * ss)
        cov = ok_b.sum(axis=-1)
        solid = cov >= min_cov
        if not solid.any():
            return
        d_b = depth.reshape(H_sub, ss, W_sub, ss).transpose(0, 2, 1, 3).reshape(H_sub, W_sub, ss * ss)
        d_masked = np.where(ok_b, d_b, -1e9)
        mean_d = np.where(solid, np.where(ok_b, d_b, 0.0).sum(axis=-1) / np.maximum(cov, 1), -1e9)

        # Prefer center subpixel if solid, else frontmost valid subpixel
        mid = (ss * ss) // 2
        best_idx = np.argmax(d_masked, axis=-1)
        use_mid = ok_b[..., mid]
        pick_idx = np.where(use_mid, mid, best_idx)

        rows_g = np.arange(H_sub)[:, None]
        cols_g = np.arange(W_sub)[None, :]

        rgba_b = rgba.reshape(H_sub, ss, W_sub, ss, 4).transpose(0, 2, 1, 3, 4).reshape(H_sub, W_sub, ss * ss, 4)
        mat_b = mat_id.reshape(H_sub, ss, W_sub, ss).transpose(0, 2, 1, 3).reshape(H_sub, W_sub, ss * ss)
        glow_b = glow_rgba.reshape(H_sub, ss, W_sub, ss, 4).transpose(0, 2, 1, 3, 4).reshape(H_sub, W_sub, ss * ss, 4)

        px_pick = rgba_b[rows_g, cols_g, pick_idx]
        mat_pick = mat_b[rows_g, cols_g, pick_idx]

        # If any subpixel has bright glow, preserve crisp 1px glow line rather than dropping it
        g_alpha = np.where(ok_b, glow_b[..., 3], 0)
        has_g = g_alpha.max(axis=-1) > 0
        g_pick_idx = np.where(has_g, np.argmax(g_alpha, axis=-1), pick_idx)
        glow_pick = glow_b[rows_g, cols_g, g_pick_idx]
        # When an emissive feature hits a pixel, ensure the base pixel also reflects the bright emissive color
        px_pick = np.where((has_g & (glow_b[rows_g, cols_g, g_pick_idx, 3] >= 120))[..., None],
                           np.concatenate([glow_pick[..., :3], np.full((H_sub, W_sub, 1), 255, dtype=np.uint8)], axis=-1),
                           px_pick)

        cur_z = self.z[y0:y1, x0:x1]
        win = solid & (mean_d >= cur_z)
        if not win.any():
            return
        self.z[y0:y1, x0:x1] = np.where(win, mean_d, cur_z)
        self.px[y0:y1, x0:x1] = np.where(win[..., None], px_pick, self.px[y0:y1, x0:x1])
        self.mat[y0:y1, x0:x1] = np.where(win, mat_pick, self.mat[y0:y1, x0:x1])
        self.obj[y0:y1, x0:x1] = np.where(win, oid, self.obj[y0:y1, x0:x1])
        g_win = win & (glow_pick[..., 3] > self.glow[y0:y1, x0:x1, 3])
        self.glow[y0:y1, x0:x1] = np.where(g_win[..., None], glow_pick, self.glow[y0:y1, x0:x1])

    def render_ring_band(
        self,
        center: tuple[float, float, float],
        R: np.ndarray,
        r_in: float,
        r_out: float,
        half_h: float,
        mat: int,
        paint_fn: Optional[Callable] = None,
        ss: int = 3,
        arc_clip: Optional[Callable] = None,
        margin: int = 2,
    ) -> int:
        """Exact analytic 3D raycast of a flat-beveled hollow cylinder ring band!"""
        c = np.asarray(center, dtype=np.float64)
        cx, cy = project_pt(c, self.ax, self.ay)
        rad = r_out + half_h + 4.0
        x0 = max(margin, int(math.floor(cx - rad)))
        x1 = min(self.w - margin, int(math.ceil(cx + rad)) + 1)
        y0 = max(margin, int(math.floor(cy - rad)))
        y1 = min(self.h - margin, int(math.ceil(cy + rad)) + 1)
        if x1 <= x0 or y1 <= y0:
            return 0
        oid = self.new_obj()
        o, ny, nx = self._ray_grid(x0, x1, y0, y1, ss)
        Rt = R.T
        p0 = (o - c) @ R  # local coords of ray origin
        d = WHAT @ R      # local ray direction (constant 3-vec)

        best_t = np.full((ny, nx), -1e9, dtype=np.float64)
        best_n_loc = np.zeros((ny, nx, 3), dtype=np.float64)
        best_pos = np.zeros((ny, nx, 3), dtype=np.float64)
        best_face = np.zeros((ny, nx), dtype=np.int8)  # 0=top, 1=bot, 2=outer, 3=inner

        def consider(t_cand: np.ndarray, valid: np.ndarray, n_loc: np.ndarray, face_id: int) -> None:
            nonlocal best_t, best_n_loc, best_pos, best_face
            p_hit = p0 + t_cand[..., None] * d
            if arc_clip is not None:
                valid = valid & arc_clip(p_hit)
            win = valid & (t_cand > best_t)
            if not win.any():
                return
            best_t = np.where(win, t_cand, best_t)
            best_pos = np.where(win[..., None], p_hit, best_pos)
            best_n_loc = np.where(win[..., None], n_loc, best_n_loc)
            best_face = np.where(win, face_id, best_face)

        # 1. Top and bottom cap planes z = +half_h, -half_h
        if abs(d[2]) > 1e-6:
            for sz, fid in ((1.0, 0), (-1.0, 1)):
                tc = (sz * half_h - p0[..., 2]) / d[2]
                px_h = p0[..., 0] + tc * d[0]
                py_h = p0[..., 1] + tc * d[1]
                r2 = px_h * px_h + py_h * py_h
                val = (r2 >= r_in * r_in) & (r2 <= r_out * r_out)
                nl = np.broadcast_to(np.array([0.0, 0.0, sz]), p0.shape)
                consider(tc, val, nl, fid)

        # 2. Outer and inner cylinder walls
        a = d[0] * d[0] + d[1] * d[1]
        if a > 1e-8:
            b = p0[..., 0] * d[0] + p0[..., 1] * d[1]
            for rad_c, n_sign, fid in ((r_out, 1.0, 2), (r_in, -1.0, 3)):
                cc = p0[..., 0] ** 2 + p0[..., 1] ** 2 - rad_c * rad_c
                disc = b * b - a * cc
                ok_d = disc >= 0.0
                sq = np.sqrt(np.where(ok_d, disc, 0.0))
                for sign_r in (1.0, -1.0):
                    tc = (-b + sign_r * sq) / a
                    pz_h = p0[..., 2] + tc * d[2]
                    val = ok_d & (np.abs(pz_h) <= half_h)
                    px_h = p0[..., 0] + tc * d[0]
                    py_h = p0[..., 1] + tc * d[1]
                    nl = np.stack([px_h * (n_sign / max(rad_c, 1e-6)), py_h * (n_sign / max(rad_c, 1e-6)), np.zeros_like(px_h)], axis=-1)
                    consider(tc, val, nl, fid)

        ok = best_t > -1e8
        if not ok.any():
            return oid

        n_world = best_n_loc @ Rt
        n_world /= np.maximum(np.linalg.norm(n_world, axis=-1, keepdims=True), 1e-9)
        lit = n_world @ L_3D

        pal = np.array(PAL_BY_MAT[mat], dtype=np.uint8)
        bands = shade_band_np(lit, len(pal))
        # Subtle edge bevel boost on upper/outer edges
        r_xy = np.hypot(best_pos[..., 0], best_pos[..., 1])
        bevel = (np.abs(best_pos[..., 2]) > half_h * 0.72) | (np.abs(r_xy - r_out) < 0.75) | (np.abs(r_xy - r_in) < 0.75)
        bands = np.where(bevel & (lit > 0.1), np.minimum(bands + 1, len(pal) - 1), bands)
        bands = np.where((best_face == 3) & (lit < 0.0), np.maximum(bands - 1, 0), bands)

        rgba = pal[bands]
        mat_arr = np.full((ny, nx), mat, dtype=np.int16)
        glow_rgba = np.zeros((ny, nx, 4), dtype=np.uint8)

        if paint_fn is not None:
            paint_fn(ok, best_pos, best_n_loc, best_face, lit, rgba, mat_arr, glow_rgba)

        self._commit_ss(x0, x1, y0, y1, ss, ok, best_t, rgba, mat_arr, glow_rgba, oid, min_cov=(ss * ss + 1) // 2)
        return oid

    def render_ellipsoid(
        self,
        center: tuple[float, float, float],
        radii: tuple[float, float, float],
        mat: int,
        R: Optional[np.ndarray] = None,
        paint_fn: Optional[Callable] = None,
        ss: int = 2,
        clip_fn: Optional[Callable] = None,
        margin: int = 2,
    ) -> int:
        c = np.asarray(center, dtype=np.float64)
        r = np.asarray(radii, dtype=np.float64)
        R = np.eye(3) if R is None else R
        cx, cy = project_pt(c, self.ax, self.ay)
        rr = float(r.max()) + 3.0
        x0 = max(margin, int(math.floor(cx - rr)))
        x1 = min(self.w - margin, int(math.ceil(cx + rr)) + 1)
        y0 = max(margin, int(math.floor(cy - rr)))
        y1 = min(self.h - margin, int(math.ceil(cy + rr)) + 1)
        if x1 <= x0 or y1 <= y0:
            return 0
        oid = self.new_obj()
        o, ny, nx = self._ray_grid(x0, x1, y0, y1, ss)
        M = np.diag(1.0 / r) @ R.T
        q0 = (o - c) @ M.T
        qd = M @ WHAT
        aa = float(qd @ qd)
        bb = q0 @ qd
        cc = (q0 * q0).sum(axis=-1) - 1.0
        disc = bb * bb - aa * cc
        ok = disc >= 0.0
        t = (-bb + np.sqrt(np.where(ok, disc, 0.0))) / aa
        q = q0 + t[..., None] * qd
        if clip_fn is not None:
            ok &= clip_fn(q)
        if not ok.any():
            return oid
        n_world = (q / r) @ R.T
        n_world /= np.maximum(np.linalg.norm(n_world, axis=-1, keepdims=True), 1e-9)
        lit = n_world @ L_3D
        pal = np.array(PAL_BY_MAT[mat], dtype=np.uint8)
        bands = shade_band_np(lit, len(pal))
        rgba = pal[bands]
        mat_arr = np.full((ny, nx), mat, dtype=np.int16)
        glow_rgba = np.zeros((ny, nx, 4), dtype=np.uint8)
        if paint_fn is not None:
            paint_fn(ok, q, n_world, lit, rgba, mat_arr, glow_rgba)
        self._commit_ss(x0, x1, y0, y1, ss, ok, t, rgba, mat_arr, glow_rgba, oid, min_cov=max(1, (ss * ss) // 2))
        return oid

    def render_facet_crystal(
        self,
        center: tuple[float, float, float],
        R: np.ndarray,
        rx: float,
        ry_top: float,
        ry_bot: float,
        n_sides: int = 6,
        glow_mode: str = "turq",
        ss: int = 3,
        margin: int = 2,
    ) -> int:
        """Crisp faceted bipyramid/hexagonal quartz crystal with glowing core in *_glow.png."""
        c = np.asarray(center, dtype=np.float64)
        cx, cy = project_pt(c, self.ax, self.ay)
        rad = max(rx, ry_top, ry_bot) + 3.0
        x0 = max(margin, int(math.floor(cx - rad)))
        x1 = min(self.w - margin, int(math.ceil(cx + rad)) + 1)
        y0 = max(margin, int(math.floor(cy - rad)))
        y1 = min(self.h - margin, int(math.ceil(cy + rad)) + 1)
        if x1 <= x0 or y1 <= y0:
            return 0
        oid = self.new_obj()
        o, ny, nx = self._ray_grid(x0, x1, y0, y1, ss)
        p0 = (o - c) @ R
        d = WHAT @ R

        # Convex polyhedron defined by planes: for each side k and top/bot half
        planes_n = []
        planes_d = []
        cos_mid = math.cos(math.pi / n_sides)
        for k in range(n_sides):
            ang = (k + 0.5) * (math.tau / n_sides)
            nx_p, nz_p = math.cos(ang), math.sin(ang)
            for slope_y, h_y in ((1.0, ry_top), (-1.0, ry_bot)):
                # Plane passes through (rx*cos_mid*nx_p, 0, rx*cos_mid*nz_p) and (0, slope_y*h_y, 0)
                raw = np.array([nx_p / (rx * cos_mid), slope_y / h_y, nz_p / (rx * cos_mid)], dtype=np.float64)
                nm = float(np.linalg.norm(raw))
                planes_n.append(raw / nm)
                planes_d.append(1.0 / nm)

        t_enter = np.full((ny, nx), -1e9, dtype=np.float64)
        t_exit = np.full((ny, nx), 1e9, dtype=np.float64)
        hit_n = np.zeros((ny, nx, 3), dtype=np.float64)

        for pn, pd in zip(planes_n, planes_d):
            denom = float(np.dot(pn, d))
            num = pd - np.sum(p0 * pn, axis=-1)
            if abs(denom) < 1e-8:
                bad = num < 0
                t_enter = np.where(bad, 1e9, t_enter)
            else:
                t_p = num / denom
                if denom < 0:
                    # Exiting in backward-ray sense, entering along +WHAT!
                    # Wait: as t increases (moving toward viewer), p*pn = pd.
                    # If denom > 0, moving +t increases p*pn -> t is UPPER bound (exit)!
                    # If denom < 0, moving +t decreases p*pn -> t is LOWER bound (enter)!
                    t_enter = np.maximum(t_enter, t_p)
                else:
                    win_exit = t_p < t_exit
                    t_exit = np.where(win_exit, t_p, t_exit)
                    hit_n = np.where(win_exit[..., None], pn, hit_n)

        ok = t_exit >= t_enter
        if not ok.any():
            return oid

        p_hit = p0 + t_exit[..., None] * d
        n_world = hit_n @ R.T
        lit = n_world @ L_3D
        pal = np.array(QUARTZ_W, dtype=np.uint8)
        bands = shade_band_np(lit, len(pal))
        # Crisp ridge highlights along crystal edges
        r_rad = np.hypot(p_hit[..., 0], p_hit[..., 2])
        is_ridge = (np.abs(p_hit[..., 1]) < 0.85) | (r_rad < rx * 0.25)
        bands = np.where(is_ridge & (lit > 0.0), 5, bands)
        rgba = pal[bands]
        mat_arr = np.full((ny, nx), MAT_QUARTZ, dtype=np.int16)
        glow_rgba = np.zeros((ny, nx, 4), dtype=np.uint8)

        core = (np.abs(p_hit[..., 1]) < min(ry_top, ry_bot) * 0.58) & (r_rad < rx * 0.72)
        if glow_mode == "turq":
            gc_hi = np.array(TURQ[3], dtype=np.uint8)
            gc_mid = np.array(TURQ[2], dtype=np.uint8)
            glow_rgba = np.where((core & (bands >= 4))[..., None], (gc_hi[0], gc_hi[1], gc_hi[2], 220), glow_rgba)
            glow_rgba = np.where((core & (bands < 4))[..., None], (gc_mid[0], gc_mid[1], gc_mid[2], 175), glow_rgba)
            rgba = np.where(core[..., None], np.where((bands >= 4)[..., None], gc_hi, gc_mid), rgba)
        elif glow_mode == "solar":
            gc_hi = np.array(SOLAR[2], dtype=np.uint8)
            gc_mid = np.array(SOLAR[1], dtype=np.uint8)
            glow_rgba = np.where((core & (bands >= 4))[..., None], (gc_hi[0], gc_hi[1], gc_hi[2], 225), glow_rgba)
            glow_rgba = np.where((core & (bands < 4))[..., None], (gc_mid[0], gc_mid[1], gc_mid[2], 180), glow_rgba)
            rgba = np.where(core[..., None], np.where((bands >= 4)[..., None], gc_hi, gc_mid), rgba)
        elif glow_mode == "prism":
            # Crisp diagonal dispersion bands: turq, astral violet, solar gold
            diag = (p_hit[..., 1] / max(ry_top, 1.0) + p_hit[..., 0] / max(rx, 1.0) * 0.5)
            m_t = diag > 0.22
            m_v = (diag <= 0.22) & (diag > -0.22)
            m_g = diag <= -0.22
            for mask_c, col_rgb, alp in (
                (m_t, TURQ[2][:3], 185),
                (m_v, ASTRAL[1][:3], 185),
                (m_g, SOLAR[1][:3], 180),
            ):
                active = ok & mask_c & (bands >= 2)
                rgba = np.where(active[..., None], (*col_rgb, 255), rgba)
                glow_rgba = np.where(active[..., None], (*col_rgb, alp), glow_rgba)
            tip_glint = ok & (bands == 5)
            glow_rgba = np.where(tip_glint[..., None], (*TURQ[3][:3], 210), glow_rgba)

        self._commit_ss(x0, x1, y0, y1, ss, ok, t_exit, rgba, mat_arr, glow_rgba, oid, min_cov=max(1, (ss * ss) // 2))
        return oid

    def render_cylinder(
        self,
        p_a: tuple[float, float, float],
        p_b: tuple[float, float, float],
        r_a: float,
        r_b: float,
        mat: int,
        ss: int = 2,
        paint_fn: Optional[Callable] = None,
        margin: int = 2,
    ) -> int:
        """Frustum/cylinder segment between p_a and p_b (for spire masts, telescope barrels, pillars)."""
        pa = np.asarray(p_a, dtype=np.float64)
        pb = np.asarray(p_b, dtype=np.float64)
        axis = pb - pa
        length = float(np.linalg.norm(axis))
        if length < 0.5:
            return 0
        ey = axis / length
        R = basis_from_normal(np.array([0.0, 0.0, 1.0]) if abs(ey[2]) < 0.9 else np.array([1.0, 0.0, 0.0]), up_hint=ey)
        # Build orthonormal frame with column 1 = ey
        hint = np.array([0.0, 0.0, 1.0]) if abs(ey[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        ex = np.cross(ey, hint)
        ex /= np.linalg.norm(ex)
        ez = np.cross(ex, ey)
        R = np.stack([ex, ey, ez], axis=1)

        ax0, ay0 = project_pt(pa, self.ax, self.ay)
        ax1, ay1 = project_pt(pb, self.ax, self.ay)
        pad = max(r_a, r_b) + 3.0
        x0 = max(margin, int(math.floor(min(ax0, ax1) - pad)))
        x1 = min(self.w - margin, int(math.ceil(max(ax0, ax1) + pad)) + 1)
        y0 = max(margin, int(math.floor(min(ay0, ay1) - pad)))
        y1 = min(self.h - margin, int(math.ceil(max(ay0, ay1) + pad)) + 1)
        if x1 <= x0 or y1 <= y0:
            return 0
        oid = self.new_obj()
        o, ny, nx = self._ray_grid(x0, x1, y0, y1, ss)
        p0 = (o - pa) @ R
        d = WHAT @ R

        # Ray-cone / tapered cylinder along local y in [0, length]
        # Radius(y) = r_a + s * y where s = (r_b - r_a) / length
        s = (r_b - r_a) / length
        qa = d[0] * d[0] + d[2] * d[2] - (s * d[1]) ** 2
        rad_0 = r_a + s * p0[..., 1]
        qb = p0[..., 0] * d[0] + p0[..., 2] * d[2] - rad_0 * (s * d[1])
        qc = p0[..., 0] ** 2 + p0[..., 2] ** 2 - rad_0 ** 2

        best_t = np.full((ny, nx), -1e9, dtype=np.float64)
        best_n = np.zeros((ny, nx, 3), dtype=np.float64)
        best_p = np.zeros((ny, nx, 3), dtype=np.float64)

        if abs(qa) > 1e-8:
            disc = qb * qb - qa * qc
            ok_d = disc >= 0.0
            sq = np.sqrt(np.where(ok_d, disc, 0.0))
            for sr in (1.0, -1.0):
                tc = (-qb + sr * sq) / qa
                ph = p0 + tc[..., None] * d
                val = ok_d & (ph[..., 1] >= 0.0) & (ph[..., 1] <= length)
                # Ensure outward normal
                nl = np.stack([ph[..., 0], -s * (r_a + s * ph[..., 1]), ph[..., 2]], axis=-1)
                nl /= np.maximum(np.linalg.norm(nl, axis=-1, keepdims=True), 1e-9)
                win = val & (tc > best_t) & (np.sum(nl * d, axis=-1) > -0.1)
                best_t = np.where(win, tc, best_t)
                best_p = np.where(win[..., None], ph, best_p)
                best_n = np.where(win[..., None], nl, best_n)

        # Cap discs at y=0 and y=length
        if abs(d[1]) > 1e-6:
            for yc, rc, ny_s in ((0.0, r_a, -1.0), (length, r_b, 1.0)):
                tc = (yc - p0[..., 1]) / d[1]
                ph = p0 + tc[..., None] * d
                val = (ph[..., 0] ** 2 + ph[..., 2] ** 2) <= rc * rc
                nl = np.broadcast_to(np.array([0.0, ny_s, 0.0]), ph.shape)
                win = val & (tc > best_t)
                best_t = np.where(win, tc, best_t)
                best_p = np.where(win[..., None], ph, best_p)
                best_n = np.where(win[..., None], nl, best_n)

        ok = best_t > -1e8
        if not ok.any():
            return oid
        n_world = best_n @ R.T
        n_world /= np.maximum(np.linalg.norm(n_world, axis=-1, keepdims=True), 1e-9)
        lit = n_world @ L_3D
        pal = np.array(PAL_BY_MAT[mat], dtype=np.uint8)
        bands = shade_band_np(lit, len(pal))
        rgba = pal[bands]
        mat_arr = np.full((ny, nx), mat, dtype=np.int16)
        glow_rgba = np.zeros((ny, nx, 4), dtype=np.uint8)
        if paint_fn is not None:
            paint_fn(ok, best_p, best_n, lit, rgba, mat_arr, glow_rgba)
        self._commit_ss(x0, x1, y0, y1, ss, ok, best_t, rgba, mat_arr, glow_rgba, oid, min_cov=max(1, (ss * ss) // 2))
        return oid

    def finalize_with_outlines(
        self,
        foot_cut_y: Optional[int] = None,
        add_internal_creases: bool = True,
        halo_alpha: float = 0.26,
        halo_max_y: Optional[int] = None,
    ) -> tuple[list[list[tuple[int, int, int, int]]], list[list[tuple[int, int, int, int]]]]:
        """Applies crisp 1px material-tinted outlines, internal depth creases, and subtle glow halo."""
        h, w = self.h, self.w
        solid = self.px[..., 3] == 255
        out_px = self.px.copy()

        # 1. Internal depth creases between distinct overlapping foreground/background objects
        if add_internal_creases:
            crease = np.zeros((h, w), dtype=bool)
            for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                nb_z = np.roll(np.roll(self.z, dy, 0), dx, 1)
                nb_s = np.roll(np.roll(solid, dy, 0), dx, 1)
                nb_o = np.roll(np.roll(self.obj, dy, 0), dx, 1)
                diff_obj = (self.obj > 0) & (nb_o > 0) & (self.obj != nb_o)
                crease |= solid & nb_s & diff_obj & (nb_z > self.z + 3.2)
            # Only darken non-emissive non-sand pixels to their darkest material shade
            ys_c, xs_c = np.nonzero(crease)
            for y, x in zip(ys_c, xs_c):
                if self.glow[y, x, 3] > 0:
                    continue
                m = int(self.mat[y, x])
                if m in (MAT_SANDSTONE, MAT_INDIGO, MAT_GOLD, MAT_QUARTZ):
                    out_px[y, x] = PAL_BY_MAT[m][0]

        # 2. 1px adaptive tinted outer silhouette contour (zero #000000; skip drifted sand edges!)
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if solid[y, x]:
                    continue
                nb_mats = []
                sand_cnt = 0
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if solid[ny, nx]:
                        m = int(self.mat[ny, nx])
                        nb_mats.append(m)
                        if m == MAT_SAND:
                            sand_cnt += 1
                if not nb_mats or sand_cnt == len(nb_mats):
                    continue
                if foot_cut_y is not None and y >= foot_cut_y + 2 and not solid[y - 1, x]:
                    continue
                # Priority ink selection from neighboring non-sand material
                non_sand = [m for m in nb_mats if m != MAT_SAND]
                chosen = non_sand[0] if non_sand else MAT_SANDSTONE
                ink = INK_BY_MAT.get(chosen)
                if ink is not None:
                    out_px[y, x] = ink

        # 3. Soft translucent warm plum ground contact shadow underneath (never 0,0,0!)
        for y in range(h):
            for x in range(w):
                if out_px[y, x, 3] == 0 and self.shadow[y, x] > 0:
                    out_px[y, x] = (*SHADOW_TINT, int(self.shadow[y, x]))

        # 4. Crisp 1px unshaded glow halo around bright emissive cores
        out_glow = self.glow.copy()
        if halo_alpha > 0.0:
            ymax = h - 1 if halo_max_y is None else min(h - 1, halo_max_y)
            snap = self.glow.copy()
            for y in range(1, ymax):
                for x in range(1, w - 1):
                    c = snap[y, x]
                    if int(c[3]) < 145:
                        continue
                    ha = int(c[3] * halo_alpha)
                    if ha < 22:
                        continue
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        nx, ny = x + dx, y + dy
                        if int(out_glow[ny, nx, 3]) < ha:
                            out_glow[ny, nx] = (c[0], c[1], c[2], ha)

        return (
            [[tuple(int(v) for v in out_px[y, x]) for x in range(w)] for y in range(h)],
            [[tuple(int(v) for v in out_glow[y, x]) for x in range(w)] for y in range(h)],
        )


# ==============================================================================
# 2B. TRUE 3D CSG & HEIGHTFIELD RAYCAST ENGINE WITH CAST SHADOWS & AO
# ==============================================================================
def sd_box(p: np.ndarray, c: tuple[float, float, float], b: tuple[float, float, float], r: float = 0.22) -> np.ndarray:
    cx, cy, cz = c
    bx, by, bz = max(b[0] - r, 0.05), max(b[1] - r, 0.05), max(b[2] - r, 0.05)
    qx = np.abs(p[..., 0] - cx) - bx
    qy = np.abs(p[..., 1] - cy) - by
    qz = np.abs(p[..., 2] - cz) - bz
    ox = np.maximum(qx, 0.0)
    oy = np.maximum(qy, 0.0)
    oz = np.maximum(qz, 0.0)
    return np.sqrt(ox * ox + oy * oy + oz * oz) + np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0) - r


def sd_cyl_y(p: np.ndarray, c: tuple[float, float, float], r: float, hh: float, bevel: float = 0.20) -> np.ndarray:
    cx, cy, cz = c
    rx = max(r - bevel, 0.05)
    hy = max(hh - bevel, 0.05)
    dxz = np.hypot(p[..., 0] - cx, p[..., 2] - cz) - rx
    dy = np.abs(p[..., 1] - cy) - hy
    return np.hypot(np.maximum(dxz, 0.0), np.maximum(dy, 0.0)) + np.minimum(np.maximum(dxz, dy), 0.0) - bevel


def sd_cyl_z(p: np.ndarray, c: tuple[float, float, float], r: float, hz: float, bevel: float = 0.20) -> np.ndarray:
    cx, cy, cz = c
    rx = max(r - bevel, 0.05)
    hzz = max(hz - bevel, 0.05)
    dxy = np.hypot(p[..., 0] - cx, p[..., 1] - cy) - rx
    dz = np.abs(p[..., 2] - cz) - hzz
    return np.hypot(np.maximum(dxy, 0.0), np.maximum(dz, 0.0)) + np.minimum(np.maximum(dxy, dz), 0.0) - bevel


def sd_oct_y(p: np.ndarray, c: tuple[float, float, float], r: float, hh: float, bevel: float = 0.20) -> np.ndarray:
    cx, cy, cz = c
    rx = max(r - bevel, 0.05)
    hy = max(hh - bevel, 0.05)
    qx = np.abs(p[..., 0] - cx)
    qz = np.abs(p[..., 2] - cz)
    m = np.maximum(np.maximum(qx, qz), (qx + qz) * 0.70710678) - rx
    dy = np.abs(p[..., 1] - cy) - hy
    return np.hypot(np.maximum(m, 0.0), np.maximum(dy, 0.0)) + np.minimum(np.maximum(m, dy), 0.0) - bevel


def sd_ring_y(p: np.ndarray, c: tuple[float, float, float], r_in: float, r_out: float, hh: float, bevel: float = 0.16) -> np.ndarray:
    cx, cy, cz = c
    rr = np.hypot(p[..., 0] - cx, p[..., 2] - cz)
    dr = np.maximum(rr - (r_out - bevel), (r_in + bevel) - rr)
    dy = np.abs(p[..., 1] - cy) - max(hh - bevel, 0.05)
    return np.hypot(np.maximum(dr, 0.0), np.maximum(dy, 0.0)) + np.minimum(np.maximum(dr, dy), 0.0) - bevel


def sd_arch_tunnel_z(
    p: np.ndarray,
    cx: float,
    y_bot: float,
    y_spring: float,
    r_arch: float,
    cz: float,
    hz: float,
) -> np.ndarray:
    dx = np.abs(p[..., 0] - cx)
    dy_up = np.maximum(p[..., 1] - y_spring, 0.0)
    d_xy = np.maximum(np.hypot(dx, dy_up) - r_arch, y_bot - p[..., 1])
    dz = np.abs(p[..., 2] - cz) - hz
    return np.hypot(np.maximum(d_xy, 0.0), np.maximum(dz, 0.0)) + np.minimum(np.maximum(d_xy, dz), 0.0)


def ashlar_shade_3d(
    u_horiz: np.ndarray,
    v_vert: np.ndarray,
    lit_eff: np.ndarray,
    mat_id: int = MAT_SANDSTONE,
    course_h: float = 6.5,
    block_w: float = 12.0,
    seed: int = 11,
    has_mortar: bool = True,
) -> np.ndarray:
    """Crisp faceted 3D ashlar masonry shader with staggered courses, 1px mortar joints,
    top course bevel highlights, and deterministic per-block value variation (zero speckles!)."""
    pal = np.array(PAL_BY_MAT[mat_id], dtype=np.uint8)
    row = np.floor(v_vert / course_h).astype(np.int32)
    ly = v_vert - row * course_h
    stagger = (row & 1) * (block_w * 0.5)
    u_s = u_horiz + stagger
    col = np.floor(u_s / block_w).astype(np.int32)
    lx = u_s - col * block_w

    bh = (((col * 73 + row * 139 + seed * 31) & 15).astype(np.float64) / 15.0) - 0.5
    bands = shade_band_np(lit_eff + bh * 0.20, len(pal))
    if has_mortar:
        joint = (ly < 0.85) | (lx < 0.85)
        bands = np.where(joint, np.where(lit_eff > 0.45, 1, 0), bands)
        lip = (~joint) & (ly >= 0.85) & (ly < 1.80) & (lit_eff > 0.05)
        bands = np.where(lip, np.minimum(bands + 1, len(pal) - 1), bands)
    return pal[bands]


def render_csg(
    cv: Canvas,
    bbox_screen: tuple[int, int, int, int],
    t_range: tuple[float, float],
    sdf_fn: Callable[[np.ndarray], tuple[np.ndarray, np.ndarray]],
    paint_fn: Callable,
    ss: int = 2,
    n_steps: int = 62,
    shadow_steps: int = 16,
    margin: int = 2,
) -> int:
    """Vectorized sphere-traced 3D CSG renderer with directional cast shadows + crevice AO."""
    x0 = max(margin, bbox_screen[0])
    x1 = min(cv.w - margin, bbox_screen[1])
    y0 = max(margin, bbox_screen[2])
    y1 = min(cv.h - margin, bbox_screen[3])
    if x1 <= x0 or y1 <= y0:
        return 0

    oid = cv.new_obj()
    o, ny, nx = cv._ray_grid(x0, x1, y0, y1, ss)
    o_flat = o.reshape(-1, 3)
    N = o_flat.shape[0]
    t_min, t_max = float(t_range[0]), float(t_range[1])

    t = np.full(N, t_max, dtype=np.float64)
    active = np.arange(N, dtype=np.int32)
    d_last = np.full(N, 1e9, dtype=np.float64)

    for _ in range(n_steps):
        if active.size == 0:
            break
        p_act = o_flat[active] + t[active, None] * WHAT
        d_act, _ = sdf_fn(p_act)
        d_last[active] = d_act
        keep = (d_act > 0.03) & (t[active] - d_act * 0.72 >= t_min)
        if not keep.any():
            break
        act_keep = active[keep]
        t[act_keep] -= np.maximum(d_act[keep] * 0.72, 0.025)
        active = act_keep

    hit_mask = (d_last <= 0.08) & (t >= t_min) & (t <= t_max)
    if not hit_mask.any():
        return oid

    h_idx = np.nonzero(hit_mask)[0]
    ph = o_flat[h_idx] + t[h_idx, None] * WHAT
    _, tag_h = sdf_fn(ph)

    # Central-difference 3D normals on hit surface
    eps = 0.09
    ex = np.array([eps, 0.0, 0.0])
    ey = np.array([0.0, eps, 0.0])
    ez = np.array([0.0, 0.0, eps])
    gx = sdf_fn(ph + ex)[0] - sdf_fn(ph - ex)[0]
    gy = sdf_fn(ph + ey)[0] - sdf_fn(ph - ey)[0]
    gz = sdf_fn(ph + ez)[0] - sdf_fn(ph - ez)[0]
    nh = np.stack([gx, gy, gz], axis=-1)
    nh /= np.maximum(np.linalg.norm(nh, axis=-1, keepdims=True), 1e-9)

    # Local Crevice AO (2 short probes along surface normal)
    d_ao1, _ = sdf_fn(ph + nh * 1.1)
    d_ao2, _ = sdf_fn(ph + nh * 2.6)
    ao_h = np.clip((d_ao1 / 1.1) * 0.55 + (d_ao2 / 2.6) * 0.45, 0.25, 1.0)

    # Directional Cast Shadow Ray along +L_3D for front-lit surfaces
    lit_raw = nh @ L_3D
    sun_vis_h = np.where(lit_raw > 0.02, 1.0, 0.0)
    sh_need = np.nonzero(lit_raw > 0.02)[0]
    if sh_need.size > 0:
        p_sh0 = ph[sh_need] + nh[sh_need] * 0.35
        ts = np.full(sh_need.size, 0.55, dtype=np.float64)
        min_occ = np.full(sh_need.size, 1e9, dtype=np.float64)
        sh_act = np.arange(sh_need.size, dtype=np.int32)
        for _ in range(shadow_steps):
            if sh_act.size == 0:
                break
            ps = p_sh0[sh_act] + ts[sh_act, None] * L_3D
            ds, _ = sdf_fn(ps)
            min_occ[sh_act] = np.minimum(min_occ[sh_act], ds)
            alive = (ds >= 0.05) & (ts[sh_act] < 24.0)
            if not alive.any():
                break
            sh_act = sh_act[alive]
            ts[sh_act] += np.clip(ds[alive] * 0.80, 0.45, 2.6)
        # Crisp stepped shadow occlusion (softly hardened near contact)
        occl = np.where(min_occ < 0.06, 0.0, np.where(min_occ < 0.28, 0.50, 1.0))
        sun_vis_h[sh_need] = occl

    rgba_h, mat_h, glow_h = paint_fn(ph, nh, tag_h, sun_vis_h, ao_h)

    ok_2d = hit_mask.reshape(ny, nx)
    depth_2d = np.where(ok_2d, t.reshape(ny, nx), -1e9)
    rgba_2d = np.zeros((ny * nx, 4), dtype=np.uint8)
    mat_2d = np.zeros(ny * nx, dtype=np.int16)
    glow_2d = np.zeros((ny * nx, 4), dtype=np.uint8)
    rgba_2d[h_idx] = rgba_h
    mat_2d[h_idx] = mat_h
    glow_2d[h_idx] = glow_h

    cv._commit_ss(
        x0,
        x1,
        y0,
        y1,
        ss,
        ok_2d,
        depth_2d,
        rgba_2d.reshape(ny, nx, 4),
        mat_2d.reshape(ny, nx),
        glow_2d.reshape(ny, nx, 4),
        oid,
        min_cov=max(1, (ss * ss + 1) // 2),
    )
    return oid


def render_heightfield(
    cv: Canvas,
    bbox_screen: tuple[int, int, int, int],
    h_max: float,
    h_min: float,
    hf_fn: Callable[[np.ndarray, np.ndarray], tuple[np.ndarray, np.ndarray]],
    paint_fn: Callable,
    ss: int = 2,
    n_coarse: int = 56,
    margin: int = 2,
) -> int:
    """Vectorized 3D stepped terrace/wall raycaster against Y_up = hf_fn(X, Z) with cast shadows & AO."""
    x0 = max(margin, bbox_screen[0])
    x1 = min(cv.w - margin, bbox_screen[1])
    y0 = max(margin, bbox_screen[2])
    y1 = min(cv.h - margin, bbox_screen[3])
    if x1 <= x0 or y1 <= y0:
        return 0

    oid = cv.new_obj()
    o, ny, nx = cv._ray_grid(x0, x1, y0, y1, ss)
    o_flat = o.reshape(-1, 3)
    N = o_flat.shape[0]
    ox, oy, oz = o_flat[..., 0], o_flat[..., 1], o_flat[..., 2]

    t_top = (h_max + 0.15 - oy) / SINP
    t_bot = (h_min - 0.15 - oy) / SINP

    ts_frac = np.linspace(0.0, 1.0, n_coarse)
    best_t = np.full(N, -1e9, dtype=np.float64)
    prev_t = t_top.copy()
    hit = np.zeros(N, dtype=bool)

    for s_i in range(n_coarse):
        tc = t_top * (1.0 - ts_frac[s_i]) + t_bot * ts_frac[s_i]
        px = ox
        py = oy + tc * SINP
        pz = oz + tc * COSP
        h_val, _ = hf_fn(px, pz)
        below = (py <= h_val) & (h_val > h_min + 0.05) & (~hit)
        if below.any():
            hit |= below
            best_t = np.where(below, tc, best_t)
            # Track bracketing lower/upper t in prev_t / best_t
        if not below.any():
            prev_t = np.where(~hit, tc, prev_t)
        else:
            prev_t = np.where(~hit & ~below, tc, prev_t)

    if not hit.any():
        return oid

    h_idx = np.nonzero(hit)[0]
    t_lo = best_t[h_idx]
    t_hi = prev_t[h_idx]
    ox_h, oy_h, oz_h = ox[h_idx], oy[h_idx], oz[h_idx]

    # 6-step exact binary search refinement between t_hi (above surface) and t_lo (on/below surface)
    for _ in range(6):
        tm = 0.5 * (t_lo + t_hi)
        hm, _ = hf_fn(ox_h, oz_h + tm * COSP)
        is_below = (oy_h + tm * SINP) <= hm
        t_lo = np.where(is_below, tm, t_lo)
        t_hi = np.where(is_below, t_hi, tm)

    t_fin = 0.5 * (t_lo + t_hi)
    xh = ox_h
    yh = oy_h + t_fin * SINP
    zh = oz_h + t_fin * COSP
    hh, tag_h = hf_fn(xh, zh)

    # Detect crisp top surface vs vertical step wall normal from finite height gradient!
    eps = 0.45
    hx_p, tag_xp = hf_fn(xh + eps, zh)
    hx_m, tag_xm = hf_fn(xh - eps, zh)
    hz_p, tag_zp = hf_fn(xh, zh + eps)
    hz_m, tag_zm = hf_fn(xh, zh - eps)
    gx = (hx_p - hx_m) / (2.0 * eps)
    gz = (hz_p - hz_m) / (2.0 * eps)
    g_norm = np.hypot(gx, gz)

    max_nb_h = np.maximum(np.maximum(hx_p, hx_m), np.maximum(hz_p, hz_m))
    # If bisect landed 0.02px outside cliff edge where hh<=0, adopt the adjacent higher cliff tag cleanly!
    use_nb_tag = hh <= h_min + 0.05
    best_nb_tag = np.where(
        hx_p >= np.maximum(hx_m, np.maximum(hz_p, hz_m)), tag_xp,
        np.where(hx_m >= np.maximum(hz_p, hz_m), tag_xm, np.where(hz_p >= hz_m, tag_zp, tag_zm)),
    )
    tag_h = np.where(use_nb_tag, best_nb_tag, tag_h)

    is_wall = (g_norm > 1.2) & (yh < max_nb_h - 0.22)
    # Normal: wall points down height gradient in XZ; horizontal terrace points straight UP [0, 1, 0]!
    n_wall_x = np.where(g_norm > 1e-6, -gx / np.maximum(g_norm, 1e-6), 0.0)
    n_wall_z = np.where(g_norm > 1e-6, -gz / np.maximum(g_norm, 1e-6), 1.0)
    nh = np.stack(
        [
            np.where(is_wall, n_wall_x, 0.0),
            np.where(is_wall, 0.08, 1.0),
            np.where(is_wall, n_wall_z, 0.0),
        ],
        axis=-1,
    )
    nh /= np.maximum(np.linalg.norm(nh, axis=-1, keepdims=True), 1e-9)

    # Directional Cast Shadow Ray along +L_3D across terrace walls
    sun_vis_h = np.ones(h_idx.size, dtype=np.float64)
    for s_step in np.linspace(0.65, 11.5, 12):
        xs = xh + L_3D[0] * s_step
        ys = yh + L_3D[1] * s_step + 0.18
        zs = zh + L_3D[2] * s_step
        hs, _ = hf_fn(xs, zs)
        sun_vis_h = np.where((hs > ys + 0.08) & (hs > h_min + 0.05), 0.0, sun_vis_h)
    sun_vis_h = np.where((nh @ L_3D) <= 0.02, 0.0, sun_vis_h)

    # Foot-of-wall Ambient Occlusion on floor near step rises
    wall_jump = np.maximum(max_nb_h - yh, 0.0)
    ao_h = np.where(~is_wall & (wall_jump > 1.2), 0.72, 1.0)

    rgba_h, mat_h, glow_h = paint_fn(xh, yh, zh, nh, is_wall, tag_h, sun_vis_h, ao_h)

    ok_2d = hit.reshape(ny, nx)
    depth_2d = np.where(ok_2d, -1e9, -1e9)
    depth_flat = np.full(N, -1e9, dtype=np.float64)
    depth_flat[h_idx] = t_fin
    depth_2d = depth_flat.reshape(ny, nx)

    rgba_2d = np.zeros((N, 4), dtype=np.uint8)
    mat_2d = np.zeros(N, dtype=np.int16)
    glow_2d = np.zeros((N, 4), dtype=np.uint8)
    rgba_2d[h_idx] = rgba_h
    mat_2d[h_idx] = mat_h
    glow_2d[h_idx] = glow_h

    cv._commit_ss(
        x0,
        x1,
        y0,
        y1,
        ss,
        ok_2d,
        depth_2d,
        rgba_2d.reshape(ny, nx, 4),
        mat_2d.reshape(ny, nx),
        glow_2d.reshape(ny, nx, 4),
        oid,
        min_cov=max(1, (ss * ss + 1) // 2),
    )
    return oid


# ==============================================================================
# 3. CRISP ARCHITECTURAL, ASHLAR & CONSTELLATION HELPERS
# ==============================================================================
def _ihash(a: int, b: int, seed: int = 0) -> float:
    n = (a * 374761393 + b * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def draw_constellation_medallion(cv: Canvas, cx: float, cy: float, idx: int, rx: float = 9.0, ry: float = 6.0) -> tuple[int, int]:
    """Draws an octagonal/elliptical indigo star medallion framed in brass with a unique glowing constellation."""
    icx, icy = int(round(cx)), int(round(cy))
    for y in range(icy - int(ry) - 2, icy + int(ry) + 3):
        for x in range(icx - int(rx) - 2, icx + int(rx) + 3):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            d = math.hypot(dx, dy)
            if d <= 1.0:
                if d >= 0.72:
                    lit = -0.35 * dx - 0.45 * dy + 0.15
                    cv.put_px(x, y, shade_color(MAT_GOLD, lit), mat=MAT_GOLD)
                else:
                    cv.put_px(x, y, INDIGO[1 if (dx + dy) < 0 else 0], mat=MAT_INDIGO)

    # 12 distinct crisp miniature constellation asterisms (normalized to [-1..1] inside disc)
    patterns = [
        [(-3, -1), (0, -2), (3, 0), (1, 2)],
        [(-3, 1), (-1, -2), (2, -1), (3, 2)],
        [(-2, -2), (0, 0), (2, 2), (2, -2)],
        [(-3, 0), (-1, -1), (1, 1), (3, 0)],
        [(-2, 2), (-2, -1), (1, -2), (3, 1)],
        [(0, -2), (-2, 1), (2, 1), (0, 2)],
        [(-3, -1), (-1, 1), (1, -1), (3, 1)],
        [(-2, -2), (1, -2), (2, 1), (-1, 2)],
        [(-3, 1), (0, -2), (3, 1)],
        [(-2, -1), (0, 0), (2, -1), (0, 2)],
        [(-3, 0), (0, -2), (3, 0), (0, 2)],
        [(-2, -2), (-1, 0), (1, 0), (2, 2)],
    ]
    pts = patterns[idx % 12]
    # Connect consecutive stars with thin faint gold-violet line, bright stars in turq/solar/astral
    for (ax_o, ay_o), (bx_o, by_o) in zip(pts, pts[1:]):
        steps = max(abs(bx_o - ax_o), abs(by_o - ay_o), 1) * 2
        for s in range(1, steps):
            t = s / steps
            px_i = int(round(cx + (ax_o + (bx_o - ax_o) * t) * 1.15))
            py_i = int(round(cy + (ay_o + (by_o - ay_o) * t) * 0.78))
            cv.put_px(px_i, py_i, GOLD[3], mat=MAT_GOLD)
            cv.put_glow(px_i, py_i, SOLAR[0][:3], 130)

    star_col = TURQ[3] if idx % 3 == 0 else (SOLAR[2] if idx % 3 == 1 else ASTRAL[1])
    for j, (sx_o, sy_o) in enumerate(pts):
        px_i = int(round(cx + sx_o * 1.15))
        py_i = int(round(cy + sy_o * 0.78))
        c = TURQ[3] if j == 0 else star_col
        cv.put_px(px_i, py_i, c, mat=MAT_QUARTZ)
        cv.put_glow(px_i, py_i, c[:3], 215 if j == 0 else 185)
    return icx, icy


def draw_line_2d(
    cv: Canvas,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    col: tuple[int, int, int, int],
    mat: int,
    glow_rgb: Optional[tuple[int, int, int]] = None,
    glow_a: int = 0,
) -> None:
    steps = max(int(math.hypot(x1 - x0, y1 - y0) * 1.5), 1)
    for i in range(steps + 1):
        t = i / steps
        ix = int(round(x0 + (x1 - x0) * t))
        iy = int(round(y0 + (y1 - y0) * t))
        cv.put_px(ix, iy, col, mat=mat)
        if glow_rgb is not None and glow_a > 0:
            cv.put_glow(ix, iy, glow_rgb, glow_a)


# ==============================================================================
# 4. ASSET GENERATORS (#1 THROUGH #11)
# ==============================================================================

# ------------------------------------------------------------------------------
# ASSET 1: plaza_mosaic (352x260, center (176, 128))
# ------------------------------------------------------------------------------
def make_plaza_mosaic() -> tuple[list, list, dict]:
    """True 3D tiered carved sandstone & sinter-quartz astronomical podium:
    raised outer kerb wall (9-10 px vertical southern riser + ground shadow),
    stepped Zodiac brass terrace with 12 constellation medallions, sunken inner
    Zodiac court showing curved shadowed northern inner wall, and baked SE
    monument cast shadows + contact AO under Rotunda, Flanks, and Portal."""
    W, H = 352, 260
    cx, cy = 176.0, 128.0
    cv = Canvas(W, H, cx, cy)
    rx_w, rz_w = 156.0, 174.0  # World ellipse radii -> screen ~ (156, 94.8)

    # Southern ground drop shadow tightly hugging podium riser base (no shadow protruding above north edge!)
    cv.draw_ground_shadow(cx + 5.0, cy + 5.0, rx_w + 1.0, rz_w * SINP + 2.0, max_alpha=68)

    # Precompute 12 medallion world positions on Tier 2 (Y_up = 7.5, r_norm = 0.80)
    med_world = []
    medallions = []
    for k in range(12):
        ang_k = math.radians(k * 30.0 - 90.0)
        xk = math.cos(ang_k) * rx_w * 0.795
        zk = math.sin(ang_k) * rz_w * 0.795
        med_world.append((k, xk, zk))
        mx_s, my_s = project_pt((xk, 7.5, zk), cx, cy)
        medallions.append([int(round(mx_s)), int(round(my_s))])

    med_patterns = [
        [(-3, -1), (0, -2), (3, 0), (1, 2)],
        [(-3, 1), (-1, -2), (2, -1), (3, 2)],
        [(-2, -2), (0, 0), (2, 2), (2, -2)],
        [(-3, 0), (-1, -1), (1, 1), (3, 0)],
        [(-2, 2), (-2, -1), (1, -2), (3, 1)],
        [(0, -2), (-2, 1), (2, 1), (0, 2)],
        [(-3, -1), (-1, 1), (1, -1), (3, 1)],
        [(-2, -2), (1, -2), (2, 1), (-1, 2)],
        [(-3, 1), (0, -2), (3, 1)],
        [(-2, -1), (0, 0), (2, -1), (0, 2)],
        [(-3, 0), (0, -2), (3, 0), (0, 2)],
        [(-2, -2), (-1, 0), (1, 0), (2, 2)],
    ]

    # Deterministic per-sector outer edge height/cutout profile (numpy vectorized)
    sec_lim = np.array(
        [0.90 + 0.03 * _ihash(s, 19, 41) if s in (3, 11, 14, 21, 27, 30) else 0.96 + 0.04 * _ihash(s, 19, 41) for s in range(32)],
        dtype=np.float64,
    )
    sec_chipped = np.array([1 if s in (3, 10, 14, 21, 26, 30) else 0 for s in range(32)], dtype=np.int8)

    def plaza_hf(x: np.ndarray, z: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        ang = np.arctan2(z, x)
        sec = (np.floor(((ang + math.pi) / math.tau) * 32.0).astype(np.int32)) & 31
        r_norm = np.hypot(x / rx_w, z / rz_w)
        lim = sec_lim[sec]
        in_p = r_norm <= lim
        is_chip = sec_chipped[sec] == 1

        # 3-Tier True 3D Podium Profile:
        # Outer Rim (r_norm >= 0.855): Y_up = 11.5 (drops to 8.0 where top kerb block is chipped away!)
        # Zodiac Brass Terrace (0.725 <= r_norm < 0.855): Y_up = 7.5
        # Sunken Inner Court (r_norm < 0.725): Y_up = 2.0 (Central Compass Star raised slightly to 3.0!)
        h_outer = np.where(is_chip & (r_norm > 0.89), 7.8, 11.5)
        h = np.where(
            ~in_p,
            0.0,
            np.where(r_norm >= 0.855, h_outer, np.where(r_norm >= 0.725, 7.5, np.where(r_norm < 0.27, 2.6, 1.8))),
        )
        tag = np.where(r_norm >= 0.855, 3, np.where(r_norm >= 0.725, 2, 1))
        return h, tag.astype(np.int32)

    def paint_plaza(
        xh: np.ndarray,
        yh: np.ndarray,
        zh: np.ndarray,
        nh: np.ndarray,
        is_wall: np.ndarray,
        tag_h: np.ndarray,
        sun_vis: np.ndarray,
        ao_h: np.ndarray,
    ):
        n = xh.size
        rgba = np.zeros((n, 4), dtype=np.uint8)
        mat = np.full(n, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((n, 4), dtype=np.uint8)

        ang = np.arctan2(zh, xh)
        deg = (np.degrees(ang) + 360.0) % 360.0
        r_norm = np.hypot(xh / rx_w, zh / rz_w)
        ang_dist_12 = np.minimum(deg % 30.0, 30.0 - (deg % 30.0))
        ang_dist_24 = np.minimum(deg % 15.0, 15.0 - (deg % 15.0))
        on_ray_12 = ang_dist_12 * np.maximum(r_norm, 0.08) < 0.85
        on_ray_24 = ang_dist_24 * np.maximum(r_norm, 0.08) < 0.45

        # Baked Monument Cast Shadows & Contact AO from Rotunda Drum, W/E Flanks, and Portal Steps!
        mon_vis = np.ones(n, dtype=np.float64)
        mon_ao = ao_h.copy()

        # 1. Rotunda Drum (radius 72..83 north of Z=+6 -> world coords centered at (0, 0)) + SE dome cast shadow
        r_drum = np.hypot(xh, zh)
        on_north_drum_arc = zh <= 14.0
        # SE ground cast shadow shifted (+10 X, +12 Z) from Rotunda wall & surviving NW dome!
        r_sh_drum = np.hypot(xh - 10.0, zh - 11.0)
        in_dome_shadow = (r_sh_drum <= 83.0) & (zh <= 24.0) & ((xh - 12.0) < 58.0) & (r_norm < 0.72)
        near_drum_foot = on_north_drum_arc & (np.abs(r_drum - 77.5) < 9.5)
        mon_vis = np.where(~is_wall & in_dome_shadow, 0.25, mon_vis)
        mon_ao = np.where(~is_wall & near_drum_foot, np.minimum(mon_ao, 0.58), mon_ao)

        # 2. West & East Flank Buttresses ([-78, +18.3] and [+78, +18.3])
        fw_d = np.hypot((xh + 78.0) / 26.0, (zh - 18.0) / 24.0)
        fw_sh = np.hypot((xh + 70.0) / 27.0, (zh - 26.0) / 24.0)
        fe_d = np.hypot((xh - 78.0) / 28.0, (zh - 18.0) / 24.0)
        fe_sh = np.hypot((xh - 86.0) / 29.0, (zh - 27.0) / 24.0)
        mon_ao = np.where(~is_wall & ((fw_d < 1.05) | (fe_d < 1.05)), np.minimum(mon_ao, 0.55), mon_ao)
        mon_vis = np.where(~is_wall & ((fw_sh < 1.0) | (fe_sh < 1.0)), 0.25, mon_vis)

        # 3. Portal Portico & Apron Stairs ([0, +25.7], footprint |X|<=46, Z in [-4..+46]) + SE portico shadow
        in_portal_sh = (xh >= -40.0) & (xh <= 56.0) & (zh >= 16.0) & (zh <= 58.0)
        near_portal_foot = (np.abs(xh) <= 46.0) & (zh >= 32.0) & (zh <= 54.0)
        mon_vis = np.where(~is_wall & in_portal_sh, 0.30, mon_vis)
        mon_ao = np.where(~is_wall & near_portal_foot, np.minimum(mon_ao, 0.60), mon_ao)

        vis_tot = np.minimum(sun_vis, mon_vis)
        lit_base = nh @ L_3D
        lit_eff = np.where(vis_tot < 0.5, np.minimum(lit_base * 0.45 - 0.32, -0.18), lit_base)
        lit_eff -= (1.0 - mon_ao) * 0.42

        # Horizontal u along curved rim or flagstones for ashlar block joints
        u_curv = ang * np.maximum(r_norm * 156.0, 20.0)
        wall_col = ashlar_shade_3d(u_curv, yh, lit_eff, MAT_SANDSTONE, course_h=4.6, block_w=13.0, seed=55)
        # Bright 1px projecting cap edge lip at top of every vertical wall
        wall_top_edge = is_wall & ((tag_h == 3) & (yh > 10.1) | (tag_h == 2) & (yh > 6.2))
        wall_col = np.where((wall_top_edge & (lit_eff > -0.15))[..., None], SANDSTONE[4], wall_col)

        # Horizontal Terrace Floor Materials (tag 3=Outer Kerb, tag 2=Zodiac Brass Tier, tag 1=Sunken Mosaic)
        floor_col = ashlar_shade_3d(u_curv, r_norm * 156.0, lit_eff, MAT_SANDSTONE, course_h=12.0, block_w=16.0, seed=71)

        # Flush wind-dusted sand caught ONLY in broken outer border mortar recesses (zero floating pillows!)
        sand_recess = (~is_wall) & (tag_h == 3) & (yh < 8.4)
        sand_c = np.array(SAND_DRIFT, dtype=np.uint8)[shade_band_np(lit_eff + 0.10, len(SAND_DRIFT))]
        floor_col = np.where(sand_recess[..., None], sand_c, floor_col)
        mat = np.where(~is_wall & sand_recess, MAT_SAND, mat)

        # Tier 2: Engraved Outer Brass Degree Ring (0.755..0.835) on Zodiac Terrace
        in_ring1 = (~is_wall) & (r_norm >= 0.750) & (r_norm <= 0.842)
        g_pal = np.array(GOLD, dtype=np.uint8)
        is_tick1 = in_ring1 & ((deg % 5.0) < 1.15) & (r_norm > 0.815)
        is_rim1 = in_ring1 & ((r_norm < 0.762) | (r_norm > 0.832))
        ring1_col = np.where(is_tick1[..., None], GOLD[0], np.where(is_rim1[..., None], GOLD[3], g_pal[shade_band_np(lit_eff + 0.12, len(GOLD))]))
        floor_col = np.where(in_ring1[..., None], ring1_col, floor_col)
        mat = np.where(in_ring1, MAT_GOLD, mat)

        # Tier 1 Sunken Mosaic Rings: Mid Brass Ring (0.51..0.565) & Inner Brass Ring (0.27..0.325)
        in_ring2 = (~is_wall) & (r_norm >= 0.510) & (r_norm <= 0.565)
        in_ring3 = (~is_wall) & (r_norm >= 0.270) & (r_norm <= 0.325)
        ring23_col = g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))]
        ring23_col = np.where((in_ring2 & ((deg % 10.0) < 1.3) & (r_norm < 0.525))[..., None], GOLD[0], ring23_col)
        floor_col = np.where((in_ring2 | in_ring3)[..., None], ring23_col, floor_col)
        mat = np.where(in_ring2 | in_ring3, MAT_GOLD, mat)

        # Between Ring 2 & Ring 3 (0.325..0.510): Alternating White Quartz & Sandstone Sunburst Wedges
        in_mid_w = (~is_wall) & (r_norm > 0.325) & (r_norm < 0.510)
        wedge_m = np.floor(deg / 15.0).astype(np.int32)
        q_pal = np.array(QUARTZ_W, dtype=np.uint8)
        s_pal = np.array(SANDSTONE, dtype=np.uint8)
        m_col = np.where(
            (on_ray_24 | (np.abs(r_norm - 0.42) < 0.011))[..., None],
            SANDSTONE[0],
            np.where((wedge_m % 2 == 0)[..., None], q_pal[shade_band_np(lit_eff + 0.10, len(QUARTZ_W))], s_pal[shade_band_np(lit_eff, len(SANDSTONE))]),
        )
        floor_col = np.where(in_mid_w[..., None], m_col, floor_col)
        mat = np.where(in_mid_w & (wedge_m % 2 == 0) & (~on_ray_24), MAT_QUARTZ, mat)

        # Outer-Mid Mosaic & Brass Azimuth Lines (0.565..0.725)
        in_om = (~is_wall) & (r_norm > 0.565) & (r_norm < 0.725)
        w_om = np.floor(deg / 30.0).astype(np.int32)
        sr_om = np.floor((r_norm - 0.565) / 0.055).astype(np.int32)
        om_q = (sr_om == 1) & (w_om % 2 == 1) & ((deg % 30.0) > 7.0) & ((deg % 30.0) < 23.0)
        om_seam = (np.abs((r_norm - 0.565) % 0.055) < 0.009) | (np.abs(deg % 15.0) < 0.85)
        om_col = np.where(
            on_ray_12[..., None],
            g_pal[shade_band_np(lit_eff + 0.12, len(GOLD))],
            np.where(
                om_seam[..., None],
                SANDSTONE[0],
                np.where(om_q[..., None], q_pal[shade_band_np(lit_eff + 0.08, len(QUARTZ_W))], s_pal[shade_band_np(lit_eff, len(SANDSTONE))]),
            ),
        )
        floor_col = np.where(in_om[..., None], om_col, floor_col)
        mat = np.where(in_om & on_ray_12, MAT_GOLD, np.where(in_om & om_q & (~om_seam), MAT_QUARTZ, mat))

        # Radial Azimuth Turquoise Pips at mid-band (r_norm ~ 0.64) & (0.42)
        az_pip = (~is_wall) & on_ray_12 & ((np.abs(r_norm - 0.64) < 0.022) | (np.abs(r_norm - 0.42) < 0.026))
        floor_col = np.where(az_pip[..., None], TURQ[2], floor_col)
        mat = np.where(az_pip, MAT_QUARTZ, mat)
        glow = np.where(az_pip[..., None], (*TURQ[2][:3], 170), glow)

        # Central 8-Pointed White Sinter-Quartz & Deep Star-Slate Compass Rose (r_norm < 0.27)
        in_rose = (~is_wall) & (r_norm < 0.270)
        ang8 = np.abs(((deg + 22.5) % 45.0) - 22.5)
        in_star = (ang8 < 7.5 * (1.0 - r_norm / 0.29)) | (r_norm < 0.085)
        star_side = ((deg % 45.0) < 22.5) ^ ((xh + zh) > 0)
        i_pal = np.array(INDIGO, dtype=np.uint8)
        rose_col = np.where(
            (r_norm < 0.032)[..., None],
            TURQ[3],
            np.where(
                (r_norm < 0.060)[..., None],
                GOLD[3],
                np.where(
                    in_star[..., None],
                    np.where(star_side[..., None], q_pal[shade_band_np(lit_eff + 0.15, len(QUARTZ_W))], q_pal[shade_band_np(lit_eff - 0.15, len(QUARTZ_W))]),
                    np.where((ang_dist_12 < 1.5)[..., None], GOLD[2], i_pal[shade_band_np(lit_eff, len(INDIGO))]),
                ),
            ),
        )
        floor_col = np.where(in_rose[..., None], rose_col, floor_col)
        mat = np.where(in_rose & (r_norm < 0.032), MAT_QUARTZ, np.where(in_rose & in_star, MAT_QUARTZ, np.where(in_rose, MAT_INDIGO, mat)))
        rose_gl = in_rose & ((r_norm < 0.035) | (in_star & (r_norm > 0.10) & (ang8 < 1.1)))
        glow = np.where(rose_gl[..., None], np.where((r_norm < 0.035)[..., None], (*TURQ[3][:3], 215), (*SOLAR[1][:3], 150)), glow)

        rgba = np.where(is_wall[..., None], wall_col, floor_col)
        mat = np.where(is_wall, MAT_SANDSTONE, mat)

        # Paint all 12 Constellation Medallions cleanly on Tier 2 in true 3D (so shadows occlude properly!)
        for k, xk, zk in med_world:
            mdx = (xh - xk) / 9.2
            mdy = (zh - zk) / 10.5
            md = np.hypot(mdx, mdy)
            hit_m = (~is_wall) & (md <= 1.0)
            if not hit_m.any():
                continue
            bezel = hit_m & (md >= 0.70)
            disc = hit_m & (md < 0.70)
            m_lit = -0.35 * mdx - 0.45 * mdy + lit_eff * 0.55
            rgba = np.where(bezel[..., None], g_pal[shade_band_np(m_lit, len(GOLD))], rgba)
            rgba = np.where(disc[..., None], i_pal[shade_band_np(lit_eff - 0.10, len(INDIGO))], rgba)
            mat = np.where(bezel, MAT_GOLD, np.where(disc, MAT_INDIGO, mat))

            pts = med_patterns[k]
            s_col = TURQ[3] if k % 3 == 0 else (SOLAR[2] if k % 3 == 1 else ASTRAL[1])
            for (ax_o, ay_o), (bx_o, by_o) in zip(pts, pts[1:]):
                # Distance to constellation asterism segment in medallion local plane
                px0, pz0 = xk + ax_o * 1.15, zk + ay_o * 1.4
                px1, pz1 = xk + bx_o * 1.15, zk + by_o * 1.4
                vx, vz = px1 - px0, pz1 - pz0
                vv = vx * vx + vz * vz + 1e-6
                t_seg = np.clip(((xh - px0) * vx + (zh - pz0) * vz) / vv, 0.0, 1.0)
                seg_d = np.hypot(xh - (px0 + vx * t_seg), zh - (pz0 + vz * t_seg))
                on_line = disc & (seg_d < 0.72)
                rgba = np.where(on_line[..., None], GOLD[3], rgba)
                glow = np.where(on_line[..., None], (*SOLAR[0][:3], 125), glow)
            for j, (sx_o, sy_o) in enumerate(pts):
                px_s, pz_s = xk + sx_o * 1.15, zk + sy_o * 1.4
                star_h = disc & (np.hypot(xh - px_s, zh - pz_s) < 1.15)
                sc = TURQ[3] if j == 0 else s_col
                rgba = np.where(star_h[..., None], sc, rgba)
                mat = np.where(star_h, MAT_QUARTZ, mat)
                glow = np.where(star_h[..., None], (*sc[:3], 210 if j == 0 else 180), glow)

        return rgba, mat, glow

    render_heightfield(cv, (4, W - 4, 4, H - 4), h_max=12.0, h_min=0.0, hf_fn=plaza_hf, paint_fn=paint_plaza, ss=2, n_coarse=36, margin=2)

    px, glow = cv.finalize_with_outlines(foot_cut_y=H, add_internal_creases=False, halo_alpha=0.22)
    meta = {
        "file": "plaza_mosaic.png",
        "glow": "plaza_mosaic_glow.png",
        "size": [W, H],
        "center": [176, 128],
        "outer_radii": [156, 95],
        "rings": [[125, 76], [84, 51], [46, 28]],
        "medallions": medallions,
    }
    return px, glow, meta


# ------------------------------------------------------------------------------
# ASSET 2: rotunda_vault (256x236, feet (128, 206))
# ------------------------------------------------------------------------------
def make_rotunda_vault() -> tuple[list, list, dict]:
    """Monumental curved northern sandstone ashlar back-drum, brass zodiac frieze band,
    surviving deep-indigo glazed NW half-dome inlaid with gold star-charts, 5 soaring
    curved sandstone-and-brass meridian ribs arching across shattered SE half, and
    tall golden Astral Lightning Spire at apex (~20px below y=0)."""
    W, H = 256, 236
    ax, ay = 128.0, 206.0
    cv = Canvas(W, H, ax, ay)

    R_drum = 82.0
    R_in = 72.0
    H_drum = 72.0
    Y_dome_base = H_drum
    R_dome_out = 83.0
    R_dome_in = 74.0
    H_dome = 74.0  # Ellipsoidal dome semi-height (apex Y = 72 + 74 = 146 -> sy = 206 - 146*0.8387 = 83.5)

    # 1. Ground contact shadow under curved northern back-drum arc only (keeps south courtyard clean & open!)
    for k in range(15):
        ang = math.pi * (0.04 + 0.92 * k / 14.0)
        gx, gz = math.cos(ang) * 77.0, -math.sin(ang) * 77.0
        sx, sy = project_pt((gx, 0.0, gz), ax, ay)
        cv.draw_ground_shadow(sx, sy + 2.0, 14.0, 5.0, max_alpha=54)

    # 2. Curved Northern Sandstone Ashlar Back-Drum + Brass Zodiac Frieze Band + Concave Interior Wall
    # Angle theta around Y-axis: 0 = East (+X), pi/2 = North (-Z), pi = West (-X).
    # Keep arc from theta = -0.05*pi (ESE) around North (pi/2) to 1.05*pi (WSW), leaving South WIDE OPEN!
    def drum_arc_clip(p: np.ndarray) -> np.ndarray:
        th = np.arctan2(-p[..., 2], p[..., 0])  # +pi/2 is North (-Z)
        # Map into [-pi/2 .. 3*pi/2] so East->North->West is [-0.06*pi .. 1.06*pi]
        th_u = np.where(th < -math.pi * 0.5, th + math.tau, th)
        return (th_u >= -0.04 * math.pi) & (th_u <= 1.04 * math.pi)

    def paint_drum(ok, pos, n_loc, face, lit, rgba, mat_arr, glow_rgba) -> None:
        # Local cylinder: pos[...,0] = X, pos[...,1] = -Z (since R rotates cylinder Z->up Y), pos[...,2] = Y_up!
        # Let's compute world-consistent azimuth & height carefully:
        # Because drum uses R = rot_x(-pi/2): local (x, y, z) -> world (X = x, Y_up = z, Z = -y)
        # So local z + H_drum/2 = Y_up in [0..H_drum], and theta = atan2(local_y, local_x)!
        y_up = pos[..., 2] + H_drum * 0.5
        th = np.arctan2(pos[..., 1], pos[..., 0])
        th_u = np.where(th < -math.pi * 0.5, th + math.tau, th)

        # Course height 7 px, staggered ashlar blocks
        row = np.floor(y_up / 7.0).astype(np.int32)
        ly = y_up - row * 7.0
        arc_u = th_u * 26.0 + (row % 2) * 0.5
        col_i = np.floor(arc_u).astype(np.int32)
        lx = arc_u - col_i

        # Subtle deterministic per-block tonal shift
        b_hash = ((col_i * 73 + row * 139) % 17) / 16.0 - 0.5
        pal_s = np.array(SANDSTONE, dtype=np.uint8)
        pal_g = np.array(GOLD, dtype=np.uint8)
        pal_q = np.array(QUARTZ_W, dtype=np.uint8)
        pal_i = np.array(INDIGO, dtype=np.uint8)

        # Deep Interior Vault Shadow + Mutual Outer Tower Shadows + Cornice Drop Shadow!
        is_inner = (face == 3)
        # Interior apse wall drops sharply into deep shadow under the surviving NW half-dome & gallery cornice!
        under_nw_vault = is_inner & ((th_u >= 0.42 * math.pi) | (y_up >= 49.0))
        in_cornice_sh = (~is_inner) & (y_up >= 48.0) & (y_up <= 51.0)
        # Mutual shadow cast on outer drum base/flanks adjacent to projecting W/E flank towers
        near_flank_sh = (~is_inner) & ((th_u > 0.90 * math.pi) | (th_u < 0.08 * math.pi)) & (y_up < 66.0)

        lit_drum = lit + b_hash * 0.18
        lit_drum = np.where(is_inner, lit_drum * 0.65 - 0.34, lit_drum)
        lit_drum = np.where(under_nw_vault, lit_drum - 0.30, lit_drum)
        lit_drum = np.where(in_cornice_sh, lit_drum - 0.35, lit_drum)
        lit_drum = np.where(near_flank_sh, lit_drum - 0.24, lit_drum)

        bands = shade_band_np(lit_drum, len(pal_s))
        # Mortar joints & sunlit top course lips
        joint = (ly < 0.9) | (lx < 0.08)
        bands = np.where(joint, 0, bands)
        bands = np.where((ly >= 0.9) & (ly < 1.8) & (lit_drum > 0.05) & ~is_inner, np.minimum(bands + 1, 4), bands)
        rgba[:] = pal_s[bands]

        # Deep Star-Slate / Indigo interior masonry tint under shadowed NW apse half-dome!
        nw_indigo_inner = ok & under_nw_vault & (y_up >= 10.0) & (y_up < 51.0) & ~joint
        i_bands_in = shade_band_np(lit_drum + 0.12, len(pal_i))
        rgba[nw_indigo_inner] = pal_i[np.minimum(i_bands_in[nw_indigo_inner], 1)]
        mat_arr[nw_indigo_inner] = MAT_INDIGO

        # Stepped outer plinth at base (y_up < 10)
        plinth = ok & (y_up < 10.0)
        rgba[plinth] = pal_s[np.maximum(bands[plinth], 1)]
        rgba[ok & (y_up >= 9.0) & (y_up < 10.2) & ~is_inner] = SANDSTONE[4]

        # Concave Interior Arched Observatory Niches on inner wall (3 deep recessed niches along NNW, N, NNE)
        for n_ang in (0.28 * math.pi, 0.50 * math.pi, 0.72 * math.pi):
            in_niche = ok & is_inner & (np.abs(th_u - n_ang) < 0.11) & (y_up >= 15.0) & (y_up <= 47.0)
            n_dx = (th_u - n_ang) / 0.11
            n_dy = (y_up - 38.0) / 9.0
            arch_top = (y_up <= 38.0) | ((n_dx * n_dx + n_dy * n_dy) <= 1.0)
            niche_m = in_niche & arch_top
            # Arched stone surround lip vs deep recessed star-indigo back
            niche_rim = niche_m & ((np.abs(n_dx) > 0.76) | ((y_up > 38.0) & (n_dx * n_dx + n_dy * n_dy > 0.65)))
            rgba[niche_m] = pal_i[0]
            mat_arr[niche_m] = MAT_INDIGO
            rgba[niche_rim] = SANDSTONE[0 if (n_dx < 0).any() else 1]
            # Glowing recessed turquoise & gold star glyph in each niche!
            glyph = niche_m & (np.abs(n_dx) < 0.24) & (y_up >= 25.0) & (y_up <= 39.0)
            rgba[glyph] = TURQ[2]
            glow_rgba[glyph] = (*TURQ[2][:3], 180)

        # Tarnished Brass Zodiac Frieze Band (y_up in [51..62]) wrapping drum!
        in_frieze = ok & (y_up >= 51.0) & (y_up <= 62.0)
        g_bands = shade_band_np(lit, len(pal_g))
        g_rim = (y_up < 52.3) | (y_up > 60.7)
        g_bands = np.where(g_rim & (lit > -0.1), np.minimum(g_bands + 1, 4), np.where(g_rim, 0, g_bands))
        rgba[in_frieze] = pal_g[g_bands[in_frieze]]
        mat_arr[in_frieze] = MAT_GOLD

        # Engraved Zodiac Plaques (12 divisions) & Verdigris / Glow Star Pips along frieze
        z_cell = (th_u / (math.pi / 10.0))
        z_frac = z_cell - np.floor(z_cell)
        z_mid = in_frieze & (y_up >= 53.8) & (y_up <= 59.2)
        is_sep = z_mid & (z_frac < 0.12)
        rgba[is_sep] = GOLD[0]
        is_patina = z_mid & (z_frac > 0.72) & (y_up < 56.5) & ((np.floor(z_cell).astype(np.int32) % 2) == 0)
        rgba[is_patina] = VERDIGRIS
        is_star = z_mid & (np.abs(z_frac - 0.45) < 0.08) & (np.abs(y_up - 56.5) < 1.2)
        rgba[is_star] = SOLAR[2]
        glow_rgba[is_star] = (*SOLAR[1][:3], 175)

        # Crown Quartz & Sandstone Cornice (y_up >= 63)
        in_cornice = ok & (y_up >= 63.0)
        is_q_trim = in_cornice & (y_up >= 65.5) & (y_up <= 68.5)
        q_bands = shade_band_np(lit, len(pal_q))
        rgba[is_q_trim] = pal_q[q_bands[is_q_trim]]
        mat_arr[is_q_trim] = MAT_QUARTZ

    # Note: R_drum_mat = rot_x(-pi/2) maps local (x, y, z) -> world (x, z, -y)
    # Check: local +z -> world +Y (UP)! local +y -> world -Z (North)!
    R_drum_mat = rot_x(-math.pi / 2.0)

    def drum_clip_fixed(p: np.ndarray) -> np.ndarray:
        th = np.arctan2(p[..., 1], p[..., 0])  # +pi/2 is North (-Z)
        th_u = np.where(th < -math.pi * 0.5, th + math.tau, th)
        return (th_u >= -0.06 * math.pi) & (th_u <= 1.06 * math.pi)

    cv.render_ring_band(
        center=(0.0, H_drum * 0.5, 0.0),
        R=R_drum_mat,
        r_in=R_in,
        r_out=R_drum,
        half_h=H_drum * 0.5,
        mat=MAT_SANDSTONE,
        paint_fn=paint_drum,
        ss=2,
        arc_clip=drum_clip_fixed,
        margin=2,
    )

    # Interior projecting stone gallery cornice ring casting shadow inside apse!
    cv.render_ring_band(
        center=(0.0, 50.0, 0.0),
        R=R_drum_mat,
        r_in=R_in - 3.5,
        r_out=R_in + 0.5,
        half_h=2.2,
        mat=MAT_SANDSTONE,
        ss=2,
        arc_clip=drum_clip_fixed,
        margin=2,
    )
    # Interior stepped ground base plinth ring inside apse
    cv.render_ring_band(
        center=(0.0, 3.5, 0.0),
        R=R_drum_mat,
        r_in=R_in - 4.0,
        r_out=R_drum + 1.8,
        half_h=3.5,
        mat=MAT_SANDSTONE,
        ss=2,
        arc_clip=drum_clip_fixed,
        margin=2,
    )

    # Decorative vertical pilaster ribs along the outer drum flanks (W, NW, NNW, NNE, NE, E)
    for k, ang in enumerate((0.0, 0.22 * math.pi, 0.40 * math.pi, 0.60 * math.pi, 0.78 * math.pi, math.pi)):
        px_c = math.cos(ang) * (R_drum + 1.2)
        pz_c = -math.sin(ang) * (R_drum + 1.2)
        cv.render_cylinder((px_c, 0.0, pz_c), (px_c, H_drum - 2.0, pz_c), 4.2, 3.3, MAT_SANDSTONE, ss=2)

    # 3. Surviving Deep-Indigo Glazed Half-Dome inlaid with Gold Star-Charts on NW Half!
    # Raycast thick ellipsoidal shell centered at (0, Y_dome_base, 0) with jagged shattered SE edge.
    dome_oid = cv.new_obj()
    dome_cx, dome_cy = project_pt((0.0, Y_dome_base + H_dome * 0.45, 0.0), ax, ay)
    dx0 = max(2, int(dome_cx - R_dome_out - 6))
    dx1 = min(W - 2, int(dome_cx + R_dome_out + 7))
    dy0 = max(2, int(dome_cy - H_dome - 6))
    dy1 = min(H - 2, int(dome_cy + R_dome_out + 6))

    star_nodes: list[list[int]] = []
    # Raycast at SS=2 for crisp dome tiles & sharp jagged fracture wall
    ss_d = 2
    o_d, ny_d, nx_d = cv._ray_grid(dx0, dx1, dy0, dy1, ss_d)
    dc = np.array([0.0, Y_dome_base, 0.0], dtype=np.float64)
    # Ellipsoid scaling: S_out = (R_dome_out, H_dome, R_dome_out)
    # Compute analytical outer and inner intersections, then step across thin shell to capture shattered fracture thickness!
    S_out = np.array([R_dome_out, H_dome, R_dome_out], dtype=np.float64)
    q0_d = (o_d - dc) / S_out
    qd_d = WHAT / S_out
    aa_d = float(qd_d @ qd_d)
    bb_d = q0_d @ qd_d
    cc_d = (q0_d * q0_d).sum(axis=-1) - 1.0
    disc_d = bb_d * bb_d - aa_d * cc_d
    hit_sphere = disc_d >= 0.0
    sq_d = np.sqrt(np.where(hit_sphere, disc_d, 0.0))
    t_hi = (-bb_d + sq_d) / aa_d
    t_lo = (-bb_d - sq_d) / aa_d

    # Sample N_STEPS along [t_hi .. t_lo] from front to back inside dome bounding sphere
    best_dome_t = np.full((ny_d, nx_d), -1e9, dtype=np.float64)
    best_dome_p = np.zeros((ny_d, nx_d, 3), dtype=np.float64)
    best_dome_n = np.zeros((ny_d, nx_d, 3), dtype=np.float64)
    best_dome_kind = np.zeros((ny_d, nx_d), dtype=np.int8)  # 0=outer glazed, 1=inner glazed, 2=fracture cut

    # Step through front and back shells
    for step_t in np.linspace(0.0, 1.0, 36):
        # March from frontmost sphere surface toward back across the dome!
        tc = t_hi * (1.0 - step_t) + t_lo * step_t
        pw = o_d + tc[..., None] * WHAT
        rel = pw - dc
        # Ellipsoidal radial distance (1.0 = outer surface, ~0.855 = thicker inner stone vault)
        er = np.sqrt((rel[..., 0] / R_dome_out) ** 2 + (rel[..., 1] / H_dome) ** 2 + (rel[..., 2] / R_dome_out) ** 2)
        in_shell = hit_sphere & (rel[..., 1] >= 0.0) & (er >= 0.855) & (er <= 1.005)
        if not in_shell.any():
            continue

        # Azimuth th_n: 0 = West (-X), pi/2 = North (-Z), pi = East (+X), -pi/2 = South (+Z)
        # Wait: let's define standard azimuth angle phi_az = atan2(-Z, -X):
        # West (-X, Z=0) -> 0
        # North (X=0, -Z) -> +pi/2
        # NW -> +pi/4 (right in the middle of the surviving NW half-dome!)
        # East (+X) -> pi, South (+Z) -> -pi/2
        az = np.arctan2(-rel[..., 2], -rel[..., 0])  # [-pi..pi], NW is +pi/4!
        elev = np.arcsin(np.clip(rel[..., 1] / H_dome, 0.0, 1.0))  # 0 at cornice .. pi/2 at apex

        # Surviving NW half-dome covers az around [-0.24*pi .. +0.96*pi], jaggedly shattered!
        jag_hi = 0.94 * math.pi - 0.25 * elev + 0.13 * np.sin(elev * 17.0) + 0.08 * np.cos(elev * 29.0)
        jag_lo = -0.22 * math.pi + 0.22 * elev + 0.12 * np.sin(elev * 14.0 + 1.2)
        # Keep crown ring right around apex intact (elev > 1.26)
        survives = ((az >= jag_lo) & (az <= jag_hi)) | (elev > 1.26)
        valid = in_shell & survives
        win = valid & (tc > best_dome_t)
        if not win.any():
            continue

        # Classify face normal: outer surface, inner vault, or fracture rim
        n_out = np.stack([rel[..., 0] / (R_dome_out ** 2), rel[..., 1] / (H_dome ** 2), rel[..., 2] / (R_dome_out ** 2)], axis=-1)
        n_out /= np.maximum(np.linalg.norm(n_out, axis=-1, keepdims=True), 1e-9)
        is_inner = (er < 0.895) & (np.sum(n_out * WHAT, axis=-1) < 0.1)
        is_cut = (np.abs(az - jag_hi) < 0.075) | (np.abs(az - jag_lo) < 0.075)
        n_use = np.where(is_inner[..., None], -n_out, n_out)
        kind_use = np.where(is_cut, 2, np.where(is_inner, 1, 0))

        best_dome_t = np.where(win, tc, best_dome_t)
        best_dome_p = np.where(win[..., None], rel, best_dome_p)
        best_dome_n = np.where(win[..., None], n_use, best_dome_n)
        best_dome_kind = np.where(win, kind_use, best_dome_kind)

    ok_d = best_dome_t > -1e8
    if ok_d.any():
        lit_d = best_dome_n @ L_3D
        pal_i = np.array(INDIGO, dtype=np.uint8)
        pal_s = np.array(SANDSTONE, dtype=np.uint8)
        pal_g = np.array(GOLD, dtype=np.uint8)

        az_h = np.arctan2(-best_dome_p[..., 2], -best_dome_p[..., 0])
        el_h = np.arcsin(np.clip(best_dome_p[..., 1] / H_dome, 0.0, 1.0))

        # Glazed tile courses (curved concentric courses, staggered per row, crisp mortar seams)
        row_t = np.floor(el_h * 11.0).astype(np.int32)
        ly_t = (el_h * 11.0) - row_t
        col_t = np.floor((az_h + math.pi) * (9.5 - row_t * 0.7) + (row_t % 2) * 0.5).astype(np.int32)
        lx_t = ((az_h + math.pi) * (9.5 - row_t * 0.7) + (row_t % 2) * 0.5) - col_t
        tile_var = ((col_t * 47 + row_t * 89) % 7) / 6.0 - 0.5

        ibands = shade_band_np(lit_d + tile_var * 0.22, len(pal_i))
        ibands = np.where(best_dome_kind == 1, np.maximum(ibands - 1, 0), ibands)
        tile_seam = (ly_t < 0.11) | (lx_t < 0.08)
        ibands = np.where(tile_seam, 0, ibands)
        rgba_d = pal_i[ibands]
        mat_d = np.full((ny_d, nx_d), MAT_INDIGO, dtype=np.int16)
        glow_d = np.zeros((ny_d, nx_d, 4), dtype=np.uint8)

        # Fracture edge: warm sandstone core masonry thickness lip
        sbands = shade_band_np(lit_d, len(pal_s))
        is_frac = ok_d & (best_dome_kind == 2)
        rgba_d[is_frac] = pal_s[sbands[is_frac]]
        mat_d[is_frac] = MAT_SANDSTONE

        # Inlaid Gold Star-Charts on the glazed NW dome exterior!
        # Concentric golden ecliptic circles + diagonal celestial meridian lines + glowing star nodes!
        on_chart_arc = (
            (np.abs(el_h - 0.50) < 0.032)
            | (np.abs(el_h - 0.92) < 0.030)
            | (np.abs(az_h - 0.26 + el_h * 0.36) < 0.036)
            | (np.abs(az_h - 0.72 - el_h * 0.28) < 0.036)
        )
        chart_px = ok_d & (best_dome_kind == 0) & on_chart_arc & (el_h < 1.24)
        rgba_d[chart_px] = np.where((lit_d[chart_px] > 0.05)[..., None], GOLD[4], GOLD[3])
        mat_d[chart_px] = MAT_GOLD
        glow_d[chart_px] = (*SOLAR[1][:3], 150)

        # Golden Star Pins at chart intersections (in *_glow.png!)
        for s_az, s_el in ((0.09, 0.50), (0.35, 0.50), (0.58, 0.50), (0.04, 0.92), (0.42, 0.92), (0.85, 0.92), (-0.12, 0.32), (0.68, 0.72)):
            s_hit = ok_d & (best_dome_kind == 0) & (np.hypot((az_h - s_az) * np.cos(el_h), el_h - s_el) < 0.052)
            rgba_d[s_hit] = SOLAR[2]
            glow_d[s_hit] = (*SOLAR[2][:3], 215)
            # Also project approximate world pos for metadata
            sx_s, sy_s = project_pt(
                (-R_dome_out * math.cos(s_el) * math.cos(s_az), Y_dome_base + H_dome * math.sin(s_el), -R_dome_out * math.cos(s_el) * math.sin(s_az)),
                ax,
                ay,
            )
            star_nodes.append([int(round(sx_s)), int(round(sy_s))])

        # Brass crown oculus collar at elev > 1.24
        is_oculus = ok_d & (el_h >= 1.24)
        gb = shade_band_np(lit_d, len(pal_g))
        rgba_d[is_oculus] = pal_g[gb[is_oculus]]
        mat_d[is_oculus] = MAT_GOLD

        cv._commit_ss(dx0, dx1, dy0, dy1, ss_d, ok_d, best_dome_t, rgba_d, mat_d, glow_d, dome_oid, min_cov=2)

    # 4. 5 Soaring Curved Sandstone-and-Brass Meridian Ribs arching open across the shattered SE half!
    # Ribs at ENE (28 deg) & E (-4 deg) anchor cleanly down onto solid drum piers;
    # shattered courtyard ribs at SE (-36 deg), SSE (-68 deg), SSW (-108 deg) soar out from apex
    # and terminate naturally in broken jagged sandstone ruin tips cleanly ABOVE portal crown!
    rib_specs = [
        (math.radians(28), 0.00),     # ENE -> lands squarely on drum pier
        (math.radians(-4), 0.00),     # E   -> lands squarely on East drum pier
        (math.radians(-36), 0.16),    # SE  -> ruined shattered cantilevered tip
        (math.radians(-68), 0.22),    # SSE -> ruined cantilevered arch stump
        (math.radians(-108), 0.25),   # SSW -> ruined cantilevered arch stump
    ]
    for ri, (phi, el_min) in enumerate(rib_specs):
        ca, sa = math.cos(phi), math.sin(phi)
        n_seg = 16
        pts_rib = []
        for s_i in range(n_seg + 1):
            t_seg = s_i / n_seg
            el = el_min * math.pi * 0.5 + t_seg * (math.pi * 0.46 - el_min * math.pi * 0.5)
            rr = R_dome_out * math.cos(el)
            yy = Y_dome_base + H_dome * math.sin(el)
            pts_rib.append((rr * ca, yy, -rr * sa))

        for s_i in range(n_seg):
            p0 = pts_rib[s_i]
            p1 = pts_rib[s_i + 1]
            is_broken_tip = (el_min > 0.05) and (s_i == 0)
            is_brass_collar = (not is_broken_tip) and ((s_i % 4 == 2) or (s_i >= n_seg - 2))
            r_rad = (2.4 if is_broken_tip else 3.4) - 0.8 * (s_i / n_seg)
            mat_seg = MAT_GOLD if is_brass_collar else MAT_SANDSTONE

            def paint_rib(ok_r, bp, bn, lit_r, rgba_r, mat_r, glow_r, _brass=is_brass_collar, _tip=is_broken_tip) -> None:
                if _tip:
                    # Jagged shadowed fractured sandstone & exposed brass core at broken arch tip
                    sb_t = shade_band_np(lit_r - 0.18, len(SANDSTONE))
                    rgba_r[:] = np.array(SANDSTONE, dtype=np.uint8)[sb_t]
                    glow_r[ok_r & (bp[..., 1] < 1.2)] = (*TURQ[2][:3], 130)
                elif not _brass:
                    # Crisp darker underside bevel + thin brass trim ridge
                    lit_b = np.where(bn[..., 1] < -0.15, lit_r - 0.25, lit_r + 0.08)
                    rgba_r[:] = np.array(SANDSTONE, dtype=np.uint8)[shade_band_np(lit_b, len(SANDSTONE))]
                    is_trim = ok_r & (np.abs(bp[..., 2]) > 1.8)
                    gb_r = shade_band_np(lit_r, len(GOLD))
                    rgba_r[is_trim] = np.array(GOLD, dtype=np.uint8)[gb_r[is_trim]]
                    mat_r[is_trim] = MAT_GOLD
                else:
                    pip = ok_r & (np.abs(bp[..., 1] - 2.2) < 1.1) & (bp[..., 2] > 0.0)
                    rgba_r[pip] = TURQ[2]
                    glow_r[pip] = (*TURQ[2][:3], 185)

            cv.render_cylinder(p0, p1, r_rad, r_rad * 0.95, mat_seg, ss=2, paint_fn=paint_rib)

    # 5. Tall Golden Astral Lightning Spire rising from dome apex (y_up = 144 -> 221 -> apex ~ y = 20!)
    Y_apex_dome = Y_dome_base + H_dome - 2.0  # ~144
    # Ornate octagonal brass & quartz crown oculus cap at dome apex
    cv.render_ring_band(
        (0.0, Y_apex_dome + 2.0, 0.0),
        rot_x(math.pi / 2.0),
        r_in=6.5,
        r_out=13.0,
        half_h=2.8,
        mat=MAT_GOLD,
        ss=2,
    )
    # Central glowing quartz apex keystone inside oculus
    cv.render_facet_crystal((0.0, Y_apex_dome + 5.5, 0.0), np.eye(3), rx=6.0, ry_top=6.5, ry_bot=3.5, n_sides=8, glow_mode="turq", ss=2)

    # Tall tapered golden-brass conductor spire up to Y = 213 -> sy ≈ 27 (crystal tip up to sy ≈ 20!)
    cv.render_cylinder((0.0, Y_apex_dome + 4.5, 0.0), (0.0, Y_apex_dome + 22.0, 0.0), 4.6, 2.8, MAT_GOLD, ss=2)
    cv.render_cylinder((0.0, Y_apex_dome + 22.0, 0.0), (0.0, Y_apex_dome + 67.0, 0.0), 2.6, 1.3, MAT_GOLD, ss=2)

    # 4 surrounding quartz resonance prongs near spire foot
    for ang_p in (0.25 * math.pi, 0.75 * math.pi, 1.25 * math.pi, 1.75 * math.pi):
        px_p, pz_p = math.cos(ang_p) * 6.2, math.sin(ang_p) * 6.2
        tilt_p = rot_y(-ang_p) @ rot_z(-0.26)
        cv.render_facet_crystal((px_p, Y_apex_dome + 11.5, pz_p), tilt_p, rx=2.0, ry_top=7.5, ry_bot=3.0, n_sides=4, glow_mode="turq", ss=2)

    # Dual tilted celestial astrolabe gimbal rings orbiting mid-spire (Y = Y_apex_dome + 42)
    Y_gimbal = Y_apex_dome + 42.0
    cv.render_ring_band((0.0, Y_gimbal, 0.0), rot_x(0.45) @ rot_y(0.35), r_in=9.5, r_out=12.5, half_h=1.4, mat=MAT_GOLD, ss=3)
    cv.render_ring_band((0.0, Y_gimbal, 0.0), rot_x(-0.55) @ rot_z(0.55), r_in=6.8, r_out=9.0, half_h=1.2, mat=MAT_QUARTZ, ss=3)

    # Glowing Astral Lightning Finial Crystal at the very spire apex!
    Y_finial = Y_apex_dome + 70.0  # ~214 -> tip at ~222 -> sy ≈ 20!
    cv.render_facet_crystal((0.0, Y_finial, 0.0), rot_y(0.35), rx=4.2, ry_top=8.2, ry_bot=4.5, n_sides=6, glow_mode="solar", ss=3)

    px, glow = cv.finalize_with_outlines(foot_cut_y=212, add_internal_creases=True, halo_alpha=0.28, halo_max_y=210)
    apex_sx, apex_sy = project_pt((0.0, Y_finial + 8.2, 0.0), ax, ay)
    oc_sx, oc_sy = project_pt((0.0, Y_apex_dome + 6.0, 0.0), ax, ay)
    meta = {
        "file": "rotunda_vault.png",
        "glow": "rotunda_vault_glow.png",
        "size": [W, H],
        "feet": [128, 206],
        "apex": [int(round(apex_sx)), int(round(apex_sy))],
        "oculus": [int(round(oc_sx)), int(round(oc_sy))],
        "drum_radius": int(R_drum),
        "courtyard_span_x": [72, 184],
        "star_nodes": star_nodes,
    }
    return px, glow, meta


# ------------------------------------------------------------------------------
# ASSET 3: rotunda_flanks (2x1 of 104x144 = 208x144, feet (52, 122))
# ------------------------------------------------------------------------------
def make_rotunda_flank(variant: int) -> tuple[list, list, dict]:
    """True 3D cylindrical ashlar buttress towers: recessed 3/4 flat roof deck
    encircled by stone battlements (Aufsicht), overhanging crown cornice casting
    crisp 3-4 px shadow down curved shaft, stepped base plinths, plus (Col 0)
    recessed stone astrolabe housing or (Col 1) true 3D curved wraparound stairs."""
    W, H = 104, 144
    fx, fy = 52.0, 122.0
    cv = Canvas(W, H, fx, fy)

    # Tight ground contact shadow hugging base plinth SE
    cv.draw_ground_shadow(fx + 3.0, fy + 4.0, 29.0, 13.0, max_alpha=68)

    # Astrolabe hub world position on front-SE face of Col 0 cylinder
    n_ast = np.array([0.24, 0.0, 0.97], dtype=np.float64)
    n_ast /= np.linalg.norm(n_ast)
    R_ast = basis_from_normal(n_ast)
    ast_center = np.array([5.8, 48.0, 22.8], dtype=np.float64)

    # Precompute 8 rotated step poses for Col 1 curved wraparound staircase
    step_poses = []
    if variant == 1:
        for s_i in range(8):
            ang_s = math.radians(74.0 - s_i * 19.0)  # wraps from SE (+74 deg) around East (0 deg) toward NE (-59 deg)
            y_top = 6.5 + s_i * 6.5
            step_poses.append((s_i, ang_s, math.cos(ang_s), math.sin(ang_s), y_top))

    def sdf_flank(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        x, y, z = p[..., 0], p[..., 1], p[..., 2]

        # 1. Main Cylindrical Tower Shaft (r=22.2, y=0..89 -> leaves 3/4 roof deck open at y=89!)
        d_shaft = sd_cyl_y(p, (0.0, 44.5, 0.0), r=22.2, hh=44.5)
        # Stepped Basal Plinths (Sockel)
        d_p1 = sd_cyl_y(p, (0.0, 5.5, 0.0), r=25.0, hh=5.5)
        d_p2 = sd_cyl_y(p, (0.0, 12.2, 0.0), r=23.6, hh=2.4)
        d_base = np.minimum(d_shaft, np.minimum(d_p1, d_p2))

        # 2. Brass Zodiac Collar Band (y=67..72.5, r=22.9)
        d_band = sd_cyl_y(p, (0.0, 69.8, 0.0), r=22.9, hh=2.8)

        # 3. Overhanging Crown Cornice Ring (y=83..89.5, r=25.4 -> projects 3.2 px!)
        d_corn = sd_cyl_y(p, (0.0, 86.2, 0.0), r=25.4, hh=3.2)

        # 4. Recessed Roof Parapet Wall + 8 Crenellated Merlons around Roof Deck (y=89..98)
        d_par_low = sd_ring_y(p, (0.0, 91.5, 0.0), r_in=17.6, r_out=24.8, hh=2.6)
        ang = np.arctan2(z, x)
        ang_cell = np.abs(((ang + math.pi / 8.0) % (math.pi / 4.0)) - math.pi / 8.0)
        d_merlon_arc = np.maximum(
            sd_ring_y(p, (0.0, 96.2, 0.0), r_in=17.8, r_out=24.8, hh=2.8),
            (ang_cell - 0.21) * 20.0,
        )
        if variant == 1:
            # Chipped broken upper-right battlement gap on East tower
            ruined = (ang > -0.25) & (ang < 1.25) & (x > 6.0)
            d_merlon_arc = np.where(ruined, d_merlon_arc + 8.0, d_merlon_arc)
            d_par_low = np.where((ang > 0.10) & (ang < 0.90) & (p[..., 1] > 91.5), d_par_low + 4.0, d_par_low)
        d_roof_wall = np.minimum(d_par_low, d_merlon_arc)

        d_best = np.minimum(np.minimum(d_base, d_roof_wall), np.minimum(d_band, d_corn))
        tag = np.where(d_band <= np.minimum(d_base, np.minimum(d_roof_wall, d_corn)), 2, 1)

        if variant == 0:
            # West outward buttress shoulder cylinder (-19, y=0..56, r=11.6) + plinth + cap cornice
            d_w = sd_cyl_y(p, (-19.0, 28.0, -2.0), r=11.6, hh=28.0)
            d_wp = sd_cyl_y(p, (-19.0, 5.5, -2.0), r=13.5, hh=5.5)
            d_wc = sd_cyl_y(p, (-19.0, 55.5, -2.0), r=13.1, hh=2.6)
            d_wb = sd_cyl_y(p, (-19.0, 39.0, -2.0), r=12.1, hh=2.2)
            d_shoul = np.minimum(np.minimum(d_w, d_wp), d_wc)
            tag = np.where(d_wb < np.minimum(d_best, d_shoul), 2, np.where(d_shoul < d_best, 1, tag))
            d_best = np.minimum(d_best, np.minimum(d_shoul, d_wb))

            # Projecting Stone Astrolabe Housing Ring + Recessed Cavity + 3D Brass Wheel Relief!
            pa = (p - ast_center) @ R_ast
            r_pa = np.hypot(pa[..., 0], pa[..., 1])
            # Stone outer ring bezel (r=11.2..14.8, z in [-3..+2.8]) + dark stone cavity backing z=-2.2
            d_bez = np.maximum(
                np.hypot(np.maximum(np.maximum(r_pa - 14.5, 11.2 - r_pa), 0.0), np.maximum(np.abs(pa[..., 2]) - 2.6, 0.0))
                + np.minimum(np.maximum(np.maximum(r_pa - 14.5, 11.2 - r_pa), np.abs(pa[..., 2]) - 2.6), 0.0),
                -r_pa + 11.1 if False else -1e9,
            )
            # Clean stone cylindrical disk recessed cavity (`z <= 0.2`) inside r_pa<=11.4, and brass wheel at z in [0.0..+2.4]!
            d_cav_back = np.hypot(np.maximum(r_pa - 11.5, 0.0), np.maximum(np.abs(pa[..., 2] + 1.6) - 1.6, 0.0)) + np.minimum(np.maximum(r_pa - 11.5, np.abs(pa[..., 2] + 1.6) - 1.6), 0.0)
            in_wheel_ring = np.maximum(r_pa - 10.6, 7.6 - r_pa)
            in_spoke = np.minimum(np.abs(pa[..., 0]), np.abs(pa[..., 1])) - 1.25
            in_hub = r_pa - 3.0
            d_w_xy = np.minimum(np.minimum(in_wheel_ring, np.maximum(in_spoke, r_pa - 10.6)), in_hub)
            d_brass_w = np.hypot(np.maximum(d_w_xy, 0.0), np.maximum(np.abs(pa[..., 2] - 1.0) - 1.4, 0.0)) + np.minimum(np.maximum(d_w_xy, np.abs(pa[..., 2] - 1.0) - 1.4), 0.0)

            d_bez_all = np.minimum(d_bez, d_cav_back)
            tag = np.where(d_brass_w < np.minimum(d_best, d_bez_all), 4, np.where(d_cav_back < np.minimum(d_best, d_bez), 5, np.where(d_bez < d_best, 3, tag)))
            d_best = np.minimum(d_best, np.minimum(d_bez_all, d_brass_w))
        else:
            # East Curved Exterior Staircase wrapping cleanly around East cylinder!
            for s_i, ang_s, ca_s, sa_s, y_top in step_poses:
                # Rotate XZ into radial u (outward along ang_s), tangential v
                u = x * ca_s + z * sa_s
                v = -x * sa_s + z * ca_s
                y_bot = max(0.0, y_top - 10.0)
                # Step main stone body (u in [20.5..33.0], |v|<=6.0, y in [y_bot..y_top-1.4])
                du_m = np.abs(u - 26.8) - 6.2
                dv_m = np.abs(v) - 6.0
                dy_m = np.abs(y - 0.5 * (y_bot + y_top - 1.4)) - 0.5 * (y_top - 1.4 - y_bot)
                d_body = np.hypot(np.maximum(du_m, 0.0), np.hypot(np.maximum(dv_m, 0.0), np.maximum(dy_m, 0.0))) + np.minimum(np.maximum(du_m, np.maximum(dv_m, dy_m)), 0.0)
                # Overhanging bullnose step tread slab (u in [20.5..34.2], |v|<=6.6, y in [y_top-1.6..y_top])
                du_n = np.abs(u - 27.35) - 6.85
                dv_n = np.abs(v) - 6.6
                dy_n = np.abs(y - (y_top - 0.8)) - 0.8
                d_nose = np.hypot(np.maximum(du_n, 0.0), np.hypot(np.maximum(dv_n, 0.0), np.maximum(dy_n, 0.0))) + np.minimum(np.maximum(du_n, np.maximum(dv_n, dy_n)), 0.0)
                d_step = np.minimum(d_body, d_nose)
                tag = np.where(d_step < d_best, 6, tag)
                d_best = np.minimum(d_best, d_step)

        return d_best, tag

    def paint_flank(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
        num = p.shape[0]
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        ang = np.arctan2(z, x)
        lit_base = n @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
        lit_eff -= (1.0 - ao) * 0.36

        # Curved cylindrical u coordinate for authentic wrapping ashlar stones
        u_cyl = ang * 23.0 + (x + z) * 0.15
        rgba = ashlar_shade_3d(u_cyl, y, lit_eff, MAT_SANDSTONE, course_h=7.2, block_w=12.5, seed=210 + variant * 29)
        mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        # Roof deck center inset star-slate & brass compass plate (top face inside parapet r<17.6 at y~89)
        on_roof_deck = (y >= 88.2) & (np.hypot(x, z) <= 17.6) & (n[..., 1] > 0.7)
        r_deck = np.hypot(x, z)
        deck_slate = on_roof_deck & (r_deck <= 14.5)
        deck_ring = on_roof_deck & (r_deck >= 12.2) & (r_deck <= 14.8)
        i_pal = np.array(INDIGO, dtype=np.uint8)
        g_pal = np.array(GOLD, dtype=np.uint8)
        rgba = np.where(deck_slate[..., None], i_pal[shade_band_np(lit_eff, len(INDIGO))], rgba)
        rgba = np.where(deck_ring[..., None], g_pal[shade_band_np(lit_eff + 0.15, len(GOLD))], rgba)
        mat = np.where(deck_ring, MAT_GOLD, np.where(deck_slate, MAT_INDIGO, mat))

        # Brass collar & trim (tag == 2 or 4)
        is_gold = (tag == 2) | (tag == 4)
        gold_c = g_pal[shade_band_np(lit_eff + 0.10, len(GOLD))]
        # Verdigris & zodiac glyphs along main zodiac collar (tag==2 & y>60)
        z_glyph = (tag == 2) & (y > 67.8) & (y < 71.8) & (np.abs(((ang * 12.0) % math.pi) - math.pi * 0.5) < 0.28)
        rgba = np.where(is_gold[..., None], gold_c, rgba)
        mat = np.where(is_gold, MAT_GOLD, mat)
        rgba = np.where(z_glyph[..., None], TURQ[2], rgba)
        glow = np.where(z_glyph[..., None], (*TURQ[2][:3], 170), glow)

        # Recessed Astrolabe Stone Bezel (tag==3) & Dark Star-Slate Cavity (tag==5)
        rgba = np.where((tag == 5)[..., None], i_pal[shade_band_np(lit_eff - 0.15, len(INDIGO))], rgba)
        mat = np.where(tag == 5, MAT_INDIGO, mat)

        if variant == 0:
            # Diagonal White Sinter-Quartz vein cleaving NW curved shaft blocks
            vein_d = np.abs((x + 11.0) * 0.85 + (y - 54.0) * 0.65)
            on_vein = (tag == 1) & (vein_d < 1.8) & (z > 4.0) & (y >= 26.0) & (y <= 78.0)
            q_pal = np.array(QUARTZ_W, dtype=np.uint8)
            rgba = np.where(on_vein[..., None], q_pal[shade_band_np(lit_eff + 0.18, len(QUARTZ_W))], rgba)
            mat = np.where(on_vein, MAT_QUARTZ, mat)
            vein_gl = on_vein & (vein_d < 0.75) & ((np.floor(y).astype(np.int32) % 4) == 1)
            rgba = np.where(vein_gl[..., None], TURQ[2], rgba)
            glow = np.where(vein_gl[..., None], (*TURQ[2][:3], 175), glow)

            # Astrolabe center Solar jewel & 4 turquoise cardinal nodes on tag==4
            pa = (p - ast_center) @ R_ast
            r_pa = np.hypot(pa[..., 0], pa[..., 1])
            is_solar = (tag == 4) & (r_pa < 1.8)
            is_node = (tag == 4) & (np.abs(r_pa - 9.0) < 1.3) & ((np.abs(pa[..., 0]) < 1.4) | (np.abs(pa[..., 1]) < 1.4))
            rgba = np.where(is_solar[..., None], SOLAR[2], np.where(is_node[..., None], TURQ[3], rgba))
            mat = np.where(is_solar | is_node, MAT_QUARTZ, mat)
            glow = np.where(is_solar[..., None], (*SOLAR[1][:3], 210), np.where(is_node[..., None], (*TURQ[2][:3], 185), glow))
        else:
            # Vertical glowing Sinter-Quartz seam running up inner West curved face of East tower!
            on_seam = (tag == 1) & (x < -11.0) & (np.abs(z - 12.0 - 2.0 * np.sin(y * 0.16)) < 2.2) & (y >= 16.0) & (y <= 76.0)
            q_pal = np.array(QUARTZ_W, dtype=np.uint8)
            rgba = np.where(on_seam[..., None], q_pal[shade_band_np(lit_eff + 0.12, len(QUARTZ_W))], rgba)
            mat = np.where(on_seam, MAT_QUARTZ, mat)
            seam_gl = on_seam & (np.abs(z - 12.0 - 2.0 * np.sin(y * 0.16)) < 0.9) & ((np.floor(y).astype(np.int32) % 3) != 0)
            rgba = np.where(seam_gl[..., None], TURQ[2], rgba)
            glow = np.where(seam_gl[..., None], (*TURQ[2][:3], 170), glow)

            # Subtle mortar accent on stair steps (tag==6): keep treads bright sunlit, risers darker with block joints
            on_tread = (tag == 6) & (n[..., 1] > 0.65)
            step_col = ashlar_shade_3d(x + z, y, np.where(on_tread, lit_eff + 0.12, lit_eff - 0.08), MAT_SANDSTONE, course_h=5.2, block_w=9.0, seed=257)
            rgba = np.where((tag == 6)[..., None], step_col, rgba)

        # Subtle lowest-2px base dust transition ONLY at ground foot (zero floating blobs!)
        at_foot = (y < 2.2) & (n[..., 1] < 0.4) & (lit_eff > -0.15)
        rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
        mat = np.where(at_foot, MAT_SAND, mat)

        return rgba, mat, glow

    render_csg(cv, (2, W - 2, 2, H - 2), (-75.0, 75.0), sdf_flank, paint_flank, ss=2, n_steps=64, shadow_steps=16, margin=2)

    hx, hy = project_pt(ast_center if variant == 0 else np.array([-16.0, 48.0, 12.0]), fx, fy)
    px, glow = cv.finalize_with_outlines(foot_cut_y=128, add_internal_creases=True, halo_alpha=0.24, halo_max_y=124)
    return px, glow, {"astrolabe_hub": [int(round(hx)), int(round(hy))]}


# ------------------------------------------------------------------------------
# ASSET 4: rotunda_portal (136x136, feet (68, 114))
# ------------------------------------------------------------------------------
def make_rotunda_portal() -> tuple[list, list, dict]:
    """Das Versiegelte Sternentor: deep projecting 3D entrance portico (sloped roof Aufsicht,
    flanking ashlar pilasters, deep 14 px barrel-vaulted archway cavern with dark shadowed
    left soffit & bounce-lit right soffit receding back to recessed Star-Slate double doors),
    3 monumental stepped sandstone stairs with overhanging nosing shadows & 3D stone balustrades,
    sealed by 3 interlocking golden & turquoise Star-Locks."""
    W, H = 136, 140
    fx, fy = 68.0, 114.0
    cv = Canvas(W, H, fx, fy)

    # Tight ground contact shadow under stair apron & wing bastions SE
    cv.draw_ground_shadow(fx + 3.0, fy + 7.5, 52.0, 11.0, max_alpha=68)

    # World coordinates for the 3 recessed Star-Locks on Z_door = -2.2 inside the barrel vault!
    Z_door = -2.2
    lock_pts_w = [
        np.array([0.0, 53.0, Z_door], dtype=np.float64),
        np.array([-11.5, 31.0, Z_door], dtype=np.float64),
        np.array([11.5, 31.0, Z_door], dtype=np.float64),
    ]

    def sdf_portal(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        x, y, z = p[..., 0], p[..., 1], p[..., 2]

        # 1. Rear Bastion Curtain Wings connecting Portal solidly to W/E Rotunda Flank Towers (|X|<=53, Z in [-9..+3], Y in [0..66])
        d_tun = sd_arch_tunnel_z(p, cx=0.0, y_bot=13.5, y_spring=52.0, r_arch=21.5, cz=8.5, hz=10.6)
        d_wings = np.maximum(sd_box(p, (0.0, 33.0, -3.0), (53.0, 33.0, 6.0)), -d_tun)
        d_wing_corn = np.maximum(sd_box(p, (0.0, 66.5, -2.5), (54.0, 2.5, 7.2)), -d_tun)
        d_wing_pl = np.maximum(sd_box(p, (0.0, 5.5, -2.5), (54.5, 5.5, 7.2)), -d_tun)

        # 2. Projecting Portico Main Mass (|X|<=39, Y in [12..82], Z in [-6..+14]) minus 16 px Deep Barrel-Vault Arch Tunnel!
        d_block = sd_box(p, (0.0, 47.0, 4.0), (39.0, 35.0, 10.0))
        d_portico = np.maximum(d_block, -d_tun)

        # 3. Recessed Star-Slate Double Doors sitting deep inside vault at Z = [-6 .. -2.0]
        d_doors = sd_arch_tunnel_z(p, cx=0.0, y_bot=13.5, y_spring=52.0, r_arch=21.8, cz=-4.0, hz=2.0)

        # 4. Projecting Flanking Ashlar Pilasters (X = +-32.5, Z in [+8..+17], Y in [13..78])
        d_pil = np.minimum(
            sd_box(p, (-32.5, 45.5, 12.5), (6.5, 32.5, 4.5)),
            sd_box(p, (32.5, 45.5, 12.5), (6.5, 32.5, 4.5)),
        )
        d_pil_cap = np.minimum(
            sd_box(p, (-32.5, 79.0, 13.0), (7.6, 2.2, 5.5)),
            sd_box(p, (32.5, 79.0, 13.0), (7.6, 2.2, 5.5)),
        )

        # 5. Projecting Front Arch Voussoir Ring (Z in [+12..+16.2], outer arch r=31.0 around (0, 52))
        d_ring_front = np.maximum(
            sd_arch_tunnel_z(p, cx=0.0, y_bot=51.0, y_spring=52.0, r_arch=30.5, cz=14.1, hz=2.1),
            -sd_arch_tunnel_z(p, cx=0.0, y_bot=13.5, y_spring=52.0, r_arch=21.4, cz=14.1, hz=2.5),
        )

        # 6. 3/4 Sloped / Stepped Stone & Brass Portico Crown Roof overhanging top (Y in [81..104], Z in [-6..+18])
        d_cornice = sd_box(p, (0.0, 82.8, 5.5), (42.5, 2.6, 13.5))  # Overhangs front face by 4 px!
        d_roof_1 = sd_box(p, (0.0, 88.5, 4.0), (39.0, 3.8, 11.2))
        d_roof_2 = sd_box(p, (0.0, 95.0, 2.2), (31.5, 3.5, 8.8))
        d_roof_3 = sd_box(p, (0.0, 100.5, 0.5), (16.5, 2.6, 6.2))
        d_roof_all = np.minimum(d_cornice, np.minimum(d_roof_1, np.minimum(d_roof_2, d_roof_3)))

        # 7. 3 Monumental Sandstone Entrance Steps with Protruding Bullnose Overhangs (Z in [+12..+33])
        d_st3 = sd_box(p, (0.0, 7.0, 16.5), (34.0, 7.0, 5.0))   # y_top = 14.0
        d_n3 = sd_box(p, (0.0, 13.1, 17.0), (34.2, 0.9, 5.8))   # protruding nosing lip
        d_st2 = sd_box(p, (0.0, 4.8, 22.5), (35.5, 4.8, 5.0))   # y_top = 9.6
        d_n2 = sd_box(p, (0.0, 8.7, 23.0), (35.7, 0.9, 5.8))
        d_st1 = sd_box(p, (0.0, 2.6, 28.0), (37.0, 2.6, 4.8))   # y_top = 5.2
        d_n1 = sd_box(p, (0.0, 4.4, 28.5), (37.2, 0.8, 5.5))
        d_steps = np.minimum(np.minimum(d_st3, d_n3), np.minimum(np.minimum(d_st2, d_n2), np.minimum(d_st1, d_n1)))

        # 8. Flanking 3D Stepped Balustrades / Stair Cheek-Walls (Treppenwangen, |X| in [34..42]) + End Newels!
        d_cheek = np.minimum(
            np.minimum(
                sd_box(p, (-38.5, 7.8, 21.5), (4.2, 7.8, 10.5)),
                sd_box(p, (38.5, 7.8, 21.5), (4.2, 7.8, 10.5)),
            ),
            np.minimum(
                sd_box(p, (-38.5, 5.5, 30.5), (4.8, 5.5, 4.2)),
                sd_box(p, (38.5, 5.5, 30.5), (4.8, 5.5, 4.2)),
            ),
        )

        # Combine cleanly with Material Tagging!
        d_stone = np.minimum(np.minimum(d_wings, np.minimum(d_wing_corn, d_wing_pl)), np.minimum(d_portico, np.minimum(d_pil, np.minimum(d_roof_all, np.minimum(d_steps, d_cheek)))))
        # Crown roof crest & pilaster capitals -> brass accents
        d_brass = np.minimum(d_pil_cap, sd_box(p, (0.0, 103.5, 0.5), (14.0, 1.4, 4.5)))
        # Golden Sun-Keystone projecting cleanly at crown of front arch
        d_keystone = sd_box(p, (0.0, 78.5, 15.2), (4.2, 5.0, 2.2))
        d_brass = np.minimum(d_brass, d_keystone)

        d_best = np.minimum(d_stone, np.minimum(d_doors, np.minimum(d_ring_front, d_brass)))
        tag = np.where(
            d_doors <= np.minimum(d_stone, np.minimum(d_ring_front, d_brass)),
            4,
            np.where(
                d_brass <= np.minimum(d_stone, d_ring_front),
                2,
                np.where(d_ring_front < d_stone, 3, 1),
            ),
        )
        return d_best, tag

    def paint_portal(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
        num = p.shape[0]
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        lit_base = n @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
        lit_eff -= (1.0 - ao) * 0.38

        # Strong realistic 3D barrel-vault tunnel attenuation as Z recedes back toward the dark door cavern!
        in_tunnel_wall = (np.abs(x) <= 23.5) & (z >= -2.5) & (z <= 13.5) & (y >= 13.5) & (y <= 75.5)
        tun_depth = np.clip((13.5 - z) / 16.0, 0.0, 1.0)
        # Left soffit wall (x < 0, normal +X) sits in deep shadow; right soffit wall (x > 0, normal -X) catches warm bounce light!
        bounce_r = np.where(in_tunnel_wall & (x > 4.0) & (n[..., 0] < -0.35), 0.16 * (1.0 - tun_depth), 0.0)
        lit_eff = np.where(in_tunnel_wall, lit_eff - 0.32 * tun_depth + bounce_r, lit_eff)

        rgba = ashlar_shade_3d(x + z * 0.65, y + z * 0.35, lit_eff, MAT_SANDSTONE, course_h=6.8, block_w=12.0, seed=321)
        mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        # Inlaid vertical white Sinter-Quartz flutes on front pilasters & top cornice trim (tag == 1)
        on_flute = (tag == 1) & (z > 15.0) & (y >= 16.0) & (y <= 74.0) & (np.abs(np.abs(x) - 32.5) < 1.6)
        q_pal = np.array(QUARTZ_W, dtype=np.uint8)
        rgba = np.where(on_flute[..., None], q_pal[shade_band_np(lit_eff + 0.14, len(QUARTZ_W))], rgba)
        mat = np.where(on_flute, MAT_QUARTZ, mat)

        # Front Arch Voussoir Ring (tag == 3): alternating white quartz & sandstone voussoir blocks + inner slate arch
        r_v = np.hypot(x, y - 52.0)
        ang_v = np.arctan2(np.maximum(y - 52.0, 0.0), x)
        v_id = np.floor(ang_v / (math.pi / 11.0)).astype(np.int32)
        v_joint = np.abs((ang_v / (math.pi / 11.0)) - np.round(ang_v / (math.pi / 11.0))) < 0.048
        is_inner_slate = (tag == 3) & (r_v < 24.4)
        is_q_voussoir = (tag == 3) & (r_v >= 24.4) & ((v_id % 2) == 0)
        i_pal = np.array(INDIGO, dtype=np.uint8)
        s_pal = np.array(SANDSTONE, dtype=np.uint8)
        v_col = np.where(
            v_joint[..., None],
            INDIGO[0],
            np.where(
                is_inner_slate[..., None],
                i_pal[shade_band_np(lit_eff + 0.05, len(INDIGO))],
                np.where(is_q_voussoir[..., None], q_pal[shade_band_np(lit_eff + 0.16, len(QUARTZ_W))], s_pal[shade_band_np(lit_eff + 0.08, len(SANDSTONE))]),
            ),
        )
        rgba = np.where((tag == 3)[..., None], v_col, rgba)
        mat = np.where(is_inner_slate | ((tag == 3) & v_joint), MAT_INDIGO, np.where(is_q_voussoir, MAT_QUARTZ, np.where(tag == 3, MAT_SANDSTONE, mat)))

        # Brass Trim & Keystone Sun Jewel (tag == 2)
        g_pal = np.array(GOLD, dtype=np.uint8)
        rgba = np.where((tag == 2)[..., None], g_pal[shade_band_np(lit_eff + 0.12, len(GOLD))], rgba)
        mat = np.where(tag == 2, MAT_GOLD, mat)
        key_jewel = (tag == 2) & (np.abs(x) < 1.6) & (y >= 76.5) & (y <= 80.5) & (z > 15.5)
        rgba = np.where(key_jewel[..., None], SOLAR[2], rgba)
        mat = np.where(key_jewel, MAT_QUARTZ, mat)
        glow = np.where(key_jewel[..., None], (*SOLAR[1][:3], 205), glow)

        # Recessed Heavy Star-Slate Double Doors inside Cavern (tag == 4)
        is_door = tag == 4
        # Keep doors richly shaded inside deep cavern while preserving readable indigo star-slate panels & seam!
        d_lit = lit_eff * 0.70 - 0.18
        door_col = i_pal[shade_band_np(d_lit, len(INDIGO))]
        # Center door vertical seam + recessed carved golden astronomical circle on double leaves
        d_seam = is_door & (np.abs(x) < 0.85)
        r_ring = np.hypot(x, y - 38.5)
        d_gold_ring = is_door & (r_ring >= 13.0) & (r_ring <= 14.6)
        door_col = np.where(d_seam[..., None], INDIGO[0], np.where(d_gold_ring[..., None], GOLD[2], door_col))
        rgba = np.where(is_door[..., None], door_col, rgba)
        mat = np.where(is_door & d_gold_ring, MAT_GOLD, np.where(is_door, MAT_INDIGO, mat))

        # 3 Interlocking Turquoise Energy Conduits & Golden-Brass Star-Locks right on the recessed doors!
        for pa_l, pb_l in ((lock_pts_w[0], lock_pts_w[1]), (lock_pts_w[1], lock_pts_w[2]), (lock_pts_w[2], lock_pts_w[0])):
            vx, vy_s = pb_l[0] - pa_l[0], pb_l[1] - pa_l[1]
            vv = vx * vx + vy_s * vy_s + 1e-6
            t_seg = np.clip(((x - pa_l[0]) * vx + (y - pa_l[1]) * vy_s) / vv, 0.0, 1.0)
            cd = np.hypot(x - (pa_l[0] + vx * t_seg), y - (pa_l[1] + vy_s * t_seg))
            on_cond = is_door & (cd < 1.35)
            rgba = np.where(on_cond[..., None], TURQ[2], rgba)
            mat = np.where(on_cond, MAT_QUARTZ, mat)
            glow = np.where(on_cond[..., None], (*TURQ[2][:3], 195), glow)

        for lp in lock_pts_w:
            dx_l, dy_l = x - lp[0], y - lp[1]
            rl = np.hypot(dx_l, dy_l)
            ang_l = np.arctan2(dy_l, dx_l)
            tooth = (np.abs(np.cos(ang_l * 4.0)) > 0.52) & (rl >= 5.2)
            on_lock = is_door & ((rl <= 5.8) | (tooth & (rl <= 7.6)))
            on_core = is_door & (rl <= 3.0)
            l_lit = -0.35 * (dx_l / 6.5) + 0.38 * (dy_l / 6.5) + 0.32
            rgba = np.where(on_lock[..., None], g_pal[shade_band_np(l_lit, len(GOLD))], rgba)
            mat = np.where(on_lock, MAT_GOLD, mat)
            core_c = np.where((dx_l - dy_l <= 0)[..., None], TURQ[3], TURQ[2])
            rgba = np.where(on_core[..., None], core_c, rgba)
            mat = np.where(on_core, MAT_QUARTZ, mat)
            glow = np.where(on_core[..., None], (*TURQ[3][:3], 235), glow)

        # Worn center step highlights & soft foot dust transition ONLY on bottom 1.5px skirt
        at_foot = (y < 1.6) & (n[..., 1] < 0.4) & (lit_eff > -0.15)
        rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
        mat = np.where(at_foot, MAT_SAND, mat)

        return rgba, mat, glow

    render_csg(cv, (2, W - 2, 2, H - 2), (-85.0, 85.0), sdf_portal, paint_portal, ss=2, n_steps=64, shadow_steps=18, margin=2)

    locks_s = [[int(round(project_pt(lp, fx, fy)[0])), int(round(project_pt(lp, fx, fy)[1]))] for lp in lock_pts_w]
    kx_s, ky_s = project_pt((0.0, 78.5, 15.2), fx, fy)
    px, glow = cv.finalize_with_outlines(foot_cut_y=128, add_internal_creases=True, halo_alpha=0.26, halo_max_y=124)
    return px, glow, {
        "file": "rotunda_portal.png",
        "glow": "rotunda_portal_glow.png",
        "size": [W, H],
        "feet": [68, 114],
        "locks": locks_s,
        "keystone": [int(round(kx_s)), int(round(ky_s))],
    }


# ------------------------------------------------------------------------------
# ASSET 5: armillary_rings (12x1 of 144x144 = 1728x144, center (72, 72))
# ------------------------------------------------------------------------------
def make_armillary_frame(frame_idx: int) -> tuple[list, list, dict]:
    """True 3D-projected animation keyframe (0..11, cyclic 0..2*pi) of 3 counter-rotating
    celestial rings orbiting a glowing faceted Zenith Core Crystal."""
    W, H = 144, 144
    cx, cy = 72.0, 72.0
    cv = Canvas(W, H, cx, cy)
    phi = math.tau * (frame_idx / 12.0)

    # 1. Outer Engraved Brass Ecliptic Band (r=48.5..54.5, half_h=4.0, smooth in-plane +phi orbit)
    R_outer = rot_y(0.22 * math.sin(phi)) @ rot_z(0.24 + 0.10 * math.cos(phi)) @ rot_x(-1.12) @ rot_z(phi)

    def paint_outer(ok, pos, n_loc, face, lit, rgba, mat_arr, glow_rgba) -> None:
        th = np.arctan2(pos[..., 1], pos[..., 0])
        # 24 crisp engraved degree notches around band!
        tick_pos = ((th % (math.tau / 24.0)) / (math.tau / 24.0))
        is_notch = (face == 2) & (tick_pos < 0.16) & (np.abs(pos[..., 2]) < 2.6)
        rgba[is_notch] = GOLD[0]
        # Central engraved turquoise-gold hairline channel
        in_groove = (face == 2) & (np.abs(pos[..., 2]) < 0.85)
        rgba[in_groove] = np.where((lit[in_groove] > 0.1)[..., None], SOLAR[1], GOLD[1])
        # Glowing degree pips every 45 deg
        pip = (face == 2) & (np.abs(pos[..., 2]) < 1.2) & (np.abs((th % (math.tau / 8.0)) - math.tau / 16.0) < 0.08)
        rgba[pip] = SOLAR[2]
        glow_rgba[pip] = (*SOLAR[1][:3], 185)

    cv.render_ring_band((0.0, 0.0, 0.0), R_outer, r_in=48.5, r_out=54.5, half_h=4.0, mat=MAT_GOLD, paint_fn=paint_outer, ss=3)

    # Sun & Moon opposing lugs mounted snugly on Outer Brass Ring (at local +X and -X)
    sun_w = R_outer @ np.array([55.0, 0.0, 0.0])
    moon_w = R_outer @ np.array([-55.0, 0.0, 0.0])
    cv.render_ellipsoid(sun_w, (4.3, 4.3, 4.3), MAT_GOLD, ss=2,
                        paint_fn=lambda ok, q, nw, lit, rg, ma, gl: (
                            rg.__setitem__(ok & (q[..., 2] > -0.2), SOLAR[2]),
                            gl.__setitem__(ok, (*SOLAR[1][:3], 205)),
                        ))
    cv.render_ellipsoid(moon_w, (3.9, 3.9, 3.9), MAT_QUARTZ, ss=2,
                        paint_fn=lambda ok, q, nw, lit, rg, ma, gl: (
                            rg.__setitem__(ok & (q[..., 0] < 0.25), TURQ[3]),
                            gl.__setitem__(ok & (q[..., 0] < 0.25), (*TURQ[2][:3], 195)),
                        ))

    # 2. Middle Tilted Quartz Meridian Ring (r=34..39, half_h=3.0, counter-rotating -1*phi)
    R_mid = rot_z(-0.58) @ rot_y(0.54) @ rot_x(-0.88 + 0.24 * math.cos(phi)) @ rot_z(-phi)

    def paint_mid(ok, pos, n_loc, face, lit, rgba, mat_arr, glow_rgba) -> None:
        th = np.arctan2(pos[..., 1], pos[..., 0])
        # 4 Golden brass cardinal clasps around quartz meridian ring
        clasp = np.abs((th % (math.pi * 0.5)) - math.pi * 0.25) > 0.68
        g_b = shade_band_np(lit, len(GOLD))
        rgba[clasp] = np.array(GOLD, dtype=np.uint8)[g_b[clasp]]
        mat_arr[clasp] = MAT_GOLD
        # Glowing turquoise meridian vein
        vein = ok & ~clasp & (face == 2) & (np.abs(pos[..., 2]) < 0.75)
        rgba[vein] = TURQ[2]
        glow_rgba[vein] = (*TURQ[2][:3], 170)

    cv.render_ring_band((0.0, 0.0, 0.0), R_mid, r_in=34.0, r_out=39.0, half_h=3.0, mat=MAT_QUARTZ, paint_fn=paint_mid, ss=3)

    # 3. Inner Fast-Spinning Brass Finder Ring (r=21..25, half_h=2.0, spinning +2*phi!)
    R_inner = rot_z(0.64) @ rot_y(-0.62 + 0.22 * math.sin(phi)) @ rot_x(-0.92) @ rot_z(2.0 * phi)

    def paint_inner(ok, pos, n_loc, face, lit, rgba, mat_arr, glow_rgba) -> None:
        th = np.arctan2(pos[..., 1], pos[..., 0])
        node = (np.abs((th % math.pi) - math.pi * 0.5) < 0.14)
        rgba[node] = TURQ[3]
        glow_rgba[node] = (*TURQ[2][:3], 190)

    cv.render_ring_band((0.0, 0.0, 0.0), R_inner, r_in=21.0, r_out=25.0, half_h=2.0, mat=MAT_GOLD, paint_fn=paint_inner, ss=3)

    # 4. Central Brightly Glowing Faceted Zenith Core Crystal (+ hovering splinter motes)
    R_core = rot_y(phi) @ rot_z(0.12 * math.sin(phi))
    cv.render_facet_crystal((0.0, 0.0, 0.0), R_core, rx=8.5, ry_top=12.5, ry_bot=10.5, n_sides=6, glow_mode="turq", ss=3)
    for mi in range(3):
        ma = phi + mi * (math.tau / 3.0)
        mp = (math.cos(ma) * 14.5, math.sin(phi * 2.0 + mi * 2.1) * 4.5, math.sin(ma) * 14.5)
        cv.render_facet_crystal(mp, rot_y(-ma), rx=2.2, ry_top=3.2, ry_bot=2.5, n_sides=4, glow_mode="solar" if mi == 0 else "turq", ss=2)

    px, glow = cv.finalize_with_outlines(foot_cut_y=None, add_internal_creases=True, halo_alpha=0.28)
    sx_s, sy_s = project_pt(sun_w, cx, cy)
    mx_s, my_s = project_pt(moon_w, cx, cy)
    return px, glow, {"sun": [int(round(sx_s)), int(round(sy_s))], "moon": [int(round(mx_s)), int(round(my_s))]}


# ------------------------------------------------------------------------------
# ASSET 6: telescope_lenses (3x1 of 64x64 = 192x64, center (32, 32))
# ------------------------------------------------------------------------------
def make_telescope_lens(variant: int) -> tuple[list, list]:
    """3 giant levitating optical telescope elements tilted along SW -> NE axis."""
    W, H = 64, 64
    cx, cy = 32.0, 32.0
    cv = Canvas(W, H, cx, cy)

    # Optical axis pointing toward NE (+X, +Y_up, +Z toward viewer so 3/4 aperture opens wide at dot ~0.65!)
    axis_ne = np.array([0.62, 0.72, 0.31], dtype=np.float64)
    axis_ne /= np.linalg.norm(axis_ne)
    R_opt = basis_from_normal(axis_ne)

    if variant == 0:
        # Col 0: Fluted brass & sandstone primary mirror collar holding concave sintered-quartz parabolic lens
        cv.render_ring_band((0.0, 0.0, 0.0), R_opt, r_in=15.0, r_out=22.0, half_h=5.2, mat=MAT_SANDSTONE, ss=3,
                            paint_fn=lambda ok, pos, nl, f, lit, rg, ma, gl: (
                                # Fluted outer sandstone grooves + brass front/rear rings
                                rg.__setitem__((f == 2) & (np.abs(pos[..., 2]) <= 3.2) & (np.sin(np.arctan2(pos[..., 1], pos[..., 0]) * 12.0) < -0.45), SANDSTONE[0]),
                                rg.__setitem__(np.abs(pos[..., 2]) > 3.2, np.array(GOLD, dtype=np.uint8)[shade_band_np(lit, len(GOLD))[np.abs(pos[..., 2]) > 3.2]]),
                                ma.__setitem__(np.abs(pos[..., 2]) > 3.2, MAT_GOLD),
                            ))
        # Outer brass clamp lugs (4 around collar)
        for ang in (0.25 * math.pi, 0.75 * math.pi, 1.25 * math.pi, 1.75 * math.pi):
            lp = R_opt @ np.array([math.cos(ang) * 22.0, math.sin(ang) * 22.0, 0.0])
            cv.render_ellipsoid(lp, (3.2, 3.2, 3.2), MAT_GOLD, ss=2)

        # Concave Sinter-Quartz Parabolic Mirror / Lens disc inside collar
        def paint_parabolic(ok, q, nw, lit, rg, ma, gl) -> None:
            # Simulates concave dish reflection: shadowed under NW rim, bright specular sweep inside SE bowl!
            r2 = q[..., 0] ** 2 + q[..., 1] ** 2
            dish_lit = (q[..., 0] - q[..., 1]) * 0.42 + (r2 * 0.40) - 0.12
            qb = shade_band_np(dish_lit, len(QUARTZ_W))
            rg[:] = np.array(QUARTZ_W, dtype=np.uint8)[qb]
            # Crisp parabolic turquoise sheen arc inside sunlit concave bowl
            arc = ok & (r2 > 0.42) & (r2 < 0.80) & ((q[..., 0] - q[..., 1]) > 0.30)
            rg[arc] = TURQ[3]
            gl[arc] = (*TURQ[2][:3], 175)

        cv.render_ellipsoid(R_opt @ np.array([0.0, 0.0, -1.2]), (16.0, 16.0, 4.5), MAT_QUARTZ, R=R_opt, paint_fn=paint_parabolic, ss=3)

    elif variant == 1:
        # Col 1: Heavy brass filigree cradle holding an octagonal faceted dispersion prism crystal
        cv.render_ring_band((0.0, 0.0, 0.0), R_opt @ rot_y(0.16), r_in=16.5, r_out=21.8, half_h=3.8, mat=MAT_GOLD, ss=3,
                            paint_fn=lambda ok, pos, nl, f, lit, rg, ma, gl: (
                                # Pierced filigree slots around brass ring
                                rg.__setitem__((f == 2) & (np.abs(pos[..., 2]) < 1.3) & ((np.arctan2(pos[..., 1], pos[..., 0]) % (math.pi / 4.0)) < 0.28), GOLD[0]),
                            ))
        # Twin orthogonal thin filigree cradle arc
        cv.render_ring_band((0.0, 0.0, 0.0), R_opt @ rot_x(1.02) @ rot_y(0.35), r_in=14.8, r_out=17.4, half_h=1.6, mat=MAT_GOLD, ss=3)
        # Central Octagonal Faceted Dispersion Prism Crystal
        cv.render_facet_crystal((0.0, 0.0, 0.0), R_opt @ rot_x(math.pi / 2.0) @ rot_z(0.25), rx=10.8, ry_top=11.5, ry_bot=11.5, n_sides=8, glow_mode="prism", ss=3)

    else:
        # Col 2: Slender brass-and-quartz objective ring lens with 1px chromatic rim glints (#78f4e6 / #cbaaff)
        cv.render_ring_band((0.0, 0.0, 0.0), R_opt, r_in=16.2, r_out=20.0, half_h=2.4, mat=MAT_GOLD, ss=3)
        cv.render_ring_band(R_opt @ np.array([0.0, 0.0, 1.4]), R_opt, r_in=14.2, r_out=17.2, half_h=1.4, mat=MAT_QUARTZ, ss=3)

        def paint_obj_lens(ok, q, nw, lit, rg, ma, gl) -> None:
            r = np.hypot(q[..., 0], q[..., 1])
            # Translucent faceted meniscus glass lens with concentric zones + crisp NW highlight
            meniscus = np.where(r > 0.72, 4, np.where(r > 0.42, 3, 2))
            meniscus = np.where(((-q[..., 0] + q[..., 1]) > 0.25) & (r > 0.50), 5, meniscus)
            rg[:] = np.array(QUARTZ_W, dtype=np.uint8)[meniscus]
            # Crisp 1px chromatic aberration rim glints: #78f4e6 on NW rim, #cbaaff on SE rim!
            nw_rim = ok & (r >= 0.85) & (r <= 0.99) & ((-q[..., 0] + q[..., 1]) > 0.22)
            se_rim = ok & (r >= 0.85) & (r <= 0.99) & ((q[..., 0] - q[..., 1]) > 0.22)
            rg[nw_rim] = TURQ[2]   # #78f4e6
            gl[nw_rim] = (*TURQ[2][:3], 200)
            rg[se_rim] = ASTRAL[1]  # #cbaaff
            gl[se_rim] = (*ASTRAL[1][:3], 190)

        cv.render_ellipsoid((0.0, 0.0, 0.0), (14.5, 14.5, 2.8), MAT_QUARTZ, R=R_opt, paint_fn=paint_obj_lens, ss=3)

    px, glow = cv.finalize_with_outlines(foot_cut_y=None, add_internal_creases=True, halo_alpha=0.22)
    return px, glow


# ------------------------------------------------------------------------------
# ASSET 7: sundial_court (240x152, center (120, 96)) + sundial_gnomon (96x148, feet (48, 130))
# ------------------------------------------------------------------------------
def make_sundial_court() -> tuple[list, list, dict]:
    """True 3D Sunken Solar Amphitheater: raised 11 px semicircular northern exedra
    parapet wall (3/4 top coping + vertical curved shadowed inner wall with solar
    recesses), sunken white sinter-quartz & star-slate sundial mosaic floor with
    brass hour rune markers & Zenith Prism Socket, and southern 3D stepped terrace
    plinth with 3 wide central descending sandstone steps & cheek balustrades."""
    W, H = 240, 152
    cx, cy = 120.0, 96.0
    cv = Canvas(W, H, cx, cy)
    rx_w, rz_w = 104.0, 120.0  # North semicircular radii -> top around sy = 96 - (15*0.84 + 120*0.54) = 18

    # Tight ground contact shadow hugging southern stepped plinth edge SE
    cv.draw_ground_shadow(cx + 4.0, cy + 12.0, 98.0, 20.0, max_alpha=66)

    # Precompute 12 engraved hour markers on sunken mosaic floor (Y_up = 4.5, r_norm = 0.70)
    hour_markers = []
    hour_world = []
    for h_i in range(12):
        ang_h = math.pi * ((h_i + 0.5) / 12.0)
        hx = math.cos(ang_h) * rx_w * 0.68
        hz = -math.sin(ang_h) * rz_w * 0.68
        hour_world.append((h_i, hx, hz))
        ihx, ihy = project_pt((hx, 4.5, hz), cx, cy)
        hour_markers.append([int(round(ihx)), int(round(ihy))])

    sec_lim = np.array(
        [0.92 + 0.03 * _ihash(s, 3, 91) if s in (2, 7, 15, 21) else 0.97 + 0.03 * _ihash(s, 5, 91) for s in range(24)],
        dtype=np.float64,
    )
    sec_broken = np.array([1 if s in (2, 7, 15, 21) else 0 for s in range(24)], dtype=np.int8)

    def sundial_hf(x: np.ndarray, z: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        r_norm = np.hypot(x / rx_w, z / rz_w)
        ang = np.arctan2(-z, x)  # 0 East .. pi West for z <= 0
        ang_clip = np.clip(ang, 0.0, math.pi * 0.999)
        sec = np.clip(np.floor((ang_clip / math.pi) * 24.0).astype(np.int32), 0, 23)
        lim = sec_lim[sec]
        broken = sec_broken[sec] == 1

        # 1. Northern Semicircular Bowl & Raised 11 px Parapet Exedra (z <= 2.0)
        in_north = (z <= 2.0) & (r_norm <= lim)
        # Parapet top Y_up=15.0 on [0.835..lim], with 7 carved inner solar niches at [0.835..0.88] dropping to 10.5
        niche_ang = ((ang_clip - 0.14) % (math.pi / 7.0))
        in_niche = (r_norm >= 0.835) & (r_norm <= 0.878) & (np.abs(niche_ang - math.pi / 14.0) < 0.09)
        h_parapet = np.where(broken & (r_norm > 0.90), 11.5, np.where(in_niche, 10.2, 15.0))
        # Sunken dial floor at Y_up=4.5; central Zenith Prism Socket raised to 6.5
        oct_d = np.maximum(np.maximum(np.abs(x) / 13.0, np.abs(z) / 15.0), (np.abs(x) / 13.0 + np.abs(z) / 15.0) * 0.72)
        h_dial = np.where(oct_d <= 1.0, 6.5, 4.5)
        h_north = np.where(r_norm >= 0.835, h_parapet, h_dial)

        # 2. Southern 3D Stepped Terrace Plinth & 3 Wide Central Descending Sandstone Steps (z > 2.0..43.0)
        wing_lim_x = rx_w * 0.94 - np.maximum(z - 2.0, 0.0) * 0.35
        in_south = (z > 2.0) & (z <= 43.0) & (np.abs(x) <= wing_lim_x)
        # Flanking 3D stepped terrace wings (|x| >= 40, z <= 36) at Y_up = 4.5
        in_wings = in_south & (np.abs(x) >= 39.0) & (z <= 36.0)
        # Left & Right 3D stone cheek-balustrades flanking central steps (|x| in [32..40], z <= 42)
        in_cheeks = in_south & (np.abs(x) >= 32.0) & (np.abs(x) < 40.0) & (z <= 42.0)
        h_cheek = np.where(z <= 18.0, 8.5, np.where(z <= 32.0, 6.5, 4.8))
        # 3 Central descending sandstone steps (|x| < 32): Y_up 4.5 -> 3.0 -> 1.5 -> 0!
        in_stairs = in_south & (np.abs(x) < 32.0) & (z <= 41.0)
        h_stairs = np.where(z <= 15.0, 4.5, np.where(z <= 28.0, 3.0, 1.5))

        h = np.where(in_north, h_north, np.where(in_cheeks, h_cheek, np.where(in_wings, 4.5, np.where(in_stairs, h_stairs, 0.0))))
        # Tag: 1=parapet wall, 2=dial mosaic, 3=south steps/wings/cheeks, 4=zenith socket
        tag = np.where(in_north & (oct_d <= 1.0), 4, np.where(in_north & (r_norm >= 0.835), 1, np.where(in_north, 2, 3)))
        return h, tag.astype(np.int32)

    def paint_sundial(
        xh: np.ndarray,
        yh: np.ndarray,
        zh: np.ndarray,
        nh: np.ndarray,
        is_wall: np.ndarray,
        tag_h: np.ndarray,
        sun_vis: np.ndarray,
        ao_h: np.ndarray,
    ):
        num = xh.size
        lit_base = nh @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
        lit_eff -= (1.0 - ao_h) * 0.38

        ang = np.arctan2(-zh, xh)
        r_norm = np.hypot(xh / rx_w, zh / rz_w)
        u_wall = np.where(zh <= 2.0, ang * rx_w * 0.9, xh + zh * 0.5)

        rgba = ashlar_shade_3d(u_wall, yh, lit_eff, MAT_SANDSTONE, course_h=4.8, block_w=11.0, seed=412)
        mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        # Crisp 1px top coping / stair nosing bevel edge
        is_top_lip = is_wall & ((yh > 13.7) | ((tag_h == 3) & (yh > 3.6)))
        rgba = np.where((is_top_lip & (lit_eff > -0.15))[..., None], SANDSTONE[4], rgba)

        # Sunken Semicircular Sundial Mosaic Floor (tag == 2 & ~is_wall)
        on_dial = (~is_wall) & (tag_h == 2)
        wedge = np.floor(np.clip(ang, 0.0, math.pi) / (math.pi / 12.0)).astype(np.int32)
        w_frac = (np.clip(ang, 0.0, math.pi) / (math.pi / 12.0)) - wedge

        g_pal = np.array(GOLD, dtype=np.uint8)
        q_pal = np.array(QUARTZ_W, dtype=np.uint8)
        i_pal = np.array(INDIGO, dtype=np.uint8)
        s_pal = np.array(SANDSTONE, dtype=np.uint8)

        is_rim_brass = on_dial & (r_norm >= 0.775) & (r_norm < 0.835)
        is_hour_plate = on_dial & (r_norm >= 0.62) & (r_norm < 0.775)
        is_wedges = on_dial & (r_norm < 0.62)

        # Hour marker plate alternating dark slate & sandstone slabs with tiny brass center bars
        hp_c = np.where((wedge % 2 == 0)[..., None], s_pal[shade_band_np(lit_eff, len(SANDSTONE))], i_pal[shade_band_np(lit_eff, len(INDIGO))])
        hp_bar = is_hour_plate & (np.abs(w_frac - 0.5) < 0.14) & (r_norm >= 0.66) & (r_norm <= 0.74)
        hp_c = np.where(hp_bar[..., None], GOLD[3], hp_c)

        # Alternating white sinter-quartz & star-slate hour wedges with brass dividers!
        w_div = (w_frac < 0.065) | (w_frac > 0.935)
        wd_c = np.where(
            w_div[..., None],
            GOLD[3],
            np.where((wedge % 2 == 0)[..., None], q_pal[shade_band_np(lit_eff + 0.12, len(QUARTZ_W))], i_pal[shade_band_np(lit_eff, len(INDIGO))]),
        )

        rgba = np.where(is_rim_brass[..., None], g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))], rgba)
        rgba = np.where(is_hour_plate[..., None], hp_c, rgba)
        rgba = np.where(is_wedges[..., None], wd_c, rgba)
        mat = np.where(is_rim_brass | hp_bar | (is_wedges & w_div), MAT_GOLD, mat)
        mat = np.where(is_wedges & (~w_div) & (wedge % 2 == 0), MAT_QUARTZ, np.where((is_wedges & (~w_div)) | (is_hour_plate & (wedge % 2 == 1)), MAT_INDIGO, mat))

        # 12 Glowing Hour Rune Markers on sunken mosaic ring
        for h_i, hx_w, hz_w in hour_world:
            hd = np.hypot(xh - hx_w, zh - hz_w)
            is_mk = (~is_wall) & (hd < 2.2)
            rgba = np.where(is_mk[..., None], SOLAR[2] if h_i % 2 == 0 else TURQ[2], rgba)
            mat = np.where(is_mk, MAT_QUARTZ, mat)
            glow = np.where(is_mk[..., None], (*SOLAR[1][:3], 185) if h_i % 2 == 0 else (*TURQ[2][:3], 175), glow)

        # Raised 3D Brass & Quartz Zenith Prism Socket (tag == 4)
        oct_d = np.maximum(np.maximum(np.abs(xh) / 13.0, np.abs(zh) / 15.0), (np.abs(xh) / 13.0 + np.abs(zh) / 15.0) * 0.72)
        in_sock_wall = is_wall & (oct_d <= 1.05) & (oct_d >= 0.80)
        in_sock_top = (~is_wall) & (tag_h == 4)
        sock_c = np.where(
            (oct_d <= 0.46)[..., None],
            TURQ[3],
            np.where((oct_d <= 0.65)[..., None], QUARTZ_W[5], g_pal[shade_band_np(lit_eff + 0.15, len(GOLD))]),
        )
        rgba = np.where(in_sock_top[..., None], sock_c, np.where(in_sock_wall[..., None], g_pal[shade_band_np(lit_eff, len(GOLD))], rgba))
        mat = np.where(in_sock_top & (oct_d <= 0.65), MAT_QUARTZ, np.where(in_sock_top | in_sock_wall, MAT_GOLD, mat))
        glow = np.where((in_sock_top & (oct_d <= 0.48))[..., None], (*TURQ[3][:3], 215), glow)

        # Subtle flush wind-sand dust ONLY in broken northern outer mortar crevices
        sand_crev = (~is_wall) & (tag_h == 1) & (yh < 12.2) & (r_norm > 0.90)
        sand_c = np.array(SAND_DRIFT, dtype=np.uint8)[shade_band_np(lit_eff + 0.1, len(SAND_DRIFT))]
        rgba = np.where(sand_crev[..., None], sand_c, rgba)
        mat = np.where(sand_crev, MAT_SAND, mat)

        return rgba, mat, glow

    render_heightfield(cv, (2, W - 2, 2, H - 2), h_max=15.5, h_min=0.0, hf_fn=sundial_hf, paint_fn=paint_sundial, ss=2, n_coarse=38, margin=2)

    px, glow = cv.finalize_with_outlines(foot_cut_y=H, add_internal_creases=False, halo_alpha=0.22)
    return px, glow, {
        "file": "sundial_court.png",
        "glow": "sundial_court_glow.png",
        "size": [W, H],
        "center": [120, 96],
        "socket": [120, 96],
        "fan_radii": [104, 65],
        "hour_markers": hour_markers,
    }


def make_sundial_gnomon() -> tuple[list, list, dict]:
    """True 3D CSG stepped octagonal pedestal + thick (11 px) swept triangular
    sandstone-and-brass wedge fin with sunlit NW cheek, shadowed SE thickness wall,
    inlaid turquoise meridian channel, and pierced 3D cylindrical solar eyelet tunnel."""
    W, H = 96, 148
    fx, fy = 48.0, 130.0
    cv = Canvas(W, H, fx, fy)

    # Tight ground contact shadow under octagonal pedestal SE
    cv.draw_ground_shadow(fx + 2.5, fy + 2.5, 24.0, 9.0, max_alpha=68)

    # Rotate wedge fin -0.42 rad around Y so front-left broad face (+w) catches bright sun
    # while right-side 11 px thickness wall (+u back edge) reads in crisp shadowed 3D relief!
    ca_f, sa_f = math.cos(-0.42), math.sin(-0.42)
    eye_u, eye_y = 2.5, 108.5  # Centered inside fin upper boss (~y_screen = 39)
    eye_r = 4.2

    def sdf_gnomon(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        x, y, z = p[..., 0], p[..., 1], p[..., 2]

        # 1. Stepped 3D Octagonal Pedestal Base (Y_up = 0..17)
        d_oct1 = sd_oct_y(p, (0.0, 5.2, 0.0), r=20.0, hh=5.2)
        d_oct2 = sd_oct_y(p, (0.0, 12.2, 0.0), r=15.6, hh=2.6)
        d_collar = sd_oct_y(p, (0.0, 16.0, 0.0), r=14.2, hh=1.6)

        # 2. Thick (11 px in w) Swept Triangular 3D Stone Wedge Fin (Y_up = 15..131)
        # Rotate (x, z) -> (u along blade sweep, w perpendicular thickness)
        u = x * ca_f - z * sa_f
        w = x * sa_f + z * ca_f
        t = np.clip((y - 16.0) / 115.0, 0.0, 1.0)
        boss = 2.6 * np.exp(-((y - eye_y) / 9.5) ** 2)
        u_left = -19.5 + 21.5 * (t ** 0.98) - boss
        u_right = 18.0 - 11.5 * (t ** 0.92) + boss * 0.6
        # Taper thickness cleanly from 11.0 px at base up to 7.2 px at apex!
        w_half = 5.6 - 2.0 * (t ** 0.85)
        u_mid = 0.5 * (u_left + u_right)
        u_half = np.maximum(0.5 * (u_right - u_left), 1.5)
        # Exact 3D wedge shell distance + pierced cylindrical solar eyelet bore along w!
        du = np.abs(u - u_mid) - u_half
        dw = np.abs(w) - w_half
        dy_f = np.maximum(15.5 - y, y - 131.0)
        d_blade_raw = np.maximum(np.maximum(du, dw), dy_f)
        d_eye_hole = np.hypot(u - eye_u, y - eye_y) - eye_r
        d_fin = np.maximum(d_blade_raw, -d_eye_hole)

        # 3. Brass Solar Ring Boss projecting +1.0 px proud on both faces around eyelet bore!
        d_eye_ring = np.hypot(
            np.maximum(np.maximum(np.hypot(u - eye_u, y - eye_y) - (eye_r + 2.6), eye_r - np.hypot(u - eye_u, y - eye_y)), 0.0),
            np.maximum(np.abs(w) - (w_half + 1.0), 0.0),
        ) + np.minimum(
            np.maximum(np.maximum(np.hypot(u - eye_u, y - eye_y) - (eye_r + 2.6), eye_r - np.hypot(u - eye_u, y - eye_y)), np.abs(w) - (w_half + 1.0)),
            0.0,
        )

        # 4. Horizontal brass reinforcement ribs wrapping fin at y = 42, 68, 92
        d_rib1 = np.maximum(np.maximum(du - 0.5, dw - 0.5), np.abs(y - 42.0) - 1.2)
        d_rib2 = np.maximum(np.maximum(du - 0.5, dw - 0.5), np.abs(y - 68.0) - 1.2)
        d_rib3 = np.maximum(np.maximum(du - 0.5, dw - 0.5), np.abs(y - 92.0) - 1.2)
        d_ribs = np.minimum(d_rib1, np.minimum(d_rib2, d_rib3))

        # 5. Top Golden-Quartz Apex Finial above (u=4.8, y=131..138, w=0)
        fin_x = 4.8 * ca_f
        fin_z = -4.8 * sa_f
        d_finial = np.hypot(np.hypot(x - fin_x, z - fin_z), (y - 134.0) * 0.52) - 2.3

        d_stone = np.minimum(np.minimum(d_oct1, d_oct2), d_fin)
        d_brass = np.minimum(d_collar, np.minimum(d_eye_ring, np.minimum(d_ribs, d_finial)))
        d_best = np.minimum(d_stone, d_brass)
        tag = np.where(d_finial <= np.minimum(d_stone, d_brass) + 0.1, 3, np.where(d_brass < d_stone, 2, 1))
        return d_best, tag

    def paint_gnomon(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
        num = p.shape[0]
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        u = x * ca_f - z * sa_f
        w = x * sa_f + z * ca_f

        lit_base = n @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
        lit_eff -= (1.0 - ao) * 0.36

        rgba = ashlar_shade_3d(u + w * 0.8, y, lit_eff, MAT_SANDSTONE, course_h=7.2, block_w=11.0, seed=455)
        mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        g_pal = np.array(GOLD, dtype=np.uint8)
        q_pal = np.array(QUARTZ_W, dtype=np.uint8)

        # Razor-sharp White Sinter-Quartz Leading NW Knife-Edge along front blade spine
        t = np.clip((y - 16.0) / 115.0, 0.0, 1.0)
        boss = 2.6 * np.exp(-((y - eye_y) / 9.5) ** 2)
        u_left = -19.5 + 21.5 * (t ** 0.98) - boss
        on_nw_edge = (tag == 1) & (y >= 17.0) & (u <= u_left + 2.4) & (w > -2.0)
        rgba = np.where(on_nw_edge[..., None], q_pal[shade_band_np(lit_eff + 0.20, len(QUARTZ_W))], rgba)
        mat = np.where(on_nw_edge, MAT_QUARTZ, mat)

        # Recessed Glowing Turquoise & Solar-Gold Meridian Channel up front blade cheek!
        u_chan = u_left + 7.5 * (1.0 - 0.55 * t)
        on_chan = (tag == 1) & (y >= 20.0) & (y <= eye_y - eye_r - 1.5) & (w > 2.0) & (np.abs(u - u_chan) <= 1.1)
        is_hot = (np.floor(y).astype(np.int32) % 8) == 0
        ch_col = np.where(is_hot[..., None], SOLAR[2], TURQ[2])
        rgba = np.where(on_chan[..., None], ch_col, rgba)
        mat = np.where(on_chan, MAT_QUARTZ, mat)
        glow = np.where(on_chan[..., None], np.where(is_hot[..., None], (*SOLAR[1][:3], 205), (*TURQ[2][:3], 175)), glow)

        # Brass Rib Bands & Eyelet Bezel Ring (tag == 2)
        rgba = np.where((tag == 2)[..., None], g_pal[shade_band_np(lit_eff + 0.10, len(GOLD))], rgba)
        mat = np.where(tag == 2, MAT_GOLD, mat)
        # Cardinal turquoise glints on eyelet brass bezel
        on_eye_pip = (tag == 2) & (y > 90.0) & ((np.abs(u - eye_u) < 1.0) | (np.abs(y - eye_y) < 1.0))
        rgba = np.where(on_eye_pip[..., None], TURQ[3], rgba)
        mat = np.where(on_eye_pip, MAT_QUARTZ, mat)
        glow = np.where(on_eye_pip[..., None], (*TURQ[2][:3], 190), glow)

        # Apex Solar-Quartz Finial (tag == 3)
        rgba = np.where((tag == 3)[..., None], SOLAR[2], rgba)
        mat = np.where(tag == 3, MAT_GOLD, mat)
        glow = np.where((tag == 3)[..., None], (*SOLAR[1][:3], 215), glow)

        # Subtle lowest-1.5px pedestal foot blend (NO floating blobs!)
        at_foot = (y < 1.5) & (n[..., 1] < 0.4) & (lit_eff > -0.15)
        rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
        mat = np.where(at_foot, MAT_SAND, mat)

        return rgba, mat, glow

    render_csg(cv, (2, W - 2, 2, H - 2), (-55.0, 55.0), sdf_gnomon, paint_gnomon, ss=2, n_steps=64, shadow_steps=16, margin=2)

    ex_s, ey_s = project_pt((eye_u * ca_f, eye_y, -eye_u * sa_f), fx, fy)
    ax_s, ay_s = project_pt((4.8 * ca_f, 136.5, -4.8 * sa_f), fx, fy)
    px, glow = cv.finalize_with_outlines(foot_cut_y=130, add_internal_creases=True, halo_alpha=0.25, halo_max_y=128)
    return px, glow, {
        "file": "sundial_gnomon.png",
        "glow": "sundial_gnomon_glow.png",
        "size": [W, H],
        "feet": [48, 130],
        "apex": [int(round(ax_s)), int(round(ay_s))],
        "eyelet": [int(round(ex_s)), int(round(ey_s))],
    }


# ------------------------------------------------------------------------------
# ASSET 8: ecliptic_gate (160x136, feet (80, 120)) + gate_ocular (48x48, center (24, 24))
# ------------------------------------------------------------------------------
def make_ecliptic_gate() -> tuple[list, list, dict]:
    """Two monumental 3D-extruded inward-curving crescent sandstone-and-brass pylons separated by an
    unobstructed 64 px walkable arch span (x=48..112 has ZERO stonework near feet), with stepped 3D plinths,
    recessed inner arch soffits (Laibung), projecting brass collars, glowing inner rune conduits, and
    broken faceted summit horns."""
    W, H = 160, 136
    cx, cy = 80.0, 120.0
    cv = Canvas(W, H, cx, cy)

    # Ground shadows strictly under outer left (x~28) & right (x~132) plinth bases — x=48..112 stays clear!
    cv.draw_ground_shadow(28.0, 121.0, 17.5, 7.5, max_alpha=68)
    cv.draw_ground_shadow(132.0, 121.0, 17.5, 7.5, max_alpha=68)

    def sdf_gate(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        ax = np.abs(x)
        is_right = x >= 0.0

        # Asymmetric ruined crescent horn heights flanking gate_ocular cleanly: Left ~116 px, Right ~113 px
        y_top_max = np.where(is_right, 113.0, 116.0)
        t = np.clip(y / 116.0, 0.0, 1.0)

        # Crescent inward sweep (kept >= 35.5 near base so x stays strictly outside 48..112!)
        inward_low = 1.6 * (np.clip(t / 0.45, 0.0, 1.0) ** 1.5)
        u_hi = np.clip((t - 0.45) / 0.55, 0.0, 1.0)
        inward = np.where(t < 0.45, inward_low, 1.6 + 14.2 * (u_hi ** 1.28))

        x_in_shaft = np.maximum(21.7, 37.5 - inward)
        # Outer curve tapers gradually, then sweeps dramatically inward into sharp crescent horn tips
        t_crown = np.clip((t - 0.62) / 0.38, 0.0, 1.0)
        x_out_shaft = 61.5 - inward * 0.78 - 18.0 * (t_crown ** 1.45)
        tooth_step = np.where(
            is_right,
            np.where((y > 95.0) & (y < 100.0), 2.2, np.where((y > 105.0) & (y < 108.5), 1.8, 0.0)),
            np.where((y > 97.0) & (y < 102.0), 2.4, np.where((y > 107.0) & (y < 110.5), 1.8, 0.0)),
        )
        x_out_shaft = np.maximum(x_in_shaft + 3.0, x_out_shaft - tooth_step)

        x_mid = 0.5 * (x_in_shaft + x_out_shaft)
        x_half = 0.5 * (x_out_shaft - x_in_shaft)
        hz_shaft = 7.6 - 1.8 * (t ** 1.5)  # ~15 px base -> ~11.6 px upper horn depth in Z

        # Beveled shaft distance with slanted 3D crescent horn slope along summit
        dx_s = np.abs(ax - x_mid) - x_half
        dz_s = np.abs(z) - hz_shaft
        horn_top_y = y_top_max - 15.0 * (np.clip((ax - x_in_shaft) / 14.0, 0.0, 1.0) ** 0.85)
        dy_top = np.maximum(-y, (y - horn_top_y) * 0.82)
        d_shaft = np.maximum(np.maximum(dx_s, dz_s), dy_top)
        d_shaft = np.maximum(d_shaft, 21.5 - ax)  # strictly clear sky chasm around ocular!

        # Stepped 3D Basal Plinths (Y_up = 0..9 lower terrace, 9..17 upper plinth, strictly ax >= 34.5)
        plinth_x_in = 35.0
        plinth1_x_out = 64.5
        plinth2_x_out = 62.5
        d_p1 = np.maximum(
            np.maximum(np.abs(ax - 0.5 * (plinth_x_in + plinth1_x_out)) - 0.5 * (plinth1_x_out - plinth_x_in), np.abs(z) - 9.8),
            np.maximum(-y, y - 9.0),
        )
        d_p2 = np.maximum(
            np.maximum(np.abs(ax - 0.5 * (plinth_x_in + 1.0 + plinth2_x_out)) - 0.5 * (plinth2_x_out - plinth_x_in - 1.0), np.abs(z) - 8.8),
            np.maximum(8.5 - y, y - 17.0),
        )
        # Overhanging plinth cap molding at Y_up = 15..17.5
        d_pcap = np.maximum(
            np.maximum(np.abs(ax - 0.5 * (plinth_x_in + 0.5 + plinth2_x_out + 0.8)) - 0.5 * (plinth2_x_out - plinth_x_in + 0.3), np.abs(z) - 9.3),
            np.maximum(15.2 - y, y - 17.5),
        )
        d_stone = np.minimum(d_shaft, np.minimum(d_p1, d_p2))

        # Projecting 3D Brass Collar Bands wrapping shaft at Y_up = 48, 76, 98 (+0.8 px proud)
        d_b1 = np.maximum(np.maximum(dx_s - 0.85, dz_s - 0.85), np.abs(y - 49.0) - 1.5)
        d_b2 = np.maximum(np.maximum(dx_s - 0.85, dz_s - 0.85), np.abs(y - 77.0) - 1.5)
        d_b3 = np.maximum(np.maximum(dx_s - 0.80, dz_s - 0.80), np.abs(y - 98.5) - 1.3)
        d_brass = np.minimum(d_pcap * 0.0 + 1e4, np.minimum(d_b1, np.minimum(d_b2, d_b3)))
        # Include projecting plinth brass trim strip at Y_up = 16.5
        d_b0 = np.maximum(np.maximum(np.abs(ax - 0.5 * (plinth_x_in + 0.8 + plinth2_x_out + 0.5)) - 0.5 * (plinth2_x_out - plinth_x_in - 0.3), np.abs(z) - 9.2), np.abs(y - 16.2) - 1.2)
        d_brass = np.minimum(d_brass, d_b0)
        d_stone = np.minimum(d_stone, d_pcap)

        # Carve recessed inner soffit rune groove (-0.6 px into inner arch reveal!)
        in_rune_y = (y >= 21.0) & (y <= 95.0)
        d_groove = np.maximum(
            np.maximum(ax - (x_in_shaft + 0.8), np.abs(z - 1.0) - 1.6),
            np.maximum(21.0 - y, y - 95.0),
        )
        d_stone = np.maximum(d_stone, -d_groove)

        # Glowing quartz crystal horn crown shard projecting slightly from inner horn tip
        y_q_bot = y_top_max - 10.5
        d_quartz = np.maximum(
            np.maximum(np.abs(ax - (x_in_shaft + 1.8)) - 2.3, np.abs(z) - 3.2),
            np.maximum(y_q_bot - y, (y - (y_top_max - 3.5 * np.clip((ax - x_in_shaft) / 4.0, 0.0, 1.0))) * 0.85),
        )

        d_best = np.minimum(d_stone, np.minimum(d_brass, d_quartz))
        tag = np.where(d_quartz < np.minimum(d_stone, d_brass) - 0.05, 3, np.where(d_brass < d_stone, 2, 1))
        # Subtle bevel soften
        return d_best, tag

    def paint_gate(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
        num = p.shape[0]
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        ax = np.abs(x)
        is_right = x >= 0.0

        lit_base = n @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.32, -0.20), lit_base)
        lit_eff -= (1.0 - ao) * 0.36

        # Inner arch soffit (Laibung): left inner faces +X (shadowed overhang), right inner faces -X (sunlit!)
        rgba = ashlar_shade_3d(x * 0.85 + z * 0.9, y, lit_eff, MAT_SANDSTONE, course_h=7.5, block_w=11.0, seed=520)
        mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        # Top surface mortarless sun-bleached ashlar deck on stepped pylon shelves
        on_top_shelf = (tag == 1) & (n[..., 1] > 0.65)
        s_pal = np.array(SANDSTONE, dtype=np.uint8)
        top_c = s_pal[shade_band_np(lit_eff + 0.14, len(SANDSTONE))]
        rgba = np.where(on_top_shelf[..., None], top_c, rgba)

        # Tarnished brass collars (tag == 2) with verdigris accents in shadowed undersides
        g_pal = np.array(GOLD, dtype=np.uint8)
        b_col = g_pal[shade_band_np(lit_eff + 0.10, len(GOLD))]
        verdigris = (tag == 2) & (n[..., 1] < -0.2) & (lit_eff < -0.15)
        b_col = np.where(verdigris[..., None], TURQ[0], b_col)
        rgba = np.where((tag == 2)[..., None], b_col, rgba)
        mat = np.where(tag == 2, MAT_GOLD, mat)

        # Sinter-quartz fractured summit crystal tips (tag == 3)
        q_pal = np.array(QUARTZ_W, dtype=np.uint8)
        q_col = q_pal[shade_band_np(lit_eff + 0.18, len(QUARTZ_W))]
        rgba = np.where((tag == 3)[..., None], q_col, rgba)
        mat = np.where(tag == 3, MAT_QUARTZ, mat)

        # Recessed Inner Soffit Glowing Rune Conduit (along front-inner bevel & inner reveal)
        t = np.clip(y / 116.0, 0.0, 1.0)
        inward = np.where(t < 0.45, 1.6 * (np.clip(t / 0.45, 0.0, 1.0) ** 1.5), 1.6 + 14.2 * (np.clip((t - 0.45) / 0.55, 0.0, 1.0) ** 1.28))
        x_in = np.maximum(21.7, 37.5 - inward)
        on_rune = (
            (tag == 1)
            & (y >= 21.5)
            & (y <= 94.5)
            & (ax <= x_in + 1.35)
            & ((np.abs(z - 1.0) <= 1.55) | (np.abs(z - 6.6) <= 0.85))
            & ((np.floor(y * 0.55).astype(np.int32) % 3) != 0)
        )
        hot_node = (np.floor(y).astype(np.int32) % 14) <= 2
        r_col = np.where(hot_node[..., None], SOLAR[2], TURQ[2])
        r_glow = np.where(hot_node[..., None], (*SOLAR[1][:3], 205), (*TURQ[2][:3], 175))
        rgba = np.where(on_rune[..., None], r_col, rgba)
        mat = np.where(on_rune, MAT_QUARTZ, mat)
        glow = np.where(on_rune[..., None], r_glow, glow)

        # Subtle lowest-1.5px outer plinth contact sand blend ONLY (never near walkable center!)
        at_foot = (y < 1.6) & (ax >= 42.0) & (lit_eff > -0.15)
        rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
        mat = np.where(at_foot, MAT_SAND, mat)

        return rgba, mat, glow

    render_csg(cv, (2, W - 2, 2, H - 2), (-48.0, 48.0), sdf_gate, paint_gate, ss=2, n_steps=64, shadow_steps=16, margin=2)

    px, glow = cv.finalize_with_outlines(foot_cut_y=120, add_internal_creases=True, halo_alpha=0.24, halo_max_y=118)
    # Hard guard: keep walkable center arch span x=48..112 completely clear down near feet (y >= 88)!
    for yy in range(88, H):
        for xx in range(48, 113):
            px[yy][xx] = CLEAR
            glow[yy][xx] = CLEAR

    lx_s, ly_s = project_pt((-22.5, 114.5, 0.0), cx, cy)
    rx_s, ry_s = project_pt((22.5, 111.5, 0.0), cx, cy)
    return px, glow, {
        "file": "ecliptic_gate.png",
        "glow": "ecliptic_gate_glow.png",
        "size": [W, H],
        "feet": [80, 120],
        "walkable_span_x": [48, 112],
        "ocular_anchor": [80, 26],
        "horn_tips": [[int(round(lx_s)), int(round(ly_s))], [int(round(rx_s)), int(round(ry_s))]],
    }


def make_gate_ocular() -> tuple[list, list, dict]:
    """Heavy cracked sintered-quartz ocular lens framed in a split brass ring that levitates
    between the ecliptic gate pylon tips."""
    W, H = 48, 48
    cx, cy = 24.0, 24.0
    cv = Canvas(W, H, cx, cy)

    # Split tarnished-brass gimbal ring (two mechanical split gaps at NE & SW)
    def split_clip(p: np.ndarray) -> np.ndarray:
        ang = np.arctan2(p[..., 1], p[..., 0])
        return (np.abs(ang - 0.85) > 0.14) & (np.abs(ang + 2.29) > 0.14)

    R_ring = rot_x(0.32) @ rot_y(-0.22)
    cv.render_ring_band((0.0, 0.0, 0.0), R_ring, r_in=13.0, r_out=17.5, half_h=3.2, mat=MAT_GOLD, arc_clip=split_clip, ss=3)
    # 4 calibration brass lugs at N, S, E, W
    for ang_l in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        lp = R_ring @ np.array([math.cos(ang_l) * 18.2, math.sin(ang_l) * 18.2, 0.0])
        cv.render_ellipsoid(lp, (2.4, 2.4, 2.4), MAT_GOLD, ss=2)

    # Heavy cracked sintered-quartz ocular lens disc
    def paint_cracked_lens(ok, q, nw, lit, rg, ma, gl) -> None:
        r = np.hypot(q[..., 0], q[..., 1])
        bands = shade_band_np(lit + 0.18, len(QUARTZ_W))
        rg[:] = np.array(QUARTZ_W, dtype=np.uint8)[bands]
        # Crisp glowing hairline crystal crack zig-zagging across the lens + focal core!
        crack_y = 0.25 * q[..., 0] + 0.14 * np.sin(q[..., 0] * 7.5)
        is_crack = ok & (np.abs(q[..., 1] - crack_y) < 0.11) & (r < 0.88)
        is_branch = ok & (np.abs(q[..., 0] - 0.15 - q[..., 1] * 0.6) < 0.08) & (q[..., 1] > 0.0) & (r < 0.75)
        is_core = ok & (r < 0.26)
        rg[is_crack] = TURQ[3]
        gl[is_crack] = (*TURQ[2][:3], 200)
        rg[is_branch] = ASTRAL[1]
        gl[is_branch] = (*ASTRAL[1][:3], 185)
        rg[is_core] = SOLAR[2]
        gl[is_core] = (*SOLAR[1][:3], 225)

    cv.render_ellipsoid((0.0, 0.0, 0.0), (12.8, 12.8, 3.8), MAT_QUARTZ, R=R_ring, paint_fn=paint_cracked_lens, ss=3)
    px, glow = cv.finalize_with_outlines(foot_cut_y=None, add_internal_creases=True, halo_alpha=0.26)
    return px, glow, {
        "file": "gate_ocular.png",
        "glow": "gate_ocular_glow.png",
        "size": [W, H],
        "center": [24, 24],
        "lens_hub": [24, 24],
    }


# ------------------------------------------------------------------------------
# ASSET 9: star_mirror_rim (184x116, center (92, 58))
# ------------------------------------------------------------------------------
def make_star_mirror_rim() -> tuple[list, list, dict]:
    """True 3D elliptical stepped star-slate & white sinter-quartz basin coping (outer ~rx 88, ry 54)
    showing a deep 9-11 px curved vertical northern inner well wall & submerged slate ledge above a
    COMPLETELY TRANSPARENT inner pool ellipse (strictly alpha=0 inside (dx/65)^2 + (dy/35)^2 < 1),
    crowned with 8 raised 3D beveled brass compass star-points."""
    W, H = 184, 116
    cx, cy = 92.0, 58.0
    cv = Canvas(W, H, cx, cy)

    # Outer ground drop shadow along south rim footprint (strictly outside inner pool & inside margin=2!)
    for sy_d in range(95, H - 3):
        for sx_d in range(6, W - 6):
            dx = sx_d + 0.5 - cx
            dy = sy_d + 0.5 - cy
            if (dx / 65.0) ** 2 + (dy / 35.0) ** 2 < 1.0:
                continue
            r_sh = math.hypot((dx - 2.0) / 88.5, (dy - 3.5) / 52.0)
            if 0.86 <= r_sh <= 1.02:
                k = clamp(1.0 - abs(r_sh - 0.94) / 0.08, 0.0, 1.0)
                a_sh = int(68 * k)
                if a_sh > int(cv.shadow[sy_d, sx_d]):
                    cv.shadow[sy_d, sx_d] = a_sh

    # Precompute 24 stone sector modulations for slight chipped ashlar coping silhouette
    sec_mods = np.array([0.965 + 0.048 * _ihash(s, 7, 61) for s in range(24)], dtype=np.float64)
    compass_angs = np.array([math.radians(k * 45.0) for k in range(8)], dtype=np.float64)
    ca_arr = np.cos(compass_angs)
    sa_arr = np.sin(compass_angs)

    def hf_mirror(x: np.ndarray, z: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        z_sh = z - 14.63  # Z-center aligned so +9.5 px coping meets south void cleanly & north reveals 9.5 px wall!
        ang = np.arctan2(z_sh, x)
        deg = (np.degrees(ang) + 360.0) % 360.0
        sec = np.clip((deg / 15.0).astype(np.int32), 0, 23)
        outer_mod = sec_mods[sec]

        rz_in = np.where(z_sh < 0.0, 79.0, 64.3)
        rz_out = np.where(z_sh < 0.0, 95.5, 79.0) * outer_mod
        rx_out = 86.0 * outer_mod

        r_top = np.hypot(x / 65.4, z_sh / rz_in)
        r_out = np.hypot(x / rx_out, z_sh / rz_out)
        r_void = np.hypot(x / 65.0, z / 64.26)

        # Tiered 3D coping heights:
        #   - Inner northern bench/ledge at Y_up = 4.6 between r_void=1.0 and r_top=1.0 (never intrudes south)
        #   - Main upper quartz/star-slate coping at Y_up = 9.5 (slightly stepped outer sandstone apron at 7.2)
        h = np.zeros_like(x)
        in_main = (r_top >= 1.0) & (r_out <= 0.90)
        in_apron = (r_out > 0.90) & (r_out <= 1.0)
        # Stepped northern inner wall bench (r_top < 1.0 and z < 14.63 and r_void >= 1.0)
        in_bench = (r_top < 1.0) & (z_sh < 0.0) & (r_void >= 1.0)

        h = np.where(in_bench, 4.6, h)
        h = np.where(in_apron, 6.8, h)
        h = np.where(in_main, 9.6, h)

        # Crisp bevel chamfer along inner & outer coping lips
        h = np.where(in_main & (r_top < 1.035), 9.9, h)
        h = np.where(in_main & ((deg % 15.0 < 0.8) | (deg % 15.0 > 14.2)), h - 0.5, h)

        tag = np.where(in_main, 2, np.where(in_apron, 3, np.where(in_bench, 1, 0)))

        # 8 Raised 3D Beveled Brass Compass Spearheads mounted around main coping (Y_up = 9.6..11.8)
        for k in range(8):
            sa_k = math.sin(compass_angs[k])
            bx = math.cos(compass_angs[k]) * (76.0 if abs(math.cos(compass_angs[k])) > 0.5 else 75.5)
            bz = 14.63 + sa_k * (86.5 if sa_k < -0.01 else 74.0)
            dx_l = x - bx
            dz_l = z - bz
            u = dx_l * ca_arr[k] + dz_l * sa_arr[k]
            v = -dx_l * sa_arr[k] + dz_l * ca_arr[k]
            hw = 3.8 * (1.0 - np.clip(np.abs(u) / 6.6, 0.0, 1.0))
            in_spear = (np.abs(u) <= 6.6) & (np.abs(v) <= hw) & (r_void >= 1.0)
            spear_h = 11.7 - 0.35 * np.abs(v) - 0.12 * np.abs(u)
            raise_m = in_spear & (spear_h > h)
            h = np.where(raise_m, spear_h, h)
            tag = np.where(raise_m, 10 + k, tag)

        return h, tag

    def paint_mirror(
        xh: np.ndarray,
        yh: np.ndarray,
        zh: np.ndarray,
        nh: np.ndarray,
        is_wall: np.ndarray,
        tag_h: np.ndarray,
        sun_vis: np.ndarray,
        ao_h: np.ndarray,
    ):
        num = xh.shape[0]
        lit_base = nh @ L_3D
        lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.44 - 0.32, -0.20), lit_base)
        lit_eff -= (1.0 - ao_h) * 0.34

        z_sh = zh - 14.63
        ang = np.arctan2(z_sh, xh)
        deg = (np.degrees(ang) + 360.0) % 360.0
        sec = (np.floor(deg / 15.0).astype(np.int32)) % 24
        is_joint = np.minimum(deg % 15.0, 15.0 - (deg % 15.0)) < 0.85

        rgba = np.zeros((num, 4), dtype=np.uint8)
        mat = np.full(num, MAT_INDIGO, dtype=np.int16)
        glow = np.zeros((num, 4), dtype=np.uint8)

        q_pal = np.array(QUARTZ_W, dtype=np.uint8)
        i_pal = np.array(INDIGO, dtype=np.uint8)
        s_pal = np.array(SANDSTONE, dtype=np.uint8)
        g_pal = np.array(GOLD, dtype=np.uint8)

        # Default stone on wall vs top:
        # 1) Alternating White Sinter-Quartz & Dark Star-Slate coping slabs (tag == 2)
        quartz_sec = (sec % 2 == 0)
        q_col = q_pal[shade_band_np(lit_eff + 0.16, len(QUARTZ_W))]
        i_col = i_pal[shade_band_np(lit_eff + 0.12, len(INDIGO))]
        slab_c = np.where(is_joint[..., None], INDIGO[0], np.where(quartz_sec[..., None], q_col, i_col))
        rgba = np.where((tag_h == 2)[..., None], slab_c, rgba)
        mat = np.where((tag_h == 2) & quartz_sec & (~is_joint), MAT_QUARTZ, mat)

        # 2) Outer Sandstone & Ashlar Apron Step (tag == 3)
        apron_c = ashlar_shade_3d(deg * 1.4, yh + zh * 0.4, lit_eff, MAT_SANDSTONE, course_h=4.5, block_w=10.0, seed=611)
        rgba = np.where((tag_h == 3)[..., None], apron_c, rgba)
        mat = np.where(tag_h == 3, MAT_SANDSTONE, mat)

        # 3) Northern Inner Vertical Well Wall & Submerged Star-Slate Ledge (tag == 1 or vertical inside wall)
        is_inner_well_wall = (tag_h == 1) | (is_wall & (z_sh < 0.0) & (np.hypot(xh / 68.0, z_sh / 81.0) < 1.02))
        wall_lit = np.where(yh < 5.0, lit_eff - 0.16, lit_eff)
        well_c = ashlar_shade_3d(deg * 1.6, yh, wall_lit, MAT_INDIGO, course_h=4.2, block_w=9.5, seed=619)
        rgba = np.where(is_inner_well_wall[..., None], well_c, rgba)
        mat = np.where(is_inner_well_wall, MAT_INDIGO, mat)

        # Subtle turquoise water-line mineralization streak along submerged inner ledge lip (Y_up = 4.4..4.9)
        is_water_seam = (tag_h == 1) & (~is_wall) & (np.hypot(xh / 65.8, zh / 65.2) < 1.03)
        rgba = np.where(is_water_seam[..., None], TURQ[0], rgba)

        # 4) Outer Southern Vertical Sandstone Riser Wall (is_wall on south outer rim)
        is_south_wall = is_wall & (~is_inner_well_wall) & (tag_h < 10)
        south_wc = ashlar_shade_3d(deg * 1.5, yh, lit_eff - 0.08, MAT_SANDSTONE, course_h=4.5, block_w=11.0, seed=623)
        rgba = np.where(is_south_wall[..., None], south_wc, rgba)
        mat = np.where(is_south_wall, MAT_SANDSTONE, mat)

        # 5) 8 Tarnished Brass Compass Spearheads + Glowing Cardinal Jewels (tag_h >= 10)
        is_brass = tag_h >= 10
        b_c = g_pal[shade_band_np(lit_eff + 0.16, len(GOLD))]
        rgba = np.where(is_brass[..., None], b_c, rgba)
        mat = np.where(is_brass, MAT_GOLD, mat)

        for k in range(8):
            sa_k = math.sin(compass_angs[k])
            bx = math.cos(compass_angs[k]) * (76.0 if abs(math.cos(compass_angs[k])) > 0.5 else 75.5)
            bz = 14.63 + sa_k * (86.5 if sa_k < -0.01 else 74.0)
            u = (xh - bx) * ca_arr[k] + (zh - bz) * sa_arr[k]
            v = -(xh - bx) * sa_arr[k] + (zh - bz) * ca_arr[k]
            on_jewel = (tag_h == 10 + k) & (np.abs(u + 0.8) <= 1.35) & (np.abs(v) <= 1.25)
            j_col = TURQ[3] if k % 2 == 0 else SOLAR[2]
            j_gcol = (*TURQ[2][:3], 200) if k % 2 == 0 else (*SOLAR[1][:3], 205)
            rgba = np.where(on_jewel[..., None], j_col, rgba)
            mat = np.where(on_jewel, MAT_QUARTZ, mat)
            glow = np.where(on_jewel[..., None], j_gcol, glow)

        # Subtle lowest-1.5px southern outer foot sand contact ONLY (no floating oval blobs!)
        at_south_foot = is_south_wall & (yh < 1.5) & (lit_eff > -0.22)
        rgba = np.where(at_south_foot[..., None], SAND_DRIFT[1], rgba)
        mat = np.where(at_south_foot, MAT_SAND, mat)

        return rgba, mat, glow

    render_heightfield(cv, (2, W - 2, 2, H - 2), h_max=12.4, h_min=0.0, hf_fn=hf_mirror, paint_fn=paint_mirror, ss=2, n_coarse=60, margin=2)

    px, glow = cv.finalize_with_outlines(foot_cut_y=H, add_internal_creases=True, halo_alpha=0.22)

    # Hard safety pass: strictly alpha=0 inside clear pool ellipse (dx/65)^2 + (dy/35)^2 < 1
    def in_clear_pool(x: int, y: int) -> bool:
        dx = x + 0.5 - cx
        dy = y + 0.5 - cy
        return (dx / 65.0) ** 2 + (dy / 35.0) ** 2 < 1.0

    for y in range(H):
        for x in range(W):
            if in_clear_pool(x, y):
                px[y][x] = CLEAR
                glow[y][x] = CLEAR

    compass_pts = []
    for k in range(8):
        sa_k = math.sin(compass_angs[k])
        bx = math.cos(compass_angs[k]) * (76.0 if abs(math.cos(compass_angs[k])) > 0.5 else 75.5)
        bz = 14.63 + sa_k * (86.5 if sa_k < -0.01 else 74.0)
        sx_k, sy_k = project_pt((bx, 11.5, bz), cx, cy)
        compass_pts.append([int(round(sx_k)), int(round(sy_k))])

    return px, glow, {
        "file": "star_mirror_rim.png",
        "glow": "star_mirror_rim_glow.png",
        "size": [W, H],
        "center": [92, 58],
        "outer_radii": [88, 54],
        "pool_radii": [65, 35],
        "compass_points": compass_pts,
    }


# ------------------------------------------------------------------------------
# ASSET 10: causeway_pillar (4x1 of 56x96 = 224x96, feet (28, 84))
# ------------------------------------------------------------------------------
def make_causeway_pillar(variant: int) -> tuple[list, list, list[int]]:
    W, H = 56, 96
    fx, fy = 28.0, 84.0
    cv = Canvas(W, H, fx, fy)

    cv.draw_ground_shadow(28.5, 85.0, 17.5, 5.2, max_alpha=68)

    if variant in (0, 1):
        # Col 0 & Col 1: True 3D Tilted Octagonal Colonnade Pillars + Overhanging Chipped Capital + Aeolian Quartz Wind-Harp
        tilt = -0.055 if variant == 0 else 0.055
        harp_side = 1.0 if variant == 0 else -1.0

        def sdf_harp(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
            x, y, z = p[..., 0], p[..., 1], p[..., 2]
            xc = tilt * np.maximum(y - 8.0, 0.0)

            # Stepped 3D Octagonal Pedestal Base (Y_up = 0..13)
            d_b1 = sd_oct_y(p, (0.0, 3.6, 0.0), r=11.5, hh=3.6)
            d_b2 = sd_oct_y(p, (0.0, 9.6, 0.0), r=9.2, hh=2.8)

            # Tilted octagonal shaft (Y_up = 11..68)
            p_sh = np.stack([x - xc, y, z], axis=-1)
            d_sh = sd_oct_y(p_sh, (0.0, 39.5, 0.0), r=6.2, hh=28.5)

            # Overhanging 3D Chipped Capital + Recessed Roof Deck (Y_up = 67..77)
            cap_xc = tilt * 62.0
            p_cap = np.stack([x - cap_xc, y, z], axis=-1)
            d_cap_outer = sd_oct_y(p_cap, (0.0, 71.5, 0.0), r=8.8, hh=4.8)
            # Chipped outer upper corner on side away from harp!
            d_chip = sd_box(p_cap, (-harp_side * 5.8, 75.2, 0.0), (3.8, 2.6, 8.5), r=0.2)
            # Shallow 1.5 px roof deck recess inside capital crown
            d_deck_pit = sd_oct_y(p_cap, (0.0, 76.2, 0.0), r=6.6, hh=1.3)
            d_cap = np.maximum(np.maximum(d_cap_outer, -d_chip), -d_deck_pit)

            # Projecting 3D Brass Collars around shaft (Y_up = 16, 44, 65)
            d_c1 = sd_oct_y(p_sh, (0.0, 15.8, 0.0), r=6.9, hh=1.3)
            d_c2 = sd_oct_y(p_sh, (0.0, 44.0, 0.0), r=6.8, hh=1.3)
            d_c3 = sd_oct_y(p_sh, (0.0, 65.5, 0.0), r=7.1, hh=1.3)

            # Projecting Brass Harp Brackets at Y_up = 26 and Y_up = 58
            bx_mid = harp_side * 10.2
            d_br1 = sd_box(p_sh, (bx_mid, 26.0, 0.0), (7.6, 1.35, 2.2), r=0.20)
            d_br2 = sd_box(p_sh, (bx_mid, 58.0, 0.0), (7.6, 1.35, 2.2), r=0.20)

            # 3 Vertical Faceted Quartz/Turquoise Harp Crystal Blades between brackets (Y_up = 27..57)
            h1 = sd_oct_y(p_sh, (harp_side * 7.8, 42.0, 0.0), r=1.15, hh=15.0, bevel=0.10)
            h2 = sd_oct_y(p_sh, (harp_side * 12.0, 42.0, 0.0), r=1.55, hh=15.2, bevel=0.10)
            h3 = sd_oct_y(p_sh, (harp_side * 16.0, 42.0, 0.0), r=1.10, hh=15.0, bevel=0.10)
            d_blades = np.minimum(h1, np.minimum(h2, h3))

            d_stone = np.minimum(np.minimum(d_b1, d_b2), np.minimum(d_sh, d_cap))
            d_brass = np.minimum(np.minimum(d_c1, np.minimum(d_c2, d_c3)), np.minimum(d_br1, d_br2))
            d_best = np.minimum(d_stone, np.minimum(d_brass, d_blades))
            tag = np.where(d_blades < np.minimum(d_stone, d_brass) - 0.05, 3, np.where(d_brass < d_stone, 2, 1))
            return d_best, tag

        def paint_harp(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
            num = p.shape[0]
            x, y, z = p[..., 0], p[..., 1], p[..., 2]
            lit_base = n @ L_3D
            lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
            lit_eff -= (1.0 - ao) * 0.36

            xc = tilt * np.maximum(y - 8.0, 0.0)
            rgba = ashlar_shade_3d((x - xc) + z * 0.85, y, lit_eff, MAT_SANDSTONE, course_h=5.8, block_w=9.5, seed=611 + variant * 13)
            mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
            glow = np.zeros((num, 4), dtype=np.uint8)

            # Vertical dark Star-Slate flute strip on front shaft face
            on_slate = (tag == 1) & (y >= 17.0) & (y <= 64.0) & (z > 3.5) & (np.abs(x - xc) < 1.8)
            i_pal = np.array(INDIGO, dtype=np.uint8)
            rgba = np.where(on_slate[..., None], i_pal[shade_band_np(lit_eff + 0.05, len(INDIGO))], rgba)
            mat = np.where(on_slate, MAT_INDIGO, mat)

            # Brass collars & brackets (tag == 2)
            g_pal = np.array(GOLD, dtype=np.uint8)
            rgba = np.where((tag == 2)[..., None], g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))], rgba)
            mat = np.where(tag == 2, MAT_GOLD, mat)

            # Translucent Luminous Turquoise & White Quartz Harp Blades (tag == 3)
            q_pal = np.array(QUARTZ_W, dtype=np.uint8)
            is_mid_blade = np.abs(np.abs(x - xc) - 12.0) < 2.2
            blade_c = np.where(is_mid_blade[..., None], TURQ[3], q_pal[shade_band_np(lit_eff + 0.25, len(QUARTZ_W))])
            b_glow = np.where(is_mid_blade[..., None], (*TURQ[3][:3], 195), (*TURQ[2][:3], 150))
            rgba = np.where((tag == 3)[..., None], blade_c, rgba)
            mat = np.where(tag == 3, MAT_QUARTZ, mat)
            glow = np.where((tag == 3)[..., None], b_glow, glow)

            # Subtle lowest-1.5px plinth sand contact
            at_foot = (y < 1.5) & (lit_eff > -0.15)
            rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
            mat = np.where(at_foot, MAT_SAND, mat)
            return rgba, mat, glow

        render_csg(cv, (2, W - 2, 2, H - 2), (-36.0, 36.0), sdf_harp, paint_harp, ss=2, n_steps=56, shadow_steps=14, margin=2)
        fx_s, fy_s = project_pt((tilt * 42.0 + harp_side * 12.0, 42.0, 0.0), fx, fy)
        focal = [int(round(fx_s)), int(round(fy_s))]

    elif variant == 2:
        # Col 2: Nordklippen Polar Ocular Pedestal (true 3D azimuth pedestal + overhanging brass table + yoke + NNE sighting telescope!)
        def sdf_ocular(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
            # Stepped 3D Plinth (Y_up = 0..14)
            d_p1 = sd_oct_y(p, (0.0, 3.8, 0.0), r=12.4, hh=3.8)
            d_p2 = sd_oct_y(p, (0.0, 10.2, 0.0), r=9.8, hh=2.8)
            # Azimuth Pillar Shaft (Y_up = 13..46)
            d_sh = sd_oct_y(p, (0.0, 29.5, 0.0), r=6.8, hh=16.8)
            # Overhanging 3D Sandstone & Brass Azimuth Table Capital (Y_up = 45..52, casts shadow on shaft!)
            d_cap = sd_oct_y(p, (0.0, 47.6, 0.0), r=9.4, hh=2.6)
            d_b1 = sd_oct_y(p, (0.0, 14.0, 0.0), r=10.3, hh=1.2)
            d_b2 = sd_oct_y(p, (0.0, 45.2, 0.0), r=8.2, hh=1.2)
            d_dial = sd_cyl_y(p, (0.0, 50.8, 0.0), r=8.4, hh=1.1, bevel=0.15)
            d_stone = np.minimum(np.minimum(d_p1, d_p2), np.minimum(d_sh, d_cap))
            d_brass = np.minimum(d_b1, np.minimum(d_b2, d_dial))
            d_best = np.minimum(d_stone, d_brass)
            tag = np.where(d_brass < d_stone, 2, 1)
            return d_best, tag

        def paint_ocular(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
            num = p.shape[0]
            x, y, z = p[..., 0], p[..., 1], p[..., 2]
            lit_base = n @ L_3D
            lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
            lit_eff -= (1.0 - ao) * 0.36
            rgba = ashlar_shade_3d(x + z * 0.8, y, lit_eff, MAT_SANDSTONE, course_h=5.5, block_w=9.5, seed=640)
            mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
            glow = np.zeros((num, 4), dtype=np.uint8)

            # Vertical star-slate calibration strip down front of shaft
            on_slate = (tag == 1) & (y >= 16.0) & (y <= 44.0) & (z > 4.2) & (np.abs(x) < 2.2)
            i_pal = np.array(INDIGO, dtype=np.uint8)
            rgba = np.where(on_slate[..., None], i_pal[shade_band_np(lit_eff + 0.05, len(INDIGO))], rgba)
            mat = np.where(on_slate, MAT_INDIGO, mat)

            # Overhanging brass dial ring & trim (tag == 2)
            g_pal = np.array(GOLD, dtype=np.uint8)
            rgba = np.where((tag == 2)[..., None], g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))], rgba)
            mat = np.where(tag == 2, MAT_GOLD, mat)

            # Glowing cardinal degree pips on top azimuth dial plate
            on_pip = (tag == 2) & (y > 51.2) & ((np.abs(x) < 1.1) & (np.abs(np.abs(z) - 5.5) < 1.1) | (np.abs(z) < 1.1) & (np.abs(np.abs(x) - 5.5) < 1.1))
            rgba = np.where(on_pip[..., None], TURQ[3], rgba)
            mat = np.where(on_pip, MAT_QUARTZ, mat)
            glow = np.where(on_pip[..., None], (*TURQ[2][:3], 175), glow)

            at_foot = (y < 1.5) & (lit_eff > -0.15)
            rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
            mat = np.where(at_foot, MAT_SAND, mat)
            return rgba, mat, glow

        render_csg(cv, (2, W - 2, 2, H - 2), (-36.0, 36.0), sdf_ocular, paint_ocular, ss=2, n_steps=56, shadow_steps=14, margin=2)

        # Brass Yoke Cradle + Altitude Vernier Quadrant Arc + Gleaming NNE Sighting Telescope!
        y_mount = 57.5
        cv.render_cylinder((0.0, 51.5, 0.0), (0.0, y_mount, 0.0), 3.6, 2.8, MAT_GOLD, ss=2)
        cv.render_ring_band((0.0, y_mount + 0.8, 0.0), rot_y(0.45), r_in=5.8, r_out=7.8, half_h=1.1, mat=MAT_GOLD, ss=2,
                            arc_clip=lambda p: (p[..., 1] <= 1.0) & (p[..., 0] >= -4.0))
        dir_nne = np.array([0.55, 0.62, -0.56], dtype=np.float64)
        dir_nne /= np.linalg.norm(dir_nne)
        p_eye = tuple(-dir_nne * 12.0 + np.array([0.0, y_mount + 1.5, 0.0]))
        p_obj = tuple(dir_nne * 14.5 + np.array([0.0, y_mount + 1.5, 0.0]))
        cv.render_cylinder(p_eye, p_obj, 2.6, 4.4, MAT_GOLD, ss=3,
                           paint_fn=lambda ok, bp, bn, lit, rg, ma, gl: (
                               rg.__setitem__(ok & (bp[..., 1] > y_mount + 8.5), QUARTZ_W[5]),
                               gl.__setitem__(ok & (bp[..., 1] > y_mount + 9.2), (*TURQ[3][:3], 205)),
                           ))
        ex_s, ey_s = project_pt(p_eye, fx, fy)
        cv.put_px(int(round(ex_s)), int(round(ey_s)), TURQ[3], mat=MAT_QUARTZ)
        cv.put_glow(int(round(ex_s)), int(round(ey_s)), TURQ[2][:3], 185)
        ox_s, oy_s = project_pt(p_obj, fx, fy)
        focal = [int(round(ox_s)), int(round(oy_s))]

    else:
        # Col 3: True 3D Open-Air Prism-Grinding Altar (twin ashlar pedestal legs + overhanging quartz slab casting shadow + grinding disc + calipers + Sun-Quartz blank)
        def sdf_altar(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
            x, y, z = p[..., 0], p[..., 1], p[..., 2]
            # Twin 3D Stepped Pedestal Legs (X = +-11.5, Y_up = 0..23)
            d_f_l = sd_box(p, (-11.5, 2.5, 0.0), (5.8, 2.5, 6.8), r=0.22)
            d_f_r = sd_box(p, (11.5, 2.5, 0.0), (5.8, 2.5, 6.8), r=0.22)
            d_l_l = sd_box(p, (-11.5, 13.0, 0.0), (4.6, 9.2, 5.4), r=0.22)
            d_l_r = sd_box(p, (11.5, 13.0, 0.0), (4.6, 9.2, 5.4), r=0.22)
            # Cross-stretcher tie beam between legs near floor (Y_up = 4..8)
            d_tie = sd_box(p, (0.0, 5.5, -1.0), (10.5, 2.2, 2.6), r=0.20)

            # Thick Overhanging Sandstone Apron Slab (Y_up = 21..28, half_x=19.5, half_z=11.0 -> casts strong shadow onto legs!)
            d_apron = sd_box(p, (0.0, 24.5, 0.0), (19.5, 3.6, 11.2), r=0.22)
            # White Sinter-Quartz Inlaid Workbench Slab Top (Y_up = 27.5..31.5, slightly chamfered!)
            d_qtop = sd_box(p, (0.0, 29.4, 0.0), (18.2, 2.0, 10.2), r=0.28)
            # Grinding wheel slot carved into right end of quartz slab
            d_slot = sd_box(p, (12.0, 31.0, 0.0), (1.4, 2.2, 5.2), r=0.10)
            d_qtop = np.maximum(d_qtop, -d_slot)

            # Upright Abrasive Stone Grinding Disc rotating in right slot (X = 12, Y_up = 34, radius = 5.4)
            d_wheel = np.maximum(np.hypot(y - 34.2, z) - 5.2, np.abs(x - 12.0) - 1.1)

            # Brass Apron Trim Band + Clamp Cradle + Hinged Calipers on Left
            d_btrim = sd_box(p, (0.0, 26.8, 0.0), (20.1, 0.9, 11.7), r=0.15)
            d_cradle = sd_cyl_y(p, (-0.5, 31.8, 1.5), r=4.2, hh=1.0, bevel=0.15)
            # Calipers V-arms on left side of workbench
            u_c = x + 10.5
            w_c = z - 2.0
            d_cal_a = np.maximum(np.abs((u_c * 0.7 + w_c * 0.7)) - 0.65, np.maximum(np.abs(u_c) - 4.2, np.abs(y - 31.7) - 0.65))
            d_cal_b = np.maximum(np.abs((u_c * 0.7 - w_c * 0.7)) - 0.65, np.maximum(np.abs(u_c) - 4.2, np.abs(y - 31.7) - 0.65))
            d_cal = np.minimum(d_cal_a, d_cal_b)

            d_stone = np.minimum(np.minimum(np.minimum(d_f_l, d_f_r), np.minimum(d_l_l, d_l_r)), np.minimum(d_tie, d_apron))
            d_quartz = d_qtop
            d_brass = np.minimum(d_btrim, np.minimum(d_cradle, d_cal))
            d_all = np.minimum(np.minimum(d_stone, d_quartz), np.minimum(d_brass, d_wheel))
            tag = np.where(d_wheel < np.minimum(d_stone, np.minimum(d_quartz, d_brass)) - 0.05, 4,
                           np.where(d_brass < np.minimum(d_stone, d_quartz), 3,
                                    np.where(d_quartz < d_stone, 2, 1)))
            return d_all, tag

        def paint_altar(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
            num = p.shape[0]
            x, y, z = p[..., 0], p[..., 1], p[..., 2]
            lit_base = n @ L_3D
            lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.42 - 0.34, -0.22), lit_base)
            lit_eff -= (1.0 - ao) * 0.38

            rgba = ashlar_shade_3d(x + z * 0.8, y, lit_eff, MAT_SANDSTONE, course_h=5.2, block_w=9.5, seed=675)
            mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
            glow = np.zeros((num, 4), dtype=np.uint8)

            q_pal = np.array(QUARTZ_W, dtype=np.uint8)
            g_pal = np.array(GOLD, dtype=np.uint8)

            # White Sinter-Quartz Workbench Slab (tag == 2)
            q_c = q_pal[shade_band_np(lit_eff + 0.16, len(QUARTZ_W))]
            # Engraved indigo alignment grid lines across tabletop
            on_grid = (tag == 2) & (n[..., 1] > 0.6) & ((np.abs(x + 0.5) < 0.45) | (np.abs(z - 1.5) < 0.45)) & (np.abs(x) < 14.0)
            q_c = np.where(on_grid[..., None], INDIGO[1], q_c)
            rgba = np.where((tag == 2)[..., None], q_c, rgba)
            mat = np.where((tag == 2) & (~on_grid), MAT_QUARTZ, mat)

            # Brass Trim, Calipers & Cradle (tag == 3)
            b_c = g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))]
            rgba = np.where((tag == 3)[..., None], b_c, rgba)
            mat = np.where(tag == 3, MAT_GOLD, mat)

            # Abrasive Sandstone Grinding Wheel with indigo axle hub (tag == 4)
            is_hub = (tag == 4) & (np.hypot(y - 34.2, z) < 1.5)
            w_c = np.where(is_hub[..., None], GOLD[2], ashlar_shade_3d(y * 1.4, z * 1.4, lit_eff + 0.08, MAT_SANDSTONE, course_h=4.0, block_w=6.0, seed=689, has_mortar=False))
            rgba = np.where((tag == 4)[..., None], w_c, rgba)
            mat = np.where(is_hub, MAT_GOLD, np.where(tag == 4, MAT_SANDSTONE, mat))

            at_foot = (y < 1.4) & (lit_eff > -0.15)
            rgba = np.where(at_foot[..., None], SAND_DRIFT[1], rgba)
            mat = np.where(at_foot, MAT_SAND, mat)
            return rgba, mat, glow

        render_csg(cv, (2, W - 2, 2, H - 2), (-36.0, 36.0), sdf_altar, paint_altar, ss=2, n_steps=56, shadow_steps=14, margin=2)

        # Uncut luminous Sun-Quartz crystal blank clamped upright on center of quartz workbench!
        cv.render_facet_crystal((-0.5, 38.2, 1.5), rot_z(-0.18) @ rot_y(0.45), rx=4.8, ry_top=8.2, ry_bot=4.0, n_sides=6, glow_mode="solar", ss=3)
        fx_c, fy_c = project_pt((-0.5, 38.5, 1.5), fx, fy)
        focal = [int(round(fx_c)), int(round(fy_c))]

    px, glow = cv.finalize_with_outlines(foot_cut_y=84, add_internal_creases=True, halo_alpha=0.24, halo_max_y=82)
    return px, glow, focal


# ------------------------------------------------------------------------------
# ASSET 11: floating_debris (6x1 of 40x40 = 240x40, center (20, 20))
# ------------------------------------------------------------------------------
def make_floating_debris(variant: int) -> tuple[list, list]:
    W, H = 40, 40
    cx, cy = 20.0, 20.0
    cv = Canvas(W, H, cx, cy)

    if variant == 0:
        # (0) Broken indigo-glazed dome tile chunk with gold star scrap
        cv.render_ellipsoid(
            (0.0, 0.0, 0.0), (14.2, 11.8, 4.5), MAT_INDIGO,
            R=rot_z(0.28) @ rot_x(-0.35), ss=3,
            clip_fn=lambda q: (q[..., 0] + 0.35 * q[..., 1] < 0.72) & (q[..., 1] - 0.2 * q[..., 0] > -0.78),
            paint_fn=lambda ok, q, nw, lit, rg, ma, gl: (
                # Sandstone fracture edge + gold star chart arc scrap + glowing star dots
                rg.__setitem__(ok & (q[..., 0] > 0.36), SANDSTONE[2]),
                ma.__setitem__(ok & (q[..., 0] > 0.36), MAT_SANDSTONE),
                rg.__setitem__(ok & (np.abs(q[..., 1] - 0.14) < 0.14) & (q[..., 0] < 0.25), GOLD[4]),
                ma.__setitem__(ok & (np.abs(q[..., 1] - 0.14) < 0.14) & (q[..., 0] < 0.25), MAT_GOLD),
                rg.__setitem__(ok & (np.hypot(q[..., 0] + 0.22, q[..., 1] - 0.14) < 0.17), SOLAR[2]),
                gl.__setitem__(ok & (np.hypot(q[..., 0] + 0.22, q[..., 1] - 0.14) < 0.17), (*SOLAR[1][:3], 205)),
                rg.__setitem__(ok & (np.hypot(q[..., 0] - 0.05, q[..., 1] + 0.28) < 0.13), TURQ[3]),
                gl.__setitem__(ok & (np.hypot(q[..., 0] - 0.05, q[..., 1] + 0.28) < 0.13), (*TURQ[2][:3], 185)),
            ),
        )
    elif variant == 1:
        # (1) Toothed brass gear-arc
        def gear_arc_clip(p: np.ndarray) -> np.ndarray:
            ang = np.arctan2(p[..., 1], p[..., 0])
            return (ang >= -0.40) & (ang <= 1.95)

        gear_c = (-4.5, -3.5, 0.0)
        R_g = rot_x(0.45) @ rot_z(-0.45)
        cv.render_ring_band(gear_c, R_g, r_in=10.0, r_out=14.6, half_h=2.8, mat=MAT_GOLD, arc_clip=gear_arc_clip, ss=3,
                            paint_fn=lambda ok, pos, nl, f, lit, rg, ma, gl: (
                                rg.__setitem__(ok & (np.abs(pos[..., 2]) < 1.1) & (np.abs(np.arctan2(pos[..., 1], pos[..., 0]) - 0.75) < 0.14), TURQ[2]),
                                gl.__setitem__(ok & (np.abs(pos[..., 2]) < 1.1) & (np.abs(np.arctan2(pos[..., 1], pos[..., 0]) - 0.75) < 0.14), (*TURQ[2][:3], 185)),
                            ))
        # Gear teeth protruding radially along the arc
        for ti in range(6):
            ta = -0.22 + ti * 0.40
            tp = np.array(gear_c) + R_g @ np.array([math.cos(ta) * 15.8, math.sin(ta) * 15.8, 0.0])
            cv.render_ellipsoid(tp, (2.4, 2.4, 2.1), MAT_GOLD, R=R_g, ss=2)
    elif variant == 2:
        # (2) Sandstone parapet baluster (tilted turned stone baluster with brass collar + faint astral glow underneath)
        R_b = rot_z(0.32) @ rot_x(0.2)
        p_bot = tuple(R_b @ np.array([0.0, -13.0, 0.0]))
        p_mid = tuple(R_b @ np.array([0.0, -4.0, 0.0]))
        p_top = tuple(R_b @ np.array([0.0, 13.0, 0.0]))
        cv.render_cylinder(p_bot, p_mid, 6.0, 3.5, MAT_SANDSTONE, ss=3)
        cv.render_cylinder(p_mid, p_top, 3.5, 5.4, MAT_SANDSTONE, ss=3)
        cv.render_ellipsoid(tuple(R_b @ np.array([0.0, 1.0, 0.0])), (6.2, 3.4, 6.2), MAT_SANDSTONE, R=R_b, ss=2)
        cv.render_ring_band(tuple(R_b @ np.array([0.0, 7.2, 0.0])), R_b @ rot_x(math.pi / 2.0), r_in=3.2, r_out=5.8, half_h=1.5, mat=MAT_GOLD, ss=2)
        # Subtle astral-violet levitation seam at broken bottom fracture
        for ax_b, ay_b in ((22, 31), (23, 31), (24, 30)):
            cv.put_px(ax_b, ay_b, ASTRAL[1], mat=MAT_QUARTZ)
            cv.put_glow(ax_b, ay_b, ASTRAL[1][:3], 185)
    elif variant == 3:
        # (3) Faceted floating quartz spirelet
        cv.render_facet_crystal((0.0, 0.0, 0.0), rot_z(-0.22) @ rot_y(0.35), rx=8.2, ry_top=15.0, ry_bot=9.5, n_sides=6, glow_mode="turq", ss=3)
    elif variant == 4:
        # (4) True 3D Tapered Trapezoidal Stone Arch Keystone with recessed glowing rune crack
        R_k = rot_z(-0.14) @ rot_y(0.32)

        def sdf_keystone(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
            q = p @ R_k
            qx, qy, qz = q[..., 0], q[..., 1], q[..., 2]
            t = np.clip((qy + 10.5) / 21.0, 0.0, 1.0)
            hx = 5.0 + 5.6 * t + np.where(qy > 7.0, 1.0, 0.0)
            hz = 4.5 + 1.0 * t + np.where(qy > 7.0, 0.6, 0.0)
            d_wedge = np.maximum(np.maximum(np.abs(qx) - hx, np.abs(qz) - hz), np.abs(qy) - 10.5) - 0.25
            # Recessed central rune fracture seam down front face & top bevel
            seam_x = 0.7 * np.sin(qy * 0.45)
            d_seam = np.maximum(np.maximum(np.abs(qx - seam_x) - 1.05, np.abs(qy) - 7.8), -qz + 2.6)
            d_body = np.maximum(d_wedge, -d_seam)
            return d_body, np.ones(p.shape[:-1], dtype=np.int32)

        def paint_keystone(p: np.ndarray, n: np.ndarray, tag: np.ndarray, sun_vis: np.ndarray, ao: np.ndarray):
            num = p.shape[0]
            q = p @ R_k
            qx, qy, qz = q[..., 0], q[..., 1], q[..., 2]
            lit_base = n @ L_3D
            lit_eff = np.where(sun_vis < 0.5, np.minimum(lit_base * 0.44 - 0.30, -0.20), lit_base)
            lit_eff -= (1.0 - ao) * 0.34
            rgba = ashlar_shade_3d(qx + qz * 0.7, qy, lit_eff, MAT_SANDSTONE, course_h=6.2, block_w=9.5, seed=740)
            mat = np.full(num, MAT_SANDSTONE, dtype=np.int16)
            glow = np.zeros((num, 4), dtype=np.uint8)

            # Crown brass molding edge near top
            on_brass = (qy > 6.2) & (qy < 7.8)
            g_pal = np.array(GOLD, dtype=np.uint8)
            rgba = np.where(on_brass[..., None], g_pal[shade_band_np(lit_eff + 0.14, len(GOLD))], rgba)
            mat = np.where(on_brass, MAT_GOLD, mat)

            # Glowing turquoise & solar-gold rune crack down center fracture
            seam_x = 0.7 * np.sin(qy * 0.45)
            on_rune = (np.abs(qx - seam_x) <= 1.15) & (np.abs(qy) <= 7.8) & (qz > 2.2)
            hot = (np.floor(qy + 11.0).astype(np.int32) % 6) == 0
            r_col = np.where(hot[..., None], SOLAR[2], TURQ[3])
            r_glow = np.where(hot[..., None], (*SOLAR[1][:3], 210), (*TURQ[2][:3], 185))
            rgba = np.where(on_rune[..., None], r_col, rgba)
            mat = np.where(on_rune, MAT_QUARTZ, mat)
            glow = np.where(on_rune[..., None], r_glow, glow)
            return rgba, mat, glow

        render_csg(cv, (2, W - 2, 2, H - 2), (-24.0, 24.0), sdf_keystone, paint_keystone, ss=2, n_steps=44, shadow_steps=10, margin=2)
    else:
        # (5) Sunken/floating carved sandstone star-globe chunk
        cv.render_ellipsoid(
            (0.0, 0.0, 0.0), (13.2, 13.2, 13.2), MAT_SANDSTONE,
            R=rot_y(0.4) @ rot_x(0.2), ss=3,
            clip_fn=lambda q: q[..., 1] + 0.25 * q[..., 0] > -0.52,
            paint_fn=lambda ok, q, nw, lit, rg, ma, gl: (
                # Deep indigo recessed star hemisphere patch + engraved brass meridian ring + constellation pins!
                rg.__setitem__(ok & (q[..., 0] < 0.25) & (q[..., 1] > -0.18), np.array(INDIGO, dtype=np.uint8)[shade_band_np(lit, len(INDIGO))[ok & (q[..., 0] < 0.25) & (q[..., 1] > -0.18)]]),
                ma.__setitem__(ok & (q[..., 0] < 0.25) & (q[..., 1] > -0.18), MAT_INDIGO),
                rg.__setitem__(ok & (np.abs(q[..., 0] - 0.15) < 0.11), GOLD[3]),
                ma.__setitem__(ok & (np.abs(q[..., 0] - 0.15) < 0.11), MAT_GOLD),
                rg.__setitem__(ok & (np.hypot(q[..., 0] + 0.34, q[..., 1] - 0.26) < 0.14), SOLAR[2]),
                gl.__setitem__(ok & (np.hypot(q[..., 0] + 0.34, q[..., 1] - 0.26) < 0.14), (*SOLAR[1][:3], 210)),
                rg.__setitem__(ok & (np.hypot(q[..., 0] + 0.08, q[..., 1] - 0.45) < 0.12), TURQ[3]),
                gl.__setitem__(ok & (np.hypot(q[..., 0] + 0.08, q[..., 1] - 0.45) < 0.12), (*TURQ[2][:3], 195)),
            ),
        )

    px, glow = cv.finalize_with_outlines(foot_cut_y=None, add_internal_creases=True, halo_alpha=0.24)
    return px, glow


# ==============================================================================
# 5. SHEET ASSEMBLY, STRICT VALIDATION & QA CONTACT SHEET
# ==============================================================================
def stitch_strip(frames: list[list[list[tuple[int, int, int, int]]]], fw: int, fh: int) -> list[list[tuple[int, int, int, int]]]:
    cols = len(frames)
    out = [[CLEAR] * (fw * cols) for _ in range(fh)]
    for i, fr in enumerate(frames):
        ox = i * fw
        for y in range(fh):
            out[y][ox : ox + fw] = fr[y]
    return out


def validate_frames(name: str, frames: list[list[list[tuple[int, int, int, int]]]], fw: int, fh: int, margin: int = 2) -> None:
    for i, fr in enumerate(frames):
        assert len(fr) == fh and len(fr[0]) == fw, f"{name}[{i}] bad dimensions {len(fr[0])}x{len(fr)} != {fw}x{fh}"
        xs, ys = [], []
        for y in range(fh):
            for x in range(fw):
                c = fr[y][x]
                if c[3] > 0:
                    assert c[:3] != (0, 0, 0), f"{name}[{i}] has pure #000000 at ({x},{y})!"
                    xs.append(x)
                    ys.append(y)
        if xs:
            assert min(xs) >= margin and max(xs) <= fw - 1 - margin, (
                f"{name}[{i}] horizontal clipping ({fw}x{fh}, margin={margin}): x={min(xs)}..{max(xs)}"
            )
            assert min(ys) >= margin and max(ys) <= fh - 1 - margin, (
                f"{name}[{i}] vertical clipping ({fw}x{fh}, margin={margin}): y={min(ys)}..{max(ys)}"
            )


def write_qa_sheet_clean(
    plaza_pair,
    vault_pair,
    flanks_pairs,
    portal_pair,
    armillary_pairs,
    lens_pairs,
    sundial_court_pair,
    gnomon_pair,
    gate_pair,
    ocular_pair,
    mirror_pair,
    pillar_pairs,
    debris_pairs,
) -> None:
    """2x sunlit desert day + starry night contact sheet with additive glow overlay & Ellie scale reference."""
    W_L = 1188
    H_HALF = 804
    Z = 2
    day_bg = hexc("d8a25e")
    night_bg = hexc("14162c")

    ellie_px = None
    player_path = ROOT / "characters" / "player.png"
    if player_path.exists():
        pim = Image.open(player_path).convert("RGBA")
        crop = pim.crop((12 * 48, 2 * 56, 13 * 48, 3 * 56))
        ellie_px = [[crop.getpixel((x, y)) for x in range(48)] for y in range(56)]

    canvas = np.zeros((H_HALF * 2, W_L, 4), dtype=np.uint8)
    canvas[:H_HALF, :] = day_bg
    canvas[H_HALF:, :] = night_bg

    # Crisp subtle night sky/sand stars on night section
    for k in range(110):
        sx = int(_ihash(k, 1, 901) * (W_L - 8)) + 4
        sy = H_HALF + int(_ihash(k, 2, 901) * (H_HALF - 8)) + 4
        canvas[sy, sx] = (46, 54, 96, 255)

    def blit(layer_rows, ox: int, oy: int, dim: float = 1.0, additive: bool = False) -> None:
        arr = np.array(layer_rows, dtype=np.float32)
        lh, lw = arr.shape[:2]
        x0, y0 = max(0, ox), max(0, oy)
        x1, y1 = min(W_L, ox + lw), min(H_HALF * 2, oy + lh)
        if x1 <= x0 or y1 <= y0:
            return
        sub_s = arr[y0 - oy : y1 - oy, x0 - ox : x1 - ox]
        sub_d = canvas[y0:y1, x0:x1].astype(np.float32)
        a = sub_s[..., 3:4] / 255.0
        if additive:
            out = np.clip(sub_d[..., :3] + sub_s[..., :3] * a, 0.0, 255.0)
        else:
            out = sub_d[..., :3] * (1.0 - a) + sub_s[..., :3] * dim * a
        canvas[y0:y1, x0:x1, :3] = out.astype(np.uint8)
        canvas[y0:y1, x0:x1, 3] = 255

    def draw_sprite(pair, ox: int, oy: int, night: bool) -> None:
        blit(pair[0], ox, oy, dim=(0.42 if night else 1.0), additive=False)
        if night:
            blit(pair[1], ox, oy, additive=True)

    for night in (0, 1):
        oy = night * H_HALF
        dim = 0.42 if night else 1.0

        # A. Top-Left: Full Composite Rotunda Assembly (exact assembly offsets!) + Ellie Scale Reference
        px_c, py_c = 192, oy + 216
        draw_sprite(plaza_pair, px_c - 176, py_c - 128, bool(night))
        draw_sprite(vault_pair, px_c - 128, py_c - 206, bool(night))
        draw_sprite(flanks_pairs[0], px_c - 78 - 52, py_c + 10 - 122, bool(night))
        draw_sprite(flanks_pairs[1], px_c + 78 - 52, py_c + 10 - 122, bool(night))
        draw_sprite(portal_pair, px_c - 68, py_c + 14 - 114, bool(night))
        if ellie_px is not None:
            blit(ellie_px, px_c + 38 - 24, py_c + 44 - 51, dim=dim)

        # B. Top-Center/Right: Sundial Court + Gnomon + Ellie, Ecliptic Gate + Ocular + Ellie, Star Mirror Rim
        sc_x, sc_y = 512, oy + 144
        draw_sprite(sundial_court_pair, sc_x - 120, sc_y - 96, bool(night))
        draw_sprite(gnomon_pair, sc_x - 48, sc_y - 130, bool(night))
        if ellie_px is not None:
            blit(ellie_px, sc_x + 76 - 24, sc_y + 20 - 51, dim=dim)

        eg_x, eg_y = 780, oy + 148
        draw_sprite(gate_pair, eg_x - 80, eg_y - 120, bool(night))
        draw_sprite(ocular_pair, eg_x - 24, (eg_y - 120 + 26) - 24, bool(night))
        if ellie_px is not None:
            blit(ellie_px, eg_x - 24, eg_y + 2 - 51, dim=dim)

        # Star Mirror Rim over subtle cosmic water oval to verify transparent pool center
        sm_x, sm_y = 512, oy + 272
        for yy in range(sm_y - 34, sm_y + 35):
            for xx in range(sm_x - 64, sm_x + 65):
                if ((xx - sm_x) / 63.0) ** 2 + ((yy - sm_y) / 33.0) ** 2 < 1.0:
                    canvas[yy, xx] = (34, 46, 82, 255) if not night else (18, 24, 52, 255)
        draw_sprite(mirror_pair, sm_x - 92, sm_y - 58, bool(night))

        # C. Middle Row: Causeway Pillars (4x), Telescope Lenses (3x), Floating Debris (6x)
        for pi, pp in enumerate(pillar_pairs):
            draw_sprite(pp, 656 + pi * 62, oy + 228, bool(night))

        for li, lp in enumerate(lens_pairs):
            draw_sprite(lp, 392 + li * 74, oy + 356, bool(night))

        for di, dp in enumerate(debris_pairs):
            draw_sprite(dp, 636 + di * 44, oy + 368, bool(night))

        # Isolated Rotunda Portal & Flanks check (left under monument, y = oy + 356)
        draw_sprite(flanks_pairs[0], 10, oy + 356, bool(night))
        draw_sprite(portal_pair, 120, oy + 360, bool(night))
        draw_sprite(flanks_pairs[1], 262, oy + 356, bool(night))

        # Standalone Rotunda Vault inspection (shows open concave south courtyard cleanly!)
        draw_sprite(vault_pair, 922, oy + 14, bool(night))
        if ellie_px is not None:
            blit(ellie_px, 922 + 128 - 24, oy + 14 + 206 - 51, dim=dim)

        # D. Bottom Strip: All 12 Armillary Rings keyframes (6x2 grid of 144x144!)
        for ai, ap in enumerate(armillary_pairs):
            ax_i = 20 + (ai % 6) * 148
            ay_i = oy + 508 + (ai // 6) * 142
            draw_sprite(ap, ax_i, ay_i, bool(night))

    # Nearest-neighbor 2x upscale
    im_up = Image.fromarray(canvas, mode="RGBA").resize((W_L * Z, H_HALF * 2 * Z), resample=Image.NEAREST)
    QA_PATH.parent.mkdir(parents=True, exist_ok=True)
    im_up.save(QA_PATH)
    print(f"Saved QA contact sheet: {QA_PATH} ({W_L * Z}x{H_HALF * 2 * Z})")


def main() -> None:
    OBS_DIR.mkdir(parents=True, exist_ok=True)
    meta: dict[str, object] = {}

    # 1. plaza_mosaic (352x260)
    plaza_px, plaza_gl, plaza_meta = make_plaza_mosaic()
    validate_frames("plaza_mosaic", [plaza_px], 352, 260, margin=2)
    validate_frames("plaza_mosaic_glow", [plaza_gl], 352, 260, margin=1)
    write_png(OBS_DIR / "plaza_mosaic.png", 352, 260, plaza_px)
    write_png(OBS_DIR / "plaza_mosaic_glow.png", 352, 260, plaza_gl)
    meta["plaza_mosaic"] = plaza_meta

    # 2. rotunda_vault (256x236)
    vault_px, vault_gl, vault_meta = make_rotunda_vault()
    validate_frames("rotunda_vault", [vault_px], 256, 236, margin=2)
    validate_frames("rotunda_vault_glow", [vault_gl], 256, 236, margin=1)
    write_png(OBS_DIR / "rotunda_vault.png", 256, 236, vault_px)
    write_png(OBS_DIR / "rotunda_vault_glow.png", 256, 236, vault_gl)
    meta["rotunda_vault"] = vault_meta

    # 3. rotunda_flanks (2x1 of 104x144 = 208x144)
    flanks = [make_rotunda_flank(i) for i in range(2)]
    validate_frames("rotunda_flanks", [f[0] for f in flanks], 104, 144, margin=2)
    validate_frames("rotunda_flanks_glow", [f[1] for f in flanks], 104, 144, margin=1)
    write_png(OBS_DIR / "rotunda_flanks.png", 208, 144, stitch_strip([f[0] for f in flanks], 104, 144))
    write_png(OBS_DIR / "rotunda_flanks_glow.png", 208, 144, stitch_strip([f[1] for f in flanks], 104, 144))
    meta["rotunda_flanks"] = {
        "file": "rotunda_flanks.png",
        "glow": "rotunda_flanks_glow.png",
        "grid": [2, 1],
        "frame": [104, 144],
        "feet": [52, 122],
        "variants": ["west_astrolabe", "east_stairs"],
        "astrolabe_hub": flanks[0][2]["astrolabe_hub"],
    }

    # 4. rotunda_portal (136x140)
    portal_px, portal_gl, portal_meta = make_rotunda_portal()
    validate_frames("rotunda_portal", [portal_px], 136, 140, margin=2)
    validate_frames("rotunda_portal_glow", [portal_gl], 136, 140, margin=1)
    write_png(OBS_DIR / "rotunda_portal.png", 136, 140, portal_px)
    write_png(OBS_DIR / "rotunda_portal_glow.png", 136, 140, portal_gl)
    meta["rotunda_portal"] = portal_meta

    meta["assembly"] = {
        "origin_note": "Offsets relative to plaza_mosaic center [176, 128] / rotunda_vault feet [128, 206]",
        "vault_offset": [0, 0],
        "flank_w_offset": [-78, 10],
        "flank_e_offset": [78, 10],
        "portal_offset": [0, 14],
    }

    # 5. armillary_rings (12x1 of 144x144 = 1728x144)
    armillary = [make_armillary_frame(i) for i in range(12)]
    validate_frames("armillary_rings", [f[0] for f in armillary], 144, 144, margin=2)
    validate_frames("armillary_rings_glow", [f[1] for f in armillary], 144, 144, margin=1)
    write_png(OBS_DIR / "armillary_rings.png", 1728, 144, stitch_strip([f[0] for f in armillary], 144, 144))
    write_png(OBS_DIR / "armillary_rings_glow.png", 1728, 144, stitch_strip([f[1] for f in armillary], 144, 144))
    meta["armillary_rings"] = {
        "file": "armillary_rings.png",
        "glow": "armillary_rings_glow.png",
        "grid": [12, 1],
        "frame": [144, 144],
        "center": [72, 72],
        "core_radius": 12,
        "sun_lugs": [f[2]["sun"] for f in armillary],
        "moon_lugs": [f[2]["moon"] for f in armillary],
    }

    # 6. telescope_lenses (3x1 of 64x64 = 192x64)
    lenses = [make_telescope_lens(i) for i in range(3)]
    validate_frames("telescope_lenses", [f[0] for f in lenses], 64, 64, margin=2)
    validate_frames("telescope_lenses_glow", [f[1] for f in lenses], 64, 64, margin=1)
    write_png(OBS_DIR / "telescope_lenses.png", 192, 64, stitch_strip([f[0] for f in lenses], 64, 64))
    write_png(OBS_DIR / "telescope_lenses_glow.png", 192, 64, stitch_strip([f[1] for f in lenses], 64, 64))
    meta["telescope_lenses"] = {
        "file": "telescope_lenses.png",
        "glow": "telescope_lenses_glow.png",
        "grid": [3, 1],
        "frame": [64, 64],
        "center": [32, 32],
        "variants": ["primary_mirror", "dispersion_prism", "objective_ring"],
        "hubs": [[32, 32], [32, 32], [32, 32]],
        "axis": "SW->NE",
    }

    # 7. sundial_court (240x152) + sundial_gnomon (96x148)
    sc_px, sc_gl, sc_meta = make_sundial_court()
    validate_frames("sundial_court", [sc_px], 240, 152, margin=2)
    validate_frames("sundial_court_glow", [sc_gl], 240, 152, margin=1)
    write_png(OBS_DIR / "sundial_court.png", 240, 152, sc_px)
    write_png(OBS_DIR / "sundial_court_glow.png", 240, 152, sc_gl)
    meta["sundial_court"] = sc_meta

    gn_px, gn_gl, gn_meta = make_sundial_gnomon()
    validate_frames("sundial_gnomon", [gn_px], 96, 148, margin=2)
    validate_frames("sundial_gnomon_glow", [gn_gl], 96, 148, margin=1)
    write_png(OBS_DIR / "sundial_gnomon.png", 96, 148, gn_px)
    write_png(OBS_DIR / "sundial_gnomon_glow.png", 96, 148, gn_gl)
    meta["sundial_gnomon"] = gn_meta

    # 8. ecliptic_gate (160x136) + gate_ocular (48x48)
    eg_px, eg_gl, eg_meta = make_ecliptic_gate()
    validate_frames("ecliptic_gate", [eg_px], 160, 136, margin=2)
    validate_frames("ecliptic_gate_glow", [eg_gl], 160, 136, margin=1)
    # Extra assertion: unobstructed 64 px clear walkable arch span (x=48..112) at feet!
    for y_chk in range(88, 136):
        for x_chk in range(48, 113):
            assert eg_px[y_chk][x_chk][3] == 0, f"ecliptic_gate walkable span obstructed at ({x_chk},{y_chk})!"
    write_png(OBS_DIR / "ecliptic_gate.png", 160, 136, eg_px)
    write_png(OBS_DIR / "ecliptic_gate_glow.png", 160, 136, eg_gl)
    meta["ecliptic_gate"] = eg_meta

    go_px, go_gl, go_meta = make_gate_ocular()
    validate_frames("gate_ocular", [go_px], 48, 48, margin=2)
    validate_frames("gate_ocular_glow", [go_gl], 48, 48, margin=1)
    write_png(OBS_DIR / "gate_ocular.png", 48, 48, go_px)
    write_png(OBS_DIR / "gate_ocular_glow.png", 48, 48, go_gl)
    meta["gate_ocular"] = go_meta

    # 9. star_mirror_rim (184x116)
    sm_px, sm_gl, sm_meta = make_star_mirror_rim()
    validate_frames("star_mirror_rim", [sm_px], 184, 116, margin=2)
    validate_frames("star_mirror_rim_glow", [sm_gl], 184, 116, margin=1)
    # Extra assertion: transparent pool interior strictly alpha==0
    for y_chk in range(116):
        for x_chk in range(184):
            dx, dy = x_chk + 0.5 - 92.0, y_chk + 0.5 - 58.0
            if (dx / 65.0) ** 2 + (dy / 35.0) ** 2 < 1.0:
                assert sm_px[y_chk][x_chk][3] == 0, f"star_mirror_rim pool non-transparent at ({x_chk},{y_chk})"
                assert sm_gl[y_chk][x_chk][3] == 0, f"star_mirror_rim_glow pool non-transparent at ({x_chk},{y_chk})"
    write_png(OBS_DIR / "star_mirror_rim.png", 184, 116, sm_px)
    write_png(OBS_DIR / "star_mirror_rim_glow.png", 184, 116, sm_gl)
    meta["star_mirror_rim"] = sm_meta

    # 10. causeway_pillar (4x1 of 56x96 = 224x96)
    pillars = [make_causeway_pillar(i) for i in range(4)]
    validate_frames("causeway_pillar", [f[0] for f in pillars], 56, 96, margin=2)
    validate_frames("causeway_pillar_glow", [f[1] for f in pillars], 56, 96, margin=1)
    write_png(OBS_DIR / "causeway_pillar.png", 224, 96, stitch_strip([f[0] for f in pillars], 56, 96))
    write_png(OBS_DIR / "causeway_pillar_glow.png", 224, 96, stitch_strip([f[1] for f in pillars], 56, 96))
    meta["causeway_pillar"] = {
        "file": "causeway_pillar.png",
        "glow": "causeway_pillar_glow.png",
        "grid": [4, 1],
        "frame": [56, 96],
        "feet": [28, 84],
        "variants": ["harp_left", "harp_right", "polar_ocular", "prism_altar"],
        "focal_points": [f[2] for f in pillars],
    }

    # 11. floating_debris (6x1 of 40x40 = 240x40)
    debris = [make_floating_debris(i) for i in range(6)]
    validate_frames("floating_debris", [f[0] for f in debris], 40, 40, margin=2)
    validate_frames("floating_debris_glow", [f[1] for f in debris], 40, 40, margin=1)
    write_png(OBS_DIR / "floating_debris.png", 240, 40, stitch_strip([f[0] for f in debris], 40, 40))
    write_png(OBS_DIR / "floating_debris_glow.png", 240, 40, stitch_strip([f[1] for f in debris], 40, 40))
    meta["floating_debris"] = {
        "file": "floating_debris.png",
        "glow": "floating_debris_glow.png",
        "grid": [6, 1],
        "frame": [40, 40],
        "center": [20, 20],
        "variants": ["dome_tile", "gear_arc", "baluster", "quartz_spire", "arch_keystone", "star_globe"],
    }

    DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    DATA_PATH.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote observatory art metadata: {DATA_PATH}")

    write_qa_sheet_clean(
        (plaza_px, plaza_gl),
        (vault_px, vault_gl),
        [(f[0], f[1]) for f in flanks],
        (portal_px, portal_gl),
        [(f[0], f[1]) for f in armillary],
        lenses,
        (sc_px, sc_gl),
        (gn_px, gn_gl),
        (eg_px, eg_gl),
        (go_px, go_gl),
        (sm_px, sm_gl),
        [(f[0], f[1]) for f in pillars],
        debris,
    )
    print("ALL 11 observatory sheets + glow pairs verified cleanly (zero #000000, zero frame clipping).")


if __name__ == "__main__":
    main()
