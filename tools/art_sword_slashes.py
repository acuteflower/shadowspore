#!/usr/bin/env python3
"""Deterministic pixel-art sword swing VFX generator for Shadowspore 2.0.

Generates 6 richly textured, frame-by-frame animated pixel-art sword slash sheets
in a crisp, normal Tempered-Steel / Wind-Shear aesthetic (no elemental theme,
designed to pop cleanly in both sunlit meadows and dark nights, and seamlessly
palette-remappable in `assets/shaders/sword_slash.gdshader` for unique weapons):

  1. sword_slash_forehand.png   (10 x 1 of  96x96  =  960x96,  pivot (48, 48))
  2. sword_slash_backhand.png   (10 x 1 of  96x96  =  960x96,  pivot (48, 48))
  3. sword_slash_thrust.png     (10 x 1 of  96x64  =  960x64,  pivot (16, 32))
  4. sword_slash_uppercut.png   (10 x 1 of 104x104 = 1040x104, pivot (52, 52))
  5. sword_slash_whirlwind.png  (12 x 1 of 112x112 = 1344x112, pivot (56, 56))
  6. sword_slash_heavy.png      (12 x 1 of 112x112 = 1344x112, pivot (56, 56))

Visual QA Contact Sheet:
  py -3 tools/art_sword_slashes.py preview <out.png>

Usage:
  py -3 tools/art_sword_slashes.py
"""
import math
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import ROOT  # noqa: E402


# ==============================================================================
# 5-TONE TEMPERED STEEL / WIND-SHEAR PALETTE (Normal Sword Aesthetic)
# Strictly distinct luminance bands so `sword_slash.gdshader` can also remap
# custom weapon `fx` ramps cleanly without banding artifacts.
# ==============================================================================
# 0 = clear, 1 = deep indigo shear, 2 = tempered slate shadow,
# 3 = airy steel-silver mid, 4 = bright steel-white core, 5 = blazing white cutting edge
PALETTE = np.array(
    [
        [0, 0, 0, 0],          # 0: clear
        [36, 44, 84, 240],     # 1: deep cool indigo shear (#242c54, lum ~0.18)
        [86, 114, 174, 250],   # 2: tempered slate-blue shadow (#5672ae, lum ~0.43)
        [158, 192, 238, 255],  # 3: airy steel-silver mid (#9ec0ee, lum ~0.72)
        [226, 242, 255, 255],  # 4: bright steel-white core (#e2f2ff, lum ~0.92)
        [255, 255, 255, 255],  # 5: pure white cutting edge (#ffffff, lum 1.00)
    ],
    dtype=np.uint8,
)


# ==============================================================================
# DETERMINISTIC STREAMLINE NOISE & DRAWING PRIMITIVES
# ==============================================================================
def _hash2(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    n = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF).astype(np.float64) / 65535.0


def smooth_noise(x: np.ndarray, y: np.ndarray, seed: int) -> np.ndarray:
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    a = _hash2(ix, iy, seed)
    b = _hash2(ix + 1, iy, seed)
    c = _hash2(ix, iy + 1, seed)
    d = _hash2(ix + 1, iy + 1, seed)
    return (a * (1.0 - ux) + b * ux) * (1.0 - uy) + (c * (1.0 - ux) + d * ux) * uy


def fbm_stream(u: np.ndarray, v: np.ndarray, seed: int) -> np.ndarray:
    """Strongly arc-aligned calligraphic flow noise (long streaks, never circular blobs)."""
    n1 = smooth_noise(u * 2.8, v * 3.6, seed)
    n2 = smooth_noise(u * 6.4 + 4.1, v * 7.8 + 2.3, seed + 61)
    return 0.72 * n1 + 0.28 * n2


def clamp01(x: np.ndarray) -> np.ndarray:
    return np.clip(x, 0.0, 1.0)


def clamp01_s(x: float) -> float:
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = clamp01((x - e0) / max(e1 - e0, 1e-6))
    return t * t * (3.0 - 2.0 * t)


def _tone_to_rgba(tone: np.ndarray, alpha_scale: np.ndarray) -> np.ndarray:
    h, w = tone.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)
    valid = (tone > 0) & (alpha_scale > 0.14)
    if not np.any(valid):
        return out
    cols = PALETTE[tone[valid]]
    a_raw = cols[:, 3].astype(np.float64) * alpha_scale[valid]
    # Crisp stepped pixel-art opacity (never blurry soft alpha)
    a_step = np.where(
        a_raw >= 220.0,
        255,
        np.where(a_raw >= 170.0, 224, np.where(a_raw >= 120.0, 172, 124)),
    ).astype(np.uint8)
    out[valid, 0] = cols[:, 0]
    out[valid, 1] = cols[:, 1]
    out[valid, 2] = cols[:, 2]
    out[valid, 3] = a_step
    return out


def _put_px(tone: np.ndarray, ascale: np.ndarray, x: int, y: int, t: int, a: float = 1.0, overwrite_brighter: bool = True) -> None:
    h, w = tone.shape
    if 0 <= x < w and 0 <= y < h:
        if not overwrite_brighter or t > tone[y, x] or (t == tone[y, x] and a > ascale[y, x]):
            tone[y, x] = t
            ascale[y, x] = a


def _draw_star_glint(tone: np.ndarray, ascale: np.ndarray, cx: float, cy: float, arm: int, core_tone: int = 5, wing_tone: int = 4, alpha: float = 1.0) -> None:
    """Crisp 4-point pixel star sparkle (+ / diamond)."""
    ix, iy = int(round(cx)), int(round(cy))
    if arm <= 0:
        _put_px(tone, ascale, ix, iy, core_tone, alpha)
        return
    _put_px(tone, ascale, ix, iy, core_tone, alpha)
    for d in range(1, arm + 1):
        t_cur = core_tone if (arm >= 3 and d == 1) else wing_tone
        a_cur = alpha if d < arm else alpha * 0.80
        _put_px(tone, ascale, ix + d, iy, t_cur, a_cur)
        _put_px(tone, ascale, ix - d, iy, t_cur, a_cur)
        _put_px(tone, ascale, ix, iy + d, t_cur, a_cur)
        _put_px(tone, ascale, ix, iy - d, t_cur, a_cur)
    if arm >= 3:
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            _put_px(tone, ascale, ix + dx, iy + dy, max(wing_tone - 1, 2), alpha * 0.65)


