"""The Shadowspore title logo (docs/logo_title_concept.md): final layered art for the idle animation.

SHADOW over SPORE, thick block letters with depth (extruded up and to the right, lit from the top left),
the void of SHADOW eats into the living green of SPORE, small plants and one big spore flower grow on the
top faces of SPORE, a floating island lit by one of the town's lamp posts lives inside the life O ("light
is land") and a watching void eye inside the shadow O.

Writes assets/ui/logo/*.png and data/title_logo_layout.json (+ docs/img/title_logo_preview.png).
Pure numpy + PIL, deterministic.   Run: py -3 tools/art_title_logo.py
Layers (all the same size, same origin): base, plants (+ sway mask), glow cores (+ pulse map), three halos
(void, life, lamp), and two orb sheets (8 frames each, drawn under the base layer inside the O holes).
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_A = ROOT / "assets" / "ui" / "logo"
OUT_D = ROOT / "data"
OUT_I = ROOT / "docs" / "img"

CW, CH = 440, 240          # canvas of the logo
SS = 4
LH = 54                    # letter height
T = 13                     # stroke
TO = 14                    # stroke of the O rings at the sides
TOY = 12                   # ... and at top and bottom
K = 1.22
GAP = 3                    # between letters
ROWGAP = 5                 # between the rows (filled by the top faces of SPORE)
D = 5                      # depth of the blocks (extruded up and to the right)
FRAMES = 8
rng = np.random.default_rng(31)


def hexc(s):
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


BARK0 = [hexc(c) for c in ("040208", "0e0919", "1a1030", "221740", "34185e")]   # SHADOW: black void flesh (the shadow creatures' ramp)
BARK1 = [hexc(c) for c in ("1a1322", "34283c", "55435a", "85697a", "b09690")]   # SPORE: the trees' and the signpost's mauve wood
VOID = [hexc(c) for c in ("07040d", "0e0919", "1a1030", "221740")]
INK = hexc("0b1620")                                                            # the ink of trees and rocks: a very dark teal
MOSS = [hexc(c) for c in ("22483c", "2f624e", "3e7d56", "55985f", "74b268", "a8dc8c")]
TEAL = [hexc(c) for c in ("1a4a52", "2f8a8c", "3cc0c6", "6ae0d2", "d0fff8")]
GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
EARTH = [hexc(c) for c in ("1e1626", "372a40", "574560", "7d6a86")]
IRON = [hexc(c) for c in ("3f3043", "69505e", "977a80", "8c8bb8")]              # the lamp post's iron and stones
STONE = [hexc(c) for c in ("2e2a52", "47436f", "665f94", "8a83b8", "d0cbec")]   # the rocks
VEIN_V, VEIN_V2 = hexc("8a4dff"), hexc("b06bff")
MAGENTA, CORE, RIM = hexc("ff4fd8"), hexc("ecd2ff"), hexc("5a36b8")
PURPLE_EDGE = hexc("34185e")
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0
K_VOID, K_MAGENTA, K_LIFE, K_BERRY, K_SHROOM, K_CRACK, K_BLOOM = range(7)


def bayer(shape):
    return np.tile(BAYER, (shape[0] // 4 + 1, shape[1] // 4 + 1))[:shape[0], :shape[1]]


def inb(x, y):
    return 0 <= x < CW and 0 <= y < CH


def smooth1(a, k=(0.25, 0.5, 0.25)):
    return np.convolve(a, k, mode="same")


# ---------------------------------------------------------------- letters
def glyph(ch, w, h=LH, t=T):
    """face mask and the solid used for the extrusion (an O is extruded as a full disc, so its hole stays open)."""
    im = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(im)

    def rect(x0, y0, x1, y1):
        d.rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], fill=255)

    def line(x0, y0, x1, y1, wd):
        d.line([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=255, width=int(wd * SS))

    m = h / 2
    mb = h * 0.6
    if ch == "H":
        rect(0, 0, t, h); rect(w - t, 0, w, h); rect(0, m - t / 2, w, m + t / 2)
    elif ch == "E":
        rect(0, 0, t, h); rect(0, 0, w, t); rect(0, h - t, w, h); rect(0, m - t / 2, w * 0.86, m + t / 2)
    elif ch == "P":
        rect(0, 0, t, h); rect(0, 0, w, t * 0.78); rect(0, mb - t * 0.34, w, mb + t * 0.34); rect(w - t * 0.82, 0, w, mb + t * 0.34)
    elif ch == "R":
        bw = w - t * 0.35
        rect(0, 0, t, h); rect(0, 0, bw, t * 0.78); rect(0, mb - t * 0.36, bw, mb + t * 0.36); rect(bw - t * 0.82, 0, bw, mb + t * 0.36)
        line(w * 0.45, mb + t * 0.1, w - t * 0.5, h + 3, t * 0.95)
    elif ch == "D":
        d.rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=int(h * 0.42 * SS), fill=255, corners=(False, True, True, False))
        d.rounded_rectangle([t * SS, t * SS, (w - t) * SS - 1, (h - t) * SS - 1], radius=int(h * 0.2 * SS), fill=0, corners=(False, True, True, False))
    elif ch == "S":
        rx, ry = (w - t) / 2, (h - t) / 4
        y1, y2 = t / 2 + ry, h - t / 2 - ry
        pts = [(w / 2 + rx * np.cos(a), y1 + ry * np.sin(a)) for a in np.radians(np.linspace(-25, -270, 26))]
        pts += [(w / 2 + rx * np.cos(a), y2 + ry * np.sin(a)) for a in np.radians(np.linspace(-90, 155, 26))]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 0.95)
    elif ch == "A":
        line(w * 0.1, h + 2, w * 0.38, -1, t * 1.1); line(w * 0.9, h + 2, w * 0.62, -1, t * 1.1)
        rect(w * 0.3, 0, w * 0.7, t); rect(w * 0.18, h * 0.6, w * 0.82, h * 0.6 + t * 0.85)
    elif ch == "W":
        pts = [(t * 0.45, -1), (w * 0.27, h), (w * 0.5, h * 0.26), (w * 0.73, h), (w - t * 0.45, -1)]
        for a, b in zip(pts, pts[1:]):
            line(a[0], a[1], b[0], b[1], t * 1.0)
    elif ch == "O":
        d.ellipse([0, 0, w * SS - 1, h * SS - 1], fill=255)
        d.ellipse([t * SS, TOY * SS, (w - t) * SS - 1, (h - TOY) * SS - 1], fill=0)
    im = im.filter(ImageFilter.GaussianBlur(SS * 1.15))
    im = im.resize((w, h), Image.BOX)
    face = np.array(im) > 128
    solid = face
    if ch == "O":
        disc = Image.new("L", (w * SS, h * SS), 0)
        ImageDraw.Draw(disc).ellipse([0, 0, w * SS - 1, h * SS - 1], fill=255)
        solid = np.array(disc.resize((w, h), Image.BOX)) > 128
    return face, solid


def glyph_shade(g):
    pad = 8
    a = np.pad(g, pad)
    im = Image.fromarray((a * 255).astype(np.uint8))
    hf = (np.array(im.filter(ImageFilter.GaussianBlur(1.7)), np.float32) * 0.6 +
          np.array(im.filter(ImageFilter.GaussianBlur(4.5)), np.float32) * 0.4) / 255.0
    gy, gx = np.gradient(hf)
    nx, ny = -gx * 5.0, -gy * 5.0
    nl = np.sqrt(nx * nx + ny * ny + 1.0)
    sh = (nx * -0.55 + ny * -0.62 + 0.56) / nl
    return np.clip(0.02 + sh * 0.92, 0, 1)[pad:-pad, pad:-pad]


WIDTHS = dict(S=34, H=32, A=36, D=32, W=57, P=34, R=34, E=28)
ROW0, ROW1 = "SHADOW", "SPORE"


def wid(ch):
    return LH - 2 if ch == "O" else int(round(WIDTHS[ch] * K))


def row_positions(word, start):
    xs, x = [], start
    for ch in word:
        xs.append(x)
        x += wid(ch) + GAP
    return xs


r0 = row_positions(ROW0, 0)
o0 = r0[ROW0.index("O")]
pre1 = sum(wid(c) + GAP for c in ROW1[:ROW1.index("O")])
r1 = row_positions(ROW1, o0 - pre1)
total = max(r0[-1] + wid(ROW0[-1]), r1[-1] + wid(ROW1[-1]))
X0 = (CW - total) // 2 - 4
Y0 = 70
Y1 = Y0 + LH + ROWGAP
GROUND_Y = Y1 + LH

M0 = np.zeros((CH, CW), bool); M1 = np.zeros((CH, CW), bool)
S0 = np.zeros((CH, CW), bool); S1 = np.zeros((CH, CW), bool)
shade = np.zeros((CH, CW), np.float32)
orbs = []        # dict(cx, cy, rx, ry, row)
letters = []
for row, (word, xs, y) in enumerate(((ROW0, r0, Y0), (ROW1, r1, Y1))):
    Mr, Sr = (M0, S0) if row == 0 else (M1, S1)
    for ch, x in zip(word, xs):
        w = wid(ch)
        face, solid = glyph(ch, w, LH, TO if ch == "O" else T)
        gx0 = X0 + x
        Mr[y:y + LH, gx0:gx0 + w] |= face
        Sr[y:y + LH, gx0:gx0 + w] |= solid
        sh = glyph_shade(face)
        shade[y:y + LH, gx0:gx0 + w][face] = sh[face]
        letters.append(dict(ch=ch, x=gx0, y=y, w=w, row=row, face=face, solid=solid))
        if ch == "O":
            orbs.append(dict(cx=gx0 + w / 2 - 0.5, cy=y + LH / 2 - 0.5, rx=(w - 2 * TO) / 2, ry=(LH - 2 * TOY) / 2, row=row))

# ---------------------------------------------------------------- depth: extrusion up and to the right
def extrude(solid):
    E = np.zeros_like(solid); kmap = np.zeros(solid.shape, np.int8)
    for k in range(1, D + 1):
        s = np.roll(np.roll(solid, k, 1), -k, 0)
        kmap[s & ~E] = k
        E |= s
    return E & ~solid, kmap


E0, k0 = extrude(S0)
E1, k1 = extrude(S1)
face_any = M0 | M1
E1 &= ~M0
E0 &= ~(M1 | E1)
E0 &= ~M0
E0 &= ~M1
def tear():
    """SHADOW is flesh, not stone: bite ragged notches into its edge, like the creatures' torn bodies."""
    global M0, E0
    u = M0 | E0
    open_nb = np.zeros_like(u)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        open_nb |= ~np.roll(np.roll(u, dy, 0), dx, 1)
    boundary = u & open_nb
    rem = boundary & (rng.random(u.shape) < 0.06)
    ys, xs = np.nonzero(boundary)
    yy, xx = np.ogrid[:CH, :CW]
    for i in rng.choice(len(ys), 26, replace=False):
        r = int(rng.integers(1, 3))
        rem |= ((yy - ys[i]) ** 2 + (xx - xs[i]) ** 2 <= r * r) & u
    M0 = M0 & ~rem
    E0 = E0 & ~rem


