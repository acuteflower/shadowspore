#!/usr/bin/env python3
"""The open-air salon of the town (docs/salon_konzept.md, piece `salon`): a low plank deck with a woven rug, a little swivel chair with a violet velvet cushion,
a tall standing mirror in a brass frame (its glass shows a dusk sky in turquoise and violet, not the world) with a ledge of combs, brushes and bottles, an open
shelf of towels, jars and ribbons, potted plants and a light pergola with a cloth sail and a brass lantern. Made like the other town pieces (ellipsoids through
art_hero3d / hut_lib, fresh plum wood), the small things painted by hand on top.

    py -3 tools/art_town_salon.py [contact.png]

Writes assets/town/salon.png (112 x 96, feet row 84), salon_glow.png (8 unlit frames side by side: a shine sweeping over the glass, twinkling bottles, a glimmer
running round the rim), the parts salon_canopy / salon_lantern (+ _glow, 8 frames) / salon_ribbons, salon_preview.png and the piece in data/town.json (after
`banner_post`). Run it alone (not the other art generators); the second run changes nothing."""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import art_town as T  # noqa: E402
import hut_lib  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import grain, log, save, slab, soft_shadow, to_array, V  # noqa: E402
from gen_art import hexc  # noqa: E402

OUT = T.OUT
JSON = Path(__file__).resolve().parent.parent / "data" / "town.json"
hut_lib.set_fresh()

FW, FH, GROUND = 112, 96, 84
CX = FW // 2
SC = h.SCALE
COSP, SINP = math.cos(math.radians(26.0)), math.sin(math.radians(26.0))

# ------------------------------------------------------------------ the salon's own materials (appended to the renderer's ramps)
_B = len(h.RAMPS)
CREAM, ROSE, VELVET, GLASS, BRASS = range(_B, _B + 5)
h.RAMPS += [[hexc(c) for c in row] for row in [
    ["4e3f58", "8c7a8e", "d6c6c0", "fbf0e2"],  # cream cloth, cool violet shade
    ["5a2a44", "9a4e68", "d0838f", "f2b6bc"],  # rose cloth (the mouth family, a little deeper)
    ["241038", "44206e", "6a38a8", "9a6ad8"],  # violet velvet
    ["0b0c0d", "0b0c0e", "0b0c0f", "0b0c10"],  # marker: the mirror glass (repainted)
    ["6f5020", "b48a38", "e6c468", "fff0b0"],  # brass / gold
]]
INK = (0x21, 0x15, 0x2b, 255)  # a dark plum outline for the cloth, velvet and brass (like the bark's ink, not brown)
_ink = h.ink_color
h.ink_color = lambda mat: INK if mat >= _B or mat == h.GOLD else _ink(mat)
WOODISH = T.WOODISH


def C(hx, a=255):
    return hexc(hx, a)


def P(sx, sy, hp):
    """A model point standing on the ground at (sx, sy) px from the feet point, hp px above it (so it shows at screen (sx, sy - hp) from the feet)."""
    return V(sx / SC, hp / (SC * COSP), sy / (SC * SINP))


def proj(p):
    """Absolute frame pixel (float) of a model point."""
    return (CX + p[0] * SC, GROUND - (p[1] * COSP - p[2] * SINP) * SC)


def render(m):
    return to_array(hut_lib.render(m, FW, FH, GROUND))


def over(base, top):
    img = Image.fromarray(base)
    img.alpha_composite(Image.fromarray(top))
    return np.array(img)


def lut_of(mats):
    out = {}
    for mat in mats:
        for b, c in enumerate(h.RAMPS[mat]):
            out[tuple(c[:3])] = (mat, b)
    return out


def setpx(arr, x, y, col):
    x, y = int(x), int(y)
    if 0 <= x < arr.shape[1] and 0 <= y < arr.shape[0]:
        arr[y, x] = col if len(col) == 4 else (*col, 255)


def outline(arr, ink=INK):
    """An ink pixel round every opaque pixel that touches transparency (for the hand-painted bits)."""
    a = arr[..., 3] > 0
    nb = np.zeros_like(a)
    nb[1:, :] |= a[:-1, :]
    nb[:-1, :] |= a[1:, :]
    nb[:, 1:] |= a[:, :-1]
    nb[:, :-1] |= a[:, 1:]
    out = arr.copy()
    out[nb & ~a] = ink
    return out


# ------------------------------------------------------------------ layout (px from the feet point; the code relies on these)
SEAT = (-14, 1)          # cushion centre
CHAIR_GROUND = (-14.0, 8.0)
MIRROR_GROUND = (19.0, -4.0)
YAW = -0.5               # the mirror turned 3/4 towards the chair
GL_RX, GL_RY, GL_VC = 8.2, 19.0, 44.0   # glass half width / half height / centre height above the deck (model units)
LEDGE_V = GL_VC - GL_RY - 4.6
POST_U = GL_RX + 3.7
LANTERN = (33.0, -12.5)  # where the lantern hangs (ground point under it)
BEAM_SY, BEAM_HP = -16.0, 56.5
DECK_HP = 2.0
RY_M = h.rot_y(YAW)
MO = P(MIRROR_GROUND[0], MIRROR_GROUND[1], DECK_HP)


def L(u, v, w):
    """A point in the mirror's own frame (u across the glass, v up, w out of the glass)."""
    return MO + RY_M @ V(u, v, w)


# ------------------------------------------------------------------ the background: deck, pergola, shelf, plants
def deck(m):
    """A rounded platform of planks (a soft superellipse, wide at the back where the pergola posts stand, narrower at the front)."""
    sy, k = -21.0, 0
    while sy < 9.0:
        c = sy + 1.5
        t = (c + 6.0) / 15.6
        half = 43.0 * (1.0 - abs(t) ** 4) ** 0.25 + (0.6 if k % 3 == 1 else 0.0)
        slab(m, P(-half, c, 1.0), P(half, c, 1.0), 1.5 / (SC * SINP) * 0.97, 1.2, PLANK_W if k % 2 == 0 else PLANK, (0, 1, 0), step=1.4)
        sy += 3.0
        k += 1


