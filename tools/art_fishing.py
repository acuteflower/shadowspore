#!/usr/bin/env python3
"""Angeln: Fischbilder, Schatten, Posen. Needs numpy. Same palette family as the rest of the game
(ink 1b1a2e, light from the top left, 4-5 tones per material, glow only in the _glow sheets).
  assets/items/fish_<x>.png              16x16 icons (check_icon: one piece, 1 px margin)
  assets/fishing/fish_side.png           48x24 side view, one row per species (the catch card, the book)
  assets/fishing/fish_side_glow.png      only the glowing pixels (drawn unlit)
  assets/fishing/fish_shadow.png         under water, seen from above: per species 16 headings x 2 swish frames, 32x32
  assets/fishing/bobbers.png / _glow     3 floats (cork, glimmer, obsidian) x 4 frames, 12x12, waterline at (6, 8)
Preview: python3 tools/art_fishing.py preview out.png"""
import math
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_art import CLEAR, ROOT, hexc, write_png  # noqa: E402

INK = hexc("1b1a2e")
ORDER = ["silverling", "copper_loach", "moon_trout", "gold_carp", "glimmer_loach", "veil_eel", "abyss_pike"]
ITEM = {"silverling": "fish_silverling", "copper_loach": "fish_loach", "moon_trout": "fish_trout", "gold_carp": "fish_carp",
        "glimmer_loach": "fish_glimmer", "veil_eel": "fish_eel", "abyss_pike": "fish_pike"}
HEADINGS = 16
SHADOW_CELL = 32

# ramp dark .. light; len = body length share of the picture, th = thickness share, tail = (length share, height share)
SP = {
    "silverling": dict(ramp="2b3550 46587a 7f95b4 bccbe0 eef4fb", len=0.92, th=0.30, tail=(0.2, 0.42), dorsal=(0.5, 0.16, 0.2), pat="stripe", acc="3cc0c6", eye="fff0b0", glow=False, size=14),
    "copper_loach": dict(ramp="3a2218 6b4028 a2653a d28f5a f0c08a", len=0.94, th=0.27, tail=(0.14, 0.3), dorsal=(0.45, 0.1, 0.3), pat="spots", acc="2a1810", eye="fff0b0", glow=False, size=18, barbels=True),
    "moon_trout": dict(ramp="34305a 585088 8c86b8 c4bfdf eeeaf8", len=0.9, th=0.32, tail=(0.18, 0.4), dorsal=(0.48, 0.16, 0.18), pat="spots", acc="6636ad", eye="fff0b0", glow=False, size=24),
    "gold_carp": dict(ramp="5a3a1c 8a5a24 c48a38 e6c468 fff0b0", len=0.86, th=0.46, tail=(0.22, 0.46), dorsal=(0.3, 0.2, 0.4), pat="scales", acc="b48a38", eye="1b1a2e", glow=False, size=30),
    "glimmer_loach": dict(ramp="1f3f4c 2a8c94 3cc0c6 78f4e6 d0fff8", len=0.9, th=0.26, tail=(0.2, 0.38), dorsal=(0.5, 0.12, 0.2), pat="glow", acc="d0fff8", eye="ffffff", glow=True, size=12),
    "veil_eel": dict(ramp="14101e 241b36 382b52 54437a 7d6aa6", len=0.94, th=0.15, tail=(0.06, 0.12), dorsal=(0.1, 0.1, 0.8), pat="vein", acc="9b5cff", eye="ff4fd8", glow=True, size=60, wave=0.07),
    "abyss_pike": dict(ramp="1a1030 2c1f55 3e3380 5a4fb0 8a7fe0", len=0.92, th=0.24, tail=(0.16, 0.4), dorsal=(0.78, 0.2, 0.15), pat="bars", acc="0e0919", eye="ff4fd8", glow=True, size=70, spiky=True),
}
for _s in SP.values():
    _s["ramp"] = [hexc(c) for c in _s["ramp"].split()]
    _s["acc"] = hexc(_s["acc"])
    _s["eye"] = hexc(_s["eye"])


def h01(x, y, s):
    n = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    return ((n ^ (n >> 16)) & 0xFF) / 255.0


def profile(u):
    """Thickness 0..1 along the body (u: 0 tail root .. 1 snout)."""
    if u < 0.55:
        return 0.24 + 0.76 * math.sqrt(max(0.0, 1.0 - ((0.55 - u) / 0.55) ** 2))
    return math.sqrt(max(0.0, 1.0 - ((u - 0.55) / 0.45) ** 2))