def _draw_curved_ribbon(
    tone: np.ndarray,
    ascale: np.ndarray,
    cx: float,
    cy: float,
    a0: float,
    a1: float,
    r0: float,
    r1: float,
    thick_max: float,
    tone_outer: int,
    tone_inner: int,
    alpha: float = 1.0,
    peak_u: float = 0.68,
    wobble_amp: float = 0.0,
    wobble_freq: float = 2.0,
    wobble_phase: float = 0.0,
    overwrite_brighter: bool = True,
) -> None:
    """Draws a razor-sharp asymmetric calligraphic curved ribbon / wisp along an arc."""
    arc_len = abs(a1 - a0) * max(r0, r1)
    steps = max(10, int(math.ceil(arc_len * 2.5)))
    for i in range(steps + 1):
        u = i / steps
        ang = a0 + (a1 - a0) * u
        rad = r0 + (r1 - r0) * u + wobble_amp * math.sin(u * math.pi * wobble_freq + wobble_phase)
        px = cx + math.cos(ang) * rad
        py = cy + math.sin(ang) * rad
        # Asymmetric sharp teardrop taper (needle tail -> peak at peak_u -> razor tip!)
        if u <= peak_u:
            env = (u / max(peak_u, 0.05)) ** 1.15
        else:
            env = ((1.0 - u) / max(1.0 - peak_u, 0.05)) ** 0.95
        th = thick_max * env
        t_head = tone_outer if u > 0.45 else max(1, tone_outer - 1)
        ix, iy = int(round(px)), int(round(py))
        if th < 0.72:
            if env > 0.10:
                _put_px(tone, ascale, ix, iy, t_head if u > 0.35 else tone_inner, alpha * (0.76 if env < 0.32 else 1.0), overwrite_brighter)
        else:
            nx, ny = math.cos(ang), math.sin(ang)
            n_off = int(math.ceil(th * 0.55))
            for k in range(-n_off, n_off + 1):
                if abs(k) <= th * 0.54:
                    kx = int(round(px + nx * k))
                    ky = int(round(py + ny * k))
                    frac = (k / max(th * 0.54, 0.5) + 1.0) * 0.5  # 0 inner .. 1 outer
                    kt = tone_outer if frac > 0.65 else (tone_inner if frac < 0.32 else int(round(0.5 * (tone_outer + tone_inner))))
                    _put_px(tone, ascale, kx, ky, kt, alpha, overwrite_brighter)


def _draw_curved_shard(
    tone: np.ndarray,
    ascale: np.ndarray,
    cx: float,
    cy: float,
    ang_center: float,
    rad: float,
    arc_rad: float,
    sweep_sign: int,
    thick: float,
    t_outer: int,
    t_inner: int,
    alpha: float = 1.0,
    dark_keel: bool = True,
) -> None:
    """Draws a crisp curved crescent breakup shard/chunk (like Sunpixels 00:03 breakup chunks!)."""
    a0 = ang_center - sweep_sign * arc_rad * 0.55
    a1 = ang_center + sweep_sign * arc_rad * 0.45
    _draw_curved_ribbon(
        tone, ascale, cx, cy,
        a0, a1,
        rad - 0.6, rad + 0.8,
        thick,
        tone_outer=t_outer,
        tone_inner=t_inner,
        alpha=alpha,
        peak_u=0.65,
    )
    if dark_keel and thick >= 1.5:
        # Crisp 1px dark-indigo underside keel on the trailing inner half of the chunk
        steps = max(4, int(math.ceil(abs(a1 - a0) * rad * 1.4)))
        for i in range(1, steps):
            u = i / steps
            if u < 0.15 or u > 0.78:
                continue
            ang = a0 + (a1 - a0) * u
            kr = rad - thick * 0.58 - 0.55
            _put_px(tone, ascale, int(round(cx + math.cos(ang) * kr)), int(round(cy + math.sin(ang) * kr)), 1, alpha * 0.90, overwrite_brighter=False)


def _draw_sliver_cluster(
    tone: np.ndarray,
    ascale: np.ndarray,
    cx: float,
    cy: float,
    tang_ang: float,
    length: float,
    width: float,
    t_core: int,
    t_edge: int,
    alpha: float = 1.0,
    dark_accent: bool = False,
) -> None:
    """Draws a sleek directional tapered steel-wind sliver aligned with arc velocity."""
    dx, dy = math.cos(tang_ang), math.sin(tang_ang)
    nx, ny = -dy, dx
    steps = max(2, int(math.ceil(length * 2.2)))
    for i in range(steps + 1):
        u = i / steps - 0.5
        s = u * length
        bow = (0.25 - u * u) * 1.15
        px = cx + dx * s + nx * bow
        py = cy + dy * s + ny * bow
        half_w = width * 0.5 * max(0.0, 1.0 - abs(u) * 1.85)
        t_cur = t_core if u > 0.02 else t_edge
        _put_px(tone, ascale, int(round(px)), int(round(py)), t_cur, alpha)
        if half_w >= 0.52:
            _put_px(tone, ascale, int(round(px + nx * half_w)), int(round(py + ny * half_w)), min(5, t_cur + 1), alpha)
            _put_px(tone, ascale, int(round(px - nx * half_w)), int(round(py - ny * half_w)), max(1, t_edge - 1), alpha * 0.92)
    if dark_accent and length >= 2.4:
        bx = int(round(cx - dx * length * 0.22 - nx * (width * 0.55 + 0.65)))
        by = int(round(cy - dy * length * 0.22 - ny * (width * 0.55 + 0.65)))
        _put_px(tone, ascale, bx, by, 1, alpha * 0.88, overwrite_brighter=False)


def _add_selective_shadow_rim(tone: np.ndarray, ascale: np.ndarray, strength: float) -> None:
    """Crisp 1px deep-indigo contrast edge selectively along shaded inner/bottom edges
    so steel-white slashes stay razor-readable over sunlit meadow grass and bright sand."""
    if strength <= 0.05:
        return
    h, w = tone.shape
    orig = tone.copy()
    orig_a = ascale.copy()
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if orig[y, x] != 0:
                continue
            nb = (orig[y - 1, x], orig[y + 1, x], orig[y, x - 1], orig[y, x + 1])
            has_body = any(1 <= nt <= 3 for nt in nb)
            has_hot = any(nt >= 5 for nt in nb)
            if not has_body or has_hot:
                continue
            # Top-left light rule: shadow edge falls on bottom/right of mid-shadow clusters
            bottom_right = (1 <= orig[y - 1, x] <= 3) or (1 <= orig[y, x - 1] <= 3)
            inner_dark = (orig[y, x + 1] in (1, 2)) or (orig[y + 1, x] in (1, 2))
            if bottom_right or (strength > 0.55 and inner_dark):
                max_a = max(orig_a[y - 1, x], orig_a[y + 1, x], orig_a[y, x - 1], orig_a[y, x + 1])
                if max_a >= 0.82:
                    tone[y, x] = 1
                    ascale[y, x] = min(1.0, 0.88 * strength + 0.12)