def pergola(m, rng):
    z = BEAM_SY / (SC * SINP)
    for sx in (-40.0, 40.0):
        x = sx / SC
        m.ell(P(sx, BEAM_SY, 1.5), (2.6, 1.6, 2.4), STONE_L)  # a footing stone
        T.upright(m, x, z, 2.0, BEAM_HP / (SC * COSP) - 1.0, 1.35, BARK, 0.93)
        log(m, P(sx, BEAM_SY, 45.5), P(sx - math.copysign(7.0, sx), BEAM_SY, 55.0), 0.75, BARK, step=0.8)  # knee braces
        m.ell(P(sx, BEAM_SY, BEAM_HP + 1.6), (1.6, 0.9, 1.6), BARK_D)
    log(m, P(-46.0, BEAM_SY, BEAM_HP), P(46.0, BEAM_SY, BEAM_HP), 1.75, BARK, step=1.0)
    for sx in (-46.5, 46.5):
        m.ell(P(sx, BEAM_SY, BEAM_HP), (1.2, 1.9, 1.9), BARK_D)
    # the lantern's hook: a little brass bracket reaching forward from the beam
    log(m, P(LANTERN[0], BEAM_SY, BEAM_HP - 0.6), P(LANTERN[0], LANTERN[1], BEAM_HP - 0.6), 0.4, IRON, step=0.5)
    m.ell(P(LANTERN[0], LANTERN[1], BEAM_HP - 1.2), (0.6, 0.8, 0.6), IRON)
    # a climbing rose on the left post, a little along the beam
    for k in range(26):
        hp = 4.0 + k * 1.75
        a = k * 1.1
        m.ell(P(-40.0 + math.cos(a) * 1.6, BEAM_SY + math.sin(a) * 0.9 + 0.6, hp), (rng.uniform(1.0, 1.6), rng.uniform(0.9, 1.3), 0.9), MOSS_L if k % 3 else MOSS)
        if k % 5 == 3:
            m.ell(P(-40.0 + math.cos(a + 0.6) * 2.0, BEAM_SY + 1.4, hp + 0.6), (0.9, 0.9, 0.7), ROSE)
    for k in range(8):
        m.ell(P(-38.0 + k * 1.6, BEAM_SY + 1.2, BEAM_HP - 1.6 - (k % 3) * 0.6), (1.3, 1.1, 0.8), MOSS_L if k % 2 else MOSS)
    m.ell(P(-35.5, BEAM_SY + 1.6, BEAM_HP - 2.8), (0.9, 0.9, 0.7), ROSE)


def shelf(m):
    zf, zb = -13.0, -17.5
    for sx in (-34.0, 6.0):
        for sy in (zf, zb):
            log(m, P(sx, sy, DECK_HP), P(sx, sy, 31.0), 0.8, PLANK, step=0.9)
        m.ell(P(sx, zf, 31.6), (1.0, 0.9, 1.0), BRASS)
    log(m, P(-34.0, zb, 30.0), P(6.0, zb, 30.0), 0.6, PLANK, step=0.8)  # back rail
    mid = (zf + zb) / 2
    for hp in (14.0, 27.0):
        slab(m, P(-35.6, mid, hp), P(7.6, mid, hp), 2.55 / (SC * SINP), 0.8, PLANK_W, (0, 1, 0), step=1.3)
    top, low = 28.0, 15.0
    # top board: folded towels, two jars, dried flowers in a jug, ribbon rolls
    for i, mat in enumerate((CREAM, ROSE, CREAM)):
        slab(m, P(-30.5 + i * 0.3, mid + 0.4, top + 0.7 + i * 1.5), P(-23.5 + i * 0.3, mid + 0.4, top + 0.7 + i * 1.5), 1.9 / (SC * SINP), 0.85, mat, (0, 1, 0), step=1.0)
    m.ell(P(-19.5, mid + 0.6, top + 1.6), (1.9, 2.0, 1.9), CLAY)
    m.ell(P(-19.5, mid + 0.6, top + 3.3), (1.6, 0.6, 1.6), BRASS)
    m.ell(P(-16.0, mid + 0.6, top + 1.3), (1.6, 1.6, 1.6), BANNER)
    m.ell(P(-16.0, mid + 0.6, top + 2.7), (1.3, 0.5, 1.3), CREAM)
    m.ell(P(-10.0, mid, top + 2.0), (2.1, 2.5, 2.1), CLAY)  # the jug of dried flowers
    m.ell(P(-10.0, mid, top + 4.2), (1.3, 0.7, 1.3), CLAY)
    for k, (dx, dh) in enumerate(((-2.6, 7.5), (-1.6, 9.0), (-0.5, 10.0), (0.6, 9.4), (1.7, 8.2), (2.6, 7.0), (0.1, 8.0))):
        m.limb(P(-10.0, mid, top + 4.4), P(-10.0 + dx, mid, top + dh), 0.22, 0.22, STRAW)
        m.ell(P(-10.0 + dx, mid, top + dh + 0.3), (0.6, 0.75, 0.6), (VELVET, STRAW, ROSE)[k % 3])
    for sx, mat in ((-4.0, ROSE), (-0.5, BANNER), (3.2, VELVET)):
        log(m, P(sx, mid - 1.4, top + 1.5), P(sx, mid + 1.4, top + 1.5), 1.75, mat, step=0.7)
        m.ell(P(sx, mid + 1.7, top + 1.5), (0.6, 0.6, 0.4), CREAM)
    # lower board: towels, a basket, bottles
    for i, mat in enumerate((ROSE, CREAM)):
        slab(m, P(-30.0, mid + 0.4, low + 0.7 + i * 1.5), P(-23.0, mid + 0.4, low + 0.7 + i * 1.5), 1.9 / (SC * SINP), 0.85, mat, (0, 1, 0), step=1.0)
    for k in range(4):
        m.ell(P(-15.5, mid + 0.4, low + 0.6 + k * 1.0), (3.4, 0.75, 3.0), STRAW)
    m.ell(P(-15.5, mid + 0.4, low + 4.2), (3.5, 0.6, 3.1), STRAW)
    m.ell(P(-16.2, mid + 0.4, low + 4.9), (2.2, 1.1, 1.8), CREAM)
    m.ell(P(-5.5, mid + 0.6, low + 2.0), (1.3, 2.4, 1.3), LINEN)
    m.ell(P(-5.5, mid + 0.6, low + 4.6), (0.6, 0.9, 0.6), STRAW)
    m.ell(P(-2.0, mid + 0.6, low + 1.4), (1.7, 1.6, 1.7), CLAY)
    m.ell(P(1.8, mid + 0.6, low + 1.8), (1.3, 2.1, 1.3), VELVET)
    m.ell(P(1.8, mid + 0.6, low + 4.2), (0.6, 0.7, 0.6), BRASS)


def plants(m, rng):
    # a fern in a bulbous clay pot
    fx, fy = -29.0, -7.0
    m.ell(P(fx, fy, DECK_HP + 3.2), (3.6, 3.6, 3.5), CLAY)
    m.ell(P(fx, fy, DECK_HP + 6.2), (2.7, 0.9, 2.6), CLAY)
    m.ell(P(fx, fy, DECK_HP + 6.9), (3.1, 0.7, 3.0), CLAY)
    m.ell(P(fx, fy, DECK_HP + 7.2), (2.4, 0.4, 2.3), SOIL)
    base = P(fx, fy, DECK_HP + 7.0)
    for k in range(11):
        az = k / 11 * math.tau + 0.3
        back = math.sin(az) < -0.2
        reach = rng.uniform(8.0, 11.0)
        rise = rng.uniform(9.0, 14.0)
        prev = base
        for i in range(1, 9):
            t = i / 8
            r = reach * t
            hgt = rise * math.sin(t * math.pi * 0.72)
            p = base + V(math.cos(az) * r, hgt, math.sin(az) * r * 0.8)
            m.limb(prev, p, 0.3, 0.3, MOSS)
            if i > 1:
                side = V(-math.sin(az), 0, math.cos(az)) * 1.0
                lw = 1.2 * (1.0 - 0.5 * t)
                m.ell(p + side, (lw, 0.55, lw), MOSS if back else MOSS_L)
                m.ell(p - side, (lw, 0.55, lw), MOSS if back else (MOSS_L if i % 2 else MOSS))
            prev = p
    # a smaller pot with flowers
    gx, gy = -37.0, -0.5
    m.ell(P(gx, gy, DECK_HP + 2.2), (2.6, 2.6, 2.5), CLAY)
    m.ell(P(gx, gy, DECK_HP + 4.4), (2.9, 0.6, 2.8), CLAY)
    for k in range(7):
        a = k / 7 * math.tau
        m.ell(P(gx + math.cos(a) * 1.4, gy + math.sin(a) * 0.6, DECK_HP + 6.0 + (k % 2)), (1.4, 1.1, 1.2), MOSS_L if k % 2 else MOSS)
    for k, (dx, dsy, dh, mat) in enumerate(((-1.5, 0.3, 8.6, ROSE), (1.3, 0.0, 9.2, CREAM), (0.0, 0.6, 10.0, ROSE), (2.0, 0.8, 7.6, VELVET), (-2.4, 0.4, 7.4, CREAM))):
        m.ell(P(gx + dx, gy + dsy, DECK_HP + dh), (1.1, 1.0, 1.0), mat)