def render_side(key, W, H, seed=1):
    """-> (pixels, glow pixels) of a fish pointing right, drawn straight into the pixel grid."""
    s = SP[key]
    ramp = s["ramp"]
    m = 2 if W <= 16 else 1
    total = W - 2 * m
    tail_len = total * s["tail"][0]
    body_len = total * s["len"] - tail_len * 0.0
    x0 = m + tail_len
    x1 = min(W - m - 1, x0 + (total - tail_len))
    th = H * s["th"] * (2.0 if H > 16 else 1.3) if key != "veil_eel" else H * 0.3
    th = min(th, H - 4)
    yc0 = (H - 1) / 2.0
    wave = s.get("wave", 0.0) * H
    img, glow = {}, {}
    cols = {}

    def yc(x):
        u = (x - x0) / max(x1 - x0, 1)
        return yc0 + (math.sin(u * math.pi * 2.4 + 0.6) * wave if wave else 0.0)

    body = set()
    for x in range(int(x0 - tail_len) - 1, int(x1) + 1):
        xf = x + 0.5
        if xf < x0:  # tail
            v = (x0 - xf) / max(tail_len, 0.01)
            if v > 1.0:
                continue
            root = th * 0.24 / 2
            half = root + (s["tail"][1] * H * (1.0 if H > 16 else 0.7) / 2 - root) * v
            notch = 0.0 if key in ("veil_eel", "copper_loach") else max(0.0, (v - 0.55)) * half * 1.4
            for y in range(H):
                d = abs(y + 0.5 - yc(x0))
                if notch < d <= half:
                    img[(x, y)] = ramp[1] if d > half - 1.0 else ramp[2]
                    cols[(x, y)] = "tail"
        elif xf <= x1:
            u = (xf - x0) / (x1 - x0)
            half = th / 2 * profile(u)
            c = yc(xf)
            top, bot = c - half, c + half
            for y in range(H):
                if top <= y + 0.5 <= bot and half > 0.4:
                    body.add((x, y))
                    t = (y + 0.5 - top) / max(bot - top, 1e-6)
                    idx = int(round((1.0 - t) * (len(ramp) - 1) * 0.9 + 0.2))
                    if t > 0.78:
                        idx = min(len(ramp) - 1, idx + 1)  # pale belly
                    img[(x, y)] = ramp[max(0, min(len(ramp) - 1, idx))]
                    cols[(x, y)] = "body"
    # dorsal fin on top of the body
    dpos, dh, dl = s["dorsal"]
    for x in range(int(x0), int(x1)):
        u = (x + 0.5 - x0) / (x1 - x0)
        if dpos <= u <= dpos + dl:
            k = (u - dpos) / dl
            fh = dh * H * (1.0 - k * (0.8 if not s.get("spiky") else 0.2)) * (1.0 + (0.5 if s.get("spiky") and int(k * 7) % 2 == 0 else 0.0))
            col_top = min((y for y in range(H) if (x, y) in body), default=None)
            if col_top is None:
                continue
            for y in range(int(col_top - fh), col_top):
                if y >= (2 if H <= 16 else 1):
                    img[(x, y)] = ramp[1] if y < col_top - 1 else ramp[2]
    # pectoral fin
    px = int(x0 + (x1 - x0) * 0.68)
    py = int(yc(px) + th * 0.18)
    for i in range(3):
        if 0 <= py + i < H:
            img[(px - i, py + i)] = ramp[2]
    # patterns
    for (x, y), kind in list(cols.items()):
        if kind != "body":
            continue
        u = (x + 0.5 - x0) / (x1 - x0)
        c = yc(x + 0.5)
        t = (y + 0.5 - (c - th / 2 * profile(u))) / max(th * profile(u), 1e-6)
        p = s["pat"]
        if p == "stripe" and abs(t - 0.5) < 0.09 and 0.12 < u < 0.86:
            img[(x, y)] = s["acc"]
        elif p == "spots" and 0.1 < u < 0.85 and 0.12 < t < 0.65 and h01(x, y, seed) > 0.8:
            img[(x, y)] = s["acc"]
        elif p == "scales" and 0.2 < u < 0.85 and t < 0.8 and (x + y) % 3 == 0 and (x // 2 + y) % 2 == 0:
            img[(x, y)] = s["acc"]
        elif p == "glow" and abs(t - 0.5) < 0.1 and 0.15 < u < 0.8:
            img[(x, y)] = s["acc"]
            glow[(x, y)] = s["acc"]
        elif p == "vein" and t < 0.2 and 0.1 < u < 0.9 and (x % 3 != 1):
            img[(x, y)] = hexc("8a4dff")
            glow[(x, y)] = hexc("9b5cff")
        elif p == "bars" and 0.2 < u < 0.8 and int((u - 0.2) * 9) % 2 == 0 and t < 0.75:
            img[(x, y)] = s["acc"]
    # eye
    ex = int(x1 - (x1 - x0) * 0.14)
    ey = int(yc(ex) - th * 0.12)
    img[(ex, ey)] = s["eye"]
    if s["glow"] and key in ("abyss_pike", "veil_eel"):
        glow[(ex, ey)] = s["eye"]
    if s.get("barbels") and W > 16:
        sx, sy = int(x1), int(yc(x1) + 1)
        img[(sx, sy)] = ramp[3]
        img[(sx + 1, sy + 1)] = ramp[3] if sx + 1 < W else CLEAR
    # outline
    out = dict(img)
    for (x, y) in img:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in img and 0 <= q[0] < W and 0 <= q[1] < H:
                out[q] = INK
    return out, glow


def to_rows(img, w, h):
    return [[img.get((x, y), CLEAR) for x in range(w)] for y in range(h)]


def shadow(key, angle, phase, cell=SHADOW_CELL):
    """The dark shape under the surface, seen from above: a swishing capsule with a tail fin."""
    s = SP[key]
    length = min(cell * 0.9, 8 + s["size"] * 0.5)
    width = max(2.4, length * (0.3 if key != "veil_eel" else 0.1))
    d = np.array([math.cos(angle), math.sin(angle) * 0.62])  # 3/4 view squashes the vertical
    d = d / max(np.linalg.norm(d), 1e-6)
    perp = np.array([-d[1], d[0]])
    centre = np.array([cell / 2.0, cell / 2.0])
    pts, ws = [], []
    n = 12
    for i in range(n):
        k = i / (n - 1)  # 0 head .. 1 tail root
        along = (0.5 - k) * length * 0.86
        sway = math.sin(phase * math.pi * 2 + k * 3.2) * k * width * 0.55
        pts.append(centre + d * along + perp * sway)
        if k < 0.3:
            w = 0.5 + 0.5 * math.sqrt(max(0.0, 1.0 - ((0.3 - k) / 0.3) ** 2))
        else:
            w = 0.12 + 0.88 * (1.0 - (k - 0.3) / 0.7) ** 1.2
        ws.append(width * w)
    tail_dir = pts[-1] - pts[-2]
    tail_dir = tail_dir / max(np.linalg.norm(tail_dir), 1e-6)
    pts.append(pts[-1] + tail_dir * length * 0.07)
    ws.append(width * 0.5)
    pts.append(pts[-1] + tail_dir * length * 0.07)
    ws.append(width * 0.3)
    img = {}
    for y in range(cell):
        for x in range(cell):
            best = 9e9
            for i in range(len(pts) - 1):
                a, b = pts[i], pts[i + 1]
                ab = b - a
                t = max(0.0, min(1.0, np.dot(np.array([x + 0.5, y + 0.5]) - a, ab) / max(np.dot(ab, ab), 1e-9)))
                dist = np.linalg.norm(np.array([x + 0.5, y + 0.5]) - (a + ab * t)) - (ws[i] + (ws[i + 1] - ws[i]) * t) / 2
                best = min(best, dist)
            if best <= 0:
                img[(x, y)] = hexc("0b1a26")
    return img


def bobber(kind, frame):
    """12x12, waterline at row 8. frames: 0 rest, 1 up, 2 tilt left, 3 tilt right."""
    ramps = {"cork": ("5c2a3a", "8a3a4a", "c4586a", "ffd0b0"), "glimmer": ("2a8c94", "3cc0c6", "78f4e6", "d0fff8"), "obsidian": ("07040d", "1a1030", "34185e", "6636ad")}
    r = [hexc(c) for c in ramps[kind]]
    dy = -1 if frame == 1 else 0
    tilt = {2: -1, 3: 1}.get(frame, 0)
    img, glow = {}, {}
    for y in range(3, 9):
        k = (y - 3) / 5.0
        half = 2.4 * math.sin(math.pi * (0.25 + 0.55 * k))
        for x in range(12):
            xc = 5.5 + tilt * (8 - y) * 0.25
            if abs(x + 0.5 - xc) <= half:
                t = (x + 0.5 - (xc - half)) / max(2 * half, 1e-6)
                top = y - 3 < 2
                idx = 3 if (t < 0.3 and top) else (2 if t < 0.45 else (1 if t < 0.8 else 0))
                if kind == "cork" and 4 <= y <= 5:
                    idx = 3 if t < 0.5 else 2
                    img[(x, y + dy)] = hexc("e9e3f7") if t < 0.5 else hexc("bdb3e4")
                    continue
                img[(x, y + dy)] = r[idx]
                if kind == "glimmer" and y <= 5:
                    glow[(x, y + dy)] = r[idx]
    img[(5, 2 + dy)] = hexc("e6c468") if kind != "obsidian" else r[2]  # the line eye
    out = dict(img)
    for (x, y) in img:
        for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ddx, y + ddy)
            if q not in img and 0 <= q[0] < 12 and 0 <= q[1] < 12:
                out[q] = INK
    return out, glow


