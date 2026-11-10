#!/usr/bin/env python3
"""
Leere-Trank (Void Potion) Icons – 3 Stufen (selten, episch, legendär)
Gleiche schlanke Hexen-Flasche wie die anderen Tränke.
Flüssigkeit: dunkles Void-Purple mit leuchtender Rift/Bruchstelle im Inneren.
"""
import struct, zlib, os

from gen_art import write_png, outline_pass, hexc

# Void-Purple-Palette (RGBA)
BLACK = (0, 0, 0, 255)
DARK_PURPLE = (26, 11, 51, 255)
VOID_PURPLE = (91, 42, 158, 255)
LIGHT_PURPLE = (201, 160, 255, 255)
WHITE = (255, 255, 255, 255)
GLASS = (180, 200, 220, 255)
CORK = (80, 50, 30, 255)
CORK_DARK = (50, 30, 15, 255)
STRING = (100, 80, 60, 255)

def make_bottle(tier=1):
    """Leere-Trank-Icon mit Void-Flüssigkeit und Rift-Motiv."""
    img = [[BLACK for _ in range(16)] for _ in range(16)]

    # Flaschen-Silhouette (schlanke Hexen-Flasche)
    bottle_cells = [
        (7, 3), (8, 3), (7, 4), (8, 4), (7, 5), (8, 5),
        (6, 6), (7, 6), (8, 6), (9, 6),
        (5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7),
        (5, 8), (6, 8), (7, 8), (8, 8), (9, 8), (10, 8),
        (5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (10, 9),
        (5, 10), (6, 10), (7, 10), (8, 10), (9, 10), (10, 10),
        (5, 11), (6, 11), (7, 11), (8, 11), (9, 11), (10, 11),
        (5, 12), (6, 12), (7, 12), (8, 12), (9, 12), (10, 12),
        (6, 13), (7, 13), (8, 13), (9, 13),
    ]
    for x, y in bottle_cells:
        img[y][x] = GLASS

    # Korken
    img[2][7] = CORK
    img[2][8] = CORK
    img[1][7] = CORK_DARK
    img[1][8] = CORK_DARK

    # Schnur mit Charm
    img[4][6] = STRING
    img[5][5] = STRING
    charm_color = [STRING, LIGHT_PURPLE, WHITE][min(tier - 1, 2)]
    img[6][4] = charm_color

    # Flüssigkeit (Void-Purple) – Füllstand steigt mit Stufe
    fill_rows = [10, 11, 12] if tier == 1 else ([9, 10, 11, 12] if tier == 2 else [8, 9, 10, 11, 12])
    for y in fill_rows:
        for x in range(5, 11):
            if any(bx == x and by == y for bx, by in bottle_cells):
                img[y][x] = VOID_PURPLE

    # Rift/Bruchstelle im Inneren – wächst mit Stufe
    if tier >= 1:
        img[10][7] = LIGHT_PURPLE
    if tier >= 2:
        img[10][8] = LIGHT_PURPLE
        img[11][7] = LIGHT_PURPLE
    if tier >= 3:
        img[9][7] = LIGHT_PURPLE
        img[11][8] = LIGHT_PURPLE
        img[10][6] = LIGHT_PURPLE

    # Glühende Partikel um die Rift (höhere Stufen)
    GLOW = (150, 100, 200, 255)
    if tier >= 2:
        img[9][8] = GLOW
    if tier >= 3:
        img[8][7] = GLOW
        img[12][7] = GLOW
        img[12][8] = GLOW

    return outline_pass(img, hexc("1b1a2e"))

from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent / "assets"
os.makedirs(str(ROOT / "items"), exist_ok=True)
for tier in range(1, 4):
    img = make_bottle(tier)
    path = ROOT / "items" / f"potion_leere_{tier}.png"
    write_png(path, 16, 16, img)
    print(f"Written: {path} (tier {tier})")