# ==============================================================================
# ARC SLASH SYNTHESIS ENGINE v2
# ==============================================================================
def render_arc_sheet(cfg: dict) -> Image.Image:
    frames = cfg["frames"]
    size = cfg["size"]
    cx = cy = size * 0.5
    base_r = cfg["radius"]
    max_thick = cfg["thick"]
    arc_start_deg = cfg["arc_start_deg"]
    arc_end_deg = cfg["arc_end_deg"]
    sweep_sign = cfg["sweep_sign"]
    seed = cfg["seed"]
    is_whirl = cfg.get("whirlwind", False)
    is_heavy = cfg.get("heavy", False)
    wisp_count = cfg.get("wisps", 5)
    outer_filaments = cfg.get("outer_filaments", 2)
    star_count = cfg.get("stars", 8)
    sliver_count = cfg.get("slivers", 18)
    shard_count = cfg.get("shards", 9)

    sheet = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))

    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    dx = xs + 0.5 - cx
    dy = (ys + 0.5 - cy) * sweep_sign  # canonical positive sweep direction
    r_grid = np.hypot(dx, dy)
    ang_grid = np.arctan2(dy, dx)

    a_start = math.radians(arc_start_deg)
    a_end = math.radians(arc_end_deg)
    total_span = a_end - a_start

    rel_ang = (ang_grid - a_start) % math.tau
    if not is_whirl:
        rel_ang = np.where(rel_ang > math.tau - 0.85, rel_ang - math.tau, rel_ang)

    rng = np.random.default_rng(seed)

    # 1. Persistent inner swept-back fluid wisps (forked wind-tongues peeling backward off concave edge!)
    wisps = []
    for wi in range(wisp_count):
        base_u = 0.20 + (wi + 0.35) / wisp_count * 0.62 + rng.uniform(-0.035, 0.035)
        wlen = rng.uniform(0.14, 0.24) * (0.72 if is_whirl else 1.0)
        idrop = rng.uniform(3.5, 7.2) * (1.22 if is_heavy else 1.0)
        wth = rng.uniform(1.5, 2.8) * (1.18 if is_heavy else 1.0)
        wisps.append((base_u, wlen, idrop, wth, rng.uniform(0.0, math.tau)))

    # 2. Persistent curved breakup crescent shards (visible during frames 3..7, Sunpixels 00:03 feel!)
    shards = []
    for sh_i in range(shard_count):
        su0 = 0.14 + (sh_i + 0.4) / shard_count * 0.80 + rng.uniform(-0.04, 0.04)
        sr_off = rng.uniform(-5.2, 2.4) * (1.15 if is_heavy else 1.0)
        s_arc = rng.uniform(0.16, 0.34) * (1.1 if is_heavy else 1.0)
        s_th = rng.uniform(1.6, 3.4) * (1.2 if is_heavy else 1.0)
        s_born = rng.uniform(0.32, 0.48)
        s_end = rng.uniform(0.68, 0.88)
        s_du = rng.uniform(0.06, 0.15) * (0.65 if is_whirl else 1.0)
        s_dr = rng.uniform(2.5, 7.8) * (1.2 if is_heavy else 1.0)
        is_outer_sh = sh_i % 2 == 0
        shards.append((su0, sr_off, s_arc, s_th, s_born, s_end, s_du, s_dr, is_outer_sh))

    # 3. Persistent flying wind-steel slivers (2..6px tapered darts spinning off the curve)
    slivers = []
    for si in range(sliver_count):
        u0 = rng.uniform(0.08, 0.99)
        r_bias = rng.uniform(-0.48, 0.46)
        drift_u = rng.uniform(0.07, 0.22) * (0.65 if is_whirl else 1.0)
        drift_r = rng.uniform(3.0, 10.5) * (1.25 if is_heavy else 1.0)
        born_f = rng.uniform(0.12, 0.48)
        life_f = rng.uniform(0.30, 0.52)
        slen = rng.uniform(2.4, 5.8) * (1.15 if is_heavy else 1.0)
        swid = rng.uniform(0.9, 1.7)
        bright = si % 3 != 0
        slivers.append((u0, r_bias, drift_u, drift_r, born_f, life_f, slen, swid, bright))

    # 4. Crisp 4-point pixel star glints (twinkling aftermath like 00:00-00:01 of video)
    stars = []
    for ki in range(star_count):
        u0 = 0.10 + (ki + 0.5) / star_count * 0.86 + rng.uniform(-0.05, 0.05)
        r_off = rng.uniform(-5.5, 6.2)
        born_f = rng.uniform(0.34, 0.76)
        peak_f = min(0.92, born_f + rng.uniform(0.08, 0.14))
        end_f = min(1.00, peak_f + rng.uniform(0.16, 0.26))
        max_arm = int(rng.choice([1, 2, 2, 3])) if (is_heavy or is_whirl) else int(rng.choice([1, 2, 2]))
        drift_r = rng.uniform(1.8, 5.8)
        drift_u = rng.uniform(0.03, 0.11)
        stars.append((u0, r_off, born_f, peak_f, end_f, max_arm, drift_r, drift_u))

    # 5. Graceful aftermath curved wind-threads (1px swirling filaments in frames 4..8)
    threads = []
    n_threads = 7 if (is_whirl or is_heavy) else 5
    for ti in range(n_threads):
        tu0 = 0.06 + (ti / max(n_threads, 1)) * 0.70 + rng.uniform(-0.04, 0.04)
        tspan = rng.uniform(0.18, 0.34) * (0.72 if is_whirl else 1.0)
        tr_off = rng.uniform(-5.5, 4.2)
        t_born = rng.uniform(0.32, 0.52)
        t_end = rng.uniform(0.76, 0.94)
        t_du = rng.uniform(0.08, 0.18) * (0.65 if is_whirl else 1.0)
        t_dr = rng.uniform(2.5, 6.8)
        threads.append((tu0, tspan, tr_off, t_born, t_end, t_du, t_dr, ti % 2 == 0))

    # Precompute sharp sickle thickness profile normalization
    # f(u) = (u ** p1) * ((1 - u) ** p2): sharp needle tail AND sharp razor hooked blade tip!
    p1 = 1.02 if is_whirl else 1.28
    p2 = 0.68 if is_whirl else 0.78
    u_peak = p1 / (p1 + p2)
    belly_peak = (u_peak ** p1) * ((1.0 - u_peak) ** p2)

    for fi in range(frames):
        t = fi / float(frames - 1)
        tone = np.zeros((size, size), dtype=np.int32)
        ascale = np.zeros((size, size), dtype=np.float64)

        # ---- 1. FRAME KINEMATICS ----
        # Frame 0 ALREADY whips out ~68% as an instant razor-sharp flash so attacks feel ultra snappy!
        if t < 0.16:
            p_whip = t / 0.16
            head_u = 0.68 + 0.32 * (1.0 - (1.0 - p_whip) ** 2.5)
        else:
            head_u = 1.0 + 0.09 * ((t - 0.16) / 0.84) ** 0.75

        # Tail stays anchored during peak, then whips forward while trailing wisps peel off behind!
        if t < 0.22:
            tail_u = 0.0
        else:
            tail_u = min(0.76, ((t - 0.22) / 0.78) ** 1.22 * 0.70)

        # Centrifugal expansion
        r_expand = (5.2 if is_heavy else (4.0 if is_whirl else 3.4)) * (1.0 - (1.0 - t) ** 1.85)

        # Bold thickness curve: Frame 0 sleek razor whip -> Frame 1-3 lush maximum meat -> Frame 4-6 thins & splits!
        if t < 0.12:
            thick_time = 0.56 + 0.44 * (t / 0.12) ** 0.6
        elif t < 0.34:
            thick_time = 1.0
        else:
            thick_time = max(0.0, 1.0 - ((t - 0.34) / 0.44) ** 1.15)

        u_raw = rel_ang / total_span
        span_now = max(head_u - tail_u, 0.14)
        u_local = (u_raw - tail_u) / span_now
        in_arc = (u_local >= 0.0) & (u_local <= 1.0)

        # ---- 2. MAIN SCULPTED SICKLE CRESCENT BODY (Razor Tail + Sharp Hooked Blade Tip!) ----
        if thick_time > 0.02 and t < 0.76:
            u_c = clamp01(u_local)

            # Outer spiral contour: pulls cleanly from tighter tail out to peak arc, then hooks smoothly
            # into a razor-sharp scythe/katana tip (ZERO blunt thumb end!)
            hook_u = np.maximum(u_c - 0.78, 0.0) / 0.22
            hook_in = (hook_u ** 1.85) * (5.2 if is_heavy else 4.2)
            tail_in = ((1.0 - u_c) ** 1.8) * (4.8 if not is_whirl else 6.2)
            swell_out = 2.6 * np.sin(math.pi * (u_c ** 0.82))
            rim_wave = 0.65 * np.sin(u_c * 8.5 + seed * 0.7) * np.sin(math.pi * u_c)
            r_out = base_r + r_expand - tail_in + swell_out - hook_in + rim_wave

            # Sleek asymmetric sickle belly tapering cleanly to razor points at BOTH ends!
            belly_norm = np.clip((u_c ** p1) * ((1.0 - u_c) ** p2) / belly_peak, 0.0, 1.0)

            # Sharp swept-back fluid notches & wind-hooks along inner concave edge (Sunpixels dynamic silhouette!)
            notch_a = np.exp(-(((u_c - 0.34) / 0.075) ** 2)) * 0.28
            notch_b = np.exp(-(((u_c - 0.57) / 0.07) ** 2)) * 0.24
            notch_c = np.exp(-(((u_c - 0.77) / 0.06) ** 2)) * 0.16 if (is_heavy or is_whirl) else 0.0
            # Sharp swept wind-crest spikes right behind each concave notch!
            spike_a = np.exp(-(((u_c - 0.43) / 0.038) ** 2)) * 0.20
            spike_b = np.exp(-(((u_c - 0.66) / 0.036) ** 2)) * 0.18
            scallop = 0.10 * np.sin(u_c * (22.0 if is_whirl else 14.5) - t * 3.5 + seed) * np.sin(math.pi * u_c)

            w_local = max_thick * thick_time * np.clip(belly_norm * (1.0 - notch_a - notch_b - notch_c + spike_a + spike_b) + scallop * 0.32, 0.0, 1.22)
            # Ensure a crisp 1px needle tip right up to u=0.98 and tail down to u=0.04!
            needle_floor = np.where((u_c > 0.04) & (u_c < 0.99), 1.05 * np.sin(math.pi * u_c) ** 0.35 * thick_time, 0.0)
            w_local = np.maximum(w_local, needle_floor)
            r_in = r_out - w_local

            v_raw = (r_grid - r_in) / np.maximum(w_local, 0.5)
            v = clamp01(v_raw)
            inside = in_arc & (r_grid <= r_out) & (r_grid >= r_in) & (w_local >= 0.78)

            # ---- 3. CALLIGRAPHIC STREAMLINE BANDS & KINETIC EROSION ----
            u_flow = u_raw * (2.2 if is_whirl else 1.55) - t * 1.1
            v_shear = v + 0.38 * u_c - 0.12 * np.sin(u_c * 6.5 + seed)
            flow_n = fbm_stream(u_flow, v_shear * 1.35, seed + 13)

            # Kinetic erosion (Frames 3+): opens long curved calligraphic gaps along streamlines!
            erode_t = max(0.0, (t - 0.24) / 0.48)
            if erode_t > 0.0:
                rim_protect = 0.40 * (v ** 2.1) + 0.18 * (u_c ** 1.7)
                # Combine continuous curved ribbon channel + streamline noise so splits are SLEEK, not noisy!
                split_wave = 0.5 + 0.5 * np.sin(v * 9.5 + u_c * 8.0 - t * 6.0 + seed)
                channel = 0.65 * flow_n + 0.35 * split_wave
                thresh = erode_t * 1.24 - rim_protect + 0.14 * (1.0 - np.sin(math.pi * u_c))
                survived = channel > thresh
                # Razor outer cutting ribbon lingers 1 frame longer as a crisp arc!
                razor_rim = (v > 0.86) & (u_c > 0.25) & (u_c < 0.96) & (channel > erode_t * 0.90 - 0.16) & (t < 0.64)
                inside = inside & (survived | razor_rim)

            # ---- 4. GRAPHIC 5-TONE TEMPERED STEEL / WIND-SHEAR SHADING ----
            # Clean, bold, hand-painted cel planes sculpted by sweeping calligraphic ribbons!
            head_heat = smoothstep(0.28, 0.94, u_c)
            flash_boost = 0.16 * max(0.0, 1.0 - t / 0.24)
            cool_drop = 0.16 * max(0.0, (t - 0.30) / 0.46)

            # Clean longitudinal curvature shift (smooth calligraphic band wave, ZERO dotty noise!)
            band_curve = 0.10 * np.sin(u_c * 7.2 + seed * 0.5) + (flow_n - 0.5) * 0.26
            val = 0.60 * v + 0.24 * head_heat + 0.14 * (v ** 2.4) + band_curve + flash_boost - cool_drop

            # 1) Blazing pure-white outer cutting edge (thickest near cutting head, tapering into needle!)
            edge_w = (2.4 if is_heavy else 1.75) * (0.45 + 0.55 * head_heat) * (1.0 if t < 0.35 else 0.75)
            is_cutting_edge = (r_out - r_grid <= edge_w) & (u_c > 0.20) & (t < 0.56)

            # 2) Sweeping calligraphic bright steel core-ribbon curving cleanly inside the belly!
            rib1_v = 0.68 - 0.16 * (1.0 - u_c) + 0.06 * np.sin(u_c * 8.0 + seed)
            is_core_rib = (np.abs(v - rib1_v) < 0.095) & (u_c > 0.22) & (u_c < 0.94) & (t < 0.48)

            # 3) Sweeping dark slate calligraphic shadow channel slicing along the inner belly!
            furrow_v = 0.32 + 0.08 * np.sin(u_c * 6.8 + seed * 1.9) - 0.08 * (1.0 - u_c)
            is_furrow = (np.abs(v - furrow_v) < 0.115) & (u_c > 0.15) & (u_c < 0.84) & (w_local > 4.5)

            # 4) Deep cool indigo underside shear groove along inner edge
            is_inner_shear = (v < 0.16) & (u_c < 0.80)

            body_tone = np.where(val >= 0.86, 5, np.where(val >= 0.65, 4, np.where(val >= 0.42, 3, np.where(val >= 0.23, 2, 1))))
            body_tone = np.where(is_furrow & (body_tone >= 3), 2, body_tone)
            body_tone = np.where(is_inner_shear & (body_tone >= 2), 1, body_tone)
            body_tone = np.where(is_core_rib & (body_tone < 4), 4, body_tone)
            body_tone = np.where(is_cutting_edge, 5, body_tone)

            # Graceful dark-slate wind-tail cooling at the very rear horn
            body_tone = np.where((u_c < 0.15) & (body_tone > 3), 3, body_tone)
            body_tone = np.where((u_c < 0.08) & (body_tone > 2), 2, body_tone)

            # Heavy Wuchtschlag gets a blazing secondary crescent rib for extra impact punch!
            if is_heavy and t < 0.44:
                heavy_rib = (np.abs(v - 0.46) < 0.075) & (u_c > 0.32) & (u_c < 0.94)
                body_tone = np.where(heavy_rib, np.maximum(body_tone, 4), body_tone)

            body_alpha = np.where(v < 0.10, 0.86, 1.0)
            if t > 0.50:
                body_alpha = body_alpha * max(0.56, 1.0 - (t - 0.50) * 1.15)

            tone = np.where(inside, body_tone, tone)
            ascale = np.where(inside, body_alpha, ascale)

        # ---- 5. SWEPT-BACK INNER FLUID WISPS (Forked wind-tongues curling back along concave edge!) ----
        if 0.06 <= t <= 0.64:
            wisp_env = math.sin(math.pi * clamp01_s((t - 0.06) / 0.58))
            for bu, wlen, idrop, wth, wph in wisps:
                if head_u < bu + 0.04:
                    continue
                u_tip = bu + 0.08 * t
                u_tail = u_tip - wlen * (0.78 + 0.42 * wisp_env)
                if u_tip <= tail_u + 0.03:
                    continue
                r_anchor = base_r + r_expand - max_thick * 0.48 * (0.45 + 0.55 * math.sin(math.pi * clamp01_s(u_tip)))
                ang_head = (a_start + u_tip * total_span) * sweep_sign
                ang_tail = (a_start + u_tail * total_span) * sweep_sign
                _draw_curved_ribbon(
                    tone, ascale, cx, cy,
                    ang_tail, ang_head,
                    r_anchor - idrop, r_anchor + 1.4,
                    wth * (0.62 + 0.38 * wisp_env),
                    tone_outer=3 if t < 0.40 else 2,
                    tone_inner=1,
                    alpha=0.94 if t < 0.46 else 0.76,
                    peak_u=0.72,
                    wobble_amp=0.55,
                    wobble_freq=2.0,
                    wobble_phase=wph,
                )

        # ---- 6. PEELING OUTER CENTRIFUGAL SHOCK-FILAMENTS ----
        # Attached tightly near their leading head, peeling gracefully outward toward their trailing tail!
        if 0.10 <= t <= 0.78:
            for oi in range(outer_filaments):
                frac = oi / max(outer_filaments, 1)
                f_start = 0.14 + 0.28 * frac + 0.18 * t
                f_end = min(1.05, f_start + (0.34 if not is_whirl else 0.26) * (1.0 - 0.30 * t))
                if head_u < f_start + 0.06:
                    continue
                f_end = min(f_end, head_u + 0.02)
                peel_out = 1.6 + 4.4 * ((t - 0.10) / 0.68) + oi * 1.3
                # Trailing end lifts further outward (centrifugal peel!) while leading tip kisses the crescent rim
                r_f0 = base_r + r_expand + peel_out * 1.25
                r_f1 = base_r + r_expand + peel_out * 0.35
                ang0 = (a_start + f_start * total_span) * sweep_sign
                ang1 = (a_start + f_end * total_span) * sweep_sign
                _draw_curved_ribbon(
                    tone, ascale, cx, cy,
                    ang0, ang1,
                    r_f0, r_f1,
                    1.35 if (is_heavy and t < 0.40) else 0.85,
                    tone_outer=5 if t < 0.38 else 4,
                    tone_inner=2 if t > 0.44 else 3,
                    alpha=0.96 if t < 0.52 else 0.72,
                    peak_u=0.72,
                )

        # ---- 7. BOLD CURVED BREAKUP CRESCENT SHARDS (Frames 3..8 — Sunpixels 00:03 iconic look!) ----
        for su0, sr_off, s_arc, s_th, s_born, s_end, s_du, s_dr, is_outer_sh in shards:
            if not (s_born <= t <= s_end):
                continue
            lt = (t - s_born) / max(s_end - s_born, 0.01)
            u_cur = su0 + s_du * (1.0 - (1.0 - lt) ** 1.6)
            if u_cur > head_u + 0.08:
                continue
            ang_c = (a_start + u_cur * total_span) * sweep_sign
            r_cur = base_r + r_expand * 0.85 + sr_off + s_dr * (lt ** 0.85)
            arc_now = s_arc * (1.0 - 0.45 * lt)
            th_now = s_th * (1.0 - 0.65 * lt)
            t_out = (5 if lt < 0.30 else 4) if is_outer_sh else (4 if lt < 0.25 else 3)
            t_in = 3 if is_outer_sh else 2
            _draw_curved_shard(
                tone, ascale, cx, cy,
                ang_c, r_cur, arc_now, sweep_sign, th_now,
                t_outer=t_out, t_inner=t_in,
                alpha=0.96 if lt < 0.62 else 0.72,
                dark_keel=(lt < 0.68),
            )

        # ---- 8. LINGERING AFTERMATH CURVED WIND-THREADS (Sunpixels 00:00-00:01!) ----
        for tu0, tspan, tr_off, t_born, t_end, t_du, t_dr, is_bright in threads:
            if not (t_born <= t <= t_end):
                continue
            lt = (t - t_born) / max(t_end - t_born, 0.01)
            u_a = tu0 + t_du * lt + tspan * 0.50 * (lt ** 1.25)
            u_b = tu0 + t_du * lt + tspan * (1.0 - 0.10 * lt)
            if u_b - u_a < 0.025:
                continue
            r_a = base_r + tr_off + t_dr * lt - 1.2
            r_b = base_r + tr_off + t_dr * lt + 1.0
            ang_a = (a_start + u_a * total_span) * sweep_sign
            ang_b = (a_start + u_b * total_span) * sweep_sign
            _draw_curved_ribbon(
                tone, ascale, cx, cy,
                ang_a, ang_b,
                r_a, r_b,
                0.78 if lt < 0.45 else 0.55,
                tone_outer=4 if (is_bright and lt < 0.62) else 3,
                tone_inner=2 if lt < 0.58 else 1,
                alpha=0.92 if lt < 0.55 else 0.66,
                peak_u=0.65,
            )

        # ---- 9. FLYING DETACHED SHEAR SLIVERS ----
        for u0, r_bias, drift_u, drift_r, born_f, life_f, slen, swid, bright in slivers:
            if t < born_f or t > born_f + life_f:
                continue
            lt = (t - born_f) / life_f
            u_cur = u0 + drift_u * (1.0 - (1.0 - lt) ** 1.7)
            if u_cur > head_u + 0.08:
                continue
            ang_c = (a_start + u_cur * total_span) * sweep_sign
            r_cur = base_r + r_expand * 0.72 + r_bias * max_thick * 0.65 + drift_r * (lt ** 0.85)
            px = cx + math.cos(ang_c) * r_cur
            py = cy + math.sin(ang_c) * r_cur
            tang = ang_c + sweep_sign * (math.pi * 0.5) - sweep_sign * 0.16 * lt
            cur_len = slen * (1.0 - 0.62 * lt)
            cur_wid = swid * (1.0 - 0.45 * lt)
            t_c = (5 if lt < 0.35 else 4) if bright else (3 if lt < 0.45 else 2)
            t_e = 3 if bright else 1
            _draw_sliver_cluster(
                tone, ascale, px, py, tang, cur_len, cur_wid,
                t_core=t_c, t_edge=t_e,
                alpha=0.96 if lt < 0.65 else 0.70,
                dark_accent=(lt < 0.58 and not bright),
            )

        # ---- 10. SELECTIVE DEEP-INDIGO CONTRAST EDGE ----
        if t < 0.66:
            _add_selective_shadow_rim(tone, ascale, strength=0.88 * (1.0 - t * 0.72))

        # ---- 11. CRISP 4-POINT PIXEL STAR GLINTS ----
        for u0, r_off, born_f, peak_f, end_f, max_arm, drift_r, drift_u in stars:
            if not (born_f <= t <= end_f):
                continue
            k = (t - born_f) / max(peak_f - born_f, 0.01) if t <= peak_f else 1.0 - (t - peak_f) / max(end_f - peak_f, 0.01)
            arm = int(round(max_arm * k))
            lt = (t - born_f) / max(end_f - born_f, 0.01)
            u_cur = u0 + drift_u * lt
            ang_c = (a_start + u_cur * total_span) * sweep_sign
            r_cur = base_r + r_expand * 0.75 + r_off + drift_r * lt
            sx = cx + math.cos(ang_c) * r_cur
            sy = cy + math.sin(ang_c) * r_cur
            _draw_star_glint(tone, ascale, sx, sy, arm=arm, core_tone=5, wing_tone=4 if k > 0.42 else 3, alpha=1.0 if k > 0.32 else 0.76)

        rgba = _tone_to_rgba(tone, ascale)
        sheet.paste(Image.fromarray(rgba, mode="RGBA"), (fi * size, 0))

    return sheet


