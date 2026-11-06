"""The adventurer who saves Ellie at the crossroads: a tall knight of the wine-red order (the dead knight at the log wore the same tabard), dark
plate, a torn cloak, a closed helm with a glowing slit, and a long sword whose edge burns cold violet-white. Built from ellipsoids like Ellie.
    python3 tools/art_adventurer.py [preview.png]      quick contact sheet of the east (0) and south (2) views, writes nothing else
    python3 tools/art_adventurer.py sheet              writes assets/characters/adventurer.png (+ _glow) and data/adventurer_rig.json
    python3 tools/art_adventurer.py portrait           writes assets/ui/portrait_adventurer.png (a backlit bust for the dialogue)
Sheet: 8 rows = sectors (E SE S SW W NW N NE, like the heroine), one column per frame, frames of 84x100, feet at (42, 84)."""
import json
import math
import multiprocessing as mp
import os
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

import art_hero3d as h
from gen_art import CLEAR, ROOT, hexc, write_png

FW1, FH1, GROUND = 84, 100, 84
h.FW, h.FH, h.GROUND_ROW = FW1, FH1, GROUND
h.SCALE = 1.05
BASE = len(h.RAMPS)
STEEL, STEEL_D, CLOTH, CLOTH_D, BLADE, WGLOW, VOIDM, NEWWOOD = range(BASE, BASE + 8)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["1f1d30", "3d3d5a", "6c7090", "aeb4cc"],  # plate
    ["141221", "292840", "474a6a", "787ea0"],  # dark plate
    ["26111d", "4a1d31", "70304a", "985470"],  # the order's wine red
    ["0d0912", "1a1222", "2c2038", "443654"],  # dark lining and fur
    ["3b3f5c", "7e86ad", "c3cae6", "f5f7ff"],  # the blade
    ["7a5cd0", "b9a0ff", "e6dcff", "ffffff"],  # cold glow: visor slit, edge, runes
    ["040208", "0a0612", "170d28", "2c1d4c"],  # void-darkened hems
    ["5a3d34", "8c6048", "c08e66", "e8bc8c"],  # fresh-cut fir
]]
GLOW_MATS = (WGLOW,)
V = lambda *a: np.array(a, float)
rot_x, rot_y = h.rot_x, h.rot_y


def P(lean=0.0, twist=0.0, pz=0.0, feet=((2.8, 2.5, 0.0), (-2.8, -1.0, 0.0)), hand_r=(-6.0, 23.0, 4.0), hand_l=(4.8, 25.0, 1.0),
      sword=(0.45, -0.66, 0.6), cloak=(0.0, 0.0, -2.0), wave=0.0, breath=0.0, head=0.0, tool=None):
    return dict(tool=tool, lean=lean, twist=twist, pz=pz, feet=feet, hand_r=hand_r, hand_l=hand_l, sword=sword, cloak=cloak, wave=wave, breath=breath, head=head)