def sheet(cells, cw, ch, cols):
    rows = (len(cells) + cols - 1) // cols
    px = [[CLEAR] * (cw * cols) for _ in range(ch * rows)]
    for i, img in enumerate(cells):
        ox, oy = (i % cols) * cw, (i // cols) * ch
        for (x, y), c in img.items():
            if 0 <= x < cw and 0 <= y < ch:
                px[oy + y][ox + x] = c
    return px, cw * cols, ch * rows


def icon_ok(img):
    xs = [x for x, _ in img]
    ys = [y for _, y in img]
    if not xs or min(xs) < 1 or min(ys) < 1 or max(xs) > 14 or max(ys) > 14:
        return False
    seen, todo = set(), [next(iter(img))]
    while todo:
        p = todo.pop()
        if p in seen or p not in img:
            continue
        seen.add(p)
        todo += [(p[0] + 1, p[1]), (p[0] - 1, p[1]), (p[0], p[1] + 1), (p[0], p[1] - 1)]
    return len(seen) == len(img)


def build():
    items = ROOT / "items"
    out = ROOT / "fishing"
    side, side_glow = [], []
    for key in ORDER:
        img, glow = render_side(key, 48, 24)
        side.append(img)
        side_glow.append(glow)
        small, _ = render_side(key, 16, 16)
        if not icon_ok(small):
            print("icon problem:", key)
        write_png(items / f"{ITEM[key]}.png", 16, 16, to_rows(small, 16, 16))
    px, w, h = sheet(side, 48, 24, 1)
    write_png(out / "fish_side.png", w, h, px)
    px, w, h = sheet(side_glow, 48, 24, 1)
    write_png(out / "fish_side_glow.png", w, h, px)
    cells = []
    for key in ORDER:
        for a in range(HEADINGS):
            for f in range(2):
                cells.append(shadow(key, a / HEADINGS * math.tau, f / 2.0))
    px, w, h = sheet(cells, SHADOW_CELL, SHADOW_CELL, HEADINGS * 2)
    write_png(out / "fish_shadow.png", w, h, px)
    cells, glows = [], []
    for kind in ("cork", "glimmer", "obsidian"):
        for f in range(4):
            i, g = bobber(kind, f)
            cells.append(i)
            glows.append(g)
    px, w, h = sheet(cells, 12, 12, 4)
    write_png(out / "bobbers.png", w, h, px)
    px, w, h = sheet(glows, 12, 12, 4)
    write_png(out / "bobbers_glow.png", w, h, px)
    print("written:", len(ORDER), "species")


def preview(path):
    scale = 8
    items = []
    for key in ORDER:
        img, _ = render_side(key, 48, 24)
        small, _ = render_side(key, 16, 16)
        items.append((img, small))
    W, H = 48 * scale + 16 * scale + 40, (24 * scale + 12) * len(ORDER)
    px = np.zeros((H, W, 4), np.uint8)
    px[:, :] = (40, 70, 66, 255)
    for i, (img, small) in enumerate(items):
        oy = i * (24 * scale + 12) + 6
        for (x, y), c in img.items():
            px[oy + y * scale: oy + (y + 1) * scale, 8 + x * scale: 8 + (x + 1) * scale] = c
        for (x, y), c in small.items():
            px[oy + y * scale: oy + (y + 1) * scale, 8 + 48 * scale + 24 + x * scale: 8 + 48 * scale + 24 + (x + 1) * scale] = c
    write_png(pathlib.Path(path), W, H, [[tuple(int(v) for v in px[y, x]) for x in range(W)] for y in range(H)])


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "preview":
        preview(sys.argv[2])
    else:
        build()
