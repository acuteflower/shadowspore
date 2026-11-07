# Boss arena (stage for the first boss fight)

Stage only: the boss design comes from another agent. Plateau at tile (499, 258) (relief level 3, ramp on the south side).

- **Data:** `data/ground.json` `arenas[]` {id, tile, level, clear_margin, poly (px relative to the tile's centre, traced from the user's drawing), pillars [{pos, variant}]}.
- **Floor:** `tools/bake_ground.py --yards` (seconds) bakes `assets/world/ground/boss_arena_arena.png` + mask (surface `stone`) with the same flagstone look as the start field, grass/moss breaking through. It is cut to the plateau top (relief field channel `level - 1`, 4 px away from the lip). Then `Godot --headless --path . --import`.
- **Empty stage:** `WorldLevel._add_arenas` keeps every tile inside the polygon (+ `clear_margin` px) free of generated trees, bushes and plants.
- **Pillars:** `ArenaPillar` (`src/entities/props/arena_pillar.gd`), art `py -3 tools/art_arena_pillars.py` -> `assets/props/arena_pillars{,_glow}.png` (3 variants, frames 64x128, feet (32, 118), contact sheet `docs/img/arena_pillars.png`). Solid 22x8 footprint, glowing vein (unlit, brighter at night), violet `NightLight`, fades to 38 % while it hides someone behind it. Two pillars were moved inward from the drawn spots so their feet stand fully on the plateau top.
- Preview: `Godot --rendering-driver opengl3 --path . tools/preview_daylight.tscn -- --dir=/abs --times=0.5 --at=499,258`.