def basket(m):
    bx, by = 36.0, 3.5
    for k in range(4):
        m.ell(P(bx, by, DECK_HP + 0.8 + k * 1.0), (3.9, 0.8, 3.5), STRAW)
    m.ell(P(bx, by, DECK_HP + 4.4), (4.1, 0.7, 3.7), STRAW)
    log(m, P(bx - 2.6, by - 0.4, DECK_HP + 5.6), P(bx + 1.0, by - 0.8, DECK_HP + 6.4), 1.6, CREAM, step=0.7)
    log(m, P(bx - 0.6, by + 0.6, DECK_HP + 5.4), P(bx + 3.0, by + 0.2, DECK_HP + 5.9), 1.5, ROSE, step=0.7)


# ------------------------------------------------------------------ the rug (painted on the deck)
RUG_C, RUG_RX, RUG_RY = (CX - 14.0, GROUND + 2.9), 19.0, 5.6
RUG = {"edge": C("241038"), "violet": C("44206e"), "violet_l": C("6a38a8"), "teal_d": C("1b4750"), "teal": C("2f7a80"), "teal_l": C("62bcb4"),
       "cream": C("d6c6c0"), "cream_l": C("fbf0e2"), "lilac": C("9a6ad8")}
RUG_DARK = {RUG["violet"][:3]: RUG["edge"], RUG["violet_l"][:3]: RUG["violet"], RUG["teal"][:3]: RUG["teal_d"], RUG["teal_l"][:3]: RUG["teal"],
            RUG["cream"][:3]: C("8c7a8e"), RUG["cream_l"][:3]: RUG["cream"], RUG["lilac"][:3]: RUG["violet_l"], RUG["teal_d"][:3]: RUG["edge"]}


def paint_rug(arr):
    deck_cols = lut_of((PLANK, PLANK_W))
    cx, cy = RUG_C
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            dx, dy = (x + 0.5 - cx) / RUG_RX, (y + 0.5 - cy) / RUG_RY
            r = math.sqrt(dx * dx + dy * dy)
            if r > 1.0 or arr[y, x, 3] == 0 or tuple(int(v) for v in arr[y, x, :3]) not in deck_cols:
                continue
            ang = math.atan2(dy, dx)
            if r > 0.9:
                col = RUG["edge"]
            elif r > 0.76:
                col = RUG["teal_l"] if int((ang + math.pi) / math.tau * 28) % 3 == 0 else RUG["violet_l"]
            elif r > 0.66:
                col = RUG["violet"]
            elif r > 0.46:
                col = RUG["teal"] if (x + y) % 2 or r < 0.52 else RUG["teal_d"]
                if int((ang + math.pi) / math.tau * 16) % 4 == 0 and 0.52 < r < 0.62:
                    col = RUG["cream"]
            elif r > 0.36:
                col = RUG["violet"]
            else:
                diamond = abs(dx) * 1.0 + abs(dy) * 1.0
                col = RUG["lilac"] if diamond < 0.18 else (RUG["violet_l"] if diamond < 0.3 else RUG["violet"])
            if dy > 0.55 and r > 0.66 and col not in (RUG["edge"],):  # the near edge a little darker: the rug's thickness
                col = RUG_DARK.get(col[:3], col)
            arr[y, x] = col
    # tassels at both ends
    for sgn in (-1, 1):
        ex = int(cx + sgn * RUG_RX) - (1 if sgn > 0 else 0)
        for k, yy in enumerate((int(cy) - 1, int(cy) + 1)):
            setpx(arr, ex + sgn, yy, RUG["cream"])
            setpx(arr, ex + 2 * sgn, yy, RUG["cream_l"] if sgn < 0 else RUG["cream"])
        setpx(arr, ex + sgn, int(cy), RUG["cream_l"])


def shade_deck(arr, cx, cy, rx, ry):
    """Contact shadow on the deck/rug: one step darker inside a small ellipse."""
    deck = lut_of((PLANK, PLANK_W))
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if not (0 <= x < FW and 0 <= y < FH) or arr[y, x, 3] == 0:
                continue
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 > 1.0:
                continue
            key = tuple(int(v) for v in arr[y, x, :3])
            if key in deck:
                mat, b = deck[key]
                arr[y, x, :3] = h.RAMPS[mat][max(0, b - 1)][:3]
            elif key in RUG_DARK:
                arr[y, x] = RUG_DARK[key]