# ==============================================================================
# THRUST LANCE & SUPERSONIC SHOCK-CHEVRON GENERATOR v2 (Combo Step 2)
# ==============================================================================
def render_thrust_sheet() -> Image.Image:
    """10 crisp frames (96x64, pivot (16, 32)) of a blazing forward sword thrust:
    - Frame 0 immediately lashes out a blazing needle spear-flash (instant visual snap!)
    - Peak frames 1-3 unleash a razor piercing lance + sweeping twin Mach-chevron wings
      + crisp oblique sonic shock-ring around the mid-shaft
    - Frames 4-9 tear along horizontal streamlines into flying needle shards & star glints
    """
    frames = 10
    w, h = 96, 64
    px0, py0 = 16.0, 32.0
    sheet = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    dx = xs + 0.5 - px0
    dy = ys + 0.5 - py0
    ady = np.abs(dy)

    rng = np.random.default_rng(7703)
    slivers = []
    for si in range(16):
        x0 = rng.uniform(12.0, 62.0)
        side = -1.0 if si % 2 == 0 else 1.0
        y0 = side * rng.uniform(2.0, 14.5)
        vx = rng.uniform(12.0, 26.0)
        vy = side * rng.uniform(1.8, 6.5)
        born = rng.uniform(0.12, 0.46)
        life = rng.uniform(0.28, 0.48)
        slen = rng.uniform(3.2, 8.2)
        slivers.append((x0, y0, vx, vy, born, life, slen, si % 3 != 0))

    stars = []
    for ki in range(8):
        x0 = rng.uniform(22.0, 74.0)
        y0 = rng.uniform(-12.0, 12.0)
        born = rng.uniform(0.30, 0.68)
        peak = born + 0.11
        end = min(0.99, peak + rng.uniform(0.14, 0.24))
        arm = int(rng.choice([1, 2, 2]))
        stars.append((x0, y0, born, peak, end, arm))

    for fi in range(frames):
        t = fi / float(frames - 1)
        tone = np.zeros((h, w), dtype=np.int32)
        ascale = np.zeros((h, w), dtype=np.float64)

        # Frame 0 ALREADY shoots out to dx=50px as a razor flash, peaking at dx=74px!
        if t < 0.18:
            p = t / 0.18
            tip_x = 50.0 + 22.0 * (1.0 - (1.0 - p) ** 2.4)
        else:
            tip_x = 72.0 + 7.5 * ((t - 0.18) / 0.82) ** 0.72

        tail_x = 0.0 + 40.0 * (max(0.0, (t - 0.16) / 0.84) ** 1.18)
        length = max(tip_x - tail_x, 10.0)
        u = (dx - tail_x) / length

        # 1. Razor Piercing Lance + Swept-Back Twin Mach-Chevron Wings
        if t < 0.72:
            thick_t = (0.64 + 0.36 * min(1.0, t / 0.14)) if t < 0.30 else max(0.0, 1.0 - (t - 0.30) / 0.42)
            u_c = clamp01(u)
            # Sleek supersonic lance spearhead: long sharp needle tip!
            half_w = (9.2 * thick_t) * (u_c ** 0.65) * ((1.0 - u_c) ** 0.92) / 0.33
            half_w = np.where((u > 0.02) & (u < 0.995), np.maximum(half_w, 1.05 * thick_t), half_w)

            # Sweeping curved supersonic chevron wings peeling back from tip_x - 4 down to tip_x - 36!
            wing_span = 34.0
            wu = np.clip((dx - (tip_x - wing_span)) / wing_span, 0.0, 1.0)
            wing_outer = (16.5 * thick_t) * ((1.0 - wu) ** 0.82) * smoothstep(0.0, 0.18, wu)
            wing_thick = 4.6 * thick_t * np.sin(math.pi * (wu ** 0.75))
            wing_inner = np.maximum(wing_outer - wing_thick, half_w * 0.55)

            in_lance = (u >= 0.0) & (u <= 1.0) & (ady <= half_w) & (half_w >= 0.55)
            in_wings = (dx >= tip_x - wing_span) & (dx <= tip_x - 2.0) & (ady <= wing_outer) & (ady >= wing_inner) & (wing_thick >= 0.8)

            fn = fbm_stream((dx - t * 44.0) * 0.045, dy * 0.20, 7717)
            erode_t = max(0.0, (t - 0.24) / 0.46)
            if erode_t > 0.0:
                center_protect = 0.44 * np.exp(-((ady / max(1.8, 4.2 * thick_t)) ** 2)) + 0.18 * u_c
                in_lance = in_lance & (fn > erode_t * 1.18 - center_protect)
                in_wings = in_wings & (fn > erode_t * 0.98)

            v_core = clamp01(1.0 - ady / np.maximum(half_w, 0.8))
            val = 0.56 * v_core + 0.28 * u_c + (fn - 0.5) * 0.26 + 0.16 * max(0.0, 1.0 - t / 0.22)
            ltone = np.where(val >= 0.82, 5, np.where(val >= 0.62, 4, np.where(val >= 0.42, 3, np.where(val >= 0.23, 2, 1))))
            needle = (ady <= 1.2) & (u_c > 0.16) & (t < 0.54)
            ltone = np.where(needle, 5, ltone)

            v_wing = clamp01((ady - wing_inner) / np.maximum(wing_outer - wing_inner, 0.6))
            w_val = 0.46 * v_wing + 0.40 * wu + (fn - 0.5) * 0.24
            wtone = np.where(w_val >= 0.78, 5, np.where(w_val >= 0.58, 4, np.where(w_val >= 0.36, 3, np.where(w_val >= 0.20, 2, 1))))

            mask_any = in_lance | in_wings
            combined = np.where(in_lance, ltone, np.where(in_wings, wtone, 0))
            tone = np.where(mask_any, combined, tone)
            ascale = np.where(mask_any, 1.0 if t < 0.46 else 0.82, ascale)

        # 2. Expanding Sonic Shock-Collar Ring (frames 0..5)
        if 0.04 <= t <= 0.62:
            rt = (t - 0.04) / 0.58
            ring_x = px0 + 22.0 + 18.0 * rt
            rx = 3.6 + 4.4 * rt
            ry = 8.5 + 12.5 * (1.0 - (1.0 - rt) ** 2.1)
            steps = 50
            for i in range(steps):
                a = i / steps * math.tau
                if rt > 0.36 and ((i + fi) % 5 in (0, 1)):
                    continue
                px_r = int(round(ring_x + math.cos(a) * rx))
                py_r = int(round(py0 + math.sin(a) * ry))
                front = math.cos(a) > 0.0
                t_r = (5 if rt < 0.30 else 4) if front else (3 if rt < 0.46 else 2)
                _put_px(tone, ascale, px_r, py_r, t_r, 0.94 if rt < 0.54 else 0.68)
                if rt < 0.32 and front:
                    _put_px(tone, ascale, px_r + 1, py_r, 4, 0.85)

        # 3. Trailing Horizontal Wind-Shear Filaments (frames 3..8)
        if 0.26 <= t <= 0.88:
            ft = (t - 0.26) / 0.62
            for lane_i, lane_y in enumerate((-12.0, -6.0, 0.0, 6.0, 12.0)):
                if abs(lane_y) > 8.5 and ft > 0.72:
                    continue
                x_s = px0 + 12.0 + 28.0 * ft + (lane_i * 7) % 13
                x_e = x_s + (18.0 - 12.0 * ft) * (1.2 if lane_y == 0.0 else 0.78)
                y_l = py0 + lane_y * (1.0 + 0.30 * ft)
                for xi in range(int(x_s), int(x_e)):
                    lu = (xi - x_s) / max(x_e - x_s, 1.0)
                    t_f = 5 if (lu > 0.75 and lane_y == 0.0 and ft < 0.42) else (4 if (lu > 0.55 and ft < 0.60) else (3 if lu > 0.30 else 2))
                    _put_px(tone, ascale, xi, int(round(y_l)), t_f, 0.88 if ft < 0.55 else 0.65)

        # 4. Flying Horizontal Needle Slivers
        for x0, y0, vx, vy, born, life, slen, bright in slivers:
            if not (born <= t <= born + life):
                continue
            lt = (t - born) / life
            sx = px0 + x0 + vx * lt
            sy = py0 + y0 + vy * lt
            ang = math.atan2(vy, vx)
            _draw_sliver_cluster(
                tone, ascale, sx, sy, ang,
                slen * (1.0 - 0.55 * lt), 1.15 * (1.0 - 0.4 * lt),
                t_core=5 if (bright and lt < 0.38) else (4 if bright else 3),
                t_edge=3 if bright else 2,
                alpha=0.96 if lt < 0.64 else 0.70,
                dark_accent=(not bright and lt < 0.52),
            )

        if t < 0.58:
            _add_selective_shadow_rim(tone, ascale, strength=0.78 * (1.0 - t))

        # 5. Crisp 4-Point Star Glints along thrust wake
        for x0, y0, born, peak, end, max_arm in stars:
            if not (born <= t <= end):
                continue
            k = (t - born) / max(peak - born, 0.01) if t <= peak else 1.0 - (t - peak) / max(end - peak, 0.01)
            lt = (t - born) / max(end - born, 0.01)
            _draw_star_glint(tone, ascale, px0 + x0 + 7.0 * lt, py0 + y0, int(round(max_arm * k)), 5, 4 if k > 0.42 else 3, 1.0 if k > 0.32 else 0.74)

        rgba = _tone_to_rgba(tone, ascale)
        sheet.paste(Image.fromarray(rgba, mode="RGBA"), (fi * w, 0))

    return sheet


