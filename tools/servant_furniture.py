"""The furniture of Ellie's room (tools/art_servant_room.py), made like the hut's: wood, cloth and clay built from ellipsoids with the renderer of the heroine, the trees and the hut
(tools/hut_lib.py, art_hero3d), lit from the top left, four bands of shade, ink between the forms. Wood is the plum-violet fir of the hut in its tended ("fresh") state: a servant's room is
poor and kept clean, nothing rotten, nothing overgrown. Every function returns an RGBA array (and the feet row where it stands on the floor); sizes are in pixels, 1 model unit ~ 1 px.
Wall things (the tools on their mounts, the shelf) are drawn on the plane of the wall, so they sit flat against the wall's face."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_hero3d as h  # noqa: E402
import hut_lib  # noqa: E402

hut_lib.set_fresh()  # tended wood and stone, before anything is drawn
from hut_lib import (BARK, BARK_D, CLAY, GAP, IRON, LINEN, PLANK, PLANK_W, STRAW, V, WAX, WOOL, FIRE, glow_of, grain, log, render, rng_for, slab, soft_shadow, to_array)  # noqa: E402


def _ground(arr, feet, rx, ry, dx=0.0, alpha=70):
    return soft_shadow(arr, arr.shape[1] / 2 + dx, feet + 1, rx, ry, alpha)


def _px(arr, x, y, col):
    if 0 <= y < arr.shape[0] and 0 <= x < arr.shape[1]:
        arr[y, x] = (*col[:3], 255)


# ------------------------------------------------------------------ wall mounts: the broom and the rake
# Each tool hangs on a vertical backboard with two wooden clips. Three pictures of the same size lie exactly on each other (backboard, tool, clips) so the tool can be taken
# off its mount later and the mount stays: they only differ in their sort rows (Interior sorts props by their feet).
MOUNT_W, MOUNT_H, MOUNT_G = 30, 56, 52  # canvas of a mount picture, the row of the wall's foot in it
CLIPS_AT = (-3.0, 20.0)  # model heights of the clips above the foot of the board


def _mount_back(top):
    m = h.Model()
    slab(m, V(0, 4.0, 0), V(0, top, 0), 3.5, 1.0, PLANK_W, (0, 0, 1), step=1.3)  # the backboard
    for y in (6.0, top - 2.0):  # two nail heads
        m.ell((0, y, 1.1), (0.5, 0.5, 0.4), IRON)
    return grain(to_array(render(m, MOUNT_W, MOUNT_H, MOUNT_G)), 91, along=(0.0, 1.0), amount=0.5, mats=(PLANK_W, BARK))


def _mount_clips(heights):
    m = h.Model()
    for y in heights:
        m.ell((0, y, 1.5), (3.2, 1.7, 2.3), BARK_D)  # the wooden band round the handle: a block with the handle sunk into it
        m.ell((0, y + 0.5, 2.6), (2.5, 1.0, 1.4), BARK)
    return grain(to_array(render(m, MOUNT_W, MOUNT_H, MOUNT_G)), 92, amount=0.4, mats=(BARK, BARK_D))


def broom_mount():
    return _mount_back(46.0), _mount_clips((16.0, 38.0))


def broom_tool():
    """A plain fir handle and a bundle of straw bound with cord, hanging head down. Hangs on the plane of the wall, `z` in front of the backboard."""
    rng = rng_for(70)
    m = h.Model()
    log(m, V(0, 12.0, 1.0), V(0, 52.0, 1.0), 1.3, PLANK_W, step=1.0)
    m.ell(V(0, 52.4, 1.0), (1.4, 0.7, 1.4), BARK_D)
    base = V(0, 14.0, 1.0)
    for k in range(64):  # the bristles fan out from the binding to ragged tips
        u = rng.uniform(-1.0, 1.0)
        tip = base + V(u * 5.5 + rng.uniform(-0.6, 0.6), -rng.uniform(10.0, 14.0) + abs(u) * 3.0, rng.uniform(-0.7, 1.4))
        m.limb(base + V(rng.uniform(-0.8, 0.8), rng.uniform(-0.3, 0.6), rng.uniform(-0.5, 0.5)), tip, 0.62, 0.22, STRAW if rng.random() < 0.82 else BARK, step=0.8)
    for dy in (0.0, -2.2):  # the cord that binds them
        for k in range(10):
            a = k / 10 * math.tau
            m.ell(V(1.3 * math.cos(a), 12.8 + dy, 1.0 + 1.3 * math.sin(a)), (0.6, 0.6, 0.6), WAX if dy == 0 else BARK_D)
    return grain(to_array(render(m, MOUNT_W, MOUNT_H, MOUNT_G)), 71, along=(0.0, 1.0), amount=0.4, mats=(PLANK_W, BARK_D, BARK))


def rake_mount():
    return _mount_back(44.0), _mount_clips((10.0, 30.0))


def rake_tool():
    """A hay rake: handle, a head-board and wooden teeth, hanging head up so the teeth are seen."""
    m = h.Model()
    log(m, V(0, 6.0, 1.0), V(0, 44.0, 1.0), 1.3, PLANK_W, step=1.0)
    slab(m, V(-9.5, 45.0, 1.0), V(9.5, 45.0, 1.0), 1.6, 1.5, BARK, (0, 0, 1), step=1.1)  # the head
    for k in range(7):
        x = -8.4 + k * 2.8
        log(m, V(x, 45.5, 1.2), V(x, 52.0 - (0.6 if k % 2 else 0.0), 1.2), 0.75, PLANK_W, step=0.9, taper=0.7)
    for x in (-3.4, 3.4):  # braces from the handle to the head
        m.limb(V(0, 38.0, 1.0), V(x * 2.2, 45.0, 1.1), 0.65, 0.65, BARK_D)
    return grain(to_array(render(m, MOUNT_W, MOUNT_H, MOUNT_G)), 73, along=(0.0, 1.0), amount=0.4, mats=(PLANK_W, BARK_D, BARK))


# ------------------------------------------------------------------ the shelf with her things
def shelf_arr():
    """A wall shelf: a thick board on two wooden brackets, and on it what is hers: a small painted picture leaning in a frame, a crow's feather in a clay cup, a book, a smooth pebble."""
    m = h.Model()
    slab(m, V(-23, 8.0, 3.0), V(23, 8.0, 3.0), 1.5, 4.8, PLANK_W, (0, 1, 0), step=1.3)  # the board
    slab(m, V(-23, 6.4, 7.2), V(23, 6.4, 7.2), 1.0, 0.9, BARK, (0, 0, 1), step=1.3)  # its front edge, a darker lip
    for bx in (-16.0, 16.0):  # brackets: an upright and a diagonal brace
        slab(m, V(bx, 0.0, 0.6), V(bx, 7.0, 0.6), 1.0, 1.2, BARK_D, (0, 0, 1), step=1.0)
        m.limb(V(bx, 0.4, 0.6), V(bx, 7.0, 5.6), 1.0, 1.0, BARK_D)
    # the picture: a frame (the glass is painted in 2D afterwards) standing a little back, leaning on the wall
    slab(m, V(-17, 10.0, 0.5), V(-17, 28.0, 0.5), 7.2, 0.9, BARK, (0, 0, 1), step=1.2)
    m.ell((-17, 18.5, 0.1), (5.6, 8.0, 0.5), GAP)
    # the feather in a clay cup
    log(m, V(-3.0, 9.4, 3.5), V(-3.0, 15.0, 3.5), 2.2, CLAY, step=0.9)
    m.ell((-3.0, 15.2, 3.5), (1.9, 0.35, 1.9), GAP)
    m.limb(V(-3.0, 14.0, 3.5), V(-1.4, 24.0, 3.2), 0.28, 0.2, IRON)  # the quill and the vane, lit edge
    m.ell((-0.8, 22.0, 3.2), (1.9, 5.0, 0.5), IRON)
    # a book with a ribbon, lying down
    m.ell((8.0, 11.0, 3.8), (6.8, 2.0, 4.4), PLANK_W)
    m.ell((8.0, 12.9, 3.8), (6.3, 0.5, 3.9), LINEN)
    m.ell((8.0, 11.0, 7.9), (6.3, 1.5, 0.5), LINEN)
    m.limb(V(11.5, 11.4, 8.3), V(12.5, 8.4, 8.6), 0.4, 0.4, CLAY)  # the ribbon
    # a smooth pebble she keeps
    m.ell((18.0, 10.2, 4.5), (2.6, 1.5, 2.2), h.CRYSTAL)
    arr = grain(to_array(render(m, 56, 40, 32)), 74, amount=0.4, mats=(PLANK_W, BARK, BARK_D))
    return arr