# ------------------------------------------------------------------ the mirror
def mirror_model():
    m = h.Model()
    for su in (-1, 1):
        u = su * POST_U
        log(m, L(u, 0.4, 0.0), L(u, GL_VC + 3.0, 0.0), 0.95, PLANK_W, step=0.9)
        m.ell(L(u, GL_VC + 4.2, 0.0), (1.2, 1.2, 1.2), BRASS)  # finials
        m.ell(L(u, GL_VC + 5.6, 0.0), (0.6, 0.8, 0.6), BRASS)
        slab(m, L(u, 0.8, -2.8), L(u, 0.8, 2.8), 1.0, 0.8, PLANK_W, (0, 1, 0), step=1.0)  # the feet
        for w in (-3.0, 3.0):
            m.ell(L(u, 0.8, w), (1.0, 0.9, 0.9), BRASS)
        m.ell(L(su * (GL_RX + 2.5), GL_VC, 0.0), (1.0, 1.0, 1.0), BRASS)  # pivot pins
    # a low board between the posts with a wash basin and a rose pitcher
    slab(m, L(-POST_U, 9.0, 0.6), L(POST_U, 9.0, 0.6), 2.7, 0.6, PLANK_W, (0, 1, 0), step=1.0)
    m.ell(L(-3.2, 11.0, 0.8), (3.6, 1.5, 2.6), CREAM, R=RY_M)
    m.ell(L(-3.2, 12.3, 0.8), (2.8, 0.4, 2.0), BANNER, R=RY_M)  # the water
    m.ell(L(4.4, 11.9, 0.6), (1.7, 2.3, 1.7), ROSE)
    m.ell(L(4.4, 14.6, 0.6), (1.1, 0.6, 1.1), ROSE)
    m.ell(L(3.1, 14.4, 0.6), (0.7, 0.5, 0.6), ROSE)  # spout
    m.limb(L(5.8, 13.8, 0.6), L(6.2, 11.6, 0.6), 0.4, 0.4, ROSE)  # handle
    m.ell(L(0.0, GL_VC, -0.4), (GL_RX + 0.4, GL_RY + 0.4, 0.5), PLANK, R=RY_M)  # backing
    m.ell(L(0.0, GL_VC, 0.15), (GL_RX, GL_RY, 0.35), GLASS, R=RY_M)
    n = 110
    for k in range(n):
        a = k / n * math.tau
        m.ell(L(math.cos(a) * (GL_RX + 1.25), GL_VC + math.sin(a) * (GL_RY + 1.25), 0.25), (1.3, 1.3, 1.1), BRASS)
    # leaf scrolls: a crest with a teal gem, small curls at the shoulders and hips, one under the glass
    m.ell(L(0.0, GL_VC + GL_RY + 3.2, 0.3), (2.2, 1.6, 0.7), BRASS, R=RY_M)
    for su in (-1, 1):
        m.ell(L(su * 2.7, GL_VC + GL_RY + 2.2, 0.3), (1.8, 1.0, 0.6), BRASS, R=RY_M @ h.rot_x(0.0))
        m.ell(L(su * 4.6, GL_VC + GL_RY + 0.6, 0.3), (1.0, 0.8, 0.5), BRASS, R=RY_M)
        for a in (math.radians(32), math.radians(-30)):
            c = (math.cos(a) * (GL_RX + 2.6) * su, math.sin(a) * (GL_RY + 2.6))
            m.ell(L(c[0], GL_VC + c[1], 0.3), (0.95, 0.9, 0.5), BRASS, R=RY_M)
    m.ell(L(0.0, GL_VC + GL_RY + 3.3, 1.0), (0.85, 0.85, 0.6), h.TEAL, kind="emit")
    m.ell(L(0.0, GL_VC - GL_RY - 2.4, 0.3), (1.8, 1.1, 0.6), BRASS, R=RY_M)
    # the ledge, and its bracket
    slab(m, L(-POST_U, LEDGE_V, 1.6), L(POST_U, LEDGE_V, 1.6), 2.9, 0.65, PLANK_W, (0, 1, 0), step=1.0)
    m.ell(L(0.0, LEDGE_V - 1.5, 1.0), (1.6, 1.4, 0.8), BRASS, R=RY_M)
    return m


GLASS_SKY = ["34185e", "6636ad", "9468ee", "cbaaff", "78f4e6", "3cc0c6", "2a8c94"]
GLASS_STOPS = [0.0, 0.22, 0.42, 0.56, 0.64, 0.76, 0.9]
DARKER = {"34185e": "241038", "6636ad": "34185e", "9468ee": "6636ad", "cbaaff": "9468ee", "78f4e6": "3cc0c6", "3cc0c6": "2a8c94", "2a8c94": "1b4750", "d0fff8": "78f4e6"}