def build(pose):
    m = h.Model()
    ell, limb, ribbon = m.ell, m.limb, m.ribbon
    legs, drop = h.pose_legs(dict(pose, hair=None))
    off = V(0.0, drop, pose["pz"])
    lean, twist = pose["lean"], pose["twist"]
    tor = rot_x(lean) @ rot_y(twist)
    breath = pose["breath"]

    def T(p):
        base = V(0.0, 27.0, 0.0)
        return base + tor @ (np.array(p, float) - base)

    # legs: cuisses, greaves, knee cops with a gold rim, sabatons
    m.off = np.zeros(3)
    for side, (hip, knee, ankle, _a, _b) in zip((1, -1), legs):
        limb(hip, knee, 2.9, 2.5, STEEL_D)
        limb(hip + (knee - hip) * 0.2, knee, 2.4, 2.2, CLOTH_D)
        limb(knee, ankle, 2.35, 1.7, STEEL)
        ell(knee + V(0, 0.8, 1.2), (3.1, 2.7, 3.0), STEEL)
        ell(knee + V(0, 0.8, 1.2), (3.25, 0.35, 3.0), h.GOLD)
        shin = knee * 0.45 + ankle * 0.55
        ell(shin + V(0, 0.0, 1.8), (0.5, 3.1, 0.45), STEEL_D)
        ell(ankle + V(0, -1.2, 2.0), (2.1, 1.5, 3.8), STEEL_D)
        ell(ankle + V(0, 0.2, -0.4), (2.0, 2.0, 2.0), STEEL_D)
    # hips: belt, faulds, a tabard hanging in front
    m.off = off
    ell(V(0, 24.5, 0), (4.4, 3.5, 3.3), CLOTH_D)
    ell(V(0, 26.6, 0), (4.1, 0.9, 3.6), h.LEATHER)
    ell(V(0, 26.6, 3.3), (1.1, 0.8, 0.5), h.GOLD, kind="emit")
    for th in np.linspace(-1.8, 1.8, 11):
        c = V(5.0 * math.sin(th), 22.4, 4.3 * math.cos(th) + 0.2)
        ell(c, (2.2, 3.2, 0.9), STEEL if abs(th) < 1.2 else STEEL_D, R=rot_y(th) @ rot_x(0.2))
    lag = V(*pose["cloak"])
    ribbon([V(0, 25.5, 4.4), V(0, 19.0, 5.2) + lag * 0.1, V(0.4, 12.0, 4.8) + lag * 0.25, V(0.6, 6.5, 4.0) + lag * 0.45], [3.6, 3.7, 3.3, 2.6, 1.4], 0.5, CLOTH, (0, 0.3, 1.0), tag=2.0, kind="")
    ell(V(0, 16.0, 5.5), (0.65, 0.8, 0.35), h.GOLD)
    # torso: gambeson, breastplate with a ridge, gorget, a heavy mantle
    ell(T((0, 29.8 + breath * 0.05, 0)), (2.9, 3.3, 2.4), CLOTH, R=tor)
    ell(T((0, 34.2 + breath * 0.12, 0)), (3.9, 4.2, 3.0), CLOTH, R=tor)
    ell(T((0, 35.0 + breath * 0.12, 0.9)), (4.7, 5.4, 3.6), STEEL, R=tor)
    ell(T((0, 35.0, 4.2)), (0.55, 4.7, 0.6), STEEL, R=tor)
    # Wine-red surcoat and a small order clasp: readable large shapes instead
    # of speckled highlights, like the existing dialogue portrait.
    ribbon([T((0, 39.0, 3.8)), T((0, 35.6, 4.8)), T((0, 31.0, 4.25))],
           [1.65, 2.0, 1.7], 0.4, CLOTH, (0, 0, 1), kind="")
    ell(T((0, 35.7, 5.35)), (0.6, 0.85, 0.35), h.GOLD, R=tor)
    ell(T((0, 29.4, 0.5)), (3.6, 3.1, 2.8), STEEL_D, R=tor)
    ell(T((0, 30.2, 4.0)), (1.2, 1.2, 0.5), h.GOLD, kind="emit", R=tor)
    ell(T((0, 40.0, 0.2)), (3.4, 1.5, 3.2), STEEL, R=tor)
    ell(T((0, 40.8, -0.4)), (5.6, 1.9, 4.4), CLOTH_D, R=tor)
    # arms: pauldrons (the left one huge, three lames), sleeves, vambraces, gauntlets; the right hand holds the sword
    sh_r, sh_l = T((-4.9, 38.0, 0.0)), T((4.9, 38.0, 0.0))
    for sh, side, big in ((sh_r, -1, 1.0), (sh_l, 1, 1.25)):
        ell(sh + V(side * 0.7, 0.5, 0), (3.5 * big, 2.4 * big, 3.3 * big), STEEL, R=tor)
        ell(sh + V(side * 0.9, -1.4 * big, 0), (3.1 * big, 1.5, 2.9 * big), STEEL_D, R=tor)
        ell(sh + V(side * 0.4, 0.5, 0), (3.6 * big, 0.35, 3.3 * big), h.GOLD, R=tor)
        ell(sh + V(side * 0.95, -2.5 * big, -0.1), (2.8 * big, 0.85, 2.7 * big), STEEL, R=tor)
    ell(sh_l + V(1.2, 3.0, -0.4), (0.8, 1.9, 0.8), STEEL, R=tor)  # a spike on the big pauldron
    pole_r, pole_l = V(-1, -0.6, -0.5), V(1, -0.6, -0.5)
    grip = None
    for sh, hand, pole, side in ((sh_r + off, pose["hand_r"], pole_r, -1), (sh_l + off, pose["hand_l"], pole_l, 1)):
        el, wr = h.ik2(sh, hand, 6.8, 6.2, pole)
        d2 = (wr - el) / np.linalg.norm(wr - el)
        el, wr = el - off, wr - off
        limb(sh - off, el, 1.8, 1.6, CLOTH)
        limb(el, wr, 1.7, 1.45, STEEL)
        ell(el, (2.1, 2.1, 2.1), STEEL)
        ell(wr + d2 * 1.1, (1.7, 1.9, 1.7), STEEL_D)
        for tt in (0.35, 0.65):  # quiet, paired rivets on the vambrace
            ell(el + (wr - el) * tt + V(0, 0.0, 1.25), (0.4, 0.4, 0.4), h.GOLD)
        if side == -1:
            grip = wr + d2 * 1.1
    # a fur collar round the neck, a pouch and a flask on the belt, a fringe of mail under the faulds
    for th in np.linspace(0, 2 * math.pi, 9)[:-1]:
        ell(T((3.9 * math.sin(th), 41.2, 3.4 * math.cos(th) + 0.2)), (1.7, 1.3, 1.7), CLOTH_D, R=tor)
    ribbon([T((-4.7, 40.4, 0.7)), T((-2.1, 38.7, 3.2)), T((2.9, 40.1, 2.3))],
           [1.1, 1.35, 0.9], 0.45, CLOTH, (0, 0, 1), kind="")
    ell(T((3.0, 39.9, 3.05)), (0.85, 0.85, 0.45), h.GOLD, R=tor)
    ell(V(-5.3, 24.0, -1.2), (1.9, 2.4, 1.7), h.LEATHER)
    ell(V(-5.3, 26.0, -1.2), (2.0, 0.8, 1.8), h.LEATHER)
    ell(V(-5.6, 24.4, 0.6), (0.6, 0.6, 0.4), h.GOLD, kind="emit")
    limb(V(2.4, 25.4, -3.9), V(2.4, 21.0, -4.3), 1.5, 1.3, CLOTH_D)
    ell(V(2.4, 19.8, -4.3), (1.2, 1.4, 1.2), h.LEATHER)
    for th in np.linspace(-1.5, 1.5, 9):
        ell(V(5.2 * math.sin(th), 18.6, 4.4 * math.cos(th) + 0.4), (0.9, 1.5, 0.6), STEEL_D, R=rot_y(th))
    # head: closed helm, a glowing slit, a crest of torn plume
    hc = T((0.0, 44.4 + breath * 0.1, 0.4))
    RH = tor @ rot_x(pose["head"])
    ell(hc, (4.9, 5.5, 5.1), STEEL, R=RH)
    ell(hc + RH @ V(0, -3.1, 1.2), (4.3, 2.8, 4.3), STEEL_D, R=RH)
    ell(hc + RH @ V(0, 5.3, 0), (0.8, 0.7, 4.6), STEEL, R=RH)
    ell(hc + RH @ V(0, 0.9, 5.2), (3.7, 0.75, 0.9), VOIDM, R=RH)
    ell(hc + RH @ V(0, 0.9, 6.05), (3.0, 0.48, 0.48), WGLOW, kind="emit", R=RH)
    ell(hc + RH @ V(0, 1.8, 4.85), (3.5, 0.38, 0.65), STEEL, R=RH)
    ell(hc + RH @ V(0, -0.8, 5.1), (0.5, 2.0, 0.7), STEEL, R=RH)
    for side in (-1, 1):
        ell(hc + RH @ V(side * 4.45, -0.1, 1.8), (0.45, 0.6, 0.6), h.GOLD, R=RH)
    plume_lag = lag + V(0.5 * math.sin(pose["wave"] - 0.8), 0.25 * math.cos(pose["wave"] - 0.5), 0.8 * math.sin(pose["wave"] - 1.1))
    ribbon([hc + RH @ V(0, 5.2, -1.2), hc + RH @ V(0, 7.2, -4.0) + plume_lag * 0.15, hc + RH @ V(0.8, 5.5, -8.5) + plume_lag * 0.5, hc + RH @ V(1.4, 2.0, -12.0) + plume_lag * 0.9,
            hc + RH @ V(2.0, -2.0, -14.0) + plume_lag * 1.2], [1.3, 1.7, 1.5, 1.0, 0.3], 0.4, CLOTH, (1, 0, 0), tag=5.0, kind="")
    # the cloak: five ribbons from the mantle, torn hems darkened by the void, streaming with `cloak`
    w = pose["wave"]
    for i, ax in enumerate((-5.2, -2.6, 0.0, 2.6, 5.2)):
        length = (25, 29, 31, 28, 24)[i]
        pts, widths_a = [], []
        for l in np.linspace(0.0, 1.0, 9):
            base = T((ax * (1.0 + 0.25 * l), 39.5 - length * l, -3.2 - 1.8 * l))
            p = base + lag * (l ** 1.4) + V(1.1 * math.sin(w - l * 2.0 + i * 0.7) * l, 0.5 * math.cos(w + i * 0.7 - l) * l, 1.4 * math.sin(w - l * 1.6 + i * 0.45) * l)
            p[1] = max(p[1], 1.3 + 0.4 * i % 2)
            pts.append(p)
        wd = [2.4, 2.8, 3.0, 3.0, 2.8, 2.5, 2.0, 1.4, 0.5]
        split = 7
        ribbon(pts[: split + 1], wd[: split + 1], 0.55, CLOTH if i in (1, 2, 3) else CLOTH_D, (0, 0, 1), tag=i * 1.3, kind="")
        ribbon(pts[split:], wd[split:], 0.5, VOIDM, (0, 0, 1), tag=i * 1.7, kind="")
    if pose.get("tool") in ("pick", "empty", "mug", "hammer", "beam"):  # "empty": nothing in his hands, the sword stays sheathed; "mug": a mug of brew in the right hand
        if pose.get("tool") == "pick":
            pickaxe(m, grip, V(*pose["sword"]))
        if pose.get("tool") == "hammer":  # a mallet in the right hand: an ash haft with a leather grip and a heavy iron head
            d = V(*pose["sword"])
            d = d / np.linalg.norm(d)
            limb(grip - d * 1.5, grip + d * 15.0, 1.1, 1.0, h.LEATHER)
            ell(grip + d * 15.5, (3.2, 3.2, 3.2), STEEL_D)
            a = np.cross(V(1, 0, 0), d)
            a = a / (np.linalg.norm(a) or 1.0)
            ell(grip + d * 15.5 + V(3.0, 0, 0), (2.0, 2.4, 2.4), STEEL)
            ell(grip + d * 15.5 - V(3.0, 0, 0), (1.7, 2.2, 2.2), STEEL)
        if pose.get("tool") == "beam":  # a long fir beam on the shoulder, steadied by both hands
            sh = V(-4.8, 40.0, 0.5)
            limb(sh + V(0, 1.5, -22.0), sh + V(0, 2.0, 13.0), 2.6, 2.6, NEWWOOD)
            ell(sh + V(0, 2.0, 13.4), (2.5, 2.5, 0.6), NEWWOOD)
        if pose.get("tool") == "mug":
            ell(grip + V(0, 2.2, 1.0), (2.1, 2.5, 2.1), h.LEATHER)  # the clay mug
            ell(grip + V(0, 4.5, 1.0), (2.15, 0.45, 2.15), h.GOLD)
            ell(grip + V(0, 4.6, 1.0), (1.6, 0.3, 1.6), h.TEAL, kind="emit")  # the brew glows
            ell(grip + V(-2.3, 2.3, 1.0), (0.55, 1.3, 1.0), h.LEATHER)  # the handle
        limb(V(5.5, 25.0, -1.2), V(8.8, 8.0, -6.5), 1.25, 1.0, CLOTH_D)  # the sword stays sheathed at his hip
        ell(V(5.4, 27.6, -1.0), (0.7, 2.3, 0.7), h.LEATHER)
        ell(V(5.4, 26.6, -1.0), (2.7, 0.5, 0.7), STEEL)
        ell(V(5.4, 30.0, -1.0), (0.9, 0.9, 0.9), h.GOLD, kind="emit")
    else:
        # the sword
        d = V(*pose["sword"])
        d = d / np.linalg.norm(d)
        n = np.cross(d, V(0, 1, 0.001))
        n = n / np.linalg.norm(n)
        Rb = h.frame_from(d, n)
        ell(grip + d * 3.0, (3.6, 0.55, 0.7), STEEL, R=Rb @ rot_y(0.0))
        ell(grip - d * 2.0, (0.9, 0.9, 0.9), h.GOLD, kind="emit")
        limb(grip - d * 1.5, grip + d * 3.0, 0.75, 0.75, h.LEATHER)
        steps = int(31 / 0.6)
        for k in range(steps + 1):
            t = k / steps
            c = grip + d * (4.0 + 31.0 * t)
            if c[1] < 0.4:
                continue  # planted in the ground
            wid = 1.25 * (1.0 - 0.5 * max(0.0, (t - 0.88) / 0.12))
            ell(c, (wid, 0.65, 0.3), BLADE, R=Rb)
            ell(c + n * 0.0 + np.cross(d, n) * (wid * 0.9), (0.3, 0.6, 0.25), WGLOW, kind="emit", R=Rb)
            if k % 9 == 4:
                ell(c, (0.35, 0.35, 0.4), WGLOW, kind="emit")  # a rune
    m.rig = {}
    return m