# ==============================================================================
# ALL 6 SWORD SLASH SPECIFICATIONS
# ==============================================================================
SLASH_SPECS = [
    {
        "name": "sword_slash_forehand",
        "kind": "arc",
        "frames": 10,
        "size": 96,
        "radius": 34.5,
        "thick": 15.0,
        "arc_start_deg": -115.0,
        "arc_end_deg": 82.0,
        "sweep_sign": -1,
        "wisps": 4,
        "outer_filaments": 2,
        "shards": 8,
        "slivers": 16,
        "stars": 7,
        "seed": 4101,
    },
    {
        "name": "sword_slash_backhand",
        "kind": "arc",
        "frames": 10,
        "size": 96,
        "radius": 35.5,
        "thick": 15.5,
        "arc_start_deg": -118.0,
        "arc_end_deg": 86.0,
        "sweep_sign": 1,
        "wisps": 5,
        "outer_filaments": 2,
        "shards": 9,
        "slivers": 18,
        "stars": 8,
        "seed": 5207,
    },
    {
        "name": "sword_slash_thrust",
        "kind": "thrust",
    },
    {
        "name": "sword_slash_uppercut",
        "kind": "arc",
        "frames": 10,
        "size": 104,
        "radius": 38.5,
        "thick": 18.0,
        "arc_start_deg": -130.0,
        "arc_end_deg": 94.0,
        "sweep_sign": 1,
        "wisps": 5,
        "outer_filaments": 3,
        "shards": 10,
        "slivers": 20,
        "stars": 9,
        "seed": 6313,
    },
    {
        "name": "sword_slash_whirlwind",
        "kind": "arc",
        "frames": 12,
        "size": 112,
        "radius": 41.0,
        "thick": 17.5,
        "arc_start_deg": -175.0,
        "arc_end_deg": 168.0,
        "sweep_sign": -1,
        "whirlwind": True,
        "wisps": 7,
        "outer_filaments": 3,
        "shards": 13,
        "slivers": 26,
        "stars": 12,
        "seed": 7419,
    },
    {
        "name": "sword_slash_heavy",
        "kind": "arc",
        "frames": 12,
        "size": 112,
        "radius": 42.0,
        "thick": 21.5,
        "arc_start_deg": -122.0,
        "arc_end_deg": 98.0,
        "sweep_sign": -1,
        "heavy": True,
        "wisps": 6,
        "outer_filaments": 3,
        "shards": 12,
        "slivers": 24,
        "stars": 11,
        "seed": 8527,
    },
]


