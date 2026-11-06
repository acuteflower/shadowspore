#!/usr/bin/env python3
"""16x16 icon of the Void Crusher's rare drop: a chunk of petrified void basalt (stone ramp of art_stone.py, outline 1b1a2e, lit top left, tiny violet vein)."""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / 'assets/items/void_slag.png'
P = {'.': None, 'o': '#1b1a2e', 'd': '#141221', 'm': '#292840', 'l': '#474a6a', 'h': '#787ea0', 'v': '#8a4dff', 'c': '#ecd2ff'}
ROWS = [
    '................',
    '................',
    '.....oooo.......',
    '...oolhhloo.....',
    '..olhhllmmdoo...',
    '..olhllmmmmmdo..',
    '.oolllmmvmmmddo.',
    '.olllmmmvmmmmdo.',
    '.olmmmmvvcmmmdo.',
    '.olmmmmmvvmmddo.',
    '.oomdmmmmmmddoo.',
    '..oomddmmmddoo..',
    '...ooodddddoo...',
    '.....oooooo.....',
    '................',
    '................',
]
im = Image.new('RGBA', (16, 16), (0, 0, 0, 0))
for y, row in enumerate(ROWS):
    assert len(row) == 16, row
    for x, ch in enumerate(row):
        if P[ch]:
            im.putpixel((x, y), tuple(int(P[ch][i:i + 2], 16) for i in (1, 3, 5)) + (255,))
im.save(OUT)
print('wrote', OUT)