def pickaxe(m, grip, d):
    """A heavy miner's pick held in both hands: a long haft wrapped in wine-red cloth with iron bands, a thick socket and a double-pointed iron head, the two long
    tips curving back towards the haft, a rune along the head that glows, the cutting tips lit."""
    d = d / np.linalg.norm(d)
    a = np.cross(V(1, 0, 0), d)
    a = a / np.linalg.norm(a)
    if a[2] < 0:
        a = -a
    m.limb(grip - d * 4.0, grip + d * 29.5, 1.3, 1.1, h.LEATHER)
    for k in range(4):  # the cloth wrap under the hands
        m.ell(grip + d * (0.5 + k * 3.0), (1.65, 1.65, 1.65), CLOTH)
    for k in range(3):
        m.ell(grip + d * (11.5 + k * 6.0), (1.5, 1.5, 1.5), STEEL_D)  # iron bands
    m.ell(grip - d * 4.4, (1.9, 1.9, 1.9), STEEL_D)  # the butt cap
    head = grip + d * 30.0
    m.ell(head, (2.7, 2.7, 2.7), STEEL_D)
    m.ell(head - d * 2.2, (2.2, 2.0, 2.2), STEEL)  # the socket
    for side in (1, -1):
        prev = head
        for t in range(1, 15):
            p = head + a * side * t * 1.05 - d * (0.034 * t * t)
            r = 3.0 - 0.19 * t
            m.limb(prev, p, max(r + 0.16, 0.45), max(r, 0.4), BLADE if t > 10 else STEEL_D)
            if 2 < t < 11 and t % 2 == 0:
                m.ell(p + d * 0.6, (0.5, 0.5, 0.5), WGLOW, kind="emit")  # the rune along the head
            prev = p
        m.ell(prev, (0.5, 0.5, 0.5), WGLOW, kind="emit")  # the tip catches the light


