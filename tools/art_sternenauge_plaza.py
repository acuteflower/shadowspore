"""DAS STERNENAUGE - Runenstelen, Steinsetzer-Pult & Kanzelbank rund um Caelias Statue (Windkap).

Prozedural, deterministisch, 1 Pixel = 1 Weltpixel. Alles spricht dieselbe Formensprache wie der Felsboden
(`rocky_ground.gdshader`, Geröll & Felsbänke): dieselben drei Gesteinsarten (Kalkstein, Moos-Schiefer,
Travertin) mit je Schatten/Mitte/Licht/Kante, 1-px-Lichtkante oben links, 1-px-Schattenkante unten rechts,
Fugen aus dunklem Lehm oder Polstermoos statt schwarzer Konturen.

Ausgabe:
  assets/props/sternenauge/stele.png          Runenstelen: 3 Varianten x (wild | erwacht)
  assets/props/sternenauge/stele_glow.png
  assets/props/map_tablet.png                 Steinsetzer-Pult (ruhend | erwacht), 64x64, Fuß (32, 54)
  assets/props/map_tablet_glow.png
  assets/props/sternenauge/vista_bench.png    Kanzelbank für den Aussichtspunkt (VistaPoint-Variante 3), 64x48
  assets/props/sternenauge/vista_bench_glow.png
  data/sternenauge_plaza.json                 Freihaltezone (sanctum_radii), Stelen-Fußpunkt

Aufruf: py -3 tools/art_sternenauge_plaza.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "props" / "sternenauge"
OUT_JSON = ROOT / "data" / "sternenauge_plaza.json"
QA_DIR = ROOT / "docs" / "img"


def _c(r: float, g: float, b: float) -> tuple[int, int, int]:
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


# Gesteinsarten 1:1 aus rocky_ground.gdshader (shade_angular_scree): Schatten, Mitte, Licht, Kante
LIME = [_c(0.227, 0.302, 0.353), _c(0.459, 0.529, 0.549), _c(0.588, 0.647, 0.639), _c(0.722, 0.765, 0.733)]
SLATE = [_c(0.216, 0.290, 0.357), _c(0.420, 0.506, 0.561), _c(0.553, 0.631, 0.667), _c(0.694, 0.753, 0.769)]
TRAV = [_c(0.267, 0.318, 0.349), _c(0.510, 0.545, 0.533), _c(0.643, 0.667, 0.631), _c(0.773, 0.788, 0.729)]
KINDS = [LIME, SLATE, TRAV]
LOAM = [_c(0.145, 0.149, 0.165), _c(0.243, 0.216, 0.196), _c(0.341, 0.298, 0.259), _c(0.447, 0.392, 0.337)]
BED = [_c(0.102, 0.149, 0.188), _c(0.157, 0.224, 0.271), _c(0.239, 0.314, 0.361), _c(0.345, 0.420, 0.455),
       _c(0.471, 0.541, 0.557), _c(0.608, 0.659, 0.647), _c(0.745, 0.784, 0.749)]
MOSS = [_c(0.086, 0.188, 0.192), _c(0.129, 0.275, 0.243), _c(0.188, 0.384, 0.290), _c(0.271, 0.506, 0.337),
        _c(0.396, 0.635, 0.388), _c(0.553, 0.773, 0.451)]
LICHEN_SAGE = [_c(0.47, 0.57, 0.51), _c(0.67, 0.76, 0.69)]
LICHEN_OCHRE = [_c(0.51, 0.43, 0.26), _c(0.68, 0.58, 0.35)]
# Gold der Statue (Halo, Armreif) — warm, gedeckt
GOLD = [(0x4a, 0x3a, 0x22), (0x7a, 0x60, 0x30), (0xa8, 0x8a, 0x44), (0xcd, 0xb0, 0x64), (0xec, 0xd4, 0x86)]
TEAL = [(0x2a, 0x6e, 0x6c), (0x4f, 0xb8, 0xb0), (0x78, 0xf4, 0xe6), (0xd0, 0xff, 0xf8)]
VIOLET = [(0x66, 0x36, 0xad), (0x94, 0x68, 0xee), (0xcb, 0xaa, 0xff)]
SHADOW = (16, 22, 34)

EMPTY = -1
SEAM = -2


def h2(*v: float) -> float:
    """Deterministischer Hash -> 0..1."""
    x = 0
    for i, f in enumerate(v):
        x = (x * 1000003) ^ int(f * 7919 + i * 104729)
        x &= 0xFFFFFFFFFFFF
    x = (x ^ (x >> 13)) * 0x5bd1e995 & 0xFFFFFFFF
    x ^= x >> 15
    return (x & 0xFFFFFF) / float(0xFFFFFF)


# ----------------------------------------------------------------------------------------------
# Gemeinsamer Steinmaler: Schlüsselbild -> Pixel (Felsboden-Sprache)
# ----------------------------------------------------------------------------------------------
def paint_stones(keys: np.ndarray, kind_of: dict[int, int], light_of: dict[int, float],
                 seam_col: callable, img: np.ndarray, face_of: dict[int, int] | None = None) -> None:
    """Malt alle Steine eines Schlüsselbilds. keys: >=0 Stein-ID, SEAM Fuge, EMPTY leer.
    Lichtkante oben/links, Schattenkante unten/rechts, Fläche Licht/Mitte mit Lichtverlauf zum Steinmittelpunkt.
    face_of: 0 = liegende Fläche (Boden/Deckel), 1 = Vorderseite (eine Stufe dunkler), 2 = Seitenfläche (zwei Stufen)."""
    hgt, wid = keys.shape
    ys, xs = np.nonzero(keys >= 0)
    ids = keys[ys, xs]
    # Schwerpunkt & Größe je Stein
    cx: dict[int, float] = {}
    cy: dict[int, float] = {}
    sz: dict[int, float] = {}
    if len(ids):
        uniq, inv, cnt = np.unique(ids, return_inverse=True, return_counts=True)
        sx = np.bincount(inv, weights=xs)
        sy = np.bincount(inv, weights=ys)
        for i, k in enumerate(uniq):
            cx[int(k)] = sx[i] / cnt[i]
            cy[int(k)] = sy[i] / cnt[i]
            sz[int(k)] = math.sqrt(cnt[i])

    def at(x: int, y: int) -> int:
        if 0 <= x < wid and 0 <= y < hgt:
            return int(keys[y, x])
        return EMPTY

    for y in range(hgt):
        for x in range(wid):
            k = int(keys[y, x])
            if k == SEAM:
                col = seam_col(x, y)
                if col is not None:
                    img[y, x, :3] = col
                    img[y, x, 3] = 255
                continue
            if k < 0:
                continue
            pal = KINDS[kind_of.get(k, 0)]
            face = face_of.get(k, 0) if face_of else 0
            up, lf = at(x, y - 1), at(x - 1, y)
            dn, rt = at(x, y + 1), at(x + 1, y)
            lit_k = light_of.get(k, 0.5)
            if up != k or (lf != k and up == k and h2(x, y, k, 3.0) < 0.85):
                ti = 3       # Lichtkante (NW-Fase)
            elif dn != k or rt != k:
                ti = 0       # Schattenkante (SO)
            else:
                rel = ((x - cx[k]) * 0.64 + (y - cy[k]) * 0.77) / max(sz[k] * 0.5, 1.0)
                clust = h2(x // 2, y // 2, k, 9.0) - 0.5
                f = 1.55 + (lit_k - 0.5) * 1.1 - rel * 0.55 + clust * 0.7
                ti = 2 if f >= 1.5 else 1
                if h2(x, y, k, 21.0) < 0.035:
                    ti = max(ti - 1, 1)  # Poren / Grübchen
            ti = max(ti - face, 0) if face < 2 else (0 if ti == 0 else 1)
            img[y, x, :3] = pal[ti]
            img[y, x, 3] = 255


def edge_outline(img: np.ndarray, col: tuple[int, int, int], only_bottom: bool = False) -> None:
    """Dunkle Materialkontur nach außen (für aufrechte Props; nicht für das Bodendecal)."""
    a = img[..., 3] > 0
    out = np.zeros_like(a)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if only_bottom and dy != 1:
            continue
        out |= np.roll(np.roll(a, dy, 0), dx, 1)
    out &= ~a
    img[out, :3] = col
    img[out, 3] = 255


# ----------------------------------------------------------------------------------------------
# Runenstelen (gleiches Gestein, Deckfläche + Vorder- + Seitenfläche, Kontur in Schatten-Schiefer)
# ----------------------------------------------------------------------------------------------
SW, SH = 32, 68


def build_stele(variant: int, awake: bool) -> tuple[np.ndarray, np.ndarray]:
    img = np.zeros((SH, SW, 4), dtype=np.float64)
    glow = np.zeros((SH, SW, 4), dtype=np.float64)
    keys = np.full((SH, SW), EMPTY, dtype=np.int64)
    foot = SH - 5
    height = [52, 43, 33][variant]
    half = [7.5, 8.0, 8.5][variant]
    lean = [0.0, 0.05, -0.08][variant]
    top_y = foot - height
    face_of: dict[int, int] = {}
    for y in range(SH):
        for x in range(SW):
            ly = y - top_y
            if ly < 0 or y > foot:
                continue
            frac = ly / max(height, 1)
            cx = SW / 2.0 + lean * (foot - y)
            hw = half * (0.82 + 0.18 * frac)
            dx = x + 0.5 - cx
            cap = 4.0 + dx * (0.3 if variant != 2 else -0.45)      # schräg gebrochene Kappe
            if ly < cap - 3.0 or abs(dx) > hw:
                continue
            if ly < cap:
                keys[y, x] = 1                                      # Deckfläche (Bruch)
            elif dx > hw * 0.42:
                keys[y, x] = 3                                      # rechte Seitenfläche
            else:
                keys[y, x] = 2                                      # Vorderseite
    # Quaderfuge: Stele aus zwei Blöcken
    split = int(top_y + height * (0.58 if variant != 2 else 0.5))
    keys[split, :] = np.where(keys[split, :] > 0, SEAM, keys[split, :])
    lower = np.zeros_like(keys, dtype=bool)
    lower[split + 1:, :] = True
    keys = np.where(lower & (keys > 0), keys + 10, keys)
    face_of = {1: 0, 2: 1, 3: 2, 11: 0, 12: 1, 13: 2}
    kind = 2 if variant == 1 else 0
    kind_of = {k: kind for k in face_of}
    light_of = {1: 0.9, 2: 0.75, 3: 0.4, 11: 0.9, 12: 0.6, 13: 0.35}
    paint_stones(keys, kind_of, light_of, lambda x, y: BED[1], img, face_of)
    edge_outline(img, BED[0])
    # Rune: Raute + drei Striche (eingeschnitten, im Wachzustand türkis)
    rc_x = int(SW / 2.0 + lean * (foot - (top_y + height * 0.4)) - 2)
    rc_y = int(top_y + height * 0.32) + 4
    rune = []
    for d in range(4):
        rune += [(rc_x - d, rc_y - 3 + d), (rc_x + d, rc_y - 3 + d), (rc_x - d, rc_y + 3 - d), (rc_x + d, rc_y + 3 - d)]
    for k in range(3):
        rune += [(rc_x - 2 + k * 2, rc_y + 6), (rc_x - 2 + k * 2, rc_y + 7)]
    for (x, y) in rune:
        if 0 <= x < SW and 0 <= y < SH and img[y, x, 3] > 0:
            img[y, x, :3] = TEAL[2] if awake else BED[1]
            glow[y, x, :3] = TEAL[2] if awake else TEAL[1]
            glow[y, x, 3] = 255 if awake else 70
    # Goldband unter der Kappe (wie Armreif der Statue)
    gy = int(top_y + 7 + (1 if variant == 2 else 0))
    for x in range(SW):
        if img[gy, x, 3] > 0 and tuple(img[gy, x, :3]) != BED[0]:
            img[gy, x, :3] = GOLD[3] if x < SW / 2 + lean * (foot - gy) + 2 else GOLD[2]
    # Polstermoos & Flechten am Fuß
    for y in range(foot - 8, foot + 1):
        for x in range(SW):
            if img[y, x, 3] > 0 and tuple(img[y, x, :3]) != BED[0] and \
                    h2(x // 2, y // 2, 31.0 + variant) < 0.62 * (1.0 - (foot - y) / 9.0):
                img[y, x, :3] = MOSS[2 + (1 if h2(x, y) > 0.5 else 0) + (1 if y < foot - 4 else 0)]
    for (x, y) in [(SW // 2 - 4, top_y + 14), (SW // 2 - 3, top_y + 15), (SW // 2 - 4, top_y + 15)]:
        if img[y, x, 3] > 0:
            img[y, x, :3] = LICHEN_SAGE[1]
    # Bodenschatten
    for y in range(foot - 1, SH):
        for x in range(SW):
            if img[y, x, 3] == 0 and ((x + 0.5 - SW / 2.0 - 1.5) / (half + 4)) ** 2 + ((y - foot - 0.5) / 2.6) ** 2 < 1.0:
                img[y, x, :3] = SHADOW
                img[y, x, 3] = 96
    return img, glow


# ----------------------------------------------------------------------------------------------
# Steinsetzer-Pult (Kartentafel) — gleiches Gestein, Goldrahmen, ALTMARK eingraviert
# ----------------------------------------------------------------------------------------------
TW, TH = 64, 64
T_FOOT = (32, 54)
# ALTMARK grob (normiert 0..1 auf der Tafel), Westküste links, Windkap unten links
ALTMARK = [(0.06, 0.62), (0.10, 0.40), (0.20, 0.30), (0.28, 0.12), (0.42, 0.18), (0.52, 0.08), (0.66, 0.14),
           (0.78, 0.10), (0.92, 0.26), (0.95, 0.46), (0.86, 0.60), (0.90, 0.78), (0.74, 0.92), (0.56, 0.84),
           (0.44, 0.94), (0.30, 0.86), (0.16, 0.90), (0.10, 0.78)]
RIFT = [(0.60, 0.30), (0.64, 0.42), (0.62, 0.52), (0.68, 0.64)]
WINDKAP = (0.14, 0.80)


def _in_poly(x: float, y: float, poly: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def build_tablet(awake: bool) -> tuple[np.ndarray, np.ndarray]:
    img = np.zeros((TH, TW, 4), dtype=np.float64)
    glow = np.zeros((TH, TW, 4), dtype=np.float64)
    keys = np.full((TH, TW), EMPTY, dtype=np.int64)
    face_of: dict[int, int] = {}
    kind_of: dict[int, int] = {}
    light_of: dict[int, float] = {}

    def box(k: int, x0: int, y0: int, x1: int, y1: int, top_h: int, kind: int, lit: float) -> None:
        """Quader in 3/4-Sicht: Deckfläche (top_h Zeilen) + Vorderseite."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                keys[y, x] = k if y < y0 + top_h else k + 1
        face_of[k], face_of[k + 1] = 0, 1
        kind_of[k] = kind_of[k + 1] = kind
        light_of[k], light_of[k + 1] = lit, lit * 0.8

    # Stufensockel (zwei Platten aus dem Platzgestein) und Schaft
    box(10, 13, 46, 50, 54, 4, 0, 0.55)
    box(20, 17, 41, 46, 47, 3, 2, 0.7)
    box(30, 24, 31, 39, 41, 2, 2, 0.6)
    # Fugen in der unteren Platte
    for xx in (25, 38):
        for yy in range(50, 55):
            keys[yy, xx] = SEAM
    # Schräges Pult: Trapez (oben schmaler), Tafelrand Travertin
    top, bot = 8, 34
    for y in range(top, bot + 1):
        t = (y - top) / (bot - top)
        hw = 21 + t * 4.0
        for x in range(TW):
            if abs(x + 0.5 - 32) <= hw:
                keys[y, x] = 40 if y < top + 3 else 41
    face_of[40], face_of[41] = 0, 0
    kind_of[40] = kind_of[41] = 2
    light_of[40], light_of[41] = 0.95, 0.7
    # Pult-Unterkante (Dicke)
    for y in range(bot + 1, bot + 4):
        hw = 25 - (y - bot - 1)
        for x in range(TW):
            if abs(x + 0.5 - 32) <= hw:
                keys[y, x] = 42
    face_of[42], kind_of[42], light_of[42] = 1, 2, 0.4

    paint_stones(keys, kind_of, light_of, lambda x, y: LOAM[1], img, face_of)
    edge_outline(img, BED[0])

    # Goldrahmen & dunkle Schiefer-Einlage mit ALTMARK
    in0, in1 = top + 4, bot - 3
    for y in range(top + 2, bot - 1):
        t = (y - top) / (bot - top)
        hw = 21 + t * 4.0 - 2.0
        for x in range(TW):
            d = abs(x + 0.5 - 32)
            if d > hw:
                continue
            if y in (top + 2, bot - 2) or d > hw - 1.0:
                img[y, x, :3] = GOLD[3] if (y == top + 2 or x < 32) else GOLD[2]
                if (y == top + 2 and h2(x, 4.0) > 0.85):
                    img[y, x, :3] = GOLD[4]
                continue
            if in0 <= y <= in1:
                hwi = hw - 1.0
                u = (x + 0.5 - (32 - hwi)) / (2 * hwi)
                v = (y - in0) / (in1 - in0)
                land = _in_poly(u, v, ALTMARK)
                col = BED[1] if not land else BED[2]
                if land:
                    # Küstenlinie
                    edge = not all(_in_poly(u + du, v + dv, ALTMARK) for du, dv in ((0.03, 0), (-0.03, 0), (0, 0.06), (0, -0.06)))
                    if edge:
                        col = TEAL[2] if awake else BED[4]
                        glow[y, x, :3] = TEAL[2] if awake else TEAL[1]
                        glow[y, x, 3] = 255 if awake else 60
                    elif h2(x, y, 3.0) < 0.12:
                        col = BED[3]
                img[y, x, :3] = col
                # Großer Riss (violett) & Windkap (Gold)
                for i in range(len(RIFT) - 1):
                    (ax, ay), (bx, by) = RIFT[i], RIFT[i + 1]
                    tt = max(0.0, min(1.0, ((u - ax) * (bx - ax) + (v - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
                    if math.hypot((u - ax - tt * (bx - ax)) * 2 * hwi, (v - ay - tt * (by - ay)) * (in1 - in0)) < 0.7:
                        img[y, x, :3] = VIOLET[1] if awake else BED[0]
                        glow[y, x, :3] = VIOLET[2] if awake else VIOLET[0]
                        glow[y, x, 3] = 255 if awake else 70
                if math.hypot((u - WINDKAP[0]) * 2 * hwi, (v - WINDKAP[1]) * (in1 - in0)) < 1.3:
                    img[y, x, :3] = GOLD[4] if awake else GOLD[2]
                    glow[y, x, :3] = (0xff, 0xe8, 0xa0)
                    glow[y, x, 3] = 255 if awake else 90
            else:
                img[y, x, :3] = BED[2]
    # Türkis-Raute am Schaft (wie Stelen & Platz)
    rx, ry = 31, 37
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if abs(dx) + abs(dy) <= 2 and img[ry + dy, rx + dx, 3] > 0:
                inner = abs(dx) + abs(dy) <= 1
                img[ry + dy, rx + dx, :3] = (TEAL[2] if awake else TEAL[0]) if inner else GOLD[2]
                if inner:
                    glow[ry + dy, rx + dx, :3] = TEAL[2]
                    glow[ry + dy, rx + dx, 3] = 255 if awake else 80
    # Moos am Sockel
    for y in range(46, 55):
        for x in range(TW):
            if img[y, x, 3] > 0 and tuple(img[y, x, :3]) != BED[0] and h2(x // 2, y // 2, 91.0) < 0.3 * (y - 45) / 9.0:
                img[y, x, :3] = MOSS[2 + (1 if h2(x, y) > 0.5 else 0)]
    # Bodenschatten
    for y in range(52, TH):
        for x in range(TW):
            if img[y, x, 3] == 0 and ((x + 0.5 - 33.5) / 22.0) ** 2 + ((y - 55.0) / 3.2) ** 2 < 1.0:
                img[y, x, :3] = SHADOW
                img[y, x, 3] = 96
    return img, glow


# ----------------------------------------------------------------------------------------------
# Kanzelbank (Aussichtspunkt am Platzrand) — 64x48, Sitzfläche ~ y 31, Boden y 40
# ----------------------------------------------------------------------------------------------
BW, BH = 64, 48


def build_bench() -> tuple[np.ndarray, np.ndarray]:
    img = np.zeros((BH, BW, 4), dtype=np.float64)
    glow = np.zeros((BH, BW, 4), dtype=np.float64)
    keys = np.full((BH, BW), EMPTY, dtype=np.int64)
    face_of: dict[int, int] = {}
    kind_of: dict[int, int] = {}
    light_of: dict[int, float] = {}

    def box(k: int, x0: int, y0: int, x1: int, y1: int, top_h: int, kind: int, lit: float) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                keys[y, x] = k if y < y0 + top_h else k + 1
        face_of[k], face_of[k + 1] = 0, 1
        kind_of[k] = kind_of[k + 1] = kind
        light_of[k], light_of[k + 1] = lit, lit * 0.8

    box(10, 16, 32, 24, 40, 2, 0, 0.5)       # linker Fuß
    box(20, 40, 32, 48, 40, 2, 0, 0.45)      # rechter Fuß
    box(30, 11, 25, 53, 33, 5, 2, 0.85)      # Sitzplatte (Travertin wie der Platz-Innenring)
    keys[25:34, 32] = np.where(keys[25:34, 32] >= 0, SEAM, keys[25:34, 32])   # zweiteilige Platte
    keys[25:34, 33:] = np.where(keys[25:34, 33:] >= 30, keys[25:34, 33:] + 100, keys[25:34, 33:])
    for k in (130, 131):
        face_of[k] = face_of[k - 100]
        kind_of[k] = 0
        light_of[k] = light_of[k - 100] * 0.9
    # abgebrochene Ecke rechts oben
    for y in range(25, 28):
        for x in range(50 + (y - 25), 54):
            keys[y, x] = EMPTY
    paint_stones(keys, kind_of, light_of, lambda x, y: LOAM[1], img, face_of)
    edge_outline(img, BED[0])
    # Goldene Einlegekante an der Sitzvorderseite & Raute
    for x in range(13, 52):
        if img[31, x, 3] > 0 and tuple(img[31, x, :3]) != BED[0] and h2(x, 31.0) > 0.18:
            img[31, x, :3] = GOLD[3] if x < 32 else GOLD[2]
    rx, ry = 32, 28
    for dy in range(-1, 2):
        for dx in range(-2, 3):
            if abs(dx) / 2.0 + abs(dy) <= 1.0:
                img[ry + dy, rx + dx, :3] = TEAL[1] if (dx, dy) != (0, 0) else TEAL[2]
                glow[ry + dy, rx + dx, :3] = TEAL[2]
                glow[ry + dy, rx + dx, 3] = 200
    # Moos & Flechten
    for y in range(24, 41):
        for x in range(BW):
            if img[y, x, 3] > 0 and tuple(img[y, x, :3]) != BED[0]:
                if y >= 36 and h2(x // 2, y // 2, 93.0) < 0.35:
                    img[y, x, :3] = MOSS[2 + (1 if h2(x, y) > 0.5 else 0)]
                elif y < 29 and 13 <= x <= 20 and h2(x, y, 94.0) < 0.4:
                    img[y, x, :3] = LICHEN_SAGE[(x + y) % 2]
    # Bodenschatten
    for y in range(38, BH):
        for x in range(BW):
            if img[y, x, 3] == 0 and ((x + 0.5 - 33.5) / 25.0) ** 2 + ((y - 40.5) / 3.0) ** 2 < 1.0:
                img[y, x, :3] = SHADOW
                img[y, x, 3] = 96
    return img, glow


def _save(arr: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(path)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet = np.zeros((SH * 2, SW * 3, 4), dtype=np.float64)
    sheet_g = np.zeros_like(sheet)
    for v in range(3):
        for row, awake in enumerate((False, True)):
            im, gl = build_stele(v, awake)
            sheet[row * SH:(row + 1) * SH, v * SW:(v + 1) * SW] = im
            sheet_g[row * SH:(row + 1) * SH, v * SW:(v + 1) * SW] = gl
    _save(sheet, OUT_DIR / "stele.png")
    _save(sheet_g, OUT_DIR / "stele_glow.png")

    tab = np.zeros((TH, TW * 2, 4), dtype=np.float64)
    tab_g = np.zeros_like(tab)
    for col, awake in enumerate((False, True)):
        im, gl = build_tablet(awake)
        tab[:, col * TW:(col + 1) * TW] = im
        tab_g[:, col * TW:(col + 1) * TW] = gl
    _save(tab, ROOT / "assets" / "props" / "map_tablet.png")
    _save(tab_g, ROOT / "assets" / "props" / "map_tablet_glow.png")

    bench, bench_g = build_bench()
    _save(bench, OUT_DIR / "vista_bench.png")
    _save(bench_g, OUT_DIR / "vista_bench_glow.png")

    meta = {
        "_doc": "Generiert von tools/art_sternenauge_plaza.py.",
        "sanctum_radii": [171.0, 96.1],
        "stele_frame": [SW, SH],
        "stele_foot": [SW // 2, SH - 5],
        "stele_variants": 3,
    }
    OUT_JSON.write_text(json.dumps(meta, indent="\t") + "\n", encoding="utf-8")
    print("stele", SW, SH, "tablet", TW, TH, "bench", BW, BH)


if __name__ == "__main__":
    main()
