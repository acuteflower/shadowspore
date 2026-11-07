"""The waystone: a goddess statue of pale violet stone on a stepped plinth with dark crystals growing out of her (the teleport points of the world).
Same ellipsoid renderer as the heroine, the signpost and the trees.
    py -3 tools/art_waystone.py [preview.png]
Writes assets/props/waystone/:
  statue_wild.png   the statue as it is found: cracked, chipped, broken left hand, overgrown with moss, ivy and roots, DARK crystals
  statue_clean.png  the same model awakened: whole, pale, polished gold, lit crystals, no growth
  statue_glow.png   only the emissive pixels of the awakened statue (crystals, runes, eyes) + a dithered halo, drawn unlit
  statue_dim.png    the faint emissive pixels of the dormant statue (dim buds, a glint in each dark crystal), drawn unlit
  statue_wave.png   per pixel the moment (R, 0..255) the awakening reaches it: the light runs out of the crystals, the growth withers ahead of it
  statue_dark.png   2 frames of the plinth ring seen from above (decal under the statue): dormant / lit runes
All sheets are FW x FH, ground row GROUND_ROW (the statue's origin), x centre FW / 2. Also prints the crystal positions (px) for the effects."""
import json
import math
import pathlib
import sys

import numpy as np

import art_hero3d as h
from gen_art import ROOT, hexc, write_png, CLEAR

FW1, FH, GROUND = 104, 112, 92
h.FW, h.FH, h.GROUND_ROW = FW1, FH, float(GROUND)
h.SCALE = 0.74  # the statue is about 1.6 x as tall as Ellie (the first version at 0.92 was too big)
BASE = len(h.RAMPS)
STONE, STONE_D, MOSS, ROOT_M, CRYST_D, CRYST_L, CRACK, GOLD_O = range(BASE, BASE + 8)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["3a3858", "615f8c", "9795b8", "d4d2ea"],  # pale violet marble
    ["1d1b30", "2f2d4b", "4b4972", "706e98"],  # the plinth: older, darker stone
    ["1c3d36", "2b5646", "3a7550", "74b268"],  # moss and ivy
    ["1a1322", "34283c", "55435a", "85697a"],  # roots, like the trees' bark
    ["05030a", "120a26", "261852", "4e3d98"],  # dormant crystal: black violet with a cold glint
    ["3a1d86", "7a4bdc", "b99bff", "f0e6ff"],  # awakened crystal: violet to white
    ["07050c", "0f0a1a", "181129", "261c3e"],  # cracks, carved grooves
    ["4a3a22", "7a6030", "a88a44", "cdb064"],  # old gold, a little dull
]]
GLOW_MATS = (CRYST_L, h.TEAL)
V = lambda *a: np.array(a, float)
PITCH_SIN, PITCH_COS, SC = h.SINP, h.COSP, h.SCALE
SNAP = math.pi / 3  # crystals are hexagonal prisms

Y0 = 17.0  # plinth top = her feet
HEIGHT = 68.0  # her height in model units (feet to the top of the head)
ROBE = [  # fraction of the height, rx, rz
    (0.00, 13.0, 11.0), (0.08, 11.4, 9.8), (0.2, 8.8, 7.8), (0.36, 7.0, 6.0), (0.50, 5.6, 4.8), (0.58, 4.9, 4.2), (0.68, 6.8, 5.3), (0.79, 9.8, 5.0), (0.835, 3.8, 3.4),
]
HEAD = V(0, Y0 + HEIGHT * 0.925, 0.5)
SHOULDER = {"R": V(-9.6, Y0 + HEIGHT * 0.775, 0.3), "L": V(9.6, Y0 + HEIGHT * 0.775, 0.3)}  # R = her right = the viewer's left


def robe_r(f):
    fr, rx, rz = zip(*ROBE)
    return float(np.interp(f, fr, rx)), float(np.interp(f, fr, rz))


def robe_pt(f, ang, push=0.0):
    rx, rz = robe_r(f)
    return V((rx + push) * math.sin(ang), Y0 + HEIGHT * f, (rz + push) * math.cos(ang))


def paint_face(q, mat, band):
    """The goddess' face (local coordinates of the head ellipsoid): calm closed eyes under fine brows, a straight nose shaded by the light, small lips, softly
    lit cheeks; awakened (`eyes_lit`) her eyes are two slits of light."""
    x, y, z = q[..., 0], q[..., 1], q[..., 2]
    front = z > 0.40
    for sx in (-1, 1):
        ex = np.abs(x - sx * 0.40)
        eye = front & (ex < 0.24) & (np.abs(y - 0.02 + 0.14 * (ex / 0.24) ** 2) < 0.085)
        brow = front & (ex < 0.28) & (np.abs(y - 0.20 - 0.10 * (ex / 0.28)) < 0.045)
        if STATE["eyes_lit"]:
            mat = np.where(eye, h.TEAL, mat)
            band = np.where(eye, 3, band)
        else:
            mat = np.where(eye, CRACK, mat)
            band = np.where(eye, 1, band)
        mat = np.where(brow & ~eye, STONE_D, mat)
        band = np.where(brow & ~eye, 2, band)
        cheek = front & (ex < 0.2) & (np.abs(y + 0.28) < 0.12)
        band = np.where(cheek & ~eye, np.maximum(band, 3), band)
    nose_shadow = front & (np.abs(x) < 0.10) & (y < -0.12) & (y > -0.36)
    band = np.where(nose_shadow, np.minimum(band, 1), band)
    mouth = front & (np.abs(x) < 0.17) & (np.abs(y + 0.55) < 0.06)
    mat = np.where(mouth, STONE_D, mat)
    band = np.where(mouth, 2, band)
    return mat.astype(np.int16), band.astype(np.int16)