# ------------------------------------------------------------------ poses
def run_pose(i, n=6):
    ph = 2 * math.pi * (i % n) / n
    s, c = math.sin(ph), math.cos(ph)
    feet = ((2.8, 5.5 * s + 2.0, 3.6 * max(0.0, c) ** 1.3), (-2.8, -5.5 * s + 2.0, 3.6 * max(0.0, -c) ** 1.3))
    return P(lean=0.37 + 0.025 * math.cos(2 * ph), twist=0.04 * s, pz=2.0 + 0.22 * (1 - math.cos(2 * ph)),
             feet=feet, hand_r=(-5.5, 27.0, -2.5), hand_l=(4.8, 28.5 + 1.8 * c, 3.5 * s + 2.0),
             sword=(-0.15, -0.3, -0.94), cloak=(0.45 * math.sin(ph - 0.8), 2.0, -7.8 + 1.1 * math.sin(ph - 1.2)),
             wave=ph, breath=0.0, head=-0.18)


IDLE = [P(breath=0.5 - 0.5 * math.cos(a), cloak=(0.6 * math.sin(a), 0.0, -2.2), wave=a,
          hand_r=(-6.0, 23.0 + 0.1 * (1.0 - math.cos(a)), 4.0)) for a in (2 * math.pi * i / 4 for i in range(4))]
