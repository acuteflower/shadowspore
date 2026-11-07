#!/usr/bin/env python3
"""The shadow face: the letterforms of everything that belongs to the void, above all the names of bosses. Run: py -3 tools/art_void_face.py [preview.png]
Writes assets/ui/void_face_<size>.png (atlases) and data/void_face.json (metrics), and a preview (docs/img/void_face.png).

This is NOT a pixel font made of blocks. The letters are drawn as razors: tall, narrow, a thick blade on one side and a hairline on the other, every stroke
ends in a needle, bowls are cut angular, feet and tails run out in thin tendrils. Each glyph is a handful of strokes (x, y, width in cap heights),
swept with variable width (Catmull-Rom where a stroke is smooth), rendered 8x oversampled and cut down to hard pixels at the size the game shows
them (no scaling at run time).

Each atlas pixel carries three channels for the shader (assets/shaders/void_title.gdshader):
  R = the letter (255 inside), G = the signed distance to its edge (128 = edge, more = deeper inside, +-SDF_RANGE px), B = the spine of the thick strokes
  (a one pixel line where the light of the void runs through the letter). A is always 255.
Coordinates of a glyph: x in cap heights from its left edge, y = 0 at the top of the capitals, 1 at the baseline; thorns and tendrils go beyond.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SS = 8
SDF_RANGE = 12.0
# size name -> cap height in px of the game picture (the face is shown 1:1)
SIZES = {"big": 44, "small": 17, "tiny": 11}
TOP_PAD = 0.34  # room above the caps (thorns), in cap heights
BOTTOM_PAD = 0.55  # room below the baseline (tendrils)
SIDE_PAD = 0.14
GAP = 0.2  # space between letters (cap heights)
SPACE = 0.5

# Gooey: every stroke is fattened (FAT + w * GROW), the sweep is blurred and cut again (a metaball: joins swell, corners melt, tips become drops).
FAT = 0.04
GROW = 1.5
BLUR = 0.034  # blur radius in cap heights
CUT = 0.43  # threshold after the blur (lower = fatter)
SIZE_WEIGHT = {"big": 1.0, "small": 0.78, "tiny": 0.7}
T = 0.115  # thick blade
M = 0.062
H = 0.03  # hairline


def catmull(points, per=14):
    """Dense Catmull-Rom through (x, y, w) points."""
    if len(points) < 3:
        out = []
        for i in range(len(points) - 1):
            for k in range(per):
                t = k / per
                out.append(tuple(a + (b - a) * t for a, b in zip(points[i], points[i + 1])))
        out.append(points[-1])
        return out
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3) for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(points[-1])
    return out


def S(*pts, smooth=False):
    return {"pts": [tuple(p) for p in pts], "smooth": smooth}


def blade(x, y0, y1, w=T):
    """A vertical dagger: needle at both ends, thick in the middle."""
    return S((x, y0 - 0.06, w * 0.18), (x, y0 + 0.05, w * 0.85), (x, y0 + 0.2, w), (x, y1 - 0.2, w), (x, y1 - 0.05, w * 0.85), (x, y1 + 0.06, w * 0.18))


def hair(x0, y0, x1, y1, w=H):
    """A hairline that thickens a little in the middle and runs out in needles."""
    return S((x0, y0, w * 0.3), ((x0 * 2 + x1) / 3, (y0 * 2 + y1) / 3, w * 0.95), ((x0 + x1 * 2) / 3, (y0 + y1 * 2) / 3, w * 0.95), (x1, y1, w * 0.3))


def diag(x0, y0, x1, y1, w=T):
    """A thick diagonal blade."""
    return S((x0, y0, w * 0.2), (x0 + (x1 - x0) * 0.25, y0 + (y1 - y0) * 0.25, w * 0.8), (x0 + (x1 - x0) * 0.6, y0 + (y1 - y0) * 0.6, w), (x1, y1, w * 0.2))


def tail(x, y, dx, dy, w=0.026):
    """A tendril of goo that runs away from the end of a stroke: a thin neck that swells into a drop."""
    return S((x, y, w * 1.1), (x + dx * 0.45, y + dy * 0.45, w * 0.55), (x + dx * 0.86, y + dy * 0.86, w * 0.5), (x + dx, y + dy, w * 1.9), smooth=True)


# ---------------------------------------------------------------------------------------------------- glyphs (width in cap heights, strokes)
GLYPHS = {}


def glyph(ch, width, *strokes):
    GLYPHS[ch] = {"w": width, "strokes": list(strokes)}


glyph("A", 0.80,
      hair(0.40, -0.05, 0.02, 1.0, 0.034), diag(0.40, -0.05, 0.78, 1.0, 0.115),
      hair(0.14, 0.7, 0.64, 0.7, 0.026), tail(0.02, 1.0, -0.07, 0.34), tail(0.78, 1.0, 0.06, 0.22, 0.02))
glyph("B", 0.66,
      blade(0.08, 0.0, 1.0),
      S((0.08, 0.02, 0.026), (0.4, 0.0, 0.03), (0.56, 0.13, 0.085), (0.5, 0.3, 0.06), (0.34, 0.46, 0.03), (0.08, 0.485, 0.026), smooth=True),
      S((0.08, 0.5, 0.026), (0.44, 0.5, 0.03), (0.63, 0.7, 0.1), (0.57, 0.89, 0.07), (0.38, 1.0, 0.03), (0.08, 0.99, 0.026), smooth=True),
      tail(0.08, 1.07, -0.02, 0.3))
glyph("C", 0.66,
      S((0.6, 0.1, 0), (0.44, -0.01, 0.034), (0.22, 0.07, 0.07), (0.08, 0.34, 0.115), (0.08, 0.66, 0.115), (0.22, 0.93, 0.07), (0.44, 1.01, 0.034), (0.62, 0.9, 0), smooth=True),
      tail(0.6, 0.1, 0.05, -0.2, 0.02))
glyph("D", 0.72,
      blade(0.08, 0.0, 1.0),
      S((0.08, 0.01, 0.028), (0.4, 0.0, 0.034), (0.62, 0.25, 0.09), (0.66, 0.5, 0.1), (0.62, 0.75, 0.09), (0.4, 1.0, 0.034), (0.08, 0.995, 0.028), smooth=True),
      tail(0.08, 1.07, -0.05, 0.3))
glyph("E", 0.58,
      blade(0.08, 0.0, 1.0), hair(0.08, 0.01, 0.56, 0.0, 0.04), hair(0.08, 0.5, 0.44, 0.5, 0.032), hair(0.08, 0.99, 0.6, 1.0, 0.045),
      tail(0.08, 1.07, -0.03, 0.34))
glyph("F", 0.55,
      blade(0.08, 0.0, 1.0), hair(0.08, 0.01, 0.55, 0.0, 0.04), hair(0.08, 0.5, 0.42, 0.5, 0.032),
      tail(0.08, 1.07, 0.0, 0.42))
glyph("G", 0.70,
      S((0.64, 0.1, 0), (0.46, -0.01, 0.034), (0.23, 0.07, 0.07), (0.08, 0.34, 0.115), (0.08, 0.66, 0.115), (0.23, 0.93, 0.07), (0.46, 1.01, 0.034), (0.62, 0.92, 0.07), (0.64, 0.58, 0.1), smooth=True),
      hair(0.36, 0.58, 0.66, 0.58, 0.035), tail(0.64, 0.1, 0.05, -0.2, 0.02))
glyph("H", 0.72,
      blade(0.08, 0.0, 1.0), blade(0.64, 0.0, 1.0, 0.1), hair(0.08, 0.5, 0.64, 0.5, 0.03),
      tail(0.08, 1.07, -0.04, 0.3), tail(0.64, 1.07, 0.03, 0.2, 0.02))
glyph("I", 0.16, blade(0.08, 0.0, 1.0), tail(0.08, 1.07, 0.02, 0.42))
glyph("J", 0.42,
      S((0.34, -0.07, 0), (0.34, 0.06, 0.1), (0.34, 0.7, 0.105), (0.26, 0.92, 0.07), (0.12, 1.0, 0.034), (0.02, 0.88, 0), smooth=True),
      tail(0.12, 1.0, -0.08, 0.34))
glyph("K", 0.70,
      blade(0.08, 0.0, 1.0), hair(0.62, -0.02, 0.1, 0.58, 0.032), diag(0.24, 0.42, 0.68, 1.0, 0.105),
      tail(0.08, 1.07, -0.03, 0.3), tail(0.68, 1.0, 0.05, 0.3, 0.02))
glyph("L", 0.55,
      blade(0.08, 0.0, 1.0), hair(0.08, 0.99, 0.6, 1.0, 0.05),
      tail(0.6, 1.0, 0.08, 0.18, 0.018), tail(0.08, 1.07, -0.04, 0.36))
glyph("M", 0.98,
      blade(0.08, 0.0, 1.0), blade(0.9, 0.0, 1.0, 0.1), hair(0.08, 0.0, 0.49, 0.78, 0.04), hair(0.9, 0.0, 0.49, 0.78, 0.03),
      tail(0.08, 1.07, -0.05, 0.3), tail(0.9, 1.07, 0.04, 0.34, 0.02), tail(0.49, 0.78, 0.0, 0.5, 0.022))
glyph("N", 0.76,
      blade(0.08, 0.0, 1.0), blade(0.68, 0.0, 1.0, 0.1), diag(0.08, 0.0, 0.68, 1.0, 0.09),
      tail(0.08, 1.07, -0.03, 0.26), tail(0.68, 1.07, 0.03, 0.34, 0.02))
glyph("O", 0.70,
      S((0.35, -0.01, 0.034), (0.57, 0.12, 0.075), (0.65, 0.5, 0.118), (0.57, 0.88, 0.075), (0.35, 1.01, 0.034), (0.13, 0.88, 0.075), (0.05, 0.5, 0.118), (0.13, 0.12, 0.075), (0.35, -0.01, 0.034), smooth=True),
      tail(0.35, 1.0, -0.02, 0.5, 0.024))
glyph("P", 0.62,
      blade(0.08, 0.0, 1.0),
      S((0.08, 0.02, 0.026), (0.4, 0.0, 0.03), (0.56, 0.15, 0.085), (0.5, 0.34, 0.06), (0.34, 0.5, 0.03), (0.08, 0.52, 0.026), smooth=True),
      tail(0.08, 1.07, -0.03, 0.34))
glyph("Q", 0.70,
      S((0.35, -0.01, 0.034), (0.57, 0.12, 0.075), (0.65, 0.5, 0.118), (0.57, 0.88, 0.075), (0.35, 1.01, 0.034), (0.13, 0.88, 0.075), (0.05, 0.5, 0.118), (0.13, 0.12, 0.075), (0.35, -0.01, 0.034), smooth=True),
      S((0.38, 0.72, 0.02), (0.55, 1.05, 0.05), (0.66, 1.22, 0.034), (0.76, 1.42, 0), smooth=True))
glyph("R", 0.70,
      blade(0.08, 0.0, 1.0),
      S((0.08, 0.02, 0.026), (0.4, 0.0, 0.03), (0.56, 0.14, 0.085), (0.5, 0.33, 0.06), (0.34, 0.49, 0.03), (0.08, 0.51, 0.026), smooth=True),
      diag(0.26, 0.5, 0.68, 1.0, 0.1), tail(0.08, 1.07, -0.03, 0.3), tail(0.68, 1.0, 0.04, 0.32, 0.02))
glyph("S", 0.58,
      S((0.54, 0.09, 0), (0.4, -0.01, 0.034), (0.18, 0.07, 0.07), (0.11, 0.26, 0.085), (0.3, 0.44, 0.05), (0.5, 0.6, 0.07), (0.53, 0.82, 0.085), (0.36, 0.99, 0.034), (0.1, 1.0, 0.034), (0.04, 0.92, 0), smooth=True),
      tail(0.54, 0.09, 0.03, -0.16, 0.018))
glyph("T", 0.74,
      hair(0.0, 0.01, 0.74, 0.0, 0.05), blade(0.37, 0.0, 1.0, 0.11),
      tail(0.37, 1.07, 0.02, 0.5, 0.024))
glyph("U", 0.72,
      S((0.09, -0.07, 0), (0.09, 0.06, 0.105), (0.09, 0.7, 0.11), (0.2, 0.93, 0.075), (0.38, 1.01, 0.034), (0.54, 0.93, 0.045), (0.62, 0.74, 0.04), smooth=True),
      hair(0.64, -0.02, 0.64, 0.98, 0.026), tail(0.64, 0.98, 0.03, 0.4, 0.018))
glyph("V", 0.74,
      diag(0.0, 0.0, 0.37, 1.02, 0.115), hair(0.74, 0.0, 0.37, 1.02, 0.03),
      tail(0.37, 1.02, 0.0, 0.5, 0.024))
glyph("W", 1.12,
      diag(0.0, 0.0, 0.27, 1.02, 0.1), hair(0.54, 0.0, 0.27, 1.02, 0.028), diag(0.54, 0.0, 0.81, 1.02, 0.1), hair(1.1, 0.0, 0.81, 1.02, 0.028),
      tail(0.27, 1.02, -0.03, 0.34, 0.02), tail(0.81, 1.02, 0.03, 0.46, 0.022))
glyph("X", 0.72,
      diag(0.0, 0.0, 0.72, 1.02, 0.11), hair(0.72, 0.0, 0.0, 1.02, 0.03),
      tail(0.0, 1.02, -0.04, 0.3, 0.02), tail(0.72, 1.02, 0.05, 0.4, 0.02))
glyph("Y", 0.72,
      diag(0.0, 0.0, 0.36, 0.52, 0.11), hair(0.72, 0.0, 0.36, 0.52, 0.03), blade(0.36, 0.5, 1.0, 0.1),
      tail(0.36, 1.07, 0.0, 0.52, 0.024))
glyph("Z", 0.64,
      hair(0.0, 0.01, 0.62, 0.0, 0.045), diag(0.6, 0.03, 0.04, 0.97, 0.1), hair(0.0, 0.99, 0.66, 1.0, 0.05),
      tail(0.66, 1.0, 0.06, 0.22, 0.018))
glyph(".", 0.14, S((0.07, 0.9, 0), (0.07, 0.94, 0.08), (0.07, 1.0, 0.1), (0.07, 1.08, 0), smooth=False))
glyph(",", 0.14, S((0.08, 0.92, 0.09), (0.07, 1.04, 0.07), (0.01, 1.2, 0.0), smooth=True))
glyph("-", 0.34, hair(0.0, 0.52, 0.34, 0.52, 0.05))
glyph("'", 0.12, S((0.06, -0.06, 0.07), (0.05, 0.1, 0.05), (0.01, 0.26, 0), smooth=True))
glyph("!", 0.14, blade(0.07, 0.0, 0.7, 0.09), S((0.07, 0.9, 0), (0.07, 0.95, 0.08), (0.07, 1.0, 0.09), (0.07, 1.08, 0)))
glyph("?", 0.50,
      S((0.04, 0.2, 0), (0.12, 0.04, 0.05), (0.3, -0.01, 0.045), (0.46, 0.13, 0.075), (0.4, 0.34, 0.07), (0.25, 0.5, 0.05), (0.25, 0.66, 0.06), smooth=True),
      S((0.25, 0.9, 0), (0.25, 0.95, 0.08), (0.25, 1.0, 0.09), (0.25, 1.08, 0)))
UMLAUT = {"Ä": "A", "Ö": "O", "Ü": "U"}


def dots(base_w):
    """Two diamond dots above a letter."""
    y = -0.2
    out = []
    for x in (base_w * 0.28, base_w * 0.72):
        out.append(S((x, y - 0.07, 0), (x, y, 0.07), (x, y + 0.07, 0)))
    return out


for k, base in UMLAUT.items():
    GLYPHS[k] = {"w": GLYPHS[base]["w"], "strokes": GLYPHS[base]["strokes"] + dots(GLYPHS[base]["w"])}


# ---------------------------------------------------------------------------------------------------- rendering
def edt(mask):
    """Exact euclidean distance of every True pixel to the nearest False pixel (small images: brute force over a window)."""
    h, w = mask.shape
    r = int(SDF_RANGE) + 1
    pad = np.pad(mask, r, constant_values=True)  # the border of the tile is not an edge
    best = np.full((h, w), float(r + 1), dtype=np.float32)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.hypot(dx, dy)
            if d > r or d == 0:
                continue
            shifted = pad[r + dy:r + dy + h, r + dx:r + dx + w]
            best = np.where(~shifted & (d < best), d, best)
    return np.where(mask, best, 0.0)


def render_glyph(ch, cap, weight=1.0):
    spec = GLYPHS[ch]
    ww = int(math.ceil((spec["w"] + SIDE_PAD * 2) * cap))
    hh = int(math.ceil((1 + TOP_PAD + BOTTOM_PAD) * cap))
    ox = SIDE_PAD * cap
    oy = TOP_PAD * cap
    big = Image.new("L", (ww * SS, hh * SS), 0)
    d = ImageDraw.Draw(big)
    spine = Image.new("L", (ww, hh), 0)
    sd = ImageDraw.Draw(spine)
    min_w = 1.4 / cap
    for st in spec["strokes"]:
        pts = catmull(st["pts"]) if st["smooth"] else catmull(st["pts"], 18) if len(st["pts"]) > 2 else catmull(st["pts"], 24)
        # sweep: a disc at every dense point
        for (x, y, w) in pts:
            w = max((FAT + w * GROW) * weight if w > 0.001 else FAT * 0.6 * weight, min_w)
            cx, cy = (ox + x * cap) * SS, (oy + y * cap) * SS
            r = w * cap * SS / 2
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        # the spine: where the stroke is thick enough to hold light
        line = [((ox + x * cap), (oy + y * cap)) for (x, y, w) in pts if (FAT + w * GROW) * weight * cap >= 4.6]
        if len(line) >= 2:
            sd.line(line, fill=255, width=1)
    big = big.filter(ImageFilter.GaussianBlur(BLUR * cap * SS))  # the goo: everything swells towards what is near it
    small = big.resize((ww, hh), Image.LANCZOS)
    mask = np.array(small) > int(255 * CUT)
    spine_a = (np.array(spine) > 100) & mask
    inside = edt(mask)
    outside = edt(~mask)
    signed = np.where(mask, inside - 0.5, -(outside - 0.5))
    g = np.clip(128 + signed / SDF_RANGE * 127, 0, 255).astype(np.uint8)
    rgba = np.zeros((hh, ww, 4), dtype=np.uint8)
    rgba[..., 0] = mask * 255
    rgba[..., 1] = g
    rgba[..., 2] = spine_a * 255
    rgba[..., 3] = 255
    return Image.fromarray(rgba, "RGBA"), ww, hh


def build():
    meta = {"sdf_range": SDF_RANGE, "faces": {}}
    for name, cap in SIZES.items():
        order = list(GLYPHS.keys())
        images = {}
        total_w = 0
        height = 0
        for ch in order:
            im, w, h = render_glyph(ch, cap, SIZE_WEIGHT[name])
            images[ch] = (im, w, h)
            total_w += w + 2
            height = h
        atlas = Image.new("RGBA", (total_w, height), (0, 0, 0, 255))
        x = 0
        glyphs = {}
        for ch in order:
            im, w, h = images[ch]
            atlas.paste(im, (x, 0))
            glyphs[ch] = {"x": x, "w": w, "adv": int(round(GLYPHS[ch]["w"] * cap + GAP * cap)), "lead": int(round(SIDE_PAD * cap))}
            x += w + 2
        path = ROOT / "assets" / "ui" / f"void_face_{name}.png"
        atlas.save(path)
        meta["faces"][name] = {
            "cap": cap, "height": height, "baseline": int(round((TOP_PAD + 1.0) * cap)), "top": int(round(TOP_PAD * cap)),
            "space": int(round(SPACE * cap)), "image": f"res://assets/ui/void_face_{name}.png", "glyphs": glyphs,
            "accents": UMLAUT,
        }
    (ROOT / "data" / "void_face.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return meta


def preview(meta, path):
    """A crude look at the letterforms (white on dark); the real look is the shader's."""
    face = meta["faces"]["big"]
    atlas = Image.open(ROOT / "assets" / "ui" / "void_face_big.png")
    arr = np.array(atlas)
    lines = ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "MORNATH", "DER HIMMELSSPALTER"]
    scale = 2
    img = Image.new("RGB", (1400, 140 * 4 * scale // 2 + 40), (14, 9, 26))
    px = np.array(img)
    y = 10
    for line in lines:
        x = 20
        for ch in line:
            if ch == " ":
                x += face["space"]
                continue
            g = face["glyphs"][ch]
            tile = arr[:, g["x"]:g["x"] + g["w"], :]
            for yy in range(tile.shape[0]):
                for xx in range(tile.shape[1]):
                    if tile[yy, xx, 0] > 0:
                        v = 255 if tile[yy, xx, 2] == 0 else 0
                        col = (225, 215, 255) if v else (255, 90, 220)
                        px[y + yy, x + xx] = col
            x += g["adv"]
        y += face["height"] + 8
    Image.fromarray(px[: y + 10]).save(path)


if __name__ == "__main__":
    meta = build()
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs" / "img" / "void_face.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    preview(meta, out)
    print("wrote atlases, data/void_face.json and", out)