def paint_glass(arr):
    """The glass: a soft dusk sky, violet at the top to turquoise at the horizon, distant hills, two stars, a resting shine. Returns its mask and box."""
    glass_cols = {tuple(c[:3]) for c in h.RAMPS[GLASS]}
    mask = np.zeros(arr.shape[:2], bool)
    for y in range(FH):
        for x in range(FW):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in glass_cols:
                mask[y, x] = True
    ys, xs = np.nonzero(mask)
    top, bot, left, right = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
    hgt = bot - top
    names = np.empty(arr.shape[:2], object)
    for y, x in zip(ys, xs):
        t = (y - top) / hgt
        i = max(k for k, s in enumerate(GLASS_STOPS) if t >= s)
        if i + 1 < len(GLASS_STOPS):  # one dithered row before each band edge
            edge = top + GLASS_STOPS[i + 1] * hgt
            if edge - 1.0 <= y < edge and (x // 2 + y) % 2 == 0:
                i += 1
        names[y, x] = GLASS_SKY[i]
    # distant hills along the bottom
    for x in range(left, right + 1):
        hill = bot - 2.2 - 1.3 * math.sin((x - left) * 0.55 + 0.8) - 0.8 * math.sin((x - left) * 1.3)
        for y in range(int(hill), bot + 1):
            if mask[y, x]:
                names[y, x] = "34185e" if y > hill + 0.6 else "6636ad"
    # the frame's shade along the upper left inside edge
    for y, x in zip(ys, xs):
        if (not mask[y - 1, x]) or (not mask[y, x - 1]):
            names[y, x] = DARKER.get(names[y, x], names[y, x])
    cxg = (left + right) / 2
    for (fx, fy, col) in ((-0.22, 0.12, "cbaaff"), (0.18, 0.2, "d0fff8"), (0.3, 0.07, "9468ee"), (-0.05, 0.3, "cbaaff")):
        x, y = int(cxg + fx * (right - left)), int(top + fy * hgt)
        if mask[y, x]:
            names[y, x] = col
    for y, x in zip(ys, xs):
        arr[y, x] = C(names[y, x])
    # a resting shine: two short slanted strokes high on the left
    for k in range(4):
        for (x, y) in ((left + 3 + k, top + 11 - k), (left + 5 + k // 2, top + 15 - k)):
            if k < 3 or (x, y) == (left + 3 + k, top + 11 - k):
                if 0 <= y < FH and mask[y, x]:
                    arr[y, x] = C("d0fff8") if k in (1, 2) else C("cbaaff")
    return mask, (left, right, top, bot)


def ledge_point(u, w=1.6, up=0.0):
    x, y = proj(L(u, LEDGE_V + 0.65 + up, w))
    return int(round(x)), int(math.floor(y))


def paint_ledge(arr):
    """Comb, brush, scissors, three little bottles (one teal, glowing), a jar and a tiny vase with a flower, on the mirror's ledge. Returns the points the glow uses."""
    pts = {}
    ink = INK
    # back row (standing): positions from the far (left) to the near (right) end
    x, y = ledge_point(-8.6, -0.2)  # tiny vase with a rose
    for (dx, dy, c) in ((0, 0, "9a4e68"), (1, 0, "5a2a44"), (0, -1, "d0838f"), (1, -1, "9a4e68"), (0, -2, "f2b6bc"), (1, -2, "9a4e68")):
        setpx(arr, x + dx, y + dy, C(c))
    for dy in (-3, -4, -5):
        setpx(arr, x + (1 if dy == -3 else 0), y + dy, C("3a7550"))
    setpx(arr, x + 1, y - 4, C("74b268"))
    for (dx, dy, c) in ((-1, -6, "d0838f"), (0, -6, "f2b6bc"), (1, -6, "d0838f"), (0, -7, "d0838f"), (0, -5, "9a4e68")):
        setpx(arr, x + dx, y + dy, C(c))
    for (dx, dy) in ((-1, -1), (-1, 0), (2, 0), (2, -1), (2, -2), (-1, -2), (-2, -6), (2, -6), (-1, -7), (1, -7), (0, -8)):
        if arr[y + dy, x + dx, :3].tolist() != [0, 0, 0] or True:
            pass
    pts["vase"] = (x, y - 6)
    x, y = ledge_point(-5.0, -0.2)  # tall violet bottle with a cork
    for dy in range(0, 5):
        setpx(arr, x, y - dy, C("9468ee" if dy in (2, 3) else "6636ad"))
        setpx(arr, x + 1, y - dy, C("6636ad" if dy in (2, 3) else "34185e"))
    setpx(arr, x, y - 3, C("cbaaff"))
    setpx(arr, x, y - 5, C("a08844"))
    setpx(arr, x, y - 6, C("d4bc78"))
    setpx(arr, x + 1, y - 5, ink)
    pts["bottle_violet"] = (x, y - 3)
    x, y = ledge_point(-1.4, -0.2)  # the round teal flask, glowing
    for (dx, dy, c) in ((-1, 0, "2a8c94"), (0, 0, "3cc0c6"), (1, 0, "2a8c94"), (-1, -1, "3cc0c6"), (0, -1, "78f4e6"), (1, -1, "3cc0c6"),
                        (-1, -2, "78f4e6"), (0, -2, "d0fff8"), (1, -2, "3cc0c6"), (0, -3, "78f4e6"), (0, -4, "3cc0c6")):
        setpx(arr, x + dx, y + dy, C(c))
    setpx(arr, x, y - 5, C("b48a38"))
    pts["flask"] = (x, y - 2)
    x, y = ledge_point(2.4, -0.2)  # a cream jar with a brass lid
    for (dx, dy, c) in ((0, 0, "8c7a8e"), (1, 0, "8c7a8e"), (2, 0, "4e3f58"), (0, -1, "fbf0e2"), (1, -1, "d6c6c0"), (2, -1, "8c7a8e"),
                        (0, -2, "e6c468"), (1, -2, "fff0b0"), (2, -2, "b48a38")):
        setpx(arr, x + dx, y + dy, C(c))
    pts["jar"] = (x + 1, y - 2)
    x, y = ledge_point(6.4, -0.2)  # a squat rose bottle with a gold stopper
    for (dx, dy, c) in ((0, 0, "9a4e68"), (1, 0, "5a2a44"), (0, -1, "f2b6bc"), (1, -1, "9a4e68"), (0, -2, "d0838f"), (1, -2, "9a4e68"),
                        (0, -3, "e6c468"), (1, -3, "b48a38")):
        setpx(arr, x + dx, y + dy, C(c))
    pts["bottle_rose"] = (x, y - 1)
    # front row (lying): comb, scissors, brush
    x, y = ledge_point(-7.4, 3.4)
    for dx in range(5):
        setpx(arr, x + dx, y - 1, C("e2d2c0" if dx < 3 else "b8a8a0"))
        if dx % 2 == 0:
            setpx(arr, x + dx, y, C("8c7a8e"))
    x, y = ledge_point(-0.6, 3.6)  # scissors: two rings and the blades
    for (dx, dy, c) in ((0, 0, "e6c468"), (1, -1, "b48a38"), (0, -1, "fff0b0"), (2, 0, "e6c468"), (3, -1, "e6c468"), (4, -1, "fff0b0"), (3, 0, "b48a38"), (2, -1, "6f5020")):
        setpx(arr, x + dx, y + dy, C(c))
    pts["scissors"] = (x + 4, y - 1)
    x, y = ledge_point(5.6, 3.4)  # brush: a wooden back with cream bristles, a short handle
    for (dx, dy, c) in ((0, -1, "bd9888"), (1, -1, "8c6a62"), (2, -1, "8c6a62"), (0, 0, "fbf0e2"), (1, 0, "d6c6c0"), (2, 0, "d6c6c0"), (3, -1, "5e4448"), (4, -1, "8c6a62")):
        setpx(arr, x + dx, y + dy, C(c))
    return pts


def mirror_layer():
    arr = grain(render(mirror_model()), 141, amount=0.4, mats=WOODISH)
    mask, box = paint_glass(arr)
    pts = paint_ledge(arr)
    return arr, mask, box, pts


# ------------------------------------------------------------------ the chair
def chair_model():
    m = h.Model()
    cx, cy = CHAIR_GROUND
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        m.limb(P(cx + math.cos(a) * 0.8, cy + math.sin(a) * 0.3, DECK_HP + 2.2), P(cx + math.cos(a) * 4.0, cy + math.sin(a) * 1.0, DECK_HP + 0.5), 0.95, 0.7, BARK)
        m.ell(P(cx + math.cos(a) * 4.1, cy + math.sin(a) * 1.0, DECK_HP + 0.4), (0.8, 0.6, 0.8), BRASS)
    log(m, P(cx, cy, DECK_HP + 1.6), P(cx, cy, DECK_HP + 4.2), 0.95, BRASS, step=0.6)
    m.ell(P(cx, cy, DECK_HP + 2.1), (1.6, 0.8, 1.6), BRASS)
    m.ell(P(cx, cy, DECK_HP + 3.7), (7.6, 1.0, 5.8), BARK)                # the seat
    m.ell(P(cx, cy, DECK_HP + 5.0), (7.0, 1.8, 5.1), VELVET)              # the cushion: centre at (-14, +1)
    # the low, curved backrest of a little tub chair: a wooden rail sweeping from the arms (low, at the cushion's sides) up to the back, velvet inside
    rx, rz = 7.3, 5.3
    zc = cy / (SC * SINP)

    def arc(th, hp):
        return V(cx / SC + math.cos(th) * rx, hp / (SC * COSP), zc + math.sin(th) * rz)

    def rail_hp(th):
        s = max(0.0, 1.0 - abs(math.degrees(th) - 270.0) / 108.0)
        return DECK_HP + 6.4 + 12.0 * math.sin(s * math.pi / 2) ** 0.8

    prev = None
    for k in range(43):
        th = math.radians(164 + k * 212 / 42)
        p = arc(th, rail_hp(th))
        if prev is not None:
            m.limb(prev, p, 1.0, 1.0, PLANK_W)
        prev = p
    # the velvet back: one plump pad inside the rail
    hp_lo, hp_hi = DECK_HP + 4.6, rail_hp(math.radians(270)) - 0.6
    m.ell(V(cx / SC, (hp_lo + hp_hi) / 2 / (SC * COSP), zc - rz * 0.62), (rx * 0.86, (hp_hi - hp_lo) / 2 / (SC * COSP), rz * 0.42), VELVET)
    for side in (-1, 1):  # the pad wraps a little round the sides
        m.ell(V(cx / SC + side * rx * 0.7, (hp_lo + DECK_HP + 12.0) / 2 / (SC * COSP), zc - rz * 0.2), (1.6, (DECK_HP + 12.0 - hp_lo) / 2 / (SC * COSP), rz * 0.5), VELVET)
    for th in (math.radians(164), math.radians(376)):
        m.ell(arc(th, rail_hp(th)), (0.95, 0.95, 0.95), BRASS)
    return m


def chair_layer():
    arr = grain(render(chair_model()), 151, amount=0.35, mats=WOODISH)
    # a tufting button on the cushion and the back pad, a sheen on the velvet's lit edge
    velvet = {tuple(c[:3]) for c in h.RAMPS[VELVET]}
    for dx in (-3, 3):  # channel tufting: two soft seams down the back
        for dy in range(-12, -1):
            x, y = CX + SEAT[0] + dx, GROUND + dy
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in velvet:
                key = tuple(int(v) for v in arr[y, x, :3])
                b = [tuple(c[:3]) for c in h.RAMPS[VELVET]].index(key)
                arr[y, x, :3] = h.RAMPS[VELVET][max(0, b - 1)][:3]
    return arr


# ------------------------------------------------------------------ parts
def canopy_part():
    """The sail under the beam: cream cloth gathered in three swags, a scalloped rose hem, little rose ties with tassels at the gathers."""
    m = h.Model()
    z = -15.0
    gathers = [-38.0, -19.0, 0.0, 19.0, 38.0]
    top = BEAM_HP - 1.8
    x = -38.0
    while x <= 38.0:
        j = max(i for i, g in enumerate(gathers) if g <= x + 1e-6)
        j = min(j, len(gathers) - 2)
        t = (x - gathers[j]) / (gathers[j + 1] - gathers[j])
        sag = 2.4 * math.sin(t * math.pi)
        bulge = 0.9 * math.sin(t * math.pi)
        bottom = top - 5.2 - sag
        fold = 0.0
        slab(m, P(x, z + fold, top), P(x, z + bulge + fold, bottom), 0.75 / SC, 0.5, CREAM, (0, 0, 1), step=0.8)
        if abs((x * 2) % 3.0) < 0.6:  # the scallops of the rose hem
            m.ell(P(x, z + bulge + 0.4, bottom - 0.4), (1.5 / SC, 1.2, 0.5), ROSE)
        x += 0.5
    for g in gathers:
        m.ell(P(g, z + 0.6, top - 0.8), (1.2, 1.3, 0.8), ROSE)
        m.limb(P(g, z + 0.8, top - 1.8), P(g + 0.3, z + 0.8, top - 5.4), 0.35, 0.35, ROSE)
        m.ell(P(g + 0.3, z + 0.8, top - 5.9), (0.7, 0.9, 0.7), ROSE)
    return m


def lantern_part():
    m = h.Model()
    lx, lz = LANTERN
    hp0 = BEAM_HP - 1.6
    m.limb(P(lx, lz, hp0), P(lx, lz, hp0 - 2.6), 0.35, 0.35, IRON)
    m.ell(P(lx, lz, hp0 - 3.0), (0.9, 0.7, 0.9), BRASS)
    m.ell(P(lx, lz, hp0 - 3.8), (2.0, 0.7, 2.0), BRASS)
    m.ell(P(lx, lz, hp0 - 4.5), (2.5, 0.6, 2.5), BRASS)
    m.ell(P(lx, lz, hp0 - 7.4), (1.75, 2.5, 1.75), FIRE, kind="emit")
    for a in (0.35, 1.92, 3.49, 5.06):
        m.limb(P(lx, lz, hp0 - 4.8) + V(math.cos(a) * 2.1, 0, math.sin(a) * 2.1), P(lx, lz, hp0 - 10.0) + V(math.cos(a) * 2.1, 0, math.sin(a) * 2.1), 0.3, 0.3, BRASS)
    m.ell(P(lx, lz, hp0 - 10.3), (2.4, 0.6, 2.4), BRASS)
    m.ell(P(lx, lz, hp0 - 11.3), (0.8, 0.9, 0.8), BRASS)
    return m


RIBBONS = [  # x px from the feet point, length, (light, mid, dark)
    (-29.0, 9, ("f2b6bc", "d0838f", "9a4e68")),
    (-26.0, 12, ("9a6ad8", "6a38a8", "44206e")),
    (-12.0, 8, ("62bcb4", "2f7a80", "1b4750")),
    (-7.0, 11, ("fbf0e2", "d6c6c0", "8c7a8e")),
    (-3.0, 7, ("e6c468", "b48a38", "6f5020")),
    (2.0, 10, ("f2b6bc", "d0838f", "9a4e68")),
]


def canopy_folds(crop, ax):
    """Soft folds drawn into the sail: from each gather two short shaded creases fanning out, a lit fold in the middle of each swag."""
    out = crop.copy()
    cream = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[CREAM])}

    def tone(x, y, b):
        if 0 <= x < out.shape[1] and 0 <= y < out.shape[0] and out[y, x, 3]:
            key = tuple(int(v) for v in out[y, x, :3])
            if key in cream and cream[key] >= 1:
                out[y, x, :3] = h.RAMPS[CREAM][b][:3]

    gathers = [-38.0, -19.0, 0.0, 19.0, 38.0]
    for g in gathers:
        gx = int(round(CX + g - ax))
        for side in (-1, 1):
            for r in range(3):
                tone(gx + side * 2, 2 + r, 2)
    for a, b in zip(gathers[:-1], gathers[1:]):
        mx = int(round(CX + (a + b) / 2 - ax))
        for r in range(2, 7):
            tone(mx - 1, r, 3)
            tone(mx + 3, r + 1, 2) if r < 5 else None
    return out


def petals(arr):
    """A few rose petals blown onto the deck."""
    deck = lut_of((PLANK, PLANK_W))
    for dx, dy, c in ((3, 5, "d0838f"), (7, 8, "f2b6bc"), (11, 3, "d0838f"), (27, 7, "d0838f"), (-31, 6, "f2b6bc"), (1, -3, "d0838f")):
        x, y = CX + dx, GROUND + dy
        if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in deck:
            arr[y, x] = C(c)
            if tuple(int(v) for v in arr[y, x + 1, :3]) in deck:
                arr[y, x + 1] = C("9a4e68")


def ribbons_part():
    """Ribbons hanging from the front edge of the shelf's top board: 2 px wide, a gentle wave, a swallow-tailed end; hand-painted."""
    arr = np.zeros((FH, FW, 4), np.uint8)
    edge = proj(P(0.0, -15.25 + 2.55, 27.0 - 0.9))[1]
    y0 = int(round(edge))
    for k, (rx, length, (lt, md, dk)) in enumerate(RIBBONS):
        x0 = int(CX + rx)
        setpx(arr, x0, y0, C(dk))
        setpx(arr, x0 + 1, y0, C(dk))
        for i in range(1, length):
            wave = 1 if (i + k) % 6 in (3, 4) else 0
            x = x0 + wave
            setpx(arr, x, y0 + i, C(lt if i % 4 else md))
            setpx(arr, x + 1, y0 + i, C(md if i % 4 else dk))
        x = x0 + (1 if (length + k) % 6 in (3, 4) else 0)
        setpx(arr, x, y0 + length, C(md))
        setpx(arr, x + 1, y0 + length, C(dk))
        setpx(arr, x, y0 + length + 1, C(md))
        setpx(arr, x + 1, y0 + length + 1, C(dk))
        arr[y0 + length + 1, x + 1] = 0 if k % 2 else arr[y0 + length + 1, x + 1]  # the swallow tail: one notch
        if k % 2 == 0:
            arr[y0 + length + 1, x] = 0
    arr = outline(arr)
    arr[:y0, :] = 0  # nothing above the board edge (it would sit on the wood)
    ys, xs = np.nonzero(arr[..., 3])
    x0, y0c = int(xs.min()), int(ys.min())
    crop = arr[y0c:int(ys.max()) + 1, x0:int(xs.max()) + 1]
    save(OUT / "salon_ribbons.png", crop)
    T.INFO["salon_ribbons"] = {"at": [x0, y0c], "frame": [crop.shape[1], crop.shape[0]]}
    return crop, (x0, y0c)


def lantern_glow(crop):
    fire = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[FIRE])}
    hh, ww = crop.shape[:2]
    sheet = np.zeros((hh, ww * 8, 4), np.uint8)
    flick = [1.0, 0.86, 0.95, 0.72, 1.0, 0.9, 0.8, 0.96]
    for f in range(8):
        for y in range(hh):
            for x in range(ww):
                key = tuple(int(v) for v in crop[y, x, :3])
                if crop[y, x, 3] and key in fire:
                    b = fire[key]
                    if flick[f] < 0.8 and b == 3:
                        b = 2
                    col = h.RAMPS[FIRE][min(3, b + (1 if flick[f] > 0.97 and b == 2 and (x + y + f) % 2 == 0 else 0))]
                    sheet[y, x + f * ww] = (*col[:3], int(255 * min(1.0, 0.55 + 0.45 * flick[f])))
                elif crop[y, x, 3] and key in {tuple(c[:3]) for c in h.RAMPS[BRASS][2:]}:  # the brass catching the flame
                    sheet[y, x + f * ww] = (*h.RAMPS[BRASS][3][:3], int(70 * flick[f]))
    return sheet


