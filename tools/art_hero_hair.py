#!/usr/bin/env python3
"""Ellie's custom hairstyles for the modular customization pipeline (`res://data/hero_cosmetics.json`).

Provides 5 distinct 3D ellipsoid hairstyles with tailored, physically grounded secondary motion:
  1. `blade_bob`   ("Klingenbob")      — Asymmetrical chin/collarbone A-line bob, tucked left ear + crossed gold pins, snappy feather physics.
  2. `storm_tail`  ("Sturmschweif")    — High swordfighter ponytail in a leather-and-gold cuff, 2x-stride bounce + S-curve whip.
  3. `moon_knot`   ("Sternenschleier") — SPECIAL: Half-up twisted crown knot with golden crescent + night-luminous turquoise prism crystal
                                         and woven prism dewdrops along a scalloped V-veil.
  4. `dusk_braids` ("Dämmerflechten")  — Twin true-3D interlocking braids with gold crimp-rings, independent pendulum sway & lively tassels.
  5. `night_bun`   ("Nachtkrone")      — Coiled multi-loop chignon updo, diagonal gold/turquoise bodkin pin + dangling bead, spiral cheek lock.

Preview usage:
  py -3 tools/art_hero_hair.py preview <out_dir>
"""
import math
import sys
from pathlib import Path

import numpy as np

STYLE_IDS = ("blade_bob", "storm_tail", "moon_knot", "dusk_braids", "night_bun")


# ------------------------------------------------------------------ tailored cap clip masks
def _clip_bob(q: np.ndarray) -> np.ndarray:
    """Asymmetrical side-parted bob cap: higher & tucked over left ear (+x), sweeping lower across right brow (-x)."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    top_y = 0.30 + 0.20 * x - 0.24 * (x * x)
    face = (z > 0.18 + 0.08 * y) & (y < top_y)
    # Expose left ear (+x) cleanly so tucked silhouette and earrings read crisply
    ear_cut = (x > 0.62) & (z > -0.18) & (z < 0.55) & (y < 0.02)
    return (y > -0.26) & ~face & ~ear_cut


def _clip_tail(q: np.ndarray) -> np.ndarray:
    """Sleek pulled-back crown cap: clean brow line, open ears & cheeks, neat high nape."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    top_y = 0.32 - 0.30 * (x * x)
    face = (z > 0.16 + 0.07 * y) & (y < top_y)
    ears = (np.abs(x) > 0.68) & (z > -0.12) & (z < 0.52) & (y < -0.02)
    return (y > -0.28) & ~face & ~ears


def _clip_moon(q: np.ndarray) -> np.ndarray:
    """Soft center-parted mystical cap: symmetric arched brow opening, graceful temple coverage."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    top_y = 0.33 - 0.34 * (x * x)
    face = (z > 0.18 + 0.08 * y) & (y < top_y)
    return (y > -0.32) & ~face


def _clip_braids(q: np.ndarray) -> np.ndarray:
    """Warm center-parted cap gathered softly behind both ears into low twin braid roots."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    top_y = 0.30 - 0.32 * (x * x)
    face = (z > 0.19 + 0.08 * y) & (y < top_y)
    ears = (np.abs(x) > 0.72) & (z > -0.05) & (z < 0.48) & (y < -0.06)
    return (y > -0.30) & ~face & ~ears


