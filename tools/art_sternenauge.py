"""DAS STERNENAUGE - Caelias kniende Leuchtturm-Statue am Windkap (Story-Startkonstrukt).

Deterministische Umarbeitung der Google-Flow-Vorlagen aus `tools/art_sources/sternenauge/`
(`flow_wild.webp`, `flow_awake.webp`, deckungsgleich generiert) in Spiel-Pixel-Art:

1. Gemeinsamer Ausschnitt beider Zustände, Abtastung im Raster `PITCH` (Vorlage ~4 px/Pixel;
   kleiner = größere Statue) an den Zellmitten der entrauschten Vorlage -> harte Pixel.
2. Freistellung: Hintergrund per Randflutung, Lücken in den fast schwarzen Leerenkristallen
   werden über eine morphologische Schließung + Lochfüllung gerettet.
3. Farbangleich: Stein wird nach Helligkeit auf die Kalkstein-Rampe von `rocky_ground.gdshader`
   abgebildet (passt zum Felsplateau des Windkaps), Gold wärmer,
   Leerenkristalle Richtung `07040d`-`221740`, dann gemeinsame Palette (beide Zustände).
4. Leuchtebene (Unlit) je Zustand: wild = magenta/violette Leerenadern + schwache Türkis-Einlagen,
   erwacht = Linse, Augen, Einlagen, Halo-Türkis, warme Fenster, saubere Kristalle.

Ausgabe:
  assets/props/sternenauge/sternenauge.png        2 Frames nebeneinander: wild | erwacht
  assets/props/sternenauge/sternenauge_glow.png   gleiche Anordnung, nur Leuchtpixel
  data/sternenauge_art.json                        Framegröße, Fußpunkt, Linse, Kollision ...

Aufruf: py -3 tools/art_sternenauge.py   (danach Godot --headless --import)
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "art_sources" / "sternenauge"
OUT_DIR = ROOT / "assets" / "props" / "sternenauge"
OUT_JSON = ROOT / "data" / "sternenauge_art.json"

CROP = (128, 32, 736, 1124)  # gemeinsamer Ausschnitt in den 864x1152-Vorlagen
PITCH = 2.875                # Quellpixel je Spielpixel (Vorlage hat ~4; 2.875 -> ~380 px hoch)
SRC_PITCH = 4.0              # echtes Pseudoraster der Vorlage (für flächenbezogene Schwellen)
BG = np.array([25.0, 22.5, 37.5])
COLORS = 72                  # gemeinsame Palette beider Zustände


def _load(name: str) -> np.ndarray:
    im = Image.open(SRC / f"flow_{name}.webp").convert("RGB").crop(CROP)
    im = im.filter(ImageFilter.MedianFilter(3))
    return np.asarray(im).astype(np.float64)


def _out_size(a: np.ndarray) -> tuple[int, int]:
    return int(a.shape[0] // PITCH), int(a.shape[1] // PITCH)


def _cell_median(a: np.ndarray) -> np.ndarray:
    """Flächenmittel je Spielpixel-Zelle + leichtes Nachschärfen: jedes Ausgabepixel ist genau
    ein Weltpixel (keine ungleich breiten Doppelpixel wie beim Punktabtasten im ~4-px-Raster)."""
    h, w = _out_size(a)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize((w, h), Image.BOX)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=70, threshold=2))
    return np.asarray(im).astype(np.float64)


def _cell_mean(a: np.ndarray) -> np.ndarray:
    """Flächenanteil je Spielpixel-Zelle (für Masken)."""
    h, w = _out_size(a)
    im = Image.fromarray((a * 255.0).astype(np.uint8))
    return np.asarray(im.resize((w, h), Image.BOX)).astype(np.float64) / 255.0


def _shift(m: np.ndarray, dy: int, dx: int) -> np.ndarray:
    out = np.zeros_like(m)
    h, w = m.shape
    ys = slice(max(dy, 0), h + min(dy, 0))
    yd = slice(max(-dy, 0), h + min(-dy, 0))
    xs = slice(max(dx, 0), w + min(dx, 0))
    xd = slice(max(-dx, 0), w + min(-dx, 0))
    out[ys, xs] = m[yd, xd]
    return out


def _dilate(m: np.ndarray, r: int) -> np.ndarray:
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= _shift(m, dy, dx)
    return out


def _erode(m: np.ndarray, r: int) -> np.ndarray:
    return ~_dilate(~m, r)


MAX_HOLE = int(60 * (SRC_PITCH / PITCH) ** 2)  # größere eingeschlossene Flächen (z. B. Raum im Heiligenschein) bleiben frei


def _fill_holes(m: np.ndarray) -> np.ndarray:
    """Kleine eingeschlossene Hintergrundinseln (Fenster, Tür, Kristallfacetten) werden Vordergrund."""
    h, w = m.shape
    seen = m.copy()
    out = m.copy()
    for sy in range(h):
        for sx in range(w):
            if seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            comp: list[tuple[int, int]] = []
            touches_edge = False
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                if y == 0 or x == 0 or y == h - 1 or x == w - 1:
                    touches_edge = True
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            cy = sum(p[0] for p in comp) / len(comp)
            in_base = cy > h * 0.8  # Kryptatür im Sockel ist größer, bleibt aber dunkel und deckend
            if not touches_edge and (len(comp) <= MAX_HOLE or in_base):
                for y, x in comp:
                    out[y, x] = True
    return out


def _mask(src: np.ndarray) -> np.ndarray:
    dist = np.abs(src - BG).sum(axis=2)
    frac = _cell_mean((dist > 34).astype(np.float64))
    fg = frac > 0.42
    r = max(2, round(2 * SRC_PITCH / PITCH))
    closed = _erode(_dilate(fg, r), r)
    # Schließen nur dort übernehmen, wo die Vorlage selbst fast schwarz ist (Leerenkristalle),
    # damit offene Lücken zwischen Armen, Kopf und Halo nicht zuwachsen.
    dark = _cell_mean((np.abs(src - BG).sum(axis=2) < 34).astype(np.float64)) > 0.5
    near = _dilate(fg, 1)
    keep = fg | (closed & near & dark)
    return _fill_holes(keep)


def _hsv(px: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rgb = px / 255.0
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6.0
    h[gm] = ((b - r)[gm] / d[gm]) + 2.0
    h[bm] = ((r - g)[bm] / d[bm]) + 4.0
    return h * 60.0, s, mx


# Kalkstein-Rampe des Felsbodens (`assets/shaders/rocky_ground.gdshader`, dunkel -> hell)
GROUND_RAMP = np.array([
    [0x1a, 0x26, 0x30], [0x28, 0x39, 0x45], [0x3d, 0x50, 0x5c], [0x58, 0x6b, 0x74],
    [0x78, 0x8a, 0x8e], [0x9b, 0xa8, 0xa5], [0xbe, 0xc8, 0xbf], [0xd6, 0xdd, 0xd4],
], dtype=np.float64)


def _ramp(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0) * (len(GROUND_RAMP) - 1)
    i = np.minimum(t.astype(int), len(GROUND_RAMP) - 2)
    f = (t - i)[..., None]
    return GROUND_RAMP[i] * (1.0 - f) + GROUND_RAMP[i + 1] * f


def _grade(px: np.ndarray) -> np.ndarray:
    """Farbangleich: Stein auf die Bodenrampe, Gold warm, Leere schwarzviolett."""
    out = px.copy()
    h, s, v = _hsv(px)
    lum = px.mean(axis=-1)
    stone = (s < 0.2) & (lum > 44)
    # Helligkeit 44..240 -> Rampe; leicht angehoben, damit die Statue heller als der Boden bleibt
    t_stone = np.power(np.clip((lum - 44.0) / 196.0, 0.0, 1.0), 0.92) * 0.97 + 0.03
    out[stone] = _ramp(t_stone)[stone]
    gold = (h > 28) & (h < 58) & (s > 0.35) & (v > 0.35)
    out[gold] = out[gold] * np.array([1.06, 1.0, 0.86])
    dark = lum < 46
    out[dark] = out[dark] * np.array([0.78, 0.72, 1.0]) + np.array([0.0, 0.0, 4.0])
    return np.clip(out, 0, 255)


def _quantize(frames: list[np.ndarray], masks: list[np.ndarray]) -> list[np.ndarray]:
    strip = np.concatenate(frames, axis=1).astype(np.uint8)
    pal_img = Image.fromarray(strip).quantize(colors=COLORS, method=Image.Quantize.FASTOCTREE,
                                              dither=Image.Dither.NONE)
    q = np.asarray(pal_img.convert("RGB")).astype(np.float64)
    w = frames[0].shape[1]
    return [q[:, i * w:(i + 1) * w] for i in range(len(frames))]


def _glow_wild(px: np.ndarray, m: np.ndarray) -> np.ndarray:
    h, s, v = _hsv(px)
    void = (((h > 255) & (h < 340)) & (s > 0.32) & (v > 0.24))
    teal = (h > 160) & (h < 200) & (s > 0.28) & (v > 0.48)
    g = np.zeros(px.shape[:2] + (4,), dtype=np.float64)
    g[..., :3] = px
    g[..., 3] = np.where(void, 255, np.where(teal, 120, 0))
    g[~m, 3] = 0
    return g


def _glow_awake(px: np.ndarray, wild_px: np.ndarray, m: np.ndarray) -> np.ndarray:
    h, s, v = _hsv(px)
    lum = px.mean(axis=-1)
    cyan = (h > 160) & (h < 205) & (s > 0.22) & (v > 0.52)
    hot = lum > 228
    wild_dark = wild_px.mean(axis=-1) < 70
    window = (h > 22) & (h < 52) & (s > 0.45) & (v > 0.55) & wild_dark
    g = np.zeros(px.shape[:2] + (4,), dtype=np.float64)
    g[..., :3] = px
    g[..., 3] = np.where(cyan | hot | window, 255, 0)
    g[~m, 3] = 0
    return g


def _components(sel: np.ndarray) -> list[list[tuple[int, int]]]:
    h, w = sel.shape
    seen = ~sel.copy()
    comps: list[list[tuple[int, int]]] = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            comp: list[tuple[int, int]] = []
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            comps.append(comp)
    return comps


def _clear_dark_gaps(px: np.ndarray, m: np.ndarray) -> np.ndarray:
    """Hintergrundfarbene Lücken (zwischen Schleier, Armen, Körper, in Kristallmassen) werden
    transparent. Bleiben: Fenster, Kryptatür und die dunkle 1-px-Fassung der Leerenkristalle."""
    h, w = m.shape
    bg_like = (np.abs(px - BG).sum(axis=-1) < 42) & (px.mean(axis=-1) < 50) & m
    hue, sat, val = _hsv(px)
    crystal = m & ~bg_like & (hue > 240) & (hue < 345) & (sat > 0.14)
    crystal_ring = _dilate(crystal, 1)
    crystal_zone = _dilate(crystal, 4)   # dunkler Körper der Leerenkristalle (Leere zwischen den Facetten)
    outside = ~m
    keep = np.zeros_like(m)
    window_max = int(26 * (SRC_PITCH / PITCH) ** 2)
    for comp in _components(bg_like):
        ys = np.array([c[0] for c in comp])
        xs = np.array([c[1] for c in comp])
        touches_out = False
        for y, x in comp:
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if not (0 <= ny < h and 0 <= nx < w) or outside[ny, nx]:
                    touches_out = True
                    break
            if touches_out:
                break
        in_base = ys.mean() > h * 0.8 and abs(xs.mean() - w / 2) < w * 0.08
        in_crystal = crystal_zone[ys, xs].mean() > 0.25
        if in_crystal or (not touches_out and (len(comp) <= window_max or in_base)):
            keep[ys, xs] = True
    drop = bg_like & ~keep & ~crystal_ring
    out = m & ~drop
    # Einzelne Restpixel ohne Halt entfernen
    nb = sum(_shift(out, dy, dx).astype(int) for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    return out & (nb >= 1)


def _outline(px: np.ndarray, m: np.ndarray) -> np.ndarray:
    """1-px-Kontur in einer dunkel getönten Version der Eigenfarbe (design_guide: nie hart Schwarz)."""
    edge = m & ~_erode(m, 1)
    out = px.copy()
    dark = out[edge] * np.array([0.42, 0.46, 0.55]) + np.array([4.0, 6.0, 12.0])
    lum = px[edge].mean(axis=-1, keepdims=True)
    out[edge] = np.where(lum > 60, dark, px[edge])
    return out


def _bbox(m: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(m)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def _region_center(sel: np.ndarray) -> list[int]:
    ys, xs = np.where(sel)
    if len(xs) == 0:
        return [0, 0]
    return [int(round(xs.mean())), int(round(ys.mean()))]


def main() -> None:
    wild_src = _load("wild")
    awake_src = _load("awake")
    m_w = _mask(wild_src)
    m_a = _mask(awake_src)
    m = m_w | m_a

    wild = _grade(_cell_median(wild_src))
    awake = _grade(_cell_median(awake_src))
    wild_q, awake_q = _quantize([wild, awake], [m_w, m_a])
    m_w = _clear_dark_gaps(wild_q, m_w)
    m_a = _clear_dark_gaps(awake_q, m_a)
    m = m_w | m_a
    wild_q = _outline(wild_q, m_w)
    awake_q = _outline(awake_q, m_a)

    x0, y0, x1, y1 = _bbox(m)
    pad = 2
    x0, y0 = max(x0 - pad, 0), max(y0 - pad, 0)
    x1, y1 = min(x1 + pad, m.shape[1] - 1), min(y1 + pad, m.shape[0] - 1)
    fw = x1 - x0 + 1
    fh = y1 - y0 + 1
    if fw % 2:
        fw += 1

    def frame(px: np.ndarray, mk: np.ndarray) -> np.ndarray:
        rgba = np.zeros((fh, fw, 4), dtype=np.float64)
        sub = px[y0:y0 + fh, x0:x0 + fw]
        sm = mk[y0:y0 + fh, x0:x0 + fw]
        rgba[: sub.shape[0], : sub.shape[1], :3] = sub
        rgba[: sm.shape[0], : sm.shape[1], 3] = sm * 255
        return rgba

    def crop_glow(g: np.ndarray) -> np.ndarray:
        out = np.zeros((fh, fw, 4), dtype=np.float64)
        sub = g[y0:y0 + fh, x0:x0 + fw]
        out[: sub.shape[0], : sub.shape[1]] = sub
        return out

    body = np.concatenate([frame(wild_q, m_w), frame(awake_q, m_a)], axis=1)
    glow = np.concatenate([crop_glow(_glow_wild(wild_q, m_w)),
                           crop_glow(_glow_awake(awake_q, wild_q, m_a))], axis=1)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    Image.fromarray(body.astype(np.uint8), "RGBA").save(OUT_DIR / "sternenauge.png")
    Image.fromarray(glow.astype(np.uint8), "RGBA").save(OUT_DIR / "sternenauge_glow.png")

    # --- Metadaten (Frame-lokale Pixel) -----------------------------------------------------
    fm = m[y0:y0 + fh, x0:x0 + fw]
    rows = np.where(fm.any(axis=1))[0]
    foot_y = int(rows.max())
    foot_x = fw // 2
    widths = fm[int(fh * 0.7):].sum(axis=1)
    base_row = int(fh * 0.7) + int(np.argmax(widths))
    cols = np.where(fm[base_row])[0]
    base_w = int(cols.max() - cols.min() + 1)
    # Linse = hellstes Türkis-Cluster im oberen Fünftel des erwachten Frames
    ag = crop_glow(_glow_awake(awake_q, wild_q, m_a))
    top = np.zeros(ag.shape[:2], dtype=bool)
    top[: fh // 5] = ag[: fh // 5, :, 3] > 0
    lens = _region_center(top)
    meta = {
        "_doc": "Generiert von tools/art_sternenauge.py. Pixel relativ zur linken oberen Frame-Ecke.",
        "frame": [fw, fh],
        "frames": {"wild": 0, "awake": 1},
        "foot": [foot_x, foot_y],
        "base_width": base_w,
        "base_row": base_row,
        "lens": lens,
        "beam_origin": lens,
        # Bodenellipse des Felssockels (Kollision + y-Sortierpunkt) und Kryptatür
        "ground_center": [foot_x, base_row + round(10 * SRC_PITCH / PITCH)],
        "ground_radii": [base_w // 2 - 3, round(30 * SRC_PITCH / PITCH)],
        "door": [foot_x, base_row + round(24 * SRC_PITCH / PITCH)],
    }
    text = json.dumps(meta, indent="\t", ensure_ascii=False)
    # Zahlenpaare einzeilig halten

    text = re.sub(r"\[\s+(-?\d+),\s+(-?\d+)\s+\]", r"[\1, \2]", text)
    OUT_JSON.write_text(text + "\n", encoding="utf-8")
    print("frame", fw, fh, "foot", foot_x, foot_y, "base_w", base_w, "lens", lens)


if __name__ == "__main__":
    main()
