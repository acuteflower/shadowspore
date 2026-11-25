# Shadowspore — Project Rules

2D pixel-art top-down (3/4) action-RPG (exploration, combat, night-survival, base-building, farming, dungeons) in **Godot 4.7** (GDScript), 1–4 players.
Architecture: **Shadowspore 2.0** zone-world (`ZoneWorld`, continent `ALTMARK`, start zone `WINDKAP`, 4-level `AtlasView`, `PocketSpace`, `SaveGame.VERSION = 2`).
For full system details, see [CLAUDE.md](CLAUDE.md).

## Hard Rules
- **Strict static typing everywhere** (`gdscript/warnings/untyped_declaration=2` in `project.godot`). Type every variable, parameter, and return value.
- **Multiplayer-first, host-authoritative:** Singleplayer = local ENet host with 1 player (`NetworkManager.host_singleplayer()`). State changes go through `@rpc` and run on the server (`if not multiplayer.is_server(): return`). Dynamic entities use `MultiplayerSpawner` and `MultiplayerSynchronizer`.
- **Input only via `InputManager`** (autoload) and defined Input Actions (`move_left/right/up/down`, `sprint`, `shadow_step`, `blink`, `sneak`, `interact`, `action_primary`, `action_secondary`, `inventory`, `map`, `dungeons`, `skills`, `progress`, `quest_journal`, `InputManager.aim_vector()`, etc.). Never call `Input.is_key_pressed` in entities.
- **Data-driven:** Static game data lives in `res://data/*.json` (via `DataRegistry.table()`) and nested world data in `res://data/world/**` (via `DataRegistry.json()`).
- **Composition:** Keep `.tscn` scenes flat and compose entities from small component nodes in `src/components/` (`HealthComponent`, `HitboxComponent`, `HurtboxComponent`, `VelocityComponent`, `InventoryComponent`, `LocomotionComponent`, `SwimComponent`, `FinisherComponent`, `ZeroGComponent`, etc.).
- **Rendering & Coordinates:** `640x360` base viewport, `16x16` tiles, nearest filtering, `canvas_items` + `expand` stretch. World entities use `y_sort_enabled = true` with pivot at bottom-center (feet).
- **Lighting & Unlit:** Anything that must stay bright at night (texts, bars, warning zones, loot, coins, glowing parts) uses `Unlit.material()` or `render_mode unshaded`. Point lights use `NightLight` / `LightTexture.apply()`.

## Multithreading (`Jobs` Autoload)
- Use `Jobs.run(work, on_done, ...)` for heavy background work (`on_done` runs on the main thread).
- Inside worker functions: read only immutable/locked data; **never** add nodes to the scene tree, call `get_tree()`, emit tree signals, or write shared dictionaries/arrays. Preload scenes/scripts on the main thread via `Jobs.warm()`.

## Physics Layers
`1` world · `2` player · `3` enemy · `4` hitbox · `5` hurtbox (enemies, dummies) · `6` player_hurtbox

## Project Layout
- `src/autoload/` (`EventBus`, `DataRegistry`, `Jobs`, `NetworkManager`, `TimeManager`, `InputManager`, `Terrain`, `GameCursor`, `Quality`, `CloudSession`, `Chat`, `GameGuard`)
- `src/world/v2/` (`ZoneWorld`, `ZoneDirector`, `ZoneStage`, `ZoneCoop`, `ZoneMood`, `ZoneBackdrop`, `ZoneVeil`, `Landscape`, `WindkapProps`)
- `src/world/` (`Atlas`, `PocketSpace`, `dungeons/`, `mine/`, weather/daylight/shadows, living nature, interiors, puzzles, reusable ALTMARK region modules)
- `src/water/`, `src/components/`, `src/fx/`, `src/net/`, `src/fishing/`
- `src/entities/{player,enemies,npcs,props,drops,magic,puzzles,wildlife,wonders}/`
- `src/systems/`, `src/town/`, `src/ui/`
- `assets/`, `data/`, `data/world/`, `docs/`, `tools/` (Python art/audio/world-bake pipelines & `test_*.tscn` / `preview_*.tscn`)

## Art & Verification
- Before creating or modifying art, load the `shadowspore-pixel-art` skill and follow `docs/design_guide.md`.
- Keep raw art/audio/doc sources behind `.gdignore` (`docs/`, `tools/art_sources/`, `tools/sfx_raw/`, `assets/ui/sources/`).
- For new or revised art, delegate art-only work to a dedicated subagent when requested by project conventions; keep gameplay, integration, and verification in the primary agent.
- After code changes, load the `shadowspore-verify` skill to run headless checks, Python atlas/zone validators, and relevant `tools/test_*.tscn` scenes.