RUN = [run_pose(i) for i in range(6)]
SLASH_A = [  # forehand, right to left
    P(twist=-0.7, lean=0.0, pz=-0.8, feet=((3.4, 3.0, 0), (-3.2, -4.0, 0)), hand_r=(-9.0, 33.0, -3.5), hand_l=(5.0, 31.0, 4.0), sword=(-0.5, 0.55, -0.7), cloak=(0, 0, -4), wave=0.4),
    P(twist=-0.3, lean=0.08, pz=0.6, feet=((3.2, 4.0, 0), (-3.2, -3.0, 0)), hand_r=(-7.0, 32.0, 3.0), hand_l=(5.5, 31.0, 2.5), sword=(-0.35, 0.25, 0.9), cloak=(1.5, 0, -7), wave=0.9),
    P(twist=0.45, lean=0.14, pz=1.8, feet=((3.0, 5.5, 0), (-3.2, -2.0, 0.4)), hand_r=(-1.0, 31.0, 9.0), hand_l=(6.0, 31.0, -1.5), sword=(0.75, 0.05, 0.65), cloak=(3.5, 0, -8), wave=1.6),
    P(twist=0.95, lean=0.16, pz=2.2, feet=((3.0, 6.0, 0), (-3.2, -1.0, 0)), hand_r=(6.0, 30.0, 6.5), hand_l=(7.0, 33.0, -3.5), sword=(0.95, 0.1, -0.15), cloak=(6.0, 0, -4), wave=2.2),
    P(twist=0.6, lean=0.1, pz=1.4, feet=((3.0, 5.0, 0), (-3.0, -1.0, 0)), hand_r=(4.0, 28.0, 6.0), hand_l=(6.0, 30.0, -1.0), sword=(0.8, -0.2, 0.4), cloak=(3.0, 0, -3), wave=2.8),
    P(twist=0.15, lean=0.03, pz=0.6, feet=((2.8, 3.0, 0), (-2.8, -0.5, 0)), hand_r=(-5.0, 24.5, 4.0), hand_l=(4.8, 26.0, 1.0), sword=(0.2, -0.85, 0.4), cloak=(1.0, 0, -2), wave=3.2),
]
SLASH_B = [  # backhand, left to right
    P(twist=0.7, lean=-0.02, pz=-0.2, feet=((3.0, 4.0, 0), (-3.0, -1.5, 0)), hand_r=(4.0, 30.0, 4.0), hand_l=(7.0, 33.0, -2.0), sword=(0.8, 0.1, -0.3), cloak=(3, 0, -4), wave=0.4),
    P(twist=0.2, lean=0.06, pz=0.9, feet=((3.0, 3.2, 0), (-3.0, -0.5, 0.3)), hand_r=(1.5, 31.5, 8.0), hand_l=(6.5, 33.0, -1.5), sword=(0.55, 0.1, 0.8), cloak=(1, 0, -7), wave=0.9),
    P(twist=-0.4, lean=0.12, pz=1.6, feet=((3.0, 2.0, 0.3), (-3.0, 4.5, 0)), hand_r=(-5.0, 31.0, 7.5), hand_l=(6.0, 31.0, 1.0), sword=(-0.8, 0.05, 0.6), cloak=(-3, 0, -8), wave=1.6),
    P(twist=-0.9, lean=0.15, pz=1.9, feet=((3.0, 1.5, 0.3), (-3.0, 5.5, 0)), hand_r=(-9.0, 30.5, 3.0), hand_l=(5.5, 32.0, 4.5), sword=(-0.95, 0.1, -0.1), cloak=(-6, 0, -4), wave=2.2),
    P(twist=-0.5, lean=0.09, pz=1.3, feet=((3.0, 1.5, 0), (-3.0, 4.5, 0)), hand_r=(-7.0, 29.0, 2.5), hand_l=(5.5, 30.0, 3.0), sword=(-0.8, -0.2, 0.3), cloak=(-3, 0, -3), wave=2.8),
    P(twist=-0.05, lean=0.03, pz=0.5, feet=((2.8, 0.5, 0), (-2.8, 3.0, 0)), hand_r=(-5.0, 24.5, 4.0), hand_l=(4.8, 26.0, 1.0), sword=(0.2, -0.85, 0.4), cloak=(-1, 0, -2), wave=3.2),
]
SLASH_C = [  # the finisher: a rising spin, the sword carried round in a full circle over the head
    P(twist=-0.9, lean=0.15, pz=-1.2, feet=((3.6, 3.0, 0), (-3.4, -5.0, 0)), hand_r=(-8.0, 24.0, -1.0), hand_l=(5.0, 28.0, 3.0), sword=(-0.5, -0.5, -0.7), cloak=(0, 2, -6), wave=0.3),
    P(twist=-0.2, lean=0.2, pz=0.6, feet=((3.4, 4.0, 0), (-3.4, -4.5, 0)), hand_r=(-6.0, 29.0, 3.0), hand_l=(5.0, 31.0, 4.0), sword=(-0.55, 0.15, 0.8), cloak=(2, 2, -7), wave=1.0),
    P(twist=0.7, lean=0.1, pz=1.8, feet=((3.2, 6.5, 0.8), (-3.2, -4.5, 0)), hand_r=(0.0, 38.0, 6.5), hand_l=(7.0, 34.0, -2.0), sword=(0.2, 0.95, 0.2), cloak=(5, 3, -4), wave=2.0),
    P(twist=1.4, lean=0.2, pz=2.6, feet=((3.2, 8.0, 0), (-3.2, -3.5, 0.6)), hand_r=(7.5, 32.0, 6.5), hand_l=(7.0, 33.0, -3.0), sword=(0.95, -0.15, 0.1), cloak=(7, 2, 0), wave=3.0),
    P(twist=1.0, lean=0.12, pz=1.6, feet=((3.0, 6.0, 0), (-3.0, -2.5, 0)), hand_r=(5.0, 26.0, 7.0), hand_l=(6.0, 29.0, 0.0), sword=(0.85, -0.45, 0.3), cloak=(4, 1, -2), wave=3.6),
    P(twist=0.25, lean=0.04, pz=0.7, feet=((2.8, 3.5, 0), (-2.8, -0.5, 0)), hand_r=(-5.0, 24.5, 4.0), hand_l=(4.8, 26.0, 1.0), sword=(0.2, -0.85, 0.4), cloak=(1, 0, -2), wave=4.0),
]
LAND = [  # drops in on one knee with the sword planted, rises and stands tall
    P(lean=0.4, pz=3.0, feet=((4.2, 7.0, 0), (-4.0, -4.0, 0)), hand_r=(-3.0, 15.0, 7.0), hand_l=(6.0, 18.0, 0.0), sword=(0.05, -0.97, 0.2), cloak=(0, 6, -3), wave=0.5, head=0.25),
    P(lean=0.35, pz=2.6, feet=((4.0, 6.5, 0), (-3.8, -3.5, 0)), hand_r=(-3.0, 15.0, 7.0), hand_l=(6.0, 17.0, 0.0), sword=(0.05, -0.97, 0.2), cloak=(0, 3, -4), wave=1.0, head=0.2),
    P(lean=0.22, pz=1.6, feet=((3.6, 5.0, 0), (-3.4, -2.0, 0)), hand_r=(-3.2, 17.5, 7.5), hand_l=(6.0, 22.0, 1.0), sword=(0.05, -0.97, 0.22), cloak=(0, 1, -3), wave=1.6, head=0.1),
    P(lean=0.1, pz=0.8, feet=((3.2, 3.8, 0), (-3.1, -1.0, 0)), hand_r=(-3.4, 19.0, 8.0), hand_l=(5.5, 24.0, 1.5), sword=(0.05, -0.97, 0.22), cloak=(0, 0.3, -2.5), wave=2.2),
    P(lean=0.0, pz=0.3, feet=((3.0, 3.2, 0), (-3.0, -0.5, 0)), hand_r=(-3.4, 19.5, 8.5), hand_l=(5.0, 25.0, 1.5), sword=(0.04, -0.98, 0.2), cloak=(0.3, 0, -2.2), wave=2.8, breath=0.5),
]
DIVE = [  # a plunge from above: coiled in the air, then the sword driven down, then the impact
    P(lean=0.55, pz=-1.0, feet=((3.0, -3.0, 7.0), (-3.0, -5.0, 6.0)), hand_r=(-2.5, 41.0, -4.5), hand_l=(2.5, 40.0, -4.0), sword=(0.0, 0.8, -0.6), cloak=(0, 7, -3), wave=0.6, head=0.2),
    P(lean=0.6, pz=0.5, feet=((3.0, -4.0, 6.0), (-3.0, -6.0, 5.0)), hand_r=(-2.0, 35.0, 8.0), hand_l=(2.0, 34.0, 7.5), sword=(0.05, -0.8, 0.6), cloak=(0, 9, -2), wave=1.4, head=0.3),
    P(lean=0.55, pz=3.0, feet=((4.4, 7.5, 0), (-4.0, -4.5, 0)), hand_r=(-2.0, 13.0, 10.0), hand_l=(2.0, 14.0, 9.5), sword=(0.0, -0.96, 0.25), cloak=(0, 6, -4), wave=2.0, head=0.3),
]
FLICK = [  # the blade shaken clean after the last cut, then lowered
    P(twist=-0.3, lean=0.05, pz=0.3, feet=((3.0, 3.0, 0), (-3.0, -1.0, 0)), hand_r=(-9.5, 30.0, 2.0), hand_l=(4.5, 25.0, 1.0), sword=(-0.9, 0.35, 0.25), cloak=(-2, 0, -3), wave=0.5),
    P(twist=-0.5, lean=0.1, pz=0.6, feet=((3.0, 3.0, 0), (-3.0, -1.0, 0)), hand_r=(-8.5, 22.0, 4.0), hand_l=(4.5, 25.0, 1.0), sword=(-0.55, -0.75, 0.3), cloak=(-3, 0, -3), wave=1.2),
    P(twist=-0.3, lean=0.05, pz=0.4, feet=((3.0, 3.0, 0), (-3.0, -1.0, 0)), hand_r=(-7.0, 21.5, 4.0), hand_l=(4.5, 25.0, 1.0), sword=(-0.35, -0.85, 0.35), cloak=(-1, 0, -2.5), wave=1.8),
    P(twist=0.0, lean=0.02, pz=0.2, feet=((2.8, 2.5, 0), (-2.8, -1.0, 0)), hand_r=(-6.0, 23.0, 4.0), hand_l=(4.8, 25.0, 1.0), sword=(0.45, -0.66, 0.6), cloak=(0, 0, -2.2), wave=2.4),
]
KNEEL = [  # down on one knee beside her, the sword planted, the free hand reaching out
    P(lean=0.12, pz=0.6, feet=((3.2, 4.0, 0), (-3.0, -2.0, 0)), hand_r=(-4.0, 21.0, 7.0), hand_l=(5.0, 24.0, 3.0), sword=(0.05, -0.97, 0.22), cloak=(0, 1, -2.5), wave=0.4, head=0.1),
    P(lean=0.3, pz=1.5, feet=((3.4, 8.0, 0), (-3.2, -9.0, 0)), hand_r=(-4.0, 17.0, 8.0), hand_l=(5.0, 20.0, 8.0), sword=(0.05, -0.97, 0.22), cloak=(0, 3, -4), wave=1.0, head=0.25),
    P(lean=0.45, pz=2.4, feet=((3.5, 11.0, 0), (-3.4, -14.0, 0)), hand_r=(-4.0, 14.0, 9.0), hand_l=(3.0, 13.0, 15.0), sword=(0.05, -0.97, 0.22), cloak=(0, 5, -5), wave=1.6, head=0.4),
    P(lean=0.47, pz=2.6, feet=((3.5, 11.0, 0), (-3.4, -14.0, 0)), hand_r=(-4.0, 14.0, 9.0), hand_l=(3.0, 12.0, 16.0), sword=(0.05, -0.97, 0.22), cloak=(0, 4, -4.5), wave=2.2, head=0.42, breath=0.4),
]
def mine_pose(hand_r, d, **kw):
    d = np.array(d, float)
    d = d / np.linalg.norm(d)
    hand_l = tuple(np.array(hand_r) + d * 10.0 + V(1.6, 0, 0))  # the left hand holds the haft above the right
    base = dict(feet=((3.6, 3.5, 0), (-3.4, -3.5, 0)), cloak=(0, 0, -2.5), tool="pick")
    base.update(kw)
    return P(hand_r=hand_r, hand_l=hand_l, sword=tuple(d), **base)


