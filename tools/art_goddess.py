#!/usr/bin/env python3
"""Complete ground-up 3D-ellipsoid pixel-art redesign of Caelia, the floating interstellar goddess
(docs/caelia_interstellar_konzept.md).

Sculpted visual pillars:
  - Weightless barefoot floating posture in open deep space (NO throne, NO corset, NO stiff spiky halo).
  - 128x144 frames, center anchor (64, 78), ~1.75x Ellie scale (~76 px tall), 8 REAL facings (E..NE).
  - Unified Silky Living Nebula Hair: sculpted flowing moon-silver hair curtain sweeping cleanly behind
    her shoulders and waist, transitioning softly through twilight lavender-indigo into starry cosmos-indigo
    tips dotted with crisp 1px unlit stars; thin delicate side locks frame her serene face cleanly.
  - Classical Flowing Moon-Ivory Veil Gown: asymmetrical left-shoulder silk drape, bare moonlit right
    shoulder with subtle antique-gold Kintsugi light seam, slender golden under-bust cord, continuous
    sculpted flowing skirt with an elegant asymmetric leg slit revealing her weightless bare feet &
    floating golden ankle rings, trailing 3 graceful sheer starlight hem tails below.
  - Wide Iconic Celestial Stole (Hagoromo Astral Ribbon): sweeping midnight-sapphire ribbon arching behind
    her upper back, curling around her forearms, and billowing wide to both sides with bright antique-gold
    borders and glowing turquoise constellation dots.
  - True 3D Z-buffered Floating Astrolabe: two thin tilted golden light rings orbiting serenely around her
    head & shoulders (never flipping edge-on!) with glowing starlight nodes.
  - Clips: float_idle (8f), float_talk (8f), float_bless (12f) -> 28 cols x 8 rows.

Usage:
  py -3 tools/art_goddess.py                          builds full sheets + rig JSON
  py -3 tools/art_goddess.py preview out.png          renders fast 2x preview (8-dir turnaround + clips)
"""
from __future__ import annotations

import json
import math
import multiprocessing as mp
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_art import ROOT  # noqa: E402

FW, FH = 128, 144
SS = 3
PITCH = math.radians(20.0)
COSP, SINP = math.cos(PITCH), math.sin(PITCH)
SCALE = 1.40
ANCHOR_X, ANCHOR_Y = 64.0, 78.0
PELVIS_Y = 26.0

UHAT = np.array([0.0, COSP, -SINP], dtype=np.float64)
WHAT = np.array([0.0, SINP, COSP], dtype=np.float64)
LIGHT = np.array([-0.50, 0.72, 0.48], dtype=np.float64)
LIGHT /= np.linalg.norm(LIGHT)

TAU = 2.0 * math.pi