# ------------------------------------------------------------------ the base's glow sheet
def base_glow(base, mask, box, pts, mirror_arr):
    left, right, top, bot = box
    frames = []
    brass = {tuple(c[:3]): b for b, c in enumerate(h.RAMPS[BRASS])}
    teal = {tuple(c[:3]) for c in h.RAMPS[h.TEAL]}
    gcx, gcy = (left + right) / 2, (top + bot) / 2
    # the rim: the frame's lit brass pixels round the glass (not the posts and feet below it)
    rim = []
    for y in range(top - 5, bot + 4):
        for x in range(left - 5, right + 6):
            if 0 <= y < FH and 0 <= x < FW and mirror_arr[y, x, 3] and not mask[y, x]:
                key = tuple(int(v) for v in mirror_arr[y, x, :3])
                d = ((x + 0.5 - gcx) / ((right - left) / 2 + 3.5)) ** 2 + ((y + 0.5 - gcy) / ((bot - top) / 2 + 3.5)) ** 2
                if key in brass and brass[key] >= 2 and d <= 1.25:
                    rim.append((math.atan2(y - gcy, x - gcx), x, y, brass[key]))
    rim.sort()
    sweep = [None, None, None, None, None, None, None, None]
    lo, hi = left + 0.5 * top - 2, right + 0.5 * bot + 2
    for f in range(4):
        sweep[f] = lo + (hi - lo) * (f + 0.5) / 4
    twinkle = {2: "bottle_violet", 5: "bottle_rose", 7: "jar", 3: "scissors", 6: "vase"}
    for f in range(8):
        g = np.zeros((FH, FW, 4), np.uint8)
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):  # the glass glows softly (its dusk sky stays at night)
            g[y, x] = (*base[y, x, :3], 105)
        if sweep[f] is not None:
            for y, x in zip(ys, xs):
                d = (x + 0.5 * y) - sweep[f]
                if -1.0 <= d < 1.0:
                    g[y, x] = (*C("d0fff8")[:3], 235)
                elif 2.0 <= d < 3.0:
                    g[y, x] = (*C("78f4e6")[:3], 150)
                elif -2.5 <= d < -1.0:
                    g[y, x] = (*C("cbaaff")[:3], 120)
        for i, (_, x, y, b) in enumerate(rim):  # the rim's soft glimmer and one spark running round it
            g[y, x] = (*base[y, x, :3], 90 if b == 2 else 140)
        if rim:
            n = len(rim)
            head = int((f / 8) * n)
            for d, a in ((0, 255), (1, 170), (-1, 170), (2, 90)):
                _, x, y, _ = rim[(head + d) % n]
                g[y, x] = (*C("fff0b0")[:3], a)
        for y in range(FH):  # the crest's gem and the teal flask always glow
            for x in range(FW):
                if base[y, x, 3] and tuple(int(v) for v in base[y, x, :3]) in teal and (y < top + 2 or abs(x - pts["flask"][0]) <= 1 and abs(y - pts["flask"][1]) <= 3):
                    g[y, x] = base[y, x]
        fx, fy = pts["flask"]
        for (dx, dy) in ((-1, 0), (0, 0), (1, 0), (-1, -1), (0, -1), (1, -1), (-1, 1), (0, 1), (1, 1), (0, -2), (0, 2)):
            if base[fy + dy, fx + dx, 3]:
                g[fy + dy, fx + dx] = (*base[fy + dy, fx + dx, :3], 255)
        if f in (1, 4):  # the flask breathes: a brighter core every few frames
            g[fy, fx] = (*C("d0fff8")[:3], 255)
            g[fy - 1, fx] = (*C("d0fff8")[:3], 255)
        if f in twinkle:  # one of the other bottles flashes: a little four-pointed star
            sx, sy = pts[twinkle[f]]
            g[sy, sx] = (*C("fff0b0")[:3], 255)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                g[sy + dy, sx + dx] = (*C("fff0b0")[:3], 150)
        frames.append(g)
    return np.concatenate(frames, axis=1)