WIDE = ((4.4, 5.0, 0), (-4.2, -5.0, 0))
LUNGE = ((4.0, 7.5, 0), (-3.8, -6.0, 0))
MINE = [  # a heavy, two-handed rhythm: ready, a crouch drawing the pick back, the full wind-up (back arched, the head hanging behind him), a held breath, the whip
          # over the head, the downswing, the STRIKE (index 6: lunging, the whole weight behind it), the jolt of the impact, yanking it free, an exhale, settling
    mine_pose((-4.5, 23.0, 6.0), (0, 0.7, 0.7), lean=0.05, wave=0.2),
    mine_pose((-4.0, 28.0, 0.5), (0, 0.9, -0.25), lean=-0.16, pz=-0.8, twist=-0.15, wave=0.7, feet=WIDE, cloak=(0, 2, -4), head=-0.1),
    mine_pose((-3.5, 40.5, -4.0), (0, 0.55, -0.85), lean=-0.4, pz=-1.3, twist=-0.28, wave=1.2, feet=WIDE, cloak=(0, 4, -8), head=-0.25),
    mine_pose((-3.6, 41.0, -4.6), (0, 0.5, -0.87), lean=-0.44, pz=-1.5, twist=-0.34, wave=1.5, feet=WIDE, cloak=(0, 5, -9), head=-0.28, breath=0.6),
    mine_pose((-3.5, 41.5, 2.0), (0, 0.97, 0.25), lean=0.04, pz=0.2, twist=0.05, wave=1.9, feet=WIDE, cloak=(0, 3, -6), head=-0.1),
    mine_pose((-3.3, 34.0, 8.0), (0, 0.38, 0.93), lean=0.36, pz=1.8, twist=0.12, wave=2.3, feet=LUNGE, cloak=(0, 5, -3), head=0.1),
    mine_pose((-3.2, 22.0, 9.5), (0, -0.26, 0.97), lean=0.72, pz=2.8, twist=0.1, wave=2.7, feet=LUNGE, cloak=(0, 7, 1), head=0.3),
    mine_pose((-3.2, 22.6, 8.8), (0, -0.2, 0.98), lean=0.66, pz=2.5, twist=0.08, wave=3.0, feet=LUNGE, cloak=(0, 4, 0), head=0.28, breath=0.5),
    mine_pose((-3.4, 27.0, 5.5), (0, 0.42, 0.9), lean=0.36, pz=1.8, twist=-0.05, wave=3.4, feet=LUNGE, cloak=(0, 2, -3), head=0.12),
    mine_pose((-4.2, 24.0, 6.0), (0, 0.55, 0.83), lean=0.2, pz=0.8, wave=3.8, breath=0.6),
    mine_pose((-4.5, 23.0, 6.0), (0, 0.65, 0.75), lean=0.1, wave=4.2, breath=0.9),
    mine_pose((-4.5, 23.0, 6.0), (0, 0.7, 0.7), lean=0.06, wave=4.6, breath=0.3),
]
SET = [  # he puts the pick down against the stone: it comes down in front of him, is held upright, let go (frame 3 is where the leaning pick prop takes over), his hands empty, he straightens
    mine_pose((-4.5, 23.0, 6.0), (0, 0.7, 0.7), lean=0.06, wave=0.2),
    mine_pose((-3.8, 24.0, 9.0), (0, 0.55, 0.83), lean=0.26, pz=1.2, wave=0.8, feet=LUNGE, head=0.12),
    mine_pose((-3.2, 18.5, 12.0), (0.0, 0.96, 0.28), lean=0.48, pz=2.0, wave=1.3, feet=LUNGE, cloak=(0, 3, -2), head=0.25),
    mine_pose((-3.0, 17.0, 12.5), (0.0, 0.97, 0.2), lean=0.4, pz=1.6, wave=1.6, feet=LUNGE, cloak=(0, 2, -2), head=0.22),
    P(tool="empty", lean=0.24, pz=1.0, hand_r=(-5.0, 22.0, 7.0), hand_l=(5.2, 23.0, 5.0), wave=2.0, feet=((3.4, 4.0, 0), (-3.2, -3.0, 0)), cloak=(0, 1, -2.5), head=0.1),
    P(tool="empty", lean=0.04, pz=0.4, hand_r=(-6.0, 24.0, 3.0), hand_l=(6.0, 26.5, 1.5), wave=2.4, cloak=(0.4, 0, -2.2), breath=0.5),
]
STAND = [P(tool="empty", breath=0.5 - 0.5 * math.cos(a), cloak=(0.6 * math.sin(a), 0.0, -2.2), wave=a,
           hand_r=(-6.0, 24.1 - 0.1 * math.cos(a), 3.0), hand_l=(6.0, 26.6 - 0.1 * math.cos(a), 1.5), head=0.04 * math.sin(a))
         for a in (2 * math.pi * i / 5 for i in range(5))]