def hexc(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


# ---------------------------------------------------------------------------
# Shadowspore Material Ramps (4 flat tones dark -> light, cool-violet shadows)
# ---------------------------------------------------------------------------
SKIN = 0          # Luminous pale moonlit porcelain
HAIR_SILV = 1     # Cool moon-silver hair
HAIR_TWIL = 2     # Smooth twilight lavender-indigo bridge between silver & nebula tips
HAIR_NEBULA = 3   # Deep starry cosmos-indigo lower hair tips
PEARL_SILK = 4    # Sculpted moon-ivory flowing veil gown
SILK_SHEER = 5    # Ethereal pale celestial-cyan sheer hem tails
COSMOS_STOLE = 6  # Deep sapphire-indigo floating Hagoromo stole
GOLD = 7          # Antique-to-champagne star-gold trim & cords
TEAL_EMIT = 8     # Unlit luminous turquoise eyes, constellation dots & veil wisps
HALO_EMIT = 9     # Unlit radiant star-gold astrolabe rings, kintsugi seam & ankle rings
STAR_EMIT = 10    # Unlit diamond-white / ice-cyan starlight nodes & nebula hair stars

RAMPS: list[list[tuple[int, int, int]]] = [
    [hexc("c88a96"), hexc("e8b2b4"), hexc("fadcd2"), hexc("fff3ea")],  # 0 SKIN
    [hexc("6c62a6"), hexc("a49ad8"), hexc("dcd6f4"), hexc("faf6fe")],  # 1 HAIR_SILV
    [hexc("322a66"), hexc("524894"), hexc("7c72c2"), hexc("b2aae4")],  # 2 HAIR_TWIL
    [hexc("0e0a26"), hexc("1e184c"), hexc("382e7e"), hexc("5e52b2")],  # 3 HAIR_NEBULA
    [hexc("726c9a"), hexc("aba6d0"), hexc("e0dcf2"), hexc("fbf8f4")],  # 4 PEARL_SILK
    [hexc("3a4d7c"), hexc("6484b4"), hexc("9ec4e8"), hexc("dcf2ff")],  # 5 SILK_SHEER
    [hexc("0e102c"), hexc("1d2254"), hexc("343f86"), hexc("5c6eb8")],  # 6 COSMOS_STOLE
    [hexc("6f5020"), hexc("b48a38"), hexc("e6c468"), hexc("fff0b0")],  # 7 GOLD
    [hexc("268890"), hexc("3cc0c6"), hexc("78f4e6"), hexc("d0fff8")],  # 8 TEAL_EMIT
    [hexc("9c7226"), hexc("dca842"), hexc("f6d674"), hexc("fff5be")],  # 9 HALO_EMIT
    [hexc("54b4cc"), hexc("8ce4f6"), hexc("c8f8ff"), hexc("f6ffff")],  # 10 STAR_EMIT
]
EMIT_MATS = {TEAL_EMIT, HALO_EMIT, STAR_EMIT}

OUTLINE_DARK = (16, 10, 30, 255)
OUTLINE_HAIR = (28, 22, 56, 255)
OUTLINE_GOLD = (46, 32, 42, 255)
OUTLINE_TEAL = (20, 48, 60, 255)
LASH_COL = (28, 16, 52, 255)
LIP_COL = (182, 104, 126, 255)


def mat_outline(mat: int) -> tuple[int, int, int, int]:
    if mat == HALO_EMIT:
        return OUTLINE_GOLD
    if mat in (TEAL_EMIT, STAR_EMIT):
        return OUTLINE_TEAL
    if mat in (HAIR_SILV, HAIR_TWIL, HAIR_NEBULA, SILK_SHEER):
        return OUTLINE_HAIR
    return OUTLINE_DARK


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


def frame_from(axis_y: np.ndarray, hint: tuple[float, float, float] = (0.0, 0.0, 1.0)) -> np.ndarray:
    ty = np.asarray(axis_y, dtype=np.float64)
    ny = float(np.linalg.norm(ty))
    ty = ty / ny if ny > 1e-6 else np.array([0.0, 1.0, 0.0])
    tx = np.cross(ty, np.asarray(hint, dtype=np.float64))
    if float(np.linalg.norm(tx)) < 1e-6:
        tx = np.cross(ty, np.array([1.0, 0.0, 0.0]))
    tx /= float(np.linalg.norm(tx))
    tz = np.cross(tx, ty)
    return np.stack([tx, ty, tz], axis=1)


def ik2(root: np.ndarray, target: np.ndarray, l1: float, l2: float, pole: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    v = target - root
    d = float(np.linalg.norm(v))
    max_d = l1 + l2 - 0.05
    min_d = abs(l1 - l2) + 0.05
    if d < 1e-5:
        v = np.array([0.0, -1.0, 0.0])
        d = min_d
    dc = max(min_d, min(max_d, d))
    dir_v = v / d
    eff_t = root + dir_v * dc
    cos_a = max(-1.0, min(1.0, (l1 * l1 + dc * dc - l2 * l2) / (2.0 * l1 * dc)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    p = pole - np.dot(pole, dir_v) * dir_v
    pn = float(np.linalg.norm(p))
    if pn < 1e-5:
        p = np.cross(dir_v, np.array([0.0, 1.0, 0.0]))
        pn = float(np.linalg.norm(p))
    p = p / max(pn, 1e-5)
    mid = root + dir_v * (l1 * cos_a) + p * (l1 * sin_a)
    return mid, eff_t


class Prim:
    __slots__ = ("c", "r", "R", "mat", "bias", "emit_band")

    def __init__(self, c, r, R, mat: int, bias: float = 0.0, emit_band: int = -1) -> None:
        self.c = np.asarray(c, dtype=np.float64)
        self.r = np.asarray(r, dtype=np.float64)
        self.R = np.asarray(R, dtype=np.float64)
        self.mat = mat
        self.bias = bias
        self.emit_band = emit_band


class Builder:
    def __init__(self) -> None:
        self.prims: list[Prim] = []
        self.head_c = np.array([0.0, 51.0, 0.4], dtype=np.float64)
        self.head_R = np.eye(3, dtype=np.float64)
        self.hand_l = np.zeros(3)
        self.hand_r = np.zeros(3)

    def ell(self, c, r, mat: int, R=None, bias: float = 0.0, emit_band: int = -1) -> None:
        self.prims.append(Prim(c, r, np.eye(3) if R is None else R, mat, bias, emit_band))

    def limb(self, a: np.ndarray, b: np.ndarray, r0: float, r1: float, mat: int, steps: int = 8) -> None:
        v = b - a
        R = frame_from(v)
        seg_len = float(np.linalg.norm(v)) / max(steps, 1)
        for i in range(steps + 1):
            t = i / max(steps, 1)
            rad = r0 * (1.0 - t) + r1 * t
            p = a * (1.0 - t) + b * t
            self.ell(p, (rad, max(rad * 1.12, seg_len * 0.72), rad), mat, R)

    def ribbon_chain(
        self,
        pts: list[np.ndarray],
        widths: list[float],
        thickness: float,
        mats: list[int],
        subdiv: int = 3,
        hint: tuple[float, float, float] = (0.0, 0.0, 1.0),
        emit_band: int = -1,
    ) -> None:
        n = len(pts) - 1
        if n <= 0:
            return
        for i in range(n):
            p0, p1 = pts[i], pts[i + 1]
            w0, w1 = widths[i], widths[i + 1]
            m0 = mats[min(i, len(mats) - 1)]
            seg = p1 - p0
            seg_len = float(np.linalg.norm(seg))
            if seg_len < 1e-4:
                continue
            R = frame_from(seg, hint)
            for k in range(subdiv):
                t = (k + 0.5) / subdiv
                p = p0 * (1.0 - t) + p1 * t
                w = w0 * (1.0 - t) + w1 * t
                ry = max(seg_len / subdiv * 1.48, thickness * 1.05)
                self.ell(p, (w, ry, thickness), m0, R, emit_band=emit_band)


def _catmull(pts: list[np.ndarray], samples_per_seg: int = 4) -> list[np.ndarray]:
    if len(pts) < 2:
        return pts
    ext = [pts[0]] + pts + [pts[-1]]
    out: list[np.ndarray] = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            q = 0.5 * (
                (2.0 * p1)
                + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
            out.append(q)
    out.append(pts[-1])
    return out


# ---------------------------------------------------------------------------
# Caelia v2 Floating Goddess Model
# ---------------------------------------------------------------------------
def build_caelia(clip: str, f_i: int, n_f: int) -> tuple[Builder, float]:
    u = f_i / max(n_f, 1)
    ph = TAU * u
    sn = math.sin(ph)
    cs = math.cos(ph)

    talk_k = 1.0 if clip == "float_talk" else 0.0
    bless_k = 0.0
    if clip == "float_bless":
        bless_k = math.sin(math.pi * (f_i + 0.5) / n_f) ** 1.15

    float_y = 1.25 * sn + 4.2 * bless_k
    torso_pitch = 0.04 + 0.025 * cs + 0.09 * talk_k - 0.12 * bless_k
    torso_yaw = 0.04 * sn + 0.07 * talk_k * math.sin(ph)
    head_nod = -0.03 * cs + 0.05 * talk_k - 0.18 * bless_k
    head_yaw = 0.05 * sn

    R_torso = rot_y(torso_yaw) @ rot_x(torso_pitch)
    pelvis = np.array([0.0, PELVIS_Y + float_y, 0.0], dtype=np.float64)

    def T(local_p: tuple[float, float, float]) -> np.ndarray:
        return pelvis + R_torso @ np.asarray(local_p, dtype=np.float64)

    b = Builder()

    # ---- 1. Sculpted Slender Torso, Graceful Neck & Unobstructed Luminous Face ----
    b.ell(T((0.0, 0.2, 0.0)), (4.5, 3.2, 3.3), PEARL_SILK, R_torso)
    b.ell(T((0.0, 4.9, 0.05)), (3.25, 3.5, 2.45), PEARL_SILK, R_torso)
    b.ell(T((0.0, 10.2, 0.25)), (4.45, 4.2, 3.15), PEARL_SILK, R_torso)

    # Slender antique-gold waist / under-bust sash cord (flowing Grecian line, NO corset!)
    for k in range(14):
        ang = TAU * k / 14.0
        cp = T((math.cos(ang) * 3.70, 6.8 + 0.35 * math.sin(ang + 0.4), math.sin(ang) * 2.75 + 0.12))
        b.ell(cp, (0.68, 0.48, 0.62), GOLD, R_torso)

    # Asymmetrical left-shoulder silk drape + bare moonlit right shoulder with Kintsugi seam
    sh_l = T((5.1, 14.6, -0.10))
    sh_r = T((-5.1, 14.6, -0.10))
    b.ell(T((0.0, 14.0, 0.15)), (4.65, 2.05, 2.35), SKIN, R_torso)
    b.ell(sh_l, (2.10, 1.75, 1.88), PEARL_SILK, R_torso)
    b.ell(T((2.8, 12.8, 1.55)), (2.45, 1.75, 1.25), PEARL_SILK, R_torso)
    b.ell(T((4.6, 15.0, 0.38)), (0.85, 0.62, 0.82), GOLD, R_torso)
    b.ell(sh_r, (1.85, 1.55, 1.65), SKIN, R_torso)

    # Subtle glowing antique-gold Kintsugi light seam across her bare right shoulder/collarbone
    for idx, kp in enumerate([(-4.5, 15.1, 0.72), (-3.5, 14.5, 1.25), (-2.5, 13.9, 1.52)]):
        b.ell(T(kp), (0.48, 0.36, 0.44), HALO_EMIT, R_torso, emit_band=3 if idx == 1 else 2)

    # Slender graceful neck lifting her head clearly above the shoulders
    neck_base = T((0.0, 15.4, 0.05))
    neck_top = T((0.0, 20.4, 0.25))
    b.limb(neck_base, neck_top, 1.42, 1.30, SKIN, steps=5)

    R_head = R_torso @ rot_y(head_yaw) @ rot_x(head_nod)
    head_c = T((0.0, 24.8, 0.40))
    b.head_c = head_c
    b.head_R = R_head
    b.ell(head_c, (4.45, 5.10, 4.40), SKIN, R_head)
    b.ell(head_c + R_head @ np.array([0.0, -2.75, 0.92]), (2.55, 2.20, 2.85), SKIN, R_head)
    for sgn in (-1.0, 1.0):
        b.ell(head_c + R_head @ np.array([sgn * 4.20, -0.55, -0.15]), (0.72, 1.20, 0.82), SKIN, R_head)

    # Minimalist glowing golden star mark on forehead
    b.ell(head_c + R_head @ np.array([0.0, 2.05, 4.30]), (0.52, 0.72, 0.32), HALO_EMIT, R_head, emit_band=3)

    # ---- 2. Weightless Barefoot Legs & Floating Golden Ankle Rings ----
    hip_l = pelvis + np.array([2.15, -1.6, 0.0])
    hip_r = pelvis + np.array([-2.15, -1.6, 0.0])

    th_l = 0.42 + 0.07 * sn - 0.12 * bless_k
    kn_l = 0.80 + 0.09 * cs - 0.16 * bless_k
    th_r = -0.12 + 0.06 * math.sin(ph + 1.3) - 0.06 * bless_k
    kn_r = 0.26 + 0.08 * math.cos(ph + 1.3) - 0.10 * bless_k

    def leg_chain(hip: np.ndarray, thigh_a: float, knee_bend: float, sgn: float) -> None:
        l_th, l_sh = 11.8, 11.4
        knee = hip + np.array([sgn * 0.65, -math.cos(thigh_a) * l_th, math.sin(thigh_a) * l_th])
        sh_a = thigh_a - knee_bend
        ankle = knee + np.array([sgn * 0.20, -math.cos(sh_a) * l_sh, math.sin(sh_a) * l_sh])
        toe = ankle + np.array([0.0, -3.1, 1.85])
        b.limb(hip, knee, 2.05, 1.48, SKIN, steps=7)
        b.limb(knee, ankle, 1.42, 0.94, SKIN, steps=7)
        b.limb(ankle, toe, 0.88, 0.62, SKIN, steps=3)
        for ri in range(8):
            ra = TAU * ri / 8.0 + ph * 0.5
            rp = ankle + np.array([math.cos(ra) * 1.90, 0.22 * math.sin(ra), math.sin(ra) * 1.90])
            b.ell(rp, (0.38, 0.32, 0.38), HALO_EMIT, emit_band=2)

    leg_chain(hip_l, th_l, kn_l, 1.0)
    leg_chain(hip_r, th_r, kn_r, -1.0)

    # ---- 3. Continuous Sculpted Moon-Ivory Silk Veil Gown (NO squid tentacles!) ----
    # Built as a cohesive flared classical silk bell around hips/thighs/calves with ONE refined front-left slit
    # revealing her floating bare bent knee & ankle ring, plus 3 long graceful sheer trailing hem tails behind!
    n_panels = 18
    for i in range(n_panels):
        ang = TAU * i / n_panels
        # Front-left slit centered around ang = +1.18 rad (+x, +z) so her bent floating bare leg peeks through gracefully
        d_slit = math.atan2(math.sin(ang - 1.20), math.cos(ang - 1.20))
        in_slit = abs(d_slit) < 0.42
        base_r = 4.45
        p0 = pelvis + np.array([math.cos(ang) * base_r * 0.88, 2.2, math.sin(ang) * base_r * 0.78])
        panel_len = 8.5 if in_slit else (23.5 + 3.2 * max(0.0, -math.sin(ang)))
        bloom = 1.0 + 0.32 * bless_k
        pts_p = [p0]
        segs = 5
        for s_i in range(1, segs + 1):
            frac = s_i / segs
            sway = math.sin(ph - frac * 2.4 + ang * 2.0) * (0.9 + 1.4 * frac)
            out_r = base_r + (2.0 + 4.4 * (frac ** 1.15)) * bloom
            px = math.cos(ang) * out_r + sway * (-math.sin(ang)) * 0.45
            pz = math.sin(ang) * (out_r * 0.82) + sway * math.cos(ang) * 0.45 - 1.6 * frac
            py = pelvis[1] + 2.2 - panel_len * frac
            pts_p.append(np.array([px, py, pz]))
        # Generous overlapping panel width forms ONE smooth continuous pleated silk skirt!
        w_base = 2.55 if not in_slit else 1.55
        widths_p = [w_base * (1.0 + 0.25 * (k / segs)) for k in range(segs + 1)]
        mats_p = [PEARL_SILK, PEARL_SILK, PEARL_SILK, PEARL_SILK, SILK_SHEER]
        b.ribbon_chain(pts_p, widths_p, 1.05, mats_p, subdiv=5)
        # Delicate gold trim dots along bottom hem of the main gown
        if not in_slit and i % 2 == 0:
            b.ell(pts_p[-1] + np.array([0.0, 0.6, 0.0]), (0.65, 0.45, 0.65), GOLD)

    # 3 long ethereal trailing sheer silk tails sweeping gently below her bare feet in back/sides
    for t_idx, t_ang in enumerate([-math.pi * 0.50, -math.pi * 0.78, -math.pi * 0.22]):
        p0 = pelvis + np.array([math.cos(t_ang) * 5.8, -16.0, math.sin(t_ang) * 5.0 - 1.2])
        tail_pts = [p0]
        for k in range(1, 5):
            f = k / 4.0
            wave = math.sin(ph - f * 2.8 + t_idx * 1.4) * (2.2 * f)
            tx = p0[0] + math.cos(t_ang) * (4.5 * f * (1.0 + 0.4 * bless_k)) + wave
            ty = p0[1] - (13.5 + 2.0 * (t_idx == 0)) * f
            tz = p0[2] - 3.5 * f + math.cos(ph + t_idx) * f
            tail_pts.append(np.array([tx, ty, tz]))
        b.ribbon_chain(tail_pts, [2.2, 1.7, 1.15, 0.72, 0.35], 0.58, [SILK_SHEER, SILK_SHEER, SILK_SHEER, TEAL_EMIT], subdiv=3)
        b.ell(tail_pts[-1], (0.58, 0.72, 0.52), TEAL_EMIT, emit_band=2)

    # ---- 4. Graceful Floating Arms & Glowing Veil Threads Between Her Hands ----
    if clip == "float_bless":
        t_hl = T((13.2 + 3.4 * bless_k, 13.8 + 5.6 * bless_k + 0.7 * sn, 4.4 + 2.0 * bless_k))
        t_hr = T((-13.2 - 3.4 * bless_k, 13.8 + 5.6 * bless_k - 0.7 * sn, 4.4 + 2.0 * bless_k))
    elif clip == "float_talk":
        t_hl = T((5.2 + 0.6 * sn, 8.8 + 0.7 * cs, 5.4 + 0.6 * sn))
        t_hr = T((-9.2 - 1.2 * cs, 8.6 + 1.1 * sn, 7.8 + 0.9 * cs))
    else:
        t_hl = T((6.4 + 0.8 * sn, 5.8 + 1.0 * cs, 6.2 + 0.7 * sn))
        t_hr = T((-6.4 - 0.8 * cs, 6.0 + 1.0 * sn, 6.4 + 0.7 * cs))

    el_l, h_l = ik2(sh_l, t_hl, 9.6, 9.2, np.array([0.45, -0.82, -0.35]))
    el_r, h_r = ik2(sh_r, t_hr, 9.6, 9.2, np.array([-0.45, -0.82, -0.35]))
    b.hand_l, b.hand_r = h_l, h_r

    b.limb(sh_l, el_l, 1.45, 1.14, SKIN, steps=6)
    b.limb(el_l, h_l, 1.08, 0.82, SKIN, steps=6)
    b.limb(sh_r, el_r, 1.45, 1.14, SKIN, steps=6)
    b.limb(el_r, h_r, 1.08, 0.82, SKIN, steps=6)

    b.ell(h_l, (1.02, 0.85, 1.10), SKIN)
    b.ell(h_r, (1.02, 0.85, 1.10), SKIN)
    b.ell(el_l * 0.20 + h_l * 0.80, (1.12, 0.60, 1.12), GOLD)
    b.ell(el_r * 0.20 + h_r * 0.80, (1.12, 0.60, 1.12), GOLD)

    # Shimmering Veil threads suspended between her floating fingertips
    n_th = 14
    for ti in range(1, n_th):
        ft = ti / n_th
        sag = -2.0 * math.sin(math.pi * ft) + 0.9 * math.sin(ph + ft * TAU)
        tp = h_l * (1.0 - ft) + h_r * ft + np.array([0.0, sag + 2.0 * bless_k * math.sin(math.pi * ft), 1.1 * math.sin(math.pi * ft)])
        mat_t = HALO_EMIT if (ti % 3 == 0) else TEAL_EMIT
        b.ell(tp, (0.42 + 0.15 * bless_k, 0.42 + 0.15 * bless_k, 0.42), mat_t, emit_band=3 if bless_k > 0.35 else 2)
    if bless_k > 0.15:
        mid_h = (h_l + h_r) * 0.5 + np.array([0.0, 2.2 * bless_k, 1.6])
        core_r = 1.6 + 2.3 * bless_k
        b.ell(mid_h, (core_r, core_r, core_r), STAR_EMIT, emit_band=3)
        for ray_i in range(6):
            ra = TAU * ray_i / 6.0 + ph * 0.5
            rp = mid_h + np.array([math.cos(ra) * (core_r + 2.8 * bless_k), math.sin(ra) * (core_r + 2.8 * bless_k), 0.2])
            b.ell(rp, (0.65, 0.65, 0.55), HALO_EMIT, emit_band=3)

    # ---- 5. Wide Iconic Celestial Stole (Hagoromo Midnight-Sapphire Astral Ribbon!) ----
    # Sweeps HIGH behind her shoulders and WIDE out around her forearms so it creates an unmistakable goddess halo silhouette!
    stole_ctrl = [
        np.array([-23.5 - 3.2 * bless_k, pelvis[1] + 2.0 + 3.4 * math.sin(ph + 0.4), -1.5 + 2.2 * cs]),
        np.array([-16.8 - 1.8 * bless_k, pelvis[1] + 9.5 + 1.8 * cs, 3.2]),
        el_r + np.array([-2.6, -1.6 + 1.0 * sn, 1.6]),
        T((-9.2, 18.2 + 1.2 * cs, -4.8 - 1.2 * bless_k)),
        T((0.0, 22.8 + 1.4 * sn + 1.8 * bless_k, -8.8 - 1.4 * bless_k)),
        T((9.2, 18.2 - 1.2 * cs, -4.8 - 1.2 * bless_k)),
        el_l + np.array([2.6, -1.6 - 1.0 * sn, 1.6]),
        np.array([16.8 + 1.8 * bless_k, pelvis[1] + 9.5 - 1.8 * cs, 3.2]),
        np.array([23.5 + 3.2 * bless_k, pelvis[1] + 2.0 - 3.4 * math.sin(ph + 0.4), -1.5 - 2.2 * cs]),
    ]
    stole_pts = _catmull(stole_ctrl, samples_per_seg=4)
    stole_w = [1.1 + 1.8 * math.sin(math.pi * (k / max(len(stole_pts) - 1, 1))) for k in range(len(stole_pts))]
    b.ribbon_chain(stole_pts, stole_w, 0.62, [COSMOS_STOLE], subdiv=2)
    # Bright antique-gold upper rim & luminous turquoise constellation dots along the dark cosmic stole
    for idx in range(2, len(stole_pts) - 2):
        sp = stole_pts[idx]
        if idx % 2 == 0:
            b.ell(sp + np.array([0.0, 0.95, 0.35]), (0.46, 0.40, 0.44), GOLD)
        if idx % 5 == 0:
            b.ell(sp + np.array([0.0, -0.1, 0.65]), (0.55, 0.55, 0.55), STAR_EMIT, emit_band=3)
        elif idx % 5 == 2:
            b.ell(sp + np.array([0.0, 0.0, 0.58]), (0.45, 0.45, 0.45), TEAL_EMIT, emit_band=2)

    # ---- 6. Unified Silky Living Nebula Hair Curtain (Smooth Flowing Cape, NOT spiky tubes!) ----
    # Smooth moon-silver crown cap + high parted forehead fringe leaving her ENTIRE face & eyes crisp and clear
    b.ell(head_c + R_head @ np.array([0.0, 1.15, -0.65]), (4.78, 4.95, 4.78), HAIR_SILV, R_head)
    for sgn in (-1.0, 1.0):
        # Swept parted brow curve (stays high above eyes!) + one slender cheek-framing wisp
        b.ell(head_c + R_head @ np.array([sgn * 2.25, 3.65, 2.75]), (2.15, 1.25, 1.55), HAIR_SILV, R_head)
        wisp = [
            head_c + R_head @ np.array([sgn * 3.85, 2.2, 1.85]),
            head_c + R_head @ np.array([sgn * 4.55, -2.0, 1.25]),
            head_c + R_head @ np.array([sgn * 5.05 + sgn * 0.8 * bless_k, -8.5, 0.25 + 0.6 * sn]),
        ]
        b.ribbon_chain(wisp, [1.05, 0.88, 0.55], 0.72, [HAIR_SILV], subdiv=3)

    # Cohesive silky back-hair curtain (13 closely-overlapping wide silk ribbons strictly behind her ears & shoulders!)
    n_curt = 13
    for i in range(n_curt):
        f_lat = (i / (n_curt - 1)) * 2.0 - 1.0  # -1 (right) .. +1 (left)
        # Span strictly the rear arc (-108 deg .. +108 deg from straight back -Z) so face & shoulders stay 100% clear!
        ang = math.pi + f_lat * math.radians(102.0)
        root = head_c + R_head @ np.array([math.sin(ang) * 4.2, 2.0 - 0.5 * abs(f_lat), math.cos(ang) * 4.0 - 0.3])
        bloom = 1.0 + 0.42 * bless_k
        # Longer in center, softly tapering at outer edges like a real luminous flowing mane
        lock_len = (34.0 - 7.5 * (f_lat * f_lat)) + 1.5 * math.sin(i * 1.3)
        pts_h = [root]
        segs_h = 6
        for k in range(1, segs_h + 1):
            t = k / segs_h
            # Smooth unified S-wave across the whole curtain (shared phase with gentle offset -> silky cloth, not frizz!)
            wave_x = math.sin(ph - t * 2.5 + f_lat * 1.1) * (1.6 + 2.8 * t)
            wave_z = math.cos(ph - t * 2.1 + f_lat * 0.9) * (1.0 + 1.6 * t)
            spread_x = f_lat * (4.2 + 8.8 * (t ** 1.15)) * bloom
            back_z = -3.8 - 7.8 * (t ** 1.10) * bloom + abs(f_lat) * 2.0 * (1.0 - t)
            ly = root[1] - lock_len * (t ** 1.04) * 0.86 + 3.4 * bless_k * (t ** 1.2)
            pts_h.append(np.array([spread_x + wave_x, ly, back_z + wave_z]))

        # Wide overlapping ribbon widths weld adjacent strands into one lush, painterly weightless mane!
        w_edge = 1.0 - 0.25 * abs(f_lat)
        widths_h = [2.1 * w_edge, 2.25 * w_edge, 2.35 * w_edge, 2.20 * w_edge, 1.85 * w_edge, 1.30 * w_edge, 0.55 * w_edge]
        # 3-stage smooth Nebula transition: Moon-Silver -> Twilight Lavender-Indigo -> Starry Deep Cosmos-Indigo!
        mats_h = [HAIR_SILV, HAIR_SILV, HAIR_SILV, HAIR_TWIL, HAIR_NEBULA, HAIR_NEBULA]
        b.ribbon_chain(pts_h, widths_h, 0.98, mats_h, subdiv=5)

        # Tiny crisp unlit nebula stars glittering softly inside the twilight & midnight-indigo lower hair cape
        if i % 2 == 0:
            star_m = STAR_EMIT if (i % 4 == 0) else TEAL_EMIT
            b.ell(pts_h[5] + np.array([0.0, 0.6, -0.55]), (0.50, 0.50, 0.50), star_m, emit_band=3)
            b.ell(pts_h[4] + np.array([0.4 * f_lat, 0.2, 0.65]), (0.45, 0.45, 0.45), star_m, emit_band=3)

    # ---- 7. True 3D Z-Buffered Floating Astrolabe (Gracefully Framed Behind Crown, Never Cutting Face!) ----
    astro_c = head_c + np.array([0.0, 2.2 + 0.8 * bless_k, -3.2])
    align_k = 1.0 - 0.58 * bless_k
    R_ring1 = rot_z(math.radians(20.0 + 3.5 * sn) * align_k) @ rot_x(math.radians(18.0 + 2.5 * cs) * align_k)
    R_ring2 = rot_z(math.radians(-24.0 - 3.5 * cs) * align_k) @ rot_x(math.radians(-16.0 + 2.5 * sn) * align_k)

    def add_astrolabe_ring(radius: float, R_ring: np.ndarray, n_seg: int, spin: float, nodes: int) -> None:
        for k in range(n_seg):
            a0 = TAU * k / n_seg + spin
            p_loc = np.array([math.cos(a0) * radius, math.sin(a0) * radius * 0.94, 0.0])
            p_w = astro_c + R_ring @ p_loc
            b.ell(p_w, (0.55, 0.55, 0.55), HALO_EMIT, emit_band=3 if bless_k > 0.35 else 2)
        for ni in range(nodes):
            na = TAU * ni / nodes + spin * 1.25
            p_loc = np.array([math.cos(na) * radius, math.sin(na) * radius * 0.94, 0.0])
            p_w = astro_c + R_ring @ p_loc
            n_mat = STAR_EMIT if ni % 2 == 0 else TEAL_EMIT
            b.ell(p_w, (1.08, 1.08, 1.08), n_mat, emit_band=3)

    add_astrolabe_ring(16.6 + 1.6 * bless_k, R_ring1, 48, ph * 0.5, 4)
    add_astrolabe_ring(12.6 + 1.2 * bless_k, R_ring2, 40, -ph * 0.5, 3)

    return b, bless_k


# ---------------------------------------------------------------------------
# Fast Vectorized Z-Buffered Ellipsoid Pixel Renderer (SS=3, 1px tinted outline)
# ---------------------------------------------------------------------------
def _project_pt(p_world: np.ndarray) -> tuple[float, float, float]:
    sx = ANCHOR_X + p_world[0] * SCALE
    sy = ANCHOR_Y - (p_world[1] * COSP - p_world[2] * SINP) * SCALE
    sz = p_world[1] * SINP + p_world[2] * COSP
    return sx, sy, sz


def render_frame(clip: str, f_i: int, n_f: int, yaw_rad: float) -> tuple[np.ndarray, np.ndarray]:
    builder, bless_k = build_caelia(clip, f_i, n_f)
    Ry = rot_y(yaw_rad)

    Ws, Hs = FW * SS, FH * SS
    depth = np.full((Hs, Ws), -1e9, dtype=np.float32)
    code = np.full((Hs, Ws), -1, dtype=np.int16)

    cam_ray = WHAT

    for prim in builder.prims:
        c0 = prim.c - np.array([0.0, PELVIS_Y, 0.0])
        c = Ry @ c0
        R = Ry @ prim.R
        r = prim.r

        cx = ANCHOR_X + c[0] * SCALE
        cy = ANCHOR_Y - (c[1] * COSP - c[2] * SINP) * SCALE
        ex = float(np.sqrt(np.sum((R[0, :] * r) ** 2))) * SCALE
        uy_vec = R[1, :] * COSP - R[2, :] * SINP
        ey = float(np.sqrt(np.sum((uy_vec * r) ** 2))) * SCALE

        x0 = max(0, int(math.floor((cx - ex) * SS)) - 1)
        x1 = min(Ws, int(math.ceil((cx + ex) * SS)) + 1)
        y0 = max(0, int(math.floor((cy - ey) * SS)) - 1)
        y1 = min(Hs, int(math.ceil((cy + ey) * SS)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue

        inv_r = 1.0 / np.maximum(r, 1e-4)
        M = R.T * inv_r[:, None]
        d_loc = M @ cam_ray
        A = float(np.dot(d_loc, d_loc))
        if A < 1e-9:
            continue

        xs = ((np.arange(x0, x1, dtype=np.float64) + 0.5) / SS - ANCHOR_X) / SCALE
        ys = (ANCHOR_Y - (np.arange(y0, y1, dtype=np.float64) + 0.5) / SS) / SCALE
        ox = xs[None, :] - c[0]
        oy = ys[:, None] * COSP - c[1]
        oz = -ys[:, None] * SINP - c[2]

        lx = M[0, 0] * ox + M[0, 1] * oy + M[0, 2] * oz
        ly = M[1, 0] * ox + M[1, 1] * oy + M[1, 2] * oz
        lz = M[2, 0] * ox + M[2, 1] * oy + M[2, 2] * oz

        B = lx * d_loc[0] + ly * d_loc[1] + lz * d_loc[2]
        C = lx * lx + ly * ly + lz * lz - 1.0
        disc = B * B - A * C
        hit = disc >= 0.0
        if not np.any(hit):
            continue

        sqrt_d = np.sqrt(np.maximum(disc, 0.0))
        w_hit = (-B + sqrt_d) / A

        d_sub = depth[y0:y1, x0:x1]
        vis = hit & (w_hit > d_sub)
        if not np.any(vis):
            continue

        d_sub[vis] = w_hit[vis].astype(np.float32)

        if prim.emit_band >= 0:
            code[y0:y1, x0:x1][vis] = prim.mat * 4 + prim.emit_band
        else:
            qx = lx[vis] + w_hit[vis] * d_loc[0]
            qy = ly[vis] + w_hit[vis] * d_loc[1]
            qz = lz[vis] + w_hit[vis] * d_loc[2]
            gx, gy, gz = qx * inv_r[0], qy * inv_r[1], qz * inv_r[2]
            nx = R[0, 0] * gx + R[0, 1] * gy + R[0, 2] * gz
            ny = R[1, 0] * gx + R[1, 1] * gy + R[1, 2] * gz
            nz = R[2, 0] * gx + R[2, 1] * gy + R[2, 2] * gz
            nlen = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-8
            ndl = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / nlen + prim.bias
            band = np.where(ndl < -0.10, 0, np.where(ndl < 0.28, 1, np.where(ndl < 0.68, 2, 3)))
            code[y0:y1, x0:x1][vis] = (prim.mat * 4 + band).astype(np.int16)

    csub = code.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    dsub = depth.reshape(FH, SS, FW, SS).transpose(0, 2, 1, 3).reshape(FH, FW, SS * SS)
    opaque = (csub >= 0).sum(axis=-1)
    is_emit_sub = (csub >= TEAL_EMIT * 4)
    emit_cnt = is_emit_sub.sum(axis=-1)
    solid = (opaque >= 4) | (emit_cnt >= 2)

    eff_d = np.where(csub >= 0, dsub + np.where(is_emit_sub, 0.35, 0.0), -1e9)
    best_i = np.argmax(eff_d, axis=-1)
    best_code = np.take_along_axis(csub, best_i[..., None], axis=-1)[..., 0]
    best_code = np.where(solid, best_code, -1)

    canvas = np.zeros((FH, FW, 4), dtype=np.uint8)
    emit_mask = np.zeros((FH, FW), dtype=bool)
    mat_map = np.where(solid, best_code // 4, -1)
    band_map = np.where(solid, best_code % 4, 0)

    ys_s, xs_s = np.nonzero(solid)
    for y, x in zip(ys_s.tolist(), xs_s.tolist()):
        m_i = int(mat_map[y, x])
        b_i = int(band_map[y, x])
        r, g, b_c = RAMPS[m_i][b_i]
        canvas[y, x] = (r, g, b_c, 255)
        if m_i in EMIT_MATS:
            emit_mask[y, x] = True

    _stamp_face(canvas, emit_mask, builder, Ry, bless_k)

    solid_now = canvas[..., 3] > 0
    air = ~solid_now
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nb_solid = np.zeros((FH, FW), dtype=bool)
        nb_mat = np.full((FH, FW), -1, dtype=np.int16)
        sy0, sy1 = max(0, -dy), FH - max(0, dy)
        dy0, dy1 = max(0, dy), FH - max(0, -dy)
        sx0, sx1 = max(0, -dx), FW - max(0, dx)
        dx0, dx1 = max(0, dx), FW - max(0, -dx)
        nb_solid[dy0:dy1, dx0:dx1] = solid_now[sy0:sy1, sx0:sx1]
        nb_mat[dy0:dy1, dx0:dx1] = mat_map[sy0:sy1, sx0:sx1]
        edge = air & nb_solid & (canvas[..., 3] == 0)
        ey, ex = np.nonzero(edge)
        for y, x in zip(ey.tolist(), ex.tolist()):
            canvas[y, x] = mat_outline(int(nb_mat[y, x]))

    glow = np.zeros((FH, FW, 4), dtype=np.uint8)
    glow[emit_mask] = canvas[emit_mask]

    open_air = canvas[..., 3] == 0
    if emit_mask.any():
        aura = np.zeros((FH, FW), dtype=bool)
        aura_col = np.zeros((FH, FW, 3), dtype=np.uint8)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1), (-2, 0), (2, 0), (0, -2), (0, 2)):
            dist = abs(dy) + abs(dx)
            if dist > (3 if bless_k > 0.35 else 2):
                continue
            nb_em = np.zeros((FH, FW), dtype=bool)
            nb_c = np.zeros((FH, FW, 3), dtype=np.uint8)
            sy0, sy1 = max(0, -dy), FH - max(0, dy)
            dy0, dy1 = max(0, dy), FH - max(0, -dy)
            sx0, sx1 = max(0, -dx), FW - max(0, dx)
            dx0, dx1 = max(0, dx), FW - max(0, -dx)
            nb_em[dy0:dy1, dx0:dx1] = emit_mask[sy0:sy1, sx0:sx1]
            nb_c[dy0:dy1, dx0:dx1] = canvas[sy0:sy1, sx0:sx1, :3]
            if dist == 1:
                bayer_ok = ((np.arange(FH)[:, None] + np.arange(FW)[None, :]) % 2 == 0)
            else:
                bayer_ok = ((np.arange(FH)[:, None] % 2 == 0) & (np.arange(FW)[None, :] % 2 == 0))
            hit_a = open_air & nb_em & (~aura) & bayer_ok
            aura |= hit_a
            aura_col[hit_a] = nb_c[hit_a]
        glow[aura, :3] = aura_col[aura]
        glow[aura, 3] = 148 if bless_k > 0.35 else 102

    return canvas, glow


def _stamp_face(
    canvas: np.ndarray,
    emit_mask: np.ndarray,
    builder: Builder,
    Ry: np.ndarray,
    bless_k: float,
) -> None:
    fwd = Ry @ (builder.head_R @ np.array([0.0, 0.0, 1.0]))
    if fwd[2] < 0.05:
        return

    def proj_head(loc: tuple[float, float, float]) -> tuple[int, int]:
        pw = Ry @ (builder.head_c + builder.head_R @ np.asarray(loc, dtype=np.float64) - np.array([0.0, PELVIS_Y, 0.0]))
        sx, sy, _ = _project_pt(pw)
        return int(round(sx)), int(round(sy))

    iris_bright = (*RAMPS[TEAL_EMIT][2], 255)
    iris_core = (*RAMPS[TEAL_EMIT][3], 255)
    iris_deep = (*RAMPS[TEAL_EMIT][0], 255)

    for sgn in (-1.0, 1.0):
        eye_norm = Ry @ (builder.head_R @ np.array([sgn * 0.38, 0.0, 0.92]))
        if eye_norm[2] < 0.16:
            continue
        ex, ey = proj_head((sgn * 1.68, -0.20, 3.92))
        if not (2 <= ex < FW - 2 and 2 <= ey < FH - 2):
            continue
        canvas[ey - 1, ex] = LASH_COL
        if eye_norm[2] > 0.45:
            canvas[ey - 1, ex + (1 if sgn > 0 else -1)] = LASH_COL
        canvas[ey, ex] = iris_core if bless_k > 0.3 else iris_bright
        emit_mask[ey, ex] = True
        canvas[ey + 1, ex] = iris_bright if bless_k > 0.3 else iris_deep
        emit_mask[ey + 1, ex] = True
        if eye_norm[2] > 0.55:
            nx = ex - (1 if sgn > 0 else -1)
            canvas[ey, nx] = iris_core
            emit_mask[ey, nx] = True

    if fwd[2] > 0.35:
        mx, my = proj_head((0.0, -2.45, 3.85))
        if 1 <= mx < FW - 1 and 1 <= my < FH - 1:
            canvas[my, mx] = LIP_COL


# ---------------------------------------------------------------------------
# Sheet Assembly & Multiprocessing Entrypoint (8 True Facings E..NE)
# ---------------------------------------------------------------------------
CLIPS: list[tuple[str, int, int, bool]] = [
    ("float_idle", 8, 6, True),
    ("float_talk", 8, 7, True),
    ("float_bless", 12, 8, False),
]
FACINGS: list[tuple[str, float]] = [
    ("E", math.pi / 2.0),
    ("SE", math.pi / 4.0),
    ("S", 0.0),
    ("SW", -math.pi / 4.0),
    ("W", -math.pi / 2.0),
    ("NW", -3.0 * math.pi / 4.0),
    ("N", math.pi),
    ("NE", 3.0 * math.pi / 4.0),
]


def _worker(job: tuple[int, int, str, int, int, float]) -> tuple[int, int, bytes, bytes]:
    row_i, col_i, clip_name, f_i, n_f, yaw_rad = job
    col_arr, glow_arr = render_frame(clip_name, f_i, n_f, yaw_rad)
    return row_i, col_i, col_arr.tobytes(), glow_arr.tobytes()


def write_sheets() -> None:
    total_cols = sum(cnt for _, cnt, _, _ in CLIPS)
    total_rows = len(FACINGS)
    sheet_c = np.zeros((total_rows * FH, total_cols * FW, 4), dtype=np.uint8)
    sheet_g = np.zeros((total_rows * FH, total_cols * FW, 4), dtype=np.uint8)

    jobs: list[tuple[int, int, str, int, int, float]] = []
    for r_i, (_f_name, yaw_rad) in enumerate(FACINGS):
        col_cursor = 0
        for c_name, cnt, _fps, _loop in CLIPS:
            for f_i in range(cnt):
                jobs.append((r_i, col_cursor + f_i, c_name, f_i, cnt, yaw_rad))
            col_cursor += cnt

    workers = min(8, os.cpu_count() or 1)
    with mp.Pool(workers) as pool:
        for r_i, col_i, cb, gb in pool.imap_unordered(_worker, jobs, chunksize=2):
            y0, y1 = r_i * FH, (r_i + 1) * FH
            x0, x1 = col_i * FW, (col_i + 1) * FW
            sheet_c[y0:y1, x0:x1] = np.frombuffer(cb, dtype=np.uint8).reshape(FH, FW, 4)
            sheet_g[y0:y1, x0:x1] = np.frombuffer(gb, dtype=np.uint8).reshape(FH, FW, 4)

    out_c = ROOT / "characters" / "goddess.png"
    out_g = ROOT / "characters" / "goddess_glow.png"
    Image.fromarray(sheet_c, "RGBA").save(out_c)
    Image.fromarray(sheet_g, "RGBA").save(out_g)

    clips_meta: dict[str, dict[str, int | bool]] = {}
    col_cursor = 0
    for c_name, cnt, fps, loop in CLIPS:
        clips_meta[c_name] = {"start": col_cursor, "count": cnt, "fps": fps, "loop": loop}
        col_cursor += cnt

    rig_data = {
        "texture": "res://assets/characters/goddess.png",
        "glow_texture": "res://assets/characters/goddess_glow.png",
        "frame_size": [FW, FH],
        "feet": [int(ANCHOR_X), int(ANCHOR_Y)],
        "floating_height_px": 76,
        "columns": total_cols,
        "rows": total_rows,
        "default_row": 2,
        "facings": [name for name, _ in FACINGS],
        "row_by_facing": {name: idx for idx, (name, _) in enumerate(FACINGS)},
        "clips": clips_meta,
    }
    rig_path = ROOT.parent / "data" / "goddess_rig.json"
    rig_path.write_text(json.dumps(rig_data, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_c} ({total_cols * FW}x{total_rows * FH}), {out_g}, and {rig_path}")


def write_preview(out_path: str) -> None:
    jobs: list[tuple[int, int, str, int, int, float]] = []
    for s_i, (_name, yaw_rad) in enumerate(FACINGS):
        jobs.append((0, s_i, "float_idle", 0, 8, yaw_rad))
    for k in range(4):
        jobs.append((1, k, "float_talk", k * 2, 8, 0.0 if k < 2 else math.pi / 4.0))
    for k in range(4):
        jobs.append((1, 4 + k, "float_bless", k * 3, 12, 0.0))

    workers = min(8, os.cpu_count() or 1)
    board = np.zeros((2 * FH, 8 * FW, 4), dtype=np.uint8)
    board[..., 0] = 6
    board[..., 1] = 4
    board[..., 2] = 16
    board[..., 3] = 255

    with mp.Pool(workers) as pool:
        for r_i, col_i, cb, gb in pool.imap_unordered(_worker, jobs, chunksize=1):
            c_arr = np.frombuffer(cb, dtype=np.uint8).reshape(FH, FW, 4)
            g_arr = np.frombuffer(gb, dtype=np.uint8).reshape(FH, FW, 4)
            y0, y1 = r_i * FH, (r_i + 1) * FH
            x0, x1 = col_i * FW, (col_i + 1) * FW
            cell = board[y0:y1, x0:x1].astype(np.float32)
            ca = c_arr[..., 3:4].astype(np.float32) / 255.0
            cell[..., :3] = cell[..., :3] * (1.0 - ca) + c_arr[..., :3].astype(np.float32) * ca
            ga = g_arr[..., 3:4].astype(np.float32) / 255.0
            cell[..., :3] = np.clip(cell[..., :3] + g_arr[..., :3].astype(np.float32) * ga * 0.55, 0.0, 255.0)
            board[y0:y1, x0:x1] = cell.astype(np.uint8)

    img = Image.fromarray(board, "RGBA").resize((8 * FW * 2, 2 * FH * 2), Image.Resampling.NEAREST)
    p = Path(out_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p)
    print("Preview written:", p)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "preview":
        write_preview(sys.argv[2])
    else:
        write_sheets()
