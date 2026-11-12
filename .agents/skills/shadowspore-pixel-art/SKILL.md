---
name: shadowspore-pixel-art
description: >-
  Guides pixel art creation, Python art generator scripts (tools/art_*.py),
  palettes, scale, pivots, glow masks, and visual previews for Shadowspore.
  Use when creating or editing sprites, tiles, icons, portraits, shaders, or
  tools/art_*.py scripts.
---

# Shadowspore Pixel Art Pipeline

Follow the project's visual standard in [design_guide.md](../../../docs/design_guide.md), [characters_guide.md](../../../docs/characters_guide.md), and [dialogue_art.md](../../../docs/dialogue_art.md).

## Core Visual Rules
1. **Grid & Filtering:** `640x360` base viewport, `16x16` tiles. Nearest filtering, strict pixel-snapping (no half-pixel positions). Never rotate pixel art sprites except weapons and FX.
2. **Lighting & Outlines:** Top-left light source. Use 3–4 tonal steps per material (dark → light) with cool-violet shadows (not neutral grey). Use a 1 px tinted dark outline (never pure `#000000`; shadow creatures use `#040208`).
3. **Clean Clusters:** Fill surfaces with short directional strokes and small clusters — never random pixel noise.
4. **Pivots & Sorting:** Anchor at bottom-center (feet). World entities use `y_sort_enabled = true` and a dark ground shadow ellipse (~`17x5` px).

## Scale Reference
- **Player (Ellie):** `48x56` frame, ~`42 px` tall, feet at `(24, 51)`.
- **Human NPCs:** `36–44 px` tall.
- **Small animals / critters:** `12–24 px`.
- **Standard enemies:** `24–40 px` body; **Bosses:** `64–96 px`.
- **Item icons:** `16x16`.
- **Dialogue portraits:** `103x153` logical (`206x306` display), head-to-hip crop, 3/4 view toward text (`docs/dialogue_art.md`).

## Palette Families (`docs/design_guide.md`)
- **Meadow (6 tones):** `22483c` `2f624e` `3e7d56` `55985f` `7cb96d` `a8dc8c`
- **Violet (Void/Magic):** `34185e` `6636ad` `9468ee` `cbaaff`
- **Turquoise Glow (Life/Unlit):** `2a8c94` `3cc0c6` `78f4e6` `d0fff8`
- **Gold (Metal/Value):** `6f5020` `b48a38` `e6c468` `fff0b0`
- **Shadow Creatures:** outline `040208`, body `07040d` `0e0919` `1a1030` `221740`, rim `5a36b8`, vein `8a4dff`, glow `b06bff`, core `ecd2ff`
- **Danger:** `ff4fd8`, warning `c21f3b` → `ff4a63` → `ffd0d6`

## Technical Pipeline (`tools/`)
1. **Procedural Python Generators:** Prefer extending or matching existing generators in `tools/art_*.py` (e.g., `tools/art_hero3d.py` ellipsoid renderer, `tools/art_flora.py`, `tools/art_loot_chests.py`).
2. **8-Direction Sprite Sheets:** Rows `0..7` follow sector order `E, SE, S, SW, W, NW, N, NE` (no horizontal flipping).
3. **Heroine Face Post-Process:** After rebuilding Ellie sheets, run `py -3 tools/hero_face.py` (or `tools/art_hero_rebuild.py` / `tools/art_hero_story_rebuild.py`) so pixel eyes and silhouettes remain valid.
4. **Glow Sheets:** Luminous pixels (veins, lanterns, runes, blooms) go into a separate `*_glow.png` rendered unlit (`Unlit.material()` / `render_mode unshaded`) without shading.

## Verification
After generating or editing art, always inspect the output visually:
- Run the matching `tools/preview_*.tscn` with `-- --capture=<abs_path.png>` or `-- --dir=<abs_dir>` (and `--night` if it has glow/lights).
- View the generated PNG via `read_file` to verify silhouette, proportions, palette, and pixel crispness.
