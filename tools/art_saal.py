#!/usr/bin/env python3
"""The entrance hall (data/interiors.json "flur_saal", written by tools/art_hallway.py through `make()`): a hall that runs from WEST to EAST. The corridor from Ellie's room comes in through the west wall into the
south aisle; the nave in the middle is divided from the aisles by two rows of tall pillars (side by side, so they never stack), a big carpet runs along it and up the steps at the east end to a second level
(a plain platform). Walls facing south are the only ones seen in this view, so the north aisle's locked door hangs in the north wall and the south aisle's is a narrow oblique door at its east end.
Everything is the same cut stone as the rest (tools/servant_floor.py, servant_wall.py, tended), the dark blue of the fortress for the carpets.
Layout in the hall's own px (x east, y south); the rect is W x H, its south edge is the top of the south wall (which hangs below it):
    rows:   north wall 0..72 | north aisle 72..168 | pillars 168..200 | nave 200..456 | pillars 456..488 | south aisle 488..584
    columns: west wall 0..16 | floor 16..592 (the aisles end at walls 592..608) | steps 608..848 (10 steps of 24 px, a rise of 140 px on the screen) | platform 848..976 | east wall 976..992
    the steps are a slope: walking east on them lifts her (Interior `slopes`), the platform lies 140 px higher on the screen than the nave
    python3 tools/art_saal.py [preview.png]     writes assets/interior/flur/saal_*.png and prints the size"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import servant_door  # noqa: E402
import servant_floor  # noqa: E402
import servant_wall  # noqa: E402
from stone_wear import Wear  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "interior" / "flur"
PAL = servant_wall.PAL
TENDED = Wear(moss=0.12, moss_reach=1.0, moss_hang=0.0, cracks=0.0, chips=0.1, pocks=0.5, stains=0.2, wash=0.3, grime=0.7, wide_joints=0.4, polish=1.0, moss_spots=())
WINE = [(8, 12, 30), (18, 28, 62), (30, 48, 98), (46, 72, 132)]
GOLD = [(88, 62, 30), (156, 120, 56), (214, 176, 96)]
INK = (6, 8, 20)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0

SIDE = 16
WALL = 76  # a wall picture: cap 14 + face 58 + 4 rows of contact shadow; its base lies 4 rows above its bottom
BASE = 72  # the north wall's foot, where the floor starts
NAVE_C, N_C, S_C = 328, 120, 536  # the middle rows of the nave and of the aisles
H = 584  # the hall's rect: its south edge is the top of the south wall (which hangs below)
X_FLOOR0, X_FLOOR1 = 16, 592  # the floor with the colonnade
X_ST0, STEPS, STEP_L, STEP_H = 608, 10, 24, 14  # the steps: 240 long, a rise of 140 px on the screen
X_ST1 = X_ST0 + STEPS * STEP_L  # 848
RISE = STEPS * STEP_H  # 140
X_PF0, X_PF1 = X_ST1, 976  # the platform
W = 992  # east wall 976..992
PILLAR_X = [64, 160, 256, 352, 448, 544]
PILLAR_FOOT = (190, 478)  # the feet of the north and the south row
CARPET_W, RUNNER_W = 72, 26
OPEN_Y0, OPEN_H = 504, 64  # the opening in the west wall the corridor comes through (the south aisle's west end)
DOOR_N_X = 548  # the north aisle's locked door in the north wall
DOOR_S = (584, 536)  # the south aisle's oblique door (its east end), x and the aisle's middle row


def hsh(x, y, seed):
    return ((x * 73856093 ^ y * 19349663 ^ seed * 83492791) % 1000) / 1000.0


def tone(x, y, base):
    b = BAYER[y % 4, x % 4]
    return PAL[max(0, min(5, base + (1 if b > 0.62 else 0) - (1 if b < 0.12 else 0)))]


def weave(length, width):
    """A carpet as a strip (width rows x length columns): an outline, a dark band, a thin gold line, a field of large diamonds (every 56 px) with a gold ring and a stud, cross-stitches between them."""
    out = np.zeros((width, length, 4), np.uint8)
    half = width / 2.0
    for y in range(width):
        for x in range(length):
            e = min(y, width - 1 - y)
            u = (x + 28) % 56
            if e == 0:
                col = INK
            elif e <= 2:
                col = WINE[0] if y > half else WINE[1]
            elif e == 3:
                col = GOLD[1] if (x + y) % 2 == 0 else GOLD[0]
            elif e <= 6:
                col = WINE[1] if (x + y) % 2 == 0 else WINE[2]
            else:
                fy = y - half + 0.5
                d = abs(u - 28) + abs(fy) * 0.9
                if abs(d - 22.0) < 1.1:
                    col = GOLD[2] if (x + y) % 2 == 0 else GOLD[1]
                elif d < 20.0:
                    col = WINE[1] if (x + y) % 2 == 0 else WINE[0]
                    if abs(d - 12.0) < 0.8:
                        col = GOLD[1] if (x + y) % 2 == 0 else GOLD[0]
                    elif d < 3.5:
                        col = GOLD[2] if (x + y) % 2 == 0 else GOLD[1]
                elif (u in (0, 55)) and abs(fy) < 5:
                    col = GOLD[1]
                else:
                    col = WINE[2] if (x + y) % 2 == 0 else WINE[3]
                    if hsh(x, y, 5) > 0.96:
                        col = WINE[1]
            if hsh(x, y, 9) > 0.985 and e > 0:
                col = tuple(min(255, c + 22) for c in col)
            out[y, x, :3] = col
            out[y, x, 3] = 255
    return out


def shade(img, x, y, amount):
    k = min(3, int(amount * 4.0 + BAYER[y % 4, x % 4]))
    img[y, x, :3] = (img[y, x, :3] * (1.0 - 0.2 * k) + np.array([22, 16, 40]) * 0.2 * k).astype(np.uint8)


def paste_h(floor, strip, cy, x0=0):
    """A carpet strip lying along the floor (rows = its width) with its middle row at cy, from column x0; a soft shadow below it and a hair above."""
    h, w = strip.shape[:2]
    y0 = cy - h // 2
    w = min(w, floor.shape[1] - x0)
    for x in range(x0, x0 + w):
        for dy, k in ((h, 0.45), (h + 1, 0.22), (-1, 0.18)):
            if 0 <= y0 + dy < floor.shape[0]:
                floor[y0 + dy, x, :3] = (floor[y0 + dy, x, :3] * (1.0 - k)).astype(np.uint8)
    floor[y0:y0 + h, x0:x0 + w, :] = strip[:, :w]


def floor_picture():
    """The floor of the colonnade (x 16..592, y 72..584, 576 x 512): the tended stone with a runner in each aisle and the nave's carpet running east to the steps; shadows at the north wall's foot and the west wall."""
    fw, fh = X_FLOOR1 - X_FLOOR0, H - BASE
    floor = servant_floor.floor_img(fw, fh + 6, seed=61, paths=(), damp=(), stains=(), wear=TENDED)[:fh].copy()
    run = weave(fw - 24, RUNNER_W)
    paste_h(floor, run, N_C - BASE, 24)
    paste_h(floor, run, S_C - BASE, 24)
    paste_h(floor, weave(fw - 24 + 16, CARPET_W), NAVE_C - BASE, 24)  # runs on under the steps' first tread
    for r in range(12):  # the north wall's foot in the north aisle
        for x in range(fw):
            shade(floor, x, r, (1.0 - r / 12.0) ** 1.6 * 0.85)
    for y in range(fh):  # the west wall's shadow
        for x in range(0, 9):
            shade(floor, x, y, (1.0 - x / 9.0) ** 1.5 * 0.7)
    return floor


def east_picture():
    """The stone mass round the steps (x 592..976, y 72..584): dressed stone seen from above, darker than the floor; the steps and the platform lie over it."""
    w, h = 976 - 592, H - BASE
    img = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            seam = (x + (y // 16) * 29) % 58 == 0 or y % 16 == 0
            img[y, x] = (*(PAL[0] if seam else tone(x, y, 2 + (1 if (x // 58 + y // 16) % 2 else 0))), 255)
    return img


def stairs_picture():
    """The steps (x 608..848, y 60..456 on the screen: 240 x 396): ten treads of 24 px, each 14 px higher than the one before it, so they climb up the screen to the east; a tread is the floor's own stone with its
    south edge lit, the step's south face below it is in shade with a joint at every step height; the carpet runs along them. Seen from the south in this view, the east-facing risers cannot be seen."""
    w, h = STEPS * STEP_L, 456 - (200 - RISE)
    tex = servant_floor.floor_img(w, h + 6, seed=67, paths=(), damp=(), stains=(), wear=TENDED, tone_bias=0.2)[:h]
    img = np.zeros((h, w, 4), np.uint8)
    top0 = 200 - RISE  # screen row 60 is local row 0
    carpet = weave(w, CARPET_W)
    f1 = 456 - top0  # the foot of the south faces
    for k in range(STEPS):
        x0, x1 = k * STEP_L, (k + 1) * STEP_L
        lift = STEP_H * (k + 1)
        t0, t1 = 200 - lift - top0, 456 - lift - top0  # the tread
        for x in range(x0, x1):
            for y in range(t0, t1):
                col = tex[y, x, :3].astype(float)
                if y == t0:
                    col = np.array(INK, float)
                elif y >= t1 - 2:
                    col = np.minimum(col * 1.25 + 14, 255)  # the lit south edge of the tread
                img[y, x, :3] = col.astype(np.uint8)
                img[y, x, 3] = 255
            for y in range(t1, f1):
                col = tex[y, x, :3].astype(float) * 0.55
                if (f1 - y) % STEP_H == 0:
                    col = col * 0.55
                if y == f1 - 1:
                    col = np.array(INK, float)
                img[y, x, :3] = col.astype(np.uint8)
                img[y, x, 3] = 255
        for y in range(t0, f1):  # the west and east ends of the step
            img[y, x0, :3] = (img[y, x0, :3] * 0.5).astype(np.uint8)
            img[y, x1 - 1, :3] = (img[y, x1 - 1, :3] * 0.65).astype(np.uint8)
        for x in range(x0, x1):  # the carpet on the tread
            for yy in range(CARPET_W):
                img[NAVE_C - CARPET_W // 2 + yy - lift - top0, x] = carpet[yy, x]
    return img


def platform_picture():
    """The second level (x 848..976, y 60..456 on the screen: 128 x 396): a plain floor of lighter stone (rows 60..316) with the carpet running on, and the south face of the level below it (rows 316..456), 140 px of
    dressed stone in shade with a joint every 14 px."""
    w, h = X_PF1 - X_PF0, 456 - (200 - RISE)
    tex = servant_floor.floor_img(w, h + 6, seed=79, paths=(), damp=(), stains=(), wear=TENDED, tone_bias=0.35)[:h]
    img = np.zeros((h, w, 4), np.uint8)
    surface = 456 - 200  # the floor's depth: 256 rows
    for y in range(h):
        for x in range(w):
            col = tex[y, x, :3].astype(float)
            if y >= surface:
                col *= 0.55
                if (h - 1 - y) % STEP_H == 0:
                    col *= 0.55
            if y == surface:
                col = np.minimum(col * 1.4 + 20, 255)
            if y == h - 1 or x == w - 1:
                col = np.array(INK, float)
            img[y, x, :3] = col.astype(np.uint8)
            img[y, x, 3] = 255
    carpet = weave(STEPS * STEP_L + w, CARPET_W)[:, STEPS * STEP_L:]
    cy = NAVE_C - RISE - (200 - RISE)  # the carpet's middle row inside the picture
    for yy in range(CARPET_W):
        img[cy - CARPET_W // 2 + yy, :, :] = carpet[yy, :w]
    for r in range(10):  # the north wall's foot (partly hidden behind the wall)
        for x in range(w):
            shade(img, x, 12 + r, (1.0 - r / 10.0) ** 1.6 * 0.6)
    return img


def endcap_picture():
    """The wall that closes an aisle at its east end (16 x 128): a lit top seen from above."""
    img = np.zeros((128, 16, 4), np.uint8)
    for y in range(128):
        for x in range(16):
            img[y, x] = (*(INK if x in (0, 15) else (PAL[1] if y % 20 == 0 else tone(x, y, 4 - (x * 3) // 16))), 255)
    return img


def pillar_picture():
    """A towering stone pillar (52 x 360) in the stone of the floor: a two-step plinth, then a round shaft 36 px thick that rises out of the picture and fades away into the dark far above (dithered
    away, so the top is never seen): lit on the left, dark on the right, fluted, a drum joint every 38 rows. Its foot stands 6 rows above the bottom; it fades out while it hides her (Interior `fades`)."""
    w, h = 52, 360
    img = np.zeros((h, w, 4), np.uint8)
    foot = h - 6
    tex = servant_floor.floor_img(w, h + 6, seed=77, paths=(), damp=(), stains=(), wear=TENDED)[:h]

    def stone(x, y, f):
        return np.clip(tex[y, x, :3].astype(float) * f, 0, 255).astype(np.uint8)

    def block(x0, x1, y0, y1, f):
        for y in range(y0, y1):
            for x in range(x0, x1):
                t = (x - x0) / float(max(1, x1 - x0 - 1))
                col = stone(x, y, f * (1.2 - 0.7 * t) * (1.12 if y == y0 + 1 else 1.0))
                if x in (x0, x1 - 1) or y in (y0, y1 - 1):
                    col = np.array(INK, np.uint8)
                img[y, x] = (*col, 255)

    block(0, 52, foot - 9, foot, 1.0)
    block(4, 48, foot - 17, foot - 9, 1.0)
    top = foot - 17
    for y in range(0, top):
        for x in range(8, 44):
            t = (x - 8) / 35.0
            f = 1.22 - 0.85 * t
            if (x - 8) % 9 == 4:
                f *= 0.8
            col = stone(x, y, f)
            if x in (8, 43):
                col = np.array(INK, np.uint8)
            if (top - y) % 38 == 0:
                col = (col * 0.45).astype(np.uint8)
            elif (top - y) % 38 == 1:
                col = np.clip(col.astype(float) * 1.25, 0, 255).astype(np.uint8)
            fade = (y - 40.0) / 150.0
            if y < 190 and BAYER[y % 4, x % 4] * 0.95 + 0.04 > fade:
                continue
            img[y, x] = (*col, 255)
    ys, xs = np.mgrid[0:h, 0:w]
    sh = (((xs - w / 2 - 4) / 24.0) ** 2 + ((ys - foot - 1) / 4.0) ** 2) <= 1.0
    for y, x in zip(*np.nonzero(sh & (img[..., 3] == 0))):
        img[y, x] = (0, 0, 0, 70)
    return img


def door_picture():
    """A locked plank door in a dressed stone frame, seen from the front (it hangs in the north wall): 56 x 52, its foot at the bottom."""
    leaf = servant_door.door_arr()
    leaf = np.concatenate([leaf[:12], leaf], axis=0)
    img = np.zeros((52, 56, 4), np.uint8)
    for y in range(52):
        for x in range(56):
            if y < 4 or x < 4 or x >= 52:
                lit = 5 if x < 8 else (4 if x < 40 else 3)
                img[y, x] = (*PAL[max(1, lit - (1 if y < 2 else 0))], 255)
                if x in (0, 55) or y == 0:
                    img[y, x, :3] = INK
    img[4:52, 4:52] = leaf
    for y in range(52):
        img[y, 3, :3] = PAL[0]
        img[y, 52, :3] = PAL[1]
    return img


def side_door_picture():
    """The same door seen obliquely on a wall that faces west (16 x 56): a slab of planks in a stone frame, narrowed and sheared a little so it reads as standing in that wall."""
    front = door_picture()
    img = np.zeros((60, 16, 4), np.uint8)
    for y in range(52):
        for x in range(16):
            src = front[y, int(x * 56 / 16), :].copy()
            if src[3]:
                src[:3] = (src[:3] * (0.7 + 0.3 * (x / 15.0))).astype(np.uint8)
                img[y + 2 + int(x * 0.25), x] = src
    return img


def cut_gap(side, y0, h):
    """An opening through a side wall picture (rows y0 .. y0+h): the stone ends in a lit edge on the north and a dark one on the south."""
    side[y0:y0 + h, :, 3] = 0
    side[y0 - 3:y0, :, :3] = PAL[5]
    side[y0 + h:y0 + h + 3, :, :3] = PAL[1]


def make():
    """Writes the pictures."""
    OUT.mkdir(parents=True, exist_ok=True)
    for name, arr in (("saal_floor.png", floor_picture()), ("saal_east.png", east_picture()), ("saal_stairs.png", stairs_picture()), ("saal_platform.png", platform_picture()),
                      ("saal_endcap.png", endcap_picture()), ("saal_pillar.png", pillar_picture()), ("saal_door.png", door_picture()), ("saal_door_side.png", side_door_picture())):
        Image.fromarray(arr).save(OUT / name)
    Image.fromarray(servant_wall.back_wall_img(W, 14, 58, 4, seed=73, wear=TENDED)).save(OUT / "saal_wall_n.png")
    Image.fromarray(servant_wall.back_wall_img(W, 14, 58, 4, seed=83, wear=TENDED)).save(OUT / "saal_wall_s.png")  # the south wall, seen from the south, hangs below the hall's rect
    for name, left in (("saal_side_l.png", True), ("saal_side_r.png", False)):
        side = servant_wall.side_img(left, H + 6, SIDE, seed=75, wear=TENDED)
        if left:
            cut_gap(side, OPEN_Y0, OPEN_H)  # the opening the corridor comes through
        Image.fromarray(side).save(OUT / name)
    return {"size": (W, H)}


if __name__ == "__main__":
    print("wrote", OUT, make())
    if len(sys.argv) > 1:
        canvas = Image.new("RGBA", (W, H + WALL), (10, 6, 16, 255))
        paste = lambda name, at: canvas.alpha_composite(Image.open(OUT / name).convert("RGBA"), at)
        paste("saal_floor.png", (X_FLOOR0, BASE))
        paste("saal_east.png", (592, BASE))
        paste("saal_stairs.png", (X_ST0, 200 - RISE))
        paste("saal_platform.png", (X_PF0, 200 - RISE))
        paste("saal_wall_n.png", (0, 0))
        for ys in (BASE, 456):
            paste("saal_endcap.png", (592, ys))
        paste("saal_side_l.png", (0, 0))
        paste("saal_side_r.png", (W - SIDE, 0))
        paste("saal_wall_s.png", (0, H))
        for foot in PILLAR_FOOT:
            for x in PILLAR_X:
                paste("saal_pillar.png", (x - 26, foot - 354))
        canvas.save(sys.argv[1])