tear()
U0 = M0 | E0
U1 = M1 | E1
U = U0 | U1


def classify(E, solid):
    top_c = np.zeros_like(E); right_c = np.zeros_like(E)
    for j in range(1, D + 1):
        top_c |= np.roll(solid, -j, 0)
        right_c |= np.roll(solid, j, 1)
    is_top = E & top_c
    return is_top, E & ~is_top


top0, side0 = classify(E0, S0)
top1, side1 = classify(E1, S1)

# which letter does a pixel belong to (faces first, then each block's depth): the seams between letters are drawn from this
lid = np.full((CH, CW), -1, np.int16)
for k_, l_ in enumerate(letters):
    sl_ = (slice(l_["y"], l_["y"] + LH), slice(l_["x"], l_["x"] + l_["w"]))
    view_ = lid[sl_]
    view_[l_["face"]] = k_
for k_, l_ in enumerate(letters):
    full_ = np.zeros((CH, CW), bool)
    full_[l_["y"]:l_["y"] + LH, l_["x"]:l_["x"] + l_["w"]] = l_["solid"]
    e_, _ = extrude(full_)
    lid[e_ & (lid < 0)] = k_

base = np.zeros((CH, CW, 4), np.float32)       # rgb 0..255, alpha 0..1
pl = np.zeros((CH, CW, 4), np.float32)         # plants layer
psway = np.zeros((CH, CW, 2), np.float32)      # weight, phase
core = np.zeros((CH, CW, 4), np.float32)       # glow cores
cmap = np.zeros((CH, CW, 3), np.float32)       # phase, kind, 1
halos = {"void": [], "life": [], "lamp": []}
eaten = np.zeros((CH, CW), bool)
vein_px = set()
bd = bayer((CH, CW))


def bpx(x, y, c, a=1.0):
    if inb(x, y):
        base[y, x, :3] = c; base[y, x, 3] = a


def ppx(x, y, c, weight, phase):
    if inb(x, y):
        pl[y, x, :3] = c; pl[y, x, 3] = 1.0
        psway[y, x] = (np.clip(weight, 0, 1), phase)


def emit(x, y, c, kind, halo=0.6, under=0.4):
    """a glowing pixel: dark in the base, alive in the glow layer, a halo in its group."""
    if not inb(x, y):
        return
    if base[y, x, 3] > 0:
        base[y, x, :3] = c * under
    core[y, x, :3] = c; core[y, x, 3] = 1.0
    cmap[y, x] = (float(np.clip((x - X0) / total, 0, 1)), float(kind), 1.0)
    group = "void" if kind in (K_VOID, K_MAGENTA) or (kind == K_CRACK and x < X0 + total * 0.5) else "life"
    halos[group].append((x, y, c, halo))


def halo(x, y, c, s, group):
    if inb(x, y):
        halos[group].append((x, y, c, s))