def _clip_bun(q: np.ndarray) -> np.ndarray:
    """Swept updo cap: high clean nape (z < 0 stops higher so neck shines!), open ears, poised side-swept brow."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    top_y = 0.29 + 0.16 * x - 0.26 * (x * x)
    face = (z > 0.17 + 0.08 * y) & (y < top_y)
    ears = (np.abs(x) > 0.66) & (z > -0.14) & (z < 0.54) & (y < 0.0)
    nape_up = -0.24 + 0.12 * np.clip(-z, 0.0, 1.0)  # lifts nape cleanly in back views
    return (y > nape_up) & ~face & ~ears


# ------------------------------------------------------------------ shared pose/standby motion helpers
def _pose_hair_displacement(pose: dict, l: float, i: int, amp_scale: float = 1.0, droop_scale: float = 1.0) -> np.ndarray:
    """Handles explicit `pose` keyframes (attacks, combos, swim, sit, faint, climb) with style-appropriate mass scaling."""
    hx, hy, hz = pose["hair"]
    ph = i * 0.9
    pc, ps = math.cos(pose.get("pitch", 0.0)), math.sin(pose.get("pitch", 0.0))
    spread, curl = float(pose.get("spread", 0.0)), float(pose.get("curl", 0.0))
    side = (((i * 0.618 + 0.3) % 1.0) - 0.5) * 2.0
    var = 1.0 + 0.45 * spread * ((((i * 0.381966) + 0.13) % 1.0) - 0.5) * 2.0
    droop = float(pose.get("droop", 0.0)) * droop_scale * var * (l ** 1.2)
    bend = curl * amp_scale * math.sin(5.0 * l + ph * 1.3) * l
    return np.array([
        (hx * amp_scale) * (l ** 1.25) + 0.30 * amp_scale * l * math.sin(ph + 2.0 * l) + spread * amp_scale * side * 2.4 * (l ** 1.1) + 0.7 * bend,
        (hy * amp_scale) * l - droop * pc + bend * ps * 1.5,
        (hz * amp_scale) * (l ** 1.25) + droop * ps + bend * pc * 1.5,
    ])


def _apply_standby_add(vec: np.ndarray, pose, l: float, scale: float = 1.0) -> np.ndarray:
    if pose and pose.get("standby"):
        hx, hy, hz = pose["hair"]
        return vec + np.array([hx * scale * (l ** 1.25), hy * scale * l, hz * scale * (l ** 1.25)])
    return vec


# ------------------------------------------------------------------ 1. BLADE BOB ("Klingenbob")
def _build_blade_bob(m, h_mod, ctx: dict) -> None:
    hc, head_R = ctx["hc"], ctx["head_R"]
    H, HL, HH = ctx["H"], ctx["HL"], ctx["HH"]
    w, sw, free, walking, running, sprint, jog, sneak, crouch, pose = (
        ctx["w"], ctx["sw"], ctx["free"], ctx["walking"], ctx["running"],
        ctx["sprint"], ctx["jog"], ctx["sneak"], ctx["crouch"], ctx["pose"],
    )
    HAIR, GOLD = h_mod.HAIR, h_mod.GOLD

    cap_c = hc + head_R @ np.array([0.0, 0.44, -0.24])
    m.ell(cap_c, (4.20, 4.65, 4.22), HAIR, kind="hair", tag=2.0, clip=_clip_bob, R=head_R)

    def bob_off(l: float, i: int, side_scale: float = 1.0) -> np.ndarray:
        """Snappy, agile low-mass feather physics: brisk flicks, minimal sag, crisp settle."""
        ph = i * 0.85
        if pose and not pose.get("standby"):
            return _pose_hair_displacement(pose, l, i, amp_scale=0.40, droop_scale=0.32)
        if running:
            lag = w - 0.9 * l + ph * 0.20
            x = 0.65 * (l ** 1.15) * math.sin(lag + 0.4) * side_scale
            z = -(1.15 + 0.65 * math.sin(lag - 0.7)) * (l ** 1.15)
            y = (0.45 + 0.55 * math.sin(lag - 1.3)) * (l ** 1.1)
            if sprint:
                run = 2 * w - 2.1 * l + ph * 0.45
                fan = math.sin(ph * 1.6 + 0.4)
                amp = 0.68 if jog else 1.0
                x = amp * (0.75 * math.sin(run + 0.4) + 0.45 * fan) * (l ** 1.15) * side_scale
                z = -amp * (2.55 + 0.65 * math.sin(run - 0.7) + 0.40 * fan) * (l ** 1.1)
                y = amp * (1.85 * l + (1.05 * math.sin(run) + 0.55 * fan) * (l ** 1.2))
        elif walking:
            lag = w - 1.0 * l + ph * 0.22
            x = 0.48 * (l ** 1.15) * math.sin(lag + 0.35) * side_scale
            if free:
                x += 0.16 * (l ** 1.2) * (math.sin(w - 1.1 - 0.6 * l) - sw)
            z = -(0.55 + 0.38 * math.sin(lag - 0.7)) * (l ** 1.15)
            y = (0.15 + 0.34 * math.sin(lag - 1.4)) * (l ** 1.1)
            if sneak:
                z -= 0.45 * (l ** 1.15)
            elif free and not crouch:
                y += 0.32 * math.sin(2 * w - 1.8 * l + ph * 0.5) * (l ** 1.15)
        else:
            x = 0.38 * (l ** 1.15) * math.sin(w + ph - 1.1 * l) * side_scale
            z = 0.24 * l * math.sin(w + ph * 0.5 - 0.8 * l)
            y = 0.18 * l * math.sin(2 * w - 0.8 * l)
        return _apply_standby_add(np.array([x, y, z]), pose, l, scale=0.45)

    # Signature swept right-side A-line blade lock (longer, framing her right cheek/jaw down to collarbone y ~ 38.6)
    pts_r_main = []
    for k_i, l in enumerate(np.linspace(0.0, 1.0, 6)):
        bx = 0.45 - 4.30 * (l ** 0.78) + 0.35 * (l ** 2.0)
        by = 49.95 - 11.35 * l
        bz = 2.05 + 1.95 * math.sin(math.pi * min(l * 0.90, 1.0)) - 0.45 * (l ** 1.6)
        p = H((bx, by, bz)) if l < 0.35 else HL((bx, by, bz), (l - 0.35) * 0.55)
        pts_r_main.append(HH(p + bob_off(l, 1, 1.0)))
    m.ribbon(pts_r_main, [1.18, 1.34, 1.24, 1.02, 0.66, 0.24], 0.70, HAIR, (-0.35, 0, 1), tag=1.0)

    # Secondary feathered right cheek/jaw lock just behind the blade lock (clears right shoulder puff cleanly)
    pts_r_sub = []
    for l in np.linspace(0.0, 1.0, 5):
        bx = -2.35 - 1.75 * (l ** 0.82) + 0.35 * (l ** 1.8)
        by = 48.2 - 7.9 * l
        bz = 2.45 - 0.85 * l
        p = HL((bx, by, bz), l * 0.45)
        pts_r_sub.append(HH(p + bob_off(l, 2, 0.9)))
    m.ribbon(pts_r_sub, [0.98, 1.10, 0.96, 0.62, 0.22], 0.64, HAIR, (-1, 0, 0.5), tag=2.4)

    # Left temple sweep neatly tucked back over the ear toward the crossed gold pins
    m.ribbon([
        H((0.65, 49.85, 2.00)),
        H((2.35, 48.65, 2.95)),
        H((3.62, 46.95, 1.45)),
        H((3.92, 45.45, -0.35)) + bob_off(0.25, 3) * 0.35,
    ], [0.92, 1.00, 0.78, 0.38], 0.58, HAIR, (0.6, 0, 1), tag=3.7)

    # Short tucked post-ear side lock on her left (+x), sitting cleanly behind the ear so earrings shine
    pts_l_post = []
    for l in np.linspace(0.0, 1.0, 5):
        bx = 3.82 + 0.32 * math.sin(math.pi * l) - 0.30 * (l ** 1.5)
        by = 46.3 - 5.6 * l
        bz = -0.65 - 0.85 * l + 0.35 * (l ** 1.6)
        pts_l_post.append(HH(HL((bx, by, bz), l * 0.40) + bob_off(l, 4, 0.85)))
    m.ribbon(pts_l_post, [0.88, 0.98, 0.84, 0.52, 0.18], 0.58, HAIR, (1, 0, -0.4), tag=4.9)

    # Stacked A-line feathered nape plumes (shorter & higher in back center, angled longer toward her right side)
    nape_specs = [
        (-3.35, 39.8, -1.25),
        (-2.30, 40.6, -2.30),
        (-1.12, 41.4, -2.95),
        (0.05,  41.8, -3.10),
        (1.20,  41.7, -2.95),
        (2.30,  41.4, -2.35),
        (3.20,  41.1, -1.45),
    ]
    for idx, (nx, y_end, nz_base) in enumerate(nape_specs):
        pts = []
        for l in np.linspace(0.0, 1.0, 6):
            sx = nx * (0.88 + 0.24 * math.sin(math.pi * 0.75 * l))
            sy = 47.6 - (47.6 - y_end) * l
            sz = nz_base - 0.85 * math.sin(math.pi * min(l * 1.05, 1.0)) - 0.35 * (l ** 2.2)
            p = HL((sx, sy, sz), l * 0.45)
            pts.append(HH(p + bob_off(l, 6 + idx, 0.95)))
        m.ribbon(pts, [1.18, 1.32, 1.24, 1.02, 0.64, 0.22], 0.76, HAIR, (0, 0, -1), tag=6.0 + idx * 1.4)

    # Ornament: two crisp crossed gold hairpins snugly anchored above her tucked left ear
    m.ell(H((3.42, 47.40, 1.85)), (0.36, 0.72, 0.36), GOLD, kind="emit", R=head_R @ h_mod.rot_x(0.45))
    m.ell(H((3.52, 47.02, 1.42)), (0.36, 0.72, 0.36), GOLD, kind="emit", R=head_R @ h_mod.rot_x(-0.55))


# ------------------------------------------------------------------ 2. STORM TAIL ("Sturmschweif")
def _build_storm_tail(m, h_mod, ctx: dict) -> None:
    hc, head_R = ctx["hc"], ctx["head_R"]
    H, HL, HH = ctx["H"], ctx["HL"], ctx["HH"]
    w, sw, free, walking, running, sprint, jog, sneak, crouch, pose = (
        ctx["w"], ctx["sw"], ctx["free"], ctx["walking"], ctx["running"],
        ctx["sprint"], ctx["jog"], ctx["sneak"], ctx["crouch"], ctx["pose"],
    )
    HAIR, GOLD, LEATHER = h_mod.HAIR, h_mod.GOLD, h_mod.LEATHER

    cap_c = hc + head_R @ np.array([0.0, 0.46, -0.26])
    m.ell(cap_c, (4.18, 4.66, 4.22), HAIR, kind="hair", tag=2.5, clip=_clip_tail, R=head_R)

    # Subtle crown gather ridges pulling upward toward the high cuff
    for sx in (-1.6, 0.0, 1.6):
        m.ribbon([
            H((sx * 1.15, 49.4, 0.6)),
            H((sx * 0.85, 49.9, -1.4)),
            H((sx * 0.42, 48.7, -3.15)),
        ], [0.85, 0.92, 0.72], 0.55, HAIR, (0, 1, -0.5), tag=1.2 + sx)

    def tail_off(l: float, i: int, side_scale: float = 1.0) -> np.ndarray:
        """Free-pivoting high ponytail physics: energetic 2x-stride bounce + wide S-curve whip!"""
        ph = i * 0.65
        if pose and not pose.get("standby"):
            # Extra lateral whip on sword cuts since the tail hangs free in the air!
            d = _pose_hair_displacement(pose, l, i, amp_scale=1.18, droop_scale=0.95)
            d[0] *= 1.18
            return d
        if running:
            lag = w - 1.55 * l + ph * 0.18
            bounce = 2 * w - 2.3 * l + ph * 0.25
            x = 2.15 * (l ** 1.18) * math.sin(lag + 0.45) * side_scale
            z = -(3.4 + 1.8 * math.sin(bounce - 0.6)) * (l ** 1.12)
            y = (2.2 + 2.1 * math.sin(bounce - 0.9)) * (l ** 1.15)
            if sprint:
                run = 2 * w - 2.9 * l + ph * 0.35
                fan = math.sin(ph * 1.5 + 0.3)
                if jog:
                    x = (1.85 * math.sin(lag + 0.5) + 0.65 * fan) * (l ** 1.18) * side_scale
                    z = -(4.8 + 1.25 * math.sin(run - 0.7) + 0.55 * fan) * (l ** 1.08)
                    y = 5.8 * (l ** 1.05) - 2.0 * (l ** 2.3) + (2.6 * math.sin(run) + 0.9 * fan) * (l ** 1.22)
                else:
                    x = (2.35 * math.sin(lag + 0.5) + 0.85 * fan) * (l ** 1.18) * side_scale
                    z = -(7.2 + 1.65 * math.sin(run - 0.7) + 0.75 * fan) * (l ** 1.06)
                    y = 10.4 * (l ** 1.02) - 3.6 * (l ** 2.4) + (3.8 * math.sin(run) + 1.4 * fan) * (l ** 1.25)
        elif walking:
            lag = w - 1.45 * l + ph * 0.20
            bounce = 2 * w - 2.1 * l + ph * 0.25
            x = 1.65 * (l ** 1.18) * math.sin(lag + 0.4) * side_scale
            if free:
                x += 0.42 * (l ** 1.25) * (math.sin(w - 1.2 - 0.8 * l) - sw)
            z = -(1.55 + 0.95 * math.sin(bounce - 0.7)) * (l ** 1.15)
            y = (0.75 + 1.45 * math.sin(bounce - 1.1)) * (l ** 1.12)
            if sneak:
                z -= (1.2 + 0.45 * math.sin(bounce)) * (l ** 1.15)
                y += 0.85 * (l ** 1.15)
        else:
            x = 1.25 * (l ** 1.2) * math.sin(w + ph * 0.7 - 1.5 * l) * side_scale
            z = 0.75 * (l ** 1.1) * math.sin(w + ph * 0.4 - 1.0 * l)
            y = 0.62 * (l ** 1.1) * math.sin(2 * w - 1.1 * l)
        return _apply_standby_add(np.array([x, y, z]), pose, l, scale=1.10)

    # Charming parted front curtain wisps + delicate cheek tendrils so Ellie stays unmistakably Ellie from the front
    for side in (-1, 1):
        m.ribbon([
            H((side * 0.35, 49.88, 2.18)),
            H((side * 1.75, 48.32, 3.68)),
            H((side * 2.98, 46.12, 3.12)),
            H((side * 3.55, 43.55, 2.02)) + tail_off(0.18, 2 + side) * 0.16,
        ], [0.92, 1.04, 0.80, 0.30], 0.58, HAIR, (0, 0, 1), tag=2.5 + side)
        # Fine wispy sideburn lock ahead of the ear
        m.ribbon([
            H((side * 3.60, 46.2, 1.28)),
            H((side * 3.80, 43.1, 1.18)) + tail_off(0.16, 5 + side) * 0.14,
            H((side * 3.58, 40.2, 0.90)) + tail_off(0.30, 5 + side) * 0.22,
        ], [0.62, 0.56, 0.22], 0.48, HAIR, (side, 0, 0.6), tag=4.2 + side)

    # Sculpted leather-and-gold cuff high on the back of the crown (max y safely <= 50.8)
    cuff_R = head_R @ h_mod.rot_x(-0.42)
    m.ell(H((0.0, 48.35, -3.28)), (1.52, 0.96, 1.44), LEATHER, R=cuff_R)
    m.ell(H((0.0, 48.75, -3.05)), (1.62, 0.38, 1.54), GOLD, kind="emit", R=cuff_R)
    m.ell(H((0.0, 47.95, -3.52)), (1.56, 0.36, 1.48), GOLD, kind="emit", R=cuff_R)

    # High arched ponytail: springs out & up from the cuff (creating a crisp air-gap behind the neck AND plush crown peek in front!),
    # then cascades down to mid-back / upper hip (y ~ 24.8) cleanly outside the skirt bell.
    plumes = [
        (0.0,   24.8, 0.0,   [1.45, 1.78, 1.90, 1.70, 1.38, 1.00, 0.60, 0.24], 0.98),
        (-1.05, 26.2, -0.25, [1.12, 1.38, 1.44, 1.26, 0.98, 0.66, 0.35, 0.14], 0.80),
        (1.05,  26.2, -0.25, [1.12, 1.38, 1.44, 1.26, 0.98, 0.66, 0.35, 0.14], 0.80),
        (-1.68, 28.6, 0.10,  [0.84, 1.04, 1.04, 0.86, 0.60, 0.32, 0.12], 0.64),
        (1.68,  28.6, 0.10,  [0.84, 1.04, 1.04, 0.86, 0.60, 0.32, 0.12], 0.64),
    ]
    for idx, (px, y_end, z_bias, widths, thick) in enumerate(plumes):
        n_pts = len(widths)
        pts = []
        for l in np.linspace(0.0, 1.0, n_pts):
            # Fountain arc at root (lifts ~1.55 units around l=0.14, max y ~ 50.1) then graceful outward S-cascade
            arch_lift = 4.6 * l * math.exp(-3.2 * l)
            sx = px * (0.42 + 1.12 * (l ** 0.82)) + 0.26 * math.sin(3.2 * l + idx) * l
            sy = 48.35 + arch_lift - (48.35 - y_end) * (l ** 1.12)
            # Stays cleanly behind neck AND behind upper skirt (-5.8..-6.8) so tips never dip into the pleated skirt!
            sz = -3.48 - 2.65 * math.sin(math.pi * min(l * 0.56, 0.54)) - (1.05 - z_bias * 0.5) * (l ** 1.15)
            sz -= min(max((31.5 - sy) / 7.5, 0.0), 1.0) * 0.95
            base = H((sx, sy, sz)) if l < 0.16 else HL((sx, sy, sz), (l - 0.16) * 0.88)
            pts.append(HH(base + tail_off(l, idx, 1.0 + 0.12 * abs(px))))
        m.ribbon(pts, widths, thick, HAIR, (0, 0, -1), tag=idx * 1.9)


# ------------------------------------------------------------------ 3. MOON KNOT ("Sternenschleier" — SPECIAL!)
def _build_moon_knot(m, h_mod, ctx: dict) -> None:
    """SHOWSTOPPER SPECIAL HAIRSTYLE ("Sternenschleier"):
    - Front & 3/4: Delicate Starlight Circlet (central turquoise star-gem + golden temple wings) nestled into parted bangs
      + twin collarbone silk locks tipped with luminous turquoise star-prism beads.
    - Back & Profile: Twisted temple ropes meeting in a sculpted half-up crown knot crowned by an Upturned Golden Crescent Moon
      cradling a glowing Turquoise Prism-Crystal (`TEAL` + `GOLD`, preserved across all dyes & bioluminescent at night!).
    - Silhouette & Motion: Splits below the crescent into a tapered Central Cathedral Veil flanked by two gracefully arched
      Winged Astral Ribbon-Trails with negative-space slits and a constellation of woven starlight prism drops."""
    hc, head_R = ctx["hc"], ctx["head_R"]
    H, HL, HH = ctx["H"], ctx["HL"], ctx["HH"]
    w, sw, mi, free, walking, running, sprint, jog, sneak, crouch, pose = (
        ctx["w"], ctx["sw"], ctx["mi"], ctx["free"], ctx["walking"], ctx["running"],
        ctx["sprint"], ctx["jog"], ctx["sneak"], ctx["crouch"], ctx["pose"],
    )
    HAIR, GOLD, TEAL = h_mod.HAIR, h_mod.GOLD, h_mod.TEAL

    cap_c = hc + head_R @ np.array([0.0, 0.44, -0.26])
    m.ell(cap_c, (4.22, 4.68, 4.25), HAIR, kind="hair", tag=3.0, clip=_clip_moon, R=head_R)

    def veil_off(l: float, i: int, side_scale: float = 1.0) -> np.ndarray:
        """Ethereal, silk-ribbon wave physics: graceful long-wavelength billow and wide magical fan-out."""
        ph = i * 0.85
        if pose and not pose.get("standby"):
            return _pose_hair_displacement(pose, l, i, amp_scale=1.10, droop_scale=1.0)
        if running:
            lag = w - 1.70 * l + ph * 0.28
            x = 1.95 * (l ** 1.18) * math.sin(lag + 0.5) * side_scale
            z = -(3.35 + 2.10 * math.sin(lag - 0.8)) * (l ** 1.22)
            y = (1.20 + 1.50 * math.sin(lag - 1.45)) * (l ** 1.15)
            if sprint:
                run = 2 * w - 3.35 * l + ph * 0.52
                fan = math.sin(ph * 1.65 + 0.55)
                if jog:
                    x = (1.60 * math.sin(run + 0.5) + 1.20 * fan) * (l ** 1.18) * side_scale
                    z = -(5.95 + 1.20 * math.sin(run - 0.8) + 0.85 * fan) * (l ** 1.08)
                    y = 6.9 * (l ** 1.08) - 2.5 * (l ** 2.5) + (2.40 * math.sin(run) + 1.50 * fan) * (l ** 1.28)
                else:
                    x = (1.85 * math.sin(run + 0.5) + 1.45 * fan) * (l ** 1.18) * side_scale
                    z = -(8.75 + 1.60 * math.sin(run - 0.8) + 1.10 * fan) * (l ** 1.08)
                    y = 12.5 * (l ** 1.08) - 4.4 * (l ** 2.5) + (3.85 * math.sin(run) + 2.55 * fan) * (l ** 1.28)
        elif walking:
            lag = w - 1.75 * l + ph * 0.28
            x = 1.45 * (l ** 1.2) * math.sin(lag + 0.42) * side_scale
            if free:
                x += 0.40 * (l ** 1.28) * (math.sin(w - 1.35 - 0.85 * l) - sw)
            z = -(1.60 + 1.12 * math.sin(lag - 0.82)) * (l ** 1.22)
            y = (0.38 + 0.92 * math.sin(lag - 1.5)) * (l ** 1.15)
            if sneak:
                z -= (1.15 + 0.42 * math.sin(2 * w - 2.1 * l + ph * 0.6)) * (l ** 1.2)
                y += 0.55 * (l ** 1.2)
            if free and not crouch:
                z -= (1.40 + 0.98 * math.sin(2 * w - 2.5 * l + ph * 0.6)) * (l ** 1.2)
                y += (1.02 + 0.88 * math.sin(2 * w - 2.5 * l + ph * 0.6 - 0.7)) * (l ** 1.2)
        else:
            # Gentle living breeze even in quiet idle!
            x = 1.38 * (l ** 1.18) * math.sin(w + ph - 1.80 * l) * side_scale
            z = 0.85 * l * math.sin(w + ph * 0.5 - 1.1 * l)
            y = 0.52 * l * math.sin(2 * w - 1.1 * l)
        return _apply_standby_add(np.array([x, y, z]), pose, l, scale=1.06)

    # Airy center-parted temple bangs + Front Starlight Circlet!
    m.ell(H((0.0, 49.05, 3.62)), (0.52, 0.58, 0.48), TEAL, kind="emit", R=head_R)
    for side in (-1, 1):
        m.ell(H((side * 0.95, 49.18, 3.45)), (0.58, 0.32, 0.42), GOLD, kind="emit", R=head_R @ h_mod.rot_y(-side * 0.25))
        m.ell(H((side * 2.15, 48.72, 2.95)), (0.48, 0.30, 0.40), GOLD, kind="emit", R=head_R @ h_mod.rot_y(-side * 0.55))

        m.ribbon([
            H((side * 0.32, 49.95, 2.15)),
            H((side * 1.62, 48.35, 3.72)),
            H((side * 2.90, 46.35, 3.22)),
            H((side * 3.68, 44.55, 2.05)) + veil_off(0.16, 1 + side) * 0.15,
        ], [0.95, 1.06, 0.84, 0.34], 0.58, HAIR, (0, 0, 1), tag=1.5 + side)

        # Slender silk collarbone tendrils in front, adorned with a luminous prism star-drop!
        pts_front = []
        bead_pt = None
        for idx_f, l in enumerate(np.linspace(0.0, 1.0, 7)):
            lx = side * (3.80 - 0.55 * (l ** 1.1))
            ly = 46.6 - 12.0 * l
            lz = 1.15 + 1.85 * math.sin(math.pi * min(l * 0.72, 0.88))
            pt = HH(HL((lx, ly, lz), l) + veil_off(l, 4 + side) * 0.36)
            pts_front.append(pt)
            if idx_f == 4:
                bead_pt = pt
        m.ribbon(pts_front, [0.78, 0.86, 0.80, 0.70, 0.56, 0.38, 0.16], 0.54, HAIR, (0, 0, 1), tag=6.0 + side)
        if bead_pt is not None:
            m.ell(bead_pt + np.array([0.0, 0.42, 0.26]), (0.48, 0.34, 0.44), GOLD, kind="emit")
            m.ell(bead_pt + np.array([0.0, -0.08, 0.30]), (0.54, 0.62, 0.50), TEAL, kind="emit")

        # Twisted half-up temple rope sweeping from above the ear around the skull into the back-crown knot!
        n_twist = 7
        for k_t in range(n_twist):
            u = k_t / (n_twist - 1)
            ang = 0.28 - u * 1.72
            rx = side * 4.20 * math.cos(ang) * (1.0 - 0.12 * u)
            ry = 47.65 - 0.80 * math.sin(math.pi * u * 0.75) + 0.24 * ((-1) ** k_t)
            rz = 4.20 * math.sin(ang) - 0.32
            twist_R = head_R @ h_mod.rot_y(side * ang) @ h_mod.rot_x(0.42 * ((-1) ** k_t))
            m.ell(H((rx, ry, rz)), (0.74, 0.90, 0.78), HAIR, kind="hair", tag=2.0 + k_t * 0.7, R=twist_R)

    # Coiled half-up knot at the back-crown
    m.ell(H((-0.70, 47.25, -3.72)), (1.18, 1.28, 1.00), HAIR, kind="hair", tag=1.0, R=head_R @ h_mod.rot_x(0.3))
    m.ell(H((0.70, 47.25, -3.72)), (1.18, 1.28, 1.00), HAIR, kind="hair", tag=3.0, R=head_R @ h_mod.rot_x(-0.3))
    m.ell(H((0.0, 47.00, -3.95)), (1.50, 1.08, 0.98), HAIR, kind="hair", tag=2.0, R=head_R)

    # GRAND UPTURNED GOLDEN CRESCENT & LUMINOUS TURQUOISE PRISM-STAR CLASP!
    # Sweeping upturned crescent cradle in GOLD + radiant central TEAL star-prism + flanking temple studs
    m.ell(H((0.0, 46.55, -4.35)), (1.55, 0.54, 0.58), GOLD, kind="emit", R=head_R)
    for side in (-1, 1):
        m.ell(H((side * 1.38, 46.98, -4.22)), (0.72, 0.62, 0.54), GOLD, kind="emit", R=head_R @ h_mod.rot_y(side * 0.22))
        m.ell(H((side * 2.05, 47.82, -3.92)), (0.52, 0.88, 0.50), GOLD, kind="emit", R=head_R @ h_mod.rot_y(side * 0.35))
        m.ell(H((side * 2.85, 47.45, -2.85)), (0.46, 0.46, 0.46), GOLD, kind="emit", R=head_R)
    # Central faceted Prism-Star crystal cradled inside the upturned golden crescent!
    m.ell(H((0.0, 47.62, -4.42)), (0.88, 1.12, 0.68), TEAL, kind="emit", R=head_R)
    m.ell(H((0.0, 48.68, -4.25)), (0.42, 0.48, 0.42), GOLD, kind="emit", R=head_R)

    # 1) Central Tapered Cathedral Veil (sleek gothic spire cascading cleanly outside her back bodice & pleated skirt to y = 17.6)
    center_plumes = [
        (-0.85, 20.2, [0.96, 1.14, 1.12, 0.98, 0.78, 0.54, 0.30, 0.12], 0.72),
        (0.0,   17.6, [1.22, 1.44, 1.42, 1.26, 1.04, 0.76, 0.46, 0.18], 0.86),
        (0.85,  20.2, [0.96, 1.14, 1.12, 0.98, 0.78, 0.54, 0.30, 0.12], 0.72),
    ]
    for c_i, (cx, y_end, widths, thick) in enumerate(center_plumes):
        pts = []
        ls = np.linspace(0.0, 1.0, len(widths))
        for l in ls:
            sx = cx * (1.0 - 0.32 * l) + 0.20 * math.sin(3.0 * l + c_i) * l
            sy = 46.2 - (46.2 - y_end) * l
            sz = -3.45 - 1.05 * math.sin(math.pi * min(l * 0.85, 0.90)) - 0.65 * l
            sz -= min(max((33.5 - sy) / 9.5, 0.0), 1.0) * (2.65 + 0.85 * mi)
            pts.append(HH(HL((sx, sy, sz), l) + veil_off(l, 2 + c_i, 0.85)))
        m.ribbon(pts, widths, thick, HAIR, (0, 0, -1), tag=c_i * 1.5)
        if c_i == 1:
            # Central constellation star-drops woven onto the outer veil surface!
            for bl in (0.48, 0.78):
                by_b = 46.2 - (46.2 - y_end) * bl
                bz_b = -3.62 - 1.05 * math.sin(math.pi * min(bl * 0.85, 0.90)) - 0.65 * bl
                bz_b -= min(max((33.5 - by_b) / 9.5, 0.0), 1.0) * (2.65 + 0.85 * mi)
                bpt = HH(HL((0.0, by_b, bz_b), bl) + veil_off(bl, 2 + c_i, 0.85))
                m.ell(bpt + np.array([0.0, 0.46, -0.22]), (0.48, 0.34, 0.48), GOLD, kind="emit")
                m.ell(bpt + np.array([0.0, -0.10, -0.28]), (0.58, 0.68, 0.56), TEAL, kind="emit")

    # 2) Twin Winged Astral Ribbon-Trails!
    # Arch outward behind her shoulders & skirt (creating crisp negative-space slits in back view while framing her
    # cinched waist silhouette from behind in front view, 100% clear of sleeves and skirt pleats!).
    for side in (-1, 1):
        r_idx = 6 if side < 0 else 8
        pts_wing = []
        y_wing_end = 21.8
        n_w = 8
        for l in np.linspace(0.0, 1.0, n_w):
            wx = side * (1.70 + 2.12 * math.sin(math.pi * min(0.10 + 0.72 * l, 0.88)))
            wy = 46.5 - (46.5 - y_wing_end) * (l ** 1.03)
            wz = -3.65 - 0.95 * math.sin(math.pi * min(l * 0.80, 0.88)) - 0.58 * l
            wz -= min(max((33.5 - wy) / 9.5, 0.0), 1.0) * (2.55 + 0.80 * mi)
            base_w = H((wx, wy, wz)) if l < 0.14 else HL((wx, wy, wz), (l - 0.14) * 0.92)
            pts_wing.append(HH(base_w + veil_off(l, r_idx, 1.20)))
        m.ribbon(pts_wing, [0.88, 1.18, 1.24, 1.12, 0.96, 0.74, 0.46, 0.18], 0.70, HAIR, (side * 0.35, 0, -1), tag=8.5 + side * 1.4)

        # Luminous Prism-Drop ornaments woven along each outer Astral Ribbon!
        for bl in (0.64,):
            wx_b = side * (1.70 + 2.12 * math.sin(math.pi * min(0.10 + 0.72 * bl, 0.88)))
            wy_b = 46.5 - (46.5 - y_wing_end) * (bl ** 1.03)
            wz_b = -3.82 - 0.95 * math.sin(math.pi * min(bl * 0.80, 0.88)) - 0.58 * bl
            wz_b -= min(max((33.5 - wy_b) / 9.5, 0.0), 1.0) * (2.55 + 0.80 * mi)
            bpt_w = HH(HL((wx_b, wy_b, wz_b), (bl - 0.14) * 0.92) + veil_off(bl, r_idx, 1.20))
            m.ell(bpt_w + np.array([0.0, 0.46, -0.18]), (0.50, 0.34, 0.50), GOLD, kind="emit")
            m.ell(bpt_w + np.array([0.0, -0.10, -0.22]), (0.58, 0.68, 0.58), TEAL, kind="emit")


# ------------------------------------------------------------------ 4. DUSK BRAIDS ("Dämmerflechten")
def _build_dusk_braids(m, h_mod, ctx: dict) -> None:
    hc, head_R = ctx["hc"], ctx["head_R"]
    H, HL, HH = ctx["H"], ctx["HL"], ctx["HH"]
    w, sw, mi, free, walking, running, sprint, jog, sneak, crouch, pose = (
        ctx["w"], ctx["sw"], ctx["mi"], ctx["free"], ctx["walking"], ctx["running"],
        ctx["sprint"], ctx["jog"], ctx["sneak"], ctx["crouch"], ctx["pose"],
    )
    HAIR, GOLD = h_mod.HAIR, h_mod.GOLD

    cap_c = hc + head_R @ np.array([0.0, 0.44, -0.25])
    m.ell(cap_c, (4.20, 4.66, 4.22), HAIR, kind="hair", tag=2.2, clip=_clip_braids, R=head_R)

    def braid_off(l: float, side: int) -> np.ndarray:
        """Weighted twin-pendulum physics: stiffer braided rope, independent L/R phase lag, extra flick on tassel!"""
        ph = 0.45 * side  # subtle L/R counter-phase so the two braids feel independently alive!
        tassel_boost = 1.0 + 0.35 * max(0.0, (l - 0.80) / 0.20)
        if pose and not pose.get("standby"):
            return _pose_hair_displacement(pose, l, 3 + side, amp_scale=0.82 * tassel_boost, droop_scale=0.88)
        if running:
            lag = w - 1.25 * l + ph
            bounce = 2 * w - 1.9 * l + ph * 0.6
            x = (1.15 * math.sin(lag + 0.4) + 0.35 * side) * (l ** 1.25) * tassel_boost
            z = -(2.55 + 1.35 * math.sin(bounce - 0.7)) * (l ** 1.2)
            y = (0.85 + 1.15 * math.sin(bounce - 1.2)) * (l ** 1.15)
            if sprint:
                run = 2 * w - 2.6 * l + ph * 0.8
                if jog:
                    x = (1.25 * math.sin(lag + 0.45) + 0.55 * side) * (l ** 1.22) * tassel_boost
                    z = -(4.4 + 0.95 * math.sin(run - 0.75)) * (l ** 1.12)
                    y = 4.6 * (l ** 1.1) - 1.6 * (l ** 2.3) + 1.75 * math.sin(run) * (l ** 1.25) * tassel_boost
                else:
                    x = (1.65 * math.sin(lag + 0.45) + 0.85 * side) * (l ** 1.22) * tassel_boost
                    z = -(6.6 + 1.25 * math.sin(run - 0.75)) * (l ** 1.12)
                    y = 8.4 * (l ** 1.1) - 2.8 * (l ** 2.3) + 2.75 * math.sin(run) * (l ** 1.25) * tassel_boost
        elif walking:
            lag = w - 1.30 * l + ph
            bounce = 2 * w - 1.9 * l + ph * 0.5
            x = 1.05 * (l ** 1.25) * math.sin(lag + 0.35) * tassel_boost
            if free:
                x += 0.32 * (l ** 1.3) * (math.sin(w - 1.2 - 0.7 * l) - sw)
            z = -(1.05 + 0.72 * math.sin(bounce - 0.75)) * (l ** 1.2)
            y = (0.25 + 0.68 * math.sin(bounce - 1.3)) * (l ** 1.15)
            if sneak:
                z -= 0.85 * (l ** 1.15)
                x += side * 0.30 * l
        else:
            x = 0.72 * (l ** 1.25) * math.sin(w + ph - 1.3 * l) * tassel_boost
            z = 0.48 * (l ** 1.15) * math.sin(w + ph * 0.6 - 0.9 * l)
            y = 0.32 * (l ** 1.15) * math.sin(2 * w - 0.9 * l)
        return _apply_standby_add(np.array([x, y, z]), pose, l, scale=0.85 * tassel_boost)

    # Soft center-parted bangs + delicate cheek-framing temple wisps
    for side in (-1, 1):
        m.ribbon([
            H((side * 0.30, 49.90, 2.12)),
            H((side * 1.68, 48.20, 3.68)),
            H((side * 2.92, 46.10, 3.08)),
            H((side * 3.55, 44.10, 1.95)) + braid_off(0.14, side) * 0.16,
        ], [0.96, 1.08, 0.82, 0.32], 0.58, HAIR, (0, 0, 1), tag=1.8 + side)
        # Charming front cheek wisp + tiny gold temple ring ahead of the ear so Front/3-quarter views read super expressive
        m.ribbon([
            H((side * 3.58, 46.15, 1.45)),
            H((side * 3.72, 43.35, 1.85)) + braid_off(0.18, side) * 0.18,
            H((side * 3.45, 40.85, 1.95)) + braid_off(0.32, side) * 0.24,
        ], [0.68, 0.62, 0.24], 0.50, HAIR, (side, 0, 0.8), tag=3.2 + side)
        m.ell(H((side * 3.62, 44.65, 1.68)), (0.38, 0.28, 0.38), GOLD, kind="emit", R=head_R)

    # Twin true-3D interlocking braids!
    # Gathered cleanly behind both ears and routed between the shoulder puffs onto her back & outside the skirt bell
    # so zero pixels ever collide with her sleeves or skirt hips in any of the 8 directions!
    for side in (-1, 1):
        # Gather puff behind the ear leading smoothly into the braid root
        m.ell(H((side * 3.42, 45.05, -1.62)), (1.18, 1.34, 1.24), HAIR, kind="hair", tag=2.0 + side, R=head_R)

        def braid_spine(l: float) -> np.ndarray:
            bx = side * (3.35 - 0.82 * math.sin(math.pi * min(l * 0.72, 0.85)) + 0.14 * l)
            by = 44.6 - 19.2 * l
            bz = -2.15 - 2.55 * (l ** 0.52)
            bz -= min(max((33.5 - by) / 8.5, 0.0), 1.0) * (2.35 + 0.75 * mi)
            base = H((bx, by, bz)) if l < 0.12 else HL((bx, by, bz), (l - 0.12) * 0.92)
            return HH(base + braid_off(l, side))

        # 11 interlocking plait nodes from l = 0.04 to 0.82
        n_links = 11
        ls_links = np.linspace(0.04, 0.82, n_links)
        spine_pts = [braid_spine(float(l)) for l in ls_links]
        for k_b, (l_val, sp) in enumerate(zip(ls_links, spine_pts)):
            nxt = spine_pts[min(k_b + 1, n_links - 1)]
            prv = spine_pts[max(k_b - 1, 0)]
            tang = nxt - prv
            t_norm = np.linalg.norm(tang)
            tang = tang / t_norm if t_norm > 1e-6 else np.array([0.0, -1.0, 0.0])
            R_seg = h_mod.frame_from(tang, (0.0, 0.0, -1.0))
            alt = 1.0 if (k_b % 2 == 0) else -1.0
            taper = 1.0 - 0.32 * ((l_val - 0.04) / 0.78)
            lobe_off = R_seg @ np.array([alt * 0.45 * taper, 0.0, -0.08 * alt])
            R_lobe = R_seg @ h_mod.rot_y(alt * 0.35) @ np.array([
                [math.cos(alt * 0.48), -math.sin(alt * 0.48), 0.0],
                [math.sin(alt * 0.48),  math.cos(alt * 0.48), 0.0],
                [0.0, 0.0, 1.0],
            ])
            m.ell(
                sp + lobe_off,
                (1.10 * taper, 1.32 * taper, 0.98 * taper),
                HAIR,
                kind="hair",
                tag=float(k_b * 1.7 + (0.5 if side > 0 else 0.0)),
                R=R_lobe,
            )

        # Gold crimp-ring at l = 0.84
        p_ring = braid_spine(0.84)
        p_ring_next = braid_spine(0.90)
        R_ring = h_mod.frame_from(p_ring_next - p_ring, (0.0, 0.0, -1.0))
        m.ell(p_ring, (0.92, 0.52, 0.92), GOLD, kind="emit", R=R_ring)

        # Lively flared paintbrush tassel below the gold ring (l = 0.85 .. 1.05)
        tassel_pts = [braid_spine(float(l)) for l in (0.85, 0.92, 0.99, 1.06)]
        m.ribbon(tassel_pts, [0.78, 1.02, 0.72, 0.24], 0.68, HAIR, (side * 0.4, 0, -1), tag=9.0 + side)


# ------------------------------------------------------------------ 5. NIGHT BUN ("Nachtkrone")
def _build_night_bun(m, h_mod, ctx: dict) -> None:
    hc, head_R = ctx["hc"], ctx["head_R"]
    H, HL, HH = ctx["H"], ctx["HL"], ctx["HH"]
    w, sw, free, walking, running, sprint, jog, sneak, crouch, pose = (
        ctx["w"], ctx["sw"], ctx["free"], ctx["walking"], ctx["running"],
        ctx["sprint"], ctx["jog"], ctx["sneak"], ctx["crouch"], ctx["pose"],
    )
    HAIR, GOLD, TEAL = h_mod.HAIR, h_mod.GOLD, h_mod.TEAL

    cap_c = hc + head_R @ np.array([0.0, 0.45, -0.24])
    m.ell(cap_c, (4.18, 4.65, 4.22), HAIR, kind="hair", tag=2.8, clip=_clip_bun, R=head_R)

    # Upward-swept nape & side ridges drawing cleanly into the coiled chignon
    for sx in (-1.8, 0.0, 1.8):
        m.ribbon([
            H((sx * 1.15, 44.3, -2.55)),
            H((sx * 0.88, 46.0, -3.45)),
            H((sx * 0.45, 47.6, -3.65)),
        ], [0.85, 0.95, 0.78], 0.56, HAIR, (0, 1, -1), tag=1.5 + sx)

    def bun_inertia() -> np.ndarray:
        """Subtle, firm elastic inertia for the pinned bun itself (never floppy, feels genuinely pinned!)."""
        if pose and not pose.get("standby"):
            hx, hy, hz = pose["hair"]
            return np.array([0.16 * hx, 0.14 * hy - 0.12 * float(pose.get("droop", 0.0)), 0.16 * hz])
        if running:
            bounce = 2 * w - 0.8
            amp = (0.45 if jog else 0.72) if sprint else 0.35
            return np.array([0.22 * amp * math.sin(w - 0.5), amp * 0.48 * math.sin(bounce), -amp * 0.32 * abs(math.cos(w))])
        if walking:
            return np.array([0.14 * math.sin(w - 0.4), 0.24 * math.sin(2 * w - 0.7), -0.12])
        res = np.array([0.06 * math.sin(w - 0.5), 0.08 * math.sin(2 * w - 0.4), 0.0])
        return _apply_standby_add(res, pose, 0.6, scale=0.18)

    def tendril_off(l: float, i: int) -> np.ndarray:
        """Lively, delicate spring physics for the romantic spiral cheek-lock, loose nape wisps & pin bead!"""
        ph = i * 1.1
        if pose and not pose.get("standby"):
            return _pose_hair_displacement(pose, l, i, amp_scale=0.52, droop_scale=0.45)
        if running:
            lag = w - 1.1 * l + ph * 0.3
            run = 2 * w - 2.2 * l + ph * 0.4
            amp = (0.72 if jog else 1.0) if sprint else 0.55
            x = amp * 0.85 * (l ** 1.15) * math.sin(lag + 0.5)
            z = -amp * (1.85 + 0.75 * math.sin(run - 0.7)) * (l ** 1.12)
            y = amp * (1.25 * l + 0.95 * math.sin(run) * (l ** 1.2))
        elif walking:
            lag = w - 1.15 * l + ph * 0.3
            x = 0.58 * (l ** 1.15) * math.sin(lag + 0.4)
            if free:
                x += 0.20 * (l ** 1.2) * (math.sin(w - 1.1 - 0.7 * l) - sw)
            z = -(0.68 + 0.45 * math.sin(2 * w - 1.8 * l)) * (l ** 1.15)
            y = (0.22 + 0.42 * math.sin(2 * w - 1.8 * l - 0.8)) * (l ** 1.15)
        else:
            x = 0.48 * (l ** 1.15) * math.sin(w + ph - 1.3 * l)
            z = 0.32 * l * math.sin(w + ph * 0.5 - 0.9 * l)
            y = 0.24 * l * math.sin(2 * w - 0.9 * l)
        return _apply_standby_add(np.array([x, y, z]), pose, l, scale=0.55)

    # Poised side-swept velvet fringe curving across her right forehead (-x)
    m.ribbon([
        H((0.85, 49.90, 2.05)),
        H((-0.85, 48.25, 3.84)),
        H((-2.35, 46.25, 3.42)),
        H((-3.45, 44.65, 2.05)) + tendril_off(0.25, 1) * 0.25,
    ], [1.05, 1.16, 0.90, 0.36], 0.62, HAIR, (0, 0, 1), tag=1.2)

    # Left temple sweep back into the bun
    m.ribbon([
        H((1.05, 49.80, 2.00)),
        H((2.55, 48.45, 2.88)),
        H((3.72, 46.85, 1.25)),
    ], [0.88, 0.94, 0.42], 0.56, HAIR, (0.5, 0, 1), tag=3.4)

    # Single romantic spiral-curled cheek tendril on her left side (+x), framing her porcelain jawline!
    curl_pts = []
    for l in np.linspace(0.0, 1.0, 7):
        cx = 3.62 + 0.42 * math.sin(2.2 * math.pi * l) - 0.22 * l
        cy = 46.5 - 7.1 * l
        cz = 1.92 + 0.45 * math.cos(2.2 * math.pi * l) - 0.15 * l
        p = H((cx, cy, cz)) if l < 0.3 else HL((cx, cy, cz), (l - 0.3) * 0.5)
        curl_pts.append(HH(p + tendril_off(l, 2)))
    m.ribbon(curl_pts, [0.72, 0.76, 0.68, 0.58, 0.48, 0.34, 0.18], 0.52, HAIR, (1, 0, 0.7), tag=5.1)

    # Two tiny loose nape wisps fluttering delicately beneath the bun so the back view feels soft & alive
    for side in (-1, 1):
        wisp_pts = [
            H((side * 1.15, 44.3, -3.15)),
            HH(HL((side * 1.45, 42.6, -3.35), 0.35) + tendril_off(0.55, 5 + side) * 0.45),
            HH(HL((side * 1.25, 41.1, -3.15), 0.65) + tendril_off(0.95, 5 + side) * 0.65),
        ]
        m.ribbon(wisp_pts, [0.55, 0.48, 0.18], 0.44, HAIR, (0, 0, -1), tag=7.0 + side)

    # Lush multi-looped crown chignon bun (max y ~ 50.1, crisp royal silhouette visible even slightly above crown!)
    b_shift = bun_inertia()
    bun_center = H((0.0, 47.72, -3.52)) + b_shift
    # Gold braided base collar wrapping the root of the chignon
    m.ell(bun_center + head_R @ np.array([0.0, -0.10, 0.55]), (2.32, 2.15, 0.55), GOLD, kind="emit", R=head_R)
    m.ell(bun_center, (2.25, 2.12, 1.75), HAIR, kind="hair", tag=1.0, R=head_R)
    # 4 intertwined torus-swirl coils around the bun so top-left lighting carves real braided loops!
    coils = [
        ((-1.10,  0.80, -0.58), (1.42, 1.12, 1.10),  0.48, 0.5),
        (( 1.10,  0.80, -0.58), (1.42, 1.12, 1.10), -0.48, 2.1),
        ((-1.00, -0.82, -0.52), (1.36, 1.08, 1.06), -0.42, 3.7),
        (( 1.00, -0.82, -0.52), (1.36, 1.08, 1.06),  0.42, 5.2),
    ]
    for (ox, oy, oz), rad, tilt_a, tg in coils:
        R_c = head_R @ np.array([
            [math.cos(tilt_a), -math.sin(tilt_a), 0.0],
            [math.sin(tilt_a),  math.cos(tilt_a), 0.0],
            [0.0, 0.0, 1.0],
        ])
        m.ell(bun_center + head_R @ np.array([ox, oy, oz]), rad, HAIR, kind="hair", tag=tg, R=R_c)

    # Diagonal Gold & Turquoise Kanzashi Bodkin Pin snugly anchored into the bun (zero detached gap!) + swinging gold bead
    pin_p0 = bun_center + head_R @ np.array([1.88, 1.32, -0.22])
    pin_p1 = bun_center + head_R @ np.array([-1.82, -1.28, -0.42])
    m.limb(pin_p0, pin_p1, 0.38, 0.28, GOLD, kind="emit", step=0.42)
    m.ell(pin_p0 + head_R @ np.array([0.15, 0.12, 0.0]), (0.62, 0.62, 0.58), TEAL, kind="emit", R=head_R)
    m.ell(pin_p0 + head_R @ np.array([0.42, 0.32, 0.0]), (0.38, 0.38, 0.38), GOLD, kind="emit", R=head_R)
    drop_pt = pin_p0 + head_R @ np.array([0.32, -0.92, 0.08]) + tendril_off(0.75, 9) * 0.35
    m.ell(drop_pt, (0.40, 0.48, 0.40), GOLD, kind="emit")


# ------------------------------------------------------------------ dispatcher
BUILDERS = {
    "blade_bob": _build_blade_bob,
    "storm_tail": _build_storm_tail,
    "moon_knot": _build_moon_knot,
    "dusk_braids": _build_dusk_braids,
    "night_bun": _build_night_bun,
}


def build_hair(m, hair_id: str, h_mod, ctx: dict) -> bool:
    fn = BUILDERS.get(hair_id)
    if fn is None:
        return False
    m.layer = "hair"
    fn(m, h_mod, ctx)
    return True


# ------------------------------------------------------------------ visual contact-sheet preview
def _render_preview(out_dir: Path) -> None:
    import art_hero3d as hero
    from art_hero_layers_rebuild import write_array

    out_dir.mkdir(parents=True, exist_ok=True)
    all_styles = ("default",) + STYLE_IDS
    bg = np.array([0x24, 0x1E, 0x32, 255], dtype=np.uint8)
    bg_alt = np.array([0x2C, 0x25, 0x3C, 255], dtype=np.uint8)

    def compose_frame(layers: dict, dye_rgb=None) -> np.ndarray:
        body = np.asarray(layers["body"], dtype=np.uint8)
        outfit = np.asarray(layers["outfit"], dtype=np.uint8)
        hf = np.asarray(layers["hair_front"], dtype=np.uint8)
        hb = np.asarray(layers["hair_back"], dtype=np.uint8)

        def dye_arr(arr: np.ndarray) -> np.ndarray:
            if dye_rgb is None:
                return arr
            out = arr.copy()
            f = out[..., :3].astype(np.float32) / 255.0
            a = out[..., 3] > 2
            lum = f[..., 0] * 0.3 + f[..., 1] * 0.59 + f[..., 2] * 0.11
            keep = (lum < 0.055) | (f[..., 0] > f[..., 2] + 0.10) | (f[..., 1] > f[..., 0] + 0.12)
            mask = a & ~keep
            t = np.clip((lum - 0.28) / 0.68, 0.0, 1.0)[..., None]
            tint = np.array(dye_rgb, dtype=np.float32) / 255.0
            dark = tint * 0.38
            light = tint * 0.28 + np.array([1.0, 0.98, 0.95], dtype=np.float32) * 0.72
            dyed = np.clip((dark + (light - dark) * t) * 255.0, 0, 255).astype(np.uint8)
            out[mask, :3] = dyed[mask]
            return out

        hf = dye_arr(hf)
        hb = dye_arr(hb)
        canvas = body.copy()
        # Back hair behind body & over ground shadow (exact shader rule)
        hb_mask = (hb[..., 3] > 2) & ((canvas[..., 3] < 3) | ((canvas[..., 3] < 80) & (canvas[..., :3].sum(-1) < 8)))
        canvas[hb_mask] = hb[hb_mask]
        of_mask = outfit[..., 3] > 2
        canvas[of_mask] = outfit[of_mask]
        hf_mask = hf[..., 3] > 2
        canvas[hf_mask] = hf[hf_mask]
        return canvas

    def upscale(img: np.ndarray, scale: int = 3) -> np.ndarray:
        return np.repeat(np.repeat(img, scale, axis=0), scale, axis=1)

    # Sheet 1: 8 Directions Turnaround (rows = 6 styles, cols = 8 sectors E SE S SW W NW N NE)
    fw, fh = 48, 56
    hero.FW, hero.FH, hero.GROUND_ROW = fw, fh, 51.0
    turnaround = np.zeros((len(all_styles) * fh, 8 * fw, 4), dtype=np.uint8)
    for r_i, st in enumerate(all_styles):
        hero.ACTIVE_HAIR = st
        for s in range(8):
            yaw = math.pi / 2 - s * math.pi / 4
            model = hero.build(0.0, "idle", False, None, outfit_id="default", hair_id=st)
            layers = hero.render_layers(model.transform(yaw, model.bob), shadow=True)
            cell = (bg if (r_i + s) % 2 == 0 else bg_alt)[None, None, :].repeat(fh, 0).repeat(fw, 1)
            comp = compose_frame(layers)
            a = comp[..., 3:4].astype(np.float32) / 255.0
            blended = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
            blended_rgba = np.concatenate([blended, np.full((fh, fw, 1), 255, dtype=np.uint8)], axis=-1)
            turnaround[r_i * fh:(r_i + 1) * fh, s * fw:(s + 1) * fw] = blended_rgba

            # Check top clipping!
            top_opaque = int((np.asarray(layers["hair_front"])[0, :, 3] > 0).sum() + (np.asarray(layers["hair_back"])[0, :, 3] > 0).sum())
            if top_opaque > 0:
                print(f"WARNING: top row clipping on {st} idle sector {s}!")

    write_array(out_dir / "turnaround_3x.png", upscale(turnaround, 3))

    # Sheet 2: Action & Sprint Dynamics + Dye Showcase (rows = 5 new styles, cols = 6 sprint E + 4 attack SE + 3 dyes S/N)
    dyes = [
        (0x3A, 0x30, 0x54),  # obsidian
        (0xF0, 0xC8, 0x78),  # blonde
        (0xC8, 0x54, 0x36),  # copper
    ]
    n_cols = 6 + 3 + 3
    motion_sheet = np.zeros((len(STYLE_IDS) * fh, n_cols * fw, 4), dtype=np.uint8)
    for r_i, st in enumerate(STYLE_IDS):
        hero.ACTIVE_HAIR = st
        col_list = []
        # 6 sprint frames in profile (W = sector 4, facing left) + 3/4 back (NW = sector 5)
        for ph_i in range(6):
            s_sec = 4 if ph_i < 3 else 5
            yaw = math.pi / 2 - s_sec * math.pi / 4
            model = hero.build(ph_i / 6.0, "run", False, None, outfit_id="default", hair_id=st)
            layers = hero.render_layers(model.transform(yaw, model.bob), shadow=True)
            if (np.asarray(layers["hair_front"])[0, :, 3] > 0).any() or (np.asarray(layers["hair_back"])[0, :, 3] > 0).any():
                print(f"WARNING: top row clipping on {st} sprint phase {ph_i}!")
            col_list.append(compose_frame(layers))
        # 3 sword slash keyframes (SE = sector 1)
        for k_idx in (0, 2, 3):
            yaw = math.pi / 2 - 1 * math.pi / 4
            model = hero.build(0.0, "attack", False, hero.ATTACK_POSES[0][k_idx], outfit_id="default", hair_id=st)
            layers = hero.render_layers(model.transform(yaw, model.bob), shadow=True)
            col_list.append(compose_frame(layers))
        # 3 dyed back/3-quarter views (SW = sector 3, NE = sector 7, N = sector 6)
        for d_idx, (sec_d, dye_c) in enumerate(zip((3, 5, 6), dyes)):
            yaw = math.pi / 2 - sec_d * math.pi / 4
            model = hero.build(0.25, "walk", False, None, outfit_id="default", hair_id=st)
            layers = hero.render_layers(model.transform(yaw, model.bob), shadow=True)
            col_list.append(compose_frame(layers, dye_rgb=dye_c))

        for c_i, comp in enumerate(col_list):
            cell = (bg if (r_i + c_i) % 2 == 0 else bg_alt)[None, None, :].repeat(fh, 0).repeat(fw, 1)
            a = comp[..., 3:4].astype(np.float32) / 255.0
            blended = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
            motion_sheet[r_i * fh:(r_i + 1) * fh, c_i * fw:(c_i + 1) * fw] = np.concatenate(
                [blended, np.full((fh, fw, 1), 255, dtype=np.uint8)], axis=-1
            )

    hero.ACTIVE_HAIR = "default"
    write_array(out_dir / "motion_and_dyes_3x.png", upscale(motion_sheet, 3))

    # Sheet 3: Story / Salon Sit, Swim & Standby Gestures (rows = 5 new styles, cols = 6 cells of 72x76)
    import art_hero_sit as sit_mod
    import art_hero_swim as swim_mod
    import art_hero_standby as sb_mod
    cw, ch = 72, 76
    sit_poses = sit_mod.poses()
    pose_sheet = np.zeros((len(STYLE_IDS) * ch, 6 * cw, 4), dtype=np.uint8)
    for r_i, st in enumerate(STYLE_IDS):
        hero.ACTIVE_HAIR = st
        cells_p = []
        # Cols 0..2: Salon / bench sitting in S (sector 2), SE (sector 1), NW (sector 5)
        for sec_s in (2, 1, 5):
            hero.FW, hero.FH, hero.GROUND_ROW = 72, 76, 51.0
            yaw = math.pi / 2 - sec_s * math.pi / 4
            model = hero.build(0.0, "attack", False, sit_poses[sit_mod.DOWN], outfit_id="default", hair_id=st)
            cells_p.append(compose_frame(hero.render_layers(model.transform(yaw, 0.0), shadow=True)))
        # Col 3: Swimming stroke in W (sector 4)
        hero.FW, hero.FH, hero.GROUND_ROW = 64, 72, float(swim_mod.WATER_ROW)
        yaw = math.pi / 2 - 4 * math.pi / 4
        sw_pose = swim_mod.FUNCS["breast"](2)
        model = hero.build(0.0, "attack", False, sw_pose, outfit_id="default", hair_id=st)
        prims_sw = model.transform(yaw, 0.0)
        swim_mod._cut(prims_sw, True)
        sw_comp = compose_frame(hero.render_layers(prims_sw, shadow=False))
        pad_sw = np.zeros((ch, cw, 4), dtype=np.uint8)
        pad_sw[2:74, 4:68] = sw_comp
        cells_p.append(pad_sw)
        # Cols 4..5: Standby hair-flip & stretch gestures (48x56 padded into 72x76)
        for clip_idx, sec_sb in ((1, 2), (0, 6)):
            hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
            yaw = math.pi / 2 - sec_sb * math.pi / 4
            p_sb = dict(hero.timeline_pose(sb_mod.KEYS[clip_idx], 0.45), standby=True)
            model = hero.build(0.0, "idle", False, p_sb, outfit_id="default", hair_id=st)
            sb_comp = compose_frame(hero.render_layers(model.transform(yaw, model.bob), shadow=True))
            pad_sb = np.zeros((ch, cw, 4), dtype=np.uint8)
            pad_sb[10:66, 12:60] = sb_comp
            cells_p.append(pad_sb)

        for c_i, comp in enumerate(cells_p):
            cell = (bg if (r_i + c_i) % 2 == 0 else bg_alt)[None, None, :].repeat(ch, 0).repeat(cw, 1)
            a = comp[..., 3:4].astype(np.float32) / 255.0
            blended = (comp[..., :3].astype(np.float32) * a + cell[..., :3].astype(np.float32) * (1.0 - a)).astype(np.uint8)
            pose_sheet[r_i * ch:(r_i + 1) * ch, c_i * cw:(c_i + 1) * cw] = np.concatenate(
                [blended, np.full((ch, cw, 1), 255, dtype=np.uint8)], axis=-1
            )
    hero.FW, hero.FH, hero.GROUND_ROW = 48, 56, 51.0
    hero.ACTIVE_HAIR = "default"
    write_array(out_dir / "poses_sit_swim_standby_3x.png", upscale(pose_sheet, 3))
    print(f"Wrote hair previews to {out_dir}")


if __name__ == "__main__":
    TOOLS_DIR = Path(__file__).resolve().parent
    sys.path.insert(0, str(TOOLS_DIR))
    if len(sys.argv) >= 3 and sys.argv[1] == "preview":
        _render_preview(Path(sys.argv[2]))
    else:
        print("Usage: py -3 tools/art_hero_hair.py preview <out_dir>")
