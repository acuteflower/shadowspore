# Forest demography, forest floor and slopes

All of it is a pure function of the world seed and the baked maps (every peer and every chunk load gets the same answer); nothing is saved.
Test: `Godot --headless --path . tools/test_forest.tscn` (23 checks over the whole map); regressions `test_flora`, `test_streaming_performance`, `test_world_rivers`.

## 1. Forest floor (`forestbed`)
- Every tree that stands in a **grove or wood** (`_grove`, `_wood`; not lone trees) lays down a patch of forest floor under itself: kind `forestbed` in the generator output (a ground decal like `stonebed`, `variant` = size, `FOREST_BED_RX` 28..70 px, chosen from the crown width x 1.35), produced **only for trees that survive the overlap tests**, so no floor lies under a tree that was dropped.
- Art: `python3 tools/art_forestbed.py [preview.png]` -> `assets/props/forestbed.png` (6 frames 192x128): plum-brown humus, needle strokes, twigs, cones, moss cushions in the land flora's greens, lichen specks, rim dissolved in dither. `WorldLevel._add_forest_bed` places it at z -9; `_forest_bed_ok` rejects water, cliffs/edges, coast, old flagstones and the footpath (the same test is used when a neighbouring chunk's bed is indexed as an obstacle).
- **Ground cover on it** (`_detail_candidate`): inside a bed (ellipse test) 45 % of the small plants are dropped and the rest are shade plants: ferns (9, 10, 11, 18, 19) and the two new **shade moss** variants 24 (cushions) and 25 (flat mat with spore stalks) of `MeadowDetails` (`COUNT` 26; the shader divides by 26; the old random pool stays 0-23).
- Fallen trunks may lie on a forest floor (`FallenLogScatter` skips `forestbed` as an obstacle).

## 2. Canopy and clearings
- `CROWN_OVERLAP` (0.8) is the **minimum distance of two crowns as a multiple of their half widths**: a *smaller* value lets crowns reach into each other, a larger one pushes trees apart. So the canopy is closed by *lowering* the value for trees of a grove or wood (`DENSE_CROWN_OVERLAP` 0.6, candidates carry `dense`); every other pair keeps 0.8. The trunk footprint still keeps trunks apart (the real limit for the giants). Measured over the map: 885 pairs closer than the old limit, none closer than 0.60.
- Most woods (65 %) get a **clearing** (radius 20-32 % of the wood, off-centre, from a seeded stream of its own): no trees inside, 4-8 sun-loving flowers instead (`_flora_kind` with open ground).

## 3. Saplings and young firs
- 2-18 % of the firs of groves and woods (avg ~13 %, more toward the rim) are planted young (`_young_for`, from the position only; variant 0/1). The generator output carries `young` (age 0-3).
- `WorldLevel._young` + `thing_state()` give them the felled-tree state `{"f": 1, "h": ...}` that a regrowing tree already shows (sapling, then young tree, `tree_growth.png`), computed from `TimeManager.day`: `(age + day - 1) / YOUNG_GROW_DAYS` (7 days) -> mature = `{}` and forgotten. Never the bare stump. They cannot be chopped meanwhile (state `f`). `_age_young` re-shows the loaded ones at every sunrise on every peer. Nothing is stored in `_thing_states` (so old saves are untouched).

## 4. Fallen trunks at trees
- `FallenLogScatter` counts trees within 5 tiles (`_trees_near`): the chance is x0.12 in the open, x(1 + 0.15 per tree, up to 4) in and at stands. Measured: 38 of 42 candidates near trees.

## 5. Krummholz
- A tree or bush whose feet stand on relief level >= 1.6 (`KRUMMHOLZ_LEVEL`: the 2 and 3 plateaus) is limited to tree variant 0/1 and drawn at 0.75-0.85 (`scale` in the generator output; footprint and crown shrink with it, `WorldLevel._create_thing` scales the node). `WorldProp.wind_boost` = 1 + 3 x (1 - scale) raises its wind exposure (sway). `FirTree._covers` divides by the scale. Hand-placed props (data/ground.json) are exempt.
- Known limit: harvest hitboxes and prompts scale with the node, the crown's night light pool does not.

## 6. Slopes (`PropGenerator.aspect(at_tiles)`, -1 .. +1)
- From the relief level 3 tiles north vs south of a point (ground rising to the north = a south-facing, sunny slope) and `wall_above` (the foot of a cliff lies in its shadow: <= -0.7).
- `shade = wild - 0.45 x aspect` replaces the noise shade for mushrooms, shroom patches, root vegetables and the flora choice (glow ferns, moonbells, mist lilies on north slopes/cliff feet); on sunny slopes sun blooms are up to 2.6x as likely, whisper grass and tussocks are more frequent, and the small ground cover turns to straw and thin grass (22, 23, 0, 2); north slopes get ferns and moss (9, 10, 11, 18, 19, 24, 25).
- Not done: the painted ground tiles (`ground_tone`, flowers/ferns in `_fill_ground`) do not follow the slope.