def build_all() -> dict:
    out_dir = ROOT / "fx"
    out_dir.mkdir(parents=True, exist_ok=True)
    built = {}
    for spec in SLASH_SPECS:
        name = spec["name"]
        img = render_thrust_sheet() if spec["kind"] == "thrust" else render_arc_sheet(spec)
        path = out_dir / f"{name}.png"
        img.save(path)
        built[name] = (img, spec)
        print(f"wrote {path.relative_to(ROOT.parent)}  ({img.width}x{img.height})")
    return built


def make_contact_sheet(built: dict, out_path: str) -> None:
    """2x nearest-neighbor visual QA contact sheet on dark twilight + daylight meadow."""
    cols = 10
    cell_w, cell_h = 112, 112
    scale = 2
    rows = len(SLASH_SPECS)
    pad = 6
    W = (cols * cell_w + (cols + 1) * pad) * scale
    block_h = (rows * cell_h + (rows + 1) * pad) * scale
    canvas = Image.new("RGBA", (W, block_h * 2 + 16), (26, 22, 46, 255))

    bgs = [(32, 28, 56, 255), (62, 118, 82, 255)]
    for bi, bg in enumerate(bgs):
        y_base = bi * (block_h + 16)
        panel = Image.new("RGBA", (W, block_h), bg)
        canvas.paste(panel, (0, y_base))
        for ri, spec in enumerate(SLASH_SPECS):
            img, _ = built[spec["name"]]
            n_frames = 10 if spec["kind"] == "thrust" else spec["frames"]
            fw = img.width // n_frames
            fh = img.height
            for ci in range(cols):
                fi = min(n_frames - 1, int(round(ci * (n_frames - 1) / (cols - 1))))
                frame_im = img.crop((fi * fw, 0, (fi + 1) * fw, fh))
                up = frame_im.resize((fw * scale, fh * scale), Image.NEAREST)
                cx_dst = (pad + ci * (cell_w + pad) + (cell_w - fw) // 2) * scale
                cy_dst = y_base + (pad + ri * (cell_h + pad) + (cell_h - fh) // 2) * scale
                canvas.alpha_composite(up, (cx_dst, cy_dst))

    pathlib.Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    print(f"wrote contact sheet: {out_path}  ({canvas.width}x{canvas.height})")


if __name__ == "__main__":
    built = build_all()
    if len(sys.argv) >= 3 and sys.argv[1] == "preview":
        make_contact_sheet(built, sys.argv[2])