h.paint_face = paint_face
STATE = {"eyes_lit": False}


# ------------------------------------------------------------------ the model
class Maker:
    def __init__(self, wild: bool, seed: int = 11):
        self.wild = wild
        self.m = h.Model()
        self.rng = np.random.default_rng(seed)  # the same draws in both states: shared geometry stays identical
        self.rng_w = np.random.default_rng(seed + 100)  # the growth (wild only)
        self.crystals: list[tuple[float, float, float, float]] = []  # (x, y, z, weight) of every crystal's heart, model units

    # materials that change between the two states
    @property
    def cm(self):
        return CRYST_D if self.wild else CRYST_L

    @property
    def ck(self):
        return "" if self.wild else "emit"

    @property
    def fk(self):
        return "facet" if self.wild else "facet_emit"

    def crystal(self, base, d, length, w, sides=True):
        """A hexagonal crystal: a chain of ellipsoids along its axis (kind facet: the rasteriser snaps their normals to six flat faces), a pointed tip, and
        (sides) two shorter shards growing out of its flank."""
        m = self.m
        d = np.array(d, float)
        d = d / np.linalg.norm(d)
        b = np.array(base, float)
        hint = np.array([0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        R = h.frame_from(d, hint)
        n = max(4, int(length / 1.8))
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            tm = (t0 + t1) / 2
            r = w if tm < 0.58 else w * max(0.10, 1.0 - (tm - 0.58) / 0.42 * 0.95)
            m.ell(b + d * length * tm, (r, length * (t1 - t0) / 2 * 1.4, r), self.cm, R=R, kind=self.fk)
        self.crystals.append((*(b + d * length * 0.5), w * length))
        if sides:
            side = np.cross(d, [0.3, 0.2, 1.0])
            side = side / np.linalg.norm(side)
            side2 = np.cross(d, side)
            for k, (sd, at, sc) in enumerate(((side, 0.18, 0.5), (-side * 0.6 + side2 * 0.8, 0.34, 0.38))):
                d2 = d * 0.75 + sd * 0.6
                d2 = d2 / np.linalg.norm(d2)
                self.crystal(b + d * length * at, d2, length * sc, w * 0.62, sides=False)

    def build(self):
        m, ell, limb = self.m, self.m.ell, self.m.limb
        rng, rw = self.rng, self.rng_w
        wild = self.wild
        # ---- plinth: three worn steps, a ring of runes between the upper two
        tiers = [(27.0, 3.4, 3.6, STONE_D), (22.0, 3.2, 9.4, STONE_D), (17.5, 3.0, 14.4, STONE)]
        for R, ry, cy, mat in tiers:
            clip = None
            if wild and R == 27.0:  # a bite out of the front right rim
                clip = lambda q: ~((q[..., 0] > 0.50) & (q[..., 0] < 0.88) & (q[..., 2] > 0.15))
            ell(V(0, cy, 0), (R, ry, R * 0.97), mat, clip=clip)
            ell(V(0, cy - 1.6, 0), (R * 0.985, ry * 0.9, R * 0.955), STONE_D, clip=clip)
        # carved panels on the upper step's rim: dark inlays
        for k in range(14):
            a = k * math.tau / 14 + 0.2
            c = V(16.9 * math.sin(a), 13.4, 16.4 * math.cos(a))
            ell(c, (2.6, 1.5, 1.0), STONE, R=h.rot_y(a))
            if k % 2 == 0:
                limb(c + V(0, 0.2, 0.6) , c + V(0, 0.2, 0.6), 0.1, 0.1, CRACK)
        # runes on the tier between: little flat strokes along a ring
        self.runes = []
        for k in range(16):
            a = k * math.tau / 16 + 0.1
            rc = V(19.8 * math.sin(a), 11.1, 19.4 * math.cos(a))
            self.runes.append(rc)
            tang = V(math.cos(a), 0, -math.sin(a))
            limb(rc - tang * 0.9, rc + tang * 0.9, 0.42, 0.42, CRACK if wild else h.TEAL, kind="" if wild else "emit")
            if k % 3 == 0:
                limb(rc, rc + V(math.sin(a), 0, math.cos(a)) * 1.3, 0.38, 0.38, CRACK if wild else h.TEAL, kind="" if wild else "emit")
        # ---- the robe
        y = Y0 - 0.5
        top = Y0 + HEIGHT * 0.835
        while y <= top:
            f = (y - Y0) / HEIGHT
            rx, rz = robe_r(max(f, 0.0))
            ell(V(0, y, 0), (rx, 0.95, rz), STONE)
            y += 0.75
        # hem and a sash with gold
        for k in range(40):
            a = k * math.tau / 40
            ell(robe_pt(0.015, a, 0.35), (1.9, 0.85, 1.9), STONE_D if wild else STONE, R=h.rot_y(a))
        for k in range(36):
            a = k * math.tau / 36
            ell(robe_pt(0.045, a, 0.55), (1.0, 0.5, 0.55), GOLD_O, R=h.rot_y(a))
        for f0, th, mat in ((0.575, 0.7, GOLD_O), (0.595, 0.55, STONE)):
            for k in range(36):
                a = k * math.tau / 36
                ell(robe_pt(f0, a, 0.5), (1.15, th, 0.75), mat, R=h.rot_y(a))
        # long vertical folds
        for ang, f_end, rad in ((-1.05, 0.55, 1.1), (-0.62, 0.5, 1.25), (-0.22, 0.56, 1.35), (0.18, 0.54, 1.3), (0.58, 0.5, 1.2), (1.0, 0.55, 1.05), (2.5, 0.5, 1.4), (-2.5, 0.5, 1.4)):
            limb(robe_pt(0.0, ang, 0.9), robe_pt(f_end * 0.6, ang * 0.92, 0.55), rad, rad * 0.55, STONE)
        # bodice and bust, neck, collar
        ell(robe_pt(0.705, 0.0, -0.5) + V(0, 0, 0.6), (5.6, 3.0, 3.8), STONE)
        for s in (-1, 1):
            ell(V(s * 2.5, Y0 + HEIGHT * 0.705, 3.4), (2.6, 2.4, 2.0), STONE)
        limb(V(0, Y0 + HEIGHT * 0.78, 0), V(0, Y0 + HEIGHT * 0.86, 0.2), 2.3, 1.9, STONE)
        for k in range(14):  # gold collar
            a = k * math.tau / 14
            ell(V(3.9 * math.sin(a), Y0 + HEIGHT * 0.805, 3.3 * math.cos(a)), (1.0, 0.55, 0.8), GOLD_O, R=h.rot_y(a))
        # ---- head: veil over the hair, a circlet, long braids in front
        ell(HEAD, (5.6, 6.2, 5.4), STONE, kind="head")
        ell(HEAD + V(0, -1.3, 5.0), (0.9, 1.3, 0.9), STONE)  # nose
        ell(HEAD + V(0, 0.9, -3.6), (6.0, 6.0, 4.4), STONE)  # the veil / hair mass BEHIND the face (the face stays free in front)
        ell(HEAD + V(0, 5.0, -1.3), (5.2, 2.2, 4.2), STONE)
        for k in range(11):  # circlet of old gold
            a = -1.5 + k * 0.3
            ell(HEAD + V(5.7 * math.sin(a), 3.5, 5.4 * math.cos(a)), (0.9, 0.65, 0.75), GOLD_O, R=h.rot_y(a))
        ell(HEAD + V(0, 3.7, 6.0), (1.0, 1.1, 0.55), GOLD_O)
        # veil: flowing from the head down both shoulders and the back
        for sx in (-1, 1):
            pts = [HEAD + V(sx * 5.0, 1.0, -1.0), HEAD + V(sx * 7.0, -5.0, -0.5), SHOULDER["R" if sx < 0 else "L"] + V(sx * 1.6, 1.2, -1.0), V(sx * 10.0, Y0 + HEIGHT * 0.66, -1.5), V(sx * 9.8, Y0 + HEIGHT * 0.5, 0.5)]
            m.ribbon(pts, [2.0, 2.6, 3.0, 2.8, 2.0], 0.9, STONE, V(0, 0, 1), kind="")
        m.ribbon([HEAD + V(0, 3, -4), HEAD + V(0, -5, -5.2), V(0, Y0 + HEIGHT * 0.64, -4.8), V(0, Y0 + HEIGHT * 0.42, -4.4), V(0.4, Y0 + HEIGHT * 0.25, -5.0)],
                 [3.4, 4.2, 5.0, 5.0, 4.0], 1.0, STONE, V(0, 0, 1), kind="")
        for sx in (-1, 1):  # braids
            pts = [HEAD + V(sx * 4.6, -2.5, 3.0), V(sx * 4.2, Y0 + HEIGHT * 0.73, 4.4), V(sx * 3.7, Y0 + HEIGHT * 0.64, 5.4), V(sx * 4.4, Y0 + HEIGHT * 0.53, 5.2)]
            for i, (a, b) in enumerate(zip(pts, pts[1:])):
                limb(a, b, 1.1, 0.95, STONE)
            ell(pts[-1] + V(0, -0.8, 0), (1.3, 1.1, 1.0), GOLD_O)
        # ---- arms
        sh_r, sh_l = SHOULDER["R"], SHOULDER["L"]
        # her right (viewer's left) is raised, the palm opens under a big crystal
        el_r = V(-15.5, Y0 + HEIGHT * 0.66, 4.5)
        hand_r = V(-15.0, Y0 + HEIGHT * 0.865, 9.5)
        limb(sh_r + V(-1, -0.5, 0), el_r, 2.9, 2.5, STONE)
        limb(el_r, hand_r, 2.5, 1.8, STONE)
        for k in range(3):  # the sleeve hangs from the forearm
            t = 0.25 + k * 0.22
            p = el_r + (hand_r - el_r) * t
            ell(p + V(-1.8, -3.2 - 1.5 * (1 - t), -1.2), (3.4 - 0.7 * t, 3.2, 3.0), STONE, R=h.rot_x(0.2))
        for k in range(8):
            ell(el_r + V(-3.0 + k * 0.3, -6.4, -1.0 + 0.5 * (k % 3)), (1.5, 1.0, 1.2), STONE)
        for sx in (-1.0, 0.0, 1.0):  # opened fingers
            limb(hand_r + V(sx * 0.9, 0.5, 0.3), hand_r + V(sx * 1.7, 2.5, 0.9), 0.65, 0.45, STONE)
        ell(hand_r + V(0, 0.6, 0.3), (1.9, 0.9, 1.6), STONE)
        for k in range(8):  # armband
            a = k * math.tau / 8
            ell(el_r + (hand_r - el_r) * 0.18 + V(math.cos(a) * 2.2, 0, math.sin(a) * 2.2), (0.55, 0.55, 0.55), GOLD_O)
        # her left (viewer's right) hangs, the forearm reaches out with the palm up: broken off at the elbow while she is wild
        el_l = V(13.5, Y0 + HEIGHT * 0.575, 3.0)
        hand_l = V(16.5, Y0 + HEIGHT * 0.50, 13.5)
        limb(sh_l + V(1, -0.5, 0), el_l, 2.9, 2.5, STONE)
        for k in range(6):
            ell(el_l + V(0.3 + 0.2 * k, -2.0 - k * 0.8, -1.0 + 0.4 * (k % 3)), (1.7, 1.4, 1.5), STONE)  # sleeve fold
        if wild:
            ell(el_l + V(1.2, -0.2, 1.2), (2.2, 1.6, 2.0), STONE_D)  # the jagged break
            ell(el_l + V(2.2, -0.6, 1.8), (1.2, 0.9, 1.0), STONE)
            # the lost forearm and hand lie on the plinth
            fa, fb = V(9.0, 12.3, 16.5), V(15.0, 11.9, 15.5)
            limb(fa, fb, 1.9, 1.5, STONE)
            ell(fb + V(2.0, 0.0, 0.7), (2.0, 0.9, 1.7), STONE)
            for s in (-1, 0, 1):
                limb(fb + V(2.5, 0.2, s * 0.9), fb + V(4.4, 0.0, s * 1.2), 0.55, 0.4, STONE)
            for k in range(7):  # rubble
                a = 0.5 + k * 0.9
                ell(V(19.5 * math.sin(0.3 + k * 0.28), 10.9, 19.5 * math.cos(0.3 + k * 0.28)), (rw.uniform(0.9, 1.7), rw.uniform(0.6, 1.0), rw.uniform(0.8, 1.4)), STONE_D)
        else:
            limb(el_l, hand_l, 2.5, 1.8, STONE)
            ell(hand_l + V(0, 0.3, 0.8), (1.9, 0.9, 2.0), STONE)
            for s in (-1.0, 0.0, 1.0):
                limb(hand_l + V(s * 0.9, 0.3, 1.4), hand_l + V(s * 1.5, 0.5, 3.4), 0.6, 0.42, STONE)
            for k in range(8):
                a = k * math.tau / 8
                ell(el_l + (hand_l - el_l) * 0.2 + V(math.cos(a) * 2.2, math.sin(a) * 2.2, 0), (0.55, 0.55, 0.55), GOLD_O)
        # ---- crystals
        c = self.crystal
        # a radiant halo behind her head: a thin ring of old gold with crystal rays running out of it (her face stays free)
        hc = HEAD + V(0, 0.6, -8.0)
        for k in range(36):
            a = k * math.tau / 36
            ell(hc + V(10.8 * math.cos(a), 10.8 * math.sin(a), 0), (0.8, 0.8, 0.7), GOLD_O)
        for deg, L, w in ((-78, 11, 1.4), (-54, 14, 1.7), (-30, 17, 1.9), (-8, 21, 2.2), (14, 20, 2.1), (38, 16, 1.8), (62, 14, 1.6), (84, 11, 1.4)):
            a = math.radians(90 - deg)
            dirv = V(math.cos(a), math.sin(a), 0.0)
            c(hc + dirv * 10.8, dirv + V(0, 0, -0.08), L, w)
        # bursting from the shoulder blades
        for sx in (-1, 1):
            c(V(sx * 8.5, 70, -3.2), (sx * 1, 0.85, -0.5), 15, 1.9)
            c(V(sx * 6.0, 68, -3.6), (sx * 0.55, 1, -0.45), 17, 1.8)
            c(V(sx * 10.5, 66, -2.0), (sx * 1, 0.4, -0.3), 10, 1.5)
        # her heart crystal, half sunk into the bodice
        c(V(0, Y0 + HEIGHT * 0.69, 4.6), (0, 0.25, 1), 5.5, 1.5, sides=False)
        # the big crystal above her raised palm, a smaller one over the left palm once she is whole
        c(hand_r + V(0, 2.4, 0.3), (0.04, 1, 0.0), 14, 2.7)
        if not wild:
            c(hand_l + V(0, 2.2, 1.6), (0, 1, 0.1), 8.5, 1.8, sides=False)
        # a long scarf from the raised arm down to the plinth
        m.ribbon([el_r + V(-2, -1.5, 1), V(-22, Y0 + HEIGHT * 0.56, 4), V(-21, Y0 + HEIGHT * 0.36, 7), V(-18, Y0 + HEIGHT * 0.15, 9), V(-14, Y0 + 1.2, 10.5)],
                 [1.3, 1.7, 1.9, 1.7, 1.3], 0.6, STONE, V(0, 0, 1), kind="")
        # clusters pushing out of cracks in the plinth
        for a, n in ((-2.7, 2), (-1.9, 3), (-0.9, 2), (0.7, 2), (1.6, 3), (2.4, 2), (3.1, 2)):
            for j in range(n):
                aa = a + j * 0.16
                R = 23.5 + 1.8 * math.cos(j * 2.0)
                base = V(R * math.sin(aa), 5.6 + 0.4 * j, R * 0.96 * math.cos(aa))
                d = V(math.sin(aa) * 0.55 + (j - 0.5) * 0.2, 1.0, math.cos(aa) * 0.55)
                c(base, d, 7.0 + 3.2 * ((j * 7 + int(a * 3)) % 3), 1.4 + 0.2 * (j % 2), sides=(j == 0))
        for k in range(16):  # small shards scattered over the steps
            aa = rng.uniform(0, math.tau)
            rr = rng.uniform(16.5, 25.0)
            height = 6.0 if rr > 22 else (11.2 if rr > 17.5 else 15.5)
            sd = V(math.sin(aa) * 0.4 + rng.uniform(-0.3, 0.3), 1.0, math.cos(aa) * 0.4 + rng.uniform(-0.3, 0.3))
            c(V(rr * math.sin(aa), height, rr * 0.96 * math.cos(aa)), sd, rng.uniform(3.0, 5.2), rng.uniform(0.8, 1.15), sides=False)
        # ---- the growth (only while she is wild)
        if wild:
            self.growth()
        return m

    def growth(self):
        m, ell, limb, rw = self.m, self.m.ell, self.m.limb, self.rng_w
        # moss on the plinth's upper faces, creeping over the steps
        for R, cy, n in ((26.0, 6.0, 14), (21.0, 11.2, 12), (16.0, 16.4, 9)):
            for k in range(n):
                a = rw.uniform(0, math.tau)
                rr = R * rw.uniform(0.7, 0.98)
                ell(V(rr * math.sin(a), cy + rw.uniform(-0.3, 0.5), rr * 0.96 * math.cos(a)), (rw.uniform(2.0, 4.6), 0.8, rw.uniform(1.5, 3.2)), MOSS)
        # grass blades and a few tufts on the steps
        for k in range(40):
            a = rw.uniform(0, math.tau)
            rr = rw.uniform(12, 25)
            b = V(rr * math.sin(a), 6.0 + (5 if rr < 21 else 0) + (5 if rr < 16 else 0), rr * 0.96 * math.cos(a))
            limb(b, b + V(rw.uniform(-1.2, 1.2), rw.uniform(3.0, 6.0), rw.uniform(-0.8, 0.8)), 0.4, 0.15, MOSS)
        # roots crossing the steps and clutching the plinth
        for a0 in (-2.3, -0.4, 1.1, 2.6):
            pts = [V(30.0 * math.sin(a0), 1.2, 28.0 * math.cos(a0))]
            for rr, cy in ((25.0, 3.5), (20.0, 9.3), (15.0, 15.0)):
                aa = a0 + rw.uniform(-0.25, 0.25)
                pts.append(V(rr * math.sin(aa), cy + 2.4, rr * 0.96 * math.cos(aa)))
            for i, (p, q) in enumerate(zip(pts, pts[1:])):
                limb(p, q, 1.5 - 0.3 * i, 1.2 - 0.3 * i, ROOT_M)
        # ivy: spirals up the robe and over the shoulders, with leaves and dim buds
        for start, turns, f_end in ((2.3, 1.6, 0.66), (-0.8, 1.2, 0.5)):
            pts = []
            n = 26
            for i in range(n):
                f = 0.02 + (f_end - 0.02) * i / (n - 1)
                a = start + turns * math.tau * i / (n - 1)
                pts.append(robe_pt(f, a, 0.5))
            for i, (p, q) in enumerate(zip(pts, pts[1:])):
                limb(p, q, 0.55, 0.45, MOSS)
                if i % 2 == 0:
                    ell(q + V(0.5 * (-1) ** i, 0.3, 0.9), (1.3, 0.5, 0.9), MOSS, R=h.rot_x(0.5) @ h.rot_y(i * 0.8))
        # ivy over her left shoulder and down the sleeve, a curtain from the raised arm
        sh = SHOULDER["L"]
        prev = sh + V(1.5, 2.0, 0.5)
        for i in range(10):
            nxt = prev + V(0.7 + 0.2 * math.sin(i), -1.5, 0.35 * math.cos(i))
            limb(prev, nxt, 0.5, 0.42, MOSS)
            ell(nxt + V(0.4, 0.1, 0.8), (1.2, 0.5, 0.9), MOSS, R=h.rot_x(0.4))
            prev = nxt
        # moss caps on shoulders, head, circlet and the raised hand
        for p, r in ((SHOULDER["R"] + V(-1, 2.4, 0), (3.6, 1.0, 2.8)), (SHOULDER["L"] + V(1, 2.2, 0), (3.6, 1.0, 2.8)), (HEAD + V(0.5, 6.2, -1.0), (3.0, 0.9, 2.6)),
                     (V(-14.0, Y0 + HEIGHT * 0.66 + 2.6, 4.5), (2.0, 0.8, 1.6)), (V(5.5, Y0 + HEIGHT * 0.70 + 3, 1.0), (3.5, 0.9, 2.0)), (V(0, Y0 + HEIGHT * 0.25, 6.8), (2.5, 0.9, 1.8))):
            ell(p, r, MOSS)
        for k in range(5):  # moss patches low on the robe
            a = rw.uniform(-1.2, 1.2)
            f = rw.uniform(0.02, 0.2)
            ell(robe_pt(f, a, 0.4), (rw.uniform(1.8, 3.4), rw.uniform(1.0, 2.0), 1.0), MOSS, R=h.rot_y(a))
        # glowing buds and a violet shelf fungus
        for p in (robe_pt(0.30, 2.5, 0.9), robe_pt(0.44, 0.2, 1.0), robe_pt(0.12, -1.0, 1.0), V(-9.5, 70.0, 0.5), V(12.0, 11.5, 16.5)):
            ell(p, (0.65, 0.65, 0.65), h.TEAL, kind="emit")
        self.buds = [robe_pt(0.30, 2.5, 0.9), robe_pt(0.44, 0.2, 1.0), robe_pt(0.12, -1.0, 1.0), V(-9.5, 70.0, 0.5), V(12.0, 11.5, 16.5)]
        for a in (-0.9, 2.0):
            ell(V(19.8 * math.sin(a), 11.5, 19 * math.cos(a)), (2.4, 0.9, 1.7), h.VIOLET, R=h.rot_y(a))
            ell(V(19.8 * math.sin(a), 12.0, 19 * math.cos(a)), (1.8, 0.5, 1.2), h.VIOLET, R=h.rot_y(a), kind="emit")


# ------------------------------------------------------------------ pixels
def raster(prims):
    """h.render without blood, plus the kinds `facet` / `facet_emit` (hexagonal crystals: the normals of the ellipsoid chain snap to six flat faces)."""
    SS = h.SS
    Hs, Ws = FH * SS, FW1 * SS
    depth = np.full((Hs, Ws), -1e9)
    code = np.full((Hs, Ws), -1, dtype=np.int16)
    for p in prims:
        cx = FW1 / 2 + p.c[0]
        cy = GROUND - (p.c[1] * h.COSP - p.c[2] * h.SINP)
        rr = float(p.r.max()) + 0.4
        x0, x1 = max(0, int((cx - rr) * SS)), min(Ws, int((cx + rr) * SS) + 1)
        y0, y1 = max(0, int((cy - rr) * SS)), min(Hs, int((cy + rr) * SS) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        a = (np.arange(x0, x1) + 0.5) / SS - FW1 / 2
        b = GROUND - (np.arange(y0, y1) + 0.5) / SS
        A, B = np.meshgrid(a, b)
        o = A[..., None] * h.XHAT + B[..., None] * h.UHAT
        M = np.diag(1.0 / p.r) @ p.R.T
        q0 = (o - p.c) @ M.T
        qd = M @ h.WHAT
        aa = qd @ qd
        bb = q0 @ qd
        cc = (q0 * q0).sum(-1) - 1.0
        disc = bb * bb - aa * cc
        ok = disc >= 0
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
        if p.kind.startswith("facet"):
            ax, e1, e2 = p.R[:, 1], p.R[:, 0], p.R[:, 2]
            na = n @ ax
            nr = n - na[..., None] * ax
            th = np.arctan2(nr @ e2, nr @ e1)
            ths = (np.floor(th / SNAP) + 0.5) * SNAP
            rad = np.sqrt(np.maximum(1.0 - na * na, 0.0))
            n = rad[..., None] * (np.cos(ths)[..., None] * e1 + np.sin(ths)[..., None] * e2) + na[..., None] * ax
            n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        lam = 0.78 * (n @ h.LIGHT) + 0.22 * (0.5 + 0.5 * n[..., 1]) - 0.06
        mat = np.full(t.shape, p.mat, dtype=np.int16)
        band = h.shade_band(lam, p.kind, p.mat).astype(np.int16)
        if p.kind == "head":
            mat, band = paint_face(q, mat, band)
        elif p.kind == "emit":
            band = np.maximum(band, 2)
        elif p.kind == "facet_emit":
            band = np.maximum(band, 1)
        sub[ok] = t[ok]
        code[y0:y1, x0:x1][ok] = (mat * 4 + band)[ok]
    return depth, code


def render(model):
    return raster(model.transform(0.0, 0.0))


def pixels(depth, code):
    rows = h.to_pixels(depth, code)
    for y in range(FH):  # the standard 8 px shadow of to_pixels is replaced by the plinth's
        for x in range(FW1):
            if rows[y][x] == (0, 0, 0, 70):
                rows[y][x] = CLEAR
    return rows


def shade(rows):
    for y in range(FH):
        for x in range(FW1):
            if rows[y][x][3] == 0:
                ex, ey = (x + 0.5 - FW1 / 2) / 26.5, (y + 0.5 - (GROUND + 1.5)) / 10.0
                if ex * ex + ey * ey <= 1.0:
                    rows[y][x] = (0, 0, 0, 78)
    return rows


def project(p):
    return (FW1 / 2 + p[0] * SC, GROUND - (p[1] * PITCH_COS - p[2] * PITCH_SIN) * SC)


def add_cracks(rows, seed=4):
    """Dark one pixel cracks with a lit lip, running over the stone of the dormant statue (random walks with a downward pull)."""
    rng = np.random.default_rng(seed)
    stone = {tuple(c) for mat in (STONE, STONE_D) for c in h.RAMPS[mat]}
    arr = [[tuple(c) for c in row] for row in rows]
    dark = h.RAMPS[CRACK][1]
    lip = h.RAMPS[STONE][3]
    starts = [(FW1 / 2 + 3, GROUND - 58), (FW1 / 2 - 6, GROUND - 38), (FW1 / 2 + 9, GROUND - 24), (FW1 / 2 - 2, GROUND - 50), (FW1 / 2 + 20, GROUND - 6), (FW1 / 2 - 20, GROUND - 5),
              (FW1 / 2 + 1, GROUND - 30), (FW1 / 2 - 11, GROUND - 16), (FW1 / 2 + 13, GROUND - 14), (FW1 / 2 + 4, GROUND - 64), (FW1 / 2 - 24, GROUND - 3)]
    for sx, sy in starts:
        x, y = int(sx), int(sy)
        length = int(rng.integers(8, 20))
        for _ in range(length):
            if 0 <= y < FH and 0 <= x < FW1 and arr[y][x] in stone:
                arr[y][x] = dark
                if x + 1 < FW1 and arr[y][x + 1] in stone:
                    arr[y][x + 1] = lip if rng.random() < 0.6 else arr[y][x + 1]
            step = rng.random()
            y += 1 if step < 0.62 else 0
            x += int(rng.choice([-1, 0, 1])) if step >= 0.25 else 0
    return arr


def glow_sheet(rows, mats, halo=True, body=None):
    cols = {tuple(c) for mat in mats for c in h.RAMPS[mat]}
    core = np.zeros((FH, FW1), bool)
    out = [[CLEAR] * FW1 for _ in range(FH)]
    for y in range(FH):
        for x in range(FW1):
            if tuple(rows[y][x]) in cols:
                out[y][x] = tuple(rows[y][x])
                core[y, x] = True
    if halo:  # a dithered halo round every lit pixel (the trees do the same): never a smooth gradient
        near = np.zeros((FH, FW1))
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                d = math.hypot(dx, dy)
                if d <= 3.2:
                    shifted = np.roll(np.roll(core.astype(float), dy, 0), dx, 1)
                    near = np.maximum(near, shifted * (1.0 - d / 3.4))
        bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
        for y in range(FH):
            for x in range(FW1):
                if not core[y, x] and not (body is not None and body[y, x]) and near[y, x] > bayer[y % 4, x % 4] * 0.9 + 0.05:
                    a = int(70 + 110 * near[y, x])
                    out[y][x] = (110, 200, 235, min(a, 190)) if (x * 3 + y) % 5 else (170, 140, 255, min(a, 190))
    return out


def wave_map(wild_rows, clean_rows, sources, vines):
    """R = when the awakening reaches a pixel (0 = at once). Distance from the nearest crystal (each starts a little later than the one before), a ragged edge,
    and the growth withers a little ahead of the light."""
    rng = np.random.default_rng(3)
    noise = rng.random((FH, FW1))
    for _ in range(3):  # smooth it into clumps
        noise = (noise + np.roll(noise, 1, 0) + np.roll(noise, 1, 1) + np.roll(noise, -1, 0) + np.roll(noise, -1, 1)) / 5.0
    noise = (noise - noise.min()) / (noise.max() - noise.min())
    t = np.full((FH, FW1), 1e9)
    ys, xs = np.mgrid[0:FH, 0:FW1]
    for (sx, sy, delay) in sources:
        d = np.hypot((xs - sx) * 1.0, (ys - sy) * 1.25)
        t = np.minimum(t, delay + d)
    t = t / t[wild_alpha(wild_rows) | wild_alpha(clean_rows)].max() if True else t
    t = np.clip(t, 0, 1)
    t = t * 0.86 + noise * 0.12
    veg = np.zeros((FH, FW1), bool)
    for y in range(FH):
        for x in range(FW1):
            if tuple(wild_rows[y][x]) in vines:
                veg[y, x] = True
    t = np.where(veg, t - 0.1, t)
    return np.clip(t, 0.0, 1.0)


def wild_alpha(rows):
    return np.array([[c[3] > 0 for c in row] for row in rows])


def to_rgba(rows):
    return [[tuple(c) for c in row] for row in rows]


def main():
    out_dir = ROOT / "props" / "waystone"
    out_dir.mkdir(parents=True, exist_ok=True)
    print("rendering the dormant statue ...")
    STATE["eyes_lit"] = False
    wild = Maker(True)
    wm = wild.build()
    depth, code = render(wm)
    wild_rows = shade(add_cracks(pixels(depth, code)))
    print("rendering the awakened statue ...")
    STATE["eyes_lit"] = True
    clean = Maker(False)
    cm = clean.build()
    depth, code = render(cm)
    clean_rows = shade(pixels(depth, code))
    body_mask = np.array([[c[3] >= 200 for c in row] for row in clean_rows])  # the halo never lies over the statue itself (it hid her face)
    glow_rows = glow_sheet(clean_rows, GLOW_MATS, True, body_mask)
    dim_cols = {tuple(c) for c in (h.RAMPS[CRYST_D][3], h.RAMPS[CRYST_D][2])} | {tuple(c) for c in h.RAMPS[h.TEAL]} | {tuple(h.RAMPS[h.VIOLET][3]), tuple(h.RAMPS[h.VIOLET][2])}
    dim_rows = [[tuple(c) if tuple(c) in dim_cols else CLEAR for c in row] for row in wild_rows]
    sources = []
    px = [project(p[:3]) for p in clean.crystals]
    order = sorted(range(len(px)), key=lambda i: -clean.crystals[i][3])
    for rank, i in enumerate(order):
        sources.append((px[i][0], px[i][1], min(rank, 12) * 0.012))
    vines = {tuple(c) for mat in (MOSS, ROOT_M) for c in h.RAMPS[mat]}
    wv = wave_map(wild_rows, clean_rows, sources, vines)
    wave_rows = [[(int(wv[y, x] * 255), 0, 0, 255 if (wild_rows[y][x][3] or clean_rows[y][x][3]) else 0) for x in range(FW1)] for y in range(FH)]
    write_png(out_dir / "statue_wild.png", FW1, FH, wild_rows)
    write_png(out_dir / "statue_clean.png", FW1, FH, clean_rows)
    write_png(out_dir / "statue_glow.png", FW1, FH, glow_rows)
    write_png(out_dir / "statue_dim.png", FW1, FH, dim_rows)
    write_png(out_dir / "statue_wave.png", FW1, FH, wave_rows)
    info = {
        "frame": [FW1, FH],
        "ground_row": GROUND,
        "crystals": [[round(p[0], 1), round(p[1], 1), round(w[3], 1)] for p, w in zip(px, clean.crystals)],
        "runes": [[round(project(r)[0], 1), round(project(r)[1], 1)] for r in clean.runes],
        "buds": [[round(project(b)[0], 1), round(project(b)[1], 1)] for b in wild.buds],
        "heart": [round(project(V(0, Y0 + HEIGHT * 0.69, 4.6))[0], 1), round(project(V(0, Y0 + HEIGHT * 0.69, 4.6))[1], 1)],
        "palm": [round(project(V(-14.0, Y0 + HEIGHT * 0.865 + 7.5, 9.5))[0], 1), round(project(V(-14.0, Y0 + HEIGHT * 0.865 + 7.5, 9.5))[1], 1)],
        "eyes": [round(project(HEAD + V(0, 0.2, 4.6))[0], 1), round(project(HEAD + V(0, 0.2, 4.6))[1], 1)],
    }
    (ROOT.parent / "data").mkdir(exist_ok=True)
    (ROOT.parent / "data" / "waystone_art.json").write_text(json.dumps(info, indent=1))
    if len(sys.argv) > 1:
        preview(wild_rows, clean_rows, glow_rows, wave_rows, pathlib.Path(sys.argv[1]))
    print("waystone art written to", out_dir)


def preview(wild_rows, clean_rows, glow_rows, wave_rows, path):
    sc = 4
    bg = (36, 52, 60)
    sheets = [wild_rows, clean_rows, glow_rows, wave_rows]
    W = FW1 * len(sheets) * sc
    big = []
    for y in range(FH):
        line = []
        for si, sheet in enumerate(sheets):
            for x in range(FW1):
                c = sheet[y][x]
                a = c[3] / 255.0
                if si == 3:
                    col = (int(c[0]),) * 3 if c[3] else bg
                elif si == 2:
                    col = tuple(min(255, int(bg[i] * 0.4 + c[i] * a)) for i in range(3))
                else:
                    col = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3))
                line += [col + (255,)] * sc
        big += [line] * sc
    write_png(path, W, FH * sc, big)


if __name__ == "__main__":
    main()