def walk_pose(i, n=8):  # an unhurried stride, empty hands swinging a little, the cloak trailing
    ph = 2 * math.pi * (i % n) / n
    s, c = math.sin(ph), math.cos(ph)
    feet = ((2.8, 4.2 * s + 2.0, 2.2 * max(0.0, c) ** 1.3), (-2.8, -4.2 * s + 2.0, 2.2 * max(0.0, -c) ** 1.3))
    return P(tool="empty", lean=0.11 + 0.015 * math.cos(2 * ph), twist=0.035 * s,
             pz=1.0 + 0.16 * (1.0 - math.cos(2 * ph)), feet=feet,
             hand_r=(-6.0, 24.0, 3.0 + 1.7 * s), hand_l=(6.0, 26.5, 1.5 - 1.7 * s),
             cloak=(0.4 * math.sin(ph - 0.7), 1.1, -4.2 + 1.0 * math.sin(ph - 1.1)), wave=ph, head=0.035 * c)


WALK = [walk_pose(i) for i in range(8)]


def mug_walk_pose(i, n=8):  # the same stride, the right hand carrying the mug out in front
    return dict(walk_pose(i, n), tool="mug", hand_r=(-3.0, 27.0, 9.5 + 0.3 * math.sin(2 * math.pi * i / n)))


WALK_MUG = [mug_walk_pose(i) for i in range(8)]
GIVE = [dict(STAND[0], tool="mug", hand_r=(-3.0, 27.5 + 0.3 * k, 9.5 + 2.2 * k), lean=0.06 + 0.02 * k, head=0.08) for k in range(4)] + [
    dict(STAND[0], tool="empty", hand_r=(-3.0, 28.0, 14.5), lean=0.08, head=0.08), dict(STAND[0], tool="empty", hand_r=(-4.0, 25.0, 8.0), lean=0.04)]
def sit_pose(k, breath=0.0, wave=0.0):  # k 0 standing .. 1 seated on a log, his hands resting on his knees (empty), cloak pooled behind
    pz = -7.0 * k
    reach = 6.5 * k
    return P(tool="empty", lean=0.05 + 0.12 * k, pz=pz, feet=((3.4, 2.5 + reach, 0.0), (-3.4, -1.0 + reach * 0.9, 0.0)),
             hand_r=(-6.0, 24.0 - 9.5 * k, 3.0 + 6.0 * k), hand_l=(6.0, 26.5 - 11.5 * k, 1.5 + 6.5 * k), cloak=(0.0, 0.5 * k, -2.5 - 1.5 * k), wave=wave, breath=breath, head=0.06 * k)


SIT_DOWN = [sit_pose(k) for k in (0.25, 0.55, 0.85, 1.0)]
SIT = [sit_pose(1.0, b, a) for a, b in ((0.0, 0.0), (1.6, 0.8), (3.1, 1.0), (4.7, 0.3))]
def hammer_pose(hand_r, d, **kw):
    base = dict(feet=((3.2, 3.0, 0), (-3.2, -2.5, 0)), cloak=(0, 1, -2.5), tool="hammer")
    base.update(kw)
    return P(hand_r=hand_r, sword=d, hand_l=(5.6, 26.0, 3.0), **base)


HAMMER = [  # a steady rhythm of nailing: the mallet raised, the wind-up, the swing, the STRIKE (index 3), the rebound, back
    hammer_pose((-4.5, 31.0, 5.0), (0, 0.9, 0.35), lean=0.1, wave=0.3),
    hammer_pose((-4.2, 37.0, 1.5), (0, 0.97, -0.15), lean=-0.02, pz=-0.4, twist=-0.1, wave=0.8, head=-0.08),
    hammer_pose((-4.0, 31.0, 8.0), (0, 0.5, 0.85), lean=0.2, pz=0.9, twist=0.06, wave=1.2, cloak=(0, 3, -3)),
    hammer_pose((-3.8, 25.5, 11.5), (0, -0.05, 1.0), lean=0.34, pz=1.5, twist=0.1, wave=1.6, cloak=(0, 4, -1), head=0.16),
    hammer_pose((-4.0, 28.0, 9.5), (0, 0.4, 0.9), lean=0.22, pz=1.0, wave=2.0),
    hammer_pose((-4.4, 30.0, 6.5), (0, 0.75, 0.6), lean=0.12, wave=2.4),
]


def beam_pose(i, n=8):  # the same unhurried stride with a beam on the shoulder: the right hand up at it, the left hand steadying it in front
    return dict(walk_pose(i, n), tool="beam", hand_r=(-3.2, 37.0, 1.5), hand_l=(3.5, 36.0, 7.0))


