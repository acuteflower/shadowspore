#!/usr/bin/env python3
"""Bake Ellie's leather cover, page block and pressed fern at the game's 1× pixel scale."""

from math import sin

from gen_art import CLEAR, ROOT, hexc, noise, write_png


OUT = ROOT / "ui" / "journal"
INK = hexc("191020")
BARK = tuple(hexc(c) for c in ("251a2c", "34263a", "412e44", "523a4f", "6a4e61"))
BRASS = tuple(hexc(c) for c in ("4c3633", "745338", "ac7f46", "d2a766", "edd195"))
PAPER = tuple(hexc(c) for c in ("8e756f", "aa8b78", "c1a48b", "cbb79c", "d5c3a6", "dfcdb0"))
LINEN = tuple(hexc(c) for c in ("a08a7c", "bcab94", "caba9e", "d7c7ae"))
BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def canvas(width, height):
    return [[CLEAR] * width for _ in range(height)]


def box(pixels, x, y, width, height, color):
    x0, x1 = max(0, x), min(len(pixels[0]), x + width)
    for yy in range(max(0, y), min(len(pixels), y + height)):
        pixels[yy][x0:x1] = [color] * max(0, x1 - x0)


def step_line(pixels, start, end, color, thick=1):
    x0, y0 = start
    dx, dy = end[0] - x0, end[1] - y0
    length = max(abs(dx), abs(dy), 1)
    for i in range(length + 1):
        box(pixels, x0 + round(dx * i / length), y0 + round(dy * i / length), thick, thick, color)


