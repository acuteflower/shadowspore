#!/usr/bin/env python3
"""Ellie's picture for the dialogue box, painted by hand in code as a 2D pixel art illustration (needs numpy): the whole figure, anime styled, about
264 px tall (the sprite is 42 px), cel shaded in the world's palette, lit from the top left. Shapes are filled from smooth outlines, shaded from the
shape's own rim (a lit edge on the upper left, a shadowed one on the lower right, flat in between), inked and detailed by hand: the face with its
big violet eyes, the long white hair, the black-violet outfit with gold and violet trim. 4 idle frames (breathing, the hair moving) in two moods:
healthy, and hurt (pale, worried face, a gloved hand pressed on a wound at the waist, blood on her clothes, skin and hair).
  assets/ui/portrait_ellie.png   8 frames of 176x264: frames 0-3 healthy, 4-7 hurt.   Usage: python3 tools/art_portrait.py [preview.png]"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

W, H = 176, 264
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
LIGHT = np.array([-0.62, -0.78])

HAIR = [hexc(c) for c in ("5e5496", "8f84c2", "bdb3e4", "e9e3f7", "fffaf0")]
SKIN = [hexc(c) for c in ("b87868", "d79a88", "efc0a8", "f9dcc6", "fff1e4")]
SKIN_HURT = [hexc(c) for c in ("8f8296", "b8a2ad", "d8c4c4", "eadad4", "f6ece8")]
LEATHER = [hexc(c) for c in ("09060f", "150f22", "2c2347", "4a3d78", "6a5aa6")]
VIOLET = [hexc(c) for c in ("34185e", "6636ad", "9468ee", "cbaaff")]
GOLD = [hexc(c) for c in ("6f5020", "b48a38", "e6c468", "fff0b0")]
BOOT = [hexc(c) for c in ("1e1626", "372a40", "574560", "7d6a86")]
BLOOD = [hexc(c) for c in ("2e040c", "5a0818", "8a1226", "b8283a")]
INK = hexc("120c1c")


# ------------------------------------------------------------------ a tiny painter
def fill_polygon(points):
    """Boolean mask of the closed polygon (pixel centres, even-odd)."""
    mask = np.zeros((H, W), dtype=bool)
    pts = np.array(points, dtype=float)
    n = len(pts)
    for y in range(max(0, int(pts[:, 1].min())), min(H, int(pts[:, 1].max()) + 1)):
        yc = y + 0.5
        xs = []
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 <= yc < y1) or (y1 <= yc < y0):
                xs.append(x0 + (yc - y0) / (y1 - y0) * (x1 - x0))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            mask[y, max(0, int(round(a))):min(W, int(round(b)))] = True
    return mask


def smooth(points, closed=True, per=6):
    """Catmull-Rom through the points (a soft outline from a few corners)."""
    pts = [np.array(p, dtype=float) for p in points]
    n = len(pts)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0, p1, p2, p3 = pts[(i - 1) % n] if closed or i > 0 else pts[0], pts[i], pts[(i + 1) % n], pts[(i + 2) % n] if closed or i + 2 < n else pts[-1]
        for k in range(per):
            t = k / per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    if not closed:
        out.append(pts[-1])
    return out


def shape(points, closed=True):
    return fill_polygon(smooth(points, closed))


def box_blur(a, r, passes=3):
    out = a.astype(float)
    k = 2 * r + 1
    for _ in range(passes):
        for axis in (0, 1):
            pad = np.pad(out, [(r + 1, r) if ax == axis else (0, 0) for ax in (0, 1)], mode="edge")
            c = np.cumsum(pad, axis=axis)
            out = (np.take(c, range(k, c.shape[axis]), axis=axis) - np.take(c, range(0, c.shape[axis] - k), axis=axis)) / k
    return out


class Canvas:
    def __init__(self):
        self.img = np.zeros((H, W, 4), dtype=np.uint8)

    def paint(self, mask, ramp, r=5, strength=1.0, shift=0.0, ink=INK, dither=0.35, rim=True):
        """Fill `mask` with the ramp, shaded from the shape's own rim: lit on the upper left, shadowed on the lower right, flat in between; inked."""
        if not mask.any():
            return
        h = box_blur(mask, r)
        gy, gx = np.gradient(h)
        nx, ny = -gx, -gy
        mag = np.sqrt(nx * nx + ny * ny + 0.0016)
        lit = (nx * LIGHT[0] + ny * LIGHT[1]) / mag * np.clip(mag * r * 2.2, 0, 1)
        ys, xs = np.nonzero(mask)
        n = len(ramp)
        base = 0.46 + shift
        for y, x in zip(ys, xs):
            v = base + 0.52 * strength * lit[y, x] + (BAYER[y % 4, x % 4] - 0.5) * dither * 0.35
            self.img[y, x] = ramp[int(np.clip(v * n, 0, n - 1))]
        if ink is not None:
            edge = mask & ~(np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1))
            self.img[edge] = ink if not isinstance(ink, list) else ink[0]

    def fill(self, mask, color):
        self.img[mask] = color

    def line(self, points, color, width=1.0, closed=False, smooth_it=True):
        pts = smooth(points, closed, 5) if smooth_it and len(points) > 2 else [np.array(p, float) for p in points]
        for a, b in zip(pts, pts[1:]):
            steps = max(1, int(np.linalg.norm(b - a) * 1.5))
            for i in range(steps + 1):
                p = a + (b - a) * i / steps
                self.dot(p[0], p[1], color, width)

    def dot(self, x, y, color, width=1.0):
        r = width / 2.0
        for yy in range(int(math.floor(y - r)), int(math.ceil(y + r)) + 1):
            for xx in range(int(math.floor(x - r)), int(math.ceil(x + r)) + 1):
                if 0 <= xx < W and 0 <= yy < H and (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2 <= max(r * r, 0.26):
                    self.img[yy, xx] = color

    def px(self, x, y, color):
        if 0 <= x < W and 0 <= y < H:
            self.img[int(y), int(x)] = color


def mix(a, b, k):
    return tuple(int(a[i] * (1 - k) + b[i] * k) for i in range(3)) + (255,)


# ------------------------------------------------------------------ Ellie
def draw(frame, hurt_mood):
    cv = Canvas()
    t = frame / 4.0 * math.tau
    breath = math.sin(t)
    bob = 0.0 + 1.2 * (0.5 + 0.5 * breath)  # chest and head rise a little
    sway = math.sin(t + 1.0)  # the hair
    skin = SKIN_HURT if hurt_mood else SKIN
    lean = 3.0 if hurt_mood else 0.0  # bent a little over the wound

    def P(x, y, g=1.0):  # a point on the body: the upper body shifts with breathing and leaning
        up = max(0.0, min(1.0, (170.0 - y) / 150.0))
        return (x + lean * up * up * 1.4, y + bob * up * g)

    # ---------------------------------------------------------------- back hair: a long fall behind everything
    back = [P(60, 40), P(54, 70), P(44, 120), P(38, 175), P(36 + sway, 226), P(46 + sway, 244), P(56, 222), P(60, 178), P(66, 150),
            P(112, 150), P(116, 178), P(122, 222), P(130 - sway, 244), P(140 - sway, 226), P(138, 175), P(132, 120), P(122, 70), P(116, 40), P(100, 16), P(76, 16)]
    m = shape(back)
    cv.paint(m, HAIR, r=7, strength=0.7, shift=0.1)
    # ---------------------------------------------------------------- legs and boots
    for side in (-1, 1):
        cx = 88 + side * 13
        leg = shape([P(cx - 10, 190), P(cx + 10, 190), P(cx + 9, 232), P(cx + 7, 262), P(cx - 9, 262), P(cx - 9, 232)])
        cv.paint(leg, LEATHER, r=4, strength=0.9)
        boot = shape([P(cx - 10, 226), P(cx + 10, 226), P(cx + 10, 264), P(cx - 11, 264), P(cx - 11, 236)])
        cv.paint(boot, BOOT, r=4)
        cv.fill(fill_polygon([(cx - 10, 229), (cx + 10, 229), (cx + 10, 232), (cx - 10, 232)]), VIOLET[2])  # violet band at the top of the boot
        cv.line([(cx - 10, 229), (cx + 10, 229)], VIOLET[0], 1, smooth_it=False)
        cv.line([(cx - 8, 252), (cx + 8, 252)], GOLD[2], 1, smooth_it=False)  # a gold buckle
        cv.fill(fill_polygon([(cx - 2, 250), (cx + 2, 250), (cx + 2, 254), (cx - 2, 254)]), GOLD[1])
    # ---------------------------------------------------------------- the right arm (viewer's left): hanging, with the bracer and a glove
    arm = shape([P(58, 94), P(66, 92), P(62, 124), P(62, 150), P(54, 150), P(52, 124)], True)
    cv.paint(arm, skin, r=3)
    sleeve = shape([P(52, 128), P(63, 128), P(63, 152), P(52, 152)])
    cv.paint(sleeve, LEATHER, r=3)
    cv.fill(fill_polygon([P(52, 128), P(63, 128), P(63, 131), P(52, 131)]), VIOLET[2])
    glove = shape([P(51, 152), P(64, 152), P(64, 166), P(58, 170), P(51, 164)])
    cv.paint(glove, LEATHER, r=3)
    # ---------------------------------------------------------------- skirt: layered, flared, with a violet hem
    skirt = [P(62, 138), P(114, 138), P(128, 196), P(122, 204), P(116, 198), P(108, 206), P(100, 198), P(92, 207), P(84, 198), P(76, 206), P(68, 198),
             P(60, 204), P(54, 196)]
    cv.paint(shape(skirt), LEATHER, r=7, strength=0.9)
    for i in range(7):  # folds
        x = 66 + i * 8
        cv.line([P(x, 142), P(x - 3 + (i - 3), 170), P(x - 5 + 1.5 * (i - 3), 200)], LEATHER[0], 1)
        cv.line([P(x + 1, 146), P(x - 2 + (i - 3), 172)], LEATHER[3], 1)
    hem = [P(54, 196), P(60, 204), P(68, 198), P(76, 206), P(84, 198), P(92, 207), P(100, 198), P(108, 206), P(116, 198), P(122, 204), P(128, 196)]
    cv.line(hem, VIOLET[2], 2, smooth_it=False)
    cv.line([(p[0], p[1] - 2) for p in hem], VIOLET[1], 1, smooth_it=False)
    # ---------------------------------------------------------------- torso: the corset, a slim waist, the neckline trimmed in violet
    torso = [P(64, 92), P(112, 92), P(116, 112), P(108, 138), P(106, 148), P(70, 148), P(68, 138), P(60, 112)]
    cv.paint(shape(torso), LEATHER, r=6, strength=1.0)
    cv.line([P(88, 104), P(88, 146)], VIOLET[2], 1, smooth_it=False)  # the lacing
    for y in range(106, 146, 5):
        cv.line([P(84, y), P(92, y + 2)], VIOLET[1], 1, smooth_it=False)
        cv.line([P(92, y), P(84, y + 2)], VIOLET[1], 1, smooth_it=False)
    for side in (-1, 1):  # the bust, a lit curve
        cv.line([P(88 + side * 3, 98), P(88 + side * 13, 108), P(88 + side * 20, 112)], LEATHER[3], 1)
    cv.line([P(64, 93), P(76, 100), P(88, 97), P(100, 100), P(112, 93)], VIOLET[2], 2)  # neckline trim
    belt = shape([P(66, 142), P(110, 142), P(110, 150), P(66, 150)])
    cv.paint(belt, LEATHER, r=2, strength=0.6)
    cv.fill(fill_polygon([P(84, 140), P(92, 140), P(92, 152), P(84, 152)]), GOLD[1])  # buckle
    cv.fill(fill_polygon([P(86, 142), P(90, 142), P(90, 150), P(86, 150)]), GOLD[3])
    cv.fill(fill_polygon([P(85, 145), P(89, 145), P(89, 147), P(85, 147)]), GOLD[0])
    # ---------------------------------------------------------------- neck and the crystal choker
    neck = shape([P(80, 78), P(96, 78), P(97, 94), P(79, 94)])
    cv.paint(neck, skin, r=3, shift=-0.1)
    cv.fill(fill_polygon([P(78, 84), P(98, 84), P(98, 89), P(78, 89)]), LEATHER[1])
    cv.fill(fill_polygon([P(85, 86), P(91, 86), P(91, 94), P(85, 94)]), VIOLET[2])
    cv.fill(fill_polygon([P(87, 87), P(89, 87), P(89, 91), P(87, 91)]), VIOLET[3])
    # ---------------------------------------------------------------- the left arm (viewer's right): bent, the hand on the waist
    if hurt_mood:
        up_arm = shape([P(110, 94), P(120, 98), P(122, 124), P(112, 128)])
        cv.paint(up_arm, skin, r=3)
        fore = shape([P(112, 124), P(122, 126), P(112, 148), P(102, 144)])
        cv.paint(fore, LEATHER, r=3)
        cv.line([P(110, 130), P(119, 134)], VIOLET[2], 2, smooth_it=False)
    else:
        up_arm = shape([P(110, 94), P(120, 98), P(124, 124), P(116, 128)])
        cv.paint(up_arm, skin, r=3)
        fore = shape([P(116, 126), P(125, 126), P(127, 152), P(118, 152)])
        cv.paint(fore, LEATHER, r=3)
        cv.fill(fill_polygon([P(116, 130), P(126, 130), P(126, 133), P(116, 133)]), VIOLET[2])
        glove2 = shape([P(117, 152), P(128, 152), P(127, 166), P(122, 170), P(116, 164)])
        cv.paint(glove2, LEATHER, r=3)
    # ---------------------------------------------------------------- the head
    face = shape([P(68, 42), P(88, 34), P(108, 42), P(110, 58), P(104, 72), P(88, 80), P(72, 72), P(66, 58)])
    cv.paint(face, skin, r=6, strength=0.8, shift=0.14, ink=skin[0])
    # ears hidden; the eyes: large, violet, with a dark upper lid, highlights and lashes
    for side in (-1, 1):
        ex = 88 + side * 11 + (lean * 0.3)
        ey = 59 + bob * 0.4
        squint = 2 if hurt_mood and side == 1 else 0
        eye = shape([P(ex - 7, ey - 4 + squint), P(ex, ey - 7 + squint), P(ex + 7, ey - 4 + squint), P(ex + 7, ey + 3), P(ex, ey + 8), P(ex - 7, ey + 3)])
        cv.fill(eye, hexc("f4effa"))
        iris = shape([P(ex - 5, ey - 4 + squint), P(ex + 5, ey - 4 + squint), P(ex + 5, ey + 4), P(ex, ey + 8), P(ex - 5, ey + 4)])
        iris &= eye
        for y in range(H):
            for x in np.nonzero(iris[y])[0]:
                k = (y - (ey - 5)) / 13.0
                cv.img[y, x] = VIOLET[3] if k > 0.78 else (VIOLET[2] if k > 0.45 else (VIOLET[1] if k > 0.15 else VIOLET[0]))
        cv.fill(shape([P(ex - 2, ey - 1 + squint * 0.5), P(ex + 2, ey - 1 + squint * 0.5), P(ex + 2, ey + 4), P(ex - 2, ey + 4)]) & eye, hexc("1a0c30"))  # the pupil
        cv.px(ex - 3, ey - 3, hexc("ffffff"))
        cv.px(ex - 4, ey - 3, hexc("ffffff"))
        cv.px(ex - 3, ey - 2, hexc("ffffff"))
        cv.px(ex + 2, ey + 3, hexc("e9deff"))
        cv.line([P(ex - 8, ey - 3 + squint), P(ex, ey - 8 + squint), P(ex + 8, ey - 4 + squint)], INK, 2)  # the upper lid
        cv.line([P(ex + side * 7, ey - 4 + squint), P(ex + side * 10, ey - 6 + squint)], INK, 1, smooth_it=False)  # a lash flick on the outer side
        cv.line([P(ex - 6, ey + 6), P(ex, ey + 8.5), P(ex + 6, ey + 6)], skin[0], 1)
        brow_y = ey - 12
        if hurt_mood:  # worried brows, slanting up on the inner side
            cv.line([P(ex - side * 8 + 0, brow_y - 3), P(ex, brow_y), P(ex + side * 7, brow_y + 2)], HAIR[1], 1)
        else:
            cv.line([P(ex - 7, brow_y + 1), P(ex, brow_y - 1), P(ex + 7, brow_y + 1)], HAIR[1], 1)
    # nose, mouth, cheeks
    cv.line([P(88, 66), P(87, 69), P(89, 70)], skin[0], 1)
    if hurt_mood:
        cv.fill(shape([P(83, 73), P(88, 72), P(93, 73), P(91, 76), P(85, 76)]), hexc("5a1d2e"))  # a small, tight, open mouth
        cv.fill(fill_polygon([P(85, 73), P(91, 73), P(91, 74), P(85, 74)]), hexc("f4effa"))
        cv.line([P(78, 63), P(78, 70)], hexc("b8c8e8"), 1)  # a tear
        cv.px(77 + lean * 0.3, 71 + bob * 0.4, hexc("e8f4ff"))
    else:
        cv.line([P(84, 73), P(88, 75), P(92, 73)], hexc("a8506a"), 1)
    for side in (-1, 1):
        for k in range(3):
            cv.line([P(88 + side * 17 - 3, 68 + k * 0), P(88 + side * 17 + 3, 68)], mix(skin[2], hexc("e87090"), 0.5 if not hurt_mood else 0.25), 2)
    # ---------------------------------------------------------------- hair in front: the fringe, locks at the temples, long locks over the shoulders
    fringe = [P(64, 46), P(70, 30), P(88, 22), P(106, 30), P(112, 46), P(108, 54), P(100, 40), P(94, 52), P(88, 38), P(82, 52), P(76, 40), P(68, 54)]
    cv.paint(shape(fringe), HAIR, r=5, strength=0.85, shift=0.14)
    for i in range(6):
        x = 70 + i * 7
        cv.line([P(x, 28), P(x + (i - 2.5), 40)], HAIR[2], 1)
    crown = shape([P(66, 40), P(72, 20), P(88, 12), P(104, 20), P(110, 40), P(104, 30), P(88, 20), P(72, 30)])
    cv.paint(crown, HAIR, r=5, strength=0.9, shift=0.16)
    cv.line([P(74, 22), P(88, 16), P(100, 22)], HAIR[4], 1)
    for side in (-1, 1):
        lock = [P(88 + side * 22, 34), P(88 + side * 28, 56), P(88 + side * 30, 90), P(88 + side * 27, 124 + sway * side), P(88 + side * 24, 148 + sway * side),
                P(88 + side * 20, 124), P(88 + side * 20, 92), P(88 + side * 21, 60)]
        cv.paint(shape(lock), HAIR, r=4, strength=0.9, shift=0.14)
        cv.line([P(88 + side * 25, 50), P(88 + side * 27, 100), P(88 + side * 25, 140)], HAIR[1], 1)
    # a hair pin with a violet gem at the temple
    cv.fill(fill_polygon([P(110, 30), P(113, 30), P(113, 36), P(110, 36)]), GOLD[2])
    cv.fill(fill_polygon([P(109, 36), P(114, 36), P(114, 40), P(109, 40)]), VIOLET[2])
    cv.px(110, 37, VIOLET[3])
    # ---------------------------------------------------------------- blood and bruises when hurt
    if hurt_mood:
        wound = shape([P(94, 138), P(108, 136), P(113, 148), P(104, 158), P(92, 150)])
        cv.paint(wound, BLOOD, r=3, strength=0.8, ink=BLOOD[0])
        hand = shape([P(98, 140), P(110, 139), P(112, 150), P(102, 154), P(96, 148)])  # the glove pressed on it, red between the fingers
        cv.paint(hand, LEATHER, r=3)
        for fx in (100, 103, 106, 109):
            cv.line([P(fx, 141), P(fx, 150)], LEATHER[0], 1, smooth_it=False)
        cv.line([P(98, 151), P(106, 153), P(111, 150)], BLOOD[2], 1)
        for dx, ln in ((98, 34), (104, 24), (108, 40)):  # drips down the skirt
            cv.line([P(dx, 152), P(dx + 1, 152 + ln * 0.5), P(dx - 1, 152 + ln)], BLOOD[2], 2)
            cv.px(dx - 1, 154 + ln, BLOOD[3])
        for x, y, s_ in ((78, 160, 2), (70, 180, 2), (112, 172, 3), (84, 190, 2), (120, 150, 2), (66, 120, 2), (104, 118, 2)):
            cv.dot(x, y, BLOOD[1], s_)
        cv.line([P(110, 58), P(111, 68), P(109, 80)], BLOOD[2], 2)  # a trickle from the temple down the cheek
        cv.line([P(70, 98), P(66, 120)], BLOOD[1], 1)
        cv.line([P(100, 144), P(112, 134)], BLOOD[0], 1)  # on the glove
        for x, y in ((40, 220), (36, 232), (132, 226), (140, 236)):  # the hair tips are bloody too
            cv.dot(x + sway, y, BLOOD[1], 2)
    return cv.img


def main():
    frames = []
    for mood in (False, True):
        for i in range(4):
            frames.append(draw(i, mood))
    sheet = np.zeros((H, len(frames) * W, 4), dtype=np.uint8)
    for n, fr in enumerate(frames):
        sheet[:, n * W:(n + 1) * W] = fr
    rows = [[tuple(int(v) for v in sheet[y, x]) for x in range(sheet.shape[1])] for y in range(H)]
    write_png(ROOT / "ui" / "portrait_ellie.png", sheet.shape[1], H, rows)
    if len(sys.argv) > 1:
        bg = np.zeros_like(sheet)
        bg[:, :] = (50, 62, 76, 255)
        a = sheet[:, :, 3:4] / 255.0
        out = (bg[:, :, :3] * (1 - a) + sheet[:, :, :3] * a).astype(np.uint8)
        big = np.concatenate([out, np.full(out.shape[:2] + (1,), 255, dtype=np.uint8)], axis=2)
        write_png(Path(sys.argv[1]), big.shape[1], H, [[tuple(int(v) for v in big[y, x]) for x in range(big.shape[1])] for y in range(H)])
    print("portrait written")


if __name__ == "__main__":
    main()
