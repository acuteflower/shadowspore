#!/usr/bin/env python3
"""The town's lamp post (docs/town.md), redone: a post grown from two young stems twisted round each other (the world's violet-veined wood), standing in a little
cairn of mossy stones with three glow caps at its foot, an arm that curls over and carries a hanging cage lantern on a short chain, a bark hood over it, wind chimes
of glass beads, ivy with glowing buds. The light is carried through the wood: a violet vein winds up the post and a pulse of light runs up it into the lantern.
    python3 tools/art_lamp.py [preview.png]   writes assets/town/lamp_post.png (frame 48x72, feet row 66; nothing emissive is bright in it),
                                              lamp_post_glow.png (8 frames side by side: the unlit pulse in the veins, breathing caps and buds),
                                              lamp_post_lantern.png (24x32: the cage on its chain, hung separately so it can sway) and
                                              lamp_post_lantern_glow.png (8 frames: the flame, the breathing light in the glass, a dithered halo).
    The hook point and the lantern's place are printed (data/town.json `parts`)."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
from hut_lib import *  # noqa: E402,F401,F403
from hut_lib import ROOT, grain, hsh, rng_for, save, soft_shadow, to_array, V, log, bayer  # noqa: E402
import hut_lib  # noqa: E402

OUT = ROOT / "town"
FW, FH, GROUND = 48, 72, 66
LW, LH, LGROUND = 24, 32, 24  # the lantern's frame and the row of its base plate
N = 8
WOODISH = (BARK, BARK_D, PLANK, PLANK_W, MOSS, MOSS_L, STONE, STONE_L, IRON, STRAW, LINEN, CLAY)
EMIT = (h.TEAL, h.VIOLET)
COSP = math.cos(math.radians(26.0))
SINP = math.sin(math.radians(26.0))


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def proj(x, y, z):
    """Model units -> (column, row) of the 48 x 72 frame."""
    return FW / 2 + x * h.SCALE, GROUND - (y * COSP - z * SINP) * h.SCALE


def emissive_masks(arr):
    """For every emissive pixel: its ramp (TEAL / VIOLET) and tone 0..3."""
    cols = {}
    for mat in EMIT:
        for tone, c in enumerate(h.RAMPS[mat]):
            cols[tuple(int(v) for v in c[:3])] = (mat, tone)
    out = {}
    for y in range(arr.shape[0]):
        for x in range(arr.shape[1]):
            if arr[y, x, 3] and tuple(int(v) for v in arr[y, x, :3]) in cols:
                out[(x, y)] = cols[tuple(int(v) for v in arr[y, x, :3])]
    return out


def darken_emissive(arr, mask, factor=0.42):
    """The base picture keeps the glowing parts only as dim glass and dim veins; the unlit sheets bring the light (and can breathe)."""
    out = arr.copy()
    for (x, y), (mat, tone) in mask.items():
        c = h.RAMPS[mat][0]
        out[y, x] = (int(c[0] * factor), int(c[1] * factor), int(c[2] * factor), 255)
    return out


# ------------------------------------------------------------------ the post
def post_model():
    rng = rng_for(77)
    m = h.Model()
    zc = -6.0
    top = 60.0
    for ring, (n, rad, y, size) in enumerate([(8, 6.8, 1.5, 2.9), (6, 4.6, 4.2, 2.5)]):  # the cairn: two rings of flat stones
        for k in range(n):
            a = k / n * math.tau + ring * 0.6
            m.ell(V(math.cos(a) * rad, y, math.sin(a) * rad * 0.72 + zc), (rng.uniform(size * 0.85, size * 1.2), rng.uniform(1.4, 2.1), rng.uniform(size * 0.7, size)),
                  STONE if (k + ring) % 2 else STONE_L, R=h.rot_y(a))
    for k in range(9):  # moss on the stones
        a = k * 0.95
        m.ell(V(math.cos(a) * 5.2, 3.0 + 0.8 * (k % 3 == 0), math.sin(a) * 3.8 + zc), (rng.uniform(1.3, 2.4), 0.6, rng.uniform(1.0, 1.8)), MOSS_L if k % 2 else MOSS)
    for dx, dz, s in ((-7.0, 1.8, 1.0), (6.6, 2.4, 1.3), (-2.8, 5.0, 0.8), (2.4, -3.0, 0.7)):  # glow caps between the stones
        m.limb(V(dx, 1.6, zc + dz), V(dx, 2.6 + s * 1.6, zc + dz), 0.55 * s, 0.45 * s, LINEN)
        m.ell(V(dx, 3.3 + s * 1.9, zc + dz), (2.0 * s, 1.05 * s, 2.0 * s), h.TEAL, kind="emit")

    def axis(y):
        return V(0.8 * y / top + 0.5 * math.sin(y * 0.12), y, zc)

    twist = 0.30
    for strand in (0, 1):  # two young stems twisted round each other
        phase = strand * math.pi
        y = 3.0
        stop = top - 7.0 if strand == 1 else top - 14.0
        while y <= stop:
            t = y / top
            spread = 1.45 * (1.0 - 0.22 * t)
            r = 1.8 - 0.5 * t + 0.9 * max(0.0, 1.0 - y / 9.0)
            c = axis(y) + V(math.cos(y * twist + phase) * spread, 0.0, math.sin(y * twist + phase) * spread * 0.9)
            m.ell(c, (r, 0.95, r), BARK_D if int(y / 2.2) % 5 == 0 else BARK)
            y += 0.7
    end = axis(top - 7.0) + V(math.cos((top - 7.0) * twist + math.pi) * 1.1, 0, math.sin((top - 7.0) * twist + math.pi) * 1.0)
    m.ell(end + V(0, 1.4, 0), (1.5, 1.8, 1.5), BARK)  # the second stem ends in a bud
    m.ell(end + V(0, 3.4, 0), (0.7, 1.2, 0.7), h.TEAL, kind="emit")
    for sx in (-1, 1):  # roots into the cairn
        m.limb(axis(4.0) + V(sx * 1.2, 0, 0), V(sx * 6.5, 1.8, zc + 1.8), 1.5, 0.6, BARK)
    # the arm: the first stem curls over to the right and ends in a hook
    p0 = axis(top - 14.0) + V(math.cos((top - 14.0) * twist) * 1.2, 0, 0)
    p1 = p0 + V(0.5, 12.0, 0)
    p2 = V(8.0, top + 7.0, zc)
    p3 = V(12.5, top - 1.0, zc)
    prev = p0
    for k in range(1, 15):
        t = k / 14.0
        pt = (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3
        m.limb(prev, pt, 1.45 - 0.7 * (k - 1) / 14.0, 1.45 - 0.7 * k / 14.0, BARK, step=0.5)
        prev = pt
    m.ell(p3 + V(0.3, -0.7, 0.0), (0.9, 1.0, 0.9), IRON)  # the hook
    # a bark hood over the lantern: two overlapping shingles and a bud on the tip
    hood = p3 + V(-1.0, 4.6, 0.0)
    m.ell(hood, (7.0, 1.0, 4.6), BARK_D, R=rot_z(0.12))
    m.ell(hood + V(0.4, 1.0, 0.0), (5.2, 0.9, 3.5), BARK, R=rot_z(0.12))
    m.ell(hood + V(0.8, 2.0, 0.0), (3.0, 0.8, 2.2), MOSS_L)
    m.ell(hood + V(1.0, 3.2, 0.0), (0.7, 0.7, 0.7), h.TEAL, kind="emit")
    # the chain from the hook down to where the lantern hangs
    link = p3 + V(0.3, -2.6, 0.0)
    chain_end = link
    for k in range(3):
        m.ell(link + V(0, -k * 2.0, 0), (0.55, 1.1, 0.35 if k % 2 else 0.9), IRON)
        chain_end = link + V(0, -k * 2.0 - 1.4, 0)
    # wind chimes of glass beads under the arm
    for k, (dx, drop) in enumerate(((-3.0, 5.0), (-0.2, 8.0), (2.8, 4.0))):
        base = p1 + V(dx + 1.5, -3.5 - k * 0.3, 1.6)
        m.limb(base, base + V(0, -drop, 0), 0.18, 0.18, LINEN)
        m.ell(base + V(0, -drop - 0.9, 0), (0.9, 1.2, 0.9), h.TEAL, kind="emit")
    # ivy up the lower half with glowing buds
    pts = [axis(y) + V(3.2 * math.sin(y * 0.55), 0, 3.0 * math.cos(y * 0.55) * 0.9) for y in np.arange(3.0, 30.0, 1.4)]
    for i, (a_, b_) in enumerate(zip(pts, pts[1:])):
        m.limb(a_, b_, 0.42, 0.38, MOSS)
        if i % 2 == 0:
            m.ell(b_ + V(0.4 * (-1) ** i, 0.2, 0.9), (1.0, 0.35, 0.8), MOSS_L if i % 4 == 0 else MOSS, R=h.rot_x(0.5))
    for i in (5, 11, 16):
        m.ell(pts[i] + V(0.5, 0.4, 1.2), (0.6, 0.6, 0.6), h.TEAL, kind="emit")
    # the vein of light: a violet line winding up the front of the post
    y = 6.0
    while y < top - 16.0:
        a = y * twist + math.pi * 0.5
        if math.sin(y * twist + math.pi * 0.5) > -0.2:
            spread = 1.45 * (1.0 - 0.22 * y / top)
            m.ell(axis(y) + V(math.cos(y * twist) * spread * 0.9, 0, math.sin(y * twist) * spread * 0.95 + 1.25), (0.55, 0.65, 0.5), h.VIOLET, kind="emit")
        y += 0.9
    return m, chain_end


def make_post():
    m, chain_end = post_model()
    arr = to_array(hut_lib.render(m, FW, FH, GROUND))
    arr = grain(arr, 31, amount=0.5, mats=WOODISH)
    mask = emissive_masks(arr)
    base = soft_shadow(darken_emissive(arr, mask), FW / 2, GROUND + 1, 9, 2.4)
    cx, cy = proj(*chain_end)
    return base, mask, (cx, cy)


def post_glow_frames(mask):
    """N frames side by side: a pulse of light runs up the violet vein from the cairn to the lantern, the glow caps and buds breathe each on its own beat."""
    out = np.zeros((FH, FW * N, 4), np.uint8)
    top_px = GROUND - 8.0
    for f in range(N):
        pulse = -0.25 + 1.55 * f / N
        for (x, y), (mat, tone) in mask.items():
            if mat == h.VIOLET:
                t = (GROUND - y) / top_px
                lit = 0.28 + 0.72 * math.exp(-(((t - pulse) / 0.16) ** 2)) + 0.18 * math.sin(f / N * math.tau + x * 0.4) * 0.5
            else:
                lit = 0.62 + 0.38 * math.sin(f / N * math.tau + hsh(x // 5, y // 6, 3) * math.tau)
            lit = max(0.0, min(1.0, lit))
            k = int(round(lit * 3))
            if lit < 0.12:
                continue
            c = h.RAMPS[mat][k]
            out[y, f * FW + x] = (*[int(v) for v in c[:3]], 255)
    return out


# ------------------------------------------------------------------ the lantern
def lantern_model():
    m = h.Model()
    m.ell(V(0, 21.2, 0), (1.5, 0.7, 1.5), IRON)  # the ring it hangs by
    m.ell(V(0, 22.3, 0), (0.7, 1.1, 0.5), IRON)
    m.ell(V(0, 19.0, 0), (2.6, 0.9, 2.6), IRON)  # the cap: a small cone of bark-black iron
    m.ell(V(0, 17.6, 0), (4.2, 1.0, 4.2), IRON)
    m.ell(V(0, 16.7, 0), (4.9, 0.7, 4.9), BARK_D)
    for a in (0.5, 2.07, 3.64, 5.21):  # four bars
        m.limb(V(math.cos(a) * 4.6, 16.2, math.sin(a) * 4.6), V(math.cos(a) * 4.6, 1.4, math.sin(a) * 4.6), 0.38, 0.38, IRON)
    m.ell(V(0, 9.0, 0), (3.9, 7.4, 3.9), h.TEAL, kind="emit")  # the glass: dim in the picture, alight in the unlit sheet
    for dx, dz, s in ((-1.4, 1.2, 1.0), (1.3, -0.8, 0.9), (0.1, 1.8, 0.8)):  # three glow caps on the floor of it
        m.ell(V(dx, 2.4 + s * 0.4, dz), (1.6 * s, 0.9 * s, 1.6 * s), h.TEAL, kind="emit")
    m.ell(V(0, 1.0, 0), (5.0, 0.9, 5.0), IRON)  # the base plate and a small finial
    m.ell(V(0, 0.0, 0), (3.2, 0.8, 3.2), BARK_D)
    m.ell(V(0, -1.4, 0), (0.8, 1.4, 0.8), IRON)
    for dx, drop in ((-3.0, 5.0), (3.2, 3.2)):  # two threads with glass beads
        m.limb(V(dx, 0.4, 2.6), V(dx, -drop, 2.6), 0.16, 0.16, LINEN)
        m.ell(V(dx, -drop - 0.8, 2.6), (0.85, 1.1, 0.85), h.TEAL, kind="emit")
    return m


def make_lantern():
    m = lantern_model()
    arr = to_array(hut_lib.render(m, LW, LH, LGROUND))
    mask = emissive_masks(arr)
    base = darken_emissive(arr, mask, 0.5)
    return base, mask, arr


def lantern_glow_frames(mask):
    """N frames of the light in the lantern: the glass breathes (its middle brightest), a teal flame of three tongues flickers in it (each loops on its own beat),
    sparks rise out of the cap, and a dithered halo round the cage breathes with it."""
    out = np.zeros((LH, LW * N, 4), np.uint8)
    cols = h.RAMPS[h.TEAL]
    cx = LW / 2.0
    for f in range(N):
        ph = f / N * math.tau
        flick = 0.82 + 0.18 * math.sin(ph) + 0.06 * math.sin(ph * 3 + 1.0)
        for y in range(LH):  # halo first, so the cage and the flame cover it
            for x in range(LW):
                d = math.hypot((x + 0.5 - cx) / 11.0, (y + 0.5 - (LGROUND - 9.0)) / 13.0)
                if 0.55 < d < 1.0 and bayer(x, y) < (1.0 - d) * 0.9 * flick:
                    out[y, f * LW + x] = (*[int(v) for v in cols[0][:3]], 255)
        for (x, y), (mat, tone) in mask.items():
            dx = (x + 0.5 - cx) / 4.5
            dy = (y + 0.5 - (LGROUND - 9.0)) / 7.5
            core = max(0.0, 1.0 - (dx * dx + dy * dy) * 0.55)
            if y > LGROUND - 3 and abs(x - cx) < 3.5:  # the caps on the floor stay brighter
                core = max(core, 0.8)
            lit = (0.45 + 0.55 * core) * flick + (hsh(x, y, f) - 0.5) * 0.12
            if y > LGROUND + 1:  # the beads on their threads
                lit = 0.6 + 0.4 * math.sin(ph + x)
            k = max(0, min(3, int(round(lit * 3.0))))
            out[y, f * LW + x] = (*[int(v) for v in cols[k][:3]], 255)
        tongues = ((-1.6, 8.5, 1, 0.0), (0.2, 11.5, 2, 1.7), (1.7, 7.0, 3, 3.1))
        for ox, ht, beats, p0 in tongues:
            hh = ht * (0.78 + 0.22 * math.sin(ph * beats + p0))
            sway = math.sin(ph * beats + p0 + 1.1) * 1.1
            for yy in range(int(hh) + 1):
                u = yy / max(hh, 1.0)
                width = 2.0 * (1.0 - u) ** 0.8
                px = cx + ox + sway * u
                for x in range(int(px - 3), int(px + 4)):
                    d = abs(x + 0.5 - px)
                    if d < width and 0 <= x < LW:
                        y = LGROUND - 3 - yy
                        if 0 <= y < LH:
                            v = (1.0 - d / max(width, 0.1)) * (1.0 - 0.4 * u)
                            out[y, f * LW + x] = (*[int(c) for c in cols[3 if v > 0.55 else 2][:3]], 255)
        for k in range(2):  # sparks out of the cap
            t = (f / N + k * 0.5) % 1.0
            sx = int(cx + math.sin(k * 2.4 + ph) * 2 + (k - 0.5) * 3)
            sy = int(LGROUND - 17 - t * 6)
            if 0 <= sy < LH and 0 <= sx < LW:
                out[sy, f * LW + sx] = (*[int(c) for c in cols[3 if t < 0.5 else 1][:3]], 255)
    return out


# ------------------------------------------------------------------ output and preview
def make(preview=None):
    hut_lib.set_fresh()  # the town is new work next to the renewed hut: the same plum-violet wood (idempotent)
    base, mask, chain = make_post()
    save(OUT / "lamp_post.png", base)
    save(OUT / "lamp_post_glow.png", post_glow_frames(mask))
    lantern, lmask, _ = make_lantern()
    save(OUT / "lamp_post_lantern.png", lantern)
    save(OUT / "lamp_post_lantern_glow.png", lantern_glow_frames(lmask))
    at = (round(chain[0] - LW / 2.0), round(chain[1] - 5.0))
    prev_img = np.array(base, np.uint8).copy()  # the picture of the finished piece for the build menu and the ghost: post, lantern and a little of the light
    from PIL import Image as _Image
    comp = _Image.fromarray(prev_img, "RGBA")
    comp.alpha_composite(_Image.fromarray(lantern, "RGBA"), at)
    lit = _Image.open(OUT / "lamp_post_lantern_glow.png").convert("RGBA").crop((2 * LW, 0, 3 * LW, LH))
    lit.putalpha(lit.getchannel("A").point(lambda v: int(v * 0.85)))
    comp.alpha_composite(lit, at)
    comp.save(OUT / "lamp_post_preview.png")
    print("lamp post: chain end at px (%.1f, %.1f), lantern frame top-left %s (rows 5 below its top = the ring), %d emissive pixels in the post" % (chain[0], chain[1], at, len(mask)))
    if preview:
        from PIL import Image
        scale = 6
        frames = []
        pg = Image.open(OUT / "lamp_post_glow.png").convert("RGBA")
        lg = Image.open(OUT / "lamp_post_lantern_glow.png").convert("RGBA")
        pb = Image.open(OUT / "lamp_post.png").convert("RGBA")
        lb = Image.open(OUT / "lamp_post_lantern.png").convert("RGBA")
        for night in (0.35, 1.0):
            for f in (0, 3, 5):
                tile = Image.new("RGBA", (64, 80), (46, 78, 44, 255) if night < 0.5 else (14, 20, 34, 255))
                tile.alpha_composite(pb, (8, 4))
                tile.alpha_composite(lb, (8 + at[0], 4 + at[1]))
                for im_, ox, oy, w, hh in ((pg, 8, 4, FW, FH), (lg, 8 + at[0], 4 + at[1], LW, LH)):
                    g = im_.crop((f * w, 0, f * w + w, hh))
                    a = g.getchannel("A").point(lambda v: int(v * night))
                    g.putalpha(a)
                    tile.alpha_composite(g, (ox, oy))
                frames.append(tile.resize((64 * scale // 2, 80 * scale // 2), Image.NEAREST))
        w = frames[0].width
        out = Image.new("RGBA", (w * 3, frames[0].height * 2))
        for i, t in enumerate(frames):
            out.alpha_composite(t, ((i % 3) * w, (i // 3) * frames[0].height))
        out.save(preview)


if __name__ == "__main__":
    make(sys.argv[1] if len(sys.argv) > 1 else None)