# ------------------------------------------------------------------ json
def put_piece(piece, entry, after):
    """Put the piece into data/town.json right after `after`, as a text edit (the rest of the file keeps its hand-made formatting; a second run replaces it)."""
    raw = JSON.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")
    block = f'  "{piece}": ' + json.dumps(entry, indent=1, ensure_ascii=False).replace("\n", "\n  ")
    key = f'\n  "{piece}": {{'
    if key in text:
        start = text.index(key) + 1
        end = text.index("\n  }", start) + 4
        text = text[:start] + block + text[end:]
    else:
        start = text.index(f'\n  "{after}": {{')
        end = text.index("\n  }", start) + 4
        text = text[:end] + ",\n" + block + text[end:]
    data = json.loads(text)
    keys = list(data["pieces"])
    assert keys.index(piece) == keys.index(after) + 1 and data["pieces"][piece] == entry
    JSON.write_bytes(text.replace("\n", nl).encode("utf-8"))


# ------------------------------------------------------------------ main
def make():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = hut_lib.rng_for(161)
    m = h.Model()
    deck(m)
    pergola(m, rng)
    shelf(m)
    plants(m, rng)
    back = grain(render(m), 161, amount=0.45, mats=WOODISH)
    paint_rug(back)
    shade_deck(back, CX - 29.0, GROUND - 7.0, 5.0, 1.8)   # under the fern
    shade_deck(back, CX - 37.0, GROUND - 0.5, 3.6, 1.4)   # under the flower pot
    shade_deck(back, CX + MIRROR_GROUND[0], GROUND + MIRROR_GROUND[1] + 0.5, 12.0, 3.2)
    shade_deck(back, CX + CHAIR_GROUND[0], GROUND + CHAIR_GROUND[1] + 0.3, 6.5, 1.8)
    shade_deck(back, CX + 36.0, GROUND + 3.8, 5.0, 1.6)
    mir, mask, box, pts = mirror_layer()
    base = over(back, mir)
    bm = h.Model()
    basket(bm)
    bk = render(bm)
    straw = lut_of((STRAW,))
    for y in range(FH):  # wicker: the straw woven in little offset strokes
        for x in range(FW):
            key = tuple(int(v) for v in bk[y, x, :3])
            if bk[y, x, 3] and key in straw and (x // 2 + y) % 2 == 0:
                mat, b = straw[key]
                bk[y, x, :3] = h.RAMPS[mat][max(0, b - 1)][:3]
    base = over(base, bk)
    base = over(base, chair_layer())
    petals(base)
    base = soft_shadow(base, CX, GROUND + 6.5, 49.0, 6.0)
    save(OUT / "salon.png", base)
    glow = base_glow(base, mask, box, pts, mir)
    save(OUT / "salon_glow.png", glow)
    canopy, (ax, ay) = T.part("salon_canopy", canopy_part(), FW, FH, GROUND, seed=181)
    canopy = canopy_folds(canopy, ax)
    save(OUT / "salon_canopy.png", canopy)
    lantern, (lx, ly) = T.part("salon_lantern", lantern_part(), FW, FH, GROUND, seed=182)
    lglow = lantern_glow(lantern)
    save(OUT / "salon_lantern_glow.png", lglow)
    ribbons, (rx, ry) = ribbons_part()
    prev = Image.fromarray(base)
    for arr, (x, y) in ((ribbons, (rx, ry)), (canopy, (ax, ay)), (lantern, (lx, ly))):
        prev.alpha_composite(Image.fromarray(arr), (x, y))
    save(OUT / "salon_preview.png", np.array(prev))
    fb = T.fire_box(lantern)
    lamp_at = [round((fb[0] + fb[1]) / 2 + lx - CX + 0.5), round((fb[2] + fb[3]) / 2 + ly - GROUND + 0.5)]
    info = T.INFO
    glass_c = [round((box[0] + box[1] + 1) / 2 - CX, 1), round((box[2] + box[3] + 1) / 2 - GROUND, 1)]
    ledge_c = [ledge_point(0.0, 1.6)[0] - CX, ledge_point(0.0, 1.6)[1] + 1 - GROUND]
    entry = {
        "name": "FREILUFTSALON", "needs": "plaza", "category": "living", "texture": "salon", "frame": [FW, FH], "feet": GROUND, "foot": [72, 18], "snap": 8,
        "limit": 1, "salon": True, "cost": {"wood": 10, "stone": 3, "plant_fiber": 4, "glow_cap": 1}, "build_seconds": 8.0, "wave": 32, "worth": 3,
        "info": "EIN FRISIERPLATZ UNTER FREIEM HIMMEL. HIER WIRD ELLIE BALD IHR AUSSEHEN ÄNDERN.", "glow": True, "anim": {"frames": 8, "fps": 6},
        "light": {"color": "ffc890", "radius": 48, "energy": 0.6, "at": lamp_at, "flicker": 0.15},
        "preview": "salon_preview", "seats": [[-14, 4, 2]], "mirror": [round(glass_c[0]), round(glass_c[1])], "fireflies": True, "trample": {"strength": 0.6, "margin": 10, "front": False},
        "perches": [[-24, int(BEAM_SY), 58], [12, int(BEAM_SY), 58]],
        "parts": [
            {"texture": "salon_ribbons", "frame": info["salon_ribbons"]["frame"], "at": info["salon_ribbons"]["at"], "window": [0.7, 1.0],
             "sway": {"pivot": 0, "amount": 1.6, "flutter": 0.9}},
            {"texture": "salon_canopy", "frame": info["salon_canopy"]["frame"], "at": info["salon_canopy"]["at"], "window": [0.8, 1.0],
             "sway": {"pivot": 0, "amount": 1.2, "flutter": 0.6}},
            {"texture": "salon_lantern", "frame": info["salon_lantern"]["frame"], "at": info["salon_lantern"]["at"], "window": [0.85, 1.0],
             "sway": {"pivot": 0, "amount": 1.4, "flutter": 0.3}, "glow": {"frames": 8, "fps": 6}, "fireflies": True},
        ],
    }
    put_piece("salon", entry, "banner_post")
    report = {"seat": list(SEAT), "glass_centre": glass_c, "glass_box": [box[0] - CX, box[1] - CX, box[2] - GROUND, box[3] - GROUND],
              "ledge_centre": ledge_c, "flask": [pts["flask"][0] - CX, pts["flask"][1] - GROUND], "lantern": lamp_at}
    print("REPORT", json.dumps(report))
    print("ENTRY", json.dumps(entry, ensure_ascii=False))
    return {"base": base, "glow": glow, "canopy": (canopy, (ax, ay)), "lantern": (lantern, (lx, ly)), "lantern_glow": lglow, "ribbons": (ribbons, (rx, ry))}


def contact(res, path, scale=5):
    """Day and night look (base + parts, glow on top), and the 8 glow frames; upscaled."""
    base, glow = res["base"], res["glow"]
    parts = [res["ribbons"], res["canopy"], res["lantern"]]
    lg = res["lantern_glow"]
    lw = res["lantern"][0].shape[1]

    def scene(f, night):
        bg = (24, 30, 52, 255) if night else (58, 110, 70, 255)
        img = Image.new("RGBA", (FW, FH), bg)
        pic = Image.fromarray(base)
        for arr, (x, y) in parts:
            pic.alpha_composite(Image.fromarray(arr), (x, y))
        a = np.array(pic).astype(float)
        if night:
            a[..., :3] *= np.array([0.24, 0.24, 0.4])
        img.alpha_composite(Image.fromarray(a.clip(0, 255).astype(np.uint8)))
        g = glow[:, f * FW:(f + 1) * FW].astype(float)
        if not night:
            g[..., 3] *= 0.3
        img.alpha_composite(Image.fromarray(g.astype(np.uint8)))
        lgf = lg[:, (f % 8) * lw:(f % 8 + 1) * lw].astype(float)
        if not night:
            lgf[..., 3] *= 0.3
        img.alpha_composite(Image.fromarray(lgf.astype(np.uint8)), res["lantern"][1])
        return img

    row1 = [scene(0, False), scene(1, False), scene(0, True), scene(2, True)]
    row2 = [scene(f, True) for f in range(8)]
    gap = 4
    W = max(len(row1) * (FW + gap), len(row2) * (FW + gap)) + gap
    sheet = Image.new("RGBA", (W, 2 * FH + 3 * gap), (12, 12, 20, 255))
    for i, im in enumerate(row1):
        sheet.paste(im, (gap + i * (FW + gap), gap))
    for i, im in enumerate(row2):
        sheet.paste(im, (gap + i * (FW + gap), FH + 2 * gap))
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST).save(path)
    big = Image.new("RGBA", (FW * 2 + gap, FH), (12, 12, 20, 255))
    big.paste(scene(0, False), (0, 0))
    big.paste(scene(1, True), (FW + gap, 0))
    big.resize((big.width * 7, big.height * 7), Image.NEAREST).save(str(path).replace(".png", "_zoom.png"))


if __name__ == "__main__":
    result = make()
    pngs = [a for a in sys.argv[1:] if a.endswith(".png")]
    if pngs:
        contact(result, pngs[0])