# ---------------------------------------------------------------- the faces: flesh and wood
coarse = rng.random((CH // 9 + 2, CW // 2 + 2))
streak = np.kron(coarse, np.ones((9, 2)))[:CH, :CW]
s_all = np.clip(shade + (streak - 0.5) * 0.34 + (rng.random((CH, CW)) - 0.5) * 0.05, 0, 1)
# SHADOW: near-black flesh, mottled, its light is only a cold violet rim
mott = np.array(Image.fromarray((rng.random((CH // 4 + 2, CW // 4 + 2)) * 255).astype(np.uint8))
                .resize((CW + 8, CH + 8), Image.BICUBIC), np.float32)[:CH, :CW] / 255.0
fl = np.clip(shade * 0.9 + (mott - 0.5) * 0.5, 0, 1)
fidx = np.clip(np.floor(1.0 + fl * 2.4 + (bd - 0.5) * 0.7), 0, 3).astype(int)
base[M0, :3] = np.stack(BARK0)[fidx][M0]
base[M0, 3] = 1.0
# SPORE: the trees' wood, in chunks like a trunk, with grain and flecks
n1 = len(BARK1)
idx = np.clip(np.floor(s_all * (n1 - 1) + bd * 0.55 + 0.22).astype(int), 0, n1 - 1)
base[M1, :3] = np.stack(BARK1)[idx][M1]
base[M1, 3] = 1.0
for ltr in letters:
    if ltr["row"] != 1:
        continue
    off = int(rng.integers(3, 9))
    for yk in range(ltr["y"] + off, ltr["y"] + LH - 3, int(rng.integers(13, 19))):
        for xk in range(ltr["x"], ltr["x"] + ltr["w"]):
            if M1[yk, xk] and rng.random() < 0.75:
                base[yk, xk, :3] = BARK1[0]
                if M1[yk + 1, xk]:
                    base[yk + 1, xk, :3] = BARK1[3] if rng.random() < 0.8 else BARK1[2]
for y, x in zip(*np.nonzero(M1)):
    r_ = rng.random()
    if r_ < 0.035:
        base[y, x, :3] = BARK1[0]
    elif r_ < 0.06:
        base[y, x, :3] = BARK1[4]

# moss across the faces of SPORE
blob = np.array(Image.fromarray((rng.random((CH // 7 + 2, CW // 7 + 2)) * 255).astype(np.uint8))
                .resize((CW + 14, CH + 14), Image.BICUBIC), np.float32)[:CH, :CW] / 255.0
blob = blob + np.clip(1.0 - (np.arange(CH)[:, None] - Y1) / (LH * 0.9), 0, 1) * 0.22
moss_sel = M1 & (blob > 0.70)
midx = np.clip(np.floor(s_all * 3.2 + bd * 0.7 + 0.5).astype(int), 0, 4)
base[moss_sel, :3] = np.stack(MOSS)[midx][moss_sel]
me_top = moss_sel & ~np.roll(moss_sel, 1, 0)
me_left = moss_sel & ~np.roll(moss_sel, 1, 1)
me_bot = moss_sel & ~np.roll(moss_sel, -1, 0)
base[me_top | me_left, :3] = MOSS[4]
base[me_bot, :3] = MOSS[0]
for _ in range(110):
    px, py = rng.integers(X0, X0 + total), rng.integers(Y1, Y1 + LH)
    if moss_sel[py, px] and not me_bot[py, px]:
        bpx(px, py, MOSS[5] if rng.random() < 0.3 else MOSS[4])
        if inb(px + 1, py + 1) and moss_sel[py + 1, px + 1]:
            bpx(px + 1, py + 1, MOSS[3])
for _ in range(240):
    px, py = rng.integers(X0, X0 + total), rng.integers(Y0, Y1 + LH)
    if face_any[py, px] and face_any[py, min(px + 2, CW - 1)] and not moss_sel[py, px]:
        r_ = BARK0 if M0[py, px] else BARK1
        bpx(px, py, r_[0]); bpx(px + 1, py, r_[1])

# ---------------------------------------------------------------- the faces: the block's top and right side
def paint_ext(E, kmap, is_top, is_side, ramp, green, flesh=False):
    for y, x in zip(*np.nonzero(is_top)):
        k = int(kmap[y, x])
        if flesh:
            c = ramp[3 + int(bd[y, x] < 0.25)]
        elif green:
            # a mossy top: darker at the front lip, lit towards the back edge, a few bark specks
            lvl = 2 + int(k >= 3) + int(k >= 5) - int(k == 1) + int(bd[y, x] < 0.3)
            c = MOSS[int(np.clip(lvl, 1, 5))]
            if rng.random() < 0.06:
                c = BARK1[2]
        else:
            c = ramp[int(np.clip(2 + (bd[y, x] < 0.5), 2, 4))]
        base[y, x, :3] = c; base[y, x, 3] = 1.0
    for y, x in zip(*np.nonzero(is_side)):
        k = int(kmap[y, x])
        if flesh:
            tone = 2 if k <= 2 else 1
            base[y, x, :3] = ramp[tone] * (0.92 + 0.12 * ((x + y) % 2))
        else:
            # the side of the block is in shade: the wood a tone down, a step darker with every pixel of depth, vertical grain, a little moss below the top
            tone = [2, 2, 1, 1, 0][min(k, 5) - 1]
            if bd[y, x] < 0.22 and tone > 0:
                tone -= 1
            elif bd[y, x] > 0.86 and tone < 2:
                tone += 1
            c = ramp[tone].copy()
            if (x + k) % 5 == 0:
                c *= 0.82
            if (y % 7) == 3 and bd[y, x] > 0.4:
                c *= 0.88
            if y > 0 and is_top[y - 1, x] and rng.random() < 0.45:
                c = MOSS[1] if k > 2 else MOSS[2]
            base[y, x, :3] = c
        base[y, x, 3] = 1.0


paint_ext(E0, k0, top0, side0, BARK0, False, flesh=True)
paint_ext(E1, k1, top1, side1, BARK1, True)
# SHADOW throws a dark band onto the green top faces under it
under = top1 & np.roll(M0, 1, 0)
under |= top1 & np.roll(np.roll(M0, 1, 0), 1, 0)
base[under, :3] = base[under, :3] * 0.42

# outlines: ink round the wood, a dim violet line round the flesh
def dilate(m):
    d = np.zeros_like(m)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        d |= np.roll(np.roll(m, dy, 0), dx, 1)
    return d


outline = dilate(U) & ~U
out0 = outline & dilate(U0) & ~dilate(U1)
for y, x in zip(*np.nonzero(outline)):
    base[y, x, :3] = RIM * 0.8 if out0[y, x] else INK
    base[y, x, 3] = 1.0
# the creatures' light: cold violet rim lines along the lit edges of every plane
top_rim = (M0 & np.roll(E0, 1, 0)) | (E0 & ~np.roll(U0, 1, 0))
left_rim = (M0 | E0) & ~np.roll(U0, 1, 1)
base[top_rim, :3] = RIM
base[left_rim & (rng.random((CH, CW)) < 0.85), :3] = RIM
base[(top_rim & (rng.random((CH, CW)) < 0.25)), :3] = VEIN_V
inner2 = (np.roll(top_rim, 1, 0) | np.roll(left_rim, 1, 1)) & (M0 | E0) & ~(top_rim | left_rim)
base[inner2, :3] = PURPLE_EDGE
dark_edge0 = ((M0 | E0) & ~np.roll(U0, -1, 0)) | ((M0 | E0) & ~np.roll(U0, -1, 1))
base[dark_edge0, :3] = BARK0[0]
# wood: a pale lit rim on the top and left edges, a dark foot
rimf1 = ((M1 & ~np.roll(M1, 1, 0)) | (M1 & ~np.roll(M1, 1, 1))) & (rng.random((CH, CW)) < 0.85)
base[rimf1 & M1 & ~moss_sel, :3] = BARK1[4]
dark_edge1 = (M1 & ~np.roll(M1, -1, 0)) | (M1 & ~np.roll(M1, -1, 1))
base[dark_edge1, :3] *= 0.62
edge_ext1 = M1 & (np.roll(E1, 1, 0) | np.roll(E1, -1, 1))
base[edge_ext1, :3] *= 0.8
face_any = M0 | M1

row_of = np.where(lid < 0, -1, (lid >= len(ROW0)).astype(np.int16))
sep = np.zeros((CH, CW), bool)
for dy_, dx_ in ((0, 1), (0, -1), (1, 0), (-1, 0)):
    nb_ = np.roll(np.roll(lid, dy_, 0), dx_, 1)
    nbr_ = np.roll(np.roll(row_of, dy_, 0), dx_, 1)
    sep |= (lid >= 0) & (nb_ >= 0) & (nb_ != lid) & (nbr_ == row_of) & ((E0 | E1) & ~(M0 | M1))
for y, x in zip(*np.nonzero(sep & E0)):
    base[y, x, :3] = RIM * 0.9
for y, x in zip(*np.nonzero(sep & E1 & ~E0)):
    base[y, x, :3] = INK

# run lengths of the SHADOW block from its top
run_top = np.zeros((CH, CW), np.int16)
for y in range(1, CH):
    run_top[y] = np.where(U0[y] & ~U1[y], run_top[y - 1] + 1, 0)
run_top[0] = U0[0].astype(np.int16)
run_bot1 = np.zeros((CH, CW), np.int16)
for y in range(CH - 2, -1, -1):
    run_bot1[y] = np.where(M1[y], run_bot1[y + 1] + 1, 0)
run_bot0 = np.zeros((CH, CW), np.int16)
for y in range(CH - 2, -1, -1):
    run_bot0[y] = np.where(M0[y], run_bot0[y + 1] + 1, 0)


def walk(vx, vy, dy, col, hot, length, branch_p, allowed, kind, beads=False, g0=0.5):
    dx = int(rng.choice([-1, 0, 1]))
    for i in range(length):
        if not (inb(vx, vy) and allowed[vy, vx]) or eaten[vy, vx] and i > 0:
            break
        c = hot if i < 2 else col
        if (i < 3 and rng.random() < g0) or (i >= 3 and rng.random() < g0 * 0.4):
            emit(vx, vy, c, kind, 0.45, under=0.5)
        else:
            bpx(vx, vy, c)
        vein_px.add((vx, vy))
        if beads and i % 6 == 5:
            for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                if inb(vx + ddx, vy + ddy) and allowed[vy + ddy, vx + ddx]:
                    emit(vx + ddx, vy + ddy, hot if not (ddx or ddy) else c, kind, 1.0 if not (ddx or ddy) else 0.4, under=0.45)
        vy += dy
        if rng.random() < 0.22:
            dx = int(rng.choice([-1, 0, 0, 1]))
        if i % 2 == 0:
            vx += dx
        if rng.random() < branch_p and i > 2:
            walk(vx, vy, dy, col, hot, int(length * 0.5), branch_p * 0.3, allowed, kind, beads, g0)


# ---------------------------------------------------------------- SHADOW: a creature's body: veins, cores, tendrils
def vein(x, y, ang, length, branch_p, depth=0):
    """a glowing vein in a free direction that bends as it goes, may branch."""
    fx, fy = float(x), float(y)
    for i in range(length):
        px, py = int(round(fx)), int(round(fy))
        if not (inb(px, py) and U0[py, px]):
            break
        c = VEIN_V2 if i < 2 else VEIN_V
        if rng.random() < 0.34:
            emit(px, py, c, K_VOID, 0.4, under=0.45)
        else:
            bpx(px, py, c)
        vein_px.add((px, py))
        ang += rng.normal(0, 0.28)
        fx += np.cos(ang); fy += np.sin(ang)
        if rng.random() < branch_p and depth < 2 and i > 3:
            vein(fx, fy, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.1), int(length * 0.55), branch_p * 0.5, depth + 1)


def core_node(x, y):
    """a glowing node of the body: lilac heart, violet ring, a magenta spot beside it."""
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if inb(x + dx, y + dy) and U0[y + dy, x + dx]:
            emit(x + dx, y + dy, VEIN_V2, K_VOID, 0.6, under=0.4)
    emit(x, y, CORE, K_MAGENTA, 1.1, under=0.5)
    mx, my = x + int(rng.choice([-2, 2])), y + int(rng.choice([-1, 1]))
    if inb(mx, my) and U0[my, mx]:
        emit(mx, my, MAGENTA, K_MAGENTA, 0.7, under=0.4)


pts0 = np.argwhere(M0)
for _ in range(15):
    y, x = pts0[int(rng.integers(len(pts0)))]
    vein(x, y, rng.uniform(0, 2 * np.pi), int(rng.integers(8, 18)), 0.10)
for _ in range(8):
    y, x = pts0[int(rng.integers(len(pts0)))]
    core_node(int(x), int(y))
for _ in range(9):
    y, x = pts0[int(rng.integers(len(pts0)))]
    emit(int(x), int(y), MAGENTA, K_MAGENTA, 0.5, under=0.4)

# wisps: thin tendrils rise from the top edge and reach out of the edges, a few detached shards float near
top_edge = np.argwhere(U0 & ~np.roll(U, 1, 0) & ~np.roll(U, 2, 0))
for y, x in top_edge:
    if rng.random() < 0.045:
        px, py, dx = int(x), int(y) - 1, int(rng.choice([-1, 0, 1]))
        ln = int(rng.integers(3, 9))
        for k in range(ln):
            if not inb(px, py) or U[py, px]:
                break
            bpx(px, py, VEIN_V if k == ln - 1 else RIM)
            if k == ln - 1:
                halo(px, py, VEIN_V, 0.35, "void")
            py -= 1
            if k % 2 == 1:
                px += dx
for _ in range(34):
    y, x = pts0[int(rng.integers(len(pts0)))]
    ang = rng.uniform(0, 2 * np.pi)
    px, py = int(x + np.cos(ang) * 9), int(y + np.sin(ang) * 9)
    if inb(px, py) and not U[py, px] and not outline[py, px] and py < Y0 + LH - 2:
        bpx(px, py, RIM if rng.random() < 0.4 else VOID[2])
        if rng.random() < 0.3 and inb(px + 1, py):
            bpx(px + 1, py, PURPLE_EDGE)

# ---------------------------------------------------------------- the seam: drips that bite into the green
contact = {}
for x in range(CW):
    ys0 = np.where(U0[:, x] & ~U1[:, x])[0]
    ys1 = np.where(U1[:, x])[0]
    if len(ys0) and len(ys1):
        b0 = int(ys0.max()); below = ys1[ys1 > b0]
        if len(below) and below.min() - b0 <= 2:
            contact[x] = (b0, int(below.min()))
depth_map = np.zeros(CW)
if contact:
    xc = min(contact) + int(rng.integers(0, 4))
    while xc <= max(contact):
        wd = int(rng.integers(2, 5)); dd = float(rng.integers(5, 17))
        for dx in range(-wd, wd + 1):
            xx = xc + dx
            if xx in contact:
                depth_map[xx] = max(depth_map[xx], dd * np.sqrt(max(0.0, 1 - (dx / (wd + 0.6)) ** 2)))
        xc += int(rng.integers(7, 15))
drip_cols = set()
for x, (b0, t1) in contact.items():
    d_ = int(round(depth_map[x]))
    if d_ <= 0:
        continue
    drip_cols.add(x)
    for k in range(d_):
        yk = t1 + k
        if inb(x, yk) and U1[yk, x]:
            eaten[yk, x] = True
            bpx(x, yk, VOID[min(k % 3, 2)])
    yk = t1 + d_ - 1
    bpx(x, yk, RIM)
    if d_ > 1:
        bpx(x, yk - 1, PURPLE_EDGE)
    halo(x, yk, RIM, 0.7, "void")
for x, (b0, t1) in contact.items():
    d_ = int(round(depth_map[x]))
    if (d_ >= 6 and depth_map[x] >= depth_map[max(x - 1, 0)] and depth_map[x] >= depth_map[min(x + 1, CW - 1)] and rng.random() < 0.8):
        walk(x, t1 + d_, 1, VEIN_V, VEIN_V2, int(rng.integers(5, 12)), 0.08, M1, K_VOID)
    elif d_ == 0 and ((x - 1) in drip_cols or (x + 1) in drip_cols):
        emit(x, t1, TEAL[4], K_LIFE, 0.9)

# SHADOW's free bottoms: drips of void hang down
def free_below(x, y, n):
    return all(inb(x, y + k) and not U[y + k, x] and not outline[y + k, x] for k in range(1, n + 1))


for x in range(CW):
    for y in range(CH):
        if M0[y, x] and run_bot0[y, x] == 1 and free_below(x, y, 9) and rng.random() < 0.20:
            ln = int(rng.integers(3, 9))
            for k in range(1, ln + 1):
                bpx(x, y + k, VOID[1] if k < ln else RIM)
            halo(x, y + ln, RIM, 0.55, "void")

# ---------------------------------------------------------------- plants (swaying layer)
plants_meta = []


def tuft(x, y, h, ph):
    for dx, hh, lean in ((0, h, int(rng.choice([-1, 0, 1]))), (-2, max(2, h - 2), -1), (2, max(2, h - 2), 1), (-1, max(2, h - 1), 0)):
        for k in range(1, hh + 1):
            px = x + dx + (lean if k > hh * 0.6 else 0)
            ppx(px, y - k, MOSS[min(5, 1 + (k * 4) // hh)], k / (h + 1), ph)


def leaf(x, y, dx, ln, ph, wbase):
    """a small leaf: a short midrib going out and up."""
    for k in range(ln):
        px, py = x + dx * k, y - (k + 1) // 2
        ppx(px, py, MOSS[3 if k < ln - 1 else 5], wbase + 0.05 * k, ph)
        if 0 < k < ln - 1:
            ppx(px, py - 1, MOSS[4], wbase + 0.05 * k, ph)
            ppx(px, py + 1, MOSS[2], wbase + 0.05 * k, ph)


def sprout(x, y, h, ph):
    for k in range(1, h):
        ppx(x, y - k, MOSS[2], k / (h + 1), ph)
    leaf(x, y - h // 2, -1, 4, ph, 0.4)
    leaf(x, y - h // 2 - 1, 1, 4, ph, 0.45)
    for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, -1)):
        ppx(x + ddx, y - h + ddy, MOSS[5] if ddy < 0 else MOSS[4], 0.95, ph)


def flower(x, y, h, ph):
    for k in range(1, h):
        ppx(x, y - k, MOSS[2], k / (h + 1), ph)
    leaf(x, y - h // 2, -1, 3, ph, 0.4)
    leaf(x, y - h // 2 + 1, 1, 3, ph, 0.4)
    tx, ty = x, y - h
    for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ppx(tx + ddx, ty + ddy, TEAL[4] if ddy < 0 else TEAL[3], 1.0, ph)
    for ddx, ddy in ((1, -1), (-1, -1)):
        ppx(tx + ddx, ty + ddy, TEAL[2], 1.0, ph)
    ppx(tx, ty, GOLD[3], 1.0, ph)
    plants_meta.append((tx, ty))


def shroom(sx, sy, s):
    """small glowing cap standing on the ground row sy (static, in the base layer)."""
    for k in range(s + 1):
        bpx(sx, sy - k, hexc("a9c5c7") * 0.6)
    cy_ = sy - s - 1
    for dx in range(-s, s + 1):
        bpx(sx + dx, cy_, TEAL[1])
    for dx in range(-s + 1, s):
        bpx(sx + dx, cy_ - 1, TEAL[2])
    if s >= 2:
        for dx in range(-s + 2, s - 1):
            bpx(sx + dx, cy_ - 2, TEAL[2])
    bpx(sx - s, cy_, TEAL[0])
    emit(sx - 1, cy_ - 1, TEAL[3], K_SHROOM, 0.6)
    emit(sx, cy_, TEAL[2], K_SHROOM, 0.3)


strip_cols = {}
for x in range(CW):
    ys = np.where(top1[:, x] & (np.arange(CH) > 0))[0]
    if len(ys):
        strip_cols[x] = (int(ys.min()), int(ys.max()))
e_letter = letters[-1]
last_x = -99
for x in sorted(strip_cols):
    if x in drip_cols or (x - 1) in drip_cols or (x + 1) in drip_cols:
        # the void has burned these: a bent, violet-tipped blade or nothing
        if rng.random() < 0.18:
            y0_, y1_ = strip_cols[x]
            for k in range(1, 4):
                ppx(x + (k // 3), y1_ - k, VOID[3] if k < 3 else PURPLE_EDGE, k / 5.0, rng.random())
        continue
    if x - last_x < 5 or rng.random() < 0.45:
        continue
    y0_, y1_ = strip_cols[x]
    yr = int(rng.integers(y0_, y1_ + 1))
    ph = float(rng.random())
    r = rng.random()
    free_top = x >= e_letter["x"] - 2
    h = int(rng.integers(3, 8 if free_top else 5))
    if r < 0.46:
        tuft(x, yr, h, ph)
    elif r < 0.64:
        sprout(x, yr, h + 1, ph)
    elif r < 0.78:
        flower(x, yr, h + 2, ph)
    elif r < 0.90:
        shroom(x, yr, int(rng.integers(1, 3)))
    else:
        tuft(x, yr, h + 1, ph); tuft(x + 3, yr, h, ph + 0.2)
    last_x = x


# the big spore flower on the right end of SPORE
def big_plant(bx, by, height=66):
    """stalk with an S-curve, big leaves, a seed head like a puffball of glowing filaments."""
    ph = 0.25
    pts = []
    for i in range(height):
        t = i / (height - 1)
        pts.append((bx + 6.0 * np.sin(t * 2.4) * (0.4 + 0.6 * t) + 4.0 * t, by - i))
    thick = lambda t: 3 if t < 0.35 else 2
    for i, (px, py) in enumerate(pts):
        t = i / (height - 1)
        w_ = (t ** 1.25)
        px = int(round(px))
        for dx in range(thick(t)):
            ppx(px + dx - 1, int(py), MOSS[1] if dx == 0 else (MOSS[3] if dx == thick(t) - 1 else MOSS[2]), w_, ph)
    # leaves
    for i, (t, side, ln) in enumerate(((0.17, -1, 15), (0.24, 1, 19), (0.36, -1, 14), (0.46, 1, 14), (0.60, -1, 10), (0.68, 1, 9))):
        px, py = pts[int(t * (height - 1))]
        px, py = int(round(px)), int(py)
        for k in range(ln):
            lx = px + side * (k + 1)
            droop = 0.014 * k * k * (1.4 - t)
            ly = py - int(round(1.5 * np.sin(k * 0.22) * 2 - droop * 3 + k * 0.28))
            width = int(round(3.2 * np.sin(np.pi * (k + 1) / (ln + 1)) + 0.6))
            for q in range(-width + 1, width + 1):
                c = MOSS[min(5, 2 + (q <= -1) + (k < ln * 0.4 and q < 0))] if q != 0 else MOSS[1]
                if q > 0:
                    c = MOSS[2 if k % 3 else 1]
                ppx(lx, ly + q, c, (1 - t) * 0.1 + t ** 1.1 + 0.05 * k, ph)
            ppx(lx, ly, MOSS[5] if k < ln - 2 else MOSS[4], t ** 1.1 + 0.05 * k, ph)
    # the head
    hx, hy = pts[-1]
    hx, hy = int(round(hx)), int(hy) - 6
    meta = (hx, hy)
    for a in np.linspace(0, 2 * np.pi, 34, endpoint=False):
        rr = 11.5 + 1.8 * np.sin(a * 3)
        for rad in np.arange(3.0, rr, 0.6):
            px, py = int(round(hx + np.cos(a) * rad)), int(round(hy + np.sin(a) * rad * 0.92))
            c = TEAL[1] if rad < 6 else (TEAL[2] if rad < 9 else TEAL[3])
            ppx(px, py, c, 1.0, ph)
        tx, ty = int(round(hx + np.cos(a) * rr)), int(round(hy + np.sin(a) * rr * 0.92))
        ppx(tx, ty, TEAL[4], 1.0, ph)
    for ddx in range(-2, 3):
        for ddy in range(-2, 3):
            if ddx * ddx + ddy * ddy <= 5:
                ppx(hx + ddx, hy + ddy, GOLD[2] if ddx * ddx + ddy * ddy > 2 else GOLD[3], 1.0, ph)
    # a few drooping seed buds under the head
    for sx_, ln in ((-5, 6), (6, 5)):
        for k in range(ln):
            ppx(hx + sx_ + (k // 3) * np.sign(sx_), hy + 12 + k, MOSS[3], 1.0, ph)
        ppx(hx + sx_ + (ln // 3) * int(np.sign(sx_)), hy + 12 + ln, TEAL[3], 1.0, ph)
    return meta


E_right = e_letter["x"] + e_letter["w"]
bx = E_right - 3
ys = strip_cols.get(bx, (Y1 - 4, Y1 - 1))
big_head = big_plant(bx, ys[1], 66)


def roots(rx, ry):
    """the stalk grips the block: a moss collar and a knot of roots creeping out and down into the wood (static, above the leaves)."""
    for dx in range(-4, 5):
        ppx(rx + dx, ry, MOSS[1] if abs(dx) > 2 else MOSS[2], 0.0, 0.0)
        if abs(dx) < 4:
            ppx(rx + dx, ry - 1, MOSS[3] if abs(dx) < 3 else MOSS[2], 0.0, 0.0)
        if abs(dx) < 2:
            ppx(rx + dx, ry - 2, MOSS[4], 0.0, 0.0)
    for sgn, ln, drop in ((-1, 12, 0.5), (1, 12, 0.4), (-1, 8, 1.1), (1, 8, 1.0), (0, 8, 1.6)):
        x_, y_ = float(rx + sgn * 2), float(ry + 1)
        for i in range(ln):
            c = BARK1[4] if i < 2 else (BARK1[3] if i < ln - 4 else BARK1[2])
            px, py = int(round(x_)), int(round(y_))
            ppx(px, py, c, 0.0, 0.0)
            if i < 5:
                ppx(px + (1 if sgn >= 0 else -1) * 0, py + 1, BARK1[1], 0.0, 0.0)
                ppx(px, py - 1 if i < 3 else py, BARK1[3], 0.0, 0.0)
            x_ += sgn * (1.0 - drop * 0.45)
            y_ += 0.3 + drop * 0.6
        ppx(int(round(x_)), int(round(y_)), TEAL[3], 0.0, 0.0)
        emit(int(round(x_)), int(round(y_)), TEAL[3], K_LIFE, 0.5, under=0.6)
    for dx in (-5, 5):
        ppx(rx + dx, ry - 1, TEAL[3], 0.0, 0.0)


roots(bx, ys[1])

# hanging vines under SPORE's free bottoms
for x in range(CW):
    for y in range(CH):
        if M1[y, x] and run_bot1[y, x] == 1 and not eaten[y, x] and free_below(x, y, 10) and rng.random() < 0.22:
            ln = int(rng.integers(3, 10))
            vx = x; ph = float(rng.random())
            for k in range(1, ln + 1):
                if k % 3 == 0:
                    vx += int(rng.choice([-1, 1]))
                ppx(vx, y + k, MOSS[1] if k < ln - 1 else MOSS[4], 0.2 + k / 14.0, ph)
                if k % 3 == 2:
                    ppx(vx + 1, y + k, MOSS[3], 0.2 + k / 14.0, ph)
            ppx(vx, y + ln, TEAL[3], 0.9, ph)

# mushrooms standing on the ground in front of SPORE
for _ in range(34):
    px = int(rng.integers(X0 + 6, X0 + total))
    if inb(px, GROUND_Y) and M1[GROUND_Y - 1, px] and not U[GROUND_Y, px]:
        shroom(px, GROUND_Y + int(rng.integers(2, 7)), int(rng.integers(2, 5)))
shroom(X0 + total - 4, GROUND_Y + 7, 4)
shroom(X0 + total + 5, GROUND_Y + 3, 2)

# life roots, beaded, growing up the faces of SPORE
bottoms = [(x, y) for x in range(CW) for y in range(CH) if M1[y, x] and run_bot1[y, x] == 1 and not eaten[y, x]]
rng.shuffle(bottoms)
picked = []
for x, y in bottoms:
    if all(abs(x - px) > 11 for px, _ in picked):
        picked.append((x, y))
for x, y in picked[:5]:
    walk(x, y - 1, -1, TEAL[2], TEAL[3], int(rng.integers(12, 26)), 0.07, M1, K_LIFE, beads=True, g0=0.3)

def shelf(x, y):
    """a small shelf fungus on a right edge, the trees' teal caps."""
    for k, c in enumerate((TEAL[1], TEAL[3], TEAL[3], TEAL[1])):
        bpx(x + 1 + k, y, c)
    for k, c in enumerate((TEAL[0], TEAL[1], TEAL[0])):
        bpx(x + 1 + k, y + 1, c)
    emit(x + 2, y, TEAL[3], K_SHROOM, 0.5, under=0.8)
    emit(x + 3, y, TEAL[4], K_SHROOM, 0.7, under=0.8)


right_edge = np.argwhere(M1 & ~np.roll(U, -1, 1) & ~np.roll(U, -2, 1))
rng.shuffle(right_edge)
placed_s = []
for y, x in right_edge:
    if Y1 + 6 < y < Y1 + LH - 8 and all(abs(y - py) + abs(x - px) > 14 for px, py in placed_s):
        shelf(int(x), int(y)); placed_s.append((int(x), int(y)))
    if len(placed_s) >= 7:
        break

# glimmer berries on the mossy faces
cands = [(x, y) for x in range(X0, X0 + total) for y in range(Y1 + 3, Y1 + LH - 3)
         if moss_sel[y, x] and not eaten[y, x] and (x, y) not in vein_px and M1[y, x] and M1[y + 1, x + 1]]
rng.shuffle(cands)
placed = []
for x, y in cands:
    if len(placed) >= 16:
        break
    if all(abs(x - px) + abs(y - py) > 9 for px, py in placed):
        placed.append((x, y))
        gold = len(placed) % 3 != 0
        c0, c1 = (GOLD[2], GOLD[3]) if gold else (TEAL[3], TEAL[4])
        for ddx, ddy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            emit(x + ddx, y + ddy, c0 if (ddx or ddy) else c1, K_BERRY, 0.8)

# ---------------------------------------------------------------- ground: shadow and the glowing crack
gsh = np.roll(np.roll(U1, 6, 1), 4, 0) & ~U & (np.arange(CH)[:, None] >= Y1 + LH - 4)
for y, x in zip(*np.nonzero(gsh)):
    if BAYER[y % 4, x % 4] < 0.62:
        base[y, x, :3] = hexc("030106"); base[y, x, 3] = 0.85
by = GROUND_Y + 11
cxs = np.arange(X0 - 40, X0 + total + 40)
off = np.round(1.6 * np.sin(cxs * 0.06) + 1.2 * np.sin(cxs * 0.17 + 1.3)).astype(int)
env = np.clip(1.0 - np.abs((cxs - (X0 + total / 2)) / (total / 2 + 40)) ** 2.0, 0, 1)
for px, o, e in zip(cxs, off, env):
    if rng.random() < e * 1.1 + 0.08:
        k = (px - cxs[0]) / (cxs[-1] - cxs[0])
        col = VEIN_V * (1 - k) + TEAL[2] * k
        hot = VEIN_V2 * (1 - k) + TEAL[3] * k
        bpx(px, by + o, col * 0.5)
        bpx(px, by + o + 1, (PURPLE_EDGE * (1 - k) + TEAL[0] * k) * 0.7)
        if rng.random() < 0.06 * e:
            ln = int(rng.integers(3, 7)); sx = int(rng.choice([-1, 1]))
            for q in range(ln):
                bpx(px + (q // 2) * sx, by + o + 2 + q, col * (0.6 - q * 0.07))
        if rng.random() < 0.5 * e:
            emit(px, by + o, hot, K_CRACK, 0.9, under=0.5)

# ---------------------------------------------------------------- the orbs (8 frames each, drawn under the base inside the holes)
FW = 40
order = sorted(orbs, key=lambda o: o["row"])
void_o, life_o = order[0], order[1]


def sphere_tone(tones, r, ddx, ddy, ex, ey, light=(-0.55, -0.6)):
    rr = np.hypot(ddx / ex, ddy / ey)
    if rr > 1.0:
        return None
    z = np.sqrt(max(0.0, 1 - rr * rr))
    sh = float(np.clip(np.array([ddx / ex, ddy / ey, z]) @ np.array([light[0], light[1], 0.58]), 0, 1))
    return tones[int(np.clip(np.floor(sh * (len(tones) - 1) + BAYER[int(ddy) % 4, int(ddx) % 4]), 0, len(tones) - 1))]


def put(img, x, y, c, a=1.0):
    x, y = int(x), int(y)
    if 0 <= x < FW and 0 <= y < FW:
        img[y, x] = (*c, a)


def void_frame(f):
    """a watching eye in the void: an almond iris with a slit pupil that breathes, veins creeping out of it, glitch rows now and then."""
    img = np.zeros((FW, FW, 4), np.float32); c = FW / 2 - 0.5
    ex, ey = void_o["rx"] + 1.5, void_o["ry"] + 1.5
    rg = np.random.default_rng(100 + f)
    for y in range(FW):
        for x in range(FW):
            col = sphere_tone(VOID, 0, x - c, y - c, ex, ey)
            if col is not None:
                img[y, x] = (*col, 1.0)
    for ang in np.linspace(-0.2, 1.8, 50):  # cold rim light, lower right
        put(img, round(c + np.cos(ang) * (ex - 1.2)), round(c + np.sin(ang) * (ey - 1.2)), RIM)
    pulse = [0.7, 1.0, 0.85, 0.6, 0.5, 0.8, 1.0, 0.75][f]
    # veins first, curving out of the eye
    for k_, ang in enumerate((0.15, 0.95, 2.2, 3.0, 3.75, 4.5, 5.35)):
        L = int(6 + 4 * pulse + (k_ % 3) * 2)
        for k in range(6, 6 + L):
            bend = 0.18 * np.sin(k * 0.45 + k_)
            px, py = c + np.cos(ang + bend) * k * 1.05, c + np.sin(ang + bend) * k * 0.85
            if np.hypot((px - c) / ex, (py - c) / ey) < 0.9:
                put(img, round(px), round(py), VEIN_V2 if k < 9 else VEIN_V)
    # the almond eye
    for y in range(FW):
        for x in range(FW):
            dx, dy = x - c, y - c
            r2 = (dx / 7.2) ** 2 + (dy / 3.8) ** 2
            if r2 <= 1.0:
                t = 0.62 + 0.38 * pulse
                col = MAGENTA * (t if r2 > 0.55 else 1.0)
                if abs(dy) >= 3 and r2 > 0.7:
                    col = PURPLE_EDGE * 1.4 + MAGENTA * 0.25
                put(img, x, y, col)
    sl = 1 if pulse < 0.75 else 2
    for y in range(int(c) - 3, int(c) + 4):
        for x in range(int(c + 0.5 - sl / 2), int(c + 0.5 + sl / 2 + 0.5)):
            put(img, x, y, VOID[0])
    put(img, c - 2, c - 1, CORE); put(img, c - 2, c, CORE * 0.7 + MAGENTA * 0.3)
    for _ in range(3):  # motes drifting in the dark
        put(img, c + rg.integers(-12, 13), c + rg.integers(-11, 12), RIM)
    if f in (2, 5, 6):  # glitch rows
        for ro in rg.choice(np.arange(-9, 10), 3, replace=False):
            yk = int(c + ro); sh_ = int(rg.choice([-3, -2, 2, 3]))
            row = np.roll(img[yk], sh_, axis=0)
            keep = img[yk, :, 3] > 0
            img[yk] = np.where(keep[:, None], row, img[yk])
            xx_ = int(c - ex + (1 if sh_ > 0 else 2 * ex - 1))
            if 0 <= xx_ < FW and img[yk, xx_, 3] > 0:
                img[yk, xx_] = (*MAGENTA, 1.0)
    return img


def stem_cols(y):
    """the lamp post's iron, three pixels wide: lit left, body, dark right; it twists by a pixel now and then."""
    sx = int(round(np.sin(y * 0.55) * 0.6))
    return [(sx - 1, IRON[3] if int(y) % 3 == 0 else IRON[2]), (sx, IRON[2] if int(y) % 2 else IRON[1]), (sx + 1, hexc("110c17"))]


def life_frame(f):
    """the town's lamp post standing right in the O, its light making a little land of the void: light is land."""
    img = np.zeros((FW, FW, 4), np.float32); c = FW / 2 - 0.5
    ex, ey = life_o["rx"] + 1.5, life_o["ry"] + 1.5
    rg = np.random.default_rng(200 + f)
    ph = f / FRAMES * 2 * np.pi
    flick = [1.0, 0.94, 1.06, 0.97, 1.08, 0.92, 1.02, 0.96][f]
    sway = round(np.sin(ph) * 0.8)
    fy = c + life_o["ry"] - 2.0                     # where the post meets the ring's inner bottom
    bx_, by_ = int(c - 3), int(fy)                  # foot of the post
    top = by_ - 24
    lan_x, lan_y = bx_ + 5 + sway, top + 3          # lantern, top left corner
    rl = 12.0 * flick
    lcx, lcy = lan_x + 3, lan_y + 5
    for y in range(FW):  # void sky
        for x in range(FW):
            if np.hypot((x - c) / ex, (y - c) / ey) <= 1.0:
                img[y, x] = (*VOID[1], 1.0)
    for y in range(FW):  # the pool of light in the air round the lantern: flat teal rings, a clean edge
        for x in range(FW):
            if img[y, x, 3] > 0:
                d_l = np.hypot(x - lcx, (y - lcy) * 1.05)
                if d_l < rl * 0.42:
                    img[y, x, :3] = hexc("1c525c")
                elif d_l < rl * 0.7:
                    img[y, x, :3] = hexc("153c46")
                elif d_l < rl:
                    img[y, x, :3] = hexc("0f2a34")
    for i, fx_ in enumerate((-13, -10, -2, 2, 5, 9, 12)):  # tufts and glow caps in the corner where the O curves up
        x = int(c + fx_)
        y = int(c + ey * np.sqrt(max(0.0, 1 - (fx_ / ex) ** 2))) - 3
        h_ = 1 + (i % 3)
        for k in range(h_):
            put(img, x, y - k, MOSS[4] if k == h_ - 1 else MOSS[3])
        if i in (1, 5):
            put(img, x + 1, y - h_, TEAL[3] if i == 1 else MOSS[5])
    # the post: cairn, two twisted stems, the curl, chain, hood, hanging cage
    for y in range(by_ - 1, top, -1):
        for dx, col in stem_cols(y):
            put(img, bx_ + dx, y, col)
    vy = by_ - 4 - int((f / FRAMES) * 20)           # the pulse of light up the violet vein
    put(img, bx_ + 1, vy, VEIN_V2); put(img, bx_ + 1, vy + 1, VEIN_V)
    for dx, dy in ((0, 0), (1, -1), (2, -1), (3, -1), (4, 0), (5, 1), (6, 2)):
        put(img, bx_ + dx, top + dy, IRON[3] if dx % 2 else IRON[2])
        put(img, bx_ + dx, top + dy + 1, hexc("110c17"))
    put(img, bx_ + 5, top + 2, EARTH[2])
    lx0, ly0 = int(lan_x), int(lan_y)
    for dx in range(-1, 8):                          # hood with a bud of moss
        put(img, lx0 + dx, ly0 - 1, IRON[0] if dx < 4 else IRON[1])
    for dx in range(0, 7):
        put(img, lx0 + dx, ly0, IRON[1])
    put(img, lx0 + 2, ly0 - 2, MOSS[3]); put(img, lx0 + 3, ly0 - 2, MOSS[4])
    for dy in range(1, 10):                          # the cage, glass lit from inside
        put(img, lx0, ly0 + dy, EARTH[0]); put(img, lx0 + 6, ly0 + dy, EARTH[0])
        put(img, lx0 + 3, ly0 + dy, EARTH[0]) if dy in (1, 9) else None
        for dx in range(1, 6):
            put(img, lx0 + dx, ly0 + dy, TEAL[2] if dy > 2 else TEAL[1])
    for dx in range(0, 7):
        put(img, lx0 + dx, ly0 + 10, EARTH[0])
    tongues = [(3, 5), (2, 3), (4, 3)] if f % 2 == 0 else [(3, 6), (2, 2), (4, 4)]
    for dx, ln in tongues:                           # three tongues, a white-teal heart, a gold seed
        for k in range(ln):
            put(img, lx0 + dx, ly0 + 8 - k, TEAL[4] if dx == 3 else TEAL[3])
    put(img, lx0 + 3, ly0 + 8, GOLD[3]); put(img, lx0 + 2, ly0 + 8, GOLD[2]); put(img, lx0 + 4, ly0 + 8, GOLD[2])
    for y in range(FW):  # glass: a dark rim, a small sheen top left
        for x in range(FW):
            if img[y, x, 3] > 0 and np.hypot((x - c) / ex, (y - c) / ey) > 0.9:
                img[y, x, :3] *= 0.5
    return img


void_sheet = np.concatenate([void_frame(f) for f in range(FRAMES)], axis=1)
life_sheet = np.concatenate([life_frame(f) for f in range(FRAMES)], axis=1)

# ---------------------------------------------------------------- halos
def make_halo(entries, strength=1.0):
    G = np.zeros((CH, CW, 3), np.float32)
    for x, y, c, s in entries:
        if inb(x, y):
            G[y, x] += c / 255.0 * s
    gi = Image.fromarray(np.clip(G * 255, 0, 255).astype(np.uint8))
    g1 = np.array(gi.filter(ImageFilter.GaussianBlur(1.3)), np.float32) / 255.0
    g2 = np.array(gi.filter(ImageFilter.GaussianBlur(3.6)), np.float32) / 255.0
    g3 = np.array(gi.filter(ImageFilter.GaussianBlur(8.0)), np.float32) / 255.0
    h = g1 * 1.8 + g2 * 3.4 + g3 * 3.0
    levels = 5
    hq = np.floor(np.clip(h, 0, 1) * levels + bayer((CH, CW))[..., None] * 0.999) / levels
    hq = hq * np.where(U | outline, 0.28, 1.0)[..., None]
    return np.clip(hq * strength, 0, 1)


# the big flower and the lamp get their halos from the plants / orb
for (tx, ty) in plants_meta:
    halo(tx, ty, GOLD[3], 1.0, "life")
bhx, bhy = big_head
for a in np.linspace(0, 2 * np.pi, 34, endpoint=False):
    rr = 11.5 + 1.8 * np.sin(a * 3)
    emit_x, emit_y = int(round(bhx + np.cos(a) * rr)), int(round(bhy + np.sin(a) * rr * 0.92))
    emit(emit_x, emit_y, TEAL[4], K_BLOOM, 0.85, under=1.0)
    halo(int(round(bhx + np.cos(a) * rr * 0.6)), int(round(bhy + np.sin(a) * rr * 0.6 * 0.92)), TEAL[3], 0.5, "life")
for ddx in range(-2, 3):
    for ddy in range(-2, 3):
        if ddx * ddx + ddy * ddy <= 5:
            emit(bhx + ddx, bhy + ddy, GOLD[3] if ddx * ddx + ddy * ddy <= 2 else GOLD[2], K_BLOOM, 1.4, under=1.0)
for ang_ in np.linspace(0, 2 * np.pi, 14, endpoint=False):
    halo(int(round(bhx + np.cos(ang_) * 5)), int(round(bhy + np.sin(ang_) * 5)), TEAL[3], 0.6, "life")

lamp_entries = []
lx_c, ly_c = life_o["cx"] + 3.0, life_o["cy"] - 3.0
for ang_ in np.linspace(0, 2 * np.pi, 12, endpoint=False):
    lamp_entries.append((int(round(lx_c + np.cos(ang_) * 3)), int(round(ly_c + np.sin(ang_) * 3)), TEAL[3], 0.9))
lamp_entries.append((int(lx_c), int(ly_c), TEAL[4], 1.4))
vo_entries = [(int(void_o["cx"] + dx), int(void_o["cy"] + dy), MAGENTA, 1.0) for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))]
halos["void"].extend(vo_entries)

# ---------------------------------------------------------------- the lamp's light on the ring of the O (so the lamp belongs to the letter)
_c = FW / 2 - 0.5
_by = int(_c + life_o["ry"] - 2.0)
lamp_cx = life_o["cx"] + (16 + 5 + 3 - _c)
lamp_cy = life_o["cy"] + ((_by - 24 + 3 + 5) - _c)
_bay = bayer((CH, CW))
for yy in range(int(life_o["cy"] - 24), int(life_o["cy"] + 25)):
    for xx in range(int(life_o["cx"] - 30), int(life_o["cx"] + 31)):
        if not (inb(xx, yy) and M1[yy, xx]):
            continue
        dn = np.hypot((xx - life_o["cx"]) / (life_o["rx"] + 0.5), (yy - life_o["cy"]) / (life_o["ry"] + 0.5))
        if dn > 2.0:
            continue
        dl = np.hypot(xx - lamp_cx, (yy - lamp_cy) * 1.1)
        L = np.clip(1.0 - dl / 24.0, 0, 1) * np.clip(1.0 - (dn - 1.0) / 0.55, 0, 1)
        a_ = np.floor(L * 3.2 + _bay[yy, xx] * 0.9) / 3.0
        a_ = float(np.clip(a_, 0, 0.9)) * 0.7
        if a_ > 0:
            base[yy, xx, :3] = base[yy, xx, :3] * (1 - a_) + TEAL[2] * a_

# the foot of the lamp post: a little cairn heaped on the O's inner rim, moss and glow caps round it, so the post really stands in the letter
_ox, _oy = life_o["cx"] - _c, life_o["cy"] - _c
_bx = int(round(int(_c - 3) + _ox))
_hole_bottom = int(round(life_o["cy"] + life_o["ry"]))


def foot(x, y, col):
    if inb(int(x), int(y)):
        base[int(y), int(x), :3] = col
        base[int(y), int(x), 3] = 1.0


_ink = hexc("110c17")
for yy in range(_hole_bottom - 9, _hole_bottom + 8):               # no random moss round the foot: plain lit stone, the heap grows its own
    for xx in range(_bx - 11, _bx + 12):
        if inb(xx, yy) and base[yy, xx, 3] > 0 and yy >= _hole_bottom - 3:
            r_, g_, b_ = base[yy, xx, :3]
            if (g_ > r_ + 6 and g_ > b_ + 6) or (b_ > r_ + 40 and g_ > r_ + 40):
                base[yy, xx, :3] = BARK1[2 + int(_bay[yy, xx] > 0.5)]
                core[yy, xx] = 0; cmap[yy, xx] = 0
for k, wd_ in enumerate((1, 2, 3, 4, 5, 6)):
    yy = _hole_bottom - 6 + k
    for dx in range(-wd_ - 1, wd_ + 2):
        if abs(dx) == wd_ + 1 or k == 0:
            foot(_bx + dx, yy, _ink if k > 0 else STONE[0])
        else:
            tone = 4 if (dx < 0 and k < 3) else (3 if k < 4 else 2)
            foot(_bx + dx, yy, STONE[min(4, tone - int((dx * 3 + k * 5) % 5 == 0))])
for dx in (-5, -4, 4, 5):                                           # moss at the foot of the heap
    foot(_bx + dx, _hole_bottom - 1, MOSS[4] if dx < 0 else MOSS[3])
    foot(_bx + dx, _hole_bottom, MOSS[3])
for dx in (-3, -2, 2, 3):
    foot(_bx + dx, _hole_bottom - 2, MOSS[4])
foot(_bx - 5, _hole_bottom - 3, TEAL[3]); foot(_bx - 5, _hole_bottom - 2, TEAL[2])   # glow caps
foot(_bx + 5, _hole_bottom - 3, TEAL[4]); foot(_bx + 5, _hole_bottom - 2, TEAL[3])
for k in range(3):                                                  # the iron stem comes down into the stones
    yo = _hole_bottom - 8 + k
    for dx, col in stem_cols(yo - _oy):
        foot(_bx + dx, yo, col)
halos["life"].extend([(_bx - 5, _hole_bottom - 3, TEAL[3], 0.7), (_bx + 5, _hole_bottom - 3, TEAL[3], 0.7)])

# ---------------------------------------------------------------- the build order (title_order.png): when does every pixel of the letters land?
# R = arrival time 0..255 (stack up from the foot of each letter, SPORE first, the letters from the middle outwards, SHADOW after it),
# G = 255 for pixels that slide in sideways (SHADOW, like the shadow creatures' glitch rows), 0 for pixels that fall from above, B = noise, A = 255 (data map)
order = np.zeros((CH, CW, 4), np.uint8)
order[..., 3] = 255
_orng = np.random.default_rng(77)
_mid = X0 + total / 2.0
_ranks = {}
for _row in (0, 1):
    _ls = [k for k, l in enumerate(letters) if l["row"] == _row]
    _ls.sort(key=lambda k: abs(letters[k]["x"] + letters[k]["w"] / 2.0 - _mid))
    for _r, k in enumerate(_ls):
        _ranks[k] = _r
_lx = np.array([l["x"] + l["w"] / 2.0 for l in letters])
_owner = np.full((CH, CW), -1, np.int16)
_ys, _xs = np.nonzero(base[..., 3] > 0)
for y, x in zip(_ys, _xs):
    k = int(lid[y, x])
    if k < 0:
        cand = [i for i, l in enumerate(letters) if (l["row"] == 0) == (y < Y0 + LH)]
        k = min(cand, key=lambda i: abs(_lx[i] - x))
    _owner[y, x] = k
_raw = np.zeros((CH, CW), np.float32)
for y, x in zip(_ys, _xs):
    k = int(_owner[y, x]); l = letters[k]
    yrel = np.clip((y - (l["y"] - D)) / float(LH + D), 0.0, 1.0)
    jitter = _orng.random()
    if l["row"] == 1:
        t_ = 0.0 + _ranks[k] * 0.09 + 0.42 * (0.78 * (1.0 - yrel) + 0.22 * jitter)       # SPORE: stacks up from its foot
        order[y, x, 1] = 0
    else:
        t_ = 0.30 + _ranks[k] * 0.09 + 0.42 * (0.78 * yrel + 0.22 * jitter)              # SHADOW: the void flows in from the top, sliding
        order[y, x, 1] = 255
    _raw[y, x] = t_
    order[y, x, 2] = int(jitter * 255)
_mx = float(_raw.max())
order[..., 0] = np.clip(_raw / _mx * 255.0 + 0.5, 0, 255).astype(np.uint8)
OUT_A.mkdir(parents=True, exist_ok=True)
Image.fromarray(order, "RGBA").save(OUT_A / "title_order.png")

# ---------------------------------------------------------------- glitch rows (baked into the still; the engine adds its own now and then)
for _ in range(8):
    yk = int(rng.integers(Y0 + 4, Y0 + LH + 2)); hh = int(rng.integers(1, 3)); sh_ = int(rng.choice([-3, -2, 2, 3]))
    for r_ in range(yk, min(yk + hh, CH)):
        xs_ = np.nonzero(U0[r_])[0]
        if len(xs_) == 0:
            continue
        x0, x1 = int(xs_.min()) - 4, int(xs_.max()) + 5
        seg = slice(x0, x1)
        for arr in (base, core, cmap):
            arr[r_, seg] = np.roll(arr[r_, seg], sh_, axis=0)

# ---------------------------------------------------------------- write the layers
OUT_A.mkdir(parents=True, exist_ok=True)
OUT_I.mkdir(parents=True, exist_ok=True)


def save_rgba(arr, name):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGBA").save(OUT_A / name)


b_out = np.zeros((CH, CW, 4), np.uint8)
b_out[..., :3] = np.clip(base[..., :3], 0, 255).astype(np.uint8)
b_out[..., 3] = np.clip(base[..., 3] * 255, 0, 255).astype(np.uint8)
Image.fromarray(b_out, "RGBA").save(OUT_A / "title_base.png")
p_out = np.zeros((CH, CW, 4), np.uint8)
p_out[..., :3] = np.clip(pl[..., :3], 0, 255).astype(np.uint8)
p_out[..., 3] = (pl[..., 3] * 255).astype(np.uint8)
Image.fromarray(p_out, "RGBA").save(OUT_A / "title_plants.png")
sm = np.zeros((CH, CW, 4), np.uint8)
sm[..., 0] = (psway[..., 0] * 255).astype(np.uint8)
sm[..., 1] = (psway[..., 1] * 255).astype(np.uint8)
sm[..., 3] = 255  # data map: fully opaque, so the importer never touches the values
Image.fromarray(sm, "RGBA").save(OUT_A / "title_plants_sway.png")
c_out = np.zeros((CH, CW, 4), np.uint8)
c_out[..., :3] = np.clip(core[..., :3], 0, 255).astype(np.uint8)
c_out[..., 3] = (core[..., 3] * 255).astype(np.uint8)
Image.fromarray(c_out, "RGBA").save(OUT_A / "title_glow.png")
m_out = np.zeros((CH, CW, 4), np.uint8)
m_out[..., 0] = (cmap[..., 0] * 255).astype(np.uint8)
m_out[..., 1] = (cmap[..., 1] * 32).astype(np.uint8)
m_out[..., 3] = 255  # data map: fully opaque
Image.fromarray(m_out, "RGBA").save(OUT_A / "title_glow_map.png")


def save_halo(hq, name):
    out = np.zeros((CH, CW, 4), np.uint8)
    out[..., :3] = (hq * 255 + 0.5).astype(np.uint8)
    out[..., 3] = np.where(hq.max(axis=2) > 0, 255, 0).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT_A / name)


h_void, h_life = make_halo(halos["void"], 0.8), make_halo(halos["life"], 0.8)
# the lamp halo is placed over the life O, so it is drawn after the base (additive) and only lights the glass
h_lamp = make_halo(lamp_entries, 0.3)
save_halo(h_void, "title_halo_void.png"); save_halo(h_life, "title_halo_life.png"); save_halo(h_lamp, "title_halo_lamp.png")


def save_sheet(arr, name):
    out = np.zeros(arr.shape, np.uint8)
    out[..., :3] = np.clip(arr[..., :3], 0, 255).astype(np.uint8)
    out[..., 3] = (arr[..., 3] * 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT_A / name)


save_sheet(void_sheet, "title_orb_void.png")
save_sheet(life_sheet, "title_orb_life.png")

layout = dict(
    size=[CW, CH], origin_of_word=[X0, Y0], word=[total, 2 * LH + ROWGAP], frames=FRAMES, orb_frame=FW,
    orbs=dict(void=dict(center=[void_o["cx"], void_o["cy"]], radius=[void_o["rx"], void_o["ry"]]),
              life=dict(center=[life_o["cx"], life_o["cy"]], radius=[life_o["rx"], life_o["ry"]])),
    lamp_light=[lx_c, ly_c],
    bloom=[bhx, bhy],
    spore_sources=[[bhx, bhy]] + [[x, y] for x, y in plants_meta[:6]],
    void_sources=[[X0 + 14, Y0 + 2], [X0 + total * 0.5, Y0 + 2]],
    drip_columns=sorted(int(x) for x in drip_cols),
    seam_y=[Y0 + LH, Y1],
    ground_y=GROUND_Y,
    crack_y=by,
    kinds=["void", "magenta", "life", "berry", "shroom", "crack", "bloom"],
)
(OUT_D / "title_logo_layout.json").write_text(json.dumps(layout, indent=1), encoding="utf-8")

# ---------------------------------------------------------------- preview composite (the same order as the engine, frame 0, no sway)
def stage(sheet_frames=(0, 0), gamma=1.0):
    SW, SH = 640, 360
    ox, oy = (SW - CW) // 2, (SH - CH) // 2 - 6
    canvas = np.zeros((SH, SW, 3), np.float32)
    cxx, cyy = SW / 2, SH / 2 + 8
    dist = np.sqrt(((np.arange(SW)[None, :] - cxx) / 340) ** 2 + ((np.arange(SH)[:, None] - cyy) / 200) ** 2)
    bgi = np.floor(np.clip(1.0 - dist, 0, 1) * 3.2 + bayer((SH, SW)) * 0.999).astype(int)
    canvas[:] = np.stack([hexc("040208"), hexc("050208"), hexc("07040d"), hexc("0e0919")])[np.clip(bgi, 0, 3)]
    srng = np.random.default_rng(5)
    for _ in range(150):
        px, py = srng.integers(0, SW), srng.integers(0, SH)
        canvas[py, px] = RIM * (0.35 + 0.4 * srng.random())

    def over(layer_rgb, layer_a, x0, y0):
        h, w = layer_a.shape
        for_y = slice(max(y0, 0), min(y0 + h, SH)); for_x = slice(max(x0, 0), min(x0 + w, SW))
        sy = slice(for_y.start - y0, for_y.stop - y0); sx = slice(for_x.start - x0, for_x.stop - x0)
        a = layer_a[sy, sx, None]
        canvas[for_y, for_x] = canvas[for_y, for_x] * (1 - a) + layer_rgb[sy, sx] * a

    for orb, sheet, f in ((void_o, void_sheet, sheet_frames[0]), (life_o, life_sheet, sheet_frames[1])):
        fr = sheet[:, f * FW:(f + 1) * FW]
        over(fr[..., :3], fr[..., 3], int(round(orb["cx"] - FW / 2 + 0.5)) + ox, int(round(orb["cy"] - FW / 2 + 0.5)) + oy)
    over(base[..., :3], base[..., 3], ox, oy)
    over(pl[..., :3], pl[..., 3], ox, oy)
    over(core[..., :3], core[..., 3], ox, oy)
    add = np.zeros((SH, SW, 3), np.float32)
    for hq in (h_void, h_life, h_lamp):
        add[oy:oy + CH, ox:ox + CW] += hq
    return np.clip(canvas / 255.0 + add * 0.8, 0, 1)


img = Image.fromarray((stage() * 255 + 0.5).astype(np.uint8))
img.save(OUT_I / "title_logo_preview_1x.png")
img.resize((640 * 3, 360 * 3), Image.NEAREST).save(OUT_I / "title_logo_preview.png")
print("layers ->", OUT_A, "| word", total, "x", 2 * LH + ROWGAP, "| plants:", len(plants_meta), "flowers | big head", big_head)
