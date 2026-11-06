"""Bake the cliff spring (Felswand-Quelltopf) spritesheet for all 5 wall styles.
Styles:
  0: Earth / Grass (mossy overhanging turf and dark loam cavity)
  1: Rock (slate stone cleft with bubbling surge)
  2: Masonry (carved stone arched niche with fountain spout / basin)
  3: Crystal (violet crystal-encrusted cavern with luminous water)
  4: Void (corrupted basalt rift with magenta pulsing cracks)

Dimensions: 48x36 per frame, 4 looping animation frames (fps=8), 5 rows (one per style).
Run: .venv/bin/python3 tools/art_cliff_spring.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/water'
OUT.mkdir(parents=True, exist_ok=True)

FW, FH = 48, 36
FRAMES = 4
STYLES = 5

sheet = Image.new('RGBA', (FW * FRAMES, FH * STYLES), (0, 0, 0, 0))
glow_sheet = Image.new('RGBA', (FW * FRAMES, FH * STYLES), (0, 0, 0, 0))

# Colors
C_DARK = '#0a0812'
C_WATER_DEEP = '#183437'
C_WATER_MID = '#2f5e5a'
C_WATER_LIGHT = '#4a7f76'
C_WATER_FOAM = '#91bbae'
C_WATER_CREAM = '#d9e8dc'

STYLE_PALETTES = [
    # 0: Earth / Turf
    {
        'base': '#2a1f2e', 'mid': '#4a352f', 'light': '#6b4c3a',
        'accent': '#3e7d56', 'accent2': '#7cb96d',
        'water_tint': None
    },
    # 1: Slate Rock
    {
        'base': '#2f2e47', 'mid': '#4c4b68', 'light': '#6e6d8e',
        'accent': '#9b99b8', 'accent2': '#c4c2db',
        'water_tint': None
    },
    # 2: Masonry (Carved Arch)
    {
        'base': '#2b2a40', 'mid': '#403f5c', 'light': '#5a5879',
        'accent': '#7a7898', 'accent2': '#9d9ab8',
        'water_tint': None
    },
    # 3: Crystal
    {
        'base': '#221b38', 'mid': '#372b58', 'light': '#563e85',
        'accent': '#7a4de0', 'accent2': '#b06bff',
        'water_tint': '#78f4e6', 'glow': True
    },
    # 4: Void
    {
        'base': '#0e0919', 'mid': '#1a1030', 'light': '#2b1542',
        'accent': '#5a36b8', 'accent2': '#ff4fd8',
        'water_tint': '#cbaaff', 'glow': True
    }
]

for style_idx, pal in enumerate(STYLE_PALETTES):
    is_glow = pal.get('glow', False)
    for frame in range(FRAMES):
        im = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        glow_im = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_im)

        # 1. Background rock/wall flanks (arch/niche framing the spring)
        # Left rock flank
        d.polygon([(4, 2), (16, 2), (18, 10), (16, 26), (12, 34), (4, 34)], fill=pal['base'])
        d.polygon([(6, 4), (14, 4), (16, 12), (14, 24), (10, 32), (6, 32)], fill=pal['mid'])
        d.polygon([(8, 5), (13, 5), (14, 11), (12, 18), (8, 20)], fill=pal['light'])

        # Right rock flank
        d.polygon([(32, 2), (44, 2), (44, 34), (36, 34), (32, 26), (30, 10)], fill=pal['base'])
        d.polygon([(34, 4), (42, 4), (42, 32), (38, 32), (34, 24), (32, 12)], fill=pal['mid'])
        d.polygon([(35, 5), (40, 5), (40, 20), (36, 18), (34, 11)], fill=pal['light'])

        # Top lintel / overhang
        d.polygon([(14, 2), (34, 2), (32, 9), (16, 9)], fill=pal['mid'])
        d.polygon([(16, 3), (32, 3), (30, 6), (18, 6)], fill=pal['light'])

        # Style specifics
        if style_idx == 0:  # Earth / Moss
            # Hanging turf and grass fringe
            for gx in range(12, 36, 3):
                d.line([(gx, 6), (gx + 1, 9), (gx, 12)], fill=pal['accent'])
                d.point((gx, 13), fill=pal['accent2'])
            d.line([(10, 15), (12, 22), (11, 28)], fill='#514c3e')  # root
        elif style_idx == 1:  # Slate Rock
            # Strata cracks
            d.line([(6, 14), (13, 12), (15, 16)], fill=C_DARK)
            d.line([(34, 15), (38, 13), (42, 17)], fill=C_DARK)
            d.line([(8, 22), (14, 21)], fill=pal['accent'])
        elif style_idx == 2:  # Masonry
            # Carved stone block borders and arched trim
            d.rectangle((10, 3, 38, 7), outline=pal['accent'], fill=pal['mid'])
            d.line([(18, 3), (18, 7)], fill=C_DARK)
            d.line([(30, 3), (30, 7)], fill=C_DARK)
            # Spout carving in upper center
            d.polygon([(22, 10), (26, 10), (25, 15), (23, 15)], fill=pal['accent2'])
            d.rectangle((23, 14, 25, 15), fill=C_DARK)
        elif style_idx == 3:  # Crystal
            # Crystal clusters jutting from walls
            # Left cluster
            d.polygon([(12, 14), (16, 10), (18, 14), (15, 18)], fill=pal['accent'])
            d.polygon([(13, 13), (16, 11), (17, 14)], fill=pal['accent2'])
            d.polygon([(10, 20), (14, 17), (15, 23), (11, 24)], fill=pal['accent'])
            # Right cluster
            d.polygon([(32, 13), (36, 9), (38, 14), (34, 17)], fill=pal['accent'])
            d.polygon([(33, 12), (36, 10), (37, 13)], fill=pal['accent2'])
            d.polygon([(34, 19), (38, 16), (39, 22), (35, 23)], fill=pal['accent'])
            # Emissive glow
            gd.polygon([(13, 13), (16, 11), (17, 14)], fill='#e6d0ff')
            gd.polygon([(33, 12), (36, 10), (37, 13)], fill='#e6d0ff')
            gd.point((15, 12), fill='#ffffff')
            gd.point((35, 11), fill='#ffffff')
        elif style_idx == 4:  # Void
            # Magenta cracks
            d.line([(10, 8), (14, 14), (12, 22), (14, 28)], fill=pal['accent2'])
            d.line([(38, 7), (35, 13), (37, 21), (34, 27)], fill=pal['accent2'])
            # Emissive glow
            gd.line([(10, 8), (14, 14), (12, 22), (14, 28)], fill=pal['accent2'])
            gd.line([(38, 7), (35, 13), (37, 21), (34, 27)], fill=pal['accent2'])

        # 2. Dark inner cavelet / fissure
        d.polygon([(15, 9), (33, 9), (35, 16), (33, 27), (15, 27), (13, 16)], fill=C_DARK)

        # 3. Gushing/Bubbling Spring Water (animated across 4 frames)
        # Deep pool at back
        d.polygon([(16, 14), (32, 14), (34, 22), (32, 28), (16, 28), (14, 22)], fill=C_WATER_DEEP)

        # Surge tongue (pours forward)
        phase = frame / float(FRAMES)
        sway = int(round(1.5 * ((frame % 2) * 2 - 1)))
        d.polygon([(18, 16), (30, 16), (32 + sway, 27), (30 + sway, 33), (18 - sway, 33), (16 - sway, 27)], fill=C_WATER_MID)
        d.polygon([(20, 18), (28, 18), (29 + sway, 26), (27 + sway, 31), (21 - sway, 31), (19 - sway, 26)], fill=C_WATER_LIGHT)

        # Bubbles & foam crests (rippling out)
        for i in range(5):
            bx = 20 + ((i * 7 + frame * 3) % 11) + (sway if i % 2 == 0 else -sway)
            by = 20 + ((i * 5 + frame * 4) % 12)
            d.point((bx, by), fill=C_WATER_FOAM)
            if (i + frame) % 2 == 0:
                d.point((bx + 1, by), fill=C_WATER_CREAM)

        # Front lip splash / foam apron (spreading into river head at y=31..35)
        apron_w = 12 + (frame % 2) * 2
        d.ellipse((24 - apron_w, 29, 24 + apron_w, 35), fill=C_WATER_MID)
        d.ellipse((24 - apron_w + 3, 30, 24 + apron_w - 3, 34), fill=C_WATER_LIGHT)
        # Foam ripples at edge
        ripple_offset = (frame * 2) % 4
        d.arc((24 - apron_w + 1, 29 + ripple_offset, 24 + apron_w - 1, 35 + ripple_offset), 0, 180, fill=C_WATER_FOAM)

        # If crystal or void, add slight water shimmer/tint in glow pass
        if style_idx == 3:  # Crystal water glint
            gd.point((24 + sway, 25), fill='#78f4e6')
            gd.point((22, 28), fill='#78f4e6')
        elif style_idx == 4:  # Void water glint
            gd.point((24 + sway, 25), fill='#ff4fd8')
            gd.point((26, 29), fill='#ff4fd8')

        # Paste onto full sheets
        ox = frame * FW
        oy = style_idx * FH
        sheet.alpha_composite(im, (ox, oy))
        glow_sheet.alpha_composite(glow_im, (ox, oy))

sheet.save(OUT / 'cliff_spring.png')
glow_sheet.save(OUT / 'cliff_spring_glow.png')
print(f"Baked cliff spring spritesheet ({sheet.width}x{sheet.height}) and glow map to {OUT}")
