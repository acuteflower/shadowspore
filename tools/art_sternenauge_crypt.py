"""DAS STERNENAUGE - die Krypta unter Caelias Statue (Innenraum `sternenauge_krypta`).

Quelle: tools/art_sources/sternenauge/flow_crypt.webp (Flow-Bild P5, 1344x756, feines Pseudoraster ~1,5 px).
Abtastung 2:1 (Flächenmittel + Nachschärfen), 1 Pixel = 1 Weltpixel: Raum 672x378, der Treppenbogen ist ~47 px hoch,
Ellie (44 px) passt hindurch. Gemeinsame Palette (64 Farben), dunkler Rand um das Oval wird transparent
(dort liegt der Schatten-Hintergrund der Innenräume).

Ausgabe (assets/interior/sternenauge_krypta/):
  crypt.png        der ganze Raum (Boden, Wände, Relief, Treppe, Schacht), z -6
  front.png        die vordere Randmauer unter der Bodenellipse (über Ellie, wenn sie davor steht)
  crypt_glow.png   Unlit: Lichtschacht aus dem Okulus, Lichtsee, Magenta-Adern der Leerenkristalle, Türkis-Fries schwach
  front_glow.png   (leer gelassen, Interior erwartet ihn nicht zwingend)
  none.png         1x1 transparent (die Treppe hat kein Türblatt)
Raumlayout & Kollision stehen in data/interiors.json -> "sternenauge_krypta" (hier nur Konstanten zum Abgleich).

Aufruf: py -3 tools/art_sternenauge_crypt.py
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "art_sources" / "sternenauge" / "flow_crypt.webp"
OUT = ROOT / "assets" / "interior" / "sternenauge_krypta"

W, H = 672, 378
COLORS = 64
# Bodenellipse (Raum-px): begehbar; darunter beginnt die vordere Randmauer
FLOOR_C = (338.0, 256.0)
FLOOR_R = (270.0, 92.0)
FRONT_R = (286.0, 104.0)      # etwas größer: alles außerhalb davon (unten) ist Vordermauer
FRONT_Y = 300                 # oberste Zeile des front.png-Ausschnitts


def _scaled() -> np.ndarray:
    im = Image.open(SRC).convert("RGB")
    s = im.resize((W, H), Image.BOX).filter(ImageFilter.UnsharpMask(1.0, 60, 2))
    q = s.quantize(COLORS, method=Image.Quantize.FASTOCTREE).convert("RGB")
    return np.array(q).astype(np.int32)


def _outside_mask(px: np.ndarray) -> np.ndarray:
    """Flutfüllung vom Bildrand über den dunklen, fast unbunten Hintergrund (#10121c-artig)."""
    lum = px.mean(axis=-1)
    sat = px.max(axis=-1) - px.min(axis=-1)
    dark = (lum < 40) & (sat < 26)
    out = np.zeros((H, W), dtype=bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(W):
        for y in (0, H - 1):
            if dark[y, x]:
                q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if dark[y, x]:
                q.append((y, x))
    while q:
        y, x = q.popleft()
        if out[y, x] or not dark[y, x]:
            continue
        out[y, x] = True
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < H and 0 <= nx < W and not out[ny, nx] and dark[ny, nx]:
                q.append((ny, nx))
    # Öffnung (Erosion, dann Dilatation): schmale Zungen in die Fugen der äußeren Randsteine fallen weg
    return _dilate(_erode(out, 3), 3)


def _shift(m: np.ndarray, dy: int, dx: int) -> np.ndarray:
    o = np.zeros_like(m)
    ys = slice(max(dy, 0), H + min(dy, 0))
    yd = slice(max(-dy, 0), H + min(-dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0))
    xd = slice(max(-dx, 0), W + min(-dx, 0))
    o[ys, xs] = m[yd, xd]
    return o


def _dilate(m: np.ndarray, r: int) -> np.ndarray:
    o = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx <= r * r:
                o |= _shift(m, dy, dx)
    return o


def _erode(m: np.ndarray, r: int) -> np.ndarray:
    return ~_dilate(~m, r)


def _glow(px: np.ndarray, keep: np.ndarray) -> np.ndarray:
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    lum = px.mean(axis=-1)
    glow = np.zeros((H, W, 4), dtype=np.float64)
    ys, xs = np.mgrid[0:H, 0:W]
    # Lichtschacht aus dem Okulus + Lichtsee auf dem Boden (helle, kühle Pixel im Mittelbereich)
    beam = keep & (b > r + 12) & (lum > 150) & (xs > 250) & (xs < 430)
    glow[beam, :3] = px[beam]
    glow[beam, 3] = np.clip((lum[beam] - 150) * 2.2, 60, 200)
    # Magenta-Adern / Augen der Leerenkristalle
    mag = keep & (r > 150) & (b > 110) & (g < 110) & (r > g + 60)
    glow[mag, :3] = (0xff, 0x6a, 0xe0)
    glow[mag, 3] = 255
    # Türkis-Fries: ganz schwach (nachts lesbar)
    teal = keep & (g > r + 25) & (b > r + 15) & (lum > 70) & (lum < 150) & ~beam
    glow[teal, :3] = (0x4f, 0xb8, 0xb0)
    glow[teal, 3] = 46
    return glow


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    px = _scaled()
    outside = _outside_mask(px)
    keep = ~outside
    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(px, 0, 255)
    rgba[..., 3] = np.where(keep, 255, 0)

    # Vordermauer: unterhalb der vergrößerten Bodenellipse
    ys, xs = np.mgrid[0:H, 0:W]
    e = ((xs - FLOOR_C[0]) / FRONT_R[0]) ** 2 + ((ys - FLOOR_C[1]) / FRONT_R[1]) ** 2
    front = keep & (e > 1.0) & (ys > FLOOR_C[1]) & (ys >= FRONT_Y)
    front_img = np.zeros((H - FRONT_Y, W, 4), dtype=np.uint8)
    front_img[...] = np.where(front[FRONT_Y:, :, None], rgba[FRONT_Y:], 0)

    Image.fromarray(rgba, "RGBA").save(OUT / "crypt.png")
    Image.fromarray(front_img, "RGBA").save(OUT / "front.png")
    g = _glow(px, keep)
    Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGBA").save(OUT / "crypt_glow.png")
    Image.fromarray(np.zeros((1, 1, 4), dtype=np.uint8), "RGBA").save(OUT / "none.png")
    print("crypt", W, H, "front rows", H - FRONT_Y, "opaque", int(keep.sum()))


if __name__ == "__main__":
    main()