def paint_picture(arr, x0, y0, w, h_):
    """Her little painting, in 2D inside the frame: a dusk sky from lilac to a warm glow at the horizon, a dark ridge of hills, one small lit tree."""
    sky = [(0x54, 0x4a, 0x84), (0x6a, 0x5a, 0x98), (0x8a, 0x70, 0xa6), (0xb4, 0x8a, 0xa8), (0xe0, 0xa8, 0x86), (0xf0, 0xcc, 0x90)]
    ridge = [(0x2a, 0x26, 0x44), (0x1c, 0x1a, 0x34)]
    for y in range(h_):
        for x in range(w):
            k = y / max(1, h_ - 1) * 4.2
            k += (-0.35 if (x + y) % 2 else 0.35) * (0.5 if 0.2 < (k % 1) < 0.8 else 1.0)
            _px(arr, x0 + x, y0 + y, sky[max(0, min(5, int(k)))])
    prof = [h_ * 0.64, h_ * 0.58, h_ * 0.55, h_ * 0.6, h_ * 0.66, h_ * 0.7, h_ * 0.64, h_ * 0.58][: w] + [h_ * 0.6] * w
    for x in range(w):
        for y in range(int(prof[x]), h_):
            _px(arr, x0 + x, y0 + y, ridge[0] if y == int(prof[x]) else ridge[1])
    tx = x0 + w // 2 + 1
    for dy in range(4):  # a tiny pale tree on the ridge, with a lit side
        for dx in range(-(dy // 2), dy // 2 + 1):
            _px(arr, tx + dx, y0 + int(h_ * 0.5) + dy, (0xa8, 0xc8, 0x9a) if dx <= 0 else (0x74, 0xa0, 0x82))
    _px(arr, tx, y0 + int(h_ * 0.5) + 4, (0x3a, 0x2a, 0x30))
    return arr


# ------------------------------------------------------------------ the bed
def bed_arr(L2=31.0):
    """Her bed: a narrow cot of the plum fir with a straw mattress in a grey linen cover, a wool blanket over the lower part, a flat pillow, a tall headboard at the wall (left), a low footboard."""
    rng = rng_for(60)
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            tall = 27.0 if sx < 0 else 15.5
            log(m, V(sx * L2, 0, sz * 12.0), V(sx * L2, tall, sz * 12.0), 2.1, BARK, step=1.2)
            m.ell((sx * L2, tall + 0.9, sz * 12.0), (2.4, 2.1, 2.4), BARK)
    for sz in (-1, 1):  # side rails
        slab(m, V(-L2, 8.0, sz * 12.0), V(L2, 8.0, sz * 12.0), 1.8, 1.1, PLANK_W if sz > 0 else BARK, (0, 0, sz), step=1.3)
    for k in range(6):  # the headboard: neat slats and a top rail
        z = -9.5 + k * 3.8
        slab(m, V(-L2, 11.0, z), V(-L2, 23.5, z), 1.5, 1.0, PLANK_W if k % 2 else BARK, (-1, 0, 0), step=1.2)
    slab(m, V(-L2, 24.0, -12.0), V(-L2, 24.0, 12.0), 1.4, 1.5, BARK, (-1, 0, 0), step=1.3)
    for z in (-6.0, 0.0, 6.0):  # the low footboard
        slab(m, V(L2, 11.0, z), V(L2, 14.0, z), 1.6, 0.9, PLANK_W, (1, 0, 0), step=1.2)
    m.ell((0, 10.4, 0), (L2 - 1.4, 2.6, 11.4), LINEN)  # the mattress
    for _ in range(22):
        m.ell((rng.uniform(-L2 + 4, L2 - 4), 12.6 + rng.uniform(-0.3, 0.4), rng.uniform(-9, 9)), (rng.uniform(3, 8), 0.9, rng.uniform(2, 4)), LINEN)
    for k in range(4):  # a seam stitched across
        m.ell((-12 + k * 12, 12.9, 0), (0.5, 0.35, 10.6), LINEN)
    m.ell((-L2 + 9.0, 14.2, 0), (8.6, 2.7, 6.6), LINEN)  # the pillow
    m.ell((-L2 + 9.0, 16.0, 0), (5.6, 0.7, 3.4), LINEN)
    n = 26
    for i in range(n):  # the blanket: spread over the lower two thirds, a hem hanging over the near side, the top edge turned down
        t = i / (n - 1.0)
        x = -L2 + 20 + t * (2 * L2 - 22)
        prof = 0.6 + 0.4 * math.sin(t * math.pi)
        m.ell((x, 13.2 + 0.16 * math.sin(i * 0.9), 0.0), (1.9, 2.0 * prof, 12.3), WOOL)
        if i % 2 == 0:
            m.ell((x, 10.8, 12.0), (1.9, 2.4 + 0.5 * math.sin(i * 1.3), 0.9), WOOL if i % 6 else CLAY)
    for k in range(3):  # the folded-down edge, lighter
        m.ell((-L2 + 17.5 + k * 0.6, 15.2, rng.uniform(-3, 3)), (2.0, 0.8, 11.3), LINEN)
    for _ in range(8):
        R = h.rot_x(rng.uniform(-0.4, 0.4)) @ h.rot_y(rng.uniform(-0.5, 0.5))
        m.ell((rng.uniform(-L2 + 20, L2 - 4), 15.2, rng.uniform(-6, 6)), (rng.uniform(2, 4.5), 0.5, rng.uniform(2.5, 5)), WOOL, R=R)
    arr = to_array(render(m, 92, 62, 50))
    arr = grain(arr, 61, amount=0.5)
    return _ground(arr, 50, 38, 6), 50


# ------------------------------------------------------------------ the little table by the bed with the candle
def nightstand_arr():
    """A little box table beside the bed: a candle in a clay holder, a tin cup, her hairbrush, on the shelf below a folded cloth and a pair of rolled stockings."""
    m = h.Model()
    for sx in (-1, 1):
        for sz in (-1, 1):
            log(m, V(sx * 7.5, 0, sz * 6.0), V(sx * 7.4, 17.0, sz * 6.0), 1.5, BARK_D, step=1.1)
    slab(m, V(-8.4, 17.6, 0), V(8.4, 17.6, 0), 1.4, 7.4, BARK, (0, 1, 0))  # top
    slab(m, V(-8, 17.2, 6.6), V(8, 17.2, 6.6), 1.5, 0.9, PLANK_W, (0, 0, 1))  # apron
    slab(m, V(-7.6, 5.5, 0), V(7.6, 5.5, 0), 1.2, 6.0, PLANK_W, (0, 1, 0))  # lower shelf
    m.ell((-2.4, 19.4, 1.0), (4.0, 0.6, 3.4), CLAY)  # the holder: a saucer with a ring handle
    m.limb(V(-6.2, 19.8, 1.0), V(-7.6, 20.8, 1.0), 0.45, 0.45, CLAY)
    log(m, V(-2.4, 19.8, 1.0), V(-2.4, 24.6, 1.0), 1.5, WAX, step=0.9)  # the candle
    m.ell((-2.4, 24.9, 1.0), (1.4, 0.5, 1.4), WAX)
    m.ell((-2.4, 26.2, 1.0), (0.7, 1.3, 0.7), FIRE, kind="emit")  # the flame
    log(m, V(4.6, 18.4, -1.0), V(4.6, 22.4, -1.0), 1.7, IRON, step=0.9)  # a tin cup
    m.ell((4.6, 22.5, -1.0), (1.5, 0.3, 1.5), GAP)
    m.ell((3.0, 18.6, 3.8), (3.0, 0.6, 1.0), BARK_D, R=h.rot_y(0.35))  # a hairbrush
    m.ell((3.0, 19.0, 3.8), (2.0, 0.4, 0.8), STRAW, R=h.rot_y(0.35))
    m.ell((-1.0, 6.9, 0.0), (4.6, 1.5, 3.6), LINEN)  # a folded cloth below
    m.ell((-1.0, 8.0, 0.0), (4.1, 0.5, 3.2), LINEN)
    m.ell((5.0, 7.0, 1.0), (1.8, 1.4, 2.0), WOOL)
    arr = to_array(render(m, 38, 48, 40))
    return _ground(grain(arr, 63, amount=0.5), 40, 14, 3), 40


# ------------------------------------------------------------------ the wardrobe
def wardrobe_arr():
    """A plain wardrobe of the plum fir: two framed doors with a raised panel each, iron pulls, a simple cornice, short feet, a keyhole plate. Stands against the back wall."""
    rng = rng_for(80)
    m = h.Model()
    W2, Hh, D2 = 22.0, 74.0, 9.0
    for sx in (-1, 1):  # the sides
        slab(m, V(sx * W2, 3, 0), V(sx * W2, Hh, 0), D2, 1.7, BARK, (sx, 0, 0), step=1.3)
    for sx in (-1, 1):  # short feet
        for sz in (-1, 1):
            log(m, V(sx * (W2 - 1.5), 0, sz * (D2 - 1.5)), V(sx * (W2 - 1.5), 5.0, sz * (D2 - 1.5)), 1.8, BARK_D, step=1.0)
    slab(m, V(0, 3, -D2), V(0, Hh, -D2), W2, 1.0, BARK_D, (0, 0, 1), step=2.0)  # the back
    slab(m, V(-W2, Hh + 1.0, 1.0), V(W2, Hh + 1.0, 1.0), D2 + 1.5, 1.6, PLANK_W, (0, 1, 0), step=1.3)  # the top
    slab(m, V(-W2 - 1.2, Hh - 1.0, D2 + 1.0), V(W2 + 1.2, Hh - 1.0, D2 + 1.0), 2.4, 1.3, BARK, (0, 0, 1), step=1.3)  # the cornice (front board)
    slab(m, V(-W2 - 0.4, 4.0, D2 + 0.4), V(W2 + 0.4, 4.0, D2 + 0.4), 2.2, 1.2, BARK, (0, 0, 1), step=1.3)  # the plinth board
    for sx in (-1, 1):  # the doors: a frame of stiles and rails round a raised panel
        cx = sx * (W2 / 2 + 0.2)
        for sx2 in (-1, 1):
            slab(m, V(cx + sx2 * (W2 / 2 - 1.0), 6, D2), V(cx + sx2 * (W2 / 2 - 1.0), Hh - 3, D2), 1.4, 1.2, BARK, (0, 0, 1), step=1.5)
        for y in (6.5, Hh - 3.5):
            slab(m, V(cx - W2 / 2 + 1.5, y, D2), V(cx + W2 / 2 - 1.5, y, D2), 1.4, 1.2, BARK, (0, 0, 1), step=1.5)
        slab(m, V(cx, 9.0, D2 - 0.2), V(cx, Hh - 6.0, D2 - 0.2), W2 / 2 - 2.4, 1.0, PLANK_W if sx < 0 else PLANK, (0, 0, 1), step=2.0)  # the panel behind
        slab(m, V(cx, 12.0, D2 + 0.6), V(cx, Hh - 10.0, D2 + 0.6), W2 / 2 - 4.6, 0.7, PLANK_W if sx < 0 else PLANK, (0, 0, 1), step=2.0)  # the raised part
        m.ell((sx * 2.8, Hh * 0.5, D2 + 2.0), (0.9, 2.6, 0.8), IRON)  # the iron pull
        m.ell((sx * 2.8, Hh * 0.5 + 3.2, D2 + 1.6), (0.7, 0.7, 0.6), IRON)
        m.ell((sx * 2.8, Hh * 0.5 - 3.2, D2 + 1.6), (0.7, 0.7, 0.6), IRON)
    m.ell((0.0, Hh * 0.5 - 6.0, D2 + 1.8), (0.9, 1.2, 0.5), IRON)  # the keyhole plate
    arr = to_array(render(m, 56, 82, 74))
    arr = grain(arr, 81, amount=0.5, mats=(PLANK_W, PLANK, BARK, BARK_D))
    return _ground(arr, 74, 22, 4), 74


# ------------------------------------------------------------------ small things
def bucket_arr():
    """A wooden bucket of fir staves with two iron hoops, water in it, a rag over the rim and a rope handle."""
    m = h.Model()
    for k in range(14):
        a = k / 14 * math.tau
        log(m, V(math.cos(a) * 4.8, 0, math.sin(a) * 4.2), V(math.cos(a) * 6.2, 12.0, math.sin(a) * 5.4), 1.4, (BARK, PLANK_W)[k % 2], step=1.0)
    m.ell((0, 11.0, 0), (5.2, 0.8, 4.6), GAP)
    m.ell((0, 11.4, 0), (4.9, 0.4, 4.3), LINEN)
    for y, r in ((3.0, 5.4), (9.0, 6.0)):
        for k in range(20):
            a = k / 20 * math.tau
            m.ell((math.cos(a) * r * 0.99, y, math.sin(a) * r * 0.86), (0.9, 0.8, 0.9), IRON)
    for k in range(9):  # the rag
        m.ell((-4.0 + k * 0.7, 12.4 - k * 0.55, 4.6), (1.4, 2.4, 0.7), LINEN)
    for k in range(14):  # the rope handle
        a = k / 13 * math.pi
        m.ell((math.cos(a) * 6.0, 12.0 + math.sin(a) * 6.5, 0.0), (0.45, 0.45, 0.45), STRAW)
    arr = to_array(render(m, 28, 34, 26))
    return _ground(grain(arr, 69, amount=0.5), 26, 9, 2.5), 26


def boots_arr():
    """A pair of worn work boots by the bed, one tipped a little."""
    m = h.Model()
    for i, (dx, dz, rot) in enumerate(((-4.2, 0.0, 0.1), (4.4, 1.5, -0.25))):
        m.ell((dx, 3.2, dz), (2.8, 3.2, 5.2), h.BOOT, R=h.rot_y(rot))  # the leg of the boot
        m.ell((dx - 0.3, 1.6, dz + 2.8), (2.9, 1.6, 4.2), h.BOOT, R=h.rot_y(rot))  # the foot
        m.ell((dx - 0.3, 0.6, dz + 3.2), (3.0, 0.7, 4.6), BARK_D, R=h.rot_y(rot))  # the sole
        m.ell((dx, 6.4, dz), (2.7, 0.5, 3.4), GAP)  # the opening
    arr = to_array(render(m, 24, 18, 14))
    return _ground(grain(arr, 83, amount=0.3, mats=(BARK_D,)), 14, 8, 2), 14


def rug_arr(seed=72, W=70, H=34):
    """A braided rag rug, oval, seen from above like the floor: rings of braid in dull linen, clay, slate and plum, every ring plaited (light/dark along it), a frayed edge, flat to the stones."""
    rng = np.random.default_rng(seed)
    cols = [h.RAMPS[m_] for m_ in (LINEN, CLAY, WOOL, BARK)]
    out = np.zeros((H, W, 4), np.uint8)
    cx, cy = W / 2 - 0.5, H / 2 - 0.5
    ring_cols = [1, 2, 0, 3, 2, 1]
    for y in range(H):
        for x in range(W):
            ang = math.atan2((y - cy) * (W / H), x - cx)
            r = math.hypot((x - cx) / (W / 2), (y - cy) / (H / 2)) + (hut_lib.fbm(x * 0.15, y * 0.15, 5) - 0.5) * 0.05
            if r > 1.0:
                continue
            ring = min(int((1.0 - r) * 6.0), 5)
            within = ((1.0 - r) * 6.0) - ring
            c = cols[ring_cols[ring]]
            braid = math.sin(ang * (12 + ring * 3) + ring) * 0.5 + 0.5
            shade = 1 + (1 if braid > 0.6 else 0) - (1 if braid < 0.25 else 0) - (1 if within > 0.85 else 0)
            shade += 1 if (-(x - cx) - (y - cy)) / (W * 0.5) > 0.4 else 0
            if r > 0.94:
                shade -= 1
            out[y, x] = (*c[max(0, min(3, shade))][:3], 255)
    for _ in range(60):  # frayed ends and loose threads at the edge
        a = rng.uniform(0, math.tau)
        x, y = int(cx + math.cos(a) * (W / 2 - 0.5)), int(cy + math.sin(a) * (H / 2 - 0.5))
        for k in range(int(rng.integers(1, 3))):
            xx_, yy_ = x + int(round(math.cos(a) * (k + 1))), y + int(round(math.sin(a) * (k + 1)))
            if 0 <= xx_ < W and 0 <= yy_ < H and out[yy_, xx_, 3] == 0:
                out[yy_, xx_] = (*cols[ring_cols[0]][1][:3], 255)
    return out