BEAM_WALK = [beam_pose(i) for i in range(8)]
CLIPS = [("idle", IDLE, 6, True), ("run", RUN, 14, True), ("slash_a", SLASH_A, 16, False), ("slash_b", SLASH_B, 16, False),
         ("slash_c", SLASH_C, 14, False), ("land", LAND, 8, False), ("dive", DIVE, 9, False), ("flick", FLICK, 11, False), ("kneel", KNEEL, 8, False), ("mine", MINE, 10, True), ("set", SET, 6, False), ("stand", STAND, 5, True), ("walk", WALK, 10, True), ("sit_down", SIT_DOWN, 6, False), ("sit", SIT, 4, True), ("walk_mug", WALK_MUG, 10, True), ("give", GIVE, 5, False), ("hammer", HAMMER, 9, True), ("carry_beam", BEAM_WALK, 9, True)]


def render(pose, sector):
    yaw = math.pi / 2 - sector * math.pi / 4
    m = build(pose)
    depth, code = h.render(m.transform(yaw, 0.0))
    return h.to_pixels(depth, code)


def shadow(rows):
    for y in range(FH1):
        for x in range(FW1):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW1 / 2) / 12.0, (y + 0.5 - GROUND) / 3.2
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 70)
    return rows


def glow(rows):
    cols = {tuple(c) for c in h.RAMPS[WGLOW]}
    return [[c if tuple(c) in cols else CLEAR for c in row] for row in rows]


def contact(path, sectors=(0, 2), step=1):
    poses = [(n, p) for n, ps, _f, _l in CLIPS for p in ps]
    cols = 11
    k = 2
    n = len(poses)
    rows_n = ((n + cols - 1) // cols) * len(sectors)
    bg = (62, 100, 80, 255)
    out = [[bg] * (cols * FW1 * k) for _ in range(rows_n * FH1 * k)]
    for si, sec in enumerate(sectors):
        for i, (_n, pose) in enumerate(poses):
            r, c = divmod(i, cols)
            fr = render(pose, sec)
            for y in range(FH1):
                for x in range(FW1):
                    px = fr[y][x]
                    if px[3]:
                        px = tuple(int(px[j] * px[3] / 255 + bg[j] * (1 - px[3] / 255)) for j in range(3)) + (255,)
                        for dy in range(k):
                            for dx in range(k):
                                out[((si * ((n + cols - 1) // cols) + r) * FH1 + y) * k + dy][(c * FW1 + x) * k + dx] = px
    write_png(Path(path), cols * FW1 * k, rows_n * FH1 * k, out)


def _render_sheet_frame(job):
    sector, index, pose = job
    pixels = np.asarray(render(pose, sector), dtype=np.uint8)
    pixels[pixels[:, :, 3] == 70] = 0  # the game draws the ground shadow separately
    return sector, index, pixels.tobytes()


def _write_array(path, pixels):
    height, width, _ = pixels.shape
    raw = b"".join(b"\0" + pixels[y].tobytes() for y in range(height))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def write_sheet():
    poses = [p for _n, ps, _f, _l in CLIPS for p in ps]
    total = len(poses)
    sheet = np.zeros((8 * FH1, total * FW1, 4), dtype=np.uint8)
    jobs = [(sec, i, pose) for sec in range(8) for i, pose in enumerate(poses)]
    workers = min(6, os.cpu_count() or 1)
    print(f"Rendering {len(jobs)} frames in {workers} workers", flush=True)
    with mp.Pool(workers) as pool:
        for done, (sec, i, data) in enumerate(pool.imap_unordered(_render_sheet_frame, jobs, chunksize=2), 1):
            sheet[sec * FH1:(sec + 1) * FH1, i * FW1:(i + 1) * FW1] = np.frombuffer(data, dtype=np.uint8).reshape(FH1, FW1, 4)
            if done % 100 == 0:
                print(f"{done}/{len(jobs)}", flush=True)
    mask = np.zeros(sheet.shape[:2], dtype=bool)
    for color in h.RAMPS[WGLOW]:
        mask |= np.all(sheet == color, axis=2)
    glow_sheet = np.where(mask[:, :, None], sheet, 0).astype(np.uint8)
    _write_array(ROOT / "characters" / "adventurer.png", sheet)
    _write_array(ROOT / "characters" / "adventurer_glow.png", glow_sheet)
    clips, start = {}, 0
    for name, ps, fps, loop in CLIPS:
        clips[name] = {"start": start, "count": len(ps), "fps": fps, "loop": loop}
        start += len(ps)
    rig = {"frame": [FW1, FH1], "feet": [FW1 // 2, GROUND], "frames": total, "clips": clips}
    (ROOT.parent / "data" / "adventurer_rig.json").write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    print("adventurer sheet written")


def write_portrait():
    """A backlit bust: everything dark with a cold rim, the glowing slit and the sword edge the only light."""
    h.FW, h.FH, h.GROUND_ROW = 103, 153, 188
    h.SCALE = 3.3
    dark = [["06040c", "0c0816", "150f26", "4a3c80"], ["0c0810", "16101c", "24182c", "5a3a60"]]
    saved = list(h.RAMPS)
    for mat in (STEEL, STEEL_D, h.LEATHER, h.LEGGING, h.GOLD, BLADE):
        h.RAMPS[mat] = [hexc(c) for c in dark[0]]
    for mat in (CLOTH, CLOTH_D, VOIDM):
        h.RAMPS[mat] = [hexc(c) for c in dark[1]]
    pose = P(lean=0.04, head=0.08, breath=0.3, cloak=(0, 0, -2))
    m = build(pose)
    shift = 0.0
    depth, code = h.render(m.transform(0.0, -shift))
    rows = h.to_pixels(depth, code)
    rows = [[(c if c[3] != 70 else CLEAR) for c in row] for row in rows]
    h.RAMPS[:] = saved
    write_png(ROOT / "ui" / "portrait_adventurer.png", 103, 153, rows)
    print("portrait written")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "sheet":
        write_sheet()
    elif len(sys.argv) > 1 and sys.argv[1] == "portrait":
        write_portrait()
    else:
        contact(sys.argv[1] if len(sys.argv) > 1 else "/tmp/adv.png")