def plate(pixels, bounds, seed, material):
    """Cut stair-stepped corners, then shade in discrete bands like the hut materials."""
    x, y, width, height = bounds
    for j in range(height):
        bevel = (7, 5, 4, 3, 2, 2, 1)[min(j, height - j - 1, 6)]
        for i in range(bevel, width - bevel):
            edge = min(i - bevel, width - bevel - 1 - i, j, height - 1 - j)
            lit = i < 8 or j < 7
            light = BAYER[j % 4][i % 4]
            grain = noise(i // 6, (j + i // 4) // 3, seed)
            if material == "leather":
                if edge == 0:
                    color = INK
                elif edge <= 2:
                    color = BARK[3 if lit else 0]
                else:
                    band = 2 if lit or i < width * 0.28 else 1
                    if grain < 32 and light < 9:
                        band -= 1
                    elif grain > 223 and light < (11 if edge < 14 else 5):
                        band += 1
                    color = BARK[band]
            else:
                gutter = width - 1 - i if material == "left" else i
                # Muted fibre clusters grow denser at the thumb edge and at the binding.
                if edge <= 1:
                    color = PAPER[2 if lit else 1]
                elif gutter < 8:
                    color = PAPER[2 + min(2, gutter // 3)]
                elif edge < 5 or (grain < 26 and light < (7 if edge < 19 else 2)):
                    color = PAPER[3]
                elif grain > 240 and light < 5:
                    color = PAPER[5]
                else:
                    color = PAPER[4]
            pixels[y + j][x + i] = color


def stitches(pixels, x, y, width, height, seed):
    for side in (y, y + height - 2):
        for offset in range(5, width - 5, 8):
            lift = int(noise(offset, side, seed) > 128)
            box(pixels, x + offset, side + lift, 5, 2, INK)
            box(pixels, x + offset, side + lift, 3, 1, BARK[4])
    for side in (x, x + width - 2):
        for offset in range(6, height - 6, 8):
            shift = int(noise(side, offset, seed) > 115)
            box(pixels, side + shift, y + offset, 2, 5, INK)
            box(pixels, side + shift, y + offset, 1, 3, BARK[4])


def clasp(pixels, x, y, bottom=False):
    """A little hammered corner with a bent lip and one rivet."""
    for j, width in enumerate((9, 13, 14, 14, 11, 9, 7, 6, 5, 4, 3)):
        yy = y + 10 - j if bottom else y + j
        left = x + 14 - width if bottom else x
        box(pixels, left, yy, width, 1, INK)
        if width > 3:
            box(pixels, left + 1, yy, width - 2, 1, BRASS[2 if j in (1, 3, 5) else 1])
        if j in (2, 4):
            box(pixels, left + 1, yy, width - 3, 1, BRASS[3])
    box(pixels, x + (9 if bottom else 4), y + (6 if bottom else 3), 3, 3, BRASS[0])
    box(pixels, x + (9 if bottom else 4), y + (6 if bottom else 3), 2, 1, BRASS[4])


def scuffs(pixels, bounds, seed):
    x, y, width, height = bounds
    for i in range(18):
        px = x + 7 + noise(i, 0, seed) * (width - 16) // 256
        py = y + (3 + i % 5 if i % 2 == 0 else height - 11 + i % 5)
        step_line(pixels, (px, py), (px + 3 + i % 8, py + (i % 3 - 1)), BARK[4 if i % 5 == 0 else 3])


def fore_edge(pixels, x, y, width, height, side, seed):
    """Thumb wear collects in broad groups at the exposed edge of each leaf."""
    for row in range(4, height - 3):
        local = noise(row // 5, side, seed) // 62
        depth = max(0, round(7 * sin(row * 0.07 + seed) - 1)) + local
        for offset in range(depth):
            px = x + offset if side < 0 else x + width - 1 - offset
            if offset < 2 or BAYER[row % 4][px % 4] < 9:
                pixels[y + row][px] = PAPER[2 if offset < 2 else 3]


def spread():
    pixels = canvas(568, 272)
    plate(pixels, (1, 2, 566, 268), 81, "leather")
    stitches(pixels, 8, 7, 552, 255, 22)
    scuffs(pixels, (1, 2, 566, 268), 122)
    # Page stacks: several uneven fore-edges and the darker spine behind them.
    for x, w in ((13, 271), (284, 270)):
        box(pixels, x + 2, 17, w - 4, 241, PAPER[0])
        box(pixels, x + 3, 17, w - 6, 238, PAPER[1])
        for y in (249, 252, 255):
            for offset in range(5, w - 5, 8):
                box(pixels, x + offset, y + noise(offset, y, 3) % 2, 5 + offset % 3, 1, PAPER[2])
    plate(pixels, (14, 12, 269, 239), 29, "left")
    plate(pixels, (285, 13, 268, 238), 62, "right")
    fore_edge(pixels, 16, 13, 265, 234, -1, 21)
    fore_edge(pixels, 288, 13, 263, 234, 1, 43)
    box(pixels, 282, 19, 3, 228, BARK[0])
    box(pixels, 283, 21, 1, 223, BARK[3])
    for y in (33, 79, 129, 182, 224):
        box(pixels, 279, y, 10, 4, PAPER[0])
        box(pixels, 280, y, 7, 1, LINEN[1])
        box(pixels, 281, y + 1, 2, 2, BARK[0])
        box(pixels, 285, y + 1, 2, 2, BARK[2])
    for j in range(13):
        box(pixels, 539 + j, 248 - j, 13 - j, 1, PAPER[1])
        box(pixels, 541 + j, 247 - j, 11 - j, 1, PAPER[5 if j < 8 else 3])
    step_line(pixels, (539, 248), (551, 236), LINEN[3])
    clasp(pixels, 5, 4)
    clasp(pixels, 549, 254, bottom=True)
    return pixels


def cover():
    pixels = canvas(236, 272)
    plate(pixels, (1, 2, 234, 268), 9, "leather")
    box(pixels, 10, 8, 17, 255, BARK[0])
    box(pixels, 12, 9, 8, 252, BARK[2])
    box(pixels, 12, 9, 1, 252, BARK[4])
    for y in (46, 111, 182, 228):
        box(pixels, 10, y, 16, 8, INK)
        box(pixels, 10, y + 1, 15, 5, BARK[3])
        box(pixels, 13, y + 1, 10, 1, BARK[4])
    stitches(pixels, 33, 13, 186, 244, 5)
    scuffs(pixels, (1, 2, 234, 268), 42)
    # Tooling is pressed into the leather. Worn ridges only catch light on the upper side.
    for side in (-1, 1):
        for i in range(6):
            x, y = 118 + 3 * i, 192 - 5 * i
            end = (x + side * (19 - i * 2), y - 8)
            step_line(pixels, (x, y), end, BARK[0], 3)
            step_line(pixels, (x, y - 1), (end[0], end[1] - 1), BARK[4])
    step_line(pixels, (110, 204), (138, 158), BARK[0], 3)
    step_line(pixels, (110, 202), (137, 158), BARK[4])
    # Rounded closure strap and a brass catch that reaches over the fore-edge.
    for j, cut in enumerate((5, 3, 2, 1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 5)):
        box(pixels, 207 + cut, 132 + j, 26 - cut, 1, INK if j in (0, 13) else BARK[3])
        if j in (2, 3, 11):
            box(pixels, 209 + cut, 132 + j, 22 - cut, 1, BARK[4 if j == 2 else 2])
    box(pixels, 213, 136, 7, 6, BRASS[0])
    box(pixels, 214, 137, 5, 4, BRASS[2])
    box(pixels, 214, 137, 2, 1, BRASS[4])
    clasp(pixels, 215, 9)
    clasp(pixels, 215, 251, bottom=True)
    return pixels


def fern():
    pixels = canvas(82, 54)
    # The living glowfern's cool greens fade to teal and olive once pressed.
    shadow, stem, leaf, face, light = (hexc(c) for c in ("343a37", "66664e", "4e6350", "71815e", "a3a874"))
    points = [(8 + x, 45 - round(x * 0.56 + 3 * sin(x * 0.08))) for x in range(61)]
    for i in range(11, 59, 6):
        x, y = points[i]
        for direction in (-1, 1):
            length = (18 if direction > 0 else 15) - i // 5
            for j in range(1, length + 1):
                dx = round(j * (1.1 if direction > 0 else 0.54))
                width = min(4, j + 1, length - j + 1)
                at_x, at_y = x + dx - width // 2, y + direction * j
                box(pixels, at_x, at_y, width + 1, 1, shadow)
                box(pixels, at_x, at_y, width, 1, face if j % 4 != 0 else leaf)
                if j in (3, 6, 9) and width > 2:
                    box(pixels, at_x + 1, at_y, 1, 1, light)
    for start, end in zip(points, points[1:]):
        step_line(pixels, (start[0], start[1] + 1), (end[0], end[1] + 1), shadow)
        step_line(pixels, start, end, stem)
    for x, y in ((8, 40), (56, 13)):
        for k in range(13):
            box(pixels, x + k, y + k // 4, 1, 4, LINEN[1 if k in (0, 12) else 3])
            if k % 3 == 1:
                box(pixels, x + k, y + k // 4 + 1, 1, 1, LINEN[2])
    return pixels


if __name__ == "__main__":
    for name, image in (("spread", spread()), ("cover", cover()), ("pressed_fern", fern())):
        write_png(OUT / f"{name}.png", len(image[0]), len(image), image)
