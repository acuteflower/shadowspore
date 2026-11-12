#!/usr/bin/env python3
"""The leg ring of a registered crow or raven (docs/pet_konzept.md 9.3) -> assets/wildlife/pet_marks.png.

An overlay sheet in the exact layout of assets/wildlife/corvid.png (62 columns x 48 rows of 48x48 frames, feet at (24, 35)) that holds, per frame, ONLY the
ring pixels, white: the leg is found in the finished picture within the central tarsus window, so the ring sits on the bird's own leg in every walking,
pecking, preening, hopping, roosting and landing frame and in all eight facings. The game tints the overlay with the bird's ring colour (data/pets.json register.ring_colors)
and lights it like the bird. No ring when the legs are tucked in flight/glide. Deterministic.
usage: py -3 tools/art_pet_marks.py [preview.png]"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets", "wildlife", "corvid.png")
OUT = os.path.join(HERE, "..", "assets", "wildlife", "pet_marks.png")
FW = FH = 48
COLS = 62
ROWS = 48          # six builds (crow 0-2, raven 3-5) x eight facings
TUCKED = set(range(30, 38)) | set(range(45, 54))


def ring_pixels(frame):
    """Pixels (x, y) of the ring for one frame: on the tarsus above the toes inside the central leg band."""
    alpha = frame[:, :, 3] > 0
    leg_band = np.zeros_like(alpha)
    leg_band[25:38, 18:31] = alpha[25:38, 18:31]
    ys = np.where(leg_band.any(axis=1))[0]
    if len(ys) < 2:
        return []
    bottom = int(ys[-1])
    row = max(25, bottom - 2)
    xs = np.where(leg_band[row])[0]
    if len(xs) == 0:
        row = bottom - 1
        xs = np.where(leg_band[row])[0]
        if len(xs) == 0:
            return []
    x = int(xs[0])
    pixels = [(x, row)]
    if x + 1 < FW and alpha[row, x + 1]:
        pixels.append((x + 1, row))
    elif row > 0 and alpha[row - 1, x]:
        pixels.append((x, row - 1))
    return pixels


def build():
    sheet = np.array(Image.open(SRC).convert("RGBA"))
    out = np.zeros_like(sheet)
    count = 0
    for r in range(ROWS):
        for c in range(COLS):
            if c in TUCKED:
                continue
            frame = sheet[r * FH:(r + 1) * FH, c * FW:(c + 1) * FW]
            for (x, y) in ring_pixels(frame):
                out[r * FH + y, c * FW + x] = (255, 255, 255, 255)
                count += 1
    return out, count


if __name__ == "__main__":
    out, count = build()
    Image.fromarray(out).save(OUT)
    print("wrote", os.path.normpath(OUT), count, "ring pixels")
    if len(sys.argv) > 1:   # preview: a few frames, bird + ring in gold, 6x
        sheet = np.array(Image.open(SRC).convert("RGBA"))
        tiles = []
        for r in (2, 18, 34):          # crow S, crow-build 2 S..., raven S
            for c in (0, 4, 10, 13, 16, 38):
                f = sheet[r * FH:(r + 1) * FH, c * FW:(c + 1) * FW].copy()
                m = out[r * FH:(r + 1) * FH, c * FW:(c + 1) * FW]
                f[m[:, :, 3] > 0] = (230, 196, 104, 255)
                tiles.append(f[16:44, 8:40])
        rows = [np.concatenate(tiles[i:i + 6], axis=1) for i in range(0, len(tiles), 6)]
        img = Image.fromarray(np.concatenate(rows, axis=0)).convert("RGBA")
        bg = Image.new("RGBA", img.size, (74, 92, 64, 255))
        bg.alpha_composite(img)
        bg.resize((bg.width * 6, bg.height * 6), Image.NEAREST).save(sys.argv[1])
